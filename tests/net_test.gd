extends Node
## Teste do multiplayer: entra num servidor como cliente headless e verifica a sincronia.
##   godot --headless --path . -- --server --port=7777 --http-port=8790 --db=<banco novo>      (terminal 1)
##   godot --headless --path . -- --nettest=127.0.0.1:7777 --auth-url=http://127.0.0.1:8790 [--peers=2] [--name=Ana]
## --name é o usuário da conta de teste (senha fixa TEST_PASS): o teste cadastra (409 é ok), loga e entra com o token.
## --peers=N espera ver N-1 outros jogadores. Sai com código 0 (ok) ou 1 (falhas).
## --probe: sem conta, confere GET /health (versão) e se uma conexão ENet na porta UDP conecta (CI contra o servidor público).
## --relogin: no fim, abre uma segunda conexão (outro processo, mesmo token) e espera esta ser derrubada.
## --token=T: entra direto com o token (é o processo da segunda conexão do --relogin).
## Todos os modos começam na praça: os outros jogadores e os emotes deles, Ecos de teste, passiva e doação.
## --horde=lead|join: testa o Desafio da Horda em grupo (lead abre a fila em Valdoria; join volta à praça,
##   vê a fila lá e entra pelo portal da praça, e no fim volta à praça).
##   Use com o servidor em --horde-round=8 --horde-pick=5 para as rodadas e escolhas não demorarem.
## --city=lead|join: testa a Defesa da Cidade em grupo pela praça (lead cria a sala e começa, join entra).
##   Use com o servidor em --city-day=12 (dia curto) e --city-event=caravan (evento do dia 2 para a troca).

var fails := 0
var address := "127.0.0.1"
var peers := 1
var my_name := "Teste"
var probe := false
var horde_role := ""
var city_role := ""
var chat_got: Array = []   # [nome, texto]
var relogin := false
var token := ""
var join_error := ""
## --city=join: net_id de um pickup deixado no chão de Valdoria antes da cidade (Review Focus 5).
var old_pickup := 0
## Cidade: Ecos e recompensas de noite (Lobby.city_nights_rewarded) antes da partida, para conferir os Ecos
## do fim pelas noites que este cliente viu de verdade (Review Focus 3).
var city_ecos0 := 0
var city_nights0 := 0

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
		elif a.begins_with("--city="):
			city_role = a.substr(7)
		elif a == "--relogin":
			relogin = true
		elif a.begins_with("--token="):
			token = a.substr(8)
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
	Network.join(address, token)

	# todo mundo chega pela praça
	var t := 0.0
	while not _in_hub() and join_error == "" and t < 15.0:
		await wait(0.2)
		t += 0.2
	check(join_error == "", "conectou sem erro %s" % join_error)
	check(_in_hub(), "chegou à praça (hub)")
	if not _in_hub():
		_finish()
		return
	check(Network.my_name == my_name, "nome no servidor é o da conta (%s)" % Network.my_name)
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
	check(await _wait_until(func() -> bool: return Network.zone_of(multiplayer.get_unique_id()) == "hub", 5.0),
		"servidor vê o jogador na praça")
	await _test_hub()
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
		# as coletas contam desde antes do abate: o ímã pode pedir a coleta antes de o teste olhar o chão
		var inv0 := _inv_total()
		var from := econ_log.size()
		# o servidor só aceita acerto perto da última posição recebida do jogador (HitGuard): espera ela chegar
		await wait(0.3)
		target.take_damage(10.0, w.player.global_position, false)
		await wait(0.6)
		check(target.hp < hp0, "dano chega ao servidor e volta no snapshot (%.0f → %.0f)" % [hp0, target.hp])
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
	# cajado (o do kit inicial: o cliente online não se dá itens): troca pedida ao servidor
	Game.equip("apprentice_staff")
	check(await _wait_until(func() -> bool: return Game.equipment.weapon == "apprentice_staff", 3.0)
		and w.player.look["class"] == "staff", "trocou para o cajado")
	await wait(0.6)
	if peers > 1:
		# cada um troca no próprio ritmo (o colega pode ainda estar no loot): espera a troca chegar
		for rp in Network.remote_players.values():
			check(await _wait_until(func() -> bool: return rp.look["class"] == "staff", 10.0),
				"vê %s trocar para cajado" % rp.display_name)
	# efeitos visuais (aura de buff/habilidade e encanto da arma) viajam com o visual
	# ficam ligados até o fim: o colega chega a este ponto no ritmo dele e precisa encontrá-los
	w.player.set_ability_aura("escudo", true)
	w.player.set_ability_aura("vento", true)
	w.player.vfx_enchant_el = "gelo"
	w.player.vfx_enchant_lv = 4
	w.player._update_equipment_visual()
	var my_fx: Dictionary = w.player._last_look.get("fx", {})
	check(my_fx.get("auras", []) == ["escudo", "vento"] and my_fx.get("en", "") == "gelo" and my_fx.get("lv", 0) == 4,
		"auras de habilidade + encanto no visual local")
	check(w.player.look["class"] == "staff" and w.player.look["holder"] != null, "trocar só os efeitos não desmonta a arma")
	if peers > 1:
		check(await _wait_until(func() -> bool:
			for rp in Network.remote_players.values():
				var fx: Dictionary = rp._last_look.get("fx", {})
				if fx.get("auras", []) != ["escudo", "vento"] or fx.get("en", "") != "gelo" or fx.get("lv", 0) != 4:
					return false
			return true, 6.0), "vê as auras e o encanto dos outros jogadores")
		for rp in Network.remote_players.values():
			check(rp.vfx_aura != null and rp.vfx_aura.styles() == ["escudo", "vento"], "aura montada na réplica de %s" % rp.display_name)
			var hold: Node3D = rp.look.get("holder")
			var mis: Array = hold.find_children("*", "MeshInstance3D", true, false) if hold else []
			check(not mis.is_empty() and mis[0].material_overlay != null, "encanto aplicado na arma da réplica de %s" % rp.display_name)

	if my_name == "Ana":
		await _test_econ()

	if horde_role != "":
		await _test_horde(w)

	# fica um pouco para os outros testes verem este jogador
	await wait(3.0 if peers > 1 else 0.5)
	if my_name == "Ana":
		await _test_reconnect_keeps_state()
	if relogin:
		await _test_second_login_kicks_first()
	_finish()


# ---------------------------------------------------------------- praça
## Logo depois de conectar, todos na praça: os outros jogadores com o nome em cima, o emote chegando à
## réplica do outro cliente, Ecos de teste, passiva e doação à Forja (com --peers=2 as duas doações sobem
## a Forja para o nível 1 e o aviso chega pelo chat).
func _test_hub() -> void:
	var hub := get_tree().current_scene
	if peers > 1:
		check(await _wait_until(func() -> bool: return Network.remote_players.size() == peers - 1, 10.0),
			"vê os outros jogadores na praça (%d)" % Network.remote_players.size())
		for rp in Network.remote_players.values():
			var nm := str(Network.players.get(rp.peer_id, {}).get("name", ""))
			check(nm != "" and rp.name_tag != null and rp.name_tag.text == nm,
				"nome de %s em cima da réplica na praça" % nm)
		# todos se veem antes do emote: o evento só anima uma réplica que já existe do outro lado
		await _sync("praca")
		await _wait_until(func() -> bool: return hub.player.is_on_floor(), 3.0)
		hub.player.play_emote("acenar")
		check(hub.player.emote == "acenar", "acenou na praça")
		check(await _wait_until(func() -> bool:
			for rp in Network.remote_players.values():
				if rp.emote != "acenar":
					return false
			return true, 4.0), "vê o emote dos outros jogadores na réplica")

	# Ecos: o servidor (em --test) concede; passiva e doação são pedidos ao servidor
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
	from = econ_log.size()
	Econ.request("donate", ["forja", 60])
	r = await _results_after(from, "donate")
	check(not r.is_empty() and r[0][0] and Game.ecos == 115, "doou 60 Ecos à Forja (Ecos %d)" % Game.ecos)
	check(await _wait_until(func() -> bool:
		return BaseRules.total_invested(Balance.tables, "forja", Hub.base.get("forja", {})) == 60 * peers, 10.0),
		"base do servidor com as doações de todos (%s)" % str(Hub.base.get("forja", {})))
	if peers == 2:
		check(int(Hub.base.get("forja", {}).get("level", 0)) == 1, "Forja no nível 1")
		check(await _wait_until(func() -> bool:
			for m in chat_got:
				if m[0] == "" and str(m[1]).begins_with("Forja subiu"):
					return true
			return false, 4.0), "aviso \"Forja subiu\" chegou pelo chat")


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
	check(await _wait_until(func() -> bool: return _in_hub() and Network.is_online(), 15.0) and join_error == "",
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


## Outro processo entra com o mesmo token: o servidor derruba esta conexão antes de aceitar a nova.
func _test_second_login_kicks_first() -> void:
	var result := "user://nettest_%s_2.result" % my_name
	DirAccess.remove_absolute(ProjectSettings.globalize_path(result))
	join_error = ""
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--",
		"--nettest=" + address, "--name=" + my_name, "--token=" + token]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--auth-url="):
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
	check(txt == "OK", "segunda conexão entrou na praça (%s)" % (txt if done else "sem resultado"))
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
	# os dois terminam os testes de Valdoria antes de o join ir para a praça (o lead ainda olha a réplica dele)
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
		# o join entra pela praça: vê a fila estando lá e passa pelo portal (Hub.go_horde)
		Lobby.go_hub()
		check(await _wait_until(func() -> bool: return _in_hub() and Network.world != null and Network.world.get("role") == "hub", 15.0),
			"voltou à praça antes da Horda")
		check(await _wait_until(func() -> bool: return _in_hub() and not Network.horde_lobby.is_empty(), 40.0),
			"vê a fila da Horda estando na praça")
		check(Network.horde_invite_pending(), "convite pendente na praça")
		Hub.go_horde()
		check(await _wait_until(func() -> bool:
			return Network.world != null and Network.world.get("role") == null and Network.world.get("player") != null, 15.0),
			"portal da praça leva a Valdoria")
		w = Network.world
		if w == null or w.get("role") != null:
			return
		check(await _wait_until(func() -> bool: return Network.in_horde_lobby() or w.survival != null, 5.0),
			"entrou na fila pelo portal da praça")
		ui = _invite_ui(w)
		check(ui != null, "painel de convite da horda existe em Valdoria")
	var p: Player = w.player

	check(await _wait_until(func() -> bool: return w.survival != null, 25.0), "entrou na partida do grupo")
	var sv = w.survival
	if sv == null:
		return
	check(sv.role == "client" and sv.team.size() == peers, "grupo com %d jogador(es) (%d)" % [peers, sv.team.size()])
	check(p.global_position.distance_to(w.ARENA) < 5.0, "teleportado para a arena")
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
	if horde_role == "join":
		# veio pelo portal da praça: no fim volta para a praça, não para a vila
		check(await _wait_until(func() -> bool: return _in_hub() and Network.world != null and Network.world.get("role") == "hub", 15.0),
			"voltou à praça depois da Horda")
		check(await _wait_until(func() -> bool: return Network.zone_of(multiplayer.get_unique_id()) == "hub", 5.0),
			"servidor vê o jogador de volta na praça")
		return
	await wait(0.3)
	check(w.survival == null and p.global_position.distance_to(w.VILLAGE_SPAWN) < 3.0, "voltou para a vila")


# ---------------------------------------------------------------- Defesa da Cidade em grupo
func _in_hub() -> bool:
	var s := get_tree().current_scene
	return s != null and s.get("role") == "hub"


func _city_colony() -> Colony:
	return Lobby.city.colony if Lobby.city != null and is_instance_valid(Lobby.city) else null


func _test_city() -> void:
	city_ecos0 = Game.ecos
	city_nights0 = Lobby.city_nights_rewarded
	# --- sala na mesa de guerra da praça
	if city_role == "lead":
		Lobby.room_send("create")
		check(await _wait_until(func() -> bool: return Lobby.in_room() and Lobby.is_leader(), 5.0), "criou a sala da cidade (líder)")
		check(await _wait_until(func() -> bool:
			return Lobby.room.get("members", []).size() == peers and Lobby.room.get("ready", []).size() >= peers - 1, 30.0),
			"todos entraram na sala e ficaram prontos (%d)" % Lobby.room.get("members", []).size())
		Lobby.room_send("start")
	else:
		# Review Focus 5: antes da cidade, deixa um pickup seu no chão de Valdoria (para depois da queda)
		old_pickup = await _leave_pickup_behind()
		check(old_pickup > 0, "deixou um pickup no chão de Valdoria (net_id %d)" % old_pickup)
		check(await _wait_until(func() -> bool: return not Lobby.room.is_empty(), 30.0), "vê a sala aberta na praça")
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
	# Review Focus 4: as doações da praça foram para a Forja; com o Celeiro no nível 0 o cofre não muda
	var start_gold := ColonyData.COOP_START_GOLD + ColonyData.COOP_GOLD_PER_PLAYER * (peers - 1)
	check(Hub.base.has("celeiro"), "base do servidor chegou à praça (%s)" % str(Hub.base.keys()))
	check(int(Hub.base.get("celeiro", {}).get("level", -1)) == 0, "Celeiro no nível 0")
	check(await _wait_until(func() -> bool: return c.treasury > 0, 5.0) and c.treasury == start_gold, "cofre inicial do grupo %d (%d)" % [start_gold, c.treasury])
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
		var g0 := c.treasury
		var w0 := c.amount("wood")
		c.place("house", Vector3(-12, 0, -6), PI / 2)
		check(await _wait_until(func() -> bool: return c.count_of("house") == 1, 5.0), "casa construída pelo servidor")
		var hcost: Dictionary = ColonyData.BUILDINGS.house.cost
		check(await _wait_until(func() -> bool: return c.treasury == g0 - int(hcost.gold) and c.amount("wood") == w0 - int(hcost.wood), 3.0),
			"casa cobra ouro e madeira do cofre (%d → %d)" % [g0, c.treasury])
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
			# golpe de longe: o servidor recusa (o jogador está longe do nó) e nada entra no cofre
			var far: ColonyResourceNode = c.nature.nearest("tree", w.player.global_position + Vector3(60, 0, 60))
			check(far != null and far != tree and far.global_position.distance_to(w.player.global_position) > HitGuard.HARVEST_RANGE + 5.0,
				"há uma árvore longe do jogador para o golpe recusado")
			if far != null:
				Lobby.city_hit_node(far.id)
				await wait(1.0)
				check(c.amount("wood") == tw0, "servidor recusa golpe num nó longe do jogador (%d → %d)" % [tw0, c.amount("wood")])
			w.player.global_position = tree.global_position + Vector3(0, 0.5, 1.5)
			await wait(0.5)   # a posição nova chega ao servidor antes do golpe
			for i in 4:
				tree.hit(w.player.global_position)
				await wait(0.35)
		check(await _wait_until(func() -> bool: return not tree.alive, 8.0), "árvore esgotada aparece para todos")
		check(await _wait_until(func() -> bool: return c.amount("wood") == tw0 + 24, 5.0),
			"madeira da coleta chega ao cofre (%d → %d)" % [tw0, c.amount("wood")])

	# --- covis: gerados da semente em todos (com o servidor em --city-day curto é sempre entardecer: não acordam)
	check(c.dens.size() >= 4 and c.dens[0].get_child_count() > 0, "covis gerados da semente do grupo (%d)" % c.dens.size())

	# --- serraria pedida pelo cliente (o líder), base da pesquisa do dia 2
	if city_role == "lead":
		var spot := _camp_spot(c)
		check(spot != Vector3.INF, "há lugar para a serraria perto de um bosque")
		if spot != Vector3.INF:
			c.place("lumber_camp", spot, 0.0)
			check(await _wait_until(func() -> bool: return c.count_of("lumber_camp") == 1, 5.0), "serraria construída pelo servidor")

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
	if city_role == "join" and peers > 1:
		# Review Focus 5: cai no meio da noite 1 e volta
		await _drop_mid_night(w, c)
		return
	if city_role == "lead" and peers > 1:
		# o colega abate o dele antes, cai no meio da noite e volta à partida com outro peer (Review Focus 3/5):
		# espera ele voltar para a cidade antes de acabar com a noite, para ele ver o amanhecer
		var before: Array = Lobby.room.get("in_city", []).duplicate()
		await wait(3.0)
		check(await _wait_until(func() -> bool:
			for pid in Lobby.room.get("in_city", []):
				if not (pid in before):
					return true
			return false, 40.0), "colega caiu e voltou para a cidade no meio da noite")
	var killed := 0
	var tt := 0.0
	while c.phase == "night" and tt < 60.0:
		# um monstro por vez: vai até ele, espera o servidor receber a posição (HitGuard) e acerta
		for e in c.live_enemies():
			w.player.global_position = e.global_position + Vector3(0, 0.5, 2.5)
			await wait(0.15)
			if is_instance_valid(e) and not e.dead:
				w.player.global_position = e.global_position + Vector3(0, 0.5, 2.5)
				e.take_damage(99999.0, w.player.global_position, false)
				killed += 1
			break
		await wait(0.25)
		tt += 0.4
	check(c.phase == "day" and c.day == 2, "amanheceu: dia %d" % c.day)
	check(killed > 0 and c.total_kills > 0, "abates contados pelo servidor (%d)" % c.total_kills)
	var rw := ColonyData.night_reward(1)
	check(await _wait_until(func() -> bool: return Game.gold >= rgold + int(rw.gold), 5.0),
		"recompensa da noite no personagem (+%d ouro: %d → %d)" % [rw.gold, rgold, Game.gold])
	check(Game.xp + Game.level * 100000 > rxp, "recompensa de XP no personagem")
	check(int(Game.flags.get("city_best", 0)) >= 1, "melhor noite salva no personagem")
	await _test_city_day2(w, c)

	# --- volta à praça: o join sai primeiro, o líder em seguida (a partida acaba quando todos saem)
	var nights_seen := c.day - 1
	var ecos0 := Game.ecos
	Lobby.last_result = {}
	await wait(0.5 if city_role == "join" else 2.5)
	if city_role == "lead":
		check(await _wait_until(func() -> bool: return Lobby.room.get("in_city", []).size() <= 1, 20.0),
			"colega saiu da cidade antes do líder")
	Lobby.go_hub()
	check(await _wait_until(func() -> bool: return _in_hub(), 10.0), "voltou à praça")
	check(await _wait_until(func() -> bool: return Network.zone_of(multiplayer.get_unique_id()) == "hub", 5.0), "servidor vê o jogador de volta na praça")
	if city_role == "lead":
		check(await _wait_until(func() -> bool: return Lobby.room.is_empty(), 8.0), "partida encerrada quando todos saíram")
		check(int(Lobby.record.get("day", 0)) >= 1, "recorde do servidor registrado (%d)" % int(Lobby.record.get("day", 0)))
		# Review Focus 3: quem viu o fim recebe o resumo com os Ecos das noites que viu, e o saldo sobe isso
		var ecos_won := RewardRules.ecos(Balance.tables, "city", nights_seen)
		check(await _wait_until(func() -> bool: return Lobby.last_result.has("ecos"), 5.0)
			and int(Lobby.last_result.ecos) == ecos_won and ecos_won > 0,
			"resumo da cidade traz os Ecos de %d noite(s) (%s, esperado %d)" % [nights_seen, str(Lobby.last_result.get("ecos")), ecos_won])
		check(await _wait_until(func() -> bool: return Game.ecos == ecos0 + ecos_won, 3.0),
			"Ecos da cidade concedidos pelo servidor (%d → %d)" % [ecos0, Game.ecos])
		check(await _wait_until(func() -> bool: return int(Hub.records.get("city", {}).get("reached", 0)) >= 1, 5.0),
			"recorde da Defesa na praça (%s)" % str(Hub.records.get("city")))
	# o personagem continua o mesmo em Valdoria
	Lobby.go_world()
	check(await _wait_until(func() -> bool: return Network.world != null and Network.world.get("player") != null, 15.0), "entrou em Valdoria depois da cidade")
	await wait(1.0)


## Dia 2 (o líder; o colega caiu na noite 1): o evento forçado no servidor (--city-event=caravan) chega pela
## rede, a troca pedida de longe é recusada pelo servidor e de perto é aceita; a pesquisa pedida pelo cliente
## aparece em andamento no estado ("busy"). O dia curto do teste (--city-day) não deixa a pesquisa terminar.
func _test_city_day2(w: Node, c: Colony) -> void:
	check(await _wait_until(func() -> bool: return c.events.active == "caravan", 5.0),
		"evento do dia forçado no servidor chega ao cliente (%s)" % c.events.active)
	if c.events.active == "caravan":
		var notes: Array[String] = []
		var grab := func(text: String, _color: Color) -> void: notes.append(text)
		Game.notify.connect(grab)
		var give: Dictionary = ColonyData.TRADES[1][0]
		var take: Dictionary = ColonyData.TRADES[1][1]
		var g0 := c.treasury
		var i0 := c.amount("iron")
		w.player.global_position = c.events.pos + Vector3(ColonyData.EVENT_REACH + 20.0, 0.5, 0)
		await wait(0.6)   # a posição longe chega ao servidor antes do pedido
		check(c.trade(1) == "", "pede a troca com a caravana")
		check(await _wait_until(func() -> bool: return notes.any(func(s: String) -> bool: return s.contains("perto")), 3.0)
			and c.treasury == g0 and c.amount("iron") == i0, "servidor recusa a troca de longe (%s)" % ", ".join(notes))
		w.player.global_position = c.events.pos + Vector3(2.0, 0.5, 0)
		await wait(0.6)
		c.trade(1)
		check(await _wait_until(func() -> bool:
			return c.treasury == g0 - int(give.gold) and c.amount("iron") == i0 + int(take.iron), 4.0),
			"troca aceita de perto: %s por %s (ferro %d)" % [ColonyData.cost_text(give), ColonyData.cost_text(take), c.amount("iron")])
		Game.notify.disconnect(grab)
	if c.count_of("lumber_camp") == 0:
		return
	var err := c.research("sharp_axe")
	check(err == "", "pede a pesquisa Machado Afiado (%s)" % err)
	check(await _wait_until(func() -> bool:
		for k in c.busy_t:
			if c.busy_t[k][0] == "sharp_axe":
				return true
		return false, 5.0), "pesquisa em andamento replicada no estado (busy %s)" % str(c.busy_t))


## Ponto livre a até ~74 m do centro com árvores suficientes em volta para a serraria (como no colony_test).
func _camp_spot(c: Colony) -> Vector3:
	for n in c.nature.nodes:
		var d := Vector2(n.global_position.x, n.global_position.z).length()
		if n.kind != "tree" or not n.alive or d < 30.0 or d > 72.0:
			continue
		for dx in [-6.0, -3.0, 0.0, 3.0, 6.0]:
			for dz in [-6.0, -3.0, 0.0, 3.0, 6.0]:
				var p: Vector3 = n.global_position + Vector3(dx, 0.0, dz)
				if Vector2(p.x, p.z).length() <= 74.0 and c.can_place("lumber_camp", p, 0.0) == "":
					return p
	return Vector3.INF


## Beto (--city=join), antes da cidade: mata um slime em Valdoria e guarda o net_id de um pickup dele sem
## pegar (o nó some do cliente; no servidor o pickup continua dele). Volta à praça. 0 se não conseguiu.
func _leave_pickup_behind() -> int:
	Lobby.go_world()
	if not await _wait_until(func() -> bool: return Network.world != null and Network.world.get("player") != null, 15.0):
		return 0
	var w: Node = Network.world
	await wait(1.0)
	var found := [0]
	for attempt in 3:
		var target: Enemy = null
		for e in Network.enemies.values():
			if e.kind == "slime" and not e.dead:
				target = e
				break
		if target == null:
			break
		w.player.global_position = target.global_position + Vector3(0, 0.5, 3)
		await wait(0.3)   # a posição chega ao servidor (HitGuard)
		var at := target.global_position
		target.take_damage(9999.0, w.player.global_position, false)
		await wait(0.2)
		w.player.global_position = at + Vector3(0, 0.5, 40)   # longe: o ímã não coleta
		await _wait_until(func() -> bool:
			for n in w.get_children():
				if n.get_script() == PICKUP and int(n.net_id) > 0:
					found[0] = int(n.net_id)
					n.queue_free()
			return found[0] > 0, 3.0)
		if found[0] > 0:
			break
	Lobby.go_hub()
	await _wait_until(func() -> bool: return _in_hub(), 10.0)
	return found[0]


## Coleta de um pickup pelo net_id; devolve o erro do servidor ("" se concedeu).
func _claim(net_id: int) -> String:
	var from := econ_log.size()
	Econ.request("claim_pickup", [net_id])
	var r: Array = await _results_after(from, "claim_pickup")
	return "sem_resposta" if r.is_empty() else ("" if r[0][0] else str(r[0][1]))


## Review Focus 5 (Duda): abate um monstro da noite 1 (o servidor concede XP e o abate na hora), cai e
## volta: o que já foi concedido continua no estado; o pickup antigo (de Valdoria) não pode ser pego nem antes
## (sumiu ao trocar de zona) nem depois da queda. Depois volta à partida (Review Focus 3) e confere os Ecos.
func _drop_mid_night(w: Node, c: Colony) -> void:
	var kills0 := Game.kills
	var tt := 0.0
	while Game.kills == kills0 and c.phase == "night" and tt < 20.0:
		for e in c.live_enemies():
			w.player.global_position = e.global_position + Vector3(0, 0.5, 2.5)
			await wait(0.15)
			if is_instance_valid(e) and not e.dead:
				w.player.global_position = e.global_position + Vector3(0, 0.5, 2.5)
				e.take_damage(99999.0, w.player.global_position, false)
			break
		await _wait_until(func() -> bool: return Game.kills > kills0, 1.0)
		tt += 1.2
	check(Game.kills > kills0 and c.phase == "night", "abateu um monstro no meio da noite 1 (abates %d → %d)" % [kills0, Game.kills])
	await wait(1.0)   # as concessões em trânsito chegam
	var xp := Game.xp + Game.level * 100000
	var kills := Game.kills
	var gold := Game.gold
	if old_pickup > 0:
		# trocar de zona tira do servidor o loot que ficou no chão da zona antiga (Valdoria → praça → cidade)
		var gone := await _claim(old_pickup)
		check(gone == "pego", "pickup de Valdoria sumiu ao trocar de zona (%s)" % gone)
	Game.go_to_menu()   # cai: a conexão fecha no meio da noite
	await wait(1.0)
	check(not Network.is_online(), "caiu do servidor no meio da noite")
	Game.apply_state(CharState.new_character(Balance.tables).to_dict(), true)
	join_error = ""
	Network.join(address, token)
	check(await _wait_until(func() -> bool: return _in_hub() and Network.is_online(), 15.0) and join_error == "",
		"voltou ao servidor %s" % join_error)
	check(Game.xp + Game.level * 100000 == xp and Game.kills == kills and Game.gold == gold,
		"concessões da noite continuam no estado depois da queda (XP %d, abates %d, ouro %d)" % [Game.xp, Game.kills, Game.gold])
	if old_pickup > 0:
		var err := await _claim(old_pickup)
		check(err == "pego", "pickup antigo recusado depois da queda (%s)" % err)

	# Review Focus 3: entra de novo na partida em andamento (outro peer da mesma conta), vê o amanhecer e sai
	# antes do líder. No fim a conta fecha a partida uma vez, com as noites dos dois peers somadas.
	check(await _wait_until(func() -> bool: return Lobby.room.get("state", "") == "running", 5.0), "a partida continua rodando")
	Lobby.room_send("enter")
	check(await _wait_until(func() -> bool: return _city_colony() != null, 20.0), "voltou para a cidade em andamento")
	var c2 := _city_colony()
	if c2 != null:
		check(await _wait_until(func() -> bool: return c2.phase == "day" and c2.day >= 2, 90.0),
			"viu o amanhecer depois de voltar (dia %d)" % c2.day)
		await wait(1.5)   # a recompensa da noite chega junto do amanhecer
		Lobby.go_hub()
		check(await _wait_until(func() -> bool: return _in_hub(), 10.0), "voltou à praça antes do líder")
	var nights := Lobby.city_nights_rewarded - city_nights0
	check(nights >= 1, "recebeu a recompensa de %d noite(s) na cidade" % nights)
	check(await _wait_until(func() -> bool: return Lobby.room.is_empty(), 40.0), "partida encerrada (o líder saiu por último)")
	var ecos_won := RewardRules.ecos(Balance.tables, "city", nights)
	check(await _wait_until(func() -> bool: return Game.ecos == city_ecos0 + ecos_won, 5.0),
		"Ecos da cidade pelas %d noite(s) vistas, somando os dois peers da conta (%d → %d, esperado +%d)" % [
			nights, city_ecos0, Game.ecos, ecos_won])
	Lobby.go_world()
	check(await _wait_until(func() -> bool: return Network.world != null and Network.world.get("player") != null, 15.0), "entrou em Valdoria depois da queda")
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
