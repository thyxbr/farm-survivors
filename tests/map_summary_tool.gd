extends Node
## Grava o retrato do mundo montado (WorldSummary) num arquivo e fecha. Usado para a linha de base da
## conversão para cenas e pelo smoke test (que compara com tests/fixtures/map_baseline.txt):
##   godot --headless --path . res://scenes/world.tscn -- --mapsummary=<arquivo> --solo-save=user://mapsummary_solo.json


func _ready() -> void:
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mapsummary="):
			path = a.substr(13)
	var w: Node = null
	for i in 600:
		await get_tree().process_frame
		w = get_tree().current_scene
		if w != null and w.get("built") == true:
			break
	if w == null or w.get("built") != true:
		printerr("MAPSUMMARY mundo não montou")
		get_tree().quit(1)
		return
	var lines := WorldSummary.collect(w)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("MAPSUMMARY %d linhas em %s" % [lines.size(), path])
	get_tree().quit(0)
