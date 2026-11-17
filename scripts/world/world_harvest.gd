class_name WorldHarvest
extends RefCounted
## Coleta de ferro e cristal em Valdoria, regras puras (o servidor e o solo rodam o mesmo código).
## O que cada tipo de veio dá vem de data/balance/world_nodes.json ("kinds": item, quantidade, golpes, tempo
## de volta); onde ficam os veios vem das cenas dos mapas (MapEntity "resource_node" com node_id fixo e o tipo
## em ref; MapData.resource_nodes). O id é o node_id: apagar ou mover um veio no editor não renumera os outros.
## Cada jogador tem os seus veios, como o saque pessoal: aqui só se guarda quando cada conta pode
## coletar cada nó de novo (em memória; reiniciar o servidor devolve todos os veios).

var _ready_at := {}   # "conta:nó" -> instante (unix s) em que volta a poder coletar


static func _table(bt: BalanceTables) -> Dictionary:
	return bt.get_table("world_nodes")


static func count(bt: BalanceTables) -> int:
	return ids(bt).size()


## Ids dos veios das cenas cujo tipo existe na tabela, em ordem.
static func ids(bt: BalanceTables) -> Array:
	var kinds: Dictionary = _table(bt).get("kinds", {})
	var nodes := MapData.resource_nodes()
	var out: Array = nodes.keys().filter(func(id) -> bool: return kinds.has(str(nodes[id].kind)))
	out.sort()
	return out


## Dados de um nó: {"id", "kind", "pos", "item", "amount", "hits", "respawn", "model", "tint", "prof", "level", "xp"}
## (prof/level/xp: a profissão de coleta, o nível dela que o nó pede e a XP de cada coleta).
## Id que não é um inteiro ou não existe nas cenas (vem do cliente) devolve {}.
static func node_def(bt: BalanceTables, id) -> Dictionary:
	if typeof(id) != TYPE_INT:
		return {}
	var n = MapData.resource_nodes().get(id)
	if n == null:
		return {}
	var k: Dictionary = _table(bt).get("kinds", {}).get(str(n.kind), {})
	if k.is_empty():
		return {}
	return {"id": id, "kind": str(n.kind), "pos": n.pos,
		"item": str(k.get("item", "")), "amount": int(k.get("amount", 1)), "hits": int(k.get("hits", 1)),
		"respawn": float(k.get("respawn", 60.0)), "model": str(k.get("model", n.kind)),
		"tint": k.get("tint", Color(0.55, 0.3, 0.2)), "prof": str(k.get("prof", "")), "level": int(k.get("level", 1)),
		"xp": int(k.get("xp", 0))}


func _key(account: int, id: int) -> String:
	return "%d:%d" % [account, id]


## Segundos até a conta poder coletar o nó de novo (0 = pronto).
func ready_in(account: int, id: int, now: float) -> float:
	return maxf(0.0, float(_ready_at.get(_key(account, id), 0.0)) - now)


## A conta `account`, na posição `from`, coleta o nó `id`. {"ok", "err", "items": {item: quantidade}}.
## Recusas: "no_invalido", "longe" (HitGuard.accepts_harvest), "esgotado" (ainda não voltou).
func gather(bt: BalanceTables, account: int, id, from: Vector3, now: float) -> Dictionary:
	var d := node_def(bt, id)
	if d.is_empty() or d.item == "":
		return {"ok": false, "err": "no_invalido", "items": {}}
	if not HitGuard.accepts_harvest(from, d.pos):
		return {"ok": false, "err": "longe", "items": {}}
	if ready_in(account, id, now) > 0.0:
		return {"ok": false, "err": "esgotado", "items": {}}
	_ready_at[_key(account, id)] = now + float(d.respawn)
	return {"ok": true, "err": "", "items": {d.item: int(d.amount)}, "prof": d.prof, "level": d.level, "xp": d.xp}


## Desfaz a marca de coletado (a concessão falhou depois do gather).
func undo(account: int, id: int) -> void:
	_ready_at.erase(_key(account, id))

