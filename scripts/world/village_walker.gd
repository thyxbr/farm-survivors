class_name VillageWalker
extends VillagerNPC
## Morador que passeia pela vila (Marta, Joca, Seu Lauro, Bia): anda pelo caminho `path` (pontos do mundo, ida e
## volta), para um pouco nos pontos com espera e para de vez quando o jogador chega perto, virado para ele, para
## conversar. Só enfeite: cada cliente anda o seu (o servidor não anima nem move), sem rede.
##
## Ponto do caminho: [x, z] ou [x, z, segundos parado ali]. Vem do MapEntity (kind "walker", params.path).

## Velocidade de passeio (m/s) e a distância em que o jogador faz o morador parar (e voltar a andar com folga).
const SPEED := 1.2
const STOP_NEAR := 2.6
const RESUME_FAR := 4.0
## Giro do corpo para o rumo do passeio (rad/s, por lerp).
const TURN := 6.0

var path: Array = []
var speed_scale := 1.0
var _i := 1
var _dir := 1
var _wait := 0.0
var _walking := false
var _held := false   # parado porque o jogador está perto


func _ready() -> void:
	super._ready()
	set_physics_process(false)
	if path.size() < 2:
		return
	var p0 := _point(0)
	global_position = Vector3(p0.x, _ground(p0.x, p0.z), p0.z)
	_wait = randf_range(0.0, 2.0)


## Ponto i do caminho (x, z) e a espera dele (y do Vector3 = segundos).
func _point(i: int) -> Vector3:
	var p: Array = path[i]
	return Vector3(float(p[0]), float(p[2]) if p.size() > 2 else 0.0, float(p[1]))


func _ground(x: float, z: float) -> float:
	var w := get_tree().current_scene if is_inside_tree() else null
	var g = w.get("ground") if w != null else null
	if g != null and g.has_method("height_at"):
		return g.height_at(x, z)
	return global_position.y


func _process(delta: float) -> void:
	super._process(delta)   # longe da câmera, virar para o jogador, diálogo
	if not _animate or far or path.size() < 2 or get_tree().paused or dialogue_open():
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var d := player.global_position.distance_to(global_position) if player else INF
	if _held:
		_held = d < RESUME_FAR
	elif d < STOP_NEAR:
		_held = true
	face_player_dist = 7.0 if _held else 0.0
	if _held:
		_set_walking(false)
		return
	if _wait > 0.0:
		_wait -= delta
		_set_walking(false)
		_face(_base_yaw, delta)
		return
	var t := _point(_i)
	var to := Vector3(t.x - global_position.x, 0, t.z - global_position.z)
	var step := SPEED * speed_scale * delta
	if to.length() <= step:
		global_position = Vector3(t.x, _ground(t.x, t.z), t.z)
		_wait = t.y
		if _i + _dir < 0 or _i + _dir >= path.size():
			_dir = -_dir
		_i += _dir
		return
	var mv := to.normalized() * step
	var np := global_position + mv
	np.y = _ground(np.x, np.z)
	global_position = np
	_base_yaw = atan2(mv.x, mv.z) - global_rotation.y
	_face(_base_yaw, delta)
	_set_walking(true)


func _face(yaw: float, delta: float) -> void:
	model.rotation.y = lerp_angle(model.rotation.y, yaw, minf(1.0, TURN * delta))


func _set_walking(on: bool) -> void:
	if on == _walking:
		return
	_walking = on
	var c := clip("walk" if on else "idle")
	if anim.has_animation(c):
		anim.play(c, BLEND, speed_scale if on else idle_speed)


func _idle() -> void:
	_walking = false
	super._idle()
