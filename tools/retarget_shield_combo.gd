extends Node
## Gera scripts/player/knight_moves_shield.gd (KnightMovesShield): o combo de espada e escudo tirado de duas
## animações do Mixamo, retargetado para os pivôs do cavaleiro (knight.glb).
##   godot --headless --path . res://tools/retarget_shield_combo.tscn -- <combo.fbx> <giro.fbx> [saida.gd]
## combo.fbx = "One Hand Club Combo" (três golpes); giro.fbx = "Sword And Shield Attack" (golpe girando).
##
## Para cada quadro: o giro do quadril e do peito (Euler YXZ dos ossos Hips e Spine2, relativos à pose de
## descanso) viram spin/twist/body_x/body_z; braços e pernas são resolvidos por mínimos quadrados no próprio
## modelo (Levenberg-Marquardt, partindo do quadro anterior, também de um golpe para o seguinte): o braço (Euler
## do ombro) e o cotovelo procuram as direções do braço e do antebraço e o eixo do cotovelo do Mixamo; depois o
## pulso (giro da arma no antebraço) procura a lâmina; a perna, as direções da coxa e da canela.
## A lâmina do Mixamo é estimada pela mão fechada: do nó do mindinho ao do indicador (o cabo atravessa o
## punho), um pouco inclinada para os dedos. O ombro sai em Euler canônico; giro, quadril e pulso começam cada
## trilha em -PI..PI (KnightAnim.unwind_twist deixa o fim do golpe anterior igual).
##
## Cada golpe é um trecho da animação ([início, acerto, fim] em segundos, e o maior arco do corte desenhado,
## em graus), reamostrado em N quadros uniformes no tempo do jogo com t_mixamo = início + (fim - início) * t^g:
## g põe o acerto do Mixamo em HIT_AT (o instante em que player.gd aplica o dano), sem quebra de velocidade no
## meio do golpe. Conferir depois: tools/shield_combo_flow.tscn (fluidez) e tools/shield_combo_shot.tscn (poses).

const KNIGHT := preload("res://assets/models/knight.glb")
const HIT_AT := 0.42
const N := 41
## [arquivo (0 = combo, 1 = giro), início, acerto, fim] em segundos da animação do Mixamo; maior arco do corte.
const SEGMENTS := [
	[0, 0.2, 0.57, 0.95, 200.0],    # 1: de baixo para cima, do quadril direito para a frente
	[0, 0.95, 1.3, 1.8, 200.0],     # 2: do alto, na diagonal, para a direita
	[0, 1.8, 2.17, 3.0, 220.0],     # 3: do ombro direito ao quadril esquerdo, o corpo acompanha
	[1, 0.03, 0.55, 1.13, 340.0],   # 4: giro de uma volta com a lâmina estendida
]
const BLADE_TO_FINGERS := 0.25   ## quanto a lâmina estimada inclina do eixo do punho para os dedos
const W_HINGE := 0.35            ## peso do eixo do cotovelo (giro do braço no próprio eixo)
const REG := 0.04                ## puxa cada quadro para a solução do anterior (continuidade)

const MixamoClip := preload("res://tools/mixamo_clip.gd")

var _clip: MixamoClip
var _r: Dictionary
var _lk: Dictionary
## Solução do ajuste no último quadro (ombro, cotovelo e pulso; perna e joelho), começando na pose parada.
var _sol := {"arm_r": [-0.15, 0.0, -0.06, -0.2, 0.0], "arm_l": [0.0, 0.0, 0.06, -0.2], "leg_l": [0.0, 0.0, 0.0],
	"leg_r": [0.0, 0.0, 0.0]}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("uso: -- <combo.fbx> <giro.fbx> [saida.gd]")
		get_tree().quit(1)
		return
	var out: String = args[2] if args.size() > 2 else "res://scripts/player/knight_moves_shield.gd"
	var m := KNIGHT.instantiate() as Node3D
	add_child(m)
	_lk = KnightLook.apply(m, {"weapon": "knight_blade", "offhand": "knight_shield"})
	_r = KnightAnim.rig(m)
	var sources := [MixamoClip.new(), MixamoClip.new()]
	for k in 2:
		if not (sources[k] as MixamoClip).load_fbx(args[k], self):
			get_tree().quit(1)
			return
	var tracks := []
	var slashes := []
	for seg in SEGMENTS:
		_clip = sources[seg[0]]
		var res := _track(seg[1], seg[2], seg[3], seg[4])
		tracks.append(res.track)
		slashes.append(res.slash)
		print("golpe %d: g=%.3f  corte em %.2f..%.2f, %.0f graus" % [tracks.size(), res.g, res.slash.at,
			res.slash.at + res.slash.sweep_frac, res.slash.arc])
	_write(out, tracks, slashes)
	print("gravado: ", out)
	get_tree().quit()


func _pt(g: Array, bone: String) -> Vector3:
	return _clip.pt(g, bone)


func _q(g: Array, bone: String) -> Basis:
	return _clip.q(g, bone)


func _dir(a: Vector3, b: Vector3) -> Vector3:
	return (b - a).normalized()


# ------------------------------------------------------------------ um golpe
func _track(t0: float, t_hit: float, t1: float, max_arc: float) -> Dictionary:
	var g := log((t_hit - t0) / (t1 - t0)) / log(HIT_AT)
	var keys := {}
	for j in ["spin", "twist", "body_x", "body_z", "head_x", "head_y", "arm_r", "elbow_r", "wrist_r", "arm_l",
			"elbow_l", "leg_l", "leg_r", "side_l", "side_r", "knee_l", "knee_r"]:
		keys[j] = []
	var tips := []
	var shoulders := []
	var prev_hip := NAN
	var prev_tw := NAN
	# o ajuste parte do quadro anterior, também de um golpe para o seguinte: o fim de um e o começo do outro
	# saem iguais (um recomeço acha outra solução de Euler e o braço estalaria na emenda)
	var arm_r: Array = _sol.arm_r
	var arm_l: Array = _sol.arm_l
	var leg_l: Array = _sol.leg_l
	var leg_r: Array = _sol.leg_r
	for i in N:
		var t := float(i) / float(N - 1)
		var gl := _clip.globals(t0 + (t1 - t0) * pow(t, g))
		# quadril e peito: Euler YXZ, desenrolados para o giro não pular de -PI para PI
		var hip := _q(gl, "Hips").get_euler(EULER_ORDER_YXZ).y
		hip = hip if is_nan(prev_hip) else prev_hip + wrapf(hip - prev_hip, -PI, PI)
		prev_hip = hip
		var c := _q(gl, "Spine2")
		var e := c.get_euler(EULER_ORDER_YXZ)
		var tw: float = hip + wrapf(e.y - hip, -PI, PI) if is_nan(prev_tw) else prev_tw + wrapf(e.y - prev_tw, -PI, PI)
		prev_tw = tw
		var he := (c.inverse() * _q(gl, "Head")).get_euler(EULER_ORDER_YXZ)
		_r.Pelvis.rotation = Vector3(0.0, hip, 0.0)
		_r.Body.rotation = Vector3(e.x, tw - hip, e.z)
		_r.Chest.rotation = Vector3.ZERO
		_r.Head.rotation = Vector3(he.x, he.y, 0.0)
		# braço da espada: ombro (3), cotovelo e pulso
		var blade := _dir(_pt(gl, "RightHandPinky1"), _pt(gl, "RightHandIndex1"))
		blade = (blade + _dir(_pt(gl, "RightHand"), _pt(gl, "RightHandMiddle1")) * BLADE_TO_FINGERS).normalized()
		# primeiro ombro e cotovelo pelo braço do Mixamo (contínuo: o braço quase esticado não salta de solução);
		# depois só o pulso procura a lâmina (ele gira a arma no plano do antebraço, então a lâmina é aproximada)
		var sh: Array = _solve(arm_r.slice(0, 4), _arm_res.bind("R", _dir(_pt(gl, "RightArm"), _pt(gl, "RightForeArm")),
			_dir(_pt(gl, "RightForeArm"), _pt(gl, "RightHand")), _q(gl, "RightForeArm") * Vector3.UP))
		_set_arm("R", sh)
		arm_r = sh + _solve([arm_r[4]], _wrist_res.bind(blade))
		arm_l = _solve(arm_l, _arm_res.bind("L", _dir(_pt(gl, "LeftArm"), _pt(gl, "LeftForeArm")),
			_dir(_pt(gl, "LeftForeArm"), _pt(gl, "LeftHand")), _q(gl, "LeftForeArm") * Vector3.UP))
		leg_l = _solve(leg_l, _leg_res.bind("L", _dir(_pt(gl, "LeftUpLeg"), _pt(gl, "LeftLeg")),
			_dir(_pt(gl, "LeftLeg"), _pt(gl, "LeftFoot"))))
		leg_r = _solve(leg_r, _leg_res.bind("R", _dir(_pt(gl, "RightUpLeg"), _pt(gl, "RightLeg")),
			_dir(_pt(gl, "RightLeg"), _pt(gl, "RightFoot"))))
		_set_arm("R", arm_r)
		_set_arm("L", arm_l)
		_set_leg("L", leg_l)
		_set_leg("R", leg_r)
		tips.append((_lk.tip as Node3D).global_position)
		shoulders.append((_r.ArmR as Node3D).global_position)
		keys.spin.append(hip)
		keys.twist.append(tw)
		keys.body_x.append(e.x)
		keys.body_z.append(e.z)
		keys.head_x.append(he.x)
		keys.head_y.append(he.y)
		keys.arm_r.append(Basis.from_euler(Vector3(arm_r[0], arm_r[1], arm_r[2])).get_euler())
		keys.elbow_r.append(arm_r[3])
		keys.wrist_r.append(arm_r[4])
		keys.arm_l.append(Basis.from_euler(Vector3(arm_l[0], arm_l[1], arm_l[2])).get_euler())
		keys.elbow_l.append(arm_l[3])
		keys.leg_l.append(leg_l[0])
		keys.side_l.append(leg_l[1])
		keys.knee_l.append(leg_l[2])
		keys.leg_r.append(leg_r[0])
		keys.side_r.append(-leg_r[1])
		keys.knee_r.append(leg_r[2])
	_sol = {"arm_r": arm_r, "arm_l": arm_l, "leg_l": leg_l, "leg_r": leg_r}
	# o pulso sai do ajuste da lâmina, que freia de uma vez quando ela alinha no acerto: suaviza um pouco (1-2-1,
	# duas vezes, sem mexer nas pontas, que emendam com os golpes vizinhos)
	for _pass in 2:
		var w: Array = keys.wrist_r.duplicate()
		for k in range(1, N - 1):
			keys.wrist_r[k] = 0.25 * w[k - 1] + 0.5 * w[k] + 0.25 * w[k + 1]
	# a trilha começa com o tronco em -PI..PI (KnightAnim.unwind_twist deixa o fim do golpe anterior assim)
	var off: float = (keys.twist[0] as float) - wrapf(keys.twist[0], -PI, PI)
	for j in ["spin", "twist"]:
		for k in N:
			keys[j][k] -= off
	var w_off: float = (keys.wrist_r[0] as float) - wrapf(keys.wrist_r[0], -PI, PI)   # o pulso também (unwind_twist)
	for k in N:
		keys.wrist_r[k] -= w_off
	return {"track": keys, "slash": _slash(tips, shoulders, max_arc), "g": g}


func _set_arm(side: String, p: Array) -> void:
	(_r["Arm" + side] as Node3D).rotation = Vector3(p[0], p[1], p[2])
	(_r["Elbow" + side] as Node3D).rotation.x = p[3]
	if p.size() > 4:
		(_lk.holder as Node3D).rotation.x = p[4]


func _set_leg(side: String, p: Array) -> void:
	var leg: Node3D = _r["Leg" + side]
	leg.rotation = Vector3(p[0], 0.0, p[1])
	(_r["Knee" + side] as Node3D).rotation.x = p[2]


## Resíduo do braço: direções do braço e do antebraço e o eixo do cotovelo contra os do Mixamo.
func _arm_res(p: Array, side: String, up: Vector3, fore: Vector3, hinge: Vector3) -> PackedFloat32Array:
	_set_arm(side, p)
	var s: Vector3 = (_r["Arm" + side] as Node3D).global_position
	var el: Vector3 = (_r["Elbow" + side] as Node3D).global_position
	var hand: Vector3 = (_r["Elbow" + side] as Node3D).global_transform * (_r["hand_" + side.to_lower()] as Vector3)
	var out := PackedFloat32Array()
	for v in [_dir(s, el) - up, _dir(el, hand) - fore]:
		out.append_array([v.x, v.y, v.z])
	out.append(maxf(0.0, p[3] + 0.03) * 10.0)   # cotovelo não estica para trás
	# giro do braço no próprio eixo: o eixo do cotovelo segue o do Mixamo (vertical na T-pose). Com o braço quase
	# esticado braço e antebraço não o definem, e sem isto o ombro do escudo girava solto de um quadro para outro
	var hx: Vector3 = (_r["Elbow" + side] as Node3D).global_basis.x.normalized().cross(hinge.normalized()) * W_HINGE
	out.append_array([hx.x, hx.y, hx.z])
	return out


## Resíduo do pulso (giro da arma no antebraço): a direção da lâmina contra a estimada do Mixamo.
func _wrist_res(p: Array, blade: Vector3) -> PackedFloat32Array:
	(_lk.holder as Node3D).rotation.x = p[0]
	var h: Node3D = _lk.holder
	var b: Vector3 = _dir(h.global_position, (_lk.tip as Node3D).global_position) - blade
	return PackedFloat32Array([b.x, b.y, b.z])


func _leg_res(p: Array, side: String, thigh: Vector3, shin: Vector3) -> PackedFloat32Array:
	_set_leg(side, p)
	var hip: Vector3 = (_r["Leg" + side] as Node3D).global_position
	var knee: Vector3 = (_r["Knee" + side] as Node3D).global_position
	var ankle: Vector3 = (_r["Ankle" + side] as Node3D).global_position
	var out := PackedFloat32Array()
	for v in [_dir(hip, knee) - thigh, _dir(knee, ankle) - shin]:
		out.append_array([v.x, v.y, v.z])
	out.append(minf(0.0, p[2]) * 10.0)   # joelho não dobra ao contrário
	return out


## Levenberg-Marquardt com jacobiano numérico, partindo de `p0` (o quadro anterior) e puxado de leve para ele.
func _solve(p0: Array, res: Callable) -> Array:
	var p := p0.duplicate()
	var n := p.size()
	var lam := 0.01
	var cost := _cost(res, p, p0)
	for it in 40:
		var r0 := _full(res, p, p0)
		var jac := []
		for k in n:
			var q := p.duplicate()
			q[k] += 0.001
			var r1 := _full(res, q, p0)
			var col := PackedFloat32Array()
			for m in r0.size():
				col.append((r1[m] - r0[m]) / 0.001)
			jac.append(col)
		# (J^T J + lam I) d = -J^T r
		var a := []
		var bv := []
		for x in n:
			var row := []
			for y in n:
				var s := 0.0
				for m in r0.size():
					s += jac[x][m] * jac[y][m]
				row.append(s + (lam if x == y else 0.0))
			a.append(row)
			var sb := 0.0
			for m in r0.size():
				sb -= jac[x][m] * r0[m]
			bv.append(sb)
		var d := _lin_solve(a, bv)
		var q2 := p.duplicate()
		for k in n:
			q2[k] += d[k]
		var c2 := _cost(res, q2, p0)
		if c2 < cost:
			p = q2
			lam = maxf(lam * 0.4, 1e-5)
			if cost - c2 < 1e-9:
				cost = c2
				break
			cost = c2
		else:
			lam *= 4.0
	return p


func _full(res: Callable, p: Array, p0: Array) -> PackedFloat32Array:
	var r: PackedFloat32Array = res.call(p)
	for k in p.size():
		r.append((p[k] - p0[k]) * REG)
	return r


func _cost(res: Callable, p: Array, p0: Array) -> float:
	var s := 0.0
	for v in _full(res, p, p0):
		s += v * v
	return s


func _lin_solve(a: Array, b: Array) -> Array:
	var n := b.size()
	for c in n:
		var piv := c
		for r in range(c + 1, n):
			if absf(a[r][c]) > absf(a[piv][c]):
				piv = r
		var tmp = a[c]
		a[c] = a[piv]
		a[piv] = tmp
		tmp = b[c]
		b[c] = b[piv]
		b[piv] = tmp
		for r in range(c + 1, n):
			var f: float = a[r][c] / a[c][c]
			for k in range(c, n):
				a[r][k] -= f * a[c][k]
			b[r] -= f * b[c]
	var x := []
	x.resize(n)
	for c in range(n - 1, -1, -1):
		var s: float = b[c]
		for k in range(c + 1, n):
			s -= a[c][k] * x[k]
		x[c] = s / a[c][c]
	return x


# ------------------------------------------------------------------ corte desenhado (FXToon.slash)
## Pela ponta da lâmina no espaço do personagem: o trecho rápido do golpe (ponta acima de 50% da maior
## velocidade, em volta do pico) vira um arco em torno do eixo do corpo, na altura do ombro.
func _slash(tips: Array, shoulders: Array, max_arc: float) -> Dictionary:
	var spd := []
	var peak := 0
	for i in tips.size():
		var v := 0.0
		if i > 0:
			v = ((tips[i] as Vector3) - (tips[i - 1] as Vector3)).length()
		spd.append(v)
		if v > spd[peak]:
			peak = i
	var lim: float = spd[peak] * 0.5
	var a := peak
	while a > 1 and spd[a - 1] > lim:
		a -= 1
	var b := peak
	while b < tips.size() - 1 and spd[b + 1] > lim:
		b += 1
	a = maxi(a - 1, 0)
	# o corpo gira em torno do próprio eixo: o centro fica nele, na altura média do ombro
	var center := Vector3.ZERO
	for i in range(a, b + 1):
		center.y += (shoulders[i] as Vector3).y
	center.y /= float(b - a + 1)
	# plano do corte: eixo médio (ponderado pelo quanto a ponta anda); o ângulo é o percorrido em volta dele
	var axis := Vector3.ZERO
	var rad := 0.0
	for i in range(a, b):
		var d0: Vector3 = (tips[i] as Vector3) - center
		var d1: Vector3 = (tips[i + 1] as Vector3) - center
		axis += d0.cross(d1)
		rad += d0.length()
	axis = axis.normalized()
	rad /= float(maxi(b - a, 1))
	var arc := 0.0
	for i in range(a, b):
		var d0: Vector3 = (tips[i] as Vector3) - center
		var d1: Vector3 = (tips[i + 1] as Vector3) - center
		d0 -= axis * d0.dot(axis)
		d1 -= axis * d1.dot(axis)
		arc += d0.signed_angle_to(d1, axis)
	var from: Vector3 = (tips[a] as Vector3) - center
	# arco desenhado no máximo `max_arc`, centrado no trecho percorrido
	if arc > deg_to_rad(max_arc):
		from = from.rotated(axis, (arc - deg_to_rad(max_arc)) * 0.5)
		arc = deg_to_rad(max_arc)
	return {"center": center, "from": from, "axis": axis, "arc": rad_to_deg(arc), "radius": clampf(rad * 1.3, 1.5, 1.95),
		"at": float(a) / float(N - 1), "sweep_frac": float(b - a) / float(N - 1)}


# ------------------------------------------------------------------ saída
func _write(path: String, tracks: Array, slashes: Array) -> void:
	var s := "class_name KnightMovesShield\nextends RefCounted\n"
	s += "## GERADO por tools/retarget_shield_combo.gd a partir do Mixamo (\"One Hand Club Combo\" e \"Sword And\n"
	s += "## Shield Attack\"): não edite à mão, rode a ferramenta de novo. Combo de espada com escudo: três golpes\n"
	s += "## do combo e o giro no fim. Cada trilha tem N quadros uniformes no tempo do golpe (0..1), com o acerto em\n"
	s += "## %.2f; KnightAnim.shield_combo_pose interpola entre eles (Catmull-Rom).\n\n" % HIT_AT
	s += "const N := %d\n\n" % N
	s += "const TRACKS := [\n"
	for tr in tracks:
		s += "\t{\n"
		for j in tr:
			var vals := []
			for v in tr[j]:
				if v is Vector3:
					vals.append("Vector3(%s, %s, %s)" % [_f(v.x), _f(v.y), _f(v.z)])
				else:
					vals.append(_f(v))
			s += "\t\t\"%s\": [%s],\n" % [j, ", ".join(vals)]
		s += "\t},\n"
	s += "]\n\n"
	s += "## Corte desenhado de cada golpe (FXToon.slash): `at` = fração do golpe em que nasce; `sweep_frac` =\n"
	s += "## fração do golpe que a ponta leva para percorrer o arco (vira `sweep` em segundos no jogo).\n"
	s += "const SLASH := [\n"
	for o in slashes:
		s += "\t{\"center\": %s, \"from\": %s, \"axis\": %s, \"arc\": %s, \"radius\": %s, \"at\": %s, \"sweep_frac\": %s},\n" % [
			_v(o.center), _v(o.from), _v(o.axis), _f(o.arc), _f(o.radius), _f(o.at), _f(o.sweep_frac)]
	s += "]\n"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(s)
	f.close()


func _f(x: float) -> String:
	var s := "%.3f" % x
	return "0.0" if s == "-0.000" or s == "0.000" else s


func _v(v: Vector3) -> String:
	return "Vector3(%s, %s, %s)" % [_f(v.x), _f(v.y), _f(v.z)]
