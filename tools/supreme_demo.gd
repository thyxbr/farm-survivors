extends Node3D
## Demonstração jogável da Lâmina Suprema (ultimate da montante) fora do jogo: o cavaleiro com a montante, bonecos de
## treino em volta (vermelhos dentro da área do golpe, azuis fora) e as mesmas chamadas do jogo (great_carry,
## great_cast_pose, apply, hold_weapon_upright e a cena GreatswordSupremeSlash).
##   godot --path . res://tools/supreme_demo.tscn
## Teclas: 4 usa a Lâmina Suprema  Espaço esquiva (cancela durante a carga)  L câmera lenta (1x / 0,5x / 0,25x)
## C câmera do jogo / de lado  ←/→ gira a câmera  ↑/↓ aproxima  R repõe os bonecos

const KNIGHT := preload("res://assets/models/knight.glb")
const SKILL := preload("res://scenes/vfx/greatsword_supreme/greatsword_supreme_slash.tscn")
const SPEEDS := [1.0, 0.5, 0.25]
## Bonecos em volta do ponto do golpe (somado a ele): 4 dentro do raio, 1 no caminho do corte (perto do herói) e 3 fora.
const DUMMIES := [Vector3(1.6, 0, 0.5), Vector3(-1.4, 0, 1.6), Vector3(2.0, 0, -1.8), Vector3(-2.2, 0, -0.8),
	Vector3(0.6, 0, -4.8), Vector3(6.5, 0, 0.0), Vector3(-6.0, 0, 0.6), Vector3(0.0, 0, -10.5)]

var _cfg: GreatswordSupremeConfig
var _knight: Node3D
var _rig: Dictionary
var _look: Dictionary
var _skill: GreatswordSupremeSlash
var _t := -1.0          ## tempo da habilidade (-1 = parado em guarda)
var _from := {}
var _idle := 0.0
var _speed_i := 0
var _side_cam := false
var _yaw := 0.0
var _dist := 0.0
var _cam: Camera3D
var _cam_ready := false
var _label: Label
var _dummies: Array = []
var _status := ""


func _ready() -> void:
	_cfg = GreatswordSupremeAbilities.CONFIG
	WorldLighting.build(self)
	var g := StaticBody3D.new()
	var gm_i := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	gm_i.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.34, 0.42, 0.26)
	gm_i.material_override = gm
	g.add_child(gm_i)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(80, 0.2, 80)
	cs.shape = bs
	cs.position.y = -0.1
	g.add_child(cs)
	add_child(g)
	_knight = KNIGHT.instantiate() as Node3D
	add_child(_knight)
	_look = KnightLook.apply(_knight, {"weapon": "eclipse_greatsword", "armor": "royal_plate", "head": "knight_helm",
		"hands": "iron_gauntlets", "feet": "iron_greaves"})
	_rig = KnightAnim.rig(_knight)
	_reset_dummies()
	_cam = Camera3D.new()
	_cam.fov = 70.0
	add_child(_cam)
	_cam.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(20, 16)
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_label)
	# como o jogador local ao carregar: shaders e pipelines prontos antes do primeiro golpe
	var w: GreatswordSupremeSlash = SKILL.instantiate()
	w.warm_only = true
	add_child(w)
	w.global_position = Vector3(0, -200, 0)
	# `-- --auto`: usa a habilidade sozinha e fecha (conferência sem janela de teclado)
	if "--auto" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.8).timeout
		_cast()
		await get_tree().create_timer(_cfg.total_time() + 0.3).timeout
		print("DEMO_OK ", _status)
		get_tree().quit()


func _reset_dummies() -> void:
	for d in _dummies:
		d.node.queue_free()
	_dummies.clear()
	var center := Vector3(0, 0, _cfg.impact_distance)
	for off: Vector3 in DUMMIES:
		var p := center + off
		var d := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.35
		cm.height = 1.4
		d.mesh = cm
		var mat := StandardMaterial3D.new()
		var inside := GreatswordSupremeRules.in_area(Vector3.ZERO, center, p, _cfg.impact_radius, _cfg.cut_half_width, 0.35)
		mat.albedo_color = Color(0.6, 0.22, 0.2) if inside else Color(0.25, 0.3, 0.6)
		d.material_override = mat
		add_child(d)
		d.position = p + Vector3.UP * 0.7
		_dummies.append({"node": d, "mat": mat, "base": mat.albedo_color})


func _unhandled_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey and ev.pressed and not ev.echo):
		return
	match (ev as InputEventKey).keycode:
		KEY_4, KEY_KP_4:
			_cast()
		KEY_SPACE:
			_dodge()
		KEY_L:
			_speed_i = (_speed_i + 1) % SPEEDS.size()
			Engine.time_scale = SPEEDS[_speed_i]
		KEY_C:
			_side_cam = not _side_cam
			_yaw = 0.0
			_dist = 0.0
		KEY_R:
			_reset_dummies()


func _cast() -> void:
	if _t >= 0.0:
		return
	_from = KnightAnim.capture_pose(_rig)
	_skill = SKILL.instantiate()
	_skill.config = _cfg
	_skill.follow = _knight
	_skill.blade_base = _look.holder
	_skill.blade_tip = _look.tip
	_skill.yaw = 0.0
	_skill.seed_value = randi() % 65536
	add_child(_skill)
	_skill.impacted.connect(_on_impact)
	_t = 0.0
	_status = "Lâmina Suprema!"
	Sfx.play("arcane_cast", 0.06, -2.0)


## Esquiva: só cancela durante a carga (como GreatswordSupremeAbilities.can_dodge_cancel).
func _dodge() -> void:
	if _t < 0.0:
		_status = "esquiva"
		return
	if _t < _cfg.charge_end() and is_instance_valid(_skill) and _skill.can_cancel():
		_skill.cancel()
		_t = -1.0
		_status = "cancelada pela esquiva"
	else:
		_status = "no corte a esquiva não cancela mais"


## Os bonecos na área piscam, mostram o dano e são empurrados para longe do ponto do golpe.
func _on_impact(center: Vector3, _targets: Array) -> void:
	var n := 0
	for d in _dummies:
		var node: MeshInstance3D = d.node
		var p := node.global_position
		if not GreatswordSupremeRules.in_area(Vector3.ZERO, center, p, _cfg.impact_radius, _cfg.cut_half_width, 0.35):
			continue
		n += 1
		var mat: StandardMaterial3D = d.mat
		mat.albedo_color = Color(1.0, 0.95, 0.7)
		var push := Vector3(p.x - center.x, 0.0, p.z - center.z)
		push = push.normalized() if push.length() > 0.05 else Vector3.FORWARD
		var tw := create_tween().set_parallel()
		tw.tween_property(node, "position", node.position + push * _cfg.knockback * 0.18, 0.35) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(mat, "albedo_color", d.base, 0.6)
		var num := Label3D.new()
		num.text = "-%d" % int(120 * _cfg.damage_mult)
		num.font_size = 72
		num.outline_size = 12
		num.modulate = Color(1.0, 0.75, 0.3)
		num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		num.no_depth_test = true
		add_child(num)
		num.global_position = p + Vector3.UP * 1.3
		var nt := num.create_tween().set_parallel()
		nt.tween_property(num, "position:y", num.position.y + 1.2, 0.9)
		nt.tween_property(num, "modulate:a", 0.0, 0.6).set_delay(0.3)
		nt.chain().tween_callback(num.queue_free)
	_status = "impacto: %d bonecos atingidos" % n


func _process(delta: float) -> void:
	_idle += delta
	var p := KnightAnim.idle_pose(_idle)
	KnightAnim.great_carry(p, 0.0, 0.0)
	if _t >= 0.0:
		_t += delta
		p.erase("tool")
		p["two_hand"] = 1.0
		var ph := GreatswordSupremeRules.phase_at(_t, GreatswordSupremeAbilities.durations())
		var back := GreatswordSupremeRules.back_weight(ph.y, GreatswordSupremeAbilities.BACK_FROM) \
			if int(ph.x) == KnightMovesGreatCast.RISE else 0.0
		KnightAnim.great_cast_pose(p, int(ph.x), ph.y, _from, back)
		if _t >= _cfg.total_time():
			_t = -1.0
	KnightAnim.hips_follow(p)
	KnightAnim.apply(_rig, p, 1.0 - exp(-14.0 * delta))
	KnightAnim.hold_weapon_upright(_look, _rig)
	_update_camera(delta)
	_label.text = "Lâmina Suprema — 4 usar   Espaço esquiva (cancela na carga)   L câmera lenta (%sx)   C câmera (%s)   setas: câmera   R repõe bonecos\n%s%s" % [
		str(SPEEDS[_speed_i]), "de lado" if _side_cam else "do jogo", _phase_text(), ("   " + _status) if _status != "" else ""]


func _phase_text() -> String:
	if _t < 0.0:
		return "em guarda"
	var names := ["erguendo", "carga (aura se formando)", "corte", "ajoelhado", "levantando"]
	var ph := GreatswordSupremeRules.phase_at(_t, GreatswordSupremeAbilities.durations())
	return "%s  %.2f s" % [names[int(ph.x)], _t]


func _update_camera(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	if Input.is_key_pressed(KEY_LEFT):
		_yaw -= 60.0 * real
	if Input.is_key_pressed(KEY_RIGHT):
		_yaw += 60.0 * real
	if Input.is_key_pressed(KEY_UP):
		_dist -= 4.0 * real
	if Input.is_key_pressed(KEY_DOWN):
		_dist += 4.0 * real
	var target: Vector3
	var pos: Vector3
	if _side_cam:
		var d := 13.0 + _dist
		var a := deg_to_rad(50.0 + _yaw)
		target = Vector3(0, 1.6, 2.0)
		pos = target + Vector3(sin(a) * d, 3.0, cos(a) * d)
	else:
		# como a câmera do jogo: atrás do herói, recuada durante a habilidade e olhando para cima na carga
		var busy := _t >= 0.0
		var d := 4.0 + (_cfg.camera_back if busy else 0.0) + _dist
		var tilt := _cfg.camera_tilt if busy and _t < _cfg.charge_end() else 0.0
		var a := deg_to_rad(180.0 + _yaw)
		var pitch := 0.25
		target = Vector3(0, 1.55 + tilt * 8.0, 0)
		pos = Vector3(0, 1.55, 0) + Vector3(sin(a) * cos(pitch), sin(pitch), cos(a) * cos(pitch)) * d
	if not _cam_ready:
		_cam.global_position = pos
		_cam_ready = true
	else:
		_cam.global_position = _cam.global_position.lerp(pos, 1.0 - exp(-6.0 * real))
	_cam.look_at(target)
