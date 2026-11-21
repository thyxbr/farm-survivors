extends Node3D
## Mede a pose do braço do escudo: procura o giro do ombro (ArmL) e a dobra do cotovelo (ElbowL) que põem
## a face do escudo de frente (+Z do modelo), de pé, na frente do peito esquerdo. Imprime os melhores valores
## para KnightMoves.SHIELD_GUARD. Sem janela:
##   godot --headless --path . res://tools/shield_pose_probe.tscn -- [fem] [x,y,z]
## x,y,z = centro desejado do escudo no espaço do modelo (padrão 0.12,1.30,0.42).

var _target := Vector3(0.12, 1.30, 0.42)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.count(",") == 2:
			var v := a.split(",")
			_target = Vector3(float(v[0]), float(v[1]), float(v[2]))
	var m := KnightLook.instance("f" if "fem" in args else "m")
	add_child(m)
	KnightLook.apply(m, {"weapon": "iron_sword", "offhand": "wooden_shield"})
	var r := KnightAnim.rig(m)
	var shield := m.find_child("Shield", true, false) as MeshInstance3D
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var best := [1e9, Vector3.ZERO, 0.0]
	for it in 60000:
		var arm: Vector3
		var el: float
		if it < 30000:
			arm = Vector3(rng.randf_range(-2.6, 0.6), rng.randf_range(-2.6, 2.6), rng.randf_range(-0.6, 1.6))
			el = rng.randf_range(-2.4, 0.2)
		else:
			var s := 0.25 * (1.0 - float(it - 30000) / 30000.0) + 0.01
			arm = best[1] + Vector3(rng.randfn(0, s), rng.randfn(0, s), rng.randfn(0, s))
			el = best[2] + rng.randfn(0, s)
		var sc := _score(m, r, shield, arm, el)
		if sc < best[0]:
			best = [sc, arm, el]
	_score(m, r, shield, best[1], best[2])
	var info := _measure(m, r, shield)
	print("SHIELD_GUARD arm_l=Vector3(%.3f, %.3f, %.3f) elbow_l=%.3f score=%.4f" % [best[1].x, best[1].y, best[1].z, best[2], best[0]])
	print("  centro=%s normal=%s cima=%s" % [info.c, info.n, info.u])
	get_tree().quit()


func _measure(m: Node3D, r: Dictionary, shield: MeshInstance3D) -> Dictionary:
	var t := KnightLook._chain(shield, m)
	var c := t * shield.mesh.get_aabb().get_center()
	return {"c": c, "n": (t.basis * Vector3.RIGHT).normalized(), "u": (t.basis * Vector3.UP).normalized()}


func _score(m: Node3D, r: Dictionary, shield: MeshInstance3D, arm: Vector3, el: float) -> float:
	r.ArmL.rotation = arm
	r.ElbowL.rotation.x = el
	var i := _measure(m, r, shield)
	var face: float = 1.0 - i.n.dot(Vector3(0, 0, 1))         # face para a frente
	var up: float = 1.0 - i.u.dot(Vector3(0, 1, 0))           # de pé (ponta para baixo)
	up *= 2.0
	var pos: float = (i.c - _target).length()
	# cotovelo dobrado de verdade (negativo = dobra) e sem torcer demais o ombro
	var pen := maxf(0.0, el + 1.1) * 0.8 + maxf(0.0, absf(arm.y) - 2.3) * 0.5
	return face * 2.0 + up * 0.6 + pos * 3.0 + pen
