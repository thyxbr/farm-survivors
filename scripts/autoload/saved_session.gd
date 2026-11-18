class_name SavedSession
extends RefCounted
## "Manter conectado": a sessão do último login guardada no disco, para entrar sem digitar a senha.
##
## Guarda o token de sessão (30 dias, AccountStore.REMEMBER_SECS), o nome da conta e o endereço do servidor;
## a senha nunca passa por aqui. O arquivo é cifrado com a identificação deste computador: copiado para
## outro, não abre. Quem lê o arquivo neste computador ainda consegue o token, por isso "Sair da conta"
## (Auth.revoke) apaga as sessões no servidor.
## Script puro (sem autoloads): os testes passam outro caminho e outro relógio.

const PATH := "user://session.dat"
const SECTION := "session"


## Grava a sessão. `r` é a resposta do Auth.login ({token, expires, name, is_admin}).
static func save(address: String, r: Dictionary, path := PATH) -> bool:
	var token := str(r.get("token", ""))
	if token == "" or address.strip_edges() == "":
		return false
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "address", address.strip_edges())
	cfg.set_value(SECTION, "token", token)
	cfg.set_value(SECTION, "name", str(r.get("name", "")))
	cfg.set_value(SECTION, "is_admin", bool(r.get("is_admin", false)))
	cfg.set_value(SECTION, "expires", int(r.get("expires", 0)))
	return cfg.save_encrypted_pass(path, _key()) == OK


## A sessão guardada ({address, token, name, is_admin, expires}) ou {} se não há, venceu ou não abre.
## `now` = instante atual em segundos (padrão: o relógio do sistema).
static func load_from(path := PATH, now := -1.0) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var cfg := ConfigFile.new()
	if cfg.load_encrypted_pass(path, _key()) != OK:
		return {}
	var out := {
		"address": str(cfg.get_value(SECTION, "address", "")),
		"token": str(cfg.get_value(SECTION, "token", "")),
		"name": str(cfg.get_value(SECTION, "name", "")),
		"is_admin": bool(cfg.get_value(SECTION, "is_admin", false)),
		"expires": int(cfg.get_value(SECTION, "expires", 0)),
	}
	if now < 0.0:
		now = Time.get_unix_time_from_system()
	if out.token == "" or out.address == "" or float(out.expires) <= now:
		return {}
	return out


static func clear(path := PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _key() -> String:
	var id := OS.get_unique_id()
	return "ecos-de-valdoria:" + (id if id != "" else "sem-id")
