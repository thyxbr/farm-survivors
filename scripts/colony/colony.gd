class_name Colony
extends Node3D
## Estado da Defesa da Cidade: economia (ouro, comida, moradores, impostos, salários),
## ciclo dia/noite, ondas de monstros, caça e as regras de onde se pode construir.
## É o pai das construções, dos soldados, dos animais e dos monstros.
##
## role = "solo"   — um jogador (o cofre é o ouro do personagem do modo, Game.gold);
##        "server" — cidade cooperativa no servidor dedicado: simula tudo, o cofre é `gold` (compartilhado)
##                   e avisa o Lobby de cada mudança para os clientes;
##        "client" — réplica no PC de cada jogador: mostra o que o servidor manda e pede as ações a ele.

signal net_changed   # cliente: chegou estado novo do servidor (as janelas se atualizam)

const BUILDING := preload("res://scripts/colony/building.gd")
const SOLDIER := preload("res://scripts/colony/soldier.gd")
const ANIMAL := preload("res://scripts/colony/animal.gd")
const ENEMY := preload("res://scripts/enemies/enemy.gd")

const DIR_NAMES := ["Norte", "Nordeste", "Leste", "Sudeste", "Sul", "Sudoeste", "Oeste", "Noroeste"]

var world: Node
var role := "solo"
var day := 1
var phase := "setup"          # setup (sem prefeitura) | day | night | over
var phase_t := 0.0            # dia: segundos restantes · noite: segundos passados
var food := 0
var citizens := 0   # aldeões (livres + ocupados)
var train_queue := 0   # aldeões na fila de treino da prefeitura
var train_t := 0.0     # progresso do aldeão que está sendo treinado (s)
var tax_level := 1
var army_mode := "guard"      # guard (defende o ponto de reunião) | follow (acompanha o jogador)
var rally := Vector3.ZERO
var hall: ColonyBuilding = null
var boss: Enemy = null
var total_kills := 0
var night_kills := 0
var wave_total := 0
var wave_queue: Array = []
var wave_dirs: Array = []     # índices de DIR_NAMES
var last_report := {}
## Obstáculos do mapa (árvores e pedras): [Vector2 centro, raio]. Preenchido pelo mundo.
var obstacles: Array = []
## Nós de recurso do mapa (árvores, pedras, veios, cristais, arbustos); a cena da cidade cria e liga.
var nature: ColonyNature
var day_length := ColonyData.DAY_LENGTH
var first_day_bonus := ColonyData.FIRST_DAY_BONUS

# ---- cooperativo
## Cofre compartilhado (no solo o cofre é Game.gold).
var gold := 0
## Estoque de madeira, pedra, ferro e cristal (ouro fica em get_gold() e comida em `food`).
var res := {"wood": 0, "stone": 0, "iron": 0, "crystal": 0}
## Jogadores na cidade (escala as ondas).
var team_size := 1
## Noite especial em curso e a anunciada para a próxima noite (chaves de ColonyData.NIGHT_MODS).
var night_mod := ""
var next_mod := ""
## Servidor: quem pediu a noite (peer -> true). A noite começa com metade do grupo.
var votes := {}
## Servidor: peer que o exército segue no modo "follow".
var follow_peer := 0
## Servidor: peer que fez o pedido em andamento (para as mensagens).
var actor := 0
var bmap := {}                # net_id -> construção
var smap := {}                # net_id -> soldado
var amap := {}                # net_id -> animal
var _next_id := 1
var _net_wave_left := 0
var _net_votes := 0
var _overflow_hp := 1.0
var _aid_day := -99
var _state_dirty := true

var _spawn_acc := 0.0
var _spawn_i := 0
var _warned := false
var _animal_t := 0.0
var _gather_t := 0.0               # segundos até a próxima entrega da serraria/pedreira
var _gather_acc := {}              # construção -> unidades produzidas e ainda não entregues (fração)
var _gather_made := {}             # construção -> unidades já entregues desde o último nó esgotado
var _core_warn := 0.0
var _dawn_pending := false
var _flag: Node3D


func new_colony() -> void:
	day = 1
	phase = "setup"
	phase_t = 0.0
	food = ColonyData.START_FOOD
	citizens = ColonyData.START_CITIZENS
	tax_level = 1
	_reset_res(0)
	Game.gold = ColonyData.START_GOLD
	Game.stats_changed.emit()


## Servidor: cidade cooperativa nova para `players` jogadores.
func new_coop(players: int) -> void:
	day = 1
	phase = "setup"
	phase_t = 0.0
	team_size = maxi(1, players)
	food = ColonyData.COOP_START_FOOD
	citizens = ColonyData.COOP_START_CITIZENS
	tax_level = 1
	_reset_res(ColonyData.COOP_WOOD_PER_PLAYER * (team_size - 1))
	gold = ColonyData.COOP_START_GOLD + ColonyData.COOP_GOLD_PER_PLAYER * (team_size - 1)
	_dirty()


func is_coop() -> bool:
	return role != "solo"


# ================================================================ cofre e mensagens
func get_gold() -> int:
	return Game.gold if role == "solo" else gold


func _pay(n: int) -> void:
	if role == "solo":
		Game.gold -= n
		Game.stats_changed.emit()
	else:
		gold -= n
		_dirty()


## Estoque inicial (ou o de um save antigo): START_RES e `extra_wood` de madeira.
func _reset_res(extra_wood: int) -> void:
	res = {"wood": 0, "stone": 0, "iron": 0, "crystal": 0}
	for r in ColonyData.START_RES:
		res[r] = int(ColonyData.START_RES[r])
	res["wood"] = int(res.wood) + extra_wood


## Quanto há de um recurso no estoque da cidade.
func amount(r: String) -> int:
	match r:
		"gold":
			return get_gold()
		"food":
			return food
	return int(res.get(r, 0))


## "" se o estoque cobre o custo; senão o que falta, ex.: "Faltam 20 de Pedra."
func missing(c: Dictionary) -> String:
	var parts: Array[String] = []
	for r in ColonyData.RESOURCES:
		var need := int(c.get(r, 0))
		if need > amount(r):
			parts.append("%d de %s" % [need - amount(r), ColonyData.RES_NAMES[r]])
	return "" if parts.is_empty() else "Faltam %s." % ", ".join(parts)


## Confere e paga o custo de uma vez (tudo ou nada). Falso, sem tirar nada, se faltar algo.
func pay(c: Dictionary) -> bool:
	if missing(c) != "":
		return false
	for r in ColonyData.RESOURCES:
		var n := int(c.get(r, 0))
		if n <= 0:
			continue
		match r:
			"gold":
				_pay(n)
			"food":
				food -= n
			_:
				res[r] = int(res.get(r, 0)) - n
	_res_changed()
	return true


## Soma ao estoque. Com `at`, mostra o número flutuante naquele ponto.
func gain(c: Dictionary, at := Vector3.INF) -> void:
	var shown := 0
	for r in ColonyData.RESOURCES:
		var n := int(c.get(r, 0))
		if n <= 0:
			continue
		match r:
			"gold":
				earn(n)
			"food":
				food += n
			_:
				res[r] = int(res.get(r, 0)) + n
		if at != Vector3.INF and DisplayServer.get_name() != "headless":
			FX.damage_number(at + Vector3.UP * 0.7 * shown, "+%d %s" % [n, ColonyData.RES_NAMES[r]], UITheme.GOLD, 40)
			shown += 1
	_res_changed()


func _res_changed() -> void:
	if role == "solo":
		Game.stats_changed.emit()
	else:
		_dirty()


func earn(n: int) -> void:
	if role == "solo":
		Game.add_gold(n)
	else:
		gold += n
		_dirty()


## Aviso para todos que estão na cidade (no servidor vai para os clientes).
func say(text: String, color := Color(1, 1, 1)) -> void:
	if role == "server":
		Lobby.city_say(text, color)
	else:
		Game.notify.emit(text, color)


func _dirty() -> void:
	_state_dirty = true


func _new_id() -> int:
	_next_id += 1
	return _next_id


## Nome de quem fez o pedido (servidor), para as mensagens do grupo.
func _actor_name() -> String:
	if actor != 0 and Network.players.has(actor):
		return str(Network.players[actor].name)
	return "Alguém"


# ================================================================ coleta
## Servidor/solo: um golpe num nó de recurso. Cada golpe entrega um pedaço do total (o último leva o
## resto, para a soma fechar) e o último golpe esgota o nó.
func harvest(id: int, at: Vector3) -> void:
	if role == "client" or nature == null:
		return
	var n := nature.node(id)
	if n == null or not n.alive:
		return
	var d: Dictionary = ColonyData.NODES[n.kind]
	var hits := int(d.hits)
	var done := hits - n.hits_left   # golpes já dados
	var piece := n.total * (done + 1) / hits - n.total * done / hits
	var mult := 1.0   # bônus de pesquisa (Task 6)
	piece = int(round(piece * mult))
	n.hits_left -= 1
	if piece > 0:
		gain({str(d.res): piece}, n.global_position.lerp(at, 0.3) + Vector3.UP * 2.2)
	if n.hits_left <= 0:
		nature.deplete(id, day)


## Há construção cobrindo o círculo (centro p no plano XZ, raio r)?
func building_at(p: Vector2, r: float) -> bool:
	for b in buildings():
		if _circle_hits(_rect(Vector2(b.global_position.x, b.global_position.z), b.rotation.y, b.size), p, r):
			return true
	return false


# ================================================================ consultas
func buildings() -> Array:
	var out: Array = []
	for b in get_tree().get_nodes_in_group("buildings"):
		if not b.dead and b.colony == self:
			out.append(b)
	return out


func count_of(kind: String) -> int:
	var n := 0
	for b in buildings():
		if b.kind == kind:
			n += 1
	return n


func soldiers() -> Array:
	var out: Array = []
	for s in get_tree().get_nodes_in_group("soldiers"):
		if not s.dead and s.colony == self:
			out.append(s)
	return out


func soldier_count() -> int:
	return soldiers().size()


## Monstros vivos desta cidade (as torres e soldados só miram nestes).
func live_enemies() -> Array:
	var out: Array = []
	for c in get_children():
		if c is Enemy and not c.dead:
			out.append(c)
	return out


## Jogadores nesta cidade: o local (solo/cliente) ou as réplicas (servidor).
func unit_players() -> Array:
	var out: Array = []
	if role == "server":
		for c in get_parent().get_children():
			if c is Player and not c.dead:
				out.append(c)
	else:
		var p := get_tree().get_first_node_in_group("player") as Player
		if p and not p.dead:
			out.append(p)
	return out


func nearest_player(pos: Vector3) -> Player:
	var best: Player = null
	var best_d := INF
	for p in unit_players():
		var d: float = pos.distance_squared_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


## Quem o exército segue no modo "follow".
func follow_target() -> Player:
	if role == "server":
		var rp = Network.remote_players.get(follow_peer)
		if rp != null and is_instance_valid(rp) and rp.get_parent() == get_parent():
			return rp
		return null
	return get_tree().get_first_node_in_group("player") as Player


## Aldeões ocupados pelas construções vivas (`crew`).
func busy() -> int:
	var n := 0
	for b in buildings():
		n += int(b.data.get("crew", 0))
	return n


func free_villagers() -> int:
	return maxi(0, citizens - busy())


## Fração das vagas ocupadas por aldeões (1 = todas cheias). Com fome ou deserção cai e a produção cai junto.
func staffing() -> float:
	var n := busy()
	return 1.0 if n == 0 else clampf(float(citizens) / n, 0.0, 1.0)


## Eficiência de uma construção: hoje todas dividem a falta de aldeões por igual.
func crew_eff(_b: ColonyBuilding) -> float:
	return staffing()


## Põe um aldeão na fila de treino (comida na hora, vaga numa moradia). "" = entrou na fila.
func train_villager() -> String:
	if phase == "over":
		return "A cidade caiu."
	if hall == null or not is_instance_valid(hall) or hall.dead:
		return "Construa a prefeitura primeiro."
	if citizens + train_queue >= pop_cap():
		return "Sem moradia livre. Construa casas."
	var lack := missing(ColonyData.VILLAGER_COST)
	if lack != "":
		return lack
	if role == "client":
		Lobby.city_request("train", [])
		return ""
	pay(ColonyData.VILLAGER_COST)
	train_queue += 1
	_dirty()
	return ""


func _train_tick(delta: float) -> void:
	if train_queue <= 0:
		return
	train_t += delta
	if train_t < ColonyData.VILLAGER_TIME:
		return
	train_t = 0.0
	train_queue -= 1
	if citizens < pop_cap():
		citizens += 1
		say("Um aldeão terminou o treino.", Color(0.8, 1.0, 0.6))
	else:   # a moradia caiu enquanto treinava: devolve a comida
		gain(ColonyData.VILLAGER_COST)
		say("Sem moradia: o treino foi cancelado e a comida devolvida.", Color(1, 0.75, 0.5))
	Game.stats_changed.emit()
	_dirty()


func pop_cap() -> int:
	var n := 0
	for b in buildings():
		if b.kind == "house":
			n += int(b.data.pop) + 3 * (b.level - 1)
		elif b.kind == "town_hall":
			n += int(b.data.pop) + 4 * (b.level - 1)
	return n


func army_cap() -> int:
	var n := 0
	for b in buildings():
		if b.kind == "barracks":
			n += int(b.data.army) + 3 * (b.level - 1)
	return n


func barracks_level() -> int:
	var lv := 0
	for b in buildings():
		if b.kind == "barracks":
			lv = maxi(lv, b.level)
	return lv


func salaries() -> int:
	var n := 0
	for s in soldiers():
		n += int(s.data.salary)
	return n


## Manutenção diária das torres e quartéis (só no cooperativo).
func upkeep() -> int:
	if not is_coop():
		return 0
	var n := 0
	for b in buildings():
		n += int(ColonyData.UPKEEP.get(b.kind, 0)) * b.level
	return n


## Preço da próxima construção deste tipo (no cooperativo cresce a cada cópia).
func cost_of(kind: String) -> Dictionary:
	if kind == "town_hall" or not ColonyData.BUILDINGS.has(kind):
		return {}
	if is_coop():
		return ColonyData.coop_cost(kind, count_of(kind))
	return ColonyData.BUILDINGS[kind].cost.duplicate()


## Alcance das torres nesta noite (Névoa Densa reduz).
func range_mult() -> float:
	return 0.7 if phase == "night" and night_mod == "nevoa" else 1.0


func siege_alive() -> int:
	var n := 0
	for c in get_children():
		if c is Enemy and c.siege and not c.dead:
			n += 1
	return n


func wave_left() -> int:
	if role == "client":
		return _net_wave_left
	return wave_queue.size() + siege_alive()


func night_votes() -> int:
	return _net_votes if role == "client" else votes.size()


func votes_needed() -> int:
	return maxi(1, int(ceil(team_size / 2.0)))


## Multiplicador de tecnologia da produção de "wood"/"stone". Ponto único para plugar `colony.mult(res)` (Task 6).
func _gather_mult(_res: String) -> float:
	return 1.0


## Nós vivos que a serraria/pedreira `b` alcança.
func _gather_live(b: ColonyBuilding) -> int:
	return nature.alive_near(b.data.gather, b.global_position, float(b.data.reach)).size() if nature != null else 0


## Servidor/solo, de dia: serraria e pedreira entregam o que produziram em `dt` segundos. Cada
## NODE_YIELD_CAMP unidades esgotam o nó vivo mais próximo (mesmo caminho de esgotamento do jogador).
func _gather_tick(dt: float) -> void:
	if role == "client" or phase != "day" or nature == null:
		return
	for b in buildings():
		if not b.data.has("gather") or b.dead:
			continue
		var res: String = ColonyData.NODES[b.data.gather].res
		var live := _gather_live(b)
		var acc := float(_gather_acc.get(b, 0.0)) + ColonyData.gather_rate(crew_eff(b), live, _gather_mult(res)) * int(b.data.crew) * dt
		var whole := int(acc)
		_gather_acc[b] = acc - whole
		if whole <= 0:
			continue
		gain({res: whole})
		var made := int(_gather_made.get(b, 0)) + whole
		while made >= ColonyData.NODE_YIELD_CAMP:
			made -= ColonyData.NODE_YIELD_CAMP
			var n := nature.nearest_to(b.data.gather, b.global_position, float(b.data.reach))
			if n == null:
				made = 0
				break
			nature.deplete(n.id, day)
		_gather_made[b] = made
	for d in [_gather_acc, _gather_made]:   # esquece as construções que caíram
		for k in d.keys():
			if not is_instance_valid(k) or k.dead:
				d.erase(k)


## Madeira e pedra por minuto que serrarias e pedreiras rendem agora (HUD e previsão).
func gather_per_min() -> Dictionary:
	var out := {"wood": 0.0, "stone": 0.0}
	for b in buildings():
		if b.data.has("gather") and not b.dead:
			var res: String = ColonyData.NODES[b.data.gather].res
			out[res] += ColonyData.gather_rate(crew_eff(b), _gather_live(b), _gather_mult(res)) * int(b.data.crew) * 60.0
	return out


## Previsão do próximo amanhecer (também usada no relatório).
func forecast() -> Dictionary:
	var farm_food := 0.0
	var market_gold := 0.0
	var hall_gold := 0
	var markets: Array[float] = []
	for b in buildings():
		match b.kind:
			"farm":
				farm_food += float(b.data.food) * ColonyData.level_mult(b.level, 0.5)
			"market":
				markets.append(float(b.data.gold) * ColonyData.level_mult(b.level, 0.5))
			"town_hall":
				hall_gold += int(b.data.gold) * b.level
				if is_coop():
					hall_gold += ColonyData.TEAM_HALL_GOLD * (team_size - 1)   # mais gente, mais tributo
	# mercados saturam no cooperativo: os melhores rendem cheio, os demais cada vez menos
	markets.sort()
	markets.reverse()
	for i in markets.size():
		var k := 1.0
		if is_coop() and i >= ColonyData.MARKET_FREE:
			k = maxf(ColonyData.MARKET_MIN, 1.0 - ColonyData.MARKET_DECAY * (i - ColonyData.MARKET_FREE + 1))
		market_gold += markets[i] * k
	var eff := staffing()
	var tax: int = citizens * ColonyData.TAX[tax_level]
	var trade := int(round(market_gold * eff))
	var sal := salaries()
	var up := upkeep()
	var food_in := int(round(farm_food * eff))
	var food_out := citizens + soldier_count()
	return {
		"tax": tax, "trade": trade, "hall": hall_gold, "salaries": sal, "upkeep": up,
		"gold_in": tax + trade + hall_gold, "gold_net": tax + trade + hall_gold - sal - up,
		"food_in": food_in, "food_out": food_out, "food_net": food_in - food_out,
		"workers": busy(), "employed": mini(citizens, busy()), "eff": eff,
		"wood_min": gather_per_min().wood, "stone_min": gather_per_min().stone,
	}


# ================================================================ construção
## Devolve "" se dá para construir ali, ou o motivo de não dar.
func can_place(kind: String, pos: Vector3, rot: float, ignore_cost := false) -> String:
	var d := ColonyData.building(kind)
	if d.is_empty():
		return "Construção desconhecida."
	if phase == "over":
		return "A cidade caiu."
	if kind == "town_hall":
		if hall != null and is_instance_valid(hall) and not hall.dead:
			return "Já existe uma prefeitura."
		if Vector2(pos.x, pos.z).length() > ColonyData.HALL_ZONE:
			return "A prefeitura vai na clareira central."
	else:
		if hall == null or not is_instance_valid(hall) or hall.dead:
			return "Construa a prefeitura primeiro."
		if d.has("gather"):   # serraria e pedreira vão para perto do recurso, até max_dist do centro do mapa
			if Vector2(pos.x, pos.z).length() > float(d.max_dist):
				return "Longe demais da cidade (máximo %d m do centro)." % int(d.max_dist)
			if nature == null or nature.alive_near(d.gather, pos, float(d.reach)).size() < int(d.min_nodes):
				var what := "árvores" if d.gather == "tree" else "pedras"
				return "Precisa de %d %s vivas num raio de %d m." % [int(d.min_nodes), what, int(d.reach)]
		elif Vector2(pos.x - hall.global_position.x, pos.z - hall.global_position.z).length() > ColonyData.CITY_RADIUS:
			return "Fora dos limites da cidade."
		if not ignore_cost:
			var lack := missing(cost_of(kind))
			if lack != "":
				return lack
			var need := int(d.get("crew", 0)) - free_villagers()
			if need > 0:
				return "Faltam %d aldeão livre." % need if need == 1 else "Faltam %d aldeões livres." % need
	var lim := ColonyData.MAP_HALF - 10.0
	if absf(pos.x) > lim or absf(pos.z) > lim:
		return "Muito perto da borda do mapa."
	var rect := _rect(Vector2(pos.x, pos.z), rot, d.size)
	for b in buildings():
		if _overlap(rect, _rect(Vector2(b.global_position.x, b.global_position.z), b.rotation.y, b.size)):
			return "O espaço está ocupado (%s)." % b.data.name
	for o in obstacles:
		if _circle_hits(rect, o[0], o[1]):
			return "Há árvores ou pedras no caminho."
	if kind not in ["gate", "spikes", "farm"]:   # dá para ficar em cima destes (não bloqueiam a passagem)
		for u in get_tree().get_nodes_in_group("colony_units"):
			if u.get_world_3d() != get_world_3d():
				continue
			if _circle_hits(rect, Vector2(u.global_position.x, u.global_position.z), 0.45):
				return "Tem alguém no lugar (saia de cima)."
	for e in live_enemies():
		if _circle_hits(rect, Vector2(e.global_position.x, e.global_position.z), e.radius):
			return "Tem um monstro no caminho."
	return ""


## Constrói (cobrando o preço, a menos que free). Devolve a construção (no cliente só pede ao servidor).
func place(kind: String, pos: Vector3, rot: float, free := false, level := 1, hp := -1.0) -> ColonyBuilding:
	if role == "client":
		if not free:
			Lobby.city_request("place", [kind, pos.x, pos.z, rot])
		return null
	var d := ColonyData.building(kind)
	var cost := cost_of(kind)
	if not free and not pay(cost):   # o servidor reconfere: dois jogadores podem gastar o mesmo cofre
		return null
	var b: ColonyBuilding = BUILDING.new()
	b.kind = kind
	b.level = level
	b.hp = hp
	b.colony = self
	b.position = Vector3(pos.x, 0.0, pos.z)
	b.rotation.y = rot
	b.invested = cost if is_coop() else d.cost.duplicate()
	if role == "server":
		b.net_id = _new_id()
		bmap[b.net_id] = b
	add_child(b)
	b.destroyed.connect(_on_building_destroyed)
	if kind == "town_hall":
		hall = b
		if rally == Vector3.ZERO:
			set_rally(b.global_position + b.global_basis.z * 8.0, true)
		if phase == "setup":
			phase = "day"
			phase_t = day_length + first_day_bonus
			say("A cidade foi fundada! Construa casas, fazendas e defesas antes da noite.", Color(1, 0.9, 0.5))
			say("Saia da cidade para caçar: cervos, coelhos e javalis rendem comida e ouro.", Color(0.8, 1.0, 0.6))
			if is_coop():
				say("Cidade em grupo: o cofre é de todos. Cada noite vencida dá ouro e XP ao seu personagem; a cada 5, um baú.", Color(0.7, 0.9, 1.0))
			_spawn_wildlife(true)
	if not free:
		Sfx.play("plant", 0.1, 0.0)
		FX.burst(b.global_position + Vector3.UP * 0.5, Color(0.75, 0.65, 0.45), 30, 5.0, 0.15, 0.8)
		FX.ring(b.global_position, Color(1, 0.9, 0.6, 0.8), maxf(d.size.x, d.size.y) * 0.6, 0.4)
	if kind == "barracks" or kind == "town_hall":
		assign_posts.call_deferred()
	if role == "server":
		Lobby.city_building_added(b)
		_dirty()
	return b


## O que demolir devolve: REFUND de cada recurso investido, arredondado para baixo.
func refund_of(b: ColonyBuilding) -> Dictionary:
	var refund := {}
	for r in b.invested:
		refund[r] = int(int(b.invested[r]) * ColonyData.REFUND)
	return refund


func demolish(b: ColonyBuilding) -> void:
	if role == "client":
		if b and not b.dead:
			if b.is_core:
				Game.notify.emit("A prefeitura não pode ser demolida.", UITheme.BAD)
			else:
				Lobby.city_request("demolish", [b.net_id])
		return
	if b == null or b.dead or b.is_core:
		if b and b.is_core:
			say("A prefeitura não pode ser demolida.", UITheme.BAD)
		return
	var refund := refund_of(b)
	gain(refund, b.global_position + Vector3.UP * 2.0)
	say("%s demolida: +%s." % [b.data.name, ColonyData.cost_text(refund)], Color(1, 0.85, 0.4))
	b.dead = true
	b.remove_from_group("buildings")
	b.remove_from_group("interactable")
	FX.burst(b.global_position + Vector3.UP, Color(0.6, 0.5, 0.4), 30, 5.0, 0.15, 0.8)
	Sfx.play("hit", 0.1, -4.0)
	if role == "server":
		Lobby.city_building_removed(b, false)
		bmap.erase(b.net_id)
	b.queue_free()
	_check_army_cap()
	_check_housing()


func upgrade_cost(b: ColonyBuilding) -> Dictionary:
	return ColonyData.upgrade_cost(b.kind, b.level)


func upgrade(b: ColonyBuilding) -> String:
	if b.level >= ColonyData.MAX_LEVEL:
		return "Já está no nível máximo."
	if b.kind != "town_hall" and hall and b.level >= hall.level + 1:
		return "Melhore a prefeitura primeiro (nível %d)." % (hall.level + 1)
	var cost := upgrade_cost(b)
	var lack := missing(cost)
	if lack != "":
		return lack
	if role == "client":
		Lobby.city_request("upgrade", [b.net_id])
		return ""
	if not pay(cost):
		return missing(cost)
	b.invested = ColonyData.add_cost(b.invested, cost)
	b.set_level(b.level + 1)
	Game.stats_changed.emit()
	Sfx.play("levelup", 0.05, -4.0)
	say("%s melhorada para o nível %d." % [b.data.name, b.level], Color(0.7, 1.0, 0.6))
	assign_posts.call_deferred()
	if role == "server":
		Lobby.city_building_changed(b)
	return ""


## Reparar custa uma fração (REPAIR_RATIO x nível x dano sofrido) de cada recurso da construção.
## A prefeitura, que não tem custo, é remendada com ouro. Vazio = não precisa de reparo.
func repair_cost(b: ColonyBuilding) -> Dictionary:
	if b.hp >= b.max_hp - 0.5:
		return {}
	var base: Dictionary = b.data.cost if not b.data.cost.is_empty() else {"gold": 120}
	var out := {}
	for r in base:
		out[r] = maxi(1, int(ceil((1.0 - b.hp / b.max_hp) * float(base[r]) * b.level * ColonyData.REPAIR_RATIO)))
	return out


func repair(b: ColonyBuilding) -> String:
	var cost := repair_cost(b)
	if cost.is_empty():
		return "Não precisa de reparo."
	var lack := missing(cost)
	if lack != "":
		return lack
	if role == "client":
		Lobby.city_request("repair", [b.net_id])
		return ""
	if not pay(cost):
		return missing(cost)
	b.repair_full()
	Sfx.play("plant", 0.1, -2.0)
	if role == "server":
		Lobby.city_building_changed(b)
	return ""


func repair_all_cost() -> Dictionary:
	var n := {}
	for b in buildings():
		n = ColonyData.add_cost(n, repair_cost(b))
	return n


func repair_all() -> String:
	var cost := repair_all_cost()
	if cost.is_empty():
		return "Nada para reparar."
	var lack := missing(cost)
	if lack != "":
		return lack
	if role == "client":
		Lobby.city_request("repair_all", [])
		return ""
	if not pay(cost):
		return missing(cost)
	for b in buildings():
		if not repair_cost(b).is_empty():
			b.repair_full()
			if role == "server":
				Lobby.city_building_changed(b)
	Game.stats_changed.emit()
	Sfx.play("plant", 0.1, -2.0)
	return ""


func set_tax(level: int) -> void:
	level = clampi(level, 0, 2)
	if role == "client":
		Lobby.city_request("tax", [level])
		return
	if level != tax_level and role == "server":
		say("%s mudou o imposto para %s." % [_actor_name(), ColonyData.TAX_NAMES[level]], Color(1, 0.9, 0.6))
	tax_level = level
	_dirty()


# ================================================================ exército
func recruit(unit: String) -> String:
	var u: Dictionary = ColonyData.UNITS[unit]
	if count_of("barracks") == 0:
		return "Construa um quartel."
	if barracks_level() < int(u.get("needs_level", 1)):
		return "Exige um quartel nível %d." % int(u.needs_level)
	if soldier_count() >= army_cap():
		return "Os quartéis estão lotados (%d vagas)." % army_cap()
	if citizens < 1 or free_villagers() < 1:
		return "Não há aldeões livres para recrutar. Treine mais na prefeitura."
	var ucost := {"gold": int(u.cost)}   # as unidades ainda custam só ouro
	var lack := missing(ucost)
	if lack != "":
		return lack
	if role == "client":
		Lobby.city_request("recruit", [unit])
		return ""
	pay(ucost)
	citizens -= 1
	Game.stats_changed.emit()
	var at := _barracks_door()
	var s := spawn_soldier(unit, at)
	FX.burst(s.global_position + Vector3.UP, Color(0.5, 0.7, 1.0), 25, 4.0, 0.12, 0.8)
	Sfx.play("quest", 0.05, -6.0)
	return ""


func spawn_soldier(unit: String, pos: Vector3, hp := -1.0) -> ColonySoldier:
	var s: ColonySoldier = SOLDIER.new()
	s.unit = unit
	s.colony = self
	s.hp = hp
	s.position = pos + Vector3.UP * 0.2
	if role == "server":
		s.net_id = _new_id()
		smap[s.net_id] = s
	add_child(s)
	assign_posts.call_deferred()
	if role == "server":
		Lobby.city_soldier_added(s)
		_dirty()
	return s


func dismiss(s: ColonySoldier) -> void:
	if s == null or s.dead:
		return
	if role == "client":
		Lobby.city_request("dismiss", [s.net_id])
		return
	citizens += 1
	s.leave()
	assign_posts.call_deferred()
	_dirty()


## O soldado saiu (dispensa, deserção ou morte).
func on_soldier_gone(s: ColonySoldier, died: bool) -> void:
	if role == "server":
		smap.erase(s.net_id)
		Lobby.city_soldier_removed(s, died)
		_dirty()


func _barracks_door() -> Vector3:
	for b in buildings():
		if b.kind == "barracks":
			return b.global_position + b.global_basis.z * (b.size.y / 2.0 + 1.5)
	return rally


func set_rally(pos: Vector3, silent := false) -> void:
	if role == "client" and not silent:
		Lobby.city_request("rally", [pos.x, pos.z])
		return
	rally = Vector3(pos.x, 0.0, pos.z)
	if _flag == null:
		_flag = Node3D.new()
		add_child(_flag)
		ColonyVisuals._cyl(_flag, 0.05, 0.05, 2.8, Vector3(0, 1.4, 0), ColonyVisuals.WOOD_DARK)
		ColonyVisuals._box(_flag, Vector3(0.9, 0.6, 0.04), Vector3(0.47, 2.45, 0), ColonyVisuals.BANNER)
		ColonyVisuals._sphere(_flag, 0.08, Vector3(0, 2.85, 0), Color(0.9, 0.75, 0.3))
	_flag.position = rally
	if not silent:
		FX.ring(rally, Color(0.4, 0.6, 1.0, 0.9), 2.5, 0.5)
		if role == "server":
			say("%s mudou o ponto de reunião do exército." % _actor_name(), Color(0.6, 0.8, 1.0))
		else:
			say("Ponto de reunião do exército definido.", Color(0.6, 0.8, 1.0))
	if role != "client":
		assign_posts()
	_dirty()


func toggle_army_mode() -> void:
	if role == "client":
		Lobby.city_request("army", [])
		return
	army_mode = "follow" if army_mode == "guard" else "guard"
	if role == "server":
		follow_peer = actor
		if army_mode == "follow":
			say("Exército: seguindo %s." % _actor_name(), Color(0.6, 0.8, 1.0))
		else:
			say("Exército: voltando a defender o ponto de reunião.", Color(0.6, 0.8, 1.0))
	elif army_mode == "follow":
		say("Exército: seguindo você.", Color(0.6, 0.8, 1.0))
	else:
		say("Exército: voltando a defender o ponto de reunião.", Color(0.6, 0.8, 1.0))
	_dirty()


## Postos em formação no ponto de reunião (corpo a corpo na frente, arqueiros atrás).
func assign_posts() -> void:
	if role == "client":
		return
	var list := soldiers()
	list.sort_custom(func(a, b) -> bool: return int(a.is_ranged()) < int(b.is_ranged()))
	var fwd := Vector3.FORWARD
	if hall and is_instance_valid(hall):
		var away := rally - hall.global_position
		away.y = 0.0
		if away.length() > 0.5:
			fwd = away.normalized()
	var right := fwd.cross(Vector3.UP)
	var per_row := 6
	for i in list.size():
		var row := i / per_row
		var col := i % per_row
		var in_row := mini(per_row, list.size() - row * per_row)
		var x := (col - (in_row - 1) / 2.0) * 1.7
		list[i].post = rally + right * x - fwd * (row * 1.8)
		list[i].follow_offset = Vector3((col - (in_row - 1) / 2.0) * 1.4, 0, -2.6 - row * 1.6)


func _check_housing() -> void:
	var lost := citizens - pop_cap()
	if lost > 0:
		citizens -= lost
		say("%d morador(es) ficaram sem casa e partiram." % lost, Color(1, 0.6, 0.5))
		_dirty()


func _check_army_cap() -> void:
	var extra := soldier_count() - army_cap()
	if extra <= 0:
		return
	var list := soldiers()
	for i in extra:
		dismiss(list[list.size() - 1 - i])
	say("%d soldado(s) dispensado(s): faltam vagas no quartel." % extra, Color(1, 0.75, 0.5))


# ================================================================ ciclo
func _physics_process(delta: float) -> void:
	if role == "client":
		# o servidor manda o relógio; aqui só corre entre um estado e outro
		if phase == "day":
			phase_t = maxf(0.0, phase_t - delta)
		elif phase == "night":
			phase_t += delta
		return
	_core_warn = maxf(0.0, _core_warn - delta)
	match phase:
		"day":
			phase_t -= delta
			_animal_t -= delta
			if _animal_t <= 0.0:
				_animal_t = 4.0
				_spawn_wildlife(false)
			_train_tick(delta)
			_gather_t -= delta
			if _gather_t <= 0.0:
				_gather_t += ColonyData.GATHER_TICK
				_gather_tick(ColonyData.GATHER_TICK)
			if phase_t <= 25.0 and not _warned:
				_warned = true
				say("O sol está se pondo... os monstros atacam ao anoitecer!", Color(1, 0.6, 0.4))
				Sfx.play("quest", 0.0, -4.0)
			if phase_t <= 0.0:
				start_night(true)
		"night":
			phase_t += delta
			var rate := (1.1 + 0.12 * day) * (1.0 + 0.3 * (team_size - 1) if is_coop() else 1.0)
			_spawn_acc += delta * rate
			while _spawn_acc >= 1.0 and not wave_queue.is_empty():
				_spawn_acc -= 1.0
				_spawn_next()
			if wave_queue.is_empty():
				_spawn_acc = 0.0
				if (siege_alive() == 0 or phase_t > ColonyData.NIGHT_MAX) and not _dawn_pending:
					_dawn_pending = true
					_end_night()


## 0 = noite fechada, 1 = meio-dia. Usado pelo mundo para a luz.
func daylight() -> float:
	match phase:
		"setup":
			return 1.0
		"day":
			var total := day_length + (first_day_bonus if day == 1 else 0.0)
			var since := total - phase_t
			var dawn_k := 1.0 if day == 1 else since / ColonyData.DAWN   # o primeiro dia já começa claro
			return clampf(minf(dawn_k, phase_t / ColonyData.DUSK), 0.0, 1.0)
		"night":
			return 0.0
	return 0.6


## Servidor: um jogador pediu a noite (N). Começa quando metade do grupo pediu.
func request_night(pid: int) -> void:
	if phase != "day":
		return
	votes[pid] = true
	var need := votes_needed()
	if votes.size() >= need:
		start_night(true)
	else:
		say("%s quer chamar a noite (%d/%d) — aperte N para concordar." % [_actor_name(), votes.size(), need], Color(1, 0.75, 0.5))
		_dirty()


## forced = o relógio acabou (ou o grupo votou); no cliente vira pedido/voto.
func start_night(forced := false) -> void:
	if role == "client":
		Lobby.city_request("night", [])
		return
	if role == "server" and not forced:
		request_night(actor)
		return
	if phase != "day":
		return
	phase = "night"
	phase_t = 0.0
	_dawn_pending = false
	night_kills = 0
	votes.clear()
	night_mod = next_mod if is_coop() else ""
	next_mod = ""
	if role == "server":
		team_size = maxi(1, Lobby.city_team_size())
		Lobby.city_night_started()
	wave_queue = _build_wave_coop(day) if is_coop() else _build_wave(day)
	wave_total = wave_queue.size()
	_spawn_i = 0
	var ndirs := 1 if day < 3 else (2 if day < 6 else 3)
	if is_coop() and day >= 12:
		ndirs = 4
	var first := randi() % 8
	wave_dirs = [first]
	while wave_dirs.size() < ndirs:
		var d: int = (first + [3, 5, 2, 6, 4][wave_dirs.size() - 1] + randi() % 2) % 8
		if d not in wave_dirs:
			wave_dirs.append(d)
	var names: Array[String] = []
	for d in wave_dirs:
		names.append(DIR_NAMES[d])
	var has_boss := "goblin_king" in wave_queue
	say("Noite %d: %d monstros vêm do %s!" % [day, wave_total, " e do ".join(names)], Color(1, 0.45, 0.35))
	if night_mod != "":
		var m: Dictionary = ColonyData.NIGHT_MODS[night_mod]
		say("%s: %s!" % [m.name, m.desc], m.color)
	if has_boss:
		say("O Rei Goblin lidera o ataque desta noite!" if wave_queue.count("goblin_king") == 1
			else "%d Reis Goblin lideram o ataque desta noite!" % wave_queue.count("goblin_king"), Color(1, 0.35, 0.25))
	Sfx.play("slam", 0.0, -2.0)
	# os animais se escondem à noite (menos os que estão perto de alguém)
	for a in get_tree().get_nodes_in_group("animals"):
		if a.colony != self:
			continue
		var p := nearest_player(a.global_position)
		if p == null or a.global_position.distance_to(p.global_position) > 25.0:
			if role == "server":
				amap.erase(a.net_id)
				Lobby.city_animal_removed(a, false)
			a.queue_free()
	_dirty()


func _build_wave(n: int) -> Array:
	var budget := 6.0 + n * 4.0 + n * n * 0.4
	var out: Array = []
	if n % ColonyData.BOSS_EVERY == 0:
		budget *= 0.7
	var weights := {"slime": 3.0, "slime_veloz": 1.4, "goblin": 2.0, "slime_grande": 1.0, "goblin_bruto": 0.5 + 0.1 * n}
	_fill_wave(out, budget, n, weights)
	out.shuffle()
	if n % ColonyData.BOSS_EVERY == 0:
		out.append("goblin_king")
	return out


## Onda do cooperativo: escala com o grupo; acima do teto, o excesso vira vida (menos monstros, mais duros);
## as noites avançadas trocam monstros fracos por pesados.
func _build_wave_coop(n: int) -> Array:
	var budget := (6.0 + n * 4.0 + n * n * 0.4) * (1.0 + ColonyData.TEAM_BUDGET * (team_size - 1))
	if night_mod == "enxame":
		budget *= 1.6
	var boss_night := n % ColonyData.BOSS_EVERY == 0
	if boss_night:
		budget *= 0.7
	var cap := ColonyData.WAVE_CAP * (1.0 + 0.35 * (team_size - 1))
	_overflow_hp = 1.0
	if budget > cap:
		_overflow_hp = budget / cap
		budget = cap
	var weights := {"slime": maxf(0.6, 3.0 - 0.15 * n), "slime_veloz": 1.4, "goblin": 2.0 + 0.05 * n,
		"slime_grande": 1.0 + 0.08 * n, "goblin_bruto": 0.5 + 0.12 * n}
	if night_mod == "cerco":
		weights.goblin_bruto *= 3.0
	var out: Array = []
	_fill_wave(out, budget, n, weights)
	out.shuffle()
	if boss_night:
		var kings := 1 + (1 if n >= 15 else 0) + (1 if n >= 25 else 0)
		for i in kings:
			out.append("goblin_king")
	return out


func _fill_wave(out: Array, budget: float, n: int, weights: Dictionary) -> void:
	var guard := 0
	while budget >= 1.0 and guard < 400:
		guard += 1
		var pool: Array = []
		var total := 0.0
		for k in ColonyData.WAVE_COSTS:
			var c: Array = ColonyData.WAVE_COSTS[k]
			if int(c[1]) <= n and float(c[0]) <= budget:
				pool.append(k)
				total += weights[k]
		if pool.is_empty():
			break
		var r := randf() * total
		var pick: String = pool[0]
		for k in pool:
			r -= weights[k]
			if r <= 0.0:
				pick = k
				break
		out.append(pick)
		budget -= float(ColonyData.WAVE_COSTS[pick][0])


func spawn_point(dir_index: int) -> Vector3:
	var center := hall.global_position if hall and is_instance_valid(hall) else Vector3.ZERO
	var a := -PI / 2 + dir_index * TAU / 8.0          # 0 = norte (-Z), sentido horário
	var dir := Vector3(cos(a), 0, sin(a))
	var p := center + dir * ColonyData.SPAWN_DIST
	var lim := ColonyData.MAP_HALF - 10.0
	p.x = clampf(p.x, -lim, lim)
	p.z = clampf(p.z, -lim, lim)
	return p


func _spawn_next() -> void:
	var kind: String = wave_queue.pop_front()
	var d: int = wave_dirs[_spawn_i % wave_dirs.size()]
	_spawn_i += 1
	var base := spawn_point(d)
	var center := hall.global_position if hall and is_instance_valid(hall) else Vector3.ZERO
	var out := base - center
	out.y = 0.0
	var side := Vector3(-out.z, 0, out.x).normalized() if out.length() > 1.0 else Vector3.RIGHT
	var pos := base + side * randf_range(-7.0, 7.0) + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
	if kind == "goblin_king":
		var tier := day / ColonyData.BOSS_EVERY
		# o rei tem 900 de vida-base: hp_mult = vida desejada / 900
		var mult := 0.8 + 0.5 * tier
		if is_coop():
			mult *= pow(ColonyData.VETERAN_RATE, maxi(0, day - ColonyData.VETERAN_NIGHT)) * (1.0 + 0.2 * (team_size - 1))
		var e := spawn_enemy(kind, pos, mult)
		boss = e
		FX.ring(e.global_position, Color(1, 0.3, 0.1, 0.9), 6.0, 0.8)
		if world and world.get("hud"):
			world.hud.boss = e
		return
	spawn_enemy(kind, pos, -1.0, _roll_affix() if is_coop() else "")


## Elite aleatório (cooperativo, a partir de ColonyData.ELITE_NIGHT).
func _roll_affix() -> String:
	if day < ColonyData.ELITE_NIGHT:
		return ""
	var chance := minf(ColonyData.ELITE_MAX, ColonyData.ELITE_STEP * (day - ColonyData.ELITE_NIGHT + 1))
	if randf() >= chance:
		return ""
	var pool: Array = []
	for k in ColonyData.AFFIXES:
		if day >= int(ColonyData.AFFIXES[k].get("night", 0)):
			pool.append(k)
	return pool.pick_random()


## boss_mult >= 0: vida fixa do chefe (hp_mult = boss_mult). affix = elite (cooperativo).
func spawn_enemy(kind: String, pos: Vector3, boss_mult := -1.0, affix := "") -> Enemy:
	var e: Enemy = ENEMY.new()
	e.kind = kind
	e.siege = true
	if boss_mult >= 0.0:
		e.hp_mult = boss_mult
	elif is_coop():
		e.hp_mult = ColonyData.coop_hp_mult(day) * (1.0 + ColonyData.TEAM_HP * (team_size - 1)) * _overflow_hp \
			* (0.65 if night_mod == "enxame" else 1.0)
	else:
		e.hp_mult = 1.0 + 0.12 * (day - 1)
	e.dmg_mult = 1.0 + 0.07 * (day - 1)
	if is_coop() and night_mod == "lua_sangue":
		e.dmg_mult *= 1.25
		e.speed_mult *= 1.25
	if affix != "":
		var a: Dictionary = ColonyData.AFFIXES[affix]
		e.affix = affix
		e.hp_mult *= float(a.hp)
		e.speed_mult *= float(a.speed)
	e.position = Vector3(pos.x, 0.3, pos.z)
	add_child(e)
	e.died.connect(_on_enemy_died)
	if role == "server" and affix != "":
		Lobby.city_enemy_meta(e)
	return e


## Chamado pelo Rei Goblin enfurecido (get_parent().summon_minions).
func summon_minions(pos: Vector3, n: int) -> void:
	if phase == "over":
		return
	for i in n + 1:
		var a := TAU * i / (n + 1)
		spawn_enemy("goblin", pos + Vector3(cos(a) * 4.0, 0, sin(a) * 4.0))


func _on_enemy_died(e: Enemy) -> void:
	if e.siege:
		night_kills += 1
		total_kills += 1
		_dirty()
	if e == boss:
		say("O Rei Goblin caiu! +80 ouro de recompensa.", Color(1, 0.85, 0.3))
		earn(80)


## Servidor: monstro da cidade morto (o ouro vai para o cofre; elites valem o dobro).
func on_net_kill(e: Enemy) -> void:
	var g: Array = e.data.gold
	var amount := randi_range(int(g[0]), int(g[1]))
	if e.affix != "":
		amount *= 2
	earn(amount)


func _end_night() -> void:
	var survivors := siege_alive()
	say("O ataque da noite %d foi contido! (%d abates)" % [day, night_kills] if survivors == 0
		else "Amanhece... %d monstros ainda rondam a cidade." % survivors, Color(0.6, 1, 0.6))
	Sfx.play("levelup", 0.0, -2.0)
	await get_tree().create_timer(2.5, false).timeout
	if phase == "night":
		dawn()


## Amanhecer: impostos, comércio, colheita, salários, comida e crescimento da população.
func dawn() -> void:
	var f := forecast()
	earn(int(f.gold_in))
	# salários: quem não recebe deserta
	var due := int(f.salaries)
	var deserters := 0
	if get_gold() >= due:
		_pay(due)
	else:
		var list := soldiers()
		list.sort_custom(func(a, b) -> bool: return int(a.data.salary) < int(b.data.salary))
		var paid := 0
		for s in list:
			if get_gold() - paid >= int(s.data.salary):
				paid += int(s.data.salary)
			else:
				s.leave()
				deserters += 1
		_pay(paid)
		due = paid
	# manutenção (cooperativo): sem ouro, as torres se desgastam
	var up := int(f.upkeep)
	var unpaid := 0
	if up > 0:
		var pay := mini(up, maxi(0, get_gold()))
		_pay(pay)
		unpaid = up - pay
		if unpaid > 0:
			for b in buildings():
				if ColonyData.UPKEEP.has(b.kind):
					b.hp = maxf(1.0, b.hp - b.max_hp * 0.15)
					if role == "server":
						Lobby.city_building_changed(b)
	var eaten := citizens + soldier_count()
	food += int(f.food_in) - eaten
	var starved := 0
	if food < 0:
		starved = mini(citizens, int(ceil(-food / 2.0)))
		citizens -= starved
		food = 0
	if citizens > pop_cap():
		citizens = pop_cap()
	var survived := day
	last_report = {"day": day, "gold_in": f.gold_in, "tax": f.tax, "trade": f.trade, "hall": f.hall,
		"salaries": due, "upkeep": up - unpaid, "deserters": deserters, "food_in": f.food_in, "food_out": f.food_out,
		"starved": starved, "kills": night_kills}
	day += 1
	phase = "day"
	phase_t = day_length
	if nature:
		nature.regrow(day)
	night_mod = ""
	_warned = false
	Game.stats_changed.emit()
	if world and world.get("hud") and world.hud.boss == boss:
		world.hud.boss = null
	for s in soldiers():
		s.hp = minf(s.max_hp, s.hp + s.max_hp * 0.5)
	say("Amanhecer do dia %d: +%d ouro (impostos %d, comércio %d, prefeitura %d), salários −%d." %
		[day, f.gold_in, f.tax, f.trade, f.hall, due], Color(1, 0.9, 0.5))
	if up > 0:
		say("Manutenção das torres e quartéis: −%d ouro." % (up - unpaid) if unpaid == 0
			else "Faltou ouro para a manutenção (%d): as torres e quartéis se desgastaram!" % unpaid,
			Color(1, 0.85, 0.5) if unpaid == 0 else UITheme.BAD)
	say("Comida: +%d colhida, −%d consumida (estoque %d) · aldeões %+d." %
		[f.food_in, eaten, food, -starved], Color(0.8, 1.0, 0.6))
	if deserters > 0:
		say("%d soldado(s) desertaram por falta de pagamento!" % deserters, UITheme.BAD)
		assign_posts.call_deferred()
	if starved > 0:
		say("Fome! %d morador(es) abandonaram a cidade." % starved, UITheme.BAD)
	if is_coop():
		_coop_dawn(survived)
	_spawn_wildlife(true)
	_dirty()
	if world and world.has_method("autosave"):
		world.autosave()


## Amanhecer do cooperativo: recuperação da prefeitura, ajuda do reino, eventos, aviso da próxima noite
## e a recompensa de quem segurou a noite.
func _coop_dawn(survived: int) -> void:
	if hall and is_instance_valid(hall) and not hall.dead and hall.hp < hall.max_hp:
		hall.hp = minf(hall.max_hp, hall.hp + hall.max_hp * 0.25)
		if role == "server":
			Lobby.city_building_changed(hall)
	var broke := get_gold() < 60 or (hall != null and is_instance_valid(hall) and hall.hp < hall.max_hp * 0.4)
	if day >= 3 and broke and day - _aid_day >= 4:
		_aid_day = day
		var aid := 100 + 25 * day
		earn(aid)
		say("Ajuda do reino: chegaram %d ouro para reerguer a cidade." % aid, Color(0.6, 0.9, 1.0))
	elif day >= 3 and randf() < 0.25:
		match randi() % 3:
			0:
				var g := 40 + 12 * day
				earn(g)
				say("Uma caravana de mercadores passou: +%d ouro." % g, Color(1, 0.9, 0.5))
			1:
				var room := maxi(0, pop_cap() - citizens)
				var n := mini(room, 2 + day / 4)
				if n > 0:
					citizens += n
					say("Refugiados chegaram e pediram abrigo: +%d moradores." % n, Color(0.8, 1.0, 0.7))
				else:
					food += 20 + 4 * day
					say("Viajantes deixaram mantimentos: +%d comida." % (20 + 4 * day), Color(0.8, 1.0, 0.6))
			_:
				food += 25 + 5 * day
				say("Colheita farta nos campos: +%d comida." % (25 + 5 * day), Color(0.8, 1.0, 0.6))
	if day >= ColonyData.MOD_NIGHT:
		var chance := 0.4 + (0.3 if day % ColonyData.BOSS_EVERY == 0 else 0.0)
		if randf() < chance:
			next_mod = ColonyData.NIGHT_MODS.keys().pick_random()
			var m: Dictionary = ColonyData.NIGHT_MODS[next_mod]
			say("Os batedores avisam: esta noite será de %s (%s). Preparem-se!" % [m.name, m.desc], m.color)
	if role == "server":
		Lobby.city_night_survived(survived)


# ================================================================ caça e vida selvagem
func _spawn_wildlife(refresh: bool) -> void:
	if role == "client" or hall == null or not is_instance_valid(hall):
		return
	var animals := 0
	for a in get_tree().get_nodes_in_group("animals"):
		if a.colony == self:
			animals += 1
	var want := 12
	var n := 0
	while animals < want and n < (6 if refresh else 1):
		var p := _wild_point(ColonyData.CITY_RADIUS + 14.0)
		if p == Vector3.INF:
			break
		var r := randf()
		var kind := "rabbit" if r < 0.35 else ("deer" if r < 0.78 else "boar")
		var group := 1 if kind == "boar" else randi_range(1, 3)
		for i in group:
			var a: ColonyAnimal = ANIMAL.new()
			a.kind = kind
			a.colony = self
			a.position = p + Vector3(randf_range(-2, 2), 0.3, randf_range(-2, 2))
			if role == "server":
				a.net_id = _new_id()
				amap[a.net_id] = a
			add_child(a)
			if role == "server":
				Lobby.city_animal_added(a)
			animals += 1
		n += 1
	if refresh:
		# monstros errantes longe da cidade: tornam a caçada perigosa
		var wild := 0
		for c in get_children():
			if c is Enemy and not c.siege and not c.dead:
				wild += 1
		for i in clampi(2 + day / 2, 2, 6) - wild:
			var p := _wild_point(ColonyData.CITY_RADIUS + 30.0)
			if p == Vector3.INF:
				break
			var e: Enemy = ENEMY.new()
			e.kind = "goblin" if day >= 3 and randf() < 0.4 else "slime"
			e.position = p + Vector3.UP * 0.3
			add_child(e)


func _wild_point(min_dist: float) -> Vector3:
	var center := hall.global_position
	var lim := ColonyData.MAP_HALF - 12.0
	for i in 30:
		var p := Vector3(randf_range(-lim, lim), 0, randf_range(-lim, lim))
		if Vector2(p.x - center.x, p.z - center.z).length() < min_dist:
			continue
		var ok := true
		for o in obstacles:
			if Vector2(p.x, p.z).distance_to(o[0]) < float(o[1]) + 1.5:
				ok = false
				break
		if ok:
			return p
	return Vector3.INF


func on_animal_killed(a: ColonyAnimal) -> void:
	var f := int(a.data.food)
	var g := int(a.data.gold)
	food += f
	earn(g)
	FX.damage_number(a.global_position + Vector3.UP * 1.6, "+%d comida  +%d ouro" % [f, g], Color(0.75, 1.0, 0.5), 44)
	say("Caça: %s — +%d comida, +%d ouro (couro)." % [a.display_name, f, g], Color(0.75, 1.0, 0.5))
	Sfx.play("coin", 0.1, -2.0)
	if role == "server":
		amap.erase(a.net_id)
		Lobby.city_animal_removed(a, true)
	_dirty()


# ================================================================ eventos
func on_soldier_died(s: ColonySoldier) -> void:
	say("Um %s caiu em combate." % s.data.name, Color(1, 0.6, 0.5))
	assign_posts.call_deferred()


func on_core_hit() -> void:
	if _core_warn <= 0.0:
		_core_warn = 12.0
		say("A prefeitura está sob ataque!", UITheme.BAD)


func _on_building_destroyed(b: ColonyBuilding) -> void:
	if role == "server":
		bmap.erase(b.net_id)
		Lobby.city_building_removed(b, true)
		_dirty()
	if b.is_core:
		defeat()
		return
	say("%s foi destruída!" % b.data.name, Color(1, 0.55, 0.45))
	if b.kind == "barracks":
		_check_army_cap.call_deferred()
	if b.kind == "house":
		_check_housing()


func defeat() -> void:
	if phase == "over":
		return
	phase = "over"
	say("A prefeitura caiu! A cidade foi tomada pelos monstros.", UITheme.BAD)
	Sfx.play("death", 0.0)
	_dirty()
	if world and world.has_method("on_defeat"):
		world.on_defeat()


# ================================================================ rede (cooperativo)
## Servidor: pedido de um jogador. Devolve "" ou o motivo da recusa (vai só para ele).
func net_request(pid: int, action: String, args: Array) -> String:
	actor = pid
	var err := ""
	match action:
		"place":
			if args.size() == 4 and args[0] is String:
				var pos := Vector3(float(args[1]), 0, float(args[2]))
				err = can_place(args[0], pos, float(args[3]))
				if err == "":
					place(args[0], pos, float(args[3]))
		"demolish":
			var b = bmap.get(int(args[0])) if args.size() == 1 else null
			if b and is_instance_valid(b):
				demolish(b)
		"upgrade":
			var b = bmap.get(int(args[0])) if args.size() == 1 else null
			if b and is_instance_valid(b) and not b.dead:
				err = upgrade(b)
		"repair":
			var b = bmap.get(int(args[0])) if args.size() == 1 else null
			if b and is_instance_valid(b) and not b.dead:
				err = repair(b)
		"repair_all":
			err = repair_all()
		"tax":
			if args.size() == 1:
				set_tax(int(args[0]))
		"train":
			err = train_villager()
		"recruit":
			if args.size() == 1 and ColonyData.UNITS.has(str(args[0])):
				err = recruit(str(args[0]))
		"dismiss":
			var s = smap.get(int(args[0])) if args.size() == 1 else null
			if s and is_instance_valid(s):
				dismiss(s)
		"rally":
			if args.size() == 2:
				var p := Vector3(float(args[0]), 0, float(args[1]))
				if hall and is_instance_valid(hall) and Vector2(p.x - hall.global_position.x, p.z - hall.global_position.z).length() <= ColonyData.CITY_RADIUS + 12.0:
					set_rally(p)
					if army_mode == "follow":
						toggle_army_mode()
				else:
					err = "O ponto de reunião precisa ficar perto da cidade."
		"army":
			toggle_army_mode()
		"night":
			request_night(pid)
	actor = 0
	return err


## Servidor: o estado resumido mandado aos clientes (2x/s e a cada mudança).
func net_state() -> Dictionary:
	_state_dirty = false
	return {"gold": gold, "food": food, "res": res, "cit": citizens, "tq": train_queue, "tt": train_t, "day": day, "phase": phase, "pt": phase_t,
		"tax": tax_level, "army": army_mode, "rally": [rally.x, rally.z], "wl": wave_left(), "wt": wave_total,
		"wd": wave_dirs, "nk": night_kills, "tk": total_kills, "nm": night_mod, "xm": next_mod,
		"hall": hall.net_id if hall and is_instance_valid(hall) else 0, "votes": votes.size(), "team": team_size,
		"rep": last_report, "dl": day_length, "fb": first_day_bonus}


func state_dirty() -> bool:
	return _state_dirty


## Cliente: aplica o estado do servidor.
func apply_state(d: Dictionary) -> void:
	gold = int(d.get("gold", gold))
	food = int(d.get("food", food))
	var rs: Dictionary = d.get("res", res)
	for r in rs:
		res[r] = int(rs[r])
	citizens = int(d.get("cit", citizens))
	train_queue = int(d.get("tq", train_queue))
	train_t = float(d.get("tt", train_t))
	day = int(d.get("day", day))
	var new_phase := str(d.get("phase", phase))
	phase_t = float(d.get("pt", phase_t))
	tax_level = int(d.get("tax", tax_level))
	army_mode = str(d.get("army", army_mode))
	var r: Array = d.get("rally", [])
	if r.size() == 2:
		var rp := Vector3(float(r[0]), 0, float(r[1]))
		if rp != rally and rp != Vector3.ZERO:
			set_rally(rp, true)
	_net_wave_left = int(d.get("wl", 0))
	wave_total = int(d.get("wt", wave_total))
	wave_dirs = d.get("wd", wave_dirs)
	night_kills = int(d.get("nk", night_kills))
	total_kills = int(d.get("tk", total_kills))
	night_mod = str(d.get("nm", ""))
	next_mod = str(d.get("xm", ""))
	_net_votes = int(d.get("votes", 0))
	team_size = int(d.get("team", team_size))
	last_report = d.get("rep", last_report)
	day_length = float(d.get("dl", day_length))
	first_day_bonus = float(d.get("fb", first_day_bonus))
	var hid := int(d.get("hall", 0))
	if hid != 0 and bmap.has(hid):
		hall = bmap[hid]
	if new_phase != phase:
		if new_phase == "day" and world and world.get("hud") and world.hud.boss != null:
			world.hud.boss = null
		phase = new_phase
	net_changed.emit()


## Servidor: tudo o que um jogador precisa para entrar na cidade em andamento.
func net_full() -> Dictionary:
	var bl: Array = []
	for b in buildings():
		bl.append([b.net_id, b.kind, b.global_position.x, b.global_position.z, b.rotation.y, b.level, b.hp, b.invested])
	var sl: Array = []
	for s in soldiers():
		sl.append([s.net_id, s.unit, s.global_position.x, s.global_position.z, s.hp])
	var al: Array = []
	for a in get_tree().get_nodes_in_group("animals"):
		if a.colony == self and not a.dead:
			al.append([a.net_id, a.kind, a.global_position.x, a.global_position.z])
	return {"state": net_state(), "buildings": bl, "soldiers": sl, "animals": al,
		"nodes": nature.depleted.keys() if nature else []}


## Servidor: posições dos soldados e animais e a vida das construções que mudou.
func net_snapshot(force_bhp := false) -> Array:
	var ss := PackedFloat32Array()
	for s in soldiers():
		var p: Vector3 = s.global_position
		ss.append_array([s.net_id, p.x, p.y, p.z, s.model.rotation.y, s.hp, 1.0 if s.attacking() else 0.0])
	var aa := PackedFloat32Array()
	for a in get_tree().get_nodes_in_group("animals"):
		if a.colony != self or a.dead:
			continue
		var p: Vector3 = a.global_position
		aa.append_array([a.net_id, p.x, p.y, p.z, a.model.rotation.y])
	var bh := PackedFloat32Array()
	for b in buildings():
		if force_bhp or absf(b.hp - b.net_sent_hp) > 0.5:
			b.net_sent_hp = b.hp
			bh.append_array([b.net_id, b.hp])
	return [ss, aa, bh]


## Cliente: aplica o snapshot do servidor.
func apply_snapshot(ss: PackedFloat32Array, aa: PackedFloat32Array, bh: PackedFloat32Array) -> void:
	var i := 0
	while i + 7 <= ss.size():
		var s = smap.get(int(ss[i]))
		if s and is_instance_valid(s) and not s.dead:
			s.apply_net(Vector3(ss[i + 1], ss[i + 2], ss[i + 3]), ss[i + 4], ss[i + 5], ss[i + 6] > 0.5)
		i += 7
	i = 0
	while i + 5 <= aa.size():
		var a = amap.get(int(aa[i]))
		if a and is_instance_valid(a) and not a.dead:
			a.apply_net(Vector3(aa[i + 1], aa[i + 2], aa[i + 3]), aa[i + 4])
		i += 5
	i = 0
	while i + 2 <= bh.size():
		var b = bmap.get(int(bh[i]))
		if b and is_instance_valid(b) and not b.dead:
			b.net_set_hp(bh[i + 1])
		i += 2


## Cliente: réplica de uma construção.
func net_building_add(id: int, kind: String, x: float, z: float, rot: float, level: int, hp: float, invested: Dictionary, fx := true) -> void:
	if bmap.has(id) or not ColonyData.BUILDINGS.has(kind):
		return
	var b: ColonyBuilding = BUILDING.new()
	b.kind = kind
	b.level = clampi(level, 1, ColonyData.MAX_LEVEL)
	b.hp = maxf(1.0, hp)
	b.colony = self
	b.puppet = true
	b.net_id = id
	b.invested = invested
	b.position = Vector3(x, 0.0, z)
	b.rotation.y = rot
	add_child(b)
	bmap[id] = b
	if kind == "town_hall":
		hall = b
		if world and world.get("build") and world.build.active and world.build.selected == "town_hall":
			world.build.select("house")
	if fx:
		Sfx.play_at("plant", b.global_position, 0.1, 0.0)
		FX.burst(b.global_position + Vector3.UP * 0.5, Color(0.75, 0.65, 0.45), 30, 5.0, 0.15, 0.8)
		FX.ring(b.global_position, Color(1, 0.9, 0.6, 0.8), maxf(b.size.x, b.size.y) * 0.6, 0.4)
	net_changed.emit()


func net_building_set(id: int, level: int, hp: float, invested: Dictionary) -> void:
	var b = bmap.get(id)
	if b == null or not is_instance_valid(b) or b.dead:
		return
	b.invested = invested
	if level != b.level:
		b.set_level(level)
	b.net_set_hp(hp)
	net_changed.emit()


func net_building_remove(id: int, destroyed: bool) -> void:
	var b = bmap.get(id)
	bmap.erase(id)
	if b == null or not is_instance_valid(b) or b.dead:
		return
	if destroyed:
		b.net_destroy()
	else:
		b.dead = true
		b.remove_from_group("buildings")
		b.remove_from_group("interactable")
		FX.burst(b.global_position + Vector3.UP, Color(0.6, 0.5, 0.4), 30, 5.0, 0.15, 0.8)
		b.queue_free()
	if b == hall:
		hall = null
	net_changed.emit()


func net_soldier_add(id: int, unit: String, x: float, z: float, hp: float, fx := true) -> void:
	if smap.has(id) or not ColonyData.UNITS.has(unit):
		return
	var s: ColonySoldier = SOLDIER.new()
	s.unit = unit
	s.colony = self
	s.hp = hp
	s.puppet = true
	s.net_id = id
	s.position = Vector3(x, 0.0, z)
	add_child(s)
	smap[id] = s
	if fx:
		FX.burst(s.global_position + Vector3.UP, Color(0.5, 0.7, 1.0), 25, 4.0, 0.12, 0.8)
	net_changed.emit()


func net_soldier_remove(id: int, died: bool) -> void:
	var s = smap.get(id)
	smap.erase(id)
	if s == null or not is_instance_valid(s) or s.dead:
		return
	if died:
		s.net_die()
	else:
		s.leave()
	net_changed.emit()


func net_animal_add(id: int, kind: String, x: float, z: float) -> void:
	if amap.has(id) or not ColonyData.ANIMALS.has(kind):
		return
	var a: ColonyAnimal = ANIMAL.new()
	a.kind = kind
	a.colony = self
	a.puppet = true
	a.net_id = id
	a.position = Vector3(x, 0.3, z)
	add_child(a)
	amap[id] = a


func net_animal_remove(id: int, killed: bool) -> void:
	var a = amap.get(id)
	amap.erase(id)
	if a == null or not is_instance_valid(a) or a.dead:
		return
	if killed:
		a.net_die()
	else:
		a.queue_free()


# ================================================================ save
func to_dict() -> Dictionary:
	var bl: Array = []
	for b in buildings():
		bl.append({"kind": b.kind, "x": b.global_position.x, "z": b.global_position.z, "rot": b.rotation.y,
			"level": b.level, "hp": b.hp, "invested": b.invested})
	var sl: Array = []
	for s in soldiers():
		sl.append({"unit": s.unit, "hp": s.hp, "x": s.global_position.x, "z": s.global_position.z})
	return {"version": 2, "seed": world.map_seed if world else 7731, "nodes": nature.to_dict() if nature else {},
		"res": res, "day": day, "phase": phase, "phase_t": phase_t, "food": food, "citizens": citizens,
		"tax": tax_level, "army_mode": army_mode, "rally": [rally.x, rally.z], "kills": total_kills, "train": train_queue,
		"buildings": bl, "soldiers": sl}


func from_dict(d: Dictionary) -> void:
	day = int(d.get("day", 1))
	food = int(d.get("food", 0))
	if d.has("res"):
		res = {"wood": 0, "stone": 0, "iron": 0, "crystal": 0}
		for r in d.res:
			res[r] = int(d.res[r])
	else:
		_reset_res(0)   # save da versão 1: estoque inicial de madeira e pedra
	citizens = int(d.get("citizens", 0))
	train_queue = int(d.get("train", 0))
	train_t = 0.0
	tax_level = clampi(int(d.get("tax", 1)), 0, 2)
	army_mode = str(d.get("army_mode", "guard"))
	total_kills = int(d.get("kills", 0))
	phase = "loading"
	for bd in d.get("buildings", []):
		var kind := str(bd.kind)
		if not ColonyData.BUILDINGS.has(kind):
			continue
		var b := place(kind, Vector3(float(bd.x), 0, float(bd.z)), float(bd.rot), true,
			clampi(int(bd.get("level", 1)), 1, ColonyData.MAX_LEVEL), maxf(1.0, float(bd.get("hp", 99999.0))))
		b.invested = ColonyData.cost_from(bd.get("invested", b.invested))
	var r: Array = d.get("rally", [])
	if r.size() == 2:
		set_rally(Vector3(float(r[0]), 0, float(r[1])), true)
	for sd in d.get("soldiers", []):
		if ColonyData.UNITS.has(str(sd.unit)):
			spawn_soldier(str(sd.unit), Vector3(float(sd.x), 0, float(sd.z)), float(sd.get("hp", -1.0)))
	if nature:
		nature.from_dict(d.get("nodes", {}))
	if hall != null:
		phase = "day"
		phase_t = clampf(float(d.get("phase_t", day_length)), 20.0, day_length + first_day_bonus)
		_spawn_wildlife(true)
	else:
		phase = "setup"
	Game.stats_changed.emit()


# ================================================================ geometria (retângulos girados)
## Retângulo no plano XZ: [centro, eixo x, eixo z, meia largura, meia profundidade]
func _rect(c: Vector2, rot: float, size: Vector2) -> Array:
	return [c, Vector2(cos(rot), -sin(rot)), Vector2(sin(rot), cos(rot)), size.x / 2.0 - 0.05, size.y / 2.0 - 0.05]


func _overlap(a: Array, b: Array) -> bool:
	var d: Vector2 = b[0] - a[0]
	for axis in [a[1], a[2], b[1], b[2]]:
		var ra: float = a[3] * absf(a[1].dot(axis)) + a[4] * absf(a[2].dot(axis))
		var rb: float = b[3] * absf(b[1].dot(axis)) + b[4] * absf(b[2].dot(axis))
		if absf(d.dot(axis)) >= ra + rb:
			return false
	return true


func _circle_hits(rect: Array, p: Vector2, r: float) -> bool:
	var d: Vector2 = p - rect[0]
	var lx := clampf(d.dot(rect[1]), -rect[3], rect[3])
	var lz := clampf(d.dot(rect[2]), -rect[4], rect[4])
	var closest: Vector2 = rect[0] + rect[1] * lx + rect[2] * lz
	return closest.distance_to(p) < r
