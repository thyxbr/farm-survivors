extends Node3D
## Portal do Desafio na vila: abre o Desafio da Horda (arena de sobrevivência).

const PILLAR := preload("res://assets/models/ruin_pillar.glb")

var npc_id := "portal"   # lido pelo teste e pela depuração (--talk) junto com os NPCs
var _ring: MeshInstance3D
var _swirl_mat: StandardMaterial3D
var _light: OmniLight3D
var _t := 0.0


func _ready() -> void:
	add_to_group("interactable")
	for x in [-1.7, 1.7]:
		var p: Node3D = PILLAR.instantiate()
		p.position = Vector3(x, 0, 0)
		p.scale = Vector3.ONE * 0.85
		add_child(p)
		var body := StaticBody3D.new()
		body.position = Vector3(x, 1.6, 0)
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.42
		cyl.height = 3.2
		cs.shape = cyl
		body.add_child(cs)
		add_child(body)

	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.15
	torus.outer_radius = 1.32
	torus.rings = 40
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.75, 0.5, 1.0)
	rm.emission_enabled = true
	rm.emission = Color(0.65, 0.35, 1.0)
	rm.emission_energy_multiplier = 3.0
	torus.material = rm
	_ring.mesh = torus
	_ring.rotation.x = PI / 2
	_ring.position.y = 1.75
	add_child(_ring)

	var swirl := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.15
	disc.bottom_radius = 1.15
	disc.height = 0.02
	disc.radial_segments = 32
	_swirl_mat = StandardMaterial3D.new()
	_swirl_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_swirl_mat.albedo_color = Color(0.45, 0.2, 0.8, 0.55)
	_swirl_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_swirl_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	disc.material = _swirl_mat
	swirl.mesh = disc
	swirl.rotation.x = PI / 2
	swirl.position.y = 1.75
	swirl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(swirl)

	_light = OmniLight3D.new()
	_light.light_color = Color(0.7, 0.45, 1.0)
	_light.light_energy = 2.0
	_light.omni_range = 7.0
	_light.position = Vector3(0, 1.8, 0.6)
	add_child(_light)

	var sparks := CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.04
	sm.height = 0.08
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.albedo_color = Color(0.85, 0.65, 1.0)
	sm.material = pm
	sparks.mesh = sm
	sparks.amount = 30
	sparks.lifetime = 1.6
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 1.0
	sparks.direction = Vector3.UP
	sparks.spread = 30.0
	sparks.gravity = Vector3(0, 0.6, 0)
	sparks.initial_velocity_min = 0.2
	sparks.initial_velocity_max = 0.6
	sparks.position.y = 1.75
	add_child(sparks)

	var tag := Label3D.new()
	tag.text = "Portal do Desafio"
	tag.font_size = 40
	tag.outline_size = 8
	tag.pixel_size = 0.005
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position.y = 3.55
	tag.modulate = Color(0.85, 0.7, 1.0)
	add_child(tag)


func _process(delta: float) -> void:
	_t += delta
	_ring.rotation.y = sin(_t * 0.8) * 0.05
	_swirl_mat.albedo_color.a = 0.45 + 0.15 * sin(_t * 2.5)
	_light.light_energy = 1.8 + 0.4 * sin(_t * 3.1)


func interact_prompt() -> String:
	return "Entrar no Portal do Desafio"


func interact(_player: Node) -> void:
	var world = get_tree().current_scene
	if not world.has_method("open_dialogue"):
		return
	var best: Dictionary = Game.flags.get("horde_best", {})
	var rec := "Ainda sem recorde."
	if not best.is_empty():
		rec = "Recorde: %d rodadas, %d abates (nível %d)." % [int(best.round), int(best.kills), int(best.get("level", 1))]
	var text := "Uma fenda pulsa entre os pilares. Do outro lado, hordas sem fim aguardam na Arena.\n" \
		+ "Mate, colete gemas, suba de nível e escolha bênçãos a cada rodada. Saia quando quiser — ou caia tentando.\n"
	var enter := "Entrar no desafio"
	if Network.is_online():
		text += "Em grupo: os jogadores online recebem um convite e quem aceitar entra na mesma arena. " \
			+ "Quem cair volta no fim da rodada se alguém do grupo sobreviver.\n"
		enter = "Entrar no grupo do desafio" if not Network.horde_lobby.is_empty() else "Abrir o desafio (convidar o grupo)"
	world.open_dialogue("Portal do Desafio", [
		{"text": text + rec,
		"choices": [
			{"text": enter, "action": world.start_survival},
			{"text": "Agora não", "action": Callable()},
		]},
	])
