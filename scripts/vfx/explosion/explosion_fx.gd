class_name ExplosionFX
extends Node3D
## Explosão de desenho animado, feita em código sobre quatro pinturas (claro em fundo preto, tingidas aqui). Uma
## por estouro; toca a linha do tempo sozinha e se libera.
##   flash    0,00 s  clarão de riscos radiais (estouro_riscos.png) e a estrela (clarao.png do Vórtice), 2 quadros
##   tongues  0,00 a 0,32 s  línguas de fogo arremessadas (linguas_folha.png), que afinam e somem
##   cloud    0,00 a ~1,1 s  baforadas da nuvem pintada (nuvem_folha.png, 16 quadros em passos): bola de fogo que
##            infla depressa, vira fumaça em gomos de dois tons com rachas de brasa acesas (rachas_brasa.png) e se
##            desfaz em tufos. Uma grande no meio e outras em volta, cada uma um pouco atrasada e indo para fora
##   embers   brasas subindo
##   light    luz na cor do fogo
## `size` = 1 é uma explosão de ~2,5 m. `palette`: as cinco cores (ver FIRE); FXToon.fire_burst e FXToon.blast
## montam a paleta a partir das cores de sempre (fogo do jogador, fogo sombrio dos monstros).

const SHEET := preload("res://assets/vfx/explosion/nuvem_folha.png")
const CRACKS := preload("res://assets/vfx/explosion/rachas_brasa.png")
const BURST := preload("res://assets/vfx/explosion/estouro_riscos.png")
const TONGUES := preload("res://assets/vfx/explosion/linguas_folha.png")
const FLARE_TEX := preload("res://assets/vfx/sword_vortex/clarao.png")
const CLOUD := preload("res://shaders/explosion/cloud_flip.gdshader")
const TONGUE := preload("res://shaders/explosion/tongue.gdshader")
const FLARE := preload("res://shaders/sword_vortex/tex_flash.gdshader")
const FIRE := {"hot": Color(1.0, 0.95, 0.7), "body": Color(1.0, 0.5, 0.08), "smoke_a": Color(0.3, 0.1, 0.08),
	"smoke_b": Color(0.11, 0.03, 0.03), "ember": Color(1.0, 0.45, 0.08)}
const FRAMES := 16.0
## A nuvem em passos: até T_FIRE a bola infla (quadros 0 a 5), até T_SMOKE vira fumaça (5 a 10), depois se desfaz.
const T_FIRE := 0.16
const T_SMOKE := 0.5
const TONGUE_LIFE := 0.24

var size := 1.0
var palette: Dictionary = FIRE

var _t := 0.0
var _puffs: Array[Dictionary] = []
var _tongues: Array[Dictionary] = []
var _light: OmniLight3D

static var _cloud_mat: ShaderMaterial
static var _tongue_mat: ShaderMaterial
static var _quad: QuadMesh


## Estouro em `pos` (o centro da bola de fogo), filho de `root`.
static func spawn(root: Node, pos: Vector3, s := 1.0, pal: Dictionary = FIRE) -> ExplosionFX:
	var fx := ExplosionFX.new()
	fx.size = s
	fx.palette = pal
	root.add_child(fx)
	fx.global_position = pos
	return fx


static func _shared() -> void:
	if _cloud_mat != null:
		return
	_cloud_mat = ShaderMaterial.new()
	_cloud_mat.shader = CLOUD
	_cloud_mat.set_shader_parameter("sheet", SHEET)
	_cloud_mat.set_shader_parameter("cracks", CRACKS)
	_cloud_mat.render_priority = 1
	_tongue_mat = ShaderMaterial.new()
	_tongue_mat.shader = TONGUE
	_tongue_mat.set_shader_parameter("shapes", TONGUES)
	_tongue_mat.render_priority = 2
	_quad = QuadMesh.new()


func _ready() -> void:
	_shared()
	var hot := _v(palette.hot)
	var body := _v(palette.body)
	# a nuvem: uma grande no meio e quatro em volta, mais baixas e atrasadas
	for i in 5:
		var n := _quad_node(_cloud_mat)
		var out := Vector3.ZERO
		var scale_k := 2.7
		var delay := 0.0
		if i > 0:
			var a := TAU * (float(i) / 4.0) + randf_range(-0.4, 0.4)
			out = Vector3(cos(a), randf_range(-0.15, 0.45), sin(a)).normalized()
			scale_k = randf_range(1.5, 2.0)
			delay = randf_range(0.03, 0.1)
		n.position = out * 0.55 * size
		n.scale = Vector3.ONE * scale_k * size
		n.visible = false
		n.set_instance_shader_parameter("roll", randf_range(-0.5, 0.5))
		n.set_instance_shader_parameter("flip", float(randi() % 2))
		n.set_instance_shader_parameter("seed", randf())
		n.set_instance_shader_parameter("hot", hot)
		n.set_instance_shader_parameter("body", body)
		n.set_instance_shader_parameter("smoke_a", _v(palette.smoke_a))
		n.set_instance_shader_parameter("smoke_b", _v(palette.smoke_b))
		n.set_instance_shader_parameter("ember", _v(palette.ember))
		_puffs.append({"node": n, "delay": delay, "life": randf_range(0.95, 1.15),
			"vel": out * randf_range(1.6, 2.4) * size + Vector3.UP * randf_range(0.5, 0.9) * size})
	# línguas de fogo para todos os lados, um pouco para cima
	for i in 6:
		var n := _quad_node(_tongue_mat)
		var a := TAU * (float(i) / 6.0) + randf_range(-0.3, 0.3)
		var dir := Vector3(cos(a), randf_range(0.0, 0.55), sin(a)).normalized()
		n.scale = Vector3.ONE * randf_range(1.5, 2.2) * size
		n.set_instance_shader_parameter("cell", float(i % 4))
		n.set_instance_shader_parameter("flip", float(randi() % 2))
		n.set_instance_shader_parameter("hot", hot)
		n.set_instance_shader_parameter("body", body)
		_tongues.append({"node": n, "dir": dir, "speed": randf_range(11.0, 16.0) * size})
	_flash(BURST, (palette.body as Color).lerp(palette.hot, 0.6), 3.8 * size, 0.08, 0.15, 0.4)
	_flash(FLARE_TEX, palette.body, 2.6 * size, 0.12, -0.4, 0.3)
	_embers()
	_light = OmniLight3D.new()
	_light.light_color = (palette.body as Color).lerp(palette.hot, 0.4)
	_light.omni_range = 7.0 * size
	_light.shadow_enabled = false
	add_child(_light)
	_apply()


func _process(delta: float) -> void:
	_t += delta
	if _t > 1.3:
		queue_free()
		return
	for p in _puffs:
		var n: MeshInstance3D = p.node
		# a nuvem sai depressa e freia
		n.position += (p.vel as Vector3) * delta * exp(-4.0 * maxf(0.0, _t - float(p.delay)))
	_apply()


func _apply() -> void:
	for p in _puffs:
		var n: MeshInstance3D = p.node
		var t := _t - float(p.delay)
		var life: float = p.life
		n.visible = t >= 0.0 and t < life
		if not n.visible:
			continue
		var f := 0.0
		if t < T_FIRE:
			f = 5.0 * t / T_FIRE
		elif t < T_SMOKE:
			f = 5.0 + 5.0 * (t - T_FIRE) / (T_SMOKE - T_FIRE)
		else:
			f = 10.0 + 5.99 * (t - T_SMOKE) / (life - T_SMOKE)
		n.set_instance_shader_parameter("frame", floorf(minf(f, FRAMES - 1.0)))
		n.set_instance_shader_parameter("heat", 1.0 - _k(t, T_FIRE * 0.7, T_SMOKE * 0.8))
		n.set_instance_shader_parameter("glow", _k(t, T_FIRE, 0.3) * (1.0 - _k(t, 0.55, life * 0.9)))
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	for g in _tongues:
		var n: MeshInstance3D = g.node
		var k := _t / TONGUE_LIFE
		n.visible = k < 1.0
		if not n.visible:
			continue
		var d: Vector3 = g.dir
		# anda rápido e freia: distância = v / 6 * (1 - e^(-6t))
		n.position = d * (0.3 * size + float(g.speed) / 6.0 * (1.0 - exp(-6.0 * _t)))
		n.set_instance_shader_parameter("erode", pow(k, 1.6))
		if cam != null:   # a cabeça grossa da pintura (à esquerda) aponta para onde a língua voa
			var v := cam.global_basis.inverse() * d
			n.set_instance_shader_parameter("roll", atan2(v.y, v.x) + PI)
	_light.light_energy = 5.0 * (1.0 - _k(_t, 0.0, 0.18)) + 2.0 * (1.0 - _k(_t, 0.2, 0.8))


func _quad_node(mat: Material) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = _quad
	n.material_override = mat
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.extra_cull_margin = 4.0 * size
	add_child(n)
	return n


func _flash(tex: Texture2D, c: Color, sz: float, time: float, turn: float, gain: float) -> void:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = FLARE
	mat.set_shader_parameter("flare", tex)
	mat.render_priority = 3
	qm.material = mat
	q.mesh = qm
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	q.extra_cull_margin = sz
	var rot0 := randf() * TAU
	q.set_instance_shader_parameter("col", _v(c))
	q.set_instance_shader_parameter("intensity", gain)
	q.set_instance_shader_parameter("spin", rot0)
	add_child(q)
	q.scale = Vector3.ONE * sz * 0.35
	var tw := q.create_tween().set_parallel(true)
	tw.tween_property(q, "scale", Vector3.ONE * sz, time * 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_method(func(v: float) -> void: q.set_instance_shader_parameter("spin", v), rot0, rot0 + turn, time)
	tw.tween_method(func(v: float) -> void: q.set_instance_shader_parameter("intensity", v), gain, 0.0, time) \
		.set_delay(time * 0.3).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_callback(q.queue_free)


func _embers() -> void:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06) * size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = (palette.ember as Color).lerp(palette.hot, 0.4) * 2.0
	q.material = m
	p.mesh = q
	p.amount = 26
	p.one_shot = true
	p.explosiveness = 0.9
	p.lifetime = 1.0
	p.lifetime_randomness = 0.5
	p.direction = Vector3.UP
	p.spread = 85.0
	p.initial_velocity_min = 2.0 * size
	p.initial_velocity_max = 7.0 * size
	p.gravity = Vector3(0.0, -2.5, 0.0)
	p.damping_min = 2.5
	p.damping_max = 5.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.5
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.emitting = true


## Cor para o shader. As paletas são escritas como se vê na tela (sRGB); o shader trabalha em linear.
static func _v(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	return Vector3(l.r, l.g, l.b)


static func _k(t: float, a: float, b: float) -> float:
	return clampf((t - a) / (b - a), 0.0, 1.0)
