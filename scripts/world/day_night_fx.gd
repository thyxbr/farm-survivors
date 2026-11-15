class_name DayNightFX
extends Node
## Desenha o dia e a noite na cena (Valdoria e praça): o sol cruza o céu e esquenta no começo e no fim do
## dia; à noite a luz vira um luar azulado, o céu escurece e ganha estrelas, e as luzes da cidade acendem
## (lampiões, janelas das casas, pisca-pisca de Natal). A hora sai de DayNightRules e do relógio do Weather.
##
## Roda depois do WeatherFX em cada quadro: o clima monta a luz do dia (nuvens, neblina) e o dia/noite
## escurece e tinge por cima do que ele deixou. Sem WeatherFX na cena, parte da luz guardada no _ready.
## Criar depois de WorldLighting.build e do WeatherFX. Só visual: não existe no servidor dedicado.
##
## Depuração: `--hora=21` fixa a hora do jogo; no chat, `/hora 21` faz o mesmo e `/hora auto` volta.

## Grupo das luzes que acendem à noite (OmniLight3D com o meta "night_energy").
const GROUP := &"night_lights"

## Hora forçada (0..24) nesta máquina, ou -1 para seguir o relógio.
static var forced_hour := -1.0
## Hora e noite (0..1) atuais, para quem quiser ler (HUD, testes).
static var hour := 12.0
static var night_amount := 0.0

var _env: Environment
var _sky: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _rim: DirectionalLight3D
var _base := {}
var _sun_rot := Vector3.ZERO
var _glass: Array = []     # [material, energia base, fator de dia] das janelas e lanternas
var _scan_in := 0.6        # segundos até procurar as janelas (o toon troca os materiais no quadro seguinte)
var _rescanned := false


## Marca uma luz para acender só à noite. `energy` é a força dela de noite.
static func night_light(l: Light3D, energy: float) -> void:
	l.set_meta("night_energy", energy)
	l.set_meta("night_offset", randf())
	l.add_to_group(GROUP)
	l.light_energy = 0.0
	l.visible = false


func _ready() -> void:
	process_priority = 50   # depois do WeatherFX (prioridade 0)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hora="):
			forced_hour = DayNightRules.parse_hour(a.substr(7))
	for c in get_parent().get_children():
		if c is WorldEnvironment and _env == null:
			_env = c.environment
		elif c is DirectionalLight3D:
			if c.shadow_enabled and _sun == null:
				_sun = c
			elif _rim == null:
				_rim = c
	if _env != null:
		_base.ambient = _env.ambient_light_energy
		_base.ambient_color = _env.ambient_light_color
		_base.fog_color = _env.fog_light_color
		if _env.sky != null and _env.sky.sky_material is ProceduralSkyMaterial:
			_sky = _env.sky.sky_material
			_base.sky_top = _sky.sky_top_color
			_base.sky_hz = _sky.sky_horizon_color
			_base.ground_hz = _sky.ground_horizon_color
			_base.ground_bottom = _sky.ground_bottom_color
			_base.sky_energy = _sky.energy_multiplier
			_sky.sky_cover = _stars()
			_sky.sky_cover_modulate = Color(1, 1, 1, 0)
	if _sun != null:
		_base.sun = _sun.light_energy
		_base.sun_color = _sun.light_color
		_sun_rot = _sun.rotation_degrees
	if _rim != null:
		_base.rim = _rim.light_energy
	_apply(0.0)


func _exit_tree() -> void:
	# os materiais das janelas são compartilhados (cache do toon): voltam ao brilho de sempre
	for g in _glass:
		_set_glow(g[0], g[1])
	if _sky != null:
		_sky.sky_cover = null


func _process(delta: float) -> void:
	_apply(delta)


## Hora atual do jogo (forçada ou pelo relógio do mundo).
static func current_hour() -> float:
	if forced_hour >= 0.0:
		return forced_hour
	return DayNightRules.hour_at(Weather._clock)


func _apply(delta: float) -> void:
	hour = current_hour()
	var n := DayNightRules.night(hour)
	night_amount = n
	var sun_k := DayNightRules.sun(hour)
	var moon_k := DayNightRules.moon(hour)
	var gold := DayNightRules.golden(hour) * (1.0 - n * 0.5)
	var cloud: float = Weather.state.get("cloud", 0.0)
	var weather_live := Weather.fx != null and is_instance_valid(Weather.fx)
	# ---- sol e lua (a direção troca no escuro, quando os dois estão perto de zero)
	if _sun != null:
		var e: float = _sun.light_energy if weather_live else _base.sun
		var c: Color = _sun.light_color if weather_live else _base.sun_color
		if sun_k > 0.0 or moon_k <= 0.0:
			_sun.rotation_degrees = DayNightRules.sun_rotation(hour)
		else:
			_sun.rotation_degrees = DayNightRules.MOON_ROTATION
		_sun.light_energy = e * (sun_k * (1.0 - 0.25 * gold) + 0.3 * moon_k)
		c = c.lerp(Color(1.0, 0.62, 0.38), gold * 0.75 * sun_k)
		_sun.light_color = c.lerp(Color(0.62, 0.72, 1.0), moon_k)
	if _rim != null:
		var r: float = _rim.light_energy if weather_live else _base.rim
		_rim.light_energy = r * (1.0 - 0.45 * n)
		_rim.light_color = Color(0.84, 0.88, 1.0).lerp(Color(0.55, 0.65, 1.0), n)
	# ---- céu, ambiente e névoa
	if _env != null:
		var amb: float = _env.ambient_light_energy if weather_live else _base.ambient
		_env.ambient_light_energy = amb * (1.0 - 0.35 * n)
		_env.ambient_light_color = (_base.ambient_color as Color).lerp(Color(0.32, 0.38, 0.68), n)
		var fog: Color = _env.fog_light_color if weather_live else _base.fog_color
		_env.fog_light_color = fog.lerp(Color(0.95, 0.62, 0.45), gold * 0.45).lerp(Color(0.1, 0.13, 0.26), n)
	if _sky != null:
		var top: Color = _sky.sky_top_color if weather_live else _base.sky_top
		var hz: Color = _sky.sky_horizon_color if weather_live else _base.sky_hz
		var ghz: Color = _sky.ground_horizon_color if weather_live else _base.ground_hz
		var sky_e: float = _sky.energy_multiplier if weather_live else _base.sky_energy
		var dusk := Color(1.0, 0.58, 0.4).lerp(Color(0.6, 0.6, 0.66), cloud)
		_sky.sky_top_color = top.lerp(Color(0.42, 0.42, 0.62), gold * 0.35).lerp(Color(0.025, 0.04, 0.12), n)
		_sky.sky_horizon_color = hz.lerp(dusk, gold * 0.7).lerp(Color(0.08, 0.11, 0.24), n)
		_sky.ground_horizon_color = ghz.lerp(dusk, gold * 0.5).lerp(Color(0.06, 0.08, 0.16), n)
		_sky.ground_bottom_color = (_base.ground_bottom as Color).lerp(Color(0.03, 0.04, 0.07), n)
		_sky.energy_multiplier = sky_e * (1.0 - 0.3 * n)
		_sky.sky_cover_modulate = Color(1, 1, 1, n * (1.0 - cloud * 0.9))
	# ---- luzes da cidade
	for l in get_tree().get_nodes_in_group(GROUP):
		var k := DayNightRules.lamp_on(n, l.get_meta("night_offset", 0.0))
		l.light_energy = float(l.get_meta("night_energy", 1.0)) * k
		l.visible = k > 0.01
	ChristmasDecor.set_night(n)
	if _scan_in > 0.0:
		_scan_in -= delta
		if _scan_in <= 0.0:
			_find_glass(get_parent())
			if not _rescanned:   # segunda passada: pega o que o toon converteu mais tarde
				_rescanned = true
				_scan_in = 3.0
	for g in _glass:
		_set_glow(g[0], g[1] * lerpf(g[2], 1.0, DayNightRules.lamp_on(n, 0.4)))


# ================================================================ janelas e lanternas
## Vidros que acendem à noite, pelo nome do material de origem (tools/blender): janelas das casas e
## lojas (b_glass) e vidro dos lampiões (p_lantern). [nome, brilho de noite (× o do modelo), fator de dia]
const GLOWS := {"b_glass": [4.0, 1.0], "p_lantern": [1.2, 0.12]}
var _glass_seen := {}


func _find_glass(root: Node) -> void:
	var seen := _glass_seen
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			if src == null or not GLOWS.has(src.resource_name):
				continue
			var active: Material = (mi as MeshInstance3D).get_active_material(i)
			if active == null or seen.has(active):
				continue
			seen[active] = true
			var base := _glow_of(active)
			if base > 0.0:
				var g: Array = GLOWS[src.resource_name]
				_glass.append([active, base * g[0], g[1] / g[0]])


static func _glow_of(m: Material) -> float:
	if m is ShaderMaterial:
		var v = (m as ShaderMaterial).get_shader_parameter("emission_energy")
		return float(v) if v != null else 0.0
	if m is BaseMaterial3D and (m as BaseMaterial3D).emission_enabled:
		return (m as BaseMaterial3D).emission_energy_multiplier
	return 0.0


static func _set_glow(m: Material, e: float) -> void:
	if m is ShaderMaterial:
		(m as ShaderMaterial).set_shader_parameter("emission_energy", e)
	elif m is BaseMaterial3D:
		(m as BaseMaterial3D).emission_energy_multiplier = e


# ================================================================ estrelas
static var _star_tex: Texture2D = null


## Panorama de estrelas (cobertura do céu procedural), gerado uma vez: pontos brancos e alguns azulados
## só na metade de cima, mais raros perto do horizonte.
static func _stars() -> Texture2D:
	if _star_tex != null:
		return _star_tex
	var w := 2048
	var h := 1024
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1225
	for i in 2600:
		var y := int(pow(rng.randf(), 1.6) * h * 0.47)   # mais estrelas no alto
		var x := rng.randi() % w
		var b := rng.randf_range(0.35, 1.0)
		var c := Color(1, 1, 1).lerp(Color(0.7, 0.8, 1.0), rng.randf()) * b
		c.a = b
		img.set_pixel(x, y, c)
		if b > 0.85:   # as mais fortes ganham uma cruzinha
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var p := Vector2i(posmod(x + d.x, w), clampi(y + d.y, 0, h - 1))
				img.set_pixel(p.x, p.y, Color(c.r, c.g, c.b, 0.45))
	_star_tex = ImageTexture.create_from_image(img)
	return _star_tex
