extends Node3D
## Monta o mundo (vila, campos, acampamento goblin, ruínas), gerencia inimigos, UI modal e morte.
## A vila é o ponto de chegada (online e solo): a antiga praça da cidade deixou de existir e os pontos dela
## (Mestre Orin, mesa de guerra, recordes e as construções da base) ficam nas ruas novas (VillageLayout).

const M := {
	"house": preload("res://assets/models/house.glb"),
	"house_b": preload("res://assets/models/house_b.glb"),
	"house_c": preload("res://assets/models/house_c.glb"),
	"house_d": preload("res://assets/models/house_d.glb"),
	"house_e": preload("res://assets/models/house_e.glb"),
	"house_f": preload("res://assets/models/house_f.glb"),
	"shop_smithy": preload("res://assets/models/shop_smithy.glb"),
	"shop_alchemist": preload("res://assets/models/shop_alchemist.glb"),
	"shop_merchant": preload("res://assets/models/shop_merchant.glb"),
	"shop_workshop": preload("res://assets/models/shop_workshop.glb"),
	"shop_alchemy_lab": preload("res://assets/models/shop_alchemy_lab.glb"),
	"stall_cloth": preload("res://assets/models/stall_cloth.glb"),
	"stall_farm": preload("res://assets/models/stall_farm.glb"),
	"stall_goods": preload("res://assets/models/stall_goods.glb"),
	"tree_pine": preload("res://assets/models/tree_pine.glb"),
	"tree_oak": preload("res://assets/models/tree_oak.glb"),
	"tree_fir": preload("res://assets/models/tree_fir.glb"),
	"tree_birch": preload("res://assets/models/tree_birch.glb"),
	"tree_maple": preload("res://assets/models/tree_maple.glb"),
	"tree_cherry": preload("res://assets/models/tree_cherry.glb"),
	"tree_apple": preload("res://assets/models/tree_apple.glb"),
	"tree_orange": preload("res://assets/models/tree_orange.glb"),
	"tree_pear": preload("res://assets/models/tree_pear.glb"),
	"notice_board": preload("res://assets/models/notice_board.glb"),
	"flower_sunflower": preload("res://assets/models/flower_sunflower.glb"),
	"flower_lavender": preload("res://assets/models/flower_lavender.glb"),
	"flower_tulips": preload("res://assets/models/flower_tulips.glb"),
	"rock": preload("res://assets/models/rock.glb"),
	"fern": preload("res://assets/models/fern.glb"),   # margem da lagoa do oeste
	"well": preload("res://assets/models/well.glb"),
	"fence": preload("res://assets/models/fence.glb"),
	"ruin_pillar": preload("res://assets/models/ruin_pillar.glb"),
	"ruin_wall": preload("res://assets/models/ruin_wall.glb"),
	"crate": preload("res://assets/models/crate.glb"),
	"barrel": preload("res://assets/models/barrel.glb"),
	"lamp": preload("res://assets/models/lamp.glb"),
	"campfire": preload("res://assets/models/campfire.glb"),
	"tent": preload("res://assets/models/tent.glb"),
	"chest": preload("res://assets/models/chest.glb"),
	"anvil": preload("res://assets/models/anvil.glb"),
	"forge": preload("res://assets/models/forge.glb"),
}
const ENEMY := preload("res://scripts/enemies/enemy.gd")
const BLACKSMITH := preload("res://scripts/world/blacksmith.gd")
const SIGNPOST := preload("res://scripts/world/signpost.gd")
const ELDER := preload("res://scripts/world/elder.gd")
const MERCHANT := preload("res://scripts/world/merchant.gd")
const SANTA := preload("res://scripts/world/santa.gd")
const EVENT_POINT := preload("res://scripts/world/christmas_event_point.gd")
const POINT := preload("res://scripts/hub/hub_point.gd")
const PASSIVE_MASTER := preload("res://scripts/ui/passive_master_ui.gd")
const RECORDS := preload("res://scripts/ui/records_ui.gd")
const ALCHEMIST := preload("res://scripts/world/alchemist.gd")
const RIVAL := preload("res://scripts/world/rival.gd")
const PLAYER := preload("res://scripts/player/player.gd")
const HUD := preload("res://scripts/ui/hud.gd")
const DIALOGUE := preload("res://scripts/ui/dialogue_ui.gd")
const GAME_MENU := preload("res://scripts/ui/game_menu.gd")
const SHOP := preload("res://scripts/ui/shop_ui.gd")
const ENCHANT_UI := preload("res://scripts/ui/enchant_ui.gd")
const PAUSE := preload("res://scripts/ui/pause_menu.gd")
const PORTAL := preload("res://scripts/world/challenge_portal.gd")
const SURVIVAL := preload("res://scripts/survival/survival_mode.gd")
const HORDE_INVITE := preload("res://scripts/ui/horde_invite_ui.gd")
const CHAT := preload("res://scripts/ui/chat_ui.gd")
const PLOT := preload("res://scripts/farm/farm_plot.gd")
const KITCHEN := preload("res://scripts/farm/kitchen.gd")
const PLANT_UI := preload("res://scripts/ui/plant_ui.gd")
const COOKING_UI := preload("res://scripts/ui/cooking_ui.gd")
const CRAFTING_STATION := preload("res://scripts/world/crafting_station.gd")
const DUNGEON_DOOR := preload("res://scripts/world/dungeon_door.gd")
const WORLD_MAP_UI := preload("res://scripts/ui/world_map_ui.gd")
const WORLD_ATLAS_UI := preload("res://scripts/ui/world_atlas_ui.gd")

## Meia largura do vale (os testes conferem que a Arena fica fora dele).
const MAP_HALF := 125.0
## Lugares com nome dos mapas: vêm dos landmarks das cenas (MapLandmark: village_spawn, ruins, camp, portal,
## horde_return, farm, nest, orchard, pond no vale) e da raiz da Arena quando os mapas são montados; os valores
## abaixo só valem antes disso.
var VILLAGE_SPAWN := Vector3(0, 0.3, 116)
var RUINS := Vector3(0, 0, -100)
var CAMP := Vector3(86, 0, 0)
## Arena do Desafio da Horda: mapa próprio (scenes/maps/arena.tscn), longe ao norte, fora de Valdoria.
var ARENA := Vector3(0, 0, -1000)
## Metade do lado do chão da arena (MapRoot.half da cena da Arena).
var ARENA_HALF := 70.0
var PORTAL_POS := Vector3(-28, 0, 54)
## Onde o jogador volta ao fim do Desafio: na frente do portal da vila.
var HORDE_RETURN := Vector3(-28, 0.5, 57.5)
var FARM := Vector3(-18, 0, 33)        # Horta da Vila (saída norte)
var NEST := Vector3(-60, 0, 46)        # Ninho de Slimes (noroeste da vila)
## Lagoa do oeste, casa dos Bocarrões.
var POND := Vector3(-80, 0, 15)
var ORCHARD := Vector3(20, 0, 33)      # pomar do outro lado da estrada, na frente da Horta

var player: Player
var hud
var ui_layer: CanvasLayer
var modal: Control = null
var dock: WindowDock
var boss: Enemy = null
var survival: Node3D = null
var chat: CanvasLayer = null
## Cartões de título dos episódios da história (StoryCard).
var story_card: StoryCard = null
## Fotos de cima de cada mapa (minimapa e mapa-mundi); null no servidor dedicado.
var map_capture: MapCapture = null
## Mapas fora do vale (RegionBuilder): chão de cada um e os pontos de nascimento dos monstros deles.
var region_grounds := {}
var region_spawns: Array = []
var _boss_scan := 0.0
var _travel_fade: ColorRect
## Destino da viagem paga esperando a confirmação do servidor/solo ("" = nenhuma).
var _travel_pending := ""
var spawns: Array = []
## Sorteio do nível de quem nasce nos pontos (à parte do `rng` fixo do cenário).
var _spawn_rng := RandomNumberGenerator.new()
## Pontos que vieram da praça (hub_point.gd): construções da base, Mestre Orin, mesa de guerra, recordes.
var points: Array = []
## Lugares com nome dos mapas (MapLandmark): id -> posição (vale) e "mapa:id" -> posição (todos).
var landmarks := {}
## Áreas do capim lidas das cenas (MapGrassArea), por mapa: {"keep_out": [...], "sparse": [...]} (mundo).
var grass_areas := {}
## Raiz da cena de cada mapa já montado (MapLoader): map_id -> MapRoot.
var maps := {}
var santa: Node3D = null
## Veios de ferro e cristais arcanos (WorldResourceNode); vazio no servidor dedicado.
var resource_nodes: Array = []
## Nós de coleta por id (Econ.node_gone esconde pelo id) e numa grade de HARVEST_CELL m (busca de F perto do jogador).
var resource_by_id := {}
var harvest_grid := {}
const HARVEST_CELL := 8.0
## Árvores do mapa montadas pelo MapLoader, pelo lugar (MapLoader.tree_key): viram nós de coleta.
var tree_props := {}
var flicker_lights: Array = []
var rng := RandomNumberGenerator.new()
var _night_scan := 0.0      # tempo até a próxima conferida de dia/noite (bichos noturnos)
var _is_night_now := false
var _no_grass: Array = []   # [Vector2 centro, raio] pegadas de props (o capim não atravessa)
var ground: Node3D
var _t := 0.0
## O mapa terminou de montar (a tela de carregamento espera por isto antes de abrir).
var built := false
var _step_from := 0.0   # faixa da barra de carregamento da etapa em andamento
var _step_to := 0.0


func _ready() -> void:
	# solo: o personagem vem do save solo (antes de montar o mapa: o chefe depende dos flags)
	if not Network.is_online():
		Econ.ensure_solo()
	rng.seed = 20261113
	# Atrás da tela de carregamento o mapa é montado em etapas, uma por quadro (a tela não congela e a
	# barra anda de verdade). Sem a tela (testes, servidor, cena aberta direto) monta tudo de uma vez.
	var staged: bool = Loading.covering
	if staged:
		process_mode = Node.PROCESS_MODE_DISABLED   # nada do mapa processa pela metade, sem o jogador
	# [etapa, peso na barra] — o peso acompanha o tempo medido de cada uma (o capim é a mais demorada)
	var steps := [[_build_environment, 2.0], [_load_vale, 6.0], [_load_arena, 0.5], [_build_regions, 2.0],
		[_scatter_grass, 7.0], [_scatter_region_grass, 3.0]]
	if not Network.is_client():
		steps.append([_setup_enemies, 2.0])   # no cliente, os inimigos chegam do servidor
	var total := 1.0   # o que sobra depois das etapas: jogador e HUD
	for st in steps:
		total += st[1]
	var done := 0.0
	for st in steps:
		_step_from = done / total
		done += st[1]
		_step_to = done / total
		await st[0].call()   # só o capim espera quadros (e só atrás da tela); o resto volta na hora
		if staged:
			if not is_inside_tree():
				return   # trocaram de cena no meio da montagem
			Loading.set_progress(_step_to)
			await get_tree().process_frame
			if not is_inside_tree():
				return
	if Network.is_server():
		# servidor dedicado: só o mundo, os inimigos e as réplicas dos jogadores
		built = true
		Network.world_ready(self)
		return

	_setup_resource_nodes()
	player = PLAYER.new()
	# personagem novo (ou sem lugar salvo) chega pela estrada do sul, olhando para a vila
	player.spawn_point = VILLAGE_SPAWN + Vector3(0, 0.2, 0)
	add_child(player)
	player.died.connect(_on_player_died)

	hud = HUD.new()
	hud.player = player
	add_child(hud)
	map_capture = MapCapture.new()
	add_child(map_capture)
	hud.add_minimap(self, map_capture)
	map_capture.texture(Regions.region_at(player.global_position))   # foto do mapa ainda atrás do carregamento
	story_card = StoryCard.new()
	story_card.world = self
	add_child(story_card)
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui_layer)
	dock = WindowDock.new()
	dock.world = self
	ui_layer.add_child(dock)

	Game.quests_changed.connect(_check_boss)
	_check_boss()
	if Game.quests.is_empty() and Game.kills == 0:
		Game.notify.emit("Bem-vindo a Valdoria! Fale com o Ancião Bram (!) perto do poço.", Color(1, 0.9, 0.6))
		_play_intro()
	if Game.quest_state("natal_presentes") == "none":
		Game.notify.emit("O Papai Noel chegou a Valdoria! Procure o trenó ao lado da árvore de Natal.", Color(1, 0.55, 0.45))
	if Network.is_client():
		var invite := HORDE_INVITE.new()
		invite.world = self
		add_child(invite)
		chat = CHAT.new()
		chat.world = self
		add_child(chat)
		Game.notify.emit("Conectado como %s — %d jogador(es) online." % [Network.my_name, Network.players.size()], Color(0.6, 0.9, 1.0))
		Network.world_ready(self)
	Hub.enter()   # solo: base e recordes do save local (online o servidor manda no _client_ready)
	if staged:
		process_mode = Node.PROCESS_MODE_INHERIT
		Loading.set_progress(1.0)
	built = true


func _exit_tree() -> void:
	Network.world_closed(self)


# ================================================================ ambiente
func _build_environment() -> void:
	WorldLighting.build(self)
	if DisplayServer.get_name() != "headless":
		add_child(WeatherFX.new())   # clima (só visual)
		add_child(DayNightFX.new())  # dia e noite por cima do clima (só visual)


## Instancia um modelo e (opcionalmente) uma colisão simples ("box" ou "cyl").
func prop(model: String, pos: Vector3, yaw := 0.0, s := 1.0, shape := "", size := Vector3.ONE) -> Node3D:
	var inst: Node3D = M[model].instantiate()
	inst.position = pos
	inst.rotation.y = yaw
	inst.scale = Vector3.ONE * s
	add_child(inst)
	if shape != "" and model != "fence":
		var foot: float = (maxf(size.x, size.z) * 0.5 if shape == "box" else size.x) * s
		_no_grass.append([Vector2(pos.x, pos.z), foot + 0.15])
	if shape != "":
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


func _light(parent: Node3D, local: Vector3, color: Color, energy: float, rng_range: float, flicker := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = local
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng_range
	l.shadow_enabled = false
	parent.add_child(l)
	if flicker:
		flicker_lights.append([l, energy, randf() * 10.0])
	return l


# ================================================================ vale (scenes/maps/vale.tscn)
## O vale vem da cena (MapLoader): chão, objetos, luzes, enfeites, NPCs, pontos, monstros e lugares. As
## construções da vila (VillageBuilding) montam aqui as casas e lojas, com os donos e as portas do Natal.
func _load_vale() -> void:
	maps["vila"] = MapLoader.build(self, "vila")
	VILLAGE_SPAWN = landmarks.get("village_spawn", VILLAGE_SPAWN)
	RUINS = landmarks.get("ruins", RUINS)
	CAMP = landmarks.get("camp", CAMP)
	PORTAL_POS = landmarks.get("portal", PORTAL_POS)
	FARM = landmarks.get("farm", FARM)
	NEST = landmarks.get("nest", NEST)
	ORCHARD = landmarks.get("orchard", ORCHARD)
	HORDE_RETURN = landmarks.get("horde_return", HORDE_RETURN)
	POND = landmarks.get("pond", POND)
	_build_buildings()
	_build_doors()


## A Arena do Desafio da Horda: mapa à parte (scenes/maps/arena.tscn), com chão e paredes próprios.
func _load_arena() -> void:
	var root := MapLoader.build(self, "arena")
	maps["arena"] = root
	if root != null:
		ARENA = root.position
		ARENA_HALF = root.half


## Entregas na Vila: um ponto na porta de cada casa marcada com "delivery" (VillageLayout.deliveries()).
func _build_doors() -> void:
	var doors := VillageLayout.deliveries()
	for i in doors.size():
		var h: Dictionary = doors[i]
		var d: Array = ChristmasDecor.HOUSE_DOORS[h.model]
		var e := EVENT_POINT.new()
		e.kind = "door"
		e.index = i
		e.position = VillageLayout.xform(h) * Vector3(d[0], 0, d[2] + 0.7)
		add_child(e)


# ================================================================ vila (montagem antiga, sai na limpeza)
## Construções do vale.tscn (VillageLayout.buildings(), editada no 3D do Godot): o poço, as lojas
## com os donos na frente e as casas com cores, pisca-pisca, guirlanda, luz da janela e canteiro.
func _build_buildings() -> void:
	var n_house := 0
	for b: Dictionary in VillageLayout.buildings():
		var model: String = b.model
		var xf := VillageLayout.xform(b)
		if model == "well":
			prop("well", b.pos, b.yaw, 1.0, "cyl", Vector3(0.95, 1.2, 0))
		elif VillageLayout.is_shop(model):
			var sh: Array = VillageLayout.SHOP_SHAPES[model]
			_shop(model, b.pos, b.yaw, sh[0], sh[1], sh[2])
			_shop_keeper(model, xf)
		else:
			_house(b, xf, n_house)
			n_house += 1


## Casa: modelo pintado com a paleta, colisão, enfeites de Natal, luz da janela à noite e canteiro de flores.
func _house(b: Dictionary, xf: Transform3D, i: int) -> void:
	var model: String = b.model
	var size: Vector3 = VillageLayout.HOUSE_SIZE[model]
	var hn := prop(model, b.pos, b.yaw, 1.0, "box", size)
	VillageLayout.tint(hn, b.palette)
	ChristmasDecor.house_lights(hn, model, i)
	var d: Array = ChristmasDecor.HOUSE_DOORS[model]
	ChristmasDecor.wreath(hn, Vector3(d[0], d[1], d[2]))
	DayNightFX.night_light(_light(hn, Vector3(0, 1.6, size.z * 0.5 + 1.2), Color(1, 0.72, 0.42), 0.9, 5.5), 0.9)
	if b.flowers == 1:   # um vaso de cada lado da porta
		for off in [-1.6, 1.6]:
			if absf(off - float(d[0])) < 0.9:
				continue
			var kind := "flower_lavender" if (i + int(off)) % 2 == 0 else "flower_tulips"
			prop(kind, xf * Vector3(off, 0, size.z * 0.5 + 0.55), rng.randf() * TAU, rng.randf_range(0.85, 1.1))
	elif b.flowers == 2:   # quatro flores sorteadas, duas de cada lado da porta
		for off in [-2.2, -1.5, 1.5, 2.2]:
			var kind := "flower_lavender" if rng.randf() < 0.5 else "flower_tulips"
			var fp: Vector3 = xf * Vector3(off + rng.randf_range(-0.15, 0.15), 0, 2.75)
			prop(kind, fp, rng.randf() * TAU, rng.randf_range(0.9, 1.2))


## O ferreiro na ferraria (a origem da ferraria é o lugar dele; a bigorna e a forja ficam em volta). A Mira e a
## Pip são nós próprios na cena (MapEntity merchant/alchemist), que se movem à parte da loja.
func _shop_keeper(model: String, xf: Transform3D) -> void:
	var yaw := xf.basis.get_euler().y
	match model:
		"shop_smithy":
			var smith := BLACKSMITH.new()
			smith.position = xf.origin
			smith.rotation.y = yaw
			smith.anvil = prop("anvil", xf * BLACKSMITH.ANVIL_OFFSET, yaw + BLACKSMITH.ANVIL_YAW, 1.0,
				"cyl", Vector3(0.3, 0.8, 0))
			prop("forge", xf * BLACKSMITH.FORGE_OFFSET, yaw + BLACKSMITH.FORGE_YAW, 1.0,
				"box", Vector3(0.9, 1.0, 0.8))
			_forge_fire(xf * BLACKSMITH.FORGE_OFFSET)
			add_child(smith)


## Loja da vila: modelo + colisões simples no espaço dela (boxes = [[centro local, tamanho]],
## cyls = [[centro local, raio]]) e um círculo sem capim de raio grass_r (0 = nenhum).
func _shop(model: String, pos: Vector3, yaw: float, boxes: Array, cyls: Array, grass_r: float) -> void:
	prop(model, pos, yaw)
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
	if grass_r > 0.0:
		_no_grass.append([Vector2(pos.x, pos.z), grass_r])
	for b in boxes:
		var size: Vector3 = b[1]
		var shape := BoxShape3D.new()
		shape.size = size
		_static_shape(xf, b[0] + Vector3(0, size.y / 2.0, 0), shape)
	for c in cyls:
		var shape := CylinderShape3D.new()
		shape.radius = c[1]
		shape.height = 1.2
		_static_shape(xf, c[0] + Vector3(0, 0.6, 0), shape)


func _static_shape(xf: Transform3D, local: Vector3, shape: Shape3D) -> void:
	var body := StaticBody3D.new()
	body.transform = Transform3D(xf.basis, xf * local)
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


## Crepitar de fogo em loop na boca da forja, só ouvido de perto (bus Ambience). Nada no servidor.
func _forge_fire(pos: Vector3) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var fire: AudioStreamOggVorbis = load("res://assets/audio/ambience/fire_crackle.ogg")
	fire.loop = true
	var p := AudioStreamPlayer3D.new()
	p.name = "ForgeFire"
	p.stream = fire
	p.bus = &"Ambience"
	p.position = pos + Vector3.UP * 0.6
	p.unit_size = 2.5
	p.max_distance = 14.0
	p.volume_db = 2.0
	p.autoplay = true
	add_child(p)


# ================================================================ horta da vila
# ================================================================ campos (slimes)
# ================================================================ acampamento goblin
# ================================================================ ruínas (chefe)
# ================================================================ Arena do Desafio (mapa da Horda)
func start_survival() -> void:
	if not Game.HORDE_ENABLED:
		return
	if survival != null or player == null or player.dead:
		return
	if Network.is_online():
		# abre a fila no servidor: os outros jogadores recebem o convite e entram juntos
		Network.request_horde()
		return
	survival = SURVIVAL.new()
	survival.world = self
	survival.player = player
	survival.center = ARENA
	add_child(survival)
	Sfx.play("portal", 0.0, -3.0)


## Multiplayer (cliente): o servidor fechou a fila; entra na arena com o grupo.
func start_survival_net(team: Dictionary, slot: int, round_time: float) -> void:
	if survival != null or player == null:
		return
	close_ui()
	if player.dead:
		player.revive(ARENA)
	survival = SURVIVAL.new()
	survival.role = "client"
	survival.world = self
	survival.player = player
	survival.center = ARENA
	survival.team = team
	survival.my_slot = slot
	survival.round_time = round_time
	add_child(survival)
	Sfx.play("portal", 0.0, -3.0)


## Multiplayer (servidor): cria a partida do grupo (rodadas, spawn e abates ficam aqui).
func server_start_horde(team: Dictionary, round_time: float) -> Node:
	survival = SURVIVAL.new()
	survival.role = "server"
	survival.world = self
	survival.center = ARENA
	survival.team = team
	survival.round_time = round_time
	add_child(survival)
	return survival


# ================================================================ bordas e vegetação
## Capim e flores (fora das trilhas pintadas, das pegadas de props e da arena).
func _scatter_grass() -> void:
	if Network.is_server():
		return   # grama é só visual
	var root: MapRoot = maps["vila"]
	var keep_out := _no_grass.duplicate()
	keep_out.append_array(grass_areas["vila"].keep_out)
	var sparse: Array = grass_areas["vila"].sparse
	if Loading.covering:
		# fileira por fileira, um quadro cada: é a etapa mais demorada da montagem
		await ground.scatter_grass(root.grass_seed, root.grass_density, keep_out, sparse, root.grass_plants,
			func(frac: float) -> void: Loading.set_progress(lerpf(_step_from, _step_to, frac)))
	else:
		ground.scatter_grass(root.grass_seed, root.grass_density, keep_out, sparse, root.grass_plants)


# ================================================================ veios e cristais
## Veios, cristais e todas as árvores (posições nas cenas dos mapas, tipos em data/balance/world_nodes.json). Os nós
## são do mundo: quem coleta primeiro leva e o nó some para todos (Econ.node_gone; quem entra recebe os esgotados).
func _setup_resource_nodes() -> void:
	for i in WorldHarvest.ids(Balance.tables):
		var def := WorldHarvest.node_def(Balance.tables, i)
		if def.is_empty():
			continue
		var n := WorldResourceNode.from_def(def)
		if n.prop:
			var p: Node3D = tree_props.get(MapLoader.tree_key(def.pos))
			if p == null:
				n.free()   # árvore de um mapa que não foi montado aqui
				continue
			n.attach_prop(p)
		add_child(n)
		resource_nodes.append(n)
		resource_by_id[n.node_id] = n
		var cell := _harvest_cell(n.position)
		if not harvest_grid.has(cell):
			harvest_grid[cell] = []
		harvest_grid[cell].append(n)
		var down := Econ.node_down_for(n.node_id)
		if down > 0.0:
			n.deplete(down)


func _harvest_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / HARVEST_CELL), floori(p.z / HARVEST_CELL))


## Nós de coleta nas células em volta de `p` (o alcance de F é bem menor que uma célula).
func harvest_near(p: Vector3) -> Array:
	var c := _harvest_cell(p)
	var out: Array = []
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			out.append_array(harvest_grid.get(c + Vector2i(dx, dz), []))
	return out


# ================================================================ inimigos
func _setup_enemies() -> void:
	# os pontos do vale já estão em spawns (MapLoader, cena do vale); as regiões trazem os delas
	spawns.append_array(region_spawns)
	var night := is_night()
	for s in spawns:
		if s.get("night", false) and not night:
			s.timer = 3.0   # bicho da noite: espera escurecer
			continue
		if s.has("dungeon") and int(s.slot) >= int(s.base):
			s.timer = DUNGEON_RECHECK   # só nasce com mais jogadores dentro (DungeonRules.population)
			continue
		_spawn(s)


func _spawn(entry: Dictionary) -> void:
	var e := ENEMY.new()
	e.kind = entry.kind
	e.elite = entry.get("elite", false)
	e.area = str(entry.get("area", ""))
	e.chief = bool(entry.get("chief", false))
	e.arena = entry.get("arena", Rect2())
	e.level = ProgressionRules.spawn_level(Balance.tables, entry.get("level", 0), entry.get("level_max", 0), e.elite, _spawn_rng)
	e.position = entry.pos + Vector3.UP * 0.2
	add_child(e)
	entry.node = e
	e.died.connect(_on_spawn_died.bind(entry))


func _on_spawn_died(_en: Enemy, entry: Dictionary) -> void:
	entry.node = null
	entry.timer = entry.respawn
	if entry.has("dungeon"):
		entry.timer = DungeonRules.respawn(Balance.tables, float(entry.respawn), _dungeon_players(str(entry.dungeon)),
			bool(entry.get("boss", false)))


## Dungeons: quantos jogadores há dentro de cada uma (recontado a cada DUNGEON_RECHECK s).
const DUNGEON_RECHECK := 2.0
var _dungeon_count := {}
var _dungeon_t := 0.0


func _dungeon_players(dungeon: String) -> int:
	return int(_dungeon_count.get(dungeon, 0))


func _count_dungeon_players() -> void:
	var pos: Array = []
	for p in get_tree().get_nodes_in_group("players"):
		pos.append((p as Node3D).global_position)
	_dungeon_count = {}
	for d in Regions.DUNGEONS:
		_dungeon_count[d] = DungeonRules.players_in(d, pos)


## Lacaios do chefe enfurecido (Rei Goblin, Lich): nascem no nível de quem invocou.
func summon_minions(pos: Vector3, n: int, kind := "goblin", level := 0) -> void:
	for i in n:
		var e := ENEMY.new()
		e.kind = kind
		e.level = level
		e.position = pos + Vector3(cos(i * PI) * 4.0, 0.3, sin(i * PI + 0.5) * 4.0)
		add_child(e)
		FX.burst(e.position + Vector3.UP, Color(0.3, 0.5, 0.15), 25, 5.0)


func _check_boss() -> void:
	if Game.quest_state("goblin_king") == "active" and not Game.flags.get("king_dead", false):
		if Network.is_client():
			if not _king_alive():
				Network.request_boss()   # o servidor cria (se ainda não existir) e todos veem
			return
		if boss == null or not is_instance_valid(boss):
			boss = ENEMY.new()
			boss.kind = "goblin_king"
			boss.level = ProgressionRules.enemy_level(Balance.tables, "goblin_king", 0)
			boss.position = RUINS + Vector3.UP * 0.3
			add_child(boss)
			hud.boss = boss


## Há um Rei Goblin vivo no mundo aberto? (no cliente ele é um boneco do servidor, fora de `boss`)
func _king_alive() -> bool:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Enemy and e.kind == "goblin_king" and not e.dead and not e.chief and not e.horde:
			return true
	return false


## Servidor: o rei aparece quando algum jogador está com a missão ativa. Quem ainda tem a missão e não
## participou do abate (outro jogador matou antes) pede de novo e ele volta BOSS_RESPAWN s depois.
const BOSS_RESPAWN := 20.0
const BOSS_RECHECK := 4.0
var _boss_wait := 0.0
var _boss_check := BOSS_RECHECK


func server_spawn_boss() -> void:
	if (boss != null and is_instance_valid(boss) and not boss.dead) or _boss_wait > 0.0:
		return
	boss = ENEMY.new()
	boss.kind = "goblin_king"
	boss.level = ProgressionRules.enemy_level(Balance.tables, "goblin_king", 0)
	boss.position = RUINS + Vector3.UP * 0.3
	add_child(boss)
	boss.died.connect(func(_e: Enemy) -> void: _boss_wait = BOSS_RESPAWN)


func _process(delta: float) -> void:
	_t += delta
	_boss_wait = maxf(_boss_wait - delta, 0.0)
	_boss_check -= delta
	if _boss_check <= 0.0:   # antes só conferia ao mudar de missão: rei morto por outro jogador não voltava
		_boss_check = BOSS_RECHECK
		_check_boss()
	_boss_scan -= delta
	if _boss_scan <= 0.0 and hud != null and player != null:
		_boss_scan = 0.5
		_scan_boss()
	for f in flicker_lights:
		f[0].light_energy = f[1] * (0.85 + 0.15 * sin(_t * 9.0 + f[2]) + 0.08 * sin(_t * 23.0 + f[2]))
	_night_scan -= delta
	if _night_scan <= 0.0:
		_night_scan = 2.0
		_is_night_now = is_night()
	_dungeon_t -= delta
	if _dungeon_t <= 0.0:
		_dungeon_t = DUNGEON_RECHECK
		_count_dungeon_players()
	for s in spawns:
		if s.get("night", false) and not _is_night_now:
			_day_leave(s)
			continue
		if s.node == null and s.timer > 0:
			s.timer -= delta
			if s.timer <= 0:
				if s.has("dungeon") and int(s.slot) >= DungeonRules.population(Balance.tables, int(s.base),
						_dungeon_players(str(s.dungeon))):
					s.timer = DUNGEON_RECHECK   # vaga extra: espera mais gente entrar
				elif _any_player_near(s.pos, 25.0) and not bool(s.get("boss", false)):
					s.timer = 5.0
				else:
					_spawn(s)


## É noite no Vale agora? (mesma hora e mesmo nascer/pôr do sol que o céu usa)
static func is_night() -> bool:
	var day := DayNightRules.day_for(Weather.season_weights())
	return DayNightRules.night(DayNightFX.current_hour(), day.sunrise, day.sunset) > 0.5


## Bicho da noite quando amanhece: some sem morrer (fora de combate) e espera a noite seguinte.
func _day_leave(s: Dictionary) -> void:
	s.timer = maxf(s.timer, 3.0)
	var e = s.node
	if e == null or not is_instance_valid(e) or e.dead or e.state in ["chase", "attack"]:
		return
	if Network.is_server():
		Network.server_enemy_despawn(e)
	FX.burst(e.global_position + Vector3.UP * 1.4, Color(0.3, 0.24, 0.3), 10, 2.5, 0.1, 0.6)
	e.queue_free()
	s.node = null


func _any_player_near(pos: Vector3, dist: float) -> bool:
	for p in get_tree().get_nodes_in_group("players"):
		if p.global_position.distance_to(pos) < dist:
			return true
	return false


# ================================================================ UI modal
func _unhandled_input(event: InputEvent) -> void:
	if modal != null or player == null:
		return
	if event.is_action_pressed("pause"):
		var p := PAUSE.new()
		p.mode = "pause"
		p.player_pos = player.global_position
		p.player_yaw = player.model.rotation.y
		_open_modal(p)
	elif player.dead:
		return
	elif event.is_action_pressed("inventory"):
		# no Desafio da Horda o Tab mostra o placar do grupo (segurar); o inventário fica no I
		if survival != null and event is InputEventKey and event.physical_keycode == KEY_TAB:
			return
		_open_menu(0)
	elif event.is_action_pressed("character"):
		_open_menu(1)
	elif event.is_action_pressed("talents"):
		_open_menu(2)
	elif event.is_action_pressed("quest_log"):
		_open_menu(3)
	elif event.is_action_pressed("professions"):
		_open_menu(4)
	elif event.is_action_pressed("world_map") and survival == null:
		open_world_map()
	elif event.is_action_pressed("party"):
		open_world_map(WORLD_MAP_UI.TAB_PARTY)
	elif event.is_action_pressed("friends"):
		open_world_map(WORLD_MAP_UI.TAB_FRIENDS)
	elif survival == null:
		for i in KnightEmotes.KINDS.size():
			if event.is_action_pressed("emote_%d" % (i + 1)):
				player.play_emote(KnightEmotes.KINDS[i])
				return


## TAB_MAP abre o mapa-mundi em tela cheia (WORLD_ATLAS_UI); TAB_PARTY e TAB_FRIENDS, o livro do social.
func open_world_map(tab := 0) -> void:
	if tab == WORLD_MAP_UI.TAB_MAP:
		var a := WORLD_ATLAS_UI.new()
		a.world = self
		a.capture = map_capture
		_open_modal(a)
		return
	var m := WORLD_MAP_UI.new()
	m.start_tab = tab
	m.world = self
	_open_modal(m)


## Menu do herói: a aba 0 é o inventário (janela da direita); 1-4 são Personagem, Talentos, Missões e
## Profissões, na janela da esquerda.
func _open_menu(tab: int) -> void:
	var m := GAME_MENU.new()
	m.mode = "inventory" if tab == 0 else "hero"
	m.start_tab = maxi(0, tab - 1)
	_open_modal(m)


## Atalho apertado com janelas abertas (WindowDock): abre a janela; se ela já está aberta na mesma aba, fecha.
func toggle_window(action: String) -> void:
	var spec: Array = WindowDock.HOTKEYS[action]
	var cur: Control = dock.at(spec[0])
	var tab: int = spec[1]
	if cur != null and cur.get_script() == GAME_MENU and tab >= 0:
		var want := "inventory" if tab == 0 else "hero"
		if cur.mode == want:
			if tab == 0 or cur.book.current_page() == tab - 1:
				WindowDock.close_window(cur)
			else:
				cur._show_tab(tab - 1)
			return
	if cur != null and cur.get_script() == WORLD_MAP_UI and tab < 0:
		var page: int = cur.book.page_for_action(action)
		if cur.book.current_page() == page:
			WindowDock.close_window(cur)
		else:
			cur.book.show_page(page)
		return
	if tab >= 0:
		_open_menu(tab)
	elif action == "party":
		open_world_map(WORLD_MAP_UI.TAB_PARTY)
	else:
		open_world_map(WORLD_MAP_UI.TAB_FRIENDS)


## Fecha tudo que está na tela: janelas laterais e a janela modal.
func close_ui() -> void:
	dock.close_all()
	if modal != null:
		modal.queue_free()
		_on_modal_closed()


## Abertura da história (personagem novo, primeira vez no mundo): a cena da chegada (ArrivalCutscene: o
## corpo do herói é montado em luz, dos pés à cabeça) e depois a narração. Não roda nos testes.
## `-- --introdemo` força a abertura num personagem novo descartável (para capturas).
func _play_intro() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or "--smoketest" in args or "--nointro" in args \
			or Array(args).any(func(a: String) -> bool: return a.begins_with("--nettest")):
		return
	await get_tree().create_timer(0.3).timeout
	# espera a tela de carregamento sair (a cena começa em preto, então nada do mapa aparece antes)
	var waited := 0.0
	while is_inside_tree() and Loading.covering and waited < 30.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if not is_inside_tree() or modal != null or survival != null or player == null:
		return
	var cut := ArrivalCutscene.new()
	cut.world = self
	cut.player = player
	add_child(cut)
	await cut.finished
	await get_tree().create_timer(0.4).timeout
	if is_inside_tree() and modal == null and survival == null:
		open_dialogue("", StoryDialogue.intro())


func open_dialogue(speaker: String, pages: Array, focus: Node3D = null) -> void:
	var d := DIALOGUE.new()
	d.speaker = speaker
	d.pages = pages
	d.world = self
	_open_modal(d)
	if modal == d and focus != null and focus.has_method("face_point"):
		_start_closeup(focus)


# ---------------------------------------------------------------- close no diálogo
## Câmera própria que voa da câmera do jogador até um 3/4 do rosto do NPC e volta ao fechar.
const CLOSEUP_DIST := 1.3
const CLOSEUP_ANGLE := 0.6   # ~35° fora do eixo: mostra o perfil do nariz e não bate no jogador
const CLOSEUP_FOV := 36.0
var closeup_cam: Camera3D
var _closeup_tween: Tween


func _start_closeup(npc: Node3D) -> void:
	if player == null or player.camera == null:
		return
	npc.turn_to(player.global_position)
	var to_npc := npc.global_position - player.global_position
	to_npc.y = 0.0
	if to_npc.length() > 0.01:
		player.model.rotation.y = atan2(to_npc.x, to_npc.z)
	var face: Vector3 = npc.face_point()
	var fwd: Vector3 = npc.face_dir()
	# Lado do close: o mesmo lado onde a câmera do jogador já está, para a transição ser curta.
	var right := fwd.cross(Vector3.UP)
	var side := 1.0 if (player.camera.global_position - face).dot(right) >= 0.0 else -1.0
	var dir := fwd.rotated(Vector3.UP, CLOSEUP_ANGLE * side)
	var pos := face + dir * CLOSEUP_DIST + Vector3.UP * 0.03
	# Mira um pouco abaixo dos olhos: o rosto fica no terço de cima, acima da caixa de diálogo.
	var target := Transform3D(Basis(), pos).looking_at(face - Vector3.UP * 0.09, Vector3.UP)

	if closeup_cam == null:
		closeup_cam = Camera3D.new()
		closeup_cam.process_mode = Node.PROCESS_MODE_ALWAYS
		closeup_cam.near = 0.03
		closeup_cam.far = 400.0
		add_child(closeup_cam)
		closeup_cam.global_transform = player.camera.global_transform
		closeup_cam.fov = player.camera.fov
	closeup_cam.current = true
	var start := closeup_cam.global_transform
	var start_fov := closeup_cam.fov
	_restart_closeup_tween()
	_closeup_tween.tween_method(_closeup_step.bind(start, target, start_fov, CLOSEUP_FOV), 0.0, 1.0, 0.7)


func _end_closeup() -> void:
	if closeup_cam == null:
		return
	var start := closeup_cam.global_transform
	var start_fov := closeup_cam.fov
	_restart_closeup_tween()
	# O destino é lido a cada quadro: o jogador já pode se mexer enquanto a câmera volta.
	_closeup_tween.tween_method(_closeup_return_step.bind(start, start_fov), 0.0, 1.0, 0.45)
	_closeup_tween.tween_callback(_finish_closeup)


func _restart_closeup_tween() -> void:
	if _closeup_tween and _closeup_tween.is_valid():
		_closeup_tween.kill()
	_closeup_tween = create_tween()
	_closeup_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_closeup_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _closeup_step(t: float, a: Transform3D, b: Transform3D, fov_a: float, fov_b: float) -> void:
	closeup_cam.global_transform = a.interpolate_with(b, t)
	closeup_cam.fov = lerpf(fov_a, fov_b, t)


func _closeup_return_step(t: float, a: Transform3D, fov_a: float) -> void:
	if player == null or player.camera == null:
		return
	closeup_cam.global_transform = a.interpolate_with(player.camera.global_transform, t)
	closeup_cam.fov = lerpf(fov_a, player.camera.fov, t)


func _finish_closeup() -> void:
	if player and player.camera:
		player.camera.current = true
	if closeup_cam:
		closeup_cam.queue_free()
		closeup_cam = null


## Loja: `stall` = a barraca de quem abriu (ShopUI.STALLS); "" = o estoque inteiro.
func open_shop(stall := "") -> void:
	var ui := SHOP.new()
	ui.stall = stall
	_open_modal(ui)


## Painel de encantamento do ferreiro. `smith` = quem abriu (bate na bigorna quando o encanto sai).
func open_enchant(smith: Node = null) -> void:
	var ui := ENCHANT_UI.new()
	ui.smith = smith
	_open_modal(ui)


func open_plant_menu(plot_index: int) -> void:
	var ui := PLANT_UI.new()
	ui.plot_index = plot_index
	_open_modal(ui)


func open_cooking(kitchen: Node = null) -> void:
	var ui := COOKING_UI.new()
	ui.kitchen = kitchen
	_open_modal(ui)


## Bancada de craft de uma estação ("forge", "leather", "alchemy"; ver CraftingUI).
func open_crafting(station: String) -> void:
	var ui := CraftingUI.new()
	ui.station = station
	_open_modal(ui)


## Painel de um ponto que veio da praça (hub_point.interact): Mestre Orin ou o quadro de recordes.
func open_point_panel(point: Node) -> void:
	var ui: Control = null
	match str(point.get("kind")):
		"passive_master":
			ui = PASSIVE_MASTER.new()
		"records":
			ui = RECORDS.new()
	if ui != null:
		open_modal(ui)


func open_modal(c: Control) -> void:
	_open_modal(c)


## Janela com `dock_side` ("left"/"right") encaixa ao lado das outras (WindowDock); o resto (diálogo,
## pausa, mapa, cartas da Horda) é modal: uma por vez, e fecha as janelas laterais ao abrir.
## `modal` aponta para a última janela aberta; fica null quando nada está na tela.
func _open_modal(c: Control) -> void:
	var side = c.get("dock_side")
	if side is String and side != "":
		_open_docked(c, side)
		return
	if modal != null:
		if not dock.has(modal):
			return
		dock.close_all()
	modal = c
	ui_layer.add_child(c)
	c.closed.connect(_on_modal_closed)
	_ui_shown()


func _open_docked(c: Control, side: String, opener: Control = null) -> void:
	if modal != null and not dock.has(modal):
		return   # diálogo, pausa etc. na frente
	var first := not dock.is_open()
	dock.put(c, side, opener)
	ui_layer.add_child(c)
	c.closed.connect(_on_docked_closed.bind(c))
	modal = c
	if first:
		_ui_shown()
	# estação que mexe com a mochila abre o inventário do outro lado (e ele fecha junto com ela)
	if opener == null and c.get("wants_inventory") == true and dock.at("right") == null:
		var inv := GAME_MENU.new()
		inv.mode = "inventory"
		_open_docked(inv, "right", c)
		modal = c
	_link_trade()
	dock.settle(c)


func _ui_shown() -> void:
	_set_paused(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.visible = false


func _on_docked_closed(c: Control) -> void:
	dock.forget(c)
	if modal == c:
		modal = dock.find(func(_w: Control) -> bool: return true)
	_link_trade()
	if not dock.is_open():
		_on_modal_closed()


## Inventário aberto ao lado de uma loja: clique direito na mochila vende (a loja recebe o item).
func _link_trade() -> void:
	var inv: Control = dock.at("right")
	if inv != null and inv.get_script() == GAME_MENU:
		var left: Control = dock.at("left")
		inv.set_trade(left if left != null and left.has_method("trade_item") else null)


## No multiplayer o mundo não para: só o controle do jogador fica travado.
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
	_end_closeup()
	if player and not player.dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ================================================================ morte
func _on_player_died() -> void:
	if survival != null:
		survival.on_player_died()
		return
	await get_tree().create_timer(1.8).timeout
	dock.close_all()
	if modal != null:
		modal.queue_free()
		modal = null
	var p := PAUSE.new()
	p.mode = "death"
	p.respawn_requested.connect(_respawn)
	modal = p
	ui_layer.add_child(p)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_paused(true)


func _respawn() -> void:
	Game.death_penalty()   # o ouro perdido e o aviso vêm das regras
	modal = null
	_set_paused(false)
	# morreu numa dungeon: volta na porta dela, no mapa de fora
	var here := Regions.region_at(player.global_position)
	player.revive(Regions.door_point(here) if Regions.is_dungeon(here) else VILLAGE_SPAWN)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if Network.is_online():
		return   # no multiplayer o servidor cuida dos inimigos
	# inimigos voltam para casa
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.state != "idle":
			e._set_state("return")


# ================================================================ guilda, NPCs novos e mapas
## Cria o nó de jogo de uma MapEntity das cenas de mapa (sem adicionar à árvore; o MapLoader adiciona), na
## posição e no giro dela, e guarda as referências que o mundo usa (points, santa). null para tipo desconhecido.
func make_entity(e: MapEntity) -> Node3D:
	var n: Node3D = null
	var yaw := e.global_rotation.y
	match e.kind:
		"elder":
			n = ELDER.new()
		"rival":
			n = RIVAL.new()
		"merchant":
			n = MERCHANT.new()
		"alchemist":
			n = ALCHEMIST.new()
		"npc":
			n = RegionBuilder.npc(e.ref, e.global_position, yaw)
			if e.params.has("npc_id"):
				n.set("npc_id", e.params.npc_id)
		"walker":
			var path: Array = e.walk_path()
			n = RegionBuilder.walker(e.ref, path)
			if path.size() >= 2:   # nasce no primeiro ponto do caminho (o _ready assenta no chão)
				var p0: Array = path[0]
				n.position = Vector3(float(p0[0]), e.global_position.y, float(p0[1]))
				return n
		"story_point":
			n = RegionBuilder.point(e.ref, e.global_position, yaw)
		"hub_point":
			var pt := POINT.new()
			pt.kind = e.ref
			if e.params.has("building_id"):
				pt.set("building_id", str(e.params.building_id))
			points.append(pt)
			n = pt
		"farm_plot":
			var plot := PLOT.new()
			plot.index = e.index
			n = plot
		"kitchen":
			n = KITCHEN.new()
		"dungeon_door":
			var door := DUNGEON_DOOR.new()
			door.target = e.ref
			n = door
		"station":
			var st := CRAFTING_STATION.new()
			st.station = e.ref
			n = st
		"portal":
			if not Game.HORDE_ENABLED:
				return null   # Horda desligada: sem portal na vila
			n = PORTAL.new()
		"guard":
			n = VillageGuard.new()
		"santa":
			santa = SANTA.new()
			n = santa
		"xmas_gift":
			var g := EVENT_POINT.new()
			g.kind = "gift"
			g.index = e.index
			n = g
		"signpost":
			var dests: Array = []
			for d in e.params.get("dests", []):
				dests.append([d[0], MapData.landmark("vila", d[1])])
			return SIGNPOST.make(e.global_position, dests)
		_:
			push_error("make_entity: tipo desconhecido %s (%s)" % [e.kind, e.get_path()])
			return null
	n.position = e.global_position
	n.rotation.y = yaw
	return n


## Bosque, Mina e Pico: cada um vem da cena dele (scenes/maps/<mapa>.tscn, MapLoader), na origem da região.
func _build_regions() -> void:
	for id in Regions.ALL:   # Bosque, Mina, Pico e as dungeons
		if id != "vila":
			maps[id] = MapLoader.build(self, id)   # chão em region_grounds[id], monstros em region_spawns
	# lê já (atrás da tela de carregamento) as regiões com nome de todos os mapas: o HUD, o mapa e as missões
	# consultam Regions.area_at durante o jogo, e a primeira leitura instancia as cenas dos mapas
	MapData.all_areas()


## O servidor dedicado e o solo criam os monstros; o cliente online recebe do servidor.
func has_server_enemies() -> bool:
	return not Network.is_client()


func _scatter_region_grass() -> void:
	if Network.is_server():
		return
	var ids: Array = region_grounds.keys()
	for i in ids.size():
		var id: String = ids[i]
		var g = region_grounds[id]
		var o: Vector3 = Regions.origin(id)
		var half: float = Regions.DATA[id].half
		var root: MapRoot = maps[id]
		var keep_out: Array = []
		for k in _no_grass + grass_areas[id].keep_out:
			var c: Vector2 = k[0]
			if absf(c.x - o.x) <= half + 5.0 and absf(c.y - o.z) <= half + 5.0:
				keep_out.append([c - Vector2(o.x, o.z), k[1]])
		var density := root.grass_density
		var from := lerpf(_step_from, _step_to, float(i) / ids.size())
		var to := lerpf(_step_from, _step_to, float(i + 1) / ids.size())
		if Loading.covering:
			await g.scatter_grass(root.grass_seed, density, keep_out, [], root.grass_plants,
				func(frac: float) -> void: Loading.set_progress(lerpf(from, to, frac)))
		else:
			g.scatter_grass(root.grass_seed, density, keep_out, [], root.grass_plants)


## Por que a viagem paga até `region` não pode sair agora ("" = pode). Dentro de dungeon não há viagem:
## é preciso sair pela porta primeiro (vale para a carruagem e para o teleporte do mapa-mundi).
func travel_block_reason(region: String, mode: String) -> String:
	if player == null or player.dead:
		return "Não dá para viajar agora."
	if not Regions.ORDER.has(region):
		return "Não há viagem para lá."
	var here := Regions.region_at(player.global_position)
	if Regions.is_dungeon(here):
		return "Não dá para viajar de dentro de uma dungeon. Saia dela primeiro."
	if here == region and mode == "coach":
		return "Você já está em %s." % Regions.display_name(region)
	if not Regions.unlocked(region, Game.access_rank()):
		return "%s exige Rank %s na guilda." % [Regions.display_name(region), Regions.DATA[region].rank]
	if _travel_pending != "":
		return "Já há uma viagem a caminho."
	var cost := Game.travel_cost(region, mode)
	if Game.gold < cost:
		return "%s até %s custa %d de ouro (você tem %d)." % ["A carruagem" if mode == "coach" else "O teleporte",
			Regions.display_name(region), cost, Game.gold]
	return ""


## Viagem paga: o servidor/solo cobra (op pay_travel) e, confirmado, o jogador viaja (_on_travel_paid).
## Devolve false (com aviso) quando nem pede.
func request_travel(region: String, mode: String) -> bool:
	var why := travel_block_reason(region, mode)
	if why != "":
		Game.notify.emit(why, Color(1, 0.6, 0.5))
		return false
	_travel_pending = region
	if not Econ.done.is_connected(_on_travel_paid):
		Econ.done.connect(_on_travel_paid)
	Econ.request("pay_travel", [region, mode])
	return true


func _on_travel_paid(op: String, args: Array, ok: bool, _err: String, _events: Array) -> void:
	if op != "pay_travel" or args.is_empty() or str(args[0]) != _travel_pending:
		return
	_travel_pending = ""
	if ok:
		travel_to(str(args[0]), str(args[1]) if args.size() > 1 else "coach")


## Viagem pela carruagem da guilda: escurece a tela, leva o jogador ao ponto de chegada do mapa e mostra
## o cartão com o nome do lugar.
func travel_to(region: String, mode := "coach") -> void:
	if player == null or player.dead or not Regions.DATA.has(region):
		return
	if not Regions.unlocked(region, Game.access_rank()):
		Game.notify.emit("A carruagem só vai para lá com Rank %s." % Regions.DATA[region].rank, Color(1, 0.6, 0.5))
		return
	if _travel_fade == null:
		var layer := CanvasLayer.new()
		layer.layer = 30
		layer.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(layer)
		_travel_fade = ColorRect.new()
		_travel_fade.color = Color(0, 0, 0, 0)
		_travel_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_travel_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_travel_fade)
	player.input_locked = true
	var tw := create_tween()
	tw.tween_property(_travel_fade, "color:a", 1.0, 0.4)
	tw.tween_callback(_arrive.bind(region, mode))
	tw.tween_interval(0.35)
	tw.tween_property(_travel_fade, "color:a", 0.0, 0.5)
	tw.tween_callback(func() -> void: player.input_locked = false)


## Porta de dungeon: entra (`target` = id da dungeon; pede o rank dela) ou sai ("out": volta à porta de fora).
func use_dungeon_door(target: String) -> void:
	if player == null or player.dead:
		return
	if target == "out":
		var here := Regions.region_at(player.global_position)
		_teleport(Regions.door_point(here), Regions.display_name(Regions.parent_of(here)), "SAINDO DA DUNGEON")
		return
	if target == "entrance":   # portal da sala do chefe, depois que ele cai
		var dg := Regions.region_at(player.global_position)
		if Regions.is_dungeon(dg):
			_teleport(Regions.arrive_point(dg), Regions.display_name(dg), "ENTRADA DA DUNGEON")
		return
	if not Regions.is_dungeon(target):
		return
	if not Regions.unlocked(target, Game.access_rank()):
		Game.notify.emit("%s exige Rank %s na guilda." % [Regions.display_name(target), Regions.DATA[target].rank],
			Color(1, 0.6, 0.5))
		return
	_teleport(Regions.arrive_point(target), Regions.display_name(target), "DUNGEON")


## Escurece a tela, leva o jogador a `to` e mostra o cartão com o nome do lugar.
func _teleport(to: Vector3, title: String, kicker: String) -> void:
	if _travel_fade == null:
		var layer := CanvasLayer.new()
		layer.layer = 30
		layer.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(layer)
		_travel_fade = ColorRect.new()
		_travel_fade.color = Color(0, 0, 0, 0)
		_travel_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_travel_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_travel_fade)
	player.input_locked = true
	var tw := create_tween()
	tw.tween_property(_travel_fade, "color:a", 1.0, 0.4)
	tw.tween_callback(func() -> void:
		player.global_position = to
		player.velocity = Vector3.ZERO
		Sfx.play("portal", -6.0)
		if story_card:
			story_card.enqueue(kicker, title))
	tw.tween_interval(0.35)
	tw.tween_property(_travel_fade, "color:a", 0.0, 0.5)
	tw.tween_callback(func() -> void: player.input_locked = false)


func _arrive(region: String, mode := "coach") -> void:
	var to: Vector3 = Regions.arrive_point(region)
	player.global_position = to
	player.velocity = Vector3.ZERO
	var back: Vector3 = Regions.coach_point(region)
	var d := to - back
	if region != "vila":
		player.model.rotation.y = atan2(-d.x, -d.z)   # de costas para a carruagem, olhando para o mapa
	Sfx.play("portal", -6.0)
	if story_card:
		story_card.enqueue("CARRUAGEM DA GUILDA" if mode == "coach" else "TELEPORTE", Regions.display_name(region))


## Chefes que nascem como monstros comuns (o Lich, a Slime Rainha não é chefe): a barra aparece quando o
## jogador chega perto, como a do Rei Goblin.
## O chefe guardado só fica se ainda estiver perto: o servidor anuncia todo chefe que nasce (o de outra dungeon
## ou o Rei Goblin do mapa), e antes isso prendia a barra num chefe distante e a do chefe da sala não aparecia.
func _scan_boss() -> void:
	var cur = hud.boss
	if cur != null and is_instance_valid(cur) and not cur.dead and cur.global_position.distance_to(player.global_position) < 40.0:
		return
	var best: Enemy = null
	var best_d := 40.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Enemy and e.is_boss and not e.dead and not e.horde:
			var d: float = e.global_position.distance_to(player.global_position)
			if d < best_d:
				best_d = d
				best = e
	if best != null:
		hud.boss = best
