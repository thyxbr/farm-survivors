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
		_head_steady_with_smoothing(c[0], c[1], tag)
	_still_pose_untouched()
	_attack_resets_leg_yaw()
	_attack_keeps_own_head()
	_stance_foot_no_back_slip(5.2, 0.0)
	_stance_foot_no_back_slip(2.5, 0.0)
	_stance_foot_no_back_slip(7.5, 1.0)
	_bow_draw_eases_hips()
	_leans_with_speed(1.0, 0.0, 0.15)
	_leans_with_speed(1.0, 1.0, 0.25)
	_foot_lands_under_body(1.0, 0.0)
	_foot_lands_under_body(1.0, 1.0)
	_spine_curves(1.0, 0.0)
	_spine_curves(1.0, 1.0)
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
			"body_yaw": _yaw(r.Chest), "body_roll": _roll(r.Chest),
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
	check(by >= 0.01 and br >= 0.01 and hy <= 0.3 * by and hr <= 0.3 * br, "head_stays_forward" + tag,
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
	check(hi - lo <= 0.002, "stance_foot_no_side_slip" + tag, "desliza %.4f m" % (hi - lo))


func _hand_crosses_in_front(d: Array, tag: String) -> void:
	var front: Dictionary = d[0]
	var back: Dictionary = d[0]
	for e in d:
		if e.hand_z > front.hand_z:
			front = e
		if e.hand_z < back.hand_z:
			back = e
	check(absf(front.hand_x) <= absf(back.hand_x) - 0.055, "hand_crosses_in_front" + tag,
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
	var rest := KnightAnim.rest_pose()
	var worst := 0.0
	var worst_key := ""
	for i in N:
		var p := KnightAnim.locomotion_pose(r, TAU * i / N, 0.0, 0.0)
		for k in KnightAnim.POSE_KEYS:
			var dev := 0.0
			if p[k] is Vector3:
				dev = (p[k] - rest[k]).length()
			else:
				dev = absf(float(p[k]) - float(rest[k]))
			if dev > worst:
				worst = dev
				worst_key = k
	model.queue_free()
	check(worst <= 1e-6, "still_pose_untouched", "maior desvio %.7f em %s" % [worst, worst_key])


## Nos golpes o quadril gira com o giro do golpe: o desfazer das pernas da marcha (leg_yaw) tem de sumir.
func _attack_resets_leg_yaw() -> void:
	var model := (load("res://assets/models/knight.glb") as PackedScene).instantiate() as Node3D
	add_child(model)
	var r := KnightAnim.rig(model)
	var p := KnightAnim.locomotion_pose(r, 0.7, 1.0, 0.0)
	var walking := absf(float(p.leg_yaw))
	KnightAnim.sword_pose(p, 1, 0.5, 1.0)
	KnightAnim.hips_follow(p)
	model.queue_free()
	check(walking > 0.01 and p.leg_yaw == 0.0, "attack_resets_leg_yaw",
		"leg_yaw andando %.4f, no golpe %.4f" % [walking, p.leg_yaw])


## Como no jogo: suavização de apply() (k = 1 - exp(-14 dt)) e follow_cycle. A cabeça tem de continuar estável
## com o atraso da suavização, não só com k = 1. Mede 1,5 s depois de 1,5 s de aquecimento.
func _head_steady_with_smoothing(move: float, run: float, tag: String) -> void:
	var model := (load("res://assets/models/knight.glb") as PackedScene).instantiate() as Node3D
	add_child(model)
	var r := KnightAnim.rig(model)
	var dt := 1.0 / 60.0
	var speed := 7.5 if run > 0.5 else 5.2
	var phase := 0.0
	var h_lo := INF
	var h_hi := -INF
	var b_lo := INF
	var b_hi := -INF
	for i in 180:
		phase += dt * KnightAnim.cadence(r, speed, move, run)
		var p := KnightAnim.locomotion_pose(r, phase, move, run)
		KnightAnim.follow_cycle(p, 1.0)
		KnightAnim.apply(r, p, 1.0 - exp(-14.0 * dt))
		if i >= 90:
			var hy := _yaw(r.Head)
			var by := _yaw(r.Chest)
			h_lo = minf(h_lo, hy)
			h_hi = maxf(h_hi, hy)
			b_lo = minf(b_lo, by)
			b_hi = maxf(b_hi, by)
	model.queue_free()
	var ha := h_hi - h_lo
	var ba := b_hi - b_lo
	check(ba >= 0.01 and ha <= 0.3 * ba, "head_steady_with_smoothing" + tag,
		"amplitude yaw cabeça %.4f corpo %.4f" % [ha, ba])


## Os golpes não herdam a compensação da marcha: head_y, head_z e leg_yaw saem iguais com a pose de
## locomoção como veio e com esses três zerados antes do ataque (como era antes da marcha ter compensação).
func _attack_keeps_own_head() -> void:
	var model := (load("res://assets/models/knight.glb") as PackedScene).instantiate() as Node3D
	add_child(model)
	var r := KnightAnim.rig(model)
	var base := KnightAnim.locomotion_pose(r, 0.2, 1.0, 0.0)
	var walk_head := absf(float(base.head_y))
	var worst := 0.0
	for kind in ["sword", "bow_draw", "bow_release", "cast"]:
		var a := base.duplicate(true)
		var b := base.duplicate(true)
		b.head_y = 0.0
		b.head_z = 0.0
		b.leg_yaw = 0.0
		for p in [a, b]:
			match kind:
				"sword":
					KnightAnim.sword_pose(p, 1, 0.5, 1.0)
				"bow_draw":
					KnightAnim.bow_draw_pose(p, 0.6, 1.0)
				"bow_release":
					KnightAnim.bow_release_pose(p, 0.3, 1.0)
				"cast":
					KnightAnim.cast_pose(p, "fireball", 0.5, 1.0)
			KnightAnim.hips_follow(p)
		for k in ["head_y", "head_z", "leg_yaw"]:
			worst = maxf(worst, absf(float(a[k]) - float(b[k])))
	model.queue_free()
	check(walk_head >= 0.02 and worst <= 1e-6, "attack_keeps_own_head",
		"head_y andando %.4f, maior diferença %.7f" % [walk_head, worst])


## Como tools/gait_shot.gd ("apoio: tornozelo desliza"): anda o ciclo com o corpo avançando `speed` e mede
## quanto o tornozelo esquerdo, no apoio, se mexe para frente/trás no mundo.
func _stance_foot_no_back_slip(speed: float, run: float) -> void:
	var move := clampf(speed / 5.2, 0.0, 1.0)
	var model := (load("res://assets/models/knight.glb") as PackedScene).instantiate() as Node3D
	add_child(model)
	var r := KnightAnim.rig(model)
	var w := KnightAnim.cadence(r, speed, move, run)
	var duty := KnightAnim.gait_duty(move, run)
	var steps := 400
	var dt := TAU / w / steps
	var lo := INF
	var hi := -INF
	for i in steps:
		var p := KnightAnim.locomotion_pose(r, TAU * i / steps, move, run)
		KnightAnim.apply(r, p, 1.0)
		KnightAnim.apply(r, p, 1.0)
		var u := float(i) / steps
		if u > 0.15 * duty and u < 0.55 * duty:
			var z: float = r.AnkleL.global_position.z + speed * dt * i - model.global_position.z
			lo = minf(lo, z)
			hi = maxf(hi, z)
	model.queue_free()
	check(hi - lo <= 0.002, "stance_foot_no_back_slip (%.1f m/s run %.1f)" % [speed, run], "desliza %.4f m" % (hi - lo))


## Como o jogo (player.gd _animate): locomoção, follow_cycle, pose do arco, hips_follow, apply, a 60 fps.
## Andando e começando a puxar o arco, o quadril não pode dar um salto: o giro tem de assentar aos poucos.
func _bow_draw_eases_hips() -> void:
	var model := (load("res://assets/models/knight.glb") as PackedScene).instantiate() as Node3D
	add_child(model)
	var r := KnightAnim.rig(model)
	var dt := 1.0 / 60.0
	var k := 1.0 - exp(-14.0 * dt)
	var phase := 0.0
	var before := 0.0
	var first := 0.0
	var after := 0.0
	for i in 60 + 30:
		phase += dt * KnightAnim.cadence(r, 5.2, 1.0, 0.0)
		var p := KnightAnim.locomotion_pose(r, phase, 1.0, 0.0)
		KnightAnim.follow_cycle(p, 1.0)
		if i >= 60:
			KnightAnim.bow_draw_pose(p, minf(1.0, float(i - 60) * dt / 0.8), 1.0)
			KnightAnim.hips_follow(p)
		KnightAnim.apply(r, p, k)
		if i == 59:
			before = _yaw(r.Pelvis)
		elif i == 60:
			first = _yaw(r.Pelvis)
		elif i == 89:
			after = _yaw(r.Pelvis)
	model.queue_free()
	check(absf(first - before) < 0.12 and absf(after - before) >= 0.15, "bow_draw_eases_hips",
		"salto no 1o quadro %.4f rad (limite 0.12), total em 0,5 s %.4f rad (mínimo 0.15)" % [
			absf(first - before), absf(after - before)])


func _pitch(n: Node3D) -> float:
	return n.global_basis.get_euler(EULER_ORDER_YXZ).x


## O tronco cai para a frente com a velocidade (média do ciclo >= `least` rad), mergulha e volta a cada
## passada, e a cabeça desfaz pelo menos metade disso (continua olhando para a frente).
func _leans_with_speed(move: float, run: float, least: float) -> void:
	var model := (load("res://assets/models/knight.glb") as PackedScene).instantiate() as Node3D
	add_child(model)
	var r := KnightAnim.rig(model)
	var body := 0.0
	var head := 0.0
	var lo := INF
	var hi := -INF
	for i in N:
		var p := KnightAnim.locomotion_pose(r, TAU * i / N, move, run)
		KnightAnim.apply(r, p, 1.0)
		KnightAnim.apply(r, p, 1.0)
		var b := _pitch(r.Chest)
		body += b / N
		head += _pitch(r.Head) / N
		lo = minf(lo, b)
		hi = maxf(hi, b)
	model.queue_free()
	check(body >= least and head <= 0.5 * body and hi - lo >= 0.02, "leans_with_speed (move %.1f run %.1f)" % [move, run],
		"tronco %.3f rad (mín. %.2f), cabeça %.3f, pulso %.3f" % [body, least, head, hi - lo])


## Inclinado, o pé pousa mais perto de baixo do quadril do que sai: a distância à frente no contato é pelo
## menos 0,04 m menor que a distância atrás na saída.
func _foot_lands_under_body(move: float, run: float) -> void:
	var model := (load("res://assets/models/knight.glb") as PackedScene).instantiate() as Node3D
	add_child(model)
	var r := KnightAnim.rig(model)
	var duty := KnightAnim.gait_duty(move, run)
	var z: Array = []
	for u in [0.0, duty - 0.001]:
		var p := KnightAnim.locomotion_pose(r, TAU * u, move, run)
		KnightAnim.apply(r, p, 1.0)
		KnightAnim.apply(r, p, 1.0)
		z.append(r.AnkleL.global_position.z - r.LegL.global_position.z)
	model.queue_free()
	var front: float = z[0]      # > 0: tornozelo à frente do quadril no contato
	var behind: float = -z[1]    # > 0: atrás na saída
	check(front > 0.0 and behind - front >= 0.04, "foot_lands_under_body (move %.1f run %.1f)" % [move, run],
		"à frente %.3f m, atrás %.3f m" % [front, behind])


## Coluna: correndo, o peito cai mais que o quadril e a cabeça volta (curva); cinto e saiote (Body) giram com
## a pelve, contra os ombros (Chest); e um golpe por cima da marcha recebe o tronco inteiro de volta em Body.
func _spine_curves(move: float, run: float) -> void:
	var model := (load("res://assets/models/knight.glb") as PackedScene).instantiate() as Node3D
	add_child(model)
	var r := KnightAnim.rig(model)
	var p := KnightAnim.locomotion_pose(r, 0.0, move, run)
	KnightAnim.apply(r, p, 1.0)
	KnightAnim.apply(r, p, 1.0)
	var hips := _pitch(r.Body)
	var chest := _pitch(r.Chest)
	var head := _pitch(r.Head)
	var hips_yaw := _yaw(r.Body)
	var chest_yaw := _yaw(r.Chest)
	var shoulders: float = p.twist + p.chest_y
	var lean: float = p.body_x + p.chest_x
	KnightAnim.drop_gait_comp(p)   # o que todo golpe, arco e magia chama antes de pôr a própria pose
	model.queue_free()
	var tag := " (move %.1f run %.1f)" % [move, run]
	check(hips > 0.03 and chest > hips + 0.03 and head < chest - 0.03, "spine_curves" + tag,
		"quadril %.3f peito %.3f cabeça %.3f rad" % [hips, chest, head])
	check(hips_yaw < -0.03 and chest_yaw > 0.03, "hips_turn_against_shoulders" + tag,
		"cinto %.3f ombros %.3f rad" % [hips_yaw, chest_yaw])
	check(p.chest_x == 0.0 and p.chest_y == 0.0 and p.chest_z == 0.0 and absf(shoulders) > 0.03
		and absf(p.twist - shoulders) < 1e-6 and absf(p.body_x - lean) < 1e-6, "attack_takes_whole_torso" + tag,
		"peito (%.3f, %.3f, %.3f) body_x %.3f (inclinação %.3f)" % [p.chest_x, p.chest_y, p.chest_z, p.body_x, lean])
