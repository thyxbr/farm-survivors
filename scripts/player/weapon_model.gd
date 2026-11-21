class_name WeaponModel
extends RefCounted
## Ajustes nos GLBs de arma (assets/models/w_*.glb) ao instanciar. Sem dependência de autoload,
## para que tools/weapon_shot.gd use exatamente o mesmo caminho do jogo.


## Armas pintadas por vértice no Blender (atributo "Col" -> COLOR_0): o importador glTF do Godot traz
## a cor do vértice mas não liga "usar como albedo", e a arma sairia branca. COLOR_0 é linear (glTF),
## então vertex_color_is_srgb fica falso. Altera o material importado (compartilhado), uma vez só.
const TOOL_GLOW := 0.35


static func use_vertex_color(root: Node) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi.mesh as ArrayMesh      # malhas primitivas montadas por código não têm cor por vértice
		if m == null:
			continue
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s) as BaseMaterial3D
			if mat and (m.surface_get_format(s) & Mesh.ARRAY_FORMAT_COLOR) != 0:
				mat.vertex_color_use_as_albedo = true
			# gemas, runas e gumes das ferramentas de coleta (tl_*) e dos arcos (bw_*_gem): a cor por vértice dessa
			# superfície chega branca no GLB e a emissão 1,0 estoura para branco no ACES. A cor de brilho vira o albedo
			# e a emissão baixa, para o roxo do cristal e o ouro do astral aparecerem e ainda brilharem.
			var glow_part := mat != null and (mat.resource_name.begins_with("tl_") or mat.resource_name.begins_with("bw_"))
			if glow_part and mat.resource_name.contains("_gem") and mat.emission_enabled:
				mat.vertex_color_use_as_albedo = false
				var c := mat.emission
				mat.albedo_color = Color(minf(c.r * 1.7, 1.0), minf(c.g * 1.7, 1.0), minf(c.b * 1.7, 1.0))
				mat.emission_energy_multiplier = TOOL_GLOW
