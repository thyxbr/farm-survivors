extends RefCounted
## Identidade do Guerreiro (Lutador) na expedição (Fase E, etapa 2): o Ímpeto (ExpeditionMomentum), as contas dele
## (ExpeditionClasses) e o sorteio/validação das bênçãos do Guerreiro (ExpeditionUpgrades, ExpeditionRun).

const ANCESTRAL := "Altar Ancestral"
## Kit da espada de uma mão (o do Guerreiro), na ordem da barra.
const WARRIOR_KIT := ["sword_charge", "sword_quake", "sword_fury", "sword_whirl", "sword_vortex"]
const WARRIOR_BOONS := ["golpes_encadeados", "pressao_implacavel", "lamina_faminta", "passo_lobo", "folego_batalha",
	"investida_predadora", "sangue_brasa", "couraca_embalo", "explosao_impeto", "brecha", "furia_desperta"]
const WARRIOR_STYLES := ["agressivo", "veloz", "resistente", "explosivo"]
const TANK_BOONS := ["muralha_viva", "teimosia", "guarda_ferro", "egide_reforcada", "estilhacos", "correntes",
	"abalo", "revide", "sede"]
## run_mods zerado (igual ao Game.reset_run_mods com "active": true), com as chaves do Ímpeto.
const BASE := {"active": true, "damage": 1.0, "max_hp": 1.0, "max_hp_flat": 0.0, "speed": 1.0, "defense": 0.0,
	"regen": 0.0, "crit": 0.0, "cooldown": 1.0, "area": 1.0, "magnet": 1.0, "xp": 1.0, "gold": 1.0,
	"lifesteal": 0.0, "cdr": 0.0, "crowd_guard": 0.0, "block_power": 0.0, "block_guard": 0.0, "aegis_integrity": 0.0,
	"aegis_burst": 0.0, "taunt_time": 0.0, "stun_bonus": 0.0, "guard_dmg": 0.0,
	"momentum_max": 0.0, "momentum_dmg": 0.0, "momentum_speed": 0.0, "momentum_hold": 0.0, "momentum_kill": 0.0,
	"momentum_stamina": 0.0, "momentum_heal": 0.0, "momentum_guard": 0.0, "momentum_crit": 0.0, "momentum_burst": 0.0,
	"momentum_charge": 0.0, "momentum_fury": 0.0}


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001


func _rng(s: int) -> RandomNumberGenerator:
	var g := RandomNumberGenerator.new()
	g.seed = s
	return g


func _ctx(skills: Array = []) -> Dictionary:
	return {"class": ExpeditionClasses.WARRIOR, "skills": skills}


func _run_at(room: String, cls := "warrior") -> ExpeditionRun:
	var r := ExpeditionRun.create("pantano")
	r.char_class = cls
	r.start()
	var route := ExpeditionDefs.route(r.def)
	for j in range(1, route.find(room) + 1):
		r.enter_room(route[j])
		if ExpeditionDefs.needs_clear(r.def, route[j]):
			r.clear_room(route[j])
	return r


## Ímpeto com `n` acúmulos (teto `cap`).
func _mom(n: int, cap := 5) -> ExpeditionMomentum:
	var m := ExpeditionMomentum.new()
	m.add(n, cap)
	return m


# ================================================================ passiva
func test_warrior_passive_is_momentum() -> void:
	T.ok(ExpeditionClasses.has_identity("warrior"), "Guerreiro tem identidade na expedição")
	var m := ExpeditionClasses.apply_passive(BASE, "warrior")
	T.ok(_near(float(m.momentum_max), 5.0), "Ímpeto até 5")
	T.ok(_near(float(m.momentum_dmg), 0.03) and _near(float(m.momentum_speed), 0.015), "+3% de dano e +1,5% de velocidade")
	T.ok(_near(float(m.crowd_guard), 0.0), "o Guerreiro não ganha a Linha de Frente do Tank")
	T.ok(_near(float(m.damage), 1.0) and _near(float(m.defense), 0.0) and _near(float(m.max_hp), 1.0),
		"a passiva não mexe em dano, defesa ou vida fixos")
	var t := ExpeditionClasses.apply_passive(BASE, "tank")
	T.ok(_near(float(t.momentum_max), 0.0), "o Tank não ganha Ímpeto")
	for k in ExpeditionClasses.passive_mods("warrior"):
		T.ok(k in ExpeditionUpgrades.RUN_MOD_KEYS, "passiva mexe em %s, chave conhecida" % k)
		T.ok(BASE.has(k), "%s existe no run_mods zerado (some na volta)" % k)
	T.eq(ExpeditionUpgrades.style_text("passo_lobo"), "Guerreiro · Veloz", "carta mostra a classe e o estilo")


# ================================================================ Ímpeto (acúmulo, limite, queda)
func test_momentum_gain_respects_gap_and_cap() -> void:
	var m := ExpeditionMomentum.new()
	T.eq(m.on_hit(5), 1, "primeiro acerto: +1")
	T.eq(m.on_hit(5), 0, "acerto no mesmo instante (área, vários inimigos): nada a mais")
	m.tick(ExpeditionMomentum.GAIN_GAP + 0.01, 5)
	T.eq(m.on_hit(5), 1, "depois do intervalo: +1")
	T.eq(m.on_kill(5), 1, "abate: +1 sem esperar o intervalo")
	T.eq(m.on_kill(5, 1), 2, "Lâmina Faminta: abate dá +2")
	T.eq(m.on_kill(5, 1), 0, "no teto 5: nada a mais")
	T.eq(m.stacks, 5, "no teto")
	T.ok(m.is_full(5), "cheio")
	m.tick(1.0, 5)
	T.eq(m.on_hit(5), 0, "cheio: não passa do teto")
	T.eq(m.stacks, 5, "continua 5")
	var big := ExpeditionMomentum.new()
	big.add(99, 99)
	T.eq(big.stacks, ExpeditionMomentum.HARD_MAX, "teto absoluto (%d)" % ExpeditionMomentum.HARD_MAX)
	T.eq(ExpeditionMomentum.clamp_cap(7.4), 7, "teto arredondado")
	T.eq(ExpeditionMomentum.clamp_cap(INF), 0, "teto não finito: desligado")


func test_momentum_off_without_cap() -> void:
	var m := ExpeditionMomentum.new()
	T.eq(m.on_hit(0), 0, "sem a passiva (teto 0) não acumula")
	T.eq(m.on_kill(0, 2), 0, "nem com abate")
	T.eq(m.add(3, 0), 0, "nem com habilidade")
	var left := _mom(4)
	T.eq(left.tick(0.016, 0), 4, "o teto caiu a 0 (fim da expedição): tudo some no passo seguinte")
	T.eq(left.stacks, 0, "zerado")
	var over := _mom(7, 7)
	T.eq(over.effective(5), 5, "acima do teto novo: vale só o teto")
	T.eq(over.tick(0.016, 5), 2, "e o excedente cai")


func test_momentum_decays_when_pressure_stops() -> void:
	var m := _mom(5)
	T.eq(m.tick(ExpeditionMomentum.HOLD - 0.1, 5), 0, "dentro do fôlego do HOLD: nada cai")
	T.eq(m.stacks, 5, "ainda 5")
	T.eq(m.tick(0.1 + ExpeditionMomentum.DECAY_STEP, 5), 1, "passou do HOLD: cai 1 a cada passo")
	T.eq(m.tick(ExpeditionMomentum.DECAY_STEP * 2.0, 5), 2, "mais dois passos, mais dois")
	m.add(1, 5)
	T.eq(m.tick(ExpeditionMomentum.HOLD - 0.1, 5), 0, "um acerto novo reinicia a espera")
	# esvazia por completo, sem ficar negativo
	var e := _mom(3)
	var lost := 0
	for i in 400:
		lost += e.tick(0.05, 5)
	T.eq(lost, 3, "perde só o que tinha")
	T.eq(e.stacks, 0, "esvaziou")
	# a queda inteira (5 -> 0) leva HOLD + 5 passos: o jogador vê o embalo indo embora, não sumindo de uma vez
	var slow := _mom(5)
	slow.tick(ExpeditionMomentum.HOLD + ExpeditionMomentum.DECAY_STEP * 2.0 + 0.01, 5)
	T.eq(slow.stacks, 3, "2,5 s + 1 s parado: ainda tem 3")


func test_momentum_hold_bonus_and_lock() -> void:
	var m := _mom(5)
	T.eq(m.tick(ExpeditionMomentum.HOLD + 0.9, 5, 1.0), 0, "Pressão Implacável: +1 s antes de cair")
	T.ok(m.tick(0.2 + ExpeditionMomentum.DECAY_STEP, 5, 1.0) >= 1, "depois cai igual")
	var f := _mom(5)
	f.lock = 10.0
	T.eq(f.tick(9.0, 5), 0, "Fúria Desperta: enquanto dura, não cai")
	T.eq(f.stacks, 5, "segue cheio")
	f.tick(1.1, 5)
	T.ok(f.tick(ExpeditionMomentum.HOLD + ExpeditionMomentum.DECAY_STEP + 0.01, 5) >= 1, "a Fúria acabou: volta a cair")


func test_momentum_consume_and_reset() -> void:
	var m := _mom(5)
	T.eq(m.consume(), 5, "Explosão gasta tudo")
	T.eq(m.stacks, 0, "zerado")
	m.add(2, 5)
	m.lock = 3.0
	m.reset()
	T.ok(m.stacks == 0 and m.lock == 0.0 and m.gap == 0.0 and m.idle == 0.0, "reset limpa tudo (fim da run)")


# ================================================================ contas do Ímpeto
func test_momentum_formulas_and_caps() -> void:
	T.ok(_near(ExpeditionClasses.momentum_damage(0, 0.03), 0.0), "sem Ímpeto: sem dano a mais")
	T.ok(_near(ExpeditionClasses.momentum_damage(5, 0.03), 0.15), "5 acúmulos: +15% de dano")
	T.ok(_near(ExpeditionClasses.momentum_damage(7, 0.05), 0.35), "Encadeados x2 (7 x 5%): +35%")
	T.ok(_near(ExpeditionClasses.momentum_damage(8, 0.2), ExpeditionClasses.MOMENTUM_DMG_CAP), "teto de dano")
	T.ok(_near(ExpeditionClasses.momentum_damage(5, -1.0), 0.0), "valor negativo não tira dano")
	T.ok(_near(ExpeditionClasses.momentum_speed(5, 0.015), 1.075), "5 acúmulos: +7,5% de velocidade")
	T.ok(_near(ExpeditionClasses.momentum_speed(8, 0.051), 1.0 + ExpeditionClasses.MOMENTUM_SPEED_CAP), "teto de velocidade")
	T.ok(_near(ExpeditionClasses.momentum_speed(0, 0.05), 1.0), "parado: velocidade normal")
	T.ok(_near(ExpeditionClasses.momentum_crit(5, 0.04), 0.20), "Brecha x2: +20% de crítico com 5")
	T.ok(_near(ExpeditionClasses.momentum_crit(8, 0.04), ExpeditionClasses.MOMENTUM_CRIT_CAP), "teto de crítico")
	T.ok(_near(ExpeditionClasses.momentum_guard(5, 0.04), 0.80), "Couraça x2 com 5: -20%")
	T.ok(_near(ExpeditionClasses.momentum_guard(8, 0.04), 1.0 - ExpeditionClasses.MOMENTUM_GUARD_CAP), "teto da Couraça")
	T.ok(ExpeditionClasses.MOMENTUM_GUARD_CAP < ExpeditionClasses.CROWD_CAP, "o Guerreiro nunca segura tanto quanto o Tank")
	T.ok(_near(ExpeditionClasses.momentum_heal(1, 2.4), 2.4), "Sangue em Brasa x3: 2,4 por ganho")
	T.ok(_near(ExpeditionClasses.momentum_heal(2, 99.0), ExpeditionClasses.MOMENTUM_HEAL_CAP * 2.0), "teto de cura por ganho")
	T.ok(_near(ExpeditionClasses.momentum_heal(0, 2.4), 0.0), "sem ganho, sem cura")
	T.ok(_near(ExpeditionClasses.momentum_burst(100.0, 0.9, 5), 90.0), "Explosão x1 com 5: 90% do golpe")
	T.ok(_near(ExpeditionClasses.momentum_burst(100.0, 0.9, 7), 126.0), "com 7: proporcional (x1,4)")
	T.ok(_near(ExpeditionClasses.momentum_burst(100.0, 0.9, 8), 126.0), "trava em x1,4")
	T.ok(_near(ExpeditionClasses.momentum_burst(100.0, 0.9, 2), 0.0), "pouco Ímpeto: sem explosão")
	T.ok(_near(ExpeditionClasses.momentum_burst(100.0, 0.0, 5), 0.0), "sem a bênção: nada")


# ================================================================ bênçãos do Guerreiro
func test_warrior_boons_table() -> void:
	T.eq(ExpeditionUpgrades.validate().size(), 0, "tabela de melhorias sem problemas")
	var styles := {}
	for id in WARRIOR_BOONS:
		T.ok(ExpeditionUpgrades.has(id), "%s existe" % id)
		T.eq(ExpeditionUpgrades.class_of(id), "warrior", "%s é do Guerreiro" % id)
		T.ok(not ExpeditionUpgrades.in_pool(id), "%s fora do sorteio comum" % id)
		var mx := ExpeditionUpgrades.max_stacks(id)
		T.ok(mx >= 1 and mx <= 3, "%s acumula pouco (%d)" % [id, mx])
		T.ok(ExpeditionUpgrades.style_text(id).begins_with("Guerreiro · "), "%s mostra o estilo na carta" % id)
		var st := ExpeditionUpgrades.style_of(id)
		T.ok(st in WARRIOR_STYLES, "%s num estilo do Guerreiro (%s)" % [id, st])
		styles[st] = int(styles.get(st, 0)) + 1
		for k in ExpeditionUpgrades.DATA[id].add:
			T.ok(BASE.has(k), "%s mexe em %s, que existe no run_mods zerado" % [id, k])
			T.ok(str(k).begins_with("momentum_"), "%s só mexe no Ímpeto (%s): nada de dano ou defesa soltos" % [id, k])
	for s in WARRIOR_STYLES:
		T.ok(int(styles.get(s, 0)) >= 2, "estilo %s tem pelo menos 2 bênçãos" % s)
	for id in ExpeditionUpgrades.DATA:
		if ExpeditionUpgrades.class_of(id) == "warrior":
			T.ok(id in WARRIOR_BOONS, "%s listada no teste" % id)


func test_needs_gate_by_skill() -> void:
	T.ok(ExpeditionUpgrades.in_class_pool("golpes_encadeados", "warrior", []), "Encadeados valem desde o começo")
	T.ok(ExpeditionUpgrades.in_class_pool("explosao_impeto", "warrior", []), "Explosão vale só com o combo")
	T.ok(not ExpeditionUpgrades.in_class_pool("investida_predadora", "warrior", []), "Investida Predadora pede a Investida")
	T.ok(ExpeditionUpgrades.in_class_pool("investida_predadora", "warrior", ["sword_charge"]), "com a Investida sai")
	T.ok(not ExpeditionUpgrades.in_class_pool("furia_desperta", "warrior", ["sword_charge"]), "Fúria Desperta pede a Fúria")
	T.ok(ExpeditionUpgrades.in_class_pool("furia_desperta", "warrior", ["sword_fury"]), "Fúria Picante basta")
	T.ok(ExpeditionUpgrades.in_class_pool("furia_desperta", "warrior", ["sword_fury_great"]), "a da montante também")
	for id in WARRIOR_BOONS:
		T.ok(not ExpeditionUpgrades.in_class_pool(id, "tank", WARRIOR_KIT), "Tank não recebe %s" % id)
	for id in TANK_BOONS:
		T.ok(not ExpeditionUpgrades.in_class_pool(id, "warrior", ["sword_aegis", "sword_taunt", "sword_hammer"]),
			"Guerreiro não recebe %s do Tank" % id)


func test_warrior_roll_always_brings_a_warrior_boon() -> void:
	var seen := {}
	for s in 60:
		var out := ExpeditionUpgrades.roll(_rng(s), {}, 3, _ctx())
		T.eq(out.size(), 3, "3 opções")
		T.eq(ExpeditionUpgrades.class_of(out[0]), "warrior", "a 1ª é do Guerreiro (%s)" % out[0])
		for id in out:
			T.ok(ExpeditionUpgrades.class_of(id) != "tank", "nunca do Tank (%s)" % id)
			seen[id] = true
		T.eq(ExpeditionUpgrades.roll(_rng(s), {}, 3, _ctx()), out, "mesma semente, mesmas opções")
	T.ok(not seen.has("investida_predadora") and not seen.has("furia_desperta"), "sem a habilidade, a bênção dela não sai")
	T.ok(seen.has("furia") or seen.has("seiva") or seen.has("casca"), "as comuns continuam saindo")
	var full := {}
	for s in 120:
		for id in ExpeditionUpgrades.roll(_rng(s), {}, 3, _ctx(WARRIOR_KIT)):
			full[id] = true
	for id in WARRIOR_BOONS:
		T.ok(full.has(id), "com o kit todo, %s aparece" % id)
	# o Tank continua só com as dele
	for s in 40:
		for id in ExpeditionUpgrades.roll(_rng(s), {}, 3, {"class": "tank", "skills": []}):
			T.ok(ExpeditionUpgrades.class_of(id) != "warrior", "Tank não sorteia bênção do Guerreiro (%s)" % id)


func test_warrior_roll_falls_back_when_maxed_and_totals_stay_bounded() -> void:
	var taken := {}
	for id in WARRIOR_BOONS:
		taken[id] = 99
	for s in 10:
		for id in ExpeditionUpgrades.roll(_rng(s), taken, 3, _ctx(WARRIOR_KIT)):
			T.eq(ExpeditionUpgrades.class_of(id), "", "Guerreiro no máximo: só comuns (%s)" % id)
	# a build inteira no máximo, por cima da passiva: tudo dentro dos tetos
	var mods := ExpeditionUpgrades.apply_to(ExpeditionClasses.apply_passive(BASE, "warrior"), taken)
	var cap := ExpeditionMomentum.clamp_cap(float(mods.momentum_max))
	T.eq(cap, 7, "Encadeados x2: teto 7")
	T.ok(_near(float(mods.momentum_dmg), 0.05), "3% + 2 x 1% por acúmulo")
	T.ok(ExpeditionClasses.momentum_damage(cap, float(mods.momentum_dmg)) <= ExpeditionClasses.MOMENTUM_DMG_CAP,
		"dano do Ímpeto no máximo dentro do teto (+%.0f%%)" % (ExpeditionClasses.momentum_damage(cap, float(mods.momentum_dmg)) * 100.0))
	T.ok(ExpeditionClasses.momentum_speed(cap, float(mods.momentum_speed)) <= 1.0 + ExpeditionClasses.MOMENTUM_SPEED_CAP + 0.0001,
		"velocidade dentro do teto")
	T.ok(_near(float(mods.momentum_heal), 2.4), "Sangue em Brasa x3: 2,4 por ganho")
	T.ok(_near(float(mods.momentum_hold), 2.0) and _near(float(mods.momentum_kill), 2.0), "Pressão x2 e Lâmina x2")
	T.ok(_near(float(mods.momentum_fury), 1.0), "Fúria Desperta só 1 vez")
	T.ok(_near(float(mods.damage), 1.0) and _near(float(mods.defense), 0.0), "nada de dano/defesa fixos a mais")


# ================================================================ run (altar e recompensa)
func test_run_validates_warrior_boons_by_class() -> void:
	var r := _run_at(ANCESTRAL)
	r.skills.assign(["sword_charge"])
	T.ok(r.boon_offerable("golpes_encadeados") and r.boon_offerable("investida_predadora"), "Guerreiro com Investida: valem")
	T.ok(not r.boon_offerable("furia_desperta"), "sem a Fúria: não vale")
	T.ok(not r.boon_offerable("guarda_ferro"), "do Tank: não vale")
	T.ok(r.boon_offerable("furia"), "comum continua valendo")
	T.eq(r.roll_context(), {"class": "warrior", "skills": ["sword_charge"]}, "contexto do sorteio")
	T.ok(r.altar_option_valid(ANCESTRAL, "investida_predadora"), "Altar Ancestral aceita a bênção do Guerreiro")
	var t := _run_at(ANCESTRAL, "tank")
	T.ok(not t.altar_option_valid(ANCESTRAL, "golpes_encadeados"), "Tank não pode levar bênção do Guerreiro")
	T.ok(t.altar_option_valid(ANCESTRAL, "guarda_ferro"), "Tank segue com as dele")
	T.eq(r.add_modifier("furia_desperta", 3), 1, "Fúria Desperta trava em 1")
	T.eq(r.add_modifier("passo_lobo", 9), 3, "Passo do Lobo trava em 3")
	r.fail()
	T.ok(not r.is_active(), "a run acabou (o modo zera run_mods e o Ímpeto na volta)")


func test_evolution_altar_offers_warrior_boon() -> void:
	var hits := 0
	for s in 30:
		var out := ExpeditionSkills.roll_evolution(_rng(s), WARRIOR_KIT, WARRIOR_KIT, {}, 3, _ctx(WARRIOR_KIT))
		T.eq(out.size(), 3, "3 opções")
		for id in out:
			T.ok(ExpeditionUpgrades.class_of(id) != "tank", "nada do Tank (%s)" % id)
			if ExpeditionUpgrades.class_of(id) == "warrior":
				hits += 1
	T.ok(hits > 0, "o Altar Ancestral oferece bênçãos do Guerreiro (%d em 30)" % hits)
