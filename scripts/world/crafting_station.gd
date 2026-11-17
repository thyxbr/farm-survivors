extends Node3D
## Bancada de craft no mundo (hoje a Bancada de Couraria, ao lado do empório; a forja e a alquimia abrem pelos
## serviços do Doran e da Pip). Mesa de madeira com couro esticado e ferramentas; [E] abre a CraftingUI da
## estação `station` (data/balance/professions.json "stations").

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
	var wood := _mat(Color(0.45, 0.3, 0.17))
	_box(Vector3(0, 0.88, 0), Vector3(2.0, 0.12, 1.0), wood)
	for x in [-0.85, 0.85]:
		for z in [-0.4, 0.4]:
			_box(Vector3(x, 0.42, z), Vector3(0.12, 0.84, 0.12), wood)
	# couro esticado em cima e um rolo de couro do lado
	_box(Vector3(-0.2, 0.96, 0), Vector3(1.1, 0.03, 0.75), _mat(Color(0.62, 0.42, 0.24)))
	var roll := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.14
	cyl.bottom_radius = 0.14
	cyl.height = 0.8
	roll.mesh = cyl
	roll.rotation.x = PI / 2
	roll.position = Vector3(0.7, 1.08, 0)
	roll.material_override = _mat(Color(0.5, 0.33, 0.18))
	add_child(roll)
	if ResourceLoader.exists(CRATE):
		var crate: Node3D = (load(CRATE) as PackedScene).instantiate()
		crate.position = Vector3(1.6, 0, 0.3)
		crate.scale = Vector3.ONE * 0.8
		add_child(crate)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


func _box(pos: Vector3, size: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = m
	add_child(mi)


func interact_prompt() -> String:
	var st: Dictionary = Balance.tables.get_table("professions").get("stations", {}).get(station, {})
	return "Usar a %s" % str(st.get("name", "bancada"))


func interact(_player: Node) -> void:
	var world := get_tree().current_scene
	if world.has_method("open_crafting"):
		world.open_crafting(station)
