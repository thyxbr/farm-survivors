extends Node
## Estilo toon no cenário: toda malha que entra na cena (prop, construção, árvore, MultiMesh de
## vegetação) troca os materiais iluminados por sombra em dois tons, sem contorno. Os personagens
## continuam chamando ToonLook.apply por conta própria, porque levam contorno.
## A conversão acontece no quadro seguinte ao da entrada na cena, para pegar materiais que o código
## atribui logo depois do add_child. Guia: docs/ESTILO_TOON.md.
## `-- --toonprobe[=SEG]` liga a sonda de desempenho (tools/toon_probe.gd).

var _pending: Array[Node] = []
## Contadores para a sonda: malhas vistas e convertidas, tempo total e o pior quadro.
var stats := {"seen": 0, "converted": 0, "usec": 0, "max_frame_usec": 0, "max_batch": 0}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--toonprobe"):
			add_child(load("res://tools/toon_probe.gd").new())
	if DisplayServer.get_name() == "headless" and not ToonLook.enabled():
		set_process(false)      # servidor dedicado: nunca liga
		return
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(n: Node) -> void:
	# a opção do menu pode ligar e desligar o estilo durante o jogo: confere a cada malha
	if (n is MeshInstance3D or n is MultiMeshInstance3D) and ToonLook.enabled():
		_pending.append(n)


func _process(_delta: float) -> void:
	if _pending.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	var batch := _pending
	_pending = []
	for n in batch:
		if not is_instance_valid(n) or not n.is_inside_tree():
			continue
		var c := 0
		if n is MeshInstance3D:
			c = ToonLook.convert_mesh(n, true)
		else:
			c = ToonLook.convert_multimesh(n)
		if c > 0:
			stats.converted += 1
	var dt := Time.get_ticks_usec() - t0
	stats.seen += batch.size()
	stats.usec += dt
	stats.max_frame_usec = maxi(stats.max_frame_usec, dt)
	stats.max_batch = maxi(stats.max_batch, batch.size())
