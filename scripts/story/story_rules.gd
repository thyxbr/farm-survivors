class_name StoryRules
extends RefCounted
## Regras puras da história (sem autoload: roda no runner de unitários). A história é a cadeia de missões de
## quests.json sem as secundárias ("side": true), na ordem das chaves; cada missão diz quem a oferece
## (giver_id), com quem se entrega (turn_in_id) e o tipo (CharRules.quest_type): abate, conversa ou coleta.
## Secundárias ficam fora da cadeia, podem exigir rank da guilda ("rank") e ser repetíveis ("repeat").
##   qt     = tabela "quests" (ItemDB.QUESTS / BalanceTables)
##   quests = estado do personagem: id -> {"state": "active"|"ready"|"done", "progress": int}
##   counts = quantos de cada item o personagem tem (só os alvos de coleta importam): id -> int
##   rank   = rank do personagem na guilda ("D" a "S")

const RANKS := ["D", "C", "B", "A", "S"]


static func rank_ge(rank: String, need: String) -> bool:
	return RANKS.find(rank) >= RANKS.find(need)


static func state(quests: Dictionary, id: String) -> String:
	return str(quests[id].state) if quests.has(id) else "none"


static func is_side(qt: Dictionary, id: String) -> bool:
	return bool(qt.get(id, {}).get("side", false))


## Primeira missão da história ainda não concluída ("" = história terminada).
static func current(qt: Dictionary, quests: Dictionary) -> String:
	for id in qt:
		if not is_side(qt, id) and state(quests, id) != "done":
			return id
	return ""


## A próxima missão da história depois de id ("" = era a última ou é secundária).
static func after(qt: Dictionary, id: String) -> String:
	if is_side(qt, id):
		return ""
	var found := false
	for k in qt:
		if is_side(qt, k):
			continue
		if found:
			return k
		if k == id:
			found = true
	return ""


static func giver(qt: Dictionary, id: String) -> String:
	return str(qt.get(id, {}).get("giver_id", "elder"))


static func turn_in(qt: Dictionary, id: String) -> String:
	var q: Dictionary = qt.get(id, {})
	return str(q.get("turn_in_id", q.get("giver_id", "elder")))


## Rank exigido pela missão para começar.
static func needs_rank(qt: Dictionary, id: String) -> String:
	return str(qt.get(id, {}).get("rank", "D"))


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


## Missão que o NPC npc_id pode entregar agora ("" = nenhuma). A da história vem primeiro.
static func turnable_at(qt: Dictionary, quests: Dictionary, npc_id: String, counts: Dictionary) -> String:
	var side := ""
	for id in quests:
		if qt.has(id) and turn_in(qt, id) == npc_id and turnable(qt, quests, id, counts):
			if not is_side(qt, id):
				return id
			if side == "":
				side = id
	return side


## Missão da história que o NPC tem para oferecer agora ("" = nenhuma): a atual, ainda não aceita e com rank.
static func offer_at(qt: Dictionary, quests: Dictionary, npc_id: String, rank := "S") -> String:
	var cur := current(qt, quests)
	if cur != "" and state(quests, cur) == "none" and giver(qt, cur) == npc_id and rank_ge(rank, needs_rank(qt, cur)):
		return cur
	return ""


## Secundária disponível para aceitar (rank suficiente; nunca feita ou repetível e já entregue).
static func side_available(qt: Dictionary, quests: Dictionary, id: String, rank: String) -> bool:
	if not is_side(qt, id) or not rank_ge(rank, needs_rank(qt, id)):
		return false
	var st := state(quests, id)
	return st == "none" or (st == "done" and bool(qt[id].get("repeat", false)))


## Secundárias que o NPC (ou o quadro da guilda) oferece agora, na ordem de quests.json.
static func side_offers_at(qt: Dictionary, quests: Dictionary, npc_id: String, rank: String) -> Array:
	var out: Array = []
	for id in qt:
		if giver(qt, id) == npc_id and side_available(qt, quests, id, rank):
			out.append(id)
	return out


## Marcador sobre a cabeça do NPC: "?" entrega, "!" história, "+" secundária nova, "" nada.
static func marker(qt: Dictionary, quests: Dictionary, npc_id: String, counts: Dictionary, rank := "S") -> String:
	if turnable_at(qt, quests, npc_id, counts) != "":
		return "?"
	if offer_at(qt, quests, npc_id, rank) != "":
		return "!"
	if not side_offers_at(qt, quests, npc_id, rank).is_empty():
		return "+"
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
