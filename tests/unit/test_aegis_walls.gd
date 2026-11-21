extends RefCounted
## AegisWalls: a Égide como parede sólida (contas puras): empurrar monstros para fora, achar onde um projétil
## entra na coroa e quem a parede protege de uma explosão do lado de fora.

const C := Vector3(10.0, 0.0, -4.0)   # centro da parede
const R := 2.9
const H := 2.6


func test_push_moves_body_to_the_edge() -> void:
	var res := AegisWalls.push_point(C + Vector3(1.0, 0.0, 0.0), C, R, H, 0.5)
	var p: Vector3 = res[0]
	T.ok(res[1] == Vector3.RIGHT, "empurra para fora, na direção de quem estava dentro")
	T.ok(is_equal_approx(Vector2(p.x - C.x, p.z - C.z).length(), R + 0.5), "fica encostado na parede (raio + corpo)")
	T.eq(p.y, C.y, "não mexe na altura")


func test_push_leaves_outside_bodies_alone() -> void:
	var far := C + Vector3(0.0, 0.0, R + 1.0)
	var res := AegisWalls.push_point(far, C, R, H, 0.5)
	T.ok(res[0] == far and res[1] == Vector3.ZERO, "fora da parede: nada muda")
	var above := C + Vector3(0.5, H + 1.0, 0.0)
	T.ok(AegisWalls.push_point(above, C, R, H, 0.5)[1] == Vector3.ZERO, "por cima da coroa: não é parede")
	T.ok(AegisWalls.push_point(C + Vector3(0.5, 0, 0), C, 0.0, H, 0.5)[1] == Vector3.ZERO, "parede sem raio ainda (início): nada")


func test_push_from_the_exact_center_still_picks_a_side() -> void:
	var res := AegisWalls.push_point(C, C, R, H, 0.4)
	T.ok(res[1] != Vector3.ZERO and is_equal_approx(Vector2(res[0].x - C.x, res[0].z - C.z).length(), R + 0.4),
		"no centro exato também sai para algum lado")


func test_projectile_entering_is_stopped_at_the_edge() -> void:
	var from := C + Vector3(-5.0, 1.0, 0.0)
	var to := C + Vector3(-2.0, 1.0, 0.0)
	var p = AegisWalls.entry_point(from, to, C, R, H)
	T.ok(p != null, "flecha vindo de fora entra: a parede pega")
	T.ok(p != null and is_equal_approx((p as Vector3).x, C.x - R), "para na borda (x = centro - raio)")


func test_projectile_leaving_or_flying_over_passes() -> void:
	T.ok(AegisWalls.entry_point(C + Vector3(-1, 1, 0), C + Vector3(-5, 1, 0), C, R, H) == null, "de dentro para fora passa (o grupo atira de dentro)")
	T.ok(AegisWalls.entry_point(C + Vector3(-5, 1, 3.5), C + Vector3(5, 1, 3.5), C, R, H) == null, "passando ao lado, fora: nada")
	T.ok(AegisWalls.entry_point(C + Vector3(-5, H + 0.5, 0), C + Vector3(-2, H + 0.5, 0), C, R, H) == null, "por cima da coroa passa")
	T.ok(AegisWalls.entry_point(C + Vector3(-5, 1, 0), C + Vector3(-2, 1, 0), C, 0.0, H) == null, "parede sem raio: nada")


func test_explosion_outside_does_not_reach_inside() -> void:
	T.ok(AegisWalls.between(C + Vector3(0.5, 0, 0), C + Vector3(4.0, 0, 0), C, R), "dentro protegido de explosão fora")
	T.ok(not AegisWalls.between(C + Vector3(0.5, 0, 0), C + Vector3(1.0, 0, 0), C, R), "explosão dentro: não protege")
	T.ok(not AegisWalls.between(C + Vector3(4.0, 0, 0), C + Vector3(6.0, 0, 0), C, R), "quem está fora não é protegido")
