class_name BlizzardBrazier
extends Node3D
## Braseiro da luta com a Sentinela da Nevasca: tripé de ferro com fogo de verdade. Aceso, abriga da nevasca quem
## está a até BlizzardRules.BRAZIER_R m (o anel no chão mostra o abrigo enquanto a nevasca sopra). O sopro dela o
## apaga (gelo sobre as brasas) e ele reacende sozinho depois de BlizzardRules.RELIGHT s.
## A Sentinela cria os quatro (servidor, solo e réplica, nos mesmos pontos da sala) e manda no estado; aqui é só o
## desenho, e no servidor sem tela não há desenho nenhum.

var lit := true
var storm := false
var _flame: Node3D
var _light: OmniLight3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _embers: CPUParticles3D
var _frost: Node3D
var _t := 0.0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_t = randf() * 10.0
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.16, 0.15, 0.17)
	iron.roughness = 0.7
	# tripé: três pernas abertas, um aro e a bacia larga
	for i in 3:
		var leg := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.07
		cm.height = 1.5
		cm.radial_segments = 6
		leg.mesh = cm
		leg.material_override = iron
		var a := TAU * i / 3.0
		leg.position = Vector3(cos(a) * 0.32, 0.7, sin(a) * 0.32)
		leg.rotation = Vector3(sin(a) * 0.3, 0.0, -cos(a) * 0.3)
		add_child(leg)
	var hoop := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.3
	tor.outer_radius = 0.38
	tor.rings = 16
	tor.ring_segments = 6
	hoop.mesh = tor
	hoop.material_override = iron
	hoop.position.y = 0.75
	add_child(hoop)
	var bowl := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.78
	bm.bottom_radius = 0.36
	bm.height = 0.42
	bm.radial_segments = 10
	bowl.mesh = bm
	bowl.material_override = iron
	bowl.position.y = 1.55
	add_child(bowl)
	var rim := MeshInstance3D.new()
	var rt := TorusMesh.new()
	rt.inner_radius = 0.72
	rt.outer_radius = 0.84
	rt.rings = 20
	rt.ring_segments = 6
	rim.mesh = rt
	rim.material_override = iron
	rim.position.y = 1.76
	add_child(rim)
	# fogo: três línguas facetadas (miolo claro, corpo laranja) que tremem
	_flame = Node3D.new()
	_flame.position.y = 1.78
	add_child(_flame)
	for i in 3:
		var tongue := MeshInstance3D.new()
		var fm := CylinderMesh.new()
		fm.top_radius = 0.0
		fm.bottom_radius = 0.42 - 0.12 * i
		fm.height = 1.25 - 0.3 * i
		fm.radial_segments = 6
		fm.rings = 1
		var m := StandardMaterial3D.new()
		var col: Color = [Color(1.0, 0.42, 0.1), Color(1.0, 0.68, 0.2), Color(1.0, 0.95, 0.7)][i]
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = col
		fm.material = m
		tongue.mesh = fm
		tongue.position.y = fm.height * 0.5 - 0.05
		tongue.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flame.add_child(tongue)
	_light = OmniLight3D.new()
	_light.light_color = BlizzardFX.WARM
	_light.light_energy = 2.6
	_light.omni_range = BlizzardRules.BRAZIER_R + 5.0
	_light.position.y = 2.4
	add_child(_light)
	_embers = FX.burst_particles(Color(1.0, 0.7, 0.3), 10, 1.2, 0.07, 1.4, 1.5)
	_embers.one_shot = false
	_embers.explosiveness = 0.0
	_embers.direction = Vector3.UP
	_embers.spread = 25.0
	_embers.position.y = 2.1
	add_child(_embers)
	_embers.emitting = true
	# o abrigo no chão: aro quente do raio do abrigo (só aparece com a nevasca)
	_ring = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = BlizzardRules.BRAZIER_R - 0.14
	ring.outer_radius = BlizzardRules.BRAZIER_R
	ring.rings = 64
	ring.ring_segments = 4
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = Color(BlizzardFX.WARM, 0.0)
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = _ring_mat
	_ring.mesh = ring
	_ring.scale = Vector3(1.0, 0.04, 1.0)
	_ring.position.y = 0.06
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	# gelo sobre as brasas (apagado)
	_frost = Node3D.new()
	_frost.position.y = 1.72
	_frost.visible = false
	add_child(_frost)
	for i in 5:
		var c := MeshInstance3D.new()
		c.mesh = FXToon.crystal_mesh()
		c.set_instance_shader_parameter("col_core", BlizzardFX.FROSTBITE.core)
		c.set_instance_shader_parameter("col_mid", BlizzardFX.FROSTBITE.mid)
		c.set_instance_shader_parameter("col_edge", BlizzardFX.FROSTBITE.edge)
		var a := TAU * i / 5.0
		var h := 0.5 + 0.3 * (i % 2)
		c.position = Vector3(cos(a) * 0.3, 0.0, sin(a) * 0.3) if i > 0 else Vector3.ZERO
		c.basis = Basis(Vector3(sin(a), 0, -cos(a)), 0.45 if i > 0 else 0.0).scaled_local(Vector3(0.36, h if i > 0 else 0.95, 0.36))
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_frost.add_child(c)
	_apply(false)


## Acende ou apaga (com o efeito da troca quando `fx`).
func set_lit(on: bool, fx := true) -> void:
	if on == lit:
		return
	lit = on
	_apply(fx)


## A nevasca está soprando: mostra o abrigo no chão.
func set_storm(on: bool) -> void:
	storm = on


func _apply(fx: bool) -> void:
	if _flame == null:
		return
	_flame.visible = lit
	_embers.emitting = lit
	_frost.visible = not lit
	if not fx:
		_light.light_energy = 2.6 if lit else 0.0
		return
	var top := global_position + Vector3.UP * 1.9
	if lit:
		FXToon.fire_burst(top, 0.55)
		Sfx.play_at("fire_cast", global_position, 0.1, -6.0)
	else:
		FXToon.puff(top, 1.6, FXToon.SMOKE, {"vel": Vector3(0, 1.6, 0), "grow": 0.15, "hold": 0.25, "fade": 0.7})
		FXToon.puff(top, 1.3, BlizzardFX.RIME, {"vel": Vector3(0, 0.6, 0), "grow": 0.1, "hold": 0.1, "fade": 0.4})
		FXToon.ring_wave(global_position + Vector3.UP * 0.07, BlizzardRules.BRAZIER_R, 0.12, BlizzardFX.RIME, 0.25)
		Sfx.play_at("frost_cast", global_position, 0.1, -3.0)


func _process(delta: float) -> void:
	_t += delta
	if _flame == null:
		return
	if lit:
		var k := 1.0 + 0.1 * sin(_t * 11.0) + 0.06 * sin(_t * 23.0 + 1.0)
		_flame.scale = Vector3(1.0 + 0.05 * sin(_t * 7.0), k, 1.0 + 0.05 * sin(_t * 9.0 + 2.0))
		_flame.rotation.y = _t * 1.3
	_light.light_energy = move_toward(_light.light_energy,
		(2.6 + 0.3 * sin(_t * 9.0) + 0.15 * sin(_t * 21.0)) * (1.25 if storm else 1.0) if lit else 0.0, delta * 8.0)
	var want := (0.5 + 0.14 * sin(_t * 3.0)) if (lit and storm) else 0.0
	_ring_mat.albedo_color.a = move_toward(_ring_mat.albedo_color.a, want, delta * 1.5)
	_ring.visible = _ring_mat.albedo_color.a > 0.01
