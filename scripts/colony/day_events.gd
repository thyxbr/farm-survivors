class_name ColonyEvents
extends Node
## Eventos aleatórios do dia da Defesa da Cidade (ColonyData.DAY_EVENTS): no amanhecer, a partir do dia
## EVENT_MIN_DAY, há EVENT_CHANCE de sair um. O servidor (ou o solo) sorteia, põe o que o evento precisa no
## mapa, anuncia com a direção e avisa os clientes (Lobby.city_event). O evento acaba quando é resolvido
## (complete) ou ao anoitecer (end), que também tira os monstros e bichos que ele trouxe.
##
## No cliente só existem o tipo, o ponto e os figurantes (caravana, aldeões, baú: ColonyEventProp), para o
## marcador do HUD e para interagir; trocar e resgatar viram pedidos ao servidor ("trade", "event_interact").
## Não vai no save: um evento dura só até o anoitecer.

const PROP := preload("res://scripts/colony/caravan.gd")
const ANIMAL := preload("res://scripts/colony/animal.gd")

var colony: Colony
## Evento em andamento ("" = nenhum) e o ponto dele no mapa (o marcador do HUD aponta para lá).
var active := ""
var pos := Vector3.ZERO
## Chance de sair um evento no amanhecer (o teste da cidade zera para o sorteio não mexer nos nós e no mapa).
var chance := ColonyData.EVENT_CHANCE
## Evento que sai no próximo amanhecer possível, uma vez só (servidor com --city-event=TIPO: gancho do net_test).
var force_next := ""
var _props: Array[Node3D] = []
var _enemies: Array[Enemy] = []
var _animals: Array[ColonyAnimal] = []


## Servidor/solo, no amanhecer: sorteia e começa o evento do dia. `force` escolhe o tipo (pula a chance e o
## dia mínimo dele, não a condição `needs`): gancho dos testes. Devolve o tipo, ou "" se nada aconteceu.
func roll(day: int, force := "") -> String:
	if colony == null or colony.role == "client":
		return ""
	end()   # nada do dia anterior fica para trás
	if day < ColonyData.EVENT_MIN_DAY:
		return ""
	var kind := force
	if kind == "" and force_next != "":
		kind = force_next
		force_next = ""
	if kind == "":
		if randf() >= chance:
			return ""
		kind = _pick(day)
	if not ColonyData.DAY_EVENTS.has(kind) or not _possible(kind):
		return ""
	var camp := _far_camp() if kind == "camp_raid" else null
	var at := camp.global_position if camp else _point(ColonyData.DAY_EVENTS[kind].rings)
	if at == Vector3.INF:
		return ""
	at.y = 0.0
	pos = at
	active = kind
	match kind:
		"caravan":
			_make_props(kind, pos)
		"lost_villagers":
			_make_props(kind, pos)
			var pack: Array = ColonyData.ANIMALS.wolf.pack
			for i in randi_range(int(pack[0]), int(pack[1])):
				var a := TAU * i / 4.0 + randf() * 0.5
				_spawn_animal("wolf", pos + Vector3(cos(a), 0, sin(a)) * randf_range(4.5, 6.5), false)
		"meteor":
			_meteor_fx(pos)
			for i in ColonyData.EVENT_METEOR_NODES:
				var a := TAU * i / ColonyData.EVENT_METEOR_NODES + randf() * 0.6
				var p := pos + Vector3(cos(a), 0, sin(a)) * randf_range(2.5, 4.0)
				var nid := colony.nature.add_rich("crystal", p, ColonyData.EVENT_METEOR_TOTAL)
				if colony.role == "server":
					Lobby.city_rich_node(nid, "crystal", p.x, p.z, ColonyData.EVENT_METEOR_TOTAL)
			for i in ColonyData.EVENT_METEOR_SLIMES:
				_spawn_enemy("slime", _around(pos, 5.0, 9.0), false)
		"alpha":
			_spawn_animal("bear" if randf() < 0.5 else "boar", pos, true)
		"camp_raid":
			var out := pos - _center()
			out.y = 0.0
			out = out.normalized() if out.length() > 0.1 else Vector3.FORWARD
			var from := pos + out * ColonyData.EVENT_RAID_DIST
			for i in 3 + day / 3:
				var e := _spawn_enemy("goblin" if randf() < 0.6 else "slime", _around(from, 0.0, 4.0), true)
				e._siege_target = camp
				e._lock_t = 9999.0   # vai até a serraria/pedreira; se ela cair, segue para a cidade
		"lost_chest":
			_make_props(kind, pos)
			for i in ColonyData.EVENT_CHEST_GUARDS:
				_spawn_enemy("goblin" if randf() < 0.5 else "slime", _around(pos, 3.0, 5.0), false)
	var msg := str(ColonyData.DAY_EVENTS[kind].msg).format({"dir": dir_name(pos),
		"camp": str(camp.data.name) if camp else ""})
	colony.say(msg, Color(1, 0.85, 0.45))
	Sfx.play("quest", 0.0, -4.0)
	if colony.role == "server":
		Lobby.city_event(kind, pos.x, pos.z, true)
	colony._dirty()
	return kind


## Servidor/solo, ao anoitecer: o evento acaba e tudo o que ele trouxe some (figurantes, monstros, bichos).
func end() -> void:
	for e in _enemies:
		if is_instance_valid(e) and not e.dead and not e.is_queued_for_deletion():
			if e.died.is_connected(_on_enemy_died):
				e.died.disconnect(_on_enemy_died)
			if colony.role == "server":
				Network.server_enemy_despawn(e)
			e.queue_free()
	_enemies.clear()
	for a in _animals:
		if is_instance_valid(a) and not a.dead and not a.is_queued_for_deletion():
			a.remove_from_group("animals")
			a.remove_from_group("enemies")
			if colony.role == "server":
				colony.amap.erase(a.net_id)
				Lobby.city_animal_removed(a, false)
			a.queue_free()
	_animals.clear()
	_finish()


## O evento foi resolvido (aldeões resgatados, baú aberto, fera abatida, ataque repelido): os figurantes
## saem e o marcador some. Monstros que sobraram continuam até o anoitecer.
func complete(kind: String) -> void:
	if active == kind:
		_finish()


## Meteoro resolvido: os slimes caíram e os cristais dele foram todos colhidos (os nós ricos criados
## pelo evento ficam acima de `nature.generated`). Chamado ao morrer um monstro e ao esgotar um nó.
func check_meteor() -> void:
	if active != "meteor" or colony == null or colony.role == "client" or colony.nature == null:
		return
	if not enemies().is_empty():
		return
	for i in range(colony.nature.generated, colony.nature.nodes.size()):
		var n: ColonyResourceNode = colony.nature.nodes[i]
		if n.kind == "crystal" and n.alive and Vector2(n.global_position.x - pos.x, n.global_position.z - pos.z).length() < 8.0:
			return
	colony.say("O meteoro foi esgotado: cristais colhidos e slimes abatidos.", Color(0.7, 0.85, 1.0))
	complete("meteor")


## Servidor/solo: um jogador interagiu com os aldeões ou com o baú. "" ou o motivo da recusa.
func interact(pid: int) -> String:
	if active not in ["lost_villagers", "lost_chest"]:
		return "Não há nada para fazer aqui."
	var far := reach_error(pid)
	if far != "":
		return far
	if active == "lost_villagers":
		if not animals().is_empty():
			return "Os lobos ainda cercam os aldeões!"
		var found := 2 + colony.day / 4
		var n := mini(maxi(0, colony.pop_cap() - colony.citizens), found)
		colony.citizens += n
		colony.food += ColonyData.EVENT_FOOD_PER_VILLAGER * (found - n)
		if n == found:
			colony.say("Os aldeões perdidos chegaram à cidade: +%d aldeões." % n, Color(0.8, 1.0, 0.7))
		else:
			colony.say("Os aldeões perdidos chegaram: +%d aldeões; sem moradia para %d, eles deixaram +%d comida." %
				[n, found - n, ColonyData.EVENT_FOOD_PER_VILLAGER * (found - n)], Color(0.8, 1.0, 0.7))
		Sfx.play("quest", 0.0, -4.0)
		colony._res_changed()
		complete("lost_villagers")
	else:
		if not enemies().is_empty():
			return "Os monstros ainda guardam o baú!"
		var loot := {"gold": 40 + 10 * colony.day, "wood": 60, "stone": 40}
		colony.gain(loot, pos + Vector3.UP * 1.5)
		colony.say("Baú esquecido aberto: %s para a cidade." % ColonyData.cost_text(loot), Color(1, 0.85, 0.35))
		Sfx.play("coin", 0.1, -2.0)
		complete("lost_chest")
	return ""


## Servidor: "" se o jogador `pid` está perto do evento; no solo (pid 0) sempre "".
func reach_error(pid: int) -> String:
	if colony.role != "server" or pid == 0:
		return ""
	var p = Network.remote_players.get(pid)
	if p == null or not is_instance_valid(p) or Vector2(p.global_position.x - pos.x, p.global_position.z - pos.z).length() > ColonyData.EVENT_REACH:
		return "Chegue mais perto."
	return ""


## Bichos do evento ainda vivos (lobos dos aldeões, a fera alfa).
func animals() -> Array[ColonyAnimal]:
	var out: Array[ColonyAnimal] = []
	for a in _animals:
		if is_instance_valid(a) and not a.dead:
			out.append(a)
	return out


## Servidor/solo: um bicho foi caçado (Colony.on_animal_killed).
func on_animal_killed(a: ColonyAnimal) -> void:
	if a not in _animals:
		return
	if active == "alpha" and a.alpha:
		complete("alpha")
	elif active == "lost_villagers" and animals().is_empty():
		colony.say("Os lobos caíram! Fale com os aldeões para trazê-los à cidade.", Color(0.8, 1.0, 0.7))


## Monstros do evento ainda vivos (guardas do baú, slimes do meteoro, o ataque à serraria).
func enemies() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for e in _enemies:
		if is_instance_valid(e) and not e.dead and not e.is_queued_for_deletion():
			out.append(e)
	return out


## "Nordeste" etc.: direção de `p` vista da prefeitura (0 = norte, -Z, sentido horário).
func dir_name(p: Vector3) -> String:
	var d := p - _center()
	var i := posmod(roundi((atan2(d.z, d.x) + PI / 2.0) / (TAU / 8.0)), 8)
	return Colony.DIR_NAMES[i]


## Cliente: o servidor começou (is_active) ou terminou um evento. fx = false no estado inicial de quem entra.
func net_event(kind: String, x: float, z: float, is_active: bool, fx := true) -> void:
	if not ColonyData.DAY_EVENTS.has(kind):
		return
	if is_active:
		_clear_props()
		active = kind
		pos = Vector3(x, 0, z)
		_make_props(kind, pos)
		if kind == "meteor" and fx:
			_meteor_fx(pos)
	elif active == kind:
		_clear_props()
		active = ""


## Servidor: o evento para quem entra depois ([tipo, x, z], ou [] sem evento).
func net_list() -> Array:
	return [active, pos.x, pos.z] if active != "" else []


# ================================================================ interno
func _finish() -> void:
	_clear_props()
	var was := active
	active = ""
	if was != "" and colony.role == "server":
		Lobby.city_event(was, pos.x, pos.z, false)
	if was != "":
		colony._dirty()


func _pick(day: int) -> String:
	var pool: Array[String] = []
	var total := 0.0
	for k in ColonyData.DAY_EVENTS:
		if day >= int(ColonyData.DAY_EVENTS[k].min_day) and _possible(k):
			pool.append(k)
			total += float(ColonyData.DAY_EVENTS[k].weight)
	var r := randf() * total
	for k in pool:
		r -= float(ColonyData.DAY_EVENTS[k].weight)
		if r < 0.0:
			return k
	return "" if pool.is_empty() else pool.back()


func _possible(kind: String) -> bool:
	match str(ColonyData.DAY_EVENTS[kind].needs):
		"camp_out":
			return _far_camp() != null
	return true


## A serraria ou pedreira mais distante da prefeitura, se estiver fora do raio da cidade.
func _far_camp() -> ColonyBuilding:
	var best: ColonyBuilding = null
	var best_d := ColonyData.CITY_RADIUS
	var c := _center()
	for b in colony.buildings():
		if b.kind in ["lumber_camp", "quarry"]:
			var d := Vector2(b.global_position.x - c.x, b.global_position.z - c.z).length()
			if d > best_d:
				best_d = d
				best = b
	return best


func _center() -> Vector3:
	return colony.hall.global_position if colony.hall and is_instance_valid(colony.hall) else Vector3.ZERO


## Ponto livre entre o primeiro e o último anel de `rings` (nunca dentro da cidade).
func _point(rings: Array) -> Vector3:
	var lo := maxf(float(ColonyData.RINGS[int(rings[0]) - 1]), ColonyData.CITY_RADIUS + 14.0)
	var last := int(rings[1])
	var hi := float(ColonyData.RINGS[last]) if last < ColonyData.RINGS.size() else INF
	return colony._wild_point(lo, hi)


func _around(c: Vector3, lo: float, hi: float) -> Vector3:
	var a := randf() * TAU
	return c + Vector3(cos(a), 0, sin(a)) * randf_range(lo, hi)


## Caravana, aldeões ou baú (cenário local; o servidor dedicado não precisa deles).
func _make_props(kind: String, at: Vector3) -> void:
	if colony.role == "server":
		return
	match kind:
		"caravan":
			_add_prop("caravan", at)
		"lost_villagers":
			for i in ColonyData.EVENT_VILLAGERS:
				var a := TAU * i / ColonyData.EVENT_VILLAGERS
				_add_prop("villager", at + Vector3(cos(a), 0, sin(a)) * 1.4)
		"lost_chest":
			_add_prop("chest", at)


func _add_prop(kind: String, at: Vector3) -> void:
	var p: ColonyEventProp = PROP.new()
	p.kind = kind
	p.colony = colony
	p.position = at
	colony.add_child(p)
	_props.append(p)


func _clear_props() -> void:
	for p in _props:
		if is_instance_valid(p):
			p.remove_from_group("interactable")
			p.remove_from_group("caravan")
			p.remove_from_group("event_props")
			p.queue_free()
	_props.clear()


func _spawn_enemy(kind: String, at: Vector3, siege: bool) -> Enemy:
	var e := colony.spawn_enemy(kind, at, -1.0, "", siege)
	e.died.connect(_on_enemy_died)
	_enemies.append(e)
	return e


func _on_enemy_died(e: Enemy) -> void:
	_enemies.erase(e)
	check_meteor()
	if active == "lost_chest" and enemies().is_empty():
		colony.say("Os guardas do baú caíram! Ele já pode ser aberto.", Color(1, 0.85, 0.35))
	if active != "camp_raid":
		return
	for o in _enemies:
		if is_instance_valid(o) and not o.dead and o.siege:
			return
	colony.say("O ataque foi repelido!", Color(0.6, 1, 0.6))
	complete("camp_raid")


func _spawn_animal(kind: String, at: Vector3, alpha: bool) -> void:
	var a: ColonyAnimal = ANIMAL.new()
	a.kind = kind
	a.alpha = alpha
	a.colony = colony
	a.position = at + Vector3.UP * 0.3
	if colony.role == "server":
		a.net_id = colony._new_id()
		colony.amap[a.net_id] = a
	colony.add_child(a)
	if colony.role == "server":
		Lobby.city_animal_added(a)
	_animals.append(a)


## Impacto do meteoro: visível de longe (só onde há tela).
func _meteor_fx(at: Vector3) -> void:
	if DisplayServer.get_name() == "headless":
		return
	FX.burst(at + Vector3.UP * 1.5, Color(1, 0.55, 0.2), 90, 16.0, 0.35, 1.6)
	FX.burst(at + Vector3.UP * 1.0, Color(0.55, 0.75, 1.0), 60, 10.0, 0.25, 1.4)
	FX.ring(at, Color(1, 0.6, 0.25, 0.9), 14.0, 1.2)
	FX.ring(at, Color(0.6, 0.8, 1.0, 0.8), 8.0, 0.9)
	Sfx.play("slam", 0.0, 0.0)
