extends Node3D
## Laboratório das asas: dois cavaleiros andando lado a lado com a mesma asa, à esquerda a batida antiga
## (asa inteira girando no pivô), à direita a nova (esqueleto ao longo da asa, BackWings). Eles andam de verdade
## pelo chão, então a velocidade, a passada e a inércia chegam às asas como no jogo.
## Precisa de janela e do --import feito antes:
##   godot --path . --resolution 1600x900 res://tools/wing_lab.tscn [-- asa] [costas|lado|frente]
## asa: seraph_wings (padrão), abyss_wings, crystal_wings, phoenix_wings, mech_wings, dragon_wings, fairy_wings.
## Teclas: 1 parado, 2 andar, 3 correr, Espaço liga/desliga o ciclo automático (parado > anda > corre > para),
## Q/E troca a asa, A/D vira (curva), setas giram a câmera, +/- zoom, V troca a vista, P pausa.
## Para gravar: acrescente --write-movie <pasta>/f.png --fixed-fps 30 (o ciclo automático roda uma volta e sai).

const KNIGHT := preload("res://assets/models/knight.glb")
const WINGS := ["seraph_wings", "abyss_wings", "dragon_wings", "phoenix_wings", "fairy_wings", "crystal_wings", "mech_wings"]
const GAP := 1.5                 # meia distância entre os dois cavaleiros
const WALK := 5.2
const RUN := 8.6
## Ciclo automático: [nome, velocidade, segundos]
const PROGRAM := [["PARADO", 0.0, 3.0], ["ANDANDO", WALK, 4.5], ["CORRENDO", RUN, 5.0], ["PARANDO", 0.0, 3.0]]

var _wing := 0
var _rig: Node3D
var _knights: Array = []         # [{model, r}]
var _cam: Camera3D
var _hud: Label
var _stripes: Array[Node3D] = []
var _speed := 0.0
var _target := 0.0
var _mode := "PARADO"
var _auto := true
var _step := 0
var _step_t := 0.0
var _loops := 0
var _phase := 0.0
var _amp := 0.0
var _run := 0.0
var _idle_t := 0.0
var _yaw_rate := 0.0
var _cam_yaw := deg_to_rad(155.0)   # atrás, um pouco de lado (como a câmera do jogo)
var _cam_pitch := deg_to_rad(18.0)
var _cam_dist := 7.0
var _views := [[155.0, 18.0, 7.0], [90.0, 6.0, 8.5], [-30.0, 10.0, 7.0], [180.0, 32.0, 8.0]]
var _view := 0
var _paused := false
var _movie := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		var i := WINGS.find(a)
		if i >= 0:
			_wing = i
	if "lado" in args:
		_view = 1
	elif "frente" in args:
		_view = 2
	_apply_view()
	_movie = OS.has_feature("movie") or "--write-movie" in OS.get_cmdline_args()
	WorldLighting.build(self)
	_rig = Node3D.new()
	_rig.name = "Treadmill"
	add_child(_rig)
	_ground()
	_cam = Camera3D.new()
	_cam.fov = 50.0
	add_child(_cam)
	_cam.current = true
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 20)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 6)
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(_hud)
	_spawn()


## (Re)cria os dois cavaleiros com a asa atual: o da esquerda com a batida antiga.
func _spawn() -> void:
	for k in _knights:
		k.model.queue_free()
	_knights.clear()
	for side in [[GAP, true, "ANTES"], [-GAP, false, "DEPOIS"]]:   # vistos de trás: antes à esquerda
		var m := KNIGHT.instantiate() as Node3D
		_rig.add_child(m)
		m.position = _slot(side[1])
		BackWings.legacy_default = side[1]
		KnightLook.apply(m, {"back": WINGS[_wing]})
		BackWings.legacy_default = false
		var tag := Label3D.new()
		tag.text = side[2]
		tag.font_size = 72
		tag.outline_size = 14
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(0, 2.75, 0)
		tag.modulate = Color(1.0, 0.75, 0.6) if side[1] else Color(0.65, 1.0, 0.7)
		m.add_child(tag)
		_knights.append({"model": m, "r": KnightAnim.rig(m)})


func _ground() -> void:
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	g.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.48, 0.30)
	g.material_override = mat
	add_child(g)
	_stripes.clear()
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.27, 0.36, 0.22)
	for i in 24:       # faixas no chão a cada 1,5 m: mostram a velocidade
		var s := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(8.0, 0.01, 0.35)
		s.mesh = bm
		s.material_override = smat
		add_child(s)
		_stripes.append(s)


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	match e.keycode:
		KEY_1:
			_set_manual("PARADO", 0.0)
		KEY_2:
			_set_manual("ANDANDO", WALK)
		KEY_3:
			_set_manual("CORRENDO", RUN)
		KEY_SPACE:
			_auto = not _auto
			_step_t = 0.0
		KEY_Q:
			_wing = (_wing + WINGS.size() - 1) % WINGS.size()
			_spawn()
		KEY_E:
			_wing = (_wing + 1) % WINGS.size()
			_spawn()
		KEY_V:
			_view = (_view + 1) % _views.size()
			_apply_view()
		KEY_P:
			_paused = not _paused
		KEY_EQUAL, KEY_KP_ADD:
			_cam_dist = maxf(2.5, _cam_dist - 0.8)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_cam_dist = minf(16.0, _cam_dist + 0.8)


func _set_manual(mode: String, v: float) -> void:
	_auto = false
	_mode = mode
	_target = v


func _apply_view() -> void:
	var v: Array = _views[_view]
	_cam_yaw = deg_to_rad(v[0])
	_cam_pitch = deg_to_rad(v[1])
	_cam_dist = v[2]
	for i in _knights.size():
		_knights[i].model.position = _slot(i == 0)


## Lugar de cada cavaleiro na esteira: lado a lado; na vista de lado, um à frente do outro (sem se cobrirem).
func _slot(old: bool) -> Vector3:
	if _view == 1:
		return Vector3(0.6 if old else -0.6, 0, 1.4 if old else -1.4)
	return Vector3(GAP if old else -GAP, 0, 0)


func _process(delta: float) -> void:
	if _paused:
		return
	if _auto:
		_step_t += delta
		var st: Array = PROGRAM[_step]
		if _step_t >= st[2]:
			_step_t = 0.0
			_step = (_step + 1) % PROGRAM.size()
			if _step == 0:
				_loops += 1
				if _movie:
					get_tree().quit()
		st = PROGRAM[_step]
		_mode = st[0]
		_target = st[1]
	# arranca e freia como o jogador (sem pulo instantâneo de velocidade)
	_speed = move_toward(_speed, _target, delta * (18.0 if _target > _speed else 14.0))
	# curva com A/D
	var turn := 0.0
	if Input.is_key_pressed(KEY_A):
		turn += 1.0
	if Input.is_key_pressed(KEY_D):
		turn -= 1.0
	_yaw_rate = lerpf(_yaw_rate, turn * 1.6, 1.0 - exp(-6.0 * delta))
	_rig.rotation.y += _yaw_rate * delta
	var fwd := Vector3(sin(_rig.rotation.y), 0, cos(_rig.rotation.y))
	_rig.position += fwd * _speed * delta

	# pose do corpo: a mesma mistura do Player (parado -> andar -> correr)
	var move_t := clampf(_speed / WALK, 0.0, 1.0)
	var run_t := clampf((_speed - WALK) / (RUN - WALK), 0.0, 1.0)
	_amp = lerpf(_amp, move_t, 1.0 - exp(-(10.0 if move_t > _amp else 6.0) * delta))
	_run = lerpf(_run, run_t, 1.0 - exp(-6.0 * delta))
	_idle_t += delta
	for k in _knights:
		var r: Dictionary = k.r
		if k == _knights[0]:
			_phase += delta * KnightAnim.cadence(r, _speed, _amp, _run)
		var p := KnightAnim.blend(KnightAnim.idle_pose(_idle_t), KnightAnim.locomotion_pose(r, _phase, _amp, _run), _amp)
		KnightAnim.apply(r, p, 1.0)

	# chão: faixas recicladas em volta do esteira
	var base := snappedf(_rig.position.dot(fwd), 1.5)
	for i in _stripes.size():
		var s := _stripes[i]
		s.position = _rig.position + fwd * (base - _rig.position.dot(fwd) + (i - 8) * 1.5) + Vector3.UP * 0.005
		s.rotation.y = _rig.rotation.y

	# câmera: segue a esteira, setas giram
	if Input.is_key_pressed(KEY_LEFT):
		_cam_yaw -= delta * 1.5
	if Input.is_key_pressed(KEY_RIGHT):
		_cam_yaw += delta * 1.5
	if Input.is_key_pressed(KEY_UP):
		_cam_pitch = clampf(_cam_pitch + delta, -0.2, 1.3)
	if Input.is_key_pressed(KEY_DOWN):
		_cam_pitch = clampf(_cam_pitch - delta, -0.2, 1.3)
	var a := _rig.rotation.y + _cam_yaw
	var focus := _rig.global_position + Vector3.UP * 1.3
	var off := Vector3(sin(a) * cos(_cam_pitch), sin(_cam_pitch), cos(a) * cos(_cam_pitch)) * _cam_dist
	_cam.global_position = focus + off
	_cam.look_at(focus, Vector3.UP)

	_hud.text = "%s  —  %s  (%.1f m/s)\n%s\n1 parado · 2 andar · 3 correr · Espaço ciclo auto %s · Q/E asa · A/D curva · setas câmera · V vista · P pausa" % [
		WINGS[_wing], _mode, _speed, "esquerda: batida antiga · direita: asa com esqueleto (nova)", "ligado" if _auto else "desligado"]
