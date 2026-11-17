class_name CraftingUI
extends Control
## Bancada de craft de uma estação (forja do Doran, couraria, alquimia da Pip): receitas da profissão em ordem
## de nível, o que falta, o ouro, a chance de sair fina/obra-prima e os botões de fabricar. Receitas que pedem
## nível maior ou pergaminho aparecem apagadas, com o motivo. O servidor decide (Game.craft -> Econ "craft").

signal closed

## "forge", "leather" ou "alchemy" (data/balance/professions.json "stations").
var station := "forge"
var list: ItemList
var prof_l: Label
var prof_bar: ProgressBar
var title_l: Label
var info_l: Label
var ing_l: Label
var craft_btn: Button
var max_btn: Button
var _order: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var st: Dictionary = Balance.tables.get_table("professions").get("stations", {}).get(station, {})
	var prof := str(st.get("prof", ""))
	var p := UITheme.centered_panel(self, 0.45)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(UITheme.label(str(st.get("name", station)), 28, UITheme.GOLD))
	prof_l = UITheme.label("", 17, UITheme.DIM)
	v.add_child(prof_l)
	prof_bar = UITheme.bar(UITheme.XP, 400, 6)
	v.add_child(prof_bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	v.add_child(h)
	list = ItemList.new()
	list.custom_minimum_size = Vector2(420, 420)
	list.item_selected.connect(func(_i: int) -> void: _update_info())
	list.item_activated.connect(func(_i: int) -> void: _craft(1))
	h.add_child(list)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(460, 0)
	right.add_theme_constant_override("separation", 8)
	h.add_child(right)
	title_l = UITheme.label("", 24, UITheme.GOLD)
	right.add_child(title_l)
	info_l = UITheme.label("", 16, UITheme.DIM)
	info_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_l.custom_minimum_size = Vector2(440, 0)
	right.add_child(info_l)
	right.add_child(HSeparator.new())
	ing_l = UITheme.label("", 17)
	ing_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ing_l.custom_minimum_size = Vector2(440, 0)
	right.add_child(ing_l)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	craft_btn = UITheme.button("Fabricar", func() -> void: _craft(1), 200)
	max_btn = UITheme.button("Fabricar tudo", func() -> void: _craft(CharRules.MAX_COUNT), 220)
	btns.add_child(craft_btn)
	btns.add_child(max_btn)
	btns.add_child(UITheme.button("Sair", _close, 120))
	v.add_child(btns)
	_order = CraftRules.station_recipes(Balance.tables, station)
	_order.sort_custom(func(a: String, b: String) -> bool:
		return int(CraftRules.recipe(Balance.tables, a).get("level", 1)) < int(CraftRules.recipe(Balance.tables, b).get("level", 1)))
	Game.inventory_changed.connect(_refresh)
	Game.stats_changed.connect(_refresh)
	Econ.done.connect(_on_econ_done)
	_refresh()
	var pick := 0
	var s := Game.char_state()
	for i in _order.size():
		if int(CraftRules.can_craft(s, Balance.tables, _order[i]).n) > 0:
			pick = i
			break
	if not _order.is_empty():
		list.select(pick)
	list.grab_focus.call_deferred()
	_update_info()


func _prof() -> String:
	return str(Balance.tables.get_table("professions").get("stations", {}).get(station, {}).get("prof", ""))


func _selected() -> String:
	var sel := list.get_selected_items()
	return _order[sel[0]] if not sel.is_empty() and sel[0] < _order.size() else ""


func _refresh() -> void:
	var prof := _prof()
	var lv := Game.prof_level(prof)
	var need := CraftRules.xp_to_next(Balance.tables, lv)
	prof_l.text = "%s nível %d%s" % [Game.prof_name(prof), lv, ("  ·  %d / %d XP" % [Game.prof_xp(prof), need]) if need > 0 else "  ·  nível máximo"]
	prof_bar.max_value = maxi(need, 1)
	prof_bar.value = Game.prof_xp(prof) if need > 0 else 1
	var sel := list.get_selected_items()
	list.clear()
	var s := Game.char_state()
	for rid in _order:
		var r := CraftRules.recipe(Balance.tables, rid)
		var it := ItemDB.get_item(str(r.get("out", rid)))
		var c := CraftRules.can_craft(s, Balance.tables, rid)
		var txt := "Nv %d  %s" % [int(r.get("level", 1)), str(it.get("name", rid))]
		if c.err == "desconhecida":
			txt += "  (pergaminho)"
		list.add_item(txt)
		var idx := list.item_count - 1
		list.set_item_tooltip_enabled(idx, false)
		var col: Color = ItemDB.rarity_color(str(r.get("out", rid))) if int(c.n) > 0 else (
			Color(0.55, 0.52, 0.47) if c.err in ["faltam_ingredientes", "ouro"] else Color(0.38, 0.36, 0.33))
		list.set_item_custom_fg_color(idx, col)
	if not sel.is_empty() and sel[0] < list.item_count:
		list.select(sel[0])
	_update_info()


func _update_info() -> void:
	var rid := _selected()
	if rid == "":
		title_l.text = ""
		info_l.text = ""
		ing_l.text = ""
		craft_btn.disabled = true
		max_btn.disabled = true
		return
	var bt := Balance.tables
	var r := CraftRules.recipe(bt, rid)
	var out := str(r.get("out", rid))
	var it := ItemDB.get_item(out)
	title_l.text = "%s%s" % [str(it.get("name", out)), " x%d" % int(r.qty) if int(r.get("qty", 1)) > 1 else ""]
	title_l.add_theme_color_override("font_color", ItemDB.rarity_color(out))
	var s := Game.char_state()
	var c := CraftRules.can_craft(s, bt, rid)
	var lines: Array[String] = []
	lines.append(ItemDB.item_summary(out))
	var lv := Game.prof_level(_prof())
	var rlv := int(r.get("level", 1))
	if lv < rlv:
		lines.append("Pede %s nível %d (você: %d)." % [Game.prof_name(_prof()), rlv, lv])
	if c.err == "desconhecida":
		lines.append("Receita de pergaminho: aprenda usando o Pergaminho: %s." % str(it.get("name", out)))
	if ItemQuality.can_have(it):
		var odds := CraftRules.quality_odds(bt, lv, rlv)
		if odds.x > 0.0:
			lines.append("Chance de sair Fina: %d%%  ·  Obra-prima: %d%%" % [roundi((odds.x - odds.y) * 100.0), roundi(odds.y * 100.0)])
		else:
			lines.append("Suba a profissão acima do nível da receita para ter chance de Fina e Obra-prima.")
	info_l.text = "\n".join(lines)
	var ing_lines: Array[String] = []
	var ing: Dictionary = r.get("ingredients", {})
	for id in ing:
		var have := Game.count_item(id)
		var need := int(ing[id])
		ing_lines.append("%s  %d/%d%s" % [ItemDB.get_item(id).get("name", id), mini(have, need), need,
			"" if have >= need else "   (falta %d)" % (need - have)])
	if int(r.get("gold", 0)) > 0:
		ing_lines.append("Ouro  %d  (você tem %d)" % [int(r.gold), Game.gold])
	ing_lines.append("XP de %s: %d" % [Game.prof_name(_prof()), int(r.get("xp", 0))])
	ing_l.text = "\n".join(ing_lines)
	craft_btn.disabled = int(c.n) <= 0
	max_btn.disabled = int(c.n) <= 1
	max_btn.text = "Fabricar tudo (%d)" % int(c.n) if int(c.n) > 1 else "Fabricar tudo"


func _craft(times: int) -> void:
	var rid := _selected()
	if rid != "":
		Game.craft(rid, times)


## O Econ confirmou: som e aviso com o que saiu (com a qualidade).
func _on_econ_done(op: String, _args: Array, ok: bool, _err: String, events: Array) -> void:
	if op != "craft" or not ok:
		return
	var got: Array[String] = []
	for e in events:
		if e.get("t") == "looted":
			var n := int(e.get("qty", 1))
			got.append("%s%s" % [ItemDB.get_item(str(e.id)).get("name", e.id), " x%d" % n if n > 1 else ""])
	if got.is_empty():
		return
	Sfx.play("anvil" if station == "forge" else "cook", 0.1)
	Game.notify.emit("Fabricou: %s" % ", ".join(got), UITheme.GOLD)
	_refresh()


func _close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_close()
