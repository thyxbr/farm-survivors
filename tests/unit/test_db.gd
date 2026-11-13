extends RefCounted
## Db + Migrations: SQLite de verdade em user://, sem autoloads.

const PATH := "user://test_db.db"
const TABELAS := ["accounts", "sessions", "characters", "inventory", "passives", "base_buildings",
	"base_donations", "balance_tables", "balance_history", "runs", "run_players", "economy_log", "schema_version"]


func _fresh() -> Db:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	return Db.open(PATH)


func test_migrate_fresh() -> void:
	var db := _fresh()
	T.ok(db != null, "abriu o banco")
	T.eq(Migrations.apply(db), 3, "banco novo vai para a versão 3")
	var nomes := []
	for r in db.query("SELECT name FROM sqlite_master WHERE type='table'"):
		nomes.append(r["name"])
	for t in TABELAS:
		T.ok(nomes.has(t), "tabela %s existe" % t)
	db.close()


func test_migrate_idempotent() -> void:
	var db := _fresh()
	T.eq(Migrations.apply(db), 3, "primeira vez")
	T.eq(Migrations.apply(db), 3, "segunda vez, mesma versão")
	T.eq(db.query("SELECT COUNT(*) AS n FROM schema_version")[0]["n"], 3, "uma linha por versão")
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
