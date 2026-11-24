class_name AcidPool
extends Node3D
## Poça de Ácido (Mãe-Verme): poça pintada no chão (WormFX.acid_pool) que dói enquanto se está dentro e some depois de `life` s.
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
var _paint: MeshInstance3D


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_paint = WormFX.acid_pool(self, radius)
	_paint.set_instance_shader_parameter("grow", 0.1)


func _physics_process(delta: float) -> void:
	_t += delta
	if _paint:   # a poça se espalha, ferve e some comida pela trama de bolhas
		_paint.set_instance_shader_parameter("grow", lerpf(0.1, 1.0, 1.0 - pow(1.0 - clampf(_t / 0.3, 0.0, 1.0), 2.0)))
		_paint.set_instance_shader_parameter("erode", clampf((_t - (life - 0.9)) / 0.9, 0.0, 1.0))
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
