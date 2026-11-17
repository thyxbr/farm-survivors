extends Node
## Confere a marcha do cavaleiro (KnightAnim.locomotion_pose): cabeça estável, quadril contra os ombros,
## pé de apoio sem deslizar para o lado, mão cruzando à frente e peso sobre a perna de apoio.
## É uma cena (não um script de tests/unit) porque KnightAnim usa autoloads. Rode com:
##   godot --headless --path . res://tests/gait_test.tscn
## Imprime PASS/FAIL para cada verificação e encerra com código 0 (ok) ou 1 (falhas).

const N := 48
const CASES := [[1.0, 0.0], [1.0, 1.0]]   # [move, run]: andar normal e correndo

var fails := 0


func check(cond: bool, what: String, detail := "") -> void:
	if cond:
		print("PASS  ", what)
	else:
		fails += 1
		print("FAIL  ", what, ": ", detail)


func _ready() -> void:
	for c in CASES:
		var tag := " (move %.1f run %.1f)" % [c[0], c[1]]
		var d := _cycle(c[0], c[1])
		_head_stays_forward(d, tag)
		_pelvis_counters_shoulders(d, tag)
		_stance_foot_no_side_slip(d, tag)
		_hand_crosses_in_front(d, tag)
		_weight_over_stance_leg(d, c[0], c[1], tag)
	_still_pose_untouched()
	print("gait_test: ", "OK" if fails == 0 else "%d falhas" % fails)
	get_tree().quit(0 if fails == 0 else 1)


## Anda as N fases de um ciclo e devolve, por fase, as medidas no mundo.
func _cycle(move: float, run: float) -> Array:
	var model := (load("res://assets/models/knight.glb") as PackedScene).instantiate() as Node3D
	add_child(model)
	var r := KnightAnim.rig(model)
	var out: Array = []
	for i in N:
		var ph := TAU * i / N
		var p := KnightAnim.locomotion_pose(r, ph, move, run)
		KnightAnim.apply(r, p, 1.0)
		KnightAnim.apply(r, p, 1.0)   # segunda vez: a altura do modelo usa as rotações já aplicadas
		var u := fposmod(ph, TAU) / TAU
		var hand: Vector3 = r.hand_l if r.has("hand_l") else _hand_point(model, r.ElbowL)
		var hw: Vector3 = r.ElbowL.global_transform * hand
		out.append({
			"head_yaw": _yaw(r.Head), "head_roll": _roll(r.Head),
			"body_yaw": _yaw(r.Body), "body_roll": _roll(r.Body),
			"pelvis_yaw": _yaw(r.Pelvis),
			"ankle_x": r.AnkleL.global_position.x,
			"stance_l": u < KnightAnim.gait_duty(move, run),
			"body_x": r.Body.position.x,
			"hand_x": hw.x, "hand_z": hw.z,
			"body_x0": r.body_x0,
		})
	model.queue_free()
	return out


## Ponto da mão esquerda no espaço do cotovelo (o rig nu não traz hand_l; ele vem do KnightLook).
func _hand_point(model: Node3D, elbow: Node3D) -> Vector3:
	var mi := model.find_child("ArmL_Hand", true, false) as MeshInstance3D
	return elbow.global_transform.affine_inverse() * (mi.global_transform * mi.get_aabb().get_center())


func _yaw(n: Node3D) -> float:
	return n.global_basis.get_euler(EULER_ORDER_YXZ).y


func _roll(n: Node3D) -> float:
	return n.global_basis.get_euler(EULER_ORDER_YXZ).z


func _range(d: Array, key: String) -> float:
	var lo := INF
	var hi := -INF
	for e in d:
		lo = minf(lo, e[key])
		hi = maxf(hi, e[key])
	return hi - lo


func _head_stays_forward(d: Array, tag: String) -> void:
	var hy := _range(d, "head_yaw")
	var by := _range(d, "body_yaw")
	var hr := _range(d, "head_roll")
	var br := _range(d, "body_roll")
	check(hy <= 0.3 * by and hr <= 0.3 * br, "head_stays_forward" + tag,
		"yaw cabeça %.4f corpo %.4f | roll cabeça %.4f corpo %.4f" % [hy, by, hr, br])


func _pelvis_counters_shoulders(d: Array, tag: String) -> void:
	var a: Dictionary = d[0]
	var b: Dictionary = d[N / 2]
	check(a.pelvis_yaw < -0.03 and a.body_yaw > 0.03 and b.pelvis_yaw > 0.03 and b.body_yaw < -0.03,
		"pelvis_counters_shoulders" + tag,
		"fase 0: pelve %.4f corpo %.4f | fase PI: pelve %.4f corpo %.4f" % [
			a.pelvis_yaw, a.body_yaw, b.pelvis_yaw, b.body_yaw])


func _stance_foot_no_side_slip(d: Array, tag: String) -> void:
	var lo := INF
	var hi := -INF
	for e in d:
		if e.stance_l:
			lo = minf(lo, e.ankle_x)
			hi = maxf(hi, e.ankle_x)
	check(hi - lo <= 0.012, "stance_foot_no_side_slip" + tag, "desliza %.4f m" % (hi - lo))


func _hand_crosses_in_front(d: Array, tag: String) -> void:
	var front: Dictionary = d[0]
	var back: Dictionary = d[0]
	for e in d:
		if e.hand_z > front.hand_z:
			front = e
		if e.hand_z < back.hand_z:
			back = e
	check(absf(front.hand_x) <= absf(back.hand_x) - 0.01, "hand_crosses_in_front" + tag,
		"|x| à frente %.4f atrás %.4f" % [absf(front.hand_x), absf(back.hand_x)])


## Meio do apoio esquerdo = fase duty/2; do direito = fase PI + duty/2 (o direito vai meio ciclo depois).
func _weight_over_stance_leg(d: Array, move: float, run: float, tag: String) -> void:
	var duty := KnightAnim.gait_duty(move, run)
	var il := int(round(duty * 0.5 * N)) % N
	var ir := int(round((0.5 + duty * 0.5) * N)) % N
	var dl: float = d[il].body_x - d[il].body_x0
	var dr: float = d[ir].body_x - d[ir].body_x0
	check(dl > 0.0 and dr < 0.0, "weight_over_stance_leg" + tag,
		"apoio esq. %.4f dir. %.4f (em relação a body_x0)" % [dl, dr])


func _still_pose_untouched() -> void:
	var model := (load("res://assets/models/knight.glb") as PackedScene).instantiate() as Node3D
	add_child(model)
	var r := KnightAnim.rig(model)
	var worst := 0.0
	for i in N:
		var p := KnightAnim.locomotion_pose(r, TAU * i / N, 0.0, 0.0)
		for k in ["hip_twist", "leg_yaw", "head_y", "head_z", "body_shift"]:
			worst = maxf(worst, absf(float(p.get(k, 0.0))))
	model.queue_free()
	check(worst == 0.0, "still_pose_untouched", "maior desvio %.5f" % worst)
