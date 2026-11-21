extends Node
## Fotos do teleporte do mapa-mundi no jogo de verdade: o herói vai até a carruagem da vila pelo modo "map"
## e a reconstrução curta (ArrivalCutscene.quick) é fotografada ao longo do tempo. Precisa de janela:
##   godot --path . --resolution 1600x900 res://scenes/world.tscn -- --geardemo --teleportshot=<pasta>

var _out := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--teleportshot="):
			_out = a.substr(15)
	_run.call_deferred()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _run() -> void:
	var w: Node = null
	for i in 200:
		await _wait(0.1)
		w = get_tree().current_scene
		if w != null and w.get("player") != null and w.get("hud") != null:
			break
	await _wait(4.0)
	if w.modal != null:   # a narração de abertura do personagem novo
		w.modal.queue_free()
		w._on_modal_closed()
	w.player.global_position += Vector3(6, 0, -10)   # longe da carruagem, para a viagem mudar de lugar
	await _wait(0.5)
	w.travel_to("vila", "map")
	var t := 0.0
	for at in [0.3, 0.9, 1.5, 2.2, 2.8, 3.4, 4.0, 4.8, 6.0]:
		await _wait(at - t)
		t = at
		_shot("%04d" % int(at * 1000))
	print("TPSHOT input_locked=", w.player.input_locked, " camera_do_jogador=", w.player.camera.current,
		" pos=", w.player.global_position)
	get_tree().quit()


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/tp_%s.png" % [_out, name])
	print("TPSHOT ", name)
