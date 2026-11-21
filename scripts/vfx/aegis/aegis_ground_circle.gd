class_name AegisGroundCircle
extends Node3D
## Égide Cristalina: círculo mágico no chão (prefab scenes/vfx/aegis/aegis_ground_circle.tscn).
## O desenho é o da sprite sheet (anel de runas, hexagrama, emblema de escudo), feito por vetor no shader
## aegis_rune_circle para ficar nítido no chão; forma-se em `form_time` na ordem da sheet, com
## partículas de energia subindo rente ao chão. Fica filho do dono, então acompanha a posição dele.
## fade_out() apaga em manchas e para as partículas; quem é dono do nó decide quando liberá-lo.

@export var radius := 3.2
@export var form_time := 0.3
@export var motes_per_second := 22
@export var spin_speed := 0.25   ## rad/s do desenho

@onready var circle: MeshInstance3D = $Circle
@onready var motes: CPUParticles3D = $Motes

var boost := 0.0        ## brilho extra (golpe recebido); decai sozinho
var _t := 0.0
var _spin := 0.0
var _fade_t := -1.0
var _fade_time := 1.0


func _ready() -> void:
	setup()


## Aplica radius/form_time/motes_per_second (chame de novo se mudar depois de entrar na árvore).
func setup() -> void:
	# material próprio: os parâmetros do círculo são do material, não por instância (ver aegis_rune_circle)
	if circle.material_override and not circle.has_meta("own_mat"):
		circle.material_override = circle.material_override.duplicate()
		circle.set_meta("own_mat", true)
	circle.scale = Vector3(radius * 2.0, 1.0, radius * 2.0)
	motes.emission_ring_radius = radius * 0.95
	motes.emission_ring_inner_radius = radius * 0.5
	motes.amount = maxi(1, int(round(float(motes_per_second) * motes.lifetime)))
	motes.emitting = motes_per_second > 0
	_apply()


## Some em `time` segundos (as partículas que já saíram terminam a vida delas).
func fade_out(time: float) -> void:
	if _fade_t >= 0.0:
		return
	_fade_t = 0.0
	_fade_time = maxf(time, 0.01)
	motes.emitting = false


func is_faded() -> bool:
	return _fade_t >= _fade_time


## 0..1: quanto do círculo já foi desenhado.
func formed() -> float:
	return clampf(_t / maxf(form_time, 0.001), 0.0, 1.0)


func _process(delta: float) -> void:
	_t += delta
	_spin += delta * spin_speed
	boost = move_toward(boost, 0.0, delta * 2.5)
	if _fade_t >= 0.0:
		_fade_t += delta
	_apply()


func _apply() -> void:
	var f := formed()
	var erode := 0.0 if _fade_t < 0.0 else clampf(_fade_t / _fade_time, 0.0, 1.0)
	var m := circle.material_override as ShaderMaterial
	m.set_shader_parameter("form", 1.0 - pow(1.0 - f, 2.0))
	m.set_shader_parameter("erode", erode)
	m.set_shader_parameter("spin", _spin)
	m.set_shader_parameter("intensity", (1.0 + boost) * (1.0 - erode * 0.5))
