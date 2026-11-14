class_name CharStore
extends RefCounted
## Onde o CharacterService guarda os personagens. As regras (CharRules) e o registro da economia são os
## mesmos em qualquer armazenamento; só muda o meio:
## - SqliteCharStore: servidor dedicado, sobre o Db (SQLite; esquema e migrações em Migrations).
## - FileCharStore: solo offline, um JSON por personagem em user:// (o cliente Windows não leva o SQLite).
##
## Linha da economia (append_economy / save_char): {"at": int, "account_id": int, "kind": String,
## "amount": int, "item_id": String ou null (null = ouro), "source": String, "detail": String JSON ou null}.

## Mensagem da última operação que falhou ("" se deu certo).
var last_error := ""


## Personagem salvo (formato de CharState.to_dict, mais "updated_at" em segundos Unix) ou null se não existe.
func load_char(_account_id: int) -> Variant:
	return null


## Grava o personagem (`state` = CharState.to_dict) e as linhas da economia `rows` numa escrita só:
## ou tudo fica gravado, ou o personagem salvo continua o anterior. `at` vira o updated_at.
func save_char(_account_id: int, _state: Dictionary, _rows: Array, _at: int) -> bool:
	last_error = "não implementado"
	return false


## Acrescenta linhas da economia sem mexer no personagem (resumo de partida).
func append_economy(_rows: Array) -> bool:
	last_error = "não implementado"
	return false


## Apaga o personagem ("Novo jogo" do solo). true se não existe mais.
func delete_char(_account_id: int) -> bool:
	last_error = "não implementado"
	return false


func close() -> void:
	pass


## Monta uma linha da economia.
static func row(at: int, account_id: int, kind: String, amount: int, item_id, source: String, detail = null) -> Dictionary:
	return {"at": at, "account_id": account_id, "kind": kind, "amount": amount, "item_id": item_id,
		"source": source, "detail": detail}
