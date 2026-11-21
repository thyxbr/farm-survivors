class_name MonsterPortraits
extends Node
## Retrato de cada monstro para o Bestiário: o modelo de verdade (EnemyModel) fotografado uma vez num
## SubViewport de fundo transparente e guardado em disco (IconCache, por versão do jogo), como os ícones de
## item (ItemIcons). Sem janela (servidor, testes) fica desligado e a tela mostra só o cartão.

const SIZE := 256
const ROOT := "user://bestiary_portraits"

static var _inst: MonsterPortraits
static var _cache := {}        # kind -> Texture2D (null = sem modelo)
var _queue: Array[String] = []
var _waiting := {}             # kind -> Array[Callable]
var _busy := false


## Textura do retrato, ou null enquanto não fica pronta (chama `on_ready` quando ficar).
static func portrait(kind: String, on_ready: Callable) -> Texture2D:
	if DisplayServer.get_name() == "headless":
		return null
	if _cache.has(kind):
		return _cache[kind]
	var saved := IconCache.load_icon(ROOT, _version(), kind)
	if saved:
		_cache[kind] = saved
		return saved
	if _inst == null or not is_instance_valid(_inst):
		_inst = MonsterPortraits.new()
		_inst.process_mode = Node.PROCESS_MODE_ALWAYS
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_inst)
	_inst._request.call_deferred(kind, on_ready)
	return null


static func _version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "dev"))


func _ready() -> void:
	IconCache.prune(ROOT, _version())


func _request(kind: String, on_ready: Callable) -> void:
	if _cache.has(kind):
		if on_ready.is_valid():
			on_ready.call()
		return
	if not _waiting.has(kind):
		_waiting[kind] = []
		_queue.append(kind)
	_waiting[kind].append(on_ready)
	if not _busy:
		_run()


func _run() -> void:
	_busy = true
	while not _queue.is_empty():
		var kind: String = _queue.pop_front()
		_cache[kind] = await _render(kind)
		for cb: Callable in _waiting.get(kind, []):
			if cb.is_valid():
				cb.call()
		_waiting.erase(kind)
	_busy = false


func _render(kind: String) -> Texture2D:
	var data: Dictionary = Balance.tables.get_table("enemies").get(kind, {})
	if data.is_empty() or not EnemyModel.MODELS.has(str(data.get("model", ""))):
		return null
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
	e.ambient_light_color = Color(0.62, 0.58, 0.54)
	e.ambient_light_energy = 0.85
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.7, 0.6, 0)
	key.light_energy = 1.3
	key.light_color = Color(1, 0.93, 0.82)
	vp.add_child(key)
	var model := EnemyModel.instance(kind, data)
	vp.add_child(model)
	model.rotation.y = 0.55      # três quartos, virado um pouco para a direita do cartão
	add_child(vp)
	for i in 3:                  # o estilo toon entra no quadro seguinte ao add_child
		await get_tree().process_frame
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		vp.queue_free()
		return null
	var dir := Vector3(0.0, 0.28, 1.0).normalized()
	var x := Vector3.UP.cross(dir).normalized()
	var y := dir.cross(x).normalized()
	var c := box.get_center()
	var half := 0.0
	for i in 8:
		var d := box.get_endpoint(i) - c
		half = maxf(half, maxf(absf(d.dot(x)), absf(d.dot(y))))
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = half * 2.0 * 1.08
	cam.far = 60.0
	vp.add_child(cam)
	cam.global_transform = Transform3D(Basis(x, y, dir), c + dir * 20.0)
	cam.current = true
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	IconCache.save_icon(ROOT, _version(), kind, img)
	return ImageTexture.create_from_image(img)
