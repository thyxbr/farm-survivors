extends RefCounted
## Fase D do Pântano Sussurrante: encontros especiais (ExpeditionEncounters + ExpeditionRun.encounters) — emboscada,
## caçada ao elite, ritual corrompido e defesa das oferendas —, a distribuição deles pela rota de 13 etapas, a
## validação, o começo/fim de cada um, a bênção que não se repete e que as lutas tradicionais seguem iguais.

const SPECIAL := {
	"Raízes Corrompidas": ExpeditionEncounters.AMBUSH,
	"Clareira Funda": ExpeditionEncounters.OFFERING,
	"Pântano Corrompido": ExpeditionEncounters.RITUAL,
	"Arauto do Pântano": ExpeditionEncounters.HUNT,
}
const TRADITIONAL := ["Encruzilhada", "Guardião das Raízes", "Trono da Rainha"]


func _def() -> Dictionary:
	return ExpeditionDefs.get_def("pantano")


func _run() -> ExpeditionRun:
	var r := ExpeditionRun.create("pantano")
	r.start()
	return r


## Anda pela rota até `room` (entra nela), limpando as salas de luta do caminho como o jogo faz: tranca, passa
## por todas as ondas, quebra o foco do ritual, limpa e escolhe a bênção que a sala abrir.
func _walk(r: ExpeditionRun, room: String) -> void:
	var route := ExpeditionDefs.route(r.def)
	for j in range(route.find(r.current_room) + 1, route.find(room) + 1):
		T.ok(r.enter_room(route[j]), "entra em %s" % route[j])
		if j < route.find(room) and ExpeditionDefs.needs_clear(r.def, route[j]):
			_fight(r, route[j])
			if r.has_pending_reward():
				r.choose_reward(str(r.pending_reward.choices[0]))


## A luta inteira de `room` (a run já está nela): tranca, todas as ondas, foco quebrado e sala limpa.
func _fight(r: ExpeditionRun, room: String) -> void:
	T.ok(r.start_encounter(room), "%s: a luta começa" % room)
	while r.has_next_wave(room):
		r.advance_wave(room)
	if r.encounter_type(room) == ExpeditionEncounters.RITUAL:
		r.break_focus(room)
	T.ok(r.clear_room(room), "%s: limpa" % room)
	# bênção ao limpar, ou pelo baú da Defesa das Oferendas (que só acende com a sala limpa)
	if ExpeditionDefs.reward_on_clear(r.def, room) or r.shrine_ready(room):
		r.offer_reward(room, ["furia", "seiva", "casca"])


# ================================================================ distribuição pela rota
func test_four_special_encounters_on_the_route() -> void:
	var d := _def()
	T.eq(ExpeditionDefs.route(d).size(), 14, "a rota continua com a chegada + 13 etapas")
	var found := ExpeditionEncounters.rooms(d)
	T.eq(found.size(), SPECIAL.size(), "quatro salas com encontro especial (%s)" % [found])
	for room in SPECIAL:
		T.eq(ExpeditionEncounters.type_of(d, room), SPECIAL[room], "%s: %s" % [room, SPECIAL[room]])
		T.ok(ExpeditionDefs.needs_clear(d, room), "%s: o encontro especial é numa sala de luta" % room)
	var types := {}
	for room in found:
		types[ExpeditionEncounters.type_of(d, room)] = true
	T.eq(types.size(), ExpeditionEncounters.TYPES.size(), "cada tipo aparece uma vez")


func test_traditional_fights_stay_traditional() -> void:
	var d := _def()
	for room in TRADITIONAL:
		T.eq(ExpeditionEncounters.type_of(d, room), "", "%s: luta tradicional" % room)
		T.eq(ExpeditionEncounters.spawn_of(d, room, 0), "", "%s: nasce espalhado como sempre" % room)
		T.ok(is_equal_approx(ExpeditionEncounters.telegraph_of(d, room, 0.9), 0.9), "%s: aviso de sempre" % room)
		T.ok(is_equal_approx(ExpeditionEncounters.daze_of(d, room), 0.0), "%s: sem atordoamento ao nascer" % room)
		T.eq(ExpeditionEncounters.bonus_stacks(d, room, true), 0, "%s: sem acúmulo extra" % room)
	var fights := ExpeditionDefs.route(d).filter(func(r: String) -> bool: return ExpeditionDefs.needs_clear(d, r))
	T.ok(fights.size() - SPECIAL.size() >= 3, "ao menos três lutas tradicionais (%d de %d)" % [fights.size() - SPECIAL.size(), fights.size()])
	T.ok(ExpeditionDefs.reward_on_clear(d, "Encruzilhada"), "Encruzilhada: a bênção sai ao limpar, como antes")
	T.ok(ExpeditionDefs.reward_on_clear(d, "Guardião das Raízes"), "Guardião: a bênção sai ao limpar, como antes")
	T.ok(ExpeditionDefs.leader_of(d, "Guardião das Raízes").size() > 0, "Guardião continua elite clássica")


func test_room_shape_and_kind_rules() -> void:
	var d := _def()
	var p := ExpeditionDefs.validate(d)
	for x in p:
		T.ok(false, x)
	T.eq(p.size(), 0, "Pântano válido com os encontros")
	T.eq(ExpeditionDefs.shrine_kind(d, "Clareira Funda"), "reward", "o baú da Defesa das Oferendas é de recompensa")
	T.ok(ExpeditionDefs.has_shrine(d, "Clareira Funda") and ExpeditionDefs.shrine_needs_clear(d, "Clareira Funda"),
		"o baú da Clareira só abre com a sala limpa")
	T.ok(not ExpeditionDefs.shrine_needs_clear(d, "Câmara das Oferendas"), "o baú da Câmara abre na hora, como antes")
	T.ok(not ExpeditionDefs.reward_on_clear(d, "Clareira Funda"), "a bênção da Clareira sai pelo baú")
	T.ok(ExpeditionDefs.grants_reward(d, "Clareira Funda"), "mas a Clareira continua dando bênção")
	T.eq(ExpeditionDefs.reward_rooms(d).size(), 6, "o mesmo número de bênçãos no caminho")
	T.eq(ExpeditionDefs.shrine_rooms(d).size(), 4, "evento, Câmara, Clareira e Refúgio têm santuário")
	var lead := ExpeditionDefs.wave_groups(d, "Arauto do Pântano", 0)
	T.ok(lead.any(func(g) -> bool: return bool(g.get("leader", false)) and bool(g.get("elite", false))),
		"caçada: o líder de elite já vem na primeira onda")
	T.eq(ExpeditionEncounters.focus_kind(d, "Pântano Corrompido"), "foco_corrupcao", "ritual com o Foco da Corrupção")


func test_validate_catches_bad_encounters() -> void:
	var bad := _def().duplicate(true)
	bad.rooms["Encruzilhada"]["encounter"] = {"type": "nada"}
	bad.rooms["Altar da Deusa"]["encounter"] = {"type": "ambush"}
	bad.rooms["Pântano Corrompido"].encounter.erase("focus")
	bad.rooms["Pântano Corrompido"].encounter["pulse_dmg"] = 0.6
	bad.rooms["Clareira Funda"].erase("shrine")
	bad.rooms["Raízes Corrompidas"].encounter["spawn"] = ["ring", "chuva"]
	bad.rooms["Guardião das Raízes"]["encounter"] = {"type": "hunt", "regroup": [{"kind": "slime", "count": 1}]}
	var text := "\n".join(ExpeditionDefs.validate(bad))
	T.ok("encontro 'nada' desconhecido" in text, "tipo desconhecido")
	T.ok("'Altar da Deusa': encontro 'ambush' só em sala do tipo combat" in text, "encontro em sala sem luta")
	T.ok("ritual sem foco" in text, "ritual sem foco")
	T.ok("acima de 25% da vida" in text, "pulso forte demais")
	T.ok("sem o baú" in text, "defesa das oferendas sem baú")
	T.ok("jeito de nascer 'chuva'" in text, "emboscada com jeito de nascer desconhecido")
	T.ok("na caçada o líder vem na primeira onda" in text, "caçada com o líder na última onda")


# ================================================================ regras puras
func test_ambush_rules_are_fair() -> void:
	var d := _def()
	var room := "Raízes Corrompidas"
	T.eq(ExpeditionEncounters.spawn_of(d, room, 0), "ring", "1ª onda em roda do jogador")
	T.eq(ExpeditionEncounters.spawn_of(d, room, 1), "behind", "2ª onda na boca por onde ele entrou")
	T.eq(ExpeditionEncounters.spawn_of(d, room, 7), "behind", "onda além da lista usa o último jeito")
	T.ok(ExpeditionEncounters.telegraph_of(d, room, 0.9) > 0.9, "a emboscada avisa mais tempo que uma onda comum")
	T.ok(ExpeditionEncounters.daze_of(d, room) >= 0.5, "quem brota fica atordoado (sem golpe na hora)")
	T.ok(ExpeditionEncounters.ring_radius(d, room) >= ExpeditionEncounters.MIN_RING, "a roda nunca cola no jogador")
	T.ok(not ExpeditionEncounters.ambush_triggered(d, room, 2.0), "na boca da sala ainda não dispara")
	T.ok(not ExpeditionEncounters.ambush_triggered(d, room, 4.5), "onde uma luta comum já trancaria, ainda não")
	T.ok(ExpeditionEncounters.ambush_triggered(d, room, 6.5), "no meio da sala dispara")
	T.ok(not ExpeditionEncounters.ambush_triggered(d, "Encruzilhada", 99.0), "sala comum não tem emboscada")
	var pts := ExpeditionEncounters.ring_points(Vector2(10, -4), 3, 6.0, 0.4)
	T.eq(pts.size(), 3, "três pontos")
	for p in pts:
		T.ok(absf(p.distance_to(Vector2(10, -4)) - 6.0) < 0.001, "ponto a 6 m do centro")
	T.ok(pts[0].distance_to(pts[1]) > 6.0, "pontos espalhados pela roda")


func test_ritual_pulse_rules() -> void:
	var d := _def()
	var room := "Pântano Corrompido"
	var dmg := ExpeditionEncounters.pulse_damage(d, room, 200.0)
	T.ok(dmg > 0.0 and dmg <= 200.0 * ExpeditionEncounters.MAX_PULSE_DMG, "pulso tira uma parte pequena da vida (%.0f)" % dmg)
	T.ok(ExpeditionEncounters.num(d, room, "pulse_warn") >= 0.8, "o pulso é avisado no chão antes")
	T.ok(not ExpeditionEncounters.pulse_summons(d, room, 1), "o 1º pulso não chama")
	T.ok(ExpeditionEncounters.pulse_summons(d, room, 2), "o 2º chama")
	T.ok(ExpeditionEncounters.pulse_summons(d, room, 4) and not ExpeditionEncounters.pulse_summons(d, room, 3), "a cada 2")
	T.ok(not ExpeditionEncounters.pulse_summons(d, "Encruzilhada", 2), "sala comum não tem ritual")


func test_offering_bonus_rules() -> void:
	var d := _def()
	T.ok(ExpeditionEncounters.offering_intact(d, "Clareira Funda", 30.0), "rápido: intactas")
	T.ok(not ExpeditionEncounters.offering_intact(d, "Clareira Funda", 500.0), "devagar: apagadas")
	T.eq(ExpeditionEncounters.bonus_stacks(d, "Clareira Funda", true), 1, "intactas: +1 acúmulo")
	T.eq(ExpeditionEncounters.bonus_stacks(d, "Clareira Funda", false), 0, "apagadas: nada a mais")


# ================================================================ emboscada na run
func test_ambush_starts_once_and_releases_the_room() -> void:
	var r := _run()
	var room := "Raízes Corrompidas"
	_walk(r, room)
	T.ok(r.start_encounter(room), "a emboscada tranca a sala")
	T.ok(r.is_locked() and bool(r.encounters[room].get("sprung", false)), "disparou")
	T.ok(not r.can_enter("Santuário Abandonado") and not r.can_enter("Altar da Deusa"), "ninguém sai")
	T.ok(not r.clear_room(room), "a 1ª onda caiu, a 2ª ainda vem")
	T.ok(r.advance_wave(room) and not r.has_next_wave(room), "2ª onda (a da boca)")
	T.ok(r.clear_room(room) and not r.is_locked(), "limpa e destranca")
	T.ok(r.can_enter("Santuário Abandonado"), "a passagem abriu")
	T.ok(not r.start_encounter(room), "voltar à sala não dispara a emboscada de novo")
	T.ok(not r.has_pending_reward(), "a emboscada não tem bênção (o ritmo respira até o evento)")


# ================================================================ ritual na run
func test_ritual_needs_the_focus_broken() -> void:
	var r := _run()
	var room := "Pântano Corrompido"
	_walk(r, room)
	T.ok(not r.break_focus(room), "sem luta começada não há foco para quebrar")
	T.ok(r.start_encounter(room), "o ritual começa")
	var total := r.wave_total(room)
	T.eq(total, 3, "três ondas")
	while r.has_next_wave(room):
		r.advance_wave(room)
	T.ok(not r.clear_room(room), "todas as ondas caíram, mas com o foco de pé a sala não abre")
	T.ok(r.is_locked(), "segue trancada")
	T.ok(r.break_focus(room) and r.is_focus_broken(room), "o foco quebra")
	T.ok(not r.break_focus(room), "não quebra duas vezes")
	T.ok(r.clear_room(room) and not r.is_locked(), "foco quebrado: a sala abre")
	T.ok(not r.break_focus(room), "sala limpa: nada mais acontece")


func test_breaking_the_focus_early_cuts_the_waves() -> void:
	var r := _run()
	var room := "Pântano Corrompido"
	_walk(r, room)
	r.start_encounter(room)
	T.ok(r.advance_wave(room), "onda 2")
	T.ok(r.break_focus(room), "quebra o foco na onda 2")
	T.eq(r.wave_total(room), 2, "a onda 3 não vem mais")
	T.ok(not r.has_next_wave(room) and not r.advance_wave(room), "nenhuma onda depois da atual")
	T.ok(r.clear_room(room), "a onda 2 caiu: sala limpa")
	T.eq(str(r.summary().encounters[room].get("focus", "")), "broken", "o resumo guarda o foco quebrado")


func test_focus_only_in_ritual_rooms() -> void:
	var r := _run()
	_walk(r, "Encruzilhada")
	r.start_encounter("Encruzilhada")
	T.ok(not r.break_focus("Encruzilhada"), "luta tradicional não tem foco")
	T.ok(not r.encounters.has("Encruzilhada"), "luta tradicional não guarda estado de encontro")
	r.advance_wave("Encruzilhada")
	T.ok(r.clear_room("Encruzilhada"), "e libera como sempre")
	T.ok(r.offer_reward("Encruzilhada", ["furia", "seiva", "casca"]) and r.pending_stacks() == 1,
		"bênção normal, sem acúmulo extra")


# ================================================================ caçada na run
func test_hunt_regroups_are_limited() -> void:
	var r := _run()
	var room := "Arauto do Pântano"
	_walk(r, room)
	T.ok(not r.regroup(room), "antes da luta o bando não se reagrupa")
	T.ok(r.start_encounter(room), "a caçada começa")
	T.eq(r.wave_total(room), 1, "uma onda só: o líder já vem com o bando")
	T.eq(r.regroups_left(room), 2, "dois reagrupamentos")
	T.ok(r.regroup(room) and r.regroup(room), "o bando se reagrupa duas vezes")
	T.ok(not r.regroup(room) and r.regroups_left(room) == 0, "a terceira não vem")
	T.ok(r.mark_prey_down(room) and r.is_prey_down(room), "o líder cai")
	T.ok(not r.mark_prey_down(room), "cai uma vez só")
	T.ok(r.clear_room(room), "a sala abre")
	T.ok(r.offer_reward(room, ["furia", "seiva", "casca"]) and r.pending_stacks() == 2, "bênção de elite em dobro")


func test_hunt_stops_regrouping_after_the_prey_falls() -> void:
	var r := _run()
	var room := "Arauto do Pântano"
	_walk(r, room)
	r.start_encounter(room)
	r.mark_prey_down(room)
	T.ok(not r.regroup(room), "sem o líder o bando não volta")
	T.eq(r.regroups_left(room), 2, "os reagrupamentos não foram gastos")
	T.eq(r.regroups_left("Encruzilhada"), 0, "sala comum não tem reagrupamento")
	T.ok(not r.mark_prey_down("Encruzilhada"), "nem presa")


# ================================================================ defesa das oferendas na run
func test_offering_chest_sealed_until_cleared_and_gives_once() -> void:
	var r := _run()
	var room := "Clareira Funda"
	_walk(r, room)
	T.ok(not r.shrine_ready(room), "antes da luta o baú está lacrado")
	T.ok(r.start_encounter(room), "os guardiões despertam")
	T.ok(not r.shrine_ready(room), "na luta o baú segue lacrado")
	r.tick(10.0)
	while r.has_next_wave(room):
		r.advance_wave(room)
	T.ok(r.clear_room(room), "os guardiões caíram")
	T.ok(r.is_offering_intact(room), "vencida a tempo: oferendas intactas")
	T.ok(not r.has_pending_reward() and r.rooms_awaiting_reward().is_empty(), "a bênção não abre sozinha: é pelo baú")
	T.ok(r.shrine_ready(room), "o baú abriu")
	T.ok(r.offer_reward(room, ["furia", "seiva", "casca"]), "o baú oferece a bênção")
	T.eq(r.pending_stacks(), 2, "oferendas intactas: um acúmulo a mais")
	T.ok(not r.shrine_ready(room), "com a escolha na tela o baú não reabre")
	T.ok(r.choose_reward("seiva") and int(r.modifiers.seiva) == 2, "dois acúmulos de Seiva")
	T.ok(r.is_shrine_used(room) and not r.shrine_ready(room), "baú gasto")
	T.ok(not r.offer_reward(room, ["furia"]) and not r.choose_reward("furia"), "não dá a bênção de novo")
	T.ok(not r.clear_room(room) and not r.start_encounter(room), "a sala não volta a lutar")
	T.eq(int(r.modifiers.seiva), 2, "nada somou a mais")


func test_slow_offering_defense_gives_the_normal_blessing() -> void:
	var r := _run()
	var room := "Clareira Funda"
	_walk(r, room)
	r.start_encounter(room)
	r.tick(500.0)
	while r.has_next_wave(room):
		r.advance_wave(room)
	r.clear_room(room)
	T.ok(not r.is_offering_intact(room), "demorou: as oferendas se apagaram")
	T.ok(r.offer_reward(room, ["furia", "seiva", "casca"]) and r.pending_stacks() == 1, "bênção normal")


# ================================================================ limpeza ao encerrar
func test_run_end_cleans_encounter_state() -> void:
	for how in [ExpeditionRun.ABANDON, ExpeditionRun.DEFEAT]:
		var r := _run()
		_walk(r, "Pântano Corrompido")
		r.start_encounter("Pântano Corrompido")
		T.ok(r.finish(how), "%s no meio do ritual" % how)
		T.ok(not r.is_locked() and not r.has_pending_reward(), "%s: nada trancado nem escolha aberta" % how)
		T.ok(not r.break_focus("Pântano Corrompido") and not r.regroup("Arauto do Pântano"), "%s: nada mais acontece" % how)
		var fresh := _run()
		T.ok(fresh.encounters.is_empty() and fresh.wave_cap.is_empty(), "%s: run nova começa sem estado de encontro" % how)
	var v := _run()
	_walk(v, "Clareira Funda")
	v.start_encounter("Clareira Funda")
	while v.has_next_wave("Clareira Funda"):
		v.advance_wave("Clareira Funda")
	v.clear_room("Clareira Funda")
	v.offer_reward("Clareira Funda", ["furia", "seiva", "casca"])
	v.abandon()
	T.ok(not v.has_pending_reward() and not v.choose_reward("furia"), "abandonar com o baú aberto descarta a escolha")


func test_full_route_with_encounters_reaches_victory() -> void:
	var r := _run()
	_walk(r, "Trono da Rainha")
	_fight(r, "Trono da Rainha")
	T.eq(r.outcome, ExpeditionRun.VICTORY, "a rota inteira com os encontros termina em vitória")
	T.ok(is_equal_approx(r.progress(), 1.0), "todas as lutas limpas")
	T.eq(r.encounters.size(), SPECIAL.size(), "cada encontro especial registrado uma vez")
	T.eq(r.rewards.size(), 4, "bênçãos: Encruzilhada, Guardião, baú da Clareira e Arauto (%s)" % [r.rewards.keys()])
	T.ok(r.rewards.has("Clareira Funda") and r.is_offering_intact("Clareira Funda"), "a Clareira deu a bênção do baú")
