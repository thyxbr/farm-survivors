class_name BookWindow
extends Control
## Janela lateral com abas (docs/INTERFACE_GRIMORIO.md, "Janelas laterais"): um painel de pergaminho
## encaixado à esquerda ou à direita da tela, com o título e o fechar no cabeçalho e as abas logo abaixo.
## Não escurece o mundo e não bloqueia o mouse fora do painel: outra janela, do outro lado, continua
## clicável (WindowDock). Quem usa só entrega as páginas com `add_page`; página maior que o painel rola.
## (O nome vem do livro aberto que esta janela substituiu.)

signal closed
signal page_shown(index: int)

## Lado da tela: "left" ou "right". Escolher antes de entrar na árvore.
var side := "left"
## Largura da área das páginas (sem a moldura).
var page_width := 560.0
## Altura do conteúdo (sem sobrar papel vazio embaixo); desligado, a janela ocupa a altura toda da tela
## (o inventário, cuja mochila rola).
var fit_height := true

## Quantas vezes uma página pediu mais largura do que a janela tem (os testes conferem que fica em 0).
var overflow_warnings := 0

var _frame: PanelContainer
var _title: Label
var _stack: PanelContainer
var _tabs: HBoxContainer
var _group := ButtonGroup.new()
var _buttons: Array[Button] = []
var _scrolls: Array[ScrollContainer] = []
var _contents: Array[Control] = []
var _titles: Array[String] = []
var _actions: Array[String] = []
var _current := -1
var _relayout_queued := false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UITheme.paper_theme()
	_frame = PanelContainer.new()
	_frame.add_theme_stylebox_override("panel", UITheme.parch_box(6))
	add_child(_frame)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_frame.add_child(v)
	# cabeçalho: título à esquerda, fechar redondo à direita, ornamento de bronze embaixo
	var head := HBoxContainer.new()
	_title = UITheme.ink("", 24, UITheme.INK, true)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	head.add_child(close_button(close))
	v.add_child(head)
	v.add_child(UITheme.ornament())
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 3)
	_tabs.visible = false
	v.add_child(_tabs)
	_stack = PanelContainer.new()
	_stack.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_stack)
	resized.connect(_layout)


## Botão redondo de fechar do cabeçalho das janelas (também usado pelas telas de estação).
static func close_button(cb: Callable) -> Button:
	var b := Button.new()
	b.text = "✕"
	b.tooltip_text = "Fechar (Esc)"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(34, 34)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 15)
	for st in [["normal", "win_close", 0.0], ["hover", "win_close_hover", 0.25], ["pressed", "win_close_hover", 0.4],
			["hover_pressed", "win_close_hover", 0.4]]:
		var s := StyleBoxFlat.new()
		s.bg_color = UITheme.PAGE_EDGE.lightened(st[2])
		s.border_color = UITheme.BRONZE
		s.set_border_width_all(2)
		s.set_corner_radius_all(17)
		var path := UITheme.KIT + str(st[1]) + ".png"
		if ResourceLoader.exists(path):
			var t := StyleBoxTexture.new()
			t.texture = load(path)
			b.add_theme_stylebox_override(st[0], t)
		else:
			b.add_theme_stylebox_override(st[0], s)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, UITheme.ON_LEATHER)
	b.pressed.connect(cb)
	return b


func _ready() -> void:
	_layout()


## Encostada no lado escolhido, a partir do topo: da altura do conteúdo (`fit_height`) ou da tela toda.
func _layout() -> void:
	var w := screen_width() - UITheme.DOCK_MARGIN
	var m := UITheme.DOCK_MARGIN
	var h := size.y - m * 2.0
	if fit_height and _current >= 0 and _current < _contents.size():
		# moldura, cabeçalho e abas (o mínimo do painel, com a rolagem valendo zero) + a página inteira
		h = minf(h, _frame.get_combined_minimum_size().y + _contents[_current].get_combined_minimum_size().y)
	_frame.size = Vector2(w, h)
	_frame.position = Vector2(m if side == "left" else size.x - w - m, m).round()


## Largura que a janela ocupa na tela, com a moldura e a margem até a borda.
func screen_width() -> float:
	var sb := _frame.get_theme_stylebox("panel")
	return page_width + sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT) + UITheme.DOCK_MARGIN


func set_page_width(w: float) -> void:
	page_width = w
	_layout()


## `key` é a letra mostrada na aba; `action` é a ação de entrada que abre a aba ("" = nenhuma);
## `on_paper` dá à página o tema de papel (texto a tinta).
func add_page(title: String, key: String, action: String, page: Control, on_paper := true) -> void:
	var index := _contents.size()
	var scroll := ScrollContainer.new()
	scroll.visible = false
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if on_paper:
		page.theme = UITheme.paper_theme()
	page.minimum_size_changed.connect(_relayout)
	scroll.add_child(page)
	_stack.add_child(scroll)
	_scrolls.append(scroll)
	_contents.append(page)
	_titles.append(title)
	_actions.append(action)
	var b := Button.new()
	b.text = title if key == "" else "%s (%s)" % [title, key]
	b.tooltip_text = "" if key == "" else "Atalho: %s" % key
	b.toggle_mode = true
	b.button_group = _group
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = 32
	b.add_theme_font_override("font", UITheme.serif())
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(show_page.bind(index))
	_tabs.add_child(b)
	_buttons.append(b)
	_tabs.visible = _buttons.size() > 1   # uma página só: o título basta


func show_page(index: int) -> void:
	if index < 0 or index >= _contents.size():
		return
	_current = index
	for i in _scrolls.size():
		_scrolls[i].visible = i == index
	_buttons[index].set_pressed_no_signal(true)
	_title.text = _titles[index]
	_relayout()
	page_shown.emit(index)
	_check_fit(index)


## Refaz o tamanho no fim do quadro (a página muda de tamanho várias vezes enquanto é remontada).
func _relayout() -> void:
	if not _relayout_queued:
		_relayout_queued = true
		(func() -> void:
			_relayout_queued = false
			_layout()).call_deferred()


func current_page() -> int:
	return _current


## Índice da aba ligada à ação de entrada `action` (-1 se nenhuma).
func page_for_action(action: String) -> int:
	return _actions.find(action)


func close() -> void:
	closed.emit()
	queue_free()


## Retângulo global da área das páginas.
func content_rect() -> Rect2:
	return _stack.get_global_rect()


## A página rola na vertical se for comprida; largura a mais vazaria da moldura, então isso vira aviso.
## Mede dois quadros depois, quando a página visível já foi diagramada.
func _check_fit(index: int) -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree() or _current != index:
		return
	var need := _contents[index].get_combined_minimum_size()
	if need.x > page_width + 1.0:
		overflow_warnings += 1
		push_warning("Página \"%s\" não cabe na janela: precisa de %.0f px de largura, cabe %.0f" % [
			_titles[index], need.x, page_width])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()
