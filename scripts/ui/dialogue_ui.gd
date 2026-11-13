extends Control
## Caixa de diálogo com páginas, efeito de digitação e escolhas.

signal closed

var speaker := ""
var pages: Array = []
var index := 0
var text_label: RichTextLabel
var name_label: Label
var choices_box: HBoxContainer
var hint: Label
var _chars := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -440
	panel.offset_right = 440
	panel.offset_top = -250
	panel.offset_bottom = -30
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	name_label = UITheme.label(speaker, 24, UITheme.GOLD)
	v.add_child(name_label)
	text_label = RichTextLabel.new()
	text_label.fit_content = true
	text_label.custom_minimum_size = Vector2(840, 90)
	text_label.add_theme_font_size_override("normal_font_size", 20)
	text_label.add_theme_color_override("default_color", UITheme.TEXT)
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(text_label)
	choices_box = HBoxContainer.new()
	choices_box.add_theme_constant_override("separation", 12)
	v.add_child(choices_box)
	hint = UITheme.label("[E / Espaço / Clique] continuar", 14, UITheme.DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(hint)
	_show_page()


func _show_page() -> void:
	var page: Dictionary = pages[index]
	text_label.text = page.text
	text_label.visible_characters = 0
	_chars = 0.0
	for c in choices_box.get_children():
		c.queue_free()
	choices_box.visible = false
	hint.visible = false
	if page.has("on_show"):
		(page.on_show as Callable).call()


func _process(delta: float) -> void:
	var total := text_label.get_total_character_count()
	if text_label.visible_characters >= 0 and text_label.visible_characters < total:
		_chars += delta * 55.0
		text_label.visible_characters = int(_chars)
		if text_label.visible_characters >= total:
			_finish_typing()


func _finish_typing() -> void:
	text_label.visible_characters = -1
	var page: Dictionary = pages[index]
	if page.has("choices"):
		choices_box.visible = true
		for ch in page.choices:
			var b := UITheme.button(ch.text, _choose.bind(ch.action), 180)
			choices_box.add_child(b)
		(choices_box.get_child(0) as Button).grab_focus.call_deferred()
	else:
		hint.visible = true


func _choose(action: Callable) -> void:
	Sfx.play("click", 0.0)
	_close()
	if action.is_valid():
		action.call()


func _advance() -> void:
	if text_label.visible_characters != -1:
		_finish_typing()
		return
	if pages[index].has("choices"):
		return
	Sfx.play("click", 0.0)
	index += 1
	if index >= pages.size():
		_close()
	else:
		_show_page()


func _close() -> void:
	closed.emit()
	queue_free()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") or event.is_action_pressed("jump") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_advance()
	elif event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_close()
