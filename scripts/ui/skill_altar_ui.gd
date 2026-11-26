extends Control
## Escolha do Altar da Deusa (expedição roguelite): 1 entre até 3 habilidades do kit do personagem
## (ExpeditionSkills). Modal (o mundo pausa o jogo enquanto está aberta). Escolher fecha a tela; quem aplica é o
## modo da expedição (expedition.choose_skill), que põe a habilidade no kit temporário da run.
## Esc fecha sem escolher: o altar continua desperto e, ao voltar, mostra as mesmas opções (elas ficam no
## ExpeditionRun.pending_altar), então não dá para sortear de novo.

signal closed

const LOCK := 0.35
const COLOR := Color(0.55, 1.0, 0.85)

var expedition: Node
var room := ""
var choices: Array = []
## Habilidades que o jogador já levou nesta run (para a linha "Já com você").
var owned: Array = []
var _cards: Array[Button] = []
var _lock := LOCK


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := UITheme.centered_panel(self, 0.6)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var title := UITheme.outlined("Altar da Deusa", 32, COLOR, 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := UITheme.label("A luz da Deusa atravessa a névoa do pântano. Escolha uma habilidade  (1 · 2 · 3)",
		17, UITheme.DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	_build_cards(v)
	if not owned.is_empty():
		var names: Array[String] = []
		for id in owned:
			names.append(str(ItemDB.ABILITIES.get(id, {}).get("name", id)))
		var l := UITheme.label("Já com você: " + " · ".join(names), 15, UITheme.TEXT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
	var hint := UITheme.label("A habilidade vale só até o fim desta expedição.  Esc: decidir depois", 15, UITheme.DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)


func _build_cards(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(row)
	for i in choices.size():
		var id := str(choices[i])
		var a: Dictionary = ItemDB.ABILITIES.get(id, {})
		var b := Button.new()
		b.custom_minimum_size = Vector2(330, 320)
		b.focus_mode = Control.FOCUS_ALL
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0.06, 0.09, 0.08, 0.97)
		normal.border_color = COLOR.darkened(0.45)
		normal.set_border_width_all(2)
		normal.set_corner_radius_all(10)
		var hover := normal.duplicate() as StyleBoxFlat
		hover.bg_color = Color(0.1, 0.15, 0.13, 1.0)
		hover.border_color = COLOR
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
		var icon := ItemSlot.new(60)
		icon.icon_tex = ItemSlot.skill_art(id)
		icon.icon_kind = str(a.get("icon", ""))
		icon.border_override = COLOR
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(icon)
		var titles := VBoxContainer.new()
		titles.add_theme_constant_override("separation", 2)
		titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(titles)
		var key := UITheme.label("[%d]" % (i + 1), 14, UITheme.DIM)
		titles.add_child(key)
		var name_l := UITheme.label(str(a.get("name", id)), 21, COLOR.lightened(0.2))
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		titles.add_child(name_l)
		var meta := UITheme.label(meta_text(id), 15, UITheme.GOLD)
		meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(meta)
		var desc := UITheme.label(str(a.get("desc", "")), 14)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size.x = 290
		desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		desc.max_lines_visible = 9
		b.tooltip_text = str(a.get("desc", ""))   # descrição inteira no mouse (as muito longas cortam no card)
		col.add_child(desc)
		for l in [key, name_l, meta, desc]:
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tw := b.create_tween()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		b.modulate.a = 0.0
		tw.tween_interval(0.08 * i)
		tw.tween_property(b, "modulate:a", 1.0, 0.2)
	if not _cards.is_empty():
		_cards[0].grab_focus.call_deferred()


## "Recarga 9 s · 20 de mana" (a recarga do ItemDB.cooldown_of, antes dos bônus).
static func meta_text(id: String) -> String:
	var a: Dictionary = ItemDB.ABILITIES.get(id, {})
	var parts: Array[String] = ["Recarga %s s" % str(snappedf(ItemDB.cooldown_of(id), 0.1)).replace(".", ",")]
	if int(a.get("cost", 0)) > 0:
		parts.append("%d de mana" % int(a.cost))
	return " · ".join(parts)


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
	if not expedition.choose_skill(str(choices[i])):
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
		get_viewport().set_input_as_handled()
		_close()   # decidir depois: as opções ficam guardadas no altar
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var idx: int = [KEY_1, KEY_2, KEY_3].find(event.physical_keycode)
	if idx >= 0:
		get_viewport().set_input_as_handled()
		_pick(idx)
