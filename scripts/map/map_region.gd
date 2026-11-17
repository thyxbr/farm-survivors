@tool
class_name MapRegion
extends Node3D
## Região de monstros com nome (Campos do Norte, Toca dos Goblins...). O nó dá a forma e o lugar; nome, faixa de
## nível, densidade e se aparece no mapa ficam no data/balance/regions.json, na chave `region_id` (mudar a faixa
## não exige abrir a cena). Vários nós com o mesmo `region_id` formam uma região só (ex.: o capinzal em 4 manchas).
## Quem usa: os pontos de monstro com nível 0 tiram a faixa daqui; o mapa, o minimapa e o aviso de entrada mostram
## o nome; missões com "region" só contam abates aqui dentro (Regions.area_at).

const RECT := 0
const DISC := 1
const REGIONS_JSON := "res://data/balance/regions.json"
const COLOR := Color(1.0, 0.75, 0.2)

## Chave da região no data/balance/regions.json.
@export var region_id := "":
	set(v):
		region_id = v
		_refresh()
## Retângulo (gira com o nó, em Y) ou disco.
@export_enum("Retângulo", "Disco") var shape := RECT:
	set(v):
		shape = v
		_refresh()
## Largura (X) e profundidade (Z) do retângulo, em metros.
@export var size := Vector2(30, 30):
	set(v):
		size = v
		_refresh()
## Raio do disco, em metros.
@export_range(1.0, 200.0, 0.5) var radius := 15.0:
	set(v):
		radius = v
		_refresh()
## Assenta a prévia no relevo.
@export var follow_ground := true

var _height := Callable()


func _ready() -> void:
	if Engine.is_editor_hint():
		set_notify_transform(true)
		build_preview(_height)


func _refresh() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		build_preview(_height)


## Texto da prévia: "Nome · Nv a–b" lido direto do JSON (no editor não há o autoload Balance).
func preview_text() -> String:
	var data = JSON.parse_string(FileAccess.get_file_as_string(REGIONS_JSON)) if FileAccess.file_exists(REGIONS_JSON) else null
	var t: Dictionary = BalanceTables.decode(data) if data is Dictionary else {}
	if not t.has(region_id):
		return "⚠ %s (não está no regions.json)" % region_id
	return Regions.area_label(t, region_id)


## Contorno da região no chão (disco ou placa translúcida) e o nome com a faixa no meio.
func build_preview(height: Callable = Callable()) -> void:
	_height = height
	var p := MapPreview.fresh(self)
	if shape == DISC:
		MapPreview.disc(p, radius, Color(COLOR, 0.12), 0.1)
	else:
		MapPreview.box(p, Vector3(0, 0.1, 0), Vector3(size.x, 0.02, size.y), Color(COLOR, 0.12))
	MapPreview.label(p, Vector3(0, 4.0, 0), preview_text(), 96)
	MapPreview.seat(self, p, follow_ground, height)


## No editor: mover o nó reassenta a prévia no relevo.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		build_preview(_height)
