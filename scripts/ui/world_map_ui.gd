extends Control
## Mapa-mundi ([M]): a região inteira vista de cima, com os lugares, os NPCs, o destino da missão e, no
## multiplayer, só os companheiros de grupo. As abas trocam entre os mapas (Vale, Bosque, Mina, Pico);
## os que a guilda ainda não libera aparecem com o rank pedido.

signal closed

var world: Node
var capture: MapCapture
var _view: MapView
var _title: Label
var _tabs: HBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	var p := UITheme.centered_panel(self, 0.6)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	_title = UITheme.heading("", 28)
	head.add_child(_title)
	head.add_child(UITheme.spacer())
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	head.add_child(_tabs)
	var side := minf(get_viewport_rect().size.y - 190.0, get_viewport_rect().size.x - 120.0)
	_view = MapView.new()
	_view.mode = "full"
	_view.world = world
	_view.capture = capture
	_view.custom_minimum_size = Vector2(side, side)
	v.add_child(_view)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 14)
	v.add_child(foot)
	foot.add_child(_legend(MapView.C_PLAYER, "você"))
	if Network.is_online():
		foot.add_child(_legend(MapView.C_PARTY, "grupo"))
	foot.add_child(_legend(MapView.C_NPC, "NPC"))
	foot.add_child(_legend(MapView.C_QUEST, "missão"))
	foot.add_child(UITheme.spacer())
	foot.add_child(UITheme.keycap("M", 13))
	foot.add_child(UITheme.button("Fechar", _close, 130))
	var p3 = world.get("player") if world else null
	_show(Regions.region_at(p3.global_position) if p3 != null else "vila")


func _legend(c: Color, text: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var dot := ColorRect.new()
	dot.color = c
	dot.custom_minimum_size = Vector2(12, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(dot)
	h.add_child(UITheme.label(text, 15, UITheme.DIM))
	return h


func _show(region: String) -> void:
	_view.region = region
	_title.text = Regions.display_name(region)
	for c in _tabs.get_children():
		c.queue_free()
	for id in Regions.ORDER:
		var open := Regions.unlocked(id, Game.rank())
		var label := Regions.display_name(id).get_slice(" ", 0) if open else "%s (Rank %s)" % [Regions.display_name(id).get_slice(" ", 0), Regions.DATA[id].rank]
		var b := UITheme.button(label, _show.bind(id), 90)
		b.disabled = id == region or not open
		b.focus_mode = Control.FOCUS_NONE
		_tabs.add_child(b)
	_view.queue_redraw()


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("world_map"):
		get_viewport().set_input_as_handled()
		_close()
