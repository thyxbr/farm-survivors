extends RefCounted
## Rio do mapa (MapRiver): caminho suavizado, paredes que só abrem na ponte e o Vale sem nada dentro do leito.


func _river_with_bridge() -> MapRoot:
	var root := MapRoot.new()
	var r := MapRiver.new()
	r.name = "Rio"
	root.add_child(r)
	for x in [-40.0, -10.0, 10.0, 40.0]:
		var w := MapWaypoint.new()
		w.position = Vector3(x, 0, 0)
		r.add_child(w)
	var b := MapProp.new()
	b.model = "bridge_stone"
	root.add_child(b)
	return root


func test_smooth_goes_through_control_points() -> void:
	var cp := PackedVector2Array([Vector2(0, 0), Vector2(10, 4), Vector2(20, -3), Vector2(30, 0)])
	var s := MapRiver.smooth(cp, 2.0)
	T.ok(s.size() > 15, "amostra a cada ~2 m")
	for p in cp:
		T.ok(MapRiver.distance_to(s, p) < 0.01, "passa pelo ponto %s" % p)
	for i in s.size() - 1:
		T.ok(s[i].distance_to(s[i + 1]) <= 2.6, "sem saltos grandes entre amostras")


func test_walls_open_only_at_the_bridge() -> void:
	var root := _river_with_bridge()
	var r: MapRiver = root.get_node("Rio")
	r.build_game()
	var body: StaticBody3D = r.get_node("Built/RiverWalls")
	T.eq(body.collision_layer, MapRiver.WALL_LAYER, "camada das paredes do rio")
	var near_l := false
	var near_r := false
	var caps := 0
	for cs: CollisionShape3D in body.get_children():
		if absf(cs.position.x) > 39.0:
			caps += 1   # contorno da ponta arredondada
			continue
		var half: float = (cs.shape as BoxShape3D).size.x / 2.0
		var x0 := cs.position.x - half
		var x1 := cs.position.x + half
		T.ok(x1 <= -2.3 or x0 >= 2.3, "nenhuma parede na passagem da ponte (%.2f..%.2f)" % [x0, x1])
		near_l = near_l or (x1 > -2.9 and x1 <= -2.3)
		near_r = near_r or (x0 < 2.9 and x0 >= 2.3)
		T.ok(absf(absf(cs.position.z) - (r.half_total() - 0.2)) < 0.05, "parede na beira da margem")
	T.ok(near_l and near_r, "as paredes encostam nas muretas dos dois lados")
	T.ok(caps >= 2 * MapRiver.CAP_STEPS, "as duas pontas do rio também têm parede em volta")
	root.free()


func test_vale_has_river_and_bridge() -> void:
	var root := (load(MapData.SCENES["vila"]) as PackedScene).instantiate() as MapRoot
	var rivers := root.pieces(MapRiver)
	T.eq(rivers.size(), 1, "o Vale tem um rio")
	var bridges := (rivers[0] as MapRiver).bridges()
	T.eq(bridges.size(), 1, "uma ponte sobre o rio")
	var pts := (rivers[0] as MapRiver).samples()
	T.ok(pts[0].x < -root.half and pts[pts.size() - 1].x > root.half, "o rio atravessa o mapa de lado a lado")
	T.ok(MapRiver.distance_to(pts, bridges[0].center) < 0.5, "a ponte fica sobre o rio")
	root.free()


func test_bridge_model_has_walkable_collision() -> void:
	var inst: Node = (load(MapProp.model_path("bridge_stone")) as PackedScene).instantiate()
	var shapes := inst.find_children("*", "CollisionShape3D", true, false)
	T.ok(shapes.size() >= 1, "a ponte traz a colisão do tabuleiro e das muretas (BridgeCol-colonly)")
	var body := inst.find_children("*", "StaticBody3D", true, false)
	T.ok(body.size() >= 1 and (body[0] as StaticBody3D).collision_layer & 1, "colisão na camada do cenário")
	inst.free()
