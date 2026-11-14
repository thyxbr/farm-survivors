extends Node
## Teste automatizado da Defesa da Cidade. Rode com:
##   godot --headless --path . res://scenes/colony.tscn -- --colonytest
## Imprime PASS/FAIL para cada verificação e encerra com código 0 (ok) ou 1 (falhas).
## Usa saves próprios (user://colonytest_*.json).

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
	for p in [Game.colony_save_path, Game.colony_char_path]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	await wait(0.6)
	_bind()
	check(world != null and colony != null and player != null, "cena da cidade carregada")
	check(colony.phase == "setup" and colony.hall == null, "começa vazia, esperando a prefeitura")
	check(Game.gold == ColonyData.START_GOLD, "ouro inicial %d" % Game.gold)
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
	# --- eras: a era é o nível da prefeitura
	check(colony.era() == 1 and colony.advance_era().begins_with("Exige"), "era II exige serraria e pedreira")
	check(colony.can_place("cannon_tower", Vector3(14, 0, 14), 0.0).contains("era"), "torre de canhão exige era II")
	check(colony.can_place("mage_tower", Vector3(14, 0, 14), 0.0).contains("era"), "torre arcana exige era II")
	check(ColonyData.era_cost(2, 1) == {"food": 250, "wood": 250, "stone": 150, "gold": 200}, "custo da era II")
	check(ColonyData.era_cost(2, 3).gold == int(round(200 * 1.7)) and ColonyData.era_cost(3, 1).crystal == 20,
		"em grupo a era custa +35%% por jogador extra")
	check(ColonyData.TECHS.size() == 11, "11 pesquisas na tabela")

	# --- regras de posicionamento
	check(colony.can_place("house", Vector3(0, 0, -6), 0.0) != "", "espaço ocupado é recusado")
	check(colony.can_place("house", Vector3(60, 0, -6), 0.0) != "", "fora do raio da cidade é recusado")
	check(colony.can_place("house", Vector3(0, 0, 14), 0.0) != "", "não constrói em cima do jogador")
	check(colony.can_place("house", Vector3(-12, 0, -6), PI / 2) == "", "casa num lugar livre é aceita")
	var g0 := Game.gold
	var w0 := colony.amount("wood")
	var house_cost: Dictionary = ColonyData.BUILDINGS.house.cost
	check(colony.amount("wood") == int(ColonyData.START_RES.wood) and colony.amount("stone") == int(ColonyData.START_RES.stone),
		"estoque inicial de madeira e pedra")
	colony.place("house", Vector3(-12, 0, -6), PI / 2)
	check(Game.gold == g0 - int(house_cost.gold) and colony.amount("wood") == w0 - int(house_cost.wood) and colony.pop_cap() == 11,
		"casa custa ouro e madeira e abriga 5")
	colony.res["wood"] = 2000   # o estoque inicial não cobre a cidade toda
	colony.res["stone"] = 2000
	colony.place("farm", Vector3(-14, 0, 8), 0.0)
	colony.place("barracks", Vector3(12, 0, -6), -PI / 2)
	check(colony.count_of("farm") == 1 and colony.army_cap() == 6, "fazenda e quartel construídos")
	Game.gold = 2000
	colony.res["stone"] = 0
	var need_stone := int(ColonyData.BUILDINGS.market.cost.stone)
	check(colony.can_place("market", Vector3(12, 0, 8), 0.0) == "Faltam %d de Pedra." % need_stone, "sem pedra, não constrói")
	check(not colony.pay({"stone": 5}) and colony.amount("stone") == 0, "pagar sem ter não deixa negativo")
	var w1 := colony.amount("wood")
	check(not colony.pay({"wood": 5, "stone": 5}) and colony.amount("wood") == w1, "pagamento é atômico: sem pedra, a madeira fica")
	check(colony.missing({"gold": Game.gold + 10, "stone": 3}) == "Faltam 10 de Ouro, 3 de Pedra.", "lista tudo o que falta")
	check(colony.place("market", Vector3(12, 0, 8), 0.0) == null and colony.count_of("market") == 0, "place sem recurso não constrói nem cobra")
	colony.res["stone"] = 2000
	colony.res["wood"] = 2000
	check(colony.upgrade_cost(colony.hall) == ColonyData.era_cost(2, 1), "melhorar a prefeitura = custo da era II")
	check(ColonyData.upgrade_cost("house", 2).has("iron") and not ColonyData.upgrade_cost("house", 1).has("iron"), "melhoria para o nível 3 pede ferro")
	# o servidor recusa pedidos sem recurso (net_request roda o mesmo caminho do servidor; aqui chamado no solo,
	# porque place/upgrade/repair não dependem do papel). Nada pode ficar negativo nem mudar.
	var bk: ColonyBuilding = colony.buildings().filter(func(x): return x.kind == "barracks")[0]
	colony.bmap[999] = bk
	colony.res["stone"] = 0
	Game.gold = 2000
	var wood_r := colony.amount("wood")
	var nb0 := colony.buildings().size()
	var err_p: String = colony.net_request(1, "place", ["market", 12.0, 8.0, 0.0])
	check(err_p == "Faltam %d de Pedra." % need_stone and colony.buildings().size() == nb0 and colony.amount("stone") == 0
		and Game.gold == 2000 and colony.amount("wood") == wood_r, "servidor recusa construção sem pedra e não cobra nada")
	var err_u: String = colony.net_request(1, "upgrade", [999])
	check(err_u.contains("era") and bk.level == 1 and colony.amount("stone") == 0
		and Game.gold == 2000 and colony.amount("wood") == wood_r, "servidor recusa melhoria acima da era (%s)" % err_u)
	var hp_bk := bk.hp
	bk.hp = bk.max_hp * 0.5
	var err_r: String = colony.net_request(1, "repair", [999])
	check(err_r.begins_with("Faltam ") and bk.hp == bk.max_hp * 0.5 and colony.amount("stone") == 0 and Game.gold == 2000,
		"servidor recusa reparo sem recurso (%s)" % err_r)
	var err_ra: String = colony.net_request(1, "repair_all", [])
	check(err_ra.begins_with("Faltam ") and colony.amount("stone") == 0 and Game.gold == 2000, "servidor recusa reparar tudo sem recurso")
	bk.hp = hp_bk
	colony.bmap.erase(999)
	colony.res["stone"] = 2000
	var sc := ColonyData.scale_cost({"gold": 30, "wood": 40}, 1.5)
	check(sc.gold == 45 and sc.wood == 60, "scale_cost multiplica cada recurso")

	# --- aldeões livres e ocupados, treino na prefeitura
	colony.citizens = 6
	colony.food = 200
	var free0 := colony.free_villagers()
	var farm2 := colony.place("farm", Vector3(-24, 0, 6), 0.0)
	check(farm2 != null and colony.free_villagers() == free0 - int(ColonyData.BUILDINGS.farm.crew), "fazenda ocupa %d aldeões" % int(ColonyData.BUILDINGS.farm.crew))
	colony.citizens = colony.busy() + 1
	check(colony.can_place("market", Vector3(12, 0, 8), 0.0) == "Faltam 1 aldeão livre.", "sem aldeões livres, não constrói")
	colony.citizens = colony.busy()
	check(colony.can_place("market", Vector3(12, 0, 8), 0.0) == "Faltam 2 aldeões livres.", "mensagem no plural")
	colony.citizens = colony.pop_cap() - 1
	var c0 := colony.citizens
	var food_t := colony.food
	check(colony.train_villager() == "" and colony.food == food_t - int(ColonyData.VILLAGER_COST.food), "treinar aldeão custa comida")
	check(colony.train_queue == 1, "aldeão entra na fila")
	await wait(ColonyData.VILLAGER_TIME + 0.5)
	check(colony.citizens == c0 + 1 and colony.train_queue == 0, "aldeão treinado em %d s" % int(ColonyData.VILLAGER_TIME))
	check(colony.train_villager() != "" and colony.food == food_t - int(ColonyData.VILLAGER_COST.food), "sem moradia, não treina nem cobra")
	colony.citizens = 0
	colony.food = int(ColonyData.VILLAGER_COST.food) - 1
	check(colony.train_villager().begins_with("Faltam "), "sem comida, não treina")
	colony.food = 200
	colony.citizens = colony.pop_cap() - 1
	check(colony.net_request(1, "train", []) == "" and colony.train_queue == 1 and colony.net_state().tq == 1, "pedido \"train\" entra na fila e vai no estado")
	colony.train_queue = 0
	colony.food = 200
	# fome deixa ocupados > aldeões: produção proporcional, nunca negativa
	colony.citizens = 1
	check(colony.free_villagers() == 0 and colony.staffing() > 0.0 and colony.staffing() < 1.0, "falta de aldeões reduz produção sem ficar negativo")
	check(colony.forecast().food_in >= 0 and colony.crew_eff(farm2) == colony.staffing(), "previsão nunca negativa")
	colony.citizens = 0
	check(colony.staffing() == 0.0 and colony.free_villagers() == 0, "sem aldeões: eficiência 0 e livres 0")
	check(ColonyData.tower_rate_mult(1.0) == 1.0 and ColonyData.tower_rate_mult(0.4) == 1.5, "torre sem operador atira mais devagar")
	# dawn: sem crescimento automático
	colony.citizens = 4
	var cz := colony.citizens
	colony.dawn()
	check(colony.citizens == cz, "aldeões não nascem sozinhos no amanhecer")
	colony.demolish(farm2)
	colony.citizens = 5

	# --- nós de recurso: coleta, esgotamento e volta
	check(world.map_seed == 7731, "teste usa semente fixa")
	var tree := colony.nature.nearest("tree", player.global_position)
	var wt0 := colony.amount("wood")
	for i in 4:
		colony.harvest(tree.id, player.global_position)
	check(colony.amount("wood") == wt0 + 24 and not tree.alive, "árvore dá 24 madeira em 4 golpes e cai")
	check(not _obstacle_at(tree.global_position), "árvore caída sai dos obstáculos")
	check(not tree.is_in_group("enemies") and tree.is_in_group("harvest"), "nó fica no grupo harvest, fora de enemies")
	colony.day += 2
	colony.nature.regrow(colony.day)
	check(tree.alive and _obstacle_at(tree.global_position), "árvore volta em 2 dias")
	# construção em cima do lugar: o nó espera e tenta de novo no próximo amanhecer
	for i in 4:
		colony.harvest(tree.id, player.global_position)
	var blocker := colony.place("wall", tree.global_position, 0.0, true)   # grátis; testa só a sobreposição
	colony.day += 2
	colony.nature.regrow(colony.day)
	check(not tree.alive, "nó não volta dentro de uma construção")
	colony.demolish(blocker)
	var keep := [colony.citizens, colony.food, Game.gold, colony.res.duplicate()]
	colony.dawn()
	check(tree.alive, "o amanhecer tenta de novo e o nó volta")
	colony.citizens = keep[0]
	colony.food = keep[1]
	Game.gold = keep[2]
	colony.res = keep[3]
	colony.day -= 5   # o resto do teste conta os dias a partir daqui
	check(colony.nature.count("crystal") == 6 and colony.nature.count("iron") == 7, "anéis externos têm cristal e ferro")
	check(colony.nature.count("gold") == 4 and colony.nature.count("berry") == 10, "veios de ouro e arbustos de frutas")
	var cr := colony.nature.nearest("crystal", Vector3.ZERO)
	check(Vector2(cr.global_position.x, cr.global_position.z).length() >= 105.0, "cristal só no anel 3")
	var ir := colony.nature.nearest("iron", Vector3.ZERO)
	check(Vector2(ir.global_position.x, ir.global_position.z).length() >= 80.0, "ferro no anel 2")
	var cry0 := colony.amount("crystal")
	for i in 6:
		colony.harvest(cr.id, player.global_position)
	check(colony.amount("crystal") == cry0 + 8 and not cr.alive, "cristal dá 8 em 6 golpes, sem perder o resto")
	var berry := colony.nature.nearest("berry", Vector3.ZERO)
	var fd0 := colony.food
	colony.harvest(berry.id, player.global_position)
	check(colony.food == fd0 + 12 and not berry.alive, "arbusto dá 12 comida de uma vez")
	var rock := colony.nature.nearest("rock", player.global_position)
	var st0 := colony.amount("stone")
	rock.hit(player.global_position)
	rock.hit(player.global_position)
	check(colony.amount("stone") == st0 + 5, "golpe duplo no mesmo instante tira só um pedaço")
	var cr_id := cr.id
	var nd: Dictionary = colony.to_dict().get("nodes", {})
	check(nd.has(str(cr.id)) and nd.has(str(berry.id)) and int(colony.to_dict().get("seed", -1)) == 7731, "save guarda semente e nós esgotados")

	# --- serraria e pedreira: produção contínua do bosque em volta
	var keep_cp := [colony.citizens, Game.gold, colony.res.duplicate()]
	colony.citizens = colony.busy() + 6   # a serraria e a pedreira ocupam 3 aldeões cada
	Game.gold += 200
	colony.res["wood"] = int(colony.res.get("wood", 0)) + 200
	var spot := _camp_spot("tree")
	check(spot != Vector3.INF, "há um bosque a ~60 m do centro para a serraria")
	check(colony.can_place("lumber_camp", spot, 0.0) == "", "serraria pode ficar fora da cidade perto do bosque (%s)" % colony.can_place("lumber_camp", spot, 0.0))
	check(colony.can_place("lumber_camp", Vector3(0, 0, 20), 0.0) != "", "serraria longe de árvores é recusada")
	check(colony.can_place("lumber_camp", spot * 1.6, 0.0) != "", "serraria além de 80 m é recusada")
	check(colony.can_place("house", spot, 0.0) != "", "casa continua restrita ao raio da cidade")
	var camp := colony.place("lumber_camp", spot, 0.0)
	check(camp != null and colony.free_villagers() >= 0, "serraria construída")
	var wc0 := colony.amount("wood")
	var live0 := colony.nature.alive_near("tree", spot, 14.0).size()
	colony._gather_tick(30.0)
	check(colony.amount("wood") > wc0 + 10, "serraria produz madeira de dia (%d, eff %.2f, nós %d)" % [colony.amount("wood") - wc0, colony.staffing(), live0])
	colony._gather_tick(60.0)
	check(colony.nature.alive_near("tree", spot, 14.0).size() < live0, "serraria consome o bosque (%d -> %d)" % [live0, colony.nature.alive_near("tree", spot, 14.0).size()])
	check(ColonyData.gather_rate(1.0, 2, 1.0) < ColonyData.gather_rate(1.0, 8, 1.0), "bosque ralo produz menos")
	check(ColonyData.gather_rate(1.0, 0, 1.0) == 0.0 and ColonyData.gather_rate(0.0, 8, 1.0) == 0.0, "sem árvore ou sem aldeão não produz")
	check(colony.gather_per_min().wood > 0.0 and colony.gather_per_min().stone == 0.0, "previsão por minuto: só madeira")
	var qspot := _camp_spot("rock")
	check(qspot != Vector3.INF and colony.can_place("quarry", qspot, 0.0) == "", "pedreira pode ficar perto das pedras")
	if qspot == Vector3.INF:
		fails += 1
		qspot = Vector3(0, 0, 20)   # sem afloramento livre: o resto do bloco falha mas não quebra
	var quarry := colony.place("quarry", qspot, 0.0)
	var sq0 := colony.amount("stone")
	colony._gather_tick(30.0)
	check(quarry != null and colony.amount("stone") > sq0 + 5, "pedreira produz pedra (%d)" % (colony.amount("stone") - sq0))
	var wn := colony.amount("wood")
	colony.phase = "night"
	colony._gather_tick(30.0)
	colony.phase = "day"
	check(colony.amount("wood") == wn, "de noite não produz")
	colony.demolish(camp)
	colony.demolish(quarry)
	colony.citizens = keep_cp[0]
	Game.gold = keep_cp[1]
	colony.res = keep_cp[2]

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
	check(f.food_in == 12 and f.workers == colony.busy(), "fazenda produz 12 com todos os aldeões")
	check(f.hall == 15, "prefeitura rende 15")

	# --- recrutamento
	var cit := colony.citizens
	g0 = Game.gold
	check(colony.recruit("soldier") == "", "recruta um soldado")
	check(colony.recruit("archer") == "", "recruta um arqueiro")
	check(colony.recruit("knight").contains("era"), "cavaleiro exige a era II")
	await wait(0.2)
	check(colony.soldier_count() == 2 and colony.citizens == cit - 2, "soldados saem dos moradores")
	colony.citizens += 2   # a torre abaixo precisa de um aldeão livre
	check(Game.gold == g0 - 150, "recrutar cobra o preço")
	check(colony.salaries() == 11, "salários somam 11/dia")

	# --- eras e pesquisas
	var keep_era := [colony.citizens, Game.gold, colony.food, colony.res.duplicate()]
	var camp2 := colony.place("lumber_camp", spot, 0.0, true)
	var quarry2 := colony.place("quarry", qspot, 0.0, true)
	Game.gold = 0
	colony.food = 1000
	for r in ["wood", "stone", "iron", "crystal"]:
		colony.res[r] = 1000
	var err_e: String = colony.net_request(1, "era", [])
	check(err_e == "Faltam 200 de Ouro." and colony.food == 1000 and colony.amount("wood") == 1000 and colony.busy_t.is_empty()
		and colony.era() == 1, "servidor recusa avançar de era sem ouro e não cobra nada (%s)" % err_e)
	Game.gold = 5000
	colony.citizens = colony.pop_cap() - 1
	check(colony.train_villager() == "", "aldeão na fila antes de avançar de era")
	check(colony.advance_era() == "", "avança para a era II")
	check(colony.advance_era() != "" and colony.net_state().busy.has(colony.hall.net_id), "avanço em andamento vai no estado e não repete")
	await wait(ColonyData.VILLAGER_TIME + 1.0)
	check(colony.train_queue == 1 and colony.era() == 1, "a prefeitura não treina enquanto avança de era")
	await wait(ColonyData.ERA_TIME - ColonyData.VILLAGER_TIME - 0.5)
	check(colony.era() == 2 and colony.hall.level == 2, "era II = prefeitura nível 2")
	check(colony.busy_t.is_empty(), "prefeitura livre depois da era")
	var r0 := ColonyData.gather_rate(1.0, 8, colony.mult("wood"))
	check(colony.research("sharp_axe") == "", "pesquisa Machado Afiado")
	check(colony.research("sharp_axe") != "", "a mesma pesquisa não começa duas vezes")
	# Alvenaria é pesquisada na prefeitura: o treino de aldeões não pode parar por isso
	var hmax := colony.hall.max_hp
	var hhp := colony.hall.hp
	var wl := colony.place("wall", Vector3(-20, 0, 26), 0.0, true)
	var wmax := wl.max_hp
	check(colony.research("masonry") == "" and colony.train_queue == 1, "Alvenaria começa na prefeitura com um aldeão na fila")
	check(colony.advance_era() == "A prefeitura está ocupada com outra ação.", "pesquisa na prefeitura não se confunde com avanço de era")
	await wait(ColonyData.TECH_TIME + 0.5)
	check(colony.train_queue == 0, "o treino anda enquanto a prefeitura pesquisa")
	check(is_equal_approx(ColonyData.gather_rate(1.0, 8, colony.mult("wood")), r0 * 1.2), "Machado Afiado dá +20% madeira")
	check(colony.research("sharp_axe") != "", "pesquisa não se compra duas vezes")
	check(colony.research("arcane_focus").contains("era"), "pesquisa da era III bloqueada na era II")
	check(colony.count_of("farm") > 0, "há uma fazenda para o Arado")
	check(colony.research("plow") == "", "pesquisa do Arado começa na fazenda")
	var live_tree := colony.nature.nearest("tree", player.global_position)
	var wh0 := colony.amount("wood")
	for i in 4:
		colony.harvest(live_tree.id, player.global_position)
	check(colony.amount("wood") > wh0 + 24, "Machado Afiado vale para o jogador (%d)" % (colony.amount("wood") - wh0))
	# pesquisas que mexem na vida: as construções que já existem crescem junto
	check(colony.has_tech("masonry") and is_equal_approx(colony.hall.max_hp, hmax * 1.2) and is_equal_approx(colony.hall.hp, hhp + hmax * 0.2)
		and is_equal_approx(wl.max_hp, wmax * 1.2), "Alvenaria: +20% de vida nas construções existentes")
	colony._finish_tech("reinforced_wall")
	check(is_equal_approx(wl.max_hp, wmax * 1.2 * 1.4) and is_equal_approx(colony.hall.max_hp, hmax * 1.2), "Muralha Reforçada: só muros e portões +40%")
	colony.demolish(wl)
	var sol: ColonySoldier = colony.soldiers()[0]
	var smax := sol.max_hp
	colony._finish_tech("elite_training")
	check(is_equal_approx(sol.max_hp, smax * 1.15) and is_equal_approx(sol.unit_damage(), float(sol.data.damage) * 1.15),
		"Treino de Elite: tropas +15% de vida e dano")
	check(colony.bonus("chain_add") == 0 and is_equal_approx(colony.mult("unit_dmg"), 1.15), "bonus/mult lidos da tabela")
	colony.hall.level = 3   # só para conferir o bônus de aldeões da era III
	check(colony.crew_for("lumber_camp") == 4 and colony.crew_for("quarry") == 4 and colony.crew_for("farm") == 2, "era III: +1 aldeão nas serrarias e pedreiras")
	colony.hall.level = 2
	colony.busy_t.clear()   # descarta o Arado (o resto do teste não depende dele)
	colony.demolish(camp2)
	colony.demolish(quarry2)
	colony.citizens = keep_era[0]
	Game.gold = keep_era[1]
	colony.food = keep_era[2]
	colony.res = keep_era[3]

	# --- torre defende
	var tower := colony.place("archer_tower", Vector3(8, 0, 14), 0.0)
	var e := colony.spawn_enemy("slime", Vector3(8, 0, 30))
	var hp0 := e.hp
	await wait(2.5)
	check(not is_instance_valid(e) or e.dead or e.hp < hp0, "torre de arqueiros acerta o monstro")
	check(colony.upgrade(tower) == "" and tower.level == 2, "torre melhora para o nível 2")

	# --- munição: torres e tropas à distância gastam do estoque
	var said: Array[String] = []
	var on_say := func(text: String, _c: Color) -> void: said.append(text)
	Game.notify.connect(on_say)
	var phase0 := colony.phase
	colony.phase = "night"   # aviso e relatório de munição só valem à noite
	colony.night_ammo = {}
	colony._ammo_acc = {}   # descarta disparos que sobraram de unidades de testes anteriores
	colony.res["wood"] = 10
	for i in 10:
		colony.use_ammo("archer_tower")
	check(colony.amount("wood") == 8, "10 flechas gastam 2 madeira")
	check(int(colony.night_ammo.get("wood", 0)) == 2, "gasto da noite registra a madeira")
	check(is_equal_approx(ColonyData.ammo_per_night("archer_tower", 10.0, 1.0), 2.0)
		and is_equal_approx(ColonyData.ammo_per_night("archer_tower", 10.0, 2.0), 1.0), "ammo_per_night usa o multiplicador de tecnologia")
	colony.res["wood"] = 0
	check(not colony.use_ammo("archer_tower") and colony.amount("wood") == 0, "sem madeira não fica negativo")
	check(not colony.use_ammo("archer") and colony.use_ammo("soldier"), "arqueiro sem madeira falha; soldado não usa munição")
	if is_instance_valid(tower):
		colony.demolish(tower)   # só a torre nova pode acertar o alvo abaixo
	colony.res["wood"] = 0   # demolir devolve madeira
	colony._ammo_acc = {}
	var t2 := colony.place("archer_tower", Vector3(-8, 0, 14), 0.0, true)
	var e2 := colony.spawn_enemy("slime", Vector3(-8, 0, 30))
	var hp2 := e2.hp
	var cd_max := 0.0
	for i in 180:
		await get_tree().process_frame
		cd_max = maxf(cd_max, t2._cd)
	check(not is_instance_valid(e2) or e2.hp < hp2, "torre sem munição continua atirando (mais devagar)")
	check(said.count("Acabaram as flechas!") == 1, "aviso de munição aparece uma vez (%d)" % said.count("Acabaram as flechas!"))
	check(cd_max > t2.tower_rate() * 1.5 and cd_max <= t2.tower_rate() * ColonyData.NO_AMMO_RATE + 0.001,
		"sem munição o intervalo da torre dobra (_cd máx %.2f, normal %.2f)" % [cd_max, t2.tower_rate()])
	check(colony.amount("wood") == 0, "a torre sem munição não deixa o estoque negativo (%d)" % colony.amount("wood"))
	check(not colony.ammo_out("wood") or colony.phase == "night", "o pisca só vale à noite")
	# arqueiro (tropa à distância): sem madeira ainda atira, mais devagar; com madeira, gasta
	if is_instance_valid(t2):
		colony.demolish(t2)
	colony.res["wood"] = 0   # a demolição devolveu madeira
	colony._ammo_acc = {}
	var archer: Node = null
	for sd in colony.soldiers():
		if sd.is_ranged():
			archer = sd
	check(archer != null, "há um arqueiro")
	if archer != null:
		var e3 := colony.spawn_enemy("slime", archer.global_position + Vector3(0, 0, 8))
		var hp3 := e3.hp
		await wait(3.0)
		check(not is_instance_valid(e3) or e3.dead or e3.hp < hp3, "arqueiro sem madeira ainda atira")
		check(colony.amount("wood") == 0 and not archer._has_ammo, "arqueiro sem madeira: estoque 0 e intervalo dobrado (%d, %s)" % [colony.amount("wood"), archer._has_ammo])
		colony.res["wood"] = 50
		colony._ammo_acc = {}
		var e4 := colony.spawn_enemy("slime", archer.global_position + Vector3(0, 0, 8))
		await wait(3.0)
		check(colony.amount("wood") < 50 and archer._has_ammo, "arqueiro com madeira gasta do estoque (%d)" % colony.amount("wood"))
		if is_instance_valid(e4):
			e4.take_damage(999999, e4.global_position, false)
	colony.phase = phase0
	Game.notify.disconnect(on_say)

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
	var hc: Dictionary = ColonyData.BUILDINGS.house.cost
	var c5 := ColonyData.coop_cost("house", 5)
	check(ColonyData.coop_cost("house", 0) == hc and c5.gold == int(round(hc.gold * 1.5)) and c5.wood == int(round(hc.wood * 1.5)),
		"em grupo a 6ª casa custa 50% a mais de cada recurso")
	check(ColonyData.coop_hp_mult(20) > ColonyData.coop_hp_mult(10) * 2.0, "vida dos monstros acelera no fim de jogo")
	check(ColonyData.chest_rarities(20)[0][0] == "legendary", "baú da noite 20 pode ser lendário")

	# --- reparo e demolição
	if is_instance_valid(wall) and not wall.dead:
		var rc := colony.repair_cost(wall)
		check(not rc.is_empty() and colony.repair(wall) == "" and wall.hp == wall.max_hp, "reparo restaura a vida (%s)" % ColonyData.cost_text(rc))
		g0 = Game.gold
		var s0 := colony.amount("stone")
		colony.demolish(wall)
		check(Game.gold == g0 + int(wall.invested.gold * 0.5) and colony.amount("stone") == s0 + int(wall.invested.stone * 0.5),
			"demolir devolve metade de cada recurso")

	# --- caça
	var deer: ColonyAnimal = load("res://scripts/colony/animal.gd").new()
	deer.kind = "deer"
	deer.colony = colony
	deer.position = player.global_position + Vector3(3, 0.3, 0)
	colony.add_child(deer)
	await wait(0.1)
	player.model.rotation.y = PI / 2
	player.look["class"] = "sword"
	# Baseline só agora, sem await até o golpe: durante a espera acima soldados/torres matam monstros
	# errantes, e cada morte soma ouro ao cofre (Enemy._die no solo), o que desalinhava o `g0` antigo.
	var food0 := colony.food
	g0 = Game.gold
	deer.take_damage(9999, player.global_position, false)
	check(colony.food == food0 + 10 and Game.gold == g0 + 9, "caçar um cervo rende comida e ouro")

	# --- fauna por anel: lobo no anel 2 (em matilha), urso no anel 3, nada de agressivo no anel 1
	for a in get_tree().get_nodes_in_group("animals"):
		a.queue_free()
	await wait(0.1)
	for i in 10:
		colony._spawn_wildlife(true, 200)   # 60 grupos: urso (15%) e lobo aparecem sempre
	var kinds := {}
	var ring_ok := true
	for a in get_tree().get_nodes_in_group("animals"):
		var d := Vector2(a.global_position.x, a.global_position.z).length()
		kinds[a.kind] = int(kinds.get(a.kind, 0)) + 1
		if a.kind == "bear" and d < 105.0:
			check(false, "urso só no anel 3 (%.1f m)" % d)
		var in_ring := false   # a matilha se espalha uns 2 m em volta do ponto sorteado
		for r in ColonyData.ANIMALS[a.kind].rings:
			var lo: float = ColonyData.RINGS[r - 1]
			var hi: float = ColonyData.RINGS[r] if r < ColonyData.RINGS.size() else INF
			in_ring = in_ring or (d >= lo - 3.0 and d <= hi + 3.0)
		if not in_ring:
			ring_ok = false
	check(kinds.has("wolf") and kinds.has("bear"), "fauna nova aparece (%s)" % str(kinds))
	check(ring_ok, "cada espécie nasce só nos anéis dela")
	check(int(kinds.get("wolf", 0)) >= 3, "lobos vêm em matilha (%d)" % int(kinds.get("wolf", 0)))
	for a in get_tree().get_nodes_in_group("animals"):
		a.queue_free()
	await wait(0.1)

	# --- amanhecer: economia
	f = colony.forecast()
	g0 = Game.gold
	var day0 := colony.day
	colony.dawn()
	check(colony.day == day0 + 1, "amanhece um novo dia")
	check(Game.gold == g0 + f.gold_net, "amanhecer aplica impostos e salários (%d -> %d)" % [g0, Game.gold])
	# salários (3 cavaleiros + 2 = 47/dia) maiores que a renda (só a prefeitura, 15): alguns desertam
	for i in 3:
		colony.spawn_soldier("knight", Vector3(12, 0, 2))
	await wait(0.1)
	var before := colony.soldier_count()
	var cit_s := colony.citizens
	colony.citizens = 0
	Game.gold = 0
	colony.dawn()
	await wait(0.1)
	check(colony.soldier_count() < before and Game.gold >= 0, "sem ouro para salários, soldados desertam (%d -> %d)" % [before, colony.soldier_count()])
	for s in colony.soldiers():
		s.leave()
	colony.citizens = cit_s
	Game.gold = 2000
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

	# --- covis: acordam com jogador perto, dormem sem ninguém e à noite, reforçam a onda, crescem e são limpos
	check(colony.dens.size() >= 4 and colony.dens.size() <= 6, "o mapa tem covis (%d)" % colony.dens.size())
	var den_dirs_ok := true
	var seen_dirs := {}
	for dn in colony.dens:
		var dd := Vector2(dn.global_position.x, dn.global_position.z).length()
		var lo: float = ColonyData.RINGS[int(ColonyData.POIS[dn.kind].ring) - 1]
		if seen_dirs.has(dn.dir_index) or dd < lo:
			den_dirs_ok = false
		seen_dirs[dn.dir_index] = true
	check(den_dirs_ok, "cada covil numa direção diferente, no anel dele")
	var den: ColonyDen = colony.dens[0]
	player.global_position = den.global_position.move_toward(Vector3.ZERO, 30.0) + Vector3(0, 0.5, 0)
	await wait(1.0)
	check(den.awake and den.guards_alive() > 0, "covil acorda com jogador perto (%d guardas)" % den.guards_alive())
	var leashed := true
	for g in den.guards():
		if g.siege or g.den_id != den.id:
			leashed = false
	check(leashed, "guardas não são do cerco e são presos ao covil")
	var boss0 := den.boss()
	check(boss0 != null and boss0.kind == str(ColonyData.POIS[den.kind].boss), "o chefe do covil está lá")
	var boss_hp := -1.0
	if boss0:
		boss0.take_damage(boss0.max_hp * 0.4, boss0.global_position, false)
		boss_hp = boss0.hp
	player.global_position = Vector3(0, 0.5, 14)
	await wait(1.0)
	check(not den.awake and den.guards_alive() == 0, "covil dorme sem ninguém perto")
	player.global_position = den.global_position.move_toward(Vector3.ZERO, 30.0) + Vector3(0, 0.5, 0)
	await wait(1.0)
	var boss1 := den.boss()
	check(boss1 != null and boss1 != boss0 and absf(boss1.hp - boss_hp) < 0.5 and boss_hp < boss1.max_hp,
		"chefe volta com o dano que levou (%.0f/%.0f)" % [boss1.hp if boss1 else -1.0, boss_hp])
	player.global_position = Vector3(0, 0.5, 14)
	await wait(1.0)
	check(not den.awake and den.guards_alive() == 0, "covil volta a dormir")
	# onda: antes de DEN_FORCE_NIGHT os covis não mexem nela (começo igual ao de antes)
	var early_ok := true
	for i in 10:
		if colony._pick_wave_dirs(1).size() != 1:
			early_ok = false
		for it in colony._build_wave(1):
			if it is Array:
				early_ok = false
	check(early_ok, "noite 1: uma direção só e nenhum extra de covil")
	var forced := colony._pick_wave_dirs(ColonyData.DEN_FORCE_NIGHT)
	var all_in := true
	for d in colony.den_dirs():
		all_in = all_in and d in forced
	check(all_in, "a partir da noite %d as direções dos covis entram na onda" % ColonyData.DEN_FORCE_NIGHT)
	# teto: covis no nível máximo somam no máximo DEN_EXTRA_MAX do orçamento
	var lv_keep: Array = []
	for dn in colony.dens:
		lv_keep.append(dn.level)
		dn.level = ColonyData.DEN_MAX_LEVEL
	var ex := colony._den_budgets(100.0, 10)
	var ex_sum := 0.0
	for d in ex:
		ex_sum += float(ex[d])
	check(ex_sum <= 100.0 * ColonyData.DEN_EXTRA_MAX + 0.01, "extra dos covis tem teto (%.0f de 100)" % ex_sum)
	for i in colony.dens.size():
		colony.dens[i].level = lv_keep[i]
	check(colony.den_dirs().has(den.dir_index), "covil de pé entra na onda")
	colony.start_night()
	check(den.dir_index in colony.wave_dirs, "direção do covil é forçada na onda")
	var den_extra := 0
	for it in colony.wave_queue:
		if it is Array and int(it[1]) == den.dir_index:
			den_extra += 1
	check(den_extra > 0, "covil soma monstros extras na direção dele (%d)" % den_extra)
	d0 = colony.day
	for i in 30:
		colony.wave_queue.clear()
		for c in colony.get_children():
			if c is Enemy and not c.dead:
				c.take_damage(999999, c.global_position, false)
		await wait(0.3)
		if colony.phase == "day":
			break
	await wait(3.0)
	check(colony.phase == "day" and colony.day == d0 + 1, "noite com covis termina (dia %d)" % colony.day)
	if cr.alive:   # a noite a mais deixou o cristal voltar; o save abaixo confere um nó esgotado
		for i in 6:
			colony.harvest(cr.id, player.global_position)
	den.level = 1   # o teste mexe nos dias à mão; conta o crescimento a partir de hoje
	den.grown_day = colony.day
	den.dawn(colony.day + 3)
	check(den.level == 2, "covil cresce a cada 3 dias (nível %d)" % den.level)
	var lv2 := den.level
	var gd2 := den.grown_day
	for i in 10:
		den.dawn(den.grown_day + ColonyData.DEN_GROW_DAYS)
	check(den.level == ColonyData.DEN_MAX_LEVEL, "covil para no nível máximo (%d)" % den.level)
	den.level = lv2
	den.grown_day = gd2
	var s0 := colony.amount("stone")
	var n_nodes := colony.nature.nodes.size()
	den.on_boss_killed()
	check(den.cleared and colony.amount("stone") > s0 and not colony.den_dirs().has(den.dir_index),
		"limpar o covil dá recursos e fecha a direção")
	var rich := colony.nature.node(n_nodes)
	var dep: Array = ColonyData.POIS[den.kind].deposit
	check(rich != null and rich.kind == str(dep[0]) and rich.total == int(dep[1]), "limpar o covil deixa um nó rico")
	if rich:
		for i in int(ColonyData.NODES[rich.kind].hits):
			colony.harvest(rich.id, player.global_position)
		colony.nature.regrow(colony.day + 30)
		check(not rich.alive, "nó rico é depósito único: esgotado, não volta")
	if cr.alive:   # o regrow acima devolveu o cristal; o save abaixo confere um nó esgotado
		for i in 6:
			colony.harvest(cr.id, player.global_position)
	colony.phase = "night"
	player.global_position = colony.dens[1].global_position.move_toward(Vector3.ZERO, 20.0) + Vector3(0, 0.5, 0)
	await wait(1.0)
	check(not colony.dens[1].awake and colony.dens[1].guards_alive() == 0, "covis dormem à noite")
	colony.phase = "day"
	player.global_position = Vector3(0, 0.5, 14)
	var rich_id := rich.id if rich else -1
	var rich_kind := rich.kind if rich else ""
	var rich_total := rich.total if rich else -1
	var den1_level := 3
	colony.dens[1].level = den1_level

	# --- salvar e carregar
	var nb := colony.buildings().size()
	var ns := colony.soldier_count()
	var day_s := colony.day
	var gold_s := Game.gold
	var stone_s := colony.amount("stone")
	var inv_s: Dictionary = colony.buildings()[0].invested.duplicate()
	var save_v: int = int(colony.to_dict().get("version", 0))
	Game.gold += 200
	colony.res["wood"] = int(colony.res.get("wood", 0)) + 200
	check(colony.research("plow") == "", "Arado em andamento na hora de salvar")
	gold_s = Game.gold
	check(world.save_colony(), "salva a cidade")
	check(Game.has_colony_save(), "arquivo de save existe")
	Game.start_colony(true)
	await wait(1.0)
	_bind()
	check(colony.buildings().size() == nb, "carrega as construções (%d)" % colony.buildings().size())
	check(colony.soldier_count() == ns, "carrega o exército (%d)" % colony.soldier_count())
	check(colony.day == day_s and Game.gold == gold_s, "carrega dia e ouro")
	check(save_v == 2 and colony.amount("stone") == stone_s, "carrega o estoque de recursos (save versão 2)")
	check(colony.buildings()[0].invested == inv_s, "carrega o investido por recurso")
	check(colony.has_tech("sharp_axe") and colony.has_tech("masonry") and colony.era() == 2, "carrega as pesquisas e a era")
	check(colony.busy_t.size() == 1 and str(colony.busy_t.values()[0][0]) == "plow", "pesquisa em andamento volta do save")
	check(colony.dens[0].cleared and colony.dens[1].level == den1_level and not colony.dens[1].cleared,
		"save guarda o estado dos covis")
	var rich_l := colony.nature.node(rich_id)
	check(rich_l != null and rich_l.kind == rich_kind and rich_l.total == rich_total, "save guarda o nó rico do covil")
	check(rich_l != null and not rich_l.alive, "nó rico esgotado continua esgotado no save")
	var old := colony.to_dict()
	old.erase("res")
	old["version"] = 1
	old["buildings"] = []   # só o estoque interessa aqui; não duplica a cidade carregada
	old["soldiers"] = []
	colony.from_dict(old)
	check(colony.amount("wood") == int(ColonyData.START_RES.wood) and colony.amount("stone") == int(ColonyData.START_RES.stone),
		"save versão 1 volta com o estoque inicial")
	check(ColonyData.cost_from(40) == {"gold": 40}, "investido inteiro de save antigo vira ouro")
	check(colony.phase == "day" and colony.hall != null, "cidade carregada de dia")
	check(not colony.nature.node(cr_id).alive, "nó esgotado volta esgotado do save")
	# save versão 1 (sem semente, sem estoque, sem nós) lido do arquivo
	var v1 := colony.to_dict()
	v1.erase("seed")
	v1.erase("res")
	v1.erase("nodes")
	v1.erase("dens")
	v1.erase("rich")
	v1["version"] = 1
	_write_save(v1)
	Game.start_colony(true)
	await wait(1.0)
	_bind()
	check(world.map_seed == 7731 and colony.amount("wood") == 150, "save antigo carrega com semente 7731 e madeira inicial")
	check(colony.nature.node(cr_id).alive, "save antigo: todos os nós vivos")
	var fresh: bool = colony.dens.size() >= 4
	for dn in colony.dens:
		fresh = fresh and not dn.cleared and dn.level == 1
	check(fresh and colony.nature.node(rich_id) == null, "save antigo: covis novos e sem nó rico")

	# --- derrota
	colony.hall.take_damage(999999, Vector3.ZERO)
	check(colony.phase == "over", "prefeitura destruída = derrota")
	await wait(3.0)
	check(world.modal != null and world.modal.get("mode") == "defeat", "tela de derrota aparece")

	print("\n%s — %d falha(s)" % ["OK" if fails == 0 else "FALHOU", fails])
	get_tree().quit(1 if fails > 0 else 0)


func _obstacle_at(p: Vector3) -> bool:
	for o in colony.obstacles:
		if Vector2(p.x, p.z).distance_to(o[0]) < 0.1:
			return true
	return false


func _write_save(d: Dictionary) -> void:
	var f := FileAccess.open(Game.colony_save_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "\t"))
	f.close()


## Ponto livre a 50-75 m do centro com árvores/pedras suficientes em volta (para serraria/pedreira).
func _camp_spot(kind: String) -> Vector3:
	var fallback := Vector3.INF
	for n in colony.nature.nodes:
		var d := Vector2(n.global_position.x, n.global_position.z).length()
		if n.kind != kind or not n.alive or d < 50.0 or d > 72.0:
			continue
		for dx in [-6.0, -3.0, 0.0, 3.0, 6.0]:
			for dz in [-6.0, -3.0, 0.0, 3.0, 6.0]:
				var p: Vector3 = n.global_position + Vector3(dx, 0.0, dz)
				if Vector2(p.x, p.z).length() > 74.0 or colony.nature.alive_near(kind, p, 14.0).size() < 4:
					continue
				if fallback == Vector3.INF:
					fallback = p
				var k := "lumber_camp" if kind == "tree" else "quarry"
				if colony.can_place(k, p, 0.0) == "":
					return p
	return fallback


func _bind() -> void:
	world = get_tree().current_scene
	colony = world.get("colony") if world else null
	player = get_tree().get_first_node_in_group("player")
