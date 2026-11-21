class_name HammerImpact
extends Node3D
## Martelo de Energia: a explosão no ponto em que o martelo bate (prefab scenes/vfx/hammer/hammer_impact.tscn).
##   Shock     onda de choque correndo pelo chão até o raio de dano (hammer_shockwave.gdshader)
##   Cracks    rachaduras luminosas do centro até a borda do raio e o chão queimado no miolo (hammer_ground, kind 1)
##   Burst     explosão em estrela da sprite sheet (quadros 48-53), dourada; BurstBlue = a mesma em azul elétrico
##   Rocks     fragmentos de pedra voando (CPUParticles3D com cubos de pedra)
##   Light     clarão azul-branco
## mais poeira, faíscas e bolas de energia azuis e douradas (FXEpic). `setup` antes de entrar na árvore; o nó se
## libera sozinho quando a última parte some.

@onready var shock: MeshInstance3D = $Shock
@onready var cracks: MeshInstance3D = $Cracks
@onready var burst: HammerSheet = $Burst
@onready var burst_blue: HammerSheet = $BurstBlue
@onready var rocks: CPUParticles3D = $Rocks
@onready var light: OmniLight3D = $Light

const SHOCK_TIME := 0.5
const CRACK_GROW := 0.22
const REF_RADIUS := 4.5   ## raio para o qual a explosão foi desenhada: maior que isso, ela cresce junto

var config: HammerConfig
var seed_value := 0
var _t := 0.0
var _shock_mat: ShaderMaterial
var _life := 3.0


func setup(cfg: HammerConfig, seed_v: int) -> void:
	config = cfg
	seed_value = seed_v


func _ready() -> void:
	if config == null:
		config = load("res://assets/vfx/hammer/hammer_config.tres")
	var k := config.explosion_intensity
	var r := config.radius
	var size_k := maxf(r / REF_RADIUS, 0.5)
	_shock_mat = (shock.material_override as ShaderMaterial).duplicate()
	shock.material_override = _shock_mat
	shock.scale = Vector3(r * 1.06, 1.0, r * 1.06)
	cracks.scale = Vector3(r, 1.0, r)
	cracks.set_instance_shader_parameter("seed", float(seed_value % 997) * 0.37)
	cracks.set_instance_shader_parameter("appear", 0.0)
	_life = maxf(config.crater_life, SHOCK_TIME + 0.4)
	burst.position.y = 1.2 * size_k
	burst_blue.position.y = 1.0 * size_k
	burst.scale = Vector3.ONE * 4.6 * size_k * maxf(k, 0.3)
	burst.play(HammerSheet.BURST, 0.55)
	burst.fade_out(0.75)
	burst_blue.scale = Vector3.ONE * 6.4 * size_k * maxf(k, 0.3)
	burst_blue.set_param("recolor", 1.0)
	burst_blue.intensity = 0.85
	burst_blue.play(Vector2i(48, 51), 0.4)
	burst_blue.fade_out(0.5)
	rocks.amount = maxi(4, int(30 * k * size_k))
	rocks.emission_sphere_radius = 0.6 * size_k
	rocks.initial_velocity_max = 7.0 * sqrt(size_k)
	light.omni_range = 11.0 * size_k
	rocks.restart()
	rocks.emitting = true
	light.light_energy = 6.0 * k
	var c := global_position
	FXEpic.glow_burst(c + Vector3.UP * 0.4, Color(0.3, 0.6, 1.0), int(46 * k), 9.0 * size_k, 0.2, 0.75, -3.0)
	FXEpic.glow_burst(c + Vector3.UP * 0.3, Color(1.0, 0.72, 0.28), int(30 * k), 7.0, 0.16, 0.6, -2.0)
	FXEpic.sparks(c + Vector3.UP * 0.2, Vector3.UP, Color(0.65, 0.85, 1.0), int(40 * k), 15.0, 0.55)
	FXEpic.sparks(c + Vector3.UP * 0.2, Vector3.UP, Color(1.0, 0.8, 0.4), int(24 * k), 11.0, 0.45)
	FXEpic.smoke(c + Vector3.UP * 0.3, Color(0.42, 0.38, 0.34, 0.6), int(16 * k), r * 0.45, 1.6)
	Sfx.play_at("slam", c, 0.04, 2.0)
	Sfx.play_at("explode", c, 0.08, -2.0)


func _process(delta: float) -> void:
	_t += delta
	var k := config.explosion_intensity
	var u := clampf(_t / SHOCK_TIME, 0.0, 1.0)
	_shock_mat.set_shader_parameter("progress", 1.0 - pow(1.0 - u, 2.2))
	_shock_mat.set_shader_parameter("intensity", 1.4 * k)
	shock.visible = u < 1.0
	cracks.set_instance_shader_parameter("appear", clampf(_t / CRACK_GROW, 0.0, 1.0))
	# as rachaduras apagam devagar e o chão queimado some no fim
	cracks.set_instance_shader_parameter("energy", clampf(1.0 - _t / (_life * 0.7), 0.0, 1.0))
	cracks.set_instance_shader_parameter("fade", clampf((_life - _t) / (_life * 0.3), 0.0, 1.0))
	light.light_energy = 6.0 * k * exp(-_t * 7.0)
	if _t >= _life and not rocks.emitting:
		queue_free()
