extends RefCounted
## ItemIconModels: todo item de data/balance tem ícone 3D, pelo modelo de equipamento ou pelo modelo
## da família (poção, anel, semente...), e o arquivo do modelo da família existe.

const DIR := "res://data/balance"


func _tables() -> BalanceTables:
	return BalanceTables.load_dir(DIR)


func test_every_item_has_a_3d_icon() -> void:
	var t := _tables()
	var items := t.get_table("items")
	var crops := t.get_table("crops")
	T.ok(items.size() > 40, "a tabela de itens carregou")
	for id: String in items:
		if ItemIconModels.is_gear(items[id]):
			T.ok(ItemIconModels.spec(id, items, crops).is_empty(), "%s usa o modelo de equipamento, não o da família" % id)
			continue
		var s := ItemIconModels.spec(id, items, crops)
		T.ok(not s.is_empty(), "%s tem modelo de família" % id)
		if s.is_empty():
			continue
		T.ok(FileAccess.file_exists(s.model), "%s: o arquivo %s existe" % [id, s.model])
		T.eq(typeof(s.tint), TYPE_COLOR, "%s tem cor" % id)
		T.ok(s.tint.a > 0.99 and s.tint.v > 0.15, "%s: cor opaca e visível sobre o papel" % id)


func test_gear_split() -> void:
	var items := _tables().get_table("items")
	for id in ["iron_sword", "ember_staff", "elven_bow", "iron_helm", "mage_robe", "iron_gauntlets", "swift_boots", "knight_shield"]:
		T.ok(ItemIconModels.is_gear(items[id]), "%s é montado como equipamento" % id)
	for id in ["arcane_orb", "hunter_quiver", "life_amulet", "vampire_ring", "health_potion", "slime_gel", "bread"]:
		T.ok(not ItemIconModels.is_gear(items[id]), "%s não tem modelo de equipamento" % id)


func test_families_share_a_model_and_change_color() -> void:
	var t := _tables()
	var items := t.get_table("items")
	var crops := t.get_table("crops")
	var hp := ItemIconModels.spec("health_potion", items, crops)
	var mp := ItemIconModels.spec("mana_potion", items, crops)
	T.eq(hp.model, mp.model, "as duas poções dividem o frasco")
	T.ok(hp.tint.r > hp.tint.b and mp.tint.b > mp.tint.r, "vida vermelha, mana azul")
	var rings := {}
	for id in ["strength_ring", "wind_ring", "vampire_ring"]:
		var s := ItemIconModels.spec(id, items, crops)
		rings[s.model] = true
		T.eq(s.tint, items[id].color, "%s: a pedra tem a cor do item" % id)
	T.eq(rings.size(), 1, "os anéis dividem um modelo")
	var seeds := {}
	for crop: String in crops:
		var s := ItemIconModels.spec(crops[crop].seed, items, crops)
		seeds[s.model] = true
		T.eq(s.tint, crops[crop].color, "semente de %s tem a cor da cultura" % crop)
		T.eq(ItemIconModels.spec(crop, items, crops).tint, crops[crop].color, "%s colhido tem a cor da cultura" % crop)
	T.eq(seeds.size(), 1, "as sementes dividem o saquinho")
	var stew := ItemIconModels.spec("carrot_stew", items, crops)
	var soup := ItemIconModels.spec("spicy_soup", items, crops)
	T.eq(stew.model, soup.model, "ensopado e sopa dividem a tigela")
	T.ok(stew.tint != soup.tint, "com caldos de cores diferentes")


func test_unknown_item_has_no_spec() -> void:
	var t := _tables()
	T.ok(ItemIconModels.spec("nao_existe", t.get_table("items"), t.get_table("crops")).is_empty(), "id desconhecido devolve vazio")


func test_material_without_entry_falls_back_to_generic() -> void:
	var items := {"new_goo": {"type": "material", "name": "Gosma nova"}}
	var s := ItemIconModels.spec("new_goo", items, {})
	T.ok(not s.is_empty() and FileAccess.file_exists(s.model), "material novo cai num modelo genérico que existe")


func test_low_wide_models_are_seen_from_above() -> void:
	var t := _tables()
	var items := t.get_table("items")
	var crops := t.get_table("crops")
	T.eq(ItemIconModels.spec("pumpkin_pie", items, crops).view, ItemIconModels.VIEW_TOP, "torta é vista mais de cima")
	T.eq(ItemIconModels.spec("health_potion", items, crops).view, ItemIconModels.VIEW_FRONT, "poção é vista de frente")
