extends RefCounted
## Dungeons (parte 4): população por jogadores, volta do chefe, loot extra, onde ficam e por onde se sai.

var _bt: BalanceTables


func _tables() -> BalanceTables:
	if _bt == null:
		_bt = BalanceTables.load_dir("res://data/balance")
	return _bt


func test_population_grows_with_players() -> void:
	var bt := _tables()
	T.eq(DungeonRules.population(bt, 4, 1), 4, "sozinho: a base")
	T.eq(DungeonRules.population(bt, 4, 0), 4, "ninguém dentro conta como 1")
	T.ok(DungeonRules.population(bt, 4, 2) > 4, "dois jogadores: mais monstros")
	var top := DungeonRules.max_population(bt, 4)
	T.eq(DungeonRules.population(bt, 4, 50), top, "muitos jogadores: no teto")
	T.ok(top >= 4 and top <= 4 * 3, "teto = base × max_mult")


func test_respawn() -> void:
	var bt := _tables()
	T.eq(DungeonRules.respawn(bt, 30.0, 1, false), 30.0, "sozinho: o tempo do ponto")
	T.ok(DungeonRules.respawn(bt, 30.0, 3, false) < 30.0, "com mais gente volta mais rápido")
	T.eq(DungeonRules.respawn(bt, 30.0, 1, true),
		float(bt.get_table("progression").dungeons.boss_respawn) * 60.0, "chefe volta em minutos")


func test_extra_loot_items_exist() -> void:
	var bt := _tables()
	var items := bt.get_table("items")
	for d in Regions.DUNGEONS:
		var boss := DungeonRules.extra_loot(bt, d, true)
		T.ok(not boss.is_empty(), "%s tem loot de chefe" % d)
		T.ok(not DungeonRules.extra_loot(bt, d, false).is_empty(), "%s tem loot extra dos monstros" % d)
		for e in boss + DungeonRules.extra_loot(bt, d, false):
			T.ok(items.has(e[0]), "%s: %s existe" % [d, e[0]])
	T.eq(DungeonRules.extra_loot(bt, "vila", true), [], "fora de dungeon: nada extra")
	# a peça do chefe da camada é garantida no chefe da dungeon
	var pieces := {"dg_bosque": "royal_jelly", "dg_mina": "knight_sigil", "dg_pico": "lich_phylactery", "dg_final": "abyss_core"}
	for d in pieces:
		T.ok(DungeonRules.extra_loot(bt, d, true).any(func(e: Array) -> bool: return e[0] == pieces[d] and float(e[1]) >= 1.0),
			"%s garante %s" % [d, pieces[d]])


func test_regions_and_doors() -> void:
	for d in Regions.DUNGEONS:
		T.ok(Regions.is_dungeon(d), "%s é dungeon" % d)
		T.eq(Regions.region_at(Regions.origin(d)), d, "o centro de %s fica nela" % d)
		T.ok(not d in Regions.ORDER, "%s fora da carruagem" % d)
		var door := Regions.door_point(d)
		T.ok(door != Vector3.ZERO, "%s tem porta no mapa de fora" % d)
		T.eq(Regions.region_at(door), Regions.parent_of(d), "a porta de %s fica no %s" % [d, Regions.parent_of(d)])
		T.ok(Regions.exit_point(d) != Vector3.ZERO and Regions.region_at(Regions.exit_point(d)) == d, "%s: saída lá dentro" % d)
		T.eq(MapRules.to_atlas(Regions.origin(d)), MapRules.to_atlas(door), "%s no atlas = a porta" % d)
	T.eq(Regions.exit_point("mina"), Regions.coach_point("mina"), "nos mapas a saída é a carruagem")
	T.eq(DungeonRules.players_in("dg_mina", [Regions.origin("dg_mina"), Vector3.ZERO, Regions.origin("mina")]), 1,
		"um jogador dentro da Mina profunda")
	var names: Array = MapRules.places("bosque").map(func(p: Array) -> String: return p[0])
	T.ok("Entrada: Covil das Raízes" in names, "a porta aparece no mapa do Bosque")
	T.ok(not "Carruagem da Guilda" in MapRules.places("dg_bosque").map(func(p: Array) -> String: return p[0]),
		"sem carruagem dentro da dungeon")
