class_name PaperInk
extends Node
## Converte uma tela montada para o tema escuro (texto claro, caixas quase pretas) em tinta sobre o
## pergaminho das janelas laterais, sem reescrever a tela: rótulos claros viram tinta (UITheme.paper_color),
## o contorno some e as caixas escuras de seção viram um quadro a tinta. Telas que refazem o conteúdo
## (listas, preços) são reconvertidas: nó novo é tratado quando entra na árvore e uma varredura curta
## pega cores trocadas depois.

const SWEEP := 0.2   # s entre varreduras

## Painel cujo conteúdo é convertido.
var target: Control
var _t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)
	_sweep.call_deferred()


func _on_node_added(n: Node) -> void:
	if n is Control and is_instance_valid(target) and target.is_ancestor_of(n):
		_ink_one.call_deferred(n)


func _process(delta: float) -> void:
	_t += delta
	if _t >= SWEEP:
		_t = 0.0
		_sweep()


func _sweep() -> void:
	if not is_instance_valid(target):
		return
	for n in target.find_children("*", "Control", true, false):
		_ink_one(n)


static func _ink_one(n: Node) -> void:
	if not is_instance_valid(n):
		return
	if n is ItemSlot:
		if not n.paper:
			n.paper = true   # poço de bronze, como os do inventário
			n.queue_redraw()
		return
	if n is Label:
		_ink_color(n, "font_color")
		if n.has_theme_constant_override("outline_size"):
			n.add_theme_constant_override("outline_size", 0)
	elif n is RichTextLabel:
		_ink_color(n, "default_color")
	elif n is ItemList:
		# cor própria de cada linha (receita pronta, semente sem estoque...): a conversão não muda tinta
		for i in n.item_count:
			var c: Color = n.get_item_custom_fg_color(i)
			if c.a > 0.0:
				var out := UITheme.paper_color(c)
				if out != c:
					n.set_item_custom_fg_color(i, out)
	elif n is Button:
		if n.has_meta("_primary"):
			return   # botão vermelho da ação principal: texto claro de propósito
		for k in ["font_color", "font_hover_color", "font_disabled_color"]:
			_ink_color(n, k)
		# ligado é couro escuro: texto claro, qualquer que fosse a cor escolhida pela tela
		for k in ["font_pressed_color", "font_hover_pressed_color"]:
			if n.has_theme_color_override(k) and n.get_theme_color(k) != UITheme.ON_LEATHER:
				n.add_theme_color_override(k, UITheme.ON_LEATHER)
		# botão que é uma linha de lista (sem texto, com ícone e rótulos dentro): ligado vira um realce claro,
		# porque os rótulos de dentro são tinta e sumiriam na tinta cheia do botão ligado do tema de papel
		if n.text == "" and n.get_child_count() > 0 and not n.has_meta("_ink_row"):
			n.set_meta("_ink_row", true)
			for st in ["pressed", "hover_pressed"]:
				var on := _flat(12, 4, UITheme.BRONZE.darkened(0.3))
				on.bg_color = Color(UITheme.BRONZE, 0.28 if st == "pressed" else 0.34)
				on.set_border_width_all(2)
				n.add_theme_stylebox_override(st, on)
	elif n is PanelContainer or n is Panel:
		var key := "panel"
		if n.has_theme_stylebox_override(key):
			var sb: StyleBox = n.get_theme_stylebox(key)
			if not n.has_meta("_ink_box") or n.get_meta("_ink_box") != sb:
				var out := _ink_box(sb)
				n.add_theme_stylebox_override(key, out)
				n.set_meta("_ink_box", out)


## Troca a cor `key` pela versão a tinta; a marca evita converter de novo a cor já convertida.
static func _ink_color(c: Control, key: String) -> void:
	if not c.has_theme_color_override(key):
		return
	var cur := c.get_theme_color(key)
	if c.has_meta("_ink_" + key) and c.get_meta("_ink_" + key) == cur:
		return
	var out := UITheme.paper_color(cur)
	c.add_theme_color_override(key, out)
	c.set_meta("_ink_" + key, out)


## Caixa escura (StyleBoxFlat escuro ou textura do kit de madeira) vira um quadro a tinta; caixa clara fica.
static func _ink_box(sb: StyleBox) -> StyleBox:
	var mx := sb.content_margin_left if sb.content_margin_left >= 0 else 12.0
	var my := sb.content_margin_top if sb.content_margin_top >= 0 else 10.0
	if sb is StyleBoxTexture:
		return _framed(mx, my, Color(UITheme.INK, 0.35))
	if sb is StyleBoxFlat:
		var f := sb as StyleBoxFlat
		if f.bg_color.get_luminance() < 0.3 and f.bg_color.a > 0.2:
			var border := Color(UITheme.INK, 0.35)
			if f.border_color.s > 0.35 and f.border_color.get_luminance() > 0.3:
				border = UITheme.on_paper(f.border_color)   # borda colorida (raridade, elemento) continua
			if f.border_color.s > 0.35 and f.border_color.get_luminance() > 0.3:
				var flat := _flat(mx, my, border)   # borda colorida fica: quadro a tinta na cor dela
				flat.set_border_width_all(maxi(1, f.border_width_left))
				return flat
			return _framed(mx, my, border)
	return sb


## Quadro rebaixado do kit (sem a textura, um quadro a tinta na cor `border`).
static func _framed(mx: float, my: float, border: Color) -> StyleBox:
	var tex := UITheme.win_inset(int(mx), _flat(mx, my, border))
	if tex is StyleBoxTexture:
		tex.content_margin_top = my
		tex.content_margin_bottom = my
	return tex


static func _flat(mx: float, my: float, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(UITheme.INK, 0.05)
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.content_margin_left = mx
	s.content_margin_right = mx
	s.content_margin_top = my
	s.content_margin_bottom = my
	return s
