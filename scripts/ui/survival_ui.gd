extends Control
## Telas do Desafio da Horda: escolha de melhoria (mode = "levelup"), bênção de fim de rodada
## ("round") e resultados da partida ("results").
## No grupo, as cartas mostram o tempo que falta e quem já escolheu; quando o tempo acaba o
## servidor manda seguir e a carta é sorteada (auto_pick).

signal closed

var mode := "levelup"
var survival: Node
var choices: Array = []
var _cards: Array[Button] = []
var _lock := 0.4   # evita escolher sem querer com um clique de ataque
var _timer_bar: ProgressBar
var _timer_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := UITheme.centered_panel(self, 0.55 if mode != "results" else 0.7)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	match mode:
		"levelup":
			var who := "O grupo subiu" if survival.is_group() else "Subiu"
			v.add_child(_title("%s de nível! — Nv %d" % [who, survival.run_level], Color(0.5, 0.85, 1.0)))
			v.add_child(_sub("Escolha uma melhoria  (1 · 2 · 3)" + ("  ·  a horda espera todos escolherem" if survival.is_group() else "")))
			_build_cards(v)
			_build_timer(v)
		"round":
			v.add_child(_title("Rodada %d concluída!" % survival.round_num, UITheme.GOLD))
			v.add_child(_sub("Escolha uma bênção para a próxima rodada  (1 · 2 · 3)"))
			_build_cards(v)
			_build_timer(v)
			v.add_child(_sub("%d abates · Nv %d · %s" % [survival.kills, survival.run_level, _time(survival.elapsed)]))
			v.add_child(_sub("Dica: coma com [Q] durante a rodada — comidas do Caldeirão dão bônus."))
			var center := CenterContainer.new()
			var leave := UITheme.button("Retirar-se com as recompensas", _retreat, 340)
			center.add_child(leave)
			v.add_child(center)
		"results":
			_build_results(v)


func _title(t: String, c: Color) -> Label:
	var l := UITheme.label(t, 34, c)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	return l


func _sub(t: String) -> Label:
	var l := UITheme.label(t, 17, UITheme.DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func _time(sec: float) -> String:
	return "%d:%02d" % [int(sec) / 60, int(sec) % 60]


# ------------------------------------------------------------ cartas
func _build_cards(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(row)
	for i in choices.size():
		var info: Dictionary = survival.describe(choices[i])
		var c: Color = info.color
		var b := Button.new()
		b.custom_minimum_size = Vector2(290, 215)
		b.focus_mode = Control.FOCUS_ALL
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0.09, 0.08, 0.1, 0.97)
		normal.border_color = c.darkened(0.3)
		normal.set_border_width_all(2)
		normal.set_corner_radius_all(10)
		var hover := normal.duplicate() as StyleBoxFlat
		hover.bg_color = Color(0.16, 0.13, 0.12, 1.0)
		hover.border_color = c.lightened(0.2)
		hover.set_border_width_all(3)
		b.add_theme_stylebox_override("normal", normal)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("focus", hover)
		b.add_theme_stylebox_override("pressed", hover)
		b.pressed.connect(_pick.bind(i))
		row.add_child(b)
		_cards.append(b)

		var m := MarginContainer.new()
		m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side in ["left", "right", "top", "bottom"]:
			m.add_theme_constant_override("margin_" + side, 16)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(m)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 8)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_child(col)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 12)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(head)
		var ch: Dictionary = choices[i]
		var cur := 0
		if ch.type == "weapon":
			cur = survival.weapon_levels.get(ch.id, 0)
		elif ch.type == "passive":
			cur = survival.passive_levels.get(ch.id, 0)
		var icon := SkillIcon.new(64).setup(ch.type, ch.id, cur)
		icon.highlight = true
		head.add_child(icon)
		var titles := VBoxContainer.new()
		titles.add_theme_constant_override("separation", 2)
		titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(titles)
		var key := UITheme.label("[%d]" % (i + 1), 14, UITheme.DIM)
		titles.add_child(key)
		var name_l := UITheme.label(info.name, 22, c.lightened(0.25))
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		titles.add_child(name_l)
		var lvl := UITheme.label(info.level, 16, UITheme.GOLD)
		col.add_child(lvl)
		var desc := UITheme.label(info.desc, 17)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size.x = 230
		col.add_child(desc)
		for l in [key, name_l, lvl, desc]:
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tw := b.create_tween()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		b.modulate.a = 0.0
		tw.tween_interval(0.06 * i)
		tw.tween_property(b, "modulate:a", 1.0, 0.18)
	if not _cards.is_empty():
		_cards[0].grab_focus.call_deferred()


## Grupo: barra de tempo e quem ainda está escolhendo.
func _build_timer(parent: Control) -> void:
	if not survival.is_group():
		return
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	parent.add_child(box)
	_timer_label = _sub("")
	box.add_child(_timer_label)
	_timer_bar = UITheme.bar(Color(0.45, 0.78, 1.0) if mode == "levelup" else UITheme.GOLD, 600, 8)
	_timer_bar.custom_minimum_size = Vector2(600, 8)
	_timer_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_timer_bar)


func _process(delta: float) -> void:
	_lock = max(0.0, _lock - delta)
	if _timer_bar == null or survival == null:
		return
	var left: float = survival.lv_left if mode == "levelup" else survival.break_left
	var total: float = survival.lv_total if mode == "levelup" else survival.break_total
	_timer_bar.max_value = total
	_timer_bar.value = left
	var key := "lv_ready" if mode == "levelup" else "ready"
	var parts: Array[String] = []
	for pid in survival.team:
		var m: Dictionary = survival.team[pid]
		var ok: bool = m.get(key, false)
		parts.append(("✓ " if ok else "… ") + str(m.get("name", "?")))
	_timer_label.text = "⏱ %ds   ·   %s" % [int(ceil(left)), "   ".join(parts)]
	_timer_label.add_theme_color_override("font_color", Color(1, 0.55, 0.4) if left <= 5.0 else UITheme.DIM)


## Tempo esgotado no grupo: escolhe uma carta ao acaso e fecha.
func auto_pick() -> void:
	if is_queued_for_deletion() or choices.is_empty():
		return
	_lock = 0.0
	_pick(randi() % choices.size())


func _pick(i: int) -> void:
	if _lock > 0.0 or i >= choices.size() or is_queued_for_deletion():
		return
	survival.choose(choices[i])
	_close()


func _retreat() -> void:
	if _lock > 0.0:
		return
	survival.end_run("retreat")   # antes de fechar: assim a próxima rodada não começa
	_close()


# ------------------------------------------------------------ resultados
func _build_results(v: VBoxContainer) -> void:
	var titles := {"death": ["Você caiu na horda...", Color(0.95, 0.35, 0.3)],
		"retreat": ["Retirada vitoriosa!", UITheme.GOLD], "quit": ["Desafio abandonado", UITheme.DIM]}
	var t: Array = titles.get(survival.end_reason, titles.quit)
	v.add_child(_title(t[0], t[1]))
	if survival.new_record:
		var rec := UITheme.label("★ Novo recorde! ★", 22, Color(1, 0.85, 0.3))
		rec.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(rec)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 6)
	var rows := [
		["Rodadas concluídas", str(survival.rounds_cleared)],
		["Tempo", _time(survival.elapsed)],
		["Abates", str(survival.kills)],
		["Nível alcançado", str(survival.run_level)],
		["Caçadas concluídas", str(survival.hunts_won)],
		["Ouro coletado", "◆ %d" % survival.rewards.gold],
		["Sementes para a Horta", str(survival.seeds_won)],
		["XP de recompensa", "+%d XP" % survival.rewards.xp],
	]
	for r in rows:
		grid.add_child(UITheme.label(r[0], 19, UITheme.DIM))
		var val := UITheme.label(r[1], 19)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(val)
	var gc := CenterContainer.new()
	gc.add_child(grid)
	v.add_child(gc)
	if survival.end_reason == "death":
		v.add_child(_sub("Você não perde ouro no desafio."))
	var center := CenterContainer.new()
	var b := UITheme.button("Voltar à vila", _finish, 280)
	center.add_child(b)
	v.add_child(center)
	b.grab_focus.call_deferred()


func _finish() -> void:
	if _lock > 0.0:
		return
	_close()


func _close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if mode == "results" or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var idx: int = [KEY_1, KEY_2, KEY_3].find(event.physical_keycode)
	if idx >= 0:
		get_viewport().set_input_as_handled()
		_pick(idx)
