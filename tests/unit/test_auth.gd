extends RefCounted
## Password + AccountStore + provedores: SQLite de verdade em user://, sem autoloads.

const PATH := "user://test_auth.db"
const ITER := 1000  # só nos testes; o AccountStore usa 100000 por padrão

var _now := 1000.0


func _store(admins := PackedStringArray()) -> AccountStore:
	Db.remove_files(PATH)
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


func test_name_trailing_chars() -> void:
	var s := _store()
	T.eq(s.register("Ana
", "senha1234")["err"], "nome_invalido", "newline no fim")
	T.eq(s.register("Ana ", "senha1234")["err"], "nome_invalido", "espaço no fim")


func test_password_too_long() -> void:
	var s := _store()
	var longa := "a".repeat(129)
	T.eq(s.register("Ana", longa)["err"], "senha_longa", "register recusa")
	T.ok(s.register("Ana", "a".repeat(128))["ok"], "128 bytes passa")
	T.eq(s.login("Ana", longa, "1.1.1.1")["err"], "credenciais", "login longo = credenciais")
	for i in 4:
		s.login("Ana", longa, "1.1.1.1")
	T.eq(s.login("Ana", "a".repeat(128), "1.1.1.1")["err"], "muitas_tentativas", "conta como falha")


func test_missing_admins() -> void:
	var s := _store(PackedStringArray(["Rique", "Fulano"]))
	s.register("rique", "senha1234")
	T.eq(s.missing_admins(), PackedStringArray(["Fulano"]), "só Fulano sem conta")


func test_pbkdf2_known_answer() -> void:
	var salt := "salt".to_utf8_buffer()
	T.eq(Password.derive("password", salt, 1).hex_encode(), "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b", "c=1")
	T.eq(Password.derive("password", salt, 4096).hex_encode(), "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a", "c=4096")


func test_register_limit_per_ip() -> void:
	var s := _store()
	for i in 3:
		T.ok(s.register("Conta%d" % i, "senha1234", "5.5.5.5")["ok"], "cadastro %d do IP" % (i + 1))
	T.eq(s.register("Conta9", "senha1234", "5.5.5.5")["err"], "muitas_tentativas", "4º cadastro na hora é recusado")
	T.ok(s.db.query("SELECT id FROM accounts WHERE username=?", ["Conta9"]).is_empty(), "e não cria a conta")
	T.ok(s.register("Outra", "senha1234", "6.6.6.6")["ok"], "outro IP passa")
	T.eq(s.register("Conta0", "senha1234", "7.7.7.7")["err"], "nome_em_uso", "nome em uso responde sem derivar")
	T.eq(s.register("x", "senha1234", "5.5.5.5")["err"], "nome_invalido", "validação antes do limite")
	_now += 3599.0
	T.eq(s.register("Conta9", "senha1234", "5.5.5.5")["err"], "muitas_tentativas", "ainda dentro da hora")
	_now += 2.0
	T.ok(s.register("Conta9", "senha1234", "5.5.5.5")["ok"], "libera depois de 1 h")
	var sem_ip := 0
	for i in 5:
		if s.register("SemIp%d" % i, "senha1234")["ok"]:
			sem_ip += 1
	T.eq(sem_ip, 5, "sem IP não limita")


func test_login_limit_per_ip_counts_successes() -> void:
	var s := _store()
	s.register("Ana", "senha1234")
	for i in 10:
		T.ok(s.login("Ana", "senha1234", "4.4.4.4")["ok"], "login certo %d" % (i + 1))
	T.eq(s.login("Ana", "senha1234", "4.4.4.4")["err"], "muitas_tentativas", "11º no minuto é recusado mesmo certo")
	T.ok(s.login("Ana", "senha1234", "3.3.3.3")["ok"], "outro IP passa")
	_now += 59.0
	T.eq(s.login("Ana", "senha1234", "4.4.4.4")["err"], "muitas_tentativas", "ainda dentro do minuto")
	_now += 2.0
	T.ok(s.login("Ana", "senha1234", "4.4.4.4")["ok"], "libera depois de 60 s")


func test_limit_maps_are_pruned() -> void:
	var s := _store()
	s.register("Ana", "senha1234")
	for i in 50:
		s.login("Ana%d" % i, "errada123", "10.0.%d.1" % i)   # falha por nome e por IP + tentativa por IP
		s.register("Novo%d" % i, "senha1234", "10.1.%d.1" % i)
	var keys := s.prune()
	T.eq(keys, 200, "chaves recentes ficam (50 nomes + 50 IPs de falha, 50 de login, 50 de cadastro)")
	_now += 301.0
	T.eq(s.prune(), 50, "falhas e tentativas saem depois das janelas; cadastros ficam 1 h")
	_now += 3300.0
	T.eq(s.prune(), 0, "depois de 1 h o mapa esvazia")


func test_phases_match_sync() -> void:
	var s := _store()
	var p := s.prepare_register("Bia", "senha1234", "2.2.2.2")
	T.ok(p.has("job"), "cadastro válido vira job")
	T.ok(s.finish(p["job"], AccountStore.derive_job(p["job"]))["ok"], "finish grava a conta")
	var lp := s.prepare_login("Bia", "senha1234", "2.2.2.2")
	T.ok(lp.has("job"), "login vira job")
	T.ok(s.finish(lp["job"], AccountStore.derive_job(lp["job"]))["ok"], "login em fases funciona")
	var bad := s.prepare_login("Bia", "errada123", "2.2.2.2")
	T.eq(s.finish(bad["job"], AccountStore.derive_job(bad["job"]))["err"], "credenciais", "senha errada em fases")
	var ghost := s.prepare_login("Ninguem", "senha1234", "2.2.2.2")
	T.ok(ghost.has("job"), "nome inexistente também deriva (tempo igual)")
	T.eq(s.finish(ghost["job"], AccountStore.derive_job(ghost["job"]))["err"], "credenciais", "e falha")
	T.ok(s.prepare_login("Bia", "", "2.2.2.2").has("done"), "senha vazia não deriva")
	# a derivação roda fora da thread principal (como no AuthHttp)
	var tp := s.prepare_login("Bia", "senha1234", "2.2.2.2")
	var out := {}
	var job: Dictionary = tp["job"]
	var task := WorkerThreadPool.add_task(func(): out["key"] = AccountStore.derive_job(job))
	WorkerThreadPool.wait_for_task_completion(task)
	T.ok(s.finish(job, out["key"])["ok"], "chave derivada no WorkerThreadPool vale")
