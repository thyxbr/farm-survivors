class_name HttpRequestParser
extends RefCounted
## Interpreta um pedido HTTP/1.1 simples (função pura, sem rede nem autoloads).
## parse(buf) -> {"complete":bool, "method", "path", "headers":{minúsculas}, "body":String}
##             ou {"error":400|413}. `complete:false` = ainda faltam bytes.

const MAX_BODY := 4096
const MAX_HEAD := 8192
## Conexões simultâneas aceitas pelo servidor HTTP (as demais são recusadas).
const MAX_CONNS := 64


static func parse(buf: PackedByteArray) -> Dictionary:
	var end := _find_head_end(buf)
	if end < 0:
		return {"error": 413} if buf.size() > MAX_HEAD else {"complete": false}
	if end > MAX_HEAD:
		return {"error": 413}
	var lines := buf.slice(0, end).get_string_from_utf8().split("\r\n")
	var parts := lines[0].split(" ")
	if parts.size() != 3 or not parts[2].begins_with("HTTP/") or parts[0].is_empty() or not parts[1].begins_with("/"):
		return {"error": 400}
	var headers := {}
	for i in range(1, lines.size()):
		var c := lines[i].find(":")
		if c <= 0:
			return {"error": 400}
		headers[lines[i].substr(0, c).strip_edges().to_lower()] = lines[i].substr(c + 1).strip_edges()
	var method := parts[0]
	var length := 0
	if headers.has("content-length"):
		var raw := String(headers["content-length"])
		if not raw.is_valid_int():
			return {"error": 400}
		length = raw.to_int()
		if length < 0:
			return {"error": 400}
		if length > MAX_BODY:
			return {"error": 413}
	elif method == "POST":
		return {"error": 400}
	var body_start := end + 4
	if buf.size() - body_start < length:
		return {"complete": false}
	return {
		"complete": true,
		"method": method,
		"path": parts[1],
		"headers": headers,
		"body": buf.slice(body_start, body_start + length).get_string_from_utf8(),
	}


## Posição do "\r\n\r\n" ou -1.
static func _find_head_end(buf: PackedByteArray) -> int:
	for i in range(0, buf.size() - 3):
		if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
			return i
	return -1


## Cabe mais uma conexão?
static func can_accept(open_count: int) -> bool:
	return open_count < MAX_CONNS


## Só vale reinterpretar o pedido quando chegaram bytes novos desde a última tentativa.
static func should_parse(last_size: int, size: int) -> bool:
	return size != last_size


## IP do jogador: o ÚLTIMO item de X-Forwarded-For (o que o proxy confiável acrescentou) só vale se o par TCP
## for privado/loopback; os itens anteriores podem ser forjados pelo cliente.
static func client_ip(peer_ip: String, headers: Dictionary) -> String:
	if headers.has("x-forwarded-for") and is_private_ip(peer_ip):
		var last := String(headers["x-forwarded-for"]).split(",")[-1].strip_edges()
		if not last.is_empty():
			return last
	return peer_ip


static func is_private_ip(ip: String) -> bool:
	if ip == "::1" or ip.begins_with("127.") or ip.begins_with("10.") or ip.begins_with("192.168.") or ip.to_lower().begins_with("fc") or ip.to_lower().begins_with("fd"):
		return true
	if ip.begins_with("::ffff:"):
		return is_private_ip(ip.substr(7))
	if ip.begins_with("172."):
		var second := ip.split(".")
		return second.size() > 1 and int(second[1]) >= 16 and int(second[1]) <= 31
	return false
