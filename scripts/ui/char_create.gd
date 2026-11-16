extends Control
## Tela de criação do herói: sexo, uma das quatro classes (cartões), prévia 3D com a arma inicial e o kit.
## "Começar" pede `choose_class` (a regra mora em CharRules, no solo e no servidor) e entra em Valdoria.
## Aberta por Game.go_to_world() quando o personagem ainda não tem classe (novo jogo, continuar, login).

const ATTR_NAMES := {"str": "Força", "agi": "Agilidade", "int": "Inteligência", "vit": "Vitalidade"}

## Testes: false = "Começar" não troca de cena (o smoke test usa a tela por cima do mundo).
var enter_world := true
## O pedido de escolha voltou ok.
var finished := false
var cls := "warrior"
var body := "m"
var busy := false

var title_label: Label
var old_note: Label
var body_note: Label
var cards := {}
var body_buttons := {}
var preview: CharPreview
var class_name_label: Label
var weapon_label: Label
var hint_label: Label
var desc_label: Label
var kit_box: VBoxContainer
var status: Label
var start_btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	_build_backdrop()

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.frame_box(UITheme.BG, UITheme.GOLD_DIM, 26))
	panel.custom_minimum_size = Vector2(1100, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)

	# título + sexo
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	v.add_child(top)
	var tbox := VBoxContainer.new()
	tbox.add_theme_constant_override("separation", 2)
	tbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tbox)
	var old := Game.is_old_character()
	title_label = UITheme.heading("Escolha sua classe" if old else "Crie seu herói", 40)
	tbox.add_child(title_label)
	tbox.add_child(UITheme.label("A classe é escolhida uma vez e decide a arma e as habilidades.", 16, UITheme.DIM))
	var sex := VBoxContainer.new()
	sex.add_theme_constant_override("separation", 4)
	top.add_child(sex)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	sex.add_child(srow)
	var sl := UITheme.label("Sexo", 18, UITheme.TEXT)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	srow.add_child(sl)
	var bg := ButtonGroup.new()
	for b in [["m", "Masculino"], ["f", "Feminino"]]:
		var btn := UITheme.button(b[1], select_body.bind(b[0]), 140)
		btn.toggle_mode = true
		btn.button_group = bg
		srow.add_child(btn)
		body_buttons[b[0]] = btn
	body_note = UITheme.label("O visual feminino chega em breve.", 14, UITheme.GOLD)
	body_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	body_note.custom_minimum_size.y = 20
	sex.add_child(body_note)

	old_note = UITheme.label("Seu herói já tem história: escolha a classe dele. Se a arma equipada não for da classe, "
		+ "ela vai para a mochila (nada se perde) e ele empunha a melhor arma da classe que tiver.", 15, Color(1, 0.8, 0.55))
	old_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	old_note.custom_minimum_size.x = 1040
	old_note.visible = old
	v.add_child(old_note)

	# cartões das classes
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 12)
	v.add_child(crow)
	var cg := ButtonGroup.new()
	var table: Dictionary = Balance.tables.get_table("classes")
	for id in CharRules.CLASS_IDS:
		var d: Dictionary = table.get(id, {})
		var card := Button.new()
		card.toggle_mode = true
		card.button_group = cg
		card.custom_minimum_size = Vector2(0, 70)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.pressed.connect(select_class.bind(id))
		var stripe := ColorRect.new()
		stripe.color = _color(d)
		stripe.custom_minimum_size.y = 4
		stripe.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		stripe.offset_left = 6
		stripe.offset_right = -6
		stripe.offset_top = 5
		stripe.offset_bottom = 9
		stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(stripe)
		var cv := VBoxContainer.new()
		cv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cv.offset_top = 12
		cv.alignment = BoxContainer.ALIGNMENT_CENTER
		cv.add_theme_constant_override("separation", 0)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(cv)
		var n := UITheme.heading(str(d.get("name", id)), 22, _color(d))
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(n)
		var w := UITheme.label(str(ItemDB.CLASS_NAMES.get(CharRules.class_weapon(Balance.tables, id), "")), 14, UITheme.DIM)
		w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(w)
		crow.add_child(card)
		cards[id] = card

	# prévia + detalhes
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 22)
	v.add_child(mid)
	var pv := PanelContainer.new()
	pv.add_theme_stylebox_override("panel", UITheme.inset_box(4))
	mid.add_child(pv)
	preview = CharPreview.new(Vector2(300, 330))
	pv.add_child(preview)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(info)
	class_name_label = UITheme.heading("", 34)
	info.add_child(class_name_label)
	weapon_label = UITheme.label("", 18, UITheme.TEXT)
	info.add_child(weapon_label)
	hint_label = UITheme.label("", 15, UITheme.DIM)
	info.add_child(hint_label)
	desc_label = UITheme.label("", 16, UITheme.TEXT)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size.x = 700
	info.add_child(desc_label)
	info.add_child(UITheme.section("Habilidades", 18))
	kit_box = VBoxContainer.new()
	kit_box.add_theme_constant_override("separation", 6)
	info.add_child(kit_box)

	# rodapé
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	v.add_child(bottom)
	status = UITheme.label("Arraste a prévia para girar o herói.", 15, UITheme.DIM)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(status)
	bottom.add_child(UITheme.button("Voltar", _back, 160))
	start_btn = UITheme.button("Começar", _start, 200)
	bottom.add_child(start_btn)

	Econ.done.connect(_on_done)
	if Network.is_client():
		multiplayer.server_disconnected.connect(_on_lost.bind("Conexão com o servidor perdida."))
		Network.join_failed.connect(_on_lost)
	# personagem antigo: começa na classe da arma que ele já usa
	var start_cls := "warrior"
	var wc := CharRules.weapon_class(Balance.tables, str(Game.equipment.get("weapon", ""))) \
		if str(Game.equipment.get("weapon", "")) != "" else ""
	for id in CharRules.CLASS_IDS:
		if wc != "" and CharRules.class_weapon(Balance.tables, id) == wc:
			start_cls = id
	var start_body := Game.body if Game.body in ["m", "f"] else "m"
	# capturas: `res://scenes/char_create.tscn -- --class=healer --body=f --shot=x.png` abre já escolhido
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--class=") and a.substr(8) in CharRules.CLASS_IDS:
			start_cls = a.substr(8)
		elif a.begins_with("--body=") and a.substr(7) in ["m", "f"]:
			start_body = a.substr(7)
	select_body(start_body)
	select_class(start_cls)
	start_btn.grab_focus.call_deferred()


func select_class(id: String) -> void:
	cls = id
	var d: Dictionary = Balance.tables.get_table("classes").get(id, {})
	if cards.has(id):
		cards[id].set_pressed_no_signal(true)
	var wc := CharRules.class_weapon(Balance.tables, id)
	class_name_label.text = str(d.get("name", id))
	class_name_label.add_theme_color_override("font_color", _color(d))
	var starter := str(d.get("starter_weapon", ""))
	weapon_label.text = "%s · %s · arma inicial: %s" % [ItemDB.CLASS_NAMES.get(wc, wc),
		ATTR_NAMES.get(str(d.get("attr", "")), ""), ItemDB.get_item(starter).get("name", starter)]
	hint_label.text = str(ItemDB.CLASS_HINT.get(wc, ""))
	desc_label.text = str(d.get("desc", ""))
	for c in kit_box.get_children():
		c.queue_free()
	for ab in ItemDB.kit(wc):
		kit_box.add_child(_ability_row(ab))
	preview.show_weapon(starter)


func select_body(b: String) -> void:
	body = b
	if body_buttons.has(b):
		body_buttons[b].set_pressed_no_signal(true)
	body_note.visible = b == "f"


## Nomes das habilidades do kit mostrado (na ordem da barra).
func kit_names() -> Array:
	var out := []
	for ab in ItemDB.kit(CharRules.class_weapon(Balance.tables, cls)):
		out.append(str(ItemDB.ABILITIES[ab].name))
	return out


func _ability_row(id: String) -> Control:
	var a: Dictionary = ItemDB.ABILITIES[id]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var key := UITheme.keycap(str(a.slot))
	key.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(key)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var tags: Array = []
	if a.get("ultimate", false):
		tags.append("ultimate")
	if int(a.get("level", 1)) > 1:
		tags.append("nível %d" % int(a.level))
	if not a.get("ready", true):
		tags.append("em breve")
	var title := UITheme.label(str(a.name) + ("   (%s)" % ", ".join(tags) if not tags.is_empty() else ""), 16,
		UITheme.GOLD if a.get("ultimate", false) else UITheme.TEXT)
	col.add_child(title)
	var desc := UITheme.label(str(a.get("desc", "")), 13, UITheme.DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = 640
	col.add_child(desc)
	return row


func _start() -> void:
	if busy or finished:
		return
	Sfx.play("click", 0.0)
	busy = true
	start_btn.disabled = true
	_set_status("Criando o herói...", UITheme.TEXT)
	Econ.request("choose_class", [cls, body])


func _on_done(op: String, _args: Array, ok: bool, err: String, _events: Array) -> void:
	if op != "choose_class" or finished:
		return
	busy = false
	if ok or Game.char_class != "":
		finished = true
		_set_status("", UITheme.DIM)
		if enter_world:
			Loading.go(Game.WORLD_SCENE)
		return
	start_btn.disabled = false
	_set_status("Não deu para criar o herói (%s). Tente de novo." % err, UITheme.BAD)


## Volta ao menu (online: desconecta; o personagem continua sem classe e a tela volta no próximo login).
func _back() -> void:
	if busy:
		return
	Sfx.play("click", 0.0)
	Game.go_to_menu()


func _on_lost(reason: String) -> void:
	if finished or not is_inside_tree():
		return
	Network.leave()
	Network.last_error = reason
	Game.go_to_menu()


func _set_status(t: String, c: Color) -> void:
	status.text = t
	status.add_theme_color_override("font_color", c)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()


static func _color(d: Dictionary) -> Color:
	var c = d.get("color", Color.WHITE)
	return c if c is Color else Color.WHITE


## Fundo: degradê escuro com um brilho quente atrás do painel.
func _build_backdrop() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.03, 0.03)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var g := Gradient.new()
	g.set_color(0, Color(0.32, 0.18, 0.08, 0.55))
	g.set_color(1, Color(0, 0, 0, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.45)
	gt.fill_to = Vector2(1.0, 1.0)
	var glow := TextureRect.new()
	glow.texture = gt
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)
