extends RefCounted
## HitGuard: acerto do cliente só conta com dano >= 1 e perto do inimigo (última posição recebida).


func test_accepts_normal_hit() -> void:
	T.ok(HitGuard.accepts(10.0, Vector3(0, 0, 3), Vector3.ZERO), "acerto perto vale")
	T.ok(HitGuard.accepts(1.0, Vector3(44, 0, 0), Vector3.ZERO), "flecha de 44 m vale")


func test_rejects_tiny_damage() -> void:
	T.ok(not HitGuard.accepts(0.001, Vector3.ZERO, Vector3.ZERO), "dano 0,001 não conta")
	T.ok(not HitGuard.accepts(0.99, Vector3.ZERO, Vector3.ZERO), "dano < 1 não conta")


func test_rejects_far_or_unknown() -> void:
	T.ok(not HitGuard.accepts(50.0, Vector3(46, 0, 0), Vector3.ZERO), "a 46 m não conta")
	T.ok(not HitGuard.accepts(50.0, Vector3.INF, Vector3.ZERO), "sem posição conhecida não conta")


func test_slow_only_needs_range() -> void:
	T.ok(HitGuard.accepts(0.0, Vector3(5, 0, 0), Vector3.ZERO), "só lentidão, perto")
	T.ok(not HitGuard.accepts(0.0, Vector3(100, 0, 0), Vector3.ZERO), "só lentidão, longe")
