extends Node3D
## Monta o mundo (vila, campos, acampamento goblin, ruínas), gerencia inimigos, UI modal e morte.

const M := {
	"house": preload("res://assets/models/house.glb"),
	"tree_pine": preload("res://assets/models/tree_pine.glb"),
	"tree_oak": preload("res://assets/models/tree_oak.glb"),
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
}
const ENEMY := preload("res://scripts/enemies/enemy.gd")
const NPC := preload("res://scripts/world/npc.gd")
const PLAYER := preload("res://scripts/player/player.gd")
const HUD := preload("res://scripts/ui/hud.gd")
const DIALOGUE := preload("res://scripts/ui/dialogue_ui.gd")
const GAME_MENU := preload("res://scripts/ui/game_menu.gd")
const SHOP := preload("res://scripts/ui/shop_ui.gd")
const PAUSE := preload("res://scripts/ui/pause_menu.gd")
const PORTAL := preload("res://scripts/world/challenge_portal.gd")
const SURVIVAL := preload("res://scripts/survival/survival_mode.gd")
const HORDE_INVITE := preload("res://scripts/ui/horde_invite_ui.gd")
const PLOT := preload("res://scripts/farm/farm_plot.gd")
const KITCHEN := preload("res://scripts/farm/kitchen.gd")
const PLANT_UI := preload("res://scripts/ui/plant_ui.gd")
const COOKING_UI := preload("res://scripts/ui/cooking_ui.gd")

const MAP_HALF := 125.0
const VILLAGE_SPAWN := Vector3(0, 0.3, 6)
const RUINS := Vector3(0, 0, -100)
const CAMP := Vector3(62, 0, 0)
const ARENA := Vector3(-72, 0, -10)     # Desafio da Horda
const PORTAL_POS := Vector3(-8, 0, -9.5)
const FARM := Vector3(0, 0, 33)          # Horta da Vila (saída sul)

var player: Player
var hud
var ui_layer: CanvasLayer
var modal: Control = null
var boss: Enemy = null
var survival: Node3D = null
var spawns: Array = []
var flicker_lights: Array = []
var rng := RandomNumberGenerator.new()
var _avoid: Array = []   # [Vector2 centro, raio] áreas sem vegetação aleatória
var _t := 0.0


func _ready() -> void:
	rng.seed = 20261113
	_build_environment()
	_build_ground()
	_build_village()
	_build_farm()
	_build_fields()
	_build_goblin_camp()
	_build_ruins()
	_build_arena()
	_build_borders()
	_scatter_nature()
	if not Network.is_client():
		_setup_enemies()   # no cliente, os inimigos chegam do servidor
	if Network.is_server():
		# servidor dedicado: só o mundo, os inimigos e as réplicas dos jogadores
		Network.world_ready(self)
		return

	player = PLAYER.new()
	add_child(player)
	player.died.connect(_on_player_died)

	hud = HUD.new()
	hud.player = player
	add_child(hud)
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui_layer)

	Game.quests_changed.connect(_check_boss)
	_check_boss()
	if Game.quests.is_empty() and Game.kills == 0:
		Game.notify.emit("Bem-vindo a Valdoria! Fale com o Ancião Bram (!) na praça.", Color(1, 0.9, 0.6))
		Game.notify.emit("Plante e cozinhe na Horta, saindo pelo portão sul da vila.", Color(0.8, 1.0, 0.6))
	if Network.is_client():
		var invite := HORDE_INVITE.new()
		invite.world = self
		add_child(invite)
		Game.notify.emit("Conectado como %s — %d jogador(es) online." % [Network.my_name, Network.players.size()], Color(0.6, 0.9, 1.0))
		Network.world_ready(self)


func _exit_tree() -> void:
	Network.world_closed(self)


# ================================================================ ambiente
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.28, 0.48, 0.82)
	sm.sky_horizon_color = Color(0.72, 0.8, 0.9)
	sm.ground_horizon_color = Color(0.72, 0.8, 0.9)
	sm.ground_bottom_color = Color(0.25, 0.3, 0.25)
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.8, 0.9)
	env.fog_density = 0.0025
	env.fog_sky_affect = 0.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)


func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(MAP_HALF * 2.6, MAP_HALF * 2.6)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	var grad := Gradient.new()
	grad.set_color(0, Color(0.2, 0.38, 0.13))
	grad.set_color(1, Color(0.36, 0.55, 0.2))
	tex.color_ramp = grad
	mat.albedo_texture = tex
	mat.uv1_scale = Vector3(30, 30, 30)
	mat.roughness = 1.0
	ground.material_override = mat
	add_child(ground)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(MAP_HALF * 2.6, 1, MAP_HALF * 2.6)
	cs.shape = box
	cs.position.y = -0.5
	body.add_child(cs)
	add_child(body)

	var dirt := Color(0.45, 0.35, 0.22)
	_flat(Vector3(0, 0.02, -50), Vector2(4.5, 80), dirt)          # trilha norte
	_flat(Vector3(38, 0.02, 0), Vector2(52, 4.5), dirt)           # trilha leste
	_disc(Vector3(0, 0.018, 1), 10.0, Color(0.5, 0.45, 0.36))     # praça
	_disc(RUINS + Vector3(0, 0.02, 0), 15.0, Color(0.42, 0.42, 0.4))
	_disc(CAMP + Vector3(0, 0.02, 0), 13.0, Color(0.4, 0.32, 0.2))


func _flat(pos: Vector3, size: Vector2, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var p := PlaneMesh.new()
	p.size = size
	mi.mesh = p
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	mi.material_override = m
	mi.position = pos
	add_child(mi)


func _disc(pos: Vector3, r: float, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = r
	cy.bottom_radius = r
	cy.height = 0.02
	cy.radial_segments = 32
	mi.mesh = cy
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	mi.material_override = m
	mi.position = pos
	add_child(mi)


## Instancia um modelo e (opcionalmente) uma colisão simples ("box" ou "cyl").
func prop(model: String, pos: Vector3, yaw := 0.0, s := 1.0, shape := "", size := Vector3.ONE) -> Node3D:
	var inst: Node3D = M[model].instantiate()
	inst.position = pos
	inst.rotation.y = yaw
	inst.scale = Vector3.ONE * s
	add_child(inst)
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


func _light(parent: Node3D, local: Vector3, color: Color, energy: float, rng_range: float, flicker := false) -> void:
	var l := OmniLight3D.new()
	l.position = local
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng_range
	l.shadow_enabled = false
	parent.add_child(l)
	if flicker:
		flicker_lights.append([l, energy, randf() * 10.0])


# ================================================================ vila
func _build_village() -> void:
	_avoid.append([Vector2(0, 4), 26.0])
	prop("well", Vector3(0, 0, 0), 0.0, 1.0, "cyl", Vector3(0.95, 1.2, 0))
	var houses := [
		[Vector3(-13, 0, -6), PI / 2], [Vector3(-13, 0, 7), PI / 2],
		[Vector3(13, 0, -6), -PI / 2], [Vector3(13, 0, 7), -PI / 2],
		[Vector3(-5, 0, 16), PI], [Vector3(6, 0, 16), PI],
	]
	for h in houses:
		prop("house", h[0], h[1], 1.0, "box", Vector3(5.2, 3.2, 4.2))
	for p in [Vector3(-5, 0, -5), Vector3(5, 0, -5), Vector3(-6, 0, 8), Vector3(6, 0, 8)]:
		var lamp := prop("lamp", p, atan2(-p.x, -p.z), 1.0, "cyl", Vector3(0.12, 2.8, 0))
		_light(lamp, Vector3(0, 2.4, 0.5), Color(1, 0.75, 0.4), 1.6, 9.0)
	# barraca da mercadora
	prop("crate", Vector3(8.2, 0, 0.6), 0.2, 1.0, "box", Vector3(0.8, 0.8, 0.8))
	prop("crate", Vector3(8.3, 0, 1.6), -0.1, 1.0, "box", Vector3(0.8, 0.8, 0.8))
	prop("crate", Vector3(8.25, 0.8, 1.1), 0.5, 0.8)
	prop("barrel", Vector3(8.0, 0, 3.0), 0.0, 1.0, "cyl", Vector3(0.38, 1.0, 0))
	prop("barrel", Vector3(8.6, 0, 3.8), 0.0, 1.0, "cyl", Vector3(0.38, 1.0, 0))
	prop("chest", Vector3(7.6, 0, -0.6), -PI / 2, 1.0, "box", Vector3(0.9, 0.7, 0.6))
	prop("barrel", Vector3(-11, 0, 0.5), 0.0, 1.0, "cyl", Vector3(0.38, 1.0, 0))
	prop("crate", Vector3(-10.5, 0, -1.2), 0.4, 1.0, "box", Vector3(0.8, 0.8, 0.8))
	prop("tree_oak", Vector3(-7, 0, 2), 0.3, 0.9, "cyl", Vector3(0.4, 3, 0))
	# cercas: perímetro x[-19,19], z[-13,23], com aberturas ao norte e a leste
	var x := -18.0
	while x <= 18.0:
		if abs(x) > 3.0:
			prop("fence", Vector3(x, 0, -13), 0.0, 1.0, "box", Vector3(2.1, 1.0, 0.25))
		if x != 0.0 and x != 2.0:   # portão sul, para a horta
			prop("fence", Vector3(x, 0, 23), 0.0, 1.0, "box", Vector3(2.1, 1.0, 0.25))
		x += 2.0
	var z := -12.0
	while z <= 22.0:
		prop("fence", Vector3(-19, 0, z), PI / 2, 1.0, "box", Vector3(2.1, 1.0, 0.25))
		if abs(z) > 3.0:
			prop("fence", Vector3(19, 0, z), PI / 2, 1.0, "box", Vector3(2.1, 1.0, 0.25))
		z += 2.0
	# NPCs
	var elder := NPC.new()
	elder.npc_id = "elder"
	elder.position = Vector3(-3, 0, -2.5)
	elder.rotation.y = atan2(3.0, 8.5)
	add_child(elder)
	var merchant := NPC.new()
	merchant.npc_id = "merchant"
	merchant.position = Vector3(6.8, 0, 1.6)
	merchant.rotation.y = -PI / 2
	add_child(merchant)
	var portal := PORTAL.new()
	portal.position = PORTAL_POS
	add_child(portal)


# ================================================================ horta da vila
func _build_farm() -> void:
	_avoid.append([Vector2(FARM.x, FARM.z), 15.0])
	_avoid.append([Vector2(1, 24), 4.0])
	_flat(Vector3(1, 0.021, 19.5), Vector2(3.2, 17), Color(0.45, 0.35, 0.22))       # trilha praça -> horta
	_flat(FARM + Vector3(0, 0.019, 0.5), Vector2(20, 13.5), Color(0.4, 0.42, 0.22))  # chão da horta
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
	var lamp := prop("lamp", FARM + Vector3(3.6, 0, -7.6), PI, 1.0, "cyl", Vector3(0.12, 2.8, 0))
	_light(lamp, Vector3(0, 2.4, 0.5), Color(1, 0.75, 0.4), 1.4, 8.0)
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
	var crop := PrismMesh.new()
	crop.size = Vector3(0.35, 0.55, 0.35)
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.45, 0.65, 0.15)
	crop.material = cm
	crop_mm.mesh = crop
	var xforms: Array[Transform3D] = []
	for plot in [Vector3(-14, 0, -24), Vector3(12, 0, -26), Vector3(-16, 0, -40), Vector3(15, 0, -42)]:
		_flat(plot + Vector3(0, 0.025, 0), Vector2(10, 7), soil)
		for row in 5:
			for col in 12:
				if rng.randf() < 0.25:
					continue
				var p: Vector3 = plot + Vector3(-4.4 + col * 0.8, 0.27, -2.6 + row * 1.3)
				xforms.append(Transform3D(Basis().rotated(Vector3.UP, rng.randf() * TAU), p))
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
	_disc(ARENA + Vector3(0, 0.015, 0), 32.0, Color(0.36, 0.33, 0.28))
	_disc(ARENA + Vector3(0, 0.02, 0), 30.5, Color(0.3, 0.42, 0.18))
	_disc(ARENA + Vector3(0, 0.025, 0), 4.5, Color(0.42, 0.4, 0.36))
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


func _blocked(p: Vector3) -> bool:
	for a in _avoid:
		if Vector2(p.x, p.z).distance_to(a[0]) < a[1]:
			return true
	if abs(p.x) < 5.0 and p.z < -8 and p.z > -92:
		return true   # trilha norte
	if abs(p.z) < 5.0 and p.x > 10 and p.x < 66:
		return true   # trilha leste
	return false


func _scatter_nature() -> void:
	# floresta densa a leste
	var placed := 0
	var tries := 0
	while placed < 140 and tries < 3000:
		tries += 1
		var p := Vector3(rng.randf_range(28, MAP_HALF - 8), 0, rng.randf_range(-70, 70))
		if _blocked(p):
			continue
		prop("tree_pine", p, rng.randf() * TAU, rng.randf_range(0.8, 1.5), "cyl", Vector3(0.35, 3, 0))
		placed += 1
	# árvores esparsas e pedras no resto do mapa
	placed = 0
	tries = 0
	while placed < 110 and tries < 3000:
		tries += 1
		var p := Vector3(rng.randf_range(-MAP_HALF + 8, 28), 0, rng.randf_range(-MAP_HALF + 8, MAP_HALF - 8))
		if _blocked(p):
			continue
		var r := rng.randf()
		if r < 0.45:
			prop("tree_oak", p, rng.randf() * TAU, rng.randf_range(0.8, 1.3), "cyl", Vector3(0.4, 3, 0))
		elif r < 0.75:
			prop("tree_pine", p, rng.randf() * TAU, rng.randf_range(0.8, 1.4), "cyl", Vector3(0.35, 3, 0))
		else:
			var s := rng.randf_range(0.6, 1.6)
			prop("rock", p, rng.randf() * TAU, s, "cyl", Vector3(0.65, 0.9, 0))
		placed += 1
	if Network.is_server():
		return   # grama é só visual
	# tufos de grama (MultiMesh)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var blade := PrismMesh.new()
	blade.size = Vector3(0.1, 0.32, 0.04)
	var gm := StandardMaterial3D.new()
	gm.vertex_color_use_as_albedo = true
	gm.roughness = 1.0
	blade.material = gm
	mm.mesh = blade
	var pts: Array[Vector3] = []
	while pts.size() < 16000:
		var c := Vector3(rng.randf_range(-MAP_HALF, MAP_HALF), 0.14, rng.randf_range(-MAP_HALF, MAP_HALF))
		if Vector2(c.x, c.z).distance_to(Vector2(ARENA.x, ARENA.z)) < 32.5:
			continue
		if Vector2(c.x, c.z).distance_to(Vector2(0, 1)) < 11.0 or (abs(c.x) < 3.0 and c.z < -8) or (abs(c.z) < 3.0 and c.x > 10 and c.x < 64):
			continue
		if (abs(c.x - FARM.x) < 11.0 and abs(c.z - FARM.z) < 7.5) or (abs(c.x - 1.0) < 1.8 and c.z > 11.0 and c.z < 27.0):
			continue   # horta e trilha
		for k in 4:  # tufos com várias folhas
			pts.append(c + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2)))
	mm.instance_count = pts.size()
	for i in pts.size():
		var p := pts[i]
		var bas := Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.4))
		mm.set_instance_transform(i, Transform3D(bas, p))
		mm.set_instance_color(i, Color(0.2, 0.4, 0.12).lerp(Color(0.38, 0.56, 0.18), rng.randf()))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


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


func summon_minions(pos: Vector3, n: int) -> void:
	for i in n:
		var e := ENEMY.new()
		e.kind = "goblin"
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


func _open_menu(tab: int) -> void:
	var m := GAME_MENU.new()
	m.start_tab = tab
	_open_modal(m)


func open_dialogue(speaker: String, pages: Array, focus: Node3D = null) -> void:
	var d := DIALOGUE.new()
	d.speaker = speaker
	d.pages = pages
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


func open_plant_menu(plot_index: int) -> void:
	var ui := PLANT_UI.new()
	ui.plot_index = plot_index
	_open_modal(ui)


func open_cooking(kitchen: Node = null) -> void:
	var ui := COOKING_UI.new()
	ui.kitchen = kitchen
	_open_modal(ui)


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
	var lost := int(Game.gold * 0.1)
	Game.gold -= lost
	modal = null
	_set_paused(false)
	player.revive(VILLAGE_SPAWN)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if lost > 0:
		Game.notify.emit("Você perdeu %d ouro." % lost, Color(1, 0.6, 0.5))
	if Network.is_online():
		return   # no multiplayer o servidor cuida dos inimigos
	# inimigos voltam para casa
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.state != "idle":
			e._set_state("return")
