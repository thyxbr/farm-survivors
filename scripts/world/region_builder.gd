class_name RegionBuilder
extends RefCounted
## Fábricas usadas pelos mapas (as cenas em scenes/maps, montadas pelo MapLoader): os NPCs da história (npc()),
## os pontos examináveis (point()) e a carroça da guilda (wagon()).

const STORY_POINT := preload("res://scripts/world/story_point.gd")
const RIVAL := preload("res://scripts/world/rival.gd")

## Visual de cada NPC novo: {"villager": roupa 1..3} ou {"knight": look do KnightLook}; "scale"; "idle".
const NPCS := {
	"lina": {"villager": 3, "scale": 0.95},
	"zelia": {"villager": 1, "scale": 0.88, "idle": 0.8},
	"tonico": {"villager": 2, "scale": 1.0},
	"coach": {"villager": 1, "scale": 1.05},
	"tico": {"villager": 3, "scale": 0.6},
	# feirantes e o artesão da praça
	"tereza": {"villager": 3, "scale": 0.93},
	"bento": {"villager": 2, "scale": 1.02},
	"cida": {"villager": 1, "scale": 0.92},
	"aurelio": {"villager": 2, "scale": 1.06, "idle": 0.85},
	# moradores que passeiam pela vila (VillageWalker; "speed" escala o passo)
	"marta": {"villager": 1, "scale": 0.95},
	"joca": {"villager": 3, "scale": 0.62, "speed": 1.35},
	"lauro": {"villager": 2, "scale": 0.97, "idle": 0.7, "speed": 0.7},
	"bia": {"villager": 3, "scale": 0.94, "speed": 1.1},
	"rufus": {"knight": {"weapon": "iron_sword", "armor": "guard_surcoat", "head": "kettle_hat", "hands": "iron_gauntlets",
		"feet": "iron_greaves", "offhand": "wooden_shield"}, "scale": 1.05},
	"osvaldo": {"knight": {"weapon": "knight_blade", "armor": "royal_plate", "head": "knight_helm", "hands": "iron_gauntlets",
		"feet": "iron_greaves", "offhand": "knight_shield"}, "scale": 0.97},
	"ravi": {"knight": {"weapon": "hunter_bow", "armor": "ranger_vest", "head": "ranger_hood", "hands": "archer_bracers",
		"feet": "leather_boots", "offhand": "hunter_quiver"}, "scale": 1.0},
	"sylvi": {"knight": {"weapon": "elven_bow", "armor": "ranger_vest", "head": "", "hands": "leather_gloves",
		"feet": "swift_boots"}, "scale": 0.95},
	"bolgar": {"knight": {"weapon": "", "armor": "leather_armor", "head": "iron_helm", "hands": "iron_gauntlets",
		"feet": "reinforced_boots"}, "scale": 0.78},
}


## Morador que passeia pela vila (VillageWalker) pelo caminho `path` ([[x, z, espera?], ...], no mundo).
static func walker(id: String, path: Array) -> Node3D:
	var d: Dictionary = NPCS.get(id, {"villager": 1})
	var v := VillageWalker.new()
	v.npc_id = id
	v.look_index = int(d.get("villager", 1))
	v.model_scale = float(d.get("scale", 1.0))
	v.idle_speed = float(d.get("idle", 1.0))
	v.speed_scale = float(d.get("speed", 1.0))
	v.path = path
	return v


## Cria um NPC da história (sem adicionar à árvore): Kael do pico, aldeões e os de armadura.
static func npc(id: String, pos: Vector3, yaw: float) -> Node3D:
	var n: Node3D
	if id == "kael_pico":
		n = RIVAL.new()
		n.npc_id = "kael_pico"
	else:
		var d: Dictionary = NPCS.get(id, {"villager": 1})
		if d.has("knight"):
			var k := KnightNPC.new()
			k.npc_id = id
			k.look = d.knight
			k.model_scale = float(d.get("scale", 1.0))
			n = k
		else:
			var v := VillagerNPC.new()
			v.npc_id = id
			v.look_index = int(d.villager)
			v.model_scale = float(d.get("scale", 1.0))
			v.idle_speed = float(d.get("idle", 1.0))
			n = v
	n.position = pos
	n.rotation.y = yaw
	return n


## Objeto examinável da história (bilhete, diário, gato, quadro).
static func point(id: String, pos: Vector3, yaw := 0.0) -> Node3D:
	var sp := STORY_POINT.new()
	sp.npc_id = id
	sp.position = pos
	sp.rotation.y = yaw
	return sp


## Carroça da guilda (montada com caixas e cilindros): caixa de madeira, quatro rodas, toldo e lanterna.
static func wagon(pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	var wood := _mat(Color(0.45, 0.3, 0.18))
	var dark := _mat(Color(0.25, 0.17, 0.1))
	var cloth := _mat(Color(0.86, 0.8, 0.64))
	var guild := _mat(Color(0.25, 0.4, 0.75))
	_box(root, Vector3(1.8, 0.7, 3.2), wood, Vector3(0, 0.95, 0))
	_box(root, Vector3(1.9, 0.12, 3.3), dark, Vector3(0, 0.6, 0))
	_box(root, Vector3(0.12, 0.12, 1.6), dark, Vector3(0, 0.6, 2.3))   # varal
	for x in [-1.0, 1.0]:
		for z in [-1.1, 1.1]:
			var w := MeshInstance3D.new()
			var c := CylinderMesh.new()
			c.top_radius = 0.48
			c.bottom_radius = 0.48
			c.height = 0.12
			w.mesh = c
			w.material_override = dark
			w.position = Vector3(x, 0.48, z)
			w.rotation.z = PI / 2
			root.add_child(w)
	# toldo em arco (três faixas) com a faixa azul da guilda
	for i in 5:
		var a := lerpf(-1.1, 1.1, i / 4.0)
		var seg := _box(root, Vector3(0.62, 0.06, 3.0), cloth if i != 2 else guild, Vector3(sin(a) * 0.9, 1.3 + cos(a) * 0.9, 0))
		seg.rotation.z = -a
	_box(root, Vector3(0.12, 0.12, 0.12), _mat(Color(1, 0.8, 0.4)), Vector3(0.95, 1.6, 1.6))
	if ToonLook.enabled():
		ToonLook.apply(root)
	var body := StaticBody3D.new()
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(2.0, 2.4, 3.4)
	cs.shape = b
	cs.position.y = 1.2
	body.add_child(cs)
	root.add_child(body)
	return root


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


static func _box(parent: Node3D, size: Vector3, m: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


# ================================================================ mapas
# ---------------------------------------------------------------- Bosque Sussurrante
# ---------------------------------------------------------------- Mina de Cristal
# ---------------------------------------------------------------- Pico das Cinzas