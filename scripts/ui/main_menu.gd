extends Control
## Menu principal com uma pequena cena 3D girando ao fundo.

const OPTIONS := preload("res://scripts/ui/options_panel.gd")
const UPDATE_PANEL := preload("res://scripts/ui/update_panel.gd")

var pivot: Node3D
var menu_box: VBoxContainer
var mp_box: VBoxContainer
var mp_name: LineEdit
var mp_pass: LineEdit
var mp_address: LineEdit
var mp_status: Label
var mp_join: Button
var mp_create: Button
var upd_box: PanelContainer


func _ready() -> void:
	if "--server" in OS.get_cmdline_user_args():
		return   # servidor dedicado: vai direto para o mundo
	theme = UITheme.get_theme()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	_build_backdrop()

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
	var title := UITheme.label("Ecos de Valdoria", 64, UITheme.GOLD)
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.0))
	menu_box.add_child(title)
	menu_box.add_child(UITheme.label("Um RPG de ação — protótipo", 20, UITheme.DIM))
	var sp := Control.new()
	sp.custom_minimum_size.y = 24
	menu_box.add_child(sp)
	var new_btn := UITheme.button("Novo jogo", _new_game, 320)
	menu_box.add_child(new_btn)
	var cont := UITheme.button("Continuar", func() -> void: Game.load_game(), 320)
	cont.disabled = not Game.has_save()
	menu_box.add_child(cont)
	if Game.has_save():
		menu_box.add_child(UITheme.label("   " + Game.save_info(), 15, UITheme.DIM))
	var colony := UITheme.button("Defesa da Cidade — nova", func() -> void:
		Sfx.play("click", 0.0)
		Game.start_colony(false), 320)
	menu_box.add_child(colony)
	if Game.has_colony_save():
		menu_box.add_child(UITheme.button("Defesa da Cidade — continuar", func() -> void:
			Sfx.play("click", 0.0)
			Game.start_colony(true), 320))
		menu_box.add_child(UITheme.label("   " + Game.colony_save_info(), 15, UITheme.DIM))
	menu_box.add_child(UITheme.button("Jogar online", _open_multiplayer, 320))
	menu_box.add_child(UITheme.button("Opções", _options, 320))
	menu_box.add_child(UITheme.button("Sair", func() -> void: get_tree().quit(), 320))
	(cont if not cont.disabled else new_btn).grab_focus.call_deferred()
	_build_multiplayer()
	Network.join_failed.connect(_on_join_failed)
	if Network.last_error != "":
		_open_multiplayer()
		_set_status(Network.last_error, Color(1, 0.6, 0.5))
		Network.last_error = ""

	_build_update_banner()

	var credit := UITheme.label("Feito com Godot 4 · modelos low-poly criados no Blender", 14, UITheme.DIM)
	credit.anchor_top = 1.0
	credit.anchor_bottom = 1.0
	credit.offset_left = 24
	credit.offset_top = -36
	add_child(credit)


func _new_game() -> void:
	Sfx.play("click", 0.0)
	Game.start_new_game()


# ---------------------------------------------------------------- jogar online (login + ENet)
func _build_multiplayer() -> void:
	mp_box = VBoxContainer.new()
	mp_box.anchor_top = 0.5
	mp_box.anchor_bottom = 0.5
	mp_box.offset_left = 90
	mp_box.offset_top = -300
	mp_box.offset_right = 560
	mp_box.offset_bottom = 300
	mp_box.add_theme_constant_override("separation", 10)
	mp_box.visible = false
	add_child(mp_box)
	mp_box.add_child(UITheme.label("Jogar online", 48, UITheme.GOLD))
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
	var who := "Personagem: " + (Game.save_info() if Game.has_save() else "novo (nenhum save neste PC)")
	mp_box.add_child(UITheme.label(who, 15, UITheme.DIM))
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
	await _login_and_connect()


func _create_account() -> void:
	if mp_create.disabled or not _read_form():
		return
	Sfx.play("click", 0.0)
	_set_busy(true)
	_set_status("Criando a conta...", UITheme.TEXT)
	var r: Dictionary = await Auth.register(mp_address.text, mp_name.text.strip_edges(), mp_pass.text)
	if not r.ok:
		_on_join_failed(r.msg)
		return
	_set_status("Conta criada! Entrando...", UITheme.TEXT)
	await _login_and_connect()


func _login_and_connect() -> void:
	var address := mp_address.text.strip_edges()
	_set_status("Entrando...", UITheme.TEXT)
	var r: Dictionary = await Auth.login(address, mp_name.text.strip_edges(), mp_pass.text)
	if not r.ok:
		_on_join_failed(r.msg)
		return
	mp_pass.text = ""
	# o personagem é o save deste PC (ou um novo, se não houver)
	if not (Game.has_save() and Game.load_character()):
		Game.new_game()
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


func _process(delta: float) -> void:
	if pivot:
		pivot.rotation.y += delta * 0.12


func _build_backdrop() -> void:
	var svc := SubViewportContainer.new()
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X
	svc.add_child(vp)
	var root := Node3D.new()
	vp.add_child(root)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.12, 0.15, 0.35)
	sm.sky_horizon_color = Color(0.85, 0.5, 0.35)
	sm.ground_horizon_color = Color(0.85, 0.5, 0.35)
	sm.ground_bottom_color = Color(0.1, 0.1, 0.1)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.8, 0.5, 0.4)
	env.fog_density = 0.02
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-20, 60, 0)
	sun.light_color = Color(1, 0.7, 0.5)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	root.add_child(sun)

	var ground := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 30
	disc.bottom_radius = 30
	disc.height = 0.1
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.25, 0.4, 0.15)
	disc.material = gm
	ground.mesh = disc
	ground.position.y = -0.05
	root.add_child(ground)

	pivot = Node3D.new()
	root.add_child(pivot)
	var knight: Node3D = load("res://assets/models/knight.glb").instantiate()
	knight.rotation.y = 0.5
	pivot.add_child(knight)
	var arm := knight.find_child("ArmR", true, false) as Node3D
	if arm:
		arm.rotation.x = -1.2
	var gob: Node3D = load("res://assets/models/goblin.glb").instantiate()
	gob.position = Vector3(2.5, 0, 2.0)
	gob.rotation.y = -2.4
	gob.scale = Vector3.ONE * 1.6
	pivot.add_child(gob)
	var slime: Node3D = load("res://assets/models/slime.glb").instantiate()
	slime.position = Vector3(-1.2, 0, -2.2)
	slime.rotation.y = 2.5
	pivot.add_child(slime)
	var fire: Node3D = load("res://assets/models/campfire.glb").instantiate()
	fire.position = Vector3(0.8, 0, -1.5)
	pivot.add_child(fire)
	var fl := OmniLight3D.new()
	fl.position = Vector3(0.8, 1.0, -1.5)
	fl.light_color = Color(1, 0.55, 0.2)
	fl.light_energy = 2.5
	fl.omni_range = 8
	pivot.add_child(fl)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 26:
		var a := rng.randf() * TAU
		var d := rng.randf_range(8, 22)
		var t: Node3D = load("res://assets/models/tree_pine.glb" if rng.randf() < 0.6 else "res://assets/models/tree_oak.glb").instantiate()
		t.position = Vector3(cos(a) * d, 0, sin(a) * d)
		t.scale = Vector3.ONE * rng.randf_range(0.9, 1.6)
		pivot.add_child(t)
	var cam := Camera3D.new()
	cam.position = Vector3(-3.2, 1.9, 6.0)
	cam.fov = 50
	root.add_child(cam)
	cam.look_at(Vector3(1.0, 1.1, 0), Vector3.UP)
