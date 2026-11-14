extends Node
## Estilo toon no cenário: toda malha que entra na cena (prop, construção, árvore, MultiMesh de
## vegetação) troca os materiais iluminados por sombra em dois tons, sem contorno. Os personagens
## continuam chamando ToonLook.apply por conta própria, porque levam contorno.
## A conversão acontece no quadro seguinte ao da entrada na cena, para pegar materiais que o código
## atribui logo depois do add_child. Guia: docs/ESTILO_TOON.md.

var _pending: Array[Node] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not ToonLook.enabled():
		set_process(false)
		return
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(n: Node) -> void:
	if n is MeshInstance3D or n is MultiMeshInstance3D:
		_pending.append(n)


func _process(_delta: float) -> void:
	if _pending.is_empty():
		return
	var batch := _pending
	_pending = []
	for n in batch:
		if not is_instance_valid(n) or not n.is_inside_tree():
			continue
		if n is MeshInstance3D:
			ToonLook.convert_mesh(n, true)
		else:
			ToonLook.convert_multimesh(n)
