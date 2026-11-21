class_name AegisRings
extends Node3D
## Égide Cristalina: anéis giratórios sobre o círculo do chão (prefab scenes/vfx/aegis/aegis_rings.tscn).
## Dois anéis tracejados (shader aegis_ring) girando devagar em sentidos opostos, um pouco acima do chão.

@export var radius := 3.2
@export var speed := 0.7          ## rad/s do anel de dentro; o de fora gira ao contrário a 70%
@export var fade_in_time := 0.25

@onready var inner: MeshInstance3D = $Inner
@onready var outer: MeshInstance3D = $Outer

var _t := 0.0
var _fade := 1.0
var _fade_speed := 0.0   ## > 0 apagando
var boost := 0.0


func _ready() -> void:
	setup()


## Aplica radius (chame de novo se mudar depois de entrar na árvore).
func setup() -> void:
	inner.scale = Vector3(radius * 2.0, 1.0, radius * 2.0)
	outer.scale = Vector3(radius * 2.0, 1.0, radius * 2.0)
	_apply()


func fade_out(time: float) -> void:
	_fade_speed = 1.0 / maxf(time, 0.01)


func is_faded() -> bool:
	return _fade <= 0.0


## Ângulo atual de cada anel (teste: confirmam que giram em sentidos opostos).
func angles() -> Vector2:
	return Vector2(inner.rotation.y, outer.rotation.y)


func _process(delta: float) -> void:
	_t += delta
	inner.rotation.y = wrapf(inner.rotation.y + speed * delta, -PI, PI)
	outer.rotation.y = wrapf(outer.rotation.y - speed * 0.7 * delta, -PI, PI)
	boost = move_toward(boost, 0.0, delta * 2.5)
	if _fade_speed > 0.0:
		_fade = maxf(0.0, _fade - _fade_speed * delta)
	_apply()


func _apply() -> void:
	var a := clampf(_t / maxf(fade_in_time, 0.001), 0.0, 1.0) * _fade
	for ring in [inner, outer]:
		ring.set_instance_shader_parameter("fade", a)
		ring.set_instance_shader_parameter("intensity", 1.0 + boost)
