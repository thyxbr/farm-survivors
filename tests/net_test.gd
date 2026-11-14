extends Node
## Teste do multiplayer: entra num servidor como cliente headless e verifica a sincronia.
##   godot --headless --path . -- --server --port=7777                      (terminal 1)
##   godot --headless --path . -- --nettest=127.0.0.1:7777 [--peers=2] [--name=A]   (terminal 2, 3...)
## --peers=N espera ver N-1 outros jogadores. Sai com código 0 (ok) ou 1 (falhas).
## --probe: só entra, confere versão e snapshots e sai (usado pelo CI contra o servidor público).
## --horde=lead|join: testa o Desafio da Horda em grupo (lead abre o portal, join aceita o convite).
##   Use com o servidor em --horde-round=8 --horde-pick=5 para as rodadas e escolhas não demorarem.
## --city=lead|join: testa a Defesa da Cidade em grupo pelo salão (lead cria a sala e começa, join entra).
##   Use com o servidor em --city-day=12 para o dia não demorar.

var fails := 0
var address := "127.0.0.1"
var peers := 1
var my_name := "Teste"
var probe := false
var horde_role := ""
var city_role := ""
var chat_got: Array = []   # [nome, texto]


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + "[%s] %s" % [my_name, what])
	if not cond:
		fails += 1


func wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, true).timeout


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--nettest="):
			address = a.substr(10)
		elif a.begins_with("--peers="):
			peers = int(a.substr(8))
		elif a.begins_with("--name="):
			my_name = a.substr(7)
		elif a == "--probe":
			probe = true
		elif a.begins_with("--horde="):
			horde_role = a.substr(8)
		elif a.begins_with("--city="):
			city_role = a.substr(7)
	Network.chat_received.connect(func(from: String, text: String) -> void: chat_got.append([from, text]))
	Game.save_path = "user://nettest_%s.json" % my_name
	Game.new_game()
	var failed := [""]
	Network.join_failed.connect(func(r: String) -> void: failed[0] = r)
	Network.join(address, my_name)

	# todo mundo chega pelo salão
	var t := 0.0
	while not _in_lobby() and failed[0] == "" and t < 15.0:
		await wait(0.2)
		t += 0.2
	check(failed[0] == "", "conectou sem erro %s" % failed[0])
	check(_in_lobby(), "chegou ao salão (lobby)")
	if not _in_lobby():
		_finish()
		return
	check(await _wait_until(func() -> bool: return Network.zone_of(multiplayer.get_unique_id()) == "lobby", 5.0),
		"servidor vê o jogador no salão")
	if city_role != "":
		await _test_city()
		_finish()
		return
	Lobby.go_world()
	t = 0.0
	while Network.world == null and t < 15.0:
		await wait(0.2)
		t += 0.2
	check(Network.world != null and Network.world.player != null, "entrou no mundo com personagem local")
	if Network.world == null:
		_finish()
		return
	# equipa arco e capuz logo ao entrar: os outros jogadores devem ver esse visual
	Game.equip("short_bow")
	Game.equip("leather_cap")
	await wait(1.5)
	var w: Node = Network.world
	check(w.player.look["class"] == "bow", "arco equipado no personagem local")
	check(Network.enemies.size() >= 15, "inimigos replicados do servidor (%d)" % Network.enemies.size())
	var e0: Enemy = Network.enemies.values()[0]
	check(e0.puppet, "inimigos no cliente são réplicas")
	print("[%s] fps cliente: %d" % [my_name, Engine.get_frames_per_second()])
	var n0 := Network.snapshots_received
	await wait(2.0)
	var rate := (Network.snapshots_received - n0) / 2.0
	check(rate >= Network.SEND_RATE * 0.75, "recebendo snapshots dos inimigos (%.1f/s)" % rate)
	# --probe: só confere que o servidor aceitou esta versão e está mandando o mundo; não mexe em nada lá
	if probe:
		print("[%s] servidor aceitou a versão %s" % [my_name, Network.version()])
		_finish()
		return

	# save automático periódico: o personagem é gravado sem o jogador sair do servidor
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	Network.autosave_interval = 1.0
	Network._autosave_t = 1.0
	await wait(1.6)
	check(Game.has_save(), "save automático periódico gravou o personagem")
	Network.autosave_interval = 120.0
	Network._autosave_t = 120.0

	# outros jogadores aparecem e se mexem
	if peers > 1:
		t = 0.0
		while Network.remote_players.size() < peers - 1 and t < 10.0:
			await wait(0.2)
			t += 0.2
		check(Network.remote_players.size() == peers - 1, "vê os outros jogadores (%d)" % Network.remote_players.size())
		await wait(1.0)
		for rp in Network.remote_players.values():
			check(rp.look["class"] == "bow" and rp._last_look.get("head", "") == "leather_cap",
				"vê o arco e o capuz de %s" % rp.display_name)
			var holder: Node3D = rp.look.get("holder")
			check(holder != null and is_instance_valid(holder), "modelo do arco montado na réplica de %s" % rp.display_name)

	# chat: cada um manda uma mensagem e recebe a do outro (com o próprio eco)
	if peers > 1:
		check(w.chat != null, "caixa de chat criada no mundo")
		Network.send_chat("  Olá de %s!
  " % my_name)
		check(await _wait_until(func() -> bool:
			var others := 0
			var mine := false
			for m in chat_got:
				if m[0] == Network.my_name and m[1] == "Olá de %s!" % my_name:
					mine = true
				elif m[0] != "" and str(m[1]).begins_with("Olá de "):
					others += 1
			return mine and others >= peers - 1, 6.0), "chat chega para todos (%s)" % str(chat_got))
		# anti-spam: a 6ª mensagem seguida recebe o aviso do servidor
		for i in 6:
			Network.send_chat("spam %d" % i)
		check(await _wait_until(func() -> bool:
			for m in chat_got:
				if m[0] == "" and str(m[1]).begins_with("Calma"):
					return true
			return false, 4.0), "chat limita mensagens em sequência")
		# abrir o chat trava o personagem; Esc fecha
		w.chat._set_open(true)
		check(w.chat.is_open() and w.player.chat_typing, "Enter abre o chat e trava o personagem")
		w.chat._set_open(false)
		check(not w.player.chat_typing, "fechar o chat devolve o controle")

	# acerta um slime até morrer: o servidor aplica o dano e devolve XP/loot
	var target: Enemy = null
	for e in Network.enemies.values():
		if e.kind == "slime" and not e.dead:
			target = e
			break
	check(target != null, "achou um slime")
	if target:
		w.player.global_position = target.global_position + Vector3(0, 0.5, 3)
		var hp0 := target.hp
		var xp0 := Game.xp + Game.level * 100000
		var kills0 := Game.kills
		var gold0 := Game.gold
		target.take_damage(10.0, w.player.global_position, false)
		await wait(0.6)
		check(target.hp < hp0, "dano chega ao servidor e volta no snapshot (%.0f → %.0f)" % [hp0, target.hp])
		target.take_damage(9999.0, w.player.global_position, false)
		await wait(0.8)
		check(not is_instance_valid(target) or target.dead, "slime morreu em todos")
		check(Game.kills == kills0 + 1 and Game.xp + Game.level * 100000 > xp0, "recebeu XP e abate (%d abates)" % Game.kills)
		await wait(1.0)
		var drops := 0
		for n in w.get_children():
			if n.get_script() == preload("res://scripts/world/pickup.gd"):
				drops += 1
		# o jogador está ao lado: o ímã das moedas costuma coletar na hora
		check(drops >= 1 or Game.gold > gold0, "loot pessoal (%d no chão, ouro %d → %d)" % [drops, gold0, Game.gold])

	# flecha (projétil) acerta um inimigo réplica: o dano passa pelo servidor
	var tgt: Enemy = null
	for e in Network.enemies.values():
		if e.kind == "slime" and not e.dead and e.hp > 20.0:
			tgt = e
			break
	check(tgt != null, "achou outro slime para a flecha")
	if tgt:
		var aim := tgt.global_position + Vector3.UP * 0.4
		var origin := aim + Vector3(0, 0, 4)
		w.player.global_position = origin + Vector3(0, -0.4, 1.0)
		var hp1 := tgt.hp
		w.player._spawn_projectile("arrow", origin, (aim - origin).normalized(), 12.0, false, 0, 40.0)
		await wait(0.8)
		check(not is_instance_valid(tgt) or tgt.hp < hp1, "flecha causa dano pelo servidor (%.0f → %.0f)" % [hp1, tgt.hp if is_instance_valid(tgt) else 0.0])
	# cajado: projétil arcano com lentidão também passa pelo servidor
	Game.add_item("frost_scepter", 1, true)
	Game.equip("frost_scepter")
	check(Game.equipment.weapon == "frost_scepter" and w.player.look["class"] == "staff", "trocou para o cajado")
	await wait(0.6)
	if peers > 1:
		await wait(0.6)
		for rp in Network.remote_players.values():
			check(rp.look["class"] == "staff", "vê %s trocar para cajado" % rp.display_name)

	if horde_role != "":
		await _test_horde(w)

	# fica um pouco para os outros testes verem este jogador
	await wait(3.0 if peers > 1 else 0.5)
	_finish()


# ---------------------------------------------------------------- Desafio da Horda em grupo
func _invite_ui(w: Node) -> Node:
	for c in w.get_children():
		if c.get_script() == preload("res://scripts/ui/horde_invite_ui.gd"):
			return c
	return null


func _wait_until(cond: Callable, max_t: float) -> bool:
	var t := 0.0
	while not cond.call() and t < max_t:
		await wait(0.1)
		t += 0.1
	return cond.call()


## Escolhe as cartas de nível que aparecerem (a primeira de cada vez).
func _pick_levelups(w: Node) -> void:
	while w.modal != null and w.modal.get("mode") == "levelup":
		await wait(0.45)
		if w.modal != null and w.modal.get("mode") == "levelup":
			w.modal._pick(0)
		await wait(0.1)


func _test_horde(w: Node) -> void:
	var p: Player = w.player
	p.global_position = w.VILLAGE_SPAWN
	Game.hp = Game.max_hp()
	var ui := _invite_ui(w)
	check(ui != null, "painel de convite da horda existe no cliente")
	if horde_role == "lead":
		w.start_survival()   # online: abre a fila e convida os outros
		check(await _wait_until(func() -> bool: return Network.in_horde_lobby(), 5.0), "abriu a fila do Desafio da Horda")
		check(ui and ui.state() == "member", "painel mostra a fila para quem abriu")
	else:
		check(await _wait_until(func() -> bool: return Network.horde_invite_pending(), 40.0), "recebeu o convite para a horda")
		check(ui and ui.state() == "invite", "painel mostra o convite [Y]/[N]")
		Network.horde_answer(true)
		check(ui and ui.state() == "member", "aceitou o convite e entrou na fila")

	check(await _wait_until(func() -> bool: return w.survival != null, 25.0), "entrou na partida do grupo")
	var sv = w.survival
	if sv == null:
		return
	check(sv.role == "client" and sv.team.size() == peers, "grupo com %d jogador(es) (%d)" % [peers, sv.team.size()])
	check(p.global_position.distance_to(w.ARENA) < 5.0, "teleportado para a arena")
	check(Network.horde_lobby.is_empty() and ui.state() == "", "fila fechada ao começar")
	check(await _wait_until(func() -> bool: return sv.round_num == 1, 5.0), "rodada 1 chega do servidor")
	check(await _wait_until(func() -> bool: return sv.alive_count() >= 1, 6.0), "inimigos da horda replicados (%d)" % sv.alive_count())
	if peers > 1:
		var near := 0
		for rp in Network.remote_players.values():
			if rp.global_position.distance_to(w.ARENA) < 40.0:
				near += 1
		check(near == peers - 1, "vê o grupo na arena (%d)" % near)

	# abate de um inimigo da horda: o servidor conta e cada um ganha a própria gema
	var xp0 := Game.xp + Game.level * 100000
	var kills0: int = sv.kills
	for e in Network.enemies.values():
		if is_instance_valid(e) and e.horde and not e.dead:
			e.take_damage(99999.0, p.global_position, false)
			break
	check(await _wait_until(func() -> bool: return sv.kills > kills0, 3.0), "abate da horda chega pelo servidor (%d)" % sv.kills)
	check(get_tree().get_nodes_in_group("xp_gems").size() > 0 or sv.run_xp > 0 or sv.run_level > 1, "gema de XP pessoal caiu")
	check(Game.xp + Game.level * 100000 == xp0, "horda não dá XP do RPG")

	# placar: o servidor conta dano e abates de cada um e repassa a build dos colegas
	var me := multiplayer.get_unique_id()
	# (os dois clientes podem mirar o mesmo inimigo: de tempos em tempos acerta outro até o abate ser meu)
	var tries := [0]
	check(await _wait_until(func() -> bool:
		tries[0] += 1
		if tries[0] % 8 == 0 and int(sv.team.get(me, {}).get("kills", 0)) < 1:
			for e in Network.enemies.values():
				if is_instance_valid(e) and e.horde and not e.dead:
					e.take_damage(99999.0, p.global_position, false)
					break
		return sv.team.has(me) and float(sv.team[me].get("dmg", 0.0)) > 0.0 and int(sv.team[me].get("kills", 0)) >= 1, 8.0),
		"servidor conta meu dano e abate no placar")
	check(sv.scoreboard_rows().size() == peers, "placar do Tab com %d linha(s)" % peers)
	if peers > 1:
		# combo: Beto pega a Aura Gélida; com o Orbe de Fogo do outro forma o Choque Térmico
		if horde_role == "join":
			sv._apply({"type": "weapon", "id": "aura"})
		check(await _wait_until(func() -> bool:
			for pid in sv.team:
				if pid != me and not sv.team[pid].get("build", {}).get("w", {}).has("fogo"):
					return false
			return true, 4.0), "build do colega chega pelo servidor")
		check(await _wait_until(func() -> bool:
			return sv.active_combos.has("choque") and sv.active_combos.choque.near, 14.0),
			"combo Choque Térmico ativo com o colega perto")
		if horde_role == "join" and sv.active_combos.has("choque"):
			# força o gatilho: um acerto da aura num inimigo dispara o combo. Na rodada 1 os inimigos
			# nascem aos poucos e as armas dos dois clientes matam rápido: espera haver um alvo vivo
			# (com o combo ainda ativo e o colega perto) antes de disparar.
			var target: Array = [null]
			var has_target: bool = await _wait_until(func() -> bool:
				target[0] = null
				if not (sv.active_combos.has("choque") and sv.active_combos.choque.near):
					return false
				for e in Network.enemies.values():
					if is_instance_valid(e) and e.horde and not e.dead:
						target[0] = e
						return true
				return false, 12.0)
			check(has_target, "inimigo vivo da horda para o acerto do combo")
			if has_target:
				sv.weapons._combo_cd.clear()
				var c0: int = sv.combos_done
				sv.weapons._combo("aura", target[0].global_position)
				check(sv.combos_done == c0 + 1, "acerto da arma dispara o combo")
	if peers > 1:
		await _test_shared_level(w, sv)

	# quem cai no grupo não sai: volta no fim da rodada
	if horde_role == "join" and peers > 1:
		p.invuln = 0
		p.take_damage(99999, p.global_position + Vector3.FORWARD)
		check(p.dead, "caiu na horda")
		await wait(1.0)
		check(w.survival == sv and sv.phase != "over", "continua no desafio enquanto o grupo luta")

	# fim da rodada: cada um escolhe a bênção
	var got_round: bool = await _wait_until(func() -> bool:
		if w.modal != null and w.modal.get("mode") == "levelup" and w.modal._lock <= 0.0:
			w.modal._pick(0)
		return w.modal != null and w.modal.get("mode") == "round", 30.0)
	check(got_round and sv.rounds_cleared == 1, "fim da rodada abre a bênção")
	check(not p.dead, "jogador de pé no fim da rodada")
	await wait(0.45)
	if w.modal != null and w.modal.get("mode") == "round":
		w.modal._pick(0)
	check(await _wait_until(func() -> bool: return sv.round_num == 2 and sv.phase == "fight", 20.0),
		"rodada 2 começa quando o grupo escolhe (%d, %s)" % [sv.round_num, sv.phase])
	await _pick_levelups(w)

	# retirada: quem abriu sai primeiro, o outro continua sozinho
	if horde_role == "join" and peers > 1:
		await wait(2.5)
		check(w.survival == sv and sv.phase == "fight" and sv.team.size() == 1, "segue na partida depois que o colega saiu")
		await _pick_levelups(w)
	sv.end_run("retreat")
	await wait(0.3)
	check(w.modal != null and w.modal.get("mode") == "results", "resultados ao se retirar")
	await wait(0.45)
	if w.modal != null:
		w.modal._finish()
	await wait(0.3)
	check(w.survival == null and p.global_position.distance_to(w.VILLAGE_SPAWN) < 3.0, "voltou para a vila")


# ---------------------------------------------------------------- salão e Defesa da Cidade em grupo
func _in_lobby() -> bool:
	var s := get_tree().current_scene
	return s != null and s.get("is_lobby") == true


func _city_colony() -> Colony:
	return Lobby.city.colony if Lobby.city != null and is_instance_valid(Lobby.city) else null


func _test_city() -> void:
	# --- sala no salão
	if city_role == "lead":
		Lobby.room_send("create")
		check(await _wait_until(func() -> bool: return Lobby.in_room() and Lobby.is_leader(), 5.0), "criou a sala da cidade (líder)")
		check(await _wait_until(func() -> bool:
			return Lobby.room.get("members", []).size() == peers and Lobby.room.get("ready", []).size() >= peers - 1, 30.0),
			"todos entraram na sala e ficaram prontos (%d)" % Lobby.room.get("members", []).size())
		Lobby.room_send("start")
	else:
		check(await _wait_until(func() -> bool: return not Lobby.room.is_empty(), 30.0), "vê a sala aberta no salão")
		Lobby.room_send("join")
		check(await _wait_until(func() -> bool: return Lobby.in_room(), 5.0), "entrou na sala")
		Lobby.room_send("ready")
		check(await _wait_until(func() -> bool: return Lobby.is_ready(), 5.0), "ficou pronto")

	# --- a cidade
	check(await _wait_until(func() -> bool: return _city_colony() != null, 20.0), "carregou a cidade em grupo")
	var c := _city_colony()
	if c == null:
		return
	var w: Node = Lobby.city
	check(c.role == "client" and w.role == "client", "cidade como réplica do servidor")
	var start_gold := ColonyData.COOP_START_GOLD + ColonyData.COOP_GOLD_PER_PLAYER * (peers - 1)
	check(await _wait_until(func() -> bool: return c.gold > 0, 5.0) and c.gold == start_gold, "cofre inicial do grupo %d (%d)" % [start_gold, c.gold])
	var start_wood := int(ColonyData.START_RES.wood) + ColonyData.COOP_WOOD_PER_PLAYER * (peers - 1)
	check(c.amount("wood") == start_wood and c.amount("stone") == int(ColonyData.START_RES.stone), "madeira e pedra iniciais do grupo (%d)" % c.amount("wood"))
	check(await _wait_until(func() -> bool: return Network.zone_of(multiplayer.get_unique_id()) == "city", 5.0), "servidor vê o jogador na cidade")
	if peers > 1:
		check(await _wait_until(func() -> bool: return Network.remote_players.size() == peers - 1, 10.0),
			"vê os outros jogadores na cidade (%d)" % Network.remote_players.size())

	if city_role == "lead":
		w.player.global_position = Vector3(0, 0.5, 14)
		c.place("town_hall", Vector3(0, 0, -6), 0.0)
	check(await _wait_until(func() -> bool: return c.hall != null and c.phase == "day", 10.0), "prefeitura fundada chega a todos")
	check(await _wait_until(func() -> bool: return c.amap.size() > 0, 5.0), "animais de caça replicados (%d)" % c.amap.size())
	if city_role == "lead":
		var g0 := c.gold
		var w0 := c.amount("wood")
		c.place("house", Vector3(-12, 0, -6), PI / 2)
		check(await _wait_until(func() -> bool: return c.count_of("house") == 1, 5.0), "casa construída pelo servidor")
		var hcost: Dictionary = ColonyData.BUILDINGS.house.cost
		check(await _wait_until(func() -> bool: return c.gold == g0 - int(hcost.gold) and c.amount("wood") == w0 - int(hcost.wood), 3.0),
			"casa cobra ouro e madeira do cofre (%d → %d)" % [g0, c.gold])
	else:
		check(await _wait_until(func() -> bool: return c.count_of("house") == 1, 10.0), "vê a casa do colega")
		await wait(2.0)   # o líder confere o cofre antes deste gasto
		c.place("barracks", Vector3(12, 0, -6), -PI / 2)
		check(await _wait_until(func() -> bool: return c.count_of("barracks") == 1, 5.0), "quartel construído pelo servidor")
		check(c.recruit("soldier") == "", "pede um soldado")
	if peers == 1:
		c.place("barracks", Vector3(12, 0, -6), -PI / 2)
		await _wait_until(func() -> bool: return c.count_of("barracks") == 1, 5.0)
		c.recruit("soldier")
	check(await _wait_until(func() -> bool: return c.soldier_count() == 1 and c.count_of("barracks") == 1, 10.0), "soldado replicado para todos")
	check(c.cost_of("house") == ColonyData.coop_cost("house", 1), "segunda casa custa mais (%s)" % ColonyData.cost_text(c.cost_of("house")))
	check(c.upkeep() == int(ColonyData.UPKEEP.barracks), "quartel tem manutenção (%d)" % c.upkeep())
	await wait(1.0)

	# --- coleta: o líder corta uma árvore; madeira e árvore caída chegam a todos
	var tree: ColonyResourceNode = c.nature.nearest("tree", Vector3.ZERO) if c.nature else null
	check(tree != null, "nós de recurso gerados da semente do grupo")
	if tree != null:
		var tw0 := c.amount("wood")
		if city_role == "lead":
			await wait(0.5)   # o colega anota a madeira antes do corte
			w.player.global_position = tree.global_position + Vector3(0, 0.5, 1.5)
			for i in 4:
				tree.hit(w.player.global_position)
				await wait(0.35)
		check(await _wait_until(func() -> bool: return not tree.alive, 8.0), "árvore esgotada aparece para todos")
		check(await _wait_until(func() -> bool: return c.amount("wood") == tw0 + 24, 5.0),
			"madeira da coleta chega ao cofre (%d → %d)" % [tw0, c.amount("wood")])

	# --- a noite: votação, monstros replicados, abates pagam o cofre
	var rgold := Game.gold
	var rxp := Game.xp + Game.level * 100000
	if city_role == "lead":
		c.start_night()
	check(await _wait_until(func() -> bool: return c.phase == "night", 25.0), "a noite começa (votada ou pelo relógio)")
	check(await _wait_until(func() -> bool: return not c.live_enemies().is_empty(), 10.0), "monstros da noite replicados (%d)" % c.live_enemies().size())
	var e0: Enemy = null
	for e in c.live_enemies():
		e0 = e
		break
	check(e0 != null and e0.puppet, "monstros no cliente são réplicas")
	var n0 := Network.snapshots_received
	await wait(1.0)
	check(Network.snapshots_received - n0 >= int(Network.SEND_RATE * 0.5), "snapshots dos monstros da cidade (%d/s)" % (Network.snapshots_received - n0))
	var killed := 0
	var tt := 0.0
	while c.phase == "night" and tt < 60.0:
		for e in c.live_enemies():
			w.player.global_position = e.global_position + Vector3(0, 0.5, 2.5)
			e.take_damage(99999.0, w.player.global_position, false)
			killed += 1
		await wait(0.4)
		tt += 0.4
	check(c.phase == "day" and c.day == 2, "amanheceu: dia %d" % c.day)
	check(killed > 0 and c.total_kills > 0, "abates contados pelo servidor (%d)" % c.total_kills)
	var rw := ColonyData.night_reward(1)
	check(await _wait_until(func() -> bool: return Game.gold >= rgold + int(rw.gold), 5.0),
		"recompensa da noite no personagem (+%d ouro: %d → %d)" % [rw.gold, rgold, Game.gold])
	check(Game.xp + Game.level * 100000 > rxp, "recompensa de XP no personagem")
	check(int(Game.flags.get("city_best", 0)) >= 1, "melhor noite salva no personagem")

	# --- volta ao salão: o join sai primeiro, o líder em seguida (a partida acaba quando todos saem)
	await wait(0.5 if city_role == "join" else 2.5)
	Lobby.go_lobby()
	check(await _wait_until(func() -> bool: return _in_lobby(), 10.0), "voltou ao salão")
	check(await _wait_until(func() -> bool: return Network.zone_of(multiplayer.get_unique_id()) == "lobby", 5.0), "servidor vê o jogador de volta no salão")
	if city_role == "lead":
		check(await _wait_until(func() -> bool: return Lobby.room.is_empty(), 8.0), "partida encerrada quando todos saíram")
		check(int(Lobby.record.get("day", 0)) >= 1, "recorde do servidor registrado (%d)" % int(Lobby.record.get("day", 0)))
	# o personagem continua o mesmo em Valdoria
	Lobby.go_world()
	check(await _wait_until(func() -> bool: return Network.world != null and Network.world.get("player") != null, 15.0), "entrou em Valdoria depois da cidade")
	await wait(1.0)


## Nível do grupo: o XP de um sobe o nível de todos; a horda congela até todos escolherem.
## Depois, um dos dois "fica AFK": o servidor espera --horde-pick segundos e sorteia a carta dele.
func _test_shared_level(w: Node, sv) -> void:
	await _pick_levelups(w)
	await _wait_until(func() -> bool: return not sv.frozen, 10.0)
	await _barrier(w, sv, "nivel")
	var lv0: int = sv.run_level
	if horde_role == "lead":
		await wait(0.5)
		sv.add_xp(sv.xp_needed() * sv.team.size() + 2)
	var opened: bool = await _wait_until(func() -> bool:
		return sv.frozen and w.modal != null and w.modal.get("mode") == "levelup", 8.0)
	check(opened, "grupo sobe de nível junto: cartas abrem e a horda congela")
	check(sv.run_level >= lv0 + 1, "nível compartilhado (%d → %d)" % [lv0, sv.run_level])
	check(w.modal != null and w.modal.get("_timer_bar") != null, "cartas mostram o tempo para escolher")
	var picks0: int = _build_size(sv)
	if horde_role == "lead":
		await wait(0.5)
		if w.modal != null and w.modal.get("mode") == "levelup":
			w.modal._pick(0)
		await wait(1.5)
		check(sv.frozen and w.player.horde_frozen, "continua congelado esperando o colega escolher")
		check(sv.hud.wait_line.visible, "faixa 'esperando o grupo' aparece")
	else:
		var pos := {}
		for e in Network.enemies.values():
			if is_instance_valid(e) and e.horde and not e.dead:
				pos[e] = e.global_position
		await wait(2.5)
		var moved := 0.0
		for e in pos:
			if is_instance_valid(e) and not e.dead:
				moved = maxf(moved, e.global_position.distance_to(pos[e]))
		check(moved < 0.5, "inimigos parados enquanto o grupo escolhe (%.2f m)" % moved)
		if w.modal != null and w.modal.get("mode") == "levelup":
			w.modal._pick(0)
	check(await _wait_until(func() -> bool: return not sv.frozen, 6.0), "horda volta quando todos escolhem")
	check(not w.player.horde_frozen, "jogador volta a se mexer")
	check(_build_size(sv) >= picks0 + 1, "carta escolhida aplicada")

	# tempo esgotado: quem não escolhe recebe uma carta sorteada
	await _pick_levelups(w)
	await _wait_until(func() -> bool: return not sv.frozen, 10.0)
	await _barrier(w, sv, "afk")
	if horde_role == "lead":
		await wait(1.0)
		sv.add_xp(sv.xp_needed() * sv.team.size() + 2)
	check(await _wait_until(func() -> bool:
		return sv.frozen and w.modal != null and w.modal.get("mode") == "levelup", 8.0), "nova subida de nível do grupo")
	var picks1: int = _build_size(sv)
	if horde_role == "lead":
		await wait(0.5)
		if w.modal != null and w.modal.get("mode") == "levelup":
			w.modal._pick(0)
	# join fica "AFK" com as cartas abertas
	check(await _wait_until(func() -> bool: return not sv.frozen, Network.horde_pick_time + 12.0),
		"servidor não espera para sempre: a horda volta depois do tempo limite")
	if horde_role == "join":
		await wait(0.3)
		check(w.modal == null or w.modal.get("mode") != "levelup", "cartas do jogador AFK fecham sozinhas")
		check(_build_size(sv) >= picks1 + 1, "carta sorteada para quem não escolheu (%d → %d)" % [picks1, _build_size(sv)])


## Sincroniza os clientes de teste pelo chat: cada um avisa que chegou e espera os outros
## (escolhendo cartas de nível que aparecerem enquanto isso).
func _barrier(w: Node, sv, tag: String) -> void:
	Network.send_chat("sync:" + tag)
	await _wait_until(func() -> bool:
		if w.modal != null and w.modal.get("mode") == "levelup" and w.modal._lock <= 0.0:
			w.modal._pick(0)
		var n := 0
		for m in chat_got:
			if m[1] == "sync:" + tag and m[0] != Network.my_name:
				n += 1
		return n >= peers - 1 and not sv.frozen and w.modal == null, 30.0)


func _build_size(sv) -> int:
	var n := 0
	for id in sv.weapon_levels:
		n += sv.weapon_levels[id]
	for id in sv.passive_levels:
		n += sv.passive_levels[id]
	return n


func _finish() -> void:
	print("[%s] %s (%d falhas)" % [my_name, "NETTEST OK" if fails == 0 else "NETTEST FALHOU", fails])
	Network.leave()
	get_tree().quit(1 if fails > 0 else 0)
