class_name Regions
extends RefCounted
## Mapas do mundo aberto (puro, sem autoload). O vale de Valdoria fica na origem; os outros mapas são
## regiões com terreno próprio montadas na mesma cena, bem longe (fora do alcance da câmera), e a viagem é
## pela carruagem da guilda. Assim tudo continua na zona "world" da rede: solo e online iguais.
##   origin = centro do mapa; half = meia largura; rank = rank da guilda para viajar até lá;
## A carruagem e o ponto de chegada de cada mapa são landmarks da cena dele ("coach", "arrive"; MapData).

const DATA := {
	"vila": {"name": "Vale de Valdoria", "origin": Vector3(0, 0, 0), "half": 125.0, "rank": "D"},
	"bosque": {"name": "Pântano Sussurrante", "origin": Vector3(0, 0, 800), "half": 70.0, "rank": "C"},
	"mina": {"name": "Geleira de Cristal", "origin": Vector3(800, 0, 0), "half": 70.0, "rank": "B"},
	"pico": {"name": "Vulcão das Cinzas", "origin": Vector3(800, 0, 800), "half": 62.0, "rank": "A"},
	# dungeons (parte 4): áreas compartilhadas com entrada por uma porta no mapa de fora (`parent`). Não estão
	# na carruagem nem no atlas; o rank é o da porta. A faixa de nível das salas fica no regions.json.
	"dg_bosque": {"name": "Covil das Raízes", "origin": Vector3(-800, 0, 800), "half": 45.0, "rank": "C",
		"dungeon": true, "parent": "bosque"},
	"dg_mina": {"name": "Galerias Profundas", "origin": Vector3(-800, 0, 0), "half": 55.0, "rank": "B",
		"dungeon": true, "parent": "mina"},
	"dg_pico": {"name": "Cripta de Cinzas", "origin": Vector3(-800, 0, -800), "half": 45.0, "rank": "A",
		"dungeon": true, "parent": "pico"},
	"dg_final": {"name": "Abismo de Valdoria", "origin": Vector3(800, 0, -800), "half": 45.0, "rank": "A",
		"dungeon": true, "parent": "pico"},
}
## Mapas de viagem (carruagem e atlas), na ordem.
const ORDER := ["vila", "bosque", "mina", "pico"]
## Dungeons, na ordem de nível.
const DUNGEONS := ["dg_bosque", "dg_mina", "dg_pico", "dg_final"]
## Todos os mapas montados no mundo.
const ALL := ["vila", "bosque", "mina", "pico", "dg_bosque", "dg_mina", "dg_pico", "dg_final"]


static func origin(id: String) -> Vector3:
	return DATA[id].origin


## Posição global de um ponto dado relativo ao centro da região.
static func at(id: String, local: Vector3) -> Vector3:
	return DATA[id].origin + local


static func arrive_point(id: String) -> Vector3:
	return MapData.landmark(id, "arrive")


static func coach_point(id: String) -> Vector3:
	return MapData.landmark(id, "coach")


static func is_dungeon(id: String) -> bool:
	return bool(DATA.get(id, {}).get("dungeon", false))


## Mapa de fora da dungeon (o próprio id para quem não é dungeon).
static func parent_of(id: String) -> String:
	return str(DATA.get(id, {}).get("parent", id))


## Onde fica a porta da dungeon no mapa de fora (landmark "dg:<id>" da cena do mapa de fora).
static func door_point(dungeon: String) -> Vector3:
	return MapData.landmark(parent_of(dungeon), "dg:" + dungeon)


## Para onde se volta para sair do mapa: a carruagem nos mapas, a porta de saída (a chegada) nas dungeons.
static func exit_point(id: String) -> Vector3:
	return arrive_point(id) if is_dungeon(id) else coach_point(id)


## Dungeons cuja porta fica no mapa `map_id`.
static func dungeons_of(map_id: String) -> Array:
	return DUNGEONS.filter(func(d: String) -> bool: return parent_of(d) == map_id)


static func display_name(id: String) -> String:
	return str(DATA.get(id, {}).get("name", id))


## Em que mapa fica a posição (fora de todas as regiões = o vale).
static func region_at(pos: Vector3) -> String:
	for id in ALL:
		if id == "vila":
			continue
		var o: Vector3 = DATA[id].origin
		var h: float = DATA[id].half + 30.0
		if absf(pos.x - o.x) <= h and absf(pos.z - o.z) <= h:
			return id
	return "vila"


## Se o rank da guilda deixa viajar para lá (ranks = ordem "D".."S").
static func unlocked(id: String, rank: String) -> bool:
	return StoryRules.rank_ge(rank, str(DATA[id].rank))


# ================================================================ regiões com nome (dentro dos mapas)
# Forma e lugar: nós MapRegion das cenas (MapData.areas). Números: data/balance/regions.json, que quem chama
# passa como `table` (estas funções são puras: o jogo passa Balance.tables.get_table("regions")).

## Se a posição (só X e Z) fica dentro da área `a` (um item de MapData.areas).
static func area_has(a: Dictionary, pos: Vector3) -> bool:
	var d := Vector2(pos.x - a.center.x, pos.z - a.center.z)
	if int(a.shape) == MapRegion.DISC:
		return d.length() <= float(a.radius)
	# volta o ponto pelo giro do nó (o retângulo gira em Y; Y positivo leva +X para -Z)
	var l := d.rotated(float(a.rot))
	var s: Vector2 = a.size
	return absf(l.x) <= s.x / 2.0 and absf(l.y) <= s.y / 2.0


static func _area_size(a: Dictionary) -> float:
	if int(a.shape) == MapRegion.DISC:
		return PI * float(a.radius) * float(a.radius)
	return (a.size as Vector2).x * (a.size as Vector2).y


## A região de `areas` que contém a posição ("" = nenhuma). Se mais de uma contém, a de menor área ganha (o
## Cume Maldito fica dentro das Ameias do Lich).
static func pick(areas: Array, pos: Vector3) -> String:
	var best := ""
	var best_size := INF
	for a in areas:
		if area_has(a, pos) and _area_size(a) < best_size:
			best_size = _area_size(a)
			best = str(a.id)
	return best


## Região com nome onde fica a posição ("" = fora de todas). Irmã de region_at (que diz o mapa).
static func area_at(pos: Vector3) -> String:
	return pick(MapData.areas(region_at(pos)), pos)


## Centro da região (o do primeiro nó dela); Vector3.INF se nenhum mapa tem a região.
static func area_center(id: String) -> Vector3:
	for a in MapData.all_areas():
		if a.id == id:
			return a.center
	return Vector3.INF


## Números da região no regions.json, com padrões (região sem dado: nome = id, sem faixa, densidade 1).
static func area_info(table: Dictionary, id: String) -> Dictionary:
	var d: Dictionary = table.get(id, {})
	var lo := int(d.get("level_min", 0))
	return {"name": str(d.get("name", id)), "level_min": lo, "level_max": maxi(int(d.get("level_max", lo)), lo),
		"density": float(d.get("density", 1.0)), "show_on_map": bool(d.get("show_on_map", true))}


## "Toca dos Goblins · Nv 5–9" (faixa de um nível só: "Nv 20"; sem faixa: só o nome).
static func area_label(table: Dictionary, id: String) -> String:
	var i := area_info(table, id)
	if i.level_min <= 0:
		return i.name
	if i.level_max == i.level_min:
		return "%s · Nv %d" % [i.name, i.level_min]
	return "%s · Nv %d–%d" % [i.name, i.level_min, i.level_max]


## Faixa de nível de um ponto de monstro: o nível do ponto (> 0) manda; com 0, a faixa da região onde ele fica;
## fora de região (ou região sem faixa) continua (0, 0) = o ref_level do monstro.
static func spawn_range(table: Dictionary, area: String, level: int, level_max: int) -> Vector2i:
	if level > 0:
		return Vector2i(level, level_max)
	if area == "":
		return Vector2i.ZERO
	var i := area_info(table, area)
	if i.level_min <= 0:
		return Vector2i.ZERO
	return Vector2i(i.level_min, i.level_max)


## Quantos monstros um ponto mantém dentro da região (count × densidade, arredondado).
static func spawn_count(table: Dictionary, area: String, count: int) -> int:
	if area == "":
		return count
	return maxi(0, roundi(count * float(area_info(table, area).density)))
