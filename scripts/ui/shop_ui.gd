extends Control
## Loja da Mira: grade de mercadorias com preço e grade da mochila para vender (metade do valor).
## Clique direito/duplo clique compra ou vende; a dica mostra a comparação com o equipado.

signal closed

const COLS := 7
const SLOT := 62.0

var tooltip: ItemTooltip
var gold_label: Label
var buy_grid: GridContainer
var sell_grid: GridContainer
var info: Label
var filter := "all"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	var p := UITheme.centered_panel(self, 0.55)
	p.custom_minimum_size = Vector2(1180, 700)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var top := HBoxContainer.new()
	var title := VBoxContainer.new()
	title.add_child(UITheme.heading("Barraca da Mira", 30))
	title.add_child(UITheme.label("\"Armas, armaduras e tudo que um herói precisa. Pago metade pelo que você trouxer!\"", 15, UITheme.DIM))
	top.add_child(title)
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
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(_set_filter.bind(f[0]))
		fr.add_child(b)
	lv.add_child(fr)
	buy_grid = _grid(lv)
	# ---- mochila
	var right := _inset()
	h.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	right.add_child(rv)
	rv.add_child(UITheme.section("Sua mochila (vender)"))
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 34
	rv.add_child(spacer)
	sell_grid = _grid(rv)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	info = UITheme.label("Passe o mouse para ver detalhes · clique direito ou duplo clique para comprar/vender", 15, UITheme.DIM)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(info)
	foot.add_child(UITheme.keycap("E", 13))
	foot.add_child(UITheme.button("Sair", _close, 140))
	v.add_child(foot)

	tooltip = ItemTooltip.new()
	add_child(tooltip)
	Game.inventory_changed.connect(_refresh)
	Game.stats_changed.connect(_refresh)
	Econ.result.connect(_on_econ_result)
	_refresh()


func _inset() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.inset_box(14))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p


func _grid(parent: Control) -> GridContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(COLS * (SLOT + 6), 470)
	parent.add_child(scroll)
	var g := GridContainer.new()
	g.columns = COLS
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	scroll.add_child(g)
	return g


func _set_filter(f: String) -> void:
	filter = f
	_refresh()


func _matches(id: String) -> bool:
	match filter:
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
	for c in sell_grid.get_children():
		c.queue_free()
	for id in ItemDB.SHOP_STOCK:
		if not _matches(id):
			continue
		var s := _slot("buy", id, 0)
		var price: int = ItemDB.get_item(id).price
		s.info_text = "%d◆" % price
		s.dim = price > Game.gold
		buy_grid.add_child(s)
	var n := 0
	for slot in Game.inventory:
		var s := _slot("sell", slot.id, slot.qty)
		sell_grid.add_child(s)
		n += 1
	while n < COLS * 7:   # espaços vazios completam a grade
		var e := ItemSlot.new(SLOT)
		e.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sell_grid.add_child(e)
		n += 1


func _slot(ctx: String, id: String, q: int) -> ItemSlot:
	var s := ItemSlot.new(SLOT)
	s.set_state(id, q)
	s.context = ctx
	s.tooltip = tooltip
	var act := _buy if ctx == "buy" else _sell
	s.right_clicked.connect(act)
	s.double_clicked.connect(act)
	return s


func _buy(s: ItemSlot) -> void:
	Game.buy(s.item_id)


func _sell(s: ItemSlot) -> void:
	Game.sell(s.item_id)


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
