class_name WormFX
extends RefCounted
## Efeitos da Mãe-Verme das Profundezas. Tudo o que fica em pé ou voa é malha 3D pintada como desenho (tons em
## faixas duras e traço por casco invertido): de lado, pintura chapada num quad denunciava o truque. Só o que é
## chão continua pintura deitada (claro em fundo preto, tingida no shader).
##   geode_ring    um anel da Onda de Cristais: geodos (pedras com pontas de cristal) que brotam do chão, acendem
##                 por dentro e estouram em estilhaços de cristal, com as cascas partidas e a crista de choque
##   falling_rock  o pedregulho do Desmoronamento caindo e o impacto: chão quebrado com as rachaduras acesas
##                 (chao_rachado.png), anel de choque, poeira e lascas
##   glob          a bolha de ácido voando, gota com a cauda para trás e gotinhas atrás: o cuspe e as Poças
##   acid_splash   a coroa do respingo: línguas de ácido que sobem em volta e gotas arremessadas
##   acid_pool     a poça (acido_poca.png girando, com a trama de acido_bolhas.png fervendo): a tela de AcidPool
## Em jogo: BossFX.geode_ring / falling_rock / lob, Enemy._acid_hit, AcidPool e EnemyArrow (cuspe).

const CRATER_TEX := preload("res://assets/vfx/worm/chao_rachado.png")
const POOL_TEX := preload("res://assets/vfx/worm/acido_poca.png")
const WEB_TEX := preload("res://assets/vfx/worm/acido_bolhas.png")
const CREST_TEX := preload("res://assets/vfx/lightning_shockwave/onda_faixa.png")
const GROUND := preload("res://shaders/worm/worm_ground.gdshader")
const POOL := preload("res://shaders/worm/acid_pool.gdshader")
const RING := preload("res://shaders/lightning_shockwave/wave_ring.gdshader")
const FACET := preload("res://shaders/worm/worm_facet.gdshader")
const BLOB := preload("res://shaders/worm/worm_blob.gdshader")
const INK := preload("res://shaders/worm/worm_ink.gdshader")

## Cores como se vê na tela (sRGB); `_v` converte para o shader. Cada paleta: face clara, cor, sombra.
const CYAN := [Color(0.88, 0.99, 1.0), Color(0.22, 0.8, 1.0), Color(0.16, 0.12, 0.62)]
const FURY := [Color(1.0, 0.9, 0.82), Color(1.0, 0.24, 0.14), Color(0.42, 0.02, 0.14)]
const EARTH := [Color(0.84, 0.74, 0.6), Color(0.6, 0.46, 0.33), Color(0.3, 0.2, 0.15)]
const ROCK := [Color(0.82, 0.8, 0.78), Color(0.55, 0.52, 0.5), Color(0.26, 0.23, 0.26)]
const ACID := [Color(0.78, 1.0, 0.3), Color(0.36, 0.9, 0.08), Color(0.03, 0.26, 0.05)]
const GEODE := [Color(0.66, 0.63, 0.66), Color(0.43, 0.4, 0.45), Color(0.2, 0.17, 0.25)]
const DUST := [Color(0.8, 0.72, 0.6), Color(0.62, 0.54, 0.44), Color(0.36, 0.29, 0.24)]
const AMBER := Color(1.0, 0.62, 0.15)
## O pedregulho do Desmoronamento (m) e a altura de onde cai.
const BOULDER := 2.4
const DROP_H := 14.0

static var _mats := {}
static var _plane: PlaneMesh
static var _annulus: ArrayMesh
static var _crystal: ArrayMesh
static var _rock: ArrayMesh
static var _ball: SphereMesh
static var _drop: ArrayMesh


static func _v(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	return Vector3(l.r, l.g, l.b)


static func _shared() -> void:
	if _plane != null:
		return
	_plane = PlaneMesh.new()
	_plane.size = Vector2.ONE
	_annulus = LightningShockwaveFX._annulus()
	_crystal = _crystal_mesh()
	_rock = _rock_mesh()
	_drop = _drop_mesh()
	_ball = SphereMesh.new()
	_ball.radius = 1.0
	_ball.height = 2.0
	_ball.radial_segments = 14
	_ball.rings = 7
	# [nome, shader, como o traço engorda (ver worm_ink), largura do traço (m), tremor da gosma]
	for spec in [["crystal", FACET, 0, 0.035, 0.0], ["rock", FACET, 2, 0.035, 0.0], ["acid", BLOB, 1, 0.03, 0.06],
			["dust", BLOB, 1, 0.03, 0.0]]:
		var ink := ShaderMaterial.new()
		ink.shader = INK
		ink.set_shader_parameter("mode", spec[2])
		ink.set_shader_parameter("width", spec[3])
		ink.set_shader_parameter("wobble", spec[4])
		var m := ShaderMaterial.new()
		m.shader = spec[1]
		if spec[1] == BLOB:
			m.set_shader_parameter("wobble", spec[4])
		m.next_pass = ink
		_mats[spec[0]] = m
	var ground := ShaderMaterial.new()
	ground.shader = GROUND
	ground.set_shader_parameter("cracks", CRATER_TEX)
	_mats["ground"] = ground
	var pool := ShaderMaterial.new()
	pool.shader = POOL
	pool.set_shader_parameter("pool", POOL_TEX)
	pool.set_shader_parameter("web", WEB_TEX)
	_mats["pool"] = pool
	for spec in [["ring_dust", DUST[2].darkened(0.45), 0.35], ["ring_glow", Color(0.05, 0.05, 0.3), 0.7]]:
		var ring := ShaderMaterial.new()
		ring.shader = RING
		ring.set_shader_parameter("crest", CREST_TEX)
		ring.set_shader_parameter("deep", _v(spec[1]))
		ring.set_shader_parameter("highlight", spec[2])
		ring.render_priority = 1
		_mats[spec[0]] = ring


# ------------------------------------------------------------ malhas
## Um cristal: prisma de seis faces de raio 1 e altura 1, com o pé um pouco mais fino e a ponta a partir de 0,68.
## Normais chapadas (uma por face): cada face ganha um tom só no shader.
static func _crystal_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tip := Vector3(0.0, 1.0, 0.0)
	for i in 6:
		var a0 := TAU * i / 6.0
		var a1 := TAU * (i + 1) / 6.0
		var b0 := Vector3(cos(a0) * 0.7, 0.0, sin(a0) * 0.7)
		var b1 := Vector3(cos(a1) * 0.7, 0.0, sin(a1) * 0.7)
		var s0 := Vector3(cos(a0), 0.68, sin(a0))
		var s1 := Vector3(cos(a1), 0.68, sin(a1))
		for tri in [[b0, s0, s1], [b0, s1, b1], [s0, tip, s1]]:
			var nrm := ((tri[1] as Vector3) - (tri[0] as Vector3)).cross((tri[2] as Vector3) - (tri[0] as Vector3)).normalized()
			if nrm.dot(Vector3(cos((a0 + a1) / 2.0), 0.2, sin((a0 + a1) / 2.0))) < 0.0:
				nrm = -nrm
				tri = [tri[0], tri[2], tri[1]]
			for v in [tri[0], tri[2], tri[1]]:   # o Godot quer a face da frente no sentido horário
				st.set_normal(nrm)
				st.add_vertex(v)
	return st.commit()


## Uma pedra: esfera de poucas faces amassada (raio ~0,5), de normais chapadas.
static func _rock_mesh() -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 6
	sm.rings = 3
	var arr := sm.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var rng := RandomNumberGenerator.new()
	var moved := {}
	for i in v.size():
		var key := Vector3i(roundi(v[i].x * 100.0), roundi(v[i].y * 100.0), roundi(v[i].z * 100.0))
		if not moved.has(key):
			rng.seed = hash(key)
			moved[key] = v[i] * rng.randf_range(0.62, 1.18)
		v[i] = moved[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in range(0, idx.size(), 3):
		for k in 3:
			st.add_vertex(v[idx[t + k]])
	st.generate_normals()
	return st.commit()


## Uma gota: sólido de revolução em volta do Y, cabeça redonda de raio 1 em cima (o centro na origem) e cauda que
## afina até -2,6. Normais lisas.
static func _drop_mesh() -> ArrayMesh:
	var prof: Array[Vector2] = []      # (raio, y), da ponta da cabeça à ponta da cauda
	for i in 7:
		var a := PI * 0.5 * i / 6.0
		prof.append(Vector2(sin(a), cos(a)))
	for i in range(1, 8):
		var k := i / 7.0
		prof.append(Vector2(pow(1.0 - k, 1.25) * (1.0 - 0.25 * sin(k * PI)), -2.6 * k))
	var seg := 12
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in prof.size() - 1:
		for j in seg:
			var a0 := TAU * j / seg
			var a1 := TAU * (j + 1) / seg
			var p00 := Vector3(cos(a0) * prof[i].x, prof[i].y, sin(a0) * prof[i].x)
			var p01 := Vector3(cos(a1) * prof[i].x, prof[i].y, sin(a1) * prof[i].x)
			var p10 := Vector3(cos(a0) * prof[i + 1].x, prof[i + 1].y, sin(a0) * prof[i + 1].x)
			var p11 := Vector3(cos(a1) * prof[i + 1].x, prof[i + 1].y, sin(a1) * prof[i + 1].x)
			for p in [p00, p10, p01, p01, p10, p11]:
				st.set_smooth_group(0)
				st.add_vertex(p)
	st.index()
	st.generate_normals()
	return st.commit()


# ------------------------------------------------------------ peças
static func _node(parent: Node, mesh: Mesh, mat: Material, cull := 4.0) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.extra_cull_margin = cull
	parent.add_child(n)
	return n


## Uma peça 3D de `mesh` no material `mat` ("crystal", "rock", "acid", "dust"), nas cores de `pal`.
static func _solid(parent: Node, mesh: Mesh, mat: String, pal: Array) -> MeshInstance3D:
	_shared()
	var n := _node(parent, mesh, _mats[mat])
	n.set_instance_shader_parameter("core", _v(pal[0]))
	n.set_instance_shader_parameter("mid", _v(pal[1]))
	n.set_instance_shader_parameter("shade", _v(pal[2]))
	n.set_instance_shader_parameter("seed", randf())
	return n


## Um cristal 3D (prisma com ponta) de altura `h` e grossura `w`, nas cores de `pal`, com o pé na origem.
static func _gem(parent: Node, h: float, w: float, pal: Array) -> MeshInstance3D:
	var n := _solid(parent, _crystal, "crystal", pal)
	n.scale = Vector3(w, h, w)
	n.set_instance_shader_parameter("streak", 1.0)
	return n


## Uma baforada de poeira: bolas juntas (raio total ~`size`), que incham depressa e murcham até sumir.
static func _puff(parent: Node, size: float) -> Node3D:
	var puff := Node3D.new()
	parent.add_child(puff)
	for i in 6:
		var b := _solid(puff, _ball, "dust", DUST)
		var off := Vector3.ZERO if i == 0 else Vector3(randf_range(-1.0, 1.0), randf_range(-0.3, 0.8), randf_range(-1.0, 1.0)).normalized()
		b.position = off * size * 0.5
		b.scale = Vector3.ONE * size * (0.55 if i == 0 else randf_range(0.28, 0.45))
	return puff


## Tamanho da baforada no tempo `t` de `life` s: incha em 0,12 s, fica e murcha (sem transparência).
static func _puff_scale(t: float, life: float) -> float:
	var up := _k(t, 0.0, 0.12)
	return maxf(0.001, (0.4 + 0.6 * LightningShockwaveFX._out(up)) * (1.0 - pow(_k(t, life * 0.45, life), 2.0)))


## Uma lasca de pedra 3D, com `size` m.
static func _chunk(parent: Node, size: float) -> MeshInstance3D:
	var n := _solid(parent, _rock, "rock", ROCK)
	n.scale = Vector3(randf_range(0.7, 1.2), randf_range(0.6, 1.0), randf_range(0.7, 1.2)) * size
	return n


## A crista de choque (onda_faixa.png) enrolada em anel no chão.
static func _crest(parent: Node, mat: String, col: Color, reach: float) -> MeshInstance3D:
	_shared()
	var n := MeshInstance3D.new()
	n.mesh = _annulus
	n.material_override = _mats[mat]
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.custom_aabb = AABB(Vector3(-reach, -1.0, -reach), Vector3(reach * 2.0, 4.0, reach * 2.0))
	n.set_instance_shader_parameter("col", _v(col))
	n.set_instance_shader_parameter("seed", randf())
	parent.add_child(n)
	return n


static func _k(t: float, a: float, b: float) -> float:
	return clampf((t - a) / (b - a), 0.0, 1.0)


## Anima uma lista de coisas arremessadas ({node, from, vel, spin, axis, size}): voam, giram e encolhem no fim.
static func _fly(bits: Array, t: float, gravity: float, life: float) -> void:
	for b in bits:
		var node: Node3D = b.node
		node.visible = t > 0.02 and t < life
		var p: Vector3 = (b.from as Vector3) + (b.vel as Vector3) * t + Vector3.DOWN * gravity * t * t
		var s: Vector3 = (b.size as Vector3) * maxf(0.001, 1.0 - _k(t, life * 0.65, life))
		node.basis = Basis(b.axis as Vector3, float(b.spin) * t) * Basis.from_scale(s)
		node.position = p


static func _bit(node: Node3D, from: Vector3, vel: Vector3) -> Dictionary:
	return {"node": node, "from": from, "vel": vel, "spin": randf_range(-9.0, 9.0), "size": node.scale,
		"axis": Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()}


# ------------------------------------------------------------ Onda de Cristais
## Um anel da Onda de Cristais em volta de `pos` (raio do meio `r`), que estoura daqui a `delay` s: `n` geodos
## (pedras redondas com pontas de cristal) brotam do chão um pouco antes, tremem, acendem por dentro e explodem em
## estilhaços de cristal voando para cima e para fora, com as cascas partidas e a crista de choque correndo o anel.
## Não fica cristal em pé. `fury`: cristais vermelhos.
static func geode_ring(root: Node, pos: Vector3, r: float, n: int, delay: float, fury := false) -> void:
	if root == null or not root.is_inside_tree():
		return
	var pal: Array = FURY if fury else CYAN
	var grow := minf(0.5, maxf(delay, 0.0))      # quanto tempo o geodo tem para brotar antes de estourar
	var t0 := delay - grow
	var fx := IceFX.Timed.new()
	fx.life = delay + 1.0
	root.add_child(fx)
	fx.global_position = pos
	var geodes: Array[Dictionary] = []
	var shards: Array[Dictionary] = []
	var flashes: Array[Vector3] = []
	var burst := [false]
	for i in n:
		var a := TAU * (i + randf_range(-0.25, 0.25)) / n
		var out := Vector3(cos(a), 0.0, sin(a))
		var foot := out * (r + randf_range(-0.45, 0.45))
		var size := randf_range(1.15, 1.6)
		var geo := Node3D.new()
		fx.add_child(geo)
		geo.basis = Basis(Vector3.UP, randf() * TAU)
		var shell := _solid(geo, _rock, "rock", GEODE)
		shell.scale = Vector3(1.0, 0.9, 1.0) * size
		var heart := _solid(geo, _rock, "rock", pal)      # o miolo de cristal, que incha e acende antes de estourar
		for k in 3:      # pontas de cristal furando a casca
			var dir := Vector3(randf_range(-1.0, 1.0), randf_range(0.2, 1.0), randf_range(-1.0, 1.0)).normalized()
			var tip := _gem(geo, size * randf_range(0.45, 0.7), size * 0.09, pal)
			tip.basis = RuneBladesFX.basis_along(dir) * Basis.from_scale(tip.scale)
			tip.position = dir * size * 0.3
		geodes.append({"node": geo, "heart": heart, "foot": foot, "size": size, "wait": randf_range(0.0, 0.08)})
		var top := foot + Vector3.UP * size * 0.4
		for k in 6:      # estilhaços de cristal: para cima e para fora
			var b := TAU * k / 6.0 + randf_range(-0.4, 0.4)
			var gem := _gem(fx, randf_range(0.7, 1.3), randf_range(0.1, 0.17), pal)
			gem.set_instance_shader_parameter("glow", 0.5)
			shards.append(_bit(gem, top, Vector3(cos(b), 0.0, sin(b)) * randf_range(1.5, 4.5) + out * randf_range(0.0, 2.5)
				+ Vector3.UP * randf_range(6.0, 11.0)))
		for k in 5:      # a casca partida
			var b := TAU * k / 5.0 + randf_range(-0.5, 0.5)
			var bit := _solid(fx, _rock, "rock", GEODE)
			bit.scale = Vector3.ONE * size * randf_range(0.28, 0.42)
			shards.append(_bit(bit, top, Vector3(cos(b), 0.0, sin(b)) * randf_range(2.5, 5.0) + Vector3.UP * randf_range(3.5, 6.5)))
		if i % 3 == 0:
			flashes.append(top)
	var crest := _crest(fx, "ring_glow", pal[1], r + 4.0)
	crest.set_instance_shader_parameter("width", 1.6)
	crest.set_instance_shader_parameter("lift", 0.5)
	fx.step = func(t: float) -> void:
		var bt := t - delay      # tempo desde o estouro
		for g in geodes:
			var geo: Node3D = g.node
			var size: float = g.size
			var gt := (t - t0 - float(g.wait) * grow) / maxf(grow * 0.6, 0.01)      # 0 -> 1 brotando
			geo.visible = bt < 0.0 and gt > 0.0
			if not geo.visible:
				continue
			var up := LightningShockwaveFX._out(clampf(gt, 0.0, 1.0))
			var hot := _k(t, delay - minf(0.18, grow), delay)      # perto do estouro: treme e acende
			var shake := Vector3(sin(t * 71.0 + size * 9.0), 0.0, cos(t * 63.0 + size * 5.0)) * 0.06 * hot
			geo.position = (g.foot as Vector3) + Vector3.UP * size * lerpf(-0.6, 0.3, up) + shake
			var heart: MeshInstance3D = g.heart
			heart.scale = Vector3(1.0, 0.9, 1.0) * size * lerpf(0.8, 1.07, hot * hot)
			heart.set_instance_shader_parameter("glow", 2.0 * hot)
		for b in shards:
			(b.node as Node3D).visible = false
		if bt >= 0.0:
			_fly(shards, bt, 12.0, 0.85)
			if not burst[0]:      # o clarão do estouro, na cor do cristal
				burst[0] = true
				for at in flashes:
					IceFX._flash(fx, at, (pal[1] as Color).lerp(pal[0], 0.4), 3.2, 0.09, 0.16)
		crest.visible = bt >= 0.0 and bt < 0.5
		crest.set_instance_shader_parameter("radius", r - 1.0 + 1.2 * LightningShockwaveFX._out(_k(bt, 0.0, 0.3)))
		crest.set_instance_shader_parameter("erode", lerpf(0.08, 1.0, _k(bt, 0.12, 0.5)))
	fx.step.call(0.0)


# ------------------------------------------------------------ Desmoronamento
## O pedregulho do Desmoronamento: cai do alto até `pos` em `fall` s, girando, e estoura no chão (`radius` = a
## área que dói).
static func falling_rock(root: Node, pos: Vector3, fall: float, radius := 2.2) -> void:
	if root == null or not root.is_inside_tree():
		return
	fall = maxf(0.05, fall)
	var fx := IceFX.Timed.new()
	fx.life = fall + 0.1
	root.add_child(fx)
	fx.global_position = pos
	var rock := _solid(fx, _rock, "rock", ROCK)
	var size := Vector3(1.0, 0.85, 0.95) * BOULDER
	var axis := Vector3(randf_range(-1.0, 1.0), randf_range(-0.3, 0.3), randf_range(-1.0, 1.0)).normalized()
	var spin := randf_range(3.0, 6.0)
	fx.step = func(t: float) -> void:
		if not rock.visible:
			return
		if t >= fall:
			rock.visible = false
			rock_impact(root, pos, radius)
			return
		var k := t / fall
		rock.basis = Basis(axis, spin * t) * Basis.from_scale(size)
		rock.position = Vector3.UP * lerpf(DROP_H, BOULDER * 0.35, k * k)
	fx.step.call(0.0)


## O impacto de uma pedra em `pos`: chão quebrado com as rachaduras acesas, anel de choque, poeira e lascas.
static func rock_impact(root: Node, pos: Vector3, radius: float) -> void:
	if root == null or not root.is_inside_tree():
		return
	_shared()
	var fx := IceFX.Timed.new()
	fx.life = 2.2
	root.add_child(fx)
	fx.global_position = pos
	var crater := _node(fx, _plane, _mats["ground"], radius * 2.0)
	crater.position = Vector3.UP * 0.1
	crater.scale = Vector3(radius * 2.7, 1.0, radius * 2.7)
	crater.set_instance_shader_parameter("spin", randf() * TAU)
	crater.set_instance_shader_parameter("hot", _v(AMBER))
	crater.set_instance_shader_parameter("stone_a", _v(Color(0.47, 0.41, 0.36)))
	crater.set_instance_shader_parameter("stone_b", _v(Color(0.2, 0.16, 0.14)))
	var crest := _crest(fx, "ring_dust", DUST[1], radius * 3.0)
	crest.set_instance_shader_parameter("lift", 0.9)
	var puffs: Array[Dictionary] = []
	for i in 6:
		var a := TAU * i / 5.0 + randf_range(-0.4, 0.4)
		var out := Vector3.ZERO if i == 0 else Vector3(cos(a), 0.0, sin(a))
		puffs.append({"node": _puff(fx, radius * (0.6 if i == 0 else randf_range(0.36, 0.5))),
			"from": out * radius * 0.5 + Vector3.UP * radius * (0.4 if i == 0 else 0.25),
			"delay": 0.0 if i == 0 else randf_range(0.02, 0.08), "life": randf_range(0.65, 0.85),
			"vel": out * randf_range(2.5, 4.0) + Vector3.UP * randf_range(0.8, 1.8)})
	var bits: Array[Dictionary] = []
	for i in 9:      # o pedregulho se parte: lascas para todos os lados
		var a := TAU * i / 9.0 + randf_range(-0.3, 0.3)
		bits.append(_bit(_chunk(fx, randf_range(0.35, 0.8)), Vector3.UP * 0.5,
			Vector3(cos(a), 0.0, sin(a)) * randf_range(3.0, 6.5) + Vector3.UP * randf_range(5.0, 9.5)))
	IceFX._flash(fx, Vector3.UP * 0.6, AMBER, radius * 2.0, 0.08, 0.14)
	var light := OmniLight3D.new()
	light.light_color = AMBER
	light.omni_range = radius * 3.0
	light.shadow_enabled = false
	light.position = Vector3.UP * 1.0
	fx.add_child(light)
	fx.step = func(t: float) -> void:
		crater.set_instance_shader_parameter("grow", lerpf(0.2, 1.1, LightningShockwaveFX._out(_k(t, 0.0, 0.12))))
		crater.set_instance_shader_parameter("heat", 1.0 - _k(t, 0.3, 1.6))
		crater.set_instance_shader_parameter("erode", _k(t, 1.5, 2.2))
		crest.set_instance_shader_parameter("radius", radius * lerpf(0.25, 1.15, LightningShockwaveFX._out(_k(t, 0.0, 0.3))))
		crest.set_instance_shader_parameter("width", radius * 0.55)
		crest.set_instance_shader_parameter("erode", lerpf(0.05, 1.0, _k(t, 0.14, 0.45)))
		crest.visible = t < 0.46
		for p in puffs:
			var node: Node3D = p.node
			var pt := t - float(p.delay)
			node.visible = pt >= 0.0 and pt < float(p.life)
			if node.visible:
				node.position = (p.from as Vector3) + (p.vel as Vector3) * (1.0 - exp(-4.0 * pt)) / 4.0
				node.scale = Vector3.ONE * _puff_scale(pt, float(p.life))
		_fly(bits, t, 12.0, 1.0)
		light.light_energy = 3.5 * (1.0 - _k(t, 0.0, 0.5))
	fx.step.call(0.0)


# ------------------------------------------------------------ ácido
## A bolha de ácido voando, com a cabeça de `radius` m: filha de `parent`, aponta sozinha para onde anda.
static func glob(parent: Node, radius: float) -> Glob:
	_shared()
	var g := Glob.new()
	parent.add_child(g)
	var head := _solid(g, _drop, "acid", ACID)
	head.scale = Vector3.ONE * radius
	head.set_instance_shader_parameter("spec", 1.0)
	head.set_instance_shader_parameter("glow", 0.25)
	for i in 3:      # gotinhas soltas atrás da cauda
		var d := _solid(g, _ball, "acid", ACID)
		d.scale = Vector3.ONE * radius * (0.3 - 0.07 * i)
		d.position = Vector3(randf_range(-0.3, 0.3), -(2.9 + 0.75 * i), randf_range(-0.3, 0.3)) * radius
		d.set_instance_shader_parameter("spec", 1.0)
	return g


## A coroa do respingo de ácido em `pos` (o chão), com `width` m de largura.
static func acid_splash(root: Node, pos: Vector3, width: float) -> void:
	if root == null or not root.is_inside_tree():
		return
	_shared()
	var fx := IceFX.Timed.new()
	fx.life = 0.5
	root.add_child(fx)
	fx.global_position = pos
	var tongues: Array[Dictionary] = []
	var count := 9
	for i in count:      # línguas em coroa: a gota de cabeça para cima, tombada para fora
		var a := TAU * i / count + randf_range(-0.2, 0.2)
		var n := _solid(fx, _drop, "acid", ACID)
		n.set_instance_shader_parameter("spec", 1.0)
		n.set_instance_shader_parameter("glow", 0.25)
		tongues.append({"node": n, "out": Vector3(cos(a), 0.0, sin(a)), "lean": randf_range(0.35, 0.75),
			"r": width * randf_range(0.055, 0.085), "h": width * randf_range(0.3, 0.52), "delay": randf_range(0.0, 0.04)})
	var drops: Array[Dictionary] = []
	for i in 10:
		var a := TAU * i / 10.0 + randf_range(-0.3, 0.3)
		var d := _solid(fx, _ball, "acid", ACID)
		d.scale = Vector3.ONE * width * randf_range(0.03, 0.06)
		d.set_instance_shader_parameter("spec", 1.0)
		drops.append(_bit(d, Vector3.UP * 0.2, Vector3(cos(a), 0.0, sin(a)) * width * randf_range(0.8, 1.7)
			+ Vector3.UP * width * randf_range(1.6, 2.6)))
	IceFX._flash(fx, Vector3.UP * width * 0.25, ACID[1], width * 0.9, 0.07, 0.1)
	fx.step = func(t: float) -> void:
		for g in tongues:
			var n: MeshInstance3D = g.node
			var tt := t - float(g.delay)
			# sobe depressa e desce afinando
			var up := LightningShockwaveFX._out(_k(tt, 0.0, 0.14)) * (1.0 - pow(_k(tt, 0.2, 0.46), 2.0))
			n.visible = tt >= 0.0 and up > 0.01
			var out: Vector3 = g.out
			var axis := (Vector3.UP + out * float(g.lean)).normalized()
			var h := float(g.h) * up
			var rr := float(g.r) * (0.5 + 0.5 * up)
			# a cauda da gota (2,6 raios abaixo da cabeça) fica cravada no chão: a cabeça sobe a `h`
			n.basis = RuneBladesFX.basis_along(axis) * Basis.from_scale(Vector3(rr, maxf(h / 2.6, 0.001), rr))
			n.position = out * width * lerpf(0.18, 0.34, _k(tt, 0.0, 0.3)) + axis * h
		_fly(drops, t, width * 6.5, 0.5)
	fx.step.call(0.0)


## A tela da Poça de Ácido: plano pintado com `radius` m de líquido, filho de `parent`. Quem chamou anima
## `grow` (0 -> 1, a poça se espalha) e `erode` (0 -> 1, some comida) pelos parâmetros de instância.
static func acid_pool(parent: Node, radius: float) -> MeshInstance3D:
	_shared()
	var n := _node(parent, _plane, _mats["pool"], radius)
	# o líquido da pintura vai até ~0,8 do meio-lado do plano
	n.scale = Vector3(radius * 2.5, 1.0, radius * 2.5)
	n.position = Vector3.UP * 0.1
	n.set_instance_shader_parameter("core", _v(ACID[0]))
	n.set_instance_shader_parameter("mid", _v(ACID[1]))
	n.set_instance_shader_parameter("shade", _v(ACID[2]))
	n.set_instance_shader_parameter("seed", randf())
	return n


## A bolha de ácido: a gota tem a cabeça no +Y e a cauda no -Y, então o nó vira o +Y para onde anda.
class Glob:
	extends Node3D

	var _prev := Vector3.ZERO
	var _has_prev := false

	func _process(_delta: float) -> void:
		var at := global_position
		if _has_prev:
			var d := at - _prev
			if d.length() > 0.001:
				global_basis = RuneBladesFX.basis_along(d)
		_prev = at
		_has_prev = true
