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
	T.eq(WorldHarvest.count(bt), 10, "dez nós no mapa")
	var kinds := {}
	for i in WorldHarvest.count(bt):
		var d := WorldHarvest.node_def(bt, i)
		kinds[d.kind] = int(kinds.get(d.kind, 0)) + 1
		T.ok(items.has(d.item), "item do nó %d existe" % i)
		T.ok(d.amount >= 1 and d.hits >= 1 and d.respawn > 0, "números do nó %d" % i)
	T.eq(kinds, {"iron": 6, "crystal": 4}, "6 de ferro e 4 de cristal")
	var iron := WorldHarvest.node_def(bt, 0)
	T.eq(iron.item, "iron_ore", "nó 0 dá minério")
	T.eq(iron.amount, 3, "3 por veio")
	T.eq(iron.hits, 5, "5 golpes")
	T.ok(iron.pos.distance_to(Vector3(62, 0, 0)) < 13.0, "ferro em volta do Acampamento Goblin")
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
	T.ok(h.gather(bt, 3, 0, at, 1181.0).ok, "outra conta no mesmo veio: veios são pessoais")
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
