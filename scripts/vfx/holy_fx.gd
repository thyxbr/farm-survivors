class_name HolyFX
extends RefCounted
## Efeitos de luz sagrada do healer (cetro), todos procedurais: colunas e domos de shader
## (shaders/holy_beam, holy_dome) somados às partículas de brilho do FXEpic. Nada aparece no servidor
## dedicado (FX._scene() devolve null lá).

const SH_BEAM := preload("res://shaders/holy_beam.gdshader")
const SH_DOME := preload("res://shaders/holy_dome.gdshader")
const GOLD := Color(1.0, 0.84, 0.4)
const LIFE := Color(0.45, 1.0, 0.55)          ## verde da cura
const WHITE_HOT := Color(1.0, 0.97, 0.85)


# ------------------------------------------------------------------ peças
## Coluna de luz: cilindro aberto em `pos` (base no chão) que abre num estalo e apaga em `time` s.
static func pillar(pos: Vector3, color: Color, radius := 0.6, height := 3.5, time := 0.8, intensity := 2.2) -> void:
	var root := FX._scene()
	if root == null:
		return
	var cm := CylinderMesh.new()
	cm.top_radius = radius * 0.75
	cm.bottom_radius = radius
	cm.height = height
	cm.cap_top = false
	cm.cap_bottom = false
	cm.radial_segments = 20
	cm.rings = 1
	var m := ShaderMaterial.new()
	m.shader = SH_BEAM
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("intensity", intensity)
	cm.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = pos + Vector3.UP * height * 0.5
	mi.scale = Vector3(0.25, 1.0, 0.25)
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3.ONE, time * 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(f: float) -> void: m.set_shader_parameter("fade", f), 1.0, 0.0, time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


## Domo de luz que cresce de `r0` até `radius` m e apaga.
static func dome(pos: Vector3, color: Color, radius: float, time := 0.55) -> void:
	var root := FX._scene()
	if root == null:
		return
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 32
	sm.rings = 16
	var m := ShaderMaterial.new()
	m.shader = SH_DOME
	m.set_shader_parameter("color", color)
	sm.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.4
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3(radius, radius * 0.45, radius), time * 0.7) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(f: float) -> void: m.set_shader_parameter("fade", f), 1.0, 0.0, time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


## Duas brasas de luz subindo em espiral (hélice dupla) ao redor de `pos`.
static func spiral(pos: Vector3, color: Color, radius := 0.75, height := 2.2, time := 0.9) -> void:
	var root := FX._scene()
	if root == null:
		return
	var holder := Node3D.new()
	root.add_child(holder)
	holder.global_position = pos
	var streams: Array = []
	for i in 2:
		var o := Node3D.new()
		holder.add_child(o)
		o.position = Vector3(cos(i * PI), 0.0, sin(i * PI)) * radius
		var p := FXEpic.stream(o, "glow", color, 22, 0.55, 0.09)
		if p:
			streams.append(p)
	var tw := holder.create_tween().set_parallel()
	tw.tween_property(holder, "rotation:y", TAU * 1.6, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(holder, "position:y", pos.y + height, time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(holder, "scale", Vector3(0.35, 1.0, 0.35), time).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func() -> void:
		for p in streams:
			if is_instance_valid(p):
				p.emitting = false)
	tw.chain().tween_interval(0.6)
	tw.chain().tween_callback(holder.queue_free)


# ------------------------------------------------------------------ cura
## Cura recebida em `pos` (pés do personagem): coluna verde-dourada, hélice de luz, motas subindo,
## selo no chão e clarão. `big` = Banquete do Herói.
static func heal_burst(pos: Vector3, big := false) -> void:
	if FX._scene() == null:
		return
	var tint := LIFE.lerp(GOLD, 0.2)
	pillar(pos, tint, 0.9 if big else 0.55, 5.0 if big else 3.2, 1.0 if big else 0.85, 2.0)
	spiral(pos + Vector3.UP * 0.1, LIFE, 0.85 if big else 0.7)
	FXEpic.glow_burst(pos + Vector3.UP * 0.5, LIFE, 30 if big else 22, 3.0, 0.11, 1.1, 3.5)
	FXEpic.glow_burst(pos + Vector3.UP * 1.1, GOLD, 16 if big else 10, 2.2, 0.08, 0.9, 2.5)
	FXEpic.ground_mark(pos, Color(LIFE.r, LIFE.g, LIFE.b, 0.95), 1.8 if big else 1.3, 1.4, "ring")
	FX.ring(pos + Vector3.UP * 0.08, Color(0.65, 1.0, 0.7, 0.85), 2.2 if big else 1.5, 0.45)
	FXEpic.flash(pos + Vector3.UP * 1.2, LIFE, 3.5, 5.0, 0.45)


## Esfera de luz que voa em arco de `from` até `target` (segue o alvo andando) e cura ao chegar.
## `burst` = toca heal_burst no alvo ao chegar (quem só assiste); falso = só um brilho pequeno (o
## curado já vê o próprio heal_burst, vindo de receive_heal).
static func heal_beam(from: Vector3, target: Node3D, burst := true) -> void:
	var root := FX._scene()
	if root == null or target == null or not is_instance_valid(target):
		return
	var orb := Node3D.new()
	root.add_child(orb)
	orb.global_position = from
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.15
	sm.height = 0.3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.85, 1.0, 0.85)
	sm.material = m
	mi.mesh = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	orb.add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = LIFE
	light.light_energy = 2.5
	light.omni_range = 4.0
	orb.add_child(light)
	var st := {"end": target.global_position + Vector3.UP * 1.1}
	var dist := from.distance_to(st.end)
	var dur := clampf(dist / 20.0, 0.2, 0.65)
	var lift := Vector3.UP * clampf(dist * 0.22, 0.6, 3.0)
	FXEpic.trail(orb, LIFE, 0.3, dur + 0.05, 0.3, GOLD, Color(0.85, 1.0, 0.75), 1.4)
	var p := FXEpic.stream(orb, "glow", LIFE, 18, 0.35, 0.07)
	var tw := orb.create_tween()
	tw.tween_method(func(t: float) -> void:
		if is_instance_valid(target):
			st.end = target.global_position + Vector3.UP * 1.1
		var mid: Vector3 = from.lerp(st.end, 0.5) + lift
		orb.global_position = from.lerp(mid, t).lerp(mid.lerp(st.end, t), t), 0.0, 1.0, dur) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		mi.visible = false
		light.visible = false
		if p and is_instance_valid(p):
			p.emitting = false
		if burst:
			heal_burst(st.end - Vector3.UP * 1.1)
		else:
			FXEpic.glow_burst(st.end, LIFE, 14, 3.0, 0.1, 0.5, 1.0))
	tw.tween_interval(0.5)
	tw.tween_callback(orb.queue_free)


## Mãos brilhando enquanto a Cura espera o alvo: motas verdes subindo do ponto `parent`.
static func charge_stream(parent: Node3D) -> CPUParticles3D:
	var p := FXEpic.stream(parent, "glow", LIFE, 16, 0.5, 0.07)
	if p:
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.18
		p.direction = Vector3.UP
		p.spread = 25.0
		p.initial_velocity_min = 0.4
		p.initial_velocity_max = 1.0
		p.gravity = Vector3(0, 0.8, 0)
	return p


# ------------------------------------------------------------------ dano
## Visual da Lança de Luz dentro do projétil `owner` (`vis` gira para a direção do voo, +Z à frente).
static func build_lance(vis: Node3D, owner: Node3D, life: float) -> void:
	var core := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.07
	cm.height = 1.5
	cm.radial_segments = 6
	cm.rings = 1
	var cmat := StandardMaterial3D.new()
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.albedo_color = Color(1.0, 0.93, 0.6)
	cm.material = cmat
	core.mesh = cm
	core.rotation.x = PI * 0.5      # eixo Y do cilindro vira +Z: a ponta vai à frente
	core.position.z = -0.25
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vis.add_child(core)
	# halo: cone maior, aditivo, apagando para a ponta
	var halo := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.02
	hm.bottom_radius = 0.18
	hm.height = 2.1
	hm.cap_top = false
	hm.cap_bottom = false
	hm.radial_segments = 12
	hm.rings = 1
	var mat := ShaderMaterial.new()
	mat.shader = SH_BEAM
	mat.set_shader_parameter("color", GOLD)
	mat.set_shader_parameter("intensity", 1.2)
	mat.set_shader_parameter("scroll", -2.0)
	hm.material = mat
	halo.mesh = hm
	halo.rotation.x = PI * 0.5
	halo.position.z = -0.45
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vis.add_child(halo)
	# guarda: anel dourado atrás da ponta
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.13
	tm.outer_radius = 0.19
	tm.rings = 16
	tm.ring_segments = 6
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.albedo_color = GOLD
	tm.material = rmat
	ring.mesh = tm
	ring.rotation.x = PI * 0.5
	ring.position.z = -0.05
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vis.add_child(ring)
	var light := OmniLight3D.new()
	light.light_color = GOLD
	light.light_energy = 1.8
	light.omni_range = 5.0
	owner.add_child(light)
	FXEpic.trail(owner, GOLD, 0.08, life, 0.14, Color(1.0, 0.65, 0.2), GOLD, 0.8)


## Impacto da Lança de Luz em `pos` (voando na direção `dir`).
static func lance_impact(pos: Vector3, dir: Vector3) -> void:
	if FX._scene() == null:
		return
	FXEpic.glow_burst(pos, GOLD, 24, 6.0, 0.11, 0.45, -2.0)
	FXEpic.sparks(pos, -dir, GOLD, 22, 11.0, 0.4)
	FXEpic.flash(pos, GOLD, 3.0, 6.0, 0.3)
	pillar(pos - Vector3.UP * 1.0, GOLD, 0.4, 2.8, 0.5, 2.6)
	FX.ring(pos - Vector3.UP * 0.9, Color(1.0, 0.9, 0.55, 0.85), 1.6, 0.3)


## Explosão radiante do Escudo de Luz em `pos`: domo de luz, onda dourada no chão, coluna central
## e raios de luz caindo em volta.
static func radiant_nova(pos: Vector3, radius: float) -> void:
	var root := FX._scene()
	if root == null:
		return
	dome(pos, GOLD, radius, 0.6)
	FXEpic.nova(pos + Vector3.UP * 0.3, GOLD, 70, 13.0, 0.22, 0.6)
	FX.ring(pos + Vector3.UP * 0.1, Color(1.0, 0.9, 0.5, 0.9), radius, 0.45)
	FXEpic.ground_mark(pos, Color(GOLD.r, GOLD.g, GOLD.b, 0.9), radius * 0.9, 2.0, "ring")
	pillar(pos, GOLD, 1.0, 6.0, 0.8, 1.6)
	FXEpic.glow_burst(pos + Vector3.UP, GOLD, 30, 6.0, 0.12, 0.8, 1.5)
	FXEpic.flash(pos + Vector3.UP * 1.5, GOLD, 4.0, radius * 1.4, 0.45)
	var tree := root.get_tree()
	for i in 8:
		var a := TAU * i / 8.0 + randf() * 0.3
		var at := pos + Vector3(cos(a), 0.0, sin(a)) * radius * 0.65
		tree.create_timer(0.04 * i).timeout.connect(func() -> void: pillar(at, GOLD, 0.22, 3.4, 0.5, 1.3))


## Luz caindo num inimigo atingido pela explosão radiante.
static func smite(pos: Vector3) -> void:
	if FX._scene() == null:
		return
	pillar(pos, GOLD, 0.35, 2.6, 0.45, 1.5)
	FXEpic.glow_burst(pos + Vector3.UP * 0.8, GOLD, 10, 3.0, 0.1, 0.4, 0.0)


## Banquete do Herói em `pos`: coluna dourada larga, hélice de luz e chuva de motas.
static func feast(pos: Vector3, radius: float) -> void:
	if FX._scene() == null:
		return
	pillar(pos, GOLD, 1.4, 8.0, 1.2, 2.6)
	spiral(pos, GOLD, 1.2, 3.0, 1.1)
	dome(pos, LIFE.lerp(GOLD, 0.5), radius, 0.8)
	FXEpic.glow_burst(pos + Vector3.UP * 1.5, GOLD, 50, 6.0, 0.14, 1.2, 2.0)
	FX.ring(pos + Vector3.UP * 0.1, Color(1.0, 0.9, 0.5, 0.9), radius, 0.6)
	FXEpic.ground_mark(pos, Color(GOLD.r, GOLD.g, GOLD.b, 0.9), radius * 0.8, 2.5, "ring")
	FXEpic.flash(pos + Vector3.UP * 2.0, GOLD, 7.0, radius * 1.8, 0.7)
