class_name WeaponModel
extends RefCounted
## Ajustes nos GLBs de arma (assets/models/w_*.glb) ao instanciar. Sem dependência de autoload,
## para que tools/weapon_shot.gd use exatamente o mesmo caminho do jogo.


## Armas pintadas por vértice no Blender (atributo "Col" -> COLOR_0): o importador glTF do Godot traz
## a cor do vértice mas não liga "usar como albedo", e a arma sairia branca. COLOR_0 é linear (glTF),
## então vertex_color_is_srgb fica falso. Altera o material importado (compartilhado), uma vez só.
const TOOL_GLOW := 0.35
const RUNE_SHADER := preload("res://shaders/mythic_rune.gdshader")
static var _runes := {}   # nome do material "bw_*_rune" -> ShaderMaterial (um por arco, compartilhado)


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
			# runas e veios dos arcos míticos (bw_*_rune): pulsos de energia correndo para as pontas
			if mat and mat.resource_name.begins_with("bw_") and mat.resource_name.contains("_rune"):
				mi.set_surface_override_material(s, rune_material(mat))
				continue
			var glow_part := mat != null and (mat.resource_name.begins_with("tl_") or mat.resource_name.begins_with("bw_"))
			if glow_part and mat.resource_name.contains("_gem") and mat.emission_enabled:
				mat.vertex_color_use_as_albedo = false
				var c := mat.emission
				mat.albedo_color = Color(minf(c.r * 1.7, 1.0), minf(c.g * 1.7, 1.0), minf(c.b * 1.7, 1.0))
				mat.emission_energy_multiplier = TOOL_GLOW


## Material animado das runas a partir do material importado (a cor de emissão do Blender vira a cor da runa).
static func rune_material(mat: BaseMaterial3D) -> ShaderMaterial:
	var key := mat.resource_name
	if _runes.has(key):
		return _runes[key]
	var sm := ShaderMaterial.new()
	sm.shader = RUNE_SHADER
	var c := mat.emission if mat.emission_enabled else mat.albedo_color
	sm.set_shader_parameter("base_color", Color(minf(c.r * 1.5, 1.0), minf(c.g * 1.5, 1.0), minf(c.b * 1.5, 1.0)))
	sm.set_shader_parameter("hot_color", c.lerp(Color.WHITE, 0.6))
	_runes[key] = sm
	return sm
