class_name Db
extends RefCounted
## Camada fina sobre o godot-sqlite: nenhuma cena fala SQL direto, tudo passa por aqui.
## Não depende de autoloads (roda em teste unitário com -s). Valores vão sempre por `args` (bindings).

var last_error := ""  # mensagem do último comando que falhou ("" se deu certo)
var _sql: SQLite = null
var _in_tx := false


## Abre (ou cria) o arquivo. Devolve null + push_error se a pasta não existe ou não aceita escrita:
## o servidor nunca deve cair num banco efêmero sem avisar.
static func open(path: String) -> Db:
	var dir := path.get_base_dir()
	if dir.is_empty():
		dir = "."  # caminho relativo simples ("x.db"): pasta atual
	if not DirAccess.dir_exists_absolute(dir):
		push_error("Db: pasta não existe: %s" % dir)
		return null
	# sonda de escrita: o SQLite abriria um arquivo somente-leitura sem reclamar
	var existed := FileAccess.file_exists(path)
	var probe := FileAccess.open(path, FileAccess.READ_WRITE if existed else FileAccess.WRITE)
	if probe == null:
		push_error("Db: sem permissão de escrita em %s (erro %d)" % [path, FileAccess.get_open_error()])
		return null
	probe.close()
	var sql := SQLite.new()
	sql.path = path
	sql.default_extension = ""  # senão o addon acrescenta ".db" e abriria outro arquivo que não o sondado acima
	sql.foreign_keys = true
	sql.verbosity_level = SQLite.QUIET
	if not sql.open_db():
		push_error("Db: não abriu %s: %s" % [path, sql.error_message])
		return null
	var db := Db.new()
	db._sql = sql
	return db


func close() -> void:
	if _sql != null:
		_sql.close_db()
		_sql = null


## SELECT (ou qualquer comando) devolvendo as linhas como dicionários. Falha devolve [] e preenche last_error.
func query(sql: String, args: Array = []) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if not _run(sql, args):
		return rows
	for r in _sql.query_result:
		rows.append(r)
	return rows


## INSERT/UPDATE/DELETE/DDL. false se falhou (ex.: UNIQUE violado); detalhe em last_error.
func exec(sql: String, args: Array = []) -> bool:
	return _run(sql, args)


func last_id() -> int:
	return _sql.last_insert_rowid if _sql != null else 0


## BEGIN ... COMMIT; ROLLBACK se `fn` devolver algo diferente de true ou o COMMIT falhar.
## Não aninha: uma transação dentro de outra devolve false sem rodar `fn`.
func transaction(fn: Callable) -> bool:
	if _sql == null or _in_tx:
		return false
	if not _run("BEGIN", []):
		return false
	_in_tx = true
	var ok = fn.call()
	_in_tx = false
	if ok == true and _run("COMMIT", []):
		return true
	_run("ROLLBACK", [])
	return false


func _run(sql: String, args: Array) -> bool:
	if _sql == null:
		last_error = "banco fechado"
		return false
	var ok: bool = _sql.query_with_bindings(sql, args) if not args.is_empty() else _sql.query(sql)
	last_error = "" if ok else _sql.error_message
	return ok
