extends Control
## Menu principal com cenas 3D do mundo se revezando ao fundo (MenuBackdrop).

const OPTIONS := preload("res://scripts/ui/options_panel.gd")
const CREDITS := preload("res://scripts/ui/credits_panel.gd")
const UPDATE_PANEL := preload("res://scripts/ui/update_panel.gd")
const BACKDROP := preload("res://scripts/ui/menu_backdrop.gd")
## Logo do jogo; sem o arquivo o menu mostra o título em texto.
const LOGO_PATH := "res://assets/ui/logo.png"

var backdrop: Control
var scene_caption: Label
var menu_box: VBoxContainer
var mp_box: VBoxContainer
var mp_name: LineEdit
var mp_pass: LineEdit
var mp_address: LineEdit
var mp_status: Label
var mp_join: Button
var mp_create: Button
## Sobe a cada tentativa e ao Voltar: um login que termina depois disso é descartado (não conecta).
var _attempt := 0
var upd_box: PanelContainer


func _ready() -> void:
	if "--server" in OS.get_cmdline_user_args():
		return   # servidor dedicado: vai direto para o mundo
	theme = UITheme.get_theme()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	backdrop = BACKDROP.new()
	add_child(backdrop)
	add_child(_vignette())
	add_child(_motes())

	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.85))
	g.set_color(1, Color(0, 0, 0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(1, 0)
	var fade := TextureRect.new()
	fade.texture = gt
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.anchor_right = 0.6
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)

	menu_box = VBoxContainer.new()
	menu_box.anchor_top = 0.5
	menu_box.anchor_bottom = 0.5
	menu_box.offset_left = 90
	menu_box.offset_top = -300
	menu_box.offset_right = 560
	menu_box.offset_bottom = 300
	menu_box.add_theme_constant_override("separation", 10)
	add_child(menu_box)
	menu_box.add_child(_title())
	var sub := UITheme.label("Um RPG de ação — protótipo", 18, UITheme.DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_box.add_child(sub)
	var sp := Control.new()
	sp.custom_minimum_size.y = 24
	menu_box.add_child(sp)
	var new_btn := UITheme.button("Novo jogo", _new_game, 320)
	menu_box.add_child(new_btn)
	var has_solo := Econ.has_solo()
	var cont := UITheme.button("Continuar", func() -> void: Game.continue_game(), 320)
	cont.disabled = not has_solo
	menu_box.add_child(cont)
	if has_solo:
		var info := UITheme.label(Econ.solo_info(), 15, UITheme.DIM)
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		menu_box.add_child(info)
	menu_box.add_child(UITheme.button("Jogar online", _open_multiplayer, 320))
	menu_box.add_child(UITheme.button("Opções", _options, 320))
	menu_box.add_child(UITheme.button("Créditos", _credits, 320))
	menu_box.add_child(UITheme.button("Sair", func() -> void: get_tree().quit(), 320))
	(cont if not cont.disabled else new_btn).grab_focus.call_deferred()
	_build_multiplayer()
	Network.join_failed.connect(_on_join_failed)
	if Network.last_error != "":
		_open_multiplayer()
		_set_status(Network.last_error, Color(1, 0.6, 0.5))
		Network.last_error = ""

	_build_update_banner()
	_style_buttons(menu_box)
	_style_buttons(mp_box)
	_intro()

	var credit := UITheme.label("Feito com Godot 4 · modelos low-poly criados no Blender", 14, UITheme.DIM)
	credit.anchor_top = 1.0
	credit.anchor_bottom = 1.0
	credit.offset_left = 24
	credit.offset_top = -36
	add_child(credit)

	var ver := UITheme.label("v" + Network.version(), 14, UITheme.DIM)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ver.anchor_left = 1.0
	ver.anchor_right = 1.0
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.offset_left = -224
	ver.offset_right = -24
	ver.offset_top = -36
	ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ver)

	# nome da cena do fundo, aparece a cada troca
	scene_caption = UITheme.label("", 18, UITheme.GOLD)
	scene_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	scene_caption.anchor_left = 1.0
	scene_caption.anchor_right = 1.0
	scene_caption.anchor_top = 1.0
	scene_caption.anchor_bottom = 1.0
	scene_caption.offset_left = -524
	scene_caption.offset_right = -24
	scene_caption.offset_top = -64
	scene_caption.offset_bottom = -40
	scene_caption.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	scene_caption.add_theme_constant_override("outline_size", 6)
	scene_caption.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.0))
	scene_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scene_caption)
	backdrop.scene_changed.connect(_show_caption)
	_show_caption(backdrop.current_title())


## Logo (assets/ui/logo.png) ou, sem ela, o nome do jogo em texto dourado. Respira devagar.
func _title() -> Control:
	var node: Control
	if ResourceLoader.exists(LOGO_PATH):
		var logo := TextureRect.new()
		logo.texture = load(LOGO_PATH)
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.custom_minimum_size = Vector2(380, 325)
		node = logo
		menu_box.offset_top = -410   # a logo é mais alta que o título em texto
		menu_box.offset_right = 470  # coluna da largura da logo
	else:
		var title := UITheme.label("Ecos de Valdoria", 64, UITheme.GOLD)
		title.add_theme_constant_override("outline_size", 10)
		title.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.0))
		node = title
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := node.create_tween().set_loops()
	tw.tween_property(node, "modulate", Color(1.12, 1.08, 0.95), 2.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "modulate", Color.WHITE, 2.2).set_trans(Tween.TRANS_SINE)
	return node


## Botões do menu com a fonte serifada da logo (Cinzel), um pouco mais altos.
func _style_buttons(box: Control) -> void:
	for b in box.find_children("*", "Button", true, false):
		b.add_theme_font_override("font", UITheme.serif())
		b.add_theme_font_size_override("font_size", 20)
		b.custom_minimum_size.y = 46


## Os itens do menu entram deslizando da esquerda, um depois do outro.
func _intro() -> void:
	var i := 0
	for c in menu_box.get_children():
		var ci := c as CanvasItem
		if ci == null:
			continue
		ci.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_interval(0.25 + i * 0.07)
		tw.tween_property(ci, "modulate:a", 1.0, 0.45)
		i += 1
	# a coluna inteira começa 40 px à esquerda e desliza para o lugar
	var right := menu_box.offset_right
	menu_box.offset_left = 50
	menu_box.offset_right = right - 40
	for prop in [["offset_left", 90.0], ["offset_right", right]]:
		create_tween().tween_property(menu_box, prop[0], prop[1], 0.8) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _show_caption(t: String) -> void:
	if scene_caption == null:
		return
	scene_caption.text = t
	scene_caption.modulate.a = 0.0
	var tw := scene_caption.create_tween()
	tw.tween_interval(0.4)
	tw.tween_property(scene_caption, "modulate:a", 0.9, 1.0)
	tw.tween_interval(4.0)
	tw.tween_property(scene_caption, "modulate:a", 0.0, 1.5)


## Escurece as bordas da tela (vinheta) para o menu e o centro da cena se destacarem.
func _vignette() -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.add_point(0.6, Color(0, 0, 0, 0.08))
	g.set_color(g.get_point_count() - 1, Color(0, 0, 0, 0.6))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.05, 1.05)
	var v := TextureRect.new()
	v.texture = gt
	v.stretch_mode = TextureRect.STRETCH_SCALE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


## Poeira dourada subindo devagar pela tela inteira, por cima de todas as cenas.
func _motes() -> Control:
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := CPUParticles2D.new()
	p.amount = 46
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.direction = Vector2(0.2, -1)
	p.spread = 25
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 12.0
	p.initial_velocity_max = 34.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 4.0
	p.color = Color(1.0, 0.85, 0.5, 0.55)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.add_point(0.25, Color(1, 1, 1, 1))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	p.color_ramp = g
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	host.add_child(p)
	# a área de emissão acompanha o tamanho da janela
	var fit := func() -> void:
		p.position = Vector2(host.size.x * 0.5, host.size.y * 0.75)
		p.emission_rect_extents = Vector2(host.size.x * 0.5, host.size.y * 0.3)
	host.resized.connect(fit)
	fit.call_deferred()
	return host


func _new_game() -> void:
	Sfx.play("click", 0.0)
	if not Econ.has_solo():
		Game.start_new_game()
		return
	# o personagem solo é um só: começar de novo apaga o atual (pergunta antes)
	var dlg := ConfirmationDialog.new()
	dlg.title = "Novo jogo"
	dlg.dialog_text = "Começar um novo jogo apaga o personagem salvo neste PC\n(%s: nível, itens e horta).\n\nContinuar?" % Econ.solo_info()
	dlg.ok_button_text = "Apagar e começar"
	dlg.cancel_button_text = "Voltar"
	dlg.confirmed.connect(func() -> void: Game.start_new_game())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


# ---------------------------------------------------------------- jogar online (login + ENet)
func _build_multiplayer() -> void:
	mp_box = VBoxContainer.new()
	mp_box.anchor_top = 0.5
	mp_box.anchor_bottom = 0.5
	mp_box.offset_left = 90
	mp_box.offset_top = -300
	mp_box.offset_right = 560
	mp_box.offset_bottom = -300   # a altura vem do conteúdo (o painel atrás acompanha)
	mp_box.add_theme_constant_override("separation", 10)
	mp_box.visible = false
	# moldura do kit atrás do formulário, do tamanho dele
	var back := Panel.new()
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.visible = false
	add_child(back)
	add_child(mp_box)
	var fit := func() -> void:
		back.position = mp_box.position - Vector2(30, 26)
		back.size = mp_box.size + Vector2(60, 52)
		back.visible = mp_box.visible
	mp_box.resized.connect(fit)
	mp_box.visibility_changed.connect(fit)
	var head := UITheme.heading("Jogar online", 40)
	mp_box.add_child(head)
	mp_box.add_child(UITheme.label("Entre com a sua conta e jogue com seus amigos.", 18, UITheme.DIM))
	mp_box.add_child(UITheme.label("Usuário", 16))
	mp_name = LineEdit.new()
	mp_name.max_length = 16
	mp_name.placeholder_text = "3 a 16 letras, números ou _"
	# o nome salvo é o usuário do último login (a senha nunca é salva)
	mp_name.text = str(Game.settings.player_name)
	mp_name.custom_minimum_size = Vector2(320, 40)
	mp_name.text_submitted.connect(func(_t: String) -> void: mp_pass.grab_focus())
	mp_box.add_child(mp_name)
	mp_box.add_child(UITheme.label("Senha", 16))
	mp_pass = LineEdit.new()
	mp_pass.secret = true
	mp_pass.max_length = 128
	mp_pass.placeholder_text = "pelo menos 8 caracteres"
	mp_pass.custom_minimum_size = Vector2(320, 40)
	mp_pass.text_submitted.connect(func(_t: String) -> void: _join())
	mp_box.add_child(mp_pass)
	mp_box.add_child(UITheme.label("Servidor (endereço ou endereço:porta)", 16))
	mp_address = LineEdit.new()
	mp_address.placeholder_text = Network.DEFAULT_ADDRESS
	var saved := str(Game.settings.server_address)
	mp_address.text = saved if saved != "" else Network.DEFAULT_ADDRESS
	mp_address.custom_minimum_size = Vector2(320, 40)
	mp_address.text_submitted.connect(func(_t: String) -> void: _join())
	mp_box.add_child(mp_address)
	var note := UITheme.label("Seus heróis online ficam na conta, no servidor (separados do solo). Depois de entrar você escolhe com quem jogar.", 15, UITheme.DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 420
	mp_box.add_child(note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	mp_box.add_child(row)
	mp_join = UITheme.button("Entrar", _join, 155)
	row.add_child(mp_join)
	mp_create = UITheme.button("Criar conta", _create_account, 155)
	row.add_child(mp_create)
	mp_box.add_child(UITheme.button("Voltar", _close_multiplayer, 320))
	mp_status = UITheme.label("", 16, UITheme.DIM)
	mp_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mp_status.custom_minimum_size.x = 420
	mp_box.add_child(mp_status)


func _open_multiplayer() -> void:
	Sfx.play("click", 0.0)
	menu_box.visible = false
	mp_box.visible = true
	_set_status("v" + Network.version(), UITheme.DIM)
	(mp_name if mp_name.text == "" else mp_pass).grab_focus.call_deferred()


func _close_multiplayer() -> void:
	_attempt += 1   # cancela um cadastro/login em andamento
	Network.leave()
	mp_box.visible = false
	menu_box.visible = true
	mp_pass.text = ""
	_set_busy(false)


func _set_busy(busy: bool) -> void:
	mp_join.disabled = busy
	mp_create.disabled = busy


## Confere os campos, lembra usuário e endereço (nunca a senha). Devolve false se falta algo.
func _read_form() -> bool:
	if mp_name.text.strip_edges() == "" or mp_pass.text == "":
		_set_status("Digite o usuário e a senha.", Color(1, 0.6, 0.5))
		return false
	if mp_address.text.strip_edges() == "":
		_set_status("Digite o endereço do servidor.", Color(1, 0.6, 0.5))
		return false
	Game.settings.player_name = mp_name.text.strip_edges()
	Game.settings.server_address = mp_address.text.strip_edges()
	Game.save_settings()
	return true


func _join() -> void:
	if mp_join.disabled or not _read_form():
		return
	Sfx.play("click", 0.0)
	_set_busy(true)
	_attempt += 1
	await _login_and_connect(_attempt)


func _create_account() -> void:
	if mp_create.disabled or not _read_form():
		return
	Sfx.play("click", 0.0)
	_set_busy(true)
	_attempt += 1
	var my_attempt := _attempt
	_set_status("Criando a conta...", UITheme.TEXT)
	var r: Dictionary = await Auth.register(mp_address.text, mp_name.text.strip_edges(), mp_pass.text)
	if my_attempt != _attempt:
		return   # o jogador voltou do painel enquanto esperava
	if not r.ok:
		_on_join_failed(r.msg)
		return
	_set_status("Conta criada! Entrando...", UITheme.TEXT)
	await _login_and_connect(my_attempt)


func _login_and_connect(my_attempt: int) -> void:
	var address := mp_address.text.strip_edges()
	_set_status("Entrando...", UITheme.TEXT)
	var r: Dictionary = await Auth.login(address, mp_name.text.strip_edges(), mp_pass.text)
	if my_attempt != _attempt or not is_instance_valid(mp_box) or not mp_box.visible:
		return   # cancelado (Voltar) enquanto o login estava no ar
	if not r.ok:
		_on_join_failed(r.msg)
		return
	mp_pass.text = ""
	# o servidor responde com a lista de personagens da conta e a tela de seleção abre (Network._char_list)
	_set_status("Conectando a %s como %s..." % [address, r.get("name", "")], UITheme.TEXT)
	Network.join(address, str(r.token))


func _on_join_failed(reason: String) -> void:
	if mp_join:
		_set_busy(false)
	_set_status(reason, Color(1, 0.6, 0.5))
	# servidor com outra versão: procura de novo (a release nova pode ter acabado de sair)
	if reason.begins_with("Versão diferente") and not Updater.can_install():
		Updater.check()


# ---------------------------------------------------------------- atualização
## Aviso no canto superior direito; só aparece quando há versão nova (ou durante a instalação).
func _build_update_banner() -> void:
	upd_box = PanelContainer.new()
	upd_box.anchor_left = 1.0
	upd_box.anchor_right = 1.0
	upd_box.offset_left = -440
	upd_box.offset_top = 24
	upd_box.offset_right = -24
	upd_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(upd_box)
	var panel := UPDATE_PANEL.new()
	upd_box.add_child(panel)
	upd_box.visible = panel.visible
	panel.visibility_changed.connect(func() -> void: upd_box.visible = panel.visible)
	Updater.recheck()


func _set_status(t: String, c: Color) -> void:
	mp_status.text = t
	mp_status.add_theme_color_override("font_color", c)


func _options() -> void:
	menu_box.visible = false
	var o := OPTIONS.new()
	add_child(o)
	o.closed.connect(func() -> void: menu_box.visible = true)


func _credits() -> void:
	Sfx.play("click", 0.0)
	menu_box.visible = false
	var c := CREDITS.new()
	add_child(c)
	c.closed.connect(func() -> void: menu_box.visible = true)
