@tool
class_name MapDungeon
extends Node3D
## Dungeon fechada, debaixo da terra: junta as salas (MapDungeonRoom) e os corredores (MapDungeonPath) da cena numa
## grade de 1 m e monta chão, paredes de rocha irregulares, teto e as colisões (paredes e teto: a câmera fica do
## lado de dentro; o teto só existe visto de baixo, então a câmera passa por ele sem esconder o jogador). Tochas nas paredes, enfeites do tema e, na sala do chefe (`boss`), o portão com estátuas,
## braseiros e a sala escura que acende quando o portão abre (DungeonFX, só com tela).
##
## O teto fica na camada visual CEILING_LAYER: a foto de cima do minimapa (MapCapture) não o desenha.

const CELL := 1.0
## Camada visual do teto (MapCapture tira da foto).
const CEILING_LAYER := 1 << 19
const FX := "res://scripts/world/dungeon_fx.gd"
const KNIGHT := "res://assets/models/knight.glb"

## Temas: cores (sRGB) das paredes (base, faixa, sujeira), chão (dois tons), teto, rugosidade das paredes (m),
## cor e força das tochas e os enfeites (`props`: [modelo, quantos por 100 m de parede, escala mín., máx., tint]).
const THEMES := {
	"raizes": {"wall": [Color(0.3, 0.24, 0.17), Color(0.36, 0.3, 0.2), Color(0.18, 0.2, 0.12)],
		"floor": [Color(0.22, 0.2, 0.14), Color(0.17, 0.21, 0.12)], "ceiling": Color(0.13, 0.11, 0.08), "rough": 0.38,
		"tiles": false, "torch": Color(1.0, 0.78, 0.45), "rune": Color(0.4, 1.0, 0.45),
		"props": [["mushrooms", 3.0, 0.7, 1.3, Color(1, 1, 1, 0)], ["rock", 3.0, 0.6, 1.1, Color(0.28, 0.24, 0.18, 1)],
			["bones", 2.5, 0.8, 1.2, Color(1, 1, 1, 0)]], "stalactites": true, "blood": 0.3,
		"roots": true},
	"mina": {"wall": [Color(0.42, 0.46, 0.52), Color(0.52, 0.57, 0.63), Color(0.3, 0.33, 0.38)],
		"floor": [Color(0.36, 0.37, 0.4), Color(0.3, 0.31, 0.34)], "ceiling": Color(0.2, 0.22, 0.26), "rough": 0.3,
		"tiles": false, "torch": Color(1.0, 0.7, 0.4), "rune": Color(1.0, 0.65, 0.3),
		"props": [["ice_crystal", 3.0, 0.4, 0.8, Color(1, 1, 1, 0)], ["crate", 1.0, 0.9, 1.1, Color(1, 1, 1, 0)],
			["barrel", 1.0, 0.9, 1.1, Color(1, 1, 1, 0)], ["bones", 2.0, 0.8, 1.2, Color(1, 1, 1, 0)]],
		"stalactites": true, "blood": 0.4, "chains": true,
		"beams": true},
	"cripta": {"wall": [Color(0.36, 0.32, 0.3), Color(0.44, 0.4, 0.36), Color(0.24, 0.21, 0.2)],
		"floor": [Color(0.3, 0.27, 0.25), Color(0.24, 0.21, 0.2)], "ceiling": Color(0.16, 0.14, 0.13), "rough": 0.05,
		"tiles": true, "torch": Color(1.0, 0.55, 0.3), "rune": Color(0.7, 0.4, 1.0),
		"props": [["tombstone", 2.5, 0.9, 1.2, Color(1, 1, 1, 0)], ["ruin_pillar", 1.0, 0.7, 0.9, Color(1, 1, 1, 0)],
			["bones", 4.0, 0.8, 1.3, Color(1, 1, 1, 0)]], "blood": 0.7, "chains": true},
	"abismo": {"wall": [Color(0.2, 0.17, 0.24), Color(0.27, 0.22, 0.3), Color(0.12, 0.1, 0.14)],
		"floor": [Color(0.18, 0.15, 0.2), Color(0.14, 0.12, 0.16)], "ceiling": Color(0.08, 0.07, 0.1), "rough": 0.34,
		"tiles": false, "torch": Color(1.0, 0.35, 0.4), "rune": Color(1.0, 0.25, 0.35),
		"props": [["ice_crystal", 3.0, 0.5, 1.0, Color(0.35, 0.12, 0.5, 1)], ["rock", 2.0, 0.6, 1.2, Color(0.14, 0.12, 0.16, 1)],
			["bones", 3.5, 0.8, 1.3, Color(1, 1, 1, 0)]], "stalactites": true, "blood": 0.8, "chains": true},
}

## Estátuas do salão do chefe por tema: [guardiões do portão, par do meio do salão] (modelos de assets/models).
const STATUES := {"raizes": ["wolf_ia", "knight_f"], "mina": ["golem", "forge_golem"], "cripta": ["sentinel", "knight_d"],
	"abismo": ["void_herald", "raptor"]}

@export_enum("raizes", "mina", "cripta", "abismo") var theme := "cripta":
	set(v):
		theme = v
		_changed()
## Sorteio dos enfeites, das tochas e da rugosidade.
@export var seed := 1:
	set(v):
		seed = v
		_changed()
## Distância entre as tochas (m).
@export var torch_step := 9.0
## Fração das tochas que ficam apagadas (só o toco queimado).
@export_range(0.0, 1.0) var dead_torches := 0.3

var _cells := {}        # Vector2i -> altura do teto
var _boss_cells := {}   # Vector2i -> true
var _hall_cells := {}   # Vector2i -> true (salão de pedra lavrada)
var _noise: FastNoiseLite


func _changed() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		MapRoot.ground_changed(self)


func _root() -> Node:
	var p := get_parent()
	while p != null and not p is MapRoot:
		p = p.get_parent()
	return p


# ================================================================ grade
## Monta a grade das células andáveis a partir das salas e corredores da cena.
func layout() -> void:
	_cells = {}
	_boss_cells = {}
	_hall_cells = {}
	var root := _root()
	if root == null:
		return
	for r: MapDungeonRoom in root.pieces(MapDungeonRoom):
		var c3 := MapData.local_xform(root, r).origin
		var c := Vector2(c3.x, c3.z)
		var ext := r.size / 2.0
		for ix in range(floori((c.x - ext.x) / CELL) - 1, ceili((c.x + ext.x) / CELL) + 1):
			for iz in range(floori((c.y - ext.y) / CELL) - 1, ceili((c.y + ext.y) / CELL) + 1):
				var k := Vector2i(ix, iz)
				if r.contains(c, _center(k)):
					_cells[k] = maxf(float(_cells.get(k, 0.0)), r.height)
					if r.boss:
						_boss_cells[k] = true
					if r.hall:
						_hall_cells[k] = true
	for p: MapDungeonPath in root.pieces(MapDungeonPath):
		var pts := p.points(root)
		var hw := p.width / 2.0
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			for ix in range(floori((minf(a.x, b.x) - hw) / CELL) - 1, ceili((maxf(a.x, b.x) + hw) / CELL) + 1):
				for iz in range(floori((minf(a.y, b.y) - hw) / CELL) - 1, ceili((maxf(a.y, b.y) + hw) / CELL) + 1):
					var k := Vector2i(ix, iz)
					var q := _center(k)
					if Geometry2D.get_closest_point_to_segment(q, a, b).distance_to(q) <= hw:
						_cells[k] = maxf(float(_cells.get(k, 0.0)), p.height)


static func _center(k: Vector2i) -> Vector2:
	return Vector2((k.x + 0.5) * CELL, (k.y + 0.5) * CELL)


## Se o ponto (x, z do mapa) fica numa célula andável (montar com layout() antes).
func walkable(p: Vector2) -> bool:
	return _cells.has(Vector2i(floori(p.x / CELL), floori(p.y / CELL)))


func cells() -> Dictionary:
	return _cells


# ================================================================ montagem
func build_preview(_height: Callable = Callable()) -> void:
	var p := MapPreview.fresh(self)
	_build(p, true, false)


## Monta no jogo: malhas e luzes (com tela) e colisões (sempre: o servidor também precisa).
func build_game() -> void:
	var holder := Node3D.new()
	holder.name = "Built"
	add_child(holder)
	_build(holder, DisplayServer.get_name() != "headless", true)


func _build(holder: Node3D, visual: bool, collide: bool) -> void:
	var root := _root()
	if root != null:
		holder.transform = MapData.local_xform(root, self).affine_inverse()   # desenha no espaço do mapa
	layout()
	if _cells.is_empty():
		return
	_noise = FastNoiseLite.new()
	_noise.seed = seed
	_noise.frequency = 0.35
	var th: Dictionary = THEMES[theme]
	if collide:
		holder.add_child(_collision())
	if not visual:
		return
	holder.add_child(_floor_mesh(th))
	holder.add_child(_wall_mesh(th))
	var ceil_mi := _ceiling_mesh(th)
	holder.add_child(ceil_mi)
	# no editor o DungeonFX não roda (não é @tool): a prévia monta tudo parado, portão fechado
	var fx: Node3D = null
	if not Engine.is_editor_hint():
		fx = load(FX).new()
		fx.name = "DungeonFX"
		holder.add_child(fx)
	_torches(holder, fx, th)
	_decor(holder, th)
	_boss_gate(holder, fx, th)


# ---------------------------------------------------------------- colisões
## Chão: uma caixa só. Paredes: cada célula de rocha que encosta numa andável vira caixa (juntas em tiras por
## linha), altas o bastante para segurar a câmera do lado de dentro.
func _collision() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "DungeonBody"
	body.collision_mask = 0
	var r := _bounds().grow(4.0)
	_box(body, Vector3(r.get_center().x, -0.5, r.get_center().y), Vector3(r.size.x, 1.0, r.size.y))
	var rock := {}
	for k: Vector2i in _cells:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1),
				Vector2i(1, -1), Vector2i(-1, -1)]:
			var n: Vector2i = k + d
			if not _cells.has(n):
				rock[n] = true
	for run in _runs(rock, func(_k): return 0.0):
		_box(body, Vector3((run[0] + run[1] + 1) * CELL / 2.0, 6.0, (run[2] + 0.5) * CELL),
			Vector3((run[1] - run[0] + 1) * CELL, 12.0, CELL))
	# o teto não tem colisão: a câmera sobe por ele quando olha de cima (visto de cima ele não é desenhado)
	var g := boss_entrance()
	if not g.is_empty():
		for f in _gate_fill(g):
			var cs := CollisionShape3D.new()
			var b := BoxShape3D.new()
			b.size = f[1]
			cs.shape = b
			cs.transform = Transform3D(Basis(Vector3.UP, f[2]), f[0])
			body.add_child(cs)
	return body


## Tiras horizontais (mesma linha z, x seguidos, mesmo valor): [x0, x1, z, valor].
static func _runs(cells_set: Dictionary, value: Callable) -> Array:
	var rows := {}
	for k: Vector2i in cells_set:
		if not rows.has(k.y):
			rows[k.y] = []
		rows[k.y].append(k.x)
	var out: Array = []
	for z in rows:
		var xs: Array = rows[z]
		xs.sort()
		var start: int = xs[0]
		var prev: int = xs[0]
		var v: float = value.call(Vector2i(start, z))
		for i in range(1, xs.size() + 1):
			var x: int = xs[i] if i < xs.size() else 0
			var vx: float = value.call(Vector2i(x, z)) if i < xs.size() else -1.0
			if i < xs.size() and x == prev + 1 and is_equal_approx(vx, v):
				prev = x
				continue
			out.append([start, prev, z, v])
			if i < xs.size():
				start = x
				prev = x
				v = vx
	return out


static func _box(body: StaticBody3D, center: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = center
	body.add_child(cs)


func _bounds() -> Rect2:
	var r := Rect2()
	var first := true
	for k: Vector2i in _cells:
		var c := Rect2(Vector2(k.x, k.y) * CELL, Vector2(CELL, CELL))
		r = c if first else r.merge(c)
		first = false
	return r


# ---------------------------------------------------------------- malhas
func _mat(emissive := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	if emissive:
		m.emission_enabled = true
	return m


static func _hash(x: float, z: float) -> float:
	return fposmod(sin(x * 12.9898 + z * 78.233) * 43758.5453, 1.0)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	if (c - a).cross(b - a).dot(n) < 0.0:
		var t := b
		b = c
		c = t
	st.set_color(col)
	st.set_normal(n)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	_tri(st, a, b, c, n, col)
	_tri(st, a, c, d, n, col)


## Deslocamento da rocha num ponto (o mesmo para as duas paredes de um canto: sem frestas).
func _disp(p: Vector3, rough: float) -> Vector3:
	if rough <= 0.0:
		return p
	var dx := _noise.get_noise_3d(p.x, p.y * 0.8, p.z)
	var dz := _noise.get_noise_3d(p.x + 71.3, p.y * 0.8, p.z - 33.1)
	return p + Vector3(dx, 0.0, dz) * rough * 1.6


func _floor_mesh(th: Dictionary) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fc: Array = th.floor
	for k: Vector2i in _cells:
		var x0 := k.x * CELL
		var z0 := k.y * CELL
		var col: Color
		if th.tiles:   # lajes de 2 m, tons alternados
			var t := (floori(x0 / 2.0) + floori(z0 / 2.0)) % 2
			col = (fc[absi(t)] as Color) * (0.92 + 0.16 * _hash(floorf(x0 / 2.0), floorf(z0 / 2.0)))
		else:
			var v := _noise.get_noise_2d(x0 * 0.4, z0 * 0.4) * 0.5 + 0.5
			col = (fc[0] as Color).lerp(fc[1], roundf(v)) * (0.94 + 0.12 * _hash(x0, z0))
		if _hall_cells.has(k):   # salão: lajes de 2 m em dois tons da pedra do portão
			var lt := absi((floori(x0 / 2.0) + floori(z0 / 2.0)) % 2)
			col = _masonry(th) * (0.5 + 0.08 * lt) * (0.92 + 0.14 * _hash(floorf(x0 / 2.0), floorf(z0 / 2.0)))
		else:
			# manchas: fuligem em placas e sangue seco perto das paredes (mais nas dungeons fundas)
			var soot := _noise.get_noise_2d(x0 * 0.9 + 40.0, z0 * 0.9) * 0.5 + 0.5
			if soot > 0.68:
				col = col * 0.6
			var blood: float = th.get("blood", 0.0)
			var bn := _noise.get_noise_2d(x0 * 1.7 - 90.0, z0 * 1.7 + 13.0) * 0.5 + 0.5
			if blood > 0.0 and bn > 1.0 - 0.18 * blood and _near_wall(k):
				col = Color(0.22, 0.04, 0.03).lerp(col, 0.35)
		if _boss_cells.has(k):
			col = col * 0.8
		col.a = 1.0
		# a laje passa um pouco por baixo das paredes (a rocha irregular não deixa fresta)
		var g := 0.0
		_quad(st, Vector3(x0 - g, 0, z0 - g), Vector3(x0 + CELL + g, 0, z0 - g), Vector3(x0 + CELL + g, 0, z0 + CELL + g),
			Vector3(x0 - g, 0, z0 + CELL + g), Vector3.UP, col)
	# barra de rocha por baixo das paredes
	for e in _edges():
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var out: Vector3 = e[2]
		var c2 := b + out * 0.9
		var d2 := a + out * 0.9
		_quad(st, a + Vector3(0, 0.001, 0), b + Vector3(0, 0.001, 0), c2, d2, Vector3.UP, (th.wall[2] as Color) * 0.8)
	var mi := MeshInstance3D.new()
	mi.name = "Floor"
	mi.mesh = st.commit()
	mi.material_override = _mat()
	return mi


## Pedra lavrada do portão e do salão do chefe (cor sRGB).
static func _masonry(th: Dictionary) -> Color:
	return (th.wall[1] as Color).lerp(Color(0.5, 0.48, 0.45), 0.4)


## Se um canto da grade (x, z inteiros) encosta numa célula do salão: ali a parede fica reta.
func _hall_pt(p: Vector3) -> bool:
	var ix := roundi(p.x / CELL)
	var iz := roundi(p.z / CELL)
	for d in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		if _hall_cells.has(Vector2i(ix, iz) + d):
			return true
	return false


func _near_wall(k: Vector2i) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(2, 0), Vector2i(-2, 0),
			Vector2i(0, 2), Vector2i(0, -2)]:
		if not _cells.has(k + d):
			return true
	return false


## Bordas entre uma célula andável e a rocha: [ponto a (y = 0), ponto b, direção para a rocha, altura do teto].
func _edges() -> Array:
	var out: Array = []
	for k: Vector2i in _cells:
		var h: float = _cells[k]
		var x0 := k.x * CELL
		var z0 := k.y * CELL
		if not _cells.has(k + Vector2i(1, 0)):
			out.append([Vector3(x0 + CELL, 0, z0), Vector3(x0 + CELL, 0, z0 + CELL), Vector3.RIGHT, h])
		if not _cells.has(k + Vector2i(-1, 0)):
			out.append([Vector3(x0, 0, z0 + CELL), Vector3(x0, 0, z0), Vector3.LEFT, h])
		if not _cells.has(k + Vector2i(0, 1)):
			out.append([Vector3(x0 + CELL, 0, z0 + CELL), Vector3(x0, 0, z0 + CELL), Vector3.BACK, h])
		if not _cells.has(k + Vector2i(0, -1)):
			out.append([Vector3(x0, 0, z0), Vector3(x0 + CELL, 0, z0), Vector3.FORWARD, h])
	return out


func _wall_mesh(th: Dictionary) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rough: float = th.rough
	var wc: Array = th.wall
	for e in _edges():
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var out: Vector3 = e[2]
		var h: float = e[3] + 0.4
		var mid := (a + b) / 2.0
		var hall := _hall_cells.has(Vector2i(floori(mid.x - out.x * 0.5), floori(mid.z - out.z * 0.5)))
		var ra := 0.0 if _hall_pt(a) else rough   # canto do salão: reto (o mesmo para as duas paredes)
		var rb := 0.0 if _hall_pt(b) else rough
		var rows := maxi(2, ceili(h / (0.6 if hall else 1.3)))
		for r in rows:
			var y0 := -0.3 + (h + 0.3) * float(r) / rows
			var y1 := -0.3 + (h + 0.3) * float(r + 1) / rows
			var p0 := _disp(a + Vector3(0, y0, 0), ra)
			var p1 := _disp(b + Vector3(0, y0, 0), rb)
			var p2 := _disp(b + Vector3(0, y1, 0), rb)
			var p3 := _disp(a + Vector3(0, y1, 0), ra)
			# faixas: sujeira embaixo, pedra no meio com veios claros, escuro perto do teto
			var t := float(r) / rows
			var col: Color = wc[0]
			if hall:   # cantaria: fiadas de blocos de 1 m, rodapé e cornija escuros
				var mc := _masonry(th)
				col = mc * (0.8 + 0.24 * _hash(a.x * 1.3 + r * 3.7, a.z * 0.7 - r * 1.9))
				if r == 0 or r == rows - 1:
					col = mc * 0.55
				elif r % 2 == 1:
					col = col * 0.9
			elif t < 0.2:
				col = wc[2]
			elif _hash(a.x + y0, a.z - y0) > 0.72:
				col = wc[1]
			elif t > 0.8:
				col = (wc[0] as Color) * 0.75
			if not hall and th.tiles and r % 2 == 1:   # cripta: fiadas de blocos
				col = col * 0.9
			if not hall:
				col = col * (0.93 + 0.14 * _hash(a.x * 3.1 + y0, a.z * 1.7))
			col.a = 1.0
			var n := -(p1 - p0).cross(p3 - p0).normalized()
			if n.dot(-out) < 0.0:
				n = -n
			_quad(st, p0, p1, p2, p3, n, col)
	# degraus do teto entre células de alturas diferentes (sala alta ao lado de corredor baixo)
	for k: Vector2i in _cells:
		var h: float = _cells[k]
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n2: Vector2i = k + d
			if _cells.has(n2) and float(_cells[n2]) > h + 0.01:
				var hn: float = _cells[n2]
				var mid := Vector3((k.x + 0.5 + d.x * 0.5) * CELL, 0, (k.y + 0.5 + d.y * 0.5) * CELL)
				var side := Vector3(-d.y, 0, d.x) * CELL * 0.5
				var a2 := _disp(mid - side + Vector3(0, h, 0), rough)
				var b2 := _disp(mid + side + Vector3(0, h, 0), rough)
				var c2 := _disp(mid + side + Vector3(0, hn + 0.1, 0), rough)
				var d2 := _disp(mid - side + Vector3(0, hn + 0.1, 0), rough)
				_quad(st, a2, b2, c2, d2, -Vector3(d.x, 0, d.y), (wc[0] as Color) * 0.7)
	var mi := MeshInstance3D.new()
	mi.name = "Walls"
	mi.mesh = st.commit()
	mi.material_override = _mat()
	return mi


func _ceiling_mesh(th: Dictionary) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cc: Color = th.ceiling
	for k: Vector2i in _cells:
		var h: float = _cells[k]
		var x0 := k.x * CELL
		var z0 := k.y * CELL
		var col := cc * (0.9 + 0.2 * _hash(x0, z0))
		col.a = 1.0
		var g := 0.6   # passa por cima das paredes
		var y := h
		_quad(st, Vector3(x0, y, z0), Vector3(x0 + CELL, y, z0), Vector3(x0 + CELL, y, z0 + CELL), Vector3(x0, y, z0 + CELL),
			Vector3.DOWN, col)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not _cells.has(k + d):
				var ox := 0.0 if d.x <= 0 else CELL
				var oz := 0.0 if d.y <= 0 else CELL
				if d.x != 0:
					var xx := x0 + ox
					_quad(st, Vector3(xx, y, z0), Vector3(xx + d.x * g, y, z0), Vector3(xx + d.x * g, y, z0 + CELL),
						Vector3(xx, y, z0 + CELL), Vector3.DOWN, col * 0.8)
				else:
					var zz := z0 + oz
					_quad(st, Vector3(x0, y, zz), Vector3(x0 + CELL, y, zz), Vector3(x0 + CELL, y, zz + d.y * g),
						Vector3(x0, y, zz + d.y * g), Vector3.DOWN, col * 0.8)
	var mi := MeshInstance3D.new()
	mi.name = "Ceiling"
	mi.mesh = st.commit()
	mi.material_override = _mat()
	mi.layers = CEILING_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ---------------------------------------------------------------- tochas e enfeites
## Pontos na parede (fora da sala do chefe): [posição no chão junto à parede, direção para dentro].
func _wall_spots(step: float, rng: RandomNumberGenerator, skip_boss := true) -> Array:
	var spots: Array = []
	var edges := _edges()
	for i in range(edges.size() - 1, 0, -1):   # embaralha com o sorteio da dungeon (igual em todo cliente)
		var j := rng.randi_range(0, i)
		var t = edges[i]
		edges[i] = edges[j]
		edges[j] = t
	for e in edges:
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var mid := (a + b) / 2.0
		var inward: Vector3 = -(e[2] as Vector3)
		var cell := Vector2i(floori((mid.x + inward.x * 0.5) / CELL), floori((mid.z + inward.z * 0.5) / CELL))
		if skip_boss and (_boss_cells.has(cell) or _hall_cells.has(cell)):
			continue
		var ok := true
		for s in spots:
			if (s[0] as Vector3).distance_to(mid) < step:
				ok = false
				break
		if ok:
			spots.append([mid, inward])
	return spots


func _torches(holder: Node3D, fx: Node, th: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 31 + 7
	var tc: Color = th.torch
	for s in _wall_spots(torch_step, rng):
		var p: Vector3 = s[0]
		var inward: Vector3 = s[1]
		var t := Node3D.new()
		t.position = p + inward * 0.25 + Vector3(0, 2.4, 0)
		t.basis = Basis.looking_at(-inward, Vector3.UP)
		holder.add_child(t)
		var dead := rng.randf() < dead_torches   # tocha apagada: só o toco queimado (o escuro fica maior)
		_torch_mesh(t, tc, dead)
		if dead:
			continue
		var l := OmniLight3D.new()
		l.light_color = tc
		l.light_energy = 2.4
		l.omni_range = 9.5
		l.omni_attenuation = 1.6
		l.position = Vector3(0, 0.35, -0.5)
		l.distance_fade_enabled = true
		l.distance_fade_begin = 40.0
		l.distance_fade_length = 10.0
		t.add_child(l)
		if fx != null:
			fx.add_flicker(l)


static func _torch_mesh(parent: Node3D, c: Color, dead := false) -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.25, 0.15, 0.08)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.12, 0.12, 0.13)
	var flame := StandardMaterial3D.new()
	flame.albedo_color = c
	flame.emission_enabled = true
	flame.emission = c
	flame.emission_energy_multiplier = 4.0
	flame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var bracket := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 0.12, 0.35)
	bracket.mesh = bm
	bracket.material_override = iron
	bracket.position = Vector3(0, -0.15, -0.12)
	parent.add_child(bracket)
	var stick := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06
	cm.bottom_radius = 0.04
	cm.height = 0.6
	cm.radial_segments = 6
	stick.mesh = cm
	stick.material_override = wood
	stick.position = Vector3(0, 0.0, -0.3)
	stick.rotation.x = -0.3
	parent.add_child(stick)
	var f := MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 0.13
	fm.height = 0.38
	fm.radial_segments = 6
	fm.rings = 3
	f.mesh = fm
	f.material_override = flame
	f.position = Vector3(0, 0.38, -0.39)
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	f.visible = not dead
	parent.add_child(f)
	if dead:
		wood.albedo_color = Color(0.06, 0.05, 0.05)


func _decor(holder: Node3D, th: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 17 + 3
	var wall_len := float(_edges().size()) * CELL
	for pd in th.props:
		var count := int(wall_len / 100.0 * float(pd[1]))
		var spots := _wall_spots(3.0, rng)
		for i in mini(count, spots.size()):
			var s: Array = spots[i]
			var inst := _model(pd[0], pd[4])
			if inst == null:
				break
			var sc := rng.randf_range(pd[2], pd[3])
			inst.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc),
				(s[0] as Vector3) + (s[1] as Vector3) * rng.randf_range(0.5, 0.9))
			holder.add_child(inst)
	var root := _root()
	for r: MapDungeonRoom in root.pieces(MapDungeonRoom):
		if not r.pillars:
			continue
		var c := MapData.local_xform(root, r).origin
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var inst := _model("ruin_pillar", Color(1, 1, 1, 0))
				inst.position = c + Vector3(sx * r.size.x * 0.3, 0, sz * r.size.y * 0.3)
				inst.scale = Vector3.ONE * (r.height / 4.2)
				holder.add_child(inst)
	if th.get("beams", false):
		_beams(holder, rng)
	if th.get("chains", false):
		_chains(holder, rng)
	if th.get("stalactites", false):
		_stalactites(holder, rng, th)
	if th.get("roots", false):
		_roots(holder, rng)


## Modelo de assets/models (com `tint` se alfa > 0).
static func _model(name: String, tint: Color) -> Node3D:
	var path := MapProp.model_path(name)
	if not ResourceLoader.exists(path):
		return null
	var inst: Node3D = (load(path) as PackedScene).instantiate()
	if tint.a > 0.0:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(tint, 1.0)
		m.roughness = 1.0
		for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
			mi.material_override = m
	return inst


## Mina: escoras de madeira atravessando os corredores (dois esteios e uma viga).
func _beams(holder: Node3D, rng: RandomNumberGenerator) -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.23, 0.12)
	var root := _root()
	for p: MapDungeonPath in root.pieces(MapDungeonPath):
		var pts := p.points(root)
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var L := a.distance_to(b)
			var d := (b - a) / maxf(L, 0.01)
			var side := Vector2(-d.y, d.x)
			var t := 3.0
			while t < L - 2.0:
				var c: Vector2 = a + d * t
				for s in [-1.0, 1.0]:
					var q: Vector2 = c + side * s * (p.width / 2.0 - 0.25)
					_beam_box(holder, Vector3(q.x, p.height / 2.0, q.y), Vector3(0.25, p.height, 0.25), wood)
				var yaw := -atan2(side.y, side.x)
				var top := _beam_box(holder, Vector3(c.x, p.height - 0.3, c.y), Vector3(p.width, 0.28, 0.3), wood)
				top.rotation.y = yaw
				t += rng.randf_range(5.0, 7.0)


static func _beam_box(holder: Node3D, pos: Vector3, size: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	holder.add_child(mi)
	return mi


## Correntes penduradas do teto nas salas, algumas com um gancho na ponta.
func _chains(holder: Node3D, rng: RandomNumberGenerator) -> void:
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.16, 0.15, 0.15)
	iron.metallic = 0.6
	iron.roughness = 0.5
	var link := TorusMesh.new()
	link.inner_radius = 0.045
	link.outer_radius = 0.085
	link.rings = 6
	link.ring_segments = 4
	var keys := _cells.keys()
	var placed := 0
	var tries := 0
	while placed < int(keys.size() / 70.0) and tries < 400:
		tries += 1
		var k: Vector2i = keys[rng.randi() % keys.size()]
		var h: float = _cells[k]
		if h < 5.5 or _near_wall(k) or _hall_cells.has(k):
			continue   # só em salas, longe das paredes
		placed += 1
		var c := _center(k)
		var L := rng.randf_range(1.5, minf(3.6, h - 2.4))
		var n := int(L / 0.13)
		for i in n:
			var mi := MeshInstance3D.new()
			mi.mesh = link
			mi.material_override = iron
			mi.position = Vector3(c.x, h - 0.07 - i * 0.13, c.y)
			mi.rotation = Vector3(PI / 2.0, (PI / 2.0) * (i % 2), 0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(mi)
		if rng.randf() < 0.5:
			var hook := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.035
			cm.bottom_radius = 0.0
			cm.height = 0.35
			cm.radial_segments = 4
			hook.mesh = cm
			hook.material_override = iron
			hook.position = Vector3(c.x, h - n * 0.13 - 0.15, c.y)
			holder.add_child(hook)


## Cavernas: estalactites pontudas descendo do teto (na cor da rocha).
func _stalactites(holder: Node3D, rng: RandomNumberGenerator, th: Dictionary) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = (th.wall[0] as Color) * 0.8
	m.roughness = 1.0
	var keys := _cells.keys()
	for i in int(keys.size() / 9.0):
		var k: Vector2i = keys[rng.randi() % keys.size()]
		var h: float = _cells[k]
		var L := rng.randf_range(0.4, minf(1.6, h - 3.0))
		if L < 0.3 or _hall_cells.has(k):
			continue
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = rng.randf_range(0.12, 0.28)
		cm.bottom_radius = 0.0
		cm.height = L
		cm.radial_segments = 5
		cm.rings = 1
		mi.mesh = cm
		mi.material_override = m
		var c := _center(k) + Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4))
		mi.position = Vector3(c.x, h - L / 2.0 + 0.05, c.y)
		holder.add_child(mi)


## Covil: raízes penduradas do teto.
func _roots(holder: Node3D, rng: RandomNumberGenerator) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.22, 0.14)
	var keys := _cells.keys()
	for i in int(keys.size() / 14.0):
		var k: Vector2i = keys[rng.randi() % keys.size()]
		var h: float = _cells[k]
		var L := rng.randf_range(0.8, minf(2.2, h - 2.6))
		if L <= 0.3 or _hall_cells.has(k):
			continue
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = rng.randf_range(0.05, 0.1)
		cm.bottom_radius = 0.01
		cm.height = L
		cm.radial_segments = 5
		cm.rings = 1
		mi.mesh = cm
		mi.material_override = m
		var c := _center(k) + Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4))
		mi.position = Vector3(c.x, h - L / 2.0, c.y)
		mi.rotation = Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))
		holder.add_child(mi)


# ---------------------------------------------------------------- portão e sala do chefe
## Onde o corredor entra na sala do chefe: {pos, dir (para dentro da sala), width}. Vazio sem sala do chefe.
func boss_entrance() -> Dictionary:
	var boundary: Array = []
	var center := Vector2.ZERO
	for k: Vector2i in _boss_cells:
		center += _center(k)
	if _boss_cells.is_empty():
		return {}
	center /= _boss_cells.size()
	for k: Vector2i in _cells:
		if _boss_cells.has(k):
			continue
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if _boss_cells.has(k + d):
				boundary.append([k, d])
				break
	if boundary.is_empty():
		return {}
	var dir := Vector2.ZERO
	var pos := Vector2.ZERO
	for bd in boundary:
		pos += _center(bd[0]) + Vector2(bd[1].x, bd[1].y) * CELL * 0.5
		dir += Vector2(bd[1].x, bd[1].y)
	pos /= boundary.size()
	dir = dir.normalized()
	# largura da abertura: de ponta a ponta na linha do portão
	var side := Vector2(-dir.y, dir.x)
	var lo := INF
	var hi := -INF
	var h := 0.0
	for bd in boundary:
		var s := (_center(bd[0]) - pos).dot(side)
		lo = minf(lo, s - CELL / 2.0)
		hi = maxf(hi, s + CELL / 2.0)
		h = maxf(h, float(_cells[bd[0]]))
	var mid := (lo + hi) / 2.0
	pos += side * mid
	var open_w := hi - lo
	return {"pos": pos, "dir": dir, "opening": open_w, "width": minf(GATE_W, open_w), "center": center,
		"height": h}


## Largura máxima do portão do chefe (o resto da abertura vira parede).
const GATE_W := 8.0


## Paredes que fecham a abertura da sala do chefe dos lados do portão: [centro, tamanho, giro] (colisão e malha).
func _gate_fill(g: Dictionary) -> Array:
	var out: Array = []
	var pos: Vector2 = g.pos
	var dir: Vector2 = g.dir
	var side := Vector2(-dir.y, dir.x)
	var inner: float = float(g.width) / 2.0 + 1.7   # os contrafortes do portão vão até aqui
	var outer: float = float(g.opening) / 2.0 + 0.6
	if outer - inner < 0.2:
		return out
	var h: float = float(g.height) + 0.5
	for s in [-1.0, 1.0]:
		var c: Vector2 = pos + side * s * (inner + outer) / 2.0
		out.append([Vector3(c.x, h / 2.0, c.y), Vector3(outer - inner, h, 1.6), -atan2(side.y, side.x)])
	return out


## Portão gótico do chefe: arco ogival de cantaria (aduelas, fecho com o selo da dungeon), folhas escuras com
## filigrana dourada (moldura, lanceta em Y, argolas) e a luz da sala vazando pela fresta do meio.
## Medidas no espaço do portão: x para o lado, y para cima; -Z aponta para dentro da sala.
const GATE_SPRING := 5.2   # altura onde o arco começa
const GATE_ARCH := 0.66    # raio dos arcos / largura do vão (mais = mais pontudo)


## Meia largura do vão na altura `y` (reto até GATE_SPRING, depois a curva do arco; 0 acima do topo).
static func _arch_half(hw: float, y: float) -> float:
	if y <= GATE_SPRING:
		return hw
	var R := GATE_ARCH * hw * 2.0
	var dy := y - GATE_SPRING
	if dy >= R:
		return 0.0
	return maxf(0.0, hw - R + sqrt(R * R - dy * dy))


static func _arch_top(hw: float) -> float:
	var R := GATE_ARCH * hw * 2.0
	return GATE_SPRING + sqrt(R * R - (R - hw) * (R - hw))


## Pontos da curva de um lado (`s` = ±1) de um arco ogival de meia largura `hw` que começa em `spring`, com o
## trecho reto desde `y0`; `grow` afasta a curva para fora (aduelas) ou para dentro (negativo).
static func _arch_pts(hw: float, s: float, y0: float, spring: float, n: int, grow := 0.0) -> PackedVector2Array:
	var R := GATE_ARCH * hw * 2.0
	var cx := hw - R
	var th1 := acos(clampf((R - hw) / R, -1.0, 1.0))
	var out := PackedVector2Array()
	if spring > y0:
		out.append(Vector2(s * (hw + grow), y0))
	for i in n + 1:
		var a := th1 * float(i) / n
		out.append(Vector2(s * (cx + (R + grow) * cos(a)), spring + (R + grow) * sin(a)))
	return out


## Barra fina entre dois pontos (x, y) do plano, na profundidade z (filigrana e aduelas); `offset` = onde fica a
## origem do `parent` nesse plano (a dobradiça da folha).
static func _bar(parent: Node3D, a: Vector2, b: Vector2, thick: float, depth: float, z: float, m: Material,
		offset := Vector2.ZERO) -> MeshInstance3D:
	var d := b - a
	var mi := _beam_box(parent, Vector3((a.x + b.x) / 2.0 - offset.x, (a.y + b.y) / 2.0 - offset.y, z),
		Vector3(d.length() + thick * 0.6, thick, depth), m)
	mi.rotation.z = atan2(d.y, d.x)
	return mi


## Fachos de luz caindo de cima do portão sobre o salão da frente (quads somados, mais fortes em cima).
static func _light_shafts(gate: Node3D, w: float, top: float, c: Color) -> void:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color;
void fragment() {
	float edge = smoothstep(0.0, 0.35, UV.x) * smoothstep(1.0, 0.65, UV.x);
	ALBEDO = col.rgb;
	ALPHA = edge * (1.0 - UV.y) * col.a;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("col", Color(c, 0.1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	for i in 3:
		var x := (float(i) - 1.0) * w * 0.32
		var L := top + 2.5
		for turn in [0.0, PI / 2.0]:   # dois quads cruzados: o facho tem volume de qualquer lado
			var q := QuadMesh.new()
			q.size = Vector2(rng.randf_range(0.9, 1.5), L)
			var mi := MeshInstance3D.new()
			mi.mesh = q
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var b := Basis(Vector3.UP, turn)
			b = Basis(Vector3.RIGHT, -0.55) * b   # inclinado: desce de cima do portão para a frente
			mi.basis = b
			mi.position = Vector3(x, top + 1.0, 0.9) - b.y * L / 2.0   # ponta de cima logo acima do arco
			gate.add_child(mi)


func _boss_gate(holder: Node3D, fx: Node, th: Dictionary) -> void:
	var g := boss_entrance()
	if g.is_empty():
		return
	var pos: Vector2 = g.pos
	var dir: Vector2 = g.dir
	var w: float = g.width
	var hw := w / 2.0
	var side := Vector2(-dir.y, dir.x)
	var top := _arch_top(hw)
	var ceil_h: float = float(g.height) + 0.5
	var stone := StandardMaterial3D.new()
	stone.albedo_color = (th.wall[1] as Color).lerp(Color(0.5, 0.48, 0.45), 0.4)
	var stone_dk := StandardMaterial3D.new()
	stone_dk.albedo_color = (stone.albedo_color as Color) * 0.72
	var rc: Color = th.rune
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.09, 0.09, 0.13).lerp(rc, 0.1)
	dark.roughness = 0.8
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.86, 0.64, 0.3)
	gold.metallic = 0.75
	gold.roughness = 0.35
	gold.emission_enabled = true
	gold.emission = Color(0.9, 0.62, 0.28)
	gold.emission_energy_multiplier = 0.35
	var rune := StandardMaterial3D.new()
	rune.albedo_color = rc
	rune.emission_enabled = true
	rune.emission = rc
	rune.emission_energy_multiplier = 3.0
	rune.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var glow_c := Color(1.0, 0.8, 0.5).lerp(rc, 0.15)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = glow_c
	glow.emission_enabled = true
	glow.emission = glow_c
	glow.emission_energy_multiplier = 5.0
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var gate := Node3D.new()
	gate.name = "BossGate"
	gate.position = Vector3(pos.x, 0, pos.y)
	gate.basis = Basis.looking_at(Vector3(dir.x, 0, dir.y), Vector3.UP)   # -Z do portão aponta para dentro da sala
	holder.add_child(gate)
	var stone_mid := StandardMaterial3D.new()
	stone_mid.albedo_color = (stone.albedo_color as Color) * 0.86
	for f in _gate_fill(g):   # parede de cantaria dos lados do portão, até o teto, em fiadas de 0,6 m
		var fc: Vector3 = f[0]
		var fs: Vector3 = f[1]
		var nc := ceili(fs.y / 0.6)
		for i in nc:
			var fy0 := fs.y * i / nc
			var fy1 := fs.y * (i + 1) / nc
			var wall := _beam_box(holder, Vector3(fc.x, (fy0 + fy1) / 2.0, fc.z), Vector3(fs.x, fy1 - fy0 + 0.01, fs.z),
				stone_dk if i == 0 else (stone if i % 2 == 0 else stone_mid))
			wall.rotation.y = f[2]
	# contrafortes: base em degrau, fuste com faixa de runas, capitel
	var pw := 1.7
	for s in [-1.0, 1.0]:
		var px: float = s * (hw + pw / 2.0)
		var pil := _beam_box(gate, Vector3(px, ceil_h / 2.0, 0), Vector3(pw, ceil_h, 1.8), stone)
		pil.name = "Pillar"
		_beam_box(gate, Vector3(px, 0.5, 0.1), Vector3(pw + 0.6, 1.0, 2.3), stone_dk)
		_beam_box(gate, Vector3(px, 1.15, 0.05), Vector3(pw + 0.3, 0.3, 2.05), stone)
		_beam_box(gate, Vector3(px, GATE_SPRING - 0.2, 0.05), Vector3(pw + 0.4, 0.45, 2.1), stone_dk)
		_beam_box(gate, Vector3(px, 3.0, 0.91), Vector3(0.16, 2.6, 0.04), rune)
		_beam_box(gate, Vector3(px, 1.75, 0.91), Vector3(0.5, 0.12, 0.04), rune)
		_beam_box(gate, Vector3(px, 4.25, 0.91), Vector3(0.5, 0.12, 0.04), rune)
	# tímpano: parede por cima do arco até o teto, em fatias que acompanham a curva
	var y := GATE_SPRING
	while y < ceil_h:
		var y1 := minf(y + 0.25, ceil_h)
		var half := maxf(_arch_half(hw, y), _arch_half(hw, y1))
		var wid := hw - half
		if wid > 0.01:
			var course := stone if int((y - GATE_SPRING) / 0.5) % 2 == 0 else stone_mid
			for s in [-1.0, 1.0]:
				_beam_box(gate, Vector3(s * (half + wid / 2.0), (y + y1) / 2.0, 0), Vector3(wid + 0.02, y1 - y + 0.01, 1.4), course)
		y = y1
	# aduelas do arco (saltadas para a frente) e a moldura dourada por dentro
	for s in [-1.0, 1.0]:
		var outer := _arch_pts(hw, s, GATE_SPRING, GATE_SPRING, 9, 0.55)
		for i in outer.size() - 1:
			_bar(gate, outer[i], outer[i + 1], 1.0, 2.0, 0.0, stone if i % 2 == 0 else stone_dk)
		var inner := _arch_pts(hw, s, 0.0, GATE_SPRING, 12, 0.06)
		for i in inner.size() - 1:
			_bar(gate, inner[i], inner[i + 1], 0.14, 0.12, 0.72, gold)
	# fecho no topo com o selo da dungeon (anel e losango de runa)
	_beam_box(gate, Vector3(0, top + 0.7, 0.15), Vector3(1.3, 1.5, 2.2), stone_dk)
	var seal := MeshInstance3D.new()
	var stm := TorusMesh.new()
	stm.inner_radius = 0.42
	stm.outer_radius = 0.55
	stm.rings = 24
	stm.ring_segments = 6
	seal.mesh = stm
	seal.material_override = rune
	seal.rotation.x = PI / 2.0
	seal.position = Vector3(0, top + 0.7, 1.27)
	gate.add_child(seal)
	var dia := _beam_box(gate, Vector3(0, top + 0.7, 1.27), Vector3(0.36, 0.36, 0.05), rune)
	dia.rotation.z = PI / 4.0
	# degraus na frente
	_beam_box(gate, Vector3(0, 0.12, 1.6), Vector3(w + 2.0 * pw + 1.0, 0.24, 1.4), stone_dk)
	_beam_box(gate, Vector3(0, 0.06, 2.8), Vector3(w + 2.0 * pw + 2.2, 0.12, 1.2), stone_dk)
	# folhas da porta: giram para dentro da sala (DungeonFX abre)
	var leaves: Array = []
	for s in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.position = Vector3(s * hw, 0, -0.1)
		gate.add_child(hinge)
		var off := Vector2(s * hw, 0.0)   # do portão para a dobradiça
		# corpo da folha; o alto em fatias que acompanham o arco
		var leaf := _beam_box(hinge, Vector3(-s * hw / 2.0, GATE_SPRING / 2.0, 0), Vector3(hw - 0.03, GATE_SPRING, 0.35), dark)
		leaf.name = "Leaf"
		y = GATE_SPRING
		while y < top:
			var y1 := minf(y + 0.2, top)
			var half := _arch_half(hw, (y + y1) / 2.0)
			if half > 0.05:
				_beam_box(hinge, Vector3(s * half / 2.0 - s * hw, (y + y1) / 2.0, 0), Vector3(half - 0.03, y1 - y + 0.01, 0.35), dark)
			y = y1
		var z := 0.2
		# filigrana: montantes, travessas e a borda do arco
		_bar(hinge, Vector2(s * (hw - 0.18), 0.1), Vector2(s * (hw - 0.18), GATE_SPRING), 0.16, 0.06, z, gold, off)
		_bar(hinge, Vector2(s * 0.1, 0.1), Vector2(s * 0.1, top - 0.3), 0.14, 0.06, z, gold, off)
		_bar(hinge, Vector2(s * 0.1, 0.25), Vector2(s * (hw - 0.18), 0.25), 0.16, 0.06, z, gold, off)
		_bar(hinge, Vector2(s * 0.1, 1.45), Vector2(s * (hw - 0.18), 1.45), 0.12, 0.06, z, gold, off)
		var edge := _arch_pts(hw, s, GATE_SPRING, GATE_SPRING, 10, -0.2)
		for i in edge.size() - 1:
			_bar(hinge, edge[i], edge[i + 1], 0.12, 0.06, z, gold, off)
		# lanceta em Y no meio da folha
		var lc: float = s * hw / 2.0
		var lw := hw / 2.0 - 0.45
		var lspring := GATE_SPRING - 1.2
		for ls in [-1.0, 1.0]:
			var pts := _arch_pts(lw, ls, 1.45, lspring, 8)
			for i in pts.size() - 1:
				_bar(hinge, pts[i] + Vector2(lc, 0), pts[i + 1] + Vector2(lc, 0), 0.1, 0.05, z, gold, off)
		var lR := GATE_ARCH * lw * 2.0
		var ltop := lspring + sqrt(lR * lR - (lR - lw) * (lR - lw))
		var fork := Vector2(lc, lspring + 0.2)
		_bar(hinge, Vector2(lc, 1.45), fork, 0.1, 0.05, z, gold, off)
		_bar(hinge, fork, Vector2(lc - lw * 0.7, ltop - 0.5), 0.08, 0.05, z, gold, off)
		_bar(hinge, fork, Vector2(lc + lw * 0.7, ltop - 0.5), 0.08, 0.05, z, gold, off)
		# rodapé com losangos e a argola
		for k in 3:
			var cx: float = s * (0.45 + k * (hw - 0.7) / 2.0)
			var lz := _beam_box(hinge, Vector3(cx - s * hw, 0.85, z), Vector3(0.32, 0.32, 0.05), gold)
			lz.rotation.z = PI / 4.0
		var ring := MeshInstance3D.new()
		var rt := TorusMesh.new()
		rt.inner_radius = 0.2
		rt.outer_radius = 0.27
		rt.rings = 16
		rt.ring_segments = 6
		ring.mesh = rt
		ring.material_override = gold
		ring.rotation.x = PI / 2.0
		ring.position = Vector3(s * 0.55 - s * hw, 2.35, 0.24)
		hinge.add_child(ring)
		_beam_box(hinge, Vector3(s * 0.55 - s * hw, 2.62, 0.22), Vector3(0.22, 0.22, 0.06), gold)
		if s > 0.0:   # luz da sala vazando pela fresta do meio (vai junto com a folha)
			_beam_box(hinge, Vector3(-hw, top / 2.0, 0.05), Vector3(0.07, top - 0.4, 0.3), glow)
		leaves.append([hinge, s])
	_light_shafts(gate, w, top, glow_c)
	# fachada: pilastras com tochas, rodapé e cornija de ponta a ponta; tocheiros no caminho até a porta
	var face_hw: float = float(g.opening) / 2.0 + 0.6
	for s in [-1.0, 1.0]:
		var plx: float = s * minf(hw + pw + 4.4, face_hw - 1.0)
		_beam_box(gate, Vector3(plx, ceil_h / 2.0, 0.95), Vector3(1.0, ceil_h, 0.5), stone_mid)
		_beam_box(gate, Vector3(plx, 0.45, 1.05), Vector3(1.3, 0.9, 0.75), stone_dk)
		var sc := Node3D.new()
		sc.position = Vector3(plx, 3.6, 1.75)
		gate.add_child(sc)
		_torch_mesh(sc, th.torch)
		_torch_light(sc, th.torch, fx)
		var high := Node3D.new()   # tocha alta no contraforte
		high.position = Vector3(s * (hw + pw / 2.0), 7.2, 1.45)
		gate.add_child(high)
		_torch_mesh(high, th.torch)
		var rest: float = face_hw - (hw + pw)
		_beam_box(gate, Vector3(s * (hw + pw + rest / 2.0), 0.3, 0.95), Vector3(rest, 0.6, 0.45), stone_dk)
		for st in [[5.6, 9.0], [4.4, 11.3]]:
			_torch_stand(gate, Vector3(s * float(st[0]), 0, float(st[1])), th, fx)
	_beam_box(gate, Vector3(0, ceil_h - 0.9, 1.0), Vector3(face_hw * 2.0, 0.5, 0.6), stone_dk)
	_beam_box(gate, Vector3(0, ceil_h - 1.3, 0.9), Vector3(face_hw * 2.0, 0.3, 0.4), stone)
	var al := OmniLight3D.new()
	al.light_color = glow_c
	al.light_energy = 2.0
	al.omni_range = 12.0
	al.position = Vector3(0, top + 0.5, 4.0)
	gate.add_child(al)
	# estátuas do tema: os guardiões do portão olhando o corredor e um par no meio do salão olhando o caminho
	var names: Array = STATUES.get(theme, ["knight", "knight_d"])
	var tint := Color((th.wall[1] as Color).lerp(Color(0.42, 0.4, 0.38), 0.5), 1.0)
	for s in [-1.0, 1.0]:
		for spot in [[names[0], hw + pw + 2.0, 2.4, -s * 0.35, 4.2], [names[1], minf(9.0, face_hw - 2.0), 6.8, -s * PI / 2.0, 3.4]]:
			var sx: float = s * float(spot[1])
			var sz: float = spot[2]
			_beam_box(gate, Vector3(sx, 0.45, sz), Vector3(1.9, 0.9, 1.9), stone)
			_beam_box(gate, Vector3(sx, 0.8, sz), Vector3(1.6, 0.12, 1.6), stone_dk)
			_beam_box(gate, Vector3(sx, 0.1, sz), Vector3(2.2, 0.2, 2.2), stone_dk)
			var stt := _statue(str(spot[0]), tint, float(spot[4]))
			if stt != null:
				stt.position += Vector3(sx, 0.9, sz)
				stt.rotation.y = float(spot[3])
				gate.add_child(stt)
	# braseiros: dois na frente do portão (sempre acesos) e um anel na sala do chefe (acendem quando abre)
	var front: Array = []
	for s in [-1.0, 1.0]:
		front.append(_brazier(holder, Vector3(pos.x, 0, pos.y) + Vector3(side.x, 0, side.y) * s * (w / 2.0 + 1.0)
			- Vector3(dir.x, 0, dir.y) * 5.0, th, true))
	var ring: Array = []
	var center: Vector2 = g.center
	var rad := 0.0
	var ext := Vector2.ZERO   # meia largura e meia profundidade da sala: o anel é uma elipse dentro das paredes
	for k: Vector2i in _boss_cells:
		rad = maxf(rad, _center(k).distance_to(center))
		ext = ext.max((_center(k) - center).abs())
	var n := 8
	for i in n:
		var a := TAU * (float(i) + 0.5) / n
		var q := center + Vector2(cos(a) * (ext.x - 2.2), sin(a) * (ext.y - 2.2))
		ring.append(_brazier(holder, Vector3(q.x, 0, q.y), th, false))
	# ossos dos que tentaram antes, espalhados na frente do portão
	var brng := RandomNumberGenerator.new()
	brng.seed = seed * 7 + 1
	for i in 5:
		var bone := _model("bones", Color(1, 1, 1, 0))
		if bone == null:
			break
		var off := side * brng.randf_range(-w / 2.0 - 1.5, w / 2.0 + 1.5) - dir * brng.randf_range(1.5, 6.0)
		bone.transform = Transform3D(Basis(Vector3.UP, brng.randf() * TAU).scaled(Vector3.ONE * brng.randf_range(0.8, 1.2)),
			Vector3(pos.x + off.x, 0, pos.y + off.y))
		holder.add_child(bone)
	var dread := OmniLight3D.new()   # luz da sala do chefe: acende pulsando quando o portão abre
	dread.light_color = th.rune
	dread.light_energy = 0.0
	dread.omni_range = rad + 4.0
	dread.position = Vector3(center.x, 6.0, center.y)
	dread.name = "Dread"
	holder.add_child(dread)
	ring.sort_custom(func(x, y): return (x as Node3D).position.distance_to(gate.position) < (y as Node3D).position.distance_to(gate.position))
	# círculo de runas no meio da sala
	var circle := MeshInstance3D.new()
	var tm := TorusMesh.new()
	var cr := clampf(minf(ext.x, ext.y) * 0.32, 4.0, 7.0)
	tm.inner_radius = cr - 0.4
	tm.outer_radius = cr
	tm.rings = 48
	tm.ring_segments = 4
	circle.mesh = tm
	circle.scale = Vector3(1, 0.05, 1)
	circle.position = Vector3(center.x, 0.03, center.y)
	circle.material_override = rune
	holder.add_child(circle)
	if fx != null:
		fx.setup_gate(gate, leaves, ring, circle, Vector3(pos.x, 0, pos.y))
		fx.set_dread(dread)


## Modelo como estátua de pedra (`tint`) com `height` m de altura e os pés na origem.
static func _statue(model: String, tint: Color, height: float) -> Node3D:
	var inst := _model(model, tint)
	if inst == null:
		inst = _model("knight", tint)
	if inst == null:
		return null
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != inst:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var bb := xf * mi.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	var holder := Node3D.new()
	holder.add_child(inst)
	if not first and box.size.y > 0.01:
		var k := height / box.size.y
		inst.scale = Vector3.ONE * k
		inst.position = Vector3(-(box.position.x + box.size.x / 2.0) * k, -box.position.y * k,
			-(box.position.z + box.size.z / 2.0) * k)
	return holder


## Luz de uma tocha de parede (`t` montada com _torch_mesh), tremendo com o DungeonFX.
static func _torch_light(t: Node3D, c: Color, fx: Node) -> void:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = 2.4
	l.omni_range = 9.5
	l.omni_attenuation = 1.6
	l.position = Vector3(0, 0.35, -0.5)
	t.add_child(l)
	if fx != null:
		fx.add_flicker(l)


## Tocheiro de ferro de chão (haste alta com a chama em cima), aceso.
func _torch_stand(parent: Node3D, pos: Vector3, th: Dictionary, fx: Node) -> void:
	var b := Node3D.new()
	b.position = pos
	parent.add_child(b)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.13, 0.12, 0.12)
	iron.metallic = 0.5
	iron.roughness = 0.6
	for part in [[0.32, 0.36, 0.14, 0.07], [0.06, 0.08, 2.6, 1.4], [0.3, 0.1, 0.3, 2.8], [0.12, 0.12, 0.08, 2.0]]:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = part[0]
		cm.bottom_radius = part[1]
		cm.height = part[2]
		cm.radial_segments = 8
		mi.mesh = cm
		mi.material_override = iron
		mi.position.y = part[3]
		b.add_child(mi)
	var tc: Color = th.torch
	var flame := MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 0.22
	fm.height = 0.6
	fm.radial_segments = 6
	fm.rings = 3
	flame.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = tc
	fmat.emission_enabled = true
	fmat.emission = tc
	fmat.emission_energy_multiplier = 4.0
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame.material_override = fmat
	flame.position.y = 3.15
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.add_child(flame)
	var l := OmniLight3D.new()
	l.light_color = tc
	l.light_energy = 2.0
	l.omni_range = 9.0
	l.position.y = 3.4
	b.add_child(l)
	if fx != null:
		fx.add_flicker(l)


func _brazier(holder: Node3D, pos: Vector3, th: Dictionary, lit: bool) -> Node3D:
	var b := Node3D.new()
	b.position = pos
	holder.add_child(b)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.14, 0.13, 0.13)
	var leg := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.12
	cm.bottom_radius = 0.28
	cm.height = 1.1
	cm.radial_segments = 6
	leg.mesh = cm
	leg.material_override = iron
	leg.position.y = 0.55
	b.add_child(leg)
	var bowl := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.55
	bm.bottom_radius = 0.3
	bm.height = 0.35
	bm.radial_segments = 8
	bowl.mesh = bm
	bowl.material_override = iron
	bowl.position.y = 1.25
	b.add_child(bowl)
	var tc: Color = th.torch if lit else th.rune   # a sala do chefe queima na cor das runas
	var flame := MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 0.38
	fm.height = 0.9
	fm.radial_segments = 6
	fm.rings = 3
	flame.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = tc
	fmat.emission_enabled = true
	fmat.emission = tc
	fmat.emission_energy_multiplier = 4.0
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame.material_override = fmat
	flame.position.y = 1.7
	flame.name = "Flame"
	flame.visible = lit
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.add_child(flame)
	var l := OmniLight3D.new()
	l.name = "Light"
	l.light_color = tc
	l.light_energy = 2.4 if lit else 0.0
	l.omni_range = 11.0
	l.position.y = 2.0
	b.add_child(l)
	b.set_meta("energy", 2.4)
	return b
