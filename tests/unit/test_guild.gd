extends RefCounted
## Guilda dos Aventureiros (rank D a S), missões secundárias e mapas: regras puras com as tabelas reais.

var _bt: BalanceTables


func _tables() -> BalanceTables:
	if _bt == null:
		_bt = BalanceTables.load_dir("res://data/balance")
	return _bt


func _blank() -> CharState:
	var s := CharState.new_character(_tables())
	s.inventory = []
	s.gold = 0
	return s


## Personagem com a história concluída até `id` (exclusive) pela cadeia principal.
func _story_until(s: CharState, id: String) -> void:
	for q in CharRules.main_chain(_tables().get_table("quests")):
		if q == id:
			return
		s.quests[q] = {"state": "done", "progress": 1}


func test_rank_table() -> void:
	var r := CharRules.ranks(_tables())
	T.eq(r.size(), 5, "cinco ranks")
	var ids: Array = []
	for x in r:
		ids.append(x.id)
	T.eq(ids, StoryRules.RANKS, "D, C, B, A, S na ordem de StoryRules")
	for i in range(1, r.size()):
		T.ok(int(r[i].pts) > int(r[i - 1].pts), "pontos crescem até o Rank %s" % r[i].id)
	T.eq(str(r[4].get("requires", "")), "lich", "Rank S exige derrotar o Lich")


func test_points_only_after_registration() -> void:
	var bt := _tables()
	var s := _blank()
	_story_until(s, "registro")
	s.quests.erase("slimes")
	s.quests["slimes"] = {"state": "ready", "progress": 5}
	CharRules.complete_quest(s, bt, "slimes")
	T.eq(CharRules.guild_points(s), 0, "feitos antes do registro não valem pontos")
	T.ok(CharRules.start_quest(s, bt, "registro").ok, "registro começa depois da festa")
	var r := CharRules.complete_quest(s, bt, "registro")
	T.ok(r.ok, "registro concluído")
	T.eq(CharRules.guild_points(s), 60, "bônus do registro")
	T.eq(CharRules.rank_of(s), "D", "começa no Rank D")


func test_rank_up_flow() -> void:
	var bt := _tables()
	var s := _blank()
	_story_until(s, "quadro")
	T.eq(CharRules.rank_up(s, bt).err, "pontos_insuficientes", "sem pontos")
	s.flags["guild_pts"] = 100
	var sp := s.stat_points
	var r := CharRules.rank_up(s, bt)
	T.ok(r.ok, "promovido")
	T.eq(CharRules.rank_of(s), "C", "Rank C")
	T.eq(s.stat_points, sp + 3, "+3 pontos de atributo")
	T.eq(s.gold, 100, "+100 ouro")
	T.ok(r.events.any(func(e: Dictionary) -> bool: return e.t == "rank" and e.rank == "C"), "evento de rank")
	s.flags["rank"] = "A"
	s.flags["guild_pts"] = 5000
	T.eq(CharRules.rank_up(s, bt).err, "falta_missao", "Rank S exige o Lich")
	s.quests["lich"] = {"state": "done", "progress": 1}
	T.ok(CharRules.rank_up(s, bt).ok, "com o Lich, Rank S")
	T.eq(CharRules.rank_up(s, bt).err, "rank_maximo", "não passa do S")
	var fresh := _blank()
	fresh.flags["guild_pts"] = 999
	T.eq(CharRules.rank_up(fresh, bt).err, "sem_registro", "sem registro não há promoção")


func test_rank_gates_main_and_side() -> void:
	var bt := _tables()
	var s := _blank()
	_story_until(s, "bosque")
	T.eq(CharRules.start_quest(s, bt, "bosque").err, "rank_insuficiente", "Bosque exige Rank C")
	T.eq(CharRules.start_quest(s, bt, "q_ninho").err, "rank_insuficiente", "contrato de Rank C")
	s.flags["rank"] = "C"
	T.ok(CharRules.start_quest(s, bt, "bosque").ok, "com Rank C a história segue")
	T.ok(CharRules.start_quest(s, bt, "q_ninho").ok, "contrato liberado")


func test_side_quests_repeat_and_skip_chain() -> void:
	var bt := _tables()
	var s := _blank()
	# secundária de Rank D não depende da cadeia da história
	T.ok(CharRules.start_quest(s, bt, "q_gelo").ok, "contrato sem história")
	for i in 3:
		CharRules.kill(s, bt, "slime_gelo", 0)
	T.eq(s.quests.q_gelo.state, "ready", "pronto com 3 slimes de gelo")
	T.ok(CharRules.complete_quest(s, bt, "q_gelo").ok, "entregue")
	T.ok(CharRules.start_quest(s, bt, "q_gelo").ok, "repetível: começa de novo")
	T.eq(s.quests.q_gelo.progress, 0, "progresso zerado")
	CharRules.add_item(s, bt, "spicy_soup", 1)
	T.ok(CharRules.start_quest(s, bt, "sopa").ok and CharRules.complete_quest(s, bt, "sopa").ok, "sopa do Rufus")
	T.eq(CharRules.start_quest(s, bt, "sopa").err, "missao_indisponivel", "não repetível")


func test_boss_flags() -> void:
	var bt := _tables()
	var s := _blank()
	CharRules.kill(s, bt, "lich", 0)
	T.ok(s.flags.get("boss_lich", false), "Lich marcado")
	T.ok(not s.flags.has("king_dead"), "o Lich não marca o Rei Goblin")
	CharRules.kill(s, bt, "goblin_king", 0)
	T.ok(s.flags.get("king_dead", false), "Rei Goblin continua marcando king_dead")


func test_story_rules_sides_and_ranks() -> void:
	var qt: Dictionary = _tables().get_table("quests")
	T.eq(StoryRules.after(qt, "festa"), "registro", "o Arco 2 segue a festa")
	T.eq(StoryRules.after(qt, "cerimonia"), "", "a cerimônia fecha a história")
	T.eq(StoryRules.after(qt, "q_gelo"), "", "secundária não tem próxima")
	var q := {}
	T.eq(StoryRules.marker(qt, q, "board", {}, "D").length() > 0, true, "quadro tem contratos para Rank D")
	T.eq(StoryRules.marker(qt, q, "board", {}, "D"), "+", "contratos aparecem como +")
	var board_d := StoryRules.side_offers_at(qt, q, "board", "D")
	var board_c := StoryRules.side_offers_at(qt, q, "board", "C")
	T.ok(board_c.size() > board_d.size(), "Rank C libera mais contratos (%d > %d)" % [board_c.size(), board_d.size()])
	for id in CharRules.main_chain(qt):
		q[id] = {"state": "done", "progress": 1}
		if id == "mina":
			break
	T.eq(StoryRules.current(qt, q), "galerias", "a cadeia ignora as secundárias")
	T.eq(StoryRules.offer_at(qt, {"festa": {"state": "done"}}, "lina", "D"), "", "Lina não oferece o que não é a vez")


func test_quest_data_valid() -> void:
	var bt := _tables()
	var qt := bt.get_table("quests")
	var items := bt.get_table("items")
	var enemies := bt.get_table("enemies")
	for id in qt:
		var d: Dictionary = qt[id]
		for it in d.reward_items:
			T.ok(items.has(it), "%s: item de recompensa %s existe" % [id, it])
		match CharRules.quest_type(d):
			"kill":
				for k in d.get("targets", [d.target]):
					T.ok(enemies.has(k), "%s: inimigo %s existe" % [id, k])
			"collect":
				T.ok(items.has(d.target), "%s: item %s existe" % [id, d.target])
		T.ok(StoryRules.RANKS.has(str(d.get("rank", "D"))), "%s: rank válido" % id)
		if d.has("where"):
			T.ok(d.where.size() == 2, "%s: where é [x, z]" % id)


func test_regions() -> void:
	T.eq(Regions.region_at(Vector3(0, 0, 0)), "vila", "vila na origem")
	T.eq(Regions.region_at(Vector3(5, 0, 790)), "bosque", "bosque")
	T.eq(Regions.region_at(Vector3(810, 0, -20)), "mina", "mina")
	T.eq(Regions.region_at(Vector3(800, 0, 800)), "pico", "pico")
	T.ok(Regions.unlocked("bosque", "C") and not Regions.unlocked("bosque", "D"), "bosque exige Rank C")
	T.ok(Regions.unlocked("pico", "S") and not Regions.unlocked("pico", "B"), "pico exige Rank A")
	for id in Regions.ORDER:
		T.eq(Regions.region_at(Regions.arrive_point(id)), id, "chegada em %s fica no próprio mapa" % id)
		T.eq(Regions.region_at(Regions.coach_point(id)), id, "carruagem de %s fica no próprio mapa" % id)
	T.eq(MusicRules.area(Vector3(800, 0, 800)), "ruins", "música do pico")
