@tool
class_name MapLandmark
extends Node3D
## Lugar com nome no mapa, lido por outros sistemas (acampamento, ruínas, arena, Horta, ninho, pomar, onde o
## jogador nasce, portal, carruagem da guilda, chegada da viagem). O código procura pelo `id`
## (MapData.landmark), então mover o nó no editor move o lugar no jogo todo.

## Nome do lugar: camp, ruins, arena, farm, nest, orchard, village_spawn, portal, coach, arrive...
@export var id := ""
## Assenta no relevo (a altura do nó vira distância até o chão).
@export var follow_ground := true

var _height := Callable()


func _ready() -> void:
	if Engine.is_editor_hint():
		set_notify_transform(true)
	if Engine.is_editor_hint():
		build_preview(_height)


func build_preview(height: Callable = Callable()) -> void:
	_height = height
	var p := MapPreview.fresh(self)
	MapPreview.box(p, Vector3(0, 1.5, 0), Vector3(0.08, 3.0, 0.08), Color(0.9, 0.9, 0.9))
	MapPreview.box(p, Vector3(0.35, 2.75, 0), Vector3(0.7, 0.45, 0.04), Color(0.2, 0.7, 1.0))
	MapPreview.label(p, Vector3(0, 3.6, 0), "📍 " + id)
	MapPreview.seat(self, p, follow_ground, height)

## No editor: mover o nó reassenta a prévia no relevo.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		build_preview(_height)
