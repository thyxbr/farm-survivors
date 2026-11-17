class_name MapData
extends RefCounted
## Leitura pura das cenas de mapa (sem autoload, para os testes e para quem precisa sem o mundo montado):
## landmarks, nós de coleta e a lista de tipos de monstro. Cada cena é lida uma vez e guardada.

const SCENES := {
	"vila": "res://scenes/maps/vale.tscn",
	"bosque": "res://scenes/maps/bosque.tscn",
	"mina": "res://scenes/maps/mina.tscn",
	"pico": "res://scenes/maps/pico.tscn",
	"arena": "res://scenes/maps/arena.tscn",
}
## Centro dos mapas que não são regiões de viagem (Regions): a Arena da Horda, longe ao norte de Valdoria.
const EXTRA_ORIGINS := {"arena": Vector3(0, 0, -1000)}
const ENEMIES_JSON := "res://data/balance/enemies.json"

## Troca a cena de um mapa (map_id -> caminho); só para testes.
static var scene_override := {}
static var _landmarks := {}        # map_id -> {id: Vector3 local}
static var _areas := {}            # map_id -> [área] (ver areas())
static var _resource_nodes = null  # node_id -> {"kind", "pos"} (global)
static var _enemy_kinds := PackedStringArray()


static func clear_cache() -> void:
	_landmarks = {}
	_areas = {}
	_resource_nodes = null


static func scene_path(map_id: String) -> String:
	return str(scene_override.get(map_id, SCENES.get(map_id, "")))


## Centro do mapa no mundo (Regions para as regiões; EXTRA_ORIGINS para a Arena).
static func origin(map_id: String) -> Vector3:
	return EXTRA_ORIGINS.get(map_id, Regions.origin(map_id) if Regions.DATA.has(map_id) else Vector3.ZERO)


## Instancia a cena do mapa sem pôr na árvore (quem chama libera). null se não existe.
static func load_root(map_id: String) -> Node:
	var path := scene_path(map_id)
	if path == "" or not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	return ps.instantiate() if ps != null else null


## Transform do nó no espaço da raiz da cena (soma os pais; a raiz não conta).
static func local_xform(root: Node, n: Node3D) -> Transform3D:
	var xf := Transform3D()
	var p: Node = n
	while p != null and p != root:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


## Posição de uma peça no espaço do mapa como o jogo põe: com follow_ground (e sem estar dentro de outra
## peça), a altura salva é a distância até o chão do mapa (o mesmo relevo do MapLoader e da prévia).
static func settled(root: Node, n: Node3D, ground: Node3D) -> Vector3:
	var p := local_xform(root, n).origin
	if ground == null or not n.get("follow_ground"):
		return p
	var up := n.get_parent()
	while up != null and up != root:
		if up.has_method("build_preview"):
			return p   # vai junto com a peça de fora
		up = up.get_parent()
	p.y = MapPreview.ground_y(true, p.y, Callable(ground, "height_at"), p.x, p.z)
	return p


## Chão do mapa só para consultar a altura (sem malha nem colisão); null se o mapa não usa o chão de
## Valdoria. Quem chama libera.
static func ground_of(root: Node) -> Node3D:
	if root is MapRoot and (root as MapRoot).has_ground:
		return (root as MapRoot).make_ground()
	return null


## Lê da cena (uma vez por mapa) os landmarks e as regiões com nome.
static func _scan(map_id: String) -> void:
	if _landmarks.has(map_id):
		return
	var found := {}
	var areas: Array = []
	var root := load_root(map_id)
	if root != null:
		var g := ground_of(root)
		for n in root.find_children("*", "Node3D", true, false):
			if n is MapLandmark:
				found[n.id] = settled(root, n, g)
			elif n is MapRegion:
				var xf := local_xform(root, n)
				var c := xf.origin
				c.y = 0.0
				areas.append({"id": n.region_id, "map": map_id, "center": origin(map_id) + c, "shape": n.shape,
					"size": n.size, "radius": n.radius, "rot": xf.basis.get_euler().y})
		if g != null:
			g.free()
		root.free()
	_landmarks[map_id] = found
	_areas[map_id] = areas


## Posição global de um landmark (origem da região + posição na cena, assentada no relevo); zero se não existe.
static func landmark(map_id: String, id: String) -> Vector3:
	_scan(map_id)
	if not _landmarks[map_id].has(id):
		return Vector3.ZERO
	return origin(map_id) + _landmarks[map_id][id]


## Regiões com nome do mapa (nós MapRegion), em posição global: [{"id", "map", "center" (y = 0), "shape"
## (MapRegion.RECT/DISC), "size" (largura X × profundidade Z), "radius", "rot" (giro em Y, rad)}].
static func areas(map_id: String) -> Array:
	_scan(map_id)
	return _areas[map_id]


## As regiões de todos os mapas de viagem (Regions.ORDER).
static func all_areas() -> Array:
	var out: Array = []
	for id in Regions.ORDER:
		out.append_array(areas(id))
	return out


## Nós de coleta de todos os mapas: node_id -> {"kind": tipo do veio, "pos": posição global (no relevo)}.
static func resource_nodes() -> Dictionary:
	if _resource_nodes == null:
		var out := {}
		for map_id in SCENES:
			var root := load_root(map_id)
			if root == null:
				continue
			var g := ground_of(root)
			for n in root.find_children("*", "Node3D", true, false):
				if n is MapEntity and n.kind == "resource_node" and n.node_id >= 0:
					out[n.node_id] = {"kind": n.ref, "pos": origin(map_id) + settled(root, n, g)}
			if g != null:
				g.free()
			root.free()
		_resource_nodes = out
	return _resource_nodes


## Tipos de monstro do data/balance/enemies.json (para a lista do Inspector e a validação).
static func enemy_kinds() -> PackedStringArray:
	if _enemy_kinds.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(ENEMIES_JSON))
		if data is Dictionary:
			for k in data:
				_enemy_kinds.append(str(k))
	return _enemy_kinds
