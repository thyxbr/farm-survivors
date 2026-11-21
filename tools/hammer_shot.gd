extends Node3D
## Folha de contato do Martelo de Energia (habilidade 2 da espada com escudo). Precisa de janela (sem --headless):
##   godot --path . --fixed-fps 30 --resolution 960x720 res://tools/hammer_shot.tscn -- <saida.png> [jogo|lado|pose]
## jogo: a linha do tempo inteira vista da câmera do jogo (atrás do herói, recuada como na habilidade).
## lado: a mesma de 3/4, de longe (o círculo lá no alto e o martelo inteiro ao lado do herói).
## pose: o herói erguendo a espada (clipe "Sword And Shield Casting"), de 3/4 e de lado, em 4 instantes.
## Monstros de treino em volta: os de dentro do raio levam o golpe (número de dano), os de fora não.

const KNIGHT := preload("res://assets/models/knight.glb")
const SKILL := preload("res://scenes/vfx/hammer/hammer_skill.tscn")
const CELL := Vector2i(480, 360)

var _out := ""
var _mode := "jogo"
var _t := 0.0
var _frames := 0
var _shots: Array = []
var _plan: Array = []
var _knight: Node3D
var _rig: Dictionary
var _look: Dictionary
var _skill: HammerSkill
var _cfg: HammerConfig
var _done := false
var _dummies: Array = []
var _game_cam: Camera3D
var _tilt := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://hammer_shot.png"
	if args.size() > 1:
		_mode = args[1]
	_cfg = load("res://assets/vfx/hammer/hammer_config.tres")
	WorldLighting.build(self)
	var g := StaticBody3D.new()
	var gm_i := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	gm_i.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.45, 0.22)
	gm_i.material_override = gm
	g.add_child(gm_i)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(60, 0.2, 60)
	cs.shape = bs
	cs.position.y = -0.1
	g.add_child(cs)
	add_child(g)
	if _mode == "pose":
		_pose_sheet()
		return
	_knight = _make_knight(Vector3.ZERO, 0.0)
	# bonecos de treino: dentro do raio (em volta do ponto do impacto) e fora dele
	var center := Vector3(0, 0, _cfg.forward_offset)
	for off in [Vector3(2.0, 0, 1.0), Vector3(-2.6, 0, 1.6), Vector3(0.5, 0, 3.6), Vector3(-1.2, 0, -2.2), Vector3(7.0, 0, 1.0), Vector3(-6.5, 0, 3.0)]:
		var d := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.35
		cm.height = 1.4
		d.mesh = cm
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(0.55, 0.25, 0.25) if (center + off).distance_to(center) <= _cfg.radius else Color(0.3, 0.3, 0.55)
		d.material_override = dm
		add_child(d)
		d.position = center + off + Vector3.UP * 0.7
		_dummies.append(d)
	var cam := Camera3D.new()
	cam.fov = 70.0
	add_child(cam)
	if _mode == "lado":
		cam.fov = 55.0
		cam.look_at_from_position(Vector3(11.0, 5.5, 13.0), Vector3(0, 4.2, 2.2))
	else:
		# câmera do jogo: atrás e um pouco à direita, inclinada -0,25 rad, 4 m + o recuo da habilidade
		var dist := 4.0 + _cfg.camera_back
		var pivot := Vector3(0.0, 1.55, 0.0)
		var back := Vector3(0, sin(0.25), -cos(0.25)) * dist
		cam.position = pivot + back + Vector3(-0.45, 0, 0)
		cam.rotation = Vector3(-0.25, PI, 0.0)   # inclinação inicial; a da habilidade entra em _process
		_game_cam = cam
	cam.current = true
	_skill = SKILL.instantiate()
	_skill.config = _cfg
	_skill.follow = _knight
	_skill.yaw = 0.0
	_skill.seed_value = 1234
	add_child(_skill)
	var it := _cfg.impact_time()
	_plan = [[0.2, "círculo materializando"], [0.5, "círculo formado"], [0.85, "martelo saindo: cabeça"],
		[1.2, "martelo saindo: cabo"], [1.5, "pronto; círculo fechando"], [1.78, "círculo fechou"],
		[it - 0.12, "caindo (rastro)"], [it + 0.04, "impacto"], [it + 0.18, "crateras em onda"], [it + 0.45, "explosão"],
		[it + 0.75, "martelo cravado"], [it + 1.1, "perde o brilho, racha"], [it + 1.6, "dissolve: cabeça"],
		[it + 2.05, "dissolve: cabo"], [it + 3.2, "crateras sumindo"], [it + 5.5, "fim"]]


func _make_knight(pos: Vector3, yaw: float) -> Node3D:
	var m := KNIGHT.instantiate() as Node3D
	add_child(m)
	m.position = pos
	m.rotation.y = yaw
	_look = KnightLook.apply(m, {"weapon": "iron_sword", "offhand": "knight_shield", "armor": "royal_plate",
		"head": "knight_helm", "hands": "iron_gauntlets", "feet": "iron_greaves"})
	_rig = KnightAnim.rig(m)
	return m


func _pose_knight(r: Dictionary, lk: Dictionary, t: float, k := 1.0) -> void:
	var p := KnightAnim.idle_pose(t)
	KnightAnim.weapon_carry(p, "sword", 0.0, 0.0)
	var lower := clampf((t - _cfg.impact_time()) / KnightMoves.HAMMER_LOWER, 0.0, 1.0)
	KnightAnim.hammer_raise_pose(p, t, lower)
	KnightAnim.hips_follow(p)
	KnightAnim.apply(r, p, k)
	KnightAnim.hold_weapon_upright(lk, r)


func _pose_sheet() -> void:
	var times := [0.0, 0.15, 0.35, 1.2]
	for row in 2:
		for i in times.size():
			var m := KNIGHT.instantiate() as Node3D
			add_child(m)
			m.position = Vector3(i * 1.7 + row * 100.0, 0, 0)
			m.rotation.y = deg_to_rad(35.0) if row == 0 else deg_to_rad(90.0)
			var lk := KnightLook.apply(m, {"weapon": "iron_sword", "offhand": "knight_shield", "armor": "royal_plate",
				"head": "knight_helm", "hands": "iron_gauntlets", "feet": "iron_greaves"})
			var r := KnightAnim.rig(m)
			for _j in 4:
				_pose_knight(r, lk, times[i])
	for row in 2:
		var vp := SubViewport.new()
		vp.size = Vector2i(1280, 480)
		vp.world_3d = get_viewport().world_3d
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.set_meta("row", row)
		add_child(vp)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 2.9
		cam.position = Vector3(1.5 * 1.7 + row * 100.0, 1.2, 8.0)
		vp.add_child(cam)
		cam.current = true


func _process(delta: float) -> void:
	_frames += 1
	if _mode == "pose":
		if _frames == 12:
			var img := Image.create(1280, 960, false, Image.FORMAT_RGBA8)
			for vp: SubViewport in find_children("*", "SubViewport", false, false):
				var part := vp.get_texture().get_image()
				part.convert(Image.FORMAT_RGBA8)
				img.blit_rect(part, Rect2i(Vector2i.ZERO, part.get_size()), Vector2i(0, 480 * int(vp.get_meta("row"))))
			img.save_png(_out)
			print("SHOT ", _out)
			get_tree().quit()
		return
	if _done:
		return
	_t += delta
	_pose_knight(_rig, _look, _t, 1.0 - exp(-14.0 * delta))
	# como no jogo (HammerAbilities.tick): olha para cima até a queda e volta suave
	if _game_cam:
		var want := _cfg.camera_tilt if _t < HammerAbilities.cancel_window() else 0.0
		_tilt = lerpf(_tilt, want, 1.0 - exp(-6.0 * delta))
		_game_cam.rotation = Vector3(-0.25 + _tilt, PI, 0.0)
	while not _plan.is_empty() and _t >= float(_plan[0][0]):
		var step: Array = _plan.pop_front()
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
		_shots.append([img, "%s (%.2f s)" % [step[1], _t]])
		print("quadro %-28s t=%.2f estado=%d nós=%d" % [step[1], _t,
			_skill.state if is_instance_valid(_skill) else -1, get_tree().get_node_count()])
		if _plan.is_empty():
			_save()


func _save() -> void:
	_done = true
	var cols := 4
	var rows := int(ceil(_shots.size() / float(cols)))
	var img := Image.create(CELL.x * cols, CELL.y * rows, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.06, 0.06, 0.08))
	for i in _shots.size():
		img.blit_rect(_shots[i][0], Rect2i(Vector2i.ZERO, CELL), Vector2i((i % cols) * CELL.x, (i / cols) * CELL.y))
	img.save_png(_out)
	for i in _shots.size():
		print("  %d: %s" % [i + 1, _shots[i][1]])
	print("SHOT ", _out, " — skill liberada: ", not is_instance_valid(_skill))
	get_tree().quit()
