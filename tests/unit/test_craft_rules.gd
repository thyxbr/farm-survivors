extends RefCounted
## Profissões e craft (CraftRules, ItemQuality): XP e nível, fabricar, recusas, qualidade, pergaminhos, save.

var _base: BalanceTables


## Tabelas reais + uma receita de forja de teste (espada de ferro, nível 5) e o pergaminho dela.
func _tables() -> BalanceTables:
	if _base == null:
		_base = BalanceTables.load_dir("res://data/balance")
	var d := _base.to_dict()
	d.recipes["t_sword"] = {"station": "forge", "prof": "smithing", "level": 5, "ingredients": {"iron_ore": 2},
		"gold": 10, "out": "iron_sword", "qty": 1, "xp": 20, "learn": "npc"}
	d.recipes["t_secret"] = {"station": "forge", "prof": "smithing", "level": 1, "ingredients": {"iron_ore": 1},
		"gold": 0, "out": "iron_sword", "qty": 1, "xp": 5, "learn": "scroll"}
	d.items["t_scroll"] = {"name": "Pergaminho", "type": "scroll", "recipe": "t_secret", "price": 10, "stack": true}
	return BalanceTables.from_dict(d)


func _char(bt: BalanceTables) -> CharState:
	var s := CharState.new_character(bt)
	s.gold = 1000
	return s


func test_curve_and_level_up() -> void:
	var bt := _tables()
	var s := _char(bt)
	T.eq(CraftRules.level(s, "smithing"), 1, "começa no nível 1")
	var need := CraftRules.xp_to_next(bt, 1)
	T.ok(need > 0 and CraftRules.xp_to_next(bt, 10) > need, "a curva sobe")
	T.eq(CraftRules.xp_to_next(bt, CraftRules.max_level(bt)), 0, "no 50 não há próximo")
	var ev := CraftRules.gain(s, bt, "smithing", need, 1)
	T.eq(CraftRules.level(s, "smithing"), 2, "sobe com a XP exata")
	T.ok(ev.any(func(e: Dictionary) -> bool: return e.get("t") == "notify"), "avisa o nível novo")
	T.eq(CraftRules.gain(s, bt, "dancar", 50, 1).size(), 0, "profissão desconhecida não ganha")


func test_xp_drops_far_below() -> void:
	var bt := _tables()
	T.eq(CraftRules.diff_mult(bt, 20, 20), 1.0, "mesmo nível: 100%")
	T.ok(CraftRules.diff_mult(bt, 5, 20) < 0.2, "15 níveis abaixo: quase nada")
	T.ok(CraftRules.diff_mult(bt, 14, 20) < 1.0, "6 abaixo: menos")


func test_craft_spends_and_gives() -> void:
	var bt := _tables()
	var s := _char(bt)
	s.professions["smithing"] = {"lv": 5, "xp": 0, "done": []}
	CharRules.add_item(s, bt, "iron_ore", 5)
	var r := CraftRules.craft(s, bt, "t_sword", 2, null)
	T.ok(r.ok and r.n == 2, "fabricou duas")
	T.eq(CharRules.count_item(s, "iron_ore"), 1, "gastou 4 minérios")
	T.eq(s.gold, 980, "gastou 20 de ouro")
	T.eq(CharRules.count_item(s, "iron_sword"), 2, "duas espadas (sem rng = normal)")
	# primeira vez: 3x a XP de uma (20 * 2 + 20 * 2 extra)
	T.eq(CraftRules.xp(s, "smithing"), 80, "XP com o bônus da primeira vez")
	CharRules.add_item(s, bt, "iron_ore", 1)
	CraftRules.craft(s, bt, "t_sword", 1, null)
	T.eq(CraftRules.xp(s, "smithing"), 100, "segunda vez: XP normal")


func test_refusals_keep_state() -> void:
	var bt := _tables()
	var s := _char(bt)
	CharRules.add_item(s, bt, "iron_ore", 5)
	var inv := s.inventory.duplicate(true)
	T.eq(CraftRules.craft(s, bt, "t_sword", 1, null).err, "nivel", "nível de profissão baixo")
	s.professions["smithing"] = {"lv": 5, "xp": 0, "done": []}
	T.eq(CraftRules.craft(s, bt, "nada", 1, null).err, "receita_invalida", "receita que não existe")
	T.eq(CraftRules.craft(s, bt, "t_secret", 1, null).err, "desconhecida", "receita de pergaminho sem aprender")
	T.eq(CraftRules.craft(s, bt, "t_sword", 0, null).err, "args", "zero vezes")
	T.eq(CraftRules.craft(s, bt, "t_sword", 100000, null).err, "args", "vezes absurdas")
	s.gold = 5
	T.eq(CraftRules.craft(s, bt, "t_sword", 1, null).err, "ouro", "sem ouro")
	s.gold = 1000
	CharRules.remove_item(s, "iron_ore", 4)
	inv = s.inventory.duplicate(true)
	T.eq(CraftRules.craft(s, bt, "t_sword", 1, null).err, "faltam_ingredientes", "falta minério")
	T.eq(s.inventory, inv, "recusa não mexe na mochila")
	T.eq(s.gold, 1000, "recusa não mexe no ouro")


func test_quality_variants_and_odds() -> void:
	var bt := _tables()
	var items := bt.get_table("items")
	T.ok(items.has("iron_sword@fina") and items.has("iron_sword@obra"), "variantes da espada fabricável")
	T.ok(int(items["iron_sword@obra"].damage) > int(items["iron_sword@fina"].damage)
		and int(items["iron_sword@fina"].damage) > int(items["iron_sword"].damage), "obra > fina > normal")
	T.ok(not items.has("bread@fina"), "comida não tem qualidade")
	T.eq(ItemQuality.base("iron_sword@fina"), "iron_sword", "base")
	T.eq(ItemQuality.quality("iron_sword@obra"), "obra", "qualidade")
	T.eq(CraftRules.quality_odds(bt, 5, 5), Vector2.ZERO, "no nível da receita: só normal")
	var hi := CraftRules.quality_odds(bt, 25, 5)
	T.ok(hi.x > 0.3 and hi.y > 0.0 and hi.y < hi.x, "bem acima: chance de fina e de obra-prima")
	var s := _char(bt)
	s.professions["smithing"] = {"lv": 40, "xp": 0, "done": []}
	CharRules.add_item(s, bt, "iron_ore", 80)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	CraftRules.craft(s, bt, "t_sword", 40, rng)
	var better := CharRules.count_item(s, "iron_sword@fina") + CharRules.count_item(s, "iron_sword@obra")
	T.ok(better > 4 and better < 30, "parte sai melhor (%d de 40)" % better)
	# encanto segue o item base; a variante equipa e volta do save
	s.level = 10
	s.char_class = "warrior"
	T.ok(CharRules.equip(s, bt, "iron_sword@fina").ok if CharRules.count_item(s, "iron_sword@fina") > 0 else true, "equipa a fina")
	s.enchants["iron_sword"] = {"el": "fogo", "lv": 2}
	T.eq(EnchantRules.of(s, "iron_sword@fina").lv, 2, "encanto do item base")
	var back := CharState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())), bt)
	T.eq(CharRules.count_item(back, "iron_sword@obra"), CharRules.count_item(s, "iron_sword@obra"), "variante volta do save")


func test_scroll_teaches() -> void:
	var bt := _tables()
	var s := _char(bt)
	CharRules.add_item(s, bt, "t_scroll", 1)
	var r := CharRules.consume(s, bt, "t_scroll", 0.0)
	T.ok(r.ok and "t_secret" in s.recipes, "usar o pergaminho ensina")
	T.eq(CharRules.count_item(s, "t_scroll"), 0, "o pergaminho some")
	T.ok(CraftRules.knows(s, bt, "t_secret"), "agora conhece")
	CharRules.add_item(s, bt, "t_scroll", 1)
	T.eq(CharRules.consume(s, bt, "t_scroll", 0.0).err, "ja_conhece", "não aprende duas vezes")
	T.eq(CharRules.count_item(s, "t_scroll"), 1, "e não gasta o segundo")


func test_save_roundtrip_and_old_save() -> void:
	var bt := _tables()
	var s := _char(bt)
	s.professions["mining"] = {"lv": 7, "xp": 33, "done": ["t_sword"]}
	s.recipes = ["t_secret"]
	var back := CharState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())), bt)
	T.eq(back.professions.mining.lv, 7, "nível volta")
	T.eq(back.professions.mining.xp, 33, "XP volta")
	T.eq(back.recipes, ["t_secret"], "receitas aprendidas voltam")
	var old := s.to_dict()
	old.erase("professions")
	old.erase("recipes")
	var o := CharState.from_dict(old, bt)
	T.eq(o.professions, {}, "save antigo: sem profissões")
	T.eq(CraftRules.level(o, "mining"), 1, "save antigo: nível 1")
	var bad := s.to_dict()
	bad.professions = {"mining": {"lv": 999, "xp": -5}, "voar": {"lv": 3}}
	bad.recipes = ["nao_existe", "t_secret", "t_secret"]
	var b := CharState.from_dict(bad, bt)
	T.eq(b.professions.mining.lv, CraftRules.max_level(bt), "nível limitado ao máximo")
	T.eq(b.professions.mining.xp, 0, "XP negativa vira 0")
	T.ok(not b.professions.has("voar"), "profissão desconhecida sai")
	T.eq(b.recipes, ["t_secret"], "receita desconhecida e repetida saem")


func test_cook_is_kitchen_craft() -> void:
	var bt := _tables()
	var s := _char(bt)
	CharRules.add_item(s, bt, "wheat", 4)
	var r := CharRules.cook(s, bt, "bread", 2)
	T.ok(r.ok and r.n == 2, "cozinhou dois pães")
	T.ok(CraftRules.xp(s, "cooking") > 0, "cozinhar dá XP de Culinária")
	T.eq(CharRules.cook(s, bt, "t_sword", 1).err, "receita_invalida", "cook não fabrica receita de forja")


## Catálogo do craft (recipes.json): cada camada tem arma de cada classe e peça de cada espaço de armadura;
## receitas apontam para itens que existem; a ponta de cada camada pede a peça do chefe e é por pergaminho.
func test_recipe_catalog() -> void:
	var bt := BalanceTables.load_dir("res://data/balance")
	var items := bt.get_table("items")
	var rt := bt.get_table("recipes")
	var tiers := [[1, 10], [11, 20], [21, 30], [31, 40], [41, 50]]
	var pieces := ["goblin_crown", "royal_jelly", "knight_sigil", "lich_phylactery", "abyss_core"]
	for t in tiers.size():
		var got := {}
		for rid in rt:
			var r: Dictionary = rt[rid]
			if int(r.level) < tiers[t][0] or int(r.level) > tiers[t][1] or r.station == "kitchen":
				continue
			var it: Dictionary = items.get(str(r.out), {})
			if it.get("type") == "weapon":
				got["w_" + str(it["class"])] = true
			elif it.get("type") == "armor":
				got["armor"] = true
			elif it.get("type") == "gear":
				got[str(it.get("slot", ""))] = true
		for need in ["w_sword", "w_bow", "w_staff", "w_scepter", "armor", "head", "hands", "feet"]:
			T.ok(got.has(need), "camada %d tem %s fabricável" % [t + 1, need])
	var scrolls := {}
	for id in items:
		if items[id].get("type") == "scroll":
			scrolls[str(items[id].recipe)] = id
	for rid in rt:
		var r: Dictionary = rt[rid]
		T.ok(items.has(str(r.out)), "%s fabrica um item que existe" % rid)
		for i in r.ingredients:
			T.ok(items.has(i), "%s: ingrediente %s existe" % [rid, i])
		T.ok(bt.get_table("professions").professions.has(str(r.prof)), "%s: profissão existe" % rid)
		if r.learn == "scroll":
			T.ok(scrolls.has(rid), "%s tem pergaminho" % rid)
		for t in pieces.size():
			if r.ingredients.has(pieces[t]):
				T.eq(r.learn, "scroll", "%s (com peça de chefe) é por pergaminho" % rid)
	for t in pieces.size():
		var used := false
		for rid in rt:
			used = used or (rt[rid].ingredients as Dictionary).has(pieces[t])
		T.ok(used, "a peça %s é pedida por alguma receita de ponta" % pieces[t])
	# loja só com o básico
	for id in bt.get_table("shop").stock:
		var it: Dictionary = items[id]
		var ok_item: bool = it.type in ["consumable", "seed"] or id in ["copper_ore", "pine_log", "hide_t1"] \
			or (it.type in ["weapon", "armor", "gear"] and it.get("rarity") == "common" and int(it.get("level", 1)) <= 10)
		T.ok(ok_item, "loja só com o básico (%s)" % id)
	# variante de qualidade e item só de craft não caem de monstro
	for id in LootRules.gear_pool(bt, 46):
		T.ok(LootRules.droppable(items[id], id), "%s pode cair" % id)
