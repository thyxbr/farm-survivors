extends Node3D
## Chão do mapa (vila e cidade): plano com o shader de grama em manchas, trilhas e clareiras
## pintadas no shader (bordas irregulares em vez de placas retas), tufos de capim com vento,
## flores, arbustos e samambaias em MultiMesh por blocos (cada bloco some de longe).

const GROUND_SHADER := preload("res://assets/shaders/ground.gdshader")
const GRASS_SHADER := preload("res://assets/shaders/grass.gdshader")
const MAX_SHAPES := 40
const CHUNK := 20.0
## Capim: candidatos por m² = density * GRASS_MUL; um ruído de touceiras decide quantos ficam
## (campo cheio onde ele sobe, ralo onde desce).
const GRASS_MUL := 4.0
## Plantas por m² (vezes o 'plants' de scatter_grass): arbustos e samambaias.
const PLANT_DENSITY := 0.02
const PLANT_MODELS := {
	"bush": preload("res://assets/models/bush.glb"),
	"bush_berry": preload("res://assets/models/bush_berry.glb"),
	"fern": preload("res://assets/models/fern.glb"),
}
const FLOWER_COLORS := [Color(0.95, 0.95, 0.9), Color(1.0, 0.85, 0.25), Color(0.75, 0.55, 0.95),
		Color(0.95, 0.5, 0.65), Color(0.5, 0.7, 1.0)]

var half := 125.0
var _shapes := PackedVector4Array()
var _cols := PackedVector4Array()
var _mix := PackedFloat32Array()
var _mat: ShaderMaterial
var _noise_tex: NoiseTexture2D


## Cria o plano visual e a colisão. Chamar uma vez, logo depois de add_child.
func setup(map_half: float) -> void:
	half = map_half
	var noise := FastNoiseLite.new()
	noise.frequency = 0.015
	noise.fractal_octaves = 3
	_noise_tex = NoiseTexture2D.new()
	_noise_tex.width = 256
	_noise_tex.height = 256
	_noise_tex.seamless = true
	_noise_tex.generate_mipmaps = true
	_noise_tex.noise = noise
	_mat = ShaderMaterial.new()
	_mat.shader = GROUND_SHADER
	_mat.set_shader_parameter("noise_tex", _noise_tex)
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(half * 2.6, half * 2.6)
	ground.mesh = plane
	ground.material_override = _mat
	add_child(ground)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(half * 2.6, 1, half * 2.6)
	cs.shape = box
	cs.position.y = -0.5
	body.add_child(cs)
	add_child(body)
	_push()


## Trilha/área retangular (alinhada aos eixos). soft = largura da borda irregular em metros.
## grass = 0 pinta terra/pedra lisa; > 0 deixa a grama aparecer por baixo (grama baixa, pisada),
## manchada com a cor da forma, e nasce capim baixo e ralo dentro (densidade ~ grass).
func add_rect(center: Vector3, size: Vector2, c: Color, soft := 0.7, grass := 0.0) -> void:
	_add(Vector4(center.x, center.z, size.x / 2.0, size.y / 2.0), c, soft, grass)


func add_disc(center: Vector3, r: float, c: Color, soft := 0.7, grass := 0.0) -> void:
	_add(Vector4(center.x, center.z, r, -1.0), c, soft, grass)


func _add(s: Vector4, c: Color, soft: float, grass: float) -> void:
	if _shapes.size() >= MAX_SHAPES:
		push_warning("ground: limite de %d formas" % MAX_SHAPES)
		return
	var lc := c.srgb_to_linear()
	_shapes.append(s)
	_cols.append(Vector4(lc.r, lc.g, lc.b, soft))
	_mix.append(clampf(grass, 0.0, 1.0))
	_push()


func _push() -> void:
	if _mat == null:
		return
	var s := _shapes.duplicate()
	var c := _cols.duplicate()
	var m := _mix.duplicate()
	s.resize(MAX_SHAPES)
	c.resize(MAX_SHAPES)
	m.resize(MAX_SHAPES)
	_mat.set_shader_parameter("shapes", s)
	_mat.set_shader_parameter("shape_cols", c)
	_mat.set_shader_parameter("shape_grass", m)
	_mat.set_shader_parameter("shape_count", _shapes.size())


## Distância (aprox.) até a forma pintada mais próxima; negativa = dentro.
func shape_distance(p: Vector2, shapes: Array = []) -> float:
	var best := INF
	for s in (shapes if not shapes.is_empty() else Array(_shapes)):
		best = min(best, _sd(s, p))
	return best


static func _sd(s: Vector4, p: Vector2) -> float:
	if s.w < 0.0:
		return p.distance_to(Vector2(s.x, s.y)) - s.z
	var q := (p - Vector2(s.x, s.y)).abs() - Vector2(s.z, s.w)
	return Vector2(max(q.x, 0.0), max(q.y, 0.0)).length() + min(max(q.x, q.y), 0.0)


## Espalha capim, flores, arbustos e samambaias. keep_out = [[Vector2 centro, raio], ...] onde não
## nasce nada (casas, poço, arena); sparse = [[Vector2, raio], ...] onde nasce pouco (praças,
## acampamentos) e não nascem plantas. plants multiplica a quantidade de arbustos/samambaias.
func scatter_grass(seed_value: int, density := 0.55, keep_out: Array = [], sparse: Array = [], plants := 1.0) -> void:
	if DisplayServer.get_name() == "headless":
		return   # só visual
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var tuft := _tuft_mesh()
	var flower := _flower_mesh()
	var gmat := ShaderMaterial.new()
	gmat.shader = GRASS_SHADER
	gmat.set_shader_parameter("noise_tex", _noise_tex)
	tuft.surface_set_material(0, gmat)
	var clump := FastNoiseLite.new()   # touceiras de capim e canteiros de flores/plantas
	clump.seed = seed_value
	clump.frequency = 0.045
	clump.fractal_octaves = 2
	var plant_meshes := {}
	for k in PLANT_MODELS:
		plant_meshes[k] = _glb_mesh(PLANT_MODELS[k])
	var n := int(ceil(half * 2.0 / CHUNK))
	for cx in n:
		for cz in n:
			var x0 := -half + cx * CHUNK
			var z0 := -half + cz * CHUNK
			var box := Rect2(x0, z0, CHUNK, CHUNK)
			# só o que encosta neste bloco entra nos testes (o mapa tem centenas de props)
			var shapes := []   # formas lisas: sem capim
			var grassy := []   # formas com grama baixa: capim ralo e curto
			for k in _shapes.size():
				var s := _shapes[k]
				var r := Rect2(s.x - s.z, s.y - (s.z if s.w < 0.0 else s.w), s.z * 2.0, (s.z if s.w < 0.0 else s.w) * 2.0)
				if box.grow(1.0).intersects(r):
					if _mix[k] > 0.0:
						grassy.append([s, _mix[k]])
					else:
						shapes.append(s)
			var outs := _near(keep_out, box)
			var few := _near(sparse, box)
			var tufts: Array[Transform3D] = []
			var tints: Array[Color] = []
			var flowers: Array[Transform3D] = []
			var fcols: Array[Color] = []
			for i in int(CHUNK * CHUNK * density * GRASS_MUL):
				var p := Vector2(x0 + rng.randf() * CHUNK, z0 + rng.randf() * CHUNK)
				var c := clump.get_noise_2d(p.x, p.y) * 0.5 + 0.5
				var thick := smoothstep(0.32, 0.68, c)
				if rng.randf() > 0.35 + 0.65 * thick:
					continue
				var r := rng.randf()
				if not shapes.is_empty() and shape_distance(p, shapes) < 0.35:
					continue
				if _inside(p, outs):
					continue
				if r < 0.75 and _inside(p, few):
					continue
				# capim mais alto nas touceiras cheias
				var s := rng.randf_range(0.8, 1.2) * (0.85 + 0.45 * thick)
				var g := _grassy_at(p, grassy)
				if g >= 0.0:
					if rng.randf() > g * 0.3:
						continue
					s *= 0.5   # pisado: tufos baixos
				var bas := Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s))
				var fl := clump.get_noise_2d(p.x * 1.7 + 311.0, p.y * 1.7 - 97.0) * 0.5 + 0.5
				if rng.randf() < 0.012 + 0.11 * smoothstep(0.6, 0.78, fl):   # flores em canteiros
					flowers.append(Transform3D(bas, Vector3(p.x, 0.0, p.y)))
					fcols.append(FLOWER_COLORS[rng.randi() % FLOWER_COLORS.size()])
				else:
					tufts.append(Transform3D(bas, Vector3(p.x, 0.0, p.y)))
					var v := rng.randf_range(0.85, 1.15)
					tints.append(Color(v, v * rng.randf_range(0.95, 1.05), v))
			var center := Vector3(x0 + CHUNK / 2.0, 0, z0 + CHUNK / 2.0)
			_chunk(tuft, tufts, tints, center, 60.0, true)
			_chunk(flower, flowers, fcols, center, 50.0, false)
			_scatter_plants(rng, clump, plant_meshes, box, plants, shapes, grassy, outs, few, center)


## Arbustos (alguns com frutinhas) e samambaias: mais nas touceiras cheias, nunca em trilhas,
## clareiras, áreas ralas nem colados nos props.
func _scatter_plants(rng: RandomNumberGenerator, clump: FastNoiseLite, meshes: Dictionary, box: Rect2,
		amount: float, shapes: Array, grassy: Array, outs: Array, few: Array, center: Vector3) -> void:
	var bushes: Array[Transform3D] = []
	var berries: Array[Transform3D] = []
	var ferns: Array[Transform3D] = []
	for i in int(box.get_area() * PLANT_DENSITY * amount * 2.0):
		var p := box.position + Vector2(rng.randf(), rng.randf()) * box.size
		var c := clump.get_noise_2d(p.x, p.y) * 0.5 + 0.5
		if rng.randf() > 0.15 + 0.85 * smoothstep(0.4, 0.75, c):
			continue
		if not shapes.is_empty() and shape_distance(p, shapes) < 1.2:
			continue
		if _grassy_at(p, grassy) >= 0.0 or _inside(p, few) or _inside_grown(p, outs, 0.9):
			continue
		var t := rng.randf()
		var s := rng.randf_range(1.0, 1.5) if t < 0.45 else rng.randf_range(0.9, 1.7)
		var bas := Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.15), s))
		var xf := Transform3D(bas, Vector3(p.x, 0.0, p.y))
		if t < 0.45:
			ferns.append(xf)
		elif t < 0.87:
			bushes.append(xf)
		else:
			berries.append(xf)
	_chunk(meshes["fern"], ferns, [], center, 70.0, false)
	_chunk(meshes["bush"], bushes, [], center, 110.0, false, true)
	_chunk(meshes["bush_berry"], berries, [], center, 110.0, false, true)


## Primeira malha de um GLB (os modelos de planta são um objeto só).
static func _glb_mesh(scene: PackedScene) -> Mesh:
	var root := scene.instantiate()
	var mesh: Mesh = null
	for node in root.find_children("*", "MeshInstance3D", true, false):
		mesh = (node as MeshInstance3D).mesh
		break
	root.free()
	return mesh


func _inside_grown(p: Vector2, areas: Array, extra: float) -> bool:
	for a in areas:
		if p.distance_to(a[0]) < a[1] + extra:
			return true
	return false


## Densidade de capim da forma com grama em p (a maior entre as que cobrem p); -1 = fora de todas.
static func _grassy_at(p: Vector2, grassy: Array) -> float:
	var best := -1.0
	for e in grassy:
		if _sd(e[0], p) < 0.0:
			best = maxf(best, e[1])
	return best


static func _near(areas: Array, box: Rect2) -> Array:
	var out := []
	for a in areas:
		var c: Vector2 = a[0]
		if box.grow(a[1]).has_point(c):
			out.append(a)
	return out


func _inside(p: Vector2, areas: Array) -> bool:
	for a in areas:
		if p.distance_to(a[0]) < a[1]:
			return true
	return false


func _chunk(mesh: Mesh, xf: Array[Transform3D], cols: Array[Color], center: Vector3, far: float, custom: bool,
		shadow := false) -> void:
	if xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = custom
	mm.use_colors = not custom and not cols.is_empty()
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		var t := xf[i]
		t.origin -= center
		mm.set_instance_transform(i, t)
		if custom:
			mm.set_instance_custom_data(i, cols[i])
		elif not cols.is_empty():
			mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.position = center
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = far
	mmi.visibility_range_end_margin = 6.0
	add_child(mmi)


## Tufo de 9 folhas finas (triângulos dobrados) abertas em leque. COLOR.r = altura relativa.
func _tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in 9:
		var yaw := k * TAU / 9.0 + rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(yaw), 0, sin(yaw))
		var side := Vector3(-dir.z, 0, dir.x)
		var h := rng.randf_range(0.28, 0.55)
		var lean := rng.randf_range(0.06, 0.16)
		var w := rng.randf_range(0.035, 0.05)
		var base := dir * 0.04
		var mid := base + dir * lean * 0.45 + Vector3.UP * h * 0.55
		var tip := base + dir * lean + Vector3.UP * h
		var bl := base - side * w
		var br := base + side * w
		var ml := mid - side * w * 0.6
		var mr := mid + side * w * 0.6
		for tri in [[bl, br, mr, 0.0, 0.0, 0.55], [bl, mr, ml, 0.0, 0.55, 0.55], [ml, mr, tip, 0.55, 0.55, 1.0]]:
			for j in 3:
				st.set_color(Color(tri[3 + j], 0, 0))
				st.set_normal(Vector3.UP)
				st.add_vertex(tri[j])
	return st.commit()


## Flor: caule e 4 pétalas em cruz + miolo. Cor por instância (vertex color x instância).
func _flower_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem := Color(0.25, 0.45, 0.15)
	var h := 0.32
	_quad(st, Vector3(-0.012, 0, 0), Vector3(0.012, 0, 0), Vector3(0.012, h, 0), Vector3(-0.012, h, 0), stem)
	_quad(st, Vector3(0, 0, -0.012), Vector3(0, 0, 0.012), Vector3(0, h, 0.012), Vector3(0, h, -0.012), stem)
	for k in 5:
		var a := k * TAU / 5.0
		var d := Vector3(cos(a), 0.25, sin(a)) * 0.07
		var s := Vector3(-sin(a), 0, cos(a)) * 0.03
		var c := Vector3(0, h, 0)
		for v in [c, c + d * 0.6 - s, c + d] + [c, c + d, c + d * 0.6 + s]:
			st.set_color(Color.WHITE)
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var core := Color(1.0, 0.8, 0.2) * 0.9
	core.a = 1.0
	_quad(st, Vector3(-0.02, h + 0.02, -0.02), Vector3(0.02, h + 0.02, -0.02), Vector3(0.02, h + 0.02, 0.02),
			Vector3(-0.02, h + 0.02, 0.02), core)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.9
	var mesh := st.commit()
	mesh.surface_set_material(0, m)
	return mesh


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for v in [a, b, c, a, c, d]:
		st.set_color(col)
		st.set_normal(Vector3.UP)
		st.add_vertex(v)
