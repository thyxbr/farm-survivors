class_name ColonyNature
extends Node3D
## Os nós de recurso do mapa da Defesa da Cidade, gerados da semente numa ordem fixa
## (o id de cada nó é o índice na geração, igual no servidor e nos clientes).
## Guarda os esgotados com o dia em que voltam, cuida da volta ao amanhecer, do save e da rede.
##
## Anéis (distância do centro, ColonyData.RINGS): no 1 ficam as árvores e pedras de sempre;
## no 2, veios de ferro e de ouro e arbustos de frutas; no 3, cristais arcanos.

const NODE := preload("res://scripts/colony/resource_node.gd")
## Um golpe só tira um pedaço do mesmo nó a cada HIT_COOLDOWN segundos.
const HIT_COOLDOWN := 0.25
const CLEARING := 52.0   # raio da clareira central (onde começa o anel 1)
const DECOR_ROCK := preload("res://assets/models/rock.glb")

var colony: Colony
var nodes: Array[ColonyResourceNode] = []
## id -> dia em que o nó volta (servidor/solo). No cliente o dia é -1 (quem decide é o servidor).
var depleted := {}
var _last_hit := {}


## Monta o mapa a partir do rng com semente. A ordem dos bosques, das árvores e pedras soltas e das
## pedras decorativas é a de sempre (mesmos lugares de antes para a mesma semente); os tipos novos vêm depois.
func generate(rng: RandomNumberGenerator, c: Colony) -> void:
	colony = c
	var half := ColonyData.MAP_HALF
	# bosques: aglomerados de árvores longe da clareira, com campos abertos entre eles (onde ficam os animais)
	for g in 26:
		var a := rng.randf() * TAU
		var d := rng.randf_range(CLEARING + 6.0, half - 14.0)
		var cen := Vector3(cos(a) * d, 0, sin(a) * d)
		cen.x = clampf(cen.x, -half + 10, half - 10)
		cen.z = clampf(cen.z, -half + 10, half - 10)
		var n := rng.randi_range(5, 11)
		for i in n:
			var p := cen + Vector3(rng.randf_range(-9, 9), 0, rng.randf_range(-9, 9))
			if Vector2(p.x, p.z).length() < CLEARING:
				continue
			var r := rng.randf()
			if r < 0.4:
				_add("tree", "tree_pine", p, rng.randf() * TAU, rng.randf_range(0.9, 1.5), 0.35)
			elif r < 0.55:
				_add("tree", "tree_fir", p, rng.randf() * TAU, rng.randf_range(0.9, 1.4), 0.32)
			elif r < 0.68:
				_add("tree", "tree_birch", p, rng.randf() * TAU, rng.randf_range(0.9, 1.3), 0.25)
			elif r < 0.78:
				_add("tree", "tree_maple", p, rng.randf() * TAU, rng.randf_range(0.9, 1.2), 0.4)
			else:
				_add("tree", "tree_oak", p, rng.randf() * TAU, rng.randf_range(0.9, 1.3), 0.4)
	# árvores e pedras soltas
	var placed := 0
	var tries := 0
	while placed < 70 and tries < 2000:
		tries += 1
		var p := Vector3(rng.randf_range(-half + 8, half - 8), 0, rng.randf_range(-half + 8, half - 8))
		if Vector2(p.x, p.z).length() < CLEARING - 4.0:
			continue
		if rng.randf() < 0.55:
			_add("rock", "rock", p, rng.randf() * TAU, rng.randf_range(0.6, 1.5), 0.65)
		else:
			_add("tree", "tree_oak", p, rng.randf() * TAU, rng.randf_range(0.8, 1.2), 0.4)
		placed += 1
	# algumas pedras decorativas na clareira (enfeite, não são nós de recurso)
	for i in 8:
		var a := rng.randf() * TAU
		var p := Vector3(cos(a), 0, sin(a)) * rng.randf_range(34.0, 48.0)
		_decor_rock(p, rng.randf() * TAU, rng.randf_range(0.4, 0.7), 0.6)
	# anéis de fora: ferro, ouro e frutas no anel 2; cristais no anel 3
	var rings: Array = ColonyData.RINGS
	_scatter(rng, "iron", "rock", 7, rings[1] + 2.0, rings[2] - 2.0, 0.9, 1.3, 0.65)
	_scatter(rng, "gold", "rock", 4, rings[1] + 2.0, rings[2] - 2.0, 0.9, 1.3, 0.65)
	_scatter(rng, "berry", "bush_berry", 10, rings[1] + 2.0, rings[2] - 2.0, 0.9, 1.2, 0.5)
	_scatter(rng, "crystal", "", 6, rings[2] + 2.0, half - 10.0, 1.0, 1.25, 0.6)


func node(id: int) -> ColonyResourceNode:
	return nodes[id] if id >= 0 and id < nodes.size() else null


## Quantos nós desse tipo existem (vivos ou não).
func count(kind: String) -> int:
	var n := 0
	for r in nodes:
		if r.kind == kind:
			n += 1
	return n


## Ids dos nós vivos desse tipo a até r metros de p (no plano).
func alive_near(kind: String, p: Vector3, r: float) -> Array[int]:
	var out: Array[int] = []
	for n in nodes:
		if n.alive and n.kind == kind and _flat(n.global_position, p) <= r:
			out.append(n.id)
	return out


## O nó vivo desse tipo mais próximo de p (null se não houver).
func nearest(kind: String, p: Vector3) -> ColonyResourceNode:
	var best: ColonyResourceNode = null
	var bd := INF
	for n in nodes:
		if n.alive and n.kind == kind:
			var d := _flat(n.global_position, p)
			if d < bd:
				bd = d
				best = n
	return best


## Cria um nó rico (mais recurso que o normal) e devolve o id, acima dos gerados pela semente.
func add_rich(kind: String, pos: Vector3, total: int) -> int:
	var model := "rock"
	match kind:
		"tree":
			model = "tree_oak"
		"berry":
			model = "bush_berry"
	var n := _add(kind, model, pos, 0.0, 1.4, 0.65)
	n.total = total
	return n.id


## Golpe aceito? (no máximo um pedaço por nó a cada HIT_COOLDOWN)
func take_hit(id: int) -> bool:
	var now := Time.get_ticks_msec()
	if now - int(_last_hit.get(id, -100000)) < int(HIT_COOLDOWN * 1000.0):
		return false
	_last_hit[id] = now
	return true


## Servidor/solo: o nó esgotou; volta depois de REGROW_DAYS dias.
func deplete(id: int, day: int) -> void:
	var n := node(id)
	if n == null or not n.alive:
		return
	n.set_alive(false)
	depleted[id] = day + int(ColonyData.REGROW_DAYS.get(n.kind, 2))
	if colony.role == "server":
		Lobby.city_node_state(id, false)


## Servidor/solo (amanhecer): devolve os nós cujo dia chegou. Se houver construção em cima,
## o nó espera e tenta de novo no próximo amanhecer.
func regrow(day: int) -> void:
	if colony == null or colony.role == "client":
		return
	for id in depleted.keys():
		if day < int(depleted[id]):
			continue
		var n := node(id)
		if n == null:
			depleted.erase(id)
			continue
		if colony.building_at(Vector2(n.global_position.x, n.global_position.z), n.radius + 0.3):
			continue
		depleted.erase(id)
		n.set_alive(true)
		if colony.role == "server":
			Lobby.city_node_state(id, true)


## Cliente: o servidor avisou que o nó esgotou ou voltou.
func net_set(id: int, alive: bool, fx := true) -> void:
	var n := node(id)
	if n == null:
		return
	if alive:
		depleted.erase(id)
	else:
		depleted[id] = -1
	n.set_alive(alive, fx)


## Save: {id: dia em que volta} dos nós esgotados.
func to_dict() -> Dictionary:
	var d := {}
	for id in depleted:
		d[str(id)] = int(depleted[id])
	return d


func from_dict(d: Dictionary) -> void:
	for k in d:
		var id := int(k)
		var n := node(id)
		if n == null:
			continue
		n.set_alive(false, false)
		depleted[id] = int(d[k])


# ================================================================ geração
func _add(kind: String, model: String, pos: Vector3, yaw: float, s: float, radius: float) -> ColonyResourceNode:
	var n: ColonyResourceNode = NODE.new()
	n.id = nodes.size()
	n.kind = kind
	n.model = model
	n.yaw = yaw
	n.size = s
	n.radius = radius * s
	n.nature = self
	n.position = pos
	nodes.append(n)
	add_child(n)
	colony.obstacles.append(n.obstacle)
	return n


## Espalha `count` nós entre os raios lo e hi, longe dos obstáculos que já existem.
func _scatter(rng: RandomNumberGenerator, kind: String, model: String, count: int, lo: float, hi: float,
		smin: float, smax: float, radius: float) -> void:
	var lim := ColonyData.MAP_HALF - 8.0
	for i in count:
		var p := Vector3.ZERO
		for t in 200:
			var a := rng.randf() * TAU
			p = Vector3(cos(a), 0, sin(a)) * rng.randf_range(lo, hi)
			if absf(p.x) <= lim and absf(p.z) <= lim and _clear(p, radius * smax + 1.5):
				break
		_add(kind, model, p, rng.randf() * TAU, rng.randf_range(smin, smax), radius)


func _clear(p: Vector3, r: float) -> bool:
	for o in colony.obstacles:
		if Vector2(p.x, p.z).distance_to(o[0]) < float(o[1]) + r:
			return false
	return true


func _decor_rock(pos: Vector3, yaw: float, s: float, radius: float) -> void:
	if DisplayServer.get_name() != "headless":
		var inst: Node3D = DECOR_ROCK.instantiate()
		inst.position = pos
		inst.rotation.y = yaw
		inst.scale = Vector3.ONE * s
		add_child(inst)
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = radius * s
	c.height = 3.0
	cs.shape = c
	cs.position.y = 1.5
	body.add_child(cs)
	add_child(body)
	colony.obstacles.append([Vector2(pos.x, pos.z), radius * s + 0.3])


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
