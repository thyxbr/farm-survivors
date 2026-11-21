class_name HammerSkill
extends Node3D
## Martelo de Energia (habilidade 4 da espada com escudo): a sequência inteira, em cena própria
## (scenes/vfx/hammer/hammer_skill.tscn). HammerAbilities cria uma por ativação, na cena do mundo; ela se libera
## sozinha quando o último efeito some. Cada etapa é de um componente:
##   INVOKE    o círculo mágico (MagicCircle) se materializa acima da cabeça do herói e o acompanha
##   FORM      o martelo (EnergyHammer) sai de dentro do círculo, cabeça primeiro e cabo depois, semitransparente
##             e ficando inteiro; um feixe de energia da sprite sheet (Beam) desce do círculo junto
##   CLOSE     o martelo está pronto: o círculo fecha com animação própria (e solta a explosão de partículas) e
##             o martelo sobe um pouco, tomando impulso
##   FALL      queda vertical acelerada (HammerRules.fall_distance), a cabeça para baixo, com rastro de energia
##   impacto   no instante em que toca o chão: o dano (sinal `landed` com os inimigos atingidos pela DamageArea),
##             a explosão (HammerImpact), o choque com o chão (HammerGroundShock: onda de choque da sprite sheet,
##             rachaduras projetadas, detritos/brasas/fumaça e o tremor da câmera) e as crateras (GroundCrater)
##   LINGER    o martelo fica cravado, perdendo o brilho e rachando
##   DISSOLVE  desfaz da cabeça para o cabo, em partículas que sobem (HammerDissolve)
## O dano é só do dono (`deal_damage`); nas réplicas é só o visual. `cancel()` antes da queda desfaz tudo sem dano.

signal landed(center: Vector3, targets: Array)
signal finished

const CRATER := preload("res://scenes/vfx/hammer/ground_crater.tscn")
const IMPACT := preload("res://scenes/vfx/hammer/hammer_impact.tscn")
const DISSOLVE := preload("res://scenes/vfx/hammer/hammer_dissolve.tscn")
const EMBED := 0.1          ## quanto a cabeça afunda no chão ao bater (m)
const CANCEL_TIME := 0.35
const TRAIL_COLOR := Color(0.35, 0.65, 1.0)

enum State { INVOKE, FORM, CLOSE, FALL, LINGER, DISSOLVE, DONE, CANCELED }

@export var config: HammerConfig

## Quem o círculo acompanha durante a invocação (o herói); `yaw` = para onde ele olha (o martelo cai à frente).
var follow: Node3D
var yaw := 0.0
var seed_value := 0
var deal_damage := false

@onready var circle: MagicCircle = $Circle
@onready var hammer: EnergyHammer = $Hammer
@onready var beam: HammerSheet = $Beam
@onready var trail: HammerSheet = $Trail
@onready var damage_area: Area3D = $DamageArea
@onready var damage_shape: CollisionShape3D = $DamageArea/Shape

var state := State.INVOKE
var t := 0.0
var impact_at := -1.0          ## t do impacto (para os testes e a recarga)
var impact_center := Vector3.ZERO
var hit_count := 0
var craters_spawned := 0
var _st := 0.0
var _following := true
var _ground_local := 0.0
var _fall_from := 0.0
var _hit := {}
var _pending: Array[Dictionary] = []
var _dissolver: HammerDissolve
var _since_impact := 0.0
var _trails: Array[CPUParticles3D] = []


func _ready() -> void:
	if config == null:
		config = load("res://assets/vfx/hammer/hammer_config.tres")
	_follow_now()
	circle.setup(config)
	circle.position = Vector3(0, config.circle_height, 0)
	hammer.setup(config)
	hammer.position = Vector3(0, config.circle_height, 0)
	hammer.set_clip(global_position.y + config.circle_height)
	hammer.set_solidity(0.25)
	hammer.visible = false
	for s: HammerSheet in [beam, trail]:
		s.set_param("crop", HammerSheet.BEAM_CROP)
		s.set_param("soft_edge", 1.0)
		s.intensity = 0.0
	beam.set_param("flip_v", 1.0)
	beam.set_param("recolor", 0.75)
	trail.set_param("recolor", 1.0)
	var cyl := CylinderShape3D.new()
	cyl.radius = config.radius
	cyl.height = 8.0
	damage_shape.shape = cyl
	damage_shape.position = Vector3(0, 1.5, 0)
	damage_area.monitoring = deal_damage   # só o dono procura alvos
	# texturas e materiais do choque prontos antes do impacto (sem engasgo no quadro do golpe)
	HammerGroundShock.warm(config)
	circle.materialize(config.circle_form_time)
	Sfx.play_at("portal", global_position + Vector3.UP * config.circle_height, 0.05, -4.0)


## Antes da queda dá para desfazer (esquiva, morte, troca de arma).
func can_cancel() -> bool:
	return state <= State.CLOSE


## Desfaz sem dano: o círculo se apaga e o martelo some depressa.
func cancel() -> void:
	if not can_cancel():
		return
	_enter(State.CANCELED)
	circle.close(CANCEL_TIME * 0.8, true)
	beam.fade_out(0.2)


func _follow_now() -> void:
	if not _following or follow == null or not is_instance_valid(follow) or not follow.is_inside_tree():
		return
	var f := Vector3(sin(yaw), 0.0, cos(yaw))
	global_position = follow.global_position + f * config.forward_offset
	rotation = Vector3(0.0, yaw, 0.0)


## `carry` = o quanto a etapa anterior passou do tempo dela neste quadro: a próxima já começa adiantada, para a
## soma das etapas bater com HammerConfig.impact_time() (sem perder um quadro a cada troca).
func _enter(s: State, carry := 0.0) -> void:
	state = s
	_st = maxf(carry, 0.0)
	match s:
		State.FORM:
			hammer.visible = true
			beam.intensity = 0.0
			beam.play(HammerSheet.BEAM, 0.4, true)
			Sfx.play_at("arcane_cast", global_position + Vector3.UP * config.circle_height, 0.08, -3.0)
		State.CLOSE:
			_following = false
			hammer.clear_clip()
			hammer.set_solidity(1.0)
			circle.close(config.circle_close_time)
			beam.fade_out(0.25)
		State.FALL:
			_ground_local = _ground_height_local()
			_fall_from = hammer.position.y
			trail.play(HammerSheet.BEAM, 0.25, true)
			# rastro de partículas nas pontas da cabeça (ficam no mundo enquanto o martelo desce)
			var k := hammer.length / EnergyHammer.BASE_LENGTH
			for anchor: Node3D in [hammer.trail_l, hammer.trail_r]:
				var p := FXEpic.stream(anchor, "glow", TRAIL_COLOR, 60, 0.35, 0.22 * k)
				if p:
					p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
					p.emission_sphere_radius = 0.45 * k
					p.direction = Vector3.UP
					p.spread = 20.0
					p.initial_velocity_min = 0.5
					p.initial_velocity_max = 2.0
					p.gravity = Vector3.ZERO
					_trails.append(p)
			Sfx.play_at("sword_swing_heavy", global_position + Vector3.UP * 2.0, 0.05, 0.0)
		State.DISSOLVE:
			_dissolver = DISSOLVE.instantiate()
			add_child(_dissolver)
			_dissolver.follow(hammer)
			Sfx.play_at("arcane_hit", hammer.global_position + Vector3.UP, 0.1, -6.0)


func _process(delta: float) -> void:
	t += delta
	_st += delta
	_follow_now()
	var ch := config.circle_height
	var L := config.hammer_size
	match state:
		State.INVOKE:
			if _st >= config.circle_form_time:
				_enter(State.FORM, _st - config.circle_form_time)
		State.FORM:
			var u := clampf(_st / config.formation_time, 0.0, 1.0)
			var e := u * u * (3.0 - 2.0 * u)
			hammer.position.y = ch - L * e
			hammer.set_clip(global_position.y + ch)
			hammer.set_solidity(lerpf(0.25, 1.0, u * u))
			hammer.set_glow(0.8 + 0.4 * u)
			# feixe de energia descendo do círculo junto com o martelo
			var bl := maxf(L * e + 0.6, 0.6)
			beam.position = Vector3(0, ch - bl * 0.5, 0)
			beam.scale = Vector3(config.circle_radius * 1.3, bl, 1.0)
			beam.intensity = 0.9 * smoothstep(0.0, 0.15, u)
			if u >= 1.0:
				_enter(State.CLOSE, _st - config.formation_time)
		State.CLOSE:
			var u := clampf(_st / config.circle_close_time, 0.0, 1.0)
			hammer.position.y = ch - L + config.windup_lift * (1.0 - (1.0 - u) * (1.0 - u))
			hammer.set_glow(1.2 + 0.3 * u)
			if u >= 1.0:
				_enter(State.FALL, _st - config.circle_close_time)
		State.FALL:
			var y := _fall_from - HammerRules.fall_distance(_st, config.fall_start_speed, config.fall_acceleration)
			var speed := config.fall_start_speed + config.fall_acceleration * _st
			# rastro de energia em cima do martelo, mais comprido quanto mais rápido
			var tl := clampf(speed * 0.14, 0.6, 3.2)
			trail.position = Vector3(0, y + L * 0.55 + tl * 0.5, 0)
			trail.scale = Vector3(hammer.head_width() * 0.75, L * 0.6 + tl, 1.0)
			trail.intensity = 0.75
			if y <= _ground_local:
				hammer.position.y = _ground_local - EMBED
				_impact()
				_enter(State.LINGER)
			else:
				hammer.position.y = y
		State.LINGER:
			var u := clampf(_st / maxf(config.linger_time, 0.001), 0.0, 1.0)
			# o clarão do golpe e depois perde a luz aos poucos, rachando
			hammer.set_glow(lerpf(1.7, 0.6, smoothstep(0.0, 1.0, u)))
			hammer.set_crack(smoothstep(0.15, 1.0, u))
			if u >= 1.0:
				_enter(State.DISSOLVE)
		State.DISSOLVE:
			var u := clampf(_st / config.dissolve_time, 0.0, 1.0)
			var front := lerpf(hammer.bottom_y() - 0.3, hammer.top_y() + 0.35, u * u * (3.0 - 2.0 * u) * 0.85 + u * 0.15)
			hammer.set_dissolve(front)
			hammer.set_glow(0.6 * (1.0 - 0.5 * u))
			hammer.set_crack(1.0)
			if is_instance_valid(_dissolver):
				_dissolver.set_front(front)
			if u >= 1.0:
				hammer.visible = false
				if is_instance_valid(_dissolver):
					_dissolver.stop()
				_enter(State.DONE)
		State.DONE:
			if _pending.is_empty() and circle.finished() and not _effects_alive():
				finished.emit()
				queue_free()
		State.CANCELED:
			var u := clampf(_st / CANCEL_TIME, 0.0, 1.0)
			hammer.set_solidity(0.25 * (1.0 - u))
			hammer.set_glow(1.0 - u)
			hammer.set_dissolve(lerpf(hammer.bottom_y() - 0.3, hammer.top_y() + 0.3, u))
			if u >= 1.0:
				hammer.visible = false
				if circle.finished():
					finished.emit()
					queue_free()
	if impact_at >= 0.0:
		_since_impact += delta
		_spawn_pending()


## Restam efeitos desta ativação na cena (explosão, crateras, partículas)?
func _effects_alive() -> bool:
	for c in get_children():
		if (c is HammerImpact or c is GroundCrater or c is HammerDissolve or c is HammerGroundShock) and not c.is_queued_for_deletion():
			return true
	return false


## Altura do chão no ponto do impacto, relativa a este nó (o chão pode estar mais alto ou mais baixo à frente).
func _ground_height_local() -> float:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return 0.0
	var from := global_position + Vector3.UP * 3.0
	var q := PhysicsRayQueryParameters3D.create(from, global_position - Vector3.UP * 6.0, 1)
	var hit := space.intersect_ray(q)
	return float(hit.position.y) - global_position.y if not hit.is_empty() else 0.0


func _impact() -> void:
	impact_at = t
	_since_impact = 0.0
	impact_center = to_global(Vector3(0, _ground_local, 0))
	for p in _trails:
		FXEpic.stop_stream(p)
	_trails.clear()
	trail.fade_out(0.15)
	var imp: HammerImpact = IMPACT.instantiate()
	imp.setup(config, seed_value)
	imp.position = Vector3(0, _ground_local, 0)
	add_child(imp)
	# o choque com o chão: onda de choque da sprite sheet, rachaduras projetadas, detritos/brasas/fumaça e tremor
	var shock: HammerGroundShock = HammerGroundShock.new()
	shock.setup(config, seed_value)
	shock.position = Vector3(0, _ground_local, 0)
	add_child(shock)
	# crateras: distribuição circular com desvio, aparecendo na onda que corre pelo chão
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 7
	for off in HammerRules.crater_layout(config.crater_count, config.crater_min_distance, config.crater_max_distance, seed_value):
		_pending.append({"at": off.length() / config.crater_wave_speed + rng.randf_range(0.0, 0.035),
			"off": off, "size": config.crater_size * rng.randf_range(0.8, 1.2), "seed": rng.randi()})
	_pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.at) < float(b.at))
	var targets := _collect_targets(impact_center) if deal_damage else []
	hit_count = targets.size()
	landed.emit(impact_center, targets)


## Inimigos dentro da DamageArea (Area3D na camada dos inimigos), filtrados pelo raio e por quem já levou o golpe.
func _collect_targets(center: Vector3) -> Array:
	var cands := []
	for b in damage_area.get_overlapping_bodies():
		if not b.is_in_group("enemies") or bool(b.get("dead")):
			continue
		cands.append({"id": b.get_instance_id(), "pos": b.global_position, "radius": float(b.get("radius")), "node": b})
	return HammerRules.pick_targets(cands, center, config.radius, _hit).map(func(x: Dictionary) -> Node: return x.node)


func _spawn_pending() -> void:
	while not _pending.is_empty() and float(_pending[0].at) <= _since_impact:
		var p: Dictionary = _pending.pop_front()
		var off: Vector2 = p.off
		var c: GroundCrater = CRATER.instantiate()
		c.setup(config, float(p.size), int(p.seed))
		add_child(c)
		var world := impact_center + Vector3(off.x, 0.0, off.y)
		c.global_transform = FXToon.ground_frame(world, float(p.size) * 0.7)
		craters_spawned += 1
		if craters_spawned <= 3:
			Sfx.play_at("chop_stone", world, 0.15, -10.0)
