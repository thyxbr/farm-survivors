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
const BASE_BUILDING := preload("res://scripts/ui/base_building_ui.gd")
const RECORDS := preload("res://scripts/ui/records_ui.gd")
const WAR_TABLE := preload("res://scripts/ui/war_table_ui.gd")
const ALCHEMIST := preload("res://scripts/world/alchemist.gd")
const RIVAL := preload("res://scripts/world/rival.gd")
const STORY_POINT := preload("res://scripts/world/story_point.gd")
const MERCHANT_SHOP := Vector3(9.4, 0, 0.5)     # empório atrás do balcão da Mira (frente para -X)
const ALCHEMIST_SHOP := Vector3(-12.0, 0, 0.5)  # botica no vão oeste (frente para +X)
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
const GROUND := preload("res://scripts/world/ground.gd")
const WORLD_MAP_UI := preload("res://scripts/ui/world_map_ui.gd")
const FIELD_CROP := preload("res://assets/models/field_crop.glb")

const MAP_HALF := 125.0
const VILLAGE_SPAWN := Vector3(0, 0.3, 6)
const RUINS := Vector3(0, 0, -100)
const CAMP := Vector3(62, 0, 0)
const ARENA := Vector3(-72, 0, -10)     # Desafio da Horda
const PORTAL_POS := Vector3(-8, 0, -9.5)
const FARM := Vector3(0, 0, 33)          # Horta da Vila (saída sul)
const NEST := Vector3(-36, 0, 36)        # Ninho de Slimes (sudoeste da vila)
## Maciços dentro do mapa: [centro, raio da base, altura]. Ficam nos cantos vazios, longe das
## áreas de missão; a serra em volta do mapa é só visual (fora da borda).
const MOUNTAINS := [
	[Vector3(-82, 0, 86), 38.0, 34.0],    # Pico do sudoeste
	[Vector3(86, 0, -96), 30.0, 26.0],    # nordeste, atrás da floresta
	[Vector3(-88, 0, -84), 22.0, 15.0],   # morro do noroeste
	[Vector3(84, 0, 96), 26.0, 17.0],     # colinas do sudeste
]
## Raio de colisão do tronco por árvore (prop "cyl").
const TREE_R := {"tree_oak": 0.4, "tree_pine": 0.35, "tree_fir": 0.32, "tree_birch": 0.25,
		"tree_maple": 0.4, "tree_cherry": 0.38, "tree_apple": 0.3, "tree_orange": 0.3, "tree_pear": 0.3}
const FRUIT_TREES := ["tree_apple", "tree_orange", "tree_pear"]
const ORCHARD := Vector3(20, 0, 33)      # pomar a leste da Horta

var player: Player
var hud
var ui_layer: CanvasLayer
var modal: Control = null
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
var spawns: Array = []
## Pontos que vieram da praça (hub_point.gd): construções da base, Mestre Orin, mesa de guerra, recordes.
var points: Array = []
var santa: Node3D = null
## Veios de ferro e cristais arcanos (WorldResourceNode); vazio no servidor dedicado.
var resource_nodes: Array = []
var flicker_lights: Array = []
var rng := RandomNumberGenerator.new()
var _avoid: Array = []   # [Vector2 centro, raio] áreas sem vegetação aleatória
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
	var steps := [[_build_environment, 2.0], [_build_ground, 2.0], [_build_village, 1.0], [_build_farm, 1.0],
		[_build_fields, 0.5], [_build_goblin_camp, 0.5], [_build_ruins, 0.5], [_build_arena, 0.5],
		[_build_borders, 0.5], [_scatter_forest, 0.5], [_scatter_sparse, 0.5], [_mountain_nature, 0.5],
		[_build_regions, 2.0], [_scatter_grass, 7.0], [_scatter_region_grass, 3.0]]
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


func _build_ground() -> void:
	ground = GROUND.new()
	add_child(ground)
	ground.setup(MAP_HALF)
	for m in MOUNTAINS:
		ground.add_mountain(m[0], m[1], m[2])
	ground.border_mountains(58.0)
	ground.build_terrain()
	var dirt := Color(0.45, 0.35, 0.22)
	_flat(Vector3(0, 0.02, -50), Vector2(4.5, 80), dirt)          # trilha norte
	_flat(Vector3(38, 0.02, 0), Vector2(52, 4.5), dirt)           # trilha leste
	_disc(Vector3(0, 0.018, 1), 10.0, Color(0.5, 0.45, 0.36))     # praça
	for st in VillageLayout.STREETS:                               # ruas da vila
		_flat(st[0] + Vector3(0, 0.017, 0), st[1], VillageLayout.STREET_COLOR, 0.5)
	_disc(VillageLayout.LARGO + Vector3(0, 0.019, 0), 4.8, Color(0.55, 0.5, 0.42), 0.5)   # Largo dos Ecos
	_flat(Vector3(-40, 0.02, 0), Vector2(9, 3.6), dirt)            # do portão oeste para a arena
	_disc(RUINS + Vector3(0, 0.02, 0), 15.0, Color(0.42, 0.42, 0.4))
	_disc(CAMP + Vector3(0, 0.02, 0), 13.0, Color(0.4, 0.32, 0.2))


## Área retangular pintada no chão (o shader do chão desenha a borda irregular).
func _flat(pos: Vector3, size: Vector2, c: Color, soft := 0.8) -> void:
	ground.add_rect(pos, size, c, soft)


func _disc(pos: Vector3, r: float, c: Color, soft := 0.9) -> void:
	ground.add_disc(pos, r, c, soft)


## Árvore com colisão no tronco, apoiada no chão (sobe nas encostas).
func tree(model: String, p: Vector3, s: float) -> void:
	p.y = maxf(0.0, ground.height_at(p.x, p.z) - 0.35)
	prop(model, p, rng.randf() * TAU, s, "cyl", Vector3(TREE_R[model], 3, 0))


## Sorteia uma espécie por peso: {"tree_oak": 3, ...}.
func _pick(weights: Dictionary) -> String:
	var total := 0.0
	for k in weights:
		total += weights[k]
	var r := rng.randf() * total
	for k in weights:
		r -= weights[k]
		if r <= 0.0:
			return k
	return weights.keys()[0]


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


# ================================================================ vila
func _build_village() -> void:
	_avoid.append([Vector2(0, 4), 26.0])
	prop("well", Vector3(0, 0, 0), 0.0, 1.0, "cyl", Vector3(0.95, 1.2, 0))
	# [posição, yaw, modelo]: as três variações (enxaimel, sapê, sobrado) alternadas em volta da praça
	var houses := [
		[Vector3(-13, 0, -6), PI / 2, "house"], [Vector3(-13, 0, 7), PI / 2, "house_c"],
		[Vector3(13, 0, -6), -PI / 2, "house_c"], [Vector3(13, 0, 7), -PI / 2, "house_b"],
		[Vector3(-5, 0, 16), PI, "house_b"], [Vector3(6, 0, 16), PI, "house"],
	]
	var house_nodes: Array = []
	for h in houses:
		house_nodes.append(prop(h[2], h[0], h[1], 1.0, "box", Vector3(5.2, 3.2, 4.2)))
	var lamps: Array = []
	for p in [Vector3(-5, 0, -5), Vector3(5, 0, -5), Vector3(6, 0, 8), Vector3(-6, 0, 8)]:
		var lamp := prop("lamp", p, atan2(-p.x, -p.z), 1.0, "cyl", Vector3(0.12, 3.7, 0))
		DayNightFX.night_light(_light(lamp, Vector3(0, 3.3, 0.5), Color(1, 0.75, 0.4), 1.6, 9.0), 1.6)
		lamps.append(lamp)
	for hn in house_nodes:   # luz das janelas caindo na frente de cada casa, só à noite
		DayNightFX.night_light(_light(hn, Vector3(0, 1.6, 3.2), Color(1, 0.72, 0.42), 0.9, 5.5), 0.9)
	_build_christmas(houses, house_nodes, lamps)
	# lojas: empório da mercadora no vão leste, botica do alquimista no vão oeste (de frente para a praça)
	_shop("shop_merchant", MERCHANT_SHOP, -PI / 2, [[Vector3(0, 0, -0.4), Vector3(5.2, 3.0, 3.6)]], [], 3.4)
	_shop("shop_alchemist", ALCHEMIST_SHOP, PI / 2, [[Vector3(0.2, 0, 0), Vector3(4.4, 3.4, 3.8)]],
		[[Vector3(-2.05, 0, -1.8), 0.95], [Vector3(-1.05, 0, 2.85), 0.45]], 3.6)
	prop("tree_cherry", Vector3(-17, 0, -1.5), 0.3, 0.85, "cyl", Vector3(0.38, 3, 0))   # atrás da botica
	prop("tree_cherry", Vector3(9, 0, 11.5), 2.0, 0.75, "cyl", Vector3(0.38, 3, 0))
	# canteiros de flores na frente das casas e em volta da praça (sem colisão)
	for h in houses:
		var fwd := Vector3(sin(h[1]), 0, cos(h[1]))
		var side := Vector3(fwd.z, 0, -fwd.x)
		for off in [-2.2, -1.5, 1.5, 2.2]:   # dos dois lados da porta
			var kind := "flower_lavender" if rng.randf() < 0.5 else "flower_tulips"
			var fp: Vector3 = h[0] + fwd * 2.75 + side * (off + rng.randf_range(-0.15, 0.15))
			prop(kind, fp, rng.randf() * TAU, rng.randf_range(0.9, 1.2))
	_build_fence()
	# NPCs
	var elder := ELDER.new()
	elder.position = Vector3(-3, 0, -2.5)
	elder.rotation.y = atan2(3.0, 8.5)
	add_child(elder)
	var merchant := MERCHANT.new()
	merchant.position = Vector3(7.0, 0, -0.2)   # na frente do balcão do empório
	merchant.rotation.y = -PI / 2
	add_child(merchant)
	# ferraria no vão entre as casas de (-13, 7) e (-5, 16), de frente para o poço: da praça se vê o ferreiro
	# atrás da bigorna (o lampião de (-6, 8) fica de lado na visada); longe dos canteiros das portas
	var smith := BLACKSMITH.new()
	smith.position = Vector3(-10.5, 0, 13)
	smith.rotation.y = atan2(10.5, -9.0)
	var smithy := Transform3D(Basis(Vector3.UP, smith.rotation.y), smith.position)
	smith.anvil = prop("anvil", smithy * BLACKSMITH.ANVIL_OFFSET, smith.rotation.y + BLACKSMITH.ANVIL_YAW, 1.0,
		"cyl", Vector3(0.3, 0.8, 0))
	prop("forge", smithy * BLACKSMITH.FORGE_OFFSET, smith.rotation.y + BLACKSMITH.FORGE_YAW, 1.0,
		"box", Vector3(0.9, 1.0, 0.8))
	_forge_fire(smithy * BLACKSMITH.FORGE_OFFSET)
	# a ferraria tem a origem no ferreiro: a forja fica sob a coifa e a chaminé, a bigorna na frente
	_shop("shop_smithy", smith.position, smith.rotation.y, [[Vector3(0, 0, -2.6), Vector3(4.0, 3.0, 0.5)],
		[Vector3(-1.8, 0, -0.7), Vector3(0.4, 1.1, 3.4)]], [[Vector3(1.4, 0, -0.4), 0.5]], 2.8)
	add_child(smith)
	# Pip, a Alquimista, na frente da botica (de frente para o poço)
	var pip := ALCHEMIST.new()
	pip.position = Vector3(-9.0, 0, 0.2)
	pip.rotation.y = PI / 2
	add_child(pip)
	# Kael, o rival, no vão do portão leste, virado para a praça (ensaiando discursos)
	var kael := RIVAL.new()
	kael.position = Vector3(16.2, 0, -1.6)
	kael.rotation.y = -PI / 2
	add_child(kael)
	_build_signs()
	_build_guild()
	var portal := PORTAL.new()
	portal.position = PORTAL_POS
	add_child(portal)
	_build_districts()


## Decoração de Natal da vila (ChristmasDecor): árvore enfeitada perto do portão norte, varal de luzes
## entre os quatro lampiões da praça, pisca-pisca e guirlanda em cada casa, festão nos postes, bengalas
## nos portões, árvores pequenas na frente das lojas, presentes e um boneco de neve.
func _build_christmas(houses: Array, house_nodes: Array, lamps: Array) -> void:
	var tree_pos := Vector3(8.8, 0, -10.3)   # ao lado do quadro de avisos, longe do portão norte
	ChristmasDecor.tree(self, tree_pos, 1.0, 1225)
	_no_grass.append([Vector2(tree_pos.x, tree_pos.z), 2.4])
	for i in houses.size():
		var model: String = houses[i][2]
		ChristmasDecor.house_lights(house_nodes[i], model, i)
		var d: Array = ChristmasDecor.HOUSE_DOORS[model]
		ChristmasDecor.wreath(house_nodes[i], Vector3(d[0], d[1], d[2]))
	var top := Vector3(0, 3.45, 0)   # logo abaixo do chapéu do poste
	for i in lamps.size():
		var a: Node3D = lamps[i]
		var b: Node3D = lamps[(i + 1) % lamps.size()]
		ChristmasDecor.light_string(self, a.transform * top, b.transform * top, 0.6, ChristmasDecor.MULTI, i % 2)
		ChristmasDecor.lamp_garland(a)
	# bengalas nos portões (norte, sul da Horta, leste e oeste)
	var b := VillageLayout.BOUNDS
	for p in [Vector3(-13.4, 0, b.position.y + 0.6), Vector3(3.4, 0, b.position.y + 0.6), Vector3(-1.4, 0, 25.4),
			Vector3(3.4, 0, 25.4), Vector3(b.end.x - 0.6, 0, -3.4), Vector3(b.end.x - 0.6, 0, 3.4),
			Vector3(b.position.x + 0.6, 0, -0.9), Vector3(b.position.x + 0.6, 0, 5.9)]:
		ChristmasDecor.candy_cane(self, p, atan2(-p.x, -p.z) + PI / 2)
	# árvores pequenas na frente da botica e do empório, e o boneco de neve olhando para o poço
	for p in [Vector3(-9.2, 0, 3.6), Vector3(8.4, 0, -3.6)]:
		ChristmasDecor.tree(self, p, 0.38, int(p.x * 10))
		_no_grass.append([Vector2(p.x, p.z), 1.0])
	var sp := Vector3(-8.5, 0, -3.6)
	ChristmasDecor.snowman(self, sp, atan2(-sp.x, -sp.z))
	_no_grass.append([Vector2(sp.x, sp.z), 0.8])
	ChristmasDecor.gifts(self, Vector3(1.4, 0, -1.4), 3, rng, 0.0, 0.4)   # presentes ao pé do poço


## Cerca em volta da vila toda (VillageLayout.BOUNDS), com os portões abertos. No sul, entre as casas, a
## cerca da Horta faz a divisa.
func _build_fence() -> void:
	var b := VillageLayout.BOUNDS
	var x := b.position.x + 1.0
	while x <= b.end.x - 1.0:
		if not _gate_at("n", x):
			prop("fence", Vector3(x, 0, b.position.y), 0.0, 1.0, "box", Vector3(2.1, 1.0, 0.25))
		if not _gate_at("s", x) and absf(x - 1.0) > VillageLayout.SOUTH_OPEN:
			prop("fence", Vector3(x, 0, b.end.y), 0.0, 1.0, "box", Vector3(2.1, 1.0, 0.25))
		x += 2.0
	var z := b.position.y + 1.0
	while z <= b.end.y - 1.0:
		if not _gate_at("w", z):
			prop("fence", Vector3(b.position.x, 0, z), PI / 2, 1.0, "box", Vector3(2.1, 1.0, 0.25))
		if not _gate_at("e", z):
			prop("fence", Vector3(b.end.x, 0, z), PI / 2, 1.0, "box", Vector3(2.1, 1.0, 0.25))
		z += 2.0


func _gate_at(side: String, t: float) -> bool:
	for g in VillageLayout.GATES:
		if g[0] == side and absf(t - float(g[1])) < float(g[2]):
			return true
	return false


## Bairros novos (VillageLayout): casas variadas pintadas com as paletas, lampiões nas esquinas, os pontos
## que eram da praça, o Papai Noel com o trenó e os pontos dos eventos de Natal.
func _build_districts() -> void:
	_avoid.append([Vector2(-24, 4), 15.5])
	_avoid.append([Vector2(26, 4), 15.5])
	for i in VillageLayout.HOUSES.size():
		var h: Array = VillageLayout.HOUSES[i]
		var model: String = h[2]
		var size: Vector3 = VillageLayout.HOUSE_SIZE[model]
		var hn := prop(model, h[0], h[1], 1.0, "box", size)
		VillageLayout.tint(hn, h[3])
		ChristmasDecor.house_lights(hn, model, i + 1)
		var d: Array = ChristmasDecor.HOUSE_DOORS[model]
		ChristmasDecor.wreath(hn, Vector3(d[0], d[1], d[2]))
		DayNightFX.night_light(_light(hn, Vector3(0, 1.6, size.z * 0.5 + 1.2), Color(1, 0.72, 0.42), 0.9, 5.5), 0.9)
		# canteiro de flores dos lados da porta (as casas de alpendre já têm banco e floreira)
		if model != "house_d":
			var xf := VillageLayout.house_xform(h)
			for off in [-1.6, 1.6]:
				if absf(off - float(d[0])) < 0.9:
					continue
				var kind := "flower_lavender" if (i + int(off)) % 2 == 0 else "flower_tulips"
				prop(kind, xf * Vector3(off, 0, size.z * 0.5 + 0.55), rng.randf() * TAU, rng.randf_range(0.85, 1.1))
	# lampiões nas esquinas das ruas, com festão e luz à noite
	for p in [Vector3(-23.6, 0, -12.6), Vector3(-23.6, 0, 4.9), Vector3(-23.7, 0, 17.8), Vector3(-34.0, 0, 0.2),
			Vector3(24.6, 0, -12.6), Vector3(24.6, 0, 2.4), Vector3(24.6, 0, 17.8), Vector3(37.0, 0, -2.3),
			Vector3(-3.0, 0, -12.8), Vector3(3.0, 0, -12.8)]:
		var lamp := prop("lamp", p, atan2(-p.x, -p.z), 1.0, "cyl", Vector3(0.12, 3.7, 0))
		DayNightFX.night_light(_light(lamp, Vector3(0, 3.3, 0.5), Color(1, 0.75, 0.4), 1.4, 8.0), 1.4)
		ChristmasDecor.lamp_garland(lamp)
	# varal de luzes atravessando a saída norte da praça
	var top := Vector3(0, 3.45, 0)
	ChristmasDecor.light_string(self, Vector3(-3.0, 0, -12.8) + top, Vector3(3.0, 0, -12.8) + top, 0.5,
		ChristmasDecor.MULTI, 1)
	# pontos da antiga praça
	for pd in VillageLayout.POINTS:
		var pt := POINT.new()
		pt.kind = pd[0]
		pt.building_id = pd[3]
		var pos: Vector3 = pd[1]
		pt.position = pos
		pt.rotation.y = pd[2]
		add_child(pt)
		points.append(pt)
		_no_grass.append([Vector2(pos.x, pos.z), 2.5])
		if pd[0] == "building":
			var back: Vector3 = pos - Vector3(sin(pd[2]), 0, cos(pd[2])) * POINT.BUILDING_BACK
			_no_grass.append([Vector2(back.x, back.z), 4.2])
	# Papai Noel, de frente para a praça, e o trenó atrás dele, perto da árvore grande
	santa = SANTA.new()
	santa.position = VillageLayout.SANTA
	santa.rotation.y = VillageLayout.SANTA_YAW
	add_child(santa)
	ChristmasDecor.sleigh(self, VillageLayout.SLEIGH, -2.2)
	_no_grass.append([Vector2(VillageLayout.SLEIGH.x, VillageLayout.SLEIGH.z), 1.8])
	# eventos: presentes caídos pelo vale e as portas das entregas
	for i in VillageLayout.GIFTS.size():
		var g := EVENT_POINT.new()
		g.kind = "gift"
		g.index = i
		var gp: Vector3 = VillageLayout.GIFTS[i]
		_avoid.append([Vector2(gp.x, gp.z), 2.5])
		gp.y = ground.height_at(gp.x, gp.z)
		g.position = gp
		add_child(g)
	for i in VillageLayout.DELIVERY.size():
		var h: Array = VillageLayout.HOUSES[VillageLayout.DELIVERY[i]]
		var d: Array = ChristmasDecor.HOUSE_DOORS[h[2]]
		var e := EVENT_POINT.new()
		e.kind = "door"
		e.index = i
		e.position = VillageLayout.house_xform(h) * Vector3(d[0], 0, d[2] + 0.7)
		add_child(e)

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


## Pomar a leste da Horta: três fileiras de frutíferas (maçã, laranja, pera), cestos e caixotes.
func _build_orchard() -> void:
	_avoid.append([Vector2(ORCHARD.x, ORCHARD.z), 9.5])
	_flat(ORCHARD + Vector3(0, 0.018, 0), Vector2(16, 15), Color(0.36, 0.42, 0.2), 0.6)
	for row in 3:
		for col in 3:
			var p := ORCHARD + Vector3(-5.0 + col * 5.0 + rng.randf_range(-0.4, 0.4), 0, -5.0 + row * 5.0 + rng.randf_range(-0.4, 0.4))
			tree(FRUIT_TREES[(row + col) % 3], p, rng.randf_range(0.95, 1.15))
	prop("crate", ORCHARD + Vector3(-7.4, 0, 0.8), 0.3, 1.0, "box", Vector3(0.8, 0.8, 0.8))
	prop("crate", ORCHARD + Vector3(-7.3, 0.8, 0.8), -0.2, 0.75)
	prop("barrel", ORCHARD + Vector3(-7.5, 0, -0.4), 0.0, 1.0, "cyl", Vector3(0.38, 1.0, 0))


## Poste de direção perto do portão sul e quadro de avisos ao norte da praça.
func _build_signs() -> void:
	var at := Vector3(-1.8, 0, 20.5)
	add_child(SIGNPOST.make(at, [["Horta", FARM], ["Ruínas", RUINS], ["Goblins", CAMP], ["Horda", ARENA]]))
	_static_shape(Transform3D(Basis(), at), Vector3(0, 1.3, 0), _cyl_shape(0.25, 2.6))
	_no_grass.append([Vector2(at.x, at.z), 0.5])
	var board_at := Vector3(5.0, 0, -10.6)
	var yaw := atan2(-board_at.x, 4.0 - board_at.z)   # de frente para o centro da praça
	var board := prop("notice_board", board_at, yaw, 1.0, "box", Vector3(2.7, 2.8, 0.3))
	var notes := Label3D.new()
	notes.text = "GUILDA DOS AVENTUREIROS\n\nContratos para todos os ranks!\nFale com a Lina.\n\nCarruagem da guilda no portão norte."
	notes.font_size = 30
	notes.pixel_size = 0.004
	notes.outline_size = 0
	notes.modulate = Color(0.2, 0.12, 0.05)
	notes.width = 480
	notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notes.double_sided = false
	notes.position = Vector3(0, 1.6, 0.05)
	board.add_child(notes)


func _cyl_shape(r: float, h: float) -> CylinderShape3D:
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = h
	return c


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
func _build_farm() -> void:
	_avoid.append([Vector2(FARM.x, FARM.z), 15.0])
	_build_orchard()
	_avoid.append([Vector2(1, 24), 4.0])
	_flat(Vector3(1, 0.021, 19.5), Vector2(3.2, 17), Color(0.45, 0.35, 0.22))       # trilha praça -> horta
	_flat(FARM + Vector3(0, 0.019, 0.5), Vector2(20, 13.5), Color(0.4, 0.42, 0.22), 0.5)  # chão da horta
	_flat(FARM + Vector3(1, 0.021, -2), Vector2(2.6, 9), Color(0.45, 0.35, 0.22))
	# cerca da horta, com portão alinhado ao portão sul da vila
	var x := -10.0
	while x <= 10.0:
		if x != 0.0 and x != 2.0:
			prop("fence", FARM + Vector3(x, 0, -7), 0.0, 1.0, "box", Vector3(2.1, 1.0, 0.25))
		prop("fence", FARM + Vector3(x, 0, 7.5), 0.0, 1.0, "box", Vector3(2.1, 1.0, 0.25))
		x += 2.0
	var z := -6.0
	while z <= 6.5:
		prop("fence", FARM + Vector3(-11, 0, z), PI / 2, 1.0, "box", Vector3(2.1, 1.0, 0.25))
		prop("fence", FARM + Vector3(11, 0, z), PI / 2, 1.0, "box", Vector3(2.1, 1.0, 0.25))
		z += 2.0
	# canteiros 4 x 3 (os mais próximos do portão são liberados primeiro)
	for i in Game.FARM_PLOTS:
		var plot := PLOT.new()
		plot.index = i
		plot.position = FARM + Vector3(-4.2 + (i % 4) * 2.8, 0, -3.3 + (i / 4) * 2.8)
		add_child(plot)
	var kitchen := KITCHEN.new()
	kitchen.position = FARM + Vector3(7.5, 0, -3.5)
	add_child(kitchen)
	prop("crate", FARM + Vector3(8.6, 0, -1.4), 0.3, 1.0, "box", Vector3(0.8, 0.8, 0.8))
	prop("crate", FARM + Vector3(8.7, 0.8, -1.4), -0.2, 0.75)
	prop("barrel", FARM + Vector3(9.2, 0, -5.6), 0.0, 1.0, "cyl", Vector3(0.38, 1.0, 0))
	prop("barrel", FARM + Vector3(-9.0, 0, -5.4), 0.0, 1.0, "cyl", Vector3(0.38, 1.0, 0))
	prop("tree_oak", FARM + Vector3(-8.2, 0, 5.0), 0.8, 1.1, "cyl", Vector3(0.4, 3, 0))
	# girassóis encostados na cerca norte da horta
	for i in 7:
		var sx := -9.5 + i * 1.3 + rng.randf_range(-0.25, 0.25)
		if absf(sx - 1.0) < 2.2:
			continue   # portão
		prop("flower_sunflower", FARM + Vector3(sx, 0, -7.6), PI + rng.randf_range(-0.3, 0.3), rng.randf_range(0.85, 1.15))
	var lamp := prop("lamp", FARM + Vector3(3.6, 0, -7.6), PI, 1.0, "cyl", Vector3(0.12, 3.7, 0))
	DayNightFX.night_light(_light(lamp, Vector3(0, 3.3, 0.5), Color(1, 0.75, 0.4), 1.4, 8.0), 1.4)
	_scarecrow(FARM + Vector3(-7.6, 0, 1.2))
	var sign := Label3D.new()
	sign.text = "Horta da Vila"
	sign.font_size = 56
	sign.outline_size = 10
	sign.pixel_size = 0.006
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.modulate = Color(0.85, 1.0, 0.6)
	sign.position = FARM + Vector3(1, 2.6, -7)
	add_child(sign)


func _scarecrow(pos: Vector3) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = 0.5
	add_child(root)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.3, 0.17)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.55, 0.2, 0.15)
	var sack := StandardMaterial3D.new()
	sack.albedo_color = Color(0.8, 0.7, 0.45)
	var straw := StandardMaterial3D.new()
	straw.albedo_color = Color(0.95, 0.8, 0.35)
	var parts := [
		[BoxMesh.new(), Vector3(0.1, 2.0, 0.1), Vector3(0, 1.0, 0), wood],
		[BoxMesh.new(), Vector3(1.5, 0.08, 0.08), Vector3(0, 1.5, 0), wood],
		[BoxMesh.new(), Vector3(0.6, 0.7, 0.3), Vector3(0, 1.35, 0), cloth],
		[SphereMesh.new(), Vector3(0.36, 0.36, 0.36), Vector3(0, 2.0, 0), sack],
		[CylinderMesh.new(), Vector3(0.5, 0.06, 0.5), Vector3(0, 2.2, 0), straw],
		[CylinderMesh.new(), Vector3(0.22, 0.3, 0.22), Vector3(0, 2.35, 0), straw],
		[BoxMesh.new(), Vector3(0.12, 0.25, 0.1), Vector3(0.78, 1.42, 0), straw],
		[BoxMesh.new(), Vector3(0.12, 0.25, 0.1), Vector3(-0.78, 1.42, 0), straw],
	]
	for p in parts:
		var mi := MeshInstance3D.new()
		var m: Mesh = p[0]
		if m is BoxMesh:
			m.size = p[1]
		elif m is SphereMesh:
			m.radius = p[1].x / 2.0
			m.height = p[1].y
		else:
			m.top_radius = p[1].x / 2.0
			m.bottom_radius = p[1].x / 2.0
			m.height = p[1].y
		mi.mesh = m
		mi.material_override = p[3]
		mi.position = p[2]
		root.add_child(mi)


# ================================================================ campos (slimes)
func _build_fields() -> void:
	var soil := Color(0.36, 0.25, 0.15)
	var crop_mm := MultiMesh.new()
	crop_mm.transform_format = MultiMesh.TRANSFORM_3D
	var crop_scene: Node3D = FIELD_CROP.instantiate()
	crop_mm.mesh = (crop_scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	crop_scene.free()
	var xforms: Array[Transform3D] = []
	for plot in [Vector3(-14, 0, -24), Vector3(12, 0, -26), Vector3(-16, 0, -40), Vector3(15, 0, -42)]:
		_flat(plot + Vector3(0, 0.025, 0), Vector2(10, 7), soil, 0.25)
		for row in 5:
			for col in 12:
				if rng.randf() < 0.25:
					continue
				var p: Vector3 = plot + Vector3(-4.4 + col * 0.8, 0.0, -2.6 + row * 1.3)
				var cs := rng.randf_range(0.85, 1.25)
				xforms.append(Transform3D(Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * cs), p))
		_avoid.append([Vector2(plot.x, plot.z), 6.5])
		# cercas dos lotes
		for i in 5:
			prop("fence", plot + Vector3(-4 + i * 2, 0, -4.2), 0.0)
	crop_mm.instance_count = xforms.size()
	for i in xforms.size():
		crop_mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = crop_mm
	add_child(mmi)
	prop("barrel", Vector3(-8, 0, -22), 0.0, 1.0, "cyl", Vector3(0.38, 1, 0))
	prop("crate", Vector3(8, 0, -21), 0.6, 1.0, "box", Vector3(0.8, 0.8, 0.8))


# ================================================================ acampamento goblin
func _build_goblin_camp() -> void:
	_avoid.append([Vector2(CAMP.x, CAMP.z), 15.0])
	prop("tent", CAMP + Vector3(-5, 0, -7), 0.4, 1.0, "box", Vector3(2.0, 2.2, 2.0))
	prop("tent", CAMP + Vector3(5, 0, -6), -0.3, 1.0, "box", Vector3(2.0, 2.2, 2.0))
	prop("tent", CAMP + Vector3(2, 0, 8), 2.8, 1.2, "box", Vector3(2.0, 2.2, 2.0))
	var fire := prop("campfire", CAMP, 0.0, 1.0, "cyl", Vector3(0.6, 0.4, 0))
	_light(fire, Vector3(0, 1.0, 0), Color(1.0, 0.55, 0.2), 3.0, 14.0, true)
	prop("crate", CAMP + Vector3(-7, 0, 2), 0.3, 1.0, "box", Vector3(0.8, 0.8, 0.8))
	var note := STORY_POINT.new()   # o bilhete do Rei Goblin (missão "bilhete"), em cima do caixote
	note.npc_id = "camp_note"
	note.position = CAMP + Vector3(-7, 0.82, 2)
	add_child(note)
	prop("barrel", CAMP + Vector3(-7.5, 0, 3.2), 0.0, 1.0, "cyl", Vector3(0.38, 1, 0))
	prop("chest", CAMP + Vector3(8, 0, 3), -1.2, 1.0, "box", Vector3(0.9, 0.7, 0.6))
	for a in [0.4, 1.2, 2.2, 3.6, 4.4, 5.4]:
		var p := CAMP + Vector3(cos(a), 0, sin(a)) * 13.0
		prop("ruin_wall", p, -a + PI / 2, 0.8, "box", Vector3(4.2, 2.0, 0.9))


# ================================================================ ruínas (chefe)
func _build_ruins() -> void:
	_avoid.append([Vector2(RUINS.x, RUINS.z), 22.0])
	for i in 10:
		if i == 7:
			continue  # pilar caído
		var a := i / 10.0 * TAU
		var p := RUINS + Vector3(cos(a), 0, sin(a)) * 12.5
		prop("ruin_pillar", p, rng.randf() * TAU, 1.0 + rng.randf() * 0.3, "cyl", Vector3(0.5, 4.0, 0))
	for i in 7:
		var a := i / 7.0 * TAU + 0.2
		if abs(wrapf(a - PI / 2, -PI, PI)) < 0.5:
			continue  # entrada voltada para o sul (para a vila)
		var p := RUINS + Vector3(cos(a), 0, sin(a)) * 18.0
		prop("ruin_wall", p, -a + PI / 2, 1.2, "box", Vector3(4.2, 2.0, 0.9))
	prop("rock", RUINS + Vector3(-6, 0, 5), 0.5, 0.8, "cyl", Vector3(0.6, 0.8, 0))
	prop("chest", RUINS + Vector3(0, 0, -9), 0.0, 1.2, "box", Vector3(0.9, 0.7, 0.6))
	var torch := Node3D.new()
	torch.position = RUINS + Vector3(0, 0, -9)
	add_child(torch)
	_light(torch, Vector3(0, 2, 0), Color(1, 0.5, 0.25), 2.0, 12.0, true)


# ================================================================ arena do Desafio da Horda
func _build_arena() -> void:
	_avoid.append([Vector2(ARENA.x, ARENA.z), 37.0])
	_disc(ARENA + Vector3(0, 0.015, 0), 32.0, Color(0.36, 0.33, 0.28), 0.4)
	_disc(ARENA + Vector3(0, 0.02, 0), 30.5, Color(0.3, 0.42, 0.18), 0.4)
	_disc(ARENA + Vector3(0, 0.025, 0), 4.5, Color(0.42, 0.4, 0.36), 0.4)
	var n := 22
	for i in n:
		var a := TAU * i / n
		var p := ARENA + Vector3(cos(a), 0, sin(a)) * 33.5
		if i % 11 == 5:
			prop("ruin_wall", p, -a + PI / 2, 1.0, "box", Vector3(4.2, 2.0, 0.9))
		else:
			prop("ruin_pillar", p, rng.randf() * TAU, 1.0 + rng.randf() * 0.4, "cyl", Vector3(0.5, 4.0, 0))
	for i in 4:
		var a := TAU * (i + 0.5) / 4.0
		var fire := prop("campfire", ARENA + Vector3(cos(a), 0, sin(a)) * 32.0, a, 1.0, "cyl", Vector3(0.6, 0.4, 0))
		_light(fire, Vector3(0, 1.2, 0), Color(0.75, 0.45, 1.0), 3.0, 16.0, true)
	var rune := Node3D.new()
	rune.position = ARENA
	add_child(rune)
	_light(rune, Vector3(0, 3.0, 0), Color(0.7, 0.5, 1.0), 1.5, 14.0)


func start_survival() -> void:
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
	if modal != null:
		modal.queue_free()
		_on_modal_closed()
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
func _build_borders() -> void:
	for side in [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(MAP_HALF * 2 + 4 if side.x == 0 else 2.0, 20, MAP_HALF * 2 + 4 if side.z == 0 else 2.0)
		cs.shape = b
		body.position = side * (MAP_HALF + 1) + Vector3.UP * 10
		body.add_child(cs)
		add_child(body)
	# anel de pinheiros densos
	var t := -MAP_HALF
	while t <= MAP_HALF:
		for edge in 4:
			var d := MAP_HALF - rng.randf_range(0, 7)
			var p: Vector3
			match edge:
				0: p = Vector3(t, 0, -d)
				1: p = Vector3(t, 0, d)
				2: p = Vector3(d, 0, t)
				_: p = Vector3(-d, 0, t)
			prop("tree_pine", p, rng.randf() * TAU, rng.randf_range(1.1, 1.8))
		t += rng.randf_range(4.0, 6.5)


## Abetos e pinheiros nas encostas dos maciços (mais densos embaixo) e pedras nas faces de rocha.
func _mountain_nature() -> void:
	for m in MOUNTAINS:
		var c: Vector3 = m[0]
		var r: float = m[1]
		var peak: float = m[2]
		var n := int(r * r * 0.04)
		for i in n:
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf()) * r
			var p := c + Vector3(cos(a) * d, 0, sin(a) * d)
			if absf(p.x) > MAP_HALF - 4 or absf(p.z) > MAP_HALF - 4:
				continue
			var h: float = ground.height_at(p.x, p.z)
			var sl: float = ground.slope_at(p.x, p.z)
			if h > peak * 0.7:
				continue
			if sl > 0.45:
				if sl < 0.6 and rng.randf() < 0.25:   # mais íngreme que isso a pedra fica no ar
					var s := rng.randf_range(0.8, 2.0)
					p.y = h - 0.65 * s   # afunda: na encosta um lado fica no ar
					prop("rock", p, rng.randf() * TAU, s)
				continue
			if rng.randf() < 0.2 + 0.5 * (1.0 - h / peak):
				tree(_pick({"tree_fir": 5, "tree_pine": 3, "tree_birch": 0.6}), p, rng.randf_range(0.8, 1.4))


func _blocked(p: Vector3) -> bool:
	if ground.on_mountain(Vector2(p.x, p.z)) and (ground.slope_at(p.x, p.z) > 0.45 or ground.height_at(p.x, p.z) > 18.0):
		return true   # penhasco ou alto demais
	for a in _avoid:
		if Vector2(p.x, p.z).distance_to(a[0]) < a[1]:
			return true
	if abs(p.x) < 5.0 and p.z < -8 and p.z > -92:
		return true   # trilha norte
	if abs(p.z) < 5.0 and p.x > 10 and p.x < 66:
		return true   # trilha leste
	return false


## Floresta densa a leste. A natureza é espalhada em quatro etapas (floresta, resto do mapa, serra,
## capim), sempre nesta ordem: todas tiram do mesmo `rng`.
func _scatter_forest() -> void:
	var placed := 0
	var tries := 0
	while placed < 140 and tries < 3000:
		tries += 1
		var p := Vector3(rng.randf_range(28, MAP_HALF - 8), 0, rng.randf_range(-70, 70))
		if _blocked(p):
			continue
		tree(_pick({"tree_pine": 5, "tree_fir": 4, "tree_birch": 1.2}), p, rng.randf_range(0.8, 1.5))
		placed += 1


## Árvores esparsas e pedras no resto do mapa.
func _scatter_sparse() -> void:
	var placed := 0
	var tries := 0
	while placed < 110 and tries < 3000:
		tries += 1
		var p := Vector3(rng.randf_range(-MAP_HALF + 8, 28), 0, rng.randf_range(-MAP_HALF + 8, MAP_HALF - 8))
		if _blocked(p):
			continue
		var r := rng.randf()
		if r < 0.75:
			var kind := _pick({"tree_oak": 3.5, "tree_pine": 2.2, "tree_birch": 1.6, "tree_maple": 1.2,
					"tree_cherry": 0.5, "tree_fir": 0.8, "tree_apple": 0.6, "tree_orange": 0.4, "tree_pear": 0.4})
			tree(kind, p, rng.randf_range(0.8, 1.3))
		else:
			var s := rng.randf_range(0.6, 1.6)
			p.y = maxf(0.0, ground.height_at(p.x, p.z) - 0.3 * s)
			prop("rock", p, rng.randf() * TAU, s, "cyl", Vector3(0.65, 0.9, 0))
		placed += 1


## Capim e flores (fora das trilhas pintadas, das pegadas de props e da arena).
func _scatter_grass() -> void:
	if Network.is_server():
		return   # grama é só visual
	var keep_out := _no_grass.duplicate()
	keep_out.append([Vector2(ARENA.x, ARENA.z), 33.0])
	keep_out.append_array(VillageLayout.street_circles())
	keep_out.append([Vector2(VillageLayout.LARGO.x, VillageLayout.LARGO.z), 4.8])
	var sparse := [[Vector2(0, 4), 22.0], [Vector2(FARM.x, FARM.z), 12.0], [Vector2(-24, 4), 15.0],
		[Vector2(26, 4), 15.0]]
	if Loading.covering:
		# fileira por fileira, um quadro cada: é a etapa mais demorada da montagem
		await ground.scatter_grass(rng.seed + 7, 0.6, keep_out, sparse, 1.0,
			func(frac: float) -> void: Loading.set_progress(lerpf(_step_from, _step_to, frac)))
	else:
		ground.scatter_grass(rng.seed + 7, 0.6, keep_out, sparse)


# ================================================================ veios e cristais
## Materiais do encantamento: veios de ferro em volta do Acampamento Goblin e cristais nas Ruínas
## (data/balance/world_nodes.json). São de cada jogador: nada aqui é replicado.
func _setup_resource_nodes() -> void:
	for i in WorldHarvest.count(Balance.tables):
		var def := WorldHarvest.node_def(Balance.tables, i)
		if def.is_empty():
			continue
		var n := WorldResourceNode.from_def(def)
		add_child(n)
		resource_nodes.append(n)


# ================================================================ inimigos
func _setup_enemies() -> void:
	for p in [Vector3(-12, 0, -30), Vector3(10, 0, -32), Vector3(-5, 0, -42), Vector3(14, 0, -47),
			Vector3(-20, 0, -52), Vector3(4, 0, -57), Vector3(20, 0, -62), Vector3(-10, 0, -66),
			Vector3(-26, 0, -34), Vector3(26, 0, -36)]:
		spawns.append({"kind": "slime", "pos": p, "node": null, "timer": 0.0, "respawn": 30.0})
	for off in [Vector3(-6, 0, 3), Vector3(4, 0, 2), Vector3(-2, 0, -10), Vector3(8, 0, -3),
			Vector3(-9, 0, -4), Vector3(6, 0, 9)]:
		spawns.append({"kind": "goblin", "pos": CAMP + off, "node": null, "timer": 0.0, "respawn": 60.0})
	for off in [Vector3(-7, 0, 14), Vector3(7, 0, 14)]:
		spawns.append({"kind": "goblin", "pos": RUINS + off, "node": null, "timer": 0.0, "respawn": 90.0})
	# monstros da Defesa da Cidade reaproveitados aqui: soltam as essências do encantamento
	# (enemies.json). Reforços do Acampamento Goblin: arqueiros nas pontas e um xamã no fundo.
	for off in [Vector3(-11, 0, -8), Vector3(10, 0, 7)]:
		spawns.append({"kind": "goblin_arqueiro", "pos": CAMP + off, "node": null, "timer": 0.0, "respawn": 75.0})
	spawns.append({"kind": "goblin_xama", "pos": CAMP + Vector3(9, 0, -9), "node": null, "timer": 0.0, "respawn": 120.0})
	# fontes de +4 e +5: o Campeão (insígnia) guarda o Acampamento, os Brutos (Sombra) guardam as Ruínas
	# e os Goblins Dourados (Sagrado) ficam soltos pelo mapa e fogem de quem chega perto
	spawns.append({"kind": "goblin_campeao", "pos": CAMP + Vector3(2, 0, -5), "node": null, "timer": 0.0, "respawn": 300.0})
	for off in [Vector3(-11, 0, 4), Vector3(11, 0, 4)]:
		spawns.append({"kind": "goblin_bruto", "pos": RUINS + off, "node": null, "timer": 0.0, "respawn": 150.0})
	for p in [Vector3(30, 0, 44), Vector3(-30, 0, -72)]:
		spawns.append({"kind": "goblin_dourado", "pos": p, "node": null, "timer": 0.0, "respawn": 240.0})
	# esqueletos guardam o caminho das Ruínas (guerreiros na trilha, arqueiros nas pontas) e os fundos
	# (o mago e o Cavaleiro), todos fora do alcance de quem luta com o rei no centro
	for off in [Vector3(-5, 0, 24), Vector3(5, 0, 24), Vector3(0, 0, 30)]:
		spawns.append({"kind": "esqueleto", "pos": RUINS + off, "node": null, "timer": 0.0, "respawn": 90.0})
	for off in [Vector3(-14, 0, 22), Vector3(14, 0, 22)]:
		spawns.append({"kind": "esqueleto_arqueiro", "pos": RUINS + off, "node": null, "timer": 0.0, "respawn": 100.0})
	spawns.append({"kind": "esqueleto_mago", "pos": RUINS + Vector3(-18, 0, -12), "node": null, "timer": 0.0, "respawn": 150.0})
	spawns.append({"kind": "esqueleto_cavaleiro", "pos": RUINS + Vector3(18, 0, -12), "node": null, "timer": 0.0, "respawn": 300.0})
	# bombardeiros rondam o Acampamento Goblin e as slimes de gelo ficam no meio das comuns, nos campos
	for off in [Vector3(-13, 0, 6), Vector3(12, 0, -10)]:
		spawns.append({"kind": "goblin_bombardeiro", "pos": CAMP + off, "node": null, "timer": 0.0, "respawn": 90.0})
	for p in [Vector3(-18, 0, -44), Vector3(16, 0, -54)]:
		spawns.append({"kind": "slime_gelo", "pos": p, "node": null, "timer": 0.0, "respawn": 60.0})
	# Ninho de Slimes: a mãe no meio, explosivos em volta dela e os velozes por fora
	spawns.append({"kind": "slime_mae", "pos": NEST, "node": null, "timer": 0.0, "respawn": 120.0})
	for i in 3:
		var a := i * TAU / 3.0 + 0.5
		spawns.append({"kind": "slime_explosivo", "pos": NEST + Vector3(cos(a), 0, sin(a)) * 4.5, "node": null,
			"timer": 0.0, "respawn": 60.0})
	for i in 4:
		var a := i * TAU / 4.0
		spawns.append({"kind": "slime_veloz", "pos": NEST + Vector3(cos(a), 0, sin(a)) * 8.5, "node": null,
			"timer": 0.0, "respawn": 45.0})
	spawns.append_array(region_spawns)
	for s in spawns:
		_spawn(s)


func _spawn(entry: Dictionary) -> void:
	var e := ENEMY.new()
	e.kind = entry.kind
	e.position = entry.pos + Vector3.UP * 0.2
	add_child(e)
	entry.node = e
	e.died.connect(_on_spawn_died.bind(entry))


func _on_spawn_died(_en: Enemy, entry: Dictionary) -> void:
	entry.node = null
	entry.timer = entry.respawn


func summon_minions(pos: Vector3, n: int, kind := "goblin") -> void:
	for i in n:
		var e := ENEMY.new()
		e.kind = kind
		e.position = pos + Vector3(cos(i * PI) * 4.0, 0.3, sin(i * PI + 0.5) * 4.0)
		add_child(e)
		FX.burst(e.position + Vector3.UP, Color(0.3, 0.5, 0.15), 25, 5.0)


func _check_boss() -> void:
	if Game.quest_state("goblin_king") == "active" and not Game.flags.get("king_dead", false):
		if Network.is_client():
			if boss == null or not is_instance_valid(boss) or boss.dead:
				Network.request_boss()   # o servidor cria (se ainda não existir) e todos veem
			return
		if boss == null or not is_instance_valid(boss):
			boss = ENEMY.new()
			boss.kind = "goblin_king"
			boss.position = RUINS + Vector3.UP * 0.3
			add_child(boss)
			hud.boss = boss


## Servidor: o rei aparece quando algum jogador está com a missão ativa.
func server_spawn_boss() -> void:
	if boss != null and is_instance_valid(boss) and not boss.dead:
		return
	boss = ENEMY.new()
	boss.kind = "goblin_king"
	boss.position = RUINS + Vector3.UP * 0.3
	add_child(boss)


func _process(delta: float) -> void:
	_t += delta
	_boss_scan -= delta
	if _boss_scan <= 0.0 and hud != null and player != null:
		_boss_scan = 0.5
		_scan_boss()
	for f in flicker_lights:
		f[0].light_energy = f[1] * (0.85 + 0.15 * sin(_t * 9.0 + f[2]) + 0.08 * sin(_t * 23.0 + f[2]))
	for s in spawns:
		if s.node == null and s.timer > 0:
			s.timer -= delta
			if s.timer <= 0:
				if _any_player_near(s.pos, 25.0):
					s.timer = 5.0
				else:
					_spawn(s)


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
	elif event.is_action_pressed("quest_log"):
		_open_menu(2)
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


## Livro do mapa e do grupo, aberto na aba `tab` (WORLD_MAP_UI.TAB_MAP ou TAB_PARTY).
func open_world_map(tab := 0) -> void:
	var m := WORLD_MAP_UI.new()
	m.start_tab = tab
	m.world = self
	m.capture = map_capture
	_open_modal(m)


func _open_menu(tab: int) -> void:
	var m := GAME_MENU.new()
	m.start_tab = tab
	_open_modal(m)


## Narração de abertura da história (personagem novo, primeira vez no mundo). Não roda nos testes.
func _play_intro() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or "--smoketest" in args \
			or Array(args).any(func(a: String) -> bool: return a.begins_with("--nettest")):
		return
	await get_tree().create_timer(1.5).timeout
	if is_inside_tree() and modal == null and not Loading.covering and survival == null:
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


func open_shop() -> void:
	_open_modal(SHOP.new())


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


## Painel de um ponto que veio da praça (hub_point.interact): mesa de guerra, Mestre Orin, recordes ou as
## doações de uma construção da base.
func open_point_panel(point: Node) -> void:
	var ui: Control = null
	match str(point.get("kind")):
		"war_table":
			ui = WAR_TABLE.new()
		"passive_master":
			ui = PASSIVE_MASTER.new()
		"records":
			ui = RECORDS.new()
		"building":
			var b := BASE_BUILDING.new()
			b.building_id = str(point.get("building_id"))
			ui = b
		"merchant":
			open_shop()
			return
	if ui != null:
		open_modal(ui)


func open_modal(c: Control) -> void:
	_open_modal(c)


func _open_modal(c: Control) -> void:
	if modal != null:
		return
	modal = c
	ui_layer.add_child(c)
	c.closed.connect(_on_modal_closed)
	_set_paused(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.visible = false


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
	player.revive(VILLAGE_SPAWN)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if Network.is_online():
		return   # no multiplayer o servidor cuida dos inimigos
	# inimigos voltam para casa
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.state != "idle":
			e._set_state("return")


# ================================================================ guilda, NPCs novos e mapas
## A Guilda dos Aventureiros no quadro de avisos (Lina + Quadro de Contratos), a carruagem da guilda do
## lado de fora do portão norte e os moradores que pedem missões secundárias, na vila e pelo vale.
func _build_guild() -> void:
	var board_at := Vector3(5.0, 0, -10.6)
	var fwd := (Vector3(0, 0, 4) - board_at).normalized()
	add_child(RegionBuilder.point("board", board_at + fwd * 1.1))
	var lina_at := Vector3(2.3, 0, -9.6)
	add_child(RegionBuilder.npc("lina", lina_at, atan2(-lina_at.x, 4.0 - lina_at.z)))
	var guild := Label3D.new()
	guild.text = "GUILDA DOS AVENTUREIROS"
	guild.font_size = 64
	guild.outline_size = 10
	guild.pixel_size = 0.006
	guild.modulate = Color(0.55, 0.8, 1.0)
	guild.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	guild.position = board_at + Vector3(0, 3.5, 0)
	add_child(guild)
	var coach_at: Vector3 = Regions.coach_point("vila")
	add_child(RegionBuilder.wagon(coach_at + Vector3(-3.2, 0, -0.5), 0.0))
	_no_grass.append([Vector2(coach_at.x - 3.2, coach_at.z - 0.5), 2.2])
	add_child(RegionBuilder.npc("coach", coach_at, 0.0))
	# moradores com pedidos
	add_child(RegionBuilder.npc("rufus", Vector3(4.6, 0, -16.6), PI))       # guarda no portão norte
	add_child(RegionBuilder.npc("zelia", Vector3(-2.6, 0, 12.6), PI))       # na porta da casa ao sul
	add_child(RegionBuilder.npc("tonico", Vector3(-21.0, 0, -22.0), PI / 2))  # nos campos ao norte
	add_child(RegionBuilder.npc("ravi", Vector3(44.0, 0, 3.6), -PI / 2))     # na trilha leste, depois do portão
	add_child(RegionBuilder.npc("osvaldo", Vector3(6.0, 0, -76.0), PI))      # na entrada das ruínas
	add_child(RegionBuilder.point("gato", Vector3(22.5, 0, 30.5), -0.8))     # no pomar


## Bosque, Mina e Pico: cada um com chão, cenário, NPCs, carruagem e monstros (Regions/RegionBuilder).
func _build_regions() -> void:
	for id in Regions.ORDER:
		if id != "vila":
			region_grounds[id] = RegionBuilder.build(self, id)


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
		var keep_out: Array = []
		for k in _no_grass:
			var c: Vector2 = k[0]
			if absf(c.x - o.x) <= half + 5.0 and absf(c.y - o.z) <= half + 5.0:
				keep_out.append([c - Vector2(o.x, o.z), k[1]])
		var density := 0.45 if id == "bosque" else 0.18
		var from := lerpf(_step_from, _step_to, float(i) / ids.size())
		var to := lerpf(_step_from, _step_to, float(i + 1) / ids.size())
		if Loading.covering:
			await g.scatter_grass(rng.seed + 31 + i, density, keep_out, [], 0.6,
				func(frac: float) -> void: Loading.set_progress(lerpf(from, to, frac)))
		else:
			g.scatter_grass(rng.seed + 31 + i, density, keep_out, [], 0.6)


## Viagem pela carruagem da guilda: escurece a tela, leva o jogador ao ponto de chegada do mapa e mostra
## o cartão com o nome do lugar.
func travel_to(region: String) -> void:
	if player == null or player.dead or not Regions.DATA.has(region):
		return
	if not Regions.unlocked(region, Game.rank()):
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
	tw.tween_callback(_arrive.bind(region))
	tw.tween_interval(0.35)
	tw.tween_property(_travel_fade, "color:a", 0.0, 0.5)
	tw.tween_callback(func() -> void: player.input_locked = false)


func _arrive(region: String) -> void:
	var to: Vector3 = Regions.arrive_point(region)
	player.global_position = to
	player.velocity = Vector3.ZERO
	var back: Vector3 = Regions.coach_point(region)
	var d := to - back
	if region != "vila":
		player.model.rotation.y = atan2(-d.x, -d.z)   # de costas para a carruagem, olhando para o mapa
	Sfx.play("portal", -6.0)
	if story_card:
		story_card.enqueue("CARRUAGEM DA GUILDA", Regions.display_name(region))


## Chefes que nascem como monstros comuns (o Lich, a Slime Rainha não é chefe): a barra aparece quando o
## jogador chega perto, como a do Rei Goblin.
func _scan_boss() -> void:
	if hud.boss != null and is_instance_valid(hud.boss) and not hud.boss.dead:
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Enemy and e.is_boss and not e.dead and e.global_position.distance_to(player.global_position) < 40.0:
			hud.boss = e
			return
