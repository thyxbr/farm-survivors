class_name EarthquakeDust
extends Node3D
## Terremoto Devastador: a poeira (scenes/vfx/earthquake/earthquake_dust.tscn), tudo em GPUParticles3D:
##   Charge  poeirinha rodando junto aos pés enquanto o herói ergue o escudo (o chão acumulando pressão)
##   Burst   nuvem densa e baixa que explode do centro no impacto e corre rente ao chão
##   Front   camada de poeira que acompanha a frente da onda: o anel de emissão cresce com ela (`set_wave`)
##   puff    baforadas saindo das fissuras e das explosões secundárias (`puff`)
##   Settle  na dissipação, a poeira se espalha pela área inteira, sobe devagar e assenta
##   Sheet   a poeira assentando da sprite sheet (EarthquakeSheet.DUST) no centro, no fim
## Quantidade e densidade multiplicadas por EarthquakeConfig.dust_intensity. Se libera quando a última some.

const SHEET := preload("res://scenes/vfx/earthquake/earthquake_sheet.tscn")
const DUST_COLOR := Color(0.55, 0.5, 0.45)

## Material da poeira (um só para todas as ativações): ILUMINADO, ao contrário das faíscas, para escurecer à
## noite e na sombra (poeira sem luz própria brilharia como neblina clara no escuro).
static var _dust_mat: StandardMaterial3D

var config: EarthquakeConfig
var ground: EarthquakeGround
var _charge: GPUParticles3D
var _front: GPUParticles3D
var _front_mat: ParticleProcessMaterial
var _life := INF
var _t := 0.0


func setup(cfg: EarthquakeConfig, g: EarthquakeGround) -> void:
	config = cfg
	ground = g


func _ready() -> void:
	var k := config.dust_intensity
	if k <= 0.0:
		return
	var smoke := dust_material()
	# junto aos pés, puxada para dentro e girando (antes do impacto)
	var cm := _mat(EMISSION_RING, 1.8, 0.6, Vector3.UP, 15.0, Vector2(0.2, 0.6), Vector2(-1.6, -0.6), 0.15)
	cm.tangential_accel_min = 2.0
	cm.tangential_accel_max = 5.0
	cm.scale_min = 0.5
	cm.scale_max = 0.9
	cm.color_ramp = ramp([_c(0.0), _c(0.35), _c(0.25), _c(0.0)], [0.0, 0.25, 0.7, 1.0])
	_charge = emitter("Charge", quad(1.2, smoke), int(26 * k), 1.1, cm, false)
	_charge.explosiveness = 0.0
	# frente da onda: o anel de emissão acompanha o raio
	_front_mat = _mat(EMISSION_RING, 0.5, 0.4, Vector3.UP, 25.0, Vector2(0.2, 0.8), Vector2(1.5, 4.0) * config.size_k(), 0.08)
	_front_mat.damping_min = 0.8
	_front_mat.damping_max = 1.6
	_front_mat.scale_min = 0.7
	_front_mat.scale_max = 1.5
	_front_mat.scale_curve = curve([Vector2(0.0, 0.5), Vector2(0.35, 1.0), Vector2(1.0, 1.6)])
	_front_mat.color_ramp = ramp([_c(0.0), _c(0.45), _c(0.25), _c(0.0)], [0.0, 0.12, 0.6, 1.0])
	_front = emitter("Front", quad(1.6 * sqrt(config.size_k()), smoke), int(120 * k * config.size_k()), 1.8, _front_mat, false)
	_front.explosiveness = 0.0
	var R := config.radius
	for p: GPUParticles3D in [_charge, _front]:
		p.visibility_aabb = AABB(Vector3(-R * 1.4, -3.0, -R * 1.4), Vector3(R * 2.8, 10.0, R * 2.8))


## Liga/desliga a poeira junto aos pés.
func charge(on: bool) -> void:
	if _charge:
		_charge.emitting = on


## O escudo bateu: nuvem densa e baixa saindo do centro; a frente da onda começa a levantar poeira.
func impact() -> void:
	charge(false)
	var k := config.dust_intensity * clampf(config.impact_intensity, 0.4, 2.0)
	if k <= 0.0:
		return
	var m := _mat(EMISSION_RING, 1.2 * config.size_k(), 0.2, Vector3.UP, 30.0, Vector2(0.3, 1.6), Vector2(5.0, 11.0) * config.size_k(), 0.0)
	m.damping_min = 3.0
	m.damping_max = 5.0
	m.scale_min = 1.6 * sqrt(config.size_k())
	m.scale_max = 3.0 * sqrt(config.size_k())
	m.scale_curve = curve([Vector2(0.0, 0.4), Vector2(0.25, 1.0), Vector2(1.0, 1.5)])
	m.color_ramp = ramp([_c(0.0), _c(0.85), _c(0.5), _c(0.0)], [0.0, 0.08, 0.55, 1.0])
	var b := emitter("Burst", quad(2.2 * sqrt(config.size_k()), dust_material()), int(36 * k * sqrt(config.size_k())), 2.6, m, true)
	b.explosiveness = 0.95
	b.visibility_aabb = AABB(Vector3(-14, -3, -14), Vector3(28, 10, 28))
	if _front:
		_front.emitting = true


## Raio atual da onda: a poeira da frente nasce nele.
func set_wave(r: float) -> void:
	if _front_mat:
		_front_mat.emission_ring_radius = maxf(r, 0.3)
		_front_mat.emission_ring_inner_radius = maxf(r - 0.6, 0.0)


## Baforada de poeira em `at` (x, z a partir do centro), do tamanho `size` (m).
func puff(at: Vector2, size: float) -> void:
	var k := config.dust_intensity
	if k <= 0.0:
		return
	var m := _mat(EMISSION_SPHERE, size * 0.4, 0.0, Vector3.UP, 40.0, Vector2(0.6, 1.8) * sqrt(size), Vector2(0.5, 1.5), 0.1)
	m.damping_min = 1.5
	m.damping_max = 2.5
	m.scale_min = 0.6 * size
	m.scale_max = 1.2 * size
	m.scale_curve = curve([Vector2(0.0, 0.5), Vector2(0.3, 1.0), Vector2(1.0, 1.4)])
	m.color_ramp = ramp([_c(0.0), _c(0.7), _c(0.4), _c(0.0)], [0.0, 0.1, 0.55, 1.0])
	var p := emitter("Puff", quad(1.8 * sqrt(config.size_k()), dust_material()), int(14 * k * size), 1.7, m, true)
	p.explosiveness = 0.85
	p.position = ground.local_at(at, 0.2)


## A onda parou: a poeira da frente para de nascer, uma camada fina se espalha pela área e assenta, e o fim da
## sprite sheet (poeira e fissuras apagando) toca no centro.
func dissipate(time: float) -> void:
	if _front:
		_front.emitting = false
	charge(false)
	var k := config.dust_intensity
	var R := config.radius
	if k > 0.0:
		var m := _mat(EMISSION_RING, R * 0.75, 0.0, Vector3.UP, 60.0, Vector2(0.1, 0.5), Vector2(0.3, 1.0), 0.12)
		m.damping_min = 0.4
		m.damping_max = 0.8
		m.scale_min = 1.8 * sqrt(config.size_k())
		m.scale_max = 3.2 * sqrt(config.size_k())
		m.scale_curve = curve([Vector2(0.0, 0.6), Vector2(1.0, 1.4)])
		m.color_ramp = ramp([_c(0.0), _c(0.3), _c(0.18), _c(0.0)], [0.0, 0.2, 0.6, 1.0])
		var s := emitter("Settle", quad(2.0 * sqrt(config.size_k()), dust_material()), int(22 * k * sqrt(config.size_k())), time * 0.85, m, true)
		s.explosiveness = 0.7
		s.visibility_aabb = AABB(Vector3(-R * 1.4, -3.0, -R * 1.4), Vector3(R * 2.8, 10.0, R * 2.8))
		var sh: EarthquakeSheet = SHEET.instantiate()
		sh.name = "Sheet"
		add_child(sh)
		sh.place(ground.local_at(Vector2.ZERO), clampf(R * 0.75, 2.6, 7.0))
		sh.intensity = 0.5
		sh.play(EarthquakeSheet.DUST, time * 0.7, false, true)
	_life = _t + time + 0.3


func _process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		queue_free()


func _c(a: float) -> Color:
	return Color(DUST_COLOR.r, DUST_COLOR.g, DUST_COLOR.b, a)


const EMISSION_RING := ParticleProcessMaterial.EMISSION_SHAPE_RING
const EMISSION_SPHERE := ParticleProcessMaterial.EMISSION_SHAPE_SPHERE


## Material de processo de partículas de poeira: forma de emissão (`radius`/`inner` m), direção e espalhamento,
## velocidade para cima e para fora (min, max) e gravidade para cima (sobe devagar se > 0).
func _mat(shape: int, radius: float, inner: float, dir: Vector3, spread: float, up: Vector2, out: Vector2, lift: float) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = shape
	if shape == EMISSION_RING:
		m.emission_ring_axis = Vector3.UP
		m.emission_ring_radius = radius
		m.emission_ring_inner_radius = inner
		m.emission_ring_height = 0.25
	else:
		m.emission_sphere_radius = radius
	m.direction = dir
	m.spread = spread
	m.initial_velocity_min = up.x
	m.initial_velocity_max = up.y
	m.radial_velocity_min = out.x
	m.radial_velocity_max = out.y
	m.gravity = Vector3(0.0, lift, 0.0)
	m.angle_min = -180.0
	m.angle_max = 180.0
	m.angular_velocity_min = -30.0
	m.angular_velocity_max = 30.0
	return m


## GPUParticles3D filho deste nó, sem coordenadas locais (as partículas ficam no mundo). `one_shot` se libera
## sozinho no fim.
func emitter(nm: String, mesh: Mesh, amount: int, lifetime: float, pm: ParticleProcessMaterial, one_shot: bool) -> GPUParticles3D:
	var p := make_emitter(nm, mesh, amount, lifetime, pm, one_shot)
	add_child(p)
	p.position = ground.local_at(Vector2.ZERO, 0.15) if ground != null else Vector3.ZERO
	p.emitting = one_shot
	return p


static func make_emitter(nm: String, mesh: Mesh, amount: int, lifetime: float, pm: ParticleProcessMaterial, one_shot: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = nm
	p.process_material = pm
	p.draw_pass_1 = mesh
	p.amount = maxi(amount, 1)
	p.lifetime = maxf(lifetime, 0.05)
	p.one_shot = one_shot
	p.randomness = 0.4
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	if one_shot:
		p.finished.connect(p.queue_free)
	return p


static func quad(size: float, mat: Material) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = mat
	return q


static func curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	for p: Vector2 in points:
		c.add_point(p)
	var t := CurveTexture.new()
	t.curve = c
	return t


static func ramp(colors: Array, offsets: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.colors = PackedColorArray(colors)
	g.offsets = PackedFloat32Array(offsets)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func dust_material() -> StandardMaterial3D:
	if _dust_mat != null:
		return _dust_mat
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_texture = FXEpic._smoke_tex()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.disable_receive_shadows = true
	# onde o quad encosta no chão a poeira some aos poucos (sem a linha reta do corte)
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.8
	_dust_mat = m
	return m
