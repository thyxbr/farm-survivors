class_name WorldHarvest
extends RefCounted
## Coleta de ferro e cristal em Valdoria, regras puras (o servidor e o solo rodam o mesmo código).
## Os nós vêm de data/balance/world_nodes.json: "kinds" (item, quantidade, golpes, tempo de volta) e
## "nodes" ([tipo, x, z]); o id de um nó é a posição dele na lista.
## Cada jogador tem os seus veios, como o saque pessoal: aqui só se guarda quando cada conta pode
## coletar cada nó de novo (em memória; reiniciar o servidor devolve todos os veios).

var _ready_at := {}   # "conta:nó" -> instante (unix s) em que volta a poder coletar


static func _table(bt: BalanceTables) -> Dictionary:
	return bt.get_table("world_nodes")


static func count(bt: BalanceTables) -> int:
	return (_table(bt).get("nodes", []) as Array).size()


## Dados de um nó: {"id", "kind", "pos", "item", "amount", "hits", "respawn", "model"}.
## Id que não é um inteiro dentro da lista (vem do cliente) devolve {}.
static func node_def(bt: BalanceTables, id) -> Dictionary:
	if typeof(id) != TYPE_INT:
		return {}
	var nodes: Array = _table(bt).get("nodes", [])
	if id < 0 or id >= nodes.size():
		return {}
	var n = nodes[id]
	if not (n is Array) or n.size() < 3:
		return {}
	var k: Dictionary = _table(bt).get("kinds", {}).get(str(n[0]), {})
	if k.is_empty():
		return {}
	return {"id": id, "kind": str(n[0]), "pos": Vector3(float(n[1]), 0.0, float(n[2])),
		"item": str(k.get("item", "")), "amount": int(k.get("amount", 1)), "hits": int(k.get("hits", 1)),
		"respawn": float(k.get("respawn", 60.0)), "model": str(k.get("model", n[0]))}


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
	return {"ok": true, "err": "", "items": {d.item: int(d.amount)}}


## Desfaz a marca de coletado (a concessão falhou depois do gather).
func undo(account: int, id: int) -> void:
	_ready_at.erase(_key(account, id))

