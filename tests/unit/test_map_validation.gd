extends RefCounted
## Validação das cenas de mapa (MapValidation): o que o editor deixa fazer mas o jogo não aceita. Rode depois
## de mexer num mapa no editor. Cada problema vem com o caminho do nó.

const BROKEN := "res://tests/unit/fixtures/map_broken_fixture.tscn"


func _root(path: String) -> MapRoot:
	return (load(path) as PackedScene).instantiate() as MapRoot


func test_real_maps_are_valid() -> void:
	var roots: Array = []
	for id in MapData.SCENES:
		var r := _root(MapData.SCENES[id])
		roots.append(r)
		var problems := MapValidation.check(r)
		for p in problems:
			T.ok(false, "%s: %s" % [id, p])
		T.eq(problems.size(), 0, "mapa %s sem problemas" % id)
	var shared := MapValidation.check_all(roots)
	for p in shared:
		T.ok(false, p)
	T.eq(shared.size(), 0, "nós de coleta com número único entre os mapas")
	for r in roots:
		r.free()


func test_broken_map_is_reported() -> void:
	var r := _root(BROKEN)
	var problems := MapValidation.check(r)
	var text := "\n".join(problems)
	T.ok("dragao_imaginario" in text, "tipo de monstro que não existe")
	T.ok("respawn" in text, "tempo de volta zero")
	T.ok("formas pintadas" in text, "mais de 64 formas pintadas no chão")
	T.ok("MoradorSemCaminho" in text and "pontos de caminho" in text, "morador que passeia sem caminho")
	T.ok("'merchant'" in text, "vale sem a Mira")
	T.ok("landmark" in text and "camp" in text, "landmark obrigatório faltando")
	T.ok("fora do mapa" in text, "peça fora do mapa")
	T.ok("adamantio" in text, "veio de tipo que não existe")
	T.ok("terra_do_nunca" in text, "região que não existe no regions.json")
	T.ok("tamanho da região" in text, "região de raio 0")
	T.ok("half" in text, "meia largura diferente da do Regions (o minimapa e as regiões usam a do Regions)")
	var twice := MapValidation.check_all([r, _root(BROKEN)])
	T.ok(twice.size() > 0 and "node_id 7" in "\n".join(twice), "o mesmo node_id em dois lugares")
	r.free()
