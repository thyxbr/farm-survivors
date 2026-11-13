extends Control
## Menu do Caldeirão: receitas com ingredientes, efeitos e botões de cozinhar.

signal closed

var kitchen: Node = null
var list: ItemList
var title_l: Label
var ing_l: Label
var eff_l: Label
var pantry_l: Label
var cook_btn: Button
var max_btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := UITheme.centered_panel(self, 0.45)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	v.add_child(UITheme.label("Caldeirão da Horta", 28, UITheme.GOLD))
	v.add_child(UITheme.label("Comidas dão bônus temporários. Coma com [Q] (troque com [T]) — inclusive no meio da Horda!", 16, UITheme.DIM))

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	v.add_child(h)
	list = ItemList.new()
	list.custom_minimum_size = Vector2(400, 360)
	list.item_selected.connect(func(_i: int) -> void: _update_info())
	list.item_activated.connect(func(_i: int) -> void: _cook(1))
	h.add_child(list)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(440, 0)
	right.add_theme_constant_override("separation", 10)
	h.add_child(right)
	title_l = UITheme.label("", 24, UITheme.GOLD)
	right.add_child(title_l)
	ing_l = UITheme.label("", 18)
	right.add_child(ing_l)
	right.add_child(HSeparator.new())
	eff_l = UITheme.label("", 16)
	eff_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	eff_l.custom_minimum_size = Vector2(420, 120)
	right.add_child(eff_l)

	pantry_l = UITheme.label("", 15, UITheme.DIM)
	pantry_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pantry_l.custom_minimum_size = Vector2(860, 0)
	v.add_child(pantry_l)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	cook_btn = UITheme.button("Cozinhar", func() -> void: _cook(1), 200)
	max_btn = UITheme.button("Cozinhar tudo", func() -> void: _cook(99), 220)
	btns.add_child(cook_btn)
	btns.add_child(max_btn)
	btns.add_child(UITheme.button("Sair", _close, 120))
	v.add_child(btns)

	Game.inventory_changed.connect(_refresh)
	_refresh()
	var pick := 0
	for i in ItemDB.RECIPE_ORDER.size():
		if Game.can_cook(ItemDB.RECIPE_ORDER[i]) > 0:
			pick = i
			break
	list.select(pick)
	list.grab_focus.call_deferred()
	_update_info()


func _selected() -> String:
	var sel := list.get_selected_items()
	return ItemDB.RECIPE_ORDER[sel[0]] if not sel.is_empty() else ""


func _refresh() -> void:
	var sel := list.get_selected_items()
	list.clear()
	for r in ItemDB.RECIPE_ORDER:
		var it := ItemDB.get_item(r)
		var n := Game.can_cook(r)
		var have := Game.count_item(r)
		var txt: String = it.name
		if have > 0:
			txt += "   (tem %d)" % have
		list.add_item(txt)
		var idx := list.item_count - 1
		list.set_item_tooltip_enabled(idx, false)
		list.set_item_custom_fg_color(idx, it.get("color", UITheme.TEXT) if n > 0 else Color(0.5, 0.48, 0.44))
	if not sel.is_empty():
		list.select(sel[0])
	var pantry: Array[String] = []
	for crop in ItemDB.CROP_ORDER:
		var n := Game.count_item(crop)
		if n > 0:
			pantry.append("%s x%d" % [ItemDB.CROPS[crop].name, n])
	pantry_l.text = "Despensa: " + (", ".join(pantry) if not pantry.is_empty() else "vazia — plante e colha na horta!")
	_update_info()


func _update_info() -> void:
	var r := _selected()
	if r == "":
		return
	var it := ItemDB.get_item(r)
	title_l.text = it.name
	title_l.add_theme_color_override("font_color", it.get("color", UITheme.GOLD))
	var lines: Array[String] = []
	var ing: Dictionary = ItemDB.RECIPES[r]
	for id in ing:
		var have := Game.count_item(id)
		var need: int = ing[id]
		lines.append("%s  %d/%d%s" % [ItemDB.get_item(id).name, min(have, need), need, "" if have >= need else "   (falta %d)" % (need - have)])
	ing_l.text = "\n".join(lines)
	eff_l.text = ItemDB.food_effect_text(r) + "\n" + it.desc
	var n := Game.can_cook(r)
	cook_btn.disabled = n <= 0
	max_btn.disabled = n <= 1
	max_btn.text = "Cozinhar tudo (%d)" % n if n > 1 else "Cozinhar tudo"


func _cook(times: int) -> void:
	var r := _selected()
	if r == "":
		return
	var n := Game.cook(r, times)
	if n <= 0:
		return
	Sfx.play("cook", 0.1)
	var it := ItemDB.get_item(r)
	Game.notify.emit("Cozinhou %s%s!" % [it.name, " x%d" % n if n > 1 else ""], it.get("color", UITheme.GOLD))
	if kitchen and kitchen.has_method("celebrate"):
		kitchen.celebrate(it.get("color", Color(1, 0.6, 0.2)))


func _close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_close()
