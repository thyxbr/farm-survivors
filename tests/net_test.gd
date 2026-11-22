extends Node
## Teste do multiplayer: entra num servidor como cliente headless e verifica a sincronia.
##   godot --headless --path . -- --server --port=7777 --http-port=8790 --db=<banco novo>      (terminal 1)
##   godot --headless --path . -- --nettest=127.0.0.1:7777 --auth-url=http://127.0.0.1:8790 [--peers=2] [--name=Ana]
## --name é o usuário da conta de teste (senha fixa TEST_PASS): o teste cadastra (409 é ok), loga e entra com o token.
## --peers=N espera ver N-1 outros jogadores. Sai com código 0 (ok) ou 1 (falhas).
## --probe: sem conta, confere GET /health (versão) e se uma conexão ENet na porta UDP conecta (CI contra o servidor público).
## --relogin: no fim, abre uma segunda conexão (outro processo, mesmo token) e espera esta ser derrubada.
## --token=T: entra direto com o token (é o processo da segunda conexão do --relogin).
## --expect-clock-offset=N: o servidor está com --clock-offset=N; confere que o relógio do mundo segue o dele.
## Todos os modos começam na vila: os outros jogadores e os emotes deles, recordes, Ecos de teste e passiva.
## --horde=lead|join: testa o Desafio da Horda em grupo (lead abre a fila; join recebe o convite e aceita).
##   A arena é um mapa à parte (world.ARENA, fora de Valdoria); no fim todos voltam à vila, na frente do portal.
##   Use com o servidor em --horde-round=8 --horde-pick=5 para as rodadas e escolhas não demorarem.

var fails := 0
var address := "127.0.0.1"
var peers := 1
var my_name := "Teste"
var probe := false
var horde_role := ""
var chat_got: Array = []   # [nome, texto]
var whispers: Array = []   # [de, para, texto, recebido]
var relogin := false
var token := ""
var join_error := ""

## --expect-clock-offset=N: o servidor roda com --clock-offset=N (relógio adiantado N s).
var expect_clock := 0.0

const TEST_PASS := "teste-1234"
const PICKUP := preload("res://scripts/world/pickup.gd")

## [op, ok, err] de cada Econ.result recebido (os testes do Econ esperam a resposta do servidor por aqui).
var econ_log: Array = []
## Estados mandados pelo servidor sem pedido (concessões: abate, loot, prêmios).
var pushes := 0


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
		elif a == "--relogin":
			relogin = true
		elif a.begins_with("--token="):
			token = a.substr(8)
		elif a.begins_with("--expect-clock-offset="):
			expect_clock = a.substr(22).to_float()
	if probe:
		await _probe()
		_finish()
		return
	var second := token != ""   # processo da segunda conexão do --relogin
	Network.chat_received.connect(func(from: String, text: String) -> void: chat_got.append([from, text]))
	Network.join_failed.connect(func(r: String) -> void: join_error = r)
	# o personagem vem do servidor; o save solo deste processo de teste fica num arquivo à parte
	Econ.solo_save_path = "user://nettest_solo_%s%s.json" % [my_name, "_2" if second else ""]
	Econ.result.connect(func(op: String, ok: bool, err: String) -> void:
		econ_log.append([op, ok, err])
		if op == "push":
			pushes += 1)
	if not second:
		var reg: Dictionary = await Auth.register(address, my_name, TEST_PASS)
		check(reg.ok or reg.err == "nome_em_uso", "cadastro da conta de teste (%s)" % reg.get("err", "201"))
		var log_r: Dictionary = await Auth.login(address, my_name, TEST_PASS)
		check(log_r.ok and str(log_r.get("token", "")) != "", "login devolve token (%s)" % log_r.get("err", "ok"))
		if not log_r.ok:
			_finish()
			return
		token = log_r.token
		if relogin:
			await _test_bad_token()
		if horde_role == "lead":
			await _test_character_select()
	Network.join(address, token)

	# todo mundo chega direto na vila
	var t := 0.0
	while not _in_village() and join_error == "" and t < 20.0:
		await wait(0.2)
		t += 0.2
	check(join_error == "", "conectou sem erro %s" % join_error)
	check(_in_village(), "chegou à vila")
	if not _in_village():
		_finish()
		return
	# o herói criado sozinho pelo teste leva o nome da conta
	check(Network.my_name == my_name, "nome no jogo é o do herói (%s)" % Network.my_name)
	# estação, hora do jogo e clima seguem o relógio do servidor (o servidor pode rodar com
	# --clock-offset=N para simular um relógio diferente; o cliente recebe --expect-clock-offset=N)
	check(Weather.synced, "recebeu o relógio do servidor")
	var want := Time.get_unix_time_from_system() + expect_clock
	check(absf(Weather.now() - want) < 3.0, "relógio do mundo = do servidor (diferença %.1f s)" % (Weather.now() - want))
	check(Weather.season == SeasonRules.kind_at(want), "mesma estação do servidor (%s)" % Weather.season_name())
	var me_info: Dictionary = Network.players.get(multiplayer.get_unique_id(), {})
	check(int(me_info.get("account", 0)) > 0, "servidor associou a conta ao jogador (%s)" % str(me_info.get("account")))
	if second:
		var same := 0
		for pid in Network.players:
			if Network.players[pid].name == my_name:
				same += 1
		check(same == 1, "só uma sessão da conta no servidor (%d)" % same)
		await wait(1.0)
		_finish()
		return
	check(await _wait_until(func() -> bool: return Network.zone_of(multiplayer.get_unique_id()) == "world", 5.0),
		"servidor vê o jogador na vila")
	await _test_village()
	t = 0.0
	while Network.world == null and t < 15.0:
		await wait(0.2)
		t += 0.2
	check(Network.world != null and Network.world.player != null, "entrou no mundo com personagem local")
	if Network.world == null:
		_finish()
		return
	# personagem novo não tem equipamento de combate: só a arma da classe que o --nettest escolheu (guerreiro),
	# além da picareta e do machado de pedra; pede ao servidor (--test) o kit das três classes de arma
	check(Game.char_class == "warrior" and Game.equipment.weapon == "azure_edge"
		and Game.equipment.pickaxe == "pickaxe_stone" and Game.equipment.axe == "axe_stone"
		and Game.equipment.keys().filter(func(k) -> bool: return Game.equipment[k] != "" and not (k in ItemDB.TOOL_SLOTS)).size() == 1,
		"personagem novo começa só com a arma da classe (%s, %s)" % [Game.char_class, Game.equipment.weapon])
	Econ.request_test_items({"azure_edge": 1, "apprentice_staff": 1, "short_bow": 1, "leather_boots": 1})
	check(await _wait_until(func() -> bool: return Game.count_item("short_bow") == 1 and Game.count_item("leather_boots") == 1, 5.0),
		"kit de teste recebido do servidor")
	# equipa arco e botas (nível 1: o capuz pede nível 2) logo ao entrar: os outros jogadores devem ver esse visual
	await _pick_class("archer", "short_bow")
	Game.equip("leather_boots")
	await wait(1.5)
	var w: Node = Network.world
	check(w.player.look["class"] == "bow", "arco equipado no personagem local")
	check(Game.body == my_body() and KnightLook.body_of(w.player.model) == my_body(), "corpo local %s com o modelo dele" % my_body())
	check(Network.enemies.size() >= 15, "inimigos replicados do servidor (%d)" % Network.enemies.size())
	var e0: Enemy = Network.enemies.values()[0]
	check(e0.puppet, "inimigos no cliente são réplicas")
	print("[%s] fps cliente: %d" % [my_name, Engine.get_frames_per_second()])
	var n0 := Network.snapshots_received
	await wait(2.0)
	var rate := (Network.snapshots_received - n0) / 2.0
	check(rate >= Network.SEND_RATE * 0.75, "recebendo snapshots dos inimigos (%.1f/s)" % rate)
	# relatório periódico de vida e posição: o personagem é gravado no servidor sem o jogador sair
	var rep0 := Econ.reports_sent
	Network.autosave_interval = 1.0
	Network._autosave_t = 1.0
	await wait(1.6)
	check(Econ.reports_sent > rep0, "relatório periódico de vida e posição enviado ao servidor")
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
			check(rp.look["class"] == "bow" and rp._last_look.get("feet", "") == "leather_boots",
				"vê o arco e as botas de %s" % rp.display_name)
			# Ana joga com o corpo feminino (_pick_class); Beto com o masculino
			var want_body := "f" if rp.display_name == "Ana" else "m"
			check(rp._last_look.get("body", "") == want_body, "o corpo escolhido (%s) chega na réplica de %s" % [want_body, rp.display_name])
			check(KnightLook.body_of(rp.model) == want_body
				and (rp.model.get_meta("ponytail", null) != null) == (want_body == "f"),   # rabo de cavalo do penteado padrão f_longo
				"réplica de %s com o modelo do corpo %s" % [rp.display_name, want_body])
			var holder: Node3D = rp.look.get("holder")
			check(holder != null and is_instance_valid(holder), "modelo do arco montado na réplica de %s" % rp.display_name)

	# título: o próprio nome (do herói) em cima da cabeça; o título escolhido aparece acima dele para todos
	check(w.player.name_tag != null and w.player.name_tag.text == my_name, "o próprio nome do herói acima da cabeça")
	Game.set_title("recem_chegado")
	var own_title := func() -> bool:
		return w.player.title_tag.visible and w.player.title_tag.text.contains("Recém-chegado")
	check(await _wait_until(own_title, 5.0), "o próprio título acima do nome")
	if peers > 1:
		check(await _wait_until(func() -> bool:
			for rp in Network.remote_players.values():
				if rp.display_title != "Recém-chegado" or not rp.title_tag.visible:
					return false
			return true, 8.0), "vê o título dos outros jogadores acima do nome")

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
		# as coletas contam desde antes do abate: o ímã pode pedir a coleta antes de o teste olhar o chão
		var inv0 := _inv_total()
		var from := econ_log.size()
		# o servidor só aceita acerto perto da última posição recebida do jogador (HitGuard): espera ela chegar
		await wait(0.3)
		target.take_damage(10.0, w.player.global_position, false)
		await wait(0.6)
		check(target.hp < hp0, "dano chega ao servidor e volta no snapshot (%.0f → %.0f)" % [hp0, target.hp])
		# afinidade elemental (ElementRules): o servidor aplica o % da ficha; slime leva 90% de físico e 125% de fogo
		var hp1 := target.hp
		target.take_damage(10.0, w.player.global_position, false, 0.0, 0.0, 0.0, "fogo")
		await wait(0.6)
		var ratio := (hp1 - target.hp) / maxf(hp0 - hp1, 0.001)
		check(absf(ratio - 1.25 / 0.9) < 0.05, "fogo no slime pelo servidor: %.2fx o físico (esperado %.2f)" % [ratio, 1.25 / 0.9])
		target.take_damage(9999.0, w.player.global_position, false)
		await wait(0.8)
		check(not is_instance_valid(target) or target.dead, "slime morreu em todos")
		# XP, abate e loot vêm do servidor: o espelho só muda pelo estado que ele manda (push do Econ)
		check(await _wait_until(func() -> bool: return Game.kills == kills0 + 1, 3.0)
			and Game.xp + Game.level * 100000 > xp0, "servidor deu XP e abate (%d abates, push %d)" % [Game.kills, pushes])
		check(pushes > 0, "estado novo chegou do servidor sem pedido (push)")
		# o pickup é do servidor: aparece com net_id e, ao pegar (o ímã coleta, o jogador está ao lado),
		# o servidor confere e concede
		var seen := [0]
		await _wait_until(func() -> bool:
			for n in w.get_children():
				if n.get_script() == PICKUP and int(n.net_id) > 0:
					seen[0] = maxi(seen[0], int(n.net_id))
			return seen[0] > 0 or _claims_ok(from) > 0, 3.0)
		check(seen[0] > 0 or _claims_ok(from) > 0, "pickup do servidor apareceu (net_id %d)" % seen[0])
		for n in w.get_children():
			if n.get_script() == PICKUP and int(n.net_id) > 0:
				n.global_position = w.player.global_position + Vector3.UP * 0.8   # garante a coleta
		check(await _wait_until(func() -> bool: return _claims_ok(from) > 0 and Game.gold > gold0, 5.0),
			"pegou o loot pessoal: servidor concede ouro (%d → %d, itens %d → %d)" % [gold0, Game.gold, inv0, _inv_total()])
		await wait(0.5)
		var pending := 0
		for n in w.get_children():
			if n.get_script() == PICKUP and int(n.net_id) > 0:
				pending += 1
		check(pending == 0 or _claims_ok(from) >= 1, "pickups coletados (%d no chão)" % pending)

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
	# cajado (o do kit de teste: o cliente online não se dá itens): troca pedida ao servidor
	await _pick_class("mage", "apprentice_staff")
	check(await _wait_until(func() -> bool: return Game.equipment.weapon == "apprentice_staff", 3.0)
		and w.player.look["class"] == "staff", "trocou para o cajado")
	await wait(0.6)
	if peers > 1:
		# cada um troca no próprio ritmo (o colega pode ainda estar no loot): espera a troca chegar
		for rp in Network.remote_players.values():
			check(await _wait_until(func() -> bool: return rp.look["class"] == "staff", 10.0),
				"vê %s trocar para cajado" % rp.display_name)
			var keep := "f" if rp.display_name == "Ana" else "m"
			check(KnightLook.body_of(rp.model) == keep and rp._last_look.get("body", "") == keep,
				"trocar a arma não muda o corpo da réplica de %s (%s)" % [rp.display_name, keep])
	# efeitos visuais: auras de habilidade (declaradas pelo cliente) e encanto (decidido pelo servidor).
	# Ficam ligados até o fim: o colega chega a este ponto no ritmo dele e precisa encontrá-los.
	w.player.set_ability_aura("escudo", true)
	w.player.set_ability_aura("vento", true)
	Econ.request_test_gold(50)
	Econ.request_test_items({"iron_ore": 4, "frost_drop": 2, "hide_t1": 2, "slime_gel": 1})
	await wait(0.5)
	# craft decidido pelo servidor: essência da alquimia gasta os materiais e dá XP de Alquimia
	var ess0 := Game.count_item("essence_t1")
	Game.craft("essence_t1", 1)
	check(await _wait_until(func() -> bool: return Game.count_item("essence_t1") == ess0 + 1 and Game.prof_xp("alchemy") > 0, 5.0),
		"servidor fabricou a essência e deu XP de Alquimia")
	var wid: String = Game.equipment.weapon
	Econ.request("enchant", ["gelo"])
	check(await _wait_until(func() -> bool: return Game.weapon_enchant() == {"el": "gelo", "lv": 1}, 5.0),
		"servidor encantou a arma equipada")
	check(await _wait_until(func() -> bool:
		var fx: Dictionary = w.player._last_look.get("fx", {})
		return fx.get("auras", []) == ["escudo", "vento"] and fx.get("en", "") == "gelo" and fx.get("lv", 0) == 1, 3.0),
		"auras de habilidade + encanto no visual local")
	check(w.player.look["class"] == "staff" and w.player.look["holder"] != null, "trocar só os efeitos não desmonta a arma")
	# o cliente não consegue declarar um encanto que o servidor não gravou
	var fake: Dictionary = w.player._last_look.duplicate(true)
	fake["fx"]["en"] = "sombra"
	fake["fx"]["lv"] = 5
	Network.send_look(fake)
	# desequipar apaga o brilho; equipar de novo traz o encanto de volta (ele é do tipo de arma)
	Econ.request("unequip", ["weapon"])
	check(await _wait_until(func() -> bool:
		return Game.equipment.weapon == "" and w.player._last_look.get("fx", {}).get("lv", -1) == 0, 5.0),
		"sem arma: sem brilho no jogador")
	Econ.request("equip", [wid])
	check(await _wait_until(func() -> bool: return w.player._last_look.get("fx", {}).get("lv", 0) == 1, 5.0),
		"arma de volta: o encanto volta com ela")
	if peers > 1:
		# espera o colega passar pelos mesmos passos; o estado final de cada um é gelo +1
		check(await _wait_until(func() -> bool:
			for rp in Network.remote_players.values():
				var fx: Dictionary = rp._last_look.get("fx", {})
				if fx.get("auras", []) != ["escudo", "vento"] or fx.get("en", "") != "gelo" or fx.get("lv", 0) != 1:
					return false
			return true, 20.0), "vê as auras e o encanto dos outros jogadores (o encanto falso foi ignorado)")
		for rp in Network.remote_players.values():
			check(rp.vfx_aura != null and rp.vfx_aura.styles() == ["escudo", "vento"], "aura montada na réplica de %s" % rp.display_name)
			var hold: Node3D = rp.look.get("holder")
			var mis: Array = hold.find_children("*", "MeshInstance3D", true, false) if hold else []
			check(not mis.is_empty() and mis[0].material_overlay != null, "encanto aplicado na arma da réplica de %s" % rp.display_name)

	# coleta de ferro: o servidor confere a distância e o tempo de volta do veio. Os veios são do mundo: cada
	# jogador coleta um diferente (Ana o 0, Beto o 1) e o veio que o outro coletou some para ele também
	var mine := 0 if my_name == "Ana" else 1
	var theirs := 1 - mine
	var ore0 := Game.count_item("iron_ore")
	var here: Vector3 = w.player.global_position
	Econ.gather_node(mine, here)
	await wait(0.8)
	check(Game.count_item("iron_ore") == ore0, "coleta de longe é recusada pelo servidor")
	w.player.global_position = WorldHarvest.node_def(Balance.tables, mine).pos + Vector3(1.5, 0.4, 0)
	await wait(0.8)   # a posição nova chega ao servidor
	Econ.gather_node(mine, w.player.global_position)
	check(await _wait_until(func() -> bool: return Game.count_item("iron_ore") == ore0 + 3, 5.0),
		"coleta perto do veio concede 3 minérios")
	Econ.gather_node(mine, w.player.global_position)
	await wait(0.8)
	check(Game.count_item("iron_ore") == ore0 + 3, "veio esgotado não concede de novo")
	if peers > 1:
		var other_node = w.resource_by_id.get(theirs)
		check(await _wait_until(func() -> bool: return other_node != null and not other_node.alive, 8.0),
			"o veio que o colega coletou sumiu para mim também")
		w.player.global_position = WorldHarvest.node_def(Balance.tables, theirs).pos + Vector3(1.5, 0.4, 0)
		await wait(0.8)
		Econ.gather_node(theirs, w.player.global_position)
		await wait(0.8)
		check(Game.count_item("iron_ore") == ore0 + 3, "o servidor recusa o veio que o colega já levou")
	w.player.global_position = here
	await wait(0.3)

	# marca de veneno adulterada: o servidor limita ao maior valor da tabela (12%).
	# Cada cliente usa um alvo só seu, para o colega não mexer na mesma vida.
	var mark_kind := "goblin_dourado" if my_name == "Ana" else "goblin_campeao"
	var vt: Enemy = null
	for en in Network.enemies.values():
		if is_instance_valid(en) and not en.dead and en.kind == mark_kind:
			vt = en
			break
	check(vt != null, "achou um %s para a marca de veneno" % mark_kind)
	# Daqui até a cura na vila os dois ficam no campo, parados, vendo um ao outro (marca, espada, arco e
	# cajado): os monstros de lá têm nível e batem forte, e o Beto chegava morto ao teste da cura (o servidor
	# não cura caído, e a tela de morte ficava no lugar do livro do grupo). Nenhuma checagem do trecho usa a
	# vida do jogador; _test_heal tira a imunidade ao chegar na vila.
	w.player.invuln = 600.0
	if vt != null:
		var before_mark: Vector3 = w.player.global_position
		var mark_level: int = vt.level
		w.player.global_position = vt.global_position + Vector3(4, 0.4, 0)
		await wait(0.8)   # a posição nova chega ao servidor
		Network.client_mark_enemy(vt.net_id, 5.0, 99.0)
		await wait(0.6)
		var vh: float = vt.hp
		vt.take_damage(10.0, w.player.global_position, false)
		await _wait_until(func() -> bool: return not is_instance_valid(vt) or vt.hp < vh, 4.0)
		var drop: float = vh - vt.hp if is_instance_valid(vt) else 0.0
		# monstro bem acima do nível de quem bate leva menos (placa vermelha, ProgressionRules.danger_mults):
		# os 12% da marca valem sobre o dano já reduzido
		# e a afinidade ao físico do monstro (ElementRules: dourado 110%, campeão 75%) também
		var taken := float(ProgressionRules.danger_mults(Balance.tables, mark_level, Game.level).taken) 			* ElementRules.mult(Balance.tables, mark_kind, "fisico")
		check(drop > 10.5 * taken and drop < 12.5 * taken,
			"marca de veneno adulterada é limitada a 12%% (10 de dano tirou %.1f; nível %d contra %d leva x%.2f)" % [drop, mark_level, Game.level, taken])
		w.player.global_position = before_mark
		await wait(0.3)

	if my_name == "Ana":
		await _test_econ()

	if peers > 1:
		await _test_sword(w)
		await _test_bow_staff(w)
		await _test_heal(w)
		await _test_party(w)
		await _test_social(w)
		await _test_gather_lock(w)
		await _test_burrow(w)

	if horde_role != "" and Game.HORDE_ENABLED:   # --horde=lead|join também separa quem age nos outros testes
		await _test_horde(w)

	# fica um pouco para os outros testes verem este jogador
	await wait(3.0 if peers > 1 else 0.5)
	if my_name == "Ana":
		await _test_reconnect_keeps_state()
	if relogin:
		await _test_second_login_kicks_first()
	_finish()


# ---------------------------------------------------------------- trava da coleta
var _holding := false


## Veio da trava (2: os veios 0 e 1 já foram coletados antes neste teste e estão esgotados).
const LOCK_NODE := 2


## Trava da coleta: enquanto Ana bate no veio 2 (reserva renovada a cada golpe), Beto vê o veio ocupado e o aviso de
## F recusa; quando Ana larga, o veio fica livre para ele. O servidor recusa a reserva de Beto no meio.
func _test_gather_lock(w: Node) -> void:
	await _sync("trava")
	if my_name == "Ana":
		_holding = true
		_keep_claim(LOCK_NODE)
	else:
		check(await _wait_until(func() -> bool: return Econ.node_busy(LOCK_NODE), 6.0), "veio em que Ana bate aparece ocupado")
		var n = w.resource_by_id.get(LOCK_NODE)
		check(n != null and not n.gather_plan().ok and n.gather_plan().msg == Econ.BUSY_TEXT,
			"F no veio ocupado avisa que outro jogador está coletando")
		Econ.claim_node(LOCK_NODE)   # o servidor recusa: a reserva continua de Ana
		await wait(0.5)
	await _sync("trava_vista")
	if my_name == "Ana":
		check(not Econ.node_busy(LOCK_NODE), "a reserva de Beto no meio foi recusada (o veio segue com Ana)")
		_holding = false
		Econ.release_node(LOCK_NODE)
	else:
		check(await _wait_until(func() -> bool: return not Econ.node_busy(LOCK_NODE), 6.0), "Ana largou: o veio fica livre")
	await _sync("trava_solta")


func _keep_claim(id: int) -> void:
	while _holding:
		Econ.claim_node(id)
		await wait(1.0)


# ---------------------------------------------------------------- Toupeira-Broca na Mina
## Toupeira-Broca (Mina): a réplica no cliente esconde o modelo e tira a colisão enquanto o servidor diz que ela
## está cavando, e mostra de novo quando ela emerge. Só Ana vai à Mina; Beto espera na barreira.
## Ana fica imune enquanto está lá (`invuln`, que vale também para o dano mandado pelo servidor): os fossos têm
## bandos de Toupeiras e outros monstros do nível 25, e morta ela voltaria para a vila (e não abriria a fila da
## Horda, que vem depois). O teste confere a réplica, não a sobrevivência no fosso.
func _test_burrow(w: Node) -> void:
	if my_name == "Ana":
		var back: Vector3 = w.player.global_position
		w.player.invuln = 999.0
		w.player.global_position = Regions.arrive_point("mina")
		await wait(1.5)
		var mole: Enemy = null
		var best := INF
		for e in Network.enemies.values():
			if is_instance_valid(e) and e.kind == "toupeira" and not e.dead:
				var d: float = e.global_position.distance_to(w.player.global_position)
				if d < best:
					best = d
					mole = e
		check(mole != null, "há uma Toupeira-Broca na Mina para o teste de cavar")
		if mole != null:
			# a meia distância (entre dig_min e dig_max): ela vê, espera a janela na superfície e cava. A réplica
			# longe da câmera fica congelada (Enemy.still) com a posição velha: a posição real é a do snapshot
			# (_net_pos), e a Ana se reposiciona se a Toupeira andar para fora da faixa
			var dug := false
			for i in 40:
				var real: Vector3 = mole._net_pos
				var d := Vector2(w.player.global_position.x - real.x, w.player.global_position.z - real.z).length()
				if i == 0 or d < 5.0 or d > 12.0:
					w.player.global_position = real + Vector3(8, 0.5, 0)
				await wait(0.25)
				if mole.state == "burrow":
					dug = true
					break
			check(dug, "a Toupeira cava (estado burrow chega ao cliente)")
			if dug:
				check(not mole.model.visible and mole.collision_layer == 0,
					"réplica enterrada: modelo escondido e sem colisão")
			# sai de perto: ela emerge pelo tempo (dig_max_secs) longe daqui, sem matar a Ana (morta não abre a
			# fila da Horda, que vem depois)
			w.player.global_position = mole.global_position + Vector3(40, 0.5, 0)
			var out := await _wait_until(func() -> bool: return mole.model.visible, 8.0)
			check(out and mole.collision_layer != 0, "réplica emerge: modelo e colisão de volta")
		w.player.global_position = back
		await wait(1.0)
		w.player.invuln = 0.0
		check(not w.player.dead, "Ana volta viva da Mina")
	await _sync("burrow_done")


# ---------------------------------------------------------------- habilidades da espada replicadas
## Quem não é "join" (Ana) usa as três habilidades; o outro (Beto) vê a réplica de Ana entrar em cada uma.
## Que o servidor dedicado não cria nós de efeito não dá para ver daqui (o cliente só enxerga os próprios nós):
## isso é conferido no smoke test (FX._scene() nulo com Network.mode == SERVER).
func _test_sword(w: Node) -> void:
	# a espada inicial voltou para a mochila quando o cajado foi equipado (o cliente online não se dá itens)
	await _pick_class("warrior", "azure_edge")
	await _wait_until(func() -> bool: return Game.equipment.weapon == "azure_edge", 3.0)
	await wait(1.0)
	await wait(Network.CHAT_WINDOW)   # o anti-spam do chat (teste anterior) precisa esvaziar para os avisos de sincronia passarem
	await _sync("sword_in")
	var actor := horde_role != "join"
	var lvl0 := Game.level
	if actor:
		Game.level = 8
		Game.fury = 100.0
		await wait(0.5)
		for id in ["sword_charge", "sword_quake", "sword_whirl"]:
			check(SwordAbilities.use(w.player, id), "%s começa" % id)
			await wait(0.3)
			await _wait_until(func() -> bool: return w.player.ability == "", 4.0)
			await wait(0.4)
		check(w.player.ability == "", "habilidades da espada terminam")
	else:
		var seen := {}
		var rp = Network.remote_players.values()[0]
		var t := 0.0
		while t < 9.0 and seen.size() < 3:
			var a: String = rp.ability
			if a != "":
				seen[a] = true
			await wait(0.05)
			t += 0.05
		for id in ["sword_charge", "sword_quake", "sword_whirl"]:
			check(seen.has(id), "réplica de %s entrou em %s (%s)" % [rp.display_name, id, str(seen.keys())])
		await wait(2.5)
		check(rp.ability == "", "réplica sai do estado de habilidade ao terminar")
		# (fúria e vida de Beto podem mudar por causa dos inimigos do mundo; o que não pode é a réplica o pôr em habilidade)
		check(w.player.ability == "" and Game.level == lvl0,
			"habilidade da réplica não afeta o meu jogador (nível %d)" % Game.level)
	await _sync("sword_out")
	if actor:
		Game.level = lvl0
		Game.fury = 0.0


# ---------------------------------------------------------------- habilidades do arco e do cajado replicadas
## Mesmo esquema do teste da espada: Ana usa Tiro Triplo, Flecha Glacial, Flecha do Vendaval (arco) e Chuva de
## Meteoros (cajado, soltando a tecla por código); Beto vê a réplica de Ana entrar em cada uma e voltar ao normal.
const BOW_STAFF_IDS := ["bow_triple", "bow_frost", "bow_gale", "meteor_rain"]

func _test_bow_staff(w: Node) -> void:
	await _sync("bow_in")
	var actor := horde_role != "join"
	var lvl0 := Game.level
	if actor:
		await _pick_class("archer", "short_bow")
		check(await _wait_until(func() -> bool: return Game.equipment.weapon == "short_bow", 3.0)
			and w.player.look["class"] == "bow", "Ana trocou para o arco")
		Game.level = 8
		Game.fury = 100.0
		await wait(1.0)
		# slot 1 e 2 (ficam sozinhas); slot 4 (ultimate) com fúria cheia e carga solta por código
		for slot in [1, 2, 4]:
			Game.fury = 100.0
			w.player.use_slot(slot)
			check(w.player.ability != "", "habilidade do arco no slot %d começa (%s)" % [slot, w.player.ability])
			if slot == 4:
				await wait(0.8)
				BowAbilities.release(w.player)
			await wait(0.3)
			check(await _wait_until(func() -> bool: return w.player.ability == "", 4.0), "habilidade do slot %d termina" % slot)
			await wait(0.4)
		await _pick_class("mage", "apprentice_staff")
		check(await _wait_until(func() -> bool: return Game.equipment.weapon == "apprentice_staff", 3.0)
			and w.player.look["class"] == "staff", "Ana voltou para o cajado")
		await wait(0.6)
		Game.level = 8   # a troca de arma devolve o estado do servidor (nível 1): reaplica
		Game.fury = 100.0
		w.player.use_slot(4)
		check(w.player.ability == "meteor_rain", "Chuva de Meteoros começa (%s)" % w.player.ability)
		await wait(2.0)   # 0.5 s de preparo + ~1.5 s de chuva
		StaffAbilities.release(w.player)
		check(await _wait_until(func() -> bool: return w.player.ability == "", 4.0), "Chuva de Meteoros termina ao soltar")
		await wait(0.5)
	else:
		var seen := {}
		var rp = Network.remote_players.values()[0]
		var t := 0.0
		while t < 16.0 and seen.size() < BOW_STAFF_IDS.size():
			var a: String = rp.ability
			if a != "":
				seen[a] = true
			await wait(0.05)
			t += 0.05
		for id in BOW_STAFF_IDS:
			check(seen.has(id), "réplica de %s entrou em %s (%s)" % [rp.display_name, id, str(seen.keys())])
		check(await _wait_until(func() -> bool: return rp.ability == "", 4.0), "réplica sai do estado de habilidade ao terminar")
		check(w.player.ability == "" and Game.level == lvl0,
			"habilidade do arco/cajado da réplica não afeta o meu jogador (nível %d)" % Game.level)
	await _sync("bow_out")
	if actor:
		Game.level = lvl0
		Game.fury = 0.0
		await _pick_class("mage", "apprentice_staff")


# ---------------------------------------------------------------- cura do healer em aliados
## Ana vira healer, Beto (guerreiro) fica ferido perto dela. Beto pedindo a cura direto não faz nada (não é
## healer); Ana mira a Cura no Beto e só a vida dele sobe; depois cura a si mesma (uma vez só: vem do servidor).
func _test_heal(w: Node) -> void:
	await _sync("heal_in")
	var actor := horde_role != "join"
	if actor:
		await _pick_class("healer", "sc_novice_scepter")
		check(Game.char_class == "healer", "Ana virou healer")
	w.player.global_position = w.VILLAGE_SPAWN + Vector3(2.0 if actor else -2.0, 0, 0)
	w.player.invuln = 0.0   # na vila (zona da guarda) não há monstro; a imunidade vinha do trecho do campo
	await wait(0.6)
	Game.hp = 10.0
	Game.mp = Game.max_mp()
	await wait(1.2)   # o servidor recebe a posição e a vida baixa fica registrada
	await _sync("heal_ready")
	var hp0 := Game.hp
	if not actor:
		Network.request_heal()   # guerreiro: o servidor recusa
	await wait(1.2)
	check(Game.hp <= hp0 + 3.0, "pedido de cura de quem não é healer não faz nada (%.0f → %.0f)" % [hp0, Game.hp])
	await _sync("heal_denied")
	if actor:
		var expected := Game.heal_amount()
		var beto: Node3D = null
		for rp in Network.remote_players.values():
			if is_instance_valid(rp):
				beto = rp
				break
		check(beto != null, "Ana vê o Beto para mirar a cura")
		Game.hp = 10.0
		w.player.cast("heal")
		check(w.player.heal_armed, "a tecla da Cura só prepara")
		w.player.confirm_heal(beto)   # mirada no Beto: só ele recebe
		await wait(1.2)
		check(Game.hp < 10.0 + expected * 0.5, "a cura mirada no Beto não cura a Ana (%.0f)" % Game.hp)
		await wait(0.5)   # passa o intervalo mínimo do servidor (1,4 s)
		w.player.cooldowns.heal = 0.0
		Game.hp = 10.0
		w.player.cast("heal")
		w.player.confirm_heal()   # sem alvo: em si mesma
		check(await _wait_until(func() -> bool: return Game.hp > 10.5, 3.0), "Ana se cura pela cura do servidor (%.0f)" % Game.hp)
		await wait(1.0)
		check(Game.hp - 10.0 <= expected + 3.0, "a cura própria vem uma vez só (+%.0f, máximo %.0f)" % [Game.hp - 10.0, expected])
	else:
		check(await _wait_until(func() -> bool: return Game.hp > hp0 + 10.0, 3.0), "Beto recebe a cura de Ana (%.0f → %.0f)" % [hp0, Game.hp])
	await _sync("heal_out")
	# Escudo de Luz e Banquete do Herói: Ana pede, Beto (perto) recebe o buff; Beto pedindo não faz nada
	Game.clear_buffs(true)
	Game.hp = 10.0
	await _sync("ally_ready")
	if not actor:
		Network.request_ally_buff("scepter_ward")   # guerreiro: o servidor recusa
		await wait(1.2)
		check(not Game.has_buff("scepter_ward"), "pedido de buff de quem não é healer não faz nada")
	await _sync("ally_denied")
	if actor:
		Network.request_ally_buff("scepter_ward")
		check(await _wait_until(func() -> bool: return Game.has_buff("scepter_ward"), 3.0), "Ana recebe o próprio Escudo de Luz")
		Network.request_ally_buff("scepter_ward")   # de novo: o intervalo mínimo recusa
		Network.request_ally_buff("buff_inexistente")
	else:
		check(await _wait_until(func() -> bool: return Game.has_buff("scepter_ward"), 3.0), "Beto recebe o Escudo de Luz de Ana")
		check(not Game.has_buff("scepter_feast"), "o escudo não traz o Banquete")
	await _sync("ally_ward")
	if actor:
		Network.request_ally_buff("scepter_ult")
		check(await _wait_until(func() -> bool: return Game.has_buff("scepter_feast"), 3.0), "Ana recebe o Banquete do Herói")
	else:
		check(await _wait_until(func() -> bool: return Game.has_buff("scepter_feast"), 3.0), "Beto recebe o Banquete do Herói")
		check(await _wait_until(func() -> bool: return Game.hp >= Game.max_hp() - 0.5, 3.0), "o Banquete cura Beto ao máximo (%.0f/%.0f)" % [Game.hp, Game.max_hp()])
	await _sync("ally_out")
	Game.clear_buffs(true)
	if actor:
		await _pick_class("mage", "apprentice_staff")
	Game.hp = Game.max_hp()


# ---------------------------------------------------------------- vila
## Logo depois de conectar, todos na vila: os outros jogadores com o nome em cima, o emote chegando à
## réplica do outro cliente, a base e os recordes que o servidor manda ao montar Valdoria, Ecos de teste,
## Amigos e sussurro (com --peers=2): Ana pede amizade ao Beto pelo nome, Beto aceita; os dois se veem
## online na lista e na aba Amigos do livro; Ana sussurra, Beto responde com /r; Ana desfaz a amizade.
func _test_social(w: Node) -> void:
	Social.whisper.connect(func(from: String, to: String, text: String, incoming: bool) -> void:
		whispers.append([from, to, text, incoming]))
	await wait(Network.CHAT_WINDOW)
	await _sync("social_in")
	var other_name := "Beto" if my_name == "Ana" else "Ana"
	if my_name == "Ana" and Social.state_of("Beto") == "":
		Social.request_add("beto")   # o nome vale sem diferenciar maiúsculas
	if my_name == "Beto":
		check(await _wait_until(func() -> bool: return Social.state_of("Ana") in ["in", "accepted"], 8.0),
			"Beto recebeu o pedido de amizade (%s)" % str(Social.friends))
		for f in Social.friends:
			if f.name == "Ana" and f.state == "in":
				Social.accept(int(f.id))
	check(await _wait_until(func() -> bool:
		for f in Social.friends:
			if f.name == other_name and f.state == "accepted" and f.online and int(f.peer) != 0:
				return true
		return false, 12.0), "amizade aceita e o amigo aparece online (%s)" % str(Social.friends))
	# livro, aba Amigos: o amigo aparece e a página cabe
	w.open_world_map(2)
	var bk: Node = w.modal
	await wait(0.4)
	check(bk != null and bk._fr_right.get_child_count() >= 2, "aba Amigos lista o amigo")
	check(bk != null and bk.book.overflow_warnings == 0, "aba Amigos cabe no livro")
	# --shot-social=ARQUIVO (cliente com janela): foto da aba Amigos e da aba Grupo com dados de verdade
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-social=") and bk != null and DisplayServer.get_name() != "headless":
			await wait(1.0)
			get_viewport().get_texture().get_image().save_png(a.substr(14))
			bk.book.show_page(0)
			await wait(1.0)
			get_viewport().get_texture().get_image().save_png(a.substr(14).replace(".png", "_grupo.png"))
	if bk != null:
		bk.book.close()
	await _sync("social_friends")
	# sussurro: Ana manda, Beto responde pelo /r (o último que sussurrou)
	if my_name == "Ana":
		Social.send_whisper("beto", "oi Beto, só pra você")
	else:
		check(await _wait_until(func() -> bool:
			return whispers.any(func(x: Array) -> bool: return x[3] and x[0] == "Ana" and x[2] == "oi Beto, só pra você"), 6.0),
			"Beto recebeu o sussurro da Ana")
		check(Social.last_whisper_from == "Ana", "/r responde para a Ana")
		w.chat._run_command("/r Oi Ana!")
	check(await _wait_until(func() -> bool:
		return whispers.any(func(x: Array) -> bool: return x[2] == "Oi Ana!" and x[3] == (my_name == "Ana")), 6.0),
		"resposta do sussurro chegou (e o eco para quem mandou)")
	check(not chat_got.any(func(m: Array) -> bool: return str(m[1]).contains("só pra você")), "sussurro não vai para o chat geral")
	await _sync("social_whisper")
	if my_name == "Ana":
		for f in Social.friends:
			if f.name == "Beto":
				Social.remove(int(f.id))
	check(await _wait_until(func() -> bool: return Social.state_of(other_name) == "", 8.0), "amizade desfeita dos dois lados")
	await _sync("social_out")


## --shot-party=ARQUIVO (cliente com janela): foto da tela com o grupo formado (ARQUIVO_near.png, ARQUIVO_far.png).
func _shot_hud(w: Node, tag: String) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-party=") and DisplayServer.get_name() != "headless" and w.modal == null:
			await wait(1.2)
			get_viewport().get_texture().get_image().save_png(a.substr(13).replace(".png", "_%s.png" % tag))


## Grupo (com --peers=2): Ana convida, Beto aceita; os dois aparecem no grupo, na HUD e no filtro do mapa.
## Ana mata um slime com Beto ao lado: o XP é dividido e o abate conta na missão dos dois. Depois Beto vai
## para longe (outro mapa) e Ana mata outro: Beto ainda divide o XP, mas o abate não conta na missão dele.
func _test_party(w: Node) -> void:
	await wait(Network.CHAT_WINDOW)
	await _sync("party_in")
	var me := multiplayer.get_unique_id()
	var other: int = Network.remote_players.keys()[0] if not Network.remote_players.is_empty() else 0
	check(other != 0, "achou o colega para o grupo")
	if my_name == "Ana":
		Party.request_invite(other)
	else:
		check(await _wait_until(func() -> bool: return not Party.invite.is_empty(), 6.0), "recebeu o convite do grupo")
		Party.answer_invite(true)
	check(await _wait_until(func() -> bool: return Party.members.size() == 2, 6.0), "grupo com os dois (%s)" % str(Party.members))
	check(Party.is_member(other) and Party.am_leader() == (my_name == "Ana"), "colega no grupo e Ana lidera")
	check(MapRules.shown_players(Network.remote_players.keys(), Party.others(), me) == [other],
		"o mapa mostra o colega do grupo")
	check(await _wait_until(func() -> bool:
		return w.hud.party_frames != null and w.hud.party_frames._bars.has(other), 3.0), "quadro do colega na HUD")
	# vida, mana e buffs: Beto toma uma sopa apimentada; Ana vê o buff no quadro dele, com o tempo
	if my_name == "Beto":
		Game.add_buff("food_warm", 300.0)
	else:
		check(await _wait_until(func() -> bool:
			for m in Party.members:
				if int(m.peer) == other:
					return float(m.get("mp", -1.0)) > 0.0 and Party.buff_left(m, "food_warm") > 200.0
			return false, 8.0), "o servidor repassa a mana e o buff do colega (%s)" % str(Party.members))
		check(await _wait_until(func() -> bool: return w.hud.party_frames._bars[other].chips.has("food_warm"), 3.0),
			"ícone do buff do colega no quadro do grupo")
	await _shot_hud(w, "buff")
	# livro do grupo (P): o colega aparece com a vida e a aba cabe nas páginas
	w.open_world_map(1)
	var bk: Node = w.modal
	check(bk != null and bk._hp_bars.has(other), "livro do grupo lista o colega")
	await wait(0.3)
	if bk != null:
		check(bk.book.overflow_warnings == 0, "aba Grupo cabe no livro")
		bk.book.close()
	# mapa-mundi (M): o colega do grupo aparece no atlas
	w.open_world_map(0)
	var atlas_ui: Node = w.modal
	await wait(0.3)
	check(atlas_ui != null and atlas_ui.get("view") is AtlasView, "M abre o mapa-mundi em tela cheia")
	if atlas_ui != null:
		atlas_ui._close()
	check(w.modal == null, "livro fechado")
	Econ.request("start_quest", ["espantalho"])
	check(await _wait_until(func() -> bool: return Game.quest_state("espantalho") == "active", 4.0), "missão de slimes ativa")
	await _sync("party_ready")

	for phase in ["near", "far"]:
		await wait(Network.CHAT_WINDOW)   # as barreiras usam o chat: o anti-spam precisa esvaziar para o alvo passar
		var kills0 := Game.kills
		var prog0 := int(Game.quests.get("espantalho", {}).get("progress", 0))
		var xp0 := Game.xp + Game.level * 100000
		var lvl0 := Game.level
		var target: Enemy = null
		if my_name == "Ana":
			# o slime vivo mais perto da chegada da vila (o dos campos); não depende da ordem em que os pontos estão
			# na cena do mapa. Só slime de vida cheia e a mais de 10 m de Beto: com os bandos dos campos, um golpe
			# de Beto no slime vizinho (ele espera ao lado do alvo da fase "near") o faria receber o abate de longe
			var best := INF
			var others: Array = []
			for rp in Network.remote_players.values():
				if is_instance_valid(rp):
					others.append((rp as Node3D).global_position)
			for e in Network.enemies.values():
				if not (is_instance_valid(e) and e.kind == "slime" and not e.dead and e.hp >= e.max_hp):
					continue
				var clear := true
				for o in others:
					clear = clear and (o as Vector3).distance_to(e.global_position) > 10.0
				if clear:
					var d: float = e.global_position.distance_to(Vector3(0, 0, 6))
					if d < best:
						best = d
						target = e
			check(target != null, "achou um slime para o grupo (%s)" % phase)
			Network.send_chat("party_target:%d" % (target.net_id if target else 0))
		var tid := [0]
		check(await _wait_until(func() -> bool:
			for m in chat_got:
				if str(m[1]).begins_with("party_target:"):
					tid[0] = int(str(m[1]).get_slice(":", 1))
			return tid[0] > 0, 6.0), "alvo do grupo combinado (%s)" % phase)
		chat_got = chat_got.filter(func(m: Array) -> bool: return not str(m[1]).begins_with("party_target:"))
		var tgt: Enemy = Network.enemies.get(tid[0])
		if tgt == null or not is_instance_valid(tgt):
			check(false, "slime do grupo existe no cliente (%s)" % phase)
			return
		var tgt_reward := tgt.xp_reward()
		var tgt_level := tgt.level
		var at := tgt.global_position
		if my_name == "Ana":
			w.player.global_position = at + Vector3(0, 0.5, 3)
		elif phase == "near":
			w.player.global_position = at + Vector3(3, 0.5, 0)
		else:
			w.player.global_position = Regions.arrive_point("mina")   # outro mapa: bem longe do combate
		await wait(1.0)   # a posição nova chega ao servidor
		await _sync("party_%s_pos" % phase)
		if my_name == "Ana":
			tgt.take_damage(9999.0, w.player.global_position, false)
		check(await _wait_until(func() -> bool: return Game.xp + Game.level * 100000 > xp0, 5.0),
			"XP do abate dividido chega aos dois (%s)" % phase)
		await wait(0.8)
		var gained := Game.xp + Game.level * 100000 - xp0
		if Game.level == lvl0:   # subir de nível zera o XP da barra: aí só confere que subiu
			# perto e longe o XP leva o ajuste de nível (slime tem nível e xp_reward)
			var share := ceili(tgt_reward / 2.0)
			# premissa: Ana e Beto têm o mesmo nível (contas novas), então o maior nível do grupo é lvl0
			var expected := int(round(share * ProgressionRules.xp_diff_mult(Balance.tables, tgt_level, lvl0)))
			check(gained == expected, "metade do XP do slime (%d de %d, %s)" % [gained, tgt_reward, phase])
		var counted: bool = my_name == "Ana" or phase == "near"
		check(Game.kills == kills0 + (1 if counted else 0),
			"abate %s para %s (%s: %d → %d)" % ["conta" if counted else "não conta", my_name, phase, kills0, Game.kills])
		check(int(Game.quests.get("espantalho", {}).get("progress", 0)) == prog0 + (1 if counted else 0),
			"missão %s (%s)" % ["avança" if counted else "não avança de longe", phase])
		if my_name == "Ana" and phase == "far":
			var far_ok: bool = await _wait_until(func() -> bool: return str(w.hud.party_frames._bars[other].tag.text).begins_with("longe"), 3.0)
			var rp = Network.remote_players.get(other)
			check(far_ok, "HUD avisa que o colega está longe (aviso \"%s\", colega em %s, eu em %s)" % [
				w.hud.party_frames._bars[other].tag.text, str(rp.global_position) if rp != null and is_instance_valid(rp) else "-",
				str(w.player.global_position)])
		await _shot_hud(w, phase)
		await _sync("party_%s_done" % phase)
	w.player.global_position = Vector3(0, 0.5, 6)
	if my_name == "Ana":
		Party.request_leave()
	check(await _wait_until(func() -> bool: return not Party.in_party(), 5.0), "grupo desfeito quando Ana sai")
	await _sync("party_out")


## Logo depois de conectar, todos na vila: os outros jogadores com o nome em cima, o emote chegando à
## réplica do outro cliente, os recordes que o servidor manda ao montar Valdoria, Ecos de teste e passiva.
func _test_village() -> void:
	var hub := get_tree().current_scene
	check(await _wait_until(func() -> bool: return Hub.records.has("horde"), 5.0),
		"servidor mandou os recordes ao chegar na vila (%s)" % str(Hub.records.keys()))
	if peers > 1:
		check(await _wait_until(func() -> bool: return Network.remote_players.size() == peers - 1, 10.0),
			"vê os outros jogadores na vila (%d)" % Network.remote_players.size())
		for rp in Network.remote_players.values():
			var nm := str(Network.players.get(rp.peer_id, {}).get("name", ""))
			check(nm != "" and rp.name_tag != null and rp.name_tag.text == nm,
				"nome de %s em cima da réplica na vila" % nm)
		# todos se veem antes do emote: o evento só anima uma réplica que já existe do outro lado
		await _sync("praca")
		await _wait_until(func() -> bool: return hub.player.is_on_floor(), 3.0)
		hub.player.play_emote("acenar")
		check(hub.player.emote == "acenar", "acenou na vila")
		check(await _wait_until(func() -> bool:
			for rp in Network.remote_players.values():
				if rp.emote != "acenar":
					return false
			return true, 4.0), "vê o emote dos outros jogadores na réplica")

	# Ecos: o servidor (em --test) concede; a passiva é pedido ao servidor
	var from := econ_log.size()
	Econ.request_test_ecos(200)
	var r: Array = await _results_after(from, "test_ecos")
	check(not r.is_empty() and r[0][0] and Game.ecos == 200, "servidor concede Ecos de teste (%d)" % Game.ecos)
	var dmg0 := Game.mod("damage")
	from = econ_log.size()
	Econ.request("buy_passive", ["poder"])
	r = await _results_after(from, "buy_passive")
	check(not r.is_empty() and r[0][0] and Game.ecos == 175 and int(Game.passives.get("poder", 0)) == 1,
		"comprou a passiva Poder no servidor (Ecos %d, nível %d)" % [Game.ecos, int(Game.passives.get("poder", 0))])
	check(is_equal_approx(Game.mod("damage"), dmg0 + 0.03), "Poder 1 soma 3%% de dano (%.2f → %.2f)" % [dmg0, Game.mod("damage")])


## Sincroniza os clientes de teste pelo chat fora da Horda: cada um avisa que chegou e espera os outros.
## O anti-spam do servidor descarta mensagens logo depois do teste de chat: reenvia até o próprio eco
## voltar (aí todos receberam) e só então espera os outros.
func _sync(tag: String) -> void:
	var msg := "sync:" + tag
	var echoed := false
	for i in 6:
		Network.send_chat(msg)
		if await _wait_until(func() -> bool: return _chat_senders(msg).has(Network.my_name), 2.0):
			echoed = true
			break
	check(echoed, "aviso da barreira \"%s\" chegou ao servidor" % tag)
	check(await _wait_until(func() -> bool: return _chat_senders(msg).size() >= peers, 20.0),
		"os outros chegaram à barreira \"%s\" (%s)" % [tag, str(_chat_senders(msg))])


## Quem mandou a mensagem `text` pelo chat (nomes sem repetição).
func _chat_senders(text: String) -> Array:
	var out: Array = []
	for m in chat_got:
		if m[1] == text and m[0] != "" and not (m[0] in out):
			out.append(m[0])
	return out


# ---------------------------------------------------------------- personagem no servidor (Econ)
## Quantas coletas de pickup o servidor aceitou depois de econ_log[from].
func _claims_ok(from: int) -> int:
	var n := 0
	for i in range(from, econ_log.size()):
		if econ_log[i][0] == "claim_pickup" and econ_log[i][1]:
			n += 1
	return n


func _seed_total() -> int:
	var n := 0
	for slot in Game.inventory:
		if str(slot.id).begins_with("seed_"):
			n += int(slot.qty)
	return n


func _inv_total() -> int:
	var n := 0
	for slot in Game.inventory:
		n += int(slot.qty)
	return n


## Espera `n` respostas da operação `op` chegarem depois de econ_log[from]. Devolve [[ok, err], ...].
func _results_after(from: int, op: String, n := 1, max_t := 5.0) -> Array:
	var got: Array = []
	await _wait_until(func() -> bool:
		got.clear()
		for i in range(from, econ_log.size()):
			if econ_log[i][0] == op:
				got.append([econ_log[i][1], econ_log[i][2]])
		return got.size() >= n, max_t)
	return got


## Ouro de teste concedido pelo servidor (só existe com o servidor em --test).
func _test_gold(amount: int) -> bool:
	var from := econ_log.size()
	Econ.request_test_gold(amount)
	var r: Array = await _results_after(from, "test_gold")
	return not r.is_empty() and r[0][0]


func _test_econ() -> void:
	# modo admin pelo servidor: liga (recursos no teto), desliga (volta ao que era)
	var ga := Game.gold
	var fa := econ_log.size()
	Econ.set_admin(true)
	var ra: Array = await _results_after(fa, "admin")
	check(not ra.is_empty() and ra[0][0] and Game.admin_mode() and Game.gold == AdminRules.GOLD,
		"servidor liga o modo admin (ouro %d)" % Game.gold)
	fa = econ_log.size()
	Econ.set_admin(false)
	ra = await _results_after(fa, "admin")
	check(not ra.is_empty() and ra[0][0] and not Game.admin_mode() and Game.gold == ga,
		"servidor desliga o modo admin e devolve o ouro (%d)" % Game.gold)
	# compra com ouro concedido pelo servidor: o cliente só pede, o estado volta do servidor
	var price := int(ItemDB.get_item("health_potion").price)
	var g0 := Game.gold
	check(await _test_gold(100) and Game.gold == g0 + 100, "servidor concede ouro de teste com --test (%d → %d)" % [g0, Game.gold])
	var pots := Game.count_item("health_potion")
	var from := econ_log.size()
	Game.buy("health_potion")
	var rb: Array = await _results_after(from, "buy")
	check(not rb.is_empty() and rb[0][0] and Game.count_item("health_potion") == pots + 1 and Game.gold == g0 + 100 - price,
		"comprou 1 poção com o ouro do servidor (ouro %d)" % Game.gold)

	# Review Focus 1: dois pedidos seguidos com ouro para um só — o servidor processa em ordem, o 2º falha
	var stock: Array = ItemDB.SHOP_STOCK.duplicate()
	stock.sort_custom(func(a, b) -> bool: return int(ItemDB.get_item(a).price) < int(ItemDB.get_item(b).price))
	var id := ""
	var p := 0
	for sid in stock:
		if int(ItemDB.get_item(sid).price) * 2 > Game.gold:
			id = sid
			p = int(ItemDB.get_item(sid).price)
			break
	check(id != "", "item da loja para a compra dupla (%s, %d ouro)" % [id, p])
	if id == "":
		return
	if Game.gold < p:
		await _test_gold(p - Game.gold)
	var g1 := Game.gold
	var c1 := Game.count_item(id)
	from = econ_log.size()
	Econ.request("buy", [id])
	Econ.request("buy", [id])
	var two: Array = await _results_after(from, "buy", 2)
	check(two.size() == 2 and two[0][0] and not two[1][0] and two[1][1] == "ouro_insuficiente",
		"compra dupla: a 1ª passa, a 2ª é recusada (%s)" % str(two))
	check(Game.count_item(id) == c1 + 1 and Game.gold == g1 - p, "compra dupla termina com 1 item e o ouro certo (%d → %d)" % [g1, Game.gold])

	# op forjada: concessão não é pedido de cliente
	var g2 := Game.gold
	from = econ_log.size()
	Econ.request("grant", [9999, 0, {}, "trapaca"])
	var f: Array = await _results_after(from, "grant")
	check(not f.is_empty() and not f[0][0] and f[0][1] == "op_invalida" and Game.gold == g2,
		"op forjada (grant) recusada com op_invalida (%s)" % str(f))
	# dungeon compartilhada: entra, vê os monstros e o chefe que o servidor mantém lá dentro e sai
	var w := get_tree().current_scene
	var back: Vector3 = w.player.global_position
	var rank0 := str(Game.flags.get("rank", "D"))
	Game.flags["rank"] = "C"
	w.use_dungeon_door("dg_bosque")
	check(await _wait_until(func() -> bool: return Regions.region_at(w.player.global_position) == "dg_bosque", 4.0),
		"entrou no Covil das Raízes")
	check(await _wait_until(func() -> bool:
		var n := 0
		var chief := false
		for e in Network.enemies.values():
			if is_instance_valid(e) and Regions.region_at(e.global_position) == "dg_bosque":
				n += 1
				chief = chief or e.chief
		return n >= 14 and chief, 5.0), "monstros e chefe da dungeon vêm do servidor")
	w.use_dungeon_door("out")
	check(await _wait_until(func() -> bool: return w.player.global_position.distance_to(Regions.door_point("dg_bosque")) < 3.0, 4.0),
		"saiu pela porta")
	Game.flags["rank"] = rank0
	w.player.global_position = back
	await wait(0.5)


## O servidor em --test deixa "choose_class" valer de novo (CharacterService.allow_reclass): é como o teste
## passa pelas quatro armas, já que a classe é fixa no jogo de verdade.
## Depois equipa a arma `weapon` (a escolha da classe equipa a melhor que o personagem tem, e um saque
## melhor do que o inicial mudaria o id): se faltar na mochila, o servidor em --test dá uma.
## Corpo do personagem do teste: Ana é mulher (o colega confere a réplica feminina), os outros homens.
func my_body() -> String:
	return "f" if my_name == "Ana" else "m"


func _pick_class(cls: String, weapon: String) -> void:
	Econ.request("choose_class", [cls, my_body()])
	await _wait_until(func() -> bool: return Game.char_class == cls and Game.equipment.weapon != "", 3.0)
	if Game.equipment.weapon == weapon:
		return
	if Game.count_item(weapon) == 0:
		Econ.request_test_items({weapon: 1})
		await _wait_until(func() -> bool: return Game.count_item(weapon) > 0, 3.0)
	Game.equip(weapon)
	await _wait_until(func() -> bool: return Game.equipment.weapon == weapon, 3.0)


## Sai do servidor e entra de novo (mesmo token): o personagem volta igual, vindo do banco do servidor.
func _test_reconnect_keeps_state() -> void:
	var inv: Array = Game.inventory.duplicate(true)
	var gold := Game.gold
	var eq: Dictionary = Game.equipment.duplicate()
	var w := Network.world
	var pos: Vector3 = w.player.global_position if w != null and w.get("player") != null else Vector3.ZERO
	Game.go_to_menu()   # manda vida/posição e sai
	await wait(1.0)
	check(not Network.is_online(), "saiu do servidor")
	# espelho zerado: o que aparecer depois de entrar veio do servidor
	Game.apply_state(CharState.new_character(Balance.tables).to_dict(), true)
	join_error = ""
	Network.join(address, token)
	check(await _wait_until(func() -> bool: return _in_village() and Network.is_online(), 20.0) and join_error == "",
		"entrou de novo no servidor %s" % join_error)
	check(Game.inventory == inv and Game.gold == gold and Game.equipment == eq,
		"personagem igual depois de reconectar (ouro %d → %d, %d → %d espaços)" % [gold, Game.gold, inv.size(), Game.inventory.size()])
	var sp = Game.spawn_position
	check(w == null or (sp is Vector3 and sp.distance_to(pos) < 1.5), "posição em Valdoria volta do servidor (%s)" % str(sp))


# ---------------------------------------------------------------- conta e sessão
## --probe: confere o servidor público sem conta: (1) HTTP — /health responde a versão deste build;
## (2) UDP — uma conexão ENet na porta do jogo chega a conectar (sem _register; desconecta logo).
func _probe() -> void:
	var h: Dictionary = await Auth.health(address)
	var v := str(h.get("version", ""))
	var http_ok: bool = h.ok and v == Network.version()
	check(h.ok, "HTTP: API respondeu /health em %s (%s)" % [Auth.base_url(address), h.get("err", "ok")])
	check(v == Network.version(), "HTTP: servidor na versão %s (está na %s)" % [Network.version(), v])
	var udp := await _probe_udp()
	check(udp == "", "UDP: conexão ENet em %s %s" % [address, "ok" if udp == "" else "falhou (%s)" % udp])
	if http_ok and udp == "":
		print("[%s] servidor aceitou a versão %s (HTTP e UDP ok)" % [my_name, v])
	else:
		printerr("[%s] PROBE FALHOU: %s" % [my_name, " e ".join(
			(["HTTP"] if not http_ok else []) + (["UDP"] if udp != "" else []))])


## Conexão ENet crua (sem o SceneMultiplayer, para não mandar _register). "" = conectou.
func _probe_udp() -> String:
	var host := address.strip_edges()
	var p := Network.DEFAULT_PORT
	if host.count(":") == 1:
		p = int(host.get_slice(":", 1))
		host = host.get_slice(":", 0)
	var ip := host if host.is_valid_ip_address() else IP.resolve_hostname(host, IP.TYPE_IPV4)
	if ip == "":
		return "não resolveu %s" % host
	var conn := ENetConnection.new()
	if conn.create_host(1) != OK:
		return "não criou o host ENet"
	var peer := conn.connect_to_host(ip, p, 0)
	if peer == null:
		conn.destroy()
		return "não abriu a conexão"
	var t := 0.0
	var res := "sem resposta em %d s" % int(Network.CONNECT_TIMEOUT)
	while t < Network.CONNECT_TIMEOUT:
		var ev: Array = conn.service(0)
		if ev[0] == ENetConnection.EVENT_CONNECT:
			res = ""
			break
		if ev[0] == ENetConnection.EVENT_DISCONNECT:
			res = "recusada"
			break
		if ev[0] == ENetConnection.EVENT_ERROR:
			res = "erro de rede"
			break
		if ev[0] == ENetConnection.EVENT_NONE:
			await wait(0.05)
			t += 0.05
	if res == "":
		peer.peer_disconnect()
		conn.flush()
	conn.destroy()
	return res


## Token que o servidor não conhece: recusado com a mensagem de sessão expirada.
func _test_bad_token() -> void:
	join_error = ""
	Network.join(address, "token-que-nao-existe")
	await _wait_until(func() -> bool: return join_error != "", 8.0)
	check(join_error.begins_with("Sessão expirada"), "token inválido é recusado (%s)" % join_error)
	Network.leave()
	join_error = ""


## Seleção de personagem: a conta logada fica fora do jogo até escolher; cria dois heróis (já com classe),
## a lista traz classe e nível, exclui um, pedido de personagem alheio é recusado e "enter" põe no jogo.
func _test_character_select() -> void:
	var sel_name := my_name + "Sel"
	var reg: Dictionary = await Auth.register(address, sel_name, TEST_PASS)
	var log_r: Dictionary = await Auth.login(address, sel_name, TEST_PASS)
	check((reg.ok or reg.err == "nome_em_uso") and log_r.ok, "conta da seleção (%s)" % log_r.get("err", "ok"))
	if not log_r.ok:
		return
	var lists: Array = []   # [lista, criado, erro]
	var on_list := func(list: Array, created: int, err: String) -> void: lists.append([list, created, err])
	Network.char_list_changed.connect(on_list)
	Game.skip_auto_class = true
	join_error = ""
	Network.join(address, str(log_r.token))
	var got: bool = await _wait_until(func() -> bool: return not lists.is_empty(), 10.0)
	check(got, "servidor mandou a lista de personagens depois do login")
	if got:
		var me := multiplayer.get_unique_id()
		check(not Network.players.has(me), "na seleção a conta ainda não está no jogo")
		# reaproveita a conta entre execuções: começa sem personagens
		for e in lists[-1][0]:
			Network.char_delete(int(e.id))
			await _wait_until(func() -> bool: return lists[-1][0].all(func(x: Dictionary) -> bool: return int(x.id) != int(e.id)), 5.0)
		lists.clear()
		Network.char_create(sel_name + "Mag", "mage", "f")
		await _wait_until(func() -> bool: return not lists.is_empty(), 5.0)
		Network.char_create(sel_name + "Arq", "archer", "m")
		await _wait_until(func() -> bool: return lists.size() >= 2, 5.0)
		Network.char_create(sel_name + "ARQ", "warrior", "m")   # mesmo nome, outra caixa
		await _wait_until(func() -> bool: return lists.size() >= 3, 5.0)
		check(lists.size() >= 3 and lists[-1][2].begins_with("Já existe"), "nome repetido recusado (%s)"
			% (lists[-1][2] if lists.size() >= 3 else "sem resposta"))
		var list: Array = lists[-1][0] if not lists.is_empty() else []
		check(list.size() == 2, "criou dois heróis na mesma conta (%d)" % list.size())
		check(lists.size() >= 2 and int(lists[1][1]) > 0 and lists[1][2] == "", "criação devolve o id do herói novo")
		if list.size() == 2:
			check(list[0].char_class == "mage" and list[1].char_class == "archer", "lista traz a classe de cada um")
			check(int(list[0].level) == 1 and list[0].body == "f", "lista traz nível e corpo")
			check(list[1].name == sel_name + "Arq", "lista traz o nome do herói (%s)" % list[1].name)
			Network.char_delete(int(list[0].id))
			await _wait_until(func() -> bool: return lists[-1][0].size() == 1, 5.0)
			check(lists[-1][0].size() == 1, "excluiu um herói (%d sobrou)" % lists[-1][0].size())
			Network.char_enter(999999)
			await _wait_until(func() -> bool: return lists[-1][2] != "", 5.0)
			check(lists[-1][2] != "" and not Network.players.has(me), "entrar com personagem alheio é recusado (%s)" % lists[-1][2])
			var keep := int(list[1].id)
			Network.char_enter(keep)
			var entered: bool = await _wait_until(func() -> bool: return Network.players.has(me), 8.0)
			check(entered and Game.char_class == "archer", "entrou no jogo com o herói escolhido (%s)" % Game.char_class)
			check(int(Network.players.get(me, {}).get("char", 0)) == keep, "servidor associou o personagem ao jogador")
			check(Network.my_name == sel_name + "Arq", "no jogo aparece o nome do herói, não o da conta (%s)" % Network.my_name)
			# "Trocar de personagem": reconecta com o mesmo token e volta para a seleção, sem login
			lists.clear()
			check(Network.rejoin(), "trocar de personagem: reconecta com o token da sessão")
			var back: bool = await _wait_until(func() -> bool: return not lists.is_empty(), 10.0)
			check(back and join_error == "", "trocar de personagem: a lista da conta chega de novo (%s)" % join_error)
			if back:
				check(not Network.players.has(multiplayer.get_unique_id()), "trocar de personagem: fora do jogo até escolher")
				check(lists[-1][0].size() == 1 and int(lists[-1][0][0].id) == keep, "trocar de personagem: o herói continua na conta")
	Network.char_list_changed.disconnect(on_list)
	Game.skip_auto_class = false
	Game.go_to_menu()   # sai do servidor e fecha o mundo dessa conta antes da conta principal entrar
	await wait(1.0)
	join_error = ""


## Outro processo entra com o mesmo token: o servidor derruba esta conexão antes de aceitar a nova.
func _test_second_login_kicks_first() -> void:
	var result := "user://nettest_%s_2.result" % my_name
	DirAccess.remove_absolute(ProjectSettings.globalize_path(result))
	join_error = ""
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--",
		"--nettest=" + address, "--name=" + my_name, "--token=" + token]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--auth-url=") or a.begins_with("--expect-clock-offset="):
			args.append(a)
	var pid := OS.create_process(OS.get_executable_path(), args)
	check(pid > 0, "abriu a segunda conexão (pid %d)" % pid)
	if pid <= 0:
		return
	check(await _wait_until(func() -> bool: return not Network.is_online(), 40.0),
		"segunda conexão com o mesmo token derruba a primeira")
	check(join_error.contains("outro lugar"), "aviso de conta aberta em outro lugar (%s)" % join_error)
	var done: bool = await _wait_until(func() -> bool: return FileAccess.file_exists(result), 30.0)
	var txt := FileAccess.get_file_as_string(result) if done else ""
	check(txt == "OK", "segunda conexão entrou na vila (%s)" % (txt if done else "sem resultado"))
	if OS.is_process_running(pid):
		OS.kill(pid)


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
	var ecos0 := Game.ecos
	# os dois terminam os testes de Valdoria antes de a fila abrir (o lead ainda olha a réplica dele)
	await _sync("horda")
	var ui: Node = null
	if horde_role == "lead":
		ui = _invite_ui(w)
		check(ui != null, "painel de convite da horda existe no cliente")
		w.player.global_position = w.VILLAGE_SPAWN
		Game.hp = Game.max_hp()
		w.start_survival()   # online: abre a fila e convida os outros
		check(await _wait_until(func() -> bool: return Network.in_horde_lobby(), 5.0), "abriu a fila do Desafio da Horda")
		check(ui and ui.state() == "member", "painel mostra a fila para quem abriu")
	else:
		# o join recebe o convite na vila e aceita (o [Y] do painel)
		ui = _invite_ui(w)
		check(ui != null, "painel de convite da horda existe em Valdoria")
		check(await _wait_until(func() -> bool: return not Network.horde_lobby.is_empty(), 40.0), "vê a fila da Horda na vila")
		check(Network.horde_invite_pending(), "convite pendente na vila")
		if ui != null:
			ui._accept()
		check(await _wait_until(func() -> bool: return Network.in_horde_lobby() or w.survival != null, 5.0),
			"entrou na fila pelo convite")
	var p: Player = w.player

	check(await _wait_until(func() -> bool: return w.survival != null, 25.0), "entrou na partida do grupo")
	var sv = w.survival
	if sv == null:
		return
	check(sv.role == "client" and sv.team.size() == peers, "grupo com %d jogador(es) (%d)" % [peers, sv.team.size()])
	check(p.global_position.distance_to(w.ARENA) < 5.0, "teleportado para a arena (mapa à parte)")
	check(Network.horde_lobby.is_empty() and ui != null and ui.state() == "", "fila fechada ao começar")
	check(await _wait_until(func() -> bool: return sv.round_num == 1, 5.0), "rodada 1 chega do servidor")
	check(await _wait_until(func() -> bool: return sv.alive_count() >= 1, 6.0), "inimigos da horda replicados (%d)" % sv.alive_count())
	if peers > 1:
		var near := [0]
		check(await _wait_until(func() -> bool:
			near[0] = 0
			for rp in Network.remote_players.values():
				if is_instance_valid(rp) and rp.global_position.distance_to(w.ARENA) < 40.0:
					near[0] += 1
			return near[0] == peers - 1, 5.0), "vê o grupo na arena (%d)" % near[0])

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

	# fim da rodada: cada um escolhe a bênção (as sementes chegam do servidor)
	var seeds0 := _seed_total()
	var got_round: bool = await _wait_until(func() -> bool:
		if w.modal != null and w.modal.get("mode") == "levelup" and w.modal._lock <= 0.0:
			w.modal._pick(0)
		return w.modal != null and w.modal.get("mode") == "round", 30.0)
	check(got_round and sv.rounds_cleared == 1, "fim da rodada abre a bênção")
	check(not p.dead, "jogador de pé no fim da rodada")
	check(await _wait_until(func() -> bool: return sv.seeds_won >= 1 and _seed_total() > seeds0, 3.0),
		"sementes da rodada concedidas pelo servidor (%d, mochila %d → %d)" % [sv.seeds_won, seeds0, _seed_total()])
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
	var end_xp0 := Game.xp + Game.level * 100000
	sv.end_run("retreat")
	await wait(0.3)
	check(w.modal != null and w.modal.get("mode") == "results", "resultados ao se retirar")
	check(await _wait_until(func() -> bool: return Game.xp + Game.level * 100000 > end_xp0, 3.0),
		"XP do fim da partida concedido pelo servidor (+%d)" % sv.rewards.get("xp", 0))
	check(await _wait_until(func() -> bool: return Game.flags.has("horde_best"), 3.0),
		"recorde da horda salvo no personagem (%s)" % str(Game.flags.get("horde_best")))
	var rounds: int = sv.rounds_cleared
	var ecos_won := RewardRules.ecos(Balance.tables, "horde", rounds)
	check(await _wait_until(func() -> bool: return Game.ecos == ecos0 + ecos_won, 3.0),
		"Ecos da Horda concedidos pelo servidor (%d rodada(s): %d → %d, +%d)" % [rounds, ecos0, Game.ecos, ecos_won])
	await wait(0.45)
	if w.modal != null:
		w.modal._finish()
	await wait(0.3)
	check(w.survival == null and p.global_position.distance_to(w.HORDE_RETURN) < 3.0, "voltou para a vila, na frente do portal")


# ---------------------------------------------------------------- vila
## Na vila de Valdoria (o mundo montado, sem ser a cidade em grupo).
func _in_village() -> bool:
	var s := get_tree().current_scene
	return s != null and s.get("role") == null and s.get("points") != null and s.get("built") == true \
		and Network.world == s


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
	if not probe:
		# o cliente online nunca concede a si mesmo (Econ.grant/kill online = push_error)
		check(Econ.client_grant_errors == 0, "nenhuma concessão no cliente online (%d)" % Econ.client_grant_errors)
	print("[%s] %s (%d falhas)" % [my_name, "NETTEST OK" if fails == 0 else "NETTEST FALHOU", fails])
	if token != "" and not relogin and OS.get_cmdline_user_args().has("--token=" + token):
		# processo da segunda conexão: o primeiro lê o resultado deste arquivo
		var f := FileAccess.open("user://nettest_%s_2.result" % my_name, FileAccess.WRITE)
		if f:
			f.store_string("OK" if fails == 0 else "FALHOU")
			f.close()
	Network.leave()
	get_tree().quit(1 if fails > 0 else 0)
