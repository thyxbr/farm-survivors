extends Node
## Fotos do mapa-mundi (M) no jogo de verdade: abre o atlas e salva a vista inicial, o mundo inteiro, o zoom
## na vila com a ficha de um NPC, a ficha da carruagem (as saídas), a borda (arrastar para fora não sai do
## mapa) e, antes de abrir, o minimapa do HUD. Precisa de janela:
##   godot --path . --resolution 1600x900 res://scenes/world.tscn -- --geardemo --atlasshot=<pasta>

var _out := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--atlasshot="):
			_out = a.substr(12)
	_run.call_deferred()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _run() -> void:
	var w: Node = null
	for i in 200:
		await _wait(0.1)
		w = get_tree().get_first_node_in_group("world") if get_tree().has_group("world") else get_tree().current_scene
		if w != null and w.get("player") != null and w.get("hud") != null:
			break
	await _wait(4.0)
	if w.modal != null:   # a narração de abertura do personagem novo
		w.modal.queue_free()
		w._on_modal_closed()
	_shot("minimapa")
	w.open_world_map(0)
	await _wait(2.5)
	var view: AtlasView = w.modal.view
	_shot("inicio")
	view.show_all()
	await _wait(1.5)
	view._mouse = view.to_screen(MapRules.atlas_center("mina"))
	view.queue_redraw()
	await _wait(0.3)
	_shot("mundo")
	view._goal_center = MapRules.to_atlas(Vector3(0, 0, 0))
	view._goal_zoom = 7.0
	await _wait(1.5)
	var npc: Node3D = null
	for n in get_tree().get_nodes_in_group("npc"):
		if n.get("marker") is Label3D and n.marker.text != "":
			npc = n
			break
	if npc == null:
		npc = get_tree().get_nodes_in_group("npc")[0]
	view._mouse = view.to_screen(MapRules.to_atlas(npc.global_position))
	view.queue_redraw()
	await _wait(0.3)
	_shot("npc")
	view._mouse = view.to_screen(MapRules.to_atlas(Regions.coach_point("vila")))
	view.queue_redraw()
	await _wait(0.3)
	_shot("carruagem")
	# arrastar para longe (oeste do vale): o centro para na borda do mapa
	view._goal_center = Vector2(-2000, 0)
	view._clamp_center()
	await _wait(1.5)
	view._mouse = Vector2(-1000, -1000)
	view.queue_redraw()
	await _wait(0.3)
	print("ATLASSHOT centro depois de arrastar para fora: ", view.center, " região: ", MapRules.atlas_region_at(view.center))
	_shot("borda")
	get_tree().quit()


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/atlas_%s.png" % [_out, name])
	print("ATLASSHOT ", name)
