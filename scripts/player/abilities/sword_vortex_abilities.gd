class_name SwordVortexAbilities
extends RefCounted
## Vórtice Sombrio: a habilidade da tecla 5 da espada de uma mão sem escudo (ItemDB "sword_vortex"; com escudo a tecla
## 5 é do Grito do Bastião) e da tecla 6 da montante ("sword_vortex_great": a mesma habilidade, a 5 da montante é a
## Fúria Picante).
##   1. Preparo (WINDUP): agacha com a espada para trás, o corpo torcido; a luz violeta acende no chão.
##   2. Giro (SPIN): gira no próprio eixo com o braço esticado e a lâmina deitada, acelerando. O braço vai subindo a
##      cada volta (em rosca, HELIX_LOW .. HELIX_HIGH), e o corte que segue a lâmina fica em vários níveis. Fitas de energia sombria
##      (fumaça quase preta com a borda violeta acesa) correm em espiral em volta do herói; cada meia volta corta quem
##      estiver a até SPIN_RADIUS (o alvo pisca dourado e solta faíscas).
##   3. Golpe final (FINALE): a última meia volta, que fecha de frente para onde o giro começou, é o corte forte: um
##      clarão violeta, um risco de luz na horizontal e raios para cima; depois uma meia-lua enorme de fumaça negra e
##      violeta fica no ar sobre o caminho da lâmina e se desfaz, com lascas escuras e uma chuva de faíscas.
##   4. Volta à guarda (RECOVER).
## O visual inteiro em SwordVortexFX (feito em código, na cena do mundo, se libera sozinho).
## Movimento: anda devagar girando (como o Turbilhão). A esquiva só cancela no preparo.
## Rede: o dono manda "sword_vortex" (a = posição, b = (yaw, 0, 0)): as réplicas tocam a mesma pose e o mesmo visual,
## sem dano. Cancelado: "sword_vortex_cancel".

const ID := "sword_vortex"
const CANCEL_EVENT := "sword_vortex_cancel"
const GREAT_ID := "sword_vortex_great"
## Rosca: quanto o braço da espada fica abaixo (+) e acima (-) da altura do giro no começo e no fim (rad no ombro).
const HELIX_LOW := 0.42
const HELIX_HIGH := -0.3
## Montante no preparo: o cabo do lado direito, na cintura, e a lâmina para trás e para baixo (espaço do modelo, como
## KnightMoves.GREAT_GUARD: `end` = mão de baixo, `dir` = do pomo para a ponta, `edge` = para onde o gume aponta).
const WIND_TOOL := {"end": Vector3(-0.32, 0.95, 0.1), "dir": Vector3(-0.55, -0.35, -0.75), "edge": Vector3(0.6, 0.0, -0.8),
	"slide": 0.0, "left": 1.0}

const WINDUP := 0.22
const SPIN := 1.0           ## voltas de TURNS - 0.5, acelerando
const FINALE := 0.24        ## a última meia volta (o corte forte), freando no fim
const RECOVER := 0.4
const TOTAL := WINDUP + SPIN + FINALE + RECOVER
const TURNS := 4.0          ## voltas inteiras: termina virado para onde começou
const RAMP := 0.25          ## o giro acelera nos primeiros RAMP s
const BRAKE := 0.16         ## e freia nos últimos BRAKE s do golpe final
const WIND_BACK := -0.45    ## no preparo o corpo torce para trás (rad) antes de girar

const SPIN_RADIUS := 3.0
const SPIN_MULT := 0.55     ## dano de cada corte do giro = Game.melee_damage() * SPIN_MULT
const SPIN_PULL := 3.0
const FINAL_RADIUS := 4.6
const FINAL_ARC := -0.25    ## cosseno: o golpe final acerta à frente e dos lados (~105° para cada lado)
const FINAL_MULT := 2.6
const FINAL_STUN := 0.8
const WALK := 0.35
const CAM_BACK := 0.8

## Pose (KnightAnim.play_track, fração do TOTAL): preparo agachado com a espada para trás, o giro de braço esticado
## e lâmina deitada (o do Turbilhão, KnightMoves.WHIRL), o mesmo no golpe final, e a volta.
const TRACK := [
	[0.1, {"arm_r": Vector3(0.5, 0.3, -0.55), "elbow_r": -0.6, "wrist_r": -2.8, "twist": -0.95,
		"body_x": 0.4, "body_y": -0.14, "body_z": 0.08, "head_x": -0.3, "head_y": 0.65,
		"arm_l": Vector3(0.15, -0.6, -0.35), "elbow_l": -1.1,
		"leg_l": -0.7, "knee_l": 1.2, "leg_r": 0.5, "knee_r": 1.0}, "out"],
	[0.16, {"arm_r": Vector3(-1.75, -0.2, -0.75), "elbow_r": -0.1, "wrist_r": 1.45, "twist": 0.1,
		"body_x": 0.32, "body_y": -0.12, "body_z": 0.16, "head_x": -0.1, "head_y": 0.0,
		"arm_l": Vector3(-0.2, 0.0, 1.1), "elbow_l": -0.3,
		"leg_l": -0.45, "knee_l": 0.95, "leg_r": 0.4, "knee_r": 0.9}, "in"],
	[0.62, {"arm_r": Vector3(-1.75, -0.2, -0.75), "elbow_r": -0.1, "wrist_r": 1.45, "twist": 0.1,
		"body_x": 0.32, "body_y": -0.12, "body_z": 0.16,
		"arm_l": Vector3(-0.2, 0.0, 1.1), "elbow_l": -0.3,
		"leg_l": -0.45, "knee_l": 0.95, "leg_r": 0.4, "knee_r": 0.9}, "lin"],
	# golpe final: o corpo abre e se joga no corte (mais baixo e mais esticado)
	[0.76, {"arm_r": Vector3(-1.6, -0.35, -1.0), "elbow_r": 0.0, "wrist_r": 1.5, "twist": 0.45,
		"body_x": 0.42, "body_y": -0.2, "body_z": 0.22, "head_x": -0.05,
		"arm_l": Vector3(-0.1, 0.2, 1.3), "elbow_l": -0.2,
		"leg_l": -0.7, "knee_l": 1.05, "leg_r": 0.55, "knee_r": 0.85}, "out"],
	[0.9, {"arm_r": Vector3(-1.2, -0.3, -0.6), "elbow_r": -0.3, "wrist_r": 1.2, "twist": 0.3,
		"body_x": 0.3, "body_y": -0.14, "body_z": 0.1,
		"arm_l": Vector3(-0.1, 0.0, 0.7), "elbow_l": -0.4,
		"leg_l": -0.55, "knee_l": 0.9, "leg_r": 0.45, "knee_r": 0.75}, "in"],
]


static func use(player: Node, id: String) -> bool:
	if (id != ID and id != GREAT_ID) or player._unarmed():   # de mãos vazias não tem lâmina para o redemoinho
		return false
	var yaw: float = player.model.rotation.y
	_begin(player, yaw)
	Network.send_event(ID, player.global_position, Vector3(yaw, 0.0, 0.0))
	Sfx.play("sword_swing", 0.1, -3.0)
	return true


static func _begin(player: Node, yaw: float) -> void:
	var fx: SwordVortexFX = null
	if FX._scene() != null:   # servidor dedicado: sem visual
		fx = SwordVortexFX.new()
		fx.follow = player
		fx.model = player.model
		fx.blade_base = player.look.get("holder")
		fx.blade_tip = player.look.get("tip")
		fx.color = SwordVortexFX.VIOLET
		FX._scene().add_child(fx)
	var d := {"fx": fx, "yaw0": yaw, "half": 0, "final_done": false, "from": KnightAnim.capture_pose(player.parts)}
	player.begin_ability(ID, d)
	d["on_end"] = _on_end.bind(player, d)


static func total_time() -> float:
	return TOTAL


## Ângulo do giro (rad, somado ao yaw de partida) no tempo `t` da habilidade: torce para trás no preparo, acelera em
## RAMP, gira a velocidade constante e freia em BRAKE, fechando TURNS voltas no fim do golpe final.
static func angle(t: float) -> float:
	if t <= WINDUP:
		return WIND_BACK * smoothstep(0.0, WINDUP, t)
	var s := t - WINDUP
	var dur := SPIN + FINALE
	if s >= dur:
		return TURNS * TAU
	var total := TURNS * TAU - WIND_BACK   # sai da torção
	var vmax := total / (dur - RAMP * 0.5 - BRAKE * 0.5)
	var a: float
	if s < RAMP:
		a = 0.5 * vmax / RAMP * s * s
	elif s < dur - BRAKE:
		a = vmax * (s - RAMP * 0.5)
	else:
		var r := dur - s
		a = total - 0.5 * vmax / BRAKE * r * r
	return WIND_BACK + a


## Onde começa o golpe final (s): o giro passa de TURNS - 0,5 voltas.
static func finale_at() -> float:
	return WINDUP + SPIN


static func tick(player: Node, delta: float, move_dir := Vector3.ZERO, move_speed := 0.0) -> void:
	var t0: float = player.ability_t
	player.ability_t += delta
	var t: float = player.ability_t
	var d: Dictionary = player.ability_data
	player.model.rotation.y = wrapf(float(d.get("yaw0", 0.0)) + angle(t), -PI, PI)
	var fx = d.get("fx")
	if is_instance_valid(fx):
		fx.set_phase(t)
		if t0 < finale_at() and t >= finale_at():
			fx.finale_start()
		if t0 < finale_at() + FINALE and t >= finale_at() + FINALE:
			fx.finale_end()
	if not player.remote:
		var spinning := t > WINDUP and t < finale_at() + FINALE
		var want := move_dir * move_speed * WALK if spinning else Vector3.ZERO
		var k := 1.0 - exp(-8.0 * delta)
		player.velocity.x = lerpf(player.velocity.x, want.x, k)
		player.velocity.z = lerpf(player.velocity.z, want.z, k)
		player.cam_back = CAM_BACK if spinning else 0.0
		# um corte a cada meia volta do giro (antes do golpe final)
		var half := int(floor(maxf(angle(t) - 0.0, 0.0) / PI))
		if t > WINDUP and t < finale_at() and half > int(d.half):
			d.half = half
			_spin_hit(player)
		# o golpe final acerta no meio da última meia volta (a lâmina passando pela frente)
		if not d.final_done and t >= finale_at() + FINALE * 0.45:
			d.final_done = true
			_final_hit(player, float(d.yaw0))
	if t >= TOTAL:
		player.end_ability()


static func release(_player: Node) -> void:
	pass


static func can_dodge_cancel(player: Node) -> bool:
	return player.ability == ID and player.ability_t < WINDUP


static func dodge_cancel(player: Node) -> void:
	player.end_ability()


static func pose(player: Node, p: Dictionary) -> void:
	var t: float = player.ability_t
	KnightAnim.play_track(p, TRACK, clampf(t / TOTAL, 0.0, 1.0), 0.0)
	# passinhos: os pés trocam de apoio acompanhando as voltas
	var s := t - WINDUP
	if s > 0.0 and s < SPIN + FINALE:
		var w := sin(angle(t)) * smoothstep(0.0, RAMP, s) * (1.0 - smoothstep(SPIN, SPIN + FINALE, s))
		p.leg_l += 0.2 * w
		p.leg_r -= 0.2 * w
		p.knee_l += 0.15 * maxf(w, 0.0)
		p.knee_r += 0.15 * maxf(-w, 0.0)
		p.body_y -= 0.02 * absf(w)
		# rosca: o braço sobe aos poucos ao longo das voltas (com um leve sobe e desce a cada volta), então a lâmina
		# corta em vários níveis; no golpe final volta à altura do giro
		p.arm_r = (p.arm_r as Vector3) + Vector3(helix_lift(t), 0.0, 0.0)
	if player._great():
		_great_tool(player, p)


## Rosca: quanto o braço fica abaixo (+) ou acima (-) da altura do giro no tempo `t` (rad no ombro). Sobe aos poucos ao
## longo das voltas, com um leve sobe e desce a cada volta; no golpe final volta à altura do giro.
static func helix_lift(t: float) -> float:
	var s := t - WINDUP
	if s <= 0.0 or s >= SPIN + FINALE:
		return 0.0
	var k := clampf(s / SPIN, 0.0, 1.0)
	var lift := lerpf(HELIX_LOW, HELIX_HIGH, smoothstep(0.0, 1.0, k)) + 0.08 * sin(angle(t) * 0.5)
	return lift * (1.0 - smoothstep(SPIN, SPIN + FINALE * 0.6, s))


## Montante: as duas mãos no cabo, por IK (p["tool"], como no Ciclone de Aço). Preparo: a lâmina vai para trás e para
## baixo, em diagonal pelo lado; giro: braços esticados à frente e a lâmina deitada, subindo e descendo com a rosca
## (helix_lift inclina a lâmina); volta: de novo à guarda de carregar.
static func _great_tool(player: Node, p: Dictionary) -> void:
	var t: float = player.ability_t
	var w_in := smoothstep(0.0, WINDUP * 0.7, t)
	var spin_in := smoothstep(WINDUP * 0.6, WINDUP + 0.08, t)
	var w_out := 1.0 - smoothstep(TOTAL - RECOVER, TOTAL, t)
	var lift := helix_lift(t)
	# no giro: a lâmina inclina para baixo (lift > 0) ou para cima (lift < 0) e o cabo acompanha
	var spin_tool := {"end": Vector3(0.03, 1.2 - 0.18 * lift, 0.5), "dir": Vector3(-0.14, -0.7 * lift, 1.0).normalized(),
		"edge": Vector3(1.0, 0.0, 0.14), "slide": 0.0, "left": 1.0}
	var from: Dictionary = player.ability_data.get("from", {})
	var start: Dictionary = from.get("tool", KnightMoves.GREAT_GUARD)
	var tl: Dictionary
	if w_out < 1.0:
		tl = GreatswordSpinAbilities._blend_tool(spin_tool, KnightMoves.GREAT_GUARD, 1.0 - w_out)
	else:
		var wind := GreatswordSpinAbilities._blend_tool(start, WIND_TOOL, w_in)
		tl = GreatswordSpinAbilities._blend_tool(wind, spin_tool, spin_in)
	tl.end = (tl.end as Vector3) + Vector3(0.0, float(p.get("body_y", 0.0)), 0.0)
	tl["w"] = 1.0
	tl["grip"] = KnightMoves.GREAT_GRIP
	p["tool"] = tl


static func play_remote(player: Node, kind: String, a: Vector3, b: Vector3) -> void:
	match kind:
		ID:
			_begin(player, b.x)
			if FX._scene() != null:
				Sfx.play_at("sword_swing", a, 0.1, -6.0)
		CANCEL_EVENT:
			if player.ability == ID:
				player.end_ability()


## Fim por qualquer caminho: antes do fim natural (esquiva, morte, troca de arma) o visual se apaga depressa.
static func _on_end(player: Node, d: Dictionary) -> void:
	var fx = d.get("fx")
	if not is_instance_valid(fx):
		return
	if player.ability_t < TOTAL - 0.05:
		fx.stop()
		if not player.remote:
			Network.send_event(CANCEL_EVENT, player.global_position, Vector3.ZERO)
	else:
		fx.finish()


## Corte do giro (dono): dano e um puxão leve em quem estiver em volta; o alvo pisca dourado e solta faíscas.
static func _spin_hit(player: Node) -> void:
	var base: Vector3 = player.global_position
	var dmg: float = Game.melee_damage() * SPIN_MULT * Game.ability_dmg_mult(ID)
	var fx = player.ability_data.get("fx")
	var n := 0
	for e in player.get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var to: Vector3 = e.global_position - base
		to.y = 0.0
		if to.length() > SPIN_RADIUS + float(e.radius):
			continue
		e.take_damage(dmg, base, false, 0.0, 0.0, SPIN_PULL)
		Game.on_damage_dealt(dmg, e.max_hp)
		if is_instance_valid(fx) and n < 6:
			fx.spin_hit(e)
		n += 1
	if n > 0:
		Sfx.play_at("sword_hit_flesh", base, 0.1, -4.0)
		player.add_shake(0.06)


## Golpe final (dono): dano forte e atordoamento à frente e dos lados.
static func _final_hit(player: Node, yaw0: float) -> void:
	var base: Vector3 = player.global_position
	var f := Vector3(sin(yaw0), 0.0, cos(yaw0))
	var dmg: float = Game.melee_damage() * FINAL_MULT * Game.ability_dmg_mult(ID)
	var fx = player.ability_data.get("fx")
	var n := 0
	for e in player.get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var to: Vector3 = e.global_position - base
		to.y = 0.0
		var dist := to.length()
		if dist > FINAL_RADIUS + float(e.radius):
			continue
		if dist > 0.6 and f.dot(to / dist) < FINAL_ARC:
			continue
		var crit: bool = randf() < Game.crit_chance()
		var dd := dmg * (1.8 if crit else 1.0)
		e.take_damage(dd, base, crit, 0.0, FINAL_STUN, 0.0)
		Game.on_damage_dealt(dd, e.max_hp)
		if is_instance_valid(fx) and n < 4:
			fx.final_hit(e)
		n += 1
	Sfx.play_at("sword_hit_flesh" if n > 0 else "sword_swing_heavy", base, 0.1, 0.0)
	player.add_shake(0.35 if n > 0 else 0.2)
	if n > 0:
		FXEpic.hit_stop(0.08, 0.06)
