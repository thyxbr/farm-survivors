extends RefCounted
## Dados da ficha de classe (classes.json) e o emblema desenhado (ClassEmblem) da tela de criação.

const PROFILE_KEYS := ["alcance", "dano", "mobilidade", "resistencia", "suporte"]


func test_every_class_has_card_data() -> void:
	var table: Dictionary = BalanceTables.load_dir("res://data/balance").get_table("classes")
	for id in CharRules.CLASS_IDS:
		var d: Dictionary = table.get(id, {})
		T.ok(str(d.get("emblem", "")) in ClassEmblem.KINDS, "%s: emblema conhecido" % id)
		for k in ["lore", "role", "style"]:
			T.ok(str(d.get(k, "")) != "", "%s: campo %s preenchido" % [id, k])
		var diff := int(d.get("difficulty", 0))
		T.ok(diff >= 1 and diff <= 3, "%s: dificuldade 1..3 (%d)" % [id, diff])
		var prof: Dictionary = d.get("profile", {})
		var keys := prof.keys()
		keys.sort()
		T.eq(keys, PROFILE_KEYS, "%s: perfil com as 5 barras" % id)
		for k in prof:
			var v = prof[k]
			T.ok(int(v) == v and int(v) >= 0 and int(v) <= 5, "%s: %s entre 0 e 5 (%s)" % [id, k, v])


func test_for_class_tolerates_missing_fields() -> void:
	var e := ClassEmblem.for_class({}, 46)
	T.eq(e.kind, "", "sem campo emblem: só o escudo")
	T.eq(e.custom_minimum_size, Vector2(46, 46), "tamanho pedido")
	e.free()
