class_name CraftRules
extends RefCounted
## Profissões e craft, regras puras (servidor e solo rodam o mesmo código; ver CharRules). Sem autoload.
##   s.professions = {prof: {"lv": int, "xp": int, "done": [receitas já feitas uma vez]}}
##   s.recipes     = [receitas aprendidas por pergaminho]
## Números: data/balance/professions.json (curva, ajuste por diferença, bônus da primeira vez) e
## data/balance/recipes.json (estação, profissão, nível, ingredientes, ouro, item, XP, como se aprende).
## Qualidade (fina/obra-prima): progression.json "quality_chance"; o item sai com o sufixo de ItemQuality.
## Bônus sorteado (raro ou acima) e chance de falha por raridade: progression.json "craft_affix" e "craft_fail".

const C_PROF := Color(0.75, 0.95, 0.6)


static func _table(bt: BalanceTables) -> Dictionary:
	return bt.get_table("professions")


static func professions(bt: BalanceTables) -> Dictionary:
	return _table(bt).get("professions", {})


static func recipe(bt: BalanceTables, rid: String) -> Dictionary:
	return bt.get_table("recipes").get(rid, {})


## Ingredientes da receita ({item: qtd}).
static func ingredients(bt: BalanceTables, rid: String) -> Dictionary:
	return recipe(bt, rid).get("ingredients", {})


## Receitas de uma estação, na ordem do arquivo.
static func station_recipes(bt: BalanceTables, station: String) -> Array:
	var out: Array = []
	var rt: Dictionary = bt.get_table("recipes")
	for rid in rt:
		if str(rt[rid].get("station", "")) == station:
			out.append(rid)
	return out


static func max_level(bt: BalanceTables) -> int:
	return int(_table(bt).get("max_level", 50))


static func level(s: CharState, prof: String) -> int:
	return int(s.professions.get(prof, {}).get("lv", 1))


static func xp(s: CharState, prof: String) -> int:
	return int(s.professions.get(prof, {}).get("xp", 0))


## XP para passar do nível `lv` (0 no máximo).
static func xp_to_next(bt: BalanceTables, lv: int) -> int:
	if lv >= max_level(bt):
		return 0
	var c: Dictionary = _table(bt).get("xp_curve", {})
	return maxi(1, roundi(float(c.get("base", 20)) * pow(float(maxi(lv, 1)), float(c.get("exp", 1.3)))))


## Multiplicador de XP pela diferença (nível da receita/nó − nível da profissão): bem abaixo rende quase nada.
static func diff_mult(bt: BalanceTables, src_level: int, prof_level: int) -> float:
	var d := src_level - prof_level
	for row in _table(bt).get("xp_diff", []):
		if d >= int(row[0]) and d <= int(row[1]):
			return float(row[2])
	return 1.0


static func _entry(s: CharState, prof: String) -> Dictionary:
	if not s.professions.has(prof):
		s.professions[prof] = {"lv": 1, "xp": 0, "done": []}
	return s.professions[prof]


## Ganho de XP da profissão por uma ação de nível `src_level` (receita ou nó). Sobe de nível quantas vezes
## der. Devolve os eventos (aviso de nível novo). Profissão desconhecida não ganha nada.
static func gain(s: CharState, bt: BalanceTables, prof: String, base_xp: int, src_level: int) -> Array:
	var ev: Array = []
	if not professions(bt).has(prof) or base_xp <= 0:
		return ev
	var e := _entry(s, prof)
	if int(e.lv) >= max_level(bt):
		return ev
	var amount := maxi(1, roundi(base_xp * diff_mult(bt, src_level, int(e.lv))))
	e.xp = int(e.xp) + amount
	var name := str(professions(bt)[prof].get("name", prof))
	while int(e.lv) < max_level(bt) and int(e.xp) >= xp_to_next(bt, int(e.lv)):
		e.xp = int(e.xp) - xp_to_next(bt, int(e.lv))
		e.lv = int(e.lv) + 1
		ev.append(CharRules._notify("%s subiu para o nível %d!" % [name, int(e.lv)], C_PROF))
	if int(e.lv) >= max_level(bt):
		e.xp = 0
	ev.append({"t": "prof_xp", "prof": prof, "xp": amount})
	return ev


## Se o personagem conhece a receita: as de NPC todos conhecem; as de pergaminho, só quem aprendeu.
static func knows(s: CharState, bt: BalanceTables, rid: String) -> bool:
	var r := recipe(bt, rid)
	if r.is_empty():
		return false
	return str(r.get("learn", "npc")) != "scroll" or rid in s.recipes


## Quantas vezes dá para fabricar agora e, se nenhuma, por quê:
## {"n", "err"}: "receita_invalida", "desconhecida", "nivel", "faltam_ingredientes", "ouro".
static func can_craft(s: CharState, bt: BalanceTables, rid: String) -> Dictionary:
	var r := recipe(bt, rid)
	if r.is_empty():
		return {"n": 0, "err": "receita_invalida"}
	if not knows(s, bt, rid):
		return {"n": 0, "err": "desconhecida"}
	if level(s, str(r.get("prof", ""))) < int(r.get("level", 1)):
		return {"n": 0, "err": "nivel"}
	var n := CharRules.MAX_COUNT
	var ing: Dictionary = r.get("ingredients", {})
	for id in ing:
		n = mini(n, CharRules.count_item(s, id) / maxi(int(ing[id]), 1))
	if n <= 0:
		return {"n": 0, "err": "faltam_ingredientes"}
	var gold := int(r.get("gold", 0))
	if gold > 0:
		n = mini(n, s.gold / gold)
		if n <= 0:
			return {"n": 0, "err": "ouro"}
	return {"n": n, "err": ""}


## Qualidade sorteada: a chance de sair melhor cresce com quanto o nível da profissão passa o da receita.
## "" (normal), "fina" ou "obra".
static func quality_roll(bt: BalanceTables, prof_level: int, recipe_level: int, rng: RandomNumberGenerator) -> String:
	var q: Dictionary = bt.get_table("progression").get("quality_chance", {})
	var better := clampf((prof_level - recipe_level) * float(q.get("per_level", 0.0)), 0.0, float(q.get("max", 0.0)))
	var roll := rng.randf() if rng != null else 1.0
	if roll < better * float(q.get("obra_share", 0.0)):
		return "obra"
	if roll < better:
		return "fina"
	return ""


## Chances de (fina ou melhor) e de obra-prima, para a tela.
static func quality_odds(bt: BalanceTables, prof_level: int, recipe_level: int) -> Vector2:
	var q: Dictionary = bt.get_table("progression").get("quality_chance", {})
	var better := clampf((prof_level - recipe_level) * float(q.get("per_level", 0.0)), 0.0, float(q.get("max", 0.0)))
	return Vector2(better, better * float(q.get("obra_share", 0.0)))


## Se a receita faz equipamento (pode sair com qualidade, bônus sorteado e pode falhar).
static func makes_gear(bt: BalanceTables, rid: String) -> bool:
	var r := recipe(bt, rid)
	return not r.is_empty() and str(r.get("station", "")) != "kitchen" \
		and ItemQuality.can_have(bt.get_table("items").get(str(r.get("out", rid)), {}))


## Chance de a fabricação falhar (0..1): cresce com a raridade do equipamento (progression.json "craft_fail") e
## cai `per_level` por nível da profissão acima da receita, nunca abaixo de `floor` × a chance da raridade.
## Só equipamento falha.
static func fail_chance(bt: BalanceTables, rid: String, prof_level: int) -> float:
	if not makes_gear(bt, rid):
		return 0.0
	var r := recipe(bt, rid)
	var f: Dictionary = bt.get_table("progression").get("craft_fail", {})
	var rar := str(bt.get_table("items").get(str(r.get("out", rid)), {}).get("rarity", "common"))
	var top := float(f.get("chance", {}).get(rar, 0.0))
	var over := maxi(prof_level - int(r.get("level", 1)), 0)
	return clampf(top - over * float(f.get("per_level", 0.0)), top * float(f.get("floor", 1.0)), 1.0)


## Se o equipamento da receita sai com um bônus sorteado (ItemQuality.affix_allowed).
static func has_affix(bt: BalanceTables, rid: String) -> bool:
	return makes_gear(bt, rid) and ItemQuality.affix_allowed(
		bt.get_table("items").get(str(recipe(bt, rid).get("out", rid)), {}), bt.get_table("progression"))


## Fabrica até `times` vezes. Resultado como o de CharRules.cook: "n" = quantas saíram e "fail" = quantas
## falharam. Equipamento sai com qualidade e, se raro ou acima, com um bônus sorteado; pode falhar (fail_chance):
## na falha o ouro é gasto, volta `craft_fail.refund` de cada material (a sobra ímpar é sorteada) e a XP vale
## `craft_fail.xp_mult`. Sem `rng` nada falha e nada é sorteado. Ingredientes e ouro só saem quando dá para fazer
## pelo menos uma.
static func craft(s: CharState, bt: BalanceTables, rid: String, times = 1, rng: RandomNumberGenerator = null) -> Dictionary:
	if not CharRules._valid_count(times):
		return CharRules._fail("args")
	var c := can_craft(s, bt, rid)
	if int(c.n) <= 0:
		var msg := {"receita_invalida": "", "desconhecida": "Você ainda não conhece esta receita.",
			"nivel": "Nível de profissão insuficiente.", "faltam_ingredientes": "Faltam ingredientes.",
			"ouro": "Ouro insuficiente."}
		var r := CharRules._fail(str(c.err), [] if str(msg.get(c.err, "")) == "" else
			[CharRules._notify(str(msg[c.err]), CharRules.C_BAD)])
		r["n"] = 0
		return r
	var rec := recipe(bt, rid)
	var n: int = mini(int(times), int(c.n))
	var ing: Dictionary = rec.get("ingredients", {})
	for id in ing:
		CharRules.remove_item(s, id, int(ing[id]) * n)
	s.gold -= int(rec.get("gold", 0)) * n
	var out := str(rec.get("out", rid))
	var qty := maxi(1, int(rec.get("qty", 1)))
	var prof := str(rec.get("prof", ""))
	var rlv := int(rec.get("level", 1))
	var prog: Dictionary = bt.get_table("progression")
	var gear := makes_gear(bt, rid)
	var fail_p := fail_chance(bt, rid, level(s, prof)) if rng != null else 0.0
	var affix_ids: Array = ItemQuality.affixes(prog).keys() if rng != null and has_affix(bt, rid) else []
	var refund := float(prog.get("craft_fail", {}).get("refund", 0.0))
	var ev: Array = []
	var got := {}
	var back := {}
	var made := 0
	for i in n:
		if fail_p > 0.0 and rng.randf() < fail_p:
			for id in ing:
				var q := float(int(ing[id])) * refund
				var b := int(floorf(q))
				if q - b > 0.0 and rng.randf() < q - b:
					b += 1
				if b > 0:
					back[id] = int(back.get(id, 0)) + b
			continue
		made += 1
		var id := out
		if gear:
			var a := str(affix_ids[rng.randi() % affix_ids.size()]) if not affix_ids.is_empty() else ""
			id = ItemQuality.make(out, quality_roll(bt, level(s, prof), rlv, rng), a)
		CharRules.add_item(s, bt, id, qty)
		got[id] = int(got.get(id, 0)) + qty
	for id in got:
		ev.append({"t": "looted", "id": id, "qty": got[id]})
	var failed := n - made
	if failed > 0:
		for id in back:
			CharRules.add_item(s, bt, id, int(back[id]))
		ev.append({"t": "craft_fail", "n": failed, "back": back})
	var e := _entry(s, prof) if professions(bt).has(prof) else {}
	var one := int(rec.get("xp", 0))
	var base_xp := one * made + roundi(one * failed * float(prog.get("craft_fail", {}).get("xp_mult", 0.0)))
	if made > 0 and not e.is_empty() and not rid in (e.get("done", []) as Array):
		(e.done as Array).append(rid)
		base_xp += one * (int(_table(bt).get("first_craft_mult", 1)) - 1)
	ev.append_array(gain(s, bt, prof, base_xp, rlv))
	var res := CharRules._ok(ev)
	res["n"] = made
	res["fail"] = failed
	return res


## Aprende a receita do pergaminho `scroll_id` (o item some). Pergaminho = item com "recipe".
static func learn(s: CharState, bt: BalanceTables, scroll_id: String) -> Dictionary:
	var it: Dictionary = bt.get_table("items").get(scroll_id, {})
	var rid := str(it.get("recipe", ""))
	if rid == "" or recipe(bt, rid).is_empty():
		return CharRules._fail("item_invalido")
	if CharRules.count_item(s, scroll_id) < 1:
		return CharRules._fail("sem_item")
	if rid in s.recipes:
		return CharRules._fail("ja_conhece", [CharRules._notify("Você já conhece esta receita.", CharRules.C_BAD)])
	CharRules.remove_item(s, scroll_id, 1)
	s.recipes.append(rid)
	var out_name := str(bt.get_table("items").get(str(recipe(bt, rid).get("out", rid)), {}).get("name", rid))
	return CharRules._ok([CharRules._notify("Receita aprendida: %s" % out_name, C_PROF), {"t": "recipes"}])
