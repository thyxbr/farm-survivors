extends Node
## Teste automatizado da Defesa da Cidade. Rode com:
##   godot --headless --path . res://scenes/colony.tscn -- --colonytest
## Imprime PASS/FAIL para cada verificação e encerra com código 0 (ok) ou 1 (falhas).
## Usa saves próprios (user://colonytest_*.json) e um personagem solo novo (user://colonytest_solo.db, apagado no início).
## O ouro da cidade é o caixa da partida (colony.treasury): o personagem só ganha as recompensas por noite.

var fails := 0
var world: Node
var colony: Colony
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
	for p in [Game.colony_save_path, Game.colony_legacy_char_path]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	await wait(0.6)
	_bind()
	check(world != null and colony != null and player != null, "cena da cidade carregada")
	check(colony.phase == "setup" and colony.hall == null, "começa vazia, esperando a prefeitura")
	# o personagem é o do solo.db (novo neste teste); o ouro da cidade é um caixa à parte
	var char_gold0 := Game.gold
	var char_xp0 := Game.xp + Game.level * 100000
	var fresh := CharState.new_character(Balance.tables)
	check(char_gold0 == fresh.gold and Econ.ensure_solo(), "personagem da cidade é o do solo.db (ouro %d)" % char_gold0)
	check(colony.treasury == ColonyData.START_GOLD, "caixa inicial da cidade %d (%d)" % [ColonyData.START_GOLD, colony.treasury])
	check(colony.buildings().is_empty(), "nenhuma construção no início")

	# --- modo construção e prefeitura
	world.build.set_active(true)
	await wait(0.1)
	check(world.build.selected == "town_hall", "sem prefeitura, o modo construção escolhe a prefeitura")
	check(player.build_lock, "modo construção trava o ataque do jogador")
	check(world.colony_hud.build_panel.visible, "barra de construção aparece")
	check(colony.can_place("house", Vector3(0, 0, -20), 0.0) != "", "não dá para construir casa antes da prefeitura")
	check(colony.can_place("town_hall", Vector3(80, 0, 0), 0.0) != "", "prefeitura fora da clareira é recusada")
	player.global_position = Vector3(0, 0.5, 14)
	var hall := colony.place("town_hall", Vector3(0, 0, -6), 0.0)
	await wait(0.1)
	check(colony.hall == hall and colony.phase == "day", "prefeitura fundada e o dia começa")
	check(colony.pop_cap() == 6, "prefeitura abriga 6 (%d)" % colony.pop_cap())
	check(get_tree().get_nodes_in_group("animals").size() > 0, "animais de caça surgem no mapa")

	# --- regras de posicionamento
	check(colony.can_place("house", Vector3(0, 0, -6), 0.0) != "", "espaço ocupado é recusado")
	check(colony.can_place("house", Vector3(60, 0, -6), 0.0) != "", "fora do raio da cidade é recusado")
	check(colony.can_place("house", Vector3(0, 0, 14), 0.0) != "", "não constrói em cima do jogador")
	check(colony.can_place("house", Vector3(-12, 0, -6), PI / 2) == "", "casa num lugar livre é aceita")
	var g0 := colony.treasury
	colony.place("house", Vector3(-12, 0, -6), PI / 2)
	check(colony.treasury == g0 - 60 and colony.pop_cap() == 11, "casa custa 60 e abriga 5")
	colony.place("farm", Vector3(-14, 0, 8), 0.0)
	colony.place("barracks", Vector3(12, 0, -6), -PI / 2)
	check(colony.count_of("farm") == 1 and colony.army_cap() == 6, "fazenda e quartel construídos")
	colony.treasury = 50
	check(colony.can_place("market", Vector3(12, 0, 8), 0.0).begins_with("Ouro"), "sem ouro, não constrói")
	colony.treasury = 2000

	# --- muros encaixam
	colony.place("wall", Vector3(0, 0, 22), 0.0)
	world.build.select("wall")
	world.build.rot = 0.0
	var snapped: Vector3 = world.build._snap(Vector3(4.6, 0, 22.7), ColonyData.building("wall"))
	check(snapped.distance_to(Vector3(4, 0, 22)) < 0.01, "muro encaixa na ponta do vizinho (%s)" % snapped)
	world.build.set_active(false)
	check(not player.build_lock, "sair do modo construção destrava o ataque")

	# --- economia
	var f := colony.forecast()
	check(f.tax == colony.citizens * 2, "imposto normal = 2 por morador (%d)" % f.tax)
	check(f.food_in == 12 and f.workers == 2, "fazenda produz 12 com 2 trabalhadores")
	check(f.hall == 15, "prefeitura rende 15")

	# --- recrutamento
	var cit := colony.citizens
	g0 = colony.treasury
	check(colony.recruit("soldier") == "", "recruta um soldado")
	check(colony.recruit("archer") == "", "recruta um arqueiro")
	check(colony.recruit("knight") != "", "cavaleiro exige quartel nível 2")
	await wait(0.2)
	check(colony.soldier_count() == 2 and colony.citizens == cit - 2, "soldados saem dos moradores")
	check(colony.treasury == g0 - 150, "recrutar cobra o preço")
	check(colony.salaries() == 11, "salários somam 11/dia")

	# --- torre defende
	var tower := colony.place("archer_tower", Vector3(8, 0, 14), 0.0)
	var e := colony.spawn_enemy("slime", Vector3(8, 0, 30))
	var hp0 := e.hp
	await wait(2.5)
	check(not is_instance_valid(e) or e.dead or e.hp < hp0, "torre de arqueiros acerta o monstro")
	check(colony.upgrade(tower) == "" and tower.level == 2, "torre melhora para o nível 2")

	# --- monstro ataca construção no caminho
	var wall := colony.place("wall", Vector3(-20, 0, 30), 0.0, true)
	var brute := colony.spawn_enemy("goblin_bruto", Vector3(-20, 0, 32))
	brute.hp = 99999.0
	brute.max_hp = 99999.0
	await wait(4.0)
	check(wall.hp < wall.max_hp or wall.dead, "goblin bruto ataca o muro (%d/%d)" % [wall.hp, wall.max_hp])
	if is_instance_valid(brute):
		brute.take_damage(999999, brute.global_position, false)

	# --- regras do modo em grupo (tabelas): elites resistem, cópias custam mais
	var elite := colony.spawn_enemy("goblin", Vector3(30, 0, 40), -1.0, "blindado")
	check(elite.affix == "blindado" and is_equal_approx(elite.resist_mult("arrow"), 0.5) and elite.resist_mult("ball") == 1.0,
		"elite Blindado resiste a flechas e não a canhão")
	check(elite.max_hp > 80.0 * (1.0 + 0.12 * (colony.day - 1)) * 1.2, "elite tem mais vida (%d)" % elite.max_hp)
	elite.take_damage(999999, elite.global_position, false)
	check(ColonyData.coop_cost("house", 0) == 60 and ColonyData.coop_cost("house", 5) == 90, "em grupo a 6ª casa custa 90")
	check(ColonyData.coop_hp_mult(20) > ColonyData.coop_hp_mult(10) * 2.0, "vida dos monstros acelera no fim de jogo")
	check(ColonyData.chest_rarities(20)[0][0] == "legendary", "baú da noite 20 pode ser lendário")

	# --- reparo e demolição
	if is_instance_valid(wall) and not wall.dead:
		var rc := colony.repair_cost(wall)
		check(rc > 0 and colony.repair(wall) == "" and wall.hp == wall.max_hp, "reparo restaura a vida (%d ouro)" % rc)
		g0 = colony.treasury
		colony.demolish(wall)
		check(colony.treasury == g0 + int(wall.invested * 0.5), "demolir devolve metade")

	# --- caça
	var food0 := colony.food
	g0 = colony.treasury
	var deer: ColonyAnimal = load("res://scripts/colony/animal.gd").new()
	deer.kind = "deer"
	deer.colony = colony
	deer.position = player.global_position + Vector3(3, 0.3, 0)
	colony.add_child(deer)
	await wait(0.1)
	player.model.rotation.y = PI / 2
	player.look["class"] = "sword"
	deer.take_damage(9999, player.global_position, false)
	check(colony.food == food0 + 10 and colony.treasury == g0 + 9, "caçar um cervo rende comida e ouro")

	# --- amanhecer: economia
	f = colony.forecast()
	g0 = colony.treasury
	var day0 := colony.day
	colony.dawn()
	check(colony.day == day0 + 1, "amanhece um novo dia")
	check(colony.treasury == g0 + f.gold_net, "amanhecer aplica impostos e salários (%d -> %d)" % [g0, colony.treasury])
	# salários (3 cavaleiros + 2 = 47/dia) maiores que a renda (só a prefeitura, 15): alguns desertam
	for i in 3:
		colony.spawn_soldier("knight", Vector3(12, 0, 2))
	await wait(0.1)
	var before := colony.soldier_count()
	var cit_s := colony.citizens
	colony.citizens = 0
	colony.treasury = 0
	colony.dawn()
	await wait(0.1)
	check(colony.soldier_count() < before and colony.treasury >= 0, "sem ouro para salários, soldados desertam (%d -> %d)" % [before, colony.soldier_count()])
	for s in colony.soldiers():
		s.leave()
	colony.citizens = cit_s
	colony.treasury = 2000
	colony.recruit("militia")
	colony.recruit("soldier")

	# --- noite e onda
	colony.start_night()
	check(colony.phase == "night" and colony.wave_total > 0, "a noite traz uma onda (%d monstros)" % colony.wave_total)
	await wait(4.0)
	check(colony.siege_alive() > 0, "monstros da onda surgem (%d)" % colony.siege_alive())
	var marching := false
	for c in colony.get_children():
		if c is Enemy and c.siege and not c.dead and c._siege_target != null:
			marching = true
	check(marching, "monstros da onda escolhem um alvo na cidade")
	var d0 := colony.day
	for i in 30:
		colony.wave_queue.clear()
		for c in colony.get_children():
			if c is Enemy and not c.dead:
				c.take_damage(999999, c.global_position, false)
		await wait(0.3)
		if colony.phase == "day":
			break
	await wait(3.0)
	check(colony.phase == "day" and colony.day == d0 + 1, "onda derrotada: amanhece (dia %d)" % colony.day)
	# o personagem: construções, recrutas, caça e saques não mexem no ouro dele; só a recompensa da noite
	var rw := ColonyData.night_reward(d0)
	check(int(colony.run_rewards.gold) == int(rw.gold) and int(colony.run_rewards.xp) == int(rw.xp),
		"recompensa da noite %d somada na partida (%s)" % [d0, str(colony.run_rewards)])
	check(Game.gold == char_gold0 + int(rw.gold),
		"ouro do personagem só muda pela recompensa da noite (%d → %d, +%d)" % [char_gold0, Game.gold, rw.gold])
	check(Game.xp + Game.level * 100000 > char_xp0, "XP da noite (e dos abates) no personagem")
	check(int(Game.flags.get("city_best", 0)) == d0, "melhor noite salva no personagem (%s)" % str(Game.flags.get("city_best")))

	# --- salvar e carregar
	var nb := colony.buildings().size()
	var ns := colony.soldier_count()
	var day_s := colony.day
	var gold_s := colony.treasury
	check(world.save_colony(), "salva a cidade")
	check(Game.has_colony_save(), "arquivo de save existe")
	Game.start_colony(true)
	await wait(1.0)
	_bind()
	check(colony.buildings().size() == nb, "carrega as construções (%d)" % colony.buildings().size())
	check(colony.soldier_count() == ns, "carrega o exército (%d)" % colony.soldier_count())
	check(colony.day == day_s and colony.treasury == gold_s, "carrega dia e caixa da cidade (%d)" % colony.treasury)
	check(int(colony.run_rewards.gold) == int(rw.gold), "recompensas da partida voltam com o save")
	check(Game.gold == char_gold0 + int(rw.gold), "carregar a cidade não mexe no personagem (%d)" % Game.gold)
	check(not FileAccess.file_exists(Game.colony_legacy_char_path), "sem save de personagem da cidade")
	check(colony.phase == "day" and colony.hall != null, "cidade carregada de dia")

	# save de uma versão antiga (sem caixa; o ouro estava no personagem do modo): o caixa vem de lá e o
	# arquivo antigo some no próximo save
	var sf := FileAccess.open(Game.colony_save_path, FileAccess.READ)
	var old: Dictionary = JSON.parse_string(sf.get_as_text())
	sf.close()
	old.erase("treasury")
	sf = FileAccess.open(Game.colony_save_path, FileAccess.WRITE)
	sf.store_string(JSON.stringify(old))
	sf.close()
	sf = FileAccess.open(Game.colony_legacy_char_path, FileAccess.WRITE)
	sf.store_string(JSON.stringify({"gold": 777, "level": 3}))
	sf.close()
	Game.start_colony(true)
	await wait(1.0)
	_bind()
	check(colony.treasury == 777 and Game.gold == char_gold0 + int(rw.gold), "save antigo: caixa vem do personagem do modo (%d), personagem intacto" % colony.treasury)
	check(world.save_colony() and not FileAccess.file_exists(Game.colony_legacy_char_path), "save antigo some no próximo save")

	# --- derrota
	colony.hall.take_damage(999999, Vector3.ZERO)
	check(colony.phase == "over", "prefeitura destruída = derrota")
	await wait(3.0)
	check(world.modal != null and world.modal.get("mode") == "defeat", "tela de derrota aparece")
	# uma linha de resumo da partida no registro da economia (as recompensas da noite não têm linha própria)
	var rows: Array = Econ._db.query("SELECT amount, detail FROM economy_log WHERE account_id = ? AND kind = 'run' AND source = 'city'",
		[CharacterService.SOLO_ACCOUNT])
	check(rows.size() == 1 and int(rows[0].amount) == int(rw.gold), "resumo da partida na economia (%s)" % str(rows))
	var nights_rows: Array = Econ._db.query("SELECT 1 FROM economy_log WHERE account_id = ? AND source = 'city_night'",
		[CharacterService.SOLO_ACCOUNT])
	check(nights_rows.is_empty(), "recompensa da noite sem linha própria")
	check(Game.gold == char_gold0 + int(rw.gold), "fim da partida: o caixa da cidade some, o personagem fica com a recompensa (%d)" % Game.gold)

	print("\n%s — %d falha(s)" % ["OK" if fails == 0 else "FALHOU", fails])
	get_tree().quit(1 if fails > 0 else 0)


func _bind() -> void:
	world = get_tree().current_scene
	colony = world.get("colony") if world else null
	player = get_tree().get_first_node_in_group("player")
