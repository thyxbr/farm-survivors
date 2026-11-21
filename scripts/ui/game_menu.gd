extends Control
## Menu do herói em janelas laterais (BookWindow, WindowDock), em dois modos:
## - "inventory" (janela da direita): o herói com o que veste em volta (abas Equipamento e Ferramentas) e,
##   embaixo, a mochila em grade. Com uma loja aberta ao lado (`set_trade`), clique direito vende.
## - "hero" (janela da esquerda): Personagem (atributos, estatísticas, magias), Talentos (árvore da classe,
##   TalentPanel), Missões (lista + detalhes) e Profissões, em duas colunas.
## Referências: boneco e grade de Diablo/Path of Exile, dicas com comparação calculada,
## filtros por categoria, atalhos visíveis nas abas.

signal closed

## Abas da janela do herói (o inventário é a outra janela).
const TAB_KEYS := ["C", "K", "J", "L", "B"]
const TAB_NAMES := ["Personagem", "Talentos", "Missões", "Profissões", "Bestiário"]
const TAB_ACTIONS := ["character", "talents", "quest_log", "professions", "bestiary"]
const BAG_COLS := 6
const BAG_MIN := 48
const SLOT := 64.0
const EQUIP_SLOT := 60.0
## Largura das páginas: a do inventário (6 colunas de mochila) e a do herói (duas colunas lado a lado,
## cabendo entre a borda esquerda e o inventário numa tela de 1600).
const INV_WIDTH := 424.0
const HERO_WIDTH := 1000.0
## Largura de cada aba da janela do herói: a janela acompanha o conteúdo (Personagem é uma coluna só,
## Talentos é a árvore com as habilidades ao lado; Missões e Profissões em duas colunas).
const TAB_WIDTHS := [640.0, 900.0, 1000.0, 900.0, 1000.0]

## "inventory" ou "hero"; escolher antes de entrar na árvore.
var mode := "hero"
## Lado da tela onde a janela encaixa (WindowDock).
var dock_side: String:
	get:
		return "right" if mode == "inventory" else "left"
## Aba aberta primeiro (na janela do herói: 0 = Personagem).
var start_tab := 0
## Loja aberta ao lado (tem `trade_item`): clique direito na mochila vende para ela.
var trade: Control = null
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
var hint_label: Label

# ferramentas (aba da página esquerda do Inventário)
var tool_slots := {}            # "pickaxe"/"axe" -> ItemSlot do espaço
var tool_info := {}             # "pickaxe"/"axe" -> VBoxContainer com força e maestria
var gear_view: Control          # aba Equipamento: o resumo de atributos embaixo do boneco
var tools_view: Control         # aba Ferramentas: o resumo de cada ferramenta embaixo do boneco
var hero_preview: CharPreview   # o boneco (na aba Ferramentas segura a picareta ou o machado)
var side_tab := "equip"
var side_buttons := {}          # "equip"/"tools" -> botão da aba

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

# talentos
var talent_panel: TalentPanel

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
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UITheme.get_theme()
	book = BookWindow.new()
	book.side = dock_side
	book.page_width = INV_WIDTH if mode == "inventory" else HERO_WIDTH
	book.fit_height = mode != "inventory"   # a mochila rola e aproveita a altura toda
	add_child(book)
	if mode == "inventory":
		var inv := _build_inventory()
		pages.append(inv)
		book.add_page("Inventário", "I", "inventory", inv)
	else:
		var builders := [_build_character, _build_talents, _build_quests, _build_professions, _build_bestiary]
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
	for s in tool_slots.values():
		s.tooltip = tooltip
	for s in bag_slots:
		s.tooltip = tooltip
	var ids: Array = Game.equipment.values()
	for entry in Game.inventory:
		ids.append(entry.id)
	ItemIcons.prewarm(ids)
	_show_tab(clampi(start_tab, 0, pages.size() - 1))
	Game.inventory_changed.connect(_refresh)
	Game.stats_changed.connect(_refresh)
	Game.quests_changed.connect(_refresh)
	Game.bestiary_changed.connect(_refresh)
	_refresh()


func _show_tab(i: int) -> void:
	book.show_page(i)


func _on_page_shown(i: int) -> void:
	start_tab = i
	if tooltip:
		tooltip.visible = false
	if mode == "hero" and i < TAB_WIDTHS.size() and book.page_width != TAB_WIDTHS[i]:
		book.set_page_width(TAB_WIDTHS[i])


# ================================================================ inventário
## Uma coluna: em cima o herói com o que veste em volta (abas Equipamento e Ferramentas), no meio o ouro, e
## embaixo a mochila em grade, que fica com o resto da altura e rola.
func _build_inventory() -> Control:
	var lv := VBoxContainer.new()
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.add_theme_constant_override("separation", 6)
	var who := HBoxContainer.new()
	hero_label = UITheme.ink("", 20, UITheme.INK, true)
	hero_label.clip_text = true
	hero_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_child(hero_label)
	# abas: Equipamento (o herói) e Ferramentas (picareta e machado)
	var sg := ButtonGroup.new()
	for f in [["equip", "Equipamento"], ["tools", "Ferramentas"]]:
		var b := Button.new()
		b.text = f[1]
		b.toggle_mode = true
		b.button_group = sg
		b.button_pressed = f[0] == side_tab
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 28)
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(_set_side_tab.bind(f[0]))
		who.add_child(b)
		side_buttons[f[0]] = b
	lv.add_child(who)
	class_label = UITheme.ink("", 13, UITheme.INK_DIM)
	class_label.clip_text = true
	lv.add_child(class_label)
	# o boneco é o mesmo nas duas abas; os espaços em volta e o resumo de baixo trocam com a aba
	var doll := HBoxContainer.new()
	doll.add_theme_constant_override("separation", 12)
	doll.alignment = BoxContainer.ALIGNMENT_CENTER
	lv.add_child(doll)
	var col_l := VBoxContainer.new()
	var col_r := VBoxContainer.new()
	for c in [col_l, col_r]:
		c.add_theme_constant_override("separation", 8)
		c.alignment = BoxContainer.ALIGNMENT_CENTER
	doll.add_child(col_l)
	# meio: o boneco e, embaixo dele, o espaço das costas (capa ou asas)
	var col_m := VBoxContainer.new()
	col_m.add_theme_constant_override("separation", 4)
	col_m.alignment = BoxContainer.ALIGNMENT_CENTER
	doll.add_child(col_m)
	hero_preview = CharPreview.new(Vector2(180, 216))
	col_m.add_child(hero_preview)
	doll.add_child(col_r)
	for i in ItemDB.SLOTS.size():
		var sname: String = ItemDB.SLOTS[i]
		var tool := sname in ItemDB.TOOL_SLOTS
		var s := ItemSlot.new(EQUIP_SLOT)
		s.paper = true
		s.slot_name = sname
		s.context = "equip"
		s.ghost_kind = IconPainter.slot_kind(sname)
		s.label_text = ItemDB.SLOT_NAMES[sname] if sname != "offhand" else "Secundária"
		s.drag_source = "equip"
		s.drop_handler = _drop_on_equip
		s.right_clicked.connect(func(sl: ItemSlot) -> void: _unequip(sl.slot_name))
		s.double_clicked.connect(func(sl: ItemSlot) -> void: _unequip(sl.slot_name))
		if tool:
			# ferramentas em volta do boneco como o equipamento, alternando os lados (novas ferramentas entram aqui)
			var k := ItemDB.TOOL_SLOTS.find(sname)
			(col_l if k % 2 == 0 else col_r).add_child(s)
			s.visible = false
			tool_slots[sname] = s
		elif sname == "back":
			s.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			col_m.add_child(s)
			equip_slots[sname] = s
		else:
			(col_l if i < 4 else col_r).add_child(s)
			equip_slots[sname] = s
	# aba Equipamento: nada embaixo do boneco (os números ficam na janela Personagem, C);
	# aba Ferramentas: força e maestria de cada ferramenta
	gear_view = Control.new()
	gear_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv.add_child(gear_view)
	tools_view = _build_tool_side()
	tools_view.size_flags_vertical = Control.SIZE_FILL
	lv.add_child(tools_view)
	var money := HBoxContainer.new()
	gold_label = UITheme.ink("", 18, INK_GOLD, true)
	money.add_child(gold_label)
	money.add_child(UITheme.spacer())
	bag_count = UITheme.ink("", 14, UITheme.INK_DIM)
	bag_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	money.add_child(bag_count)
	lv.add_child(money)
	lv.add_child(HSeparator.new())
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 4)
	var fg := ButtonGroup.new()
	for f in [["all", "Tudo"], ["equip", "Equipar"], ["use", "Usar"], ["misc", "Outros"]]:
		var b := Button.new()
		b.text = f[1]
		b.toggle_mode = true
		b.button_group = fg
		b.button_pressed = f[0] == bag_filter
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 28)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(_set_filter.bind(f[0]))
		filters.add_child(b)
	var sort := UITheme.button("Organizar", _sort_bag)
	sort.custom_minimum_size.y = 28
	sort.focus_mode = Control.FOCUS_NONE
	sort.add_theme_font_size_override("font_size", 15)
	sort.tooltip_text = "Ordena por tipo e raridade"
	filters.add_child(sort)
	lv.add_child(filters)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 3 * SLOT + 10
	lv.add_child(scroll)
	bag_grid = GridContainer.new()
	bag_grid.columns = BAG_COLS
	bag_grid.add_theme_constant_override("h_separation", 5)
	bag_grid.add_theme_constant_override("v_separation", 5)
	scroll.add_child(bag_grid)
	_ensure_bag_slots(BAG_MIN)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 6)
	sel_label = UITheme.ink("", 16)
	sel_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sel_label.clip_text = true
	foot.add_child(sel_label)
	use_btn = UITheme.primary(UITheme.button("Usar", _use_selected, 96))
	drop_btn = UITheme.button("Descartar", _drop_selected, 96)
	for b in [drop_btn, use_btn]:   # a ação principal (vermelha) por último, como nas outras janelas
		b.custom_minimum_size.y = 34
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 16)
		foot.add_child(b)
	lv.add_child(foot)
	hint_label = UITheme.ink("", 13, UITheme.INK_DIM)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # quebra linha em vez de cortar
	hint_label.custom_minimum_size.x = 120
	lv.add_child(hint_label)
	return lv


## Loja aberta ao lado (ou null): troca o clique direito da mochila entre usar e vender.
func set_trade(t: Control) -> void:
	trade = t
	for s in bag_slots:
		s.context = "sell" if trade != null else "bag"
	if hint_label:
		hint_label.text = ("Clique direito ou duplo: vender · Shift: comparar com o equipado" if trade != null
			else "Clique direito ou duplo: usar/equipar · Shift: comparar com o equipado")


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
	if trade != null and is_instance_valid(trade):
		trade.trade_item(s.item_id)
		return
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
	gold_label.text = "◆ %d de ouro" % Game.gold
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
	var cls := Game.weapon_class()
	class_label.text = "%s · Ataque: %s — %s" % [Game.class_display_name(), ItemDB.CLASS_NAMES[cls], ItemDB.CLASS_HINT[cls]]


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
	use_btn.text = "Equipar" if ItemDB.is_equippable(id) else ("Comer" if t in ["food", "crop"] else ("Aprender" if t == "scroll" else "Usar"))
	drop_btn.disabled = false


# ================================================================ personagem
## Página esquerda: nome, experiência e atributos; página direita: estatísticas e habilidades.
## Uma coluna compacta (a aba é estreita): cartão do herói, atributos em blocos 2x2, estatísticas lado a lado.
func _build_character() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	char_left = col
	char_right = col
	return col


func _refresh_character() -> void:
	_clear(char_left)
	_clear(char_right)
	attr_buttons.clear()
	attr_values.clear()
	# ---- página esquerda: quem é o herói e os atributos
	var lv := char_left
	lv.add_child(_hero_card())
	lv.add_child(_gap(4))
	var pts := UITheme.ink_section("Atributos", 20)
	if Game.stat_points > 0:
		# aviso em quadro de tinta vermelha (texto a tinta, não um selo de cor cheia)
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UITheme._box(Color(UITheme.INK_RED, 0.1), UITheme.INK_RED, 1, 10, 10, 1))
		var n := Game.stat_points
		chip.add_child(UITheme.ink("%d %s para distribuir" % [n, "ponto" if n == 1 else "pontos"], 15, UITheme.INK_RED))
		pts.add_child(chip)
	lv.add_child(pts)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	lv.add_child(grid)
	for a in ATTR_ORDER:
		var info: Array = ATTR_INFO[a]
		var tile := PanelContainer.new()
		tile.add_theme_stylebox_override("panel", UITheme.ink_inset(10))
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.tooltip_text = "%s: %s" % [info[0], info[1]]
		grid.add_child(tile)
		var rh := HBoxContainer.new()
		rh.add_theme_constant_override("separation", 8)
		tile.add_child(rh)
		var strip := ColorRect.new()
		strip.color = info[2]
		strip.custom_minimum_size = Vector2(4, 0)
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rh.add_child(strip)
		var names := VBoxContainer.new()
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		names.add_theme_constant_override("separation", 0)
		names.mouse_filter = Control.MOUSE_FILTER_IGNORE
		names.add_child(UITheme.ink(info[0], 18, info[2], true))
		var bonus := int(Game.gear(a))
		var desc := UITheme.ink(info[1] + (" (+%d dos itens)" % bonus if bonus > 0 else ""), 13, UITheme.INK_DIM)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size.x = 150
		names.add_child(desc)
		rh.add_child(names)
		var val := UITheme.ink(str(Game.attr(a)), 26, UITheme.INK, true)
		val.custom_minimum_size.x = 32
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rh.add_child(val)
		attr_values[a] = val
		var b := UITheme.button("+", Game.spend_point.bind(a), 34)
		b.custom_minimum_size.y = 32
		b.tooltip_text = "Gastar 1 ponto em %s" % info[0]
		b.disabled = Game.stat_points <= 0
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rh.add_child(b)
		attr_buttons[a] = b
	lv.add_child(_gap(4))

	# ---- página direita: estatísticas agrupadas (cada número com ícone e dica) e habilidades
	var rv := char_right
	rv.add_child(UITheme.ink_section("Estatísticas", 20))
	var st := Game.stat_snapshot()
	var red := 1.0 - 50.0 / (50.0 + Game.defense() * 4.0)
	var pct := func(v: float) -> String: return "%d%%" % int(round(v * 100))
	var groups := HBoxContainer.new()
	groups.add_theme_constant_override("separation", 10)
	rv.add_child(groups)
	groups.add_child(_stat_group("Ataque", [
		["fury", Color(0.85, 0.3, 0.15), "Dano do ataque", "%.0f" % st.dmg,
			"Dano de cada golpe. Vem da arma, da Força (espada e arco), da Inteligência (cajado) e dos talentos."],
		["focus", Color(0.9, 0.7, 0.2), "Crítico", pct.call(st.crit), "Chance de um golpe causar dano dobrado. Agilidade e itens aumentam."],
		["boot", Color(0.35, 0.65, 0.3), "Velocidade", pct.call(st.speed), "Ritmo dos ataques e do passo. Agilidade e itens aumentam."],
		["orb", Color(0.35, 0.45, 0.95), "Poder mágico", "%.0f" % st.spell, "Força das magias e curas. Inteligência e itens aumentam."],
		["frost", Color(0.35, 0.7, 0.95), "Recarga reduzida", pct.call(st.cdr), "Quanto as recargas das habilidades ficam mais curtas."],
		["heal", Color(0.75, 0.15, 0.2), "Roubo de vida", pct.call(st.leech), "Parte do dano causado que volta como vida."]]))
	groups.add_child(_stat_group("Defesa", [
		["potion", Color(0.85, 0.15, 0.15), "Vida máxima", "%d" % st.hp, "Vitalidade, armaduras e o Mestre Orin aumentam."],
		["shield", Color(0.55, 0.45, 0.3), "Defesa", "%.1f" % st.def, "Soma das armaduras e da Vitalidade."],
		["ward", Color(0.3, 0.55, 0.9), "Redução de dano", pct.call(red), "Quanto do dano dos inimigos a sua Defesa absorve agora."],
		["potion", Color(0.2, 0.4, 0.95), "Mana máxima", "%d" % st.mp, "Gasta pelas magias. Inteligência aumenta."],
		["boot", Color(0.45, 0.7, 0.3), "Vigor máximo", "%d" % Game.max_stamina(), "Gasto ao correr e esquivar. Agilidade aumenta."]]))


## Cartão do herói no topo da ficha: emblema da classe, nome e nível, classe e título, experiência.
func _hero_card() -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.ink_inset(12))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	card.add_child(h)
	var row = Balance.tables.get_table("classes").get(Game.char_class, {})
	var em := ClassEmblem.for_class(row if row is Dictionary else {}, 64)
	em.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(em)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var name_l := UITheme.ink(_hero_name(), 24, UITheme.INK, true)
	name_l.clip_text = true
	v.add_child(name_l)
	# o resumo numa linha: nível, classe, arma, abates e, depois do registro, o rank na Guilda
	var parts := ["Nível %d" % Game.level, Game.class_display_name(), ItemDB.CLASS_NAMES[Game.weapon_class()],
		"%d abates" % Game.kills]
	if Game.quest_state("registro") == "done":
		parts.append("Rank %s (%d pts)" % [Game.rank(), Game.guild_points()])
	var sub := UITheme.ink(" · ".join(parts), 15, UITheme.INK_DIM)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(sub)
	v.add_child(_title_row())
	var xrow := HBoxContainer.new()
	xrow.add_child(UITheme.ink("Experiência", 14, UITheme.INK_DIM))
	xrow.add_child(UITheme.spacer())
	var xp_need := Game.xp_to_next()
	xrow.add_child(UITheme.ink("MÁX" if xp_need <= 0 else "%d / %d" % [Game.xp, xp_need], 14))
	v.add_child(xrow)
	var xpb := UITheme.ink_bar(UITheme.XP, 0, 12)
	xpb.max_value = maxi(xp_need, 1)
	xpb.value = Game.xp if xp_need > 0 else 1
	v.add_child(xpb)
	return card


## Quadro de estatísticas: título e uma linha por número (ícone, nome, valor). Passar o mouse explica de
## onde o número vem. `rows`: [desenho, cor, nome, valor, explicação].
func _stat_group(title: String, rows: Array) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.ink_inset(10))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	card.add_child(v)
	v.add_child(UITheme.ink(title, 17, UITheme.INK_RED, true))
	for r in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		line.mouse_filter = Control.MOUSE_FILTER_PASS
		line.tooltip_text = "%s: %s" % [r[2], r[4]]
		var ic := ItemSlot.new(24)
		ic.paper = true
		ic.icon_kind = r[0]
		ic.icon_color = r[1]
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(ic)
		var nl := UITheme.ink(r[2], 15, UITheme.INK_DIM)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(nl)
		var vl := UITheme.ink(r[3], 17, UITheme.INK, true)
		vl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(vl)
		v.add_child(line)
	return card


# ================================================================ talentos
func _build_talents() -> Control:
	talent_panel = TalentPanel.new()
	return talent_panel


## Linha "Título" da ficha: lista dos títulos liberados (o escolhido aparece acima do nome, para todos).
func _title_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var lbl := UITheme.ink("Título", 15, UITheme.INK_DIM)
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lbl)
	var pick := OptionButton.new()
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.add_item("Sem título")
	pick.set_item_metadata(0, "")
	var cur := TitleRules.current(Game.level, Game.flags)
	var ids := TitleRules.unlocked(Game.level, Game.flags)
	for id in ids:
		pick.add_item(TitleRules.label(id))
		var i := pick.item_count - 1
		pick.set_item_metadata(i, id)
		pick.set_item_tooltip(i, str(TitleRules.TITLES[id].desc))
		if id == cur:
			pick.select(i)
	pick.tooltip_text = "%d de %d títulos liberados. Sobem com o nível, o rank da guilda e os recordes." % [
		ids.size(), TitleRules.TITLES.size()]
	pick.item_selected.connect(func(i: int) -> void:
		var id := str(pick.get_item_metadata(i))
		if id != TitleRules.current(Game.level, Game.flags):
			Game.set_title(id))
	row.add_child(pick)
	return row


func _hero_name() -> String:
	var n: String = Game.hero_name()
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
			var hint := "○  Próxima: fale com %s" % who if StoryRules.rank_ge(Game.access_rank(), need) \
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
	var obj := UITheme.ink(StoryRules.objective(d, Balance.tables.get_table("regions")) if d.has("objective") else str(d.desc), 16)
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


# ================================================================ bestiário
var bestiary_panel: BestiaryPanel


func _build_bestiary() -> Control:
	bestiary_panel = BestiaryPanel.new()
	return bestiary_panel


func _refresh_bestiary() -> void:
	if bestiary_panel != null:
		bestiary_panel.tooltip = tooltip
		bestiary_panel.refresh()


# ================================================================ geral
## Uma abertura do livro: duas páginas lado a lado com a lombada livre no meio.
## Devolve [abertura, página esquerda, página direita].
# ================================================================ profissões
## Página esquerda: as sete profissões com nível e XP; página direita: onde se usa cada uma e quantas receitas
## você conhece (as de pergaminho contam só depois de aprendidas).
var prof_left: VBoxContainer
var prof_right: VBoxContainer
const PROF_WHERE := {"mining": "Veios de minério nos mapas (cobre no Vale, prata na Mina, mithril no Pico).",
	"woodcutting": "Árvores com a fita amarela (pinho no Vale, carvalho no Bosque...).",
	"farming": "A horta da vila: plantar e colher. Sementes melhores pedem nível.",
	"smithing": "Forja do Doran: espadas e peças de metal.",
	"leatherwork": "Bancada de Couraria, a leste do empório: arcos e peças de couro.",
	"alchemy": "Bancada da Pip, na botica: poções, essências, cajados e cetros.",
	"cooking": "Caldeirão da Horta: comidas com bônus."}


func _build_professions() -> Control:
	var cols := _spread(6)
	prof_left = cols[1]
	prof_right = cols[2]
	return cols[0]


## Ícone de cada profissão (um item que ela produz ou colhe).
const PROF_ICON := {"mining": "copper_ore", "woodcutting": "pine_log", "farming": "seed_carrot", "smithing": "iron_sword",
	"leatherwork": "leather_armor", "alchemy": "health_potion", "cooking": "bread"}


## Um cartão por profissão, em duas colunas: ícone, nome, nível grande, barra de XP com os números, onde se
## pratica e quantas receitas já sabe.
func _refresh_professions() -> void:
	if prof_left == null:
		return
	_clear(prof_left)
	_clear(prof_right)
	var bt := Balance.tables
	var s := Game.char_state()
	var profs: Array = CraftRules.professions(bt).keys()
	for i in profs.size():
		var prof: String = profs[i]
		var col := prof_left if i < int(ceil(profs.size() / 2.0)) else prof_right
		col.add_child(_prof_card(prof, bt, s))


func _prof_card(prof: String, bt: Variant, s: Variant) -> Control:
	var lv := Game.prof_level(prof)
	var need := CraftRules.xp_to_next(bt, lv)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.ink_inset(10))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	card.add_child(h)
	var ic := ItemSlot.new(58)
	ic.paper = true
	ic.model_icon = true
	ic.item_id = str(PROF_ICON.get(prof, ""))
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(ic)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var top := HBoxContainer.new()
	var n := UITheme.ink(Game.prof_name(prof), 19, UITheme.INK, true)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(n)
	top.add_child(UITheme.ink("Nível %d" % lv, 17, UITheme.INK_RED, true))
	v.add_child(top)
	var bar := UITheme.ink_bar(UITheme.XP, 0, 8)
	bar.max_value = maxi(need, 1)
	bar.value = Game.prof_xp(prof) if need > 0 else 1
	v.add_child(bar)
	var line := "%d / %d XP" % [Game.prof_xp(prof), need] if need > 0 else "Nível máximo"
	var st := str(CraftRules.professions(bt)[prof].get("station", ""))
	if st != "":
		var total := 0
		var known := 0
		for rid in CraftRules.station_recipes(bt, st):
			total += 1
			if CraftRules.knows(s, bt, rid):
				known += 1
		line += "  ·  receitas %d de %d" % [known, total]
	v.add_child(UITheme.ink(line, 13, UITheme.INK_DIM))
	var where := UITheme.ink(str(PROF_WHERE.get(prof, "")), 14)
	where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(where)
	return card


# ================================================================ ferramentas (aba da página esquerda)
## Resumo embaixo do boneco na aba Ferramentas: uma coluna por ferramenta (nome, nível, força e maestria), como os
## grupos de atributos da aba Equipamento. Os espaços ficam em volta do boneco (_build_inventory).
func _build_tool_side() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.visible = false
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	box.add_child(cols)
	for kind in ItemDB.TOOL_SLOTS:
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(info)
		tool_info[kind] = info
	return box


func _set_side_tab(t: String) -> void:
	side_tab = t
	if side_buttons.has(t):
		(side_buttons[t] as Button).button_pressed = true   # o grupo solta o outro (só "pressed" chama esta função)
	if gear_view and tools_view:
		gear_view.visible = t == "equip"
		tools_view.visible = t == "tools"
		for k in equip_slots:
			(equip_slots[k] as ItemSlot).visible = t == "equip"
		for k in tool_slots:
			(tool_slots[k] as ItemSlot).visible = t == "tools"
		_show_tool_in_hand()
	Sfx.play("click", 0.0)


## Na aba Ferramentas o boneco segura a picareta (ou o machado, sem picareta); na de Equipamento, a arma.
func _show_tool_in_hand() -> void:
	if hero_preview == null:
		return
	var want := ""
	if side_tab == "tools":
		for kind in ItemDB.TOOL_SLOTS:
			if str(Game.equipment.get(kind, "")) != "":
				want = str(Game.equipment[kind])
				break
	if hero_preview.weapon_override != want:
		hero_preview.weapon_override = want
		hero_preview.refresh()


func _refresh_tools() -> void:
	if tool_slots.is_empty():
		return
	_show_tool_in_hand()
	for kind in tool_slots:
		var id := str(Game.equipment.get(kind, ""))
		(tool_slots[kind] as ItemSlot).set_state(id)
		var info: VBoxContainer = tool_info[kind]
		_clear(info)
		var prof := "mining" if kind == "pickaxe" else "woodcutting"
		var lv := Game.prof_level(prof)
		info.add_child(UITheme.ink(ItemDB.SLOT_NAMES[kind], 18, UITheme.INK_RED, true))
		# mesma altura dos grupos de atributos: título + 3 linhas
		var rows: Array = []
		if id == "":
			rows.append(["Equipada", "nenhuma"])
			rows.append(["Nível · Força", "—"])
		else:
			var it := ItemDB.get_item(id)
			rows.append([str(it.name), ""])
			rows.append(["Nível · Força", "%d · %.1f" % [int(it.get("tier", 1)), float(it.get("power", 1.0))]])
		rows.append(["Maestria (%s)" % Game.prof_name(prof), "%d (+%d%%)" % [lv, roundi((GatherRules.mastery_mult(lv) - 1.0) * 100.0)]])
		for r in rows:
			var row := HBoxContainer.new()
			row.add_child(UITheme.ink(r[0], 14, UITheme.INK_DIM))
			row.add_child(UITheme.spacer())
			row.add_child(UITheme.ink(r[1], 15, UITheme.INK))
			info.add_child(row)


func _spread(separation: int) -> Array:
	var spread := HBoxContainer.new()
	spread.add_theme_constant_override("separation", int(BookLayout.COL_GAP))
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
	if mode == "inventory":
		_refresh_inventory()
		_refresh_tools()
		set_trade(trade if is_instance_valid(trade) else null)
		return
	_refresh_character()
	talent_panel.refresh()
	_refresh_quests()
	_refresh_professions()
	_refresh_bestiary()


func _close() -> void:
	closed.emit()
	queue_free()
