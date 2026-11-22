class_name GreatswordSupremeAbilities
extends RefCounted
## Lâmina Suprema: a ultimate da montante (espada de duas mãos). ItemDB "sword_supreme", "offhand": "two_handed": com
## a montante nas mãos ela troca o Turbilhão na tecla 4 e, como as outras ultimates, gasta a fúria cheia (Player.cast).
##   1. Carga: o herói ergue a montante acima da cabeça (clipe "Great Sword Casting" do Mixamo retargetado,
##      KnightMovesGreatCast) e fica parado com ela no alto enquanto uma energia sombria (violeta e carmesim, a das
##      garras do Corte do Abismo) cobre a lâmina da guarda até a ponta e vai crescendo até ~3x a altura dele, com
##      chamas escuras, fiapos de fumaça e faíscas sendo puxadas para ela.
##   2. Corte: gira a lâmina por trás, passa por cima da cabeça e crava a espada de energia no chão à frente.
##   3. Impacto: abre-se uma grande cratera em linha reta (3 m de largura) do herói para a frente, com as bordas de
##      pedra partida saltando do chão, e almas saem voando de dentro dela, fugindo em várias direções; quem está na
##      cratera ou no ponto do golpe leva dano (uma vez), atordoamento e empurrão. Depois a cratera fecha aos poucos.
## Sequência e visual: GreatswordSupremeSlash (cena própria na cena do mundo, se libera sozinha). Configuração em
## GreatswordSupremeConfig (assets/vfx/greatsword_supreme/greatsword_supreme_config.tres, editável no Inspector).
## Movimento: preso do começo ao fim (tick zera a velocidade e mantém o herói virado para o golpe); a esquiva só
## cancela durante a carga (antes do corte), sem dano e sem devolver a fúria.
## Rede: o dono manda "sword_supreme" (a = posição, b = (yaw, semente)): as réplicas tocam a mesma animação e o mesmo
## visual, sem dano. Cancelado antes do corte: "sword_supreme_cancel".

const ID := "sword_supreme"
const CANCEL_EVENT := "sword_supreme_cancel"
const SKILL := preload("res://scenes/vfx/greatsword_supreme/greatsword_supreme_slash.tscn")
const CONFIG := preload("res://assets/vfx/greatsword_supreme/greatsword_supreme_config.tres")
## A volta para a guarda começa nesta fração da fase de levantar.
const BACK_FROM := 0.55


static func use(player: Node, id: String) -> bool:
	if id != ID:
		return false
	var f: Vector3 = player.facing()
	var yaw := atan2(f.x, f.z)
	var seed_v := randi() % 65536
	_begin(player, yaw, seed_v)
	Network.send_event(ID, player.global_position, Vector3(yaw, float(seed_v), 0.0))
	Sfx.play("arcane_cast", 0.06, -2.0)
	return true


static func _begin(player: Node, yaw: float, seed_v: int) -> void:
	var skill: GreatswordSupremeSlash = null
	var root := FX._scene()
	if root != null:   # servidor dedicado: sem visual (o dano é do cliente dono)
		skill = SKILL.instantiate()
		skill.config = CONFIG
		skill.follow = player
		skill.yaw = yaw
		skill.seed_value = seed_v
		skill.deal_damage = not player.remote
		var lk: Dictionary = player.look
		skill.blade_base = lk.get("holder")
		skill.blade_tip = lk.get("tip")
		root.add_child(skill)
		if not player.remote:
			skill.impacted.connect(_on_impact.bind(weakref(player)))
	var d := {"skill": skill, "yaw": yaw, "from": KnightAnim.capture_pose(player.parts)}
	player.begin_ability(ID, d)
	d["on_end"] = _on_end.bind(player, d)


static func durations() -> Array[float]:
	return GreatswordSupremeRules.durations(CONFIG.raise_time, CONFIG.charge_time, CONFIG.slash_time, CONFIG.kneel_time,
		CONFIG.rise_time)


## Tempo total da habilidade no herói.
static func total_time() -> float:
	return CONFIG.total_time()


## Até quando a esquiva cancela (antes do corte).
static func cancel_window() -> float:
	return CONFIG.charge_end()


static func tick(player: Node, delta: float, _move_dir := Vector3.ZERO, _move_speed := 0.0) -> void:
	player.ability_t += delta
	var d: Dictionary = player.ability_data
	player.model.rotation.y = lerp_angle(player.model.rotation.y, float(d.get("yaw", 0.0)), 1.0 - exp(-12.0 * delta))
	if not player.remote:
		# parado do começo ao fim: a tecla de andar não move
		player.velocity.x = move_toward(player.velocity.x, 0.0, 40.0 * delta)
		player.velocity.z = move_toward(player.velocity.z, 0.0, 40.0 * delta)
		player.cam_back = CONFIG.camera_back
		# olha para cima enquanto a espada se forma; no corte volta para ver o chão
		player.cam_tilt = CONFIG.camera_tilt if player.ability_t < cancel_window() else 0.0
	if player.ability_t >= total_time():
		player.end_ability()


static func release(_player: Node) -> void:
	pass


static func can_dodge_cancel(player: Node) -> bool:
	return player.ability == ID and player.ability_t < cancel_window()


static func dodge_cancel(player: Node) -> void:
	player.end_ability()


## A animação do Mixamo em fases: erguer, segurar (a carga inteira, a fase do clipe esticada), cortar, ajoelhado e
## levantar, voltando para a guarda no fim.
static func pose(player: Node, p: Dictionary) -> void:
	var ph := GreatswordSupremeRules.phase_at(player.ability_t, durations())
	var phase := int(ph.x)
	var back := GreatswordSupremeRules.back_weight(ph.y, BACK_FROM) if phase == KnightMovesGreatCast.RISE else 0.0
	KnightAnim.great_cast_pose(p, phase, ph.y, player.ability_data.get("from", {}), back)


static func play_remote(player: Node, kind: String, a: Vector3, b: Vector3) -> void:
	match kind:
		ID:
			_begin(player, b.x, int(b.y))
			if FX._scene() != null:
				Sfx.play_at("arcane_cast", a, 0.06, -5.0)
		CANCEL_EVENT:
			if player.ability == ID:
				player.end_ability()


## Fim por qualquer caminho: antes do corte a aura é desfeita (sem dano); depois o visual segue sozinho.
static func _on_end(player: Node, d: Dictionary) -> void:
	var skill = d.get("skill")
	if is_instance_valid(skill) and skill.can_cancel():
		skill.cancel()
		if not player.remote:
			Network.send_event(CANCEL_EVENT, player.global_position, Vector3.ZERO)


## A espada de energia bateu (dono): dano, atordoamento e empurrão para longe do ponto do golpe em cada inimigo atingido.
static func _on_impact(center: Vector3, targets: Array, player_ref: WeakRef) -> void:
	var dmg := Game.melee_damage() * CONFIG.damage_mult * Game.ability_dmg_mult(ID)
	var any := false
	for e in targets:
		if not is_instance_valid(e) or e.dead:
			continue
		# a ultimate não recarrega a própria fúria (como a Flecha do Vendaval)
		e.take_damage(dmg, center, false, 0.0, CONFIG.stun_time, -CONFIG.knockback, ElementRules.NEUTRAL)
		Game.on_damage_dealt(dmg, e.max_hp, false)
		any = true
	if any:
		Sfx.play("sword_hit_heavy", 0.1)
	var player = player_ref.get_ref()
	if player != null and is_instance_valid(player) and CONFIG.hitstop_time > 0.0:
		FXEpic.hit_stop(CONFIG.hitstop_time)


## Toca o visual uma vez, bem abaixo do mapa, para os shaders e pipelines ficarem prontos antes da primeira ultimate
## da sessão (como FXEpic.prewarm_instances). Chamado (deferred) pelo jogador local.
static func prewarm_instances(at: Node3D) -> void:
	var root := FX._scene()
	if root == null or at == null or not is_instance_valid(at) or not at.is_inside_tree():
		return
	var s: GreatswordSupremeSlash = SKILL.instantiate()
	s.config = CONFIG
	s.warm_only = true
	root.add_child(s)
	s.global_position = at.global_position + Vector3(0, -200, 0)
