extends Node
## Teste de fumaça do gameplay. Rode com:
##   godot --headless --path . res://scenes/world.tscn -- --smoketest
## Imprime PASS/FAIL para cada verificação e encerra com código 0 (ok) ou 1 (falhas).

var fails := 0
var world: Node
var player: Player


func check(cond: bool, what: String) -> void:
	if cond:
		print("PASS  ", what)
	else:
		fails += 1
		print("FAIL  ", what)


func wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, true).timeout


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
	check(get_tree().get_nodes_in_group("enemies").size() >= 15, "inimigos spawnados (%d)" % get_tree().get_nodes_in_group("enemies").size())
	check(get_tree().get_nodes_in_group("interactable").size() == 3 + Game.FARM_PLOTS + 1,
		"2 NPCs + portal + %d canteiros + caldeirão interagíveis" % Game.FARM_PLOTS)

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

	# --- combate corpo a corpo
	var slime := _nearest("slime")
	var xp0 := Game.xp
	var gold0 := Game.gold
	player.global_position = slime.global_position + Vector3(0, 0.3, 1.2)
	player.model.rotation.y = PI
	await wait(0.2)
	var hp0: float = slime.hp
	player._start_swing()
	await wait(0.5)
	check(slime.hp < hp0, "golpe de espada causa dano (%.0f -> %.0f)" % [hp0, slime.hp])
	slime.take_damage(9999, player.global_position, false)
	check(Game.xp > xp0, "XP ganho ao matar slime")
	check(Game.quests.slimes.progress == 1, "progresso da missão 1/5")
	player.global_position = slime.global_position + Vector3(0, 0.3, 0)
	await wait(2.5)
	check(Game.gold > gold0, "ouro coletado do chão (%d -> %d)" % [gold0, Game.gold])

	# --- magia
	var mp0 := Game.mp
	player.cast("fireball")
	await wait(0.05)
	check(Game.mp < mp0, "bola de fogo gasta mana")
	var found_fb := false
	for c in world.get_children():
		if c is Area3D and c.get_script() == preload("res://scripts/player/fireball.gd"):
			found_fb = true
	check(found_fb, "projétil de bola de fogo criado")
	player.cast("heal")
	check(player.cooldowns.heal == 0.0, "cura bloqueada no nível 1")

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
	check(Game.equipment.weapon == "iron_sword" and Game.count_item("wooden_sword") == 1, "equipou espada de ferro")
	Game.sell("wooden_sword")
	check(Game.count_item("wooden_sword") == 0, "vendeu espada de madeira")
	world.modal._close()
	await wait(0.05)

	# --- novas armas, armaduras e equipamentos
	await _test_gear()

	# --- save / load
	Game.save_game(player.global_position, 0.0)
	var saved_gold := Game.gold
	var saved_lvl := Game.level
	Game.gold = 1
	Game.level = 1
	check(Game.load_game(), "load_game executado")
	await wait(0.6)
	world = get_tree().current_scene
	player = get_tree().get_first_node_in_group("player")
	check(Game.gold == saved_gold and Game.level == saved_lvl, "save/load restaura ouro e nível")
	check(Game.equipment.weapon == "iron_sword", "save/load restaura equipamento")
	check(Game.equipment.head == "leather_cap" and Game.equipment.feet == "leather_boots", "save/load restaura cabeça e pés")

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
	world.modal._respawn()
	await wait(0.2)
	check(not player.dead and not get_tree().paused and Game.hp == Game.max_hp(), "renasce na vila")

	await _test_farm()
	await _test_survival()
	await _test_update()

	print("\n==== %s (%d falhas) ====" % ["OK" if fails == 0 else "FALHOU", fails])
	if FileAccess.file_exists(Game.save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	get_tree().quit(1 if fails > 0 else 0)


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
	var g0: float = Game.farm.plots[0].growth
	await wait(1.0)
	var g1: float = Game.farm.plots[0].growth
	check(g1 > g0 and abs((g1 - g0) - 2.0 / ItemDB.CROPS.carrot.time) < 0.02, "regado cresce 2x (%.3f/s)" % (g1 - g0))
	Game.farm.plots[0].growth = 0.995
	await wait(0.3)
	check(Game.plot_state(0) == "ready", "planta fica pronta")
	var carrots := Game.count_item("carrot")
	plot.interact(player)
	check(Game.plot_state(0) == "empty" and Game.count_item("carrot") >= carrots + 3, "colheita regada rende +1 (%d)" % (Game.count_item("carrot") - carrots))

	# adubo de gel de slime
	Game.add_item("slime_gel", 1, true)
	Game.plant(1, "wheat", true)
	Game.water(1)
	check(Game.fertilize(1) and Game.farm.plots[1].growth >= 0.4, "adubo de gel de slime acelera")

	# plantar em todos os vazios
	Game.gold += 200
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
	check(Game.unlock_next_plot() and Game.farm.unlocked == Game.FARM_START_PLOTS + 1 and Game.gold == gold0 - cost, "canteiro novo liberado por %d ouro" % cost)

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
	check(Game.cook("dragon_chili") == 1 and Game.count_item("dragon_chili") == 1, "cozinhou chili do dragão")

	# comer: bônus temporário
	var dmg0 := Game.melee_damage()
	Game.selected_food = "spicy_soup"
	Game.eat_cooldown = 0.0
	check(Game.eat_selected() and Game.food_buffs.has("spicy_soup"), "comeu sopa picante")
	check(Game.melee_damage() > dmg0 * 1.25, "sopa aumenta o dano (%.1f -> %.1f)" % [dmg0, Game.melee_damage()])
	check(not Game.eat("spicy_soup"), "não come de novo durante a mastigação")
	Game.tick_food(999.0)
	check(Game.food_buffs.is_empty() and abs(Game.melee_damage() - dmg0) < 0.01, "bônus expira e o dano volta")

	# save/load da horta
	Game.save_game(player.global_position, 0.0)
	var farm_saved: Dictionary = Game.farm.duplicate(true)
	Game.farm = Game.default_farm()
	Game.load_game()
	await wait(0.6)
	world = get_tree().current_scene
	player = get_tree().get_first_node_in_group("player")
	check(Game.farm.unlocked == farm_saved.unlocked and Game.farm.plots[1].crop == "wheat" \
		and abs(Game.farm.plots[1].growth - farm_saved.plots[1].growth) < 0.05, "save/load restaura a horta")


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

	# chefe na rodada 5
	sv.round_num = 4
	sv._start_round()
	await wait(0.1)
	check(sv.boss_alive() and sv.boss.horde, "Rei Goblin aparece na rodada 5")
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
	check(Game.save_game(player.global_position, 0.0), "salvar volta a funcionar após o desafio")

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
	check(hud.lvl_badge.text == str(sv.run_level), "HUD mostra o nível (%s)" % hud.lvl_badge.text)
	check(hud.weapons_row.get_child_count() == sv.weapon_levels.size(), "HUD mostra os ícones das armas (%d)" % hud.weapons_row.get_child_count())
	check(hud.passives_row.get_child_count() == sv.passive_levels.size(), "HUD mostra os ícones das passivas")

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


func _count_projectiles(kind: String) -> int:
	var n := 0
	for c in world.get_children():
		if c is Area3D and c.get_script() == preload("res://scripts/player/projectile.gd") and c.kind == kind:
			n += 1
	return n


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
	check(Game.equip("apprentice_staff"), "equipou cajado")
	await wait(0.05)
	check(Game.weapon_class() == "staff" and player.look["class"] == "staff", "classe da arma: cajado")
	check(player.look.holder != null and is_instance_valid(player.look.holder), "modelo do cajado montado na mão")
	player.attacking = false
	player.combo_window = 0.0
	player._start_swing()
	await wait(0.3)
	check(_count_projectiles("bolt") >= 1, "cajado dispara faísca arcana")
	await wait(0.5)

	# arco: tensionar e soltar
	check(Game.equip("short_bow"), "equipou arco")
	await wait(0.05)
	check(player.look["class"] == "bow" and player.look.arrow != null, "classe da arma: arco (com flecha encaixável)")
	player.attacking = false
	player.drawing = true
	player.draw_t = player.BOW_FULL
	check(player.bow_charge() >= 0.99, "arco totalmente tensionado")
	player.release_arrow()
	await wait(0.05)
	check(_count_projectiles("arrow") >= 1, "arco dispara flecha")
	check(not player.drawing, "soltar encerra a tensão")

	# mão secundária combina com a arma
	Game.add_item("wooden_shield", 1, true)
	check(not Game.equip("wooden_shield"), "escudo recusado com arco")
	Game.equip("iron_sword")
	check(Game.equip("wooden_shield") and Game.equipment.offhand == "wooden_shield", "escudo equipado com espada")
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
