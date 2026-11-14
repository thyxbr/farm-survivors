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
	if kind == "lumber_camp" or kind == "quarry":   # modelos procedurais, sem .glb
		if kind == "lumber_camp":
			_lumber_camp(root, level)
		else:
			_quarry(root, level)
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
		"lumber_camp":
			return 3.0
		"quarry":
			return 2.4
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


## Serraria: galpão aberto de toras, pilha de lenha, tocos e caixotes. Cada nível aumenta o galpão e a pilha.
static func _lumber_camp(r: Node3D, level: int) -> void:
	var w := 3.4 + 0.4 * (level - 1)
	_box(r, Vector3(w, 0.2, 2.6), Vector3(-0.6, 0.1, -0.5), WOOD_DARK)                  # piso
	for sx in [-1.0, 1.0]:                                                             # postes e fundo
		for sz in [-1.0, 1.0]:
			_cyl(r, 0.14, 0.16, 2.4, Vector3(-0.6 + sx * (w * 0.5 - 0.15), 1.4, -0.5 + sz * 1.1), WOOD, 8)
	_box(r, Vector3(w, 1.6, 0.14), Vector3(-0.6, 1.1, -1.55), WOOD_DARK)
	_box(r, Vector3(w + 0.6, 0.18, 3.0), Vector3(-0.6, 2.7, -0.5), WOOD, Vector3(0.14, 0, 0))   # telhado inclinado
	_box(r, Vector3(1.8, 0.25, 0.5), Vector3(-0.6, 0.8, -0.3), STONE_DARK)              # bancada da serra
	_box(r, Vector3(0.1, 0.55, 0.9), Vector3(-0.6, 1.2, -0.3), IRON)                    # lâmina
	# pilha de toras deitadas
	var rows := 2 + level
	for row in rows:
		for i in (4 - row):
			_cyl(r, 0.22, 0.22, 2.0, Vector3(2.0 + (i - (3 - row) * 0.5) * 0.46, 0.25 + row * 0.4, 1.0), WOOD,
				8, Vector3(PI / 2, 0, 0))
	_cyl(r, 0.35, 0.4, 0.5, Vector3(-2.6, 0.25, 1.4), WOOD_DARK, 10)                      # toco com machado
	_box(r, Vector3(0.08, 0.7, 0.08), Vector3(-2.6, 0.85, 1.4), WOOD, Vector3(0, 0, 0.5))
	_box(r, Vector3(0.5, 0.5, 0.5), Vector3(1.8, 0.25, -1.4), WOOD)                     # caixote
	if level >= 2:
		_box(r, Vector3(0.5, 0.5, 0.5), Vector3(1.8, 0.75, -1.4), WOOD_DARK)
		_glb(r, BARREL, Vector3(-2.6, 0, -1.3), 0.0, 0.8)


## Pedreira: blocos de pedra, bloco em corte, carrinho com carga e barril.
static func _quarry(r: Node3D, level: int) -> void:
	_box(r, Vector3(4.6, 0.12, 3.6), Vector3(0, 0.06, 0), STONE_DARK)                     # chão de pedra batida
	_box(r, Vector3(1.6, 1.0, 1.3), Vector3(-1.4, 0.55, -0.6), STONE, Vector3(0, 0.3, 0))
	_box(r, Vector3(1.1, 0.8, 1.0), Vector3(-1.2, 1.4, -0.5), STONE_DARK, Vector3(0, 0.6, 0))
	_box(r, Vector3(1.3, 0.7, 1.0), Vector3(0.4, 0.4, -1.1), STONE, Vector3(0, -0.2, 0))
	_box(r, Vector3(0.7, 0.5, 0.7), Vector3(1.9, 0.3, -0.9), STONE_DARK, Vector3(0, 0.4, 0))
	_box(r, Vector3(0.12, 1.0, 0.12), Vector3(-2.2, 0.7, 0.4), WOOD, Vector3(0, 0, 0.35))  # picareta
	_box(r, Vector3(0.6, 0.12, 0.12), Vector3(-2.3, 1.2, 0.4), IRON, Vector3(0, 0, 0.35))
	# carrinho de mão com pedras
	_box(r, Vector3(1.2, 0.5, 0.9), Vector3(1.0, 0.65, 1.1), WOOD)
	_box(r, Vector3(0.8, 0.3, 0.6), Vector3(1.0, 1.0, 1.1), STONE)
	_cyl(r, 0.3, 0.3, 0.12, Vector3(1.7, 0.3, 1.1), WOOD_DARK, 10, Vector3(0, 0, PI / 2))
	_box(r, Vector3(0.9, 0.08, 0.08), Vector3(0.0, 0.7, 0.8), WOOD_DARK)
	_box(r, Vector3(0.9, 0.08, 0.08), Vector3(0.0, 0.7, 1.4), WOOD_DARK)
	_glb(r, BARREL, Vector3(-0.4, 0, 1.6), 0.0, 0.8)
	if level >= 2:
		_box(r, Vector3(1.0, 0.7, 1.0), Vector3(2.1, 0.45, 0.4), STONE)
		_box(r, Vector3(0.9, 0.6, 0.9), Vector3(2.1, 1.05, 0.4), STONE_DARK, Vector3(0, 0.3, 0))
	if level >= 3:
		_box(r, Vector3(1.4, 0.9, 1.1), Vector3(-0.2, 0.5, -1.6), STONE_DARK)


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
