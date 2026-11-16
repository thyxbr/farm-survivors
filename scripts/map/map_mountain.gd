@tool
class_name MapMountain
extends Node3D
## Morro do relevo: centro (posição do nó), raio da base e altura do pico. O chão soma todos os morros e a
## serra da borda (MapRoot.border_height). No editor um anel marca a base; o relevo de verdade aparece no chão
## da prévia (MapRoot remonta ao mexer).

@export var radius := 20.0:
	set(v):
		radius = v
		_refresh()
@export var height := 10.0:
	set(v):
		height = v
		_refresh()


func _ready() -> void:
	if Engine.is_editor_hint():
		set_notify_transform(true)
	_refresh()


func _refresh() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		build_preview()
		MapRoot.ground_changed(self)


func build_preview(_height: Callable = Callable()) -> void:
	var p := MapPreview.fresh(self)
	var ring := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = maxf(radius - 0.3, 0.1)
	t.outer_radius = maxf(radius, 0.2)
	ring.mesh = t
	ring.position.y = 0.3
	ring.material_override = MapPreview.mat(Color(0.55, 0.45, 0.3, 0.6))
	p.add_child(ring)
	MapPreview.label(p, Vector3(0, height + 1.5, 0), "morro %.0f m" % height)


## No editor: mover o nó remonta o chão da prévia.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		MapRoot.ground_changed(self)
