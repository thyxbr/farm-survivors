extends Control
## Salão de Valdoria: o lobby central do multiplayer.
## Mostra quem está online e onde, leva para Valdoria (o mundo do RPG) e organiza a sala da
## Defesa da Cidade em grupo (criar, entrar, ficar pronto, começar ou entrar na partida em andamento).
## Ao fundo, uma fogueira com o cavaleiro de cada jogador que está no salão.

const OPTIONS := preload("res://scripts/ui/options_panel.gd")
const KNIGHT := preload("res://assets/models/knight.glb")
const CHAT := preload("res://scripts/ui/chat_ui.gd")

## Lobby.in_session() reconhece a cena por isto.
var is_lobby := true

var _pivot: Node3D
var _knights := {}          # peer id -> Node3D
var _header: Label
var _players_box: VBoxContainer
var _room_box: VBoxContainer
var _record_label: Label
var _result_panel: PanelContainer
var _feed: VBoxContainer
var _main: Control
var _dirty := true
var _t := 0.0


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	_build_backdrop()
	_build_ui()
	Lobby.changed.connect(_mark)
	Network.players_changed.connect(_mark)
	Game.notify.connect(_on_notify)
	if Network.is_client():
		add_child(CHAT.new())   # chat do servidor inteiro (canto inferior esquerdo)
	Lobby.lobby_ready()


func _exit_tree() -> void:
	if Game.notify.is_connected(_on_notify):
		Game.notify.disconnect(_on_notify)


func _mark() -> void:
	_dirty = true


func _process(delta: float) -> void:
	_t += delta
	if _pivot:
		_pivot.rotation.y += delta * 0.05
	if _dirty:
		_dirty = false
		_refresh()


# ================================================================ interface
func _build_ui() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.88))
	g.set_color(1, Color(0, 0, 0, 0.15))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(1, 0)
	var fade := TextureRect.new()
	fade.texture = gt
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)

	_main = Control.new()
	_main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_main)

	# --- coluna da esquerda: título, jogadores, botões
	var left := VBoxContainer.new()
	left.position = Vector2(60, 40)
	left.custom_minimum_size = Vector2(430, 0)
	left.add_theme_constant_override("separation", 8)
	_main.add_child(left)
	var title := UITheme.label("Salão de Valdoria", 52, UITheme.GOLD)
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.0))
	left.add_child(title)
	_header = UITheme.label("", 18, UITheme.DIM)
	left.add_child(_header)
	left.add_child(UITheme.spacer())
	left.add_child(UITheme.section("Jogadores online", 20))
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 2)
	left.add_child(_players_box)
	left.add_child(UITheme.spacer())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	left.add_child(row)
	row.add_child(UITheme.button("Opções", _options, 140))
	row.add_child(UITheme.button("Desconectar", func() -> void: Game.go_to_menu(), 180))

	# --- coluna da direita: os modos de jogo
	var right := VBoxContainer.new()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -640
	right.offset_right = -50
	right.offset_top = 40
	right.add_theme_constant_override("separation", 14)
	_main.add_child(right)

	_result_panel = _card(right)
	_result_panel.visible = false

	var world_card := _card(right)
	var wv := VBoxContainer.new()
	wv.add_theme_constant_override("separation", 6)
	world_card.add_child(wv)
	wv.add_child(UITheme.heading("Valdoria — mundo aberto", 26))
	wv.add_child(_wrap("Missões do Ancião Bram, a loja da Mira, a Horta e o Desafio da Horda com quem estiver por lá. " +
		"Seu personagem e seu progresso são os mesmos em todos os modos.", 15, UITheme.DIM))
	var go := UITheme.button("Explorar Valdoria", func() -> void: Lobby.go_world(), 260)
	wv.add_child(go)

	var city_card := _card(right)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	city_card.add_child(cv)
	cv.add_child(UITheme.heading("Defesa da Cidade — em grupo", 26))
	cv.add_child(_wrap("Fundem uma cidade juntos e segurem as hordas noite após noite. O cofre é de todos; " +
		"cada noite vencida dá ouro e XP ao seu personagem, e a cada %d noites (os chefes) um baú de equipamento que fica melhor quanto mais longe o grupo chega." % ColonyData.BOSS_EVERY,
		15, UITheme.TEXT))
	cv.add_child(_wrap("Começo tranquilo, fim de jogo duro: construções repetidas custam cada vez mais, torres pedem " +
		"manutenção, surgem elites que resistem a um tipo de torre (misture as defesas) e noites especiais são avisadas um dia antes.",
		14, UITheme.DIM))
	_record_label = UITheme.label("", 15, UITheme.GOLD)
	cv.add_child(_record_label)
	cv.add_child(UITheme.section("Sala", 18))
	_room_box = VBoxContainer.new()
	_room_box.add_theme_constant_override("separation", 6)
	cv.add_child(_room_box)

	# --- avisos (canto inferior direito; o esquerdo é do chat)
	_feed = VBoxContainer.new()
	_feed.anchor_left = 1.0
	_feed.anchor_right = 1.0
	_feed.anchor_top = 1.0
	_feed.anchor_bottom = 1.0
	_feed.offset_left = -690
	_feed.offset_top = -190
	_feed.offset_right = -50
	_feed.offset_bottom = -30
	_feed.alignment = BoxContainer.ALIGNMENT_END
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main.add_child(_feed)


func _card(parent: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.frame_box(Color(0.05, 0.045, 0.04, 0.88), UITheme.GOLD_DIM, 16))
	parent.add_child(p)
	return p


func _wrap(t: String, size: int, c: Color) -> Label:
	var l := UITheme.label(t, size, c)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 540
	return l


func _zone_text(zone: String) -> String:
	match zone:
		"world":
			return "em Valdoria"
		"city":
			return "na Defesa da Cidade"
	return "no salão"


func _refresh() -> void:
	var me := multiplayer.get_unique_id()
	_header.text = "Conectado como %s  ·  %d online  ·  v%s" % [Network.my_name, Network.players.size(), Network.version()]
	for c in _players_box.get_children():
		c.queue_free()
	var ids: Array = Network.players.keys()
	ids.sort()
	for id in ids:
		var info: Dictionary = Network.players[id]
		var zone := str(info.get("zone", "lobby"))
		var l := UITheme.label("%s%s — %s" % [info.name, " (você)" if id == me else "", _zone_text(zone)], 16,
			UITheme.GOLD if id == me else (UITheme.TEXT if zone == "lobby" else UITheme.DIM))
		_players_box.add_child(l)
	var rec: Dictionary = Lobby.record
	if int(rec.get("day", 0)) > 0:
		_record_label.text = "Recorde do servidor: %d noite(s) — %s" % [int(rec.day), ", ".join(rec.get("names", []))]
	else:
		_record_label.text = "Ninguém defendeu uma cidade neste servidor ainda."
	var best := int(Game.flags.get("city_best", 0))
	if best > 0:
		_record_label.text += "   ·   Seu melhor: %d" % best
	_refresh_room()
	_refresh_result()
	_refresh_knights()


func _refresh_room() -> void:
	for c in _room_box.get_children():
		c.queue_free()
	var r: Dictionary = Lobby.room
	var me := multiplayer.get_unique_id()
	if r.is_empty():
		_room_box.add_child(UITheme.label("Nenhuma sala aberta.", 15, UITheme.DIM))
		_room_box.add_child(UITheme.button("Criar sala", func() -> void: Lobby.room_send("create"), 240))
		return
	var names: Dictionary = r.get("names", {})
	var members: Array = r.get("members", [])
	var ready: Array = r.get("ready", [])
	var leader := int(r.get("leader", 0))
	if r.get("state", "") == "running":
		var phase := str(r.get("phase", ""))
		var where := "noite %d" % int(r.get("day", 1)) if phase == "night" else "dia %d" % int(r.get("day", 1))
		if phase == "setup":
			where = "fundando a cidade"
		var in_city: Array = r.get("in_city", [])
		var who: Array[String] = []
		for id in in_city:
			who.append(str(names.get(id, Network.players.get(id, {}).get("name", "?"))))
		_room_box.add_child(UITheme.label("Partida em andamento — %s (%d/%d): %s" % [where, in_city.size(), int(r.get("max", 6)), ", ".join(who)], 16, UITheme.TEXT))
		var enter := UITheme.button("Entrar na partida", func() -> void: Lobby.room_send("enter"), 240)
		enter.disabled = in_city.size() >= int(r.get("max", 6))
		_room_box.add_child(enter)
		_room_box.add_child(UITheme.label("Quem entra no meio recebe as recompensas das noites que ajudar a vencer.", 13, UITheme.DIM))
		return
	for id in members:
		var tag := "  (líder)" if int(id) == leader else ""
		var ok: bool = id in ready or int(id) == leader
		_room_box.add_child(UITheme.label("%s %s%s" % ["✔" if ok else "…", names.get(id, "?"), tag], 16, UITheme.GOOD if ok else UITheme.DIM))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	_room_box.add_child(h)
	if not Lobby.in_room():
		var join := UITheme.button("Entrar na sala", func() -> void: Lobby.room_send("join"), 200)
		join.disabled = members.size() >= int(r.get("max", 6))
		h.add_child(join)
		return
	if Lobby.is_leader():
		var all_ready := true
		for id in members:
			if int(id) != me and not (id in ready):
				all_ready = false
		var start := UITheme.button("Começar", func() -> void: Lobby.room_send("start"), 160)
		start.disabled = not all_ready
		h.add_child(start)
		if not all_ready:
			_room_box.add_child(UITheme.label("Esperando todos ficarem prontos.", 13, UITheme.DIM))
	else:
		h.add_child(UITheme.button("Não estou pronto" if Lobby.is_ready() else "Estou pronto",
			func() -> void: Lobby.room_send("unready" if Lobby.is_ready() else "ready"), 200))
	h.add_child(UITheme.button("Sair da sala", func() -> void: Lobby.room_send("leave"), 160))


func _refresh_result() -> void:
	var res: Dictionary = Lobby.last_result
	_result_panel.visible = not res.is_empty()
	if res.is_empty():
		return
	for c in _result_panel.get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_result_panel.add_child(v)
	var fell: bool = res.get("reason", "") == "defeat"
	v.add_child(UITheme.heading("Última defesa: %d noite(s)%s" % [int(res.get("nights", 0)), " — a cidade caiu" if fell else ""], 20,
		UITheme.BAD if fell else UITheme.GOLD))
	v.add_child(UITheme.label("Você ganhou +%d ouro e +%d XP." % [int(res.get("gold", 0)), int(res.get("xp", 0))], 15, UITheme.TEXT))
	v.add_child(UITheme.button("Ok", func() -> void:
		Lobby.last_result = {}
		_mark(), 100))


func _on_notify(text: String, color: Color) -> void:
	var l := UITheme.label(text, 15, color)
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 620
	_feed.add_child(l)
	while _feed.get_child_count() > 6:
		_feed.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(7.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)


func _options() -> void:
	_main.visible = false
	var o := OPTIONS.new()
	add_child(o)
	o.closed.connect(func() -> void: _main.visible = true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not _main.visible:
		get_viewport().set_input_as_handled()


# ================================================================ cenário (fogueira com os jogadores do salão)
func _build_backdrop() -> void:
	if DisplayServer.get_name() == "headless":
		return
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
	sm.sky_top_color = Color(0.06, 0.08, 0.2)
	sm.sky_horizon_color = Color(0.55, 0.32, 0.38)
	sm.ground_horizon_color = Color(0.45, 0.28, 0.32)
	sm.ground_bottom_color = Color(0.05, 0.05, 0.05)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.2, 0.15, 0.25)
	env.fog_density = 0.018
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-35, 140, 0)
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.light_energy = 0.9
	root.add_child(moon)

	var ground := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 34
	disc.bottom_radius = 34
	disc.height = 0.1
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.2, 0.3, 0.13)
	disc.material = gm
	ground.mesh = disc
	ground.position.y = -0.05
	root.add_child(ground)

	_pivot = Node3D.new()
	root.add_child(_pivot)
	var fire: Node3D = load("res://assets/models/campfire.glb").instantiate()
	_pivot.add_child(fire)
	var fl := OmniLight3D.new()
	fl.position = Vector3(0, 1.0, 0)
	fl.light_color = Color(1, 0.55, 0.2)
	fl.light_energy = 4.0
	fl.omni_range = 13
	fl.shadow_enabled = true
	_pivot.add_child(fl)
	var tent_c := [Color(0.55, 0.2, 0.15), Color(0.2, 0.3, 0.5), Color(0.5, 0.42, 0.2)]
	for i in 3:
		var a := PI * 0.9 + i * 0.7
		var t := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(3.2, 2.4, 3.4)
		var tm := StandardMaterial3D.new()
		tm.albedo_color = tent_c[i]
		pm.material = tm
		t.mesh = pm
		t.position = Vector3(cos(a) * 8.0, 1.2, sin(a) * 8.0)
		t.rotation.y = -a
		_pivot.add_child(t)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 30:
		var a := rng.randf() * TAU
		var d := rng.randf_range(12, 28)
		var tr: Node3D = load("res://assets/models/tree_pine.glb" if rng.randf() < 0.6 else "res://assets/models/tree_oak.glb").instantiate()
		tr.position = Vector3(cos(a) * d, 0, sin(a) * d)
		tr.scale = Vector3.ONE * rng.randf_range(0.9, 1.7)
		_pivot.add_child(tr)
	var cam := Camera3D.new()
	cam.position = Vector3(-2.0, 3.2, 9.5)
	cam.fov = 50
	root.add_child(cam)
	cam.look_at(Vector3(1.5, 0.9, 0), Vector3.UP)


## Um cavaleiro em volta da fogueira para cada jogador no salão (com o nome em cima).
func _refresh_knights() -> void:
	if _pivot == null:
		return
	var here: Array = []
	for id in Network.players:
		if str(Network.players[id].get("zone", "lobby")) == "lobby":
			here.append(id)
	here.sort()
	for id in _knights.keys():
		if not (id in here):
			_knights[id].queue_free()
			_knights.erase(id)
	for i in here.size():
		var id: int = here[i]
		var k: Node3D = _knights.get(id)
		if k == null:
			k = Node3D.new()
			var m: Node3D = KNIGHT.instantiate()
			k.add_child(m)
			KnightLook.apply(m, Network.players[id].get("look", {}))
			var tag := Label3D.new()
			tag.text = str(Network.players[id].name)
			tag.font_size = 48
			tag.outline_size = 10
			tag.pixel_size = 0.006
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			tag.modulate = Color(1, 0.9, 0.6) if id == multiplayer.get_unique_id() else Color(0.8, 0.9, 1.0)
			tag.position.y = 2.3
			k.add_child(tag)
			_pivot.add_child(k)
			_knights[id] = k
		var a := TAU * i / maxf(1.0, here.size()) + 0.4
		k.position = Vector3(cos(a) * 2.6, 0, sin(a) * 2.6)
		k.rotation.y = atan2(-k.position.x, -k.position.z)
