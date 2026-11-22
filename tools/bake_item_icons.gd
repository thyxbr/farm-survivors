extends Node
## Assa os ícones 3D dos itens (ItemIcons.render_image) em assets/ui/item_icons/<id>.png, para o jogo já
## sair com eles prontos em vez de fotografar cada item na primeira vez que a tela abre.
## Precisa de janela (sem --headless). Depois rode --import para gerar os .import:
##   godot --path . res://tools/bake_item_icons.tscn            (só os que faltam)
##   godot --path . res://tools/bake_item_icons.tscn -- --all   (refaz todos: modelo de item mudou)
##   godot --path . res://tools/bake_item_icons.tscn -- iron_sword leather_cap   (só esses)
## Item com arte pintada (assets/ui/items) não precisa: ItemSlot usa a arte.

var _icons: ItemIcons


func _ready() -> void:
	_icons = ItemIcons.new()
	add_child(_icons)
	_bake.call_deferred()


func _bake() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var all := "--all" in args
	var only: Array = args.filter(func(a: String) -> bool: return not a.begins_with("--"))
	var dir := ProjectSettings.globalize_path(ItemIcons.BAKED_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var ids: Array = ItemDB.ITEMS.keys() if only.is_empty() else only
	ids.sort()
	var made := 0
	var skipped := 0
	for id: String in ids:
		if id != ItemQuality.base(id) or not ItemIcons._has_model(id):
			continue
		var out := dir.path_join(id + ".png")
		if not all and only.is_empty() and FileAccess.file_exists(out):
			skipped += 1
			continue
		var img: Image = await _icons.render_image(id)
		if img == null:
			print("SEM MODELO ", id)
			continue
		img.save_png(out)
		made += 1
	print("ICONES assados %d, já existiam %d" % [made, skipped])
	get_tree().quit()
