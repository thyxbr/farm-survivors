extends RefCounted
## Db + Migrations: SQLite de verdade em user://, sem autoloads.

const PATH := "user://test_db.db"
const TABELAS := ["accounts", "sessions", "characters", "inventory", "passives", "base_buildings",
	"base_donations", "balance_tables", "balance_history", "runs", "run_players", "economy_log", "schema_version"]


func _fresh() -> Db:
	Db.remove_files(PATH)
	return Db.open(PATH)


func test_migrate_fresh() -> void:
	var db := _fresh()
	T.ok(db != null, "abriu o banco")
	T.eq(Migrations.apply(db), Migrations.latest(), "banco novo vai para a versão mais nova")
	var nomes := []
	for r in db.query("SELECT name FROM sqlite_master WHERE type='table'"):
		nomes.append(r["name"])
	for t in TABELAS:
		T.ok(nomes.has(t), "tabela %s existe" % t)
	db.close()


func test_migrate_idempotent() -> void:
	var db := _fresh()
	T.eq(Migrations.apply(db), Migrations.latest(), "primeira vez")
	T.eq(Migrations.apply(db), Migrations.latest(), "segunda vez, mesma versão")
	T.eq(db.query("SELECT COUNT(*) AS n FROM schema_version")[0]["n"], Migrations.latest(), "uma linha por versão")
	db.close()


func test_username_nocase_unique() -> void:
	var db := _fresh()
	Migrations.apply(db)
	T.ok(db.exec("INSERT INTO accounts(username, pass_hash, pass_salt, created_at) VALUES(?,?,?,?)", ["Ana", "h", "s", 1]), "insere Ana")
	T.ok(not db.exec("INSERT INTO accounts(username, pass_hash, pass_salt, created_at) VALUES(?,?,?,?)", ["ana", "h", "s", 1]), "ana duplica (NOCASE)")
	T.ok(db.last_id() > 0, "last_id")
	db.close()


func test_transaction_rollback() -> void:
	var db := _fresh()
	Migrations.apply(db)
	var ok := db.transaction(func():
		db.exec("INSERT INTO accounts(username, pass_hash, pass_salt, created_at) VALUES(?,?,?,?)", ["x", "h", "s", 1])
		return false)
	T.ok(not ok, "transaction devolve false")
	T.eq(db.query("SELECT * FROM accounts WHERE username=?", ["x"]).size(), 0, "linha sumiu no rollback")
	var ok2 := db.transaction(func():
		db.exec("INSERT INTO accounts(username, pass_hash, pass_salt, created_at) VALUES(?,?,?,?)", ["y", "h", "s", 1])
		return true)
	T.ok(ok2, "commit")
	T.eq(db.query("SELECT * FROM accounts WHERE username=?", ["y"]).size(), 1, "linha existe após commit")
	db.close()


func test_open_missing_dir() -> void:
	T.ok(Db.open("user://nao_existe/x.db") == null, "pasta inexistente devolve null")


## Cliente exportado (sem addons/godot-sqlite): a classe SQLite não existe. Db compila mesmo assim e
## open devolve null (com push_error), em vez de quebrar a compilação de todo script que cita Db.
func test_open_without_sqlite_class() -> void:
	var real := Db.sqlite_class
	T.ok(Db.available(), "a extensão está carregada no editor/servidor")
	Db.sqlite_class = "SQLiteQueNaoExiste"
	T.ok(not Db.available(), "classe ausente é detectada")
	T.ok(Db.open("user://test_db_sem_classe.db") == null, "sem a classe SQLite, open devolve null")
	Db.sqlite_class = real
	var db := Db.open("user://test_db_sem_classe.db")
	T.ok(db != null, "com a classe de volta, abre")
	if db != null:
		db.close()
	Db.remove_files("user://test_db_sem_classe.db")


func test_open_path_without_extension() -> void:
	# o addon acrescentaria ".db" por conta própria: o arquivo criado tem que ser exatamente o caminho pedido
	var p := "user://test_db_noext"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p + ".db"))
	var db := Db.open(p)
	T.ok(db != null, "abriu sem extensão")
	if db != null:
		T.ok(Migrations.apply(db) == Migrations.MIGRATIONS.size(), "migrou")
		db.close()
	T.ok(FileAccess.file_exists(p), "arquivo é exatamente o caminho pedido")
	T.ok(not FileAccess.file_exists(p + ".db"), "não criou <caminho>.db")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func test_open_unwritable_path() -> void:
	# no Windows não dá para tirar permissão de pasta; um diretório no lugar do arquivo também falha a abertura
	var d := "user://test_db_dir_as_file"
	DirAccess.make_dir_absolute(d)
	T.ok(Db.open(d) == null, "caminho que é diretório devolve null")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(d))


func test_open_bare_relative_path() -> void:
	var db := Db.open("test_db_rel.db")  # relativo ao diretório atual
	T.ok(db != null, "caminho relativo simples abre")
	if db != null:
		db.close()
	DirAccess.remove_absolute("test_db_rel.db")
	for suf in ["-wal", "-shm"]:
		DirAccess.remove_absolute("test_db_rel.db" + suf)


func test_failed_migration_is_detected() -> void:
	# tabela "accounts" já existe sem schema_version: a v1 (CREATE TABLE accounts) falha
	var db := _fresh()
	db.exec("CREATE TABLE accounts (x INTEGER)")
	T.eq(Migrations.apply(db), -1, "apply devolve -1")
	T.ok(not Migrations.ensure_latest(db), "ensure_latest recusa")
	db.close()


func test_newer_db_is_refused() -> void:
	var db := _fresh()
	T.ok(Migrations.ensure_latest(db), "banco novo fica na mais nova")
	T.ok(Migrations.ensure_latest(db), "idempotente")
	db.exec("INSERT INTO schema_version(version, applied_at) VALUES(?, 0)", [Migrations.latest() + 1])
	T.ok(not Migrations.ensure_latest(db), "banco de versão mais nova do jogo é recusado")
	db.close()


func test_wal_and_remove_files() -> void:
	var p := "user://test_db_wal.db"
	Db.remove_files(p)
	var db := Db.open(p)
	T.eq(str(db.query("PRAGMA journal_mode")[0].values()[0]).to_lower(), "wal", "journal em WAL")
	T.eq(int(db.query("PRAGMA busy_timeout")[0].values()[0]), 2000, "busy_timeout 2000")
	T.eq(int(db.query("PRAGMA synchronous")[0].values()[0]), 1, "synchronous NORMAL")
	T.ok(db.exec("CREATE TABLE t (x INTEGER)"), "grava")
	T.ok(FileAccess.file_exists(p + "-wal"), "arquivo -wal existe com o banco aberto")
	db.close()
	Db.remove_files(p)
	for suf in ["", "-wal", "-shm", "-journal"]:
		T.ok(not FileAccess.file_exists(p + suf), "apagou %s" % (p + suf))
