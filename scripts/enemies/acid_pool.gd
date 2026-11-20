class_name AcidPool
extends Node3D
## Poça de Ácido (Mãe-Verme): disco verde no chão que dói enquanto se está dentro e some depois de `life` s.
## Servidor e cliente criam a poça no mesmo ponto; só quem manda no chefe (`deal`: servidor ou solo) dá o dano.

const TICK := 0.5

var radius := 1.8
var life := 6.0
## Dano por tique (a cada TICK s), já com o multiplicador do chefe; o nível ajusta contra cada jogador.
var dmg := 5.0
var level := 0
var deal := false
var _t := 0.0
var _tick := 0.0
var _mat: StandardMaterial3D


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mi := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.04
	disc.radial_segments = 20
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.42, 0.95, 0.15, 0.6)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.emission_enabled = true
	_mat.emission = Color(0.35, 0.9, 0.1)
	_mat.emission_energy_multiplier = 0.8
	disc.material = _mat
	mi.mesh = disc
	mi.position.y = 0.05
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _physics_process(delta: float) -> void:
	_t += delta
	if _mat:
		var bubble := 0.5 + sin(_t * 6.0) * 0.08
		_mat.albedo_color.a = bubble * clampf((life - _t) / 0.8, 0.0, 1.0)
	if _t >= life:
		queue_free()
		return
	if not deal:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead:
			continue
		var d := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length()
		if d <= radius and absf(p.global_position.y - global_position.y) < 2.0:
			p.take_damage(Enemy.vs(level, p, dmg), global_position)
