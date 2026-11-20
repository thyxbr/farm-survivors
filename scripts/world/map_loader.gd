class_name MapLoader
extends RefCounted
## Monta no jogo um mapa a partir da cena dele (scenes/maps/<mapa>.tscn, MapData.SCENES): põe a cena na
## origem da região, cria o chão (formas, morros, serra), assenta no relevo as peças com follow_ground e
## transforma cada peça no que o jogo usa: modelo + colisão (MapProp), luz registrada (MapLight), enfeite
## (MapDecor), NPC/ponto de jogo (MapEntity, pela fábrica do mundo), entradas de monstro (EnemySpawn, só onde
## o mundo cria monstros), landmarks e áreas do capim. Lado do jogo: pode citar autoload.

## Monta o mapa `map_id` dentro do mundo `w` e devolve a raiz (Map_<id>).
static func build(w: Node3D, map_id: String) -> MapRoot:
	var root := MapData.load_root(map_id) as MapRoot
	if root == null:
		push_error("MapLoader: cena do mapa %s não existe (%s)" % [map_id, MapData.scene_path(map_id)])
		return null
	var o: Vector3 = MapData.origin(map_id)
	root.name = "Map_" + map_id
	root.position = o
	w.add_child(root)
	var ground: Node3D = null
	if root.has_ground:
		var g := root.make_ground(Vector2(o.x, o.z))
		ground = g
		g.position = o
		w.add_child(g)
		g.build_terrain()
		if map_id == "vila":
			w.ground = g
		else:
			w.region_grounds[map_id] = g
		_settle(root, g)
	var keep: Array = []
	var sparse: Array = []
	for n in root.all_pieces():
		if n is MapProp:
			_prop(w, n)
		elif n is MapLight:
			_light(w, n)
		elif n is MapDecor:
			(n as MapDecor).build_into(n)
		elif n is MapEntity:
			if n.kind != "resource_node":   # nós de coleta: o mundo cria de WorldHarvest (cliente e solo)
				var e: Node = w.make_entity(n)
				if e != null:
					w.add_child(e)
		elif n is EnemySpawn:
			if w.has_server_enemies() and not n.boss:
				var list: Array = w.spawns if map_id == "vila" else w.region_spawns
				# região com nome: nível 0 tira a faixa dela; a densidade multiplica a quantidade
				var rt: Dictionary = Balance.tables.get_table("regions")
				var area := Regions.area_at(n.global_position)
				var lv := Regions.spawn_range(rt, area, n.level, n.level_max)
				var count := Regions.spawn_count(rt, area, n.count)
				# dungeon: o ponto tem entradas até o teto da população (DungeonRules); as acima da base só
				# nascem com mais jogadores dentro. O chefe volta em minutos (progression.json "dungeons").
				var dungeon := Regions.is_dungeon(map_id)
				var base := count
				if dungeon:
					count = DungeonRules.max_population(Balance.tables, base)
				var boss_kind: bool = Balance.tables.get_table("enemies").get(n.kind, {}).get("boss", false) or n.chief
				var pts: Array[Vector3] = EnemySpawn.spread(n.global_position, count, n.radius)
				if n.follow_ground and ground != null:
					# cada um no chão de onde cai (o centro já foi assentado: a distância salva é y - chão)
					var c: Vector3 = n.global_position - o
					var h := Callable(ground, "height_at")
					var off: float = c.y - MapPreview.ground_y(true, 0.0, h, c.x, c.z)
					pts = []
					for q in EnemySpawn.spread_on_ground(c, count, n.radius, off, h):
						pts.append(q + o)
				for i in pts.size():
					var p: Vector3 = pts[i]
					var entry := {"kind": n.kind, "pos": p, "node": null, "timer": 0.0, "respawn": n.respawn,
							"level": lv.x, "level_max": lv.y, "elite": n.elite, "area": area}
					if dungeon:
						entry.merge({"dungeon": map_id, "slot": i, "base": base, "boss": boss_kind, "chief": n.chief})
					if n.night_only:
						entry["night"] = true   # bicho da noite (o mundo segura de dia)
					list.append(entry)
		elif n is MapLandmark:
			if map_id == "vila":
				w.landmarks[n.id] = n.global_position
			w.landmarks["%s:%s" % [map_id, n.id]] = n.global_position
		elif n is MapGrassArea:
			var c: Vector3 = n.global_position
			(sparse if n.sparse else keep).append([Vector2(c.x, c.z), n.radius])
		elif n is MapDungeon:
			(n as MapDungeon).build_game()
		elif n is MapRiver:
			(n as MapRiver).build_game()
			keep.append_array((n as MapRiver).grass_discs(Vector2(o.x, o.z)))
	w.grass_areas[map_id] = {"keep_out": keep, "sparse": sparse}
	return root


## Assenta no relevo as peças de topo com follow_ground (as que estão dentro de outra peça vão junto com ela):
## a altura salva vira distância até o chão.
static func _settle(root: MapRoot, g: Node3D) -> void:
	for n in root.all_pieces():
		if not n.get("follow_ground"):
			continue
		var p: Node = n.get_parent()
		var nested := false
		while p != root:
			if p.has_method("build_preview"):
				nested = true
				break
			p = p.get_parent()
		if nested:
			continue
		var local := root.local_xform(n).origin
		var h: float = MapPreview.ground_y(true, 0.0, Callable(g, "height_at"), local.x, local.z)
		(n as Node3D).global_position.y += h


## Chave de lugar de uma árvore do mapa (x, z em quartos de metro): liga o MapProp montado ao nó de coleta de mesmo
## lugar (MapData.resource_nodes calcula a posição pela mesma cena).
static func tree_key(pos: Vector3) -> Vector2i:
	return Vector2i(roundi(pos.x * 4.0), roundi(pos.z * 4.0))


## Modelo + colisão simples + pegada sem capim, como o prop() do mundo, dentro do próprio nó.
static func _prop(w: Node3D, p: MapProp) -> void:
	var inst: Node3D = (load(MapProp.model_path(p.model)) as PackedScene).instantiate()
	p.add_child(inst)
	if p.model.begins_with("tree_") and "tree_props" in w:
		w.tree_props[tree_key(p.global_position)] = p   # vira nó de coleta (world._setup_resource_nodes)
	p.apply_tint(inst)
	var s := p.scale.x
	_set_range(p, inst, s)
	var pos := p.global_position
	if p.shape != 0 and p.no_grass:
		w._no_grass.append([Vector2(pos.x, pos.z), p.footprint() + 0.15])
	if p.shape == 0:
		return
	var body := StaticBody3D.new()
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var size := p.shape_size * s   # tamanho * escala, como o prop() antigo (a colisão não herda a escala)
	if p.shape == 1:
		var b := BoxShape3D.new()
		b.size = size
		cs.shape = b
	else:
		var c := CylinderShape3D.new()
		c.radius = size.x
		c.height = size.y
		cs.shape = c
	cs.position.y = size.y / 2.0
	body.add_child(cs)
	p.add_child(body)
	body.global_transform = Transform3D(Basis(Vector3.UP, p.global_rotation.y), pos)


## Peça pequena some de longe: a distância vem do tamanho da peça inteira (RANGE_PER_M metros por metro do
## lado maior, no mínimo RANGE_MIN), então flor e pedrinha somem cedo, árvore fica até longe e casa e torre
## (alcance acima de RANGE_MAX) nunca somem. Todas as malhas da peça levam a mesma distância.
const RANGE_PER_M := 50.0
const RANGE_MIN := 60.0
const RANGE_MAX := 250.0
const RANGE_MARGIN := 8.0
static var _model_size := {}      # modelo -> lado maior da peça, em metros, sem a escala


static func _set_range(p: MapProp, inst: Node3D, s: float) -> void:
	var meshes := inst.find_children("*", "MeshInstance3D", true, false)
	if inst is MeshInstance3D:
		meshes.append(inst)
	if not _model_size.has(p.model):
		var box := AABB()
		var first := true
		var inv := inst.global_transform.affine_inverse()
		for mi: MeshInstance3D in meshes:
			if mi.mesh == null:
				continue
			var b: AABB = (inv * mi.global_transform) * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		_model_size[p.model] = box.get_longest_axis_size()
	var reach: float = maxf(RANGE_MIN, float(_model_size[p.model]) * s * RANGE_PER_M)
	if reach >= RANGE_MAX:
		return
	for mi: MeshInstance3D in meshes:
		if mi.visibility_range_end <= 0.0:
			mi.visibility_range_end = reach
			mi.visibility_range_end_margin = RANGE_MARGIN


static func _light(w: Node3D, l: MapLight) -> void:
	l.shadow_enabled = false
	match l.mode:
		1:
			DayNightFX.night_light(l, l.night_energy)
		2:
			w.flicker_lights.append([l, l.light_energy, randf() * 10.0])
