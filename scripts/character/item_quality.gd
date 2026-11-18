class_name ItemQuality
extends RefCounted
## Qualidade de craft (pura): normal, fina e obra-prima. A qualidade vai no id do item com sufixo
## ("iron_sword@fina"), porque inventário e equipamento guardam só ids. As variantes são entradas de verdade na
## tabela de itens, geradas a partir do item base quando as tabelas carregam (expand): dano, defesa, bônus e preço
## multiplicados por data/balance/progression.json "quality_mult". Encanto e receitas usam o id base (base()).
## Bônus de craft (afixo): equipamento raro ou acima sai com um atributo sorteado, também no id, depois da
## qualidade: "knight_blade@fina~urso" = base[@qualidade][~afixo]. Números em progression.json "craft_affix".

const SEP := "@"
const AFFIX_SEP := "~"
const LEVELS := ["fina", "obra"]
const NAMES := {"fina": "Fina", "obra": "Obra-prima"}


## Id sem qualidade nem afixo ("iron_sword@fina~urso" -> "iron_sword").
static func base(id: String) -> String:
	var i := id.find(SEP)
	var j := id.find(AFFIX_SEP)
	if i < 0 or (j >= 0 and j < i):
		i = j
	return id if i < 0 else id.substr(0, i)


## Qualidade do id ("" = normal).
static func quality(id: String) -> String:
	var i := id.find(SEP)
	if i < 0:
		return ""
	var j := id.find(AFFIX_SEP, i)
	return id.substr(i + 1) if j < 0 else id.substr(i + 1, j - i - 1)


## Afixo do id ("" = sem bônus de craft).
static func affix(id: String) -> String:
	var j := id.find(AFFIX_SEP)
	return "" if j < 0 else id.substr(j + 1)


## Monta o id a partir das partes.
static func make(base_id: String, q: String, affix_id := "") -> String:
	var id := base(base_id)
	if q != "":
		id += SEP + q
	if affix_id != "":
		id += AFFIX_SEP + affix_id
	return id


## Id da variante de qualidade (`q` = "" devolve o normal); o afixo do id é mantido.
static func variant(id: String, q: String) -> String:
	return make(id, q, affix(id))


## Item que pode ter qualidade: equipamento (arma, armadura, peça) que sai de uma receita fora da cozinha.
static func can_have(item: Dictionary) -> bool:
	return str(item.get("type", "")) in ["weapon", "armor", "gear"] and not item.get("stack", false)


## Afixos possíveis ({id: {"name", "stat", "base", "per_level"}}).
static func affixes(prog: Dictionary) -> Dictionary:
	return prog.get("craft_affix", {}).get("affixes", {})


## Se o equipamento sai com bônus sorteado: só as raridades de craft_affix.rarities.
static func affix_allowed(item: Dictionary, prog: Dictionary) -> bool:
	var rar: Array = prog.get("craft_affix", {}).get("rarities", [])
	return can_have(item) and not affixes(prog).is_empty() and str(item.get("rarity", "common")) in rar


## Valor do bônus para uma receita de nível `level`: inteiro (pelo menos 1) quando "base" é inteiro, senão fração.
static func affix_value(def: Dictionary, level: int):
	var b = def.get("base", 0)
	var v := float(b) + float(def.get("per_level", 0.0)) * level
	if typeof(b) == TYPE_INT or (typeof(b) == TYPE_FLOAT and b >= 1.0):
		return maxi(1, roundi(v))
	return float("%.3f" % v)


## A tabela de itens com as variantes de qualidade e de afixo de todo equipamento fabricável (idempotente:
## variantes já presentes são refeitas a partir do base). `recipes` = recipes.json; `prog` = progression.json.
static func expand(items: Dictionary, recipes: Dictionary, prog: Dictionary) -> Dictionary:
	var mult: Dictionary = prog.get("quality_mult", {})
	if mult.is_empty():
		return items
	var afx := affixes(prog)
	var price_mult := float(prog.get("craft_affix", {}).get("price_mult", 1.0))
	var out := {}
	for id in items:
		if base(id) == id:
			out[id] = items[id]
	var seen := {}
	for rid in recipes:
		var r: Dictionary = recipes[rid]
		var oid := str(r.get("out", rid))
		if str(r.get("station", "kitchen")) == "kitchen" or seen.has(oid) or not out.has(oid) or not can_have(out[oid]):
			continue
		seen[oid] = true
		var bases := {"": out[oid]}
		if affix_allowed(out[oid], prog):
			for a in afx:
				bases[a] = _with_affix(out[oid], oid, a, afx[a], int(r.get("level", 1)), price_mult)
				out[make(oid, "", a)] = bases[a]
		for q in LEVELS:
			if mult.has(q):
				for a in bases:
					out[make(oid, q, a)] = _scaled(bases[a], oid, q, float(mult[q]))
	return out


## O item base com o bônus do afixo somado aos atributos.
static func _with_affix(item: Dictionary, base_id: String, a: String, def: Dictionary, level: int, price_mult: float) -> Dictionary:
	var v := item.duplicate(true)
	var stat := str(def.get("stat", ""))
	var val = affix_value(def, level)
	var st: Dictionary = v.get("stats", {})
	st[stat] = (st[stat] + val) if st.has(stat) else val
	if typeof(st[stat]) == TYPE_FLOAT:
		st[stat] = float("%.3f" % st[stat])
	v["stats"] = st
	v["affix"] = a
	v["affix_stat"] = stat
	v["affix_value"] = val
	v["affix_name"] = str(def.get("name", a))
	v["base_name"] = str(item.get("name", ""))
	v["name"] = "%s %s" % [v.base_name, v.affix_name]
	v["art"] = str(item.get("art", base_id))
	if v.has("price"):
		v["price"] = _mul(v.price, price_mult)
	return v


static func _scaled(item: Dictionary, base_id: String, q: String, m: float) -> Dictionary:
	var v := item.duplicate(true)
	# "Lâmina do Cavaleiro Fina da Águia": a qualidade vem antes do afixo
	v["name"] = " ".join([str(item.get("base_name", item.get("name", ""))), str(NAMES.get(q, q)),
		str(item.get("affix_name", ""))]).strip_edges()
	v["quality"] = q
	v["art"] = str(item.get("art", base_id))
	for k in ["damage", "defense", "price", "affix_value"]:
		if v.has(k):
			v[k] = _mul(v[k], m)
	if v.get("stats") is Dictionary:
		var st: Dictionary = v.stats
		for k in st:
			st[k] = _mul(st[k], m)
	return v


## Inteiro continua inteiro (arredondado, nunca menor que o base); fração é multiplicada.
static func _mul(x, m: float):
	if typeof(x) == TYPE_INT:
		return maxi(x, roundi(x * m)) if x > 0 else x
	if typeof(x) == TYPE_FLOAT:
		return float("%.3f" % (x * m))   # pelo texto: o mesmo double que volta do JSON da rede
	return x
