extends RefCounted
## Fase B do Pântano Sussurrante: a rota de 13 etapas (ExpeditionDefs.route), o evento do Santuário
## (ExpeditionEvents + ExpeditionRun.choose_event), a recompensa da Câmara, o descanso do Refúgio, as elites
## (líder, reforços, bênção em dobro) e o altar que dá bênção quando não há mais habilidade.

const STAGES := [
	["Entrada", "start"], ["Encruzilhada", "combat"], ["Altar da Deusa", "altar"],
	["Raízes Corrompidas", "combat"], ["Santuário Abandonado", "event"], ["Guardião das Raízes", "elite"],
	["Câmara das Oferendas", "reward"], ["Clareira Funda", "combat"], ["Altar Ancestral", "altar"],
	["Pântano Corrompido", "combat"], ["Arauto do Pântano", "elite"], ["Refúgio das Raízes", "rest"],
	["Antecâmara", "rest"], ["Trono da Rainha", "boss"],
]


func _def() -> Dictionary:
	return ExpeditionDefs.get_def("pantano")


func _run() -> ExpeditionRun:
	var r := ExpeditionRun.create("pantano")
	r.start()
	return r


## Anda pela rota até `room`, limpando as salas de luta do caminho (sem abrir as bênçãos delas).
func _walk(r: ExpeditionRun, room: String) -> void:
	var route := ExpeditionDefs.route(r.def)
	for j in range(route.find(r.current_room) + 1, route.find(room) + 1):
		T.ok(r.enter_room(route[j]), "entra em %s" % route[j])
		if j < route.find(room) and ExpeditionDefs.needs_clear(r.def, route[j]):
			r.clear_room(route[j])


# ================================================================ rota
func test_route_has_thirteen_stages_in_order() -> void:
	var route := ExpeditionDefs.route(_def())
	T.eq(route.size(), STAGES.size(), "chegada + 13 etapas")
	for i in STAGES.size():
		if i >= route.size():
			break
		T.eq(route[i], STAGES[i][0], "etapa %d: %s" % [i, STAGES[i][0]])
		T.eq(ExpeditionDefs.kind_of(_def(), route[i]), STAGES[i][1], "%s é do tipo %s" % [route[i], STAGES[i][1]])
	T.eq(route.size(), ExpeditionDefs.rooms(_def()).size(), "rota linear: toda sala está nela")
	for r in route:
		T.ok(ExpeditionDefs.next_of(_def(), r).size() <= 1, "%s: sem ramificação nesta fase" % r)


func test_room_levels_climb_and_stay_low() -> void:
	var last := 0
	for r in ExpeditionDefs.route(_def()):
		if not ExpeditionDefs.needs_clear(_def(), r):
			continue
		var lv := ExpeditionBalance.level_range(_def(), r, 0, 0)
		T.ok(lv.x >= last, "%s: nível %d não cai em relação à sala anterior (%d)" % [r, lv.x, last])
		T.ok(lv.y <= 5, "%s: nível máximo %d (nunca liga a placa de perigo)" % [r, lv.y])
		last = lv.x


func test_wave_sizes_stay_small() -> void:
	for r in ExpeditionDefs.route(_def()):
		for i in ExpeditionDefs.waves_of(_def(), r).size():
			var n := ExpeditionDefs.wave_size(_def(), r, i)
			T.ok(n >= 1 and n <= 5, "%s onda %d: %d monstros (nunca um bando enorme)" % [r, i + 1, n])


func test_every_room_kind_shows_up() -> void:
	var kinds := {}
	for r in ExpeditionDefs.route(_def()):
		kinds[ExpeditionDefs.kind_of(_def(), r)] = true
	for k in ["start", "combat", "altar", "event", "elite", "reward", "rest", "boss"]:
		T.ok(kinds.has(k), "a rota tem sala do tipo %s" % k)


# ================================================================ validação nova
func test_validate_catches_bad_new_rooms() -> void:
	var bad := _def().duplicate(true)
	bad.rooms["Santuário Abandonado"].erase("event")
	bad.rooms["Câmara das Oferendas"].erase("shrine")
	bad.rooms["Altar Ancestral"].erase("altar")
	bad.rooms["Guardião das Raízes"].waves[1][0].erase("leader")
	bad.rooms["Encruzilhada"]["leader"] = {"name": "X"}
	bad.rooms["Entrada"]["shrine"] = {"at": [0, 0]}
	var text := "\n".join(ExpeditionDefs.validate(bad))
	T.ok("sem \"event\"" in text, "evento sem id")
	T.ok("'Câmara das Oferendas' do tipo 'reward' sem santuário" in text, "recompensa sem baú")
	T.ok("sala de altar 'Altar Ancestral' sem altar" in text, "sala de altar sem altar")
	T.ok("exatamente um líder" in text, "elite sem líder")
	T.ok("só sala de elite tem líder" in text, "líder fora da elite")
	T.ok("'Entrada' do tipo 'start' não pode ter santuário" in text, "santuário em sala errada")


# ================================================================ evento do Santuário Abandonado
func test_event_table_is_valid() -> void:
	var p := ExpeditionEvents.validate()
	for x in p:
		T.ok(false, x)
	T.eq(p.size(), 0, "eventos sem problemas")
	T.ok(ExpeditionEvents.has(ExpeditionDefs.event_of(_def(), "Santuário Abandonado")), "o Santuário tem evento")
	for o in ExpeditionEvents.options("santuario"):
		var up := str(o.get("upgrade", ""))
		if up != "":
			T.ok(not ExpeditionUpgrades.in_pool(up), "%s só vem do evento (fora do sorteio)" % up)


func test_event_upgrades_never_rolled() -> void:
	for s in 40:
		var g := RandomNumberGenerator.new()
		g.seed = s
		for id in ExpeditionUpgrades.roll(g, {}):
			T.ok(ExpeditionUpgrades.in_pool(id), "sorteio %d sem bênção de evento (%s)" % [s, id])


func test_hp_cost_never_kills() -> void:
	T.ok(is_equal_approx(ExpeditionEvents.hp_after(100.0, 0.25), 75.0), "25% de 100")
	T.ok(is_equal_approx(ExpeditionEvents.hp_after(1.0, 0.25), 1.0), "com 1 de vida continua 1")
	T.ok(is_equal_approx(ExpeditionEvents.hp_after(40.0, 0.0), 40.0), "sem custo")


func test_event_is_chosen_once() -> void:
	var r := _run()
	T.ok(not r.shrine_ready("Santuário Abandonado"), "santuário de sala não visitada não responde")
	_walk(r, "Santuário Abandonado")
	T.ok(r.shrine_ready("Santuário Abandonado"), "visitado: santuário pronto")
	T.ok(r.choose_event("Santuário Abandonado", "inexistente").is_empty(), "opção que não existe")
	var o := r.choose_event("Santuário Abandonado", "sangue")
	T.ok(not o.is_empty() and float(o.hp_cost) > 0.0, "sangue tem custo em vida")
	T.eq(int(r.modifiers.get("pacto_sangue", 0)), 1, "Pacto de Sangue na run")
	T.ok(not r.shrine_ready("Santuário Abandonado") and r.is_shrine_used("Santuário Abandonado"), "gasto")
	T.ok(r.choose_event("Santuário Abandonado", "prece").is_empty(), "não escolhe duas vezes")
	T.eq(r.summary().shrines, {"Santuário Abandonado": "sangue"}, "resumo traz o evento")
	var damage := float(ExpeditionUpgrades.total_mods(r.modifiers).get("damage", 0.0))
	T.ok(is_equal_approx(damage, 0.25), "+25% de dano até o fim da run (%.2f)" % damage)


func test_event_refuse_and_protection() -> void:
	var a := _run()
	_walk(a, "Santuário Abandonado")
	T.ok(not a.choose_event("Santuário Abandonado", "recusar").is_empty(), "recusar vale")
	T.eq(a.modifiers.size(), 0, "recusar não dá nada")
	var b := _run()
	_walk(b, "Santuário Abandonado")
	b.choose_event("Santuário Abandonado", "prece")
	T.eq(int(b.modifiers.get("veu_deusa", 0)), 1, "Véu da Deusa")
	T.ok(float(ExpeditionUpgrades.total_mods(b.modifiers).defense) > 0.0, "proteção temporária: defesa")
	b.abandon()
	T.ok(b.choose_event("Santuário Abandonado", "sangue").is_empty(), "depois do fim, nada")


# ================================================================ Câmara das Oferendas
func test_offering_room_gives_one_blessing() -> void:
	var r := _run()
	_walk(r, "Câmara das Oferendas")
	T.ok(r.shrine_ready("Câmara das Oferendas"), "baú pronto")
	T.eq(r.rooms_awaiting_reward().size(), 2, "as bênçãos das lutas esperam (Encruzilhada e Guardião), a do baú não")
	T.ok(not r.rooms_awaiting_reward().has("Câmara das Oferendas"), "o baú não abre sozinho")
	T.ok(r.offer_reward("Câmara das Oferendas", ["furia", "seiva", "casca"]), "o baú oferece a bênção")
	T.eq(r.pending_stacks(), 1, "bênção normal")
	T.ok(not r.shrine_ready("Câmara das Oferendas"), "com a escolha na tela o baú não reabre")
	T.ok(r.choose_reward("seiva"), "escolhe")
	T.ok(r.is_shrine_used("Câmara das Oferendas") and not r.shrine_ready("Câmara das Oferendas"), "baú gasto")
	T.ok(not r.offer_reward("Câmara das Oferendas", ["furia"]), "não dá de novo")


# ================================================================ Refúgio das Raízes
func test_rest_heals_once() -> void:
	var r := _run()
	T.ok(is_equal_approx(r.rest("Refúgio das Raízes"), 0.0), "não descansa antes de chegar")
	_walk(r, "Refúgio das Raízes")
	var f := r.rest("Refúgio das Raízes")
	T.ok(f > 0.0 and f <= 0.6, "cura uma parte da vida (%.2f)" % f)
	T.ok(is_equal_approx(r.rest("Refúgio das Raízes"), 0.0), "uma vez só")
	T.ok(r.is_shrine_used("Refúgio das Raízes"), "fonte gasta")
	T.ok(is_equal_approx(ExpeditionDefs.heal_of(_def(), "Antecâmara"), 0.0), "a Antecâmara não cura")
	T.eq(r.modifiers.size(), 0, "descansar não mexe em atributo nenhum")


# ================================================================ elites
func test_elite_rooms_have_a_named_leader() -> void:
	for room in ["Guardião das Raízes", "Arauto do Pântano"]:
		var l := ExpeditionDefs.leader_of(_def(), room)
		T.eq(str(l.get("name", "")), room, "%s: líder com o nome da sala" % room)
		T.ok(not (l.get("call", []) as Array).is_empty(), "%s: o líder chama reforços" % room)
		var leaders := 0
		for i in ExpeditionDefs.waves_of(_def(), room).size():
			for g in ExpeditionDefs.wave_groups(_def(), room, i):
				if bool(g.get("leader", false)):
					leaders += 1
					T.ok(bool(g.get("elite", false)), "%s: o líder é de elite" % room)
					T.eq(i, ExpeditionDefs.waves_of(_def(), room).size() - 1, "%s: o líder vem na última onda" % room)
		T.eq(leaders, 1, "%s: um líder só" % room)
		T.eq(ExpeditionDefs.reward_stacks(_def(), room), 2, "%s: bênção em dobro" % room)
		T.ok(ExpeditionDefs.reward_on_clear(_def(), room), "%s: a bênção sai ao limpar" % room)
	T.eq(ExpeditionDefs.reward_stacks(_def(), "Clareira Funda"), 1, "sala comum: bênção normal")
	T.eq(ExpeditionBalance.role_of(false, false, true), "elite", "líder tem o papel de elite")


func test_elite_blessing_counts_double() -> void:
	var r := _run()
	_walk(r, "Guardião das Raízes")
	r.clear_room("Guardião das Raízes")
	T.ok(r.offer_reward("Guardião das Raízes", ["furia", "seiva", "casca"]), "elite limpa oferece")
	T.eq(r.pending_stacks(), 2, "em dobro")
	r.choose_reward("furia")
	T.eq(int(r.modifiers.furia), 2, "dois acúmulos de uma vez")
	T.eq(r.add_modifier("furia", 10), ExpeditionUpgrades.MAX_STACKS - 2, "acúmulo nunca passa do máximo")
	T.eq(int(r.modifiers.furia), ExpeditionUpgrades.MAX_STACKS, "no máximo")


# ================================================================ Altar Ancestral sem habilidade
func test_altar_without_skills_gives_a_blessing() -> void:
	var r := _run()
	_walk(r, "Altar Ancestral")
	T.ok(r.altar_ready("Altar Ancestral"), "altar desperto")
	T.ok(not r.offer_altar("Altar Ancestral", []), "nada para ensinar")
	T.ok(r.spend_altar("Altar Ancestral"), "o altar se apaga sem habilidade")
	T.ok(r.is_altar_used("Altar Ancestral") and r.skills.is_empty(), "gasto, sem habilidade nova")
	T.ok(ExpeditionDefs.grants_reward(_def(), "Altar Ancestral"), "a sala tem bênção")
	T.ok(r.offer_reward("Altar Ancestral", ["nevoa", "sussurro", "casca"]), "a bênção no lugar")
	T.ok(not r.spend_altar("Altar Ancestral"), "não gasta duas vezes")
	T.ok(not ExpeditionDefs.grants_reward(_def(), "Altar da Deusa"), "o primeiro altar não tem bênção extra")
