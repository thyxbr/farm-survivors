extends Node3D
## Foto das construções da Defesa da Cidade com a luz do jogo, níveis 1 a 3 em fileiras
## (assets/models/buildings/*.glb via ColonyVisuals). Precisa de janela (sem --headless) e do --import:
##   godot --path . --resolution 1800x1000 res://tools/building_shot.tscn -- <saida.png> [tipos] [back]
## tipos: ids separados por vírgula (padrão: todos). back = câmera por trás.

const ALL := ["town_hall", "house", "barracks", "market", "farm", "archer_tower", "cannon_tower", "mage_tower",
	"wall", "gate", "spikes"]

var _frames := 0
var _out := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://building_shot.png"
	var kinds: Array = ALL
	if args.size() > 1 and args[1] != "back":
		kinds = Array(args[1].split(","))
	WorldLighting.build(self)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.42, 0.22)
	ground.material_override = gm
	add_child(ground)
	var x := 0.0
	var span := 0.0
	var made: Array[Node3D] = []
	for kind in kinds:
		var w: float = ColonyData.BUILDINGS[kind].size.x + 1.5
		for lv in 3:
			var v := ColonyVisuals.make(kind, lv + 1)
			add_child(v)
			made.append(v)
			v.position = Vector3(x + w / 2.0, 0, -lv * 9.0)
		x += w
	span = x
	for v in made:
		v.position.x -= span / 2.0
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(span * 0.62, 20.0)
	var back := "back" in args
	cam.position = Vector3(-span * 0.12, 40.0, 50.0 * (-1.0 if back else 1.0) - 9.0)
	add_child(cam)
	cam.look_at(Vector3(0, 1.5, -9.0))
	cam.current = true


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 20:
		return
	get_viewport().get_texture().get_image().save_png(_out)
	print("SHOT ", _out)
	get_tree().quit()
