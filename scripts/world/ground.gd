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
## Touceiras de flores (modelos): nascem em canteiros, cada canteiro com uma espécie dominante.
const FLOWER_MODELS := {
	"tulips": preload("res://assets/models/flower_tulips.glb"),
	"poppies": preload("res://assets/models/flower_poppies.glb"),
	"daisies": preload("res://assets/models/flower_daisies.glb"),
	"lavender": preload("res://assets/models/flower_lavender.glb"),
	"bluebells": preload("res://assets/models/flower_bluebells.glb"),
}
const FLOWER_DENSITY := 0.05
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


# ================================================================ montanhas
## Relevo: o chão jogável é plano (y = 0) e as montanhas sobem dele. Dois tipos:
##  - maciços dentro do mapa (add_mountain): com colisão, árvores e capim nas encostas;
##  - serra em volta do mapa (border_mountains): fora da borda, só visual (cercam o vale).
## A altura sai de uma função determinística (mesmo ruído no servidor e nos clientes).
const MTN_SINK := 0.25   # a malha afunda um pouco: a base some sob o plano de grama, sem emenda
var _peaks: Array[Vector4] = []   # (cx, cz, raio, altura)
var _ring_height := 0.0
var _mnoise: FastNoiseLite


func _mtn_noise() -> FastNoiseLite:
	if _mnoise == null:
		_mnoise = FastNoiseLite.new()
		_mnoise.seed = 4127
		_mnoise.frequency = 0.02
		_mnoise.fractal_octaves = 3
	return _mnoise


## Maciço dentro do mapa: centro, raio da base (m) e altura do pico (m).
func add_mountain(center: Vector3, radius: float, height: float) -> void:
	_peaks.append(Vector4(center.x, center.z, radius, height))


## Serra em volta do mapa, a partir da borda (altura típica dos picos).
func border_mountains(height: float) -> void:
	_ring_height = height


## Altura do terreno em (x, z); 0 no chão plano.
func height_at(x: float, z: float) -> float:
	return maxf(_peak_h(x, z), _ring_h(x, z))


## Inclinação (0 = plano, 1 = vertical) pela diferença de alturas em volta.
func slope_at(x: float, z: float) -> float:
	var e := 0.75
	var dx := height_at(x + e, z) - height_at(x - e, z)
	var dz := height_at(x, z + e) - height_at(x, z - e)
	var n := Vector3(-dx, 2.0 * e, -dz).normalized()
	return 1.0 - n.y


## True se (x, z) cai em algum maciço interno (mais a margem).
func on_mountain(p: Vector2, margin := 0.0) -> bool:
	for pk in _peaks:
		if p.distance_to(Vector2(pk.x, pk.y)) < pk.z + margin:
			return true
	return false


func _peak_h(x: float, z: float) -> float:
	var best := 0.0
	for pk in _peaks:
		var dx := x - pk.x
		var dz := z - pk.y
		var d2 := dx * dx + dz * dz
		if d2 >= pk.z * pk.z:
			continue
		var n := _mtn_noise()
		var d := sqrt(d2) / pk.z
		# contorno irregular (o raio varia com a direção), sem degrau na borda
		var warp := n.get_noise_2d(x * 0.7 + 517.0, z * 0.7 - 211.0) * 0.3
		d = clampf(d + warp * minf(1.0, (1.0 - d) * 3.0), 0.0, 1.0)
		var s := 1.0 - d
		var shape := s * s * (3.0 - 2.0 * s) * 0.45 + pow(s, 1.7) * 0.55
		var ridge := 1.0 - absf(n.get_noise_2d(x * 2.2, z * 2.2))
		best = maxf(best, pk.w * shape * (0.72 + 0.4 * ridge))
	return best


func _ring_h(x: float, z: float) -> float:
	if _ring_height <= 0.0:
		return 0.0
	var out := maxf(absf(x), absf(z)) - (half + 1.0)
	if out <= 0.0:
		return 0.0
	var n := _mtn_noise()
	var big := n.get_noise_2d(x * 0.35 + 900.0, z * 0.35 - 400.0)        # picos e vales da serra
	var ridge := 1.0 - absf(n.get_noise_2d(x * 1.1, z * 1.1 + 300.0))      # cristas
	var rise := smoothstep(0.0, 75.0, out)
	return _ring_height * rise * maxf(0.15, 0.62 + 0.5 * big + 0.3 * ridge) + out * 0.04


## Monta a malha (cliente) e a colisão (sempre, também no servidor) do relevo. Chamar depois de
## add_mountain/border_mountains.
func build_terrain() -> void:
	var visual := DisplayServer.get_name() != "headless"
	for pk in _peaks:
		var r := pk.z + 1.0
		_terrain_grid(Rect2(pk.x - r, pk.y - r, r * 2.0, r * 2.0), 1.6, false, true, visual)
	if _ring_height > 0.0 and visual:
		var ext := half + 150.0
		_terrain_grid(Rect2(-ext, -ext, ext * 2.0, ext * 2.0), 5.0, true, false, true)
		_ring_forest()


func _terrain_grid(rect: Rect2, step: float, ring: bool, collide: bool, visual: bool) -> void:
	var nx := int(ceil(rect.size.x / step))
	var nz := int(ceil(rect.size.y / step))
	var hs := PackedFloat32Array()
	hs.resize((nx + 1) * (nz + 1))
	for iz in nz + 1:
		for ix in nx + 1:
			var x := rect.position.x + ix * step
			var z := rect.position.y + iz * step
			hs[iz * (nx + 1) + ix] = _ring_h(x, z) if ring else _peak_h(x, z)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var n := _mtn_noise()
	for iz in nz:
		for ix in nx:
			var i00 := iz * (nx + 1) + ix
			var h00 := hs[i00]
			var h10 := hs[i00 + 1]
			var h01 := hs[i00 + nx + 1]
			var h11 := hs[i00 + nx + 2]
			if maxf(maxf(h00, h10), maxf(h01, h11)) < 0.02:
				continue
			var x0 := rect.position.x + ix * step
			var z0 := rect.position.y + iz * step
			var a := Vector3(x0, h00 - MTN_SINK, z0)
			var b := Vector3(x0 + step, h10 - MTN_SINK, z0)
			var c := Vector3(x0, h01 - MTN_SINK, z0 + step)
			var d := Vector3(x0 + step, h11 - MTN_SINK, z0 + step)
			# diagonal alternada: facetas em losango, menos "grade"
			if (ix + iz) % 2 == 0:
				_terrain_tri(verts, norms, cols, a, b, d, ring, n)
				_terrain_tri(verts, norms, cols, a, d, c, ring, n)
			else:
				_terrain_tri(verts, norms, cols, a, b, c, ring, n)
				_terrain_tri(verts, norms, cols, b, d, c, ring, n)
	if verts.is_empty():
		return
	if visual:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_COLOR] = cols
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 1.0
		m.metallic_specular = 0.25
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
		mesh.surface_set_material(0, m)
		var mi := MeshInstance3D.new()
		mi.name = "Mountains" if ring else "Mountain"
		mi.mesh = mesh
		add_child(mi)
	if collide:
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(verts)
		var body := StaticBody3D.new()
		body.name = "MountainBody"
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		add_child(body)


func _terrain_tri(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray,
		a: Vector3, b: Vector3, c: Vector3, ring: bool, n: FastNoiseLite) -> void:
	var nr := (a - c).cross(a - b).normalized()   # normal da face da frente no Godot
	if nr.y < 0.0:
		var t := b
		b = c
		c = t
		nr = -nr
	var cen := (a + b + c) / 3.0
	var h := cen.y + MTN_SINK
	var slope := 1.0 - nr.y
	var v := n.get_noise_2d(cen.x * 3.0, cen.z * 3.0) * 0.5 + 0.5
	var jit := 0.93 + 0.14 * fposmod(sin(cen.x * 12.9898 + cen.z * 78.233) * 43758.5453, 1.0)
	# grama (a mesma do chão na base), mata mais escura nas encostas baixas da serra, rocha nas
	# faces íngremes e no alto, neve nos topos da serra
	var grass := Color(0.27, 0.45, 0.16).lerp(Color(0.2, 0.37, 0.13), v)
	if ring:
		grass = grass.lerp(Color(0.16, 0.3, 0.14), smoothstep(4.0, 20.0, h) * 0.7)
	var rock := Color(0.47, 0.44, 0.4).lerp(Color(0.33, 0.31, 0.3), v)
	var t_rock := smoothstep(0.24, 0.42, slope) + smoothstep(14.0, 32.0, h) * 0.5
	var col := grass.lerp(rock, clampf(t_rock, 0.0, 1.0))
	if ring:
		var line := _ring_height * 0.62 + n.get_noise_2d(cen.x * 0.8, cen.z * 0.8) * 10.0
		if h > line and slope < 0.62:
			col = Color(0.9, 0.92, 0.96).lerp(Color(0.78, 0.82, 0.9), v)
	col = Color(col.r * jit, col.g * jit, col.b * jit)
	verts.append(a)
	verts.append(b)
	verts.append(c)
	for k in 3:
		norms.append(nr)
		cols.append(col)


## Abetos e pinheiros nas encostas baixas da serra (MultiMesh, sem colisão: fica fora da borda).
func _ring_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	var fir := _glb_mesh(load("res://assets/models/tree_fir.glb"))
	var pine := _glb_mesh(load("res://assets/models/tree_pine.glb"))
	var firs: Array[Transform3D] = []
	var pines: Array[Transform3D] = []
	var n := _mtn_noise()
	var ext := half + 70.0
	for i in 2600:
		var p := Vector2(rng.randf_range(-ext, ext), rng.randf_range(-ext, ext))
		var out := maxf(absf(p.x), absf(p.y)) - (half + 1.0)
		if out < 2.0:
			continue
		var h := _ring_h(p.x, p.y)
		if h > _ring_height * 0.5 or slope_at(p.x, p.y) > 0.4:
			continue
		if n.get_noise_2d(p.x * 1.5 + 77.0, p.y * 1.5) < -0.15 + smoothstep(5.0, 30.0, h) * 0.4:
			continue   # bosques com clareiras, mais ralo para cima
		var s := rng.randf_range(1.0, 1.9)
		var xf := Transform3D(Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.2), s)),
				Vector3(p.x, h - MTN_SINK - 0.1, p.y))
		if rng.randf() < 0.65:
			firs.append(xf)
		else:
			pines.append(xf)
	_chunk(fir, firs, [], Vector3.ZERO, 0.0, false, true)
	_chunk(pine, pines, [], Vector3.ZERO, 0.0, false, true)


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
	var flower_meshes := {}
	for k in FLOWER_MODELS:
		flower_meshes[k] = _glb_mesh(FLOWER_MODELS[k])
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
				var y := _ground_y(p)
				if y < 0.0:
					continue   # encosta íngreme ou alto demais
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
					flowers.append(Transform3D(bas, Vector3(p.x, y, p.y)))
					fcols.append(FLOWER_COLORS[rng.randi() % FLOWER_COLORS.size()])
				else:
					tufts.append(Transform3D(bas, Vector3(p.x, y, p.y)))
					var v := rng.randf_range(0.85, 1.15)
					tints.append(Color(v, v * rng.randf_range(0.95, 1.05), v))
			var center := Vector3(x0 + CHUNK / 2.0, 0, z0 + CHUNK / 2.0)
			_chunk(tuft, tufts, tints, center, 60.0, true)
			_chunk(flower, flowers, fcols, center, 50.0, false)
			_scatter_plants(rng, clump, plant_meshes, box, plants, shapes, grassy, outs, few, center)
			_scatter_flowers(rng, clump, flower_meshes, box, plants, shapes, grassy, outs, few, center)


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
		var y := _ground_y(p)
		if y < 0.0:
			continue
		var t := rng.randf()
		var s := rng.randf_range(1.0, 1.5) if t < 0.45 else rng.randf_range(0.9, 1.7)
		var bas := Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.15), s))
		var xf := Transform3D(bas, Vector3(p.x, y, p.y))
		if t < 0.45:
			ferns.append(xf)
		elif t < 0.87:
			bushes.append(xf)
		else:
			berries.append(xf)
	_chunk(meshes["fern"], ferns, [], center, 70.0, false)
	_chunk(meshes["bush"], bushes, [], center, 110.0, false, true)
	_chunk(meshes["bush_berry"], berries, [], center, 110.0, false, true)


## Touceiras de flores em canteiros: um ruído de baixa frequência marca os canteiros e outro
## escolhe a espécie de cada região (canteiro de tulipas, de papoulas...), com algumas misturadas.
func _scatter_flowers(rng: RandomNumberGenerator, clump: FastNoiseLite, meshes: Dictionary, box: Rect2,
		amount: float, shapes: Array, grassy: Array, outs: Array, few: Array, center: Vector3) -> void:
	var kinds: Array = meshes.keys()
	var by_kind := {}
	for k in kinds:
		var arr: Array[Transform3D] = []
		by_kind[k] = arr
	for i in int(box.get_area() * FLOWER_DENSITY * amount * 3.0):
		var p := box.position + Vector2(rng.randf(), rng.randf()) * box.size
		var bed := clump.get_noise_2d(p.x * 1.3 - 431.0, p.y * 1.3 + 157.0) * 0.5 + 0.5
		if rng.randf() > 0.04 + 0.96 * smoothstep(0.58, 0.72, bed):
			continue
		if not shapes.is_empty() and shape_distance(p, shapes) < 0.8:
			continue
		if _grassy_at(p, grassy) >= 0.0 or _inside(p, few) or _inside_grown(p, outs, 0.4):
			continue
		var y := _ground_y(p)
		if y < 0.0:
			continue
		var pick := clump.get_noise_2d(p.x * 0.35 + 913.0, p.y * 0.35 - 77.0) * 0.5 + 0.5
		var ki := clampi(int(pick * kinds.size() * 1.6 - kinds.size() * 0.3), 0, kinds.size() - 1)
		if rng.randf() < 0.2:
			ki = rng.randi() % kinds.size()
		var s := rng.randf_range(0.8, 1.35)
		var bas := Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.2), s))
		by_kind[kinds[ki]].append(Transform3D(bas, Vector3(p.x, y, p.y)))
	for k in kinds:
		_chunk(meshes[k], by_kind[k], [], center, 55.0, false)


## Altura do chão para decoração em p; -1 = não plante (encosta íngreme ou alto na montanha).
func _ground_y(p: Vector2) -> float:
	if _peaks.is_empty() or not on_mountain(p):
		return 0.0
	var h := _peak_h(p.x, p.y)
	if h < 0.05:
		return 0.0
	if h > 6.0 or slope_at(p.x, p.y) > 0.35:   # capim só no pé do morro (de longe vira névoa)
		return -1.0
	return h - MTN_SINK - 0.03


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
	if far > 0.0:
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
