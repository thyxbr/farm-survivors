class_name BackFx
extends RefCounted
## Partículas que caem das peças das costas (asas e capas), uma receita por tipo (item "back_fx").
## Tudo CPUParticles3D pequeno, sem luz: brilho aditivo ou cor chapada. Só visual.

## Receitas: desenho da partícula, tamanho (m), quantidade, vida (s), queda (m/s², negativo desce),
## empurrão inicial, giro (graus/s), aditivo, e as cores (nasce, meio, some).
const KINDS := {
	# asas
	"light_feathers": {"tex": "feather", "size": Vector2(0.07, 0.16), "amount": 7, "life": 2.6, "fall": -0.35,
		"push": 0.25, "spin": 60.0, "add": true, "colors": [Color(1, 1, 0.92), Color(1.0, 0.9, 0.55), Color(1.0, 0.7, 0.3)]},
	"embers": {"tex": "dot", "size": Vector2(0.05, 0.05), "amount": 12, "life": 2.0, "fall": -0.45,
		"push": 0.3, "spin": 0.0, "add": true, "colors": [Color(1, 0.9, 0.6), Color(1.0, 0.45, 0.12), Color(0.7, 0.1, 0.05)]},
	"crystal_dust": {"tex": "diamond", "size": Vector2(0.05, 0.08), "amount": 10, "life": 2.2, "fall": -0.5,
		"push": 0.2, "spin": 120.0, "add": true, "colors": [Color(1, 1, 1), Color(0.6, 0.92, 1.0), Color(0.35, 0.6, 1.0)]},
	"fire_feathers": {"tex": "feather", "size": Vector2(0.07, 0.15), "amount": 9, "life": 2.0, "fall": -0.3,
		"push": 0.35, "spin": 90.0, "add": true, "colors": [Color(1, 0.95, 0.6), Color(1.0, 0.55, 0.12), Color(0.8, 0.12, 0.05)]},
	"sparks": {"tex": "streak", "size": Vector2(0.018, 0.11), "amount": 10, "life": 0.9, "fall": -2.6,
		"push": 0.5, "spin": 0.0, "add": true, "colors": [Color(1, 1, 1), Color(0.45, 0.9, 1.0), Color(0.2, 0.5, 1.0)]},
	"scales": {"tex": "diamond", "size": Vector2(0.045, 0.06), "amount": 6, "life": 2.4, "fall": -0.7,
		"push": 0.2, "spin": 160.0, "add": false, "colors": [Color(0.8, 0.95, 0.6), Color(0.25, 0.7, 0.45), Color(0.1, 0.4, 0.3)]},
	"pixie_dust": {"tex": "star", "size": Vector2(0.06, 0.06), "amount": 14, "life": 2.4, "fall": -0.25,
		"push": 0.25, "spin": 80.0, "add": true, "colors": [Color(1, 1, 1), Color(1.0, 0.7, 0.92), Color(1.0, 0.85, 0.4)]},
	# capas
	"gold_dust": {"tex": "dot", "size": Vector2(0.035, 0.035), "amount": 10, "life": 2.2, "fall": -0.3,
		"push": 0.15, "spin": 0.0, "add": true, "colors": [Color(1, 1, 0.85), Color(1.0, 0.8, 0.3), Color(0.9, 0.5, 0.1)]},
	"stardust": {"tex": "star", "size": Vector2(0.055, 0.055), "amount": 12, "life": 2.6, "fall": -0.22,
		"push": 0.15, "spin": 50.0, "add": true, "colors": [Color(1, 1, 1), Color(0.7, 0.85, 1.0), Color(0.45, 0.55, 1.0)]},
	"road_dust": {"tex": "puff", "size": Vector2(0.09, 0.09), "amount": 6, "life": 2.0, "fall": -0.15,
		"push": 0.12, "spin": 20.0, "add": false, "colors": [Color(0.8, 0.72, 0.6), Color(0.7, 0.62, 0.5), Color(0.6, 0.52, 0.42)]},
	"petals": {"tex": "petal", "size": Vector2(0.06, 0.07), "amount": 7, "life": 3.0, "fall": -0.28,
		"push": 0.2, "spin": 140.0, "add": false, "colors": [Color(1.0, 0.75, 0.82), Color(0.9, 0.35, 0.5), Color(0.7, 0.2, 0.36)]},
	"raven_feathers": {"tex": "feather", "size": Vector2(0.06, 0.14), "amount": 6, "life": 2.8, "fall": -0.3,
		"push": 0.2, "spin": 70.0, "add": false, "colors": [Color(0.2, 0.18, 0.3), Color(0.12, 0.1, 0.2), Color(0.3, 0.26, 0.55)]},
	"snowflakes": {"tex": "star", "size": Vector2(0.05, 0.05), "amount": 14, "life": 2.8, "fall": -0.2,
		"push": 0.15, "spin": 60.0, "add": true, "colors": [Color(1, 1, 1), Color(0.8, 0.94, 1.0), Color(0.55, 0.8, 1.0)]},
	"bolt_sparks": {"tex": "streak", "size": Vector2(0.02, 0.13), "amount": 10, "life": 0.8, "fall": -3.0,
		"push": 0.6, "spin": 0.0, "add": true, "colors": [Color(1, 1, 1), Color(1.0, 0.95, 0.5), Color(0.5, 0.7, 1.0)]},
	"leaves": {"tex": "petal", "size": Vector2(0.065, 0.08), "amount": 8, "life": 3.0, "fall": -0.3,
		"push": 0.2, "spin": 150.0, "add": false, "colors": [Color(0.7, 0.95, 0.45), Color(0.3, 0.72, 0.36), Color(0.16, 0.45, 0.26)]},
}

## Pano animado (assets/shaders/back_anim.gdshader): material do GLB -> modo e cores do shader.
const ANIM := {
	"fx_galaxy": {"mode": 0, "base": Color(0.05, 0.07, 0.3), "base2": Color(0.3, 0.1, 0.5),
		"glow": Color(1.0, 0.96, 0.78), "glow2": Color(0.35, 0.6, 1.0), "energy": 2.2},
	"fx_fire": {"mode": 1, "base": Color(0.16, 0.04, 0.04), "base2": Color(0.62, 0.08, 0.05),
		"glow": Color(1.0, 0.72, 0.15), "glow2": Color(1.0, 0.3, 0.05), "energy": 1.1},
	"fx_ice": {"mode": 2, "base": Color(0.3, 0.6, 0.9), "base2": Color(0.72, 0.92, 1.0),
		"glow": Color(1.0, 1.0, 1.0), "glow2": Color(0.6, 0.9, 1.0), "energy": 1.6},
	"fx_storm": {"mode": 3, "base": Color(0.09, 0.11, 0.2), "base2": Color(0.24, 0.28, 0.44),
		"glow": Color(1.0, 0.96, 0.6), "glow2": Color(0.5, 0.7, 1.0), "energy": 2.4},
	"fx_nature": {"mode": 4, "base": Color(0.1, 0.36, 0.2), "base2": Color(0.24, 0.6, 0.3),
		"glow": Color(0.8, 1.0, 0.45), "glow2": Color(1.0, 0.95, 0.55), "energy": 1.6},
}
const ANIM_SHADER := preload("res://assets/shaders/back_anim.gdshader")

static var _tex := {}
static var _anim := {}


## Troca, em todas as malhas sob `root`, os materiais "fx_<tipo>" pelo shader animado.
static func apply_anim(root: Node) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			if src != null and ANIM.has(src.resource_name):
				mi.set_surface_override_material(s, anim_material(src.resource_name))


## Material animado do tipo `name` (um por tipo, compartilhado). Null se o tipo não existe.
static func anim_material(name: String) -> ShaderMaterial:
	if not ANIM.has(name):
		return null
	if not _anim.has(name):
		var m := ShaderMaterial.new()
		m.shader = ANIM_SHADER
		for k in ANIM[name]:
			m.set_shader_parameter(k, ANIM[name][k])
		_anim[name] = m
	return _anim[name]


## Emissor do tipo `kind` numa caixa de meio-tamanho `extents` em volta de `pos` (espaço do pai). Null se
## o tipo não existe.
static func make(kind: String, pos: Vector3, extents: Vector3) -> CPUParticles3D:
	if not KINDS.has(kind):
		return null
	var k: Dictionary = KINDS[kind]
	var p := CPUParticles3D.new()
	p.name = "BackFx_" + kind
	var quad := QuadMesh.new()
	quad.size = k.size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if k.add:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = texture(k.tex)
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = m
	p.mesh = quad
	p.amount = k.amount
	p.lifetime = k.life
	p.local_coords = false          # ficam para trás quando o personagem anda
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.position = pos
	p.direction = Vector3.DOWN
	p.spread = 40.0
	p.gravity = Vector3(0, k.fall, 0)
	p.initial_velocity_min = k.push * 0.2
	p.initial_velocity_max = k.push
	p.angle_min = -45.0
	p.angle_max = 45.0
	p.angular_velocity_min = -k.spin
	p.angular_velocity_max = k.spin
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.25
	var c: Array = k.colors
	var a := 1.0 if k.add else 0.85
	var grad := Gradient.new()
	grad.set_color(0, Color(c[0].r, c[0].g, c[0].b, 0.0))
	grad.add_point(0.12, Color(c[0].r, c[0].g, c[0].b, a))
	grad.add_point(0.55, Color(c[1].r, c[1].g, c[1].b, a * 0.8))
	grad.set_color(grad.get_point_count() - 1, Color(c[2].r, c[2].g, c[2].b, 0.0))
	p.color_ramp = grad
	return p


## Desenho branco da partícula (a cor vem do emissor), feito uma vez em memória.
static func texture(kind: String) -> Texture2D:
	if _tex.has(kind):
		return _tex[kind]
	var n := 48
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (float(x) + 0.5) / n * 2.0 - 1.0      # -1..1, direita positiva
			var v := (float(y) + 0.5) / n * 2.0 - 1.0      # -1..1, de cima para baixo
			img.set_pixel(x, y, Color(1, 1, 1, clampf(_alpha(kind, u, v), 0.0, 1.0)))
	_tex[kind] = ImageTexture.create_from_image(img)
	return _tex[kind]


static func _alpha(kind: String, u: float, v: float) -> float:
	var r := sqrt(u * u + v * v)
	match kind:
		"feather":     # folha fina com haste: larga no meio, ponta arredondada em cima
			var t := (v + 1.0) * 0.5
			var half := 0.42 * minf(1.0, 0.25 + 2.2 * (1.0 - t)) * sqrt(maxf(0.0, 1.0 - pow(maxf(0.0, (0.45 - t) / 0.45), 2.4)))
			return (half - absf(u)) / 0.1 * (0.7 + clampf(1.0 - absf(u) / 0.08, 0.0, 1.0) * 0.3)
		"diamond":     # losango de borda dura
			return (0.92 - (absf(u) * 1.5 + absf(v))) / 0.08
		"star":        # estrela de quatro pontas com miolo redondo
			return maxf((0.16 - absf(u) * absf(v) * 6.0 - r * 0.14) / 0.05, (0.3 - r) / 0.12)
		"streak":      # risco de faísca: fino, mais forte embaixo
			return (1.0 - absf(u) / 0.7) * clampf((v + 1.0) * 0.6, 0.0, 1.0) * (1.0 - maxf(0.0, v - 0.6) / 0.4)
		"petal":       # pétala: gota arredondada
			var py := v * 0.9 + 0.1
			return (0.72 - sqrt(u * u * (1.6 + py * 0.9) + py * py)) / 0.08
		"puff":        # tufo redondo e macio
			return (0.85 - r) / 0.5
	return (0.8 - r) / 0.45     # "dot": ponto de luz macio
