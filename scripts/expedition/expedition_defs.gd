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
##   elite  — bando com um líder de elite (mais forte, com nome); conta no progresso e dá uma bênção melhor
##   altar  — sala do Altar da Deusa (sem luta)
##   event  — sala com um evento (escolha com consequência na run: ExpeditionEvents)
##   reward — sala de recompensa (o santuário da sala dá uma bênção ao ser usado)
##   rest   — descanso (o santuário da sala, se houver, cura uma vez)
##   boss   — chefe; limpar a sala de chefe conclui a expedição (vitória)
##
## Encontros (salas de CLEAR_KINDS): entrar na sala fecha as passagens dela (barreiras do expedition_mode) até
## a luta acabar. "waves" na sala = lista de ondas, cada onda uma lista de {"kind": id do enemies.json, "count": n}
## (e "elite": true opcional; "leader": true = o líder da sala de elite, ver "leader"). A próxima onda só nasce
## quando a atual cai inteira, e nada nasce antes de o jogador entrar. Sala de luta sem "waves" (o chefe) é uma
## onda só: os pontos de monstro (EnemySpawn) da cena.
##
## Líder de elite ("leader" na sala de elite): {"name": nome na placa, "call": [grupos], "call_at": fração da vida}.
## O monstro do grupo com "leader": true ganha o nome, o balanceamento de elite (ExpeditionBalance "elite") e, quando
## a vida dele cai abaixo de `call_at`, chama os grupos de `call` uma vez só (reforços que também precisam cair).
##
## Bênçãos ("reward": true; ExpeditionUpgrades): sala de luta dá a escolha ao ser limpa; sala "reward"/"altar" dá
## quando o santuário/altar dela é usado. "reward_stacks" = acúmulos que a bênção escolhida soma (padrão: 2 na sala
## de elite, 1 nas outras).
##
## Altar da Deusa ("altar" na sala; skill_altar.gd + ExpeditionSkills): {"at": [x, z]} = lugar do altar em metros a
## partir do centro da sala. Usado uma vez só: escolhe 1 de 3 habilidades para o kit temporário da run. Numa sala de
## luta ele só desperta depois que a sala é limpa. Sala de chefe não tem altar (limpá-la encerra a run). Se não há
## mais habilidade para ensinar e a sala tem "reward": true, o altar oferece uma bênção no lugar.
## "mode": "evolve" no altar (Altar Ancestral) = altar de evolução da build: as 3 opções misturam uma habilidade nova,
## uma melhoria de habilidade que o jogador já tem (ExpeditionUpgrades: Potência, Recuperação, Persistência) e uma
## bênção de run, conforme a build (ExpeditionSkills.roll_evolution). Sem "mode" = só habilidades novas.
##
## Santuário ("shrine" na sala; run_shrine.gd): {"at": [x, z]} e, conforme o tipo da sala:
##   event  — "event": id do ExpeditionEvents (a escolha da sala)
##   reward — a bênção da sala (precisa de "reward": true)
##   rest   — "heal": fração da vida máxima recuperada (uma vez só)
## A sala de luta com o encontro "offering" (Defesa das Oferendas) também tem santuário: o baú da bênção da sala,
## lacrado até a luta acabar (shrine_kind = "reward").
##
## Encontros especiais ("encounter" numa sala de luta; ExpeditionEncounters): emboscada, caçada ao elite, ritual
## corrompido e defesa das oferendas. Mudam como a luta começa, onde os monstros nascem e o que libera a sala,
## sempre pelas mesmas ondas, barreiras e ExpeditionRun. Sala sem "encounter" é a luta tradicional.

const ROOM_KINDS := ["start", "combat", "elite", "altar", "event", "reward", "rest", "boss"]
## Tipos que precisam ser limpos (todos os monstros mortos) para contar no progresso.
const CLEAR_KINDS := ["combat", "elite", "boss"]
## Tipos de sala com ondas.
const WAVE_KINDS := ["combat", "elite"]
## Tipos de sala que podem dar uma melhoria temporária ("reward": true na sala; ExpeditionUpgrades). As de luta dão
## ao serem limpas; as outras pelo santuário/altar. A sala de chefe não entra: limpá-la encerra a run.
const REWARD_KINDS := ["combat", "elite", "reward", "altar"]
## Tipos de sala que podem ter Altar da Deusa.
const ALTAR_KINDS := ["start", "combat", "elite", "altar", "reward", "event", "rest"]
## Modos do altar: "skill" ensina uma habilidade nova; "evolve" evolui a build (habilidade nova, melhoria de
## habilidade ou bênção).
const ALTAR_SKILL := "skill"
const ALTAR_EVOLVE := "evolve"
const ALTAR_MODES := [ALTAR_SKILL, ALTAR_EVOLVE]
## Tipos de sala que podem ter santuário (o tipo da sala é o tipo do santuário).
const SHRINE_KINDS := ["event", "reward", "rest"]

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
		"half": 100.0,           # meia largura da cena (MapRoot.half)
		# texto da seleção da Guilda
		"desc": "Um brejo de névoa e raízes onde as vozes dos afogados guiam os incautos. Treze etapas de lama, "
			+ "ruínas, emboscadas, rituais e elites até o coração do pântano, onde a Espinheira guarda o Trono da Rainha.",
		"boss": "Espinheira",
		"start": "Entrada",
		# Rota linear de 13 etapas até o chefe. Ritmo: luta curta -> habilidade -> luta -> evento -> elite ->
		# recompensa -> luta longa -> habilidade -> luta dura -> elite -> descanso -> antecâmara -> chefe.
		# Encontros especiais (ExpeditionEncounters) em 4 das 7 lutas — emboscada (3), defesa das oferendas (7),
		# ritual corrompido (9) e caçada ao elite (10); Encruzilhada, Guardião e o chefe são lutas tradicionais.
		# "level": [mín, máx] dos monstros que nascem na sala (ExpeditionBalance; vale sobre o nível da cena)
		"rooms": {
			"Entrada": {"kind": "start", "next": ["Encruzilhada"]},
			# 1. primeira luta: duas ondas curtas; a segunda já mostra o slime explosivo
			"Encruzilhada": {"kind": "combat", "reward": true, "level": [2, 3], "next": ["Altar da Deusa"],
				"waves": [
					[{"kind": "slime_veloz", "count": 2}],
					[{"kind": "slime_veloz", "count": 2}, {"kind": "slime_explosivo", "count": 1}],
				]},
			# 2. a primeira habilidade da run (o altar que ficava na Encruzilhada)
			"Altar da Deusa": {"kind": "altar", "next": ["Raízes Corrompidas"], "altar": {"at": [-3.5, 1.0]}},
			# 3. EMBOSCADA: a sala parece vazia; no meio dela as sanguessugas brotam em roda do jogador e, depois, o
			# arqueiro e mais sanguessugas fecham a boca por onde ele entrou. Sem bênção (o ritmo respira até o evento)
			"Raízes Corrompidas": {"kind": "combat", "level": [3, 3], "next": ["Santuário Abandonado"],
				"encounter": {"type": "ambush", "trigger": 6.0, "ring": 6.0, "telegraph": 1.6, "daze": 1.0,
					"spawn": ["ring", "behind"]},
				"waves": [
					[{"kind": "sanguessuga_lodo", "count": 2}, {"kind": "slime_veloz", "count": 1}],
					[{"kind": "brejeiro_arqueiro", "count": 1}, {"kind": "sanguessuga_lodo", "count": 2}],
				]},
			# 4. evento: a oferenda de sangue na estátua caída da Deusa (ExpeditionEvents "santuario")
			"Santuário Abandonado": {"kind": "event", "next": ["Guardião das Raízes"], "event": "santuario",
				"shrine": {"at": [0.0, -2.5]}},
			# 5. primeira elite: o Guardião (brejeiro de elite) faz brotar duas flores-famintas quando perde metade da vida
			"Guardião das Raízes": {"kind": "elite", "reward": true, "level": [3, 4], "next": ["Câmara das Oferendas"],
				"leader": {"name": "Guardião das Raízes", "call_at": 0.5,
					"call": [{"kind": "flor_faminta", "count": 2}]},
				"waves": [
					[{"kind": "sanguessuga_lodo", "count": 2}, {"kind": "slime_veloz", "count": 2}],
					[{"kind": "brejeiro", "count": 1, "elite": true, "leader": true},
						{"kind": "brejeiro_arqueiro", "count": 1}],
				]},
			# 6. recompensa: o baú das oferendas dá uma bênção (sem luta)
			"Câmara das Oferendas": {"kind": "reward", "reward": true, "next": ["Clareira Funda"],
				"shrine": {"at": [0.0, -2.0]}},
			# 7. DEFESA DAS OFERENDAS, a luta longa: três ondas que sobem (explosivos; os xamãs que atacam de longe; os
			# dois juntos) nascem em volta do baú das oferendas, lacrado até o último guardião cair. Vencer em até
			# 90 s mantém as oferendas intactas: a bênção do baú soma um acúmulo a mais
			"Clareira Funda": {"kind": "combat", "reward": true, "level": [3, 4], "next": ["Altar Ancestral"],
				"encounter": {"type": "offering", "bonus_time": 90.0, "bonus_stacks": 1, "guard": 3.0},
				"shrine": {"at": [-6.0, 0.0]},
				"waves": [
					[{"kind": "slime_explosivo", "count": 2}, {"kind": "slime_veloz", "count": 1}],
					[{"kind": "goblin_xama", "count": 2}, {"kind": "slime_veloz", "count": 1}],
					[{"kind": "slime_explosivo", "count": 2}, {"kind": "goblin_xama", "count": 2}],
				]},
			# 8. evolução da build: habilidade nova, melhoria de uma habilidade já levada ou bênção de run (1 de 3);
			# sem nada para oferecer, uma bênção comum
			"Altar Ancestral": {"kind": "altar", "reward": true, "next": ["Pântano Corrompido"],
				"altar": {"at": [-3.5, 0.0], "mode": "evolve"}},
			# 9. RITUAL CORROMPIDO, a luta mais dura antes da última elite: mosquitos, sanguessugas, o xamã e os
			# arqueiros enquanto o Foco da Corrupção marca o chão sob o jogador e chama mosquitos. Quebrar o foco
			# interrompe o ritual (as ondas que ainda não vieram não vêm); a sala só abre com o foco quebrado
			"Pântano Corrompido": {"kind": "combat", "level": [4, 5], "next": ["Arauto do Pântano"],
				"encounter": {"type": "ritual", "pulse": 6.5, "pulse_radius": 2.4, "pulse_warn": 1.4, "pulse_dmg": 0.1,
					"focus": {"kind": "foco_corrupcao", "at": [6.0, 3.5], "name": "Foco da Corrupção"},
					"summon": [{"kind": "pernilongo_brejo", "count": 1}], "summon_every": 2, "summon_cap": 2},
				"waves": [
					[{"kind": "pernilongo_brejo", "count": 3}, {"kind": "slime_veloz", "count": 1}],
					[{"kind": "sanguessuga_lodo", "count": 2}, {"kind": "brejeiro_xama", "count": 1}],
					[{"kind": "brejeiro_arqueiro", "count": 2}, {"kind": "pernilongo_brejo", "count": 2},
						{"kind": "slime_explosivo", "count": 1}],
				]},
			# 10. CAÇADA AO ELITE: o Arauto (xamã de elite) já chega com o bando; enquanto ele vive o bando que cai se
			# reagrupa (2 vezes), na metade da vida ele chama mosquitos e um slime explosivo, e ele caindo o bando que
			# sobrou se dispersa
			"Arauto do Pântano": {"kind": "elite", "reward": true, "level": [4, 5], "next": ["Refúgio das Raízes"],
				"leader": {"name": "Arauto do Pântano", "call_at": 0.5,
					"call": [{"kind": "pernilongo_brejo", "count": 2}, {"kind": "slime_explosivo", "count": 1}]},
				"encounter": {"type": "hunt", "regroups": 2, "regroup_delay": 1.4, "daze": 0.6,
					"regroup": [{"kind": "sanguessuga_lodo", "count": 1}, {"kind": "brejeiro_arqueiro", "count": 1}]},
				"waves": [
					[{"kind": "brejeiro_xama", "count": 1, "elite": true, "leader": true},
						{"kind": "sanguessuga_lodo", "count": 2}, {"kind": "goblin_xama", "count": 1}],
				]},
			# 11. descanso: a fonte das raízes cura metade da vida, uma vez
			"Refúgio das Raízes": {"kind": "rest", "next": ["Antecâmara"], "shrine": {"at": [0.0, -2.0], "heal": 0.5}},
			# 12. salão de pedra na frente do portão do chefe (sem luta)
			"Antecâmara": {"kind": "rest", "next": ["Trono da Rainha"]},
			# 13. a Espinheira
			"Trono da Rainha": {"kind": "boss", "level": [5, 5], "next": []},
		},
		# Balanceamento só desta expedição (ExpeditionBalance): multiplica a vida e o dano que o monstro já tem
		# pelas regras de sempre (curva de nível + categoria do progression.json) no nível da sala.
		#   common — monstros das salas; elite — o líder da sala de elite (por cima do bônus de elite do MMO);
		#   minion — o que nasce durante a luta (brotos, lacaios, reforços do líder); boss — o chefe
		"balance": {
			"common": {"hp": 0.8, "dmg": 0.75},
			"elite": {"hp": 1.0, "dmg": 0.6},
			"minion": {"hp": 0.5, "dmg": 0.75},
			"boss": {"hp": 0.5, "dmg": 0.2},
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


## Nome da (primeira) sala de chefe ("" = nenhuma).
static func boss_room(def: Dictionary) -> String:
	for r in rooms(def):
		if kind_of(def, r) == "boss":
			return str(r)
	return ""


## Salas que precisam ser limpas (as que contam no progresso).
static func clear_rooms(def: Dictionary) -> Array:
	return rooms(def).keys().filter(func(r: String) -> bool: return needs_clear(def, r))


## A sala dá uma melhoria temporária (sala com "reward": true de um tipo de REWARD_KINDS).
static func grants_reward(def: Dictionary, room: String) -> bool:
	return bool(rooms(def).get(room, {}).get("reward", false)) and kind_of(def, room) in REWARD_KINDS


## A bênção da sala sai sozinha quando ela é limpa (sala de luta); as outras saem pelo santuário/altar (e a da
## Defesa das Oferendas pelo baú, depois de a sala ser limpa).
static func reward_on_clear(def: Dictionary, room: String) -> bool:
	return grants_reward(def, room) and needs_clear(def, room) \
		and not ExpeditionEncounters.is_type(def, room, ExpeditionEncounters.OFFERING)


## Acúmulos que a bênção escolhida na sala soma ("reward_stacks"; padrão 2 na elite, 1 nas outras).
static func reward_stacks(def: Dictionary, room: String) -> int:
	var d := 2 if kind_of(def, room) == "elite" else 1
	return maxi(1, int(rooms(def).get(room, {}).get("reward_stacks", d)))


## Salas que dão melhoria.
static func reward_rooms(def: Dictionary) -> Array:
	return rooms(def).keys().filter(func(r: String) -> bool: return grants_reward(def, r))


# ================================================================ altares (kit temporário de habilidades)
## A sala tem Altar da Deusa.
static func has_altar(def: Dictionary, room: String) -> bool:
	return rooms(def).get(room, {}).get("altar") is Dictionary and kind_of(def, room) in ALTAR_KINDS


## Lugar do altar em metros a partir do centro da sala (x, z); Vector2.ZERO se a sala não tem altar.
static func altar_offset(def: Dictionary, room: String) -> Vector2:
	if not has_altar(def, room):
		return Vector2.ZERO
	return _offset(rooms(def)[room].altar)


## Salas com altar.
static func altar_rooms(def: Dictionary) -> Array:
	return rooms(def).keys().filter(func(r: String) -> bool: return has_altar(def, r))


## Modo do altar da sala: ALTAR_SKILL (só habilidade nova) ou ALTAR_EVOLVE (evolução da build); "" sem altar.
static func altar_mode(def: Dictionary, room: String) -> String:
	if not has_altar(def, room):
		return ""
	return str(rooms(def)[room].altar.get("mode", ALTAR_SKILL))


## O altar da sala só desperta depois de a sala ser limpa (sala de luta).
static func altar_needs_clear(def: Dictionary, room: String) -> bool:
	return has_altar(def, room) and needs_clear(def, room)


static func _offset(d: Dictionary) -> Vector2:
	var at = d.get("at", [0.0, 0.0])
	if at is Array and (at as Array).size() == 2:
		return Vector2(float(at[0]), float(at[1]))
	return Vector2.ZERO


# ================================================================ santuários (evento, recompensa, descanso)
## A sala tem santuário (o tipo é o da sala: event, reward ou rest; o baú da Defesa das Oferendas é "reward").
static func has_shrine(def: Dictionary, room: String) -> bool:
	return rooms(def).get(room, {}).get("shrine") is Dictionary and shrine_kind(def, room) != ""


## Tipo do santuário da sala: o tipo da sala (event, reward, rest), "reward" no baú da Defesa das Oferendas e ""
## se a sala não pode ter santuário.
static func shrine_kind(def: Dictionary, room: String) -> String:
	var k := kind_of(def, room)
	if k in SHRINE_KINDS:
		return k
	if ExpeditionEncounters.is_type(def, room, ExpeditionEncounters.OFFERING):
		return "reward"
	return ""


## O santuário da sala só acende depois de a luta dela acabar (o baú lacrado da Defesa das Oferendas).
static func shrine_needs_clear(def: Dictionary, room: String) -> bool:
	return has_shrine(def, room) and needs_clear(def, room)


static func shrine_offset(def: Dictionary, room: String) -> Vector2:
	if not has_shrine(def, room):
		return Vector2.ZERO
	return _offset(rooms(def)[room].shrine)


static func shrine_rooms(def: Dictionary) -> Array:
	return rooms(def).keys().filter(func(r: String) -> bool: return has_shrine(def, r))


## Evento da sala (id do ExpeditionEvents; "" = nenhum).
static func event_of(def: Dictionary, room: String) -> String:
	if kind_of(def, room) != "event":
		return ""
	return str(rooms(def).get(room, {}).get("event", ""))


## Fração da vida máxima que o descanso da sala cura (0 = a sala não cura).
static func heal_of(def: Dictionary, room: String) -> float:
	if not has_shrine(def, room) or kind_of(def, room) != "rest":
		return 0.0
	return clampf(float(rooms(def)[room].shrine.get("heal", 0.0)), 0.0, 1.0)


# ================================================================ elites
## Líder da sala de elite ({} = nenhum): {"name", "call", "call_at"}.
static func leader_of(def: Dictionary, room: String) -> Dictionary:
	var l = rooms(def).get(room, {}).get("leader")
	return l if l is Dictionary and kind_of(def, room) == "elite" else {}


# ================================================================ encontros (ondas)
## Ondas configuradas na sala ([] = sem "waves": a sala usa os pontos de monstro da cena como onda única).
static func waves_of(def: Dictionary, room: String) -> Array:
	var w = rooms(def).get(room, {}).get("waves", [])
	return w if w is Array else []


## Se a sala nasce por ondas do ExpeditionDefs (e não pelos pontos de monstro da cena).
static func has_waves(def: Dictionary, room: String) -> bool:
	return not waves_of(def, room).is_empty()


## Quantas ondas a luta da sala tem (0 = sala sem luta; sem "waves" = 1, a dos pontos da cena).
static func wave_count(def: Dictionary, room: String) -> int:
	if not needs_clear(def, room):
		return 0
	return maxi(1, waves_of(def, room).size())


## Grupos da onda `index` (0 = a primeira): [{"kind", "count", "elite"?}]; [] fora da faixa.
static func wave_groups(def: Dictionary, room: String, index: int) -> Array:
	var w := waves_of(def, room)
	if index < 0 or index >= w.size() or not (w[index] is Array):
		return []
	return w[index]


## Monstros na onda `index` (solo; no coop o DungeonRules.population aumenta cada grupo).
static func wave_size(def: Dictionary, room: String, index: int) -> int:
	var n := 0
	for g in wave_groups(def, room, index):
		n += int(g.get("count", 0)) if g is Dictionary else 0
	return n


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


## Rota da chegada ao fim seguindo sempre o primeiro `next` (as etapas, em ordem, de uma rota linear).
static func route(def: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var r := str(def.get("start", ""))
	while rooms(def).has(r) and not out.has(r):
		out.append(r)
		var n := next_of(def, r)
		r = str(n[0]) if not n.is_empty() else ""
	return out


## Confere uma lista de grupos de monstros ({"kind", "count"}); usada também pelo ExpeditionEncounters.
static func check_groups(groups, r: String, what: String, out: PackedStringArray) -> void:
	_check_groups(groups, r, what, out)


static func _check_groups(groups, r: String, what: String, out: PackedStringArray) -> void:
	if not (groups is Array) or (groups as Array).is_empty():
		out.append("sala '%s': %s vazia" % [r, what])
		return
	for g in groups:
		if not (g is Dictionary) or str(g.get("kind", "")) == "" or int(g.get("count", 0)) < 1:
			out.append("sala '%s': %s com grupo inválido %s" % [r, what, str(g)])


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
		if k == "reward" and not bool(rs[r].get("reward", false)):
			out.append("sala de recompensa '%s' sem \"reward\": true" % r)
		var altar = rs[r].get("altar")
		if altar != null:
			if not (altar is Dictionary):
				out.append("sala '%s': altar precisa ser {\"at\": [x, z]}" % r)
			elif not k in ALTAR_KINDS:
				out.append("sala '%s' do tipo '%s' não pode ter altar" % [r, k])
			elif not str(altar.get("mode", ALTAR_SKILL)) in ALTAR_MODES:
				out.append("sala '%s': modo de altar '%s' desconhecido" % [r, str(altar.mode)])
		if k == "altar" and not (altar is Dictionary):
			out.append("sala de altar '%s' sem altar" % r)
		var shrine = rs[r].get("shrine")
		if shrine != null:
			if not (shrine is Dictionary):
				out.append("sala '%s': santuário precisa ser {\"at\": [x, z]}" % r)
			elif shrine_kind(def, r) == "":
				out.append("sala '%s' do tipo '%s' não pode ter santuário" % [r, k])
		if k in ["event", "reward"] and not (shrine is Dictionary):
			out.append("sala '%s' do tipo '%s' sem santuário" % [r, k])
		if k == "event" and str(rs[r].get("event", "")) == "":
			out.append("sala de evento '%s' sem \"event\"" % r)
		var waves = rs[r].get("waves")
		if waves != null:
			if not (waves is Array) or (waves as Array).is_empty():
				out.append("sala '%s': waves precisa ser uma lista de ondas" % r)
			elif not k in WAVE_KINDS:
				out.append("sala '%s' do tipo '%s' não tem ondas (só combat/elite)" % [r, k])
			else:
				for i in (waves as Array).size():
					_check_groups(waves[i], r, "onda %d" % (i + 1), out)
		var leader = rs[r].get("leader")
		if leader != null:
			if k != "elite" or not (leader is Dictionary):
				out.append("sala '%s': só sala de elite tem líder {\"name\", \"call\"}" % r)
			else:
				if str(leader.get("name", "")) == "":
					out.append("sala '%s': líder sem nome" % r)
				if leader.has("call"):
					_check_groups(leader.call, r, "chamado do líder", out)
		if k == "elite":
			var leaders := 0
			for wave in (waves if waves is Array else []):
				for g in (wave if wave is Array else []):
					if g is Dictionary and bool(g.get("leader", false)):
						leaders += int(g.get("count", 0))
			if leaders != 1:
				out.append("sala de elite '%s' precisa de exatamente um líder nas ondas (%d)" % [r, leaders])
		ExpeditionEncounters.check_room(def, r, out)
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
