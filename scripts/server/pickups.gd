class_name PickupRegistry
extends RefCounted
## Loot no chão do servidor: cada pickup tem um dono (peer), uma zona, uma posição e o conteúdo
## (ouro e/ou itens). O cliente só vê os próprios e pede a coleta pelo net_id; o servidor confere
## dono, se já foi pego, se expirou e se o jogador está perto (última posição recebida dele).
## Puro: sem autoload nem nós; o relógio é injetável (testes).

## Distância máxima entre a última posição do jogador e o pickup na coleta.
const MAX_DIST := 4.0
const DEFAULT_TTL := 120.0

var _clock: Callable
var _next := 1
var _items := {}   # net_id -> {"owner", "zone", "pos", "gold", "items", "expires"}


func _init(clock: Callable = Callable()) -> void:
	_clock = clock


func _now() -> float:
	return float(_clock.call()) if _clock.is_valid() else Time.get_ticks_msec() / 1000.0


## Registra um pickup e devolve o net_id (sempre > 0).
func spawn(owner: int, zone: String, pos: Vector3, gold: int, items: Dictionary, ttl := DEFAULT_TTL) -> int:
	var id := _next
	_next += 1
	_items[id] = {"owner": owner, "zone": zone, "pos": pos, "gold": maxi(0, gold), "items": items.duplicate(),
		"expires": _now() + ttl}
	return id


## {"ok": true, "gold", "items"} (e o pickup some) ou {"ok": false, "err": "dono"|"pego"|"expirou"|"longe"}.
## "longe" deixa o pickup no chão (o jogador pode chegar mais perto e tentar de novo).
## Vector3.INF em `peer_pos` = posição desconhecida (sempre longe).
func claim(net_id: int, peer: int, peer_pos: Vector3) -> Dictionary:
	if not _items.has(net_id):
		return {"ok": false, "err": "pego"}
	var p: Dictionary = _items[net_id]
	if int(p.owner) != peer:
		return {"ok": false, "err": "dono"}
	if _now() >= float(p.expires):
		_items.erase(net_id)
		return {"ok": false, "err": "expirou"}
	if not peer_pos.is_finite() or peer_pos.distance_to(p.pos) > MAX_DIST:
		return {"ok": false, "err": "longe"}
	_items.erase(net_id)
	return {"ok": true, "gold": int(p.gold), "items": p.items}


## Zona do pickup ("" se não existe).
func zone_of(net_id: int) -> String:
	return str(_items[net_id].zone) if _items.has(net_id) else ""


## Tira os pickups do peer (saiu do jogo; com `zone`, só os daquela zona — fim da partida da Horda).
func drop_peer(peer: int, zone := "") -> void:
	for id in _items.keys():
		if int(_items[id].owner) == peer and (zone == "" or _items[id].zone == zone):
			_items.erase(id)


## Remove os expirados; devolve quantos.
func purge_expired() -> int:
	var t := _now()
	var n := 0
	for id in _items.keys():
		if t >= float(_items[id].expires):
			_items.erase(id)
			n += 1
	return n


func size() -> int:
	return _items.size()
