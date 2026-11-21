class_name MoltenTrail
extends Node3D
## Faixa de metal derretido (Forjador Rúnico): a Martelada deixa faixas incandescentes no chão, dentro do cone.
## Ficam `life` s; quem pisa leva dano a cada ForgeRules.TRAIL_TICK s. Servidor e cliente criam a faixa no mesmo
## lugar (origem e direção do golpe); só quem manda no chefe (`deal`: servidor ou solo) dá o dano.
## Desenho: a faixa incandescente no chão (shaders/fx_molten) que esfria com o tempo, borbulhas de fogo carmim e
## fagulhas subindo.

const SHADER := preload("res://shaders/fx_molten.gdshader")
const PUFF_EVERY := 0.28

## De onde saiu o golpe e para onde a faixa corre (no plano, normalizada).
var origin := Vector3.ZERO
var dir := Vector3.BACK
var life := ForgeRules.TRAIL_LIFE
## Dano por tique, já com o multiplicador do chefe; o nível ajusta contra cada jogador.
var dmg := 5.0
var level := 0
var deal := false
var _t := 0.0
var _tick := 0.0
var _puff_t := 0.0
var _strip: MeshInstance3D

static var _mesh: PlaneMesh


func _ready() -> void:
	global_position = ForgeRules.trail_center(origin, dir)
	rotation.y = atan2(dir.x, dir.z)
	if DisplayServer.get_name() == "headless":
		return
	if _mesh == null:
		_mesh = PlaneMesh.new()
		_mesh.size = Vector2(ForgeRules.TRAIL_HALF * 2.6, ForgeRules.trail_len() + 0.8)
		var m := ShaderMaterial.new()
		m.shader = SHADER
		_mesh.material = m
	_strip = MeshInstance3D.new()
	_strip.mesh = _mesh
	_strip.position.y = 0.07
	_strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_strip.sorting_offset = -0.4
	_strip.set_instance_shader_parameter("seed", randf() * 30.0)
	_strip.set_instance_shader_parameter("aspect", _mesh.size.y / _mesh.size.x)
	_strip.set_instance_shader_parameter("heat", 1.0)
	_strip.set_instance_shader_parameter("fade", 0.0)
	add_child(_strip)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= life:
		queue_free()
		return
	if _strip:
		_strip.set_instance_shader_parameter("heat", clampf(1.0 - _t / (life * 0.85), 0.0, 1.0))
		_strip.set_instance_shader_parameter("fade", clampf((_t - (life - 0.9)) / 0.9, 0.0, 1.0))
		_puff_t -= delta
		if _puff_t <= 0.0 and _t < life - 1.0:
			_puff_t = PUFF_EVERY
			var along := randf_range(-0.5, 0.5) * ForgeRules.trail_len()
			var at := global_position + dir * along + dir.cross(Vector3.UP) * randf_range(-0.5, 0.5) * ForgeRules.TRAIL_HALF
			FXToon.puff(at + Vector3.UP * 0.25, randf_range(0.5, 0.85), FXToon.HELLFIRE,
				{"vel": Vector3(0, 1.1, 0), "grow": 0.14, "hold": 0.08, "fade": 0.4})
			if randf() < 0.5:
				FX.burst(at + Vector3.UP * 0.15, Color(1.0, 0.55, 0.15), 3, 2.2, 0.06, 0.5, -3.0)
	if not deal:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = ForgeRules.TRAIL_TICK
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead or absf(p.global_position.y - origin.y) > 2.5:
			continue
		if ForgeRules.in_trail(origin, dir, p.global_position):
			p.take_damage(Enemy.vs(level, p, dmg), p.global_position - dir * 0.5)
