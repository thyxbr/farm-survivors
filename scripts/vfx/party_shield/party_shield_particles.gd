class_name PartyShieldParticles
extends RefCounted
## Grito do Bastião: monta os GPUParticles3D das cenas (faíscas em volta do buff, dissipação dos escudos, energia
## subindo na aura do grito). Pontinhos azuis aditivos num billboard de partícula; o material de desenho é um só,
## compartilhado (criado na primeira vez).

const BLUE := Color(0.45, 0.75, 1.0)
const HOT := Color(0.85, 0.96, 1.0)
## Tamanho do ponto de luz (m); a escala de cada partícula (scale_min/max) multiplica isto.
const DOT_SIZE := 0.09

static var _dot_mat: StandardMaterial3D
static var _dot_mesh: QuadMesh


## Quad de partícula com um ponto de luz redondo (aditivo, cor do vértice = cor da partícula).
static func dot_mesh() -> QuadMesh:
	if _dot_mesh == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(0, 0, 0, 1))
		g.add_point(0.25, Color(0.8, 0.8, 0.8, 1))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 32
		tex.height = 32
		_dot_mat = StandardMaterial3D.new()
		_dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_dot_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_dot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_dot_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_dot_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_dot_mat.vertex_color_use_as_albedo = true
		_dot_mat.albedo_texture = tex
		_dot_mat.render_priority = 3
		_dot_mesh = QuadMesh.new()
		_dot_mesh.size = Vector2.ONE * DOT_SIZE
		_dot_mesh.material = _dot_mat
	return _dot_mesh


## Cor que nasce clara, vira azul e some (o preto, no aditivo, não soma nada).
static func _fade_ramp(start: Color, mid: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, start)
	g.set_color(1, Color(0, 0, 0, 1))
	g.add_point(0.35, mid)
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex


static func _common(p: GPUParticles3D, amount: int, life: float) -> void:
	p.amount = maxi(amount, 1)
	p.lifetime = life
	p.local_coords = false
	p.draw_pass_1 = dot_mesh()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 6, 8))


## Os escudos virando partículas pequenas: um estouro só, saindo da órbita para fora e para cima, freando e sumindo.
static func setup_dissipate(p: GPUParticles3D, cfg: PartyShieldConfig) -> void:
	_common(p, cfg.dissipate_particles, PartyShieldBuff.PARTICLE_LIFE)
	p.one_shot = true
	p.explosiveness = 0.75
	p.emitting = false
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	m.emission_ring_axis = Vector3.UP
	m.emission_ring_radius = cfg.orbit_radius
	m.emission_ring_inner_radius = cfg.orbit_radius * 0.75
	m.emission_ring_height = 0.35
	m.direction = Vector3(0, 0.6, 0)
	m.spread = 180.0
	m.initial_velocity_min = 0.3
	m.initial_velocity_max = 1.2
	m.radial_velocity_min = 0.2
	m.radial_velocity_max = 0.7
	m.damping_min = 1.2
	m.damping_max = 2.4
	m.gravity = Vector3(0, 0.35, 0)
	m.scale_min = 0.25
	m.scale_max = 0.65
	m.color_ramp = _fade_ramp(HOT, BLUE)
	p.process_material = m
	p.position.y = cfg.orbit_height


## Energia subindo do chão em volta do herói enquanto ele grita.
static func setup_motes(p: GPUParticles3D, cfg: PartyShieldConfig) -> void:
	var life := 1.1
	_common(p, int(28 * cfg.aura_intensity) + 4, life)
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	m.emission_ring_axis = Vector3.UP
	m.emission_ring_radius = 0.75
	m.emission_ring_inner_radius = 0.3
	m.emission_ring_height = 0.1
	m.direction = Vector3.UP
	m.spread = 12.0
	m.initial_velocity_min = 0.8
	m.initial_velocity_max = 1.8
	m.radial_velocity_min = -0.25
	m.radial_velocity_max = -0.05
	m.gravity = Vector3.ZERO
	m.damping_min = 0.3
	m.damping_max = 0.8
	m.scale_min = 0.35
	m.scale_max = 0.7
	m.color_ramp = _fade_ramp(HOT, BLUE)
	p.process_material = m
	p.position.y = 0.1
