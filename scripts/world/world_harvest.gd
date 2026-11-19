class_name WorldHarvest
extends RefCounted
## Coleta de minério, cristal e madeira em Valdoria, regras puras (o servidor e o solo rodam o mesmo código).
## O que cada tipo de nó dá vem de data/balance/world_nodes.json ("kinds": item, quantidade, resistência, nível
## mínimo de ferramenta, tempo de volta; ver GatherRules). Onde ficam: veios e árvores especiais são MapEntity
## "resource_node" com node_id fixo e o tipo em ref; e toda árvore do cenário (MapProp tree_*) também se corta, com o
## tipo de madeira de "tree_models" (MapData.resource_nodes, ids a partir de MapData.TREE_ID_BASE).
## Os nós são do mundo, iguais para todos: quem coleta primeiro leva e o nó some para todo mundo até voltar. Aqui
## só se guarda quando cada nó volta (em memória; reiniciar o servidor devolve todos).

var _ready_at := {}   # nó -> instante (unix s) em que volta a poder ser coletado


static func _table(bt: BalanceTables) -> Dictionary:
	return bt.get_table("world_nodes")


static func count(bt: BalanceTables) -> int:
	return ids(bt).size()


## Ids dos nós das cenas cujo tipo existe na tabela, em ordem.
static func ids(bt: BalanceTables) -> Array:
	var nodes := MapData.resource_nodes()
	var out: Array = nodes.keys().filter(func(id) -> bool: return kind_of(bt, str(nodes[id].kind)) != "")
	out.sort()
	return out


## Tipo da tabela de um nó das cenas: o próprio (veio "iron", árvore especial "oak") ou, para uma árvore do cenário
## (modelo "tree_pine"), o de "tree_models". "" se não existe.
static func kind_of(bt: BalanceTables, raw: String) -> String:
	var t := _table(bt)
	if (t.get("kinds", {}) as Dictionary).has(raw):
		return raw
	return str(t.get("tree_models", {}).get(raw, ""))


## Dados de um nó: {"id", "kind", "pos", "item", "amount", "tough", "tier", "respawn", "model", "tint", "prof", "level", "xp"}
## (tough/tier: resistência aos golpes e nível mínimo de ferramenta, ver GatherRules; prof/level/xp: a profissão de
## coleta, o nível dela que o nó pede e a XP de cada coleta).
## Id que não é um inteiro ou não existe nas cenas (vem do cliente) devolve {}.
static func node_def(bt: BalanceTables, id) -> Dictionary:
	if typeof(id) != TYPE_INT:
		return {}
	var n = MapData.resource_nodes().get(id)
	if n == null:
		return {}
	var kind := kind_of(bt, str(n.kind))
	var k: Dictionary = _table(bt).get("kinds", {}).get(kind, {})
	if k.is_empty():
		return {}
	var prop: bool = n.get("prop", false)
	return {"id": id, "kind": kind, "pos": n.pos, "prop": prop, "scale": float(n.get("scale", 1.0)),
		"item": str(k.get("item", "")), "amount": int(k.get("amount", 1)), "tough": float(k.get("tough", 6.0)), "tier": int(k.get("tier", 1)),
		"respawn": float(k.get("respawn", 60.0)), "model": str(n.kind) if prop else str(k.get("model", n.kind)),
		"tint": Color(0.55, 0.3, 0.2) if prop else k.get("tint", Color(0.55, 0.3, 0.2)), "prof": str(k.get("prof", "")), "level": int(k.get("level", 1)),
		"xp": int(k.get("xp", 0))}


## Segundos até o nó poder ser coletado de novo (0 = pronto). `_account` ficou na assinatura: os nós são de todos.
func ready_in(_account: int, id: int, now: float) -> float:
	return maxf(0.0, float(_ready_at.get(id, 0.0)) - now)


## Nós esgotados agora: {id: segundos até voltar} (o servidor manda para quem entra em Valdoria).
func depleted(now: float) -> Dictionary:
	var out := {}
	for id in _ready_at.keys():
		var left := float(_ready_at[id]) - now
		if left > 0.0:
			out[id] = left
		else:
			_ready_at.erase(id)
	return out


## A conta `account`, na posição `from`, coleta o nó `id` (some para todos até voltar). {"ok", "err", "items": {item: quantidade}}.
## Recusas: "no_invalido", "longe" (HitGuard.accepts_harvest), "esgotado" (ainda não voltou).
func gather(bt: BalanceTables, account: int, id, from: Vector3, now: float) -> Dictionary:
	var d := node_def(bt, id)
	if d.is_empty() or d.item == "":
		return {"ok": false, "err": "no_invalido", "items": {}}
	if not HitGuard.accepts_harvest(from, d.pos):
		return {"ok": false, "err": "longe", "items": {}}
	if ready_in(account, id, now) > 0.0:
		return {"ok": false, "err": "esgotado", "items": {}}
	_ready_at[id] = now + float(d.respawn)
	return {"ok": true, "err": "", "items": {d.item: int(d.amount)}, "prof": d.prof, "level": d.level, "xp": d.xp,
		"tier": d.tier}


## Desfaz a marca de coletado (a concessão falhou depois do gather).
func undo(_account: int, id: int) -> void:
	_ready_at.erase(id)

