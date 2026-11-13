class_name ColonyData
extends RefCounted
## Tabelas do modo Defesa da Cidade: construções, unidades do exército, animais de caça,
## ritmo do dia/noite e regras da economia. Os números de BUILDINGS, UNITS, ANIMALS, WAVE_COSTS,
## COST_GROWTH, UPKEEP, AFFIXES e NIGHT_MODS vivem em data/balance/colony.json (Balance preenche as
## static var); os escalares abaixo continuam aqui.

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

# ---------------------------------------------------------------- economia
const START_GOLD := 350
const START_FOOD := 30
const START_CITIZENS := 5
const TAX := [1, 2, 3]                       # ouro por morador por dia (baixo/normal/alto)
const TAX_NAMES := ["Baixo", "Normal", "Alto"]
const GROWTH := [3, 2, 1]                    # novos moradores por dia, conforme o imposto
const REFUND := 0.5                          # demolir devolve 50% do que foi gasto
const REPAIR_RATIO := 0.4                    # reparar a construção inteira custa 40% do preço
const MAX_LEVEL := 3

## Ordem da barra de construção (teclas 1..9, 0). A prefeitura é a primeira construção da partida.
const ORDER := ["house", "farm", "market", "barracks", "wall", "gate", "spikes",
	"archer_tower", "cannon_tower", "mage_tower"]

## size = pegada no chão (x = largura, y = profundidade), em metros.
## pop: moradias · food/gold: produção por dia · workers: moradores empregados · army: vagas no quartel.
static var BUILDINGS: Dictionary = {}

## Unidades recrutáveis no quartel. look = equipamentos usados para vestir o modelo do cavaleiro.
static var UNITS: Dictionary = {}
const UNIT_ORDER := ["militia", "soldier", "archer", "knight"]

## Animais de caça (aparecem de dia, longe da cidade).
static var ANIMALS: Dictionary = {}

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


## Custo para construir mais uma do tipo, já havendo `owned` (cooperativo).
static func coop_cost(kind: String, owned: int) -> int:
	var base := int(BUILDINGS[kind].cost)
	return int(round(base * (1.0 + float(COST_GROWTH.get(kind, 0.0)) * owned)))


## Vida dos monstros na noite n (cooperativo, sem contar grupo nem elites).
static func coop_hp_mult(n: int) -> float:
	return (1.0 + 0.12 * (n - 1)) * pow(VETERAN_RATE, maxi(0, n - VETERAN_NIGHT))


static func building(kind: String) -> Dictionary:
	return BUILDINGS.get(kind, {})


static func is_tower(kind: String) -> bool:
	return BUILDINGS.get(kind, {}).has("shot")


## Fator de melhoria por nível (vida, dano, produção).
static func level_mult(level: int, per := 0.45) -> float:
	return 1.0 + per * (level - 1)


static func upgrade_cost(kind: String, level: int) -> int:
	var base: int = BUILDINGS[kind].cost
	if kind == "town_hall":
		base = 250
	return int(round(base * 0.8 * level))
