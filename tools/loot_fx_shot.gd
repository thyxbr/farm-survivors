extends Node3D
## Foto do espólio de um abate saltando (LootFx): itens comuns, um raro e um épico, e ouro.
## Precisa de janela:  godot --path . --resolution 960x600 res://tools/loot_fx_shot.tscn -- <saida.png> [quadros]

var _f := 0
var _at := 24
var _out := "user://loot_fx.png"


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		_out = a[0]
	if a.size() > 1:
		_at = int(a[1])
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.45, 0.6, 0.75)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.8)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.4, 0)
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.35, 0.55, 0.3)
	ground.material_override = gm
	add_child(ground)
	var player := Node3D.new()
	player.add_to_group("player")
	add_child(player)
	player.position = Vector3(0, 0, 6)
	var cam := Camera3D.new()
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 3.2, 8.5), Vector3(0, 1.4, 0))
	cam.current = true


func _physics_process(_d: float) -> void:
	_f += 1
	if _f == 10:
		LootFx.play(self, Vector3(-2.2, 0, 0), 23, {"slime_gel": 1, "iron_ore": 1, "leather_cap": 1})
		LootFx.play(self, Vector3(2.4, 0, -1), 40, {"swift_boots": 1, "royal_gauntlets": 1})
	if _f == 10 + _at:
		get_viewport().get_texture().get_image().save_png(_out)
		print("SHOT ", _out)
		get_tree().quit()
