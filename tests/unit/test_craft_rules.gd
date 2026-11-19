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
			or (it.type in ["weapon", "armor", "gear"] and it.get("rarity") == "common" and int(it.get("level", 1)) <= 10) 			or (it.type == "tool" and int(it.get("tier", 0)) == 1)
		T.ok(ok_item, "loja só com o básico (%s)" % id)
	# variante de qualidade e item só de craft não caem de monstro
	for id in LootRules.gear_pool(bt, 46):
		T.ok(LootRules.droppable(items[id], id), "%s pode cair" % id)


## Coleta: pede o nível da profissão do nó, dá os itens e a XP; a horta pede nível de Fazenda e dá XP.
func test_gathering_and_farming_xp() -> void:
	var bt := BalanceTables.load_dir("res://data/balance")
	var s := CharState.new_character(bt)
	var g := {"items": {"silver_ore": 3}, "prof": "mining", "level": 20, "xp": 45}
	var r := CharRules.gather(s, bt, g)
	T.eq(r.err, "nivel", "prata pede Mineração 20")
	T.eq(CharRules.count_item(s, "silver_ore"), 0, "recusa não dá minério")
	r = CharRules.gather(s, bt, {"items": {"copper_ore": 3}, "prof": "mining", "level": 1, "xp": 12})
	T.ok(r.ok and CharRules.count_item(s, "copper_ore") == 3, "cobre no nível 1")
	T.eq(CraftRules.xp(s, "mining"), 12, "XP de Mineração")
	# ferramenta: o nó pede picareta/machado do nível dele equipado
	r = CharRules.gather(s, bt, {"items": {"arcane_crystal": 1}, "prof": "mining", "level": 1, "xp": 25, "tier": 2})
	T.eq(r.err, "ferramenta_fraca", "cristal pede picareta de ferro; só tem a de pedra")
	CharRules.add_item(s, bt, "pickaxe_iron", 1)
	T.eq(CharRules.gather(s, bt, {"items": {"arcane_crystal": 1}, "prof": "mining", "level": 1, "xp": 25, "tier": 2}).err,
		"ferramenta_fraca", "a de ferro só na mochila não conta")
	T.ok(CharRules.equip(s, bt, "pickaxe_iron").ok, "equipa a de ferro")
	T.ok(CharRules.gather(s, bt, {"items": {"arcane_crystal": 1}, "prof": "mining", "level": 1, "xp": 25, "tier": 2}).ok,
		"com a de ferro coleta")
	s.equipment.axe = ""
	r = CharRules.gather(s, bt, {"items": {"pine_log": 3}, "prof": "woodcutting", "level": 1, "xp": 12, "tier": 1})
	T.eq(r.err, "sem_ferramenta", "sem machado não corta")
	T.eq(CharRules.count_item(s, "pine_log"), 0, "recusa não dá madeira")
	# nós por camada nas cenas: cada tipo da tabela tem pelo menos um nó
	var kinds := {}
	for id in WorldHarvest.ids(bt):
		kinds[WorldHarvest.node_def(bt, id).kind] = true
	for k in bt.get_table("world_nodes").kinds:
		T.ok(kinds.has(k), "nó de %s em algum mapa" % k)
	# horta
	var crops := bt.get_table("crops")
	T.ok(int(crops.pumpkin.level) > 1, "abóbora pede nível de Fazenda")
	CharRules.add_item(s, bt, "seed_pumpkin", 1)
	T.eq(CharRules.plant(s, bt, 0, "pumpkin", false, 0.0).err, "nivel", "sem nível não planta abóbora")
	T.ok(CharRules.plant(s, bt, 0, "carrot", true, 0.0).ok, "cenoura no nível 1")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var h := CharRules.harvest(s, bt, 0, 99999.0, rng)
	T.ok(h.ok and CraftRules.xp(s, "farming") > 0, "colher dá XP de Fazenda")


## Receitas de teste: lâmina rara (nível 17) e uma peça lendária, as duas de forja.
func _gear_tables() -> BalanceTables:
	var d := _tables().to_dict()
	d.recipes["t_rare"] = {"station": "forge", "prof": "smithing", "level": 17, "ingredients": {"iron_ore": 4, "oak_log": 1},
		"gold": 10, "out": "knight_blade", "qty": 1, "xp": 20, "learn": "npc"}
	d.recipes["t_legend"] = {"station": "forge", "prof": "smithing", "level": 35, "ingredients": {"mithril_ore": 6},
		"gold": 5, "out": "dragon_plate", "qty": 1, "xp": 40, "learn": "npc"}
	return BalanceTables.from_dict(d)


func test_id_parts() -> void:
	T.eq(ItemQuality.base("knight_blade@fina~urso"), "knight_blade", "base com tudo")
	T.eq(ItemQuality.base("knight_blade~urso"), "knight_blade", "base só com afixo")
	T.eq(ItemQuality.quality("knight_blade@obra~aguia"), "obra", "qualidade com afixo")
	T.eq(ItemQuality.quality("knight_blade~aguia"), "", "sem qualidade")
	T.eq(ItemQuality.affix("knight_blade@obra~aguia"), "aguia", "afixo")
	T.eq(ItemQuality.affix("knight_blade@obra"), "", "sem afixo")
	T.eq(ItemQuality.make("knight_blade", "fina", "urso"), "knight_blade@fina~urso", "monta")
	T.eq(ItemQuality.variant("knight_blade~urso", "obra"), "knight_blade@obra~urso", "variante mantém o afixo")


func test_affix_variants() -> void:
	var bt := _gear_tables()
	var items: Dictionary = bt.get_table("items")
	var base: Dictionary = items["knight_blade"]
	T.eq(str(items["iron_sword@fina"].get("art", "")), "iron_sword", "qualidade usa a arte do base")
	T.ok(not items.has("iron_sword~urso"), "comum não tem afixo")
	for a in ["urso", "touro", "coruja", "raposa", "aguia", "lebre", "tartaruga", "morcego"]:
		for q in ["", "fina", "obra"]:
			T.ok(items.has(ItemQuality.make("knight_blade", q, a)), "existe %s %s" % [q, a])
	var urso: Dictionary = items["knight_blade~urso"]
	T.eq(int(urso.stats.vit), int(base.stats.vit) + 2, "Urso no nível 17: +2 de vitalidade")
	T.eq(int(urso.affix_value), 2, "valor do bônus guardado")
	T.eq(str(urso.name), "%s do Urso" % base.name, "nome com o afixo")
	T.eq(str(items["knight_blade@fina~urso"].name), "%s Fina do Urso" % base.name, "qualidade antes do afixo")
	T.ok(int(items["knight_blade@obra~urso"].stats.vit) > int(urso.stats.vit), "a qualidade multiplica o bônus")
	T.ok(int(urso.price) > int(base.price), "vale mais")
	T.ok(not items["knight_blade~aguia"].stats.has("vit") or int(items["knight_blade~aguia"].stats.vit) == int(base.stats.vit), "Águia não mexe na vitalidade")
	T.ok(float(items["knight_blade~aguia"].stats.crit) > 0.02, "Águia dá crítico")
	T.ok(not LootRules.droppable(urso, "knight_blade~urso"), "item com afixo não cai de monstro")
	# idempotente: expandir de novo não muda nada
	T.eq(BalanceTables.from_dict(bt.to_dict()).get_table("items").size(), items.size(), "expand idempotente")
	# save com item de afixo e de qualidade antiga continua valendo
	var s := _char(bt)
	CharRules.add_item(s, bt, "knight_blade@fina~urso", 1)
	CharRules.add_item(s, bt, "iron_sword@fina", 1)
	var s2 := CharState.from_dict(s.to_dict(), bt)
	T.eq(CharRules.count_item(s2, "knight_blade@fina~urso"), 1, "afixo sobrevive ao save")
	T.eq(CharRules.count_item(s2, "iron_sword@fina"), 1, "id antigo de qualidade continua valendo")


func test_fail_chance() -> void:
	var bt := _gear_tables()
	T.eq(CraftRules.fail_chance(bt, "t_sword", 5), 0.0, "comum não falha")
	T.eq(CraftRules.fail_chance(bt, "essence_t4", 31), 0.0, "material não falha")
	T.ok(absf(CraftRules.fail_chance(bt, "t_rare", 17) - 0.15) < 0.0001, "raro no nível da receita: 15%")
	T.ok(absf(CraftRules.fail_chance(bt, "t_rare", 22) - 0.10) < 0.0001, "5 níveis acima: 10%")
	T.ok(absf(CraftRules.fail_chance(bt, "t_rare", 50) - 0.06) < 0.0001, "piso de 40% da chance")
	T.ok(absf(CraftRules.fail_chance(bt, "t_legend", 35) - 0.35) < 0.0001, "lendário: 35%")
	T.ok(CraftRules.has_affix(bt, "t_rare") and not CraftRules.has_affix(bt, "t_sword"), "só raro+ tem bônus")


func test_craft_can_fail_and_refunds_half() -> void:
	var bt := _gear_tables()
	var s := _char(bt)
	s.professions["smithing"] = {"lv": 35, "xp": 0, "done": []}
	CharRules.add_item(s, bt, "mithril_ore", 360)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var r := CraftRules.craft(s, bt, "t_legend", 60, rng)
	T.ok(r.ok, "o pedido vale mesmo com falhas")
	T.eq(int(r.n) + int(r.fail), 60, "sucessos + falhas = tentativas")
	T.ok(int(r.fail) >= 10 and int(r.fail) <= 32, "perto de 35%% de falha (%d)" % int(r.fail))
	T.eq(s.gold, 1000 - 300, "o ouro é gasto também na falha")
	T.eq(CharRules.count_item(s, "mithril_ore"), int(r.fail) * 3, "metade do material de cada falha volta")
	var plates := 0
	var with_affix := 0
	for slot in s.inventory:
		if ItemQuality.base(str(slot.id)) == "dragon_plate":
			plates += int(slot.qty)
			with_affix += int(slot.qty) if ItemQuality.affix(str(slot.id)) != "" else 0
	T.eq(plates, int(r.n), "uma peça por sucesso")
	T.eq(with_affix, plates, "todo lendário sai com bônus")
	var fe: Array = (r.events as Array).filter(func(e: Dictionary) -> bool: return e.get("t") == "craft_fail")
	T.ok(fe.size() == 1 and int(fe[0].n) == int(r.fail) and int(fe[0].back.get("mithril_ore", 0)) == int(r.fail) * 3, "evento de falha com o que voltou")
	# quantidade ímpar: a unidade que sobra volta às vezes
	var s2 := _char(bt)
	s2.professions["smithing"] = {"lv": 17, "xp": 0, "done": []}
	CharRules.add_item(s2, bt, "iron_ore", 400)
	CharRules.add_item(s2, bt, "oak_log", 99)
	var r2 := CraftRules.craft(s2, bt, "t_rare", 99, rng)
	var logs := CharRules.count_item(s2, "oak_log")
	T.ok(int(r2.fail) > 3 and logs > 0 and logs < int(r2.fail), "sobra ímpar volta em parte (%d de %d)" % [logs, int(r2.fail)])
	T.eq(CharRules.count_item(s2, "iron_ore"), 400 - 99 * 4 + int(r2.fail) * 2, "metade exata do par")


func test_all_fail_and_no_rng() -> void:
	var d := _gear_tables().to_dict()
	d.progression["craft_fail"]["chance"]["legendary"] = 1.0
	d.progression["craft_fail"]["floor"] = 1.0
	var bt := BalanceTables.from_dict(d)
	var s := _char(bt)
	s.professions["smithing"] = {"lv": 35, "xp": 0, "done": []}
	CharRules.add_item(s, bt, "mithril_ore", 12)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var r := CraftRules.craft(s, bt, "t_legend", 2, rng)
	T.ok(r.ok and int(r.n) == 0 and int(r.fail) == 2, "tudo falhou: ok com n = 0")
	T.eq(CharRules.count_item(s, "mithril_ore"), 6, "metade voltou")
	T.eq(CharRules.count_item(s, "dragon_plate"), 0, "nada saiu")
	T.eq(CraftRules.xp(s, "smithing"), 40, "XP pela metade e sem bônus de primeira vez")
	T.ok(not "t_legend" in (s.professions.smithing.done as Array), "falha não conta como primeira vez")
	# sem rng: nunca falha, sem bônus
	var r2 := CraftRules.craft(s, bt, "t_legend", 1, null)
	T.ok(r2.ok and int(r2.n) == 1 and int(r2.fail) == 0, "sem rng não falha")
	T.eq(CharRules.count_item(s, "dragon_plate"), 1, "sem rng sai o item base")
