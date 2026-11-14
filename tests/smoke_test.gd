extends Node
## Teste de fumaça do gameplay. Rode com:
##   godot --headless --path . res://scenes/world.tscn -- --smoketest
## Imprime PASS/FAIL para cada verificação e encerra com código 0 (ok) ou 1 (falhas).

const UPG := preload("res://scripts/survival/upgrades.gd")

var fails := 0
var world: Node
var player: Player


func check(cond: bool, what: String) -> void:
	if cond:
		print("PASS  ", what)
	else:
		fails += 1
		print("FAIL  ", what)


## Ids das habilidades mostradas nos slots 1-4 da barra de ações (pelo ícone).
func hud_slot_ids() -> Array[String]:
	var out: Array[String] = []
	var hud = world.hud
	for n in range(1, 5):
		var icon: String = hud.slots["slot_%d" % n].icon_kind
		var found := ""
		for id in ItemDB.ABILITIES:
			if ItemDB.ABILITIES[id].icon == icon and ItemDB.ABILITIES[id].slot == n and ItemDB.ABILITIES[id]["class"] == Game.weapon_class():
				found = id
		if found != "":
			out.append(found)
	return out


func wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, true).timeout


## Espera até `cond` ficar verdadeira ou estourar `timeout` (evita folgas fixas frágeis).
func wait_until(cond: Callable, timeout := 3.0) -> void:
	var t := 0.0
	while t < timeout and not cond.call():
		await wait(0.05)
		t += 0.05


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await wait(0.5)
	world = get_tree().current_scene
	player = get_tree().get_first_node_in_group("player")
	check(world != null and player != null, "mundo e jogador carregados")
	# confere o kit antes de qualquer combate: slimes podem soltar cajado/arco e o saque é aleatório
	check(Game.count_item("apprentice_staff") == 1 and Game.count_item("short_bow") == 1, "kit inicial tem cajado e arco")

	# --- som posicional: combate longe do jogador não deve ser ouvido
	check(Sfx.distance_gain(0.0) == 1.0 and Sfx.distance_gain(15.0) < 0.5 and Sfx.distance_gain(Sfx.FAR_DIST + 1.0) == 0.0,
		"volume do som do mundo cai com a distância")
	var slot0: int = Sfx._next_3d
	Sfx.play_at("hit", player.global_position + Vector3(Sfx.FAR_DIST + 5.0, 0, 0))
	check(Sfx._next_3d == slot0, "som de combate longe do jogador é descartado")
	var near_pos := player.global_position + Vector3(10, 0, 0)
	Sfx.play_at("hit", near_pos)
	var used: AudioStreamPlayer3D = Sfx._players_3d[slot0]
	check(Sfx._next_3d != slot0 and used.global_position.is_equal_approx(near_pos) and used.volume_db < -1.0,
		"som de combate perto toca no lugar certo, mais baixo (%.1f dB)" % used.volume_db)
	var slot_anvil: int = Sfx._next_3d
	Sfx.play_at("anvil", player.global_position + Vector3(2, 0, 0))
	check(Sfx._next_3d != slot_anvil, "som da bigorna toca perto do jogador")
	check(get_tree().get_nodes_in_group("enemies").size() >= 15, "inimigos spawnados (%d)" % get_tree().get_nodes_in_group("enemies").size())
	check(get_tree().get_nodes_in_group("interactable").size() == 4 + Game.FARM_PLOTS + 1,
		"3 NPCs + portal + %d canteiros + caldeirão interagíveis" % Game.FARM_PLOTS)

	# --- diálogo e missão
	var elder: Node = null
	for n in get_tree().get_nodes_in_group("interactable"):
		if n.npc_id == "elder":
			elder = n
	player.global_position = elder.global_position + Vector3(0, 0.2, 1.5)
	await wait(0.3)
	check(player.interact_target == elder, "jogador detecta o ancião para interagir")
	elder.interact(player)
	await wait(0.1)
	check(world.modal != null and get_tree().paused, "diálogo abre e pausa o jogo")
	check(world.modal.size.x > 100 and world.modal.size.y > 100, "janela de diálogo ocupa a tela (%s)" % world.modal.size)
	var pages: Array = world.modal.pages
	var last: Dictionary = pages[pages.size() - 1]
	check(last.has("choices"), "diálogo oferece escolha de missão")
	world.modal._choose(last.choices[0].action)
	await wait(0.1)
	check(Game.quest_state("slimes") == "active", "missão dos slimes aceita")
	check(world.modal == null and not get_tree().paused, "diálogo fecha e despausa")
	await _test_blacksmith()

	# --- combate corpo a corpo
	var slime := _nearest("slime")
	var xp0 := Game.xp
	var gold0 := Game.gold
	player.global_position = slime.global_position + Vector3(0, 0.3, 1.2)
	player.model.rotation.y = PI
	await wait(0.2)
	var hp0: float = slime.hp
	Game.fury = 0.0
	player._start_swing()
	await wait(0.5)
	check(Game.fury > 0.0 and Game.fury < 10.0, "fúria sobe com o dano do golpe do jogador (%.2f)" % Game.fury)
	Game.fury = 0.0
	check(slime.hp < hp0, "golpe de espada causa dano (%.0f -> %.0f)" % [hp0, slime.hp])
	slime.take_damage(9999, player.global_position, false)
	check(Game.xp > xp0, "XP ganho ao matar slime")
	check(Game.quests.slimes.progress == 1, "progresso da missão 1/5")
	player.global_position = slime.global_position + Vector3(0, 0.3, 0)
	await wait(2.5)
	check(Game.gold > gold0, "ouro coletado do chão (%d -> %d)" % [gold0, Game.gold])

	# --- acerto de longe num slime parado em casa: ele persegue, não volta para casa curando o dano
	var far_s := _nearest("slime")
	far_s.global_position = far_s.home
	far_s._set_state("idle")
	player.global_position = far_s.home + Vector3(0, 0.3, far_s.data.aggro * 2.5)
	await wait(0.1)
	var far_hp: float = far_s.hp
	far_s.take_damage(10.0, player.global_position, false)
	await wait(0.4)
	check(far_s.hp < far_hp and far_s.state == "chase",
		"acerto de longe não é curado na hora (%.0f -> %.0f, %s)" % [far_hp, far_s.hp, far_s.state])

	# --- Investida (espada, slot 1): avança pela frente atravessando o slime
	var pos_c := player.global_position
	var ch_s := _nearest("slime")
	ch_s.global_position = ch_s.home
	player.global_position = ch_s.global_position + Vector3(0, 0.3, 3.0)
	player.model.rotation.y = PI   # olhando para -Z, para o slime
	player.velocity = Vector3.ZERO
	await wait(0.2)
	player.global_position = ch_s.global_position + Vector3(0, 0.3, 3.0)
	player.model.rotation.y = PI
	player.cooldowns.sword_charge = 0.0
	var ch_hp: float = ch_s.hp
	var ch_from := player.global_position
	player.use_slot(1)
	check(player.ability == "sword_charge", "Investida começa (%s)" % player.ability)
	var mask_c: int = player.collision_mask
	await wait(0.75)   # folga sobre SwordAbilities.CHARGE_TIME (0,6 s)
	var ch_d := Vector2(player.global_position.x - ch_from.x, player.global_position.z - ch_from.z).length()
	check(ch_s.hp < ch_hp, "Investida fere o slime no caminho (%.0f -> %.0f)" % [ch_hp, ch_s.hp])
	# o dano é fixo (melee_damage x1,6, sem crítico): a perda de vida igual a um golpe prova acerto único
	check(is_equal_approx(ch_hp - ch_s.hp, Game.melee_damage() * SwordAbilities.CHARGE_MULT),
		"Investida acerta cada inimigo uma vez só (perdeu %.1f, golpe %.1f)" % [ch_hp - ch_s.hp, Game.melee_damage() * SwordAbilities.CHARGE_MULT])
	check(ch_d >= 3.0 and ch_d <= 5.5, "Investida avança entre 3 e 5,5 m (%.2f)" % ch_d)
	check(player.ability == "" and player.cooldowns.sword_charge > 0.0, "Investida termina e entra em recarga (%s, %.2f)" % [player.ability, player.cooldowns.sword_charge])
	check(player.collision_mask == mask_c, "Investida devolve a colisão com inimigos ao terminar")
	# as próximas investidas vão para longe do slime (+Z)
	var away := ch_s.global_position + Vector3(0, 0.3, 3.0)
	# end_ability no meio do avanço: colisão de volta e sem velocidade especial
	player.global_position = away
	player.model.rotation.y = 0.0
	player.cooldowns.sword_charge = 0.0
	player.use_slot(1)
	await wait(0.25)
	var mid_v := Vector2(player.velocity.x, player.velocity.z).length()
	check(player.ability == "sword_charge" and player.collision_mask != mask_c and mid_v > 10.0,
		"Investida no meio do avanço atravessa inimigos (vel %.1f)" % mid_v)
	player.end_ability()
	check(player.ability == "" and player.ability_t == 0.0 and player.collision_mask == mask_c
		and Vector2(player.velocity.x, player.velocity.z).length() < 0.01, "end_ability no avanço limpa estado, colisão e velocidade")
	# esquiva: cancela no preparo, é ignorada no avanço
	Game.stamina = Game.max_stamina()
	player.global_position = away
	player.velocity = Vector3.ZERO
	await wait(0.2)
	player.cooldowns.sword_charge = 0.0
	player.use_slot(1)
	await wait(0.05)
	player._dodge_pressed(Vector3.ZERO)
	check(player.ability == "" and player.dodge_timer > 0.0, "esquiva no preparo cancela a Investida")
	await wait(0.5)
	Game.stamina = Game.max_stamina()
	player.global_position = away
	player.velocity = Vector3.ZERO
	await wait(0.2)
	player.cooldowns.sword_charge = 0.0
	player.use_slot(1)
	await wait(0.3)
	player._dodge_pressed(Vector3.ZERO)
	check(player.ability == "sword_charge" and player.dodge_timer <= 0.0, "esquiva no avanço é ignorada")
	await wait(0.45)
	# abrir menu (build_lock) encerra
	player.global_position = away
	player.cooldowns.sword_charge = 0.0
	player.use_slot(1)
	player.build_lock = true
	await wait(0.05)
	player.build_lock = false
	check(player.ability == "", "menu (build_lock) encerra a habilidade")
	Game.fury = 0.0
	Game.stamina = Game.max_stamina()
	player.cooldowns.sword_charge = 0.0
	player.global_position = pos_c
	player.velocity = Vector3.ZERO
	await wait(0.1)

	# --- Golpe Sísmico (espada, slot 2, nível 3): cone à frente fere e atordoa, quem está atrás não
	var lvl_q := Game.level
	Game.level = 3
	var qk_a := _nearest("slime")
	var qk_b: Enemy = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != qk_a and e.kind == "slime" and not e.dead:
			qk_b = e
			break
	var qk_base := pos_c + Vector3(0, 0.3, 0)   # chão firme da vila
	qk_a.hp = qk_a.max_hp   # o mais próximo pode ser o ferido pela Investida
	qk_b.hp = qk_b.max_hp
	player.global_position = qk_base
	player.model.rotation.y = PI   # olhando para -Z
	player.velocity = Vector3.ZERO
	qk_a.global_position = qk_base + Vector3(0, 0, -3.0)
	qk_b.global_position = qk_base + Vector3(0, 0, 3.0)
	await wait(0.2)
	player.global_position = qk_base
	player.model.rotation.y = PI
	qk_a.global_position = qk_base + Vector3(0, 0, -3.0)
	qk_b.global_position = qk_base + Vector3(0, 0, 3.0)
	player.cooldowns.sword_quake = 0.0
	var qk_ahp: float = qk_a.hp
	var qk_bhp: float = qk_b.hp
	qk_a._set_state("attack")   # no meio de um golpe: o atordoamento o interrompe
	var qk_pos: Vector3 = qk_a.global_position
	player.use_slot(2)
	check(player.ability == "sword_quake", "Golpe Sísmico começa (%s)" % player.ability)
	await wait(0.8)   # 0,35 s de preparo + 0,3 s de recuperação, com folga
	check(qk_a.hp < qk_ahp, "Golpe Sísmico fere o slime da frente (%.0f -> %.0f)" % [qk_ahp, qk_a.hp])
	check(is_equal_approx(qk_ahp - qk_a.hp, Game.melee_damage() * SwordAbilities.QUAKE_MULT),
		"Golpe Sísmico causa melee_damage x2 (perdeu %.1f)" % (qk_ahp - qk_a.hp))
	check(qk_b.hp == qk_bhp, "Golpe Sísmico não fere quem está atrás")
	check(player.ability == "" and player.cooldowns.sword_quake > 0.0, "Golpe Sísmico termina e entra em recarga (%s, %.2f)" % [player.ability, player.cooldowns.sword_quake])
	# 0,8 s depois do início (0,45 s após o impacto) ainda restam ~0,55 s dos 1,0 s de atordoamento
	check(qk_a.stagger > 0.3 and qk_a.state != "attack", "Golpe Sísmico atordoa e interrompe o golpe (stagger %.2f, %s)" % [qk_a.stagger, qk_a.state])
	check(qk_pos.distance_to(qk_a.global_position) < 2.5, "inimigo atordoado não avançou (%.2f m)" % qk_pos.distance_to(qk_a.global_position))
	# a esquiva não cancela
	Game.stamina = Game.max_stamina()
	qk_a.hp = qk_a.max_hp   # sobrevive ao segundo golpe
	player.cooldowns.sword_quake = 0.0
	player.use_slot(2)
	await wait(0.1)
	player._dodge_pressed(Vector3.ZERO)
	check(player.ability == "sword_quake" and player.dodge_timer <= 0.0, "esquiva não cancela o Golpe Sísmico")
	await wait(0.7)
	# colado no jogador, o atordoado não volta a atacar durante o atordoamento
	player.global_position = qk_base
	player.model.rotation.y = PI
	qk_a.global_position = qk_base + Vector3(0, 0, -1.2)
	qk_a.attack_cd = 0.0
	qk_a.hp = qk_a.max_hp
	player.cooldowns.sword_quake = 0.0
	player.use_slot(2)
	await wait(0.45)   # impacto aos 0,35 s
	var qk_attacked := false
	for i in 8:
		await wait(0.08)
		if qk_a.state == "attack":
			qk_attacked = true
	check(qk_a.stagger > 0.0 and not qk_attacked, "atordoado ao alcance não ataca durante o atordoamento (stagger %.2f)" % qk_a.stagger)
	await wait(0.3)
	Game.level = lvl_q
	Game.fury = 0.0
	player.cooldowns.sword_quake = 0.0
	player.global_position = pos_c
	player.velocity = Vector3.ZERO
	await wait(0.1)

	# --- Turbilhão (ultimate da espada, slot 4, nível 8, fúria cheia): gira ferindo e puxando em volta
	var lvl_w := Game.level
	var hp_w := Game.hp
	var spring_w: float = player.spring.spring_length
	Game.level = 8
	Game.fury = 100.0
	var s1 := _nearest("slime")
	s1.hp = s1.max_hp
	player.global_position = s1.global_position + Vector3(2.5, 0.3, 0)
	player.velocity = Vector3.ZERO
	var h1: float = s1.hp
	player.invuln = 3.0   # apanhar de um inimigo próximo também enche a fúria: só os acertos do giro contam aqui
	player.use_slot(4)
	check(Game.fury == 0.0 and player.ability == "sword_whirl", "Turbilhão começa e gasta a fúria")
	check(player.ability_slot == 4, "ability_slot = tecla que começou a habilidade (%d)" % player.ability_slot)
	player.use_slot(1)   # com habilidade em execução o cast é ignorado: a soltura continua da tecla 4
	check(player.ability == "sword_whirl" and player.ability_slot == 4, "tecla de outro slot não sobrescreve ability_slot (%d)" % player.ability_slot)
	await wait_until(func(): return s1.hp < h1, 3.0)
	check(Game.fury == 0.0, "Turbilhão que acertou não recarrega a própria fúria (%.2f)" % Game.fury)
	check(s1.hp < h1, "Turbilhão causa dano durante o giro (%.0f -> %.0f)" % [h1, s1.hp])
	# imune a empurrão: o golpe tira vida mas não empurra nem levanta
	player.invuln = 0.0
	player.take_damage(1.0, player.global_position + Vector3(0, 0, 3.0))
	check(player.velocity.y < 1.0 and Vector2(player.velocity.x, player.velocity.z).length() < 3.0,
		"Turbilhão: imune a empurrão (vel %s)" % player.velocity)
	check(player.spring.spring_length > spring_w + 0.2, "Turbilhão: câmera recua (%.2f -> %.2f)" % [spring_w, player.spring.spring_length])
	Game.stamina = Game.max_stamina()
	player._dodge_pressed(Vector3.ZERO)
	check(player.ability == "sword_whirl" and player.dodge_timer <= 0.0, "esquiva não cancela o Turbilhão")
	player._die()
	await wait(0.1)
	check(player.ability == "" and is_equal_approx(Engine.time_scale, 1.0), "morrer no meio limpa o estado")
	player.revive(player.global_position)
	# a tela de morte abre 1,8 s depois de morrer, mesmo revivido: fecha sem a multa de ouro
	await wait(2.0)
	if world.modal != null:
		world.modal.queue_free()
		world.modal = null
	world._set_paused(false)
	check(not player.dead and not get_tree().paused, "reviveu depois de morrer no Turbilhão")
	check(absf(player.spring.spring_length - spring_w) < 0.05, "câmera volta ao normal (%.2f)" % player.spring.spring_length)
	# puxão: o golpe com pull leva o inimigo em direção a quem bateu (em vez de empurrar)
	var pl_s := _nearest("slime")
	pl_s.hp = pl_s.max_hp
	pl_s.global_position = player.global_position + Vector3(3.0, 0.0, 0.0)
	pl_s.velocity = Vector3.ZERO
	pl_s.take_damage(0.5, player.global_position, false, 0.0, 0.0, SwordAbilities.WHIRL_PULL)
	var to_pl := player.global_position - pl_s.global_position
	check(Vector2(pl_s.velocity.x, pl_s.velocity.z).dot(Vector2(to_pl.x, to_pl.z)) > 0.0,
		"golpe com puxão leva o inimigo para o jogador (vel %s)" % pl_s.velocity)
	# giro inteiro: termina sozinho, tempo normal e o modelo volta a olhar para onde olhava
	Game.fury = 100.0
	player.invuln = 0.0
	player.model.rotation.y = 0.5
	# o puxão se vê: um inimigo a 3 m termina bem mais perto depois do giro (com vida de sobra para não morrer)
	var pl_max: float = pl_s.max_hp
	pl_s.hp = 100000.0
	pl_s.max_hp = 100000.0
	pl_s.global_position = player.global_position + Vector3(3.0, 0.0, 0.0)
	pl_s.velocity = Vector3.ZERO
	var d_pull0: float = pl_s.global_position.distance_to(player.global_position)
	var lvl_w2: int = Game.level
	Game.level = 8   # morrer e reviver passa pelo Econ, cuja resposta devolve Game.level ao nível real
	player.use_slot(4)
	check(player.ability == "sword_whirl", "Turbilhão de novo com a fúria cheia (nível antes %d, %s, esquiva %.2f, atacando %s)"
		% [lvl_w2, player.ability, player.dodge_timer, player.attacking])
	await wait_until(func(): return player.ability == "", SwordAbilities.WHIRL_TIME + 1.5)
	var d_pull1: float = pl_s.global_position.distance_to(player.global_position)
	# o puxão por volta depende de quantos quadros de física cabem no giro: na máquina local leva ~1,7 m,
	# no CI lento chegou a 0,98 m. 0,6 m ainda separa com folga o puxão de um inimigo parado.
	check(d_pull0 - d_pull1 >= 0.6, "Turbilhão puxa o inimigo para perto (%.2f m -> %.2f m)" % [d_pull0, d_pull1])
	pl_s.max_hp = pl_max
	pl_s.hp = pl_max
	check(player.ability == "" and is_equal_approx(Engine.time_scale, 1.0), "Turbilhão termina sozinho (%s)" % player.ability)
	check(absf(wrapf(player.model.rotation.y - 0.5, -PI, PI)) < 0.05, "giro volta à direção inicial (%.2f)" % player.model.rotation.y)
	Game.level = lvl_w
	Game.fury = 0.0
	Game.hp = hp_w
	player.cooldowns.sword_whirl = 0.0
	player.global_position = pos_c
	player.velocity = Vector3.ZERO
	await wait(0.1)

	# --- servidor dedicado: nenhum nó de efeito nasce (FX._scene() devolve null)
	var mode_s: int = Network.mode
	Network.mode = Network.Mode.SERVER
	var kids_s := world.get_child_count()
	check(FX._scene() == null, "servidor dedicado não cria efeitos (FX._scene nulo)")
	FX.ring(player.global_position, Color.WHITE, 3.0, 0.3)
	FXEpic.nova(player.global_position, Color.ORANGE, 20, 5.0, 0.2, 0.4)
	check(world.get_child_count() == kids_s and FXEpic.stream(player, "flame", Color.ORANGE, 10, 0.5) == null,
		"servidor: chamadas de efeito não adicionam nós")
	Network.mode = mode_s

	# --- kits de habilidade por arma (começa de espada: weapon_class() == "sword")
	var kit_weapon: String = Game.equipment.weapon
	check(Game.ability_kit() == ["sword_charge", "sword_quake", "sword_whirl"], "kit da espada (%s)" % [Game.ability_kit()])
	check(not Game.knows_ability("sword_quake") and Game.knows_ability("sword_charge"), "liberação por nível")
	check(Game.level == 1 and not Game.knows_ability("heal") and ItemDB.ABILITIES.heal.level == 5, "cura só no nível 5")
	# todas as habilidades estão prontas (a Chuva de Meteoros foi a última): o caminho "Em breve" não tem mais
	# quem testar; resta conferir que há recarga para cada habilidade
	Game.add_item("short_bow")
	Game.equip("short_bow")
	var lvl_bf: int = Game.level
	check(Game.weapon_class() == "bow" and player.cooldowns.size() == ItemDB.ABILITIES.size(), "uma recarga por habilidade")
	# --- Tiro Triplo (arco, slot 1): 3 flechas em leque, ignora multishot, esquiva só cancela antes do disparo
	var tt_pos := player.global_position
	var tt_s := _nearest("slime")
	var tt_max: float = tt_s.max_hp
	tt_s.max_hp = 100000.0   # aguenta as 9 flechas sem morrer (o nó some ao morrer)
	tt_s.global_position = tt_s.home
	var tt_fire := func() -> Array:
		var out := []
		for c in world.get_children():
			if c.get("kind") == "arrow" and not c.visual_only:
				out.append(c)
		return out
	Game.add_item("storm_bow")
	Game.add_item("goblin_warbow")
	var tt_weapons := ["short_bow", "storm_bow", "goblin_warbow"]
	var tt_grounded := func() -> bool: return player.is_on_floor()
	for tt_w in tt_weapons:
		Game.equip(tt_w)
		await wait_until(func(): return player.dodge_timer <= 0.0 and not player.attacking)
		for c in tt_fire.call():
			c.queue_free()
		tt_s.global_position = tt_s.home
		player.global_position = tt_s.global_position + Vector3(0, 0.3, 6.0)
		player.model.rotation.y = PI
		player.velocity = Vector3.ZERO
		await wait_until(tt_grounded)
		player.global_position = tt_s.global_position + Vector3(0, 0.3, 6.0)
		player.cooldowns.bow_triple = 0.0
		tt_s.hp = tt_s.max_hp
		var tt_hp: float = tt_s.hp
		player.use_slot(1)
		check(player.ability == "bow_triple" and BowAbilities.can_dodge_cancel(player), "Tiro Triplo começa (%s, %s)" % [player.ability, tt_w])
		await wait_until(func(): return tt_fire.call().size() > 0 or player.ability == "")
		var tt_arrows: Array = tt_fire.call()
		var tt_n: int = tt_arrows.size()
		var tt_ab: bool = player.ability == "bow_triple"
		check(tt_n == 3 and tt_ab and not BowAbilities.can_dodge_cancel(player),
			"Tiro Triplo dispara 3 flechas de uma vez (%s: %d)" % [tt_w, tt_n])
		if tt_n == 3:
			# dano de cada flecha (x0,8, x1,8 se crítica), velocidade 42 e perfuração só com fx "pierce"
			var tt_dmg_ok := true
			var tt_pierce_ok := true
			var tt_flat := []
			for ar in tt_arrows:
				var want: float = Game.melee_damage() * BowAbilities.TRIPLE_MULT * (1.8 if ar.crit else 1.0)
				tt_dmg_ok = tt_dmg_ok and absf(ar.damage - want) < 0.01 and is_equal_approx(ar.speed, BowAbilities.TRIPLE_SPEED)
				tt_pierce_ok = tt_pierce_ok and ar.pierce == (2 if tt_w == "goblin_warbow" else 0)
				var f: Vector3 = ar.direction
				f.y = 0.0
				tt_flat.append(f.normalized())
			tt_flat.sort_custom(func(x, y): return x.signed_angle_to(y, Vector3.UP) < 0.0)   # esquerda, centro, direita
			var ang_a := rad_to_deg(absf(tt_flat[0].signed_angle_to(tt_flat[1], Vector3.UP)))
			var ang_b := rad_to_deg(absf(tt_flat[1].signed_angle_to(tt_flat[2], Vector3.UP)))
			var ang_c := rad_to_deg(tt_flat[0].angle_to(tt_flat[2]))
			check(tt_dmg_ok, "Tiro Triplo: dano x0,8 e velocidade 42 em cada flecha (%s)" % tt_w)
			check(tt_pierce_ok, "Tiro Triplo: perfuração %s (%s)" % ["+2 com fx pierce" if tt_w == "goblin_warbow" else "0", tt_w])
			check(absf(ang_a - 12.0) < 0.5 and absf(ang_b - 12.0) < 0.5 and absf(ang_c - 24.0) < 0.5,
				"Tiro Triplo: leque de 12 graus (%.1f, %.1f, total %.1f)" % [ang_a, ang_b, ang_c])
		await wait_until(func(): return player.ability == "")
		check(player.cooldowns.bow_triple > 0.0 and tt_s.hp < tt_hp, "Tiro Triplo fere o slime e entra em recarga (%.0f -> %.0f)" % [tt_hp, tt_s.hp])
	# esquiva antes do disparo cancela sem gastar flechas (logo no início, ability_t = 0); depois é ignorada
	Game.equip("short_bow")
	await wait_until(func(): return player.dodge_timer <= 0.0 and not player.attacking)
	Game.stamina = Game.max_stamina()
	player.global_position = tt_pos
	for c in tt_fire.call():
		c.queue_free()
	player.cooldowns.bow_triple = 0.0
	player.use_slot(1)
	check(player.ability == "bow_triple" and player.ability_t < BowAbilities.TRIPLE_DRAW, "Tiro Triplo antes do disparo (t %.2f)" % player.ability_t)
	player._dodge_pressed(Vector3.ZERO)
	check(player.ability == "" and tt_fire.call().size() == 0 and player.dodge_timer > 0.0, "esquiva antes do disparo cancela o Tiro Triplo")
	await wait_until(func(): return player.dodge_timer <= 0.0)
	Game.stamina = Game.max_stamina()
	player.cooldowns.bow_triple = 0.0
	player.use_slot(1)
	await wait_until(func(): return player.ability_t >= BowAbilities.TRIPLE_DRAW or player.ability == "")
	player._dodge_pressed(Vector3.ZERO)
	check(player.ability == "bow_triple" and player.dodge_timer <= 0.0, "esquiva depois do disparo é ignorada")
	await wait_until(func(): return player.ability == "")
	for c in tt_fire.call():
		c.queue_free()
	# réplica: o evento "bow_triple" cria 3 flechas só visuais, sem dano, e a pose acaba em 0,25 s
	var tt_rp := Player.new()
	tt_rp.remote = true
	world.add_child(tt_rp)
	tt_s.hp = tt_s.max_hp
	var tt_rhp: float = tt_s.hp
	var tt_o := tt_s.global_position + Vector3(0, 1.2, 6.0)
	var tt_vis_before := 0
	for c in world.get_children():
		if c.get("kind") == "arrow" and c.visual_only:
			tt_vis_before += 1
	BowAbilities.play_remote(tt_rp, "bow_triple", tt_o, Vector3(0, 0, -1))
	var tt_vis := []
	for c in world.get_children():
		if c.get("kind") == "arrow" and c.visual_only:
			tt_vis.append(c)
	check(tt_vis.size() - tt_vis_before == 3 and tt_fire.call().size() == 0, "réplica do Tiro Triplo cria 3 flechas visual_only (%d)" % [tt_vis.size() - tt_vis_before])
	check(tt_rp.ability == "bow_triple" and is_equal_approx(tt_rp.ability_t, BowAbilities.TRIPLE_DRAW), "réplica começa no disparo")
	var tt_t0 := Time.get_ticks_msec()
	await wait_until(func(): return tt_rp.ability == "")
	var tt_el := (Time.get_ticks_msec() - tt_t0) / 1000.0
	check(tt_rp.ability == "" and tt_el >= BowAbilities.TRIPLE_RECOVER - 0.1, "réplica termina após a recuperação de 0,25 s (%.2f s)" % tt_el)
	await wait(0.6)   # as flechas visuais atravessam o slime: sem dano
	check(tt_s.hp == tt_rhp, "flechas da réplica não ferem (%.0f)" % tt_s.hp)
	tt_rp.queue_free()
	for c in world.get_children():
		if c.get("kind") == "arrow":
			c.queue_free()
	Game.stamina = Game.max_stamina()
	player.cooldowns.bow_triple = 0.0
	# --- Flecha Glacial (arco, slot 2): tensão 0,35 s, 1 flecha (dano x1,4, vel 40), prende 1,5 s + lentidão 3 s; chefe só a lentidão
	Game.level = 3
	Game.equip("short_bow")
	await wait_until(func(): return player.dodge_timer <= 0.0 and not player.attacking)
	var fg_boss0: bool = tt_s.is_boss
	tt_s.global_position = tt_s.home
	player.global_position = tt_s.global_position + Vector3(0, 0.3, 6.0)
	player.model.rotation.y = PI
	player.velocity = Vector3.ZERO
	await wait_until(tt_grounded)
	player.global_position = tt_s.global_position + Vector3(0, 0.3, 6.0)
	for c in tt_fire.call():
		c.queue_free()
	tt_s.stagger = 0.0
	tt_s.slow_timer = 0.0
	tt_s.hp = tt_s.max_hp
	var fg_hp: float = tt_s.hp
	player.cooldowns.bow_frost = 0.0
	Game.level = 3
	player.use_slot(2)
	check(player.ability == "bow_frost" and BowAbilities.can_dodge_cancel(player), "Flecha Glacial começa (%s)" % player.ability)
	await wait_until(func(): return tt_fire.call().size() > 0 or player.ability == "")
	var fg_arrows: Array = tt_fire.call()
	check(fg_arrows.size() == 1 and player.ability == "bow_frost" and player.ability_t >= BowAbilities.FROST_DRAW - 0.0001
		and not BowAbilities.can_dodge_cancel(player), "Flecha Glacial dispara 1 flecha só depois da tensão (%d, t %.2f)" % [fg_arrows.size(), player.ability_t])
	if fg_arrows.size() == 1:
		var fa = fg_arrows[0]
		var fwant: float = Game.melee_damage() * BowAbilities.FROST_MULT * (1.8 if fa.crit else 1.0)
		check(absf(fa.damage - fwant) < 0.01 and is_equal_approx(fa.speed, 40.0) and fa.pierce == 0 and fa.fx == "glacial",
			"Flecha Glacial: dano x1,4, velocidade 40, sem perfuração (%.1f vs %.1f, vel %.0f, fx %s)" % [fa.damage, fwant, fa.speed, fa.fx])
	await wait_until(func(): return tt_s.hp < fg_hp)
	check(tt_s.stagger > 0.8 and tt_s.slow_timer > 1.5, "Flecha Glacial prende e atrasa (stagger %.2f, slow %.2f)" % [tt_s.stagger, tt_s.slow_timer])
	await wait_until(func(): return player.ability == "")
	check(player.cooldowns.bow_frost > 0.0, "Flecha Glacial entra em recarga")
	# chefe: só a lentidão (sem prender)
	tt_s.is_boss = true
	tt_s.stagger = 0.0
	tt_s.slow_timer = 0.0
	tt_s.global_position = tt_s.home
	player.global_position = tt_s.global_position + Vector3(0, 0.3, 6.0)
	player.velocity = Vector3.ZERO
	await wait_until(tt_grounded)
	player.global_position = tt_s.global_position + Vector3(0, 0.3, 6.0)
	player.cooldowns.bow_frost = 0.0
	fg_hp = tt_s.hp
	Game.level = 3
	player.use_slot(2)
	await wait_until(func(): return tt_s.hp < fg_hp)
	check(tt_s.stagger < 1.0 and tt_s.slow_timer > 0.0, "Flecha Glacial no chefe: só lentidão (stagger %.2f, slow %.2f)" % [tt_s.stagger, tt_s.slow_timer])
	await wait_until(func(): return player.ability == "")
	tt_s.is_boss = fg_boss0
	# réplica: flecha visual_only, sem dano nem prisão
	var fg_rp := Player.new()
	fg_rp.remote = true
	world.add_child(fg_rp)
	tt_s.stagger = 0.0
	tt_s.slow_timer = 0.0
	tt_s.hp = tt_s.max_hp
	var fg_rhp: float = tt_s.hp
	var fg_vis0 := 0
	for c in world.get_children():
		if c.get("kind") == "arrow" and c.visual_only:
			fg_vis0 += 1
	BowAbilities.play_remote(fg_rp, "bow_frost", tt_s.global_position + Vector3(0, 1.2, 6.0), Vector3(0, 0, -1))
	var fg_vis := []
	for c in world.get_children():
		if c.get("kind") == "arrow" and c.visual_only:
			fg_vis.append(c)
	check(fg_vis.size() - fg_vis0 == 1 and fg_rp.ability == "bow_frost" and tt_fire.call().size() == 0,
		"réplica da Flecha Glacial cria 1 flecha visual_only (%d)" % [fg_vis.size() - fg_vis0])
	await wait_until(func(): return fg_rp.ability == "")
	await wait(0.6)
	check(tt_s.hp == fg_rhp and tt_s.stagger <= 0.0 and tt_s.slow_timer <= 0.0, "flecha glacial da réplica não fere nem prende")
	fg_rp.queue_free()
	for c in world.get_children():
		if c.get("kind") == "arrow":
			c.queue_free()
	tt_s.stagger = 0.0
	tt_s.slow_timer = 0.0
	player.cooldowns.bow_frost = 0.0
	await _test_bow_gale()
	await _test_meteor_rain()
	Game.level = lvl_bf
	tt_s.hp = tt_max
	tt_s.max_hp = tt_max
	tt_s.global_position = tt_s.home
	player.global_position = tt_pos
	player.velocity = Vector3.ZERO
	Game.equip(kit_weapon)
	player.cooldowns.sword_charge = 3.0   # para conferir que a recarga atravessa a troca de arma
	Game.equip("apprentice_staff")
	await wait(0.1)
	check(Game.ability_kit() == ["fireball", "frost_nova", "heal", "meteor_rain"], "trocar de arma troca o kit")
	check(player.cooldowns.sword_charge > 2.5, "recarga continua depois de trocar de arma")
	check(hud_slot_ids() == Game.ability_kit(), "barra de ações mostra o kit novo (%s)" % [hud_slot_ids()])
	var mp_m := Game.mp
	player.cast("meteor_rain")
	check(Game.mp == mp_m and player.cooldowns.meteor_rain == 0.0 and player.ability == "", "ultimate sem fúria não sai nem gasta nada")

	# --- magia do cajado enche a fúria (Nova Gélida causa dano ao slime perto)
	var lvl_n := Game.level
	var mp_n := Game.mp
	Game.level = 5
	Game.mp = Game.max_mp()
	player.cooldowns.frost_nova = 0.0
	player.cast_timer = 0.0
	var pos_n := player.global_position
	var nova_s := _nearest("slime")
	player.global_position = nova_s.global_position + Vector3(0, 0.3, 1.5)
	await wait(0.1)
	Game.fury = 0.0
	player.cast("frost_nova")
	check(Game.fury > 0.0, "magia do cajado enche a fúria (%.2f)" % Game.fury)
	# magias não roubam vida (o roubo é só do corpo a corpo)
	var weapon_n: String = Game.equipment.weapon
	var hp_n := Game.hp
	Game.equipment.weapon = "scarlet_talon"
	Game.hp = 10.0
	player.cooldowns.frost_nova = 0.0
	player.cast_timer = 0.0
	Game.mp = Game.max_mp()
	var nova_saved := {}   # sem abate: o XP subiria o nível do Econ e curaria (apply_state)
	for e in get_tree().get_nodes_in_group("enemies"):
		nova_saved[e] = [e.max_hp, e.hp]
		e.max_hp = 1.0e6
		e.hp = 1.0e6
	player.cast("frost_nova")
	for e in nova_saved:
		if is_instance_valid(e):
			e.max_hp = nova_saved[e][0]
			e.hp = nova_saved[e][1]
	check(Game.gear("leech") > 0.0 and Game.hp <= 10.0, "Nova Gélida não rouba vida mesmo com roubo de vida equipado (%.1f)" % Game.hp)
	Game.equipment.weapon = weapon_n
	Game.hp = hp_n
	Game.fury = 0.0
	Game.level = lvl_n
	Game.mp = mp_n
	player.cooldowns.frost_nova = 0.0
	player.global_position = pos_n
	player.cast_timer = 0.0

	# --- barra de fúria e ultimate (slot 4 do cajado = meteor_rain)
	var lvl_f := Game.level
	var hp_f := Game.hp
	Game.fury = 0.0
	Game.on_damage_dealt(5.0, 100.0)
	check(is_equal_approx(Game.fury, 2.5), "fúria: 5 de dano em alvo de 100 de vida = 2.5 (%.2f)" % Game.fury)
	Game.on_damage_dealt(9999.0, 10.0)
	check(is_equal_approx(Game.fury, 8.5), "fúria: ganho por golpe limitado a 6 (%.2f)" % Game.fury)
	Game.on_damage_dealt(0.01, 1000.0)
	check(is_equal_approx(Game.fury, 9.0), "fúria: ganho mínimo 0.5 (%.2f)" % Game.fury)
	Game.fury = 0.0
	player.invuln = 0.0
	player.take_damage(Game.max_hp() * 0.4, player.global_position + Vector3(0, 0, 5))
	check(is_equal_approx(Game.fury, (Game.max_hp() * 0.4 * 50.0 / (50.0 + Game.defense() * 4.0)) / Game.max_hp() * 25.0), "fúria sobe ao receber dano (%.2f)" % Game.fury)
	Game.hp = hp_f
	player.invuln = 0.0
	Game.add_fury(500.0)
	check(Game.fury == 100.0 and Game.fury_full(), "fúria limitada a 100")
	Game.level = 8
	Game.fury = 50.0
	player.use_slot(4)
	check(Game.fury == 50.0, "ultimate não sai com fúria incompleta")
	Game.level = 2
	Game.fury = 100.0
	player.use_slot(4)
	check(Game.fury == 100.0, "ultimate não sai abaixo do nível 8")
	Game.level = 8
	player.use_slot(4)
	check(Game.fury == 0.0 and player.ability == "meteor_rain", "ultimate sai com fúria cheia no nível 8 e zera a fúria")
	player.end_ability()   # encerrada no preparo (o teste completo é _test_meteor_rain)
	player.cooldowns.meteor_rain = 0.0
	# --- fúria persistida no personagem (CharState)
	var fs := CharState.new()
	fs.fury = 70.0
	check(is_equal_approx(CharState.from_dict(fs.to_dict(), Balance.tables).fury, 70.0), "fúria: to_dict/from_dict preserva 70")
	var fd := fs.to_dict()
	fd.erase("fury")
	check(CharState.from_dict(fd, Balance.tables).fury == 0.0, "fúria: save antigo sem o campo = 0")
	fd["fury"] = 999.0
	check(CharState.from_dict(fd, Balance.tables).fury == CharState.FURY_MAX, "fúria: limitada a FURY_MAX ao carregar")

	# --- despacho por módulo da classe da arma, com fonte única de "pronta"
	for id in ItemDB.ABILITIES:
		check(Game.ability_implemented(id) == ItemDB.ABILITIES[id].ready, "fonte única de 'pronta' (%s)" % id)
	check(player._ab_module("sword_whirl") == SwordAbilities and player._ab_module("bow_gale") == BowAbilities
		and player._ab_module("meteor_rain") == StaffAbilities, "despacho por módulo da classe")
	check(player._ab_module("meteor_rain_end") == StaffAbilities and player._ab_module("bow_gale_fire") == BowAbilities
		and player._ab_module("sword_charge") == SwordAbilities, "kind de evento remoto roteia por prefixo")

	Game.level = lvl_f
	Game.fury = 0.0
	Game.hp = hp_f

	# --- magia
	var mp0 := Game.mp
	var fb_watch := _watch_spawns()
	player.cast("fireball")
	# a bola de fogo sai depois do movimento de apontar
	await wait_until(func(): return "fireball" in fb_watch[0])
	_stop_spawn_watch(fb_watch)
	check(Game.mp < mp0, "bola de fogo gasta mana")
	check("fireball" in fb_watch[0], "projétil de bola de fogo criado")
	player.cast("heal")
	check(player.cooldowns.heal == 0.0, "cura bloqueada no nível 1")
	player.use_slot(2)   # Nova Gélida (nível 3) bloqueada no nível 1
	check(player.cooldowns.frost_nova == 0.0, "slot 2 respeita o nível")
	Game.equip(kit_weapon)   # restaura a arma inicial

	# --- completar missão e subir de nível
	for i in 4:
		var s := _nearest("slime")
		s.take_damage(9999, player.global_position, false)
	check(Game.quest_state("slimes") == "ready", "missão pronta após 5 slimes")
	var xp_before := Game.xp + Game.level * 100000
	Game.complete_quest("slimes")
	check(Game.quest_state("slimes") == "done" and Game.xp + Game.level * 100000 > xp_before, "recompensa de XP entregue")
	check(Game.level >= 2, "subiu para o nível %d" % Game.level)
	check(Game.count_item("health_potion") >= 6, "poções de recompensa recebidas")
	Game.spend_point("str")
	check(Game.attributes.str == 6, "ponto de atributo gasto em força")

	# --- inventário / equipamento / loja
	world._open_menu(0)
	await wait(0.1)
	check(world.modal != null, "menu de inventário abre")
	world.modal._close()
	await wait(0.05)
	world.open_shop()
	await wait(0.05)
	var g := Game.gold
	Game.buy("iron_sword")
	check(Game.count_item("iron_sword") == 1 and Game.gold == g - 60, "comprou espada de ferro")
	Game.use_item("iron_sword")
	check(Game.equipment.weapon == "iron_sword" and Game.count_item("azure_edge") == 1, "equipou espada de ferro")
	Game.sell("azure_edge")
	check(Game.count_item("azure_edge") == 0, "vendeu o gume celeste")
	world.modal._close()
	await wait(0.05)

	# --- novas armas, armaduras e equipamentos
	await _test_gear()

	# --- persistência no save solo: cada pedido já foi gravado; recriar o serviço local devolve o mesmo personagem
	var saved_gold := Game.gold
	var saved_lvl := Game.level
	var saved_inv: Array = Game.inventory.duplicate(true)
	var saved_pos := player.global_position
	check(Econ.quick_save(saved_pos, 0.0), "F5 offline grava vida e posição")
	Game.gold = 1   # bagunça o espelho: o estado tem que voltar do banco
	Game.level = 1
	Game.inventory = []
	check(Econ.reload_solo(), "serviço local recriado a partir do save solo")
	check(Game.gold == saved_gold and Game.level == saved_lvl, "save solo guarda ouro e nível")
	check(Game.inventory == saved_inv, "save solo guarda a mochila (%d espaços)" % Game.inventory.size())
	check(Game.equipment.weapon == "iron_sword", "save solo guarda o equipamento")
	check(Game.equipment.head == "leather_cap" and Game.equipment.feet == "leather_boots", "save solo guarda cabeça e pés")
	Econ.quick_load()   # F9: recarrega do save solo e volta ao mundo
	await wait(0.6)
	world = get_tree().current_scene
	player = get_tree().get_first_node_in_group("player")
	check(player != null and Game.gold == saved_gold and player.global_position.distance_to(saved_pos) < 1.5,
		"F9 recarrega do save solo na posição salva")

	# --- missões goblin e chefe
	Game.start_quest("goblins")
	for i in 4:
		_nearest("goblin").take_damage(9999, player.global_position, false)
	Game.complete_quest("goblins")
	check(Game.count_item("chain_mail") == 1, "cota de malha recebida")
	Game.start_quest("goblin_king")
	await wait(0.1)
	var boss: Enemy = world.boss
	check(boss != null and is_instance_valid(boss), "chefe aparece ao aceitar a missão final")
	var goblins_before := _count("goblin")
	boss.take_damage(boss.max_hp * 0.6, boss.global_position + Vector3.FORWARD, false)
	await wait(0.2)
	check(boss.enraged and _count("goblin") == goblins_before + 2, "chefe enfurece e invoca 2 goblins")
	boss.take_damage(99999, boss.global_position + Vector3.FORWARD, false)
	check(Game.quest_state("goblin_king") == "ready" and Game.flags.get("king_dead", false), "chefe derrotado")

	# --- IA ataca o jogador
	var gob := _nearest("goblin")
	player.global_position = gob.global_position + Vector3(0, 0.3, 1.0)
	var php := Game.hp
	await wait(3.0)
	check(Game.hp < php, "goblin causa dano ao jogador (%.0f -> %.0f)" % [php, Game.hp])

	# --- morte e renascimento
	player.invuln = 0
	player.take_damage(99999, player.global_position + Vector3.FORWARD)
	check(player.dead, "jogador morre")
	await wait(2.2)
	check(world.modal != null and get_tree().paused, "tela de morte aparece")
	var gold_dead := Game.gold
	world.modal._respawn()
	await wait(0.2)
	check(not player.dead and not get_tree().paused and Game.hp == Game.max_hp(), "renasce na vila")
	check(Game.gold == gold_dead - int(gold_dead * 0.1), "renascer custa 10%% do ouro (%d -> %d)" % [gold_dead, Game.gold])

	await _test_fx_epic()
	await _test_farm()
	await _test_survival()
	await _test_update()

	print("\n==== %s (%d falhas) ====" % ["OK" if fails == 0 else "FALHOU", fails])
	get_tree().quit(1 if fails > 0 else 0)


# ---------------------------------------------------------------- Efeitos épicos
## Flecha do Vendaval (ultimate do arco, slot 4): segurar 4 tensiona (carga 0..1 em 1,2 s), soltar dispara
## um raio de 40 m na mira que atravessa todos os inimigos da linha (cada um uma vez) e para em parede.
func _test_bow_gale() -> void:
	var lvl0: int = Game.level
	var fury0: float = Game.fury
	var weapon0: String = Game.equipment.weapon
	var pos0 := player.global_position
	var yaw0: float = player.cam_yaw.rotation.y
	var spring0: float = player.spring.spring_length
	var fov0: float = player.camera.fov
	Game.equip("short_bow")
	await wait_until(func(): return player.dodge_timer <= 0.0 and not player.attacking and player.ability == "")
	# 4 slimes (os mais perto): 3 na linha da mira a 5/10/15 m e 1 a 6 m do lado da linha
	var gs: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.kind == "slime" and not e.dead and not e.is_boss:
			gs.append(e)
	gs.sort_custom(func(a, b): return a.global_position.distance_to(player.global_position) < b.global_position.distance_to(player.global_position))
	gs = gs.slice(0, 4)
	check(gs.size() == 4, "Vendaval: 4 slimes para o teste (%d)" % gs.size())
	if gs.size() < 4:
		return
	var saved: Array = []
	for e in gs:
		saved.append([e, e.max_hp, e.global_position])
		e.max_hp = 100000.0
	# lugar aberto: casa do slime mais perto; gira a câmera até a mira ter 18 m livres
	var base: Vector3 = gs[0].home
	var grounded := func() -> bool: return player.is_on_floor()
	player.global_position = base + Vector3(0, 0.3, 0)
	player.velocity = Vector3.ZERO
	await wait_until(grounded)
	var dir := Vector3.ZERO
	for k in 12:
		player.cam_yaw.rotation.y = yaw0 + k * TAU / 12.0
		await wait(0.05)
		var d: Vector3 = BowAbilities._gale_dir(player)
		var o: Vector3 = player.global_position + Vector3.UP * BowAbilities.GALE_HEIGHT
		if BowAbilities._gale_length(player, o, d) >= 18.0:
			dir = d
			break
	check(dir != Vector3.ZERO and absf(dir.y) < 0.001, "Vendaval: mira horizontal com 18 m livres (%s)" % dir)
	var side := dir.cross(Vector3.UP).normalized()
	var place := func() -> void:
		var p0: Vector3 = player.global_position
		for i in 3:
			gs[i].global_position = p0 + dir * (5.0 * (i + 1)) + Vector3.UP * 0.3
		gs[3].global_position = p0 + dir * 10.0 + side * 6.0 + Vector3.UP * 0.3
		for e in gs:
			e.velocity = Vector3.ZERO
			e.stagger = 5.0   # parados até o tiro
			e.hp = e.max_hp
	var hps := func() -> Array:
		var out := []
		for e in gs:
			out.append(e.hp)
		return out
	var lines := func() -> int:
		var n := 0
		for c in world.get_children():
			if c is BowAbilities.GaleLine:
				n += 1
		return n
	place.call()
	await wait(0.3)
	place.call()
	var h0: Array = hps.call()

	# --- 1) segura, solta aos 0,6 s: os 3 da linha perdem vida, o de fora não; a fúria fica em 0
	Game.fury = 100.0
	Game.level = 8
	player.use_slot(4)
	check(player.ability == "bow_gale" and Game.fury == 0.0 and player.ability_slot == 4,
		"Vendaval começa, gasta a fúria e grava a tecla 4 (%s, %.0f, %d)" % [player.ability, Game.fury, player.ability_slot])
	check(not BowAbilities.can_dodge_cancel(player), "Vendaval: esquiva não cancela a tensão")
	await wait(0.3)
	var c03: float = player.ability_data.get("charge", -1.0)
	check(c03 > 0.15 and c03 < 0.4 and not player.ability_data.get("fired", false), "Vendaval: carga cresce com o tempo (%.2f aos 0,3 s)" % c03)
	check(Vector2(player.velocity.x, player.velocity.z).length() < 0.1, "Vendaval: parado na tensão (vel %s)" % player.velocity)
	check(player.camera.fov < fov0 - 0.5 and player.cam_back > 0.0, "Vendaval: câmera recua e fecha o FOV (%.1f, back %.2f)" % [player.camera.fov, player.cam_back])
	Game.stamina = Game.max_stamina()
	player._dodge_pressed(Vector3.ZERO)
	check(player.ability == "bow_gale" and player.dodge_timer <= 0.0, "Vendaval: esquiva ignorada na tensão")
	await wait_until(func(): return player.ability_t >= 0.6 or player.ability == "")
	BowAbilities.release(player)
	var fired1: bool = player.ability_data.get("fired", false)
	var ch1: float = player.ability_data.get("charge", -1.0)
	check(fired1 and absf(ch1 - 0.5) < 0.06, "Vendaval: soltar com carga >= 0,25 dispara na hora (carga %.2f)" % ch1)
	check(lines.call() >= 1, "Vendaval: o disparo cria a linha visual")
	await wait_until(func(): return player.ability == "", 2.0)
	var h1: Array = hps.call()
	var want1: float = Game.melee_damage() * lerpf(BowAbilities.GALE_MULT_MIN, BowAbilities.GALE_MULT_MAX, ch1)
	var line_ok := true
	for i in 3:
		line_ok = line_ok and absf((h0[i] - h1[i]) - want1) < 0.05
	check(line_ok, "Vendaval: os 3 slimes da linha (5/10/15 m) perdem melee x lerp(3,6,carga) uma vez (%.1f, %.1f, %.1f; esperado %.1f)"
		% [h0[0] - h1[0], h0[1] - h1[1], h0[2] - h1[2], want1])
	check(h1[3] == h0[3], "Vendaval: o slime fora da linha não perde vida")
	check(Game.fury == 0.0, "Vendaval: acertos da ultimate não recarregam a fúria (%.2f)" % Game.fury)
	check(is_equal_approx(Engine.time_scale, 1.0) and player.cam_back == 0.0 and absf(player.camera.fov - fov0) < 0.01,
		"Vendaval: fim restaura tempo, câmera e FOV (%.2f, %.2f, %.1f)" % [Engine.time_scale, player.cam_back, player.camera.fov])

	# --- 2) sem soltar: dispara sozinha com carga cheia em <= 1,4 s
	player.global_position = base + Vector3(0, 0.3, 0)
	player.velocity = Vector3.ZERO
	await wait_until(grounded)
	place.call()
	await wait(0.1)
	h0 = hps.call()
	Game.fury = 100.0
	Game.level = 8
	var t2 := Time.get_ticks_msec()
	player.use_slot(4)
	await wait_until(func(): return player.ability_data.get("fired", false) or player.ability == "", 2.0)
	var el2 := (Time.get_ticks_msec() - t2) / 1000.0
	var ch2: float = player.ability_data.get("charge", -1.0)
	check(player.ability_data.get("fired", false) and el2 <= 1.4 and is_equal_approx(ch2, 1.0),
		"Vendaval: sem soltar dispara sozinha com carga cheia (%.2f s, carga %.2f)" % [el2, ch2])
	await wait_until(func(): return player.ability == "", 2.0)
	var h2: Array = hps.call()
	var want2: float = Game.melee_damage() * BowAbilities.GALE_MULT_MAX
	check(absf((h0[0] - h2[0]) - want2) < 0.05 and h2[2] < h0[2] and h2[3] == h0[3],
		"Vendaval: carga cheia = melee x6 (%.1f, esperado %.1f)" % [h0[0] - h2[0], want2])

	# --- 3) soltar cedo (carga < 0,25): continua tensionando até 0,25 e dispara
	player.global_position = base + Vector3(0, 0.3, 0)
	player.velocity = Vector3.ZERO
	await wait_until(grounded)
	place.call()
	await wait(0.1)
	Game.fury = 100.0
	Game.level = 8
	player.use_slot(4)
	await wait(0.05)
	BowAbilities.release(player)
	check(player.ability == "bow_gale" and not player.ability_data.get("fired", false), "Vendaval: soltar com carga < 0,25 não dispara na hora")
	await wait_until(func(): return player.ability_data.get("fired", false) or player.ability == "", 1.0)
	var ch3: float = player.ability_data.get("charge", -1.0)
	check(player.ability_data.get("fired", false) and absf(ch3 - BowAbilities.GALE_MIN) < 0.03,
		"Vendaval: dispara ao chegar a 0,25 (carga %.2f)" % ch3)
	await wait_until(func(): return player.ability == "", 2.0)

	# --- 4) morrer na tensão: não dispara, limpa o estado
	player.global_position = base + Vector3(0, 0.3, 0)
	player.velocity = Vector3.ZERO
	await wait_until(grounded)
	place.call()
	await wait(0.1)
	h0 = hps.call()
	var lines0: int = lines.call()
	Game.fury = 100.0
	Game.level = 8
	player.use_slot(4)
	await wait(0.4)
	check(player.ability == "bow_gale" and player.cam_back > 0.0, "Vendaval: tensionando antes de morrer")
	player._die()
	await wait(0.1)
	check(player.ability == "" and is_equal_approx(Engine.time_scale, 1.0) and player.cam_back == 0.0 and absf(player.camera.fov - fov0) < 0.01,
		"Vendaval: morrer na tensão limpa o estado (%s, %.2f, %.2f, %.1f)" % [player.ability, Engine.time_scale, player.cam_back, player.camera.fov])
	player.revive(player.global_position)
	await wait(1.5)
	check(hps.call() == h0 and lines.call() <= lines0, "Vendaval: morrer na tensão não dispara (nenhum slime ferido)")
	# a tela de morte abre 1,8 s depois de morrer, mesmo revivido: fecha sem a multa de ouro
	await wait(0.5)
	if world.modal != null:
		world.modal.queue_free()
		world.modal = null
	world._set_paused(false)
	check(not player.dead and absf(player.spring.spring_length - spring0) < 0.05, "Vendaval: câmera volta depois de morrer (%.2f)" % player.spring.spring_length)

	# --- 5) trocar de arma na tensão: encerra sem disparar
	place.call()
	await wait(0.1)
	h0 = hps.call()
	Game.fury = 100.0
	Game.level = 8
	player.use_slot(4)
	await wait(0.3)
	check(player.ability == "bow_gale", "Vendaval: tensionando antes de trocar de arma")
	Game.equip("apprentice_staff")   # outra classe: Game.kit_changed -> end_ability
	await wait(0.1)
	check(player.ability == "" and player.cam_back == 0.0 and absf(player.camera.fov - fov0) < 0.01, "Vendaval: trocar de arma na tensão encerra")
	await wait(1.3)
	check(hps.call() == h0, "Vendaval: trocar de arma na tensão não dispara")
	Game.equip("short_bow")
	await wait(0.1)

	# --- 6) réplica: "bow_gale" toca a tensão sem dano; "bow_gale_fire" toca o disparo e a linha, sem dano nem hit stop
	place.call()
	await wait(0.1)
	h0 = hps.call()
	var rp := Player.new()
	rp.remote = true
	world.add_child(rp)
	rp.global_position = player.global_position
	var lines6: int = lines.call()
	BowAbilities.play_remote(rp, "bow_gale", rp.global_position, Vector3.ZERO)
	check(rp.ability == "bow_gale" and not rp.ability_data.get("fired", false), "réplica do Vendaval começa a tensão")
	await wait(0.3)
	check(rp.ability == "bow_gale" and hps.call() == h0, "réplica tensionando não fere")
	var ro: Vector3 = player.global_position + Vector3.UP * BowAbilities.GALE_HEIGHT
	BowAbilities.play_remote(rp, "bow_gale_fire", ro, dir * 0.8)
	check(rp.ability == "bow_gale" and rp.ability_data.get("fired", false) and is_equal_approx(rp.ability_data.get("charge", 0.0), 0.8)
		and lines.call() > lines6, "réplica do Vendaval dispara a linha visual")
	var ts_ok := true
	for i in 6:
		await wait(0.03)
		ts_ok = ts_ok and is_equal_approx(Engine.time_scale, 1.0)
	check(ts_ok, "réplica do Vendaval não dá hit stop")
	await wait_until(func(): return rp.ability == "", 2.0)
	await wait(0.2)
	check(rp.ability == "" and hps.call() == h0, "réplica do Vendaval não fere (%s)" % [hps.call()])
	rp.queue_free()

	# restaura
	for s in saved:
		var e = s[0]
		if is_instance_valid(e):
			e.max_hp = s[1]
			e.hp = s[1]
			e.global_position = s[2]
			e.stagger = 0.0
			e.velocity = Vector3.ZERO
	player.cam_yaw.rotation.y = yaw0
	player.global_position = pos0
	player.velocity = Vector3.ZERO
	player.cooldowns.bow_gale = 0.0
	Game.equip(weapon0)
	Game.fury = fury0
	Game.level = lvl0
	await wait(0.1)


## Chuva de Meteoros (ultimate do cajado, canalizada): soltar, tempo, esquiva, mirar no céu, morrer e réplica.
func _test_meteor_rain() -> void:
	var lvl0: int = Game.level
	var fury0: float = Game.fury
	var weapon0: String = Game.equipment.weapon
	var pos0 := player.global_position
	var yaw0: float = player.cam_yaw.rotation.y
	var pitch0: float = player.cam_pitch.rotation.x
	var spring0: float = player.spring.spring_length
	Game.equip("apprentice_staff")
	await wait_until(func(): return player.dodge_timer <= 0.0 and not player.attacking and player.ability == "")
	var gs: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.kind == "slime" and not e.dead and not e.is_boss:
			gs.append(e)
	gs.sort_custom(func(a, b): return a.global_position.distance_to(player.global_position) < b.global_position.distance_to(player.global_position))
	gs = gs.slice(0, 4)
	check(gs.size() == 4, "Meteoros: 4 slimes para o teste (%d)" % gs.size())
	if gs.size() < 4:
		return
	var saved: Array = []
	for e in gs:
		saved.append([e, e.max_hp, e.global_position])
		e.max_hp = 100000.0
	var base: Vector3 = gs[0].home
	var grounded := func() -> bool: return player.is_on_floor()
	player.global_position = base + Vector3(0, 0.3, 0)
	player.velocity = Vector3.ZERO
	await wait_until(grounded)
	await wait(0.1)
	var c: Vector3 = StaffAbilities._meteor_center(player)
	var flat_d := Vector2(c.x - player.global_position.x, c.z - player.global_position.z).length()
	check(flat_d <= StaffAbilities.METEOR_RANGE + 0.01, "Meteoros: centro da mira no chão a até 14 m (%.1f m)" % flat_d)
	# 3 slimes perto do centro (dentro da área) e 1 longe, do outro lado (fora do alcance de qualquer explosão)
	var place_at := func(ctr: Vector3) -> void:
		var away := Vector3(ctr.x - player.global_position.x, 0.0, ctr.z - player.global_position.z)
		away = away.normalized() if away.length() > 0.1 else player.facing()
		for i in 3:
			var a := i * TAU / 3.0
			gs[i].global_position = ctr + Vector3(cos(a), 0.0, sin(a)) * 0.8 + Vector3.UP * 0.4
		gs[3].global_position = ctr + away * (StaffAbilities.METEOR_AREA + StaffAbilities.METEOR_HIT_RADIUS + 4.0) + Vector3.UP * 0.4
		for e in gs:
			e.velocity = Vector3.ZERO
			e.stagger = 10.0   # parados até o primeiro acerto
			e.hp = e.max_hp
	var hps := func() -> Array:
		var out := []
		for e in gs:
			out.append(e.hp)
		return out
	var mets := func(caster: Node) -> Array:
		var out := []
		for n in world.get_children():
			if n is StaffAbilities.MeteorStrike and n.caster == caster and not n.is_queued_for_deletion():
				out.append(n)
		return out
	var airborne := func(caster: Node) -> int:
		var n := 0
		for m in mets.call(caster):
			if not m.landed:
				n += 1
		return n
	var area_hit := func(hb: Array) -> bool:
		for i in 3:
			if gs[i].hp < hb[i]:
				return true
		return false
	player.invuln = 60.0   # os slimes não interrompem nem enchem a fúria batendo no jogador
	place_at.call(c)
	await wait(0.3)
	place_at.call(c)
	var h0: Array = hps.call()

	# --- 1) segura, solta aos 2,0 s: os 3 da área perdem vida, o de fora não; fúria 0, mana igual
	Game.fury = 100.0
	Game.level = 8
	Game.mp = Game.max_mp()   # cheia (o máximo depende do nível): a regeneração não a muda
	var mp1: float = Game.mp
	var c1: Vector3 = StaffAbilities._meteor_center(player)   # com os slimes no lugar (a mira também acerta inimigos)
	player.use_slot(4)
	var d1: Dictionary = player.ability_data
	check(player.ability == "meteor_rain" and Game.fury == 0.0 and player.ability_slot == 4,
		"Meteoros começa, gasta a fúria e grava a tecla 4 (%s, %.0f, %d)" % [player.ability, Game.fury, player.ability_slot])
	check(d1.get("center", Vector3.INF).distance_to(c1) < 0.05, "Meteoros: área fixada no ponto mirado (%s vs %s)" % [d1.get("center"), c1])
	check(not StaffAbilities.can_dodge_cancel(player), "Meteoros: esquiva não cancela o preparo")
	Game.stamina = Game.max_stamina()
	player._dodge_pressed(Vector3.ZERO)
	check(player.ability == "meteor_rain" and player.dodge_timer <= 0.0, "Meteoros: esquiva no preparo é ignorada")
	await wait_until(func(): return player.ability_t >= 0.3 or player.ability == "")
	check(airborne.call(player) == 0, "Meteoros: nenhum meteoro no preparo")
	await wait_until(func(): return area_hit.call(h0) or player.ability == "", 3.0)
	check(area_hit.call(h0), "Meteoros: um slime da área perde vida (t %.2f)" % player.ability_t)
	check(player.ability == "meteor_rain" and StaffAbilities.can_dodge_cancel(player), "Meteoros: esquiva pode cancelar a canalização")
	check(Vector2(player.velocity.x, player.velocity.z).length() < 0.1, "Meteoros: parado canalizando (vel %s)" % player.velocity)
	var seed1: int = int(d1.get("seed", -1))
	var center1: Vector3 = d1.get("center", c)
	await wait_until(func(): return player.ability_t >= 2.0 or player.ability == "", 3.0)
	check(player.ability == "meteor_rain", "Meteoros: ainda canalizando aos 2,0 s")
	var targets1: Array = d1.get("targets", []).slice(0, 4)
	var n_rel: int = d1.get("targets", []).size()
	StaffAbilities.release(player)
	check(player.ability == "", "Meteoros: soltar a tecla encerra a canalização na hora")
	await wait(0.6)
	check(airborne.call(player) == 0 and d1.get("targets", []).size() == n_rel, "Meteoros: nenhum meteoro novo depois de soltar")
	var h1: Array = hps.call()
	check(h1[0] < h0[0] and h1[1] < h0[1] and h1[2] < h0[2], "Meteoros: os 3 slimes da área perdem vida (%.0f, %.0f, %.0f)"
		% [h0[0] - h1[0], h0[1] - h1[1], h0[2] - h1[2]])
	var want: float = (14.0 + Game.spell_power() * 1.6) * Game.damage_mult()
	var ok_dmg := true
	for i in 3:
		var hits: float = (h0[i] - h1[i]) / want
		ok_dmg = ok_dmg and hits >= 0.99 and absf(hits - roundf(hits)) < 0.01
	check(ok_dmg, "Meteoros: cada explosão tira (14 + INT x 1,6) x dano (%.1f; perdas %.1f, %.1f, %.1f)"
		% [want, h0[0] - h1[0], h0[1] - h1[1], h0[2] - h1[2]])
	check(h1[3] == h0[3], "Meteoros: o slime fora da área não perde vida")
	check(Game.fury == 0.0, "Meteoros: acertos da ultimate não recarregam a fúria (%.2f)" % Game.fury)
	check(Game.mp == mp1, "Meteoros: não gasta mana (%.1f -> %.1f)" % [mp1, Game.mp])
	check(is_equal_approx(Engine.time_scale, 1.0) and player.cam_back == 0.0, "Meteoros: fim restaura tempo e câmera")

	# --- soltar no preparo (um toque na tecla): fica guardado; a chuva abre no fim do preparo, canaliza
	# METEOR_TAP_MIN s e termina sozinha (a ultimate não se desperdiça)
	place_at.call(c)
	await wait(0.1)
	Game.fury = 100.0
	Game.level = 8
	player.use_slot(4)
	await wait_until(func(): return player.ability_t >= 0.2 or player.ability == "")
	check(player.ability == "meteor_rain" and player.ability_t < StaffAbilities.METEOR_WINDUP, "Meteoros: no preparo antes de soltar")
	var dw: Dictionary = player.ability_data
	StaffAbilities.release(player)
	check(player.ability == "meteor_rain" and Game.fury == 0.0, "Meteoros: soltar no preparo não encerra (fica guardado)")
	var tap_t := [0.0]
	await wait_until(func():
		if player.ability == "meteor_rain":
			tap_t[0] = player.ability_t
		return player.ability == "", 3.0)
	var tap_end: float = StaffAbilities.METEOR_WINDUP + StaffAbilities.METEOR_TAP_MIN
	check(player.ability == "" and tap_t[0] >= tap_end - 0.1 and tap_t[0] <= tap_end + 0.05 and dw.get("targets", []).size() >= 4,
		"Meteoros: um toque abre a chuva e ela dura o mínimo (fim aos %.2f s, %d meteoros)" % [tap_t[0], dw.get("targets", []).size()])
	await wait(0.6)
	check(airborne.call(player) == 0, "Meteoros: depois do toque não nasce meteoro novo")
	player.cooldowns.meteor_rain = 0.0

	# --- 2) sem soltar: termina sozinha em <= 4,6 s
	place_at.call(c)
	await wait(0.1)
	Game.fury = 100.0
	Game.level = 8
	player.use_slot(4)
	var last_t := [0.0]
	await wait_until(func():
		if player.ability == "meteor_rain":
			last_t[0] = player.ability_t
		return player.ability == "", 6.0)
	check(player.ability == "" and last_t[0] <= 4.6 and last_t[0] >= 4.0,
		"Meteoros: sem soltar termina sozinha aos 4,5 s (último t %.2f)" % last_t[0])
	await wait(0.6)
	check(airborne.call(player) == 0, "Meteoros: os últimos meteoros caem depois do fim")

	# --- esquiva na canalização: encerra; os meteoros no ar ainda caem e ferem
	place_at.call(c)
	await wait(0.1)
	Game.fury = 100.0
	Game.level = 8
	player.use_slot(4)
	var aimed := [null, null]   # [meteoro no ar, slime perto do alvo dele]
	await wait_until(func():
		if player.ability != "meteor_rain":
			return true
		for m in mets.call(player):
			if m.landed or m.age() > StaffAbilities.METEOR_FALL * 0.5:
				continue
			for i in 3:
				var dd := Vector2(m.target.x - gs[i].global_position.x, m.target.z - gs[i].global_position.z).length()
				if dd < 1.0:
					aimed[0] = m
					aimed[1] = gs[i]
					return true
		return false, 4.0)
	check(aimed[0] != null and player.ability == "meteor_rain", "Meteoros: meteoro no ar sobre um slime antes da esquiva")
	if aimed[0] != null:
		var hd: float = aimed[1].hp
		Game.stamina = Game.max_stamina()
		player._dodge_pressed(Vector3.ZERO)
		check(player.ability == "" and player.dodge_timer > 0.0, "Meteoros: esquiva encerra a canalização")
		check(is_instance_valid(aimed[0]) and not aimed[0].is_queued_for_deletion() and not aimed[0].landed,
			"Meteoros: depois da esquiva o meteoro no ar continua caindo")
		await wait(0.7)
		check(aimed[1].hp < hd, "Meteoros: meteoro no ar fere depois da esquiva (%.0f -> %.0f)" % [hd, aimed[1].hp])
		check(airborne.call(player) == 0, "Meteoros: nenhum meteoro novo depois da esquiva")
	await wait_until(func(): return player.dodge_timer <= 0.0)

	# --- 3) mirar no céu: centro a <= 14 m; 4) morrer no meio: meteoros no ar somem sem dano
	player.cam_pitch.rotation.x = 0.6
	await wait(0.1)
	var cs: Vector3 = StaffAbilities._meteor_center(player)
	var sd := Vector2(cs.x - player.global_position.x, cs.z - player.global_position.z).length()
	check(sd <= StaffAbilities.METEOR_RANGE + 0.01 and sd >= StaffAbilities.METEOR_RANGE - 0.5 and absf(cs.y - player.global_position.y) < 6.0,
		"Meteoros: mirar no céu põe a área no chão a 14 m (%.1f m, dy %.1f)" % [sd, cs.y - player.global_position.y])
	place_at.call(cs)
	await wait(0.1)
	Game.fury = 100.0
	Game.level = 8
	player.use_slot(4)
	var c4: Vector3 = player.ability_data.get("center", Vector3.INF)
	check(Vector2(c4.x - player.global_position.x, c4.z - player.global_position.z).length() <= StaffAbilities.METEOR_RANGE + 0.01,
		"Meteoros: mirando no céu a área começa a até 14 m")
	await wait_until(func(): return player.ability == "" or (player.ability_t > StaffAbilities.METEOR_WINDUP + 0.3 and airborne.call(player) >= 1), 3.0)
	check(player.ability == "meteor_rain" and airborne.call(player) >= 1, "Meteoros: meteoros no ar antes de morrer")
	player._die()
	await get_tree().process_frame
	check(player.ability == "" and airborne.call(player) == 0 and mets.call(player).is_empty() and is_equal_approx(Engine.time_scale, 1.0),
		"Meteoros: morrer remove os meteoros no ar (%d) e restaura o tempo (%.2f)" % [mets.call(player).size(), Engine.time_scale])
	var h4b: Array = hps.call()
	player.revive(player.global_position)
	await wait(0.8)
	check(hps.call() == h4b, "Meteoros: nenhum dano depois de morrer")
	# a tela de morte abre 1,8 s depois de morrer, mesmo revivido: fecha sem a multa de ouro
	await wait_until(func(): return world.modal != null, 3.0)
	if world.modal != null:
		world.modal.queue_free()
		world.modal = null
	world._set_paused(false)
	check(not player.dead and player.cam_back == 0.0, "Meteoros: revive sem resto da habilidade")
	player.cam_pitch.rotation.x = pitch0

	# --- 5) réplica: mesma semente = mesmos pontos de impacto; visual sem dano; para em "meteor_rain_end"
	place_at.call(c)
	await wait(0.1)
	var h5: Array = hps.call()
	var rp := Player.new()
	rp.remote = true
	world.add_child(rp)
	rp.global_position = player.global_position
	StaffAbilities.play_remote(rp, "meteor_rain", center1, Vector3(seed1, 0, 0))
	check(rp.ability == "meteor_rain", "réplica da Chuva de Meteoros começa")
	await wait_until(func(): return rp.ability_data.get("targets", []).size() >= 4 or rp.ability == "", 3.0)
	var rt: Array = rp.ability_data.get("targets", []).slice(0, 4)
	var same := rt.size() == 4 and targets1.size() == 4
	for i in mini(rt.size(), targets1.size()):
		same = same and rt[i].distance_to(targets1[i]) < 0.01
	check(same, "réplica: a semente reproduz os mesmos pontos de impacto (%s vs %s)" % [rt, targets1])
	await wait_until(func(): return rp.ability == "" or rp.ability_data.get("targets", []).size() >= 8, 3.0)
	check(rp.ability == "meteor_rain" and airborne.call(rp) >= 1 and hps.call() == h5, "réplica da Chuva de Meteoros cai e não fere (%s)" % [hps.call()])
	StaffAbilities.play_remote(rp, "meteor_rain_end", c, Vector3.ZERO)
	check(rp.ability == "", "réplica: 'meteor_rain_end' encerra a chuva")
	await wait(0.6)
	check(airborne.call(rp) == 0 and hps.call() == h5, "réplica: nenhum meteoro novo depois do fim e nenhum dano")
	# o estado de rede sem a flag de habilidade (sem morte) encerra macio: os meteoros no ar ainda caem
	StaffAbilities.play_remote(rp, "meteor_rain", center1, Vector3(seed1, 0, 0))
	await wait_until(func(): return airborne.call(rp) >= 1 or rp.ability == "", 3.0)
	var rp_air: Array = []
	for m in mets.call(rp):
		if not m.landed:
			rp_air.append(m)
	rp.apply_net_state(rp.global_position, 0.0, Vector3.ZERO, 0, 0, 0.0)
	await get_tree().process_frame
	var still := 0
	for m in rp_air:
		if is_instance_valid(m) and not m.is_queued_for_deletion():
			still += 1
	check(rp.ability == "" and rp_air.size() >= 1 and still == rp_air.size(),
		"réplica: perder a flag encerra macio, os meteoros no ar continuam (%d de %d)" % [still, rp_air.size()])
	await wait(0.8)
	rp.queue_free()

	# --- réplica removida no meio da chuva (o jogador saiu ou trocou de zona): nada fica órfão na cena
	await wait(1.0)
	var budget0: int = FXEpic._active_amount
	var skies := func() -> int:
		var n := 0
		for x in world.get_children():
			if x.has_node("Dark") and x.has_node("Glow") and not x.is_queued_for_deletion():
				n += 1
		return n
	var sky0: int = skies.call()
	var rq := Player.new()
	rq.remote = true
	world.add_child(rq)
	rq.global_position = player.global_position
	StaffAbilities.play_remote(rq, "meteor_rain", center1, Vector3(seed1, 0, 0))
	await wait_until(func(): return rq.ability_t >= StaffAbilities.METEOR_WINDUP + 0.6 or rq.ability == "", 3.0)
	check(rq.ability == "meteor_rain" and skies.call() == sky0 + 1, "réplica removida: céu escuro no ar antes de sair (%d)" % skies.call())
	rq.queue_free()
	for i in 3:
		await get_tree().process_frame
	var live_mets := 0
	for x in world.get_children():
		if x is StaffAbilities.MeteorStrike and not x.is_queued_for_deletion():
			live_mets += 1
	check(skies.call() == sky0 and live_mets == 0, "réplica removida: céu, redemoinho e meteoros somem com ela (%d céus, %d meteoros)" % [skies.call(), live_mets])
	await wait(1.2)   # as explosões que já tinham começado terminam a vida
	check(FXEpic._active_amount <= budget0, "réplica removida: o orçamento de partículas volta (%d -> %d)" % [budget0, FXEpic._active_amount])

	# --- 6) encosta de montanha: de pé na encosta do Pico do sudoeste, mirando no céu para fora (para a
	# planície lá embaixo). O centro e cada ponto de impacto ficam no chão de verdade (um raio de cima a
	# baixo no mesmo x, z), não enterrados nem flutuando na altura do jogador.
	var top_ground := func(x: float, z: float) -> float:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 300.0, z), Vector3(x, -100.0, z), StaffAbilities.METEOR_GROUND_MASK)
		var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(q)
		return hit.position.y if not hit.is_empty() else -999.0
	var pk: Vector3 = world.MOUNTAINS[0][0]
	var out := Vector3(-pk.x, 0.0, -pk.z).normalized()   # do pico para o meio do mapa
	var best_r := 0.0
	var best_drop := -1.0
	for r in range(4, 36):
		var a: Vector3 = pk + out * float(r)
		var b2: Vector3 = a + out * StaffAbilities.METEOR_RANGE
		var drop: float = top_ground.call(a.x, a.z) - top_ground.call(b2.x, b2.z)
		if drop > best_drop:
			best_drop = drop
			best_r = float(r)
	var flank: Vector3 = pk + out * best_r
	player.global_position = Vector3(flank.x, top_ground.call(flank.x, flank.z) + 0.5, flank.z)
	player.velocity = Vector3.ZERO
	player._snap_visuals()
	await wait_until(grounded)
	await wait(0.2)
	player.cam_yaw.rotation.y = atan2(-out.x, -out.z)   # frente da câmera (-Z) para fora do pico
	var pf: Vector3 = player.global_position
	check(pf.y > 10.0, "Meteoros: jogador no alto da encosta (y %.1f)" % pf.y)
	# no céu (o ponto vai a 14 m) e para baixo, na planície distante (o raio acerta o chão bem além dos
	# 14 m e o ponto a 14 m ainda está no meio da encosta, muito acima do acerto)
	for pitch in [0.6, -0.5]:
		player.cam_pitch.rotation.x = pitch
		await wait(0.15)
		var aim: Vector3 = player.aim_point()
		var cm: Vector3 = StaffAbilities._meteor_center(player)
		var cm_ref: float = top_ground.call(cm.x, cm.z)
		var pn: Vector3 = player.global_position   # (no topo o jogador pode escorregar um pouco)
		check(absf(cm.y - cm_ref) < 0.05 and Vector2(cm.x - pn.x, cm.z - pn.z).length() <= StaffAbilities.METEOR_RANGE + 0.01,
			"Meteoros: na encosta (pitch %.1f) o centro fica no chão (y %.2f, chão %.2f, jogador %.1f, mira em y %.1f a %.0f m)"
			% [pitch, cm.y, cm_ref, pf.y, aim.y, Vector2(aim.x - pf.x, aim.z - pf.z).length()])
	Game.fury = 100.0
	Game.level = 8
	player.use_slot(4)
	await wait_until(func(): return player.ability_data.get("targets", []).size() >= 6 or player.ability == "", 3.0)
	var on_ground := 0
	var tg: Array = player.ability_data.get("targets", [])
	for t in tg:
		if absf(t.y - top_ground.call(t.x, t.z)) < 0.05:
			on_ground += 1
	check(tg.size() >= 6 and on_ground == tg.size(), "Meteoros: na encosta os meteoros caem no chão (%d de %d)" % [on_ground, tg.size()])
	player.end_ability()
	player.cooldowns.meteor_rain = 0.0

	# restaura
	for s in saved:
		var e = s[0]
		if is_instance_valid(e):
			e.max_hp = s[1]
			e.hp = s[1]
			e.global_position = s[2]
			e.stagger = 0.0
			e.velocity = Vector3.ZERO
	player.cam_yaw.rotation.y = yaw0
	player.cam_pitch.rotation.x = pitch0
	player.global_position = pos0
	player.velocity = Vector3.ZERO
	player.invuln = 0.0
	player.cooldowns.meteor_rain = 0.0
	Game.equip(weapon0)
	Game.fury = fury0
	Game.level = lvl0
	await wait(0.3)
	check(absf(player.spring.spring_length - spring0) < 0.3, "Meteoros: câmera de volta (%.2f)" % player.spring.spring_length)


func _test_fx_epic() -> void:
	var p := player.global_position
	var n0 := get_tree().current_scene.get_child_count()
	FXEpic.glow_burst(p, Color.ORANGE)
	FXEpic.sparks(p, Vector3.UP, Color.YELLOW)
	FXEpic.smoke(p)
	FXEpic.flash(p, Color.ORANGE)
	FXEpic.ground_mark(p, Color.BLACK, 2.0, 1.0)
	FXEpic.trail(player.model, Color.ORANGE)
	check(get_tree().current_scene.get_child_count() >= n0 + 6, "efeitos épicos criados")
	FXEpic.hit_stop(0.05)
	FXEpic.hit_stop(0.05)
	check(Engine.time_scale >= 0.05 and Engine.time_scale < 1.0, "hit stop ativo (%.2f)" % Engine.time_scale)
	await get_tree().create_timer(0.3, true, false, true).timeout
	check(is_equal_approx(Engine.time_scale, 1.0), "hit stop volta para 1.0")
	# perder o guarda no meio do hit stop também restaura o tempo
	FXEpic.hit_stop(5.0)
	check(Engine.time_scale < 1.0, "hit stop longo ativo")
	FXEpic._hs_guard.free()
	check(is_equal_approx(Engine.time_scale, 1.0), "guarda liberado cedo restaura o tempo")
	FXEpic.hit_stop(0.05)
	await get_tree().create_timer(0.3, true, false, true).timeout
	check(is_equal_approx(Engine.time_scale, 1.0), "hit stop volta para 1.0 de novo")
	await wait(2.0)
	check(get_tree().current_scene.get_child_count() <= n0 + 1, "efeitos épicos se liberam")
	check(FXEpic._active_amount == 0, "orçamento de partículas devolvido (%d)" % FXEpic._active_amount)
	# liberar um emissor antes da hora também devolve o orçamento
	FXEpic.glow_burst(p, Color.ORANGE, 40)
	check(FXEpic._active_amount == 40, "orçamento reservado (%d)" % FXEpic._active_amount)
	get_tree().current_scene.get_child(get_tree().current_scene.get_child_count() - 1).free()
	check(FXEpic._active_amount == 0, "emissor liberado cedo devolve o orçamento (%d)" % FXEpic._active_amount)


# ---------------------------------------------------------------- Ferreiro
func _test_blacksmith() -> void:
	var back := player.global_position
	var smith := _interactable("blacksmith") as Blacksmith
	check(smith != null and smith.state == Blacksmith.State.WORK, "ferreiro começa trabalhando")
	if smith == null:
		return
	# jogador longe: golpes acontecem mas o som não toca (fora de FAR_DIST)
	player.global_position = smith.global_position + Vector3(Sfx.FAR_DIST + 5.0, 0.3, 0)
	var s0 := smith.strikes
	# esvazia os slots 3D que já tocaram a bigorna: outros sons (inimigos perto do jogador) podem ocupar
	# slots à vontade, mas nenhum pode voltar a receber o som da bigorna enquanto o jogador está longe
	var clang: AudioStream = Sfx.streams["anvil"]
	for p3 in Sfx._players_3d:
		if p3.stream == clang:
			p3.stop()
			p3.stream = null
	# 3,2 s: cobre o pior caso de começar logo no início de uma pausa (work_pause 2,5 s + golpe a 0,53 s)
	await wait(3.2)
	check(smith.strikes > s0, "ferreiro bate na bigorna (%d golpes)" % (smith.strikes - s0))
	var clangs := Sfx._players_3d.filter(func(p3: AudioStreamPlayer3D) -> bool: return p3.stream == clang).size()
	check(clangs == 0, "som do golpe não toca com o jogador longe (%d slots com a bigorna)" % clangs)
	# outro modal pausa o jogo (menu, inventário, loja, outro diálogo): a bigorna fica quieta
	smith._work()
	get_tree().paused = true
	var sp := smith.strikes
	await wait(1.5)   # mais que uma volta do work_hammer (1,2 s)
	check(smith.strikes == sp and smith.state == Blacksmith.State.WORK, "ferreiro para de martelar com o jogo pausado por outro modal (%d golpes)" % (smith.strikes - sp))
	get_tree().paused = false
	var wh: Animation = smith.anim.get_animation(smith.clip("work_hammer"))
	check(wh.find_track(smith.anim.get_node(smith.anim.root_node).get_path_to(smith), Animation.TYPE_METHOD) >= 0, "golpe injetado no clipe que o ferreiro toca (%s)" % smith.clip("work_hammer"))
	# chega perto: para e vira
	var ahead := smith.anvil.global_position - smith.global_position
	ahead.y = 0.0
	player.global_position = smith.anvil.global_position + ahead.normalized() * 2.0 + Vector3(0, 0.3, 0)
	await wait(0.6)
	check(smith.state == Blacksmith.State.IDLE, "ferreiro para quando o jogador chega")
	var s1 := smith.strikes
	smith._on_strike()   # o que a method track do work_hammer faria no blend de saída
	check(smith.strikes == s1, "golpe fora do trabalho é ignorado")
	# conversa: anima com o jogo pausado
	smith.interact(player)
	await wait(0.1)
	check(smith.state == Blacksmith.State.TALK and get_tree().paused, "ferreiro conversa com o jogo pausado")
	var ap: AnimationPlayer = smith.anim
	var p0 := ap.current_animation_position
	await wait(0.3)
	check(ap.current_animation_position != p0, "ferreiro continua animando durante o diálogo")
	world.modal._choose(Callable())
	await wait(0.1)
	check(smith.state == Blacksmith.State.IDLE and not get_tree().paused, "ferreiro volta a ouvir após o diálogo (estado %s, pausado %s)" % [Blacksmith.State.keys()[smith.state], get_tree().paused])
	# sai de perto: volta a martelar e vira para a bigorna
	player.global_position = smith.global_position + Vector3(Blacksmith.NEAR + 3.0, 0.3, 0)
	await wait(1.0)
	check(smith.state == Blacksmith.State.WORK, "ferreiro volta a trabalhar quando o jogador sai (estado %s)" % Blacksmith.State.keys()[smith.state])
	check(absf(angle_difference(smith.model.rotation.y, smith._base_yaw)) < 0.2, "ferreiro vira de volta para a bigorna")
	check(smith.clip("work_hammer") == "work_hammer", "sem biblioteca Mixamo, usa clipe provisório")
	player.global_position = back


# ---------------------------------------------------------------- Horta, caldeirão e comida
func _interactable(id: String, index := -1) -> Node:
	for n in get_tree().get_nodes_in_group("interactable"):
		if n.npc_id == id and (index < 0 or n.get("index") == index):
			return n
	return null


func _test_farm() -> void:
	var plot := _interactable("plot", 0)
	check(plot != null and Game.plot_state(0) == "empty", "canteiro 0 vazio e liberado")
	check(Game.plot_state(Game.FARM_START_PLOTS) == "locked", "canteiros extras começam bloqueados")
	player.global_position = plot.global_position + Vector3(0, 0.3, -1.2)
	await wait(0.3)
	check(player.interact_target == plot, "jogador detecta o canteiro")
	plot.interact(player)
	await wait(0.1)
	check(world.modal != null and world.modal.get("plot_index") == 0, "menu de plantio abre")
	var seeds0 := Game.count_item("seed_carrot")
	world.modal.seed_list.select(ItemDB.CROP_ORDER.find("carrot"))
	world.modal._plant_here()
	await wait(0.1)
	check(world.modal == null and Game.plot_state(0) == "growing" and Game.farm.plots[0].crop == "carrot", "cenoura plantada")
	check(Game.count_item("seed_carrot") == seeds0 - 1, "semente consumida")
	plot.interact(player)
	check(Game.farm.plots[0].watered, "canteiro regado")
	var g0: float = Game.plot_growth(0)
	var t0 := Econ.now()
	await wait(1.0)
	var g1: float = Game.plot_growth(0)
	var rate := (g1 - g0) / (Econ.now() - t0)
	check(g1 > g0 and abs(rate - 2.0 / ItemDB.CROPS.carrot.time) < 0.02, "regado cresce 2x (%.3f/s)" % rate)
	Econ.time_offset += ItemDB.CROPS.carrot.time   # a horta cresce pelo relógio: adianta o relógio
	await wait(0.3)
	check(Game.plot_state(0) == "ready", "planta fica pronta")
	var carrots := Game.count_item("carrot")
	plot.interact(player)
	check(Game.plot_state(0) == "empty" and Game.count_item("carrot") >= carrots + 3, "colheita regada rende +1 (%d)" % (Game.count_item("carrot") - carrots))

	# adubo de gel de slime
	Game.add_item("slime_gel", 1, true)
	Game.plant(1, "wheat", true)
	Game.water(1)
	Game.fertilize(1)
	check(Game.farm.plots[1].fert and Game.plot_growth(1) >= 0.4, "adubo de gel de slime acelera")

	# plantar em todos os vazios
	Econ.grant(200, 0, {}, "teste")
	plot.interact(player)
	await wait(0.1)
	world.modal.seed_list.select(ItemDB.CROP_ORDER.find("tomato"))
	world.modal._plant_all()
	await wait(0.1)
	var growing := 0
	for i in Game.FARM_PLOTS:
		if Game.plot_state(i) == "growing":
			growing += 1
	check(growing == Game.FARM_START_PLOTS, "plantar em todos os vazios (%d canteiros)" % growing)

	# liberar canteiro
	var gold0 := Game.gold
	var cost := Game.unlock_cost()
	Game.unlock_next_plot()
	check(Game.farm.unlocked == Game.FARM_START_PLOTS + 1 and Game.gold == gold0 - cost, "canteiro novo liberado por %d ouro" % cost)

	# caldeirão
	var kitchen := _interactable("kitchen")
	check(kitchen != null, "caldeirão na horta")
	Game.add_item("tomato", 6, true)
	Game.add_item("pepper", 6, true)
	Game.add_item("carrot", 2, true)
	kitchen.interact(player)
	await wait(0.1)
	check(world.modal != null and world.modal.has_method("_cook"), "menu do caldeirão abre")
	world.modal.list.select(ItemDB.RECIPE_ORDER.find("spicy_soup"))
	world.modal._cook(99)
	check(Game.count_item("spicy_soup") == 3, "cozinhou 3 sopas picantes (%d)" % Game.count_item("spicy_soup"))
	world.modal._close()
	await wait(0.05)
	Game.cook("dragon_chili")
	check(Game.count_item("dragon_chili") == 1, "cozinhou chili do dragão")

	# comer: bônus temporário
	var dmg0 := Game.melee_damage()
	Game.selected_food = "spicy_soup"
	Game.eat_cooldown = 0.0
	check(Game.eat_selected() and Game.food_buffs.has("spicy_soup"), "comeu sopa picante")
	check(Game.melee_damage() > dmg0 * 1.25, "sopa aumenta o dano (%.1f -> %.1f)" % [dmg0, Game.melee_damage()])
	check(not Game.eat("spicy_soup"), "não come de novo durante a mastigação")
	Game.tick_food(999.0)
	check(Game.food_buffs.is_empty() and abs(Game.melee_damage() - dmg0) < 0.01, "bônus expira e o dano volta")

	# a horta também fica no save solo
	var farm_saved: Dictionary = Game.farm.duplicate(true)
	var g_saved := Game.plot_growth(1)
	Game.farm = {"unlocked": 0, "plots": []}
	check(Econ.reload_solo(), "serviço local recriado (horta)")
	check(Game.farm.unlocked == farm_saved.unlocked and Game.farm.plots[1].crop == "wheat" \
		and abs(Game.plot_growth(1) - g_saved) < 0.05, "save solo guarda a horta")


# ---------------------------------------------------------------- Desafio da Horda
func _test_survival() -> void:
	var portal: Node = null
	for n in get_tree().get_nodes_in_group("interactable"):
		if n.npc_id == "portal":
			portal = n
	check(portal != null, "portal do desafio na vila")
	player.global_position = portal.global_position + Vector3(0, 0.3, 1.5)
	await wait(0.3)
	check(player.interact_target == portal, "jogador detecta o portal")
	portal.interact(player)
	await wait(0.1)
	check(world.modal != null and world.modal.pages[0].has("choices"), "portal abre diálogo com escolha")
	var xp0 := Game.xp
	var lvl0 := Game.level
	var gold0 := Game.gold
	world.modal._choose(world.modal.pages[0].choices[0].action)
	await wait(0.2)
	var sv = world.survival
	check(sv != null and Game.run_mods.active, "desafio iniciado pelo portal")
	check(player.global_position.distance_to(world.ARENA) < 3.0, "jogador teleportado para a arena")
	check(sv.weapon_levels.get("fogo", 0) == 1, "começa com Orbe de Fogo Nv 1")
	sv.round_time = 6.0
	sv.round_left = 6.0
	await wait(3.0)
	var horde: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.horde:
			horde.append(e)
	check(horde.size() >= 2, "inimigos da horda surgem (%d)" % horde.size())
	var near := true
	for e in horde:
		if e.global_position.distance_to(world.ARENA) > sv.ARENA_RADIUS + 1.0:
			near = false
	check(near, "inimigos nascem dentro da arena")
	for e in horde:
		if is_instance_valid(e) and not e.dead:
			e.take_damage(99999, player.global_position, false)
	await wait(0.1)
	check(sv.kills >= horde.size(), "abates contados (%d)" % sv.kills)
	check(sv.my_dmg > 0.0, "placar soma o dano causado (%d)" % int(sv.my_dmg))
	var rows: Array = sv.scoreboard_rows()
	check(rows.size() == 1 and rows[0].me and rows[0].build.w.has("fogo"), "placar do Tab tem a build do jogador")
	sv.hud.scoreboard.force_open = true
	await wait(0.1)
	check(sv.hud.scoreboard.visible and sv.hud.weapon_row.get_child_count() == 1, "Tab abre o placar e a build aparece em ícones")
	sv.hud.scoreboard.force_open = false
	check(Game.xp == xp0 and Game.level == lvl0, "horda não dá XP do RPG")
	check(get_tree().get_nodes_in_group("xp_gems").size() > 0, "gemas de XP caem")
	var gem = get_tree().get_nodes_in_group("xp_gems")[0]
	player.global_position = gem.global_position + Vector3(0.5, 0.0, 0.0)
	await wait(0.8)
	check(not is_instance_valid(gem) and sv.run_xp + sv.run_level > 1, "gema coletada ao se aproximar")

	# subida de nível da partida
	sv.add_xp(sv.xp_needed())
	await wait(0.1)
	check(world.modal != null and world.modal.mode == "levelup" and get_tree().paused, "cartas de nível abrem e pausam")
	check(world.modal.choices.size() == 3, "3 cartas oferecidas")
	await _pick_levelups(true)
	check(not get_tree().paused, "jogo volta após a escolha")

	# fim de rodada: limpa a arena e oferece bênção
	sv.round_left = 0.01
	for i in 50:
		await wait(0.1)
		if world.modal != null and world.modal.get("mode") == "round":
			break
		await _pick_levelups(false)
	check(sv.rounds_cleared == 1 and world.modal != null and world.modal.mode == "round", "fim da rodada abre escolha de bênção")
	var horde_alive := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.horde:
			horde_alive += 1
	check(horde_alive == 0, "pulso de fim de rodada elimina a horda")
	await wait(0.45)
	world.modal._pick(0)
	await wait(0.2)
	check(sv.blessing_counts.size() == 1 and sv.round_num == 2 and sv.phase == "fight", "bênção aplicada e rodada 2 começa")
	check(sv.seeds_won >= 1, "rodada concluída dá sementes (%d)" % sv.seeds_won)

	# comer no meio da rodada: chili explode e fere a horda em volta
	var near_e: Enemy = sv._spawn_enemy("slime", player.global_position + Vector3(3, 0.2, 0))
	await wait(0.1)
	var ehp := near_e.hp
	Game.eat_cooldown = 0.0
	Game.selected_food = "dragon_chili"
	check(Game.eat_selected() and Game.food_buffs.has("dragon_chili"), "comeu chili do dragão na rodada")
	check(near_e.dead or near_e.hp < ehp, "explosão do chili fere inimigos próximos")
	check(Game.mod("damage") > Game.run_mods.damage, "bônus da comida soma aos da Horda")

	# elite: maior, mais vida e solta mais gemas
	var plain: Enemy = sv._spawn_enemy("slime", player.global_position + Vector3(-5, 0.2, 0))
	var elite: Enemy = sv._spawn_enemy("slime", player.global_position + Vector3(-5, 0.2, 2), -1.0, -1.0, true)
	await wait(0.1)
	check(elite.elite and elite.max_hp > plain.max_hp * 3.0, "elite tem 3x+ a vida de um comum")
	var gems0 := get_tree().get_nodes_in_group("xp_gems").size()
	elite.take_damage(99999, player.global_position, false)
	plain.take_damage(99999, player.global_position, false)
	await wait(0.1)
	check(get_tree().get_nodes_in_group("xp_gems").size() >= gems0 + 4, "elite solta várias gemas")
	for g in get_tree().get_nodes_in_group("xp_gems"):
		g.queue_free()   # não deixa XP extra no chão para os testes seguintes

	# combo (efeito direto): dano em área em volta do ponto
	var ce: Enemy = sv._spawn_enemy("slime_grande", player.global_position + Vector3(0, 0.2, -4))
	await wait(0.1)
	var chp := ce.hp
	sv.weapons.combo_strike("choque", ce.global_position, 2)
	check(ce.hp < chp or ce.dead, "efeito de combo fere inimigos em volta")
	if not ce.dead:
		ce._die()
	await wait(0.05)
	for g in get_tree().get_nodes_in_group("xp_gems"):
		g.queue_free()
	check(UPG.combo_for("aura", "fogo") == "choque" and UPG.combo_for("fogo", "fogo") == "", "pares de combo")

	# escala de dificuldade: sobe a cada rodada e alivia na do chefe
	var r0: int = sv.round_num
	sv.round_num = 4
	var hp4: float = sv.hp_scale()
	sv.round_num = 9
	check(sv.hp_scale() > hp4 * 1.8 and sv.elite_chance() > 0.0, "inimigos escalam com a rodada")
	var evt = load("res://scripts/survival/horde_events.gd")
	check(evt.spawn_rate(4, 1) > evt.spawn_rate(5, 1) and evt.spawn_rate(6, 1) > evt.spawn_rate(1, 1),
		"ritmo em dente de serra: alivia na rodada do chefe e o ciclo seguinte começa mais forte")
	sv.round_num = r0

	# chefe na rodada 5
	sv.round_num = 4
	sv._start_round()
	await wait(0.1)
	check(sv.boss_alive() and sv.boss.horde, "Rei Goblin aparece na rodada 5")
	check(sv.event == "", "rodada do chefe sem evento")
	var king_flag = Game.flags.get("king_dead", false)
	sv.boss.take_damage(99999, player.global_position, false)
	await wait(0.1)
	check(Game.flags.get("king_dead", false) == king_flag and not sv.boss_alive(), "chefe da horda derrotado sem afetar missões")

	await _test_horde_extras(sv)

	# retirada pelo menu de pausa
	world._open_modal(_pause_menu())
	await wait(0.1)
	world.modal._abandon()
	await wait(0.2)
	check(world.modal != null and world.modal.mode == "results", "tela de resultados ao abandonar")
	await wait(0.45)
	world.modal._finish()
	await wait(0.2)
	check(world.survival == null and not Game.run_mods.active, "desafio encerrado e bônus zerados")
	check(player.global_position.distance_to(world.VILLAGE_SPAWN) < 3.0, "jogador volta para a vila")
	check(Game.xp != xp0 or Game.level > lvl0, "XP de recompensa entregue ao RPG")
	check(Game.flags.has("horde_best"), "recorde salvo")
	check(Econ.quick_save(player.global_position, 0.0), "salvar volta a funcionar após o desafio")

	# morte no desafio não tira ouro
	world.start_survival()
	await wait(0.2)
	sv = world.survival
	var gold1 := Game.gold
	player.invuln = 0
	player.take_damage(99999, player.global_position + Vector3.FORWARD)
	check(player.dead, "jogador cai na horda")
	await wait(2.2)
	check(world.modal != null and world.modal.mode == "results", "resultados após morrer no desafio")
	await wait(0.45)
	world.modal._finish()
	await wait(0.2)
	check(not player.dead and Game.gold == gold1 and Game.hp == Game.max_hp(), "volta à vila sem perder ouro")
	check(gold1 >= gold0, "ouro não diminuiu durante o desafio")


## Monstros novos, eventos e Caçada (solo). As armas automáticas ficam desligadas para não
## matarem os monstros antes de eles mostrarem o comportamento.
func _test_horde_extras(sv) -> void:
	await _pick_levelups(false)
	sv.weapons.process_mode = Node.PROCESS_MODE_DISABLED
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.horde and not e.dead:
			e._die()
	sv.round_left = 999.0
	sv._spawn_acc = -9999.0   # sem spawns normais durante o teste
	sv.event = ""
	sv.hunt_target = 0
	await wait(0.3)
	var base: Vector3 = player.global_position

	# slime explosivo: corre até o jogador, explode (dano em área) e morre
	player.invuln = 0
	Game.hp = Game.max_hp()
	var hp0 := Game.hp
	var bomb: Enemy = sv._spawn_enemy("slime_explosivo", base + Vector3(3.0, 0.2, 0))
	var kills0: int = sv.kills
	check(await _until(func() -> bool: return not is_instance_valid(bomb) or bomb.dead, 5.0), "slime explosivo explode")
	check(Game.hp < hp0, "explosão fere o jogador (%.0f → %.0f)" % [hp0, Game.hp])
	check(sv.kills == kills0 + 1, "explosão conta como abate")
	Game.hp = Game.max_hp()

	# Slime Mãe se divide em 3 slimes velozes
	var veloz0 := _count_alive("slime_veloz")
	var mae: Enemy = sv._spawn_enemy("slime_mae", base + Vector3(-12, 0.2, 0))
	await wait(0.1)
	mae.take_damage(99999, base, false)
	await wait(0.2)
	check(_count_alive("slime_veloz") == veloz0 + 3, "Slime Mãe se divide em 3 (%d)" % (_count_alive("slime_veloz") - veloz0))
	_kill_horde()
	await wait(0.2)

	# Goblin Arqueiro mantém distância e atira flechas
	var archer: Enemy = sv._spawn_enemy("goblin_arqueiro", base + Vector3(0, 0.2, 9.0))
	var arrow_seen := await _until(func() -> bool: return _count_script(sv, preload("res://scripts/enemies/enemy_arrow.gd")) > 0, 6.0)
	check(arrow_seen, "Goblin Arqueiro atira flechas")
	check(archer.global_position.distance_to(player.global_position) > 4.0, "arqueiro mantém distância (%.1f m)" % archer.global_position.distance_to(player.global_position))
	player.invuln = 0
	Game.hp = Game.max_hp()
	var hp1 := Game.hp
	check(await _until(func() -> bool: return Game.hp < hp1, 6.0), "flecha acerta o jogador")
	_kill_horde()
	Game.hp = Game.max_hp()
	await wait(0.2)

	# Goblin Xamã cura os aliados em volta
	var shaman: Enemy = sv._spawn_enemy("goblin_xama", base + Vector3(8.0, 0.2, 0))
	var hurt: Enemy = sv._spawn_enemy("slime_grande", base + Vector3(9.0, 0.2, 1.0))
	await wait(0.1)
	hurt.hp = hurt.max_hp * 0.3
	var hhp := hurt.hp
	check(await _until(func() -> bool: return is_instance_valid(hurt) and hurt.hp > hhp, 7.0), "Goblin Xamã cura aliados (%.0f → %.0f)" % [hhp, hurt.hp])
	check(is_instance_valid(shaman) and shaman.data.get("tint") != null, "xamã com cor própria")
	_kill_horde()
	Game.hp = Game.max_hp()
	await wait(0.2)

	# Goblin Dourado: foge e some sem contar abate; abatido, solta ouro
	var gold_g: Enemy = sv._spawn_enemy("goblin_dourado", base + Vector3(5, 0.2, 0))
	await wait(1.0)
	check(gold_g.global_position.distance_to(player.global_position) > 5.5, "Goblin Dourado foge do jogador")
	var k1: int = sv.kills
	gold_g.born_t = sv.GOLD_ESCAPE + 1.0
	await wait(0.2)
	check(gold_g.dead and gold_g.escaped and sv.kills == k1, "Goblin Dourado escapa sem contar abate")
	var gold_g2: Enemy = sv._spawn_enemy("goblin_dourado", base + Vector3(2, 0.2, 0))
	await wait(0.1)
	var coins0 := _count_script(sv, preload("res://scripts/world/pickup.gd"))
	gold_g2.take_damage(99999, base, false)
	await wait(0.1)
	check(_count_script(sv, preload("res://scripts/world/pickup.gd")) >= coins0 + 3 or Game.gold > 0, "Goblin Dourado abatido solta ouro")

	# Campeão Goblin: elite com barra de vida sempre visível
	var champ: Enemy = sv._spawn_enemy("goblin_campeao", base + Vector3(-6, 0.2, 0))
	await wait(0.1)
	check(champ.bar_root.visible and champ.max_hp > 400, "Campeão Goblin (elite, %d de vida)" % champ.max_hp)
	_kill_horde()
	Game.hp = Game.max_hp()
	await wait(0.3)

	# Chuva de Meteoros: o círculo avisa e o impacto fere quem ficou dentro
	_clear_gems()
	await _pick_levelups(false)
	sv.event = "meteoros"
	player.invuln = 0
	Game.hp = Game.max_hp()
	var hp2 := Game.hp
	sv._meteor_t = 999.0
	sv._drop_meteor(player.global_position)
	check(sv._meteors.size() == 1, "meteoro anunciado com aviso")
	# cartas de nível (gemas ainda chegando) pausam o jogo: escolhe e segue esperando
	await _until(func() -> bool:
		if world.modal != null and world.modal.get("mode") == "levelup" and world.modal._lock <= 0.0:
			world.modal._pick(0)
		return sv._meteors.is_empty(), 8.0)
	check(Game.hp < hp2 and sv._meteors.is_empty(), "meteoro cai e fere quem ficou no círculo (hp %.0f→%.0f, %d pendentes, fase %s, pausado %s, modal %s)" % [hp2, Game.hp, sv._meteors.size(), sv.phase, get_tree().paused, world.modal])
	sv.event = ""
	Game.hp = Game.max_hp()

	# sorteio dos eventos
	var seen := {}
	for i in 200:
		var ev: String = sv.EVT.roll_event(3 + i % 4, false, "")
		if ev != "":
			seen[ev] = true
	check(seen.size() >= 5, "eventos sorteados variam (%s)" % ", ".join(seen.keys()))
	check(sv.EVT.roll_event(5, true) == "" and sv.EVT.roll_event(1, false) == "", "sem evento na rodada 1 e na do chefe")

	# Caçada: bater a meta dá o baú (gemas e ouro em volta do jogador)
	_clear_gems()
	await _pick_levelups(false)
	sv.hunt_target = sv.hunt_kills + 1
	sv.hunt_done = false
	var won0: int = sv.hunts_won
	var gems0 := get_tree().get_nodes_in_group("xp_gems").size()
	var victim: Enemy = sv._spawn_enemy("slime", base + Vector3(4, 0.2, 0))
	await wait(0.1)
	victim.take_damage(99999, base, false)
	# conta logo: o ímã recolhe as gemas em poucos quadros
	var gems1 := get_tree().get_nodes_in_group("xp_gems").size()
	check(sv.hunt_done and sv.hunts_won == won0 + 1, "Caçada concluída dá o baú")
	check(gems1 >= gems0 + 6, "baú da Caçada solta gemas (%d)" % (gems1 - gems0))
	await wait(0.1)
	sv.hunt_target = 0

	# HUD da horda mostra nível e habilidades
	var hud = sv.hud
	await wait(0.05)
	check(hud.lvl_label.text.ends_with(" %d" % sv.run_level), "HUD mostra o nível (%s)" % hud.lvl_label.text)
	check(hud.weapon_row.get_child_count() == sv.weapon_levels.size(), "HUD mostra os ícones das armas (%d)" % hud.weapon_row.get_child_count())
	check(hud.extra_row.get_child_count() == sv.passive_levels.size() + sv.blessing_counts.size(), "HUD mostra os ícones das passivas e bênçãos")

	sv.weapons.process_mode = Node.PROCESS_MODE_INHERIT
	sv._spawn_acc = 0.0
	await _pick_levelups(false)


func _until(cond: Callable, max_t: float) -> bool:
	var t := 0.0
	while not cond.call() and t < max_t:
		await wait(0.1)
		t += 0.1
	return cond.call()


func _count_alive(kind: String) -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.kind == kind and not e.dead:
			n += 1
	return n


func _count_script(parent: Node, scr: Script) -> int:
	var n := 0
	for c in parent.get_children():
		if c.get_script() == scr:
			n += 1
	return n


func _clear_gems() -> void:
	for g in get_tree().get_nodes_in_group("xp_gems"):
		g.remove_from_group("xp_gems")
		g.queue_free()


func _kill_horde() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.horde and not e.dead:
			e.take_damage(99999, player.global_position, false)


# ---------------------------------------------------------------- Aviso de atualização durante a partida
func _test_update() -> void:
	check(Updater.state == Updater.State.DISABLED, "auto update desligado fora do build exportado")
	# simula a checagem periódica achando uma versão nova com a partida em andamento
	Updater.latest_version = "99.0.0"
	Updater._set_state(Updater.State.AVAILABLE)
	check(Updater._toast != null and Updater._toast.visible, "aviso de versão nova aparece durante a partida")
	world._open_modal(_pause_menu())
	await wait(0.1)
	var panel: Control = null
	for n in world.modal.find_children("*", "VBoxContainer", true, false):
		if n.get_script() == preload("res://scripts/ui/update_panel.gd"):
			panel = n
	check(panel != null and panel.is_visible_in_tree(), "menu de pausa oferece Atualizar agora")
	world.modal._close()
	await wait(0.1)
	Updater.latest_version = ""
	Updater._set_state(Updater.State.DISABLED)
	check(not Updater._toast.visible, "aviso some quando não há versão nova")
	# recusa por versão: servidor antigo (deploy em andamento) x jogo desatualizado
	var r := "Versão diferente do servidor (sua: %s, servidor: %s). Atualize o jogo."
	check(Network.explain_rejection(r % ["0.5.3", "0.5.2"], "0.5.3").begins_with("O servidor ainda está na v0.5.2"),
		"jogo mais novo que o servidor: avisa que o servidor está sendo atualizado")
	check(Network.explain_rejection(r % ["0.5.2", "0.5.3"], "0.5.2") == r % ["0.5.2", "0.5.3"],
		"jogo mais velho que o servidor: mantém o pedido para atualizar")


func _pause_menu() -> Control:
	var p := preload("res://scripts/ui/pause_menu.gd").new()
	p.mode = "pause"
	return p


## Registra os projéteis CRIADOS na cena (não só os vivos): a faísca do cajado e a bola de fogo seguem a mira
## da câmera, batem no chão a poucos metros e somem; contar só os vivos depois de uma espera falhava no CI.
## Devolve [lista de kinds, callable]; chame _stop_spawn_watch com o resultado ao terminar.
func _watch_spawns() -> Array:
	var seen: Array[String] = []
	var cb := func(n: Node) -> void:
		if n is Area3D and n.get_script() == preload("res://scripts/player/projectile.gd"):
			seen.append(n.kind)
		elif n is Area3D and n.get_script() == preload("res://scripts/player/fireball.gd"):
			seen.append("fireball")
	world.child_entered_tree.connect(cb)
	return [seen, cb]


func _stop_spawn_watch(w: Array) -> void:
	if world.child_entered_tree.is_connected(w[1]):
		world.child_entered_tree.disconnect(w[1])


func _test_gear() -> void:
	# dados consistentes
	var bad: Array[String] = []
	for id in ItemDB.ITEMS:
		var it: Dictionary = ItemDB.ITEMS[id]
		if it.type in ["weapon", "armor", "gear"] and not ItemDB.SLOTS.has(ItemDB.slot_of(id)):
			bad.append(id)
		for k in it.get("stats", {}):
			if not ItemDB.STAT_NAMES.has(k):
				bad.append("%s.%s" % [id, k])
		if ItemTooltip.build_text(id) == "":
			bad.append(id + " (dica)")
	for id in ItemDB.SHOP_STOCK:
		if not ItemDB.ITEMS.has(id):
			bad.append("loja:" + id)
	for k in Enemy.TYPES:
		for entry in Enemy.TYPES[k].loot:
			if not ItemDB.ITEMS.has(entry[0]):
				bad.append("saque:" + entry[0])
	check(bad.is_empty(), "itens novos consistentes (%d itens) %s" % [ItemDB.ITEMS.size(), bad])

	# cajado: ataque básico dispara projétil arcano
	var dmg_sword := Game.melee_damage()
	Game.equip("apprentice_staff")
	check(Game.equipment.weapon == "apprentice_staff", "equipou cajado")
	await wait(0.05)
	check(Game.weapon_class() == "staff" and player.look["class"] == "staff", "classe da arma: cajado")
	check(player.look.holder != null and is_instance_valid(player.look.holder), "modelo do cajado montado na mão")
	player.attacking = false
	player.combo_window = 0.0
	Game.stamina = Game.max_stamina()
	var bolt_watch := _watch_spawns()
	player._start_swing()
	await wait_until(func(): return "bolt" in bolt_watch[0], 2.0)
	_stop_spawn_watch(bolt_watch)
	check("bolt" in bolt_watch[0], "cajado dispara faísca arcana")
	await wait(0.5)

	# arco: tensionar e soltar
	Game.equip("short_bow")
	check(Game.equipment.weapon == "short_bow", "equipou arco")
	await wait(0.05)
	check(player.look["class"] == "bow" and player.look.arrow != null, "classe da arma: arco (com flecha encaixável)")
	player.attacking = false
	player.drawing = true
	player.draw_t = player.BOW_FULL
	check(player.bow_charge() >= 0.99, "arco totalmente tensionado")
	var arrow_watch := _watch_spawns()
	player.release_arrow()
	await wait_until(func(): return "arrow" in arrow_watch[0], 2.0)
	_stop_spawn_watch(arrow_watch)
	check("arrow" in arrow_watch[0], "arco dispara flecha")
	check(not player.drawing, "soltar encerra a tensão")

	# mão secundária combina com a arma
	Game.add_item("wooden_shield", 1, true)
	var refused := [""]
	var on_res := func(op: String, ok: bool, err: String) -> void:
		if op == "equip" and not ok:
			refused[0] = err
	Econ.result.connect(on_res)
	Game.equip("wooden_shield")
	Econ.result.disconnect(on_res)
	check(refused[0] == "exige_classe" and Game.equipment.offhand == "", "escudo recusado com arco (%s)" % refused[0])
	Game.equip("iron_sword")
	Game.equip("wooden_shield")
	check(Game.equipment.offhand == "wooden_shield", "escudo equipado com espada")
	var shield_mesh := player.model.find_child("Shield", true, false) as MeshInstance3D
	check(shield_mesh == null or shield_mesh.visible, "escudo aparece no modelo")
	Game.equip("apprentice_staff")
	check(Game.equipment.offhand == "" and Game.count_item("wooden_shield") == 1, "trocar para cajado guarda o escudo")
	Game.equip("iron_sword")
	check(is_equal_approx(Game.melee_damage(), dmg_sword), "dano da espada volta ao trocar de volta")

	# armaduras: defesa e bônus somam
	var def0 := Game.defense()
	var hp0 := Game.max_hp()
	Game.add_item("leather_boots", 1, true)
	Game.add_item("life_amulet", 1, true)
	var prev := Game.preview_equip("life_amulet")
	check(prev.get("hp", 0.0) > 0.0, "comparação prevê +vida do amuleto (%+.0f)" % prev.get("hp", 0.0))
	Game.equip("leather_cap")
	Game.equip("leather_boots")
	Game.equip("life_amulet")
	check(Game.defense() > def0, "capuz e botas aumentam a defesa (%.1f -> %.1f)" % [def0, Game.defense()])
	check(Game.max_hp() > hp0 and Game.attr("vit") == Game.attributes.vit + 1, "amuleto dá vida e vitalidade")
	check(Game.speed_multiplier() > 1.0, "botas dão velocidade")
	Game.sort_inventory()
	check(ItemDB.category(Game.inventory[0].id) == "equip", "organizar coloca equipamentos primeiro")

	# telas novas abrem
	world._open_menu(0)
	await wait(0.15)
	var m = world.modal
	check(m != null and m.equip_slots.size() == 8 and m.bag_slots.size() >= 54, "inventário com boneco (8 espaços) e grade")
	check(m.equip_slots.head.item_id == "leather_cap", "boneco mostra o capuz equipado")
	m._show_tab(1)
	await wait(0.05)
	m._show_tab(2)
	await wait(0.05)
	m._close()
	await wait(0.05)
	world.open_shop()
	await wait(0.1)
	check(world.modal != null and world.modal.buy_grid.get_child_count() > 10, "loja mostra a grade de mercadorias")
	world.modal._close()
	await wait(0.05)


## Escolhe cartas de nível enquanto houver; se check_weapon, confere que a arma escolhida subiu.
func _pick_levelups(check_weapon: bool) -> void:
	var first := true
	while world.modal != null and world.modal.get("mode") == "levelup":
		await wait(0.45)
		var m = world.modal
		var idx := 0
		for i in m.choices.size():
			if m.choices[i].type == "weapon":
				idx = i
		var ch: Dictionary = m.choices[idx]
		var sv = world.survival
		var before: int = sv.weapon_levels.get(ch.id, 0) if ch.type == "weapon" else sv.passive_levels.get(ch.id, 0)
		m._pick(idx)
		await wait(0.15)
		if check_weapon and first:
			var after: int = sv.weapon_levels.get(ch.id, 0) if ch.type == "weapon" else sv.passive_levels.get(ch.id, 0)
			check(after == before + 1, "carta escolhida aplicada (%s %d -> %d)" % [ch.id, before, after])
		first = false


func _nearest(kind: String) -> Enemy:
	var best: Enemy = null
	var bd := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.kind == kind and not e.dead:
			var d: float = e.global_position.distance_to(player.global_position)
			if d < bd:
				bd = d
				best = e
	return best


func _count(kind: String) -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.kind == kind:
			n += 1
	return n
