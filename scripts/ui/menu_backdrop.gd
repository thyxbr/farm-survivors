extends Control
## Fundo animado do menu principal: uma batalha em equipe nas ruínas, à noite. Guerreiro, arqueira, maga e
## curandeira (as quatro classes do jogo) enfrentam goblins, esqueletos, slimes, uma aranha e morcegos.
## A batalha roda sem parar; a câmera corta entre alguns planos (SHOTS) com um fade pelo preto.
## Os atores são funções chamadas a cada quadro com o tempo da batalha (`t`) e o delta.

signal scene_changed(title: String)

const SHOT_TIME := 12.0     ## segundos de cada plano antes do corte
const FADE := 0.7           ## duração de cada metade do fade (escurece / clareia)
const TITLE := "Batalha nas Ruínas Esquecidas"
## Planos de câmera: posição e alvo no começo e no fim do plano. O menu cobre o lado esquerdo da tela,
## então os alvos ficam à esquerda da ação (a luta aparece no centro-direita).
const SHOTS := {
	"aberto": {"from": Vector3(4.5, 2.4, 9.5), "look_from": Vector3(-1.6, 1.0, 0.4),
		"to": Vector3(1.0, 2.9, 10.0), "look_to": Vector3(-2.2, 0.9, 0.2)},
	"herois": {"from": Vector3(-5.2, 2.2, 7.6), "look_from": Vector3(0.6, 1.2, 0.6),
		"to": Vector3(-4.0, 1.8, 8.4), "look_to": Vector3(1.0, 1.2, 0.4)},
	"magia": {"from": Vector3(0.2, 1.5, 6.2), "look_from": Vector3(1.6, 1.5, 0.6),
		"to": Vector3(-0.6, 1.7, 7.0), "look_to": Vector3(1.4, 1.4, 0.6)},
}
const ORDER := ["aberto", "herois", "magia"]
const M := "res://assets/models/"

# posições da batalha: heróis em +X, monstros em -X
const P_WARRIOR := Vector3(0.9, 0, 0.6)
const P_ARCHER := Vector3(3.4, 0, -1.0)
const P_MAGE := Vector3(3.0, 0, 2.1)
const P_HEALER := Vector3(4.7, 0, 0.7)
const P_GOBLIN := Vector3(-0.5, 0, 0.4)
const P_SKEL_A := Vector3(-2.2, 0, -1.3)
const P_SKEL_B := Vector3(-2.8, 0, 1.4)
const FOE_CENTER := Vector3(-2.0, 0, 0.5)

var _root: Node3D
var _set: Node3D
var _env: Environment
var _sky: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _cam: Camera3D
var _fade: ColorRect
var _actors: Array[Callable] = []
var _shot := {}
var _t := 0.0         ## tempo da batalha (não volta a zero nos cortes)
var _shot_t := 0.0    ## tempo do plano atual
var _idx := 0
var _switching := false
var _rng := RandomNumberGenerator.new()
var _soft: Texture2D   ## ponto redondo e macio para as partículas (sem ele os quads viram quadrados)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var svc := SubViewportContainer.new()
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X
	svc.add_child(vp)
	_root = Node3D.new()
	vp.add_child(_root)

	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	_sky = ProceduralSkyMaterial.new()
	sky.sky_material = _sky
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.glow_enabled = true
	_env.glow_intensity = 0.9
	_env.glow_bloom = 0.08
	_env.fog_enabled = true
	var we := WorldEnvironment.new()
	we.environment = _env
	_root.add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 40.0
	_root.add_child(_sun)
	_cam = Camera3D.new()
	_cam.fov = 46
	_root.add_child(_cam)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)

	_set = Node3D.new()
	_root.add_child(_set)
	_rng.seed = 7
	_build_battle()
	_shot = SHOTS[ORDER[0]]
	_place_camera()
	create_tween().tween_property(_fade, "color:a", 0.0, FADE * 2.0)
	scene_changed.emit.call_deferred(TITLE)


## Vai direto para o plano `shot_name` com a batalha em `at` segundos (sem fade). Para testes e capturas.
func show_scene(shot_name: String, at := 0.0) -> void:
	_idx = maxi(0, ORDER.find(shot_name))
	_shot = SHOTS[ORDER[_idx]]
	_fade.color.a = 0.0
	# avança a batalha em passos curtos, para os gatilhos (golpes, magias) acontecerem no caminho
	_t = maxf(0.0, at - 2.0)
	for i in 60:
		_step(2.0 / 60.0)
	_shot_t = SHOT_TIME * 0.5
	_place_camera()


func current_title() -> String:
	return TITLE


func _process(delta: float) -> void:
	_step(delta)
	_shot_t += delta
	_place_camera()
	if _shot_t > SHOT_TIME and not _switching:
		_next()


func _step(delta: float) -> void:
	_t += delta
	for a in _actors:
		a.call(_t, delta)


func _place_camera() -> void:
	var u := clampf(_shot_t / (SHOT_TIME + FADE), 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u) * 0.6 + u * 0.4
	_cam.position = (_shot.from as Vector3).lerp(_shot.to, u)
	_cam.look_at((_shot.look_from as Vector3).lerp(_shot.look_to, u), Vector3.UP)


func _next() -> void:
	_switching = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, FADE)
	tw.tween_callback(func() -> void:
		_idx = (_idx + 1) % ORDER.size()
		_shot = SHOTS[ORDER[_idx]]
		_shot_t = 0.0
		_place_camera())
	tw.tween_property(_fade, "color:a", 0.0, FADE)
	tw.tween_callback(func() -> void: _switching = false)


# ======================================================================== batalha

func _build_battle() -> void:
	# noite de lua cheia, céu azul-escuro; a luz quente vem dos braseiros e das magias
	_sky.sky_top_color = Color(0.03, 0.04, 0.12)
	_sky.sky_horizon_color = Color(0.16, 0.2, 0.38)
	_sky.ground_horizon_color = Color(0.16, 0.2, 0.38)
	_sky.ground_bottom_color = Color(0.02, 0.02, 0.05)
	_env.fog_light_color = Color(0.08, 0.1, 0.2)
	_env.fog_density = 0.03
	_env.ambient_light_energy = 0.6
	_sun.rotation_degrees = Vector3(-40, 160, 0)
	_sun.light_color = Color(0.6, 0.7, 1.0)
	_sun.light_energy = 0.9

	_ground(Color(0.15, 0.21, 0.13), 34)
	_disc(Color(0.26, 0.25, 0.28), 6.0, Vector3(0.5, 0, 0.3))   # piso de pedra das ruínas
	_scenery()

	var warrior := _knight("m", {"weapon": "knight_blade", "armor": "royal_plate", "head": "knight_helm",
		"hands": "iron_gauntlets", "feet": "iron_greaves", "offhand": "knight_shield"}, P_WARRIOR)
	var archer := _knight("f", {"weapon": "elven_bow", "armor": "ranger_vest", "head": "ranger_hood",
		"hands": "archer_bracers", "feet": "swift_boots", "offhand": "hunter_quiver"}, P_ARCHER)
	var mage := _knight("f", {"weapon": "archmage_staff", "armor": "mage_robe", "head": "wizard_hat",
		"hands": "spellweaver_gloves", "feet": "leather_boots"}, P_MAGE)
	var healer := _knight("m", {"weapon": "sc_seraph_scepter", "armor": "astral_plate", "head": "",
		"hands": "astral_gauntlets", "feet": "astral_greaves"}, P_HEALER)

	var goblin := _foe("goblin", P_GOBLIN, 1.6)
	EnemyGear.apply(goblin, ["Club"])
	if ToonLook.enabled():
		ToonLook.apply(goblin)
	var goblin2 := _foe("goblin", Vector3(-1.7, 0, 2.6), 1.5)
	EnemyGear.apply(goblin2, ["Club"])
	if ToonLook.enabled():
		ToonLook.apply(goblin2)
	var skel_a := _foe("skeleton", P_SKEL_A, 1.0)
	var skel_b := _foe("skeleton", P_SKEL_B, 1.0)
	var spider := _foe("spider", Vector3(-3.9, 0, -0.2), 1.0)
	for p in [Vector3(-0.2, 0, 2.5), Vector3(-3.6, 0, 2.4)]:
		var s := _foe("slime", p, 0.9, false)
		if ToonLook.enabled():
			ToonLook.apply_slime(s)
			ToonLook.apply(s)
		_hopper(s, _rng.randf_range(0.9, 1.3), 0.3, Vector3(0.12, 0, -0.05))

	_face(warrior.root, P_GOBLIN)
	_face(goblin, P_WARRIOR)
	for h in [archer, mage, healer]:
		_face(h.root, FOE_CENTER)
	_face(archer.root, P_SKEL_A)
	_face(mage.root, P_SKEL_B)
	_face(healer.root, P_WARRIOR + Vector3(-1.5, 0, 0))

	_warrior_actor(warrior, goblin)
	_archer_actor(archer, skel_a)
	_mage_actor(mage, skel_b)
	_healer_actor(healer)
	_sway(goblin2, 2.1, 0.08)
	_sway(skel_a, 1.4, 0.06)
	_sway(skel_b, 1.2, 0.06)
	_sway(spider, 3.0, 0.04)
	_bats(4)
	_set.add_child(_fireflies(Vector3(0, 1.6, 0), Vector3(9, 1.5, 7), Color(0.55, 0.75, 1.0), 40))


func _scenery() -> void:
	# colunas e muros quebrados atrás da luta, braseiros acesos dos dois lados
	for i in 6:
		var ang := -PI * 0.55 + i * PI * 0.22
		var p := _model("ruin_pillar", Vector3(sin(ang) * 7.0, 0, -cos(ang) * 7.0 - 1.0), _rng.randf() * TAU,
			_rng.randf_range(1.0, 1.35))
		if i == 1 or i == 4:
			p.rotation.z = 0.3
	_model("ruin_wall", Vector3(-4.5, 0, -6.5), 0.3)
	_model("ruin_wall", Vector3(4.0, 0, -7.0), -0.35)
	_model("ruin_wall", Vector3(-8.0, 0, -2.0), 1.3)
	for i in 10:
		var ang := _rng.randf_range(PI * 1.05, PI * 1.95)
		_model("rock" if i % 2 == 0 else "fern", Vector3(cos(ang), 0, sin(ang)) * _rng.randf_range(4.5, 8.5),
			_rng.randf() * TAU, _rng.randf_range(0.5, 1.1))
	for b: Vector3 in [Vector3(-5.5, 0, -3.0), Vector3(6.5, 0, -2.5)]:
		_model("campfire", b, 0.0, 0.8)
		var fl := _light(b + Vector3(0, 0.9, 0), Color(1, 0.55, 0.22), 2.4, 10.0)
		var ph: float = b.x
		_actors.append(func(t: float, _d: float) -> void:
			fl.light_energy = 2.4 + sin(t * 12.0 + ph) * 0.3 + sin(t * 7.1 + ph) * 0.2)
		_set.add_child(_embers(b + Vector3(0, 0.4, 0), Color(1.0, 0.55, 0.15), 24))
	var placed := 0
	while placed < 28:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(10.0, 26.0)
		var pos := Vector3(cos(a) * d, 0, sin(a) * d)
		if pos.z > 0.0 and absf(pos.x) < 14.0:
			continue   # nada entre as câmeras e a luta
		placed += 1
		_model(["tree_fir", "tree_pine", "tree_birch"][_rng.randi() % 3], pos, _rng.randf() * TAU, _rng.randf_range(1.0, 1.7))


## Guerreiro: combo de três golpes no goblin, com faíscas a cada acerto; entre um combo e outro o goblin
## ataca e bate no escudo.
func _warrior_actor(k: Dictionary, goblin: Node3D) -> void:
	const SWING := 0.5
	const IDLE := 1.4
	var sparks := _burst(Color(1.0, 0.8, 0.4), 26, 3.5)
	var base := goblin.position
	var back: Vector3 = (goblin.position - P_WARRIOR).normalized()
	var st := {"prev": 0.0}
	_actors.append(func(t: float, d: float) -> void:
		var c := fmod(t, IDLE + SWING * 3.0)
		var p := KnightAnim.idle_pose(t)
		var hit := 0.0
		var lunge := 0.0
		if c > IDLE:
			var s := c - IDLE
			var u := fmod(s, SWING) / SWING
			KnightAnim.sword_pose(p, int(s / SWING) + 1, u, 0.0)
			hit = sin(clampf((u - 0.3) / 0.7, 0.0, 1.0) * PI)
			for i in 3:
				if _crossed(st.prev, c, IDLE + SWING * (i + 0.35)):
					_fire(sparks, (P_WARRIOR + base) * 0.5 + Vector3(0, 1.2, 0))
		else:
			lunge = sin(clampf((c - 0.3) / 0.8, 0.0, 1.0) * PI)   # o goblin avança e bate
			p.body_x += lunge * 0.12   # o guerreiro se protege atrás do escudo
			p.arm_l = (p.arm_l as Vector3) + Vector3(-0.9, 0, 0) * lunge
		st.prev = c
		KnightAnim.apply(k.rig, p, clampf(d * 14.0, 0.0, 1.0))
		if c <= IDLE:
			KnightAnim.hold_weapon_upright(k.look, k.rig)
		goblin.position = base + back * (hit * 0.35 - lunge * 0.3) + Vector3.UP * absf(sin(t * 4.0)) * 0.04
		goblin.rotation.x = -hit * 0.25 + lunge * 0.2)


## Arqueira: puxa a corda, solta, a flecha atravessa a luta e acerta o esqueleto.
func _archer_actor(k: Dictionary, target: Node3D) -> void:
	const DRAW := 1.0
	const HOLD := 0.25
	const RECOVER := 0.6
	const REST := 0.7
	const FLIGHT := 0.32
	var period := DRAW + HOLD + RECOVER + REST
	var arrow := _arrow()
	var hit_fx := _burst(Color(0.75, 1.0, 0.7), 16, 2.5)
	var base := target.position
	var st := {"prev": 0.0, "kick": 0.0}
	_actors.append(func(t: float, d: float) -> void:
		var c := fmod(t + 0.4, period)
		var p := KnightAnim.idle_pose(t)
		var shot := DRAW + HOLD
		if c < shot:
			KnightAnim.bow_draw_pose(p, minf(c / DRAW, 1.0), 0.0)
		elif c < shot + RECOVER:
			KnightAnim.bow_release_pose(p, (c - shot) / RECOVER, 0.0)
		if c < shot + RECOVER:
			KnightAnim.hips_follow(p)
		KnightAnim.apply(k.rig, p, clampf(d * 14.0, 0.0, 1.0))
		KnightAnim.hold_weapon_upright(k.look, k.rig)
		KnightAnim.sway_ponytail(k.rig, d)
		KnightAnim.bow_string(k.look, k.rig)
		# flecha em voo
		var from := (k.root as Node3D).position + Vector3(0, 1.45, 0)
		var to := base + Vector3(0, 1.1, 0)
		var u := (c - shot) / FLIGHT
		arrow.visible = u >= 0.0 and u <= 1.0
		if arrow.visible:
			arrow.position = from.lerp(to, u) + Vector3.UP * sin(u * PI) * 0.15
			arrow.basis = Basis.looking_at(to - from, Vector3.UP)
		if _crossed(st.prev, c, shot + FLIGHT):
			_fire(hit_fx, to)
			st.kick = 1.0
		st.prev = c
		st.kick = maxf(0.0, st.kick - d * 3.0)
		target.position = base + (base - P_ARCHER).normalized() * st.kick * 0.25
		target.rotation.x = -st.kick * 0.3)


## Maga: conjura com o cajado, a bola de fogo voa em arco e explode no esqueleto. Runas giram aos pés dela.
func _mage_actor(k: Dictionary, target: Node3D) -> void:
	const CAST := 0.9
	const FLIGHT := 0.75
	const PERIOD := 3.2
	var ball := _projectile(Color(1.0, 0.5, 0.15), 0.22)
	var boom := _burst(Color(1.0, 0.55, 0.15), 60, 4.5)
	var boom_light := _light(Vector3.ZERO, Color(1.0, 0.5, 0.2), 0.0, 6.0)
	var gem := _light(P_MAGE + Vector3(0, 2.0, 0), Color(0.7, 0.6, 1.0), 0.0, 4.0)
	var rune := _light(P_MAGE + Vector3(0, 0.3, 0), Color(0.55, 0.45, 1.0), 1.5, 5.0)
	_set.add_child(_rune_ring(P_MAGE + Vector3(0, 0.05, 0), 1.1, Color(0.65, 0.5, 1.0)))
	var base := target.position
	var st := {"prev": 0.0, "kick": 0.0, "flash": 0.0}
	_actors.append(func(t: float, d: float) -> void:
		var c := fmod(t + 1.3, PERIOD)
		var p := KnightAnim.idle_pose(t)
		var glow := 0.0
		if c < CAST:
			KnightAnim.cast_pose(p, "fireball", c / CAST, 0.0, true)
			KnightAnim.hips_follow(p)
			glow = sin(c / CAST * PI)
		KnightAnim.apply(k.rig, p, clampf(d * 12.0, 0.0, 1.0))
		KnightAnim.hold_weapon_upright(k.look, k.rig)
		KnightAnim.sway_ponytail(k.rig, d)
		gem.light_energy = glow * 4.0
		rune.light_energy = 1.4 + glow * 2.0 + sin(t * 3.0) * 0.3
		var launch := CAST * 0.55
		var from := P_MAGE + Vector3(0, 1.9, 0) + (base - P_MAGE).normalized() * 0.5
		var to := base + Vector3(0, 1.0, 0)
		var u := (c - launch) / FLIGHT
		ball.visible = u >= 0.0 and u <= 1.0
		(ball.get_node("Trail") as CPUParticles3D).emitting = ball.visible
		if ball.visible:
			ball.position = from.lerp(to, u) + Vector3.UP * sin(u * PI) * 0.9
		if _crossed(st.prev, c, launch + FLIGHT):
			_fire(boom, to)
			boom_light.position = to
			st.kick = 1.0
			st.flash = 1.0
		st.prev = c
		st.kick = maxf(0.0, st.kick - d * 2.5)
		st.flash = maxf(0.0, st.flash - d * 3.0)
		boom_light.light_energy = st.flash * 6.0
		target.position = base + (base - P_MAGE).normalized() * st.kick * 0.4
		target.rotation.x = -st.kick * 0.4)


## Curandeira: ergue o cetro e uma coluna de luz dourada cura o guerreiro.
func _healer_actor(k: Dictionary) -> void:
	const CAST := 1.1
	const PERIOD := 4.2
	var pillar := _heal_pillar()
	pillar.position = P_WARRIOR
	var halo := _light(P_WARRIOR + Vector3(0, 1.2, 0), Color(1.0, 0.85, 0.45), 0.0, 4.0)
	var hand := _light(P_HEALER + Vector3(0, 2.0, 0), Color(1.0, 0.9, 0.6), 0.0, 3.5)
	var st := {"prev": 0.0, "glow": 0.0}
	_actors.append(func(t: float, d: float) -> void:
		var c := fmod(t + 2.6, PERIOD)
		var p := KnightAnim.idle_pose(t)
		var raise := 0.0
		if c < CAST:
			KnightAnim.cast_pose(p, "heal", c / CAST, 0.0, true)
			KnightAnim.hips_follow(p)
			raise = sin(c / CAST * PI)
		KnightAnim.apply(k.rig, p, clampf(d * 12.0, 0.0, 1.0))
		KnightAnim.hold_weapon_upright(k.look, k.rig)
		hand.light_energy = raise * 3.0
		if _crossed(st.prev, c, CAST * 0.5):
			pillar.restart()
			st.glow = 1.0
		st.prev = c
		st.glow = maxf(0.0, st.glow - d * 0.8)
		halo.light_energy = st.glow * 3.5)


## Balanço leve no lugar (monstro esperando a vez).
func _sway(n: Node3D, freq: float, amount: float) -> void:
	var base := n.position
	var ph := _rng.randf() * TAU
	_actors.append(func(t: float, _d: float) -> void:
		n.rotation.z = sin(t * freq + ph) * amount
		n.position = base + Vector3(0, absf(sin(t * freq * 2.0 + ph)) * 0.04, 0))


## Morcegos rodando por cima da luta.
func _bats(count: int) -> void:
	for i in count:
		var bat := _model("bat", Vector3.ZERO, 0.0, 0.8)
		var off := TAU * i / count
		var r := 2.5 + i * 0.7
		var spd := 0.8 + i * 0.15
		_actors.append(func(t: float, _d: float) -> void:
			var ang := t * spd + off
			bat.position = FOE_CENTER + Vector3(cos(ang) * r + 1.5, 3.0 + i * 0.4 + sin(t * 2.0 + off) * 0.3, sin(ang) * r)
			bat.rotation.y = -ang
			bat.scale = Vector3(1.0 + sin(t * 14.0 + off) * 0.25, 1.0, 1.0) * 0.8)


# ======================================================================== ajudantes

## true quando o ciclo passou pelo instante `x` neste quadro (`prev` -> `c`, com volta do ciclo).
static func _crossed(prev: float, c: float, x: float) -> bool:
	if c >= prev:
		return prev < x and c >= x
	return c >= x or prev < x   # o ciclo deu a volta


func _model(file: String, pos: Vector3, yaw := 0.0, s := 1.0, toon := true) -> Node3D:
	var n: Node3D = (load(M + file + ".glb") as PackedScene).instantiate()
	n.position = pos
	n.rotation.y = yaw
	n.scale = Vector3.ONE * s
	_set.add_child(n)
	if toon and ToonLook.enabled():
		# vegetação sem contorno (fica pesado em muita folha), como na tela de seleção
		var leafy := file.begins_with("tree") or file in ["fern", "bush"]
		ToonLook.apply(n, not leafy)
	return n


## Monstro virado para os heróis.
func _foe(file: String, pos: Vector3, s: float, toon := true) -> Node3D:
	var n := _model(file, pos, 0.0, s, toon and file != "goblin")
	_face(n, Vector3(P_HEALER.x, 0, pos.z * 0.5))
	return n


## +Z do modelo olha para `target`.
func _face(n: Node3D, target: Vector3) -> void:
	var d := target - n.position
	n.rotation.y = atan2(d.x, d.z)


func _ground(c: Color, radius: float) -> void:
	_disc(c, radius, Vector3(0, -0.05, 0), 0.1)


func _disc(c: Color, radius: float, pos: Vector3, h := 0.02) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = h
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	cm.material = m
	mi.mesh = cm
	mi.position = pos + Vector3(0, 0.005, 0) if h < 0.05 else pos
	_set.add_child(mi)


func _light(pos: Vector3, c: Color, energy: float, rng: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = c
	l.light_energy = energy
	l.omni_range = rng
	_set.add_child(l)
	return l


## Herói vestido com `look`, já parado em idle. Devolve {root, model, rig, look}.
func _knight(body: String, look: Dictionary, pos: Vector3) -> Dictionary:
	var root := Node3D.new()
	root.position = pos
	_set.add_child(root)
	var model := KnightLook.instance(body)
	root.add_child(model)
	var rig := KnightAnim.rig(model)
	var lk := KnightLook.apply(model, look)
	KnightAnim.apply(rig, KnightAnim.idle_pose(0.0), 1.0)
	return {"root": root, "model": model, "rig": rig, "look": lk}


## Pula no lugar amassando como gelatina (slime), avançando e voltando um pouco na direção `drift`.
func _hopper(n: Node3D, period: float, height: float, drift: Vector3) -> void:
	var base := n.position
	var s0 := n.scale
	_actors.append(func(t: float, _d: float) -> void:
		var u := fmod(t, period) / period
		var air := clampf((u - 0.25) / 0.6, 0.0, 1.0)
		var squash := 0.0
		if u < 0.25:
			squash = sin(u / 0.25 * PI) * 0.3
		elif u > 0.85:
			squash = sin((u - 0.85) / 0.15 * PI) * 0.25
		var stretch := sin(air * PI) * 0.15
		n.position = base + Vector3.UP * sin(air * PI) * height + drift * sin(t * 0.5) * 4.0
		n.scale = s0 * Vector3(1.0 + squash * 0.6 - stretch * 0.5, 1.0 - squash + stretch, 1.0 + squash * 0.6 - stretch * 0.5))


func _soft_dot() -> Texture2D:
	if _soft == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.add_point(0.35, Color(1, 1, 1, 0.85))
		g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 64
		gt.height = 64
		_soft = gt
	return _soft


func _glow_mat(c: Color, energy: float, billboard := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if billboard:
		m.albedo_texture = _soft_dot()
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func _quad(size: float, mat: Material) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = mat
	return q


func _fade_out() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	return g


## Explosão de faíscas (one shot). Dispara com _fire.
func _burst(c: Color, amount: int, speed: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.7
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 180
	p.gravity = Vector3(0, -4.0, 0)
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.mesh = _quad(0.16, _glow_mat(c, 5.0))
	p.color_ramp = _fade_out()
	_set.add_child(p)
	return p


func _fire(p: CPUParticles3D, pos: Vector3) -> void:
	p.position = pos
	p.restart()


## Bola de fogo: esfera brilhante, luz própria e rastro de fagulhas (nó "Trail").
func _projectile(c: Color, radius: float) -> Node3D:
	var n := Node3D.new()
	n.visible = false
	_set.add_child(n)
	for layer in [[radius * 5.0, c, 3.0], [radius * 2.4, c.lerp(Color.WHITE, 0.6), 6.0]]:
		var mi := MeshInstance3D.new()
		mi.mesh = _quad(layer[0], _glow_mat(layer[1], layer[2]))
		n.add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = 3.0
	l.omni_range = 4.0
	n.add_child(l)
	var tr := CPUParticles3D.new()
	tr.name = "Trail"
	tr.amount = 50
	tr.lifetime = 0.45
	tr.local_coords = false
	tr.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	tr.emission_sphere_radius = radius * 0.7
	tr.direction = Vector3.UP
	tr.spread = 180
	tr.gravity = Vector3(0, 1.0, 0)
	tr.initial_velocity_min = 0.1
	tr.initial_velocity_max = 0.5
	tr.scale_amount_min = 0.6
	tr.scale_amount_max = 1.5
	tr.mesh = _quad(0.3, _glow_mat(c, 4.0))
	tr.color_ramp = _fade_out()
	n.add_child(tr)
	return n


## Flecha: haste fina com ponta brilhante (olhando para -Z, como o look_at).
func _arrow() -> Node3D:
	var n := Node3D.new()
	n.visible = false
	_set.add_child(n)
	var shaft := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.03, 0.03, 0.75)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.4, 0.25)
	bm.material = m
	shaft.mesh = bm
	n.add_child(shaft)
	var tip := MeshInstance3D.new()
	var tm := SphereMesh.new()
	tm.radius = 0.05
	tm.height = 0.1
	tm.material = _glow_mat(Color(0.7, 1.0, 0.7), 5.0, false)
	tip.mesh = tm
	tip.position.z = -0.38
	n.add_child(tip)
	var trail := CPUParticles3D.new()
	trail.amount = 30
	trail.lifetime = 0.25
	trail.local_coords = false
	trail.gravity = Vector3.ZERO
	trail.initial_velocity_min = 0.0
	trail.initial_velocity_max = 0.1
	trail.mesh = _quad(0.14, _glow_mat(Color(0.7, 1.0, 0.75), 3.0))
	trail.color_ramp = _fade_out()
	n.add_child(trail)
	return n


## Coluna de luz dourada subindo em volta do aliado curado (one shot, dispara com restart()).
func _heal_pillar() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.6
	p.amount = 70
	p.lifetime = 1.4
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 0.7
	p.emission_ring_inner_radius = 0.3
	p.emission_ring_height = 0.1
	p.direction = Vector3.UP
	p.spread = 8
	p.gravity = Vector3(0, 0.8, 0)
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.8
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	p.mesh = _quad(0.18, _glow_mat(Color(1.0, 0.85, 0.4), 5.0))
	p.color_ramp = _fade_out()
	_set.add_child(p)
	return p


## Fagulhas subindo de `pos`.
func _embers(pos: Vector3, c: Color, amount: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 2.0
	p.position = pos
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.25
	p.direction = Vector3.UP
	p.spread = 18
	p.gravity = Vector3(0, 0.6, 0)
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.1
	p.mesh = _quad(0.09, _glow_mat(c, 3.0))
	p.color_ramp = _fade_out()
	return p


## Vaga-lumes: pontinhos brilhantes flutuando devagar dentro de uma caixa.
func _fireflies(center: Vector3, extents: Vector3, c: Color, amount: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 5.0
	p.preprocess = 5.0
	p.position = center
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.direction = Vector3.UP
	p.spread = 180
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.25
	p.mesh = _quad(0.12, _glow_mat(c, 4.0))
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.add_point(0.3, Color(1, 1, 1, 1))
	g.add_point(0.7, Color(1, 1, 1, 1))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	p.color_ramp = g
	return p


## Anel de runas: partículas subindo de um círculo no chão.
func _rune_ring(pos: Vector3, radius: float, c: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 50
	p.lifetime = 1.6
	p.preprocess = 2.0
	p.position = pos
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = radius
	p.emission_ring_inner_radius = radius * 0.9
	p.emission_ring_height = 0.0
	p.direction = Vector3.UP
	p.spread = 5
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.6
	p.mesh = _quad(0.12, _glow_mat(c, 4.0))
	p.color_ramp = _fade_out()
	return p
