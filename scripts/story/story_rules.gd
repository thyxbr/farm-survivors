class_name StoryRules
extends RefCounted
## Regras puras da história (sem autoload: roda no runner de unitários). A história é a cadeia de missões de
## quests.json, na ordem das chaves; cada missão diz quem a oferece (giver_id), com quem se entrega
## (turn_in_id) e o tipo (CharRules.quest_type): abate, conversa ou coleta.
##   qt     = tabela "quests" (ItemDB.QUESTS / BalanceTables)
##   quests = estado do personagem: id -> {"state": "active"|"ready"|"done", "progress": int}
##   counts = quantos de cada item o personagem tem (só os alvos de coleta importam): id -> int


static func state(quests: Dictionary, id: String) -> String:
	return str(quests[id].state) if quests.has(id) else "none"


## Primeira missão da cadeia ainda não concluída ("" = história terminada).
static func current(qt: Dictionary, quests: Dictionary) -> String:
	for id in qt:
		if state(quests, id) != "done":
			return id
	return ""


## A próxima missão depois de id na cadeia ("" = era a última).
static func after(qt: Dictionary, id: String) -> String:
	var order: Array = qt.keys()
	var i := order.find(id)
	return order[i + 1] if i >= 0 and i + 1 < order.size() else ""


static func giver(qt: Dictionary, id: String) -> String:
	return str(qt.get(id, {}).get("giver_id", "elder"))


static func turn_in(qt: Dictionary, id: String) -> String:
	var q: Dictionary = qt.get(id, {})
	return str(q.get("turn_in_id", q.get("giver_id", "elder")))


## A missão já pode ser entregue (abate pronto, conversa ativa ou itens de coleta na mochila).
static func turnable(qt: Dictionary, quests: Dictionary, id: String, counts: Dictionary) -> bool:
	var st := state(quests, id)
	if st == "ready":
		return true
	if st != "active":
		return false
	var q: Dictionary = qt[id]
	match CharRules.quest_type(q):
		"talk":
			return true
		"collect":
			return int(counts.get(q.target, 0)) >= int(q.count)
	return false


## Missão que o NPC npc_id pode entregar agora ("" = nenhuma).
static func turnable_at(qt: Dictionary, quests: Dictionary, npc_id: String, counts: Dictionary) -> String:
	for id in quests:
		if qt.has(id) and turn_in(qt, id) == npc_id and turnable(qt, quests, id, counts):
			return id
	return ""


## Missão que o NPC npc_id tem para oferecer agora ("" = nenhuma): a atual da cadeia, ainda não aceita.
static func offer_at(qt: Dictionary, quests: Dictionary, npc_id: String) -> String:
	var cur := current(qt, quests)
	if cur != "" and state(quests, cur) == "none" and giver(qt, cur) == npc_id:
		return cur
	return ""


## Marcador sobre a cabeça do NPC: "?" entrega, "!" missão nova, "" nada.
static func marker(qt: Dictionary, quests: Dictionary, npc_id: String, counts: Dictionary) -> String:
	if turnable_at(qt, quests, npc_id, counts) != "":
		return "?"
	if offer_at(qt, quests, npc_id) != "":
		return "!"
	return ""


## [feito, total] do objetivo da missão.
static func progress(qt: Dictionary, quests: Dictionary, id: String, counts: Dictionary) -> Array:
	var q: Dictionary = qt[id]
	var total := int(q.get("count", 1))
	var st := state(quests, id)
	if st == "done" or st == "ready":
		return [total, total]
	match CharRules.quest_type(q):
		"talk":
			return [0, total]
		"collect":
			return [mini(int(counts.get(q.target, 0)), total), total]
	return [mini(int(quests.get(id, {}).get("progress", 0)), total), total]


## Para onde o rastreador aponta: o NPC de entrega (id) quando dá para entregar ou a missão é de conversa;
## senão a área da missão ("where": [x, z]). {"npc": id} ou {"pos": Vector2} ou {} (sem destino).
static func destination(qt: Dictionary, quests: Dictionary, id: String, counts: Dictionary) -> Dictionary:
	if id == "" or not qt.has(id):
		return {}
	var q: Dictionary = qt[id]
	var st := state(quests, id)
	if st == "none":
		return {"npc": giver(qt, id)}
	if turnable(qt, quests, id, counts) or CharRules.quest_type(q) == "talk":
		return {"npc": turn_in(qt, id)}
	if q.has("where"):
		var w: Array = q.where
		return {"pos": Vector2(float(w[0]), float(w[1]))}
	return {}


## Missões que estrearam um capítulo entre dois estados (para o cartão de título "Episódio N").
static func new_chapters(qt: Dictionary, before: Dictionary, now: Dictionary) -> Array:
	var out: Array = []
	for id in now:
		if qt.has(id) and qt[id].has("chapter") and state(before, id) == "none" and state(now, id) != "none":
			out.append(id)
	return out
