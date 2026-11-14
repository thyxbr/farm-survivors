class_name AuthHttp
extends Node
## Servidor HTTP mínimo (JSON) para cadastro e login. Fica atrás do proxy HTTPS do Easypanel.
## Uma resposta por conexão; conexão sem pedido completo em TIMEOUT s é fechada.
##
## A derivação da senha (PBKDF2, ~0,3 s) nunca roda na thread principal: o AccountStore prepara o pedido
## (validação, limites por IP, leitura do banco), a chave é derivada no WorkerThreadPool e o AccountStore
## conclui (grava no banco) quando ela fica pronta. No máximo DeriveQueue.MAX_RUNNING derivações ao mesmo tempo
## (DeriveQueue); as outras esperam na fila e a conexão fica aberta até a resposta. Fila cheia → 503.

const TIMEOUT := 5.0
## De quanto em quanto tempo limpa os mapas de limite por IP do AccountStore.
const PRUNE_EVERY := 30.0
const STATUS_TEXT := {200: "OK", 201: "Created", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found",
		409: "Conflict", 413: "Payload Too Large", 429: "Too Many Requests", 501: "Not Implemented",
		503: "Service Unavailable"}
const ERR_STATUS := {"nome_invalido": 400, "senha_curta": 400, "senha_longa": 400, "nome_em_uso": 409,
		"credenciais": 401, "muitas_tentativas": 429, "ocupado": 503}

var accounts: AccountStore
var _server := TCPServer.new()
var _conns: Array = []  ## [{"peer": StreamPeerTCP, "buf": PackedByteArray, "age": float}]
var _queue := DeriveQueue.new()
## Derivações em andamento: [{"task": id do WorkerThreadPool, "out": {"key"}, "peer", "job", "status"}]
var _running: Array = []
var _prune_t := PRUNE_EVERY


func start(port: int, p_accounts: AccountStore) -> Error:
	accounts = p_accounts
	var err := _server.listen(port)
	if err != OK:
		printerr("[http] não foi possível abrir a porta TCP %d (erro %d)" % [port, err])
	return err


func _process(delta: float) -> void:
	if not _server.is_listening():
		return
	while _server.is_connection_available():
		var p := _server.take_connection()
		if HttpRequestParser.can_accept(_conns.size()):
			_conns.append({"peer": p, "buf": PackedByteArray(), "age": 0.0, "parsed": -1})
		else:
			p.disconnect_from_host()  # lotado: recusa na hora
	for c in _conns.duplicate():
		if _step(c, delta):
			_conns.erase(c)
	_pump_derivations()
	_prune_t -= delta
	if _prune_t <= 0.0:
		_prune_t = PRUNE_EVERY
		accounts.prune()


## Conclui as derivações prontas (thread principal: banco + resposta) e começa as que couberem.
func _pump_derivations() -> void:
	for r in _running.duplicate():
		if not WorkerThreadPool.is_task_completed(r["task"]):
			continue
		WorkerThreadPool.wait_for_task_completion(r["task"])
		_running.erase(r)
		_queue.finished()
		var res := accounts.finish(r["job"], r["out"].get("key", PackedByteArray()))
		_reply_result(r["peer"], res, r["status"])
	for item in _queue.take_startable():
		var out := {}
		var job: Dictionary = item["job"]
		item["out"] = out
		item["task"] = WorkerThreadPool.add_task(func(): out["key"] = AccountStore.derive_job(job), false, "senha")
		_running.append(item)


## Quantas derivações estão rodando agora (o teste do limite confere que nunca passa de DeriveQueue.MAX_RUNNING).
func deriving_count() -> int:
	return _running.size()


func _exit_tree() -> void:
	# tarefas do WorkerThreadPool precisam ser esperadas antes de sair
	for r in _running:
		WorkerThreadPool.wait_for_task_completion(r["task"])
	_running.clear()


## true quando a conexão saiu da lista (respondida, fechada, expirada ou esperando a derivação da senha).
func _step(c: Dictionary, delta: float) -> bool:
	var peer: StreamPeerTCP = c["peer"]
	peer.poll()
	var st := peer.get_status()
	if st == StreamPeerTCP.STATUS_CONNECTING:
		c["age"] += delta
		return c["age"] > TIMEOUT
	if st != StreamPeerTCP.STATUS_CONNECTED:
		return true
	c["age"] += delta
	var n := peer.get_available_bytes()
	if n > 0:
		var got := peer.get_data(n)
		if got[0] == OK:
			c["buf"].append_array(got[1])
	if not HttpRequestParser.should_parse(c["parsed"], c["buf"].size()):
		if c["age"] > TIMEOUT:
			peer.disconnect_from_host()
			return true
		return false
	c["parsed"] = c["buf"].size()
	var req := HttpRequestParser.parse(c["buf"])
	if req.has("error"):
		_reply(peer, int(req["error"]), {"err": "pedido_invalido"})
		return true
	if req["complete"]:
		_handle(peer, req)
		return true
	if c["age"] > TIMEOUT:
		peer.disconnect_from_host()
		return true
	return false


func _handle(peer: StreamPeerTCP, req: Dictionary) -> void:
	var method: String = req["method"]
	var path := String(req["path"]).split("?")[0]
	if method == "GET" and path == "/health":
		_reply(peer, 200, {"version": Network.version()})
	elif method == "POST" and path == "/auth/steam":
		_reply(peer, 501, {"err": "nao_implementado"})
	elif method == "POST" and (path == "/auth/register" or path == "/auth/login"):
		var data = JSON.parse_string(req["body"])
		if typeof(data) != TYPE_DICTIONARY or typeof(data.get("user")) != TYPE_STRING or typeof(data.get("pass")) != TYPE_STRING:
			_reply(peer, 400, {"err": "json_invalido"})
			return
		var ip := HttpRequestParser.client_ip(peer.get_connected_host(), req["headers"])
		var reg := path == "/auth/register"
		var p: Dictionary
		if reg:
			p = accounts.prepare_register(data["user"], data["pass"], ip)
		else:
			p = accounts.prepare_login(data["user"], data["pass"], ip)
		var status := 201 if reg else 200
		if p.has("done"):
			_reply_result(peer, p["done"], status)
		elif not _queue.push({"peer": peer, "job": p["job"], "status": status}):
			_reply(peer, 503, {"err": "ocupado"})
	else:
		_reply(peer, 404, {"err": "nao_encontrado"})


## Resposta de um cadastro/login: o corpo de sucesso sai do próprio resultado.
func _reply_result(peer: StreamPeerTCP, r: Dictionary, status: int) -> void:
	if r["ok"]:
		if status == 201:
			_reply(peer, status, {"id": r.get("id", 0)})
		else:
			_reply(peer, status, {"token": r.get("token", ""), "expires": r.get("expires", 0),
					"name": r.get("name", ""), "is_admin": r.get("is_admin", false)})
	else:
		_reply(peer, ERR_STATUS.get(r["err"], 400), {"err": r["err"]})


func _reply(peer: StreamPeerTCP, status: int, body: Dictionary) -> void:
	var json := JSON.stringify(body).to_utf8_buffer()
	var head := "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [
			status, STATUS_TEXT.get(status, "Error"), json.size()]
	peer.put_data(head.to_utf8_buffer() + json)
	peer.disconnect_from_host()
