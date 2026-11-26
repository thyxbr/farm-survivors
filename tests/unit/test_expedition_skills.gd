extends RefCounted
## Kit temporário de habilidades da expedição: o que um Altar da Deusa pode oferecer (ExpeditionSkills), o altar
## na run (ExpeditionRun) e os altares nos dados (ExpeditionDefs).

## Kits como o ItemDB.kit devolve (aqui escritos à mão: os testes não chamam funções do autoload).
const SWORD := ["sword_charge", "sword_quake", "sword_fury", "sword_whirl", "sword_vortex"]
const SHIELD := ["sword_aegis", "sword_earthquake", "sword_taunt", "sword_hammer", "sword_rally"]
const STAFF := ["staff_flame", "frost_nova", "staff_ember", "meteor_rain"]

## Rota pequena com um altar numa sala de luta e outro numa sala de descanso.
const ALTARS := {
	"name": "Teste", "map": "x", "start": "A",
	"rooms": {
		"A": {"kind": "start", "next": ["B"]},
		"B": {"kind": "combat", "next": ["C"], "altar": {"at": [-3.0, 1.0]},
			"waves": [[{"kind": "slime", "count": 1}]]},
		"C": {"kind": "rest", "next": ["D"], "altar": {"at": [2.0, 0.0]}},
		"D": {"kind": "boss", "next": []},
	},
}


func _run(d: Dictionary) -> ExpeditionRun:
	var r := ExpeditionRun.new()
	r.expedition_id = "teste"
	r.def = d
	return r


func _rng(s := 7) -> RandomNumberGenerator:
	var g := RandomNumberGenerator.new()
	g.seed = s
	return g


# ================================================================ ExpeditionSkills
func test_pool_is_the_characters_kit_without_ultimates() -> void:
	T.eq(ExpeditionSkills.pool(SWORD, []), ["sword_charge", "sword_quake", "sword_fury", "sword_vortex"],
		"espada: o kit da arma sem a ultimate (Turbilhão)")
	T.eq(ExpeditionSkills.pool(SHIELD, []), SHIELD, "espada + escudo: o Martelo (tecla 4) não é ultimate e entra")
	T.ok(not ("meteor_rain" in ExpeditionSkills.pool(STAFF, [])), "a ultimate do cajado fica de fora")
	T.eq(ExpeditionSkills.pool(SWORD, ["sword_quake", "sword_fury"]), ["sword_charge", "sword_vortex"],
		"o que já foi levado não volta a ser oferecido")


func test_pool_never_leaves_the_kit() -> void:
	# o altar só oferece o que o personagem pode usar: nada de outra classe nem de outra mão secundária
	for kit in [SWORD, SHIELD, STAFF]:
		for id in ExpeditionSkills.pool(kit, []):
			T.ok(kit.has(id), "%s é do kit oferecido" % id)
	T.ok(not ("sword_aegis" in ExpeditionSkills.pool(SWORD, [])), "a Égide só com escudo")
	T.eq(ExpeditionSkills.pool([], []).size(), 0, "sem arma, nada a oferecer")
	T.eq(ExpeditionSkills.pool(["nao_existe", "frost_nova"], []), ["frost_nova"], "id desconhecido é ignorado")


func test_roll_gives_three_distinct_choices() -> void:
	for s in 20:
		var c := ExpeditionSkills.roll(_rng(s), SWORD, [])
		T.eq(c.size(), ExpeditionSkills.CHOICES, "três opções (semente %d)" % s)
		var seen := {}
		for id in c:
			T.ok(not seen.has(id), "sem repetir (%s)" % id)
			seen[id] = true
			T.ok(ExpeditionSkills.pool(SWORD, []).has(id), "opção do pool (%s)" % id)
	T.eq(ExpeditionSkills.roll(_rng(), SWORD, ["sword_charge", "sword_quake", "sword_fury"]), ["sword_vortex"],
		"pool menor que 3: mostra o que sobrou")
	T.eq(ExpeditionSkills.roll(_rng(), SWORD, ["sword_charge", "sword_quake", "sword_fury", "sword_vortex"]).size(), 0,
		"pool vazio: nada")
	T.eq(ExpeditionSkills.roll(_rng(3), SWORD, []), ExpeditionSkills.roll(_rng(3), SWORD, []), "mesma semente, mesmo sorteio")


func test_active_kit_keeps_pick_order_and_drops_incompatible() -> void:
	T.eq(ExpeditionSkills.active_kit(SWORD, []), [], "começa vazio: só o ataque básico")
	T.eq(ExpeditionSkills.active_kit(SWORD, ["sword_vortex", "sword_quake"]), ["sword_vortex", "sword_quake"],
		"na ordem em que foram levadas (teclas 1, 2)")
	# trocou a espada pelo escudo no meio da run: o Golpe Sísmico some (no lugar dele o kit tem o Terremoto)
	T.eq(ExpeditionSkills.active_kit(SHIELD, ["sword_vortex", "sword_quake"]), [], "o que a arma de agora não usa some")
	T.eq(ExpeditionSkills.active_kit(SWORD, ["sword_fury", "sword_fury"]), ["sword_fury"], "sem repetir")


# ================================================================ ExpeditionDefs
func test_altar_data() -> void:
	T.eq(ExpeditionDefs.validate(ALTARS).size(), 0, "rota com altares é válida")
	T.ok(ExpeditionDefs.has_altar(ALTARS, "B") and ExpeditionDefs.has_altar(ALTARS, "C"), "salas com altar")
	T.ok(not ExpeditionDefs.has_altar(ALTARS, "A"), "sala sem altar")
	T.eq(ExpeditionDefs.altar_offset(ALTARS, "B"), Vector2(-3, 1), "lugar do altar a partir do centro da sala")
	T.eq(ExpeditionDefs.altar_offset(ALTARS, "A"), Vector2.ZERO, "sem altar: zero")
	T.ok(ExpeditionDefs.altar_needs_clear(ALTARS, "B"), "na sala de luta o altar espera a sala ser limpa")
	T.ok(not ExpeditionDefs.altar_needs_clear(ALTARS, "C"), "no descanso o altar já está desperto")
	var bad := ALTARS.duplicate(true)
	bad.rooms.D["altar"] = {"at": [0, 0]}
	T.ok("não pode ter altar" in "\n".join(ExpeditionDefs.validate(bad)), "sala de chefe não tem altar")
	bad = ALTARS.duplicate(true)
	bad.rooms.C["altar"] = true
	T.ok("altar precisa ser" in "\n".join(ExpeditionDefs.validate(bad)), "altar mal escrito")


func test_pantano_has_an_altar_before_the_next_fight() -> void:
	var d := ExpeditionDefs.get_def("pantano")
	var rooms := ExpeditionDefs.altar_rooms(d)
	T.ok(rooms.size() >= 1, "ao menos um altar no Pântano")
	var route := ExpeditionDefs.route(d)
	T.ok(rooms.has("Altar da Deusa") and rooms.has("Altar Ancestral"), "os dois altares da Deusa estão na rota")
	T.eq(route.find("Altar da Deusa"), route.find("Encruzilhada") + 1,
		"o primeiro altar vem logo depois da primeira luta (sai dela para ganhar uma habilidade)")
	T.ok(route.find("Altar Ancestral") > route.find("Clareira Funda"), "o segundo altar depois da Clareira")
	for r in rooms:
		T.ok(ExpeditionDefs.kind_of(d, r) != "boss", "%s: altar fora da sala do chefe" % r)
	# o altar não muda as ondas da Fase A
	T.eq(ExpeditionDefs.wave_count(d, "Encruzilhada"), 2, "Encruzilhada continua com 2 ondas")
	T.eq(ExpeditionDefs.wave_count(d, "Clareira Funda"), 3, "Clareira Funda continua com 3 ondas")


# ================================================================ ExpeditionRun
func test_run_starts_with_no_skills() -> void:
	var r := _run(ALTARS)
	r.start()
	T.eq(r.skills.size(), 0, "a run começa só com o ataque básico")
	T.ok(not r.altar_ready("B"), "altar de sala ainda não visitada dorme")
	T.ok(not r.altar_ready("A"), "sala sem altar")


func test_combat_altar_wakes_only_after_clear() -> void:
	var r := _run(ALTARS)
	r.start()
	r.enter_room("B")
	T.ok(not r.altar_ready("B"), "luta por fazer: o altar dorme")
	T.ok(not r.offer_altar("B", ["sword_quake"]), "não abre dormindo")
	r.start_encounter("B")
	T.ok(not r.altar_ready("B"), "luta em andamento: dorme")
	T.ok(r.clear_room("B"), "limpa a sala")
	T.ok(r.altar_ready("B"), "sala limpa: o altar desperta")


func test_altar_is_used_once() -> void:
	var r := _run(ALTARS)
	r.start()
	r.enter_room("B")
	r.start_encounter("B")
	r.clear_room("B")
	T.ok(r.offer_altar("B", ["sword_quake", "sword_fury", "sword_vortex", "sword_whirl", "sword_quake"]), "abre a escolha")
	T.eq(r.altar_choices("B"), ["sword_quake", "sword_fury", "sword_vortex"], "sem ultimate e sem repetir")
	T.ok(not r.choose_skill("B", "sword_charge"), "habilidade fora das opções não vale")
	T.ok(r.choose_skill("B", "sword_fury"), "escolhe")
	T.eq(r.skills, ["sword_fury"], "entra no kit da run")
	T.ok(r.is_altar_used("B") and not r.altar_ready("B"), "o altar fica gasto")
	T.ok(not r.offer_altar("B", ["sword_quake"]), "não abre de novo")
	T.ok(not r.choose_skill("B", "sword_quake"), "não dá uma segunda habilidade")
	T.eq(r.skills.size(), 1, "só uma do altar")


func test_closing_keeps_the_same_choices() -> void:
	var r := _run(ALTARS)
	r.start()
	r.enter_room("B")
	r.start_encounter("B")
	r.clear_room("B")
	r.enter_room("C")
	T.ok(r.altar_ready("C"), "descanso: o altar já está desperto")
	r.offer_altar("C", ["sword_quake", "sword_fury"])
	T.ok(r.offer_altar("C", ["sword_vortex", "sword_charge"]), "reabrir não sorteia de novo")
	T.eq(r.altar_choices("C"), ["sword_quake", "sword_fury"], "as mesmas opções de antes")
	# levou o Golpe Sísmico em outro altar: ele sai das opções guardadas deste
	r.offer_altar("B", ["sword_quake", "sword_vortex"])
	T.ok(r.choose_skill("B", "sword_quake"), "outro altar")
	T.eq(r.altar_choices("C"), ["sword_fury"], "o que já foi levado sai das opções guardadas")
	T.ok(r.choose_skill("C", "sword_fury"), "segundo altar")
	T.eq(r.skills, ["sword_quake", "sword_fury"], "kit cresce na ordem das escolhas")


func test_skills_end_with_the_run() -> void:
	var r := _run(ALTARS)
	r.start()
	r.enter_room("B")
	r.start_encounter("B")
	r.clear_room("B")
	r.offer_altar("B", ["sword_quake"])
	r.abandon()
	T.ok(not r.choose_skill("B", "sword_quake"), "fim da run: a escolha aberta morre")
	T.eq(r.pending_altar.size(), 0, "sem escolha pendente")
	T.ok(not r.altar_ready("B"), "altar não desperta fora da run")
	T.eq(r.summary().skills, [], "resumo com as habilidades da run")
