extends CanvasLayer
## HUD do Desafio da Horda, enxuto:
## - topo: rodada e tempo, nível (do grupo, no multiplayer) com barra de XP fina, abates/inimigos, o evento
##   da rodada, a Caçada e, com a horda congelada, quem ainda está escolhendo a carta;
## - canto superior direito: build em ícones (armas com nível, passivas, bênçãos) e combos do grupo;
## - esquerda: quadro do grupo (vida, caído, escolhendo/pronto) no multiplayer;
## - Tab (segurar): placar com build, dano, abates, quedas e combos de cada jogador.

const UPG := preload("res://scripts/survival/upgrades.gd")
const EVT := preload("res://scripts/survival/horde_events.gd")
const LEVEL_BLUE := Color(0.45, 0.78, 1.0)
const SCOREBOARD := preload("res://scripts/ui/horde_scoreboard.gd")

var survival: Node
var root: Control
var xp_bar: ProgressBar
var lvl_label: Label
var round_label: Label
var info_label: Label
var event_label: Label
var hunt_line: HBoxContainer
var hunt_label: Label
var hunt_bar: ProgressBar
var wait_line: VBoxContainer
var wait_label: Label
var wait_bar: ProgressBar
var weapon_row: HBoxContainer
var extra_row: HBoxContainer
var combo_row: HBoxContainer
var party_box: VBoxContainer
var scoreboard: CanvasLayer
var _build_sig := ""
var _combo_sig := ""
var _party_sig := ""
var _combo_icons := {}   # combo -> HordeIcon
var _party_rows := {}    # pid -> {"bar", "lv", "state", "name"}


func _ready() -> void:
	layer = 6
	process_mode = Node.PROCESS_MODE_ALWAYS   # atualiza o nível atrás das cartas (jogo pausado)
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)

	# ---- topo central: rodada · tempo / nível + XP / maldição
	var top := VBoxContainer.new()
	top.anchor_left = 0.5
	top.anchor_right = 0.5
	top.offset_left = -220
	top.offset_right = 220
	top.offset_top = 10
	top.add_theme_constant_override("separation", 2)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	round_label = UITheme.outlined("", 20, UITheme.GOLD, 5)
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(round_label)
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 8)
	top.add_child(line)
	lvl_label = UITheme.outlined("", 13, Color(0.6, 0.85, 1.0), 4)
	line.add_child(lvl_label)
	xp_bar = UITheme.bar(Color(0.3, 0.65, 1.0), 170, 5)
	xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(xp_bar)
	info_label = UITheme.outlined("", 13, Color(0.85, 0.83, 0.76), 4)
	line.add_child(info_label)
	event_label = UITheme.outlined("", 12, Color(1, 0.55, 0.45), 4)
	event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(event_label)
	hunt_line = HBoxContainer.new()
	hunt_line.alignment = BoxContainer.ALIGNMENT_CENTER
	hunt_line.add_theme_constant_override("separation", 6)
	top.add_child(hunt_line)
	hunt_label = UITheme.outlined("", 12, EVT.HUNT.color, 4)
	hunt_line.add_child(hunt_label)
	hunt_bar = UITheme.bar(EVT.HUNT.color, 110, 4)
	hunt_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hunt_line.add_child(hunt_bar)
	# horda congelada: quem ainda escolhe a carta e quanto tempo falta
	wait_line = VBoxContainer.new()
	wait_line.add_theme_constant_override("separation", 3)
	wait_line.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(wait_line)
	wait_label = UITheme.outlined("", 14, LEVEL_BLUE, 4)
	wait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wait_line.add_child(wait_label)
	wait_bar = UITheme.bar(LEVEL_BLUE, 260, 4)
	wait_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wait_line.add_child(wait_bar)
	for c in [round_label, lvl_label, xp_bar, info_label, event_label, line, hunt_line, hunt_label, hunt_bar,
			wait_line, wait_label, wait_bar]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# ---- canto superior direito: build e combos
	var build := VBoxContainer.new()
	build.anchor_left = 1.0
	build.anchor_right = 1.0
	build.offset_left = -340
	build.offset_right = -18
	build.offset_top = 18
	build.add_theme_constant_override("separation", 9)
	build.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(build)
	weapon_row = _row(build, 8)
	extra_row = _row(build, 7)
	combo_row = _row(build, 8)

	# ---- esquerda: quadro do grupo (abaixo da placa do personagem)
	party_box = VBoxContainer.new()
	party_box.position = Vector2(16, 66)
	party_box.add_theme_constant_override("separation", 5)
	party_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(party_box)

	var hint := UITheme.outlined("[Tab] placar do grupo", 12, Color(0.8, 0.76, 0.66, 0.55), 3)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.anchor_left = 1.0
	hint.anchor_right = 1.0
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = -314
	hint.offset_right = -14
	hint.offset_top = -42
	hint.offset_bottom = -24
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hint)

	scoreboard = SCOREBOARD.new()
	scoreboard.survival = survival
	add_child(scoreboard)


func _row(parent: Control, sep: int) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.alignment = BoxContainer.ALIGNMENT_END
	r.add_theme_constant_override("separation", sep)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


func _process(_delta: float) -> void:
	if survival == null:
		return
	xp_bar.max_value = survival.xp_needed()
	xp_bar.value = survival.run_xp
	lvl_label.text = ("Nv do grupo %d" if survival.is_group() else "Nv %d") % survival.run_level
	var t := int(ceil(survival.round_left))
	if survival.phase == "break":
		round_label.text = "Rodada %d concluída" % survival.round_num
		if survival.waiting:
			round_label.text += "  ·  aguardando o grupo  ·  %ds" % int(ceil(survival.break_left))
	elif survival.boss_alive() and survival.round_left <= 0.0:
		round_label.text = "Rodada %d  ·  derrote o chefe!" % survival.round_num
	else:
		round_label.text = "Rodada %d  ·  %d:%02d" % [survival.round_num, t / 60, t % 60]
	info_label.text = "☠ %d  ·  %d vivos" % [survival.kills, survival.alive_count()]
	event_label.visible = survival.event != "" and survival.phase == "fight"
	if event_label.visible:
		event_label.text = "⚠ %s — %s" % [EVT.event_name(survival.event), EVT.event_desc(survival.event)]
		event_label.add_theme_color_override("font_color", EVT.event_color(survival.event))
	hunt_line.visible = survival.hunt_target > 0 and (survival.phase == "fight" or survival.hunt_done)
	if hunt_line.visible:
		hunt_bar.visible = not survival.hunt_done
		if survival.hunt_done:
			hunt_label.text = "Caçada concluída!"
		else:
			hunt_label.text = "Caçada %d/%d" % [mini(survival.hunt_kills, survival.hunt_target), survival.hunt_target]
			hunt_bar.max_value = survival.hunt_target
			hunt_bar.value = survival.hunt_kills
	_update_wait()
	_update_build()
	_update_combos()
	_update_party()


## Horda congelada (grupo subiu de nível) e você já escolheu: mostra quem falta e o tempo.
func _update_wait() -> void:
	wait_line.visible = survival.frozen and survival.world != null and survival.world.modal == null
	if not wait_line.visible:
		return
	var missing: Array[String] = []
	for pid in survival.team:
		if not survival.team[pid].get("lv_ready", true):
			missing.append(str(survival.team[pid].name))
	if missing.is_empty():
		wait_label.text = "Nível %d — todos escolheram!" % survival.run_level
	else:
		wait_label.text = "Nível %d — horda congelada · esperando %s · %ds" % [survival.run_level,
			", ".join(missing), int(ceil(survival.lv_left))]
	wait_bar.max_value = survival.lv_total
	wait_bar.value = survival.lv_left


# ---------------------------------------------------------------- build
func _update_build() -> void:
	var sig := "%s|%s|%s" % [survival.weapon_levels, survival.passive_levels, survival.blessing_counts]
	if sig == _build_sig:
		return
	_build_sig = sig
	HordeIcon.fill_build(weapon_row, extra_row, survival.weapon_levels, survival.passive_levels, survival.blessing_counts, 34, 24)


# ---------------------------------------------------------------- combos
func _update_combos() -> void:
	var active: Dictionary = survival.active_combos
	var sig := ",".join(active.keys())
	if sig != _combo_sig:
		_combo_sig = sig
		for c in combo_row.get_children():
			c.queue_free()
		_combo_icons.clear()
		for cid in active:
			var ic := HordeIcon.new(26, "combo", cid)
			combo_row.add_child(ic)
			_combo_icons[cid] = ic
	for cid in _combo_icons:
		var near: bool = active.get(cid, {}).get("near", false)
		var ic: HordeIcon = _combo_icons[cid]
		if ic.glow != near:
			ic.dim = not near
			ic.glow = near
			ic.queue_redraw()


# ---------------------------------------------------------------- grupo
func _update_party() -> void:
	if not survival.is_group():
		party_box.visible = false
		return
	party_box.visible = true
	var me: int = multiplayer.get_unique_id()
	var ids: Array = survival.team.keys().filter(func(x) -> bool: return x != me)
	var sig := str(ids)
	if sig != _party_sig:
		_party_sig = sig
		for c in party_box.get_children():
			c.queue_free()
		_party_rows.clear()
		for pid in ids:
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 6)
			h.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var state := UITheme.outlined("", 12, UITheme.TEXT, 3)
			state.custom_minimum_size.x = 12
			h.add_child(state)
			var nm := UITheme.outlined(str(survival.team[pid].get("name", "?")), 13, Color(0.75, 0.9, 1.0), 3)
			nm.custom_minimum_size.x = 86
			nm.clip_text = true
			h.add_child(nm)
			var bar := UITheme.bar(UITheme.HP, 70, 4)
			bar.max_value = 1.0
			bar.step = 0.0
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(bar)
			var lv := UITheme.outlined("", 11, Color(0.8, 0.78, 0.7), 3)
			h.add_child(lv)
			for c in h.get_children():
				c.mouse_filter = Control.MOUSE_FILTER_IGNORE
			party_box.add_child(h)
			_party_rows[pid] = {"bar": bar, "lv": lv, "state": state, "name": nm}
	var partners := {}
	for c in survival.active_combos.values():
		if c.near:
			partners[c.partner] = true
	for pid in _party_rows:
		if not survival.team.has(pid):
			continue
		var m: Dictionary = survival.team[pid]
		var row: Dictionary = _party_rows[pid]
		var b: Dictionary = m.get("build", {})
		var dead: bool = m.get("dead", false)
		row.bar.value = 0.0 if dead else float(b.get("hp", 1.0))
		var st: Label = row.state
		var note := ""
		if survival.frozen or survival.phase == "break":
			var ok: bool = m.get("lv_ready", true) if survival.frozen else m.get("ready", false)
			st.text = "✓" if ok else "…"
			st.add_theme_color_override("font_color", UITheme.GOOD if ok else Color(1, 0.85, 0.4))
			note = "pronto" if ok else "escolhendo"
		elif dead:
			st.text = "☠"
			st.add_theme_color_override("font_color", UITheme.BAD)
			note = "caído"
		else:
			# ◆ = combo ativo com este colega (está perto)
			st.text = "◆" if partners.has(str(m.get("name", ""))) else ""
			st.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
		row.lv.text = note
		row.name.modulate.a = 0.5 if dead else 1.0
