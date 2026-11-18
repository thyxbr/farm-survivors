extends RefCounted
## CharacterService: regras + SQLite + registro da economia, com banco de verdade em user://.

const PATH := "user://test_charsvc.db"

var _bt: BalanceTables


func _tables() -> BalanceTables:
	if _bt == null:
		_bt = BalanceTables.load_dir("res://data/balance")
	return _bt


func _fresh() -> Db:
	Db.remove_files(PATH)
	var db := Db.open(PATH)
	Migrations.apply(db)
	db.exec("INSERT INTO accounts(id, username, pass_hash, pass_salt, created_at) VALUES(2, 'ana', 'h', 's', 1)")
	return db


func _count(s: CharState, id: String) -> int:
	return CharRules.count_item(s, id)


func test_persists_across_instances() -> void:
	var db := _fresh()
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	var antes := svc.load_or_create(2)
	svc.apply(2, "choose_class", ["warrior", "m"])
	var ouro := antes.gold
	var pocoes := _count(antes, "health_potion")
	var r := svc.apply(2, "buy", ["health_potion", 1])
	T.ok(r.ok, "comprou: %s" % r.err)
	T.eq(r.state.gold, ouro - int(_tables().get_table("items")["health_potion"]["price"]), "estado devolvido")
	db.close()
	var db2 := Db.open(PATH)
	var svc2 := CharacterService.new(SqliteCharStore.new(db2), _tables())
	var s := svc2.load_or_create(2)
	T.eq(_count(s, "health_potion"), pocoes + 1, "poções persistiram")
	T.eq(s.gold, r.state.gold, "ouro persistiu")
	T.eq(s.to_dict()["equipment"], antes.to_dict()["equipment"], "equipamento igual")
	db2.close()


func test_solo_account_created() -> void:
	var db := _fresh()
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	var s := svc.load_or_create(1)
	T.ok(s.gold > 0, "personagem novo na conta 1")
	T.eq(db.query("SELECT provider FROM accounts WHERE id = 1")[0]["provider"], "local", "conta local criada")
	db.close()


func test_rejects_unknown_op() -> void:
	var db := _fresh()
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	svc.load_or_create(2)
	var r := svc.apply(2, "grant", [9999, 0, {}])
	T.ok(not r.ok, "grant não vem do cliente")
	T.eq(r.err, "op_invalida", "erro")
	T.eq(svc.load_or_create(2).gold, 25, "ouro intacto")
	db.close()


func test_rejects_bad_args() -> void:
	var db := _fresh()
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	svc.load_or_create(2)
	T.eq(svc.apply(2, "buy", [123]).err, "args", "id não é String")
	T.eq(svc.apply(2, "buy", []).err, "args", "faltou argumento")
	T.eq(svc.apply(2, "buy", ["health_potion", "2"]).err, "args", "qty não é int")
	T.eq(svc.apply(2, "buy", ["health_potion", 1, 1]).err, "args", "argumento a mais")
	T.eq(svc.apply(2, "plant", [0, "carrot", 1]).err, "args", "bool esperado")
	T.eq(db.query("SELECT COUNT(*) AS n FROM economy_log")[0]["n"], 0, "nada registrado")
	db.close()


func test_economy_log_rows() -> void:
	var db := _fresh()
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	svc.load_or_create(2)
	svc.apply(2, "choose_class", ["warrior", "m"])
	var r := svc.apply(2, "buy", ["health_potion", 1])
	T.ok(r.ok, "comprou")
	var itens := db.query("SELECT * FROM economy_log WHERE item_id = 'health_potion'")
	T.eq(itens.size(), 1, "uma linha do item")
	T.eq(itens[0]["kind"], "buy", "kind = op")
	T.eq(itens[0]["amount"], 1, "quantidade")
	T.eq(itens[0]["source"], "player", "source")
	T.eq(itens[0]["account_id"], 2, "conta")
	var ouro := db.query("SELECT * FROM economy_log WHERE item_id IS NULL")
	T.eq(ouro.size(), 1, "uma linha de ouro")
	T.ok(ouro[0]["amount"] < 0, "ouro gasto é negativo")
	# falha não registra
	svc.apply(2, "buy", ["legendary_nonexistent", 1])
	T.eq(db.query("SELECT COUNT(*) AS n FROM economy_log")[0]["n"], 2, "falha não gera linha")
	# equipar não muda posse: sem linha
	svc.apply(2, "equip", ["leather_cap"])
	T.eq(db.query("SELECT COUNT(*) AS n FROM economy_log")[0]["n"], 2, "equipar não gera linha")
	db.close()


func test_stale_session_report_ignored() -> void:
	var db := _fresh()
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	svc.load_or_create(2)
	svc.set_session(2, 7)
	svc.report(2, 7, 50.0, 20000.0, Vector3(1, 2, 3), 1.5)
	var s := svc.load_or_create(2)
	T.eq(s.hp, 50.0, "sessão atual vale")
	T.eq(s.mp, 10000.0, "mp clampado")
	T.eq(s.world_pos, Vector3(1, 2, 3), "posição")
	svc.report(2, 6, 1.0, 1.0, Vector3(9, 9, 9), 0.0)
	T.eq(s.hp, 50.0, "sessão velha ignorada (hp)")
	T.eq(s.world_pos, Vector3(1, 2, 3), "sessão velha ignorada (pos)")
	svc.report(2, 7, -5.0, 1.0, Vector3.ZERO, 0.0)
	T.eq(s.hp, 0.0, "hp negativo vira 0")
	svc.unload(2)
	var s2 := svc.load_or_create(2)
	T.eq(s2.mp, 1.0, "unload gravou")
	T.eq(s2.world_yaw, 0.0, "yaw gravado")
	db.close()


func test_grant_logs_source() -> void:
	var db := _fresh()
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	svc.load_or_create(2)
	var r := svc.grant(2, 40, 5, {"health_potion": 1}, "loot")
	T.ok(r.ok, "concedeu")
	T.eq(r.state.gold, 65, "ouro somado")
	var ouro := db.query("SELECT * FROM economy_log WHERE kind = 'grant' AND item_id IS NULL")
	T.eq(ouro.size(), 1, "linha de ouro")
	T.eq(ouro[0]["amount"], 40, "valor")
	T.eq(ouro[0]["source"], "loot", "source")
	var it := db.query("SELECT * FROM economy_log WHERE item_id = 'health_potion'")
	T.eq(it[0]["source"], "loot", "source do item")
	T.eq(db.query("SELECT amount FROM economy_log WHERE kind = 'xp'")[0]["amount"], 5, "linha de xp")
	T.ok(not svc.grant(2, -1, 0, {}, "loot").ok, "negativo recusado")
	db.close()


func test_kill_and_run_finish() -> void:
	var db := _fresh()
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	svc.load_or_create(2)
	var r := svc.kill(2, "goblin", 10)
	T.ok(r.ok, "abate")
	T.eq(r.state.kills, 1, "contou abate")
	svc.finish_player(0, 2, "horde_run", 0, 30, 12, {"health_potion": 2}, {})
	var rows := db.query("SELECT * FROM economy_log WHERE kind = 'run'")
	T.eq(rows.size(), 1, "uma linha por partida")
	T.eq(rows[0]["source"], "horde_run", "modo")
	T.eq(rows[0]["amount"], 30, "ouro")
	var det = JSON.parse_string(rows[0]["detail"])
	T.eq(int(det["xp"]), 12, "xp no detalhe")
	T.eq(int(det["items"]["health_potion"]), 2, "itens no detalhe")
	svc.grant(2, 5, 0, {}, "horde_run")
	T.eq(db.query("SELECT COUNT(*) AS n FROM economy_log WHERE kind = 'grant'")[0]["n"], 0, "grant da partida não registra por moeda")
	db.close()


func test_unload_is_session_scoped() -> void:
	var db := _fresh()
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	svc.load_or_create(2)
	svc.set_session(2, 10)
	svc.set_session(2, 11)
	svc.unload(2, 10)   # desconexão tardia da conexão velha
	svc.report(2, 11, 33.0, 4.0, Vector3(1, 1, 1), 0.0)
	T.eq(svc.load_or_create(2).hp, 33.0, "sessão nova continua valendo")
	svc.unload(2, 11)
	T.eq(svc.load_or_create(2).hp, 33.0, "unload da sessão atual gravou")
	db.close()


func test_discard_and_death_are_client_ops() -> void:
	var db := _fresh()
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	var s := svc.load_or_create(2)
	svc.apply(2, "choose_class", ["warrior", "m"])
	var pocoes := _count(s, "health_potion")
	T.ok(svc.apply(2, "discard", ["health_potion"]).ok, "jogar fora")
	T.eq(_count(svc.load_or_create(2), "health_potion"), pocoes - 1, "uma poção a menos")
	var r := svc.apply(2, "death_penalty", [])
	T.ok(r.ok, "morte")
	T.eq(r.state.gold, 23, "25 - 10%")
	db.close()


## Relatório de vida/posição só mexe no cache; o servidor grava em lote (flush_dirty), não o cliente.
func test_report_is_cache_only_and_flush_dirty() -> void:
	var db := _fresh()
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	svc.load_or_create(2)
	svc.set_session(2, 7)
	svc.report(2, 7, 40.0, 3.0, Vector3(1, 2, 3), 0.5)
	var hp_db = db.query("SELECT hp FROM characters WHERE account_id = 2")[0]["hp"]
	T.ok(not is_equal_approx(float(hp_db), 40.0), "report não grava no banco na hora")
	T.eq(svc.flush_dirty(), 1, "uma conta suja gravada")
	T.ok(is_equal_approx(float(db.query("SELECT hp FROM characters WHERE account_id = 2")[0]["hp"]), 40.0), "flush gravou")
	T.eq(svc.flush_dirty(), 0, "nada sujo depois do flush")
	db.close()


## Servidor desligando: save_all grava todos os personagens em cache (o relatório ainda não gravado inclusive).
func test_save_all_on_shutdown() -> void:
	var db := _fresh()
	db.exec("INSERT INTO accounts(id, username, pass_hash, pass_salt, created_at) VALUES(3, 'bia', 'h', 's', 1)")
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	svc.load_or_create(2)
	svc.load_or_create(3)
	svc.set_session(2, 7)
	svc.report(2, 7, 33.0, 4.0, Vector3(5, 1, 5), 0.0)
	T.eq(svc.save_all(), 2, "gravou os 2 personagens em cache")
	db.close()
	var db2 := Db.open(PATH)
	T.ok(is_equal_approx(float(db2.query("SELECT hp FROM characters WHERE account_id = 2")[0]["hp"]), 33.0),
		"vida do relatório sobreviveu ao desligamento")
	T.eq(db2.query("SELECT account_id FROM characters").size(), 2, "as duas linhas existem")
	db2.close()


func test_report_clamps_position() -> void:
	var db := _fresh()
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	svc.load_or_create(2)
	svc.set_session(2, 7)
	svc.report(2, 7, 10.0, 1.0, Vector3(1e9, -1e9, 5), 0.0)
	T.eq(svc.load_or_create(2).world_pos, Vector3(10000, -10000, 5), "posição limitada a ±10000")
	db.close()


## Ouro de teste (net_test): só com o servidor em --test, valor entre 1 e TEST_GOLD_MAX.
func test_grant_test_gold_gate() -> void:
	var db := _fresh()
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	T.eq(svc.grant_test_gold(2, 100, false).err, "sem_teste", "sem --test é recusado")
	T.eq(svc.load_or_create(2).gold, 25, "ouro intacto")
	T.eq(svc.grant_test_gold(2, 0, true).err, "valor_invalido", "zero")
	T.eq(svc.grant_test_gold(2, CharacterService.TEST_GOLD_MAX + 1, true).err, "valor_invalido", "acima do teto")
	var r := svc.grant_test_gold(2, 100, true)
	T.ok(r.ok and r.state.gold == 125, "com --test concede")
	db.close()


## Recorde de partida (horde_best/city_best) gravado pelo servidor no personagem; só sobe.
func test_set_record() -> void:
	var db := _fresh()
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	T.ok(svc.set_record(2, "city_best", 3).ok, "grava city_best")
	T.eq(svc.set_record(2, "city_best", 2).state.flags.get("city_best"), 3, "não desce")
	T.eq(svc.set_record(2, "outra", 9).err, "chave_invalida", "só as chaves de recorde")
	var hb := {"round": 4, "kills": 50, "time": 200, "level": 7}
	T.ok(svc.set_record(2, "horde_best", hb).ok, "grava horde_best")
	T.eq(svc.set_record(2, "horde_best", {"round": 2, "kills": 99}).state.flags.horde_best.round, 4, "horde_best não desce")
	db.close()
	var db2 := Db.open(PATH)
	var s := CharacterService.new(SqliteCharStore.new(db2), _tables()).load_or_create(2)
	T.eq(int(s.flags.get("city_best", 0)), 3, "city_best persistiu")
	T.eq(int(s.flags.get("horde_best", {}).get("round", 0)), 4, "horde_best persistiu")
	db2.close()


## Encantar pelo serviço: grava no SQLite (coluna enchants), registra ouro e materiais e sobrevive a reabrir.
func test_enchant_persists_and_logs() -> void:
	var db := _fresh()
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	svc.load_or_create(2)
	svc.apply(2, "choose_class", ["warrior", "m"])
	svc.grant(2, 50, 0, {"iron_ore": 4, "ember_core": 2}, "test")
	var r := svc.apply(2, "enchant", ["fogo"])
	T.ok(r.ok, "encantou pelo serviço: %s" % r.err)
	T.eq(r.state.enchants, {"azure_edge": {"el": "fogo", "lv": 1}}, "estado devolvido traz o encanto")
	var rows := db.query("SELECT * FROM economy_log WHERE source = 'enchant' ORDER BY item_id")
	T.eq(rows.size(), 3, "ouro, ferro e essência registrados")
	for row in rows:
		T.eq(row["kind"], "enchant", "kind = enchant")
		T.ok(row["amount"] < 0, "gasto é negativo")
	db.close()
	var db2 := Db.open(PATH)
	var s := CharacterService.new(SqliteCharStore.new(db2), _tables()).load_or_create(2)
	T.eq(s.enchants, {"azure_edge": {"el": "fogo", "lv": 1}}, "gravado: sobrevive a reabrir o banco")
	db2.close()


## Classe e corpo vão para o SQLite (colunas char_class e body): sem isso, todo login online voltava sem classe.
func test_class_and_body_persist_in_sqlite() -> void:
	var db := _fresh()
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	svc.load_or_create(2)
	T.ok(svc.apply(2, "choose_class", ["archer", "f"]).ok, "escolheu")
	svc.unload(2)
	db.close()
	var db2 := Db.open(PATH)
	var s := CharacterService.new(SqliteCharStore.new(db2), _tables()).load_or_create(2)
	T.eq(s.char_class, "archer", "classe sobrevive a reabrir o banco")
	T.eq(s.body, "f", "corpo sobrevive a reabrir o banco")
	T.eq(s.equipment.weapon, "short_bow", "arco da classe")
	db2.close()


func test_enchant_bad_args_and_refusal() -> void:
	var db := _fresh()
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	svc.load_or_create(2)
	svc.apply(2, "choose_class", ["warrior", "m"])
	T.eq(svc.apply(2, "enchant", []).err, "args", "sem argumento")
	T.eq(svc.apply(2, "enchant", [3]).err, "args", "tipo errado")
	T.eq(svc.apply(2, "enchant", ["luz"]).err, "elemento_invalido", "elemento desconhecido")
	T.eq(svc.apply(2, "enchant", ["fogo"]).err, "sem_ouro", "sem recursos")
	T.eq(db.query("SELECT COUNT(*) AS n FROM economy_log WHERE source = 'enchant'")[0]["n"], 0, "recusa não registra")
	db.close()


## Os Ecos do +5 entram no registro como kind "ecos" e item "enchant".
func test_enchant_ecos_logged() -> void:
	var db := _fresh()
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	var s := svc.load_or_create(2)
	svc.apply(2, "choose_class", ["warrior", "m"])
	s.enchants["azure_edge"] = {"el": "sombra", "lv": 4}
	s.ecos = 40
	svc.grant(2, 1000, 0, {"iron_ore": 20, "arcane_crystal": 12, "shadow_fang": 10}, "test")
	T.ok(svc.apply(2, "enchant", ["sombra"]).ok, "+5")
	var ecos := db.query("SELECT * FROM economy_log WHERE kind = 'ecos' AND source = 'enchant'")
	T.eq(ecos.size(), 1, "uma linha de Ecos")
	T.eq(ecos[0]["amount"], -40, "40 Ecos gastos")
	T.eq(ecos[0]["item_id"], "enchant", "item = enchant")
	db.close()


## Itens de teste: só com o servidor em --test, até 99 de cada item conhecido.
func test_grant_test_items_gate() -> void:
	var db := _fresh()
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	T.eq(svc.grant_test_items(2, {"iron_ore": 4}, false).err, "sem_teste", "sem --test é recusado")
	T.eq(svc.grant_test_items(2, {"item_fantasma": 1}, true).err, "valor_invalido", "item desconhecido")
	T.eq(svc.grant_test_items(2, {"iron_ore": 100}, true).err, "valor_invalido", "acima de 99")
	T.eq(svc.grant_test_items(2, {}, true).err, "valor_invalido", "vazio")
	var r := svc.grant_test_items(2, {"iron_ore": 4, "frost_drop": 2}, true)
	T.ok(r.ok, "com --test concede")
	T.eq(_count(svc.load_or_create(2), "iron_ore"), 4, "ferro na mochila")
	db.close()


func test_op_blocked_without_class() -> void:
	var db := _fresh()
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	svc.load_or_create(2)
	var r := svc.apply(2, "buy", ["health_potion", 1])
	T.ok(not r.ok, "bloqueado")
	T.eq(r.err, "sem_classe", "erro")
	T.eq(svc.apply(2, "choose_class", ["archer"]).err, "args", "faltou o corpo")
	var c := svc.apply(2, "choose_class", ["archer", "m"])
	T.ok(c.ok, "escolheu")
	T.eq(svc.load_or_create(2).equipment.weapon, "short_bow", "arco inicial")
	T.ok(svc.apply(2, "buy", ["health_potion", 1]).ok, "depois da escolha compra")
	db.close()


func test_food_bonus_xp_gold_in_town() -> void:
	var db := _fresh()
	var t := [1000.0]
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables(), func() -> float: return t[0])
	svc.apply(2, "choose_class", ["warrior", "m"])
	var s := svc.load_or_create(2)
	var xp0 := s.xp
	s.inventory.append({"id": "garden_salad", "qty": 1})
	T.ok(svc.apply(2, "consume", ["garden_salad"]).ok, "comeu")
	svc.kill(2, "slime", 10)
	T.eq(s.xp - xp0, 11, "kill de 10 XP vira 11 (+10%)")
	xp0 = s.xp
	svc.grant(2, 0, 10, {}, "party_xp")
	T.eq(s.xp - xp0, 11, "XP do grupo também")
	xp0 = s.xp
	svc.grant(2, 0, 10, {}, "horde_run")
	T.eq(s.xp - xp0, 10, "horde_run não multiplica")
	svc.grant(2, 0, 10, {}, "admin")
	T.eq(s.xp - xp0, 20, "outras fontes não multiplicam")
	xp0 = s.xp
	t[0] += 1000.0   # passou do tempo do buff
	svc.kill(2, "slime", 10)
	T.eq(s.xp - xp0, 10, "depois de expirar volta ao normal")
	db.close()


func test_talents_ops_and_sqlite_roundtrip() -> void:
	var db := _fresh()
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	var s := svc.load_or_create(2)
	T.eq(svc.apply(2, "learn_talent", ["w_edge"]).err, "sem_classe", "sem classe o servidor recusa")
	svc.apply(2, "choose_class", ["warrior", "m"])
	s.level = 5
	T.eq(svc.apply(2, "learn_talent", []).err, "args", "sem argumento")
	T.eq(svc.apply(2, "learn_talent", [3]).err, "args", "tipo errado")
	T.eq(svc.apply(2, "learn_talent", ["a_aim"]).err, "talento_invalido", "outra classe")
	var r := svc.apply(2, "learn_talent", ["w_edge"])
	T.ok(r.ok, "aprendeu: %s" % r.err)
	T.eq(r.state.talents, {"w_edge": 1}, "estado devolvido")
	svc.unload(2)
	db.close()
	var db2 := Db.open(PATH)
	var svc2 := CharacterService.new(SqliteCharStore.new(db2), _tables())
	var s2 := svc2.load_or_create(2)
	T.eq(s2.talents, {"w_edge": 1}, "talentos sobrevivem a reabrir o banco")
	T.ok(svc2.apply(2, "reset_talents", []).ok, "redistribui (nível baixo, grátis)")
	svc2.unload(2)
	db2.close()
	var db3 := Db.open(PATH)
	T.eq(CharacterService.new(SqliteCharStore.new(db3), _tables()).load_or_create(2).talents, {}, "reset persistiu")
	db3.close()


## Seleção de personagem: a conta cria vários (já com classe), lista e exclui só os dela.
func test_many_characters_per_account() -> void:
	var db := _fresh()
	db.exec("INSERT INTO accounts(id, username, pass_hash, pass_salt, created_at) VALUES(3, 'bia', 'h', 's', 1)")
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	T.eq(svc.list_characters(2).size(), 0, "conta nova sem personagens")
	var a := svc.create_character(2, "Aldric", "warrior", "m")
	var b := svc.create_character(2, "Lyra", "mage", "f")
	T.ok(a.ok and b.ok and a.id != b.id, "criou dois personagens (%s, %s)" % [a, b])
	T.ok(not svc.create_character(2, "Pirata", "pirata", "m").ok, "classe inválida recusada")
	var list := svc.list_characters(2)
	T.eq(list.size(), 2, "lista tem os dois")
	T.eq(list[0].char_class, "warrior", "primeiro é o guerreiro")
	T.eq(list[1].body, "f", "segunda é mulher")
	T.eq(list[0].level, 1, "nível 1")
	T.eq(list[0].name, "Aldric", "lista traz o nome")
	T.eq(svc.name_of(b.id), "Lyra", "name_of")
	T.ok(str(list[1].equipment.get("weapon", "")) != "", "já empunha a arma da classe")
	# cada personagem tem a sua mochila e o seu ouro
	svc.grant(a.id, 50, 0, {}, "test")
	T.eq(svc.load_or_create(b.id).gold, svc.load_or_create(a.id).gold - 50, "ouro é por personagem")
	T.eq(svc.owner_of(b.id), 2, "dono é a conta 2")
	# economia registra conta e personagem
	var row := db.query("SELECT account_id, char_id FROM economy_log WHERE source = 'test'")
	T.ok(not row.is_empty() and int(row[0]["account_id"]) == 2 and int(row[0]["char_id"]) == a.id, "linha com conta e personagem")
	# outra conta não exclui
	T.ok(not svc.delete_character(3, a.id), "conta 3 não exclui personagem da 2")
	T.ok(svc.delete_character(2, a.id), "dona exclui")
	T.eq(svc.list_characters(2).size(), 1, "sobrou um")
	T.eq(db.query("SELECT COUNT(*) AS n FROM inventory WHERE char_id = ?", [a.id])[0]["n"], 0, "mochila apagada")
	db.close()


## Nome do herói: regra (3 a 16 letras/números, começa por letra, sem espaço) e único entre todas as
## contas, sem diferenciar maiúsculas. Excluir libera o nome.
func test_character_names() -> void:
	T.eq(CharacterService.clean_name("  Élise  "), "Élise", "acento vale e as pontas são cortadas")
	T.eq(CharacterService.clean_name("Ana2"), "Ana2", "número depois da letra vale")
	for bad in ["Al", "2Ana", "Ana Maria", "Ana_", "Abcdefghijklmnopq", ""]:
		T.eq(CharacterService.clean_name(bad), "", "nome inválido: '%s'" % bad)
	var db := _fresh()
	db.exec("INSERT INTO accounts(id, username, pass_hash, pass_salt, created_at) VALUES(3, 'bia', 'h', 's', 1)")
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	var a := svc.create_character(2, "Aldric", "warrior", "m")
	T.ok(a.ok, "criou Aldric")
	var dup := svc.create_character(3, "ALDRIC", "mage", "f")
	T.ok(not dup.ok and dup.err == "nome_em_uso", "outro jogador não usa o mesmo nome (%s)" % dup.err)
	T.eq(svc.create_character(2, "A b", "mage", "f").err, "nome_invalido", "nome inválido recusado no servidor")
	T.ok(svc.delete_character(2, a.id), "excluiu")
	T.ok(svc.create_character(3, "Aldric", "mage", "f").ok, "nome livre de novo depois de excluir")
	db.close()


func test_load_migrates_and_saves() -> void:
	var db := _fresh()
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	var s := svc.load_or_create(2)
	T.eq(int(s.flags.get("prog_v", 0)), 1, "personagem novo já nasce na versão")
	# vira um save antigo: sem prog_v, nível 18 e atributos gastos
	s.level = 18
	s.flags.erase("prog_v")
	s.flags["rank"] = "C"
	s.attributes = {"str": 56, "int": 5, "vit": 5, "agi": 5}
	s.stat_points = 0
	T.ok(svc.save(2), "gravou o save antigo")
	var svc2 := CharacterService.new(SqliteCharStore.new(db), _tables())
	var m := svc2.load_or_create(2)
	T.eq(m.attributes["str"], 5, "migrado ao carregar")
	T.eq(m.stat_points, 17 * 3 + 3, "pontos devolvidos")
	T.ok(m.flags.get("prog_notice", false), "aviso pendente")
	var svc3 := CharacterService.new(SqliteCharStore.new(db), _tables())
	var again := svc3.load_or_create(2)
	T.eq(again.attributes["str"], 5, "o banco também está migrado")
	T.eq(again.stat_points, 17 * 3 + 3, "pontos gravados")
	# o cliente confirma o aviso (mesmo sem classe escolhida) e o servidor grava
	T.ok(svc3.apply(2, "ack_prog_notice", []).ok, "confirma o aviso")
	var svc4 := CharacterService.new(SqliteCharStore.new(db), _tables())
	T.ok(not svc4.load_or_create(2).flags.has("prog_notice"), "aviso limpo no banco")
	T.ok(not svc4.apply(2, "ack_prog_notice", [1]).ok, "argumentos de fora são recusados")
	db.close()


func test_hair_persists_and_lists() -> void:
	var db := _fresh()
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	var r := svc.create_character(2, "Lyra", "mage", "f", "f_marias")
	T.ok(r.ok, "criou: %s" % r.err)
	T.eq(str(svc.create_character(2, "Bia", "mage", "f", "m_franja").err), "penteado_invalido", "penteado do outro corpo")
	var e: Array = svc.list_characters(2).filter(func(x: Dictionary) -> bool: return int(x.id) == int(r.id))
	T.eq(e[0].get("hair", ""), "f_marias", "lista traz o penteado")
	svc.unload(int(r.id))
	db.close()
	var db2 := Db.open(PATH)
	var s := CharacterService.new(SqliteCharStore.new(db2), _tables()).load_or_create(int(r.id))
	T.eq(s.hair, "f_marias", "penteado sobrevive a reabrir o banco")
	db2.close()
