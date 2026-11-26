extends RefCounted
## Estado da expedição roguelite (ExpeditionRun) e o grafo das salas (ExpeditionDefs).


## Definição pequena com ramificação, para conferir regras que a rota real (reta) ainda não usa.
const BRANCHED := {
	"name": "Teste", "map": "x", "start": "A",
	"rooms": {
		"A": {"kind": "start", "next": ["B", "C"]},
		"B": {"kind": "combat", "next": ["D"]},
		"C": {"kind": "reward", "reward": true, "shrine": {"at": [0, 0]}, "next": ["D"]},
		"D": {"kind": "boss", "next": []},
	},
}


func _run(d: Dictionary) -> ExpeditionRun:
	var r := ExpeditionRun.new()
	r.expedition_id = "teste"
	r.def = d
	return r


func test_real_expeditions_are_valid() -> void:
	T.ok(ExpeditionDefs.DATA.size() >= 1, "ao menos uma expedição")
	for id in ExpeditionDefs.DATA:
		var d := ExpeditionDefs.get_def(id)
		var problems := ExpeditionDefs.validate(d)
		for p in problems:
			T.ok(false, "%s: %s" % [id, p])
		T.eq(problems.size(), 0, "expedição %s sem problemas" % id)
		T.ok(MapData.SCENES.has(ExpeditionDefs.map_of(id)), "%s monta um mapa do MapData" % id)
		T.ok(ExpeditionDefs.is_map(ExpeditionDefs.map_of(id)), "%s: o mapa é reconhecido como de expedição" % id)
		T.ok(Regions.DATA.has(str(d.biome)), "%s vem de um bioma que existe (%s)" % [id, d.biome])
		T.ok(Regions.DATA.has(str(d.get("ambience", d.biome))), "%s com ambientação de um mapa que existe" % id)


func test_pantano_uses_the_swamp() -> void:
	var d := ExpeditionDefs.get_def("pantano")
	T.eq(str(d.biome), "bosque", "o Pântano Sussurrante é o mapa bosque")
	T.eq(Regions.display_name("bosque"), ExpeditionDefs.display_name("pantano"), "mesmo nome do mapa do MMO")
	T.ok(ExpeditionDefs.clear_rooms(d).size() >= 3, "ao menos 3 salas com luta (com o chefe)")


func test_validate_catches_broken_graphs() -> void:
	T.eq(ExpeditionDefs.validate(BRANCHED).size(), 0, "grafo com ramificação é válido")
	var bad := {"start": "A", "rooms": {
		"A": {"kind": "combat", "next": ["Z"]},
		"B": {"kind": "boss", "next": []},
		"C": {"kind": "festa", "next": ["C"]},
	}}
	var text := "\n".join(ExpeditionDefs.validate(bad))
	T.ok("precisa ser do tipo start" in text, "chegada que não é start")
	T.ok("'Z', que não existe" in text, "next para sala inexistente")
	T.ok("não é alcançável" in text and "'B'" in text, "sala solta")
	T.ok("festa" in text, "tipo desconhecido")
	T.ok("ela mesma" in text, "sala que leva a ela mesma")
	var no_boss := {"start": "A", "rooms": {"A": {"kind": "start", "next": []}}}
	T.ok("sem sala de chefe" in "\n".join(ExpeditionDefs.validate(no_boss)), "sem chefe não há como vencer")
	T.ok(ExpeditionDefs.validate({}).size() > 0, "definição vazia")


func test_create_only_for_known_expeditions() -> void:
	T.ok(ExpeditionRun.create("pantano") != null, "cria a run do Pântano")
	T.ok(ExpeditionRun.create("nao_existe") == null, "expedição desconhecida não cria")


func test_start_enters_the_arrival() -> void:
	var r := ExpeditionRun.create("pantano")
	T.eq(r.phase, ExpeditionRun.IDLE, "antes de começar: idle")
	T.ok(not r.enter_room("Entrada"), "não entra em sala antes de começar")
	T.ok(r.start(), "começa")
	T.ok(r.is_active() and not r.is_over(), "em andamento")
	T.eq(r.current_room, "Entrada", "começa na chegada")
	T.eq(r.visited, ["Entrada"] as Array[String], "chegada visitada")
	T.ok(not r.start(), "não começa duas vezes")
	T.eq(r.progress(), 0.0, "progresso zero")


func test_rooms_follow_the_graph() -> void:
	var r := _run(BRANCHED)
	r.start()
	T.ok(not r.enter_room("D"), "não pula para o chefe")
	T.ok(not r.enter_room("nada"), "sala que não existe")
	T.eq(r.current_room, "A", "continua na chegada")
	T.ok(r.enter_room("C"), "entra num dos ramos")
	T.ok(not r.enter_room("B"), "o outro ramo não sai de C")
	T.ok(r.enter_room("A"), "volta para sala visitada")
	T.ok(r.enter_room("B"), "e daí pega o outro ramo")
	T.ok(r.enter_room("D"), "chega no chefe")
	T.eq(r.visited, ["A", "C", "B", "D"] as Array[String], "ordem da primeira visita")


func test_clearing_rooms_and_victory() -> void:
	var r := _run(BRANCHED)
	var events: Array = []
	r.room_cleared.connect(func(room: String) -> void: events.append(room))
	r.phase_changed.connect(func(p: String) -> void: events.append("fase:" + p))
	r.start()
	T.ok(not r.clear_room("B"), "não limpa sala nunca visitada")
	r.enter_room("B")
	T.ok(r.clear_room("B"), "limpa a sala visitada")
	T.ok(not r.clear_room("B"), "não limpa duas vezes")
	T.eq(r.progress(), 0.5, "metade das salas com luta (B de B e D)")
	T.ok(r.is_active(), "sala comum não encerra")
	r.enter_room("D")
	T.ok(r.clear_room("D"), "limpa a sala do chefe")
	T.eq(r.phase, ExpeditionRun.ENDED, "chefe caído encerra")
	T.eq(r.outcome, ExpeditionRun.VICTORY, "com vitória")
	T.eq(r.progress(), 1.0, "progresso completo")
	T.ok(not r.enter_room("A"), "acabou: não anda mais de sala")
	T.ok(not r.fail(), "vitória não vira derrota")
	T.ok(r.mark_returned(), "volta à Guilda")
	T.eq(r.phase, ExpeditionRun.RETURNED, "de volta")
	T.ok(not r.mark_returned(), "não volta duas vezes")
	T.eq(events, ["fase:active", "B", "D", "fase:ended", "fase:returned"], "sinais na ordem")


func test_defeat_and_abandon() -> void:
	var r := ExpeditionRun.create("pantano")
	T.ok(not r.mark_returned(), "não volta antes de começar")
	T.ok(not r.fail(), "não perde antes de começar")
	r.start()
	r.enter_room("Encruzilhada")
	T.ok(r.fail(), "cai na expedição")
	T.eq(r.outcome, ExpeditionRun.DEFEAT, "derrota")
	T.ok(r.is_over(), "acabou")
	T.ok(not r.abandon(), "não abandona depois de perder")
	var s := r.summary()
	T.eq(s.outcome, "defeat", "resumo com o resultado")
	T.eq(int(s.rooms_visited), 2, "resumo com as salas visitadas")
	var a := ExpeditionRun.create("pantano")
	a.start()
	T.ok(a.abandon() and a.outcome == ExpeditionRun.ABANDON, "abandono")
	T.ok(not a.finish("outra"), "resultado desconhecido não vale")


func test_elapsed_only_while_active() -> void:
	var r := ExpeditionRun.create("pantano")
	r.tick(5.0)
	T.eq(r.elapsed, 0.0, "parado antes de começar")
	r.start()
	r.tick(2.5)
	r.abandon()
	r.tick(10.0)
	T.eq(r.elapsed, 2.5, "conta só em andamento")


func test_is_inside_matches_the_map_origin() -> void:
	var o := MapData.origin("exp_pantano")
	T.ok(ExpeditionDefs.is_inside(o + Vector3(10, 0, 50)), "dentro da área da expedição")
	T.ok(not ExpeditionDefs.is_inside(Vector3(0, 0, 116)), "a vila fica fora")
	for id in Regions.ALL + ["arena"]:
		T.ok(not ExpeditionDefs.is_inside(MapData.origin(id)), "%s fica fora da expedição" % id)
	# ambientação (clima, céu, música): a do Covil dentro da expedição, a de sempre fora dela
	T.eq(ExpeditionDefs.ambience_at(o + Vector3(0, 0, 40)), "dg_bosque", "dentro: ambiente do Covil das Raízes")
	T.ok(Regions.is_dungeon(ExpeditionDefs.ambience_at(o)), "dentro: sem chuva nem vento (ambiente de dungeon)")
	for id in Regions.ALL:
		T.eq(ExpeditionDefs.ambience_at(MapData.origin(id)), Regions.region_at(MapData.origin(id)),
			"fora: %s igual ao region_at" % id)


# ================================================================ encontros por ondas e salas trancadas
## Rota com uma sala de duas ondas e recompensa, um descanso e o chefe (onda única, a da cena).
const WAVED := {
	"name": "Ondas", "map": "x", "start": "A",
	"rooms": {
		"A": {"kind": "start", "next": ["B"]},
		"B": {"kind": "combat", "reward": true, "next": ["C"], "waves": [
			[{"kind": "slime", "count": 2}],
			[{"kind": "slime", "count": 1}, {"kind": "goblin", "count": 2}],
		]},
		"C": {"kind": "rest", "next": ["D"]},
		"D": {"kind": "boss", "next": []},
	},
}


func test_wave_data() -> void:
	T.eq(ExpeditionDefs.wave_count(WAVED, "B"), 2, "B tem duas ondas")
	T.eq(ExpeditionDefs.wave_count(WAVED, "D"), 1, "chefe sem waves: uma onda (a da cena)")
	T.eq(ExpeditionDefs.wave_count(WAVED, "C"), 0, "descanso sem luta")
	T.ok(ExpeditionDefs.has_waves(WAVED, "B") and not ExpeditionDefs.has_waves(WAVED, "D"), "quem nasce por ondas")
	T.eq(ExpeditionDefs.wave_size(WAVED, "B", 0), 2, "onda 1: 2 monstros")
	T.eq(ExpeditionDefs.wave_size(WAVED, "B", 1), 3, "onda 2: 3 monstros")
	T.eq(ExpeditionDefs.wave_groups(WAVED, "B", 2), [], "não há onda 3")
	T.eq(ExpeditionDefs.validate(WAVED).size(), 0, "definição com ondas válida")
	var bad := WAVED.duplicate(true)
	bad.rooms.C["waves"] = [[{"kind": "slime", "count": 1}]]
	bad.rooms.B.waves = [[], [{"kind": "", "count": 1}], [{"kind": "slime", "count": 0}]]
	var p := ExpeditionDefs.validate(bad)
	T.ok(p.size() >= 4, "pega onda em sala sem luta, onda vazia, sem tipo e com contagem 0 (%d)" % p.size())


func test_pantano_has_escalating_waves() -> void:
	var d := ExpeditionDefs.get_def("pantano")
	var multi := 0
	var last_total := 0
	for room in ["Encruzilhada", "Raízes Corrompidas", "Clareira Funda", "Pântano Corrompido"]:
		var n := ExpeditionDefs.wave_count(d, room)
		if n > 1:
			multi += 1
		var total := 0
		for i in n:
			var s := ExpeditionDefs.wave_size(d, room, i)
			T.ok(s >= 1 and s <= 5, "%s onda %d com %d monstros (nenhuma onda é um bando enorme)" % [room, i + 1, s])
			total += s
		T.ok(total > last_total, "%s mais pesada que a sala anterior (%d > %d)" % [room, total, last_total])
		last_total = total
	T.ok(multi >= 4, "todas as salas de luta comuns têm mais de uma onda")
	T.ok(ExpeditionDefs.wave_count(d, "Clareira Funda") > ExpeditionDefs.wave_count(d, "Encruzilhada"),
		"a segunda sala tem mais ondas que a primeira")
	T.eq(ExpeditionDefs.wave_count(d, "Trono da Rainha"), 1, "o chefe continua sendo a luta da cena")


func test_encounter_locks_until_last_wave() -> void:
	var r := _run(WAVED)
	var ev: Array = []
	r.wave_started.connect(func(room: String, w: int, t: int) -> void: ev.append("%s %d/%d" % [room, w, t]))
	r.room_locked.connect(func(room: String) -> void: ev.append("tranca " + room))
	r.room_unlocked.connect(func(room: String) -> void: ev.append("solta " + room))
	r.start()
	T.ok(not r.can_start_encounter("B"), "não começa luta de sala onde o jogador não está")
	T.ok(not r.start_encounter("A"), "a chegada não tem luta")
	r.enter_room("B")
	T.ok(not r.is_locked() and r.current_wave("B") == 0, "entrar não tranca sozinho (quem tranca é o modo)")
	T.ok(r.start_encounter("B"), "começa a luta de B")
	T.ok(r.is_locked() and r.locked_room == "B" and r.current_wave("B") == 1, "B trancada na onda 1")
	T.ok(not r.start_encounter("B"), "não recomeça a luta")
	T.ok(not r.can_enter("C") and not r.enter_room("C"), "trancada: não segue para a próxima sala")
	T.ok(not r.can_enter("A") and not r.enter_room("A"), "trancada: não volta para a anterior")
	T.ok(r.can_enter("B"), "trancada: só a própria sala")
	T.ok(not r.clear_room("B"), "não limpa com onda por vir")
	T.ok(r.has_next_wave("B") and r.advance_wave("B"), "onda 1 caiu: vem a 2")
	T.eq(r.current_wave("B"), 2, "na onda 2")
	T.ok(not r.has_next_wave("B") and not r.advance_wave("B"), "a 2 é a última")
	T.ok(r.is_locked(), "ainda trancada até limpar")
	T.ok(r.clear_room("B"), "última onda caiu: limpa")
	T.ok(not r.is_locked() and r.can_enter("C"), "solta: pode seguir")
	T.eq(ev, ["tranca B", "B 1/2", "B 2/2", "solta B"], "sinais na ordem")
	# voltar à sala limpa: nada tranca, nenhuma onda nova
	r.enter_room("A")
	r.enter_room("B")
	T.ok(not r.can_start_encounter("B") and not r.start_encounter("B") and not r.advance_wave("B"),
		"sala limpa não tranca nem gera onda de novo")
	T.ok(not r.clear_room("B"), "nem limpa (e recompensa) duas vezes")


func test_reward_waits_for_last_wave_and_happens_once() -> void:
	var r := _run(WAVED)
	r.start()
	r.enter_room("B")
	r.start_encounter("B")
	T.ok(not r.can_offer_reward("B"), "sem bênção no meio da luta")
	r.advance_wave("B")
	r.clear_room("B")
	T.eq(r.rooms_awaiting_reward(), ["B"], "limpa: a bênção espera")
	T.ok(r.offer_reward("B", ["furia", "seiva", "casca"]), "oferece")
	T.ok(r.choose_reward("seiva"), "escolhe")
	T.ok(not r.offer_reward("B", ["furia"]) and r.rooms_awaiting_reward().is_empty(), "uma bênção por sala")
	T.eq(r.modifiers, {"seiva": 1}, "uma melhoria só")


func test_boss_room_locks_and_victory_unlocks() -> void:
	var r := _run(WAVED)
	r.start()
	r.enter_room("B")
	r.start_encounter("B")
	r.advance_wave("B")
	r.clear_room("B")
	r.offer_reward("B", ["furia"])
	r.choose_reward("furia")
	r.enter_room("C")
	T.ok(not r.start_encounter("C"), "descanso não tranca")
	r.enter_room("D")
	T.ok(r.start_encounter("D") and r.wave_total("D") == 1, "chefe: tranca com uma onda")
	T.ok(not r.can_enter("C"), "não foge do chefe pela sala de descanso")
	T.ok(r.clear_room("D") and r.outcome == ExpeditionRun.VICTORY, "chefe caído: vitória")
	T.ok(not r.is_locked(), "vitória solta a sala")


func test_end_of_run_releases_the_lock() -> void:
	var r := _run(WAVED)
	r.start()
	r.enter_room("B")
	r.start_encounter("B")
	T.ok(r.fail() and not r.is_locked(), "cair no meio da luta solta a tranca")
	var a := _run(WAVED)
	a.start()
	a.enter_room("B")
	a.start_encounter("B")
	T.ok(a.abandon() and not a.is_locked() and not a.advance_wave("B"), "abandonar solta e não gera onda")
