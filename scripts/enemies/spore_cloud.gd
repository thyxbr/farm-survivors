class_name SporeCloud
extends Node3D
## Nuvem de Esporos (Espinheira, na fúria): névoa doentia rente ao chão que cresce de ThornRules.SPORE_R0 até
## SPORE_R1 m em SPORE_LIFE s; quem fica dentro leva dano a cada TICK s e fica envenenado (lento). Servidor e
## cliente criam a nuvem no mesmo ponto; só quem manda no chefe (`deal`: servidor ou solo) dá o dano.
## Desenho: um disco de mancha no chão (o "desenho embaixo da área") e tufos de fumaça BLIGHT soltos por cima.

const TICK := 0.6
const PUFF_EVERY := 0.35

## Dano por tique, já com o multiplicador do chefe; o nível ajusta contra cada jogador.
var dmg := 5.0
var level := 0
var deal := false
var _t := 0.0
var _tick := 0.0
var _puff_t := 0.0
var _disc: MeshInstance3D
var _mat: StandardMaterial3D


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_disc = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 0.03
	cyl.radial_segments = 28
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(0.36, 0.62, 0.16, 0.0)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cyl.material = _mat
	_disc.mesh = cyl
	_disc.position.y = 0.06
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_disc)
	# a borda: anel arroxeado mais escuro, para ler o limite da nuvem no chão
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.93
	tor.outer_radius = 1.0
	tor.rings = 40
	tor.ring_segments = 4
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(0.3, 0.06, 0.36, 0.75)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tor.material = rm
	ring.mesh = tor
	ring.scale = Vector3(1.0, 0.05, 1.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_disc.add_child(ring)
	_resize()


func radius() -> float:
	return ThornRules.spore_radius(_t)


func _resize() -> void:
	if _disc:
		var r := radius()
		_disc.scale = Vector3(r, 1.0, r)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= ThornRules.SPORE_LIFE:
		queue_free()
		return
	if _mat:
		_resize()
		var fade := clampf(_t / 0.5, 0.0, 1.0) * clampf((ThornRules.SPORE_LIFE - _t) / 1.0, 0.0, 1.0)
		_mat.albedo_color.a = (0.32 + sin(_t * 3.0) * 0.05) * fade
		_puff_t -= delta
		if _puff_t <= 0.0 and fade > 0.3:
			_puff_t = PUFF_EVERY
			var r := radius()
			var a := randf() * TAU
			var d := sqrt(randf()) * r * 0.8
			FXToon.puff(global_position + Vector3(cos(a) * d, 0.35, sin(a) * d), randf_range(0.9, 1.4) * (0.6 + r * 0.2),
				FXToon.BLIGHT, {"vel": Vector3(0, 0.45, 0), "grow": 0.35, "hold": 0.5, "fade": 0.9})
	if not deal:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	var r := radius()
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead:
			continue
		var d := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length()
		if d <= r and absf(p.global_position.y - global_position.y) < 2.5:
			p.take_damage(Enemy.vs(level, p, dmg), global_position)
			if p.has_method("apply_chill"):
				p.apply_chill(1.2, true)
