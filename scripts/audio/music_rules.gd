class_name MusicRules
extends RefCounted
## Regra pura de qual música e qual som ambiente tocam, a partir de um retrato do momento (ctx).
## O autoload Music monta o ctx a cada meio segundo; aqui não há cena nem nó, para dar para testar.
##
## ctx (todas as chaves opcionais):
##   scene: "menu" | "world" | ""
##   dead: bool              jogador local caído
##   boss_near: bool         chefe vivo perto do jogador
##   horde: bool             Desafio da Horda em andamento
##   pos: Vector3            posição do jogador (no mundo aberto)

## A música da vila vai até VILLAGE_MARGIN m além da cerca (VillageLayout.BOUNDS). Antes era um círculo de
## 30 m em volta da praça, que passava da cerca norte e seguia tocando até os campos das slimes.
const VILLAGE_MARGIN := 4.0
const FARM_CENTER := Vector2(0, 33)
const FARM_RADIUS := 16.0
const RUINS_CENTER := Vector2(0, -100)
const RUINS_RADIUS := 38.0

## Faixas: id -> arquivos (assets/audio/music). Mais de um arquivo vira playlist (um depois do outro);
## um só fica em loop; lista vazia = silêncio (derrota).
const TRACKS := {
	"menu": ["menu_asamis_journey"],
	# evento de Natal; fora dele a vila toca "village_squirrel_village". Guardada para outro momento:
	# "village_morning_frost" (Morning Frost & Cheerful Christmas Time).
	"village": ["village_deck_the_halls"],
	"wild": ["wild_greenland_theme"],
	"ruins": ["ruins_dark_cavern"],
	"boss": ["boss_blackmoor_colossus"],
	"horde": ["combat_battle_theme_3"],
	"game_over": [],
}
## Faixas que tocam uma vez só e param (sem loop nem playlist).
const ONE_SHOT: Array[String] = []

const AMBIENCES := {
	"day": "birds_wind",
	"night": "crickets_night",
}


static func track(ctx: Dictionary) -> String:
	var scene: String = ctx.get("scene", "")
	if scene == "menu":
		return "menu"
	if scene == "":
		return ""
	if ctx.get("dead", false):
		return "game_over"
	if ctx.get("boss_near", false):
		return "boss"
	match scene:
		"world":
			if ctx.get("horde", false):
				return "horde"
			return area(ctx.get("pos", Vector3.ZERO))
	return ""


## Trecho do mundo aberto em que o jogador está: vila (com a horta), ruínas do Rei Goblin ou mata.
static func area(pos: Vector3) -> String:
	match Regions.region_at(pos):
		"bosque":
			return "wild"
		"mina", "pico":
			return "ruins"
	var p := Vector2(pos.x, pos.z)
	if VillageLayout.BOUNDS.grow(VILLAGE_MARGIN).has_point(p) or p.distance_to(FARM_CENTER) < FARM_RADIUS:
		return "village"
	if p.distance_to(RUINS_CENTER) < RUINS_RADIUS:
		return "ruins"
	return "wild"


static func ambience(ctx: Dictionary) -> String:
	match ctx.get("scene", ""):
		"world":
			return "" if ctx.get("horde", false) else "day"
	return ""
