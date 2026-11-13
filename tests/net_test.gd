extends Node
## Teste do multiplayer: entra num servidor como cliente headless e verifica a sincronia.
##   godot --headless --path . -- --server --port=7777                      (terminal 1)
##   godot --headless --path . -- --nettest=127.0.0.1:7777 [--peers=2] [--name=A]   (terminal 2, 3...)
## --peers=N espera ver N-1 outros jogadores. Sai com código 0 (ok) ou 1 (falhas).

var fails := 0
var address := "127.0.0.1"
var peers := 1
var my_name := "Teste"


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
	await wait(1.5)
	var w: Node = Network.world
	check(Network.enemies.size() >= 15, "inimigos replicados do servidor (%d)" % Network.enemies.size())
	var e0: Enemy = Network.enemies.values()[0]
	check(e0.puppet, "inimigos no cliente são réplicas")
	print("[%s] fps cliente: %d" % [my_name, Engine.get_frames_per_second()])
	var n0 := Network.snapshots_received
	await wait(2.0)
	var rate := (Network.snapshots_received - n0) / 2.0
	check(rate >= Network.SEND_RATE * 0.75, "recebendo snapshots dos inimigos (%.1f/s)" % rate)

	# outros jogadores aparecem e se mexem
	if peers > 1:
		t = 0.0
		while Network.remote_players.size() < peers - 1 and t < 10.0:
			await wait(0.2)
			t += 0.2
		check(Network.remote_players.size() == peers - 1, "vê os outros jogadores (%d)" % Network.remote_players.size())

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

	# fica um pouco para os outros testes verem este jogador
	await wait(3.0 if peers > 1 else 0.5)
	_finish()


func _finish() -> void:
	print("[%s] %s (%d falhas)" % [my_name, "NETTEST OK" if fails == 0 else "NETTEST FALHOU", fails])
	Network.leave()
	get_tree().quit(1 if fails > 0 else 0)
