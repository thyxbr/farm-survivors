extends Node3D
## Foto de vários cavaleiros lado a lado, cada um vestido com um conjunto de equipamento (KnightLook),
## com a luz do jogo. Serve para conferir roupas e armaduras (assets/models/gear/*.glb) sem abrir o jogo.
## Precisa de janela (sem --headless) e do --import feito antes:
##   godot --path . --resolution 1800x900 res://tools/look_shot.tscn -- <saida.png> [conjunto] [3q|back|side|close|wide|head|bust|waist|torso|legs|hands] [run|arms|block] [fem] [wait=<s>]
## run = pose de corrida no meio da passada; fem = corpo feminino; wait = segundos antes da foto (efeitos animados).
## conjunto: "leves", "pesados", "todos" (padrão) ou ids separados por vírgula num só personagem;
## "cada:id1,id2,..." põe um personagem por id (para comparar armas lado a lado); "id1+id2" veste as duas
## peças no mesmo personagem (conjuntos lado a lado: "cada:lich_crown+lich_robe,frost_crown+frost_robe").

const SETS := {
	"leves": [
		{},
		{"armor": "traveler_tunic", "head": "wool_hood", "feet": "leather_boots"},
		{"armor": "leather_armor", "head": "leather_cap", "hands": "leather_gloves", "feet": "leather_boots"},
		{"armor": "ranger_vest", "head": "ranger_hood", "hands": "archer_bracers", "feet": "swift_boots"},
		{"armor": "mage_robe", "head": "wizard_hat", "hands": "spellweaver_gloves", "feet": "leather_boots"},
	],
	"pesados": [
		{"armor": "chain_mail", "head": "iron_helm", "hands": "leather_gloves", "feet": "reinforced_boots"},
		{"armor": "chain_mail", "head": "kettle_hat", "hands": "iron_gauntlets", "feet": "reinforced_boots"},
		{"armor": "guard_surcoat", "head": "guard_greathelm", "hands": "iron_gauntlets", "feet": "iron_greaves"},
		{"armor": "royal_plate", "head": "knight_helm", "hands": "iron_gauntlets", "feet": "iron_greaves"},
		{"armor": "dragon_plate", "head": "guard_greathelm", "hands": "iron_gauntlets", "feet": "reinforced_boots"},
	],
}

var _frames := 0
var _out := ""
var _models: Array[Node3D] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://look_shot.png"
	var which: String = args[1] if args.size() > 1 else "todos"
	var looks: Array = []
	if SETS.has(which):
		looks = SETS[which]
	elif which == "todos":
		looks = SETS.leves + SETS.pesados
	elif which.begins_with("cada:"):
		for ids in which.substr(5).split(","):
			var l := {}
			for id in ids.split("+"):       # "a+b" veste as duas peças no mesmo personagem
				l[ItemDB.slot_of(id)] = id
			looks.append(l)
	else:
		var l := {}
		for id in which.split(","):
			var slot := ItemDB.slot_of(id)
			if slot != "":
				l[slot] = id
		looks = [l]
	WorldLighting.build(self)
	var yaw := 0.0
	if "3q" in args:
		yaw = -35.0
	elif "back" in args:
		yaw = 180.0
	elif "side" in args:
		yaw = -90.0
	for i in looks.size():
		var m := KnightLook.instance("f" if "fem" in args else "m")    # fem = corpo feminino (roupas _f)
		add_child(m)
		var gap := 2.5 if "wide" in args else 0.95    # asas abertas pedem mais espaço entre os personagens
		m.position = Vector3((i - (looks.size() - 1) / 2.0) * gap, 0, 0)
		m.rotation_degrees.y = yaw
		KnightLook.apply(m, looks[i])
		if "arms" in args:     # braços abertos e levantados: confere ombros e mangas
			for side in [["ArmL", -1.0], ["ArmR", 1.0]]:
				var arm := m.find_child(side[0], true, false) as Node3D
				if arm:
					arm.rotation_degrees.z = 75.0 * side[1]
		if "block" in args:    # escudo levantado (KnightAnim.shield_block_pose)
			var rb := KnightAnim.rig(m)
			var pb := KnightAnim.rest_pose()
			KnightAnim.shield_block_pose(pb, 1.0, 0.0, 0.0)
			KnightAnim.apply(rb, pb, 1.0)
		if "run" in args:      # meio da passada de corrida: confere saias e mangas com as pernas abertas
			var r := KnightAnim.rig(m)
			KnightAnim.apply(r, KnightAnim.locomotion_pose(r, 0.25, 1.0, 1.0), 1.0)
		_models.append(m)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var vp := get_viewport().get_visible_rect().size
	var w := looks.size() * 0.95 + 0.2
	if "legs" in args:
		cam.size = 0.85
		cam.position = Vector3(0, 0.4, 4.0)
	elif "hands" in args:
		cam.size = 0.6
		cam.position = Vector3(0, 0.98, 4.0)
	elif "torso" in args:
		cam.size = 1.25
		cam.position = Vector3(0, 1.08, 4.0)
	elif "head" in args:      # chapéu ou elmo inteiro, com aba, ponta e pingentes
		cam.size = 1.0
		cam.position = Vector3(0, 1.8, 4.0)
	elif "bust" in args:      # do chapéu à cintura: gola, ombros e peito
		cam.size = 1.25
		cam.position = Vector3(0, 1.55, 4.0)
	elif "waist" in args:     # do peito ao joelho: tronco, faixa e o que pende dela
		cam.size = 1.0
		cam.position = Vector3(0, 0.95, 4.0)
	elif "wide" in args:      # asas abertas: mais alto e mais largo que o corpo
		cam.size = maxf(2.7, (looks.size() * 2.5 + 0.2) * vp.y / vp.x)
		cam.position = Vector3(0, 1.15, 4.0)
	elif "close" in args:
		cam.size = 0.75
		cam.position = Vector3(0, 1.5, 4.0)
	else:
		cam.size = maxf(2.05, w * vp.y / vp.x)
		cam.position = Vector3(0, 0.95, 4.0)
	add_child(cam)
	cam.current = true


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 12:
		return
	# wait=<s>: espera esse tempo antes da foto (efeitos animados nos frisos, faixas de brilho)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("wait=") and Time.get_ticks_msec() < float(a.substr(5)) * 1000.0:
			return
	get_viewport().get_texture().get_image().save_png(_out)
	print("SHOT ", _out)
	get_tree().quit()
