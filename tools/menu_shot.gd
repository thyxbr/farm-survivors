extends SceneTree
## Fotos do menu principal com cada cena do fundo (MenuBackdrop), para conferir o visual sem abrir o jogo.
## Precisa de janela (sem --headless):
##   godot --path . --resolution 1600x900 --script res://tools/menu_shot.gd -- <pasta_saida> [segundo_da_cena]
## Salva menu_<cena>.png na pasta, e no fim menu_login.png (painel "Jogar online") e menu_opcoes.png.

var _out := ""
var _at := 6.0
var _menu: Control
var _i := -1
var _wait := 0
var _scenes: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://menu_shots"
	if args.size() > 1 and args[1].is_valid_float():
		_at = float(args[1])
	DirAccess.make_dir_recursive_absolute(_out)
	_menu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(_menu)
	_wait = 150   # deixa o menu montar e a entrada animada terminar


func _process(_delta: float) -> bool:
	if _wait > 0:
		_wait -= 1
		return false
	var bd = _menu.get("backdrop")
	if bd == null:
		quit(1)
		return true
	if _scenes.is_empty():
		_scenes = bd.ORDER.duplicate()
	if _i >= 0:
		var img := root.get_texture().get_image()
		var path := _out.path_join("menu_%s.png" % _scenes[_i])
		img.save_png(path)
		print("salvo ", path)
	_i += 1
	if _i == 0:
		_scenes.append_array(["login", "opcoes"])   # telas do menu, depois das cenas do fundo
	if _i >= _scenes.size():
		quit()
		return true
	match _scenes[_i]:
		"login":
			_menu.call("_open_multiplayer")
			_wait = 30
			return false
		"opcoes":
			_menu.call("_close_multiplayer")
			_menu.call("_options")
			_wait = 30
			return false
	bd.show_scene(_scenes[_i], _at)
	_wait = 12
	return false
