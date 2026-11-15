class_name BookWindow
extends Control
## Janela em forma de livro aberto (docs/INTERFACE_GRIMORIO.md): fundo escurecido, o livro centralizado,
## abas de marcador saindo do topo da página direita e um botão de fechar. Quem usa só entrega as páginas
## com `add_page`; o conteúdo vive dentro das margens de `BookLayout` e, se for maior, rola.

signal closed
signal page_shown(index: int)

## Quantas vezes uma página pediu mais espaço do que o livro tem (os testes conferem que fica em 0).
var overflow_warnings := 0

var _holder: Control
var _stack: PanelContainer
var _tabs: HBoxContainer
var _group := ButtonGroup.new()
var _buttons: Array[Button] = []
var _scrolls: Array[ScrollContainer] = []
var _contents: Array[Control] = []
var _titles: Array[String] = []
var _actions: Array[String] = []
var _current := -1
var _close_tab: Button


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	# tamanho fixo; `_layout` centraliza e encolhe o conjunto quando a janela é menor que o livro
	_holder = Control.new()
	_holder.size = BookLayout.SIZE
	add_child(_holder)
	var book := TextureRect.new()
	book.texture = UITheme.tex("book")
	book.size = BookLayout.SIZE
	book.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.add_child(book)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 4)
	_tabs.position = Vector2(BookLayout.SIZE.x * 0.5 + 36, -16)
	_holder.add_child(_tabs)
	var margin := MarginContainer.new()
	margin.position = Vector2(BookLayout.SIDE, BookLayout.TOP)
	margin.size = BookLayout.content_room()
	_holder.add_child(margin)
	_stack = PanelContainer.new()
	_stack.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	margin.add_child(_stack)
	# fechar: um marcador curto no fim da fila de abas, fora da página (não encosta na vinheta do canto
	# nem em texto nenhum, e não depende do que cada página põe no canto)
	_close_tab = Button.new()
	_close_tab.text = "✕"
	_close_tab.tooltip_text = "Fechar (Esc)"
	_close_tab.custom_minimum_size = Vector2(46, 52)
	_close_tab.add_theme_font_size_override("font_size", 20)
	_close_tab.add_theme_stylebox_override("normal", _tab_box("tab_off", Color(0.9, 0.9, 0.9)))
	_close_tab.add_theme_stylebox_override("hover", _tab_box("tab_off", Color(1.3, 1.2, 1.2)))
	_close_tab.add_theme_stylebox_override("pressed", _tab_box("tab_off", Color(0.75, 0.75, 0.75)))
	_close_tab.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_close_tab.add_theme_color_override("font_color", Color(0.93, 0.84, 0.66))
	_close_tab.add_theme_color_override("font_hover_color", Color(1, 0.96, 0.85))
	_close_tab.add_theme_color_override("font_pressed_color", Color(1, 0.96, 0.85))
	_close_tab.pressed.connect(close)
	_tabs.add_child(_close_tab)
	resized.connect(_layout)


func _ready() -> void:
	_layout()


func _layout() -> void:
	var k := BookLayout.scale_for(size)
	_holder.scale = Vector2(k, k)
	_holder.position = ((size - BookLayout.SIZE * k) * 0.5).round()


## `key` é a letra mostrada na aba; `action` é a ação de entrada que abre a aba ("" = nenhuma);
## `on_paper` dá à página o tema de papel (texto a tinta).
func add_page(title: String, key: String, action: String, page: Control, on_paper := true) -> void:
	var index := _contents.size()
	var scroll := ScrollContainer.new()
	scroll.visible = false
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if on_paper:
		page.theme = UITheme.paper_theme()
	scroll.add_child(page)
	_stack.add_child(scroll)
	_scrolls.append(scroll)
	_contents.append(page)
	_titles.append(title)
	_actions.append(action)
	var b := Button.new()
	b.text = title if key == "" else "%s  %s" % [title, key]
	b.tooltip_text = "" if key == "" else "Atalho: %s" % key
	b.toggle_mode = true
	b.button_group = _group
	b.custom_minimum_size = Vector2(178, 52)
	b.add_theme_font_override("font", UITheme.serif())
	b.add_theme_font_size_override("font_size", 19)
	var on := _tab_box("tab_on", Color.WHITE)
	b.add_theme_stylebox_override("normal", _tab_box("tab_off", Color(0.9, 0.9, 0.9)))
	b.add_theme_stylebox_override("hover", _tab_box("tab_off", Color(1.25, 1.2, 1.2)))
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color(0.93, 0.84, 0.66))
	b.add_theme_color_override("font_hover_color", Color(1, 0.94, 0.78))
	b.add_theme_color_override("font_pressed_color", UITheme.INK)
	b.add_theme_color_override("font_hover_pressed_color", UITheme.INK)
	b.pressed.connect(show_page.bind(index))
	_tabs.add_child(b)
	_tabs.move_child(_close_tab, -1)   # o fechar fica sempre depois da última aba
	_buttons.append(b)


## Marcador de aba; as pontas arredondadas não esticam, então serve também para o marcador curto do fechar.
func _tab_box(tex_name: String, tint: Color) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = UITheme.tex(tex_name)
	sb.texture_margin_left = 18
	sb.texture_margin_right = 18
	sb.modulate_color = tint
	return sb


func show_page(index: int) -> void:
	if index < 0 or index >= _contents.size():
		return
	_current = index
	for i in _scrolls.size():
		_scrolls[i].visible = i == index
	_buttons[index].set_pressed_no_signal(true)
	page_shown.emit(index)
	_check_fit(index)


func current_page() -> int:
	return _current


func close() -> void:
	closed.emit()
	queue_free()


## Retângulo global da área das páginas, já com a escala do livro.
func content_rect() -> Rect2:
	var k := _holder.scale.x
	return Rect2(_holder.global_position + Vector2(BookLayout.SIDE, BookLayout.TOP) * k, BookLayout.content_room() * k)


## A página rola se for grande demais, então nada sai do livro; o aviso existe para a tela ser consertada.
## Mede dois quadros depois, quando a página visível já foi diagramada.
func _check_fit(index: int) -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree() or _current != index:
		return
	var need := _contents[index].get_combined_minimum_size()
	if not BookLayout.fits(need):
		overflow_warnings += 1
		push_warning("Página \"%s\" não cabe no livro: precisa de %s, cabe %s" % [_titles[index], need,
			BookLayout.content_room()])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()
		return
	for i in _actions.size():
		if _actions[i] != "" and event.is_action_pressed(_actions[i]):
			get_viewport().set_input_as_handled()
			if i == _current:
				close()
			else:
				show_page(i)
			return
