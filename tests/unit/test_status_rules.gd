extends RefCounted
## Status elementais (StatusRules): resistência a partir do Bestiário, chance cortada pela resistência,
## rolagem com "Resistiu", chance por nível, renovação sem empilhar, congelamento e limites do servidor.

var _bt: BalanceTables


func _tables() -> BalanceTables:
	if _bt == null:
		_bt = BalanceTables.load_dir("res://data/balance")
	return _bt


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001


func test_resist_do_bestiario() -> void:
	var bt := _tables()
	T.ok(_near(StatusRules.enemy_resist(bt, "slime", "veneno"), 0.25), "afinidade 75 = 25% de resistência")
	T.ok(_near(StatusRules.enemy_resist(bt, "slime", "fogo"), 0.0), "fraco (125) não passa de 0")
	T.ok(_near(StatusRules.enemy_resist(bt, "slime_explosivo", "fogo"), 1.0), "imune = 100%")
	T.ok(_near(StatusRules.enemy_resist(bt, "goblin", "gelo"), 0.0), "sem entrada = 0")


func test_chance_final() -> void:
	T.ok(_near(StatusRules.final_chance(0.30, 0.5), 0.15), "30% com 50% de resistência = 15%")
	T.ok(_near(StatusRules.final_chance(0.30, 1.4), 0.0), "resistência acima de 100% = 0")
	T.ok(_near(StatusRules.final_chance(0.30, -0.2), 0.30), "resistência negativa não aumenta")


func test_roll() -> void:
	T.eq(StatusRules.roll(0.30, 0.5, 0.10), "applied", "abaixo da chance final")
	T.eq(StatusRules.roll(0.30, 0.5, 0.20), "none", "resistência parcial barrou: silencioso")
	T.eq(StatusRules.roll(0.30, 1.0, 0.10), "resisted", "imune barrou um que teria pego")
	T.eq(StatusRules.roll(0.30, 1.0, 0.50), "none", "nem a base pegou: nada")


func test_chance_por_nivel() -> void:
	var bt := _tables()
	T.ok(_near(StatusRules.chance(bt, "fogo", 1), 0.25), "fogo +1")
	T.ok(_near(StatusRules.chance(bt, "gelo", 5), 0.50), "gelo +5")
	T.ok(_near(StatusRules.chance(bt, "raio", 3), 0.0), "raio não é status nesta entrega")
	T.ok(_near(StatusRules.chance(bt, "fogo", 0), 0.0), "sem encanto")
	T.ok(_near(StatusRules.chance(bt, "fogo", 9), 0.45), "acima do máximo vale o máximo")
	T.eq(StatusRules.ticks(bt, "veneno"), 5, "veneno em 5 ticks")
	T.eq(StatusRules.ticks(bt, "fogo"), 3, "fogo em 3 ticks")


func test_renova_sem_empilhar() -> void:
	var a := StatusRules.renew({}, 10.0, 3.0)
	T.ok(_near(a.power, 10.0) and _near(a.timer, 3.0), "primeiro")
	var b := StatusRules.renew({"power": 10.0, "timer": 1.0}, 6.0, 3.0)
	T.ok(_near(b.power, 10.0) and _near(b.timer, 3.0), "mais fraco renova tempo, mantém força")
	var c := StatusRules.renew({"power": 10.0, "timer": 2.5}, 14.0, 2.0)
	T.ok(_near(c.power, 14.0) and _near(c.timer, 2.5), "mais forte troca força, tempo fica o maior")


func test_congelamento() -> void:
	T.ok(StatusRules.should_freeze(3, 3, false, 0.0), "3 acúmulos congelam")
	T.ok(not StatusRules.should_freeze(2, 3, false, 0.0), "2 não")
	T.ok(not StatusRules.should_freeze(3, 3, true, 0.0), "chefe/elite nunca")
	T.ok(not StatusRules.should_freeze(3, 3, false, 2.0), "em recarga não")


func test_limites_do_servidor() -> void:
	var bt := _tables()
	T.ok(_near(StatusRules.cap_power(bt, "fogo", 1e9), 5000.0 * 0.45), "fogo: 5000 × maior value")
	T.ok(_near(StatusRules.cap_power(bt, "raio", 10.0), 0.0), "elemento sem status = 0")
	T.ok(_near(StatusRules.cap_secs(bt, "veneno", 999.0), 5.0), "veneno: secs da tabela")
	T.ok(_near(StatusRules.cap_secs(bt, "gelo", 999.0), 2.0), "gelo: maior value (segundos)")
	T.ok(_near(StatusRules.cap_power(bt, "fogo", NAN), 0.0), "lixo vira 0")
	T.ok(_near(StatusRules.cap_power(bt, "fogo", -5.0), 0.0), "negativo vira 0")
