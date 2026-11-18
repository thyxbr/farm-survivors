class_name ItemIcons
extends Node
## Ícone do item tirado do modelo 3D de verdade (a mesma arma/armadura que o cavaleiro veste),
## renderizado uma vez num SubViewport e guardado em disco (IconCache, por versão do jogo). Sem janela
## (servidor dedicado, testes) fica desligado e o espaço cai no ícone pintado por código (IconPainter),
## que também aparece enquanto o ícone 3D não chega.
## Item que o cavaleiro não veste (poções, comida, colheitas, sementes, materiais, anéis, amuletos, orbe,
## aljava) usa o modelo da família, com a cor do item: a tabela está em ItemIconModels.

const KNIGHT := preload("res://assets/models/knight.glb")
const SIZE := 192
const ROOT := "user://icons"

static var _inst: ItemIcons
static var _cache := {}        # id -> Texture2D (null = item sem modelo)
var _queue: Array[String] = []
var _waiting := {}             # id -> Array[Callable] (quem redesenhar quando ficar pronto)
var _busy := false


## Textura do item, ou null se ainda não ficou pronta (chama `on_ready` quando ficar) ou se não há modelo.
static func icon(id: String, on_ready: Callable) -> Texture2D:
	if not enabled():
		return null
	if _cache.has(id):
		return _cache[id]
	if not _has_model(id):
		_cache[id] = null
		return null
	var saved := IconCache.load_icon(ROOT, _version(), id)
	if saved:
		_cache[id] = saved
		return saved
	if _inst == null or not is_instance_valid(_inst):
		_inst = ItemIcons.new()
		_inst.process_mode = Node.PROCESS_MODE_ALWAYS
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_inst)
	_inst._request.call_deferred(id, on_ready)
	return null


## Sem janela não há o que fotografar: o espaço mostra o ícone pintado.
static func enabled() -> bool:
	return DisplayServer.get_name() != "headless"


## Enfileira de uma vez os ícones que ainda faltam (chamado ao abrir uma tela com muitos itens).
static func prewarm(ids: Array) -> void:
	for id in ids:
		if id is String and id != "":
			icon(id, Callable())


static func _version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "dev"))


func _ready() -> void:
	IconCache.prune(ROOT, _version())    # ícones de versões antigas do jogo


static func _has_model(id: String) -> bool:
	var item := ItemDB.get_item(id)
	if item.is_empty():
		return false
	if ResourceLoader.exists("res://assets/ui/items/%s.png" % str(item.get("art", id))):
		return false    # tem arte pintada (ItemSlot.item_art): não precisa fotografar
	return ItemIconModels.is_gear(item) or not _family(id).is_empty()


## Modelo e cor da família de um item sem modelo de equipamento (vazio para equipamento).
static func _family(id: String) -> Dictionary:
	return ItemIconModels.spec(id, ItemDB.ITEMS, ItemDB.CROPS)


func _request(id: String, on_ready: Callable) -> void:
	if _cache.has(id):
		if on_ready.is_valid():
			on_ready.call()
		return
	if not _waiting.has(id):
		_waiting[id] = []
		_queue.append(id)
	_waiting[id].append(on_ready)
	if not _busy:
		_run()


func _run() -> void:
	_busy = true
	while not _queue.is_empty():
		var id: String = _queue.pop_front()
		_cache[id] = await _render(id)
		for cb: Callable in _waiting.get(id, []):
			if cb.is_valid():
				cb.call()
		_waiting.erase(id)
	_busy = false


func _render(id: String) -> Texture2D:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.size = Vector2i(SIZE, SIZE)
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.56, 0.52)
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.6, 0.5, 0)
	key.light_energy = 1.3
	key.light_color = Color(1, 0.93, 0.82)
	vp.add_child(key)
	var holder := Node3D.new()
	vp.add_child(holder)
	var slot := ItemDB.slot_of(id)
	var weapon := slot == "weapon"
	var family := _family(id)
	if not family.is_empty():
		var model := _family_model(family)
		if model == null:
			vp.queue_free()
			return null
		holder.add_child(model)
	elif weapon:
		var tip := Marker3D.new()
		holder.add_child(tip)
		match ItemDB.weapon_class(id):
			"staff", "scepter":
				KnightLook._build_staff(holder, tip, id)
			"bow":
				KnightLook._build_bow(holder, tip, id)
			_:
				KnightLook._build_sword(holder, tip, id)
	else:
		holder.add_child(_gear_only(slot, id))
	add_child(vp)
	for i in 3:                     # o estilo toon entra no quadro seguinte ao add_child
		await get_tree().process_frame
	var box := _bounds(holder)
	if box.size == Vector3.ZERO:
		vp.queue_free()
		return null
	# de onde olhar: equipamento de frente, em três quartos; arma de lado, deitada na diagonal
	var dir := Vector3(0.5, 0.3, 1.0).normalized()
	var up := Vector3.UP
	if weapon:
		var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
		var order := [0, 1, 2]
		order.sort_custom(func(a: int, b: int) -> bool: return box.size[a] > box.size[b])
		# arma comprida e fina vira um risco no ícone: engorda a largura até uns 3,5:1
		var k := clampf(box.size[order[0]] / maxf(box.size[order[1]] * 3.5, 0.001), 1.0, 2.4)
		if k > 1.0:
			var sc := Vector3.ONE
			sc[order[1]] = k
			sc[order[2]] = k
			holder.scale = sc
			box = _bounds(holder)
		dir = axes[order[2]]
		up = (axes[order[0]] - axes[order[1]]).normalized()
	elif not family.is_empty():
		dir = (family.view as Vector3).normalized()     # peça em pé de frente; prato e monte, mais de cima
	var x := up.cross(dir).normalized()
	var y := dir.cross(x).normalized()
	var c := box.get_center()
	var half := 0.0
	var margin := 1.1
	if family.is_empty():
		for i in 8:
			var d := box.get_endpoint(i) - c
			half = maxf(half, maxf(absf(d.dot(x)), absf(d.dot(y))))
	else:
		# enquadra pelos vértices de verdade: pela caixa, peça redonda ou inclinada sobrava pequena no quadro
		var frame := _frame(holder, x, y)
		var mid := frame.get_center()
		c += x * (mid.x - c.dot(x)) + y * (mid.y - c.dot(y))
		half = maxf(frame.size.x, frame.size.y) * 0.5
		margin = FAMILY_MARGIN
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = half * 2.0 * margin
	cam.far = 30.0
	vp.add_child(cam)
	cam.global_transform = Transform3D(Basis(x, y, dir), c + dir * 8.0)
	cam.current = true
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	IconCache.save_icon(ROOT, _version(), id, img)
	return ImageTexture.create_from_image(img)


func _bounds(holder: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in holder.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## Folga em volta dos modelos de família no quadro.
const FAMILY_MARGIN := 1.2
## Brilho próprio do material `i_tint_glow` (orbe, cristal, brasa).
const FAMILY_GLOW := 0.55


## O modelo da família com a cor do item nos materiais `i_tint*` (os outros ficam como vieram do Blender).
func _family_model(family: Dictionary) -> Node3D:
	var scene := load(family.model) as PackedScene
	if scene == null:
		return null
	var model := scene.instantiate() as Node3D
	var tint: Color = family.tint
	var made := {}       # material do GLB -> cópia tingida
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if src == null:
				continue
			if not made.has(src):
				made[src] = _tinted(src, tint)
			if made[src] != null:
				mi.set_surface_override_material(s, made[src])
	return model


## Cópia do material com a cor do item, ou null se o material não é um dos `i_tint*`.
func _tinted(src: BaseMaterial3D, tint: Color) -> BaseMaterial3D:
	var col := tint
	match src.resource_name:
		ItemIconModels.TINT, ItemIconModels.TINT_GLOW:
			pass
		ItemIconModels.TINT_DARK:
			col = tint.darkened(0.38)
		ItemIconModels.TINT_LIGHT:
			col = tint.lightened(0.5)
		_:
			return null
	var m := src.duplicate() as BaseMaterial3D
	m.albedo_color = col
	m.emission_enabled = src.resource_name == ItemIconModels.TINT_GLOW
	if m.emission_enabled:
		m.emission = tint
		m.emission_energy_multiplier = FAMILY_GLOW
	return m


## Retângulo que os vértices visíveis ocupam no plano da câmera (eixos x e y dela).
func _frame(holder: Node3D, x: Vector3, y: Vector3) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for mi: MeshInstance3D in holder.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or mi.mesh == null or mi.name.begins_with("ToonOutline"):
			continue
		var xf := mi.global_transform
		for s in mi.mesh.get_surface_count():
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var p := xf * v
				var q := Vector2(p.dot(x), p.dot(y))
				lo = lo.min(q)
				hi = hi.max(q)
	return Rect2(lo, hi - lo)


## Materiais do corpo que vêm dentro dos GLBs de equipamento (rosto sob o capuz, pescoço da cota).
const BODY_MATS := ["g_skin", "g_hair", "g_eye", "g_sclera", "g_lip"]


## Malha que é só corpo (todas as superfícies com material de pele, cabelo, olho ou boca).
func _is_body(mi: MeshInstance3D) -> bool:
	for s in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(s)
		if m == null or m.resource_name not in BODY_MATS:
			return false
	return true


## O cavaleiro com tudo escondido menos a peça `id` (elmo, armadura, luvas, botas ou escudo).
func _gear_only(slot: String, id: String) -> Node3D:
	var model := KNIGHT.instantiate() as Node3D
	WeaponModel.use_vertex_color(model)
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.visible = false
	if slot == "offhand":
		for pn in KnightLook.SHIELD_PARTS:
			var mi := model.find_child(pn, true, false) as MeshInstance3D
			if mi:
				mi.visible = true
				if pn == "Shield" and id != "knight_shield":
					mi.material_override = KnightLook._item_mat(id)
		return model
	if slot == "back" and ItemDB.get_item(id).has("style"):
		# asas e capas com modelo próprio: a peça sozinha, sem o cavaleiro
		var path := "res://assets/models/back/%s.glb" % ItemDB.get_item(id).get("style", "")
		if ResourceLoader.exists(path):
			model.free()
			var wings := (load(path) as PackedScene).instantiate() as Node3D
			WeaponModel.use_vertex_color(wings)
			BackFx.apply_anim(wings)
			return wings
	if slot == "back":
		# capa: a malha de capa do cavaleiro com a cor do item
		var cape := model.find_child("Cape", true, false) as MeshInstance3D
		if cape:
			cape.visible = true
			cape.material_override = KnightLook._item_mat(id)
		return model
	var style := KnightLook.gear_style(slot, id)
	if style == KnightLook.PLATE:
		for pn in KnightLook.REGION[slot]:
			var n := model.find_child(pn, true, false) as Node3D
			if n:
				n.visible = slot != "hands" or not pn.begins_with("ArmL")   # luvas: mostra uma só
		for pn in KnightLook.PARTS[slot]:
			var mi := model.find_child(pn, true, false) as MeshInstance3D
			if mi:
				mi.material_override = KnightLook._item_mat(id)
	else:
		var pants := Color(0, 0, 0, 0)
		if slot == "armor":
			pants = ItemDB.get_item(id).get("pants", Color(0.24, 0.22, 0.22))
		var made: Array = []
		KnightLook._attach_gear(model, style, id, pants, made)
		for n: Node in made:
			var meshes: Array = n.find_children("*", "MeshInstance3D", true, false)
			if n is MeshInstance3D:
				meshes.append(n)
			for mi: MeshInstance3D in meshes:
				if _is_body(mi) or (slot == "hands" and "ArmL" in mi.name):
					mi.visible = false
	return model
