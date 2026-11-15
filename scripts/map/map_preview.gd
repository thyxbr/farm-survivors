@tool
class_name MapPreview
extends RefCounted
## Ajudantes da prévia das peças de mapa no editor: altura no relevo, boneco com nome, rótulo, disco de área e
## o estilo toon (ToonLook por load(), porque estas peças não podem depender de nada que cite autoload).

const NAME := "Preview"


## Altura de uma peça: com `follow` ligado é o chão em (x, z) + a distância salva (`local_y`); sem chão válido
## (fora do relevo, servidor, teste) fica só a distância.
static func ground_y(follow: bool, local_y: float, height: Callable, x: float, z: float) -> float:
	if not follow or not height.is_valid():
		return local_y
	var h = height.call(x, z)
	if typeof(h) != TYPE_FLOAT or is_nan(h) or is_inf(h):
		return local_y
	return h + local_y


## Tira a prévia antiga e devolve um nó novo e vazio para a nova (filho sem dono: não vai para o arquivo).
static func fresh(owner_node: Node3D) -> Node3D:
	var old := owner_node.get_node_or_null(NAME)
	if old != null:
		owner_node.remove_child(old)
		old.free()
	var p := Node3D.new()
	p.name = NAME
	owner_node.add_child(p)
	return p


## Desloca a prévia para o chão: o nó fica onde o usuário pôs, o desenho desce/sobe até o relevo.
static func seat(owner_node: Node3D, preview: Node3D, follow: bool, height: Callable) -> void:
	var g := owner_node.global_position if owner_node.is_inside_tree() else owner_node.position
	var y := ground_y(follow, 0.0, height, g.x, g.z)
	var s := owner_node.scale.y if absf(owner_node.scale.y) > 0.0001 else 1.0
	preview.position.y = y / s if follow else 0.0   # a prévia é filha do nó: desfaz a escala dele


static func toon(root: Node) -> void:
	var tl: GDScript = load("res://scripts/world/toon_look.gd")
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		tl.convert_mesh(mi)


static func model(parent: Node3D, path: String) -> Node3D:
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var n: Node3D = ps.instantiate()
	parent.add_child(n)
	return n


static func mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## Boneco (cápsula) com nome em cima: NPCs e monstros na prévia.
static func dummy(parent: Node3D, pos: Vector3, text: String, c: Color, height := 1.7) -> void:
	var mi := MeshInstance3D.new()
	var m := CapsuleMesh.new()
	m.radius = height * 0.18
	m.height = height
	mi.mesh = m
	mi.position = pos + Vector3(0, height / 2.0, 0)
	mi.material_override = mat(c)
	parent.add_child(mi)
	if text != "":
		label(parent, pos + Vector3(0, height + 0.5, 0), text)


static func label(parent: Node3D, pos: Vector3, text: String, size := 48) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = 12
	l.pixel_size = 0.008
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = pos
	parent.add_child(l)


## Disco fino no chão (área de capim, raio de monstros).
static func disc(parent: Node3D, r: float, c: Color, y := 0.05) -> void:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = maxf(r, 0.05)
	m.bottom_radius = maxf(r, 0.05)
	m.height = 0.02
	mi.mesh = m
	mi.position.y = y
	mi.material_override = mat(c)
	parent.add_child(mi)


## Caixa (contorno de colisão, paredes).
static func box(parent: Node3D, center: Vector3, size: Vector3, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.position = center
	mi.material_override = mat(c)
	parent.add_child(mi)
