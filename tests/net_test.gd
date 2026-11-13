extends Node
## Teste do multiplayer: entra num servidor como cliente headless e verifica a sincronia.
##   godot --headless --path . -- --server --port=7777                      (terminal 1)
##   godot --headless --path . -- --nettest=127.0.0.1:7777 [--peers=2] [--name=A]   (terminal 2, 3...)
## --peers=N espera ver N-1 outros jogadores. Sai com código 0 (ok) ou 1 (falhas).
## --probe: só entra, confere versão e snapshots e sai (usado pelo CI contra o servidor público).
## --horde=lead|join: testa o Desafio da Horda em grupo (lead abre o portal, join aceita o convite).
##   Use com o servidor em --horde-round=8 para as rodadas não demorarem.

var fails := 0
var address := "127.0.0.1"
var peers := 1
var my_name := "Teste"
var probe := false
var horde_role := ""


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
	Game.save_path = "user://nettest_%s.json" % my_name
	Game.new_game()
	var failed := [""]
	Network.join_failed.connect(func(r: String) -> void: failed[0] = r)
	Network.join(address, my_name)

	var t := 0.0
	while Network.world == null and failed[0] == "" and t < 15.0:
		await wait(0.2)
		t += 0.2
	check(failed[0] == "", "conectou sem erro %s" % failed[0])
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
			# força o gatilho: um acerto da aura num inimigo dispara o combo
			sv.weapons._combo_cd.clear()
			var c0: int = sv.combos_done
			for e in Network.enemies.values():
				if is_instance_valid(e) and e.horde and not e.dead:
					sv.weapons._combo("aura", e.global_position)
					break
			check(sv.combos_done == c0 + 1, "acerto da arma dispara o combo")

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


func _finish() -> void:
	print("[%s] %s (%d falhas)" % [my_name, "NETTEST OK" if fails == 0 else "NETTEST FALHOU", fails])
	Network.leave()
	get_tree().quit(1 if fails > 0 else 0)
