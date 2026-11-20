@tool
class_name MapRiver
extends Node3D
## Rio rebaixado: o caminho são os filhos Ponto0, Ponto1... (MapWaypoint; arraste no 3D, a ordem na árvore é a
## ordem do rio, Ctrl+D num ponto acrescenta outro). O chão some numa faixa ao longo do caminho (ground.gd) e no
## lugar entram a margem inclinada e a água animada, abaixo do nível do chão. Paredes na beira da margem (camada
## WALL_LAYER: jogador e monstros batem, a câmera não) seguram todo mundo fora da água, menos onde há ponte (um
## MapProp com modelo "bridge_*" sobre o rio). Capim e flores não nascem no rio. Rio é plano (y = 0).

const WATER_SHADER := preload("res://assets/shaders/river_water.gdshader")
## Camada das paredes do rio (jogador e monstros têm no collision_mask; a mola da câmera, não).
const WALL_LAYER := 32
## Passo da amostragem do caminho suavizado (m).
const STEP := 2.0
## Meia largura da passagem de uma ponte (bridge_stone tem 5,6 m de largura, 15,2 m de comprimento).
const BRIDGE_HALF := {"bridge_stone": Vector2(2.8, 7.6)}
## Distância média entre os enfeites da margem (m).
const DECOR_STEP := 6.0

## Largura da água (m).
@export var width := 7.0:
	set(v):
		width = v
		_changed()
## Largura da margem inclinada de cada lado (m), da água até o nível do chão.
@export var bank := 2.0:
	set(v):
		bank = v
		_changed()
## Altura da água (abaixo do chão).
@export var water_y := -0.45:
	set(v):
		water_y = v
		_changed()
## Velocidade da correnteza (m/s; negativa = corre do último ponto para o primeiro).
@export var flow := 1.2
## Cor da água funda (meio) e rasa (beiras).
@export var deep_color := Color(0.09, 0.27, 0.36)
@export var shallow_color := Color(0.2, 0.47, 0.5)
## Brilho da água (0 = água; ~2,5 = lava: a cor acende e borra com o glow da tela).
@export var glow := 0.0
## Cor da espuma da beira (água: branca; lava: amarela).
@export var foam_color := Color(0.86, 0.93, 0.92)
## Planta da beira (modelo de assets/models: fern, reeds...; vazio = nenhuma) e se há pedras na beira.
@export var bank_plant := "fern"
@export var bank_rocks := true
## Sorteio das pedras e plantas da margem.
@export var decor_seed := 7
## Cor da margem: barranco de cima (perto do capim), terra e lama molhada (perto da água).
@export var bank_top := Color(0.33, 0.33, 0.18)
@export var bank_mid := Color(0.36, 0.27, 0.17)
@export var bank_wet := Color(0.2, 0.16, 0.12)


func _ready() -> void:
	if Engine.is_editor_hint():
		set_notify_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		_changed()


## Um ponto do caminho foi arrastado (MapWaypoint chama).
func waypoints_changed() -> void:
	_changed()


func _changed() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		MapRoot.ground_changed(self)


func _root() -> Node:
	var p := get_parent()
	while p != null and not p is MapRoot:
		p = p.get_parent()
	return p


## Meia largura da faixa sem chão (água + margem).
func half_total() -> float:
	return width / 2.0 + bank


## Pontos de controle (x, z) no espaço do mapa.
func control_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	var root := _root()
	for c in get_children():
		if c is MapWaypoint:
			var o: Vector3 = MapData.local_xform(root, c).origin if root != null else c.position
			out.append(Vector2(o.x, o.z))
	return out


## Caminho suavizado (Catmull-Rom), um ponto a cada ~STEP m, no espaço do mapa.
func samples() -> PackedVector2Array:
	return smooth(control_points(), STEP)


static func smooth(cp: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if cp.size() < 2:
		return out
	for i in cp.size() - 1:
		var p0 := cp[maxi(i - 1, 0)]
		var p1 := cp[i]
		var p2 := cp[i + 1]
		var p3 := cp[mini(i + 2, cp.size() - 1)]
		var n := maxi(1, ceili(p1.distance_to(p2) / step))
		for k in n:
			var t := float(k) / n
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
					+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(cp[cp.size() - 1])
	return out


## Distância de um ponto (x, z do mapa) até o eixo do rio.
static func distance_to(pts: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	for i in pts.size() - 1:
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1]).distance_to(p))
	return best


## Discos sem capim ao longo do rio, no espaço do mapa + `offset`: [[Vector2, raio], ...].
func grass_discs(offset := Vector2.ZERO) -> Array:
	var out: Array = []
	var pts := samples()
	var r := half_total() + 0.6
	var acc := INF
	for i in pts.size():
		if i > 0:
			acc += pts[i].distance_to(pts[i - 1])
		if acc >= r * 0.6 or i == pts.size() - 1:
			out.append([pts[i] + offset, r])
			acc = 0.0
	return out


## Pontes sobre este rio: [{center: Vector2, along: Vector2 (eixo da travessia), half: Vector2}] no mapa.
func bridges() -> Array:
	var out: Array = []
	var root := _root()
	if root == null:
		return out
	for p: MapProp in root.pieces(MapProp):
		if not BRIDGE_HALF.has(p.model):
			continue
		var xf := MapData.local_xform(root, p)
		var along := Vector2(xf.basis.z.x, xf.basis.z.z).normalized()
		var s := p.scale.x
		out.append({"center": Vector2(xf.origin.x, xf.origin.z), "along": along, "half": BRIDGE_HALF[p.model] * s})
	return out


static func _in_bridge(p: Vector2, bridges_list: Array, margin := 0.1) -> bool:
	for b in bridges_list:
		var d: Vector2 = p - b.center
		var al: float = d.dot(b.along)
		var ac: float = d.dot(Vector2(-b.along.y, b.along.x))
		if absf(ac) < b.half.x - margin and absf(al) < b.half.y + 1.0:
			return true
	return false


# ---------------------------------------------------------------- montagem (jogo e prévia)

func build_preview(_height: Callable = Callable()) -> void:
	var p := MapPreview.fresh(self)
	_build(p, true, false)
	for i in get_child_count():
		var c := get_child(i)
		if c is MapWaypoint:
			(c as MapWaypoint).draw_marker(0.0, c.get_index())
	MapPreview.toon(p)


## Monta o rio no jogo: malhas (com tela) e paredes (sempre: o servidor também precisa delas).
func build_game() -> void:
	var holder := Node3D.new()
	holder.name = "Built"
	add_child(holder)
	_build(holder, DisplayServer.get_name() != "headless", true)


func _build(holder: Node3D, visual: bool, walls: bool) -> void:
	var root := _root()
	if root != null:
		holder.transform = MapData.local_xform(root, self).affine_inverse()   # desenha no espaço do mapa
	var pts := samples()
	if pts.size() < 2:
		return
	var nrm := _normals(pts)
	if visual:
		var bm := _bank_mesh(pts, nrm)
		holder.add_child(bm)
		holder.add_child(_water_mesh(pts, nrm))
		_decor(holder, pts, nrm, bridges())
	if walls:
		holder.add_child(_walls(pts, nrm, bridges()))


static func _normals(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in pts.size():
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, pts.size() - 1)]
		var t := (b - a).normalized()
		out.append(Vector2(-t.y, t.x))
	return out


## Perfil da margem, da água para fora: [distância do eixo, altura, cor 0 molhada / 1 terra / 2 barranco].
func _profile() -> Array:
	var w := width / 2.0
	return [[w - 1.2, water_y - 0.6, 0], [w - 0.1, water_y - 0.12, 0], [w + bank * 0.3, water_y + 0.12, 1],
		[w + bank * 0.62, -0.17, 1], [w + bank * 0.85, -0.05, 2], [w + bank + 0.2, -0.03, 2]]


func _bank_mesh(pts: PackedVector2Array, nrm: PackedVector2Array) -> MeshInstance3D:
	var prof := _profile()
	var cols := [bank_wet, bank_mid, bank_top]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		for i in pts.size() - 1:
			for k in prof.size() - 1:
				var a := _pv(pts[i], nrm[i], side, prof[k])
				var b := _pv(pts[i + 1], nrm[i + 1], side, prof[k])
				var c := _pv(pts[i + 1], nrm[i + 1], side, prof[k + 1])
				var d := _pv(pts[i], nrm[i], side, prof[k + 1])
				var col: Color = cols[prof[k + 1][2]]
				var j := 0.94 + 0.12 * fposmod(sin(pts[i].x * 12.99 + pts[i].y * 78.23 + k * 3.1) * 43758.5, 1.0)
				col = Color(col.r * j, col.g * j, col.b * j)
				_quad(st, a, b, c, d, col)
	# pontas arredondadas (charco e poça fecham; o rio do Vale some dentro da serra)
	for e in _ends(pts, nrm):
		for q in CAP_STEPS:
			for k in prof.size() - 1:
				var a := _cv(e, q, prof[k])
				var b := _cv(e, q + 1, prof[k])
				var c := _cv(e, q + 1, prof[k + 1])
				var d := _cv(e, q, prof[k + 1])
				_quad(st, a, b, c, d, cols[prof[k + 1][2]])
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	mesh.surface_set_material(0, m)
	var mi := MeshInstance3D.new()
	mi.name = "RiverBank"
	mi.mesh = mesh
	return mi


const CAP_STEPS := 8


## Pontas do rio: [ponto, normal, direção para fora].
static func _ends(pts: PackedVector2Array, nrm: PackedVector2Array) -> Array:
	var n := pts.size()
	return [[pts[0], nrm[0], (pts[0] - pts[1]).normalized()],
		[pts[n - 1], -nrm[n - 1], (pts[n - 1] - pts[n - 2]).normalized()]]


## Direção do passo `q` da ponta (de um lado do rio, contornando a ponta, até o outro).
static func _cap_dir(e: Array, q: int) -> Vector2:
	var a := PI * float(q) / CAP_STEPS
	return (e[1] as Vector2) * cos(a) + (e[2] as Vector2) * sin(a)


static func _cv(e: Array, q: int, pr: Array) -> Vector3:
	var p: Vector2 = (e[0] as Vector2) + _cap_dir(e, q) * float(pr[0])
	return Vector3(p.x, float(pr[1]), p.y)


static func _pv(p: Vector2, n: Vector2, side: float, pr: Array) -> Vector3:
	var q: Vector2 = p + n * side * float(pr[0])
	return Vector3(q.x, float(pr[1]), q.y)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for tri in [[a, b, c], [a, c, d]]:
		var n: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0]).normalized()
		if n.y < 0.0:
			n = -n
			tri = [tri[0], tri[2], tri[1]]
		st.set_color(col)
		st.set_normal(n)
		for v in tri:
			st.add_vertex(v)


func _water_mesh(pts: PackedVector2Array, nrm: PackedVector2Array) -> MeshInstance3D:
	var w := width / 2.0 + 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	for i in pts.size() - 1:
		var u0 := along
		along += pts[i].distance_to(pts[i + 1])
		var u1 := along
		var a := pts[i] - nrm[i] * w
		var b := pts[i] + nrm[i] * w
		var c := pts[i + 1] + nrm[i + 1] * w
		var d := pts[i + 1] - nrm[i + 1] * w
		var verts := [[a, Vector2(u0, -1)], [b, Vector2(u0, 1)], [c, Vector2(u1, 1)], [a, Vector2(u0, -1)],
			[c, Vector2(u1, 1)], [d, Vector2(u1, -1)]]
		for v in verts:
			st.set_normal(Vector3.UP)
			st.set_uv(v[1])
			st.add_vertex(Vector3(v[0].x, water_y, v[0].y))
	for e in _ends(pts, nrm):   # leque na ponta: a borda de fora com espuma (v = ±1)
		for q in CAP_STEPS:
			var c0: Vector2 = e[0]
			var r0 := c0 + _cap_dir(e, q) * w
			var r1 := c0 + _cap_dir(e, q + 1) * w
			for v in [[c0, 0.0], [r0, 1.0], [r1, 1.0]]:
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(along * 0.5, v[1]))
				st.add_vertex(Vector3(v[0].x, water_y, v[0].y))
	st.index()
	var mesh := st.commit()
	# a ordem dos triângulos depende do lado da normal: o material desenha os dois lados
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	mat.set_shader_parameter("deep", deep_color)
	mat.set_shader_parameter("shallow", shallow_color)
	mat.set_shader_parameter("flow", flow)
	mat.set_shader_parameter("glow", glow)
	mat.set_shader_parameter("foam", foam_color)
	mat.set_shader_parameter("noise_tex", _noise())
	mat.set_shader_parameter("toon", ToonLook.enabled())
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "RiverWater"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _noise() -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.frequency = 0.03
	n.fractal_octaves = 2
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.generate_mipmaps = true
	t.noise = n
	return t


## Pedras na beira d'água e samambaias no barranco, sorteadas sempre do mesmo jeito (sem colisão).
func _decor(holder: Node3D, pts: PackedVector2Array, nrm: PackedVector2Array, bridges_list: Array) -> void:
	var rock: PackedScene = load(MapProp.model_path("rock")) if bank_rocks else null
	var fern: PackedScene = load(MapProp.model_path(bank_plant)) if bank_plant != "" else null
	var rng := RandomNumberGenerator.new()
	rng.seed = decor_seed
	var w := width / 2.0
	var acc := 0.0
	for i in range(1, pts.size()):
		acc += pts[i].distance_to(pts[i - 1])
		if acc < DECOR_STEP:
			continue
		acc = rng.randf_range(-1.5, 1.5)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var c := pts[i]
		if _in_bridge(c, bridges_list, -3.0):
			continue
		var n := nrm[i] * side
		if rock != null and rng.randf() < 0.75:
			var q := c + n * rng.randf_range(w - 0.3, w + 0.5)
			var s := rng.randf_range(0.45, 0.85)
			_place(holder, rock, Vector3(q.x, water_y - 0.3 * s, q.y), s, rng.randf() * TAU)
			if rng.randf() < 0.4:   # uma pedrinha ao lado
				var q2 := q + (pts[i] - pts[i - 1]).normalized() * rng.randf_range(0.7, 1.2)
				_place(holder, rock, Vector3(q2.x, water_y - 0.12, q2.y), s * 0.45, rng.randf() * TAU)
		for k in (rng.randi_range(1, 3) if fern != null else 0):
			var q := c + n * rng.randf_range(w + bank * 0.8, w + bank + 0.4) 					+ (pts[i] - pts[i - 1]).normalized() * rng.randf_range(-1.2, 1.2)
			_place(holder, fern, Vector3(q.x, -0.06, q.y), rng.randf_range(0.7, 1.15), rng.randf() * TAU)


static func _place(holder: Node3D, ps: PackedScene, pos: Vector3, s: float, yaw: float) -> void:
	var inst: Node3D = ps.instantiate()
	inst.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), pos)
	holder.add_child(inst)


## Paredes nas duas beiras (fora da margem), abertas onde uma ponte cruza.
func _walls(pts: PackedVector2Array, nrm: PackedVector2Array, bridges_list: Array) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "RiverWalls"
	body.collision_layer = WALL_LAYER
	body.collision_mask = 0
	var off := half_total() - 0.2
	for side in [-1.0, 1.0]:
		for i in pts.size() - 1:
			var a: Vector2 = pts[i] + nrm[i] * side * off
			var b: Vector2 = pts[i + 1] + nrm[i + 1] * side * off
			# em pedaços de ~0,4 m: os que caem na passagem da ponte saem, os vizinhos viram uma caixa só
			var n := maxi(1, ceili(a.distance_to(b) / 0.4))
			var run_start := -1
			for k in n + 1:
				var inside := k == n
				if k < n:
					inside = _in_bridge(a.lerp(b, (k + 0.5) / n), bridges_list)
				if not inside and run_start < 0:
					run_start = k
				elif inside and run_start >= 0:
					_wall_box(body, a.lerp(b, float(run_start) / n), a.lerp(b, float(k) / n), k < n)
					run_start = -1
	for e in _ends(pts, nrm):
		for q in CAP_STEPS:
			var c0: Vector2 = e[0]
			_wall_box(body, c0 + _cap_dir(e, q) * off, c0 + _cap_dir(e, q + 1) * off, false)
	return body


## Caixa de parede de `a` a `b`; `tight` = encosta na ponte (sem a sobra que fecha as emendas da curva).
static func _wall_box(body: StaticBody3D, a: Vector2, b: Vector2, tight: bool) -> void:
	var len := a.distance_to(b)
	if len < 0.01:
		return
	var dir := (b - a) / len
	var pad := 0.0 if tight else 0.3
	var mid := (a + b) / 2.0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(len + pad * 2.0, 3.0, 0.5)
	cs.shape = box
	cs.transform = Transform3D(Basis(Vector3.UP, -atan2(dir.y, dir.x)), Vector3(mid.x, 1.0, mid.y))
	body.add_child(cs)
