class_name MapValidation
extends RefCounted
## Confere uma cena de mapa contra o que o jogo aceita (sem autoload; usado pelo teste
## tests/unit/test_map_validation.gd, rode depois de editar um mapa). Cada problema vem com o caminho do nó.

const MAX_PAINTS := 40
const MARGIN := 30.0   # além da meia largura (a serra e a floresta da borda ficam um pouco para fora)
const WORLD_NODES := "res://data/balance/world_nodes.json"
## Landmarks que cada mapa precisa ter uma vez.
const REQUIRED := {"vila": ["camp", "ruins", "farm", "nest", "orchard", "village_spawn", "portal", "horde_return",
	"pond", "coach", "arrive"], "arena": []}
const REQUIRED_REGION := ["coach", "arrive"]
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
	var paints := root.pieces(MapGroundPaint).size()
	if paints > MAX_PAINTS:
		out.append("%d formas pintadas no chão (o máximo é %d; as de sobra não aparecem)" % [paints, MAX_PAINTS])
	var marks := {}
	for m: MapLandmark in root.pieces(MapLandmark):
		marks[m.id] = int(marks.get(m.id, 0)) + 1
	for id in REQUIRED.get(root.map_id, REQUIRED_REGION):
		if int(marks.get(id, 0)) != 1:
			out.append("landmark '%s' aparece %d vez(es); precisa de exatamente 1" % [id, int(marks.get(id, 0))])
	var veins: Dictionary = _vein_kinds()
	var seen := {}
	for e: MapEntity in root.pieces(MapEntity):
		var at := str(root.get_path_to(e))
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
		for k in INDEXED:
			var got: Array = seen.get(k, [])
			got.sort()
			if got != range(INDEXED[k]):
				out.append("%s: os índices precisam ser 0..%d, um de cada (veio %s)" % [k, INDEXED[k] - 1, str(got)])
	var lim := root.half + MARGIN
	for n in root.all_pieces():
		var p := root.local_xform(n).origin
		if absf(p.x) > lim or absf(p.z) > lim:
			out.append("%s: fora do mapa (%.0f, %.0f; limite %.0f)" % [str(root.get_path_to(n)), p.x, p.z, lim])
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
