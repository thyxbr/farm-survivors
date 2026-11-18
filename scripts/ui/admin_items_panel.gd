extends Control
## Modo admin: lista todos os itens do jogo e põe o escolhido na mochila (Econ.admin_give).
## Abre pelo menu de pausa com o modo admin ligado. Busca por nome ou id, filtro por tipo, quantidade e a
## opção de já vestir a peça (com o modo admin ligado o nível do item não impede de equipar).

signal closed

const TYPE_NAMES := {
	"weapon": "Armas", "armor": "Mantos e armaduras", "gear": "Cabeça, mãos, pés e acessórios",
	"consumable": "Consumíveis", "food": "Comida", "material": "Materiais", "seed": "Sementes", "crop": "Colheita",
}

var _search: LineEdit
var _type: OptionButton
var _qty: SpinBox
var _equip: CheckBox
var _list: VBoxContainer
var _status: Label
var _types: Array = []
var _equip_after := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := UITheme.centered_panel(self, 0.6)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.custom_minimum_size = Vector2(600, 0)
	p.add_child(v)
	var title := UITheme.label("Adicionar item (admin)", 28, UITheme.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	_search = LineEdit.new()
	_search.placeholder_text = "Buscar por nome ou id"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t: String) -> void: _fill())
	row.add_child(_search)
	_type = OptionButton.new()
	_type.add_item("Todos os tipos")
	for id in ItemDB.ITEMS:
		var t := str(ItemDB.ITEMS[id].get("type", ""))
		if t != "" and not (t in _types):
			_types.append(t)
	_types.sort()
	for t in _types:
		_type.add_item(str(TYPE_NAMES.get(t, t.capitalize())))
	_type.item_selected.connect(func(_i: int) -> void: _fill())
	row.add_child(_type)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	v.add_child(row2)
	row2.add_child(UITheme.label("Quantidade", 16, UITheme.DIM))
	_qty = SpinBox.new()
	_qty.min_value = 1
	_qty.max_value = AdminRules.ITEM_QTY
	_qty.value = 1
	row2.add_child(_qty)
	_equip = CheckBox.new()
	_equip.text = "Equipar ao adicionar"
	_equip.button_pressed = true
	row2.add_child(_equip)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)

	_status = UITheme.label("", 15, UITheme.DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_status)
	v.add_child(UITheme.button("Voltar", _close))
	Econ.done.connect(_on_done)
	_fill()
	_search.grab_focus.call_deferred()


## Ids que passam na busca e no filtro, por tipo, nível e nome.
func matching() -> Array:
	var q := _search.text.strip_edges().to_lower()
	var want: String = _types[_type.selected - 1] if _type.selected > 0 else ""
	var out := []
	for id in ItemDB.ITEMS:
		var it: Dictionary = ItemDB.ITEMS[id]
		if want != "" and str(it.get("type", "")) != want:
			continue
		if q != "" and not (q in str(it.get("name", "")).to_lower() or q in str(id).to_lower()):
			continue
		out.append(str(id))
	out.sort_custom(func(a: String, b: String) -> bool:
		var ia: Dictionary = ItemDB.ITEMS[a]
		var ib: Dictionary = ItemDB.ITEMS[b]
		var ka := [str(ia.get("type", "")), int(ia.get("level", 1)), str(ia.get("name", a))]
		var kb := [str(ib.get("type", "")), int(ib.get("level", 1)), str(ib.get("name", b))]
		return ka < kb)
	return out


func _fill() -> void:
	for c in _list.get_children():
		c.queue_free()
	var ids := matching()
	for id: String in ids:
		var it: Dictionary = ItemDB.ITEMS[id]
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s   ·   %s   ·   nv %d   ·   %s" % [it.get("name", id), TYPE_NAMES.get(it.get("type", ""), it.get("type", "")),
				int(it.get("level", 1)), id]
		b.add_theme_color_override("font_color", ItemDB.rarity_color(id))
		b.pressed.connect(_give.bind(id))
		_list.add_child(b)
	_status.text = "%d itens" % ids.size()
	_status.add_theme_color_override("font_color", UITheme.DIM)


func _give(id: String) -> void:
	_equip_after = id if _equip.button_pressed and ItemDB.slot_of(id) != "" else ""
	Econ.admin_give(id, int(_qty.value))


func _on_done(op: String, args: Array, ok: bool, _err: String, _events: Array) -> void:
	if op != "admin_give" or args.is_empty():
		return
	var id := str(args[0])
	if not ok:
		_status.text = "Não adicionou %s (o modo admin está ligado?)." % id
		_status.add_theme_color_override("font_color", UITheme.BAD)
		return
	_status.text = "Adicionado: %s" % ItemDB.get_item(id).get("name", id)
	_status.add_theme_color_override("font_color", UITheme.GOOD)
	if _equip_after == id:
		_equip_after = ""
		Game.equip(id)


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_close()
