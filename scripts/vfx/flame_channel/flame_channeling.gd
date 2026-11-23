class_name FlameChanneling
extends Node3D
## Canalização de Fogo (mago com cajado, tecla 1): o visual e a detecção do dano, em cena própria
## (scenes/vfx/flame_channel/flame_channeling.tscn). FlameChannelAbilities cria uma por ativação, na cena do mundo; ela
## segue a palma da mão esquerda do mago (a mão sem o cajado) virada para onde ele olha, vive um pouco mais que a
## habilidade (o fade-out) e se libera sozinha (queue_free).
## Nós (o -Z do nó é a direção do jato; o nó fica na palma):
##   Circle    o círculo mágico de fogo (sheet A, flame_circle.gdshader, aditivo) de pé na frente da palma: forma-se,
##             gira rápido e, no fim, toca o anel se desfazendo. Glow: halo laranja atrás dele
##   Core      chama curta e quente saindo do centro do círculo (sheet B, quadros da ignição; presa à mão)
##   Flames    a labareda: pedaços de chama da sheet B (flame_particle.gdshader, aditivo, flipbook dos quadros cheios)
##             voando `length` m, crescendo e esfriando (no mundo: viram junto com a mira com um atraso de fluido)
##   Embers    brasas com turbulência por todo o percurso
##   Smoke     fumaça escura subindo da metade para a ponta
##   HeatHaze  distorção de calor na ponta (heat_haze.gdshader, lê a tela)
##   Light     luz laranja tremendo no meio do jato
##   Hitbox    Area3D (camada dos inimigos) com um prisma convexo cobrindo o cone de dano: a fase larga; o cone exato
##             e o intervalo por inimigo são de FlameChannelRules
## Fases: preparo (`windup_time`: o braço estende, o círculo se forma, a chama da mão acende) -> canalização (a labareda
## sai, dano a cada `hit_interval` em cada inimigo dentro dela) -> `stop()` (soltar a tecla, mana, tempo, esquiva,
## morte): as partículas param de nascer (as já soltas terminam o voo), o círculo toca o anel se desfazendo e tudo some
## num Tween de `fade_time`.
## O dano é só do dono (`deal_damage`): o sinal `hit` leva os inimigos atingidos agora; nas réplicas é só o visual.

## Inimigos atingidos agora (dono): FlameChannelAbilities aplica o dano.
signal hit(targets: Array)

@export var config: FlameChannelConfig

## O mago (pés e modelo: a direção) e a mão de onde o fogo sai (ArmL_Hand). Sem mão: na frente do peito.
var caster: Node3D
var model: Node3D
var hand: Node3D
var deal_damage := false
## Só aquece os pipelines (FlameChannelAbilities.prewarm_instances): desenha cada efeito uma vez e se libera.
var warm_only := false

@onready var circle: MeshInstance3D = $Circle
@onready var glow: MeshInstance3D = $Circle/Glow
@onready var core: GPUParticles3D = $Core
@onready var flames: GPUParticles3D = $Flames
@onready var embers: GPUParticles3D = $Embers
@onready var smoke: GPUParticles3D = $Smoke
@onready var heat: MeshInstance3D = $HeatHaze
@onready var light: OmniLight3D = $Light
@onready var hitbox: Area3D = $Hitbox
@onready var hit_shape: CollisionShape3D = $Hitbox/Shape

## Tempo desde o começo (s), se ainda canaliza e quantos tiques já acertaram (testes e demonstração).
var t := 0.0
var channeling := true
var hit_count := 0
## Quanto do efeito está aceso (0..1): sobe no preparo, o Tween do fim derruba.
var level := 0.0
## Progresso do fade-out (0..1): toca os quadros do anel se desfazendo.
var fade_u := 0.0

var _spin := 0.0
var _last_hit := {}
var _tween: Tween
var _jet_on := false


func _ready() -> void:
	if config == null:
		config = load("res://assets/vfx/flame_channel/flame_channel_config.tres")
	top_level = true
	_setup()
	if warm_only:
		_warm_pipelines()
		return
	hitbox.monitoring = deal_damage
	_follow_now()
	_set_level(0.0)
	core.emitting = true   # a mão acende já no preparo
	_tween = create_tween()
	_tween.tween_property(self, "level", 1.0, config.windup_time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


## Ajusta nós e partículas à configuração (alcance, tamanhos, quantidades).
func _setup() -> void:
	var cfg := config
	var off := Vector3(0, 0, -cfg.circle_offset)
	circle.position = off
	circle.scale = Vector3.ONE * cfg.circle_size
	for p: GPUParticles3D in [core, flames, embers]:
		p.position = off
	flames.amount = cfg.jet_amount
	flames.lifetime = cfg.jet_lifetime
	embers.amount = maxi(cfg.ember_amount, 1)
	smoke.amount = maxi(cfg.smoke_amount, 1)
	var fm := flames.process_material as ParticleProcessMaterial
	var v := FlameChannelRules.jet_speed(cfg.length, cfg.jet_lifetime, (fm.damping_min + fm.damping_max) * 0.5)
	fm.initial_velocity_min = v * 0.94
	fm.initial_velocity_max = v * 1.06
	fm.scale_min = cfg.jet_scale * 0.85
	fm.scale_max = cfg.jet_scale * 1.15
	var em := embers.process_material as ParticleProcessMaterial
	em.initial_velocity_min = v * 0.6
	em.initial_velocity_max = v * 1.15
	smoke.position = Vector3(0, 0.3, -cfg.length * 0.35)
	heat.position = Vector3(0, 0.35, -cfg.length * 0.9)
	light.position = Vector3(0, 0, -cfg.length * 0.4)
	light.omni_range = cfg.length * 1.45
	# a fase larga do dano: o cone visto de cima (trapézio da palma até a ponta), esticado na altura
	var pts := PackedVector3Array()
	for z in [0.0, -cfg.length]:
		var r: float = (cfg.radius_start if z == 0.0 else cfg.radius_end) + 0.6
		for x in [-r, r]:
			for y in [-cfg.height_below - 1.6, cfg.height_above]:
				pts.append(Vector3(x, y, z + (0.6 if z == 0.0 else -0.6)))
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	hit_shape.shape = shape


func _warm_pipelines() -> void:
	set_process(false)
	set_physics_process(false)
	hitbox.monitoring = false
	_set_level(1.0)
	circle.set_instance_shader_parameter("frame_a", 30.0)
	circle.set_instance_shader_parameter("frame_b", 31.0)
	for p: GPUParticles3D in [core, flames, embers, smoke]:
		p.emitting = true
		p.restart()
	get_tree().create_timer(0.6).timeout.connect(queue_free)


func _process(delta: float) -> void:
	t += delta
	if channeling:
		_follow_now()
	var cfg := config
	# o círculo: forma-se (e cresce num estalo), depois gira rápido em laço; no fim, o anel se desfazendo
	var fr := FlameChannelRules.end_frame(fade_u, cfg.end_frames) if not channeling \
		else FlameChannelRules.circle_frame(t, cfg.form_frames, cfg.form_time, cfg.loop_frames, cfg.loop_fps)
	circle.set_instance_shader_parameter("frame_a", fr.x)
	circle.set_instance_shader_parameter("frame_b", fr.y)
	circle.set_instance_shader_parameter("frame_mix", fr.z)
	var spin_k := smoothstep(0.0, cfg.form_time + 0.2, t)
	_spin += delta * cfg.circle_spin * (0.35 + 0.65 * spin_k)
	circle.set_instance_shader_parameter("spin", _spin)
	var pop := 1.0 - pow(1.0 - clampf(t / maxf(cfg.form_time, 0.01), 0.0, 1.0), 3.0)
	circle.scale = Vector3.ONE * cfg.circle_size * lerpf(0.35, 1.0, pop) * (1.0 + 0.03 * sin(t * 31.0))
	# a labareda sai no fim do preparo
	if channeling and not _jet_on and t >= cfg.windup_time * 0.75:
		_jet_on = true
		for p: GPUParticles3D in [flames, embers, smoke]:
			p.emitting = true
	_set_level(level)


## Intensidade de tudo o que não é partícula (círculo, halo, luz, calor) para `k` 0..1.
func _set_level(k: float) -> void:
	var cfg := config
	var flick := 0.85 + 0.15 * sin(t * 37.0) * sin(t * 13.0 + 1.3)
	circle.set_instance_shader_parameter("intensity", k * cfg.circle_intensity)
	glow.transparency = 1.0 - clampf(k, 0.0, 1.0) * (0.75 + 0.25 * flick)
	var jet := smoothstep(cfg.windup_time * 0.75, cfg.windup_time + 0.25, t) if channeling else 1.0
	light.light_energy = k * cfg.light_energy * flick * lerpf(0.35, 1.0, jet)
	heat.set_instance_shader_parameter("strength", k * jet * cfg.heat_strength)


func _valid(n: Node3D) -> bool:
	return n != null and is_instance_valid(n) and n.is_inside_tree()


## Direção do jato: para onde o modelo do mago olha (no plano).
func jet_dir() -> Vector3:
	if _valid(model):
		return Vector3(sin(model.global_rotation.y), 0.0, cos(model.global_rotation.y))
	return -global_basis.z


## Na palma: o centro da mão um pouco à frente, virado para o jato.
func _follow_now() -> void:
	var dir := jet_dir()
	var at := global_position
	if _valid(hand):
		var mi := hand as MeshInstance3D
		at = (mi.global_transform * mi.get_aabb().get_center()) if mi else hand.global_position
		at += dir * 0.1
	elif _valid(caster):
		at = caster.global_position + Vector3.UP * 1.35 + dir * 0.55
	global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), at)


## Dano no passo de física: os corpos na Hitbox filtrados pelo cone exato e pelo intervalo por inimigo.
func _physics_process(_delta: float) -> void:
	if not deal_damage or not channeling or warm_only or t < config.windup_time:
		return
	var targets := []
	for b in hitbox.get_overlapping_bodies():
		if not b.is_in_group("enemies") or b.get("dead"):
			continue
		targets.append({"id": b.get_instance_id(), "pos": b.global_position, "radius": float(b.get("radius") if b.get("radius") != null else 0.4), "node": b})
	if targets.is_empty():
		return
	var feet_y := caster.global_position.y if _valid(caster) else global_position.y - 1.3
	var cfg := config
	var cone := {"origin": global_position, "dir": jet_dir(), "length": cfg.length, "r0": cfg.radius_start,
		"r1": cfg.radius_end, "feet_y": feet_y, "below": cfg.height_below, "above": cfg.height_above}
	var picked := FlameChannelRules.pick_targets(targets, cone, t, cfg.hit_interval, _last_hit)
	if picked.is_empty():
		return
	var nodes := []
	for p in picked:
		nodes.append(p.node)
	hit_count += nodes.size()
	hit.emit(nodes)


## Para de canalizar: as partículas param de nascer (as soltas terminam o voo), o círculo toca o anel se desfazendo e
## tudo apaga em `time` s (padrão: `fade_time`). A cena se libera quando a última partícula morre.
func stop(time := -1.0) -> void:
	if not channeling:
		return
	channeling = false
	if time < 0.0:
		time = config.fade_time
	hitbox.set_deferred("monitoring", false)
	for p: GPUParticles3D in [core, flames, embers, smoke]:
		p.emitting = false
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "level", 0.0, time).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(self, "fade_u", 1.0, time)
	var tail := maxf(time, maxf(flames.lifetime, maxf(embers.lifetime * 1.4, smoke.lifetime * 1.3)))
	_tween.chain().tween_interval(maxf(tail - time, 0.0))
	_tween.chain().tween_callback(queue_free)
