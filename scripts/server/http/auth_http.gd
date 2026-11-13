class_name AuthHttp
extends Node
## Servidor HTTP mínimo (JSON) para cadastro e login. Fica atrás do proxy HTTPS do Easypanel.
## Uma resposta por conexão; conexão sem pedido completo em TIMEOUT s é fechada.

const TIMEOUT := 5.0
const STATUS_TEXT := {200: "OK", 201: "Created", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found",
		409: "Conflict", 413: "Payload Too Large", 429: "Too Many Requests", 501: "Not Implemented"}
const ERR_STATUS := {"nome_invalido": 400, "senha_curta": 400, "senha_longa": 400, "nome_em_uso": 409,
		"credenciais": 401, "muitas_tentativas": 429}

var accounts: AccountStore
var _server := TCPServer.new()
var _conns: Array = []  ## [{"peer": StreamPeerTCP, "buf": PackedByteArray, "age": float}]


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
		_conns.append({"peer": _server.take_connection(), "buf": PackedByteArray(), "age": 0.0})
	for c in _conns.duplicate():
		if _step(c, delta):
			_conns.erase(c)


## true quando a conexão terminou (respondida, fechada ou expirada).
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
		if path == "/auth/register":
			var r := accounts.register(data["user"], data["pass"])
			_reply_result(peer, r, 201, {"id": r.get("id", 0)})
		else:
			var l := accounts.login(data["user"], data["pass"], HttpRequestParser.client_ip(peer.get_connected_host(), req["headers"]))
			_reply_result(peer, l, 200, {"token": l.get("token", ""), "expires": l.get("expires", 0),
					"name": l.get("name", ""), "is_admin": l.get("is_admin", false)})
	else:
		_reply(peer, 404, {"err": "nao_encontrado"})


func _reply_result(peer: StreamPeerTCP, r: Dictionary, status: int, ok_body: Dictionary) -> void:
	if r["ok"]:
		_reply(peer, status, ok_body)
	else:
		_reply(peer, ERR_STATUS.get(r["err"], 400), {"err": r["err"]})


func _reply(peer: StreamPeerTCP, status: int, body: Dictionary) -> void:
	var json := JSON.stringify(body).to_utf8_buffer()
	var head := "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [
			status, STATUS_TEXT.get(status, "Error"), json.size()]
	peer.put_data(head.to_utf8_buffer() + json)
	peer.disconnect_from_host()
