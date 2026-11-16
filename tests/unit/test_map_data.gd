extends RefCounted
## MapData e EnemySpawn.spread: leitura pura das cenas de mapa (landmarks, nós de coleta, tipos de monstro) e a
## regra que espalha os monstros de um ponto no raio dele.

const FIXTURE := "res://tests/unit/fixtures/map_fixture.tscn"


func _with_fixture() -> void:
	MapData.scene_override = {"vila": FIXTURE}
	MapData.clear_cache()


func _done() -> void:
	MapData.scene_override = {}
	MapData.clear_cache()


func test_spread_single_and_empty() -> void:
	var c := Vector3(1, 0, 2)
	T.eq(EnemySpawn.spread(c, 1, 5.0), [c] as Array[Vector3], "um monstro fica no centro")
	T.eq(EnemySpawn.spread(c, 0, 5.0).size(), 0, "count 0 não gera ninguém")
	var flat := EnemySpawn.spread(c, 4, 0.0)
	T.eq(flat.size(), 4, "raio 0 ainda gera todos")
	for p in flat:
		T.eq(p, c, "raio 0: todos no centro")


func test_spread_inside_radius_and_stable() -> void:
	var c := Vector3(10, 0, -3)
	var a := EnemySpawn.spread(c, 6, 4.0)
	T.eq(a.size(), 6, "6 pontos")
	for p in a:
		T.ok(p.distance_to(c) <= 4.0 + 0.001, "ponto %s dentro do raio" % str(p))
		T.eq(p.y, c.y, "mesma altura do centro")
	for i in a.size():
		for j in range(i + 1, a.size()):
			T.ok(a[i].distance_to(a[j]) >= 1.0, "pontos %d e %d a pelo menos 1 m" % [i, j])
	T.eq(EnemySpawn.spread(c, 6, 4.0), a, "mesma conta, mesmo resultado (servidor e testes)")


func test_landmark_and_resource_nodes() -> void:
	_with_fixture()
	T.eq(MapData.landmark("vila", "camp"), Vector3(62, 0, 0), "landmark do acampamento")
	T.eq(MapData.landmark("vila", "nao_existe"), Vector3.ZERO, "landmark ausente devolve zero")
	var nodes := MapData.resource_nodes()
	T.eq(nodes.get(3), {"kind": "iron", "pos": Vector3(5, 0, 7)}, "nó de coleta 3 lido da cena")
	T.ok(not nodes.has(0), "só os nós que existem na cena")
	_done()


func test_landmark_in_region_uses_origin() -> void:
	MapData.scene_override = {"bosque": FIXTURE}
	MapData.clear_cache()
	T.eq(MapData.landmark("bosque", "camp"), Regions.origin("bosque") + Vector3(62, 0, 0),
		"landmark de região soma a origem do mapa")
	_done()


func test_enemy_kinds() -> void:
	var kinds := MapData.enemy_kinds()
	for k in ["slime", "goblin", "lich"]:
		T.ok(k in kinds, "tipo %s vem do enemies.json" % k)


## Lugares e veios com follow_ground ficam no relevo também nas leituras sem o mundo (viagem, coleta no
## servidor), igual ao editor e ao jogo.
func test_reads_follow_the_relief() -> void:
	MapData.scene_override = {"mina": "res://tests/unit/fixtures/map_hill_fixture.tscn",
		"vila": "res://tests/unit/fixtures/map_root_fixture.tscn", "bosque": "res://tests/unit/fixtures/map_root_fixture.tscn",
		"pico": "res://tests/unit/fixtures/map_root_fixture.tscn", "arena": "res://tests/unit/fixtures/map_root_fixture.tscn"}
	MapData.clear_cache()
	var o := Regions.origin("mina")
	var arrive := MapData.landmark("mina", "arrive")
	T.ok(arrive.y > 5.0, "chegada no alto do morro, não dentro dele (y %.2f)" % arrive.y)
	T.eq(MapData.landmark("mina", "fixo"), o + Vector3(1, 0.3, 1), "sem follow_ground: altura da cena")
	var vein: Dictionary = MapData.resource_nodes().get(5, {})
	T.ok(not vein.is_empty() and vein.pos.y > 5.0, "veio no alto do morro (%s)" % str(vein.get("pos")))
	T.ok(not vein.is_empty() and is_equal_approx(vein.pos.y, arrive.y - 0.3), "veio e chegada no mesmo chão")
	MapData.scene_override = {}
	MapData.clear_cache()


## Monstros de um ponto com raio nascem cada um no chão do lugar onde caem (encosta), não na altura do centro.
func test_spread_on_ground() -> void:
	var slope := func(x: float, _z: float) -> float: return x * 0.5
	var pts := EnemySpawn.spread_on_ground(Vector3(0, 0, 0), 5, 8.0, 0.0, slope)
	T.eq(pts.size(), 5, "5 pontos")
	for p in pts:
		T.ok(is_equal_approx(p.y, p.x * 0.5), "ponto %s no chão da encosta" % str(p))
	var flat := EnemySpawn.spread_on_ground(Vector3(2, 0, 3), 3, 4.0, 0.2, Callable())
	for p in flat:
		T.ok(is_equal_approx(p.y, 0.2), "sem chão: fica na distância salva")
