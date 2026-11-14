class_name ColonyData
extends RefCounted
## Tabelas do modo Defesa da Cidade: construções, unidades do exército, animais de caça,
## ritmo do dia/noite e regras da economia. Para balancear o modo, mexa aqui.

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
const BUILDINGS := {
	"town_hall": {"name": "Prefeitura", "cost": {}, "hp": 1600, "size": Vector2(7.4, 6.4), "pop": 6, "gold": 15,
		"desc": "O coração da cidade: abriga 6 moradores e rende 15 ouro por dia. Se cair, a cidade cai."},
	"house": {"name": "Casa", "cost": {"gold": 30, "wood": 40}, "hp": 320, "size": Vector2(5.6, 4.6), "pop": 5,
		"desc": "Abriga 5 moradores. Moradores pagam impostos e podem ser recrutados."},
	"farm": {"name": "Fazenda", "cost": {"gold": 30, "wood": 50}, "hp": 240, "size": Vector2(7.0, 6.0), "food": 12, "crew": 2,
		"desc": "Produz 12 de comida por dia. Ocupa 2 aldeões."},
	"lumber_camp": {"name": "Serraria", "cost": {"gold": 40, "wood": 30}, "hp": 300, "size": Vector2(5.0, 4.0), "crew": 3,
		"gather": "tree", "reach": 14.0, "max_dist": 80.0, "min_nodes": 4,
		"desc": "Corta as árvores em volta (14 m) e entrega madeira o dia todo. Ocupa 3 aldeões. Pode ficar fora da cidade, mas o bosque acaba."},
	"quarry": {"name": "Pedreira", "cost": {"gold": 40, "wood": 50}, "hp": 300, "size": Vector2(5.0, 4.0), "crew": 3,
		"gather": "rock", "reach": 14.0, "max_dist": 80.0, "min_nodes": 4,
		"desc": "Quebra as pedras em volta (14 m) e entrega pedra o dia todo. Ocupa 3 aldeões. Pode ficar fora da cidade, mas as pedras acabam."},
	"market": {"name": "Mercado", "cost": {"gold": 90, "wood": 60, "stone": 20}, "hp": 380, "size": Vector2(5.2, 5.2), "gold": 25, "crew": 2,
		"desc": "Rende 25 ouro por dia com o comércio. Ocupa 2 aldeões."},
	"barracks": {"name": "Quartel", "cost": {"gold": 100, "wood": 80, "stone": 40}, "hp": 650, "size": Vector2(6.6, 5.6), "army": 6, "crew": 1,
		"desc": "Recrute o exército aqui (E). Cada quartel aloja 6 soldados."},
	"wall": {"name": "Muro", "cost": {"gold": 4, "stone": 8}, "hp": 420, "size": Vector2(4.0, 0.9), "wall": true,
		"desc": "Segura os monstros. Encoste um no outro para fechar a cidade."},
	"gate": {"name": "Portão", "cost": {"gold": 20, "wood": 20, "stone": 15}, "hp": 520, "size": Vector2(4.0, 1.1), "wall": true,
		"desc": "Você e seus soldados passam; os monstros precisam derrubar."},
	"spikes": {"name": "Estacas", "cost": {"gold": 10, "wood": 20}, "hp": 200, "size": Vector2(4.0, 1.6), "dps": 16, "wall": true,
		"desc": "Ferem e atrasam os monstros que passam por cima. Desgastam com o uso."},
	"archer_tower": {"name": "Torre de Arqueiros", "cost": {"gold": 70, "wood": 60, "stone": 30}, "hp": 460, "size": Vector2(3.2, 3.2),
		"crew": 1, "range": 20.0, "damage": 14.0, "rate": 0.95, "shot": "arrow",
		"desc": "Dispara flechas rápidas no monstro mais próximo."},
	"cannon_tower": {"name": "Torre de Canhão", "cost": {"gold": 120, "wood": 40, "stone": 80, "iron": 15}, "hp": 620, "size": Vector2(3.8, 3.8),
		"crew": 1, "range": 23.0, "damage": 40.0, "rate": 2.8, "splash": 3.2, "shot": "ball",
		"desc": "Balas lentas que explodem e ferem todos em volta."},
	"mage_tower": {"name": "Torre Arcana", "cost": {"gold": 100, "wood": 40, "stone": 50, "crystal": 10}, "hp": 420, "size": Vector2(3.2, 3.2),
		"crew": 1, "range": 17.0, "damage": 16.0, "rate": 1.3, "slow": 2.0, "chain": 2, "shot": "bolt",
		"desc": "Raio gélido que deixa lento e salta para mais 2 monstros."},
}

## Unidades recrutáveis no quartel. look = equipamentos usados para vestir o modelo do cavaleiro.
const UNITS := {
	"militia": {"name": "Miliciano", "cost": 30, "salary": 2, "hp": 70, "damage": 8.0, "reach": 1.9,
		"cooldown": 1.1, "speed": 4.6, "armor": 0, "aggro": 13.0,
		"look": {"weapon": "wooden_sword", "head": "wool_hood", "armor": "traveler_tunic", "feet": "leather_boots"},
		"desc": "Barato, mas frágil."},
	"soldier": {"name": "Soldado", "cost": 70, "salary": 5, "hp": 150, "damage": 15.0, "reach": 2.0,
		"cooldown": 1.0, "speed": 4.4, "armor": 5, "aggro": 13.0,
		"look": {"weapon": "iron_sword", "offhand": "wooden_shield", "head": "kettle_hat", "armor": "chain_mail",
			"hands": "leather_gloves", "feet": "reinforced_boots"},
		"desc": "Espada e escudo: segura a linha."},
	"archer": {"name": "Arqueiro", "cost": 80, "salary": 6, "hp": 80, "damage": 12.0, "reach": 15.0,
		"cooldown": 1.3, "speed": 4.6, "armor": 1, "aggro": 17.0, "ranged": true,
		"look": {"weapon": "hunter_bow", "offhand": "hunter_quiver", "head": "ranger_hood", "armor": "leather_armor",
			"hands": "archer_bracers", "feet": "leather_boots"},
		"desc": "Atira por cima dos muros."},
	"knight": {"name": "Cavaleiro", "cost": 180, "salary": 12, "hp": 300, "damage": 28.0, "reach": 2.3,
		"cooldown": 1.15, "speed": 4.9, "armor": 12, "aggro": 15.0, "needs_level": 2,
		"look": {"weapon": "guardian_greatsword", "head": "knight_helm", "armor": "royal_plate",
			"hands": "iron_gauntlets", "feet": "iron_greaves"},
		"desc": "Elite. Exige um quartel nível 2."},
}
const UNIT_ORDER := ["militia", "soldier", "archer", "knight"]

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

## Animais de caça (aparecem de dia, longe da cidade).
const ANIMALS := {
	"rabbit": {"name": "Coelho", "hp": 14, "speed": 6.8, "food": 3, "gold": 2, "radius": 0.3, "flee": true},
	"deer": {"name": "Cervo", "hp": 50, "speed": 7.2, "food": 10, "gold": 9, "radius": 0.55, "flee": true},
	"boar": {"name": "Javali", "hp": 95, "speed": 5.8, "food": 14, "gold": 12, "radius": 0.6,
		"damage": 11.0, "aggressive": true},
}

## Custo de cada monstro no orçamento da onda e a noite em que começa a aparecer.
const WAVE_COSTS := {
	"slime": [1.0, 1], "slime_veloz": [1.0, 2], "goblin": [2.0, 2], "slime_grande": [3.0, 4], "goblin_bruto": [4.0, 3],
}


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
const COST_GROWTH := {"house": 0.10, "farm": 0.12, "market": 0.30, "barracks": 0.35, "wall": 0.015,
	"gate": 0.08, "spikes": 0.06, "archer_tower": 0.14, "cannon_tower": 0.18, "mage_tower": 0.18}
## Manutenção paga ao amanhecer, por nível da construção.
const UPKEEP := {"archer_tower": 2, "cannon_tower": 4, "mage_tower": 3, "barracks": 3}
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
const AFFIXES := {
	"blindado": {"name": "Blindado", "hp": 1.3, "speed": 0.9, "color": Color(0.7, 0.75, 0.82),
		"resist": {"arrow": 0.5, "melee": 0.35}, "desc": "resiste a flechas e aos soldados"},
	"arcano": {"name": "Arcano", "hp": 1.15, "speed": 1.0, "color": Color(0.75, 0.4, 1.0),
		"resist": {"bolt": 0.6}, "no_slow": true, "desc": "resiste à Torre Arcana e não fica lento"},
	"agil": {"name": "Ágil", "hp": 0.9, "speed": 1.35, "color": Color(1.0, 0.85, 0.25),
		"resist": {"ball": 0.5}, "desc": "rápido e desvia de explosões"},
	"colosso": {"name": "Colosso", "hp": 2.2, "speed": 0.85, "color": Color(1.0, 0.3, 0.2), "bld": 1.3,
		"scale": 1.3, "resist": {}, "night": 12, "desc": "enorme, derruba muros"},
}
## Noites especiais (a partir de MOD_NIGHT), anunciadas no amanhecer anterior.
const MOD_NIGHT := 7
const NIGHT_MODS := {
	"lua_sangue": {"name": "Lua de Sangue", "desc": "monstros 25% mais rápidos e fortes", "color": Color(1, 0.3, 0.25)},
	"nevoa": {"name": "Névoa Densa", "desc": "torres com 30% menos alcance", "color": Color(0.75, 0.8, 0.9)},
	"enxame": {"name": "Enxame", "desc": "60% mais monstros, porém mais frágeis", "color": Color(0.6, 1.0, 0.4)},
	"cerco": {"name": "Cerco Pesado", "desc": "muito mais Goblins Brutos atrás dos muros", "color": Color(1, 0.6, 0.3)},
}
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
## A prefeitura continua em ouro (as eras a substituem).
static func upgrade_cost(kind: String, level: int) -> Dictionary:
	var base: Dictionary = {"gold": 250} if kind == "town_hall" else BUILDINGS[kind].cost
	var c := scale_cost(base, 0.8 * level)
	if level >= 2 and kind != "town_hall":
		c = add_cost(c, {"iron": 5})
	return c
