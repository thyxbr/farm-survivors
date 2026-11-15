extends RefCounted
## MapSummary.compare: o retrato do mundo antes e depois da conversão para cenas tem que bater. Cada linha é
## "chave;n1;n2;..." (a chave diz o que é; os números, onde está). Números iguais dentro da tolerância contam
## como iguais; a ordem das linhas não importa.


func test_same_content_any_order() -> void:
	var a := PackedStringArray(["prop|rock;1.00;0.00;2.00", "prop|rock;5.00;0.00;5.00", "light|night;0;3;0"])
	var b := PackedStringArray(["light|night;0;3;0", "prop|rock;5.00;0.00;5.00", "prop|rock;1.00;0.00;2.00"])
	T.eq(MapSummary.compare(a, b), PackedStringArray(), "mesmas linhas em outra ordem")


func test_tolerance() -> void:
	var a := PackedStringArray(["prop|rock;1.000;0.000;2.000"])
	T.eq(MapSummary.compare(a, PackedStringArray(["prop|rock;1.009;0.000;1.995"])), PackedStringArray(),
		"diferença menor que 1 cm passa")
	T.eq(MapSummary.compare(a, PackedStringArray(["prop|rock;1.050;0.000;2.000"])).size(), 2,
		"5 cm de diferença: uma falta e uma sobra")


func test_missing_and_extra() -> void:
	var a := PackedStringArray(["prop|rock;1;0;2", "prop|fence;0;0;0"])
	var b := PackedStringArray(["prop|rock;1;0;2", "prop|crate;0;0;0"])
	var d := MapSummary.compare(a, b)
	T.ok("falta: prop|fence;0;0;0" in d, "cerca sumiu")
	T.ok("sobra: prop|crate;0;0;0" in d, "caixote apareceu")
	T.eq(d.size(), 2, "só as duas diferenças")


func test_duplicates_count() -> void:
	var a := PackedStringArray(["prop|rock;1;0;2", "prop|rock;1;0;2"])
	var b := PackedStringArray(["prop|rock;1;0;2"])
	T.eq(MapSummary.compare(a, b), PackedStringArray(["falta: prop|rock;1;0;2"]), "duas pedras viraram uma")
