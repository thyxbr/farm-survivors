class_name Blacksmith
extends "res://scripts/world/npc.gd"
## Doran, o ferreiro: martela na bigorna (com pausas de vez em quando), para e se vira quando o
## jogador chega e gesticula enquanto conversa. Cada golpe solta faíscas e o som da bigorna,
## sincronizados com a animação por uma method track injetada nos clipes em _ready.

enum State { WORK, PAUSE, IDLE, TALK }

const NEAR := 7.0     # mesmo raio em que o npc.gd vira para o jogador
const BLEND := 0.25
## Tempo (s) do impacto do martelo em cada clipe: work_hammer provisório = quadro 16 de 36 a 30 fps.
const STRIKES := {"work_hammer": [0.533]}
const SPARK_COLOR := Color(1.0, 0.72, 0.25)
## Ferraria em coordenadas do ferreiro (frente = +Z): bigorna à frente, de lado (chifre à esquerda dele) e
## puxada para a direita, com o StrikePoint embaixo da face do martelo na batida; forja às costas com a boca
## virada para ele. Usado pelo mundo e por tools/blacksmith_shot.gd (que confere o golpe).
const ANVIL_OFFSET := Vector3(-0.24, 0, 0.6)
const ANVIL_YAW := PI / 2
const FORGE_OFFSET := Vector3(0, 0, -1.6)
const FORGE_YAW := 0.0

var state: State = State.WORK
var strikes := 0
var anvil: Node3D          # criado pelo mundo e atribuído antes do add_child
var anim: AnimationPlayer
var skeleton: Skeleton3D
var _animate := true       # falso no servidor dedicado: sem animação, golpes, faíscas nem som
var _sparks: CPUParticles3D
var _strike_point: Node3D
var _cycles_left := 0
var _last_pos := 0.0
var _dialogue: Node = null


func _init() -> void:
	npc_id = "blacksmith"


func _ready() -> void:
	super._ready()
	# o diálogo pausa a árvore no solo: o ferreiro continua checando o estado e animando
	process_mode = Node.PROCESS_MODE_ALWAYS
	skeleton = model.find_children("*", "Skeleton3D")[0]
	anim = model.find_children("*", "AnimationPlayer")[0]
	anim.process_mode = Node.PROCESS_MODE_ALWAYS
	anim.animation_finished.connect(_on_anim_finished)
	_attach_hammer()
	if anvil:
		_strike_point = anvil.find_child("StrikePoint", true, false)
	var headless := DisplayServer.get_name() == "headless"
	# o smoke test roda headless, mas precisa da animação e dos golpes para conferir o ferreiro
	_animate = not headless or "--smoketest" in OS.get_cmdline_user_args()
	if not _animate:
		anim.stop()
		anim.active = false
		set_process(false)
		return
	_add_strike_tracks()
	if not headless:
		_sparks = FX.burst_particles(SPARK_COLOR, 20, 3.5, 0.035, 0.35, -9.0)
		_sparks.spread = 70.0
		_sparks.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_sparks)
		_sparks.global_position = strike_pos()
	_work()


## Nome do clipe a tocar: a versão do Mixamo, se a biblioteca "mixamo" existir e tiver o clipe.
func clip(clip_name: String) -> String:
	if anim and anim.has_animation_library("mixamo") and anim.get_animation_library("mixamo").has_animation(clip_name):
		return "mixamo/" + clip_name
	return clip_name


## Onde o martelo bate na bigorna (coordenadas globais).
func strike_pos() -> Vector3:
	if _strike_point:
		return _strike_point.global_position
	return global_position + model.global_basis.z * 0.7 + Vector3.UP * 0.8


func interact(player: Node) -> void:
	var world := get_tree().current_scene
	if world.get("modal") != null:
		return
	super.interact(player)
	_dialogue = world.get("modal")
	if _dialogue != null:
		state = State.TALK
		_play("talk")


## Ponto entre os olhos, a partir da pose atual do osso Head.
func face_point() -> Vector3:
	var i := skeleton.find_bone("Head") if skeleton else -1
	if i < 0:
		return super.face_point()
	return skeleton.global_transform * skeleton.get_bone_global_pose(i) * Vector3(0, 0.1, 0.08)


func _process(delta: float) -> void:
	if not get_tree().paused:
		super._process(delta)   # marcador e virar aos poucos (para o jogador ou de volta à bigorna)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var near := player != null and player.global_position.distance_to(global_position) < NEAR
	match state:
		State.TALK:
			# o diálogo fechou pelo caminho normal do mundo (world.modal deixa de ser ele); depois do
			# queue_free a referência liberada compara igual a null, daí o is_instance_valid
			if not is_instance_valid(_dialogue) or get_tree().current_scene.get("modal") != _dialogue:
				_dialogue = null
				if near:
					_idle()
				else:
					_work()
		State.IDLE:
			if not near:
				_work()
		_:
			if near:
				_idle()
			elif state == State.WORK:
				_count_cycle()


func _on_strike() -> void:
	# a method track do work_hammer ainda dispara durante o blend de saída (BLEND): fora do WORK não bate
	if not _animate or state != State.WORK:
		return
	strikes += 1
	Sfx.play_at("anvil", strike_pos())
	if _sparks:
		_sparks.restart()


# ---------------------------------------------------------------- estados
func _work() -> void:
	state = State.WORK
	_cycles_left = randi_range(3, 5)
	_last_pos = 0.0
	_play("work_hammer")


func _idle() -> void:
	state = State.IDLE
	_play("idle")


func _play(clip_name: String) -> void:
	anim.play(clip(clip_name), BLEND)


## Conta as voltas do martelar (a posição do clipe em loop volta para o início); depois de 3 a 5,
## faz a pausa (limpar a testa) e volta a martelar.
func _count_cycle() -> void:
	var pos := anim.current_animation_position
	if pos < _last_pos:
		_cycles_left -= 1
		if _cycles_left <= 0:
			state = State.PAUSE
			_play("work_pause")
	_last_pos = pos


func _on_anim_finished(anim_name: StringName) -> void:
	if state == State.PAUSE and String(anim_name) == clip("work_pause"):
		_work()


# ---------------------------------------------------------------- montagem
## Injeta nos clipes uma method track que chama _on_strike no instante do impacto. Os clipes são
## recursos compartilhados do .glb: se outro ferreiro já injetou, a track está lá e é reaproveitada.
func _add_strike_tracks() -> void:
	var path := anim.get_node(anim.root_node).get_path_to(self)
	for clip_name: String in STRIKES:
		if not anim.has_animation(clip_name):
			continue
		var a := anim.get_animation(clip_name)
		if a.find_track(path, Animation.TYPE_METHOD) >= 0:
			continue
		var t := a.add_track(Animation.TYPE_METHOD)
		a.track_set_path(t, path)
		for time: float in STRIKES[clip_name]:
			a.track_insert_key(t, time, {"method": &"_on_strike", "args": []})


## O martelo vem como malha solta com o pivô no punho (pose T); passa a seguir o osso RightHand.
func _attach_hammer() -> void:
	var hammer := model.find_child("Hammer", true, false) as Node3D
	var i := skeleton.find_bone("RightHand")
	if hammer == null or i < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = "RightHand"
	skeleton.add_child(att)
	var rest := skeleton.global_transform * skeleton.get_bone_global_rest(i)
	var xf := rest.affine_inverse() * hammer.global_transform
	hammer.reparent(att, false)
	hammer.transform = xf
