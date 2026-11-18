class_name EnchantBlade
extends Node3D
## Efeito em volta da lâmina de uma arma encantada, no estilo "desenhado" das habilidades (FXToon): formas
## de borda dura em três tons chapados (núcleo claro, cor, sombra), que tremem em passos como desenho
## quadro a quadro, sem brilho macio nem partícula redonda. Cada elemento tem a sua cara:
##   fogo     labaredas que lambem a lâmina para cima e ficam para trás no golpe, mais fagulhas
##   gelo     cristais lapidados presos na lâmina, brilhos de quatro pontas e flocos caindo
##   raio     feixes em zigue-zague correndo pela lâmina, com ramos e faíscas; no +4 saltam da ponta
##   veneno   gotas que incham na lâmina e pingam, e bolhas que sobem e estouram
##   sagrado  estrelas de quatro pontas piscando e riscos de luz subindo; no +4 uma estrela na ponta
##   sombra   fiapos de fumaça escura ondulando para cima e ciscos puxados para dentro da lâmina
## O nível (+1..+5) aumenta a quantidade e o tamanho; os detalhes secundários entram a partir do +2/+3.
## Fica como filho do suporte da arma (KnightLook "holder"); o eixo vai do cabo até a ponta ("tip").
## As formas são triângulos coloridos por vértice, refeitos a cada quadro de frente para a câmera, numa
## malha só em espaço de mundo (as labaredas e gotas ficam no ar quando a arma se move).

const STEP_FPS := 12.0         ## "quadros desenhados" por segundo (o tremor das formas)
const GRIP := 0.22             ## fração do comprimento, a partir do cabo, que fica sem efeito
const LIFT := 0.004            ## cada tom fica este tanto (m) mais perto da câmera que o de trás

const PALS := {
	"fogo": FXToon.FIRE,
	"gelo": FXToon.ICE,
	"raio": {"core": Color(1.0, 1.0, 1.0), "mid": Color(0.8, 0.72, 1.0), "edge": Color(0.38, 0.2, 0.92)},
	"veneno": {"core": Color(0.88, 1.0, 0.55), "mid": Color(0.42, 0.88, 0.2), "edge": Color(0.08, 0.38, 0.14)},
	"sagrado": {"core": Color(1.0, 1.0, 0.92), "mid": Color(1.0, 0.86, 0.4), "edge": Color(0.9, 0.5, 0.1)},
	"sombra": {"core": Color(0.82, 0.55, 1.0), "mid": Color(0.36, 0.1, 0.6), "edge": Color(0.09, 0.02, 0.16)},
}
## Formas principais por nível (+1..+5): labaredas, cristais, feixes, gotas por segundo, estrelas, fiapos.
const MAIN := {
	"fogo": [3, 5, 7, 9, 12],
	"gelo": [2, 3, 5, 7, 9],
	"raio": [1, 2, 2, 3, 4],
	"veneno": [1.2, 2.0, 3.0, 4.0, 5.5],
	"sagrado": [2, 3, 5, 7, 9],
	"sombra": [2, 3, 5, 6, 8],
}

static var _mat: StandardMaterial3D

var _el := ""
var _lv := 1
var _pal: Dictionary
var _len := 1.0
var _t := 0.0
var _mi: MeshInstance3D
var _mesh: ArrayMesh
var _v := PackedVector3Array()
var _c := PackedColorArray()
var _cam_pos := Vector3.ZERO
var _cx := Vector3.RIGHT
var _cy := Vector3.UP
var _s := 1.0                  # escala do suporte no mundo (a prévia do menu é menor)
var _tips: Array = []          # ponta atrasada de cada labareda/fiapo (mundo)
var _gens: Array = []          # ciclo em que cada labareda/fiapo está
var _parts: Array = []         # soltos no mundo: fagulhas, flocos, gotas, bolhas, riscos, ciscos
var _acc := [0.0, 0.0]         # acumuladores de nascimento (principal, secundário)
var _crystals: Array = []      # [posição local da ponta] dos cristais de gelo


## Monta o efeito. `def` = EnchantFX.ELEMENTS[element]; `tip_pos` = ponta da arma no espaço do suporte.
static func make(element: String, _def: Dictionary, tip_pos: Vector3, level: int) -> EnchantBlade:
	var b := EnchantBlade.new()
	b._build(element, tip_pos, clampi(level, 1, 5))
	return b


func _build(element: String, tip_pos: Vector3, level: int) -> void:
	_el = element if PALS.has(element) else "fogo"
	_lv = level
	_pal = PALS[_el]
	_len = maxf(tip_pos.length(), 0.2)
	# eixo: +Z ao longo da lâmina, origem no cabo
	var d := tip_pos.normalized() if tip_pos.length() > 0.01 else Vector3(0, 0, 1)
	var up := Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
	basis = Basis.looking_at(-d, up)
	_t = randf() * 10.0   # armas lado a lado não tremem em sincronia
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.vertex_color_use_as_albedo = true
		_mat.vertex_color_is_srgb = true
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh = ArrayMesh.new()
	_mi = MeshInstance3D.new()
	_mi.mesh = _mesh
	_mi.material_override = _mat
	_mi.top_level = true
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.set_meta("enchant_skip_overlay", true)
	add_child(_mi)
	if _el == "gelo":
		_grow_crystals()
	if _el in ["fogo", "sombra"]:
		var n := int(MAIN[_el][_lv - 1])
		_tips.resize(n)
		_gens.resize(n)
		_gens.fill(-1)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_t += delta
	_cam_pos = cam.global_position
	_cx = cam.global_basis.x.normalized()
	_cy = cam.global_basis.y.normalized()
	_s = global_basis.z.length()
	_mi.global_transform = Transform3D.IDENTITY
	_v.clear()
	_c.clear()
	var step := int(_t * STEP_FPS)
	match _el:
		"fogo": _fire(delta, step)
		"gelo": _ice(delta, step)
		"raio": _bolts(step)
		"veneno": _venom(delta)
		"sagrado": _holy(delta, step)
		_: _shadow(delta, step)
	_draw_parts(delta, step)
	_mesh.clear_surfaces()
	if _v.size() >= 3:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _v
		arrays[Mesh.ARRAY_COLOR] = _c
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


# ------------------------------------------------------------------ base
static func _h(a: float, b: float) -> float:
	return fposmod(sin(a * 127.1 + b * 311.7) * 43758.5453, 1.0)


## Ponto da lâmina no mundo: `z` metros a partir do cabo, `off` de afastamento do eixo.
func _at(z: float, off := Vector2.ZERO) -> Vector3:
	return global_transform * Vector3(off.x, off.y, z)


## Ponto sorteado ao longo da parte da lâmina que recebe efeito (`k` 0..1).
func _z(k: float) -> float:
	return lerpf(GRIP, 1.0, k) * _len


func _tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	_v.append(a)
	_v.append(b)
	_v.append(c)
	_c.append(col)
	_c.append(col)
	_c.append(col)


## Faixa de frente para a câmera passando por `pts`, com meia largura `ws` em cada ponto (0 = ponta).
func _ribbon(pts: PackedVector3Array, ws: PackedFloat32Array, col: Color, lift := 0.0) -> void:
	var n := pts.size()
	var l := PackedVector3Array()
	var r := PackedVector3Array()
	for k in n:
		var to_cam := (_cam_pos - pts[k]).normalized()
		var side := (pts[mini(k + 1, n - 1)] - pts[maxi(k - 1, 0)]).cross(to_cam).normalized() * ws[k]
		var p := pts[k] + to_cam * lift
		l.append(p - side)
		r.append(p + side)
	for k in n - 1:
		_tri(l[k], r[k], r[k + 1], col)
		_tri(l[k], r[k + 1], l[k + 1], col)


## Traço de três tons: sombra larga atrás, cor e um fio claro no meio.
func _stroke(pts: PackedVector3Array, ws: PackedFloat32Array, pal: Dictionary) -> void:
	var wide := PackedFloat32Array()
	var thin := PackedFloat32Array()
	for w in ws:
		wide.append(w * 2.0)
		thin.append(w * 0.42)
	_ribbon(pts, wide, pal.edge)
	_ribbon(pts, ws, pal.mid, LIFT)
	_ribbon(pts, thin, pal.core, LIFT * 2.0)


## Polígono de frente para a câmera em volta de `at` (pontos no plano da tela, em metros).
func _fan(at: Vector3, pts: PackedVector2Array, col: Color, lift := 0.0) -> void:
	var o := at + (_cam_pos - at).normalized() * lift
	for k in pts.size():
		var a := pts[k]
		var b := pts[(k + 1) % pts.size()]
		_tri(o, o + _cx * a.x + _cy * a.y, o + _cx * b.x + _cy * b.y, col)


func _star_pts(r: float, rot: float, points := 4, waist := 0.2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in points * 2:
		var a := rot + PI * k / points
		out.append(Vector2(cos(a), sin(a)) * (r if k % 2 == 0 else r * waist))
	return out


## Estrela de quatro pontas em três tons (brilho, faísca).
func _star(at: Vector3, r: float, rot: float, pal: Dictionary) -> void:
	_fan(at, _star_pts(r, rot), pal.edge)
	_fan(at, _star_pts(r * 0.72, rot), pal.mid, LIFT)
	_fan(at, _star_pts(r * 0.4, rot), pal.core, LIFT * 2.0)


func _disc_pts(r: float, n := 10) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in n:
		out.append(Vector2(cos(TAU * k / n), sin(TAU * k / n)) * r)
	return out


static func _bez(a: Vector3, b: Vector3, c: Vector3, t: float) -> Vector3:
	return a.lerp(b, t).lerp(b.lerp(c, t), t)


func _spawn(kind: String, p: Vector3, v: Vector3, life: float, size: float, extra := {}) -> void:
	var d := {"k": kind, "p": p, "v": v, "age": 0.0, "life": life, "s": size, "sd": randf()}
	d.merge(extra)
	_parts.append(d)


## Quantos nascem neste quadro para uma taxa por segundo (`slot` = qual acumulador).
func _due(slot: int, rate: float, delta: float) -> int:
	_acc[slot] += rate * minf(delta, 0.1)
	var n := int(_acc[slot])
	_acc[slot] -= n
	return n


# ------------------------------------------------------------------ labaredas e fiapos (fogo, sombra)
## Línguas que nascem na lâmina, sobem e se soltam. A ponta segue com atraso, então no golpe elas ficam
## para trás como chama de tocha. `o`: h (altura), w (meia largura), period (s), sway (m), rise (quanto
## a base se solta, em alturas).
func _tongues(delta: float, step: int, o: Dictionary) -> void:
	var n := _tips.size()
	for i in n:
		var period: float = o.period * (0.75 + 0.5 * _h(i, 7.0))
		var cyc := _t / period + _h(i, 3.0)
		var g := int(cyc)
		var f := cyc - g
		var root := _at(_z((i + _h(i, g)) / n), Vector2(_h(g, i) - 0.5, _h(i, g + 5.0) - 0.5) * 0.03)
		var height: float = o.h * (0.7 + 0.6 * _h(g, i + 1.0)) * _s
		var base: Vector3 = root + Vector3.UP * height * o.rise * maxf(f - 0.45, 0.0) / 0.55
		var target: Vector3 = base + Vector3.UP * height * (1.0 - (1.0 - f) * (1.0 - f))
		if _gens[i] != g:
			_gens[i] = g
			_tips[i] = root
		_tips[i] = (_tips[i] as Vector3).lerp(target, 1.0 - exp(-14.0 * delta))
		var tip: Vector3 = _tips[i]
		var ctrl: Vector3 = base + Vector3.UP * base.distance_to(tip) * 0.55
		var side := Vector3.UP.cross(_cam_pos - base).normalized()
		var thin := 1.0 - pow(f, 2.5)
		# [quanto do comprimento, largura, tom, quanto mais perto da câmera]
		for layer in [[1.0, 1.0, _pal.edge, 0.0], [0.8, 0.62, _pal.mid, LIFT], [0.5, 0.3, _pal.core, LIFT * 2.0]]:
			var pts := PackedVector3Array()
			var ws := PackedFloat32Array()
			for j in 6:
				var u := j / 5.0
				var q: float = u * layer[0]
				var wob: float = sin(q * 5.0 + step * 1.1 + i * 2.3) * o.sway * q * _s
				pts.append(_bez(base, ctrl, tip, q) + side * wob)
				ws.append(o.w * _s * thin * layer[1] * sqrt(clampf(u / 0.18, 0.0, 1.0)) * (1.0 - pow(u, 1.6)))
			_ribbon(pts, ws, layer[2], layer[3])


func _fire(delta: float, step: int) -> void:
	_tongues(delta, step, {"h": 0.1 + 0.024 * _lv, "w": 0.024 + 0.004 * _lv, "period": 0.6, "sway": 0.02, "rise": 0.9})
	if _lv >= 2:
		for i in _due(1, 2.5 * _lv, delta):
			_spawn("ember", _at(_z(randf())), Vector3(randf_range(-0.15, 0.15), randf_range(0.4, 0.8), randf_range(-0.15, 0.15)),
				randf_range(0.45, 0.8), 0.012 + 0.002 * _lv)


func _shadow(delta: float, step: int) -> void:
	_tongues(delta, step, {"h": 0.2 + 0.03 * _lv, "w": 0.02 + 0.003 * _lv, "period": 1.4, "sway": 0.05, "rise": 0.6})
	if _lv >= 3:
		for i in _due(1, 3.0 * (_lv - 2), delta):
			var dir := Vector3(randf_range(-1, 1), randf_range(-0.4, 1), randf_range(-1, 1)).normalized()
			_spawn("mote", Vector3.ZERO, Vector3.ZERO, randf_range(0.45, 0.7), 0.016 + 0.002 * _lv,
				{"z": _z(randf()), "from": dir * randf_range(0.22, 0.34)})


# ------------------------------------------------------------------ raio
## Feixes em zigue-zague colados na lâmina. Cada um dura três quadros desenhados (cheio, fino, restos) e
## some por um ou dois antes do próximo: no +1 a arma estala de vez em quando, no +5 não para.
func _bolts(step: int) -> void:
	var n := int(MAIN.raio[_lv - 1])
	var amp := (0.028 + 0.007 * _lv)
	var width := (0.0045 + 0.0009 * _lv) * _s
	for i in n:
		var cyc := 4 + i % 2
		var si := step + i * 3
		var k := si % cyc
		if k >= 3:
			continue
		var g := float(si / cyc)
		var a := _z(_h(i, g) * 0.55)
		var b := minf(a + (0.3 + 0.4 * _h(g, i + 2.0)) * _len, _len * 1.02)
		var w: float = width * [1.0, 0.75, 0.5][k]
		var pts := PackedVector3Array()
		var ws := PackedFloat32Array()
		var mid_off := Vector2.ZERO
		# zigue-zague: os pontos alternam de lado numa direção sorteada em volta da lâmina
		var ang0 := _h(g, i + 11.0) * TAU
		var zig := Vector2(cos(ang0), sin(ang0))
		for j in 9:
			var off := Vector2.ZERO
			if j > 0 and j < 8:
				off = zig * (1.0 if j % 2 == 0 else -1.0) * amp * (0.35 + 0.65 * _h(g + j, i + k * 0.37))
				off += Vector2(-zig.y, zig.x) * (_h(i + j, g + 9.0 + k * 0.21) - 0.5) * amp
			if j == 4:
				mid_off = off
			pts.append(_at(lerpf(a, b, (j + (_h(j, g + i) - 0.5) * 0.5 * float(j > 0 and j < 8)) / 8.0), off))
			ws.append(w * (0.0 if j == 0 or j == 8 else 1.0))
		_stroke(pts, ws, _pal)
		if _lv >= 2 and k < 2 and _h(g, i + 4.0) > 0.35:      # ramo que sai para o ar
			var out := mid_off.normalized() if mid_off.length() > 0.001 else Vector2.RIGHT
			var reach := 0.07 + 0.03 * _lv * _h(i, g + 6.0)
			var zc := lerpf(a, b, 0.5)
			_stroke(PackedVector3Array([_at(zc, mid_off), _at(zc + 0.04, mid_off + out * reach * 0.5 + Vector2(out.y, -out.x) * 0.03),
				_at(zc + 0.02, mid_off + out * reach)]), PackedFloat32Array([w * 0.8, w * 0.6, 0.0]), _pal)
		if k == 0:                                             # faísca onde o feixe morre
			_star(_at(b), (0.022 + 0.004 * _lv) * _s, _h(g, i) * PI, _pal)
	if _lv >= 4:                                               # salto da ponta para o ar
		var cyc2 := 16 - 3 * (_lv - 4)
		var k2 := step % cyc2
		if k2 < 3:
			var g2 := float(step / cyc2)
			var ang := _h(g2, 1.0) * TAU
			var out2 := Vector2(cos(ang), sin(ang))
			var end := out2 * (0.2 + 0.08 * _h(g2, 2.0))
			var pts2 := PackedVector3Array()
			var ws2 := PackedFloat32Array()
			for j in 6:
				var u := j / 5.0
				var jit := Vector2(_h(g2 + j, 3.0 + k2) - 0.5, _h(g2 + j, 4.0 + k2) - 0.5) * 0.09 * sin(u * PI)
				pts2.append(_at(_len * (0.92 + 0.2 * u), end * u + jit))
				ws2.append(width * 1.3 * [1.0, 0.75, 0.5][k2] * (1.0 - u * 0.7))
			_stroke(pts2, ws2, _pal)
			if k2 < 2:
				_star(pts2[5], 0.05 * _s, ang, _pal)


# ------------------------------------------------------------------ gelo
## Cristais lapidados (a mesma malha da Nova Gélida) crescidos na lâmina, apontando para fora e para a ponta.
func _grow_crystals() -> void:
	var n := int(MAIN.gelo[_lv - 1])
	for i in n:
		var z := _z((i + 0.2 + 0.6 * _h(i, 1.0)) / n * 0.92)
		var a := _h(i, 2.0) * TAU
		var radial := Vector3(cos(a), sin(a), 0.0)
		var up := (radial * 0.8 + Vector3(0, 0, 0.6)).normalized()
		var height := (0.06 + 0.012 * _lv) * (0.7 + 0.6 * _h(i, 3.0))
		var m := MeshInstance3D.new()
		m.mesh = FXToon.crystal_mesh()
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.set_meta("enchant_skip_overlay", true)
		m.set_instance_shader_parameter("col_core", _pal.core)
		m.set_instance_shader_parameter("col_mid", _pal.mid)
		m.set_instance_shader_parameter("col_edge", _pal.edge)
		var side := up.cross(Vector3(0, 0, 1)).normalized()
		m.basis = Basis(side, up, side.cross(up)).scaled_local(Vector3(height * 0.45, height, height * 0.45))
		m.position = Vector3(0, 0, z) + radial * 0.008
		add_child(m)
		_crystals.append(m.position + up * height)


func _ice(delta: float, step: int) -> void:
	# brilhos nas pontas dos cristais: abrem e fecham em quatro quadros desenhados
	for i in ceili(_crystals.size() * 0.5):
		var si := step + i * 5
		var k := si % 10
		if k >= 4:
			continue
		var g := float(si / 10)
		var tip: Vector3 = _crystals[int(_h(i, g) * _crystals.size()) % _crystals.size()]
		_star(global_transform * tip, (0.03 + 0.005 * _lv) * [0.5, 1.0, 0.75, 0.35][k] * _s, 0.0, _pal)
	if _lv >= 2:
		for i in _due(1, 1.6 * _lv, delta):
			_spawn("snow", _at(_z(randf())), Vector3(randf_range(-0.08, 0.08), randf_range(-0.3, -0.12), randf_range(-0.08, 0.08)),
				randf_range(0.7, 1.1), 0.012 + 0.0015 * _lv)


# ------------------------------------------------------------------ veneno
func _venom(delta: float) -> void:
	for i in _due(0, float(MAIN.veneno[_lv - 1]), delta):
		_spawn("drip", Vector3.ZERO, Vector3.ZERO, 0.9, 0.013 + 0.002 * _lv, {"z": _z(randf())})
	if _lv >= 2:
		for i in _due(1, 0.9 * _lv, delta):
			_spawn("bubble", _at(_z(randf())), Vector3(randf_range(-0.05, 0.05), randf_range(0.08, 0.16), randf_range(-0.05, 0.05)),
				randf_range(0.6, 1.0), randf_range(0.011, 0.016 + 0.002 * _lv))


# ------------------------------------------------------------------ sagrado
func _holy(delta: float, step: int) -> void:
	var n := int(MAIN.sagrado[_lv - 1])
	for i in n:
		var cyc := 9 + i % 4
		var si := step + i * 4
		var k := si % cyc
		if k >= 6:
			continue
		var g := float(si / cyc)
		var at := _at(_z((i + _h(i, g)) / n), Vector2(_h(g, i) - 0.5, _h(i, g + 3.0) - 0.5) * 0.1)
		_star(at, (0.04 + 0.007 * _lv) * [0.4, 0.8, 1.0, 1.0, 0.7, 0.35][k] * (0.7 + 0.6 * _h(g, i + 8.0)) * _s, 0.0, _pal)
	if _lv >= 3:
		for i in _due(1, 2.0 * (_lv - 2), delta):
			_spawn("ray", _at(_z(randf())), Vector3.UP * randf_range(0.25, 0.45), randf_range(0.4, 0.6), 0.1 + 0.02 * _lv)
	if _lv >= 4:   # estrela na ponta, alternando reta e inclinada
		var big := step % 6 < 3
		_star(_at(_len), (0.07 + 0.03 * (_lv - 4)) * (1.0 if big else 0.72) * _s, 0.0 if big else PI * 0.25, _pal)


# ------------------------------------------------------------------ soltos no mundo
func _draw_parts(delta: float, step: int) -> void:
	var i := 0
	while i < _parts.size():
		var p: Dictionary = _parts[i]
		p.age += delta
		if p.age >= p.life:
			_parts.remove_at(i)
			continue
		i += 1
		var f: float = p.age / p.life
		var size: float = p.s * _s
		match p.k:
			"ember":      # fagulha em losango que sobe e encolhe
				p.p += p.v * delta
				var r := size * (1.0 - f)
				_fan(p.p, PackedVector2Array([Vector2(0, r * 1.7), Vector2(r, 0), Vector2(0, -r * 1.7), Vector2(-r, 0)]),
					(_pal.core as Color).lerp(_pal.mid, clampf(f * 2.0, 0.0, 1.0)))
			"snow":       # floco de quatro pontas caindo em zigue-zague
				p.p += (p.v + _cx * sin(p.age * 6.0 + p.sd * 9.0) * 0.06) * delta
				_fan(p.p, _star_pts(size * 1.6 * (1.0 - f * f), (step % 2) * PI * 0.25, 4, 0.3), _pal.mid)
				_fan(p.p, _star_pts(size * 0.9 * (1.0 - f * f), (step % 2) * PI * 0.25, 4, 0.3), _pal.core, LIFT)
			"drip":       # incha presa na lâmina, depois pinga
				var hang := 0.3
				if p.age < hang:
					p.p = _at(p.z) + Vector3.DOWN * 0.018 * _s
					p.v = Vector3.ZERO
					size *= 0.35 + 0.65 * p.age / hang
				else:
					p.v += Vector3.DOWN * 5.0 * delta
					p.p += p.v * delta
					size *= 1.0 - smoothstep(0.75, 1.0, f)
				var tail: float = size * (1.0 + minf((p.v as Vector3).length() * 1.6, 3.0))
				for layer in [[1.0, _pal.edge, 0.0], [0.62, _pal.mid, LIFT]]:
					var r: float = size * layer[0]
					_ribbon(PackedVector3Array([p.p + Vector3.DOWN * r, p.p + Vector3.DOWN * r * 0.6, p.p, p.p + Vector3.UP * r,
						p.p + Vector3.UP * (r + tail * layer[0])]), PackedFloat32Array([0.0, r * 0.8, r, r * 0.7, 0.0]), layer[1], layer[2])
				_fan(p.p - _cx * size * 0.25 + _cy * size * 0.1, _disc_pts(size * 0.18, 6), _pal.core, LIFT * 2.0)
			"bubble":     # sobe devagar e estoura num risco de quatro pontas
				p.p += p.v * delta
				if f > 0.86:
					_fan(p.p, _star_pts(size * 1.9, PI * 0.25, 4, 0.12), _pal.mid)
				else:
					var r := size * minf(f * 6.0, 1.0)
					_fan(p.p, _disc_pts(r), _pal.edge)
					_fan(p.p, _disc_pts(r * 0.72), _pal.mid, LIFT)
					_fan(p.p - _cx * r * 0.3 + _cy * r * 0.3, _disc_pts(r * 0.2, 6), _pal.core, LIFT * 2.0)
			"ray":        # risco de luz vertical que sobe e afina
				p.p += p.v * delta
				var half := size * 0.5 * sin(PI * minf(f * 1.3, 1.0))
				var w := 0.007 * _s * (1.0 - f)
				var pts := PackedVector3Array([p.p - Vector3.UP * half, p.p, p.p + Vector3.UP * half])
				_ribbon(pts, PackedFloat32Array([0.0, w * 2.0, 0.0]), _pal.mid)
				_ribbon(pts, PackedFloat32Array([0.0, w, 0.0]), _pal.core, LIFT)
			"mote":       # cisco puxado de fora para dentro da lâmina
				var to := _at(p.z)
				p.p = (to + p.from * _s).lerp(to, f * f)
				var r := size * (1.0 - f * 0.6)
				_fan(p.p, PackedVector2Array([Vector2(0, r), Vector2(r, 0), Vector2(0, -r), Vector2(-r, 0)]), _pal.edge)
				_fan(p.p, PackedVector2Array([Vector2(0, r * 0.5), Vector2(r * 0.5, 0), Vector2(0, -r * 0.5), Vector2(-r * 0.5, 0)]),
					_pal.core, LIFT)
