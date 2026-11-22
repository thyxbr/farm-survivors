extends Node
## Demonstração do Grito do Bastião EM GRUPO, pelo servidor de verdade (o buff de cada um vem do servidor, como no
## jogo online). Precisa de um servidor local em --test e de dois clientes: você (com janela) e um companheiro
## automático (sem janela) que entra no seu grupo e anda do seu lado.
##   servidor:     godot --headless --path . -- --server --port=P --http-port=H --db=<arquivo> --test
##   companheiro:  godot --headless --path . -- --groupdemo=127.0.0.1:P --auth-url=http://127.0.0.1:H --name=Bruno --role=bot
##   você:         godot --path . -- --groupdemo=127.0.0.1:P --auth-url=http://127.0.0.1:H --name=Diego --role=host
## Cada um entra com uma conta de teste, vira guerreiro de espada e escudo e fica no nível do Grito do Bastião (só no
## espelho do cliente: o servidor em --test não confere o nível). Você convida o companheiro e ele aceita sozinho.
##   5  usa o Grito do Bastião     Y  zera a recarga     B  o companheiro também grita
## O companheiro grita sozinho quando você aperta B (ele avisa pelo chat): aí você recebe o buff dele.

const PASS := "demo-grupo-123"
const FOLLOW := Vector3(2.4, 0, 1.2)
const ID := PartyShieldRules.ID
const BOT_CAST := "grupo:bastiao"

var address := ""
var my_name := "Diego"
var role := "host"
var _label: Label
var _ready_done := false
var _invited := false
var _status := "conectando..."


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--groupdemo="):
			address = a.substr(12)
		elif a.begins_with("--name="):
			my_name = a.substr(7)
		elif a.begins_with("--role="):
			role = a.substr(7)
	Econ.solo_save_path = "user://groupdemo_%s.json" % my_name
	if role == "host":
		var layer := CanvasLayer.new()
		layer.layer = 50
		add_child(layer)
		_label = Label.new()
		_label.position = Vector2(20, 140)
		_label.add_theme_font_size_override("font_size", 20)
		_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_label.add_theme_constant_override("outline_size", 6)
		layer.add_child(_label)
	Network.chat_received.connect(_on_chat)
	_run()


func _run() -> void:
	var reg: Dictionary = await Auth.register(address, my_name, PASS)
	var log_r: Dictionary = await Auth.login(address, my_name, PASS)
	if not log_r.ok:
		_status = "login falhou: %s (%s)" % [log_r.get("err", "?"), reg.get("err", "")]
		print("GRUPO ", _status)
		return
	Network.join(address, str(log_r.token))
	_status = "entrando no mundo..."
	while Network.world == null or Network.world.get("player") == null or Game.char_class == "":
		await get_tree().create_timer(0.3).timeout
	_status = "pegando espada e escudo..."
	if Game.char_class != "warrior":
		Econ.request("choose_class", ["warrior", "m"])
		await _until(func() -> bool: return Game.char_class == "warrior", 5.0)
	for it in ["iron_sword", "wooden_shield"]:
		if Game.count_item(it) == 0 and not (it in Game.equipment.values()):
			Econ.request_test_items({it: 1})
			await _until(func() -> bool: return Game.count_item(it) > 0, 5.0)
	Game.equip("iron_sword")
	await _until(func() -> bool: return Game.equipment.weapon == "iron_sword", 5.0)
	Game.equip("wooden_shield")
	await _until(func() -> bool: return Game.offhand_kind() == "shield", 5.0)
	_ready_done = true
	_status = "pronto"
	print("GRUPO pronto: ", my_name)


func _until(cond: Callable, timeout: float) -> void:
	var t := 0.0
	while t < timeout and not cond.call():
		await get_tree().create_timer(0.1).timeout
		t += 0.1


func _process(_delta: float) -> void:
	var w = Network.world
	var me = w.get("player") if w != null else null
	if _ready_done and me != null and is_instance_valid(me):
		# nível da habilidade só no espelho (o servidor em --test não confere) e vida cheia
		var lv := int(ItemDB.ABILITIES[ID].level)
		if Game.level < lv:
			Game.level = lv
		Game.hp = Game.max_hp()
		var other := _other_peer()
		if role == "host":
			if other != 0 and not _invited and not Party.in_party():
				_invited = true
				Party.request_invite(other)
		else:
			if not Party.invite.is_empty():
				Party.answer_invite(true)
			var host = Network.remote_players.get(other) if other != 0 else null
			if host != null and is_instance_valid(host) and me.ability == "":
				var want: Vector3 = host.global_position + FOLLOW
				if me.global_position.distance_to(want) > 1.0:
					me.global_position = want
					me.velocity = Vector3.ZERO
	if _label == null:
		return
	var lines := ["Grito do Bastião em grupo — servidor local", "[5] gritar   [Y] zerar recarga   [B] o companheiro grita", ""]
	lines.append("estado: %s" % _status)
	lines.append("grupo: %s" % (", ".join(Party.members.map(func(m): return str(m.name))) if Party.in_party() else "formando..."))
	if _ready_done:
		var cd: float = me.cooldowns.get(ID, 0.0) if me != null else 0.0
		var left: float = Game.buffs.get(PartyShieldRules.BUFF, 0.0)
		lines.append("recarga: %s   seu buff: %s   defesa: %.1f" % [("%.1f s" % cd) if cd > 0.0 else "pronta",
			("%.1f s" % left) if left > 0.0 else "—", Game.defense()])
		for m in Party.members:
			if int(m.peer) != multiplayer.get_unique_id():
				var bl := Party.buff_left(m, PartyShieldRules.BUFF)
				lines.append("buff de %s: %s" % [m.name, ("%.0f s" % bl) if bl > 0.0 else "—"])
	_label.text = "\n".join(lines)


func _other_peer() -> int:
	for pid in Network.remote_players:
		if is_instance_valid(Network.remote_players[pid]):
			return int(pid)
	return 0


func _unhandled_input(ev: InputEvent) -> void:
	if role != "host" or not _ready_done or not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	match ev.keycode:
		KEY_Y:
			Network.world.player.cooldowns[ID] = 0.0
		KEY_B:
			Network.send_chat(BOT_CAST)


## Companheiro: grita quando o anfitrião pede pelo chat.
func _on_chat(from: String, text: String) -> void:
	if role != "bot" or text != BOT_CAST or from == my_name or not _ready_done:
		return
	var me = Network.world.player if Network.world != null else null
	if me == null:
		return
	me.cooldowns[ID] = 0.0
	me.use_slot(5)
