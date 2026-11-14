extends RefCounted
## HttpRequestParser: função pura, sem rede nem autoloads.


func _buf(s: String) -> PackedByteArray:
	return s.to_utf8_buffer()


func test_complete_get() -> void:
	var r := HttpRequestParser.parse(_buf("GET /health HTTP/1.1\r\nHost: x\r\nX-Forwarded-For: 1.2.3.4, 10.0.0.1\r\n\r\n"))
	T.ok(r["complete"], "completo")
	T.eq(r["method"], "GET", "método")
	T.eq(r["path"], "/health", "caminho")
	T.eq(r["headers"]["x-forwarded-for"], "1.2.3.4, 10.0.0.1", "cabeçalho em minúsculas")
	T.eq(r["body"], "", "sem corpo")


func test_complete_post() -> void:
	var body := '{"user":"Ana","pass":"teste-1234"}'
	var r := HttpRequestParser.parse(_buf("POST /auth/login HTTP/1.1\r\nContent-Length: %d\r\n\r\n%s" % [body.length(), body]))
	T.ok(r["complete"], "completo")
	T.eq(r["method"], "POST", "método")
	T.eq(r["body"], body, "corpo")


func test_two_chunks() -> void:
	var body := "{}"
	var full := "POST /auth/login HTTP/1.1\r\nContent-Length: 2\r\n\r\n" + body
	var r1 := HttpRequestParser.parse(_buf(full.substr(0, 20)))
	T.eq(r1.get("complete", null), false, "1º pedaço incompleto")
	T.ok(not r1.has("error"), "sem erro")
	var r2 := HttpRequestParser.parse(_buf(full.substr(0, full.length() - 1)))
	T.eq(r2.get("complete", null), false, "cabeçalho ok, corpo faltando")
	var r3 := HttpRequestParser.parse(_buf(full))
	T.ok(r3["complete"], "completo no fim")
	T.eq(r3["body"], body, "corpo")


func test_body_too_large() -> void:
	var r := HttpRequestParser.parse(_buf("POST /x HTTP/1.1\r\nContent-Length: 4097\r\n\r\n"))
	T.eq(r.get("error", 0), 413, "corpo > 4096")
	var ok := HttpRequestParser.parse(_buf("POST /x HTTP/1.1\r\nContent-Length: 4096\r\n\r\n"))
	T.ok(not ok.has("error"), "4096 ainda vale")


func test_post_without_length() -> void:
	var r := HttpRequestParser.parse(_buf("POST /x HTTP/1.1\r\nHost: a\r\n\r\n{}"))
	T.eq(r.get("error", 0), 400, "POST sem Content-Length")


func test_malformed() -> void:
	T.eq(HttpRequestParser.parse(_buf("LIXO\r\n\r\n")).get("error", 0), 400, "linha de pedido inválida")
	T.eq(HttpRequestParser.parse(_buf("POST /x HTTP/1.1\r\nContent-Length: abc\r\n\r\n")).get("error", 0), 400, "length inválido")
	T.eq(HttpRequestParser.parse(_buf("A".repeat(9000))).get("error", 0), 413, "cabeçalho sem fim")


func test_client_ip() -> void:
	var xff := {"x-forwarded-for": "6.6.6.6, 9.9.9.9"}  # 6.6.6.6 forjado pelo cliente
	T.eq(HttpRequestParser.client_ip("10.0.0.2", xff), "9.9.9.9", "par privado: usa o último item do X-Forwarded-For")
	T.eq(HttpRequestParser.client_ip("172.18.0.3", xff), "9.9.9.9", "172.16/12")
	T.eq(HttpRequestParser.client_ip("127.0.0.1", xff), "9.9.9.9", "loopback")
	T.eq(HttpRequestParser.client_ip("8.8.8.8", xff), "8.8.8.8", "par público: ignora o cabeçalho")
	T.eq(HttpRequestParser.client_ip("172.32.0.1", xff), "172.32.0.1", "172.32 é público")
	T.eq(HttpRequestParser.client_ip("10.0.0.2", {}), "10.0.0.2", "sem cabeçalho")


func test_connection_limits() -> void:
	T.ok(HttpRequestParser.can_accept(63), "63 abertas: cabe mais uma")
	T.ok(not HttpRequestParser.can_accept(64), "64 abertas: recusa")
	T.ok(HttpRequestParser.should_parse(-1, 0), "primeira vez parseia")
	T.ok(not HttpRequestParser.should_parse(10, 10), "sem bytes novos não parseia")
	T.ok(HttpRequestParser.should_parse(10, 12), "bytes novos parseiam")
