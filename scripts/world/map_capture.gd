class_name MapCapture
extends Node
## Imagem de cima de cada mapa (para o minimapa e o mapa-mundi): uma câmera ortográfica olhando para baixo
## renderiza a região uma vez num SubViewport do mesmo mundo 3D e guarda a textura. Uma região por vez,
## só quando alguém pede (`texture`). Sem tela (headless/servidor) não renderiza: o mapa fica com o fundo liso.
## O clima não entra na foto: durante a captura a neve, a chuva e as poças ficam em 0 (depois do WeatherFX
## publicar as globais no quadro) e as partículas do clima ficam escondidas.

signal captured(region: String)

const RES := {"vila": 1024}
const RES_DEFAULT := 640

var _tex := {}       # região -> Texture2D
var _queue: Array = []
var _busy := false
var _hidden: Array = []   # partículas do clima escondidas durante a captura


func _ready() -> void:
	process_priority = 1000   # depois do WeatherFX, que publica as globais de clima a cada quadro


func _process(_delta: float) -> void:
	if _busy:
		for k in ["weather_snow", "weather_wet", "weather_rain"]:
			RenderingServer.global_shader_parameter_set(k, 0.0)


## Textura do mapa da região (null enquanto não ficou pronta; pede a captura na primeira vez).
func texture(region: String) -> Texture2D:
	if _tex.has(region):
		return _tex[region]
	if not (region in _queue) and Regions.DATA.has(region):
		_queue.append(region)
		if not _busy:
			_next.call_deferred()
	return null


static func can_render() -> bool:
	return DisplayServer.get_name() != "headless"


func _next() -> void:
	if _busy or _queue.is_empty() or not is_inside_tree():
		return
	var region: String = _queue.pop_front()
	if not can_render():
		_tex[region] = null
		return
	_busy = true
	var tex := await _render(region)
	_busy = false
	if not is_inside_tree():
		return
	_tex[region] = tex
	captured.emit(region)
	if not _queue.is_empty():
		_next.call_deferred()


func _render(region: String) -> Texture2D:
	var res := int(RES.get(region, RES_DEFAULT))
	var r := MapRules.rect(region)
	var vp := SubViewport.new()
	vp.size = Vector2i(res, res)
	vp.world_3d = get_viewport().world_3d
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.msaa_3d = Viewport.MSAA_2X
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = r.size.x
	cam.near = 1.0
	cam.far = 400.0
	cam.environment = _environment()
	vp.add_child(cam)
	add_child(vp)
	# olhando para baixo com o norte (-Z) para cima na imagem
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(-PI / 2, 0, 0)),
		Vector3(r.get_center().x, 160.0, r.get_center().y))
	cam.current = true
	_hide_weather(true)
	_process(0.0)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image() if is_inside_tree() else null
	_hide_weather(false)
	vp.queue_free()
	if img == null or img.is_empty():
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _hide_weather(on: bool) -> void:
	if on:
		_hidden.clear()
		var fx: Node = Weather.fx if is_instance_valid(Weather.fx) else null
		if fx == null:
			return
		for n in fx.find_children("*", "GPUParticles3D", true, false):
			if n.visible:
				n.visible = false
				_hidden.append(n)
	else:
		for n in _hidden:
			if is_instance_valid(n):
				n.visible = true
		_hidden.clear()


## Luz própria da foto do mapa: sem neblina e com ambiente forte (o mapa fica legível também à noite).
func _environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.2, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.85, 0.8)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	return env
