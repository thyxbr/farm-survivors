@tool
class_name MapGrassArea
extends Node3D
## Área do capim: sem capim (ex.: dentro da arena, em cima das ruas) ou capim ralo (praça, Horta). O capim em si
## continua gerado pelo código; esta área só diz onde ele não nasce ou nasce pouco.

## Ralo em vez de nenhum.
@export var sparse := false:
	set(v):
		sparse = v
		_refresh()
@export var radius := 5.0:
	set(v):
		radius = v
		_refresh()


func _ready() -> void:
	_refresh()


func _refresh() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		build_preview()


func build_preview(_height: Callable = Callable()) -> void:
	var p := MapPreview.fresh(self)
	MapPreview.disc(p, radius, Color(0.9, 0.9, 0.3, 0.12) if sparse else Color(0.9, 0.3, 0.3, 0.12), 0.1)
