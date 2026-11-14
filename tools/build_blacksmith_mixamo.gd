extends SceneTree
## Monta assets/animations/blacksmith_mixamo.res (AnimationLibrary "mixamo" do ferreiro) a partir dos FBX
## baixados do Mixamo em assets/animations/mixamo/. Os .import dos FBX usam o mesmo BoneMap
## (SkeletonProfileHumanoid, renomear ossos, rest fixer) do blacksmith.glb, então as tracks já saem como
## %GeneralSkeleton:<osso do perfil> e tocam direto no esqueleto do ferreiro. Rode depois do --import:
##   godot --headless --path . --script res://tools/build_blacksmith_mixamo.gd
## O Mixamo não tinha um clipe bom de martelar: work_hammer segue o provisório do .glb.

const DIR := "res://assets/animations/mixamo/"
const OUT := "res://assets/animations/blacksmith_mixamo.res"
## clipe -> em loop? (work_pause toca uma vez: o ferreiro espera o animation_finished para voltar a martelar)
const CLIPS := {"idle": true, "talk": true, "work_pause": false}


func _initialize() -> void:
	var lib := AnimationLibrary.new()
	for c: String in CLIPS:
		var scene := load(DIR + c + ".fbx") as PackedScene
		if scene == null:
			push_error("Mixamo: falta %s%s.fbx" % [DIR, c])
			quit(1)
			return
		var m := scene.instantiate()
		var ap := m.find_children("*", "AnimationPlayer")[0] as AnimationPlayer
		var a := ap.get_animation(ap.get_animation_list()[0]).duplicate(true) as Animation
		m.free()
		a.resource_name = c
		a.loop_mode = Animation.LOOP_LINEAR if CLIPS[c] else Animation.LOOP_NONE
		lib.add_animation(c, a)
		print("%s: %.2f s, %d tracks, loop %s" % [c, a.length, a.get_track_count(), CLIPS[c]])
	var err := ResourceSaver.save(lib, OUT, ResourceSaver.FLAG_COMPRESS)
	print("SALVO ", OUT, " err=", err)
	quit(0 if err == OK else 1)
