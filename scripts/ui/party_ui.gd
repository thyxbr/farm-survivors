extends Control
## Janela do grupo ([P]): membros (o líder expulsa), sair do grupo e a lista de quem está online para
## convidar. No solo só explica que o grupo é do multiplayer.

signal closed

var _body: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	var p := UITheme.centered_panel(self, 0.45)
	p.custom_minimum_size = Vector2(560, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(UITheme.heading("Grupo", 30))
	v.add_child(UITheme.label("Quem está no grupo divide o XP dos monstros. O abate conta na missão de quem estiver"
		+ " perto do combate (até %d m)." % int(PartyRules.SHARE_RANGE), 15, UITheme.DIM))
	v.get_child(1).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.get_child(1).custom_minimum_size.x = 520
	v.add_child(HSeparator.new())
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	v.add_child(_body)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	foot.add_child(UITheme.spacer())
	foot.add_child(UITheme.keycap("P", 13))
	foot.add_child(UITheme.button("Fechar", _close, 140))
	v.add_child(foot)
	Party.changed.connect(_refresh)
	Network.players_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if not is_inside_tree():
		return
	for c in _body.get_children():
		c.queue_free()
	if not Network.is_online():
		_body.add_child(UITheme.label("O grupo é do multiplayer: entre em um servidor para jogar com outras pessoas.", 17))
		return
	var me := multiplayer.get_unique_id()
	_body.add_child(UITheme.section("Membros", 18))
	if not Party.in_party():
		_body.add_child(UITheme.label("Você não está em um grupo. Convide alguém da lista abaixo.", 16, UITheme.DIM))
	else:
		var lead := Party.am_leader()
		for m in Party.members:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			var who := "%s%s  ·  Nv %d" % ["♛ " if m.leader else "", m.name, int(m.level)]
			row.add_child(UITheme.label(who, 18, UITheme.GOLD if int(m.peer) == me else UITheme.TEXT))
			row.add_child(UITheme.spacer())
			if lead and int(m.peer) != me:
				row.add_child(UITheme.button("Expulsar", Party.request_kick.bind(int(m.peer)), 120))
			_body.add_child(row)
		_body.add_child(UITheme.button("Sair do grupo", Party.request_leave, 180))
	_body.add_child(UITheme.section("Online", 18))
	var any := false
	var can_invite := not Party.in_party() or (Party.am_leader() and Party.members.size() < PartyBook.MAX_MEMBERS)
	for pid in Network.players:
		if int(pid) == me or Party.is_member(int(pid)):
			continue
		any = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(UITheme.label(str(Network.players[pid].name), 17))
		row.add_child(UITheme.spacer())
		if can_invite:
			row.add_child(UITheme.button("Convidar", _invite.bind(int(pid)), 120))
		_body.add_child(row)
	if not any:
		_body.add_child(UITheme.label("Ninguém mais online agora.", 16, UITheme.DIM))
	elif not can_invite:
		_body.add_child(UITheme.label("Só o líder convida (e o grupo tem no máximo %d)." % PartyBook.MAX_MEMBERS, 14, UITheme.DIM))


func _invite(peer: int) -> void:
	Party.request_invite(peer)
	Sfx.play("click", 0.0)


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("party"):
		get_viewport().set_input_as_handled()
		_close()
