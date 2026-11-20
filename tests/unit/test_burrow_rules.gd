extends RefCounted
## BurrowRules: quando a Toupeira-Broca (e a Mãe-Verme) cava, anda por baixo da terra e emerge.

const CFG := {"dig_min": 4.0, "dig_max": 14.0, "surface_secs": 3.0, "dig_max_secs": 4.0}


func test_digs_only_mid_range_after_surface_time() -> void:
	T.ok(BurrowRules.should_dig(8.0, 3.5, CFG), "média distância depois da janela")
	T.ok(not BurrowRules.should_dig(2.0, 5.0, CFG), "colado: luta na superfície")
	T.ok(not BurrowRules.should_dig(20.0, 5.0, CFG), "longe demais: persegue andando")
	T.ok(not BurrowRules.should_dig(8.0, 1.0, CFG), "ainda na janela vulnerável")


func test_dig_step_moves_toward_target() -> void:
	var p := BurrowRules.dig_step(Vector3.ZERO, Vector3(10, 0, 0), 6.0, 0.5)
	T.ok(absf(p.x - 3.0) < 0.001 and absf(p.z) < 0.001, "anda speed*delta na direção do alvo")


func test_dig_step_does_not_overshoot() -> void:
	T.eq(BurrowRules.dig_step(Vector3.ZERO, Vector3(1, 0, 0), 6.0, 1.0), Vector3(1, 0, 0), "para no alvo")


func test_dig_step_keeps_height() -> void:
	T.eq(BurrowRules.dig_step(Vector3(0, 2, 0), Vector3(1, 7, 0), 6.0, 1.0).y, 2.0, "anda no plano, não sobe para o alvo")


func test_emerges_on_arrival_or_timeout() -> void:
	T.ok(BurrowRules.should_emerge(Vector3(0.3, 0, 0), Vector3.ZERO, 0.5, CFG), "chegou")
	T.ok(BurrowRules.should_emerge(Vector3(9, 0, 0), Vector3.ZERO, 4.0, CFG), "tempo esgotado")
	T.ok(not BurrowRules.should_emerge(Vector3(9, 0, 0), Vector3.ZERO, 1.0, CFG), "ainda indo")


## O corpo da toupeira esbarra no do jogador: com raio 0,55 ela para a ~0,9 m dele, e isso já é "chegou".
func test_arrival_counts_body_radius() -> void:
	var cfg := CFG.duplicate()
	cfg["radius"] = 0.55
	T.ok(BurrowRules.should_emerge(Vector3(0.9, 0, 0), Vector3.ZERO, 0.5, cfg), "encostou no jogador: emerge")
	T.ok(not BurrowRules.should_emerge(Vector3(1.6, 0, 0), Vector3.ZERO, 0.5, cfg), "ainda a um passo: segue")


func test_clamp_to_leash() -> void:
	T.eq(BurrowRules.clamp_to_leash(Vector3(30, 1, 0), Vector3.ZERO, Vector2(20, 15)), Vector3(20, 1, 0), "corta na borda em x")
	T.eq(BurrowRules.clamp_to_leash(Vector3(-50, 0, -40), Vector3(-45, 0, -40), Vector2(20, 15)), Vector3(-50, 0, -40), "dentro: igual")


func test_burrowed_is_untargetable() -> void:
	T.ok(BurrowRules.hidden("burrow", "", false), "debaixo da terra: não leva dano")
	T.ok(BurrowRules.hidden("attack", "emerge", false), "subindo (antes do golpe): ainda escondida")
	T.ok(not BurrowRules.hidden("attack", "emerge", true), "saiu do chão: leva dano")
	T.ok(not BurrowRules.hidden("chase", "", false), "na superfície: leva dano")
	T.ok(not BurrowRules.hidden("attack", "swing", false), "golpe comum: leva dano")
