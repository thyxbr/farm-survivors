extends Node3D
## A praça da cidade (hub.tscn): o ponto de chegada, online e solo, no lugar do antigo salão.
## O cavaleiro anda pela praça sem combate (build_lock + peaceful), vê os outros jogadores com o nome em
## cima (réplicas do Network, zona "hub"), conversa pelo chat e faz emotes (teclas 1–3). Os pontos da praça
## (hub_point.gd) levam à Horda, à Defesa da Cidade, a Valdoria e aos painéis de passivas, doações e recordes.
##
## `role = "hub"` faz o resto do jogo tratar a cena como "fora de Valdoria": o autosave não grava a posição
## da praça, o menu de pausa tem o modo praça e Lobby.in_session() a reconhece. Tudo é montado por código.

const PLAYER := preload("res://scripts/player/player.gd")
const HUD := preload("res://scripts/ui/hub_hud.gd")
const PAUSE := preload("res://scripts/ui/pause_menu.gd")
const CHAT := preload("res://scripts/ui/chat_ui.gd")
const POINT := preload("res://scripts/hub/hub_point.gd")
const SHOP := preload("res://scripts/ui/shop_ui.gd")
const PASSIVE_MASTER := preload("res://scripts/ui/passive_master_ui.gd")
const BASE_BUILDING := preload("res://scripts/ui/base_building_ui.gd")
const RECORDS := preload("res://scripts/ui/records_ui.gd")
const WAR_TABLE := preload("res://scripts/ui/war_table_ui.gd")
const HORDE_PORTAL := preload("res://scripts/ui/horde_portal_ui.gd")
const GROUND := preload("res://scripts/world/ground.gd")
const M := {
	"well": preload("res://assets/models/well.glb"),
	"lamp": preload("res://assets/models/lamp.glb"),
	"house": preload("res://assets/models/house.glb"),
	"tent": preload("res://assets/models/tent.glb"),
	"tree_oak": preload("res://assets/models/tree_oak.glb"),
	"tree_pine": preload("res://assets/models/tree_pine.glb"),
	"tree_birch": preload("res://assets/models/tree_birch.glb"),
	"tree_cherry": preload("res://assets/models/tree_cherry.glb"),
	"tree_maple": preload("res://assets/models/tree_maple.glb"),
	"barrel": preload("res://assets/models/barrel.glb"),
	"crate": preload("res://assets/models/crate.glb"),
	"flower_lavender": preload("res://assets/models/flower_lavender.glb"),
	"flower_tulips": preload("res://assets/models/flower_tulips.glb"),
}

const SPAWN := Vector3(0, 0.5, 12)
## Raio do calçamento da praça e das paredes invisíveis (um pouco de grama em volta fica andável).
const RADIUS := 22.0
const WALL_RADIUS := 25.5
const MAP_HALF := 60.0
## Pontos da praça: [kind, posição, building_id].
const POINTS := [
	["horde_portal", Vector3(0, 0, -18), ""],
	["war_table", Vector3(16, 0, -4), ""],
	["road", Vector3(0, 0, 22), ""],
	["passive_master", Vector3(-14, 0, -6), ""],
	["merchant", Vector3(-12, 0, 8), ""],
	["records", Vector3(6, 0, -10), ""],
	["building", Vector3(-9, 0, -15), "forja"],
	["building", Vector3(9, 0, -15), "muralha"],
	["building", Vector3(15, 0, 9), "celeiro"],
]

var role := "hub"
var player: Player
var hud: CanvasLayer
var ui_layer: CanvasLayer
var chat: CanvasLayer = null
var modal: Control = null
var ground: Node3D
var points: Array = []
var rng := RandomNumberGenerator.new()
var _no_grass: Array = []   # [Vector2 centro, raio]


func _ready() -> void:
	get_tree().paused = false
	Lobby.joining_city = false
	# solo: o personagem vem do save solo (Game.spawn_position sai dele: é a posição em Valdoria)
	if not Network.is_online():
		Econ.ensure_solo()
	rng.seed = 20261114
	WorldLighting.build(self)
	if DisplayServer.get_name() != "headless":
		add_child(WeatherFX.new())   # clima (só visual), o mesmo de Valdoria
	_build_ground()
	_build_square()
	_build_edge()
	_build_points()
	_build_walls()
	_scatter_grass()

	# a posição em Valdoria fica guardada para a estrada; a praça sempre começa no SPAWN
	if Game.spawn_position != null:
		Lobby._last_world_pos = Game.spawn_position
		Lobby._last_world_yaw = Game.spawn_yaw
	Game.spawn_position = null
	player = PLAYER.new()
	player.spawn_point = SPAWN
	player.build_lock = true   # sem atacar, esquivar, conjurar nem beber poção
	player.peaceful = true
	add_child(player)

	hud = HUD.new()
	hud.player = player
	add_child(hud)
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui_layer)
	if Network.is_client():
		chat = CHAT.new()
		chat.world = self
		add_child(chat)
		Game.notify.emit("Bem-vindo à praça, %s — %d jogador(es) online." % [Network.my_name, Network.players.size()],
			Color(0.6, 0.9, 1.0))
	Hub.enter(self)   # online: Network.hub_ready + _enter_hub (zona "hub"); solo: base e recordes locais
	# depuração/screenshot: `--emote=sentar` faz o emote logo depois de nascer (junto com --shot e --cam)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--emote="):
			await get_tree().create_timer(1.0).timeout
			player.play_emote(a.substr(8))


func _exit_tree() -> void:
	Network.world_closed(self)


# ================================================================ cenário
func _build_ground() -> void:
	ground = GROUND.new()
	add_child(ground)
	ground.setup(MAP_HALF)
	ground.border_mountains(34.0)   # serra ao longe (só visual)
	ground.build_terrain()
	ground.add_disc(Vector3(0, 0.02, 0), RADIUS, Color(0.56, 0.54, 0.5), 0.6)        # calçamento
	ground.add_disc(Vector3(0, 0.023, 0), 14.0, Color(0.5, 0.48, 0.45), 0.25)        # anel interno
	ground.add_disc(Vector3(0, 0.024, 0), 12.5, Color(0.58, 0.56, 0.52), 0.25)
	ground.add_disc(Vector3(0, 0.025, 0), 6.0, Color(0.47, 0.45, 0.42), 0.3)         # anel do poço
	ground.add_rect(Vector3(0, 0.022, 38), Vector2(4.5, 34), Color(0.45, 0.35, 0.22)) # estrada sul
	ground.add_disc(Vector3(0, 0.024, -18), 3.5, Color(0.4, 0.36, 0.42), 0.4)        # chão do portal


func _prop(model: String, pos: Vector3, yaw := 0.0, s := 1.0, shape := "", size := Vector3.ONE) -> Node3D:
	var inst: Node3D = M[model].instantiate()
	inst.position = pos
	inst.rotation.y = yaw
	inst.scale = Vector3.ONE * s
	add_child(inst)
	if shape != "":
		_no_grass.append([Vector2(pos.x, pos.z), (maxf(size.x, size.z) * 0.5 if shape == "box" else size.x) * s + 0.2])
		var body := StaticBody3D.new()
		body.position = pos
		body.rotation.y = yaw
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var sz := size * s
		if shape == "box":
			var b := BoxShape3D.new()
			b.size = sz
			cs.shape = b
		else:
			var c := CylinderShape3D.new()
			c.radius = sz.x
			c.height = sz.y
			cs.shape = c
		cs.position.y = sz.y / 2.0
		body.add_child(cs)
		add_child(body)
	return inst


func _lamp(p: Vector3) -> void:
	var lamp := _prop("lamp", p, atan2(-p.x, -p.z), 1.0, "cyl", Vector3(0.12, 2.8, 0))
	var l := OmniLight3D.new()
	l.position = Vector3(0, 2.4, 0.5)
	l.light_color = Color(1, 0.75, 0.4)
	l.light_energy = 1.4
	l.omni_range = 8.0
	lamp.add_child(l)


## Poço no centro, lampiões em dois anéis e canteiros de flores em volta do poço.
func _build_square() -> void:
	_prop("well", Vector3.ZERO, 0.0, 1.0, "cyl", Vector3(0.95, 1.2, 0))
	for i in 4:
		var a := TAU * (i + 0.5) / 4.0
		_lamp(Vector3(sin(a), 0, cos(a)) * 6.5)
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		var p := Vector3(sin(a), 0, cos(a)) * 19.5
		if absf(p.x) < 3.0 and p.z > 0:
			continue   # saída da estrada
		_lamp(p)
	for i in 12:
		var a := TAU * i / 12.0 + 0.13
		var kind := "flower_lavender" if i % 2 == 0 else "flower_tulips"
		_prop(kind, Vector3(sin(a), 0, cos(a)) * rng.randf_range(3.2, 3.8), rng.randf() * TAU, rng.randf_range(0.9, 1.2))


## Casas, tendas e árvores em volta da praça (fora das paredes invisíveis), viradas para o centro.
func _build_edge() -> void:
	var a := 0.0
	var i := 0
	while a < TAU - 0.05:
		var d := Vector3(sin(a), 0, cos(a))
		var road := absf(wrapf(a, -PI, PI)) < 0.32
		if not road:
			var p := d * rng.randf_range(29.0, 31.0)
			var yaw := atan2(-d.x, -d.z)
			match i % 4:
				0, 2:
					_prop("house", p, yaw + rng.randf_range(-0.15, 0.15), 1.0, "box", Vector3(5.2, 3.2, 4.2))
				1:
					_prop("tent", d * 27.5, yaw, 1.1, "box", Vector3(2.0, 2.2, 2.0))
					_prop("barrel", d * 27.5 + Vector3(d.z, 0, -d.x) * 1.8, 0.0)
				3:
					_prop("tree_cherry" if rng.randf() < 0.5 else "tree_maple", d * 28.0, rng.randf() * TAU,
						rng.randf_range(0.9, 1.2), "cyl", Vector3(0.4, 3, 0))
		a += 0.29
		i += 1
	# bosque atrás das casas
	for n in 70:
		var b := rng.randf() * TAU
		if absf(wrapf(b, -PI, PI)) < 0.35:
			continue
		var p := Vector3(sin(b), 0, cos(b)) * rng.randf_range(35.0, 55.0)
		var kinds := ["tree_oak", "tree_pine", "tree_birch", "tree_pine"]
		_prop(kinds[n % kinds.size()], p, rng.randf() * TAU, rng.randf_range(0.9, 1.5))
	# árvores dos dois lados da estrada
	for z in [30.0, 37.0, 44.0, 51.0]:
		for x in [-5.0, 5.0]:
			_prop("tree_oak" if int(z) % 2 == 0 else "tree_birch", Vector3(x + rng.randf_range(-0.8, 0.8), 0, z),
				rng.randf() * TAU, rng.randf_range(0.9, 1.2))


func _build_points() -> void:
	for d in POINTS:
		var pt := POINT.new()
		pt.kind = d[0]
		pt.building_id = d[2]
		var pos: Vector3 = d[1]
		pt.position = pos
		pt.rotation.y = atan2(-pos.x, -pos.z)   # a frente (+Z) virada para o centro da praça
		add_child(pt)
		points.append(pt)
		_no_grass.append([Vector2(pos.x, pos.z), 3.0])
	# a banca do mercador ganha uns caixotes a mais em volta
	_prop("crate", Vector3(-14.2, 0, 9.5), 0.3, 1.0, "box", Vector3(0.8, 0.8, 0.8))
	_prop("barrel", Vector3(-13.6, 0, 6.4), 0.0, 1.0, "cyl", Vector3(0.38, 1.0, 0))


## Paredes invisíveis num anel em volta da praça (a estrada viaja pela placa, não andando).
func _build_walls() -> void:
	var n := 40
	for i in n:
		var a := TAU * i / n
		var body := StaticBody3D.new()
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(TAU * WALL_RADIUS / n + 0.6, 6.0, 1.0)
		cs.shape = b
		cs.position.y = 3.0
		body.add_child(cs)
		body.position = Vector3(sin(a), 0, cos(a)) * WALL_RADIUS
		body.rotation.y = a
		add_child(body)


func _scatter_grass() -> void:
	var keep := _no_grass.duplicate()
	keep.append([Vector2.ZERO, RADIUS + 0.5])
	for z in range(22, 58, 4):
		keep.append([Vector2(0, z), 3.0])   # estrada
	ground.scatter_grass(rng.seed + 7, 0.55, keep, [])


# ================================================================ painéis dos pontos
## Abre o painel do ponto da praça (portal, mesa de guerra, mestre das passivas, mercador, recordes ou
## doações da construção). A estrada não tem painel: ela viaja direto (hub_point.interact).
func open_point_panel(point: Node) -> void:
	var ui: Control = null
	match str(point.get("kind")):
		"horde_portal":
			ui = HORDE_PORTAL.new()
		"war_table":
			ui = WAR_TABLE.new()
		"passive_master":
			ui = PASSIVE_MASTER.new()
		"merchant":
			var shop := SHOP.new()
			shop.title = "Banca do Tobias"
			shop.quote = "\"Compro o que você achar por aí e vendo o que um aventureiro precisa. Dê uma olhada!\""
			ui = shop
		"records":
			ui = RECORDS.new()
		"building":
			var b := BASE_BUILDING.new()
			b.building_id = str(point.get("building_id"))
			ui = b
	if ui != null:
		open_modal(ui)


# ================================================================ UI modal
func _unhandled_input(event: InputEvent) -> void:
	if modal != null or player == null:
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		var p := PAUSE.new()
		p.mode = "pause"
		open_modal(p)
		return
	for i in KnightEmotes.KINDS.size():
		if event.is_action_pressed("spell_%d" % (i + 1)):
			get_viewport().set_input_as_handled()
			player.play_emote(KnightEmotes.KINDS[i])
			return


func open_modal(ui: Control) -> void:
	if modal != null:
		return
	modal = ui
	ui_layer.add_child(ui)
	if ui.has_signal("closed"):
		ui.closed.connect(_on_modal_closed)
	_set_paused(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.visible = false


## Online o mundo não para: só o controle do jogador trava (como em Valdoria).
func _set_paused(on: bool) -> void:
	if Network.is_online():
		if player:
			player.input_locked = on
	else:
		get_tree().paused = on


func _on_modal_closed() -> void:
	modal = null
	_set_paused(false)
	hud.visible = true
	if player and not player.dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
