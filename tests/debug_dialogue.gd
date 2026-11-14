extends Node
# Depuração: abre cada janela modal e salva um screenshot de cada (pasta passada em --dbgdir=).

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dir := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dbgdir="):
			dir = a.substr(9)
	await get_tree().create_timer(1.5).timeout
	var world := get_tree().current_scene
	for n in get_tree().get_nodes_in_group("interactable"):
		if n.npc_id == "elder":
			n.interact(null)
	await _shot(dir + "/m_dialogue.png", 1.5)
	world.modal._close()
	for n in get_tree().get_nodes_in_group("interactable"):
		if n.npc_id == "merchant":
			n.interact(null)
	await _shot(dir + "/m_dialogue_merchant.png", 1.5)
	world.modal._close()
	for n in get_tree().get_nodes_in_group("interactable"):
		if n.npc_id == "blacksmith":
			n.interact(null)
	await _shot(dir + "/m_dialogue_blacksmith.png", 1.5)
	world.modal._close()
	await get_tree().create_timer(0.8).timeout
	world._open_menu(0)
	await _shot(dir + "/m_inventory.png", 0.4)
	world.modal.tabs.current_tab = 1
	await _shot(dir + "/m_character.png", 0.4)
	world.modal._close()
	world.open_shop()
	await _shot(dir + "/m_shop.png", 0.4)
	world.modal._close()
	var p = load("res://scripts/ui/pause_menu.gd").new()
	world._open_modal(p)
	await _shot(dir + "/m_pause.png", 0.4)
	get_tree().quit()


func _shot(path: String, wait: float) -> void:
	await get_tree().create_timer(wait, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
