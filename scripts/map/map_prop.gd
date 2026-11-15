@tool
class_name MapProp
extends Node3D
## Um objeto do mapa feito de um modelo GLB (árvore, pedra, cerca, caixote, tenda, ruína, lampião...). A escala
## do nó é a escala do modelo. No jogo vira o modelo + uma colisão simples (caixa ou cilindro, como o prop()
## antigo do world.gd) e tira o capim de baixo dele.

const MODELS := ["tree_oak", "tree_pine", "tree_fir", "tree_birch", "tree_maple", "tree_cherry", "tree_apple",
	"tree_orange", "tree_pear", "rock", "fence", "crate", "barrel", "chest", "tent", "campfire", "lamp", "well",
	"notice_board", "signpost", "ruin_pillar", "ruin_wall", "anvil", "forge", "flower_sunflower",
	"flower_lavender", "flower_tulips", "house", "house_b", "house_c", "house_d", "house_e", "house_f",
	"shop_smithy", "shop_alchemist", "shop_merchant"]

## Colisão padrão de cada modelo: [forma (1 caixa, 2 cilindro), tamanho]. Caixa: largura, altura, profundidade;
## cilindro: x = raio, y = altura. Valores tirados do world.gd antigo.
const DEFAULT_SHAPE := {
	"tree_oak": [2, Vector3(0.4, 3, 0)], "tree_pine": [2, Vector3(0.35, 3, 0)], "tree_fir": [2, Vector3(0.32, 3, 0)],
	"tree_birch": [2, Vector3(0.25, 3, 0)], "tree_maple": [2, Vector3(0.4, 3, 0)],
	"tree_cherry": [2, Vector3(0.38, 3, 0)], "tree_apple": [2, Vector3(0.3, 3, 0)],
	"tree_orange": [2, Vector3(0.3, 3, 0)], "tree_pear": [2, Vector3(0.3, 3, 0)],
	"rock": [2, Vector3(0.65, 0.9, 0)], "fence": [1, Vector3(2.1, 1.0, 0.25)],
	"crate": [1, Vector3(0.8, 0.8, 0.8)], "barrel": [2, Vector3(0.38, 1.0, 0)], "chest": [1, Vector3(0.9, 0.7, 0.6)],
	"tent": [1, Vector3(2.0, 2.2, 2.0)], "campfire": [2, Vector3(0.6, 0.4, 0)], "lamp": [2, Vector3(0.12, 3.7, 0)],
	"well": [2, Vector3(0.95, 1.2, 0)], "notice_board": [1, Vector3(2.7, 2.8, 0.3)],
	"signpost": [2, Vector3(0.25, 2.6, 0)], "ruin_pillar": [2, Vector3(0.5, 4.0, 0)],
	"ruin_wall": [1, Vector3(4.2, 2.0, 0.9)], "anvil": [2, Vector3(0.3, 0.8, 0)], "forge": [1, Vector3(0.9, 1.0, 0.8)],
}
const COLLIDER_COLOR := Color(0.2, 0.6, 1.0, 0.25)

## Modelo (assets/models/<modelo>.glb).
@export_enum("tree_oak", "tree_pine", "tree_fir", "tree_birch", "tree_maple", "tree_cherry", "tree_apple",
	"tree_orange", "tree_pear", "rock", "fence", "crate", "barrel", "chest", "tent", "campfire", "lamp", "well",
	"notice_board", "signpost", "ruin_pillar", "ruin_wall", "anvil", "forge", "flower_sunflower",
	"flower_lavender", "flower_tulips", "house", "house_b", "house_c", "house_d", "house_e", "house_f",
	"shop_smithy", "shop_alchemist", "shop_merchant") var model := "rock":
	set(v):
		var changed := v != model
		model = v
		if changed and Engine.is_editor_hint() and DEFAULT_SHAPE.has(v):
			shape = DEFAULT_SHAPE[v][0]
			shape_size = DEFAULT_SHAPE[v][1]
		_refresh()
## Colisão: nenhuma, caixa ou cilindro.
@export_enum("Nenhuma", "Caixa", "Cilindro") var shape := 0:
	set(v):
		shape = v
		_refresh()
## Tamanho da colisão antes da escala do nó (caixa: x, y, z; cilindro: x = raio, y = altura).
@export var shape_size := Vector3.ZERO:
	set(v):
		shape_size = v
		_refresh()
## Tira o capim de baixo do objeto.
@export var no_grass := true
## Assenta no relevo (a altura do nó vira distância até o chão).
@export var follow_ground := true

var _height := Callable()


static func model_path(m: String) -> String:
	return "res://assets/models/%s.glb" % m


func _ready() -> void:
	if Engine.is_editor_hint():
		set_notify_transform(true)
	_refresh()


func _refresh() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		build_preview(_height)


## Pegada no chão (raio) já com a escala do nó; 0 sem colisão.
func footprint() -> float:
	return footprint_for(scale.x)


## Pegada no chão (raio) com a escala `s`; 0 sem colisão.
func footprint_for(s: float) -> float:
	if shape == 1:
		return maxf(shape_size.x, shape_size.z) * 0.5 * s
	if shape == 2:
		return shape_size.x * s
	return 0.0


func build_preview(height: Callable = Callable()) -> void:
	_height = height
	var p := MapPreview.fresh(self)
	MapPreview.model(p, model_path(model))
	if not MapPreview.show_colliders:
		pass
	elif shape == 1:
		MapPreview.box(p, Vector3(0, shape_size.y / 2.0, 0), shape_size, COLLIDER_COLOR)
	elif shape == 2:
		var mi := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = maxf(shape_size.x, 0.01)
		c.bottom_radius = maxf(shape_size.x, 0.01)
		c.height = maxf(shape_size.y, 0.01)
		mi.mesh = c
		mi.position.y = shape_size.y / 2.0
		mi.material_override = MapPreview.mat(COLLIDER_COLOR)
		p.add_child(mi)
	MapPreview.seat(self, p, follow_ground, height)
	MapPreview.toon(p)

## No editor: mover o nó reassenta a prévia no relevo.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		_refresh()
