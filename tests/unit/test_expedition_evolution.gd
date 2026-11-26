extends RefCounted
## Evolução da build no Altar Ancestral (Fase C): melhorias de habilidade (ExpeditionUpgrades "<tipo>@<habilidade>"),
## o sorteio controlado das 3 opções (ExpeditionSkills.roll_evolution) e a escolha no ExpeditionRun.

const ANCESTRAL := "Altar Ancestral"
const FIRST_ALTAR := "Altar da Deusa"
## Kit da espada de uma mão sem escudo (ordem da barra), com a ultimate no meio.
const SWORD_KIT := ["sword_charge", "sword_quake", "sword_fury", "sword_whirl", "sword_vortex"]
const BASE := {"active": true, "damage": 1.0, "max_hp": 1.0, "max_hp_flat": 0.0, "speed": 1.0, "defense": 0.0,
	"regen": 0.0, "crit": 0.0, "cooldown": 1.0, "area": 1.0, "magnet": 1.0, "xp": 1.0, "gold": 1.0,
	"lifesteal": 0.0, "cdr": 0.0}


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001


func _rng(s: int) -> RandomNumberGenerator:
	var g := RandomNumberGenerator.new()
	g.seed = s
	return g


## Run no Pântano levada pela rota (limpando as lutas do caminho) até `room`.
func _run_at(room: String) -> ExpeditionRun:
	var r := ExpeditionRun.create("pantano")
	r.start()
	var route := ExpeditionDefs.route(r.def)
	for j in range(1, route.find(room) + 1):
		T.ok(r.enter_room(route[j]), "entra em %s" % route[j])
		if ExpeditionDefs.needs_clear(r.def, route[j]):
			r.clear_room(route[j])
	return r


# ================================================================ definição
func test_ancestral_altar_is_evolve() -> void:
	var d := ExpeditionDefs.get_def("pantano")
	T.eq(ExpeditionDefs.validate(d).size(), 0, "definição válida")
	T.eq(ExpeditionDefs.altar_mode(d, ANCESTRAL), ExpeditionDefs.ALTAR_EVOLVE, "Altar Ancestral evolui a build")
	T.eq(ExpeditionDefs.altar_mode(d, FIRST_ALTAR), ExpeditionDefs.ALTAR_SKILL, "o primeiro altar só ensina")
	T.eq(ExpeditionDefs.route(d).find(ANCESTRAL), 8, "etapa 8 da rota (a Entrada é a 0)")
	var broken := d.duplicate(true)
	broken.rooms[ANCESTRAL].altar["mode"] = "qualquer"
	T.ok(ExpeditionDefs.validate(broken).size() > 0, "modo de altar desconhecido é erro")


# ================================================================ melhorias de habilidade
func test_ability_upgrade_ids() -> void:
	T.ok(ExpeditionUpgrades.validate().is_empty(), "tabela válida: %s" % str(ExpeditionUpgrades.validate()))
	T.ok(ExpeditionUpgrades.has("potencia@sword_vortex"), "Potência no Vórtice (dano pelo multiplicador)")
	T.ok(not ExpeditionUpgrades.has("potencia@sword_quake"), "sem Potência no Golpe Sísmico (não lê o multiplicador)")
	T.ok(ExpeditionUpgrades.has("recarga@sword_quake"), "Recuperação em qualquer habilidade com recarga")
	T.ok(ExpeditionUpgrades.has("persistencia@sword_fury"), "Persistência no buff da Fúria")
	T.ok(not ExpeditionUpgrades.has("persistencia@sword_vortex"), "sem Persistência no que não tem duração")
	T.ok(not ExpeditionUpgrades.has("recarga@sword_whirl"), "ultimate não evolui nesta fase")
	T.ok(not ExpeditionUpgrades.has("potencia@inexistente") and not ExpeditionUpgrades.has("xyz@sword_vortex"),
		"id quebrado não vale")
	T.ok(not ExpeditionUpgrades.in_pool("potencia@sword_vortex"), "fora do sorteio das bênçãos comuns")
	T.eq(ExpeditionUpgrades.max_stacks("potencia@sword_vortex"), ExpeditionUpgrades.ABILITY_MAX_STACKS, "teto próprio")
	T.eq(ExpeditionUpgrades.display_name("potencia@sword_vortex"), "Vórtice Sombrio — Potência", "nome da carta")
	T.eq(ExpeditionUpgrades.value_text("potencia@sword_vortex"), "+15% de dano", "valor")
	T.eq(ExpeditionUpgrades.value_text("recarga@sword_quake", 2), "-20% de recarga", "valor acumulado")
	T.eq(ExpeditionUpgrades.level_text("recarga@sword_quake", {"recarga@sword_quake": 1}), "Nv 2/3", "nível")


func test_ability_upgrade_mods() -> void:
	var taken := {"potencia@sword_vortex_great": 2, "recarga@sword_quake": 1, "persistencia@sword_fury_great": 1,
		"furia": 1}
	var m := ExpeditionUpgrades.total_mods(taken, {"sword_fury": 10.0})
	T.ok(_near(float(m.get("ability_dmg:sword_vortex", 0.0)), 0.30), "Vórtice da montante usa a chave do Vórtice")
	T.ok(_near(float(m.get("ability_cd:sword_quake", 0.0)), 0.10), "recarga do Golpe Sísmico")
	T.ok(_near(float(m.get("ability_time:sword_fury", 0.0)), 2.0), "+20% de 10 s = +2 s na Fúria")
	T.ok(_near(float(m.get("damage", 0.0)), 0.12), "bênção comum continua somando")
	var applied := ExpeditionUpgrades.apply_to(BASE, taken, {"sword_fury": 10.0})
	T.ok(_near(float(applied["ability_cd:sword_quake"]), 0.10) and _near(float(applied.damage), 1.12),
		"run_mods com as chaves por habilidade")
	T.eq(ExpeditionUpgrades.apply_to(BASE, {}), BASE, "sem melhorias = run_mods padrão")
	var capped := ExpeditionUpgrades.total_mods({"potencia@sword_vortex": 99})
	T.ok(_near(float(capped["ability_dmg:sword_vortex"]), 0.15 * ExpeditionUpgrades.ABILITY_MAX_STACKS),
		"acúmulo limitado ao teto")
	T.ok(not ExpeditionUpgrades.total_mods({"persistencia@sword_fury": 1}).has("ability_time:sword_fury"),
		"sem duração base, a Persistência não inventa segundos")


# ================================================================ sorteio controlado
func test_roll_mixes_categories() -> void:
	for s in 40:
		var out := ExpeditionSkills.roll_evolution(_rng(s), SWORD_KIT, ["sword_vortex"], {})
		T.eq(out.size(), 3, "semente %d: 3 opções" % s)
		var kinds := {}
		for id in out:
			kinds[ExpeditionSkills.option_kind(id)] = true
			T.ok(id != "sword_whirl", "sem ultimate (%s)" % id)
			T.ok(id != "sword_vortex", "não oferece a habilidade já levada")
			if ExpeditionSkills.option_kind(id) == "ability":
				T.eq(ExpeditionUpgrades.ability_of(id), "sword_vortex", "melhoria só do que já tem (%s)" % id)
		T.eq(kinds.size(), 3, "semente %d: nova habilidade, melhoria e bênção (%s)" % [s, str(out)])
		var uniq := {}
		for id in out:
			uniq[id] = true
		T.eq(uniq.size(), 3, "sem opção repetida")
	T.eq(ExpeditionSkills.roll_evolution(_rng(7), SWORD_KIT, ["sword_vortex"], {}),
		ExpeditionSkills.roll_evolution(_rng(7), SWORD_KIT, ["sword_vortex"], {}), "mesma semente, mesmas opções")


func test_roll_without_owned_skills() -> void:
	var out := ExpeditionSkills.roll_evolution(_rng(3), SWORD_KIT, [], {})
	T.eq(out.size(), 3, "sem habilidade: ainda 3 opções")
	for id in out:
		T.ok(ExpeditionSkills.option_kind(id) in ["skill", "boon"], "nada a melhorar: troca por habilidade/bênção")


func test_roll_full_kit_and_maxed() -> void:
	var owned := ["sword_charge", "sword_quake", "sword_fury", "sword_vortex"]
	var out := ExpeditionSkills.roll_evolution(_rng(5), SWORD_KIT, owned, {})
	T.eq(out.size(), 3, "kit cheio: 3 opções")
	for id in out:
		T.ok(ExpeditionSkills.option_kind(id) != "skill", "sem habilidade nova para dar (%s)" % id)
	var maxed := {}
	for id in ExpeditionSkills.upgrade_pool(owned, {}):
		maxed[id] = ExpeditionUpgrades.ABILITY_MAX_STACKS
	for id in ExpeditionUpgrades.DATA:
		maxed[id] = ExpeditionUpgrades.MAX_STACKS
	T.eq(ExpeditionSkills.roll_evolution(_rng(5), SWORD_KIT, owned, maxed).size(), 0, "tudo no máximo: nada")
	var one_left := maxed.duplicate()
	one_left.erase("recarga@sword_quake")
	T.eq(ExpeditionSkills.roll_evolution(_rng(5), SWORD_KIT, owned, one_left), ["recarga@sword_quake"],
		"só o que ainda não chegou ao teto")


# ================================================================ escolha no altar
func test_choose_ability_upgrade_at_ancestral() -> void:
	var r := _run_at(ANCESTRAL)
	r.skills.append("sword_vortex")
	T.ok(r.altar_ready(ANCESTRAL), "Altar Ancestral desperto")
	var bad := ["sword_whirl", "potencia@sword_charge", "recarga@sword_quake", "pacto_sangue", "sword_vortex"]
	T.ok(not r.offer_altar(ANCESTRAL, bad), "nenhuma opção válida (ultimate, sem suporte, não levada, evento, já tem)")
	T.ok(r.offer_altar(ANCESTRAL, ["potencia@sword_vortex", "sword_quake", "furia", "potencia@sword_vortex"]),
		"oferta válida")
	T.eq(r.altar_choices(ANCESTRAL), ["potencia@sword_vortex", "sword_quake", "furia"], "sem repetida")
	T.ok(not r.choose_skill(ANCESTRAL, "nevoa"), "fora das opções não vale")
	T.ok(r.choose_skill(ANCESTRAL, "potencia@sword_vortex"), "escolhe a Potência")
	T.eq(r.modifiers, {"potencia@sword_vortex": 1}, "um acúmulo na run")
	T.eq(r.skills, ["sword_vortex"] as Array[String], "o kit não muda")
	T.ok(r.is_altar_used(ANCESTRAL) and not r.altar_ready(ANCESTRAL), "altar gasto")
	T.ok(not r.choose_skill(ANCESTRAL, "sword_quake"), "uma escolha só")
	T.ok(not r.offer_altar(ANCESTRAL, ["furia"]), "não reabre")
	T.ok(r.abandon(), "abandona")
	T.eq(ExpeditionRun.create("pantano").modifiers.size(), 0, "run nova sem a evolução da anterior")


func test_choose_skill_and_boon_at_ancestral() -> void:
	var r := _run_at(ANCESTRAL)
	r.skills.append("sword_charge")
	T.ok(r.offer_altar(ANCESTRAL, ["sword_vortex", "furia"]), "oferta")
	T.ok(r.choose_skill(ANCESTRAL, "sword_vortex"), "habilidade nova")
	T.eq(r.skills, ["sword_charge", "sword_vortex"] as Array[String], "entra no kit")
	T.eq(r.modifiers.size(), 0, "sem melhoria")
	var b := _run_at(ANCESTRAL)
	T.ok(b.offer_altar(ANCESTRAL, ["furia"]) and b.choose_skill(ANCESTRAL, "furia"), "bênção de run")
	T.eq(b.modifiers, {"furia": 1}, "bênção somada")


func test_first_altar_only_teaches() -> void:
	var r := _run_at(FIRST_ALTAR)
	T.ok(not r.offer_altar(FIRST_ALTAR, ["furia", "recarga@sword_quake"]), "altar comum não dá melhoria nem bênção")
	T.ok(r.offer_altar(FIRST_ALTAR, ["sword_quake", "furia"]), "só a habilidade fica")
	T.eq(r.altar_choices(FIRST_ALTAR), ["sword_quake"], "opções do altar comum")


func test_upgrade_stops_at_cap() -> void:
	var r := _run_at(ANCESTRAL)
	r.skills.append("sword_quake")
	r.modifiers["recarga@sword_quake"] = ExpeditionUpgrades.ABILITY_MAX_STACKS
	T.ok(not r.altar_option_valid(ANCESTRAL, "recarga@sword_quake"), "no teto não aparece")
	T.eq(r.add_modifier("recarga@sword_quake", 1), 0, "nem soma por fora")
