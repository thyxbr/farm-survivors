class_name ArrivalCutscene
extends Node
## Abertura "isekai" do personagem novo (primeira vez no mundo), antes da narração e do Ancião Bram:
##   1. Tela preta: a última lembrança do outro mundo ("uma luz muito forte... e uma voz dizendo: Ops.").
##   2. Janela de SISTEMA (o clichê do anime isekai): transferência de alma, nome, classe, nível 1 e o aviso
##      de que o corpo vai ser montado "com o material disponível".
##   3. Plano do céu sobre Valdoria: um ponto de luz se abre lá no alto e desce um feixe até a estrada do sul.
##   4. Um selo se acende no chão e fragmentos de cristal chegam girando de todos os lados, montando um casulo.
##   5. O casulo pulsa, racha e estoura em cacos: o herói está lá dentro, flutuando, e desce devagar até o chão.
##   6. A câmera volta para trás do jogador e o mundo passa para a narração (StoryDialogue.intro()).
## Espaço, Enter ou Esc pulam para o fim a qualquer momento. Alguns cristais pequenos ficam cravados na estrada
## (só neste cliente, até sair do mapa), como prova da chegada.

signal finished

const SKY_BLUE := Color(0.45, 0.85, 1.0)
const STAR_GOLD := Color(1.0, 0.9, 0.55)
const CRYSTAL_TONES := [Color(0.55, 0.92, 1.0), Color(0.4, 0.75, 1.0), Color(0.72, 0.68, 1.0), Color(0.82, 0.97, 1.0)]

## Altura em que o herói aparece quando o casulo estoura (depois desce flutuando).
const REVEAL_HEIGHT := 0.9
## Quanto tempo os fragmentos levam para chegar ao casulo (cada um tem um atraso de até SHARD_STAGGER).
const SHARD_FLIGHT := 1.5
const SHARD_STAGGER := 1.1

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
var _sky_look := Vector3.ZERO
var _beam: MeshInstance3D
var _seal: MeshInstance3D
var _core_light: OmniLight3D
var _cocoon: Array = []      # fragmentos em voo/montados: {"n", "a0", "r0", "h0", "a1", "r1", "h1", "q0", "q1", "t0"}
var _cocoon_t := -1.0        # relógio da montagem (-1 fora dela)
var _remnants: Node3D
var _glow: MeshInstance3D
var _shake := 0.0
var _fx: Array = []          # partículas soltas: {"n": Node3D, "v": Vector3, "life", "age", "grow", "grav", "a0"}
var _tweens: Array[Tween] = []
var _done := false
var _hud_was_visible := true
var _clock := 0.0
var _interp_mode := Node.PHYSICS_INTERPOLATION_MODE_INHERIT


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_land = player.global_position
	# a vila fica ao norte da estrada: o herói surge olhando para ela
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
	player.set_physics_process(false)
	var model: Node3D = player.get("model")
	if model:
		model.rotation.y = atan2(_fwd.x, _fwd.z)
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
	# --- 3. o céu de Valdoria e o feixe de luz
	_fade(_black, 0.0, 1.0)
	_subtitle_show("Valdoria", 2.0, true)
	await _wait(1.6)
	if _done: return
	await _beam_down()
	if _done: return
	# --- 4. o selo e os fragmentos montando o casulo
	_start_cocoon()
	await _wait(SHARD_FLIGHT + SHARD_STAGGER + 0.15)
	if _done: return
	await _cocoon_pulse()
	if _done: return
	# --- 5. o casulo estoura e o herói desce flutuando
	_shatter()
	await _float_down()
	if _done: return
	await _wait(1.0)
	if _done: return
	_subtitle_show("(Eu fui... montado de cristal? Isso é... OUTRO MUNDO?!)", 2.6)
	await _wait(3.0)
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


## Pula para o estado final: herói em pé na estrada, cristais cravados em volta, câmera do jogo.
func _skip() -> void:
	for tw in _tweens:
		if tw.is_valid():
			tw.kill()
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	_cocoon_t = -1.0
	for c in _cocoon:
		if is_instance_valid(c.n):
			c.n.queue_free()
	_cocoon.clear()
	for n in [_beam, _seal, _core_light, _glow]:
		if is_instance_valid(n):
			n.queue_free()
	for f in _fx:
		if is_instance_valid(f.n):
			f.n.queue_free()
	_fx.clear()
	if _remnants == null:
		_plant_remnants()
	# herói em pé no meio dos cristais, olhando a vila
	var model: Node3D = player.get("model")
	if model:
		model.rotation.x = 0.0
		model.rotation.z = 0.0
		model.rotation.y = atan2(_fwd.x, _fwd.z)
	player.global_position = _land + Vector3.UP * 0.05
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
	# fragmentos chegando em espiral até o lugar deles no casulo
	if _cocoon_t >= 0.0:
		_cocoon_t += delta
		for c in _cocoon:
			var u := clampf((_cocoon_t - float(c.t0)) / SHARD_FLIGHT, 0.0, 1.0)
			var n: Node3D = c.n
			if u <= 0.0:
				continue
			if not n.visible:
				n.visible = true
				if randf() < 0.35:
					Sfx.play("gem", 0.15, -10.0)
			var e := 1.0 - pow(1.0 - u, 3.0)   # chega rápido e assenta devagar
			var a := lerpf(c.a0, c.a1, e)
			var r := lerpf(c.r0, c.r1, e)
			var h := lerpf(c.h0, c.h1, e)
			n.global_position = _land + Vector3(cos(a) * r, h, sin(a) * r)
			n.quaternion = (c.q0 as Quaternion).slerp(c.q1, e)
			if u < 1.0:
				_trail_mote(n.global_position, 0.05)
	# partículas: brilhos, cacos e poeira
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
		if f.has("spin"):
			n.rotate_object_local(f.spin, delta * 7.0)
		n.scale = Vector3.ONE * lerpf(1.0, float(f.grow), k)
		var mi := n as MeshInstance3D
		if mi and mi.material_override is StandardMaterial3D:
			var m: StandardMaterial3D = mi.material_override
			m.albedo_color.a = (1.0 - k) * float(f.get("a0", 1.0))
	# selo girando no chão
	if is_instance_valid(_seal):
		_seal.rotation.y += delta * 0.8
	# tremor da câmera
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 1.6)
		_cam.h_offset = randf_range(-1, 1) * _shake * 0.3
		_cam.v_offset = randf_range(-1, 1) * _shake * 0.3
	else:
		_cam.h_offset = 0.0
		_cam.v_offset = 0.0


# ================================================================ cenas
func _place_sky_camera() -> void:
	# ao sul do ponto de chegada, baixo, olhando o céu por cima da vila
	var pos := _land - _fwd * 11.0 - _right * 3.5 + Vector3.UP * 2.0
	_sky_look = _land + _fwd * 40.0 + _right * 8.0 + Vector3.UP * 22.0
	_look(pos, _sky_look)


## Um ponto de luz se abre no céu e um feixe desce até a estrada; a câmera acompanha descendo.
func _beam_down() -> void:
	Sfx.play("portal", 0.0, -4.0)
	var top := _land + Vector3.UP * 60.0
	_beam = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.55
	cm.bottom_radius = 0.55
	cm.height = 1.0
	cm.radial_segments = 16
	cm.cap_top = false
	cm.cap_bottom = false
	_beam.mesh = cm
	var bm := _glow_mat(Color(SKY_BLUE, 0.45))
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam.material_override = bm
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(_beam)
	_beam.global_position = top
	_beam.scale = Vector3(1, 0.01, 1)
	var cam0 := _cam.global_position
	var cam1 := _land + _fwd * 5.5 + _right * 2.6 + Vector3.UP * 2.4
	var look0 := _sky_look
	var grow := func(u: float) -> void:
		var ln := maxf(0.01, 60.0 * u)
		_beam.scale = Vector3(1, ln, 1)
		_beam.global_position = top + Vector3.DOWN * ln * 0.5
		var tip := top + Vector3.DOWN * ln
		_look(cam0.lerp(cam1, smoothstep(0.25, 1.0, u)), look0.lerp(tip, smoothstep(0.0, 0.5, u)).lerp(_land + Vector3.UP * 1.1, smoothstep(0.55, 1.0, u)))
	var tw := _track(create_tween())
	tw.tween_method(grow, 0.0, 1.0, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	if _done:
		return
	_shake = 0.3
	# o feixe afina enquanto o selo assume
	_track(create_tween()).tween_property(_beam, "scale:x", 0.25, 1.4)
	_track(create_tween()).tween_property(_beam, "scale:z", 0.25, 1.4)


## Selo no chão e os fragmentos saindo de todos os lados em espiral até o casulo.
func _start_cocoon() -> void:
	_seal = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.25
	tm.outer_radius = 1.4
	tm.rings = 48
	tm.ring_segments = 6
	_seal.mesh = tm
	_seal.material_override = _glow_mat(SKY_BLUE)
	_seal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(_seal)
	_seal.global_position = _land + Vector3.UP * 0.04
	_seal.scale = Vector3(0.05, 0.12, 0.05)
	# marcas do selo: quatro losangos em cruz por dentro do anel
	for i in 4:
		var mark := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.22, 0.36, 0.02)
		mark.mesh = pm
		mark.material_override = _glow_mat(STAR_GOLD)
		var a := TAU * i / 4.0
		mark.position = Vector3(cos(a) * 1.0, 0.0, sin(a) * 1.0)
		mark.rotation = Vector3(-PI / 2, 0, 0)
		mark.rotate_y(-a - PI / 2)
		_seal.add_child(mark)
	_track(create_tween()).tween_property(_seal, "scale", Vector3(1, 0.12, 1), 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_core_light = OmniLight3D.new()
	_core_light.light_color = Color(0.7, 0.9, 1.0)
	_core_light.light_energy = 1.5
	_core_light.omni_range = 7.0
	world.add_child(_core_light)
	_core_light.global_position = _land + Vector3.UP * 1.1
	Sfx.play("frost", 0.0, -6.0)
	# câmera girando devagar em volta do casulo enquanto ele se monta
	var orbit := func(u: float) -> void:
		var a := lerpf(0.55, -0.35, u)
		var dir := (_fwd * cos(a) + _right * sin(a)).normalized()
		_look(_land + dir * lerpf(6.0, 4.6, u) + Vector3.UP * lerpf(2.4, 1.8, u), _land + Vector3.UP * 1.1)
	_track(create_tween()).tween_method(orbit, 0.0, 1.0, SHARD_FLIGHT + SHARD_STAGGER + 1.4).set_trans(Tween.TRANS_SINE)
	# o casulo: um anel de cristais grandes inclinados para dentro e uma coroa menor por cima
	var slots: Array = []
	for i in 9:
		var a := TAU * i / 9.0 + 0.2
		slots.append({"a": a, "r": randf_range(0.6, 0.78), "h": 0.0, "len": randf_range(1.7, 2.4), "w": randf_range(0.17, 0.24), "tilt": randf_range(0.22, 0.45)})
	for i in 6:
		var a := TAU * i / 6.0 + 0.5
		slots.append({"a": a, "r": 0.32, "h": 0.85, "len": randf_range(1.0, 1.3), "w": 0.16, "tilt": 0.6})
	for i in 4:
		var a := TAU * i / 4.0 + 1.0
		slots.append({"a": a, "r": 0.95, "h": 0.0, "len": randf_range(0.6, 0.9), "w": 0.13, "tilt": -0.35})
	for s in slots:
		var n := _crystal(float(s.w), float(s.len), CRYSTAL_TONES[randi() % CRYSTAL_TONES.size()], 0.9)
		n.visible = false
		world.add_child(n)
		# aponta para cima, inclinado em direção ao centro (tilt > 0) ou para fora (tilt < 0)
		var out := Vector3(cos(s.a), 0, sin(s.a))
		var dir := (Vector3.UP - out * float(s.tilt)).normalized()
		var q1 := Quaternion(Vector3.UP, dir)
		var q0 := Quaternion(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized(), randf() * TAU)
		var a0 := float(s.a) - randf_range(1.4, 2.4)
		_cocoon.append({"n": n, "a0": a0, "r0": randf_range(3.5, 6.0), "h0": randf_range(4.5, 9.0),
			"a1": float(s.a), "r1": float(s.r), "h1": float(s.h), "q0": q0, "q1": q1,
			"t0": randf() * SHARD_STAGGER})
	_cocoon_t = 0.0


## O casulo pronto pulsa de luz duas vezes e treme (alguém está lá dentro).
func _cocoon_pulse() -> void:
	_cocoon_t = -1.0
	for i in 2:
		Sfx.play("gem", 0.0, -4.0)
		var tw := _track(create_tween())
		tw.tween_property(_core_light, "light_energy", 6.0, 0.22)
		tw.tween_property(_core_light, "light_energy", 1.8, 0.35)
		_shake = 0.25 + 0.2 * i
		await tw.finished
		if _done:
			return
	await _wait(0.25)


## O casulo estoura em cacos: flash, tremor, cacos voando e alguns cristais cravados na estrada.
func _shatter() -> void:
	Sfx.play("frost_hit", 0.0, -1.0)
	Sfx.play("levelup", 0.0, -8.0)
	_flash.color = Color(0.85, 0.97, 1.0, 0.9)
	_track(create_tween()).tween_property(_flash, "color:a", 0.0, 0.6)
	_shake = 0.8
	for c in _cocoon:
		var n: Node3D = c.n
		if not is_instance_valid(n):
			continue
		# cada cristal do casulo vira dois ou três cacos voando para fora
		for k in 3:
			var shard := _crystal(randf_range(0.05, 0.1), randf_range(0.15, 0.32), CRYSTAL_TONES[randi() % CRYSTAL_TONES.size()], 0.95)
			world.add_child(shard)
			shard.global_position = n.global_position + Vector3.UP * randf_range(0.2, 1.4)
			var out := (shard.global_position - _land) * Vector3(1, 0, 1)
			out = out.normalized() if out.length() > 0.05 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
			var v := out * randf_range(3.0, 6.5) + Vector3.UP * randf_range(2.5, 5.5)
			_fx.append({"n": shard, "v": v, "life": randf_range(1.1, 1.7), "age": 0.0, "grow": 0.4, "grav": 11.0,
				"spin": Vector3(randf_range(-1, 1), 1, randf_range(-1, 1)).normalized()})
		n.queue_free()
	_cocoon.clear()
	for i in 24:
		_trail_mote(_land + Vector3.UP * randf_range(0.3, 1.9), 0.9)
	_plant_remnants()
	if is_instance_valid(_beam):
		_track(create_tween()).tween_property(_beam.material_override, "albedo_color:a", 0.0, 0.8)
	if is_instance_valid(_seal):
		# o selo abre e some (o anel e as marcas)
		for mi in [_seal] + _seal.get_children():
			var m: StandardMaterial3D = mi.material_override
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_track(create_tween()).tween_property(m, "albedo_color:a", 0.0, 1.2)
		var st := _track(create_tween())
		st.tween_property(_seal, "scale", Vector3(1.6, 0.12, 1.6), 1.2)
		st.tween_callback(_seal.queue_free)
	if is_instance_valid(_core_light):
		_track(create_tween()).tween_property(_core_light, "light_energy", 0.0, 1.4)
	# o herói aparece no meio, flutuando, envolto num brilho que se apaga
	player.global_position = _land + Vector3.UP * REVEAL_HEIGHT
	_set_player_hidden(false, true)
	_glow = _sphere(1.05, Color(SKY_BLUE, 0.35), true)
	world.add_child(_glow)
	_glow.global_position = player.global_position + Vector3.UP * 0.95


## O herói desce flutuando até o chão; a câmera vai para a frente dele.
func _float_down() -> void:
	var a := player.global_position
	var b := _land + Vector3.UP * 0.05
	var cam0 := _cam.global_position
	var cam1 := _land + _fwd * 3.6 - _right * 1.2 + Vector3.UP * 1.55
	var look0 := _land + Vector3.UP * 1.1
	var look1 := _land + Vector3.UP * 1.2
	var down := func(u: float) -> void:
		player.global_position = a.lerp(b, u)
		if is_instance_valid(_glow):
			_glow.global_position = player.global_position + Vector3.UP * 0.95
			(_glow.material_override as StandardMaterial3D).albedo_color.a = 0.35 * (1.0 - u)
			_glow.scale = Vector3.ONE * lerpf(1.0, 0.7, u)
		if randf() < 0.3:
			_trail_mote(player.global_position + Vector3(randf_range(-0.5, 0.5), randf_range(0.2, 1.8), randf_range(-0.5, 0.5)), 0.4)
		_look(cam0.lerp(cam1, u), look0.lerp(look1, u))
	var tw := _track(create_tween())
	tw.tween_method(down, 0.0, 1.0, 1.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	if _done:
		return
	if is_instance_valid(_glow):
		_glow.queue_free()
	player.global_position = b
	Sfx.play("heal", 0.05, -6.0)
	# poeirinha de cristal subindo em volta dos pés
	for i in 10:
		var ang := TAU * i / 10.0
		_trail_mote(_land + Vector3(cos(ang) * 0.6, 0.1, sin(ang) * 0.6), 0.6)


func _blend_to_player(dur: float) -> void:
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


# ================================================================ cenário e efeitos
## Cristal: prisma de seis lados com ponta, de pé ao longo de +Y a partir da base (origem no pé).
func _crystal(w: float, length: float, c: Color, alpha: float) -> MeshInstance3D:
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = w
	cm.bottom_radius = w * 0.8
	cm.height = length * 0.72
	cm.radial_segments = 6
	cm.rings = 1
	body.mesh = cm
	body.material_override = _crystal_mat(c, alpha)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# a malha do corpo fica deslocada para a base cair na origem do nó
	var root := MeshInstance3D.new()
	root.material_override = body.material_override
	root.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.position = Vector3.UP * length * 0.36
	root.add_child(body)
	var tip := MeshInstance3D.new()
	var tmesh := CylinderMesh.new()
	tmesh.top_radius = 0.0
	tmesh.bottom_radius = w
	tmesh.height = length * 0.28
	tmesh.radial_segments = 6
	tmesh.rings = 1
	tip.mesh = tmesh
	tip.material_override = body.material_override
	tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tip.position = Vector3.UP * length * 0.86
	root.add_child(tip)
	return root


func _crystal_mat(c: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.55
	m.roughness = 0.15
	m.metallic_specular = 0.9
	return m


## Brilho pequeno que sobe e some (rastro dos fragmentos, poeira de cristal).
func _trail_mote(p: Vector3, rise: float) -> void:
	var c: Color = SKY_BLUE if randf() < 0.7 else STAR_GOLD
	var s := _sphere(randf_range(0.04, 0.09), Color(c, 0.85), true)
	world.add_child(s)
	s.global_position = p
	_fx.append({"n": s, "v": Vector3(randf_range(-0.2, 0.2), rise, randf_range(-0.2, 0.2)), "life": randf_range(0.6, 1.1),
		"age": 0.0, "grow": 0.3, "grav": 0.0, "a0": 0.85})


## Cristais pequenos cravados na estrada em volta do ponto de chegada (ficam depois da cena).
func _plant_remnants() -> void:
	_remnants = Node3D.new()
	_remnants.name = "CristaisDaChegada"
	world.add_child(_remnants)
	_remnants.global_position = _land
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 7:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.9, 2.1)
		var cl := Node3D.new()
		_remnants.add_child(cl)
		cl.position = Vector3(cos(a) * r, -0.04, sin(a) * r)
		cl.rotation.y = rng.randf() * TAU
		for k in rng.randi_range(1, 3):
			var n := _crystal(rng.randf_range(0.05, 0.09), rng.randf_range(0.22, 0.45), CRYSTAL_TONES[rng.randi() % CRYSTAL_TONES.size()], 0.85)
			cl.add_child(n)
			n.position = Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.08, 0.08))
			n.rotation = Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))


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
		["⚠ Corpo original: indisponível. Montando um novo com o material local...", Color(1.0, 0.78, 0.4)],
		["⚠ Material local: cristal. Montagem: 99,7%.  Boa sorte!", Color(1.0, 0.55, 0.45)],
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
