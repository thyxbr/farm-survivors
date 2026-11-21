extends Node3D
## Folha de contato do Círculo da Provocação Sombria (habilidade 3 da espada com escudo). Precisa de janela:
##   godot --path . --fixed-fps 30 --resolution 960x720 res://tools/taunt_shot.tscn -- <saida.png> [jogo|alto|pose|perto]
## jogo: a linha do tempo inteira da câmera do jogo (atrás do herói, recuada como na habilidade).
## alto: a mesma de cima, de 3/4 (o círculo inteiro no chão, as mãos agarrando os bonecos).
## perto: de perto de um boneco agarrado (dedos fechando, olhos vermelhos).
## pose: o herói no clipe "Sword And Shield Power Up" (recolhe, explode, segura, volta), de 3/4 e de lado.
## Bonecos de treino (camada e grupo dos inimigos): os de dentro do raio são agarrados e ganham os olhos; os de fora não.

const KNIGHT := preload("res://assets/models/knight.glb")
const SKILL := preload("res://scenes/vfx/dark_taunt/dark_taunt_skill.tscn")
const EYES := preload("res://scenes/vfx/dark_taunt/taunt_indicator.tscn")
const CELL := Vector2i(480, 360)
const DUMMY_SRC := """extends CharacterBody3D
var radius := 0.4
var dead := false
var parts := {}
var h := 1.5
func head_top() -> float:
	return h
"""

var _out := ""
var _mode := "jogo"
var _t := 0.0
var _frames := 0
var _shots: Array = []
var _plan: Array = []
var _knight: Node3D
var _rig: Dictionary
var _look: Dictionary
var _skill: DarkTauntSkill
var _cfg: DarkTauntConfig
var _done := false
var _dummies: Array = []
var _eyes: Array = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://taunt_shot.png"
	if args.size() > 1:
		_mode = args[1]
	_cfg = load("res://assets/vfx/dark_taunt/dark_taunt_config.tres")
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
	var script := GDScript.new()
	script.source_code = DUMMY_SRC
	script.reload()
	for off in [Vector3(2.4, 0, 2.0), Vector3(-3.0, 0, 1.4), Vector3(0.6, 0, 4.2), Vector3(-1.8, 0, -3.2), Vector3(4.2, 0, -1.5),
			Vector3(8.5, 0, 2.0), Vector3(-8.0, 0, 3.0)]:
		var d := CharacterBody3D.new()
		d.set_script(script)
		d.collision_layer = 4
		d.collision_mask = 0
		d.add_to_group("enemies")
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.35
		cm.height = 1.5
		mi.mesh = cm
		mi.position.y = 0.75
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(0.55, 0.3, 0.25) if off.length() <= _cfg.radius else Color(0.3, 0.3, 0.55)
		mi.material_override = dm
		d.add_child(mi)
		var shape := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.35
		cap.height = 1.5
		shape.shape = cap
		shape.position.y = 0.75
		d.add_child(shape)
		add_child(d)
		d.position = off
		d.look_at(Vector3(0, 0, 0) + Vector3(0.01, 0, 0), Vector3.UP)
		_dummies.append(d)
	var cam := Camera3D.new()
	cam.fov = 70.0
	add_child(cam)
	if _mode == "alto":
		cam.fov = 55.0
		cam.look_at_from_position(Vector3(9.0, 9.5, -11.0), Vector3(0, 0.3, 0.6))
	elif _mode == "perto":
		cam.fov = 45.0
		cam.look_at_from_position(Vector3(0.7, 1.35, 0.1), Vector3(2.4, 0.75, 2.0))
	else:
		var dist := 4.0 + _cfg.camera_back
		var pivot := Vector3(0.0, 1.55, 0.0)
		cam.position = pivot + Vector3(0, sin(0.32), -cos(0.32)) * dist + Vector3(-0.45, 0, 0)
		cam.rotation = Vector3(-0.32, PI, 0.0)
	cam.current = true
	_skill = SKILL.instantiate()
	_skill.config = _cfg
	_skill.caster = _knight
	_skill.seed_value = 4321
	_skill.deal_effects = true
	add_child(_skill)
	_skill.captured.connect(_on_captured)
	var ga := _cfg.grab_at()
	var ra := _cfg.release_at()
	_plan = [[0.3, "recolhe os braços"], [0.6, "solta: onda + círculo"], [0.85, "círculo se desenhando"],
		[1.25, "círculo pronto, mãos rompendo"], [1.55, "mãos subindo"], [ga - 0.15, "esticando até os alvos"],
		[ga + 0.12, "dedos fecham"], [ga + 0.6, "segurando + olhos"], [ra - 0.3, "segurando (energia)"],
		[ra + 0.3, "soltam e afundam"], [ra + 0.9, "círculo apagando"], [ra + 1.5, "runas em partículas"],
		[ra + 2.2, "anéis se contraindo"], [ra + 3.4, "fim (olhos seguem)"]]


func _on_captured(e: Node3D) -> void:
	var ind: TauntIndicator = EYES.instantiate()
	e.add_child(ind)
	ind.attach(e)
	ind.show_eyes()
	_eyes.append(ind)


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
	KnightAnim.taunt_pose(p, DarkTauntRules.clip_time(t, DarkTauntAbilities.cancel_window(), KnightMoves.TAUNT_RETURN))
	KnightAnim.hips_follow(p)
	KnightAnim.apply(r, p, k)
	KnightAnim.hold_weapon_upright(lk, r)


func _pose_sheet() -> void:
	var cw := DarkTauntAbilities.cancel_window()
	# tempo da habilidade para cada instante do clipe: recolhido (0,35), explosão (0,55), segurando, voltando
	var times := [0.0, 0.35, 0.6, cw + KnightMoves.TAUNT_RETURN * 0.45]
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
	if _t > _cfg.release_at() + 2.0:
		for e in _eyes:
			if is_instance_valid(e) and e.active:
				e.hide_eyes()
	while not _plan.is_empty() and _t >= float(_plan[0][0]):
		var step: Array = _plan.pop_front()
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
		_shots.append([img, "%s (%.2f s)" % [step[1], _t]])
		print("quadro %-30s t=%.2f estado=%d agarrados=%d" % [step[1], _t,
			_skill.state if is_instance_valid(_skill) else -1, _eyes.size()])
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
