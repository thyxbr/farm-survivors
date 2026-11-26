class_name MapValidation
extends RefCounted
## Confere uma cena de mapa contra o que o jogo aceita (sem autoload; usado pelo teste
## tests/unit/test_map_validation.gd, rode depois de editar um mapa). Cada problema vem com o caminho do nó.

const MAX_PAINTS := 64
const MARGIN := 30.0   # além da meia largura (a serra e a floresta da borda ficam um pouco para fora)
const WORLD_NODES := "res://data/balance/world_nodes.json"
const REGIONS := "res://data/balance/regions.json"
## Landmarks que cada mapa precisa ter uma vez.
const REQUIRED := {"vila": ["camp", "ruins", "farm", "nest", "orchard", "village_spawn", "portal", "horde_return",
	"pond", "coach", "arrive"], "arena": [], "exp_pantano": ["arrive", "exit"]}
const REQUIRED_REGION := ["coach", "arrive"]
## NPCs que o vale precisa ter uma vez (MapEntity com esse kind): a Mira e a Pip.
const UNIQUE_NPCS := ["merchant", "alchemist"]
## Índices que o vale precisa ter completos: tipo -> quantidade (canteiros da Horta, presentes do Natal).
const INDEXED := {"farm_plot": 12, "xmas_gift": 8}


static func check(root: MapRoot) -> PackedStringArray:
	var out := PackedStringArray()
	var kinds := MapData.enemy_kinds()
	for s: EnemySpawn in root.pieces(EnemySpawn):
		var at := str(root.get_path_to(s))
		if not s.kind in kinds:
			out.append("%s: monstro '%s' não existe no enemies.json" % [at, s.kind])
		if s.count < 0 or s.radius < 0.0:
			out.append("%s: quantidade e raio não podem ser negativos" % at)
		if s.respawn <= 0.0:
			out.append("%s: respawn precisa ser maior que 0 (veio %.1f)" % [at, s.respawn])
		# o vale: nenhum bando nasce colado na vila (a guarda abateria tudo e ninguém ganharia nada)
		var gap := VillageWard.distance(s.position) - s.radius
		if root.map_id == "vila" and not s.boss and gap < VillageWard.SPAWN_CLEARANCE:
			out.append("%s: nasce a %.1f m da zona da guarda da vila (mínimo %.0f m)" % [at, gap, VillageWard.SPAWN_CLEARANCE])
	var regions = JSON.parse_string(FileAccess.get_file_as_string(REGIONS))
	for r: MapRegion in root.pieces(MapRegion):
		var at := str(root.get_path_to(r))
		if not (regions is Dictionary and regions.has(r.region_id)):
			out.append("%s: região '%s' não existe no regions.json" % [at, r.region_id])
		if (r.shape == MapRegion.DISC and r.radius <= 0.0) or (r.shape == MapRegion.RECT and (r.size.x <= 0.0 or r.size.y <= 0.0)):
			out.append("%s: tamanho da região precisa ser maior que 0" % at)
	if Regions.DATA.has(root.map_id) and not is_equal_approx(root.half, float(Regions.DATA[root.map_id].half)):
		out.append("half %.0f diferente do Regions.DATA (%.0f): o minimapa e a detecção de região usam o do Regions"
			% [root.half, float(Regions.DATA[root.map_id].half)])
	var paints := root.pieces(MapGroundPaint).size()
	if paints > MAX_PAINTS:
		out.append("%d formas pintadas no chão (o máximo é %d; as de sobra não aparecem)" % [paints, MAX_PAINTS])
	var marks := {}
	for m: MapLandmark in root.pieces(MapLandmark):
		marks[m.id] = int(marks.get(m.id, 0)) + 1
	var required: Array = REQUIRED.get(root.map_id, REQUIRED_REGION)
	if Regions.is_dungeon(root.map_id):
		required = ["arrive"]   # a saída é a porta "out" (abaixo); dungeon não tem carruagem
	else:
		for d in Regions.dungeons_of(root.map_id):
			required = required + ["dg:" + d]   # onde fica a porta de cada dungeon deste mapa
	for id in required:
		if int(marks.get(id, 0)) != 1:
			out.append("landmark '%s' aparece %d vez(es); precisa de exatamente 1" % [id, int(marks.get(id, 0))])
	var doors := {}
	for e: MapEntity in root.pieces(MapEntity):
		if e.kind == "dungeon_door":
			doors[e.ref] = int(doors.get(e.ref, 0)) + 1
			if e.ref != "out" and not Regions.is_dungeon(e.ref):
				out.append("%s: porta para '%s', que não é dungeon do Regions.DATA" % [root.get_path_to(e), e.ref])
	if Regions.is_dungeon(root.map_id) and int(doors.get("out", 0)) != 1:
		out.append("dungeon precisa de exatamente 1 porta de saída (dungeon_door ref \"out\")")
	for d in Regions.dungeons_of(root.map_id):
		if int(doors.get(d, 0)) != 1:
			out.append("precisa de exatamente 1 porta para a dungeon '%s' (dungeon_door ref \"%s\")" % [d, d])
	var veins: Dictionary = _vein_kinds()
	var seen := {}
	var npcs := {}
	for e: MapEntity in root.pieces(MapEntity):
		var at := str(root.get_path_to(e))
		npcs[e.kind] = int(npcs.get(e.kind, 0)) + 1
		if e.kind == "walker" and e.walk_path().size() < 2:
			out.append("%s: morador que passeia precisa de 2 pontos de caminho ou mais (filhos MapWaypoint)" % at)
		if e.kind == "resource_node":
			if e.node_id < 0:
				out.append("%s: nó de coleta sem node_id" % at)
			if not veins.has(e.ref):
				out.append("%s: veio de tipo '%s' não existe no world_nodes.json" % [at, e.ref])
		if INDEXED.has(e.kind):
			if not seen.has(e.kind):
				seen[e.kind] = []
			seen[e.kind].append(e.index)
	if root.map_id == "vila":
		for k in UNIQUE_NPCS:
			if int(npcs.get(k, 0)) != 1:
				out.append("NPC '%s' aparece %d vez(es); precisa de exatamente 1" % [k, int(npcs.get(k, 0))])
		for k in INDEXED:
			var got: Array = seen.get(k, [])
			got.sort()
			if got != range(INDEXED[k]):
				out.append("%s: os índices precisam ser 0..%d, um de cada (veio %s)" % [k, INDEXED[k] - 1, str(got)])
	out.append_array(_river_problems(root))
	var lim := root.half + MARGIN
	for n in root.all_pieces():
		var p := root.local_xform(n).origin
		if absf(p.x) > lim or absf(p.z) > lim:
			out.append("%s: fora do mapa (%.0f, %.0f; limite %.0f)" % [str(root.get_path_to(n)), p.x, p.z, lim])
	return out


## Rios: precisam de 2 pontos ou mais, e nada do jogo pode ficar dentro do leito (fica do outro lado da parede ou
## debaixo d'água). Só a ponte pode.
static func _river_problems(root: MapRoot) -> PackedStringArray:
	var out := PackedStringArray()
	var rivers := root.pieces(MapRiver)
	for r: MapRiver in rivers:
		if r.control_points().size() < 2:
			out.append("%s: rio precisa de 2 pontos de caminho ou mais (filhos MapWaypoint)" % root.get_path_to(r))
	if rivers.is_empty():
		return out
	for n in root.all_pieces():
		if n is MapRiver or n is MapGroundPaint or n is MapRegion or n is MapGrassArea or n is MapMountain:
			continue
		if n is MapProp and MapRiver.BRIDGE_HALF.has((n as MapProp).model):
			continue
		var p := root.local_xform(n).origin
		var reach := 0.0
		if n is MapProp:
			reach = (n as MapProp).footprint()
		elif n is EnemySpawn:
			reach = (n as EnemySpawn).radius
		for r: MapRiver in rivers:
			var d := MapRiver.distance_to(r.samples(), Vector2(p.x, p.z))
			if d - reach < r.half_total():
				out.append("%s: dentro do rio %s (a %.1f m do meio; o leito vai até %.1f m)"
					% [root.get_path_to(n), r.name, d, r.half_total()])
	return out


## Problemas entre mapas: o mesmo node_id em dois nós de coleta (em qualquer mapa).
static func check_all(roots: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var where := {}
	for r: MapRoot in roots:
		for e: MapEntity in r.pieces(MapEntity):
			if e.kind != "resource_node" or e.node_id < 0:
				continue
			var at := "%s/%s" % [r.map_id, r.get_path_to(e)]
			if where.has(e.node_id):
				out.append("node_id %d em %s e em %s" % [e.node_id, where[e.node_id], at])
			else:
				where[e.node_id] = at
	return out


static func _vein_kinds() -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(WORLD_NODES))
	return data.get("kinds", {}) if data is Dictionary else {}
