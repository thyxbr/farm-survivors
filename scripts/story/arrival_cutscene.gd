class_name ArrivalCutscene
extends Node
## Abertura "isekai" do personagem novo (primeira vez no mundo), antes da narração e do Ancião Bram:
##   1. Tela preta: a última lembrança do outro mundo ("uma luz muito forte... e uma voz dizendo: Ops.").
##   2. Janela de SISTEMA (o clichê do anime isekai): transferência de alma, nome, classe, nível 1 e o aviso
##      de que o corpo original não veio junto e um novo vai ser gerado ali mesmo.
##   3. Plano do céu sobre Valdoria: um feixe de luz desce do céu até a estrada do sul.
##   4. Reconstrução: um anel de varredura sobe dos pés à cabeça e o corpo vai sendo montado em luz azul,
##      com blocos de dados chegando de todos os lados até a linha do anel.
##   5. O holograma fica sólido num clarão (o brilho azul se apaga por cima do corpo de verdade).
##   6. A câmera volta para trás do jogador e o mundo passa para a narração (StoryDialogue.intro()).
## Espaço, Enter ou Esc pulam para o fim a qualquer momento.

signal finished

const SKY_BLUE := Color(0.45, 0.85, 1.0)
const STAR_GOLD := Color(1.0, 0.9, 0.55)
const DATA_TONES := [Color(0.45, 0.85, 1.0), Color(0.75, 0.95, 1.0), Color(0.35, 0.6, 1.0)]

## Altura que o anel de varredura percorre (pés até um pouco acima da cabeça) e quanto tempo leva.
const BUILD_HEIGHT := 2.15
const BUILD_TIME := 2.8

## Holograma da reconstrução: some acima da linha de corte (altura no mundo), faixa branca na linha, grade
## de "dados" e borda brilhante. `fade` multiplica tudo (o brilho que se apaga por cima do corpo pronto).
const HOLO_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;
uniform float cut_y = 1000.0;
uniform float band = 0.14;
uniform vec4 tint : source_color = vec4(0.45, 0.85, 1.0, 1.0);
uniform float fade = 1.0;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	if (wpos.y > cut_y) {
		discard;
	}
	float edge = 1.0 - smoothstep(0.0, band, cut_y - wpos.y);
	vec3 g = abs(fract(wpos * 14.0) - 0.5);
	float grid = step(0.43, max(g.x, g.z)) + step(0.45, g.y);
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	vec3 c = tint.rgb * (0.28 + 0.75 * rim + 0.35 * min(grid, 1.0)) + vec3(0.9, 0.97, 1.0) * edge * 1.4;
	ALBEDO = c * fade;
}
"""

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
var _rings: Array[MeshInstance3D] = []
var _core_light: OmniLight3D
var _holo: ShaderMaterial
var _holo_meshes: Array = []   # {"mi", "override", "overlay"}: materiais originais para devolver no fim
var _cut := -1000.0            # linha de corte atual (altura no mundo) durante a montagem
var _building := false
var _bit_acc := 0.0
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
	player.global_position = _land + Vector3.UP * 0.05
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
	# --- 4. a reconstrução, dos pés à cabeça
	await _build_body()
	if _done: return
	await _wait(0.45)
	if _done: return
	# --- 5. o holograma fica sólido
	_solidify()
	await _wait(1.4)
	if _done: return
	_subtitle_show("(Esse corpo... é meu? Isso é... OUTRO MUNDO?!)", 2.6)
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


## Pula para o estado final: herói em pé na estrada, câmera do jogo.
func _skip() -> void:
	for tw in _tweens:
		if tw.is_valid():
			tw.kill()
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	_building = false
	_restore_materials()
	for n in [_beam, _seal, _core_light]:
		if is_instance_valid(n):
			n.queue_free()
	for r in _rings:
		if is_instance_valid(r):
			r.queue_free()
	_rings.clear()
	for f in _fx:
		if is_instance_valid(f.n):
			f.n.queue_free()
	_fx.clear()
	# herói em pé, olhando a vila
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
	# blocos de dados chegando de todos os lados até a linha do anel
	if _building:
		_bit_acc += delta
		while _bit_acc > 0.012:
			_bit_acc -= 0.012
			_data_bit_in()
		if _holo:
			_holo.set_shader_parameter("fade", 0.85 + 0.15 * sin(_clock * 37.0))
	# partículas
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


## Um feixe de luz desce do céu até a estrada; a câmera acompanha descendo.
func _beam_down() -> void:
	Sfx.play("portal", 0.0, -4.0)
	var top := _land + Vector3.UP * 60.0
	_beam = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.6
	cm.bottom_radius = 0.6
	cm.height = 1.0
	cm.radial_segments = 16
	cm.cap_top = false
	cm.cap_bottom = false
	_beam.mesh = cm
	var bm := _glow_mat(Color(SKY_BLUE, 0.4))
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam.material_override = bm
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(_beam)
	_beam.global_position = top
	_beam.scale = Vector3(1, 0.01, 1)
	var cam0 := _cam.global_position
	var cam1 := _land + _fwd * 4.6 + _right * 2.2 + Vector3.UP * 1.6
	var look0 := _sky_look
	var grow := func(u: float) -> void:
		var ln := maxf(0.01, 60.0 * u)
		_beam.scale = Vector3(1, ln, 1)
		_beam.global_position = top + Vector3.DOWN * ln * 0.5
		var tip := top + Vector3.DOWN * ln
		_look(cam0.lerp(cam1, smoothstep(0.25, 1.0, u)), look0.lerp(tip, smoothstep(0.0, 0.5, u)).lerp(_land + Vector3.UP * 0.9, smoothstep(0.55, 1.0, u)))
	var tw := _track(create_tween())
	tw.tween_method(grow, 0.0, 1.0, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	if _done:
		return
	_shake = 0.3
	# selo no chão e luz azul no ponto de chegada
	_seal = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.05
	tm.outer_radius = 1.15
	tm.rings = 48
	tm.ring_segments = 6
	_seal.mesh = tm
	_seal.material_override = _glow_mat(SKY_BLUE)
	_seal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(_seal)
	_seal.global_position = _land + Vector3.UP * 0.04
	_seal.scale = Vector3(0.05, 0.12, 0.05)
	_track(create_tween()).tween_property(_seal, "scale", Vector3(1, 0.12, 1), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_core_light = OmniLight3D.new()
	_core_light.light_color = Color(0.6, 0.85, 1.0)
	_core_light.light_energy = 2.0
	_core_light.omni_range = 6.0
	world.add_child(_core_light)
	_core_light.global_position = _land + Vector3.UP * 1.2
	# o feixe afina até virar um fio fraco, para não esconder o corpo sendo montado
	_track(create_tween()).tween_property(_beam, "scale:x", 0.1, 0.6)
	_track(create_tween()).tween_property(_beam, "scale:z", 0.1, 0.6)
	_track(create_tween()).tween_property(_beam.material_override, "albedo_color:a", 0.22, 0.6)


## O anel de varredura sobe dos pés à cabeça; abaixo dele o corpo existe em luz azul.
func _build_body() -> void:
	_apply_hologram()
	_set_player_hidden(false, true)
	Sfx.play("arcane_cast", 0.0, -3.0)
	for i in 2:
		var r := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.55 + 0.22 * i
		tm.outer_radius = 0.59 + 0.22 * i
		tm.rings = 40
		tm.ring_segments = 4
		r.mesh = tm
		var m := _glow_mat(Color(0.85, 0.97, 1.0, 0.95 - 0.45 * i))
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		r.material_override = m
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(r)
		r.scale = Vector3(1, 0.3, 1)
		_rings.append(r)
	_building = true
	var y0 := _land.y - 0.05
	var step := func(u: float) -> void:
		_cut = y0 + BUILD_HEIGHT * u
		_holo.set_shader_parameter("cut_y", _cut)
		for i in _rings.size():
			_rings[i].global_position = Vector3(_land.x, _cut - 0.06 * i, _land.z)
		# câmera girando devagar, de três quartos para a frente do herói, subindo junto
		var a := lerpf(0.75, 0.15, u)
		var dir := (_fwd * cos(a) + _right * sin(a)).normalized()
		_look(_land + dir * lerpf(4.4, 3.6, u) + Vector3.UP * lerpf(1.1, 1.6, u), _land + Vector3.UP * lerpf(0.7, 1.2, u))
	var tw := _track(create_tween())
	tw.tween_method(step, 0.0, 1.0, BUILD_TIME)
	# blips de montagem pelo caminho
	for i in 5:
		tw.parallel().tween_callback(Sfx.play.bind("click", 0.2, -8.0)).set_delay(BUILD_TIME * (0.1 + 0.18 * i))
	await tw.finished
	_building = false
	if _done:
		return
	_holo.set_shader_parameter("fade", 1.0)
	for r in _rings:
		var rt := _track(create_tween())
		rt.tween_property(r.material_override, "albedo_color:a", 0.0, 0.35)
		rt.tween_callback(r.queue_free)
	_rings.clear()


## O holograma vira o corpo de verdade num clarão; o brilho azul se apaga por cima e os blocos se espalham.
func _solidify() -> void:
	Sfx.play("levelup", 0.0, -4.0)
	Sfx.play("heal", 0.0, -6.0)
	_flash.color = Color(0.85, 0.97, 1.0, 0.85)
	_track(create_tween()).tween_property(_flash, "color:a", 0.0, 0.5)
	_shake = 0.35
	# materiais originais de volta; o holograma passa a ser só um brilho por cima, que some
	for h in _holo_meshes:
		if is_instance_valid(h.mi):
			h.mi.material_override = h.override
			h.mi.material_overlay = _holo
	_holo.set_shader_parameter("cut_y", 1000.0)
	_track(create_tween()).tween_method(func(v: float) -> void: _holo.set_shader_parameter("fade", v), 1.0, 0.0, 0.9)
	_track(create_tween()).tween_callback(_restore_materials).set_delay(0.95)
	for i in 40:
		var p := _land + Vector3(randf_range(-0.35, 0.35), randf_range(0.1, 1.9), randf_range(-0.35, 0.35))
		var out := (p - _land) * Vector3(1, 0, 1)
		out = out.normalized() if out.length() > 0.05 else Vector3.RIGHT
		_data_bit(p, out * randf_range(1.5, 3.2) + Vector3.UP * randf_range(0.2, 1.2), randf_range(0.6, 1.0), -1.5)
	if is_instance_valid(_beam):
		_track(create_tween()).tween_property(_beam.material_override, "albedo_color:a", 0.0, 0.6)
	if is_instance_valid(_seal):
		var m: StandardMaterial3D = _seal.material_override
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_track(create_tween()).tween_property(m, "albedo_color:a", 0.0, 1.0)
		_track(create_tween()).tween_property(_seal, "scale", Vector3(1.8, 0.12, 1.8), 1.0)
	if is_instance_valid(_core_light):
		_track(create_tween()).tween_property(_core_light, "light_energy", 0.0, 1.2)
	# câmera de frente, mais perto
	var cam0 := _cam.global_position
	var cam1 := _land + _fwd * 3.0 - _right * 0.9 + Vector3.UP * 1.55
	var look0 := _land + Vector3.UP * 1.2
	var move := func(u: float) -> void: _look(cam0.lerp(cam1, u), look0.lerp(_land + Vector3.UP * 1.3, u))
	_track(create_tween()).tween_method(move, 0.0, 1.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


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


# ================================================================ holograma e efeitos
## Troca os materiais do modelo pelo holograma (guardando os originais).
func _apply_hologram() -> void:
	var sh := Shader.new()
	sh.code = HOLO_SHADER
	_holo = ShaderMaterial.new()
	_holo.shader = sh
	_holo.set_shader_parameter("cut_y", _land.y - 0.1)
	var model: Node3D = player.get("model")
	if model == null:
		return
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		_holo_meshes.append({"mi": mi, "override": mi.material_override, "overlay": mi.material_overlay})
		mi.material_override = _holo
		mi.material_overlay = null


func _restore_materials() -> void:
	for h in _holo_meshes:
		if is_instance_valid(h.mi):
			h.mi.material_override = h.override
			h.mi.material_overlay = h.overlay
	_holo_meshes.clear()


## Bloco de dados que nasce em volta do herói e voa até a linha do anel.
func _data_bit_in() -> void:
	var a := randf() * TAU
	var r := randf_range(1.2, 2.6)
	var p := _land + Vector3(cos(a) * r, _cut - _land.y + randf_range(-0.2, 0.9), sin(a) * r)
	var target := _land + Vector3(cos(a) * 0.25, _cut - _land.y, sin(a) * 0.25)
	var life := randf_range(0.3, 0.5)
	_data_bit(p, (target - p) / life, life, 0.0)


## Cubinho de luz (os "dados" da reconstrução).
func _data_bit(p: Vector3, v: Vector3, life: float, grav: float) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var s := randf_range(0.035, 0.08)
	bm.size = Vector3(s, s, s)
	mi.mesh = bm
	var m := _glow_mat(Color(DATA_TONES[randi() % DATA_TONES.size()], 0.95))
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	mi.global_position = p
	mi.rotation = Vector3(randf() * TAU, randf() * TAU, 0)
	_fx.append({"n": mi, "v": v, "life": life, "age": 0.0, "grow": 0.4, "grav": grav, "a0": 0.95})


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
		["⚠ Corpo original: não veio junto. Gerando um novo no destino...", Color(1.0, 0.78, 0.4)],
		["⚠ Reconstrução: 99,7%. Os 0,3% devem fazer falta.  Boa sorte!", Color(1.0, 0.55, 0.45)],
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
