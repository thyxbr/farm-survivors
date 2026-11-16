extends RefCounted
## Modo admin: recursos infinitos ao ligar, devolve o que havia ao desligar, só com permissão.

const PATH := "user://test_admin.db"

var _bt: BalanceTables


func _tables() -> BalanceTables:
	if _bt == null:
		_bt = BalanceTables.load_dir("res://data/balance")
	return _bt


func _svc() -> CharacterService:
	Db.remove_files(PATH)
	var db := Db.open(PATH)
	Migrations.apply(db)
	db.exec("INSERT INTO accounts(id, username, pass_hash, pass_salt, created_at) VALUES(2, 'ana', 'h', 's', 1)")
	var svc := CharacterService.new(SqliteCharStore.new(db), _tables())
	svc.load_or_create(2)
	svc.apply(2, "choose_class", ["warrior", "m"])
	return svc


func test_resource_ids_cover_enchant_materials() -> void:
	var ids := AdminRules.resource_ids(_tables())
	for id in ["iron_ore", "ember_core", "health_potion"]:
		T.ok(id in ids, "%s é recurso" % id)
	T.ok(not ("azure_edge" in ids), "arma não é recurso")


func test_on_fills_and_off_restores() -> void:
	var bt := _tables()
	var s := CharState.new_character(bt)
	CharRules.choose_class(s, bt, "warrior", "m")
	s.gold = 37
	s.ecos = 4
	CharRules.add_item(s, bt, "iron_ore", 2)
	var inv_before := s.inventory.duplicate(true)
	T.ok(AdminRules.set_on(s, bt, true).ok, "ligou")
	T.ok(AdminRules.is_on(s), "está ligado")
	T.eq(s.gold, AdminRules.GOLD, "ouro no teto")
	T.eq(s.ecos, AdminRules.ECOS, "Ecos no teto")
	T.eq(CharRules.count_item(s, "ember_core"), AdminRules.ITEM_QTY, "essência no teto")
	# gasta à vontade: encanta até o máximo
	var lv := 0
	for i in 20:
		var r := EnchantRules.enchant(s, bt, "fogo")
		if not r.ok:
			T.eq(r.err, "nivel_maximo", "só para no nível máximo")
			break
		AdminRules.top_up(s, bt)
		lv += 1
	T.ok(lv >= 1, "encantou %d vezes" % lv)
	T.ok(AdminRules.set_on(s, bt, false).ok, "desligou")
	T.ok(not AdminRules.is_on(s), "está desligado")
	T.eq(s.gold, 37, "ouro devolvido")
	T.eq(s.ecos, 4, "Ecos devolvidos")
	T.eq(CharRules.count_item(s, "iron_ore"), 2, "ferro devolvido")
	T.eq(CharRules.count_item(s, "ember_core"), 0, "essência devolvida")
	T.eq(EnchantRules.of(s, "azure_edge").lv, lv, "encanto feito no modo admin fica")
	T.eq(s.inventory.size(), inv_before.size(), "mochila do tamanho de antes")


func test_service_requires_permission() -> void:
	var svc := _svc()
	var gold := svc.load_or_create(2).gold
	var r := svc.set_admin(2, true, false)
	T.ok(not r.ok and r.err == "sem_permissao", "recusado sem permissão")
	T.eq(int(r.state.gold), gold, "nada mudou")


func test_service_refills_after_each_op() -> void:
	var svc := _svc()
	svc.load_or_create(2).equipment.weapon = "azure_edge"   # o personagem novo começa sem arma
	T.ok(svc.set_admin(2, true, true).ok, "ligou")
	var r := svc.apply(2, "buy", ["health_potion", 5])
	T.ok(r.ok, "comprou: %s" % r.err)
	T.eq(int(r.state.gold), AdminRules.GOLD, "ouro cheio de novo")
	r = svc.apply(2, "enchant", ["gelo"])
	T.ok(r.ok, "encantou: %s" % r.err)
	T.eq(int(r.state.ecos), AdminRules.ECOS, "Ecos cheios de novo")
	T.ok(r.state.flags.get("admin") is Dictionary, "flag no estado do cliente")
	r = svc.set_admin(2, false, true)
	T.ok(r.ok and not r.state.flags.has("admin"), "desligou")
