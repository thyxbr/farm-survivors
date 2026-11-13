extends CanvasLayer
## Multiplayer: convite e fila do Desafio da Horda. Painel no canto da tela que não pausa nem trava o
## jogo. Quem ainda não respondeu vê "[Y] Entrar · [N] Recusar"; quem está na fila vê o grupo, a
## contagem e "[N] Sair da fila". As teclas funcionam com o mouse preso na câmera.

var world: Node
var _panel: PanelContainer
var _text: Label
var _names: Label
var _timer: Label
var _yes: Button
var _no: Button


func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UITheme.frame_box(UITheme.BG, Color(0.6, 0.42, 0.9), 14))
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -390
	_panel.offset_right = -20
	_panel.offset_top = 170
	root.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_panel.add_child(v)
	v.add_child(UITheme.heading("Desafio da Horda", 22, Color(0.85, 0.65, 1.0)))
	_text = UITheme.label("", 17)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = 340
	v.add_child(_text)
	_names = UITheme.label("", 15, Color(0.75, 0.9, 1.0))
	_names.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_names.custom_minimum_size.x = 340
	v.add_child(_names)
	_timer = UITheme.label("", 15, UITheme.DIM)
	v.add_child(_timer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_yes = UITheme.button("[Y] Entrar", _accept, 160)
	_no = UITheme.button("[N] Recusar", _decline, 160)
	for b in [_yes, _no]:
		b.focus_mode = Control.FOCUS_NONE   # não rouba Espaço/Enter do jogo
		row.add_child(b)
	_panel.visible = false
	Network.horde_changed.connect(_refresh)


## "" (escondido) | "invite" (convite sem resposta) | "member" (já na fila)
func state() -> String:
	if Network.horde_lobby.is_empty() or (world and world.get("survival") != null):
		return ""
	if Network.in_horde_lobby():
		return "member"
	if Network.horde_invite_pending():
		return "invite"
	return ""


func _refresh() -> void:
	var st := state()
	_panel.visible = st != ""
	if st == "":
		return
	var lob: Dictionary = Network.horde_lobby
	if st == "invite":
		_text.text = "%s abriu o Portal do Desafio! Entre para lutar na mesma arena." % lob.get("leader", "?")
		_yes.visible = true
		_no.text = "[N] Recusar"
	else:
		_text.text = "Você está no grupo. Todos vão juntos para a arena quando a contagem acabar."
		_yes.visible = false
		_no.text = "[N] Sair da fila"
	_names.text = "No grupo: " + ", ".join(lob.get("names", []))


func _process(_delta: float) -> void:
	if _panel.visible != (state() != ""):
		_refresh()
	if _panel.visible:
		_timer.text = "Começa em %ds" % int(ceil(Network.horde_lobby_t))


func _unhandled_input(event: InputEvent) -> void:
	if not _panel.visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_Y:
			if state() == "invite":
				get_viewport().set_input_as_handled()
				_accept()
		KEY_N:
			get_viewport().set_input_as_handled()
			_decline()


func _accept() -> void:
	Network.horde_answer(true)
	Sfx.play("pickup", 0.0)


func _decline() -> void:
	Network.horde_answer(false)
