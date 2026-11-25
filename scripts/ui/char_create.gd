extends Control
## Tela de criação do herói (layout "palco central", docs/superpowers/specs/2026-11-18-criacao-heroi-design.md):
## coluna de classes com emblema à esquerda, herói grande no centro com a aparência (sexo e penteados em
## miniatura) e a placa de nome, ficha da classe à direita (história, perfil, habilidades) e o rodapé com o nome.
## "Começar" pede `choose_class` (a regra mora em CharRules, no solo e no servidor) e entra em Valdoria.
## Aberta por Game.go_to_world() quando o personagem solo ainda não tem classe (novo jogo, continuar).
## Online é aberta por "Criar herói" da seleção de personagem: "Começar" pede ao servidor um personagem
## novo (Network.char_create) e a seleção volta com ele escolhido; "Voltar" volta para a seleção.

const ATTR_NAMES := {"str": "Força", "agi": "Agilidade", "int": "Inteligência", "vit": "Vitalidade"}
const PROFILE := [["dano", "Dano"], ["resistencia", "Resistência"], ["alcance", "Alcance"],
	["mobilidade", "Mobilidade"], ["suporte", "Suporte"]]
## Nomes do botão de dado (só sugestão: a disponibilidade é vista ao criar).
const RANDOM_NAMES := ["Arvelin", "Tessa", "Brannoc", "Ilyra", "Doran", "Maelis", "Corvo", "Selene",
	"Theodric", "Ayla"]
const RAIL_W := 140.0
const INFO_W := 700.0

## Testes: false = "Começar" não troca de cena (o smoke test usa a tela por cima do mundo).
var enter_world := true
## O pedido de escolha voltou ok.
var finished := false
var cls := "warrior"
var body := "m"
var hair := ""
var busy := false

var title_label: Label
var old_note: Label
## id da classe -> botão da coluna.
var cards := {}
var body_buttons := {}
var hair_picker: HairPicker
var preview: CharPreview
var class_name_label: Label
var skill_strip: SkillStrip
var status: Label
var start_btn: Button
## Online: nome do herói (o que aparece no jogo). Solo não tem nome.
var name_edit: LineEdit
var name_rule: Label

var _glow: TextureRect
var _emblem: ClassEmblem
var _chips: HBoxContainer
var _role_chip: Label
var _style_chip: Label
var _diff: Control
var _diff_chip: PanelContainer
var _lore: Label
var _weapon: Label
var _stats: GridContainer
var _stats_title: Control
var _plate_name: Label
var _plate_emblem: ClassEmblem
var _plate_cls: Label
var _name_count: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	_build_backdrop()

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 0)
	root.add_child(main)
	main.add_child(_build_rail())
	main.add_child(_build_stage())
	main.add_child(_build_info())

	var old := Game.is_old_character()
	title_label.text = "Escolha sua classe" if old else "Crie seu herói"
	old_note = UITheme.label("Seu herói já tem história: escolha a classe dele. Se a arma equipada não for da classe, "
		+ "ela vai para a mochila (nada se perde) e ele empunha a melhor arma da classe que tiver.", 15, Color(1, 0.8, 0.55))
	old_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	old_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	old_note.visible = old
	root.add_child(old_note)
	root.add_child(_build_bottom())

	Econ.done.connect(_on_done)
	if Network.is_client():
		Network.char_list_changed.connect(_on_char_list)
		multiplayer.server_disconnected.connect(_on_lost.bind("Conexão com o servidor perdida."))
		Network.join_failed.connect(_on_lost)
	# personagem antigo: começa na classe da arma que ele já usa
	var start_cls := "warrior"
	var wc := CharRules.weapon_class(Balance.tables, str(Game.equipment.get("weapon", ""))) \
		if str(Game.equipment.get("weapon", "")) != "" else ""
	for id in CharRules.CLASS_IDS:
		if wc != "" and CharRules.class_weapon(Balance.tables, id) == wc:
			start_cls = id
			break
	var start_body := Game.body if Game.body in ["m", "f", "d"] else "m"
	# capturas: `res://scenes/char_create.tscn -- --class=healer --body=f --hair=f_marias --shot=x.png`
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--class=") and a.substr(8) in CharRules.CLASS_IDS:
			start_cls = a.substr(8)
		elif a.begins_with("--body=") and a.substr(7) in ["m", "f", "d"]:
			start_body = a.substr(7)
	var start_hair := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hair=") and HairStyles.valid(start_body, a.substr(7)):
			start_hair = a.substr(7)
	select_body(start_body)
	if start_hair != "":
		select_hair(start_hair)
	select_class(start_cls)
	(name_edit if name_edit else start_btn).grab_focus.call_deferred()


# ---------------------------------------------------------------- montagem

## Coluna de classes: um botão por classe com o emblema e o nome; rola quando houver muitas.
func _build_rail() -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.028, 0.02, 0.85)
	sb.border_color = Color(0.17, 0.13, 0.1)
	sb.border_width_right = 1
	sb.content_margin_top = 28
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size.x = RAIL_W
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var l := UITheme.heading("Classes", 15, UITheme.GOLD_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	var group := ButtonGroup.new()
	var table: Dictionary = Balance.tables.get_table("classes")
	for id in CharRules.CLASS_IDS:
		var d: Dictionary = table.get(id, {})
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(112, 86)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.tooltip_text = str(d.get("name", id))
		for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			b.add_theme_stylebox_override(st, _rail_box(st, _color(d)))
		b.pressed.connect(select_class.bind(id))
		var cv := VBoxContainer.new()
		cv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cv.alignment = BoxContainer.ALIGNMENT_CENTER
		cv.add_theme_constant_override("separation", 3)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(cv)
		var e := ClassEmblem.for_class(d, 46)
		e.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cv.add_child(e)
		var n := UITheme.heading(str(d.get("name", id)), 13, UITheme.TEXT)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(n)
		list.add_child(b)
		cards[id] = b
	return panel


## Palco: título, coluna de aparência (sexo e penteados) e o herói grande com a placa de nome.
func _build_stage() -> Control:
	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_theme_constant_override("margin_left", 34)
	m.add_theme_constant_override("margin_top", 26)
	m.add_theme_constant_override("margin_right", 10)
	m.add_theme_constant_override("margin_bottom", 10)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	m.add_child(v)
	title_label = UITheme.heading("Crie seu herói", 36)
	v.add_child(title_label)
	v.add_child(UITheme.label("A classe é para sempre. A aparência você escolhe agora.", 15, UITheme.DIM))
	var h := HBoxContainer.new()
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)

	var look := VBoxContainer.new()
	look.add_theme_constant_override("separation", 8)
	look.custom_minimum_size.x = 186
	h.add_child(look)
	look.add_child(_spacer(14))
	look.add_child(UITheme.heading("Aparência", 14, UITheme.GOLD_DIM))
	var sex := HBoxContainer.new()
	sex.add_theme_constant_override("separation", 6)
	look.add_child(sex)
	var bg := ButtonGroup.new()
	for b in [["m", "Masculino"], ["f", "Feminino"], ["d", "Anão"]]:
		var btn := UITheme.button(b[1], _on_body_button.bind(b[0]))
		btn.toggle_mode = true
		btn.button_group = bg
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 15)
		btn.add_theme_color_override("font_color", UITheme.DIM)   # o escolhido fica dourado, o outro apagado
		btn.add_theme_color_override("font_pressed_color", UITheme.GOLD)
		btn.add_theme_color_override("font_hover_pressed_color", UITheme.GOLD)
		sex.add_child(btn)
		body_buttons[b[0]] = btn
	look.add_child(_spacer(4))
	look.add_child(UITheme.heading("Cabelo", 14, UITheme.GOLD_DIM))
	hair_picker = HairPicker.new()
	hair_picker.chosen.connect(select_hair)
	look.add_child(hair_picker)

	var area := Control.new()
	area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_child(area)
	_glow = TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.5))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	_glow.texture = gt
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.anchor_left = 0.12
	_glow.anchor_right = 0.88
	_glow.anchor_top = 0.72
	_glow.anchor_bottom = 1.0
	_glow.offset_bottom = -30
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(_glow)
	preview = CharPreview.new(Vector2(420, 560))
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.offset_top = 52
	preview.offset_bottom = -44
	area.add_child(preview)
	area.add_child(_build_plate())
	var rot := HBoxContainer.new()
	rot.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	rot.grow_horizontal = Control.GROW_DIRECTION_BOTH
	rot.offset_top = -38
	rot.offset_bottom = -4
	rot.alignment = BoxContainer.ALIGNMENT_CENTER
	rot.add_theme_constant_override("separation", 10)
	area.add_child(rot)
	rot.add_child(_turn_button("⟲", 0.6))
	var hint := UITheme.label("arraste para girar", 13, UITheme.DIM)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rot.add_child(hint)
	rot.add_child(_turn_button("⟳", -0.6))
	return m


## Placa sobre o herói, como no jogo: nome (online), emblema + "Nv 1 · Classe" e a barra de vida.
func _build_plate() -> Control:
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.offset_top = 112
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate_name = UITheme.outlined("Seu nome", 18, Color.WHITE, 5)
	_plate_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plate_name.visible = Network.is_client()
	v.add_child(_plate_name)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	_plate_emblem = ClassEmblem.for_class({}, 16)
	_plate_emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_plate_emblem)
	_plate_cls = UITheme.outlined("", 13, Color.WHITE, 4)
	row.add_child(_plate_cls)
	var hp := ColorRect.new()
	hp.color = UITheme.HP
	hp.custom_minimum_size = Vector2(110, 5)
	hp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(hp)
	return v


## Ficha da classe: emblema, nome, selos, história, arma, perfil em barras e as habilidades.
func _build_info() -> Control:
	var m := MarginContainer.new()
	m.custom_minimum_size.x = INFO_W
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_top", 26)
	m.add_theme_constant_override("margin_right", 34)
	m.add_theme_constant_override("margin_bottom", 10)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	m.add_child(v)
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 16)
	v.add_child(hdr)
	_emblem = ClassEmblem.for_class({}, 76)
	hdr.add_child(_emblem)
	var hv := VBoxContainer.new()
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	hv.add_theme_constant_override("separation", 6)
	hdr.add_child(hv)
	class_name_label = UITheme.heading("", 40)
	hv.add_child(class_name_label)
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 6)
	hv.add_child(_chips)
	_role_chip = _chip(_chips)
	_style_chip = _chip(_chips)
	_diff_chip = PanelContainer.new()
	_diff_chip.add_theme_stylebox_override("panel", _chip_box())
	_chips.add_child(_diff_chip)
	var dh := HBoxContainer.new()
	dh.add_theme_constant_override("separation", 6)
	_diff_chip.add_child(dh)
	dh.add_child(UITheme.label("Dificuldade", 13, UITheme.TEXT))
	_diff = Control.new()
	_diff.custom_minimum_size = Vector2(48, 14)
	_diff.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_diff.draw.connect(_draw_difficulty)
	dh.add_child(_diff)
	_lore = UITheme.label("", 21, Color(0.89, 0.85, 0.75))
	_lore.add_theme_font_override("font", UITheme.body())
	_lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lore.custom_minimum_size.x = INFO_W - 60
	v.add_child(_lore)
	_stats_title = UITheme.section("Arma e atributos", 16)
	v.add_child(_stats_title)
	_weapon = UITheme.label("", 15, UITheme.DIM)
	v.add_child(_weapon)
	_stats = GridContainer.new()
	_stats.columns = 2
	_stats.add_theme_constant_override("h_separation", 28)
	_stats.add_theme_constant_override("v_separation", 6)
	v.add_child(_stats)
	v.add_child(UITheme.section("Habilidades", 16))
	skill_strip = SkillStrip.new()
	v.add_child(skill_strip)
	return m


## Rodapé: nome (online) com contador, dado e a regra ao vivo; status; Voltar e Começar.
func _build_bottom() -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.028, 0.02, 0.88)
	sb.border_color = Color(0.17, 0.13, 0.1)
	sb.border_width_top = 1
	sb.content_margin_left = RAIL_W + 28
	sb.content_margin_right = 34
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	panel.add_child(h)
	if Network.is_client():
		var nv := VBoxContainer.new()
		nv.add_theme_constant_override("separation", 3)
		h.add_child(nv)
		var field := HBoxContainer.new()
		field.add_theme_constant_override("separation", 6)
		nv.add_child(field)
		name_edit = LineEdit.new()
		name_edit.max_length = CharacterService.NAME_MAX
		name_edit.placeholder_text = "Nome do herói"
		name_edit.custom_minimum_size = Vector2(300, 40)
		name_edit.text_changed.connect(_on_name_changed)
		name_edit.text_submitted.connect(func(_t: String) -> void: _start())
		field.add_child(name_edit)
		_name_count = UITheme.label("0/%d" % CharacterService.NAME_MAX, 13, UITheme.DIM)
		_name_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		field.add_child(_name_count)
		var dice := UITheme.button("Sortear", _roll_name)
		dice.tooltip_text = "Sugere um nome"
		field.add_child(dice)
		name_rule = UITheme.label("", 13, UITheme.DIM)
		nv.add_child(name_rule)
		_on_name_changed("")
	status = UITheme.label("", 15, UITheme.DIM)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(status)
	var back := UITheme.button("Voltar", _back, 150)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(back)
	start_btn = UITheme.button("Começar a jornada", _start, 230)
	start_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(start_btn)
	return panel


# ---------------------------------------------------------------- escolhas

func select_class(id: String) -> void:
	cls = id
	var d: Dictionary = Balance.tables.get_table("classes").get(id, {})
	var col := _color(d)
	if cards.has(id):
		_press_only(cards, id)
	var wc := CharRules.class_weapon(Balance.tables, id)
	class_name_label.text = str(d.get("name", id))
	class_name_label.add_theme_color_override("font_color", col)
	_emblem.kind = str(d.get("emblem", ""))
	_emblem.color = col
	_plate_emblem.kind = _emblem.kind
	_plate_emblem.color = col
	_plate_cls.text = "Nv 1 · %s" % class_name_label.text
	_plate_cls.add_theme_color_override("font_color", col)
	_glow.modulate = Color(col, 0.7)
	_role_chip.text = str(d.get("role", ""))
	_role_chip.get_parent().visible = _role_chip.text != ""
	_style_chip.text = str(d.get("style", ""))
	_style_chip.get_parent().visible = _style_chip.text != ""
	_diff.set_meta("level", int(d.get("difficulty", 0)))
	_diff.set_meta("color", col)
	_diff.queue_redraw()
	_diff_chip.visible = int(d.get("difficulty", 0)) > 0
	_lore.text = str(d.get("lore", d.get("desc", "")))
	var starter := str(d.get("starter_weapon", ""))
	var start_off := str(d.get("starter_offhand", ""))
	var kit_txt := str(ItemDB.get_item(starter).get("name", starter))
	if start_off != "":
		kit_txt += " e " + str(ItemDB.get_item(start_off).get("name", start_off))
	_weapon.text = "%s · escala com %s · começa com %s" % [str(d.get("weapon_label", ItemDB.CLASS_NAMES.get(wc, wc))),
		ATTR_NAMES.get(str(d.get("attr", "")), "?"), kit_txt]
	_fill_stats(d.get("profile", {}), col)
	# com escudo de início (Tank) a barra já mostra o kit do escudo, o que ele terá no jogo
	var shield_kit := start_off != "" and str(ItemDB.get_item(start_off).get("needs", "")) == "sword"
	skill_strip.show_kit(wc, "shield" if shield_kit else "")
	preview.show_weapon(starter, start_off)


func select_body(b: String) -> void:
	body = b
	if body_buttons.has(b):
		_press_only(body_buttons, b)
	if hair_picker:
		hair_picker.set_body(b)
	if preview:
		preview.show_body(b)   # a prévia troca para o corpo escolhido na hora
	select_hair(HairStyles.default_for(b))   # trocar o corpo volta ao penteado padrão dele


## Clique no sexo: o já escolhido não refaz nada (o grupo emite pressed de novo e perderia o penteado).
func _on_body_button(b: String) -> void:
	if b != body:
		select_body(b)


func select_hair(h: String) -> void:
	hair = h
	if hair_picker:
		hair_picker.select(h)
	if preview:
		preview.show_hair(h)


## Nomes das habilidades do kit mostrado (na ordem da barra; com o escudo do Tank, o kit do escudo).
func kit_names() -> Array:
	var out := []
	for ab in skill_strip.kit_ids():
		out.append(str(ItemDB.ABILITIES[ab].name))
	return out


## Regra do nome para o texto `text`: [aceito, mensagem]. A disponibilidade só o servidor sabe.
func _name_rule(text: String) -> Array:
	if text.strip_edges() == "":
		return [false, "%d a %d letras ou números, sem espaços" % [CharacterService.NAME_MIN, CharacterService.NAME_MAX]]
	if CharacterService.clean_name(text) == "":
		return [false, CharacterService.explain_create("nome_invalido")]
	return [true, "Nome válido (a disponibilidade é vista ao criar)"]


func _on_name_changed(text: String) -> void:
	_name_count.text = "%d/%d" % [text.length(), CharacterService.NAME_MAX]
	var r := _name_rule(text)
	name_rule.text = str(r[1])
	name_rule.add_theme_color_override("font_color", UITheme.DIM if text == "" else (UITheme.GOOD if r[0] else UITheme.BAD))
	_plate_name.text = text if text != "" else "Seu nome"


func _roll_name() -> void:
	Sfx.play("click", 0.0)
	name_edit.text = RANDOM_NAMES.pick_random()
	_on_name_changed(name_edit.text)


# ---------------------------------------------------------------- fluxo

func _start() -> void:
	if busy or finished:
		return
	var hero_name := ""
	if name_edit:
		var r := _name_rule(name_edit.text)
		if not r[0]:
			_set_status(str(r[1]), UITheme.BAD)
			name_edit.grab_focus()
			return
		hero_name = CharacterService.clean_name(name_edit.text)
	Sfx.play("click", 0.0)
	busy = true
	start_btn.disabled = true
	_set_status("Criando o herói...", UITheme.TEXT)
	if Network.is_client():
		Network.char_create(hero_name, cls, body, hair)   # a resposta é a lista nova (_on_char_list)
		return
	Econ.request("choose_class", [cls, body, hair])


## Online: o servidor respondeu à criação. Deu certo: Network já abre a seleção com o herói novo.
func _on_char_list(_list: Array, created: int, err: String) -> void:
	if finished or not busy:
		return
	busy = false
	if created > 0 and err == "":
		finished = true
		_set_status("", UITheme.DIM)
		return
	start_btn.disabled = false
	_set_status(err if err != "" else "Não deu para criar o herói. Tente de novo.", UITheme.BAD)


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


## Volta ao menu (solo) ou à seleção de personagem (online, continua conectado).
func _back() -> void:
	if busy:
		return
	Sfx.play("click", 0.0)
	if Network.is_client():
		Loading.go(Network.CHAR_SELECT_SCENE)
		return
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


# ---------------------------------------------------------------- peças

## Marca só `key` entre os botões de `buttons` (set_pressed_no_signal não desmarca os outros do grupo).
static func _press_only(buttons: Dictionary, key) -> void:
	for k in buttons:
		buttons[k].set_pressed_no_signal(k == key)


static func _color(d: Dictionary) -> Color:
	var c = d.get("color", Color.WHITE)
	return c if c is Color else Color.WHITE


## Barras do perfil (5 pontos cada) na cor da classe; perfil ausente esconde a grade.
func _fill_stats(prof: Dictionary, col: Color) -> void:
	for c in _stats.get_children():
		_stats.remove_child(c)
		c.queue_free()
	_stats.visible = not prof.is_empty()
	for p in PROFILE:
		if not prof.has(p[0]):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var l := UITheme.label(p[1], 14, UITheme.DIM)
		l.custom_minimum_size.x = 104
		row.add_child(l)
		for i in 5:
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(26, 8)
			pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pip.color = col if i < int(prof[p[0]]) else Color(0.16, 0.125, 0.1)
			row.add_child(pip)
		_stats.add_child(row)


func _draw_difficulty() -> void:
	var n := int(_diff.get_meta("level", 0))
	var col: Color = _diff.get_meta("color", UITheme.GOLD)
	for i in 3:
		var c := Vector2(7 + i * 16, 7)
		var pts := PackedVector2Array([c + Vector2(0, -6), c + Vector2(6, 0), c + Vector2(0, 6), c + Vector2(-6, 0)])
		_diff.draw_colored_polygon(pts, col if i < n else Color(0.2, 0.16, 0.12))


func _chip(parent: Control) -> Label:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _chip_box())
	parent.add_child(p)
	var l := UITheme.label("", 13, UITheme.TEXT)
	p.add_child(l)
	return l


static func _chip_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.1, 0.08, 0.06)
	s.border_color = Color(0.35, 0.27, 0.14)
	s.set_border_width_all(1)
	s.set_corner_radius_all(12)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 2
	s.content_margin_bottom = 3
	return s


static func _rail_box(state: String, col: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(6)
	s.set_border_width_all(2)
	s.bg_color = Color(0, 0, 0, 0)
	s.border_color = Color(0, 0, 0, 0)
	match state:
		"pressed", "hover_pressed":
			s.bg_color = Color(0.11, 0.08, 0.06)
			s.border_color = col
		"hover":
			s.bg_color = Color(0.1, 0.075, 0.055)
	return s


func _turn_button(glyph: String, angle: float) -> Button:
	var b := UITheme.button(glyph, func() -> void:
		preview._user_turned = true
		preview.pivot.rotation.y += angle)
	b.custom_minimum_size = Vector2(40, 34)
	return b


static func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c


## Fundo: degradê escuro com um brilho quente no meio.
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
	gt.fill_from = Vector2(0.42, 0.45)
	gt.fill_to = Vector2(1.0, 1.0)
	var glow := TextureRect.new()
	glow.texture = gt
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)
