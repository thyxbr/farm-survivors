class_name EnchantRules
extends RefCounted
## Encantamento de armas, regras puras (servidor e solo rodam o mesmo código; ver CharRules).
## O encanto pertence ao TIPO de arma do personagem: s.enchants = {id da arma: {"el", "lv"}}.
## Fica guardado mesmo com a arma desequipada ou vendida. Números em data/balance/enchant.json:
##   max_level, damage[nível-1], elements[el].essence, levels[nível-1] (custo para chegar ao nível),
##   swap (taxa para trocar de elemento mantendo o nível).


static func _table(bt: BalanceTables) -> Dictionary:
	return bt.get_table("enchant")


## Encanto de uma arma: {"el", "lv"}; sem encanto = {"el": "", "lv": 0}.
static func of(s: CharState, weapon_id: String) -> Dictionary:
	var e = s.enchants.get(weapon_id)
	if e is Dictionary and int(e.get("lv", 0)) > 0:
		return {"el": str(e.get("el", "")), "lv": int(e.lv)}
	return {"el": "", "lv": 0}


## O que custa pôr `element` na arma equipada agora.
## {"ok", "err", "kind": "up"|"swap", "to": nível resultante, "gold", "ecos", "items": {id: qty}}
## (a essência do elemento já vem somada em items). Só confere arma, elemento e nível máximo:
## se o personagem pode pagar é com enchant().
static func cost(s: CharState, bt: BalanceTables, element: String) -> Dictionary:
	var out := {"ok": false, "err": "", "kind": "up", "to": 0, "gold": 0, "ecos": 0, "items": {}}
	var t := _table(bt)
	var levels: Array = t.get("levels", [])
	var elements: Dictionary = t.get("elements", {})
	if levels.is_empty() or elements.is_empty():
		out.err = "sem_tabela"
		return out
	var wid: String = s.equipment.get("weapon", "")
	if wid == "":
		out.err = "sem_arma"
		return out
	if not elements.has(element):
		out.err = "elemento_invalido"
		return out
	var cur := of(s, wid)
	var max_lv := mini(int(t.get("max_level", levels.size())), levels.size())
	var essence: String = elements[element].get("essence", "")
	var n_ess := 0
	if cur.lv > 0 and cur.el != element:
		var sw: Dictionary = t.get("swap", {})
		out.kind = "swap"
		out.to = cur.lv
		out.gold = int(sw.get("gold", 0))
		n_ess = int(sw.get("essence", 0))
	else:
		if cur.lv >= max_lv:
			out.err = "nivel_maximo"
			return out
		var lv: Dictionary = levels[cur.lv]
		out.to = cur.lv + 1
		out.gold = int(lv.get("gold", 0))
		out.ecos = int(lv.get("ecos", 0))
		var its: Dictionary = lv.get("items", {})
		for id in its:
			out.items[id] = int(its[id])
		n_ess = int(lv.get("essence", 0))
	if essence != "" and n_ess > 0:
		out.items[essence] = int(out.items.get(essence, 0)) + n_ess
	out.ok = true
	return out


## Encanta a arma equipada com `element`: sobe um nível (mesmo elemento ou arma sem encanto)
## ou troca o elemento mantendo o nível. Sem chance de falha: tendo os recursos, acontece.
static func enchant(s: CharState, bt: BalanceTables, element: String) -> Dictionary:
	var c := cost(s, bt, element)
	if not c.ok:
		return CharRules._fail(c.err)
	if s.gold < c.gold:
		return CharRules._fail("sem_ouro")
	if s.ecos < c.ecos:
		return CharRules._fail("sem_ecos")
	for id in c.items:
		if CharRules.count_item(s, id) < int(c.items[id]):
			return CharRules._fail("sem_material")
	s.gold -= int(c.gold)
	s.ecos -= int(c.ecos)
	for id in c.items:
		CharRules.remove_item(s, id, int(c.items[id]))
	var wid: String = s.equipment.weapon
	s.enchants[wid] = {"el": element, "lv": int(c.to)}
	var wname: String = CharRules._item(bt, wid).get("name", wid)
	var ename: String = _table(bt).elements[element].get("name", element)
	return CharRules._ok([
		{"t": "enchant", "id": wid, "el": element, "lv": int(c.to)},
		CharRules._notify("%s: %s +%d" % [wname, ename, int(c.to)], CharRules.C_GOLD),
	])


## Bônus do encanto da arma equipada, no formato dos `mods` do Game: {"damage": fração}. Sem encanto: {}.
static func mods(s: CharState, bt: BalanceTables) -> Dictionary:
	var dmg: Array = _table(bt).get("damage", [])
	var cur := of(s, s.equipment.get("weapon", ""))
	if cur.lv <= 0 or dmg.is_empty():
		return {}
	return {"damage": float(dmg[mini(cur.lv, dmg.size()) - 1])}
