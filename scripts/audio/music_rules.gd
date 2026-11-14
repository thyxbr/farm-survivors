class_name MusicRules
extends RefCounted
## Regra pura de qual música e qual som ambiente tocam, a partir de um retrato do momento (ctx).
## O autoload Music monta o ctx a cada meio segundo; aqui não há cena nem nó, para dar para testar.
##
## ctx (todas as chaves opcionais):
##   scene: "menu" | "hub" | "world" | "colony" | ""
##   dead: bool              jogador local caído
##   boss_near: bool         chefe vivo perto do jogador
##   horde: bool             Desafio da Horda em andamento
##   phase: String           fase da Defesa da Cidade (setup | day | night | over)
##   pos: Vector3            posição do jogador (no mundo aberto)

const VILLAGE_CENTER := Vector2(0, 4)
const VILLAGE_RADIUS := 30.0
const FARM_CENTER := Vector2(0, 33)
const FARM_RADIUS := 16.0
const RUINS_CENTER := Vector2(0, -100)
const RUINS_RADIUS := 38.0

## Faixas: id -> arquivos (assets/audio/music). Mais de um arquivo vira playlist (um depois do outro);
## um só fica em loop; lista vazia = silêncio (derrota).
const TRACKS := {
	"menu": ["menu_asamis_journey"],
	"hub": ["hub_town_theme"],
	"village": ["village_squirrel_village"],
	"wild": ["wild_greenland_theme"],
	"ruins": ["ruins_dark_cavern"],
	"boss": ["boss_blackmoor_colossus"],
	"horde": ["combat_battle_theme_3"],
	"city_day": ["village_squirrel_village"],
	"city_night": ["combat_battle_theme_3"],
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
	if ctx.get("dead", false) or (scene == "colony" and ctx.get("phase", "") == "over"):
		return "game_over"
	if ctx.get("boss_near", false):
		return "boss"
	match scene:
		"hub":
			return "hub"
		"colony":
			return "city_night" if ctx.get("phase", "") == "night" else "city_day"
		"world":
			if ctx.get("horde", false):
				return "horde"
			return area(ctx.get("pos", Vector3.ZERO))
	return ""


## Trecho do mundo aberto em que o jogador está: vila (com a horta), ruínas do Rei Goblin ou mata.
static func area(pos: Vector3) -> String:
	var p := Vector2(pos.x, pos.z)
	if p.distance_to(VILLAGE_CENTER) < VILLAGE_RADIUS or p.distance_to(FARM_CENTER) < FARM_RADIUS:
		return "village"
	if p.distance_to(RUINS_CENTER) < RUINS_RADIUS:
		return "ruins"
	return "wild"


static func ambience(ctx: Dictionary) -> String:
	match ctx.get("scene", ""):
		"hub", "world":
			return "" if ctx.get("horde", false) else "day"
		"colony":
			return "night" if ctx.get("phase", "") == "night" else "day"
	return ""
