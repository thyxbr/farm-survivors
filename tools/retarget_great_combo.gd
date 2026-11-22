extends "res://tools/retarget_shield_combo.gd"
## Gera scripts/player/knight_moves_great.gd (KnightMovesGreat): o combo da montante (espada de duas mãos) tirado do
## "Two Hand Club Combo" do Mixamo, retargetado para os pivôs do cavaleiro (knight.glb).
##   godot --headless --path . res://tools/retarget_great_combo.tscn -- <two_hand_club_combo.fbx> [saida.gd]
##
## O corpo (giro do quadril e do peito, inclinação, cabeça e pernas) sai como em tools/retarget_shield_combo.gd. Os
## braços não: na montante as duas mãos vão por IK até o cabo (KnightAnim._tool_ik), então a trilha leva a trajetória
## da arma no espaço do modelo, como KnightMoves.GREAT_GUARD: `end` = mão esquerda (a de baixo, perto do pomo), `dir` =
## lâmina (do pomo para a ponta) e `edge` = para onde o gume aponta. No Mixamo a direita também fica acima da esquerda.
## A pegada do Mixamo é medida nas duas mãos: o cabo atravessa o punho (do mindinho ao indicador, um pouco inclinado
## para os dedos), o gume aponta para os nós dos dedos (do pulso à base do dedo médio) e o centro do cabo fica entre as
## palmas, levado para o cavaleiro pelo meio dos ombros na escala do braço dele.
##
## Cada golpe é um trecho da animação reamostrado como no combo com escudo: o acerto do Mixamo cai em HIT_AT.

## [início, acerto, fim] em segundos do "Two Hand Club Combo"; maior arco do corte desenhado (graus).
const GREAT_SEGMENTS := [
	[1.0, 1.58, 2.3, 200.0],    # 1: de cima da cabeça para baixo, pela frente
	[2.3, 2.9, 3.45, 220.0],    # 2: diagonal do ombro direito para baixo e para a esquerda
	[3.45, 3.96, 4.6, 300.0],   # 3: varrida na horizontal da esquerda para a direita
]
const GREAT_WEAPON := "iron_zweihander"

var _scale := 1.0
var _blade_len := 1.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 1:
		push_error("uso: -- <two_hand_club_combo.fbx> [saida.gd]")
		get_tree().quit(1)
		return
	var out: String = args[1] if args.size() > 1 else "res://scripts/player/knight_moves_great.gd"
	var m := KNIGHT.instantiate() as Node3D
	add_child(m)
	_lk = KnightLook.apply(m, {"weapon": GREAT_WEAPON})
	_r = KnightAnim.rig(m)
	_clip = MixamoClip.new()
	if not _clip.load_fbx(args[0], self):
		get_tree().quit(1)
		return
	_blade_len = (_lk.tip as Node3D).global_position.distance_to((_lk.holder as Node3D).global_position)
	# escala do braço: ombro-cotovelo-mão do cavaleiro contra ombro-cotovelo-palma do Mixamo
	var g0 := _clip.globals(0.0)
	var arm_k: float = (_r.ArmR as Node3D).global_position.distance_to((_r.ElbowR as Node3D).global_position) \
		+ (_r.hand_r as Vector3).length()
	var arm_m := _pt(g0, "RightArm").distance_to(_pt(g0, "RightForeArm")) + _pt(g0, "RightForeArm").distance_to(_palm(g0, "Right"))
	_scale = arm_k / arm_m
	print("escala do braço %.3f, lâmina %.2f m" % [_scale, _blade_len])
	var tracks := []
	var slashes := []
	for seg in GREAT_SEGMENTS:
		var res := _great_track(seg[0], seg[1], seg[2], seg[3])
		tracks.append(res.track)
		slashes.append(res.slash)
		print("golpe %d: g=%.3f  corte em %.2f..%.2f, %.0f graus  mão mais longe do alcance %.2f m" % [tracks.size(),
			res.g, res.slash.at, res.slash.at + res.slash.sweep_frac, res.slash.arc, res.miss])
	_write_great(out, tracks, slashes)
	print("gravado: ", out)
	get_tree().quit()


func _palm(g: Array, side: String) -> Vector3:
	return (_pt(g, side + "Hand") + _pt(g, side + "HandMiddle1")) * 0.5


# ------------------------------------------------------------------ um golpe
func _great_track(t0: float, t_hit: float, t1: float, max_arc: float) -> Dictionary:
	var g := log((t_hit - t0) / (t1 - t0)) / log(HIT_AT)
	var keys := {}
	for j in ["spin", "twist", "body_x", "body_z", "head_x", "head_y", "leg_l", "leg_r", "side_l", "side_r", "knee_l",
			"knee_r", "end", "dir", "edge"]:
		keys[j] = []
	var shoulders := []
	var prev_hip := NAN
	var prev_tw := NAN
	var leg_l: Array = _sol.leg_l
	var leg_r: Array = _sol.leg_r
	var miss := 0.0
	for i in N:
		var t := float(i) / float(N - 1)
		var gl := _clip.globals(t0 + (t1 - t0) * pow(t, g))
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
		leg_l = _solve(leg_l, _leg_res.bind("L", _dir(_pt(gl, "LeftUpLeg"), _pt(gl, "LeftLeg")),
			_dir(_pt(gl, "LeftLeg"), _pt(gl, "LeftFoot"))))
		leg_r = _solve(leg_r, _leg_res.bind("R", _dir(_pt(gl, "RightUpLeg"), _pt(gl, "RightLeg")),
			_dir(_pt(gl, "RightLeg"), _pt(gl, "RightFoot"))))
		_set_leg("L", leg_l)
		_set_leg("R", leg_r)
		# pegada: cabo pelo punho das duas mãos, gume para os nós dos dedos
		var axis := Vector3.ZERO
		var knuckles := Vector3.ZERO
		for side in ["Right", "Left"]:
			axis += _dir(_pt(gl, side + "HandPinky1"), _pt(gl, side + "HandIndex1"))
			axis += _dir(_pt(gl, side + "Hand"), _pt(gl, side + "HandMiddle1")) * BLADE_TO_FINGERS
			knuckles += _dir(_pt(gl, side + "Hand"), _pt(gl, side + "HandMiddle1"))
		var dir := axis.normalized()
		var edge := (knuckles - dir * knuckles.dot(dir)).normalized()
		# centro do cabo entre as palmas, do meio dos ombros do Mixamo para o do cavaleiro
		var mid_m := (_pt(gl, "RightArm") + _pt(gl, "LeftArm")) * 0.5
		var mid_k := ((_r.ArmR as Node3D).global_position + (_r.ArmL as Node3D).global_position) * 0.5
		var center := mid_k + ((_palm(gl, "Right") + _palm(gl, "Left")) * 0.5 - mid_m) * _scale
		var end := center - dir * (KnightMoves.GREAT_GRIP * 0.5)
		for side in ["l", "r"]:
			var target := end + (dir * KnightMoves.GREAT_GRIP if side == "r" else Vector3.ZERO)
			var gs := KnightAnim.grip_solve(_r, side, target, dir, KnightMoves.TOOL_POLE_R if side == "r" else KnightMoves.TOOL_POLE_L)
			miss = maxf(miss, float(gs.get("miss", 0.0)))
		shoulders.append((_r.ArmR as Node3D).global_position)
		keys.spin.append(hip)
		keys.twist.append(tw)
		keys.body_x.append(e.x)
		keys.body_z.append(e.z)
		keys.head_x.append(he.x)
		keys.head_y.append(he.y)
		keys.leg_l.append(leg_l[0])
		keys.side_l.append(leg_l[1])
		keys.knee_l.append(leg_l[2])
		keys.leg_r.append(leg_r[0])
		keys.side_r.append(-leg_r[1])
		keys.knee_r.append(leg_r[2])
		keys.end.append(end)
		keys.dir.append(dir)
		keys.edge.append(edge)
	_sol = {"arm_r": _sol.arm_r, "arm_l": _sol.arm_l, "leg_l": leg_l, "leg_r": leg_r}
	# a pegada medida nos dedos treme um pouco: suaviza (1-2-1, sem mexer nas pontas, que emendam com os vizinhos)
	for j in ["end", "dir", "edge"]:
		for _pass in 2:
			var w: Array = keys[j].duplicate()
			for k in range(1, N - 1):
				keys[j][k] = 0.25 * w[k - 1] + 0.5 * w[k] + 0.25 * w[k + 1]
		if j != "end":
			for k in N:
				keys[j][k] = (keys[j][k] as Vector3).normalized()
	# o gume aponta para onde a ponta corre no acerto (lâmina de dois gumes: só o lado do que se vê)
	var hit_i := roundi(HIT_AT * (N - 1))
	var tip_v: Vector3 = _tip(keys, hit_i + 1) - _tip(keys, hit_i - 1)
	if (keys.edge[hit_i] as Vector3).dot(tip_v) < 0.0:
		for k in N:
			keys.edge[k] = -(keys.edge[k] as Vector3)
	var off: float = (keys.twist[0] as float) - wrapf(keys.twist[0], -PI, PI)
	for j in ["spin", "twist"]:
		for k in N:
			keys[j][k] -= off
	var tips := []
	for k in N:
		tips.append(_tip(keys, k))
	return {"track": keys, "slash": _slash(tips, shoulders, max_arc), "g": g, "miss": miss}


## Ponta da lâmina no quadro `k`: a mão direita (GREAT_GRIP acima da esquerda) mais a lâmina inteira.
func _tip(keys: Dictionary, k: int) -> Vector3:
	var d: Vector3 = keys.dir[k]
	return (keys.end[k] as Vector3) + d * (KnightMoves.GREAT_GRIP + _blade_len)


# ------------------------------------------------------------------ saída
func _write_great(path: String, tracks: Array, slashes: Array) -> void:
	var s := "class_name KnightMovesGreat\nextends RefCounted\n"
	s += "## GERADO por tools/retarget_great_combo.gd a partir do Mixamo (\"Two Hand Club Combo\"): não edite à mão, rode\n"
	s += "## a ferramenta de novo. Combo da montante (espada de duas mãos), três golpes. Cada trilha tem N quadros\n"
	s += "## uniformes no tempo do golpe (0..1), com o acerto em HIT_AT: o corpo como em KnightMovesShield e a arma\n"
	s += "## (`end`, `dir`, `edge`, como KnightMoves.GREAT_GUARD) no espaço do modelo, para o IK das duas mãos.\n"
	s += "## KnightAnim.great_pose interpola entre eles (Catmull-Rom).\n\n"
	s += "const N := %d\n" % N
	s += "const HIT_AT := %s\n\n" % _f(HIT_AT)
	s += "const TRACKS := [\n"
	for tr in tracks:
		s += "\t{\n"
		for j in tr:
			var vals := []
			for v in tr[j]:
				vals.append(_v(v) if v is Vector3 else _f(v))
			s += "\t\t\"%s\": [%s],\n" % [j, ", ".join(vals)]
		s += "\t},\n"
	s += "]\n\n"
	s += "## Corte desenhado de cada golpe (FXToon.great_slash): `at` = fração do golpe em que nasce; `sweep_frac` =\n"
	s += "## fração do golpe que a ponta leva para percorrer o arco (vira `sweep` em segundos no jogo).\n"
	s += "const SLASH := [\n"
	for o in slashes:
		s += "\t{\"center\": %s, \"from\": %s, \"axis\": %s, \"arc\": %s, \"radius\": %s, \"at\": %s, \"sweep_frac\": %s},\n" % [
			_v(o.center), _v(o.from), _v(o.axis), _f(o.arc), _f(o.radius), _f(o.at), _f(o.sweep_frac)]
	s += "]\n"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(s)
	f.close()
