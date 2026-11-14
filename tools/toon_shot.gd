extends SceneTree
## Foto de um personagem (assets/models/<id>.glb) com a luz do jogo, lado a lado: como está hoje à
## esquerda e com o ToonLook à direita. Precisa de janela (sem --headless) e do --import feito antes:
##   godot --path . --resolution 1400x1000 --script res://tools/toon_shot.gd -- merchant <saida.png> [3q] [close]
## Com `slime`, aceita também `goo=RRGGBBAA` (cor da variante, como em data/balance/enemies.json).

var _frames := 0
var _out := ""
var _models: Array[Node3D] = []
var _close := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var id: String = args[0]
	_out = args[1]
	_close = "close" in args
	WorldLighting.build(root)
	var scene := load("res://assets/models/%s.glb" % id) as PackedScene
	for i in 2:
		var m := scene.instantiate() as Node3D
		root.add_child(m)
		m.position.x = (i - 0.5) * 1.5
		if "3q" in args:
			m.rotation_degrees.y = -35.0
		_models.append(m)
	if id == "slime":
		_slime_goo(args)
	print("TOON_SURFACES ", ToonLook.apply(_models[1]))
	# chão claro para a sombra projetada e o contato aparecerem
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	floor_mi.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.47, 0.6, 0.36)
	fm.roughness = 1.0
	floor_mi.material_override = fm
	root.add_child(floor_mi)


## Slime: a gelatina é posta por código (enemy.gd), então a foto repete os dois caminhos: o material
## translúcido antigo à esquerda e ToonLook.apply_slime à direita. `goo=RRGGBBAA` troca a cor (variantes).
func _slime_goo(args: PackedStringArray) -> void:
	var goo := ToonLook.SLIME_GOO
	for a in args:
		if a.begins_with("goo="):
			goo = Color.html(a.substr(4))
	var old := StandardMaterial3D.new()
	old.albedo_color = goo
	old.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	old.roughness = 0.1
	old.rim_enabled = true
	old.rim = 0.6
	for n in ["BodyMesh", "Base"]:
		var mi := _models[0].find_child(n, true, false) as MeshInstance3D
		if mi:
			mi.material_override = old
	ToonLook.apply_slime(_models[1], goo)


func _frame_camera() -> void:
	var box := AABB()
	var first := true
	for m in _models:
		for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
			var b := mi.global_transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var vp := root.get_visible_rect().size
	var c := box.get_center()
	if _close:
		cam.size = 1.55
		c.y = box.end.y - 0.50
	else:
		cam.size = maxf(box.size.y, box.size.x * vp.y / vp.x) * 1.06
	# câmera levemente de cima, como a 3ª pessoa do jogo
	cam.position = Vector3(c.x, c.y + 1.2, box.end.z + 6.0)
	root.add_child(cam)
	cam.look_at(c)
	cam.current = true


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_frame_camera()
	if _frames < 14:
		return false
	root.get_texture().get_image().save_png(_out)
	print("SHOT ", _out)
	return true
