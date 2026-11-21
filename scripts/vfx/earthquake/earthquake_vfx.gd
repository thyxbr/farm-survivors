class_name EarthquakeVFX
extends Node3D
## Terremoto Devastador: os efeitos de energia que complementam a onda (scenes/vfx/earthquake/earthquake_vfx.tscn):
##   Charge     enquanto o herói ergue o escudo: partículas de energia azul sendo puxadas para o ponto do golpe, o
##              brilho da energia acumulada no chão (EarthquakeSheet.CHARGE, vai e volta) e uma luz que cresce
##   Sparks     faíscas azuis e brancas empurradas para fora e para cima pela frente da onda (anel de emissão no raio)
##   Rising     depois que a onda passa: fiapos de energia saindo das rachaduras e subindo devagar até apagar
##   secondary  explosões secundárias nas pontas das rachaduras (`secondary`): pedras e poeira (quadros DEBRIS da
##              sheet), faíscas e um clarão curto
## As pedras e a poeira das explosões secundárias são do RockDebris e do EarthquakeDust (o EarthquakeSkill chama).

const SHEET := preload("res://scenes/vfx/earthquake/earthquake_sheet.tscn")
const ENERGY := Color(0.35, 0.65, 1.0)
const MAX_LIGHTS := 3

var config: EarthquakeConfig
var ground: EarthquakeGround
var _charge_p: GPUParticles3D
var _charge_sheet: EarthquakeSheet
var _charge_light: OmniLight3D
var _sparks: GPUParticles3D
var _sparks_mat: ParticleProcessMaterial
var _lights := 0
var _life := INF
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func setup(cfg: EarthquakeConfig, g: EarthquakeGround, seed_v: int) -> void:
	config = cfg
	ground = g
	_rng.seed = seed_v * 5 + 9


func _ready() -> void:
	var glow := FXEpic._particle_mat(FXEpic._glow_tex(), true, true)
	var R := config.radius
	var aabb := AABB(Vector3(-R * 1.4, -3.0, -R * 1.4), Vector3(R * 2.8, 12.0, R * 2.8))
	# energia sendo puxada para o ponto do golpe
	var cm := ParticleProcessMaterial.new()
	cm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	cm.emission_ring_axis = Vector3.UP
	cm.emission_ring_radius = 2.4
	cm.emission_ring_inner_radius = 1.2
	cm.emission_ring_height = 1.6
	cm.direction = Vector3.UP
	cm.spread = 30.0
	cm.initial_velocity_min = 0.3
	cm.initial_velocity_max = 1.2
	cm.radial_velocity_min = -3.6
	cm.radial_velocity_max = -2.0
	cm.tangential_accel_min = 3.0
	cm.tangential_accel_max = 7.0
	cm.gravity = Vector3.ZERO
	cm.scale_min = 0.5
	cm.scale_max = 1.2
	cm.scale_curve = EarthquakeDust.curve([Vector2(0.0, 0.2), Vector2(0.3, 1.0), Vector2(1.0, 0.0)])
	cm.color_ramp = EarthquakeDust.ramp([Color(0.8, 0.92, 1.0, 0.0), Color(0.6, 0.85, 1.0, 1.0), Color(0.2, 0.5, 1.0, 0.0)], [0.0, 0.3, 1.0])
	_charge_p = EarthquakeDust.make_emitter("Charge", EarthquakeDust.quad(0.22, glow), 70, 0.7, cm, false)
	_charge_p.visibility_aabb = aabb
	add_child(_charge_p)
	_charge_p.position = ground.local_at(Vector2.ZERO, 0.6)
	# faíscas na frente da onda (esticadas na direção do movimento)
	_sparks_mat = ParticleProcessMaterial.new()
	_sparks_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	_sparks_mat.emission_ring_axis = Vector3.UP
	_sparks_mat.emission_ring_radius = 0.5
	_sparks_mat.emission_ring_inner_radius = 0.2
	_sparks_mat.emission_ring_height = 0.2
	_sparks_mat.direction = Vector3.UP
	_sparks_mat.spread = 35.0
	_sparks_mat.initial_velocity_min = 3.0
	_sparks_mat.initial_velocity_max = 8.0
	_sparks_mat.radial_velocity_min = 3.0
	_sparks_mat.radial_velocity_max = 9.0
	_sparks_mat.gravity = Vector3(0.0, -14.0, 0.0)
	_sparks_mat.damping_min = 0.5
	_sparks_mat.damping_max = 1.5
	_sparks_mat.particle_flag_align_y = true
	_sparks_mat.scale_min = 0.25
	_sparks_mat.scale_max = 0.7
	_sparks_mat.scale_curve = EarthquakeDust.curve([Vector2(0.0, 1.0), Vector2(1.0, 0.0)])
	_sparks_mat.color_ramp = EarthquakeDust.ramp([Color(1.0, 1.0, 1.0, 1.0), Color(0.5, 0.8, 1.0, 1.0), Color(0.1, 0.35, 1.0, 0.0)], [0.0, 0.35, 1.0])
	var spark_mesh := FXEpic._spark_mesh().duplicate() as ArrayMesh
	spark_mesh.surface_set_material(0, FXEpic._particle_mat(FXEpic._glow_tex(), true, true))
	_sparks = EarthquakeDust.make_emitter("Sparks", spark_mesh, int(220 * clampf(config.impact_intensity, 0.3, 2.0)), 0.75, _sparks_mat, false)
	_sparks.explosiveness = 0.0
	_sparks.visibility_aabb = aabb
	add_child(_sparks)
	_sparks.position = ground.local_at(Vector2.ZERO, 0.1)


## Liga a carga (antes do impacto): energia sendo puxada, o brilho no chão e a luz crescendo em `time` s.
func charge(time: float) -> void:
	_charge_p.emitting = true
	_charge_sheet = SHEET.instantiate()
	_charge_sheet.name = "ChargeSheet"
	add_child(_charge_sheet)
	_charge_sheet.place(ground.local_at(Vector2.ZERO), 1.2)
	_charge_sheet.intensity = 0.0
	_charge_sheet.play(EarthquakeSheet.CHARGE, 0.35, true)
	var tw := _charge_sheet.create_tween()
	tw.tween_property(_charge_sheet, "intensity", 1.1, time).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_charge_sheet, "scale", Vector3.ONE * 2.6, time).set_ease(Tween.EASE_IN)
	_charge_light = OmniLight3D.new()
	_charge_light.name = "ChargeLight"
	_charge_light.light_color = ENERGY
	_charge_light.omni_range = 4.0
	_charge_light.light_energy = 0.0
	_charge_light.shadow_enabled = false
	add_child(_charge_light)
	_charge_light.position = ground.local_at(Vector2.ZERO, 0.6)
	var lt := _charge_light.create_tween()
	lt.tween_property(_charge_light, "light_energy", 2.2, time).set_ease(Tween.EASE_IN)


## Cancela a carga (esquiva, morte) ou termina no impacto: tudo da carga some depressa.
func end_charge() -> void:
	if is_instance_valid(_charge_p):
		_charge_p.emitting = false
	if is_instance_valid(_charge_sheet):
		_charge_sheet.fade_out(0.12)
	if is_instance_valid(_charge_light):
		var tw := _charge_light.create_tween()
		tw.tween_property(_charge_light, "light_energy", 0.0, 0.15)
		tw.tween_callback(_charge_light.queue_free)


## O escudo bateu: começam as faíscas da frente da onda.
func impact() -> void:
	end_charge()
	_sparks.emitting = true


func set_wave(r: float) -> void:
	_sparks_mat.emission_ring_radius = maxf(r, 0.3)
	_sparks_mat.emission_ring_inner_radius = maxf(r - 0.4, 0.0)


## Explosão secundária em `at` (x, z a partir do centro).
func secondary(at: Vector2) -> void:
	var p := ground.local_at(at)
	var k := clampf(config.impact_intensity, 0.4, 2.0)
	var s: EarthquakeSheet = SHEET.instantiate()
	s.name = "Secondary"
	add_child(s)
	s.place(p, _rng.randf_range(2.6, 3.6) * k)
	s.intensity = 1.0
	s.play(Vector2i(EarthquakeSheet.DEBRIS.x, EarthquakeSheet.LIGHTNING.y), _rng.randf_range(0.8, 1.0), false, true)
	# faíscas espirrando
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.4
	m.direction = Vector3.UP
	m.spread = 60.0
	m.initial_velocity_min = 4.0
	m.initial_velocity_max = 11.0 * k
	m.gravity = Vector3(0.0, -16.0, 0.0)
	m.particle_flag_align_y = true
	m.scale_min = 0.3
	m.scale_max = 0.8
	m.scale_curve = EarthquakeDust.curve([Vector2(0.0, 1.0), Vector2(1.0, 0.0)])
	m.color_ramp = EarthquakeDust.ramp([Color(1, 1, 1, 1), Color(0.45, 0.75, 1.0, 1.0), Color(0.1, 0.3, 1.0, 0.0)], [0.0, 0.4, 1.0])
	var mesh := FXEpic._spark_mesh().duplicate() as ArrayMesh
	mesh.surface_set_material(0, FXEpic._particle_mat(FXEpic._glow_tex(), true, true))
	var sp := EarthquakeDust.make_emitter("SecondarySparks", mesh, int(40 * k), 0.8, m, true)
	sp.explosiveness = 0.95
	sp.visibility_aabb = AABB(Vector3(-8, -3, -8), Vector3(16, 14, 16))
	add_child(sp)
	sp.position = p + Vector3.UP * 0.2
	sp.emitting = true
	if _lights < MAX_LIGHTS:
		_lights += 1
		var l := OmniLight3D.new()
		l.light_color = ENERGY
		l.omni_range = 5.0
		l.shadow_enabled = false
		l.light_energy = 0.0
		add_child(l)
		l.position = p + Vector3.UP * 0.8
		var tw := l.create_tween()
		tw.tween_property(l, "light_energy", 3.5 * k, 0.04)
		tw.tween_property(l, "light_energy", 0.0, 0.45).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func() -> void:
			_lights -= 1
			l.queue_free())


## A onda parou: as faíscas da frente param e a energia passa a sair das rachaduras (`crack_points`, Vector2 a
## partir do centro), subindo devagar e apagando em `time` s.
func dissipate(crack_points: PackedVector2Array, time: float) -> void:
	_sparks.emitting = false
	end_charge()
	if crack_points.size() > 0:
		var n := crack_points.size()
		var img := Image.create(n, 1, false, Image.FORMAT_RGBF)
		for i in n:
			var q := ground.local_at(crack_points[i], 0.05)
			img.set_pixel(i, 0, Color(q.x, q.y, q.z))
		var m := ParticleProcessMaterial.new()
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
		m.emission_point_texture = ImageTexture.create_from_image(img)
		m.emission_point_count = n
		m.direction = Vector3.UP
		m.spread = 12.0
		m.initial_velocity_min = 0.6
		m.initial_velocity_max = 1.8
		m.gravity = Vector3(0.0, 0.4, 0.0)
		m.turbulence_enabled = true
		m.turbulence_noise_strength = 0.8
		m.turbulence_noise_scale = 3.0
		m.turbulence_influence_min = 0.05
		m.turbulence_influence_max = 0.15
		m.scale_min = 0.4
		m.scale_max = 1.0
		m.scale_curve = EarthquakeDust.curve([Vector2(0.0, 0.3), Vector2(0.3, 1.0), Vector2(1.0, 0.0)])
		m.color_ramp = EarthquakeDust.ramp([Color(0.85, 0.95, 1.0, 0.0), Color(0.5, 0.8, 1.0, 1.0), Color(0.1, 0.35, 1.0, 0.0)], [0.0, 0.25, 1.0])
		var glow := FXEpic._particle_mat(FXEpic._glow_tex(), true, true)
		var rp := EarthquakeDust.make_emitter("Rising", EarthquakeDust.quad(0.3, glow), int(90 * clampf(config.impact_intensity, 0.3, 2.0)), 1.2, m, false)
		rp.explosiveness = 0.0
		var R := config.radius
		rp.visibility_aabb = AABB(Vector3(-R * 1.3, -3.0, -R * 1.3), Vector3(R * 2.6, 10.0, R * 2.6))
		add_child(rp)
		rp.emitting = true
		# para de nascer na metade da dissipação; as que já saíram terminam de subir
		var tw := rp.create_tween()
		tw.tween_interval(time * 0.5)
		tw.tween_callback(func() -> void: rp.emitting = false)
	_life = _t + time + 0.5


func _process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		queue_free()
