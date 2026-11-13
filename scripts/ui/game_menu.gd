extends Control
## Menu do jogo com abas: Inventário, Personagem e Missões.

signal closed

var start_tab := 0
var tabs: TabContainer
var item_list: ItemList
var details: Label
var use_btn: Button
var drop_btn: Button
var weapon_label: Label
var armor_label: Label
var gold_label: Label
var char_box: VBoxContainer
var quest_box: VBoxContainer
var _ids: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.5)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(980, 600)
	center.add_child(tabs)
	_build_inventory()
	_build_character()
	_build_quests()
	tabs.current_tab = start_tab
	Game.inventory_changed.connect(_refresh)
	Game.stats_changed.connect(_refresh)
	_refresh()


func _build_inventory() -> void:
	var h := HBoxContainer.new()
	h.name = "Inventário"
	h.add_theme_constant_override("separation", 20)
	tabs.add_child(h)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(left)
	left.add_child(UITheme.label("Mochila", 22, UITheme.GOLD))
	item_list = ItemList.new()
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_list.custom_minimum_size = Vector2(420, 380)
	item_list.item_selected.connect(_on_select)
	item_list.item_activated.connect(func(_i: int) -> void: _use())
	left.add_child(item_list)
	gold_label = UITheme.label("", 20, Color(1, 0.85, 0.35))
	left.add_child(gold_label)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(440, 0)
	right.add_theme_constant_override("separation", 10)
	h.add_child(right)
	right.add_child(UITheme.label("Equipamento", 22, UITheme.GOLD))
	var eq := GridContainer.new()
	eq.columns = 3
	eq.add_theme_constant_override("h_separation", 12)
	right.add_child(eq)
	eq.add_child(UITheme.label("Arma:", 18, UITheme.DIM))
	weapon_label = UITheme.label("")
	weapon_label.custom_minimum_size.x = 240
	eq.add_child(weapon_label)
	eq.add_child(UITheme.button("Remover", func() -> void: Game.unequip("weapon")))
	eq.add_child(UITheme.label("Armadura:", 18, UITheme.DIM))
	armor_label = UITheme.label("")
	eq.add_child(armor_label)
	eq.add_child(UITheme.button("Remover", func() -> void: Game.unequip("armor")))
	right.add_child(HSeparator.new())
	right.add_child(UITheme.label("Detalhes", 22, UITheme.GOLD))
	details = UITheme.label("Selecione um item.", 17)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.custom_minimum_size = Vector2(420, 150)
	right.add_child(details)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	use_btn = UITheme.button("Usar", _use, 140)
	drop_btn = UITheme.button("Descartar", _drop, 140)
	btns.add_child(use_btn)
	btns.add_child(drop_btn)
	right.add_child(btns)
	var foot := UITheme.label("[I] ou [Esc] fecha · duplo clique usa/equipa", 14, UITheme.DIM)
	right.add_child(foot)


func _build_character() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Personagem"
	tabs.add_child(scroll)
	char_box = VBoxContainer.new()
	char_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	char_box.add_theme_constant_override("separation", 8)
	scroll.add_child(char_box)


func _build_quests() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Missões"
	tabs.add_child(scroll)
	quest_box = VBoxContainer.new()
	quest_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quest_box.add_theme_constant_override("separation", 10)
	scroll.add_child(quest_box)


func _refresh() -> void:
	# inventário
	var prev := item_list.get_selected_items()
	item_list.clear()
	_ids.clear()
	for slot in Game.inventory:
		var it := ItemDB.get_item(slot.id)
		var txt: String = it.name
		if slot.qty > 1:
			txt += "  x%d" % slot.qty
		item_list.add_item(txt)
		item_list.set_item_custom_fg_color(item_list.item_count - 1, _type_color(it.type))
		_ids.append(slot.id)
	if prev.size() > 0 and prev[0] < item_list.item_count:
		item_list.select(prev[0])
		_on_select(prev[0])
	else:
		_on_select(-1)
	weapon_label.text = ItemDB.get_item(Game.equipment.weapon).get("name", "—") if Game.equipment.weapon != "" else "—"
	armor_label.text = ItemDB.get_item(Game.equipment.armor).get("name", "—") if Game.equipment.armor != "" else "—"
	gold_label.text = "◆ %d ouro" % Game.gold

	# personagem
	for c in char_box.get_children():
		c.queue_free()
	char_box.add_child(UITheme.label("Cavaleiro — Nível %d" % Game.level, 26, UITheme.GOLD))
	char_box.add_child(UITheme.label("XP: %d / %d" % [Game.xp, Game.xp_to_next()], 18))
	char_box.add_child(UITheme.label("Pontos disponíveis: %d" % Game.stat_points, 18,
		Color(1, 0.85, 0.3) if Game.stat_points > 0 else UITheme.DIM))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	char_box.add_child(grid)
	var names := {"str": ["Força", "+dano corpo a corpo"], "int": ["Inteligência", "+mana, +dano e cura mágicos"],
		"vit": ["Vitalidade", "+vida, +defesa, regeneração"], "agi": ["Agilidade", "+vigor, +velocidade, +crítico"]}
	for a in ["str", "int", "vit", "agi"]:
		grid.add_child(UITheme.label("%s: %d" % [names[a][0], Game.attributes[a]], 20))
		var b := UITheme.button("+", Game.spend_point.bind(a), 44)
		b.disabled = Game.stat_points <= 0
		grid.add_child(b)
		grid.add_child(UITheme.label(names[a][1], 15, UITheme.DIM))
	char_box.add_child(HSeparator.new())
	char_box.add_child(UITheme.label(
		"Vida máx: %d    Mana máx: %d    Vigor máx: %d\nDano físico: %.0f    Defesa: %.1f    Poder mágico: %.0f    Velocidade: %d%%" % [
		Game.max_hp(), Game.max_mp(), Game.max_stamina(), Game.melee_damage(), Game.defense(),
		Game.spell_power(), int(Game.speed_multiplier() * 100)], 17))
	char_box.add_child(HSeparator.new())
	char_box.add_child(UITheme.label("Magias", 22, UITheme.GOLD))
	for id in ItemDB.SPELLS:
		var sp: Dictionary = ItemDB.SPELLS[id]
		var known := Game.knows_spell(id)
		var txt := "[%s] %s — %d MP, recarga %.1fs\n      %s" % [sp.key, sp.name, sp.cost, sp.cooldown, sp.desc]
		if not known:
			txt += "  (aprende no nível %d)" % sp.level
		char_box.add_child(UITheme.label(txt, 16, UITheme.TEXT if known else UITheme.DIM))

	# missões
	for c in quest_box.get_children():
		c.queue_free()
	if Game.quests.is_empty():
		quest_box.add_child(UITheme.label("Nenhuma missão ainda. Fale com o Ancião Bram na vila.", 18, UITheme.DIM))
	for id in Game.quests:
		var q: Dictionary = Game.quests[id]
		var d: Dictionary = ItemDB.QUESTS[id]
		var st: String = {"active": "Em andamento", "ready": "Pronta para entregar", "done": "Concluída"}[q.state]
		quest_box.add_child(UITheme.label("%s  [%s]" % [d.name, st], 21,
			UITheme.DIM if q.state == "done" else UITheme.GOLD))
		var l := UITheme.label("%s\nProgresso: %d/%d   ·   Recompensa: %d ouro, %d XP" % [d.desc, q.progress, d.count, d.reward_gold, d.reward_xp], 16)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 900
		quest_box.add_child(l)


func _type_color(t: String) -> Color:
	match t:
		"weapon":
			return Color(1, 0.75, 0.5)
		"armor":
			return Color(0.7, 0.8, 1)
		"consumable":
			return Color(0.6, 1, 0.6)
		"food":
			return Color(1, 0.8, 0.4)
		"crop":
			return Color(1, 0.65, 0.35)
		"seed":
			return Color(0.75, 0.85, 0.5)
	return UITheme.TEXT


func _selected_id() -> String:
	var sel := item_list.get_selected_items()
	if sel.is_empty() or sel[0] >= _ids.size():
		return ""
	return _ids[sel[0]]


func _on_select(i: int) -> void:
	var id := _ids[i] if i >= 0 and i < _ids.size() else ""
	if id == "":
		details.text = "Selecione um item."
		use_btn.disabled = true
		drop_btn.disabled = true
		return
	details.text = ItemDB.item_summary(id)
	var t: String = ItemDB.get_item(id).type
	use_btn.disabled = t == "material" or t == "seed" or (t == "crop" and not Game.is_edible(id))
	use_btn.text = "Equipar" if t in ["weapon", "armor"] else ("Comer" if t in ["food", "crop"] else "Usar")
	drop_btn.disabled = false


func _use() -> void:
	var id := _selected_id()
	if id != "" and Game.use_item(id):
		Sfx.play("click", 0.0)


func _drop() -> void:
	var id := _selected_id()
	if id != "":
		Game.remove_item(id, 1)


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("inventory") \
			or event.is_action_pressed("character") or event.is_action_pressed("quest_log"):
		get_viewport().set_input_as_handled()
		_close()
