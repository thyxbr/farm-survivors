class_name StatusAura
extends Node3D
## Status elemental no corpo de um monstro (StatusEffects): o corpo tingido na cor do efeito, com contorno de luz
## por cima, e poucas partículas
## pequenas do elemento, no estilo das auras de buff (BuffAura): chamas arredondadas subindo (fogo), névoa fria
## e cristais (gelo), bolhas e gotas verdes (veneno). Congelado é só o contorno forte, como uma casca de gelo.
## Filho do modelo do monstro (escala junto). Só o efeito de maior prioridade aparece; os outros esperam.
## Em horda grande só MAX_PARTICLE_AURAS auras ganham partícula ao mesmo tempo; as outras ficam no contorno e
## tentam de novo no próximo set_mask.

const MAX_PARTICLE_AURAS := 12
const PRIORITY := ["congelado", "fogo", "veneno", "gelo"]
const RIM := {
	"congelado": Color(0.85, 0.97, 1.0), "fogo": Color(1.0, 0.45, 0.1),
	"veneno": Color(0.4, 0.95, 0.25), "gelo": Color(0.45, 0.85, 1.0),
}
## Tinta do corpo (alfa = quanto cobre). Leve: o monstro continua reconhecível; o contorno e as partículas
## completam a leitura (o contorno aditivo sozinho some sob o sol).
const TINT := {
	"congelado": Color(0.75, 0.92, 1.0, 0.26), "fogo": Color(1.0, 0.42, 0.08, 0.2),
	"veneno": Color(0.45, 0.95, 0.1, 0.2), "gelo": Color(0.5, 0.85, 1.0, 0.18),
}

static var _slots := 0

## Altura e raio do corpo no espaço do modelo (o Enemy passa os da ficha).
var height := 1.0
var radius := 0.35
## Camada para o Enemy pôr nas malhas: tinta com o contorno como next_pass (null = nenhum efeito).
var rim: Material = null
var _shown := ""
var _fx: Node3D = null
var _has_slot := false


static func particle_slots_used() -> int:
	return _slots


## Efeito que está aparecendo ("" = nenhum).
func shown() -> String:
	return _shown


func has_particles() -> bool:
	return _fx != null


func set_mask(m: int) -> void:
	var want := ""
	for el in PRIORITY:
		if m & int(StatusRules.BITS[el]) != 0:
			want = el
			break
	if want == _shown and (want == "" or want == "congelado" or _fx != null):
		return
	_clear_fx()
	_shown = want
	rim = null if want == "" else _rim_for(want)
	if want == "" or want == "congelado":
		return
	if _slots >= MAX_PARTICLE_AURAS:
		return
	_slots += 1
	_has_slot = true
	_fx = _build(want)
	add_child(_fx)


func _exit_tree() -> void:
	_clear_fx()


func _clear_fx() -> void:
	if _fx != null:
		_fx.queue_free()
		_fx = null
	if _has_slot:
		_slots -= 1
		_has_slot = false


func _rim_for(el: String) -> Material:
	var tint := StandardMaterial3D.new()
	tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tint.albedo_color = TINT[el]
	tint.render_priority = 2   # depois da gelatina do slime (transparente, prioridade 0/1), senão ela cobre a tinta
	var m := ShaderMaterial.new()
	m.shader = BuffAura.SH_RIM
	m.set_shader_parameter("color", RIM[el])
	m.set_shader_parameter("color2", RIM[el])
	m.set_shader_parameter("strength", 1.8 if el == "congelado" else 1.6)
	m.set_shader_parameter("pulse_speed", 0.0 if el == "congelado" else 2.4)
	m.set_shader_parameter("rise", 1.0 if el == "fogo" else 0.0)
	m.render_priority = 3
	tint.next_pass = m
	return tint


## Partícula em mistura normal: a soma (ADD) das auras de buff estoura no chão claro e não aparece de dia.
static func _solid(p: CPUParticles3D) -> CPUParticles3D:
	var m := (p.mesh.surface_get_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	p.mesh.surface_set_material(0, m)
	return p


func _build(el: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Status_" + el
	var r := radius
	var h := height
	match el:
		"fogo":   # chamas arredondadas saindo do corpo todo + poucas brasas
			var f := BuffAura._flames(Color(1.0, 0.78, 0.3), Color(1.0, 0.25, 0.02), 24, r, 0.55)
			f.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			f.emission_box_extents = Vector3(r * 0.9, h * 0.3, r * 0.9)
			f.position.y = h * 0.45
			root.add_child(f)
			root.add_child(_solid(BuffAura._emitter({"color": Color(1.0, 0.55, 0.15), "amount": 6, "life": 1.1,
				"radius": r * 0.8, "y": h * 0.6, "vel": Vector2(0.6, 1.1), "size": 0.06, "spread": 25.0})))
		"veneno":   # bolhas verdes subindo + gotas pingando
			root.add_child(_solid(BuffAura._emitter({"color": Color(0.3, 0.8, 0.05), "amount": 10, "life": 1.5,
				"radius": r * 0.9, "y": h * 0.5, "vel": Vector2(0.3, 0.6), "size": 0.34})))
			var drip := _solid(BuffAura._emitter({"color": Color(0.3, 0.75, 0.1), "amount": 6, "life": 0.8,
				"shape": "sphere", "radius": r * 0.7, "y": h * 0.55, "vel": Vector2(0.0, 0.05), "size": 0.12}))
			drip.gravity = Vector3(0, -3.0, 0)
			root.add_child(drip)
		"gelo":   # névoa fria baixa em puffs redondos + cristais pequenos piscando
			root.add_child(_solid(BuffAura._emitter({"color": Color(0.85, 0.95, 1.0, 0.7), "amount": 7, "life": 1.8,
				"radius": r * 1.1, "y": 0.05, "vel": Vector2(0.05, 0.2), "size": 0.32})))
			root.add_child(_solid(BuffAura._emitter({"tex": "star", "color": Color(0.7, 0.92, 1.0), "amount": 5,
				"life": 1.0, "shape": "sphere", "radius": r, "y": h * 0.5, "vel": Vector2(0.0, 0.05), "size": 0.16,
				"twinkle": true})))
	return root
