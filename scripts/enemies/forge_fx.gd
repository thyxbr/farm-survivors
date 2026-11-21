class_name ForgeFX
extends RefCounted
## Efeitos do Forjador Rúnico: aviso da Martelada em cone, o impacto do martelo, as labaredas do Respiro da
## Fornalha, o Escudo Rúnico (uma torre facetada de luz âmbar em volta dele, com as correntes de luz até as
## runas), a fumaça das chaminés e as fagulhas da fornalha. Só visual (o dano é do servidor/solo); nada é criado
## no servidor sem tela. Paleta dos monstros (núcleo escuro, borda carmim) com o âmbar das runas por cima.

const CONE_SHADER := preload("res://shaders/fx_cone_telegraph.gdshader")
const AMBER := Color(1.0, 0.68, 0.2)
const RUNE := {"core": Color(1.0, 0.95, 0.7), "mid": Color(1.0, 0.66, 0.18), "edge": Color(0.6, 0.12, 0.08)}

static var _cone_mesh: PlaneMesh
static var _ward_mesh: ArrayMesh
static var _spark_ramp: Gradient


static func _root() -> Node3D:
	if DisplayServer.get_name() == "headless":
		return null
	return FX._scene() as Node3D


## Aviso da Martelada: um leque no chão que sai de `origin` na direção `dir`, com `length` m e `half_deg` graus
## para cada lado; o miolo enche em `dur` s (cheio = o martelo bate) e some.
static func cone_warning(origin: Vector3, dir: Vector3, length: float, half_deg: float, dur: float) -> void:
	var root := _root()
	if root == null:
		return
	if _cone_mesh == null:
		_cone_mesh = PlaneMesh.new()
		_cone_mesh.size = Vector2(2, 2)
		var m := ShaderMaterial.new()
		m.shader = CONE_SHADER
		_cone_mesh.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = _cone_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.sorting_offset = -0.5
	mi.set_instance_shader_parameter("half", deg_to_rad(half_deg))
	mi.set_instance_shader_parameter("reveal", 0.0)
	mi.set_instance_shader_parameter("fade", 0.0)
	root.add_child(mi)
	mi.global_position = origin + Vector3.UP * 0.06
	mi.rotation.y = atan2(dir.x, dir.z)
	mi.scale = Vector3(length, 1.0, length)
	var tw := mi.create_tween()
	tw.tween_method(func(v: float) -> void: mi.set_instance_shader_parameter("reveal", v), 0.0, 1.0, maxf(0.05, dur))
	tw.tween_method(func(v: float) -> void: mi.set_instance_shader_parameter("fade", v), 0.0, 1.0, 0.15)
	tw.tween_callback(mi.queue_free)


## O martelo bate em `at`: pancada de monstro, clarão de brasa, fagulhas para a frente e tufos de fuligem correndo
## pelo cone (até `length` m, `half_deg` graus para cada lado).
static func hammer_impact(at: Vector3, origin: Vector3, dir: Vector3, length: float, half_deg: float) -> void:
	if _root() == null:
		return
	FXToon.slam(at, 3.0)
	FXToon.puff(at + Vector3.UP * 0.5, 2.6, FXToon.HELLFIRE, {"grow": 0.07, "hold": 0.06, "fade": 0.25, "sort": 0.2})
	FXToon.impact_sparks(at + Vector3.UP * 0.15, dir, 10, 70.0)
	FX.burst(at + Vector3.UP * 0.3, Color(1.0, 0.6, 0.18), 22, 7.0, 0.09, 0.7)
	FX.burst(at + Vector3.UP * 0.2, Color(0.3, 0.27, 0.25), 12, 4.0, 0.16, 0.6)
	# a onda corre pelo cone: tufos de fuligem com miolo de fogo, mais tarde quanto mais longe
	for i in 9:
		var a := deg_to_rad(randf_range(-half_deg, half_deg) * 0.9)
		var d := dir.rotated(Vector3.UP, a)
		var far := randf_range(0.35, 1.0) * length
		var pal: Dictionary = FXToon.SOOT if i % 3 else FXToon.HELLFIRE
		FXToon.puff(origin + d * far + Vector3.UP * 0.4, randf_range(1.1, 1.7), pal,
			{"vel": d * 2.4 + Vector3.UP * 0.8, "delay": far * 0.035, "grow": 0.16, "hold": 0.14, "fade": 0.5})


## Respiro da Fornalha: labaredas carmim estouram em roda de `pos` até `radius` m, com um anel escuro e fuligem.
static func vent_burst(pos: Vector3, radius: float) -> void:
	if _root() == null:
		return
	FXToon.ring_wave(pos + Vector3.UP * 0.08, radius, clampf(1.1 / radius, 0.12, 0.3), FXToon.MENACE, 0.16)
	for i in 14:
		var a := TAU * (i + randf_range(-0.3, 0.3)) / 14.0
		var d := Vector3(sin(a), 0, cos(a))
		var r0 := randf_range(0.25, 0.5) * radius
		FXToon.puff(pos + d * r0 + Vector3.UP * randf_range(0.5, 1.4), randf_range(1.3, 2.0), FXToon.HELLFIRE,
			{"vel": d * randf_range(5.0, 7.5) + Vector3.UP * 1.2, "grow": 0.1, "hold": 0.1, "fade": 0.35})
		if i % 2 == 0:
			FXToon.puff(pos + d * r0 * 1.4 + Vector3.UP * 1.0, randf_range(1.4, 2.0), FXToon.SOOT,
				{"vel": d * 3.0 + Vector3.UP * 1.6, "delay": 0.14, "grow": 0.3, "hold": 0.3, "fade": 0.7, "sort": -0.2})
	FXToon.impact_sparks(pos + Vector3.UP * 1.2, Vector3.BACK, 10, 180.0)


## A malha do escudo: prisma de seis lados aberto em cima e embaixo, com raio e altura 1 (as faces dos dois lados).
static func ward_mesh() -> ArrayMesh:
	if _ward_mesh != null:
		return _ward_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 6:
		var a0 := TAU * i / 6.0
		var a1 := TAU * (i + 1) / 6.0
		var p0 := Vector3(cos(a0), 0, sin(a0))
		var p1 := Vector3(cos(a1), 0, sin(a1))
		var q0 := p0 + Vector3.UP
		var q1 := p1 + Vector3.UP
		for v in [[p0, 0.0], [q0, 1.0], [q1, 1.0], [p0, 0.0], [q1, 1.0], [p1, 0.0]]:
			# a cor do vértice guarda a altura (alfa menor em cima) e a borda da face (r = 1 nas quinas)
			st.set_color(Color(1, 1, 1, 1.0 - 0.55 * float(v[1])))
			st.add_vertex(v[0])
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(AMBER, 0.2)
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	st.set_material(m)
	_ward_mesh = st.commit()
	return _ward_mesh


## Escudo Rúnico preso a `parent` (o chefe): torre facetada âmbar de `radius` x `height` m que gira devagar, com
## as arestas acesas e um círculo de runas no chão. Devolve o nó (null sem tela); quem chamou o solta com
## ward_drop().
static func ward(parent: Node3D, radius: float, height: float) -> Node3D:
	if _root() == null:
		return null
	var w := Node3D.new()
	parent.add_child(w)
	var shell := MeshInstance3D.new()
	shell.mesh = ward_mesh()
	shell.scale = Vector3(radius, height, radius)
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.name = "Shell"
	w.add_child(shell)
	# arestas: seis barras acesas nas quinas e o aro de baixo
	var edge := StandardMaterial3D.new()
	edge.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge.albedo_color = Color(1.0, 0.8, 0.35)
	var bar := BoxMesh.new()
	bar.size = Vector3(0.07, 1.0, 0.07)
	bar.material = edge
	for i in 6:
		var a := TAU * i / 6.0
		var b := MeshInstance3D.new()
		b.mesh = bar
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.position = Vector3(cos(a) * radius, height * 0.5, sin(a) * radius)
		b.scale.y = height
		w.add_child(b)
	w.set_meta("sigil", FXToon.rune_circle(parent.global_position, radius * 1.15, 0.3, -1.0))
	w.scale = Vector3(0.2, 0.05, 0.2)
	var tw := w.create_tween()
	tw.tween_property(w, "scale", Vector3.ONE, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	return w


## O escudo cai: estilhaça em riscos âmbar e some.
static func ward_drop(w: Node3D, at: Vector3, radius: float, height: float) -> void:
	if w == null or not is_instance_valid(w):
		return
	var sig = w.get_meta("sigil", null)
	if sig != null and is_instance_valid(sig):
		sig.release()
	w.queue_free()
	if _root() == null:
		return
	for i in 14:
		var a := TAU * i / 14.0
		var d := Vector3(cos(a), 0, sin(a))
		var p := at + d * radius * 0.9 + Vector3.UP * randf_range(0.4, height)
		FXToon.streak(p, p + d * randf_range(1.2, 2.2) + Vector3.UP * randf_range(-0.4, 0.8), randf_range(0.1, 0.16), RUNE,
			{"billboard": true, "shadow": false, "sweep": 0.08, "hold": 0.05, "fade": 0.3, "peak": 0.5})
	FXToon.ring_wave(at + Vector3.UP * 0.1, radius * 1.8, 0.2, RUNE, 0.14)
	FX.burst(at + Vector3.UP * height * 0.5, AMBER, 30, 7.0, 0.1, 0.8)


## Corrente de luz de uma runa (`from`) até o chefe (`to`): mostra de onde vem o escudo.
static func rune_link(from: Vector3, to: Vector3) -> void:
	if _root() == null:
		return
	FXToon.streak(from, to, 0.09, RUNE,
		{"billboard": true, "shadow": false, "sweep": 0.16, "hold": 0.22, "fade": 0.25, "peak": 0.6})


## A runa nasce / quebra em `pos`.
static func rune_pop(pos: Vector3, broken: bool) -> void:
	if _root() == null:
		return
	FXToon.ring_wave(pos + Vector3.UP * 0.1, 2.2 if broken else 1.6, 0.22, RUNE, 0.12)
	FX.burst(pos + Vector3.UP * 0.9, AMBER, 26 if broken else 14, 6.0 if broken else 3.5, 0.1, 0.7)
	if broken:
		FXToon.impact_sparks(pos + Vector3.UP * 0.8, Vector3.BACK, 10, 180.0)
		FXToon.puff(pos + Vector3.UP * 0.8, 1.8, FXToon.SOOT, {"vel": Vector3(0, 1.2, 0), "grow": 0.2, "hold": 0.2, "fade": 0.6})


## Baforada de uma chaminé em `pos`: fuligem que sobe (com miolo de fogo quando superaquecido).
static func stack_puff(pos: Vector3, hot: bool) -> void:
	if _root() == null:
		return
	var drift := Vector3(randf_range(-0.3, 0.3), randf_range(1.4, 2.0), randf_range(-0.3, 0.3))
	FXToon.puff(pos + Vector3.UP * 0.15, randf_range(0.7, 1.0) * (1.25 if hot else 1.0), FXToon.SOOT,
		{"vel": drift, "grow": 0.3, "hold": 0.35, "fade": 0.9, "sort": -0.2})
	if hot:
		FXToon.puff(pos + Vector3.UP * 0.1, randf_range(0.5, 0.75), FXToon.HELLFIRE,
			{"vel": drift * 1.3, "grow": 0.1, "hold": 0.08, "fade": 0.3})


## Fagulhas subindo sem parar da boca da fornalha (`parent` = o pivô das labaredas; ficam no mundo enquanto ele
## anda). Devolve o emissor (null sem tela); `hot` dobra a quantidade (set_sparks_hot).
static func sparks(parent: Node3D) -> CPUParticles3D:
	if _root() == null:
		return null
	if _spark_ramp == null:
		_spark_ramp = Gradient.new()
		_spark_ramp.set_color(0, Color(1.0, 0.9, 0.5, 1.0))
		_spark_ramp.set_color(1, Color(0.7, 0.05, 0.1, 0.0))
		_spark_ramp.add_point(0.45, Color(1.0, 0.45, 0.1, 1.0))
	var p := CPUParticles3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.07, 0.07, 0.07)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	box.material = m
	p.mesh = box
	p.amount = 18
	p.lifetime = 1.5
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.3, 0.15, 0.1)
	p.direction = Vector3(0, 1, 0.6)
	p.spread = 35.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.6
	p.gravity = Vector3(0, 1.4, 0)
	p.damping_min = 0.3
	p.damping_max = 0.8
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.color_ramp = _spark_ramp
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p
