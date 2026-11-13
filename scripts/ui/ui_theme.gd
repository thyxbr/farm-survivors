class_name UITheme
extends RefCounted
## Tema visual compartilhado (painéis escuros com borda dourada) e helpers de UI.

const GOLD := Color(0.86, 0.68, 0.32)
const TEXT := Color(0.93, 0.9, 0.82)
const DIM := Color(0.62, 0.6, 0.55)

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 18
	var panel := _box(Color(0.07, 0.07, 0.09, 0.93), GOLD.darkened(0.35), 2, 8)
	panel.content_margin_left = 18
	panel.content_margin_right = 18
	panel.content_margin_top = 14
	panel.content_margin_bottom = 14
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	t.set_stylebox("normal", "Button", _box(Color(0.16, 0.14, 0.12), GOLD.darkened(0.5), 1, 5, 10, 6))
	t.set_stylebox("hover", "Button", _box(Color(0.27, 0.22, 0.14), GOLD, 1, 5, 10, 6))
	t.set_stylebox("pressed", "Button", _box(Color(0.4, 0.3, 0.15), GOLD, 1, 5, 10, 6))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), GOLD.lightened(0.2), 1, 5, 10, 6))
	t.set_stylebox("disabled", "Button", _box(Color(0.1, 0.1, 0.1), Color(0.25, 0.25, 0.25), 1, 5, 10, 6))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 0.95, 0.75))
	t.set_color("font_disabled_color", "Button", Color(0.45, 0.45, 0.45))
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "ItemList", _box(Color(0.04, 0.04, 0.05, 0.8), Color(0.25, 0.22, 0.18), 1, 4, 6, 6))
	t.set_stylebox("selected", "ItemList", _box(Color(0.35, 0.27, 0.12), GOLD, 1, 3))
	t.set_stylebox("selected_focus", "ItemList", _box(Color(0.35, 0.27, 0.12), GOLD, 1, 3))
	t.set_stylebox("hovered", "ItemList", _box(Color(0.2, 0.17, 0.12), Color(0, 0, 0, 0), 0, 3))
	t.set_color("font_color", "ItemList", TEXT)
	t.set_constant("v_separation", "ItemList", 6)
	t.set_stylebox("panel", "TabContainer", _box(Color(0.07, 0.07, 0.09, 0.95), GOLD.darkened(0.35), 2, 6, 16, 14))
	t.set_stylebox("tab_selected", "TabContainer", _box(Color(0.3, 0.23, 0.12), GOLD, 1, 4, 14, 6))
	t.set_stylebox("tab_unselected", "TabContainer", _box(Color(0.12, 0.11, 0.1), Color(0.3, 0.27, 0.2), 1, 4, 14, 6))
	t.set_stylebox("tab_hovered", "TabContainer", _box(Color(0.2, 0.17, 0.12), GOLD.darkened(0.3), 1, 4, 14, 6))
	t.set_stylebox("background", "ProgressBar", _box(Color(0.05, 0.05, 0.06, 0.85), Color(0, 0, 0, 0.9), 1, 3))
	t.set_stylebox("grabber_area", "HSlider", _box(GOLD.darkened(0.2), Color(0, 0, 0, 0), 0, 3, 0, 3))
	t.set_stylebox("slider", "HSlider", _box(Color(0.15, 0.15, 0.15), Color(0, 0, 0, 0), 0, 3, 0, 3))
	_theme = t
	return t


static func _box(bg: Color, border: Color, bw: int, radius: int, mx := 0, my := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = mx
	s.content_margin_right = mx
	s.content_margin_top = my
	s.content_margin_bottom = my
	return s


static func bar(color: Color, w: float, h: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(w, h)
	b.show_percentage = false
	var fill := _box(color, color.lightened(0.25), 0, 3)
	b.add_theme_stylebox_override("fill", fill)
	return b


static func label(text: String, size := 18, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, cb: Callable, min_w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 40)
	b.pressed.connect(cb)
	return b


## Overlay de tela cheia escurecido com um painel centralizado.
static func centered_panel(parent: Node, dim := 0.55) -> PanelContainer:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = get_theme()
	parent.add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, dim)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var p := PanelContainer.new()
	center.add_child(p)
	return p
