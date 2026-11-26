class_name ExpeditionDefs
extends RefCounted
## Expedições do modo roguelite (puro, sem autoload): de qual bioma vêm, que cena de mapa montam e o grafo das
## salas. A geometria das salas fica na cena (MapDungeonRoom com o mesmo nome do nó); aqui fica só a ordem e o
## papel de cada uma. `next` é uma lista: hoje a rota é reta, mas uma sala pode abrir mais de um caminho
## (ramificações) sem mudar o ExpeditionRun.
##
## Tipos de sala (ROOM_KINDS):
##   start  — chegada, sem monstros (a saída para a Guilda fica nela)
##   combat — monstros comuns; precisa limpar para contar no progresso
##   elite  — (futuro) bando mais forte; conta no progresso
##   reward / event / rest — (futuro) sala sem luta obrigatória
##   boss   — chefe; limpar a sala de chefe conclui a expedição (vitória)

const ROOM_KINDS := ["start", "combat", "elite", "reward", "event", "rest", "boss"]
## Tipos que precisam ser limpos (todos os monstros mortos) para contar no progresso.
const CLEAR_KINDS := ["combat", "elite", "boss"]
## Tipos de sala que podem dar uma melhoria temporária ao serem limpos ("reward": true na sala; ExpeditionUpgrades).
## A sala de chefe não entra: limpá-la encerra a run.
const REWARD_KINDS := ["combat", "elite"]

## Ordem em que as expedições aparecem na seleção da Guilda (expedition_select_ui.gd). Bioma novo: entra em DATA
## e aqui; sem mais nada a mudar na seleção.
const ORDER := ["pantano"]

const DATA := {
	"pantano": {
		"name": "Pântano Sussurrante",
		"map": "exp_pantano",    # MapData.SCENES / EXTRA_ORIGINS
		"biome": "bosque",       # Regions.DATA: de onde vêm o tema, os monstros e a faixa de nível
		"ambience": "dg_bosque", # clima, céu e música como dentro do Covil das Raízes (ambience_at)
		"rank": "C",             # dificuldade mostrada na seleção da Guilda
		"half": 70.0,            # meia largura da cena (MapRoot.half)
		# texto da seleção da Guilda
		"desc": "Um brejo de névoa e raízes onde as vozes dos afogados guiam os incautos. "
			+ "No coração do pântano, a Espinheira guarda o Trono da Rainha.",
		"boss": "Espinheira",
		"start": "Entrada",
		"rooms": {
			"Entrada": {"kind": "start", "next": ["Encruzilhada"]},
			"Encruzilhada": {"kind": "combat", "reward": true, "next": ["Clareira Funda"]},
			"Clareira Funda": {"kind": "combat", "reward": true, "next": ["Salão do Portão"]},
			"Salão do Portão": {"kind": "rest", "next": ["Trono da Rainha"]},
			"Trono da Rainha": {"kind": "boss", "next": []},
		},
	},
}


static func has(id: String) -> bool:
	return DATA.has(id)


## Definição da expedição (vazia se não existe).
static func get_def(id: String) -> Dictionary:
	return DATA.get(id, {})


static func display_name(id: String) -> String:
	return str(get_def(id).get("name", id))


## Id do mapa (MapData) que a expedição monta ("" se não existe).
static func map_of(id: String) -> String:
	return str(get_def(id).get("map", ""))


## Se `map_id` é o mapa de alguma expedição (o MapLoader trata como dungeon e não põe portal de chefe).
static func is_map(map_id: String) -> bool:
	if map_id == "":
		return false
	for id in DATA:
		if str(DATA[id].map) == map_id:
			return true
	return false


## Se a posição global cai na área de alguma expedição (ninguém pode nascer lá com a expedição desmontada).
static func is_inside(pos: Vector3) -> bool:
	return expedition_at(pos) != ""


## Expedição em cuja área fica a posição global ("" = nenhuma). A área é o mapa com a mesma folga do
## Regions.region_at (meia largura + 30 m).
static func expedition_at(pos: Vector3) -> String:
	for id in DATA:
		var o := MapData.origin(str(DATA[id].map))
		var h := float(DATA[id].get("half", 70.0)) + 30.0
		if absf(pos.x - o.x) <= h and absf(pos.z - o.z) <= h:
			return id
	return ""


## Mapa cuja ambientação (clima, céu, música) vale na posição: o `ambience` da expedição dentro dela, senão o
## Regions.region_at de sempre. Só para o que é visual/sonoro: regras de jogo (saque, missões, morte) continuam
## no region_at, que não conhece as expedições.
static func ambience_at(pos: Vector3) -> String:
	var id := expedition_at(pos)
	if id == "":
		return Regions.region_at(pos)
	return str(DATA[id].get("ambience", DATA[id].get("biome", "vila")))


static func rooms(def: Dictionary) -> Dictionary:
	return def.get("rooms", {})


static func kind_of(def: Dictionary, room: String) -> String:
	return str(rooms(def).get(room, {}).get("kind", ""))


static func next_of(def: Dictionary, room: String) -> Array:
	return rooms(def).get(room, {}).get("next", [])


static func needs_clear(def: Dictionary, room: String) -> bool:
	return kind_of(def, room) in CLEAR_KINDS


## Salas que precisam ser limpas (as que contam no progresso).
static func clear_rooms(def: Dictionary) -> Array:
	return rooms(def).keys().filter(func(r: String) -> bool: return needs_clear(def, r))


## Limpar `room` dá uma melhoria temporária (sala de luta comum/elite marcada com "reward": true).
static func grants_reward(def: Dictionary, room: String) -> bool:
	return bool(rooms(def).get(room, {}).get("reward", false)) and kind_of(def, room) in REWARD_KINDS


## Salas que dão melhoria ao serem limpas.
static func reward_rooms(def: Dictionary) -> Array:
	return rooms(def).keys().filter(func(r: String) -> bool: return grants_reward(def, r))


## Expedições na ordem da seleção da Guilda (só as que existem em DATA).
static func ids() -> Array[String]:
	var out: Array[String] = []
	for id in ORDER:
		if DATA.has(id):
			out.append(id)
	return out


## Salas alcançáveis a partir da chegada seguindo `next`.
static func reachable(def: Dictionary) -> Dictionary:
	var start := str(def.get("start", ""))
	if not rooms(def).has(start):
		return {}
	var seen := {start: true}
	var todo: Array = [start]
	while not todo.is_empty():
		var r: String = todo.pop_back()
		for n in next_of(def, r):
			if rooms(def).has(n) and not seen.has(n):
				seen[n] = true
				todo.append(n)
	return seen


## Problemas da definição ([] = ok): chegada existe e é "start", tipos conhecidos, `next` aponta para salas que
## existem, toda sala é alcançável e há ao menos uma sala de chefe no caminho.
static func validate(def: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var rs := rooms(def)
	if rs.is_empty():
		out.append("expedição sem salas")
		return out
	var start := str(def.get("start", ""))
	if not rs.has(start):
		out.append("chegada '%s' não é uma sala" % start)
	elif kind_of(def, start) != "start":
		out.append("chegada '%s' precisa ser do tipo start" % start)
	var bosses := 0
	for r in rs:
		var k := kind_of(def, r)
		if not k in ROOM_KINDS:
			out.append("sala '%s' com tipo desconhecido '%s'" % [r, k])
		if k == "boss":
			bosses += 1
		if bool(rs[r].get("reward", false)) and not k in REWARD_KINDS:
			out.append("sala '%s' do tipo '%s' não pode dar recompensa" % [r, k])
		for n in next_of(def, r):
			if not rs.has(n):
				out.append("sala '%s' leva a '%s', que não existe" % [r, n])
			elif n == r:
				out.append("sala '%s' leva a ela mesma" % r)
	var seen := reachable(def)
	for r in rs:
		if not seen.has(r):
			out.append("sala '%s' não é alcançável a partir da chegada" % r)
	if bosses == 0:
		out.append("expedição sem sala de chefe (não há como vencer)")
	return out
