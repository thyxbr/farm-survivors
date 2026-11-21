class_name CharPreview
extends SubViewportContainer
## Prévia 3D do cavaleiro com o equipamento atual (atualiza ao equipar). Arraste para girar.

var vp: SubViewport
var pivot: Node3D
var model: Node3D
var _drag := false
var _user_turned := false
var _base := -0.6
var _idle := 0.0
var _rig := {}
var _look := {}
## Encanto mostrado na arma da prévia (painel do ferreiro): elemento e nível; nível 0 = o do personagem.
var _ench_el := ""
var _ench_lv := -1
## Arma mostrada no lugar da equipada (tela de criação: a arma inicial da classe, sem equipar). "" = a equipada.
var weapon_override := ""
## Corpo mostrado ("m"/"f") no lugar do do personagem (tela de criação: o sexo escolhido). "" = Game.body.
var body_override := ""
var hair_override := ""     ## penteado mostrado com body_override (tela de criação)
var cam: Camera3D
## Sem o equipamento do personagem (miniaturas de penteado: elmo e capuz esconderiam o cabelo).
var bare := false
## Modo retrato (miniaturas de penteado): câmera fechada no rosto, sem balançar.
var _face := false
## Quadros que ainda renderiza antes de congelar (freeze_after); -1 = renderiza sempre.
var _frames_left := -1


func _init(sz := Vector2(260, 340)) -> void:
	custom_minimum_size = sz
	stretch = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_2X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.5, 0.48)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.6, 0.5, 0)
	key.light_energy = 1.3
	key.light_color = Color(1, 0.93, 0.82)
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(-0.3, PI + 0.6, 0)
	rim.light_energy = 0.9
	rim.light_color = Color(0.6, 0.7, 1.0)
	vp.add_child(rim)
	cam = Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 1.15, 4.4)
	vp.add_child(cam)
	cam.look_at(Vector3(0, 0.98, 0))
	# pedestal
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.75
	cyl.bottom_radius = 0.8
	cyl.height = 0.08
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.16, 0.13, 0.1)
	dm.roughness = 0.9
	cyl.material = dm
	disc.mesh = cyl
	disc.position.y = -0.04
	vp.add_child(disc)
	pivot = Node3D.new()
	vp.add_child(pivot)
	pivot.rotation.y = _base
	refresh()
	Game.inventory_changed.connect(refresh)
	if _face:
		frame_face()


func refresh() -> void:
	if pivot == null:
		return
	var b := KnightLook.body_key(body_override if body_override != "" else Game.body)
	if model == null or KnightLook.body_of(model) != b:
		if model:
			model.queue_free()
		model = KnightLook.instance(b)
		pivot.add_child(model)
		_rig = KnightAnim.rig(model)
	if model:
		var eq: Dictionary = Game.equipment.duplicate()
		if bare:
			for k in eq:
				eq[k] = ""
		eq["hair"] = hair_override if body_override != "" else Game.hair
		if weapon_override != "":
			eq["weapon"] = weapon_override
			eq["offhand"] = ""   # a mão secundária equipada pode não combinar com a arma mostrada
		_look = KnightLook.apply(model, eq)
		var e := Game.weapon_enchant()
		if _ench_lv >= 0:
			EnchantFX.apply(_look, _ench_el, _ench_lv)
		elif weapon_override != "" and weapon_override != Game.equipment.weapon:
			EnchantFX.apply(_look, "", 0)   # o encanto é da arma equipada, não da mostrada
		else:
			EnchantFX.apply(_look, e.el, e.lv)


## Mostra a arma com um encanto escolhido (a prévia do nível que o ferreiro vai dar).
func show_enchant(element: String, level: int) -> void:
	_ench_el = element
	_ench_lv = level
	refresh()


## Mostra o corpo `b` ("m"/"f") sem gravar (tela de criação). "" volta para o do personagem.
func show_body(b: String) -> void:
	body_override = b
	refresh()


## Mostra o penteado `h` (HairStyles) sem gravar (tela de criação); vale junto com show_body.
func show_hair(h: String) -> void:
	hair_override = h
	refresh()


## Mostra uma arma sem equipá-la (a arma inicial da classe na tela de criação). "" volta para a equipada.
func show_weapon(id: String) -> void:
	weapon_override = id
	refresh()


## Câmera fechada no rosto, virado ~45° para mostrar rabo de cavalo e marias (miniaturas de penteado).
func frame_face() -> void:
	_face = true
	_user_turned = true
	if cam == null:
		return   # ainda fora da árvore: _ready aplica
	cam.position = Vector3(0, 1.66, 1.0)
	cam.look_at(Vector3(0, 1.58, 0))
	pivot.rotation.y = -0.75


## Renderiza mais `frames` quadros e congela a imagem (o viewport para de atualizar e de animar).
func freeze_after(frames: int) -> void:
	_frames_left = frames


func _process(delta: float) -> void:
	if _frames_left == 0:
		return
	if _frames_left > 0:
		_frames_left -= 1
		if _frames_left == 0 and vp:
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_idle += delta
	# balança em volta de uma vista 3/4 de frente (melhor para ver arma e armadura)
	if not _drag and not _user_turned and pivot:
		pivot.rotation.y = _base + sin(_idle * 0.7) * 0.45
	# mesma pose de parado do jogador (respiração e troca de peso entre as pernas)
	if not _rig.is_empty():
		var p := KnightAnim.idle_pose(_idle)
		KnightAnim.carry(_look, p)   # montante: as duas mãos no cabo, como no jogo
		KnightAnim.apply(_rig, p, 1.0 - exp(-14.0 * delta))
		KnightAnim.hold_weapon_upright(_look, _rig)
		KnightAnim.sway_ponytail(_rig, delta)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_drag = event.pressed
	elif event is InputEventMouseMotion and _drag:
		_user_turned = true
		pivot.rotation.y += event.relative.x * 0.012
