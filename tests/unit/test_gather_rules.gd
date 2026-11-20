extends RefCounted
## Ferramentas de coleta e maestria (GatherRules) com as tabelas reais.

var _bt: BalanceTables


func _items() -> Dictionary:
	if _bt == null:
		_bt = BalanceTables.load_dir("res://data/balance")
	return _bt.get_table("items")


func test_tools_in_table() -> void:
	var items := _items()
	var recipes := _bt.get_table("recipes")
	for kind in ["pickaxe", "axe"]:
		var last := 0.0
		for t in 5:
			var id := "%s_%s" % [kind, ["stone", "iron", "mithril", "crystal", "astral"][t]]
			T.ok(GatherRules.is_tool_item(items, id), "%s é ferramenta" % id)
			T.eq(GatherRules.tier(items, id), t + 1, "nível de %s" % id)
			T.eq(str(items[id].tool), kind, "tipo de %s" % id)
			var p := float(items[id].power)
			T.ok(p > last, "%s bate mais forte que o nível de baixo" % id)
			last = p
			T.ok(ResourceLoader.exists("res://assets/models/%s.glb" % items[id].model), "modelo de %s" % id)
			if t > 0:
				T.ok(recipes.has(id), "%s sai da forja" % id)
	T.ok("pickaxe_stone" in _bt.get_table("shop").stock and "axe_stone" in _bt.get_table("shop").stock,
		"o mercador vende as de pedra")


## Cada nível de ferramenta é forjado com o que o nível de baixo consegue coletar (sem beco sem saída).
func test_recipes_use_lower_tier_materials() -> void:
	var items := _items()
	var recipes := _bt.get_table("recipes")
	var kinds: Dictionary = _bt.get_table("world_nodes").kinds
	var need_tier := {}   # item coletado -> nível de ferramenta que o nó pede
	for k in kinds:
		need_tier[str(kinds[k].item)] = int(kinds[k].tier)
	for id in items:
		if not GatherRules.is_tool_item(items, id) or not recipes.has(id):
			continue
		for ing in recipes[id].ingredients:
			if need_tier.has(ing):
				T.ok(need_tier[ing] < GatherRules.tier(items, id), "%s pede %s, que sai com ferramenta mais fraca" % [id, ing])


func test_best_tool() -> void:
	var items := _items()
	var inv := [{"id": "pickaxe_stone", "qty": 1}, {"id": "axe_iron", "qty": 1}, {"id": "pickaxe_crystal", "qty": 1},
		{"id": "iron_ore", "qty": 5}]
	T.eq(GatherRules.best_tool(items, inv, "pickaxe"), "pickaxe_crystal", "a melhor picareta")
	T.eq(GatherRules.best_tool(items, inv, "axe"), "axe_iron", "o único machado")
	T.eq(GatherRules.best_tool(items, [], "axe"), "", "mochila vazia")
	T.eq(GatherRules.tool_kind("mining"), "pickaxe", "Mineração usa picareta")
	T.eq(GatherRules.tool_kind("woodcutting"), "axe", "Lenhador usa machado")
	T.eq(GatherRules.tool_kind("farming"), "", "horta sem ferramenta")


## O pedido: árvore simples sai muito mais fácil com a de cristal do que com a de pedra; a maestria ajuda.
func test_strikes_by_tier_and_mastery() -> void:
	var items := _items()
	var pine := float(_bt.get_table("world_nodes").kinds.pine.tough)
	var stone := GatherRules.strikes(pine, GatherRules.hit_power(items, "axe_stone", 1))
	var crystal := GatherRules.strikes(pine, GatherRules.hit_power(items, "axe_crystal", 1))
	T.eq(stone, 6, "pinheiro: 6 golpes com machado de pedra")
	T.eq(crystal, 2, "pinheiro: 2 golpes com machado de cristal")
	var master := GatherRules.strikes(pine, GatherRules.hit_power(items, "axe_stone", 30))
	T.ok(master < stone, "maestria 30 corta com menos golpes (%d)" % master)
	T.ok(GatherRules.swing_time(5, 50) < GatherRules.swing_time(1, 1), "ferramenta melhor e maestria: golpe mais rápido")
	T.ok(GatherRules.swing_time(5, 50) >= GatherRules.SWING_MIN, "ritmo tem piso")
	T.eq(GatherRules.mastery_mult(1), 1.0, "maestria 1 sem bônus")
	T.eq(GatherRules.strikes(5.0, 0.0), 0, "sem força não conta golpes")
	T.eq(GatherRules.hit_power(items, "iron_ore", 10), 0.0, "minério não é ferramenta")


func test_check() -> void:
	var items := _items()
	T.ok(GatherRules.check(items, "pickaxe_stone", "pickaxe", 1).ok, "pedra serve no nível 1")
	T.eq(GatherRules.check(items, "pickaxe_stone", "pickaxe", 2).err, "ferramenta_fraca", "pedra não serve no 2")
	T.eq(GatherRules.check(items, "axe_crystal", "pickaxe", 1).err, "sem_ferramenta", "machado não minera")
	T.eq(GatherRules.check(items, "", "axe", 1).err, "sem_ferramenta", "sem ferramenta")
	T.ok(GatherRules.check(items, "", "", 1).ok, "nó sem profissão não pede ferramenta")
	T.ok(GatherRules.refusal_text(items, "ferramenta_fraca", "pickaxe", 2).contains("Picareta de Ferro"),
		"aviso diz qual ferramenta falta")


## Personagem de antes das ferramentas ganha as de pedra uma vez (quem já tem do tipo não ganha outra).
func test_migrate_tools() -> void:
	_items()
	# personagem de antes de tudo: a picareta da mochila vai para o espaço; sem machado, ganha o de pedra equipado
	var s := CharState.new()
	s.equipment = CharRules.empty_equipment()
	s.inventory = [{"id": "pickaxe_iron", "qty": 1}, {"id": "pickaxe_stone", "qty": 1}]
	T.ok(CharRules.migrate_tools(s, _bt), "migrou")
	T.eq(s.equipment.pickaxe, "pickaxe_iron", "a melhor picareta da mochila foi equipada")
	T.eq(CharRules.count_item(s, "pickaxe_iron"), 0, "e saiu da mochila")
	T.eq(CharRules.count_item(s, "pickaxe_stone"), 1, "a de pedra fica na mochila")
	T.eq(s.equipment.axe, "axe_stone", "sem machado: ganha o de pedra equipado")
	T.ok(not CharRules.migrate_tools(s, _bt), "só uma vez")
	# personagem da versão anterior (ferramentas na mochila, flag 1): equipa, não dá outra
	var v1 := CharState.new()
	v1.equipment = CharRules.empty_equipment()
	v1.flags["tools_v"] = true
	v1.inventory = [{"id": "axe_stone", "qty": 1}]
	CharRules.migrate_tools(v1, _bt)
	T.eq(v1.equipment.axe, "axe_stone", "v1: o machado da mochila foi equipado")
	T.eq(v1.equipment.pickaxe, "", "v1 que vendeu a picareta: não ganha outra")
	var fresh := CharState.new_character(_bt)
	T.ok(not CharRules.migrate_tools(fresh, _bt), "personagem novo já nasce com as de pedra")
	T.eq([fresh.equipment.pickaxe, fresh.equipment.axe], ["pickaxe_stone", "axe_stone"], "kit de pedra equipado")


## Picareta e machado têm espaço próprio: equipar e desequipar.
func test_tool_slots() -> void:
	_items()
	var s := CharState.new_character(_bt)
	T.eq(CharRules.slot_of(_bt, "pickaxe_crystal"), "pickaxe", "picareta vai no espaço da picareta")
	T.eq(CharRules.slot_of(_bt, "axe_iron"), "axe", "machado vai no espaço do machado")
	CharRules.add_item(s, _bt, "axe_iron", 1)
	T.ok(CharRules.equip(s, _bt, "axe_iron").ok, "equipa o machado de ferro")
	T.eq(s.equipment.axe, "axe_iron", "no espaço")
	T.eq(CharRules.count_item(s, "axe_stone"), 1, "o de pedra voltou para a mochila")
