extends RefCounted
## Password + AccountStore + provedores: SQLite de verdade em user://, sem autoloads.

const PATH := "user://test_auth.db"
const ITER := 1000  # só nos testes; o AccountStore usa 100000 por padrão

var _now := 1000.0


func _store(admins := PackedStringArray()) -> AccountStore:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var db := Db.open(PATH)
	Migrations.apply(db)
	var s := AccountStore.new(db, admins)
	s.iterations = ITER
	_now = 1000.0
	s.clock = func(): return _now
	return s


func test_register_and_login() -> void:
	var s := _store()
	var r := s.register("Ana_1", "senha1234")
	T.ok(r["ok"], "registra")
	var l := s.login("ana_1", "senha1234", "1.1.1.1")
	T.ok(l["ok"], "loga (nome sem diferenciar maiúsculas)")
	T.eq(l["id"], r["id"], "mesmo id")
	T.eq(String(l["token"]).length(), 64, "token de 32 bytes em hex")
	T.eq(s.resolve_token(l["token"])["id"], r["id"], "token resolve para o mesmo id")
	T.eq(s.resolve_token(l["token"])["name"], "Ana_1", "nome cadastrado")
	T.ok(s.resolve_token("zz").is_empty(), "token inválido")
	T.ok(s.resolve_token("").is_empty(), "token vazio")


func test_validation() -> void:
	var s := _store()
	T.eq(s.register("ab", "senha1234")["err"], "nome_invalido", "curto")
	T.eq(s.register("a".repeat(17), "senha1234")["err"], "nome_invalido", "longo")
	T.eq(s.register("an a", "senha1234")["err"], "nome_invalido", "espaço")
	T.eq(s.register("João", "senha1234")["err"], "nome_invalido", "acento")
	T.eq(s.register("Ana", "1234567")["err"], "senha_curta", "senha curta")


func test_wrong_password() -> void:
	var s := _store()
	s.register("Ana", "senha1234")
	T.eq(s.login("Ana", "errada123", "ip")["err"], "credenciais", "senha errada")
	T.eq(s.login("Nao", "senha1234", "ip")["err"], "credenciais", "usuário inexistente")


func test_duplicate_name_case_insensitive() -> void:
	var s := _store()
	T.ok(s.register("Ana", "senha1234")["ok"], "primeira")
	T.eq(s.register("ana", "senha1234")["err"], "nome_em_uso", "ana duplica Ana")


func test_rate_limit() -> void:
	var s := _store()
	s.register("Ana", "senha1234")
	for i in 5:
		T.eq(s.login("Ana", "errada123", "1.1.1.1")["err"], "credenciais", "falha %d" % (i + 1))
	T.eq(s.login("Ana", "senha1234", "1.1.1.1")["err"], "muitas_tentativas", "6ª bloqueia mesmo com senha certa")
	_now += 301.0
	T.ok(s.login("Ana", "senha1234", "1.1.1.1")["ok"], "libera após 300 s")


func test_rate_limit_by_ip() -> void:
	var s := _store()
	s.register("Ana", "senha1234")
	for i in 5:
		s.login("nome%d" % i, "errada123", "9.9.9.9")
	T.eq(s.login("Ana", "senha1234", "9.9.9.9")["err"], "muitas_tentativas", "IP bloqueado")
	T.ok(s.login("Ana", "senha1234", "8.8.8.8")["ok"], "outro IP passa")


func test_hash_not_plain() -> void:
	var s := _store()
	s.register("Ana", "senha1234")
	var row := s.db.query("SELECT pass_hash, pass_salt FROM accounts WHERE username=?", ["Ana"])[0]
	T.ok(String(row["pass_hash"]) != "senha1234", "hash não é a senha")
	T.eq(String(row["pass_hash"]).hex_decode().size(), 32, "hash de 32 bytes")
	T.eq(String(row["pass_salt"]).hex_decode().size(), 16, "sal de 16 bytes")
	var salt := Password.new_salt()
	T.ok(Password.matches("abc", salt, Password.derive("abc", salt, ITER), ITER), "matches certo")
	T.ok(not Password.matches("abd", salt, Password.derive("abc", salt, ITER), ITER), "matches errado")
	var t0 := Time.get_ticks_msec()
	Password.derive("abc", salt)  # 100000 iterações
	T.ok(Time.get_ticks_msec() - t0 < 2000, "100k iterações em < 2 s (%d ms)" % (Time.get_ticks_msec() - t0))


func test_token_stored_hashed() -> void:
	var s := _store()
	s.register("Ana", "senha1234")
	var l := s.login("Ana", "senha1234", "ip")
	var rows := s.db.query("SELECT token FROM sessions")
	T.eq(rows.size(), 1, "uma sessão")
	T.ok(rows[0]["token"] != l["token"], "banco não guarda o token")
	T.eq(rows[0]["token"], String(l["token"]).sha256_text(), "guarda o SHA-256")


func test_admin_flag() -> void:
	var s := _store(PackedStringArray(["Rique"]))
	s.register("Rique", "senha1234")
	s.register("Ana", "senha1234")
	var l := s.login("Rique", "senha1234", "ip")
	T.ok(l["is_admin"], "admin no login")
	T.ok(s.resolve_token(l["token"])["is_admin"], "admin no token")
	T.ok(not s.login("Ana", "senha1234", "ip")["is_admin"], "Ana não é admin")


func test_expired_token() -> void:
	var s := _store()
	s.register("Ana", "senha1234")
	var l := s.login("Ana", "senha1234", "ip")
	T.ok(not s.resolve_token(l["token"]).is_empty(), "válido antes")
	s.db.exec("UPDATE sessions SET expires_at = ?", [int(_now) - 1])
	T.ok(s.resolve_token(l["token"]).is_empty(), "expirado devolve {}")


func test_password_provider() -> void:
	var s := _store()
	s.register("Ana", "senha1234")
	var p: AuthProvider = PasswordProvider.new(s)
	T.ok(p.verify({"username": "Ana", "password": "senha1234"}, "ip")["ok"], "provedor de senha")
	T.ok(not p.verify({}, "ip")["ok"], "credenciais vazias")


func test_steam_unsupported() -> void:
	var r := SteamProvider.new().verify({"ticket": "x"}, "ip")
	T.ok(not r["ok"], "steam falha")
	T.eq(r["err"], "não suportado", "mensagem")
