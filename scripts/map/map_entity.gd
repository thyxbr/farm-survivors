@tool
class_name MapEntity
extends Node3D
## Algo do mapa que tem script de jogo: NPC, ponto da antiga praça, canteiro da Horta, cozinha, ponto da
## história, presente ou porta do Natal, portal da Horda, poste de direção, Papai Noel, nó de coleta. No jogo o
## mundo cria o nó certo pelo `kind` (world.gd, make_entity); aqui ficam só os dados, sem autoload.

## Tipo: elder, merchant, alchemist, blacksmith, rival, npc, story_point, hub_point, farm_plot, kitchen,
## portal, signpost, santa, xmas_gift, xmas_door, resource_node, guard (guarda da vila, VillageGuard), station
## (bancada de craft), walker (morador que passeia: ref = id do NPC; o caminho são os filhos MapWaypoint, que se
## arrastam no 3D; sem filhos vale o antigo params.path = [[x, z, espera?], ...] no mundo).
@export var kind := "npc"
## Referência do tipo: id do NPC ou do ponto da história, building_id do ponto da praça, tipo do veio
## (iron/crystal) do nó de coleta.
@export var ref := ""
## Índice (canteiro 0..11, presente 0..7, porta 0..5); -1 quando não se aplica.
@export var index := -1
## Número fixo do nó de coleta (o mesmo que o save e a rede usam); -1 quando não é nó de coleta.
@export var node_id := -1
## Parâmetros extras do tipo (ex.: destinos do poste de direção).
@export var params := {}
## Assenta no relevo (a altura do nó vira distância até o chão).
@export var follow_ground := true

const LABELS := {"elder": "Ancião Bram", "merchant": "Mira", "alchemist": "Pip", "blacksmith": "Ferreiro",
	"rival": "Kael", "santa": "Papai Noel", "kitchen": "Cozinha", "portal": "Portal da Horda", "station": "Bancada",
	"guard": "Guarda da vila"}
const COLORS := {"npc": Color(1.0, 0.85, 0.3), "hub_point": Color(0.85, 0.3, 0.9), "story_point": Color(0.4, 0.8, 1.0),
	"resource_node": Color(0.6, 0.65, 0.7), "xmas_gift": Color(0.9, 0.2, 0.2), "xmas_door": Color(0.9, 0.2, 0.2),
	"farm_plot": Color(0.4, 0.27, 0.15)}

var _height := Callable()


func _ready() -> void:
	if Engine.is_editor_hint():
		set_notify_transform(true)
	if Engine.is_editor_hint():
		build_preview(_height)


## Nome mostrado na prévia: o tipo, a referência e o número quando houver.
func caption() -> String:
	var t: String = LABELS.get(kind, kind)
	if ref != "":
		t = "%s: %s" % [t, ref]
	if node_id >= 0:
		t += " #%d" % node_id
	elif index >= 0:
		t += " #%d" % index
	return t


func build_preview(height: Callable = Callable()) -> void:
	_height = height
	var p := MapPreview.fresh(self)
	match kind:
		"signpost":
			MapPreview.model(p, "res://assets/models/signpost.glb")
			MapPreview.label(p, Vector3(0, 3.2, 0), caption())
		"portal":
			MapPreview.disc(p, 1.4, Color(0.6, 0.3, 1.0, 0.7))
			MapPreview.label(p, Vector3(0, 2.5, 0), caption())
		"farm_plot", "resource_node", "xmas_gift", "kitchen":
			MapPreview.box(p, Vector3(0, 0.3, 0), Vector3(1.2, 0.6, 1.2), COLORS.get(kind, Color(0.8, 0.6, 0.3)))
			MapPreview.label(p, Vector3(0, 1.3, 0), caption(), 36)
		"hub_point":
			MapPreview.box(p, Vector3(0, 1.0, 0), Vector3(1.2, 2.0, 1.2), Color(0.85, 0.3, 0.9, 0.6))
			MapPreview.label(p, Vector3(0, 2.6, 0), caption())
		"walker":
			_walker_preview(p, height)
		_:
			MapPreview.dummy(p, Vector3.ZERO, caption(), COLORS.get(kind, Color(1.0, 0.85, 0.3)))
	MapPreview.seat(self, p, follow_ground, height)

## Caminho do morador que passeia, no mundo: os filhos MapWaypoint em ordem; sem eles, o params.path.
func walk_path() -> Array:
	var out: Array = []
	for c in get_children():
		if c is MapWaypoint:
			out.append((c as MapWaypoint).path_point())
	return out if not out.is_empty() else params.get("path", [])


## Um MapWaypoint filho mudou (arrastado, duplicado, espera nova): redesenha o caminho.
func waypoints_changed() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		build_preview(_height)


## Boneco no primeiro ponto, faixa azul ligando os pontos e a marca de cada ponto (clicável no 3D).
func _walker_preview(p: Node3D, height: Callable) -> void:
	var base := MapPreview.ground_y(follow_ground, 0.0, height, global_position.x, global_position.z)
	var pts: Array[Vector3] = []
	var n := 0
	for c in get_children():
		if not c is MapWaypoint:
			continue
		var wp := c as MapWaypoint
		var g := wp.global_position
		var gy := MapPreview.ground_y(true, 0.0, height, g.x, g.z)
		wp.draw_marker(gy - g.y, n)
		var l := to_local(g)
		pts.append(Vector3(l.x, gy - base, l.z))
		n += 1
	if pts.is_empty():   # caminho antigo, em números: só o boneco
		MapPreview.dummy(p, Vector3.ZERO, caption() + " (sem pontos)", COLORS.get(kind, Color(1.0, 0.85, 0.3)))
		return
	MapPreview.dummy(p, pts[0], caption(), Color(0.3, 0.9, 1.0))
	for i in range(1, pts.size()):
		MapPreview.segment(p, pts[i - 1], pts[i], Color(0.3, 0.9, 1.0, 0.6))


## No editor: mover o nó reassenta a prévia no relevo.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		build_preview(_height)
