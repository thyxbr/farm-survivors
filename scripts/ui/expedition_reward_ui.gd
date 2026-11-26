extends Control
## Escolha de melhoria temporária da expedição (ExpeditionUpgrades): aparece ao limpar uma sala com recompensa.
## Modal (o mundo pausa o jogo enquanto está aberta) e obrigatória: Esc não fecha, não há botão de sair, e um
## clique de ataque logo depois da última morte não escolhe sem querer (_lock). Escolher fecha a tela; quem
## aplica é o modo da expedição (expedition.choose_reward). Se a tela some sem escolha, o modo reabre com as
## mesmas opções (elas ficam no ExpeditionRun), então não há como sortear de novo nem pular.

signal closed

## Ícone das cartas: o desenho das passivas da Horda (SkillIcon), com a cor da melhoria.
class RunIcon extends SkillIcon:
	var tint := Color.WHITE

	func color() -> Color:
		return tint


const LOCK := 0.6

var expedition: Node
var room := ""
var choices: Array = []
## Melhorias que o jogador já tem nesta run ({id: acúmulos}), para o nível da carta.
var taken := {}
var _cards: Array[Button] = []
var _lock := LOCK
var _hint: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := UITheme.centered_panel(self, 0.6)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var title := UITheme.outlined("Sala purificada: %s" % room, 32, UITheme.GOLD, 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := UITheme.label("Os ecos do pântano oferecem uma bênção para esta expedição. Escolha uma  (1 · 2 · 3)",
		17, UITheme.DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	_build_cards(v)
	if not taken.is_empty():
		v.add_child(_current_line())
	_hint = UITheme.label("As bênçãos valem só até o fim da expedição.", 15, UITheme.DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_hint)


func _build_cards(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(row)
	for i in choices.size():
		var id := str(choices[i])
		var info := ExpeditionUpgrades.info(id)
		var c: Color = info.get("color", UITheme.GOLD)
		var b := Button.new()
		b.custom_minimum_size = Vector2(270, 220)
		b.focus_mode = Control.FOCUS_ALL
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0.09, 0.08, 0.07, 0.97)
		normal.border_color = c.darkened(0.3)
		normal.set_border_width_all(2)
		normal.set_corner_radius_all(10)
		var hover := normal.duplicate() as StyleBoxFlat
		hover.bg_color = Color(0.16, 0.13, 0.1, 1.0)
		hover.border_color = c.lightened(0.2)
		hover.set_border_width_all(3)
		for s in ["normal", "hover", "focus", "pressed"]:
			b.add_theme_stylebox_override(s, normal if s == "normal" else hover)
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
		var icon := RunIcon.new(60)
		icon.tint = c
		icon.setup("passive", str(info.get("icon", "")), int(taken.get(id, 0)))
		icon.highlight = true
		head.add_child(icon)
		var titles := VBoxContainer.new()
		titles.add_theme_constant_override("separation", 2)
		titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(titles)
		var key := UITheme.label("[%d]" % (i + 1), 14, UITheme.DIM)
		titles.add_child(key)
		var name_l := UITheme.label(str(info.get("name", id)), 21, c.lightened(0.25))
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		titles.add_child(name_l)
		var lvl := UITheme.label(ExpeditionUpgrades.level_text(id, taken), 16, UITheme.GOLD)
		col.add_child(lvl)
		var desc := UITheme.label(str(info.get("desc", "")), 17)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size.x = 220
		col.add_child(desc)
		for l in [key, name_l, lvl, desc]:
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tw := b.create_tween()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		b.modulate.a = 0.0
		tw.tween_interval(0.08 * i)
		tw.tween_property(b, "modulate:a", 1.0, 0.2)
	if not _cards.is_empty():
		_cards[0].grab_focus.call_deferred()


## "Já com você: Fúria do Pântano x2 · Seiva Vital".
func _current_line() -> Label:
	var parts: Array[String] = []
	for id in taken:
		var n := int(taken[id])
		parts.append(ExpeditionUpgrades.display_name(str(id)) + (" x%d" % n if n > 1 else ""))
	var l := UITheme.label("Já com você: " + " · ".join(parts), 15, UITheme.TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _process(delta: float) -> void:
	_lock = maxf(0.0, _lock - delta)


## Escolhe a carta `i`. Também usada pelos testes (sem esperar o _lock: `force`).
func pick(i: int, force := false) -> bool:
	if force:
		_lock = 0.0
	return _pick(i)


func _pick(i: int) -> bool:
	if _lock > 0.0 or i < 0 or i >= choices.size() or is_queued_for_deletion() or expedition == null:
		return false
	if not expedition.choose_reward(str(choices[i])):
		return false
	_close()
	return true


func _close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		# obrigatória: Esc não fecha, só lembra
		get_viewport().set_input_as_handled()
		if _hint != null:
			_hint.text = "Escolha uma bênção para continuar a expedição."
			_hint.add_theme_color_override("font_color", Color(1, 0.75, 0.5))
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var idx: int = [KEY_1, KEY_2, KEY_3].find(event.physical_keycode)
	if idx >= 0:
		get_viewport().set_input_as_handled()
		_pick(idx)
