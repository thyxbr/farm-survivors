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


func test_enchant_bad_args_and_refusal() -> void:
	var db := _fresh()
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	svc.load_or_create(2)
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
