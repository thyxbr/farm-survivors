extends Node3D
## Foto do ferreiro na ferraria (bigorna e forja montadas como no mundo), com a luz do jogo. Serve para
## conferir o golpe na bigorna, os pés no chão e o estilo ao lado de Bram e Mira sem abrir o jogo.
## Precisa de janela (sem --headless) e do --import feito antes:
##   godot --path . --resolution 1600x900 res://tools/blacksmith_shot.tscn -- <saida.png> [work|pause|idle|talk] [t] [3q|side|front|close] [lineup]
## t = tempo (s) em que o clipe fica parado (padrão: o golpe do work_hammer, ou 0,5 s).
## side = perfil ortográfico (golpe x bigorna); close = o mesmo close do diálogo no jogo (world.gd);
## lineup = Bram e Mira ao lado, para comparar o estilo.
## Imprime a distância entre o ponto mais baixo do martelo e o StrikePoint da bigorna.

const BLACKSMITH := preload("res://scripts/world/blacksmith.gd")
const NPC := preload("res://scripts/world/npc.gd")
const WORLD := preload("res://scripts/world/world.gd")
const ANVIL := preload("res://assets/models/anvil.glb")
const FORGE := preload("res://assets/models/forge.glb")
const CLIPS := {"work": "work_hammer", "pause": "work_pause", "idle": "idle", "talk": "talk"}

var _frames := 0
var _out := ""
var _smith: Blacksmith
var _cam: Camera3D
var _view := "3q"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://blacksmith_shot.png"
	var mode := "work"
	var t := -1.0
	for a: String in args.slice(1):
		if CLIPS.has(a):
			mode = a
		elif a in ["3q", "side", "front", "close"]:
			_view = a
		elif a.is_valid_float():
			t = float(a)
	if t < 0.0:
		t = BLACKSMITH.STRIKES[CLIPS[mode]][0] if BLACKSMITH.STRIKES.has(CLIPS[mode]) else 0.5
	WorldLighting.build(self)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.45, 0.24)
	ground.material_override = gm
	add_child(ground)
	# ferreiro na origem virado para +Z; bigorna e forja nas mesmas posições relativas do mundo
	var anvil := ANVIL.instantiate() as Node3D
	anvil.position = BLACKSMITH.ANVIL_OFFSET
	anvil.rotation.y = BLACKSMITH.ANVIL_YAW
	add_child(anvil)
	var forge := FORGE.instantiate() as Node3D
	forge.position = BLACKSMITH.FORGE_OFFSET
	forge.rotation.y = BLACKSMITH.FORGE_YAW
	add_child(forge)
	_smith = BLACKSMITH.new()
	_smith.anvil = anvil
	add_child(_smith)
	_smith.set_process(false)   # sem máquina de estados: o clipe fica parado no tempo pedido
	_smith.anim.play(_smith.clip(CLIPS[mode]))
	_smith.anim.seek(t, true)
	_smith.anim.pause()
	if "lineup" in args:
		for pair in [["elder", -2.1], ["merchant", 2.1]]:
			var n := NPC.new()
			n.npc_id = pair[0]
			n.position = Vector3(pair[1], 0, 0)
			add_child(n)
			n.set_process(false)
	print("SMITH %s t=%.3f view=%s" % [CLIPS[mode], t, _view])
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true


func _place_camera() -> void:
	match _view:
		"side":   # perfil pela direita do ferreiro (-X): ferreiro à esquerda, bigorna à direita
			_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			_cam.size = 2.3
			_cam.look_at_from_position(Vector3(-6, 1.0, 0.35), Vector3(0, 1.0, 0.35))
		"front":
			_cam.fov = 35.0
			_cam.look_at_from_position(Vector3(0, 1.3, 5.5), Vector3(0, 0.95, 0))
		"close":   # mesma conta do world._start_closeup
			var face := _smith.face_point()
			var dir := _smith.face_dir().rotated(Vector3.UP, WORLD.CLOSEUP_ANGLE)
			var pos := face + dir * WORLD.CLOSEUP_DIST + Vector3.UP * 0.03
			_cam.fov = WORLD.CLOSEUP_FOV
			_cam.near = 0.03
			_cam.look_at_from_position(pos, face - Vector3.UP * 0.09)
		_:
			_cam.fov = 35.0
			_cam.look_at_from_position(Vector3(3.2, 1.9, 3.6), Vector3(0, 0.85, 0.2))


## Ponto mais baixo do martelo (na batida, a cabeça) e a distância dele ao StrikePoint.
func _report_hammer() -> void:
	var hammer := _smith.model.find_child("Hammer", true, false) as Node3D
	if hammer == null:
		return
	var pts: Array[Vector3] = []
	var meshes: Array = hammer.find_children("*", "MeshInstance3D", true, false)
	if hammer is MeshInstance3D:
		meshes.append(hammer)
	for mi: MeshInstance3D in meshes:
		for v: Vector3 in mi.mesh.get_faces():
			pts.append(mi.global_transform * v)
	var min_y := INF
	for g in pts:
		min_y = minf(min_y, g.y)
	# centro da faixa de 1 cm mais baixa (na batida, o meio da face)
	var low := Vector3.ZERO
	var n := 0
	for g in pts:
		if g.y < min_y + 0.01:
			low += g
			n += 1
	low /= n
	var sp := _smith.strike_pos()
	# na pose T: cabo = -Y do Blender (+Z aqui), face da cabeça = -X (igual aqui)
	var b := hammer.global_basis.orthonormalized()
	print("HAMMER low=%s strike=%s gap=%.3f dy=%.3f cabo=%s face=%s" % [low, sp, low.distance_to(sp), low.y - sp.y,
		b * Vector3.BACK, b * Vector3.LEFT])


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 3:
		_place_camera()   # face_point segue o osso Head: só depois que a pose parada foi aplicada
		_report_hammer()
	if _frames < 12:
		return
	get_viewport().get_texture().get_image().save_png(_out)
	print("SHOT ", _out)
	get_tree().quit()
