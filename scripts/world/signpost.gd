extends RefCounted
## Poste de direção (assets/models/signpost.glb, tools/blender/props.py build_signpost): até 4 setas
## ("Arrow0".."Arrow3", origem no eixo do poste, apontando para +X). make() vira cada seta para o seu
## destino e escreve o nome nela (dos dois lados); setas que sobram ficam escondidas.

const MODEL := preload("res://assets/models/signpost.glb")
const INK := Color(0.2, 0.12, 0.05)


## dests = [[texto, alvo (Vector3, no mundo)], ...]; pos = pé do poste no mundo. Devolve o nó (sem pai).
static func make(pos: Vector3, dests: Array) -> Node3D:
	var root: Node3D = MODEL.instantiate()
	root.position = pos
	for i in 4:
		var arrow := root.find_child("Arrow%d" % i, true, false) as Node3D
		if arrow == null:
			continue
		if i >= dests.size():
			arrow.visible = false
			continue
		var to: Vector3 = dests[i][1] - pos
		arrow.rotation.y = atan2(-to.z, to.x)
		for side in [1.0, -1.0]:
			var label := Label3D.new()
			label.text = str(dests[i][0])
			label.font_size = 40
			label.pixel_size = 0.004
			label.outline_size = 0
			label.modulate = INK
			label.double_sided = false
			label.position = Vector3(0.58, 0.0, 0.036 * side)
			if side < 0.0:
				label.rotation.y = PI
			arrow.add_child(label)
	return root
