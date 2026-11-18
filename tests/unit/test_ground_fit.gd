extends RefCounted
## GroundFit.fit: o desenho de área deita no terreno, mas uma pedra no meio não o deixa de lado.


func _ring(center: Vector3, reach: float, height: Callable) -> Array:
	var pts: Array = []
	for i in 9:
		var off := Vector3.ZERO if i == 0 else Vector3(cos(i * TAU / 8.0), 0, sin(i * TAU / 8.0)) * reach
		var p := center + off
		pts.append(Vector3(p.x, height.call(p.x, p.z), p.z))
	return pts


func test_flat_ground_stays_flat() -> void:
	var f := GroundFit.fit(_ring(Vector3(4, 0, -2), 2.0, func(_x: float, _z: float) -> float: return 1.5), Vector3(4, 9, -2))
	T.ok(f.basis.y.distance_to(Vector3.UP) < 0.001, "chão reto: normal para cima")
	T.ok(absf(f.origin.y - 1.5) < 0.001, "origem na altura do chão")


func test_slope_tilts_with_the_terrain() -> void:
	var f := GroundFit.fit(_ring(Vector3.ZERO, 2.0, func(x: float, _z: float) -> float: return x * 0.3), Vector3.ZERO)
	var n := Vector3(-0.3, 1, 0).normalized()
	T.ok(f.basis.y.distance_to(n) < 0.001, "ladeira: normal do terreno (%s)" % f.basis.y)
	T.ok(absf(f.basis.determinant() - 1.0) < 0.001, "base ortonormal, sem espelhar")


func test_rock_under_one_ray_does_not_tilt() -> void:
	var pts := _ring(Vector3.ZERO, 2.0, func(_x: float, _z: float) -> float: return 0.0)
	pts[1].y = 1.4      # um raio caiu em cima de uma pedra
	var f := GroundFit.fit(pts, Vector3.ZERO)
	T.ok(f.basis.y.distance_to(Vector3.UP) < 0.001, "pedra num raio: continua reto (%s)" % f.basis.y)
	T.ok(absf(f.origin.y) < 0.001, "e no chão, não na pedra")


func test_rock_under_center_and_neighbor_on_a_slope() -> void:
	var pts := _ring(Vector3.ZERO, 2.0, func(x: float, _z: float) -> float: return x * 0.2)
	pts[0].y += 1.0     # o centro e um vizinho em cima da pedra
	pts[3].y += 0.8
	var f := GroundFit.fit(pts, Vector3.ZERO)
	T.ok(f.basis.y.distance_to(Vector3(-0.2, 1, 0).normalized()) < 0.001, "segue a ladeira, ignora a pedra (%s)" % f.basis.y)
	T.ok(absf(f.origin.y) < 0.001, "origem no plano da ladeira")


func test_wall_or_too_few_points_stay_upright() -> void:
	var steep := GroundFit.fit(_ring(Vector3.ZERO, 2.0, func(x: float, _z: float) -> float: return x * 1.5), Vector3.ZERO)
	T.ok(steep.basis.is_equal_approx(Basis.IDENTITY), "íngreme demais: não deita")
	var few := GroundFit.fit([Vector3(0, 2, 0), Vector3(1, 2, 0)], Vector3(0, 5, 0))
	T.ok(few.basis.is_equal_approx(Basis.IDENTITY) and absf(few.origin.y - 2.0) < 0.001, "poucos pontos: reto, na altura medida")
	T.ok(GroundFit.fit([], Vector3(1, 5, 2)).origin == Vector3(1, 5, 2), "sem chão: a própria posição")
