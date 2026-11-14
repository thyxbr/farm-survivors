class_name ItemIcons
extends Node
## Ícone do item tirado do modelo 3D de verdade (a mesma arma/armadura que o cavaleiro veste),
## renderizado uma vez num SubViewport e guardado. Itens sem modelo (poções, anéis, materiais) devolvem
## null e o espaço cai no ícone pintado por código.

const KNIGHT := preload("res://assets/models/knight.glb")
const SIZE := 192

static var _inst: ItemIcons
static var _cache := {}        # id -> Texture2D (null = item sem modelo)
var _queue: Array[String] = []
var _waiting := {}             # id -> Array[Callable] (quem redesenhar quando ficar pronto)
var _busy := false


## Textura do item, ou null se ainda não ficou pronta (chama `on_ready` quando ficar) ou se não há modelo.
static func icon(id: String, on_ready: Callable) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	if not _has_model(id):
		_cache[id] = null
		return null
	if _inst == null or not is_instance_valid(_inst):
		_inst = ItemIcons.new()
		_inst.process_mode = Node.PROCESS_MODE_ALWAYS
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_inst)
	_inst._request.call_deferred(id, on_ready)
	return null


static func _has_model(id: String) -> bool:
	var slot := ItemDB.slot_of(id)
	if slot == "weapon" or KnightLook.REGION.has(slot):
		return true
	return slot == "offhand" and ItemDB.get_item(id).get("needs", "") == "sword"


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
	if weapon:
		var tip := Marker3D.new()
		holder.add_child(tip)
		match ItemDB.weapon_class(id):
			"staff":
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
	var x := up.cross(dir).normalized()
	var y := dir.cross(x).normalized()
	var c := box.get_center()
	var half := 0.0
	for i in 8:
		var d := box.get_endpoint(i) - c
		half = maxf(half, maxf(absf(d.dot(x)), absf(d.dot(y))))
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = half * 2.0 * 1.1
	cam.far = 30.0
	vp.add_child(cam)
	cam.global_transform = Transform3D(Basis(x, y, dir), c + dir * 8.0)
	cam.current = true
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var tex := ImageTexture.create_from_image(vp.get_texture().get_image())
	vp.queue_free()
	return tex


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
