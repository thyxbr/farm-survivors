class_name KnightNPC
extends "res://scripts/world/npc.gd"
## NPC com o modelo do cavaleiro do jogador (knight.glb vestido pelo KnightLook, animado pelo KnightAnim):
## Kael, o guarda Rufus, Sir Osvaldo, o caçador Ravi, a patrulheira Sylvi e o minerador Bolgar. Cada um
## diz o visual (look, igual ao equipamento do jogador) e a escala. Quando o diálogo abre ele faz um gesto
## (gesture: emote do KnightEmotes) e, se show_off, ensaia gestos sozinho com o jogador por perto.

const KNIGHT := preload("res://assets/models/knight.glb")
## Intervalo entre os gestos ensaiados (s, sorteado) e a distância em que ele se exibe para o jogador.
const POSE_EVERY := Vector2(7.0, 12.0)
const SHOW_OFF_DIST := 16.0

var look := {}
var model_scale := 1.0
## Gesto ao abrir o diálogo ("" = nenhum) e se ensaia gestos sozinho.
var gesture := "acenar"
var show_off := false
var rig := {}
var _emote := ""
var _emote_t := 0.0
var _next_pose := 4.0
var _anim_t := 0.0
var _talking := false
var _animated := true


func _make_model() -> Node3D:
	return KNIGHT.instantiate()


func _ready() -> void:
	super._ready()
	model.scale = Vector3.ONE * model_scale
	KnightLook.apply(model, look)
	rig = KnightAnim.rig(model)
	_anim_t = randf() * 10.0
	_animated = DisplayServer.get_name() != "headless" or "--smoketest" in OS.get_cmdline_user_args()
	if not _animated:
		set_process(false)


func interact(player: Node) -> void:
	var world := get_tree().current_scene
	if world.get("modal") != null:
		return
	super.interact(player)
	if world.get("modal") != null:
		_talking = true
		process_mode = Node.PROCESS_MODE_ALWAYS   # o diálogo pausa o jogo: ele continua animando
		if gesture != "":
			_start_emote(gesture)


func _start_emote(kind: String) -> void:
	_emote = kind
	_emote_t = 0.0


func _process(delta: float) -> void:
	if not get_tree().paused:
		super._process(delta)
	if far and not _talking:
		return      # longe da câmera: fica na pose em que estava
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
		if show_off:
			_next_pose -= delta
			if _next_pose <= 0.0:
				_next_pose = randf_range(POSE_EVERY.x, POSE_EVERY.y)
				var player := get_tree().get_first_node_in_group("player") as Node3D
				if player and player.global_position.distance_to(global_position) < SHOW_OFF_DIST:
					_start_emote("comemorar" if randf() < 0.6 else "acenar")
	KnightAnim.apply(rig, pose, clampf(delta * 10.0, 0.0, 1.0))
