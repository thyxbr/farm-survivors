class_name UITheme
extends RefCounted
## Tema visual compartilhado: fantasia sombria (painéis quase pretos, molduras douradas duplas,
## títulos com fonte serifada) e helpers de UI.
## Referências: molduras por raridade e tooltips com comparação (Diablo / Path of Exile),
## barras com "rastro" de dano (Dark Souls), recarga radial (World of Warcraft).

const GOLD := Color(0.86, 0.68, 0.32)
const GOLD_DIM := Color(0.52, 0.4, 0.2)
const TEXT := Color(0.93, 0.9, 0.82)
const DIM := Color(0.62, 0.6, 0.55)
const BG := Color(0.055, 0.05, 0.05, 0.96)
const BG_INNER := Color(0.09, 0.08, 0.075, 0.95)
const GOOD := Color(0.45, 0.95, 0.45)
const BAD := Color(1.0, 0.42, 0.38)
const HP := Color(0.78, 0.1, 0.1)
const MP := Color(0.16, 0.36, 0.92)
const STAMINA := Color(0.42, 0.78, 0.3)
const XP := Color(0.85, 0.66, 0.2)

static var _theme: Theme
static var _serif: Font


## Fonte serifada para títulos (cai na fonte padrão se o sistema não tiver nenhuma).
static func serif() -> Font:
	if _serif:
		return _serif
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Cinzel", "Trajan Pro", "Palatino Linotype", "Book Antiqua", "Georgia",
		"Times New Roman", "serif"])
	f.font_weight = 600
	_serif = f
	return f


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 18
	var panel := frame_box()
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	t.set_stylebox("normal", "Button", _box(Color(0.15, 0.12, 0.1), GOLD_DIM, 1, 4, 12, 6))
	t.set_stylebox("hover", "Button", _box(Color(0.26, 0.2, 0.12), GOLD, 1, 4, 12, 6))
	t.set_stylebox("pressed", "Button", _box(Color(0.38, 0.28, 0.13), GOLD.lightened(0.2), 1, 4, 12, 6))
	t.set_stylebox("hover_pressed", "Button", _box(Color(0.38, 0.28, 0.13), GOLD.lightened(0.3), 1, 4, 12, 6))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), GOLD.lightened(0.2), 1, 4, 12, 6))
	t.set_stylebox("disabled", "Button", _box(Color(0.09, 0.09, 0.09), Color(0.22, 0.21, 0.2), 1, 4, 12, 6))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 0.95, 0.75))
	t.set_color("font_pressed_color", "Button", Color(1, 0.92, 0.6))
	t.set_color("font_hover_pressed_color", "Button", Color(1, 0.92, 0.6))
	t.set_color("font_disabled_color", "Button", Color(0.42, 0.41, 0.4))
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "ItemList", _box(Color(0.035, 0.032, 0.03, 0.85), Color(0.25, 0.21, 0.15), 1, 4, 6, 6))
	t.set_stylebox("selected", "ItemList", _box(Color(0.35, 0.27, 0.12), GOLD, 1, 3))
	t.set_stylebox("selected_focus", "ItemList", _box(Color(0.35, 0.27, 0.12), GOLD, 1, 3))
	t.set_stylebox("hovered", "ItemList", _box(Color(0.2, 0.17, 0.12), Color(0, 0, 0, 0), 0, 3))
	t.set_color("font_color", "ItemList", TEXT)
	t.set_constant("v_separation", "ItemList", 6)
	t.set_stylebox("panel", "TabContainer", frame_box())
	t.set_stylebox("tab_selected", "TabContainer", _box(Color(0.3, 0.23, 0.12), GOLD, 1, 4, 14, 6))
	t.set_stylebox("tab_unselected", "TabContainer", _box(Color(0.12, 0.11, 0.1), Color(0.3, 0.27, 0.2), 1, 4, 14, 6))
	t.set_stylebox("tab_hovered", "TabContainer", _box(Color(0.2, 0.17, 0.12), GOLD.darkened(0.3), 1, 4, 14, 6))
	t.set_stylebox("background", "ProgressBar", _box(Color(0.03, 0.03, 0.035, 0.9), Color(0, 0, 0, 0.9), 1, 2))
	t.set_stylebox("grabber_area", "HSlider", _box(GOLD.darkened(0.2), Color(0, 0, 0, 0), 0, 3, 0, 3))
	t.set_stylebox("slider", "HSlider", _box(Color(0.15, 0.15, 0.15), Color(0, 0, 0, 0), 0, 3, 0, 3))
	t.set_stylebox("separator", "HSeparator", _line(GOLD_DIM))
	t.set_constant("separation", "HSeparator", 10)
	var grab := _box(Color(0.4, 0.32, 0.18, 0.8), Color(0, 0, 0, 0), 0, 3)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", _box(GOLD_DIM, Color(0, 0, 0, 0), 0, 3))
	t.set_stylebox("grabber_pressed", "VScrollBar", _box(GOLD, Color(0, 0, 0, 0), 0, 3))
	t.set_stylebox("scroll", "VScrollBar", _box(Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 0, 3, 4, 0))
	t.set_color("default_color", "RichTextLabel", TEXT)
	_theme = t
	return t


## Painel principal: fundo escuro, borda dourada e sombra (aparência de moldura).
static func frame_box(bg := BG, border := GOLD_DIM, margin := 18) -> StyleBoxFlat:
	var s := _box(bg, border, 2, 6, margin, margin - 4)
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_size = 10
	s.border_blend = false
	return s


## Painel interno (seção dentro de uma janela).
static func inset_box(margin := 12) -> StyleBoxFlat:
	var s := _box(BG_INNER, Color(0.24, 0.2, 0.14), 1, 4, margin, margin - 2)
	return s


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


static func _line(c: Color) -> StyleBoxLine:
	var l := StyleBoxLine.new()
	l.color = c
	l.thickness = 1
	l.grow_begin = -4
	l.grow_end = -4
	return l


static func bar(color: Color, w: float, h: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(w, h)
	b.show_percentage = false
	var fill := _box(color, color.lightened(0.25), 0, 2)
	fill.border_width_top = 1 if h >= 8 else 0
	b.add_theme_stylebox_override("fill", fill)
	return b


static func label(text: String, size := 18, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Título com fonte serifada e contorno.
static func heading(text: String, size := 24, color := GOLD) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", serif())
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	return l


## Texto com contorno escuro (legível sobre o mundo 3D).
static func outlined(text: String, size := 18, color := TEXT, outline := 5) -> Label:
	var l := label(text, size, color)
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	return l


static func button(text: String, cb: Callable, min_w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 40)
	b.pressed.connect(cb)
	return b


## Tecla desenhada como "tecla de teclado" (para dicas de atalho).
static func keycap(key: String, size := 15) -> PanelContainer:
	var p := PanelContainer.new()
	var s := _box(Color(0.16, 0.14, 0.12), Color(0.55, 0.48, 0.36), 1, 4, 7, 1)
	s.border_width_bottom = 3
	p.add_theme_stylebox_override("panel", s)
	var l := label(key, size, Color(1, 0.95, 0.8))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Linha "título ─── " com ornamento, para cabeçalhos de seção.
static func section(text: String, size := 20) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var t := heading(text, size)
	h.add_child(t)
	var line := HSeparator.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(line)
	return h


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


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
