extends SceneTree
## Simulação da economia da Defesa da Cidade (seção 18 do spec: garantia de equilíbrio). Rode com:
##   godot --headless --path . --script res://tests/economy_sim.gd
## Um "jogador razoável" scriptado joga 15 dias em solo, com 2 e com 4 jogadores, usando só as funções e
## tabelas de ColonyData (as mesmas contas do jogo). Imprime o estoque de cada dia, PASS/FAIL para cada meta
## e sai com 1 se alguma falhar.
##
## ColonyData lê ItemDB (autoload) e as tabelas de colony.json são preenchidas pelo autoload Balance; com
## --script os autoloads só existem a partir do primeiro quadro, então o script de ColonyData é carregado
## (load) no _process, e não referenciado pelo nome (o que falharia ao compilar este arquivo).
##
## Modelo de cada dia (simplificado, sem combate nem covis/eventos):
##  · começo do dia: o jogador gasta o estoque seguindo a lista de prioridades (abaixo) e treina aldeões até o
##    pop_cap, guardando a comida da próxima era (mas sempre treina até ter 3 aldeões livres);
##  · durante o dia: serrarias e pedreiras com 8 nós vivos e crew cheio (gather_rate × crew × duração do dia) e a
##    coleta à mão de cada jogador (1,5 × uma serraria cheia: meta "Exploração"), metade numa repartição fixa
##    por era (MANUAL_SPLIT) e metade no que falta para a próxima era;
##  · noite: cada torre de arqueiros dá 60 / rate tiros (~60 s de combate ativo) e gasta ammo_per_night;
##  · amanhecer: imposto normal, mercado, prefeitura, comida, salários e (em grupo) manutenção, como Colony.dawn.
## O que se gasta durante o dia só é gasto no começo do dia seguinte (a madeira da noite mede a regra de bolso).
##
## Lista do jogador, a cada gasto: abertura fixa em ordem (casa, fazenda, serraria, torre de arqueiros, pedreira,
## quartel, mercado; o primeiro que não dá para pagar segura o resto; se faltar aldeão, cuida antes de moradia e
## fazenda); depois casa quando faltar moradia, fazenda até sobrar FOOD_SURPLUS × era de comida por dia, torres
## até a meta de defesa do dia (1 serraria a cada 6 torres), pesquisas da era atual em ordem, a próxima era
## (o quartel nível 2 da era III entra aqui; sem dinheiro, junta para ela) e, na era III, soldados.

const DAYS := 15
const PLAYERS := [1, 2, 4]
const NIGHT_COMBAT := 60.0      # segundos de combate ativo por noite (ordem de grandeza da seção 15)
const OPENING := ["house", "farm", "lumber_camp", "archer_tower", "quarry", "barracks", "market"]
const CAMP_PER_TOWERS := 6      # regra de bolso: uma serraria cheia sustenta ~6 torres de arqueiros
const FOOD_SURPLUS := 40       # o jogador quer sobrar tanta comida por dia (para treinar aldeões e para a era)
## Repartição do dia de coleta de cada jogador (fração do tempo) e quanto cada recurso rende em relação à madeira
## por golpe (árvore 24/4 = 6; pedra 25/5; ferro 12/6; cristal 8/6; veio de ouro 60/6; comida de caça e arbustos
## conta como a madeira). Ferro e cristal só a partir da era II, quando passam a ter uso.
const MANUAL_SPLIT := {1: {"wood": 0.3, "stone": 0.25, "food": 0.3, "gold": 0.15},
	2: {"wood": 0.15, "stone": 0.15, "iron": 0.25, "crystal": 0.15, "food": 0.15, "gold": 0.15},
	3: {"wood": 0.15, "stone": 0.15, "iron": 0.25, "crystal": 0.15, "food": 0.15, "gold": 0.15}}
const MANUAL_YIELD := {"wood": 1.0, "stone": 25.0 / 5.0 / 6.0, "iron": 12.0 / 6.0 / 6.0, "crystal": 8.0 / 6.0 / 6.0,
	"gold": 60.0 / 6.0 / 6.0, "food": 1.0}

var CD: GDScript
var fails := 0
var _started := false

# estado de uma partida
var players := 1
var coop := false
var day := 1
var era := 1
var gold := 0
var food := 0
var res := {}
var citizens := 0
var soldiers := 0
var count := {}
var barracks_lv := 0
var techs: Array = []
var log_rows: Array = []
# métricas
var era2_day := 99
var era3_day := 99
var era1_techs_day := 99
var min_wood_night := 999999
var max_wood_before_12 := 0
var starved := 0


func _process(_dt: float) -> bool:
	if _started:
		return false
	_started = true
	CD = load("res://scripts/colony/colony_data.gd")
	var tables: Array[String] = []
	for p in PLAYERS:
		_run(p)
		tables.append(_table())
		_check_goals()
	print("")
	for t in tables:
		print(t)
	print("%s — %d falha(s)" % ["OK" if fails == 0 else "FALHOU", fails])
	quit(1 if fails > 0 else 0)
	return true


func check(cond: bool, what: String) -> void:
	if cond:
		print("PASS  ", what)
	else:
		fails += 1
		print("FAIL  ", what)


# ================================================================ partida
func _run(p: int) -> void:
	players = p
	coop = p > 1
	day = 1
	era = 1
	techs = []
	soldiers = 0
	barracks_lv = 0
	count = {"town_hall": 1}
	log_rows = []
	era2_day = 99
	era3_day = 99
	era1_techs_day = 99
	min_wood_night = 999999
	max_wood_before_12 = 0
	starved = 0
	res = {"wood": 0, "stone": 0, "iron": 0, "crystal": 0}
	for r in CD.START_RES:
		res[r] = int(CD.START_RES[r])
	if coop:
		gold = CD.COOP_START_GOLD + CD.COOP_GOLD_PER_PLAYER * (p - 1)
		food = CD.COOP_START_FOOD
		citizens = CD.COOP_START_CITIZENS
		res.wood += CD.COOP_WOOD_PER_PLAYER * (p - 1)
	else:
		gold = CD.START_GOLD
		food = CD.START_FOOD
		citizens = CD.START_CITIZENS
	print("\n=== %d jogador(es) ===" % p)
	print("dia era  ouro comida madeira pedra ferro crist ald sold torres pesq munição mad-noite  casa/faz/serr/ped/merc/quartel")
	for d in range(1, DAYS + 1):
		day = d
		var day_len: float = CD.DAY_LENGTH + (CD.FIRST_DAY_BONUS if d == 1 else 0.0)
		_spend()
		_train()
		_produce(day_len)
		if d < 12:
			max_wood_before_12 = maxi(max_wood_before_12, int(res.wood))
		var ammo := _night_ammo()
		var after := float(res.wood) - ammo
		min_wood_night = mini(min_wood_night, int(floor(after)))
		res.wood = maxi(0, int(floor(after)))
		var row := "%3d %3s %5d %6d %7d %5d %5d %5d %3d %4d %6d %4d %7.1f %9d  %d/%d/%d/%d/%d/%d" % [d, CD.ERA_ROMAN[era], gold, food,
			int(res.wood + ammo), res.stone, res.iron, res.crystal, citizens, soldiers, _count("archer_tower"),
			techs.size(), ammo, int(floor(after)), _count("house"), _count("farm"), _count("lumber_camp"),
			_count("quarry"), _count("market"), _count("barracks")]
		print(row)
		log_rows.append([d, era, gold, food, int(res.wood + ammo), int(floor(after)), _count("archer_tower"), techs.size()])
		_dawn()


# ---------------------------------------------------------------- gastos
func _spend() -> void:
	var guard := 0
	while guard < 60:
		guard += 1
		if not _spend_one():
			break


## Um gasto da lista de prioridades; falso quando nada mais dá para comprar agora.
func _spend_one() -> bool:
	# abertura: em ordem; o primeiro que não dá para pagar segura o resto (o jogador junta para ele).
	# Se o que segura é falta de aldeão, o jogador cuida do básico (moradia e comida para treinar)
	for k in OPENING:
		if _count(k) == 0:
			if _build(k):
				return true
			if _crew(k) <= _free():
				return false
			return _basics()
	if _basics():
		return true
	var towers := _count("archer_tower")
	if towers + 1 > CAMP_PER_TOWERS * _count("lumber_camp") and towers < _tower_goal() and _build("lumber_camp"):
		return true
	if towers < _tower_goal() and towers + 1 <= CAMP_PER_TOWERS * _count("lumber_camp") and _build("archer_tower"):
		return true
	# pesquisas da era atual (e das anteriores), em ordem; a que não dá para pagar segura o resto (junta para ela)
	for t in CD.TECH_ORDER:
		if techs.has(t) or int(CD.TECHS[t].era) > era or _count(CD.TECHS[t].at) == 0:
			continue
		if not _pay(CD.TECHS[t].cost):
			return false
		techs.append(t)
		_note_era1_techs()
		return true
	# a próxima era: requisitos cumpridos e sem dinheiro, o jogador junta para ela
	if era < 3:
		return _try_era()
	if soldiers < 2 * era and soldiers < _army_cap() and _free() >= 1 and _pay(CD.UNITS.soldier.cost):
		soldiers += 1
		citizens -= 1
		return true
	return false


## Moradia para os aldeões que as construções pedem e fazenda até sobrar FOOD_SURPLUS de comida por dia por era
## (as eras pedem cada vez mais comida).
func _basics() -> bool:
	if _pop_cap() - citizens - soldiers < 2 and _free() < 3 and _build("house"):
		return true
	return _food_in() - (citizens + soldiers) < FOOD_SURPLUS * era and _build("farm")


## Torres de arqueiros que o jogador quer ter no dia (defesa; em grupo as ondas crescem 45% por jogador extra).
func _tower_goal() -> int:
	return int(ceil((1.0 + (day - 1) / 3.0) * (1.0 + CD.TEAM_BUDGET * (players - 1))))


func _opening_done() -> bool:
	for k in OPENING:
		if _count(k) == 0:
			return false
	return true


## Os requisitos de construção da próxima era estão cumpridos (o quartel nível 2 da era III o jogador compra junto).
func _era_ready() -> bool:
	if era == 1:
		return _count("lumber_camp") >= 1 and _count("quarry") >= 1
	return era == 2 and _count("barracks") > 0


func _try_era() -> bool:
	if era >= 3 or not _era_ready():
		return false
	if era == 2 and barracks_lv < 2:
		# a era III exige o quartel nível 2 (a melhoria pede a era II)
		if _pay(CD.upgrade_cost("barracks", 1)):
			barracks_lv = 2
			return true
		return false
	if not _pay(CD.era_cost(era + 1, players)):
		return false
	era += 1
	if era == 2:
		era2_day = day
	else:
		era3_day = day
	return true


func _note_era1_techs() -> void:
	if era1_techs_day != 99:
		return
	for t in CD.TECHS:
		if int(CD.TECHS[t].era) == 1 and not techs.has(t):
			return
	era1_techs_day = day


func _build(kind: String) -> bool:
	if _crew(kind) > _free():
		return false
	if not _pay(_cost(kind)):
		return false
	count[kind] = _count(kind) + 1
	if kind == "barracks" and barracks_lv == 0:
		barracks_lv = 1
	return true


func _cost(kind: String) -> Dictionary:
	if coop:
		return CD.coop_cost(kind, _count(kind))
	return CD.BUILDINGS[kind].cost


func _pay(c: Dictionary) -> bool:
	for r in c:
		if _amount(r) < int(c[r]):
			return false
	for r in c:
		match r:
			"gold":
				gold -= int(c[r])
			"food":
				food -= int(c[r])
			_:
				res[r] = int(res[r]) - int(c[r])
	return true


func _amount(r: String) -> int:
	match r:
		"gold":
			return gold
		"food":
			return food
	return int(res.get(r, 0))


## Treina aldeões até o pop_cap enquanto houver comida (sem tocar na comida guardada para a próxima era).
func _train() -> void:
	var c: int = int(CD.VILLAGER_COST.food)
	var keep := 0
	if era < 3 and _era_ready() and _opening_done():
		keep = int(CD.era_cost(era + 1, players).get("food", 0))
	# sempre treina até ter 3 aldeões livres para as próximas construções; além disso, só com a comida que sobra
	while citizens + soldiers < _pop_cap() and food >= c and (_free() < 3 or food - c >= keep):
		food -= c
		citizens += 1


# ---------------------------------------------------------------- produção e consumo
func _produce(day_len: float) -> void:
	var eff := _staffing()
	for kind in ["lumber_camp", "quarry"]:
		var r: String = CD.NODES[CD.BUILDINGS[kind].gather].res
		var per_s: float = CD.gather_rate(eff, CD.GATHER_FULL, _mult(r)) * _crew(kind) * _count(kind)
		res[r] = int(res[r]) + int(per_s * day_len)
	var split := _manual_split()
	for r in split:
		var mult := _mult(r) if r in ["wood", "stone"] else 1.0
		var got := int(_manual_per_day() * players * float(split[r]) * float(MANUAL_YIELD[r]) * mult)
		if r == "food":
			food += got
		elif r == "gold":
			gold += got
		else:
			res[r] = int(res[r]) + got


## Como o jogador divide o dia de coleta: metade na repartição fixa da era (MANUAL_SPLIT) e metade no que falta
## para a próxima era, proporcional ao tempo de coleta que cada falta pede (o jogador vai atrás do que precisa).
func _manual_split() -> Dictionary:
	var base: Dictionary = MANUAL_SPLIT[era]
	var need := {}
	var total := 0.0
	if era < 3:
		var goal: Dictionary = CD.era_cost(era + 1, players)
		for r in goal:
			if not base.has(r):
				continue
			var t := maxf(0.0, float(goal[r]) - _amount(r)) / float(MANUAL_YIELD[r])
			if t > 0.0:
				need[r] = t
				total += t
	if total <= 0.0:
		return base
	var out := {}
	for r in base:
		out[r] = 0.5 * float(base[r]) + 0.5 * float(need.get(r, 0.0)) / total
	return out


## Coleta à mão de um jogador num dia inteiro: 1,5 × uma serraria cheia (meta "Exploração" da seção 18).
func _manual_per_day() -> float:
	return 1.5 * CD.gather_rate(1.0, CD.GATHER_FULL, 1.0) * int(CD.BUILDINGS.lumber_camp.crew) * CD.DAY_LENGTH


func _night_ammo() -> float:
	var shots := NIGHT_COMBAT / float(CD.BUILDINGS.archer_tower.rate)
	return CD.ammo_per_night("archer_tower", shots, 1.0 / maxf(0.01, _mult("ammo_wood"))) * _count("archer_tower")


func _dawn() -> void:
	var eff := _staffing()
	var tax: int = citizens * int(CD.TAX[1])
	var hall: int = int(CD.BUILDINGS.town_hall.gold) * era + (CD.TEAM_HALL_GOLD * (players - 1) if coop else 0)
	var market := 0.0
	for i in _count("market"):
		var k := 1.0
		if coop and i >= CD.MARKET_FREE:
			k = maxf(CD.MARKET_MIN, 1.0 - CD.MARKET_DECAY * (i - CD.MARKET_FREE + 1))
		market += float(CD.BUILDINGS.market.gold) * k
	gold += tax + hall + int(round(market * eff))
	gold -= mini(gold, soldiers * int(CD.UNITS.soldier.salary))
	if coop:
		var up := 0
		for kind in CD.UPKEEP:
			up += int(CD.UPKEEP[kind]) * _count(kind) * (barracks_lv if kind == "barracks" else 1)
		gold -= mini(gold, up)
	food += int(round(_food_in() * eff)) - (citizens + soldiers)
	if food < 0:
		var n := mini(citizens, int(ceil(-food / 2.0)))
		citizens -= n
		starved += n
		food = 0


func _food_in() -> float:
	return float(CD.BUILDINGS.farm.food) * _count("farm") * _mult("food")


# ---------------------------------------------------------------- contas da cidade (espelho de Colony)
func _count(kind: String) -> int:
	return int(count.get(kind, 0))


func _crew(kind: String) -> int:
	var n := int(CD.BUILDINGS[kind].get("crew", 0))
	if era >= 3:
		n += int(CD.ERA3_CREW.get(kind, 0))
	return n


func _busy() -> int:
	var n := 0
	for k in count:
		n += _crew(k) * _count(k)
	return n


func _free() -> int:
	return maxi(0, citizens - _busy())


func _staffing() -> float:
	var n := _busy()
	return 1.0 if n == 0 else clampf(float(citizens) / n, 0.0, 1.0)


func _pop_cap() -> int:
	return int(CD.BUILDINGS.town_hall.pop) + 4 * (era - 1) + int(CD.BUILDINGS.house.pop) * _count("house")


func _army_cap() -> int:
	return (int(CD.BUILDINGS.barracks.army) + 3 * (barracks_lv - 1)) if _count("barracks") > 0 else 0


func _mult(key: String) -> float:
	var m := 1.0
	for t in techs:
		m *= float(CD.TECHS[t].fx.get(key, 1.0))
	return m


# ================================================================ metas
## O kit do dia 1 cabe no estoque inicial (recursos e aldeões; a comida inicial pode treinar aldeões).
func day1_affordable(kit: Array) -> bool:
	var owned := {}
	var need := {}
	var crew := 0
	for k in kit:
		if k == "town_hall":
			continue
		var c: Dictionary = CD.coop_cost(k, int(owned.get(k, 0))) if coop else CD.BUILDINGS[k].cost
		need = CD.add_cost(need, c)
		owned[k] = int(owned.get(k, 0)) + 1
		crew += int(CD.BUILDINGS[k].get("crew", 0))
	var start_gold: int = (CD.COOP_START_GOLD + CD.COOP_GOLD_PER_PLAYER * (players - 1)) if coop else CD.START_GOLD
	var start_food: int = CD.COOP_START_FOOD if coop else CD.START_FOOD
	var start_cit: int = CD.COOP_START_CITIZENS if coop else CD.START_CITIZENS
	var start := {"gold": start_gold, "food": start_food,
		"wood": int(CD.START_RES.wood) + (CD.COOP_WOOD_PER_PLAYER * (players - 1) if coop else 0),
		"stone": int(CD.START_RES.get("stone", 0))}
	for r in need:
		if int(start.get(r, 0)) < int(need[r]):
			return false
	var trainable := int(start_food / int(CD.VILLAGER_COST.food))
	return crew <= start_cit + trainable


func _check_goals() -> void:
	var tag := "[%d jog.] " % players
	var era3_techs_left := 0
	for t in CD.TECHS:
		if int(CD.TECHS[t].era) == 3 and not techs.has(t):
			era3_techs_left += 1
	check(day1_affordable(["town_hall", "house", "house", "farm", "lumber_camp", "archer_tower"]), tag + "começo: dia 1 compra o kit inicial")
	check(era2_day >= 4 and era2_day <= 6, tag + "era II entre os dias 4 e 6 (dia %d)" % era2_day)
	check(era3_day >= 9 and era3_day <= 12, tag + "era III entre os dias 9 e 12 (dia %d)" % era3_day)
	check(min_wood_night > 0, tag + "madeira nunca zera à noite até o dia 15 (mínimo %d)" % min_wood_night)
	check(max_wood_before_12 <= 1500, tag + "madeira não acumula demais antes do dia 12 (máximo %d)" % max_wood_before_12)
	check(era1_techs_day <= era2_day, tag + "pesquisas da era I compráveis até a era II (dia %d)" % era1_techs_day)
	check(era3_techs_left > 0, tag + "pesquisas da era III não acabam antes do dia 15 (faltam %d)" % era3_techs_left)
	check(starved == 0, tag + "ninguém passa fome seguindo a lista (%d)" % starved)


## Tabela-resumo da partida (vai para o relatório).
func _table() -> String:
	var out := "--- %d jogador(es): era II no dia %s, era III no dia %s, pesquisas da era I até o dia %s ---\n" % [
		players, _d(era2_day), _d(era3_day), _d(era1_techs_day)]
	out += "dia era  ouro comida madeira(dia) madeira(noite) torres pesquisas\n"
	for r in log_rows:
		out += "%3d %3s %5d %6d %12d %14d %6d %9d\n" % [r[0], CD.ERA_ROMAN[r[1]], r[2], r[3], r[4], r[5], r[6], r[7]]
	return out


func _d(n: int) -> String:
	return "—" if n == 99 else str(n)
