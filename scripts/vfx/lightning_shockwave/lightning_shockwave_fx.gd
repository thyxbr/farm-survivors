class_name LightningShockwaveFX
extends Node3D
## Raio e Onda de Choque: o visual inteiro, feito em código sobre três pinturas (branco em fundo preto, tingidas
## aqui). Um por ativação; nasce no ponto do impacto, toca a linha do tempo sozinho e se libera.
## Medido na referência (30 quadros por segundo, t = 0 no quadro em que o raio cai):
##   bolt      0,00 s  raio grosso branco do céu ao chão, UM quadro (raio_folha.png, 4 desenhos)
##   flare     0,00 s  clarão em estrela no peito e nos pés (clarao.png do Vórtice)
##   bolt_dark 0,04 a 0,26 s  o mesmo raio em preto (negativo), trocando de desenho, apagando
##   rim       0,00 a 1,05 s  contorno do corpo aceso: branco, depois na cor, apagando (body_rim.gdshader)
##   splash    0,02 a 0,38 s  respingo no chão (respingo_chao.png) que abre e fura no meio, virando anel
##   ring      0,12 a 0,85 s  a crista pintada (onda_faixa.png) enrolada em anel: abre rápido e freia, depois se
##                            desfaz em pedaços (erosão, não transparência)
##   crown     a mesma crista em pé sobre o anel (dá volume), some antes
##   lines     riscos finos de velocidade em volta
##   disc      o chão escurece por dentro do anel
##   arcs      arcos brancos pequenos: no corpo no começo, depois na crista; trocam a cada quadro de 30 Hz
##   bolt2     0,22 a 0,31 s  segundo raio, fino e azul
##   sparks    faíscas soltas
##   light     luz azul no chão, forte no impacto, apagando devagar
## `radius` = raio final do anel (m). `body` = o modelo do personagem (para o contorno); pode ser nulo.
## Em jogo: a pancada em área do Golem de Cristal (Enemy._slam_visual, `slam_fx: "lightning"` em enemies.json).

const BLUE := Color(0.14, 0.2, 1.0)
const LIFE := 1.2
const STEP_HZ := 30.0      ## o tremor de desenho: tudo que é sorteado troca nesta frequência
const BOLT_H := 11.0
const BOLT_W := 1.5
const ARCS := 12
## A borda de fora do anel deitado sobe um pouco (m): em jogo a grama alta cobre o que fica rente ao chão.
const RING_LIFT := 0.38
const RING_Y := 0.1
const SEG := 96
const ROWS := 6

const BOLT_TEX := preload("res://assets/vfx/lightning_shockwave/raio_folha.png")
const CREST_TEX := preload("res://assets/vfx/lightning_shockwave/onda_faixa.png")
const SPLASH_TEX := preload("res://assets/vfx/lightning_shockwave/respingo_chao.png")
const FLARE_TEX := preload("res://assets/vfx/sword_vortex/clarao.png")
const BOLT_ADD := preload("res://shaders/lightning_shockwave/bolt_add.gdshader")
const BOLT_DARK := preload("res://shaders/lightning_shockwave/bolt_dark.gdshader")
const SPLASH := preload("res://shaders/lightning_shockwave/ground_splash.gdshader")
const RING := preload("res://shaders/lightning_shockwave/wave_ring.gdshader")
const LINES := preload("res://shaders/lightning_shockwave/speed_lines.gdshader")
const DISC := preload("res://shaders/lightning_shockwave/dark_disc.gdshader")
const RIM := preload("res://shaders/lightning_shockwave/body_rim.gdshader")
const FLARE := preload("res://shaders/sword_vortex/tex_flash.gdshader")

var radius := 3.8
var color := BLUE
var body: Node3D

var _t := 0.0
var _frames := 0
var _step := -1
var _seed := 0.0
var _bolt: MeshInstance3D
var _bolt_dark: MeshInstance3D
var _bolt2: MeshInstance3D
var _splash: MeshInstance3D
var _ring: MeshInstance3D
var _crown: MeshInstance3D
var _lines: MeshInstance3D
var _disc: MeshInstance3D
var _arcs: Array[MeshInstance3D] = []
var _light: OmniLight3D
var _rim: ShaderMaterial
var _rim_prev := {}


## Cria o efeito em `at` (o chão sob o personagem: posição e base inclinada como o terreno, FXToon.ground_frame),
## filho de `root`. `model` = quem acende o contorno: um nó com `flash_with` (Enemy) ou a raiz das malhas.
static func cast(root: Node, at: Transform3D, r := 3.8, model: Node3D = null, c := BLUE) -> LightningShockwaveFX:
	var fx := LightningShockwaveFX.new()
	fx.radius = r
	fx.color = c
	fx.body = model
	root.add_child(fx)
	fx.global_transform = at
	return fx


func _ready() -> void:
	_seed = randf() * 10.0
	var cv := Vector3(color.r, color.g, color.b)
	var big := AABB(Vector3(-radius * 2.0, -1.0, -radius * 2.0), Vector3(radius * 4.0, BOLT_H + 2.0, radius * 4.0))

	var add := _mat(BOLT_ADD, "bolts", BOLT_TEX, 6)
	var dark := _mat(BOLT_DARK, "bolts", BOLT_TEX, 5)
	var tall := QuadMesh.new()
	tall.center_offset = Vector3(0.0, 0.5, 0.0)
	_bolt = _node(tall, add, big)
	_bolt.scale = Vector3(BOLT_W, BOLT_H, 1.0)
	_bolt.set_instance_shader_parameter("col", cv.lerp(Vector3.ONE, 0.6))
	_bolt.set_instance_shader_parameter("intensity", 1.3)
	_bolt_dark = _node(tall, dark, big)
	_bolt_dark.scale = Vector3(BOLT_W, BOLT_H, 1.0)
	_bolt2 = _node(tall, add, big)
	_bolt2.scale = Vector3(BOLT_W * 0.4, BOLT_H, 1.0)
	_bolt2.set_instance_shader_parameter("whiten", 0.25)
	_bolt2.set_instance_shader_parameter("col", cv)
	_bolt2.set_instance_shader_parameter("intensity", 1.1)

	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	_disc = _node(plane, _mat(DISC, "", null, 0), big)
	_disc.position.y = 0.02
	_splash = _node(plane, _mat(SPLASH, "splash", SPLASH_TEX, 1), big)
	_splash.position.y = 0.04
	_splash.set_instance_shader_parameter("col", cv)
	_splash.set_instance_shader_parameter("spin", _seed)

	var ann := _annulus()
	var ring_mat := _mat(RING, "crest", CREST_TEX, 2)
	_ring = _node(ann, ring_mat, big)
	_ring.set_instance_shader_parameter("col", cv)
	_ring.set_instance_shader_parameter("seed", _seed)
	_ring.position.y = RING_Y
	var crown_mat := _mat(RING, "crest", CREST_TEX, 3)
	crown_mat.set_shader_parameter("repeat", 2.0)
	_crown = _node(ann, crown_mat, big)
	_crown.set_instance_shader_parameter("col", cv)
	_crown.set_instance_shader_parameter("seed", _seed + 0.37)
	_crown.position.y = RING_Y
	_lines = _node(ann, _mat(LINES, "", null, 2), big)
	_lines.set_instance_shader_parameter("col", cv)
	_lines.set_instance_shader_parameter("seed", _seed)

	var small := QuadMesh.new()
	for i in ARCS:
		var a := _node(small, add, big)
		a.set_instance_shader_parameter("free", 1.0)
		a.set_instance_shader_parameter("col", cv.lerp(Vector3.ONE, 0.5))
		a.visible = false
		_arcs.append(a)

	_light = OmniLight3D.new()
	_light.light_color = color.lerp(Color.WHITE, 0.45)
	_light.omni_range = radius * 1.7
	_light.omni_attenuation = 1.2
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, 1.3, 0.0)
	add_child(_light)

	_sparks()
	_flare(Vector3(0.0, 1.0, 0.0), 2.6, 0.075, 0.4, 0.5)
	_flare(Vector3(0.0, 0.1, 0.0), 1.8, 0.09, -0.5, 0.45)
	_rim_on()
	_apply(0.0)


func _exit_tree() -> void:
	_rim_off()


func _process(delta: float) -> void:
	_t += delta
	_frames += 1
	if _t >= LIFE:
		queue_free()
		return
	_apply(_t)


func _apply(t: float) -> void:
	var step := int(t * STEP_HZ)
	var reroll := step != _step
	_step = step

	# o raio: um quadro branco, depois o negativo preto, e o segundo raio fino
	var white := _frames <= 1 or t < 0.045
	_bolt.visible = white
	var dk := 1.0 - _k(t, 0.045, 0.26)
	_bolt_dark.visible = not white and dk > 0.0
	_bolt_dark.set_instance_shader_parameter("intensity", 0.95 * sqrt(dk))
	_bolt2.visible = t >= 0.225 and t < 0.3
	if reroll:
		if step == 0:
			_roll_bolt(_bolt, 0.0)
		if step % 2 == 0:
			_roll_bolt(_bolt_dark, 0.12)
		_roll_bolt(_bolt2, 0.35)

	# respingo no chão: abre, fura no meio e some comido
	_splash.visible = t >= 0.02 and t < 0.27
	var sd := radius * 2.0 * lerpf(0.16, 0.62, _out(_k(t, 0.02, 0.22)))
	_splash.scale = Vector3(sd, 1.0, sd)
	_splash.set_instance_shader_parameter("hole", lerpf(0.0, 1.15, _k(t, 0.12, 0.26)))
	_splash.set_instance_shader_parameter("erode", lerpf(0.08, 0.6, _k(t, 0.14, 0.27)))

	# o anel: abre rápido e freia; depois se desfaz
	var rk := _k(t, 0.1, 0.44)
	var r := radius * lerpf(0.3, 1.0, 1.0 - pow(1.0 - rk, 1.7))
	var w := radius * lerpf(0.42, 0.3, rk)
	_ring.visible = t >= 0.12 and t < 0.66
	_ring.set_instance_shader_parameter("radius", r - w * 0.55)
	_ring.set_instance_shader_parameter("width", w)
	_ring.set_instance_shader_parameter("erode", lerpf(0.06, 1.05, _k(t, 0.36, 0.64)))
	_ring.set_instance_shader_parameter("swirl", t * 0.3)
	_ring.set_instance_shader_parameter("lift", RING_LIFT)
	_crown.visible = t >= 0.12 and t < 0.6
	_crown.set_instance_shader_parameter("radius", r - w * 0.15)
	_crown.set_instance_shader_parameter("width", w * 0.75)
	_crown.set_instance_shader_parameter("lift", lerpf(1.15, 0.5, rk))
	_crown.set_instance_shader_parameter("erode", lerpf(0.12, 1.05, _k(t, 0.3, 0.58)))
	_crown.set_instance_shader_parameter("swirl", -t * 0.45)

	_lines.visible = t >= 0.18 and t < 0.65
	_lines.set_instance_shader_parameter("radius", r + w * 0.3)
	_lines.set_instance_shader_parameter("width", radius * 0.22)
	_lines.set_instance_shader_parameter("swirl", t * 5.0)
	_lines.set_instance_shader_parameter("intensity", _k(t, 0.18, 0.3) * (1.0 - _k(t, 0.45, 0.65)))

	_disc.visible = t >= 0.08 and t < 0.8
	_disc.scale = Vector3(r * 2.1, 1.0, r * 2.1)
	_disc.set_instance_shader_parameter("intensity", 0.35 * _k(t, 0.08, 0.24) * (1.0 - _k(t, 0.45, 0.8)))

	if reroll:
		_roll_arcs(t, r)

	# luz: estouro no impacto, depois uma poça azul que apaga devagar
	_light.light_energy = 5.0 * (1.0 - _k(t, 0.0, 0.12)) + 2.6 * (1.0 - _k(t, 0.45, 1.15))

	if _rim != null:
		_rim.set_shader_parameter("intensity", 1.0 - pow(_k(t, 0.55, 1.08), 1.5))
		_rim.set_shader_parameter("white", 1.0 - _k(t, 0.3, 0.8))


## Sorteia o desenho do raio (coluna, espelho) e desloca um pouco para o lado.
func _roll_bolt(n: MeshInstance3D, jitter: float) -> void:
	n.set_instance_shader_parameter("column", float(randi() % 4))
	n.set_instance_shader_parameter("flip", float(randi() % 2))
	n.position = Vector3(randf_range(-jitter, jitter), 0.0, randf_range(-jitter, jitter))


## Arcos pequenos: no corpo logo depois do impacto, depois espalhados pela crista do anel. Cada sorteio muda
## lugar, tamanho, giro e o trecho do desenho.
func _roll_arcs(t: float, r: float) -> void:
	var on_body := int(round(5.0 * (1.0 - _k(t, 0.12, 0.5))))
	var on_ring := int(round(float(ARCS - 5) * _k(t, 0.16, 0.24) * (1.0 - _k(t, 0.48, 0.74))))
	for i in ARCS:
		var a := _arcs[i]
		var is_body := i < 5
		a.visible = (i < on_body) if is_body else (i - 5 < on_ring)
		if not a.visible:
			continue
		var ang := randf() * TAU
		var size := randf_range(0.45, 0.95)
		if is_body:
			a.position = Vector3(cos(ang) * randf_range(0.2, 0.55), randf_range(0.25, 1.7), sin(ang) * randf_range(0.2, 0.55))
		else:
			var rr := r * randf_range(0.9, 1.08)
			a.position = Vector3(cos(ang) * rr, randf_range(0.12, 0.55), sin(ang) * rr)
			size *= 1.15
		a.scale = Vector3(0.5 * size, 0.62 * size, 1.0)
		var v0 := randf_range(0.02, 0.66)
		a.set_instance_shader_parameter("vrange", Vector2(v0, v0 + 0.3))
		a.set_instance_shader_parameter("column", float(randi() % 4))
		a.set_instance_shader_parameter("flip", float(randi() % 2))
		a.set_instance_shader_parameter("roll", randf() * TAU)
		a.set_instance_shader_parameter("intensity", randf_range(0.7, 1.3))


func _sparks() -> void:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = color.lerp(Color.WHITE, 0.7) * 2.5
	q.material = m
	p.mesh = q
	p.amount = 42
	p.one_shot = true
	p.explosiveness = 0.92
	p.lifetime = 0.85
	p.lifetime_randomness = 0.5
	p.direction = Vector3.UP
	p.spread = 78.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 9.0
	p.gravity = Vector3(0.0, -5.0, 0.0)
	p.damping_min = 2.0
	p.damping_max = 5.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.6
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	p.position = Vector3(0.0, 0.4, 0.0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.emitting = true


## Clarão pintado (tex_flash.gdshader do Vórtice): abre de golpe, gira um pouco e apaga.
func _flare(at: Vector3, size: float, time: float, turn: float, gain: float) -> void:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = FLARE
	mat.set_shader_parameter("flare", FLARE_TEX)
	mat.render_priority = 7
	qm.material = mat
	q.mesh = qm
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	q.extra_cull_margin = size
	var c := color.lerp(Color.WHITE, 0.35)
	q.set_instance_shader_parameter("col", Vector3(c.r, c.g, c.b))
	q.set_instance_shader_parameter("intensity", gain)
	q.set_instance_shader_parameter("spin", _seed)
	add_child(q)
	q.position = at
	q.scale = Vector3.ONE * size * 0.3
	var tw := q.create_tween().set_parallel(true)
	tw.tween_property(q, "scale", Vector3.ONE * size, time * 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_method(func(v: float) -> void: q.set_instance_shader_parameter("spin", v), _seed, _seed + turn, time)
	tw.tween_method(func(v: float) -> void: q.set_instance_shader_parameter("intensity", v), gain, 0.0, time) \
		.set_delay(time * 0.15).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_callback(q.queue_free)


func _rim_on() -> void:
	if body == null or not is_instance_valid(body):
		return
	_rim = ShaderMaterial.new()
	_rim.shader = RIM
	_rim.set_shader_parameter("col", Vector3(color.r, color.g, color.b))
	_rim.set_shader_parameter("intensity", 1.0)
	if body.has_method("flash_with"):   # Enemy: a camada entra pelo clarão dele (não briga com o status e o acerto)
		body.flash_with(_rim, 1.08)
		return
	for n in body.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		_rim_prev[mi] = mi.material_overlay
		mi.material_overlay = _rim


func _rim_off() -> void:
	for mi in _rim_prev:
		if is_instance_valid(mi) and mi.material_overlay == _rim:
			mi.material_overlay = _rim_prev[mi]
	_rim_prev.clear()


func _mat(shader: Shader, tex_name: String, tex: Texture2D, priority: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	if tex_name != "":
		m.set_shader_parameter(tex_name, tex)
	m.render_priority = priority
	return m


func _node(mesh: Mesh, mat: Material, aabb: AABB) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.custom_aabb = aabb
	add_child(n)
	return n


## Anel unitário para wave_ring / speed_lines: VERTEX = (cos, v, sen), UV = (volta, v).
static func _annulus() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in ROWS + 1:
		var v := float(i) / ROWS
		for j in SEG + 1:
			var a := TAU * float(j) / SEG
			verts.append(Vector3(cos(a), v, sin(a)))
			uvs.append(Vector2(float(j) / SEG, v))
	var row := SEG + 1
	for i in ROWS:
		for j in SEG:
			var a := i * row + j
			var b := a + row
			idx.append_array([a, b, a + 1, a + 1, b, b + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static func _k(t: float, a: float, b: float) -> float:
	return clampf((t - a) / (b - a), 0.0, 1.0)


static func _out(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)
