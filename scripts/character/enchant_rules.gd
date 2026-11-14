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


# ================================================================ efeitos dos elementos
## Efeito do elemento no nível dado: {"el", "value"} mais os campos fixos da tabela ("secs", "mult",
## "radius"). O significado de "value" depende do elemento: fogo = fração do dano do golpe que vira
## queimadura; gelo = segundos de lentidão; raio = chance de corrente; veneno = dano extra que o alvo
## marcado recebe; sagrado = dano extra em chefes e elites; sombra = fração do dano que vira cura.
## Sem efeito (nível 0, elemento desconhecido, tabela sem "effects"): {}.
static func effect(bt: BalanceTables, element: String, level: int) -> Dictionary:
	if level <= 0:
		return {}
	var def: Dictionary = _table(bt).get("effects", {}).get(element, {})
	var values: Array = def.get("values", [])
	if values.is_empty():
		return {}
	var out := def.duplicate()
	out.erase("values")
	out["el"] = element
	out["value"] = float(values[mini(level, values.size()) - 1])
	return out


## Maior valor do efeito de um elemento (o servidor usa para limitar o que o cliente manda). 0 se não há.
static func max_effect(bt: BalanceTables, element: String) -> float:
	var values: Array = _table(bt).get("effects", {}).get(element, {}).get("values", [])
	var m := 0.0
	for v in values:
		m = maxf(m, float(v))
	return m


## Número para texto: inteiro sem casas, senão uma casa com vírgula ("30", "1,5").
static func _num(v: float) -> String:
	if absf(v - roundf(v)) < 0.005:
		return str(int(roundf(v)))
	return ("%.1f" % v).replace(".", ",")


## O efeito em uma frase, para o painel do ferreiro e a dica do item. Sem efeito: "".
static func effect_text(bt: BalanceTables, element: String, level: int) -> String:
	var fx := effect(bt, element, level)
	if fx.is_empty():
		return ""
	var v: float = fx.value
	match element:
		"fogo":
			return "Queimadura: %s%% do dano em %s s" % [_num(v * 100.0), _num(float(fx.get("secs", 3)))]
		"gelo":
			return "Lentidão por %s s" % _num(v)
		"raio":
			return "Corrente: %s%% de chance de saltar a outro inimigo" % _num(v * 100.0)
		"veneno":
			return "Marca tóxica: alvo recebe +%s%% de dano por %s s" % [_num(v * 100.0), _num(float(fx.get("secs", 4)))]
		"sagrado":
			return "+%s%% de dano em chefes e elites" % _num(v * 100.0)
		"sombra":
			return "Cura %s%% do dano causado" % _num(v * 100.0)
	return ""
