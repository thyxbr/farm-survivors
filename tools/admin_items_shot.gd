extends Node
## Confere o menu "Adicionar item" do modo admin sem abrir o jogo: liga o modo admin no personagem de
## demonstração, abre o painel, busca, adiciona e veste o que achou, imprime o resultado e tira uma foto.
## Precisa de janela (sem --headless):
##   godot --path . --resolution 1280x720 res://tools/admin_items_shot.tscn -- <saida.png> [busca] --geardemo

const PANEL := preload("res://scripts/ui/admin_items_panel.gd")

var _frames := 0
var _panel: Control
var _out := "user://admin_items.png"
var _query := "arquimago"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not args[0].begins_with("--"):
		_out = args[0]
	if args.size() > 1 and not args[1].begins_with("--"):
		_query = args[1]
	Econ.set_admin(true)
	_panel = PANEL.new()
	add_child(_panel)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 5:
		_panel._search.text = _query
		_panel._fill()
	elif _frames == 10:
		for id: String in _panel.matching():
			_panel._give(id)
	elif _frames == 600:   # espera os ícones 3D da grade ficarem prontos
		print("ADMIN ", Game.admin_mode(), " | ACHOU ", _panel.matching(), " | VESTIDO ", Game.equipment)
		get_viewport().get_texture().get_image().save_png(_out)
		print("SHOT ", _out)
		get_tree().quit()
