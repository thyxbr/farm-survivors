class_name ColonyVisuals
extends RefCounted
## Modelos das construções da Defesa da Cidade. Cada tipo tem um GLB por nível, gerado por
## tools/blender/buildings.py em assets/models/buildings/<tipo>_<nível>.glb (a casa usa o house.glb).
## make(kind, level) devolve um Node3D centrado na pegada, frente em +Z. Torres têm os nós "Turret"
## (gira para o alvo, com o modelo <tipo>_turret_<nível>.glb) e "Muzzle" (de onde sai o disparo).
## As primitivas no fim do arquivo continuam servindo a bandeira da cidade e os animais.

const HOUSE := preload("res://assets/models/house.glb")
const BARREL := preload("res://assets/models/barrel.glb")
const DIR := "res://assets/models/buildings/"

const WOOD := Color(0.45, 0.3, 0.17)
const WOOD_DARK := Color(0.3, 0.2, 0.11)
const STONE := Color(0.55, 0.54, 0.5)
const STONE_DARK := Color(0.4, 0.39, 0.37)
const IRON := Color(0.28, 0.29, 0.31)
const BANNER := Color(0.18, 0.32, 0.72)

## Torres: modelo que gira, altura do piso onde ele fica (por nível) e ponto de disparo no modelo.
const TURRETS := {
	"archer_tower": {"model": "archer_turret", "y": [4.0, 4.4, 4.8], "muzzle": Vector3(0, 0.9, 0.55)},
	"cannon_tower": {"model": "cannon_turret", "y": [3.14, 3.44, 3.74], "muzzle": Vector3(0, 1.08, 1.12)},
	"mage_tower": {"model": "mage_turret", "y": [7.8, 8.2, 8.6], "muzzle": Vector3.ZERO},
}

static var _mats := {}
static var _scenes := {}


static func make(kind: String, level := 1) -> Node3D:
	var root := Node3D.new()
	root.name = "Visual"
	level = clampi(level, 1, 3)
	if kind == "house":
		_house(root, level)
		return root
	var scene := _scene("%s_%d" % [kind, level])
	if scene:
		root.add_child(scene.instantiate())
	if TURRETS.has(kind):
		var t: Dictionary = TURRETS[kind]
		var turret := Node3D.new()
		turret.name = "Turret"
		turret.position.y = t.y[level - 1]
		root.add_child(turret)
		var ts := _scene("%s_%d" % [t.model, level])
		if ts:
			turret.add_child(ts.instantiate())
		var muzzle := Node3D.new()
		muzzle.name = "Muzzle"
		muzzle.position = t.muzzle
		turret.add_child(muzzle)
	return root


static func _scene(file: String) -> PackedScene:
	if not _scenes.has(file):
		var path := DIR + file + ".glb"
		_scenes[file] = load(path) if ResourceLoader.exists(path) else null
		if _scenes[file] == null:
			push_warning("ColonyVisuals: modelo ausente " + path)
	return _scenes[file]


## Altura aproximada (para a barra de vida, a luz das torres e o nome).
static func height(kind: String) -> float:
	match kind:
		"town_hall":
			return 7.2
		"house":
			return 5.0
		"barracks":
			return 4.6
		"market":
			return 3.2
		"farm":
			return 2.2
		"spikes":
			return 1.4
		"wall":
			return 3.3
		"gate":
			return 4.0
		"archer_tower":
			return 7.6
		"cannon_tower":
			return 4.6
		"mage_tower":
			return 8.6
	return 3.0


static func _house(r: Node3D, level: int) -> void:
	_glb(r, HOUSE, Vector3.ZERO, 0.0, 1.0)
	if level >= 2:
		_glb(r, BARREL, Vector3(2.6, 0, 1.6), 0.0, 0.8)
		_box(r, Vector3(1.4, 0.5, 0.6), Vector3(-1.8, 0.25, 2.4), WOOD)
	if level >= 3:
		_box(r, Vector3(0.44, 0.5, 0.44), Vector3(1.5, 5.89, -1.0), STONE_DARK)   # chaminé mais alta


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
