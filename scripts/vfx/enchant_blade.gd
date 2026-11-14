class_name EnchantBlade
extends Node3D
## Partículas em volta da lâmina de uma arma encantada. Cada nível acrescenta uma camada, para a
## arma ficar visivelmente mais "épica" conforme sobe:
##   +1  poucas faíscas soltando da lâmina
##   +2  mais faíscas, os primeiros fios de brilho e um pouco do detalhe do elemento
##   +3  + uma espiral de luz girando em volta da lâmina e um brilho na ponta
##   +4  + segunda espiral, mais de tudo
##   +5  + terceira espiral, clarão na ponta e explosões de faíscas de tempos em tempos
## O detalhe do elemento muda a cara de cada um: fogo sobe em labaredas, gelo cai em cristais,
## raio estala em riscos, veneno pinga, sagrado solta estrelas e sombra solta fumaça escura.
## Fica como filho do suporte da arma (KnightLook "holder"); o eixo vai do cabo até a ponta ("tip").

## Por nível (+1..+5): faíscas, fios de brilho, espirais, partículas do elemento, tamanho do brilho da ponta.
const LEVELS := [
	{"sparks": 8, "wisps": 0, "helix": 0, "flavor": 0, "flare": 0.0},
	{"sparks": 16, "wisps": 3, "helix": 0, "flavor": 4, "flare": 0.0},
	{"sparks": 26, "wisps": 5, "helix": 1, "flavor": 9, "flare": 0.16},
	{"sparks": 40, "wisps": 8, "helix": 2, "flavor": 15, "flare": 0.26},
	{"sparks": 60, "wisps": 12, "helix": 3, "flavor": 26, "flare": 0.42},
]
const HELIX_RADIUS := 0.12
const HELIX_SPIN := 7.5        # rad/s em volta da lâmina
const HELIX_TRAVEL := 1.15     # segundos para ir do cabo à ponta
const BURST_EVERY := 1.5       # segundos entre as explosões de faíscas do +5

var _orbiters: Array = []      # [{"node": Node3D, "phase": float}]
var _flare: MeshInstance3D
var _flare_size := 0.0
var _burst: CPUParticles3D
var _len := 1.0
var _t := 0.0
var _burst_t := 0.0


## Monta o efeito. `def` = EnchantFX.ELEMENTS[element]; `tip_pos` = ponta da arma no espaço do suporte.
static func make(element: String, def: Dictionary, tip_pos: Vector3, level: int) -> EnchantBlade:
	var b := EnchantBlade.new()
	b._build(element, def, tip_pos, clampi(level, 1, LEVELS.size()))
	return b


func _build(element: String, def: Dictionary, tip_pos: Vector3, level: int) -> void:
	var cfg: Dictionary = LEVELS[level - 1]
	_len = maxf(tip_pos.length(), 0.2)
	# eixo: +Z ao longo da lâmina, origem no cabo
	var d := tip_pos.normalized() if tip_pos.length() > 0.01 else Vector3(0, 0, 1)
	var up := Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
	basis = Basis.looking_at(-d, up)
	_t = randf() * 10.0   # armas lado a lado não giram em sincronia
	add_child(_sparks(def, int(cfg.sparks), level))
	if int(cfg.wisps) > 0:
		add_child(_wisps(def, int(cfg.wisps), level))
	for i in int(cfg.helix):
		var orb := Node3D.new()
		add_child(orb)
		orb.add_child(_trail(def))
		_orbiters.append({"node": orb, "phase": float(i) / float(cfg.helix)})
	if int(cfg.flavor) > 0:
		add_child(_flavor(element, def, int(cfg.flavor)))
	_flare_size = float(cfg.flare)
	if _flare_size > 0.0:
		_flare = _tip_flare(def)
		add_child(_flare)
	if level >= LEVELS.size():
		_burst = _tip_burst(def)
		add_child(_burst)
	_animate(0.0)


func _process(delta: float) -> void:
	_animate(delta)


func _animate(delta: float) -> void:
	_t += delta
	for o in _orbiters:
		var along := fposmod(_t / HELIX_TRAVEL + float(o.phase), 1.0)
		var ang := _t * HELIX_SPIN + float(o.phase) * TAU
		(o.node as Node3D).position = Vector3(cos(ang) * HELIX_RADIUS, sin(ang) * HELIX_RADIUS, along * _len)
	if _flare:
		var s := _flare_size * (0.8 + 0.2 * sin(_t * 6.0) + 0.1 * sin(_t * 17.0))
		_flare.scale = Vector3.ONE * s
	if _burst:
		_burst_t += delta
		if _burst_t >= BURST_EVERY:
			_burst_t = 0.0
			_burst.position = Vector3(0, 0, randf_range(0.35, 1.0) * _len)
			_burst.restart()


# ------------------------------------------------------------------ camadas
func _mat(tex: String, add := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if add else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.albedo_texture = BuffAura._tex(tex)
	return m


func _emitter(tex: String, size: Vector2, add := true) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	quad.material = _mat(tex, add)
	p.mesh = quad
	p.local_coords = false       # o rastro fica no ar quando a arma se move
	p.randomness = 1.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Caixa fina ao longo da lâmina (no espaço do eixo: Z = comprimento).
func _along_blade(p: CPUParticles3D, width := 0.035) -> void:
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(width, width * 1.6, _len * 0.5)
	p.position = Vector3(0, 0, _len * 0.5)


func _fade(c0: Color, c1: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(c0.r, c0.g, c0.b, 0.0))
	g.add_point(0.15, c0)
	g.add_point(0.6, c1)
	g.set_color(g.get_point_count() - 1, Color(c1.r, c1.g, c1.b, 0.0))
	return g


func _shrink() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, 0.4))
	c.add_point(Vector2(0.2, 1.0))
	c.add_point(Vector2(1, 0.0))
	return c


## Faíscas pequenas soltando da lâmina (a base de todos os níveis).
func _sparks(def: Dictionary, amount: int, level: int) -> CPUParticles3D:
	var p := _emitter("dot", Vector2.ONE * (0.04 + 0.006 * level))
	_along_blade(p)
	p.amount = amount
	p.lifetime = 0.75
	p.preprocess = 0.75
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.08
	p.initial_velocity_max = 0.3 * float(def.speed)
	p.gravity = Vector3(0, float(def.grav), 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	p.scale_amount_curve = _shrink()
	p.color_ramp = _fade(def.spark, def.color)
	return p


## Fios de brilho: manchas macias e maiores coladas na lâmina, que dão o halo.
func _wisps(def: Dictionary, amount: int, level: int) -> CPUParticles3D:
	var p := _emitter("dot", Vector2.ONE * (0.14 + 0.02 * level))
	_along_blade(p, 0.02)
	p.local_coords = true        # o halo acompanha a lâmina
	p.amount = amount
	p.lifetime = 1.1
	p.preprocess = 1.1
	p.direction = Vector3(0, 0, 1)
	p.spread = 20.0
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.25
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.2
	p.scale_amount_curve = _shrink()
	var c: Color = def.color
	p.color_ramp = _fade(Color(c.r, c.g, c.b, 0.45), Color(c.r, c.g, c.b, 0.3))
	return p


## Rastro de uma espiral: o emissor é carregado em volta da lâmina por _animate.
func _trail(def: Dictionary) -> CPUParticles3D:
	var p := _emitter("dot", Vector2.ONE * 0.045)
	p.amount = 22
	p.lifetime = 0.45
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.05
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.1
	p.scale_amount_curve = _shrink()
	var s: Color = def.spark
	p.color_ramp = _fade(s.lightened(0.3), def.color)
	return p


## O detalhe de cada elemento.
func _flavor(element: String, def: Dictionary, amount: int) -> CPUParticles3D:
	var p: CPUParticles3D
	var c: Color = def.color
	var s: Color = def.spark
	match element:
		"fogo":      # labaredas subindo da lâmina
			p = _emitter("flame", Vector2(0.07, 0.15))
			p.lifetime = 0.55
			p.direction = Vector3.UP
			p.spread = 12.0
			p.initial_velocity_min = 0.3
			p.initial_velocity_max = 0.8
			p.gravity = Vector3(0, 2.2, 0)
			p.color_ramp = _fade(Color(1.0, 0.9, 0.5), Color(1.0, 0.3, 0.05))
		"gelo":      # cristais de neve caindo
			p = _emitter("star", Vector2.ONE * 0.085)
			p.lifetime = 1.0
			p.direction = Vector3.DOWN
			p.spread = 40.0
			p.initial_velocity_min = 0.05
			p.initial_velocity_max = 0.25
			p.gravity = Vector3(0, -0.9, 0)
			p.color_ramp = _fade(Color(1, 1, 1), c)
		"raio":      # riscos curtos estalando para todo lado
			p = _emitter("dot", Vector2(0.018, 0.17))
			(p.mesh.material as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
			p.particle_flag_align_y = true
			p.lifetime = 0.16
			p.direction = Vector3.UP
			p.spread = 180.0
			p.initial_velocity_min = 1.2
			p.initial_velocity_max = 3.0
			p.gravity = Vector3.ZERO
			p.color_ramp = _fade(Color(1, 1, 1), c)
		"veneno":    # gotas pingando
			p = _emitter("dot", Vector2(0.04, 0.06))
			p.lifetime = 0.8
			p.direction = Vector3.DOWN
			p.spread = 10.0
			p.initial_velocity_min = 0.0
			p.initial_velocity_max = 0.15
			p.gravity = Vector3(0, -3.2, 0)
			p.color_ramp = _fade(s, c)
		"sagrado":   # estrelas subindo devagar
			p = _emitter("star", Vector2.ONE * 0.11)
			p.lifetime = 1.0
			p.direction = Vector3.UP
			p.spread = 50.0
			p.initial_velocity_min = 0.1
			p.initial_velocity_max = 0.35
			p.gravity = Vector3(0, 0.5, 0)
			p.color_ramp = _fade(Color(1, 1, 0.9), c)
		_:           # sombra: fumaça escura subindo
			p = _emitter("dot", Vector2.ONE * 0.2, false)
			p.lifetime = 1.1
			p.direction = Vector3.UP
			p.spread = 35.0
			p.initial_velocity_min = 0.1
			p.initial_velocity_max = 0.35
			p.gravity = Vector3(0, 0.5, 0)
			p.color_ramp = _fade(Color(0.12, 0.02, 0.2, 0.75), Color(0.3, 0.08, 0.5, 0.5))
	_along_blade(p, 0.03)
	p.amount = amount
	p.preprocess = p.lifetime
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	p.scale_amount_curve = _shrink()
	return p


## Brilho de quatro pontas na ponta da arma (pulsa em _animate).
func _tip_flare(def: Dictionary) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_texture = BuffAura._tex("star")
	var c: Color = def.spark
	m.albedo_color = Color(c.r, c.g, c.b, 0.9) if c.get_luminance() > 0.3 else def.color
	quad.material = m
	mi.mesh = quad
	mi.position = Vector3(0, 0, _len)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("enchant_skip_overlay", true)
	return mi


## Explosão de faíscas do +5 (disparada de tempos em tempos por _animate).
func _tip_burst(def: Dictionary) -> CPUParticles3D:
	var p := _emitter("dot", Vector2.ONE * 0.05)
	p.amount = 14
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.95
	p.lifetime = 0.5
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.3
	p.gravity = Vector3(0, float(def.grav) * 0.5, 0)
	p.scale_amount_curve = _shrink()
	var s: Color = def.spark
	p.color_ramp = _fade(s.lightened(0.4), def.color)
	return p
