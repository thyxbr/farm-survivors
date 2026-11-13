class_name AccountStore
extends RefCounted
## Contas, senhas (PBKDF2) e sessões por token. Só o SHA-256 do token vai para o banco.

const SESSION_SECS := 86400
const MAX_FAILS := 5
const FAIL_WINDOW := 300.0

var db: Db
var admin_users: PackedStringArray
var iterations := 100000  ## os testes baixam isso; em produção fica o padrão
var clock: Callable = func(): return Time.get_unix_time_from_system()  ## injetável para os testes
var _fails := {}  ## "n:nome" / "i:ip" -> Array de instantes das falhas (memória; zera ao reiniciar)


func _init(p_db: Db, p_admin_users: PackedStringArray = PackedStringArray()) -> void:
	db = p_db
	admin_users = p_admin_users


func register(username: String, password: String) -> Dictionary:
	var re := RegEx.create_from_string("^[A-Za-z0-9_]{3,16}$")
	if re.search(username) == null:
		return {"ok": false, "err": "nome_invalido"}
	if password.length() < 8:
		return {"ok": false, "err": "senha_curta"}
	var salt := Password.new_salt()
	var h := Password.derive(password, salt, iterations)
	if not db.exec("INSERT INTO accounts(username, pass_hash, pass_salt, created_at) VALUES(?,?,?,?)",
			[username, h.hex_encode(), salt.hex_encode(), int(clock.call())]):
		return {"ok": false, "err": "nome_em_uso"}
	return {"ok": true, "id": db.last_id()}


func login(username: String, password: String, ip: String) -> Dictionary:
	var now := float(clock.call())
	var kn := "n:" + username.to_lower()
	var ki := "i:" + ip
	if _count(kn, now) >= MAX_FAILS or _count(ki, now) >= MAX_FAILS:
		return {"ok": false, "err": "muitas_tentativas"}
	var rows := db.query("SELECT id, username, pass_hash, pass_salt FROM accounts WHERE username = ?", [username])
	var ok := false
	if rows.is_empty():
		# gasta o mesmo tempo para não revelar se o nome existe
		Password.derive(password, Password.new_salt(), iterations)
	else:
		ok = Password.matches(password, String(rows[0]["pass_salt"]).hex_decode(), String(rows[0]["pass_hash"]).hex_decode(), iterations)
	if not ok:
		_fail(kn, now)
		_fail(ki, now)
		return {"ok": false, "err": "credenciais"}
	var id := int(rows[0]["id"])
	var name := String(rows[0]["username"])
	var token := Crypto.new().generate_random_bytes(32).hex_encode()
	var expires := int(now) + SESSION_SECS
	if not db.exec("INSERT INTO sessions(token, account_id, expires_at) VALUES(?,?,?)", [token.sha256_text(), id, expires]):
		return {"ok": false, "err": "credenciais"}
	db.exec("UPDATE accounts SET last_login = ? WHERE id = ?", [int(now), id])
	db.exec("DELETE FROM sessions WHERE expires_at <= ?", [int(now)])
	return {"ok": true, "id": id, "name": name, "token": token, "expires": expires, "is_admin": _is_admin(name)}


func resolve_token(token: String) -> Dictionary:
	if token.is_empty():
		return {}
	var rows := db.query("SELECT a.id AS id, a.username AS name FROM sessions s JOIN accounts a ON a.id = s.account_id WHERE s.token = ? AND s.expires_at > ?",
			[token.sha256_text(), int(clock.call())])
	if rows.is_empty():
		return {}
	var name := String(rows[0]["name"])
	return {"id": int(rows[0]["id"]), "name": name, "is_admin": _is_admin(name)}


func _is_admin(name: String) -> bool:
	for a in admin_users:
		if a.to_lower() == name.to_lower():
			return true
	return false


func _count(key: String, now: float) -> int:
	var arr: Array = _fails.get(key, [])
	arr = arr.filter(func(t): return now - t < FAIL_WINDOW)
	if arr.is_empty():
		_fails.erase(key)
	else:
		_fails[key] = arr
	return arr.size()


func _fail(key: String, now: float) -> void:
	var arr: Array = _fails.get(key, [])
	arr.append(now)
	_fails[key] = arr
