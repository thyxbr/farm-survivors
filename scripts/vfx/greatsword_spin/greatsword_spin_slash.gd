class_name GreatswordSpinSlash
extends Node3D
## Ciclone de Aço (montante, tecla 1): o visual e a detecção do giro, em cena própria
## (scenes/vfx/greatsword_spin/greatsword_spin_slash.tscn). GreatswordSpinAbilities cria uma por ativação, na cena do
## mundo; ela segue o herói, vive um pouco mais que a habilidade (o apagar) e se libera sozinha (queue_free).
##   (raiz)        na posição do herói a cada quadro
##     Pivot       gira com o modelo do herói (a lâmina): o anel acompanha a espada
##       Ring      o corte principal: PlaneMesh deitado na altura da lâmina, do tamanho do alcance, com a sprite sheet
##                 8x8 em modo aditivo (spin_slash_flipbook.gdshader): o começo da sheet na aceleração, o laço dos
##                 redemoinhos no giro (mais rápido quanto mais rápido gira) e o apagar na desaceleração
##       RingTrail o mesmo corte um pouco atrás e mais fraco: o borrão do giro
##     Slashes     GPUParticles3D (coordenadas locais) de cortes soltos da sheet em vários ângulos em volta do herói
##                 (spin_slash_particles.gdshader); a emissão acompanha a velocidade do giro e cai com Tween ao desacelerar
##     Sparks      fagulhas laranja lançadas da lâmina (no mundo: ficam para trás se o herói se mexer)
##     Light       luz quente do giro
## Fases (GreatswordSpinRules, os tempos do GreatswordSpinConfig, os mesmos da pose do herói):
##   STANCE  postura parada (só com `stance_time` > 0; o padrão é girar na hora)
##   ACCEL   o giro acelera: anel, cortes, fagulhas e luz crescem com a velocidade
##   SPIN    velocidade máxima; dano (sinal `hit`) a cada `hit_interval` em cada inimigo no alcance
##   DECEL   os cortes param de surgir e o anel se dissipa (Tween); o dano segue até a lâmina ficar lenta
##   RECOVER herói voltando à guarda; o que sobrou se apaga (Tween) e a cena se libera
## O dano é só do dono (`deal_damage`): uma consulta de forma (PhysicsShapeQueryParameters3D) na camada dos inimigos
## filtrada por GreatswordSpinRules.pick_targets (alcance + intervalo por alvo). Nas réplicas é só o visual.
## `stop()` (morte, troca de arma, esquiva na postura parada) apaga tudo depressa, sem mais dano.

## Inimigos atingidos agora (dono): GreatswordSpinAbilities aplica o dano.
signal hit(targets: Array)

const ENEMY_MASK := 4      ## camada 3 ("enemies")
const STOP_FADE := 0.2     ## apagar rápido do stop() (s)
const TRAIL_LAG := 0.5     ## o borrão fica este tanto atrás do anel (rad)
const TRAIL_FRAMES := 2.0  ## e este tanto de quadros atrás

@export var config: GreatswordSpinConfig

## O herói (posição) e o modelo dele (para onde a lâmina aponta).
var follow: Node3D
var model: Node3D
var deal_damage := false
## Só aquece os pipelines (GreatswordSpinAbilities.prewarm_instances): desenha cada efeito uma vez e se libera.
var warm_only := false

@onready var pivot: Node3D = $Pivot
@onready var ring: MeshInstance3D = $Pivot/Ring
@onready var ring_trail: MeshInstance3D = $Pivot/RingTrail
@onready var slashes: GPUParticles3D = $Slashes
@onready var sparks: GPUParticles3D = $Sparks
@onready var light: OmniLight3D = $Light

## Tempo desde o começo (s), a fase atual e quantos cortes o giro já deu (testes).
var t := 0.0
var phase := GreatswordSpinRules.Phase.STANCE
var hit_count := 0
var stopped := false
## Quanto nasce de cortes soltos e fagulhas (0..1).
var emission: float:
	get:
		return _emission
	set(v):
		_set_emission_ratio(v)

var _durs: Array[float] = []
var _loop_f := 0.0
var _turns_heard := 0
var _last_hit := {}
var _decel_started := false
var _fade_started := false
var _ring_level := 0.0
var _frame := 0.0
var _emission := 0.0
var _tween: Tween


func _ready() -> void:
	if config == null:
		config = load("res://assets/vfx/greatsword_spin/greatsword_spin_config.tres")
	_durs = config.durations()
	var d := config.radius * 2.0 * config.ring_scale
	ring.scale = Vector3(d, 1.0, d)
	ring_trail.scale = ring.scale * 0.96
	ring.position.y = config.slash_height
	ring_trail.position.y = config.slash_height - 0.04
	for m: MeshInstance3D in [ring, ring_trail]:
		var mat := (m.get_surface_override_material(0) as ShaderMaterial)
		if mat != null:
			mat.set_shader_parameter("flip_x", config.ring_flip)
	# cortes soltos: um material de processo por ativação (o tamanho e a inclinação vêm da configuração)
	var pm := (slashes.process_material as ShaderMaterial).duplicate() as ShaderMaterial
	pm.set_shader_parameter("size_min", d * 0.85)
	pm.set_shader_parameter("size_max", d * 1.15)
	pm.set_shader_parameter("height", config.slash_height)
	pm.set_shader_parameter("tilt_max", deg_to_rad(config.slash_tilt))
	slashes.process_material = pm
	slashes.amount = maxi(2, int(ceil(config.slashes_per_second * slashes.lifetime)) + 1)
	sparks.material_override = FXEpic._particle_mat(FXEpic._glow_tex(), true, true)
	var spm := (sparks.process_material as ParticleProcessMaterial).duplicate() as ParticleProcessMaterial
	spm.emission_ring_radius = config.radius * 0.85
	spm.emission_ring_inner_radius = config.radius * 0.45
	sparks.process_material = spm
	sparks.position.y = config.slash_height
	light.position.y = config.slash_height
	if warm_only:
		_warm_pipelines()
		return
	_set_ring(config.frames_start.x, 0.0)
	slashes.emitting = true
	sparks.emitting = true
	_set_emission(0.0)
	light.light_energy = 0.0
	_follow_now()


func _warm_pipelines() -> void:
	set_process(false)
	set_physics_process(false)
	_set_ring(20.0, 0.01)
	emission = 1.0
	slashes.restart()
	sparks.restart()
	get_tree().create_timer(0.6).timeout.connect(queue_free)


func _process(delta: float) -> void:
	t += delta
	_follow_now()
	var ph := GreatswordSpinRules.phase_at(t, _durs)
	phase = int(ph.x) as GreatswordSpinRules.Phase
	var spd := GreatswordSpinRules.speed_frac(t, _durs)
	if _fade_started:
		# apagando (fim do giro ou stop()): o quadro fica, o brilho vem do Tween
		_set_ring(_frame, _ring_level)
		return
	match phase:
		GreatswordSpinRules.Phase.STANCE, GreatswordSpinRules.Phase.ACCEL:
			# o primeiro crescente da sheet acende na postura e cresce com a aceleração
			var u := clampf(t / (_durs[0] + _durs[1]), 0.0, 1.0)
			_ring_level = config.ring_intensity * (0.25 * smoothstep(0.0, 1.0, u) + 0.75 * spd)
			_set_ring(lerpf(config.frames_start.x, config.frames_start.y, u), _ring_level)
			_set_emission(spd)
			light.light_energy = 1.8 * spd
		GreatswordSpinRules.Phase.SPIN:
			_loop_f += delta * config.loop_fps * maxf(spd, 0.2)
			_set_ring(_loop_frame(), config.ring_intensity)
			_set_emission(1.0)
			light.light_energy = 1.8 + 0.4 * sin(t * 22.0)
		GreatswordSpinRules.Phase.DECEL:
			_begin_decel()
			# o redemoinho da sheet se desfaz enquanto o giro perde velocidade (o brilho cai pelo Tween)
			_set_ring(lerpf(config.frames_end.x, config.frames_end.y, smoothstep(0.0, 1.0, ph.y)), _ring_level)
		GreatswordSpinRules.Phase.RECOVER:
			_set_ring(config.frames_end.y, _ring_level)
			_begin_fade(config.fade_time)
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


func _follow_now() -> void:
	if follow != null and is_instance_valid(follow):
		global_position = follow.global_position
	if model != null and is_instance_valid(model):
		pivot.global_rotation = Vector3(0.0, model.global_rotation.y + deg_to_rad(config.ring_yaw_offset), 0.0)
		ring_trail.rotation.y = -TRAIL_LAG


func _loop_frame() -> float:
	var span := maxf(config.frames_loop.y - config.frames_loop.x, 1.0)
	return config.frames_loop.x + fposmod(_loop_f, span)


func _set_ring(frame: float, level: float) -> void:
	_frame = frame
	ring.set_instance_shader_parameter("frame", frame)
	ring.set_instance_shader_parameter("intensity", level)
	ring_trail.set_instance_shader_parameter("frame", maxf(frame - TRAIL_FRAMES, 0.0))
	ring_trail.set_instance_shader_parameter("intensity", level * 0.45)
	ring.visible = level > 0.001
	ring_trail.visible = ring.visible


func _set_emission(k: float) -> void:
	emission = k
	slashes.set_instance_shader_parameter("intensity", config.slash_intensity)


## Quanto nasce de cortes soltos e fagulhas (0..1, acompanha a velocidade do giro; o Tween da desaceleração o derruba).
func _set_emission_ratio(k: float) -> void:
	_emission = clampf(k, 0.0, 1.0)
	if slashes == null:   # antes do @onready
		return
	(slashes.process_material as ShaderMaterial).set_shader_parameter("emit_ratio", _emission)
	sparks.amount_ratio = _emission * 0.8
	if not _fade_started:
		sparks.emitting = _emission > 0.05


## Desaceleração: os cortes param de surgir e o anel e a luz se dissipam aos poucos (Tween, o tempo da fase).
func _begin_decel() -> void:
	if _decel_started:
		return
	_decel_started = true
	var dur := _durs[GreatswordSpinRules.Phase.DECEL]
	_tween = create_tween().set_parallel()
	_tween.tween_property(self, "emission", 0.0, dur * 0.7).set_ease(Tween.EASE_OUT)
	_tween.tween_property(light, "light_energy", 0.4, dur).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "_ring_level", config.ring_intensity * 0.3, dur).set_trans(Tween.TRANS_SINE)


## Apaga o que sobrou (anel, luz e os cortes ainda no ar) e libera a cena quando o último some.
func _begin_fade(dur: float) -> void:
	if _fade_started:
		return
	_fade_started = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	slashes.emitting = false
	sparks.emitting = false
	_tween = create_tween().set_parallel()
	_tween.tween_property(self, "_ring_level", 0.0, dur).set_ease(Tween.EASE_IN)
	_tween.tween_property(light, "light_energy", 0.0, dur)
	_tween.tween_method(func(v: float) -> void: slashes.set_instance_shader_parameter("intensity", v),
		config.slash_intensity, 0.0, dur)
	_tween.chain().tween_interval(maxf(slashes.lifetime, sparks.lifetime))
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
