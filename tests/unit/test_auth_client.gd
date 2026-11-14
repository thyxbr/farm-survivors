extends RefCounted
## Auth (cliente): endereço da API de login e mensagens de erro. Só as funções estáticas (sem rede).

const AUTH := preload("res://scripts/autoload/auth.gd")


func test_ip_literal_uses_http_8080() -> void:
	T.eq(AUTH.url_for("127.0.0.1", ""), "http://127.0.0.1:8080", "IP sem porta")
	T.eq(AUTH.url_for("192.168.0.10:7790", ""), "http://192.168.0.10:8080", "porta do endereço é só do UDP")
	T.eq(AUTH.url_for("  localhost:7777 ", ""), "http://localhost:8080", "localhost")


func test_domain_uses_https() -> void:
	T.eq(AUTH.url_for("jogo.exemplo.com", ""), "https://jogo.exemplo.com", "domínio")
	T.eq(AUTH.url_for("jogo.exemplo.com:7777", ""), "https://jogo.exemplo.com", "domínio com porta UDP")


func test_override_wins() -> void:
	T.eq(AUTH.url_for("jogo.exemplo.com", "http://127.0.0.1:8790"), "http://127.0.0.1:8790", "--auth-url")
	T.eq(AUTH.url_for("127.0.0.1", "http://127.0.0.1:8790/"), "http://127.0.0.1:8790", "sem barra no fim")


func test_messages_in_portuguese() -> void:
	for err in ["nome_invalido", "senha_curta", "senha_longa", "nome_em_uso", "credenciais", "muitas_tentativas",
			"sem_conexao", "json_invalido"]:
		var m: String = AUTH.message(err)
		T.ok(m != "" and m != err, "mensagem para %s" % err)
	T.ok(AUTH.message("xyz").contains("xyz"), "erro desconhecido mostra o código")
