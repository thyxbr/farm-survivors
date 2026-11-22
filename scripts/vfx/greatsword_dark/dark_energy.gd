class_name DarkEnergy
extends RefCounted
## Peças da energia sombria da montante, divididas pelas três habilidades (Ciclone de Aço, Dança do Abismo, Lâmina
## Suprema): a paleta (a das garras do Corte do Abismo: violeta, carmesim, miolo quase preto) e as partículas feitas em
## código (GPUParticles3D), para não repetir as mesmas dezenas de linhas em cada cena.
##   wisps()   fiapos de fumaça escura (mistura normal: escurecem o que está atrás) subindo e se desfazendo
##   motes()   faíscas violeta (aditivas) flutuando com turbulência
##   sparks()  lascas carmesim alongadas na direção do voo (aditivas)
## Todas no mundo (local_coords = false): ficam para trás quando o emissor se mexe, como rastro.

const VIOLET := Color(0.48, 0.16, 1.0)
const CRIMSON := Color(1.0, 0.1, 0.32)
const HOT := Color(1.0, 0.82, 1.0)
const SMOKE := Color(0.06, 0.012, 0.1)

static var _ramps := {}


## Fumaça escura. `size` = lado do quad (m).
static func wisps(amount: int, lifetime: float, size: float) -> GPUParticles3D:
	var p := _base(amount, lifetime)
	var m := _process_mat()
	m.direction = Vector3.UP
	m.spread = 35.0
	m.initial_velocity_min = 0.2
	m.initial_velocity_max = 0.8
	m.gravity = Vector3(0, 0.45, 0)
	m.damping_min = 0.6
	m.damping_max = 1.4
	m.angle_min = -180.0
	m.angle_max = 180.0
	m.angular_velocity_min = -40.0
	m.angular_velocity_max = 40.0
	m.scale_min = 0.6
	m.scale_max = 1.3
	m.scale_curve = _curve_tex("wisp_scale", [Vector2(0.0, 0.35), Vector2(0.4, 0.9), Vector2(1.0, 1.25)])
	m.color_ramp = _ramp("wisp", [0.0, 0.15, 0.55, 1.0], [Color(SMOKE, 0.0), Color(SMOKE, 0.6),
		Color(0.11, 0.03, 0.17, 0.3), Color(0.16, 0.05, 0.22, 0.0)])
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 1.2
	m.turbulence_noise_scale = 2.5
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = FXEpic._particle_mat(FXEpic._smoke_tex(), false, true)
	p.draw_pass_1 = q
	return p


## Faíscas violeta. `size` = lado do quad (m).
static func motes(amount: int, lifetime: float, size: float) -> GPUParticles3D:
	var p := _base(amount, lifetime)
	var m := _process_mat()
	m.direction = Vector3.UP
	m.spread = 60.0
	m.initial_velocity_min = 0.4
	m.initial_velocity_max = 1.8
	m.gravity = Vector3(0, 1.2, 0)
	m.damping_min = 0.5
	m.damping_max = 1.2
	m.scale_min = 0.5
	m.scale_max = 1.3
	m.color_ramp = _ramp("mote", [0.0, 0.12, 0.55, 1.0], [Color(HOT, 0.0), Color(VIOLET * 1.6, 1.0),
		Color(CRIMSON * 1.2, 0.8), Color(CRIMSON * 0.6, 0.0)])
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 2.4
	m.turbulence_noise_scale = 2.0
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = FXEpic._particle_mat(FXEpic._glow_tex(), true, true)
	p.draw_pass_1 = q
	return p


## Lascas carmesim e violeta alongadas no voo. `length` = comprimento do quad (m).
static func sparks(amount: int, lifetime: float, length: float) -> GPUParticles3D:
	var p := _base(amount, lifetime)
	var m := _process_mat()
	m.particle_flag_align_y = true
	m.direction = Vector3.UP
	m.spread = 75.0
	m.initial_velocity_min = 2.5
	m.initial_velocity_max = 7.0
	m.gravity = Vector3(0, -6.0, 0)
	m.damping_min = 1.5
	m.damping_max = 3.0
	m.scale_min = 0.5 * length
	m.scale_max = 1.2 * length
	m.color_ramp = _ramp("spark", [0.0, 0.4, 1.0], [Color(HOT * 1.4, 1.0), Color(VIOLET * 1.5, 1.0), Color(CRIMSON, 0.0)])
	p.process_material = m
	p.draw_pass_1 = FXEpic._spark_mesh()   # cruz de quads ao longo de Y: o align_y estica no voo
	return p


static func _base(amount: int, lifetime: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(1, amount)
	p.lifetime = lifetime
	p.emitting = false
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-8, -4, -8), Vector3(16, 12, 16))
	return p


static func _process_mat() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(0.1, 0.1, 0.1)
	return m


static func _ramp(key: String, offsets: Array, colors: Array) -> GradientTexture1D:
	if _ramps.has(key):
		return _ramps[key]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var t := GradientTexture1D.new()
	t.gradient = g
	t.use_hdr = true
	_ramps[key] = t
	return t


static func _curve_tex(key: String, pts: Array) -> CurveTexture:
	if _ramps.has(key):
		return _ramps[key]
	var c := Curve.new()
	for v: Vector2 in pts:
		c.add_point(v)
	var t := CurveTexture.new()
	t.curve = c
	_ramps[key] = t
	return t


## Coloca a caixa de emissão de `p` ao longo da lâmina (do cabo `b` à ponta `t`, mais `reach`): as partículas saem do
## corte inteiro, não de um ponto.
static func along_blade(p: GPUParticles3D, b: Vector3, t: Vector3, reach := 0.0, thick := 0.08) -> void:
	var axis := t - b
	var len := axis.length()
	if len < 0.001:
		p.global_position = b
		return
	var y := axis / len
	var x := y.cross(Vector3.UP)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	var full := len + reach
	p.global_transform = Transform3D(Basis(x, y, z), b + y * full * 0.5)
	(p.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(thick, full * 0.5, thick)
