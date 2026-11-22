class_name FireballProjectile
extends Area3D
## Bola de Fogo do ataque básico do cajado (MageStaffAttack). Cena: scenes/vfx/fireball/fireball_projectile.tscn.
##
## Vida em três fases:
## - CARGA: nasce na ponta do cajado (o jogador a segue até a gema e a faz crescer com set_charge); sem colisão.
##   Fagulhas (Converge) correm para dentro, para a bola.
## - VOO (launch): voa reto em velocidade constante deixando rastro de fogo e fumaça (GPUParticles3D em
##   coordenadas do mundo, que somem sozinhos pelo tempo de vida).
## - FIM: no acerto (inimigo ou cenário) ou no fim do alcance. Simples: dano num alvo só e um estouro pequeno.
##   Carregada: explosão em área (dano com queda pela distância, empurrão leve, tremor de câmera, marca no chão).
##   A bola apaga, o rastro para de emitir e o que já saiu termina de sumir antes do queue_free.
##
## Desenho: quadros da folha 8x8 (assets/vfx/fireball/fireball_sheet.webp, fundo preto, mistura aditiva) pelo
## shader fireball_sheet; o material é um só para todas as bolas (parâmetros por instância).

enum { CHARGING, FLYING, DONE }

# quadros da folha (índice = linha * 8 + coluna)
const CHARGE_IN := Vector2i(0, 5)     ## bola nascendo na ponta do cajado
const CHARGE_LOOP := Vector2i(6, 16)  ## bola com o anel incandescente (carga), em laço
const FLY_ROUND := 19                 ## bola quase sem cauda: voando para longe (ou para perto) da câmera
const FLY_TAIL := Vector2i(26, 31)    ## bola com cauda, em laço: voando de lado na tela
const IMPACT := Vector2i(44, 56)      ## explosão (do chão para cima, até a fumaça)
## Miolo de cada quadro na célula (UV): fica na posição do nó.
const PIVOT_CHARGE := Vector2(0.5, 0.49)
const PIVOT_ROUND := Vector2(0.51, 0.48)
const PIVOT_TAIL := Vector2(0.64, 0.48)
const PIVOT_IMPACT := Vector2(0.55, 0.68)
const FPS := 20.0
const IMPACT_TIME := 0.6
const CHARGE_IN_TIME := 0.22
const SHEET_SIZE := 1.1    ## m: lado do quad no voo, tamanho 1 (a bola ocupa ~40% dele)
const CHARGE_SIZE := 0.85  ## m: lado do quad na carga, tamanho 1 (com o anel, a bola ocupa ~75%)
const HIT_RADIUS := 0.22   ## m: raio da colisão no tamanho 1 (cresce com a bola)
const TRAIL_FADE := 0.8    ## s: o nó dura isto depois do fim (o rastro no ar termina de sumir)
const LIGHT := 2.0
const FIRE_EL := "fogo"
const FIRE_GLOW := Color(1.0, 0.5, 0.12)

## Disparo carregado: explode em área (aoe_radius) em vez de ferir um alvo só.
@export var is_charged := false
@export var damage := 10.0
@export var aoe_radius := 2.5
@export var speed := 24.0
## Tempo de voo (s): no fim do alcance a bola se apaga sem dano.
@export var life := 1.4
## Escala da bola (1 = clique; até MageStaffAttack.MAX_SCALE carregada): desenho, rastro e colisão.
@export var size := 1.0
var direction := Vector3.FORWARD
var crit := false
## Cajado de gelo (efeito "slow" da arma): segundos de lentidão no alvo.
var slow := 0.0
## Empurrão (m/s) da explosão carregada.
var knockback := 5.0
## Multiplayer: bola de outro jogador, só o visual.
var visual_only := false
## Quem disparou (o tremor de câmera da explosão vai para ele).
var shooter: Node = null

var _state := CHARGING
var _t := 0.0
var _charge_t := 0.0
var _impact_t := -1.0
var _impact_size := 1.0
var _hit_ids := {}

@onready var _visual: Node3D = $Visual
@onready var _sheet: GeometryInstance3D = $Visual/Sheet
@onready var _trail: GPUParticles3D = $Visual/Trail
@onready var _smoke: GPUParticles3D = $Visual/Smoke
@onready var _embers: GPUParticles3D = $Visual/Embers
@onready var _converge: GPUParticles3D = $Visual/Converge
@onready var _light: OmniLight3D = $Visual/Light
@onready var _impact: GeometryInstance3D = $Impact
@onready var _hit: CollisionShape3D = $Hit


func _ready() -> void:
	body_entered.connect(_on_body)
	_converge.emitting = _state == CHARGING
	_apply_size()
	_draw_charge()


# ---------------------------------------------------------------- carga
## Carga: `t` = s desde que o botão desceu; `scale_now` = tamanho atual da bola; `c` = carga 0..1 (mais fagulhas
## e mais luz quanto mais cheia).
func set_charge(t: float, scale_now: float, c: float) -> void:
	if _state != CHARGING:
		return
	_charge_t = t
	size = scale_now
	_apply_size()
	_converge.amount_ratio = lerpf(0.35, 1.0, c)
	_light.light_energy = LIGHT * lerpf(0.6, 1.6, c)


## Desistiu da carga (esquiva, troca de arma, menu): a bola some num instante, sem dano.
func cancel() -> void:
	if _state == DONE:
		return
	_state = DONE
	_converge.emitting = false
	var tw := create_tween()
	tw.tween_property(_visual, "scale", Vector3.ONE * 0.01, 0.12)
	tw.parallel().tween_property(_light, "light_energy", 0.0, 0.12)
	tw.tween_callback(queue_free)


# ---------------------------------------------------------------- disparo
## Solta a bola: voa reto em `dir` dali em diante.
func launch(dir: Vector3) -> void:
	direction = dir.normalized()
	_state = FLYING
	_t = 0.0
	if direction.length() > 0.01:
		var up := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
		look_at(global_position + direction, up)   # só gira o nó: a bola encara a câmera pelo shader
	_converge.emitting = false
	var rate := 1.0 if is_charged else 0.55
	for ps in [_trail, _smoke, _embers]:
		ps.amount_ratio = rate
		ps.emitting = true
	_light.light_energy = LIGHT * (1.4 if is_charged else 1.0)
	_light.omni_range = 3.5 * sqrt(size)
	_apply_size()
	monitoring = true


func _physics_process(delta: float) -> void:
	if _state != FLYING:
		return
	global_position += direction * speed * delta
	life -= delta
	if life <= 0.0:
		_finish(null, false)


func _process(delta: float) -> void:
	_t += delta
	match _state:
		CHARGING:
			_draw_charge()
		FLYING:
			_draw_flight()
	if _impact_t >= 0.0:
		_impact_t += delta
		_draw_impact()


func _on_body(body: Node) -> void:
	if _state != FLYING or body.is_in_group("player") or body.is_in_group("players"):
		return
	if body.is_in_group("enemies"):
		if body.dead:
			return
		_finish(body, true)
		return
	_finish(null, true)   # chão, parede, árvore


# ---------------------------------------------------------------- impacto
## `target` = inimigo tocado (ou null); `hit` = tocou em algo (false = fim do alcance: apaga sem dano).
func _finish(target: Node, hit: bool) -> void:
	if _state == DONE:
		return
	_state = DONE
	set_deferred("monitoring", false)
	var pos := global_position
	if hit and is_charged:
		_explode(pos)
	elif hit:
		_single(target, pos)
	# a bola apaga; o rastro para de sair e o que já está no ar some pelo próprio tempo de vida
	_sheet.visible = false
	for ps in [_trail, _smoke, _embers, _converge]:
		ps.emitting = false
	_impact_size = (aoe_radius * 1.5 if is_charged else 1.5 * size) if hit else 0.8 * size
	_impact_t = 0.0
	_impact.visible = true
	_draw_impact()
	var tw := create_tween()
	_light.light_energy = LIGHT * (4.0 if hit and is_charged else 2.0)
	_light.omni_range = maxf(_light.omni_range, _impact_size * 2.0)
	tw.tween_property(_light, "light_energy", 0.0, IMPACT_TIME * 0.8).set_ease(Tween.EASE_OUT)
	tw.tween_interval(maxf(TRAIL_FADE, IMPACT_TIME) - IMPACT_TIME * 0.8)
	tw.tween_callback(queue_free)


## Clique: só o alvo tocado leva dano; um estouro pequeno.
func _single(target: Node, pos: Vector3) -> void:
	Sfx.play_at("fire_hit", pos, 0.1, -3.0)
	FXEpic.glow_burst(pos, FIRE_GLOW, 10, 3.0, 0.12, 0.4, -4.0)
	if target and not visual_only:
		_damage(target, damage, pos - direction, 0.0)


## Carregada: todo inimigo no raio leva dano (100% no centro, 60% na borda), com empurrão para fora.
func _explode(pos: Vector3) -> void:
	Sfx.play_at("explode", pos, 0.1, -4.0 + 2.0 * (size - 1.0))
	FXEpic.glow_burst(pos + Vector3.UP * 0.3, FIRE_GLOW, int(24 * size), 4.0 + 1.5 * size, 0.16, 0.6, -5.0)
	FXEpic.sparks(pos, Vector3.UP, FIRE_GLOW, int(14 * size), 9.0, 0.45)
	FXEpic.ground_mark(pos, Color(0.08, 0.05, 0.03, 0.8), aoe_radius * 0.8, 2.5, "scorch")
	if visual_only:
		return
	if shooter and is_instance_valid(shooter) and shooter.has_method("add_shake"):
		shooter.add_shake(0.18 + 0.12 * (size - 1.0))
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var to: Vector3 = e.global_position - pos
		if absf(to.y) > 3.0:
			continue
		var d := Vector2(to.x, to.z).length()
		if d > aoe_radius + e.radius:
			continue
		var fall := lerpf(1.0, 0.6, clampf(d / maxf(aoe_radius, 0.01), 0.0, 1.0))
		# `from` embaixo do centro: o empurrão sai do miolo da explosão
		_damage(e, damage * fall, pos - Vector3(to.x, 0, to.z).normalized() * 0.1, knockback)


func _damage(e: Node, amount: float, from: Vector3, push: float) -> void:
	if _hit_ids.has(e.get_instance_id()):
		return
	_hit_ids[e.get_instance_id()] = true
	var dmg := EnchantHit.scale(e, amount * randf_range(0.9, 1.1))
	# `pull` negativo = empurra com essa força (Enemy.take_damage); 0 = o tranco normal do golpe
	e.take_damage(dmg, from, crit, slow, 0.0, -push if push > 0.0 else 0.0, EnchantHit.mix(FIRE_EL))
	Game.on_damage_dealt(dmg, e.max_hp)
	EnchantHit.on_hit(e, dmg)


# ---------------------------------------------------------------- desenho
func _apply_size() -> void:
	_visual.scale = Vector3.ONE * size
	var s := (CHARGE_SIZE if _state == CHARGING else SHEET_SIZE)
	_sheet.scale = Vector3.ONE * s
	_hit.scale = Vector3.ONE * size


## Dois quadros seguidos de um laço e a mistura entre eles (troca suave de quadro).
static func _loop(range_: Vector2i, x: float) -> Array:
	var n := range_.y - range_.x + 1
	var i := int(floorf(x)) % n
	return [range_.x + i, range_.x + (i + 1) % n, x - floorf(x)]


func _set_frames(a: float, b: float, mix: float, pa: Vector2, pb: Vector2, travel: Vector3, intensity: float, node: GeometryInstance3D) -> void:
	node.set_instance_shader_parameter("frame_a", a)
	node.set_instance_shader_parameter("frame_b", b)
	node.set_instance_shader_parameter("blend", mix)
	node.set_instance_shader_parameter("pivot_a", pa)
	node.set_instance_shader_parameter("pivot_b", pb)
	node.set_instance_shader_parameter("travel", travel)
	node.set_instance_shader_parameter("intensity", intensity)


func _draw_charge() -> void:
	if _charge_t < CHARGE_IN_TIME:
		var x := _charge_t / CHARGE_IN_TIME * float(CHARGE_IN.y - CHARGE_IN.x)
		var f := float(CHARGE_IN.x) + floorf(x)
		_set_frames(f, minf(f + 1.0, float(CHARGE_IN.y)), x - floorf(x), PIVOT_CHARGE, PIVOT_CHARGE, Vector3.ZERO, 1.2, _sheet)
	else:
		var l := _loop(CHARGE_LOOP, (_charge_t - CHARGE_IN_TIME) * FPS)
		_set_frames(l[0], l[1], l[2], PIVOT_CHARGE, PIVOT_CHARGE, Vector3.ZERO, 1.3, _sheet)


func _draw_flight() -> void:
	# frame_a = bola redonda, frame_b = bola com cauda; o shader mistura pela direção do voo na tela
	var l := _loop(FLY_TAIL, _t * FPS)
	var flick := 1.0 + 0.1 * sin(_t * 37.0)
	_set_frames(float(FLY_ROUND), float(l[0]), 0.0, PIVOT_ROUND, PIVOT_TAIL, direction, flick, _sheet)


func _draw_impact() -> void:
	var k := clampf(_impact_t / IMPACT_TIME, 0.0, 1.0)
	_impact.scale = Vector3.ONE * _impact_size
	var x := k * float(IMPACT.y - IMPACT.x)
	var f := float(IMPACT.x) + floorf(x)
	var fade := 1.0 - smoothstep(0.75, 1.0, k)
	_set_frames(f, minf(f + 1.0, float(IMPACT.y)), x - floorf(x), PIVOT_IMPACT, PIVOT_IMPACT, Vector3.ZERO, 1.4 * fade, _impact)
	if k >= 1.0:
		_impact.visible = false
		_impact_t = -1.0


# ---------------------------------------------------------------- aquecimento
## Uma bola longe da vista, carregando e explodindo: prepara o shader, as partículas e a explosão antes do
## primeiro clique (como FXEpic.prewarm_instances). Chamado (deferred) pelo jogador local.
static func prewarm_instances(at: Node3D) -> void:
	var root := FX._scene()
	if root == null or at == null or not is_instance_valid(at) or not at.is_inside_tree():
		return
	var fb: FireballProjectile = MageStaffAttack.SCENE.instantiate()
	fb.visual_only = true
	fb.is_charged = true
	fb.life = 0.15   # some no fim do alcance (sem som nem dano) e desenha o estouro
	root.add_child(fb)
	fb.global_position = at.global_position + Vector3(0, -240, 0)   # bem abaixo do mapa
	fb.launch(Vector3.DOWN)
