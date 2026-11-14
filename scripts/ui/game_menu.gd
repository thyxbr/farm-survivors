extends Control
## Menu do herói, num livro aberto (BookWindow): Inventário (herói com o equipamento + mochila em grade),
## Personagem (atributos, estatísticas, magias) e Missões (lista + detalhes).
## Referências: boneco e grade de Diablo/Path of Exile, dicas com comparação calculada,
## filtros por categoria, atalhos visíveis nas abas.

signal closed

const TAB_KEYS := ["I", "C", "J"]
const TAB_NAMES := ["Inventário", "Personagem", "Missões"]
const TAB_ACTIONS := ["inventory", "character", "quest_log"]
const BAG_COLS := 8
const BAG_MIN := 56
const SLOT := 62.0

var start_tab := 0
var tooltip: ItemTooltip
var pages: Array[Control] = []
var book: BookWindow
var gold_label: Label

# inventário
var equip_slots := {}
var bag_grid: GridContainer
var bag_slots: Array[ItemSlot] = []
var bag_filter := "all"
var sel_index := -1
var sel_label: Label
var use_btn: Button
var drop_btn: Button
var stats_box: HBoxContainer
var hero_label: Label
var class_label: Label
var bag_count: Label

# personagem e missões
var char_page: HBoxContainer
var quest_page: HBoxContainer
var quest_sel := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	book = BookWindow.new()
	add_child(book)
	var builders := [_build_inventory, _build_character, _build_quests]
	for i in builders.size():
		var page: Control = builders[i].call()
		pages.append(page)
		# Personagem e Missões ainda usam painéis escuros (viram tinta na etapa 2 do plano)
		book.add_page(TAB_NAMES[i], TAB_KEYS[i], TAB_ACTIONS[i], page, i == 0)
	book.closed.connect(_close)
	book.page_shown.connect(_on_page_shown)
	tooltip = ItemTooltip.new()
	add_child(tooltip)
	for s in equip_slots.values():
		s.tooltip = tooltip
	for s in bag_slots:
		s.tooltip = tooltip
	var ids: Array = Game.equipment.values()
	for entry in Game.inventory:
		ids.append(entry.id)
	ItemIcons.prewarm(ids)
	_show_tab(start_tab)
	Game.inventory_changed.connect(_refresh)
	Game.stats_changed.connect(_refresh)
	Game.quests_changed.connect(_refresh)
	_refresh()


func _show_tab(i: int) -> void:
	book.show_page(i)


func _on_page_shown(i: int) -> void:
	start_tab = i
	if tooltip:
		tooltip.visible = false


# ================================================================ inventário
## Livro aberto: página esquerda com o herói e o que ele veste; página direita com a mochila.
func _build_inventory() -> Control:
	var spread := HBoxContainer.new()
	spread.add_theme_constant_override("separation", 84)   # a lombada

	# ================= página esquerda
	var lv := VBoxContainer.new()
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.add_theme_constant_override("separation", 6)
	spread.add_child(lv)
	hero_label = UITheme.ink("", 30, UITheme.INK, true)
	hero_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(hero_label)
	class_label = UITheme.ink("", 14, UITheme.INK_DIM)
	class_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(class_label)
	lv.add_child(HSeparator.new())
	var doll := HBoxContainer.new()
	doll.add_theme_constant_override("separation", 16)
	doll.alignment = BoxContainer.ALIGNMENT_CENTER
	lv.add_child(doll)
	var col_l := VBoxContainer.new()
	var col_r := VBoxContainer.new()
	for c in [col_l, col_r]:
		c.add_theme_constant_override("separation", 10)
		c.alignment = BoxContainer.ALIGNMENT_CENTER
	doll.add_child(col_l)
	doll.add_child(CharPreview.new(Vector2(250, 330)))
	doll.add_child(col_r)
	for i in ItemDB.SLOTS.size():
		var sname: String = ItemDB.SLOTS[i]
		var s := ItemSlot.new(74)
		s.paper = true
		s.slot_name = sname
		s.context = "equip"
		s.ghost_kind = IconPainter.slot_kind(sname)
		s.label_text = ItemDB.SLOT_NAMES[sname] if sname != "offhand" else "Secundária"
		s.drag_source = "equip"
		s.drop_handler = _drop_on_equip
		s.right_clicked.connect(func(sl: ItemSlot) -> void: _unequip(sl.slot_name))
		s.double_clicked.connect(func(sl: ItemSlot) -> void: _unequip(sl.slot_name))
		(col_l if i < 4 else col_r).add_child(s)
		equip_slots[sname] = s
	lv.add_child(HSeparator.new())
	stats_box = HBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 22)
	stats_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(stats_box)
	gold_label = UITheme.ink("", 20, Color(0.45, 0.27, 0.02), true)
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(gold_label)

	# ================= página direita
	var rv := VBoxContainer.new()
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.add_theme_constant_override("separation", 8)
	spread.add_child(rv)
	var top_gap := Control.new()
	top_gap.custom_minimum_size.y = 4
	rv.add_child(top_gap)
	var head := HBoxContainer.new()
	head.add_child(UITheme.ink("Mochila", 26, UITheme.INK, true))
	head.add_child(UITheme.spacer())
	bag_count = UITheme.ink("", 14, UITheme.INK_DIM)
	bag_count.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(bag_count)
	rv.add_child(head)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 6)
	var fg := ButtonGroup.new()
	for f in [["all", "Todos"], ["equip", "Equipamento"], ["use", "Consumíveis"], ["misc", "Diversos"]]:
		var b := Button.new()
		b.text = f[1]
		b.toggle_mode = true
		b.button_group = fg
		b.button_pressed = f[0] == bag_filter
		b.custom_minimum_size = Vector2(0, 30)
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(_set_filter.bind(f[0]))
		filters.add_child(b)
	filters.add_child(UITheme.spacer())
	var sort := UITheme.button("Organizar", _sort_bag)
	sort.custom_minimum_size.y = 30
	sort.add_theme_font_size_override("font_size", 17)
	sort.tooltip_text = "Ordena por tipo e raridade"
	filters.add_child(sort)
	rv.add_child(filters)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(scroll)
	bag_grid = GridContainer.new()
	bag_grid.columns = BAG_COLS
	bag_grid.add_theme_constant_override("h_separation", 5)
	bag_grid.add_theme_constant_override("v_separation", 5)
	scroll.add_child(bag_grid)
	_ensure_bag_slots(BAG_MIN)
	rv.add_child(HSeparator.new())
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	sel_label = UITheme.ink("", 17)
	sel_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sel_label.clip_text = true
	foot.add_child(sel_label)
	use_btn = UITheme.button("Usar", _use_selected, 110)
	drop_btn = UITheme.button("Descartar", _drop_selected, 110)
	for b in [use_btn, drop_btn]:
		b.custom_minimum_size.y = 34
		b.add_theme_font_size_override("font_size", 18)
		foot.add_child(b)
	rv.add_child(foot)
	var hint := UITheme.ink("Clique direito ou duplo: usar/equipar · Arraste entre a mochila e o herói", 12, UITheme.INK_DIM)
	hint.clip_text = true
	rv.add_child(hint)
	return spread


func _set_filter(f: String) -> void:
	bag_filter = f
	sel_index = -1
	_refresh()


func _sort_bag() -> void:
	Game.sort_inventory()
	sel_index = -1
	Sfx.play("click", 0.0)


func _ensure_bag_slots(n: int) -> void:
	while bag_slots.size() < n:
		var s := ItemSlot.new(SLOT)
		s.paper = true
		s.context = "bag"
		s.drag_source = "bag"
		s.drop_handler = _drop_on_bag
		s.tooltip = tooltip
		s.clicked.connect(_on_bag_click)
		s.right_clicked.connect(_on_bag_use)
		s.double_clicked.connect(_on_bag_use)
		bag_grid.add_child(s)
		bag_slots.append(s)


func _on_bag_click(s: ItemSlot) -> void:
	sel_index = s.index if s.item_id != "" else -1
	_refresh_selection()


func _on_bag_use(s: ItemSlot) -> void:
	if s.item_id == "":
		return
	sel_index = s.index
	_use_index(s.index)


func _use_selected() -> void:
	_use_index(sel_index)


func _use_index(i: int) -> void:
	if i < 0 or i >= Game.inventory.size():
		return
	var id: String = Game.inventory[i].id
	if Game.use_item(id):
		Sfx.play("click", 0.0)
		if Game.count_item(id) <= 0:   # (no solo a resposta já chegou; online o refresh acerta depois)
			sel_index = -1


func _drop_selected() -> void:
	if sel_index < 0 or sel_index >= Game.inventory.size():
		return
	Game.discard(Game.inventory[sel_index].id)
	if sel_index >= Game.inventory.size():
		sel_index = -1


func _unequip(slot_name: String) -> void:
	if Game.equipment.get(slot_name, "") != "":
		Game.unequip(slot_name)
		Sfx.play("click", 0.0)


## Soltar na mochila: item vindo do boneco é desequipado.
func _drop_on_bag(_target: ItemSlot, data: Dictionary, apply: bool) -> bool:
	if data.source != "equip":
		return false
	if apply:
		_unequip(data.slot)
	return true


## Soltar num espaço do boneco: equipa se o item couber naquele espaço.
func _drop_on_equip(target: ItemSlot, data: Dictionary, apply: bool) -> bool:
	if data.source != "bag" or ItemDB.slot_of(data.id) != target.slot_name:
		return false
	if apply:
		Game.equip(data.id)
		Sfx.play("click", 0.0)
	return true


func _refresh_inventory() -> void:
	gold_label.text = "%d moedas de ouro" % Game.gold
	for sname in equip_slots:
		var s: ItemSlot = equip_slots[sname]
		s.set_state(Game.equipment.get(sname, ""))
	# mochila filtrada (os índices apontam para Game.inventory)
	var shown: Array = []
	for i in Game.inventory.size():
		var id: String = Game.inventory[i].id
		if bag_filter == "all" or ItemDB.category(id) == bag_filter:
			shown.append(i)
	var need := maxi(BAG_MIN, int(ceil(shown.size() / float(BAG_COLS))) * BAG_COLS)
	_ensure_bag_slots(need)
	for j in bag_slots.size():
		var s := bag_slots[j]
		s.visible = j < need
		if j < shown.size():
			var i: int = shown[j]
			s.index = i
			s.set_state(Game.inventory[i].id, Game.inventory[i].qty)
		else:
			s.index = -1
			s.set_state("")
	bag_count.text = "%d itens" % Game.inventory.size()
	hero_label.text = "%s · Nível %d" % [_hero_name(), Game.level]
	if sel_index >= Game.inventory.size():
		sel_index = -1
	_refresh_selection()
	# resumo de estatísticas
	var cls := Game.weapon_class()
	class_label.text = "Ataque: %s — %s" % [ItemDB.CLASS_NAMES[cls], ItemDB.CLASS_HINT[cls]]
	for c in stats_box.get_children():
		c.queue_free()
	var st := Game.stat_snapshot()
	var groups := [
		["Ataque", [["Dano", "%.0f" % st.dmg], ["Crítico", "%d%%" % int(round(st.crit * 100))],
			["Velocidade", "%d%%" % int(round(st.speed * 100))]]],
		["Defesa", [["Defesa", "%.1f" % st.def], ["Vida", "%d" % st.hp], ["Roubo de vida", "%d%%" % int(round(st.leech * 100))]]],
		["Magia", [["Poder mágico", "%.0f" % st.spell], ["Mana", "%d" % st.mp]]]]
	for g in groups:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 2)
		col.add_child(UITheme.ink(g[0], 18, UITheme.INK_RED, true))
		for r in g[1]:
			var row := HBoxContainer.new()
			row.add_child(UITheme.ink(r[0], 14, UITheme.INK_DIM))
			row.add_child(UITheme.spacer())
			row.add_child(UITheme.ink(r[1], 15, UITheme.INK))
			col.add_child(row)
		stats_box.add_child(col)


func _refresh_selection() -> void:
	for s in bag_slots:
		s.selected = s.item_id != "" and s.index == sel_index
		s.queue_redraw()
	if sel_index < 0 or sel_index >= Game.inventory.size():
		sel_label.text = "Selecione um item."
		sel_label.add_theme_color_override("font_color", UITheme.INK_DIM)
		use_btn.disabled = true
		drop_btn.disabled = true
		use_btn.text = "Usar"
		return
	var id: String = Game.inventory[sel_index].id
	var it := ItemDB.get_item(id)
	sel_label.text = it.name + ("  x%d" % Game.inventory[sel_index].qty if Game.inventory[sel_index].qty > 1 else "")
	sel_label.add_theme_color_override("font_color", ItemDB.rarity_color(id).darkened(0.55) if ItemDB.is_equippable(id) else UITheme.INK)
	var t: String = it.type
	use_btn.disabled = t == "material" or t == "seed" or (t == "crop" and not Game.is_edible(id))
	use_btn.text = "Equipar" if ItemDB.is_equippable(id) else ("Comer" if t in ["food", "crop"] else "Usar")
	drop_btn.disabled = false


# ================================================================ personagem
func _build_character() -> Control:
	char_page = HBoxContainer.new()
	char_page.add_theme_constant_override("separation", 14)
	return char_page


func _refresh_character() -> void:
	for c in char_page.get_children():
		c.queue_free()
	# ---- atributos
	var left := _inset()
	left.custom_minimum_size.x = 560
	char_page.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 10)
	left.add_child(lv)
	var top := HBoxContainer.new()
	top.add_child(UITheme.heading("%s — Nível %d" % [_hero_name(), Game.level], 26))
	lv.add_child(top)
	var xpb := UITheme.bar(UITheme.XP, 520, 14)
	xpb.max_value = Game.xp_to_next()
	xpb.value = Game.xp
	lv.add_child(xpb)
	lv.add_child(UITheme.label("Experiência: %d / %d" % [Game.xp, Game.xp_to_next()], 15, UITheme.DIM))
	var pts := UITheme.section("Atributos")
	if Game.stat_points > 0:
		var chip := UITheme.label("  %d pontos para distribuir  " % Game.stat_points, 15, Color(0.1, 0.07, 0.02))
		var chip_bg := PanelContainer.new()
		chip_bg.add_theme_stylebox_override("panel", UITheme._box(Color(1, 0.8, 0.3), Color(1, 0.9, 0.5), 1, 10, 4, 1))
		chip_bg.add_child(chip)
		pts.add_child(chip_bg)
	lv.add_child(pts)
	var info := {"str": ["Força", "Dano da espada, um pouco do arco", Color(1, 0.55, 0.35)],
		"int": ["Inteligência", "Mana, magias e dano do cajado", Color(0.55, 0.65, 1.0)],
		"vit": ["Vitalidade", "Vida, defesa e regeneração", Color(1, 0.4, 0.4)],
		"agi": ["Agilidade", "Vigor, velocidade, crítico e dano do arco", Color(0.5, 0.95, 0.55)]}
	for a in ["str", "int", "vit", "agi"]:
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UITheme._box(Color(0.12, 0.1, 0.08, 0.8), Color(0.28, 0.23, 0.16), 1, 4, 12, 6))
		lv.add_child(row)
		var rh := HBoxContainer.new()
		rh.add_theme_constant_override("separation", 12)
		row.add_child(rh)
		var bar := ColorRect.new()
		bar.color = info[a][2]
		bar.custom_minimum_size = Vector2(4, 0)
		rh.add_child(bar)
		var names := VBoxContainer.new()
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		names.add_child(UITheme.heading(info[a][0], 19, info[a][2].lightened(0.2)))
		names.add_child(UITheme.label(info[a][1], 14, UITheme.DIM))
		rh.add_child(names)
		var val := UITheme.heading(str(Game.attr(a)), 28, UITheme.TEXT)
		val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rh.add_child(val)
		var bonus := int(Game.gear(a))
		var bl := UITheme.label("(+%d itens)" % bonus if bonus > 0 else "", 14, UITheme.GOOD)
		bl.custom_minimum_size.x = 80
		bl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rh.add_child(bl)
		var b := UITheme.button("+", Game.spend_point.bind(a), 44)
		b.disabled = Game.stat_points <= 0
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rh.add_child(b)

	# ---- estatísticas e magias
	var right := _inset()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	char_page.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	right.add_child(rv)
	rv.add_child(UITheme.section("Estatísticas"))
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 5)
	rv.add_child(g)
	var st := Game.stat_snapshot()
	var red := 1.0 - 50.0 / (50.0 + Game.defense() * 4.0)
	var rows := [["Arma", ItemDB.CLASS_NAMES[Game.weapon_class()]], ["Dano do ataque", "%.0f" % st.dmg],
		["Defesa", "%.1f" % st.def], ["Redução de dano", "%d%%" % int(round(red * 100))],
		["Vida máxima", "%d" % st.hp], ["Mana máxima", "%d" % st.mp], ["Vigor máximo", "%d" % Game.max_stamina()],
		["Poder mágico", "%.0f" % st.spell], ["Crítico", "%d%%" % int(round(st.crit * 100))],
		["Velocidade", "%d%%" % int(round(st.speed * 100))], ["Recarga reduzida", "%d%%" % int(round(st.cdr * 100))],
		["Roubo de vida", "%d%%" % int(round(st.leech * 100))], ["Inimigos derrotados", str(Game.kills)]]
	for r in rows:
		g.add_child(UITheme.label(r[0], 15, UITheme.DIM))
		var vl := UITheme.label(r[1], 16)
		vl.custom_minimum_size.x = 80
		g.add_child(vl)
	rv.add_child(UITheme.section("Habilidades"))
	for id in Game.ability_kit():
		var sp: Dictionary = ItemDB.ABILITIES[id]
		var known := Game.knows_ability(id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var s := ItemSlot.new(52)
		s.icon_kind = sp.icon
		s.key_text = str(sp.slot)
		s.dim = not known
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(s)
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(UITheme.label("%s   ·   %s   ·   %s" % [sp.name, ("%d MP" % sp.cost) if sp.cost > 0 else "sem custo",
			("ultimate (fúria)" if sp.ultimate else "recarga %.1fs" % (sp.cooldown * Game.cooldown_mult()))], 17,
			UITheme.TEXT if known else UITheme.DIM))
		var d := UITheme.label(sp.desc + ("" if known else "   (aprende no nível %d)" % sp.level), 14, UITheme.DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tv.add_child(d)
		row.add_child(tv)
		rv.add_child(row)


func _hero_name() -> String:
	var n: String = str(Game.settings.get("player_name", ""))
	return n if n != "" else "Cavaleiro"


# ================================================================ missões
func _build_quests() -> Control:
	quest_page = HBoxContainer.new()
	quest_page.add_theme_constant_override("separation", 14)
	return quest_page


func _refresh_quests() -> void:
	for c in quest_page.get_children():
		c.queue_free()
	var left := _inset()
	left.custom_minimum_size.x = 380
	quest_page.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	left.add_child(lv)
	lv.add_child(UITheme.section("Diário"))
	var right := _inset()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quest_page.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	right.add_child(rv)
	if Game.quests.is_empty():
		lv.add_child(UITheme.label("Nenhuma missão ainda.", 16, UITheme.DIM))
		var l := UITheme.label("Fale com o Ancião Bram na vila para receber sua primeira missão.", 17, UITheme.DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rv.add_child(l)
		return
	if quest_sel == "" or not Game.quests.has(quest_sel):
		for id in Game.quests:   # a primeira não concluída
			if Game.quests[id].state != "done":
				quest_sel = id
				break
		if quest_sel == "":
			quest_sel = Game.quests.keys()[0]
	var group := ButtonGroup.new()
	for state in ["ready", "active", "done"]:
		for id in Game.quests:
			if Game.quests[id].state != state:
				continue
			var d: Dictionary = ItemDB.QUESTS[id]
			var b := Button.new()
			b.toggle_mode = true
			b.button_group = group
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.text = ("✔ " if state == "done" else ("★ " if state == "ready" else "◆ ")) + d.name
			b.button_pressed = id == quest_sel
			b.custom_minimum_size.y = 42
			if state == "done":
				b.add_theme_color_override("font_color", UITheme.DIM)
			elif state == "ready":
				b.add_theme_color_override("font_color", UITheme.GOOD)
			b.pressed.connect(_select_quest.bind(id))
			lv.add_child(b)
	# detalhes
	var q: Dictionary = Game.quests[quest_sel]
	var d: Dictionary = ItemDB.QUESTS[quest_sel]
	rv.add_child(UITheme.heading(d.name, 28))
	var st: String = {"active": "Em andamento", "ready": "Pronta para entregar", "done": "Concluída"}[q.state]
	var sc: Color = {"active": UITheme.GOLD, "ready": UITheme.GOOD, "done": UITheme.DIM}[q.state]
	rv.add_child(UITheme.label("%s   ·   dada por %s" % [st, d.giver], 16, sc))
	rv.add_child(HSeparator.new())
	var desc := UITheme.label(d.desc, 18)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(desc)
	rv.add_child(UITheme.section("Objetivo", 18))
	var pb := UITheme.bar(UITheme.XP, 500, 16)
	pb.max_value = d.count
	pb.value = mini(q.progress, d.count)
	rv.add_child(pb)
	rv.add_child(UITheme.label("%d / %d" % [mini(q.progress, d.count), d.count] + ("   —   volte para %s" % d.giver if q.state == "ready" else ""), 16))
	rv.add_child(UITheme.section("Recompensas", 18))
	var rw := HBoxContainer.new()
	rw.add_theme_constant_override("separation", 12)
	rw.add_child(UITheme.label("◆ %d ouro     ✦ %d XP" % [d.reward_gold, d.reward_xp], 18, Color(1, 0.85, 0.4)))
	for item in d.reward_items:
		var s := ItemSlot.new(56)
		s.set_state(item, d.reward_items[item])
		s.context = "reward"
		s.tooltip = tooltip
		rw.add_child(s)
	rv.add_child(rw)


func _select_quest(id: String) -> void:
	quest_sel = id
	_refresh_quests.call_deferred()


# ================================================================ geral
func _inset() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.inset_box(14))
	return p


func _refresh() -> void:
	if not is_inside_tree():
		return
	_refresh_inventory()
	_refresh_character()
	_refresh_quests()


func _close() -> void:
	closed.emit()
	queue_free()
