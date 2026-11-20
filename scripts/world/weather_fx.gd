class_name WeatherFX
extends Node3D
## Desenha o clima do autoload Weather na cena (Valdoria e praça): chuva com respingos, neve,
## folhas e rajadas de vento (partículas que seguem a câmera), céu nublado, neblina, som de chuva e
## de vento, e publica as globais de shader que o chão, o capim e os modelos leem (poças, neve
## acumulada, capim vergando). Também desenha a estação: no outono as copas ganham tons de fogo, a grama
## doura, folhas caem e cobrem o chão e a luz fica mais quente (global `season_autumn`). Criar depois de WorldLighting.build (lê o ambiente e o sol da cena).
## Só visual: não existe no servidor dedicado.

const OVERLAY_SHADER := preload("res://assets/shaders/weather_overlay.gdshader")
const STREAK_SHADER := preload("res://assets/shaders/weather_streak.gdshader")
const TREE_SHADER := preload("res://assets/shaders/tree_wind.gdshader")
const WIND_LINES_SHADER := preload("res://assets/shaders/wind_lines.gdshader")
const MESSAGES := [
	"O tempo abre: o sol volta a brilhar.",
	"Nuvens carregadas: começa a chover.",
	"Esfria de repente: começa a nevar.",
	"O vento aperta: rajadas fortes!",
]
const SEASON_MESSAGES := [
	"A primavera chegou: tudo volta a florescer.",
	"O verão chegou: dias longos e quentes.",
	"O outono chegou: as folhas ganham tons de fogo.",
	"O inverno chegou: o frio se instala em Valdoria.",
]
const RATE := 22050

var _env: Environment
var _sky: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _rim: DirectionalLight3D
var _base := {}

var _rain: GPUParticles3D
var _rain_pm: ParticleProcessMaterial
var _splash: GPUParticles3D
var _snow: GPUParticles3D
var _snow_pm: ParticleProcessMaterial
var _leaves: GPUParticles3D
var _leaves_pm: ParticleProcessMaterial
var _fall: GPUParticles3D
var _fall_pm: ParticleProcessMaterial
var _streaks: GPUParticles3D
var _streaks_pm: ParticleProcessMaterial
var _lines: GPUParticles3D
var _lines_pm: ShaderMaterial
var _dust: GPUParticles3D
var _dust_pm: ParticleProcessMaterial
var _collision: GPUParticlesCollisionHeightField3D
# bioma (BiomeRules): o mapa onde a câmera está troca céu, névoa, sol e clima; cinza e brasas no vulcão,
# vaga-lumes no pântano
var _region := ""
var _bio := {}
var _ash: GPUParticles3D
var _ash_pm: ParticleProcessMaterial
var _embers: GPUParticles3D
var _flies: GPUParticles3D
var _cave: GPUParticles3D   # dungeon: poeira pairando devagar na luz das tochas
var _hero_light: OmniLight3D   # dungeon: brilho fraco e curto em volta do herói (vê-se perto, o resto é escuro)

var _rain_audio: AudioStreamPlayer
var _wind_audio: AudioStreamPlayer

var _overlay: ShaderMaterial
var _noise_tex: NoiseTexture2D
var _trees_done := false
var _overlaid := {}   # instance_id -> GeometryInstance3D
var _overlay_on := false
var _rescan := 0.0
var _lp := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	Weather.fx = self
	Weather.changed.connect(_on_changed)
	Weather.season_changed.connect(_on_season_changed)
	_find_lighting()
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.noise = noise
	_noise_tex = tex
	_overlay = ShaderMaterial.new()
	_overlay.shader = OVERLAY_SHADER
	_overlay.set_shader_parameter("noise_tex", tex)
	_build_particles()
	_build_audio()
	# o primeiro _apply fica para o primeiro quadro: a cena já terminou de montar os props


func _exit_tree() -> void:
	if Weather.fx == self:
		Weather.fx = null
	# fora de Valdoria/praça o chão e o capim voltam ao normal
	for k in ["weather_wet", "weather_snow", "weather_rain", "weather_wind", "weather_phase", "season_autumn"]:
		RenderingServer.global_shader_parameter_set(k, 0.0)


func _on_changed(kind: int) -> void:
	Game.notify.emit(MESSAGES[kind], Color(0.7, 0.85, 1.0))


func _on_season_changed(kind: int) -> void:
	Game.notify.emit(SEASON_MESSAGES[kind], SeasonRules.COLORS[kind])


# ================================================================ luz
func _find_lighting() -> void:
	for c in get_parent().get_children():
		if c is WorldEnvironment and _env == null:
			_env = c.environment
		elif c is DirectionalLight3D:
			if c.shadow_enabled and _sun == null:
				_sun = c
			elif _rim == null:
				_rim = c
	if _env != null:
		_base.fog_density = _env.fog_density
		_base.fog_color = _env.fog_light_color
		_base.ambient = _env.ambient_light_energy
		_base.saturation = _env.adjustment_saturation
		if _env.sky != null and _env.sky.sky_material is ProceduralSkyMaterial:
			_sky = _env.sky.sky_material
			_base.sky_top = _sky.sky_top_color
			_base.sky_hz = _sky.sky_horizon_color
			_base.ground_hz = _sky.ground_horizon_color
			_base.sky_energy = _sky.energy_multiplier
	if _sun != null:
		_base.sun = _sun.light_energy
		_base.sun_color = _sun.light_color
	if _rim != null:
		_base.rim = _rim.light_energy


## Base da luz com o bioma do mapa atual por cima (o Vale e a Arena: a base de sempre).
func _eff_base() -> Dictionary:
	if _bio.is_empty() or not _bio.has("sky_top"):
		return _base
	var b := _base.duplicate()
	b.fog_color = _bio.fog
	b.fog_density = float(_bio.fog_density) * (0.6 if ToonLook.enabled() else 1.0)
	b.sky_top = _bio.sky_top
	b.sky_hz = _bio.sky_hz
	b.ground_hz = _bio.ground_hz
	if b.has("sun"):
		b.sun = float(_base.sun) * float(_bio.sun)
		b.sun_color = _bio.sun_color
	if b.has("ambient"):
		b.ambient = float(_base.ambient) * float(_bio.ambient)
		b.saturation = float(_base.saturation) * float(_bio.saturation)
	if b.has("rim"):
		b.rim = float(_base.rim) * float(_bio.get("rim", 1.0))
	return b


func _apply_light(s: Dictionary) -> void:
	var b := _eff_base()   # a base já com o bioma do mapa atual
	var cloud: float = s.cloud
	var snow: float = maxf(s.snow, s.cover * 0.5)
	var rain: float = s.rain
	var wind: float = s.wind
	var dust := clampf((wind - 0.3) / 0.7, 0.0, 1.0) * (1.0 - cloud)
	# Estilo desenhado: tempo fechado mais brando. A sombra em dois tons depende do sol; com ele a 38% e
	# a névoa cheia, chuva e neve viravam um cinza só (docs/ESTILO_TOON.md, "Luz e pós-processo").
	var toon := ToonLook.enabled()
	var sun_loss := 0.45 if toon else 0.62
	var shadow_loss := 0.35 if toon else 0.6
	var fog_gain := 0.55 if toon else 1.0
	var amb_gain := 0.5 if toon else 1.0
	var sat_loss := 0.15 if toon else 0.25
	# outono: sol mais baixo e dourado, névoa morna
	var autumn := (Weather.autumn if _bio.get("autumn", true) else 0.0) * (1.0 - snow)
	if _sun != null:
		_sun.light_energy = b.sun * (1.0 - sun_loss * cloud)
		_sun.light_color = (b.sun_color as Color).lerp(Color(1.0, 0.84, 0.62), autumn * 0.35 * (1.0 - cloud)) 				.lerp(Color(0.86, 0.9, 1.0), cloud * 0.8)
		_sun.shadow_opacity = 1.0 - shadow_loss * cloud
	if _rim != null:
		_rim.light_energy = b.rim * (1.0 - 0.5 * cloud)
	if _env == null:
		return
	var grey := Color(0.6, 0.63, 0.67)
	var white := Color(0.84, 0.87, 0.92)
	var dusty := Color(0.8, 0.76, 0.66)
	var fog: Color = (b.fog_color as Color).lerp(Color(0.88, 0.74, 0.55), autumn * 0.3).lerp(grey, cloud).lerp(white, snow * 0.8).lerp(dusty, dust * 0.6)
	_env.fog_light_color = fog
	_env.fog_density = b.fog_density + (0.009 * rain + 0.009 * s.snow + 0.004 * dust) * fog_gain
	_env.ambient_light_energy = b.ambient * (1.0 + (0.12 * cloud + 0.15 * snow) * amb_gain)
	_env.adjustment_saturation = b.saturation - sat_loss * cloud
	if _sky != null:
		_sky.sky_top_color = (b.sky_top as Color).lerp(Color(0.45, 0.5, 0.56), cloud).lerp(Color(0.7, 0.74, 0.8), snow * cloud * 0.6)
		var hz: Color = (b.sky_hz as Color).lerp(Color(0.62, 0.65, 0.69), cloud).lerp(white, snow * 0.6).lerp(dusty, dust * 0.4)
		_sky.sky_horizon_color = hz
		_sky.ground_horizon_color = (b.ground_hz as Color).lerp(hz, maxf(cloud, dust))
		_sky.energy_multiplier = b.sky_energy * (1.0 - 0.25 * cloud * (1.0 - snow))


# ================================================================ partículas
func _build_particles() -> void:
	# a chuva e a neve param no que estiver por cima (telhados, copas) e somem ao tocar o chão
	_collision = GPUParticlesCollisionHeightField3D.new()
	_collision.size = Vector3(56, 50, 56)
	_collision.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_512
	_collision.follow_camera_enabled = true
	_collision.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	add_child(_collision)

	# respingos: nascem onde cada gota bate (sub-emissor da chuva)
	_splash = GPUParticles3D.new()
	_splash.amount = 4000
	_splash.lifetime = 0.3
	_splash.local_coords = false
	var spm := ParticleProcessMaterial.new()
	spm.direction = Vector3.UP
	spm.spread = 55.0
	spm.initial_velocity_min = 0.8
	spm.initial_velocity_max = 2.0
	spm.gravity = Vector3(0, -9.8, 0)
	spm.scale_min = 0.5
	spm.scale_max = 1.0
	spm.color_ramp = _fade_ramp(0.0, 0.0)
	_splash.process_material = spm
	_splash.draw_pass_1 = _dot_mesh(0.045, Color(0.85, 0.9, 1.0, 0.55))
	_add_particles(_splash)
	_splash.emitting = true   # sub-emissor: só solta partículas quando uma gota bate

	_rain = GPUParticles3D.new()
	_rain.amount = 6000
	_rain.lifetime = 1.4
	_rain.local_coords = false
	_rain.collision_base_size = 0.02
	_rain_pm = ParticleProcessMaterial.new()
	_rain_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_pm.emission_box_extents = Vector3(20, 1, 20)
	_rain_pm.direction = Vector3.DOWN
	_rain_pm.spread = 1.5
	_rain_pm.initial_velocity_min = 22.0
	_rain_pm.initial_velocity_max = 26.0
	_rain_pm.gravity = Vector3(0, -6, 0)
	_rain_pm.particle_flag_align_y = true
	_rain_pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_rain_pm.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_AT_COLLISION
	_rain_pm.sub_emitter_amount_at_collision = 1
	_rain.process_material = _rain_pm
	_rain.draw_pass_1 = _streak_mesh(Color(0.72, 0.78, 0.88, 0.32), 0.011, 0.6)
	_add_particles(_rain)
	_rain.sub_emitter = _rain.get_path_to(_splash)

	_snow = GPUParticles3D.new()
	_snow.amount = 5000
	_snow.lifetime = 9.0
	_snow.preprocess = 6.0
	_snow.local_coords = false
	_snow.collision_base_size = 0.02
	_snow_pm = ParticleProcessMaterial.new()
	_snow_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_snow_pm.emission_box_extents = Vector3(22, 1, 22)
	_snow_pm.direction = Vector3.DOWN
	_snow_pm.spread = 20.0
	_snow_pm.initial_velocity_min = 1.0
	_snow_pm.initial_velocity_max = 1.8
	_snow_pm.gravity = Vector3(0, -0.5, 0)
	_snow_pm.scale_min = 0.6
	_snow_pm.scale_max = 1.4
	_snow_pm.turbulence_enabled = true
	_snow_pm.turbulence_noise_strength = 1.5
	_snow_pm.turbulence_noise_scale = 6.0
	_snow_pm.turbulence_influence_min = 0.04
	_snow_pm.turbulence_influence_max = 0.12
	_snow_pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_snow.process_material = _snow_pm
	_snow.draw_pass_1 = _dot_mesh(0.1, Color(1, 1, 1, 0.95))
	_add_particles(_snow)

	# vulcão: cinza caindo devagar (flocos escuros) e brasas subindo do chão
	_ash = GPUParticles3D.new()
	_ash.amount = 1800
	_ash.lifetime = 10.0
	_ash.preprocess = 6.0
	_ash.local_coords = false
	_ash_pm = ParticleProcessMaterial.new()
	_ash_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_ash_pm.emission_box_extents = Vector3(22, 1, 22)
	_ash_pm.direction = Vector3.DOWN
	_ash_pm.spread = 30.0
	_ash_pm.initial_velocity_min = 0.5
	_ash_pm.initial_velocity_max = 1.1
	_ash_pm.scale_min = 0.6
	_ash_pm.scale_max = 1.3
	_ash_pm.turbulence_enabled = true
	_ash_pm.turbulence_noise_strength = 1.2
	_ash_pm.turbulence_noise_scale = 5.0
	_ash_pm.turbulence_influence_min = 0.05
	_ash_pm.turbulence_influence_max = 0.14
	_ash.process_material = _ash_pm
	_ash.draw_pass_1 = _dot_mesh(0.085, Color(0.24, 0.22, 0.22, 0.9))
	_add_particles(_ash)
	_embers = GPUParticles3D.new()
	_embers.amount = 160
	_embers.lifetime = 4.0
	_embers.local_coords = false
	var epm := ParticleProcessMaterial.new()
	epm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	epm.emission_box_extents = Vector3(16, 0.5, 16)
	epm.direction = Vector3.UP
	epm.spread = 25.0
	epm.initial_velocity_min = 0.8
	epm.initial_velocity_max = 2.0
	epm.gravity = Vector3(0, 0.25, 0)
	epm.scale_min = 0.5
	epm.scale_max = 1.2
	epm.turbulence_enabled = true
	epm.turbulence_noise_strength = 2.0
	epm.turbulence_influence_min = 0.1
	epm.turbulence_influence_max = 0.25
	epm.color_ramp = _fade_ramp(0.1, 0.6)
	_embers.process_material = epm
	_embers.draw_pass_1 = _dot_mesh(0.07, Color(1.0, 0.55, 0.15, 1.0) * 3.0)
	_add_particles(_embers)
	# pântano: vaga-lumes pairando baixo, piscando devagar
	_flies = GPUParticles3D.new()
	_flies.amount = 90
	_flies.lifetime = 6.0
	_flies.preprocess = 4.0
	_flies.local_coords = false
	var fpm := ParticleProcessMaterial.new()
	fpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	fpm.emission_box_extents = Vector3(16, 1.2, 16)
	fpm.spread = 180.0
	fpm.initial_velocity_min = 0.1
	fpm.initial_velocity_max = 0.4
	fpm.gravity = Vector3.ZERO
	fpm.turbulence_enabled = true
	fpm.turbulence_noise_strength = 1.0
	fpm.turbulence_noise_scale = 3.0
	fpm.turbulence_influence_min = 0.05
	fpm.turbulence_influence_max = 0.15
	fpm.color_ramp = _fade_ramp(0.3, 0.6)
	_flies.process_material = fpm
	_flies.draw_pass_1 = _dot_mesh(0.09, Color(0.75, 1.0, 0.45, 1.0) * 2.5)
	_add_particles(_flies)
	_cave = GPUParticles3D.new()
	_cave.amount = 260
	_cave.lifetime = 8.0
	_cave.preprocess = 5.0
	_cave.local_coords = false
	var cpm := ParticleProcessMaterial.new()
	cpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	cpm.emission_box_extents = Vector3(10, 2.5, 10)
	cpm.spread = 180.0
	cpm.initial_velocity_min = 0.02
	cpm.initial_velocity_max = 0.15
	cpm.gravity = Vector3(0, -0.02, 0)
	cpm.turbulence_enabled = true
	cpm.turbulence_noise_strength = 0.6
	cpm.turbulence_noise_scale = 4.0
	cpm.turbulence_influence_min = 0.02
	cpm.turbulence_influence_max = 0.06
	cpm.color_ramp = _fade_ramp(0.25, 0.7)
	_cave.process_material = cpm
	_cave.draw_pass_1 = _dot_mesh(0.035, Color(0.75, 0.7, 0.62, 0.55))
	_add_particles(_cave)

	# vento forte: folhas rodopiando e riscos de ar passando rápido
	_leaves = GPUParticles3D.new()
	_leaves.amount = 320
	_leaves.lifetime = 3.5
	_leaves.local_coords = false
	_leaves_pm = ParticleProcessMaterial.new()
	_leaves_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_leaves_pm.emission_box_extents = Vector3(18, 3, 18)
	_leaves_pm.spread = 18.0
	_leaves_pm.initial_velocity_min = 8.0
	_leaves_pm.initial_velocity_max = 14.0
	_leaves_pm.gravity = Vector3(0, -1.5, 0)
	_leaves_pm.angle_min = -180.0
	_leaves_pm.angle_max = 180.0
	_leaves_pm.angular_velocity_min = -420.0
	_leaves_pm.angular_velocity_max = 420.0
	_leaves_pm.scale_min = 0.6
	_leaves_pm.scale_max = 1.2
	_leaves_pm.turbulence_enabled = true
	_leaves_pm.turbulence_noise_strength = 3.0
	_leaves_pm.turbulence_influence_min = 0.08
	_leaves_pm.turbulence_influence_max = 0.22
	var lg := Gradient.new()
	lg.set_color(0, Color(0.35, 0.5, 0.16))
	lg.set_color(1, Color(0.62, 0.4, 0.14))
	lg.add_point(0.5, Color(0.8, 0.66, 0.2))
	var lgt := GradientTexture1D.new()
	lgt.gradient = lg
	_leaves_pm.color_initial_ramp = lgt
	_leaves_pm.color_ramp = _fade_ramp(0.1, 0.8)
	_leaves.process_material = _leaves_pm
	_leaves.draw_pass_1 = _leaf_mesh()
	_add_particles(_leaves)

	# outono: folhas soltas caindo devagar, balançando, em volta da câmera
	_fall = GPUParticles3D.new()
	_fall.amount = 260
	_fall.lifetime = 8.0
	_fall.preprocess = 6.0
	_fall.local_coords = false
	_fall.collision_base_size = 0.05
	_fall_pm = ParticleProcessMaterial.new()
	_fall_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_fall_pm.emission_box_extents = Vector3(17, 2, 17)
	_fall_pm.direction = Vector3.DOWN
	_fall_pm.spread = 35.0
	_fall_pm.initial_velocity_min = 0.4
	_fall_pm.initial_velocity_max = 0.9
	_fall_pm.gravity = Vector3(0, -0.7, 0)
	_fall_pm.angle_min = -180.0
	_fall_pm.angle_max = 180.0
	_fall_pm.angular_velocity_min = -160.0
	_fall_pm.angular_velocity_max = 160.0
	_fall_pm.scale_min = 0.9
	_fall_pm.scale_max = 1.5
	_fall_pm.turbulence_enabled = true
	_fall_pm.turbulence_noise_strength = 2.0
	_fall_pm.turbulence_noise_scale = 4.0
	_fall_pm.turbulence_influence_min = 0.05
	_fall_pm.turbulence_influence_max = 0.14
	_fall_pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	var fg := Gradient.new()
	fg.set_color(0, Color(0.72, 0.16, 0.06))
	fg.set_color(1, Color(0.45, 0.24, 0.1))
	fg.add_point(0.35, Color(0.9, 0.42, 0.08))
	fg.add_point(0.7, Color(0.92, 0.68, 0.15))
	var fgt := GradientTexture1D.new()
	fgt.gradient = fg
	_fall_pm.color_initial_ramp = fgt
	_fall_pm.color_ramp = _fade_ramp(0.08, 0.85)
	_fall.process_material = _fall_pm
	_fall.draw_pass_1 = _leaf_mesh()
	_add_particles(_fall)

	_streaks = GPUParticles3D.new()
	_streaks.amount = 160
	_streaks.lifetime = 1.2
	_streaks.local_coords = false
	_streaks_pm = ParticleProcessMaterial.new()
	_streaks_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_streaks_pm.emission_box_extents = Vector3(18, 4, 18)
	_streaks_pm.spread = 3.0
	_streaks_pm.initial_velocity_min = 22.0
	_streaks_pm.initial_velocity_max = 30.0
	_streaks_pm.gravity = Vector3.ZERO
	_streaks_pm.particle_flag_align_y = true
	_streaks_pm.color_ramp = _fade_ramp(0.3, 0.6)
	_streaks.process_material = _streaks_pm
	_streaks.draw_pass_1 = _streak_mesh(Color(1, 1, 1, 0.26), 0.022, 3.6)
	_add_particles(_streaks)

	# linhas do vento: rastros finos e brancos que ondulam e às vezes dão um laço no ar
	_lines = GPUParticles3D.new()
	_lines.amount = 44
	_lines.lifetime = 1.8
	_lines.local_coords = false
	_lines.trail_enabled = true
	_lines.trail_lifetime = 0.7
	_lines_pm = ShaderMaterial.new()
	_lines_pm.shader = WIND_LINES_SHADER
	_lines.process_material = _lines_pm
	var ribbon := RibbonTrailMesh.new()
	ribbon.shape = RibbonTrailMesh.SHAPE_FLAT
	ribbon.size = 0.045
	ribbon.sections = 24
	ribbon.section_segments = 1
	var taper := Curve.new()   # fina nas pontas, mais cheia no meio
	taper.add_point(Vector2(0.0, 0.15))
	taper.add_point(Vector2(0.4, 1.0))
	taper.add_point(Vector2(1.0, 0.3))
	ribbon.curve = taper
	var lm := StandardMaterial3D.new()
	lm.use_particle_trails = true
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lm.cull_mode = BaseMaterial3D.CULL_DISABLED
	lm.vertex_color_use_as_albedo = true
	lm.albedo_color = Color(1, 1, 1, 0.95)
	lm.albedo_texture = _trail_tex()
	lm.disable_receive_shadows = true
	lm.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	lm.distance_fade_min_distance = 2.0
	lm.distance_fade_max_distance = 5.0
	ribbon.material = lm
	_lines.draw_pass_1 = ribbon
	_add_particles(_lines)

	# poeira levantada: nuvens baixas e largas varrendo o chão
	_dust = GPUParticles3D.new()
	_dust.amount = 45
	_dust.lifetime = 2.6
	_dust.local_coords = false
	_dust_pm = ParticleProcessMaterial.new()
	_dust_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_dust_pm.emission_box_extents = Vector3(18, 0.4, 18)
	_dust_pm.spread = 8.0
	_dust_pm.initial_velocity_min = 9.0
	_dust_pm.initial_velocity_max = 14.0
	_dust_pm.gravity = Vector3(0, 0.3, 0)
	_dust_pm.scale_min = 0.7
	_dust_pm.scale_max = 1.6
	_dust_pm.angle_min = -180.0
	_dust_pm.angle_max = 180.0
	_dust_pm.angular_velocity_min = -40.0
	_dust_pm.angular_velocity_max = 40.0
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 1.3))
	var grow_t := CurveTexture.new()
	grow_t.curve = grow
	_dust_pm.scale_curve = grow_t
	_dust_pm.color_ramp = _fade_ramp(0.25, 0.55)
	_dust.process_material = _dust_pm
	var dm := _dot_mesh(2.8, Color(0.93, 0.89, 0.8, 0.22))
	var dmat := dm.material as StandardMaterial3D
	dmat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	dmat.distance_fade_min_distance = 1.5
	dmat.distance_fade_max_distance = 5.0
	_dust.draw_pass_1 = dm
	_add_particles(_dust)


func _add_particles(p: GPUParticles3D) -> void:
	p.top_level = true
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-40, -45, -40), Vector3(80, 70, 80))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)


## Rampa de alfa: aparece até `fade_in`, fica, some a partir de `fade_out` (frações da vida).
func _fade_ramp(fade_in: float, fade_out: float) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0 if fade_in > 0.0 else 1.0))
	g.set_color(1, Color(1, 1, 1, 0))
	if fade_in > 0.0:
		g.add_point(fade_in, Color(1, 1, 1, 1))
	if fade_out > 0.0:
		g.add_point(fade_out, Color(1, 1, 1, 1))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


func _streak_mesh(tint: Color, width: float, length_m: float) -> QuadMesh:
	var m := ShaderMaterial.new()
	m.shader = STREAK_SHADER
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("width", width)
	m.set_shader_parameter("length_m", length_m)
	var q := QuadMesh.new()
	q.material = m
	return q


func _round_tex(hard: bool) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	if hard:
		g.add_point(0.85, Color(1, 1, 1, 1))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 32
	t.height = 32
	return t


## Textura do rastro: some nas bordas da largura (UV.x) e na cauda (UV.y), linha macia.
func _trail_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.5, Color(1, 1, 1, 1))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(1, 0)
	t.width = 32
	t.height = 4
	return t


## Floco/gota redonda virada para a câmera.
func _dot_mesh(size: float, col: Color) -> QuadMesh:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = col
	m.albedo_texture = _round_tex(false)
	m.disable_receive_shadows = true
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = m
	return q


## Folha: oval com a cor da partícula, iluminada, girando no plano da tela.
func _leaf_mesh() -> QuadMesh:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _round_tex(true)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.9
	# rente à câmera a folha viraria um borrão: some aos poucos perto dela
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
	m.distance_fade_min_distance = 1.2
	m.distance_fade_max_distance = 3.5
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.07)
	q.material = m
	return q


func _update_particles(s: Dictionary, wind: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := cam.global_position
	var wd := Vector3(Weather.wind_dir.x, 0.0, Weather.wind_dir.y)
	# chuva: inclina com o vento; o emissor vai para o lado de onde o vento vem
	var slant := clampf(wind * 0.5, 0.0, 0.7)
	_rain_pm.direction = (Vector3.DOWN + wd * slant).normalized()
	_rain.global_position = c + Vector3(0, 13, 0) - wd * slant * 13.0
	_set_level(_rain, s.rain)
	_snow_pm.gravity = Vector3(0, -0.5, 0) + wd * wind * 2.5
	_snow.global_position = c + Vector3(0, 10, 0) - wd * wind * 12.0
	_set_level(_snow, s.snow)
	var strong := clampf((float(s.wind) - 0.35) / 0.65, 0.0, 1.0)
	_leaves_pm.direction = (wd + Vector3(0, 0.12, 0)).normalized()
	_leaves.global_position = c + Vector3(0, 1.5, 0) - wd * 14.0
	_set_level(_leaves, strong * (0.5 + 0.5 * Weather.gust) * (1.0 - s.snow) * (1.0 - s.rain * 0.6))
	_fall_pm.gravity = Vector3(0, -0.7, 0) + wd * (0.3 + wind * 2.0)
	_fall.global_position = c + Vector3(0, 9, 0) - wd * (2.0 + wind * 8.0)
	_set_level(_fall, (Weather.autumn if _bio.get("autumn", true) else 0.0) * (1.0 - s.snow) * (1.0 - s.rain * 0.5))
	_streaks_pm.direction = (wd + Vector3(0, 0.02, 0)).normalized()
	_streaks.global_position = c + Vector3(0, 2.0, 0) - wd * 13.0
	_set_level(_streaks, strong * (0.35 + 0.65 * Weather.gust))
	_lines_pm.set_shader_parameter("wind_dir", wd)
	_lines_pm.set_shader_parameter("camera_pos", c)
	_lines_pm.set_shader_parameter("speed", 7.5 + 4.0 * Weather.gust)
	# na altura do personagem (0,3 a ~5 m): as linhas passam na frente das casas e das árvores
	_lines.global_position = Vector3(c.x, maxf(2.2, c.y - 0.6), c.z) - wd * 8.0
	_set_level(_lines, strong * (0.45 + 0.55 * Weather.gust) * (1.0 - s.rain * 0.7))
	_dust_pm.direction = (wd + Vector3(0, 0.05, 0)).normalized()
	_dust.global_position = Vector3(c.x, maxf(0.6, c.y - 2.0), c.z) - wd * 12.0
	_set_level(_dust, strong * (0.4 + 0.6 * Weather.gust) * (1.0 - s.rain) * (1.0 - s.cover) * (1.0 - s.wet))
	var motes := str(_bio.get("motes", ""))
	_ash_pm.gravity = Vector3(0, -0.35, 0) + wd * wind * 1.5
	_ash.global_position = c + Vector3(0, 9, 0)
	_set_level(_ash, 0.75 if motes == "ash" else 0.0)
	_embers.global_position = Vector3(c.x, maxf(0.3, c.y - 3.0), c.z)
	_set_level(_embers, 0.6 if motes == "ash" else 0.0)
	_flies.global_position = Vector3(c.x, maxf(0.8, c.y - 2.0), c.z)
	_set_level(_flies, 1.0 if motes == "fireflies" else 0.0)
	_cave.global_position = c + Vector3(0, -1.5, 0)
	_set_level(_cave, 1.0 if motes == "dust" else 0.0)
	var w := get_tree().current_scene
	var hero: Node3D = w.get("player") if w != null else null
	if _hero_light == null:
		_hero_light = OmniLight3D.new()
		_hero_light.top_level = true
		_hero_light.light_color = Color(1.0, 0.82, 0.62)
		_hero_light.omni_range = 7.0
		_hero_light.omni_attenuation = 1.8
		_hero_light.shadow_enabled = false
		add_child(_hero_light)
	var under := motes == "dust" and hero != null
	_hero_light.visible = under
	if under:
		_hero_light.global_position = hero.global_position + Vector3(0, 2.6, 0)
		_hero_light.light_energy = 0.9


func _set_level(p: GPUParticles3D, level: float) -> void:
	p.amount_ratio = clampf(level, 0.0, 1.0)
	var on := level > 0.01
	if p.emitting != on:
		p.emitting = on


# ================================================================ som
func _build_audio() -> void:
	_rng.seed = 77
	_rain_audio = AudioStreamPlayer.new()
	_rain_audio.stream = _loop(2.0, func(t: float) -> float:
		var hiss := _noise(0.55) - _noise_slow(0.04)
		var drop := 0.0
		if _rng.randf() < 0.004:
			drop = _rng.randf_range(0.4, 0.9)
		return hiss * 0.7 + drop * sin(t * 2600.0))
	_rain_audio.volume_db = -80.0
	add_child(_rain_audio)
	_wind_audio = AudioStreamPlayer.new()
	_wind_audio.stream = _loop(3.0, func(_t: float) -> float: return _noise(0.018) * 9.0)
	_wind_audio.volume_db = -80.0
	add_child(_wind_audio)


var _lp2 := 0.0


func _noise(cut: float) -> float:
	_lp += (_rng.randf_range(-1.0, 1.0) - _lp) * cut
	return _lp


func _noise_slow(cut: float) -> float:
	_lp2 += (_rng.randf_range(-1.0, 1.0) - _lp2) * cut
	return _lp2


func _loop(dur: float, f: Callable) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	# emenda do loop: os últimos 10% se misturam com o começo para não estalar
	var vals := PackedFloat32Array()
	vals.resize(n)
	for i in n:
		vals[i] = f.call(float(i) / RATE)
	var xf := int(n * 0.1)
	for i in n:
		var v := vals[i]
		if i < xf:
			var a := float(i) / xf
			v = vals[i] * a + vals[n - xf + i] * (1.0 - a)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 26000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data.slice(0, (n - xf) * 2)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n - xf
	return w


func _set_volume(p: AudioStreamPlayer, level: float, max_db: float) -> void:
	if level < 0.01:
		if p.playing:
			p.stop()
		return
	p.volume_db = max_db + linear_to_db(level)
	if not p.playing:
		p.play()


# ================================================================ modelos (neve e umidade)
func _scan(n: Node) -> void:
	for c in n.get_children():
		if c == self or c is CharacterBody3D or c is GPUParticles3D or c is CanvasItem or c is CanvasLayer:
			continue
		if c is GeometryInstance3D and not _overlaid.has(c.get_instance_id()) and _wants_overlay(c):
			_overlaid[c.get_instance_id()] = c
			if _overlay_on:
				c.material_overlay = _overlay
		_scan(c)


func _wants_overlay(g: GeometryInstance3D) -> bool:
	# material toon (ToonLook) conta como material liso comum: é opaco e iluminado
	if g.material_overlay != null or (g.material_override is ShaderMaterial and not ToonLook.is_toon(g.material_override)):
		return false
	if g.material_override is BaseMaterial3D and not _opaque(g.material_override):
		return false
	var mesh: Mesh = null
	if g is MeshInstance3D:
		mesh = g.mesh
	elif g is MultiMeshInstance3D and g.multimesh != null:
		mesh = g.multimesh.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return false
	for i in mesh.get_surface_count():
		var m: Material = mesh.surface_get_material(i)
		if g is MeshInstance3D and g.get_surface_override_material(i) != null:
			m = g.get_surface_override_material(i)
		if (m is ShaderMaterial and not ToonLook.is_toon(m)) or (m is BaseMaterial3D and not _opaque(m)):
			return false
	return true


## Modelo com alguma superfície transparente ou sem luz (feixes, folhas recortadas) fica sem a
## camada: ela cobriria o recorte inteiro. Brilho (janelas, lanternas) não atrapalha.
func _opaque(m: BaseMaterial3D) -> bool:
	return m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
			and m.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED


func _update_overlay(s: Dictionary, delta: float) -> void:
	var need: bool = s.cover > 0.004 or s.wet > 0.01
	if need and not _overlay_on:
		_overlay_on = true
		_scan(get_parent())
		for id in _overlaid:
			var g: GeometryInstance3D = _overlaid[id]
			if is_instance_valid(g):
				g.material_overlay = _overlay
	elif not need and _overlay_on:
		_overlay_on = false
		for id in _overlaid:
			var g: GeometryInstance3D = _overlaid[id]
			if is_instance_valid(g) and g.material_overlay == _overlay:
				g.material_overlay = null
	if _overlay_on:
		# props que nasceram depois (plantas da horta, construções) também ganham a camada
		_rescan -= delta
		if _rescan <= 0.0:
			_rescan = 8.0
			for id in _overlaid.keys():
				if not is_instance_valid(_overlaid[id]):
					_overlaid.erase(id)
			_scan(get_parent())


# ================================================================ árvores
## Troca o material liso das árvores (GLB tree_*) pelo shader com balanço de vento e neve.
## Um ShaderMaterial por material original: todas as árvores da mesma espécie compartilham.
func _setup_trees(n: Node, cache: Dictionary) -> void:
	for c in n.get_children():
		if c == self or c is CharacterBody3D or c is CanvasItem or c is CanvasLayer:
			continue
		if c is MeshInstance3D and String(c.name).begins_with("Tree") and c.mesh != null 				and c.material_override == null and c.material_overlay == null:
			var mesh: Mesh = c.mesh
			var top := maxf(1.0, mesh.get_aabb().end.y)
			for i in mesh.get_surface_count():
				var m := mesh.surface_get_material(i) as BaseMaterial3D
				# o estilo toon pode ter passado antes: o shader da árvore (que também é toon) fica no lugar
				var ov: Material = c.get_surface_override_material(i)
				if m == null or (ov != null and not ToonLook.is_toon(ov)):
					continue
				var leaf := 1.0 if _changes_in_autumn(c, m.albedo_color) else 0.0
				var key := "%d:%.2f:%d" % [m.get_instance_id(), top, int(leaf)]
				if not cache.has(key):
					var sm := ShaderMaterial.new()
					sm.shader = TREE_SHADER
					sm.set_shader_parameter("leaf", leaf)
					sm.set_shader_parameter("albedo", Color(m.albedo_color.r, m.albedo_color.g, m.albedo_color.b))
					sm.set_shader_parameter("roughness", m.roughness)
					sm.set_shader_parameter("tree_height", top)
					sm.set_shader_parameter("noise_tex", _noise_tex)
					sm.set_shader_parameter("toon", ToonLook.enabled())
					cache[key] = sm
				c.set_surface_override_material(i, cache[key])
		_setup_trees(c, cache)


## Folhagem que muda no outono: copa colorida (não tronco: marrom escuro ou sem cor, como a
## bétula) de árvore folhosa (pinheiro e abeto ficam verdes).
func _changes_in_autumn(mi: MeshInstance3D, col: Color) -> bool:
	var names := String(mi.mesh.resource_path)
	var n: Node = mi
	for i in 4:
		if n == null:
			break
		names += " " + String(n.name)
		n = n.get_parent()
	names = names.to_lower()
	if names.contains("pine") or names.contains("fir") or names.contains("pinh") or names.contains("abet"):
		return false
	var mx := maxf(col.r, maxf(col.g, col.b))
	var mn := minf(col.r, minf(col.g, col.b))
	var brown := col.r >= col.g and col.g >= col.b and mx < 0.5
	return not brown and mx - mn > 0.12


# ================================================================ quadro a quadro
func _process(delta: float) -> void:
	_apply(delta)


func _apply(delta: float) -> void:
	if not _trees_done:
		_trees_done = true
		_setup_trees(get_parent(), {})
	var cam := get_viewport().get_camera_3d()
	var region := Regions.region_at(cam.global_position) if cam != null else "vila"
	if region != _region:
		_region = region
		_bio = BiomeRules.atmo(region)
	var s: Dictionary = BiomeRules.weather(region, Weather.state)
	var wind := 0.0 if Regions.is_dungeon(region) else Weather.wind_now()
	RenderingServer.global_shader_parameter_set("weather_wet", s.wet)
	RenderingServer.global_shader_parameter_set("weather_snow", s.cover)
	RenderingServer.global_shader_parameter_set("weather_rain", s.rain)
	RenderingServer.global_shader_parameter_set("weather_wind", clampf(wind, 0.0, 1.3))
	RenderingServer.global_shader_parameter_set("weather_wind_dir", Weather.wind_dir)
	RenderingServer.global_shader_parameter_set("weather_phase", Weather.phase)
	var autumn := Weather.autumn if _bio.get("autumn", true) else 0.0
	RenderingServer.global_shader_parameter_set("season_autumn", autumn)
	_apply_light(s)
	_update_particles(s, wind)
	_update_overlay(s, delta)
	_set_volume(_rain_audio, s.rain, -8.0)
	var strong := clampf((wind - 0.25) / 0.9, 0.0, 1.0)
	_set_volume(_wind_audio, strong, -6.0)
	_wind_audio.pitch_scale = 0.8 + 0.45 * Weather.gust
