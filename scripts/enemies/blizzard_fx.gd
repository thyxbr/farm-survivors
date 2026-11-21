class_name BlizzardFX
extends RefCounted
## Efeitos da Sentinela da Nevasca (chefe do Pico): o aviso em cone que gira com o sopro, o jato de frio, a estaca
## de gelo caindo do teto, a nevasca que enche a sala e as partículas de geada que caem do corpo dela.
## Só visual (o dano é do servidor/solo); nada é criado no servidor sem tela. Gelo de monstro: cristal lapidado
## (FXToon.crystal) e tufos redondos (FXToon.puff) com núcleo escuro e borda carmim (RIME, FROSTBITE).

const CONE_SHADER := preload("res://shaders/fx_cone_warning.gdshader")
## Gelo de monstro: miolo azul-noite, corpo de gelo e a borda carmim dos golpes inimigos.
const RIME := {"core": Color(0.06, 0.08, 0.2), "mid": Color(0.42, 0.8, 1.0), "edge": Color(1.0, 0.22, 0.34)}
## Cristal de gelo de monstro: faces claras de gelo, sombra carmim escura.
const FROSTBITE := {"core": Color(0.86, 0.97, 1.0), "mid": Color(0.36, 0.7, 0.98), "edge": Color(0.5, 0.05, 0.22)}
## Brasa do braseiro (fogo de verdade: é o abrigo do jogador, não um golpe).
const WARM := Color(1.0, 0.62, 0.22)

static var _cone_mesh: PlaneMesh
static var _flake_mesh: QuadMesh
static var _mote_mesh: ArrayMesh


static func _root() -> Node3D:
	if DisplayServer.get_name() == "headless":
		return null
	return FX._scene() as Node3D


# ------------------------------------------------------------ aviso do sopro
## Aviso do Sopro no chão: quem chama atualiza `yaw`, `ahead` (arco que falta, com sinal) e `reveal` a cada quadro
## e chama `finish()` quando o sopro acaba (some sozinho se quem o criou sumir).
class ConeWarning extends MeshInstance3D:
	var yaw := 0.0
	var ahead := 0.0
	var reveal := 0.0
	var owner_ref: WeakRef
	var _done := -1.0
	var _t := 0.0

	func finish() -> void:
		if _done < 0.0:
			_done = 0.0

	func _process(delta: float) -> void:
		_t += delta
		if _done < 0.0 and (owner_ref == null or owner_ref.get_ref() == null):
			finish()
		if _done >= 0.0:
			_done += delta
			if _done >= 0.3:
				queue_free()
				return
		rotation.y = yaw
		set_instance_shader_parameter("ahead", ahead)
		set_instance_shader_parameter("reveal", reveal)
		set_instance_shader_parameter("run", _t)
		set_instance_shader_parameter("fade", clampf(_done / 0.3, 0.0, 1.0) if _done >= 0.0 else 0.0)


## Cria o aviso em cone com o bico em `pos`, alcance `reach` m e meia abertura `half_deg` graus.
static func cone_warning(pos: Vector3, reach: float, half_deg: float, owner: Node) -> ConeWarning:
	var root := _root()
	if root == null:
		return null
	if _cone_mesh == null:
		_cone_mesh = PlaneMesh.new()
		_cone_mesh.size = Vector2(2, 2)
		var m := ShaderMaterial.new()
		m.shader = CONE_SHADER
		_cone_mesh.material = m
	var n := ConeWarning.new()
	n.mesh = _cone_mesh
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.sorting_offset = -0.5
	n.owner_ref = weakref(owner)
	n.set_instance_shader_parameter("half_angle", deg_to_rad(half_deg))
	root.add_child(n)
	n.global_position = pos + Vector3.UP * 0.07
	n.scale = Vector3.ONE * (reach / 0.97)
	return n


# ------------------------------------------------------------ sopro
## Um instante do jato de frio: tufos que saem da boca (`mouth`) e correm pelo cone no yaw `yaw`, riscos de vento
## e, no chão por onde o cone passa, cristais que brotam e ficam um pouco (o rastro de gelo).
static func breath_gust(mouth: Vector3, floor_y: float, yaw: float, reach: float, half_deg: float) -> void:
	if _root() == null:
		return
	var half := deg_to_rad(half_deg)
	for i in 3:
		var a := yaw + randf_range(-half, half) * 0.85
		var dir := Vector3(sin(a), 0.0, cos(a))
		var d := randf_range(0.08, 1.0) * reach
		var at := mouth.lerp(Vector3(mouth.x, floor_y + 0.7, mouth.z), clampf(d / 5.0, 0.0, 1.0)) + dir * d
		FXToon.puff(at, 1.0 + d * 0.17, RIME if i > 0 else FXToon.MIST,
			{"vel": dir * randf_range(5.0, 9.0), "delay": d * 0.012, "grow": 0.12, "hold": 0.1, "fade": 0.4})
	var a1 := yaw + randf_range(-half, half) * 0.9
	var d1 := Vector3(sin(a1), 0.0, cos(a1))
	FXToon.streak(mouth + d1 * 1.0, Vector3(mouth.x, floor_y + 0.5, mouth.z) + d1 * reach * randf_range(0.6, 1.0), 0.12,
		{"core": Color.WHITE, "mid": FXToon.MIST.mid, "edge": RIME.edge},
		{"billboard": true, "shadow": false, "sweep": 0.14, "hold": 0.03, "fade": 0.2, "peak": 0.5})
	if randf() < 0.6:
		var a2 := yaw + randf_range(-half, half) * 0.9
		var d2 := randf_range(0.25, 1.0) * reach
		var foot := Vector3(mouth.x + sin(a2) * d2, floor_y, mouth.z + cos(a2) * d2)
		var h := randf_range(0.7, 1.4)
		FXToon.crystal(foot, h, h * 0.5, Vector3.UP + Vector3(sin(a2), 0.0, cos(a2)) * 0.5, {"pal": FROSTBITE, "hold": 1.1})


# ------------------------------------------------------------ estaca caindo
## Estaca de gelo que cai do teto até `pos` em `fall` s (só a queda: a estaca que fica no chão é o IceSpike).
static func falling_spike(pos: Vector3, fall: float) -> void:
	var root := _root()
	if root == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = FXToon.crystal_mesh()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("col_core", FROSTBITE.core)
	mi.set_instance_shader_parameter("col_mid", FROSTBITE.mid)
	mi.set_instance_shader_parameter("col_edge", FROSTBITE.edge)
	root.add_child(mi)
	# de ponta para baixo: a base larga do cristal fica em cima
	mi.basis = Basis(Vector3.RIGHT, PI).scaled_local(Vector3(0.72, 3.6, 0.72))
	mi.global_position = pos + Vector3.UP * 16.0
	var tw := mi.create_tween()
	tw.tween_property(mi, "global_position", pos + Vector3.UP * 3.3, maxf(0.05, fall)).set_ease(Tween.EASE_IN) \
		.set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(mi.queue_free)


## A estaca crava no chão: estilhaços lapidados em volta, tufos de frio e o anel no chão.
static func spike_impact(pos: Vector3, radius: float) -> void:
	if _root() == null:
		return
	FXToon.ring_wave(pos + Vector3.UP * 0.07, radius, 0.16, RIME, 0.14)
	FXToon.ground_gust(pos, radius * 1.3, FXToon.MIST, 0.35)
	for i in 6:
		var out := Vector3.BACK.rotated(Vector3.UP, TAU * (i + randf_range(-0.3, 0.3)) / 6.0)
		var h := randf_range(0.6, 1.1)
		FXToon.crystal(pos + out * radius * randf_range(0.45, 0.8), h, h * 0.5, Vector3.UP + out * 0.7,
			{"pal": FROSTBITE, "hold": 0.5, "delay": 0.03 * i})
	for i in 4:
		var a := randf() * TAU
		FXToon.puff(pos + Vector3(cos(a), 0.4, sin(a)) * radius * 0.4, randf_range(1.2, 1.8), RIME if i % 2 else FXToon.MIST,
			{"vel": Vector3(cos(a) * 2.5, 1.2, sin(a) * 2.5), "grow": 0.1, "hold": 0.12, "fade": 0.45})


# ------------------------------------------------------------ nevasca
static func _flake() -> QuadMesh:
	if _flake_mesh == null:
		_flake_mesh = QuadMesh.new()
		_flake_mesh.size = Vector2(0.5, 0.045)   # risco de neve levado pelo vento
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.92, 0.97, 1.0, 0.85)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_flake_mesh.material = m
	return _flake_mesh


## Neve varrendo a sala `room` (x, z do mundo) na altura do chão `y`: riscos brancos atravessando de lado. Devolve o
## emissor (quem chamou liga/desliga com `emitting` e o libera).
static func snowstorm(parent: Node3D, room: Rect2, y: float) -> CPUParticles3D:
	if _root() == null:
		return null
	var p := CPUParticles3D.new()
	p.mesh = _flake()
	p.amount = 260
	p.lifetime = 1.5
	p.preprocess = 1.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(room.size.x * 0.5 + 2.0, 2.6, room.size.y * 0.5 + 2.0)
	p.direction = Vector3(1.0, -0.12, 0.35)
	p.spread = 14.0
	p.initial_velocity_min = 11.0
	p.initial_velocity_max = 17.0
	p.gravity = Vector3(0, -1.5, 0)
	p.particle_flag_align_y = false
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.5
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.15, Color(1, 1, 1, 1))
	fade.add_point(0.8, Color(0.8, 0.92, 1.0, 0.9))
	p.color_ramp = fade
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.top_level = true
	p.emitting = false
	parent.add_child(p)
	var c := room.get_center()
	p.global_position = Vector3(c.x, y + 2.8, c.y)
	return p


## Um sopro da nevasca na sala: um tufo de névoa correndo rente ao chão e, de vez em quando, uma rajada rasteira.
static func storm_gust(room: Rect2, y: float) -> void:
	if _root() == null:
		return
	var at := Vector3(randf_range(room.position.x, room.end.x), y + randf_range(0.4, 1.6), randf_range(room.position.y, room.end.y))
	FXToon.puff(at, randf_range(2.2, 3.6), FXToon.MIST,
		{"vel": Vector3(9.0, 0.0, 3.0), "grow": 0.3, "hold": 0.35, "fade": 0.7})
	if randf() < 0.35:
		FXToon.ground_gust(Vector3(at.x, y, at.z), randf_range(3.0, 5.0), FXToon.MIST, 0.6)


## Geada no jogador exposto: um cristal pequeno aos pés e um tufo de frio (cresce com a exposição).
static func frostbite(feet: Vector3, e: float) -> void:
	if _root() == null:
		return
	for i in 1 + int(e * 3.0):
		var a := randf() * TAU
		var h := randf_range(0.3, 0.5) + 0.4 * e
		FXToon.crystal(feet + Vector3(cos(a), 0.0, sin(a)) * randf_range(0.3, 0.7), h, h * 0.5,
			Vector3.UP + Vector3(cos(a), 0.0, sin(a)) * 0.6, {"pal": FROSTBITE, "hold": 0.5})
	FXToon.puff(feet + Vector3.UP * 1.0, 0.9 + e, RIME, {"vel": Vector3(2.0, 0.6, 0.6), "grow": 0.12, "hold": 0.1, "fade": 0.4})


# ------------------------------------------------------------ partículas do corpo
## Lasca de gelo: losango chato de duas faces, sem luz (a cor vem da partícula).
static func mote_mesh() -> ArrayMesh:
	if _mote_mesh != null:
		return _mote_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var t := Vector3(0, 0.1, 0)
	var b := Vector3(0, -0.1, 0)
	var l := Vector3(0.045, 0, 0.012)
	var r := Vector3(-0.045, 0, 0.012)
	for tri in [[t, l, b], [t, b, r], [t, b, l], [t, r, b]]:
		for v in tri:
			st.set_color(Color.WHITE)
			st.add_vertex(v)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(m)
	_mote_mesh = st.commit()
	return _mote_mesh


## Geada caindo do corpo dela o tempo todo (`parent` = o pivô da corcunda; as lascas ficam no mundo enquanto ela
## anda): lascas de gelo girando e descendo devagar.
static func frost_fall(parent: Node3D, radius: float) -> CPUParticles3D:
	if _root() == null:
		return null
	var p := CPUParticles3D.new()
	p.mesh = mote_mesh()
	p.amount = 26
	p.lifetime = 2.6
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3(0.2, -1.0, 0.1)
	p.spread = 60.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.8
	p.gravity = Vector3(0, -0.9, 0)
	p.damping_min = 0.3
	p.damping_max = 0.8
	p.particle_flag_rotate_y = true
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -220.0
	p.angular_velocity_max = 220.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.6
	var ramp := Gradient.new()
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	ramp.set_color(0, Color(0.9, 0.98, 1.0))
	ramp.set_color(1, Color(0.4, 0.75, 1.0))
	ramp.add_point(0.5, Color(0.66, 0.9, 1.0))
	p.color_initial_ramp = ramp
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.75, Color(1, 1, 1, 1))
	p.color_ramp = fade
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p


## Lascas de gelo arrancadas (golpe que ela dá, pisada pesada).
static func frost_burst(pos: Vector3, n: int, radius: float) -> void:
	var root := _root()
	if root == null:
		return
	var p := CPUParticles3D.new()
	p.mesh = mote_mesh()
	p.amount = n
	p.lifetime = 1.4
	p.one_shot = true
	p.explosiveness = 0.92
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, -6.0, 0)
	p.particle_flag_rotate_y = true
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.8
	p.color = Color(0.75, 0.94, 1.0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	root.get_tree().create_timer(2.0).timeout.connect(p.queue_free)
