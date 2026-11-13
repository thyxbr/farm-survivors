extends CanvasLayer
## Chat do multiplayer (canto inferior esquerdo).
##   [Enter] abre a caixa de texto · [Enter] envia · [Esc] cancela.
## As mensagens novas aparecem por alguns segundos e somem; com a caixa aberta, o histórico fica
## visível. Enquanto digita, o personagem fica parado (as teclas vão para o texto, não para o jogo).
## Funciona também com as cartas da Horda abertas (dá para combinar a build com o grupo).

const UI_CARDS := preload("res://scripts/ui/survival_ui.gd")
const MAX_LINES := 50
const VISIBLE_LINES := 7
const FADE_AFTER := 9.0
const WIDTH := 440.0

var world: Node
var _root: Control
var _panel: PanelContainer
var _scroll: ScrollContainer
var _log: VBoxContainer
var _entry: LineEdit
var _hint: Label
var _open := false
var _lines: Array = []   # [{"node": Control, "t": float}]


func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.get_theme()
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 18
	_panel.offset_right = 18 + WIDTH
	_panel.offset_top = -250
	_panel.offset_bottom = -150
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(v)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.custom_minimum_size = Vector2(WIDTH - 20, 0)
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_scroll)
	_log = VBoxContainer.new()
	_log.add_theme_constant_override("separation", 2)
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_log)
	_entry = LineEdit.new()
	_entry.placeholder_text = "Mensagem para todos..."
	_entry.max_length = Network.CHAT_MAX
	_entry.custom_minimum_size = Vector2(WIDTH - 20, 34)
	_entry.context_menu_enabled = false
	_entry.text_submitted.connect(_on_submit)
	v.add_child(_entry)
	_hint = UITheme.outlined("[Enter] chat", 13, Color(0.75, 0.72, 0.65, 0.7), 3)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_hint)
	_set_open(false)
	Network.chat_received.connect(_on_message)
	Network.players_changed.connect(_refresh_hint)
	_refresh_hint()


func is_open() -> bool:
	return _open


func _refresh_hint() -> void:
	if _hint:
		_hint.text = "[Enter] chat  ·  %d online" % Network.players.size()


## O chat pode abrir com o jogo livre ou com as cartas da Horda na tela; outras janelas usam o Enter.
func _can_open() -> bool:
	if world == null:
		return true
	var m: Control = world.get("modal")
	return m == null or m.get_script() == UI_CARDS


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: Key = event.keycode
	if _open:
		if k == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_set_open(false)
		return
	if (k == KEY_ENTER or k == KEY_KP_ENTER) and _can_open():
		get_viewport().set_input_as_handled()
		_set_open(true)


func _on_submit(text: String) -> void:
	var t := text.strip_edges()
	if t != "":
		Network.send_chat(t)
	_set_open(false)


func _set_open(on: bool) -> void:
	_open = on
	var sb := UITheme._box(Color(0.03, 0.03, 0.04, 0.78), UITheme.GOLD_DIM, 1, 8, 10, 8) if on \
		else UITheme._box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 8, 10, 8)
	_panel.add_theme_stylebox_override("panel", sb)
	_entry.visible = on
	_hint.visible = not on
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if on else ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS if on else Control.MOUSE_FILTER_IGNORE
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	var p: Player = world.get("player") if world else null
	if p:
		p.chat_typing = on
	if on:
		_entry.text = ""
		_entry.grab_focus()
	else:
		_entry.release_focus()
	_layout()


func _on_message(from: String, text: String) -> void:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WIDTH - 24
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("normal_font_size", 17)
	l.add_theme_font_size_override("bold_font_size", 17)
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	var safe := text.replace("[", "[lb]")
	if from == "":
		l.text = "[color=#ffb070]%s[/color]" % safe
	else:
		var mine := from == Network.my_name
		var col := "#9fd2ff" if mine else _name_color(from)
		l.text = "[b][color=%s]%s:[/color][/b] [color=#f0ebe0]%s[/color]" % [col, from.replace("[", "[lb]"), safe]
	_log.add_child(l)
	_lines.append({"node": l, "t": 0.0})
	while _lines.size() > MAX_LINES:
		var old: Dictionary = _lines.pop_front()
		if is_instance_valid(old.node):
			old.node.queue_free()
	if not _open:
		Sfx.play("click", 0.05, -8.0)
	_layout()
	_scroll_to_end.call_deferred()


## Cor estável por nome (cada jogador sempre com a mesma cor).
func _name_color(n: String) -> String:
	var hues := ["#ffd27a", "#a6f0a0", "#f5a0d0", "#c8b0ff", "#ffb38a", "#8ee6e0", "#f0e68c", "#ff9f9f"]
	return hues[abs(n.hash()) % hues.size()]


func _layout() -> void:
	var shown := 0
	for i in range(_lines.size() - 1, -1, -1):
		var e: Dictionary = _lines[i]
		var n: Control = e.node
		if not is_instance_valid(n):
			continue
		if _open:
			n.visible = true
			n.modulate.a = 1.0
		else:
			n.visible = shown < VISIBLE_LINES and e.t < FADE_AFTER + 1.0
			if n.visible:
				shown += 1
	_fit_scroll()


func _fit_scroll() -> void:
	var content := _log.get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = 230.0 if _open else minf(content, 420.0)


func _scroll_to_end() -> void:
	if _scroll:
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _process(delta: float) -> void:
	if _open:
		# a janela da Horda pode ter aberto por cima: o texto continua com o foco
		var p: Player = world.get("player") if world else null
		if p:
			p.chat_typing = true
		if not _entry.has_focus():
			_entry.grab_focus()
		return
	_fit_scroll()
	var changed := false
	for e in _lines:
		e.t += delta
		var n: Control = e.node
		if not is_instance_valid(n) or not n.visible:
			continue
		if e.t > FADE_AFTER:
			n.modulate.a = clampf(1.0 - (e.t - FADE_AFTER), 0.0, 1.0)
			if n.modulate.a <= 0.0:
				changed = true
	if changed:
		_layout()
