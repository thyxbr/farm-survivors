extends SceneTree
## Monta as AnimationLibrary "mixamo" dos NPCs com esqueleto (ferreiro, Bram, Mira) a partir dos FBX baixados
## do Mixamo em assets/animations/mixamo/. Os .import dos FBX usam o mesmo BoneMap (SkeletonProfileHumanoid,
## renomear ossos, rest fixer) dos modelos, então as tracks já saem como %GeneralSkeleton:<osso do perfil> e
## tocam direto no esqueleto de qualquer um deles. Rode depois do --import:
##   godot --headless --path . --script res://tools/build_npc_mixamo.gd [-- blacksmith elder merchant]
## Sem argumentos monta as três. Imprime, por clipe, a origem: FBX ou SUBSTITUTO (<origem>).
## FBX faltando: idle/talk vêm de blacksmith_mixamo.res; excited/call, do clipe provisório do próprio .glb.
## O ferreiro não tem substitutos (o Mixamo não tinha martelar: work_hammer segue o provisório do .glb).

const DIR := "res://assets/animations/mixamo/"
const SMITH_LIB := "res://assets/animations/blacksmith_mixamo.res"
const SK := "%GeneralSkeleton:"

## npc -> saída, modelo (.glb: substitutos provisórios, pose de repouso e braço preso), braço preso e clipes.
## Clipe: fbx (nome do arquivo em DIR), loop e sub ("smith" = mesmo clipe do ferreiro, "glb" = do modelo).
const NPCS := {
	"blacksmith": {
		"out": "res://assets/animations/blacksmith_mixamo.res",
		"model": "",
		"clips": {
			"idle": {"fbx": "idle", "loop": true, "sub": ""},
			"talk": {"fbx": "talk", "loop": true, "sub": ""},
			# toca uma vez: o ferreiro espera o animation_finished para voltar a martelar
			"work_pause": {"fbx": "work_pause", "loop": false, "sub": ""},
		},
	},
	"elder": {
		"out": "res://assets/animations/elder_mixamo.res",
		"model": "res://assets/models/elder.glb",
		# o cajado vai na mão esquerda: o braço fica na pose staff_hold em todos os clipes, sem balançar
		"lock": {"pose": "staff_hold", "bones": ["LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand"]},
		"clips": {
			"idle": {"fbx": "elder_idle", "loop": true, "sub": "smith"},
			"excited": {"fbx": "elder_excited", "loop": false, "sub": "glb"},
			"talk": {"fbx": "elder_talk", "loop": true, "sub": "smith"},
		},
	},
	"merchant": {
		"out": "res://assets/animations/merchant_mixamo.res",
		"model": "res://assets/models/merchant.glb",
		"clips": {
			"idle": {"fbx": "merchant_idle", "loop": true, "sub": "smith"},
			"call": {"fbx": "merchant_call", "loop": false, "sub": "glb"},
			"talk": {"fbx": "merchant_talk", "loop": true, "sub": "smith"},
		},
	},
}


func _initialize() -> void:
	var which := OS.get_cmdline_user_args()
	if which.is_empty():
		which = PackedStringArray(NPCS.keys())   # o ferreiro primeiro: os outros usam os clipes dele
	var ok := true
	for npc in which:
		if not NPCS.has(npc):
			push_error("NPC desconhecido: " + npc)
			ok = false
			continue
		print("== ", npc)
		var origins := {}
		var lib := build(npc, DIR, origins)
		if lib == null:
			ok = false
			continue
		for c: String in origins:
			var a := lib.get_animation(c)
			print("  %s: %s, %.2f s, %d tracks, loop %s" % [c, origins[c], a.length, a.get_track_count(),
					a.loop_mode == Animation.LOOP_LINEAR])
		var err := ResourceSaver.save(lib, NPCS[npc].out, ResourceSaver.FLAG_COMPRESS)
		print("SALVO ", NPCS[npc].out, " err=", err)
		ok = ok and err == OK
	quit(0 if ok else 1)


## Monta a biblioteca do npc lendo os FBX de fbx_dir; origins recebe clipe -> "FBX" ou "SUBSTITUTO (<origem>)".
## Devolve null se faltar um clipe sem substituto.
static func build(npc: String, fbx_dir: String, origins: Dictionary) -> AnimationLibrary:
	var cfg: Dictionary = NPCS[npc]
	var model: Node3D = null
	if cfg.model != "":
		model = (load(cfg.model) as PackedScene).instantiate()
	var lib := AnimationLibrary.new()
	for c: String in cfg.clips:
		var clip: Dictionary = cfg.clips[c]
		var path: String = fbx_dir + clip.fbx + ".fbx"
		var a: Animation = null
		if ResourceLoader.exists(path):
			a = _first_clip(load(path) as PackedScene)
			origins[c] = "FBX"
		elif clip.sub == "smith":
			var smith := load(SMITH_LIB) as AnimationLibrary
			if smith and smith.has_animation(c):
				a = smith.get_animation(c).duplicate(true)
				origins[c] = "SUBSTITUTO (%s/%s)" % [SMITH_LIB.get_file(), c]
		elif clip.sub == "glb" and model:
			var ap := _player(model)
			if ap and ap.has_animation(c):
				a = ap.get_animation(c).duplicate(true)
				origins[c] = "SUBSTITUTO (%s/%s)" % [str(cfg.model).get_file(), c]
		if a == null:
			push_error("%s: falta %s e não há substituto" % [npc, path])
			if model:
				model.free()
			return null
		a.resource_name = c
		a.loop_mode = Animation.LOOP_LINEAR if clip.loop else Animation.LOOP_NONE
		a.set_meta("origem", origins[c])
		lib.add_animation(c, a)
	if model:
		var sk := model.find_children("*", "Skeleton3D")[0] as Skeleton3D
		if cfg.has("lock"):
			_lock_bones(lib, sk, _player(model).get_animation(cfg.lock.pose), cfg.lock.bones)
		_fill_rest(lib, sk)
		model.free()
	return lib


static func _player(m: Node) -> AnimationPlayer:
	var aps := m.find_children("*", "AnimationPlayer")
	return aps[0] if aps.size() > 0 else null


static func _first_clip(scene: PackedScene) -> Animation:
	if scene == null:
		return null
	var m := scene.instantiate()
	var ap := _player(m)
	var a: Animation = null
	if ap and ap.get_animation_list().size() > 0:
		a = ap.get_animation(ap.get_animation_list()[0]).duplicate(true)
	m.free()
	return a


## Em todos os clipes, os ossos dados ficam constantes na pose do clipe pose (ou no repouso, se ele não os anima).
static func _lock_bones(lib: AnimationLibrary, sk: Skeleton3D, pose: Animation, bones: Array) -> void:
	for b: String in bones:
		var path := NodePath(SK + b)
		var tp := pose.find_track(path, Animation.TYPE_ROTATION_3D)
		var rot: Quaternion = pose.rotation_track_interpolate(tp, 0.0) if tp >= 0 \
				else sk.get_bone_rest(sk.find_bone(b)).basis.get_rotation_quaternion()
		for c in lib.get_animation_list():
			var a := lib.get_animation(c)
			for i in range(a.get_track_count() - 1, -1, -1):
				if a.track_get_path(i) == path:
					a.remove_track(i)
			var t := a.add_track(Animation.TYPE_ROTATION_3D)
			a.track_set_path(t, path)
			a.rotation_track_insert_key(t, 0.0, rot)


## Um osso sem track no clipe atual fica na pose do clipe anterior (o AnimationPlayer não volta ao repouso):
## cada clipe ganha uma track constante no repouso do modelo para o que os outros clipes animam e ele não.
static func _fill_rest(lib: AnimationLibrary, sk: Skeleton3D) -> void:
	var tracks := {}   # NodePath -> [tipos]
	for c in lib.get_animation_list():
		var a := lib.get_animation(c)
		for i in a.get_track_count():
			var key := a.track_get_path(i)
			if not tracks.has(key):
				tracks[key] = []
			if not a.track_get_type(i) in tracks[key]:
				tracks[key].append(a.track_get_type(i))
	for c in lib.get_animation_list():
		var a := lib.get_animation(c)
		for path: NodePath in tracks:
			var bone := sk.find_bone(path.get_concatenated_subnames())
			if bone < 0:
				continue
			var rest := sk.get_bone_rest(bone)
			for type: int in tracks[path]:
				if a.find_track(path, type) >= 0:
					continue
				var t := a.add_track(type)
				a.track_set_path(t, path)
				match type:
					Animation.TYPE_POSITION_3D:   # posições do quadril vêm normalizadas pelo motion_scale
						a.position_track_insert_key(t, 0.0, rest.origin / sk.motion_scale)
					Animation.TYPE_ROTATION_3D:
						a.rotation_track_insert_key(t, 0.0, rest.basis.get_rotation_quaternion())
					Animation.TYPE_SCALE_3D:
						a.scale_track_insert_key(t, 0.0, rest.basis.get_scale())
