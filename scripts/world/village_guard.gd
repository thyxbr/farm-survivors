class_name VillageGuard
extends KnightNPC
## Guarda da vila (MapEntity "guard" no vale.tscn): sobreveste da guarda, chapéu de ferro e arco. Fica no posto
## olhando para fora e, quando um monstro chega na zona protegida (VillageWard), vira, puxa o arco e atira.
## Aqui é só o visual (solo e cliente): quem derruba o monstro é o próprio Enemy (_ward_doom/guard_kill), no
## solo ou no servidor, VillageWard.DOOM segundos depois de entrar, sem XP nem loot para ninguém.

const LOOK := {"weapon": "hunter_bow", "armor": "guard_surcoat", "head": "kettle_hat", "hands": "iron_gauntlets",
	"feet": "iron_greaves"}
## Alcance do arco (m) e tempos do tiro (puxar, soltar e o descanso até o próximo).
const RANGE := 40.0
const DRAW := 0.35
const RELEASE := 0.5
const COOLDOWN := 0.25
const SCAN_EVERY := 0.15
## Velocidade da flecha (m/s) e altura de onde ela sai (m, mais ou menos no queixo).
const ARROW_SPEED := 55.0
const ARROW_HEIGHT := 1.5
const LINES := [
	"Fica tranquilo, aventureiro. Da cerca para dentro, monstro nenhum passa. Nem slime.",
	"Bicho que a guarda derruba não rende nada pra ninguém: nem XP, nem saque. Se quer a caça, cace lá fora.",
	"Os slimes ficam nos campos do norte e no ninho do sudoeste, os esqueletos no cemitério e nas ruínas. Goblin? Lá no leste, atrás da paliçada deles.",
]

var _target: Node3D = null
var _shot_t := -1.0       # tempo desde que começou a puxar (< 0 = sem tiro em andamento)
var _shot_fired := false
var _scan := 0.0
var _post_yaw := 0.0


func _init() -> void:
	npc_id = "guarda"
	look = LOOK
	model_scale = 1.03
	gesture = ""


func _ready() -> void:
	super._ready()
	_post_yaw = model.rotation.y
	_base_yaw = _post_yaw


func _build_dialogue() -> Array:
	return [StoryDialogue.p(LINES[randi() % LINES.size()])]


func _process(delta: float) -> void:
	if get_tree().paused or not _animated:
		super._process(delta)
		return
	_scan -= delta
	if _shot_t < 0.0 and _scan <= 0.0:
		_scan = SCAN_EVERY
		_target = _pick_target()
		if _target != null:
			_shot_t = 0.0
			_shot_fired = false
	if _shot_t < 0.0:
		super._process(delta)
		return
	_shot(delta)


## O monstro mais perto do guarda que entrou na zona protegida (com a mesma folga em que a guarda abate).
func _pick_target() -> Node3D:
	var best: Node3D = null
	var best_d := RANGE * RANGE
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead or e.horde or not VillageWard.inside(e.global_position, VillageWard.KILL_MARGIN):
			continue
		var d := global_position.distance_squared_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


## Vira para o alvo, puxa o arco, solta a flecha e volta ao posto.
func _shot(delta: float) -> void:
	_shot_t += delta
	_anim_t += delta
	var aim := _target.global_position if is_instance_valid(_target) else Vector3.INF
	if aim != Vector3.INF:
		var to := aim - global_position
		model.rotation.y = lerp_angle(model.rotation.y, atan2(to.x, to.z) - global_rotation.y, minf(1.0, 14.0 * delta))
	var pose := KnightAnim.idle_pose(_anim_t)
	if _shot_t < DRAW:
		KnightAnim.bow_draw_pose(pose, _shot_t / DRAW)
	else:
		if not _shot_fired:
			_shot_fired = true
			if aim != Vector3.INF:
				_fire(aim)
		KnightAnim.bow_release_pose(pose, clampf((_shot_t - DRAW) / RELEASE, 0.0, 1.0), 0.0)
	KnightAnim.apply(rig, pose, clampf(delta * 10.0, 0.0, 1.0))
	if _shot_t >= DRAW + RELEASE + COOLDOWN:
		_shot_t = -1.0
		_target = null


## Flecha só de enfeite (o abate é do Enemy): voa reta do guarda até o monstro e some num estalo.
func _fire(aim: Vector3) -> void:
	var from := global_position + Vector3.UP * ARROW_HEIGHT + model.global_basis.z * 0.4
	var to := aim + Vector3.UP * 0.7
	var arrow := Node3D.new()
	var shaft := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.03
	mesh.bottom_radius = 0.03
	mesh.height = 0.85
	mesh.radial_segments = 5
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.35, 0.18)
	m.emission_enabled = true
	m.emission = Color(0.9, 0.85, 0.6)
	m.emission_energy_multiplier = 0.5
	mesh.material = m
	shaft.mesh = mesh
	shaft.rotation.x = PI / 2
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arrow.add_child(shaft)
	get_tree().current_scene.add_child(arrow)
	arrow.global_position = from
	if from.distance_to(to) > 0.1:
		arrow.look_at(to, Vector3.UP)
	Sfx.play_at("bow_shot", from, 0.08, -4.0)
	var tw := arrow.create_tween()
	tw.tween_property(arrow, "global_position", to, from.distance_to(to) / ARROW_SPEED)
	tw.tween_callback(func() -> void:
		Sfx.play_at("arrow_hit", to, 0.08, -4.0)
		FX.burst(to, Color(0.9, 0.85, 0.7), 8, 3.0, 0.08, 0.35)
		arrow.queue_free())
