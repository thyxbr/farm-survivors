@tool
class_name VillageBuilding
extends Node3D
## Uma construção da vila na cena scenes/village.tscn (casa, loja ou o poço). No editor ela mostra o modelo
## (com as cores da paleta), então dá para arrastar, girar e duplicar (Ctrl+D) as casas no 3D. No jogo o
## world.gd não põe esta cena na árvore: ele lê a posição, o giro e as opções de cada uma
## (VillageLayout.buildings()) e monta o modelo, a colisão, as luzes, os enfeites e as flores.
##
## Só o giro em volta do eixo Y e a posição contam (escala e inclinação são ignoradas). A frente da casa
## (a porta) é o +Z do nó: a seta azul do gizmo local aponta para a rua.

const MODELS := ["house", "house_b", "house_c", "house_d", "house_e", "house_f",
	"shop_merchant", "shop_alchemist", "shop_smithy", "well"]

## Modelo: as seis casas, as três lojas (com a Mira, a Pip e o ferreiro na frente) ou o poço.
@export_enum("house", "house_b", "house_c", "house_d", "house_e", "house_f",
	"shop_merchant", "shop_alchemist", "shop_smithy", "well") var model := "house":
	set(v):
		model = v
		_refresh()
## Cores da casa (índice em VillageLayout.PALETTES); -1 = cores originais do modelo. Só vale para casas.
@export_range(-1, 15) var palette := -1:
	set(v):
		palette = v
		_refresh()
## Canteiro na frente da porta: nenhum, dois vasos (um de cada lado) ou quatro flores sorteadas.
@export_enum("Nenhum", "Dois vasos", "Quatro sorteadas") var flowers := 1
## Uma das portas da missão de Natal "Entregas na Vila" (a missão pede 6).
@export var delivery := false


func _ready() -> void:
	_refresh()


func is_house() -> bool:
	return model.begins_with("house")


## Prévia do modelo, só no editor. O nó fica sem dono, então não vai para o arquivo da cena.
func _refresh() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		build_preview()


## Monta a prévia (o editor chama sozinho; as ferramentas de foto chamam direto).
func build_preview(_height: Callable = Callable()) -> void:
	var old := get_node_or_null("Preview")
	if old != null:
		remove_child(old)
		old.free()
	var scn := load("res://assets/models/%s.glb" % model) as PackedScene
	if scn == null:
		return
	var v: Node3D = scn.instantiate()
	v.name = "Preview"
	add_child(v)
	# os scripts do jogo vão por load(): esta cena também é lida nos testes, onde autoload não compila
	if is_house():
		VillageLayout.tint(v, palette)
		_house_extras(v)
	else:
		_shop_extras(v)
	var toon: GDScript = load("res://scripts/world/toon_look.gd")
	for mi: MeshInstance3D in v.find_children("*", "MeshInstance3D", true, false):
		toon.convert_mesh(mi)


## Pisca-pisca, guirlanda e canteiro, como o world.gd põe no jogo.
func _house_extras(v: Node3D) -> void:
	var cd: GDScript = load("res://scripts/world/christmas_decor.gd")
	cd.house_lights(v, model, 0)
	var d: Array = cd.HOUSE_DOORS[model]
	cd.wreath(v, Vector3(d[0], d[1], d[2]))
	var depth: float = VillageLayout.HOUSE_SIZE[model].z
	var spots: Array = []
	if flowers == 1:
		for off in [-1.6, 1.6]:
			if absf(off - float(d[0])) >= 0.9:
				spots.append(Vector3(off, 0, depth * 0.5 + 0.55))
	elif flowers == 2:
		for off in [-2.2, -1.5, 1.5, 2.2]:
			spots.append(Vector3(off, 0, 2.75))
	for i in spots.size():
		var kind := "flower_lavender" if i % 2 == 0 else "flower_tulips"
		var f: Node3D = (load("res://assets/models/%s.glb" % kind) as PackedScene).instantiate()
		f.position = spots[i]
		v.add_child(f)


## O dono na frente da loja (boneco com o nome); na ferraria, a bigorna e a forja do ferreiro.
func _shop_extras(v: Node3D) -> void:
	match model:
		"shop_merchant":
			_keeper(v, VillageLayout.MERCHANT_SPOT, "Mira")
		"shop_alchemist":
			_keeper(v, VillageLayout.ALCHEMIST_SPOT, "Pip")
		"shop_smithy":
			_keeper(v, Vector3.ZERO, "Ferreiro")
			var bs: GDScript = load("res://scripts/world/blacksmith.gd")
			for part in [["anvil", bs.ANVIL_OFFSET, bs.ANVIL_YAW], ["forge", bs.FORGE_OFFSET, bs.FORGE_YAW]]:
				var n: Node3D = (load("res://assets/models/%s.glb" % part[0]) as PackedScene).instantiate()
				n.position = part[1]
				n.rotation.y = part[2]
				v.add_child(n)


func _keeper(v: Node3D, at: Vector3, text: String) -> void:
	var mi := MeshInstance3D.new()
	var m := CapsuleMesh.new()
	m.radius = 0.3
	m.height = 1.7
	mi.mesh = m
	mi.position = at + Vector3(0, 0.85, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.3)
	mi.material_override = mat
	v.add_child(mi)
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.outline_size = 12
	l.pixel_size = 0.008
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = at + Vector3(0, 2.2, 0)
	v.add_child(l)
