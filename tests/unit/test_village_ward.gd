extends RefCounted
## Zona protegida pela guarda da vila (VillageWard): onde o monstro para, onde a guarda abate e a distância que
## os pontos de monstro do vale mantêm da cerca.


func test_village_and_farm_are_protected() -> void:
	T.ok(VillageWard.inside(Vector3(0, 0, 0)), "praça da vila")
	T.ok(VillageWard.inside(Vector3(0, 0, 35)), "Horta")
	T.ok(VillageWard.inside(Vector3(22, 0, 33)), "Pomar")
	T.ok(VillageWard.inside(Vector3(41, 0, 0)), "logo fora do portão leste (folga)")
	T.ok(not VillageWard.inside(Vector3(86, 0, 0)), "Toca dos Goblins fica fora")
	T.ok(not VillageWard.inside(Vector3(0, 0, -45)), "Campos do Norte ficam fora")
	T.ok(not VillageWard.inside(Vector3(-60, 0, 46)), "Ninho de Slimes fica fora")


func test_distance_to_zone() -> void:
	T.eq(VillageWard.distance(Vector3(0, 0, 0)), 0.0, "dentro = 0")
	T.ok(is_equal_approx(VillageWard.distance(Vector3(53, 0, 0)), 10.0), "10 m do lado leste (cerca 39 + folga 4)")
	T.ok(is_equal_approx(VillageWard.distance(Vector3(0, 0, -32)), 10.0), "10 m ao norte (cerca -18 - folga 4)")


func test_step_into_zone_is_blocked() -> void:
	T.ok(VillageWard.blocks_step(Vector3(44, 0, 0), Vector3(42.5, 0, 0)), "passo de fora para dentro")
	T.ok(not VillageWard.blocks_step(Vector3(44, 0, 0), Vector3(45.5, 0, 0)), "passo para longe")
	T.ok(not VillageWard.blocks_step(Vector3(42, 0, 0), Vector3(40, 0, 0)), "quem já está dentro não trava (a guarda abate)")


func test_kill_line_is_inside_stop_line() -> void:
	# o monstro para na folga inteira (MARGIN); a guarda só atira mais para dentro, para um empurrão de quem
	# luta na beira da cerca não custar o abate ao jogador
	T.ok(VillageWard.KILL_MARGIN < VillageWard.MARGIN, "linha do abate dentro da linha de parada")
	T.ok(VillageWard.inside(Vector3(42, 0, 0)) and not VillageWard.inside(Vector3(42, 0, 0), VillageWard.KILL_MARGIN),
		"entre as duas linhas: parado, mas ainda vivo")
