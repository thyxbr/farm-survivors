extends SceneTree
## Foto de objetos de cenário (assets/models/<id>.glb) lado a lado, com a luz do jogo, o toon e
## um pedaço de chão com grama de verdade (Ground.scatter_grass). Serve para conferir props e capim
## sem abrir o jogo. Precisa de janela (sem --headless) e do --import feito antes:
##   godot --path . --resolution 1600x900 --script res://tools/prop_shot.gd -- <saida.png> tent,crate,barrel [close] [low]
## close = câmera mais perto (metade da largura); low = câmera na altura dos olhos.

var _frames := 0
var _out := ""
var _models: Array[Node3D] = []
var _close := false
var _low := false


func _setup() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0]
	var ids: PackedStringArray = args[1].split(",") if args.size() > 1 else PackedStringArray(["tent", "crate", "barrel"])
	_close = "close" in args
	_low = "low" in args
	WorldLighting.build(root)
	var x := 0.0
	var widths: Array[float] = []
	for id in ids:
		var m := (load("res://assets/models/%s.glb" % id) as PackedScene).instantiate() as Node3D
		root.add_child(m)
		m.rotation_degrees.y = -30.0
		_models.append(m)
		var box := _box(m)
		widths.append(maxf(box.size.x, box.size.z))
	var total := 0.0
	for w in widths:
		total += w + 0.6
	x = -total / 2.0
	for i in _models.size():
		_models[i].position.x = x + widths[i] / 2.0 + 0.3
		x += widths[i] + 0.6
	for m in _models:
		ToonLook.apply(m)
	var ground = load("res://scripts/world/ground.gd").new()
	root.add_child(ground)
	ground.setup(14.0)
	ground.add_disc(Vector3(0, 0.02, 0), 0.01, Color(0.4, 0.3, 0.2), 0.1)
	var keep := []
	for m in _models:
		var b := _box(m)
		keep.append([Vector2(m.position.x, m.position.z), maxf(b.size.x, b.size.z) * 0.45])
	ground.scatter_grass(11, 0.55, keep, [])


func _box(m: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _frame_camera() -> void:
	var box := AABB()
	var first := true
	for m in _models:
		var b := _box(m)
		box = b if first else box.merge(b)
		first = false
	var cam := Camera3D.new()
	cam.fov = 40.0
	var c := box.get_center()
	var w := box.size.x * (0.5 if _close else 1.0)
	var dist := w / (2.0 * tan(deg_to_rad(cam.fov * 0.5))) * 0.95 + box.size.z * 0.5
	if _close:
		c.x = _models[0].position.x
	cam.position = Vector3(c.x, (1.2 if _low else c.y + dist * 0.35), c.z + dist)
	root.add_child(cam)
	cam.look_at(Vector3(c.x, c.y * (0.8 if _low else 0.6), c.z))
	cam.current = true


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_setup()
	if _frames == 3:
		_frame_camera()
	if _frames < 24:
		return false
	root.get_texture().get_image().save_png(_out)
	print("SHOT ", _out)
	return true
