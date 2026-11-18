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
	"feet": ["LegL_Sabaton", "LegR_Sabaton", "LegL_Foot", "LegR_Foot"],
}
## Todas as peças do knight.glb de cada espaço: somem quando o estilo do item vem de um GLB de equipamento.
const REGION := {
	"head": ["Helmet", "HelmetDome", "VisorSlit", "HelmetTrim", "Plume"],
	"armor": ["Hips", "Torso", "Fauld", "Belt", "Tabard", "Gorget", "ArmL_Pauldron", "ArmR_Pauldron",
		"ArmL_Upper", "ArmR_Upper", "ArmL_Vambrace", "ArmR_Vambrace", "LegL_Thigh", "LegR_Thigh"],
	"hands": ["ArmL_Gauntlet", "ArmR_Gauntlet", "ArmL_Hand", "ArmR_Hand"],
	"feet": ["LegL_Sabaton", "LegR_Sabaton", "LegL_Knee", "LegR_Knee", "LegL_Foot", "LegR_Foot"],
}
## Estilo de cada espaço vazio: o personagem sem equipamento usa camisa, calça e sapatos.
const DEFAULT_STYLE := {"head": "h_bare", "armor": "a_shirt", "hands": "g_bare", "feet": "f_shoes"}
## Estilo que usa as próprias peças de placas do knight.glb (tingidas por PARTS).
const PLATE := "plate"
## Modelo do herói por corpo ("m"/"f"): o feminino tem os mesmos pivôs e nomes, mais o nó "Ponytail" (rabo de
## cavalo, filho de Head). As roupas e cabeças de equipamento também têm versão feminina: gear/<estilo>_f.glb.
const KNIGHT_SCENE := {"m": "res://assets/models/knight.glb", "f": "res://assets/models/knight_f.glb"}
## Estilos de cabeça que cobrem a nuca (capuz, coifas de malha e o chapéu de mago, que já traz o cabelo solto):
## o rabo de cavalo atravessaria, então some.
const HIDE_PONYTAIL := ["h_hood", "h_nasal", "h_kettle", "h_wizard", "h_archmage", "h_sage", "h_void", "h_oracle", "h_ember",
		"h_lich", "h_hierophant", "h_reaper", "h_raven", "h_dragon", "h_astral"]
## Materiais copiados e tingidos, por material de origem + cor (evita duplicar a cada troca de equipamento).
static var _tint_cache := {}
const SWORD_PARTS := ["Grip", "Blade"]
const SHIELD_PARTS := ["ShieldRim", "Shield"]
## Quanto o suporte da arma "desfaz" a rotação do braço (cajado fica quase de pé, arco fica vertical ao mirar).
const COUNTER := {"sword": 0.0, "staff": 0.75, "bow": 1.0}
## Cajado empunhado: quanto a vara desce na mão. A vara vai de -0,55 a 0,95 m do suporte (mais a gema, até
## ~1,17): com 0,3 a mão fica no meio dela, em vez de a 1/3 da ponta de baixo.
const STAFF_GRIP := 0.3
## Arco: número de trechos da curva, curvatura em repouso, quanto as pontas recuam e se aproximam com a
## corda toda puxada, a puxada "cheia" (m) e o ponto do punho onde a flecha descansa.
const BOW_SEGS := 6
const BOW_CURVE := 0.16
const BOW_FLEX_BACK := 0.1
const BOW_FLEX_SHRINK := 0.06
const BOW_FULL_DRAW := 0.5
const BOW_ARROW_REST := Vector3(0.0, 0.04, 0.03)


## Corpo normalizado: "f" ou "m" (vazio ou desconhecido = masculino).
static func body_key(body) -> String:
	return "f" if str(body) == "f" else "m"


## Novo modelo do herói para o corpo `body` (marca o corpo no meta "body", que apply() usa nas roupas).
static func instance(body) -> Node3D:
	var k := body_key(body)
	var m := (load(KNIGHT_SCENE[k]) as PackedScene).instantiate() as Node3D
	m.set_meta("body", k)
	return m


## Corpo do modelo montado por instance() ("m" para modelos antigos sem a marca).
static func body_of(model: Node3D) -> String:
	return str(model.get_meta("body", "m")) if model else "m"


## GLB de equipamento do estilo para o corpo: a versão _f no feminino (cai na masculina se faltar).
static func gear_path(style: String, body: String) -> String:
	var path := "res://assets/models/gear/%s.glb" % style
	if body_key(body) == "f":
		var fem := "res://assets/models/gear/%s_f.glb" % style
		if ResourceLoader.exists(fem):
			return fem
	return path


## Aplica o visual e devolve referências: {"class", "holder", "tip", "arrow", "arm", "elbow", "counter"}.
## As armas ficam presas no antebraço (ElbowX) para acompanhar a mão quando o cotovelo dobra;
## "arm" e "elbow" são os pivôs que o suporte precisa desfazer (veja COUNTER).
static func apply(model: Node3D, look: Dictionary) -> Dictionary:
	WeaponModel.use_vertex_color(model)   # sombra assada (AO) das placas do knight.glb
	for n in model.get_meta("look_nodes", []):
		if is_instance_valid(n):
			n.free()
	var made: Array = []
	var wid: String = look.get("weapon", "")
	var cls := ItemDB.weapon_class(wid)
	if cls == "scepter":
		cls = "staff"   # o cetro usa a animação e a pegada do cajado; o visual vem de sc_<id>.glb (_build_staff; sem ele, o cajado procedural)

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
			_attach_gear(model, style, id, pants, made, body_of(model))
	# rabo de cavalo (corpo feminino): some sob o capuz e as coifas de malha, que cobrem a nuca
	var tail := model.find_child("Ponytail", true, false) as Node3D
	if tail:
		tail.visible = not (gear_style("head", look.get("head", "")) in HIDE_PONYTAIL)
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
				_build_staff(holder, tip, wid, STAFF_GRIP)
			"bow":
				res.arrow = _build_bow(holder, tip, wid)
			_:
				_build_sword(holder, tip, wid)
	model.set_meta("look_nodes", made)
	KnightAnim.ensure_chest(model)   # peças novas da parte de cima do tronco vão para o pivô do peito
	PivotSkin.ensure(model)    # ossos das roupas com pele contínua seguem os pivôs
	if ToonLook.enabled():
		ToonLook.apply(model)
	if cape:
		_sync_skinned_outline(cape)
	return res


## A capa tem esqueleto (CapeRig): o contorno toon dela fica ao lado (não é filho) e não some junto ao
## esconder a capa. Copia a visibilidade da capa para as cascas que usam a mesma pele.
static func _sync_skinned_outline(mi: Node3D) -> void:
	var m := mi as MeshInstance3D
	if m == null or m.skin == null or m.get_parent() == null:
		return
	for c in m.get_parent().get_children():
		if c != m and c is MeshInstance3D and str(c.name).begins_with("ToonOutline") and (c as MeshInstance3D).skin == m.skin:
			(c as MeshInstance3D).visible = m.visible


# ------------------------------------------------------------------ roupas e armaduras
## Estilo visual do item `id` no espaço `slot` ("" = espaço vazio). Itens sem "style" usam as placas.
static func gear_style(slot: String, id: String) -> String:
	if id == "":
		return DEFAULT_STYLE.get(slot, PLATE)
	return ItemDB.get_item(id).get("style", PLATE)


## Veste o GLB assets/models/gear/<style>.glb (<style>_f.glb no corpo feminino): ele tem os mesmos pivôs do knight.glb (LegL, KneeL, Body,
## Head, ArmL, ElbowL...), então cada malha passa para o pivô de mesmo nome do cavaleiro e anima junto.
## A cor por vértice é a sombra assada (AO) no Blender. Materiais t1_/t2_ (t1d_/t2d_ escurecidos) recebem a cor do item ("color" e "color2") e tp_ a cor da calça.
static func _attach_gear(model: Node3D, style: String, id: String, pants: Color, made: Array, body := "m") -> void:
	var path := gear_path(style, body)
	if not ResourceLoader.exists(path):
		push_warning("equipamento sem modelo: " + path)
		return
	var it := ItemDB.get_item(id) if id != "" else {}
	var tints := {}
	if it.has("color"):
		var c: Color = it.color
		tints["t1_"] = c
		var c2: Color = it.get("color2", c.darkened(0.45))
		tints["t2_"] = c2
		tints["t1d"] = c.darkened(0.42)      # tons escurecidos (linhas da malha, gibão sob o couro)
		tints["t2d"] = c2.darkened(0.42)
	if pants.a > 0.0:
		tints["tp_"] = pants
	var glow: float = it.get("glow", 0.0)
	var g := (load(path) as PackedScene).instantiate() as Node3D
	WeaponModel.use_vertex_color(g)    # sombra assada (AO) na cor por vértice multiplica o albedo
	# roupa com pele contínua (esqueleto próprio): o esqueleto inteiro entra no modelo e o PivotSkin faz os
	# ossos seguirem os pivôs do cavaleiro
	var skels := g.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		for sk: Skeleton3D in skels:
			var top: Node = sk
			while top.get_parent() != g:
				top = top.get_parent()
			var xf := (top as Node3D).transform
			top.owner = null
			for d in top.find_children("*", "", true, false):
				d.owner = null
			g.remove_child(top)
			top.name = "Gear_%s_%s" % [style, top.name]
			model.add_child(top)
			(top as Node3D).transform = xf
			made.append(top)
			for mi: MeshInstance3D in top.find_children("*", "MeshInstance3D", true, false):
				mi.name = "Gear_" + mi.name
				_tint_mesh(mi, tints, glow)
		g.free()
		return
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
		_tint_mesh(mi, tints, glow)
	g.free()


static func _tint_mesh(mi: MeshInstance3D, tints: Dictionary, glow: float) -> void:
	for s in mi.mesh.get_surface_count():
		var src := mi.mesh.surface_get_material(s) as BaseMaterial3D
		if src == null:
			continue
		var pre := src.resource_name.left(3)
		if tints.has(pre):
			mi.set_surface_override_material(s, _tinted(src, tints[pre], glow if pre == "t1_" else 0.0))


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
	if it.has("model") and _build_model(h, tip, it.model) != null:
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
## O lado esquerdo da folha de conceito (-X do GLB, para onde as lâminas curvas dobram: as costas) vai para
## +Y do suporte, como a "saber" procedural: ponta curvando para cima e gume para baixo na guarda, liderando
## o golpe. Com -X -> +Y, o eixo Z do GLB vira -X do suporte (giro de 180° no eixo da lâmina, sem espelhar).
static func _build_model(h: Node3D, tip: Node3D, model: String, basis := SWORD_BASIS) -> Node3D:
	var path := "res://assets/models/%s.glb" % model
	if not ResourceLoader.exists(path):
		return null
	var w := (load(path) as PackedScene).instantiate() as Node3D
	WeaponModel.use_vertex_color(w)
	w.transform = Transform3D(basis, Vector3.ZERO)
	h.add_child(w)
	var t := w.find_child("Tip", true, false) as Node3D
	tip.position = w.transform * t.position if t else Vector3(0, 0, 1.0)
	return w


const SWORD_BASIS := Basis(Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0))


## Cajado modelado no Blender (st_<id>.glb, tools/blender/armory.py): a haste já sobe em +Y do GLB, como o suporte
## espera; o "Tip" é o centro da gema, onde nascem os projéteis e a luz.
## `grip` desce a vara inteira em relação ao suporte (a mão): o cajado empunhado usa STAFF_GRIP para a mão
## ficar no meio da vara; o ícone do inventário usa 0 (enquadramento de sempre).
static func _build_staff(h: Node3D, tip: Node3D, id: String, grip := 0.0) -> void:
	var it := ItemDB.get_item(id)
	if it.has("model"):
		var w := _build_model(h, tip, it.model, Basis.IDENTITY)
		if w != null:
			w.position.y -= grip
			tip.position.y -= grip
			_gem_light(h, tip.position, it.color)
			return
	var wood := _mat(it.get("wood", Color(0.45, 0.3, 0.16)), false)
	var gem_c: Color = it.color
	var dn := Vector3(0, -grip, 0)
	h.add_child(_cyl(0.022, 0.028, 1.5, wood, Vector3(0, 0.2, 0) + dn))
	h.add_child(_cyl(0.035, 0.035, 0.08, _mat(Color(0.85, 0.7, 0.3), true), Vector3(0, -0.5, 0) + dn))
	var top := Vector3(0, 0.98, 0) + dn
	# garras segurando a gema
	for i in 4:
		var a := i * TAU / 4.0 + PI / 4.0
		var c := _box(Vector3(0.02, 0.17, 0.02), wood, top + Vector3(cos(a) * 0.055, 0.04, sin(a) * 0.055),
			Vector3(sin(a) * 0.35, 0, -cos(a) * 0.35))
		h.add_child(c)
	var gem := _sphere(0.065 if it.rarity != "legendary" else 0.085, _glow_mat(gem_c, 2.2 + it.get("glow", 0.0)), top + Vector3(0, 0.1, 0))
	gem.scale = Vector3(1, 1.35, 1)
	h.add_child(gem)
	_gem_light(h, top + Vector3(0, 0.1, 0), gem_c)
	tip.position = top + Vector3(0, 0.1, 0)


static func _gem_light(h: Node3D, at: Vector3, c: Color) -> void:
	var lt := OmniLight3D.new()
	lt.light_color = c
	lt.light_energy = 0.7
	lt.omni_range = 2.2
	lt.position = at
	h.add_child(lt)


## Arco vertical na mão esquerda (+Z = para frente). Devolve a flecha encaixada (oculta).
static func _build_bow(h: Node3D, tip: Node3D, id: String) -> Node3D:
	var it := ItemDB.get_item(id)
	if it.has("model"):
		var w := _build_model(h, tip, it.model, Basis.IDENTITY)
		if w != null:
			return _model_bow_string(h, w, _model_arrow(h, w))
	var wood := _bow_mat(id)
	var half := 0.62 if it.rarity in ["rare", "epic", "legendary"] else 0.55
	var segs: Array = []
	for i in BOW_SEGS:
		var thick := 0.045 if abs(i - BOW_SEGS / 2.0 + 0.5) < 1.0 else 0.034
		var seg := _box(Vector3(thick, 1.0, thick * 1.2), wood, Vector3.ZERO)
		h.add_child(seg)
		segs.append(seg)
	h.add_child(_box(Vector3(0.04, 0.12, 0.045), _mat(Color(0.25, 0.15, 0.08), false), Vector3(0, 0, 0.02)))
	# corda em dois trechos (pontas do arco até o encaixe da flecha): segue os dedos ao puxar
	var string_m := _mat(Color(0.92, 0.9, 0.82), false)
	var strings: Array = []
	for i in 2:
		var st := _box(Vector3(0.006, 1.0, 0.006), string_m, Vector3.ZERO)
		h.add_child(st)
		strings.append(st)
	# flecha encaixada (aparece ao tensionar): o nó fica no encaixe (fim da haste) e a haste vai para +Z
	var arrow := Node3D.new()
	arrow.visible = false
	h.add_child(arrow)
	arrow.add_child(_cyl(0.008, 0.008, 0.75, _mat(Color(0.55, 0.4, 0.22), false), Vector3(0, 0, 0.375), Vector3(PI / 2, 0, 0)))
	var head_m := _glow_mat(it.color, 1.5) if it.get("glow", 0.0) > 0.0 else _mat(Color(0.75, 0.77, 0.8), true)
	arrow.add_child(_cyl(0.0, 0.022, 0.07, head_m, Vector3(0, 0, 0.785), Vector3(PI / 2, 0, 0)))
	arrow.add_child(_box(Vector3(0.004, 0.04, 0.09), _mat(Color(0.9, 0.25, 0.2), false), Vector3(0, 0, 0.06)))
	h.set_meta("bow", {"half": half, "segs": segs, "strings": strings, "arrow": arrow})
	bow_shape(h, bow_rest_nock(h))
	tip.position = Vector3(0, 0, 0.3)
	return arrow


## Encaixe da flecha com a corda solta (espaço do suporte do arco).
static func bow_rest_nock(h: Node3D) -> Vector3:
	var data: Dictionary = h.get_meta("bow", {})
	if data.has("rest"):
		return data.rest
	return Vector3(0.0, 0.0, _bow_limb(1.0, 0.0).z)


## Arco modelado: a corda não vem no GLB, só as pontas dela ("StringTop"/"StringBot"). Desenha a corda em dois
## trechos que bow_shape estica até os dedos (o arco do GLB é uma peça só: não enverga). GLB antigo, com a
## corda na malha e sem as pontas: fica como está (corda parada).
static func _model_bow_string(h: Node3D, bow: Node3D, arrow: Node3D) -> Node3D:
	var top := bow.find_child("StringTop", true, false) as Node3D
	var bot := bow.find_child("StringBot", true, false) as Node3D
	if top == null or bot == null:
		return arrow
	var string_m := _mat(Color(0.92, 0.89, 0.78), false)
	var strings: Array = []
	for i in 2:
		var st := _box(Vector3(0.0065, 1.0, 0.0065), string_m, Vector3.ZERO)
		h.add_child(st)
		strings.append(st)
	var tips := [bow.transform * top.position, bow.transform * bot.position]
	var rest: Vector3 = arrow.position
	h.set_meta("bow", {"tips": tips, "strings": strings, "arrow": arrow, "rest": Vector3(0.0, rest.y, rest.z)})
	bow_shape(h, bow_rest_nock(h))
	return arrow


## Ponto do arco no parâmetro `t` (-1 = ponta de baixo, 0 = punho, 1 = ponta de cima), envergado por `flex`
## (0..1): as pontas recuam (para o lado da corda) e se aproximam um pouco uma da outra.
static func _bow_limb(t: float, flex: float, half := 1.0) -> Vector3:
	return Vector3(0.0, t * half * (1.0 - BOW_FLEX_SHRINK * flex), -(BOW_CURVE + BOW_FLEX_BACK * flex) * t * t + 0.02)


## Monta o arco com a corda puxada até `nock` (espaço do suporte; z menor = mais puxada): verga o arco,
## estica os dois trechos da corda das pontas até o encaixe e põe a flecha no encaixe apontando para o
## punho (ela passa rente à mão do arco).
static func bow_shape(h: Node3D, nock: Vector3) -> void:
	var data: Dictionary = h.get_meta("bow")
	var tips: Array = data.get("tips", [])
	if data.has("segs"):   # arco do código: os trechos vergam
		var half: float = data.half
		var rest := bow_rest_nock(h)
		var flex := clampf((rest.z - nock.z) / BOW_FULL_DRAW, 0.0, 1.2)
		var segs: Array = data.segs
		var n := segs.size()
		for i in n:
			var a := _bow_limb(-1.0 + 2.0 * i / n, flex, half)
			var b := _bow_limb(-1.0 + 2.0 * (i + 1) / n, flex, half)
			var d := b - a
			var seg: Node3D = segs[i]
			seg.basis = Basis.from_euler(Vector3(atan2(d.z, d.y), 0, 0)).scaled_local(Vector3(1.0, d.length() + 0.012, 1.0))
			seg.position = (a + b) * 0.5
		tips = [_bow_limb(1.0, flex, half), _bow_limb(-1.0, flex, half)]
	var strings: Array = data.strings
	for i in 2:
		var tp: Vector3 = tips[i]
		var d := nock - tp
		var st: Node3D = strings[i]
		st.basis = Basis.from_euler(Vector3(atan2(d.z, d.y), 0, 0)).scaled_local(Vector3(1.0, maxf(d.length(), 0.01), 1.0))
		st.position = (tp + nock) * 0.5
	var arrow: Node3D = data.arrow
	arrow.position = nock
	var to := BOW_ARROW_REST - nock
	if to.length() > 0.01:
		arrow.basis = Basis.looking_at(to.normalized(), Vector3.UP, true)


## Arco modelado no Blender (bw_<id>.glb, tools/blender/armory.py): braços em ±Y, corda atrás (-Z). A flecha
## (bw_arrow.glb, ponta em +Z) encaixa no empty "Nock", o centro da corda; o "Tip" fica 0,3 m à frente.
static func _model_arrow(h: Node3D, bow: Node3D) -> Node3D:
	var arrow := Node3D.new()
	arrow.visible = false
	var nock := bow.find_child("Nock", true, false) as Node3D
	arrow.position = bow.transform * nock.position if nock else Vector3(0, 0, -0.14)
	h.add_child(arrow)
	const ARROW := "res://assets/models/bw_arrow.glb"
	if ResourceLoader.exists(ARROW):
		var a := (load(ARROW) as PackedScene).instantiate() as Node3D
		WeaponModel.use_vertex_color(a)
		arrow.add_child(a)
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
	m.vertex_color_use_as_albedo = true      # peças de placas tingidas mantêm a sombra assada
	if it.get("metal", false):               # metal fosco, como as peças modulares (não espelha o céu)
		m.metallic = 0.6
		m.roughness = 0.45
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
