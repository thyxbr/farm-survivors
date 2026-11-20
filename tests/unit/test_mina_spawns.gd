extends RefCounted
## A Geleira de Cristal (scenes/maps/mina.tscn): cada monstro novo na sua região, os esqueletos só no corredor norte
## e no Salão (a linha de história do Bolgar), a Mãe-Verme no fosso oeste e só o bando de Brutos do contrato.
## Lê o .tscn como texto (o mapa tem scripts @tool que precisam dos autoloads).

const MAP := "res://scenes/maps/mina.tscn"


## [{kind, x, z, count}] dos pontos de nascimento sob "Monstros".
func _spawns() -> Array:
	var text := FileAccess.get_file_as_string(MAP)
	var out := []
	for block in text.split("\n[node "):
		if not block.contains("parent=\"Monstros\""):
			continue
		var kind := ""
		var x := 0.0
		var z := 0.0
		var count := 1
		for line in block.split("\n"):
			if line.begins_with("kind = "):
				kind = line.get_slice("\"", 1)
			elif line.begins_with("count = "):
				count = int(line.get_slice("= ", 1))
			elif line.begins_with("transform = Transform3D("):
				var nums := line.get_slice("(", 1).get_slice(")", 0).split(",")
				x = float(nums[9])
				z = float(nums[11])
		if kind != "":
			out.append({"kind": kind, "x": x, "z": z, "count": count})
	return out


func test_new_monsters_have_points() -> void:
	var s := _spawns()
	for kind in ["kobold", "centopeia", "golem_cristal", "toupeira"]:
		T.ok(s.filter(func(p: Dictionary) -> bool: return p.kind == kind).size() >= 2, "%s tem pelo menos 2 pontos" % kind)


func test_one_worm_in_west_pit() -> void:
	var w := _spawns().filter(func(p: Dictionary) -> bool: return p.kind == "mae_verme")
	T.eq(w.size(), 1, "uma Mãe-Verme")
	if w.size() == 1:
		T.ok(w[0].x < -35.0 and absf(w[0].z + 40.0) < 6.0 and w[0].count == 1, "no fosso oeste, sozinha")


func test_skeletons_only_north() -> void:
	var out_of_place := []
	var corridor := 0
	for p in _spawns():
		if not str(p.kind).begins_with("esqueleto"):
			continue
		if p.z > -18.0:
			out_of_place.append("%s em z=%.0f" % [p.kind, p.z])
		if p.z <= -18.0 and p.z >= -37.0 and absf(p.x) <= 25.0 and p.kind != "esqueleto_cavaleiro":
			corridor += int(p.count)
	T.eq(out_of_place, [], "esqueletos só no corredor norte e no Salão")
	T.ok(corridor >= 8, "corredor norte com esqueletos para a quest de 8 abates (%d)" % corridor)


func test_brutes_only_by_the_contract_marker() -> void:
	var b := _spawns().filter(func(p: Dictionary) -> bool: return p.kind == "goblin_bruto")
	T.eq(b.size(), 1, "um ponto de Goblin Bruto")
	if b.size() == 1:
		T.ok(absf(b[0].x - 30.0) < 6.0 and absf(b[0].z) < 6.0 and b[0].count >= 3,
			"bando perto do marcador do contrato Brutamontes (x 30, z 0)")
