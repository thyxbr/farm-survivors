class_name HammerGroundShock
extends Node3D
## Martelo de Energia: o choque do martelo com o chão, por cima da explosão (HammerImpact) e das crateras
## (GroundCrater). O HammerSkill cria um no instante do impacto, no ponto onde o martelo bate; tudo é filho deste
## nó e ele se libera sozinho quando a última camada some (nada fica na cena depois da habilidade).
##   Shock     onda de choque e fissuras radiais da sprite sheet (assets/vfx/hammer/hammer_shock_sheet.webp, 8 x 8,
##             fundo #000000, aditiva) num billboard de pé no ponto do impacto (hammer_shock_sheet.gdshader)
##   Decals    rachaduras radiais projetadas no chão (Decal, então seguem o relevo): uma grande no centro e
##             algumas menores na onda; abrem num estalo, as brasas das rachaduras esfriam e elas somem com Tween
##   Debris / Embers / Smoke   GPUParticles3D de pedras, brasas e fumaça subindo e se espalhando
##   Light     clarão alaranjado das brasas
## e o tremor da câmera de quem está perto (`shake_local`). O hitstop é só do dono (HammerAbilities._on_landed).
## Tudo é ajustável no HammerConfig (grupo "Choque no chão"). `setup` antes de entrar na árvore.

const SHEET := preload("res://scenes/vfx/hammer/hammer_sheet_bill.tscn")
const SHEET_MAT := preload("res://assets/vfx/hammer/hammer_shock_sheet_mat.tres")
const STONE_MAT := preload("res://assets/vfx/hammer/hammer_stone_mat.tres")
## Quadros usados da sheet: 0-2 são só o ponto de luz crescendo (o martelo já bateu) e 58-63 estão vazios.
const SHEET_FRAMES := Vector2i(3, 57)
## Onde fica o ponto do impacto dentro do quadro (0 = topo, 1 = base): o chão desenhado ocupa a metade de baixo.
const SHEET_GROUND_V := 0.58
const DECAL_HEIGHT := 4.0       ## altura da caixa do Decal (m): pega o chão mesmo com desnível
const CRACK_TEX_SIZE := 256
const SIDE_DECALS := 4
const DECAL_GROW := 0.16        ## tempo para as rachaduras correrem até o tamanho todo (s)
const EMBER_COLOR := Color(1.0, 0.55, 0.15)

## Texturas das rachaduras (geradas uma vez, divididas por todas as ativações).
static var _crack_albedo: ImageTexture
static var _crack_emission: ImageTexture
## ParticleProcessMaterial por raio/intensidade: material novo a cada golpe faria o Godot descartar e recompilar o
## shader dele (engasgo no impacto), como em FXEpic._mats.
static var _process_mats := {}

var config: HammerConfig
var seed_value := 0
var deal_shake := true
var _t := 0.0
var _life := 1.0
var _rng := RandomNumberGenerator.new()


func setup(cfg: HammerConfig, seed_v: int) -> void:
	config = cfg
	seed_value = seed_v


## Prepara as texturas e os materiais antes do impacto (o HammerSkill chama ao começar a invocação), para o
## quadro do choque não pagar a geração.
static func warm(cfg: HammerConfig) -> void:
	if cfg == null:
		return
	_crack_textures()
	_process_material("debris", cfg)
	_process_material("embers", cfg)
	_process_material("smoke", cfg)


func _ready() -> void:
	if config == null:
		config = load("res://assets/vfx/hammer/hammer_config.tres")
	_rng.seed = seed_value * 17 + 3
	var k := config.explosion_intensity
	_spawn_sheet()
	_spawn_decals()
	var amt := config.debris_amount * k
	if amt > 0.0:
		_spawn_particles("debris", _stone_mesh(), int(46 * amt), 1.5)
		_spawn_particles("embers", _quad(0.16, FXEpic._particle_mat(FXEpic._glow_tex(), true, true)), int(110 * amt), 2.0)
		_spawn_particles("smoke", _quad(2.4, FXEpic._particle_mat(FXEpic._smoke_tex(), false)), int(26 * amt), 2.8)
	_spawn_light(k)
	if deal_shake:
		shake_local(global_position, config)
	_life = maxf(maxf(config.crack_decal_life, config.shock_sheet_time), 3.0) + 0.2


func _process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		queue_free()


## Treme a câmera do jogador local conforme a distância até o impacto (também em quem só vê o martelo de outro).
static func shake_local(center: Vector3, cfg: HammerConfig) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null or cfg.shake_strength <= 0.0:
		return
	var lp = tree.current_scene.get("player")
	if lp == null or not is_instance_valid(lp) or not lp.is_inside_tree() or not lp.has_method("add_shake"):
		return
	var d := Vector2(lp.global_position.x - center.x, lp.global_position.z - center.z).length()
	var f := 1.0 - clampf(d / cfg.shake_range, 0.0, 1.0)
	if f > 0.0:
		lp.add_shake(cfg.shake_strength * cfg.explosion_intensity * f * f * (3.0 - 2.0 * f))


# ------------------------------------------------------------------- onda de choque (sprite sheet)
func _spawn_sheet() -> void:
	if config.shock_sheet_scale <= 0.0:
		return
	var s: HammerSheet = SHEET.instantiate()
	s.name = "Shock"
	s.material_override = SHEET_MAT
	add_child(s)
	var size := config.radius * config.shock_sheet_scale
	s.scale = Vector3.ONE * size
	# o ponto do impacto desenhado (SHEET_GROUND_V) fica sobre o ponto do impacto de verdade
	s.position = Vector3(0.0, (SHEET_GROUND_V - 0.5) * size, 0.0)
	s.set_param("soft_edge", 1.0)   # sem a borda do quad
	s.intensity = clampf(0.95 * config.explosion_intensity, 0.0, 1.6)
	var dur := config.shock_sheet_time
	s.play(SHEET_FRAMES, dur)
	var tw := s.create_tween()
	tw.tween_interval(dur * 0.62)
	tw.tween_property(s, "intensity", 0.0, dur * 0.38).set_ease(Tween.EASE_IN)
	tw.tween_callback(s.queue_free)


# ------------------------------------------------------------------- rachaduras projetadas (Decal)
func _spawn_decals() -> void:
	var r := config.radius * config.crack_decal_scale
	if r <= 0.0:
		return
	_spawn_decal(Vector3.ZERO, r, 0.0, 1.0)
	# menores, na onda que corre pelo chão (mesma velocidade das crateras)
	for i in SIDE_DECALS:
		var a := TAU * (float(i) + _rng.randf_range(-0.3, 0.3)) / SIDE_DECALS
		var dist := config.radius * _rng.randf_range(0.5, 0.8)
		var off := Vector3(cos(a), 0.0, sin(a)) * dist
		_spawn_decal(off, r * _rng.randf_range(0.32, 0.45), dist / config.crater_wave_speed, 0.7)


func _spawn_decal(offset: Vector3, half: float, delay: float, energy: float) -> void:
	_crack_textures()
	var d := Decal.new()
	d.name = "CrackDecal"
	d.texture_albedo = _crack_albedo
	d.texture_emission = _crack_emission
	d.albedo_mix = 1.0
	d.emission_energy = 0.0
	d.upper_fade = 0.35
	d.lower_fade = 0.35
	d.normal_fade = 0.55        # não pinta paredes nem o lado dos monstros
	d.cull_mask = 1             # só a camada do cenário
	d.position = offset
	d.rotation.y = _rng.randf() * TAU
	var full := Vector3(half * 2.0, DECAL_HEIGHT, half * 2.0)
	d.size = Vector3(full.x * 0.15, DECAL_HEIGHT, full.z * 0.15)
	d.visible = false
	add_child(d)
	var life := config.crack_decal_life
	var peak := 5.0 * energy * config.explosion_intensity
	var tw := d.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_callback(d.show)
	# abrem num estalo, com as rachaduras em brasa
	tw.tween_property(d, "size", full, DECAL_GROW).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(d, "emission_energy", peak, DECAL_GROW * 0.6)
	# as brasas esfriam devagar...
	tw.tween_property(d, "emission_energy", 0.0, life * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# ...e a marca some no fim
	tw.parallel().tween_property(d, "modulate:a", 0.0, life * 0.4).set_delay(life * 0.5 - DECAL_GROW)
	tw.tween_callback(d.queue_free)


## Rachaduras radiais com ramificações, do miolo até a borda (alfa = rachadura e chão queimado; emissão = brasa
## no fundo das rachaduras). Geradas uma vez com semente fixa: cada decal gira para não repetir.
static func _crack_textures() -> void:
	if _crack_albedo != null and _crack_emission != null:
		return
	var n := CRACK_TEX_SIZE
	var core := PackedFloat32Array()
	var halo := PackedFloat32Array()
	core.resize(n * n)
	halo.resize(n * n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var c := Vector2(n, n) * 0.5
	var main := 15
	for i in main:
		var a0 := TAU * (float(i) + rng.randf_range(-0.35, 0.35)) / main
		var reach := n * 0.5 * rng.randf_range(0.72, 0.97)
		_crack_walk(core, halo, n, rng, c + Vector2.from_angle(a0) * n * 0.03, a0, reach, 3.4, 1)
	# bytes direto (set_pixel em 256 x 256 custava um engasgo visível)
	var ab := PackedByteArray()
	var eb := PackedByteArray()
	ab.resize(n * n * 4)
	eb.resize(n * n * 4)
	var c_mid := Color(1.0, 0.85, 0.45)
	var c_out := Color(1.0, 0.38, 0.06)
	var c_tip := Color(0.7, 0.12, 0.02)
	for y in n:
		for x in n:
			var i := y * n + x
			var o := i * 4
			var rr := Vector2(x + 0.5 - c.x, y + 0.5 - c.y).length() / (n * 0.5)
			var edge := 1.0 - smoothstep(0.85, 1.0, rr)
			var scorch := (1.0 - smoothstep(0.0, 0.42, rr)) * 0.7
			ab[o] = 15
			ab[o + 1] = 10
			ab[o + 2] = 8
			ab[o + 3] = int(clampf(maxf(maxf(core[i], halo[i] * 0.75), scorch) * edge, 0.0, 1.0) * 255.0)
			# brasa: amarelo-branco perto do centro, laranja e depois vermelho na ponta das rachaduras
			var hot := core[i] * edge
			if hot > 0.0:
				var col := c_mid.lerp(c_out, smoothstep(0.1, 0.55, rr)).lerp(c_tip, smoothstep(0.55, 1.0, rr))
				eb[o] = int(col.r * hot * 255.0)
				eb[o + 1] = int(col.g * hot * 255.0)
				eb[o + 2] = int(col.b * hot * 255.0)
			eb[o + 3] = 255
	var albedo := Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, ab)
	var emission := Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, eb)
	albedo.generate_mipmaps()
	emission.generate_mipmaps()
	_crack_albedo = ImageTexture.create_from_image(albedo)
	_crack_emission = ImageTexture.create_from_image(emission)


## Uma rachadura: anda para fora do centro com desvio (sem sair muito da direção radial), afinando, e abre
## ramificações curtas pelo caminho.
static func _crack_walk(core: PackedFloat32Array, halo: PackedFloat32Array, n: int, rng: RandomNumberGenerator,
		from: Vector2, a0: float, reach: float, width: float, depth: int) -> void:
	var p := from
	var a := a0
	var walked := 0.0
	var step := 1.4
	while walked < reach:
		a = lerp_angle(a + rng.randf_range(-0.45, 0.45), a0, 0.12)
		p += Vector2.from_angle(a) * step
		walked += step
		var w := lerpf(width, 0.55, walked / reach)
		_crack_stamp(core, halo, n, p, w)
		if depth > 0 and walked > reach * 0.2 and rng.randf() < 0.022:
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			_crack_walk(core, halo, n, rng, p, a + side * rng.randf_range(0.35, 0.8), (reach - walked) * rng.randf_range(0.3, 0.6), w * 0.7, depth - 1)


static func _crack_stamp(core: PackedFloat32Array, halo: PackedFloat32Array, n: int, p: Vector2, w: float) -> void:
	var h := w + 3.0
	for y in range(maxi(0, int(p.y - h)), mini(n, int(p.y + h) + 1)):
		for x in range(maxi(0, int(p.x - h)), mini(n, int(p.x + h) + 1)):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(p)
			var i := y * n + x
			core[i] = maxf(core[i], clampf(w + 0.5 - d, 0.0, 1.0))
			halo[i] = maxf(halo[i], clampf((h - d) / 3.0, 0.0, 1.0))


# ------------------------------------------------------------------- detritos, brasas e fumaça (GPUParticles3D)
func _spawn_particles(kind: String, mesh: Mesh, amount: int, lifetime: float) -> void:
	if amount <= 0:
		return
	var p := GPUParticles3D.new()
	p.name = kind.capitalize()
	p.process_material = _process_material(kind, config)
	p.draw_pass_1 = mesh
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.92 if kind != "smoke" else 0.75
	p.randomness = 0.4
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if kind != "debris" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var r := config.radius
	p.visibility_aabb = AABB(Vector3(-r * 1.5, -2.0, -r * 1.5), Vector3(r * 3.0, 16.0, r * 3.0))
	p.position = Vector3(0.0, 0.25, 0.0)
	add_child(p)
	p.emitting = true


static func _process_material(kind: String, cfg: HammerConfig) -> ParticleProcessMaterial:
	var key := "%s/%.2f/%.2f" % [kind, cfg.radius, cfg.explosion_intensity]
	if _process_mats.has(key):
		return _process_mats[key]
	if _process_mats.size() > 32:
		_process_mats.clear()
	var r := cfg.radius
	var k := maxf(cfg.explosion_intensity, 0.3)
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	match kind:
		"debris":
			# pedras arrancadas do chão: sobem rápido, giram e caem
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			m.emission_sphere_radius = 0.9
			m.spread = 55.0
			m.initial_velocity_min = 6.0 * sqrt(k)
			m.initial_velocity_max = 15.0 * sqrt(k)
			m.radial_velocity_min = 1.0
			m.radial_velocity_max = 4.0
			m.gravity = Vector3(0.0, -26.0, 0.0)
			m.angle_min = -180.0
			m.angle_max = 180.0
			m.angular_velocity_min = -540.0
			m.angular_velocity_max = 540.0
			m.particle_flag_rotate_y = true
			m.scale_min = 0.4
			m.scale_max = 1.4
			m.scale_curve = _curve_tex([Vector2(0.0, 1.0), Vector2(0.8, 0.9), Vector2(1.0, 0.0)])
		"embers":
			# brasas: espirram alto, perdem força e ficam boiando, apagando de amarelo para vermelho
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			m.emission_sphere_radius = 1.2
			m.spread = 70.0
			m.initial_velocity_min = 4.0 * k
			m.initial_velocity_max = 14.0 * k
			m.radial_velocity_min = 2.0
			m.radial_velocity_max = 6.0
			m.gravity = Vector3(0.0, -4.5, 0.0)
			m.damping_min = 2.5
			m.damping_max = 5.0
			m.turbulence_enabled = true
			m.turbulence_noise_strength = 1.4
			m.turbulence_noise_scale = 4.0
			m.turbulence_influence_min = 0.05
			m.turbulence_influence_max = 0.2
			m.scale_min = 0.5
			m.scale_max = 1.5
			m.scale_curve = _curve_tex([Vector2(0.0, 1.0), Vector2(0.7, 0.7), Vector2(1.0, 0.0)])
			m.color_ramp = _ramp_tex([Color(1.0, 0.95, 0.7, 1.0), Color(1.0, 0.6, 0.15, 1.0), Color(0.8, 0.15, 0.03, 0.8), Color(0.3, 0.05, 0.0, 0.0)],
				[0.0, 0.25, 0.7, 1.0])
		"smoke":
			# fumaça escura saindo do anel do choque, subindo e se abrindo
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			m.emission_ring_axis = Vector3.UP
			m.emission_ring_radius = r * 0.45
			m.emission_ring_inner_radius = r * 0.1
			m.emission_ring_height = 0.4
			m.spread = 35.0
			m.initial_velocity_min = 1.2
			m.initial_velocity_max = 3.2
			m.radial_velocity_min = 1.0
			m.radial_velocity_max = 3.0
			m.gravity = Vector3(0.0, 0.7, 0.0)
			m.damping_min = 0.6
			m.damping_max = 1.2
			m.angle_min = -180.0
			m.angle_max = 180.0
			m.angular_velocity_min = -25.0
			m.angular_velocity_max = 25.0
			m.scale_min = 0.8 * sqrt(r / 4.5)
			m.scale_max = 1.6 * sqrt(r / 4.5)
			m.scale_curve = _curve_tex([Vector2(0.0, 0.45), Vector2(0.4, 1.0), Vector2(1.0, 1.35)])
			m.color_ramp = _ramp_tex([Color(0.22, 0.19, 0.17, 0.0), Color(0.24, 0.2, 0.18, 0.6), Color(0.3, 0.27, 0.25, 0.4), Color(0.35, 0.32, 0.3, 0.0)],
				[0.0, 0.12, 0.55, 1.0])
	_process_mats[key] = m
	return m


static func _curve_tex(points: Array) -> CurveTexture:
	var c := Curve.new()
	for p: Vector2 in points:
		c.add_point(p)
	var t := CurveTexture.new()
	t.curve = c
	return t


static func _ramp_tex(colors: Array, offsets: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.colors = PackedColorArray(colors)
	g.offsets = PackedFloat32Array(offsets)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


func _stone_mesh() -> Mesh:
	var b := BoxMesh.new()
	b.size = Vector3(0.2, 0.15, 0.17)
	b.material = STONE_MAT
	return b


func _quad(size: float, mat: Material) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = mat
	return q


# ------------------------------------------------------------------- clarão das brasas
func _spawn_light(k: float) -> void:
	var l := OmniLight3D.new()
	l.name = "Light"
	l.light_color = EMBER_COLOR
	l.omni_range = config.radius * 1.6
	l.shadow_enabled = false
	l.position = Vector3(0.0, 1.2, 0.0)
	l.light_energy = 0.0
	add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 4.5 * k, 0.05)
	tw.tween_property(l, "light_energy", 0.0, 1.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_callback(l.queue_free)
