class_name EarthquakeSkill
extends Node3D
## Terremoto Devastador (habilidade 2 da espada com escudo): a sequência visual inteira, em cena própria
## (scenes/vfx/earthquake/earthquake_skill.tscn). EarthquakeAbilities cria uma por ativação, na cena do mundo, no
## ponto à frente do herói onde a borda do escudo bate; ela se libera sozinha quando o último efeito some. Só visual:
## o dano é do EarthquakeDamage (o mesmo relógio da onda, EarthquakeRules.wave_radius), criado pelo dono no sinal
## `impacted`. Etapas:
##   CHARGE     o herói ergue o escudo: rachaduras pequenas e luminosas sob o ponto do golpe (GroundCrack pequeno),
##              energia sendo puxada (EarthquakeVFX.charge), poeira girando e pedrinhas tremendo (EarthquakeDust,
##              RockDebris.tremble) e um ronco leve na câmera. Enquanto isso o chão em volta é medido aos poucos
##              (EarthquakeGround) e as peças da onda já ficam montadas, escondidas (nada pesa no quadro do golpe)
##   impacto    no instante do contato: a explosão (GroundImpact: clarão, explosão da sheet, onda inicial, luz),
##              pedras e poeira do centro, tremor da câmera e o sinal `impacted`
##   WAVE       a onda de choque (ShockwaveRing) corre até o raio máximo; atrás dela as rachaduras abrem
##              (GroundCrack), as placas se levantam, pedaços do chão são lançados na frente da onda, a poeira e as
##              faíscas a acompanham e as explosões secundárias estouram nas pontas das fissuras quando ela chega
##   DISSIPATE  parou: cada peça some no seu ritmo (EarthquakeConfig.dissipation_time)
## `cancel()` antes do impacto desfaz a carga sem onda.

signal impacted(center: Vector3)
signal finished

const IMPACT := preload("res://scenes/vfx/earthquake/ground_impact.tscn")
const RING := preload("res://scenes/vfx/earthquake/shockwave_ring.tscn")
const CRACK := preload("res://scenes/vfx/earthquake/ground_crack.tscn")
const DEBRIS := preload("res://scenes/vfx/earthquake/rock_debris.tscn")
const DUST := preload("res://scenes/vfx/earthquake/earthquake_dust.tscn")
const VFX := preload("res://scenes/vfx/earthquake/earthquake_vfx.tscn")
const CHARGE_CRACK_REACH := 1.8
const CHARGE_RUMBLE := 0.06       ## ronco da câmera enquanto o chão acumula pressão (só perto)
const GROUND_REACH := 1.15        ## a grade de alturas cobre um pouco além do raio

enum State { CHARGE, WAVE, DISSIPATE, DONE, CANCELED }

@export var config: EarthquakeConfig

var seed_value := 0
var state := State.CHARGE
var t := 0.0
var impact_at := -1.0
var impact_center := Vector3.ZERO
var wave_r := 0.0
var ground: EarthquakeGround
var paths: Array = []
var plate_spots: Array = []
var secondary_spots: Array = []
var secondary_done := 0
var ring: ShockwaveRing
var cracks: GroundCrack
var charge_cracks: GroundCrack
var debris: RockDebris
var dust: EarthquakeDust
var vfx: EarthquakeVFX
var _bursts: Array = []           ## {at (Vector2), dist, kind}: o que estoura quando a onda chega
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if config == null:
		config = load("res://assets/vfx/earthquake/earthquake_config.tres")
	_rng.seed = seed_value * 19 + 7
	ground = EarthquakeGround.new(global_position, config.radius * GROUND_REACH)
	# os primeiros anéis já agora: os efeitos da carga ficam perto do centro
	ground.measure_step(_space(), 3)
	var R := config.radius
	paths = EarthquakeRules.crack_paths(config.crack_count, R * config.crack_length, config.crack_branching, config.crack_width, seed_value)
	plate_spots = EarthquakeRules.plate_spots(paths, config.plate_count, config.plate_size, seed_value)
	secondary_spots = EarthquakeRules.secondary_spots(paths, config.secondary_count)
	dust = DUST.instantiate()
	dust.setup(config, ground)
	add_child(dust)
	vfx = VFX.instantiate()
	vfx.setup(config, ground, seed_value)
	add_child(vfx)
	debris = DEBRIS.instantiate()
	debris.setup(config, ground, seed_value)
	add_child(debris)
	charge_cracks = CRACK.instantiate()
	charge_cracks.name = "ChargeCracks"
	charge_cracks.setup(config, ground, EarthquakeRules.crack_paths(7, CHARGE_CRACK_REACH, 0.35, 0.14, seed_value + 99))
	add_child(charge_cracks)
	var wt := config.impact_time()
	vfx.charge(wt)
	dust.charge(true)
	debris.tremble(int(18 * clampf(config.dust_intensity, 0.3, 2.0)), 2.4)
	_plan_bursts()


func _space() -> PhysicsDirectSpaceState3D:
	return get_world_3d().direct_space_state if is_inside_tree() else null


## Antes do impacto dá para desfazer (esquiva, morte, troca de arma).
func can_cancel() -> bool:
	return state == State.CHARGE


## Desfaz a carga sem onda nem dano: a energia apaga e as rachaduras pequenas e as pedrinhas somem depressa.
func cancel() -> void:
	if not can_cancel():
		return
	state = State.CANCELED
	vfx.end_charge()
	vfx.dissipate(PackedVector2Array(), 0.4)
	dust.dissipate(0.4)
	charge_cracks.dissipate(0.4)
	debris.dissipate(0.4)
	for n in [ring, cracks]:
		if is_instance_valid(n):
			n.queue_free()


func _process(delta: float) -> void:
	t += delta
	match state:
		State.CHARGE:
			if not ground.is_done():
				ground.measure_step(_space(), 1)
			if ground.is_done() and ring == null:
				_build_wave_pieces()
			var u := clampf(t / config.impact_time(), 0.0, 1.0)
			charge_cracks.set_wave(CHARGE_CRACK_REACH * u * u)
			_rumble(CHARGE_RUMBLE * u)
			if t >= config.impact_time():
				_impact()
		State.WAVE:
			var wt := t - impact_at
			wave_r = EarthquakeRules.wave_radius(wt, config.radius, config.expansion_speed)
			ring.set_wave(wave_r)
			cracks.set_wave(wave_r)
			dust.set_wave(wave_r)
			vfx.set_wave(wave_r)
			while not _bursts.is_empty() and float(_bursts[0].dist) <= wave_r:
				_burst(_bursts.pop_front())
			if wt >= config.expansion_time():
				_dissipate()
		State.DISSIPATE, State.CANCELED:
			if not _alive():
				state = State.DONE
				finished.emit()
				queue_free()


## Restam peças desta ativação na cena?
func _alive() -> bool:
	for c in get_children():
		if not c.is_queued_for_deletion():
			return true
	return false


## Monta a onda e as rachaduras grandes (escondidas até o impacto) quando a medição do chão termina.
func _build_wave_pieces() -> void:
	ring = RING.instantiate()
	ring.setup(config, ground)
	ring.visible = false
	add_child(ring)
	var flashes: Array = []
	for c in paths:
		if bool(c.main) and flashes.size() < 4:
			var pts: PackedVector2Array = c.points
			flashes.append(pts[pts.size() / 2])
	flashes.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.length() < b.length())
	cracks = CRACK.instantiate()
	cracks.setup(config, ground, paths, plate_spots, flashes, seed_value)
	add_child(cracks)


func _impact() -> void:
	ground.finish(_space())
	if ring == null:
		_build_wave_pieces()
	state = State.WAVE
	impact_at = t
	impact_center = global_position + Vector3(0.0, ground.height_at(Vector2.ZERO), 0.0)
	ring.visible = true
	var imp: GroundImpact = IMPACT.instantiate()
	imp.setup(config, ground)
	add_child(imp)
	var k := clampf(config.impact_intensity, 0.0, 3.0)
	var n := config.debris_count
	debris.burst(Vector2.ZERO, int(n * 0.3 * k), config.debris_height, 5.5, Vector2(0.18, 0.5), Vector2.ZERO, 0.55)
	debris.burst(Vector2.ZERO, int(n * 0.12 * k), config.debris_height * 1.2, 8.0, Vector2(0.05, 0.14), Vector2.ZERO, 0.8)
	debris.launch_trembling(config.debris_height * 0.5)
	dust.impact()
	vfx.impact()
	shake_local(impact_center, config)
	Sfx.play_at("slam", impact_center, 0.05, 2.0)
	Sfx.play_at("explode", impact_center, 0.1, -2.0)
	impacted.emit(impact_center)


## Pedaços do chão lançados na frente da onda, poeira saindo das fissuras e as explosões secundárias, em ordem de
## distância: estouram quando a onda chega em cada ponto.
func _plan_bursts() -> void:
	var R := config.radius
	var along := maxi(int(config.debris_count * 0.3 / 4.0), 0)
	for c in paths:
		if not bool(c.main):
			continue
		var pts: PackedVector2Array = c.points
		for j in range(2, pts.size(), 4):
			_bursts.append({"at": pts[j], "dist": pts[j].length(), "kind": "chunk"})
	# a quantidade por ponto depende de quantos pontos saíram
	var chunks := _bursts.size()
	for b in _bursts:
		b.count = maxi(1, roundi(float(along * 4) / maxf(chunks, 1)))
	for i in 10:
		var a := TAU * (float(i) + _rng.randf_range(-0.3, 0.3)) / 10.0
		var d := R * _rng.randf_range(0.35, 0.85)
		_bursts.append({"at": Vector2.from_angle(a) * d, "dist": d, "kind": "puff"})
	for p: Vector2 in secondary_spots:
		_bursts.append({"at": p, "dist": p.length(), "kind": "secondary"})
	_bursts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.dist) < float(b.dist))


func _burst(b: Dictionary) -> void:
	var at: Vector2 = b.at
	var k := clampf(config.impact_intensity, 0.0, 3.0)
	var fall := 1.0 - 0.5 * clampf(at.length() / config.radius, 0.0, 1.0)   # a onda perde força
	match String(b.kind):
		"chunk":
			debris.burst(at, int(b.count), config.debris_height * 0.55 * fall, 3.0, Vector2(0.08, 0.32) * clampf(fall + 0.3, 0.5, 1.0), at, 0.4)
		"puff":
			dust.puff(at, 1.0 + 0.6 * fall)
		"secondary":
			secondary_done += 1
			vfx.secondary(at)
			debris.burst(at, int(config.debris_count * 0.2 / maxf(config.secondary_count, 1) * k), config.debris_height * 0.8, 4.0, Vector2(0.1, 0.4), Vector2.ZERO, 0.55)
			dust.puff(at, 1.6)
			if secondary_done <= 3:
				Sfx.play_at("explode", global_position + Vector3(at.x, 0.0, at.y), 0.15, -8.0)


func _dissipate() -> void:
	state = State.DISSIPATE
	wave_r = config.radius
	var T := config.dissipation_time
	ring.set_wave(wave_r)
	ring.dissipate(T)
	cracks.dissipate(T)
	charge_cracks.dissipate(T * 0.8)
	dust.dissipate(T)
	debris.dissipate(T)
	var pts := PackedVector2Array()
	for c in paths:
		var cp: PackedVector2Array = c.points
		for j in range(1, cp.size(), 2):
			pts.append(cp[j])
	vfx.dissipate(pts, T)


## Ronco da câmera do jogador local perto do ponto (a carga): leve e crescendo.
func _rumble(amount: float) -> void:
	var lp := _local_player()
	if lp == null:
		return
	if EarthquakeRules.flat_distance(global_position, lp.global_position) < config.radius:
		lp.add_shake(amount)


## Treme a câmera do jogador local conforme a distância até o impacto (também em quem só vê o golpe de outro).
static func shake_local(center: Vector3, cfg: EarthquakeConfig) -> void:
	var lp := _local_player()
	if lp == null or cfg.shake_strength <= 0.0:
		return
	var f := 1.0 - clampf(EarthquakeRules.flat_distance(center, lp.global_position) / cfg.shake_range, 0.0, 1.0)
	if f > 0.0:
		lp.add_shake(cfg.shake_strength * clampf(cfg.impact_intensity, 0.0, 2.0) * f * f * (3.0 - 2.0 * f))


static func _local_player() -> Node3D:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return null
	var lp = tree.current_scene.get("player")
	if lp == null or not is_instance_valid(lp) or not lp.is_inside_tree() or not lp.has_method("add_shake"):
		return null
	return lp
