extends Control
## Mapa-mundi em tela cheia (M): só o mapa (AtlasView), com zoom e fichas ao passar o mouse. Em cima, o
## título e os botões de zoom; embaixo, os atalhos e a legenda. M ou Esc fecha.

signal closed

var world: Node
var capture: MapCapture
var view: AtlasView
var _age := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	view = AtlasView.new()
	view.world = world
	view.capture = capture
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	add_child(_top_bar())
	add_child(_bottom_bar())
	view.grab_focus.call_deferred()


func _top_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 24
	bar.offset_right = -24
	bar.offset_top = 16
	bar.add_theme_constant_override("separation", 8)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(UITheme.outlined("Mapa de Valdoria", 30, UITheme.GOLD, 7))
	var sp := UITheme.spacer()
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(sp)
	for b in [["+", func() -> void: view.zoom_by(1.5)], ["−", func() -> void: view.zoom_by(1.0 / 1.5)],
			["Você", view.focus_player], ["Mundo", view.show_all], ["Fechar  M", _close]]:
		var btn := UITheme.button(b[0], b[1], 44)
		btn.focus_mode = Control.FOCUS_NONE
		bar.add_child(btn)
	return bar


func _bottom_bar() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.kit_inset(14))
	panel.anchor_left = 0.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 24
	panel.offset_bottom = -16
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)
	var keys := HBoxContainer.new()
	keys.add_theme_constant_override("separation", 6)
	for k in [["Roda", "zoom"], ["Arrastar", "mover"], ["Clique duplo", "aproximar na região"], ["Espaço", "você"]]:
		keys.add_child(UITheme.keycap(k[0], 13))
		keys.add_child(UITheme.label(k[1] + "   ", 14, UITheme.DIM))
	v.add_child(keys)
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 14)
	for l in [[AtlasView.C_PLAYER, "você"], [AtlasView.C_NPC, "personagens"], [Color(1, 0.8, 0.2), "! história"],
			[Color(0.45, 0.8, 1.0), "! contrato"], [Color(0.55, 1.0, 0.45), "? entregar"], [AtlasView.C_QUEST, "missão rastreada"],
			[AtlasView.C_ROUTE, "carruagem / saídas"]]:
		legend.add_child(_legend(l[0], l[1]))
	if Network.is_online():
		legend.add_child(_legend(AtlasView.C_PARTY, "grupo"))
	v.add_child(legend)
	return panel


func _legend(c: Color, text: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := ColorRect.new()
	dot.color = c
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(dot)
	h.add_child(UITheme.label(text, 14, UITheme.TEXT))
	return h


func _process(delta: float) -> void:
	_age += delta


func _unhandled_input(event: InputEvent) -> void:
	if _age < 0.15:
		return   # o mesmo M que abriu não fecha
	if event.is_action_pressed("pause") or event.is_action_pressed("world_map"):
		get_viewport().set_input_as_handled()
		_close()
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_SPACE:
				view.focus_player()
			KEY_EQUAL, KEY_KP_ADD:
				view.zoom_by(1.5)
			KEY_MINUS, KEY_KP_SUBTRACT:
				view.zoom_by(1.0 / 1.5)
			_:
				return
		get_viewport().set_input_as_handled()


func _close() -> void:
	closed.emit()
	queue_free()
