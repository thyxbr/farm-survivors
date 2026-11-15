@tool
class_name MapGroundPaint
extends Node3D
## Área pintada no chão (trilha, praça, lote de terra, clareira): retângulo ou disco com cor e borda suave. O
## shader do chão desenha a borda irregular. Gira só em Y; no máximo 40 por mapa (limite do ground.gd).
## No editor entra no chão da prévia (MapRoot); um contorno fino mostra onde ela está.

## Disco em vez de retângulo.
@export var disc := false:
	set(v):
		disc = v
		_refresh()
## Tamanho do retângulo (x, z).
@export var size := Vector2(4, 4):
	set(v):
		size = v
		_refresh()
## Raio do disco.
@export var radius := 4.0:
	set(v):
		radius = v
		_refresh()
@export var color := Color(0.45, 0.35, 0.22):
	set(v):
		color = v
		_refresh()
## Suavidade da borda (0 = dura).
@export_range(0.0, 1.0, 0.01) var soft := 0.8
## Quanto capim cresce em cima (0 = nenhum).
@export_range(0.0, 1.0, 0.01) var grass := 0.0


func _ready() -> void:
	_refresh()


func _refresh() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		build_preview()


## Contorno da área (o desenho de verdade é do chão, que o MapRoot remonta).
func build_preview(_height: Callable = Callable()) -> void:
	var p := MapPreview.fresh(self)
	var c := Color(color, 0.35)
	if disc:
		MapPreview.disc(p, radius, c, 0.12)
	else:
		MapPreview.box(p, Vector3(0, 0.12, 0), Vector3(size.x, 0.02, size.y), c)
