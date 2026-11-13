extends Node3D
## Foto de vários cavaleiros lado a lado, cada um vestido com um conjunto de equipamento (KnightLook),
## com a luz do jogo. Serve para conferir roupas e armaduras (assets/models/gear/*.glb) sem abrir o jogo.
## Precisa de janela (sem --headless) e do --import feito antes:
##   godot --path . --resolution 1800x900 res://tools/look_shot.tscn -- <saida.png> [conjunto] [3q|back|close] [run]
## run = pose de corrida no meio da passada.
## conjunto: "leves", "pesados", "todos" (padrão) ou ids separados por vírgula num só personagem.

const KNIGHT := preload("res://assets/models/knight.glb")
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
	for i in looks.size():
		var m := KNIGHT.instantiate() as Node3D
		add_child(m)
		m.position = Vector3((i - (looks.size() - 1) / 2.0) * 0.95, 0, 0)
		m.rotation_degrees.y = yaw
		KnightLook.apply(m, looks[i])
		if "run" in args:      # meio da passada de corrida: confere saias e mangas com as pernas abertas
			var r := KnightAnim.rig(m)
			KnightAnim.apply(r, KnightAnim.locomotion_pose(r, 0.25, 1.0, 1.0), 1.0)
		_models.append(m)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var vp := get_viewport().get_visible_rect().size
	var w := looks.size() * 0.95 + 0.2
	if "close" in args:
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
	get_viewport().get_texture().get_image().save_png(_out)
	print("SHOT ", _out)
	get_tree().quit()
