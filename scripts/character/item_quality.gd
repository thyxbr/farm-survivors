class_name ItemQuality
extends RefCounted
## Qualidade de craft (pura): normal, fina e obra-prima. A qualidade vai no id do item com sufixo
## ("iron_sword@fina"), porque inventário e equipamento guardam só ids. As variantes são entradas de verdade na
## tabela de itens, geradas a partir do item base quando as tabelas carregam (expand): dano, defesa, bônus e preço
## multiplicados por data/balance/progression.json "quality_mult". Encanto e receitas usam o id base (base()).

const SEP := "@"
const LEVELS := ["fina", "obra"]
const NAMES := {"fina": "Fina", "obra": "Obra-prima"}


## Id sem a qualidade ("iron_sword@fina" -> "iron_sword").
static func base(id: String) -> String:
	var i := id.find(SEP)
	return id if i < 0 else id.substr(0, i)


## Qualidade do id ("" = normal).
static func quality(id: String) -> String:
	var i := id.find(SEP)
	return "" if i < 0 else id.substr(i + 1)


## Id da variante (`q` = "" devolve o base).
static func variant(id: String, q: String) -> String:
	return base(id) if q == "" else "%s%s%s" % [base(id), SEP, q]


## Item que pode ter qualidade: equipamento (arma, armadura, peça) que sai de uma receita fora da cozinha.
static func can_have(item: Dictionary) -> bool:
	return str(item.get("type", "")) in ["weapon", "armor", "gear"] and not item.get("stack", false)


## A tabela de itens com as variantes de qualidade de todo equipamento fabricável (idempotente: variantes já
## presentes são refeitas a partir do base). `recipes` = recipes.json; `prog` = progression.json.
static func expand(items: Dictionary, recipes: Dictionary, prog: Dictionary) -> Dictionary:
	var mult: Dictionary = prog.get("quality_mult", {})
	if mult.is_empty():
		return items
	var out := {}
	for id in items:
		if quality(id) == "":
			out[id] = items[id]
	for rid in recipes:
		var r: Dictionary = recipes[rid]
		var oid := str(r.get("out", rid))
		if str(r.get("station", "kitchen")) == "kitchen" or not out.has(oid) or not can_have(out[oid]):
			continue
		for q in LEVELS:
			if mult.has(q):
				out[variant(oid, q)] = _scaled(out[oid], q, float(mult[q]))
	return out


static func _scaled(item: Dictionary, q: String, m: float) -> Dictionary:
	var v := item.duplicate(true)
	v["name"] = "%s %s" % [str(item.get("name", "")), NAMES.get(q, q)]
	v["quality"] = q
	for k in ["damage", "defense", "price"]:
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
		return snappedf(x * m, 0.001)
	return x
