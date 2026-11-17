extends RefCounted
## EnemyPose: IK de dois ossos dos braços do goblin e do esqueleto, arco em pé na linha da mira e cajado.


func _parts(model: String) -> Array:
	var m: Node3D = (load("res://assets/models/%s.glb" % model) as PackedScene).instantiate()
	var p := {}
	for n in ["LegL", "LegR", "ArmL", "ArmR", "ElbowL", "ElbowR", "Body", "Head"]:
		p[n] = m.find_child(n, true, false)
	p["Bow"] = m.find_child("Opt_Bow", true, false)
	p["Staff"] = m.find_child("Opt_Staff", true, false)
	return [m, p]


## Posição da mão no espaço do Body com a pose atual dos dois ossos.
func _hand(p: Dictionary, r: Dictionary, sd: String) -> Vector3:
	var arm: Node3D = p["Arm" + sd]
	var el: Node3D = p["Elbow" + sd]
	return arm.position + arm.basis * (el.position + el.basis * (r["H" + sd] as Vector3))


func test_weapon_of() -> void:
	T.eq(EnemyPose.weapon_of(["Bow", "Quiver"]), "bow")
	T.eq(EnemyPose.weapon_of(["Staff", "Hood"]), "staff")
	T.eq(EnemyPose.weapon_of(["Club"]), "")


func test_models_have_elbows() -> void:
	for model in ["goblin", "skeleton"]:
		var mp := _parts(model)
		var p: Dictionary = mp[1]
		T.ok(p.ElbowL != null and p.ElbowR != null, "%s: ElbowL e ElbowR no modelo" % model)
		T.ok(p.Bow != null and p.Bow.get_parent() == p.ElbowL, "%s: arco na mão esquerda (dentro do cotovelo)" % model)
		T.ok(p.Staff != null and p.Staff.get_parent() == p.ElbowR, "%s: cajado na mão direita" % model)
		T.ok(not EnemyPose.rig(p).is_empty(), "%s: medidas dos braços" % model)
		(mp[0] as Node).free()


func test_ik_reaches_target() -> void:
	var mp := _parts("goblin")
	var p: Dictionary = mp[1]
	var r := EnemyPose.rig(p)
	var S: Vector3 = r.SR
	for target in [S + Vector3(0.1, 0.0, 0.35), S + Vector3(0.25, 0.1, 0.2), S + Vector3(-0.05, 0.3, 0.1)]:
		var sol := EnemyPose.solve(r, "R", target, EnemyPose.POLE_DRAW)
		(p.ArmR as Node3D).quaternion = sol[0]
		(p.ElbowR as Node3D).rotation = Vector3(sol[1], 0, 0)
		var err := _hand(p, r, "R").distance_to(target)
		T.ok(err < 0.03, "IK leva a mão até o alvo (erro %.3f)" % err)
		T.ok(sol[1] <= 0.0, "cotovelo dobra só para a frente")
	(mp[0] as Node).free()


## No meio do puxar: braço do arco esticado para a frente, arco em pé e a mão da corda perto do queixo.
func test_bow_draw_pose() -> void:
	var mp := _parts("goblin")
	var p: Dictionary = mp[1]
	var r := EnemyPose.rig(p)
	var st := {"state": "attack", "kind": "shoot", "t": 0.58, "ht": 0.6, "dur": 1.0, "amp": 0.0, "s": 0.0,
		"weapon": "bow"}
	EnemyPose.humanoid(p, r, st, 1.0, 1.0)
	var body: Node3D = p.Body
	var bow_hand := body.basis * _hand(p, r, "L")
	var shoulder := body.basis * (r.SL as Vector3)
	T.ok((bow_hand - shoulder).normalized().dot(Vector3.BACK) > 0.8, "braço do arco aponta para o alvo (+z)")
	var bow_basis: Basis = body.basis * (p.ArmL as Node3D).basis * (p.ElbowL as Node3D).basis * (p.Bow as Node3D).basis
	T.ok(bow_basis.y.normalized().dot(Vector3.UP) > 0.9, "arco em pé")
	T.ok(bow_basis.z.normalized().dot(Vector3.BACK) > 0.9, "arco no plano da mira")
	var draw_hand := _hand(p, r, "R")
	T.ok(draw_hand.distance_to(r.anchor) < 0.08, "mão da corda no queixo (%.3f)" % draw_hand.distance_to(r.anchor))
	(mp[0] as Node).free()


## Andando com o cajado: a vara fica em pé (antes girava com o braço e atravessava a perna).
func test_staff_upright_walking() -> void:
	var mp := _parts("skeleton")
	var p: Dictionary = mp[1]
	var r := EnemyPose.rig(p)
	for s in [-1.0, 0.0, 1.0]:
		var st := {"state": "chase", "kind": "swing", "t": 0.0, "ht": 0.6, "dur": 1.0, "amp": 0.8, "s": s,
			"weapon": "staff"}
		EnemyPose.humanoid(p, r, st, 1.0, 1.0)
		var b: Basis = (p.Body as Node3D).basis * (p.ArmR as Node3D).basis * (p.ElbowR as Node3D).basis * (p.Staff as Node3D).basis
		T.ok(b.y.normalized().dot(Vector3.UP) > 0.95, "cajado em pé andando (passada %.0f)" % s)
	(mp[0] as Node).free()
