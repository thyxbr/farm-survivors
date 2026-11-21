class_name AbyssFX
extends RefCounted
## Efeitos do Arauto do Abismo: avisos no chão (arco da Garra, faixas da Rajada), a fumaça de sombra de sumir e
## aparecer, o estouro em anel do Colapso, os riscos do puxão, a sombra no chão do verdadeiro e os fiapos de
## sombra que caem do manto. Só visual (o dano é do servidor/solo); nada é criado no servidor sem tela.

## Vazio: miolo preto, meio violeta, borda carmim (o traço dos monstros).
const VOID := {"core": Color(0.03, 0.01, 0.06), "mid": Color(0.34, 0.07, 0.5), "edge": Color(1.0, 0.2, 0.42)}
## Sombra: fumaça quase preta com borda violeta.
const SHADE := {"core": Color(0.05, 0.03, 0.09), "mid": Color(0.13, 0.07, 0.22), "edge": Color(0.42, 0.14, 0.6)}
const WARN := Color(1.0, 0.16, 0.2)


static func _root() -> Node3D:
	if DisplayServer.get_name() == "headless":
		return null
	return FX._scene() as Node3D


static func _flat(color: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Malha deitada no chão (triângulos em leque/faixa) que fica mais forte até `dur` s e some.
static func _ground_warning(verts: PackedVector3Array, pos: Vector3, dur: float) -> void:
	var root := _root()
	if root == null:
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var m := _flat(WARN, 0.14)
	mesh.surface_set_material(0, m)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = pos + Vector3.UP * 0.07
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.55, maxf(0.05, dur))
	tw.tween_property(m, "albedo_color:a", 0.0, 0.12)
	tw.tween_callback(mi.queue_free)


## Aviso da Garra: setor de raio `r` à frente de `pos`, virado para `dir`, `half_deg` graus para cada lado.
static func arc_warning(pos: Vector3, dir: Vector3, r: float, half_deg: float, dur: float) -> void:
	var d := Vector3(dir.x, 0.0, dir.z).normalized()
	var verts := PackedVector3Array()
	var n := 14
	for i in n:
		var a0 := deg_to_rad(lerpf(-half_deg, half_deg, float(i) / n))
		var a1 := deg_to_rad(lerpf(-half_deg, half_deg, float(i + 1) / n))
		verts.append(Vector3.ZERO)
		verts.append(d.rotated(Vector3.UP, a0) * r)
		verts.append(d.rotated(Vector3.UP, a1) * r)
	_ground_warning(verts, pos, dur)
	# a borda do arco, mais forte desde o começo
	var rim := PackedVector3Array()
	for i in n:
		var a0 := deg_to_rad(lerpf(-half_deg, half_deg, float(i) / n))
		var a1 := deg_to_rad(lerpf(-half_deg, half_deg, float(i + 1) / n))
		var p0 := d.rotated(Vector3.UP, a0)
		var p1 := d.rotated(Vector3.UP, a1)
		rim.append_array([p0 * (r - 0.18), p0 * r, p1 * r, p0 * (r - 0.18), p1 * r, p1 * (r - 0.18)])
	_ground_warning(rim, pos + Vector3.UP * 0.01, dur)


## Aviso de um projétil da Rajada: faixa estreita no chão de `a` até `b`.
static func line_warning(a: Vector3, b: Vector3, half_w: float, dur: float) -> void:
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var side := d.normalized().cross(Vector3.UP) * half_w
	var e := Vector3(d.x, 0.0, d.z)
	_ground_warning(PackedVector3Array([-side, side, e + side * 0.4, -side, e + side * 0.4, e - side * 0.4]), a, dur)


## Coluna de fumaça de sombra em `pos` (ele some ou aparece ali; uma cópia se desfaz).
static func vanish(pos: Vector3, height: float) -> void:
	if _root() == null:
		return
	for i in 7:
		var y := height * (i + 0.5) / 7.0
		var off := Vector3(randf_range(-0.5, 0.5), y, randf_range(-0.5, 0.5))
		FXToon.puff(pos + off, randf_range(1.5, 2.3), SHADE if i % 2 else VOID,
			{"vel": Vector3(off.x, 1.2, off.z) * 1.3, "delay": 0.03 * i, "grow": 0.14, "hold": 0.16, "fade": 0.5})
	FXToon.ring_wave(pos + Vector3.UP * 0.08, 2.6, 0.22, VOID, 0.16)
	FX.burst(pos + Vector3.UP * height * 0.5, Color(0.3, 0.1, 0.45), 16, 4.0, 0.12, 0.6, -2.0)


## Uma faixa do Colapso estoura: tufos de vazio ao longo do anel (ou enchendo o disco) e uma onda na borda.
static func ring_blast(pos: Vector3, r0: float, r1: float) -> void:
	if _root() == null:
		return
	var mid := (r0 + r1) / 2.0
	var w := r1 - r0
	if r0 <= 0.01:   # o miolo: estouro cheio
		for i in 12:
			var a := TAU * i / 12.0 + randf() * 0.3
			var d := sqrt(randf()) * r1 * 0.85
			FXToon.puff(pos + Vector3(cos(a) * d, 0.7, sin(a) * d), randf_range(2.0, 3.0), VOID if i % 3 else SHADE,
				{"vel": Vector3(cos(a), 0.9, sin(a)) * 2.0, "delay": 0.02 * (i % 4), "grow": 0.12, "hold": 0.18, "fade": 0.5})
		FXToon.ring_wave(pos + Vector3.UP * 0.08, r1, 0.5, VOID, 0.14)
		FXToon.thorns(pos, Basis.IDENTITY, r1 * 0.5, r1 * 0.95, 10, 1.8, 0.3)
		return
	var n := clampi(int(mid * 2.2), 10, 40)
	for i in n:
		var a := TAU * (i + randf_range(-0.25, 0.25)) / n
		var d := mid + randf_range(-0.3, 0.3) * w
		FXToon.puff(pos + Vector3(cos(a) * d, 0.6, sin(a) * d), randf_range(1.5, 2.2) * (0.7 + w * 0.2),
			VOID if i % 3 else SHADE, {"vel": Vector3(cos(a) * 1.5, 1.6, sin(a) * 1.5), "delay": 0.015 * (i % 5),
			"grow": 0.1, "hold": 0.16, "fade": 0.45})
	FXToon.ring_wave(pos + Vector3.UP * 0.08, r1, w * 0.45, VOID, 0.12)
	FXToon.thorns(pos, Basis.IDENTITY, r0, r1, clampi(n / 2, 6, 16), 1.5, 0.25)


## Riscos do puxão: traços de sombra correndo da borda para o centro, rente ao chão.
static func pull_streaks(center: Vector3, radius: float, n: int) -> void:
	if _root() == null:
		return
	for i in n:
		var a := randf() * TAU
		var d := Vector3(cos(a), 0.0, sin(a))
		var r := randf_range(radius * 0.55, radius)
		FXToon.streak(center + d * r + Vector3.UP * 0.1, center + d * maxf(1.2, r - randf_range(3.5, 5.5))
			+ Vector3.UP * 0.1, randf_range(0.1, 0.18), VOID, {"sweep": 0.22, "hold": 0.05, "fade": 0.2, "shadow": false})


## A sombra no chão do verdadeiro (as cópias não têm): disco escuro de borda mole preso a `parent`, na altura dos
## pés. É a pista da Miragem; como vem do tipo do monstro, todo cliente vê igual.
static func ground_shadow(parent: Node3D, radius: float) -> MeshInstance3D:
	if _root() == null:
		return null
	var mi := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2(2, 2)
	var m := ShaderMaterial.new()
	m.shader = _shadow_shader()
	quad.material = m
	mi.mesh = quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(radius, 1.0, radius * 0.9)
	mi.position = Vector3(0, 0.06, 0)
	parent.add_child(mi)
	return mi


static var _shadow: Shader


static func _shadow_shader() -> Shader:
	if _shadow == null:
		_shadow = Shader.new()
		_shadow.code = """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	ALBEDO = vec3(0.01, 0.0, 0.03);
	ALPHA = smoothstep(1.0, 0.55, d) * 0.78;
}
"""
	return _shadow


static var _shred_mesh: ArrayMesh


## Um fiapo: triângulo comprido e fino, das duas faces, sem luz (a cor vem da partícula).
static func _shred() -> ArrayMesh:
	if _shred_mesh != null:
		return _shred_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tri in [[Vector3(-0.05, 0.16, 0), Vector3(0.05, 0.16, 0), Vector3(0, -0.2, 0)],
			[Vector3(0, 0.16, -0.05), Vector3(0, 0.16, 0.05), Vector3(0, -0.2, 0)]]:
		for v in tri:
			st.set_color(Color.WHITE)
			st.add_vertex(v)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	st.set_material(m)
	_shred_mesh = st.commit()
	return _shred_mesh


## Fiapos de sombra caindo sem parar da barra do manto (`parent` = o corpo; ficam no mundo enquanto ele anda).
static func shreds(parent: Node3D, radius: float, y: float) -> CPUParticles3D:
	if _root() == null:
		return null
	var p := CPUParticles3D.new()
	p.mesh = _shred()
	p.amount = 22
	p.lifetime = 1.9
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3(0, -1, 0)
	p.spread = 35.0
	p.initial_velocity_min = 0.15
	p.initial_velocity_max = 0.6
	p.gravity = Vector3(0, -0.5, 0)
	p.tangential_accel_min = -0.8
	p.tangential_accel_max = 0.8
	p.angle_min = -30.0
	p.angle_max = 30.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.5
	var ramp := Gradient.new()
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	ramp.set_color(0, Color(0.04, 0.02, 0.08))
	ramp.set_color(1, Color(0.7, 0.12, 0.36))
	ramp.add_point(0.45, Color(0.16, 0.08, 0.28))
	ramp.add_point(0.85, Color(0.36, 0.1, 0.5))
	p.color_initial_ramp = ramp
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	fade.add_point(0.15, Color(1, 1, 1, 0.95))
	fade.add_point(0.7, Color(1, 1, 1, 0.8))
	p.color_ramp = fade
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.position = Vector3(0, y, 0)
	return p


## Brasas de vazio subindo do halo (`parent` = o pivô do halo).
static func halo_embers(parent: Node3D, radius: float) -> CPUParticles3D:
	if _root() == null:
		return null
	var p := CPUParticles3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.05, 0.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	box.material = m
	p.mesh = box
	p.amount = 12
	p.lifetime = 1.4
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3(0, 0, 1)
	p.emission_ring_radius = radius
	p.emission_ring_inner_radius = radius * 0.9
	p.emission_ring_height = 0.05
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.9
	p.gravity = Vector3(0, 0.4, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.25, 0.45))
	ramp.set_color(1, Color(0.5, 0.15, 0.9, 0.0))
	p.color_ramp = ramp
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p
