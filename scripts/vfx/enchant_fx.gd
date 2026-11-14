class_name EnchantFX
extends RefCounted
## PROTÓTIPO (spike): visual de arma encantada. Cor = elemento, força = nível (1..MAX_LEVEL).
##  nível 1: só um tom da cor do elemento
##  nível 2: + borda brilhando e pulsando
##  nível 3: + faixas de energia correndo pela lâmina
##  nível 4: + algumas partículas saindo da lâmina
##  nível 5: + muitas partículas e brilho máximo

const MAX_LEVEL := 5
## Força do brilho por nível (+1..+5): degraus desiguais para cada nível ficar fácil de distinguir.
const LEVEL_INTENSITY := [0.08, 0.32, 0.58, 0.8, 1.0]
const SHADER := preload("res://shaders/enchant_overlay.gdshader")

## Elemento -> cor principal, cor das partículas e gravidade das faíscas (fogo sobe, gelo cai...).
const ELEMENTS := {
	"fogo":    {"name": "Fogo",    "color": Color(1.0, 0.42, 0.08), "spark": Color(1.0, 0.8, 0.3), "grav": 2.5, "speed": 1.4},
	"gelo":    {"name": "Gelo",    "color": Color(0.35, 0.8, 1.0),  "spark": Color(0.85, 0.97, 1.0), "grav": -1.2, "speed": 0.5},
	"raio":    {"name": "Raio",    "color": Color(0.65, 0.55, 1.0), "spark": Color(0.95, 0.95, 1.0), "grav": 0.0, "speed": 3.5},
	"veneno":  {"name": "Veneno",  "color": Color(0.4, 0.95, 0.2),  "spark": Color(0.7, 1.0, 0.3), "grav": -0.8, "speed": 0.6},
	"sagrado": {"name": "Sagrado", "color": Color(1.0, 0.85, 0.35), "spark": Color(1.0, 1.0, 0.8), "grav": 0.8, "speed": 0.8},
	"sombra":  {"name": "Sombra",  "color": Color(0.55, 0.15, 0.85), "spark": Color(0.25, 0.05, 0.4), "grav": 0.6, "speed": 0.6},
}


## Aplica (ou remove, com level 0) o encantamento na arma montada por KnightLook.apply (`look`).
static func apply(look: Dictionary, element: String, level: int) -> void:
	var holder: Node3D = look.get("holder")
	if holder == null or not is_instance_valid(holder):
		return
	for n in holder.get_children():
		if n.has_meta("enchant_fx"):
			n.free()
	var meshes: Array = []
	_collect_meshes(holder, meshes)
	if level <= 0 or not ELEMENTS.has(element):
		for mi in meshes:
			mi.material_overlay = null
		return
	var e: Dictionary = ELEMENTS[element]
	var k: float = LEVEL_INTENSITY[clampi(level, 1, MAX_LEVEL) - 1]
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("glow_color", e.color)
	mat.set_shader_parameter("intensity", k)
	mat.set_shader_parameter("band_speed", 0.6 + e.speed * 0.6)
	for mi in meshes:
		mi.material_overlay = mat

	var tip: Node3D = look.get("tip")
	var tip_pos := tip.position if tip else Vector3(0, 0, 1)
	# sem luz de verdade: ela tingia a armadura inteira. O brilho (bloom) do ambiente já dá o halo.
	# partículas ao longo da lâmina a partir do nível 4 (mais densas no 5)
	if level >= 4:
		holder.add_child(_blade_particles(e, tip_pos, level))


static func _collect_meshes(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		_collect_meshes(c, out)


static func _blade_particles(e: Dictionary, tip_pos: Vector3, level: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.set_meta("enchant_fx", true)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.05
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if e.spark.get_luminance() > 0.3 else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = _dot_texture()
	quad.material = m
	p.mesh = quad
	p.amount = 14 if level == 4 else 32
	p.lifetime = 0.7
	p.local_coords = false            # rastro fica no ar quando a arma se move
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	var half := tip_pos * 0.5
	p.position = half
	# caixa fina ao longo do eixo da lâmina
	p.emission_box_extents = Vector3(absf(half.x) + 0.02, absf(half.y) + 0.02, absf(half.z) + 0.02)
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.25 * e.speed
	p.gravity = Vector3(0, e.grav, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, e.spark)
	grad.set_color(1, Color(e.color.r, e.color.g, e.color.b, 0.0))
	p.color_ramp = grad
	p.emitting = true
	return p


static var _dot: Texture2D
## Bolinha macia (gradiente radial) usada pelas partículas.
static func _dot_texture() -> Texture2D:
	if _dot:
		return _dot
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 32
	t.height = 32
	_dot = t
	return t
