class_name BackWings
extends Node
## Asas do espaço das costas (assets/models/back/<estilo>.glb). Só visual: nada aqui afeta jogabilidade nem rede.
##
## Cada asa (pivôs WingL e WingR do GLB) ganha, em tempo de execução, um esqueleto pequeno (como o CapeRig faz
## com as capas): uma cadeia de SPAN ossos da raiz até perto da ponta, ao longo do braço da asa, e em cada junta
## um osso de "caimento" que dobra as penas de baixo para trás. A asa deixa de ser uma placa rígida: cada junta
## gira um pouco atrasada em relação à anterior, então a batida e o vento correm da raiz até a ponta como onda.
##
## Camadas do movimento, somadas por junta:
##   - pose de velocidade: andar recua e inclina um pouco; correr recua bem mais, deita a asa para trás e as
##     pontas dobram com o arrasto do ar (curva, não reta);
##   - batida lenta parada, em onda da raiz até a ponta;
##   - tremulado do vento ao andar e correr (pontas e penas de baixo), também em onda;
##   - inércia: molas por junta empurradas pela aceleração do peito (passada, arrancar, frear, virar), mais
##     moles na ponta, para as asas acompanharem o corpo com atraso.
## Para comparar com a batida antiga (asa inteira girando no pivô), `legacy = true` antes do setup.

## Batida parada: amplitude (rad) e frequência (Hz). O item pode acelerar com "flap" (asas de fada: 2.5).
const IDLE_AMP := 0.07
const IDLE_HZ := 0.28
## Velocidades de referência (m/s): andar e correr do jogador (Player.WALK_SPEED, SPRINT_SPEED).
const WALK_SPEED := 5.2
const SPRINT_SPEED := 8.6

## Ossos ao longo da envergadura (juntas da raiz até 85% da asa).
const SPAN := 5
## Ângulo da asa aberta para trás na modelagem (tools/blender/back.py, seraph_wing: sw = 24°).
const MODEL_SWEEP := deg_to_rad(24.0)

## Pose de velocidade na raiz (rad): recuo em torno do eixo de pé e deitar para trás.
const SWEEP_WALK := 0.12
const SWEEP_RUN := 0.22
const PITCH_WALK := 0.05
const PITCH_RUN := 0.16
## Arrasto: cada junta depois da raiz recua mais um pouco (rad, multiplicado pela distância à raiz). Os giros
## das juntas se somam até a ponta (com o recuo da raiz e os 24° da modelagem), então valores pequenos aqui já
## curvam bastante: acima disso a asa fecha nas costas e as penas atravessam umas às outras.
const DRAG_WALK := 0.02
const DRAG_RUN := 0.045
## Penas de baixo levadas para trás pelo ar (rad).
const DRAPE_WALK := 0.06
const DRAPE_RUN := 0.15

## Batida antiga (legacy): recuo e tremida da asa inteira.
const OLD_RUN_SWEEP := 0.34
const OLD_RUN_AMP := 0.05
const OLD_RUN_HZ := 2.1
const OLD_RUN_SPEED := 5.0

## Malhas com pesos já calculados, por malha de origem e lado.
static var _cache := {}

var legacy := false
## Laboratório (tools/wing_lab.gd): asas criadas enquanto isto vale usam a batida antiga.
static var legacy_default := false

var _l: Node3D
var _r: Node3D
var _rest_l: Basis
var _rest_r: Basis
var _t := 0.0
var _walk := 0.0
var _run := 0.0
var _flap := 1.0
## 1 = penas e membranas que dobram; menos para asas duras (cristal, mecânica) e de borboleta.
var _flex := 1.0
## Quanto a pose de velocidade (recuo, deitar, caimento) vale; o item pode mudar com "wing_pose".
var _pose := 1.0
var _last := Vector3.ZERO
var _has_last := false
var _vel := Vector3.ZERO
var _acc := Vector3.ZERO
## [{skel, side, S: [osso], D: [osso], span_axis, spring: [{sw, sv, lf, lv, dr, dv}]}]
var _wings: Array = []


## Liga a animação aos pivôs dentro de `root` (a instância do GLB) e cria o efeito do item.
func setup(root: Node3D, item: Dictionary) -> void:
	legacy = legacy or legacy_default
	_l = root.find_child("WingL", true, false) as Node3D
	_r = root.find_child("WingR", true, false) as Node3D
	if _l:
		_rest_l = _l.transform.basis
	if _r:
		_rest_r = _r.transform.basis
	_t = randf() * 10.0     # cada personagem bate num tempo diferente
	_flap = float(item.get("flap", 1.0))
	var style: String = item.get("style", "")
	var flex_default := 1.0
	if style in ["b_crystal", "b_mech"]:
		flex_default = 0.35
	elif style == "b_fairy":
		flex_default = 0.15     # membrana dura: bate quase inteira, sem dobrar lóbulo sobre lóbulo
	_flex = float(item.get("wing_flex", flex_default))
	_pose = float(item.get("wing_pose", 1.0))
	if not legacy:
		for side in [[_l, 1.0], [_r, -1.0]]:
			if side[0] != null:
				var w := _rig(side[0], side[1])
				if not w.is_empty():
					_wings.append(w)
	var kind: String = item.get("back_fx", "")
	# o pivô fica na raiz da asa; o meio da asa está para fora, um pouco acima e atrás dele
	for side in [[_l, 1.0], [_r, -1.0]]:
		var wing: Node3D = side[0]
		if wing == null:
			continue
		var fx := BackFx.make(kind, Vector3(0.48 * side[1], 0.12, -0.2), Vector3(0.32, 0.4, 0.05))
		if fx:
			wing.add_child(fx)


func _process(delta: float) -> void:
	var host := get_parent() as Node3D
	if host == null or (_l == null and _r == null) or delta <= 0.0:
		return
	_t += delta
	var p := host.global_position
	var vel := Vector3.ZERO
	if _has_last:
		vel = (p - _last) / delta
	_last = p
	_has_last = true
	if legacy:
		_legacy(vel, delta)
		return
	# velocidade e aceleração suavizadas; a aceleração vai para o espaço do personagem (frente +Z, cima +Y)
	var prev := _vel
	_vel = _vel.lerp(vel, 1.0 - exp(-14.0 * delta))
	_acc = _acc.lerp((_vel - prev) / delta, 1.0 - exp(-10.0 * delta))
	var speed := Vector2(_vel.x, _vel.z).length()
	_walk = lerpf(_walk, clampf(speed / WALK_SPEED, 0.0, 1.0), 1.0 - exp(-5.0 * delta))
	_run = lerpf(_run, clampf((speed - WALK_SPEED) / (SPRINT_SPEED - WALK_SPEED - 0.4), 0.0, 1.0), 1.0 - exp(-4.0 * delta))
	var acc_l := host.global_transform.basis.inverse() * _acc
	var weather := get_node_or_null("/root/Weather")
	var wind: float = weather.visual_wind() if weather != null else 0.0
	for w in _wings:
		_animate(w, acc_l, wind, delta)


## Pose de cada junta: alvo (velocidade + batida + vento) mais a mola da inércia.
func _animate(w: Dictionary, acc: Vector3, wind: float, delta: float) -> void:
	var skel: Skeleton3D = w.skel
	var s: float = w.side
	var hz := IDLE_HZ * _flap
	var still := 1.0 - _walk
	var move := _walk * _pose
	var run := _run * _pose
	var flex := _flex
	var flutter_amp := (0.025 * move + 0.055 * run + 0.04 * wind) * flex
	var flutter_hz := 2.2 + 2.6 * run
	var dt := minf(delta, 1.0 / 30.0)
	for i in SPAN:
		var t := float(i) / (SPAN - 1)            # 0 na raiz, 1 na ponta
		var lag := i * 0.75                        # onda: cada junta atrasada em relação à anterior
		var beat := sin(_t * TAU * hz - lag)
		var sweep := 0.0
		var lift := 0.0
		var pitch := 0.0
		if i == 0:
			sweep = beat * IDLE_AMP * (0.5 + 0.5 * still) + move * SWEEP_WALK + run * (SWEEP_RUN - SWEEP_WALK)
			lift = sin(_t * TAU * hz - 0.9) * 0.04 * (0.4 + 0.6 * still) - run * 0.06
			pitch = -(move * PITCH_WALK + run * (PITCH_RUN - PITCH_WALK))
		else:
			# a batida curva a asa (meio vai, ponta vem depois) em vez de girar a placa inteira
			sweep = beat * IDLE_AMP * 0.55 * flex * (0.6 + 0.4 * still)
			sweep += (move * DRAG_WALK + run * (DRAG_RUN - DRAG_WALK)) * t * flex
			sweep += sin(_t * TAU * flutter_hz - lag * 1.3 + s) * flutter_amp * t
			lift = sin(_t * TAU * hz - 0.9 - lag) * 0.035 * flex
			lift += sin(_t * TAU * flutter_hz * 0.7 - lag + 1.1) * flutter_amp * 0.5 * t
			lift -= run * 0.03 * t * flex          # pontas abaixam um pouco na corrida
		var drape := (move * DRAPE_WALK + run * (DRAPE_RUN - DRAPE_WALK)) * (0.55 + 0.45 * t) * flex
		drape += sin(_t * TAU * flutter_hz * 1.15 - lag * 1.1 + 0.6 * s) * flutter_amp * 1.4 * (0.4 + 0.6 * t)
		drape += sin(_t * TAU * hz - lag - 1.6) * 0.03 * still * flex

		# inércia: o peito acelera, a asa fica para trás (molas mais moles e mais fortes na ponta)
		var sp: Dictionary = w.spring[i]
		var k := lerpf(90.0, 38.0, t)
		var c := lerpf(13.0, 6.5, t)
		var gain := lerpf(0.010, 0.022, t) * (flex if i > 0 else 1.0)
		var f_sw := acc.z * gain + acc.x * s * gain * 0.7        # arrancar recua, frear joga para a frente; curva
		var f_lf := -acc.y * gain * 1.4                           # passada: corpo sobe, ponta fica embaixo
		var f_dr := acc.z * gain * 1.2
		sp.sv += (f_sw * k - k * sp.sw - c * sp.sv) * dt
		sp.sw += sp.sv * dt
		sp.lv += (f_lf * k - k * sp.lf - c * sp.lv) * dt
		sp.lf += sp.lv * dt
		sp.dv += (f_dr * k - k * sp.dr - c * sp.dv) * dt
		sp.dr += sp.dv * dt
		sweep += clampf(sp.sw, -0.35, 0.35)
		lift += clampf(sp.lf, -0.3, 0.3)
		drape += clampf(sp.dr, -0.3, 0.3)

		# eixos no espaço do pivô: positivo recua (em pé), sobe a ponta (normal da asa), deita para trás (X)
		var q := Quaternion(Vector3.UP * s, sweep) * Quaternion(Vector3.BACK * s, lift) * Quaternion(Vector3.RIGHT, pitch)
		skel.set_bone_pose_rotation(w.S[i], q)
		skel.set_bone_pose_rotation(w.D[i], Quaternion(w.span_axis, drape))


## Batida antiga, para comparar: a asa inteira gira no pivô.
func _legacy(vel: Vector3, delta: float) -> void:
	var speed := Vector2(vel.x, vel.z).length()
	_run = lerpf(_run, clampf(speed / OLD_RUN_SPEED, 0.0, 1.0), 1.0 - exp(-5.0 * delta))
	var hz := IDLE_HZ * _flap
	var beat := sin(_t * TAU * hz)
	var sweep := beat * IDLE_AMP * (1.0 - 0.6 * _run) + _run * OLD_RUN_SWEEP + sin(_t * TAU * OLD_RUN_HZ) * OLD_RUN_AMP * _run
	var lift := sin(_t * TAU * hz - 0.9) * 0.045 - _run * 0.10
	if _l:
		_l.transform.basis = Basis(Vector3.UP, sweep) * Basis(Vector3.BACK, lift) * _rest_l
	if _r:
		_r.transform.basis = Basis(Vector3.UP, -sweep) * Basis(Vector3.BACK, -lift) * _rest_r


# ------------------------------------------------------------------ montagem do esqueleto
## Põe a malha da asa (filha do pivô) num Skeleton3D com a cadeia da envergadura e os ossos de caimento.
func _rig(piv: Node3D, s: float) -> Dictionary:
	var mi: MeshInstance3D = null
	for c in piv.get_children():
		if c is MeshInstance3D:
			mi = c
			break
	if mi == null or mi.mesh == null:
		return {}
	var key := "%d:%d" % [mi.mesh.get_instance_id(), int(s)]
	if not _cache.has(key):
		_cache[key] = _build(mi.mesh, s)
	var data: Dictionary = _cache[key]
	var skel := Skeleton3D.new()
	skel.name = "WingSkeleton"
	skel.transform = mi.transform      # a malha fica na origem do esqueleto: pesos e ossos no espaço dela
	for b in data.bones:
		var bi := skel.add_bone(b.name)
		skel.set_bone_parent(bi, b.parent)
		skel.set_bone_rest(bi, b.rest)
		skel.set_bone_pose(bi, b.rest)
	piv.add_child(skel)
	piv.remove_child(mi)
	skel.add_child(mi)
	mi.transform = Transform3D.IDENTITY
	mi.mesh = data.mesh
	mi.skin = data.skin
	mi.skeleton = NodePath("..")
	var spring: Array = []
	for i in SPAN:
		spring.append({"sw": 0.0, "sv": 0.0, "lf": 0.0, "lv": 0.0, "dr": 0.0, "dv": 0.0})
	return {"skel": skel, "side": s, "S": data.S, "D": data.D, "span_axis": data.span_axis, "spring": spring}


## Esqueleto e pesos de uma asa. s = 1 esquerda (+X), -1 direita. Espaço da malha = espaço do pivô.
static func _build(src: Mesh, s: float) -> Dictionary:
	var U := Vector3(s * cos(MODEL_SWEEP), 0.0, -sin(MODEL_SWEEP))    # envergadura (costas = -Z)
	# perfil por fatia de envergadura: topo (o braço) e fundo (pontas das penas)
	const BINS := 24
	var umax := 0.05
	var all: Array = []
	for si in src.get_surface_count():
		var vs: PackedVector3Array = src.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
		all.append(vs)
		for p in vs:
			umax = maxf(umax, p.dot(U))
	var top: Array = []
	var bot: Array = []
	for b in BINS:
		top.append(-INF)
		bot.append(INF)
	for vs: PackedVector3Array in all:
		for p in vs:
			var b := clampi(int(p.dot(U) / umax * BINS), 0, BINS - 1)
			top[b] = maxf(top[b], p.y)
			bot[b] = minf(bot[b], p.y)
	for b in BINS:     # fatia vazia: copia a vizinha
		if top[b] == -INF:
			top[b] = top[b - 1] if b > 0 else 0.0
			bot[b] = bot[b - 1] if b > 0 else 0.0

	# juntas ao longo da envergadura, na altura do braço (perto do topo de cada fatia)
	var joints: Array[Vector3] = []
	var ju: Array[float] = []
	for i in SPAN:
		var u := umax * 0.85 * float(i) / (SPAN - 1)
		var b := clampi(int(u / umax * BINS), 0, BINS - 1)
		var y: float = 0.0 if i == 0 else lerpf(bot[b], top[b], 0.82)
		joints.append(U * u + Vector3.UP * y)
		ju.append(u)
	var bones: Array = []
	var S: Array = []
	var D: Array = []
	var parent_pos := Vector3.ZERO
	var parent := -1
	for i in SPAN:
		S.append(bones.size())
		bones.append({"name": "Span%d" % i, "parent": parent, "rest": Transform3D(Basis.IDENTITY, joints[i] - parent_pos)})
		parent = bones.size() - 1
		parent_pos = joints[i]
	for i in SPAN:
		D.append(bones.size())
		bones.append({"name": "Drape%d" % i, "parent": S[i], "rest": Transform3D.IDENTITY})
	var skin := Skin.new()
	for i in bones.size():
		var g: Vector3 = joints[i] if i < SPAN else joints[i - SPAN]
		skin.add_bind(i, Transform3D(Basis.IDENTITY, -g))

	var mesh := ArrayMesh.new()
	for si in src.get_surface_count():
		var arrays := src.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bi := PackedInt32Array()
		var bw := PackedFloat32Array()
		bi.resize(verts.size() * 4)
		bw.resize(verts.size() * 4)
		for vi in verts.size():
			var q := verts[vi]
			var u := clampf(q.dot(U), 0.0, ju[SPAN - 1])
			var j0 := 0
			while j0 < SPAN - 2 and u > ju[j0 + 1]:
				j0 += 1
			var f := clampf((u - ju[j0]) / (ju[j0 + 1] - ju[j0]), 0.0, 1.0)
			f = f * f * (3.0 - 2.0 * f)
			# caimento: 0 no braço, 1 nas pontas de baixo da fatia
			var b := clampi(int(clampf(q.dot(U), 0.0, umax) / umax * BINS), 0, BINS - 1)
			var arm: float = lerpf(bot[b], top[b], 0.82)
			var d := clampf((arm - q.y) / maxf(arm - bot[b], 0.05), 0.0, 1.0)
			d = d * d * (3.0 - 2.0 * d)
			var slot := vi * 4
			for pair in [[j0, 1.0 - f], [j0 + 1, f]]:
				bi[slot] = S[pair[0]]
				bw[slot] = pair[1] * (1.0 - d)
				bi[slot + 1] = D[pair[0]]
				bw[slot + 1] = pair[1] * d
				slot += 2
		arrays[Mesh.ARRAY_BONES] = bi
		arrays[Mesh.ARRAY_WEIGHTS] = bw
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(si, src.surface_get_material(si))
	return {"mesh": mesh, "skin": skin, "bones": bones, "S": S, "D": D, "span_axis": (U * s).normalized()}
