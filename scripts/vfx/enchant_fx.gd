class_name EnchantFX
extends RefCounted
## Visual de arma encantada. Cor = elemento, força = nível (1..MAX_LEVEL). Duas partes:
##  - brilho por cima da arma (shader enchant_overlay): tom no +1, borda pulsando no +2,
##    faixas de energia correndo pela lâmina do +3 em diante;
##  - efeito desenhado em volta da lâmina (EnchantBlade), com a cara do elemento: feixes de raio,
##    labaredas, cristais de gelo, gotas de veneno, estrelas, fumaça de sombra; cresce a cada nível.

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
	# efeito desenhado do elemento em volta da lâmina, maior a cada nível (ver EnchantBlade)
	var blade := EnchantBlade.make(element, e, tip_pos, level)
	blade.set_meta("enchant_fx", true)
	holder.add_child(blade)


static func _collect_meshes(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		_collect_meshes(c, out)
