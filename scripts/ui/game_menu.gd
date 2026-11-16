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

# personagem
const ATTR_ORDER := ["str", "int", "vit", "agi"]
## nome, o que o atributo faz, cor da tinta
const ATTR_INFO := {"str": ["Força", "Dano da espada, um pouco do arco", Color(0.6, 0.22, 0.06)],
	"int": ["Inteligência", "Mana, magias e dano do cajado", Color(0.15, 0.24, 0.56)],
	"vit": ["Vitalidade", "Vida, defesa e regeneração", Color(0.58, 0.1, 0.12)],
	"agi": ["Agilidade", "Vigor, velocidade, crítico e dano do arco", Color(0.12, 0.4, 0.15)]}
const INK_GOOD := Color(0.1, 0.4, 0.12)
const INK_GOLD := Color(0.45, 0.27, 0.02)
var char_left: VBoxContainer
var char_right: VBoxContainer
var attr_buttons := {}      # atributo -> botão "+"
var attr_values := {}       # atributo -> rótulo do valor

# missões
## estado -> título do grupo no diário, marca, cor da tinta, texto do estado nos detalhes (na ordem do diário)
const QUEST_STATES := {"ready": ["Prontas para entregar", "★", INK_GOOD, "Pronta para entregar"],
	"active": ["Em andamento", "◆", UITheme.INK, "Em andamento"],
	"done": ["Concluídas", "✓", UITheme.INK_DIM, "Concluída"]}
var quest_left: VBoxContainer
var quest_right: VBoxContainer
var quest_buttons := {}     # id da missão -> botão no diário
var quest_title: Label
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
		book.add_page(TAB_NAMES[i], TAB_KEYS[i], TAB_ACTIONS[i], page)
	book.closed.connect(_close)
	book.page_shown.connect(_on_page_shown)
	tooltip = ItemTooltip.new()
	tooltip.paper = true
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
	spread.add_theme_constant_override("separation", int(BookLayout.SPINE))   # a lombada

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
	gold_label = UITheme.ink("", 20, INK_GOLD, true)
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
	if data.source != "bag" or ItemDB.slot_of(data.id) != target.slot_name or not Game.can_wield(data.id):
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
			s.dim = not Game.can_wield(s.item_id)   # arma de outra classe: só para vender
		else:
			s.index = -1
			s.set_state("")
			s.dim = false
	bag_count.text = "%d itens" % Game.inventory.size()
	hero_label.text = "%s · Nível %d" % [_hero_name(), Game.level]
	if sel_index >= Game.inventory.size():
		sel_index = -1
	_refresh_selection()
	# resumo de estatísticas
	var cls := Game.weapon_class()
	class_label.text = "%s · Ataque: %s — %s" % [Game.class_display_name(), ItemDB.CLASS_NAMES[cls], ItemDB.CLASS_HINT[cls]]
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
	use_btn.disabled = t == "material" or t == "seed" or (t == "crop" and not Game.is_edible(id)) or not Game.can_wield(id)
	use_btn.text = "Equipar" if ItemDB.is_equippable(id) else ("Comer" if t in ["food", "crop"] else "Usar")
	drop_btn.disabled = false


# ================================================================ personagem
## Página esquerda: nome, experiência e atributos; página direita: estatísticas e habilidades.
func _build_character() -> Control:
	var cols := _spread(8)
	char_left = cols[1]
	char_right = cols[2]
	return cols[0]


func _refresh_character() -> void:
	_clear(char_left)
	_clear(char_right)
	attr_buttons.clear()
	attr_values.clear()
	# ---- página esquerda: quem é o herói e os atributos
	var lv := char_left
	var title := UITheme.ink("%s · Nível %d" % [_hero_name(), Game.level], 30, UITheme.INK, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.clip_text = true
	lv.add_child(title)
	var xrow := HBoxContainer.new()
	xrow.add_child(UITheme.ink("Experiência", 15, UITheme.INK_DIM))
	xrow.add_child(UITheme.spacer())
	xrow.add_child(UITheme.ink("%d / %d" % [Game.xp, Game.xp_to_next()], 15))
	lv.add_child(xrow)
	var xpb := UITheme.ink_bar(UITheme.XP, 0, 14)
	xpb.max_value = Game.xp_to_next()
	xpb.value = Game.xp
	lv.add_child(xpb)
	lv.add_child(_gap(6))
	var pts := UITheme.ink_section("Atributos", 20)
	if Game.stat_points > 0:
		# aviso em quadro de tinta vermelha (texto a tinta, não um selo de cor cheia)
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UITheme._box(Color(UITheme.INK_RED, 0.1), UITheme.INK_RED, 1, 10, 10, 1))
		var n := Game.stat_points
		chip.add_child(UITheme.ink("%d %s para distribuir" % [n, "ponto" if n == 1 else "pontos"], 15, UITheme.INK_RED))
		pts.add_child(chip)
	lv.add_child(pts)
	for a in ATTR_ORDER:
		var info: Array = ATTR_INFO[a]
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UITheme.ink_inset(12))
		lv.add_child(row)
		var rh := HBoxContainer.new()
		rh.add_theme_constant_override("separation", 12)
		row.add_child(rh)
		var strip := ColorRect.new()
		strip.color = info[2]
		strip.custom_minimum_size = Vector2(4, 0)
		rh.add_child(strip)
		var names := VBoxContainer.new()
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		names.add_theme_constant_override("separation", 0)
		names.add_child(UITheme.ink(info[0], 19, info[2], true))
		var desc := UITheme.ink(info[1], 14, UITheme.INK_DIM)
		desc.clip_text = true
		names.add_child(desc)
		rh.add_child(names)
		var bonus := int(Game.gear(a))
		var bl := UITheme.ink("+%d de itens" % bonus if bonus > 0 else "", 13, INK_GOOD)
		bl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rh.add_child(bl)
		var val := UITheme.ink(str(Game.attr(a)), 28, UITheme.INK, true)
		val.custom_minimum_size.x = 44
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rh.add_child(val)
		attr_values[a] = val
		var b := UITheme.button("+", Game.spend_point.bind(a), 40)
		b.custom_minimum_size.y = 36
		b.tooltip_text = "Gastar 1 ponto em %s" % info[0]
		b.disabled = Game.stat_points <= 0
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rh.add_child(b)
		attr_buttons[a] = b
	var tip := UITheme.ink("Cada nível dá pontos para distribuir. O valor já soma o que os itens dão.", 13, UITheme.INK_DIM)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(tip)

	# ---- página direita: estatísticas e habilidades
	var rv := char_right
	rv.add_child(_gap(4))
	rv.add_child(UITheme.ink_section("Estatísticas", 20))
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 2)
	rv.add_child(g)
	var st := Game.stat_snapshot()
	var red := 1.0 - 50.0 / (50.0 + Game.defense() * 4.0)
	var rows := [["Classe", Game.class_display_name()], ["Arma", ItemDB.CLASS_NAMES[Game.weapon_class()]], ["Dano do ataque", "%.0f" % st.dmg],
		["Defesa", "%.1f" % st.def], ["Redução de dano", "%d%%" % int(round(red * 100))],
		["Vida máxima", "%d" % st.hp], ["Mana máxima", "%d" % st.mp], ["Vigor máximo", "%d" % Game.max_stamina()],
		["Poder mágico", "%.0f" % st.spell], ["Crítico", "%d%%" % int(round(st.crit * 100))],
		["Velocidade", "%d%%" % int(round(st.speed * 100))], ["Recarga reduzida", "%d%%" % int(round(st.cdr * 100))],
		["Roubo de vida", "%d%%" % int(round(st.leech * 100))], ["Inimigos derrotados", str(Game.kills)]]
	if Game.quest_state("registro") == "done":
		rows.push_front(["Pontos de guilda", str(Game.guild_points())])
		rows.push_front(["Rank na Guilda", Game.rank()])
	for r in rows:
		var nl := UITheme.ink(r[0], 15, UITheme.INK_DIM)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(nl)
		var vl := UITheme.ink(r[1], 16)
		vl.custom_minimum_size.x = 62
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		g.add_child(vl)
	rv.add_child(_gap(6))
	rv.add_child(UITheme.ink_section("Habilidades", 20))
	for id in Game.ability_kit():
		var sp: Dictionary = ItemDB.ABILITIES[id]
		var known := Game.knows_ability(id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var s := ItemSlot.new(50)
		s.paper = true
		s.icon_kind = sp.icon
		s.key_text = str(sp.slot)
		s.dim = not known
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(s)
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_theme_constant_override("separation", 0)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		head.add_child(UITheme.ink(sp.name, 17, UITheme.INK if known else UITheme.INK_DIM, true))
		head.add_child(UITheme.spacer())
		var meta := "%s · %s" % [("%d MP" % sp.cost) if sp.cost > 0 else "sem custo",
			"ultimate (fúria)" if sp.ultimate else "recarga %.1fs" % (sp.cooldown * Game.cooldown_mult())]
		head.add_child(UITheme.ink(meta, 14, UITheme.INK_DIM))
		tv.add_child(head)
		var d := UITheme.ink(sp.desc, 14, UITheme.INK if known else UITheme.INK_DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tv.add_child(d)
		if not known:
			tv.add_child(UITheme.ink("Aprende no nível %d" % sp.level, 13, UITheme.INK_RED))
		row.add_child(tv)
		rv.add_child(row)


func _hero_name() -> String:
	var n: String = str(Game.settings.get("player_name", ""))
	return n if n != "" else "Cavaleiro"


# ================================================================ missões
## Página esquerda: o diário (lista por estado); página direita: os detalhes da missão escolhida.
func _build_quests() -> Control:
	var cols := _spread(8)
	quest_left = cols[1]
	quest_right = cols[2]
	return cols[0]


func _refresh_quests() -> void:
	_clear(quest_left)
	_clear(quest_right)
	quest_buttons.clear()
	quest_title = null
	var lv := quest_left
	var rv := quest_right
	lv.add_child(_gap(4))
	lv.add_child(UITheme.ink_section("Diário", 20))
	rv.add_child(_gap(4))
	if Game.quests.is_empty():
		lv.add_child(UITheme.ink("Nenhuma missão ainda.", 16, UITheme.INK_DIM))
		var l := UITheme.ink("Fale com o Ancião Bram, perto do poço da vila, para começar a história.", 17, UITheme.INK_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rv.add_child(l)
		return
	if quest_sel == "" or not Game.quests.has(quest_sel):
		quest_sel = ""
		for id in Game.quests:   # a primeira não concluída
			if Game.quests[id].state != "done":
				quest_sel = id
				break
		if quest_sel == "":
			quest_sel = Game.quests.keys()[0]
	# linha do tempo: a história na ordem da cadeia, separada por episódio, até a próxima missão;
	# depois os contratos (prontos e em andamento primeiro). A lista rola quando passa da página.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	var qt: Dictionary = ItemDB.QUESTS
	var group := ButtonGroup.new()
	var sel_btn: Button = null
	list.add_child(UITheme.ink("HISTÓRIA", 16, INK_GOLD, true))
	var nxt := StoryRules.current(qt, Game.quests)
	for id in qt:
		if StoryRules.is_side(qt, id):
			continue
		var started := Game.quests.has(id)
		if not started and id != nxt:
			continue
		if qt[id].has("chapter"):
			var ch: Dictionary = qt[id].chapter
			list.add_child(_gap(6))
			list.add_child(UITheme.ink("Episódio %d · %s" % [int(ch.get("n", 0)), ch.get("title", "")], 15, INK_GOLD))
		if started:
			var b := _quest_button(id, group)
			list.add_child(b)
			if id == quest_sel:
				sel_btn = b
		else:
			# a próxima da história, ainda não aceita: diz com quem falar (ou o rank que falta)
			var need := StoryRules.needs_rank(qt, id)
			var who: String = StoryDialogue.NAMES.get(StoryRules.giver(qt, id), qt[id].get("giver", ""))
			var hint := "○  Próxima: fale com %s" % who if StoryRules.rank_ge(Game.rank(), need) \
				else "○  Próxima: exige Rank %s" % need
			var l := UITheme.ink(hint, 18, UITheme.INK_DIM)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			list.add_child(l)
	var sides: Array = []
	for state in QUEST_STATES:
		for id in Game.quests:
			if Game.quests[id].state == state and StoryRules.is_side(qt, id):
				sides.append(id)
	if not sides.is_empty():
		list.add_child(_gap(10))
		list.add_child(UITheme.ink("CONTRATOS", 16, INK_GOLD, true))
		for id in sides:
			var b := _quest_button(id, group)
			list.add_child(b)
			if id == quest_sel:
				sel_btn = b
	if sel_btn != null:
		(func() -> void: if is_instance_valid(sel_btn): scroll.ensure_control_visible(sel_btn)).call_deferred()
	# detalhes
	var q: Dictionary = Game.quests[quest_sel]
	var d: Dictionary = ItemDB.QUESTS[quest_sel]
	var sinfo: Array = QUEST_STATES[q.state]
	quest_title = UITheme.ink(d.name, 28, UITheme.INK, true)
	quest_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if d.has("chapter"):
		rv.add_child(UITheme.ink("Episódio %d · %s" % [int(d.chapter.get("n", 0)), d.chapter.get("title", "")], 14, INK_GOLD))
	rv.add_child(quest_title)
	rv.add_child(UITheme.ink("%s · dada por %s" % [sinfo[3], d.giver], 15, sinfo[2]))
	if CharRules.is_side(d):
		var tag := "Contrato secundário · Rank %s" % d.get("rank", "D")
		if d.get("repeat", false):
			tag += " · repetível"
		rv.add_child(UITheme.ink(tag, 14, UITheme.INK_DIM))
	rv.add_child(HSeparator.new())
	var desc := UITheme.ink(d.desc, 17)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(desc)
	rv.add_child(_gap(4))
	rv.add_child(UITheme.ink_section("Objetivo", 18))
	var counts := {}
	for item in StoryRules.count_ids(d):
		counts[item] = Game.count_item(item)
	var pr := StoryRules.progress(ItemDB.QUESTS, Game.quests, quest_sel, counts)
	var turn := StoryRules.turnable(ItemDB.QUESTS, Game.quests, quest_sel, counts)
	var obj := UITheme.ink(str(d.get("objective", d.desc)), 16)
	obj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(obj)
	if CharRules.quest_type(d) != "talk":
		var pb := UITheme.ink_bar(UITheme.XP, 0, 16)
		pb.max_value = pr[1]
		pb.value = pr[0]
		rv.add_child(pb)
	var prog := "%d / %d" % [pr[0], pr[1]] if CharRules.quest_type(d) != "talk" else ""
	if q.state != "done" and turn:
		prog += (" — " if prog != "" else "") + "fale com %s" % d.get("turn_in", d.giver)
	if prog != "":
		rv.add_child(UITheme.ink(prog, 16))
	rv.add_child(_gap(4))
	rv.add_child(UITheme.ink_section("Recompensas", 18))
	var rw := HBoxContainer.new()
	rw.add_theme_constant_override("separation", 12)
	var coins := UITheme.ink("%d de ouro  ·  %d de XP" % [d.reward_gold, d.reward_xp], 17, INK_GOLD)
	coins.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rw.add_child(coins)
	for item in d.reward_items:
		var s := ItemSlot.new(56)
		s.paper = true
		s.set_state(item, d.reward_items[item])
		s.context = "reward"
		s.tooltip = tooltip
		rw.add_child(s)
	rv.add_child(rw)
	if q.state == "done":
		rv.add_child(UITheme.ink("Recompensas já recebidas.", 14, UITheme.INK_DIM))


## Botão de uma missão do diário: ícone do estado (✓ ◆ ★) e o nome, na cor do estado.
func _quest_button(id: String, group: ButtonGroup) -> Button:
	var info: Array = QUEST_STATES[Game.quests[id].state]
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = group
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = "%s  %s" % [info[1], ItemDB.QUESTS[id].name]
	b.clip_text = true
	b.button_pressed = id == quest_sel
	b.custom_minimum_size.y = 40
	b.add_theme_font_size_override("font_size", 21)
	b.add_theme_color_override("font_color", info[2])
	b.add_theme_color_override("font_hover_color", info[2])
	b.pressed.connect(_select_quest.bind(id))
	quest_buttons[id] = b
	return b


func _select_quest(id: String) -> void:
	quest_sel = id
	_refresh_quests.call_deferred()


# ================================================================ geral
## Uma abertura do livro: duas páginas lado a lado com a lombada livre no meio.
## Devolve [abertura, página esquerda, página direita].
func _spread(separation: int) -> Array:
	var spread := HBoxContainer.new()
	spread.add_theme_constant_override("separation", int(BookLayout.SPINE))
	var out: Array = [spread]
	for i in 2:
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", separation)
		spread.add_child(v)
		out.append(v)
	return out


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Tira os filhos na hora (queue_free sozinho deixaria o conteúdo velho na página até o fim do quadro).
func _clear(box: Control) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _refresh() -> void:
	if not is_inside_tree():
		return
	_refresh_inventory()
	_refresh_character()
	_refresh_quests()


func _close() -> void:
	closed.emit()
	queue_free()
