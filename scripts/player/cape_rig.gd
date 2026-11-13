class_name CapeRig
extends Node
## Física de tecido para capas: monta, em tempo de execução, um esqueleto pequeno dentro da capa
## (algumas cadeias verticais de ossos), liga cada vértice aos ossos mais próximos e deixa um
## SpringBoneSimulator3D balançar tudo. Colisores em cápsula seguem pernas e tronco para a capa
## não atravessar o corpo. Só visual: nada disso afeta jogabilidade nem rede.

## Cadeias da esquerda para a direita, em fração do arco da capa (-1 = borda esquerda, 1 = direita).
const CHAINS := [-0.75, 0.0, 0.75]
## Ossos por cadeia (o último se estende até a barra).
const BONES := 4
## Rigidez da mola no ombro e na barra (maior = volta mais rápido ao caimento).
const STIFF_TOP := 4.0
const STIFF_HEM := 1.6

## Malha com pesos já calculados, por malha de origem (todas as instâncias do knight.glb compartilham).
static var _cache := {}

var skeleton: Skeleton3D
var sim: SpringBoneSimulator3D
## [{"col": SpringBoneCollisionCapsule3D, "node": Node3D, "offset": Transform3D}]
var _followers: Array = []


## Transforma `cape` (MeshInstance3D com a frente do personagem em +Z) em tecido simulado.
## `center` é o centro (x, z) do arco da capa no espaço da malha.
static func attach(cape: MeshInstance3D, center := Vector2(0.0, -0.035)) -> CapeRig:
	var parent := cape.get_parent() as Node3D
	if parent == null or cape.mesh == null:
		return null
	var key := cape.mesh.get_instance_id()
	if not _cache.has(key):
		_cache[key] = _build(cape.mesh, center)
	var data: Dictionary = _cache[key]

	var rig := CapeRig.new()
	rig.name = "CapeRig"
	var skel := Skeleton3D.new()
	skel.name = "CapeSkeleton"
	skel.transform = cape.transform
	skel.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS
	for b in data.bones:
		var i := skel.add_bone(b.name)
		skel.set_bone_parent(i, b.parent)
		skel.set_bone_rest(i, b.rest)
		skel.set_bone_pose(i, b.rest)
	parent.add_child(skel)
	parent.remove_child(cape)
	skel.add_child(cape)
	cape.transform = Transform3D.IDENTITY
	cape.mesh = data.mesh
	cape.skin = data.skin
	cape.skeleton = NodePath("..")

	var s := SpringBoneSimulator3D.new()
	s.name = "CapeSprings"
	skel.add_child(s)
	s.setting_count = CHAINS.size()
	for c in CHAINS.size():
		var root_i: int = data.chain_roots[c]
		s.set_root_bone(c, root_i)
		s.set_end_bone(c, root_i + BONES - 1)
		s.set_extend_end_bone(c, true)
		s.set_end_bone_direction(c, SkeletonModifier3D.BONE_DIRECTION_PLUS_Y)
		s.set_end_bone_length(c, data.end_lengths[c])
		s.set_center_from(c, SpringBoneSimulator3D.CENTER_FROM_WORLD_ORIGIN)
		s.set_radius(c, 0.035)
		s.set_enable_all_child_collisions(c, true)
		s.set_gravity_direction(c, Vector3.DOWN)
		# ombros firmes, barra solta: a capa curva em vez de girar inteira como uma tábua
		s.set_individual_config(c, true)
		var n := s.get_joint_count(c)
		for j in n:
			var t := float(j) / maxf(n - 1, 1)
			s.set_joint_stiffness(c, j, lerpf(STIFF_TOP, STIFF_HEM, t))
			s.set_joint_drag(c, j, lerpf(0.2, 0.3, t))
			s.set_joint_gravity(c, j, lerpf(2.0, 2.6, t))
			s.set_joint_gravity_direction(c, j, Vector3.DOWN)
			s.set_joint_radius(c, j, 0.035)
	rig.skeleton = skel
	rig.sim = s
	skel.add_child(rig)
	return rig


## Colisor em cápsula preso a `node` (eixo da cápsula = Y local do nó, centrado em `offset`).
func add_capsule(node: Node3D, radius: float, height: float, offset := Vector3.ZERO) -> void:
	var col := SpringBoneCollisionCapsule3D.new()
	col.radius = radius
	col.height = height
	sim.add_child(col)
	_followers.append({"col": col, "node": node, "offset": Transform3D(Basis.IDENTITY, offset)})
	_follow()


## Volta a capa ao repouso (teleporte, renascer): evita um chicote gigante.
func reset() -> void:
	_follow()
	sim.reset()


func _physics_process(_delta: float) -> void:
	_follow()


func _follow() -> void:
	for f in _followers:
		var n: Node3D = f.node
		if is_instance_valid(n) and n.is_inside_tree():
			f.col.global_transform = n.global_transform * f.offset


# ------------------------------------------------------------------ montagem
static func _build(src: Mesh, center: Vector2) -> Dictionary:
	# perfil por altura: raio médio e meio-arco de cada fileira de vértices
	var rows := {}
	for si in src.get_surface_count():
		for p: Vector3 in src.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
			var k := snappedf(p.y, 0.01)
			if not rows.has(k):
				rows[k] = {"r": 0.0, "n": 0, "half": 0.0}
			var d := Vector2(p.x - center.x, center.y - p.z)
			rows[k].r += d.length()
			rows[k].n += 1
			rows[k].half = maxf(rows[k].half, absf(atan2(d.x, d.y)))
	var ys: Array = rows.keys()
	ys.sort()
	var prof: Array = []   # [[y, raio, meio-arco]] de baixo para cima
	for y in ys:
		prof.append([y, rows[y].r / rows[y].n, rows[y].half])
	var top: float = ys[-1]
	var bottom: float = ys[0]
	var seg := (top - bottom) / BONES

	# juntas de cada cadeia (BONES + 1 pontos, de cima para baixo)
	var bones: Array = [{"name": "CapeRoot", "parent": -1, "rest": Transform3D.IDENTITY}]
	var chain_roots: Array = []
	var end_lengths: Array = []
	for c in CHAINS.size():
		var pts: Array[Vector3] = []
		for j in BONES + 1:
			var y := top - seg * j
			var pr := _profile(prof, y)
			var phi: float = CHAINS[c] * pr[1]
			pts.append(Vector3(center.x + sin(phi) * pr[0], y, center.y - cos(phi) * pr[0]))
		chain_roots.append(bones.size())
		var parent_global := Transform3D.IDENTITY
		var parent_i := 0
		for j in BONES:
			var y_axis := (pts[j + 1] - pts[j]).normalized()
			var out := Vector3(pts[j].x - center.x, 0, pts[j].z - center.y).normalized()
			var x_axis := y_axis.cross(out).normalized()
			var z_axis := x_axis.cross(y_axis).normalized()
			var g := Transform3D(Basis(x_axis, y_axis, z_axis), pts[j])
			bones.append({"name": "Cape%d_%d" % [c, j], "parent": parent_i, "rest": parent_global.affine_inverse() * g, "global": g})
			parent_i = bones.size() - 1
			parent_global = g
		end_lengths.append(pts[BONES].distance_to(pts[BONES - 1]))

	var skin := Skin.new()
	for i in bones.size():
		skin.add_bind(i, (bones[i].get("global", Transform3D.IDENTITY) as Transform3D).affine_inverse())

	# pesos: mistura linear entre as duas cadeias vizinhas e entre ossos vizinhos da cadeia
	var mesh := ArrayMesh.new()
	for si in src.get_surface_count():
		var arrays := src.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bi := PackedInt32Array()
		var bw := PackedFloat32Array()
		bi.resize(verts.size() * 4)
		bw.resize(verts.size() * 4)
		for vi in verts.size():
			var p := verts[vi]
			var pr := _profile(prof, p.y)
			var d := Vector2(p.x - center.x, center.y - p.z)
			var g: float = clampf(atan2(d.x, d.y) / maxf(pr[1], 0.001), CHAINS[0], CHAINS[-1])
			var c0 := 0
			while c0 < CHAINS.size() - 2 and g > CHAINS[c0 + 1]:
				c0 += 1
			var hc: float = (g - CHAINS[c0]) / (CHAINS[c0 + 1] - CHAINS[c0])
			var vert := _vertical(clampf((top - p.y) / seg, 0.0, BONES))
			var slot := vi * 4
			for side in 2:
				var cw: float = 1.0 - hc if side == 0 else hc
				var root_i: int = chain_roots[c0 + side]
				for v in 2:
					bi[slot] = root_i + vert[v * 2]
					bw[slot] = cw * vert[v * 2 + 1]
					slot += 1
		arrays[Mesh.ARRAY_BONES] = bi
		arrays[Mesh.ARRAY_WEIGHTS] = bw
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(si, src.surface_get_material(si))
	return {"mesh": mesh, "skin": skin, "bones": bones, "chain_roots": chain_roots, "end_lengths": end_lengths}


## Dois ossos da cadeia e seus pesos para a posição `s` (0 = topo, BONES = barra), em [osso, peso, osso, peso].
static func _vertical(s: float) -> Array:
	var i := mini(int(s), BONES - 1)
	var f := s - i
	if f < 0.5 and i > 0:
		return [i, 0.5 + f, i - 1, 0.5 - f]
	if f > 0.5 and i < BONES - 1:
		return [i, 1.5 - f, i + 1, f - 0.5]
	return [i, 1.0, i, 0.0]


## [raio, meio-arco] interpolados na altura y.
static func _profile(prof: Array, y: float) -> Array:
	if y <= prof[0][0]:
		return [prof[0][1], prof[0][2]]
	for i in range(1, prof.size()):
		if y <= prof[i][0]:
			var t: float = (y - prof[i - 1][0]) / (prof[i][0] - prof[i - 1][0])
			return [lerpf(prof[i - 1][1], prof[i][1], t), lerpf(prof[i - 1][2], prof[i][2], t)]
	return [prof[-1][1], prof[-1][2]]
