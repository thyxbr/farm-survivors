extends RefCounted
## Títulos do personagem (TitleRules) e a op "set_title" do CharacterService.

var _bt: BalanceTables


func _tables() -> BalanceTables:
	if _bt == null:
		_bt = BalanceTables.load_dir("res://data/balance")
	return _bt


func test_unlocks_by_progress() -> void:
	T.eq(TitleRules.unlocked(1, {}), ["recem_chegado"], "nível 1 sem nada: só recém-chegado")
	var got := TitleRules.unlocked(25, {"rank": "B", "horde_best": {"round": 12}, "city_best": 3})
	for id in ["aventureiro", "veterano", "membro_guilda", "lamina_guilda", "sobrevivente"]:
		T.ok(id in got, "%s liberado" % id)
	for id in ["lenda_valdoria", "campeao_guilda", "flagelo_horda", "guardiao_noite"]:
		T.ok(not (id in got), "%s ainda bloqueado" % id)
	T.eq(TitleRules.horde_round({"horde_best": 7}), 7, "recorde antigo só com o número")


func test_set_title_validates() -> void:
	var s := CharState.new_character(_tables())
	T.ok(TitleRules.set_title(s, "recem_chegado").ok, "escolhe título liberado")
	T.eq(TitleRules.current(s.level, s.flags), "recem_chegado", "título guardado")
	var r := TitleRules.set_title(s, "veterano")
	T.eq(r.err, "titulo_bloqueado", "nível 1 não pode ser veterano")
	T.eq(str(s.flags.get("title")), "recem_chegado", "recusa mantém o anterior")
	T.eq(TitleRules.set_title(s, "nao_existe").err, "titulo_invalido", "id desconhecido")
	T.ok(TitleRules.set_title(s, "").ok, "tira o título")
	T.ok(not s.flags.has("title"), "sem título")
	T.eq(TitleRules.label("aventureiro"), "Aventureiro", "nome do título")


func test_service_op() -> void:
	var svc := CharacterService.new(FileCharStore.new("user://test_titles.json"), _tables())
	var s := svc.load_or_create(1)
	CharRules.choose_class(s, _tables(), "warrior", "m")
	var r := svc.apply(1, "set_title", ["recem_chegado"])
	T.ok(r.ok, "op set_title aceita")
	T.eq(str(svc.load_or_create(1).flags.get("title")), "recem_chegado", "gravado no personagem")
	T.ok(not svc.apply(1, "set_title", [3]).ok, "argumento errado recusado")
