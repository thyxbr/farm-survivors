extends Node
## Conversão (uma vez) do mundo montado por código para as cenas de mapa (scenes/maps/<mapa>.tscn). Monta o
## mundo antigo com a gravação do ChristmasDecor ligada e escreve cada mapa com as peças das cenas: modelos
## (MapProp) com a colisão que o prop() criou, luzes (MapLight), textos e enfeites (MapDecor), NPCs e pontos de
## jogo (MapEntity), pontos de monstro (EnemySpawn), colisões soltas, formas e morros do chão, áreas do capim,
## landmarks e as construções da vila (VillageBuilding). Sorteios ficam congelados como estão.
##   godot --headless --path . res://scenes/world.tscn -- --bakemaps=vila,bosque,mina,pico --solo-save=user://bake_solo.json
## Depois de usada (e conferida pelo retrato --mapsummary), esta ferramenta sai do projeto.

const OUT := "res://scenes/maps/%s.tscn"
const FILES := {"vila": "vale", "bosque": "bosque", "mina": "mina", "pico": "pico"}
const ENTITY_SCRIPTS := ["elder", "rival", "villager_npc", "knight_npc", "story_point", "hub_point", "farm_plot",
	"kitchen", "challenge_portal", "santa", "christmas_event_point", "world_resource_node"]
## Destinos do poste de direção (constantes antigas -> landmark).
const SIGN_DESTS := [["Horta", "farm"], ["Ruínas", "ruins"], ["Goblins", "camp"], ["Horda", "arena"]]

var w: Node3D
var roots := {}        # map_id -> MapRoot
var heights := {}      # map_id -> Callable(x, z) local
var groups := {}       # "map/caminho" -> Node3D
var names := {}        # Node -> {nome: contagem}
var by_parent := {}    # nó pai -> [records]
var prop_feet: Array = []   # [Vector2, raio] pegadas que o MapLoader recria (para separar do resto do _no_grass)


func _ready() -> void:
	var maps := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bakemaps="):
			maps = a.substr(11).split(",")
	for i in 900:
		await get_tree().process_frame
		w = get_tree().current_scene
		if w != null and w.get("built") == true:
			break
	if w == null or w.get("built") != true:
		printerr("BAKE mundo não montou")
		get_tree().quit(1)
		return
	await get_tree().process_frame
	_bake()
	for id in maps:
		_save(id)
	get_tree().quit(0)


# ---------------------------------------------------------------- montagem

func _bake() -> void:
	for id in Regions.ORDER:
		var r := MapRoot.new()
		r.name = FILES[id].capitalize()
		r.map_id = id
		r.half = Regions.DATA[id].half
		roots[id] = r
	_ground("vila", w.ground)
	for id in w.region_grounds:
		_ground(id, w.region_grounds[id])
	_grass_params()
	for rec in ChristmasDecor.records:
		var p = rec.parent
		if p == null or p == w:
			continue
		if not by_parent.has(p):
			by_parent[p] = []
		by_parent[p].append(rec)
	var kids := w.get_children()
	var i := 0
	while i < kids.size():
		var n: Node = kids[i]
		i += 1
		if n.has_meta("from_building") or n is MultiMeshInstance3D or n is CanvasLayer or n is Camera3D \
				or n is WorldEnvironment or n is DirectionalLight3D or n is AudioStreamPlayer3D:
			continue
		if not n is Node3D:
			continue
		var model := _model(n)
		var sname := _script(n)
		if model == "signpost":
			_signpost(n)
			if i < kids.size() and kids[i] is StaticBody3D:
				_body(kids[i])   # a colisão do poste (cilindro) fica como colisão solta
				i += 1
		elif model != "":
			var body: StaticBody3D = null
			if i < kids.size() and kids[i] is StaticBody3D and (kids[i] as Node3D).position.is_equal_approx(n.position):
				body = kids[i]
				i += 1
			_prop(n, model, body)
		elif sname in ENTITY_SCRIPTS:
			_entity(n, sname)
		elif sname != "":
			continue   # chão, jogador, interface, clima
		elif n is StaticBody3D:
			_body(n)
		elif n is OmniLight3D:
			_add(_map(n.global_position), "Luzes", _light(n, Transform3D()), n.global_transform, false)
		elif n is Label3D:
			_add(_map(n.global_position), "Enfeites", _label(n), n.global_transform, false)
	for rec in ChristmasDecor.records:
		if rec.parent == null or rec.parent == w:
			var xf: Transform3D = rec.xform
			_add(_map(xf.origin), "Enfeites", _decor(rec), xf, true)
	_spawns()
	_landmarks()
	_grass_areas()
	_buildings()


func _model(n: Node) -> String:
	return n.scene_file_path.get_file().get_basename() if n.scene_file_path.begins_with("res://assets/models/") else ""


func _script(n: Node) -> String:
	var s: Script = n.get_script()
	return s.resource_path.get_file().get_basename() if s != null else ""


func _map(p: Vector3) -> String:
	return Regions.region_at(p)


## Área do vale (para agrupar os nós no editor); nas regiões tudo fica na raiz por categoria.
func _area(id: String, p: Vector3) -> String:
	if id != "vila":
		return ""
	var x := p.x
	var z := p.z
	if VillageLayout.BOUNDS.has_point(Vector2(x, z)):
		return "Vila"
	if absf(x) <= 12.0 and absf(z - 33.0) <= 9.0:
		return "Horta"
	if absf(x - 20.0) <= 9.0 and absf(z - 33.0) <= 9.0:
		return "Pomar"
	if p.distance_to(w.CAMP) < 20.0:
		return "Acampamento Goblin"
	if p.distance_to(w.RUINS) < 34.0:
		return "Ruínas"
	if p.distance_to(w.ARENA) < 42.0:
		return "Arena"
	if p.distance_to(w.NEST) < 14.0:
		return "Ninho de Slimes"
	if absf(x) <= 26.0 and z >= -52.0 and z <= -18.0:
		return "Campos"
	return "Natureza"


func _group(id: String, path: String) -> Node3D:
	var key := id + "/" + path
	if groups.has(key):
		return groups[key]
	var parent: Node3D = roots[id]
	var acc := ""
	for part in path.split("/", false):
		acc += "/" + part
		var k := id + acc
		if not groups.has(k):
			var g := Node3D.new()
			g.name = part
			parent.add_child(g)
			groups[k] = g
		parent = groups[k]
	return parent


func _unique(parent: Node, base: String) -> String:
	if not names.has(parent):
		names[parent] = {}
	var c: int = names[parent].get(base, 0) + 1
	names[parent][base] = c
	return base if c == 1 else "%s %d" % [base, c]


## Põe a peça no mapa certo, no grupo da área/categoria, com o transform local ao mapa. `follow`: a altura
## vira distância até o chão.
func _add(id: String, category: String, piece: Node3D, global: Transform3D, follow: bool) -> void:
	var o: Vector3 = Regions.origin(id)
	var area := _area(id, global.origin)
	var parent := _group(id, (area + "/" + category) if area != "" else category)
	var xf := global
	xf.origin -= o
	if follow:
		xf.origin.y -= _h(id, xf.origin)
	piece.transform = xf
	piece.set("follow_ground", follow)
	piece.name = _unique(parent, piece.name if piece.name != "" else category)
	parent.add_child(piece)


func _h(id: String, local: Vector3) -> float:
	return MapPreview.ground_y(true, 0.0, heights.get(id, Callable()), local.x, local.z)


# ---------------------------------------------------------------- peças

func _prop(n: Node3D, model: String, body: StaticBody3D) -> void:
	var id := _map(n.global_position)
	var p := MapProp.new()
	p.name = model
	p.model = model
	p.no_grass = model != "fence"
	if body != null:
		var cs := body.get_child(0) as CollisionShape3D
		var s := n.scale.x
		if cs.shape is BoxShape3D:
			p.shape = 1
			p.shape_size = (cs.shape as BoxShape3D).size / s
		else:
			p.shape = 2
			p.shape_size = Vector3((cs.shape as CylinderShape3D).radius / s, (cs.shape as CylinderShape3D).height / s, 0)
		prop_feet.append([Vector2(n.global_position.x, n.global_position.z), p.footprint_for(n.scale.x) + 0.15])
	var cat := "Árvores" if model.begins_with("tree_") else ("Pedras" if model == "rock" else "Objetos")
	_add(id, cat, p, n.global_transform, true)
	_nested(n, p)


## O que o código pendurou num modelo (luzes, textos, enfeites) vira filho da peça, no espaço do modelo.
func _nested(n: Node3D, piece: Node3D) -> void:
	var inv := n.global_transform.affine_inverse()
	for c in n.get_children():
		if c.owner == n:
			continue   # peça do próprio GLB
		if c is OmniLight3D:
			var l := _light(c, Transform3D())
			l.transform = inv * (c as Node3D).global_transform
			piece.add_child(l)
		elif c is Label3D:
			var d := _label(c)
			d.transform = inv * (c as Node3D).global_transform
			piece.add_child(d)
	for rec in by_parent.get(n, []):
		var d := _decor(rec)
		d.transform = rec.xform
		d.follow_ground = false
		piece.add_child(d)


func _light(src: OmniLight3D, _xf: Transform3D) -> MapLight:
	var l := MapLight.new()
	l.name = "Luz"
	l.light_color = src.light_color
	l.omni_range = src.omni_range
	l.omni_attenuation = src.omni_attenuation
	l.shadow_enabled = false
	l.light_specular = src.light_specular
	var flick := -1.0
	for f in w.flicker_lights:
		if f[0] == src:
			flick = f[1]
	if flick >= 0.0:
		l.mode = 2
		l.light_energy = flick
	elif src.has_meta("night_energy"):
		l.mode = 1
		l.night_energy = src.get_meta("night_energy")
		l.light_energy = l.night_energy
	else:
		l.light_energy = src.light_energy
	return l


func _label(src: Label3D) -> MapDecor:
	var d := MapDecor.new()
	d.name = "Placa"
	d.kind = "label"
	d.params = {"text": src.text, "font_size": src.font_size, "pixel_size": src.pixel_size,
		"outline_size": src.outline_size, "color": src.modulate, "billboard": src.billboard != BaseMaterial3D.BILLBOARD_DISABLED,
		"width": src.width if src.autowrap_mode != TextServer.AUTOWRAP_OFF else 0.0, "double_sided": src.double_sided}
	return d


func _decor(rec: Dictionary) -> MapDecor:
	var d := MapDecor.new()
	d.kind = rec.kind
	d.name = {"xmas_tree": "Árvore de Natal", "snowman": "Boneco de neve", "sleigh": "Trenó", "candy_cane": "Bengala",
		"gifts": "Presentes", "light_string": "Varal de luzes", "lamp_garland": "Festão", "wreath": "Guirlanda",
		"wagon": "Carroça", "scarecrow": "Espantalho", "crops": "Plantação"}.get(rec.kind, rec.kind)
	d.params = rec.params
	return d


func _entity(n: Node3D, sname: String) -> void:
	var e := MapEntity.new()
	var cat := "NPCs e pontos"
	match sname:
		"elder":
			e.kind = "elder"
		"rival":
			if str(n.get("npc_id")) == "kael_pico":
				e.kind = "npc"
				e.ref = "kael_pico"
			else:
				e.kind = "rival"
		"villager_npc", "knight_npc":
			e.kind = "npc"
			var nid := str(n.get("npc_id"))
			if nid.begins_with("coach_"):
				e.ref = "coach"
				e.params = {"npc_id": nid}
			else:
				e.ref = nid
		"story_point":
			e.kind = "story_point"
			e.ref = str(n.get("npc_id"))
		"hub_point":
			e.kind = "hub_point"
			e.ref = str(n.get("kind"))
			e.params = {"building_id": str(n.get("building_id"))}
		"farm_plot":
			e.kind = "farm_plot"
			e.index = int(n.get("index"))
		"kitchen":
			e.kind = "kitchen"
		"challenge_portal":
			e.kind = "portal"
		"santa":
			e.kind = "santa"
		"christmas_event_point":
			if str(n.get("kind")) != "gift":
				return   # portas: vêm das casas marcadas com delivery
			e.kind = "xmas_gift"
			e.index = int(n.get("index"))
		"world_resource_node":
			e.kind = "resource_node"
			e.node_id = int(n.get("node_id"))
			e.ref = str(WorldHarvest.node_def(Balance.tables, e.node_id).get("kind", ""))
			cat = "Coleta"
	e.name = e.ref if e.ref != "" else e.kind
	_add(_map(n.global_position), cat, e, n.global_transform, true)


func _signpost(n: Node3D) -> void:
	var e := MapEntity.new()
	e.name = "Poste de direção"
	e.kind = "signpost"
	e.params = {"dests": SIGN_DESTS}
	_add(_map(n.global_position), "NPCs e pontos", e, n.global_transform, true)


func _body(src: StaticBody3D) -> void:
	var b := StaticBody3D.new()
	b.name = "Colisão"
	b.collision_mask = src.collision_mask
	b.collision_layer = src.collision_layer
	for c in src.get_children():
		if c is CollisionShape3D:
			var cs := CollisionShape3D.new()
			cs.shape = (c as CollisionShape3D).shape.duplicate()
			cs.transform = (c as Node3D).transform
			b.add_child(cs)
	var id := _map(src.global_position)
	var parent := _group(id, "Colisões")
	var xf := src.global_transform
	xf.origin -= Regions.origin(id)
	b.transform = xf
	b.name = _unique(parent, "Colisão")
	parent.add_child(b)


# ---------------------------------------------------------------- chão, capim, monstros, lugares, vila

func _ground(id: String, g: Node3D) -> void:
	var r: MapRoot = roots[id]
	r.border_height = g.get("_ring_height")
	r.half = g.get("half")
	heights[id] = Callable(g, "height_at")
	var shapes: PackedVector4Array = g.get("_shapes")
	var cols: PackedVector4Array = g.get("_cols")
	var mix: PackedFloat32Array = g.get("_mix")
	var parent := _group(id, "Chão")
	for i in shapes.size():
		var s := shapes[i]
		var c := cols[i]
		var p := MapGroundPaint.new()
		p.disc = s.w < 0.0
		if p.disc:
			p.radius = s.z
		else:
			p.size = Vector2(s.z * 2.0, s.w * 2.0)
		p.color = Color(c.x, c.y, c.z).linear_to_srgb()
		p.soft = c.w
		p.grass = mix[i]
		p.position = Vector3(s.x, 0, s.y)
		p.name = _unique(parent, "Disco" if p.disc else "Área")
		parent.add_child(p)
	for pk: Vector4 in g.get("_peaks"):
		var m := MapMountain.new()
		m.position = Vector3(pk.x, 0, pk.y)
		m.radius = pk.z
		m.height = pk.w
		m.name = _unique(parent, "Morro")
		parent.add_child(m)


func _grass_params() -> void:
	var seed0: int = w.rng.seed
	var r: MapRoot = roots.vila
	r.grass_density = 0.6
	r.grass_plants = 1.0
	r.grass_seed = seed0 + 7
	var i := 0
	for id in w.region_grounds:
		var rr: MapRoot = roots[id]
		rr.grass_density = 0.45 if id == "bosque" else 0.18
		rr.grass_plants = 0.6
		rr.grass_seed = seed0 + 31 + i
		i += 1


## Áreas do capim: o _no_grass do mundo menos o que as casas e os MapProp recriam; no vale também a arena,
## as ruas e o Largo (keep_out) e as manchas de capim ralo.
func _grass_areas() -> void:
	var bg: Array = w.building_grass
	for k in range(w._no_grass.size()):
		if k >= bg[0] and k < bg[1]:
			continue
		var e: Array = w._no_grass[k]
		var dup := false
		for f in prop_feet:
			if (f[0] as Vector2).is_equal_approx(e[0]) and is_equal_approx(f[1], e[1]):
				dup = true
				prop_feet.erase(f)
				break
		if not dup:
			_grass_area(Vector3(e[0].x, 0, e[0].y), e[1], false)
	_grass_area(w.ARENA, 33.0, false)
	for c in VillageLayout.street_circles():
		_grass_area(Vector3(c[0].x, 0, c[0].y), c[1], false)
	_grass_area(VillageLayout.LARGO, 4.8, false)
	for s in [[Vector2(0, 4), 22.0], [Vector2(w.FARM.x, w.FARM.z), 12.0], [Vector2(-24, 4), 15.0], [Vector2(26, 4), 15.0]]:
		_grass_area(Vector3(s[0].x, 0, s[0].y), s[1], true)


func _grass_area(p: Vector3, r: float, sparse: bool) -> void:
	var a := MapGrassArea.new()
	a.name = "Capim ralo" if sparse else "Sem capim"
	a.radius = r
	a.sparse = sparse
	var id := _map(p)
	var parent := _group(id, "Capim")
	a.position = p - Regions.origin(id)
	a.name = _unique(parent, a.name)
	parent.add_child(a)


func _spawns() -> void:
	for s in w.spawns:
		var e := EnemySpawn.new()
		e.name = s.kind
		e.kind = s.kind
		e.count = 1
		e.radius = 0.0
		e.respawn = s.respawn
		_add(_map(s.pos), "Monstros", e, Transform3D(Basis(), s.pos), true)


func _landmarks() -> void:
	var vale := {"camp": w.CAMP, "ruins": w.RUINS, "arena": w.ARENA, "farm": w.FARM, "nest": w.NEST,
		"orchard": w.ORCHARD, "village_spawn": w.VILLAGE_SPAWN, "portal": w.PORTAL_POS}
	for id in Regions.ORDER:
		var pts := {"coach": Regions.coach_point(id), "arrive": Regions.arrive_point(id)}
		if id == "vila":
			pts.merge(vale)
		var parent := _group(id, "Lugares")
		for k in pts:
			var m := MapLandmark.new()
			m.id = k
			m.name = k
			m.follow_ground = false
			m.position = pts[k] - Regions.origin(id)
			parent.add_child(m)


func _buildings() -> void:
	var src := (load("res://scenes/village.tscn") as PackedScene).instantiate()
	var parent := _group("vila", "Vila/Construções")
	for g in src.get_children():
		var copy := g.duplicate()
		parent.add_child(copy)
	src.free()


func _own(n: Node, root: Node) -> void:
	for c in n.get_children():
		c.owner = root
		_own(c, root)


func _save(id: String) -> void:
	var r: MapRoot = roots[id]
	_own(r, r)
	var ps := PackedScene.new()
	var err := ps.pack(r)
	var path := OUT % FILES[id]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes/maps"))
	var e2 := ResourceSaver.save(ps, path)
	print("BAKE %s -> %s (pack %d, save %d, %d nós)" % [id, path, err, e2, r.find_children("*", "", true, false).size()])
