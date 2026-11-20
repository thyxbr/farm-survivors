class_name BossFX
extends RefCounted
## Efeitos das habilidades de chefe (Mãe-Verme): aviso em anel no chão, cristais brotando em anel, pedra caindo do
## teto e bolha de ácido em arco. Só visual (o dano é do servidor/solo); nada é criado no servidor sem tela.

const CYAN := Color(0.25, 0.85, 1.0)
const RED := Color(1.0, 0.18, 0.12)
const ACID := Color(0.5, 1.0, 0.18)


static func _root() -> Node3D:
	if DisplayServer.get_name() == "headless":
		return null
	return FX._scene() as Node3D


static func _flat(color: Color, alpha: float, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if emit <= 0.0 else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.albedo_color = Color(color, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Aviso da Onda de Cristais: anel vermelho deitado no chão (raio do meio `r`, largura `w`) que fica mais forte
## até `dur` segundos (a hora em que os cristais irrompem) e some.
static func ring_warning(pos: Vector3, r: float, w: float, dur: float) -> void:
	var root := _root()
	if root == null:
		return
	var mi := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = maxf(0.05, r - w / 2.0)
	tor.outer_radius = r + w / 2.0
	tor.rings = clampi(int(r * 6.0), 24, 96)
	tor.ring_segments = 4
	var m := _flat(RED, 0.18)
	tor.material = m
	mi.mesh = tor
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = pos + Vector3.UP * 0.06
	mi.scale = Vector3(1.0, 0.04, 1.0)
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.6, maxf(0.05, dur))
	tw.tween_callback(mi.queue_free)


## Cristais irrompendo em anel de raio `r` em volta de `pos`: `n` pontas que sobem rápido, ficam e afundam.
static func crystal_ring(pos: Vector3, r: float, n: int, color := CYAN) -> void:
	var root := _root()
	if root == null:
		return
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.28
	cone.height = 1.6
	cone.radial_segments = 6
	cone.material = _flat(color, 1.0, 2.2)
	for i in n:
		var a := TAU * (i + randf_range(-0.3, 0.3)) / n
		var d := r + randf_range(-0.6, 0.6)
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		root.add_child(mi)
		mi.global_position = pos + Vector3(cos(a) * d, 0.7, sin(a) * d)
		mi.rotation = Vector3(randf_range(-0.35, 0.35), randf() * TAU, randf_range(-0.35, 0.35))
		mi.scale = Vector3(1.0, 0.05, 1.0) * randf_range(0.8, 1.25)
		var full := mi.scale * Vector3(1.0, 20.0, 1.0)
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", full, 0.12).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.45)
		tw.tween_property(mi, "scale", Vector3(full.x, 0.02, full.z), 0.3).set_ease(Tween.EASE_IN)
		tw.tween_callback(mi.queue_free)
	FX.burst(pos + Vector3.UP * 0.3, color, 6, 2.0, 0.12, 0.5)


## Pedra do Desmoronamento: cai do alto até `pos` em `fall` segundos e se desfaz em poeira.
static func falling_rock(pos: Vector3, fall: float) -> void:
	var root := _root()
	if root == null:
		return
	var rock := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.75
	sm.height = 1.3
	sm.radial_segments = 7
	sm.rings = 4
	sm.material = _flat(Color(0.42, 0.39, 0.37), 1.0, 0.01)
	rock.mesh = sm
	root.add_child(rock)
	rock.global_position = pos + Vector3.UP * 14.0
	rock.rotation = Vector3(randf() * TAU, randf() * TAU, 0.0)
	var tw := rock.create_tween()
	tw.tween_property(rock, "global_position", pos + Vector3.UP * 0.5, maxf(0.05, fall)).set_ease(Tween.EASE_IN) \
		.set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func() -> void:
		FX.burst(pos + Vector3.UP * 0.4, Color(0.5, 0.45, 0.4), 14, 4.0, 0.16, 0.7)
		FXToon.ring_wave(pos + Vector3.UP * 0.07, 2.2, 0.3, FXToon.MENACE, 0.12)
		rock.queue_free())


## Bolha de ácido em arco de `from` a `to` em `dur` segundos (o impacto é tratado por quem chamou).
static func lob(from: Vector3, to: Vector3, dur: float, height := 4.0) -> void:
	var root := _root()
	if root == null:
		return
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.32
	sm.height = 0.64
	sm.radial_segments = 8
	sm.rings = 4
	sm.material = _flat(ACID, 1.0, 1.6)
	mi.mesh = sm
	root.add_child(mi)
	mi.global_position = from
	var tw := mi.create_tween()
	tw.tween_method(func(t: float) -> void: mi.global_position = ThrowRules.arc(from, to, t, height), 0.0, 1.0,
		maxf(0.05, dur))
	tw.tween_callback(mi.queue_free)
