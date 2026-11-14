extends Node
## Cliente: cadastro e login na API HTTP do servidor (scripts/server/http/auth_http.gd).
##
## O login devolve um token de sessão; o Network entra no ENet com ele (em vez de um nome digitado).
## Endereço da API: `--auth-url=` tem prioridade; IP literal ou `localhost` → http://host:8080 (servidor
## local, sem HTTPS); domínio → https://host (proxy HTTPS do Easypanel). A porta digitada no endereço é a
## do UDP do jogo e não vale para o HTTP.
## A senha nunca é guardada: só o token fica na memória enquanto o jogo está aberto.

const LOCAL_HTTP_PORT := 8080
const TIMEOUT := 10.0
const MESSAGES := {
	"nome_invalido": "Nome inválido: use de 3 a 16 letras, números ou _ (sem espaços nem acentos).",
	"senha_curta": "Senha curta demais: use pelo menos 8 caracteres.",
	"senha_longa": "Senha longa demais.",
	"nome_em_uso": "Esse nome já tem conta. Escolha outro ou entre com a sua senha.",
	"credenciais": "Usuário ou senha incorretos.",
	"muitas_tentativas": "Muitas tentativas erradas. Espere alguns minutos e tente de novo.",
	"sem_conexao": "Não foi possível falar com o servidor de login. Confira o endereço e a sua internet.",
	"json_invalido": "O servidor não entendeu o pedido. Atualize o jogo.",
	"resposta_invalida": "Resposta inesperada do servidor de login.",
	"pedido_invalido": "O servidor não entendeu o pedido. Atualize o jogo.",
	"nao_encontrado": "Esse servidor não tem login. Confira o endereço ou atualize o jogo.",
}

## --auth-url=URL (testes e servidores fora do padrão).
var auth_url := ""
## Sessão atual (depois de um login ok).
var token := ""
var account_name := ""
var is_admin := false
var expires := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--auth-url="):
			auth_url = a.substr(11)


## Endereço base da API para o endereço do jogo ("host" ou "host:porta").
func base_url(address: String) -> String:
	return url_for(address, auth_url)


static func url_for(address: String, override: String) -> String:
	if override.strip_edges() != "":
		return override.strip_edges().trim_suffix("/")
	var host := address.strip_edges()
	if host.count(":") == 1:
		host = host.get_slice(":", 0)
	if host == "localhost" or host.is_valid_ip_address():
		return "http://%s:%d" % [host, LOCAL_HTTP_PORT]
	return "https://" + host


## Texto em português para um código de erro da API (ou da rede).
static func message(err: String) -> String:
	return MESSAGES.get(err, "Erro no login (%s)." % err)


## Cria a conta. {ok: true, id} ou {ok: false, err, msg}.
func register(address: String, user: String, password: String) -> Dictionary:
	return await _request(base_url(address) + "/auth/register", HTTPClient.METHOD_POST, {"user": user, "pass": password})


## Entra na conta e guarda o token. {ok: true, token, expires, name, is_admin} ou {ok: false, err, msg}.
func login(address: String, user: String, password: String) -> Dictionary:
	var r := await _request(base_url(address) + "/auth/login", HTTPClient.METHOD_POST, {"user": user, "pass": password})
	if r.ok:
		if str(r.get("token", "")) == "":
			return _error("resposta_invalida")
		token = str(r.token)
		account_name = str(r.get("name", user))
		is_admin = bool(r.get("is_admin", false))
		expires = int(r.get("expires", 0))
	return r


## Versão do servidor (GET /health). {ok: true, version} ou {ok: false, err, msg}.
func health(address: String) -> Dictionary:
	return await _request(base_url(address) + "/health", HTTPClient.METHOD_GET, {})


func logout() -> void:
	token = ""
	account_name = ""
	is_admin = false
	expires = 0


func _error(err: String) -> Dictionary:
	return {"ok": false, "err": err, "msg": message(err)}


func _request(url: String, method: int, body: Dictionary) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT
	add_child(req)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var data := JSON.stringify(body) if method == HTTPClient.METHOD_POST else ""
	if req.request(url, headers, method, data) != OK:
		req.queue_free()
		return _error("sem_conexao")
	var res: Array = await req.request_completed   # [result, código, cabeçalhos, corpo]
	req.queue_free()
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS:
		return _error("sem_conexao")
	var code := int(res[1])
	var parsed = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return _error("resposta_invalida")
	if code >= 200 and code < 300:
		parsed["ok"] = true
		return parsed
	return _error(str(parsed.get("err", "resposta_invalida")))
