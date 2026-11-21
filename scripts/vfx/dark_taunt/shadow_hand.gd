class_name ShadowHand
extends Node3D
## Mão sombria (prefab scenes/vfx/dark_taunt/shadow_hand.tscn): um braço espectral que sai do chão, se estica até um
## inimigo e fecha os dedos em volta dele (pelo corpo ou pelas pernas), segura e depois afunda no chão desfazendo
## em fumaça. Sem alvo (`target` nulo) ela sai num ponto vazio do círculo e arranha o ar.
## O corpo é montado aqui, por peças (antebraço, palma, quatro dedos compridos de três falanges com garra e o
## polegar), todas com shadow_hand.gdshader (miolo escuro, borda violeta, pontas magenta). Os dedos são juntas
## (Node3D) que giram: abrir = esticados e afastados, agarrar = cada falange dobra para o lado da palma.
## Etapas (o DarkTauntSkill chama start(); o resto é sozinho, pelo relógio):
##   RISE   o braço desliza para fora do chão, de pé, dedos se mexendo (o shader corta abaixo do chão)
##   REACH  inclina e estica até o alvo, dedos bem abertos
##   GRIP   fecha os dedos (com um tranco) e emite `grabbed` no instante em que fecha
##   HOLD   segura, apertando em pulsos e acompanhando o alvo; arranhar o ar, se não tem alvo
##   SINK   abre um pouco os dedos e afunda no chão, se desfazendo em fumaça
## O alvo morto (ou liberado) no meio do caminho solta na hora: a mão afunda sem esperar.

signal grabbed(hand: ShadowHand, enemy: Node3D)
signal finished(hand: ShadowHand)

const MAT := preload("res://assets/vfx/dark_taunt/shadow_hand_mat.tres")
const SMOKE_COLOR := Color(0.07, 0.02, 0.11, 0.65)
const WISP_COLOR := Color(0.65, 0.25, 1.0)
const GRIP_TIME := 0.16
## Falanges de cada dedo (indicador, médio, anelar, mínimo): comprimento relativo, base na palma (x), abertura.
const FINGERS := [
	{"x": 0.072, "len": 1.0, "splay": 0.16},
	{"x": 0.024, "len": 1.12, "splay": 0.04},
	{"x": -0.024, "len": 1.04, "splay": -0.06},
	{"x": -0.07, "len": 0.84, "splay": -0.2},
]
const PHALANX := [0.13, 0.1, 0.085]   ## comprimento das falanges (m, mão tamanho 1): dedos compridos
const FINGER_R := 0.021
## Escala da mão inteira sobre as medidas acima (palma de ~0,38 m, dedos de ~0,6 m): grande o bastante para fechar
## em volta do corpo de um inimigo do tamanho do herói.
const HAND_SCALE := 1.9

enum State { IDLE, RISE, REACH, GRIP, HOLD, SINK, DONE }

var state := State.IDLE
var target: Node3D = null
var size := 1.0
var rise_time := 0.55
var reach_time := DarkTauntRules.REACH_TIME
var hold_until := 2.0         ## t (s desde start) em que solta (o skill acerta todas pelo mesmo relógio)
var sink_time := 0.7
var glow := 1.0
var t := 0.0
var grip := 0.0               ## 0 = aberta, 1 = fechada (lida pelos testes)
var held := false             ## fechou no alvo (emitiu `grabbed`)

var _arm: Node3D
var _forearm: MeshInstance3D
var _wrist: Node3D
var _joints: Array = []       ## [[junta0, junta1, junta2], ...] dos quatro dedos e o polegar por último
var _meshes: Array[MeshInstance3D] = []
var _st := 0.0
var _rng := RandomNumberGenerator.new()
var _leg_grab := false        ## agarra as pernas (senão o corpo)
var _lean := Vector3.ZERO     ## para onde a mão sem alvo se inclina
var _arm_len := 1.4
var _ground_y := 0.0
var _wisps: CPUParticles3D
var _smoke: CPUParticles3D
var _sink_from := Basis()
var _sink_len := 1.4
var _hand_basis := Basis()
## 0 = dedos para cima (saindo do chão), 1 = dedos dando a volta no corpo do alvo (horizontais, palma nele).
var _wrap := 0.0
var _wrap_sign := 1.0
## Dobra de cada falange para os dedos fecharem em volta do corpo (pelo raio do alvo: corpo grosso, dobra menos).
var _grip_curl := 0.7


func _ready() -> void:
	_build()


## Começa: `t_target` = inimigo a agarrar (ou null), `seed` = variação (dedos, ponto do corpo, inclinação).
func start(t_target: Node3D, hand_size: float, rise: float, hold_end: float, sink: float, intensity: float, seed: int) -> void:
	target = t_target
	_rng.seed = seed
	rise_time = maxf(rise, 0.05)
	hold_until = hold_end
	sink_time = maxf(sink, 0.05)
	glow = intensity
	_leg_grab = _rng.randf() < 0.4
	_wrap_sign = 1.0 if _rng.randf() < 0.5 else -1.0
	_wrap = 0.0
	var enemy_h := 1.7
	if target != null and target.has_method("head_top"):
		enemy_h = float(target.head_top())
	size = hand_size * HAND_SCALE * clampf(enemy_h / 1.7, 0.7, 2.0)
	_wrist.scale = Vector3.ONE * size
	_ground_y = global_position.y
	_lean = Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized() * _rng.randf_range(0.15, 0.4)
	_arm_len = (0.75 + _rng.randf_range(-0.08, 0.12)) * size
	var er := 0.5
	if target != null and target.get("radius") != null:
		er = float(target.get("radius"))
	var finger := (float(PHALANX[0]) + float(PHALANX[1]) + float(PHALANX[2])) * 1.05 * size
	_grip_curl = clampf(finger / maxf(er, 0.15) / 3.0 * 1.7, 0.5, 1.3)
	for m in _meshes:
		m.set_instance_shader_parameter("clip_y", _ground_y)
		m.set_instance_shader_parameter("glow", glow)
		m.set_instance_shader_parameter("dissolve", 0.0)
	t = 0.0
	_st = 0.0
	state = State.RISE
	visible = true
	_place(0.0, Basis.IDENTITY, _arm_len)
	_set_curl(-0.1, 0.0)
	# fumaça escura saindo do chão onde a mão rompe
	_smoke = FXEpic.stream(self, "smoke", SMOKE_COLOR, int(10 * clampf(glow, 0.3, 2.0)) + 2, 1.1, 0.7 * size)
	if _smoke:
		_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_smoke.emission_sphere_radius = 0.25 * size
		_smoke.direction = Vector3.UP
		_smoke.spread = 40.0
		_smoke.initial_velocity_min = 0.2
		_smoke.initial_velocity_max = 0.8
		_smoke.gravity = Vector3(0, 0.3, 0)


func is_done() -> bool:
	return state == State.DONE


## Solta agora (alvo morreu, habilidade cancelada): afunda sem esperar o relógio.
func release_now() -> void:
	if state == State.SINK or state == State.DONE or state == State.IDLE:
		return
	_enter(State.SINK)


func _process(delta: float) -> void:
	if state == State.IDLE or state == State.DONE:
		return
	t += delta
	_st += delta
	if target != null and (not is_instance_valid(target) or target.get("dead") == true):
		target = null
		if state != State.RISE:
			release_now()   # morreu na mão: solta e afunda
	match state:
		State.RISE:
			var u := clampf(_st / rise_time, 0.0, 1.0)
			var e := 1.0 - pow(1.0 - u, 3.0)
			# sobe de pé, saindo de dentro do chão; um balanço de quem vem de outra dimensão
			var sway := Basis(Vector3(1, 0, 0), sin(t * 7.0) * 0.08 * (1.0 - u)) * Basis(Vector3(0, 0, 1), cos(t * 5.0) * 0.06)
			_place(-(1.0 - e) * (_arm_len + 0.45 * size), sway, _arm_len)
			_set_curl(-0.15 + 0.25 * sin(t * 9.0 + 1.0) * (1.0 - u), 0.3)
			if u >= 1.0:
				_enter(State.REACH)
		State.REACH:
			var u := clampf(_st / reach_time, 0.0, 1.0)
			var e := u * u * (3.0 - 2.0 * u)
			var aim := _aim()
			var b := Basis(Quaternion.IDENTITY.slerp(Quaternion((aim[0] as Basis).orthonormalized()), e))
			_place(0.0, b, lerpf(_arm_len, float(aim[1]), e))
			_wrap = e * 0.75 if target != null else 0.0
			_set_curl(-0.35 * e - 0.1, 1.0)   # dedos bem abertos, garras à mostra
			if u >= 1.0:
				_enter(State.GRIP if target != null else State.HOLD)
		State.GRIP:
			var u := clampf(_st / GRIP_TIME, 0.0, 1.0)
			var aim := _aim()
			_place(0.0, aim[0], aim[1])
			# fecha com um tranco: passa um pouco e volta
			grip = clampf(u * 1.15, 0.0, 1.15) - maxf(u - 0.85, 0.0) * 1.0
			_wrap = lerpf(0.75, 1.0, u)
			_set_curl(lerpf(-0.45, _grip_curl * 1.12, grip), 1.0 - u)
			_set_glow(glow * (1.0 + 0.8 * u))
			if u >= 1.0:
				grip = 1.0
				held = true
				grabbed.emit(self, target)
				if _wisps == null:
					_wisps = FXEpic.stream(_wrist, "glow", WISP_COLOR, int(12 * clampf(glow, 0.3, 2.0)) + 2, 0.6, 0.05 * size)
				_enter(State.HOLD)
		State.HOLD:
			if target != null:
				var aim := _aim()
				_place(0.0, aim[0], aim[1])
				# aperta em pulsos, tremendo (segurando algo que luta)
				var squeeze := _grip_curl * (1.0 + 0.1 * sin(t * 11.0) + 0.05 * sin(t * 23.0))
				_set_curl(squeeze, 0.0)
				_set_glow(glow * (1.3 + 0.25 * sin(t * 11.0)))
			else:
				# sem alvo: arranha o ar, inclinado, abrindo e fechando aos trancos
				var lean := Basis(Vector3.UP.cross(_lean).normalized() if _lean.length() > 0.01 else Vector3.RIGHT,
					_lean.length() * (1.0 + 0.25 * sin(t * 3.0)))
				_place(0.0, lean, _arm_len)
				var claw := 0.35 + 0.45 * absf(sin(t * 4.2 + _lean.x * 3.0))
				_set_curl(claw, 0.6 + 0.4 * sin(t * 2.3))
			if t >= hold_until:
				_enter(State.SINK)
		State.SINK:
			var u := clampf(_st / sink_time, 0.0, 1.0)
			var e := u * u
			# volta a ficar de pé e afunda, abrindo os dedos, desfazendo em fumaça
			var b := Basis(Quaternion(_sink_from.orthonormalized()).slerp(Quaternion.IDENTITY, minf(u * 1.6, 1.0)))
			_place(-e * (_sink_len + 0.5 * size), b, _sink_len)
			_wrap = maxf(0.0, 1.0 - u * 2.0) if target != null else 0.0
			_set_curl(lerpf(_grip_curl * 0.7, 0.1, minf(u * 2.0, 1.0)), 0.4)
			for m in _meshes:
				m.set_instance_shader_parameter("dissolve", smoothstep(0.2, 1.0, u))
			_set_glow(glow * (1.0 - 0.6 * u))
			if u >= 1.0:
				_enter(State.DONE)


func _enter(s: State) -> void:
	state = s
	_st = 0.0
	match s:
		State.SINK:
			_sink_from = _arm.basis.orthonormalized()
			_sink_len = _forearm.scale.y
			held = false
			grip = 0.0
			if _wisps:
				FXEpic.stop_stream(_wisps)
				_wisps = null
			if _smoke == null or not is_instance_valid(_smoke):
				_smoke = FXEpic.stream(self, "smoke", SMOKE_COLOR, 8, 1.0, 0.6 * size)
			FXEpic.smoke(_wrist.global_position, SMOKE_COLOR, 6, 0.5 * size, 1.0)
		State.DONE:
			visible = false
			if _smoke:
				FXEpic.stop_stream(_smoke)
				_smoke = null
			finished.emit(self)
		State.HOLD:
			if _smoke and target != null:
				FXEpic.stop_stream(_smoke)   # já saiu: a fumaça do chão para
				_smoke = null


## Para onde o braço aponta e o comprimento dele para a mão chegar no alvo: [Basis do braço (Y = eixo), comprimento].
## A palma encosta no lado do corpo virado para a raiz da mão, com os nós dos dedos no meio desse lado: os dedos
## (horizontais, dando a volta) fecham em volta do corpo ou das pernas.
func _aim() -> Array:
	if target == null or not is_instance_valid(target):
		return [Basis.IDENTITY, _arm_len]
	var h := float(target.head_top()) if target.has_method("head_top") else 1.7
	var er := float(target.get("radius")) if target.get("radius") != null else 0.5
	var at := target.global_position + Vector3.UP * h * (0.25 if _leg_grab else 0.5)
	var to := Vector3(at.x - global_position.x, 0.0, at.z - global_position.z)
	var side := to.normalized() if to.length() > 0.01 else Vector3.FORWARD
	var tangent := Vector3.UP.cross(side).normalized() * _wrap_sign
	# os nós dos dedos ficam 0,215 x tamanho à frente do pulso, ao longo da tangente
	var wrist := at - side * (er + 0.015 * size) - tangent * 0.2 * size * _wrap - Vector3.UP * 0.05 * size
	var d := wrist - global_position
	var len := maxf(d.length(), 0.3)
	var y := d / len
	var x := y.cross(side)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	return [Basis(x, y, z), len]


## Põe o braço: raiz deslocada `slide` m ao longo do eixo (negativo = ainda dentro do chão), orientação `b` (Y =
## eixo do braço, em relação ao mundo) e comprimento `len`. A palma (+Z da mão) vira para o alvo; os dedos (+Y)
## saem para cima no começo e, com `_wrap`, deitam na horizontal dando a volta no corpo dele.
func _place(slide: float, b: Basis, len: float) -> void:
	_arm.global_basis = b.orthonormalized()
	_arm.global_position = global_position + b.y.normalized() * slide
	_forearm.scale = Vector3(size * 0.75, len, size * 0.75)   # suporte do antebraço: escala y = comprimento
	_wrist.position = Vector3(0.0, len, 0.0)
	var up := b.y.normalized()
	var face := Vector3.ZERO
	if target != null and is_instance_valid(target):
		face = target.global_position - _wrist.global_position
		face.y = 0.0
	if face.length() < 0.01:
		face = Vector3(-up.x, 0.0, -up.z) if Vector2(up.x, up.z).length() > 0.05 else Vector3.FORWARD
	face = face.normalized()
	var tangent := Vector3.UP.cross(face).normalized() * _wrap_sign
	var lift := (up * 0.6 + Vector3.UP * 0.4 + face * 0.3).normalized()
	var hy := (lift * (1.0 - _wrap) + (tangent + Vector3.UP * 0.18) * _wrap).normalized()
	var hz := (face - hy * face.dot(hy)).normalized()
	var hx := hy.cross(hz).normalized()
	_hand_basis = Basis(hx, hy, hz)
	_wrist.global_basis = _hand_basis.scaled(Vector3.ONE * size)


## Dobra dos dedos: `c` < 0 esticados para trás (garra aberta), 0 retos, ~1,2 fechados; `twitch` 0..1 = tremor.
func _set_curl(c: float, twitch: float) -> void:
	for i in _joints.size():
		var chain: Array = _joints[i]
		var thumb := i == _joints.size() - 1
		var jitter := twitch * 0.25 * sin(t * (13.0 + i * 2.7) + i)
		for j in chain.size():
			var k: float = [0.8, 1.15, 0.95][j] if not thumb else [0.6, 0.9, 0.9][j]
			(chain[j] as Node3D).rotation.x = (c + jitter) * k
		if not thumb:
			# abertura: quanto mais aberta, mais afastados os dedos
			(chain[0] as Node3D).rotation.z = float(FINGERS[i].splay) * (1.6 - clampf(c, -0.5, 1.2) * 0.9)


func _set_glow(g: float) -> void:
	for m in _meshes:
		m.set_instance_shader_parameter("glow", g)


# ------------------------------------------------------------------ montagem
static var _cyl: CylinderMesh
static var _palm: SphereMesh
static var _seg: CylinderMesh
static var _knuckle: SphereMesh
static var _claw: CylinderMesh


static func _shared() -> void:
	if _cyl != null:
		return
	_cyl = CylinderMesh.new()   # antebraço: mais grosso no chão, afinando até o pulso
	_cyl.top_radius = 0.055
	_cyl.bottom_radius = 0.095
	_cyl.height = 1.0
	_cyl.radial_segments = 10
	_cyl.rings = 3
	_palm = SphereMesh.new()
	_palm.radius = 0.5
	_palm.height = 1.0
	_palm.radial_segments = 10
	_palm.rings = 6
	_seg = CylinderMesh.new()   # falange: altura 1, escalada pelo comprimento
	_seg.top_radius = FINGER_R * 0.85
	_seg.bottom_radius = FINGER_R
	_seg.height = 1.0
	_seg.radial_segments = 6
	_seg.rings = 1
	_knuckle = SphereMesh.new()
	_knuckle.radius = FINGER_R * 1.15
	_knuckle.height = FINGER_R * 2.3
	_knuckle.radial_segments = 6
	_knuckle.rings = 3
	_claw = CylinderMesh.new()
	_claw.top_radius = 0.0
	_claw.bottom_radius = FINGER_R * 0.9
	_claw.height = 0.075
	_claw.radial_segments = 6
	_claw.rings = 1


func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, scl: Vector3, hot := false) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = MAT
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position = pos
	m.scale = scl
	m.set_instance_shader_parameter("tip_from", -10.0 if hot else 10.0)
	parent.add_child(m)
	_meshes.append(m)
	return m


## Um dedo: juntas encadeadas a partir de `base` (no pai), cada falange com o nó do dedo na junta e garra na ponta.
func _finger(parent: Node3D, base: Vector3, lens: Array, thick: float) -> Array:
	var chain := []
	for j in lens.size():
		var joint := Node3D.new()
		joint.position = base
		parent.add_child(joint)
		var l: float = lens[j]
		var tp := thick * (1.0 - j * 0.12)
		_mesh(joint, _knuckle, Vector3.ZERO, Vector3.ONE * tp)
		_mesh(joint, _seg, Vector3(0.0, l * 0.5, 0.0), Vector3(tp, l, tp))
		chain.append(joint)
		parent = joint
		base = Vector3(0.0, l, 0.0)
	# garra curva para o lado da palma (+Z)
	var claw := _mesh(parent, _claw, base + Vector3(0.0, 0.03, 0.008), Vector3.ONE * thick, true)
	claw.rotation.x = 0.4
	return chain


func _build() -> void:
	_shared()
	_arm = Node3D.new()
	_arm.name = "Arm"
	add_child(_arm)
	# o antebraço fica num suporte escalado no comprimento (y); a malha (centro no meio) sobe meio comprimento
	_forearm = MeshInstance3D.new()   # (marcador: a escala de comprimento é a dele)
	_forearm.name = "Forearm"
	_arm.add_child(_forearm)
	_mesh(_forearm, _cyl, Vector3(0.0, 0.5, 0.0), Vector3.ONE)
	_wrist = Node3D.new()
	_wrist.name = "Wrist"
	_arm.add_child(_wrist)
	_mesh(_wrist, _palm, Vector3(0.0, 0.11, 0.0), Vector3(0.2, 0.24, 0.085))
	# quatro dedos compridos, três falanges e garra
	for f in FINGERS:
		var lens := []
		for l in PHALANX:
			lens.append(float(l) * float(f.len))
		_joints.append(_finger(_wrist, Vector3(float(f.x), 0.215, 0.005), lens, 1.0))
	# polegar: sai do lado e da frente da palma, girado para fechar contra os outros
	var tb := Node3D.new()
	tb.position = Vector3(0.09, 0.07, 0.04)
	tb.rotation = Vector3(0.6, -0.25, -0.3)
	_wrist.add_child(tb)
	_joints.append(_finger(tb, Vector3.ZERO, [0.085, 0.07], 1.15))
	visible = false
