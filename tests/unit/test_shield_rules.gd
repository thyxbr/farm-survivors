extends RefCounted
## ShieldRules: defesa com escudo (custo de fôlego que sobe a cada golpe seguido, cone da frente, guarda quebrada).

const WOOD := {"block": 0.6, "guard": 0.0}
const TOWER := {"block": 0.9, "guard": 0.4}


func test_each_hit_in_chain_costs_more() -> void:
	var c0 := ShieldRules.cost(10.0, 0, WOOD)
	var c1 := ShieldRules.cost(10.0, 1, WOOD)
	var c2 := ShieldRules.cost(10.0, 2, WOOD)
	T.ok(c1 > c0 and c2 > c1, "2º golpe custa mais que o 1º e o 3º mais que o 2º")
	T.ok(absf(c1 / c0 - (1.0 + ShieldRules.CHAIN_STEP)) < 0.001, "cada golpe seguido soma CHAIN_STEP")
	T.ok(absf(ShieldRules.chain_mult(50) - ShieldRules.CHAIN_MAX) < 0.001, "multiplicador tem teto")


func test_bigger_hit_costs_more_and_guard_cuts_cost() -> void:
	T.ok(ShieldRules.cost(40.0, 0, WOOD) > ShieldRules.cost(10.0, 0, WOOD), "pancada maior cansa mais")
	T.ok(ShieldRules.cost(10.0, 0, TOWER) < ShieldRules.cost(10.0, 0, WOOD), "escudo com guard cansa menos")


func test_resolve_blocks_and_breaks() -> void:
	var r := ShieldRules.resolve(20.0, 100.0, 0, WOOD)
	T.ok(r.blocked and not r.broke, "com fôlego defende")
	T.ok(absf(r.damage - 8.0) < 0.001, "madeira segura 60%")
	T.ok(r.stamina < 100.0, "gasta fôlego")
	r = ShieldRules.resolve(20.0, 3.0, 0, WOOD)
	T.ok(r.broke and not r.blocked, "sem fôlego a guarda quebra")
	T.ok(absf(r.damage - 20.0) < 0.001, "guarda quebrada: dano cheio")
	T.ok(absf(r.stamina - 0.0) < 0.001, "guarda quebrada zera o fôlego")


func test_chain_drains_full_bar() -> void:
	# 100 de fôlego contra golpes de 15: a sequência quebra a guarda em poucos golpes
	var st := 100.0
	var hits := 0
	while hits < 20:
		var r := ShieldRules.resolve(15.0, st, hits, WOOD)
		if r.broke:
			break
		st = r.stamina
		hits += 1
	T.ok(hits >= 3 and hits <= 6, "madeira aguenta de 3 a 6 golpes seguidos (aguentou %d)" % hits)


func test_front_cone() -> void:
	var f := Vector3(0, 0, 1)
	T.ok(ShieldRules.in_front(Vector3.ZERO, f, Vector3(0, 0, 3)), "de frente")
	T.ok(ShieldRules.in_front(Vector3.ZERO, f, Vector3(2, 0, 2)), "45° de lado")
	T.ok(not ShieldRules.in_front(Vector3.ZERO, f, Vector3(3, 0, 0.2)), "de lado puro não")
	T.ok(not ShieldRules.in_front(Vector3.ZERO, f, Vector3(0, 0, -3)), "pelas costas não")


func test_item_defaults() -> void:
	T.ok(absf(ShieldRules.block_of({}) - ShieldRules.DEFAULT_BLOCK) < 0.001, "item sem block usa o padrão")
	T.ok(absf(ShieldRules.block_of({"block": 2.0}) - 0.95) < 0.001, "block tem teto")
	T.ok(absf(ShieldRules.guard_of({}) - 0.0) < 0.001, "item sem guard não corta")
