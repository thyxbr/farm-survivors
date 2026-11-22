class_name BowMythic
extends RefCounted
## Efeitos em cena dos arcos míticos (regras e números em BowMythicRules). Chamado pelo projectile.gd:
## on_enemy_hit (a flecha acertou um inimigo, depois do dano) e on_impact (a flecha acabou: alvo, chão ou fim do voo).
## Réplicas de outros jogadores (visual_only) mostram fenda, chuva e espinheiro, mas só o dono da flecha dá dano;
## marcas solares, ricochete e flor de cura acontecem só no dono.

const PROJECTILE := preload("res://scripts/player/projectile.gd")
const R := preload("res://scripts/player/bow_mythic_rules.gd")

## Paletas desenhadas ({core, mid, edge}, como as de FXToon) e a cor das partículas de cada efeito.
const VOID := {"core": Color(0.95, 0.85, 1.0), "mid": Color(0.6, 0.3, 1.0), "edge": Color(0.16, 0.04, 0.32)}
const SUN := {"core": Color(1.0, 1.0, 0.9), "mid": Color(1.0, 0.8, 0.3), "edge": Color(0.95, 0.45, 0.1)}
const MOON := {"core": Color(1.0, 1.0, 1.0), "mid": Color(0.8, 0.86, 1.0), "edge": Color(0.42, 0.48, 0.8)}
const LEAF := {"core": Color(0.92, 1.0, 0.75), "mid": Color(0.45, 0.85, 0.3), "edge": Color(0.12, 0.36, 0.12)}
const BLOOM := {"core": Color(1.0, 0.95, 0.98), "mid": Color(1.0, 0.62, 0.8), "edge": Color(0.7, 0.24, 0.5)}

## Rastro da flecha mítica (projectile._build_arrow).
static func trail_palette(fx: String) -> Dictionary:
	match fx:
		"vortex":
			return VOID
		"solar":
			return SUN
		"dragonfire":
			return FXToon.FIRE
		"gale":
			return FXToon.WIND
		"crescent":
			return MOON
		"bramble":
			return LEAF
	return {}


static func particle_color(fx: String) -> Color:
	var pal := trail_palette(fx)
	return pal.mid if not pal.is_empty() else Color.WHITE


# ------------------------------------------------------------------ ganchos do projétil
static func on_enemy_hit(p: Node3D, e: Node) -> void:
	if p.visual_only or e == null or not is_instance_valid(e):
		return
	match p.fx:
		"solar":
			_solar_mark(p, e)
		"gale":
			FXToon.ground_gust(e.global_position, 1.4, FXToon.WIND, 0.35)
			if p.full and p.bounces > 0:
				_bounce(p, e)
	if p.fx == "bramble" and (e.dead or e.hp <= 0.0):
		spawn_flower(p, e.global_position)


static func on_impact(p: Node3D, pos: Vector3) -> void:
	if not p.full:
		return
	match p.fx:
		"vortex":
			_add(p, Rift.new(), pos)
		"dragonfire":
			_add(p, Rain.new(), pos)
		"bramble":
			_add(p, Bramble.new(), pos)


static func _add(p: Node3D, n: Node3D, pos: Vector3) -> void:
	n.set("damage", p.damage)
	n.set("visual_only", p.visual_only)
	n.set("crit", p.crit)
	var root := p.get_tree().current_scene if p.is_inside_tree() else null
	if root == null:
		return
	# a posição vai antes do add_child: o _ready do efeito já desenha e calcula em volta dela
	n.position = _ground(p, pos)
	root.add_child(n)


## Ponto do chão logo abaixo de `pos` (até 6 m), para fenda, chuva e espinheiro deitarem no terreno.
static func _ground(p: Node3D, pos: Vector3) -> Vector3:
	if not p.is_inside_tree():
		return pos
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.5, pos + Vector3.DOWN * 6.0, 1)
	var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if hit else pos


static func _enemies_near(tree: SceneTree, pos: Vector3, radius: float) -> Array:
	var out: Array = []
	for e in tree.get_nodes_in_group("enemies"):
		if not e.dead and e.global_position.distance_to(pos) <= radius + float(e.radius):
			out.append(e)
	return out


## `element`: Alvorada sagrado, Suspiro do Abismo sombra, Presa do Dragão fogo; espinheiro físico.
static func _hurt(e: Node, amount: float, from: Vector3, crit := false, slow := 0.0, stun := 0.0, pull := 0.0, element := "fisico") -> void:
	var dmg := amount * randf_range(0.9, 1.1)
	e.take_damage(dmg, from, crit, slow, stun, pull, element)
	Game.on_damage_dealt(dmg, e.max_hp)


# ------------------------------------------------------------------ Alvorada: marcas e coluna de sol
static func _solar_mark(p: Node3D, e: Node) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var res := R.add_mark(e.get_meta("solar_marks", []), now)
	e.set_meta("solar_marks", res.marks)
	var top: Vector3 = e.global_position + Vector3.UP * 1.6
	HolyFX.star(top + Vector3.UP * 0.25 * res.marks.size(), SUN, 0.35 + 0.1 * res.marks.size())
	if not res.fire:
		return
	var at: Vector3 = e.global_position
	HolyFX.seal(at, SUN, float(R.SOLAR.radius), 0.9)
	HolyFX.pillar(at, SUN, 1.1, 7.0, 0.9)
	HolyFX.sparkles(at + Vector3.UP, SUN, 24, 1.6, 4.0, 1.5, 0.35)
	FXToon.ring_wave(at, float(R.SOLAR.radius), 0.35, SUN)
	Sfx.play_at("explode", at, 0.1, -4.0)
	FXEpic.hit_stop(0.05, 0.1)
	for t in _enemies_near(p.get_tree(), at, float(R.SOLAR.radius)):
		_hurt(t, p.damage * float(R.SOLAR.dmg), at, true, 0.0, 0.0, 0.0, "sagrado")


# ------------------------------------------------------------------ Rei dos Ventos: ricochete
static func _bounce(p: Node3D, e: Node) -> void:
	var cands: Array = []
	var list: Array = []
	for o in p.get_tree().get_nodes_in_group("enemies"):
		if o != e and not o.dead:
			cands.append({"id": o.get_instance_id(), "pos": o.global_position})
			list.append(o)
	var hit: Dictionary = p.hit_ids()
	var i := R.bounce_target(e.global_position, cands, hit, float(R.GALE.range))
	if i < 0:
		return
	var t: Node3D = list[i]
	var from: Vector3 = e.global_position + Vector3.UP * 1.0
	var to: Vector3 = t.global_position + Vector3.UP * 0.9
	var b := PROJECTILE.new()
	b.kind = "arrow"
	b.fx = "gale"
	b.full = true
	b.bounces = p.bounces - 1
	b.direction = (to - from).normalized()
	b.damage = p.damage * float(R.GALE.bounce_dmg)
	b.crit = p.crit
	b.color = p.color
	b.speed = 38.0
	b.life = float(R.GALE.range) / 38.0 + 0.2
	b.no_drop = true
	b.skip_ids = hit.duplicate()
	b.skip_ids[e.get_instance_id()] = true
	p.get_tree().current_scene.add_child(b)
	b.global_position = from
	FXToon.streak(from, from + b.direction * 1.2, 0.08, FXToon.WIND, {"billboard": true, "fade": 0.25})


# ------------------------------------------------------------------ Raiz-Mãe: flor de cura
static func spawn_flower(p: Node3D, at: Vector3) -> void:
	var f := Flower.new()
	f.position = _ground(p, at)
	p.get_tree().current_scene.add_child(f)


# ================================================================== nós dos efeitos
## Fenda do Abismo: puxa por VORTEX.time s e implode (dano + atordoamento).
class Rift extends Node3D:
	var damage := 10.0
	var crit := false
	var visual_only := false
	var _t := 0.0
	var _tick := 0.0
	var _swirl: CPUParticles3D
	var _ring_t := 0.0
	var _core: Node3D
	var _light: OmniLight3D

	func _ready() -> void:
		var r := float(R.VORTEX.radius)
		FXToon.ring_wave(global_position, r, 0.4, VOID, 0.2)
		HolyFX.seal(global_position, VOID, r * 0.75, float(R.VORTEX.time) + 0.2)
		HolyFX.seal(global_position, VOID, r * 0.4, float(R.VORTEX.time) + 0.2)
		_core = Node3D.new()
		add_child(_core)
		_core.position = Vector3.UP * 1.0
		FXToon.orb(_core, VOID, 2.4)
		_swirl = FXEpic.stream(self, "glow", VOID.mid, 140, 0.9, 0.16)
		if _swirl:   # partículas nascem na borda e espiralam para o centro
			_swirl.position = Vector3.UP * 0.8
			_swirl.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
			_swirl.emission_sphere_radius = r * 0.55
			_swirl.gravity = Vector3.ZERO
			_swirl.radial_accel_min = -9.0
			_swirl.radial_accel_max = -6.0
			_swirl.tangential_accel_min = 7.0
			_swirl.tangential_accel_max = 10.0
		_light = OmniLight3D.new()
		_light.light_color = VOID.mid
		_light.light_energy = 2.5
		_light.omni_range = r
		_light.position = Vector3.UP
		add_child(_light)
		Sfx.play_at("frost_hit", global_position, 0.1, -6.0)

	func _process(delta: float) -> void:
		_t += delta
		_core.scale = Vector3.ONE * (0.7 + 0.12 * sin(_t * 9.0) + _t / float(R.VORTEX.time) * 0.6)
		_core.rotate_y(delta * 6.0)
		_ring_t -= delta
		if _ring_t <= 0.0:   # ondas que fecham para o centro: o puxão desenhado no chão
			_ring_t = 0.3
			FXToon.ring_wave(global_position, float(R.VORTEX.radius) * 0.9, 0.25, VOID, 0.3)
		_tick -= delta
		if _tick <= 0.0:
			_tick = float(R.VORTEX.tick)
			if not visual_only:
				for e in BowMythic._enemies_near(get_tree(), global_position, float(R.VORTEX.radius)):
					var d := Vector2(e.global_position.x - global_position.x, e.global_position.z - global_position.z).length()
					BowMythic._hurt(e, damage * float(R.VORTEX.tick_dmg), global_position, false, 0.0, 0.0, R.vortex_pull(d), "sombra")
		if _t >= float(R.VORTEX.time):
			_implode()

	func _implode() -> void:
		var r := float(R.VORTEX.implode_radius)
		FXToon.energy_burst(global_position + Vector3.UP * 0.8, VOID, r)
		FXToon.ring_wave(global_position, r * 1.2, 0.5, VOID, 0.1)
		HolyFX.pillar(global_position, VOID, 0.8, 5.0, 0.6)
		Sfx.play_at("explode", global_position, 0.1, -3.0)
		if not visual_only:
			FXEpic.hit_stop(0.06, 0.08)
			for e in BowMythic._enemies_near(get_tree(), global_position, r):
				BowMythic._hurt(e, damage * float(R.VORTEX.implode_dmg), global_position, crit, 0.0, float(R.VORTEX.stun), 0.0, "sombra")
		FXEpic.stop_stream(_swirl)
		set_process(false)
		var tw := create_tween()
		tw.tween_property(_light, "light_energy", 0.0, 0.3)
		tw.tween_callback(queue_free)


## Chuva de flechas de fogo da Presa do Dragão: RAIN.arrows flechas caem do alto em RAIN.time s.
class Rain extends Node3D:
	var damage := 10.0
	var crit := false
	var visual_only := false
	var _pts: Array = []
	var _t := 0.0
	var _next := 0

	func _ready() -> void:
		_pts = R.rain_points(global_position, int(R.RAIN.arrows), float(R.RAIN.radius))
		FXToon.ring_wave(global_position, float(R.RAIN.radius), 0.3, FXToon.FIRE, 0.25)
		FXToon.telegraph(global_position, float(R.RAIN.radius), float(R.RAIN.time))
		var embers := FXEpic.stream(self, "glow", FXToon.FIRE.mid, 40, 1.0, 0.09)
		if embers:
			embers.position = Vector3.UP * float(R.RAIN.height) * 0.6
			embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			embers.emission_box_extents = Vector3(float(R.RAIN.radius), 0.5, float(R.RAIN.radius))
			embers.gravity = Vector3(0, -14, 0)
			get_tree().create_timer(float(R.RAIN.time)).timeout.connect(func() -> void: FXEpic.stop_stream(embers))
		Sfx.play_at("bow_full", global_position, 0.1, -2.0)

	func _process(delta: float) -> void:
		_t += delta
		var due := int(_t / float(R.RAIN.time) * _pts.size()) + 1
		while _next < mini(due, _pts.size()):
			_drop(_pts[_next])
			_next += 1
		if _next >= _pts.size():
			set_process(false)
			get_tree().create_timer(float(R.RAIN.height) / 40.0 + 0.2).timeout.connect(queue_free)

	## Uma flecha de fogo desce sobre `at`. A flecha é só visual (árvores e telhados no caminho não roubam o
	## acerto); o dano em área sai no ponto do chão quando ela chega lá.
	func _drop(at: Vector3) -> void:
		var a := PROJECTILE.new()
		a.kind = "arrow"
		a.color = Color(1.0, 0.45, 0.12)
		a.trail = FXToon.FIRE
		a.visual_only = true
		a.no_drop = true
		var start := at + Vector3(randf_range(-0.8, 0.8), float(R.RAIN.height), randf_range(-0.8, 0.8))
		a.direction = (at - start).normalized()
		a.speed = 40.0
		var fly := start.distance_to(at) / a.speed
		a.life = fly
		a.position = start
		get_tree().current_scene.add_child(a)
		get_tree().create_timer(fly).timeout.connect(_land.bind(at))

	func _land(at: Vector3) -> void:
		FXToon.fire_burst(at, 1.0)
		FXToon.ring_wave(at, 1.4, 0.25, FXToon.FIRE, 0.12)
		if visual_only or not is_inside_tree():
			return
		for e in BowMythic._enemies_near(get_tree(), at, float(R.RAIN.splash)):
			BowMythic._hurt(e, damage * float(R.RAIN.dmg), at, crit, 0.0, 0.0, 0.0, "fogo")


## Espinheiro da Raiz-Mãe: espinhos verdes brotam em volta; dano e lentidão por BRAMBLE.time s.
class Bramble extends Node3D:
	var damage := 10.0
	var crit := false
	var visual_only := false
	var _t := 0.0
	var _tick := 0.0
	var _leaves: CPUParticles3D

	func _ready() -> void:
		var r := float(R.BRAMBLE.radius)
		FXToon.ring_wave(global_position, r, 0.35, LEAF, 0.2)
		HolyFX.seal(global_position, LEAF, r, float(R.BRAMBLE.time))
		_leaves = FXEpic.stream(self, "glow", LEAF.mid, 60, 1.4, 0.12)
		if _leaves:
			_leaves.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			_leaves.emission_sphere_radius = r * 0.8
			_leaves.gravity = Vector3(0, 0.8, 0)
		Sfx.play_at("arrow_hit", global_position, 0.1, -4.0)

	func _process(delta: float) -> void:
		_t += delta
		_tick -= delta
		if _tick <= 0.0:
			_tick = float(R.BRAMBLE.tick)
			_thorns()
			if not visual_only:
				for e in BowMythic._enemies_near(get_tree(), global_position, float(R.BRAMBLE.radius)):
					BowMythic._hurt(e, damage * float(R.BRAMBLE.tick_dmg), global_position, false, float(R.BRAMBLE.slow))
					if e.dead or e.hp <= 0.0:
						var f := Flower.new()
						f.position = e.global_position
						get_tree().current_scene.add_child(f)
		if _t >= float(R.BRAMBLE.time):
			FXEpic.stop_stream(_leaves)
			queue_free()

	func _thorns() -> void:
		var r := float(R.BRAMBLE.radius)
		for i in 11:
			var out := Vector3.BACK.rotated(Vector3.UP, TAU * (i + randf_range(-0.3, 0.3)) / 11.0)
			var foot := global_position + out * randf_range(0.3, r)
			var h := randf_range(1.0, 1.9)
			FXToon.streak(foot, foot + (Vector3.UP + out * 0.6).normalized() * h, h * 0.2, LEAF,
				{"billboard": true, "sweep": 0.06, "hold": 0.25, "fade": 0.3, "blunt": 1.0, "peak": 0.05, "lead": 0.3})


## Flor que nasce do abate da Raiz-Mãe: cura o jogador local por perto a cada segundo, por BRAMBLE.flower_time s.
class Flower extends Node3D:
	var _t := 0.0
	var _pulse := 0.0

	func _ready() -> void:
		var stem := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.02
		c.bottom_radius = 0.03
		c.height = 0.5
		c.radial_segments = 6
		stem.mesh = c
		stem.position.y = 0.25
		stem.material_override = _mat(LEAF.edge.lightened(0.2), 0.0)
		add_child(stem)
		for i in 6:
			var pe := MeshInstance3D.new()
			var s := SphereMesh.new()
			s.radius = 0.11
			s.height = 0.08
			s.radial_segments = 8
			s.rings = 4
			pe.mesh = s
			var a := TAU * i / 6.0
			pe.position = Vector3(cos(a) * 0.12, 0.52, sin(a) * 0.12)
			pe.material_override = _mat(BLOOM.mid, 0.4)
			add_child(pe)
		var heart := MeshInstance3D.new()
		var hs := SphereMesh.new()
		hs.radius = 0.06
		hs.height = 0.1
		heart.mesh = hs
		heart.position.y = 0.55
		heart.material_override = _mat(Color(1.0, 0.9, 0.4), 0.8)
		add_child(heart)
		scale = Vector3.ONE * 0.05
		create_tween().tween_property(self, "scale", Vector3.ONE * 1.7, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var motes := FXEpic.stream(self, "glow", BLOOM.mid, 16, 1.2, 0.07)
		if motes:
			motes.position.y = 0.55
			motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			motes.emission_sphere_radius = 0.25
			motes.gravity = Vector3(0, 0.7, 0)
		FXToon.heal_pulse(global_position, float(R.BRAMBLE.flower_radius))

	func _mat(col: Color, glow: float) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		if glow > 0.0:
			m.emission_enabled = true
			m.emission = col
			m.emission_energy_multiplier = glow
		return m

	func _process(delta: float) -> void:
		_t += delta
		rotate_y(delta * 0.8)
		_pulse -= delta
		if _pulse <= 0.0:
			_pulse = 1.0
			for pl in get_tree().get_nodes_in_group("player"):
				if not pl.remote and not pl.dead and pl.global_position.distance_to(global_position) <= float(R.BRAMBLE.flower_radius):
					pl.receive_heal(Game.max_hp() * float(R.BRAMBLE.flower_heal))
		if _t >= float(R.BRAMBLE.flower_time):
			set_process(false)
			var tw := create_tween()
			tw.tween_property(self, "scale", Vector3.ONE * 0.05, 0.3)
			tw.tween_callback(queue_free)
