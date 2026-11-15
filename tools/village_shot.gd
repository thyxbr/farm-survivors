extends SceneTree
## Fotos da vila de Valdoria montada de verdade (scenes/world.tscn), de alguns ângulos fixos: serve para
## conferir casas e lojas no lugar (encaixe entre as casas, NPCs na frente dos balcões) sem jogar.
## Usa o personagem de demonstração (--geardemo), não o save. Precisa de janela (sem --headless) e do --import:
##   godot --path . --resolution 1600x900 --script res://tools/village_shot.gd -- <pasta_saida> [vista,vista] --geardemo
## Vistas: over (de cima), east (empório), west (botica), smithy (ferraria), north (casas do fundo), south,
## xmas (árvore de Natal), gate (bengalas do portão norte). `--hora=22` tira as fotos de noite.

const VIEWS := {
	"xmas": [Vector3(1.0, 2.6, -3.5), Vector3(6, 2.0, -9.5)],
	"gate": [Vector3(0, 2.2, -8.0), Vector3(2.5, 0.8, -12.4)],
	"over": [Vector3(2, 26, -20), Vector3(0, 0, 4)],
	"east": [Vector3(-1, 4.5, -5), Vector3(9.5, 1.4, 0.5)],
	"west": [Vector3(1, 4.5, 5.5), Vector3(-12, 1.6, 0.5)],
	"smithy": [Vector3(-3.5, 4.0, 6.0), Vector3(-11.0, 1.4, 13.5)],
	"north": [Vector3(0, 5.0, 3), Vector3(0, 2.0, 16)],
	"south": [Vector3(3, 6.0, 9), Vector3(0, 1.5, -7)],
}

var _out := ""
var _views: Array = []
var _cam: Camera3D
var _t := 0.0
var _i := -1
var _wait := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://"
	_views = Array(args[1].split(",")) if args.size() > 1 and not args[1].begins_with("--") else VIEWS.keys()
	change_scene_to_file("res://scenes/world.tscn")


func _process(delta: float) -> bool:
	_t += delta
	if _t < 9.0:   # a vila é montada em etapas atrás da tela de carregamento
		return false
	if _cam == null:
		for c in root.find_children("*", "CanvasLayer", true, false):
			(c as CanvasLayer).visible = false
		_cam = Camera3D.new()
		_cam.fov = 60.0
		root.add_child(_cam)
		_cam.current = true
		_next()
		return false
	_wait += 1
	if _wait < 12:
		return false
	var path := "%s/village_%s.png" % [_out, _views[_i]]
	root.get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)
	_next()
	return _i >= _views.size()


func _next() -> void:
	_i += 1
	_wait = 0
	if _i < _views.size():
		var v: Array = VIEWS[_views[_i]]
		_cam.position = v[0]
		_cam.look_at(v[1])
		_cam.current = true
