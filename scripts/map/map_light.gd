@tool
class_name MapLight
extends OmniLight3D
## Luz do mapa. Normal fica sempre acesa; "noite" acende ao escurecer (lampiões, janelas); "piscando" tremula
## como fogo (fogueiras, tochas). Cor, alcance e força são os da própria OmniLight3D.

@export_enum("Normal", "Noite", "Piscando") var mode := 0
## Força da luz acesa à noite (o modo noite parte de 0 durante o dia).
@export var night_energy := 1.0


## Peça de mapa (o MapRoot e o MapLoader acham as peças por este método); a luz em si já é a prévia.
func build_preview(_height: Callable = Callable()) -> void:
	pass
