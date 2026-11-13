extends RefCounted
## Eventos aleatórios e desafios das rodadas do Desafio da Horda.
## O dono da partida (solo ou servidor) sorteia no começo de cada rodada; no multiplayer o id
## chega aos clientes junto com a rodada (_horde_round_start).

const EVENTS := {
	"meteoros": {"name": "Chuva de Meteoros", "color": Color(1.0, 0.5, 0.2),
		"desc": "Meteoros caem na arena: saia dos círculos vermelhos!"},
	"lua_sangue": {"name": "Lua de Sangue", "color": Color(1.0, 0.25, 0.3),
		"desc": "Monstros mais rápidos e fortes, mas as gemas valem o dobro."},
	"febre_ouro": {"name": "Febre do Ouro", "color": Color(1.0, 0.82, 0.25),
		"desc": "Goblins Dourados fogem pela arena. Pegue-os antes que escapem!"},
	"enxame": {"name": "Enxame", "color": Color(0.95, 0.45, 0.3),
		"desc": "O dobro de monstros, porém mais frágeis."},
	"campeoes": {"name": "Campeões", "color": Color(0.9, 0.35, 0.25),
		"desc": "Campeões Goblin entram na arena. Derrote-os por um bom saque."},
	"emboscada": {"name": "Emboscada", "color": Color(0.75, 0.55, 1.0),
		"desc": "A horda surge cercando o grupo!"},
}

## Desafio opcional da rodada: abater N inimigos antes do tempo acabar rende um baú para todos.
const HUNT := {"name": "Caçada", "color": Color(0.5, 0.9, 1.0)}

## Ritmo em "dente de serra" dentro de cada ciclo de 5 rodadas: a pressão sobe até a rodada 4 do ciclo e
## alivia na rodada do chefe (que já é o desafio). Cada ciclo começa mais forte que o anterior.
const SAW := [0.85, 1.0, 1.1, 1.25, 0.7]

const FIRST_EVENT_ROUND := 2
const EVENT_CHANCE := 0.7
const HUNT_CHANCE := 0.45


## Sorteia o evento da rodada ("" = rodada normal). Rodadas de chefe não têm evento.
static func roll_event(round_num: int, boss_round: bool, last := "") -> String:
	if boss_round or round_num < FIRST_EVENT_ROUND or randf() > EVENT_CHANCE:
		return ""
	var ids: Array = EVENTS.keys()
	ids.erase(last)   # não repete o evento da rodada anterior
	if round_num < 4:
		ids.erase("campeoes")
	return ids.pick_random()


## Meta da Caçada (0 = sem desafio nesta rodada).
static func roll_hunt(round_num: int, boss_round: bool, team: int, round_time: float) -> int:
	if boss_round or round_num < FIRST_EVENT_ROUND or randf() > HUNT_CHANCE:
		return 0
	# ~70% do que nasce na rodada (mesma taxa de survival_mode._spawn_tick)
	var per_sec := spawn_rate(round_num, team)
	return maxi(10, int(per_sec * round_time * 0.7 / 5.0) * 5)


static func event_name(id: String) -> String:
	return EVENTS[id].name if EVENTS.has(id) else ""


static func event_color(id: String) -> Color:
	return EVENTS[id].color if EVENTS.has(id) else Color.WHITE


static func event_desc(id: String) -> String:
	return EVENTS[id].desc if EVENTS.has(id) else ""


## Inimigos por segundo na rodada (sem evento nem chefe), usado pelo spawn e pela meta da Caçada.
static func spawn_rate(round_num: int, team: int) -> float:
	return (1.0 + 0.42 * (round_num - 1)) * float(SAW[(round_num - 1) % SAW.size()]) * (1.0 + 0.7 * (team - 1))
