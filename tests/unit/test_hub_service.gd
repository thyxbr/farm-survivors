extends RefCounted
## CharacterService da fase 2: Ecos, passivas, base compartilhada e registro das partidas.

const PATH := "user://test_hubsvc.db"

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
	db.exec("INSERT INTO accounts(id, username, pass_hash, pass_salt, created_at) VALUES(3, 'beto', 'h', 's', 1)")
	return db


func _with_ecos(svc: CharacterService, account: int, n: int) -> void:
	svc.load_or_create(account).ecos = n
	svc.save(account)


func test_ecos_and_passives_persist() -> void:
	var db := _fresh()
	var svc := CharacterService.new(db, _tables())
	var f := svc.finish_player(0, 2, "city", 5, 0, 0, {}, {})
	T.ok(f.ok, "finish ok")
	T.eq(f.state.ecos, 45, "ecos da partida")
	var r := svc.apply(2, "buy_passive", ["poder"])
	T.ok(r.ok, "comprou passiva: %s" % r.err)
	db.close()
	var db2 := Db.open(PATH)
	var svc2 := CharacterService.new(db2, _tables())
	var s := svc2.load_or_create(2)
	T.eq(s.ecos, 20, "ecos persistiram")
	T.eq(int(s.passives.get("poder", 0)), 1, "passiva persistiu")
	var rows := db2.query("SELECT * FROM economy_log WHERE kind = 'ecos'")
	T.eq(rows.size(), 1, "uma linha de ecos")
	T.eq(rows[0]["amount"], -25, "custo")
	T.eq(rows[0]["source"], "passive", "origem")
	T.eq(rows[0]["item_id"], "poder", "passiva")
	db2.close()


func test_donate_debits_and_levels_shared_base() -> void:
	var db := _fresh()
	var svc := CharacterService.new(db, _tables())
	_with_ecos(svc, 2, 200)
	_with_ecos(svc, 3, 100)
	var r := svc.apply(2, "donate", ["forja", 150])
	T.ok(r.ok, "doou: %s" % r.err)
	T.eq(r.state.ecos, 50, "debitou")
	T.eq(r.base.forja.level, 1, "nível 1")
	T.eq(r.base.forja.fund, 30, "fundo")
	T.eq(r.events[0].t, "donated", "evento")
	T.eq(r.events[0].used, 150, "usado")
	var r2 := svc.apply(3, "donate", ["forja", 100])
	T.ok(r2.ok, "segunda doação")
	T.eq(svc.base_state().forja.fund, 130, "fundo somado")
	T.eq(svc.top_donors("forja"), [{"name": "ana", "amount": 150}, {"name": "beto", "amount": 100}], "doadores")
	T.ok(absf(float(svc.base_bonus().get("horde_damage", 0.0)) - 0.04) < 0.0001, "bônus")
	var log := db.query("SELECT * FROM economy_log WHERE kind = 'ecos' AND source = 'donation' AND account_id = 2")
	T.eq(log.size(), 1, "log da doação")
	T.eq(log[0]["amount"], -150, "valor logado")
	T.eq(log[0]["item_id"], "forja", "construção logada")
	db.close()


func test_donate_rejects_without_touching_db() -> void:
	var db := _fresh()
	var svc := CharacterService.new(db, _tables())
	_with_ecos(svc, 2, 10)
	T.eq(svc.apply(2, "donate", ["forja", 50]).err, "sem_ecos", "sem ecos")
	T.eq(svc.apply(2, "donate", ["forja", 0]).err, "valor_invalido", "valor inválido")
	T.eq(svc.apply(2, "donate", ["forja", "50"]).err, "args", "tipo errado")
	T.eq(db.query("SELECT COUNT(*) AS n FROM base_donations")[0]["n"], 0, "sem doações")
	T.eq(db.query("SELECT COUNT(*) AS n FROM base_buildings")[0]["n"], 0, "sem construções")
	T.eq(svc.load_or_create(2).ecos, 10, "ecos intactos")
	db.close()


func test_donate_at_max_charges_only_needed() -> void:
	var db := _fresh()
	var svc := CharacterService.new(db, _tables())
	_with_ecos(svc, 2, 1000)
	db.exec("INSERT INTO base_buildings(building_id, level, fund) VALUES('forja', 4, 900)")
	var r := svc.apply(2, "donate", ["forja", 500])
	T.ok(r.ok, "doou: %s" % r.err)
	T.eq(r.state.ecos, 900, "só o necessário")
	T.eq(r.base.forja.level, 5, "nível máximo")
	var r2 := svc.apply(2, "donate", ["forja", 10])
	T.eq(r2.err, "nivel_maximo", "já no máximo")
	T.eq(r2.state.ecos, 900, "ecos intactos")
	db.close()


func test_finish_player_idempotent() -> void:
	var db := _fresh()
	var svc := CharacterService.new(db, _tables())
	var id := svc.start_run("horde", [2])
	T.ok(id > 0, "run criada")
	var a := svc.finish_player(id, 2, "horde", 10, 40, 12, {"health_potion": 1}, {"w": "x"})
	T.ok(a.ok, "finish ok")
	T.eq(a.state.ecos, 50, "50 ecos")
	T.eq(a.events[0].t, "ecos", "evento ecos")
	T.eq(a.events[0].n, 50, "n")
	var b := svc.finish_player(id, 2, "horde", 10, 40, 12, {"health_potion": 1}, {"w": "x"})
	T.ok(b.ok, "repetido ok")
	T.eq(b.state.ecos, 50, "não concede de novo")
	T.eq(b.events[0].n, 0, "evento zero")
	T.eq(db.query("SELECT COUNT(*) AS n FROM run_players")[0]["n"], 1, "uma linha em run_players")
	var rows := db.query("SELECT * FROM economy_log WHERE kind = 'run'")
	T.eq(rows.size(), 1, "uma linha de run")
	T.eq(rows[0]["amount"], 40, "ouro")
	T.eq(rows[0]["source"], "horde", "modo")
	var det = JSON.parse_string(rows[0]["detail"])
	T.eq(int(det["ecos"]), 50, "ecos no detalhe")
	T.eq(int(det["run_id"]), id, "run_id no detalhe")
	db.close()


func test_finish_player_without_run_row() -> void:
	var db := _fresh()
	var svc := CharacterService.new(db, _tables())
	var r := svc.finish_player(0, 2, "city", 2, 7, 3, {}, {})
	T.ok(r.ok, "ok")
	T.eq(db.query("SELECT COUNT(*) AS n FROM run_players")[0]["n"], 0, "sem run_players")
	T.eq(db.query("SELECT COUNT(*) AS n FROM economy_log WHERE kind = 'run'")[0]["n"], 1, "log de run")
	db.close()


func test_records_best_per_mode() -> void:
	var db := _fresh()
	var svc := CharacterService.new(db, _tables())
	T.eq(svc.records(), {"horde": {"reached": 0, "names": []}, "city": {"reached": 0, "names": []}}, "vazio")
	var c1 := svc.start_run("city", [2])
	svc.finish_player(c1, 2, "city", 3, 0, 0, {}, {})
	svc.close_run(c1, 3, {})
	var c2 := svc.start_run("city", [2, 3])
	svc.finish_player(c2, 2, "city", 7, 0, 0, {}, {})
	svc.finish_player(c2, 3, "city", 7, 0, 0, {}, {})
	T.ok(svc.close_run(c2, 7, {"ok": true}), "fechou")
	var h := svc.start_run("horde", [3])
	svc.finish_player(h, 3, "horde", 4, 0, 0, {}, {})
	svc.close_run(h, 4, {})
	var rec := svc.records()
	T.eq(rec.city.reached, 7, "melhor city")
	var names: Array = rec.city.names.duplicate()
	names.sort()
	T.eq(names, ["ana", "beto"], "nomes")
	T.eq(rec.horde.reached, 4, "melhor horde")
	T.eq(rec.horde.names, ["beto"], "nome horde")
	db.close()


func test_solo_account_same_rules() -> void:
	var db := _fresh()
	var svc := CharacterService.new(db, _tables())
	var f := svc.finish_player(0, CharacterService.SOLO_ACCOUNT, "city", 5, 0, 0, {}, {})
	T.eq(f.state.ecos, 45, "ecos no solo")
	T.ok(svc.apply(CharacterService.SOLO_ACCOUNT, "buy_passive", ["poder"]).ok, "passiva no solo")
	var d := svc.apply(CharacterService.SOLO_ACCOUNT, "donate", ["forja", 20])
	T.ok(d.ok, "doação no solo: %s" % d.err)
	T.eq(d.state.ecos, 0, "debitou tudo")
	T.eq(svc.top_donors("forja"), [{"name": "local", "amount": 20}], "doador local")
	db.close()
