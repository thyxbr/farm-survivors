extends Control
## Portal do Desafio da Horda: mostra a fila do servidor (quem abriu, membros e quanto falta) e leva à
## arena em Valdoria (Hub.go_horde abre ou entra na fila). No solo só começa o Desafio.

signal closed

var body: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	var p := UITheme.centered_panel(self, 0.55)
	p.custom_minimum_size = Vector2(640, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(UITheme.heading("Portal do Desafio da Horda", 30))
	v.add_child(UITheme.label("Ondas cada vez maiores; ao fim, os Ecos da rodada alcançada.", 15, UITheme.DIM))
	v.add_child(HSeparator.new())
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	v.add_child(body)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	foot.add_child(UITheme.spacer())
	foot.add_child(UITheme.keycap("E", 13))
	foot.add_child(UITheme.button("Sair", _close, 140))
	v.add_child(foot)
	Network.horde_changed.connect(_refresh)
	_refresh()


func _process(_delta: float) -> void:
	# o tempo da fila corre no Network.horde_lobby_t: só o texto muda por quadro
	if Network.is_online() and not Network.horde_lobby.is_empty() and body.has_meta("timer"):
		(body.get_meta("timer") as Label).text = "A fila fecha em %d s." % ceili(Network.horde_lobby_t)


func _refresh() -> void:
	for c in body.get_children():
		c.queue_free()
	if body.has_meta("timer"):
		body.remove_meta("timer")
	if not Network.is_online():
		body.add_child(UITheme.label("Jogando sozinho: a arena fica em Valdoria; ao terminar você volta para a praça.", 16, UITheme.TEXT))
		body.add_child(UITheme.button("Começar o Desafio", _enter, 260))
		return
	var q: Dictionary = Network.horde_lobby
	if q.is_empty():
		body.add_child(UITheme.label("Nenhuma fila aberta. Entre no portal para abrir uma: os outros jogadores recebem o convite.", 16, UITheme.TEXT))
		body.add_child(UITheme.button("Entrar no portal", _enter, 260))
		return
	body.add_child(UITheme.label("%s abriu uma fila." % q.get("leader", "?"), 18, UITheme.GOLD))
	var names: Array = q.get("names", [])
	body.add_child(UITheme.label("Na fila (%d): %s" % [names.size(), ", ".join(names)], 16, UITheme.TEXT))
	var t := UITheme.label("A fila fecha em %d s." % ceili(Network.horde_lobby_t), 15, UITheme.DIM)
	body.add_child(t)
	body.set_meta("timer", t)
	body.add_child(UITheme.button("Entrar no portal", _enter, 260))


func _enter() -> void:
	Hub.go_horde()


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_close()
