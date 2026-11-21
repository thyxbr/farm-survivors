class_name MagicCircle
extends Node3D
## Martelo de Energia: o círculo mágico suspenso (prefab scenes/vfx/hammer/magic_circle.tscn), deitado e com a face
## para baixo e para cima (o martelo sai de dentro dele). Duas camadas que giram juntas devagar:
##   Sheet  quadros 2-9 da sprite sheet (o círculo se materializando: anel, hexagrama, runas), aditivo
##   Runes  o mesmo desenho por vetor (hammer_rune_circle.gdshader), nítido de perto, com o miolo azul
## mais filamentos de energia correndo pela borda e partículas orbitando (CPUParticles3D, presas ao círculo).
## materialize(): aparece do centro para fora, com faíscas na frente do traço.
## close(): animação própria de fechamento: anéis e runas se contraem para o centro girando cada vez mais rápido,
## a sheet volta os quadros (perde os detalhes), o brilho sobe até um ponto e solta uma pequena explosão de
## partículas. Emite `closed` no fim; a explosão termina sozinha e o nó fica invisível (o dono o libera).

signal closed

@export var config: HammerConfig

@onready var spin_node: Node3D = $Spin
@onready var sheet: HammerSheet = $Spin/Sheet
@onready var runes: MeshInstance3D = $Spin/Runes
@onready var orbit: CPUParticles3D = $Orbit
@onready var filaments: CPUParticles3D = $Filaments
@onready var burst: CPUParticles3D = $Burst
@onready var light: OmniLight3D = $Light

enum State { IDLE, FORMING, HOLD, CLOSING, CLOSED }
var state := State.IDLE
var spin_angle := 0.0
var _mat: ShaderMaterial
var _t := 0.0
var _dur := 1.0
var _spin_mult := 1.0
var _base_scale := 1.0


func _ready() -> void:
	if config == null:
		config = load("res://assets/vfx/hammer/hammer_config.tres")
	_mat = (runes.material_override as ShaderMaterial).duplicate()
	runes.material_override = _mat
	setup(config)


## Tamanhos pelo `cfg` (o HammerSkill chama com a configuração dele).
func setup(cfg: HammerConfig) -> void:
	config = cfg
	var r := config.circle_radius
	_base_scale = r
	runes.scale = Vector3.ONE * r
	sheet.scale = Vector3.ONE * r * 2.25   # o desenho ocupa ~89% do quadro
	orbit.emission_ring_radius = r * 1.08
	orbit.emission_ring_inner_radius = r * 0.92
	filaments.emission_ring_radius = r * 0.98
	filaments.emission_ring_inner_radius = r * 0.94
	burst.emission_sphere_radius = r * 0.3
	var glow_mat := FXEpic._particle_mat(FXEpic._glow_tex(), true, true)
	(orbit.mesh as QuadMesh).material = glow_mat
	filaments.mesh = FXEpic._spark_mesh()   # sem billboard: o align_y estica na direção em que correm
	(burst.mesh as QuadMesh).material = glow_mat
	_set_form(0.0)
	_mat.set_shader_parameter("contract", 0.0)
	visible = false


## Começa a materialização (s).
func materialize(time: float) -> void:
	state = State.FORMING
	_t = 0.0
	_dur = maxf(time, 0.01)
	visible = true
	sheet.play(HammerSheet.CIRCLE_FORM, _dur)
	orbit.emitting = true
	filaments.emitting = true


## Começa o fechamento (s). `quick` = cancelado: sem a explosão no fim, só se apaga.
func close(time: float, quick := false) -> void:
	if state == State.CLOSING or state == State.CLOSED:
		return
	state = State.CLOSING
	set_meta("quick", quick)
	_t = 0.0
	_dur = maxf(time, 0.01)
	visible = true
	sheet.play_reverse(HammerSheet.CIRCLE_FORM, _dur)
	orbit.emitting = false
	filaments.emitting = false


func formed() -> float:
	if state == State.FORMING:
		return clampf(_t / _dur, 0.0, 1.0)
	return 1.0 if state == State.HOLD or state == State.CLOSING else 0.0


func is_closed() -> bool:
	return state == State.CLOSED


func _set_form(f: float) -> void:
	_mat.set_shader_parameter("form", f)
	sheet.set_param("reveal", clampf(f * 1.3, 0.0, 1.0))
	light.light_energy = 2.2 * f


func _process(delta: float) -> void:
	_t += delta
	spin_angle += config.circle_spin * _spin_mult * delta
	spin_node.rotation.y = spin_angle
	_mat.set_shader_parameter("spin", spin_angle * 0.5)
	match state:
		State.FORMING:
			var u := clampf(_t / _dur, 0.0, 1.0)
			_set_form(u)
			# energia se juntando: cresce do miolo com um tranco no fim
			var s := lerpf(0.55, 1.0, ease_out_back(u))
			spin_node.scale = Vector3(s, 1.0, s)
			if u >= 1.0:
				state = State.HOLD
				sheet.play(HammerSheet.CIRCLE_HOLD, 0.6, true)
		State.HOLD:
			# respira de leve enquanto o martelo sai
			light.light_energy = 2.2 + 0.4 * sin(_t * 9.0)
		State.CLOSING:
			var u := clampf(_t / _dur, 0.0, 1.0)
			_mat.set_shader_parameter("contract", u)
			_spin_mult = 1.0 + 9.0 * u * u
			var s := maxf(1.0 - u * u * 0.85, 0.05)
			spin_node.scale = Vector3(s, 1.0, s)
			sheet.intensity = 1.0 - u * 0.6
			light.light_energy = 2.2 + 4.0 * u
			if u >= 1.0:
				_finish_close()
		State.CLOSED:
			light.light_energy = maxf(0.0, light.light_energy - 18.0 * delta)


func _finish_close() -> void:
	state = State.CLOSED
	spin_node.visible = false
	if not bool(get_meta("quick", false)):
		burst.restart()
		burst.emitting = true
		FXEpic.glow_burst(global_position, Color(1.0, 0.75, 0.35), 26, 5.0, 0.12, 0.6, 0.0)
		FXEpic.flash(global_position, Color(1.0, 0.85, 0.6), 5.0, 7.0, 0.25)
		Sfx.play_at("zap", global_position, 0.1, -6.0)
	closed.emit()


## Terminou tudo (fechado e a explosão acabou)?
func finished() -> bool:
	return state == State.CLOSED and not burst.emitting and light.light_energy <= 0.01


static func ease_out_back(x: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)
