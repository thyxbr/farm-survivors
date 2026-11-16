class_name CharStore
extends RefCounted
## Onde o CharacterService guarda os personagens e o registro das partidas (runs, recordes). As regras
## (CharRules, RewardRules) e o registro da economia são os mesmos
## em qualquer armazenamento; só muda o meio:
## - SqliteCharStore: servidor dedicado, sobre o Db (SQLite; esquema e migrações em Migrations).
## - FileCharStore: solo offline, JSON em user:// (o cliente Windows não leva o SQLite): personagem
##   e partidas em arquivos ao lado um do outro.
##
## Linha da economia (append_economy / save_char): {"at": int, "account_id": int, "kind": String,
## "amount": int, "item_id": String ou null (null = ouro), "source": String, "detail": String JSON ou null}.

## Mensagem da última operação que falhou ("" se deu certo).
var last_error := ""


## Os métodos de personagem recebem o id do PERSONAGEM (`char_id`). No SQLite uma conta tem vários
## (create_char/list_chars); no solo (arquivo) o personagem 1 é o da conta 1.

## Personagem salvo (formato de CharState.to_dict, mais "updated_at" em segundos Unix) ou null se não existe.
func load_char(_char_id: int) -> Variant:
	return null


## Conta dona do personagem (o registro da economia e as partidas são da conta). Sem dono conhecido: o
## próprio id (solo e testes antigos: personagem N = conta N).
func owner_of(char_id: int) -> int:
	return char_id


## Cria um personagem novo da conta com o nome `name` e o estado `state` (CharState.to_dict).
## Devolve o id (> 0) ou 0 (nome já usado por outro herói: last_error = "nome_em_uso").
func create_char(_account_id: int, _name: String, _state: Dictionary, _at: int) -> int:
	last_error = "não implementado"
	return 0


## Resumo dos personagens da conta para a tela de seleção, do mais antigo ao mais novo:
## [{"id", "name", "level", "char_class", "body", "equipment", "updated_at"}].
func list_chars(_account_id: int) -> Array:
	return []


## Nome do personagem ("" se não tem: solo e testes antigos).
func name_of(_char_id: int) -> String:
	return ""


## Algum personagem (de qualquer conta) já usa este nome? Sem diferenciar maiúsculas.
func name_taken(_name: String) -> bool:
	return false


## Conta dona do personagem chamado `name` (0 se não existe).
func account_by_char_name(_name: String) -> int:
	return 0


## Grava o personagem (`state` = CharState.to_dict) e as linhas da economia `rows` numa escrita só:
## ou tudo fica gravado, ou o personagem salvo continua o anterior. `at` vira o updated_at.
func save_char(_char_id: int, _state: Dictionary, _rows: Array, _at: int) -> bool:
	last_error = "não implementado"
	return false


## Acrescenta linhas da economia sem mexer no personagem (resumo de partida).
func append_economy(_rows: Array) -> bool:
	last_error = "não implementado"
	return false


## Apaga o personagem ("Novo jogo" do solo, "Excluir" da seleção). true se não existe mais.
func delete_char(_char_id: int) -> bool:
	last_error = "não implementado"
	return false


## Abre o registro de uma partida (`accounts` = contas que começaram). Devolve o run_id (> 0) ou 0 se falhou.
func start_run(_mode: String, _accounts: Array, _at: int) -> int:
	last_error = "não implementado"
	return 0


## A conta do personagem já fechou sua parte nesta partida (finish_player é idempotente por run_id + conta)?
func run_player_done(_run_id: int, _char_id: int) -> bool:
	return false


## Fim da partida de um jogador numa escrita só: o personagem (`state`, já com os Ecos), a linha dele na
## partida (`entry` = {"reached", "ecos", "gold", "xp", "build"}; nenhuma se run_id <= 0) e as linhas da
## economia `rows`. Ou tudo fica gravado, ou nada.
func save_run_player(_char_id: int, _state: Dictionary, _run_id: int, _entry: Dictionary, _rows: Array,
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
## `char_id` 0 = sem personagem (o servidor sempre manda o do personagem que mudou).
static func row(at: int, account_id: int, kind: String, amount: int, item_id, source: String, detail = null,
		char_id := 0) -> Dictionary:
	return {"at": at, "account_id": account_id, "kind": kind, "amount": amount, "item_id": item_id,
		"source": source, "detail": detail, "char_id": char_id}
