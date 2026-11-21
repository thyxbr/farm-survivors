@tool
class_name MapDungeonRoom
extends Node3D
## Sala de uma dungeon (filha de qualquer nó da cena; o MapDungeon junta todas). Retângulo `size` (x, z) em volta do
## nó, ou elipse com `round`. `height` = altura do teto. `boss` marca a sala do chefe: ela fica escura até o
## jogador chegar no portão, que é montado sozinho onde um corredor entra nela.

@export var size := Vector2(12, 10):
	set(v):
		size = v
		_changed()
@export var height := 6.0:
	set(v):
		height = v
		_changed()
@export var round := false:
	set(v):
		round = v
		_changed()
@export var boss := false:
	set(v):
		boss = v
		_changed()
## Salão de pedra lavrada (o da frente do portão do chefe): paredes retas de cantaria e chão de lajes, sem a
## rocha irregular nem os enfeites de caverna.
@export var hall := false:
	set(v):
		hall = v
		_changed()
## Pilares de pedra dentro da sala (salas grandes).
@export var pillars := false:
	set(v):
		pillars = v
		_changed()


func _ready() -> void:
	if Engine.is_editor_hint():
		set_notify_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		_changed()


func _changed() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		MapRoot.ground_changed(self)


## Se o ponto (x, z do mapa; `c` = centro da sala no mapa) fica dentro da sala.
func contains(c: Vector2, p: Vector2) -> bool:
	var d := p - c
	if round:
		var rx := size.x / 2.0
		var rz := size.y / 2.0
		return (d.x * d.x) / (rx * rx) + (d.y * d.y) / (rz * rz) <= 1.0
	return absf(d.x) <= size.x / 2.0 and absf(d.y) <= size.y / 2.0


func build_preview(_height: Callable = Callable()) -> void:
	var p := MapPreview.fresh(self)
	MapPreview.label(p, Vector3(0, 1.5, 0), ("Chefe: " if boss else "") + str(name), 40)
