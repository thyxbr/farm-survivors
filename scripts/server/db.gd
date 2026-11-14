class_name Db
extends RefCounted
## Camada fina sobre o godot-sqlite: nenhuma cena fala SQL direto, tudo passa por aqui.
## Não depende de autoloads (roda em teste unitário com -s). Valores vão sempre por `args` (bindings).
##
## Só o servidor dedicado usa o SQLite: o cliente Windows é exportado SEM o addons/godot-sqlite (uma DLL
## sem assinatura é barrada pelo Smart App Control). Por isso nada aqui cita o tipo `SQLite` estaticamente
## (o script não compilaria sem a extensão e derrubaria todo script que cita `Db`): a classe é achada
## pelo ClassDB e as variáveis são sem tipo. Sem a extensão, `open` devolve null com push_error.

## Nome da classe da extensão. Os testes trocam por um nome inexistente para simular o cliente exportado.
static var sqlite_class := "SQLite"

var last_error := ""  # mensagem do último comando que falhou ("" se deu certo)
var _sql = null   # instância do SQLite (sem tipo: ver o topo)
var _in_tx := false


## Abre (ou cria) o arquivo. Devolve null + push_error se a pasta não existe ou não aceita escrita:
## o servidor nunca deve cair num banco efêmero sem avisar. Também null se a extensão SQLite não está
## carregada (cliente exportado, que não leva o addon).
static func open(path: String) -> Db:
	if not available():
		push_error("Db: a extensão SQLite (classe %s) não está carregada; o banco só existe no servidor dedicado" % sqlite_class)
		return null
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
	var sql = ClassDB.instantiate(sqlite_class)
	if sql == null:
		push_error("Db: não instanciou %s" % sqlite_class)
		return null
	sql.path = path
	sql.default_extension = ""  # senão o addon acrescenta ".db" e abriria outro arquivo que não o sondado acima
	sql.foreign_keys = true
	# SQLite.QUIET lido pelo ClassDB (escrever `SQLite.QUIET` exigiria a classe em tempo de compilação)
	sql.verbosity_level = ClassDB.class_get_integer_constant(sqlite_class, "QUIET")
	if not sql.open_db():
		push_error("Db: não abriu %s: %s" % [path, sql.error_message])
		return null
	var db := Db.new()
	db._sql = sql
	# WAL: leituras não esperam a escrita e o commit grava menos; synchronous=NORMAL é seguro com WAL (perde no
	# máximo a última transação numa queda de energia, nunca corrompe); busy_timeout espera um lock em vez de falhar
	for pragma in ["PRAGMA journal_mode=WAL", "PRAGMA synchronous=NORMAL", "PRAGMA busy_timeout=2000"]:
		if not db._run(pragma, []):
			push_warning("Db: %s falhou: %s" % [pragma, db.last_error])
	return db


## A extensão SQLite está carregada neste processo?
static func available() -> bool:
	return ClassDB.class_exists(sqlite_class)


## Apaga o arquivo do banco e os auxiliares do SQLite (-wal, -shm, -journal). O banco precisa estar fechado.
static func remove_files(path: String) -> void:
	for f in [path, path + "-wal", path + "-shm", path + "-journal"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


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
