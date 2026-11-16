extends Control
## Seleção de personagem (online). Depois do login a conta escolhe com quem entra em Valdoria.
## Esquerda: só a fogueira e os heróis da conta sentados em troncos em volta dela (3D). O herói
## selecionado se levanta, pega a arma, vira um pouco para a câmera e ganha uma borda dourada.
## Direita: a lista (classe e nível) com Entrar, Criar herói, Excluir e Voltar.
## A lista vem do servidor (Network.char_list e o sinal char_list_changed); os pedidos vão por
## Network.char_enter / char_delete; "Criar herói" abre a tela de criação, que chama Network.char_create.
## Capturas sem servidor: `res://scenes/char_select.tscn -- --charselect-demo[=N] --shot=x.png` (N heróis).

const VIEW_FRACTION := 0.66          ## parte da largura da tela com a fogueira
const SEAT_RADIUS := 2.45            ## distância dos assentos até o centro da fogueira (m)
## Ângulo de cada assento (rad; 0 = atrás da fogueira, de frente para a câmera). Um por herói da conta
## (Network.MAX_CHARACTERS).
const SEATS := [-1.3, -0.48, 0.48, 1.3]
const LOG_BACK := -0.3               ## tronco do assento, atrás do herói (z local do assento)
const SIT_Z := -0.27                 ## sentado: o quadril fica em cima do tronco
const STAND_Z := 0.2                 ## de pé: um passo para a frente, saindo do tronco
## Levantar: de sentado (0) a de pé (1). Primeiro a mão vai até a arma encostada, pega, e ele se levanta.
const RISE_TIME := 1.25              ## segundos de sentado até de pé
const SIT_TIME := 1.0                ## e de volta (senta e encosta a arma)
const GRAB_AT := 0.3                 ## a arma passa do chão para a mão neste ponto
const LOG_HAND_X := 0.3              ## sentado: mãos no tronco, de cada lado do quadril (m)
const FACE_CAMERA := 0.6             ## de pé, quanto vira para a câmera (0 = continua olhando o fogo)
const GLOW_COLOR := Color(1.0, 0.76, 0.28)
const GLOW_WIDTH := 0.022            ## espessura da borda do selecionado (m)
const GLOW_SHADER := preload("res://assets/shaders/select_glow.gdshader")
const MASK_SHADER := preload("res://assets/shaders/select_mask.gdshader")
const GLOW_MIN_SIZE := 0.05          ## peças menores ficam sem borda (olhos, rebites)
const PICK_RADIUS := 110.0           ## clique na fogueira: distância máxima (px) até o herói
const CAM_FOLLOW := 0.18             ## quanto a câmera vira para o herói de pé (0 = sempre no fogo)

## Lista de exemplo (`--charselect-demo`, capturas sem servidor).
const DEMO := [
	{"id": 1, "name": "Aldric", "level": 14, "char_class": "warrior", "body": "m", "updated_at": 5,
		"equipment": {"weapon": "azure_edge", "armor": "leather_armor", "head": "knight_helm", "feet": "leather_boots"}},
	{"id": 2, "name": "Lyra", "level": 9, "char_class": "mage", "body": "f", "updated_at": 2,
		"equipment": {"weapon": "apprentice_staff", "armor": "mage_robe", "head": "wool_hood"}},
	{"id": 3, "name": "Tobias", "level": 21, "char_class": "archer", "body": "m", "updated_at": 3,
		"equipment": {"weapon": "short_bow", "head": "ranger_hood", "hands": "leather_gloves"}},
	{"id": 4, "name": "Sereia", "level": 3, "char_class": "healer", "body": "f", "updated_at": 1,
		"equipment": {"weapon": "sc_novice_scepter", "armor": "traveler_tunic"}},
]

var chars: Array = []      # entradas do servidor: {"id", "level", "char_class", "body", "equipment", "updated_at"}
var seats: Array = []      # por entrada: {"spot", "mover", "model", "rig", "look", "glow", "k", "t"}
var selected := -1
var busy := false
var demo := false

var view: SubViewportContainer
var cam: Camera3D
var heroes: Node3D
var fire_light: OmniLight3D
var list_box: VBoxContainer
var count_label: Label
var empty_label: Label
var status: Label
var enter_btn: Button
var create_btn: Button
var delete_btn: Button
var _rows: Array = []
var _group := ButtonGroup.new()
var _time := 0.0
var _cam_look := Vector3(0, 0.85, 0)
## Capturas: `--charselect-pose=X` prende o selecionado no ponto X (0 sentado .. 1 de pé) do levantar.
var _freeze := -1.0
## Capturas: `--charselect-pick=N` começa com o herói N selecionado (-1 = o de sempre).
var _demo_pick := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	var demo_n := -1
	for a in OS.get_cmdline_user_args():
		if a == "--charselect-demo":
			demo_n = DEMO.size()
		elif a.begins_with("--charselect-demo="):
			demo_n = clampi(int(a.substr(18)), 0, Network.MAX_CHARACTERS)
		elif a.begins_with("--charselect-pose="):
			_freeze = clampf(float(a.substr(18)), 0.0, 1.0)
		elif a.begins_with("--charselect-pick="):
			_demo_pick = int(a.substr(18))
	demo = demo_n >= 0
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.03)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_build_view()
	_build_panel()
	Network.char_list_changed.connect(_on_list)
	Network.join_failed.connect(_on_lost)
	multiplayer.server_disconnected.connect(_on_lost.bind("Conexão com o servidor perdida."))
	var created := Network.char_created
	Network.char_created = 0
	set_list(_demo_list(demo_n) if demo and Network.char_list.is_empty() else Network.char_list, created)
	if _demo_pick >= 0:
		select(_demo_pick, false)


## `n` heróis de exemplo (repete a lista DEMO com ids novos).
static func _demo_list(n: int) -> Array:
	var out := []
	for i in n:
		var e: Dictionary = DEMO[i % DEMO.size()].duplicate(true)
		e.id = i + 1
		if i >= DEMO.size():
			e.name = str(e.name) + str(i / DEMO.size() + 1)
		e.level = int(e.level) + 5 * (i / DEMO.size())
		out.append(e)
	return out


# ================================================================ lista
## Monta a lista e a roda da fogueira. Seleciona o recém-criado, senão o que já estava selecionado,
## senão o último jogado.
func set_list(list: Array, created := 0) -> void:
	var keep := int(chars[selected].id) if selected >= 0 and selected < chars.size() else 0
	chars = list.duplicate(true)
	_build_rows()
	_build_seats()
	var pick := -1
	var newest := -1
	for i in chars.size():
		var id := int(chars[i].id)
		if id == created or (created == 0 and id == keep):
			pick = i
		if newest < 0 or int(chars[i].get("updated_at", 0)) > int(chars[newest].get("updated_at", 0)):
			newest = i
	if pick < 0:
		pick = newest
	selected = -1
	select(pick, false)
	count_label.text = "%d/%d" % [chars.size(), Network.MAX_CHARACTERS]
	create_btn.disabled = chars.size() >= Network.MAX_CHARACTERS
	empty_label.visible = chars.is_empty()
	(enter_btn if not chars.is_empty() else create_btn).grab_focus.call_deferred()


func select(i: int, sound := true) -> void:
	if i < 0 or i >= chars.size():
		selected = -1
	else:
		if i != selected and sound:
			Sfx.play("click", 0.0)
		selected = i
		(_rows[i] as Button).set_pressed_no_signal(true)
	enter_btn.disabled = selected < 0 or busy
	delete_btn.disabled = selected < 0 or busy


## Nome da classe (tabela "classes") e cor da faixa.
static func class_info(cls: String) -> Dictionary:
	var d: Dictionary = Balance.tables.get_table("classes").get(cls, {})
	var c = d.get("color", Color.WHITE)
	return {"name": str(d.get("name", cls.capitalize())), "color": c if c is Color else Color.WHITE}


## Nome do herói (sem nome: a classe).
static func hero_name(e: Dictionary) -> String:
	var n := str(e.get("name", ""))
	return n if n != "" else class_info(str(e.get("char_class", ""))).name


## Texto da linha da lista (nome, classe e nível); os testes conferem.
static func row_text(e: Dictionary) -> String:
	return "%s · %s · Nível %d" % [hero_name(e), class_info(str(e.get("char_class", ""))).name, int(e.get("level", 1))]


func _build_rows() -> void:
	for r in _rows:
		r.queue_free()
	_rows.clear()
	for i in chars.size():
		var e: Dictionary = chars[i]
		var info := class_info(str(e.char_class))
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = _group
		b.custom_minimum_size = Vector2(0, 74)
		b.tooltip_text = row_text(e)
		b.pressed.connect(select.bind(i))
		b.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.double_click and ev.button_index == MOUSE_BUTTON_LEFT:
				_enter())
		var stripe := ColorRect.new()
		stripe.color = info.color
		stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stripe.anchor_bottom = 1.0
		stripe.offset_left = 8
		stripe.offset_right = 13
		stripe.offset_top = 10
		stripe.offset_bottom = -10
		b.add_child(stripe)
		var h := HBoxContainer.new()
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 26
		h.offset_right = -18
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(h)
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", 0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(v)
		var n := UITheme.heading(hero_name(e), 24, UITheme.TEXT)
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(n)
		var wc := CharRules.class_weapon(Balance.tables, str(e.char_class))
		var sub := HBoxContainer.new()
		sub.add_theme_constant_override("separation", 6)
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(sub)
		var cl := UITheme.label(info.name, 15, info.color)
		cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sub.add_child(cl)
		var wl := UITheme.label("· %s · %s" % [ItemDB.CLASS_NAMES.get(wc, wc), "Feminino" if e.get("body") == "f" else "Masculino"],
			14, UITheme.DIM)
		wl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sub.add_child(wl)
		var lv := VBoxContainer.new()
		lv.alignment = BoxContainer.ALIGNMENT_CENTER
		lv.add_theme_constant_override("separation", -4)
		lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(lv)
		var cap := UITheme.label("NÍVEL", 12, UITheme.DIM)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lv.add_child(cap)
		var num := UITheme.heading(str(int(e.level)), 30, UITheme.GOLD)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lv.add_child(num)
		list_box.add_child(b)
		_rows.append(b)


# ================================================================ ações
func _enter() -> void:
	if busy or selected < 0:
		return
	Sfx.play("click", 0.0)
	if demo and not Network.is_client():
		_set_status("(demonstração: sem servidor)", UITheme.DIM)
		return
	_set_busy(true)
	_set_status("Entrando em Valdoria...", UITheme.TEXT)
	Network.char_enter(int(chars[selected].id))


func _create() -> void:
	if busy or chars.size() >= Network.MAX_CHARACTERS:
		return
	Sfx.play("click", 0.0)
	# a tela de criação lê o espelho do personagem (Game): começa de um herói novo, sem nada
	Game.apply_state(CharState.new_character(Balance.tables).to_dict(), true)
	Loading.go(Game.CHAR_CREATE_SCENE)


func _ask_delete() -> void:
	if busy or selected < 0:
		return
	Sfx.play("click", 0.0)
	var e: Dictionary = chars[selected]
	var dlg := ConfirmationDialog.new()
	dlg.title = "Excluir herói"
	dlg.dialog_text = "Excluir %s (%s, nível %d)?\n\nO herói, a mochila e todo o progresso dele somem para sempre." \
		% [hero_name(e), class_info(str(e.char_class)).name, int(e.level)]
	dlg.ok_button_text = "Excluir"
	dlg.cancel_button_text = "Voltar"
	var id := int(e.id)
	dlg.confirmed.connect(func() -> void:
		dlg.queue_free()
		_delete(id))
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


func _delete(id: int) -> void:
	if demo and not Network.is_client():
		set_list(chars.filter(func(c: Dictionary) -> bool: return int(c.id) != id))
		return
	_set_busy(true)
	_set_status("Excluindo...", UITheme.TEXT)
	Network.char_delete(id)


## Volta ao menu principal (desconecta; a conta continua logada só até fechar a conexão).
func _back() -> void:
	Sfx.play("click", 0.0)
	Game.go_to_menu()


func _on_list(list: Array, created: int, err: String) -> void:
	Network.char_created = 0
	_set_busy(false)
	set_list(list, created)
	_set_status(err, UITheme.BAD if err != "" else UITheme.DIM)


func _on_lost(reason: String) -> void:
	if not is_inside_tree():
		return
	Network.leave()
	Network.last_error = reason
	Game.go_to_menu()


func _set_busy(b: bool) -> void:
	busy = b
	enter_btn.disabled = b or selected < 0
	delete_btn.disabled = b or selected < 0
	create_btn.disabled = b or chars.size() >= Network.MAX_CHARACTERS


func _set_status(t: String, c: Color) -> void:
	status.text = t
	status.add_theme_color_override("font_color", c)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()


# ================================================================ painel da direita
func _build_panel() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.frame_box(UITheme.BG, UITheme.GOLD_DIM, 26))
	panel.anchor_left = VIEW_FRACTION
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 18
	panel.offset_top = 24
	panel.offset_right = -24
	panel.offset_bottom = -24
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	v.add_child(UITheme.heading("Seus heróis", 40))
	var acc := Network.account_name if Network.account_name != "" else str(Game.settings.player_name)
	var who := UITheme.label(("Conta %s · " % acc if acc != "" else "") + "escolha com quem entrar em Valdoria.", 16, UITheme.DIM)
	who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(who)
	var sec := UITheme.section("Personagens", 18)
	count_label = UITheme.label("", 15, UITheme.DIM)
	sec.add_child(count_label)
	v.add_child(sec)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 8)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_box)
	empty_label = UITheme.label("Ninguém em volta da fogueira ainda.\nCrie o seu primeiro herói.", 17, UITheme.DIM)
	empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list_box.add_child(empty_label)
	status = UITheme.label("", 15, UITheme.DIM)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(status)
	enter_btn = UITheme.button("Entrar no mundo", _enter)
	enter_btn.custom_minimum_size.y = 54
	v.add_child(enter_btn)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	create_btn = UITheme.button("Criar herói", _create)
	create_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(create_btn)
	delete_btn = UITheme.button("Excluir", _ask_delete)
	delete_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(delete_btn)
	v.add_child(UITheme.button("Voltar ao menu", _back))


# ================================================================ fogueira (3D)
func _build_view() -> void:
	view = SubViewportContainer.new()
	view.stretch = true
	view.anchor_right = VIEW_FRACTION
	view.anchor_bottom = 1.0
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	view.gui_input.connect(_on_view_input)
	add_child(view)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X
	view.add_child(vp)
	var root := Node3D.new()
	vp.add_child(root)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.02, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.3, 0.5)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.fog_enabled = true
	env.fog_light_color = Color(0.03, 0.035, 0.06)
	env.fog_density = 0.06
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	# lua fria por trás (contorno dos heróis), a fogueira faz o resto
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-35, 160, 0)
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.light_energy = 0.45
	moon.shadow_enabled = true
	root.add_child(moon)

	var ground := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 26
	disc.bottom_radius = 26
	disc.height = 0.1
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.17, 0.22, 0.12)
	gm.roughness = 1.0
	disc.material = gm
	ground.mesh = disc
	ground.position.y = -0.05
	root.add_child(ground)
	# terra batida em volta do fogo
	var dirt := MeshInstance3D.new()
	var dd := CylinderMesh.new()
	dd.top_radius = SEAT_RADIUS + 0.9
	dd.bottom_radius = SEAT_RADIUS + 0.9
	dd.height = 0.02
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.25, 0.2, 0.14)
	dm.roughness = 1.0
	dd.material = dm
	dirt.mesh = dd
	dirt.position.y = 0.005
	root.add_child(dirt)

	var fire: Node3D = load("res://assets/models/campfire.glb").instantiate()
	root.add_child(fire)
	fire_light = OmniLight3D.new()
	fire_light.position = Vector3(0, 0.9, 0)
	fire_light.light_color = Color(1, 0.55, 0.22)
	fire_light.light_energy = 3.2
	fire_light.omni_range = 9.0
	fire_light.omni_attenuation = 1.3
	fire_light.shadow_enabled = true
	root.add_child(fire_light)
	root.add_child(_embers())

	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 34:
		var a := rng.randf() * TAU
		var d := rng.randf_range(7.5, 18.0)
		var t: Node3D = load("res://assets/models/tree_pine.glb" if rng.randf() < 0.65 else "res://assets/models/tree_fir.glb").instantiate()
		t.position = Vector3(cos(a) * d, 0, sin(a) * d)
		t.rotation.y = rng.randf() * TAU
		t.scale = Vector3.ONE * rng.randf_range(1.0, 1.7)
		root.add_child(t)
		if ToonLook.enabled():
			ToonLook.apply(t, false)
	for i in 6:
		var a := rng.randf() * TAU
		var rk: Node3D = load("res://assets/models/rock.glb").instantiate()
		rk.position = Vector3(cos(a), 0, sin(a)) * rng.randf_range(4.2, 6.5)
		rk.scale = Vector3.ONE * rng.randf_range(0.5, 1.0)
		root.add_child(rk)
	if ToonLook.enabled():
		ToonLook.apply(fire, false)

	heroes = Node3D.new()
	root.add_child(heroes)
	cam = Camera3D.new()
	cam.fov = 40
	cam.position = Vector3(0, 2.15, 7.9)
	root.add_child(cam)
	cam.look_at(_cam_look, Vector3.UP)


## Fagulhas subindo da fogueira.
func _embers() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 40
	p.lifetime = 2.2
	p.position = Vector3(0, 0.45, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.25
	p.direction = Vector3.UP
	p.spread = 18
	p.gravity = Vector3(0, 0.6, 0)
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.1
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(0.035, 0.035)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(1.0, 0.6, 0.2)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.5, 0.15)
	m.emission_energy_multiplier = 3.0
	q.material = m
	p.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = g
	return p


## Ângulo do assento `i` de `n` em volta do fogo (0 = atrás, de frente para a câmera). Os assentos são
## fixos (SEATS) e ninguém fica bem atrás das chamas; com poucos heróis ficam os do meio.
static func seat_angle(i: int, n: int) -> float:
	n = clampi(n, 1, SEATS.size())
	var first := (SEATS.size() - n) / 2
	return SEATS[first + clampi(i, 0, n - 1)]


func _build_seats() -> void:
	for st in seats:
		(st.spot as Node3D).queue_free()
	seats.clear()
	for i in chars.size():
		var e: Dictionary = chars[i]
		var a := seat_angle(i, chars.size())
		var spot := Node3D.new()
		spot.position = Vector3(sin(a), 0, -cos(a)) * SEAT_RADIUS
		spot.rotation.y = atan2(-spot.position.x, -spot.position.z)   # +Z do herói olha para o fogo
		heroes.add_child(spot)
		var mover := Node3D.new()
		mover.position.z = SIT_Z
		spot.add_child(mover)
		var model := KnightLook.instance(e.get("body", "m"))
		mover.add_child(model)
		var rig := KnightAnim.rig(model)
		var eq: Dictionary = Game.empty_equipment()
		var src = e.get("equipment", {})
		if src is Dictionary:
			for k in src:
				eq[k] = str(src[k])
		var look := KnightLook.apply(model, eq)
		var glow := _add_glow(model)
		# o assento: o quadril sentado fica na altura do joelho
		var seat_h: float = float(rig.shin) + float(rig.ankle_h) + 0.07 * float(rig.thigh) - 0.07
		spot.add_child(_log(seat_h))
		var t0 := float(i) * 1.7
		# começa já sentado (sem a animação de sentar ao abrir a tela)
		KnightAnim.apply(rig, KnightAnim.sit_pose(t0), 1.0)
		# o lado da mão da arma (o arco vai na esquerda) e a arma encostada no tronco desse lado
		var hand := "l" if look.get("class") == "bow" else "r"
		var arm: Node3D = rig.get("Arm" + hand.to_upper())
		var side := signf(model.to_local(arm.global_position).x) if arm else -1.0
		var prop := _lean_weapon(spot, look, side, seat_h)
		seats.append({"spot": spot, "mover": mover, "model": model, "rig": rig, "look": look, "glow": glow,
			"k": 0.0, "t": t0, "hand": hand, "side": side, "prop": prop, "seat_h": seat_h})


## Cópia da arma equipada encostada no tronco, do lado `side` (x do assento), com a ponta (o nó "tip"
## do suporte) para baixo na espada e para cima no cajado/arco. A base encosta no chão. null sem arma.
func _lean_weapon(spot: Node3D, look: Dictionary, side: float, seat_h: float) -> Node3D:
	var holder: Node3D = look.get("holder")
	if holder == null or not is_instance_valid(holder):
		return null
	var prop := holder.duplicate() as Node3D
	for n in prop.find_children("Sel*", "", true, false):
		n.free()   # sem a borda do herói
	prop.transform = Transform3D.IDENTITY
	spot.add_child(prop)
	# eixo mais comprido da arma (no espaço do suporte); o sentido é o da ponta ("tip")
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in prop.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = KnightLook._chain(mi, prop) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var along := Vector3.UP
	if not first:
		along = Vector3.ZERO
		along[box.get_longest_axis_index()] = 1.0
	var tip: Node3D = look.get("tip")
	if tip and along.dot(tip.position) < 0.0:
		along = -along
	var lean := 0.32   # rad: o topo deita para trás, no tronco
	var want := Vector3(0, -cos(lean), sin(lean)) if look.get("class") == "sword" else Vector3(0, cos(lean), -sin(lean))
	prop.basis = Basis(Quaternion(along, want.normalized()))
	prop.set_meta("axis", along)   # eixo comprido no espaço da arma (_grip_point)
	prop.position = Vector3(side * 0.55, 0, LOG_BACK + 0.24)
	# a parte mais baixa no chão
	var low := INF
	for mi: MeshInstance3D in prop.find_children("*", "MeshInstance3D", true, false):
		if not mi.visible or str(mi.name).begins_with("ToonOutline"):
			continue
		var xf := spot.global_transform.affine_inverse() * mi.global_transform
		var bb := mi.get_aabb()
		for c in 8:
			low = minf(low, (xf * bb.get_endpoint(c)).y)
	if low < INF:
		prop.position.y -= low
	prop.position.y = minf(prop.position.y, seat_h + 0.3)
	return prop


## Tronco deitado atrás do herói; o topo fica na altura `top`.
func _log(top: float) -> Node3D:
	var r := 0.17
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r * 1.06
	c.height = 1.0
	c.radial_segments = 9
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.36, 0.24, 0.15)
	m.roughness = 0.95
	c.material = m
	mi.mesh = c
	mi.rotation.z = PI / 2
	mi.position = Vector3(0, maxf(r, top - r), LOG_BACK)
	if ToonLook.enabled():
		ToonLook.apply(mi)
	return mi


## Borda dourada do selecionado: cada peça ganha uma máscara (marca o stencil) e uma casca invertida de
## normais suavizadas (a mesma do contorno toon) que só pinta fora da marca, então sobra a silhueta do
## corpo inteiro. Um par de materiais por herói: a borda acende e apaga junto com o "levantar".
func _add_glow(model: Node3D) -> Dictionary:
	var glow := ShaderMaterial.new()
	glow.shader = GLOW_SHADER
	glow.render_priority = 20
	glow.set_shader_parameter("color", GLOW_COLOR)
	glow.set_shader_parameter("width", GLOW_WIDTH)
	glow.set_shader_parameter("strength", 0.0)
	var mask := ShaderMaterial.new()
	mask.shader = MASK_SHADER
	mask.render_priority = -20
	var nodes: Array = []
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or str(mi.name).begins_with("ToonOutline") or str(mi.name).begins_with("Sel"):
			continue
		var m := _shell(mi, mi.mesh, mask, "SelMask")
		nodes.append(m)
		if mi.get_aabb().get_longest_axis_size() < GLOW_MIN_SIZE:
			continue
		var hull := ToonLook._hull_of(mi.mesh)
		if hull != null:
			nodes.append(_shell(mi, hull, glow, "SelGlow"))
	return {"glow": glow, "nodes": nodes}


## Cópia de `mi` com outra malha e material (filha da peça; com esqueleto, irmã presa à mesma pele).
func _shell(mi: MeshInstance3D, mesh: Mesh, mat: Material, node_name: String) -> MeshInstance3D:
	var o := MeshInstance3D.new()
	o.name = node_name
	o.mesh = mesh
	o.material_override = mat
	o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	o.visible = false
	if mi.skin != null:
		o.skin = mi.skin
		o.transform = mi.transform
		mi.get_parent().add_child(o)
		o.skeleton = o.get_path_to(mi.get_node(mi.skeleton)) if mi.has_node(mi.skeleton) else mi.skeleton
	else:
		mi.add_child(o)
	return o


func _process(delta: float) -> void:
	_time += delta
	if fire_light:
		fire_light.light_energy = 3.0 + sin(_time * 11.0) * 0.25 + sin(_time * 4.3 + 1.0) * 0.35
	var k := 1.0 - exp(-16.0 * delta)
	var look_at := Vector3(0, 0.85, 0)
	for i in seats.size():
		var st: Dictionary = seats[i]
		var up := i == selected
		st.t += delta
		st.k = move_toward(float(st.k), 1.0 if up else 0.0, delta / (RISE_TIME if up else SIT_TIME))
		if _freeze >= 0.0 and up:
			st.k = _freeze
		var pr := float(st.k)
		# 0..GRAB_AT: a mão vai até a arma; depois levanta (e a mão solta o gesto de pegar)
		var reach := smoothstep(0.0, GRAB_AT * 0.85, pr) * (1.0 - smoothstep(GRAB_AT + 0.05, GRAB_AT + 0.35, pr))
		var w := smoothstep(GRAB_AT, 1.0, pr)   # quanto já levantou
		var rig: Dictionary = st.rig
		var pose := KnightAnim.blend(KnightAnim.sit_pose(st.t), KnightAnim.idle_pose(st.t), w)
		# indo pegar a arma: inclina e olha para ela
		pose.body_x += 0.12 * reach
		pose.head_x += 0.25 * reach
		_seat_arms(st, pose, pr)
		KnightAnim.apply(rig, pose, k)
		var mover: Node3D = st.mover
		mover.position.z = lerpf(SIT_Z, STAND_Z, w)
		# de pé, vira um pouco para a câmera
		var spot: Node3D = st.spot
		var to_cam := spot.to_local(cam.global_position)
		mover.rotation.y = lerp_angle(0.0, atan2(to_cam.x, to_cam.z), w * FACE_CAMERA)
		# a arma sai do chão para a mão no meio do gesto (e volta ao chão ao sentar)
		var grabbed := pr >= GRAB_AT
		var look: Dictionary = st.look
		var holder: Node3D = look.get("holder")
		if holder and is_instance_valid(holder):
			holder.visible = grabbed
		if st.prop:
			(st.prop as Node3D).visible = not grabbed
		KnightAnim.hold_weapon_upright(look, rig)
		KnightAnim.sway_ponytail(rig, delta)
		var g: Dictionary = st.glow
		var lit := smoothstep(0.0, 0.5, pr) if up else w
		(g.glow as ShaderMaterial).set_shader_parameter("strength", lit * (0.8 + 0.2 * sin(_time * 3.2)))
		for n: MeshInstance3D in g.nodes:
			n.visible = lit > 0.01
		if up:
			look_at = look_at.lerp(spot.global_position + Vector3(0, 0.9, 0), CAM_FOLLOW)
	# a câmera acompanha de leve o herói de pé
	_cam_look = _cam_look.lerp(look_at, 1.0 - exp(-2.5 * delta))
	if cam:
		cam.look_at(_cam_look, Vector3.UP)


## Braços sentado: as duas mãos apoiadas no tronco, ao lado do quadril (IK). A mão da arma vai até a
## arma encostada e, depois de pegar, sai do gesto direto para a pose de pé (nunca volta ao tronco, que
## fica para trás quando ele levanta). As mãos soltam o tronco logo no começo do levantar. `pr` 0..1.
func _seat_arms(st: Dictionary, pose: Dictionary, pr: float) -> void:
	var rig: Dictionary = st.rig
	var model: Node3D = st.model
	var spot: Node3D = st.spot
	var to_model := model.global_transform.affine_inverse()
	var seat_top := float(st.seat_h) + 0.02
	var hold := 1.0 - smoothstep(GRAB_AT, GRAB_AT + 0.25, pr)
	var reach_to := smoothstep(0.0, GRAB_AT * 0.85, pr)                          # mão indo até a arma
	var let_go := 1.0 - smoothstep(GRAB_AT + 0.05, GRAB_AT + 0.35, pr)           # depois de pegar
	for side in ["l", "r"]:
		var arm: Node3D = rig.get("Arm" + side.to_upper())
		if arm == null:
			continue
		var sx := signf(model.to_local(arm.global_position).x)
		var on_log := to_model * spot.to_global(Vector3(sx * LOG_HAND_X, seat_top, LOG_BACK + 0.04))
		if side == st.hand and st.prop:
			var grip := to_model * _grip_point(st)
			var w := 1.0 if pr < GRAB_AT else let_go
			KnightAnim.arm_ik_pose(rig, pose, side, on_log.lerp(grip, reach_to), Vector3(sx, -0.3, 0.4), w)
			continue
		KnightAnim.arm_ik_pose(rig, pose, side, on_log, Vector3(sx, 0, -1.0), hold)


## Onde a mão pega a arma encostada: no cabo, na altura do assento (o suporte da arma fica na mão,
## que pode estar na ponta de baixo ou no meio da arma).
func _grip_point(st: Dictionary) -> Vector3:
	var prop: Node3D = st.prop
	var spot: Node3D = st.spot
	var o := prop.global_position
	var d := (prop.global_basis * (prop.get_meta("axis", Vector3.UP) as Vector3)).normalized()
	var want_y := spot.global_position.y + float(st.seat_h) + 0.1
	if absf(d.y) > 0.2:
		return o + d * clampf((want_y - o.y) / d.y, -1.2, 1.2)
	return o


## Clique na fogueira seleciona o herói mais perto do cursor; clique duplo entra.
func _on_view_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	var best := -1
	var best_d := PICK_RADIUS
	for i in seats.size():
		var p: Vector3 = (seats[i].spot as Node3D).global_position + Vector3(0, 0.9, 0)
		if cam.is_position_behind(p):
			continue
		var d := cam.unproject_position(p).distance_to(event.position)
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		select(best)
		if event.double_click:
			_enter()
