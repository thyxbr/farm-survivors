class_name Footprints
extends MultiMeshInstance3D
## Pegadas dos jogadores (o local e as réplicas dos outros) no chão de ground.gd: a cada STRIDE
## andado no chão, um pé deixa a marca. Só visual (não roda no servidor dedicado). As marcas ficam
## num anel de MAX quadrados num MultiMesh; o shader apaga cada uma sozinha quando a vida acaba,
## então só se mexe no MultiMesh quando alguém pisa. A aparência (neve, lama, poeira) é do shader.

const SHADER := preload("res://assets/shaders/footprint.gdshader")
const MAX := 480
## Tamanho do quadrado de cada pegada (m): a marca fica no meio, com folga para a borda de neve.
const QUAD := Vector2(0.26, 0.42)
## Folga acima do chão (o quadrado não briga com o chão pela profundidade).
const LIFT := 0.012
## Até quanto acima do chão os pés podem estar e ainda assim marcar (pulo não marca).
const MAX_GAP := 0.12
## Andou mais que isto num quadro: teleporte (portal, renascer), não um passo.
const TELEPORT := 3.0

var _mat: ShaderMaterial
var _body: CollisionObject3D
var _next := 0
var _clock := 0.0
## id do jogador -> {pos, acc, side}
var _walkers := {}


## noise_tex = o mesmo ruído do chão; body = a colisão do chão (só ela recebe pegadas).
func setup(noise_tex: Texture2D, body: CollisionObject3D) -> void:
	name = "Footprints"
	_body = body
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("noise_tex", noise_tex)
	_mat.set_shader_parameter("toon", ToonLook.enabled())
	var quad := QuadMesh.new()
	quad.orientation = PlaneMesh.FACE_Y
	quad.size = QUAD
	_mat.set_shader_parameter("quad_size", QUAD)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = MAX
	# todas começam escondidas: vida 0 já nasceu apagada
	for i in MAX:
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -100, 0)))
		mm.set_instance_custom_data(i, Color(-1000.0, 1.0, 0.0, 0.0))
	multimesh = mm
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# o anel inteiro cobre o mapa: sem isso o Godot cortaria as marcas quando a origem sai da tela
	custom_aabb = AABB(Vector3(-2000, -50, -2000), Vector3(4000, 100, 4000))
	top_level = true
	global_transform = Transform3D.IDENTITY


func _process(delta: float) -> void:
	_clock += delta
	_mat.set_shader_parameter("now", _clock)


func _physics_process(_delta: float) -> void:
	var seen := {}
	for p in get_tree().get_nodes_in_group("players"):
		var n := p as Node3D
		if n == null or not n.is_inside_tree():
			continue
		var id := n.get_instance_id()
		seen[id] = true
		_walk(id, n.global_position)
	for id in _walkers.keys():
		if not seen.has(id):
			_walkers.erase(id)


func _walk(id: int, pos: Vector3) -> void:
	var w: Dictionary = _walkers.get(id, {})
	if w.is_empty():
		_walkers[id] = {"pos": pos, "acc": 0.0, "side": 1}
		return
	var last: Vector3 = w.pos
	var step := Vector2(pos.x - last.x, pos.z - last.z)
	w.pos = pos
	var dist := step.length()
	if dist > TELEPORT:
		w.acc = 0.0
		return
	if dist < 0.0005:
		return
	w.acc += dist
	if w.acc < FootprintRules.STRIDE:
		return
	w.acc = fmod(w.acc, FootprintRules.STRIDE)
	w.side = -int(w.side)
	_stamp(FootprintRules.foot_pos(pos, step, w.side), step, w.side)


## Marca um pé em `at` se ali embaixo, rente aos pés, estiver o chão deste mapa.
func _stamp(at: Vector3, dir: Vector2, side: int) -> void:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.4, at + Vector3.DOWN * MAX_GAP)
	q.collision_mask = _body.collision_layer
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or hit.collider != _body:
		return
	var y: float = hit.position.y
	if at.y - y > MAX_GAP:
		return
	# fora de Valdoria/praça não há clima no chão (o shader recebe 0): marca de chão seco
	var s: Dictionary = Weather.state if Weather.fx != null else {}
	var life := FootprintRules.life(float(s.get("cover", 0.0)), float(s.get("snow", 0.0)), float(s.get("wet", 0.0)))
	var t := Transform3D(Basis(Vector3.UP, FootprintRules.yaw_of(dir)), Vector3(at.x, y + LIFT, at.z))
	multimesh.set_instance_transform(_next, t)
	multimesh.set_instance_custom_data(_next, Color(_clock, float(side), life, 0.0))
	_next = (_next + 1) % MAX


## Quantas pegadas ainda aparecem (para testes).
func visible_count() -> int:
	var n := 0
	for i in MAX:
		var c := multimesh.get_instance_custom_data(i)
		if _clock - c.r < c.b:
			n += 1
	return n
