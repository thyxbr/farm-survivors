class_name Colony
extends Node3D
## Estado da Defesa da Cidade: economia (ouro, comida, moradores, impostos, salários),
## ciclo dia/noite, ondas de monstros, caça e as regras de onde se pode construir.
## É o pai das construções, dos soldados, dos animais e dos monstros.

const BUILDING := preload("res://scripts/colony/building.gd")
const SOLDIER := preload("res://scripts/colony/soldier.gd")
const ANIMAL := preload("res://scripts/colony/animal.gd")
const ENEMY := preload("res://scripts/enemies/enemy.gd")

const DIR_NAMES := ["Norte", "Nordeste", "Leste", "Sudeste", "Sul", "Sudoeste", "Oeste", "Noroeste"]

var world: Node
var day := 1
var phase := "setup"          # setup (sem prefeitura) | day | night | over
var phase_t := 0.0            # dia: segundos restantes · noite: segundos passados
var food := 0
var citizens := 0
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

var _spawn_acc := 0.0
var _spawn_i := 0
var _warned := false
var _animal_t := 0.0
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
	Game.gold = ColonyData.START_GOLD
	Game.stats_changed.emit()


# ================================================================ consultas
func buildings() -> Array:
	var out: Array = []
	for b in get_tree().get_nodes_in_group("buildings"):
		if not b.dead:
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
		if not s.dead:
			out.append(s)
	return out


func soldier_count() -> int:
	return soldiers().size()


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


func siege_alive() -> int:
	var n := 0
	for c in get_children():
		if c is Enemy and c.siege and not c.dead:
			n += 1
	return n


func wave_left() -> int:
	return wave_queue.size() + siege_alive()


## Previsão do próximo amanhecer (também usada no relatório).
func forecast() -> Dictionary:
	var workers := 0
	var farm_food := 0.0
	var market_gold := 0.0
	var hall_gold := 0
	for b in buildings():
		workers += int(b.data.get("workers", 0))
		match b.kind:
			"farm":
				farm_food += float(b.data.food) * ColonyData.level_mult(b.level, 0.5)
			"market":
				market_gold += float(b.data.gold) * ColonyData.level_mult(b.level, 0.5)
			"town_hall":
				hall_gold += int(b.data.gold) * b.level
	var eff := 1.0 if workers == 0 else clampf(float(citizens) / workers, 0.0, 1.0)
	var tax: int = citizens * ColonyData.TAX[tax_level]
	var trade := int(round(market_gold * eff))
	var sal := salaries()
	var food_in := int(round(farm_food * eff))
	var food_out := citizens + soldier_count()
	return {
		"tax": tax, "trade": trade, "hall": hall_gold, "salaries": sal,
		"gold_in": tax + trade + hall_gold, "gold_net": tax + trade + hall_gold - sal,
		"food_in": food_in, "food_out": food_out, "food_net": food_in - food_out,
		"workers": workers, "employed": mini(citizens, workers), "eff": eff,
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
		if Vector2(pos.x - hall.global_position.x, pos.z - hall.global_position.z).length() > ColonyData.CITY_RADIUS:
			return "Fora dos limites da cidade."
		if not ignore_cost and Game.gold < int(d.cost):
			return "Ouro insuficiente (%d)." % int(d.cost)
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
			if _circle_hits(rect, Vector2(u.global_position.x, u.global_position.z), 0.45):
				return "Tem alguém no lugar (saia de cima)."
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e.dead and _circle_hits(rect, Vector2(e.global_position.x, e.global_position.z), e.radius):
			return "Tem um monstro no caminho."
	return ""


## Constrói (cobrando o preço, a menos que free). Devolve a construção.
func place(kind: String, pos: Vector3, rot: float, free := false, level := 1, hp := -1.0) -> ColonyBuilding:
	var d := ColonyData.building(kind)
	var b: ColonyBuilding = BUILDING.new()
	b.kind = kind
	b.level = level
	b.hp = hp
	b.colony = self
	b.position = Vector3(pos.x, 0.0, pos.z)
	b.rotation.y = rot
	if not free:
		Game.gold -= int(d.cost)
		Game.stats_changed.emit()
	b.invested = int(d.cost)
	add_child(b)
	b.destroyed.connect(_on_building_destroyed)
	if kind == "town_hall":
		hall = b
		if rally == Vector3.ZERO:
			set_rally(b.global_position + b.global_basis.z * 8.0, true)
		if phase == "setup":
			phase = "day"
			phase_t = ColonyData.DAY_LENGTH + ColonyData.FIRST_DAY_BONUS
			Game.notify.emit("A cidade foi fundada! Construa casas, fazendas e defesas antes da noite.", Color(1, 0.9, 0.5))
			Game.notify.emit("Saia da cidade para caçar: cervos, coelhos e javalis rendem comida e ouro.", Color(0.8, 1.0, 0.6))
			_spawn_wildlife(true)
	if not free:
		Sfx.play("plant", 0.1, 0.0)
		FX.burst(b.global_position + Vector3.UP * 0.5, Color(0.75, 0.65, 0.45), 30, 5.0, 0.15, 0.8)
		FX.ring(b.global_position, Color(1, 0.9, 0.6, 0.8), maxf(d.size.x, d.size.y) * 0.6, 0.4)
	if kind == "barracks" or kind == "town_hall":
		assign_posts.call_deferred()
	return b


func demolish(b: ColonyBuilding) -> void:
	if b == null or b.dead or b.is_core:
		if b and b.is_core:
			Game.notify.emit("A prefeitura não pode ser demolida.", UITheme.BAD)
		return
	var refund := int(b.invested * ColonyData.REFUND)
	Game.add_gold(refund)
	Game.notify.emit("%s demolida: +%d ouro." % [b.data.name, refund], Color(1, 0.85, 0.4))
	b.dead = true
	b.remove_from_group("buildings")
	b.remove_from_group("interactable")
	FX.burst(b.global_position + Vector3.UP, Color(0.6, 0.5, 0.4), 30, 5.0, 0.15, 0.8)
	Sfx.play("hit", 0.1, -4.0)
	b.queue_free()
	_check_army_cap()
	_check_housing()


func upgrade_cost(b: ColonyBuilding) -> int:
	return ColonyData.upgrade_cost(b.kind, b.level)


func upgrade(b: ColonyBuilding) -> String:
	if b.level >= ColonyData.MAX_LEVEL:
		return "Já está no nível máximo."
	if b.kind != "town_hall" and hall and b.level >= hall.level + 1:
		return "Melhore a prefeitura primeiro (nível %d)." % (hall.level + 1)
	var cost := upgrade_cost(b)
	if Game.gold < cost:
		return "Ouro insuficiente (%d)." % cost
	Game.gold -= cost
	b.invested += cost
	b.set_level(b.level + 1)
	Game.stats_changed.emit()
	Sfx.play("levelup", 0.05, -4.0)
	Game.notify.emit("%s melhorada para o nível %d." % [b.data.name, b.level], Color(0.7, 1.0, 0.6))
	assign_posts.call_deferred()
	return ""


func repair_cost(b: ColonyBuilding) -> int:
	if b.hp >= b.max_hp - 0.5:
		return 0
	var base := maxi(int(b.data.cost), 120) * b.level
	return maxi(1, int(ceil((1.0 - b.hp / b.max_hp) * base * ColonyData.REPAIR_RATIO)))


func repair(b: ColonyBuilding) -> String:
	var cost := repair_cost(b)
	if cost <= 0:
		return "Não precisa de reparo."
	if Game.gold < cost:
		return "Ouro insuficiente (%d)." % cost
	Game.gold -= cost
	Game.stats_changed.emit()
	b.repair_full()
	Sfx.play("plant", 0.1, -2.0)
	return ""


func repair_all_cost() -> int:
	var n := 0
	for b in buildings():
		n += repair_cost(b)
	return n


func repair_all() -> String:
	var cost := repair_all_cost()
	if cost <= 0:
		return "Nada para reparar."
	if Game.gold < cost:
		return "Ouro insuficiente (%d)." % cost
	for b in buildings():
		if repair_cost(b) > 0:
			Game.gold -= repair_cost(b)
			b.repair_full()
	Game.stats_changed.emit()
	Sfx.play("plant", 0.1, -2.0)
	return ""


# ================================================================ exército
func recruit(unit: String) -> String:
	var u: Dictionary = ColonyData.UNITS[unit]
	if count_of("barracks") == 0:
		return "Construa um quartel."
	if barracks_level() < int(u.get("needs_level", 1)):
		return "Exige um quartel nível %d." % int(u.needs_level)
	if soldier_count() >= army_cap():
		return "Os quartéis estão lotados (%d vagas)." % army_cap()
	if citizens < 1:
		return "Não há moradores para recrutar. Construa casas."
	if Game.gold < int(u.cost):
		return "Ouro insuficiente (%d)." % int(u.cost)
	Game.gold -= int(u.cost)
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
	add_child(s)
	assign_posts.call_deferred()
	return s


func dismiss(s: ColonySoldier) -> void:
	if s == null or s.dead:
		return
	citizens += 1
	s.leave()
	assign_posts.call_deferred()


func _barracks_door() -> Vector3:
	for b in buildings():
		if b.kind == "barracks":
			return b.global_position + b.global_basis.z * (b.size.y / 2.0 + 1.5)
	return rally


func set_rally(pos: Vector3, silent := false) -> void:
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
		Game.notify.emit("Ponto de reunião do exército definido.", Color(0.6, 0.8, 1.0))
	assign_posts()


func toggle_army_mode() -> void:
	army_mode = "follow" if army_mode == "guard" else "guard"
	if army_mode == "follow":
		Game.notify.emit("Exército: seguindo você.", Color(0.6, 0.8, 1.0))
	else:
		Game.notify.emit("Exército: voltando a defender o ponto de reunião.", Color(0.6, 0.8, 1.0))


## Postos em formação no ponto de reunião (corpo a corpo na frente, arqueiros atrás).
func assign_posts() -> void:
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
		Game.notify.emit("%d morador(es) ficaram sem casa e partiram." % lost, Color(1, 0.6, 0.5))


func _check_army_cap() -> void:
	var extra := soldier_count() - army_cap()
	if extra <= 0:
		return
	var list := soldiers()
	for i in extra:
		dismiss(list[list.size() - 1 - i])
	Game.notify.emit("%d soldado(s) dispensado(s): faltam vagas no quartel." % extra, Color(1, 0.75, 0.5))


# ================================================================ ciclo
func _physics_process(delta: float) -> void:
	_core_warn = maxf(0.0, _core_warn - delta)
	match phase:
		"day":
			phase_t -= delta
			_animal_t -= delta
			if _animal_t <= 0.0:
				_animal_t = 4.0
				_spawn_wildlife(false)
			if phase_t <= 25.0 and not _warned:
				_warned = true
				Game.notify.emit("O sol está se pondo... os monstros atacam ao anoitecer!", Color(1, 0.6, 0.4))
				Sfx.play("quest", 0.0, -4.0)
			if phase_t <= 0.0:
				start_night()
		"night":
			phase_t += delta
			_spawn_acc += delta * (1.1 + 0.12 * day)
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
			var total := ColonyData.DAY_LENGTH + (ColonyData.FIRST_DAY_BONUS if day == 1 else 0.0)
			var since := total - phase_t
			var dawn_k := 1.0 if day == 1 else since / ColonyData.DAWN   # o primeiro dia já começa claro
			return clampf(minf(dawn_k, phase_t / ColonyData.DUSK), 0.0, 1.0)
		"night":
			return 0.0
	return 0.6


func start_night() -> void:
	if phase != "day":
		return
	phase = "night"
	phase_t = 0.0
	_dawn_pending = false
	night_kills = 0
	wave_queue = _build_wave(day)
	wave_total = wave_queue.size()
	_spawn_i = 0
	var ndirs := 1 if day < 3 else (2 if day < 6 else 3)
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
	Game.notify.emit("Noite %d: %d monstros vêm do %s!" % [day, wave_total, " e do ".join(names)], Color(1, 0.45, 0.35))
	if has_boss:
		Game.notify.emit("O Rei Goblin lidera o ataque desta noite!", Color(1, 0.35, 0.25))
	Sfx.play("slam", 0.0, -2.0)
	# os animais se escondem à noite
	var p := get_tree().get_first_node_in_group("player") as Node3D
	for a in get_tree().get_nodes_in_group("animals"):
		if p == null or a.global_position.distance_to(p.global_position) > 25.0:
			a.queue_free()


func _build_wave(n: int) -> Array:
	var budget := 6.0 + n * 4.0 + n * n * 0.4
	var out: Array = []
	if n % ColonyData.BOSS_EVERY == 0:
		budget *= 0.7
	var weights := {"slime": 3.0, "slime_veloz": 1.4, "goblin": 2.0, "slime_grande": 1.0, "goblin_bruto": 0.5 + 0.1 * n}
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
	out.shuffle()
	if n % ColonyData.BOSS_EVERY == 0:
		out.append("goblin_king")
	return out


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
	var e := spawn_enemy(kind, pos)
	if kind == "goblin_king":
		boss = e
		var tier := day / ColonyData.BOSS_EVERY
		e.max_hp = 900.0 * (0.8 + 0.5 * tier)
		e.hp = e.max_hp
		FX.ring(e.global_position, Color(1, 0.3, 0.1, 0.9), 6.0, 0.8)
		if world and world.hud:
			world.hud.boss = e


func spawn_enemy(kind: String, pos: Vector3) -> Enemy:
	var e: Enemy = ENEMY.new()
	e.kind = kind
	e.siege = true
	e.hp_mult = 1.0 + 0.12 * (day - 1)
	e.dmg_mult = 1.0 + 0.07 * (day - 1)
	e.position = Vector3(pos.x, 0.3, pos.z)
	add_child(e)
	e.died.connect(_on_enemy_died)
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
	if e == boss:
		Game.notify.emit("O Rei Goblin caiu! +80 ouro de recompensa.", Color(1, 0.85, 0.3))
		Game.add_gold(80)


func _end_night() -> void:
	var survivors := siege_alive()
	Game.notify.emit("O ataque da noite %d foi contido! (%d abates)" % [day, night_kills] if survivors == 0
		else "Amanhece... %d monstros ainda rondam a cidade." % survivors, Color(0.6, 1, 0.6))
	Sfx.play("levelup", 0.0, -2.0)
	await get_tree().create_timer(2.5, false).timeout
	if phase == "night":
		dawn()


## Amanhecer: impostos, comércio, colheita, salários, comida e crescimento da população.
func dawn() -> void:
	var f := forecast()
	Game.gold += int(f.gold_in)
	# salários: quem não recebe deserta
	var due := int(f.salaries)
	var deserters := 0
	if Game.gold >= due:
		Game.gold -= due
	else:
		var list := soldiers()
		list.sort_custom(func(a, b) -> bool: return int(a.data.salary) < int(b.data.salary))
		var paid := 0
		for s in list:
			if Game.gold - paid >= int(s.data.salary):
				paid += int(s.data.salary)
			else:
				s.leave()
				deserters += 1
		Game.gold -= paid
		due = paid
	var eaten := citizens + soldier_count()
	food += int(f.food_in) - eaten
	var starved := 0
	if food < 0:
		starved = mini(citizens, int(ceil(-food / 2.0)))
		citizens -= starved
		food = 0
	var houses := count_of("house")
	var growth := 0
	if starved == 0 and food > 0:
		growth = clampi(ColonyData.GROWTH[tax_level] + houses / 3, 0, maxi(0, pop_cap() - citizens))
	citizens += growth
	if citizens > pop_cap():
		citizens = pop_cap()
	last_report = {"day": day, "gold_in": f.gold_in, "tax": f.tax, "trade": f.trade, "hall": f.hall,
		"salaries": due, "deserters": deserters, "food_in": f.food_in, "food_out": f.food_out,
		"starved": starved, "growth": growth, "kills": night_kills}
	day += 1
	phase = "day"
	phase_t = ColonyData.DAY_LENGTH
	_warned = false
	Game.stats_changed.emit()
	if world and world.hud and world.hud.boss == boss:
		world.hud.boss = null
	for s in soldiers():
		s.hp = minf(s.max_hp, s.hp + s.max_hp * 0.5)
	Game.notify.emit("Amanhecer do dia %d: +%d ouro (impostos %d, comércio %d, prefeitura %d), salários −%d." %
		[day, f.gold_in, f.tax, f.trade, f.hall, due], Color(1, 0.9, 0.5))
	Game.notify.emit("Comida: +%d colhida, −%d consumida (estoque %d) · moradores %+d." %
		[f.food_in, eaten, food, growth - starved], Color(0.8, 1.0, 0.6))
	if deserters > 0:
		Game.notify.emit("%d soldado(s) desertaram por falta de pagamento!" % deserters, UITheme.BAD)
		assign_posts.call_deferred()
	if starved > 0:
		Game.notify.emit("Fome! %d morador(es) abandonaram a cidade." % starved, UITheme.BAD)
	_spawn_wildlife(true)
	if world and world.has_method("autosave"):
		world.autosave()


# ================================================================ caça e vida selvagem
func _spawn_wildlife(refresh: bool) -> void:
	if hall == null or not is_instance_valid(hall):
		return
	var animals := get_tree().get_nodes_in_group("animals").size()
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
			add_child(a)
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
	Game.add_gold(g)
	FX.damage_number(a.global_position + Vector3.UP * 1.6, "+%d comida  +%d ouro" % [f, g], Color(0.75, 1.0, 0.5), 44)
	Game.notify.emit("Caça: %s — +%d comida, +%d ouro (couro)." % [a.display_name, f, g], Color(0.75, 1.0, 0.5))
	Sfx.play("coin", 0.1, -2.0)


# ================================================================ eventos
func on_soldier_died(s: ColonySoldier) -> void:
	Game.notify.emit("Um %s caiu em combate." % s.data.name, Color(1, 0.6, 0.5))
	assign_posts.call_deferred()


func on_core_hit() -> void:
	if _core_warn <= 0.0:
		_core_warn = 12.0
		Game.notify.emit("A prefeitura está sob ataque!", UITheme.BAD)


func _on_building_destroyed(b: ColonyBuilding) -> void:
	if b.is_core:
		defeat()
		return
	Game.notify.emit("%s foi destruída!" % b.data.name, Color(1, 0.55, 0.45))
	if b.kind == "barracks":
		_check_army_cap.call_deferred()
	if b.kind == "house":
		_check_housing()


func defeat() -> void:
	if phase == "over":
		return
	phase = "over"
	Game.notify.emit("A prefeitura caiu! A cidade foi tomada pelos monstros.", UITheme.BAD)
	Sfx.play("death", 0.0)
	if world and world.has_method("on_defeat"):
		world.on_defeat()


# ================================================================ save
func to_dict() -> Dictionary:
	var bl: Array = []
	for b in buildings():
		bl.append({"kind": b.kind, "x": b.global_position.x, "z": b.global_position.z, "rot": b.rotation.y,
			"level": b.level, "hp": b.hp, "invested": b.invested})
	var sl: Array = []
	for s in soldiers():
		sl.append({"unit": s.unit, "hp": s.hp, "x": s.global_position.x, "z": s.global_position.z})
	return {"version": 1, "day": day, "phase": phase, "phase_t": phase_t, "food": food, "citizens": citizens,
		"tax": tax_level, "army_mode": army_mode, "rally": [rally.x, rally.z], "kills": total_kills,
		"buildings": bl, "soldiers": sl}


func from_dict(d: Dictionary) -> void:
	day = int(d.get("day", 1))
	food = int(d.get("food", 0))
	citizens = int(d.get("citizens", 0))
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
		b.invested = int(bd.get("invested", b.invested))
	var r: Array = d.get("rally", [])
	if r.size() == 2:
		set_rally(Vector3(float(r[0]), 0, float(r[1])), true)
	for sd in d.get("soldiers", []):
		if ColonyData.UNITS.has(str(sd.unit)):
			spawn_soldier(str(sd.unit), Vector3(float(sd.x), 0, float(sd.z)), float(sd.get("hp", -1.0)))
	if hall != null:
		phase = "day"
		phase_t = clampf(float(d.get("phase_t", ColonyData.DAY_LENGTH)), 20.0, ColonyData.DAY_LENGTH + ColonyData.FIRST_DAY_BONUS)
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
