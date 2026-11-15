extends SceneTree
## Compara dois modelos de personagem com o estilo toon e a luz do jogo, lado a lado (A à esquerda,
## B à direita), em close. Precisa de janela (sem --headless) e do --import feito antes:
##   godot --path . --resolution 1600x900 --script res://tools/face_shot.gd -- merchant merchant_anime <saida.png> [face|hands|body] [graus]
## `graus` gira os dois modelos (0 = de frente, 35 = três quartos, 90 = perfil).

var _frames := 0
var _out := ""
var _models: Array[Node3D] = []
var _mode := "face"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[2]
	_mode = args[3] if args.size() > 3 else "face"
	var yaw := float(args[4]) if args.size() > 4 else 0.0
	WorldLighting.build(root)
	var gap := 0.62 if _mode == "face" else (0.9 if _mode == "hands" else 1.5)
	for i in 2:
		var m := (load("res://assets/models/%s.glb" % args[i]) as PackedScene).instantiate() as Node3D
		root.add_child(m)
		m.position.x = (i - 0.5) * gap
		if _mode == "hands":       # as duas mãos esquerdas no quadro, lado a lado
			m.position.x = -0.55 + i * 0.62
		m.rotation_degrees.y = -yaw
		ToonLook.apply(m)
		_models.append(m)
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	floor_mi.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.47, 0.6, 0.36)
	fm.roughness = 1.0
	floor_mi.material_override = fm
	root.add_child(floor_mi)


func _frame_camera() -> void:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	root.add_child(cam)
	var c := Vector3(0, 0.95, 0)
	match _mode:
		"face":
			cam.size = 0.62
			c.y = 1.78
		"hands":
			cam.size = 0.62
			c.y = 0.86
		_:
			cam.size = 2.2
	cam.look_at_from_position(c + Vector3(0, 0.25 if _mode == "body" else 0.05, 6.0), c)
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
