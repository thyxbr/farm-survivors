extends RefCounted
## Dungeons subterrâneas (MapDungeon): cada uma fechada, com chegada, saída e todos os monstros em chão andável,
## caminho da entrada até a sala do chefe, portão na entrada da sala e o chefe lá dentro.


## Distância mínima (m) de qualquer monstro até a chegada.
const SAFE_ARRIVE := 22.0


func _root(id: String) -> MapRoot:
	return (load(MapData.SCENES[id]) as PackedScene).instantiate() as MapRoot


func _xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## Células alcançáveis a partir de `start` andando pela grade (4 vizinhos).
func _reach(cells: Dictionary, start: Vector2i) -> Dictionary:
	var seen := {start: true}
	var todo: Array = [start]
	while not todo.is_empty():
		var k: Vector2i = todo.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = k + d
			if cells.has(n) and not seen.has(n):
				seen[n] = true
				todo.append(n)
	return seen


func test_every_dungeon_is_underground_and_complete() -> void:
	for id in Regions.DUNGEONS:
		var root := _root(id)
		T.ok(not root.has_ground, "%s não usa o chão aberto de Valdoria" % id)
		var ds := root.pieces(MapDungeon)
		T.eq(ds.size(), 1, "%s tem uma planta de dungeon" % id)
		if ds.is_empty():
			root.free()
			continue
		var d: MapDungeon = ds[0]
		d.layout()
		var cells := d.cells()
		T.ok(cells.size() > 600, "%s tem salas e corredores (%d m²)" % [id, cells.size()])
		var arrive := Vector3.INF
		for m: MapLandmark in root.pieces(MapLandmark):
			if m.id == "arrive":
				arrive = root.local_xform(m).origin
		T.ok(d.walkable(_xz(arrive)), "%s: a chegada fica no chão da dungeon" % id)
		for e: MapEntity in root.pieces(MapEntity):
			if e.kind == "dungeon_door":
				T.ok(d.walkable(_xz(root.local_xform(e).origin)), "%s: a porta de saída fica no chão da dungeon" % id)
		var reach := _reach(cells, Vector2i(floori(arrive.x), floori(arrive.z)))
		T.eq(reach.size(), cells.size(), "%s: dá para andar da entrada até qualquer canto" % id)
		var g := d.boss_entrance()
		T.ok(not g.is_empty(), "%s: o portão do chefe fica onde o corredor entra na sala" % id)
		var chiefs := 0
		for s: EnemySpawn in root.pieces(EnemySpawn):
			var c := root.local_xform(s).origin
			for p in EnemySpawn.spread(c, maxi(s.count, 1), s.radius):
				T.ok(d.walkable(_xz(p)), "%s: %s nasce no chão (%.1f, %.1f)" % [id, s.name, p.x, p.z])
				# ninguém nasce na sala de chegada nem colado nela: quem entra não cai no meio de um bando
				T.ok(_xz(p).distance_to(_xz(arrive)) >= SAFE_ARRIVE, "%s: %s longe da chegada (%.1f m)"
					% [id, s.name, _xz(p).distance_to(_xz(arrive))])
			if s.chief:
				chiefs += 1
				var center: Vector2 = g.get("center", Vector2.INF)
				T.ok(_xz(c).distance_to(center) < 8.0, "%s: o chefe espera na sala dele" % id)
		T.eq(chiefs, 1, "%s tem um chefe só" % id)
		for pth: MapDungeonPath in root.pieces(MapDungeonPath):
			T.ok(pth.width >= 6.0, "%s: %s é largo (%.1f m)" % [id, pth.name, pth.width])
		root.free()


func test_walls_close_the_dungeon() -> void:
	var root := _root("dg_pico")
	var d: MapDungeon = root.pieces(MapDungeon)[0]
	d.build_game()
	var body: StaticBody3D = d.get_node("Built/DungeonBody")
	var walls := 0
	for cs: CollisionShape3D in body.get_children():
		if (cs.shape as BoxShape3D).size.y >= 10.0:
			walls += 1
	T.ok(walls > 50, "paredes de rocha em volta, altas para segurar a câmera (%d tiras)" % walls)
	root.free()
