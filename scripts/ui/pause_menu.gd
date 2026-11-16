extends Control
## Menu de pausa e tela de morte (mode = "pause" ou "death").

signal closed
signal respawn_requested

const OPTIONS := preload("res://scripts/ui/options_panel.gd")
const UPDATE_PANEL := preload("res://scripts/ui/update_panel.gd")

var mode := "pause"
var player_pos := Vector3.ZERO
var player_yaw := 0.0
var _panel: Control
var _status: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := UITheme.centered_panel(self, 0.6 if mode == "pause" else 0.7)
	_panel = p.get_parent().get_parent()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(340, 0)
	p.add_child(v)
	if mode == "pause":
		v.add_child(_title("Menu" if Network.is_online() else "Pausado", UITheme.GOLD))
		v.add_child(UITheme.button("Continuar", _close))
		if Game.run_mods.active:
			v.add_child(UITheme.button("Abandonar desafio", _abandon))
		else:
			v.add_child(UITheme.button("Salvar jogo", _save))
		if not Network.is_online():
			var lb := UITheme.button("Carregar jogo", func() -> void: Econ.quick_load())
			lb.disabled = not Econ.has_solo()
			v.add_child(lb)
		v.add_child(UITheme.button("Opções", _options))
		if Game.can_admin():
			v.add_child(UITheme.button("Desligar modo admin" if Game.admin_mode() else "Ligar modo admin", _toggle_admin))
		v.add_child(UITheme.button("Menu principal", func() -> void: Game.go_to_menu()))
		v.add_child(UITheme.button("Sair do jogo", _quit))
	else:
		v.add_child(_title("Você caiu...", Color(0.9, 0.25, 0.2)))
		v.add_child(UITheme.label("Renascer na vila custa 10% do seu ouro.", 16, UITheme.DIM))
		v.add_child(UITheme.button("Renascer na vila", _respawn))
		var lb := UITheme.button("Carregar último save", func() -> void: Econ.quick_load())
		lb.disabled = Network.is_online() or not Econ.has_solo()
		v.add_child(lb)
		v.add_child(UITheme.button("Menu principal", func() -> void: Game.go_to_menu()))
	_status = UITheme.label("", 15, Color(0.7, 1, 0.7))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_status)
	if mode == "pause":
		var upd := UPDATE_PANEL.new()
		upd.before_install = _save_before_update
		v.add_child(upd)
	if not Network.is_online() and Econ.has_solo():
		_status.text = "Save: " + Econ.solo_info()
		_status.add_theme_color_override("font_color", UITheme.DIM)
	var first := v.get_child(1) as Button
	if first:
		first.grab_focus.call_deferred()


func _title(t: String, c: Color) -> Label:
	var l := UITheme.label(t, 34, c)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _save() -> void:
	if Econ.quick_save(player_pos, player_yaw):
		_status.text = "Jogo salvo!"
		_status.add_theme_color_override("font_color", Color(0.7, 1, 0.7))
		Sfx.play("pickup", 0.0)


## O jogo reabre sozinho depois de atualizar: salva antes para não perder o progresso.
func _save_before_update() -> void:
	if Network.is_online():
		Network.autosave()
	elif not Game.run_mods.active:
		Econ.report_vitals(player_pos, player_yaw)


func _toggle_admin() -> void:
	Game.toggle_admin()
	_close()


func _quit() -> void:
	if Network.is_online():
		Network.autosave()
	get_tree().quit()


func _options() -> void:
	_panel.visible = false
	var o := OPTIONS.new()
	add_child(o)
	o.closed.connect(func() -> void: _panel.visible = true)


func _abandon() -> void:
	var w = get_tree().current_scene
	if w and w.get("survival") != null:
		w.survival.end_run("quit")
	_close()


func _respawn() -> void:
	respawn_requested.emit()
	queue_free()


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if mode == "pause" and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_close()
