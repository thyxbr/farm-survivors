class_name ArrivalCutscene
extends Node
## Abertura "isekai" do personagem novo (primeira vez no mundo), antes da narração e do Ancião Bram:
##   1. Tela preta: a última lembrança do outro mundo ("uma luz muito forte... e uma voz dizendo: Ops.").
##   2. Janela de SISTEMA (o clichê do anime isekai): transferência de alma, nome, classe, nível 1 e um
##      aviso de que a altitude de chegada ficou "um pouco" imprecisa.
##   3. Plano do céu sobre Valdoria: uma estrela cai riscando o céu na direção da estrada do sul...
##   4. ...e acerta em cheio a carroça de feno do Beto. PLOFT. Só as pernas do herói ficam para fora.
##   5. O herói se solta num pulo, cai em pé ao lado da carroça, tonto (estrelinhas girando) e olha a vila.
##   6. A câmera volta para trás do jogador e o mundo passa para a narração (StoryDialogue.intro()).
## Espaço, Enter ou Esc pulam para o fim a qualquer momento. A carroça e o feno espalhado ficam na estrada
## (só neste cliente, até sair do mapa), como prova do pouso.

signal finished

const SKY_BLUE := Color(0.45, 0.85, 1.0)
const STAR_GOLD := Color(1.0, 0.9, 0.55)
const HAY := Color(0.93, 0.78, 0.36)
const HAY_DARK := Color(0.8, 0.6, 0.24)
const WOOD := Color(0.48, 0.3, 0.15)
const WOOD_DARK := Color(0.3, 0.18, 0.09)

## Pés do herói quando ele está de cabeça para baixo enfiado no feno (acima do chão).
const STUCK_FEET := 2.85
## Para onde ele pula ao sair da carroça (lado direito da estrada).
const HOP_SIDE := 2.1

var world: Node
var player: Node3D

var _cam: Camera3D
var _ui: CanvasLayer
var _black: ColorRect
var _flash: ColorRect
var _subtitle: Label
var _skip_hint: Label
var _window: PanelContainer
var _lines: VBoxContainer
var _land := Vector3.ZERO
var _fwd := Vector3.FORWARD
var _right := Vector3.RIGHT
var _cart: Node3D
var _star: Node3D
var _star_p := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]   # bézier da queda
var _star_t := -1.0          # 0..1 durante a queda, -1 fora dela
var _trail_acc := 0.0
var _sky_look := Vector3.ZERO
var _shake := 0.0
var _wiggle := false
var _dizzy: Node3D
var _fx: Array = []          # partículas soltas: {"n": Node3D, "v": Vector3, "life", "age", "grow", "grav"}
var _tweens: Array[Tween] = []
var _done := false
var _hud_was_visible := true
var _clock := 0.0
var _interp_mode := Node.PHYSICS_INTERPOLATION_MODE_INHERIT


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_land = player.global_position
	# a vila fica ao norte da estrada: o herói cai olhando para ela
	var to_village := Vector3(-_land.x, 0, -_land.z)
	_fwd = to_village.normalized() if to_village.length() > 1.0 else Vector3(0, 0, -1)
	_right = _fwd.cross(Vector3.UP).normalized()
	_build_ui()
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.far = 900.0
	world.add_child(_cam)
	_cam.current = true
	_set_player_hidden(true)
	# a cena move o herói fora do passo de física: sem interpolação, o desenho acompanha na hora
	_interp_mode = player.physics_interpolation_mode
	player.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if world.get("hud") != null:
		_hud_was_visible = world.hud.visible
		world.hud.visible = false
	_run()


# ================================================================ roteiro
func _run() -> void:
	# --- 1. a última lembrança (tela preta)
	_place_sky_camera()
	await _say_black("A última coisa de que você se lembra é uma luz muito forte...", 2.1)
	if _done: return
	await _say_black("...e uma voz, bem baixinho, dizendo: \"Ops.\"", 2.0)
	if _done: return
	# --- 2. janela de sistema
	await _system_window()
	if _done: return
	# --- 3. o céu de Valdoria e a estrela cadente
	_cart = _build_cart()
	world.add_child(_cart)
	_cart.global_position = _land
	_cart.rotation.y = atan2(_fwd.x, _fwd.z)
	_fade(_black, 0.0, 1.0)
	_subtitle_show("Valdoria", 2.4, true)
	await _wait(1.1)
	if _done: return
	_start_star()
	Sfx.play("staff_wind", 0.0, -4.0)
	await _wait(3.1)
	if _done: return
	# --- 4. PLOFT
	_impact()
	await _wait(2.6)
	if _done: return
	# --- 5. o herói se solta e cai tonto ao lado da carroça
	await _hop_out()
	if _done: return
	await _wait(2.4)
	if _done: return
	_subtitle_show("(Isso é... feno? Isso é... OUTRO MUNDO?!)", 2.6)
	await _wait(2.8)
	if _done: return
	# --- 6. volta para a câmera do jogo
	await _blend_to_player(1.3)
	if _done: return
	_finish()


func _input(event: InputEvent) -> void:
	if _done:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
		get_viewport().set_input_as_handled()
		_skip()


## Pula para o estado final: herói em pé ao lado da carroça, câmera do jogo.
func _skip() -> void:
	for tw in _tweens:
		if tw.is_valid():
			tw.kill()
	if _cart == null:
		_cart = _build_cart()
		world.add_child(_cart)
		_cart.global_position = _land
		_cart.rotation.y = atan2(_fwd.x, _fwd.z)
		_scatter_hay()
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	_star_t = -1.0
	if _star:
		_star.queue_free()
		_star = null
	if _dizzy:
		_dizzy.queue_free()
		_dizzy = null
	for f in _fx:
		if is_instance_valid(f.n):
			f.n.queue_free()
	_fx.clear()
	# herói em pé, fora da carroça, olhando a vila
	var model: Node3D = player.get("model")
	if model:
		model.rotation.x = 0.0
		model.rotation.z = 0.0
		model.rotation.y = atan2(_fwd.x, _fwd.z)
	if player.global_position.distance_to(_land + _right * HOP_SIDE) > 0.3:
		player.global_position = _land + _right * HOP_SIDE + Vector3.UP * 0.1
	_set_player_hidden(false)
	player.set_physics_process(true)
	player.physics_interpolation_mode = _interp_mode
	player.reset_physics_interpolation()
	if player.has_method("_snap_visuals"):
		player.call("_snap_visuals")
	_aim_player_camera()
	var cam: Camera3D = player.get("camera")
	if cam:
		cam.current = true
	if is_instance_valid(_cam):
		_cam.queue_free()
	if world.get("hud") != null:
		world.hud.visible = _hud_was_visible
	player.set("input_locked", false)
	if is_instance_valid(_ui):
		_ui.queue_free()
	finished.emit()
	# some depois: as esperas que ainda estão correndo voltam, veem _done e param
	get_tree().create_timer(5.0, true).timeout.connect(queue_free)


# ================================================================ quadro a quadro
func _process(delta: float) -> void:
	if _done:
		return
	_clock += delta
	# estrela caindo: posição na bézier (acelera no fim), rastro e câmera acompanhando
	if _star_t >= 0.0 and _star:
		_star_t = minf(1.0, _star_t + delta / 3.0)
		var u := pow(_star_t, 1.7)
		var p := _bezier(u)
		_star.global_position = p
		_star.rotate_y(delta * 6.0)
		_trail_acc += delta
		while _trail_acc > 0.018:
			_trail_acc -= 0.018
			_trail_puff(p)
		_look(_cam.global_position, _sky_look.lerp(p, 0.55 + 0.4 * u))
	# partículas: rastro, poeira e fiapos de feno
	for i in range(_fx.size() - 1, -1, -1):
		var f: Dictionary = _fx[i]
		var n: Node3D = f.n
		f.age += delta
		if not is_instance_valid(n) or f.age >= f.life:
			if is_instance_valid(n):
				n.queue_free()
			_fx.remove_at(i)
			continue
		var k: float = f.age / f.life
		f.v += Vector3.DOWN * float(f.grav) * delta
		n.global_position += f.v * delta
		if f.grav > 0.0 and n.global_position.y < _land.y + 0.03:
			n.global_position.y = _land.y + 0.03
			f.v = Vector3.ZERO
		n.scale = Vector3.ONE * lerpf(1.0, float(f.grow), k)
		var mi := n as MeshInstance3D
		if mi and mi.material_override is StandardMaterial3D:
			var m: StandardMaterial3D = mi.material_override
			m.albedo_color.a = (1.0 - k) * float(f.get("a0", 1.0))
	# pernas para fora do feno, chacoalhando
	var model: Node3D = player.get("model")
	if _wiggle and model:
		model.rotation.z = sin(_clock * 15.0) * 0.14
	# estrelinhas de tontura em volta da cabeça
	if _dizzy:
		_dizzy.global_position = player.global_position + Vector3.UP * 2.05
		_dizzy.rotation.y += delta * 5.0
	# tremor da câmera
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 1.6)
		_cam.h_offset = randf_range(-1, 1) * _shake * 0.35
		_cam.v_offset = randf_range(-1, 1) * _shake * 0.35
	else:
		_cam.h_offset = 0.0
		_cam.v_offset = 0.0


# ================================================================ cenas
func _place_sky_camera() -> void:
	# atrás da carroça (ao sul), baixo, olhando o céu por cima da vila
	var pos := _land - _fwd * 11.0 - _right * 3.5 + Vector3.UP * 2.0
	_sky_look = _land + _fwd * 40.0 + _right * 8.0 + Vector3.UP * 22.0
	_look(pos, _sky_look)


func _start_star() -> void:
	_star = Node3D.new()
	world.add_child(_star)
	var core := _sphere(0.32, Color(1, 0.98, 0.9), false)
	_star.add_child(core)
	var halo := _sphere(0.95, Color(SKY_BLUE, 0.35), true)
	_star.add_child(halo)
	var halo2 := _sphere(2.2, Color(0.35, 0.6, 1.0, 0.12), true)
	_star.add_child(halo2)
	var light := OmniLight3D.new()
	light.light_color = Color(0.75, 0.9, 1.0)
	light.light_energy = 5.0
	light.omni_range = 14.0
	_star.add_child(light)
	_star_p = [
		_land + _fwd * 75.0 + _right * 34.0 + Vector3.UP * 58.0,
		_land + _fwd * 22.0 + _right * 18.0 + Vector3.UP * 34.0,
		_land + Vector3.UP * 1.4,
	]
	_star.global_position = _star_p[0]
	_star_t = 0.0


func _bezier(u: float) -> Vector3:
	var a: Vector3 = _star_p[0].lerp(_star_p[1], u)
	var b: Vector3 = _star_p[1].lerp(_star_p[2], u)
	return a.lerp(b, u)


func _trail_puff(p: Vector3) -> void:
	var c := SKY_BLUE if randf() < 0.55 else STAR_GOLD
	var s := _sphere(randf_range(0.35, 0.6), Color(c, 0.7), true)
	world.add_child(s)
	s.global_position = p + Vector3(randf_range(-0.2, 0.2), randf_range(-0.2, 0.2), randf_range(-0.2, 0.2))
	_fx.append({"n": s, "v": Vector3.ZERO, "life": 1.3, "age": 0.0, "grow": 0.1, "grav": 0.0, "a0": 0.7})


func _impact() -> void:
	_star_t = -1.0
	if _star:
		_star.queue_free()
		_star = null
	Sfx.play("explode", 0.05, -2.0)
	Sfx.play("slam", 0.05, -4.0)
	_flash.color.a = 0.95
	_track(create_tween()).tween_property(_flash, "color:a", 0.0, 0.55)
	_shake = 1.0
	# poeira
	for i in 12:
		var a := TAU * i / 12.0
		var d := _sphere(randf_range(0.18, 0.3), Color(0.86, 0.78, 0.6, 0.5), false)
		world.add_child(d)
		d.global_position = _land + Vector3.UP * 0.3 + Vector3(cos(a), 0, sin(a)) * 1.0
		_fx.append({"n": d, "v": Vector3(cos(a) * randf_range(1.6, 2.6), randf_range(0.3, 0.9), sin(a) * randf_range(1.6, 2.6)),
			"life": 1.0, "age": 0.0, "grow": 1.6, "grav": 0.0, "a0": 0.45})
	# fiapos de feno voando
	for i in 36:
		var straw := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.04, 0.04, randf_range(0.18, 0.35))
		straw.mesh = bm
		straw.material_override = _mat(HAY if randf() < 0.6 else HAY_DARK)
		world.add_child(straw)
		straw.global_position = _land + Vector3.UP * 1.3
		straw.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		var dir := Vector3(randf_range(-1, 1), randf_range(0.8, 2.0), randf_range(-1, 1)).normalized()
		_fx.append({"n": straw, "v": dir * randf_range(4.0, 8.0), "life": 2.6, "age": 0.0, "grow": 1.0, "grav": 9.0})
	_scatter_hay()
	# o herói enfiado de cabeça no feno, pernas para cima
	_set_player_hidden(false, true)
	player.set_physics_process(false)
	player.global_position = _land + Vector3.UP * STUCK_FEET
	var model: Node3D = player.get("model")
	if model:
		model.rotation.y = atan2(_fwd.x, _fwd.z)
		model.rotation.x = PI
	_wiggle = true
	_onomatopoeia("PLOFT!")
	# corta para o lado da carroça
	_look(_land + _right * 4.6 - _fwd * 2.2 + Vector3.UP * 1.7, _land + Vector3.UP * 1.45)


func _hop_out() -> void:
	_wiggle = false
	Sfx.play("dodge", 0.05)
	var model: Node3D = player.get("model")
	var a := player.global_position
	var b := _land + _right * HOP_SIDE + Vector3.UP * 0.05
	var hop := func(u: float) -> void:
		player.global_position = a.lerp(b, u) + Vector3.UP * sin(u * PI) * 1.5
		if model:
			model.rotation.x = PI + PI * u   # cambalhota: de cabeça para baixo até em pé
			model.rotation.z = 0.0
	var tw := _track(create_tween())
	tw.tween_method(hop, 0.0, 1.0, 0.75)
	await tw.finished
	if _done:
		return
	if model:
		model.rotation.x = 0.0
	player.global_position = b
	player.set_physics_process(true)
	Sfx.play("hit", 0.05, -6.0)
	_shake = 0.35
	_dizzy = _make_dizzy()
	world.add_child(_dizzy)
	# câmera de frente para o herói tonto, a vila atrás da câmera
	var from := _land + _right * 4.6 - _fwd * 2.2 + Vector3.UP * 1.7
	var to := b + _fwd * 3.0 - _right * 1.4 + Vector3.UP * 1.5
	var at0 := _land + Vector3.UP * 1.45
	var at1 := b + Vector3.UP * 1.25
	var move := func(u: float) -> void: _look(from.lerp(to, u), at0.lerp(at1, u))
	_track(create_tween()).tween_method(move, 0.0, 1.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _blend_to_player(dur: float) -> void:
	if _dizzy:
		_dizzy.queue_free()
		_dizzy = null
	_aim_player_camera()
	var cam: Camera3D = player.get("camera")
	if cam == null:
		return
	await get_tree().process_frame   # a mola da câmera se ajusta à nova direção
	var from := _cam.global_transform
	var fov0 := _cam.fov
	var blend := func(u: float) -> void:
		_cam.global_transform = from.interpolate_with(cam.global_transform, u)
		_cam.fov = lerpf(fov0, cam.fov, u)
	var tw := _track(create_tween())
	tw.tween_method(blend, 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished


## Câmera do jogo atrás do herói, olhando a vila (o mesmo que o player faz ao nascer com rumo salvo).
func _aim_player_camera() -> void:
	var yaw_node: Node3D = player.get("cam_yaw")
	var pitch_node: Node3D = player.get("cam_pitch")
	if yaw_node == null:
		return
	yaw_node.rotation.y = atan2(_fwd.x, _fwd.z) + PI
	yaw_node.global_position = player.global_position + Vector3.UP * 1.55
	if pitch_node:
		pitch_node.rotation.x = -0.25


# ================================================================ cenário
## Carroça de feno do Beto: caixa de madeira, quatro rodas, varais na frente e um monte de feno em cima.
## Comprimento ao longo de +Z (o roteiro gira para a frente apontar para a vila).
func _build_cart() -> Node3D:
	var root := Node3D.new()
	root.name = "CarrocaDoBeto"
	var wood := _mat(WOOD)
	var dark := _mat(WOOD_DARK)
	_box(root, Vector3(1.5, 0.12, 2.4), Vector3(0, 0.6, 0), wood)
	for sx in [-1.0, 1.0]:
		_box(root, Vector3(0.08, 0.42, 2.4), Vector3(0.71 * sx, 0.87, 0), wood)
		_box(root, Vector3(0.1, 0.1, 2.5), Vector3(0.71 * sx, 1.1, 0), dark)
		for sz in [-1.0, 1.0]:
			var wheel := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.44
			cm.bottom_radius = 0.44
			cm.height = 0.09
			cm.radial_segments = 16
			wheel.mesh = cm
			wheel.material_override = dark
			wheel.rotation.z = PI / 2
			wheel.position = Vector3(0.84 * sx, 0.44, 0.78 * sz)
			root.add_child(wheel)
			_box(root, Vector3(0.12, 0.16, 0.16), Vector3(0.9 * sx, 0.44, 0.78 * sz), wood)
		# varal (os dois paus da frente, para o cavalo que fugiu de susto)
		var shaft := _box(root, Vector3(0.07, 0.07, 1.7), Vector3(0.42 * sx, 0.5, 2.0), dark)
		shaft.rotation.x = 0.12
	for sz in [-1.0, 1.0]:
		_box(root, Vector3(1.5, 0.42, 0.08), Vector3(0, 0.87, 1.18 * sz), wood)
	_box(root, Vector3(1.6, 0.08, 0.08), Vector3(0, 0.44, 0.78), dark)
	_box(root, Vector3(1.6, 0.08, 0.08), Vector3(0, 0.44, -0.78), dark)
	# monte de feno (uma cratera no meio, onde o herói entrou)
	var mounds := [[Vector3(0, 1.08, -0.55), Vector3(0.78, 0.5, 0.75)], [Vector3(0, 1.08, 0.6), Vector3(0.78, 0.48, 0.7)],
		[Vector3(-0.42, 1.12, 0.0), Vector3(0.42, 0.52, 0.6)], [Vector3(0.42, 1.1, 0.05), Vector3(0.42, 0.5, 0.55)],
		[Vector3(0, 1.35, -0.2), Vector3(0.5, 0.42, 0.5)]]
	for m in mounds:
		var hay := _sphere(1.0, HAY, false)
		hay.material_override = _mat(HAY)
		hay.position = m[0]
		hay.scale = m[1]
		root.add_child(hay)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 26:
		var st := _box(root, Vector3(0.035, 0.035, rng.randf_range(0.25, 0.45)),
			Vector3(rng.randf_range(-0.65, 0.65), rng.randf_range(1.2, 1.55), rng.randf_range(-1.0, 1.0)),
			_mat(HAY_DARK if i % 3 == 0 else HAY))
		st.rotation = Vector3(rng.randf_range(-0.9, 0.9), rng.randf() * TAU, rng.randf_range(-0.9, 0.9))
	# colisão simples: dá para encostar na carroça, não para atravessar
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.7, 1.5, 2.5)
	shape.shape = bs
	shape.position = Vector3(0, 0.75, 0)
	body.add_child(shape)
	root.add_child(body)
	return root


## Feno espalhado pelo chão em volta da carroça (fica depois da cena).
func _scatter_hay() -> void:
	if _cart == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 9:
		var a := rng.randf() * TAU
		var r := rng.randf_range(1.5, 3.2)
		var tuft := _sphere(1.0, HAY, false)
		tuft.material_override = _mat(HAY_DARK if i % 2 else HAY)
		tuft.scale = Vector3(rng.randf_range(0.18, 0.32), 0.12, rng.randf_range(0.18, 0.32))
		_cart.add_child(tuft)
		tuft.global_position = _land + Vector3(cos(a) * r, 0.04, sin(a) * r)


func _make_dizzy() -> Node3D:
	var root := Node3D.new()
	# brilhos de quatro pontas (duas varetas cruzadas) girando em volta da cabeça
	for i in 4:
		var a := TAU * i / 4.0
		var spark := Node3D.new()
		spark.position = Vector3(cos(a) * 0.4, (0.05 if i % 2 else -0.03), sin(a) * 0.4)
		for rz in [0.0, PI / 2]:
			var arm := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.2, 0.035, 0.02)
			arm.mesh = bm
			arm.material_override = _glow_mat(STAR_GOLD if i % 2 == 0 else Color(1, 1, 0.85))
			arm.rotation.z = rz + PI / 4
			spark.add_child(arm)
		root.add_child(spark)
	return root


# ================================================================ interface (tela preta, sistema, legendas)
func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 30
	_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ui)
	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 1)
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_black)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 0.95, 0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_flash)
	# faixas de cinema
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 1)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0
		bar.anchor_bottom = 0.0 if top else 1.0
		bar.offset_top = 0.0 if top else -64.0
		bar.offset_bottom = 64.0 if top else 0.0
		_ui.add_child(bar)
	_subtitle = UITheme.outlined("", 30, Color(1, 0.97, 0.9), 8)
	_subtitle.add_theme_font_override("font", UITheme.serif())
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.anchor_left = 0.1
	_subtitle.anchor_right = 0.9
	_subtitle.anchor_top = 1.0
	_subtitle.anchor_bottom = 1.0
	_subtitle.offset_top = -170
	_subtitle.offset_bottom = -80
	_subtitle.modulate.a = 0.0
	_ui.add_child(_subtitle)
	_skip_hint = UITheme.outlined("[Espaço] pular", 15, Color(1, 1, 1, 0.55), 4)
	_skip_hint.anchor_left = 1.0
	_skip_hint.anchor_right = 1.0
	_skip_hint.anchor_top = 1.0
	_skip_hint.anchor_bottom = 1.0
	_skip_hint.offset_left = -170
	_skip_hint.offset_right = -24
	_skip_hint.offset_top = -50
	_skip_hint.offset_bottom = -22
	_skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ui.add_child(_skip_hint)


## Frase branca no meio da tela preta: aparece, segura e some.
func _say_black(text: String, hold: float) -> void:
	var l := UITheme.outlined(text, 28, Color(0.95, 0.95, 1.0), 0)
	l.add_theme_font_override("font", UITheme.serif())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.modulate.a = 0.0
	_ui.add_child(l)
	var tw := _track(create_tween())
	tw.tween_property(l, "modulate:a", 1.0, 0.6)
	tw.tween_interval(hold)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)
	await tw.finished


## A janela azul de sistema do anime isekai, digitando linha por linha.
func _system_window() -> void:
	_window = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.12, 0.24, 0.9)
	sb.border_color = SKY_BLUE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.shadow_color = Color(SKY_BLUE, 0.35)
	sb.shadow_size = 18
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 22
	sb.content_margin_bottom = 26
	_window.add_theme_stylebox_override("panel", sb)
	_window.anchor_left = 0.5
	_window.anchor_right = 0.5
	_window.anchor_top = 0.5
	_window.anchor_bottom = 0.5
	_window.offset_left = -330
	_window.offset_right = 330
	_window.offset_top = -190
	_window.offset_bottom = 190
	_window.modulate.a = 0.0
	_window.pivot_offset = Vector2(330, 190)
	_window.scale = Vector2(1.0, 0.05)
	_ui.add_child(_window)
	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 7)
	_window.add_child(_lines)
	var head := UITheme.outlined("◆  S I S T E M A  ◆", 22, SKY_BLUE, 0)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lines.add_child(head)
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", _hline(Color(SKY_BLUE, 0.5)))
	_lines.add_child(sep)
	Sfx.play("arcane_cast", 0.0, -6.0)
	var tw := _track(create_tween()).set_parallel(true)
	tw.tween_property(_window, "modulate:a", 1.0, 0.25)
	tw.tween_property(_window, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished
	var cls: String = Game.class_display_name()
	var rows := [
		["Alma detectada. Origem: outro mundo.", Color(0.85, 0.95, 1.0)],
		["Transferência de alma ............ 100%", Color(0.85, 0.95, 1.0)],
		["Nome: %s   ·   Classe: %s   ·   Nível 1" % [StoryDialogue.hero(), cls if cls != "" else "???"], Color(1, 1, 1)],
		["Título obtido: [ Forasteiro de Outro Mundo ]", STAR_GOLD],
		["Habilidade única: ??? (ainda não descoberta)", Color(0.85, 0.95, 1.0)],
		["⚠ Destino: Valdoria — coordenadas imprecisas.", Color(1.0, 0.78, 0.4)],
		["⚠ Altitude de chegada: 300 m.  Boa sorte!", Color(1.0, 0.55, 0.45)],
	]
	for r in rows:
		if _done:
			return
		await _type_line(str(r[0]), r[1])
		await _wait(0.16)
	await _wait(1.3)
	if _done:
		return
	var out := _track(create_tween()).set_parallel(true)
	out.tween_property(_window, "scale", Vector2(1.0, 0.05), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	out.tween_property(_window, "modulate:a", 0.0, 0.22)
	await out.finished
	_window.queue_free()


func _type_line(text: String, color: Color) -> void:
	var l := UITheme.outlined(text, 19, color, 0)
	l.visible_ratio = 0.0
	_lines.add_child(l)
	Sfx.play("click", 0.1, -12.0)
	var tw := _track(create_tween())
	tw.tween_property(l, "visible_ratio", 1.0, clampf(text.length() * 0.016, 0.25, 0.7))
	await tw.finished


func _subtitle_show(text: String, hold: float, title := false) -> void:
	_subtitle.text = text
	_subtitle.add_theme_font_size_override("font_size", 46 if title else 28)
	_subtitle.modulate.a = 0.0
	var tw := _track(create_tween())
	tw.tween_property(_subtitle, "modulate:a", 1.0, 0.4)
	tw.tween_interval(hold)
	tw.tween_property(_subtitle, "modulate:a", 0.0, 0.5)


## Onomatopeia de mangá no meio da tela: entra grande e torta, encolhe e some.
func _onomatopoeia(text: String) -> void:
	var l := UITheme.outlined(text, 96, Color(1.0, 0.86, 0.3), 16)
	l.add_theme_font_override("font", UITheme.serif())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.anchor_left = 0.27
	l.anchor_right = 0.27
	l.anchor_top = 0.24
	l.anchor_bottom = 0.24
	l.offset_left = -260
	l.offset_right = 260
	l.offset_top = -80
	l.offset_bottom = 80
	l.pivot_offset = Vector2(260, 80)
	l.rotation = -0.18
	l.scale = Vector2(2.2, 2.2)
	_ui.add_child(l)
	var tw := _track(create_tween())
	tw.tween_property(l, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)


# ================================================================ utilidades
func _wait(s: float) -> void:
	await get_tree().create_timer(s, true).timeout


func _track(tw: Tween) -> Tween:
	_tweens.append(tw)
	return tw


func _fade(rect: ColorRect, to: float, dur: float) -> void:
	_track(create_tween()).tween_property(rect, "color:a", to, dur)


func _look(pos: Vector3, at: Vector3) -> void:
	_cam.global_position = pos
	if pos.distance_to(at) > 0.01:
		_cam.look_at(at, Vector3.UP)


func _set_player_hidden(hide: bool, keep_tags_hidden := false) -> void:
	player.visible = not hide
	player.set("input_locked", true)   # _finish devolve o controle
	for tag in ["name_tag", "title_tag"]:
		var t = player.get(tag)
		if t is Node3D:
			t.visible = not hide and not keep_tags_hidden


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


func _glow_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


func _sphere(r: float, c: Color, additive: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	var m := _glow_mat(c)
	if additive or c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _hline(c: Color) -> StyleBoxLine:
	var s := StyleBoxLine.new()
	s.color = c
	s.thickness = 1
	return s
