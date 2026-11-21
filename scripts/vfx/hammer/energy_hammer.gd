class_name EnergyHammer
extends Node3D
## Martelo de Energia: o martelo 3D (prefab scenes/vfx/hammer/energy_hammer.tscn), um objeto independente da sprite
## sheet. Geometria provisória feita de primitivas (MeshInstance3D): cabeça de martelo de guerra com as faces
## douradas, faixa rúnica no meio, aletas, selos rúnicos nas laterais, colar, cabo com anéis dourados e pomo, e um
## cristal branco no miolo da cabeça. Todas as peças usam o mesmo material de energia (hammer_energy.gdshader,
## duplicado aqui por martelo); cada peça diz por instance uniform se é dourada (`accent`), tem runas ou é miolo.
## A origem é a base da cabeça (onde bate no chão) e o cabo sobe em +Y: pendurado assim, a cabeça fica para baixo.
## O modelo foi feito com BASE_LENGTH m; `setup` escala para HammerConfig.hammer_size.

const BASE_LENGTH := 3.6

@onready var body: Node3D = $Body
@onready var light: OmniLight3D = $Light
@onready var trail_l: Node3D = $Body/TrailL
@onready var trail_r: Node3D = $Body/TrailR

var length := BASE_LENGTH
var mat: ShaderMaterial
var _glow := 1.0


func setup(cfg: HammerConfig) -> void:
	length = cfg.hammer_size
	var s := length / BASE_LENGTH
	body.scale = Vector3.ONE * s
	light.position = Vector3(0, 0.6 * s, 0)
	light.omni_range = 7.0 * s
	var base: ShaderMaterial = load("res://assets/vfx/hammer/hammer_energy_mat.tres")
	mat = base.duplicate()
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.material_override == base or m.material_override == null:
			m.material_override = mat
	for q in body.find_children("Seal*", "MeshInstance3D", true, false):
		var sm: ShaderMaterial = (q as MeshInstance3D).material_override
		if sm and sm != mat:
			(q as MeshInstance3D).material_override = sm.duplicate()
	set_solidity(1.0)
	set_glow(1.0)
	set_crack(0.0)
	clear_clip()
	set_dissolve(-10000.0)


## Nada acima desta altura (mundo) aparece: o martelo saindo de dentro do círculo.
func set_clip(world_y: float) -> void:
	mat.set_shader_parameter("clip_y", world_y)
	for q in _seals():
		q.visible = q.global_position.y < world_y


func clear_clip() -> void:
	mat.set_shader_parameter("clip_y", 10000.0)
	for q in _seals():
		q.visible = true


## 0..1: transparente na formação -> inteiro.
func set_solidity(v: float) -> void:
	mat.set_shader_parameter("solidity", clampf(v, 0.0, 1.0))


## Brilho geral (1 = cheio). A luz do miolo acompanha.
func set_glow(v: float) -> void:
	_glow = v
	mat.set_shader_parameter("glow", v)
	light.light_energy = 3.0 * v
	for q in _seals():
		var sm := q.material_override as ShaderMaterial
		if sm:
			sm.set_shader_parameter("intensity", 0.9 * v)


func get_glow() -> float:
	return _glow


## 0..1: rachaduras de energia na superfície.
func set_crack(v: float) -> void:
	mat.set_shader_parameter("crack", clampf(v, 0.0, 1.0))


## Altura (mundo) até onde o martelo já se desfez, de baixo para cima (a cabeça vai primeiro).
func set_dissolve(world_y: float) -> void:
	mat.set_shader_parameter("dissolve_y", world_y)
	for q in _seals():
		if q.global_position.y < world_y:
			q.visible = false


## Base e topo (mundo) do martelo agora.
func bottom_y() -> float:
	return global_position.y


func top_y() -> float:
	return global_position.y + length


## Largura da cabeça (m), para as partículas da dissolução.
func head_width() -> float:
	return 1.75 * length / BASE_LENGTH


func _seals() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for q in body.find_children("Seal*", "MeshInstance3D", true, false):
		out.append(q as MeshInstance3D)
	return out
