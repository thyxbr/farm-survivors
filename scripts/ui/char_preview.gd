class_name CharPreview
extends SubViewportContainer
## Prévia 3D do cavaleiro com o equipamento atual (atualiza ao equipar). Arraste para girar.

const KNIGHT := preload("res://assets/models/knight.glb")

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
	var cam := Camera3D.new()
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
	model = KNIGHT.instantiate()
	pivot.add_child(model)
	pivot.rotation.y = _base
	_rig = KnightAnim.rig(model)
	refresh()
	Game.inventory_changed.connect(refresh)


func refresh() -> void:
	if model:
		_look = KnightLook.apply(model, Game.equipment)
		var e := Game.weapon_enchant()
		if _ench_lv >= 0:
			EnchantFX.apply(_look, _ench_el, _ench_lv)
		else:
			EnchantFX.apply(_look, e.el, e.lv)


## Mostra a arma com um encanto escolhido (a prévia do nível que o ferreiro vai dar).
func show_enchant(element: String, level: int) -> void:
	_ench_el = element
	_ench_lv = level
	refresh()


func _process(delta: float) -> void:
	_idle += delta
	# balança em volta de uma vista 3/4 de frente (melhor para ver arma e armadura)
	if not _drag and not _user_turned and pivot:
		pivot.rotation.y = _base + sin(_idle * 0.7) * 0.45
	# mesma pose de parado do jogador (respiração e troca de peso entre as pernas)
	if not _rig.is_empty():
		KnightAnim.apply(_rig, KnightAnim.idle_pose(_idle), 1.0 - exp(-14.0 * delta))
		KnightAnim.hold_weapon_upright(_look, _rig)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_drag = event.pressed
	elif event is InputEventMouseMotion and _drag:
		_user_turned = true
		pivot.rotation.y += event.relative.x * 0.012
