class_name AccountStore
extends RefCounted
## Contas, senhas (PBKDF2) e sessões por token. Só o SHA-256 do token vai para o banco.
##
## Duas formas de usar:
## - Síncrona (`register`/`login`): deriva a senha na thread que chamou. Serve aos testes e a ferramentas.
## - Em fases (o AuthHttp): `prepare_register`/`prepare_login` validam, aplicam os limites e leem o banco na
##   thread principal e devolvem {"done": resultado} (acabou sem derivar) ou {"job": {...}}. A derivação
##   `derive_job(job)` é pura (sem banco nem estado) e roda numa thread do WorkerThreadPool; a chave volta
##   para `finish(job, chave)`, de novo na thread principal, que grava no banco. O banco (godot-sqlite) e os
##   mapas de limite só são tocados na thread principal.
##
## Limites por IP (memória; zeram ao reiniciar o servidor):
## - cadastro: REGISTER_MAX por REGISTER_WINDOW s (contam os que chegariam a derivar: nome e senha válidos e
##   nome livre), para não criar contas sem limite;
## - login: LOGIN_MAX tentativas por LOGIN_WINDOW s, certas ou erradas;
## - falhas de login: MAX_FAILS por FAIL_WINDOW s, por nome e por IP.
## IP vazio ("") desliga os limites de cadastro e de tentativas por IP (chamadas locais, testes).

const SESSION_SECS := 86400
const MAX_PASS_BYTES := 128
const MAX_FAILS := 5
const FAIL_WINDOW := 300.0
const REGISTER_MAX := 3
const REGISTER_WINDOW := 3600.0
const LOGIN_MAX := 10
const LOGIN_WINDOW := 60.0

var db: Db
var admin_users: PackedStringArray
var iterations := 100000  ## os testes baixam isso; em produção fica o padrão
var clock: Callable = func(): return Time.get_unix_time_from_system()  ## injetável para os testes
var _fails := {}      ## "n:nome" / "i:ip" -> Array de instantes das falhas de login
var _logins := {}     ## ip -> Array de instantes das tentativas de login
var _registers := {}  ## ip -> Array de instantes dos cadastros


func _init(p_db: Db, p_admin_users: PackedStringArray = PackedStringArray()) -> void:
	db = p_db
	admin_users = p_admin_users


# ================================================================ síncrono
func register(username: String, password: String, ip := "") -> Dictionary:
	var p := prepare_register(username, password, ip)
	return p["done"] if p.has("done") else finish(p["job"], derive_job(p["job"]))


func login(username: String, password: String, ip: String) -> Dictionary:
	var p := prepare_login(username, password, ip)
	return p["done"] if p.has("done") else finish(p["job"], derive_job(p["job"]))


# ================================================================ em fases
## Thread principal. {"done": resultado} ou {"job": dados para derive_job/finish}.
func prepare_register(username: String, password: String, ip := "") -> Dictionary:
	var re := RegEx.create_from_string("^[A-Za-z0-9_]{3,16}\\z")
	if re.search(username) == null:
		return {"done": {"ok": false, "err": "nome_invalido"}}
	if password.length() < 8:
		return {"done": {"ok": false, "err": "senha_curta"}}
	if password.to_utf8_buffer().size() > MAX_PASS_BYTES:
		return {"done": {"ok": false, "err": "senha_longa"}}
	var now := float(clock.call())
	if ip != "" and _count(_registers, ip, now, REGISTER_WINDOW) >= REGISTER_MAX:
		return {"done": {"ok": false, "err": "muitas_tentativas"}}
	# nome já em uso: responde sem gastar a derivação (o INSERT do finish ainda confere)
	if not db.query("SELECT id FROM accounts WHERE username = ?", [username]).is_empty():
		return {"done": {"ok": false, "err": "nome_em_uso"}}
	if ip != "":
		_hit(_registers, ip, now)
	return {"job": {"kind": "register", "username": username, "password": password,
		"salt": Password.new_salt(), "iterations": iterations}}


## Thread principal. {"done": resultado} ou {"job": dados para derive_job/finish}.
func prepare_login(username: String, password: String, ip: String) -> Dictionary:
	var now := float(clock.call())
	if _count(_fails, "n:" + username.to_lower(), now, FAIL_WINDOW) >= MAX_FAILS \
			or _count(_fails, "i:" + ip, now, FAIL_WINDOW) >= MAX_FAILS:
		return {"done": {"ok": false, "err": "muitas_tentativas"}}
	if ip != "":
		if _count(_logins, ip, now, LOGIN_WINDOW) >= LOGIN_MAX:
			return {"done": {"ok": false, "err": "muitas_tentativas"}}
		_hit(_logins, ip, now)
	if password.is_empty() or password.to_utf8_buffer().size() > MAX_PASS_BYTES:
		# vazia ou longa demais: não deriva; conta como falha
		_fail_login(username, ip, now)
		return {"done": {"ok": false, "err": "credenciais"}}
	var rows := db.query("SELECT id, username, pass_hash, pass_salt FROM accounts WHERE username = ?", [username])
	var job := {"kind": "login", "username": username, "password": password, "ip": ip, "iterations": iterations}
	if rows.is_empty():
		# deriva do mesmo jeito (sal qualquer) para não revelar pelo tempo se o nome existe
		job["salt"] = Password.new_salt()
		job["expected"] = PackedByteArray()
	else:
		job["salt"] = String(rows[0]["pass_salt"]).hex_decode()
		job["expected"] = String(rows[0]["pass_hash"]).hex_decode()
		job["id"] = int(rows[0]["id"])
		job["name"] = String(rows[0]["username"])
	return {"job": job}


## Pura (qualquer thread): a chave PBKDF2 do pedido.
static func derive_job(job: Dictionary) -> PackedByteArray:
	return Password.derive(str(job["password"]), job["salt"], int(job["iterations"]))


## Thread principal: conclui o pedido com a chave derivada.
func finish(job: Dictionary, key: PackedByteArray) -> Dictionary:
	var now := float(clock.call())
	if job["kind"] == "register":
		var salt: PackedByteArray = job["salt"]
		if not db.exec("INSERT INTO accounts(username, pass_hash, pass_salt, created_at) VALUES(?,?,?,?)",
				[job["username"], key.hex_encode(), salt.hex_encode(), int(now)]):
			return {"ok": false, "err": "nome_em_uso"}
		return {"ok": true, "id": db.last_id()}
	var expected: PackedByteArray = job["expected"]
	if expected.is_empty() or not Password.constant_eq(key, expected):
		_fail_login(str(job["username"]), str(job["ip"]), now)
		return {"ok": false, "err": "credenciais"}
	var id := int(job["id"])
	var name := str(job["name"])
	var token := Crypto.new().generate_random_bytes(32).hex_encode()
	var expires := int(now) + SESSION_SECS
	if not db.exec("INSERT INTO sessions(token, account_id, expires_at) VALUES(?,?,?)", [token.sha256_text(), id, expires]):
		return {"ok": false, "err": "credenciais"}
	db.exec("UPDATE accounts SET last_login = ? WHERE id = ?", [int(now), id])
	db.exec("DELETE FROM sessions WHERE expires_at <= ?", [int(now)])
	return {"ok": true, "id": id, "name": name, "token": token, "expires": expires, "is_admin": _is_admin(name)}


## Tira dos mapas de limite as chaves sem instantes dentro da janela (o AuthHttp chama de tempos em tempos).
## Devolve quantas chaves sobraram (os testes conferem que os mapas não crescem sem fim).
func prune() -> int:
	var now := float(clock.call())
	return _prune(_fails, now, FAIL_WINDOW) + _prune(_logins, now, LOGIN_WINDOW) \
		+ _prune(_registers, now, REGISTER_WINDOW)


func resolve_token(token: String) -> Dictionary:
	if token.is_empty():
		return {}
	var rows := db.query("SELECT a.id AS id, a.username AS name FROM sessions s JOIN accounts a ON a.id = s.account_id WHERE s.token = ? AND s.expires_at > ?",
			[token.sha256_text(), int(clock.call())])
	if rows.is_empty():
		return {}
	var name := String(rows[0]["name"])
	return {"id": int(rows[0]["id"]), "name": name, "is_admin": _is_admin(name)}


## Nomes de admin_users que ainda não têm conta (o servidor avisa na partida).
func missing_admins() -> PackedStringArray:
	var out := PackedStringArray()
	for a in admin_users:
		if db.query("SELECT id FROM accounts WHERE username = ?", [a]).is_empty():
			out.append(a)
	return out


func _is_admin(name: String) -> bool:
	for a in admin_users:
		if a.to_lower() == name.to_lower():
			return true
	return false


func _fail_login(username: String, ip: String, now: float) -> void:
	_hit(_fails, "n:" + username.to_lower(), now)
	_hit(_fails, "i:" + ip, now)


## Quantos instantes de `key` caem na janela (e descarta os velhos; chave vazia sai do mapa).
static func _count(map: Dictionary, key: String, now: float, window: float) -> int:
	var arr: Array = map.get(key, [])
	arr = arr.filter(func(t): return now - t < window)
	if arr.is_empty():
		map.erase(key)
	else:
		map[key] = arr
	return arr.size()


static func _hit(map: Dictionary, key: String, now: float) -> void:
	var arr: Array = map.get(key, [])
	arr.append(now)
	map[key] = arr


static func _prune(map: Dictionary, now: float, window: float) -> int:
	for key in map.keys():
		_count(map, key, now, window)
	return map.size()
