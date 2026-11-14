class_name StaffAbilities
extends RefCounted
## Habilidades da classe cajado (mesma API de SwordAbilities). Estático: o estado vive no Player
## (ability, ability_t, ability_data). As magias antigas (fireball, frost_nova, heal) seguem em
## Player.cast(); aqui fica a ultimate, a Chuva de Meteoros.
##
## Fim da Chuva de Meteoros, de dois tipos:
## - macio (soltar a tecla, tempo esgotado, esquiva; na réplica, o evento "meteor_rain_end"):
##   _meteor_soft_end tira os meteoros já no ar de ability_data.nodes antes de end_ability(); eles terminam
##   a queda sozinhos e ferem. O céu escuro clareia num fade (tween do próprio nó).
## - duro (morte, menu/trava de entrada, troca de arma, réplica perdendo a flag): o Player chama
##   end_ability() direto, que libera ability_data.nodes; os meteoros no ar estão lá e somem sem dano.
## Cada meteoro (MeteorStrike) anima, fere e se libera no próprio _process: nada de fora (timer, lambda)
## chama um meteoro já liberado.

# ------------------------------------------------------------------ Chuva de Meteoros (ultimate, slot 4)
const METEOR_WINDUP := 0.5        ## preparo (s): cajado erguido; a esquiva não cancela
const METEOR_CHANNEL := 4.0       ## canalização máxima depois do preparo (s)
const METEOR_INTERVAL := 0.18     ## um meteoro a cada (s)
const METEOR_FALL := 0.45         ## tempo de queda de cada meteoro (s)
const METEOR_RANGE := 14.0        ## o centro da área fica a até 14 m do jogador (no plano)
const METEOR_AREA := 5.0          ## raio da área (m)
const METEOR_INNER := 0.45        ## meteoros pares caem no miolo (fração do raio): o ponto mirado apanha mais
const METEOR_HIT_RADIUS := 2.2    ## raio da explosão (m), somado ao raio do inimigo
const METEOR_VERT := 3.0          ## diferença de altura máxima entre o impacto e o inimigo (m)
const METEOR_HEIGHT := 14.0       ## a queda começa esta altura acima do impacto (m)
const METEOR_SLANT := 6.5         ## e deslocada na horizontal (m): a diagonal
const METEOR_SKY := 12.0          ## altura do céu escuro sobre a área (m)
const METEOR_LINGER := 0.1       ## o nó do meteoro fica um instante depois do impacto (s) e se libera
const METEOR_CAM_BACK := 1.2      ## a câmera recua (m) na canalização para mostrar a área
const METEOR_GROUND_MASK := 1     ## só o cenário (inimigos ficam de fora do raio do chão)
const METEOR_FIRE := Color(1.0, 0.45, 0.1)
const METEOR_HOT := Color(1.0, 0.8, 0.35)
const METEOR_EMBER := Color(1.0, 0.35, 0.05)
const METEOR_SCORCH := Color(0.06, 0.04, 0.03, 0.85)
const METEOR_RING := Color(1.0, 0.15, 0.05, 0.6)

## Recursos compartilhados (um de cada, criados uma vez e aquecidos em prewarm): material novo por
## meteoro recompilaria shader no meio da chuva (quadros de 60-90 ms).
static var _rock_mesh: ArrayMesh
static var _halo_mesh: QuadMesh
static var _sky_mesh: PlaneMesh
static var _sky_glow_mesh: PlaneMesh
static var _dark_tex: ImageTexture
static var _tail_mesh: ArrayMesh
static var _fire_mesh: QuadMesh
static var _fire_curve: Curve
static var _fire_ramp: Gradient


## Executa a habilidade `id` para `player`. Devolve true só se ela começou.
static func use(player: Node, id: String) -> bool:
	match id:
		"meteor_rain":
			var center := _meteor_center(player)
			var seed := randi() % 16777216   # cabe exato no float do Vector3 do evento
			player.begin_ability(id, {"center": center, "seed": seed})
			var to: Vector3 = center - player.global_position
			if Vector2(to.x, to.z).length() > 0.3:
				player.model.rotation.y = atan2(to.x, to.z)
			Network.send_event(id, center, Vector3(seed, 0, 0))
			_meteor_start(player)
			return true
	return false


## Um passo de física da habilidade em execução (jogador local e réplicas).
static func tick(player: Node, delta: float, _move_dir := Vector3.ZERO, _move_speed := 0.0) -> void:
	var t0: float = player.ability_t
	player.ability_t += delta
	match player.ability:
		"meteor_rain":
			_meteor_tick(player, t0, player.ability_t, delta)
		_:
			player.end_ability()


## A esquiva pode interromper a habilidade agora? No preparo não (a fúria já foi gasta).
static func can_dodge_cancel(player: Node) -> bool:
	return player.ability == "meteor_rain" and player.ability_t >= METEOR_WINDUP


## A esquiva interrompeu a habilidade (can_dodge_cancel deu true): fim macio, como soltar a tecla.
static func dodge_cancel(player: Node) -> void:
	if player.ability == "meteor_rain":
		_meteor_soft_end(player)
	else:
		player.end_ability()


## Pose da habilidade por cima da locomoção (de _animate).
static func pose(player: Node, p: Dictionary) -> void:
	match player.ability:
		"meteor_rain":
			var t: float = player.ability_t
			KnightAnim.meteor_pose(p, clampf(t / METEOR_WINDUP, 0.0, 1.0), smoothstep(METEOR_WINDUP * 0.6, METEOR_WINDUP + 0.3, t))


## Réplica: começa a habilidade de outro jogador pelo evento de rede (só visual).
static func play_remote(player: Node, kind: String, a: Vector3, b: Vector3) -> void:
	match kind:
		"meteor_rain":
			# a = centro da área; b.x = semente: os mesmos pontos de impacto do dono, sem dano
			player.begin_ability(kind, {"center": a, "seed": int(b.x)})
			_meteor_start(player)
		"meteor_rain_end":
			if player.ability == "meteor_rain":
				_meteor_soft_end(player)


## A tecla do slot foi solta: a chuva para na hora (os meteoros já no ar ainda caem e ferem). Solta no
## preparo, acaba ali mesmo sem meteoro nenhum: a fúria gasta é o preço de uma ultimate canalizada.
static func release(player: Node) -> void:
	if player.ability != "meteor_rain" or player.remote:
		return
	_meteor_soft_end(player)


## Cria malhas, materiais e texturas compartilhados (shaders prontos antes da primeira chuva).
static func prewarm() -> void:
	if Network.is_server():
		return
	_rock()
	_halo()
	_sky(false)
	_sky(true)
	_dark()
	_tail()
	_fireball_res()


## Um meteoro e um céu longe da vista: prepara os pipelines de desenho de cada malha/material (como
## FXEpic.prewarm_instances). Chamado (deferred) pelo jogador local.
static func prewarm_instances(at: Node3D) -> void:
	var root := FX._scene()
	if root == null or at == null or not is_instance_valid(at) or not at.is_inside_tree():
		return
	var p := at.global_position + Vector3(0, -220, 0)   # bem abaixo do mapa
	var holder := Node3D.new()
	root.add_child(holder)
	holder.global_position = p
	_sky_nodes(holder)
	for n in ["Dark", "Glow"]:   # visíveis (transparency 1 poderia pular o desenho e não aquecer nada)
		(holder.get_node(n) as GeometryInstance3D).transparency = 0.5
	var t := Timer.new()
	t.one_shot = true
	t.autostart = true
	t.wait_time = 0.3
	t.timeout.connect(holder.queue_free)
	holder.add_child(t)
	var m := MeteorStrike.new()
	m.start = p + Vector3.UP * 0.5
	m.target = p
	root.add_child(m)   # cai em 0,45 s: aquece também a explosão (bola de fogo, faíscas, marcas)


# ------------------------------------------------------------------ Chuva de Meteoros
## Centro da área: o ponto para onde a câmera mira (raio da câmera contra cenário e inimigos, como
## Player.aim_dir), limitado a METEOR_RANGE m do jogador no plano e baixado até o chão. Mirando no céu,
## fica a METEOR_RANGE m na direção da mira.
static func _meteor_center(player: Node) -> Vector3:
	var cam: Camera3D = player.camera
	var from := cam.global_position
	var to := from - cam.global_basis.z * 80.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4)
	q.exclude = [player.get_rid()]
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(q)
	var target: Vector3 = hit.position if not hit.is_empty() else to
	var origin: Vector3 = player.global_position
	var flat := Vector3(target.x - origin.x, 0.0, target.z - origin.z)
	if flat.length() > METEOR_RANGE:
		flat = flat.normalized() * METEOR_RANGE
	var y := origin.y if hit.is_empty() else minf(target.y, origin.y + 8.0)
	return _ground(player, origin + flat, y)


## Ponto do chão (cenário) sob `p`, procurando perto da altura `y`; sem chão, fica em `y`.
static func _ground(node: Node, p: Vector3, y: float) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, y + 10.0, p.z), Vector3(p.x, y - 20.0, p.z), METEOR_GROUND_MASK)
	var hit: Dictionary = node.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return Vector3(p.x, y, p.z)
	return hit.position


## Começo (dono e réplicas): semente, agenda dos meteoros e efeitos do preparo no mago.
static func _meteor_start(player: Node) -> void:
	var d: Dictionary = player.ability_data
	var rng := RandomNumberGenerator.new()
	rng.seed = int(d.seed)
	d.rng = rng
	d.next_t = METEOR_WINDUP
	d.meteors = []   # nós MeteorStrike (os que já caíram se liberam sozinhos)
	d.targets = []   # pontos de impacto, em ordem (a réplica com a mesma semente gera os mesmos)
	var nodes: Array = d.get_or_add("nodes", [])
	# de onde os meteoros vêm: do lado de lá da área, cruzando a vista na diagonal (sorteado pela semente)
	var away: Vector3 = d.center - player.global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.5 else player.facing()
	var turn := deg_to_rad(rng.randf_range(25.0, 50.0)) * (1.0 if rng.randf() < 0.5 else -1.0)
	d.from_dir = away.rotated(Vector3.UP, turn)
	Sfx.play_at("fire", player.global_position, 0.1, -4.0)
	if FX._scene() == null:
		return   # servidor dedicado: sem efeitos
	# luz laranja-avermelhada no alto do cajado, crescendo no preparo
	var light := OmniLight3D.new()
	light.light_color = METEOR_FIRE
	light.light_energy = 0.0
	light.omni_range = 5.0
	light.shadow_enabled = false
	player.add_child(light)
	light.position = Vector3(0, 2.4, 0)
	nodes.append(light)
	d.light = light
	# brasas subindo do chão num anel em volta do mago (o círculo de runas)
	var embers := FXEpic.stream(player, "glow", METEOR_EMBER, 30, 1.1, 0.09)
	if embers:
		embers.position = Vector3(0, 0.1, 0)
		embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		embers.emission_ring_axis = Vector3.UP
		embers.emission_ring_radius = 1.9
		embers.emission_ring_inner_radius = 1.5
		embers.emission_ring_height = 0.05
		embers.direction = Vector3.UP
		embers.spread = 10.0
		embers.initial_velocity_min = 1.2
		embers.initial_velocity_max = 2.6
		embers.gravity = Vector3(0, 0.6, 0)
		embers.tangential_accel_min = 1.5
		embers.tangential_accel_max = 3.0
		embers.scale_amount_min = 0.6
		embers.scale_amount_max = 1.3
		nodes.append(embers)
		d.embers = embers
	# gema acesa: brasas saindo da ponta do cajado
	var tip = player.look.get("tip")
	if is_instance_valid(tip):
		var gem := FXEpic.stream(tip, "glow", METEOR_HOT, 16, 0.3, 0.1)
		if gem:
			gem.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			gem.emission_sphere_radius = 0.08
			gem.direction = Vector3.UP
			gem.spread = 50.0
			gem.initial_velocity_min = 0.4
			gem.initial_velocity_max = 1.4
			gem.gravity = Vector3(0, 1.0, 0)
			nodes.append(gem)
			d.gem = gem
	# círculo de runas no chão em volta do mago
	FXEpic.ground_mark(player.global_position, Color(1.0, 0.4, 0.08, 0.8), 2.2, METEOR_WINDUP + 0.6, "ring")
	FXEpic.glow_burst(player.weapon_tip(), METEOR_HOT, 10, 1.5, 0.12, 0.4, 0.0)


static func _meteor_tick(player: Node, t0: float, t: float, delta: float) -> void:
	var d: Dictionary = player.ability_data
	var local: bool = not player.remote
	if local:
		# parado; a câmera recua para mostrar a área
		player.velocity.x = move_toward(player.velocity.x, 0.0, 40.0 * delta)
		player.velocity.z = move_toward(player.velocity.z, 0.0, 40.0 * delta)
		player.cam_back = METEOR_CAM_BACK * smoothstep(0.0, METEOR_WINDUP + 0.4, t)
	var light = d.get("light")
	if is_instance_valid(light):
		var u := clampf(t / METEOR_WINDUP, 0.0, 1.0)
		light.light_energy = (0.6 + 2.6 * u) * (0.85 + 0.15 * sin(t * 37.0) * sin(t * 13.0))
		light.global_position = player.weapon_tip() + Vector3.UP * 0.3
	var end_t := METEOR_WINDUP + METEOR_CHANNEL
	if t0 < METEOR_WINDUP and t >= METEOR_WINDUP:
		_meteor_channel_start(player, d)
	if t >= METEOR_WINDUP:
		# anel vermelho pulsando na área
		if FX._scene() != null and (t0 < METEOR_WINDUP or int((t0 - METEOR_WINDUP) / 0.6) != int((t - METEOR_WINDUP) / 0.6)):
			FXEpic.ground_mark(d.center, METEOR_RING, METEOR_AREA, 0.75, "ring")
		_sky_tick(d, t)
		while float(d.next_t) <= t and float(d.next_t) < end_t - 0.0001:
			_spawn_meteor(player, d)
			d.next_t = float(d.next_t) + METEOR_INTERVAL
	if t >= end_t - 0.0001:
		_meteor_soft_end(player)


## Fim do preparo: o céu escurece sobre a área e um jato de fogo sobe da gema.
static func _meteor_channel_start(player: Node, d: Dictionary) -> void:
	Sfx.play_at("explode", d.center, 0.1, -10.0)
	var root := FX._scene()
	if root == null:
		return
	# o círculo de brasas do preparo apaga (o orçamento de partículas vai para a chuva)
	var embers = d.get("embers")
	if is_instance_valid(embers):
		d.nodes.erase(embers)
		d.erase("embers")
		FXEpic.stop_stream(embers)
	var tip: Vector3 = player.weapon_tip()
	FXEpic.sparks(tip, Vector3.UP, METEOR_HOT, 18, 22.0, 0.45)
	FXEpic.glow_burst(tip, METEOR_FIRE, 16, 3.0, 0.16, 0.45, 2.0)
	FXEpic.flash(tip, METEOR_FIRE, 4.0, 7.0, 0.35)
	var sky := Node3D.new()
	root.add_child(sky)
	sky.global_position = d.center
	_sky_nodes(sky)
	d.nodes.append(sky)
	d.sky = sky


## Céu escuro (filhos de `sky`, que fica no chão do centro da área): duas camadas de nuvem girando em
## sentidos opostos (a de baixo com brilho de fogo), uma luz avermelhada, fumaça escura em redemoinho e a
## sombra no chão. Malhas e materiais compartilhados; o fade usa `transparency` (por instância).
static func _sky_nodes(sky: Node3D) -> void:
	var dark := MeshInstance3D.new()
	dark.name = "Dark"
	dark.mesh = _sky(false)
	dark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dark.transparency = 1.0
	sky.add_child(dark)
	dark.position = Vector3(0, METEOR_SKY, 0)
	var glow := MeshInstance3D.new()
	glow.name = "Glow"
	glow.mesh = _sky(true)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.transparency = 1.0
	sky.add_child(glow)
	glow.position = Vector3(0, METEOR_SKY - 0.6, 0)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = Color(1.0, 0.3, 0.12)
	light.light_energy = 0.0
	light.omni_range = METEOR_AREA * 3.2
	light.omni_attenuation = 0.5
	light.shadow_enabled = false
	sky.add_child(light)
	light.position = Vector3(0, 5.5, 0)
	# clarão das explosões: uma luz só por chuva, levada a cada impacto (antes: uma OmniLight nova por meteoro)
	var boom := OmniLight3D.new()
	boom.name = "Boom"
	boom.light_color = METEOR_FIRE
	boom.light_energy = 0.0
	boom.omni_range = 8.0
	boom.shadow_enabled = false
	sky.add_child(boom)
	var shadow := Decal.new()
	shadow.name = "Shadow"
	shadow.texture_albedo = _dark()
	shadow.size = Vector3(METEOR_AREA * 3.4, 6.0, METEOR_AREA * 3.4)
	shadow.modulate = Color(0.0, 0.0, 0.0, 0.0)
	shadow.upper_fade = 0.3
	shadow.lower_fade = 0.3
	shadow.cull_mask = 1   # só o cenário
	sky.add_child(shadow)
	shadow.position = Vector3(0, 1.0, 0)
	var swirl := FXEpic.stream(sky, "smoke", Color(0.09, 0.06, 0.06, 0.75), 8, 2.4, 4.5)
	if swirl:
		swirl.name = "Swirl"
		swirl.position = Vector3(0, METEOR_SKY - 1.5, 0)
		swirl.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		swirl.emission_ring_axis = Vector3.UP
		swirl.emission_ring_radius = METEOR_AREA * 1.3
		swirl.emission_ring_inner_radius = METEOR_AREA * 0.4
		swirl.emission_ring_height = 1.0
		swirl.direction = Vector3.DOWN
		swirl.spread = 20.0
		swirl.initial_velocity_min = 0.3
		swirl.initial_velocity_max = 1.0
		swirl.gravity = Vector3.ZERO
		swirl.tangential_accel_min = 2.5
		swirl.tangential_accel_max = 4.0
		swirl.radial_accel_min = -0.8
		swirl.radial_accel_max = -0.3


## Anima o céu: nuvens girando, a luz tremendo como fogo e a entrada em fade.
static func _sky_tick(d: Dictionary, t: float) -> void:
	var sky = d.get("sky")
	if not is_instance_valid(sky):
		return
	var u := clampf((t - METEOR_WINDUP) / 0.4, 0.0, 1.0)
	var dark := sky.get_node_or_null("Dark") as MeshInstance3D
	if dark:
		dark.rotation.y = t * 0.35
		dark.transparency = 1.0 - u
	var glow := sky.get_node_or_null("Glow") as MeshInstance3D
	if glow:
		glow.rotation.y = -t * 0.5
		glow.transparency = 1.0 - u * (0.75 + 0.25 * sin(t * 5.0))
	var light := sky.get_node_or_null("Light") as OmniLight3D
	if light:
		light.light_energy = u * (2.4 + 0.6 * sin(t * 23.0) * sin(t * 7.0))
	var shadow := sky.get_node_or_null("Shadow") as Decal
	if shadow:
		shadow.modulate.a = 0.72 * u


## Um meteoro (dono e réplicas, os mesmos sorteios na mesma ordem): pares no miolo da área, ímpares em toda ela.
static func _spawn_meteor(player: Node, d: Dictionary) -> void:
	var rng: RandomNumberGenerator = d.rng
	var k: int = d.targets.size()
	var r_max := METEOR_AREA * (METEOR_INNER if k % 2 == 0 else 1.0)
	var r := r_max * sqrt(rng.randf())
	var ang := rng.randf() * TAU
	var jitter := deg_to_rad(rng.randf_range(-14.0, 14.0))
	var size := rng.randf_range(0.8, 1.35)
	var c: Vector3 = d.center
	var target := _ground(player, c + Vector3(cos(ang), 0.0, sin(ang)) * r, c.y)
	var from: Vector3 = (d.from_dir as Vector3).rotated(Vector3.UP, jitter)
	var m := MeteorStrike.new()
	m.caster = player
	m.target = target
	m.start = target + from * METEOR_SLANT + Vector3.UP * METEOR_HEIGHT
	m.size = size
	m.harm = not player.remote
	var sky = d.get("sky")
	if is_instance_valid(sky):
		m.boom = sky.get_node_or_null("Boom")
	player.get_tree().current_scene.add_child(m)
	d.meteors.append(m)
	d.targets.append(target)
	d.nodes.append(m)   # fim duro: end_ability libera os que ainda estão no ar


## Fim macio (soltar, tempo, esquiva; réplica: "meteor_rain_end"): os meteoros no ar saem de "nodes"
## (end_ability não os libera: caem e ferem); o céu e as brasas somem aos poucos.
static func _meteor_soft_end(player: Node) -> void:
	var d: Dictionary = player.ability_data
	var nodes: Array = d.get("nodes", [])
	for m in d.get("meteors", []):
		if is_instance_valid(m):
			nodes.erase(m)
	var sky = d.get("sky")
	if is_instance_valid(sky):
		nodes.erase(sky)
		_sky_fade(sky)
	for key in ["embers", "gem"]:
		var p = d.get(key)
		if is_instance_valid(p):
			nodes.erase(p)
			FXEpic.stop_stream(p)
	if not player.remote:
		Network.send_event("meteor_rain_end", d.get("center", player.global_position), Vector3.ZERO)
	player.end_ability()


## O céu clareia em 0,7 s e o nó se libera (tween do próprio nó: morre junto se o nó sumir antes).
static func _sky_fade(sky: Node3D) -> void:
	var tw := sky.create_tween().set_parallel(true)
	var dark := sky.get_node_or_null("Dark")
	if dark:
		tw.tween_property(dark, "transparency", 1.0, 0.7)
	var glow := sky.get_node_or_null("Glow")
	if glow:
		tw.tween_property(glow, "transparency", 1.0, 0.5)
	var light := sky.get_node_or_null("Light")
	if light:
		tw.tween_property(light, "light_energy", 0.0, 0.6)
	var shadow := sky.get_node_or_null("Shadow")
	if shadow:
		tw.tween_property(shadow, "modulate:a", 0.0, 0.7)
	var swirl := sky.get_node_or_null("Swirl") as CPUParticles3D
	if swirl:
		swirl.emitting = false
	tw.chain().tween_callback(sky.queue_free)


## Explosão de um meteoro (só o dono): dano em METEOR_HIT_RADIUS com empurrão para fora, sem encher a fúria.
static func _meteor_damage(caster: Node, pos: Vector3) -> void:
	var dmg := (14.0 + Game.spell_power() * 1.6) * Game.damage_mult()
	var any := false
	for e in caster.get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var rel: Vector3 = e.global_position - pos
		if absf(rel.y) > METEOR_VERT:
			continue
		rel.y = 0.0
		if rel.length() > METEOR_HIT_RADIUS + e.radius:
			continue
		e.take_damage(dmg, pos, false)   # o empurrão sai do impacto (em puppet o servidor aplica)
		Game.on_damage_dealt(dmg, e.max_hp, false)   # a ultimate não recarrega a própria fúria
		any = true
	if any:
		Sfx.play_at("hit", pos, 0.15, -4.0)


## Efeitos do impacto (dono e réplicas): poucas partículas por explosão (são ~5 por segundo por chuva).
static func _meteor_impact_fx(pos: Vector3, size: float, boom: OmniLight3D = null) -> void:
	Sfx.play_at("explode", pos, 0.2, -9.0)
	if FX._scene() == null:
		return
	var up := Vector3.UP
	_fireball(pos + up * 0.9, size)
	FXEpic.sparks(pos + up * 0.2, up, METEOR_HOT, 6, 15.0, 0.45)   # estilhaços e brasas para cima
	if boom and is_instance_valid(boom) and boom.is_inside_tree():
		boom.global_position = pos + up * 1.2
		boom.light_energy = 7.0
		if boom.has_meta("tw"):   # (get_meta com padrão null ainda registra erro se a chave falta)
			var old = boom.get_meta("tw")
			if old is Tween and old.is_valid():
				old.kill()
		var tw := boom.create_tween()   # do próprio nó: morre junto com ele
		tw.tween_property(boom, "light_energy", 0.0, 0.22).set_ease(Tween.EASE_OUT)
		boom.set_meta("tw", tw)
	# uma marca só por impacto: os maiores deixam rachaduras em brasa, os outros a mancha queimada
	if size > 1.1:
		FXEpic.ground_mark(pos, Color(1.0, 0.42, 0.1, 0.9), 1.3 * size, 2.0, "crack")
	else:
		FXEpic.ground_mark(pos, METEOR_SCORCH, 1.5 * size, 2.5, "scorch")


# ------------------------------------------------------------------ recursos compartilhados
## Rocha: esfera baixa com os vértices deslocados por ruído (sempre o mesmo) e faces chapadas; emissiva.
static func _rock() -> ArrayMesh:
	if _rock_mesh != null:
		return _rock_mesh
	var sphere := SphereMesh.new()
	sphere.radius = 0.42
	sphere.height = 0.84
	sphere.radial_segments = 9
	sphere.rings = 5
	var arr := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 2.2
	for i in verts.size():
		var v := verts[i]
		verts[i] = v * (1.0 + 0.32 * noise.get_noise_3dv(v * 3.0)) * Vector3(1.0, 0.85, 1.1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in (arr[Mesh.ARRAY_INDEX] as PackedInt32Array):
		st.add_vertex(verts[i])
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.07, 0.03)
	mat.roughness = 0.9
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.32, 0.06)
	mat.emission_energy_multiplier = 3.5
	st.set_material(mat)
	_rock_mesh = st.commit()
	return _rock_mesh


## Halo de fogo em volta da rocha: billboard aditivo laranja com a textura de brilho do FXEpic.
static func _halo() -> QuadMesh:
	if _halo_mesh != null:
		return _halo_mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = FXEpic._glow_tex()
	m.albedo_color = Color(1.0, 0.33, 0.06)
	_halo_mesh = QuadMesh.new()
	_halo_mesh.size = Vector2.ONE * 2.1
	_halo_mesh.material = m
	return _halo_mesh


## Camada do céu: `glow` = false, nuvem escura (alfa); true, o brilho de fogo por baixo dela (aditivo).
static func _sky(glow: bool) -> PlaneMesh:
	if glow and _sky_glow_mesh != null:
		return _sky_glow_mesh
	if not glow and _sky_mesh != null:
		return _sky_mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = FXEpic._smoke_tex()
	if glow:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(0.85, 0.2, 0.04, 0.9)
	else:
		m.albedo_color = Color(0.07, 0.03, 0.03, 0.97)
	var p := PlaneMesh.new()
	p.size = Vector2.ONE * METEOR_AREA * (3.4 if glow else 4.8)
	p.material = m
	if glow:
		_sky_glow_mesh = p
	else:
		_sky_mesh = p
	return p


## Bola de fogo do impacto: bolas de brilho com mistura alfa (sRGB) do FXEpic, crescendo e subindo. O brilho
## aditivo (glow_burst) lava para creme sobre a grama ao sol; com mistura alfa o laranja fica saturado.
## Malha, curva e rampa compartilhadas: nenhum recurso novo por explosão.
static func _fireball(pos: Vector3, size: float) -> void:
	var root := FX._scene()
	if root == null:
		return
	_fireball_res()
	var amount := FXEpic._reserve(8)
	var p := CPUParticles3D.new()
	p.mesh = _fire_mesh
	p.amount = amount
	p.lifetime = 0.75
	p.explosiveness = 0.95
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.5 * size
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 2.0 * size
	p.initial_velocity_max = 5.5 * size
	p.damping_min = 5.0
	p.damping_max = 8.0
	p.gravity = Vector3(0, 2.5, 0)
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.scale_amount_min = 0.8 * size
	p.scale_amount_max = 1.5 * size
	p.scale_amount_curve = _fire_curve
	p.color_ramp = _fire_ramp
	FXEpic._launch(root, p, pos, amount)


static func _fireball_res() -> void:
	if _fire_mesh != null:
		return
	_fire_mesh = QuadMesh.new()
	_fire_mesh.size = Vector2.ONE * 1.8
	_fire_mesh.material = FXEpic._particle_mat(FXEpic._glow_tex(), false, true)
	_fire_curve = Curve.new()
	_fire_curve.add_point(Vector2(0, 0.55))
	_fire_curve.add_point(Vector2(0.25, 1.0))
	_fire_curve.add_point(Vector2(1, 0.35))
	_fire_ramp = Gradient.new()
	# fogo que vira um fiapo de fumaça no fim (sem emissor de fumaça à parte); acima de 1: brilho HDR sem ir ao branco
	_fire_ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.55, 0.8, 1.0])
	_fire_ramp.colors = PackedColorArray([Color(1.6, 1.35, 0.8, 1.0), Color(1.5, 0.75, 0.12, 1.0),
		Color(1.2, 0.38, 0.06, 0.75), Color(0.2, 0.15, 0.13, 0.4), Color(0.18, 0.16, 0.15, 0.0)])


## Cauda do meteoro: dois planos em cruz ao longo de +Z (de -0,4 a TAIL m), mais largos na cabeça, com a
## cor por vértice indo de amarelo quente no eixo a vermelho transparente nas bordas e na ponta. Mistura
## alfa (a cor fica saturada sobre a grama ao sol; o brilho vem do halo aditivo).
static func _tail() -> ArrayMesh:
	if _tail_mesh != null:
		return _tail_mesh
	const L := 4.2
	var fire := [   # [z, meia largura, cor do eixo]
		[-0.4, 0.42, Color(1.0, 0.85, 0.45, 0.95)],
		[0.6, 0.36, Color(1.0, 0.55, 0.12, 0.9)],
		[L * 0.55, 0.22, Color(0.95, 0.25, 0.05, 0.5)],
		[L, 0.06, Color(0.5, 0.1, 0.03, 0.0)],
	]
	# rastro de fumaça atrás do fogo, alargando (antes: um emissor de partículas por meteoro)
	var smoke := [
		[1.6, 0.25, Color(0.16, 0.12, 0.1, 0.0)],
		[3.2, 0.5, Color(0.15, 0.12, 0.1, 0.5)],
		[6.0, 0.85, Color(0.18, 0.16, 0.15, 0.3)],
		[9.0, 1.1, Color(0.22, 0.2, 0.19, 0.0)],
	]
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for strip in 4:   # fumaça primeiro (fica atrás do fogo na mesma superfície), fogo depois; dois planos em cruz cada
		var rows: Array = smoke if strip < 2 else fire
		var across := Vector3.RIGHT if strip % 2 == 0 else Vector3.UP
		var base := verts.size()
		for r in rows:
			var c: Color = r[2]
			var edge := Color(c.r, c.g * 0.6, c.b * 0.5, 0.0)
			for k in [-1.0, 0.0, 1.0]:
				verts.append(Vector3(0, 0, float(r[0])) + across * float(r[1]) * k)
				cols.append(c if k == 0.0 else edge)
		for i in rows.size() - 1:
			for k in 2:
				var a := base + i * 3 + k
				var b := a + 3
				idx.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.surface_set_material(0, mat)
	_tail_mesh = m
	return m


## Sombra suave no chão (decal): disco cheio com borda que some devagar.
static func _dark() -> ImageTexture:
	if _dark_tex == null:
		_dark_tex = FXEpic._make_tex(64, func(u: float, v: float) -> float:
			return smoothstep(1.0, 0.45, sqrt(u * u + v * v)))
	return _dark_tex


## Um meteoro: desce de `start` a `target` em METEOR_FALL (acelerando), girando, com halo de fogo, rastro
## de fita em cruz, brasas e fumaça. No impacto fere (se `harm`: o dono), explode e se libera sozinho
## METEOR_LINGER s depois. Liberado antes do impacto (end_ability: fim duro) não fere.
class MeteorStrike extends Node3D:
	var caster: Node
	var boom: OmniLight3D   ## luz de clarão da chuva (filha do céu), ou null
	var start := Vector3.ZERO
	var target := Vector3.ZERO
	var size := 1.0
	var harm := false
	var landed := false
	var _t := 0.0
	var _rock: MeshInstance3D
	var _tail: MeshInstance3D
	var _halos: Array = []
	var _spin_axis := Vector3.UP
	var _spin_rate := 8.0

	## Tempo desde o começo da queda (s).
	func age() -> float:
		return _t

	func _ready() -> void:
		top_level = true
		global_position = start
		if FX._scene() == null:
			return
		var dir := (target - start).normalized()
		_spin_axis = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5).normalized()
		_spin_rate = randf_range(6.0, 11.0)
		_rock = MeshInstance3D.new()
		_rock.mesh = StaffAbilities._rock()
		_rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_rock.scale = Vector3.ONE * size
		add_child(_rock)
		var h := MeshInstance3D.new()   # um halo só (o miolo quente vem da rocha emissiva e da cauda)
		h.mesh = StaffAbilities._halo()
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		h.scale = Vector3.ONE * size
		add_child(h)
		_halos.append(h)
		# cauda de fogo: malha fixa apontando para trás da queda (a queda é reta). Sem rastro de fita: a fita
		# refaz a malha todo quadro e, com ~40 meteoros no ar em 4 chuvas, era o maior custo de CPU
		_tail = MeshInstance3D.new()
		_tail.mesh = StaffAbilities._tail()
		_tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_tail.basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT).scaled(Vector3.ONE * size)
		add_child(_tail)

	func _process(delta: float) -> void:
		if is_queued_for_deletion():
			return   # fim duro neste quadro: não fere nem explode
		_t += delta
		if landed:
			if _t >= StaffAbilities.METEOR_FALL + StaffAbilities.METEOR_LINGER:
				queue_free()
			return
		var u := clampf(_t / StaffAbilities.METEOR_FALL, 0.0, 1.0)
		global_position = start.lerp(target, u * (0.6 + 0.4 * u))   # acelera na queda
		if _rock:
			_rock.rotate(_spin_axis, _spin_rate * delta)
		for i in _halos.size():
			(_halos[i] as Node3D).scale = Vector3.ONE * size * (0.9 + 0.15 * sin(_t * 40.0 + i * 2.0))
		if u >= 1.0:
			_land()

	func _land() -> void:
		landed = true
		global_position = target
		if _rock:
			_rock.visible = false
		if _tail:
			_tail.visible = false
		for h in _halos:
			h.visible = false
		if harm and is_instance_valid(caster) and caster.is_inside_tree():
			StaffAbilities._meteor_damage(caster, target)
			caster.add_shake(0.08)
		StaffAbilities._meteor_impact_fx(target, size, boom)
