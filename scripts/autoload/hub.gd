extends Node
## Hub: os recordes da Horda, que são de todos os jogadores (o quadro de avisos da vila mostra).
##
## - Online: os recordes moram no servidor (Network.characters). Quem termina de carregar Valdoria recebe
##   `_hub_state`; cada fim de partida reenvia o estado a todos os conectados.
## - Solo: o mesmo estado sai do serviço local (Econ.records) em refresh_solo().
##
## As RPCs moram aqui (e não no Network): uma RPC nova no Network mudaria os ids das que os clientes
## antigos usam para receber "atualize o jogo". Este autoload existe igual em servidor e clientes.

## Cliente/solo: os recordes mudaram.
signal changed

## Nome que aparece para a conta do solo (no banco ela se chama "local").
const SOLO_NAME := "Você"

## {"horde": {"reached": int, "names": [..]}}
var records := {}


## Solo: relê os recordes do save solo e avisa quem mostra.
func refresh_solo() -> void:
	if Network.is_online():
		return
	var rec := Econ.records()
	for mode in rec:
		if rec[mode] is Dictionary and rec[mode].has("names"):
			rec[mode]["names"] = [SOLO_NAME] if not rec[mode].names.is_empty() else []
	records = rec
	changed.emit()


## A vila terminou de montar: no solo lê o estado local (online o servidor manda no _client_ready).
func enter() -> void:
	if not Network.is_online():
		refresh_solo()


## Cliente saiu do servidor (Network.leave): os recordes vistos eram os do servidor.
func client_reset() -> void:
	records = {}
	changed.emit()


# ================================================================ servidor
func _server_records() -> Dictionary:
	return Network.characters.records() if Network.characters != null else {}


func server_send_state(peer: int) -> void:
	if Network.is_server() and Network.players.has(peer):
		_hub_state.rpc_id(peer, _server_records())


## Uma partida terminou: os recordes podem ter mudado (vai a todos os conectados).
func server_records_changed() -> void:
	if not Network.is_server():
		return
	var r := _server_records()
	for pid in Network._all_peers():
		_hub_state.rpc_id(pid, r)


# ================================================================ cliente
@rpc("authority", "call_remote", "reliable")
func _hub_state(r: Dictionary) -> void:
	records = r
	changed.emit()
