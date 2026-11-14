extends Node
## Hub: a praça da cidade (ponto de chegada) e o que ela mostra — a base compartilhada e os recordes.
##
## - Online: a base e os recordes moram no servidor (Network.characters). Quem entra na praça manda
##   `_enter_hub`; o servidor põe o peer na zona "hub", apresenta os jogadores que já estão lá e manda
##   `_hub_state`. Cada doação (Econ._econ_req) e cada fim de partida reenviam o estado a todos os
##   conectados, em qualquer zona (a praça de quem está em Valdoria também fica em dia).
## - Solo: o mesmo estado sai do serviço local (Econ.base_state/records/top_donors) em refresh_solo().
##
## As RPCs da praça moram aqui (e não no Network): uma RPC nova no Network mudaria os ids das que os
## clientes antigos usam para receber "atualize o jogo". Este autoload existe igual em servidor e clientes.

## Cliente/solo: a base ou os recordes mudaram (a praça redesenha).
signal changed

## Doadores mostrados por construção.
const TOP_DONORS := 5
## Nome que a praça mostra para a conta do solo (no banco ela se chama "local").
const SOLO_NAME := "Você"

## {id: {"level": int, "fund": int, "donors": [{"name", "amount"}]}} — o que a praça mostra.
var base := {}
## {"horde": {"reached": int, "names": [..]}, "city": {...}}
var records := {}
## Solo: o portal da praça pediu a Horda; Valdoria começa a partida assim que monta (world.gd).
var pending_horde := false
## A próxima partida da Horda veio do portal da praça: no fim ela volta para a praça, não para a vila.
var horde_return := false
## Online: horde_return vence neste instante (ms) se a fila não abrir/continuar aberta. Cobre o servidor
## recusar o pedido (partida em andamento) e a fila fechar sem o jogador (não chegou a tempo, recusou):
## sem isso uma Horda aberta depois pelo portal da vila terminaria na praça.
var _return_until := 0
## Tempo para a fila aparecer depois do pedido (viagem até Valdoria + resposta do servidor) e para o
## começo da partida chegar depois que a fila fecha (as duas mensagens podem vir em quadros diferentes).
const RETURN_WAIT_MS := 10000
const RETURN_GRACE_MS := 5000


## Portal da praça: a arena fica em Valdoria. Online abre/entra na fila no servidor (ele espera quem
## ainda está viajando, HORDE_TRAVEL_WAIT) e viaja; solo viaja e a partida começa ao chegar.
func go_horde() -> void:
	horde_return = true
	_return_until = Time.get_ticks_msec() + RETURN_WAIT_MS
	if Network.is_online():
		Network.request_horde()
	else:
		pending_horde = true
	Lobby.go_world()


func _process(_delta: float) -> void:
	if not horde_return or not Network.is_client():
		return
	var now := Time.get_ticks_msec()
	if not Network.horde_lobby.is_empty():
		_return_until = now + RETURN_GRACE_MS   # fila aberta: o pedido continua valendo
	elif now > _return_until:
		horde_return = false


## Solo (world.gd no fim do _ready): devolve e limpa o pedido de Horda vindo da praça.
func take_pending_horde() -> bool:
	var p := pending_horde
	pending_horde = false
	return p


## Quem cria a partida (world.gd) pergunta uma vez se ela deve voltar à praça.
func take_horde_return() -> bool:
	var r := horde_return
	horde_return = false
	return r


## Bônus da base: online sobre a base que veio do servidor; solo direto do serviço local.
func base_bonus() -> Dictionary:
	if Network.is_online():
		return BaseRules.bonus(Balance.tables, base)
	return Econ.base_bonus()


## Solo: relê a base e os recordes do solo.db e avisa a praça.
func refresh_solo() -> void:
	if Network.is_online():
		return
	var st := Econ.base_state()
	for id in st:
		var donors: Array = Econ.top_donors(id, TOP_DONORS)
		for d in donors:
			d["name"] = SOLO_NAME   # no solo.db só existe a conta do jogador
		st[id]["donors"] = donors
	base = st
	var rec := Econ.records()
	for mode in rec:
		if rec[mode] is Dictionary and rec[mode].has("names"):
			rec[mode]["names"] = [SOLO_NAME] if not rec[mode].names.is_empty() else []
	records = rec
	changed.emit()


## A cena da praça terminou de montar: online avisa o servidor (zona "hub"); solo lê o estado local.
func enter(scene: Node) -> void:
	Network.hub_ready(scene)
	if Network.is_client():
		_enter_hub.rpc_id(1)
	elif not Network.is_online():
		refresh_solo()


## Cliente saiu do servidor (Network.leave): a base vista era a do servidor.
func client_reset() -> void:
	base = {}
	records = {}
	pending_horde = false
	horde_return = false
	changed.emit()


# ================================================================ servidor
## Estado da base com os maiores doadores de cada construção.
func _server_base() -> Dictionary:
	var c: CharacterService = Network.characters
	if c == null:
		return {}
	var st := c.base_state()
	for id in st:
		st[id]["donors"] = c.top_donors(id, TOP_DONORS)
	return st


func _server_records() -> Dictionary:
	return Network.characters.records() if Network.characters != null else {}


func server_send_state(peer: int) -> void:
	if Network.is_server() and Network.players.has(peer):
		_hub_state.rpc_id(peer, _server_base(), _server_records())


## A todos os conectados, em qualquer zona.
func server_broadcast() -> void:
	if not Network.is_server():
		return
	var b := _server_base()
	var r := _server_records()
	for pid in Network._all_peers():
		_hub_state.rpc_id(pid, b, r)


## Uma doação mudou a base: todos recebem o estado novo e, se uma construção subiu de nível, o chat avisa.
func server_base_changed(account: int, events: Array) -> void:
	if not Network.is_server():
		return
	server_broadcast()
	var who := "?"
	for pid in Network.players:
		if int(Network.players[pid].get("account", 0)) == account:
			who = str(Network.players[pid].name)
			break
	var defs: Dictionary = Balance.tables.get_table("base_buildings").get("buildings", {})
	for e in events:
		if not (e is Dictionary) or e.get("t") != "donated" or int(e.get("leveled", 0)) <= 0:
			continue
		var id := str(e.get("building", ""))
		var text := "%s subiu para o nível %d! (doação de %s)" % [
			str(defs.get(id, {}).get("name", id)), int(e.get("level", 0)), who]
		print("[server] %s" % text)
		for pid in Network._all_peers():
			Network._chat_msg.rpc_id(pid, "", text)


## Uma partida terminou (Task 4): os recordes podem ter mudado.
func server_records_changed() -> void:
	server_broadcast()


## Cliente → servidor: cheguei à praça.
@rpc("any_peer", "call_remote", "reliable")
func _enter_hub() -> void:
	var id := multiplayer.get_remote_sender_id()
	if not Network.is_server() or not Network.players.has(id):
		return
	if Network.zone_of(id) == "hub" and Network.players[id].ready:
		server_send_state(id)   # já está na praça: pedido repetido só reenvia o estado (barato contra spam)
		return
	Network.server_set_zone(id, "hub")
	# quem já está na praça é apresentado ao recém-chegado (nome e visual das réplicas)
	for pid in Network.zone_peers("hub"):
		if pid != id:
			Network._player_joined.rpc_id(id, pid, Network.players[pid])
	server_send_state(id)
	Lobby._room_state.rpc_id(id, Lobby._room_view(), Lobby._record)
	# fila da Horda aberta: quem chega à praça também vê o convite (como no _client_ready)
	if not Network._lobby.is_empty():
		Network._horde_lobby.rpc_id(id, Network._lobby_state())


# ================================================================ cliente
@rpc("authority", "call_remote", "reliable")
func _hub_state(b: Dictionary, r: Dictionary) -> void:
	base = b
	records = r
	changed.emit()
