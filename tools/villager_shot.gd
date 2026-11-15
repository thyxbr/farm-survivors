extends Node3D
## Foto dos aldeões da Defesa da Cidade (ColonyVillager.make_model). Precisa de janela (sem --headless), do
## --import e de assets/animations/villager_mixamo.res (tools/build_npc_mixamo.gd):
##   godot --path . --resolution 1800x1000 res://tools/villager_shot.tscn -- <saida.png> [opções]
## Sem opções: um aldeão por ofício (serraria, pedreira, fazenda, mercado, torre); na frente parados, no meio
## trabalhando e atrás andando.
##   clip=<nome>     só esse clipe (idle, walk, hoe, chop, dig, carry_idle, carry_walk), em seis fases, uma por aldeão
##   kind=<tipo>     construção do aldeão das fases (padrão: a do ofício que usa o clipe)
##   yaw=<graus>     para onde os aldeões olham (0 = para a câmera; padrão 30; 90 = de perfil)
##   back            câmera por trás
##   zoom=<tam>,<x>  fecha a câmera (tamanho da vista ortogonal e x do centro)

const KINDS := ["lumber_camp", "quarry", "farm", "market", "archer_tower"]
const CLIP_KIND := {"hoe": "farm", "dig": "farm", "chop": "lumber_camp", "carry_idle": "market", "carry_walk": "market"}

var _frames := 0
var _out := ""
var _focus_x := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://villager_shot.png"
	var opt := {}
	for a in args:
		var kv := a.split("=")
		opt[kv[0]] = kv[1] if kv.size() > 1 else ""
	seed(7)
	WorldLighting.build(self)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(100, 100)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.42, 0.22)
	ground.material_override = gm
	add_child(ground)
	var yaw := deg_to_rad(float(opt.get("yaw", "30")))
	var size := 7.5
	if opt.has("clip"):   # seis fases do clipe, uma roupa por aldeão
		var clip: String = opt.clip
		var kind: String = opt.get("kind", CLIP_KIND.get(clip, "archer_tower"))
		size = 3.4
		for i in 6:
			_spawn(kind, 1 + i % 3, Vector3((i - 2.5) * 1.45, 0, -2.4), yaw, clip, i / 6.0)
	else:
		for i in KINDS.size():
			var x := (i - (KINDS.size() - 1) / 2.0) * 1.7
			var job: Dictionary = ColonyVillager.JOBS.get(KINDS[i], ColonyVillager.GUARD)
			_spawn(KINDS[i], 1 + i % 3, Vector3(x, 0, 0), yaw, "idle", 0.3)
			_spawn(KINDS[i], 1 + (i + 1) % 3, Vector3(x, 0, -2.4), yaw, job.work[0], 0.5)
			_spawn(KINDS[i], 1 + (i + 2) % 3, Vector3(x, 0, -4.8), yaw, "walk", 0.25)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	if opt.has("zoom"):
		var z: PackedStringArray = opt.zoom.split(",")
		size = float(z[0])
		_focus_x = float(z[1]) if z.size() > 1 else 0.0
	cam.size = size
	cam.position = Vector3(3.0 + _focus_x, 5.0, 12.0 * (-1.0 if opt.has("back") else 1.0) - 2.4)
	add_child(cam)
	cam.look_at(Vector3(_focus_x, 0.9, -2.4))
	cam.current = true


## Um aldeão da construção kind, com a roupa look, parado na fração phase do clipe do estado.
func _spawn(kind: String, look: int, pos: Vector3, yaw: float, state: String, phase: float) -> void:
	var v := ColonyVillager.make_model(kind, look)
	var m: Node3D = v.model
	add_child(m)
	m.position = pos
	m.rotation.y = yaw
	ColonyVillager.play(v, state, 0.0)
	var ap: AnimationPlayer = v.anim
	ap.seek(ColonyVillager.clip_length(v, state) * phase, true)
	ap.pause()
	(v.skeleton as Skeleton3D).force_update_all_bone_transforms()
	ColonyVillager.place_prop(v)
	var pr: Vector3 = v.to_model * (v.skeleton as Skeleton3D).get_bone_global_pose(v.bone_Right) * v.palm_Right if v.prop else Vector3.ZERO
	var pl: Vector3 = v.to_model * (v.skeleton as Skeleton3D).get_bone_global_pose(v.bone_Left) * v.palm_Left if v.prop else Vector3.ZERO
	print("%s %s %.0f%%: ferramenta %s, modo %s, palmas a %.2f m" % [kind, v.clip, phase * 100.0, v.tool, v.mode, pr.distance_to(pl)])


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 20:
		return
	get_viewport().get_texture().get_image().save_png(_out)
	print("SHOT ", _out)
	get_tree().quit()
