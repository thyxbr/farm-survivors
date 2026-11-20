extends RefCounted
## Coleta de ferro e cristal em Valdoria: regras puras com a tabela real (world_nodes).

var _bt: BalanceTables


func _tables() -> BalanceTables:
	if _bt == null:
		_bt = BalanceTables.load_dir("res://data/balance")
	return _bt


func test_table_shape() -> void:
	var bt := _tables()
	var items: Dictionary = bt.get_table("items")
	# 20 de antes (ferro e cristal no vale e na Mina) + 51 da parte 3 (minério e madeira de cada camada)
	# 71 veios e árvores especiais (MapEntity) + toda árvore do cenário dos quatro mapas (MapProp tree_*)
	var placed := WorldHarvest.ids(bt).filter(func(i) -> bool: return i < MapData.TREE_ID_BASE).size()
	var trees := WorldHarvest.count(bt) - placed
	T.eq(placed, 71, "veios e árvores especiais dos quatro mapas")
	T.ok(trees > 600, "árvores do cenário cortáveis (%d)" % trees)
	var kinds := {}
	for i in WorldHarvest.ids(bt).filter(func(x) -> bool: return x < MapData.TREE_ID_BASE):
		var d := WorldHarvest.node_def(bt, i)
		kinds[d.kind] = int(kinds.get(d.kind, 0)) + 1
		T.ok(items.has(d.item), "item do nó %d existe" % i)
		T.ok(d.amount >= 1 and d.tough > 0.0 and d.tier >= 1 and d.respawn > 0, "números do nó %d" % i)
	T.eq(kinds, {"iron": 14, "crystal": 10, "copper": 6, "pine": 8, "oak": 8, "silver": 6, "silverbirch": 4,
		"mithril": 6, "ashwood": 4, "astralite": 3, "soulwood": 2}, "nós por tipo")
	for i in range(10, 20):
		T.eq(Regions.region_at(WorldHarvest.node_def(bt, i).pos), "mina", "nó %d fica na Geleira de Cristal" % i)
	var iron := WorldHarvest.node_def(bt, 0)
	T.eq(iron.item, "iron_ore", "nó 0 dá minério")
	T.eq(iron.amount, 3, "3 por veio")
	T.eq(iron.tough, 8.0, "resistência do ferro")
	T.eq(iron.tier, 1, "ferro sai com picareta de pedra")
	T.eq(iron.prof, "mining", "ferro é de Mineração")
	T.ok(iron.level >= 1 and iron.xp > 0, "nível e XP do nó")
	T.ok(iron.pos.distance_to(Vector3(86, 0, 0)) < 13.0, "ferro em volta do Acampamento Goblin")
	var cr := WorldHarvest.node_def(bt, 6)
	T.eq(cr.item, "arcane_crystal", "nó 6 dá cristal")
	T.ok(cr.pos.distance_to(Vector3(0, 0, -100)) < 18.0, "cristal em volta das Ruínas")


func test_gather_and_respawn() -> void:
	var bt := _tables()
	var h := WorldHarvest.new()
	var at: Vector3 = WorldHarvest.node_def(bt, 0).pos + Vector3(1.5, 0, 0)
	var r := h.gather(bt, 2, 0, at, 1000.0)
	T.ok(r.ok, "coletou perto")
	T.eq(r.items, {"iron_ore": 3}, "3 minérios")
	T.eq(h.gather(bt, 2, 0, at, 1001.0).err, "esgotado", "de novo na hora: esgotado")
	T.ok(h.ready_in(2, 0, 1001.0) > 170.0, "falta quase o tempo todo para voltar")
	T.eq(h.gather(bt, 2, 0, at, 1179.0).err, "esgotado", "um segundo antes de voltar")
	T.ok(h.gather(bt, 2, 0, at, 1180.0).ok, "depois de 180 s concede de novo")
	T.eq(h.gather(bt, 3, 0, at, 1001.0).err, "esgotado", "outra conta no mesmo veio: é do mundo, já foi coletado")
	var h2 := WorldHarvest.new()
	h2.gather(bt, 2, 0, at, 10.0)
	T.ok(h2.depleted(11.0).has(0), "esgotado aparece para quem entra")
	T.ok(not h2.depleted(191.0).has(0), "depois de voltar, sai da lista")
	T.ok(h.gather(bt, 2, 1, WorldHarvest.node_def(bt, 1).pos, 1181.0).ok, "outro veio da mesma conta")


func test_refusals() -> void:
	var bt := _tables()
	var h := WorldHarvest.new()
	var pos: Vector3 = WorldHarvest.node_def(bt, 0).pos
	T.eq(h.gather(bt, 2, 0, pos + Vector3(30, 0, 0), 10.0).err, "longe", "a 30 m")
	T.eq(h.gather(bt, 2, 0, Vector3.INF, 10.0).err, "longe", "posição desconhecida")
	for bad in [-1, 999, "x", 1.5, null]:
		T.eq(h.gather(bt, 2, bad, pos, 10.0).err, "no_invalido", "id inválido: %s" % str(bad))
		T.eq(WorldHarvest.node_def(bt, bad), {}, "node_def de id inválido: %s" % str(bad))
	T.ok(h.gather(bt, 2, 0, pos, 10.0).ok, "recusas não gastam o veio")


func test_undo() -> void:
	var bt := _tables()
	var h := WorldHarvest.new()
	var pos: Vector3 = WorldHarvest.node_def(bt, 0).pos
	T.ok(h.gather(bt, 2, 0, pos, 10.0).ok, "coletou")
	h.undo(2, 0)
	T.eq(h.ready_in(2, 0, 11.0), 0.0, "desfeito: pronto de novo")
	T.ok(h.gather(bt, 2, 0, pos, 11.0).ok, "coleta de novo depois de desfazer")


func test_missing_table() -> void:
	var bt := BalanceTables.from_dict({"items": _tables().get_table("items")})
	T.eq(WorldHarvest.count(bt), 0, "sem tabela: nenhum nó")
	T.eq(WorldHarvest.new().gather(bt, 2, 0, Vector3.ZERO, 1.0).err, "no_invalido", "sem tabela: recusa sem quebrar")


## As posições e os tipos dos veios vêm das cenas dos mapas (MapEntity resource_node, node_id fixo); o
## world_nodes.json só guarda o que cada tipo dá. Valores de antes da conversão.
func test_positions_come_from_scene() -> void:
	var bt := _tables()
	T.ok(not bt.get_table("world_nodes").has("nodes"), "a lista de posições saiu do world_nodes.json")
	T.ok(WorldHarvest.node_def(bt, 0).pos.is_equal_approx(Vector3(95.6, 0, 8.0)), "nó 0 no lugar de sempre (na Toca, que foi para o leste)")
	T.ok(WorldHarvest.node_def(bt, 6).pos.is_equal_approx(Vector3(14.7, 0, -91.5)), "nó 6 no lugar de sempre")


func test_ids_are_fixed_not_list_positions() -> void:
	var bt := _tables()
	MapData.scene_override = {"vila": "res://tests/unit/fixtures/map_nodes_fixture.tscn",
		"bosque": "res://tests/unit/fixtures/map_root_fixture.tscn", "mina": "res://tests/unit/fixtures/map_root_fixture.tscn",
		"pico": "res://tests/unit/fixtures/map_root_fixture.tscn"}
	MapData.clear_cache()
	var placed := WorldHarvest.ids(bt).filter(func(i) -> bool: return i < MapData.TREE_ID_BASE)
	T.eq(placed, [0, 2], "dois nós na cena, com os ids da cena e em ordem (as árvores do cenário vêm depois)")
	T.eq(WorldHarvest.node_def(bt, 1), {}, "id que a cena não tem: nada (apagar um nó não renumera os outros)")
	T.eq(WorldHarvest.node_def(bt, 2).kind, "crystal", "nó 2 é o cristal da cena")
	T.ok(WorldHarvest.node_def(bt, 2).pos.is_equal_approx(Vector3(-5, 0, 4)), "posição do nó 2 vem da cena")
	MapData.scene_override = {}
	MapData.clear_cache()


## Toda árvore do cenário se corta e dá a madeira da família dela (world_nodes.json "tree_models").
func test_scenery_trees() -> void:
	var bt := _tables()
	var models := {}
	for id in WorldHarvest.ids(bt):
		if id < MapData.TREE_ID_BASE:
			continue
		var d := WorldHarvest.node_def(bt, id)
		T.ok(d.prop, "árvore %d é do cenário" % id)
		T.ok(str(d.model).begins_with("tree_"), "modelo da árvore %d" % id)
		models[d.model] = d.kind
	T.eq(models.get("tree_pine"), "pine", "pinheiro dá pinho")
	T.eq(models.get("tree_fir"), "pine", "abeto dá pinho")
	T.eq(models.get("tree_oak"), "oak", "carvalho dá carvalho")
	T.eq(models.get("tree_maple"), "oak", "bordo dá carvalho")
	T.eq(models.get("tree_apple"), "oak", "frutífera dá carvalho")
	T.eq(models.get("tree_birch"), "silverbirch", "bétula dá bétula prateada")
	var first: int = WorldHarvest.ids(bt).filter(func(x) -> bool: return x >= MapData.TREE_ID_BASE)[0]
	var pos: Vector3 = WorldHarvest.node_def(bt, first).pos
	var h := WorldHarvest.new()
	T.ok(h.gather(bt, 2, first, pos + Vector3(1.0, 0, 0), 50.0).ok, "corta uma árvore do cenário")
	T.eq(h.gather(bt, 3, first, pos, 51.0).err, "esgotado", "e ela some para os outros")
