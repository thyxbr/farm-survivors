extends RefCounted
## BalanceTables: os JSON em data/balance têm que devolver exatamente o que as antigas `const` tinham.

const DIR := "res://data/balance"
const SNAPSHOT := "res://tests/unit/fixtures/balance_snapshot.res"


func _snapshot() -> Dictionary:
	var f := FileAccess.open(SNAPSHOT, FileAccess.READ)
	var snap = bytes_to_var(f.get_buffer(f.get_length()))
	f.close()
	return snap


func test_roundtrip_matches_consts() -> void:
	var t := BalanceTables.load_dir(DIR)
	var snap := _snapshot()
	T.eq(snap.size(), BalanceTables.NAMES.size(), "snapshot tem todas as tabelas")
	for n in snap:
		T.ok(not t.get_table(n).is_empty(), "tabela %s carregou" % n)
		# o snapshot tem 40.0 onde o JSON devolve 40 (decode troca float inteiro por int), então
		# normaliza o snapshot com a mesma regra antes do == profundo (que distingue int de float)
		T.ok(t.get_table(n) == BalanceTables.decode(snap[n]), "tabela %s igual ao snapshot das const" % n)


func test_ints_stay_int() -> void:
	var t := BalanceTables.load_dir(DIR)
	T.eq(typeof(t.get_table("items")["health_potion"].price), TYPE_INT, "price é int")
	T.eq(typeof(t.get_table("rules")["xp_curve"]["base"]), TYPE_INT, "base da curva é int")
	T.eq(typeof(t.get_table("rules")["sell_ratio"]), TYPE_FLOAT, "0.5 continua float")


func test_color_and_vector() -> void:
	var t := BalanceTables.load_dir(DIR)
	T.eq(typeof(t.get_table("items")["wooden_sword"].color), TYPE_COLOR, "cor do item")
	T.eq(t.get_table("enemies")["slime"].color, Color(0.3, 0.9, 0.35), "cor do slime")
	T.eq(typeof(t.get_table("colony")["buildings"]["house"].size), TYPE_VECTOR2, "pegada da casa")
	T.eq(BalanceTables.decode({"$v3": [1, 2.5, 3]}), Vector3(1, 2.5, 3), "decode Vector3")
	T.eq(BalanceTables.decode(BalanceTables.encode(Color(0.1, 0.2, 0.3, 0.4))), Color(0.1, 0.2, 0.3, 0.4), "Color ida e volta")


func test_from_dict_and_set_table() -> void:
	var t := BalanceTables.from_dict({"items": {"x": {"price": 3}}})
	T.eq(t.get_table("items")["x"].price, 3, "from_dict")
	T.eq(t.get_table("nada"), {}, "tabela inexistente é vazia")
	t.set_table("items", {"y": 1})
	T.eq(t.to_dict()["items"], {"y": 1}, "set_table/to_dict")
