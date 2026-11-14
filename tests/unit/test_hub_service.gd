extends RefCounted
## CharacterService da fase 2: Ecos, passivas, base compartilhada e registro das partidas.

const PATH := "user://test_hubsvc.db"
const SOLO_PATH := "user://test_hubsvc_solo.json"

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
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	var f := svc.finish_player(0, 2, "city", 5, 0, 0, {}, {})
	T.ok(f.ok, "finish ok")
	T.eq(f.state.ecos, 45, "ecos da partida")
	var r := svc.apply(2, "buy_passive", ["poder"])
	T.ok(r.ok, "comprou passiva: %s" % r.err)
	db.close()
	var db2 := Db.open(PATH)
	var svc2 := CharacterService.new(SqliteCharStore.new(db2), _tables())
	var s := svc2.load_or_create(2)
	T.eq(s.ecos, 20, "ecos persistiram")
	T.eq(int(s.passives.get("poder", 0)), 1, "passiva persistiu")
	var ganhos := db2.query("SELECT * FROM economy_log WHERE kind = 'ecos' AND source = 'city'")
	T.eq(ganhos.size(), 1, "uma linha dos Ecos ganhos na partida")
	T.eq(ganhos[0]["amount"], 45, "Ecos ganhos, fonte = modo")
	T.eq(db2.query("SELECT COUNT(*) AS n FROM economy_log WHERE kind = 'ecos'")[0]["n"], 2, "ganho + passiva")
	var rows := db2.query("SELECT * FROM economy_log WHERE kind = 'ecos' AND source = 'passive'")
	T.eq(rows.size(), 1, "uma linha da passiva")
	T.eq(rows[0]["amount"], -25, "custo")
	T.eq(rows[0]["source"], "passive", "origem")
	T.eq(rows[0]["item_id"], "poder", "passiva")
	db2.close()


func test_donate_debits_and_levels_shared_base() -> void:
	var db := _fresh()
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
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
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
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
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
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
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
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
	var ecos_rows := db.query("SELECT * FROM economy_log WHERE kind = 'ecos'")
	T.eq(ecos_rows.size(), 1, "uma linha de Ecos (o repetido não registra de novo)")
	T.eq([ecos_rows[0]["amount"], ecos_rows[0]["source"]], [50, "horde"], "Ecos ganhos por fonte")
	T.eq(rows[0]["amount"], 40, "ouro")
	T.eq(rows[0]["source"], "horde", "modo")
	var det = JSON.parse_string(rows[0]["detail"])
	T.eq(int(det["ecos"]), 50, "ecos no detalhe")
	T.eq(int(det["run_id"]), id, "run_id no detalhe")
	db.close()


func test_finish_player_without_run_row() -> void:
	var db := _fresh()
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	var r := svc.finish_player(0, 2, "city", 2, 7, 3, {}, {})
	T.ok(r.ok, "ok")
	T.eq(db.query("SELECT COUNT(*) AS n FROM run_players")[0]["n"], 0, "sem run_players")
	T.eq(db.query("SELECT COUNT(*) AS n FROM economy_log WHERE kind = 'run'")[0]["n"], 1, "log de run")
	db.close()


func test_records_best_per_mode() -> void:
	var db := _fresh()
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
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


func _fresh_files() -> FileCharStore:
	var st := FileCharStore.new(SOLO_PATH)
	st.remove_files()
	return st


## Solo = FileCharStore com as mesmas regras do servidor, e sem SQLite nenhum: a classe é trocada por
## uma inexistente (como no cliente exportado) e todo o fluxo da praça tem que funcionar igual.
func test_solo_account_same_rules() -> void:
	var real := Db.sqlite_class
	Db.sqlite_class = "SQLiteQueNaoExiste"
	var st := _fresh_files()
	var svc := CharacterService.new(st, _tables())
	var solo := CharacterService.SOLO_ACCOUNT
	var run := svc.start_run("city", [solo])
	T.ok(run > 0, "partida aberta no arquivo")
	var f := svc.finish_player(run, solo, "city", 5, 7, 3, {"health_potion": 1}, {})
	T.eq(f.state.ecos, 45, "ecos no solo")
	T.eq(svc.finish_player(run, solo, "city", 5, 7, 3, {}, {}).state.ecos, 45, "fim de partida idempotente")
	T.ok(svc.close_run(run, 5, {}), "fechou a partida")
	var p := svc.apply(solo, "buy_passive", ["poder"])
	T.ok(p.ok, "passiva no solo: %s" % p.err)
	var d := svc.apply(solo, "donate", ["forja", 20])
	T.ok(d.ok, "doação no solo: %s" % d.err)
	T.eq(d.state.ecos, 0, "debitou tudo")
	T.eq(d.base.forja.fund, 20, "fundo da base local")
	T.eq(svc.top_donors("forja"), [{"name": "local", "amount": 20}], "doador local")
	T.eq(svc.records().city, {"reached": 5, "names": ["local"]}, "recorde local")
	# economia: run, passiva e doação no *_economy.jsonl
	var kinds := st.economy_rows().map(func(r: Dictionary) -> String: return "%s/%s" % [r.kind, r.source])
	T.eq(kinds, ["run/city", "ecos/city", "ecos/passive", "ecos/donation"], "linhas da economia (%s)" % str(kinds))
	# tudo relido do disco por um serviço novo
	var svc2 := CharacterService.new(FileCharStore.new(SOLO_PATH), _tables())
	var s := svc2.load_or_create(solo)
	T.eq(s.ecos, 0, "ecos persistiram")
	T.eq(int(s.passives.get("poder", 0)), 1, "passiva persistiu")
	T.eq(svc2.base_state().forja, {"level": 0, "fund": 20}, "base persistiu")
	T.eq(svc2.records().city.reached, 5, "recorde persistiu")
	T.ok(svc2.finish_player(run, solo, "city", 5, 0, 0, {}, {}).events[0].n == 0, "idempotente depois de reabrir")
	Db.sqlite_class = real
	st.remove_files()


## Arquivo: se o personagem não grava, a base não fica creditada nem a partida marcada como concedida.
func test_solo_files_all_or_nothing() -> void:
	var st := _fresh_files()
	var svc := CharacterService.new(st, _tables())
	var solo := CharacterService.SOLO_ACCOUNT
	_with_ecos(svc, solo, 100)
	T.ok(svc.apply(solo, "donate", ["forja", 10]).ok, "primeira doação")
	st.fail_next_write = true
	st.fail_after_writes = 1   # a base grava, o personagem falha
	var r := svc.apply(solo, "donate", ["forja", 30])
	T.eq(r.err, "erro_banco", "falha ao gravar")
	T.eq(r.state.ecos, 90, "ecos não debitados")
	T.eq(svc.base_state().forja.fund, 10, "base voltou ao que era")
	T.eq(svc.top_donors("forja")[0].amount, 10, "doação não entrou no histórico")
	var run := svc.start_run("horde", [solo])
	st.fail_next_write = true
	st.fail_after_writes = 1   # o arquivo das partidas grava, o personagem falha
	T.eq(svc.finish_player(run, solo, "horde", 10, 0, 0, {}, {}).err, "erro_banco", "fim de partida falhou")
	T.ok(not st.run_player_done(run, solo), "partida não marcada como concedida")
	var ok := svc.finish_player(run, solo, "horde", 10, 0, 0, {}, {})
	T.ok(ok.ok and ok.state.ecos == 140, "tentar de novo concede uma vez (%d)" % ok.state.ecos)
	st.remove_files()


func test_donate_checks_ecos_against_used() -> void:
	var db := _fresh()
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	_with_ecos(svc, 2, 120)
	db.exec("INSERT INTO base_buildings(building_id, level, fund) VALUES('forja', 4, 900)")
	var r := svc.apply(2, "donate", ["forja", 500])
	T.ok(r.ok, "doou o que faltava mesmo pedindo mais do que tem: %s" % r.err)
	T.eq(r.state.ecos, 20, "debitou só 100")
	T.eq(r.events[0].used, 100, "usado")
	T.eq(r.base.forja.level, 5, "nível máximo")
	db.close()


func test_grant_test_ecos_only_in_test() -> void:
	var db := _fresh()
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	T.eq(svc.grant_test_ecos(2, 50, false).err, "sem_teste", "sem --test")
	T.eq(svc.grant_test_ecos(2, 0, true).err, "valor_invalido", "zero")
	T.eq(svc.grant_test_ecos(2, CharacterService.TEST_GOLD_MAX + 1, true).err, "valor_invalido", "acima do teto")
	var r := svc.grant_test_ecos(2, 300, true)
	T.ok(r.ok, "concedeu: %s" % r.err)
	T.eq(r.state.ecos, 300, "ecos no estado")
	var rows := db.query("SELECT * FROM economy_log WHERE kind = 'ecos' AND source = 'test'")
	T.eq(rows.size(), 1, "registrado")
	T.eq(rows[0]["amount"], 300, "valor registrado")
	db.close()


## Arquivo do solo: uma cidade salva fica aberta enquanto o jogador faz mais de KEEP_RUNS Hordas; a poda
## não pode levar a partida aberta (o fim dela concede os Ecos e vale para o recorde).
func test_solo_open_run_survives_prune() -> void:
	var st := _fresh_files()
	var svc := CharacterService.new(st, _tables())
	var solo := CharacterService.SOLO_ACCOUNT
	var city := svc.start_run("city", [solo])
	for i in FileCharStore.KEEP_RUNS + 2:
		var h := svc.start_run("horde", [solo])
		svc.finish_player(h, solo, "horde", 1, 0, 0, {}, {})
		svc.close_run(h, 1, {})
	# 20 encerradas mais recentes + o recorde da Horda (a mais antiga, no empate) + a cidade aberta
	T.eq(st.run_rows().size(), FileCharStore.KEEP_RUNS + 2, "arquivo podado (%d partidas)" % st.run_rows().size())
	T.ok(st.run_rows().any(func(r) -> bool: return int(r.id) == city), "a cidade aberta continua no arquivo")
	var ecos0 := svc.load_or_create(solo).ecos
	var r := svc.finish_player(city, solo, "city", 5, 0, 0, {}, {})
	T.ok(r.ok, "fim da cidade gravou: %s" % r.err)
	T.eq(r.state.ecos, ecos0 + 45, "Ecos da cidade concedidos")
	T.ok(svc.close_run(city, 5, {}), "cidade fechada")
	T.eq(svc.records().city, {"reached": 5, "names": ["local"]}, "recorde da cidade")
	st.remove_files()


## Partida que sumiu (save antigo, id inválido): o fim concede como sem run_id, nos dois armazenamentos.
func test_finish_player_missing_run_still_grants() -> void:
	var st := _fresh_files()
	var svc := CharacterService.new(st, _tables())
	var r := svc.finish_player(999, 1, "city", 5, 0, 0, {}, {})
	T.ok(r.ok and r.state.ecos == 45, "arquivo: concedeu (%s, %d)" % [r.err, r.state.ecos])
	st.remove_files()
	var db := _fresh()
	var svc2 := CharacterService.new(SqliteCharStore.new(db), _tables())
	var r2 := svc2.finish_player(999, 2, "city", 5, 0, 0, {}, {})
	T.ok(r2.ok and r2.state.ecos == 45, "SQLite: concedeu (%s)" % r2.err)
	T.eq(db.query("SELECT COUNT(*) AS n FROM run_players")[0]["n"], 0, "sem linha em run_players")
	db.close()
