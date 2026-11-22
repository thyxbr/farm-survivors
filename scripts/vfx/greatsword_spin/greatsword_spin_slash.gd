class_name GreatswordSpinSlash
extends Node3D
## Ciclone de Aço (montante, tecla 1): o visual e a detecção do giro, em cena própria
## (scenes/vfx/greatsword_spin/greatsword_spin_slash.tscn). GreatswordSpinAbilities cria uma por ativação, na cena do
## mundo; ela segue o herói, vive um pouco mais que a habilidade (o apagar) e se libera sozinha (queue_free).
## Visual de energia sombria (a paleta das garras do Corte do Abismo, DarkEnergy):
##   Trail       DarkBladeTrail: a energia que segue o corte da espada, do cabo até além da ponta, montada das posições
##               da lâmina de verdade (blade_base, blade_tip) nos últimos `trail_time` s. Acende com a velocidade do
##               giro e fica enquanto ele durar; some aos poucos na desaceleração
##   Wisps       fiapos de fumaça escura soltos ao longo da lâmina (ficam para trás no giro: o borrão escuro)
##   Motes       faíscas violeta, Sparks lascas carmesim lançadas pela lâmina
##   Light       luz violeta do giro
## Fases (GreatswordSpinRules, os tempos do GreatswordSpinConfig, os mesmos da pose do herói):
##   STANCE  postura parada (só com `stance_time` > 0; o padrão é girar na hora)
##   ACCEL   o giro acelera: rastro, fiapos e luz crescem com a velocidade
##   SPIN    velocidade máxima; dano (sinal `hit`) a cada `hit_interval` em cada inimigo no alcance
##   DECEL   o rastro encolhe com a velocidade e as partículas param de surgir (Tween); o dano segue até a lâmina ficar lenta
##   RECOVER herói voltando à guarda; o que sobrou se apaga (Tween) e a cena se libera
## O dano é só do dono (`deal_damage`): uma consulta de forma (PhysicsShapeQueryParameters3D) na camada dos inimigos
## filtrada por GreatswordSpinRules.pick_targets (alcance + intervalo por alvo). Nas réplicas é só o visual.
## `stop()` (morte, troca de arma, esquiva na postura parada) apaga tudo depressa, sem mais dano.

## Inimigos atingidos agora (dono): GreatswordSpinAbilities aplica o dano.
signal hit(targets: Array)

const ENEMY_MASK := 4      ## camada 3 ("enemies")
const STOP_FADE := 0.2     ## apagar rápido do stop() (s)

@export var config: GreatswordSpinConfig

## O herói (posição), o modelo dele (para onde a lâmina aponta) e as pontas da montante (KnightLook: holder, tip).
var follow: Node3D
var model: Node3D
var blade_base: Node3D
var blade_tip: Node3D
var deal_damage := false
## Só aquece os pipelines (GreatswordSpinAbilities.prewarm_instances): desenha cada efeito uma vez e se libera.
var warm_only := false

@onready var trail: DarkBladeTrail = $Trail
@onready var light: OmniLight3D = $Light
var wisps: GPUParticles3D
var motes: GPUParticles3D
var sparks: GPUParticles3D

## Tempo desde o começo (s), a fase atual e quantos cortes o giro já deu (testes).
var t := 0.0
var phase := GreatswordSpinRules.Phase.STANCE
var hit_count := 0
var stopped := false
## Quanto da energia está acesa (0..1): acompanha a velocidade do giro; o Tween da desaceleração e do fim o derruba.
var level := 0.0

var _durs: Array[float] = []
var _turns_heard := 0
var _last_hit := {}
var _decel_started := false
var _fade_started := false
var _tween: Tween


func _ready() -> void:
	if config == null:
		config = load("res://assets/vfx/greatsword_spin/greatsword_spin_config.tres")
	_durs = config.durations()
	trail.base_node = blade_base
	trail.tip_node = blade_tip
	trail.lifetime = config.trail_time
	trail.reach = config.trail_reach
	trail.strength_override = 0.0
	trail.intensity = config.trail_intensity
	light.position.y = config.slash_height
	wisps = DarkEnergy.wisps(maxi(8, int(config.wisps_per_second * 0.9)), 0.9, 0.75)
	motes = DarkEnergy.motes(maxi(8, int(config.motes_per_second * 0.8)), 0.8, 0.09)
	sparks = DarkEnergy.sparks(maxi(8, int(config.sparks_per_second * 0.5)), 0.5, 0.32)
	for p: GPUParticles3D in [wisps, motes, sparks]:
		add_child(p)
		p.top_level = true
	# as lascas saem para fora do giro (a lâmina as lança na direção em que corre)
	var spm := sparks.process_material as ParticleProcessMaterial
	spm.direction = Vector3(1, 0.25, 0)
	spm.spread = 35.0
	if warm_only:
		_warm_pipelines()
		return
	_set_level(0.0)
	_follow_now()


func _warm_pipelines() -> void:
	set_process(false)
	set_physics_process(false)
	for p: GPUParticles3D in [wisps, motes, sparks]:
		p.global_position = global_position
		p.restart()
	get_tree().create_timer(0.6).timeout.connect(queue_free)


func _process(delta: float) -> void:
	t += delta
	_follow_now()
	var ph := GreatswordSpinRules.phase_at(t, _durs)
	phase = int(ph.x) as GreatswordSpinRules.Phase
	var spd := GreatswordSpinRules.speed_frac(t, _durs)
	if not _fade_started:
		match phase:
			GreatswordSpinRules.Phase.STANCE, GreatswordSpinRules.Phase.ACCEL, GreatswordSpinRules.Phase.SPIN:
				level = spd
			GreatswordSpinRules.Phase.DECEL:
				_begin_decel()
			GreatswordSpinRules.Phase.RECOVER:
				_begin_fade(config.fade_time)
	_set_level(level)
	light.light_energy = level * (2.2 + 0.5 * sin(t * 19.0))
	_turn_sounds()


## Dano no passo de física (a consulta de forma é segura aqui).
func _physics_process(_delta: float) -> void:
	if not deal_damage or stopped or warm_only:
		return
	var spd := GreatswordSpinRules.speed_frac(t, _durs)
	if spd < config.hit_min_speed:
		return
	var targets := _collect_targets()
	if targets.is_empty():
		return
	hit_count += targets.size()
	hit.emit(targets)


func _valid(n: Node3D) -> bool:
	return n != null and is_instance_valid(n) and n.is_inside_tree()


func _follow_now() -> void:
	if _valid(follow):
		global_position = follow.global_position
	# as partículas saem ao longo da lâmina (sem a arma: um anel em volta do herói, na altura dela)
	var b: Vector3
	var tip: Vector3
	if _valid(blade_base) and _valid(blade_tip):
		b = blade_base.global_position
		tip = blade_tip.global_position
	else:
		var yaw := model.global_rotation.y if _valid(model) else 0.0
		var f := Vector3(sin(yaw), 0.0, cos(yaw))
		b = global_position + Vector3.UP * config.slash_height + f * 0.5
		tip = b + f * 1.6
	for p: GPUParticles3D in [wisps, motes, sparks]:
		DarkEnergy.along_blade(p, b, tip, config.trail_reach * 0.8, 0.1)


## Liga a energia toda num nível só (0..1): rastro e quanto nasce de partículas.
func _set_level(k: float) -> void:
	k = clampf(k, 0.0, 1.0)
	trail.strength_override = k
	wisps.amount_ratio = k
	motes.amount_ratio = k
	sparks.amount_ratio = k * k
	var on := k > 0.05 and not _fade_started
	for p: GPUParticles3D in [wisps, motes, sparks]:
		if p.emitting != on:
			p.emitting = on


## Desaceleração: a energia cai com a velocidade do giro (Tween, o tempo da fase).
func _begin_decel() -> void:
	if _decel_started:
		return
	_decel_started = true
	var dur := _durs[GreatswordSpinRules.Phase.DECEL]
	_tween = create_tween()
	_tween.tween_property(self, "level", 0.25, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Apaga o que sobrou (rastro, luz e as partículas no ar) e libera a cena quando o último some.
func _begin_fade(dur: float) -> void:
	if _fade_started:
		return
	_fade_started = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	for p: GPUParticles3D in [wisps, motes, sparks]:
		p.emitting = false
	trail.emitting = false
	_tween = create_tween().set_parallel()
	_tween.tween_property(self, "level", 0.0, dur).set_ease(Tween.EASE_IN)
	_tween.tween_property(trail, "intensity", 0.0, dur)
	_tween.chain().tween_interval(maxf(wisps.lifetime, trail.lifetime))
	_tween.chain().tween_callback(queue_free)
	set_physics_process(false)


## Desfaz depressa e sem mais dano (a habilidade acabou antes da hora).
func stop() -> void:
	if stopped or _fade_started:
		return
	stopped = true
	_begin_fade(STOP_FADE)


## Um "vush" a cada volta completa, mais alto quanto mais rápido (dono e réplicas).
func _turn_sounds() -> void:
	var turns := int(GreatswordSpinRules.angle(t, _durs, config.turns) / TAU + 0.0001)
	while _turns_heard < turns:
		_turns_heard += 1
		var spd := GreatswordSpinRules.speed_frac(t, _durs)
		Sfx.play_at("sword_swing_heavy" if spd > 0.8 else "sword_swing", global_position, 0.12, lerpf(-10.0, -3.0, spd))


## Inimigos no alcance do giro que podem levar um corte agora: consulta de forma (esfera em volta do herói) na camada
## dos inimigos, filtrada por GreatswordSpinRules (alcance exato, altura e intervalo por alvo).
func _collect_targets() -> Array:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return []
	var center := global_position
	var sphere := SphereShape3D.new()
	sphere.radius = config.radius + 1.5
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.transform = Transform3D(Basis.IDENTITY, center + Vector3.UP)
	q.collision_mask = ENEMY_MASK
	q.collide_with_areas = false
	q.collide_with_bodies = true
	var cands := []
	for r in space.intersect_shape(q, 64):
		var b = r.get("collider")
		if b == null or not is_instance_valid(b) or not b.is_in_group("enemies") or bool(b.get("dead")):
			continue
		cands.append({"id": b.get_instance_id(), "pos": b.global_position, "radius": float(b.get("radius")), "node": b})
	return GreatswordSpinRules.pick_targets(cands, center, config.radius, config.height, t, config.hit_interval,
		_last_hit).map(func(x: Dictionary) -> Node: return x.node)
