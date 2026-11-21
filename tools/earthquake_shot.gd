extends Node3D
## Folha de contato do Terremoto Devastador (habilidade 2 da espada com escudo). Precisa de janela (sem --headless):
##   godot --path . --fixed-fps 30 --resolution 960x720 res://tools/earthquake_shot.tscn -- <saida.png> [jogo|alto|pose] [rampa]
## jogo: a linha do tempo inteira vista da câmera do jogo (atrás do herói, recuada como na habilidade).
## alto: a mesma de cima e de longe (a onda inteira, as rachaduras e as placas pelo raio todo).
## pose: o herói erguendo o escudo e batendo no chão, de 3/4 e de lado, em 5 instantes.
## rampa: o chão é uma rampa com um degrau (a onda e as rachaduras têm de seguir o relevo).

const KNIGHT := preload("res://assets/models/knight.glb")
const SKILL := preload("res://scenes/vfx/earthquake/earthquake_skill.tscn")
const CELL := Vector2i(480, 360)

var _out := ""
var _mode := "jogo"
var _slope := false
var _t := 0.0
var _frames := 0
var _shots: Array = []
var _plan: Array = []
var _knight: Node3D
var _rig: Dictionary
var _look: Dictionary
var _skill: EarthquakeSkill
var _cfg: EarthquakeConfig
var _done := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://earthquake_shot.png"
	if args.size() > 1:
		_mode = args[1]
	_slope = args.size() > 2 and args[2] == "rampa"
	_cfg = load("res://assets/vfx/earthquake/earthquake_config.tres")
	WorldLighting.build(self)
	_ground()
	if _mode == "pose":
		_pose_sheet()
		return
	_knight = _make_knight(Vector3.ZERO, 0.0)
	var center := Vector3(0, 0, _cfg.forward_offset)
	for off in [Vector3(2.5, 0, 1.0), Vector3(-3.6, 0, 2.6), Vector3(0.5, 0, 6.5), Vector3(-1.2, 0, -4.2), Vector3(11.0, 0, 1.0), Vector3(-10.5, 0, 3.0)]:
		var d := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.35
		cm.height = 1.4
		d.mesh = cm
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(0.55, 0.25, 0.25) if off.length() <= _cfg.radius else Color(0.3, 0.3, 0.55)
		d.material_override = dm
		add_child(d)
		d.position = center + off + Vector3.UP * (0.7 + _height_at(center + off))
	var cam := Camera3D.new()
	cam.fov = 70.0
	add_child(cam)
	if _mode == "alto":
		cam.fov = 60.0
		cam.look_at_from_position(Vector3(9.0, 15.0, -9.0), center)
	else:
		# câmera do jogo: atrás e um pouco à direita, inclinada -0,25 rad, 4 m + o recuo da habilidade
		var dist := 4.0 + _cfg.camera_back
		var pivot := Vector3(0.0, 1.55, 0.0)
		cam.position = pivot + Vector3(0, sin(0.25), -cos(0.25)) * dist + Vector3(-0.45, 0, 0)
		cam.rotation = Vector3(-0.25, PI, 0.0)
	cam.current = true
	_skill = SKILL.instantiate()
	_skill.config = _cfg
	_skill.seed_value = 1234
	_skill.position = center
	add_child(_skill)
	var it := _cfg.impact_time()
	var et := _cfg.expansion_time()
	_plan = [[0.2, "erguendo o escudo"], [it - 0.12, "escudo no alto: carga"], [it - 0.03, "descendo"], [it + 0.02, "impacto"],
		[it + 0.1, "onda inicial"], [it + et * 0.3, "onda: 30%"], [it + et * 0.6, "onda: 60%"], [it + et + 0.02, "raio máximo"],
		[it + et + 0.5, "dissipando"], [it + et + 1.2, "placas voltando"], [it + et + 2.2, "poeira assentando"], [it + et + _cfg.dissipation_time + 0.6, "fim"]]


func _ground() -> void:
	var g := StaticBody3D.new()
	add_child(g)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.45, 0.22)
	var parts := [[Vector3(0, -0.1, 0), Vector3(80, 0.2, 80), 0.0]]
	if _slope:
		parts = [[Vector3(0, -0.1, 0), Vector3(80, 0.2, 80), 0.0], [Vector3(-8, 0.0, 6), Vector3(10, 0.2, 18), -0.12],
			[Vector3(6.5, 0.25, 3), Vector3(6, 0.5, 8), 0.0]]
	for p in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = p[1]
		mi.mesh = bm
		mi.material_override = gm
		mi.position = p[0]
		mi.rotation.z = p[2]
		g.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = p[1]
		cs.shape = bs
		cs.position = p[0]
		cs.rotation.z = p[2]
		g.add_child(cs)


## Altura do chão de teste (só o degrau da rampa importa para os bonecos).
func _height_at(p: Vector3) -> float:
	if _slope and absf(p.x - 6.5) <= 3.0 and absf(p.z - 3.0) <= 4.0:
		return 0.5
	return 0.0


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
	KnightAnim.earthquake_pose(p, EarthquakeRules.pose_phase(t, _cfg.windup_time, _cfg.slam_time, _cfg.hold_time, _cfg.recover_time))
	KnightAnim.hips_follow(p)
	KnightAnim.apply(r, p, k)
	KnightAnim.hold_weapon_upright(lk, r)


func _pose_sheet() -> void:
	var it := _cfg.impact_time()
	var times := [0.0, _cfg.windup_time * 0.5, _cfg.windup_time, _cfg.windup_time + _cfg.slam_time * 0.6, it]
	for row in 2:
		for i in times.size():
			var m := KNIGHT.instantiate() as Node3D
			add_child(m)
			m.position = Vector3(i * 1.9 + row * 100.0, 0, 0)
			m.rotation.y = deg_to_rad(35.0) if row == 0 else deg_to_rad(90.0)
			var lk := KnightLook.apply(m, {"weapon": "iron_sword", "offhand": "knight_shield", "armor": "royal_plate",
				"head": "knight_helm", "hands": "iron_gauntlets", "feet": "iron_greaves"})
			var r := KnightAnim.rig(m)
			for _j in 6:
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
		cam.size = 3.5
		cam.position = Vector3(2.0 * 1.9 + row * 100.0, 1.2, 8.0)
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
	while not _plan.is_empty() and _t >= float(_plan[0][0]):
		var step: Array = _plan.pop_front()
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
		_shots.append([img, "%s (%.2f s)" % [step[1], _t]])
		var rocks: int = _skill.debris.count() if is_instance_valid(_skill) and is_instance_valid(_skill.debris) else -1
		print("quadro %-24s t=%.2f onda=%.2f pedras=%d nós=%d" % [step[1], _t,
			_skill.wave_r if is_instance_valid(_skill) else -1.0, rocks, get_tree().get_node_count()])
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
