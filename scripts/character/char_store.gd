class_name CharStore
extends RefCounted
## Onde o CharacterService guarda os personagens, a base compartilhada (doações) e o registro das partidas
## (runs, recordes). As regras (CharRules, BaseRules, RewardRules) e o registro da economia são os mesmos
## em qualquer armazenamento; só muda o meio:
## - SqliteCharStore: servidor dedicado, sobre o Db (SQLite; esquema e migrações em Migrations).
## - FileCharStore: solo offline, JSON em user:// (o cliente Windows não leva o SQLite): personagem, base
##   e partidas em arquivos ao lado um do outro.
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


## Base compartilhada gravada: {building_id: {"level": int, "fund": int}} (só as que já receberam doação).
func load_base() -> Dictionary:
	return {}


## Doação à base numa escrita só: o personagem (`state`, já debitado), o novo nível/fundo da construção, a
## doação no histórico e as linhas da economia `rows`. Ou tudo fica gravado, ou nada: nunca debita os
## Ecos sem creditar a base.
func save_donation(_account_id: int, _state: Dictionary, _building_id: String, _level: int, _fund: int,
		_amount: int, _rows: Array, _at: int) -> bool:
	last_error = "não implementado"
	return false


## Maiores doadores de uma construção: [{"name", "amount"}], soma por conta, do maior para o menor
## (empate: quem doou primeiro).
func top_donors(_building_id: String, _limit: int) -> Array:
	return []


## Abre o registro de uma partida (`accounts` = contas que começaram). Devolve o run_id (> 0) ou 0 se falhou.
func start_run(_mode: String, _accounts: Array, _at: int) -> int:
	last_error = "não implementado"
	return 0


## A conta já fechou sua parte nesta partida (finish_player é idempotente por run_id + conta)?
func run_player_done(_run_id: int, _account_id: int) -> bool:
	return false


## Fim da partida de um jogador numa escrita só: o personagem (`state`, já com os Ecos), a linha dele na
## partida (`entry` = {"reached", "ecos", "gold", "xp", "build"}; nenhuma se run_id <= 0) e as linhas da
## economia `rows`. Ou tudo fica gravado, ou nada.
func save_run_player(_account_id: int, _state: Dictionary, _run_id: int, _entry: Dictionary, _rows: Array,
		_at: int) -> bool:
	last_error = "não implementado"
	return false


## Encerra uma partida (vale para o recorde).
func close_run(_run_id: int, _reached: int, _result: Dictionary, _at: int) -> bool:
	last_error = "não implementado"
	return false


## Recorde de um modo: a partida encerrada que foi mais longe (empate: a mais antiga) e o nome de quem
## jogou, em ordem alfabética. {"reached": 0, "names": []} se não houver.
func best_run(_mode: String) -> Dictionary:
	return {"reached": 0, "names": []}


func close() -> void:
	pass


## Monta uma linha da economia.
static func row(at: int, account_id: int, kind: String, amount: int, item_id, source: String, detail = null) -> Dictionary:
	return {"at": at, "account_id": account_id, "kind": kind, "amount": amount, "item_id": item_id,
		"source": source, "detail": detail}
