class_name RegionBuilder
extends RefCounted
## Monta os mapas fora do vale (Regions): Bosque Sussurrante, Mina de Cristal e Pico das Cinzas. Cada um tem
## chão próprio (ground.gd com world_offset), serra em volta, paredes de colisão na borda, cenário, NPCs da
## história, a carruagem da guilda e os pontos de nascimento dos monstros (o mundo cria e repõe, como no vale).
## Também guarda as fábricas dos NPCs novos (npc()) e da carroça (wagon()), usadas pela vila.

const GROUND := preload("res://scripts/world/ground.gd")
const STORY_POINT := preload("res://scripts/world/story_point.gd")
const RIVAL := preload("res://scripts/world/rival.gd")
## Raio de colisão do tronco por árvore (o mesmo do vale).
const TREE_R := {"tree_oak": 0.4, "tree_pine": 0.35, "tree_fir": 0.32, "tree_birch": 0.25, "tree_maple": 0.4}

## Visual de cada NPC novo: {"villager": roupa 1..3} ou {"knight": look do KnightLook}; "scale"; "idle".
const NPCS := {
	"lina": {"villager": 3, "scale": 0.95},
	"zelia": {"villager": 1, "scale": 0.88, "idle": 0.8},
	"tonico": {"villager": 2, "scale": 1.0},
	"coach": {"villager": 1, "scale": 1.05},
	"tico": {"villager": 3, "scale": 0.6},
	"rufus": {"knight": {"weapon": "iron_sword", "armor": "guard_surcoat", "head": "kettle_hat", "hands": "iron_gauntlets",
		"feet": "iron_greaves", "offhand": "wooden_shield"}, "scale": 1.05},
	"osvaldo": {"knight": {"weapon": "knight_blade", "armor": "royal_plate", "head": "knight_helm", "hands": "iron_gauntlets",
		"feet": "iron_greaves", "offhand": "knight_shield"}, "scale": 0.97},
	"ravi": {"knight": {"weapon": "hunter_bow", "armor": "ranger_vest", "head": "ranger_hood", "hands": "archer_bracers",
		"feet": "leather_boots", "offhand": "hunter_quiver"}, "scale": 1.0},
	"sylvi": {"knight": {"weapon": "elven_bow", "armor": "ranger_vest", "head": "", "hands": "leather_gloves",
		"feet": "swift_boots"}, "scale": 0.95},
	"bolgar": {"knight": {"weapon": "", "armor": "leather_armor", "head": "iron_helm", "hands": "iron_gauntlets",
		"feet": "reinforced_boots"}, "scale": 0.78},
}


## Cria um NPC da história (sem adicionar à árvore): Kael do pico, aldeões e os de armadura.
static func npc(id: String, pos: Vector3, yaw: float) -> Node3D:
	var n: Node3D
	if id == "kael_pico":
		n = RIVAL.new()
		n.npc_id = "kael_pico"
	else:
		var d: Dictionary = NPCS.get(id, {"villager": 1})
		if d.has("knight"):
			var k := KnightNPC.new()
			k.npc_id = id
			k.look = d.knight
			k.model_scale = float(d.get("scale", 1.0))
			n = k
		else:
			var v := VillagerNPC.new()
			v.npc_id = id
			v.look_index = int(d.villager)
			v.model_scale = float(d.get("scale", 1.0))
			v.idle_speed = float(d.get("idle", 1.0))
			n = v
	n.position = pos
	n.rotation.y = yaw
	return n


## Objeto examinável da história (bilhete, diário, gato, quadro).
static func point(id: String, pos: Vector3, yaw := 0.0) -> Node3D:
	var sp := STORY_POINT.new()
	sp.npc_id = id
	sp.position = pos
	sp.rotation.y = yaw
	return sp


## Carroça da guilda (montada com caixas e cilindros): caixa de madeira, quatro rodas, toldo e lanterna.
static func wagon(pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	var wood := _mat(Color(0.45, 0.3, 0.18))
	var dark := _mat(Color(0.25, 0.17, 0.1))
	var cloth := _mat(Color(0.86, 0.8, 0.64))
	var guild := _mat(Color(0.25, 0.4, 0.75))
	_box(root, Vector3(1.8, 0.7, 3.2), wood, Vector3(0, 0.95, 0))
	_box(root, Vector3(1.9, 0.12, 3.3), dark, Vector3(0, 0.6, 0))
	_box(root, Vector3(0.12, 0.12, 1.6), dark, Vector3(0, 0.6, 2.3))   # varal
	for x in [-1.0, 1.0]:
		for z in [-1.1, 1.1]:
			var w := MeshInstance3D.new()
			var c := CylinderMesh.new()
			c.top_radius = 0.48
			c.bottom_radius = 0.48
			c.height = 0.12
			w.mesh = c
			w.material_override = dark
			w.position = Vector3(x, 0.48, z)
			w.rotation.z = PI / 2
			root.add_child(w)
	# toldo em arco (três faixas) com a faixa azul da guilda
	for i in 5:
		var a := lerpf(-1.1, 1.1, i / 4.0)
		var seg := _box(root, Vector3(0.62, 0.06, 3.0), cloth if i != 2 else guild, Vector3(sin(a) * 0.9, 1.3 + cos(a) * 0.9, 0))
		seg.rotation.z = -a
	_box(root, Vector3(0.12, 0.12, 0.12), _mat(Color(1, 0.8, 0.4)), Vector3(0.95, 1.6, 1.6))
	if ToonLook.enabled():
		ToonLook.apply(root)
	var body := StaticBody3D.new()
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(2.0, 2.4, 3.4)
	cs.shape = b
	cs.position.y = 1.2
	body.add_child(cs)
	root.add_child(body)
	return root


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


static func _box(parent: Node3D, size: Vector3, m: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


# ================================================================ mapas
## Monta a região `id` no mundo `w` (world.gd). Devolve o chão (para a grama, que vem depois).
static func build(w: Node3D, id: String) -> Node3D:
	var o: Vector3 = Regions.origin(id)
	var half: float = Regions.DATA[id].half
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var g = GROUND.new()
	g.name = "Ground_" + id
	g.position = o
	g.world_offset = Vector2(o.x, o.z)
	w.add_child(g)
	g.setup(half)
	_walls(w, o, half)
	match id:
		"bosque":
			_bosque(w, g, o, half, rng)
		"mina":
			_mina(w, g, o, half, rng)
		"pico":
			_pico(w, g, o, half, rng)
	g.border_mountains(34.0 if id == "pico" else 26.0)
	g.build_terrain()
	# carruagem e cocheiro
	var cp: Vector3 = Regions.coach_point(id)
	w.add_child(wagon(cp + Vector3(-3.0, 0, 0), 0.0))
	var beto := npc("coach", cp, PI)
	beto.set("npc_id", "coach_" + id)   # a carruagem de cada mapa é um NPC próprio (o rastreador acha pelo id)
	w.add_child(beto)
	return g


## Paredes invisíveis na borda (a serra em volta é só visual).
static func _walls(w: Node3D, o: Vector3, half: float) -> void:
	for side in [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(half * 2 + 4 if side.x == 0 else 2.0, 20, half * 2 + 4 if side.z == 0 else 2.0)
		cs.shape = b
		body.position = o + side * (half + 1) + Vector3.UP * 10
		body.add_child(cs)
		w.add_child(body)


## Espalha árvores pelo mapa fora das áreas livres (clear: [[Vector2 local, raio]]).
static func _forest(w: Node3D, o: Vector3, half: float, rng: RandomNumberGenerator, weights: Dictionary, n: int,
		clear: Array, scale_rng := Vector2(0.9, 1.4)) -> void:
	var placed := 0
	var tries := 0
	while placed < n and tries < n * 6:
		tries += 1
		var p := Vector2(rng.randf_range(-half + 4, half - 4), rng.randf_range(-half + 4, half - 4))
		var ok := true
		for c in clear:
			if p.distance_to(c[0]) < c[1]:
				ok = false
				break
		if not ok:
			continue
		var model := _pick(weights, rng)
		w.prop(model, o + Vector3(p.x, 0, p.y), rng.randf() * TAU, rng.randf_range(scale_rng.x, scale_rng.y), "cyl",
			Vector3(TREE_R.get(model, 0.35), 3, 0))
		placed += 1


static func _pick(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k in weights:
		total += weights[k]
	var r := rng.randf() * total
	for k in weights:
		r -= weights[k]
		if r <= 0.0:
			return k
	return weights.keys()[0]


static func _spawn(w: Node3D, kind: String, pos: Vector3, respawn: float) -> void:
	w.region_spawns.append({"kind": kind, "pos": pos, "node": null, "timer": 0.0, "respawn": respawn})


# ---------------------------------------------------------------- Bosque Sussurrante
static func _bosque(w: Node3D, g: Node3D, o: Vector3, half: float, rng: RandomNumberGenerator) -> void:
	var dirt := Color(0.36, 0.28, 0.17)
	var moss := Color(0.22, 0.36, 0.16)
	g.add_rect(Vector3(0, 0.02, 30), Vector2(4.0, 56), dirt)          # trilha da carruagem ao centro
	g.add_rect(Vector3(14, 0.02, -6), Vector2(30, 3.5), dirt)         # trilha leste (xamãs)
	g.add_disc(Vector3(0, 0.02, 30), 7.0, Color(0.42, 0.34, 0.22))    # acampamento da Sylvi
	g.add_disc(Vector3(-26, 0.02, -34), 14.0, moss, 0.9, 0.5)         # clareira da Slime Rainha
	g.add_disc(Vector3(30, 0.02, -28), 6.0, moss, 0.9, 0.5)           # esconderijo do Tico
	g.add_disc(Vector3(24, 0.02, 8), 7.0, Color(0.4, 0.3, 0.2))       # acampamento dos xamãs
	var clear := [[Vector2(0, 30), 9.0], [Vector2(-26, -34), 15.0], [Vector2(30, -28), 6.0], [Vector2(24, 8), 8.0],
		[Vector2(0, 56), 8.0], [Vector2(15, 0), 10.0]]
	for z in range(-10, 60, 4):
		clear.append([Vector2(0, z), 3.5])
	for x in range(0, 30, 4):
		clear.append([Vector2(x, -6), 3.0])
	_forest(w, o, half, rng, {"tree_oak": 3, "tree_birch": 2, "tree_maple": 2, "tree_pine": 2, "tree_fir": 1}, 190, clear)
	# acampamento da Sylvi: barraca, fogueira, caixotes
	w.prop("tent", o + Vector3(-4, 0, 27), 0.6, 1.0, "box", Vector3(2.0, 2.2, 2.0))
	var fire: Node3D = w.prop("campfire", o + Vector3(2, 0, 31), 0.0, 1.0, "cyl", Vector3(0.6, 0.4, 0))
	w._light(fire, Vector3(0, 1.0, 0), Color(1.0, 0.55, 0.2), 2.5, 12.0, true)
	w.prop("crate", o + Vector3(-5, 0, 31.5), 0.3, 1.0, "box", Vector3(0.8, 0.8, 0.8))
	w.add_child(npc("sylvi", o + Vector3(0, 0, 33), PI))
	# clareira da rainha: pilares velhos em círculo
	for i in 7:
		var a := i * TAU / 7.0
		w.prop("ruin_pillar", o + Vector3(-26, 0, -34) + Vector3(cos(a), 0, sin(a)) * 12.0, rng.randf() * TAU,
			0.8, "cyl", Vector3(0.5, 4.0, 0))
	# esconderijo do Tico: pedras
	for off in [Vector3(-2, 0, -1.5), Vector3(2.2, 0, -1), Vector3(0.5, 0, -2.6)]:
		w.prop("rock", o + Vector3(30, 0, -28) + off, rng.randf() * TAU, 0.9, "cyl", Vector3(0.6, 0.8, 0))
	w.add_child(npc("tico", o + Vector3(30, 0, -27), PI))
	# acampamento dos xamãs
	w.prop("tent", o + Vector3(27, 0, 11), 2.4, 1.0, "box", Vector3(2.0, 2.2, 2.0))
	var f2: Node3D = w.prop("campfire", o + Vector3(24, 0, 8), 0.0, 1.0, "cyl", Vector3(0.6, 0.4, 0))
	w._light(f2, Vector3(0, 1.0, 0), Color(0.6, 1.0, 0.4), 2.2, 10.0, true)
	if w.has_server_enemies():
		for p in [Vector3(10, 0, -2), Vector3(16, 0, 4), Vector3(20, 0, -6), Vector3(8, 0, -14), Vector3(-10, 0, 0),
				Vector3(-14, 0, 12)]:
			_spawn(w, "slime_veloz", o + p, 40.0)
		for p in [Vector3(-8, 0, -18), Vector3(12, 0, -20), Vector3(-20, 0, 6)]:
			_spawn(w, "slime_gelo", o + p, 60.0)
		for p in [Vector3(22, 0, 6), Vector3(26, 0, 9), Vector3(21, 0, 11)]:
			_spawn(w, "goblin_xama", o + p, 90.0)
		for p in [Vector3(28, 0, 2), Vector3(18, 0, 14)]:
			_spawn(w, "goblin_arqueiro", o + p, 75.0)
		_spawn(w, "slime_rainha", o + Vector3(-26, 0, -36), 240.0)
		for p in [Vector3(-4, 0, 12), Vector3(4, 0, 4)]:
			_spawn(w, "slime", o + p, 30.0)


# ---------------------------------------------------------------- Mina de Cristal
static func _mina(w: Node3D, g: Node3D, o: Vector3, half: float, rng: RandomNumberGenerator) -> void:
	var stone := Color(0.38, 0.37, 0.36)
	var gravel := Color(0.46, 0.42, 0.36)
	g.add_rect(Vector3(0, 0.02, 0), Vector2(half * 1.6, half * 1.6), Color(0.42, 0.4, 0.34), 3.0)  # chão rochoso
	g.add_rect(Vector3(0, 0.025, -12), Vector2(12, 84), stone, 0.6)       # galeria principal
	g.add_rect(Vector3(0, 0.025, 46), Vector2(4.5, 22), gravel)           # trilha da carruagem
	for c in [Vector3(-22, 0.025, -8), Vector3(22, 0.025, -8), Vector3(-20, 0.025, -30), Vector3(20, 0.025, -30)]:
		g.add_disc(c, 8.0, stone, 0.8)
	g.add_disc(Vector3(0, 0.025, 32), 7.0, gravel)                        # entrada (Bolgar)
	for c in [Vector3(-34, 0.025, 2), Vector3(34, 0.025, 2)]:
		g.add_disc(c, 9.0, stone, 0.8)                                    # cavernas dos brutos
	# paredes das galerias (x = ±7), com aberturas para as câmaras laterais
	var z := 26.0
	while z > -52.0:
		var open: bool = absf(z + 8.0) < 3.5 or absf(z + 30.0) < 3.5
		if not open:
			for x in [-7.0, 7.0]:
				w.prop("ruin_wall", o + Vector3(x, 0, z), PI / 2, 1.15, "box", Vector3(4.2, 2.0, 0.9))
		z -= 4.6
	for x in [-4.6, 0.0, 4.6]:
		w.prop("ruin_wall", o + Vector3(x, 0, -56), 0.0, 1.15, "box", Vector3(4.2, 2.0, 0.9))
	# lampiões ao longo da galeria
	for zl in [20.0, 6.0, -16.0, -40.0]:
		for x in [-5.6, 5.6]:
			var lamp: Node3D = w.prop("lamp", o + Vector3(x, 0, zl), PI / 2 if x < 0 else -PI / 2, 0.9, "cyl", Vector3(0.12, 3.7, 0))
			w._light(lamp, Vector3(0, 3.0, 0.4), Color(1.0, 0.7, 0.4), 1.4, 8.0, true)
	# rochas espalhadas e cristais decorativos (os veios de verdade vêm de world_nodes.json)
	var clear := [[Vector2(0, -12), 9.0], [Vector2(0, 40), 8.0], [Vector2(-22, -8), 6.0], [Vector2(22, -8), 6.0],
		[Vector2(-20, -30), 6.0], [Vector2(20, -30), 6.0], [Vector2(-34, 2), 7.0], [Vector2(34, 2), 7.0]]
	for i in 70:
		var p := Vector2(rng.randf_range(-half + 4, half - 4), rng.randf_range(-half + 4, half - 4))
		var ok := true
		for c in clear:
			if p.distance_to(c[0]) < c[1]:
				ok = false
		if ok:
			w.prop("rock", o + Vector3(p.x, 0, p.y), rng.randf() * TAU, rng.randf_range(0.8, 2.2), "cyl", Vector3(0.6, 0.8, 0))
	_forest(w, o, half, rng, {"tree_pine": 3, "tree_fir": 2}, 40, clear + [[Vector2(0, 0), 40.0]])
	# entrada: Bolgar, caixotes, barris e uma bigorna
	w.prop("crate", o + Vector3(9, 0, 30), 0.2, 1.0, "box", Vector3(0.8, 0.8, 0.8))
	w.prop("crate", o + Vector3(9.2, 0.8, 30), -0.3, 0.75)
	w.prop("barrel", o + Vector3(10, 0, 31.6), 0.0, 1.0, "cyl", Vector3(0.38, 1.0, 0))
	w.prop("anvil", o + Vector3(4, 0, 29), 0.4, 1.0, "cyl", Vector3(0.3, 0.8, 0))
	w.add_child(npc("bolgar", o + Vector3(6, 0, 32), PI))
	w.add_child(point("diario", o + Vector3(0, 0, -52)))
	for c in [Vector3(-22, 0, -8), Vector3(22, 0, -8), Vector3(-20, 0, -30), Vector3(20, 0, -30)]:
		var glow := OmniLight3D.new()
		glow.position = o + c + Vector3(0, 1.5, 0)
		glow.light_color = Color(0.6, 0.4, 1.0)
		glow.light_energy = 1.4
		glow.omni_range = 8.0
		w.add_child(glow)
	if w.has_server_enemies():
		for p in [Vector3(-2, 0, 12), Vector3(2, 0, 2), Vector3(-3, 0, -10), Vector3(3, 0, -20), Vector3(-2, 0, -36),
				Vector3(2, 0, -44)]:
			_spawn(w, "esqueleto", o + p, 60.0)
		for p in [Vector3(-22, 0, -8), Vector3(22, 0, -8)]:
			_spawn(w, "esqueleto_arqueiro", o + p, 80.0)
		for p in [Vector3(-20, 0, -30), Vector3(20, 0, -30)]:
			_spawn(w, "esqueleto_mago", o + p, 100.0)
		_spawn(w, "esqueleto_cavaleiro", o + Vector3(0, 0, -48), 300.0)
		for p in [Vector3(-34, 0, 2), Vector3(34, 0, 2)]:
			_spawn(w, "goblin_bruto", o + p, 150.0)


# ---------------------------------------------------------------- Pico das Cinzas
static func _pico(w: Node3D, g: Node3D, o: Vector3, half: float, rng: RandomNumberGenerator) -> void:
	var ash := Color(0.24, 0.22, 0.22)
	var ember := Color(0.42, 0.16, 0.1)
	g.add_rect(Vector3(0, 0.02, 0), Vector2(half * 1.7, half * 1.7), ash, 4.0)
	g.add_rect(Vector3(0, 0.025, 14), Vector2(4.5, 64), Color(0.32, 0.28, 0.26))   # trilha até o topo
	g.add_disc(Vector3(0, 0.025, -34), 15.0, Color(0.18, 0.15, 0.17), 0.9)         # círculo do Lich
	for c in [Vector3(-26, 0.025, 20), Vector3(28, 0.025, -12), Vector3(-30, 0.025, -26), Vector3(22, 0.025, 30)]:
		g.add_disc(c, 6.0, ember, 1.2)                                              # brasas no chão
	# círculo de pedras do Lich
	for i in 10:
		var a := i * TAU / 10.0
		w.prop("ruin_pillar", o + Vector3(0, 0, -34) + Vector3(cos(a), 0, sin(a)) * 13.0, rng.randf() * TAU,
			1.2, "cyl", Vector3(0.5, 4.0, 0))
	for i in 4:
		var a := i * TAU / 4.0 + 0.4
		var l := OmniLight3D.new()
		l.position = o + Vector3(0, 2.0, -34) + Vector3(cos(a), 0, sin(a)) * 9.0
		l.light_color = Color(0.6, 0.3, 1.0)
		l.light_energy = 1.6
		l.omni_range = 10.0
		w.add_child(l)
	# brasas: luzes vermelhas fracas no chão
	for c in [Vector3(-26, 0.5, 20), Vector3(28, 0.5, -12), Vector3(-30, 0.5, -26), Vector3(22, 0.5, 30)]:
		var l := OmniLight3D.new()
		l.position = o + c
		l.light_color = Color(1.0, 0.35, 0.1)
		l.light_energy = 1.3
		l.omni_range = 9.0
		w.add_child(l)
	var clear := [[Vector2(0, -34), 16.0], [Vector2(0, 46), 8.0], [Vector2(0, 20), 6.0], [Vector2(18, -6), 6.0],
		[Vector2(-18, -6), 6.0]]
	for zc in range(-14, 48, 4):
		clear.append([Vector2(0, zc), 3.5])
	for i in 60:
		var p := Vector2(rng.randf_range(-half + 4, half - 4), rng.randf_range(-half + 4, half - 4))
		var ok := true
		for c in clear:
			if p.distance_to(c[0]) < c[1]:
				ok = false
		if ok:
			w.prop("rock", o + Vector3(p.x, 0, p.y), rng.randf() * TAU, rng.randf_range(1.0, 2.6), "cyl", Vector3(0.6, 0.8, 0))
	_forest(w, o, half, rng, {"tree_fir": 2, "tree_pine": 1}, 50, clear, Vector2(0.7, 1.1))
	for p in [Vector3(-6, 0, 2), Vector3(6, 0, -8), Vector3(-8, 0, 30), Vector3(8, 0, 34)]:
		w.prop("ruin_wall", o + p, rng.randf() * TAU, 1.0, "box", Vector3(4.2, 2.0, 0.9))
	w.add_child(npc("kael_pico", o + Vector3(0, 0, 20), PI))
	if w.has_server_enemies():
		for p in [Vector3(-8, 0, 6), Vector3(8, 0, 2), Vector3(-6, 0, -10), Vector3(6, 0, -14), Vector3(-14, 0, -20),
				Vector3(14, 0, -22)]:
			_spawn(w, "esqueleto", o + p, 60.0)
		for p in [Vector3(-12, 0, 14), Vector3(12, 0, 12)]:
			_spawn(w, "esqueleto_arqueiro", o + p, 80.0)
		_spawn(w, "esqueleto_mago", o + Vector3(-22, 0, -30), 100.0)
		for p in [Vector3(-18, 0, -6), Vector3(18, 0, -6)]:
			_spawn(w, "esqueleto_cavaleiro", o + p, 180.0)
		_spawn(w, "lich", o + Vector3(0, 0, -36), 300.0)
