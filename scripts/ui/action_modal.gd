class_name ActionModal
extends Control
## Janelinha de confirmação por cima de uma estação (como a do canteiro no Albion): título, o ícone grande
## do que vai acontecer, algumas linhas (tempo, rendimento, custo) e dois botões — Cancelar e a ação em
## vermelho. Escurece só a estação por trás; Esc ou Cancelar fecha sem fazer nada.

signal confirmed

var _action: Button


## Abre sobre `parent`. `lines`: [texto, cor] (cor do tema escuro; vira tinta). Devolve a janelinha.
static func open(parent: Control, title: String, item_id: String, lines: Array, action_text: String,
		on_confirm: Callable, qty := 0) -> ActionModal:
	var m := ActionModal.new()
	m._build(title, item_id, lines, action_text, qty)
	m.confirmed.connect(on_confirm)
	parent.add_child(m)
	return m


func _build(title: String, item_id: String, lines: Array, action_text: String, qty: int) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.paper_theme()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)   # bloqueia o clique no que está por trás
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.parch_box())
	p.custom_minimum_size.x = 380
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var head := HBoxContainer.new()
	var t := UITheme.ink(title, 22, UITheme.INK, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(BookWindow.close_button(_cancel))
	v.add_child(head)
	v.add_child(UITheme.ornament())
	var slot := ItemSlot.new(96)
	slot.paper = true
	slot.model_icon = true
	slot.set_state(item_id, qty)
	slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(slot)
	for ln in lines:
		var l := UITheme.ink(str(ln[0]), 16, UITheme.paper_color(ln[1]) if ln.size() > 1 else UITheme.INK)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	_action = UITheme.primary(UITheme.button(action_text, _confirm))
	v.add_child(UITheme.footer(null, [UITheme.button("Cancelar", _cancel), _action]))


func _confirm() -> void:
	confirmed.emit()
	queue_free()


func _cancel() -> void:
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_cancel()
	elif event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		_confirm()
