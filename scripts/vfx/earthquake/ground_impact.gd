class_name GroundImpact
extends Node3D
## Terremoto Devastador: a explosão inicial, no instante em que o escudo toca o chão (scenes/vfx/earthquake/
## ground_impact.tscn), exatamente sob o ponto do golpe:
##   Core      clarão branco-azulado intenso (eq_flash.gdshader), curtíssimo
##   Flash     a explosão de energia da sprite sheet (EarthquakeSheet.BURST: estrela de luz abrindo em anel)
##   InitRing  a onda circular inicial de energia: um anel rápido e pequeno, rente ao chão (disco que segue o relevo)
##   Light     a luz do clarão
##   AnimationPlayer ("impact"): a curva do clarão e da luz (`flash`, `core`), ajustável no editor
## A poeira e as pedras do impacto são do EarthquakeDust e do RockDebris. Tudo multiplicado por
## EarthquakeConfig.impact_intensity. Se libera sozinho no fim.

const INIT_RING_RADIUS := 3.2
const INIT_RING_TIME := 0.28
const LIGHT_ENERGY := 9.0
const CORE_SIZE := 3.2

var config: EarthquakeConfig
var ground: EarthquakeGround
## 0..1: força do clarão e da luz (animado pelo AnimationPlayer).
@export var flash := 0.0:
	set(v):
		flash = v
		_apply()
## 0..1: tamanho do clarão (animado pelo AnimationPlayer).
@export var core := 0.0:
	set(v):
		core = v
		_apply()
var _ring_mat: ShaderMaterial
var _k := 1.0

@onready var core_mesh: MeshInstance3D = $Core
@onready var sheet: EarthquakeSheet = $Flash
@onready var init_ring: MeshInstance3D = $InitRing
@onready var light: OmniLight3D = $Light
@onready var anim: AnimationPlayer = $AnimationPlayer


func setup(cfg: EarthquakeConfig, g: EarthquakeGround) -> void:
	config = cfg
	ground = g


func _ready() -> void:
	_k = clampf(config.impact_intensity, 0.0, 3.0)
	var c := ground.local_at(Vector2.ZERO)
	core_mesh.position = c + Vector3.UP * 0.5
	light.position = c + Vector3.UP * 1.0
	light.omni_range = config.radius * 1.3
	sheet.place(c, 4.2 * clampf(_k, 0.5, 1.6))
	sheet.intensity = 1.25 * clampf(_k, 0.3, 1.6)
	sheet.play(EarthquakeSheet.BURST, 0.5)
	var ft := sheet.create_tween()
	ft.tween_interval(0.3)
	ft.tween_property(sheet, "intensity", 0.0, 0.25)
	# anel inicial: rápido e pequeno
	_ring_mat = (init_ring.material_override as ShaderMaterial).duplicate()
	init_ring.material_override = _ring_mat
	init_ring.mesh = ShockwaveRing.build_disc(ground, INIT_RING_RADIUS * 1.12, INIT_RING_RADIUS, 16, 64, 0.07)
	_ring_mat.set_shader_parameter("ring_width", 0.09)
	_ring_mat.set_shader_parameter("trail", 0.35)
	_ring_mat.set_shader_parameter("residual", 0.0)
	var rt := create_tween()
	rt.tween_method(_ring, 0.0, 1.0, INIT_RING_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rt.tween_method(_ring_fade, 1.0, 0.0, 0.2)
	anim.play("impact")
	anim.animation_finished.connect(func(_n: StringName) -> void: _finish())
	_apply()


func _ring(u: float) -> void:
	_ring_mat.set_shader_parameter("wave", u)
	_ring_mat.set_shader_parameter("intensity", 1.6 * _k)


func _ring_fade(v: float) -> void:
	_ring_mat.set_shader_parameter("intensity", 1.6 * _k * v)


func _apply() -> void:
	if not is_node_ready():
		return
	light.light_energy = LIGHT_ENERGY * flash * _k
	core_mesh.scale = Vector3.ONE * CORE_SIZE * maxf(core, 0.001) * sqrt(maxf(_k, 0.1))
	core_mesh.set_instance_shader_parameter("energy", flash * 2.5 * _k)
	core_mesh.visible = core > 0.01 and flash > 0.01


func _finish() -> void:
	# o último pedaço (a sheet apagando, o anel) já acabou junto; um quadro de folga
	queue_free.call_deferred()
