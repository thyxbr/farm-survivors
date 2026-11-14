class_name ToonLook
extends RefCounted
## Estilo "desenhado" dos personagens: troca os materiais de um modelo por sombra em dois tons e
## acrescenta contorno. Não mexe nos GLBs: lê a cor de cada StandardMaterial3D e monta um ShaderMaterial
## equivalente. Ligado por padrão; `-- --notoon` volta ao sombreado antigo (comparação e depuração).
## Sem dependência de autoload, para que as ferramentas de foto usem o mesmo caminho do jogo.
## Guia completo: docs/ESTILO_TOON.md.

const TOON := preload("res://assets/shaders/toon_character.gdshader")
const OUTLINE := preload("res://assets/shaders/toon_outline.gdshader")
const MIN_OUTLINE_SIZE := 0.07

static var _mats := {}          # chave das propriedades do material -> ShaderMaterial toon
static var _hulls := {}         # malha original -> ArrayMesh da casca
static var _outline_mat: ShaderMaterial
static var _enabled := -1       # -1 = ainda não leu os argumentos


static func enabled() -> bool:
	if _enabled < 0:
		_enabled = 0 if "--notoon" in OS.get_cmdline_user_args() else 1
	return _enabled == 1


## Aplica em todas as malhas abaixo de `root`. Devolve quantas superfícies foram convertidas.
## Pode ser chamada de novo no mesmo modelo (troca de equipamento): só converte o que ainda não é toon.
static func apply(root: Node, outline := true) -> int:
	var n := 0
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.name.begins_with("ToonOutline") or mi.mesh == null:
			continue
		var any := false
		# material_override (tintura das placas do cavaleiro) vence os materiais por superfície
		var over := mi.material_override as BaseMaterial3D
		if over != null and _convertible(over):
			mi.material_override = _toon_of(over)
			any = true
			n += 1
		for s in mi.mesh.get_surface_count():
			var src := mi.get_surface_override_material(s) as BaseMaterial3D
			if src == null and mi.get_surface_override_material(s) == null:
				src = mi.mesh.surface_get_material(s) as BaseMaterial3D
			if src == null or not _convertible(src):
				continue
			mi.set_surface_override_material(s, _toon_of(src))
			any = true
			n += 1
		# peças miúdas (olhos, sobrancelhas, rebites) ficam sem contorno: a casca engoliria a peça
		if any and outline and not mi.has_meta("toon_outline") 				and mi.get_aabb().get_longest_axis_size() >= MIN_OUTLINE_SIZE:
			mi.set_meta("toon_outline", true)
			_add_outline(mi)
	return n


static func _convertible(src: BaseMaterial3D) -> bool:
	return src.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED 		and src.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED


static func _toon_of(src: BaseMaterial3D) -> ShaderMaterial:
	var tex := src.albedo_texture
	var key := "%s|%.2f|%s|%.2f|%d|%d|%d" % [src.albedo_color.to_html(), src.metallic,
		src.emission.to_html() if src.emission_enabled else "-", src.emission_energy_multiplier,
		int(src.vertex_color_use_as_albedo), int(src.vertex_color_is_srgb), tex.get_instance_id() if tex else 0]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = TOON
	# metal no PBR reflete o céu e sai mais escuro que o albedo; aceso por inteiro ficaria quase branco
	# (vale também para o metal fosco das malhas e cotas, com metallic em torno de 0.5)
	m.set_shader_parameter("albedo", src.albedo_color.darkened(0.35 * clampf(src.metallic, 0.0, 1.0)))
	m.set_shader_parameter("gloss", 0.9 if src.metallic > 0.55 else 0.0)
	m.set_shader_parameter("use_vertex_color", src.vertex_color_use_as_albedo)
	m.set_shader_parameter("vertex_color_srgb", src.vertex_color_is_srgb)
	if tex:
		m.set_shader_parameter("albedo_tex", tex)
	if src.emission_enabled:
		m.set_shader_parameter("emission", src.emission)
		m.set_shader_parameter("emission_energy", src.emission_energy_multiplier)
	_mats[key] = m
	return m


static func _add_outline(mi: MeshInstance3D) -> void:
	var hull := _hull_of(mi.mesh)
	if hull == null:
		return
	if _outline_mat == null:
		_outline_mat = ShaderMaterial.new()
		_outline_mat.shader = OUTLINE
	var o := MeshInstance3D.new()
	o.name = "ToonOutline"
	o.mesh = hull
	o.material_override = _outline_mat
	o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	o.layers = mi.layers
	if mi.skin != null:
		# malha com esqueleto: a casca fica ao lado, presa ao mesmo esqueleto
		o.skin = mi.skin
		o.transform = mi.transform
		mi.get_parent().add_child(o)
		o.skeleton = o.get_path_to(mi.get_node(mi.skeleton)) if mi.has_node(mi.skeleton) else mi.skeleton
	else:
		mi.add_child(o)      # filha: herda transformação e visibilidade da peça


## Cópia da malha só com posição, ossos e uma normal por posição (média das faces vizinhas).
static func _hull_of(mesh: Mesh) -> ArrayMesh:
	if _hulls.has(mesh):
		return _hulls[mesh]
	var sums := {}
	var surfaces := []
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms = arr[Mesh.ARRAY_NORMAL]
		if norms == null or verts.is_empty():
			continue
		for i in verts.size():
			var k := Vector3i((verts[i] * 4000.0).round())
			sums[k] = sums.get(k, Vector3.ZERO) + (norms[i] as Vector3)
		surfaces.append([s, arr])
	if surfaces.is_empty():
		_hulls[mesh] = null
		return null
	var hull := ArrayMesh.new()
	for pair in surfaces:
		var s: int = pair[0]
		var arr: Array = pair[1]
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var smooth := PackedVector3Array()
		smooth.resize(verts.size())
		for i in verts.size():
			var v: Vector3 = sums[Vector3i((verts[i] * 4000.0).round())]
			smooth[i] = v.normalized() if v.length_squared() > 1e-8 else (arr[Mesh.ARRAY_NORMAL][i] as Vector3)
		var out := []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = verts
		out[Mesh.ARRAY_NORMAL] = smooth
		out[Mesh.ARRAY_INDEX] = arr[Mesh.ARRAY_INDEX]
		out[Mesh.ARRAY_BONES] = arr[Mesh.ARRAY_BONES]
		out[Mesh.ARRAY_WEIGHTS] = arr[Mesh.ARRAY_WEIGHTS]
		var flags := 0
		if mesh is ArrayMesh:
			flags = (mesh as ArrayMesh).surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		hull.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out, [], {}, flags)
	_hulls[mesh] = hull
	return hull
