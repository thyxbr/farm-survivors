class_name DragAndSlash
extends Node3D
## Corte do Abismo (montante, tecla 2): o visual e a detecção de dano das duas fases, em cena própria
## (scenes/vfx/longsword_drag/drag_and_slash.tscn). DragSlashAbilities cria uma por ativação, na cena do mundo, e
## cuida do herói (corrida, pose, quando o corte começa); esta cena vive mais que a habilidade e se libera sozinha
## (queue_free) quando o último efeito some.
##   Drag            (top_level) segue o ponto em que a ponta da lâmina toca o chão, virado para trás (+Z = para trás)
##     SparkSheet    a sprite sheet das fagulhas (drag_sparks_sheet.webp, 4 x 8), aditiva, deitada ao longo do caminho
##                   e girando em volta dele para encarar a câmera (additive_sheet.gdshader, billboard 2)
##     Sparks        GPUParticles3D: chuva de fagulhas alongadas para trás e para cima, quicando no chão
##     Embers        brasas lentas subindo com turbulência
##     Pebbles       pedrinhas arrancadas do chão, quicando
##     Dust          rastro de poeira
##     Ground        GPUParticlesCollisionBox3D: o chão em que as partículas quicam (anda junto)
##     TipLight      luz alaranjada tremendo na ponta
##   Groove          (top_level) o sulco em brasa que a ponta deixa no chão (fita montada a cada quadro)
##   Slash           (top_level) no ponto em que o corte começou, virado na direção da corrida
##     Trail         o rastro incandescente da lâmina no corte (fita do cabo à ponta, montada a cada quadro)
##     ArcSheet      o arco de energia da sprite sheet (rising_claws_sheet.webp quadros 10-13 e 23-27), de pé
##     SlashSparks   explosão de fagulhas no acerto
##     SlashLight    clarão
##     Ground        chão das partículas do corte e das garras
##   Claws/Claw      a garra espectral (duplicada em _ready até `claw_count`): Sheet (quadros 4-35 da mesma folha, de
##                   pé, sobe de dentro do chão), Glow (brilho violeta no chão), Motes (faíscas violeta), Shards
##                   (lascas de pedra) e Light
## Fases: DRAG (corrida: a ponta raspa, fagulhas e sulco) -> SLASH (start_slash: o último passo e o corte de baixo para
## cima; no acerto o arco e as garras, que saem do chão em onda) -> FADE (tudo se apaga) -> DONE.
## Dano (só no dono, `deal_damage`): no acerto do corte os inimigos no arco à frente (sinal `slash_hit`) e, quando cada
## garra irrompe, os que estão em cima dela (`claw_hit`); cada inimigo leva o corte uma vez e no máximo uma garra.
## Consulta de forma (PhysicsShapeQueryParameters3D) na camada dos inimigos, filtrada pelas contas de DragSlashRules.
## `cancel()` antes do corte apaga tudo sem dano (esquiva, morte, troca de arma).

signal slash_hit(origin: Vector3, fwd: Vector3, targets: Array)
signal claw_hit(center: Vector3, targets: Array)
signal finished

const ENEMY_MASK := 4      ## camada 3 ("enemies")
const WORLD_MASK := 1
const CANCEL_TIME := 0.2
## Folha das fagulhas (4 x 8, quadros de 256 x 128): o 0 é só o chão; 1-4 a ponta encosta e as fagulhas começam; 5-27
## o atrito cheio (em laço, com cross-fade na volta); 28-31 apagando.
const SPARK_GRID := Vector2i(4, 8)
const SPARK_IN := Vector2i(1, 4)
const SPARK_LOOP := Vector2i(5, 27)
const SPARK_OUT := Vector2i(28, 31)
## Folha do corte e das garras (6 x 6, ~170 px, com linhas de grade): o arco subindo (10-13) e, no alto, se desfazendo
## (23-27); a garra cheia crepitando (14-21) e se desfazendo em faíscas (22, 28-35).
const CLAW_GRID := Vector2i(6, 6)
const ARC_RISE: Array[int] = [10, 11, 12, 13]
const ARC_FADE: Array[int] = [23, 24, 25, 26, 27]
const CLAW_LIVE: Array[int] = [14, 15, 16, 17, 18, 19, 20, 21]
const CLAW_FADE: Array[int] = [22, 28, 29, 30, 31, 32, 33, 34, 35]
## A ponta conta como "no chão" até esta altura (m): acima dela as fagulhas param.
const CONTACT_H := 0.2
const GROOVE_STEP := 0.09     ## um ponto do sulco a cada 9 cm
const GROOVE_WIDTH := 0.26
const TRAIL_SUB := 4          ## pontos interpolados entre dois quadros no rastro do corte (curva suave)

## Unhas de cristal de cada garra (Claws/Claw/Talons): altura da maior em fração de `claw_height`, e por unha
## [x, z (em fração da altura), tamanho, leque (rad, giro em Z: a ponta abre para fora), inclinação (rad, giro em X:
## negativo = a base puxa para trás e a ponta, com a curva da malha, vira um gancho para a frente)].
const TALON_HEIGHT := 0.62
const TALON_LAYOUT := [[0.15, -0.04, 0.78, -0.34, -0.12], [0.0, 0.0, 1.0, 0.0, -0.18], [-0.15, -0.04, 0.82, 0.34, -0.12]]
const TALON_RISE := 0.16       ## tempo para a unha sair do chão (s)
const TALON_STAGGER := 0.045   ## a do meio primeiro, as dos lados logo depois (s)
const TALON_RADIUS := 0.13     ## raio da base (fração da altura)
const TALON_CURVE := 0.62      ## quanto a ponta se curva para a frente (fração da altura)
const TALON_SIDES := 6

enum State { DRAG, SLASH, FADE, DONE, CANCELED }

@export var config: DragSlashConfig

## O herói e as pontas da lâmina da montante dele (KnightLook: holder = o cabo nas mãos, tip = a ponta).
var follow: Node3D
var blade_base: Node3D
var blade_tip: Node3D
var yaw := 0.0
var seed_value := 0
var deal_damage := false
## Só aquece os pipelines (DragSlashAbilities.prewarm_instances): desenha cada efeito uma vez, longe da vista, e se libera.
var warm_only := false

@onready var drag_root: Node3D = $Drag
@onready var spark_sheet: MeshInstance3D = $Drag/SparkSheet
@onready var sparks: GPUParticles3D = $Drag/Sparks
@onready var embers: GPUParticles3D = $Drag/Embers
@onready var pebbles: GPUParticles3D = $Drag/Pebbles
@onready var dust: GPUParticles3D = $Drag/Dust
@onready var tip_light: OmniLight3D = $Drag/TipLight
@onready var groove: MeshInstance3D = $Groove
@onready var slash_root: Node3D = $Slash
@onready var trail: MeshInstance3D = $Slash/Trail
@onready var arc_sheet: MeshInstance3D = $Slash/ArcSheet
@onready var slash_sparks: GPUParticles3D = $Slash/SlashSparks
@onready var slash_light: OmniLight3D = $Slash/SlashLight
@onready var claws_root: Node3D = $Claws

var state := State.DRAG
var t := 0.0
## Instante (t) em que o corte começou e em que ele acertou (-1 = ainda não).
var slash_at := -1.0
var hit_at := -1.0
var hit_count := 0
var claw_hit_count := 0
var fwd := Vector3.FORWARD
var _drag_at := -1.0           ## quando a ponta encostou no chão e as fagulhas começaram
var _out_at := -1.0            ## quando as fagulhas começaram a se apagar
var _contact := 0.0            ## 0..1: quanto a ponta está raspando o chão agora (suavizado)
var _groove_pts: Array = []    ## [{p: Vector3, side: Vector3, t: float}]
var _trail_pts: Array = []     ## [{a: Vector3 (cabo), b: Vector3 (ponta), t: float}]
var _trail_raw: Array = []     ## amostras cruas do quadro (para a interpolação)
var _claws: Array[Node3D] = []
var _claw_at: Array[float] = []
var _claw_up: Array[bool] = []
var _hit_slash := {}
var _hit_claw := {}
var _scrape_t := 0.0
var _fade_started := false
var _ground_y := 0.0
var _groove_mesh: ImmediateMesh
var _trail_mesh: ImmediateMesh


func _ready() -> void:
	if config == null:
		config = load("res://assets/vfx/longsword_drag/drag_slash_config.tres")
	fwd = Vector3(sin(yaw), 0.0, cos(yaw))
	# materiais de desenho das partículas: os mesmos do resto do jogo (FXEpic), divididos por todas as habilidades
	sparks.draw_pass_1 = FXEpic._spark_mesh()
	slash_sparks.draw_pass_1 = FXEpic._spark_mesh()
	embers.material_override = FXEpic._particle_mat(FXEpic._glow_tex(), true, true)
	dust.material_override = FXEpic._particle_mat(FXEpic._smoke_tex(), false)
	var k := maxf(config.spark_amount, 0.05)
	for p: GPUParticles3D in [sparks, embers, pebbles, dust]:
		p.amount = maxi(1, int(round(p.amount * k)))
	# a sprite sheet das fagulhas deitada ao longo do caminho, para trás da ponta (+Z do Drag): X do quad = para trás
	var sw := config.spark_sheet_size
	spark_sheet.transform = Transform3D(Basis(Vector3(0, 0, sw.x), Vector3(0, sw.y, 0), Vector3(-1, 0, 0)), Vector3.ZERO)
	spark_sheet.set_instance_shader_parameter("intensity", 0.0)
	arc_sheet.set_instance_shader_parameter("intensity", 0.0)
	arc_sheet.visible = false
	var ah := config.arc_height
	arc_sheet.transform = Transform3D(Basis.from_scale(Vector3(ah, ah, 1.0)), Vector3(0.0, -0.08 * ah, 1.0))
	_groove_mesh = ImmediateMesh.new()
	groove.mesh = _groove_mesh
	_trail_mesh = ImmediateMesh.new()
	trail.mesh = _trail_mesh
	# as garras: a do modelo na cena e cópias dela até `claw_count`
	var tmpl: Node3D = claws_root.get_node("Claw")
	_claws.append(tmpl)
	for i in range(1, config.claw_count):
		var c := tmpl.duplicate() as Node3D
		claws_root.add_child(c)
		_claws.append(c)
	for c in _claws:
		_claw_at.append(-1.0)
		_claw_up.append(false)
		c.visible = false
		var motes: GPUParticles3D = c.get_node("Motes")
		motes.material_override = FXEpic._particle_mat(FXEpic._glow_tex(), true, true)
		(c.get_node("Glow") as MeshInstance3D).material_override = _glow_mat()
		c.get_node("Sheet").set_instance_shader_parameter("intensity", 0.0)
		(c.get_node("Ring") as MeshInstance3D).material_override = _ring_mat()
		var tk := 0
		for tn: MeshInstance3D in c.get_node("Talons").get_children():
			tn.mesh = talon_mesh()
			tn.set_instance_shader_parameter("seed", float(_claws.find(c) * 3 + tk) * 0.37)
			tn.set_instance_shader_parameter("dissolve", 0.0)
			tk += 1
	if warm_only:
		_warm_pipelines()
		return
	_place_drag()


## Desenha cada efeito um instante (o Godot prepara o pipeline de desenho no primeiro uso; sem isso a primeira
## ativação da sessão engasgaria).
func _warm_pipelines() -> void:
	set_process(false)
	state = State.DONE
	drag_root.global_transform = Transform3D(Basis.IDENTITY, global_position)
	slash_root.global_transform = Transform3D(Basis.IDENTITY, global_position)
	claws_root.global_position = global_position
	spark_sheet.set_instance_shader_parameter("intensity", 0.01)
	arc_sheet.visible = true
	arc_sheet.set_instance_shader_parameter("intensity", 0.01)
	for c in _claws:
		c.visible = true
		c.get_node("Sheet").set_instance_shader_parameter("intensity", 0.01)
		(c.get_node("Motes") as GPUParticles3D).restart()
		(c.get_node("Shards") as GPUParticles3D).restart()
	for p: GPUParticles3D in [sparks, embers, pebbles, dust, slash_sparks]:
		p.restart()
	var a := global_position
	_draw_ribbon(_groove_mesh, [{"a": a, "b": a + Vector3.RIGHT * 0.2, "age": 0.0, "w": 1.0},
		{"a": a + Vector3.FORWARD, "b": a + Vector3.FORWARD + Vector3.RIGHT * 0.2, "age": 0.5, "w": 1.0}])
	_draw_ribbon(_trail_mesh, [{"a": a, "b": a + Vector3.UP, "age": 0.0, "w": 1.0},
		{"a": a + Vector3.FORWARD, "b": a + Vector3.FORWARD + Vector3.UP, "age": 0.5, "w": 1.0}])
	get_tree().create_timer(0.6).timeout.connect(queue_free)


# ------------------------------------------------------------------- controle (DragSlashAbilities)
## A corrida começou: a ponta já está no chão e o atrito acende.
func start_drag() -> void:
	if state != State.DRAG or _drag_at >= 0.0:
		return
	_drag_at = t
	Sfx.play_at("anvil", _tip_pos(), 0.12, -9.0)
	Sfx.play_at("staff_wind", _tip_pos(), 0.1, -6.0)


## O herói parou de correr: o último passo e o corte de baixo para cima (o acerto vem `config.hit_time()` depois).
func start_slash() -> void:
	if state != State.DRAG:
		return
	state = State.SLASH
	slash_at = t
	if _drag_at < 0.0:
		_drag_at = t
	var at: Vector3 = follow.global_position if _valid(follow) else global_position
	slash_root.global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	claws_root.global_transform = Transform3D(Basis(Vector3.UP, yaw), at)


## Antes do corte dá para desfazer (esquiva, morte, troca de arma).
func can_cancel() -> bool:
	return state == State.DRAG


## Desfaz sem dano: as fagulhas param e o que já está no ar termina sozinho.
func cancel() -> void:
	if not can_cancel():
		return
	state = State.CANCELED
	_set_drag_emitting(false)
	var a := float(spark_sheet.get_instance_shader_parameter("intensity"))
	var l := tip_light.light_energy
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		spark_sheet.set_instance_shader_parameter("intensity", a * v)
		tip_light.light_energy = l * v, 1.0, 0.0, CANCEL_TIME)
	tw.tween_interval(maxf(config.groove_life, 0.8))
	tw.tween_callback(_finish)


# ------------------------------------------------------------------- quadro a quadro
func _process(delta: float) -> void:
	t += delta
	_refresh_blade()
	_update_contact(delta)
	_update_drag_fx(delta)
	_update_groove()
	match state:
		State.SLASH:
			var s := t - slash_at
			_sample_trail(s)
			_update_arc(s)
			if hit_at < 0.0 and s >= config.hit_time():
				_hit()
			_update_claws()
			if s >= config.plant_time + config.rise_time + config.hold_time and not _fade_started:
				_fade_out()
		State.FADE, State.CANCELED:
			_sample_trail(t - slash_at if slash_at >= 0.0 else 0.0)
			_update_arc(t - slash_at if slash_at >= 0.0 else 99.0)
			_update_claws()
	_draw_trail()


func _valid(n: Variant) -> bool:
	return n != null and is_instance_valid(n) and (n as Node).is_inside_tree()


## A arma do herói pode ser recriada no meio da habilidade (troca de visual, nível): pega a ponta e o cabo atuais.
func _refresh_blade() -> void:
	if _valid(blade_tip) and _valid(blade_base):
		return
	if _valid(follow) and follow.get("look") is Dictionary:
		var lk: Dictionary = follow.get("look")
		var tp = lk.get("tip")
		var hd = lk.get("holder")
		blade_tip = tp if _valid(tp) else null
		blade_base = hd if _valid(hd) else null
	else:
		blade_tip = null
		blade_base = null


## Onde está a ponta da lâmina agora (sem a arma: atrás do herói, no chão).
func _tip_pos() -> Vector3:
	if _valid(blade_tip):
		return blade_tip.global_position
	var base: Vector3 = follow.global_position if _valid(follow) else global_position
	return base - fwd * 1.3 + Vector3.UP * 0.05


func _base_pos() -> Vector3:
	if _valid(blade_base):
		return blade_base.global_position
	var base: Vector3 = follow.global_position if _valid(follow) else global_position
	return base + Vector3.UP * 0.9


## Altura do chão embaixo de `p` (raio para baixo no mundo; sem acerto, a dos pés do herói).
func _ground_at(p: Vector3) -> float:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.5, p - Vector3.UP * 3.0, WORLD_MASK)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			return float(hit.position.y)
	return follow.global_position.y if _valid(follow) else p.y


## Quanto a ponta está raspando: no chão (até CONTACT_H) durante a corrida e o último passo; no corte ela sobe e solta.
func _update_contact(delta: float) -> void:
	var tip := _tip_pos()
	_ground_y = _ground_at(tip)
	var touching := tip.y - _ground_y < CONTACT_H and _drag_at >= 0.0
	if state == State.SLASH and t - slash_at > config.plant_time + config.rise_time * 0.5:
		touching = false   # já subiu: o resto da raspagem é o arco no ar
	if state in [State.FADE, State.CANCELED, State.DONE]:
		touching = false
	_contact = move_toward(_contact, 1.0 if touching else 0.0, delta * (14.0 if touching else 6.0))


## As fagulhas seguem o ponto em que a ponta toca o chão; a sprite sheet toca entrada, laço e saída.
func _place_drag() -> void:
	var tip := _tip_pos()
	var g := Vector3(tip.x, _ground_y + 0.02, tip.z)
	# virado para trás do caminho: +Z = para trás (para onde as fagulhas voam), o mesmo da corrida
	var back := -fwd
	var side := Vector3.UP.cross(back).normalized()
	drag_root.global_transform = Transform3D(Basis(side, Vector3.UP, back), g)


func _update_drag_fx(delta: float) -> void:
	_place_drag()
	var on := _contact > 0.35
	_set_drag_emitting(on)
	if on:
		_scrape_t -= delta
		if _scrape_t <= 0.0:   # o raspar: pancadas curtas de pedra, aleatórias
			_scrape_t = randf_range(0.09, 0.16)
			Sfx.play_at("chop_stone", drag_root.global_position, 0.25, -15.0)
	# a sprite sheet: entrada (1-4) quando encosta, laço (5-27) raspando, saída (28-31) quando solta
	var fps := config.sheet_fps
	var fa := 0.0
	var fb := 0.0
	var bl := 0.0
	var vis := _contact
	if _drag_at >= 0.0 and _contact > 0.01 and _out_at < 0.0:
		var f := (t - _drag_at) * fps
		var n_in := float(SPARK_IN.y - SPARK_IN.x + 1)
		if f < n_in:
			fa = SPARK_IN.x + floorf(f)
			fb = fa + 1.0
			bl = f - floorf(f)
		else:
			var span := float(SPARK_LOOP.y - SPARK_LOOP.x + 1)
			var x := fposmod(f - n_in, span)
			fa = SPARK_LOOP.x + floorf(x)
			fb = SPARK_LOOP.x if fa >= SPARK_LOOP.y else fa + 1.0
			bl = x - floorf(x)
		if _contact < 0.5 and state != State.DRAG:
			_out_at = t
	if _out_at >= 0.0:
		var f := (t - _out_at) * fps
		var n_out := float(SPARK_OUT.y - SPARK_OUT.x)
		fa = SPARK_OUT.x + minf(floorf(f), n_out)
		fb = minf(fa + 1.0, SPARK_OUT.y)
		bl = clampf(f - floorf(f), 0.0, 1.0) if f < n_out else 0.0
		vis = 1.0 - smoothstep(n_out * 0.6, n_out + 1.0, f)
	elif state != State.DRAG and _contact <= 0.01:
		vis = 0.0
	# brilho tremendo como fogo de verdade (duas senoides fora de fase)
	var flick := 0.88 + 0.08 * sin(t * 37.0) + 0.06 * sin(t * 61.0 + 1.3)
	spark_sheet.set_instance_shader_parameter("frame_a", fa)
	spark_sheet.set_instance_shader_parameter("frame_b", fb)
	spark_sheet.set_instance_shader_parameter("blend", bl)
	spark_sheet.set_instance_shader_parameter("intensity", vis * flick)
	tip_light.light_energy = 2.6 * _contact * flick


func _set_drag_emitting(on: bool) -> void:
	for p: GPUParticles3D in [sparks, embers, pebbles, dust]:
		if p.emitting != on:
			p.emitting = on


# ------------------------------------------------------------------- sulco em brasa no chão
func _update_groove() -> void:
	if _contact > 0.5 and state != State.CANCELED:
		var p := Vector3(drag_root.global_position.x, _ground_y + 0.03, drag_root.global_position.z)
		if _groove_pts.is_empty() or (_groove_pts[-1].p as Vector3).distance_to(p) >= GROOVE_STEP:
			var dirv := fwd
			if not _groove_pts.is_empty():
				var d: Vector3 = p - (_groove_pts[-1].p as Vector3)
				d.y = 0.0
				if d.length() > 0.001:
					dirv = d.normalized()
			_groove_pts.append({"p": p, "side": dirv.cross(Vector3.UP).normalized(), "t": t})
	var life := config.groove_life
	while not _groove_pts.is_empty() and t - float(_groove_pts[0].t) > life:
		_groove_pts.pop_front()
	var ribbon := []
	for g in _groove_pts:
		var hw := GROOVE_WIDTH * 0.5
		ribbon.append({"a": (g.p as Vector3) - (g.side as Vector3) * hw, "b": (g.p as Vector3) + (g.side as Vector3) * hw,
			"age": (t - float(g.t)) / life, "w": 1.0})
	_draw_ribbon(_groove_mesh, ribbon)


# ------------------------------------------------------------------- rastro do corte
## Guarda o cabo e a ponta da lâmina a cada quadro enquanto ela corta (do começo do giro até o fim do alto).
func _sample_trail(s: float) -> void:
	var from := config.plant_time * 0.9
	var to := config.plant_time + config.rise_time + config.hold_time * 0.35
	if state == State.SLASH and s >= from and s <= to:
		var a := _base_pos()
		var b := _tip_pos()
		# a fita começa um pouco depois do cabo: o miolo dela é o caminho da metade de fora da lâmina
		_trail_raw.append({"a": a.lerp(b, 0.4), "b": b + (b - a).normalized() * 0.1, "t": t})
		_rebuild_trail_points()
	var life := config.trail_life
	while not _trail_pts.is_empty() and t - float(_trail_pts[0].t) > life:
		_trail_pts.pop_front()
	while _trail_raw.size() > 2 and t - float(_trail_raw[0].t) > life * 1.5:
		_trail_raw.pop_front()


## Interpola (Catmull-Rom) entre as amostras: o corte é rápido, a ~20° por quadro a fita ficaria facetada.
func _rebuild_trail_points() -> void:
	_trail_pts.clear()
	var n := _trail_raw.size()
	if n < 2:
		for r in _trail_raw:
			_trail_pts.append(r)
		return
	for i in n - 1:
		var p0: Dictionary = _trail_raw[maxi(i - 1, 0)]
		var p1: Dictionary = _trail_raw[i]
		var p2: Dictionary = _trail_raw[i + 1]
		var p3: Dictionary = _trail_raw[mini(i + 2, n - 1)]
		for k in TRAIL_SUB:
			var u := float(k) / TRAIL_SUB
			_trail_pts.append({"a": _cr(p0.a, p1.a, p2.a, p3.a, u), "b": _cr(p0.b, p1.b, p2.b, p3.b, u),
				"t": lerpf(float(p1.t), float(p2.t), u)})
	_trail_pts.append(_trail_raw[n - 1])


static func _cr(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: float) -> Vector3:
	var u2 := u * u
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u2 * u)


func _draw_trail() -> void:
	var life := config.trail_life
	var ribbon := []
	for p in _trail_pts:
		ribbon.append({"a": p.a, "b": p.b, "age": clampf((t - float(p.t)) / life, 0.0, 1.0), "w": 1.0})
	# o mais novo primeiro: a borda da frente (idade 0) é a da lâmina
	ribbon.reverse()
	_draw_ribbon(_trail_mesh, ribbon)


## Fita em tiras: cada ponto {a, b, age, w}; UV.x = idade, UV.y = 0 em `a` e 1 em `b`, COLOR.a = w.
func _draw_ribbon(m: ImmediateMesh, pts: Array) -> void:
	m.clear_surfaces()
	if pts.size() < 2:
		return
	m.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for p in pts:
		var c := Color(1, 1, 1, float(p.w))
		m.surface_set_color(c)
		m.surface_set_uv(Vector2(float(p.age), 0.0))
		m.surface_add_vertex(p.a)
		m.surface_set_color(c)
		m.surface_set_uv(Vector2(float(p.age), 1.0))
		m.surface_add_vertex(p.b)
	m.surface_end()


# ------------------------------------------------------------------- arco de energia
## O arco da sprite sheet acompanha a lâmina: sobe (10-13) do começo do giro ao acerto e se desfaz no alto (23-27).
func _update_arc(s: float) -> void:
	var r0 := config.plant_time + config.rise_time * 0.2
	var r1 := config.hit_time() + config.rise_time * 0.15
	var f1 := r1 + config.hold_time + 0.18
	if s < r0 or s > f1 + 0.05:
		arc_sheet.visible = false
		return
	arc_sheet.visible = true
	var seq: Array[int]
	var x: float
	if s < r1:
		seq = ARC_RISE
		x = (s - r0) / (r1 - r0) * (seq.size() - 1)
	else:
		seq = ARC_FADE
		x = clampf((s - r1) / (f1 - r1), 0.0, 1.0) * (seq.size() - 1)
	var i := mini(int(x), seq.size() - 1)
	var j := mini(i + 1, seq.size() - 1)
	arc_sheet.set_instance_shader_parameter("frame_a", float(seq[i]))
	arc_sheet.set_instance_shader_parameter("frame_b", float(seq[j]))
	arc_sheet.set_instance_shader_parameter("blend", x - float(i))
	var grow := smoothstep(r0, r0 + 0.05, s)
	var gone := 1.0 - smoothstep(f1 - 0.12, f1, s)
	arc_sheet.set_instance_shader_parameter("intensity", 1.6 * grow * gone)


# ------------------------------------------------------------------- acerto e garras
func _hit() -> void:
	hit_at = t
	var origin: Vector3 = follow.global_position if _valid(follow) else slash_root.global_position
	slash_root.global_position = origin
	claws_root.global_position = origin
	slash_sparks.global_position = origin + fwd * 1.1 + Vector3.UP * 0.4
	slash_sparks.restart()
	slash_light.light_energy = 5.0
	create_tween().tween_property(slash_light, "light_energy", 0.0, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_shake_local(origin, 1.0)
	Sfx.play_at("sword_hit_heavy", origin + fwd, 0.08, -2.0)
	Sfx.play_at("arcane_cast", origin + fwd * 2.0, 0.1, -4.0)
	# as garras saem do chão em onda, na direção do corte
	var centers := DragSlashRules.claw_centers(origin, fwd, _claws.size(), config.claw_first, config.claw_step, config.claw_spread)
	for i in _claws.size():
		var c := centers[i]
		c.y = _ground_at(c + Vector3.UP * 0.5)
		_claws[i].global_transform = Transform3D(Basis(Vector3.UP, yaw), c)
		_claw_at[i] = t + 0.03 + config.claw_stagger * i
	if deal_damage:
		var targets := _query(origin + fwd * config.slash_radius * 0.45, config.slash_radius + 1.0)
		var picked := DragSlashRules.pick(targets, func(e: Dictionary) -> bool:
			return DragSlashRules.in_slash(origin, fwd, e.pos, config.slash_radius, config.slash_half_angle, float(e.radius)), _hit_slash)
		hit_count = picked.size()
		slash_hit.emit(origin, fwd, picked.map(func(x: Dictionary) -> Node: return x.node))


## As garras: cada uma sobe de dentro do chão (o terreno esconde a parte de baixo), crepita (14-21) e se desfaz em
## faíscas (22, 28-35). Ao irromper fere quem está em cima.
func _update_claws() -> void:
	var life := config.claw_life
	var fps := config.sheet_fps
	for i in _claws.size():
		var at := _claw_at[i]
		if at < 0.0 or t < at:
			continue
		var c := _claws[i]
		var age := t - at
		var sheet: MeshInstance3D = c.get_node("Sheet")
		if not _claw_up[i]:
			_claw_up[i] = true
			_erupt(i)
		if age > life:
			# só o desenho some: as faíscas e lascas no ar terminam sozinhas
			sheet.visible = false
			c.get_node("Glow").visible = false
			c.get_node("Talons").visible = false
			c.get_node("Ring").visible = false
			(c.get_node("Light") as OmniLight3D).light_energy = 0.0
			_claw_at[i] = -1.0
			continue
		# sobe do chão com um pequeno passo além (ease out back) e assenta
		var rise := clampf(age / 0.14, 0.0, 1.0)
		var ov := 1.0 + 2.2 * pow(rise - 1.0, 3.0) + 1.2 * pow(rise - 1.0, 2.0)
		var h := config.claw_height
		sheet.transform = Transform3D(Basis(Vector3(h, 0, 0), Vector3(0, h, 0), Vector3(0, 0, 1)),
			Vector3(0, -h * (1.0 - ov) * 0.9, 0))
		var live_t := life * 0.55
		var fa: float
		var fb: float
		var bl: float
		var vis := 1.0
		if age < live_t:
			var x := fposmod(age * fps, float(CLAW_LIVE.size() - 1) * 2.0)
			x = x if x <= CLAW_LIVE.size() - 1 else float(CLAW_LIVE.size() - 1) * 2.0 - x   # vaivém
			var k := mini(int(x), CLAW_LIVE.size() - 1)
			fa = CLAW_LIVE[k]
			fb = CLAW_LIVE[mini(k + 1, CLAW_LIVE.size() - 1)]
			bl = x - float(k)
		else:
			var x := clampf((age - live_t) / (life - live_t), 0.0, 1.0) * (CLAW_FADE.size() - 1)
			var k := mini(int(x), CLAW_FADE.size() - 1)
			fa = CLAW_FADE[k]
			fb = CLAW_FADE[mini(k + 1, CLAW_FADE.size() - 1)]
			bl = x - float(k)
			vis = 1.0 - smoothstep(0.75, 1.0, (age - live_t) / (life - live_t))
		var flick := 0.9 + 0.1 * sin(t * 43.0 + i * 2.0)
		sheet.set_instance_shader_parameter("frame_a", fa)
		sheet.set_instance_shader_parameter("frame_b", fb)
		sheet.set_instance_shader_parameter("blend", bl)
		sheet.set_instance_shader_parameter("intensity", 1.25 * vis * flick * smoothstep(0.0, 0.05, age))
		(c.get_node("Light") as OmniLight3D).light_energy = 3.2 * vis * flick * (1.0 - 0.5 * smoothstep(0.0, 0.3, age))
		(c.get_node("Glow") as MeshInstance3D).transparency = 1.0 - 0.9 * vis * smoothstep(0.0, 0.08, age)
		_pose_talons(c, i, age, life, live_t)
		# anel de choque correndo pelo chão no nascer
		var ring: MeshInstance3D = c.get_node("Ring")
		var ru := clampf(age / 0.42, 0.0, 1.0)
		var rr := lerpf(0.8, config.claw_radius * 1.9, 1.0 - pow(1.0 - ru, 3.0))
		ring.scale = Vector3(rr, 1.0, rr)
		ring.transparency = clampf(0.15 + 0.85 * ru * ru, 0.0, 1.0)


## As três unhas de cristal da garra (Talons/T0..T2): saem de dentro do chão em leque, uma logo depois da outra, com um
## pequeno passo além da altura (ease out back), o brilho do nascer apagando para o crepitar; no fim se desfazem de
## baixo para cima (abyss_talon.gdshader, `dissolve`) e afundam um pouco.
func _pose_talons(c: Node3D, ci: int, age: float, life: float, live_t: float) -> void:
	var hh := config.claw_height * TALON_HEIGHT
	var k := 0
	for tn: MeshInstance3D in c.get_node("Talons").get_children():
		var lay: Array = TALON_LAYOUT[k]
		var a := age - TALON_STAGGER * float(k if k != 1 else 0) - (TALON_STAGGER * 0.5 if k == 2 else 0.0)
		var r := clampf(a / TALON_RISE, 0.0, 1.0)
		var ov := 1.0 + 2.7 * pow(r - 1.0, 3.0) + 1.7 * pow(r - 1.0, 2.0)   # ease out back (passa ~8% e volta)
		var sz := hh * float(lay[2])
		var dis := smoothstep(live_t, life, age)
		var sink := sz * (0.85 * (1.0 - clampf(ov, 0.0, 1.2)) + 0.18 * dis)
		var b := Basis.from_euler(Vector3(float(lay[4]), 0.0, float(lay[3]))) \
			* Basis.from_scale(Vector3(1.0, maxf(ov, 0.02), 1.0) * sz)
		tn.transform = Transform3D(b, Vector3(float(lay[0]) * hh, -sink, float(lay[1]) * hh))
		tn.visible = a > 0.0
		var flick := 0.92 + 0.08 * sin(t * 37.0 + float(ci * 3 + k) * 1.7)
		tn.set_instance_shader_parameter("glow", (1.0 + 1.6 * (1.0 - smoothstep(0.0, 0.25, a))) * flick)
		tn.set_instance_shader_parameter("dissolve", dis)
		k += 1


func _erupt(i: int) -> void:
	var c := _claws[i]
	c.visible = true
	(c.get_node("Motes") as GPUParticles3D).restart()
	(c.get_node("Shards") as GPUParticles3D).restart()
	var center := c.global_position
	_shake_local(center, 0.55)
	Sfx.play_at("arcane_hit", center, 0.12, -3.0)
	Sfx.play_at("chop_stone", center, 0.15, -8.0)
	if not deal_damage:
		return
	var targets := _query(center, config.claw_radius + 1.0)
	var picked := DragSlashRules.pick(targets, func(e: Dictionary) -> bool:
		return DragSlashRules.in_claw(center, e.pos, config.claw_radius, float(e.radius)), _hit_claw)
	claw_hit_count += picked.size()
	if not picked.is_empty():
		claw_hit.emit(center, picked.map(func(x: Dictionary) -> Node: return x.node))


## Inimigos vivos perto de `center`: consulta de esfera na camada dos inimigos -> [{id, pos, radius, node}].
func _query(center: Vector3, radius: float) -> Array:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return []
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.transform = Transform3D(Basis.IDENTITY, center + Vector3.UP * 0.8)
	q.collision_mask = ENEMY_MASK
	q.collide_with_areas = false
	q.collide_with_bodies = true
	var out := []
	var seen := {}
	for r in space.intersect_shape(q, 64):
		var b = r.get("collider")
		if b == null or not is_instance_valid(b) or not b.is_in_group("enemies") or bool(b.get("dead")):
			continue
		if seen.has(b.get_instance_id()):
			continue
		seen[b.get_instance_id()] = true
		out.append({"id": b.get_instance_id(), "pos": b.global_position, "radius": float(b.get("radius")), "node": b})
	return out


## Treme a câmera do jogador local conforme a distância (também em quem só vê o golpe de outro).
func _shake_local(center: Vector3, k: float) -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null or config.shake_strength <= 0.0:
		return
	var lp = tree.current_scene.get("player")
	if lp == null or not is_instance_valid(lp) or not lp.is_inside_tree() or not lp.has_method("add_shake"):
		return
	var d := Vector2(lp.global_position.x - center.x, lp.global_position.z - center.z).length()
	var f := 1.0 - clampf(d / config.shake_range, 0.0, 1.0)
	if f > 0.0:
		lp.add_shake(config.shake_strength * k * f * f * (3.0 - 2.0 * f))


# ------------------------------------------------------------------- fim
func _fade_out() -> void:
	_fade_started = true
	state = State.FADE
	_set_drag_emitting(false)
	# espera as garras, o sulco e as últimas faíscas
	var last := 0.0
	for at in _claw_at:
		last = maxf(last, at)
	var wait := maxf(last - t, 0.0) + config.claw_life + 1.0
	wait = maxf(wait, config.groove_life + 0.2)
	get_tree().create_timer(wait).timeout.connect(_finish)


func _finish() -> void:
	if state == State.DONE:
		return
	state = State.DONE
	finished.emit()
	queue_free()


static var _glow_m: StandardMaterial3D
static var _ring_m: StandardMaterial3D
static var _talon_mesh: ArrayMesh


## Anel de choque violeta no chão quando a garra irrompe (a transparência do nó dá o apagado).
static func _ring_mat() -> StandardMaterial3D:
	if _ring_m != null:
		return _ring_m
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = FXEpic._ring_tex()
	m.albedo_color = Color(0.9, 0.35, 1.0) * 1.2
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_m = m
	return m


## Uma unha da garra, altura 1: cone de cristal facetado (seção de TALON_SIDES lados, um pouco achatada de lado) que
## afina até uma ponta afiada e se curva para a frente (+Z) como um gancho. UV.y = 0 na base e 1 na ponta. Feita uma vez.
static func talon_mesh() -> ArrayMesh:
	if _talon_mesh != null:
		return _talon_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)   # faces planas: cristal com quinas
	var rings := 11
	var pts := []   # [anel][lado] -> Vector3
	for j in rings:
		var v := float(j) / (rings - 1)
		var center := Vector3(0.0, v, TALON_CURVE * v * v)
		# o raio afina até a ponta, com uma barriga perto da base
		var rad := TALON_RADIUS * pow(1.0 - v, 1.15) * (1.0 + 0.35 * sin(PI * clampf(v * 2.5, 0.0, 1.0)))
		var ring := []
		for s in TALON_SIDES:
			var ang := TAU * s / TALON_SIDES
			ring.append(center + Vector3(cos(ang) * rad * 0.72, 0.0, sin(ang) * rad))
		pts.append(ring)
	for j in rings - 1:
		var v0 := float(j) / (rings - 1)
		var v1 := float(j + 1) / (rings - 1)
		for s in TALON_SIDES:
			var s1 := (s + 1) % TALON_SIDES
			var u0 := float(s) / TALON_SIDES
			var u1 := float(s + 1) / TALON_SIDES
			var a: Vector3 = pts[j][s]
			var b: Vector3 = pts[j][s1]
			var c: Vector3 = pts[j + 1][s1]
			var d: Vector3 = pts[j + 1][s]
			for tri in [[[a, u0, v0], [d, u0, v1], [c, u1, v1]], [[a, u0, v0], [c, u1, v1], [b, u1, v0]]]:
				for vtx in tri:
					st.set_uv(Vector2(vtx[1], vtx[2]))
					st.add_vertex(vtx[0])
	st.generate_normals()
	_talon_mesh = st.commit()
	return _talon_mesh

## O brilho violeta no chão sob cada garra: disco suave aditivo, deitado (a transparência do nó dá o apagado).
static func _glow_mat() -> StandardMaterial3D:
	if _glow_m != null:
		return _glow_m
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = FXEpic._glow_tex()
	m.albedo_color = Color(0.75, 0.22, 1.0) * 1.6
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shadow_to_opacity = false
	_glow_m = m
	return m
