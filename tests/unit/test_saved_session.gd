extends RefCounted
## SavedSession ("Manter conectado"): grava o token cifrado, lê de volta, descarta vencido ou estragado.

const PATH := "user://test_saved_session.dat"
const LOGIN := {"ok": true, "token": "abc123", "expires": 5000, "name": "Ana_1", "is_admin": true}


func test_roundtrip() -> void:
	SavedSession.clear(PATH)
	T.ok(SavedSession.load_from(PATH, 1000.0).is_empty(), "sem arquivo: nada guardado")
	T.ok(SavedSession.save(" jogo.exemplo.com:7777 ", LOGIN, PATH), "grava")
	var s := SavedSession.load_from(PATH, 1000.0)
	T.eq(s.get("token", ""), "abc123", "token")
	T.eq(s.get("name", ""), "Ana_1", "nome da conta")
	T.eq(s.get("address", ""), "jogo.exemplo.com:7777", "endereço sem espaços")
	T.eq(s.get("is_admin", false), true, "admin")
	T.eq(s.get("expires", 0), 5000, "validade")
	SavedSession.clear(PATH)
	T.ok(SavedSession.load_from(PATH, 1000.0).is_empty(), "apagada")


func test_expired_is_ignored() -> void:
	SavedSession.save("127.0.0.1", LOGIN, PATH)
	T.ok(not SavedSession.load_from(PATH, 4999.0).is_empty(), "vale até vencer")
	T.ok(SavedSession.load_from(PATH, 5000.0).is_empty(), "vencida não entra")
	SavedSession.clear(PATH)


func test_not_plain_text_on_disk() -> void:
	SavedSession.save("127.0.0.1", LOGIN, PATH)
	var raw := FileAccess.get_file_as_bytes(PATH).get_string_from_ascii()
	T.ok(not raw.contains("abc123"), "o token não fica em texto puro")
	SavedSession.clear(PATH)


func test_empty_or_broken() -> void:
	T.ok(not SavedSession.save("127.0.0.1", {"token": ""}, PATH), "sem token não grava")
	T.ok(not SavedSession.save("", LOGIN, PATH), "sem endereço não grava")
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("isto não é uma sessão")
	f.close()
	T.ok(SavedSession.load_from(PATH, 1000.0).is_empty(), "arquivo estragado: nada guardado")
	SavedSession.clear(PATH)
