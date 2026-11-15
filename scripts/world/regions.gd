class_name Regions
extends RefCounted
## Mapas do mundo aberto (puro, sem autoload). O vale de Valdoria fica na origem; os outros mapas são
## regiões com terreno próprio montadas na mesma cena, bem longe (fora do alcance da câmera), e a viagem é
## pela carruagem da guilda. Assim tudo continua na zona "world" da rede: solo e online iguais.
##   origin = centro do mapa; half = meia largura; rank = rank da guilda para viajar até lá;
##   coach = ponto da carruagem (relativo ao centro); arrive = onde o jogador chega (relativo ao centro).

const DATA := {
	"vila": {"name": "Vale de Valdoria", "origin": Vector3(0, 0, 0), "half": 125.0, "rank": "D",
		"coach": Vector3(-7.5, 0, -18.0), "arrive": Vector3(-4.0, 0.3, -16.0)},
	"bosque": {"name": "Bosque Sussurrante", "origin": Vector3(0, 0, 800), "half": 70.0, "rank": "C",
		"coach": Vector3(-4.0, 0, 56.0), "arrive": Vector3(0.0, 0.3, 52.0)},
	"mina": {"name": "Mina de Cristal", "origin": Vector3(800, 0, 0), "half": 70.0, "rank": "B",
		"coach": Vector3(-4.0, 0, 56.0), "arrive": Vector3(0.0, 0.3, 52.0)},
	"pico": {"name": "Pico das Cinzas", "origin": Vector3(800, 0, 800), "half": 62.0, "rank": "A",
		"coach": Vector3(-4.0, 0, 48.0), "arrive": Vector3(0.0, 0.3, 44.0)},
}
const ORDER := ["vila", "bosque", "mina", "pico"]


static func origin(id: String) -> Vector3:
	return DATA[id].origin


## Posição global de um ponto dado relativo ao centro da região.
static func at(id: String, local: Vector3) -> Vector3:
	return DATA[id].origin + local


static func arrive_point(id: String) -> Vector3:
	return at(id, DATA[id].arrive)


static func coach_point(id: String) -> Vector3:
	return at(id, DATA[id].coach)


static func display_name(id: String) -> String:
	return str(DATA.get(id, {}).get("name", id))


## Em que mapa fica a posição (fora de todas as regiões = o vale).
static func region_at(pos: Vector3) -> String:
	for id in ORDER:
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
