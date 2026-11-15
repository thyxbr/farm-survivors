class_name ToonLook
extends RefCounted
## Estilo "desenhado" dos personagens: troca os materiais de um modelo por sombra em dois tons e
## acrescenta contorno. Não mexe nos GLBs: lê a cor de cada StandardMaterial3D e monta um ShaderMaterial
## equivalente. Ligado por padrão; `-- --notoon` volta ao sombreado antigo (comparação e depuração).
## Sem dependência de autoload, para que as ferramentas de foto usem o mesmo caminho do jogo.
## Guia completo: docs/ESTILO_TOON.md.

const TOON := preload("res://assets/shaders/toon_character.gdshader")
const OUTLINE := preload("res://assets/shaders/toon_outline.gdshader")
const SLIME := preload("res://assets/shaders/toon_slime.gdshader")
const SLIME_OUTLINE := preload("res://assets/shaders/toon_slime_outline.gdshader")
const MIN_OUTLINE_SIZE := 0.07
const OUTLINE_RANGE := 36.0          # metros da câmera; além disso a casca não é desenhada
const OUTLINE_RANGE_MARGIN := 4.0    # folga para não piscar na fronteira
const OUTLINE_GROUP := "toon_outline"
const SETTINGS_PATH := "user://settings.cfg"     # o mesmo arquivo de Game.settings
const LIVE := &"toon_live"     # meta no material original: o toon exclusivo dele (ver sync)
const SLIME_GOO := Color(0.25, 0.85, 0.3, 0.78)      # slime comum; as variantes trazem `goo` nos dados

const SLIME_FACE := {"EyeL": Vector3(0.012, 0, 0.05), "EyeR": Vector3(-0.012, 0, 0.05),
	"PupilL": Vector3(0.012, 0, 0.05), "PupilR": Vector3(-0.012, 0, 0.05), "Shine": Vector3(0, 0.02, 0)}

static var _mats := {}          # chave das propriedades do material -> ShaderMaterial toon
static var _hulls := {}         # malha original -> ArrayMesh da casca
static var _merged := {}        # hash das peças de um grupo -> ArrayMesh com as cascas juntas
static var _outline_mat: ShaderMaterial
static var _enabled := -1       # -1 = ainda não leu os argumentos nem a opção do menu
static var _outline := -1
## Contadores para a sonda de desempenho (tools/toon_probe.gd, `-- --toonprobe`).
static var stats := {"apply": 0, "apply_usec": 0, "apply_max_usec": 0, "hulls": 0, "hull_usec": 0, "outlines": 0}
static var _slime_mats := {}    # cor da gelatina -> ShaderMaterial
static var _slime_outline_mat: ShaderMaterial


## Desligado com `-- --notoon`, pela opção "Estilo desenhado" do menu e no servidor dedicado (sem janela e
## sem ser um dos testes), que não desenha nada e só gastaria memória com materiais e cascas.
## A linha de comando vence a opção; os testes ignoram a opção (rodam sempre com o estilo).
static func enabled() -> bool:
	if _enabled < 0:
		_enabled = 1 if decide_style(OS.get_cmdline_user_args(), DisplayServer.get_name() == "headless", _setting("toon")) else 0
	return _enabled == 1


## Contorno dos personagens: desligado com `-- --nooutline` ou pela opção "Contorno" do menu.
static func outline_enabled() -> bool:
	if _outline < 0:
		_outline = 1 if decide_outline(OS.get_cmdline_user_args(), _setting("toon_outline")) else 0
	return _outline == 1


## Regra pura (testada em tests/unit/test_toon_look.gd): a linha de comando vence a opção do menu, os
## testes ignoram a opção, e sem janela só os testes ligam o estilo.
static func decide_style(args: PackedStringArray, headless: bool, setting: bool) -> bool:
	if "--notoon" in args:
		return false
	if is_test(args):
		return true
	return setting and not headless


static func decide_outline(args: PackedStringArray, setting: bool) -> bool:
	if "--nooutline" in args:
		return false
	return setting or is_test(args)


static func is_test(args: PackedStringArray) -> bool:
	return "--smoketest" in args or "--colonytest" in args or "--hubtest" in args


## Verdadeiro quando a linha de comando decide (`--notoon` / `--nooutline`) e a opção do menu não vale.
static func forced_off(outline := false) -> bool:
	return ("--nooutline" if outline else "--notoon") in OS.get_cmdline_user_args()


## O menu de opções gravou o settings.cfg: lê de novo. Vale para o que for criado dali em diante
## (a cena já montada fica como está até ser recarregada).
static func reload_settings() -> void:
	_enabled = -1
	_outline = -1
	# contornos que já existem: desligar a opção esconde na hora, ligar de novo mostra
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		var show := enabled() and outline_enabled()
		for o in tree.get_nodes_in_group(OUTLINE_GROUP):
			(o as Node3D).visible = show


## Lê direto do arquivo de Game.settings (este script não pode depender de autoload).
static func _setting(key: String) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return true
	return bool(cfg.get_value("settings", key, true))


## Verdadeiro para um material montado por ToonLook (o clima trata esse material como liso comum).
static func is_toon(m: Material) -> bool:
	return m is ShaderMaterial and (m as ShaderMaterial).shader == TOON


## Personagens: aplica em todas as malhas abaixo de `root`, com contorno. Devolve quantas superfícies
## foram convertidas. Pode ser chamada de novo no mesmo modelo (troca de equipamento).
## `merge` junta numa casca só as peças irmãs (mesmo nó pai): o goblin cai de 59 cascas para 7. Só serve
## para modelos cujas peças não mudam depois (o código anima e esconde os grupos, nunca uma peça sozinha):
## inimigos sim; cavaleiro não, porque o equipamento troca peça por peça.
static func apply(root: Node, outline := true, merge := false) -> int:
	var t0 := Time.get_ticks_usec()
	var n := 0
	outline = outline and outline_enabled()
	var groups := {}        # nó pai -> peças que levam contorno
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.name.begins_with("ToonOutline") or mi.mesh == null:
			continue
		var c := convert_mesh(mi, false)
		n += c
		# peças miúdas (olhos, sobrancelhas, rebites) ficam sem contorno: a casca engoliria a peça
		if (c > 0 or mi.has_meta("toon")) and outline and not mi.has_meta("toon_outline") 				and mi.get_aabb().get_longest_axis_size() >= MIN_OUTLINE_SIZE:
			mi.set_meta("toon_outline", true)
			if merge and mi.skin == null:
				var p := mi.get_parent()
				if not groups.has(p):
					groups[p] = []
				groups[p].append(mi)
			else:
				_add_outline(mi)
	for p in groups:
		_add_group_outline(p, groups[p])
	var dt := Time.get_ticks_usec() - t0
	stats.apply += 1
	stats.apply_usec += dt
	stats.apply_max_usec = maxi(stats.apply_max_usec, dt)
	return n


## Slime: corpo e base (`BodyMesh`, `Base`) viram gelatina em dois tons, translúcida e com contorno só
## na silhueta. Olhos e brilho são opacos e seguem por `apply`, chamada em seguida por quem monta o modelo.
static func apply_slime(root: Node, goo := SLIME_GOO) -> void:
	var key := goo.to_html()
	var m: ShaderMaterial = _slime_mats.get(key)
	if m == null:
		m = ShaderMaterial.new()
		m.shader = SLIME
		m.set_shader_parameter("albedo", goo)
		_slime_mats[key] = m
	if _slime_outline_mat == null:
		_slime_outline_mat = ShaderMaterial.new()
		_slime_outline_mat.shader = SLIME_OUTLINE
		_slime_outline_mat.render_priority = 1      # depois do corpo, que grava profundidade
	for n in ["BodyMesh", "Base"]:
		var mi := root.find_child(n, true, false) as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		mi.material_override = m
		mi.set_meta("toon", true)
		if outline_enabled() and not mi.has_meta("toon_outline"):
			mi.set_meta("toon_outline", true)
			_add_outline(mi, _slime_outline_mat)
	# olhos e brilho nascem meio afundados na gelatina; com contorno, a parte de dentro saía riscada e
	# esverdeada. Aqui eles vêm para fora da superfície (só no toon: sem ele o modelo fica como no GLB).
	for n in SLIME_FACE:
		var part := root.find_child(n, true, false) as Node3D
		if part != null and not part.has_meta("toon_slime_face"):
			part.set_meta("toon_slime_face", true)
			part.position += SLIME_FACE[n]


## Material que o código continua alterando depois de criado (terra do canteiro que escurece ao regar,
## caldo do caldeirão que pulsa): ganha um material toon só dele, em vez do compartilhado do cache, e
## esta função copia cor e emissão de `src` para ele. Chame ao criar o material e depois de cada mudança.
static func sync(src: BaseMaterial3D) -> void:
	if not enabled() or not _convertible(src):
		return
	var m: ShaderMaterial = src.get_meta(LIVE) if src.has_meta(LIVE) else null
	if m == null:
		m = ShaderMaterial.new()
		m.shader = TOON
		src.set_meta(LIVE, m)
	_fill(m, src)


## Troca os materiais iluminados de uma malha por toon, mantendo a emissão. O parâmetro `scenery` ficou
## só por compatibilidade: cenário e personagem convertem os mesmos materiais.
static func convert_mesh(mi: MeshInstance3D, _scenery := false) -> int:
	if mi.mesh == null or mi.name.begins_with("ToonOutline"):
		return 0
	var n := 0
	# material_override (tintura das placas do cavaleiro, peças montadas por código) vence os por superfície
	var over := mi.material_override as BaseMaterial3D
	if over != null and _convertible(over):
		mi.material_override = _toon_of(over)
		n += 1
	for s in mi.mesh.get_surface_count():
		var cur := mi.get_surface_override_material(s)
		var src := (cur if cur != null else mi.mesh.surface_get_material(s)) as BaseMaterial3D
		if src == null or not _convertible(src):
			continue
		mi.set_surface_override_material(s, _toon_of(src))
		n += 1
	if n > 0:
		mi.set_meta("toon", true)
	return n


## MultiMesh (vegetação, plantações): não há material por superfície na instância, então o material toon
## entra na própria malha (compartilhada). A cor por instância continua valendo.
static func convert_multimesh(mmi: MultiMeshInstance3D) -> int:
	var n := 0
	var over := mmi.material_override as BaseMaterial3D
	if over != null and _convertible(over):
		mmi.material_override = _toon_of(over)
		n += 1
	var mesh := mmi.multimesh.mesh if mmi.multimesh else null
	if mesh == null:
		return n
	for s in mesh.get_surface_count():
		var src := mesh.surface_get_material(s) as BaseMaterial3D
		if src == null or not _convertible(src):
			continue
		mesh.surface_set_material(s, _toon_of(src))
		n += 1
	return n


## Conferência: lista as peças visíveis abaixo de `root` que ainda usam material iluminado comum, ou
## seja, que o estilo deveria ter convertido e não converteu (material trocado depois do gancho).
static func audit(root: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		if not (n is MeshInstance3D or n is MultiMeshInstance3D) or not (n as Node3D).is_visible_in_tree():
			continue
		var mesh: Mesh = n.mesh if n is MeshInstance3D else (n.multimesh.mesh if n.multimesh else null)
		if mesh == null or n.name.begins_with("ToonOutline"):
			continue
		var over := (n as GeometryInstance3D).material_override
		var left := PackedStringArray()
		if over != null:
			if over is BaseMaterial3D and _convertible(over):
				left.append("override " + (over as BaseMaterial3D).albedo_color.to_html(false))
		else:
			for s in mesh.get_surface_count():
				var cur: Material = n.get_surface_override_material(s) if n is MeshInstance3D else null
				var m := (cur if cur != null else mesh.surface_get_material(s)) as BaseMaterial3D
				if m != null and _convertible(m):
					left.append("sup. %d %s" % [s, m.albedo_color.to_html(false)])
		if not left.is_empty():
			out.append("%s  [%s]" % [root.get_path_to(n), ", ".join(left)])
	return out


static func _convertible(src: BaseMaterial3D) -> bool:
	return src.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED 		and src.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED


static func _toon_of(src: BaseMaterial3D) -> ShaderMaterial:
	if src.has_meta(LIVE):       # material que o código anima: toon exclusivo, mantido por sync()
		return src.get_meta(LIVE)
	var tex := src.albedo_texture
	var key := "%s|%.2f|%s|%.2f|%d|%d|%d" % [src.albedo_color.to_html(), src.metallic,
		src.emission.to_html() if src.emission_enabled else "-", src.emission_energy_multiplier,
		int(src.vertex_color_use_as_albedo), int(src.vertex_color_is_srgb), tex.get_instance_id() if tex else 0]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = TOON
	_fill(m, src)
	_mats[key] = m
	return m


static func _fill(m: ShaderMaterial, src: BaseMaterial3D) -> void:
	# metal no PBR reflete o céu e sai mais escuro que o albedo; aceso por inteiro ficaria quase branco
	# (vale também para o metal fosco das malhas e cotas, com metallic em torno de 0.5)
	m.set_shader_parameter("albedo", src.albedo_color.darkened(0.35 * clampf(src.metallic, 0.0, 1.0)))
	m.set_shader_parameter("gloss", 0.9 if src.metallic > 0.55 else 0.0)
	m.set_shader_parameter("use_vertex_color", src.vertex_color_use_as_albedo)
	m.set_shader_parameter("vertex_color_srgb", src.vertex_color_is_srgb)
	m.set_shader_parameter("albedo_tex", src.albedo_texture)
	m.set_shader_parameter("emission", src.emission if src.emission_enabled else Color.BLACK)
	m.set_shader_parameter("emission_energy", src.emission_energy_multiplier if src.emission_enabled else 0.0)


static func _add_outline(mi: MeshInstance3D, mat: ShaderMaterial = null) -> void:
	var hull := _hull_of(mi.mesh)
	if hull == null:
		return
	var o := _outline_node(hull, mi.layers)
	if mat != null:
		o.material_override = mat
	if mi.skin != null:
		# malha com esqueleto: a casca fica ao lado, presa ao mesmo esqueleto
		o.skin = mi.skin
		o.transform = mi.transform
		mi.get_parent().add_child(o)
		o.skeleton = o.get_path_to(mi.get_node(mi.skeleton)) if mi.has_node(mi.skeleton) else mi.skeleton
	else:
		mi.add_child(o)      # filha: herda transformação e visibilidade da peça


## Uma casca só para várias peças irmãs, filha do nó pai delas (herda a animação e a visibilidade do grupo).
static func _add_group_outline(parent: Node, pieces: Array) -> void:
	if pieces.size() == 1:
		_add_outline(pieces[0])
		return
	var hull := _merged_hull(pieces)
	if hull != null:
		parent.add_child(_outline_node(hull, (pieces[0] as MeshInstance3D).layers))


static func _outline_node(hull: ArrayMesh, layers: int) -> MeshInstance3D:
	if _outline_mat == null:
		_outline_mat = ShaderMaterial.new()
		_outline_mat.shader = OUTLINE
	var o := MeshInstance3D.new()
	o.name = "ToonOutline"
	o.mesh = hull
	o.material_override = _outline_mat
	o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	o.layers = layers
	# de longe o traço tem menos de meio pixel: a casca nem é desenhada
	o.visibility_range_end = OUTLINE_RANGE
	o.visibility_range_end_margin = OUTLINE_RANGE_MARGIN
	o.add_to_group(OUTLINE_GROUP)
	stats.outlines += 1
	return o


## Cascas de várias peças numa malha só, cada uma na posição da peça (espaço do nó pai). A chave é a
## lista de malhas e transformações: todos os goblins compartilham as mesmas 7 cascas.
static func _merged_hull(pieces: Array) -> ArrayMesh:
	var key_parts := []
	for mi: MeshInstance3D in pieces:
		key_parts.append(mi.mesh.get_instance_id())
		key_parts.append(mi.transform)
	var key := key_parts.hash()
	if _merged.has(key):
		return _merged[key]
	var t0 := Time.get_ticks_usec()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for mi: MeshInstance3D in pieces:
		var hull := _hull_of(mi.mesh)
		if hull == null:
			continue
		var xf := mi.transform
		var nb := xf.basis.inverse().transposed()      # normais: inversa transposta (escala não uniforme)
		var plain := xf.is_equal_approx(Transform3D.IDENTITY)
		for s in hull.get_surface_count():
			var arr := hull.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var base := verts.size()
			if plain:
				verts.append_array(v)
				norms.append_array(nn)
			else:
				for i in v.size():
					verts.append(xf * v[i])
					norms.append((nb * nn[i]).normalized())
			if arr[Mesh.ARRAY_INDEX] != null:
				for i in (arr[Mesh.ARRAY_INDEX] as PackedInt32Array):
					idx.append(base + i)
			else:
				for i in v.size():
					idx.append(base + i)
	var out: ArrayMesh = null
	if not verts.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_INDEX] = idx
		out = ArrayMesh.new()
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_merged[key] = out
	stats.hulls += 1
	stats.hull_usec += Time.get_ticks_usec() - t0
	return out


## Cópia da malha só com posição, ossos e uma normal por posição (média das faces vizinhas).
static func _hull_of(mesh: Mesh) -> ArrayMesh:
	if _hulls.has(mesh):
		return _hulls[mesh]
	var t0 := Time.get_ticks_usec()
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
	stats.hulls += 1
	stats.hull_usec += Time.get_ticks_usec() - t0
	return hull
