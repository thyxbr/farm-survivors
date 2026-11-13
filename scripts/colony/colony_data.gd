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
const BUILDINGS := {
	"town_hall": {"name": "Prefeitura", "cost": 0, "hp": 1600, "size": Vector2(7.4, 6.4), "pop": 6, "gold": 15,
		"desc": "O coração da cidade: abriga 6 moradores e rende 15 ouro por dia. Se cair, a cidade cai."},
	"house": {"name": "Casa", "cost": 60, "hp": 320, "size": Vector2(5.6, 4.6), "pop": 5,
		"desc": "Abriga 5 moradores. Moradores pagam impostos e podem ser recrutados."},
	"farm": {"name": "Fazenda", "cost": 70, "hp": 240, "size": Vector2(7.0, 6.0), "food": 12, "workers": 2,
		"desc": "Produz 12 de comida por dia. Emprega 2 moradores."},
	"market": {"name": "Mercado", "cost": 140, "hp": 380, "size": Vector2(5.2, 5.2), "gold": 25, "workers": 2,
		"desc": "Rende 25 ouro por dia com o comércio. Emprega 2 moradores."},
	"barracks": {"name": "Quartel", "cost": 160, "hp": 650, "size": Vector2(6.6, 5.6), "army": 6,
		"desc": "Recrute o exército aqui (E). Cada quartel aloja 6 soldados."},
	"wall": {"name": "Muro", "cost": 12, "hp": 420, "size": Vector2(4.0, 0.9), "wall": true,
		"desc": "Segura os monstros. Encoste um no outro para fechar a cidade."},
	"gate": {"name": "Portão", "cost": 40, "hp": 520, "size": Vector2(4.0, 1.1), "wall": true,
		"desc": "Você e seus soldados passam; os monstros precisam derrubar."},
	"spikes": {"name": "Estacas", "cost": 30, "hp": 200, "size": Vector2(4.0, 1.6), "dps": 16, "wall": true,
		"desc": "Ferem e atrasam os monstros que passam por cima. Desgastam com o uso."},
	"archer_tower": {"name": "Torre de Arqueiros", "cost": 110, "hp": 460, "size": Vector2(3.2, 3.2),
		"range": 20.0, "damage": 14.0, "rate": 0.95, "shot": "arrow",
		"desc": "Dispara flechas rápidas no monstro mais próximo."},
	"cannon_tower": {"name": "Torre de Canhão", "cost": 200, "hp": 620, "size": Vector2(3.8, 3.8),
		"range": 23.0, "damage": 40.0, "rate": 2.8, "splash": 3.2, "shot": "ball",
		"desc": "Balas lentas que explodem e ferem todos em volta."},
	"mage_tower": {"name": "Torre Arcana", "cost": 170, "hp": 420, "size": Vector2(3.2, 3.2),
		"range": 17.0, "damage": 16.0, "rate": 1.3, "slow": 2.0, "chain": 2, "shot": "bolt",
		"desc": "Raio gélido que deixa lento e salta para mais 2 monstros."},
}

## Unidades recrutáveis no quartel. look = equipamentos usados para vestir o modelo do cavaleiro.
const UNITS := {
	"militia": {"name": "Miliciano", "cost": 30, "salary": 2, "hp": 70, "damage": 8.0, "reach": 1.9,
		"cooldown": 1.1, "speed": 4.6, "armor": 0, "aggro": 13.0,
		"look": {"weapon": "wooden_sword", "head": "leather_cap"},
		"desc": "Barato, mas frágil."},
	"soldier": {"name": "Soldado", "cost": 70, "salary": 5, "hp": 150, "damage": 15.0, "reach": 2.0,
		"cooldown": 1.0, "speed": 4.4, "armor": 5, "aggro": 13.0,
		"look": {"weapon": "iron_sword", "offhand": "wooden_shield", "head": "iron_helm", "armor": "chain_mail"},
		"desc": "Espada e escudo: segura a linha."},
	"archer": {"name": "Arqueiro", "cost": 80, "salary": 6, "hp": 80, "damage": 12.0, "reach": 15.0,
		"cooldown": 1.3, "speed": 4.6, "armor": 1, "aggro": 17.0, "ranged": true,
		"look": {"weapon": "hunter_bow", "offhand": "hunter_quiver", "head": "ranger_hood", "armor": "leather_armor"},
		"desc": "Atira por cima dos muros."},
	"knight": {"name": "Cavaleiro", "cost": 180, "salary": 12, "hp": 300, "damage": 28.0, "reach": 2.3,
		"cooldown": 1.15, "speed": 4.9, "armor": 12, "aggro": 15.0, "needs_level": 2,
		"look": {"weapon": "guardian_greatsword", "head": "knight_helm", "armor": "royal_plate",
			"hands": "iron_gauntlets", "feet": "iron_greaves"},
		"desc": "Elite. Exige um quartel nível 2."},
}
const UNIT_ORDER := ["militia", "soldier", "archer", "knight"]

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
