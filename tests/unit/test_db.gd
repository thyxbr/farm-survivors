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
	T.eq(Migrations.apply(db), 1, "banco novo vai para a versão 1")
	var nomes := []
	for r in db.query("SELECT name FROM sqlite_master WHERE type='table'"):
		nomes.append(r["name"])
	for t in TABELAS:
		T.ok(nomes.has(t), "tabela %s existe" % t)
	db.close()


func test_migrate_idempotent() -> void:
	var db := _fresh()
	T.eq(Migrations.apply(db), 1, "primeira vez")
	T.eq(Migrations.apply(db), 1, "segunda vez, mesma versão")
	T.eq(db.query("SELECT COUNT(*) AS n FROM schema_version")[0]["n"], 1, "uma linha de versão só")
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
