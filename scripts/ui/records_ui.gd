extends Control
## Quadro de recordes: a melhor noite da Defesa e a melhor rodada da Horda do servidor (com os nomes)
## e os recordes pessoais do personagem.

signal closed

var body: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	var p := UITheme.centered_panel(self, 0.55)
	p.custom_minimum_size = Vector2(640, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(UITheme.heading("Recordes da cidade", 30))
	v.add_child(HSeparator.new())
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	v.add_child(body)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	foot.add_child(UITheme.spacer())
	foot.add_child(UITheme.keycap("E", 13))
	foot.add_child(UITheme.button("Sair", _close, 140))
	v.add_child(foot)
	Hub.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	for c in body.get_children():
		c.queue_free()
	var r: Dictionary = Hub.records
	var c: Dictionary = r.get("city", {})
	body.add_child(UITheme.section("Defesa da Cidade"))
	if int(c.get("reached", 0)) > 0:
		body.add_child(UITheme.label("Melhor noite: %d — %s" % [int(c.reached), ", ".join(c.get("names", []))], 18, UITheme.TEXT))
	else:
		body.add_child(UITheme.label("Ninguém defendeu uma cidade ainda.", 16, UITheme.DIM))
	body.add_child(UITheme.label("Seu melhor: %d noite(s)" % int(Game.flags.get("city_best", 0)), 16, UITheme.GOLD))
	var h: Dictionary = r.get("horde", {})
	body.add_child(UITheme.section("Desafio da Horda"))
	if int(h.get("reached", 0)) > 0:
		body.add_child(UITheme.label("Melhor rodada: %d — %s" % [int(h.reached), ", ".join(h.get("names", []))], 18, UITheme.TEXT))
	else:
		body.add_child(UITheme.label("Ninguém venceu rodadas da Horda ainda.", 16, UITheme.DIM))
	body.add_child(UITheme.label("Seu melhor: rodada %d" % int(Game.flags.get("horde_best", 0)), 16, UITheme.GOLD))


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_close()
