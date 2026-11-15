class_name Rival
extends "res://scripts/world/npc.gd"
## Kael, a Lâmina Carmesim: o rival do herói, parado no portão leste da vila. Usa o mesmo modelo do
## cavaleiro do jogador (knight.glb vestido pelo KnightLook, animado pelo KnightAnim): sobreveste da guarda,
## sabre e luvas, sem elmo para o rosto aparecer no close. De tempos em tempos ensaia a "pose heroica"
## (o emote de comemorar) e, quando o diálogo abre, faz a pose na hora.

const KNIGHT := preload("res://assets/models/knight.glb")
const LOOK := {"weapon": "steel_saber", "armor": "guard_surcoat", "hands": "leather_gloves",
	"feet": "leather_boots", "head": ""}
## Intervalo entre as poses ensaiadas (s, sorteado) e a distância em que ele se exibe para o jogador.
const POSE_EVERY := Vector2(7.0, 12.0)
const SHOW_OFF_DIST := 16.0

var rig := {}
var _emote := ""
var _emote_t := 0.0
var _next_pose := 4.0
var _anim_t := 0.0
var _talking := false
var _animate := true


func _init() -> void:
	npc_id = "rival"


func _make_model() -> Node3D:
	return KNIGHT.instantiate()


func _ready() -> void:
	super._ready()
	model.scale = Vector3.ONE * 1.02
	KnightLook.apply(model, LOOK)
	rig = KnightAnim.rig(model)
	_animate = DisplayServer.get_name() != "headless" or "--smoketest" in OS.get_cmdline_user_args()
	if not _animate:
		set_process(false)


func interact(player: Node) -> void:
	var world := get_tree().current_scene
	if world.get("modal") != null:
		return
	super.interact(player)
	if world.get("modal") != null:
		_talking = true
		process_mode = Node.PROCESS_MODE_ALWAYS   # o diálogo pausa o jogo: ele continua posando
		_start_emote("comemorar")


func _start_emote(kind: String) -> void:
	_emote = kind
	_emote_t = 0.0


func _process(delta: float) -> void:
	if not get_tree().paused:
		super._process(delta)
	_anim_t += delta
	if _talking and get_tree().current_scene.get("modal") == null:
		_talking = false
		process_mode = Node.PROCESS_MODE_INHERIT
	var pose: Dictionary
	if _emote != "":
		_emote_t += delta
		pose = KnightEmotes.pose(_emote, _emote_t)
		if _emote_t >= KnightEmotes.duration(_emote):
			_emote = ""
	else:
		pose = KnightAnim.idle_pose(_anim_t)
		_next_pose -= delta
		if _next_pose <= 0.0:
			_next_pose = randf_range(POSE_EVERY.x, POSE_EVERY.y)
			var player := get_tree().get_first_node_in_group("player") as Node3D
			if player and player.global_position.distance_to(global_position) < SHOW_OFF_DIST:
				_start_emote("comemorar" if randf() < 0.6 else "acenar")
	KnightAnim.apply(rig, pose, clampf(delta * 10.0, 0.0, 1.0))
