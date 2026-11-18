extends RefCounted
## BalanceTables: os JSON em data/balance têm que devolver exatamente o que as antigas `const` tinham.

const DIR := "res://data/balance"
const SNAPSHOT := "res://tests/unit/fixtures/balance_snapshot.bin"


## Tabelas do snapshot que não existem mais.
const REMOVED := ["colony"]


func _snapshot() -> Dictionary:
	var f := FileAccess.open(SNAPSHOT, FileAccess.READ)
	var snap = bytes_to_var(f.get_buffer(f.get_length()))
	f.close()
	return snap


func test_roundtrip_matches_consts() -> void:
	var t := BalanceTables.load_dir(DIR)
	var snap := _snapshot()
	# tabelas que saíram do jogo (a Defesa da Cidade) continuam no snapshot binário: ficam de fora
	for gone in REMOVED:
		snap.erase(gone)
	# o snapshot da fase 1 não tem as tabelas novas (Ecos, passivas, base): basta cada nome dele existir
	for n in snap:
		T.ok(n in BalanceTables.NAMES, "tabela %s do snapshot está em NAMES" % n)
	for n in snap:
		T.ok(not t.get_table(n).is_empty(), "tabela %s carregou" % n)
		# o snapshot tem 40.0 onde o JSON devolve 40 (decode troca float inteiro por int), então
		# normaliza o snapshot com a mesma regra antes do == profundo (que distingue int de float)
		var cur: Dictionary = t.get_table(n)
		if n == "enemies":
			# campos de progressão (ref_level) nasceram depois do snapshot: compara sem eles
			cur = cur.duplicate(true)
			for kind in cur:
				(cur[kind] as Dictionary).erase("ref_level")
			# o loot foi enxugado (equipamento vem do sorteio por nível): compara o resto, dos dois lados
			var snap_enemies: Dictionary = (BalanceTables.decode(snap[n]) as Dictionary).duplicate(true)
			for kind in cur:
				(cur[kind] as Dictionary).erase("loot")
				(snap_enemies[kind] as Dictionary).erase("loot")
				(snap_enemies[kind] as Dictionary).erase("ref_level")   # snapshot regravado já traz o campo
			T.ok(cur == snap_enemies, "tabela enemies igual ao snapshot das const (sem loot)")
			continue
		elif n == "items":
			# o nível de equipar (level) nasceu depois do snapshot: compara sem ele; recompensas de missão
			# rebaixadas de nível ganharam `named` (saem do sorteio de equipamento): sem ele onde o snapshot não tem
			cur = cur.duplicate(true)
			var snap_items: Dictionary = (BalanceTables.decode(snap[n]) as Dictionary).duplicate(true)
			# parte 3 (craft): variantes de qualidade, materiais, pergaminhos e itens novos não existiam no
			# snapshot; os de antes continuam iguais
			for id in cur.keys():
				if not snap_items.has(id):
					cur.erase(id)
			for id in cur:
				(cur[id] as Dictionary).erase("level")
				if snap_items.has(id) and not (snap_items[id] as Dictionary).has("named"):
					(cur[id] as Dictionary).erase("named")
			# o Cutelo do Rei Goblin passou para o nível do chefe, com o dano das armas de lá: sem o dano dele
			(cur["goblin_cleaver"] as Dictionary).erase("damage")
			(snap_items["goblin_cleaver"] as Dictionary).erase("damage")
			T.ok(cur == snap_items, "tabela items igual ao snapshot (sem level e o dano do Cutelo)")
			continue
		elif n == "quests":
			# o nível da missão e o XP pela fatia do nível nasceram depois do snapshot: compara sem eles
			cur = cur.duplicate(true)
			var snap_quests: Dictionary = (BalanceTables.decode(snap[n]) as Dictionary).duplicate(true)
			for id in cur:
				(cur[id] as Dictionary).erase("level")
				(cur[id] as Dictionary).erase("reward_xp")
				(snap_quests[id] as Dictionary).erase("reward_xp")
				# regiões com nome (parte 2): a missão cita a região e o objetivo perdeu o "onde"
				if (cur[id] as Dictionary).has("region"):
					(cur[id] as Dictionary).erase("region")
					(cur[id] as Dictionary).erase("objective")
					(snap_quests[id] as Dictionary).erase("objective")
			T.ok(cur == snap_quests, "tabela quests igual ao snapshot (sem level, reward_xp e region)")
			continue
		elif n == "recipes":
			# o recipes.json passou a cobrir todas as estações (parte 3): a cozinha de antes é a visão
			# {receita: ingredientes} das receitas da estação "kitchen"
			var kitchen := {}
			for rid in CraftRules.station_recipes(t, "kitchen"):
				kitchen[rid] = CraftRules.ingredients(t, rid)
			T.ok(kitchen == BalanceTables.decode(snap[n]), "receitas da cozinha iguais ao snapshot")
			continue
		elif n == "crops" or n == "world_nodes":
			# parte 3: nível e XP de profissão nas culturas e nos nós; tipos de nó novos; coleta em 2-3 golpes
			var snap_t: Dictionary = (BalanceTables.decode(snap[n]) as Dictionary).duplicate(true)
			var cur_t: Dictionary = cur.duplicate(true)
			var a: Dictionary = cur_t if n == "crops" else cur_t.get("kinds", {})
			var b: Dictionary = snap_t if n == "crops" else snap_t.get("kinds", {})
			for k in a.keys():
				if not b.has(k):
					a.erase(k)
					continue
				for f in ["level", "xp", "prof", "hits", "tint"]:
					(a[k] as Dictionary).erase(f)
					(b[k] as Dictionary).erase(f)
			T.ok(a == b, "tabela %s igual ao snapshot (sem os campos de profissão)" % n)
			continue
		elif n == "shop":
			# a loja foi cortada ao básico na parte 3 (decisão do usuário na revisão da progressão):
			# o que sobrou estava na loja de antes ou é material/semente da camada 1
			var old_stock: Array = (BalanceTables.decode(snap[n]) as Dictionary).get("stock", [])
			for id in cur.get("stock", []):
				T.ok(id in old_stock or id == "wooden_sword" or t.get_table("items").get(id, {}).get("type") in ["seed", "material"],
					"loja: %s estava antes ou é semente/material" % id)
			continue
		elif n == "rules":
			# a curva de XP foi para progression.json
			cur = cur.duplicate(true)
			var snap_rules: Dictionary = (BalanceTables.decode(snap[n]) as Dictionary).duplicate(true)
			snap_rules.erase("xp_curve")
			# o raio do sono dos monstros (regiões cheias, parte 2) nasceu depois do snapshot
			cur.erase("enemy_sleep_radius")
			T.ok(cur == snap_rules, "tabela rules igual ao snapshot (sem xp_curve e enemy_sleep_radius)")
			continue
		T.ok(cur == BalanceTables.decode(snap[n]), "tabela %s igual ao snapshot das const" % n)


func test_ints_stay_int() -> void:
	var t := BalanceTables.load_dir(DIR)
	T.eq(typeof(t.get_table("items")["health_potion"].price), TYPE_INT, "price é int")
	T.eq(typeof(t.get_table("progression")["xp_curve"]["base"]), TYPE_INT, "base da curva é int")
	T.eq(typeof(t.get_table("rules")["sell_ratio"]), TYPE_FLOAT, "0.5 continua float")


func test_color_and_vector() -> void:
	var t := BalanceTables.load_dir(DIR)
	T.eq(typeof(t.get_table("items")["wooden_sword"].color), TYPE_COLOR, "cor do item")
	T.eq(t.get_table("enemies")["slime"].color, Color(0.3, 0.9, 0.35), "cor do slime")
	T.eq(BalanceTables.decode({"$v3": [1, 2.5, 3]}), Vector3(1, 2.5, 3), "decode Vector3")
	T.eq(BalanceTables.decode(BalanceTables.encode(Color(0.1, 0.2, 0.3, 0.4))), Color(0.1, 0.2, 0.3, 0.4), "Color ida e volta")


func test_from_dict_and_set_table() -> void:
	var t := BalanceTables.from_dict({"items": {"x": {"price": 3}}})
	T.eq(t.get_table("items")["x"].price, 3, "from_dict")
	T.eq(t.get_table("nada"), {}, "tabela inexistente é vazia")
	t.set_table("items", {"y": 1})
	T.eq(t.to_dict()["items"], {"y": 1}, "set_table/to_dict")


func test_to_dict_from_dict_roundtrip() -> void:
	var t := BalanceTables.load_dir(DIR)
	var again := BalanceTables.from_dict(t.to_dict())
	T.ok(again.to_dict() == t.to_dict(), "to_dict -> from_dict -> to_dict idêntico")
	T.ok(again.get_table("items") == t.get_table("items"), "itens idênticos")


func test_json_wire_roundtrip() -> void:
	# o que o servidor fará: encode -> texto JSON -> parse -> decode
	var t := BalanceTables.load_dir(DIR)
	var wire := JSON.stringify(BalanceTables.encode(t.to_dict()))
	var back = BalanceTables.decode(JSON.parse_string(wire))
	T.ok(back is Dictionary, "JSON da rede volta Dictionary")
	T.ok(back == t.to_dict(), "encode -> JSON -> decode preserva todas as tabelas")


func test_malformed_tags_do_not_crash() -> void:
	for bad in [{"$c": [1, 2]}, {"$v3": "x"}, {"$v2": [1, 2, 3]}, {"$c": ["a", "b", "c"]}, {"$v3": null}]:
		T.eq(BalanceTables.decode(bad), bad, "tag malformada devolve o valor cru")
	T.eq(BalanceTables.decode({"a": {"$v2": [1]}}), {"a": {"$v2": [1]}}, "tag ruim aninhada")


func test_enchant_table() -> void:
	var bt := BalanceTables.load_dir(DIR)
	var e: Dictionary = bt.get_table("enchant")
	var items: Dictionary = bt.get_table("items")
	T.eq(e.get("max_level"), 5, "nível máximo")
	T.eq(e.get("damage"), [0.05, 0.10, 0.16, 0.23, 0.30], "bônus de dano por nível")
	T.eq(e.get("elements", {}).keys(), ["fogo", "gelo", "raio", "veneno", "sagrado", "sombra"], "seis elementos, em ordem")
	T.eq(e.get("levels", []).size(), 5, "um custo por nível")
	for el in e.get("elements", {}):
		T.ok(items.has(e.elements[el].essence), "essência de %s existe em items" % el)
	for id in ["iron_ore", "arcane_crystal", "champion_badge"]:
		T.ok(items.get(id, {}).get("type") == "material" and items.get(id, {}).get("stack", false), "%s é material empilhável" % id)
	for lv in e.get("levels", []):
		for id in lv.get("items", {}):
			T.ok(items.has(id), "item de custo %s existe" % id)


## Todo elemento tem um monstro que solta a essência, e a Insígnia do Campeão (+4) também tem fonte.
func test_essence_sources() -> void:
	var bt := BalanceTables.load_dir(DIR)
	var elements: Dictionary = bt.get_table("enchant").get("elements", {})
	var enemies: Dictionary = bt.get_table("enemies")
	var wanted := {"champion_badge": "insígnia"}
	for el in elements:
		wanted[elements[el].essence] = el
	T.eq(wanted.size(), 7, "seis essências e a insígnia")
	for item in wanted:
		var found := false
		for kind in enemies:
			for entry in enemies[kind].get("loot", []):
				found = found or (entry[0] == item and float(entry[1]) > 0.0)
		T.ok(found, "algum monstro solta %s (%s)" % [item, wanted[item]])
