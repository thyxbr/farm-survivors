extends Node3D
## Bancada de craft no mundo: a Bancada de Couraria (dentro da oficina do artesão, na praça) e a Bancada da Pip
## (a mesa de alquimia, no laboratório ao lado da botica). A forja abre pelos serviços do Doran. [E] abre a
## CraftingUI da estação `station` (data/balance/professions.json "stations"). Cada estação tem a mesa dela,
## montada aqui com caixas e cilindros (o galpão em volta é o modelo da construção).

const CRATE := "res://assets/models/crate.glb"

var station := "leather"
var npc_id := "station"   # lido pelo teste e pela depuração junto com os NPCs


func _ready() -> void:
	add_to_group("interactable")
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 1.0, 1.0)
	cs.shape = box
	cs.position.y = 0.5
	body.add_child(cs)
	add_child(body)
	if DisplayServer.get_name() == "headless":
		return
	if station == "alchemy":
		_alchemy_table()
	else:
		_leather_bench()


## Mesa de couraria: tampo de tábuas, couro esticado preso com pregos, faca, sovela, carretéis de linha, rolo
## de couro e um caixote de retalhos do lado.
func _leather_bench() -> void:
	var wood := _mat(Color(0.45, 0.3, 0.17))
	var dark := _mat(Color(0.26, 0.16, 0.08))
	_box(Vector3(0, 0.88, 0), Vector3(2.0, 0.12, 1.0), wood)
	for x in [-0.85, 0.85]:
		for z in [-0.4, 0.4]:
			_box(Vector3(x, 0.42, z), Vector3(0.12, 0.84, 0.12), dark)
	_box(Vector3(0, 0.2, 0), Vector3(1.8, 0.05, 0.85), wood)   # prateleira de baixo
	for i in 3:
		_cyl(Vector3(-0.6 + i * 0.6, 0.32, 0), 0.11, 0.7, _mat([Color(0.62, 0.42, 0.24), Color(0.45, 0.28, 0.14),
			Color(0.55, 0.22, 0.14)][i]), Vector3(0, 0, PI / 2))
	_box(Vector3(-0.2, 0.96, 0), Vector3(1.1, 0.03, 0.75), _mat(Color(0.62, 0.42, 0.24)))
	for p in [Vector3(-0.72, 0.98, -0.34), Vector3(0.32, 0.98, -0.34), Vector3(-0.72, 0.98, 0.34), Vector3(0.32, 0.98, 0.34)]:
		_box(p, Vector3(0.03, 0.03, 0.03), _mat(Color(0.75, 0.75, 0.8)))   # pregos nos cantos do couro
	_box(Vector3(0.1, 0.99, 0.15), Vector3(0.3, 0.015, 0.04), _mat(Color(0.8, 0.82, 0.86)), Vector3(0, 0.5, 0))   # faca
	_cyl(Vector3(0.55, 1.0, -0.25), 0.05, 0.12, _mat(Color(0.75, 0.2, 0.15)))   # carretéis
	_cyl(Vector3(0.68, 1.0, -0.25), 0.05, 0.12, _mat(Color(0.2, 0.35, 0.7)))
	_cyl(Vector3(0.7, 1.08, 0.2), 0.14, 0.8, _mat(Color(0.5, 0.33, 0.18)), Vector3(PI / 2, 0, 0))
	if ResourceLoader.exists(CRATE):
		var crate: Node3D = (load(CRATE) as PackedScene).instantiate()
		crate.position = Vector3(1.55, 0, 0.35)
		crate.scale = Vector3.ONE * 0.75
		add_child(crate)


## Mesa de alquimia: tampo de pedra sobre pés de madeira, almofariz com pilão, livro aberto, três frascos que
## brilham, um balão sobre o fogareiro (a chama acesa) e uma vela; luz verde fraca em cima da mesa.
func _alchemy_table() -> void:
	var wood := _mat(Color(0.3, 0.19, 0.1))
	var stone := _mat(Color(0.42, 0.4, 0.46))
	_box(Vector3(0, 0.86, 0), Vector3(2.0, 0.1, 1.0), stone)
	_box(Vector3(0, 0.79, 0), Vector3(1.9, 0.05, 0.9), wood)
	for x in [-0.85, 0.85]:
		for z in [-0.38, 0.38]:
			_box(Vector3(x, 0.4, z), Vector3(0.12, 0.8, 0.12), wood)
	_box(Vector3(0, 0.22, 0), Vector3(1.8, 0.05, 0.8), wood)
	for i in 4:   # potes na prateleira de baixo
		_cyl(Vector3(-0.6 + i * 0.4, 0.34, 0.05), 0.1, 0.2, _mat([Color(0.55, 0.3, 0.15), Color(0.4, 0.38, 0.35)][i % 2]))
	# almofariz e pilão
	_cyl(Vector3(-0.65, 0.98, 0.15), 0.13, 0.14, stone)
	_cyl(Vector3(-0.62, 1.1, 0.15), 0.025, 0.25, wood, Vector3(0, 0, 0.5))
	# livro aberto
	_box(Vector3(-0.15, 0.93, 0.1), Vector3(0.5, 0.03, 0.36), _mat(Color(0.45, 0.12, 0.1)), Vector3(0, 0.2, 0))
	_box(Vector3(-0.15, 0.95, 0.1), Vector3(0.46, 0.02, 0.32), _mat(Color(0.92, 0.86, 0.7)), Vector3(0, 0.2, 0))
	# frascos que brilham
	for i in 3:
		var c: Color = [Color(0.3, 1.0, 0.45), Color(0.75, 0.35, 1.0), Color(0.3, 0.55, 1.0)][i]
		_cyl(Vector3(0.25 + i * 0.16, 1.0, -0.3), 0.06, 0.18, _glow(c))
	# balão de vidro sobre o fogareiro
	_cyl(Vector3(0.7, 0.98, 0.15), 0.12, 0.12, _mat(Color(0.18, 0.17, 0.17)))
	_cyl(Vector3(0.7, 1.04, 0.15), 0.06, 0.04, _glow(Color(1.0, 0.45, 0.1)))
	var flask := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.12
	sph.height = 0.24
	flask.mesh = sph
	flask.position = Vector3(0.7, 1.2, 0.15)
	flask.material_override = _glow(Color(0.35, 1.0, 0.5))
	add_child(flask)
	_cyl(Vector3(0.7, 1.36, 0.15), 0.03, 0.12, _glow(Color(0.35, 1.0, 0.5)))
	# vela
	_cyl(Vector3(-0.85, 0.98, -0.3), 0.035, 0.14, _mat(Color(0.95, 0.92, 0.8)))
	_cyl(Vector3(-0.85, 1.08, -0.3), 0.015, 0.05, _glow(Color(1.0, 0.8, 0.35)))
	var l := OmniLight3D.new()
	l.light_color = Color(0.5, 1.0, 0.6)
	l.light_energy = 0.7
	l.omni_range = 3.0
	l.position = Vector3(0.3, 1.6, 0)
	add_child(l)


func _glow(c: Color) -> StandardMaterial3D:
	var m := _mat(c)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 1.4
	return m


func _cyl(pos: Vector3, r: float, h: float, m: Material, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 10
	mi.mesh = c
	mi.position = pos
	mi.rotation = rot
	mi.material_override = m
	add_child(mi)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


func _box(pos: Vector3, size: Vector3, m: Material, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.rotation = rot
	mi.material_override = m
	add_child(mi)


func interact_prompt() -> String:
	var st: Dictionary = Balance.tables.get_table("professions").get("stations", {}).get(station, {})
	return "Usar a %s" % str(st.get("name", "bancada"))


func interact(_player: Node) -> void:
	var world := get_tree().current_scene
	if world.has_method("open_crafting"):
		world.open_crafting(station)
