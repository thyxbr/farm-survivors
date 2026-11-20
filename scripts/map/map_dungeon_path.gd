@tool
class_name MapDungeonPath
extends Node3D
## Corredor de uma dungeon: segmentos retos entre os filhos Ponto0, Ponto1... (MapWaypoint; arraste no 3D, Ctrl+D
## acrescenta). Curvas secas (90°) escondem o que vem depois. `width` = largura, `height` = altura do teto.

@export var width := 3.5:
	set(v):
		width = v
		_changed()
@export var height := 4.6:
	set(v):
		height = v
		_changed()


func _ready() -> void:
	if Engine.is_editor_hint():
		set_notify_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		_changed()


func waypoints_changed() -> void:
	_changed()


func _changed() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		MapRoot.ground_changed(self)


## Pontos (x, z) no espaço do mapa.
func points(root: Node) -> PackedVector2Array:
	var out := PackedVector2Array()
	for c in get_children():
		if c is MapWaypoint:
			var o: Vector3 = MapData.local_xform(root, c).origin
			out.append(Vector2(o.x, o.z))
	return out


func build_preview(_height: Callable = Callable()) -> void:
	MapPreview.fresh(self)
	var i := 0
	for c in get_children():
		if c is MapWaypoint:
			(c as MapWaypoint).draw_marker(0.0, i)
			i += 1
