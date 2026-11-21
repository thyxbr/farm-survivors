class_name DarkMagicCircle
extends Node3D
## Círculo da Provocação Sombria: o círculo mágico no chão (prefab scenes/vfx/dark_taunt/dark_magic_circle.tscn).
## O DarkTauntSkill o põe deitado no terreno (FXToon.ground_frame: acompanha a altura e a inclinação do chão). Camadas:
##   Runes      o desenho por vetor (dark_rune_circle.gdshader): anéis, runas, hexagrama e o olho no meio; os anéis
##              giram em sentidos opostos (o giro é do shader, pelo parâmetro `spin`) e um véu de fumaça escura cobre
##              o disco
##   Sheet      quadros 1-10 da sprite sheet (o círculo se desenhando e a energia das runas), aditivo, com a
##              perspectiva desfeita (DarkSheet.fit_circle); gira devagar por inteiro
##   Filaments  filetes de energia violeta subindo do chão pela borda
##   Smoke      fumaça escura rente ao chão, dentro do disco
##   Motes      faíscas magenta subindo devagar de dentro do disco
##   Flakes     na dissipação, as runas viram pequenas partículas que sobem e somem
##   Light      luz roxa, fraca, que respira
## materialize(): se desenha por energia sombria (a borda corre, o anel de dentro corre ao contrário, o hexagrama se
## traça, o olho abre). dissipate(): perde a luz, as runas se desfazem em partículas, a fumaça se espalha e os anéis
## se contraem para o centro. finished() = tudo apagado (o dono libera).

@export var config: DarkTauntConfig

@onready var runes: MeshInstance3D = $Runes
@onready var sheet: DarkSheet = $Spin/Sheet
@onready var spin_node: Node3D = $Spin
@onready var filaments: CPUParticles3D = $Filaments
@onready var smoke: CPUParticles3D = $Smoke
@onready var motes: CPUParticles3D = $Motes
@onready var flakes: CPUParticles3D = $Flakes
@onready var light: OmniLight3D = $Light

enum State { IDLE, FORMING, HOLD, DISSIPATING, GONE }
var state := State.IDLE
var spin_angle := 0.0
var _mat: ShaderMaterial
var _t := 0.0
var _dur := 1.0
var _light_max := 1.6


func _ready() -> void:
	if config == null:
		config = load("res://assets/vfx/dark_taunt/dark_taunt_config.tres")
	_mat = (runes.material_override as ShaderMaterial).duplicate()
	runes.material_override = _mat
	setup(config)


## Tamanhos e intensidade pelo `cfg` (o DarkTauntSkill chama com a configuração dele).
func setup(cfg: DarkTauntConfig) -> void:
	config = cfg
	var r := config.radius
	var k := config.energy_intensity
	runes.scale = Vector3(r, 1.0, r)
	sheet.fit_circle(r)
	filaments.emission_ring_radius = r * 0.99
	filaments.emission_ring_inner_radius = r * 0.9
	smoke.emission_ring_radius = r * 0.8
	motes.emission_ring_radius = r * 0.85
	flakes.emission_ring_radius = r * 0.93
	flakes.emission_ring_inner_radius = r * 0.3
	filaments.amount = maxi(int(48 * clampf(k, 0.2, 2.5) * clampf(r / 6.0, 0.5, 2.0)), 4)
	smoke.amount = maxi(int(36 * clampf(k, 0.2, 2.5) * clampf(r / 6.0, 0.5, 2.0)), 4)
	motes.amount = maxi(int(40 * clampf(k, 0.2, 2.5)), 4)
	var glow_mat := FXEpic._particle_mat(FXEpic._glow_tex(), true, true)
	(motes.mesh as QuadMesh).material = glow_mat
	(flakes.mesh as QuadMesh).material = glow_mat
	filaments.mesh = FXEpic._spark_mesh()   # sem billboard: o align_y estica na direção em que sobem
	(smoke.mesh as QuadMesh).material = FXEpic._particle_mat(FXEpic._smoke_tex(), false, true)
	light.omni_range = r * 1.4
	_light_max = 1.6 * k
	_mat.set_shader_parameter("intensity", k)
	_mat.set_shader_parameter("form", 0.0)
	_mat.set_shader_parameter("fade", 0.0)
	_mat.set_shader_parameter("contract", 0.0)
	sheet.intensity = 0.0
	visible = false


## Começa a se desenhar (s).
func materialize(time: float) -> void:
	state = State.FORMING
	_t = 0.0
	_dur = maxf(time, 0.01)
	visible = true
	sheet.intensity = 0.7 * config.energy_intensity
	sheet.play(DarkSheet.CIRCLE_FORM, _dur)
	sheet.set_param("reveal", 0.0)
	filaments.emitting = true
	smoke.emitting = true
	motes.emitting = true


## Começa a dissipar (s): perde a luz, as runas viram partículas, os anéis se contraem.
func dissipate(time: float) -> void:
	if state == State.DISSIPATING or state == State.GONE:
		return
	if state == State.IDLE:
		state = State.GONE
		return
	state = State.DISSIPATING
	_t = 0.0
	_dur = maxf(time, 0.01)
	filaments.emitting = false
	motes.emitting = false
	smoke.emitting = false
	flakes.restart()
	flakes.emitting = true
	sheet.fade_out(_dur * 0.6)
	# a fumaça escura se espalha para fora e some
	FXEpic.smoke(global_position + Vector3.UP * 0.3, Color(0.06, 0.02, 0.1, 0.55), int(14 * config.energy_intensity) + 4,
		config.radius * 0.55, _dur * 1.2)


func formed() -> float:
	if state == State.FORMING:
		return clampf(_t / _dur, 0.0, 1.0)
	return 1.0 if state == State.HOLD or state == State.DISSIPATING else 0.0


## Tudo apagado (as partículas da dissipação também)?
func finished() -> bool:
	return state == State.GONE and not flakes.emitting and light.light_energy <= 0.01


func _process(delta: float) -> void:
	_t += delta
	spin_angle += config.circle_spin * delta
	spin_node.rotation.y = spin_angle * 0.35   # a sheet inteira gira devagar
	_mat.set_shader_parameter("spin", spin_angle)
	match state:
		State.FORMING:
			var u := clampf(_t / _dur, 0.0, 1.0)
			_mat.set_shader_parameter("form", u)
			sheet.set_param("reveal", clampf(u * 1.25, 0.0, 1.0))
			light.light_energy = _light_max * u
			if u >= 1.0:
				state = State.HOLD
				sheet.play(DarkSheet.CIRCLE_HOLD, 0.9, true)
		State.HOLD:
			light.light_energy = _light_max * (0.85 + 0.15 * sin(_t * 5.0))
		State.DISSIPATING:
			var u := clampf(_t / _dur, 0.0, 1.0)
			_mat.set_shader_parameter("fade", u)
			_mat.set_shader_parameter("contract", smoothstep(0.25, 1.0, u))
			light.light_energy = _light_max * (1.0 - u)
			if u >= 1.0:
				state = State.GONE
				runes.visible = false
				flakes.emitting = false
		State.GONE:
			light.light_energy = maxf(0.0, light.light_energy - 8.0 * delta)
