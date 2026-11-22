extends Node3D
## Folha de contato da Lâmina Suprema (ultimate da montante): a linha do tempo inteira, com a pose do herói
## (KnightAnim.great_cast_pose) e o visual (GreatswordSupremeSlash) como no jogo. Precisa de janela (sem --headless):
##   godot --path . --fixed-fps 30 --resolution 960x720 res://tools/supreme_shot.tscn -- <saida.png> [jogo|lado|perto]
## jogo: da câmera do jogo (atrás do herói, recuada como na habilidade). lado: de 3/4, de longe. perto: a espada de perto.
## Bonecos em volta: vermelhos dentro da área do golpe (ponto do golpe ou caminho do corte), azuis fora.

const KNIGHT := preload("res://assets/models/knight.glb")
const SKILL := preload("res://scenes/vfx/greatsword_supreme/greatsword_supreme_slash.tscn")
const CELL := Vector2i(480, 360)

var _out := ""
var _mode := "jogo"
var _t := 0.0
var _done := false
var _shots: Array = []
var _plan: Array = []
var _knight: Node3D
var _rig: Dictionary
var _look: Dictionary
var _from := {}
var _skill: GreatswordSupremeSlash
var _cfg: GreatswordSupremeConfig
var _game_cam: Camera3D
var _tilt := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://supreme_shot.png"
	if args.size() > 1:
		_mode = args[1]
	_cfg = load("res://assets/vfx/greatsword_supreme/greatsword_supreme_config.tres")
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
	_knight = KNIGHT.instantiate() as Node3D
	add_child(_knight)
	_look = KnightLook.apply(_knight, {"weapon": "eclipse_greatsword", "armor": "royal_plate", "head": "knight_helm",
		"hands": "iron_gauntlets", "feet": "iron_greaves"})
	_rig = KnightAnim.rig(_knight)
	for _k in 4:
		_carry_pose(1.0)
	_from = KnightAnim.capture_pose(_rig)
	var center := Vector3(0, 0, _cfg.impact_distance)
	for off in [Vector3(2.0, 0, 1.0), Vector3(-2.6, 0, 1.6), Vector3(0.5, 0, 3.0), Vector3(-1.0, 0, -2.0), Vector3(6.5, 0, 1.0), Vector3(-6.0, 0, 3.0)]:
		var d := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.35
		cm.height = 1.4
		d.mesh = cm
		var dm := StandardMaterial3D.new()
		var inside := GreatswordSupremeRules.in_area(Vector3.ZERO, center, center + off, _cfg.impact_radius, _cfg.cut_half_width, 0.35)
		dm.albedo_color = Color(0.55, 0.25, 0.25) if inside else Color(0.3, 0.3, 0.55)
		d.material_override = dm
		add_child(d)
		d.position = center + off + Vector3.UP * 0.7
	var cam := Camera3D.new()
	cam.fov = 70.0
	add_child(cam)
	if _mode == "perto":
		cam.fov = 50.0
		cam.look_at_from_position(Vector3(6.5, 3.2, 3.0), Vector3(0, 3.2, 0.0))
	elif _mode == "lado":
		cam.fov = 55.0
		cam.look_at_from_position(Vector3(10.0, 4.5, 9.0), Vector3(0, 1.8, 2.0))
	else:
		var dist := 4.0 + _cfg.camera_back
		var pivot := Vector3(0.0, 1.55, 0.0)
		cam.position = pivot + Vector3(0, sin(0.25), -cos(0.25)) * dist + Vector3(-0.45, 0, 0)
		cam.rotation = Vector3(-0.25, PI, 0.0)
		_game_cam = cam
	cam.current = true
	# como o jogador local ao carregar (GreatswordSupremeAbilities.prewarm_instances): os pipelines antes do golpe
	var w: GreatswordSupremeSlash = SKILL.instantiate()
	w.warm_only = true
	add_child(w)
	w.global_position = Vector3(0, -200, 0)
	await get_tree().create_timer(1.0).timeout
	_skill = SKILL.instantiate()
	_skill.config = _cfg
	_skill.follow = _knight
	_skill.blade_base = _look.holder
	_skill.blade_tip = _look.tip
	_skill.yaw = 0.0
	_skill.seed_value = 1234
	add_child(_skill)
	var r := _cfg.raise_time
	var ce := _cfg.charge_end()
	var it := _cfg.impact_time()
	_plan = [[r * 0.6, "erguendo"], [r + 0.3, "aura começando"], [r + _cfg.charge_time * 0.5, "aura na metade"],
		[ce - 0.05, "aura formada"], [ce + _cfg.slash_time * 0.35, "corte: por trás"], [ce + _cfg.slash_time * 0.75, "corte: por cima"],
		[it - 0.03, "crava no chão"], [it + 0.08, "impacto"], [it + 0.3, "rachadura e pedras"], [it + 0.7, "poeira"],
		[it + 1.3, "ajoelhado / levantando"], [it + 2.2, "fogo diminuindo"], [it + _cfg.crack_hold + _cfg.fade_time * 0.5, "rachadura sumindo"]]


func _carry_pose(k: float) -> Dictionary:
	var p := KnightAnim.idle_pose(_t)
	KnightAnim.great_carry(p, 0.0, 0.0)
	return p


func _process(delta: float) -> void:
	if _done or _skill == null:
		return
	_t += delta
	var p := _carry_pose(1.0)
	p.erase("tool")
	p["two_hand"] = 1.0
	var durs := GreatswordSupremeRules.durations(_cfg.raise_time, _cfg.charge_time, _cfg.slash_time, _cfg.kneel_time, _cfg.rise_time)
	var ph := GreatswordSupremeRules.phase_at(_t, durs)
	var back := GreatswordSupremeRules.back_weight(ph.y, GreatswordSupremeAbilities.BACK_FROM) if int(ph.x) == 4 else 0.0
	KnightAnim.great_cast_pose(p, int(ph.x), ph.y, _from, back)
	KnightAnim.hips_follow(p)
	KnightAnim.apply(_rig, p, 1.0 - exp(-14.0 * delta))
	KnightAnim.hold_weapon_upright(_look, _rig)
	if _game_cam:
		var want := _cfg.camera_tilt if _t < _cfg.charge_end() else 0.0
		_tilt = lerpf(_tilt, want, 1.0 - exp(-6.0 * delta))
		_game_cam.rotation = Vector3(-0.25 + _tilt, PI, 0.0)
	while not _plan.is_empty() and _t >= float(_plan[0][0]):
		var step: Array = _plan.pop_front()
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
		_shots.append([img, "%s (%.2f s)" % [step[1], _t]])
		print("quadro %-24s t=%.2f estado=%d" % [step[1], _t, _skill.state if is_instance_valid(_skill) else -1])
		if _plan.is_empty():
			_save()


func _save() -> void:
	_done = true
	var cols := 4
	var rows := int(ceil(_shots.size() / float(cols)))
	var img := Image.create(CELL.x * cols, CELL.y * rows, false, Image.FORMAT_RGBA8)
	for i in _shots.size():
		img.blit_rect(_shots[i][0], Rect2i(Vector2i.ZERO, CELL), Vector2i((i % cols) * CELL.x, (i / cols) * CELL.y))
	img.save_png(_out)
	print("SHOT ", _out)
	get_tree().quit()
