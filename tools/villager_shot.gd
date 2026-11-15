extends Node3D
## Foto dos aldeões da Defesa da Cidade (ColonyVillager.make_model), um por ferramenta: na frente, parados;
## atrás, no meio do golpe/passo. Precisa de janela (sem --headless) e do --import:
##   godot --path . --resolution 1800x1000 res://tools/villager_shot.tscn -- <saida.png> [back] [zoom=<tamanho>,<x>] [hoe]
## hoe = só o aldeão da enxada, em seis fases da capina, de perfil.

const KINDS := ["lumber_camp", "quarry", "farm", "market", "archer_tower"]

var _frames := 0
var _out := ""
var _focus_x := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://villager_shot.png"
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
	var hoe := "hoe" in args
	for i in (6 if hoe else 0):   # só a capina: seis fases do ciclo, de perfil
		var v := ColonyVillager.make_model("farm")
		var m: Node3D = v.model
		add_child(m)
		m.position = Vector3((i - 2.5) * 1.7, 0, -2.4)
		m.rotation.y = PI / 2 - 0.35
		ColonyVillager.pose(v, "work", ColonyVillager.HOE_CYCLE * [0.0, 0.16, 0.32, 0.46, 0.65, 0.88][i])
		print("capina fase %d: mãos a %.2f m uma da outra" % [i, absf(v.get("hoe_gap", 0.0))])
	for i in (0 if hoe else KINDS.size()):
		var x := (i - (KINDS.size() - 1) / 2.0) * 1.7
		for row in 3:
			var v := ColonyVillager.make_model(KINDS[i])
			var m: Node3D = v.model
			add_child(m)
			m.position = Vector3(x, 0, -row * 2.4)
			m.rotation.y = 0.5
			if row == 1:
				ColonyVillager.pose(v, "work", ColonyVillager.SWING * 0.45)
			elif row == 2:
				ColonyVillager.pose(v, "walk", PI / 2)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 7.5
	for a in args:   # zoom=<tamanho>,<x>: fecha a câmera numa coluna (ex.: zoom=3.5,1.7 para o caixote)
		if a.begins_with("zoom="):
			var z := a.substr(5).split(",")
			cam.size = float(z[0])
			_focus_x = float(z[1]) if z.size() > 1 else 0.0
	cam.position = Vector3(3.0 + _focus_x, 5.0, 12.0 * (-1.0 if "back" in args else 1.0) - 2.4)
	add_child(cam)
	cam.look_at(Vector3(_focus_x, 0.9, -2.4))
	cam.current = true


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 20:
		return
	get_viewport().get_texture().get_image().save_png(_out)
	print("SHOT ", _out)
	get_tree().quit()
