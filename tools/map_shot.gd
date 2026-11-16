extends SceneTree
## Fotos de uma cena de mapa como o editor mostra (prévia do MapRoot: chão, luz, toon e todas as peças), sem
## abrir o editor. Serve para conferir a cena e comparar com o jogo (tools/village_shot.gd) nas mesmas vistas.
## Precisa de janela (sem --headless) e do --import:
##   godot --path . --resolution 1200x700 --script res://tools/map_shot.gd -- <pasta_saida> <cena.tscn> [vista,vista]
## Vistas do vale: as do village_shot (over, wide, east, west, westside, eastside, ...) e camp, ruins, arena,
## fields, nest. Regiões (cena com origem local): region_wide, region_center. Sem vistas: wide.

const VIEWS := {
	"over": [Vector3(2, 26, -20), Vector3(0, 0, 4)],
	"wide": [Vector3(0, 62, 52), Vector3(0, 0, 3)],
	"east": [Vector3(-1, 4.5, -5), Vector3(9.5, 1.4, 0.5)],
	"west": [Vector3(1, 4.5, 5.5), Vector3(-12, 1.6, 0.5)],
	"smithy": [Vector3(-3.5, 4.0, 6.0), Vector3(-11.0, 1.4, 13.5)],
	"westside": [Vector3(-10, 9, -8), Vector3(-27, 1, 3)],
	"eastside": [Vector3(10, 9, -8), Vector3(28, 1, 3)],
	"largo": [Vector3(21, 5.5, 0.5), Vector3(21, 1.2, 9)],
	"camp": [Vector3(40, 18, 18), Vector3(62, 0, 0)],
	"ruins": [Vector3(0, 24, -66), Vector3(0, 0, -100)],
	"arena": [Vector3(-40, 30, 10), Vector3(-72, 0, -10)],
	"fields": [Vector3(0, 22, -8), Vector3(0, 0, -36)],
	"nest": [Vector3(-20, 14, 20), Vector3(-36, 0, 36)],
	"region_wide": [Vector3(0, 90, 95), Vector3(0, 0, 0)],
	"region_center": [Vector3(0, 14, 40), Vector3(0, 0, 0)],
}

var _out := ""
var _views: Array = []
var _cam: Camera3D
var _frame := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0]
	var root: Node3D = (load(args[1]) as PackedScene).instantiate()
	_views = (args[2] if args.size() > 2 else "wide").split(",")
	get_root().add_child.call_deferred(root)
	_cam = Camera3D.new()
	_cam.far = 2000.0
	root.add_child(_cam)
	(func() -> void: root.build_preview()).call_deferred()


func _process(_d: float) -> bool:
	_frame += 1
	var i := _frame / 20 - 1
	if _frame % 20 != 0 or i < 0:
		return false
	if i > 0:
		var name: String = _views[i - 1]
		get_root().get_texture().get_image().save_png("%s/mapa_%s.png" % [_out, name])
		print("MAPSHOT ", name)
	if i >= _views.size():
		return true
	var v: Array = VIEWS.get(_views[i], VIEWS.wide)
	_cam.position = v[0]
	_cam.look_at(v[1])
	_cam.current = true
	return false
