extends RefCounted
## Mapas das expedições (cena + ExpeditionDefs): cada sala do grafo existe na cena, salas ligadas no grafo estão
## ligadas por chão andável (sem passar por outra sala do grafo), a chegada e a saída ficam na sala de chegada, os
## monstros nascem no chão de salas com luta e longe da chegada, o chefe fica na sala de chefe e as paredes fecham.

const SAFE_ARRIVE := 22.0


func _root(map_id: String) -> MapRoot:
	return (load(MapData.SCENES[map_id]) as PackedScene).instantiate() as MapRoot


func _xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.y))


## Salas da cena por nome: {"node", "center" (x, z no mapa)}.
func _rooms(root: MapRoot) -> Dictionary:
	var out := {}
	for r: MapDungeonRoom in root.pieces(MapDungeonRoom):
		out[str(r.name)] = {"node": r, "center": _xz(root.local_xform(r).origin)}
	return out


func _room_of(rooms: Dictionary, p: Vector2) -> String:
	for id in rooms:
		if (rooms[id].node as MapDungeonRoom).contains(rooms[id].center, p):
			return id
	return ""


## Células alcançáveis a partir de `start` sem pisar em salas fora de `allowed` (4 vizinhos).
func _reach(cells: Dictionary, start: Vector2i, rooms: Dictionary, allowed: Array) -> Dictionary:
	var seen := {start: true}
	var todo: Array = [start]
	while not todo.is_empty():
		var k: Vector2i = todo.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = k + d
			if not cells.has(n) or seen.has(n):
				continue
			var in_room := _room_of(rooms, Vector2(n) + Vector2(0.5, 0.5))
			if in_room != "" and not in_room in allowed:
				continue
			seen[n] = true
			todo.append(n)
	return seen


func test_expedition_maps_follow_the_graph() -> void:
	for id in ExpeditionDefs.DATA:
		var def := ExpeditionDefs.get_def(id)
		var map_id := ExpeditionDefs.map_of(id)
		var root := _root(map_id)
		T.eq(root.map_id, map_id, "%s: cena com o map_id certo" % id)
		T.ok(not root.has_ground, "%s: subterrânea (sem o chão aberto de Valdoria)" % id)
		T.ok(is_equal_approx(root.half, float(def.half)), "%s: meia largura igual à da definição" % id)
		var ds := root.pieces(MapDungeon)
		T.eq(ds.size(), 1, "%s: uma planta de dungeon" % id)
		if ds.is_empty():
			root.free()
			continue
		var d: MapDungeon = ds[0]
		d.layout()
		var cells := d.cells()
		var rooms := _rooms(root)
		for r in ExpeditionDefs.rooms(def):
			T.ok(rooms.has(r), "%s: a sala '%s' existe na cena" % [id, r])
			if rooms.has(r):
				T.ok(d.walkable(rooms[r].center), "%s: o centro de '%s' é chão" % [id, r])
		# ligações do grafo: de uma sala dá para andar até a seguinte só pelos corredores entre elas
		for r in ExpeditionDefs.rooms(def):
			for n in ExpeditionDefs.next_of(def, r):
				if not (rooms.has(r) and rooms.has(n)):
					continue
				var seen := _reach(cells, _cell(rooms[r].center), rooms, [r, n])
				T.ok(seen.has(_cell(rooms[n].center)), "%s: de '%s' anda-se até '%s'" % [id, r, n])
		var marks := {}
		for m: MapLandmark in root.pieces(MapLandmark):
			marks[m.id] = _xz(root.local_xform(m).origin)
		var start := str(def.start)
		for k in ["arrive", "exit"]:
			T.ok(marks.has(k), "%s: landmark %s" % [id, k])
			if marks.has(k) and rooms.has(start):
				T.ok(d.walkable(marks[k]), "%s: %s fica no chão" % [id, k])
				T.eq(_room_of(rooms, marks[k]), start, "%s: %s fica na sala de chegada" % [id, k])
		var chiefs := 0
		for s: EnemySpawn in root.pieces(EnemySpawn):
			var c := root.local_xform(s).origin
			var home := _room_of(rooms, _xz(c))
			T.ok(ExpeditionDefs.needs_clear(def, home), "%s: %s nasce numa sala com luta ('%s')" % [id, s.name, home])
			T.ok(s.level > 0, "%s: %s com nível fixo (a expedição não fica em região com faixa)" % [id, s.name])
			for p in EnemySpawn.spread(c, maxi(s.count, 1), s.radius):
				T.ok(d.walkable(_xz(p)), "%s: %s nasce no chão (%.1f, %.1f)" % [id, s.name, p.x, p.z])
				T.eq(_room_of(rooms, _xz(p)), home, "%s: o bando %s fica todo na mesma sala" % [id, s.name])
				if marks.has("arrive"):
					T.ok(_xz(p).distance_to(marks.arrive) >= SAFE_ARRIVE, "%s: %s longe da chegada" % [id, s.name])
			if s.chief:
				chiefs += 1
				T.eq(ExpeditionDefs.kind_of(def, home), "boss", "%s: o chefe espera na sala de chefe" % id)
		T.eq(chiefs, 1, "%s: um chefe só" % id)
		for r in ExpeditionDefs.clear_rooms(def):
			var has_spawn := false
			for s: EnemySpawn in root.pieces(EnemySpawn):
				has_spawn = has_spawn or _room_of(rooms, _xz(root.local_xform(s).origin)) == r
			T.ok(has_spawn, "%s: a sala com luta '%s' tem monstros" % [id, r])
		for pth: MapDungeonPath in root.pieces(MapDungeonPath):
			T.ok(pth.width >= 6.0, "%s: %s é largo (%.1f m)" % [id, pth.name, pth.width])
		root.free()


func test_expedition_walls_close_the_map() -> void:
	for id in ExpeditionDefs.DATA:
		var root := _root(ExpeditionDefs.map_of(id))
		var d: MapDungeon = root.pieces(MapDungeon)[0]
		d.build_game()
		var body: StaticBody3D = d.get_node("Built/DungeonBody")
		var walls := 0
		for cs: CollisionShape3D in body.get_children():
			if cs.shape is BoxShape3D and (cs.shape as BoxShape3D).size.y >= 10.0:
				walls += 1
		T.ok(walls > 20, "%s: chão e paredes de rocha com colisão (%d tiras)" % [id, walls])
		root.free()


func test_expedition_map_origin_is_far_from_everything() -> void:
	for id in ExpeditionDefs.DATA:
		var o := MapData.origin(ExpeditionDefs.map_of(id))
		for other in Regions.ALL + ["arena"]:
			T.ok(o.distance_to(MapData.origin(other)) > 650.0, "%s longe de %s (fora do alcance da câmera)" % [id, other])
		T.eq(Regions.region_at(o), "vila", "%s fora de todas as regiões do MMO (não conta como dungeon do mundo)" % id)
