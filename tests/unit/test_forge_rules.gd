extends RefCounted
## ForgeRules: as habilidades do Forjador Rúnico (escolha do golpe, cone da Martelada, faixas de metal derretido,
## Escudo Rúnico e Superaquecimento).


func test_attack_choice() -> void:
	T.eq(ForgeRules.attack(0, 5.0, false), "hammer", "o golpe comum é a martelada")
	T.eq(ForgeRules.attack(1, 12.0, false), "hammer", "de longe também")
	T.eq(ForgeRules.attack(2, 3.0, false), "vent", "3º golpe com o alvo colado: Respiro da Fornalha")
	T.eq(ForgeRules.attack(2, ForgeRules.VENT_R + 1.0, false), "hammer", "3º golpe com o alvo longe: martelada")
	T.eq(ForgeRules.attack(0, 3.0, true), "rune_shield", "na hora do escudo, o escudo vem primeiro")


func test_shield_first_by_hp_then_by_time() -> void:
	T.ok(not ForgeRules.should_shield(0.95, 0, 999.0, false), "vida cheia: sem escudo ainda")
	T.ok(ForgeRules.should_shield(ForgeRules.SHIELD_FIRST, 0, 0.0, false), "primeiro escudo pela vida")
	T.ok(not ForgeRules.should_shield(0.3, 1, ForgeRules.SHIELD_CD - 1.0, false), "o seguinte espera a recarga")
	T.ok(ForgeRules.should_shield(0.3, 1, ForgeRules.SHIELD_CD, false), "o seguinte vem pelo tempo")
	T.ok(not ForgeRules.should_shield(0.3, 1, 999.0, true), "com o escudo de pé não ergue outro")


func test_shield_only_falls_with_all_runes_broken() -> void:
	T.ok(not ForgeRules.shield_down(3), "3 runas: de pé")
	T.ok(not ForgeRules.shield_down(1), "1 runa: ainda de pé")
	T.ok(ForgeRules.shield_down(0), "nenhuma runa: cai")


func test_damage_taken() -> void:
	T.ok(absf(ForgeRules.taken(100.0, true, false)) <= 0.0001, "com escudo: imune")
	T.ok(absf(ForgeRules.taken(100.0, true, true)) <= 0.0001, "com escudo e superaquecido: imune")
	T.ok(absf(ForgeRules.taken(100.0, false, false) - 100.0) <= 0.0001, "sem escudo: dano normal")
	T.ok(ForgeRules.taken(100.0, false, true) > 100.0, "superaquecido: leva mais dano")


func test_overheat_is_faster() -> void:
	T.ok(ForgeRules.time_scale(true) < ForgeRules.time_scale(false), "superaquecido ataca mais rápido")
	T.ok(ForgeRules.HAMMER_T * ForgeRules.time_scale(true) >= 0.8, "mesmo assim o aviso dá tempo de sair")


func test_cone_hits_front_misses_side_and_back() -> void:
	var o := Vector3(-800, 0, -44)
	var d := Vector3(0, 0, 1)
	T.ok(ForgeRules.in_cone(o, d, o + Vector3(0, 0, 6)), "à frente: leva")
	T.ok(ForgeRules.in_cone(o, d, o + Vector3(2.5, 0.4, 6)), "dentro da abertura: leva")
	T.ok(not ForgeRules.in_cone(o, d, o + Vector3(6, 0, 4)), "de lado: escapa")
	T.ok(not ForgeRules.in_cone(o, d, o + Vector3(0, 0, -3)), "atrás: escapa")
	T.ok(not ForgeRules.in_cone(o, d, o + Vector3(0, 0, ForgeRules.CONE_LEN + 0.5)), "além da ponta: escapa")
	T.ok(ForgeRules.in_cone(o, d, o + Vector3(1.6, 0, 0.4)), "colado de lado, na frente: leva")
	T.ok(not ForgeRules.in_cone(o, d, o + Vector3(0.4, 0, -1.5)), "colado nas costas: escapa")


func test_trails_inside_cone() -> void:
	var o := Vector3(3, 0, 4)
	var d := Vector3(1, 0, 0)
	var cold := ForgeRules.trail_dirs(d, false)
	var hot := ForgeRules.trail_dirs(d, true)
	T.eq(cold.size(), ForgeRules.TRAILS, "três faixas")
	T.eq(hot.size(), ForgeRules.TRAILS_HOT, "cinco superaquecido")
	for v in hot:
		T.ok(absf((v as Vector3).length() - 1.0) <= 0.001, "direções normalizadas")
		var tip: Vector3 = o + (v as Vector3) * (ForgeRules.CONE_LEN - 0.1)
		T.ok(ForgeRules.in_cone(o, d, tip), "a faixa fica dentro do cone avisado")


func test_trail_burns_who_steps() -> void:
	var o := Vector3(0, 0, 0)
	var d := Vector3(0, 0, 1)
	T.ok(ForgeRules.in_trail(o, d, Vector3(0.3, 0, 5)), "em cima da faixa")
	T.ok(not ForgeRules.in_trail(o, d, Vector3(ForgeRules.TRAIL_HALF + 0.3, 0, 5)), "ao lado da faixa")
	T.ok(not ForgeRules.in_trail(o, d, Vector3(0, 0, ForgeRules.TRAIL_START - 0.5)), "antes de ela começar")
	T.ok(not ForgeRules.in_trail(o, d, Vector3(0, 0, ForgeRules.CONE_LEN + 0.5)), "depois da ponta")
	var c := ForgeRules.trail_center(o, d)
	T.ok(ForgeRules.in_trail(o, d, c), "o centro está na faixa")
	T.ok(ForgeRules.trail_life(true) > ForgeRules.trail_life(false), "superaquecido, o metal demora mais a esfriar")


func test_rune_points_deterministic_and_spread() -> void:
	var c := Vector3(-800, 0, -44)
	var a := ForgeRules.rune_points(77, c, Vector3(0, 0, 1))
	var b := ForgeRules.rune_points(77, c, Vector3(0, 0, 1))
	T.eq(a, b, "mesma semente, mesmos pontos (servidor e cliente)")
	T.eq(a.size(), ForgeRules.RUNES, "três runas")
	for p in a:
		var dist := Vector2((p as Vector3).x - c.x, (p as Vector3).z - c.z).length()
		T.ok(dist >= ForgeRules.RUNE_MIN - 0.001 and dist <= ForgeRules.RUNE_MAX + 0.001, "na distância certa")
		T.ok((p as Vector3).z > c.z - 4.0, "nunca bem atrás dele (a parede do fundo)")
	for i in a.size():
		for j in range(i + 1, a.size()):
			T.ok((a[i] as Vector3).distance_to(a[j]) > 6.0, "espalhadas pela sala")
