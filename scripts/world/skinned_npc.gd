class_name SkinnedNPC
extends "res://scripts/world/npc.gd"
## Base dos NPCs com esqueleto (ferreiro, Bram, Mira): acha o AnimationPlayer e o Skeleton3D do modelo,
## carrega a biblioteca de clipes do Mixamo como "mixamo" (com prioridade sobre os provisórios do .glb, ver
## clip()), prende ferramentas soltas aos ossos, vira o close do diálogo para o osso Head e sabe se o diálogo
## aberto por ele continua aberto. As subclasses dizem a biblioteca (library_path) e cuidam dos estados.

const BLEND := 0.25

var anim: AnimationPlayer
var skeleton: Skeleton3D
var _animate := true       # falso no servidor dedicado: sem animação (nem golpes, faíscas ou som)
var _dialogue: Node = null


## Caminho da biblioteca de clipes do Mixamo deste NPC; "" = sem biblioteca (só os clipes do .glb).
func library_path() -> String:
	return ""


func _ready() -> void:
	super._ready()
	var sks := model.find_children("*", "Skeleton3D")
	var aps := model.find_children("*", "AnimationPlayer")
	skeleton = sks[0] if sks.size() > 0 else null
	anim = aps[0] if aps.size() > 0 else null
	_add_library(anim, library_path())
	var headless := DisplayServer.get_name() == "headless"
	# o smoke test roda headless, mas precisa da animação para conferir os NPCs
	_animate = anim != null and (not headless or "--smoketest" in OS.get_cmdline_user_args())
	if not _animate:
		if anim:
			anim.stop()
			anim.active = false
		set_process(false)


## Nome do clipe a tocar: a versão do Mixamo, se a biblioteca "mixamo" existir e tiver o clipe.
func clip(clip_name: String) -> String:
	return _resolve(anim, clip_name)


func _play(clip_name: String, blend := BLEND) -> void:
	anim.play(clip(clip_name), blend)


## O diálogo pausa a árvore no solo: só durante a conversa o NPC segue checando o estado e animando; em
## qualquer outro modal (menu, inventário, loja...) ele pausa junto com o jogo.
func _set_always(on: bool) -> void:
	var mode := Node.PROCESS_MODE_ALWAYS if on else Node.PROCESS_MODE_INHERIT
	process_mode = mode
	anim.process_mode = mode


func interact(player: Node) -> void:
	var world := get_tree().current_scene
	if world.get("modal") != null:
		return
	super.interact(player)
	_dialogue = world.get("modal")
	if _dialogue != null:
		_set_always(true)
		_on_dialogue_opened()


## Chamado quando interact() abriu o diálogo (já com PROCESS_MODE_ALWAYS). Sobrescrito pelas subclasses.
func _on_dialogue_opened() -> void:
	pass


## Se o diálogo aberto por interact() continua aberto. Ele fecha pelo caminho normal do mundo (world.modal
## deixa de ser ele); depois do queue_free a referência liberada compara igual a null, daí o is_instance_valid.
func dialogue_open() -> bool:
	return is_instance_valid(_dialogue) and get_tree().current_scene.get("modal") == _dialogue


## Fim da conversa: esquece o diálogo e volta a pausar junto com o jogo.
func _end_dialogue() -> void:
	_dialogue = null
	_set_always(false)


## Ponto entre os olhos, a partir da pose atual do osso Head.
func face_point() -> Vector3:
	var i := skeleton.find_bone("Head") if skeleton else -1
	if i < 0:
		return super.face_point()
	return skeleton.global_transform * skeleton.get_bone_global_pose(i) * Vector3(0, 0.1, 0.08)


## Prende a malha solta node_name (pivô no punho, pose T) ao osso bone.
func attach_to_bone(node_name: String, bone: String) -> void:
	_attach(model, skeleton, node_name, bone)


## Os clipes provisórios do .glb podem não animar todos os ossos que os do Mixamo animam. Como o
## AnimationPlayer não é determinístico, um osso sem track no clipe atual fica na última pose (o passo de um
## clipe do Mixamo ficaria preso nas pernas durante um provisório). Aqui cada clipe dado ganha uma track
## constante na pose de repouso para os ossos que a biblioteca "mixamo" anima e ele não; as tracks que ele já
## tem ficam como estão. Recursos compartilhados do .glb: o find_track evita duplicar com mais de um NPC.
func _add_rest_tracks(clips: Array) -> void:
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
	for n in clips:
		if not anim.has_animation(n):
			continue
		var a := anim.get_animation(n)
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


# ---------------------------------------------------------------- estáticos
## Para cenas que só mostram o modelo (caravana, praça...), sem NPC: prende as malhas soltas aos ossos
## ({"Staff": "LeftHand"}), carrega a biblioteca como "mixamo" e toca clip_name (versão do Mixamo, se houver).
## Funciona antes ou depois do add_child. Devolve o AnimationPlayer (null se o modelo não tiver).
static func pose_model(m: Node3D, attachments := {}, library := "", clip_name := "") -> AnimationPlayer:
	var sks := m.find_children("*", "Skeleton3D")
	var aps := m.find_children("*", "AnimationPlayer")
	var sk: Skeleton3D = sks[0] if sks.size() > 0 else null
	var ap: AnimationPlayer = aps[0] if aps.size() > 0 else null
	for node_name: String in attachments:
		_attach(m, sk, node_name, attachments[node_name])
	_add_library(ap, library)
	if ap and clip_name != "":
		var c := _resolve(ap, clip_name)
		if ap.has_animation(c):
			ap.play(c)
	return ap


static func _add_library(ap: AnimationPlayer, path: String) -> void:
	if ap and path != "" and ResourceLoader.exists(path) and not ap.has_animation_library("mixamo"):
		ap.add_animation_library("mixamo", load(path))


static func _resolve(ap: AnimationPlayer, clip_name: String) -> String:
	if ap and ap.has_animation_library("mixamo") and ap.get_animation_library("mixamo").has_animation(clip_name):
		return "mixamo/" + clip_name
	return clip_name


## Malha solta com o pivô no punho (pose T) passa a seguir o osso, mantendo onde está em relação a ele.
static func _attach(m: Node3D, sk: Skeleton3D, node_name: String, bone: String) -> void:
	var tool := m.find_child(node_name, true, false) as Node3D
	var i := sk.find_bone(bone) if sk else -1
	if tool == null or i < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	sk.add_child(att)
	# tudo relativo ao modelo: vale também fora da árvore (global_transform só existe dentro dela)
	var rest := _xform_to(sk, m) * sk.get_bone_global_rest(i)
	var xf := rest.affine_inverse() * _xform_to(tool, m)
	tool.reparent(att, false)
	tool.transform = xf


## Transformação de n relativa ao ancestral top.
static func _xform_to(n: Node3D, top: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	while n != top and n != null:
		xf = n.transform * xf
		n = n.get_parent() as Node3D
	return xf
