extends SceneTree
## Foto de uma cena qualquer depois de N quadros (para conferir telas de UI, como a seleção de heróis).
## Precisa de janela (sem --headless). Argumentos extras depois do "--" seguem para a cena:
##   godot --path . --resolution 1600x900 --script res://tools/scene_shot.gd -- <cena.tscn> <saida.png> [quadros] [args...]
## Exemplo: ... -- res://scenes/char_select.tscn shot.png 120 --charselect-demo --charselect-pick=1

var _out := ""
var _frames := 120


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[1]
	if args.size() > 2 and args[2].is_valid_int():
		_frames = int(args[2])
	change_scene_to_file(args[0])


func _process(_delta: float) -> bool:
	_frames -= 1
	if _frames > 0:
		return false
	root.get_texture().get_image().save_png(_out)
	print("salvo ", _out)
	quit()
	return true
