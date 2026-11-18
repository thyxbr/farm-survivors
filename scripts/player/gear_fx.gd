class_name GearFx
extends RefCounted
## Texturas animadas e partículas dos conjuntos de fim de jogo (nível 50). Roda no fim de KnightLook.apply,
## depois do ToonLook: troca por shader animado as superfícies cujo material do GLB está em SURFACES (pelo
## nome) e prende ao personagem as partículas do conjunto (PARTICLES, por estilo do equipamento).
## Sem dependência de autoload, para as ferramentas de foto usarem o mesmo caminho do jogo.

const GALAXY := preload("res://assets/shaders/gear_galaxy.gdshader")
const GLOW := preload("res://assets/shaders/gear_glow.gdshader")

## nome do material no GLB -> {"shader", "params"}. Em "params", cores como Color e o resto como no shader.
const SURFACES := {
	# ---- Ceifador do Vazio: galáxia nas costas do manto e no disco atrás da cabeça, fios com energia correndo
	"rb_reaper_cloth": {"shader": GALAXY, "lit": true, "params": {
		"center": Vector2(0.0, 0.74), "radius": 0.225, "squash": Vector2(1.0, 0.72), "tilt": 0.5, "star_reach": 3.0}},
	"eg_reaper_space_gem_flat": {"shader": GALAXY, "lit": true, "params": {
		"center": Vector2(0.0, 1.765), "radius": 0.14, "star_reach": 0.0, "spin": 0.3, "energy": 1.4}},
	"eg_reaper_glow_gem_flat": {"shader": GLOW, "params": {
		"flow_freq": 3.2, "flow_speed": 2.6, "flow_sharp": 4.0, "low": 0.5, "hot": Color(1.0, 0.92, 1.0)}},
	"rb_reaper_gem_flat": {"shader": GLOW, "params": {"pulse": 0.35, "pulse_speed": 1.8, "hot": Color(1.0, 0.92, 1.0)}},
}

## estilo do equipamento -> partículas (ver _particles)
const PARTICLES := {
	"a_reaper": {"color": Color(0.66, 0.36, 1.0), "amount": 14, "life": 2.4, "height": 0.3, "ring": 0.3, "rise": 0.32,
		"size": 0.034, "spread": 12.0},
}

static var _mats := {}       # nome do material + cor por vértice -> ShaderMaterial
static var _part_mats := {}  # cor -> material das partículas


## Aplica nas peças de equipamento de `model` (nós `Gear_*`). `styles`: estilos vestidos (h_reaper, a_reaper...).
## Devolve os nós criados (partículas), para KnightLook apagar na próxima troca de equipamento.
static func apply(model: Node3D, styles: Array) -> Array:
	var made: Array = []
	for mi: MeshInstance3D in model.find_children("Gear_*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			if src != null and SURFACES.has(src.resource_name):
				var colored := (mi.mesh as ArrayMesh) != null and ((mi.mesh as ArrayMesh).surface_get_format(s) & Mesh.ARRAY_FORMAT_COLOR) != 0
				mi.set_surface_override_material(s, material_for(src, colored))
	if DisplayServer.get_name() != "headless":
		for st in styles:
			if PARTICLES.has(st):
				var p := _particles(PARTICLES[st])
				p.name = "GearFx_" + str(st)
				model.add_child(p)
				made.append(p)
	return made


## Material animado para um material do GLB que está em SURFACES (um por nome, compartilhado).
static func material_for(src: Material, vertex_color := false) -> ShaderMaterial:
	var key := "%s|%d" % [src.resource_name, int(vertex_color)]
	if _mats.has(key):
		return _mats[key]
	var fx: Dictionary = SURFACES[src.resource_name]
	var m := ShaderMaterial.new()
	m.shader = fx.shader
	var base := src as BaseMaterial3D
	if base != null:
		m.set_shader_parameter("albedo", base.albedo_color)
		if fx.shader == GLOW and base.emission_enabled:
			m.set_shader_parameter("emission", base.emission)
			m.set_shader_parameter("hot", base.emission.lightened(0.6))
			m.set_shader_parameter("energy", base.emission_energy_multiplier)
	if fx.get("lit", false):
		m.set_shader_parameter("toon", ToonLook.enabled())
		m.set_shader_parameter("use_vertex_color", vertex_color)
	for k in fx.params:
		m.set_shader_parameter(k, fx.params[k])
	_mats[key] = m
	return m


## Fagulhas em losango que nascem num anel em volta do personagem e sobem (ou descem, com "rise" negativo),
## ficando para trás quando ele anda. Poucas e sem luz: custo desprezível mesmo com vários jogadores.
static func _particles(d: Dictionary) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = d.amount
	p.lifetime = d.life
	p.preprocess = d.life
	p.local_coords = false
	p.position.y = d.height
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = d.ring
	p.emission_ring_inner_radius = d.ring * 0.55
	p.emission_ring_height = d.get("band", 0.25)
	p.direction = Vector3.UP if d.rise >= 0.0 else Vector3.DOWN
	p.spread = d.spread
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = absf(d.rise) * 0.6
	p.initial_velocity_max = absf(d.rise)
	p.angle_min = 45.0
	p.angle_max = 45.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.2, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	var q := QuadMesh.new()
	q.size = Vector2.ONE * float(d.size)
	q.material = _particle_mat(d.color)
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


static func _particle_mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if _part_mats.has(key):
		return _part_mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.albedo_color = Color(c.r * 2.2, c.g * 2.2, c.b * 2.2)       # acima de 1: acende o brilho da tela
	_part_mats[key] = m
	return m
