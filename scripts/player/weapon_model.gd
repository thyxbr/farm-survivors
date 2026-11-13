class_name WeaponModel
extends RefCounted
## Ajustes nos GLBs de arma (assets/models/w_*.glb) ao instanciar. Sem dependência de autoload,
## para que tools/weapon_shot.gd use exatamente o mesmo caminho do jogo.


## Armas pintadas por vértice no Blender (atributo "Col" -> COLOR_0): o importador glTF do Godot traz
## a cor do vértice mas não liga "usar como albedo", e a arma sairia branca. COLOR_0 é linear (glTF),
## então vertex_color_is_srgb fica falso. Altera o material importado (compartilhado), uma vez só.
static func use_vertex_color(root: Node) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi.mesh
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s) as BaseMaterial3D
			if mat and (m.surface_get_format(s) & Mesh.ARRAY_FORMAT_COLOR) != 0:
				mat.vertex_color_use_as_albedo = true
