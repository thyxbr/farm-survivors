class_name GreatswordDarkComboAbilities
extends RefCounted
## Dança do Abismo: a habilidade da tecla 3 com a montante (espada de duas mãos). ItemDB "sword_dark_combo", "offhand":
## "two_handed": com a montante nas mãos ela troca a Fúria Picante (que vai para a tecla 5, sword_fury_great).
## Um combo de quatro golpes do Mixamo (KnightMovesGreatDark), sempre nesta ordem:
##   1. Deslize: escorrega de joelho para a frente com a lâmina baixa e sobe girando num corte (~3,4 m à frente)
##   2. Corte girando o corpo inteiro (acerta em volta), com um segundo corte de volta
##   3. Corte rápido em diagonal à frente
##   4. Giro alto: avança girando (acerta em volta) e fecha num golpe de cima, que abre um anel de energia no chão e
##      ergue garras sombrias em volta do herói (atordoa)
## Cada golpe emenda no seguinte (começa antes do anterior voltar à guarda, a pose se mistura). Todos em energia
## sombria: o rastro que segue cada corte, fiapos escuros e faíscas violeta, explosões nos acertos (GreatswordDarkComboFX).
## O herói anda com os clipes (a trilha ROOT, na direção em que o combo começou); a tecla de andar não move. A esquiva
## cancela a qualquer momento (sem mais dano).
## Ritmo, dano e visual em GreatswordDarkComboConfig (assets/vfx/greatsword_dark/greatsword_dark_combo_config.tres, no
## Inspector); as contas (relógio, acertos, arcos) em GreatswordDarkComboRules.
## Rede: o dono manda "sword_dark_combo" (a = posição, b = (yaw, 0, 0)): as réplicas tocam a mesma animação, o mesmo
## visual e as explosões nos acertos, sem dano. Cancelado: "sword_dark_combo_cancel".

const ID := "sword_dark_combo"
const CANCEL_EVENT := "sword_dark_combo_cancel"
const SKILL := preload("res://scenes/vfx/greatsword_dark/greatsword_dark_combo_fx.tscn")
const CONFIG := preload("res://assets/vfx/greatsword_dark/greatsword_dark_combo_config.tres")
## Mira suave: ao acionar, vira para o inimigo mais perto à frente (até esta distância e este ângulo).
const AIM_RANGE := 7.0
const AIM_ARC := 0.5   ## cosseno (~60° para cada lado)


static func use(player: Node, id: String) -> bool:
	if id != ID:
		return false
	var f: Vector3 = player.facing()
	var yaw := _aim_yaw(player, atan2(f.x, f.z))
	_begin(player, yaw)
	Network.send_event(ID, player.global_position, Vector3(yaw, 0.0, 0.0))
	Sfx.play("sword_swing_heavy", 0.1, -4.0)
	return true


## Para onde o combo vai: a frente do herói, ou o inimigo vivo mais perto dentro do cone à frente.
static func _aim_yaw(player: Node, yaw: float) -> float:
	var f := Vector3(sin(yaw), 0.0, cos(yaw))
	var best := AIM_RANGE
	var out := yaw
	for e in player.get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var to: Vector3 = e.global_position - player.global_position
		to.y = 0.0
		var dist := to.length()
		if dist < 0.3 or dist > best or f.dot(to / dist) < AIM_ARC:
			continue
		best = dist
		out = atan2(to.x, to.z)
	return out


static func _begin(player: Node, yaw: float) -> void:
	var skill: GreatswordDarkComboFX = null
	var root := FX._scene()
	if root != null:   # servidor dedicado: sem visual (o dano é do cliente dono)
		skill = SKILL.instantiate()
		skill.config = CONFIG
		skill.follow = player
		var lk: Dictionary = player.look
		skill.blade_base = lk.get("holder")
		skill.blade_tip = lk.get("tip")
		root.add_child(skill)
	var d := {"skill": skill, "yaw": yaw, "seg": 0, "from": KnightAnim.capture_pose(player.parts)}
	player.begin_ability(ID, d)
	player.model.rotation.y = yaw
	d["on_end"] = _on_end.bind(player, d)


## Tempo total da habilidade no herói.
static func total_time() -> float:
	return CONFIG.total_time()


static func tick(player: Node, delta: float, _move_dir := Vector3.ZERO, _move_speed := 0.0) -> void:
	var t0: float = player.ability_t
	player.ability_t += delta
	var t: float = player.ability_t
	var d: Dictionary = player.ability_data
	var cfg: GreatswordDarkComboConfig = CONFIG
	var lens := cfg.lengths()
	var starts := cfg.starts()
	var yaw := float(d.get("yaw", 0.0))
	player.model.rotation.y = lerp_angle(player.model.rotation.y, yaw, 1.0 - exp(-16.0 * delta))
	var sa := GreatswordDarkComboRules.segment_at(t, lens, starts)
	var seg := int(sa.x)
	if seg != int(d.get("seg", 0)):
		# golpe novo: emenda a partir da pose em que o anterior está agora
		d["seg"] = seg
		d["from"] = KnightAnim.capture_pose(player.parts)
	if not player.remote:
		# anda com o clipe (a diferença da trilha ROOT desde o quadro anterior), na direção do combo
		var step := _root_total(t, lens, starts) - _root_total(t0, lens, starts)
		var v := Basis(Vector3.UP, yaw) * step * (cfg.move_scale / maxf(delta, 0.0001))
		player.velocity.x = v.x
		player.velocity.z = v.z
		player.cam_back = cfg.camera_back
	for i in GreatswordDarkComboRules.hits_between(t0, t, Array(cfg.hit_segment), Array(cfg.hit_at), lens, starts):
		if i < cfg.hit_count():
			_strike(player, d, i)
	if t >= cfg.total_time():
		player.end_ability()


## Quanto o herói já andou (espaço do modelo) no instante `t`: os golpes inteiros até a emenda e o atual até agora.
static func _root_total(t: float, lens: Array[float], starts: Array[float]) -> Vector3:
	var sa := GreatswordDarkComboRules.segment_at(t, lens, starts)
	var seg := int(sa.x)
	var cfg: GreatswordDarkComboConfig = CONFIG
	var acc := Vector3.ZERO
	for j in seg:
		acc += GreatswordDarkComboRules.root_at(KnightMovesGreatDark.ROOT[j], float(cfg.chain[j]) if j < cfg.chain.size() else 1.0)
	return acc + GreatswordDarkComboRules.root_at(KnightMovesGreatDark.ROOT[seg], sa.y)


## Um acerto (dono e réplicas): o visual sempre; o dano só no dono.
static func _strike(player: Node, d: Dictionary, i: int) -> void:
	var cfg: GreatswordDarkComboConfig = CONFIG
	var final := i == cfg.hit_count() - 1
	var yaw := float(d.get("yaw", 0.0))
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var origin: Vector3 = player.global_position
	var around := cfg.hit_arc[i] >= 359.0
	var skill = d.get("skill")
	if is_instance_valid(skill):
		var at := origin + fwd * 1.6
		var tip = player.look.get("tip")
		if not around and tip != null and is_instance_valid(tip) and tip.is_inside_tree():
			at = Vector3(tip.global_position.x, origin.y, tip.global_position.z)
		skill.burst(at if not around else origin, fwd, final)
		if final:
			skill.final_strike(origin, yaw, cfg.hit_reach[i])
	Sfx.play_at("sword_swing_heavy", origin, 0.12, -4.0 if final else -7.0)
	if player.remote:
		return
	if final:
		player.add_shake(cfg.final_shake)
	var dmg := Game.melee_damage() * cfg.hit_mult[i] * Game.ability_dmg_mult(ID)
	var cands := []
	for e in player.get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		cands.append({"pos": e.global_position, "radius": float(e.radius), "node": e})
	var n := 0
	for c in GreatswordDarkComboRules.pick_targets(cands, origin, fwd, cfg.hit_reach[i], cfg.hit_arc[i]):
		var e = c.node
		if not is_instance_valid(e) or e.dead:
			continue
		e.take_damage(dmg, origin, false, 0.0, cfg.final_stun if final else 0.0, -cfg.hit_knockback[i])
		Game.on_damage_dealt(dmg, e.max_hp)
		FXEpic.sparks(e.global_position + Vector3.UP * 0.8, fwd + Vector3.UP * 0.4, Color(0.5, 0.1, 0.9), 10, 8.0, 0.3)
		n += 1
	d["hits"] = int(d.get("hits", 0)) + n
	if n > 0:
		Sfx.play("sword_hit_flesh", 0.1, -2.0)
		if final:
			Sfx.play("sword_hit_heavy", 0.1)
			FXEpic.hit_stop(0.06)


static func release(_player: Node) -> void:
	pass


## A esquiva cancela o combo a qualquer momento (ele é longo: preso nele o herói não teria como fugir).
static func can_dodge_cancel(player: Node) -> bool:
	return player.ability == ID


static func dodge_cancel(player: Node) -> void:
	player.end_ability()


## Pose: o golpe atual do clipe, emendado no anterior nos primeiros `blend_time` s e, no fim do último, de volta à
## guarda de carregar.
static func pose(player: Node, p: Dictionary) -> void:
	var cfg: GreatswordDarkComboConfig = CONFIG
	var lens := cfg.lengths()
	var starts := cfg.starts()
	var t: float = player.ability_t
	var sa := GreatswordDarkComboRules.segment_at(t, lens, starts)
	var seg := int(sa.x)
	var w := smoothstep(0.0, maxf(cfg.blend_time, 0.001), t - starts[seg])
	var total := cfg.total_time()
	var back := smoothstep(total - cfg.back_time, total, t) if seg == lens.size() - 1 else 0.0
	KnightAnim.great_dark_pose(p, seg, sa.y, player.ability_data.get("from", {}), w, back)


static func play_remote(player: Node, kind: String, a: Vector3, b: Vector3) -> void:
	match kind:
		ID:
			_begin(player, b.x)
			if FX._scene() != null:
				Sfx.play_at("sword_swing_heavy", a, 0.1, -7.0)
		CANCEL_EVENT:
			if player.ability == ID:
				player.end_ability()


## Fim por qualquer caminho: no fim natural o visual termina sozinho; antes disso (esquiva, morte, troca de arma) se
## apaga depressa e as réplicas param junto.
static func _on_end(player: Node, d: Dictionary) -> void:
	var skill = d.get("skill")
	if not player.remote:
		player.cam_back = 0.0
	if not is_instance_valid(skill):
		return
	if player.ability_t < total_time() - 0.05:
		skill.stop()
		if not player.remote:
			Network.send_event(CANCEL_EVENT, player.global_position, Vector3.ZERO)
	else:
		skill.finish()


## Toca o visual uma vez, bem abaixo do mapa, para os shaders e pipelines ficarem prontos antes do primeiro combo da
## sessão (como GreatswordSpinAbilities.prewarm_instances). Chamado (deferred) pelo jogador local.
static func prewarm_instances(at: Node3D) -> void:
	var root := FX._scene()
	if root == null or at == null or not is_instance_valid(at) or not at.is_inside_tree():
		return
	var s: GreatswordDarkComboFX = SKILL.instantiate()
	s.config = CONFIG
	s.warm_only = true
	s.position = at.global_position + Vector3(0, -200, 0)   # já longe no _ready (as explosões nascem ali)
	root.add_child(s)
	s.global_position = at.global_position + Vector3(0, -200, 0)
