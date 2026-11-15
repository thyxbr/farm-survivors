class_name ChristmasDecor
extends RefCounted
## Decoração de Natal da vila de Valdoria e da praça, montada por código (sem GLB): árvore de Natal
## enfeitada com bolas, pisca-pisca e estrela; varal de luzes entre os postes; pisca-pisca nos beirais e
## nas empenas das casas; guirlandas nas portas; laços e festão nos lampiões; bengalas doces nas entradas;
## pilhas de presentes e bonecos de neve.
##
## As peças sólidas usam StandardMaterial3D comum, que o autoload Toon converte para o sombreado em dois
## tons como qualquer prop. As lâmpadas usam um shader próprio (assets/shaders/xmas_bulb.gdshader) que
## pisca sozinho e brilha mais à noite: o DayNightFX chama set_night() a cada quadro.

const BULB_SHADER := preload("res://assets/shaders/xmas_bulb.gdshader")

## Cores das lâmpadas (sRGB): vermelho, verde, amarelo, azul, rosa.
const MULTI := [Color(1.0, 0.16, 0.1), Color(0.15, 1.0, 0.3), Color(1.0, 0.78, 0.15), Color(0.25, 0.5, 1.0),
	Color(1.0, 0.35, 0.75)]
## Branco quente (lâmpadas "de festa" nas empenas e no varal da praça).
const WARM := [Color(1.0, 0.82, 0.5), Color(1.0, 0.9, 0.62)]
const RED := Color(0.78, 0.08, 0.08)
const GREEN := Color(0.1, 0.36, 0.2)
const GOLD := Color(0.95, 0.72, 0.2)

## Beirais das casas da vila (tools/blender/village.py), no espaço local da casa (frente = +Z):
## [meia largura do telhado, z do beiral da frente, altura do beiral, altura da cumeeira].
const HOUSE_ROOFS := {
	"house": [2.88, 2.5, 2.62, 5.0],
	"house_b": [2.9, 2.4, 2.25, 5.0],
	"house_c": [2.95, 2.48, 3.48, 5.95],
}
## Porta de cada casa: [x, altura do centro da guirlanda, z da face da porta].
const HOUSE_DOORS := {
	"house": [0.0, 1.9, 2.1],
	"house_b": [0.6, 1.75, 2.1],
	"house_c": [0.0, 1.45, 2.1],
}

static var _bulb_mat: ShaderMaterial = null
static var _bulb_mesh: SphereMesh = null
static var _mats := {}


## Brilho das lâmpadas: 0 de dia, 1 à noite (DayNightFX).
static func set_night(n: float) -> void:
	if _bulb_mat != null:
		_bulb_mat.set_shader_parameter("night", n)


# ================================================================ materiais e malhas
static func mat(c: Color, metallic := 0.0, emission := 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f" % [c.to_html(), metallic, emission]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = 0.35 if metallic > 0.0 else 0.8
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	_mats[key] = m
	return m


static func _bulbs_material() -> ShaderMaterial:
	if _bulb_mat == null:
		_bulb_mat = ShaderMaterial.new()
		_bulb_mat.shader = BULB_SHADER
		_bulb_mesh = SphereMesh.new()
		_bulb_mesh.radius = 0.055
		_bulb_mesh.height = 0.13
		_bulb_mesh.radial_segments = 6
		_bulb_mesh.rings = 3
	return _bulb_mat


static func _piece(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3, rot := Vector3.ZERO,
		shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _sphere(r: float, segs := 8, rings := 5) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = segs
	s.rings = rings
	return s


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _cone(r_bottom: float, r_top: float, h: float, segs := 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.bottom_radius = r_bottom
	c.top_radius = r_top
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


## Tubo ao longo de uma linha de pontos. `color_at(s, ang)` (opcional) pinta por vértice: s = metros
## desde o começo, ang = ângulo em volta do tubo (para listras em espiral). `ref` é um eixo que nunca fica
## paralelo à linha (orienta o anel do tubo).
static func tube(points: PackedVector3Array, radius: float, sides := 5, ref := Vector3.UP,
		color_at := Callable()) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := points.size()
	var dist := 0.0
	var rings: Array = []
	for i in n:
		if i > 0:
			dist += points[i].distance_to(points[i - 1])
		var a := points[maxi(i - 1, 0)]
		var b := points[mini(i + 1, n - 1)]
		var t := (b - a).normalized()
		var side := t.cross(ref)
		if side.length() < 0.01:
			side = t.cross(Vector3.RIGHT if absf(ref.x) < 0.9 else Vector3.FORWARD)
		side = side.normalized()
		var up := side.cross(t).normalized()
		var ring: Array = []
		for k in sides + 1:
			var ang := TAU * k / sides
			var nrm := side * cos(ang) + up * sin(ang)
			ring.append([points[i] + nrm * radius, nrm, dist, ang])
		rings.append(ring)
	for i in n - 1:
		for k in sides:
			var quad := [rings[i][k], rings[i + 1][k], rings[i + 1][k + 1], rings[i][k], rings[i + 1][k + 1], rings[i][k + 1]]
			for v in quad:
				if color_at.is_valid():
					st.set_color(color_at.call(v[2], v[3]))
				st.set_normal(v[1])
				st.add_vertex(v[0])
	return st.commit()


# ================================================================ pisca-pisca
## Pontos de um fio pendurado entre a e b (catenária aproximada por parábola), um a cada `step` metros.
static func sag_points(a: Vector3, b: Vector3, sag: float, step := 0.25) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var n := maxi(2, int(ceil(a.distance_to(b) / step)))
	for i in n + 1:
		var u := float(i) / n
		pts.append(a.lerp(b, u) + Vector3.DOWN * sag * 4.0 * u * (1.0 - u))
	return pts


## Lâmpadas (uma instância de MultiMesh cada) nos pontos dados, com as cores do `palette` alternadas.
## `pattern`: 0 corrida, 1 cintilar, 2 respirar (xmas_bulb.gdshader).
static func bulbs(parent: Node3D, pts: PackedVector3Array, palette: Array, pattern := 0, scale := 1.0) -> MultiMeshInstance3D:
	var mat_ := _bulbs_material()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _bulb_mesh
	mm.instance_count = pts.size()
	for i in pts.size():
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * scale), pts[i]))
		mm.set_instance_color(i, palette[i % palette.size()])
		mm.set_instance_custom_data(i, Color(float(i), float(pattern), 0.0, 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat_
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi


## Fio de luzes pendurado entre dois pontos (no espaço de `parent`): fio verde-escuro e lâmpadas
## penduradas embaixo, a cada `spacing` metros.
static func light_string(parent: Node3D, a: Vector3, b: Vector3, sag := 0.5, palette: Array = MULTI,
		pattern := 0, spacing := 0.42) -> void:
	var wire := sag_points(a, b, sag, 0.3)
	_piece(parent, tube(wire, 0.012, 4), mat(Color(0.06, 0.12, 0.08)), Vector3.ZERO, Vector3.ZERO, false)
	var pts := sag_points(a, b, sag, spacing)
	var hang := PackedVector3Array()
	for i in range(1, pts.size() - 1):   # sem lâmpada colada no poste
		hang.append(pts[i] + Vector3.DOWN * 0.06)
	bulbs(parent, hang, palette, pattern)


## Fio reto com lâmpadas encostadas (beirais e empenas), sem barriga.
static func edge_lights(parent: Node3D, a: Vector3, b: Vector3, palette: Array, pattern := 0, spacing := 0.36) -> void:
	_piece(parent, tube(PackedVector3Array([a, b]), 0.012, 4), mat(Color(0.06, 0.12, 0.08)), Vector3.ZERO,
		Vector3.ZERO, false)
	var n := maxi(1, int(round(a.distance_to(b) / spacing)))
	var pts := PackedVector3Array()
	for i in n + 1:
		pts.append(a.lerp(b, float(i) / n) + Vector3.DOWN * 0.05)
	bulbs(parent, pts, palette, pattern)


## Pisca-pisca numa casa da vila (filho da casa, no espaço dela): beiral da frente em gomos e as duas
## empenas até a cumeeira. `variant` escolhe as cores e o padrão.
static func house_lights(house: Node3D, model: String, variant := 0) -> void:
	if not HOUSE_ROOFS.has(model):
		return
	var r: Array = HOUSE_ROOFS[model]
	var hw: float = r[0]
	var zf: float = r[1]
	var ye: float = r[2]
	var yr: float = r[3]
	var palette: Array = MULTI if variant % 2 == 0 else WARM
	var pattern := variant % 3
	# beiral da frente: gomos pendurados de gancho em gancho (~1 m)
	var hooks := int(round(hw * 2.0 / 0.95))
	for i in hooks:
		var a := Vector3(-hw + 2.0 * hw * i / hooks, ye, zf + 0.04)
		var b := Vector3(-hw + 2.0 * hw * (i + 1) / hooks, ye, zf + 0.04)
		light_string(house, a, b, 0.14, palette, pattern, 0.3)
	# empenas: sobem do beiral da frente até a cumeeira e descem até o de trás
	for sx in [-1.0, 1.0]:
		var x: float = sx * (hw + 0.04)
		edge_lights(house, Vector3(x, ye + 0.08, zf), Vector3(x, yr, 0.0), palette, pattern)
		edge_lights(house, Vector3(x, yr, 0.0), Vector3(x, ye + 0.08, -zf), palette, pattern)


# ================================================================ árvore de Natal
## Camadas da copa: [altura da base, raio, altura].
const TIERS := [[0.7, 1.9, 1.9], [1.6, 1.55, 1.7], [2.45, 1.15, 1.5], [3.25, 0.78, 1.35]]


## Raio da copa na altura y (o maior entre as camadas que passam por ali).
static func _crown_r(y: float) -> float:
	var best := 0.0
	for t in TIERS:
		var f: float = (y - t[0]) / t[2]
		if f >= 0.0 and f <= 1.0:
			best = maxf(best, t[1] * (1.0 - f))
	return best


## Árvore de Natal enfeitada: copa em quatro camadas, bolas coloridas, pisca-pisca em espiral, estrela
## no topo, presentes no pé e uma luz quente que acende à noite. Colisão no tronco.
static func tree(parent: Node3D, pos: Vector3, s := 1.0, seed_value := 1) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var root := Node3D.new()
	root.name = "ChristmasTree"
	root.position = pos
	root.scale = Vector3.ONE * s
	parent.add_child(root)
	_piece(root, _cone(0.24, 0.18, 0.9, 8), mat(Color(0.36, 0.22, 0.12)), Vector3(0, 0.45, 0))
	_piece(root, _cone(0.55, 0.5, 0.35, 10), mat(RED), Vector3(0, 0.17, 0))   # vaso/saia vermelha
	for i in TIERS.size():
		var t: Array = TIERS[i]
		var shade := GREEN if i % 2 == 0 else Color(0.13, 0.42, 0.23)
		_piece(root, _cone(t[1], 0.0, t[2], 11), mat(shade), Vector3(0, t[0] + t[2] * 0.5, 0), Vector3(0, i * 0.5, 0))
	# bolas: em cada camada, na borda de baixo (onde a copa é mais larga)
	var ball_cols := [mat(RED, 0.4), mat(GOLD, 0.6), mat(Color(0.2, 0.4, 0.9), 0.4), mat(Color(0.85, 0.87, 0.92), 0.7)]
	var counts := [10, 8, 7, 4]
	var ball := _sphere(0.11, 8, 5)
	for i in TIERS.size():
		var t: Array = TIERS[i]
		for k in counts[i]:
			var ang: float = TAU * (k + rng.randf_range(-0.2, 0.2)) / counts[i] + i * 0.7
			var f := rng.randf_range(0.12, 0.55)
			var y: float = t[0] + f * t[2]
			var rr: float = t[1] * (1.0 - f) + 0.05
			_piece(root, ball, ball_cols[(k + i) % ball_cols.size()], Vector3(sin(ang) * rr, y, cos(ang) * rr),
				Vector3.ZERO, false)
	# pisca-pisca em espiral (5 voltas), encostado na copa
	var pts := PackedVector3Array()
	var n := 150
	for i in n:
		var u := float(i) / (n - 1)
		var y := 0.85 + u * 3.6
		var ang := u * TAU * 5.0
		var rr := _crown_r(y) + 0.06
		if rr > 0.1:
			pts.append(Vector3(sin(ang) * rr, y, cos(ang) * rr))
	bulbs(root, pts, MULTI, 1, 1.15)
	# estrela: duas estrelas cruzadas, para ler de qualquer lado
	var star := _star_mesh(0.34, 0.15, 0.07)
	var star_m := mat(Color(1.0, 0.82, 0.25), 0.3, 2.2)
	_piece(root, star, star_m, Vector3(0, 4.85, 0), Vector3.ZERO, false)
	_piece(root, star, star_m, Vector3(0, 4.85, 0), Vector3(0, PI / 2, 0), false)
	var glow := OmniLight3D.new()
	glow.position = Vector3(0, 2.6, 0)
	glow.light_color = Color(1.0, 0.78, 0.45)
	glow.omni_range = 7.0
	glow.shadow_enabled = false
	root.add_child(glow)
	DayNightFX.night_light(glow, 1.3)
	# presentes no pé da árvore
	gifts(root, Vector3.ZERO, 6, rng, 1.25, 2.1)
	# colisão no tronco e na saia
	_collider(parent, pos, 0.75 * s, 3.0 * s)
	return root


## Estrela de cinco pontas com espessura (prisma), de frente para +Z.
static func _star_mesh(r_out: float, r_in: float, depth: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim: Array = []
	for i in 10:
		var ang := PI / 2.0 + TAU * i / 10.0
		var r := r_out if i % 2 == 0 else r_in
		rim.append(Vector2(cos(ang) * r, sin(ang) * r))
	for face in [1.0, -1.0]:
		var c := Vector3(0, 0, face * depth)   # o miolo saliente dá volume
		for i in 10:
			var a: Vector2 = rim[i]
			var b: Vector2 = rim[(i + 1) % 10]
			var va := Vector3(a.x, a.y, 0)
			var vb := Vector3(b.x, b.y, 0)
			var tri := [c, va, vb] if face < 0.0 else [c, vb, va]
			var nrm: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
			for v in tri:
				st.set_normal(nrm)
				st.add_vertex(v)
	return st.commit()


## Pilha de presentes em volta de `center`, entre os raios r0 e r1.
static func gifts(parent: Node3D, center: Vector3, n: int, rng: RandomNumberGenerator, r0 := 0.0, r1 := 0.8) -> void:
	var wraps := [RED, Color(0.15, 0.45, 0.25), Color(0.2, 0.35, 0.8), Color(0.92, 0.9, 0.85), Color(0.55, 0.2, 0.6),
		GOLD]
	var ribbons := [GOLD, RED, Color(0.95, 0.95, 0.95), GOLD, Color(0.2, 0.5, 0.25), RED]
	for i in n:
		var ang := TAU * (i + rng.randf_range(-0.25, 0.25)) / n
		var r := rng.randf_range(r0, r1)
		var size := Vector3(rng.randf_range(0.3, 0.55), rng.randf_range(0.22, 0.45), rng.randf_range(0.3, 0.5))
		var k := rng.randi() % wraps.size()
		gift(parent, center + Vector3(sin(ang) * r, 0, cos(ang) * r), size, wraps[k], ribbons[k], rng.randf() * TAU)


## Um presente: caixa embrulhada, duas fitas cruzadas e um laço em cima.
static func gift(parent: Node3D, pos: Vector3, size: Vector3, wrap: Color, ribbon: Color, yaw := 0.0) -> void:
	var g := Node3D.new()
	g.position = pos
	g.rotation.y = yaw
	parent.add_child(g)
	_piece(g, _box(size), mat(wrap), Vector3(0, size.y * 0.5, 0))
	var rm := mat(ribbon, 0.2)
	_piece(g, _box(Vector3(size.x + 0.012, size.y + 0.012, 0.07)), rm, Vector3(0, size.y * 0.5, 0), Vector3.ZERO, false)
	_piece(g, _box(Vector3(0.07, size.y + 0.012, size.z + 0.012)), rm, Vector3(0, size.y * 0.5, 0), Vector3.ZERO, false)
	_bow(g, Vector3(0, size.y + 0.03, 0), ribbon, 0.6, true)


## Laço de fita: duas alças e o nó. `flat` deita o laço (em cima de um presente).
static func _bow(parent: Node3D, pos: Vector3, c: Color, s := 1.0, flat := false) -> void:
	var b := Node3D.new()
	b.position = pos
	b.scale = Vector3.ONE * s
	if flat:
		b.rotation.x = -PI / 2
	parent.add_child(b)
	var m := mat(c, 0.15)
	var loop := _sphere(0.08, 8, 4)
	for sx in [-1.0, 1.0]:
		var mi := _piece(b, loop, m, Vector3(sx * 0.085, 0.02, 0), Vector3(0, 0, sx * 0.5), false)
		mi.scale = Vector3(1.2, 0.75, 0.45)
		_piece(b, _box(Vector3(0.045, 0.16, 0.02)), m, Vector3(sx * 0.05, -0.09, 0), Vector3(0, 0, sx * 0.35), false)
	_piece(b, _sphere(0.04, 6, 3), m, Vector3.ZERO, Vector3.ZERO, false)


# ================================================================ guirlanda, laços, bengala, boneco
## Guirlanda de porta (no espaço de `parent`), de frente para +Z.
static func wreath(parent: Node3D, pos: Vector3, s := 1.0) -> void:
	var w := Node3D.new()
	w.position = pos
	w.scale = Vector3.ONE * s
	parent.add_child(w)
	var t := TorusMesh.new()
	t.inner_radius = 0.13
	t.outer_radius = 0.27
	t.rings = 14
	t.ring_segments = 6
	_piece(w, t, mat(Color(0.1, 0.34, 0.17)), Vector3.ZERO, Vector3(PI / 2, 0, 0), false)
	var berry := _sphere(0.032, 6, 3)
	for i in 7:
		var a := TAU * i / 7.0 + 0.3
		_piece(w, berry, mat(Color(0.85, 0.08, 0.08)), Vector3(cos(a) * 0.2, sin(a) * 0.2, 0.06), Vector3.ZERO, false)
	_bow(w, Vector3(0, -0.2, 0.07), RED, 1.0)


## Festão verde em espiral no poste do lampião, com laço vermelho virado para a praça (+Z do lampião).
static func lamp_garland(lamp: Node3D) -> void:
	var pts := PackedVector3Array()
	for i in 49:
		var u := i / 48.0
		var ang := u * TAU * 3.5
		pts.append(Vector3(sin(ang) * 0.1, 0.75 + u * 1.75, cos(ang) * 0.1))
	_piece(lamp, tube(pts, 0.035, 5), mat(Color(0.12, 0.4, 0.2)), Vector3.ZERO, Vector3.ZERO, false)
	_bow(lamp, Vector3(0, 2.2, 0.12), RED, 1.3)


## Bengala doce listrada (vermelho e branco), com o gancho virado para +X. Fica fincada no chão.
static func candy_cane(parent: Node3D, pos: Vector3, yaw := 0.0, s := 1.0) -> void:
	var pts := PackedVector3Array()
	var h := 1.05
	for i in 15:
		pts.append(Vector3(0, h * i / 14.0, 0))
	var r := 0.17
	for i in range(1, 15):
		var a := PI * i / 14.0
		pts.append(Vector3(r - r * cos(a), h + r * sin(a), 0))
	pts.append(Vector3(2.0 * r, h - 0.12, 0))
	var stripes := func(d: float, ang: float) -> Color:
		return RED if fposmod(d * 5.0 + ang / TAU, 1.0) < 0.5 else Color(0.97, 0.96, 0.94)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = false   # com true, no toon o branco estourava num borrão de glow
	m.roughness = 0.4
	var node := _piece(parent, tube(pts, 0.05, 8, Vector3(0, 0, 1), stripes), m, pos, Vector3(0, yaw, 0))
	node.scale = Vector3.ONE * s


## Boneco de neve de cachecol e cartola, de frente para +Z (gire com `yaw`).
static func snowman(parent: Node3D, pos: Vector3, yaw := 0.0) -> void:
	var sm := Node3D.new()
	sm.name = "Snowman"
	sm.position = pos
	sm.rotation.y = yaw
	parent.add_child(sm)
	var snow := mat(Color(0.94, 0.96, 1.0))
	_piece(sm, _sphere(0.5, 12, 8), snow, Vector3(0, 0.45, 0))
	_piece(sm, _sphere(0.36, 12, 8), snow, Vector3(0, 1.12, 0))
	_piece(sm, _sphere(0.26, 12, 8), snow, Vector3(0, 1.63, 0))
	var coal := mat(Color(0.08, 0.08, 0.1))
	var dot := _sphere(0.035, 6, 3)
	for sx in [-1.0, 1.0]:
		_piece(sm, dot, coal, Vector3(sx * 0.09, 1.7, 0.22), Vector3.ZERO, false)
	for i in 3:
		_piece(sm, dot, coal, Vector3(0, 0.98 + i * 0.13, 0.35 - absf(i - 1) * 0.02), Vector3.ZERO, false)
	for i in 5:   # boca de carvão em arco
		var a := lerpf(-0.6, 0.6, i / 4.0)
		_piece(sm, _sphere(0.022, 5, 3), coal, Vector3(sin(a) * 0.11, 1.56 - cos(a) * 0.04 + 0.04, 0.235), Vector3.ZERO, false)
	_piece(sm, _cone(0.045, 0.0, 0.26, 6), mat(Color(0.95, 0.45, 0.1)), Vector3(0, 1.64, 0.36), Vector3(PI / 2, 0, 0), false)
	var scarf := TorusMesh.new()
	scarf.inner_radius = 0.2
	scarf.outer_radius = 0.3
	scarf.rings = 12
	scarf.ring_segments = 5
	_piece(sm, scarf, mat(RED), Vector3(0, 1.4, 0), Vector3.ZERO, false)
	_piece(sm, _box(Vector3(0.12, 0.34, 0.05)), mat(RED), Vector3(0.14, 1.24, 0.27), Vector3(0.2, 0, 0.15), false)
	var hat := mat(Color(0.1, 0.09, 0.12))
	_piece(sm, _cone(0.3, 0.3, 0.035, 12), hat, Vector3(0, 1.85, 0))
	_piece(sm, _cone(0.18, 0.17, 0.32, 12), hat, Vector3(0, 2.02, 0))
	_piece(sm, _cone(0.185, 0.185, 0.06, 12), mat(RED), Vector3(0, 1.9, 0), Vector3.ZERO, false)
	var wood := mat(Color(0.36, 0.22, 0.12))
	for sx in [-1.0, 1.0]:   # braços de galho
		_piece(sm, _cone(0.025, 0.015, 0.7, 5), wood, Vector3(sx * 0.55, 1.25, 0), Vector3(0, 0, -sx * 1.0), false)
	_collider(parent, pos, 0.5, 1.4)


static func _collider(parent: Node3D, pos: Vector3, r: float, h: float) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = h
	cs.shape = c
	cs.position.y = h * 0.5
	body.add_child(cs)
	parent.add_child(body)
