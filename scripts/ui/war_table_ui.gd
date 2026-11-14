extends Control
## Mesa de guerra: a Defesa da Cidade. Online mostra a sala do servidor (criar, entrar, pronto, começar,
## entrar na partida em andamento, sair) e o resultado da última defesa; no solo, "Nova cidade" e
## "Continuar cidade". A lógica da sala é a do antigo salão (lobby_ui), agora num painel da praça.

signal closed

var room_box: VBoxContainer
var result_box: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	var p := UITheme.centered_panel(self, 0.55)
	p.custom_minimum_size = Vector2(760, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(UITheme.heading("Mesa de Guerra", 30))
	v.add_child(UITheme.label("Defesa da Cidade: funde a cidade de dia e a defenda à noite.", 15, UITheme.DIM))
	v.add_child(HSeparator.new())
	result_box = VBoxContainer.new()
	result_box.add_theme_constant_override("separation", 4)
	v.add_child(result_box)
	room_box = VBoxContainer.new()
	room_box.add_theme_constant_override("separation", 8)
	v.add_child(room_box)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	foot.add_child(UITheme.spacer())
	foot.add_child(UITheme.keycap("E", 13))
	foot.add_child(UITheme.button("Sair", _close, 140))
	v.add_child(foot)
	Lobby.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if not is_inside_tree():
		return
	_refresh_result()
	for c in room_box.get_children():
		c.queue_free()
	if Network.is_online():
		_refresh_room()
	else:
		_refresh_solo()


func _refresh_solo() -> void:
	room_box.add_child(UITheme.label("Jogando sozinho: a cidade tem caixa e progresso próprios.", 15, UITheme.DIM))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	room_box.add_child(h)
	h.add_child(UITheme.button("Nova cidade", func() -> void: Game.start_colony(false), 200))
	var cont := UITheme.button("Continuar cidade", func() -> void: Game.start_colony(true), 220)
	cont.disabled = not Game.has_colony_save()
	h.add_child(cont)
	if Game.has_colony_save():
		room_box.add_child(UITheme.label(Game.colony_save_info(), 14, UITheme.DIM))


func _refresh_room() -> void:
	var r: Dictionary = Lobby.room
	var me := multiplayer.get_unique_id()
	if r.is_empty():
		room_box.add_child(UITheme.label("Nenhuma sala aberta.", 15, UITheme.DIM))
		room_box.add_child(UITheme.button("Criar sala", func() -> void: Lobby.room_send("create"), 240))
		return
	var names: Dictionary = r.get("names", {})
	var members: Array = r.get("members", [])
	var ready: Array = r.get("ready", [])
	var leader := int(r.get("leader", 0))
	if r.get("state", "") == "running":
		var phase := str(r.get("phase", ""))
		var where := "noite %d" % int(r.get("day", 1)) if phase == "night" else "dia %d" % int(r.get("day", 1))
		if phase == "setup":
			where = "fundando a cidade"
		var in_city: Array = r.get("in_city", [])
		var who: Array[String] = []
		for id in in_city:
			who.append(str(names.get(id, Network.players.get(id, {}).get("name", "?"))))
		room_box.add_child(UITheme.label("Partida em andamento — %s (%d/%d): %s" % [where, in_city.size(), int(r.get("max", 6)), ", ".join(who)], 16, UITheme.TEXT))
		var enter := UITheme.button("Entrar na partida", func() -> void: Lobby.room_send("enter"), 240)
		enter.disabled = in_city.size() >= int(r.get("max", 6))
		room_box.add_child(enter)
		room_box.add_child(UITheme.label("Quem entra no meio recebe as recompensas das noites que ajudar a vencer.", 13, UITheme.DIM))
		return
	for id in members:
		var tag := "  (líder)" if int(id) == leader else ""
		var ok: bool = id in ready or int(id) == leader
		room_box.add_child(UITheme.label("%s %s%s" % ["✔" if ok else "…", names.get(id, "?"), tag], 16, UITheme.GOOD if ok else UITheme.DIM))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	room_box.add_child(h)
	if not Lobby.in_room():
		var join := UITheme.button("Entrar na sala", func() -> void: Lobby.room_send("join"), 200)
		join.disabled = members.size() >= int(r.get("max", 6))
		h.add_child(join)
		return
	if Lobby.is_leader():
		var all_ready := true
		for id in members:
			if int(id) != me and not (id in ready):
				all_ready = false
		var start := UITheme.button("Começar", func() -> void: Lobby.room_send("start"), 160)
		start.disabled = not all_ready
		h.add_child(start)
		if not all_ready:
			room_box.add_child(UITheme.label("Esperando todos ficarem prontos.", 13, UITheme.DIM))
	else:
		h.add_child(UITheme.button("Não estou pronto" if Lobby.is_ready() else "Estou pronto",
			func() -> void: Lobby.room_send("unready" if Lobby.is_ready() else "ready"), 200))
	h.add_child(UITheme.button("Sair da sala", func() -> void: Lobby.room_send("leave"), 160))


func _refresh_result() -> void:
	for c in result_box.get_children():
		c.queue_free()
	var res: Dictionary = Lobby.last_result
	if res.is_empty():
		return
	var fell: bool = res.get("reason", "") == "defeat"
	result_box.add_child(UITheme.heading("Última defesa: %d noite(s)%s" % [int(res.get("nights", 0)), " — a cidade caiu" if fell else ""], 20,
		UITheme.BAD if fell else UITheme.GOLD))
	result_box.add_child(UITheme.label("Você ganhou +%d ouro, +%d XP e +%d Ecos." % [int(res.get("gold", 0)), int(res.get("xp", 0)),
		int(res.get("ecos", 0))], 15, UITheme.TEXT))
	result_box.add_child(UITheme.button("Ok", func() -> void:
		Lobby.last_result = {}
		_refresh(), 100))
	result_box.add_child(HSeparator.new())


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_close()
