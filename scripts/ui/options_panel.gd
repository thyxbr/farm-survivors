extends Control
## Painel de opções reutilizado no menu principal e no menu de pausa.

signal closed


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := UITheme.centered_panel(self, 0.6)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.custom_minimum_size = Vector2(460, 0)
	p.add_child(v)
	v.add_child(UITheme.label("Opções", 30, UITheme.GOLD))

	v.add_child(UITheme.label("Volume geral"))
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = Game.settings.master_volume
	vol.value_changed.connect(_on_volume)
	v.add_child(vol)

	var sens_label := UITheme.label("")
	v.add_child(sens_label)
	var sens := HSlider.new()
	sens.min_value = 0.05
	sens.max_value = 1.0
	sens.step = 0.05
	sens.value = Game.settings.mouse_sensitivity
	var upd := func(x):
		Game.settings.mouse_sensitivity = x
		sens_label.text = "Sensibilidade do mouse: %.2f" % x
	upd.call(sens.value)
	sens.value_changed.connect(upd)
	v.add_child(sens)

	var inv := CheckBox.new()
	inv.text = "Inverter eixo Y"
	inv.button_pressed = Game.settings.invert_y
	inv.toggled.connect(func(on: bool) -> void: Game.settings.invert_y = on)
	v.add_child(inv)

	var fs := CheckBox.new()
	fs.text = "Tela cheia"
	fs.button_pressed = Game.settings.fullscreen
	fs.toggled.connect(_on_fullscreen)
	v.add_child(fs)

	# estilo "desenhado" (docs/ESTILO_TOON.md): `--notoon` e `--nooutline` vencem estas opções
	var toon := CheckBox.new()
	toon.text = "Estilo desenhado (sombra em dois tons)"
	var outline := CheckBox.new()
	outline.text = "Contorno nos personagens"
	if ToonLook.forced_off():
		toon.text += " — desligado pela linha de comando"
		toon.disabled = true
	else:
		toon.button_pressed = Game.settings.toon
	if ToonLook.forced_off(true):
		outline.text += " — desligado pela linha de comando"
		outline.disabled = true
	else:
		outline.button_pressed = Game.settings.toon_outline
		outline.disabled = toon.disabled or not toon.button_pressed
	var note := UITheme.label("", 14, Color(0.78, 0.76, 0.7))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(460, 0)
	note.visible = false
	toon.toggled.connect(func(on: bool) -> void:
		Game.settings.toon = on
		outline.disabled = not on or ToonLook.forced_off(true)
		note.text = "O estilo muda no que aparecer daqui em diante; o cenário já montado muda ao trocar de área."
		note.visible = true
		Game.save_settings())
	outline.toggled.connect(func(on: bool) -> void:
		Game.settings.toon_outline = on
		note.text = "Desligar vale na hora. Ligar vale para os personagens que aparecerem daqui em diante."
		note.visible = true
		Game.save_settings())
	v.add_child(toon)
	v.add_child(outline)
	v.add_child(note)

	v.add_child(UITheme.button("Voltar", _close))


func _on_volume(x: float) -> void:
	Game.settings.master_volume = x
	Game.apply_settings()


func _on_fullscreen(on: bool) -> void:
	Game.settings.fullscreen = on
	Game.apply_settings()


func _close() -> void:
	Game.save_settings()
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_close()
