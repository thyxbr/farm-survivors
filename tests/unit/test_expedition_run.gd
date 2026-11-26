extends RefCounted
## Estado da expedição roguelite (ExpeditionRun) e o grafo das salas (ExpeditionDefs).


## Definição pequena com ramificação, para conferir regras que a rota real (reta) ainda não usa.
const BRANCHED := {
	"name": "Teste", "map": "x", "start": "A",
	"rooms": {
		"A": {"kind": "start", "next": ["B", "C"]},
		"B": {"kind": "combat", "next": ["D"]},
		"C": {"kind": "reward", "next": ["D"]},
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
