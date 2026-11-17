class_name FXShatter
extends RefCounted
## Morte "em cacos": o monstro acende azul, incha um pouco e se desfaz em fragmentos de vidro azul
## que nascem na superfície do próprio modelo, giram, sobem devagar e apagam.

const GLOW_TIME := 0.3          # quanto tempo o corpo fica acendendo antes de quebrar
const SHARD_LIFE := 1.1
const POINTS_PER_MESH := 40     # vértices sorteados de cada malha (guardados por malha)
const GLOW_COLOR := Color(0.35, 0.72, 1.0)

static var _shard_mesh: ArrayMesh
static var _glow_keep: StandardMaterial3D   # fica vivo: o shader não é recompilado a cada morte
static var _ramp: Gradient
static var _shrink: Curve
static var _points_cache := {}


static func prewarm() -> void:
	_mesh()
	_glow_template()


## Começa o efeito no `enemy` (já marcado como morto). Chama `done` quando o modelo sumiu.
static func play(enemy: Node3D, model: Node3D, meshes: Array[MeshInstance3D], scale: float, big: bool, done: Callable) -> void:
	var root := FX._scene()
	if root == null or model == null:
		# servidor dedicado (ninguém vê): o nó ainda dura um instante, como antes
		enemy.create_tween().tween_interval(1.0).finished.connect(done)
		return
	var glow := _glow_template().duplicate() as StandardMaterial3D
	for m in meshes:
		if is_instance_valid(m):
			m.material_overlay = glow
	var tw := enemy.create_tween()
	tw.set_parallel()
	tw.tween_property(glow, "albedo_color:a", 0.9, GLOW_TIME).set_ease(Tween.EASE_IN)
	tw.tween_property(model, "scale", model.scale * 1.08, GLOW_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func() -> void:
		_shatter(root, enemy, meshes, scale, big)
		model.visible = false
		done.call())


static func _shatter(root: Node, enemy: Node3D, meshes: Array[MeshInstance3D], scale: float, big: bool) -> void:
	var center := enemy.global_position + Vector3.UP * 0.6 * scale
	var pts := PackedVector3Array()
	var normals := PackedVector3Array()
	for m in meshes:
		if not is_instance_valid(m) or m.mesh == null or not m.is_visible_in_tree():
			continue
		var xf := m.global_transform
		for v in _local_points(m.mesh):
			var w: Vector3 = xf * v
			pts.append(w - center)
			var n := (w - center).normalized()
			normals.append((n + Vector3.UP * 0.6).normalized())
	if pts.is_empty():
		pts.append(Vector3.ZERO)
		normals.append(Vector3.UP)

	var amount := FXEpic._reserve(140 if big else 46)
	var p := CPUParticles3D.new()
	p.mesh = _mesh()
	p.amount = amount
	p.lifetime = SHARD_LIFE
	p.explosiveness = 0.8
	p.randomness = 0.5
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_DIRECTED_POINTS
	p.emission_points = pts
	p.emission_normals = normals
	p.direction = Vector3(0, 0, 1)        # pontos dirigidos: +Z vira a normal de cada ponto (para fora)
	p.spread = 30.0
	p.initial_velocity_min = 1.2 * sqrt(scale)
	p.initial_velocity_max = 3.4 * sqrt(scale)
	p.damping_min = 2.0
	p.damping_max = 3.5
	p.gravity = Vector3(0, 1.4, 0)        # os cacos sobem, como se evaporassem
	p.particle_flag_rotate_y = true
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = 0.6 * sqrt(scale)
	p.scale_amount_max = 1.5 * sqrt(scale)
	p.scale_amount_curve = _shrink_curve()
	p.color_ramp = _color_ramp()
	FXEpic._launch(root, p, center, amount)
	# clarão do estouro: brilho branco-azulado rápido e um anel no chão
	FXEpic.glow_burst(center, Color(0.4, 0.75, 1.0), 10 if big else 6, 2.0, 0.22 * sqrt(scale), 0.35, 0.0)
	if big:
		FX.ring(enemy.global_position, Color(0.5, 0.85, 1.0, 0.8), 3.5 * scale, 0.6)


## Até POINTS_PER_MESH vértices da malha (espaço local), sorteados uma vez por malha.
static func _local_points(mesh: Mesh) -> PackedVector3Array:
	var cached: PackedVector3Array = _points_cache.get(mesh, PackedVector3Array())
	if not cached.is_empty():
		return cached
	var all := PackedVector3Array()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
			all.append_array(arrays[Mesh.ARRAY_VERTEX])
	if all.is_empty():
		var box := mesh.get_aabb()
		for i in 8:
			all.append(box.get_endpoint(i))
	var out := PackedVector3Array()
	var step := maxf(1.0, float(all.size()) / POINTS_PER_MESH)
	var f := randf() * step
	while int(f) < all.size() and out.size() < POINTS_PER_MESH:
		out.append(all[int(f)])
		f += step
	if _points_cache.size() > 256:
		_points_cache.clear()
	_points_cache[mesh] = out
	return out


## Caco: losango fino e torto, dupla face; cor chapada sem luz, para ler azul em chão claro ou escuro.
static func _mesh() -> ArrayMesh:
	if _shard_mesh == null:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		# losango irregular: duas metades, uma mais clara (parece faceta de vidro)
		var a := Vector3(0, 0.11, 0)
		var b := Vector3(0.07, -0.02, 0)
		var c := Vector3(-0.01, -0.09, 0)
		var d := Vector3(-0.06, 0.01, 0)
		st.set_color(Color(1, 1, 1))
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
		st.set_color(Color(0.72, 0.82, 1.0))
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)
		st.set_material(mat)
		_shard_mesh = st.commit()
	return _shard_mesh


static func _glow_template() -> StandardMaterial3D:
	if _glow_keep == null:
		_glow_keep = StandardMaterial3D.new()
		_glow_keep.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow_keep.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glow_keep.albedo_color = Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, 0.0)
	return _glow_keep


static func _color_ramp() -> Gradient:
	if _ramp == null:
		_ramp = Gradient.new()
		_ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.6, 1.0])
		_ramp.colors = PackedColorArray([
			Color(0.85, 0.97, 1.0, 1.0),   # estouro quase branco
			Color(0.4, 0.8, 1.0, 0.95),    # azul-ciano
			Color(0.25, 0.55, 1.0, 0.75),
			Color(0.2, 0.4, 1.0, 0.0)])
	return _ramp


static func _shrink_curve() -> Curve:
	if _shrink == null:
		_shrink = Curve.new()
		_shrink.add_point(Vector2(0.0, 1.0))
		_shrink.add_point(Vector2(0.6, 0.85))
		_shrink.add_point(Vector2(1.0, 0.0))
	return _shrink
