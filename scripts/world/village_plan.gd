@tool
extends Node3D
## Raiz de scenes/village.tscn. No editor monta em volta das construções uma prévia do resto da vila, com os
## mesmos modelos, a mesma luz (WorldLighting) e o mesmo estilo toon do jogo: ruas, praça, cerca, lampiões,
## cerejeiras, enfeites de Natal, Horta, pomar, placas, portal, os NPCs (bonecos com o nome) e os pontos da
## antiga praça (Forja, Celeiro, Muralha, Orin...). Tudo isso continua montado pelo código no jogo (as
## posições ficam no VillageLayout); aqui é só referência: não dá para selecionar nem vai para o arquivo.
## O que se edita são as construções (VillageBuilding). "show_plan" desliga a prévia.
##
## Os scripts do jogo são carregados com load() e não por nome de classe: a cena também é lida pelos
## testes unitários (VillageLayout.buildings()), e lá um script que dependa de autoload não compila.

const GROUND_COLOR := Color(0.36, 0.5, 0.25)
const PLAZA_COLOR := Color(0.5, 0.45, 0.36)
const DIRT := Color(0.45, 0.35, 0.22)
const POINT_COLOR := Color(0.85, 0.3, 0.9, 0.5)
const NPC_COLOR := Color(1.0, 0.85, 0.3)
const NPC_NAMES := {"elder": "Ancião Bram", "kael": "Kael", "lina": "Lina", "rufus": "Rufus", "zelia": "Zélia"}
const POINT_NAMES := {"passive_master": "Mestre Orin", "war_table": "Mesa de guerra", "records": "Recordes"}

## Mostra a prévia do resto da vila (desligue para ver só as construções).
@export var show_plan := true:
	set(v):
		show_plan = v
		_rebuild()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		build_plan()


## Monta a prévia (o editor chama sozinho; as ferramentas de foto chamam direto).
func build_plan() -> void:
	var old := get_node_or_null("Planta")
	if old != null:
		remove_child(old)
		old.free()
	if not show_plan:
		return
	var plan := Node3D.new()
	plan.name = "Planta"
	add_child(plan)
	load("res://scripts/world/world_lighting.gd").build(plan)
	_ground(plan)
	_props(plan)
	_christmas(plan)
	_people(plan)
	var toon: GDScript = load("res://scripts/world/toon_look.gd")
	for mi: MeshInstance3D in plan.find_children("*", "MeshInstance3D", true, false):
		toon.convert_mesh(mi)


## Chão, ruas, praça, Largo dos Ecos, trilhas, Horta e pomar.
func _ground(plan: Node3D) -> void:
	_box(plan, Vector3(0, -0.1, 8), Vector3(130, 0.1, 110), GROUND_COLOR)
	for st in VillageLayout.STREETS:
		var sz: Vector2 = st[1]
		_box(plan, st[0], Vector3(sz.x, 0.02, sz.y), VillageLayout.STREET_COLOR)
	_disc(plan, Vector3(0, 0, 1), 10.0, PLAZA_COLOR)
	_disc(plan, VillageLayout.LARGO, 4.8, Color(0.55, 0.5, 0.42))
	_box(plan, Vector3(1, 0, 19.5), Vector3(3.2, 0.015, 17), DIRT)                     # praça -> Horta
	_box(plan, Vector3(0, 0, -40), Vector3(4.5, 0.015, 50), DIRT)                       # trilha norte
	_box(plan, Vector3(48, 0, 0), Vector3(20, 0.015, 4.5), DIRT)                        # trilha leste
	_box(plan, Vector3(-40, 0, 0), Vector3(9, 0.015, 3.6), DIRT)                        # para a arena
	var farm := VillageLayout.FARM
	_box(plan, farm + Vector3(0, 0, 0.5), Vector3(20, 0.02, 13.5), Color(0.4, 0.42, 0.22))
	for i in 12:   # canteiros 4 x 3
		_box(plan, farm + Vector3(-4.2 + (i % 4) * 2.8, 0, -3.3 + (i / 4) * 2.8), Vector3(2.2, 0.12, 2.2),
			Color(0.3, 0.2, 0.12))
	_box(plan, VillageLayout.ORCHARD, Vector3(16, 0.02, 15), Color(0.36, 0.42, 0.2))
	_label(plan, farm + Vector3(0, 3, 0), "Horta")
	_label(plan, VillageLayout.ORCHARD + Vector3(0, 6, 0), "Pomar")


## Cerca da vila e da Horta, lampiões, cerejeiras, árvores do pomar, placas e o portal.
func _props(plan: Node3D) -> void:
	for f in VillageLayout.fence_posts():
		_model(plan, "fence", f[0], f[1])
	for f in VillageLayout.farm_fence_posts():
		_model(plan, "fence", f[0], f[1])
	var cd: GDScript = load("res://scripts/world/christmas_decor.gd")
	for p: Vector3 in VillageLayout.LAMPS_SQUARE + VillageLayout.LAMPS_STREET:
		cd.lamp_garland(_model(plan, "lamp", p, atan2(-p.x, -p.z)))
	_model(plan, "lamp", VillageLayout.FARM + Vector3(3.6, 0, -7.6), PI)
	for c in VillageLayout.CHERRIES:
		_model(plan, "tree_cherry", c[0], c[1], c[2])
	var fruit := ["tree_apple", "tree_orange", "tree_pear"]
	for row in 3:
		for col in 3:
			_model(plan, fruit[(row + col) % 3], VillageLayout.ORCHARD + Vector3(-5.0 + col * 5.0, 0, -5.0 + row * 5.0))
	_model(plan, "signpost", VillageLayout.SIGNPOST)
	var b := VillageLayout.NOTICE_BOARD
	_model(plan, "notice_board", b, atan2(-b.x, 4.0 - b.z))
	_label(plan, b + Vector3(0, 3.5, 0), "Guilda (quadro)")
	_disc(plan, VillageLayout.PORTAL, 1.4, Color(0.6, 0.3, 1.0))
	_label(plan, VillageLayout.PORTAL + Vector3(0, 2.5, 0), "Portal da Horda")


## Enfeites de Natal (ChristmasDecor), nos mesmos lugares do jogo.
func _christmas(plan: Node3D) -> void:
	var cd: GDScript = load("res://scripts/world/christmas_decor.gd")
	cd.tree(plan, VillageLayout.XMAS_TREE, 1.0, 1225)
	for p: Vector3 in VillageLayout.XMAS_SMALL:
		cd.tree(plan, p, 0.38, int(p.x * 10))
	var sp := VillageLayout.SNOWMAN
	cd.snowman(plan, sp, atan2(-sp.x, -sp.z))
	cd.sleigh(plan, VillageLayout.SLEIGH, VillageLayout.SLEIGH_YAW)
	for c in VillageLayout.candy_canes():
		cd.candy_cane(plan, c[0], c[1])
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	cd.gifts(plan, VillageLayout.WELL_GIFTS, 3, rng, 0.0, 0.4)
	var top := Vector3(0, 3.45, 0)
	var lamps: Array = VillageLayout.LAMPS_SQUARE
	for i in lamps.size():
		cd.light_string(plan, lamps[i] + top, lamps[(i + 1) % lamps.size()] + top, 0.6, cd.MULTI, i % 2)
	cd.light_string(plan, VillageLayout.NORTH_STRING[0] + top, VillageLayout.NORTH_STRING[1] + top, 0.5, cd.MULTI, 1)


## NPCs como bonecos com o nome, a carroça da guilda e os pontos da antiga praça.
func _people(plan: Node3D) -> void:
	var spots := VillageLayout.npc_spots()
	for id in spots:
		_npc(plan, spots[id][0], NPC_NAMES.get(id, id))
	_npc(plan, VillageLayout.SANTA, "Papai Noel")
	var coach: Vector3 = load("res://scripts/world/regions.gd").coach_point("vila")
	_npc(plan, coach, "Cocheiro")
	plan.add_child(load("res://scripts/world/region_builder.gd").wagon(coach + Vector3(-3.2, 0, -0.5), 0.0))
	var back: float = load("res://scripts/hub/hub_point.gd").BUILDING_BACK
	for pd in VillageLayout.POINTS:
		var pos: Vector3 = pd[1]
		if pd[0] == "building":   # o prédio da base fica atrás do ponto
			var at: Vector3 = pos - Vector3(sin(pd[2]), 0, cos(pd[2])) * back
			_box(plan, at, Vector3(5, 3, 5), POINT_COLOR)
			_label(plan, at + Vector3(0, 4, 0), "%s (base)" % str(pd[3]).capitalize())
		else:
			_npc(plan, pos, POINT_NAMES.get(pd[0], pd[0]))


func _model(parent: Node3D, model: String, pos: Vector3, yaw := 0.0, s := 1.0) -> Node3D:
	var n: Node3D = (load("res://assets/models/%s.glb" % model) as PackedScene).instantiate()
	n.position = pos
	n.rotation.y = yaw
	n.scale = Vector3.ONE * s
	parent.add_child(n)
	return n


func _npc(parent: Node3D, pos: Vector3, text: String) -> void:
	var mi := MeshInstance3D.new()
	var m := CapsuleMesh.new()
	m.radius = 0.3
	m.height = 1.7
	mi.mesh = m
	mi.position = pos + Vector3(0, 0.85, 0)
	mi.material_override = _mat(NPC_COLOR)
	parent.add_child(mi)
	_label(parent, pos + Vector3(0, 2.2, 0), text)


func _label(parent: Node3D, pos: Vector3, text: String) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.outline_size = 12
	l.pixel_size = 0.008
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = pos
	parent.add_child(l)


func _box(parent: Node3D, pos: Vector3, size: Vector3, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.position = pos + Vector3(0, size.y / 2.0, 0)
	mi.material_override = _mat(c)
	parent.add_child(mi)


func _disc(parent: Node3D, pos: Vector3, r: float, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = 0.03
	mi.mesh = m
	mi.position = pos + Vector3(0, 0.015, 0)
	mi.material_override = _mat(c)
	parent.add_child(mi)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m
