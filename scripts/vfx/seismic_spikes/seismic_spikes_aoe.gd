class_name SeismicSpikesAoE
extends Node3D
## Estacas Sísmicas: o visual inteiro de uma ativação (cena scenes/vfx/seismic_spikes/seismic_spikes_aoe.tscn). Vive
## na cena do mundo, parado no ponto onde a ponta da espada crava (a cena do mundo fica na origem: local = global), segue
## o próprio relógio `t` (0 = a tecla) com os tempos do SeismicSpikesConfig e se libera sozinho no fim. Não fere
## ninguém: avisa `impacted` (a espada tocou o chão) e `quake_started` (a terra começa a tremer) e o dono cria o
## SeismicSpikesDamage (SeismicSpikesAbilities). Nas réplicas é igual (mesma semente = mesmo desenho), só visual.
##
## Fases: 1. a espada crava e o chão racha do centro até o raio; 2. depois de um intervalo a terra TREME (terremoto)
## enquanto a espada está cravada: o chão rachado sacode, pedrinhas pulam, poeira sobe, ronco e a câmera de quem está
## perto treme, com abalos mais fortes de tempos em tempos; 3. quando o herói arranca a espada o tremor para e tudo
## some suavemente.
##
## Nós da cena:
##   CrackGround  (MeshInstance3D, PlaneMesh deitado no chão) a sheet animada: a cratera abrindo, o chão rachando até
##                 o raio (`reveal` no shader), a poeira subindo no tremor e assentando no fim.
##   FissureDecal (Decal) as fissuras escuras e as brasas projetadas no terreno de verdade (acompanham o relevo);
##                 crescem com as rachaduras, sacodem no tremor e somem no fim.
##   ImpactEmbers / QuakeEmbers (GPUParticles3D, one_shot) fagulhas do impacto e do começo do tremor.
##   Pebbles      (GPUParticles3D contínuo, malha de prisma iluminada) pedrinhas pulando no chão durante o tremor.
##   QuakeDust    (GPUParticles3D contínuo) nuvens de poeira subindo do chão durante o tremor.
##   ImpactLight  (OmniLight3D) a luz laranja curta do impacto e do começo do tremor.
## A sheet (seismic_cracks_sheet.webp, 8 x 8 quadros de 128 px, fundo preto puro, vista de cima): 0-20 a cratera
## abrindo, 20-27 o chão inteiro rachado, 28-50 poeira, 50-63 escurecendo até o preto. É terra, não luz: o shader
## (shaders/seismic_spikes/seismic_rock.gdshader) usa mistura normal com o preto recortado pelo brilho, é iluminado pela
## cena e só as brasas laranja emitem.

signal impacted(center: Vector3)
signal quake_started(center: Vector3)

enum State { CHARGE, CRACKS, WAIT, QUAKE, FADE, CANCELED }

const CRACK_GROW := Vector2(0.0, 22.0)     ## da cratera pequena ao chão inteiro rachado (fase 1)
const CRACK_QUAKE := Vector2(22.0, 34.0)   ## rachado, e a poeira começando a subir com o tremor
const CRACK_SETTLE := Vector2(34.0, 58.0)  ## poeira assentando (a espada saiu do chão)
const GROUND_MASK := 1     ## camada do cenário (chão, pedras, construções)
const GROUND_LIFT := 0.04  ## o chão rachado fica rente, um pouco acima do terreno
const RUMBLE_SFX := ["chop_stone", "slam", "chop_stone", "explode"]

@export var config: SeismicSpikesConfig
var seed_value := 0
## Só para preparar shaders (prewarm_instances): mostra cada camada um instante e se libera logo.
var warm_only := false

var state := State.CHARGE
var t := 0.0
var impact_center := Vector3.ZERO
var impact_at := -1.0
var quake_at := -1.0
var reveal := 0.0
## Abalos (trancos) do tremor até agora: um a cada ~quake_beat s.
var beats := 0
var _next_beat := 0.0
var _light_peak := 0.0
var _light_t := 0.0
var _rng := RandomNumberGenerator.new()
var _ground_base := Vector3.ZERO

@onready var crack_ground: MeshInstance3D = $CrackGround
@onready var decal: Decal = $FissureDecal
@onready var impact_embers: GPUParticles3D = $ImpactEmbers
@onready var quake_embers: GPUParticles3D = $QuakeEmbers
@onready var pebbles: GPUParticles3D = $Pebbles
@onready var dust: GPUParticles3D = $QuakeDust
@onready var light: OmniLight3D = $ImpactLight


func _ready() -> void:
	_rng.seed = seed_value
	_set_cracks(0.0, 0.0, 0.0)
	decal.visible = false
	light.light_energy = 0.0
	if warm_only:
		crack_ground.scale = Vector3.ONE * 2.0
		_set_cracks(10.0, 0.01, 1.0)
		decal.visible = true
		decal.modulate.a = 0.01
		pebbles.emitting = true
		dust.emitting = true
		get_tree().create_timer(0.4).timeout.connect(queue_free)
		return
	_snap_to_ground()
	impact_center = global_position
	# o desenho gira com a semente (cada uso racha diferente); o Decal gira junto para as fissuras baterem
	var yaw := float(seed_value % 360) * PI / 180.0
	crack_ground.rotation.y = yaw
	crack_ground.scale = Vector3(config.crack_size, 1.0, config.crack_size)
	_ground_base = Vector3(0.0, GROUND_LIFT, 0.0)
	crack_ground.position = _ground_base
	decal.rotation.y = yaw
	decal.emission_energy = config.decal_glow
	for p in [quake_embers, pebbles, dust]:
		var m := (p as GPUParticles3D).process_material as ParticleProcessMaterial
		if m != null:
			m.emission_ring_radius = config.radius * 0.92
	pebbles.amount = maxi(1, int(config.pebble_rate * pebbles.lifetime))
	dust.amount = maxi(1, int(config.dust_rate * dust.lifetime))
	light.omni_range = config.radius + 2.0


## O ponto do golpe desce (ou sobe) até o chão de verdade embaixo dele: a ponta crava no terreno, não no ar.
func _snap_to_ground() -> void:
	var w := get_world_3d()
	if w == null:
		return
	var p := global_position
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.5, p + Vector3.DOWN * 5.0, GROUND_MASK)
	var hit := w.direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		global_position = hit.position


## A esquiva só cancela antes da espada tocar o chão.
func can_cancel() -> bool:
	return state == State.CHARGE


## Cancelado antes do impacto: nada apareceu ainda; some sem rachar nem ferir.
func cancel() -> void:
	if not can_cancel():
		return
	state = State.CANCELED
	queue_free()


func _process(delta: float) -> void:
	if warm_only or state == State.CANCELED:
		return
	t += delta
	_light_t += delta
	light.light_energy = _light_peak * exp(-6.0 * _light_t)
	if state == State.CHARGE:
		if t >= config.impact_time():
			_impact()
		return
	_update_cracks()
	match state:
		State.CRACKS:
			if t >= config.cracks_done_time():
				state = State.WAIT   # o intervalo antes do tremor
		State.WAIT:
			if t >= config.quake_time():
				_quake_start()
		State.QUAKE:
			_tremble()
			if t >= config.pull_end():
				_stop_quake()
		State.FADE:
			if t >= config.pull_end() + maxf(config.fade_time, dust.lifetime) + 0.1:
				queue_free()


## Fase 1: a espada tocou o chão. Fagulhas, luz, tranco, e o chão começa a rachar do centro para fora.
func _impact() -> void:
	state = State.CRACKS
	impact_at = t
	decal.visible = true
	_update_cracks()
	impact_embers.restart()
	_flash(2.2)
	_shake(config.shake_strength)
	Sfx.play_at("slam", impact_center, 0.05, 1.0)
	impacted.emit(impact_center)


## Fase 2: depois do intervalo a terra começa a tremer (e o dano corre do centro até a borda).
func _quake_start() -> void:
	state = State.QUAKE
	quake_at = t
	_next_beat = t
	quake_embers.restart()
	pebbles.emitting = config.pebble_rate > 0
	dust.emitting = config.dust_rate > 0
	_flash(1.4)
	_shake(config.shake_strength * 0.8)
	Sfx.play_at("explode", impact_center, 0.1, -3.0)
	quake_started.emit(impact_center)


## Um passo do tremor: o chão rachado e as fissuras sacodem, a câmera de quem está perto treme sem parar e, a cada
## abalo, dá um tranco mais forte com ronco.
func _tremble() -> void:
	# entra rápido, firme no meio, cedendo enquanto a espada sai
	var s := t - quake_at
	var amp := smoothstep(0.0, 0.25, s) * (1.0 - 0.6 * smoothstep(config.pull_start(), config.pull_end(), t))
	var j := config.ground_jitter * amp
	var off := Vector3(_rng.randf_range(-j, j), _rng.randf_range(-j, j) * 0.5, _rng.randf_range(-j, j))
	crack_ground.position = _ground_base + off
	decal.position = off
	var pulse := 0.0
	if t >= _next_beat:
		beats += 1
		_next_beat = t + config.quake_beat * _rng.randf_range(0.7, 1.3)
		pulse = config.quake_pulse * amp
		Sfx.play_at(RUMBLE_SFX[beats % RUMBLE_SFX.size()], impact_center, 0.2, -13.0 + 4.0 * amp)
	_shake(config.quake_shake * amp + pulse)


## Tremendo agora? (o herói usa para sacudir junto com o chão)
func is_quaking() -> bool:
	return state == State.QUAKE


## A espada saiu do chão: o tremor para (o chão volta ao lugar), pedrinhas e poeira param de nascer e tudo some.
func _stop_quake() -> void:
	state = State.FADE
	crack_ground.position = _ground_base
	decal.position = Vector3.ZERO
	pebbles.emitting = false
	dust.emitting = false


## O chão rachado e o Decal pelo relógio: abrindo até o raio, rachado com a poeira subindo no tremor e assentando no
## fim, com fade quando a espada sai.
func _update_cracks() -> void:
	if impact_at < 0.0:
		return
	var s := t - impact_at
	reveal = maxf(reveal, SeismicSpikesRules.crack_reveal(s, config.crack_time))
	var frame: float
	var alpha := config.crack_opacity
	var fade := 1.0 - clampf((t - config.pull_end()) / maxf(config.fade_time, 0.01), 0.0, 1.0)
	if t < config.cracks_done_time():
		frame = lerpf(CRACK_GROW.x, CRACK_GROW.y, clampf(s / maxf(config.crack_time, 0.01), 0.0, 1.0))
	elif t < config.pull_end():
		var u := clampf((t - config.cracks_done_time()) / maxf(config.pull_end() - config.cracks_done_time(), 0.01), 0.0, 1.0)
		frame = lerpf(CRACK_QUAKE.x, CRACK_QUAKE.y, u)
		alpha = lerpf(config.crack_opacity, lerpf(config.crack_opacity, config.dust_opacity, 0.5), smoothstep(0.4, 1.0, u))
	else:
		var u := clampf((t - config.pull_end()) / maxf(config.fade_time, 0.01), 0.0, 1.0)
		frame = lerpf(CRACK_SETTLE.x, CRACK_SETTLE.y, u)
		alpha = config.dust_opacity
	_set_cracks(frame, alpha * fade, reveal)
	decal.modulate.a = config.decal_opacity * smoothstep(0.0, 0.5, reveal) * fade
	var grow := lerpf(0.45, 1.0, reveal)
	decal.size = Vector3(config.crack_size * grow, 1.2, config.crack_size * grow)
	decal.visible = decal.modulate.a > 0.001
	# o capim dentro da área se abaixa junto com as rachaduras (senão esconde o chão rachado) e volta no fim
	_flatten(config.radius * 1.08 * maxf(reveal, 0.2), smoothstep(0.0, 0.4, reveal) * fade)


## Capim achatado (global `fx_flatten` do shader do capim, assets/shaders/grass.gdshader). Um efeito por vez: o último
## a mexer é o dono e só ele zera.
static var _flatten_owner: WeakRef = null


func _flatten(r: float, amount: float) -> void:
	_flatten_owner = weakref(self)
	RenderingServer.global_shader_parameter_set("fx_flatten",
		Vector4(impact_center.x, impact_center.z, r, clampf(amount, 0.0, 1.0)))


func _exit_tree() -> void:
	if _flatten_owner != null and _flatten_owner.get_ref() == self:
		RenderingServer.global_shader_parameter_set("fx_flatten", Vector4.ZERO)
		_flatten_owner = null


func _set_cracks(frame: float, alpha: float, rv: float) -> void:
	crack_ground.set_instance_shader_parameter("frame", frame)
	crack_ground.set_instance_shader_parameter("intensity", alpha)
	crack_ground.set_instance_shader_parameter("reveal", rv)
	crack_ground.visible = alpha > 0.001


func _flash(energy: float) -> void:
	_light_peak = energy
	_light_t = 0.0


## Tremor na câmera do jogador local, mais fraco quanto mais longe dele (some em `shake_range`).
func _shake(amount: float) -> void:
	var lp := EarthquakeSkill._local_player()
	if lp == null or amount <= 0.0:
		return
	var d := Vector2(lp.global_position.x - impact_center.x, lp.global_position.z - impact_center.z).length()
	var f := 1.0 - clampf(d / config.shake_range, 0.0, 1.0)
	if f > 0.0:
		lp.add_shake(amount * f * f * (3.0 - 2.0 * f))
