extends Control
## Caixa de diálogo no estilo das visual novels e dos animes: faixas de cinema em cima e embaixo, caixa larga
## no rodapé com a plaquinha do nome na cor de quem fala, texto digitado, seta ▼ pulando quando dá para
## seguir e escolhas empilhadas à direita (teclas 1–4 também escolhem).
## Página: {"text", "speaker"?, "mood"?: "shout"|"whisper"|"think", "fx"?: "boom"|"sparkle"|"end",
## "on_show"?: Callable, "choices"?: [{"text", "action"?: Callable, "pages"?: Array}]} (ver StoryDialogue).
## Escolha com "pages": as páginas entram logo depois desta e o diálogo segue; sem: fecha e chama action.

signal closed

const CPS := 55.0           # letras por segundo
const BOX_W := 1060.0
const BOX_H := 196.0
const BAR_H := 56.0         # faixas de cinema

var speaker := ""
var pages: Array = []
var index := 0
## Mundo que abriu o diálogo (para o cartão do fim da história); pode ficar nulo.
var world: Node = null
var text_label: RichTextLabel
var name_label: Label
var name_plate: PanelContainer
var box: PanelContainer
var choices_box: VBoxContainer
var hint: Label
var arrow: Label
var _chars := 0.0
var _speed := CPS
var _t := 0.0
var _shake := 0.0
var _box_pos := Vector2.ZERO
var _flash: ColorRect
var _bars: Array[ColorRect] = []
var _end_card := false
var _box_style: StyleBoxFlat
var _plate_style: StyleBoxFlat


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	# sombra subindo do rodapé (o texto lê bem sobre qualquer cenário)
	var shade := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill_from = Vector2(0.5, 1.0)
	gt.fill_to = Vector2(0.5, 0.45)
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.7))
	g.set_color(1, Color(0, 0, 0, 0.0))
	gt.gradient = g
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	# faixas de cinema (entram de fora da tela)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 0.92)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_left = 0.0
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0
		bar.anchor_bottom = 0.0 if top else 1.0
		bar.offset_top = -BAR_H if top else 0.0
		bar.offset_bottom = 0.0 if top else BAR_H
		add_child(bar)
		_bars.append(bar)
	# caixa
	box = PanelContainer.new()
	_box_style = StyleBoxFlat.new()
	_box_style.bg_color = Color(0.05, 0.045, 0.06, 0.9)
	_box_style.border_color = UITheme.GOLD_DIM
	_box_style.set_border_width_all(2)
	_box_style.border_width_left = 6
	_box_style.set_corner_radius_all(10)
	_box_style.content_margin_left = 30
	_box_style.content_margin_right = 30
	_box_style.content_margin_top = 26
	_box_style.content_margin_bottom = 14
	_box_style.shadow_color = Color(0, 0, 0, 0.5)
	_box_style.shadow_size = 10
	box.add_theme_stylebox_override("panel", _box_style)
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = -BOX_W / 2.0
	box.offset_right = BOX_W / 2.0
	box.offset_top = -BOX_H - 34
	box.offset_bottom = -34
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(v)
	text_label = RichTextLabel.new()
	text_label.fit_content = true
	text_label.scroll_active = false
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_label.custom_minimum_size = Vector2(BOX_W - 70, 110)
	text_label.add_theme_font_size_override("normal_font_size", 22)
	text_label.add_theme_color_override("default_color", UITheme.TEXT)
	text_label.add_theme_constant_override("line_separation", 4)
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(text_label)
	var foot := HBoxContainer.new()
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_theme_constant_override("separation", 10)
	v.add_child(foot)
	hint = UITheme.label("E / Espaço / Clique — continuar   ·   Esc — sair", 13, UITheme.DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	foot.add_child(hint)
	arrow = UITheme.outlined("▼", 18, UITheme.GOLD, 3)
	foot.add_child(arrow)
	# plaquinha do nome (por cima da borda da caixa, à esquerda)
	name_plate = PanelContainer.new()
	_plate_style = StyleBoxFlat.new()
	_plate_style.bg_color = UITheme.GOLD
	_plate_style.set_corner_radius_all(6)
	_plate_style.skew = Vector2(-0.25, 0)
	_plate_style.content_margin_left = 22
	_plate_style.content_margin_right = 22
	_plate_style.content_margin_top = 4
	_plate_style.content_margin_bottom = 4
	_plate_style.shadow_color = Color(0, 0, 0, 0.45)
	_plate_style.shadow_size = 4
	name_plate.add_theme_stylebox_override("panel", _plate_style)
	name_plate.anchor_left = 0.5
	name_plate.anchor_right = 0.5
	name_plate.anchor_top = 1.0
	name_plate.anchor_bottom = 1.0
	name_plate.offset_left = -BOX_W / 2.0 + 24
	name_plate.offset_right = -BOX_W / 2.0 + 24
	name_plate.offset_top = -BOX_H - 34 - 20
	name_plate.offset_bottom = -BOX_H - 34 - 20
	name_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(name_plate)
	name_label = UITheme.label(speaker, 21, Color(0.08, 0.06, 0.05))
	name_label.add_theme_font_override("font", UITheme.serif())
	name_plate.add_child(name_label)
	# escolhas: empilhadas à direita, logo acima da caixa (crescem para cima)
	choices_box = VBoxContainer.new()
	choices_box.add_theme_constant_override("separation", 8)
	choices_box.anchor_left = 0.5
	choices_box.anchor_right = 0.5
	choices_box.anchor_top = 1.0
	choices_box.anchor_bottom = 1.0
	choices_box.offset_left = BOX_W / 2.0 - 360
	choices_box.offset_right = BOX_W / 2.0
	choices_box.offset_top = -BOX_H - 34 - 24
	choices_box.offset_bottom = -BOX_H - 34 - 24
	choices_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(choices_box)
	# clarão (as explosões da Pip)
	_flash = ColorRect.new()
	_flash.color = Color(1, 0.97, 0.85, 0.0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	_box_pos = Vector2(box.offset_left, box.offset_top)
	# entrada: as faixas descem/sobem e a caixa aparece
	var tw := create_tween().set_parallel(true)
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_bars[0], "offset_bottom", BAR_H, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_bars[0], "offset_top", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_bars[1], "offset_top", -BAR_H, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_bars[1], "offset_bottom", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	box.modulate.a = 0.0
	tw.tween_property(box, "modulate:a", 1.0, 0.2)
	_show_page()


func _page_speaker(page: Dictionary) -> String:
	return str(page.get("speaker", speaker))


func _show_page() -> void:
	var page: Dictionary = pages[index]
	var who := _page_speaker(page)
	var mood := str(page.get("mood", ""))
	name_plate.visible = who != ""
	name_label.text = who
	var col: Color = StoryDialogue.color_of(who) if who != "" else StoryDialogue.COLORS[""]
	_plate_style.bg_color = col
	_box_style.border_color = col.darkened(0.25) if who != "" else Color(0.45, 0.47, 0.52)
	var size_px := 22
	var color := UITheme.TEXT
	_speed = CPS
	match mood:
		"shout":
			size_px = 27
			_speed = CPS * 1.35
			_shake = 0.35
		"whisper":
			size_px = 18
			color = Color(0.78, 0.76, 0.86)
			_speed = CPS * 0.8
		"think":
			color = Color(0.72, 0.8, 0.92)
	if who == "" and mood != "think":
		color = Color(0.95, 0.92, 0.84)
	text_label.add_theme_font_size_override("normal_font_size", size_px)
	text_label.add_theme_color_override("default_color", color)
	text_label.text = page.text
	text_label.visible_characters = 0
	_chars = 0.0
	for c in choices_box.get_children():
		c.queue_free()
	choices_box.visible = false
	hint.visible = false
	arrow.visible = false
	match str(page.get("fx", "")):
		"boom":
			_flash.color.a = 1.0
			_shake = 0.6
			Sfx.play("explode", 0.0)
		"sparkle":
			Sfx.play("gem", 0.0)
		"end":
			_end_card = true
	if page.has("on_show"):
		(page.on_show as Callable).call()


func _process(delta: float) -> void:
	_t += delta
	var total := text_label.get_total_character_count()
	if text_label.visible_characters >= 0 and text_label.visible_characters < total:
		_chars += delta * _speed
		text_label.visible_characters = int(_chars)
		if text_label.visible_characters >= total:
			_finish_typing()
	arrow.modulate.a = 0.55 + 0.45 * absf(sin(_t * 4.0))
	# tremida (grito, explosão) e clarão sumindo
	_shake = maxf(0.0, _shake - delta)
	var k := _shake * 14.0
	var off := Vector2(randf_range(-k, k), randf_range(-k, k)) if _shake > 0.0 else Vector2.ZERO
	box.offset_left = _box_pos.x + off.x
	box.offset_right = _box_pos.x + BOX_W + off.x
	box.offset_top = _box_pos.y + off.y
	box.offset_bottom = _box_pos.y + BOX_H + off.y
	_flash.color.a = maxf(0.0, _flash.color.a - delta * 1.8)


func _finish_typing() -> void:
	if text_label.visible_characters == -1 and (hint.visible or choices_box.visible):
		return   # esta página já terminou de digitar (não monta as escolhas de novo)
	text_label.visible_characters = -1
	var page: Dictionary = pages[index]
	if page.has("choices"):
		choices_box.visible = true
		var i := 0
		for ch in page.choices:
			i += 1
			var b := UITheme.button("%d   %s" % [i, ch.text], _choose.bind(ch.get("action", Callable()), ch.get("pages", [])), 300)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.add_theme_font_size_override("font_size", 18)
			choices_box.add_child(b)
		(choices_box.get_child(0) as Button).grab_focus.call_deferred()
	else:
		hint.visible = true
		arrow.visible = true


func _choose(action: Callable, more: Array = []) -> void:
	Sfx.play("click", 0.0)
	if not more.is_empty():
		# resposta da escolha: entra logo depois desta página e o diálogo segue
		for i in more.size():
			pages.insert(index + 1 + i, more[i])
		if action.is_valid():
			action.call()
		index += 1
		_show_page()
		return
	_close()
	if action.is_valid():
		action.call()


func _advance() -> void:
	if text_label.visible_characters != -1:
		_finish_typing()
		return
	if pages[index].has("choices"):
		return
	Sfx.play("click", 0.0)
	index += 1
	if index >= pages.size():
		_close()
	else:
		_show_page()


func _close() -> void:
	if _end_card and world != null and world.get("story_card") != null:
		world.story_card.enqueue_end()
	closed.emit()
	queue_free()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and choices_box.visible:
		var n: int = event.physical_keycode - KEY_1
		if n >= 0 and n < choices_box.get_child_count():
			get_viewport().set_input_as_handled()
			(choices_box.get_child(n) as Button).pressed.emit()
			return
	if event.is_action_pressed("interact") or event.is_action_pressed("jump") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_advance()
	elif event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_close()
