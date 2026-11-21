class_name DarkTauntSkill
extends Node3D
## Círculo da Provocação Sombria (habilidade 3 da espada com escudo): a sequência inteira, em cena própria
## (scenes/vfx/dark_taunt/dark_taunt_skill.tscn). DarkTauntAbilities cria uma por ativação, na cena do mundo, centrada
## no herói; ela se libera sozinha quando o último efeito some. Etapas (relógio `t`, desde a ativação):
##   GATHER    0..CAST_LEAD: o herói recolhe os braços (clipe "Power Up"); nada no chão ainda
##   FORM      ele solta a energia: a onda corre pelo chão (DarkTauntVFX.burst) e o círculo (DarkMagicCircle) se
##             desenha, deitado no terreno
##   RISE      círculo pronto: escolhe os alvos (os inimigos dentro do raio AGORA, cada um uma vez) e as mãos
##             (ShadowHand) saem do chão em pontos diferentes, cada uma com a erupção de mãos e fumaça da sheet
##   HOLD      cada mão fecha no seu alvo e emite `captured` (só o dono aplica a provocação: Enemy.apply_taunt);
##             a energia sombria envolve os agarrados; as mãos sem alvo arranham o ar
##   DISSIPATE as mãos soltam e afundam em fumaça; o círculo fica um pouco, perde a luz, as runas viram
##             partículas e os anéis se contraem para o centro
## Visual separado da regra: o skill só diz quem foi agarrado e quando; imobilizar e provocar é do Enemy (com
## tempo próprio: nada fica preso se a animação falhar). `cancel()` antes de alguma mão fechar desfaz tudo sem
## efeito (esquiva, morte, troca de arma).

signal captured(enemy: Node3D)
signal finished

const HAND := preload("res://scenes/vfx/dark_taunt/shadow_hand.tscn")
const CANCEL_TIME := 0.35

enum State { GATHER, FORM, RISE, HOLD, DISSIPATE, DONE, CANCELED }

@export var config: DarkTauntConfig

## O herói que invocou (o círculo nasce em volta dele) e se este cliente aplica a provocação (o dono).
var caster: Node3D
var seed_value := 0
var deal_effects := false

@onready var circle: DarkMagicCircle = $Circle
@onready var vfx: DarkTauntVFX = $VFX
@onready var detect_area: Area3D = $DetectArea
@onready var detect_shape: CollisionShape3D = $DetectArea/Shape

var state := State.GATHER
var t := 0.0
var center := Vector3.ZERO
var targets: Array = []           ## inimigos agarrados nesta ativação (escolhidos ao fim do FORM)
var hands: Array[ShadowHand] = []
var captured_count := 0
var _taken := {}                  ## ids de instância já escolhidos (cada um uma vez por ativação)
var _sent := {}                   ## ids que já receberam `captured`
var _linger_t := -1.0


func _ready() -> void:
	if config == null:
		config = load("res://assets/vfx/dark_taunt/dark_taunt_config.tres")
	if caster != null and is_instance_valid(caster) and caster.is_inside_tree():
		global_position = caster.global_position   # centrado no herói, seja qual for a ordem de entrada na cena
	center = _ground_at(global_position)
	global_position = center
	circle.setup(config)
	circle.global_transform = FXToon.ground_frame(center, config.radius * 0.6)
	vfx.setup(config)
	var cyl := CylinderShape3D.new()
	cyl.radius = config.radius + 1.5   # folga: o corpo encostando na borda conta (DarkTauntRules.in_radius)
	cyl.height = 8.0
	detect_shape.shape = cyl
	detect_shape.position = Vector3(0, 1.0, 0)
	detect_area.monitoring = true


## Antes de alguma mão fechar dá para desfazer (sem provocar ninguém).
func can_cancel() -> bool:
	return state <= State.RISE and captured_count == 0


func cancel() -> void:
	if not can_cancel():
		return
	state = State.CANCELED
	t = 0.0
	for h in hands:
		h.release_now()
	circle.dissipate(CANCEL_TIME)
	vfx.dissipate(CANCEL_TIME)


func _process(delta: float) -> void:
	t += delta
	var cfg := config
	match state:
		State.GATHER:
			if t >= DarkTauntConfig.CAST_LEAD:
				state = State.FORM
				vfx.burst(center)
				circle.materialize(cfg.circle_form_time)
				Sfx.play_at("portal", center, 0.05, -3.0)
		State.FORM:
			if t >= DarkTauntConfig.CAST_LEAD + cfg.circle_form_time:
				state = State.RISE
				_spawn_hands()
				Sfx.play_at("arcane_cast", center, 0.08, -4.0)
		State.RISE:
			if t >= cfg.grab_at():
				state = State.HOLD
				vfx.grab(cfg.hold_time)
				# mais inimigos que mãos (teto MAX_HANDS): os de sobra são agarrados pela energia, sem mão própria
				for e in targets:
					if is_instance_valid(e) and not _sent.has(e.get_instance_id()) and not _has_hand(e):
						_capture(e)
		State.HOLD:
			if t >= cfg.release_at():
				state = State.DISSIPATE
				vfx.dissipate(cfg.dissipate_time)
				_linger_t = 0.0
		State.DISSIPATE:
			_linger_t += delta
			if _linger_t >= cfg.circle_linger and circle.state != DarkMagicCircle.State.DISSIPATING \
					and circle.state != DarkMagicCircle.State.GONE:
				circle.dissipate(cfg.dissipate_time)
			if circle.finished() and _hands_done() and not vfx.alive():
				state = State.DONE
				finished.emit()
				queue_free()
		State.CANCELED:
			if (circle.finished() and _hands_done() and not vfx.alive()) or t > 4.0:
				finished.emit()
				queue_free()


## Escolhe os alvos (dentro do raio agora, cada um uma vez) e solta as mãos em pontos diferentes do círculo.
func _spawn_hands() -> void:
	var cands := []
	for b in detect_area.get_overlapping_bodies():
		if not b.is_in_group("enemies") or b.get("dead") == true or b is Player:
			continue
		cands.append({"id": b.get_instance_id(), "pos": b.global_position, "radius": float(b.get("radius")), "node": b})
	var picked := DarkTauntRules.pick_targets(cands, center, config.radius, _taken)
	targets = picked.map(func(x: Dictionary) -> Node: return x.node)
	var with_hand: Array = targets.slice(0, DarkTauntConfig.MAX_HANDS)
	var offs := []
	for e in with_hand:
		offs.append(Vector2(e.global_position.x - center.x, e.global_position.z - center.z))
	var count := clampi(maxi(config.hand_count, with_hand.size()), 0, DarkTauntConfig.MAX_HANDS)
	var spots := DarkTauntRules.hand_spots(offs, count, config.radius, config.hand_size, seed_value)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7 + 3
	var hold_end := config.release_at() - t   # no relógio da mão (começa agora)
	for s in spots:
		var p: Vector2 = s.pos
		var h: ShadowHand = HAND.instantiate()
		add_child(h)
		h.global_position = _ground_at(center + Vector3(p.x, 0.0, p.y))
		var tgt: Node3D = with_hand[int(s.target)] if int(s.target) >= 0 else null
		# as sem alvo surgem um pouco antes ou depois (não todas juntas)
		var rise := config.rise_time() * (1.0 if tgt != null else rng.randf_range(0.8, 1.3))
		h.start(tgt, config.hand_size, rise, hold_end + rng.randf_range(-0.1, 0.15), config.dissipate_time * 0.6,
			config.energy_intensity, rng.randi())
		h.grabbed.connect(_on_grabbed)
		vfx.eruption(h.global_position, h.size, rise + DarkTauntRules.REACH_TIME)
		hands.append(h)


func _has_hand(e: Node3D) -> bool:
	for h in hands:
		if h.target == e or (h.held and h.target == e):
			return true
	return false


func _on_grabbed(_hand: ShadowHand, enemy: Node3D) -> void:
	if state == State.CANCELED:
		return
	_capture(enemy)
	Sfx.play_at("hit", enemy.global_position, 0.15, -8.0)


## Um inimigo agarrado (uma vez por ativação): a energia em volta dele e, no dono, a provocação.
func _capture(enemy: Node3D) -> void:
	if enemy == null or not is_instance_valid(enemy) or enemy.get("dead") == true:
		return
	var id := enemy.get_instance_id()
	if _sent.has(id):
		return
	_sent[id] = true
	captured_count += 1
	vfx.aura(enemy)
	if deal_effects:
		captured.emit(enemy)


func _hands_done() -> bool:
	for h in hands:
		if is_instance_valid(h) and not h.is_done():
			return false
	return true


## Ponto do chão (camada world) sob `p`; sem chão, o próprio ponto.
func _ground_at(p: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return p
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.5, p - Vector3.UP * 6.0, 1)
	var hit := space.intersect_ray(q)
	return hit.position if not hit.is_empty() else p
