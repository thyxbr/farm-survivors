class_name HairPicker
extends GridContainer
## Penteados do corpo escolhido como miniaturas do rosto (tela de criação). Cada miniatura é um CharPreview
## pequeno em modo retrato que tira a foto e congela, então penteado novo em HairStyles aparece sozinho.

signal chosen(hair_id: String)

const THUMB := 80.0
## id do penteado -> Button.
var buttons := {}
var _group := ButtonGroup.new()


func _init() -> void:
	columns = 2
	add_theme_constant_override("h_separation", 8)
	add_theme_constant_override("v_separation", 8)


## Refaz as miniaturas com os penteados de `body` ("m"/"f").
func set_body(body: String) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	buttons.clear()
	_group = ButtonGroup.new()
	for id in HairStyles.STYLES.get(body, []):
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = _group
		b.custom_minimum_size = Vector2(THUMB + 6, THUMB + 26)
		b.tooltip_text = str(HairStyles.NAMES.get(id, id))
		for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			b.add_theme_stylebox_override(st, _box(st))
		b.pressed.connect(func() -> void: chosen.emit(id))
		var v := VBoxContainer.new()
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 3
		v.offset_top = 3
		v.offset_right = -3
		v.add_theme_constant_override("separation", 2)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(v)
		var p := CharPreview.new(Vector2(THUMB, THUMB))
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.bare = true
		p.show_body(body)
		p.show_hair(id)
		p.frame_face()
		p.freeze_after(6)
		v.add_child(p)
		var l := UITheme.label(b.tooltip_text, 11, UITheme.DIM)
		l.clip_text = true
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l)
		b.toggled.connect(func(on: bool) -> void: l.add_theme_color_override("font_color", UITheme.TEXT if on else UITheme.DIM))
		add_child(b)
		buttons[id] = b


## Marca o penteado `hair_id` sem emitir `chosen`.
func select(hair_id: String) -> void:
	if buttons.has(hair_id):
		for id in buttons:   # set_pressed_no_signal não desmarca os outros do grupo
			buttons[id].set_pressed_no_signal(id == hair_id)
			var l: Label = buttons[id].get_child(0).get_child(1)
			l.add_theme_color_override("font_color", UITheme.TEXT if id == hair_id else UITheme.DIM)


static func _box(state: String) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.09, 0.067, 0.05)
	s.set_border_width_all(2)
	s.set_corner_radius_all(6)
	match state:
		"pressed", "hover_pressed":
			s.border_color = UITheme.GOLD
			s.shadow_color = Color(UITheme.GOLD, 0.3)
			s.shadow_size = 5
		"hover":
			s.border_color = UITheme.GOLD_DIM
		"focus":
			s.draw_center = false
			s.border_color = Color(0, 0, 0, 0)
		_:
			s.border_color = Color(0.23, 0.17, 0.11)
	return s
