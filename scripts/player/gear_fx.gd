class_name GearFx
extends RefCounted
## Texturas animadas e partículas dos conjuntos de fim de jogo (nível 50). Roda no fim de KnightLook.apply,
## depois do ToonLook: troca por shader animado as superfícies cujo material do GLB está em SURFACES (pelo
## nome) e prende ao personagem as partículas do conjunto (PARTICLES, por estilo do equipamento).
## Sem dependência de autoload, para as ferramentas de foto usarem o mesmo caminho do jogo.

const GALAXY := preload("res://assets/shaders/gear_galaxy.gdshader")
const GLOW := preload("res://assets/shaders/gear_glow.gdshader")
const SHEEN := preload("res://assets/shaders/gear_sheen.gdshader")
const STARSKY := preload("res://assets/shaders/gear_starsky.gdshader")
const ENERGY := preload("res://assets/shaders/gear_energy.gdshader")

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
	# ---- Placas Astrais (cavaleiro celeste): céu estrelado vivo na capa
	"cs_sky": {"shader": STARSKY, "lit": true, "params": {}},
	# ---- Cavaleiro Cósmico: céu roxo e magenta com estrelas douradas nas janelas da placa (esterno, olhos)
	"cz_sky": {"shader": STARSKY, "lit": true, "params": {
		"cloth_z": 3.0, "top_z": 1.7, "bottom_z": 0.6, "drift": 0.035, "energy": 1.4,
		"top_col": Color(0.14, 0.04, 0.28), "bottom_col": Color(0.34, 0.07, 0.38),
		"neb_col": Color(0.85, 0.2, 0.45), "star_col": Color(1.0, 0.86, 0.5), "rings": 1.0, "star_scale": 0.6}},
	# frisos de ouro: uma faixa de luz sobe correndo de tempos em tempos (só nos frisos: em placa inteira escurece)
	"cz_gold": {"shader": SHEEN, "lit": true, "params": {
		"sheen_col": Color(1.0, 0.92, 0.66), "sheen_power": 1.4, "sheen_dir": Vector3(0.25, 1.0, 0.0), "sheen_freq": 0.06,
		"sheen_speed": 0.3, "sheen_width": 0.05, "gloss": 0.0}},
	# linhas de luz estelar: onda clara correndo pelos traços, de baixo para cima
	"cz_star_flat": {"shader": GLOW, "params": {
		"flow_freq": 2.2, "flow_speed": 0.9, "flow_sharp": 5.0, "low": 0.55, "flow_dir": Vector3(0.0, 1.0, 0.0),
		"hot": Color(1.0, 1.0, 0.92), "energy": 2.4, "twinkle": 0.4, "twinkle_cell": 0.02}},
	# buraco negro do peito: disco de acreção dourado girando em volta do miolo escuro
	"cs_void_flat": {"shader": GALAXY, "lit": true, "params": {
		"center": Vector2(0.0, 1.322), "radius": 0.022, "star_reach": 0.0, "spin": 0.7, "core_gain": -0.8,
		"energy": 1.4, "space_col": Color(0.01, 0.008, 0.02), "haze_col": Color(0.2, 0.11, 0.03),
		"arm_col": Color(0.92, 0.62, 0.2), "hot_col": Color(1.0, 0.9, 0.6)}},
	# ---- Manto do Vazio (faixas de energia e runas, ref. Natam Antony): o forro azul vira energia líquida
	#      escorrendo com bolhas de luz; as runas acendem em onda que desce pelo manto e cintilam
	"rb_void_lining": {"shader": ENERGY, "params": {}},
	"rb_void_slit": {"shader": ENERGY, "params": {"rim": 0.25}},
	"rb_void_hatlining": {"shader": ENERGY, "params": {}},
	"rb_void_gem_flat": {"shader": GLOW, "params": {
		"flow_freq": 1.4, "flow_speed": 2.2, "flow_sharp": 6.0, "low": 0.35, "flow_dir": Vector3(0.0, -1.0, 0.0),
		"twinkle": 0.35, "twinkle_cell": 0.05, "hot": Color(0.92, 0.98, 1.0)}},
	# ---- Lich Soberano: fogo-fátuo verde tremulando em olhos e gemas, reflexo espectral varrendo os ossos
	"eg_lich_glow_gem_flat": {"shader": GLOW, "params": {"flicker": 1.0, "hot": Color(0.9, 1.0, 0.85)}},
	"rb_lich_gem_flat": {"shader": GLOW, "params": {"flicker": 0.8, "pulse": 0.25, "hot": Color(0.9, 1.0, 0.85)}},
	"eg_lich_bone": {"shader": SHEEN, "lit": true, "params": {
		"sheen_col": Color(0.36, 1.0, 0.48), "sheen_power": 0.55, "sheen_dir": Vector3(0.2, 1.0, 0.0), "sheen_speed": 0.22}},
	# ---- Hierofante Solar: gemas pulsando como sol, brilho correndo no ouro
	"eg_hiero_glow_gem_flat": {"shader": GLOW, "params": {"pulse": 0.4, "pulse_speed": 1.3, "hot": Color(1.0, 1.0, 0.9)}},
	"rb_hierophant_gem_flat": {"shader": GLOW, "params": {"pulse": 0.4, "pulse_speed": 1.3, "hot": Color(1.0, 1.0, 0.9)}},
	"eg_hiero_gold": {"shader": SHEEN, "lit": true, "params": {
		"sheen_col": Color(1.0, 0.93, 0.62), "sheen_power": 1.1, "sheen_dir": Vector3(0.6, 1.0, 0.0), "sheen_speed": 0.34}},
	"rb_hierophant_trim": {"shader": SHEEN, "lit": true, "params": {
		"sheen_col": Color(1.0, 0.93, 0.62), "sheen_power": 1.1, "sheen_dir": Vector3(0.6, 1.0, 0.0), "sheen_speed": 0.34}},
	# ---- Escamas de brasa: a brasa respira (pulso lento) e uma onda mais clara desce do peito para as mãos e a
	#      barra da saia; a gema do esterno treme como chama
	"ds_vein_glow_flat": {"shader": GLOW, "params": {
		"pulse": 0.2, "pulse_speed": 1.1, "flow_freq": 0.9, "flow_speed": 0.45, "flow_sharp": 10.0, "low": 0.75,
		"flow_dir": Vector3(0.0, -1.0, 0.0), "emission": Color(1.0, 0.02, 0.03), "hot": Color(1.0, 0.06, 0.05),
		"energy": 2.2}},
	"ds_gem_glow_flat": {"shader": GLOW, "params": {"flicker": 0.55, "pulse": 0.15, "pulse_speed": 1.1,
		"hot": Color(1.0, 0.97, 0.8), "energy": 4.0}},
	# ---- Paladino real: a cada poucos segundos uma faixa de luz sobe correndo pelos frisos de ouro
	"pa_gold": {"shader": SHEEN, "lit": true, "params": {
		"sheen_col": Color(1.0, 0.95, 0.7), "sheen_power": 1.5, "sheen_dir": Vector3(0.35, 1.0, 0.0), "sheen_freq": 0.05,
		"sheen_speed": 0.35, "sheen_width": 0.045, "gloss": 0.0}},
	# ---- Senhor dos Corvos: reflexo azul-violeta varrendo as penas, olhos pulsando
	"eg_raven_feather": {"shader": SHEEN, "lit": true, "params": {
		"sheen_col": Color(0.3, 0.42, 1.0), "sheen_power": 0.6, "sheen_dir": Vector3(1.0, 0.5, 0.0), "sheen_freq": 0.7,
		"sheen_speed": 0.28, "sheen_width": 0.07}},
	"eg_raven_sheen": {"shader": SHEEN, "lit": true, "params": {
		"sheen_col": Color(0.62, 0.38, 1.0), "sheen_power": 0.75, "sheen_dir": Vector3(1.0, 0.5, 0.0), "sheen_freq": 0.7,
		"sheen_speed": 0.28, "sheen_width": 0.07}},
	"eg_raven_glow_gem_flat": {"shader": GLOW, "params": {"pulse": 0.6, "pulse_speed": 2.2, "hot": Color(1.0, 0.9, 1.0)}},
	"rb_raven_gem_flat": {"shader": GLOW, "params": {"pulse": 0.6, "pulse_speed": 2.2, "hot": Color(1.0, 0.9, 1.0)}},
	# ---- Mago Dracônico: brasa respirando entre as escamas, gemas em chama
	"eg_dragon_scale": {"shader": SHEEN, "lit": true, "params": {
		"sheen_power": 0.0, "ember": 2.0, "ember_col": Color(1.0, 0.42, 0.08)}},
	"eg_dragon_plate": {"shader": SHEEN, "lit": true, "params": {
		"sheen_power": 0.0, "ember": 2.0, "ember_col": Color(1.0, 0.42, 0.08)}},
	"eg_dragon_glow_gem_flat": {"shader": GLOW, "params": {"flicker": 0.9, "hot": Color(1.0, 0.95, 0.7)}},
	"rb_dragon_gem_flat": {"shader": GLOW, "params": {"flicker": 0.9, "hot": Color(1.0, 0.95, 0.7)}},
	# ---- Astrônomo Celeste: constelações cintilando conta a conta, brilho correndo no ouro
	"eg_astral_glow_gem_flat": {"shader": GLOW, "params": {"twinkle": 1.0, "twinkle_cell": 0.035, "hot": Color(1.0, 1.0, 1.0)}},
	"rb_astral_gem_flat": {"shader": GLOW, "params": {"twinkle": 1.0, "twinkle_cell": 0.035, "hot": Color(1.0, 1.0, 1.0)}},
	"eg_astral_gold": {"shader": SHEEN, "lit": true, "params": {
		"sheen_col": Color(0.85, 0.95, 1.0), "sheen_power": 0.9, "sheen_dir": Vector3(-0.5, 1.0, 0.0), "sheen_speed": 0.3}},
	# ---- Soberano do Gelo: brilho interno correndo nos cristais e cintilação
	"eg_frost_ice_gem_flat": {"shader": GLOW, "params": {
		"flow_freq": 3.0, "flow_speed": 1.6, "flow_sharp": 8.0, "low": 0.75, "flow_dir": Vector3(0.45, 1.0, 0.2),
		"hot": Color(1.0, 1.0, 1.0), "energy": 1.3}},
	"eg_frost_deep_gem_flat": {"shader": GLOW, "params": {"pulse": 0.4, "pulse_speed": 1.0, "hot": Color(1.0, 1.0, 1.0)}},
	# ---- Dragão negro e ouro: olho de dragão no peito pulsando como brasa, a fenda do elmo acesa no mesmo ouro
	"dk_eye_glow_flat": {"shader": GLOW, "params": {"pulse": 0.45, "pulse_speed": 0.9, "flicker": 0.25,
		"hot": Color(1.0, 0.92, 0.55), "energy": 2.4}},
	"dk_helm_glow_flat": {"shader": GLOW, "params": {"pulse": 0.45, "pulse_speed": 0.9, "flicker": 0.3,
		"hot": Color(1.0, 0.9, 0.5), "energy": 2.0}},
}

## estilo do equipamento -> partículas (ver _particles)
const PARTICLES := {
	"a_reaper": {"color": Color(0.66, 0.36, 1.0), "amount": 14, "life": 2.4, "height": 0.3, "ring": 0.3, "rise": 0.32,
		"size": 0.034, "spread": 12.0},
	"a_void": {"color": Color(0.35, 0.7, 1.0), "amount": 12, "life": 2.6, "height": 0.6, "ring": 0.34, "rise": 0.22,
		"size": 0.022, "spread": 20.0, "band": 1.0},
	"a_lich": {"color": Color(0.36, 1.0, 0.48), "amount": 12, "life": 2.8, "height": 0.5, "ring": 0.34, "rise": 0.42,
		"size": 0.042, "spread": 8.0, "band": 0.6},
	"a_hierophant": {"color": Color(1.0, 0.82, 0.4), "amount": 14, "life": 3.2, "height": 0.9, "ring": 0.42, "rise": 0.16,
		"size": 0.026, "spread": 30.0, "band": 1.2},
	"a_raven": {"color": Color(0.08, 0.09, 0.16), "amount": 5, "life": 3.0, "height": 1.3, "ring": 0.36, "rise": -0.3,
		"size": 0.06, "spread": 25.0, "band": 0.3, "dark": true},
	"a_dragon": {"color": Color(1.0, 0.5, 0.12), "amount": 16, "life": 1.6, "height": 0.6, "ring": 0.32, "rise": 0.75,
		"size": 0.022, "spread": 18.0, "band": 0.8},
	"a_astral": {"color": Color(0.62, 0.82, 1.0), "amount": 16, "life": 3.4, "height": 1.0, "ring": 0.46, "rise": 0.1,
		"size": 0.024, "spread": 60.0, "band": 1.4},
	"a_emberscale": {"color": Color(1.0, 0.3, 0.1), "amount": 18, "life": 1.8, "height": 0.5, "ring": 0.34, "rise": 0.7,
		"size": 0.024, "spread": 16.0, "band": 1.0},
	"a_celestial": {"color": Color(1.0, 0.9, 0.62), "amount": 14, "life": 3.0, "height": 1.1, "ring": 0.36,
		"rise": -0.18, "size": 0.026, "spread": 40.0, "band": 1.0},
	"a_cosmic": {"color": Color(1.0, 0.84, 0.5), "amount": 18, "life": 3.4, "height": 1.25, "ring": 0.4,
		"rise": -0.14, "size": 0.024, "spread": 45.0, "band": 1.3},
	"h_cosmic": {"color": Color(0.78, 0.5, 1.0), "amount": 8, "life": 2.2, "height": 1.72, "ring": 0.2,
		"rise": 0.18, "size": 0.02, "spread": 25.0, "band": 0.3},
	"a_frost": {"color": Color(0.8, 0.93, 1.0), "amount": 14, "life": 2.6, "height": 1.2, "ring": 0.38, "rise": -0.26,
		"size": 0.03, "spread": 14.0, "band": 0.7},
	# fumaça escura subindo devagar em volta do corpo
	"a_blackdragon": {"color": Color(0.05, 0.05, 0.06, 0.7), "amount": 22, "life": 3.6, "height": 0.55, "ring": 0.28,
		"rise": 0.2, "size": 0.42, "spread": 18.0, "band": 1.3, "dark": true, "soft": true},
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
	if fx.shader == SHEEN and base != null:      # metal escurecido e com brilho em faixa, como em ToonLook._fill
		m.set_shader_parameter("albedo", base.albedo_color.darkened(0.35 * clampf(base.metallic, 0.0, 1.0)))
		m.set_shader_parameter("gloss", 0.9 if base.metallic > 0.55 else 0.0)
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
	p.angle_min = 0.0 if d.get("soft", false) else 45.0
	p.angle_max = 360.0 if d.get("soft", false) else 45.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.2, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	var q := QuadMesh.new()
	q.size = Vector2.ONE * float(d.size)
	q.material = _particle_mat(d.color, d.get("dark", false), d.get("soft", false))
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


static func _particle_mat(c: Color, dark := false, soft := false) -> StandardMaterial3D:
	var key := c.to_html() + str(dark) + str(soft)
	if _part_mats.has(key):
		return _part_mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	# acima de 1 acende o brilho da tela; "dark" (penas do corvo) fica na cor, sem acender
	m.albedo_color = c if dark else Color(c.r * 2.2, c.g * 2.2, c.b * 2.2)
	if soft:                   # fumaça: mancha redonda de borda esfumaçada, transparente (alfa da cor)
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.75))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 64
		m.albedo_texture = tex
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_part_mats[key] = m
	return m
