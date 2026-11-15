extends SceneTree
## Compara dois modelos de personagem com o estilo toon e a luz do jogo, lado a lado (A à esquerda,
## B à direita), em close. Precisa de janela (sem --headless) e do --import feito antes:
##   godot --path . --resolution 1600x900 --script res://tools/face_shot.gd -- merchant merchant_anime <saida.png> [face|hands|body|torso|legs] [graus] [clipe] [t]
## `graus` gira os dois modelos (0 = de frente, 35 = três quartos, 90 = perfil).
## `clipe` e `t` (s) param os dois modelos num quadro de um clipe embutido no GLB (ex.: idle 0 tira os
## personagens com esqueleto da pose T; work_hammer 0.433 confere os pesos no golpe). Hammer e Tongs, se
## existirem, são presos às mãos como no jogo.

var _frames := 0
var _out := ""
var _models: Array[Node3D] = []
var _mode := "face"
var _clip := ""
var _clip_t := 0.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[2]
	_mode = args[3] if args.size() > 3 else "face"
	var yaw := float(args[4]) if args.size() > 4 else 0.0
	WorldLighting.build(root)
	var gap := 0.62 if _mode == "face" else (0.9 if _mode in ["hands", "torso", "legs"] else 1.5)
	for i in 2:
		var m := (load("res://assets/models/%s.glb" % args[i]) as PackedScene).instantiate() as Node3D
		root.add_child(m)
		m.position.x = (i - 0.5) * gap
		if _mode == "hands":       # as duas mãos esquerdas no quadro, lado a lado
			m.position.x = -0.55 + i * 0.62
		m.rotation_degrees.y = -yaw
		ToonLook.apply(m)
		_models.append(m)
	if args.size() > 5:
		_clip = args[5]
		_clip_t = float(args[6]) if args.size() > 6 else 0.0
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	floor_mi.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.47, 0.6, 0.36)
	fm.roughness = 1.0
	floor_mi.material_override = fm
	root.add_child(floor_mi)


## Para o modelo num quadro de um clipe do próprio GLB, com o martelo e a tenaz presos às mãos.
func _pose(m: Node3D, clip: String, t: float) -> void:
	var players := m.find_children("*", "AnimationPlayer", true, false)
	var skels := m.find_children("*", "Skeleton3D", true, false)
	if players.is_empty() or skels.is_empty():
		return
	var sk := skels[0] as Skeleton3D
	for pair in [["Hammer", "RightHand"], ["Tongs", "LeftHand"]]:
		var n := m.find_child(pair[0], true, false) as Node3D
		if n == null:
			continue
		for i in sk.get_bone_count():
			if sk.get_bone_name(i).ends_with(pair[1]):
				var ba := BoneAttachment3D.new()
				sk.add_child(ba)
				ba.bone_idx = i
				var local := sk.get_bone_global_rest(i).affine_inverse() * sk.global_transform.affine_inverse() * n.global_transform
				n.reparent(ba, false)
				n.transform = local
	var ap := players[0] as AnimationPlayer
	ap.play(clip)
	ap.seek(t, true)
	ap.pause()


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
		"torso":
			cam.size = 0.95
			c.y = 1.2
		"legs":
			cam.size = 0.95
			c.y = 0.42
		_:
			cam.size = 2.2
	cam.look_at_from_position(c + Vector3(0, 0.25 if _mode == "body" else 0.05, 6.0), c)
	cam.current = true


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_frame_camera()
		if _clip != "":      # só aqui os modelos já estão na árvore (o encaixe do martelo usa transformações globais)
			for m in _models:
				_pose(m, _clip, _clip_t)
	if _frames < 14:
		return false
	root.get_texture().get_image().save_png(_out)
	print("SHOT ", _out)
	return true
