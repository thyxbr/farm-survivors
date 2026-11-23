class_name IceFX
extends RefCounted
## Gelo pintado da Sentinela da Nevasca: efeitos feitos em código sobre quatro pinturas (claro em fundo preto,
## tingidas no shader com as três cores do gelo de monstro: face clara, azul e sombra carmim).
##   bloom        o cacho de cristais que abre como flor num impacto (gelo_floracao.png), com o clarão de riscos,
##                cacos voando (gelo_cristais.png) e a geada no chão; depois estilhaça das pontas para o centro
##   frost_patch  a geada no chão (geada_chao.png): abre do centro, fica e some comida
##   crystal_card um cristal pintado em pé (a estaca que cai e fica cravada, os cacos do pé)
##   sprout       um cristal que brota do chão e some (o rastro do Sopro)
##   gust         uma rajada do Sopro: faixa de vento gelado (sopro_faixa.png) correndo da boca até um ponto
##   roar         o urro que chama a nevasca: cúpula de riscos girando (as pinturas da Esfera Sombria, em gelo) que
##                abre em volta dela e some, com geada no chão
## Em jogo: BlizzardFX.spike_impact (estacas e patada), BlizzardFX.breath_gust, IceSpike e Enemy._roar_warn.

const BLOOM_TEX := preload("res://assets/vfx/ice/gelo_floracao.png")
const SHARDS_TEX := preload("res://assets/vfx/ice/gelo_cristais.png")
const WIND_TEX := preload("res://assets/vfx/ice/sopro_faixa.png")
const FROST_TEX := preload("res://assets/vfx/ice/geada_chao.png")
const BURST_TEX := preload("res://assets/vfx/explosion/estouro_riscos.png")
const CARD := preload("res://shaders/ice/ice_card.gdshader")
const GROUND := preload("res://shaders/ice/ice_ground.gdshader")
const GUST := preload("res://shaders/ice/ice_gust.gdshader")
const FLARE := preload("res://shaders/sword_vortex/tex_flash.gdshader")
## Como se vê na tela (sRGB); `_v` converte para o shader.
const CORE := Color(0.86, 0.97, 1.0)
const MID := Color(0.36, 0.7, 0.98)
const SHADE := Color(0.5, 0.05, 0.22)
## A estaca que cai e fica cravada: a célula da folha de cristais (a agulha comprida) e a altura (m).
const SPIKE_CELL := 0
const SPIKE_H := 4.2

static var _bloom_mat: ShaderMaterial
static var _shard_mat: ShaderMaterial
static var _ground_mat: ShaderMaterial
static var _gust_mat: ShaderMaterial
static var _quad: QuadMesh
static var _strip: QuadMesh
static var _plane: PlaneMesh


static func _shared() -> void:
	if _bloom_mat != null:
		return
	_bloom_mat = ShaderMaterial.new()
	_bloom_mat.shader = CARD
	_bloom_mat.set_shader_parameter("paint", BLOOM_TEX)
	_bloom_mat.set_shader_parameter("cols", 1.0)
	_bloom_mat.render_priority = 2
	_shard_mat = ShaderMaterial.new()
	_shard_mat.shader = CARD
	_shard_mat.set_shader_parameter("paint", SHARDS_TEX)
	_shard_mat.set_shader_parameter("cols", 2.0)
	_shard_mat.render_priority = 3
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = GROUND
	_ground_mat.set_shader_parameter("frost", FROST_TEX)
	_gust_mat = ShaderMaterial.new()
	_gust_mat.shader = GUST
	_gust_mat.set_shader_parameter("wind", WIND_TEX)
	_gust_mat.render_priority = 1
	_quad = QuadMesh.new()
	_strip = QuadMesh.new()
	_strip.center_offset = Vector3(0.0, 0.5, 0.0)
	_plane = PlaneMesh.new()
	_plane.size = Vector2.ONE


static func _v(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	return Vector3(l.r, l.g, l.b)


static func _node(parent: Node, mesh: Mesh, mat: Material, cull := 4.0) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.extra_cull_margin = cull
	parent.add_child(n)
	return n


static func _card(parent: Node, mat: Material, cull := 4.0) -> MeshInstance3D:
	var n := _node(parent, _quad, mat, cull)
	n.set_instance_shader_parameter("core", _v(CORE))
	n.set_instance_shader_parameter("mid", _v(MID))
	n.set_instance_shader_parameter("shade", _v(SHADE))
	return n


## Um cristal pintado em pé (folha gelo_cristais.png, célula `cell`), com `height` m, a base no ponto do nó; gira
## só em volta do próprio Y para a câmera, então dá para incliná-lo. `point_down` vira a ponta para baixo.
static func crystal_card(parent: Node, cell: int, height: float, point_down := false) -> MeshInstance3D:
	_shared()
	var n := _node(parent, _strip, _shard_mat, height)
	n.scale = Vector3(height, height, 1.0)
	n.set_instance_shader_parameter("core", _v(CORE))
	n.set_instance_shader_parameter("mid", _v(MID))
	n.set_instance_shader_parameter("shade", _v(SHADE))
	n.set_instance_shader_parameter("cell", float(cell))
	n.set_instance_shader_parameter("upright", 1.0)
	n.set_instance_shader_parameter("flipv", 1.0 if point_down else 0.0)
	n.set_instance_shader_parameter("grow", 3.0)
	n.set_instance_shader_parameter("fade", 3.0)
	return n


## Um cristal pintado que brota do chão em `foot`, fica `hold` s e encolhe de volta (o rastro do Sopro).
static func sprout(root: Node, foot: Vector3, height: float, lean: Vector3, hold := 1.1) -> void:
	if root == null or not root.is_inside_tree():
		return
	var fx := Timed.new()
	fx.life = hold + 0.4
	root.add_child(fx)
	fx.global_position = foot
	fx.global_basis = RuneBladesFX.basis_along(lean)
	var n := crystal_card(fx, 1 + randi() % 3, height)
	n.set_instance_shader_parameter("flip", float(randi() % 2))
	fx.step = func(t: float) -> void:
		var up := clampf(t / 0.12, 0.0, 1.0)
		var down := clampf((t - (hold + 0.15)) / 0.25, 0.0, 1.0)
		var k := (up + 0.2 * sin(up * PI)) * (1.0 - down)
		n.scale = Vector3(height, height * maxf(0.001, k), 1.0)
	fx.step.call(0.0)


## O cacho de cristais abrindo em `pos` (o chão do impacto), com `radius` m.
static func bloom(root: Node, pos: Vector3, radius: float) -> void:
	if root == null or not root.is_inside_tree():
		return
	_shared()
	var fx := Timed.new()
	fx.life = 0.95
	root.add_child(fx)
	fx.global_position = pos
	var center := Vector3.UP * radius * 0.4
	# dois cachos: o de trás maior e girado, para o cacho ter fundo
	var cards: Array[MeshInstance3D] = []
	for i in 2:
		var n := _card(fx, _bloom_mat, radius * 3.0)
		n.position = center
		n.set_instance_shader_parameter("roll", randf() * TAU)
		n.set_instance_shader_parameter("flip", float(i))
		cards.append(n)
	var shards: Array[Dictionary] = []
	for i in 9:
		var n := _card(fx, _shard_mat, radius * 3.0)
		var a := TAU * float(i) / 9.0 + randf_range(-0.3, 0.3)
		n.set_instance_shader_parameter("cell", float(i % 4))
		n.set_instance_shader_parameter("flip", float(randi() % 2))
		n.scale = Vector3.ONE * radius * randf_range(0.28, 0.5)
		shards.append({"node": n, "vel": Vector3(cos(a), randf_range(0.9, 1.9), sin(a)) * radius * randf_range(2.2, 3.6),
			"roll": randf() * TAU, "spin": randf_range(-9.0, 9.0)})
	_flash(fx, center, CORE.lerp(MID, 0.4), radius * 2.4, 0.08, 0.24)
	var light := OmniLight3D.new()
	light.light_color = MID.lerp(CORE, 0.5)
	light.omni_range = radius * 3.5
	light.shadow_enabled = false
	light.position = center
	fx.add_child(light)
	frost_patch(root, pos, radius * 1.5, 1.8)
	fx.step = func(t: float) -> void:
		var open := clampf(t / 0.1, 0.0, 1.0)
		var pop := 1.0 + 0.18 * sin(open * PI)          # passa do tamanho e volta
		var gone := clampf((t - 0.42) / 0.38, 0.0, 1.0)
		for i in cards.size():
			var n := cards[i]
			n.scale = Vector3.ONE * radius * (2.3 if i == 0 else 2.75) * pop
			n.set_instance_shader_parameter("grow", lerpf(0.15, 1.1, open))
			n.set_instance_shader_parameter("fade", lerpf(1.2, -0.3, gone))
		for s in shards:
			var n: MeshInstance3D = s.node
			var v: Vector3 = s.vel
			n.visible = t > 0.03 and t < 0.75
			n.position = center * 0.6 + v * t * exp(-1.2 * t) + Vector3.DOWN * 7.0 * t * t
			n.set_instance_shader_parameter("roll", float(s.roll) + float(s.spin) * t)
			n.set_instance_shader_parameter("fade", lerpf(1.3, -0.3, clampf((t - 0.45) / 0.3, 0.0, 1.0)))
		light.light_energy = 4.0 * (1.0 - clampf(t / 0.2, 0.0, 1.0)) + 1.2 * (1.0 - clampf(t / 0.8, 0.0, 1.0))
	fx.step.call(0.0)


## Geada no chão em `pos`, com `radius` m, por `life` s. Devolve o nó (quem chamou pode soltá-lo antes).
static func frost_patch(root: Node, pos: Vector3, radius: float, life: float) -> Node3D:
	if root == null or not root.is_inside_tree():
		return null
	_shared()
	var fx := Timed.new()
	fx.life = life
	root.add_child(fx)
	fx.global_position = pos + Vector3.UP * 0.06
	var n := _node(fx, _plane, _ground_mat, radius)
	n.scale = Vector3(radius * 2.0, 1.0, radius * 2.0)
	n.set_instance_shader_parameter("core", _v(CORE))
	n.set_instance_shader_parameter("mid", _v(MID))
	n.set_instance_shader_parameter("spin", randf() * TAU)
	var out := minf(0.7, life * 0.4)
	fx.step = func(t: float) -> void:
		n.set_instance_shader_parameter("grow", lerpf(0.1, 1.15, 1.0 - pow(1.0 - clampf(t / 0.3, 0.0, 1.0), 2.0)))
		n.set_instance_shader_parameter("erode", clampf((t - (life - out)) / out, 0.0, 1.0))
	fx.step.call(0.0)
	return fx


## Uma rajada do Sopro, de `mouth` até `to`, com `width` m de largura.
static func gust(root: Node, mouth: Vector3, to: Vector3, width: float) -> void:
	if root == null or not root.is_inside_tree():
		return
	var d := to - mouth
	var length := d.length()
	if length < 0.5:
		return
	_shared()
	var fx := Timed.new()
	fx.life = 0.34
	root.add_child(fx)
	fx.global_position = mouth
	fx.global_basis = RuneBladesFX.basis_along(d)
	var n := _node(fx, _strip, _gust_mat, length)
	n.scale = Vector3(width, length, 1.0)
	n.set_instance_shader_parameter("col", _v(MID))
	n.set_instance_shader_parameter("core", _v(CORE))
	n.set_instance_shader_parameter("seed", randf())
	fx.step = func(t: float) -> void:
		n.set_instance_shader_parameter("reveal", lerpf(0.2, 1.3, clampf(t / 0.14, 0.0, 1.0)))
		n.set_instance_shader_parameter("intensity", 0.85 * (1.0 - clampf((t - 0.2) / 0.14, 0.0, 1.0)))
	fx.step.call(0.0)


## O urro: cúpula de riscos de gelo girando em volta de `pos` (o chão sob ela), que abre até `radius` m e some.
static func roar(root: Node, pos: Vector3, radius: float) -> void:
	if root == null or not root.is_inside_tree():
		return
	var fx := Timed.new()
	fx.life = 1.1
	root.add_child(fx)
	fx.global_position = pos + Vector3.UP * radius * 0.45
	var orb := ShadowOrbFX.new()
	orb.radius = 1.0
	orb.color = CORE
	fx.add_child(orb)
	for n in orb.get_children():   # os riscos escuros da esfera viram gelo azul, sem o miolo fechado
		if n is MeshInstance3D:
			n.set_instance_shader_parameter("dark", _v(MID) * 0.8)
			n.set_instance_shader_parameter("core", 0.0)
	frost_patch(root, pos, radius * 1.3, 2.4)
	_flash(fx, Vector3.ZERO, CORE.lerp(MID, 0.4), radius * 1.6, 0.1, 0.25)
	fx.step = func(t: float) -> void:
		var k := 1.0 - pow(1.0 - clampf(t / 0.45, 0.0, 1.0), 3.0)
		orb.scale = Vector3.ONE * lerpf(0.3, radius * 0.6, k)
		orb.intensity = 0.85 * (1.0 - clampf((t - 0.45) / 0.6, 0.0, 1.0))
	fx.step.call(0.0)


static func _flash(parent: Node3D, at: Vector3, c: Color, size: float, time: float, gain: float) -> void:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = FLARE
	mat.set_shader_parameter("flare", BURST_TEX)
	mat.render_priority = 4
	qm.material = mat
	q.mesh = qm
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	q.extra_cull_margin = size
	var rot0 := randf() * TAU
	q.set_instance_shader_parameter("col", _v(c))
	q.set_instance_shader_parameter("intensity", gain)
	q.set_instance_shader_parameter("spin", rot0)
	parent.add_child(q)
	q.position = at
	q.scale = Vector3.ONE * size * 0.35
	var tw := q.create_tween().set_parallel(true)
	tw.tween_property(q, "scale", Vector3.ONE * size, time * 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_method(func(v: float) -> void: q.set_instance_shader_parameter("intensity", v), gain, 0.0, time) \
		.set_delay(time * 0.3).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_callback(q.queue_free)


## Nó que toca `step(t)` a cada quadro e se libera em `life` s.
class Timed:
	extends Node3D

	var life := 1.0
	var step: Callable
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if _t >= life:
			queue_free()
			return
		if step.is_valid():
			step.call(_t)
