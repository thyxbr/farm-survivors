class_name GreatswordDarkComboFX
extends Node3D
## Dança do Abismo (montante, tecla 3): o visual do combo, em cena própria
## (scenes/vfx/greatsword_dark/greatsword_dark_combo_fx.tscn). GreatswordDarkComboAbilities cria uma por ativação, na
## cena do mundo; ela segue o herói, vive um pouco mais que a habilidade (o apagar) e se libera sozinha.
## Tudo em energia sombria (a paleta das garras do Corte do Abismo, DarkEnergy):
##   Trail       DarkBladeTrail: a energia que segue cada corte da lâmina (acende com a velocidade da ponta: parada não
##               deixa rastro, num golpe vira uma meia-lua escura com a borda violeta)
##   (código)    fiapos escuros e faíscas violeta soltos ao longo da lâmina enquanto ela corta
##   BladeLight  luz violeta na lâmina, com a força do corte
##   burst()     em cada acerto: explosão de fumaça escura, lascas carmesim e um clarão violeta no ponto do golpe
##   Wave/Claws  no acerto final: um anel de energia escura corre pelo chão e garras sombrias (as unhas de cristal do
##               Corte do Abismo, DragAndSlash.talon_mesh) irrompem em volta do herói, viradas para fora
## `finish()` (fim normal) e `stop()` (esquiva, morte, troca de arma) param de emitir; o resto se apaga sozinho.

const WAVE_TIME := 0.45
const CLAW_RISE := 0.14
const CLAW_HOLD := 0.35
const CLAW_FADE := 0.4
const CLAW_HEIGHT := 1.5
const TALON_MAT := preload("res://assets/vfx/greatsword_dark/dark_talon_mat.tres")

@export var config: GreatswordDarkComboConfig

var follow: Node3D
var blade_base: Node3D
var blade_tip: Node3D
## Só aquece os pipelines (GreatswordDarkComboAbilities.prewarm_instances): desenha cada efeito uma vez e se libera.
var warm_only := false

@onready var trail: DarkBladeTrail = $Trail
@onready var blade_light: OmniLight3D = $BladeLight
@onready var wave: MeshInstance3D = $Wave
@onready var claws_root: Node3D = $Claws
var wisps: GPUParticles3D
var motes: GPUParticles3D

var t := 0.0
var bursts := 0
var stopped := false
var _ending := false
var _wave_at := -1.0
var _wave_reach := 3.0
var _claws: Array[Dictionary] = []


func _ready() -> void:
	if config == null:
		config = load("res://assets/vfx/greatsword_dark/greatsword_dark_combo_config.tres")
	trail.base_node = blade_base
	trail.tip_node = blade_tip
	trail.lifetime = config.trail_time
	trail.reach = config.trail_reach
	trail.min_speed = config.trail_min_speed
	trail.full_speed = config.trail_full_speed
	trail.intensity = config.trail_intensity
	wisps = DarkEnergy.wisps(40, 0.8, 0.6)
	motes = DarkEnergy.motes(50, 0.7, 0.08)
	for p: GPUParticles3D in [wisps, motes]:
		add_child(p)
		p.top_level = true
		p.amount_ratio = 0.0
		p.emitting = true
	wave.set_instance_shader_parameter("seed", randf() * 10.0)
	if warm_only:
		_warm()


func _warm() -> void:
	set_process(false)
	for p: GPUParticles3D in [wisps, motes]:
		p.global_position = global_position
		p.amount_ratio = 1.0
		p.restart()
	wave.visible = true
	wave.global_position = global_position
	wave.set_instance_shader_parameter("intensity", 0.01)
	burst(global_position, Vector3.FORWARD, true)
	_spawn_claws(global_position, 0.0)
	get_tree().create_timer(0.6).timeout.connect(queue_free)


func _valid(n: Node3D) -> bool:
	return n != null and is_instance_valid(n) and n.is_inside_tree()


func _process(delta: float) -> void:
	t += delta
	if _valid(follow):
		global_position = follow.global_position
	var k := trail.strength() if not _ending else 0.0
	if _valid(blade_base) and _valid(blade_tip):
		var b := blade_base.global_position
		var tip := blade_tip.global_position
		for p: GPUParticles3D in [wisps, motes]:
			DarkEnergy.along_blade(p, b, tip, config.trail_reach * 0.7, 0.08)
		blade_light.global_position = b.lerp(tip, 0.7)
	wisps.amount_ratio = k
	motes.amount_ratio = k
	blade_light.light_energy = lerpf(blade_light.light_energy, 2.4 * k, 1.0 - exp(-12.0 * delta))
	_update_wave()
	_update_claws()
	if _ending and _claws.is_empty() and _wave_at < 0.0 and trail.sample_count() == 0:
		queue_free()


## Explosão de energia sombria num acerto, em `at`, para onde o golpe corre (`dir`). `big` = o acerto final.
func burst(at: Vector3, dir: Vector3, big := false) -> void:
	bursts += 1
	var k := 1.6 if big else 1.0
	var smoke := DarkEnergy.wisps(int(16 * k), 0.9, 0.9 * k)
	var sp := DarkEnergy.sparks(int(26 * k), 0.45, 0.4)
	var mo := DarkEnergy.motes(int(20 * k), 0.8, 0.1)
	for p: GPUParticles3D in [smoke, sp, mo]:
		add_child(p)
		p.top_level = true
		p.one_shot = true
		p.explosiveness = 0.9
		p.global_position = at + Vector3.UP * 0.9
		var m := p.process_material as ParticleProcessMaterial
		m.emission_box_extents = Vector3(0.35, 0.35, 0.35) * k
		m.direction = (dir.normalized() + Vector3.UP * 0.6).normalized() if dir.length() > 0.01 else Vector3.UP
		m.initial_velocity_max *= 1.8 * k
		p.emitting = true
		get_tree().create_timer(p.lifetime + 0.3).timeout.connect(p.queue_free)
	var fl := OmniLight3D.new()
	add_child(fl)
	fl.top_level = true
	fl.global_position = at + Vector3.UP * 1.0
	fl.light_color = DarkEnergy.VIOLET
	fl.omni_range = 4.5 * k
	fl.light_energy = 3.0 * k
	var tw := fl.create_tween()
	tw.tween_property(fl, "light_energy", 0.0, 0.35).set_ease(Tween.EASE_OUT)
	tw.tween_callback(fl.queue_free)


## O acerto final: o anel de energia correndo pelo chão até `reach` e as garras em volta de `center`, viradas a partir
## de `yaw` (a primeira aponta para a frente do golpe).
func final_strike(center: Vector3, yaw: float, reach: float) -> void:
	_wave_at = t
	_wave_reach = reach
	wave.global_position = center + Vector3.UP * 0.06
	wave.visible = true
	_spawn_claws(center, yaw)
	Sfx.play_at("arcane_hit", center, 0.1, -1.0)
	Sfx.play_at("slam", center, 0.1, -4.0)


func _update_wave() -> void:
	if _wave_at < 0.0:
		return
	var u := (t - _wave_at) / WAVE_TIME
	if u >= 1.0:
		_wave_at = -1.0
		wave.visible = false
		return
	var d := lerpf(1.0, _wave_reach * 2.2, 1.0 - pow(1.0 - u, 3.0))
	wave.scale = Vector3(d, 1.0, d)
	wave.set_instance_shader_parameter("intensity", 1.0 - smoothstep(0.35, 1.0, u))
	wave.set_instance_shader_parameter("spin", t * 4.0)


func _spawn_claws(center: Vector3, yaw: float) -> void:
	var n := config.final_claws
	for i in n:
		var a := yaw + TAU * float(i) / float(maxi(n, 1))
		var out := Vector3(sin(a), 0.0, cos(a))
		var m := MeshInstance3D.new()
		m.mesh = DragAndSlash.talon_mesh()
		m.material_override = TALON_MAT
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		claws_root.add_child(m)
		m.set_instance_shader_parameter("seed", float(i) * 0.37 + randf())
		m.visible = false
		var pos := center + out * config.final_claw_radius * randf_range(0.85, 1.1)
		_claws.append({"node": m, "at": t + 0.03 * float(i % 3), "pos": pos, "yaw": a,
			"size": CLAW_HEIGHT * randf_range(0.75, 1.15), "lean": randf_range(0.15, 0.35)})


## Garras: sobem de dentro do chão (passam um pouco da altura e voltam), crepitam e se desfazem de baixo para cima.
func _update_claws() -> void:
	var i := 0
	while i < _claws.size():
		var c: Dictionary = _claws[i]
		var m: MeshInstance3D = c.node
		var age := t - float(c.at)
		if age < 0.0:
			i += 1
			continue
		var life := CLAW_RISE + CLAW_HOLD + CLAW_FADE
		if age >= life or not is_instance_valid(m):
			if is_instance_valid(m):
				m.queue_free()
			_claws.remove_at(i)
			continue
		var r := clampf(age / CLAW_RISE, 0.0, 1.0)
		var ov := 1.0 + 2.7 * pow(r - 1.0, 3.0) + 1.7 * pow(r - 1.0, 2.0)   # ease out back
		var dis := smoothstep(CLAW_RISE + CLAW_HOLD, life, age)
		var sz: float = c.size
		# a unha curva para +Z: virada para fora, a base puxada para dentro (gancho saindo do chão)
		var b := Basis(Vector3.UP, float(c.yaw)) * Basis(Vector3.RIGHT, float(c.lean)) \
			* Basis.from_scale(Vector3(1.0, maxf(ov, 0.02), 1.0) * sz)
		m.global_transform = Transform3D(b, (c.pos as Vector3) - Vector3.UP * sz * (0.2 * dis + 0.6 * (1.0 - minf(ov, 1.0))))
		m.visible = true
		m.set_instance_shader_parameter("glow", 1.0 + 1.6 * (1.0 - smoothstep(0.0, 0.2, age)))
		m.set_instance_shader_parameter("dissolve", dis)
		i += 1


## Fim normal: para de soltar energia; o rastro, as garras e o anel terminam sozinhos e a cena se libera.
func finish() -> void:
	if _ending:
		return
	_ending = true
	trail.emitting = false
	for p: GPUParticles3D in [wisps, motes]:
		p.emitting = false
	var tw := create_tween()
	tw.tween_property(blade_light, "light_energy", 0.0, 0.3)
	# garantia: mesmo se algo ficar preso, a cena sai
	get_tree().create_timer(3.0).timeout.connect(func() -> void:
		if is_instance_valid(self):
			queue_free())


## Interrompido (esquiva, morte, troca de arma): apaga depressa.
func stop() -> void:
	if stopped:
		return
	stopped = true
	finish()
	var tw := create_tween()
	tw.tween_property(trail, "intensity", 0.0, 0.2)
