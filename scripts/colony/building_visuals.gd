class_name ColonyVisuals
extends RefCounted
## Modelos das construções da Defesa da Cidade, montados com primitivas (e alguns GLBs do cenário).
## make(kind, level) devolve um Node3D centrado na pegada. Torres têm os nós "Turret" (gira para o alvo)
## e "Muzzle" (de onde sai o disparo).

const HOUSE := preload("res://assets/models/house.glb")
const TENT := preload("res://assets/models/tent.glb")
const CRATE := preload("res://assets/models/crate.glb")
const BARREL := preload("res://assets/models/barrel.glb")
const FENCE := preload("res://assets/models/fence.glb")
const CAMPFIRE := preload("res://assets/models/campfire.glb")
const CHEST := preload("res://assets/models/chest.glb")

const WOOD := Color(0.45, 0.3, 0.17)
const WOOD_DARK := Color(0.3, 0.2, 0.11)
const STONE := Color(0.55, 0.54, 0.5)
const STONE_DARK := Color(0.4, 0.39, 0.37)
const ROOF_RED := Color(0.62, 0.2, 0.14)
const IRON := Color(0.28, 0.29, 0.31)
const BANNER := Color(0.18, 0.32, 0.72)

static var _mats := {}


static func make(kind: String, level := 1) -> Node3D:
	var root := Node3D.new()
	root.name = "Visual"
	match kind:
		"town_hall":
			_town_hall(root, level)
		"house":
			_house(root, level)
		"farm":
			_farm(root, level)
		"market":
			_market(root, level)
		"barracks":
			_barracks(root, level)
		"wall":
			_wall(root, level)
		"gate":
			_gate(root, level)
		"spikes":
			_spikes(root, level)
		"archer_tower":
			_archer_tower(root, level)
		"cannon_tower":
			_cannon_tower(root, level)
		"mage_tower":
			_mage_tower(root, level)
	return root


## Altura aproximada (para a barra de vida e o nome).
static func height(kind: String) -> float:
	match kind:
		"town_hall":
			return 6.5
		"house", "market", "barracks":
			return 4.2
		"farm", "spikes":
			return 1.6
		"wall", "gate":
			return 3.2
		"archer_tower":
			return 6.6
		"cannon_tower":
			return 5.0
		"mage_tower":
			return 7.6
	return 3.0


# ================================================================ cidade
static func _town_hall(r: Node3D, level: int) -> void:
	_box(r, Vector3(7.4, 0.35, 6.4), Vector3(0, 0.17, 0), STONE_DARK)
	var h := _glb(r, HOUSE, Vector3(0, 0.3, 0), 0.0, 1.3)
	h.scale = Vector3(1.3, 1.25 + 0.08 * (level - 1), 1.3)
	# torre do sino com bandeira
	_box(r, Vector3(1.6, 5.4 + level * 0.4, 1.6), Vector3(2.6, 2.7 + level * 0.2, -1.8), STONE)
	_cyl(r, 0.0, 1.25, 1.4, Vector3(2.6, 6.1 + level * 0.4, -1.8), ROOF_RED, 4, Vector3(0, PI / 4, 0))
	_cyl(r, 0.05, 0.05, 2.2, Vector3(2.6, 7.6 + level * 0.4, -1.8), WOOD_DARK)
	_box(r, Vector3(1.2, 0.7, 0.04), Vector3(3.2, 8.2 + level * 0.4, -1.8), Color(0.85, 0.65, 0.2))
	# degraus e tochas
	_box(r, Vector3(2.4, 0.2, 0.8), Vector3(0, 0.1, 3.4), STONE)
	for x in [-1.6, 1.6]:
		_cyl(r, 0.07, 0.07, 1.8, Vector3(x, 0.9, 3.5), WOOD_DARK)
		_sphere(r, 0.16, Vector3(x, 1.9, 3.5), Color(1.0, 0.6, 0.2), 3.0)
	if level >= 2:
		for x in [-3.3, 3.3]:
			_box(r, Vector3(0.6, 1.2, 0.6), Vector3(x, 0.6, 2.9), STONE)
	if level >= 3:
		_box(r, Vector3(0.9, 1.5, 0.05), Vector3(0, 3.6, 3.0), BANNER)


static func _house(r: Node3D, level: int) -> void:
	_glb(r, HOUSE, Vector3.ZERO, 0.0, 1.0)
	if level >= 2:
		_glb(r, BARREL, Vector3(2.6, 0, 1.6), 0.0, 0.8)
		_box(r, Vector3(1.4, 0.5, 0.6), Vector3(-1.8, 0.25, 2.4), WOOD)
	if level >= 3:
		_box(r, Vector3(0.6, 1.4, 0.6), Vector3(1.4, 4.0, -0.6), STONE_DARK)   # chaminé


static func _farm(r: Node3D, level: int) -> void:
	_flat(r, Vector2(6.6, 5.0), Vector3(0, 0.03, 0.4), Color(0.36, 0.25, 0.15))
	var crop := Color(0.5, 0.68, 0.18).lerp(Color(0.85, 0.72, 0.25), 0.25 * (level - 1))
	for row in 4:
		for col in 7:
			var p := Vector3(-2.7 + col * 0.9, 0.3, -1.3 + row * 1.2)
			_cyl(r, 0.0, 0.22, 0.6, p, crop, 4, Vector3(0, (row * 7 + col) * 0.7, 0))
	for x in [-2.0, 0.0, 2.0]:
		_glb(r, FENCE, Vector3(x, 0, -2.75), 0.0, 1.0)
	_glb(r, CRATE, Vector3(2.8, 0, -2.6), 0.3, 0.8)
	_glb(r, BARREL, Vector3(-2.9, 0, -2.5), 0.0, 0.8)
	# espantalho
	_cyl(r, 0.05, 0.05, 1.8, Vector3(0, 0.9, 0.4), WOOD)
	_box(r, Vector3(1.1, 0.07, 0.07), Vector3(0, 1.4, 0.4), WOOD)
	_box(r, Vector3(0.5, 0.55, 0.25), Vector3(0, 1.3, 0.4), Color(0.55, 0.2, 0.15))
	_sphere(r, 0.18, Vector3(0, 1.8, 0.4), Color(0.85, 0.75, 0.5))
	_cyl(r, 0.25, 0.25, 0.05, Vector3(0, 1.95, 0.4), Color(0.95, 0.8, 0.35))


static func _market(r: Node3D, level: int) -> void:
	_box(r, Vector3(5.0, 0.12, 5.0), Vector3(0, 0.06, 0), Color(0.5, 0.45, 0.36))
	_glb(r, TENT, Vector3(0, 0, -0.4), 0.0, 1.3)
	_glb(r, CRATE, Vector3(-1.8, 0, 1.6), 0.2, 0.9)
	_glb(r, CRATE, Vector3(-1.1, 0, 1.9), -0.3, 0.8)
	_glb(r, BARREL, Vector3(1.8, 0, 1.7), 0.0, 0.9)
	_glb(r, CHEST, Vector3(0.4, 0, 1.9), 0.0, 0.9)
	# toldo listrado
	for i in 4:
		var c := Color(0.85, 0.75, 0.3) if i % 2 == 0 else Color(0.7, 0.2, 0.15)
		_box(r, Vector3(0.6, 0.06, 1.2), Vector3(-0.9 + i * 0.6, 2.0, 2.0), c, Vector3(0.35, 0, 0))
	for x in [-1.2, 1.2]:
		_cyl(r, 0.05, 0.05, 2.0, Vector3(x, 1.0, 2.5), WOOD_DARK)
	if level >= 2:
		_glb(r, BARREL, Vector3(2.2, 0, -1.8), 0.0, 0.9)
		_sphere(r, 0.2, Vector3(1.8, 1.05, 1.7), Color(1.0, 0.8, 0.25), 0.6)
	if level >= 3:
		_glb(r, CHEST, Vector3(-2.0, 0, -1.6), 1.2, 0.9)


static func _barracks(r: Node3D, level: int) -> void:
	_box(r, Vector3(6.6, 0.3, 5.6), Vector3(0, 0.15, 0), STONE_DARK)
	_box(r, Vector3(6.0, 2.6, 4.4), Vector3(0, 1.6, -0.3), Color(0.72, 0.62, 0.45))
	# vigas
	for x in [-3.0, 0.0, 3.0]:
		_box(r, Vector3(0.22, 2.6, 0.22), Vector3(x, 1.6, 1.92), WOOD_DARK)
	_box(r, Vector3(6.2, 0.22, 0.22), Vector3(0, 2.85, 1.92), WOOD_DARK)
	# telhado de duas águas
	var roof := ROOF_RED.darkened(0.1 * (level - 1))
	_box(r, Vector3(6.6, 0.18, 2.8), Vector3(0, 3.45, 0.7), roof, Vector3(0.62, 0, 0))
	_box(r, Vector3(6.6, 0.18, 2.8), Vector3(0, 3.45, -1.3), roof, Vector3(-0.62, 0, 0))
	_box(r, Vector3(1.3, 1.9, 0.1), Vector3(0, 1.25, 1.92), WOOD_DARK)   # porta
	# estandartes
	for i in level:
		var x := -2.0 + i * 2.0
		_box(r, Vector3(0.7, 1.2, 0.04), Vector3(x if i < 2 else 2.0, 2.1, 1.98), Color(0.7, 0.12, 0.1))
	# armeiro com lanças
	_box(r, Vector3(1.6, 0.12, 0.3), Vector3(-2.2, 1.2, 2.45), WOOD)
	for i in 4:
		_cyl(r, 0.03, 0.03, 2.0, Vector3(-2.8 + i * 0.4, 1.0, 2.45), WOOD, 6, Vector3(0.15, 0, 0))
		_cyl(r, 0.0, 0.06, 0.25, Vector3(-2.8 + i * 0.4, 2.1, 2.6), IRON, 6, Vector3(0.15, 0, 0))
	_glb(r, BARREL, Vector3(2.6, 0.3, 2.3), 0.0, 0.8)


# ================================================================ defesas
static func _wall(r: Node3D, level: int) -> void:
	if level == 1:
		# paliçada de troncos
		for i in 7:
			var x := -1.71 + i * 0.57
			_cyl(r, 0.27, 0.3, 2.6 + (i % 2) * 0.2, Vector3(x, 1.3, 0), WOOD, 7)
			_cyl(r, 0.0, 0.27, 0.4, Vector3(x, 2.8 + (i % 2) * 0.2, 0), WOOD, 7)
		_box(r, Vector3(4.0, 0.22, 0.2), Vector3(0, 1.8, 0.32), WOOD_DARK)
		_box(r, Vector3(4.0, 0.22, 0.2), Vector3(0, 0.7, 0.32), WOOD_DARK)
		return
	var c := STONE if level == 2 else STONE_DARK
	var h := 2.5 if level == 2 else 3.0
	_box(r, Vector3(4.0, h, 0.9), Vector3(0, h / 2.0, 0), c)
	for i in 3:
		_box(r, Vector3(0.7, 0.45, 0.95), Vector3(-1.4 + i * 1.4, h + 0.22, 0), c)
	_box(r, Vector3(4.02, 0.12, 0.92), Vector3(0, 0.6, 0), c.darkened(0.2))
	if level == 3:
		_box(r, Vector3(4.02, 0.12, 0.92), Vector3(0, 1.8, 0), c.darkened(0.25))


static func _gate(r: Node3D, level: int) -> void:
	var c := STONE if level < 3 else STONE_DARK
	for x in [-1.7, 1.7]:
		_box(r, Vector3(0.7, 3.4, 1.1), Vector3(x, 1.7, 0), c)
		_box(r, Vector3(0.85, 0.3, 1.2), Vector3(x, 3.5, 0), c.darkened(0.15))
	_box(r, Vector3(4.0, 0.5, 1.1), Vector3(0, 3.2, 0), c)
	var door := Color(0.4, 0.26, 0.14) if level == 1 else Color(0.32, 0.2, 0.1)
	_box(r, Vector3(2.7, 2.9, 0.22), Vector3(0, 1.45, 0), door)
	for y in [0.6, 1.5, 2.4]:
		_box(r, Vector3(2.72, 0.12, 0.26), Vector3(0, y, 0), IRON)
	if level >= 2:
		_sphere(r, 0.1, Vector3(0.5, 1.4, 0.15), Color(0.8, 0.65, 0.25))


static func _spikes(r: Node3D, level: int) -> void:
	_box(r, Vector3(4.0, 0.25, 0.35), Vector3(0, 0.13, 0), WOOD_DARK)
	var tip := WOOD if level == 1 else IRON
	var n := 6 + level * 2
	for i in n:
		var x := -1.8 + i * (3.6 / float(n - 1))
		var side := 1.0 if i % 2 == 0 else -1.0
		_cyl(r, 0.0, 0.09, 1.3, Vector3(x, 0.45, side * 0.35), tip, 5, Vector3(side * 0.75, 0, 0))


static func _tower_base(r: Node3D, radius: float, h: float, c: Color) -> void:
	_cyl(r, radius * 0.92, radius, h, Vector3(0, h / 2.0, 0), c, 10)
	_cyl(r, radius * 1.08, radius * 1.08, 0.3, Vector3(0, h + 0.15, 0), c.darkened(0.15), 10)
	for i in 6:
		var a := TAU * i / 6.0
		_box(r, Vector3(0.45, 0.45, 0.35), Vector3(cos(a) * radius, h + 0.5, sin(a) * radius), c, Vector3(0, -a, 0))
	_box(r, Vector3(0.7, 1.2, 0.1), Vector3(0, 0.6, radius - 0.02), WOOD_DARK)   # porta


static func _archer_tower(r: Node3D, level: int) -> void:
	var h := 4.0 + 0.4 * (level - 1)
	_tower_base(r, 1.35, h, STONE if level < 3 else STONE_DARK)
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4
		_cyl(r, 0.06, 0.06, 1.6, Vector3(cos(a) * 1.1, h + 1.1, sin(a) * 1.1), WOOD_DARK)
	_cyl(r, 0.0, 1.75, 1.3, Vector3(0, h + 2.5, 0), ROOF_RED if level < 3 else BANNER, 8)
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position.y = h + 0.3
	r.add_child(turret)
	# arqueiro
	_cyl(turret, 0.18, 0.22, 0.75, Vector3(0, 0.45, 0), Color(0.25, 0.4, 0.2))
	_sphere(turret, 0.16, Vector3(0, 0.98, 0), Color(0.9, 0.72, 0.58))
	_cyl(turret, 0.0, 0.2, 0.25, Vector3(0, 1.17, 0), Color(0.25, 0.4, 0.2))
	_box(turret, Vector3(0.05, 0.9, 0.05), Vector3(0.18, 0.7, 0.35), WOOD)
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0.8, 0.5)
	turret.add_child(muzzle)
	for i in level:
		_box(r, Vector3(0.5, 0.7, 0.03), Vector3(-0.6 + i * 0.6, h - 0.8, 1.42), Color(0.75, 0.15, 0.1))


static func _cannon_tower(r: Node3D, level: int) -> void:
	var h := 3.0 + 0.3 * (level - 1)
	_tower_base(r, 1.75, h, STONE_DARK)
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position.y = h + 0.3
	r.add_child(turret)
	_box(turret, Vector3(1.2, 0.5, 1.4), Vector3(0, 0.25, 0), WOOD_DARK)
	for x in [-0.6, 0.6]:
		_cyl(turret, 0.35, 0.35, 0.12, Vector3(x, 0.3, 0), WOOD, 10, Vector3(0, 0, PI / 2))
	_cyl(turret, 0.26 + 0.03 * level, 0.32 + 0.03 * level, 1.7, Vector3(0, 0.75, 0.35), IRON, 10, Vector3(PI / 2 - 0.25, 0, 0))
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0.95, 1.2)
	turret.add_child(muzzle)
	for i in level:
		_sphere(r, 0.2, Vector3(1.1 - i * 0.45, h + 0.5, -1.0), Color(0.12, 0.12, 0.13))


static func _mage_tower(r: Node3D, level: int) -> void:
	var h := 5.0 + 0.4 * (level - 1)
	var c := Color(0.5, 0.48, 0.58)
	_cyl(r, 0.85, 1.25, h, Vector3(0, h / 2.0, 0), c, 8)
	_cyl(r, 1.25, 1.25, 0.25, Vector3(0, h, 0), c.darkened(0.2), 8)
	_cyl(r, 0.0, 1.3, 2.2, Vector3(0, h + 1.3, 0), Color(0.35, 0.2, 0.6), 8)
	_box(r, Vector3(0.6, 1.1, 0.1), Vector3(0, 0.55, 1.15), WOOD_DARK)
	for i in 3:
		_box(r, Vector3(0.25, 0.35, 0.05), Vector3(0, 1.8 + i * 1.2, 0.98 - i * 0.05), Color(0.6, 0.85, 1.0))
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position.y = h + 2.8
	r.add_child(turret)
	var crystal := _cyl(turret, 0.0, 0.32, 0.55, Vector3(0, 0.27, 0), Color(0.5, 0.85, 1.0), 6)
	crystal.material_override = _glow(Color(0.5, 0.85, 1.0), 2.5)
	var lower := _cyl(turret, 0.32, 0.0, 0.45, Vector3(0, -0.22, 0), Color(0.5, 0.85, 1.0), 6)
	lower.material_override = crystal.material_override
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	turret.add_child(muzzle)
	for i in level:
		var a := TAU * i / 3.0
		_sphere(r, 0.12, Vector3(cos(a) * 1.0, h + 0.4, sin(a) * 1.0), Color(0.6, 0.4, 1.0), 2.0)


# ================================================================ primitivas
static func _mat(c: Color, emission := 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f" % [c.to_html(), emission]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	_mats[key] = m
	return m


static func _glow(c: Color, energy: float) -> StandardMaterial3D:
	return _mat(c, energy)


static func _glb(r: Node3D, scene: PackedScene, pos: Vector3, yaw: float, s: float) -> Node3D:
	var n: Node3D = scene.instantiate()
	n.position = pos
	n.rotation.y = yaw
	n.scale = Vector3.ONE * s
	r.add_child(n)
	return n


static func _box(r: Node3D, size: Vector3, pos: Vector3, c: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _mat(c)
	mi.position = pos
	mi.rotation = rot
	r.add_child(mi)
	return mi


static func _cyl(r: Node3D, top: float, bottom: float, h: float, pos: Vector3, c: Color, seg := 12, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = h
	cm.radial_segments = seg
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = _mat(c)
	mi.position = pos
	mi.rotation = rot
	r.add_child(mi)
	return mi


static func _sphere(r: Node3D, radius: float, pos: Vector3, c: Color, emission := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 10
	s.rings = 6
	mi.mesh = s
	mi.material_override = _mat(c, emission)
	mi.position = pos
	r.add_child(mi)
	return mi


static func _flat(r: Node3D, size: Vector2, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var p := PlaneMesh.new()
	p.size = size
	mi.mesh = p
	mi.material_override = _mat(c)
	mi.position = pos
	r.add_child(mi)
	return mi
