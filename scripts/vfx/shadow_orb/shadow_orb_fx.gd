class_name ShadowOrbFX
extends Node3D
## Esfera Sombria: bola de riscos de fumaça quase preta saindo torcidos de um miolo escuro, com o violeta só nas
## pontas mais claras. Feita em código sobre duas pinturas (claro em fundo preto):
##   swirl   quatro quads virados para a câmera com vortice_riscos.png girando no plano (orb_swirl.gdshader), em
##           velocidades, sentidos e tamanhos diferentes: o volume e o borrão do giro; a de trás fecha o miolo
##   shell   duas cascas de esfera com fios_faixa.png correndo (orb_shell.gdshader), inclinadas e girando: os arcos
##           finos em volta
##   light   luz violeta fraca
## Fica enquanto o dono existir (o projétil); `radius` = raio da bola (m), `intensity` apaga tudo junto.
## Em jogo: o projétil do Esqueleto Mago (EnemyArrow, orbe `magic` que não é ácido nem gelo).

const STREAKS := preload("res://assets/vfx/shadow_orb/vortice_riscos.png")
const STRANDS := preload("res://assets/vfx/shadow_orb/fios_faixa.png")
const SWIRL := preload("res://shaders/shadow_orb/orb_swirl.gdshader")
const SHELL := preload("res://shaders/shadow_orb/orb_shell.gdshader")
const VIOLET := Color(0.62, 0.5, 1.0)
const DARK := Vector3(0.004, 0.002, 0.009)
## Camadas de riscos: tamanho (x o raio), velocidade do giro (rad/s, o sinal é o sentido), espelhada, quanto do
## violeta aparece, miolo fechado.
const LAYERS := [
	{"size": 2.5, "speed": -2.6, "flip": 0.0, "glow": 0.0, "core": 1.0},
	{"size": 2.9, "speed": 4.4, "flip": 1.0, "glow": 0.85, "core": 0.0},
	{"size": 2.2, "speed": -6.8, "flip": 0.0, "glow": 0.45, "core": 0.0},
	{"size": 3.3, "speed": 1.7, "flip": 1.0, "glow": 1.0, "core": 0.0},
]

var radius := 0.45
var intensity := 1.0
var color := VIOLET

var _swirls: Array[MeshInstance3D] = []
var _shells: Array[MeshInstance3D] = []
var _light: OmniLight3D
var _t := 0.0


func _ready() -> void:
	var sm := ShaderMaterial.new()
	sm.shader = SWIRL
	sm.set_shader_parameter("streaks", STREAKS)
	var quad := QuadMesh.new()
	var gv := Vector3(color.r, color.g, color.b)
	for i in LAYERS.size():
		var l: Dictionary = LAYERS[i]
		var mat := sm.duplicate() as ShaderMaterial
		mat.render_priority = i
		var n := MeshInstance3D.new()
		n.mesh = quad
		n.material_override = mat
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.extra_cull_margin = radius * 4.0
		n.set_instance_shader_parameter("spin_speed", float(l.speed))
		n.set_instance_shader_parameter("phase", randf() * TAU)
		n.set_instance_shader_parameter("flip", float(l.flip))
		n.set_instance_shader_parameter("glow_amt", float(l.glow))
		n.set_instance_shader_parameter("core", float(l.core))
		n.set_instance_shader_parameter("glow", gv)
		n.set_instance_shader_parameter("dark", DARK)
		n.set_instance_shader_parameter("intensity", 1.0)
		n.set_instance_shader_parameter("blur", 2.6 if i == 0 else 1.6 + 0.5 * float(i % 2))
		n.scale = Vector3.ONE * radius * float(l.size)
		add_child(n)
		_swirls.append(n)

	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 32
	ball.rings = 16
	var shm := ShaderMaterial.new()
	shm.shader = SHELL
	shm.set_shader_parameter("strands", STRANDS)
	shm.render_priority = LAYERS.size()
	for i in 2:
		var n := MeshInstance3D.new()
		n.mesh = ball
		n.material_override = shm
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.set_instance_shader_parameter("flow", 1.6 if i == 0 else -2.3)
		n.set_instance_shader_parameter("phase", randf())
		n.set_instance_shader_parameter("glow", gv)
		n.set_instance_shader_parameter("dark", DARK)
		n.scale = Vector3.ONE * radius * (1.05 if i == 0 else 1.25)
		n.rotation = Vector3(0.9 + i * 1.3, randf() * TAU, 0.4 - i * 1.1)
		add_child(n)
		_shells.append(n)

	_light = OmniLight3D.new()
	_light.light_color = color
	_light.shadow_enabled = false
	_light.omni_range = maxf(3.0, radius * 5.0)
	add_child(_light)
	_apply()


func _process(delta: float) -> void:
	_t += delta
	for i in _shells.size():
		_shells[i].rotate_object_local(Vector3.UP, delta * (2.4 if i == 0 else -3.1))
	_apply()


func _apply() -> void:
	for n in _swirls:
		n.set_instance_shader_parameter("intensity", intensity)
	for n in _shells:
		n.set_instance_shader_parameter("intensity", intensity * 0.9)
	_light.light_energy = 0.6 * intensity
