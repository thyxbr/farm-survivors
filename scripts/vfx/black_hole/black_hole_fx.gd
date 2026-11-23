class_name BlackHoleFX
extends Node3D
## Buraco Negro: disco de acreção deitado no chão, feito em código sobre duas pinturas (braços em espiral e névoa,
## claro em fundo preto, tingidas pelo raio em hole_disc.gdshader), com a esfera preta no miolo, brasas que sobem
## em volta e uma luz magenta. Fica enquanto o dono existir: quem usa muda `radius` (o limite do dano, onde corre o
## aro aceso) e `intensity` (0 a 1, para nascer e sumir) a cada quadro.
## Em jogo: as Zonas de Vazio do Arauto do Abismo (VoidZone).

const ARMS := preload("res://assets/vfx/black_hole/espiral_bracos.png")
const HAZE := preload("res://assets/vfx/black_hole/espiral_nevoa.png")
const DISC := preload("res://shaders/black_hole/hole_disc.gdshader")
const CORE := preload("res://shaders/black_hole/hole_core.gdshader")
## Os braços pintados acabam nesta fração do meio-lado da imagem: o plano é esticado para eles acabarem no raio.
const ARMS_END := 0.88
## Raio da esfera do miolo, em fração do raio do disco.
const CORE_R := 0.14

var radius := 3.0
var intensity := 1.0

var _disc: MeshInstance3D
var _core: MeshInstance3D
var _embers: CPUParticles3D
var _light: OmniLight3D


func _ready() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	var dm := ShaderMaterial.new()
	dm.shader = DISC
	dm.set_shader_parameter("arms", ARMS)
	dm.set_shader_parameter("haze", HAZE)
	dm.set_shader_parameter("rim_at", ARMS_END)
	_disc = MeshInstance3D.new()
	_disc.mesh = plane
	_disc.material_override = dm
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_disc.position.y = 0.07
	_disc.set_instance_shader_parameter("seed", randf() * TAU)
	add_child(_disc)

	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 24
	ball.rings = 12
	var cm := ShaderMaterial.new()
	cm.shader = CORE
	_core = MeshInstance3D.new()
	_core.mesh = ball
	_core.material_override = cm
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)

	_embers = CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.045, 0.045)
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	em.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	em.vertex_color_use_as_albedo = true
	q.material = em
	_embers.mesh = q
	_embers.amount = 26
	_embers.lifetime = 2.6
	_embers.lifetime_randomness = 0.5
	_embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_embers.emission_ring_axis = Vector3.UP
	_embers.emission_ring_height = 0.1
	_embers.direction = Vector3.UP
	_embers.spread = 35.0
	_embers.initial_velocity_min = 0.15
	_embers.initial_velocity_max = 0.6
	_embers.gravity = Vector3(0.0, 0.25, 0.0)
	_embers.radial_accel_min = -0.9
	_embers.radial_accel_max = -0.3
	_embers.tangential_accel_min = 0.5
	_embers.tangential_accel_max = 1.4
	_embers.scale_amount_min = 0.5
	_embers.scale_amount_max = 1.5
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.6, 0.15))
	ramp.set_color(1, Color(1.0, 0.2, 0.55))
	_embers.color_initial_ramp = ramp
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	_embers.color_ramp = fade
	_embers.position.y = 0.15
	_embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_embers)

	_light = OmniLight3D.new()
	_light.light_color = Color(0.85, 0.3, 1.0)
	_light.shadow_enabled = false
	_light.omni_attenuation = 1.3
	add_child(_light)
	_apply()


func _process(_delta: float) -> void:
	_apply()


func _apply() -> void:
	var side := radius * 2.0 / ARMS_END
	_disc.scale = Vector3(side, 1.0, side)
	_disc.set_instance_shader_parameter("intensity", intensity)
	var cr := radius * CORE_R * (0.4 + 0.6 * intensity)
	_core.scale = Vector3.ONE * cr
	_core.position.y = cr * 0.35
	_core.visible = intensity > 0.05
	_embers.emission_ring_inner_radius = radius * 0.35
	_embers.emission_ring_radius = radius * 0.95
	_embers.emitting = intensity > 0.3
	_light.position.y = 0.6 + radius * 0.12
	_light.omni_range = radius * 1.6
	_light.light_energy = 0.9 * intensity
