extends SceneTree
## Foto das poses de ataque dos monstros humanoides (EnemyPose), quadro a quadro, numa fileira por monstro.
## Precisa de janela (sem --headless) e do --import feito antes:
##   godot --path . --resolution 1800x600 --script res://tools/enemy_pose_shot.gd -- <saida.png> <linha> [side]
## <linha> = índice em ROWS (um monstro por foto). `side` põe a câmera de lado (bom para conferir a linha da
## flecha); sem ele, de frente-lado (3/4).

const ROWS := [
	# [tipo, attack_kind, tempos (s) dentro do ataque; -1 = andando]
	["goblin_arqueiro", "shoot", [-1.0, 0.1, 0.35, 0.58, 0.7, 0.95]],
	["esqueleto_arqueiro", "shoot", [-1.0, 0.1, 0.35, 0.58, 0.7, 0.95]],
	["esqueleto_mago", "shoot", [-1.0, 0.3, 0.55, 0.65, 0.8, 0.95]],
	["goblin_xama", "cast", [-1.0, 0.3, 0.6, 0.8, 0.95, 1.2]],
	["lich", "swing", [-1.0, 0.25, 0.45, 0.6, 0.75, 0.9]],
	["goblin", "swing", [-1.0, 0.25, 0.45, 0.55, 0.7, 0.9]],
]
const HIT := {"shoot": 0.6, "cast": 0.75, "swing": 0.5}
const DUR := {"shoot": 1.0, "cast": 1.3, "swing": 0.95}

var _frames := 0
var _out := ""
var _side := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0]
	var only := int(args[1])
	_side = "side" in args
	WorldLighting.build(root)
	var types: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance/enemies.json"))
	if types.has("types"):
		types = types.types
	var sc := 1.0
	for row in [only]:
		var kind: String = ROWS[row][0]
		var data: Dictionary = types[kind].duplicate()
		data.erase("tint")      # a tintura vem como texto no JSON (o Balance converte); a foto é da pose
		var times: Array = ROWS[row][2]
		for col in times.size():
			var m := EnemyModel.instance(kind, data)
			root.add_child(m)
			m.scale = Vector3.ONE * float(data.scale)
			sc = float(data.scale)
			m.position = Vector3(col * 1.7 * sc, 0, 0)
			m.rotation.y = -PI / 2 if _side else -0.6     # alvo para a direita da foto
			_pose(m, data, ROWS[row][1], times[col])
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	floor_mi.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.47, 0.6, 0.36)
	floor_mi.material_override = fm
	root.add_child(floor_mi)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 3.4 * sc
	var c := Vector3(4.25 * sc, 0.85 * sc, 0.0)
	root.add_child(cam)
	cam.look_at_from_position(c + Vector3(0, 1.5, 12.0), c)
	cam.current = true


func _pose(m: Node3D, data: Dictionary, kind: String, t: float) -> void:
	var parts := {}
	for n in ["LegL", "LegR", "ArmL", "ArmR", "ElbowL", "ElbowR", "Body", "Head"]:
		parts[n] = m.find_child(n, true, false)
	parts["Bow"] = m.find_child("Opt_Bow", true, false)
	parts["Staff"] = m.find_child("Opt_Staff", true, false)
	var weapon := EnemyPose.weapon_of(data.get("gear", []))
	if weapon == "bow":
		var nock := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.012
		cyl.bottom_radius = 0.012
		cyl.height = EnemyPose.ARROW_LEN
		nock.mesh = cyl
		parts.Body.add_child(nock)
		parts["Nock"] = nock
	var rig := EnemyPose.rig(parts)
	var walking := t < 0.0
	var st := {"state": "chase" if walking else "attack", "kind": kind, "t": maxf(t, 0.0), "ht": HIT[kind],
		"dur": DUR[kind], "amp": 0.8 if walking else 0.0, "s": 0.8 if walking else 0.0, "weapon": weapon}
	EnemyPose.humanoid(parts, rig, st, 1.0, 1.0)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 12:
		return false
	root.get_texture().get_image().save_png(_out)
	print("SHOT ", _out)
	return true
