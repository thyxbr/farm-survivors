extends Control
## Escolha de um evento da expedição (ExpeditionEvents): o texto do lugar e uma opção por linha. Modal (o mundo pausa
## o jogo enquanto está aberta). Escolher fecha a tela; quem aplica é o modo da expedição (expedition.choose_event).
## Esc fecha sem escolher: o santuário continua lá e pode ser examinado de novo.

signal closed

const LOCK := 0.35

var expedition: Node
var room := ""
var event_id := ""
var _buttons: Array[Button] = []
var _options: Array = []
var _lock := LOCK


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ev := ExpeditionEvents.info(event_id)
	_options = ExpeditionEvents.options(event_id)
	var p := UITheme.centered_panel(self, 0.6)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var title := UITheme.outlined(str(ev.get("title", room)), 32, Color(0.95, 0.45, 0.4), 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var text := UITheme.label(str(ev.get("text", "")), 18, UITheme.TEXT)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = 640
	v.add_child(text)
	for i in _options.size():
		var o: Dictionary = _options[i]
		var c: Color = o.get("color", UITheme.GOLD)
		var b := Button.new()
		b.custom_minimum_size = Vector2(660, 74)
		b.focus_mode = Control.FOCUS_ALL
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0.08, 0.07, 0.07, 0.97)
		normal.border_color = c.darkened(0.35)
		normal.set_border_width_all(2)
		normal.set_corner_radius_all(8)
		var hover := normal.duplicate() as StyleBoxFlat
		hover.bg_color = Color(0.15, 0.11, 0.1, 1.0)
		hover.border_color = c
		hover.set_border_width_all(3)
		for s in ["normal", "hover", "focus", "pressed"]:
			b.add_theme_stylebox_override(s, normal if s == "normal" else hover)
		b.pressed.connect(_pick.bind(i))
		v.add_child(b)
		_buttons.append(b)
		var m := MarginContainer.new()
		m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side in ["left", "right", "top", "bottom"]:
			m.add_theme_constant_override("margin_" + side, 12)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(m)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_child(col)
		var name_l := UITheme.label("[%d]  %s" % [i + 1, str(o.get("name", ""))], 20, c.lightened(0.2))
		var desc := UITheme.label(str(o.get("desc", "")), 16)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		for l in [name_l, desc]:
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_child(l)
	var hint := UITheme.label("Os efeitos valem só até o fim desta expedição.  Esc: decidir depois", 15, UITheme.DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)
	if not _buttons.is_empty():
		_buttons[0].grab_focus.call_deferred()


func _process(delta: float) -> void:
	_lock = maxf(0.0, _lock - delta)


## Escolhe a opção `i`. Também usada pelos testes (sem esperar o _lock: `force`).
func pick(i: int, force := false) -> bool:
	if force:
		_lock = 0.0
	return _pick(i)


func _pick(i: int) -> bool:
	if _lock > 0.0 or i < 0 or i >= _options.size() or is_queued_for_deletion() or expedition == null:
		return false
	if not expedition.choose_event(str(_options[i].get("id", ""))):
		return false
	_close()
	return true


func _close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_close()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var idx: int = [KEY_1, KEY_2, KEY_3].find(event.physical_keycode)
	if idx >= 0:
		get_viewport().set_input_as_handled()
		_pick(idx)
