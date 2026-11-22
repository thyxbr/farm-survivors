extends RefCounted
## Afinidades elementais no combate (ElementRules): o multiplicador é o mesmo % da ficha do Bestiário, a mistura
## do golpe com encantamento, a dica do número de dano e o elemento de cada projétil.

var _bt: BalanceTables


func _tables() -> BalanceTables:
	if _bt == null:
		_bt = BalanceTables.load_dir("res://data/balance")
	return _bt


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001


func test_mult_igual_a_ficha() -> void:
	var bt := _tables()
	for k in BestiaryRules.all_kinds(bt):
		for el in BestiaryRules.ELEMENTS:
			var m := ElementRules.mult(bt, k, el)
			T.ok(_near(m, BestiaryRules.element_pct(bt, k, el) / 100.0), "%s/%s: combate = ficha" % [k, el])


func test_mult_casos() -> void:
	var bt := _tables()
	T.ok(_near(ElementRules.mult(bt, "esqueleto", "sagrado"), 1.5), "esqueleto fraco a sagrado")
	T.ok(_near(ElementRules.mult(bt, "esqueleto", "sombra"), 0.0), "esqueleto imune a sombra")
	T.ok(_near(ElementRules.mult(bt, "slime_explosivo", "fogo"), 0.0), "slime explosivo imune a fogo")
	T.ok(_near(ElementRules.mult(bt, "goblin", "gelo"), 1.0), "sem entrada = neutro")
	T.ok(_near(ElementRules.mult(bt, "nao_existe", "fogo"), 1.0), "monstro desconhecido = neutro")
	T.ok(_near(ElementRules.mult(bt, "esqueleto", ElementRules.NEUTRAL), 1.0), "arcano não tem afinidade")


func test_mistura() -> void:
	var bt := _tables()
	# esqueleto: físico 90, sagrado 150 -> 80% físico + 20% sagrado = 0.72 + 0.30
	T.ok(_near(ElementRules.mult(bt, "esqueleto", {"fisico": 0.8, "sagrado": 0.2}), 1.02), "média pelos pesos")
	# pesos não precisam somar 1
	T.ok(_near(ElementRules.mult(bt, "esqueleto", {"fisico": 4.0, "sagrado": 1.0}), 1.02), "pesos normalizados")
	# a parte imune zera só a fatia dela
	T.ok(_near(ElementRules.mult(bt, "slime_explosivo", {"fisico": 0.75, "fogo": 0.25}), 0.75), "fatia imune some")


func test_mix_of_saneia() -> void:
	T.eq(ElementRules.mix_of("fogo"), {"fogo": 1.0}, "nome vira mistura")
	T.eq(ElementRules.mix_of("lava"), {"fisico": 1.0}, "desconhecido vira físico")
	T.eq(ElementRules.mix_of(null), {"fisico": 1.0}, "nada vira físico")
	T.eq(ElementRules.mix_of(42), {"fisico": 1.0}, "lixo vira físico")
	T.eq(ElementRules.mix_of({"fogo": -1.0, "gelo": INF, "x": 1.0}), {"fisico": 1.0}, "pesos inválidos descartados")
	T.eq(ElementRules.mix_of({"fogo": 1, "raio": 0.5}), {"fogo": 1.0, "raio": 0.5}, "pesos inteiros aceitos")


func test_weapon_mix() -> void:
	T.eq(ElementRules.weapon_mix("fisico", "", 0.0, 1.0), "fisico", "sem encanto: só o base")
	T.eq(ElementRules.weapon_mix("fogo", "fogo", 0.3, 1.3), "fogo", "encanto igual ao base")
	var m = ElementRules.weapon_mix("fisico", "fogo", 0.3, 1.5)   # +30% num multiplicador de 1,5
	T.ok(m is Dictionary and _near(m.fogo, 0.2) and _near(m.fisico, 0.8), "fatia = bônus / multiplicador")
	var all = ElementRules.weapon_mix("fisico", "raio", 5.0, 1.0)
	T.ok(_near(all.raio, 1.0) and _near(all.fisico, 0.0), "fatia limitada a 100%")
	T.eq(ElementRules.weapon_mix("fisico", "lava", 0.3, 1.3), "fisico", "encanto desconhecido ignorado")


func test_hint() -> void:
	T.eq(ElementRules.hint(0.0), "Imune", "imune")
	T.eq(ElementRules.hint(1.5), "Fraco!", "fraco")
	T.eq(ElementRules.hint(0.5), "Resistiu", "resiste")
	T.eq(ElementRules.hint(1.0), "", "neutro sem dica")
	T.eq(ElementRules.hint(1.02), "", "quase neutro sem dica")
	T.eq(ElementRules.hint_color(1.0, Color.WHITE), Color.WHITE, "neutro mantém a cor")
	T.eq(ElementRules.hint_color(1.5, Color.WHITE), ElementRules.C_WEAK, "fraco muda a cor")


func test_projectile_element() -> void:
	T.eq(ElementRules.projectile_element("arrow", "", ""), "fisico", "flecha física")
	T.eq(ElementRules.projectile_element("arrow", "", "glacial"), "gelo", "Flecha Glacial")
	T.eq(ElementRules.projectile_element("bolt", "fire", "splash"), "fogo", "cajado de fogo")
	T.eq(ElementRules.projectile_element("bolt", "frost", "slow"), "gelo", "cajado de gelo")
	T.eq(ElementRules.projectile_element("bolt", "arcane", ""), ElementRules.NEUTRAL, "cajado arcano")
	T.eq(ElementRules.projectile_element("light_orb", "", ""), "sagrado", "esfera do cetro")
	T.eq(ElementRules.projectile_element("holy_lance", "", ""), "sagrado", "Lança de Luz")


func test_combos_da_horda_tem_elemento() -> void:
	var combos: Dictionary = _tables().get_table("horde").get("combos", {})
	T.ok(not combos.is_empty(), "há combos")
	for c in combos:
		T.ok(ElementRules.known(str(combos[c].get("element", ""))), "combo %s com elemento conhecido" % c)
