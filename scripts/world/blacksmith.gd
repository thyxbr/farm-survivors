class_name Blacksmith
extends "res://scripts/world/npc.gd"
## Doran, o ferreiro: martela na bigorna (com pausas de vez em quando), para e se vira quando o
## jogador chega e gesticula enquanto conversa. Cada golpe solta faíscas e o som da bigorna,
## sincronizados com a animação por uma method track injetada nos clipes em _ready.

enum State { WORK, PAUSE, IDLE, TALK }

const NEAR := 7.0     # mesmo raio em que o npc.gd vira para o jogador
const BLEND := 0.25
## Entrada e saída da pausa: o work_pause (Mixamo) começa e termina numa base aberta e com o corpo virado,
## longe da pose do martelar provisório; em 0,25 s as pernas cruzavam e o pé escorregava.
const PAUSE_BLEND := 0.5
## Clipes em que o martelo bate na bigorna (nome base, antes de clip()).
const STRIKE_CLIPS := ["work_hammer"]
## Tempo (s) do impacto em cada clipe, pelo nome resolvido por clip(): work_hammer provisório = quadro 13
## de 36 a 30 fps. O Mixamo não tinha martelar; se um dia entrar, vem com a própria chave ("mixamo/work_hammer").
const STRIKES := {"work_hammer": [0.433]}
## Clipes do Mixamo (parado, conversa e pausa), montados por tools/build_blacksmith_mixamo.gd. Entram como
## a biblioteca "mixamo" do AnimationPlayer e têm prioridade sobre os provisórios do .glb (ver clip()).
const MIXAMO_LIB := "res://assets/animations/blacksmith_mixamo.res"
const SPARK_COLOR := Color(1.0, 0.72, 0.25)
## Ferraria em coordenadas do ferreiro (frente = +Z): bigorna à frente, de lado (chifre à esquerda dele) e
## puxada para a direita, com o StrikePoint embaixo da face do martelo na batida; forja às costas com a boca
## virada para ele. Usado pelo mundo, por tools/blacksmith_shot.gd (que confere o golpe) e, nas coordenadas do
## Blender, por BS_BAR_*/BS_STRIKE em tools/blender/characters.py (barra, tenaz e alvo do martelo).
const ANVIL_OFFSET := Vector3(-0.18, 0, 0.6)
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
	skeleton = model.find_children("*", "Skeleton3D")[0]
	anim = model.find_children("*", "AnimationPlayer")[0]
	anim.animation_finished.connect(_on_anim_finished)
	if ResourceLoader.exists(MIXAMO_LIB) and not anim.has_animation_library("mixamo"):
		anim.add_animation_library("mixamo", load(MIXAMO_LIB))
	_attach_tools()
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
	_add_rest_tracks()
	_add_strike_tracks()
	if not headless:
		_sparks = FX.burst_particles(SPARK_COLOR, 20, 3.5, 0.035, 0.35, -9.0)
		_sparks.spread = 70.0
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
		# o diálogo pausa a árvore no solo: só durante a conversa o ferreiro segue checando o estado e
		# animando; em qualquer outro modal (menu, inventário, loja...) ele pausa junto com o jogo
		_set_always(true)
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
				_set_always(false)
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
	# get_tree().paused: segurança extra, a bigorna nunca toca com o jogo pausado
	if not _animate or state != State.WORK or get_tree().paused:
		return
	strikes += 1
	Sfx.play_at("anvil", strike_pos())
	if _sparks:
		_sparks.restart()


# ---------------------------------------------------------------- estados
func _work(blend := BLEND) -> void:
	state = State.WORK
	_cycles_left = randi_range(3, 5)
	_last_pos = 0.0
	_play("work_hammer", blend)


func _idle() -> void:
	state = State.IDLE
	_play("idle")


func _set_always(on: bool) -> void:
	var mode := Node.PROCESS_MODE_ALWAYS if on else Node.PROCESS_MODE_INHERIT
	process_mode = mode
	anim.process_mode = mode


func _play(clip_name: String, blend := BLEND) -> void:
	anim.play(clip(clip_name), blend)


## Conta as voltas do martelar (a posição do clipe em loop volta para o início); depois de 3 a 5,
## faz a pausa (limpar a testa) e volta a martelar.
func _count_cycle() -> void:
	var pos := anim.current_animation_position
	if pos < _last_pos:
		_cycles_left -= 1
		if _cycles_left <= 0:
			state = State.PAUSE
			_play("work_pause", PAUSE_BLEND)
	_last_pos = pos


func _on_anim_finished(anim_name: StringName) -> void:
	if state == State.PAUSE and String(anim_name) == clip("work_pause"):
		_work(PAUSE_BLEND)


# ---------------------------------------------------------------- montagem
## Injeta no clipe que vai tocar (clip(): o provisório ou o do Mixamo) uma method track que chama
## _on_strike no instante do impacto. Os clipes são recursos compartilhados do .glb: se outro ferreiro
## já injetou, a track está lá e é reaproveitada.
func _add_strike_tracks() -> void:
	var path := anim.get_node(anim.root_node).get_path_to(self)
	for base: String in STRIKE_CLIPS:
		var clip_name := clip(base)
		if not anim.has_animation(clip_name):
			continue
		if not STRIKES.has(clip_name):
			push_warning("Ferreiro: sem tempo de golpe em STRIKES para o clipe %s" % clip_name)
			continue
		var a := anim.get_animation(clip_name)
		if a.find_track(path, Animation.TYPE_METHOD) >= 0:
			continue
		var t := a.add_track(Animation.TYPE_METHOD)
		a.track_set_path(t, path)
		for time: float in STRIKES[clip_name]:
			a.track_insert_key(t, time, {"method": &"_on_strike", "args": []})


## Os clipes provisórios idle/talk/work_pause do .glb só animam tronco, braços e cabeça (o work_hammer anima
## também quadril e pernas, e aí as tracks dele já existem e ficam como estão); os do Mixamo animam tudo. Como o AnimationPlayer não é determinístico, um osso sem track no
## clipe atual fica na última pose: o passo da pausa ficaria preso nas pernas enquanto ele martela. Aqui cada
## clipe provisório ganha uma track constante na pose de repouso para os ossos que só o Mixamo anima.
## Recursos compartilhados do .glb: o find_track evita duplicar quando há mais de um ferreiro.
func _add_rest_tracks() -> void:
	if not anim.has_animation_library("mixamo"):
		return
	var tracks := {}   # NodePath -> [tipo, ...] das tracks dos clipes do Mixamo
	var lib := anim.get_animation_library("mixamo")
	for n in lib.get_animation_list():
		var m := lib.get_animation(n)
		for i in m.get_track_count():
			var key := m.track_get_path(i)
			if not tracks.has(key):
				tracks[key] = []
			if not m.track_get_type(i) in tracks[key]:
				tracks[key].append(m.track_get_type(i))
	var base := anim.get_animation_library("")
	for n in base.get_animation_list():
		var a := base.get_animation(n)
		for path: NodePath in tracks:
			var bone := skeleton.find_bone(path.get_concatenated_subnames())
			if bone < 0:
				continue
			var rest := skeleton.get_bone_rest(bone)
			for type: int in tracks[path]:
				if a.find_track(path, type) >= 0:
					continue
				var t := a.add_track(type)
				a.track_set_path(t, path)
				match type:
					Animation.TYPE_POSITION_3D:   # posições do quadril vêm normalizadas pelo motion_scale
						a.position_track_insert_key(t, 0.0, rest.origin / skeleton.motion_scale)
					Animation.TYPE_ROTATION_3D:
						a.rotation_track_insert_key(t, 0.0, rest.basis.get_rotation_quaternion())
					Animation.TYPE_SCALE_3D:
						a.scale_track_insert_key(t, 0.0, rest.basis.get_scale())


## O martelo e a tenaz vêm como malhas soltas com o pivô no punho (pose T); passam a seguir os ossos das mãos.
func _attach_tools() -> void:
	for pair: Array in [["Hammer", "RightHand"], ["Tongs", "LeftHand"]]:
		var tool := model.find_child(pair[0], true, false) as Node3D
		var i := skeleton.find_bone(pair[1])
		if tool == null or i < 0:
			continue
		var att := BoneAttachment3D.new()
		att.bone_name = pair[1]
		skeleton.add_child(att)
		var rest := skeleton.global_transform * skeleton.get_bone_global_rest(i)
		var xf := rest.affine_inverse() * tool.global_transform
		tool.reparent(att, false)
		tool.transform = xf
