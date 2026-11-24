class_name SporeCloud
extends Node3D
## Nuvem de Esporos (Espinheira, na fúria): mofo rente ao chão que cresce de ThornRules.SPORE_R0 até SPORE_R1 m em
## SPORE_LIFE s; quem fica dentro leva dano a cada TICK s e fica envenenado (lento). Servidor e cliente criam a
## nuvem no mesmo ponto; só quem manda no chefe (`deal`: servidor ou solo) dá o dano.
## Desenho (ThornFX.Mold): o mofo pintado no chão marca a área, com esporos 3D subindo e cogumelos na borda.

const TICK := 0.6

## Dano por tique, já com o multiplicador do chefe; o nível ajusta contra cada jogador.
var dmg := 5.0
var level := 0
var deal := false
var _t := 0.0
var _tick := 0.0
var _mold: ThornFX.Mold


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_mold = ThornFX.Mold.new()
	_mold.life = ThornRules.SPORE_LIFE
	_mold.radius = radius()
	add_child(_mold)


func radius() -> float:
	return ThornRules.spore_radius(_t)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= ThornRules.SPORE_LIFE:
		queue_free()
		return
	if _mold:
		_mold.radius = radius()
		_mold.age = _t
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
