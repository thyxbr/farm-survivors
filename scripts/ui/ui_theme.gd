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
static var _body: Font


## Fonte dos títulos: Cinzel embutida (assets/fonts, licença OFL); sem o arquivo, a serifada do sistema.
static func serif() -> Font:
	if _serif == null:
		var f := _load_font("res://assets/fonts/Cinzel.ttf", ["Cinzel", "Trajan Pro", "Palatino Linotype",
			"Book Antiqua", "Georgia", "Times New Roman", "serif"])
		if f is FontFile:
			# a Cinzel é variável e o peso normal fica fino demais em título pequeno: usa 600
			var heavy := FontVariation.new()
			heavy.base_font = f
			heavy.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600}
			f = heavy
		_serif = f
	return _serif


## Fonte do texto corrido das telas do livro: EB Garamond embutida; sem o arquivo, a serifada do sistema.
static func body() -> Font:
	if _body == null:
		_body = _load_font("res://assets/fonts/EBGaramond.ttf", ["EB Garamond", "Garamond", "Palatino Linotype",
			"Georgia", "Times New Roman", "serif"])
	return _body


## Fonte do arquivo `path`; se não existir ou não carregar, uma fonte do sistema com os nomes de `fallback`.
static func _load_font(path: String, fallback: Array) -> Font:
	if ResourceLoader.exists(path):
		var f := load(path) as FontFile
		if f:
			return f
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(fallback)
	sys.font_weight = 600
	return sys


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 18
	var panel := kit_panel()
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	# botões do kit (madeira com moldura dourada); sem as texturas, as caixas lisas de antes
	t.set_stylebox("normal", "Button", _kit_button("normal", _box(Color(0.15, 0.12, 0.1), GOLD_DIM, 1, 4, 12, 6)))
	t.set_stylebox("hover", "Button", _kit_button("hover", _box(Color(0.26, 0.2, 0.12), GOLD, 1, 4, 12, 6)))
	t.set_stylebox("pressed", "Button", _kit_button("pressed", _box(Color(0.38, 0.28, 0.13), GOLD.lightened(0.2), 1, 4, 12, 6)))
	t.set_stylebox("hover_pressed", "Button", _kit_button("pressed", _box(Color(0.38, 0.28, 0.13), GOLD.lightened(0.3), 1, 4, 12, 6)))
	t.set_stylebox("focus", "Button", _kit("focus", 14, 0, 12, 6, _box(Color(0, 0, 0, 0), GOLD.lightened(0.2), 1, 4, 12, 6)))
	t.set_stylebox("disabled", "Button", _kit_button("disabled", _box(Color(0.09, 0.09, 0.09), Color(0.22, 0.21, 0.2), 1, 4, 12, 6)))
	# caixa de marcar herdaria a madeira do botão: fica só com o texto e a marca
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(st, "CheckBox", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 4, 6, 4))
	t.set_stylebox("hover", "CheckBox", _box(Color(1, 0.85, 0.5, 0.06), Color(0, 0, 0, 0), 0, 4, 6, 4))
	for pair in [["checked", "check_on"], ["unchecked", "check_off"], ["checked_disabled", "check_on_disabled"],
			["unchecked_disabled", "check_off_disabled"]]:
		_kit_icon(t, pair[0], "CheckBox", pair[1])
	_kit_icon(t, "grabber", "HSlider", "knob")
	_kit_icon(t, "grabber_highlight", "HSlider", "knob_hover")
	# campo de texto afundado com aro dourado
	t.set_stylebox("normal", "LineEdit", _kit("field", 10, 0, 12, 6, _box(Color(0.04, 0.035, 0.03), GOLD_DIM, 1, 4, 12, 6)))
	t.set_stylebox("focus", "LineEdit", _kit("field_focus", 10, 0, 12, 6, _box(Color(0, 0, 0, 0), GOLD, 1, 4, 12, 6)))
	t.set_stylebox("read_only", "LineEdit", _kit("field", 10, 0, 12, 6, _box(Color(0.04, 0.035, 0.03), GOLD_DIM, 1, 4, 12, 6)))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(DIM.r, DIM.g, DIM.b, 0.7))
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_color("selection_color", "LineEdit", Color(GOLD.r, GOLD.g, GOLD.b, 0.35))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 0.95, 0.75))
	t.set_color("font_pressed_color", "Button", Color(1, 0.92, 0.6))
	t.set_color("font_hover_pressed_color", "Button", Color(1, 0.92, 0.6))
	t.set_color("font_disabled_color", "Button", Color(0.42, 0.41, 0.4))
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "ItemList", _kit("panel_inset", 14, 6, 8, 8, _box(Color(0.035, 0.032, 0.03, 0.85), Color(0.25, 0.21, 0.15), 1, 4, 6, 6)))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())   # a borda branca padrão do Godot destoava do kit
	t.set_stylebox("selected", "ItemList", _box(Color(0.35, 0.27, 0.12), GOLD, 1, 3))
	t.set_stylebox("selected_focus", "ItemList", _box(Color(0.35, 0.27, 0.12), GOLD, 1, 3))
	t.set_stylebox("hovered", "ItemList", _box(Color(0.2, 0.17, 0.12), Color(0, 0, 0, 0), 0, 3))
	t.set_color("font_color", "ItemList", TEXT)
	t.set_constant("v_separation", "ItemList", 6)
	t.set_stylebox("panel", "TabContainer", kit_panel())
	t.set_stylebox("tab_selected", "TabContainer", _kit_tab("tab_selected", _box(Color(0.3, 0.23, 0.12), GOLD, 1, 4, 14, 6)))
	t.set_stylebox("tab_unselected", "TabContainer", _kit_tab("tab_unselected", _box(Color(0.12, 0.11, 0.1), Color(0.3, 0.27, 0.2), 1, 4, 14, 6)))
	t.set_stylebox("tab_hovered", "TabContainer", _kit_tab("tab_hover", _box(Color(0.2, 0.17, 0.12), GOLD.darkened(0.3), 1, 4, 14, 6)))
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


# ------------------------------------------------------------------ kit de UI (assets/ui/kit)
## Texturas 9-slice geradas por tools/ui_kit/make_ui_kit.py: madeira escura e moldura dourada com rebites,
## no estilo da logo. Cada peça tem uma borda transparente (`pad`: brilho ou sombra) que fica para fora do
## controle (expand_margin), então o retângulo do controle é a moldura em si.
const KIT := "res://assets/ui/kit/"


## Caixa com a textura `name` do kit (cantos de `margin` px não esticam). Sem o arquivo, devolve `fallback`.
static func _kit(name: String, margin: int, pad: int, mx: int, my: int, fallback: StyleBox) -> StyleBox:
	var path := KIT + name + ".png"
	if not ResourceLoader.exists(path):
		return fallback
	var s := StyleBoxTexture.new()
	s.texture = load(path)
	s.set_texture_margin_all(margin + pad)
	s.set_expand_margin_all(pad)
	s.content_margin_left = mx
	s.content_margin_right = mx
	s.content_margin_top = my
	s.content_margin_bottom = my
	return s


## Ícone `icon` do tipo `type` com a textura `name` do kit (sem o arquivo, fica o ícone padrão).
static func _kit_icon(t: Theme, icon: String, type: String, name: String) -> void:
	var path := KIT + name + ".png"
	if ResourceLoader.exists(path):
		t.set_icon(icon, type, load(path))


static func _kit_button(state: String, fallback: StyleBox) -> StyleBox:
	return _kit("button_" + state, 13, 3, 16, 6, fallback)


static func _kit_tab(name: String, fallback: StyleBox) -> StyleBox:
	var s := _kit(name, 11, 0, 16, 6, fallback)
	if s is StyleBoxTexture:
		(s as StyleBoxTexture).texture_margin_bottom = 4
	return s


## Janela principal do kit: madeira escura, moldura dourada dupla e rebites nos cantos.
static func kit_panel(margin := 22) -> StyleBox:
	return _kit("panel", 20, 6, margin, margin - 4, frame_box(BG, GOLD_DIM, margin))


## Seção interna do kit (painel menor, moldura simples).
static func kit_inset(margin := 12) -> StyleBox:
	return _kit("panel_inset", 14, 6, margin, margin - 2, inset_box(margin))


## Moldura de espaço de item/ícone.
static func kit_slot() -> StyleBox:
	return _kit("slot", 8, 0, 4, 4, _box(Color(0.06, 0.05, 0.045), GOLD_DIM, 1, 4, 4, 4))


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


# ================================================================ peças renderizadas (assets/ui)


static func tex(name: String) -> Texture2D:
	return load("res://assets/ui/%s.png" % name)


static func _tex_box(name: String, ml: int, mt: int, cx: int, cy: int, expand := 0) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = tex(name)
	s.texture_margin_left = ml
	s.texture_margin_right = ml
	s.texture_margin_top = mt
	s.texture_margin_bottom = mt
	s.content_margin_left = cx
	s.content_margin_right = cx
	s.content_margin_top = cy
	s.content_margin_bottom = cy
	s.set_expand_margin_all(expand)
	return s




# ================================================================ grimório (páginas de pergaminho)
const INK := Color(0.2, 0.12, 0.06)
const INK_DIM := Color(0.42, 0.31, 0.2)
const INK_RED := Color(0.55, 0.11, 0.07)
const INK_GOLD := Color(0.45, 0.27, 0.02)
## Pergaminho das janelas laterais (assets/ui/kit/win_frame.png) e a madeira da moldura.
const PAGE := Color(0.914, 0.839, 0.675)
const PAGE_EDGE := Color(0.24, 0.16, 0.1)
const BRONZE := Color(0.69, 0.53, 0.28)
## Texto sobre botão ligado (couro escuro).
const ON_LEATHER := Color(0.97, 0.9, 0.74)
## Espaço de item das janelas: aço azulado escuro, como uma moldura de metal sobre o papel.
const SLOT_BG := Color(0.2, 0.23, 0.27)
const SLOT_EDGE := Color(0.46, 0.51, 0.57)
static var _paper: Theme


## Texto a tinta (sem contorno); `title` usa a fonte serifada.
static func ink(text: String, size := 16, color := INK, title := false) -> Label:
	var l := label(text, size if title else size + 2, color)
	l.add_theme_font_override("font", serif() if title else body())
	return l


## Cor clara do tema escuro (raridade, elemento) escurecida até dar para ler sobre o papel.
static func on_paper(c: Color) -> Color:
	var d := c.darkened(0.35)
	var lum := d.get_luminance()
	return d.darkened(1.0 - 0.33 / lum) if lum > 0.33 else d


static func _ink_box(fill: float, border: float, bw := 1) -> StyleBoxFlat:
	var s := _box(Color(INK.r, INK.g, INK.b, fill), Color(INK.r, INK.g, INK.b, border), bw, 3, 12, 4)
	return s


static func paper_theme() -> Theme:
	if _paper:
		return _paper
	var t: Theme = get_theme().duplicate()
	t.default_font = body()
	t.default_font_size = 20      # a Garamond é menor que a fonte padrão no mesmo tamanho
	# botões de pergaminho com bisel; ligado (aba, filtro) é couro escuro com texto claro
	t.set_stylebox("normal", "Button", win_btn("win_btn", _ink_box(0.06, 0.55)))
	t.set_stylebox("hover", "Button", win_btn("win_btn_hover", _ink_box(0.16, 0.8)))
	t.set_stylebox("pressed", "Button", win_btn("win_btn_on", _ink_box(0.78, 0.9)))
	t.set_stylebox("hover_pressed", "Button", win_btn("win_btn_on", _ink_box(0.85, 1.0)))
	t.set_stylebox("disabled", "Button", win_btn("win_btn_off", _ink_box(0.0, 0.2)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", ON_LEATHER)
	t.set_color("font_hover_pressed_color", "Button", ON_LEATHER)
	t.set_color("font_disabled_color", "Button", Color(INK.r, INK.g, INK.b, 0.4))
	t.set_color("font_color", "Label", INK)
	t.set_stylebox("separator", "HSeparator", _line(Color(0.45, 0.31, 0.15, 0.7)))
	t.set_stylebox("separator", "VSeparator", _line(Color(0.45, 0.31, 0.15, 0.7)))
	t.set_stylebox("grabber", "VScrollBar", _box(Color(INK.r, INK.g, INK.b, 0.5), Color(0, 0, 0, 0), 0, 3))
	t.set_stylebox("grabber_highlight", "VScrollBar", _box(Color(INK.r, INK.g, INK.b, 0.7), Color(0, 0, 0, 0), 0, 3))
	t.set_stylebox("grabber_pressed", "VScrollBar", _box(INK, Color(0, 0, 0, 0), 0, 3))
	t.set_stylebox("scroll", "VScrollBar", _box(Color(INK.r, INK.g, INK.b, 0.1), Color(0, 0, 0, 0), 0, 3, 4, 0))
	# abas: selecionada é tinta cheia com texto cor de papel; linha de lista selecionada é só um realce
	# (as linhas têm cor própria — pronta, sem estoque — que sumiria na tinta cheia)
	t.set_stylebox("panel", "ItemList", win_inset(10, _ink_box(0.05, 0.4)))
	t.set_stylebox("selected", "ItemList", _ink_box(0.16, 0.85, 2))
	t.set_stylebox("selected_focus", "ItemList", _ink_box(0.16, 0.85, 2))
	t.set_stylebox("hovered", "ItemList", _ink_box(0.14, 0.0, 0))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_color("font_color", "ItemList", INK)
	t.set_color("font_hovered_color", "ItemList", INK)
	t.set_color("font_selected_color", "ItemList", INK)
	t.set_stylebox("panel", "TabContainer", win_inset(10, _ink_box(0.04, 0.45)))
	t.set_stylebox("tab_selected", "TabContainer", win_btn("win_btn_on", _ink_box(0.78, 0.9)))
	t.set_stylebox("tab_unselected", "TabContainer", win_btn("win_btn", _ink_box(0.06, 0.4)))
	t.set_stylebox("tab_hovered", "TabContainer", win_btn("win_btn_hover", _ink_box(0.16, 0.7)))
	t.set_stylebox("tab_focus", "TabContainer", StyleBoxEmpty.new())
	t.set_color("font_selected_color", "TabContainer", ON_LEATHER)
	t.set_color("font_unselected_color", "TabContainer", INK)
	t.set_color("font_hovered_color", "TabContainer", INK)
	# barras e deslizadores
	t.set_stylebox("background", "ProgressBar", _box(Color(INK.r, INK.g, INK.b, 0.16), Color(INK.r, INK.g, INK.b, 0.6), 1, 2))
	t.set_stylebox("slider", "HSlider", _box(Color(INK.r, INK.g, INK.b, 0.2), Color(0, 0, 0, 0), 0, 3, 0, 3))
	t.set_stylebox("grabber_area", "HSlider", _box(INK_RED, Color(0, 0, 0, 0), 0, 3, 0, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(INK_RED.lightened(0.15), Color(0, 0, 0, 0), 0, 3, 0, 3))
	# campo de texto, caixa de marcar e seletor
	var focus := _ink_box(0.04, 1.0, 2)
	t.set_stylebox("normal", "LineEdit", win_inset(10, _ink_box(0.05, 0.55)))
	t.set_stylebox("focus", "LineEdit", focus)
	t.set_stylebox("read_only", "LineEdit", _ink_box(0.0, 0.25))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(INK.r, INK.g, INK.b, 0.45))
	t.set_color("caret_color", "LineEdit", INK)
	t.set_color("selection_color", "LineEdit", Color(INK_RED.r, INK_RED.g, INK_RED.b, 0.3))
	for type in ["CheckBox", "OptionButton"]:
		t.set_stylebox("normal", type, win_btn("win_btn", _ink_box(0.06, 0.55)))
		t.set_stylebox("hover", type, win_btn("win_btn_hover", _ink_box(0.16, 0.8)))
		t.set_stylebox("pressed", type, win_btn("win_btn_hover", _ink_box(0.16, 0.8)))
		t.set_stylebox("focus", type, focus)
		t.set_color("font_color", type, INK)
		t.set_color("font_hover_color", type, INK)
		t.set_color("font_pressed_color", type, INK)
		t.set_color("font_focus_color", type, INK)
	# menus suspensos e dicas: um pedaço de papel por cima da página
	var sheet := _box(PAGE, PAGE_EDGE, 2, 3, 10, 6)
	sheet.shadow_color = Color(0, 0, 0, 0.35)
	sheet.shadow_size = 6
	t.set_stylebox("panel", "PopupMenu", sheet)
	t.set_stylebox("hover", "PopupMenu", _ink_box(0.18, 0.0, 0))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", INK)
	t.set_stylebox("panel", "TooltipPanel", sheet)
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_color("default_color", "RichTextLabel", INK)
	_paper = t
	return t


## Título de seção a tinta: vermelho, na serifada, com uma linha até o fim (o par de `section()`).
static func ink_section(text: String, size := 18) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(ink(text, size, INK_RED, true))
	var line := HSeparator.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_theme_stylebox_override("separator", _line(Color(INK.r, INK.g, INK.b, 0.45)))
	h.add_child(line)
	return h


## Barra de progresso sobre papel: fundo de tinta clara, preenchimento na cor pedida.
static func ink_bar(color: Color, w: float, h: float) -> ProgressBar:
	var b := bar(color.darkened(0.15), w, h)
	b.add_theme_stylebox_override("background", _box(Color(INK.r, INK.g, INK.b, 0.16), Color(INK.r, INK.g, INK.b, 0.6), 1, 2))
	return b


## Quadro rebaixado para subdividir uma página (o par de `inset_box()`).
static func ink_inset(margin := 12) -> StyleBox:
	return win_inset(margin, _box(Color(INK.r, INK.g, INK.b, 0.05), Color(INK.r, INK.g, INK.b, 0.4), 1, 4, margin, margin - 2))


# ================================================================ janelas laterais (WindowDock)
## Distância das janelas até a borda da tela.
const DOCK_MARGIN := 16.0


## Fundo de uma janela lateral: moldura de madeira com friso de bronze e cantoneiras, pergaminho dentro
## (assets/ui/kit/win_frame.png, gerado por tools/ui_kit/make_window_kit.py). `margin` é o respiro entre o
## friso e o conteúdo.
static func parch_box(margin := 8) -> StyleBox:
	var fb := _box(PAGE, PAGE_EDGE, 3, 8, margin + 12, margin + 10)
	return _win_tex("win_frame_" + frame_style(), 30, 13 + margin, 12 + margin, fb)


## Moldura pequena (dica de item): o mesmo material com friso fino.
static func small_frame(margin := 6) -> StyleBox:
	var fb := _box(PAGE, PAGE_EDGE, 2, 4, margin + 6, margin + 5)
	return _win_tex("win_frame_small_" + frame_style(), 16, 8 + margin, 7 + margin, fb)


## Material da moldura das janelas (tools/ui_kit/frame_styles.py). Comparadas A (madeira e bronze),
## B (ferro forjado) e C (couro costurado) em 20/11/2026; o dono do projeto escolheu a B.
static func frame_style() -> String:
	return "b"


## Botão de pergaminho do kit das janelas (`name` = win_btn, win_btn_hover, win_btn_on, win_btn_off, win_btn_red).
static func win_btn(name: String, fallback: StyleBox) -> StyleBox:
	return _win_tex(name, 7, 12, 5, fallback)


## Quadro rebaixado no papel (seções, listas, campos).
static func win_inset(margin: int, fallback: StyleBox) -> StyleBox:
	return _win_tex("win_inset", 8, margin, margin - 2, fallback)


static func _win_tex(name: String, tm: int, cx: int, cy: int, fallback: StyleBox) -> StyleBox:
	var path := KIT + name + ".png"
	if not ResourceLoader.exists(path):
		return fallback
	var s := StyleBoxTexture.new()
	s.texture = load(path)
	s.set_texture_margin_all(tm)
	s.content_margin_left = cx
	s.content_margin_right = cx
	s.content_margin_top = cy
	s.content_margin_bottom = cy
	return s


## Botão da ação principal da janela (Comprar, Fabricar, Plantar): vermelho com texto claro.
static func primary(b: Button) -> Button:
	b.add_theme_stylebox_override("normal", win_btn("win_btn_red", _box(Color(0.59, 0.16, 0.11), Color(0.27, 0.06, 0.04), 2, 4, 12, 5)))
	var hov := win_btn("win_btn_red", _box(Color(0.68, 0.2, 0.14), Color(0.27, 0.06, 0.04), 2, 4, 12, 5))
	if hov is StyleBoxTexture:
		(hov as StyleBoxTexture).modulate_color = Color(1.15, 1.1, 1.1)
	b.add_theme_stylebox_override("hover", hov)
	var down := win_btn("win_btn_red", _box(Color(0.45, 0.1, 0.07), Color(0.27, 0.06, 0.04), 2, 4, 12, 5))
	if down is StyleBoxTexture:
		(down as StyleBoxTexture).modulate_color = Color(0.82, 0.8, 0.8)
	b.add_theme_stylebox_override("pressed", down)
	b.add_theme_stylebox_override("disabled", win_btn("win_btn_off", _box(PAGE.darkened(0.1), INK_DIM, 1, 4, 12, 5)))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, ON_LEATHER)
	b.set_meta("_primary", true)
	return b


## Rodapé das janelas: a dica numa linha própria (quebra linha, nunca é espremida pelos botões) e, embaixo,
## os botões alinhados à direita, todos da mesma altura e com largura pelo texto. Ordem: secundários, a ação
## principal (vermelha) e por último "Sair". Sem selo de tecla: Esc fecha qualquer janela.
static func footer(hint: Label, buttons: Array) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	if hint != null:
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hint.custom_minimum_size.x = 120
		v.add_child(hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_END
	for b: Button in buttons:
		b.custom_minimum_size = Vector2(110, 36)
		b.size_flags_horizontal = Control.SIZE_SHRINK_END
		b.add_theme_font_size_override("font_size", 16)
		row.add_child(b)
	v.add_child(row)
	return v


## Ornamento de bronze (linha com losango) para separar o título do conteúdo.
static func ornament() -> Control:
	var path := KIT + "win_divider.png"
	if not ResourceLoader.exists(path):
		return HSeparator.new()
	var r := TextureRect.new()
	r.texture = load(path)
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	r.custom_minimum_size.y = 14
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Janela de estação (loja, bancada, horta...) encaixada num lado da tela, sem escurecer o mundo: devolve o
## painel de pergaminho onde a tela monta o conteúdo. O resto da tela não bloqueia o mouse, então outra
## janela (o inventário, do outro lado) continua clicável. As cores do tema escuro viram tinta (PaperInk).
static func dock_panel(parent: Control, side := "left") -> PanelContainer:
	parent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = paper_theme()
	parent.add_child(root)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", parch_box())
	root.add_child(p)
	var place := func() -> void:
		var sz := p.get_combined_minimum_size()
		if p.size != sz:
			p.size = sz   # encolhe junto quando o conteúdo diminui (o Control sozinho só cresce)
		var x := DOCK_MARGIN if side == "left" else root.size.x - sz.x - DOCK_MARGIN
		p.position = frame_pos(p, Vector2(x, DOCK_MARGIN), root.size)
	parent.set_meta("_dock_frame", p)
	make_draggable(p, place)
	root.resized.connect(place)
	p.resized.connect(place)
	p.minimum_size_changed.connect(place)
	place.call_deferred()
	var ink := PaperInk.new()
	ink.target = p
	p.add_child(ink)
	return p


## Janela arrastável: segurando o botão esquerdo em qualquer parte vazia do painel (título, papel, moldura)
## ela acompanha o mouse; `relayout` reposiciona (lendo `frame_pos`). Ao soltar, o WindowDock desencavala:
## se ficou por cima de outra janela, encosta ao lado dela.
static func make_draggable(frame: Control, relayout: Callable) -> void:
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				frame.set_meta("_drag", frame.get_global_mouse_position() - frame.global_position)
			elif frame.has_meta("_drag"):
				frame.remove_meta("_drag")
				frame.get_tree().call_group("window_dock", "resolve", frame)
		elif e is InputEventMouseMotion and frame.has_meta("_drag"):
			var parent_pos := (frame.get_parent() as Control).global_position
			frame.set_meta("_user_pos", frame.get_global_mouse_position() - frame.get_meta("_drag") - parent_pos)
			relayout.call())


## Posição da janela: a que o jogador escolheu arrastando (ou o WindowDock, ao desencavalar) ou `default`;
## sempre inteira dentro de `area`.
static func frame_pos(frame: Control, default: Vector2, area: Vector2) -> Vector2:
	var p: Vector2 = frame.get_meta("_user_pos") if frame.has_meta("_user_pos") else default
	return p.clamp(Vector2.ZERO, (area - frame.size).max(Vector2.ZERO)).round()


## Cor clara do tema escuro convertida para tinta sobre o pergaminho: branco/creme vira tinta, cinza vira
## tinta apagada, dourado vira ouro escuro e as cores vivas (raridade, bônus) escurecem (`on_paper`).
static func paper_color(c: Color) -> Color:
	var lum := c.get_luminance()
	if lum < 0.33:
		return c
	if c.s < 0.28:
		return INK if lum > 0.68 else INK_DIM
	if c.h > 0.07 and c.h < 0.16 and c.s > 0.35:
		return INK_GOLD
	return Color(on_paper(c), c.a)
