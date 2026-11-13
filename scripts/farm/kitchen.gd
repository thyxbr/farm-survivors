extends Node3D
## Caldeirão da Horta: fogueira com panelão borbulhante. E abre o menu de receitas.

const CAMPFIRE := preload("res://assets/models/campfire.glb")

var npc_id := "kitchen"   # lido pelo teste e pela depuração junto com os NPCs
var _soup_mat: StandardMaterial3D
var _light: OmniLight3D
var _bubbles: CPUParticles3D
var _t := 0.0
var _boost := 0.0   # chama e vapor mais fortes logo após cozinhar


func _ready() -> void:
	add_to_group("interactable")
	add_child(CAMPFIRE.instantiate())
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.75
	cyl.height = 1.2
	cs.shape = cyl
	cs.position.y = 0.6
	body.add_child(cs)
	add_child(body)

	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.13, 0.13, 0.14)
	iron.metallic = 0.7
	iron.roughness = 0.45
	# tripé
	for i in 3:
		var a := i * TAU / 3.0
		var leg := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.03
		lm.bottom_radius = 0.035
		lm.height = 1.45
		leg.mesh = lm
		leg.material_override = iron
		leg.position = Vector3(cos(a) * 0.55, 0.68, sin(a) * 0.55)
		leg.rotation = Vector3(sin(a) * 0.35, 0, -cos(a) * 0.35)
		add_child(leg)
	# panelão
	var pot := MeshInstance3D.new()
	var pm := SphereMesh.new()
	pm.radius = 0.5
	pm.height = 0.8
	pm.is_hemisphere = false
	pot.mesh = pm
	pot.material_override = iron
	pot.position.y = 0.78
	pot.scale = Vector3(1, 0.85, 1)
	add_child(pot)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.4
	tm.outer_radius = 0.47
	rim.mesh = tm
	rim.material_override = iron
	rim.position.y = 1.1
	add_child(rim)
	var soup := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.41
	sm.bottom_radius = 0.41
	sm.height = 0.02
	soup.mesh = sm
	_soup_mat = StandardMaterial3D.new()
	_soup_mat.albedo_color = Color(0.85, 0.55, 0.15)
	_soup_mat.emission_enabled = true
	_soup_mat.emission = Color(0.9, 0.5, 0.1)
	_soup_mat.emission_energy_multiplier = 0.6
	soup.material_override = _soup_mat
	soup.position.y = 1.08
	add_child(soup)
	# concha
	var ladle := MeshInstance3D.new()
	var lb := CylinderMesh.new()
	lb.top_radius = 0.02
	lb.bottom_radius = 0.02
	lb.height = 0.8
	ladle.mesh = lb
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.5, 0.33, 0.18)
	ladle.material_override = wood
	ladle.position = Vector3(0.18, 1.3, 0.05)
	ladle.rotation.z = -0.5
	add_child(ladle)

	_bubbles = CPUParticles3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.06
	bm.height = 0.12
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.albedo_color = Color(1, 1, 1, 0.35)
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.material = bmat
	_bubbles.mesh = bm
	_bubbles.amount = 18
	_bubbles.lifetime = 1.8
	_bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_bubbles.emission_sphere_radius = 0.3
	_bubbles.direction = Vector3.UP
	_bubbles.spread = 12.0
	_bubbles.gravity = Vector3(0, 0.4, 0)
	_bubbles.initial_velocity_min = 0.4
	_bubbles.initial_velocity_max = 0.8
	_bubbles.scale_amount_min = 0.8
	_bubbles.scale_amount_max = 2.2
	_bubbles.position.y = 1.15
	add_child(_bubbles)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.6, 0.25)
	_light.light_energy = 2.0
	_light.omni_range = 8.0
	_light.position.y = 0.9
	add_child(_light)

	var tag := Label3D.new()
	tag.text = "Caldeirão da Horta"
	tag.font_size = 40
	tag.outline_size = 8
	tag.pixel_size = 0.005
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position.y = 2.2
	tag.modulate = Color(1, 0.8, 0.5)
	add_child(tag)


func _process(delta: float) -> void:
	_t += delta
	_boost = max(0.0, _boost - delta)
	_light.light_energy = 1.8 + 0.35 * sin(_t * 8.0) + 0.15 * sin(_t * 21.0) + _boost * 2.0
	_soup_mat.emission_energy_multiplier = 0.5 + 0.15 * sin(_t * 3.0) + _boost


## Chamado pelo menu de receitas ao cozinhar: muda a cor do caldo e solta vapor.
func celebrate(color: Color) -> void:
	_boost = 1.2
	_soup_mat.albedo_color = color
	_soup_mat.emission = color
	FX.burst(global_position + Vector3.UP * 1.3, color, 30, 3.0, 0.1, 1.0, 2.0)
	FX.burst(global_position + Vector3.UP * 1.3, Color(1, 1, 1, 0.6), 16, 1.6, 0.18, 1.4, 1.5)


func interact_prompt() -> String:
	return "Cozinhar no Caldeirão"


func interact(_player: Node) -> void:
	var world := get_tree().current_scene
	if world.has_method("open_cooking"):
		world.open_cooking(self)
