extends RefCounted
## FileCharStore (personagem solo em JSON, sem SQLite) e o CharacterService sobre ele.

const PATH := "user://test_filestore_character.json"

var _bt: BalanceTables


func _tables() -> BalanceTables:
	if _bt == null:
		_bt = BalanceTables.load_dir("res://data/balance")
	return _bt


func _fresh() -> FileCharStore:
	var st := FileCharStore.new(PATH)
	st.remove_files()
	for f in [PATH + ".invalido", "user://test_filestore_character_2.json"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	return st


func test_round_trip() -> void:
	var st := _fresh()
	T.ok(st.load_char(1) == null, "sem arquivo: null")
	var s := CharState.new_character(_tables())
	s.gold = 321
	s.level = 4
	s.world_pos = Vector3(1.5, 0.5, -2)
	s.world_yaw = 0.75
	s.flags["horde_best"] = {"round": 3, "kills": 40}
	T.ok(st.save_char(1, s.to_dict(), [], 1000), "gravou")
	T.ok(FileAccess.file_exists(PATH), "arquivo existe")
	T.ok(not FileAccess.file_exists(PATH + ".tmp"), "temporário renomeado")
	var d = FileCharStore.new(PATH).load_char(1)
	T.ok(d is Dictionary, "leu de novo")
	T.eq(int(d["updated_at"]), 1000, "updated_at")
	var s2 := CharState.from_dict(d, _tables())
	var a := s.to_dict()
	var b := s2.to_dict()
	# o JSON devolve todo número como float: compara pelo texto JSON. Os flags ficam como vieram (float),
	# igual ao que já acontecia com o JSON dos flags no SQLite: quem lê usa int().
	for k in a:
		if k != "flags":
			T.eq(JSON.stringify(b[k]), JSON.stringify(a[k]), "campo %s igual depois de ida e volta" % k)
	T.eq(int(b["flags"]["horde_best"]["round"]), 3, "flags")
	# segunda gravação substitui a primeira (rename por cima do arquivo existente)
	s.gold = 7
	T.ok(st.save_char(1, s.to_dict(), [], 2000), "regravou")
	T.eq(CharState.from_dict(st.load_char(1), _tables()).gold, 7, "valor novo")
	# outra conta vai noutro arquivo
	T.ok(st.save_char(2, s.to_dict(), [], 1), "conta 2")
	T.ok(FileAccess.file_exists("user://test_filestore_character_2.json"), "arquivo da conta 2")
	T.ok(st.delete_char(1) and st.load_char(1) == null, "apagou o solo")
	T.ok(st.load_char(2) is Dictionary, "conta 2 intacta")
	st.delete_char(2)


func test_atomic_write_keeps_old_file() -> void:
	var st := _fresh()
	var s := CharState.new_character(_tables())
	s.gold = 100
	T.ok(st.save_char(1, s.to_dict(), [], 1), "versão 1")
	var antes := FileAccess.get_file_as_string(PATH)
	s.gold = 999
	st.fail_next_write = true
	T.ok(not st.save_char(1, s.to_dict(), [CharStore.row(2, 1, "grant", 899, null, "loot")], 2), "falha simulada devolve false")
	T.ok(st.last_error != "", "last_error preenchido")
	T.eq(FileAccess.get_file_as_string(PATH), antes, "arquivo anterior intacto")
	T.eq(CharState.from_dict(st.load_char(1), _tables()).gold, 100, "continua a versão 1")
	T.eq(st.economy_rows().size(), 0, "falha não registra economia")
	# o temporário pela metade não atrapalha a próxima gravação
	T.ok(st.save_char(1, s.to_dict(), [], 3), "grava de novo")
	T.eq(CharState.from_dict(st.load_char(1), _tables()).gold, 999, "versão nova")
	st.remove_files()


func test_invalid_file_is_kept_aside() -> void:
	var st := _fresh()
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("{quebrado")
	f.close()
	T.ok(st.load_char(1) == null, "JSON inválido: null")
	T.ok(FileAccess.file_exists(PATH + ".invalido"), "cópia guardada")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH + ".invalido"))
	st.remove_files()


func test_economy_rows() -> void:
	var st := _fresh()
	T.ok(st.append_economy([CharStore.row(10, 1, "run", 30, null, "horde_run", JSON.stringify({"xp": 5}))]), "acrescentou")
	T.ok(st.append_economy([CharStore.row(11, 1, "buy", 1, "health_potion", "player"),
		CharStore.row(11, 1, "buy", -20, null, "player")]), "acrescentou mais duas")
	var rows := st.economy_rows()
	T.eq(rows.size(), 3, "três linhas")
	T.eq(rows[0]["kind"], "run", "ordem mantida")
	T.eq(rows[0]["item_id"], null, "ouro = item null")
	T.eq(rows[1]["item_id"], "health_potion", "item")
	T.eq(int(rows[2]["amount"]), -20, "valor")
	T.ok(st.delete_char(1), "novo jogo")
	T.ok(not FileAccess.file_exists(st.economy_path()), "novo jogo apaga a economia do solo")


## As mesmas regras do servidor sobre o arquivo: compra registra, recarrega igual, resumo de partida.
func test_character_service_on_files() -> void:
	var st := _fresh()
	var svc := CharacterService.new(st, _tables())
	var s := svc.load_or_create(1)
	var ouro := s.gold
	T.ok(FileAccess.file_exists(PATH), "personagem novo gravado")
	var r := svc.apply(1, "buy", ["health_potion", 1])
	T.ok(r.ok, "comprou: %s" % r.err)
	var rows := st.economy_rows()
	T.eq(rows.size(), 2, "item + ouro registrados")
	T.ok(svc.finish_player(0, 1, "horde_run", 0, 30, 12, {"health_potion": 2}, {}).ok, "resumo de partida")
	T.eq(st.economy_rows().size(), 3, "linha do resumo")
	T.eq(st.economy_rows()[2]["source"], "horde_run", "modo")
	svc.grant(1, 5, 0, {}, "horde_run")
	T.eq(st.economy_rows().size(), 3, "grant da partida não registra por moeda")
	var s2 := CharacterService.new(FileCharStore.new(PATH), _tables()).load_or_create(1)
	T.eq(s2.gold, ouro - int(_tables().get_table("items")["health_potion"]["price"]) + 5, "ouro persistiu")
	T.eq(s2.to_dict()["inventory"], svc.load_or_create(1).to_dict()["inventory"], "mochila persistiu")
	st.remove_files()


## O encanto vai e volta pelo arquivo do solo.
func test_enchants_round_trip() -> void:
	var st := _fresh()
	var svc := CharacterService.new(st, _tables())
	svc.load_or_create(1)
	svc.grant(1, 50, 0, {"iron_ore": 4, "frost_drop": 2}, "test")
	T.ok(svc.apply(1, "enchant", ["gelo"]).ok, "encantou no solo")
	var s2 := CharacterService.new(FileCharStore.new(PATH), _tables()).load_or_create(1)
	T.eq(s2.enchants, {"azure_edge": {"el": "gelo", "lv": 1}}, "encanto persistiu no arquivo")
	st.remove_files()


## Queda entre o "apaga o destino" e o "move o .tmp" do rename no Windows: o save inteiro ficou no .tmp.
func test_recovers_save_left_in_tmp() -> void:
	var st := _fresh()
	var s := CharState.new_character(_tables())
	s.gold = 777
	T.ok(st.save_char(1, s.to_dict(), [], 2000), "gravou")
	var p := st.char_path(1)
	DirAccess.rename_absolute(ProjectSettings.globalize_path(p), ProjectSettings.globalize_path(p + ".tmp"))
	T.ok(not FileAccess.file_exists(p), "simulou a queda: só o .tmp existe")
	var d = FileCharStore.new(PATH).load_char(1)
	T.ok(d is Dictionary, "recuperou o save do .tmp")
	T.eq(int(CharState.from_dict(d, _tables()).gold), 777, "mesmo ouro")
	T.ok(FileAccess.file_exists(p) and not FileAccess.file_exists(p + ".tmp"), ".tmp voltou para o lugar")
	FileAccess.open(p + ".tmp", FileAccess.WRITE).store_string("{quebrado")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	T.ok(FileCharStore.new(PATH).load_char(1) == null, ".tmp estragado não é recuperado")
	st.remove_files()
