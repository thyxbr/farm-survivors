class_name GreatswordSpinAbilities
extends RefCounted
## Ciclone de Aço: a habilidade da tecla 1 com a montante (espada de duas mãos). ItemDB "sword_spin", "offhand":
## "two_handed": com a montante nas mãos ela troca a Investida (Game.offhand_kind / ItemDB.kit).
##   1. Assim que aciona: o herói ergue a montante com as duas mãos, os braços esticados para a frente, junta os pés e
##      já começa a girar (sem postura parada antes do giro).
##   2. Giro: gira no próprio eixo (Y), ganhando velocidade, e inclina o corpo para trás (contrapeso da lâmina); cortes
##      de lâmina da sprite sheet 8x8 (aditiva) varrem em volta dele em vários ângulos e cada inimigo no alcance leva
##      um corte a cada `hit_interval`.
##   3. Desaceleração: o giro perde velocidade aos poucos, os cortes param de surgir e se dissipam (Tween) e o herói
##      para virado para onde começou, com o corpo voltando ao normal, e volta à guarda.
## Ritmo, dano e visual em GreatswordSpinConfig (assets/vfx/greatsword_spin/greatsword_spin_config.tres, no Inspector);
## as contas (fase, velocidade, ângulo, quem leva corte) em GreatswordSpinRules; o visual e a detecção em
## GreatswordSpinSlash (cena própria na cena do mundo, se libera sozinha).
## Movimento: preso do começo ao fim (tick zera a velocidade e gira o modelo); a esquiva não cancela (o giro
## começa na hora; só com `stance_time` > 0 na configuração a esquiva cancela nessa postura parada).
## Rede: o dono manda "sword_spin" (a = posição, b = (yaw, 0, 0)): as réplicas tocam a mesma pose e o mesmo visual, sem
## dano. Cancelado: "sword_spin_cancel".

const ID := "sword_spin"
const CANCEL_EVENT := "sword_spin_cancel"
const SKILL := preload("res://scenes/vfx/greatsword_spin/greatsword_spin_slash.tscn")
const CONFIG := preload("res://assets/vfx/greatsword_spin/greatsword_spin_config.tres")

## A lâmina na postura (espaço do modelo, como KnightMoves.GREAT_GUARD: `end` = mão de baixo, `dir` = do pomo para a
## ponta, `edge` = para onde o gume aponta): os dois braços erguidos e esticados para a frente, as mãos juntas no cabo
## na altura do peito (longe o bastante para o IK deixar os braços retos), a lâmina reta à frente, o gume virado para o
## lado para onde a lâmina corre no giro (+X: o giro aumenta o yaw do modelo).
const STANCE_TOOL := {"end": Vector3(0.0, 1.27, 0.52), "dir": Vector3(0.0, -0.04, 1.0), "edge": Vector3(1.0, 0.0, 0.0),
	"slide": 0.0, "left": 1.0}
## No giro: os braços seguem esticados e a lâmina deita um pouco, arrastada para trás pelo giro.
const SPIN_TOOL := {"end": Vector3(0.03, 1.22, 0.52), "dir": Vector3(-0.14, -0.02, 1.0), "edge": Vector3(1.0, 0.0, 0.14),
	"slide": 0.0, "left": 1.0}
## Pés juntos e joelhos soltos (substitui a base afastada da guarda, KnightMoves.GREAT_STANCE).
const STANCE_LEGS := {"leg_l": 0.0, "leg_r": 0.0, "side_l": 0.02, "side_r": 0.02, "knee_l": 0.14, "knee_r": 0.14,
	"twist": 0.0, "hip_twist": 0.0, "leg_yaw": 0.0, "body_z": 0.0}
## Passinhos no giro: os pés trocam de apoio acompanhando as voltas (não patinam parados).
const STEP_SWING := 0.14
const STEP_KNEE := 0.12
## Tempo para os braços saírem da guarda e ficarem esticados à frente (s): curto, já com o giro começando.
const ARM_BLEND := 0.1


static func use(player: Node, id: String) -> bool:
	if id != ID:
		return false
	var yaw: float = player.model.rotation.y
	_begin(player, yaw)
	Network.send_event(ID, player.global_position, Vector3(yaw, 0.0, 0.0))
	Sfx.play("sword_swing", 0.1, -6.0)
	return true


static func _begin(player: Node, yaw: float) -> void:
	var skill: GreatswordSpinSlash = null
	var root := FX._scene()
	if root != null:   # servidor dedicado: sem visual (o dano é do cliente dono)
		skill = SKILL.instantiate()
		skill.config = CONFIG
		skill.follow = player
		skill.model = player.model
		skill.deal_damage = not player.remote
		root.add_child(skill)
		if not player.remote:
			skill.hit.connect(_on_hit.bind(weakref(player)))
	var d := {"skill": skill, "yaw0": yaw, "from": KnightAnim.capture_pose(player.parts)}
	player.begin_ability(ID, d)
	d["on_end"] = _on_end.bind(player, d)


static func durations() -> Array[float]:
	return CONFIG.durations()


## Tempo total da habilidade no herói.
static func total_time() -> float:
	return CONFIG.total_time()


## Até quando a esquiva cancela: a postura parada (`stance_time`; 0 = nunca, o giro começa na hora).
static func cancel_window() -> float:
	return durations()[GreatswordSpinRules.Phase.STANCE]


static func tick(player: Node, delta: float, _move_dir := Vector3.ZERO, _move_speed := 0.0) -> void:
	player.ability_t += delta
	var d: Dictionary = player.ability_data
	var t: float = player.ability_t
	# o giro do modelo (na réplica também: durante a habilidade o yaw da rede é ignorado). `yaw0` também faz o
	# end_ability devolver o herói virado para onde começou, mesmo se ela acabar no meio do giro.
	player.model.rotation.y = wrapf(float(d.get("yaw0", 0.0)) + GreatswordSpinRules.angle(t, durations(), CONFIG.turns), -PI, PI)
	if not player.remote:
		# preso do começo ao fim: a tecla de andar não move
		player.velocity.x = move_toward(player.velocity.x, 0.0, 40.0 * delta)
		player.velocity.z = move_toward(player.velocity.z, 0.0, 40.0 * delta)
		# a câmera recua enquanto gira (o player suaviza a ida e a volta)
		var ph := int(GreatswordSpinRules.phase_at(t, durations()).x)
		var spinning := ph >= GreatswordSpinRules.Phase.ACCEL and ph <= GreatswordSpinRules.Phase.DECEL
		player.cam_back = CONFIG.camera_back if spinning else 0.0
	if t >= total_time():
		player.end_ability()


static func release(_player: Node) -> void:
	pass


static func can_dodge_cancel(player: Node) -> bool:
	return player.ability == ID and CONFIG.stance_time > 0.0 and player.ability_t < cancel_window()


static func dodge_cancel(player: Node) -> void:
	player.end_ability()


## Pose: postura (espada à frente, pés juntos, corpo para trás), giro com passinhos e a volta à guarda. A arma vai por IK
## pelas duas mãos (p["tool"], como na Lâmina Suprema); o giro em si é o do modelo (tick).
static func pose(player: Node, p: Dictionary) -> void:
	var durs := durations()
	var t: float = player.ability_t
	var total := total_time()
	# os braços vão à frente em ARM_BLEND, já girando (sem postura parada não dá para ver a espada virar antes do giro)
	var w_in := smoothstep(0.0, maxf(durs[GreatswordSpinRules.Phase.STANCE], ARM_BLEND), t)
	var w_out := 1.0 - smoothstep(total - durs[GreatswordSpinRules.Phase.RECOVER], total, t)
	var w := w_in * w_out
	var spd := GreatswordSpinRules.speed_frac(t, durs)
	KnightAnim.drop_gait_comp(p)
	for j in STANCE_LEGS:
		p[j] = lerpf(float(p.get(j, 0.0)), float(STANCE_LEGS[j]), w)
	# contrapeso: na postura o tronco fica reto; quando começa a girar ele inclina para trás (a cabeça segue olhando
	# para a frente) e volta ao normal no fim da animação (GreatswordSpinRules.lean_weight)
	var lw := GreatswordSpinRules.lean_weight(t, durs)
	p["body_x"] = lerpf(float(p.get("body_x", 0.0)), -CONFIG.lean, lw)
	p["head_x"] = lerpf(float(p.get("head_x", 0.0)), CONFIG.lean * 0.7, lw)
	p["body_y"] = float(p.get("body_y", 0.0)) - 0.03 * w
	# passinhos acompanhando as voltas
	var ang := GreatswordSpinRules.angle(t, durs, CONFIG.turns)
	var s := sin(ang * 2.0) * spd * w
	p["leg_l"] = float(p.leg_l) + STEP_SWING * s
	p["leg_r"] = float(p.leg_r) - STEP_SWING * s
	p["knee_l"] = float(p.knee_l) + STEP_KNEE * maxf(s, 0.0)
	p["knee_r"] = float(p.knee_r) + STEP_KNEE * maxf(-s, 0.0)
	# a arma: da pose em que estava (capture_pose) para a postura, dela para a do giro com a velocidade, e no fim de
	# volta para a guarda de carregar
	var held := KnightAnim.great_mix(STANCE_TOOL, SPIN_TOOL, spd)
	var from: Dictionary = player.ability_data.get("from", {})
	var start: Dictionary = from.get("tool", KnightMoves.GREAT_GUARD)
	var tl: Dictionary
	if w_out < 1.0:
		tl = _blend_tool(held, KnightMoves.GREAT_GUARD, 1.0 - w_out)
	else:
		tl = _blend_tool(start, held, w_in)
	tl.end = (tl.end as Vector3) + Vector3(0.0, float(p.get("body_y", 0.0)), 0.0)
	tl["w"] = 1.0
	tl["grip"] = KnightMoves.GREAT_GRIP
	p["tool"] = tl


## Mistura duas posições da lâmina (`k` 0..1): a ponta gira pelo caminho de cima (KnightAnim.blade_turn), sem cortar
## por dentro do corpo.
static func _blend_tool(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	k = clampf(k, 0.0, 1.0)
	var da := (a.dir as Vector3).normalized()
	var q := KnightAnim.blade_turn(da, b.dir as Vector3, k)
	var tl := KnightAnim.great_mix(a, b, k)
	tl.dir = q * da
	return tl


static func play_remote(player: Node, kind: String, a: Vector3, b: Vector3) -> void:
	match kind:
		ID:
			_begin(player, b.x)
			if FX._scene() != null:
				Sfx.play_at("sword_swing", a, 0.1, -8.0)
		CANCEL_EVENT:
			if player.ability == ID:
				player.end_ability()


## Fim por qualquer caminho: antes do fim natural (esquiva, morte, troca de arma) o visual se apaga depressa.
static func _on_end(player: Node, d: Dictionary) -> void:
	var skill = d.get("skill")
	if not is_instance_valid(skill):
		return
	if player.ability_t < total_time() - 0.05:
		skill.stop()
		if not player.remote:
			Network.send_event(CANCEL_EVENT, player.global_position, Vector3.ZERO)


## Cortes do giro (dono): dano e um leve puxão para dentro em cada inimigo atingido, fagulhas para onde a lâmina corre.
static func _on_hit(targets: Array, player_ref: WeakRef) -> void:
	var player = player_ref.get_ref()
	if player == null or not is_instance_valid(player):
		return
	var base: Vector3 = player.global_position
	var dmg: float = Game.melee_damage() * CONFIG.damage_mult * Game.ability_dmg_mult(ID)
	var n := 0
	for e in targets:
		if not is_instance_valid(e) or e.dead:
			continue
		e.take_damage(dmg, base, false, 0.0, 0.0, CONFIG.pull)
		Game.on_damage_dealt(dmg, e.max_hp)
		if n < 6:
			var to: Vector3 = e.global_position - base
			to.y = 0.0
			var along := Vector3.UP.cross(to).normalized() if to.length() > 0.01 else Vector3.UP
			FXEpic.sparks(e.global_position + Vector3.UP * 0.6, along + Vector3.UP * 0.3, Color(1.0, 0.7, 0.35), 8, 7.0, 0.25)
		n += 1
	if n > 0:
		Sfx.play_at("sword_hit_flesh", base, 0.1, -3.0)
		player.add_shake(0.08)


## Toca o visual uma vez, bem abaixo do mapa, para os shaders e pipelines ficarem prontos antes do primeiro giro da
## sessão (como GreatswordSupremeAbilities.prewarm_instances). Chamado (deferred) pelo jogador local.
static func prewarm_instances(at: Node3D) -> void:
	var root := FX._scene()
	if root == null or at == null or not is_instance_valid(at) or not at.is_inside_tree():
		return
	var s: GreatswordSpinSlash = SKILL.instantiate()
	s.config = CONFIG
	s.warm_only = true
	root.add_child(s)
	s.global_position = at.global_position + Vector3(0, -200, 0)
