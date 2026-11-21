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
## Quem está batendo em cada nó agora: nó -> {"owner": quem (o peer, no servidor), "until": instante em que a reserva
## vence se não for renovada}. Enquanto vale, só o dono coleta o nó (os outros são recusados com "ocupado").
var _claims := {}

## Segundos que uma reserva dura sem ser renovada (o cliente renova a cada golpe, ver GatherAction; o golpe mais
## lento é de GatherRules.SWING_BASE = 1 s e a ida até a pedra leva até GatherAction.APPROACH_MAX = 2 s).
const CLAIM_TTL := 5.0


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
## Recusas: "no_invalido", "longe" (HitGuard.accepts_harvest), "esgotado" (ainda não voltou), "ocupado" (outro
## `owner` tem a reserva do nó; owner 0 = sem reservas, como no solo).
func gather(bt: BalanceTables, account: int, id, from: Vector3, now: float, owner := 0) -> Dictionary:
	var d := node_def(bt, id)
	if d.is_empty() or d.item == "":
		return {"ok": false, "err": "no_invalido", "items": {}}
	if not HitGuard.accepts_harvest(from, d.pos):
		return {"ok": false, "err": "longe", "items": {}}
	if ready_in(account, id, now) > 0.0:
		return {"ok": false, "err": "esgotado", "items": {}}
	if owner != 0 and holder(id, now) not in [0, owner]:
		return {"ok": false, "err": "ocupado", "items": {}}
	_ready_at[id] = now + float(d.respawn)
	_claims.erase(id)   # o nó caiu: a reserva acabou junto
	return {"ok": true, "err": "", "items": {d.item: int(d.amount)}, "prof": d.prof, "level": d.level, "xp": d.xp,
		"tier": d.tier}


## `owner` começa ou renova a reserva do nó `id` (começou a bater nele). false se outro já está batendo nele, ou se o
## nó não existe ou está esgotado.
func claim(bt: BalanceTables, id, owner: int, now: float) -> bool:
	if node_def(bt, id).is_empty() or ready_in(0, id, now) > 0.0:
		return false
	var h := holder(id, now)
	if h != 0 and h != owner:
		return false
	_claims[id] = {"owner": owner, "until": now + CLAIM_TTL}
	return true


## Quem tem a reserva do nó `id` agora (0 = ninguém).
func holder(id, now: float) -> int:
	var c = _claims.get(id)
	if c == null:
		return 0
	if float(c.until) <= now:
		_claims.erase(id)
		return 0
	return int(c.owner)


## `owner` largou o nó `id` (parou de bater). true se a reserva era dele e saiu.
func release(id, owner: int) -> bool:
	var c = _claims.get(id)
	if c == null or int(c.owner) != owner:
		return false
	_claims.erase(id)
	return true


## Larga todas as reservas de `owner` (saiu do jogo ou da zona). Devolve os nós liberados.
func release_owner(owner: int) -> Array:
	var out: Array = []
	for id in _claims.keys():
		if int(_claims[id].owner) == owner:
			_claims.erase(id)
			out.append(id)
	return out


## Tira as reservas vencidas (o dono parou de renovar sem avisar). Devolve os nós liberados.
func expire_claims(now: float) -> Array:
	var out: Array = []
	for id in _claims.keys():
		if float(_claims[id].until) <= now:
			_claims.erase(id)
			out.append(id)
	return out


## Nós reservados agora: {id: dono}.
func claims(now: float) -> Dictionary:
	var out := {}
	for id in _claims.keys():
		var h := holder(id, now)
		if h != 0:
			out[id] = h
	return out


## Desfaz a marca de coletado (a concessão falhou depois do gather).
func undo(_account: int, id: int) -> void:
	_ready_at.erase(id)

