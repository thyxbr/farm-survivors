extends Node3D
## Demonstração do combo básico da montante (KnightMovesGreat) ao lado do combo de espada e escudo, na velocidade do
## jogo, repetindo sem parar: guarda, o combo inteiro emendado, volta à guarda. Usa as mesmas chamadas do player.gd
## (great_carry, great_pose, great_recover_pose, shield_combo_pose, apply, hold_weapon_upright) e os cortes desenhados.
##   godot --path . res://tools/great_combo_demo.tscn
## Teclas: L câmera lenta (1x / 0,5x / 0,25x)  Espaço pausa  ←/→ gira a câmera  ↑/↓ aproxima  1/2 só um dos dois
## G golpes soltos (volta à guarda entre um e outro) ou emendados

const KNIGHT := preload("res://assets/models/knight.glb")
const Player := preload("res://scripts/player/player.gd")
const IDLE_BEFORE := 0.7
const IDLE_AFTER := 0.9
const SPEEDS := [1.0, 0.5, 0.25]

var _knights: Array = []
var _label: Label
var _cam: Camera3D
var _yaw := 30.0
var _dist := 5.5
var _speed_i := 0
var _paused := false
var _single := false
var _show := 0   # 0 = os dois, 1 = só a montante, 2 = só espada e escudo


func _ready() -> void:
	WorldLighting.build(self)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.36, 0.45, 0.3)
	ground.material_override = gmat
	add_child(ground)
	_knights.append(_make_knight(Vector3(-1.4, 0, 0), true))
	_knights.append(_make_knight(Vector3(1.4, 0, 0), false))
	_cam = Camera3D.new()
	_cam.fov = 50.0
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


func _make_knight(pos: Vector3, great: bool) -> Dictionary:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var m := KNIGHT.instantiate() as Node3D
	root.add_child(m)
	var gear := {"armor": "royal_plate", "head": "knight_helm", "hands": "iron_gauntlets", "feet": "iron_greaves"}
	if great:
		gear["weapon"] = "eclipse_greatsword"
	else:
		gear["weapon"] = "knight_blade"
		gear["offhand"] = "knight_shield"
	var lk := KnightLook.apply(m, gear)
	var r := KnightAnim.rig(m)
	var times: Array = Player.GREAT_SWING_TIMES if great else Player.SHIELD_SWING_TIMES
	return {"root": root, "model": m, "lk": lk, "r": r, "great": great, "times": times,
		"phase": "idle", "t": 0.0, "combo": 0, "from": {}, "rec_t": -1.0, "slashed": false, "idle_t": 0.0}


func _unhandled_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey and ev.pressed and not ev.echo):
		return
	match (ev as InputEventKey).keycode:
		KEY_L:
			_speed_i = (_speed_i + 1) % SPEEDS.size()
		KEY_SPACE:
			_paused = not _paused
		KEY_G:
			_single = not _single
		KEY_1:
			_show = 0 if _show == 1 else 1
		KEY_2:
			_show = 0 if _show == 2 else 2


var _shot_t := 0.0


func _process(delta: float) -> void:
	# `-- shot=<png>`: salva a tela depois de 1,25 s e fecha (para conferir o enquadramento)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shot="):
			_shot_t += delta
			if _shot_t > 1.25:
				get_viewport().get_texture().get_image().save_png(a.substr(5))
				get_tree().quit()
	if Input.is_key_pressed(KEY_LEFT):
		_yaw -= 70.0 * delta
	if Input.is_key_pressed(KEY_RIGHT):
		_yaw += 70.0 * delta
	if Input.is_key_pressed(KEY_UP):
		_dist = maxf(2.5, _dist - 3.0 * delta)
	if Input.is_key_pressed(KEY_DOWN):
		_dist = minf(12.0, _dist + 3.0 * delta)
	var center := Vector3(0.0 if _show == 0 else (-1.4 if _show == 1 else 1.4), 1.1, 0.0)
	var yr := deg_to_rad(_yaw)
	_cam.position = center + Vector3(sin(yr), 0.25, cos(yr)) * _dist
	_cam.look_at(center, Vector3.UP)
	(_knights[0].root as Node3D).visible = _show != 2
	(_knights[1].root as Node3D).visible = _show != 1
	var dt: float = 0.0 if _paused else delta * float(SPEEDS[_speed_i])
	var lines := []
	for k in _knights:
		_step(k, dt)
		var name: String = "Montante (duas mãos)" if k.great else "Espada e escudo"
		var tms := ", ".join((k.times as Array).map(func(x): return "%.2f" % x))
		var what: String = "guarda" if k.phase != "swing" else "golpe %d de %d" % [k.combo, (k.times as Array).size()]
		lines.append("%s  [%s s]  —  %s" % [name, tms, what])
	_label.text = "\n".join(lines) + "\n\nvelocidade %.2fx%s  ·  %s\nL câmera lenta   Espaço pausa   ←/→ ↑/↓ câmera   1/2 só um   G soltos/emendados" % [
		SPEEDS[_speed_i], "  (pausado)" if _paused else "", "golpes soltos" if _single else "combo emendado"]


func _step(k: Dictionary, dt: float) -> void:
	var r: Dictionary = k.r
	var great: bool = k.great
	var times: Array = k.times
	k.t = float(k.t) + dt
	var p := KnightAnim.idle_pose(float(k.idle_t))
	k.idle_t = float(k.idle_t) + dt
	KnightAnim.weapon_carry(p, "sword", 0.0, 0.0)
	if great:
		KnightAnim.great_carry(p, 0.0, 0.0)
	match k.phase:
		"idle":
			if k.rec_t >= 0.0:
				k.rec_t = float(k.rec_t) + dt
				if k.rec_t < KnightAnim.SHIELD_RECOVER:
					if great:
						KnightAnim.great_recover_pose(p, k.from, k.rec_t / KnightAnim.SHIELD_RECOVER)
					else:
						KnightAnim.shield_recover_pose(p, k.from, k.rec_t / KnightAnim.SHIELD_RECOVER)
				else:
					k.rec_t = -1.0
			var wait := IDLE_AFTER if k.combo >= times.size() or k.combo == 0 else 0.45
			if k.combo == 0:
				wait = IDLE_BEFORE
			if float(k.t) >= wait:
				_start(k, 1 if k.combo >= times.size() else int(k.combo) + 1)
		"swing":
			var dur: float = times[int(k.combo) - 1]
			var u := float(k.t) / dur
			if u >= 1.0:
				# fim do golpe, como player._end_swing_twist: emenda o próximo ou volta à guarda
				KnightAnim.unwind_twist(r)
				k.from = KnightAnim.capture_pose(r)
				if k.combo < times.size() and not _single:
					_start(k, int(k.combo) + 1)
					u = 0.0
				else:
					k.phase = "idle"
					k.t = 0.0
					k.rec_t = 0.0
			if k.phase == "swing":
				if great:
					KnightAnim.great_pose(p, k.combo, u, 0.0, k.from)
				else:
					KnightAnim.shield_combo_pose(p, k.combo, u, 0.0, k.from)
				_slash(k, u)
	if k.phase == "swing":
		KnightAnim.hips_follow(p)
	KnightAnim.apply(r, p, 1.0 - exp(-14.0 * maxf(dt, 0.0001)))
	KnightAnim.hold_weapon_upright(k.lk, r)


func _start(k: Dictionary, c: int) -> void:
	if k.phase != "swing":
		KnightAnim.unwind_twist(k.r)
		k.from = KnightAnim.capture_pose(k.r)   # o golpe nasce da pose em que o corpo está
	k.phase = "swing"
	k.combo = c
	k.t = 0.0
	k.rec_t = -1.0
	k.slashed = false


## Corte desenhado do golpe, no instante medido do retarget (como player._slash_fx). Em câmera lenta o rastro corre na
## velocidade normal (é um efeito com tempo próprio): só a pose fica lenta.
func _slash(k: Dictionary, u: float) -> void:
	var c: int = k.combo
	var at: float = (KnightMovesGreat.SLASH if k.great else KnightMovesShield.SLASH)[c - 1].at
	if k.slashed or u < at:
		return
	k.slashed = true
	var dur: float = (k.times as Array)[c - 1] / float(SPEEDS[_speed_i])
	var col := Color(0.75, 0.55, 1.0) if k.great else Color(0.95, 0.85, 0.55)
	if k.great:
		FXToon.great_slash(k.root, 0.0, c, dur, col)
	else:
		FXToon.shield_combo_slash(k.root, 0.0, c, dur, col)
