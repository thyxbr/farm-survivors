class_name MapData
extends RefCounted
## Leitura pura das cenas de mapa (sem autoload, para os testes e para quem precisa sem o mundo montado):
## landmarks, nós de coleta e a lista de tipos de monstro. Cada cena é lida uma vez e guardada.

const SCENES := {
	"vila": "res://scenes/maps/vale.tscn",
	"bosque": "res://scenes/maps/bosque.tscn",
	"mina": "res://scenes/maps/mina.tscn",
	"pico": "res://scenes/maps/pico.tscn",
}
const ENEMIES_JSON := "res://data/balance/enemies.json"

## Troca a cena de um mapa (map_id -> caminho); só para testes.
static var scene_override := {}
static var _landmarks := {}        # map_id -> {id: Vector3 local}
static var _resource_nodes = null  # node_id -> {"kind", "pos"} (global)
static var _enemy_kinds := PackedStringArray()


static func clear_cache() -> void:
	_landmarks = {}
	_resource_nodes = null


static func scene_path(map_id: String) -> String:
	return str(scene_override.get(map_id, SCENES.get(map_id, "")))


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


## Posição global de um landmark (origem da região + posição na cena); zero se não existe.
static func landmark(map_id: String, id: String) -> Vector3:
	if not _landmarks.has(map_id):
		var found := {}
		var root := load_root(map_id)
		if root != null:
			for n in root.find_children("*", "Node3D", true, false):
				if n is MapLandmark:
					found[n.id] = local_xform(root, n).origin
			root.free()
		_landmarks[map_id] = found
	if not _landmarks[map_id].has(id):
		return Vector3.ZERO
	return Regions.origin(map_id) + _landmarks[map_id][id]


## Nós de coleta de todos os mapas: node_id -> {"kind": tipo do veio, "pos": posição global no chão (y = 0)}.
static func resource_nodes() -> Dictionary:
	if _resource_nodes == null:
		var out := {}
		for map_id in SCENES:
			var root := load_root(map_id)
			if root == null:
				continue
			for n in root.find_children("*", "Node3D", true, false):
				if n is MapEntity and n.kind == "resource_node" and n.node_id >= 0:
					var p: Vector3 = Regions.origin(map_id) + local_xform(root, n).origin
					out[n.node_id] = {"kind": n.ref, "pos": Vector3(p.x, 0.0, p.z)}
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
