extends Control
## Loja de um vendedor da vila: janela da esquerda com a grade de mercadorias e o preço; a mochila é o inventário, aberto
## à direita junto com a loja (WindowDock), e lá o clique direito vende (metade do valor, `trade_item`).
## Clique direito/duplo clique compra; a dica mostra a comparação com o equipado (Shift: o equipado ao lado).
## Cada vendedor vende um tipo de coisa (`stall`, ver STALLS): a Mira as armas, a Tereza couro e tecido, o Seu
## Bento sementes e ferramentas, a Dona Cida provisões e a Pip poções. Todos compram qualquer item da mochila.
## O estoque é um só (shop.json); a barraca só escolhe o que mostra. "" = tudo, com os filtros.
## Quantidade (embaixo da grade): itens que empilham (poções, comida, sementes...) saem no lote escolhido, limitado
## ao ouro que o herói tem; equipamento sai sempre um por vez.

signal closed

## Janela lateral da esquerda (WindowDock), com o inventário aberto ao lado.
var dock_side := "left"
var wants_inventory := true

const COLS := 7
const SLOT := 62.0
## Lotes rápidos da linha de quantidade; o campo aceita até MAX_QTY.
const QTY_PRESETS := [1, 10, 50, 100]
const MAX_QTY := 999

var tooltip: ItemTooltip
var gold_label: Label
var buy_grid: GridContainer
var info: Label
var qty_spin: SpinBox
var _qty_buttons: Array[Button] = []
var filter := "all"
var title := "Mercadorias de Valdoria"
var quote := "\"Tudo que um herói precisa. Pago metade pelo que você trouxer!\""
## Barraca aberta (chave de STALLS); "" mostra o estoque inteiro com os botões de filtro.
var stall := ""

## Barracas: [título, fala, filtro do que vendem].
const STALLS := {
	"arms": ["Empório da Mira", "\"Lâminas, cajados, arcos e escudos. Pago metade pelo que você trouxer!\"", "arms"],
	"cloth": ["Couro & Tecido da Tereza", "\"Cada ponto costurado à mão. Gibão novo, herói novo!\"", "armor"],
	"farm": ["Sementes & Ferramentas do Seu Bento", "\"Planta hoje, colhe amanhã. Picareta boa não escolhe pedra.\"", "farm"],
	"goods": ["Provisões da Dona Cida", "\"Poção, pão e o que mais faltar no alforje, meu bem.\"", "goods"],
	"potions": ["Botica da Pip", "\"Poções. Não agite. Não cheire. Beba de uma vez.\"", "use"],
}


func _ready() -> void:
	if STALLS.has(stall):
		title = STALLS[stall][0]
		quote = STALLS[stall][1]
		filter = STALLS[stall][2]
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	var p := UITheme.dock_panel(self)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var top := HBoxContainer.new()
	var title_box := VBoxContainer.new()
	title_box.add_child(UITheme.heading(title, 30))
	# a fala quebra linha: quem dá a largura da janela é a grade, sem sobrar papel dos lados
	var q := UITheme.label(quote, 15, UITheme.DIM)
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.custom_minimum_size.x = 260
	title_box.add_child(q)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title_box)
	top.add_child(UITheme.spacer())
	gold_label = UITheme.heading("", 24, Color(1, 0.84, 0.35))
	gold_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(gold_label)
	v.add_child(top)
	v.add_child(HSeparator.new())

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(h)
	# ---- mercadorias
	var left := _inset()
	h.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	left.add_child(lv)
	lv.add_child(UITheme.section("À venda"))
	var fr := HBoxContainer.new()
	fr.add_theme_constant_override("separation", 6)
	var fg := ButtonGroup.new()
	for f in [["all", "Tudo"], ["weapon", "Armas"], ["armor", "Armaduras"], ["acc", "Acessórios"], ["use", "Consumíveis"]]:
		var b := Button.new()
		b.text = f[1]
		b.toggle_mode = true
		b.button_group = fg
		b.button_pressed = f[0] == filter
		b.custom_minimum_size.y = 34
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL   # os filtros ocupam a linha toda
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(_set_filter.bind(f[0]))
		fr.add_child(b)
	if stall == "":   # numa barraca o filtro é o da barraca, sem botões
		lv.add_child(fr)
	else:
		fr.free()
	buy_grid = _grid(lv)
	lv.add_child(_qty_row())

	info = UITheme.label("Clique direito: comprar (poções e outros empilháveis na quantidade escolhida) · na mochila: vender · Shift: comparar", 14, UITheme.DIM)
	v.add_child(UITheme.footer(info, [UITheme.button("Sair", _close)]))

	tooltip = ItemTooltip.new()
	tooltip.paper = true
	add_child(tooltip)
	Game.inventory_changed.connect(_refresh)
	Game.stats_changed.connect(_refresh)
	Econ.result.connect(_on_econ_result)
	_refresh()


## Linha "Quantidade": botões de lote rápido + campo livre.
func _qty_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UITheme.label("Quantidade", 15, UITheme.DIM))
	var g := ButtonGroup.new()
	for n: int in QTY_PRESETS:
		var b := Button.new()
		b.text = "×%d" % n
		b.toggle_mode = true
		b.button_group = g
		b.button_pressed = n == 1
		b.custom_minimum_size = Vector2(52, 32)
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(func() -> void: qty_spin.value = n)
		row.add_child(b)
		_qty_buttons.append(b)
	qty_spin = SpinBox.new()
	qty_spin.min_value = 1
	qty_spin.max_value = MAX_QTY
	qty_spin.value = 1
	qty_spin.rounded = true
	qty_spin.custom_minimum_size.x = 96
	qty_spin.size_flags_horizontal = Control.SIZE_SHRINK_END
	qty_spin.value_changed.connect(_on_qty_changed)
	row.add_child(UITheme.spacer())
	row.add_child(qty_spin)
	return row


func _on_qty_changed(v: float) -> void:
	for i in _qty_buttons.size():
		_qty_buttons[i].set_pressed_no_signal(int(v) == QTY_PRESETS[i])


func _inset() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.kit_inset(14))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p


func _grid(parent: Control) -> GridContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(COLS * (SLOT + 6), 4 * (SLOT + 6) + 4)
	parent.add_child(scroll)
	var g := GridContainer.new()
	g.columns = COLS
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	scroll.add_child(g)
	# quantas colunas couberem na largura da janela (o título pode alargá-la): a grade vai de borda a borda
	scroll.resized.connect(func() -> void:
		var bar := 14.0 if scroll.get_v_scroll_bar().visible else 0.0
		g.columns = maxi(COLS, int((scroll.size.x - bar + 6.0) / (SLOT + 6.0))))
	return g


func _set_filter(f: String) -> void:
	filter = f
	_refresh()


func _matches(id: String) -> bool:
	var t: String = ItemDB.get_item(id).get("type", "")
	match filter:
		"arms":
			return t == "weapon" or ItemDB.slot_of(id) == "offhand"
		"farm":
			return t in ["seed", "tool"]
		"goods":
			return t in ["consumable", "food", "material"]
		"weapon":
			return ItemDB.slot_of(id) in ["weapon", "offhand"]
		"armor":
			return ItemDB.slot_of(id) in ["armor", "head", "hands", "feet"]
		"acc":
			return ItemDB.slot_of(id) in ["amulet", "ring"]
		"use":
			return ItemDB.category(id) == "use"
	return true


func _refresh() -> void:
	if not is_inside_tree():
		return
	gold_label.text = "◆ %d ouro" % Game.gold
	tooltip.visible = false
	for c in buy_grid.get_children():
		c.queue_free()
	for id in ItemDB.SHOP_STOCK:
		if not _matches(id):
			continue
		var s := _slot("buy", id, 0)
		var price: int = ItemDB.get_item(id).price
		s.info_text = "%d◆" % price
		# arma de outra classe continua à venda (dá para revender), mas apagada: a dica diz de quem ela é
		# acima do nível do herói: apagada e com o nível no lugar do preço (a dica mostra os dois)
		var need := CharRules.item_level(Balance.tables, id)
		var locked := need > Game.level
		if locked:
			s.info_text = "Nv %d" % need
		var it := ItemDB.get_item(id)
		if str(it.get("type", "")) == "seed" and ItemDB.CROPS.has(str(it.get("crop", ""))):
			var farm_need := int(ItemDB.CROPS[it.crop].get("level", 1))
			if Game.prof_level("farming") < farm_need:
				locked = true
				s.info_text = "Faz %d" % farm_need
		s.dim = price > Game.gold or not Game.can_wield(id) or locked
		buy_grid.add_child(s)


func _slot(ctx: String, id: String, q: int) -> ItemSlot:
	var s := ItemSlot.new(SLOT)
	s.model_icon = true
	s.set_state(id, q)
	s.context = ctx
	s.tooltip = tooltip
	var act := _buy if ctx == "buy" else _sell
	s.right_clicked.connect(act)
	s.double_clicked.connect(act)
	return s


func _buy(s: ItemSlot) -> void:
	var id := s.item_id
	var qty := 1
	if ItemDB.is_stackable(id) and qty_spin != null:
		var price: int = int(ItemDB.get_item(id).get("price", 0))
		qty = int(qty_spin.value)
		if price > 0:
			qty = mini(qty, floori(float(Game.gold) / price))   # lote maior que o ouro: compra o que der
		if qty < 1:
			qty = 1   # deixa o servidor responder "Ouro insuficiente"
	# o servidor aceita até CharRules.MAX_COUNT por pedido: lote grande vai em partes
	while qty > 0:
		var part := mini(qty, CharRules.MAX_COUNT)
		Game.buy(id, part)
		qty -= part


func _sell(s: ItemSlot) -> void:
	Game.sell(s.item_id)


## Item vendido pelo inventário aberto ao lado (clique direito na mochila).
func trade_item(id: String) -> void:
	Game.sell(id)


func _on_econ_result(op: String, ok: bool, _err: String) -> void:
	if ok and op in ["buy", "sell"]:
		Sfx.play("coin")


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_close()
