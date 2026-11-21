@tool
class_name MapWaypoint
extends Node3D
## Ponto do caminho de um morador que passeia: filho de uma MapEntity `walker`. Arraste no 3D para mudar o
## caminho; a ordem dos filhos na árvore é a ordem do caminho (o morador vai do primeiro ao último e volta).
## Duplique um ponto (Ctrl+D) para acrescentar outro. Só x e z contam: o morador anda no chão.

## Segundos parado quando chega neste ponto (0 = passa direto).
@export var wait := 0.0:
	set(v):
		wait = v
		_changed()


func _ready() -> void:
	if Engine.is_editor_hint():
		set_notify_transform(true)
		_changed()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		_changed()


## Ponto do caminho no formato do VillageWalker: [x, z] ou [x, z, segundos parado], no mundo.
func path_point() -> Array:
	var g := global_position if is_inside_tree() else position
	return [g.x, g.z, wait] if wait > 0.0 else [g.x, g.z]


## Marca no chão (para clicar e arrastar o ponto no 3D). `y` = altura do chão relativa ao ponto.
func draw_marker(y: float, number: int) -> void:
	var p := MapPreview.fresh(self)
	MapPreview.disc(p, 0.45, Color(0.3, 0.9, 1.0, 0.75), y + 0.06)
	var text := "%d" % number
	if wait > 0.0:
		text += " · %ss" % str(wait)
	MapPreview.label(p, Vector3(0, y + 0.8, 0), text, 32)


func _changed() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var w := get_parent()
	if w != null and w.has_method("waypoints_changed"):
		w.waypoints_changed()
