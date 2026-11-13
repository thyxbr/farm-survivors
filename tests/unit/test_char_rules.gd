extends RefCounted
## CharState + CharRules + LootRules: regras do personagem puras, com as tabelas reais de data/balance.

var _bt: BalanceTables


func _tables() -> BalanceTables:
	if _bt == null:
		_bt = BalanceTables.load_dir("res://data/balance")
	return _bt


func _price(id: String) -> int:
	return int(_tables().get_table("items")[id]["price"])


func _count(s: CharState, id: String) -> int:
	var n := 0
	for slot in s.inventory:
		if slot.id == id:
			n += int(slot.qty)
	return n


## Personagem vazio (sem kit inicial) para os testes fixarem valores sem ruído.
func _blank(gold := 0) -> CharState:
	var s := CharState.new_character(_tables())
	s.inventory = []
	s.gold = gold
	return s


func _has_event(r: Dictionary, t: String) -> bool:
	for e in r.events:
		if e.t == t:
			return true
	return false


# ---------------------------------------------------------------- estado
func test_new_character_matches_new_game() -> void:
	var s := CharState.new_character(_tables())
	T.eq(s.level, 1, "nível")
	T.eq(s.gold, 25, "ouro inicial")
	T.eq(s.attributes, {"str": 5, "int": 5, "vit": 5, "agi": 5}, "atributos")
	T.eq(s.equipment.weapon, "wooden_sword", "arma inicial")
	T.eq(_count(s, "health_potion"), 3, "poções")
	T.eq(_count(s, "seed_wheat"), 4, "sementes de trigo")
	T.eq(_count(s, "short_bow"), 1, "arco")
	T.eq(s.farm.unlocked, 6, "canteiros abertos")
	T.eq(s.farm.plots.size(), 12, "canteiros")
	T.eq(s.hp, 110.0, "vida cheia do nível 1")
	T.eq(s.mp, 55.0, "mana cheia do nível 1")


func test_state_roundtrip_json() -> void:
	var s := CharState.new_character(_tables())
	s.world_pos = Vector3(1.5, 0.5, -3.0)
	s.world_yaw = 0.7
	s.quests = {"slimes": {"state": "active", "progress": 2}}
	var d = JSON.parse_string(JSON.stringify(s.to_dict()))
	var b := CharState.from_dict(d)
	T.eq(b.to_dict(), s.to_dict(), "volta igual depois do JSON")
	T.eq(typeof(b.gold), TYPE_INT, "ouro int")
	T.eq(typeof(b.inventory[0].qty), TYPE_INT, "qty int")
	T.eq(b.world_pos, Vector3(1.5, 0.5, -3.0), "posição")


# ---------------------------------------------------------------- loja
func test_buy_and_sell() -> void:
	var bt := _tables()
	var s := _blank(100)
	var p := _price("health_potion")
	var r := CharRules.buy(s, bt, "health_potion")
	T.ok(r.ok, "compra")
	T.eq(s.gold, 100 - p, "ouro descontado")
	T.eq(_count(s, "health_potion"), 1, "uma poção")
	T.ok(_has_event(r, "looted"), "evento looted")
	r = CharRules.sell(s, bt, "health_potion")
	T.ok(r.ok, "venda")
	T.eq(s.gold, 100 - p + int(ceil(p * 0.5)), "metade arredondada para cima")
	T.eq(_count(s, "health_potion"), 0, "sem poção")
	T.eq(CharRules.sell(s, bt, "health_potion").err, "sem_item", "vender o que não tem")


func test_buy_not_in_shop() -> void:
	var bt := _tables()
	var s := _blank(99999)
	var before := s.to_dict()
	var r := CharRules.buy(s, bt, "dragonfang")
	T.ok(not r.ok, "falha")
	T.eq(r.err, "nao_vende", "lendário não está na loja")
	T.eq(s.to_dict(), before, "estado igual")
	T.ok(CharRules.buy(s, bt, "seed_pumpkin").ok, "semente de cultura pode")


func test_buy_double_without_gold() -> void:
	var bt := _tables()
	var s := _blank(_price("iron_sword"))
	T.ok(CharRules.buy(s, bt, "iron_sword").ok, "primeira")
	var r := CharRules.buy(s, bt, "iron_sword")
	T.eq(r.err, "ouro_insuficiente", "segunda")
	T.eq(s.gold, 0, "ouro zerado, não negativo")
	T.eq(_count(s, "iron_sword"), 1, "só uma espada")


# ---------------------------------------------------------------- equipamento
func test_equip_offhand_needs_class() -> void:
	var bt := _tables()
	var s := _blank()
	s.inventory = [{"id": "arcane_orb", "qty": 1}]
	var r := CharRules.equip(s, bt, "arcane_orb")
	T.eq(r.err, "exige_classe", "orbe com espada")
	T.eq(r.events[0].text, "Orbe Arcano exige cajado.", "texto do aviso")
	T.eq(s.equipment.offhand, "", "nada equipado")
	T.eq(_count(s, "arcane_orb"), 1, "continua na mochila")
	s.inventory.append({"id": "knight_shield", "qty": 1})
	T.ok(CharRules.equip(s, bt, "knight_shield").ok, "escudo com espada")
	T.eq(s.equipment.offhand, "knight_shield", "escudo equipado")


func test_equip_swaps_back_to_bag() -> void:
	var bt := _tables()
	var s := _blank()
	s.inventory = [{"id": "iron_sword", "qty": 1}]
	var r := CharRules.equip(s, bt, "iron_sword")
	T.ok(r.ok, "equipa")
	T.eq(s.equipment.weapon, "iron_sword", "nova arma")
	T.eq(_count(s, "wooden_sword"), 1, "a antiga volta")
	T.eq(_count(s, "iron_sword"), 0, "a nova sai da mochila")
	T.eq(r.events[-1].text, "Equipado: Espada de Ferro", "aviso")
	T.eq(CharRules.equip(s, bt, "iron_sword").err, "sem_item", "não tem outra")
	T.ok(CharRules.unequip(s, bt, "weapon").ok, "desequipa")
	T.eq(s.equipment.weapon, "", "mão vazia")
	T.eq(_count(s, "iron_sword"), 1, "volta para a mochila")
	T.eq(CharRules.unequip(s, bt, "weapon").err, "slot_vazio", "nada para tirar")


func test_weapon_change_returns_offhand() -> void:
	var bt := _tables()
	var s := _blank()
	s.inventory = [{"id": "knight_shield", "qty": 1}, {"id": "apprentice_staff", "qty": 1}]
	CharRules.equip(s, bt, "knight_shield")
	var r := CharRules.equip(s, bt, "apprentice_staff")
	T.ok(r.ok, "troca para cajado")
	T.eq(s.equipment.offhand, "", "escudo sai da mão")
	T.eq(_count(s, "knight_shield"), 1, "escudo na mochila")
	T.eq(r.events[0].text, "Escudo do Cavaleiro guardado (exige espada).", "aviso do escudo")


# ---------------------------------------------------------------- consumo e cozinha
func test_consume() -> void:
	var bt := _tables()
	var s := _blank()
	s.inventory = [{"id": "health_potion", "qty": 2}, {"id": "carrot", "qty": 1}, {"id": "iron_sword", "qty": 1}]
	T.ok(CharRules.consume(s, bt, "health_potion").ok, "poção")
	T.eq(_count(s, "health_potion"), 1, "tirou uma")
	var r := CharRules.consume(s, bt, "carrot")
	T.ok(r.ok, "colheita crua")
	T.eq(r.events[0].text, "Comeu Cenoura", "aviso")
	T.eq(CharRules.consume(s, bt, "carrot").err, "sem_item", "acabou")
	T.eq(CharRules.consume(s, bt, "iron_sword").err, "nao_consumivel", "espada não se come")


func test_cook() -> void:
	var bt := _tables()
	var s := _blank()
	s.inventory = [{"id": "wheat", "qty": 1}]
	var r := CharRules.cook(s, bt, "bread", 1)
	T.eq(r.err, "faltam_ingredientes", "falta trigo")
	T.eq(r.events[0].text, "Faltam ingredientes.", "aviso")
	T.eq(_count(s, "wheat"), 1, "nada gasto")
	s.inventory = [{"id": "wheat", "qty": 4}]
	r = CharRules.cook(s, bt, "bread", 2)
	T.ok(r.ok, "cozinha")
	T.eq(r.n, 2, "dois pães")
	T.eq(_count(s, "bread"), 2, "na mochila")
	T.eq(_count(s, "wheat"), 0, "trigo gasto")
	T.eq(CharRules.cook(s, bt, "nao_existe", 1).err, "receita_invalida", "receita inválida")


# ---------------------------------------------------------------- progressão
func test_kill_levels_up() -> void:
	var bt := _tables()
	var s := _blank()
	var r := CharRules.kill(s, bt, "slime", 60)
	T.ok(r.ok, "ok")
	T.eq(s.level, 2, "nível 2")
	T.eq(s.xp, 0, "xp zerado")
	T.eq(s.stat_points, 3, "3 pontos")
	T.eq(s.kills, 1, "abate contado")
	T.ok(_has_event(r, "level_up"), "evento level_up")
	T.eq(r.events[0].text, "+60 XP", "aviso de XP")
	T.eq(r.events[1].text, "Nível 2! +3 pontos de atributo (C)", "aviso de nível")
	T.eq(r.events[2].text, "Nova magia: Cura [2]", "magia nova")


func test_spend_point() -> void:
	var bt := _tables()
	var s := _blank()
	T.eq(CharRules.spend_point(s, bt, "str").err, "sem_pontos", "sem pontos")
	s.stat_points = 1
	T.eq(CharRules.spend_point(s, bt, "sorte").err, "atributo_invalido", "atributo inválido")
	T.ok(CharRules.spend_point(s, bt, "str").ok, "gasta")
	T.eq(s.attributes.str, 6, "força 6")
	T.eq(s.stat_points, 0, "zero pontos")


func test_grant() -> void:
	var bt := _tables()
	var s := _blank()
	var r := CharRules.grant(s, bt, 7, 10, {"slime_gel": 2, "iron_sword": 2})
	T.ok(r.ok, "ok")
	T.eq(s.gold, 7, "ouro")
	T.eq(s.xp, 10, "xp")
	T.eq(_count(s, "slime_gel"), 2, "gel")
	T.eq(s.inventory.size(), 3, "gel empilha, espadas não")
	T.eq(CharRules.grant(s, bt, -5, 0, {}).err, "valor_invalido", "negativo")
	T.eq(CharRules.grant(s, bt, 0, 0, {"nada": 1}).err, "item_invalido", "item desconhecido")


func test_quest_flow() -> void:
	var bt := _tables()
	var s := _blank()
	T.eq(CharRules.start_quest(s, bt, "goblins").err, "missao_indisponivel", "anterior não concluída")
	T.eq(CharRules.complete_quest(s, bt, "slimes").err, "missao_nao_pronta", "nem começou")
	var r := CharRules.start_quest(s, bt, "slimes")
	T.ok(r.ok, "começa")
	T.eq(r.events[0].text, "Nova missão: Praga Gosmenta", "aviso")
	T.eq(CharRules.start_quest(s, bt, "slimes").err, "missao_indisponivel", "não repete")
	var q: Dictionary = bt.get_table("quests")["slimes"]
	for i in q.count - 1:
		CharRules.kill(s, bt, "slime", 0)
	T.eq(s.quests.slimes.state, "active", "ainda ativa")
	T.eq(CharRules.complete_quest(s, bt, "slimes").err, "missao_nao_pronta", "antes de pronta")
	r = CharRules.kill(s, bt, "slime", 0)
	T.eq(s.quests.slimes.state, "ready", "pronta")
	T.ok(_has_event(r, "quest"), "evento quest")
	var gold := s.gold
	r = CharRules.complete_quest(s, bt, "slimes")
	T.ok(r.ok, "conclui")
	T.eq(s.quests.slimes.state, "done", "concluída")
	T.eq(s.gold, gold + int(q.reward_gold), "ouro da recompensa")
	T.eq(_count(s, "health_potion"), 3, "itens da recompensa")
	T.eq(s.level, 2, "120 XP: nível 2")
	T.eq(s.xp, 60, "sobra 60")
	T.ok(CharRules.start_quest(s, bt, "goblins").ok, "a próxima abre")


func test_sort_inventory() -> void:
	var bt := _tables()
	var s := _blank()
	s.inventory = [{"id": "slime_gel", "qty": 3}, {"id": "health_potion", "qty": 1},
		{"id": "wooden_sword", "qty": 1}, {"id": "dragonfang", "qty": 1}]
	T.ok(CharRules.sort_inventory(s, bt).ok, "ok")
	var ids := []
	for slot in s.inventory:
		ids.append(slot.id)
	T.eq(ids, ["dragonfang", "wooden_sword", "health_potion", "slime_gel"], "ordem")


# ---------------------------------------------------------------- horta
func test_farm_clock() -> void:
	var bt := _tables()
	var s := _blank(100)
	s.inventory = [{"id": "seed_carrot", "qty": 2}]
	var time := float(bt.get_table("crops")["carrot"]["time"])
	T.eq(CharRules.plant(s, bt, 6, "carrot", false, 1000.0).err, "canteiro_trancado", "canteiro 6 trancado")
	var r := CharRules.plant(s, bt, 0, "carrot", false, 1000.0)
	T.ok(r.ok, "planta")
	T.ok(_has_event(r, "farm"), "evento farm")
	T.eq(_count(s, "seed_carrot"), 1, "semente gasta")
	T.eq(CharRules.plant(s, bt, 0, "carrot", false, 1000.0).err, "canteiro_ocupado", "ocupado")
	var half := 1000.0 + time / 2.0
	T.ok(absf(CharRules.farm_growth(s.farm.plots[0], bt, half) - 0.5) < 0.001, "metade sem regar")
	T.eq(CharRules.harvest(s, bt, 0, half, _rng(1)).err, "nao_pronto", "colher antes falha")
	# outro canteiro, regado na hora de plantar
	CharRules.plant(s, bt, 1, "carrot", false, 1000.0)
	T.ok(CharRules.water(s, bt, 1, 1000.0).ok, "rega")
	T.eq(CharRules.water(s, bt, 1, 1000.0).err, "ja_regado", "não rega duas vezes")
	T.ok(absf(CharRules.farm_growth(s.farm.plots[1], bt, half) - 1.0) < 0.001, "regado fica pronto")
	r = CharRules.harvest(s, bt, 1, half, _rng(1))
	T.ok(r.ok, "colhe")
	T.ok(int(r.harvest.qty) >= 3, "colheita regada rende +1")
	T.eq(_count(s, "carrot"), int(r.harvest.qty), "cenouras na mochila")
	T.eq(s.farm.plots[1].crop, "", "canteiro vazio")
	# rega no meio: o que cresceu antes conta, o resto vai 2x
	T.ok(CharRules.water(s, bt, 0, half).ok, "rega no meio")
	T.ok(absf(CharRules.farm_growth(s.farm.plots[0], bt, half + time / 4.0) - 1.0) < 0.001, "0.5 + 0.25*2")
	# sem semente, comprando
	s.inventory = []
	T.eq(CharRules.plant(s, bt, 2, "carrot", false, 1000.0).err, "sem_semente", "sem semente")
	var gold := s.gold
	T.ok(CharRules.plant(s, bt, 2, "carrot", true, 1000.0).ok, "compra a semente")
	T.eq(s.gold, gold - _price("seed_carrot"), "pagou a semente")


func test_fertilize_and_unlock() -> void:
	var bt := _tables()
	var s := _blank(30)
	s.inventory = [{"id": "seed_carrot", "qty": 1}]
	CharRules.plant(s, bt, 0, "carrot", false, 1000.0)
	T.eq(CharRules.fertilize(s, bt, 0, 1000.0).err, "sem_adubo", "sem gel")
	s.inventory.append({"id": "slime_gel", "qty": 2})
	T.ok(CharRules.fertilize(s, bt, 0, 1000.0).ok, "aduba")
	T.ok(absf(CharRules.farm_growth(s.farm.plots[0], bt, 1000.0) - 0.4) < 0.001, "+40%")
	T.eq(CharRules.fertilize(s, bt, 0, 1000.0).err, "ja_adubado", "uma vez por plantio")
	T.eq(_count(s, "slime_gel"), 1, "um gel gasto")
	var r := CharRules.unlock_plot(s, bt)
	T.ok(r.ok, "abre o 7º canteiro por 30")
	T.eq(s.farm.unlocked, 7, "7 abertos")
	T.eq(s.gold, 0, "pagou 30")
	r = CharRules.unlock_plot(s, bt)
	T.eq(r.err, "ouro_insuficiente", "o próximo custa 45")
	T.eq(r.events[0].text, "Ouro insuficiente (45).", "aviso com o preço")


# ---------------------------------------------------------------- loot
func _rng(seed_: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_
	return r


func test_loot_roll_deterministic() -> void:
	var bt := _tables()
	var a := LootRules.roll(bt, "goblin_king", _rng(42))
	var b := LootRules.roll(bt, "goblin_king", _rng(42))
	T.eq(a, b, "mesma seed, mesmo resultado")
	T.ok(int(a.gold) >= 90 and int(a.gold) <= 130, "ouro na faixa")
	T.eq(int(a.items.get("goblin_crown", 0)), 1, "chance 1.0 sempre cai")
	T.eq(LootRules.roll(bt, "nao_existe", _rng(1)), {"gold": 0, "items": {}}, "tipo desconhecido")


# ---------------------------------------------------------------- correções da revisão
func test_counts_are_bounded() -> void:
	var bt := _tables()
	var s := _blank(1000)
	s.inventory = [{"id": "wheat", "qty": 400}]
	var before := s.to_dict()
	for q in [0, -1, 100, 1 << 62, 2.0, "3"]:
		T.eq(CharRules.buy(s, bt, "health_potion", q).err, "args", "buy qty %s" % var_to_str(q))
		T.eq(CharRules.buy(s, bt, "iron_sword", q).err, "args", "buy não empilhável qty %s" % var_to_str(q))
		T.eq(CharRules.cook(s, bt, "bread", q).err, "args", "cook times %s" % var_to_str(q))
	T.eq(s.to_dict(), before, "estado igual")
	T.ok(CharRules.buy(s, bt, "health_potion", 5).ok, "5 pode")
	T.eq(CharRules.cook(s, bt, "bread", 99).n, 99, "99 pode")


func test_from_dict_rejects_malicious() -> void:
	var bt := _tables()
	var d := {"level": 0, "xp": -10, "gold": -5, "stat_points": [], "kills": null,
		"attributes": {"str": 5, "int": 0, "vit": "x", "hack": 99},
		"inventory": [{"id": "nao_existe", "qty": 3}, {"id": "slime_gel", "qty": -2}, {"id": "slime_gel", "qty": 4},
			{"id": "iron_sword", "qty": 50}, {"id": null, "qty": 1}, "lixo"],
		"equipment": {"weapon": "health_potion", "head": "iron_helm", "ring": 7, "cauda": "x"},
		"quests": {"slimes": {"state": "ready", "progress": 5}, "goblins": {"state": "hack"}, "falsa": {"state": "done"},
			"goblin_king": "x"},
		"flags": null, "farm": {"unlocked": 99, "plots": [{"crop": "trufa", "growth": 1.0}, null,
			{"crop": "carrot", "growth": "x", "t": null, "watered": "sim"}]},
		"hp": null, "mp": -3, "world_pos": [1, null, 2], "world_yaw": "x"}
	var s := CharState.from_dict(d, bt)
	T.eq(s.level, 1, "nível ≥ 1")
	T.eq([s.xp, s.gold, s.stat_points, s.kills], [0, 0, 0, 0], "não negativos / tipo errado = 0")
	T.eq(s.attributes, {"str": 5, "int": 1, "vit": 5, "agi": 5}, "só os 4 atributos, ≥ 1")
	T.eq(s.inventory, [{"id": "slime_gel", "qty": 4}, {"id": "iron_sword", "qty": 1}], "ids e qty válidos")
	T.eq(s.equipment.weapon, "", "poção não é arma")
	T.eq(s.equipment.head, "iron_helm", "elmo na cabeça")
	T.eq(s.equipment.ring, "", "anel de tipo errado")
	T.ok(not s.equipment.has("cauda"), "espaço desconhecido some")
	T.eq(s.quests, {"slimes": {"state": "ready", "progress": 5}}, "só missões e estados conhecidos")
	T.eq(s.flags, {}, "flags padrão")
	T.eq(s.farm.unlocked, 12, "abertos limitados")
	T.eq(s.farm.plots.size(), 12, "12 canteiros")
	T.eq(s.farm.plots[0].crop, "", "cultura desconhecida some")
	T.eq(s.farm.plots[2].crop, "carrot", "cenoura fica")
	T.eq(s.farm.plots[2].growth, 0.0, "crescimento de tipo errado")
	T.eq(s.farm.plots[2].watered, false, "regado de tipo errado")
	T.eq([s.hp, s.mp], [0.0, 0.0], "vida/mana padrão")
	T.eq(s.world_pos, null, "posição inválida")
	T.eq(s.world_yaw, 0.0, "yaw padrão")
	T.eq(CharState.from_dict(null).level, 1, "nem é dicionário")
	# sem bt: só tipos e faixas
	var nb := CharState.from_dict(d)
	T.eq(nb.gold, 0, "sem bt também limita")
	T.eq(nb.inventory.size(), 3, "sem bt não confere ids")


func test_settle_clock_backwards() -> void:
	var bt := _tables()
	var s := _blank()
	s.inventory = [{"id": "seed_carrot", "qty": 1}]
	var time := float(bt.get_table("crops")["carrot"]["time"])
	CharRules.plant(s, bt, 0, "carrot", false, 1000.0)
	T.ok(CharRules.water(s, bt, 0, 1000.0 - time / 4.0).ok, "rega com relógio atrasado")
	T.ok(absf(CharRules.farm_growth(s.farm.plots[0], bt, 1000.0 + time / 4.0) - 0.5) < 0.001,
		"não conta o mesmo intervalo duas vezes")


func test_farm_fail_keeps_state() -> void:
	var bt := _tables()
	var s := _blank()
	s.farm = {"unlocked": 2, "plots": [CharRules._empty_plot(), CharRules._empty_plot()]}
	var before := s.to_dict()
	T.eq(CharRules.water(s, bt, 0, 1000.0).err, "canteiro_vazio", "falha")
	T.eq(s.to_dict(), before, "horta não foi normalizada na falha")
	s.inventory = [{"id": "seed_carrot", "qty": 1}]
	T.ok(CharRules.plant(s, bt, 0, "carrot", false, 1000.0).ok, "sucesso")
	T.eq(s.farm.plots.size(), 12, "normalizada no sucesso")


func test_kill_boss_sets_flag() -> void:
	var bt := _tables()
	var s := _blank()
	CharRules.kill(s, bt, "goblin", 0)
	T.ok(not s.flags.has("king_dead"), "goblin comum")
	CharRules.kill(s, bt, "goblin_king", 0)
	T.eq(s.flags.get("king_dead"), true, "rei morto")
