class_name KnightLook
extends RefCounted
## Visual do cavaleiro conforme o equipamento: monta as armas (espada, cajado, arco) por código,
## pinta elmo/peitoral/manoplas/botas e mostra escudo, orbe ou aljava. Usado pelo jogador,
## pelas réplicas do multiplayer e pela prévia 3D do inventário.

## Peças do modelo knight.glb tingidas por cada espaço de equipamento (estilo "plate").
const PARTS := {
	"head": ["Helmet", "HelmetDome"],
	"armor": ["Torso", "Fauld", "ArmL_Pauldron", "ArmR_Pauldron"],
	"hands": ["ArmL_Gauntlet", "ArmR_Gauntlet", "ArmL_Hand", "ArmR_Hand"],
	"feet": ["LegL_Sabaton", "LegR_Sabaton"],
}
## Todas as peças do knight.glb de cada espaço: somem quando o estilo do item vem de um GLB de equipamento.
const REGION := {
	"head": ["Helmet", "HelmetDome", "VisorSlit", "HelmetTrim", "Plume"],
	"armor": ["Hips", "Torso", "Fauld", "Belt", "Tabard", "Gorget", "ArmL_Pauldron", "ArmR_Pauldron",
		"ArmL_Upper", "ArmR_Upper", "ArmL_Vambrace", "ArmR_Vambrace", "LegL_Thigh", "LegR_Thigh"],
	"hands": ["ArmL_Gauntlet", "ArmR_Gauntlet", "ArmL_Hand", "ArmR_Hand"],
	"feet": ["LegL_Sabaton", "LegR_Sabaton", "LegL_Knee", "LegR_Knee"],
}
## Estilo de cada espaço vazio: o personagem sem equipamento usa camisa, calça e sapatos.
const DEFAULT_STYLE := {"head": "h_bare", "armor": "a_shirt", "hands": "g_bare", "feet": "f_shoes"}
## Estilo que usa as próprias peças de placas do knight.glb (tingidas por PARTS).
const PLATE := "plate"
## Materiais copiados e tingidos, por material de origem + cor (evita duplicar a cada troca de equipamento).
static var _tint_cache := {}
const SWORD_PARTS := ["Grip", "Blade"]
const SHIELD_PARTS := ["ShieldRim", "Shield"]
## Quanto o suporte da arma "desfaz" a rotação do braço (cajado fica quase de pé, arco fica vertical ao mirar).
const COUNTER := {"sword": 0.0, "staff": 0.75, "bow": 1.0}


## Aplica o visual e devolve referências: {"class", "holder", "tip", "arrow", "arm", "elbow", "counter"}.
## As armas ficam presas no antebraço (ElbowX) para acompanhar a mão quando o cotovelo dobra;
## "arm" e "elbow" são os pivôs que o suporte precisa desfazer (veja COUNTER).
static func apply(model: Node3D, look: Dictionary) -> Dictionary:
	for n in model.get_meta("look_nodes", []):
		if is_instance_valid(n):
			n.free()
	var made: Array = []
	var wid: String = look.get("weapon", "")
	var cls := ItemDB.weapon_class(wid)

	# ---- roupas e armaduras: cada espaço usa as placas do knight.glb ou um GLB de equipamento
	var armor_id: String = look.get("armor", "")
	var pants := Color(0, 0, 0, 0)    # alfa 0 = calça com a cor do GLB
	if armor_id != "":
		pants = ItemDB.get_item(armor_id).get("pants", Color(0.24, 0.22, 0.22))
	for slot in REGION:
		var id: String = look.get(slot, "")
		var style := gear_style(slot, id)
		var plate := style == PLATE
		for pn in REGION[slot]:
			var n := model.find_child(pn, true, false) as Node3D
			if n:
				n.visible = plate
		if plate:
			var mat: Material = _item_mat(id) if id != "" else null
			for pn in PARTS[slot]:
				var mi := model.find_child(pn, true, false) as MeshInstance3D
				if mi:
					mi.material_override = mat
		else:
			_attach_gear(model, style, id, pants, made)
	# capa: só com armadura de placas ou peça que a pede ("cape": true)
	var cape := model.find_child("Cape", true, false) as Node3D
	if cape:
		cape.visible = gear_style("armor", armor_id) == PLATE or ItemDB.get_item(armor_id).get("cape", false)

	# ---- mão secundária
	var off: String = look.get("offhand", "")
	var shield_on: bool = off != "" and ItemDB.get_item(off).get("needs", "") == "sword"
	var shield_mat: Material = null
	if shield_on and off != "knight_shield":
		shield_mat = _item_mat(off)
	for pn in SHIELD_PARTS:
		var mi := model.find_child(pn, true, false) as MeshInstance3D
		if mi:
			mi.visible = shield_on
			if pn == "Shield":
				mi.material_override = shield_mat
	var arm_l := model.find_child("ArmL", true, false) as Node3D
	var arm_r := model.find_child("ArmR", true, false) as Node3D
	var body := model.find_child("Body", true, false) as Node3D
	# antebraços (modelos antigos sem cotovelo: o próprio braço)
	var fore_l := model.find_child("ElbowL", true, false) as Node3D
	var fore_r := model.find_child("ElbowR", true, false) as Node3D
	if fore_l == null:
		fore_l = arm_l
	if fore_r == null:
		fore_r = arm_r
	var hand_l := _point_in(model, fore_l, "ArmL_Hand")
	if off != "" and not shield_on and fore_l:
		var it := ItemDB.get_item(off)
		if it.get("needs", "") == "staff":   # orbe flutuando sobre a mão esquerda
			var orb := Node3D.new()
			orb.name = "Orb"
			orb.position = hand_l + Vector3(0.06, 0.02, 0.12)
			fore_l.add_child(orb)
			made.append(orb)
			orb.add_child(_sphere(0.075, _glow_mat(it.color, 2.5), Vector3.ZERO))
			var lt := OmniLight3D.new()
			lt.light_color = it.color
			lt.light_energy = 0.8
			lt.omni_range = 2.0
			orb.add_child(lt)
		elif it.get("needs", "") == "bow" and body:   # aljava nas costas
			var q := Node3D.new()
			q.position = Vector3(0.1, 0.45, -0.2)
			q.rotation = Vector3(0.25, 0, -0.35)
			body.add_child(q)
			made.append(q)
			q.add_child(_cyl(0.07, 0.06, 0.5, _mat(it.color, false), Vector3.ZERO))
			for i in 4:
				var a := i * TAU / 4.0
				q.add_child(_box(Vector3(0.012, 0.18, 0.012), _mat(Color(0.9, 0.9, 0.85), false),
					Vector3(cos(a) * 0.03, 0.32, sin(a) * 0.03)))

	# ---- arma
	for pn in SWORD_PARTS:
		var mi := model.find_child(pn, true, false) as MeshInstance3D
		if mi:
			mi.visible = false
	var res := {"class": cls, "holder": null, "tip": null, "arrow": null, "arm": null, "elbow": null,
		"counter": COUNTER[cls]}
	if wid != "" and arm_r and arm_l:
		var holder := Node3D.new()
		holder.name = "WeaponHolder"
		if cls == "bow":
			holder.position = hand_l
			fore_l.add_child(holder)
			res.arm = arm_l
			res.elbow = fore_l
		else:
			holder.position = _point_in(model, fore_r, "Grip")
			fore_r.add_child(holder)
			res.arm = arm_r
			res.elbow = fore_r
		made.append(holder)
		var tip := Marker3D.new()
		holder.add_child(tip)
		res.holder = holder
		res.tip = tip
		match cls:
			"staff":
				_build_staff(holder, tip, wid)
			"bow":
				res.arrow = _build_bow(holder, tip, wid)
			_:
				_build_sword(holder, tip, wid)
	model.set_meta("look_nodes", made)
	return res


# ------------------------------------------------------------------ roupas e armaduras
## Estilo visual do item `id` no espaço `slot` ("" = espaço vazio). Itens sem "style" usam as placas.
static func gear_style(slot: String, id: String) -> String:
	if id == "":
		return DEFAULT_STYLE.get(slot, PLATE)
	return ItemDB.get_item(id).get("style", PLATE)


## Veste o GLB assets/models/gear/<style>.glb: ele tem os mesmos pivôs do knight.glb (LegL, KneeL, Body,
## Head, ArmL, ElbowL...), então cada malha passa para o pivô de mesmo nome do cavaleiro e anima junto.
## Materiais t1_/t2_ recebem a cor do item ("color" e "color2") e tp_ a cor da calça.
static func _attach_gear(model: Node3D, style: String, id: String, pants: Color, made: Array) -> void:
	var path := "res://assets/models/gear/%s.glb" % style
	if not ResourceLoader.exists(path):
		push_warning("equipamento sem modelo: " + path)
		return
	var it := ItemDB.get_item(id) if id != "" else {}
	var tints := {}
	if it.has("color"):
		var c: Color = it.color
		tints["t1_"] = c
		tints["t2_"] = it.get("color2", c.darkened(0.45))
	if pants.a > 0.0:
		tints["tp_"] = pants
	var glow: float = it.get("glow", 0.0)
	var g := (load(path) as PackedScene).instantiate() as Node3D
	for mi: MeshInstance3D in g.find_children("*", "MeshInstance3D", true, false):
		var pivot := mi.get_parent()
		var target := model.find_child(pivot.name, true, false) as Node3D
		if target == null:
			continue
		var xf := mi.transform
		mi.owner = null
		pivot.remove_child(mi)
		mi.name = "Gear_" + mi.name
		target.add_child(mi)
		mi.transform = xf
		made.append(mi)
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if src == null:
				continue
			var pre := src.resource_name.left(3)
			if tints.has(pre):
				mi.set_surface_override_material(s, _tinted(src, tints[pre], glow if pre == "t1_" else 0.0))
	g.free()


static func _tinted(src: BaseMaterial3D, c: Color, glow: float) -> BaseMaterial3D:
	var key := "%d|%s|%.2f" % [src.get_instance_id(), c.to_html(), glow]
	if _tint_cache.has(key):
		return _tint_cache[key]
	var m := src.duplicate() as BaseMaterial3D
	m.albedo_color = c
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow * 0.5
	_tint_cache[key] = m
	return m


# ------------------------------------------------------------------ armas
static func _build_sword(h: Node3D, tip: Node3D, id: String) -> void:
	var it := ItemDB.get_item(id)
	if it.has("model") and _build_model(h, tip, it.model):
		return
	var shape: String = it.get("shape", "")
	var length := 0.86
	var width := 0.052
	match shape:
		"saber":
			length = 0.8
			width = 0.04
		"cleaver":
			length = 0.68
			width = 0.15
		"great":
			length = 1.02
			width = 0.075
		"wood":
			width = 0.062
	var blade := _blade_mat(id)
	var trim := _mat(Color(0.9, 0.72, 0.3), true) if shape != "wood" else _mat(Color(0.4, 0.27, 0.14), false)
	var grip_len := 0.2 if shape == "great" else 0.14
	h.add_child(_cyl(0.017, 0.017, grip_len, _mat(Color(0.3, 0.18, 0.09), false), Vector3(0, 0, 0), Vector3(PI / 2, 0, 0)))
	h.add_child(_sphere(0.03, trim, Vector3(0, 0, -grip_len / 2 - 0.02)))
	var guard_w := 0.3 if shape == "great" else 0.24
	h.add_child(_box(Vector3(0.035, guard_w, 0.035), trim, Vector3(0, 0, grip_len / 2 + 0.015)))
	var z0 := grip_len / 2 + 0.03
	if shape == "saber":
		# lâmina curva: três segmentos girando de leve para cima
		var seg := length / 3.0
		var p := Vector3(0, 0, z0)
		for i in 3:
			var ang := -0.08 * (i + 1)
			var d := Vector3(0, -sin(ang), cos(ang)) * seg
			var b := _box(Vector3(0.012, width * (1.0 - i * 0.15), seg + 0.01), blade, p + d * 0.5, Vector3(ang, 0, 0))
			h.add_child(b)
			p += d
		tip.position = p
	else:
		var y_off := width * 0.35 if shape == "cleaver" else 0.0
		h.add_child(_box(Vector3(0.014 if shape != "cleaver" else 0.02, width, length), blade,
			Vector3(0, y_off, z0 + length / 2)))
		if shape != "cleaver":
			var pt := _cyl(0.0, width * 0.5, 0.12, blade, Vector3(0, 0, z0 + length + 0.06), Vector3(PI / 2, 0, 0))
			pt.scale = Vector3(0.3, 1, 1)
			h.add_child(pt)
		if shape == "great" or it.get("glow", 0.0) > 0.0:
			# sulco central brilhante
			h.add_child(_box(Vector3(0.018, width * 0.22, length * 0.8), _glow_mat(it.color.lightened(0.3), 0.6 + it.get("glow", 0.0)),
				Vector3(0, y_off, z0 + length * 0.45)))
		tip.position = Vector3(0, 0, z0 + length)


## Arma modelada no Blender (assets/models/<model>.glb): cabo na origem, lâmina em +Y do GLB, largura em X.
## O suporte usa +Z como direção da lâmina e Y como largura; o empty "Tip" do GLB vira a ponta.
static func _build_model(h: Node3D, tip: Node3D, model: String) -> bool:
	var path := "res://assets/models/%s.glb" % model
	if not ResourceLoader.exists(path):
		return false
	var w := (load(path) as PackedScene).instantiate() as Node3D
	WeaponModel.use_vertex_color(w)
	w.transform = Transform3D(Basis(Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)), Vector3.ZERO)
	h.add_child(w)
	var t := w.find_child("Tip", true, false) as Node3D
	tip.position = w.transform * t.position if t else Vector3(0, 0, 1.0)
	return true


static func _build_staff(h: Node3D, tip: Node3D, id: String) -> void:
	var it := ItemDB.get_item(id)
	var wood := _mat(it.get("wood", Color(0.45, 0.3, 0.16)), false)
	var gem_c: Color = it.color
	h.add_child(_cyl(0.022, 0.028, 1.5, wood, Vector3(0, 0.2, 0)))
	h.add_child(_cyl(0.035, 0.035, 0.08, _mat(Color(0.85, 0.7, 0.3), true), Vector3(0, -0.5, 0)))
	var top := Vector3(0, 0.98, 0)
	# garras segurando a gema
	for i in 4:
		var a := i * TAU / 4.0 + PI / 4.0
		var c := _box(Vector3(0.02, 0.17, 0.02), wood, top + Vector3(cos(a) * 0.055, 0.04, sin(a) * 0.055),
			Vector3(sin(a) * 0.35, 0, -cos(a) * 0.35))
		h.add_child(c)
	var gem := _sphere(0.065 if it.rarity != "legendary" else 0.085, _glow_mat(gem_c, 2.2 + it.get("glow", 0.0)), top + Vector3(0, 0.1, 0))
	gem.scale = Vector3(1, 1.35, 1)
	h.add_child(gem)
	var lt := OmniLight3D.new()
	lt.light_color = gem_c
	lt.light_energy = 0.7
	lt.omni_range = 2.2
	lt.position = top + Vector3(0, 0.1, 0)
	h.add_child(lt)
	tip.position = top + Vector3(0, 0.1, 0)


## Arco vertical na mão esquerda (+Z = para frente). Devolve a flecha encaixada (oculta).
static func _build_bow(h: Node3D, tip: Node3D, id: String) -> Node3D:
	var it := ItemDB.get_item(id)
	var wood := _bow_mat(id)
	var half := 0.62 if it.rarity in ["rare", "epic", "legendary"] else 0.55
	var n := 6
	var pts: Array[Vector3] = []
	for i in n + 1:
		var t := -1.0 + 2.0 * i / n
		pts.append(Vector3(0, t * half, -0.16 * t * t + 0.02))
	for i in n:
		var a := pts[i]
		var b := pts[i + 1]
		var d := b - a
		var thick := 0.045 if abs(i - n / 2.0 + 0.5) < 1.0 else 0.034
		var seg := _box(Vector3(thick, d.length() + 0.012, thick * 1.2), wood, (a + b) * 0.5,
			Vector3(atan2(d.z, d.y), 0, 0))
		h.add_child(seg)
	h.add_child(_box(Vector3(0.04, 0.12, 0.045), _mat(Color(0.25, 0.15, 0.08), false), Vector3(0, 0, 0.02)))
	# corda
	var string_m := _mat(Color(0.92, 0.9, 0.82), false)
	var ta := pts[0]
	var tb := pts[n]
	h.add_child(_box(Vector3(0.006, tb.y - ta.y, 0.006), string_m, Vector3(0, 0, ta.z)))
	# flecha encaixada (aparece ao tensionar)
	var arrow := Node3D.new()
	arrow.visible = false
	arrow.position = Vector3(0, 0.0, ta.z)
	h.add_child(arrow)
	arrow.add_child(_cyl(0.008, 0.008, 0.75, _mat(Color(0.55, 0.4, 0.22), false), Vector3(0, 0, 0.3), Vector3(PI / 2, 0, 0)))
	var head_m := _glow_mat(it.color, 1.5) if it.get("glow", 0.0) > 0.0 else _mat(Color(0.75, 0.77, 0.8), true)
	arrow.add_child(_cyl(0.0, 0.022, 0.07, head_m, Vector3(0, 0, 0.71), Vector3(PI / 2, 0, 0)))
	arrow.add_child(_box(Vector3(0.004, 0.04, 0.09), _mat(Color(0.9, 0.25, 0.2), false), Vector3(0, 0, -0.02)))
	tip.position = Vector3(0, 0, 0.3)
	return arrow


# ------------------------------------------------------------------ helpers
## Ponto (no espaço do pivô `space`) do centro da malha indicada, mesmo que a malha não seja filha dele.
static func _point_in(model: Node3D, space: Node3D, mesh_name: String) -> Vector3:
	if space == null:
		return Vector3.ZERO
	var mi := model.find_child(mesh_name, true, false) as MeshInstance3D
	if mi == null:
		return Vector3(0, -0.6, 0)
	return _chain(space, model, true).affine_inverse() * _chain(mi, model, true) * mi.get_aabb().get_center()


## Transformação acumulada de `n` até o ancestral `top` (funciona fora da árvore).
## `rest`: pivôs (nós que não são malha) contam só a posição, como se o cavaleiro estivesse na
## pose de repouso; assim trocar de equipamento no meio de um passo não prende a arma torta.
static func _chain(n: Node3D, top: Node3D, rest := false) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != top:
		if cur is Node3D:
			var x := (cur as Node3D).transform
			if rest and not (cur is MeshInstance3D):
				x = Transform3D(Basis.IDENTITY, x.origin)
			t = x * t
		cur = cur.get_parent()
	return t


static func _item_mat(id: String) -> StandardMaterial3D:
	var it := ItemDB.get_item(id)
	var m := _mat(it.get("color", Color.GRAY), it.get("metal", false))
	if it.get("glow", 0.0) > 0.0:
		m.emission_enabled = true
		m.emission = it.color
		m.emission_energy_multiplier = it.glow * 0.5
	return m


static func _blade_mat(id: String) -> StandardMaterial3D:
	var it := ItemDB.get_item(id)
	var wooden: bool = it.get("shape", "") == "wood"
	var m := _mat(it.get("color", Color(0.8, 0.8, 0.85)), not wooden)
	if it.get("glow", 0.0) > 0.0:
		m.emission_enabled = true
		m.emission = it.color
		m.emission_energy_multiplier = it.glow * 0.3
	return m


static func _bow_mat(id: String) -> StandardMaterial3D:
	var it := ItemDB.get_item(id)
	var m := _mat(it.get("color", Color(0.5, 0.35, 0.2)), false)
	if it.get("glow", 0.0) > 0.0:
		m.emission_enabled = true
		m.emission = it.color
		m.emission_energy_multiplier = it.glow * 0.6
	return m


static func _mat(c: Color, metal: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.85 if metal else 0.0
	m.roughness = 0.3 if metal else 0.8
	return m


static func _glow_mat(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


static func _box(size: Vector3, m: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = m
	mi.mesh = b
	mi.position = pos
	mi.rotation = rot
	return mi


static func _cyl(top: float, bottom: float, height: float, m: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = 10
	c.rings = 1
	c.material = m
	mi.mesh = c
	mi.position = pos
	mi.rotation = rot
	return mi


static func _sphere(r: float, m: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	s.material = m
	mi.mesh = s
	mi.position = pos
	return mi
