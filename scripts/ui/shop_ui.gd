extends Control
## Loja da Mira: comprar do estoque e vender itens da mochila (metade do valor).

signal closed

var buy_list: ItemList
var sell_list: ItemList
var info: Label
var gold_label: Label
var _sell_ids: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := UITheme.centered_panel(self, 0.5)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	var top := HBoxContainer.new()
	top.add_child(UITheme.label("Barraca da Mira", 28, UITheme.GOLD))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	gold_label = UITheme.label("", 22, Color(1, 0.85, 0.35))
	top.add_child(gold_label)
	v.add_child(top)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	v.add_child(h)
	buy_list = _column(h, "Comprar")
	sell_list = _column(h, "Vender")
	buy_list.item_activated.connect(func(_i: int) -> void: _buy())
	sell_list.item_activated.connect(func(_i: int) -> void: _sell())
	buy_list.item_selected.connect(func(i: int) -> void: info.text = ItemDB.item_summary(ItemDB.SHOP_STOCK[i]))
	sell_list.item_selected.connect(func(i: int) -> void: info.text = ItemDB.item_summary(_sell_ids[i]))
	info = UITheme.label("Duplo clique para comprar ou vender.", 16)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(820, 110)
	v.add_child(info)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	btns.add_child(UITheme.button("Comprar", _buy, 160))
	btns.add_child(UITheme.button("Vender", _sell, 160))
	btns.add_child(UITheme.button("Sair", _close, 160))
	v.add_child(btns)
	Game.inventory_changed.connect(_refresh)
	Game.stats_changed.connect(_refresh)
	_refresh()


func _column(parent: Control, title: String) -> ItemList:
	var c := VBoxContainer.new()
	parent.add_child(c)
	c.add_child(UITheme.label(title, 20, UITheme.GOLD))
	var l := ItemList.new()
	l.custom_minimum_size = Vector2(400, 320)
	c.add_child(l)
	return l


func _refresh() -> void:
	gold_label.text = "◆ %d ouro" % Game.gold
	var bsel := buy_list.get_selected_items()
	buy_list.clear()
	for id in ItemDB.SHOP_STOCK:
		var it := ItemDB.get_item(id)
		buy_list.add_item("%s — %d ouro" % [it.name, it.price])
		if it.price > Game.gold:
			buy_list.set_item_custom_fg_color(buy_list.item_count - 1, Color(0.6, 0.45, 0.45))
	if bsel.size() > 0:
		buy_list.select(bsel[0])
	var ssel := sell_list.get_selected_items()
	sell_list.clear()
	_sell_ids.clear()
	for slot in Game.inventory:
		var it := ItemDB.get_item(slot.id)
		var txt := "%s%s — %d ouro" % [it.name, ("  x%d" % slot.qty) if slot.qty > 1 else "", int(ceil(it.price * 0.5))]
		sell_list.add_item(txt)
		_sell_ids.append(slot.id)
	if ssel.size() > 0 and ssel[0] < sell_list.item_count:
		sell_list.select(ssel[0])


func _buy() -> void:
	var sel := buy_list.get_selected_items()
	if sel.is_empty():
		return
	if Game.buy(ItemDB.SHOP_STOCK[sel[0]]):
		Sfx.play("coin")


func _sell() -> void:
	var sel := sell_list.get_selected_items()
	if sel.is_empty() or sel[0] >= _sell_ids.size():
		return
	if Game.sell(_sell_ids[sel[0]]):
		Sfx.play("coin")


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_close()
