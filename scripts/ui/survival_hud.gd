extends CanvasLayer
## HUD do Desafio da Horda.
##   Esquerda: nível (do grupo, no multiplayer) com barra de XP grande e as habilidades da build
##             (armas e passivas com pontinhos de nível, bênçãos embaixo).
##   Centro:   rodada, tempo, abates, evento da rodada e a Caçada.
##   Direita:  o grupo (vivo / caído / escolhendo / pronto).
##   Faixa central quando a horda está congelada esperando o grupo escolher as cartas.

const UPG := preload("res://scripts/survival/upgrades.gd")
const EVT := preload("res://scripts/survival/horde_events.gd")

const LEVEL_BLUE := Color(0.45, 0.78, 1.0)

var survival: Node
var root: Control

# nível e build
var lvl_badge: Label
var lvl_title: Label
var xp_bar: ProgressBar
var xp_text: Label
var weapons_row: HBoxContainer
var passives_title: Label
var passives_row: HBoxContainer
var blessings_label: Label
var _build_key := ""

# rodada
var round_label: Label
var time_label: Label
var info_label: Label
var event_chip: PanelContainer
var event_label: Label
var hunt_box: VBoxContainer
var hunt_label: Label
var hunt_bar: ProgressBar

# grupo e espera
var team_panel: PanelContainer
var team_list: VBoxContainer
var _team_key := ""
var wait_panel: PanelContainer
var wait_title: Label
var wait_sub: Label
var wait_bar: ProgressBar

var _flash := 0.0
var _last_level := 1
var _last_round := 0


func _ready() -> void:
	layer = 6
	process_mode = Node.PROCESS_MODE_ALWAYS   # atualiza o nível atrás das cartas (jogo pausado)
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)
	_build_level()
	_build_round()
	_build_team()
	_build_wait()
	_ignore_all(root)


func _ignore_all(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_all(c)


func _panel(border: Color, margin := 12, alpha := 0.82) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UITheme._box(Color(0.05, 0.045, 0.05, alpha), border, 2, 10, margin, margin - 4)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 6
	p.add_theme_stylebox_override("panel", sb)
	return p


# ---------------------------------------------------------------- construção
func _build_level() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.position = Vector2(20, 96)
	root.add_child(col)

	var p := _panel(LEVEL_BLUE.darkened(0.35))
	col.add_child(p)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	p.add_child(row)
	var badge := PanelContainer.new()
	var bs := UITheme._box(Color(0.06, 0.12, 0.22, 0.95), LEVEL_BLUE, 3, 32, 0, 0)
	badge.add_theme_stylebox_override("panel", bs)
	badge.custom_minimum_size = Vector2(64, 64)
	lvl_badge = UITheme.heading("1", 30, Color(0.85, 0.95, 1.0))
	lvl_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lvl_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(lvl_badge)
	row.add_child(badge)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(info)
	var title_row := HBoxContainer.new()
	info.add_child(title_row)
	lvl_title = UITheme.label("NÍVEL", 17, LEVEL_BLUE)
	lvl_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(lvl_title)
	xp_text = UITheme.label("", 15, Color(0.8, 0.88, 0.98))
	title_row.add_child(xp_text)
	xp_bar = UITheme.bar(LEVEL_BLUE, 270, 16)
	xp_bar.custom_minimum_size = Vector2(270, 16)
	info.add_child(xp_bar)

	var sp := _panel(Color(0.5, 0.42, 0.3, 0.8), 10, 0.72)
	col.add_child(sp)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 6)
	sp.add_child(sv)
	sv.add_child(UITheme.outlined("ARMAS", 13, UITheme.GOLD, 3))
	weapons_row = HBoxContainer.new()
	weapons_row.add_theme_constant_override("separation", 6)
	sv.add_child(weapons_row)
	passives_title = UITheme.outlined("PASSIVAS", 13, UITheme.GOLD, 3)
	sv.add_child(passives_title)
	passives_row = HBoxContainer.new()
	passives_row.add_theme_constant_override("separation", 6)
	sv.add_child(passives_row)
	blessings_label = UITheme.outlined("", 14, Color(1, 0.88, 0.6), 3)
	blessings_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blessings_label.custom_minimum_size.x = 330
	sv.add_child(blessings_label)


func _build_round() -> void:
	var top := VBoxContainer.new()
	top.anchor_left = 0.5
	top.anchor_right = 0.5
	top.offset_left = -230
	top.offset_right = 230
	top.offset_top = 12
	top.add_theme_constant_override("separation", 6)
	root.add_child(top)
	var p := _panel(UITheme.GOLD_DIM)
	top.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	p.add_child(v)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	round_label = UITheme.heading("Rodada 1", 26, UITheme.GOLD)
	row.add_child(round_label)
	time_label = UITheme.heading("0:45", 26, Color(1, 0.96, 0.85))
	row.add_child(time_label)
	info_label = UITheme.label("", 16, Color(0.85, 0.82, 0.75))
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(info_label)

	event_chip = PanelContainer.new()
	event_chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top.add_child(event_chip)
	event_label = UITheme.outlined("", 18, Color.WHITE, 4)
	event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	event_chip.add_child(event_label)

	var hunt_chip := PanelContainer.new()
	hunt_chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hunt_chip.add_theme_stylebox_override("panel", UITheme._box(Color(0.03, 0.06, 0.08, 0.8), EVT.HUNT.color.darkened(0.4), 1, 8, 12, 4))
	top.add_child(hunt_chip)
	hunt_box = VBoxContainer.new()
	hunt_box.add_theme_constant_override("separation", 3)
	hunt_chip.add_child(hunt_box)
	hunt_label = UITheme.label("", 16, EVT.HUNT.color.lightened(0.2))
	hunt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hunt_box.add_child(hunt_label)
	hunt_bar = UITheme.bar(EVT.HUNT.color, 220, 8)
	hunt_bar.custom_minimum_size = Vector2(220, 8)
	hunt_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hunt_box.add_child(hunt_bar)


func _build_team() -> void:
	team_panel = _panel(Color(0.45, 0.6, 0.85, 0.8), 12, 0.75)
	team_panel.anchor_left = 1.0
	team_panel.anchor_right = 1.0
	team_panel.offset_left = -270
	team_panel.offset_right = -20
	team_panel.offset_top = 24
	team_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(team_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	team_panel.add_child(v)
	v.add_child(UITheme.outlined("GRUPO", 14, Color(0.7, 0.85, 1.0), 3))
	team_list = VBoxContainer.new()
	team_list.add_theme_constant_override("separation", 3)
	v.add_child(team_list)
	team_panel.visible = false


func _build_wait() -> void:
	wait_panel = _panel(LEVEL_BLUE, 18, 0.88)
	wait_panel.anchor_left = 0.5
	wait_panel.anchor_right = 0.5
	wait_panel.anchor_top = 0.5
	wait_panel.anchor_bottom = 0.5
	wait_panel.offset_left = -260
	wait_panel.offset_right = 260
	wait_panel.offset_top = -250
	wait_panel.offset_bottom = -250
	wait_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	wait_panel.grow_vertical = Control.GROW_DIRECTION_END
	root.add_child(wait_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	wait_panel.add_child(v)
	wait_title = UITheme.heading("Horda congelada", 24, LEVEL_BLUE)
	wait_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(wait_title)
	wait_sub = UITheme.label("", 16, UITheme.TEXT)
	wait_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wait_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(wait_sub)
	wait_bar = UITheme.bar(LEVEL_BLUE, 480, 8)
	wait_bar.custom_minimum_size = Vector2(480, 8)
	v.add_child(wait_bar)
	wait_panel.visible = false


# ---------------------------------------------------------------- atualização
func _process(delta: float) -> void:
	if survival == null:
		return
	var sv := survival
	# nível
	if sv.run_level != _last_level:
		_flash = 1.0 if sv.run_level > _last_level else 0.0
		_last_level = sv.run_level
	_flash = maxf(0.0, _flash - delta * 1.5)
	lvl_badge.text = str(sv.run_level)
	lvl_badge.pivot_offset = lvl_badge.size * 0.5
	lvl_badge.scale = Vector2.ONE * (1.0 + 0.25 * _flash)
	lvl_title.text = "NÍVEL DO GRUPO" if sv.is_group() else "NÍVEL"
	xp_bar.max_value = maxf(1.0, sv.xp_needed())
	xp_bar.value = sv.run_xp
	xp_text.text = "%d / %d" % [int(sv.run_xp), sv.xp_needed()]
	xp_bar.modulate = Color.WHITE.lerp(Color(1.6, 1.6, 1.6), _flash)
	_update_build()

	# rodada
	var t := int(ceil(sv.round_left))
	round_label.text = "Rodada %d" % sv.round_num
	if sv.phase == "break":
		time_label.text = "concluída"
		time_label.add_theme_color_override("font_color", Color(0.6, 1, 0.6))
	elif sv.boss_alive() and sv.round_left <= 0.0:
		time_label.text = "derrote o chefe!"
		time_label.add_theme_color_override("font_color", Color(1, 0.5, 0.35))
	else:
		time_label.text = "%d:%02d" % [t / 60, t % 60]
		var low: bool = sv.phase == "fight" and t <= 5
		time_label.add_theme_color_override("font_color", Color(1, 0.5, 0.35) if low else Color(1, 0.96, 0.85))
	var info := "%d abates  ·  %d inimigos" % [sv.kills, sv.alive_count()]
	if sv.phase == "break" and sv.waiting:
		info = "Aguardando o grupo escolher a bênção  ·  %ds" % int(ceil(sv.break_left))
	info_label.text = info
	if sv.round_num != _last_round:
		_last_round = sv.round_num
		if sv.event != "":
			_pulse(event_chip)
	event_chip.visible = sv.event != "" and sv.phase == "fight"
	if event_chip.visible:
		var ec := EVT.event_color(sv.event)
		event_chip.add_theme_stylebox_override("panel", UITheme._box(ec.darkened(0.72), ec, 2, 8, 12, 3))
		event_label.text = "⚠  " + EVT.event_name(sv.event)
		event_label.add_theme_color_override("font_color", ec.lightened(0.3))
	hunt_box.get_parent().visible = sv.hunt_target > 0 and (sv.phase == "fight" or sv.hunt_done)
	hunt_box.visible = hunt_box.get_parent().visible
	if hunt_box.visible:
		if sv.hunt_done:
			hunt_label.text = "Caçada concluída!  ✓"
			hunt_bar.max_value = 1
			hunt_bar.value = 1
		else:
			hunt_label.text = "Caçada: %d / %d abates" % [mini(sv.hunt_kills, sv.hunt_target), sv.hunt_target]
			hunt_bar.max_value = sv.hunt_target
			hunt_bar.value = sv.hunt_kills

	_update_team()
	_update_wait()


func _pulse(c: Control) -> void:
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(c, "scale", Vector2(1.25, 1.25), 0.15)
	tw.tween_property(c, "scale", Vector2.ONE, 0.35)


## Recria os ícones só quando a build muda.
func _update_build() -> void:
	var sv := survival
	var key := str(sv.weapon_levels) + str(sv.passive_levels) + str(sv.blessing_counts)
	if key == _build_key:
		return
	_build_key = key
	for c in weapons_row.get_children():
		c.queue_free()
	for c in passives_row.get_children():
		c.queue_free()
	for id in UPG.WEAPONS:
		if sv.weapon_levels.has(id):
			weapons_row.add_child(SkillIcon.new(54).setup("weapon", id, sv.weapon_levels[id]))
	for id in sv.passive_levels:
		passives_row.add_child(SkillIcon.new(46).setup("passive", id, sv.passive_levels[id]))
	passives_title.visible = not sv.passive_levels.is_empty()
	passives_row.visible = not sv.passive_levels.is_empty()
	var parts: Array[String] = []
	for id in sv.blessing_counts:
		var n: int = sv.blessing_counts[id]
		var nm: String = UPG.BLESSINGS[id].name.trim_prefix("Bênção da ").trim_prefix("Bênção do ")
		parts.append("✦ " + nm + (" ×%d" % n if n > 1 else ""))
	blessings_label.text = "   ".join(parts)
	blessings_label.visible = not parts.is_empty()


func _update_team() -> void:
	var sv := survival
	team_panel.visible = sv.is_group()
	if not team_panel.visible:
		return
	var key: String = str(sv.team) + str(sv.phase) + str(sv.frozen)
	if key == _team_key:
		return
	_team_key = key
	for c in team_list.get_children():
		c.queue_free()
	var me := multiplayer.get_unique_id()
	for pid in sv.team:
		var m: Dictionary = sv.team[pid]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var status := "●"
		var sc := Color(0.45, 0.95, 0.5)
		var note := ""
		if sv.frozen:
			var ok: bool = m.get("lv_ready", true)
			status = "✓" if ok else "…"
			sc = Color(0.45, 0.95, 0.5) if ok else Color(1, 0.85, 0.4)
			note = "pronto" if ok else "escolhendo"
		elif m.get("dead", false):
			status = "✝"
			sc = Color(1, 0.45, 0.4)
			note = "caído"
		elif sv.phase == "break":
			var ok: bool = m.get("ready", false)
			status = "✓" if ok else "…"
			sc = Color(0.45, 0.95, 0.5) if ok else Color(1, 0.85, 0.4)
			note = "pronto" if ok else "escolhendo"
		var s := UITheme.outlined(status, 17, sc, 3)
		s.custom_minimum_size.x = 18
		row.add_child(s)
		var mine := int(pid) == me
		var nm := UITheme.outlined(str(m.get("name", "?")) + ("  (você)" if mine else ""), 16,
			Color(0.75, 0.9, 1.0) if mine else UITheme.TEXT, 3)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		if note != "":
			row.add_child(UITheme.outlined(note, 13, sc.darkened(0.1), 3))
		team_list.add_child(row)
	_ignore_all(team_list)


## Faixa "horda congelada": aparece para quem já escolheu e espera o resto do grupo.
func _update_wait() -> void:
	var sv := survival
	var show: bool = sv.frozen and sv.world != null and sv.world.modal == null
	wait_panel.visible = show
	if not show:
		return
	var missing: Array[String] = []
	for pid in sv.team:
		if not sv.team[pid].get("lv_ready", true):
			missing.append(str(sv.team[pid].name))
	wait_title.text = "Nível %d — horda congelada" % sv.run_level
	if missing.is_empty():
		wait_sub.text = "Todos escolheram! Voltando à luta..."
	else:
		wait_sub.text = "Esperando %s escolher  ·  %ds" % [", ".join(missing), int(ceil(sv.lv_left))]
	wait_bar.max_value = sv.lv_total
	wait_bar.value = sv.lv_left
