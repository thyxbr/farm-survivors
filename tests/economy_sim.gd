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
## Modelo de cada dia (sem combate):
##  · começo do dia: o jogador gasta seguindo a lista abaixo, treina aldeões (fila de VILLAGER_TIME cada, só de
##    dia, parada nos ERA_TIME em que a prefeitura avança de era, até o pop_cap e com a comida que sobra depois de
##    guardar a da próxima era) e gasta de novo com os aldeões que saíram da fila;
##  · durante o dia: cada serraria/pedreira produz gather_rate(staffing, nós vivos) × crew em PROD_STEPS passos; a
##    cada NODE_YIELD_CAMP um nó do raio se esgota e volta em REGROW_DAYS (CAMP_NODES: quantos nós há no raio);
##    a coleta à mão de cada jogador rende 1,5 × uma serraria cheia (meta "Exploração"), metade numa repartição
##    fixa por era (MANUAL_SPLIT) e metade no que falta para a próxima era; ouro, ferro e cristal à mão ficam
##    limitados ao que os veios do mapa rendem por dia (ColonyNature.VEINS), para o grupo todo;
##  · noite: cada torre de arqueiros dá 60 / rate tiros (~60 s de combate ativo) e gasta ammo_per_night;
##  · amanhecer: imposto normal, mercado, prefeitura, comida, salários, manutenção (em grupo) e a volta dos nós.
##
## Lista do jogador: abertura em ordem (OPENING: casa, casa, fazenda, serraria, torre, pedreira, quartel, mercado;
## o primeiro que não dá para pagar segura o resto; faltando aldeão, cuida antes de moradia e comida); depois a
## próxima era assim que dá (com as pesquisas da era atual feitas; o quartel nível 2 da era III junto), pesquisas
## da era atual em ordem, casa quando falta moradia, fazenda até sobrar FOOD_SURPLUS × era de comida por dia,
## outra serraria/pedreira quando o bosque se esgota e o recurso faz falta, torres até a meta de defesa do dia
## (1 serraria a cada 6 torres) e, só na era III, soldados. Sem dinheiro para a pesquisa ou a era, junta.
##
## O que deixa a simulação MAIS RÁPIDA que um jogador de verdade (as datas das eras são um limite otimista):
##  · cada jogador passa o dia inteiro coletando à mão, sem caminhar até os nós, sem disputar nós com os colegas
##    (fora os veios) e sem perder tempo construindo, caçando por diversão ou morrendo;
##  · metade da coleta vai direto ao recurso que falta para a próxima era (o jogador sabe exatamente o que falta);
##  · todo o estoque é gasto na hora, na melhor ordem, e construir não leva tempo nem precisa de lugar livre;
##  · os nós no raio das serrarias/pedreiras (CAMP_NODES) vêm do melhor lugar do mapa, e a coleta à mão não
##    esgota esses mesmos nós;
##  · nenhuma construção é perdida à noite, não há reparo, deserção nem fome forçada por noites ruins;
##  · a comida de caça conta como madeira por golpe, com os bichos sempre por perto.
## O que a deixa MAIS LENTA: o que se ganha durante o dia só é gasto no dia seguinte; covis, eventos (caravana,
## baú, meteoro, aldeões perdidos) e a ajuda do reino não entram; o imposto é sempre o normal; o tempo que a
## coleta à mão "sobraria" quando os veios se esgotam não é reaproveitado.

const DAYS := 15
const PLAYERS := [1, 2, 4]
const NIGHT_COMBAT := 60.0      # segundos de combate ativo por noite (ordem de grandeza da seção 15)
## Abertura em ordem (repetir = mais uma cópia). As cinco primeiras são o kit do dia 1 (meta "Começo").
const OPENING := ["house", "house", "farm", "lumber_camp", "archer_tower", "quarry", "barracks", "market"]
const DAY1_KIT := {"house": 2, "farm": 1, "lumber_camp": 1, "archer_tower": 1}
## Nós vivos no raio da 1ª, 2ª, 3ª... serraria/pedreira (a partir da última, repete): o melhor lugar livre a
## 52-80 m do centro, o 2º melhor sem os nós do 1º etc., no pior de 12 sementes do gerador de verdade
## (ColonyNature.generate). O colony_test confere que o melhor lugar de cada semente tem pelo menos CAMP_NODES[0].
## Cada NODE_YIELD_CAMP produzidos esgotam um nó, que volta em REGROW_DAYS (gather_rate com os nós vivos).
const CAMP_NODES := {"lumber_camp": [10, 8, 8], "quarry": [7, 7, 5]}
## Recurso coletado à mão -> tipo de nó dos veios do mapa; quantos há vem de ColonyNature.VEINS.
const VEIN_NODES := {"gold": "gold", "iron": "iron", "crystal": "crystal"}
const MAX_CAMPS := 3            # serrarias/pedreiras a mais quando o bosque/as pedras se esgotam
const PROD_STEPS := 10          # passos por dia na produção das serrarias (os nós se esgotam no meio do dia)
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
var NATURE: GDScript
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
## Serrarias e pedreiras: {"kind", "live", "made", "back": [dias em que um nó volta]}.
var camps: Array = []
var era_today := false          # a prefeitura avançou de era hoje (ERA_TIME sem treinar aldeões)
var trained_today := 0
var day1 := {}                  # o que o jogador construiu no dia 1
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
	NATURE = load("res://scripts/colony/nature.gd")
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
	camps = []
	day1 = {}
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
	print("dia era  ouro comida madeira pedra ferro crist ald sold torres pesq munição mad-noite  casa/faz/serr/ped/merc/quartel  nós vivos serr/ped")
	for d in range(1, DAYS + 1):
		day = d
		var day_len: float = CD.DAY_LENGTH + (CD.FIRST_DAY_BONUS if d == 1 else 0.0)
		era_today = false
		trained_today = 0
		# gasta, treina aldeões (fila de VILLAGER_TIME cada) e gasta de novo com os aldeões que saíram da fila
		_spend()
		_train(day_len)
		_spend()
		_train(day_len)
		if d == 1:
			day1 = count.duplicate()
		_produce(day_len)
		if d < 12:
			max_wood_before_12 = maxi(max_wood_before_12, int(res.wood))
		var ammo := _night_ammo()
		var after := float(res.wood) - ammo
		min_wood_night = mini(min_wood_night, int(floor(after)))
		res.wood = maxi(0, int(floor(after)))
		var row := "%3d %3s %5d %6d %7d %5d %5d %5d %3d %4d %6d %4d %7.1f %9d  %d/%d/%d/%d/%d/%d  %.1f/%.1f" % [d, CD.ERA_ROMAN[era], gold, food,
			int(res.wood + ammo), res.stone, res.iron, res.crystal, citizens, soldiers, _count("archer_tower"),
			techs.size(), ammo, int(floor(after)), _count("house"), _count("farm"), _count("lumber_camp"),
			_count("quarry"), _count("market"), _count("barracks"), _live_avg("lumber_camp"), _live_avg("quarry")]
		print(row + "  " + _short_of())
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
	var want := {}
	for k in OPENING:
		want[k] = int(want.get(k, 0)) + 1
		if _count(k) < int(want[k]):
			if _build(k):
				return true
			if _crew(k) <= _free():
				return false
			return _basics()
	# a próxima era assim que dá (com as pesquisas da era atual feitas): vem antes de casas, fazendas e torres extras
	if era < 3 and _techs_left() == 0 and _try_era():
		return true
	# pesquisas da era atual (e das anteriores), em ordem, quando dá para pagar
	for t in CD.TECH_ORDER:
		if _tech_open(t) and _pay(CD.TECHS[t].cost):
			techs.append(t)
			_note_era1_techs()
			return true
	if _basics():
		return true
	# bosque ou pedras esgotados (menos da metade dos nós da produção cheia) e o recurso faz falta para a próxima
	# era: monta outra mais adiante
	for kind in ["lumber_camp", "quarry"]:
		var r: String = CD.NODES[CD.BUILDINGS[kind].gather].res
		if _count(kind) < MAX_CAMPS and _live_avg(kind) < CD.GATHER_FULL / 2.0 and _lacks(r) and _build(kind):
			return true
	var towers := _count("archer_tower")
	if towers + 1 > CAMP_PER_TOWERS * _count("lumber_camp") and towers < _tower_goal() and _build("lumber_camp"):
		return true
	if towers < _tower_goal() and towers + 1 <= CAMP_PER_TOWERS * _count("lumber_camp") and _build("archer_tower"):
		return true
	# falta pesquisa da era atual ou a próxima era: o jogador junta para elas (não gasta com soldados)
	if _techs_left() > 0 or era < 3:
		return false
	if soldiers < 2 * era and soldiers < _army_cap() and _free() >= 1 and _pay(CD.UNITS.soldier.cost):
		soldiers += 1
		citizens -= 1
		return true
	return false


## A pesquisa `t` está liberada e ainda não foi feita (era alcançada e a construção dela existe).
func _tech_open(t: String) -> bool:
	return not techs.has(t) and int(CD.TECHS[t].era) <= era and _count(CD.TECHS[t].at) > 0


func _techs_left() -> int:
	var n := 0
	for t in CD.TECH_ORDER:
		if _tech_open(t):
			n += 1
	return n


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
	var want := {}
	for k in OPENING:
		want[k] = int(want.get(k, 0)) + 1
	for k in want:
		if _count(k) < int(want[k]):
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
	era_today = true
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
	if CAMP_NODES.has(kind):
		var ks: Array = CAMP_NODES[kind]
		camps.append({"kind": kind, "live": int(ks[mini(_count(kind) - 1, ks.size() - 1)]), "made": 0.0, "back": []})
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


## Treina aldeões até o pop_cap enquanto houver comida (sem tocar na comida guardada para a próxima era) e
## tempo de dia na fila: VILLAGER_TIME por aldeão, sem treinar nos ERA_TIME em que a prefeitura avança de era.
func _train(day_len: float) -> void:
	var c: int = int(CD.villager_cost(1).food)
	var keep := 0
	if era < 3 and _era_ready() and _opening_done():
		keep = int(CD.era_cost(era + 1, players).get("food", 0))
	var slots := int(floor((day_len - (CD.ERA_TIME if era_today else 0.0)) / CD.VILLAGER_TIME))
	# sempre treina até ter 3 aldeões livres para as próximas construções; além disso, só com a comida que sobra
	while trained_today < slots and citizens + soldiers < _pop_cap() and food >= c and (_free() < 3 or food - c >= keep):
		food -= c
		citizens += 1
		trained_today += 1


# ---------------------------------------------------------------- produção e consumo
func _produce(day_len: float) -> void:
	var eff := _staffing()
	var dt := day_len / PROD_STEPS
	for cp in camps:
		var node: String = CD.BUILDINGS[cp.kind].gather
		var r: String = CD.NODES[node].res
		var got := 0.0
		for i in PROD_STEPS:
			var made: float = CD.gather_rate(eff, int(cp.live), _mult(r)) * _crew(cp.kind) * dt
			got += made
			cp.made = float(cp.made) + made
			while float(cp.made) >= CD.NODE_YIELD_CAMP and int(cp.live) > 0:
				cp.made = float(cp.made) - CD.NODE_YIELD_CAMP
				cp.live = int(cp.live) - 1
				cp.back.append(day + int(CD.REGROW_DAYS[node]))
		res[r] = int(res[r]) + int(got)
	# veios de ouro, de ferro e cristais são poucos no mapa: o grupo todo não colhe mais do que eles rendem por dia
	# (ColonyNature.VEINS × total ÷ dias para voltar); o tempo que sobraria fica para covis e eventos, que a simulação não
	# conta (as recompensas e depósitos deles não entram: pessimista)
	var split := _manual_split()
	var budget := _manual_per_day() * players
	var amounts := {}
	for r in split:
		var want := budget * float(split[r]) * float(MANUAL_YIELD[r])
		if VEIN_NODES.has(r):
			var node: String = VEIN_NODES[r]
			var cap := float(NATURE.VEINS[node]) * float(CD.NODES[node].total) / float(CD.REGROW_DAYS[node])
			want = minf(want, cap)
		amounts[r] = want
	for r in amounts:
		var mult := _mult(r) if r in ["wood", "stone"] else 1.0
		var got := int(float(amounts[r]) * mult)
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
	var tax: int = citizens * int(CD.TAX[1])   # imposto normal, o mesmo do treino (villager_cost(1))
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
	_regrow(day + 1)


## Falta o recurso `r` para a próxima era (na era III, para a pesquisa mais cara que ainda falta: 400).
func _lacks(r: String) -> bool:
	var goal: Dictionary = CD.era_cost(era + 1, players) if era < 3 else {r: 400}
	return _amount(r) < int(goal.get(r, 0))


## O que falta no fim do dia para a próxima era (e o quartel nível 2 da era III), para ler a tabela.
func _short_of() -> String:
	if era >= 3:
		return ""
	var goal: Dictionary = CD.era_cost(era + 1, players)
	if era == 2 and barracks_lv < 2:
		goal = CD.add_cost(goal, CD.upgrade_cost("barracks", 1))
	var parts: Array[String] = []
	for r in goal:
		if _amount(r) < int(goal[r]):
			parts.append("%s %d" % [CD.RES_SHORT[r], int(goal[r]) - _amount(r)])
	return "falta: " + ", ".join(parts) if not parts.is_empty() else "era pronta"


## Média de nós vivos por construção do tipo (GATHER_FULL quando não há nenhuma).
func _live_avg(kind: String) -> float:
	var n := 0
	var live := 0
	for cp in camps:
		if cp.kind == kind:
			n += 1
			live += int(cp.live)
	return float(CD.GATHER_FULL) if n == 0 else float(live) / n


## Amanhecer do dia `d`: os nós cujo dia chegou voltam (como ColonyNature.regrow).
func _regrow(d: int) -> void:
	for cp in camps:
		var keep: Array = []
		for back in cp.back:
			if d >= int(back):
				cp.live = int(cp.live) + 1
			else:
				keep.append(back)
		cp.back = keep


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
## O jogador construiu no dia 1 o kit inicial (além da prefeitura) com o estoque inicial e os aldeões que treinou.
func day1_bought(kit: Dictionary) -> bool:
	for k in kit:
		if int(day1.get(k, 0)) < int(kit[k]):
			return false
	return true


func _check_goals() -> void:
	var tag := "[%d jog.] " % players
	var era3_techs_left := 0
	for t in CD.TECHS:
		if int(CD.TECHS[t].era) == 3 and not techs.has(t):
			era3_techs_left += 1
	check(day1_bought(DAY1_KIT), tag + "começo: dia 1 compra o kit inicial (prefeitura + %s)" % str(day1))
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
