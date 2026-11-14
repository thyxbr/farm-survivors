class_name ColonyData
extends RefCounted
## Tabelas do modo Defesa da Cidade: construções, unidades do exército, animais de caça,
## ritmo do dia/noite e regras da economia. Os números de BUILDINGS, UNITS, ANIMALS, WAVE_COSTS,
## COST_GROWTH, UPKEEP, AFFIXES e NIGHT_MODS vivem em data/balance/colony.json (Balance preenche as
## static var); os escalares e as demais tabelas abaixo continuam aqui.

# ---------------------------------------------------------------- ritmo
const DAY_LENGTH := 150.0        # segundos de dia (caça, construção, economia)
const FIRST_DAY_BONUS := 90.0    # o primeiro dia é mais longo para montar a cidade
const NIGHT_MAX := 240.0         # se a onda se arrastar, amanhece mesmo assim
const DUSK := 18.0               # segundos de entardecer no fim do dia
const DAWN := 10.0               # segundos de amanhecer no começo do dia
const BOSS_EVERY := 5            # a cada 5 noites vem o Rei Goblin

# ---------------------------------------------------------------- mapa
const MAP_HALF := 125.0
const CITY_RADIUS := 42.0        # raio em volta da prefeitura onde se pode construir
const HALL_ZONE := 30.0          # a prefeitura vai na clareira central
const SPAWN_DIST := 78.0         # distância da prefeitura onde as ondas surgem

# ---------------------------------------------------------------- recursos
## Os seis recursos do estoque da cidade, na ordem em que aparecem no HUD e nas mensagens.
const RESOURCES := ["gold", "food", "wood", "stone", "iron", "crystal"]
const RES_NAMES := {"gold": "Ouro", "food": "Comida", "wood": "Madeira", "stone": "Pedra", "iron": "Ferro", "crystal": "Cristal"}
## Forma curta para caber nos cartões da barra de construção.
const RES_SHORT := {"gold": "ouro", "food": "com", "wood": "mad", "stone": "ped", "iron": "fer", "crystal": "cri"}

# ---------------------------------------------------------------- economia
const START_GOLD := 350
const START_RES := {"wood": 150, "stone": 60}   # estoque inicial dos demais recursos (ouro e comida têm constantes próprias)
const START_FOOD := 30
const START_CITIZENS := 5
const TAX := [1, 2, 3]                       # ouro por morador por dia (baixo/normal/alto)
const TAX_NAMES := ["Baixo", "Normal", "Alto"]
const VILLAGER_COST := {"food": 40}         # treinar um aldeão na prefeitura
const VILLAGER_TIME := 8.0                   # segundos de fila por aldeão
const UNMANNED_TOWER_SLOW := 1.5             # torre sem operador atira com o intervalo multiplicado por isto
# Munição: [recurso, quantos disparos rende 1 unidade]. Sem estoque, a cadência cai (intervalo x NO_AMMO_RATE).
const AMMO := {"archer_tower": ["wood", 5], "cannon_tower": ["stone", 2], "mage_tower": ["crystal", 15],
	"archer": ["wood", 8], "mage": ["crystal", 20], "cannoneer": ["stone", 3]}
const NO_AMMO_RATE := 2.0                    # sem munição: o intervalo dobra (metade da cadência)
const AMMO_OUT_MSG := {"wood": "Acabaram as flechas!", "stone": "Acabaram as balas de canhão!", "crystal": "Acabaram os cristais arcanos!"}
const REFUND := 0.5                          # demolir devolve 50% do que foi gasto
const REPAIR_RATIO := 0.4                    # reparar a construção inteira custa 40% do preço
const MAX_LEVEL := 3

## Ordem da barra de construção (teclas 1..9, 0). A prefeitura é a primeira construção da partida.
const ORDER := ["house", "farm", "lumber_camp", "quarry", "market", "barracks", "wall", "gate", "spikes",
	"archer_tower", "cannon_tower", "mage_tower"]

## size = pegada no chão (x = largura, y = profundidade), em metros.
## pop: moradias · food/gold: produção por dia · crew: aldeões ocupados · army: vagas no quartel.
static var BUILDINGS: Dictionary = {}

## Unidades recrutáveis no quartel. look = equipamentos usados para vestir o modelo do cavaleiro.
static var UNITS: Dictionary = {}

# ---------------------------------------------------------------- eras e pesquisas
## A era é o nível da prefeitura. cost = preço para chegar nela (solo; em grupo use era_cost);
## requires: tipo de construção -> quantidade, ou "barracks_level" -> nível mínimo do melhor quartel.
const ERAS := {
	1: {"name": "I · Aldeia", "cost": {}, "requires": {}},
	2: {"name": "II · Vila", "cost": {"food": 250, "wood": 250, "stone": 150, "gold": 200},
		"requires": {"lumber_camp": 1, "quarry": 1}},
	3: {"name": "III · Cidade", "cost": {"food": 500, "wood": 450, "stone": 400, "gold": 400, "iron": 40, "crystal": 20},
		"requires": {"barracks_level": 2}},
}
const ERA_ROMAN := ["", "I", "II", "III"]
const ERA_TIME := 30.0      # segundos de dia para avançar de era
const TECH_TIME := 20.0     # segundos de dia por pesquisa
## Construções que só existem a partir de uma era.
const BUILD_ERA := {"cannon_tower": 2, "mage_tower": 2}
## Era III: aldeões extras de `crew` nestas construções.
const ERA3_CREW := {"lumber_camp": 1, "quarry": 1}
## Pesquisas: era mínima, construção onde se faz (at), custo e efeitos.
## fx: chave -> multiplicador (lido por Colony.mult); "chain_add" é aditivo (Colony.bonus).
## Chaves: wood/stone/food (produção), arrow_dmg, bld_hp, wall_hp, ammo_wood/ammo_stone/ammo_crystal
## (consumo de munição), splash, chain_add, unit_hp, unit_dmg.
const TECHS := {
	"sharp_axe": {"name": "Machado Afiado", "era": 1, "at": "lumber_camp", "cost": {"gold": 60, "wood": 60},
		"fx": {"wood": 1.2}, "desc": "+20% madeira (serraria e jogador)"},
	"pickaxe": {"name": "Picareta", "era": 1, "at": "quarry", "cost": {"gold": 60, "wood": 80},
		"fx": {"stone": 1.2}, "desc": "+20% pedra"},
	"plow": {"name": "Arado", "era": 1, "at": "farm", "cost": {"gold": 80, "wood": 80},
		"fx": {"food": 1.2}, "desc": "+20% comida"},
	"arrow_bundles": {"name": "Feixes de Flechas", "era": 2, "at": "archer_tower", "cost": {"gold": 100, "wood": 120},
		"fx": {"ammo_wood": 0.7}, "desc": "−30% munição de madeira"},
	"iron_arrows": {"name": "Flechas de Ferro", "era": 2, "at": "archer_tower", "cost": {"gold": 120, "wood": 100, "iron": 10},
		"fx": {"arrow_dmg": 1.15}, "desc": "+15% dano de flechas (torres e arqueiros)"},
	"masonry": {"name": "Alvenaria", "era": 2, "at": "town_hall", "cost": {"gold": 150, "stone": 200},
		"fx": {"bld_hp": 1.2}, "desc": "+20% vida de todas as construções"},
	"double_saw": {"name": "Serra Dupla", "era": 2, "at": "lumber_camp", "cost": {"gold": 120, "wood": 150, "iron": 10},
		"fx": {"wood": 1.2}, "desc": "+20% madeira (soma com o Machado)"},
	"fine_powder": {"name": "Pólvora Fina", "era": 3, "at": "cannon_tower", "cost": {"gold": 200, "stone": 200, "iron": 25},
		"fx": {"splash": 1.25, "ammo_stone": 0.7}, "desc": "+25% raio da explosão, −30% munição"},
	"arcane_focus": {"name": "Foco Arcano", "era": 3, "at": "mage_tower", "cost": {"gold": 200, "crystal": 25},
		"fx": {"chain_add": 1, "ammo_crystal": 0.7}, "desc": "+1 salto na cadeia, −30% munição"},
	"reinforced_wall": {"name": "Muralha Reforçada", "era": 3, "at": "town_hall", "cost": {"gold": 150, "stone": 400},
		"fx": {"wall_hp": 1.4}, "desc": "muros e portões +40% vida"},
	"elite_training": {"name": "Treino de Elite", "era": 3, "at": "barracks", "cost": {"gold": 250, "food": 150, "iron": 30},
		"fx": {"unit_hp": 1.15, "unit_dmg": 1.15}, "desc": "tropas +15% vida e dano"},
}
const TECH_ORDER := ["sharp_axe", "pickaxe", "plow", "arrow_bundles", "iron_arrows", "masonry", "double_saw",
	"fine_powder", "arcane_focus", "reinforced_wall", "elite_training"]


## Custo para chegar à era `era` com `players` jogadores: +35% por jogador além do primeiro.
static func era_cost(era: int, players: int) -> Dictionary:
	if not ERAS.has(era):
		return {}
	return scale_cost(ERAS[era].cost, 1.0 + 0.35 * (maxi(1, players) - 1))
const UNIT_ORDER := ["militia", "soldier", "archer", "knight", "mage", "cannoneer"]

## Nós de recurso que o jogador coleta com o ataque normal: recurso, golpes para esgotar e total entregue.
const NODES := {
	"tree": {"name": "Árvore", "res": "wood", "hits": 4, "total": 24},
	"rock": {"name": "Pedra", "res": "stone", "hits": 5, "total": 25},
	"iron": {"name": "Veio de ferro", "res": "iron", "hits": 6, "total": 12},
	"gold": {"name": "Veio de ouro", "res": "gold", "hits": 6, "total": 60},
	"crystal": {"name": "Cristal arcano", "res": "crystal", "hits": 6, "total": 8},
	"berry": {"name": "Arbusto de frutas", "res": "food", "hits": 1, "total": 12},
}
## Serraria e pedreira: unidades por aldeão por segundo com o bosque cheio (GATHER_FULL nós vivos no raio ou mais).
const GATHER_RATE := 1.0 / 6.0
const GATHER_FULL := 8
const GATHER_TICK := 3.0           # segundos entre entregas
const NODE_YIELD_CAMP := 24        # a cada tantas unidades produzidas, o nó vivo mais próximo se esgota

## Raio (a partir do centro do mapa) onde começam os anéis 1, 2 e 3.
const RINGS := [52.0, 80.0, 105.0]
## Dias até um nó esgotado voltar no mesmo lugar.
const REGROW_DAYS := {"tree": 2, "berry": 2, "rock": 4, "iron": 4, "gold": 4, "crystal": 4}

## Animais de caça (aparecem de dia, longe da cidade). `rings`: anéis (ver RINGS) onde nascem;
## `weight`: peso do sorteio dentro do anel; `pack`: tamanho [mín, máx] do grupo que nasce junto.
static var ANIMALS: Dictionary = {}
## Chance de o próximo grupo de fauna nascer no anel 1, 2 ou 3.
const WILD_RING_WEIGHTS := [0.55, 0.30, 0.15]

## Covis (pontos de interesse), gerados da semente: cada um numa direção de Colony.DIR_NAMES.
## ring: anel (ver RINGS) · props: [modelo, deslocamento a partir do centro, giro] (o centro fica livre
## para o depósito rico) · guards: [[tipo, quantos no nível 1]] · elite: chance de cada guarda vir com afixo ·
## boss/boss_affix/boss_hp: o chefe (boss_hp multiplica a vida-base dele) · reward: recursos da cidade ao limpar
## (× level_mult(nível, 0.5)) · deposit: [tipo de nó, total] do nó rico que aparece no centro.
## Uma entrada de dungeon futura vira mais um tipo aqui.
const POIS := {
	"goblin_camp": {"name": "Acampamento Goblin", "ring": 2,
		"props": [["tent", Vector3(-5, 0, -3), 0.5], ["tent", Vector3(5, 0, -3.5), -0.6], ["campfire", Vector3(0, 0, -5), 0.0],
			["crate", Vector3(-6, 0, 3), 0.3], ["barrel", Vector3(6, 0, 2.5), 0.0], ["chest", Vector3(0, 0, 6), PI]],
		"guards": [["goblin", 3], ["goblin_arqueiro", 2], ["goblin_xama", 1]], "elite": 0.0,
		"boss": "goblin_campeao", "boss_affix": "", "boss_hp": 1.0,
		"reward": {"wood": 60, "stone": 60, "iron": 15, "crystal": 0, "gold": 80}, "deposit": ["iron", 60]},
	"slime_nest": {"name": "Ninho de Slimes", "ring": 2,
		"props": [["rock", Vector3(-5, 0, -2), 0.0], ["rock", Vector3(4, 0, -4), 1.2], ["ruin_pillar", Vector3(5, 0, 3), 0.4],
			["barrel", Vector3(-4, 0, 5), 0.0], ["crate", Vector3(-6.5, 0, 1.5), 0.8]],
		"guards": [["slime", 4], ["slime_mae", 1], ["slime_explosivo", 2]], "elite": 0.0,
		"boss": "slime_grande", "boss_affix": "", "boss_hp": 3.0,
		"reward": {"wood": 40, "stone": 80, "iron": 0, "crystal": 5, "gold": 60}, "deposit": ["gold", 200]},
	"haunted_ruins": {"name": "Ruínas Assombradas", "ring": 3,
		"props": [["ruin_wall", Vector3(-5, 0, -4), 0.3], ["ruin_wall", Vector3(4, 0, -5), -0.4], ["ruin_pillar", Vector3(-6, 0, 3), 0.0],
			["ruin_pillar", Vector3(6, 0, 3), 0.0], ["chest", Vector3(0, 0, -6.5), 0.0]],
		"guards": [["goblin", 3], ["goblin_bruto", 1], ["slime_grande", 1], ["goblin_xama", 1]], "elite": 0.4,
		"boss": "goblin_bruto", "boss_affix": "blindado", "boss_hp": 1.8,
		"reward": {"wood": 80, "stone": 120, "iron": 25, "crystal": 15, "gold": 150}, "deposit": ["crystal", 30]},
}
const DEN_WAKE := 45.0          # um jogador a até tantos metros acorda o covil (os guardas nascem)
const DEN_SLEEP := 60.0         # sem ninguém a até tantos metros, o covil volta a dormir (os guardas somem)
const DEN_LEASH := 25.0         # guarda atraído para além disto do centro volta ao covil
const DEN_GROW_DAYS := 3        # covil não limpo sobe de nível a cada tantos dias
const DEN_WAVE_BONUS := 0.15    # +15% de orçamento da onda por nível, na direção do covil
const DEN_LEVEL_GUARDS := 1     # guardas a mais de cada tipo por nível acima do 1
const DEN_LEVEL_HP := 0.3       # vida dos guardas e do chefe: +30% por nível acima do 1
const DEN_MAX_LEVEL := 5        # o covil não cresce além disto
const DEN_FORCE_NIGHT := 3      # antes desta noite os covis não mexem na onda (começo igual ao de antes)
const DEN_EXTRA_MAX := 1.0      # o extra de todos os covis juntos é no máximo +100% do orçamento da onda

## Eventos aleatórios do dia (ColonyEvents): sorteados no amanhecer, acabam ao anoitecer.
## weight: peso no sorteio · min_day: primeiro dia em que pode sair · needs: condição extra
## ("camp_out" = existe serraria ou pedreira além de CITY_RADIUS) · rings: [primeiro, último] anel do ponto
## (ver RINGS) · msg: o anúncio ({dir} = "Nordeste"; {camp} = a construção atacada).
const DAY_EVENTS := {
	"caravan": {"name": "Caravana", "weight": 3.0, "min_day": 2, "needs": "", "rings": [1, 2],
		"msg": "Uma caravana de mercadores parou ao {dir}. Vá negociar antes do anoitecer!"},
	"lost_villagers": {"name": "Aldeões perdidos", "weight": 2.0, "min_day": 3, "needs": "", "rings": [1, 2],
		"msg": "Aldeões perdidos pedem socorro ao {dir}, cercados por lobos!"},
	"meteor": {"name": "Meteoro", "weight": 2.0, "min_day": 3, "needs": "", "rings": [2, 3],
		"msg": "Um meteoro caiu ao {dir}! Ficaram cristais no lugar... e slimes."},
	"alpha": {"name": "Fera alfa", "weight": 2.0, "min_day": 2, "needs": "", "rings": [1, 3],
		"msg": "Uma fera alfa ronda ao {dir}. O couro dela vale muito!"},
	"camp_raid": {"name": "Ataque", "weight": 1.5, "min_day": 4, "needs": "camp_out", "rings": [1, 1],
		"msg": "Monstros marcham contra a {camp} ao {dir}!"},
	"lost_chest": {"name": "Baú esquecido", "weight": 2.0, "min_day": 2, "needs": "", "rings": [1, 2],
		"msg": "Batedores viram um baú esquecido ao {dir}, guardado por monstros."},
}
const EVENT_CHANCE := 0.6
const EVENT_MIN_DAY := 2
const EVENT_VILLAGERS := 3            # aldeões perdidos (modelo do ancião) no ponto do evento
const EVENT_FOOD_PER_VILLAGER := 10   # resgatado sem moradia vira comida
const EVENT_METEOR_NODES := 3         # nós ricos de cristal que o meteoro deixa
const EVENT_METEOR_TOTAL := 16        # cristal de cada um (um cristal comum dá 8)
const EVENT_METEOR_SLIMES := 4
const EVENT_ALPHA_MULT := 3.0         # vida e recompensa da fera alfa
const EVENT_ALPHA_SCALE := 1.5
const EVENT_RAID_DIST := 20.0         # o grupo nasce a tantos metros da serraria/pedreira, do lado de fora
const EVENT_CHEST_GUARDS := 3
const EVENT_REACH := 8.0              # servidor: o jogador precisa estar a até tantos metros para interagir
## Trocas da caravana: [o que a cidade paga, o que recebe].
const TRADES := [[{"wood": 50}, {"gold": 30}], [{"gold": 40}, {"iron": 5}], [{"gold": 80}, {"crystal": 3}], [{"stone": 60}, {"gold": 35}]]

## Custo de cada monstro no orçamento da onda e a noite em que começa a aparecer.
static var WAVE_COSTS: Dictionary = {}


# ================================================================ cooperativo (multiplayer)
# A cidade é compartilhada: um cofre só, ondas maiores para grupos maiores e uma curva de
# dificuldade pensada para o começo ser tranquilo e o fim de jogo não virar passeio:
#  · custo progressivo: cada cópia extra da mesma construção custa mais;
#  · manutenção diária das torres e quartéis (cresce com o nível);
#  · mercados saturam: a partir do 3º, cada um rende menos;
#  · os monstros ganham vida mais rápido depois da noite 10 e surgem elites com resistências
#    (é preciso misturar torres); noites especiais são anunciadas um dia antes;
#  · para não ficar impossível: começo generoso, prefeitura se recupera ao amanhecer,
#    ajuda do reino quando a cidade está quebrada e bons eventos de vez em quando.
const COOP_START_GOLD := 450
const COOP_GOLD_PER_PLAYER := 150
const COOP_START_FOOD := 40
const COOP_START_CITIZENS := 6
const COOP_WOOD_PER_PLAYER := 50   # madeira extra no cofre por jogador além do primeiro
const COOP_MAX_PLAYERS := 6
## Cada jogador além do primeiro: ondas +TEAM_BUDGET e monstros +TEAM_HP de vida; a prefeitura rende +TEAM_HALL_GOLD/dia.
const TEAM_BUDGET := 0.45
const TEAM_HP := 0.1
const TEAM_HALL_GOLD := 15
## Multiplicador de custo por cópia já construída (casa: +10% por casa existente...).
static var COST_GROWTH: Dictionary = {}
## Manutenção paga ao amanhecer, por nível da construção.
static var UPKEEP: Dictionary = {}
## Mercados além do MARKET_FREE-ésimo rendem MARKET_DECAY a menos cada (mínimo MARKET_MIN).
const MARKET_FREE := 2
const MARKET_DECAY := 0.2
const MARKET_MIN := 0.4
## A partir desta noite a vida dos monstros cresce mais rápido (VETERAN_RATE por noite, composto).
const VETERAN_NIGHT := 10
const VETERAN_RATE := 1.06
## Teto do orçamento da onda (por jogador extra +35%); o que passar vira vida extra (menos monstros, mais duros),
## para o servidor não ter centenas de monstros no fim de jogo.
const WAVE_CAP := 120.0
## Elites: aparecem a partir da noite ELITE_NIGHT, chance cresce ELITE_STEP por noite (até ELITE_MAX).
const ELITE_NIGHT := 6
const ELITE_STEP := 0.04
const ELITE_MAX := 0.45
## resist: fração do dano ignorada por tipo de disparo ("arrow" flechas e golpes, "ball" canhão, "bolt" arcano).
static var AFFIXES: Dictionary = {}
## Noites especiais (a partir de MOD_NIGHT), anunciadas no amanhecer anterior.
const MOD_NIGHT := 7
static var NIGHT_MODS: Dictionary = {}
## Recompensa de cada noite sobrevivida (vai para o personagem do RPG de cada jogador).
static func night_reward(n: int) -> Dictionary:
	return {"gold": 15 + 6 * n, "xp": 30 + 12 * n + n * n}


## Raridade do baú das noites de chefe (a cada BOSS_EVERY): [raridade, chance] em ordem.
static func chest_rarities(n: int) -> Array:
	var tier := n / BOSS_EVERY
	match tier:
		0:
			return [["uncommon", 1.0]]
		1:
			return [["rare", 0.6], ["uncommon", 1.0]]
		2:
			return [["epic", 0.35], ["rare", 1.0]]
		3:
			return [["legendary", 0.15], ["epic", 1.0]]
		4:
			return [["legendary", 0.5], ["epic", 1.0]]
	return [["legendary", 1.0]]


## Baú da noite n (só nas noites de chefe, a cada BOSS_EVERY): um equipamento sorteado por chest_rarities
## e duas poções de vida. [] nas outras noites. Vale para o solo e para o grupo (servidor).
static func night_chest(n: int) -> Array:
	if n <= 0 or n % BOSS_EVERY != 0:
		return []
	var items: Array = []
	for entry in chest_rarities(n):
		if randf() < float(entry[1]):
			var pool: Array = []
			for id in ItemDB.ITEMS:
				if ItemDB.is_equippable(id) and ItemDB.rarity_of(id) == entry[0]:
					pool.append(id)
			if not pool.is_empty():
				items.append(pool.pick_random())
				break
	items.append("health_potion")
	items.append("health_potion")
	return items


## Multiplica cada recurso do custo por k, arredondando (o que custa algo nunca vira grátis).
static func scale_cost(c: Dictionary, k: float) -> Dictionary:
	var out := {}
	for r in c:
		var v := float(c[r])
		out[r] = maxi(1, int(round(v * k))) if v > 0.0 and k > 0.0 else int(round(v * k))
	return out


## Soma dois custos, recurso a recurso.
static func add_cost(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	for r in b:
		out[r] = int(out.get(r, 0)) + int(b[r])
	return out


## Custo lido de um save ou da rede: o JSON devolve números reais, e um save antigo guardava só o ouro (inteiro).
static func cost_from(v) -> Dictionary:
	if v is Dictionary:
		var out := {}
		for r in v:
			out[str(r)] = int(v[r])
		return out
	return {"gold": int(v)}


## Texto do custo na ordem dos recursos: "30 Ouro, 40 Madeira" (vazio = grátis).
static func cost_text(c: Dictionary) -> String:
	var parts: Array[String] = []
	for r in RESOURCES:
		if int(c.get(r, 0)) > 0:
			parts.append("%d %s" % [int(c[r]), RES_NAMES[r]])
	return ", ".join(parts)


## Custo para construir mais uma do tipo, já havendo `owned` (cooperativo): multiplica todos os recursos.
static func coop_cost(kind: String, owned: int) -> Dictionary:
	return scale_cost(BUILDINGS[kind].cost, 1.0 + float(COST_GROWTH.get(kind, 0.0)) * owned)


## Vida dos monstros na noite n (cooperativo, sem contar grupo nem elites).
static func coop_hp_mult(n: int) -> float:
	return (1.0 + 0.12 * (n - 1)) * pow(VETERAN_RATE, maxi(0, n - VETERAN_NIGHT))


## Unidades por segundo de UM aldeão da serraria/pedreira (multiplique por `crew`): taxa × eficiência, proporcional ao bosque (cheio com GATHER_FULL nós).
static func gather_rate(crew_eff: float, live: int, tech_mult: float) -> float:
	return GATHER_RATE * crew_eff * clampf(float(live) / GATHER_FULL, 0.0, 1.0) * tech_mult


static func building(kind: String) -> Dictionary:
	return BUILDINGS.get(kind, {})


static func is_tower(kind: String) -> bool:
	return BUILDINGS.get(kind, {}).has("shot")


## Intervalo entre disparos de uma torre: x1,5 (mais lento) se faltar aldeão para operá-la (eff < 1).
static func tower_rate_mult(eff: float) -> float:
	return 1.0 if eff >= 1.0 else UNMANNED_TOWER_SLOW


## Unidades de recurso gastas por `shots` disparos de `kind` (torre ou tropa); tech_mult > 1 rende mais disparos por unidade.
static func ammo_per_night(kind: String, shots: float, tech_mult: float) -> float:
	if not AMMO.has(kind):
		return 0.0
	return shots / (float(AMMO[kind][1]) * maxf(0.01, tech_mult))


## Fator de melhoria por nível (vida, dano, produção).
static func level_mult(level: int, per := 0.45) -> float:
	return 1.0 + per * (level - 1)


## Melhorar da faixa `level` para a seguinte: 80% × nível × custo-base; o nível 3 pede ainda 5 de ferro.
## A prefeitura não passa por aqui: melhorá-la é avançar de era (era_cost).
static func upgrade_cost(kind: String, level: int) -> Dictionary:
	if kind == "town_hall":
		return era_cost(level + 1, 1)
	var c := scale_cost(BUILDINGS[kind].cost, 0.8 * level)
	if level >= 2:
		c = add_cost(c, {"iron": 5})
	return c
