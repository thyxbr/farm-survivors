class_name ThornFX
extends RefCounted
## Efeitos da Espinheira, a Guardiã-Raiz. Tudo o que fica em pé ou voa é malha 3D pintada como desenho (tons em
## faixas duras e traço por casco invertido); só o que é chão é pintura deitada (claro em fundo preto, tingida no
## shader). Nada some por transparência: os espinhos afundam de volta na terra, as peças encolhem e o chão é comido
## em pedaços.
##   root_burst   um trecho das Raízes: o chão racha e espinhos curvos de casca irrompem tombados para fora, com
##                torrões de terra voando; depois afundam
##   claw         a Garra: três rasgos pintados no chão e uma coroa de espinhos na borda do círculo, torrões e folhas
##   sprout_rise  onde um Broto vai nascer: um monte de terra treme e estoura, gavinhas em espiral sobem e folhas voam
##   sap          a gota de seiva que voa em arco de um Broto até ela (a cura)
##   spore_pod    o cogumelo-bolota que brota, incha aos trancos e estoura na hora da Nuvem de Esporos
##   Mold         a tela da Nuvem de Esporos: mofo pintado no chão, esporos 3D subindo e cogumelos na borda
## Em jogo: Enemy._thorn_claw, _roots_tick, _sprouts_warn, _thorn_process, _spores_warn e SporeCloud.

const CLAW_TEX := preload("res://assets/vfx/thorn/garra_rasgos.png")
const MOLD_TEX := preload("res://assets/vfx/thorn/esporos_mofo.png")
const CRACK_TEX := preload("res://assets/vfx/worm/chao_rachado.png")
const FACET := preload("res://shaders/thorn/thorn_facet.gdshader")
const INK := preload("res://shaders/thorn/thorn_ink.gdshader")
const GROUND := preload("res://shaders/thorn/thorn_ground.gdshader")

## Cores como se vê na tela (sRGB); `_v` converte para o shader. Cada paleta: face clara, cor, sombra.
const BARK := [Color(0.5, 0.35, 0.29), Color(0.3, 0.18, 0.15), Color(0.12, 0.05, 0.07)]
const CRIMSON := Color(0.88, 0.16, 0.38)
const VINE := [Color(0.6, 0.82, 0.3), Color(0.27, 0.52, 0.16), Color(0.07, 0.19, 0.08)]
const SAP := [Color(0.92, 1.0, 0.6), Color(0.55, 0.95, 0.25), Color(0.1, 0.38, 0.1)]
const POD := [Color(0.76, 0.44, 0.9), Color(0.45, 0.15, 0.57), Color(0.16, 0.03, 0.24)]
const SPORE := [Color(0.82, 1.0, 0.42), Color(0.48, 0.84, 0.2), Color(0.22, 0.08, 0.3)]
const STALK := [Color(0.96, 0.9, 0.82), Color(0.78, 0.69, 0.62), Color(0.4, 0.28, 0.34)]
const DIRT := [Color(0.62, 0.47, 0.34), Color(0.42, 0.3, 0.21), Color(0.2, 0.13, 0.1)]
const LEAF_G := Color(0.4, 0.62, 0.22)
const LEAF_C := Color(0.66, 0.16, 0.38)

static var _mats := {}
static var _plane: PlaneMesh
static var _horn: ArrayMesh
static var _tendril: ArrayMesh
static var _stem: ArrayMesh


static func _v(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	return Vector3(l.r, l.g, l.b)


static func _shared() -> void:
	if _plane != null:
		return
	WormFX._shared()
	_plane = PlaneMesh.new()
	_plane.size = Vector2.ONE
	_horn = _horn_mesh()
	_tendril = _tendril_mesh()
	_stem = _stem_mesh()
	var ink := ShaderMaterial.new()
	ink.shader = INK
	ink.set_shader_parameter("width", 0.035)
	var bark := ShaderMaterial.new()
	bark.shader = FACET
	bark.next_pass = ink
	_mats["bark"] = bark
	for spec in [["crack", CRACK_TEX], ["claw", CLAW_TEX], ["mold", MOLD_TEX]]:
		var g := ShaderMaterial.new()
		g.shader = GROUND
		g.set_shader_parameter("paint", spec[1])
		_mats[spec[0]] = g
	for spec in [["leaf_g", LEAF_G], ["leaf_c", LEAF_C]]:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = spec[1]
		_mats[spec[0]] = m


# ------------------------------------------------------------ malhas
## Um tubo facetado ao longo de `spine` (pontos no plano XY), com o raio `radii[i]` em cada ponto e `sides`
## faces em volta; raio zero no fim fecha numa ponta. Normais chapadas (um tom por face no shader); a cor do
## vértice guarda a direção lisa para o traço (thorn_ink); UV.x dá a volta e UV.y vai de 0 no pé a 1 na ponta.
static func _tube(spine: Array[Vector3], radii: Array[float], sides: int) -> ArrayMesh:
	var n := spine.size()
	var rings: Array = []
	var dirs: Array = []
	for i in n:
		var tan := (spine[mini(i + 1, n - 1)] - spine[maxi(i - 1, 0)]).normalized()
		var a := Vector3.BACK
		var b := tan.cross(a).normalized()
		var ring: Array[Vector3] = []
		var dr: Array[Vector3] = []
		for j in sides + 1:
			var th := TAU * j / sides
			var d := (a * cos(th) + b * sin(th)).normalized()
			ring.append(spine[i] + d * radii[i])
			dr.append(d if radii[i] > 0.0005 else tan)
		rings.append(ring)
		dirs.append(dr)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length_v: Array[float] = [0.0]
	for i in range(1, n):
		length_v.append(length_v[i - 1] + spine[i].distance_to(spine[i - 1]))
	var total: float = maxf(length_v[n - 1], 0.001)
	for i in n - 1:
		for j in sides:
			var quad := [[i, j], [i + 1, j], [i, j + 1], [i + 1, j + 1]]
			var tris := [[quad[0], quad[1], quad[2]], [quad[2], quad[1], quad[3]]]
			if radii[i + 1] <= 0.0005:
				tris = [[quad[0], quad[1], quad[2]]]
			for tri in tris:
				var p: Array[Vector3] = []
				for c in tri:
					p.append(rings[c[0]][c[1]])
				var nrm := (p[1] - p[0]).cross(p[2] - p[0])
				if nrm.length() < 0.000001:
					continue
				nrm = nrm.normalized()
				var outward: Vector3 = dirs[tri[0][0]][tri[0][1]]
				var order := [0, 2, 1]      # o Godot quer a face da frente no sentido horário
				if nrm.dot(outward) < 0.0:
					nrm = -nrm
					order = [0, 1, 2]
				for k in order:
					var c: Array = tri[k]
					var sm: Vector3 = dirs[c[0]][c[1]]
					st.set_normal(nrm)
					st.set_color(Color(sm.x * 0.5 + 0.5, sm.y * 0.5 + 0.5, sm.z * 0.5 + 0.5))
					st.set_uv(Vector2(float(c[1]) / sides, length_v[c[0]] / total))
					st.add_vertex(rings[c[0]][c[1]])
	return st.commit()


## Espinho de raiz: chifre de altura 1 e pé de raio 0,2, que curva para +X.
static func _horn_mesh() -> ArrayMesh:
	var spine: Array[Vector3] = []
	var radii: Array[float] = []
	for i in 8:
		var t := i / 7.0
		spine.append(Vector3(0.34 * t * t, t, 0.0))
		radii.append(0.2 * pow(1.0 - t, 0.85))
	return _tube(spine, radii, 6)


## Gavinha de Broto: haste reta até 0,7 e a ponta enrolada para +X como um broto de samambaia.
static func _tendril_mesh() -> ArrayMesh:
	var spine: Array[Vector3] = []
	var radii: Array[float] = []
	for i in 4:
		spine.append(Vector3(0.0, 0.7 * i / 4.0, 0.0))
	for i in 16:      # a ponta enrola em espiral, fechando em volta de (0,16; 0,7)
		var k := i / 15.0
		var f := 7.0 * k
		var rr := 0.16 * (1.0 - 0.78 * k)
		spine.append(Vector3(0.16 - rr * cos(f), 0.7 + rr * sin(f), 0.0))
	for i in spine.size():
		radii.append(0.07 * (1.0 - float(i) / spine.size()) + 0.01)
	radii[radii.size() - 1] = 0.0
	return _tube(spine, radii, 5)


## Talo de cogumelo: reto, altura 1, um pouco mais grosso no pé.
static func _stem_mesh() -> ArrayMesh:
	var spine: Array[Vector3] = []
	var radii: Array[float] = []
	for i in 4:
		var t := i / 3.0
		spine.append(Vector3(0.04 * sin(t * 2.0), t, 0.0))
		radii.append(lerpf(0.16, 0.1, t))
	return _tube(spine, radii, 6)


# ------------------------------------------------------------ peças
static func _barked(parent: Node, mesh: Mesh, pal: Array, tip: Color, tip_from: float) -> MeshInstance3D:
	_shared()
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = _mats["bark"]
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.extra_cull_margin = 4.0
	parent.add_child(n)
	n.set_instance_shader_parameter("core", _v(pal[0]))
	n.set_instance_shader_parameter("mid", _v(pal[1]))
	n.set_instance_shader_parameter("shade", _v(pal[2]))
	n.set_instance_shader_parameter("tip", _v(tip))
	n.set_instance_shader_parameter("tip_from", tip_from)
	return n


## Base que põe o +Y da malha em `up` e curva o +X dela para o lado de `bend`.
static func _aim(up: Vector3, bend: Vector3) -> Basis:
	var y := up.normalized()
	var x := bend - y * bend.dot(y)
	x = x.normalized() if x.length() > 0.001 else y.cross(Vector3.BACK).normalized()
	return Basis(x, y, x.cross(y))


## Pintura deitada (`mat`: "crack", "claw" ou "mold") de `size` m de lado, um pouco acima do chão (a grama tapa
## o que fica rente).
static func _decal(parent: Node, mat: String, size: float, pal: Array) -> MeshInstance3D:
	_shared()
	var n := MeshInstance3D.new()
	n.mesh = _plane
	n.material_override = _mats[mat]
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.extra_cull_margin = size
	parent.add_child(n)
	n.position = Vector3.UP * 0.12
	n.scale = Vector3(size, 1.0, size)
	n.set_instance_shader_parameter("core", _v(pal[0]))
	n.set_instance_shader_parameter("mid", _v(pal[1]))
	n.set_instance_shader_parameter("shade", _v(pal[2]))
	n.set_instance_shader_parameter("seed", randf())
	return n


## Um torrão de terra 3D de `size` m.
static func _clod(parent: Node, size: float) -> MeshInstance3D:
	var n := WormFX._solid(parent, WormFX._rock, "rock", DIRT)
	n.scale = Vector3(randf_range(0.8, 1.2), randf_range(0.6, 0.9), randf_range(0.8, 1.2)) * size
	return n


## Uma folha 3D (verde ou, uma em três, tomada pelo carmim).
static func _leaf(parent: Node) -> MeshInstance3D:
	_shared()
	var n := MeshInstance3D.new()
	n.mesh = BossFX.leaf_mesh()
	n.material_override = _mats["leaf_c" if randf() < 0.33 else "leaf_g"]
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.scale = Vector3.ONE * randf_range(1.5, 2.2)
	parent.add_child(n)
	return n


## Tempo em passos de 1/12 s: o que segura e afunda anda como desenho.
static func _steps(t: float) -> float:
	return floorf(t * 12.0) / 12.0


## Espinho que sai do chão ao longo do próprio eixo: `e` s desde que começou a sair. Sobe em 0,1 s passando um
## pouco do tamanho, segura até `hold` e afunda de volta em `sink` s, em passos.
static func _erupt(node: Node3D, foot: Vector3, basis: Basis, h: float, e: float, hold: float, sink: float) -> void:
	node.visible = e > 0.0 and e < hold + sink
	if not node.visible:
		return
	var up := LightningShockwaveFX._out(clampf(e / 0.1, 0.0, 1.0))
	var pop := 1.0 + 0.16 * sin(clampf((e - 0.06) / 0.14, 0.0, 1.0) * PI)
	var down := WormFX._k(_steps(e), hold, hold + sink)
	var depth := (1.0 - up) + down * 0.95
	node.basis = basis * Basis.from_scale(Vector3(1.0, pop, 1.0) * h * (1.0 - 0.25 * down))
	node.position = foot - basis.y * h * depth


# ------------------------------------------------------------ Raízes
## Um trecho das Raízes em `at` (o chão), na linha que corre para `dir`, com `half` m de meia-largura: o chão
## racha, dois ou três espinhos de `height` m irrompem tombados para os lados e para a frente, e torrões voam.
static func root_burst(root: Node, at: Vector3, dir: Vector3, half: float, height: float) -> void:
	if root == null or not root.is_inside_tree():
		return
	_shared()
	var fx := IceFX.Timed.new()
	fx.life = 1.4
	root.add_child(fx)
	fx.global_position = at
	var fwd := Vector3(dir.x, 0.0, dir.z).normalized()
	var side := Vector3.UP.cross(fwd).normalized()
	var crack := _decal(fx, "crack", half * 2.5, [CRIMSON, DIRT[2], Color(0.08, 0.03, 0.04)])
	crack.set_instance_shader_parameter("spin", randf() * TAU)
	var thorns: Array[Dictionary] = []
	var count := 3 if randf() < 0.6 else 2
	var flip := 1.0 if randf() < 0.5 else -1.0
	for k in count:
		var s := flip * (-1.0 if k == 0 else 1.0 if k == 1 else randf_range(-0.2, 0.2))
		var lean := (Vector3.UP * 1.0 + side * s * randf_range(0.3, 0.6) + fwd * randf_range(0.15, 0.4)).normalized()
		var bend := fwd * randf_range(0.4, 1.0) + side * s
		var h := height * (randf_range(1.05, 1.25) if k == 2 else randf_range(0.75, 1.0))
		var foot := side * s * half * randf_range(0.2, 0.5) + fwd * randf_range(-0.35, 0.35) + Vector3.DOWN * 0.12 * h
		var node := _barked(fx, _horn, BARK, CRIMSON, randf_range(0.6, 0.72))
		thorns.append({"node": node, "foot": foot, "basis": _aim(lean, bend), "h": h, "wait": k * 0.025})
	var clods: Array[Dictionary] = []
	for k in 4:
		var a := randf() * TAU
		clods.append(WormFX._bit(_clod(fx, randf_range(0.22, 0.4)), Vector3.UP * 0.2,
			Vector3(cos(a), 0.0, sin(a)) * randf_range(1.2, 2.8) + fwd * randf_range(0.0, 1.5) + Vector3.UP * randf_range(4.0, 6.5)))
	fx.step = func(t: float) -> void:
		crack.set_instance_shader_parameter("grow", lerpf(0.2, 1.05, LightningShockwaveFX._out(WormFX._k(t, 0.0, 0.1))))
		crack.set_instance_shader_parameter("heat", 1.0 - WormFX._k(t, 0.1, 0.7))
		crack.set_instance_shader_parameter("erode", WormFX._k(t, 0.9, 1.35))
		for th in thorns:
			_erupt(th.node, th.foot, th.basis, th.h, t - float(th.wait), 0.62, 0.34)
		WormFX._fly(clods, t, 11.0, 0.8)
	fx.step.call(0.0)


# ------------------------------------------------------------ Garra
## A Garra descendo no círculo de `radius` m em `pos` (o chão), com ela olhando para `fwd`: três rasgos pintados
## no chão que rasgam em diagonal e acendem carmim, uma coroa de espinhos irrompendo na borda tombados para fora,
## torrões e folhas voando e a crista de poeira correndo até a borda.
static func claw(root: Node, pos: Vector3, radius: float, fwd: Vector3) -> void:
	if root == null or not root.is_inside_tree():
		return
	_shared()
	var fx := IceFX.Timed.new()
	fx.life = 1.6
	root.add_child(fx)
	fx.global_position = pos
	var f := Vector3(fwd.x, 0.0, fwd.z)
	f = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
	var rip := _decal(fx, "claw", radius * 2.1, [CRIMSON, BARK[2], Color(0.07, 0.02, 0.04)])
	rip.basis = Basis(Vector3.UP, atan2(f.x, f.z) + randf_range(-0.2, 0.2)) * Basis.from_scale(Vector3(radius * 2.1, 1.0, radius * 2.1))
	rip.set_instance_shader_parameter("sweep", 1.0)
	var thorns: Array[Dictionary] = []
	var count := 8
	var a0 := randf() * TAU
	for k in count:
		var a := a0 + TAU * (k + randf_range(-0.2, 0.2)) / count
		var out := Vector3(cos(a), 0.0, sin(a))
		var h := randf_range(1.3, 1.8)
		var lean := (Vector3.UP + out * randf_range(0.25, 0.5)).normalized()
		var foot := out * radius * randf_range(0.72, 0.92) + Vector3.DOWN * 0.12 * h
		var node := _barked(fx, _horn, BARK, CRIMSON, randf_range(0.55, 0.7))
		# a coroa sobe como onda, a partir da frente dela
		var wait := (1.0 - out.dot(f)) * 0.03
		thorns.append({"node": node, "foot": foot, "basis": _aim(lean, out), "h": h, "wait": wait})
	var bits: Array[Dictionary] = []
	for k in 8:
		var a := TAU * k / 8.0 + randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0.0, sin(a))
		bits.append(WormFX._bit(_clod(fx, randf_range(0.22, 0.42)), out * radius * 0.4 + Vector3.UP * 0.2,
			out * randf_range(2.0, 4.0) + Vector3.UP * randf_range(4.5, 7.0)))
	for k in 6:
		var a := randf() * TAU
		bits.append(WormFX._bit(_leaf(fx), Vector3.UP * 0.5,
			Vector3(cos(a), 0.0, sin(a)) * randf_range(1.5, 3.5) + Vector3.UP * randf_range(3.0, 5.0)))
	var crest := WormFX._crest(fx, "ring_dust", WormFX.DUST[1], radius * 2.0)
	crest.set_instance_shader_parameter("lift", 0.7)
	IceFX._flash(fx, Vector3.UP * 0.5, CRIMSON, radius * 1.1, 0.07, 0.12)
	fx.step = func(t: float) -> void:
		rip.set_instance_shader_parameter("grow", LightningShockwaveFX._out(WormFX._k(t, 0.0, 0.12)) * 1.1)
		rip.set_instance_shader_parameter("heat", 1.0 - WormFX._k(t, 0.12, 0.8))
		rip.set_instance_shader_parameter("erode", WormFX._k(t, 1.05, 1.55))
		for th in thorns:
			_erupt(th.node, th.foot, th.basis, th.h, t - float(th.wait), 0.6, 0.3)
		WormFX._fly(bits, t, 10.0, 0.9)
		crest.visible = t < 0.4
		crest.set_instance_shader_parameter("radius", radius * lerpf(0.3, 1.05, LightningShockwaveFX._out(WormFX._k(t, 0.0, 0.28))))
		crest.set_instance_shader_parameter("width", radius * 0.45)
		crest.set_instance_shader_parameter("erode", lerpf(0.05, 1.0, WormFX._k(t, 0.12, 0.4)))
	fx.step.call(0.0)


# ------------------------------------------------------------ Brotos
## Onde um Broto vai nascer daqui a `delay` s, em `pos` (o chão): um monte de terra sobe e treme, estoura em
## torrões, três gavinhas em espiral sobem girando em volta do broto e folhas voam; as gavinhas afundam depois.
static func sprout_rise(root: Node, pos: Vector3, delay: float) -> void:
	if root == null or not root.is_inside_tree():
		return
	_shared()
	delay = maxf(delay, 0.0)
	var fx := IceFX.Timed.new()
	fx.life = delay + 1.5
	root.add_child(fx)
	fx.global_position = pos
	var mound: Array[Dictionary] = []
	for k in 6:
		var a := TAU * k / 6.0 + randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0.0, sin(a))
		var c := _clod(fx, randf_range(0.35, 0.55))
		mound.append({"node": c, "at": out * randf_range(0.15, 0.45), "phase": randf() * TAU})
	var bits: Array[Dictionary] = []
	for m in mound:
		var out: Vector3 = (m.at as Vector3).normalized()
		bits.append(WormFX._bit(m.node, (m.at as Vector3) + Vector3.UP * 0.2, out * randf_range(2.0, 3.5) + Vector3.UP * randf_range(4.0, 6.0)))
	for k in 7:
		var a := randf() * TAU
		bits.append(WormFX._bit(_leaf(fx), Vector3.UP * 0.6,
			Vector3(cos(a), 0.0, sin(a)) * randf_range(1.0, 2.5) + Vector3.UP * randf_range(3.5, 5.5)))
	var vines: Array[Dictionary] = []
	for k in 3:
		var a := TAU * k / 3.0 + randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0.0, sin(a))
		var node := _barked(fx, _tendril, VINE, CRIMSON, 0.86)
		node.set_instance_shader_parameter("grain", 0.0)
		var h := randf_range(1.3, 1.7)
		vines.append({"node": node, "foot": out * 0.75 + Vector3.DOWN * 0.1, "out": out, "h": h,
			"lean": (Vector3.UP + out * 0.35).normalized(), "wait": k * 0.04})
	var burst := [false]
	fx.step = func(t: float) -> void:
		var bt := t - delay
		var rise := WormFX._k(t, delay - 0.8, delay)
		for m in mound:
			var c: Node3D = m.node
			if bt >= 0.0:
				continue
			c.visible = rise > 0.0
			var shake := Vector3(sin(t * 60.0 + float(m.phase)), 0.0, cos(t * 53.0 + float(m.phase))) * 0.05 * rise
			c.position = (m.at as Vector3) + Vector3.UP * lerpf(-0.5, 0.1, rise) + shake
		if bt >= 0.0:
			WormFX._fly(bits, bt, 11.0, 0.85)
			if not burst[0]:
				burst[0] = true
				IceFX._flash(fx, Vector3.UP * 0.6, VINE[0], 2.4, 0.08, 0.12)
		else:
			for b in bits:
				if not mound.any(func(m: Dictionary) -> bool: return m.node == b.node):
					(b.node as Node3D).visible = false
		for v in vines:
			var e := bt - float(v.wait)
			var spin := Basis(Vector3.UP, (1.0 - LightningShockwaveFX._out(clampf(e / 0.3, 0.0, 1.0))) * 2.5)
			_erupt(v.node, v.foot, spin * _aim(v.lean, v.out), v.h, e, 0.9, 0.35)
	fx.step.call(0.0)


## A cura de um Broto: uma gota de seiva 3D voando em arco de `from` até `to` (o peito dela) em `dur` s, que
## estoura num clarão verde ao chegar.
static func sap(root: Node, from: Vector3, to: Vector3, dur := 0.42) -> void:
	if root == null or not root.is_inside_tree():
		return
	_shared()
	var g := WormFX.Glob.new()
	root.add_child(g)
	var head := WormFX._solid(g, WormFX._drop, "acid", SAP)
	head.scale = Vector3.ONE * 0.16
	head.set_instance_shader_parameter("spec", 1.0)
	head.set_instance_shader_parameter("glow", 0.35)
	g.global_position = from
	var tw := g.create_tween()
	tw.tween_method(func(t: float) -> void: g.global_position = ThrowRules.arc(from, to, t, 1.6), 0.0, 1.0, dur)
	tw.tween_callback(func() -> void:
		if g.is_inside_tree():
			IceFX._flash(root as Node3D, to, SAP[1], 1.4, 0.07, 0.1)
		g.queue_free())


# ------------------------------------------------------------ Esporos
## O cogumelo-bolota da Nuvem de Esporos em `pos` (o chão), que estoura daqui a `delay` s: brota, incha aos
## trancos, treme e estoura em cascas roxas e esporos que sobem.
static func spore_pod(root: Node, pos: Vector3, delay: float) -> void:
	if root == null or not root.is_inside_tree():
		return
	_shared()
	delay = maxf(delay, 0.05)
	var fx := IceFX.Timed.new()
	fx.life = delay + 1.3
	root.add_child(fx)
	fx.global_position = pos
	var pod := Node3D.new()
	fx.add_child(pod)
	var size := 0.75
	var ball := WormFX._solid(pod, WormFX._ball, "acid", POD)
	ball.set_instance_shader_parameter("spec", 1.0)
	for k in 5:      # pintas de esporo na casca
		var d := Vector3(cos(TAU * k / 5.0), randf_range(-0.2, 0.7), sin(TAU * k / 5.0)).normalized()
		var spot := WormFX._solid(ball, WormFX._ball, "acid", SPORE)
		spot.scale = Vector3.ONE * randf_range(0.16, 0.24)
		spot.position = d * 0.93
	var bits: Array[Dictionary] = []
	for k in 7:
		var a := TAU * k / 7.0 + randf_range(-0.3, 0.3)
		var shell := WormFX._solid(fx, WormFX._rock, "rock", POD)
		shell.scale = Vector3.ONE * randf_range(0.3, 0.45)
		bits.append(WormFX._bit(shell, Vector3.UP * size, Vector3(cos(a), 0.0, sin(a)) * randf_range(2.5, 4.5) + Vector3.UP * randf_range(3.0, 5.5)))
	var motes: Array[Dictionary] = []
	for k in 12:
		var a := randf() * TAU
		var m := WormFX._solid(fx, WormFX._rock, "rock", SPORE)
		m.scale = Vector3.ONE * randf_range(0.12, 0.2)
		m.set_instance_shader_parameter("glow", 0.4)
		motes.append(WormFX._bit(m, Vector3.UP * size, Vector3(cos(a), 0.0, sin(a)) * randf_range(1.0, 3.0) + Vector3.UP * randf_range(2.0, 4.0)))
	var burst := [false]
	fx.step = func(t: float) -> void:
		var bt := t - delay
		pod.visible = bt < 0.0
		if pod.visible:
			var up := LightningShockwaveFX._out(WormFX._k(t, 0.0, minf(0.35, delay * 0.4)))
			# incha em três trancos e treme perto do estouro
			var swell := floorf(WormFX._k(t, delay * 0.4, delay) * 3.0) / 3.0
			var hot := WormFX._k(t, delay - 0.2, delay)
			var s := size * (0.7 + 0.35 * swell) * up
			pod.scale = Vector3(1.0, 0.85, 1.0) * maxf(s, 0.001)
			pod.position = Vector3(sin(t * 70.0), 0.0, cos(t * 61.0)) * 0.05 * hot + Vector3.UP * s * 0.55
			ball.set_instance_shader_parameter("glow", 0.6 * hot)
		for b in bits:
			(b.node as Node3D).visible = false
		for b in motes:
			(b.node as Node3D).visible = false
		if bt >= 0.0:
			WormFX._fly(bits, bt, 10.0, 0.75)
			WormFX._fly(motes, bt, 1.5, 1.2)
			if not burst[0]:
				burst[0] = true
				IceFX._flash(fx, Vector3.UP * size, SPORE[1], 3.0, 0.08, 0.14)
	fx.step.call(0.0)


## A tela da Nuvem de Esporos (filha de SporeCloud, que diz `radius` e `age` a cada quadro): o mofo pintado no
## chão girando em passos, cogumelos na borda que pulsam e esporos 3D subindo e encolhendo. Some comido e
## encolhendo no último segundo de `life`.
class Mold:
	extends Node3D

	var radius := 1.6
	var age := 0.0
	var life := 12.0
	var _mat: MeshInstance3D
	var _motes: Array[Dictionary] = []
	var _shrooms: Array[Dictionary] = []

	func _ready() -> void:
		ThornFX._shared()
		_mat = ThornFX._decal(self, "mold", 1.0, [ThornFX.SPORE[0], ThornFX.POD[1], ThornFX.POD[2].darkened(0.3)])
		_mat.set_instance_shader_parameter("fill", 0.5)
		_mat.set_instance_shader_parameter("turn", 0.25)
		_mat.set_instance_shader_parameter("spin", randf() * TAU)
		for k in 24:
			var m := WormFX._solid(self, WormFX._rock, "rock", ThornFX.SPORE)
			m.set_instance_shader_parameter("glow", 0.35)
			_motes.append({"node": m, "phase": randf(), "a": randf() * TAU, "d": sqrt(randf()), "size": randf_range(0.08, 0.15),
				"axis": Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()})
		for k in 5:
			var root := Node3D.new()
			add_child(root)
			var stem := ThornFX._barked(root, ThornFX._stem, ThornFX.STALK, ThornFX.STALK[0], 2.0)
			stem.set_instance_shader_parameter("grain", 0.0)
			stem.scale = Vector3.ONE * 0.45
			var cap := WormFX._solid(root, WormFX._ball, "acid", ThornFX.POD)
			cap.set_instance_shader_parameter("spec", 1.0)
			cap.scale = Vector3(0.32, 0.17, 0.32)
			cap.position = Vector3.UP * 0.45
			var dot := WormFX._solid(cap, WormFX._ball, "acid", ThornFX.SPORE)
			dot.scale = Vector3.ONE * 0.3
			dot.position = Vector3(0.3, 0.8, 0.2)
			_shrooms.append({"node": root, "a": TAU * (k + randf_range(-0.25, 0.25)) / 5.0, "size": randf_range(0.6, 0.95),
				"wait": randf_range(0.0, 0.4), "beat": randf() * 1.5})
		_process(0.0)

	func _process(_delta: float) -> void:
		var end := WormFX._k(age, life - 1.0, life)
		var open := LightningShockwaveFX._out(WormFX._k(age, 0.0, 0.35))
		# o mofo da pintura vai até ~0,9 do meio-lado do plano: o plano tem 2,2 raios de lado
		var side := radius * 2.2
		_mat.scale = Vector3(side, 1.0, side)
		_mat.set_instance_shader_parameter("grow", lerpf(0.2, 1.05, open))
		_mat.set_instance_shader_parameter("erode", end)
		for m in _motes:
			var node: Node3D = m.node
			var k := fmod(age * 0.45 + float(m.phase), 1.0)      # cada esporo sobe ~2 s e renasce
			var d := float(m.d) * radius * 0.85
			var a := float(m.a) + floorf(age * 0.45 + float(m.phase)) * 2.4
			var sway := Vector3(sin(age * 2.0 + float(m.phase) * 9.0), 0.0, cos(age * 1.7 + float(m.phase) * 7.0)) * 0.2
			node.position = Vector3(cos(a) * d, 0.7 + k * 2.2, sin(a) * d) + sway
			var s := float(m.size) * minf(1.0, k * 6.0) * (1.0 - WormFX._k(k, 0.6, 1.0)) * (1.0 - end) * open
			node.basis = Basis(m.axis as Vector3, age * 2.0 + float(m.phase) * 6.0) * Basis.from_scale(Vector3.ONE * maxf(s, 0.001))
		for sh in _shrooms:
			var node: Node3D = sh.node
			var a := float(sh.a)
			var pop := LightningShockwaveFX._out(WormFX._k(age, float(sh.wait), float(sh.wait) + 0.25))
			# pulsa em passos a cada 1,5 s: espirra e volta
			var beat := fmod(ThornFX._steps(age) + float(sh.beat), 1.5)
			var squash := 1.0 + 0.18 * (1.0 - WormFX._k(beat, 0.0, 0.25)) * float(age > 0.6)
			var s := float(sh.size) * pop * (1.0 - end)
			node.visible = s > 0.01
			node.position = Vector3(cos(a), 0.0, sin(a)) * radius * 0.92 + Vector3.DOWN * 0.05
			node.basis = Basis(Vector3.UP, a) * Basis.from_scale(Vector3(squash, 2.0 - squash, squash) * maxf(s, 0.001))
