class_name WormFX
extends RefCounted
## Efeitos da Mãe-Verme das Profundezas, feitos em código sobre seis pinturas (claro em fundo preto, tingidas no
## shader); os cristais são malha 3D pintada como desenho (de lado, pintura chapada denunciava o truque):
##   crystal_ring  um anel da Onda de Cristais: cachos de cristais 3D facetados que sobem de dentro do chão
##                 num jorro de terra (jorro_terra.png, 4 quadros), com lascas de pedra (pedras_folha.png), poeira
##                 (a nuvem da explosão, em tons de terra) e a crista de choque correndo o anel; depois afundam
##   falling_rock  o pedregulho do Desmoronamento caindo (pedras_folha.png) e o impacto: chão quebrado com as
##                 rachaduras acesas (chao_rachado.png), anel de choque, poeira e lascas
##   glob          a bolha de ácido voando (acido_respingo.png), virada para onde vai: o cuspe e as Poças
##   acid_splash   a coroa do respingo (acido_respingo.png, 3 quadros)
##   acid_pool     a poça (acido_poca.png girando, com a trama de acido_bolhas.png fervendo): a tela de AcidPool
## Em jogo: BossFX.crystal_ring / falling_rock / lob, Enemy._acid_hit, AcidPool e EnemyArrow (cuspe).

const DIRT_TEX := preload("res://assets/vfx/worm/jorro_terra.png")
const ROCKS_TEX := preload("res://assets/vfx/worm/pedras_folha.png")
const CRATER_TEX := preload("res://assets/vfx/worm/chao_rachado.png")
const POOL_TEX := preload("res://assets/vfx/worm/acido_poca.png")
const SPLASH_TEX := preload("res://assets/vfx/worm/acido_respingo.png")
const WEB_TEX := preload("res://assets/vfx/worm/acido_bolhas.png")
const CLOUD_TEX := preload("res://assets/vfx/explosion/nuvem_folha.png")
const EMBER_TEX := preload("res://assets/vfx/explosion/rachas_brasa.png")
const CREST_TEX := preload("res://assets/vfx/lightning_shockwave/onda_faixa.png")
const CARD := preload("res://shaders/worm/worm_card.gdshader")
const GROUND := preload("res://shaders/worm/worm_ground.gdshader")
const POOL := preload("res://shaders/worm/acid_pool.gdshader")
const CLOUD := preload("res://shaders/explosion/cloud_flip.gdshader")
const RING := preload("res://shaders/lightning_shockwave/wave_ring.gdshader")
const CRYSTAL := preload("res://shaders/worm/worm_crystal.gdshader")
const CRYSTAL_INK := preload("res://shaders/worm/worm_crystal_ink.gdshader")

## Cores como se vê na tela (sRGB); `_v` converte para o shader. Cada paleta: face clara, cor, sombra.
const CYAN := [Color(0.88, 0.99, 1.0), Color(0.22, 0.8, 1.0), Color(0.16, 0.12, 0.62)]
const FURY := [Color(1.0, 0.9, 0.82), Color(1.0, 0.24, 0.14), Color(0.42, 0.02, 0.14)]
const EARTH := [Color(0.84, 0.74, 0.6), Color(0.56, 0.43, 0.31), Color(0.25, 0.17, 0.13)]
const ROCK := [Color(0.8, 0.78, 0.76), Color(0.5, 0.47, 0.46), Color(0.2, 0.18, 0.21)]
const ACID := [Color(0.78, 1.0, 0.3), Color(0.36, 0.9, 0.08), Color(0.03, 0.26, 0.05)]
const DUST_A := Color(0.66, 0.58, 0.48)
const DUST_B := Color(0.4, 0.33, 0.27)
const AMBER := Color(1.0, 0.62, 0.15)
## O pedregulho do Desmoronamento (m) e a altura de onde cai.
const BOULDER := 2.6
const DROP_H := 14.0

static var _mats := {}
static var _quad: QuadMesh
static var _strip: QuadMesh
static var _plane: PlaneMesh
static var _annulus: ArrayMesh
static var _crystal: ArrayMesh


static func _v(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	return Vector3(l.r, l.g, l.b)


static func _shared() -> void:
	if _quad != null:
		return
	_quad = QuadMesh.new()
	_strip = QuadMesh.new()
	_strip.center_offset = Vector3(0.0, 0.5, 0.0)
	_plane = PlaneMesh.new()
	_plane.size = Vector2.ONE
	_annulus = LightningShockwaveFX._annulus()
	# [pintura, linha do pé na célula, prioridade]: a terra atrás, os cristais na frente
	for spec in [["dirt", DIRT_TEX, 0.13, 1], ["rock", ROCKS_TEX, 0.0, 4],
			["splash", SPLASH_TEX, 0.1, 3]]:
		var m := ShaderMaterial.new()
		m.shader = CARD
		m.set_shader_parameter("paint", spec[1])
		m.set_shader_parameter("cols", 2.0)
		m.set_shader_parameter("base", spec[2])
		m.set_shader_parameter("foot_fade", 0.14 if spec[0] == "splash" else 0.0)
		m.render_priority = spec[3]
		_mats[spec[0]] = m
	var ink := ShaderMaterial.new()
	ink.shader = CRYSTAL_INK
	var gem := ShaderMaterial.new()
	gem.shader = CRYSTAL
	gem.next_pass = ink
	_mats["crystal"] = gem
	_crystal = _crystal_mesh()
	var cloud := ShaderMaterial.new()
	cloud.shader = CLOUD
	cloud.set_shader_parameter("sheet", CLOUD_TEX)
	cloud.set_shader_parameter("cracks", EMBER_TEX)
	cloud.render_priority = 2
	_mats["cloud"] = cloud
	var ground := ShaderMaterial.new()
	ground.shader = GROUND
	ground.set_shader_parameter("cracks", CRATER_TEX)
	_mats["ground"] = ground
	var pool := ShaderMaterial.new()
	pool.shader = POOL
	pool.set_shader_parameter("pool", POOL_TEX)
	pool.set_shader_parameter("web", WEB_TEX)
	_mats["pool"] = pool
	for spec in [["ring_dust", DUST_B.darkened(0.45), 0.35], ["ring_glow", Color(0.05, 0.05, 0.3), 0.7]]:
		var ring := ShaderMaterial.new()
		ring.shader = RING
		ring.set_shader_parameter("crest", CREST_TEX)
		ring.set_shader_parameter("deep", _v(spec[1]))
		ring.set_shader_parameter("highlight", spec[2])
		ring.render_priority = 1
		_mats[spec[0]] = ring


static func _node(parent: Node, mesh: Mesh, mat: Material, cull := 4.0) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.extra_cull_margin = cull
	parent.add_child(n)
	return n


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


## Um cacho de cristais 3D com o pé na origem de `parent`: um grande no meio e outros menores abrindo em leque.
## `h` = altura do maior (m). Devolve os cristais (para animar o brilho).
static func crystal_cluster(parent: Node3D, h: float, pal: Array) -> Array[MeshInstance3D]:
	_shared()
	var out: Array[MeshInstance3D] = []
	var count := 5 + randi() % 3
	var turn := randf() * TAU
	for i in count:
		var n := _node(parent, _crystal, _mats["crystal"], h)
		var k := 1.0 if i == 0 else randf_range(0.4, 0.75)
		var thick := h * k * randf_range(0.13, 0.18)
		n.scale = Vector3(thick, h * k, thick)
		if i > 0:   # os menores tombam para fora, em volta do grande
			var a := turn + TAU * i / float(count - 1) + randf_range(-0.3, 0.3)
			var lean := Vector3(cos(a), 0.0, sin(a))
			n.position = lean * h * randf_range(0.05, 0.12)
			n.basis = Basis(lean.cross(Vector3.UP).normalized(), -randf_range(0.35, 0.8)) * Basis.from_scale(n.scale)
		n.rotate_object_local(Vector3.UP, randf() * TAU)
		n.position.y -= h * 0.12      # o pé fica enterrado
		n.set_instance_shader_parameter("core", _v(pal[0]))
		n.set_instance_shader_parameter("mid", _v(pal[1]))
		n.set_instance_shader_parameter("shade", _v(pal[2]))
		out.append(n)
	return out


## Uma pintura da folha `sheet` ("dirt", "rock", "splash"), célula `cell`, nas cores de `pal`.
## `upright`: em pé, com o pé na origem do nó (a escala é largura, altura); senão virada para a câmera.
static func card(parent: Node, sheet: String, cell: int, pal: Array, upright := false) -> MeshInstance3D:
	_shared()
	var n := _node(parent, _strip if upright else _quad, _mats[sheet])
	n.set_instance_shader_parameter("cell", float(cell))
	n.set_instance_shader_parameter("core", _v(pal[0]))
	n.set_instance_shader_parameter("mid", _v(pal[1]))
	n.set_instance_shader_parameter("shade", _v(pal[2]))
	n.set_instance_shader_parameter("upright", 1.0 if upright else 0.0)
	n.set_instance_shader_parameter("flip", float(randi() % 2))
	n.set_instance_shader_parameter("seed", randf())
	return n


## Uma baforada de poeira (a nuvem da explosão, sem fogo).
static func _puff(parent: Node, size: float) -> MeshInstance3D:
	_shared()
	var n := _node(parent, _quad, _mats["cloud"], size)
	n.scale = Vector3.ONE * size
	n.set_instance_shader_parameter("roll", randf_range(-0.5, 0.5))
	n.set_instance_shader_parameter("flip", float(randi() % 2))
	n.set_instance_shader_parameter("seed", randf())
	n.set_instance_shader_parameter("smoke_a", _v(DUST_A))
	n.set_instance_shader_parameter("smoke_b", _v(DUST_B))
	n.set_instance_shader_parameter("heat", 0.0)
	n.set_instance_shader_parameter("glow", 0.0)
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


## Quadro da nuvem de poeira no tempo `t` de `life` s: infla depressa (quadros 2 a 7) e se desfaz (até o 15).
static func _dust_frame(t: float, life: float) -> float:
	if t < 0.14:
		return floorf(2.0 + 5.0 * t / 0.14)
	return floorf(minf(15.0, 7.0 + 8.99 * (t - 0.14) / (life - 0.14)))


## Um anel da Onda de Cristais em volta de `pos`: raio do meio `r`, `n` cachos. `fury`: cristais vermelhos.
static func crystal_ring(root: Node, pos: Vector3, r: float, n: int, fury := false) -> void:
	if root == null or not root.is_inside_tree():
		return
	var pal: Array = FURY if fury else CYAN
	var fx := IceFX.Timed.new()
	fx.life = 1.25
	root.add_child(fx)
	fx.global_position = pos
	var clusters: Array[Dictionary] = []
	var bits: Array[Dictionary] = []
	var puffs: Array[Dictionary] = []
	for i in n:
		var a := TAU * (i + randf_range(-0.3, 0.3)) / n
		var out := Vector3(cos(a), 0.0, sin(a))
		var foot := out * (r + randf_range(-0.5, 0.5))
		var holder := Node3D.new()
		fx.add_child(holder)
		holder.position = foot
		# o cacho tomba para fora, como a onda que o empurra
		holder.basis = RuneBladesFX.basis_along((Vector3.UP + out * randf_range(0.15, 0.5)).normalized())
		var h := randf_range(2.3, 3.4)
		var dirt := card(holder, "dirt", 0, EARTH, true)
		var dw := h * randf_range(1.0, 1.25)
		dirt.scale = Vector3(dw, dw, 1.0)
		var grp := Node3D.new()
		holder.add_child(grp)
		clusters.append({"dirt": dirt, "grp": grp, "h": h, "gems": crystal_cluster(grp, h, pal),
			"delay": randf_range(0.0, 0.07)})
		if i % 3 == 0:
			var rock := card(fx, "rock", 1 + randi() % 3, ROCK)
			rock.scale = Vector3.ONE * randf_range(0.45, 0.8)
			bits.append({"node": rock, "from": foot + Vector3.UP * 0.4, "spin": randf_range(-9.0, 9.0),
				"vel": (out * randf_range(-1.5, 3.5) + Vector3.UP * randf_range(5.0, 9.0))})
		if i % 3 == 1:
			var puff := _puff(fx, randf_range(2.6, 3.6))
			puffs.append({"node": puff, "from": foot + Vector3.UP * 0.7, "delay": randf_range(0.03, 0.12), "life": randf_range(0.8, 1.05),
				"vel": out * randf_range(0.5, 1.6) + Vector3.UP * randf_range(0.8, 1.6)})
	var crest := _crest(fx, "ring_glow", pal[1], r + 4.0)
	crest.set_instance_shader_parameter("width", 1.6)
	crest.set_instance_shader_parameter("lift", 0.5)
	fx.step = func(t: float) -> void:
		for c in clusters:
			var ct := t - float(c.delay)
			var up := _k(ct, 0.0, 0.1)
			var rise := (up + 0.12 * sin(up * PI)) * (1.0 - _k(ct, 0.6, 0.9))   # passa do ponto, fica e afunda
			# os cristais sobem de verdade de dentro do chão (o terreno esconde o que ainda está embaixo)
			(c.grp as Node3D).position.y = -float(c.h) * 1.15 * (1.0 - rise)
			(c.grp as Node3D).visible = ct >= 0.0 and rise > 0.01
			for g in c.gems:
				(g as MeshInstance3D).set_instance_shader_parameter("glow", lerpf(1.0, 0.2, _k(ct, 0.05, 0.4)))
			var d: MeshInstance3D = c.dirt
			d.visible = ct >= 0.0 and ct < 0.44
			d.set_instance_shader_parameter("cell", floorf(clampf(ct / 0.11, 0.0, 3.0)))
		for b in bits:
			var node: MeshInstance3D = b.node
			node.visible = t > 0.03 and t < 0.9
			node.position = (b.from as Vector3) + (b.vel as Vector3) * t + Vector3.DOWN * 11.0 * t * t
			node.set_instance_shader_parameter("roll", float(b.spin) * t)
			node.set_instance_shader_parameter("erode", _k(t, 0.6, 0.9))
		for p in puffs:
			var node: MeshInstance3D = p.node
			var pt := t - float(p.delay)
			node.visible = pt >= 0.0 and pt < float(p.life)
			if node.visible:
				node.position = (p.from as Vector3) + (p.vel as Vector3) * (1.0 - exp(-3.0 * pt)) / 3.0
				node.set_instance_shader_parameter("frame", _dust_frame(pt, float(p.life)))
		crest.set_instance_shader_parameter("radius", r - 1.0 + 1.2 * LightningShockwaveFX._out(_k(t, 0.0, 0.3)))
		crest.set_instance_shader_parameter("erode", lerpf(0.08, 1.0, _k(t, 0.12, 0.5)))
		crest.visible = t < 0.5
	fx.step.call(0.0)


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
	var rock := card(fx, "rock", 0, ROCK)
	rock.scale = Vector3.ONE * BOULDER
	var spin := randf_range(-5.0, 5.0)
	var roll0 := randf() * TAU
	fx.step = func(t: float) -> void:
		if not rock.visible:
			return
		if t >= fall:
			rock.visible = false
			rock_impact(root, pos, radius)
			return
		var k := t / fall
		rock.position = Vector3.UP * lerpf(DROP_H, BOULDER * 0.35, k * k)
		rock.set_instance_shader_parameter("roll", roll0 + spin * t)
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
	var crest := _crest(fx, "ring_dust", DUST_A, radius * 3.0)
	crest.set_instance_shader_parameter("lift", 0.9)
	var puffs: Array[Dictionary] = []
	for i in 5:
		var a := TAU * i / 4.0 + randf_range(-0.4, 0.4)
		var out := Vector3.ZERO if i == 0 else Vector3(cos(a), 0.0, sin(a))
		var puff := _puff(fx, radius * (1.5 if i == 0 else randf_range(0.9, 1.25)))
		puffs.append({"node": puff, "from": out * radius * 0.5 + Vector3.UP * radius * (0.5 if i == 0 else 0.3), "delay": 0.0 if i == 0 else randf_range(0.02, 0.08), "life": randf_range(0.65, 0.85),
			"vel": out * randf_range(2.5, 4.0) + Vector3.UP * randf_range(0.8, 1.8)})
	var bits: Array[Dictionary] = []
	for i in 8:
		var a := TAU * i / 8.0 + randf_range(-0.3, 0.3)
		var chunk := card(fx, "rock", 1 + i % 3, ROCK)
		chunk.scale = Vector3.ONE * randf_range(0.45, 0.95)
		bits.append({"node": chunk, "spin": randf_range(-10.0, 10.0),
			"vel": Vector3(cos(a), 0.0, sin(a)) * randf_range(3.0, 6.5) + Vector3.UP * randf_range(5.0, 9.5)})
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
			var node: MeshInstance3D = p.node
			var pt := t - float(p.delay)
			node.visible = pt >= 0.0 and pt < float(p.life)
			if node.visible:
				node.position = (p.from as Vector3) + (p.vel as Vector3) * (1.0 - exp(-4.0 * pt)) / 4.0
				node.set_instance_shader_parameter("frame", _dust_frame(pt, float(p.life)))
		for b in bits:
			var node: MeshInstance3D = b.node
			node.visible = t < 1.0
			node.position = Vector3.UP * 0.4 + (b.vel as Vector3) * t + Vector3.DOWN * 12.0 * t * t
			node.set_instance_shader_parameter("roll", float(b.spin) * t)
			node.set_instance_shader_parameter("erode", _k(t, 0.65, 1.0))
		light.light_energy = 3.5 * (1.0 - _k(t, 0.0, 0.5))
	fx.step.call(0.0)


## A bolha de ácido voando, com `size` m: filha de `parent`, vira a cauda para trás de onde anda sozinha.
static func glob(parent: Node, size: float) -> Glob:
	var g := Glob.new()
	parent.add_child(g)
	var n := card(g, "splash", 0, ACID)
	n.scale = Vector3.ONE * size
	n.set_instance_shader_parameter("flip", 0.0)
	n.set_instance_shader_parameter("glow", 0.5)
	g.card = n
	return g


## A coroa do respingo de ácido em `pos` (o chão), com `width` m.
static func acid_splash(root: Node, pos: Vector3, width: float) -> void:
	if root == null or not root.is_inside_tree():
		return
	var fx := IceFX.Timed.new()
	fx.life = 0.42
	root.add_child(fx)
	fx.global_position = pos
	var n := card(fx, "splash", 1, ACID, true)
	n.set_instance_shader_parameter("glow", 0.5)
	IceFX._flash(fx, Vector3.UP * width * 0.25, ACID[1], width * 0.9, 0.07, 0.1)
	fx.step = func(t: float) -> void:
		var k := _k(t, 0.0, 0.42)
		n.set_instance_shader_parameter("cell", 1.0 + floorf(minf(2.0, k * 3.0)))
		var s := width * lerpf(0.7, 1.15, LightningShockwaveFX._out(k))
		n.scale = Vector3(s, s, 1.0)
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


## A bolha de ácido: a pintura tem a cabeça à direita e a cauda à esquerda, então gira no plano da tela para a
## cabeça apontar para onde o nó anda.
class Glob:
	extends Node3D

	var card: MeshInstance3D
	var _prev := Vector3.ZERO
	var _has_prev := false

	func _process(_delta: float) -> void:
		var cam := get_viewport().get_camera_3d()
		var at := global_position
		if _has_prev and cam != null and card != null:
			var d := at - _prev
			if d.length() > 0.001:
				var b := cam.global_basis
				card.set_instance_shader_parameter("roll", atan2(d.dot(b.y), d.dot(b.x)))
		_prev = at
		_has_prev = true
