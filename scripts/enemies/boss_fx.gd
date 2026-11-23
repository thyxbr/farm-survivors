class_name BossFX
extends RefCounted
## Efeitos das habilidades de chefe (Mãe-Verme): aviso em anel no chão, cristais brotando em anel, pedra caindo do
## teto e bolha de ácido em arco. Só visual (o dano é do servidor/solo); nada é criado no servidor sem tela.

const CYAN := Color(0.25, 0.85, 1.0)
const RED := Color(1.0, 0.18, 0.12)
const ACID := Color(0.5, 1.0, 0.18)


static func _root() -> Node3D:
	if DisplayServer.get_name() == "headless":
		return null
	return FX._scene() as Node3D


static func _flat(color: Color, alpha: float, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if emit <= 0.0 else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.albedo_color = Color(color, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Aviso da Onda de Cristais: anel vermelho deitado no chão (raio do meio `r`, largura `w`) que fica mais forte
## até `dur` segundos (a hora em que os cristais irrompem) e some.
static func ring_warning(pos: Vector3, r: float, w: float, dur: float) -> void:
	var root := _root()
	if root == null:
		return
	var mi := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = maxf(0.05, r - w / 2.0)
	tor.outer_radius = r + w / 2.0
	tor.rings = clampi(int(r * 6.0), 24, 96)
	tor.ring_segments = 4
	var m := _flat(RED, 0.18)
	tor.material = m
	mi.mesh = tor
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = pos + Vector3.UP * 0.06
	mi.scale = Vector3(1.0, 0.04, 1.0)
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.6, maxf(0.05, dur))
	tw.tween_callback(mi.queue_free)


## Cristais irrompendo em anel de raio `r` em volta de `pos`: `n` cachos de cristais 3D (WormFX) que sobem de dentro do
## chão num jorro de terra, ficam e afundam. `fury`: cristais vermelhos.
static func crystal_ring(pos: Vector3, r: float, n: int, fury := false) -> void:
	WormFX.crystal_ring(_root(), pos, r, n, fury)


## Pedra do Desmoronamento: cai do alto até `pos` em `fall` segundos e quebra o chão (WormFX).
static func falling_rock(pos: Vector3, fall: float) -> void:
	WormFX.falling_rock(_root(), pos, fall)


## Bolha de ácido em arco de `from` a `to` em `dur` segundos (o impacto é tratado por quem chamou).
static func lob(from: Vector3, to: Vector3, dur: float, height := 4.0) -> void:
	var root := _root()
	if root == null:
		return
	var g := WormFX.glob(root, 0.42)
	g.global_position = from
	var tw := g.create_tween()
	tw.tween_method(func(t: float) -> void: g.global_position = ThrowRules.arc(from, to, t, height), 0.0, 1.0,
		maxf(0.05, dur))
	tw.tween_callback(g.queue_free)


# ------------------------------------------------------------ folhas da Espinheira
static var _leaf_mesh: ArrayMesh
static var _leaf_ramp: Gradient


## Uma folha: losango pontudo dobrado ao meio, com as duas faces, sem luz (a cor vem da partícula).
static func leaf_mesh() -> ArrayMesh:
	if _leaf_mesh != null:
		return _leaf_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var b := Vector3(0, 0, -0.16)
	var t := Vector3(0, -0.02, 0.2)
	var l := Vector3(0.09, 0.035, 0.0)
	var r := Vector3(-0.09, 0.035, 0.0)
	for tri in [[b, l, t], [b, t, r], [b, t, l], [b, r, t]]:
		for v in tri:
			st.set_color(Color.WHITE)
			st.add_vertex(v)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(m)
	_leaf_mesh = st.commit()
	return _leaf_mesh


## Cores das folhas que caem: verdes na maioria, algumas tomadas pela corrupção (carmim).
static func _leaf_colors() -> Gradient:
	if _leaf_ramp == null:
		_leaf_ramp = Gradient.new()
		_leaf_ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
		_leaf_ramp.set_color(0, Color(0.25, 0.42, 0.17))
		_leaf_ramp.set_color(1, Color(0.76, 0.29, 0.42))
		_leaf_ramp.add_point(0.3, Color(0.42, 0.58, 0.22))
		_leaf_ramp.add_point(0.55, Color(0.16, 0.28, 0.12))
		_leaf_ramp.add_point(0.75, Color(0.54, 0.16, 0.36))
	return _leaf_ramp


static func _leaf_emitter(amount: int, radius: float, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = leaf_mesh()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3(0.3, -1.0, 0.2)
	p.spread = 70.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.9
	p.gravity = Vector3(0, -1.1, 0)
	p.damping_min = 0.4
	p.damping_max = 0.9
	p.tangential_accel_min = -1.2
	p.tangential_accel_max = 1.2
	p.particle_flag_rotate_y = true
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -160.0
	p.angular_velocity_max = 160.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	p.color_initial_ramp = _leaf_colors()
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.8, Color(1, 1, 1, 1))
	p.color_ramp = fade
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Folhas caindo sem parar da copa (`parent` = o pivô da copa; as folhas ficam no mundo enquanto ela anda).
static func leaf_fall(parent: Node3D, radius: float, height: float) -> CPUParticles3D:
	if _root() == null:
		return null
	var p := _leaf_emitter(16, radius, 4.2)
	parent.add_child(p)
	p.position = Vector3(0, height, 0)
	return p


## Rajada de folhas arrancadas (pancada que ela leva, golpe que ela dá, passada pesada).
static func leaf_burst(pos: Vector3, n: int, radius: float) -> void:
	var root := _root()
	if root == null:
		return
	var p := _leaf_emitter(n, radius, 2.6)
	p.one_shot = true
	p.explosiveness = 0.9
	p.spread = 180.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 3.2
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	root.get_tree().create_timer(3.4).timeout.connect(p.queue_free)
