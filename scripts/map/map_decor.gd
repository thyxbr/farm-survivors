@tool
class_name MapDecor
extends Node3D
## Enfeite montado por código (sem GLB próprio): árvore de Natal, boneco de neve, trenó, bengala, presentes,
## varal de luzes, festão de lampião, guirlanda, carroça da guilda, espantalho, plantação, placa de texto e o fogo
## da forja (som). O editor e o jogo chamam o mesmo construtor (build_into), então a prévia é o enfeite de
## verdade. O enfeite fica na origem do nó: mova e gire o nó.
##
## params por tipo: xmas_tree {scale, seed}; candy_cane {scale}; gifts {count, seed, r0, r1};
## light_string {end (Vector3 no espaço do nó), sag, pattern, palette ("multi"/"warm")}; wreath {scale};
## crops {size (Vector2), seed}; label {text, font_size, color, billboard, width}.

const KINDS := ["xmas_tree", "snowman", "sleigh", "candy_cane", "gifts", "light_string", "lamp_garland", "wreath",
	"wagon", "scarecrow", "crops", "label", "forge_fire"]
const XMAS := "res://scripts/world/christmas_decor.gd"
const FIELD_CROP := "res://assets/models/field_crop.glb"

@export_enum("xmas_tree", "snowman", "sleigh", "candy_cane", "gifts", "light_string", "lamp_garland", "wreath",
	"wagon", "scarecrow", "crops", "label", "forge_fire") var kind := "xmas_tree":
	set(v):
		kind = v
		_refresh()
@export var params := {}:
	set(v):
		params = v
		_refresh()
## Assenta no relevo (a altura do nó vira distância até o chão).
@export var follow_ground := true

var _height := Callable()


func _ready() -> void:
	_refresh()


func _refresh() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		build_preview(_height)


func build_preview(height: Callable = Callable()) -> void:
	_height = height
	var p := MapPreview.fresh(self)
	build_into(p, true)
	MapPreview.seat(self, p, follow_ground, height)
	MapPreview.toon(p)


## Monta o enfeite dentro de `parent` (na origem dele). `preview`: no editor, o som não toca.
func build_into(parent: Node3D, preview := false) -> void:
	var cd: GDScript = load(XMAS)
	var g := func(k: String, d): return params.get(k, d)
	match kind:
		"xmas_tree":
			cd.tree(parent, Vector3.ZERO, float(g.call("scale", 1.0)), int(g.call("seed", 1)))
		"snowman":
			cd.snowman(parent, Vector3.ZERO, 0.0)
		"sleigh":
			cd.sleigh(parent, Vector3.ZERO, 0.0)
		"candy_cane":
			cd.candy_cane(parent, Vector3.ZERO, 0.0, float(g.call("scale", 1.0)))
		"gifts":
			var rng := RandomNumberGenerator.new()
			rng.seed = int(g.call("seed", 1))
			cd.gifts(parent, Vector3.ZERO, int(g.call("count", 3)), rng, float(g.call("r0", 0.0)), float(g.call("r1", 0.4)))
		"light_string":
			var pal: Array = cd.WARM if str(g.call("palette", "multi")) == "warm" else cd.MULTI
			cd.light_string(parent, Vector3.ZERO, g.call("end", Vector3(4, 0, 0)), float(g.call("sag", 0.5)), pal,
				int(g.call("pattern", 0)))
		"lamp_garland":
			cd.lamp_garland(parent)
		"wreath":
			cd.wreath(parent, Vector3.ZERO, float(g.call("scale", 1.0)))
		"wagon":
			parent.add_child(load("res://scripts/world/region_builder.gd").wagon(Vector3.ZERO, 0.0))
		"scarecrow":
			scarecrow(parent)
		"crops":
			crops(parent, g.call("size", Vector2(10, 7)), int(g.call("seed", 1)))
		"label":
			var l := Label3D.new()
			l.text = str(g.call("text", "Placa"))
			l.font_size = int(g.call("font_size", 48))
			l.pixel_size = float(g.call("pixel_size", 0.006))
			l.outline_size = int(g.call("outline_size", 10))
			l.modulate = g.call("color", Color.WHITE)
			if bool(g.call("billboard", true)):
				l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			if g.call("width", 0) > 0:
				l.width = float(g.call("width", 0))
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			parent.add_child(l)
		"forge_fire":
			if preview or DisplayServer.get_name() == "headless":
				return
			var fire: AudioStreamOggVorbis = load("res://assets/audio/ambience/fire_crackle.ogg")
			fire.loop = true
			var a := AudioStreamPlayer3D.new()
			a.name = "ForgeFire"
			a.stream = fire
			a.bus = &"Ambience"
			a.position = Vector3.UP * 0.6
			a.unit_size = 2.5
			a.max_distance = 14.0
			a.volume_db = 2.0
			a.autoplay = true
			parent.add_child(a)


## Espantalho de madeira, roupa e palha (o mesmo que a Horta tinha no world.gd).
static func scarecrow(parent: Node3D) -> void:
	var wood := MapPreview.mat(Color(0.45, 0.3, 0.17))
	var cloth := MapPreview.mat(Color(0.55, 0.2, 0.15))
	var sack := MapPreview.mat(Color(0.8, 0.7, 0.45))
	var straw := MapPreview.mat(Color(0.95, 0.8, 0.35))
	var parts := [
		[BoxMesh.new(), Vector3(0.1, 2.0, 0.1), Vector3(0, 1.0, 0), wood],
		[BoxMesh.new(), Vector3(1.5, 0.08, 0.08), Vector3(0, 1.5, 0), wood],
		[BoxMesh.new(), Vector3(0.6, 0.7, 0.3), Vector3(0, 1.35, 0), cloth],
		[SphereMesh.new(), Vector3(0.36, 0.36, 0.36), Vector3(0, 2.0, 0), sack],
		[CylinderMesh.new(), Vector3(0.5, 0.06, 0.5), Vector3(0, 2.2, 0), straw],
		[CylinderMesh.new(), Vector3(0.22, 0.3, 0.22), Vector3(0, 2.35, 0), straw],
		[BoxMesh.new(), Vector3(0.12, 0.25, 0.1), Vector3(0.78, 1.42, 0), straw],
		[BoxMesh.new(), Vector3(0.12, 0.25, 0.1), Vector3(-0.78, 1.42, 0), straw],
	]
	for pt in parts:
		var mi := MeshInstance3D.new()
		var m: Mesh = pt[0]
		if m is BoxMesh:
			m.size = pt[1]
		elif m is SphereMesh:
			m.radius = pt[1].x / 2.0
			m.height = pt[1].y
		else:
			m.top_radius = pt[1].x / 2.0
			m.bottom_radius = pt[1].x / 2.0
			m.height = pt[1].y
		mi.mesh = m
		mi.material_override = pt[3]
		mi.position = pt[2]
		parent.add_child(mi)


## Lote plantado: fileiras de field_crop (MultiMesh) num retângulo `size`, com falhas sorteadas por `seed`.
static func crops(parent: Node3D, size: Vector2, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var scn: Node3D = (load(FIELD_CROP) as PackedScene).instantiate()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = (scn.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	scn.free()
	var cols := maxi(int(size.x / 0.8), 1)
	var rows := maxi(int(size.y / 1.3), 1)
	var xforms: Array[Transform3D] = []
	for row in rows:
		for col in cols:
			if rng.randf() < 0.25:
				continue
			var p := Vector3(-size.x / 2.0 + 0.6 + col * 0.8, 0.0, -size.y / 2.0 + 0.9 + row * 1.3)
			var cs := rng.randf_range(0.85, 1.25)
			xforms.append(Transform3D(Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * cs), p))
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	parent.add_child(mmi)
