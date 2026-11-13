extends CanvasLayer
## HUD da Defesa da Cidade: painel de recursos (canto superior direito), faixa do dia/noite
## (topo) e a barra de construção (embaixo, só no modo construção).

var colony: Colony
var build: Node   # build_mode.gd

var root: Control
var status_label: RichTextLabel
var phase_label: Label
var phase_sub: Label
var build_panel: PanelContainer
var cards: Array = []          # [{"kind", "panel", "name", "cost"}]
var info_label: Label
var reason_label: Label
var _style_on: StyleBoxFlat
var _style_off: StyleBoxFlat
var _last_status := ""
var _reward_label: Label
var _reward_t := 0.0


func _ready() -> void:
	layer = 5
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)

	# --- painel de recursos
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.frame_box(Color(0.04, 0.035, 0.03, 0.8), Color(0.35, 0.28, 0.16), 12))
	# canto superior direito (o das missões, escondidas neste modo); o esquerdo é da placa do personagem
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -378
	panel.offset_right = -18
	panel.offset_top = 18
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	status_label = RichTextLabel.new()
	status_label.bbcode_enabled = true
	status_label.fit_content = true
	status_label.scroll_active = false
	status_label.custom_minimum_size = Vector2(330, 0)
	status_label.add_theme_font_size_override("normal_font_size", 16)
	status_label.add_theme_font_size_override("bold_font_size", 17)
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(status_label)

	# --- faixa de dia/noite
	var top := VBoxContainer.new()
	top.anchor_left = 0.5
	top.anchor_right = 0.5
	top.offset_left = -360
	top.offset_right = 360
	top.offset_top = 10
	top.add_theme_constant_override("separation", 0)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	phase_label = _outlined("", 28, UITheme.GOLD)
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(phase_label)
	phase_sub = _outlined("", 16, UITheme.TEXT)
	phase_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(phase_sub)

	# --- barra de construção
	_style_on = UITheme.frame_box(Color(0.16, 0.13, 0.07, 0.95), UITheme.GOLD, 8)
	_style_off = UITheme.frame_box(Color(0.06, 0.055, 0.05, 0.88), Color(0.3, 0.25, 0.18), 8)
	build_panel = PanelContainer.new()
	build_panel.add_theme_stylebox_override("panel", UITheme.frame_box(Color(0.03, 0.03, 0.03, 0.82), Color(0.35, 0.28, 0.16), 10))
	build_panel.anchor_left = 0.5
	build_panel.anchor_right = 0.5
	build_panel.anchor_top = 1.0
	build_panel.anchor_bottom = 1.0
	build_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(build_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_panel.add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	var kinds: Array = ["town_hall"] + ColonyData.ORDER + ["demolish"]
	for i in kinds.size():
		var kind: String = kinds[i]
		var key := ""
		if kind == "demolish":
			key = "X"
		elif kind != "town_hall":
			key = str((i) % 10)
		cards.append(_card(row, kind, key))
	info_label = UITheme.label("", 15, UITheme.TEXT)
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(info_label)
	reason_label = UITheme.label("", 15, UITheme.BAD)
	reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(reason_label)
	var keys := UITheme.label("Clique: construir · Roda/R: girar · 1–0: escolher · X: demolir · B/Esc: sair", 13, UITheme.DIM)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(keys)
	build_panel.visible = false

	# --- aviso de recompensa (cidade em grupo)
	_reward_label = _outlined("", 24, UITheme.GOLD)
	_reward_label.anchor_left = 0.5
	_reward_label.anchor_right = 0.5
	_reward_label.anchor_top = 0.3
	_reward_label.offset_left = -420
	_reward_label.offset_right = 420
	_reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reward_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reward_label.visible = false
	root.add_child(_reward_label)


## Cidade em grupo: recompensa da noite vencida no centro da tela por alguns segundos.
func show_reward(n: int, gold: int, xp: int, items: Array) -> void:
	var t := "Noite %d vencida!\n+%d ouro  ·  +%d XP" % [n, gold, xp]
	for id in items:
		if ItemDB.ITEMS.has(str(id)) and str(id) != "health_potion":
			t += "\nBaú: %s" % ItemDB.ITEMS[str(id)].name
	_reward_label.text = t
	_reward_label.visible = true
	_reward_label.modulate.a = 1.0
	_reward_t = 5.0


func _outlined(t: String, size: int, c: Color) -> Label:
	var l := UITheme.label(t, size, c)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _card(parent: Control, kind: String, key: String) -> Dictionary:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(92, 58)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var title := "Demolir" if kind == "demolish" else String(ColonyData.BUILDINGS[kind].name)
	var name_l := UITheme.label(("[%s] " % key if key != "" else "") + title, 13, UITheme.TEXT)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.custom_minimum_size.x = 84
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_l)
	var cost := 0 if kind == "demolish" else int(ColonyData.BUILDINGS[kind].cost)
	var cost_l := UITheme.label("+50%" if kind == "demolish" else ("grátis" if cost == 0 else "%d ouro" % cost), 13, UITheme.GOLD)
	cost_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cost_l)
	return {"kind": kind, "panel": p, "name": name_l, "cost": cost_l, "price": cost}


func _process(_delta: float) -> void:
	if _reward_t > 0.0:
		_reward_t -= _delta
		_reward_label.modulate.a = clampf(_reward_t, 0.0, 1.0)
		_reward_label.visible = _reward_t > 0.0
	if colony == null:
		return
	_update_status()
	_update_phase()
	_update_build()


func _update_status() -> void:
	var f := colony.forecast()
	var lines: Array[String] = []
	if colony.is_coop():
		lines.append("[b][color=#dcae52]Cidade em grupo — dia %d[/color][/b]  ·  %d jogador(es)" % [colony.day, colony.team_size])
		lines.append("Cofre  [b]%d[/b]   [color=%s](%+d/dia)[/color]" % [colony.get_gold(), _col(f.gold_net), f.gold_net])
	else:
		lines.append("[b][color=#dcae52]Cidade — dia %d[/color][/b]" % colony.day)
		lines.append("Ouro  [b]%d[/b]   [color=%s](%+d/dia)[/color]" % [Game.gold, _col(f.gold_net), f.gold_net])
	lines.append("Comida  [b]%d[/b]   [color=%s](%+d/dia)[/color]" % [colony.food, _col(f.food_net), f.food_net])
	lines.append("Moradores  [b]%d[/b] / %d   (%d trabalhando)" % [colony.citizens, colony.pop_cap(), f.employed])
	lines.append("Exército  [b]%d[/b] / %d   salários %d/dia" % [colony.soldier_count(), colony.army_cap(), f.salaries])
	lines.append("Imposto: %s   ·   [color=#9fc4ff]%s[/color] [G]" % [ColonyData.TAX_NAMES[colony.tax_level],
		("seguindo" if colony.is_coop() else "seguindo você") if colony.army_mode == "follow" else "defendendo"])
	if colony.is_coop():
		if f.upkeep > 0:
			lines.append("Manutenção  %d/dia" % f.upkeep)
		var mod := colony.next_mod if colony.phase == "day" else colony.night_mod
		if mod != "":
			var m: Dictionary = ColonyData.NIGHT_MODS[mod]
			lines.append("[color=#%s]%s %s[/color]: %s" % [m.color.to_html(false), "Esta noite:" if colony.phase == "night" else "Próxima noite:", m.name, m.desc])
		if colony.phase == "day" or colony.phase == "night":
			var rw := ColonyData.night_reward(colony.day)
			var chest := "  + baú" if colony.day % ColonyData.BOSS_EVERY == 0 else ""
			lines.append("[color=#a39d8c]Vencer a noite %d: +%d ouro, +%d XP%s[/color]" % [colony.day, rw.gold, rw.xp, chest])
	var s := "\n".join(lines)
	if s != _last_status:
		_last_status = s
		status_label.text = s


func _col(v: int) -> String:
	return "#7ff07f" if v > 0 else ("#ff7a6e" if v < 0 else "#a39d8c")


func _update_phase() -> void:
	match colony.phase:
		"setup":
			phase_label.text = "Funde a sua cidade"
			phase_label.add_theme_color_override("font_color", UITheme.GOLD)
			phase_sub.text = "Aperte B e posicione a Prefeitura na clareira central"
		"day":
			var t := int(ceil(colony.phase_t))
			phase_label.text = "Dia %d  ·  %d:%02d" % [colony.day, t / 60, t % 60]
			phase_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4) if t > 25 else Color(1.0, 0.55, 0.35))
			phase_sub.text = "Construa, recrute e saia para caçar — a noite traz monstros" if t > 25 else "A noite se aproxima! Prepare as defesas"
			if colony.is_coop() and colony.night_votes() > 0:
				phase_sub.text += "  ·  noite pedida %d/%d [N]" % [colony.night_votes(), colony.votes_needed()]
		"night":
			phase_label.text = "Noite %d  ·  %d monstros" % [colony.day, colony.wave_left()]
			phase_label.add_theme_color_override("font_color", Color(0.65, 0.7, 1.0))
			var names: Array[String] = []
			for d in colony.wave_dirs:
				names.append(Colony.DIR_NAMES[d])
			phase_sub.text = "Ataque vindo do " + " e do ".join(names) + "  ·  %d abatidos" % colony.night_kills
		"over":
			phase_label.text = "A cidade caiu"
			phase_label.add_theme_color_override("font_color", UITheme.BAD)
			phase_sub.text = "Sobreviveu a %d noite(s)" % maxi(0, colony.day - 1)
		_:
			phase_label.text = ""
			phase_sub.text = ""


func _update_build() -> void:
	var on: bool = build != null and build.active
	build_panel.visible = on
	if not on:
		return
	var no_hall: bool = colony.hall == null or not is_instance_valid(colony.hall)
	for c in cards:
		var kind: String = c.kind
		c.panel.visible = no_hall if kind == "town_hall" else not no_hall
		var sel: bool = build.selected == kind
		c.panel.add_theme_stylebox_override("panel", _style_on if sel else _style_off)
		var price := colony.cost_of(kind) if kind != "demolish" else 0
		var afford: bool = colony.get_gold() >= price
		if kind != "demolish" and kind != "town_hall" and int(c.price) != price:
			c.price = price
			c.cost.text = "%d ouro" % price
		c.cost.add_theme_color_override("font_color", UITheme.GOLD if afford else UITheme.BAD)
		c.name.add_theme_color_override("font_color", UITheme.TEXT if afford or sel else UITheme.DIM)
	var sz := build_panel.get_combined_minimum_size()
	build_panel.offset_left = -sz.x / 2.0
	build_panel.offset_right = sz.x / 2.0
	build_panel.offset_top = -sz.y - 170.0
	build_panel.offset_bottom = -170.0
	if build.selected == "demolish":
		info_label.text = "Demolir: devolve 50% do ouro gasto. A prefeitura não pode ser demolida."
	else:
		info_label.text = _describe(build.selected)
	reason_label.text = build.reason


func _describe(kind: String) -> String:
	var d := ColonyData.building(kind)
	if d.is_empty():
		return ""
	var extra := ""
	if ColonyData.is_tower(kind):
		extra = "  ·  Alcance %d · Dano %d" % [int(d.range), int(d.damage)]
	return "%s — %s%s" % [d.name, d.desc, extra]
