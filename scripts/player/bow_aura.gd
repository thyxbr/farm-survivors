class_name BowAura
extends RefCounted
## Partículas dos arcos míticos e das montantes de nível 50 na mão. O GLB do arco (tools/blender/armory.py) traz empties "Aura_<tipo>_<n>"
## nos pontos onde o efeito sai (pontas, gemas, braseiro...); cada um ganha um emissor contínuo (FXEpic.stream)
## no estilo do tipo. As partículas ficam no mundo: o arco em movimento deixa um rastro delas.

## tipo -> cor, quantidade, vida (s), tamanho, gravidade (m/s², para cima > 0), velocidade e raio de saída.
const KINDS := {
	"void": {"color": Color(0.62, 0.32, 1.0), "amount": 12, "life": 1.1, "size": 0.05, "grav": 0.35, "vel": 0.12, "r": 0.03},
	"sun": {"color": Color(1.0, 0.78, 0.3), "amount": 12, "life": 0.9, "size": 0.05, "grav": 0.7, "vel": 0.15, "r": 0.03},
	"fire": {"color": Color(1.0, 0.5, 0.12), "amount": 14, "life": 0.7, "size": 0.055, "grav": 1.4, "vel": 0.2, "r": 0.025},
	"wind": {"color": Color(0.72, 0.95, 1.0), "amount": 10, "life": 0.8, "size": 0.045, "grav": 0.0, "vel": 0.45, "r": 0.04},
	"moon": {"color": Color(0.82, 0.88, 1.0), "amount": 10, "life": 1.4, "size": 0.045, "grav": 0.12, "vel": 0.08, "r": 0.04},
	"leaf": {"color": Color(0.55, 0.92, 0.38), "amount": 8, "life": 1.6, "size": 0.05, "grav": -0.35, "vel": 0.1, "r": 0.04},
	# montantes de nível 50 (armory.py, build_gsia): dez pontos (guarda, ponta e as duas bordas da lâmina)
	"arcane": {"color": Color(0.3, 0.85, 1.0), "amount": 10, "life": 1.2, "size": 0.07, "grav": 0.25, "vel": 0.1, "r": 0.06},
	"storm": {"color": Color(0.35, 0.72, 1.0), "amount": 12, "life": 0.45, "size": 0.06, "grav": 0.0, "vel": 0.5, "r": 0.06},
	"crimson": {"color": Color(1.0, 0.2, 0.28), "amount": 10, "life": 1.0, "size": 0.07, "grav": 0.45, "vel": 0.1, "r": 0.06},
	"frost": {"color": Color(0.7, 0.92, 1.0), "amount": 10, "life": 1.5, "size": 0.07, "grav": -0.2, "vel": 0.08, "r": 0.06},
	"abyss": {"color": Color(0.66, 0.3, 1.0), "amount": 10, "life": 1.1, "size": 0.07, "grav": 0.35, "vel": 0.12, "r": 0.06},
	"radiant": {"color": Color(1.0, 0.82, 0.35), "amount": 10, "life": 0.9, "size": 0.07, "grav": 0.7, "vel": 0.15, "r": 0.06},
}


const SHEEN := preload("res://shaders/mythic_sheen.gdshader")


## Liga as partículas a todos os empties "Aura_*" do modelo do arco. Devolve quantos emissores criou.
static func attach(model: Node3D) -> int:
	if model == null:
		return 0
	var n := 0
	var first := ""
	for e in model.find_children("Aura_*", "Node3D", true, false):
		var kind := kind_of(e.name)
		if not KINDS.has(kind):
			continue
		if first == "":
			first = kind
		var k: Dictionary = KINDS[kind]
		var p := FXEpic.stream(e, "glow", k.color, int(k.amount), float(k.life), float(k.size))
		if p == null:   # servidor ou sem cena
			continue
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = float(k.r)
		p.gravity = Vector3(0, float(k.grav), 0)
		p.direction = Vector3.UP
		p.spread = 180.0
		p.initial_velocity_min = float(k.vel) * 0.5
		p.initial_velocity_max = float(k.vel)
		n += 1
	if first != "":
		add_sheen(model, KINDS[first].color)
	return n


## Brilho de metal encantado por cima do arco inteiro (borda, reflexo que corre, cintilas): só nos míticos.
static func add_sheen(model: Node3D, color: Color) -> void:
	var sm := ShaderMaterial.new()
	sm.shader = SHEEN
	sm.set_shader_parameter("glow_color", color)
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.material_overlay = sm


## "Aura_fire_3" -> "fire".
static func kind_of(node_name: String) -> String:
	var parts := node_name.split("_")
	return parts[1] if parts.size() >= 2 and parts[0] == "Aura" else ""
