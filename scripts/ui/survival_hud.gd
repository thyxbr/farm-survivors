extends CanvasLayer
## HUD do Desafio da Horda: barra de XP da partida, rodada/tempo/abates e armas equipadas.

const UPG := preload("res://scripts/survival/upgrades.gd")

var survival: Node
var xp_bar: ProgressBar
var lvl_label: Label
var round_label: Label
var info_label: Label
var gear_label: Label
var team_label: Label


func _ready() -> void:
	layer = 6
	process_mode = Node.PROCESS_MODE_ALWAYS   # atualiza o nível atrás das cartas (jogo pausado)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)

	xp_bar = UITheme.bar(Color(0.25, 0.6, 1.0), 10, 12)
	xp_bar.anchor_right = 1.0
	xp_bar.offset_bottom = 12
	xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(xp_bar)

	lvl_label = _outlined("", 20, Color(0.6, 0.85, 1.0))
	lvl_label.anchor_left = 1.0
	lvl_label.anchor_right = 1.0
	lvl_label.offset_left = -140
	lvl_label.offset_right = -20
	lvl_label.offset_top = 14
	lvl_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(lvl_label)

	var top := VBoxContainer.new()
	top.anchor_left = 0.5
	top.anchor_right = 0.5
	top.offset_left = -300
	top.offset_right = 300
	top.offset_top = 16
	top.add_theme_constant_override("separation", 0)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	round_label = _outlined("", 30, UITheme.GOLD)
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(round_label)
	info_label = _outlined("", 17, Color(0.9, 0.88, 0.8))
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(info_label)
	team_label = _outlined("", 16, Color(0.75, 0.9, 1.0))
	team_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(team_label)

	gear_label = _outlined("", 16, Color(0.9, 0.88, 0.8))
	gear_label.anchor_left = 1.0
	gear_label.anchor_right = 1.0
	gear_label.offset_left = -300
	gear_label.offset_right = -20
	gear_label.offset_top = 48
	gear_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(gear_label)


func _outlined(t: String, size: int, c: Color) -> Label:
	var l := UITheme.label(t, size, c)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(_delta: float) -> void:
	if survival == null:
		return
	xp_bar.max_value = survival.xp_needed()
	xp_bar.value = survival.run_xp
	lvl_label.text = "Nv %d" % survival.run_level
	var t := int(ceil(survival.round_left))
	if survival.phase == "break":
		round_label.text = "Rodada %d concluída" % survival.round_num
		if survival.waiting:
			round_label.text += "  ·  aguardando o grupo"
	elif survival.boss_alive() and survival.round_left <= 0.0:
		round_label.text = "Rodada %d — derrote o chefe!" % survival.round_num
	else:
		round_label.text = "Rodada %d  ·  %d:%02d" % [survival.round_num, t / 60, t % 60]
	info_label.text = "%d abates  ·  %d inimigos" % [survival.kills, survival.alive_count()]
	team_label.text = _team_text()
	var lines: Array[String] = []
	for id in survival.weapon_levels:
		lines.append("%s  Nv %d" % [UPG.WEAPONS[id].name, survival.weapon_levels[id]])
	for id in survival.passive_levels:
		lines.append("%s  Nv %d" % [UPG.PASSIVES[id].name, survival.passive_levels[id]])
	for id in survival.blessing_counts:
		var n: int = survival.blessing_counts[id]
		lines.append(UPG.BLESSINGS[id].name + (" ×%d" % n if n > 1 else ""))
	gear_label.text = "\n".join(lines)


## Multiplayer: "Grupo: Ana · Beto (caído) · Caio ✓" (✓ = já escolheu a bênção).
func _team_text() -> String:
	if survival.role != "client" or survival.team.size() <= 1:
		return ""
	var parts: Array[String] = []
	for pid in survival.team:
		var m: Dictionary = survival.team[pid]
		var s := str(m.get("name", "?"))
		if m.get("dead", false):
			s += " (caído)"
		elif survival.phase == "break" and m.get("ready", false):
			s += " ✓"
		parts.append(s)
	return "Grupo: " + "  ·  ".join(parts)
