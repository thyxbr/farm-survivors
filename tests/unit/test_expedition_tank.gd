extends RefCounted
## Identidade do Tank na expedição (Fase E): a passiva Linha de Frente, as contas puras das bênçãos de classe
## (ExpeditionClasses) e o sorteio/validação das bênçãos do Tank (ExpeditionUpgrades, ExpeditionRun).

const ANCESTRAL := "Altar Ancestral"
## Kit da espada com escudo (o do Tank), na ordem da barra.
const TANK_KIT := ["sword_aegis", "sword_earthquake", "sword_taunt", "sword_hammer", "sword_rally"]
const TANK_BOONS := ["muralha_viva", "teimosia", "guarda_ferro", "egide_reforcada", "estilhacos", "correntes",
	"abalo", "revide", "sede"]
const BASE := {"active": true, "damage": 1.0, "max_hp": 1.0, "max_hp_flat": 0.0, "speed": 1.0, "defense": 0.0,
	"regen": 0.0, "crit": 0.0, "cooldown": 1.0, "area": 1.0, "magnet": 1.0, "xp": 1.0, "gold": 1.0,
	"lifesteal": 0.0, "cdr": 0.0, "crowd_guard": 0.0, "block_power": 0.0, "block_guard": 0.0, "aegis_integrity": 0.0,
	"aegis_burst": 0.0, "taunt_time": 0.0, "stun_bonus": 0.0, "guard_dmg": 0.0}


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001


func _rng(s: int) -> RandomNumberGenerator:
	var g := RandomNumberGenerator.new()
	g.seed = s
	return g


func _ctx(skills: Array = []) -> Dictionary:
	return {"class": ExpeditionClasses.TANK, "skills": skills}


func _run_at(room: String, cls := "tank") -> ExpeditionRun:
	var r := ExpeditionRun.create("pantano")
	r.char_class = cls
	r.start()
	var route := ExpeditionDefs.route(r.def)
	for j in range(1, route.find(room) + 1):
		r.enter_room(route[j])
		if ExpeditionDefs.needs_clear(r.def, route[j]):
			r.clear_room(route[j])
	return r


# ================================================================ passiva
func test_only_the_tank_has_identity() -> void:
	T.ok(ExpeditionClasses.has_identity("tank"), "Tank tem identidade na expedição")
	for c in ["warrior", "archer", "mage", "healer", ""]:
		T.ok(not ExpeditionClasses.has_identity(c), "%s ainda sem identidade (só o Tank nesta etapa)" % c)
		T.eq(ExpeditionClasses.apply_passive(BASE, c), BASE, "%s: run_mods intactos" % c)
	var m := ExpeditionClasses.apply_passive(BASE, "tank")
	T.ok(_near(float(m.crowd_guard), 0.04), "Linha de Frente: 4% por inimigo")
	T.ok(_near(float(BASE.crowd_guard), 0.0), "não mexe no run_mods de entrada")
	for k in ExpeditionClasses.passive_mods("tank"):
		T.ok(k in ExpeditionUpgrades.RUN_MOD_KEYS, "passiva mexe em %s, chave conhecida" % k)
		T.ok(BASE.has(k), "%s existe no run_mods zerado (some na volta)" % k)


func test_crowd_mult() -> void:
	T.ok(_near(ExpeditionClasses.crowd_mult(0, 0.04), 1.0), "ninguém perto: dano cheio")
	T.ok(_near(ExpeditionClasses.crowd_mult(3, 0.0), 1.0), "sem a passiva: dano cheio")
	T.ok(_near(ExpeditionClasses.crowd_mult(1, 0.04), 0.96), "1 inimigo: -4%")
	T.ok(_near(ExpeditionClasses.crowd_mult(3, 0.04), 0.88), "3 inimigos: -12%")
	T.ok(_near(ExpeditionClasses.crowd_mult(5, 0.04), 0.80), "5 inimigos: -20%")
	T.ok(_near(ExpeditionClasses.crowd_mult(12, 0.04), 0.80), "conta no máximo 5 inimigos")
	# Muralha Viva x3: 0.04 + 0.06 = 10% por inimigo, mas o teto é 40%
	T.ok(_near(ExpeditionClasses.crowd_mult(3, 0.10), 0.70), "Muralha x3 com 3 inimigos: -30%")
	T.ok(_near(ExpeditionClasses.crowd_mult(5, 0.10), 1.0 - ExpeditionClasses.CROWD_CAP), "teto de 40%")
	T.ok(_near(ExpeditionClasses.crowd_mult(4, -1.0), 1.0), "valor negativo não cura")
	T.ok(_near(ExpeditionClasses.crowd_mult(4, INF), 1.0), "valor não finito não zera o dano")


# ================================================================ contas das bênçãos
func test_block_item_boost_respects_shield_caps() -> void:
	var wood := {"block": 0.6, "guard": 0.0}
	T.eq(ExpeditionClasses.block_item(wood, 0.0, 0.0), wood, "sem bênção: o mesmo escudo")
	var b := ExpeditionClasses.block_item(wood, 0.1, 0.2)
	T.ok(_near(float(b.block), 0.7) and _near(float(b.guard), 0.2), "Guarda de Ferro x1")
	T.ok(_near(float(wood.block), 0.6), "não mexe no item original")
	var plain := ShieldRules.resolve(20.0, 100.0, 0, wood)
	var iron := ShieldRules.resolve(20.0, 100.0, 0, b)
	T.ok(iron.damage < plain.damage, "segura mais do golpe (%.1f < %.1f)" % [iron.damage, plain.damage])
	T.ok(iron.stamina > plain.stamina, "gasta menos fôlego")
	var huge := ExpeditionClasses.block_item(wood, 3.0, 3.0)
	T.ok(ShieldRules.block_of(huge) <= 0.95 and ShieldRules.guard_of(huge) <= 0.6, "tetos do ShieldRules valem")
	T.ok(ShieldRules.resolve(50.0, 100.0, 0, huge).damage > 0.0, "o bloqueio nunca vira imunidade")
	var none := ExpeditionClasses.block_item({}, 0.1, 0.0)
	T.ok(_near(float(none.block), ShieldRules.DEFAULT_BLOCK + 0.1), "item sem campos: madeira + bônus")


func test_burst_and_guard_damage() -> void:
	T.ok(_near(ExpeditionClasses.burst_damage(100.0, 0.0), 0.0), "sem Estilhaços: nada")
	T.ok(_near(ExpeditionClasses.burst_damage(2.0, 0.6), 0.0), "Égide que quase não segurou: sem estalo")
	T.ok(_near(ExpeditionClasses.burst_damage(100.0, 0.6), 60.0), "60% do que segurou")
	T.ok(_near(ExpeditionClasses.burst_damage(100.0, 1.8), 180.0), "x3 acúmulos")
	T.ok(_near(ExpeditionClasses.guard_damage_bonus(12.0, 0.0), 0.0), "sem Revide: nada")
	T.ok(_near(ExpeditionClasses.guard_damage_bonus(12.0, 0.01), 0.12), "12 de defesa: +12% de dano")
	T.ok(_near(ExpeditionClasses.guard_damage_bonus(-5.0, 0.01), 0.0), "defesa negativa não tira dano")


# ================================================================ bênçãos do Tank
func test_tank_boons_table() -> void:
	T.eq(ExpeditionUpgrades.validate().size(), 0, "tabela de melhorias sem problemas")
	var styles := {}
	for id in TANK_BOONS:
		T.ok(ExpeditionUpgrades.has(id), "%s existe" % id)
		T.eq(ExpeditionUpgrades.class_of(id), "tank", "%s é do Tank" % id)
		T.ok(not ExpeditionUpgrades.in_pool(id), "%s fora do sorteio comum" % id)
		T.eq(ExpeditionUpgrades.max_stacks(id), 3, "%s acumula até 3" % id)
		T.ok(ExpeditionUpgrades.style_text(id).begins_with("Tank · "), "%s mostra o estilo na carta" % id)
		styles[ExpeditionUpgrades.style_of(id)] = int(styles.get(ExpeditionUpgrades.style_of(id), 0)) + 1
		for k in ExpeditionUpgrades.DATA[id].add:
			T.ok(BASE.has(k), "%s mexe em %s, que existe no run_mods zerado" % [id, k])
	for s in ExpeditionClasses.STYLES:
		T.ok(int(styles.get(s, 0)) >= 2, "estilo %s tem pelo menos 2 bênçãos" % s)
	T.eq(ExpeditionUpgrades.style_text("furia"), "", "bênção comum sem estilo")
	T.eq(ExpeditionUpgrades.max_stacks("furia"), ExpeditionUpgrades.MAX_STACKS, "comum segue com 5")


func test_needs_gate_by_skill() -> void:
	T.ok(ExpeditionUpgrades.in_class_pool("guarda_ferro", "tank", []), "bloqueio vale desde o começo")
	T.ok(ExpeditionUpgrades.in_class_pool("revide", "tank", []), "Revide vale desde o começo")
	T.ok(not ExpeditionUpgrades.in_class_pool("estilhacos", "tank", []), "Estilhaços pede a Égide")
	T.ok(ExpeditionUpgrades.in_class_pool("estilhacos", "tank", ["sword_aegis"]), "com a Égide sai")
	T.ok(not ExpeditionUpgrades.in_class_pool("correntes", "tank", ["sword_aegis"]), "Correntes pede a Provocação")
	T.ok(ExpeditionUpgrades.in_class_pool("abalo", "tank", ["sword_hammer"]), "Abalo: Martelo basta")
	T.ok(ExpeditionUpgrades.in_class_pool("abalo", "tank", ["sword_earthquake"]), "Abalo: Terremoto basta")
	T.ok(not ExpeditionUpgrades.in_class_pool("guarda_ferro", "warrior", []), "Guerreiro não recebe do Tank")
	T.ok(not ExpeditionUpgrades.in_class_pool("furia", "tank", []), "comum não é bênção de classe")


func test_roll_without_class_is_unchanged() -> void:
	for s in 40:
		var a := ExpeditionUpgrades.roll(_rng(s), {})
		T.eq(ExpeditionUpgrades.roll(_rng(s), {}, ExpeditionUpgrades.CHOICES, {}), a, "ctx vazio = sorteio de antes")
		for id in a:
			T.eq(ExpeditionUpgrades.class_of(id), "", "sem classe, sem bênção de classe (%s)" % id)
		for id in ExpeditionUpgrades.roll(_rng(s), {}, 3, {"class": "warrior", "skills": []}):
			T.eq(ExpeditionUpgrades.class_of(id), "", "Guerreiro: só comuns (%s)" % id)


func test_tank_roll_always_brings_a_tank_boon() -> void:
	var seen := {}
	for s in 60:
		var out := ExpeditionUpgrades.roll(_rng(s), {}, 3, _ctx())
		T.eq(out.size(), 3, "3 opções")
		T.eq(ExpeditionUpgrades.class_of(out[0]), "tank", "a 1ª é do Tank (%s)" % out[0])
		var uniq := {}
		for id in out:
			T.ok(not uniq.has(id), "sem repetir")
			uniq[id] = true
			T.ok(ExpeditionUpgrades.in_pool(id) or ExpeditionUpgrades.in_class_pool(id, "tank", []),
				"%s pode sair sem habilidades" % id)
			seen[id] = true
		T.eq(ExpeditionUpgrades.roll(_rng(s), {}, 3, _ctx()), out, "mesma semente, mesmas opções")
	T.ok(not seen.has("estilhacos") and not seen.has("correntes") and not seen.has("abalo"),
		"sem a habilidade, a bênção dela não aparece")
	T.ok(seen.has("furia") or seen.has("seiva") or seen.has("casca"), "as comuns continuam saindo")
	var full := {}
	for s in 80:
		for id in ExpeditionUpgrades.roll(_rng(s), {}, 3, _ctx(TANK_KIT)):
			full[id] = true
	for id in TANK_BOONS:
		T.ok(full.has(id), "com o kit todo, %s aparece" % id)


func test_tank_roll_falls_back_when_class_boons_maxed() -> void:
	var taken := {}
	for id in TANK_BOONS:
		taken[id] = 3
	for s in 10:
		for id in ExpeditionUpgrades.roll(_rng(s), taken, 3, _ctx(TANK_KIT)):
			T.eq(ExpeditionUpgrades.class_of(id), "", "Tank no máximo: só comuns (%s)" % id)
	var n := ExpeditionUpgrades.total_mods(taken)
	T.ok(_near(float(n.crowd_guard), 0.06) and _near(float(n.regen), 4.5), "Muralha x3 e Teimosia x3 somam")
	T.ok(_near(float(n.aegis_integrity), 1.05) and _near(float(n.stun_bonus), 1.5), "Égide e Abalo somam")
	taken["muralha_viva"] = 9
	T.ok(_near(float(ExpeditionUpgrades.total_mods(taken).crowd_guard), 0.06), "acúmulo travado no máximo")


# ================================================================ run (altar e recompensa)
func test_run_validates_class_boons_by_class() -> void:
	var r := _run_at(ANCESTRAL)
	r.skills.assign(["sword_aegis"])
	T.ok(r.boon_offerable("guarda_ferro") and r.boon_offerable("estilhacos"), "Tank com Égide: valem")
	T.ok(not r.boon_offerable("correntes"), "sem a Provocação: não vale")
	T.ok(r.boon_offerable("furia"), "comum continua valendo")
	T.eq(r.roll_context(), {"class": "tank", "skills": ["sword_aegis"]}, "contexto do sorteio")
	T.ok(r.altar_option_valid(ANCESTRAL, "estilhacos"), "Altar Ancestral aceita a bênção do Tank")
	var w := _run_at(ANCESTRAL, "warrior")
	T.ok(not w.altar_option_valid(ANCESTRAL, "guarda_ferro"), "Guerreiro não pode levar bênção do Tank")
	T.ok(w.altar_option_valid(ANCESTRAL, "furia"), "Guerreiro leva as comuns")


func test_tank_boon_from_reward_stacks_and_ends_with_run() -> void:
	var r := _run_at(ANCESTRAL)
	var opts := ExpeditionUpgrades.roll(_rng(3), r.modifiers, 3, r.roll_context())
	T.eq(ExpeditionUpgrades.class_of(opts[0]), "tank", "a recompensa traz uma do Tank")
	T.eq(r.add_modifier("muralha_viva", 5), 3, "trava em 3 acúmulos")
	var mods := ExpeditionUpgrades.apply_to(ExpeditionClasses.apply_passive(BASE, "tank"), r.modifiers)
	T.ok(_near(float(mods.crowd_guard), 0.10), "passiva 4% + Muralha x3 6% = 10% por inimigo")
	T.ok(_near(ExpeditionClasses.crowd_mult(5, float(mods.crowd_guard)), 0.60), "build de defesa no teto: -40%")
	r.fail()
	T.ok(not r.is_active(), "a run acabou (o modo zera run_mods na volta)")


func test_evolution_altar_offers_tank_boon() -> void:
	var owned := ["sword_aegis", "sword_earthquake", "sword_taunt", "sword_hammer", "sword_rally"]
	var hits := 0
	for s in 30:
		var out := ExpeditionSkills.roll_evolution(_rng(s), TANK_KIT, owned, {}, 3, _ctx(owned))
		T.eq(out.size(), 3, "3 opções")
		for id in out:
			if ExpeditionUpgrades.class_of(id) == "tank":
				hits += 1
	T.ok(hits > 0, "o Altar Ancestral oferece bênçãos do Tank (%d em 30)" % hits)
	var plain := ExpeditionSkills.roll_evolution(_rng(4), TANK_KIT, owned, {})
	for id in plain:
		T.eq(ExpeditionUpgrades.class_of(id), "", "sem contexto: sem bênção de classe (%s)" % id)
