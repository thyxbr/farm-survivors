class_name CraftingUI
extends Control
## Bancada de craft de uma estação (forja do Doran, couraria, alquimia da Pip). À esquerda as receitas da
## profissão em ordem de nível, cada uma com o ícone do que faz; à direita o item grande com os atributos, as
## chances (sucesso, Fina, Obra-prima, bônus sorteado), os materiais com ícone e tenho/preciso, o ouro e a XP.
## Receitas que pedem nível maior ou pergaminho aparecem apagadas, com o motivo. O servidor decide
## (Game.craft -> Econ "craft"); enquanto ele responde roda a CraftAnim, que mostra o sucesso ou a falha.

signal closed

## Janela lateral da esquerda (WindowDock), com o inventário aberto ao lado.
var dock_side := "left"
var wants_inventory := true

const ROW_H := 58.0
const C_LOCK := Color(0.45, 0.42, 0.38)
const C_MISSING := Color(0.62, 0.58, 0.52)

## "forge", "leather" ou "alchemy" (data/balance/professions.json "stations").
var station := "forge"
var tooltip: ItemTooltip
var anim: CraftAnim
var prof_l: Label
var prof_bar: ProgressBar
var rows_box: VBoxContainer
var scroll: ScrollContainer
var only_ready: CheckBox
var out_slot: ItemSlot
var title_l: Label
var sub_l: Label
var stats_l: Label
var odds_box: HBoxContainer
var bonus_l: Label
var mats: GridContainer
var cost_l: Label
var note_l: Label
var craft_btn: Button
var max_btn: Button
var _order: Array = []
var _rows := {}      # receita -> {"btn", "name", "tag", "slot"}
var _sel := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var st: Dictionary = Balance.tables.get_table("professions").get("stations", {}).get(station, {})
	var p := UITheme.dock_panel(self)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	# ---- cabeçalho: estação e profissão
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 24)
	v.add_child(head)
	var name_l := UITheme.heading(str(st.get("name", station)), 30)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_l)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 4)
	pv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(pv)
	prof_l = UITheme.label("", 16, UITheme.DIM)
	prof_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pv.add_child(prof_l)
	prof_bar = UITheme.bar(UITheme.XP, 300, 8)
	pv.add_child(prof_bar)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	v.add_child(h)
	# ---- receitas
	var left := _inset()
	h.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	left.add_child(lv)
	var lh := HBoxContainer.new()
	var sec := UITheme.section("Receitas")
	sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lh.add_child(sec)
	only_ready = CheckBox.new()
	only_ready.text = "Só as que posso fazer"
	only_ready.focus_mode = Control.FOCUS_NONE
	only_ready.add_theme_font_size_override("font_size", 14)
	only_ready.toggled.connect(func(_on: bool) -> void: _refresh())
	lh.add_child(only_ready)
	lv.add_child(lh)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(400, 420)
	lv.add_child(scroll)
	rows_box = VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", 4)
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows_box)
	# ---- detalhe
	var right := _inset()
	h.add_child(right)
	var rv := VBoxContainer.new()
	rv.custom_minimum_size = Vector2(520, 0)
	rv.add_theme_constant_override("separation", 10)
	right.add_child(rv)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	rv.add_child(top)
	tooltip = ItemTooltip.new()
	tooltip.paper = true
	out_slot = ItemSlot.new(132)
	out_slot.model_icon = true
	out_slot.tooltip = tooltip
	out_slot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(out_slot)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 3)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tv)
	title_l = UITheme.heading("", 24)
	title_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(title_l)
	sub_l = UITheme.label("", 15, UITheme.DIM)
	tv.add_child(sub_l)
	stats_l = UITheme.label("", 16, Color(0.72, 0.85, 1.0))
	stats_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(stats_l)
	odds_box = HBoxContainer.new()
	odds_box.add_theme_constant_override("separation", 8)
	rv.add_child(odds_box)
	bonus_l = UITheme.label("", 14, UITheme.DIM)
	bonus_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bonus_l.custom_minimum_size.x = 500
	rv.add_child(bonus_l)
	rv.add_child(UITheme.section("Materiais", 18))
	mats = GridContainer.new()
	mats.columns = 2
	mats.add_theme_constant_override("h_separation", 14)
	mats.add_theme_constant_override("v_separation", 8)
	rv.add_child(mats)
	rv.add_child(UITheme.spacer())
	cost_l = UITheme.label("", 16)
	rv.add_child(cost_l)
	note_l = UITheme.label("", 15, UITheme.BAD)
	note_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_l.custom_minimum_size.x = 500
	rv.add_child(note_l)
	# ---- rodapé
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	var hint := UITheme.label("↑ ↓ escolhe · Enter fabrica", 14, UITheme.DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(hint)
	craft_btn = UITheme.primary(UITheme.button("Fabricar", func() -> void: _craft(1), 200))
	max_btn = UITheme.button("Fabricar tudo", func() -> void: _craft(CharRules.MAX_COUNT), 220)
	foot.add_child(craft_btn)
	foot.add_child(max_btn)
	foot.add_child(UITheme.button("Sair", _close, 120))
	v.add_child(foot)
	add_child(tooltip)
	anim = CraftAnim.new()
	add_child(anim)
	anim.finished.connect(_refresh)

	_order = CraftRules.station_recipes(Balance.tables, station)
	_order.sort_custom(func(a: String, b: String) -> bool:
		return int(CraftRules.recipe(Balance.tables, a).get("level", 1)) < int(CraftRules.recipe(Balance.tables, b).get("level", 1)))
	for rid in _order:
		_add_row(rid)
	Game.inventory_changed.connect(_refresh)
	Game.stats_changed.connect(_refresh)
	Econ.done.connect(_on_econ_done)
	# começa na melhor receita que dá para fazer agora (a de maior nível); sem nenhuma, na primeira
	var s := Game.char_state()
	_sel = _order[0] if not _order.is_empty() else ""
	for rid in _order:
		if int(CraftRules.can_craft(s, Balance.tables, rid).n) > 0:
			_sel = rid
	_refresh()
	_scroll_to_selected.call_deferred()


func _inset() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.kit_inset(14))
	return p


## Quantas receitas a bancada mostra (teste de fumaça).
func recipe_count() -> int:
	return _order.size()


func _prof() -> String:
	return str(Balance.tables.get_table("professions").get("stations", {}).get(station, {}).get("prof", ""))


func _out(rid: String) -> String:
	return str(CraftRules.recipe(Balance.tables, rid).get("out", rid))


# ================================================================ lista de receitas
func _add_row(rid: String) -> void:
	var out := _out(rid)
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, ROW_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(_select.bind(rid))
	b.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.double_click and e.button_index == MOUSE_BUTTON_LEFT:
			_select(rid)
			_craft(1))
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 8
	hb.offset_right = -10
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	var slot := ItemSlot.new(44)
	slot.model_icon = true
	slot.item_id = out
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(slot)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(tv)
	var name_l := UITheme.label(str(ItemDB.get_item(out).get("name", out)), 16)
	name_l.clip_text = true
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(name_l)
	var lvl := UITheme.label("Nível %d" % int(CraftRules.recipe(Balance.tables, rid).get("level", 1)), 13, UITheme.DIM)
	lvl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(lvl)
	var tag := UITheme.label("", 15, UITheme.GOOD)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(tag)
	rows_box.add_child(b)
	_rows[rid] = {"btn": b, "name": name_l, "tag": tag, "slot": slot, "lvl": lvl}


func _select(rid: String) -> void:
	_sel = rid
	_refresh()


func _scroll_to_selected() -> void:
	if _rows.has(_sel):
		scroll.ensure_control_visible(_rows[_sel].btn)


func _visible_order() -> Array:
	return _order.filter(func(rid: String) -> bool: return (_rows[rid].btn as Button).visible)


func _move(step: int) -> void:
	var vis := _visible_order()
	if vis.is_empty():
		return
	var i := vis.find(_sel)
	_sel = vis[clampi(i + step, 0, vis.size() - 1)] if i >= 0 else vis[0]
	_refresh()
	_scroll_to_selected()


func _refresh() -> void:
	var bt := Balance.tables
	var prof := _prof()
	var lv := Game.prof_level(prof)
	var need := CraftRules.xp_to_next(bt, lv)
	prof_l.text = "%s nível %d%s" % [Game.prof_name(prof), lv, ("  ·  %d / %d XP" % [Game.prof_xp(prof), need]) if need > 0 else "  ·  nível máximo"]
	prof_bar.max_value = maxi(need, 1)
	prof_bar.value = Game.prof_xp(prof) if need > 0 else 1
	var s := Game.char_state()
	for rid in _order:
		var row: Dictionary = _rows[rid]
		var c := CraftRules.can_craft(s, bt, rid)
		var can := int(c.n) > 0
		var locked: bool = c.err in ["desconhecida", "nivel"]
		(row.btn as Button).visible = can or not only_ready.button_pressed
		(row.btn as Button).set_pressed_no_signal(rid == _sel)
		(row.name as Label).add_theme_color_override("font_color",
			ItemDB.rarity_color(_out(rid)) if can else (C_LOCK if locked else C_MISSING))
		(row.slot as ItemSlot).dim = not can
		(row.slot as ItemSlot).queue_redraw()
		var tag: Label = row.tag
		tag.text = "x%d" % int(c.n) if can else ("pergaminho" if c.err == "desconhecida" else ("nível" if c.err == "nivel" else ""))
		tag.add_theme_color_override("font_color", UITheme.GOOD if can else C_LOCK)
	if _rows.has(_sel) and not (_rows[_sel].btn as Button).visible:
		var vis := _visible_order()
		_sel = vis[0] if not vis.is_empty() else ""
		for rid in _order:
			(_rows[rid].btn as Button).set_pressed_no_signal(rid == _sel)
	_update_info()


# ================================================================ detalhe da receita
func _update_info() -> void:
	for c in odds_box.get_children() + mats.get_children():
		c.get_parent().remove_child(c)
		c.queue_free()
	if _sel == "":
		out_slot.set_state("")
		title_l.text = "Nenhuma receita"
		for l in [sub_l, stats_l, bonus_l, cost_l, note_l]:
			(l as Label).text = ""
		craft_btn.disabled = true
		max_btn.disabled = true
		return
	var bt := Balance.tables
	var r := CraftRules.recipe(bt, _sel)
	var out := _out(_sel)
	var it := ItemDB.get_item(out)
	var qty := int(r.get("qty", 1))
	out_slot.set_state(out, qty)
	title_l.text = "%s%s" % [str(it.get("name", out)), " x%d" % qty if qty > 1 else ""]
	title_l.add_theme_color_override("font_color", ItemDB.rarity_color(out))
	# "Raro · Espada · Dano 14" e os atributos, um por linha
	var sum := ItemDB.item_summary(out).split("\n")
	var rar := str(ItemDB.RARITY[ItemDB.rarity_of(out)].name)
	sub_l.text = "%s · %s" % [rar, sum[1].replace(" — ", " · ")] if sum.size() > 1 else rar
	var st := ItemDB.item_stats(out)
	var stat_lines: Array[String] = []
	for k in ItemDB.STAT_ORDER:
		if st.has(k):
			stat_lines.append(ItemDB.format_stat(k, float(st[k])))
	if stat_lines.is_empty() and not ItemDB.is_equippable(out):
		stat_lines.append(str(it.get("desc", "")))
	stats_l.text = "\n".join(stat_lines)
	stats_l.visible = stats_l.text != ""
	# chances
	var lv := Game.prof_level(_prof())
	var rlv := int(r.get("level", 1))
	var gear := CraftRules.makes_gear(bt, _sel)
	var fail := CraftRules.fail_chance(bt, _sel, lv)
	odds_box.visible = gear
	bonus_l.visible = gear
	if gear:
		var odds := CraftRules.quality_odds(bt, lv, rlv)
		_chip("Sucesso", 1.0 - fail, UITheme.GOOD if fail < 0.12 else (UITheme.GOLD if fail < 0.3 else UITheme.BAD))
		_chip("Fina", odds.x - odds.y, Color(0.75, 0.9, 1.0))
		_chip("Obra-prima", odds.y, Color(1.0, 0.85, 0.5))
		var notes: Array[String] = []
		if CraftRules.has_affix(bt, _sel):
			notes.append("✦ Sai com um destes bônus, sorteado: %s" % _affix_preview(rlv))
		if fail > 0.0:
			notes.append("Se falhar, o ouro é gasto e metade dos materiais volta.")
		if odds.x <= 0.0:
			notes.append("Passe do nível %d de %s para ter chance de Fina e Obra-prima." % [rlv, Game.prof_name(_prof())])
		bonus_l.text = "\n".join(notes)
		bonus_l.visible = not notes.is_empty()
	# materiais
	var ing: Dictionary = r.get("ingredients", {})
	for id in ing:
		mats.add_child(_material(str(id), Game.count_item(id), int(ing[id])))
	var gold := int(r.get("gold", 0))
	var parts: Array[String] = []
	if gold > 0:
		parts.append("Ouro: %d (você tem %d)" % [gold, Game.gold])
	parts.append("XP de %s: +%d" % [Game.prof_name(_prof()), int(r.get("xp", 0))])
	cost_l.text = "   ·   ".join(parts)
	cost_l.add_theme_color_override("font_color", UITheme.BAD if gold > Game.gold else UITheme.TEXT)
	var c := CraftRules.can_craft(Game.char_state(), bt, _sel)
	note_l.text = {"desconhecida": "Receita de pergaminho: aprenda usando o Pergaminho: %s." % str(it.get("name", out)),
		"nivel": "Pede %s nível %d (você: %d)." % [Game.prof_name(_prof()), rlv, lv],
		"faltam_ingredientes": "Faltam materiais.", "ouro": "Falta ouro."}.get(c.err, "")
	note_l.visible = note_l.text != ""
	craft_btn.disabled = int(c.n) <= 0
	max_btn.disabled = int(c.n) <= 1
	max_btn.text = "Fabricar tudo (%d)" % int(c.n) if int(c.n) > 1 else "Fabricar tudo"


## "+2 Vitalidade, +2 Força, +3% Chance de crítico..." (os valores do nível da receita).
func _affix_preview(recipe_level: int) -> String:
	var parts: Array[String] = []
	var afx: Dictionary = ItemQuality.affixes(Balance.tables.get_table("progression"))
	for a in afx:
		parts.append(ItemDB.format_stat(str(afx[a].get("stat", "")), float(ItemQuality.affix_value(afx[a], recipe_level))))
	return " · ".join(parts)


## Plaquinha "Sucesso 85%".
func _chip(text: String, chance: float, col: Color) -> void:
	var p := PanelContainer.new()
	var sb := UITheme.inset_box(10)
	sb.border_color = Color(col, 0.55 if chance > 0.0 else 0.15)
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -2)
	p.add_child(vb)
	var pct := UITheme.heading("%d%%" % roundi(chance * 100.0), 22, col if chance > 0.0 else C_LOCK)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(pct)
	var l := UITheme.label(text, 13, UITheme.DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(l)
	odds_box.add_child(p)


## Um material: ícone (com dica), nome e tenho/preciso em verde ou vermelho.
func _material(id: String, have: int, need: int) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.custom_minimum_size.x = 245
	var slot := ItemSlot.new(50)
	slot.model_icon = true
	slot.item_id = id
	slot.tooltip = tooltip
	slot.dim = have < need
	hb.add_child(slot)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(vb)
	var n := UITheme.label(str(ItemDB.get_item(id).get("name", id)), 15)
	n.clip_text = true
	n.custom_minimum_size.x = 180
	vb.add_child(n)
	vb.add_child(UITheme.label("%d / %d" % [have, need], 15, UITheme.GOOD if have >= need else UITheme.BAD))
	return hb


# ================================================================ fabricar
func _craft(times: int) -> void:
	if _sel == "" or anim.active() or craft_btn.disabled:
		return
	tooltip.visible = false
	anim.start(_out(_sel), station)   # antes do pedido: no solo a resposta chega na mesma chamada
	Game.craft(_sel, times)


## O Econ respondeu: entrega o desfecho à animação e avisa o que saiu (com qualidade e bônus).
func _on_econ_done(op: String, _args: Array, ok: bool, _err: String, events: Array) -> void:
	if op != "craft":
		return
	if not ok:
		anim.cancel()
		return
	var items: Array = []
	var names: Array[String] = []
	var fails := 0
	var back := {}
	for e in events:
		if e.get("t") == "looted":
			var n := int(e.get("qty", 1))
			items.append([str(e.id), n])
			names.append("%s%s" % [ItemDB.get_item(str(e.id)).get("name", e.id), " x%d" % n if n > 1 else ""])
		elif e.get("t") == "craft_fail":
			fails = int(e.get("n", 0))
			back = e.get("back", {})
	if anim.active():
		anim.resolve(items, fails, back)
	if not names.is_empty():
		Game.notify.emit("Fabricou: %s" % ", ".join(names), UITheme.GOLD)
	if fails > 0:
		Game.notify.emit("A fabricação falhou%s." % (" %d vezes" % fails if fails > 1 else ""), UITheme.BAD)
	_refresh()


func _close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if anim.active():
		if event is InputEventKey and event.pressed and not event.echo:
			get_viewport().set_input_as_handled()
			anim.skip()
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_close()
	elif event.is_action_pressed("ui_down", true):
		get_viewport().set_input_as_handled()
		_move(1)
	elif event.is_action_pressed("ui_up", true):
		get_viewport().set_input_as_handled()
		_move(-1)
	elif event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_craft(1)
