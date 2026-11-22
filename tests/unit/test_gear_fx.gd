extends RefCounted
## GearFx: a tabela de texturas animadas tem que bater com os GLBs (o efeito é escolhido pelo nome do
## material; um material renomeado no Blender deixaria a peça sem efeito, em silêncio).

const ENDGAME := ["lich", "hierophant", "reaper", "raven", "dragon", "astral", "frost", "celestial", "void", "blackdragon", "cosmic"]
## armaduras com efeito só no material, sem partículas nem cabeça própria (o brilho do ouro do paladino)
const FX_ONLY := ["a_paladin", "a_emberscale"]
const DIR := "res://assets/models/gear/"


## Nomes de material por estilo ("a_reaper" -> {nome: true}).
func _materials(style: String) -> Dictionary:
	var out := {}
	var scene := load(DIR + style + ".glb") as PackedScene
	if scene == null:
		return out
	var root := scene.instantiate()
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m != null:
				out[m.resource_name] = true
	root.free()
	return out


func test_every_surface_entry_exists_in_a_model() -> void:
	var all := {}
	for k in ENDGAME:
		all.merge(_materials("h_" + k))
		all.merge(_materials("a_" + k))
	for st in FX_ONLY:
		all.merge(_materials(st))
	for name in GearFx.SURFACES:
		T.ok(all.has(name), "material '%s' da tabela não existe em nenhum GLB com efeito" % name)


func test_every_endgame_set_is_animated() -> void:
	for k in ENDGAME:
		for pre in ["h_", "a_"]:
			var hit := 0
			for name in _materials(pre + k):
				if GearFx.SURFACES.has(name):
					hit += 1
			T.ok(hit > 0, "%s%s não tem nenhuma superfície animada" % [pre, k])
		T.ok(GearFx.PARTICLES.has("a_" + k), "a_%s sem partículas" % k)


func test_tinted_and_shared_materials_stay_out() -> void:
	# t1_/t2_/tp_ recebem a cor do item e g_ é pele/cabelo de todo equipamento: não podem virar efeito
	for name in GearFx.SURFACES:
		var n := str(name)
		T.ok(not (n.begins_with("t1") or n.begins_with("t2") or n.begins_with("tp_") or n.begins_with("g_")),
			"'%s' é material tingido ou comum" % n)


func test_galaxy_uv_is_baked_in_the_models() -> void:
	# a galáxia é desenhada a partir do UV (tools/blender/gear.py, g_galaxy_uv): sem ele, não aparece
	for pair in [["a_reaper", "rb_reaper_cloth"], ["h_reaper", "eg_reaper_space_gem_flat"],
			["a_celestial", "cs_sky"], ["a_celestial", "cs_void_flat"], ["a_cosmic", "cz_sky"]]:
		var root := (load(DIR + pair[0] + ".glb") as PackedScene).instantiate()
		var with_uv := 0
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			for s in mi.mesh.get_surface_count():
				if mi.mesh.surface_get_material(s).resource_name != pair[1]:
					continue
				var uv = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_TEX_UV]
				if uv != null:
					for p: Vector2 in uv:
						if p.x > 0.02:
							with_uv += 1
							break
		root.free()
		T.ok(with_uv > 0, "%s: nenhuma face de %s com UV de galáxia" % pair)


func test_material_is_shared_and_keeps_glb_colors() -> void:
	var src := StandardMaterial3D.new()
	src.resource_name = "eg_lich_glow_gem_flat"
	src.albedo_color = Color(0.2, 0.4, 0.6)
	src.emission_enabled = true
	src.emission = Color(0.1, 0.9, 0.3)
	src.emission_energy_multiplier = 2.0
	var a := GearFx.material_for(src)
	T.ok(a == GearFx.material_for(src), "um material por nome (cache)")
	T.eq(a.shader, GearFx.GLOW, "shader da tabela")
	T.eq(a.get_shader_parameter("emission"), src.emission, "cor da luz vem do GLB")
	T.eq(a.get_shader_parameter("energy"), 2.0, "força da luz vem do GLB")
