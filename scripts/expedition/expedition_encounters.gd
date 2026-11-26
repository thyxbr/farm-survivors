class_name ExpeditionEncounters
extends RefCounted
## Encontros especiais das salas de luta da expedição (puro: só lê o ExpeditionDefs; sem cena, sem autoload).
##
## Não é um segundo sistema de combate: o encontro especial é uma sala de luta comum (ondas do ExpeditionDefs,
## barreiras, ExpeditionRun.start_encounter/advance_wave/clear_room) com um "encounter" que muda COMO a luta
## começa, ONDE os monstros nascem e O QUE libera a sala. Quem executa é o expedition_mode; o estado que precisa
## sobreviver (o que já aconteceu na sala) fica no ExpeditionRun.encounters, para nada se repetir ao voltar à sala.
##
## Tipos ("encounter": {"type": ...} na sala do ExpeditionDefs):
##   ambush   — EMBOSCADA (sala combat): a sala parece vazia e só tranca quando o jogador avança `trigger` m desde
##              onde entrou. Cada onda tem um jeito de nascer ("spawn": lista por onda): "ring" = em roda do jogador,
##              a `ring` m dele; "behind" = na boca por onde ele entrou (corta a volta). Aviso no chão mais longo
##              (`telegraph` s) e quem brota fica atordoado `daze` s: a surpresa nunca dá dano sem chance de reagir.
##   hunt     — CAÇADA AO ELITE (sala elite): o líder de elite já vem na primeira onda com o bando dele. Enquanto o
##              líder vive, o bando que cai se reagrupa (`regroup`: grupos, até `regroups` vezes). O líder caindo
##              dispersa o bando que sobrou e a sala é liberada.
##   ritual   — RITUAL CORROMPIDO (sala combat): um foco de corrupção (`focus`: monstro parado do enemies.json, em
##              `at` metros do centro) nasce com a luta. A cada `pulse` s ele marca o chão onde o jogador está
##              (`pulse_radius` m, `pulse_warn` s de aviso) e quem ficar leva `pulse_dmg` da vida máxima; a cada
##              `summon_every` pulsos chama `summon` (até `summon_cap` vivos). Destruir o foco interrompe o ritual:
##              os pulsos e os chamados param, os chamados se desfazem e as ondas que ainda não vieram não vêm mais.
##              A sala só é liberada com o foco destruído.
##   offering — DEFESA DAS OFERENDAS (sala combat com "reward": true e "shrine"): o baú das oferendas fica lacrado
##              enquanto os guardiões estão de pé (as ondas nascem em volta dele, "guard"). Limpa a sala, o baú abre a
##              bênção da sala (uma vez só, como a Câmara das Oferendas). Vencer em até `bonus_time` s desde que a
##              sala trancou mantém as oferendas intactas: a bênção soma `bonus_stacks` acúmulo(s) a mais.

const AMBUSH := "ambush"
const HUNT := "hunt"
const RITUAL := "ritual"
const OFFERING := "offering"
const TYPES := [AMBUSH, HUNT, RITUAL, OFFERING]
## Tipo de sala em que cada encontro pode estar.
const ROOM_KIND := {AMBUSH: "combat", HUNT: "elite", RITUAL: "combat", OFFERING: "combat"}
## Jeitos de uma onda nascer ("" = o de sempre: espalhada pela sala, longe do jogador).
const SPAWNS := ["", "ring", "behind", "guard"]

## Nome do encontro (letreiro e aviso da primeira visita).
const NAMES := {AMBUSH: "Emboscada", HUNT: "Caçada ao Elite", RITUAL: "Ritual Corrompido",
	OFFERING: "Defesa das Oferendas"}

## Valores padrão de cada tipo (a sala pode trocar qualquer um).
const DEFAULTS := {
	AMBUSH: {"trigger": 5.0, "ring": 6.0, "telegraph": 1.6, "daze": 1.0, "spawn": ["ring", "behind"]},
	HUNT: {"regroup": [], "regroups": 2, "regroup_delay": 1.4, "daze": 0.6},
	RITUAL: {"focus": {}, "pulse": 6.0, "pulse_radius": 2.4, "pulse_warn": 1.4, "pulse_dmg": 0.1,
		"summon": [], "summon_every": 2, "summon_cap": 3, "daze": 0.6},
	OFFERING: {"bonus_time": 90.0, "bonus_stacks": 1, "guard": 4.0},
}
## Teto do dano do pulso do ritual (fração da vida máxima): nunca é um golpe que mata de uma vez.
const MAX_PULSE_DMG := 0.25
## Ninguém da emboscada nasce a menos disso do jogador (m), por mais apertada que seja a sala.
const MIN_RING := 5.0


## Encontro especial da sala ({} = sala comum).
static func of(def: Dictionary, room: String) -> Dictionary:
	var e = ExpeditionDefs.rooms(def).get(room, {}).get("encounter")
	return e if e is Dictionary else {}


## Tipo do encontro da sala ("" = sala comum).
static func type_of(def: Dictionary, room: String) -> String:
	var t := str(of(def, room).get("type", ""))
	return t if t in TYPES else ""


static func is_type(def: Dictionary, room: String, t: String) -> bool:
	return type_of(def, room) == t


## Salas com encontro especial, na ordem da rota.
static func rooms(def: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for r in ExpeditionDefs.route(def):
		if type_of(def, r) != "":
			out.append(r)
	return out


static func display_name(t: String) -> String:
	return str(NAMES.get(t, ""))


## Valor `key` do encontro da sala (o da sala, senão o padrão do tipo; `fallback` se nenhum).
static func param(def: Dictionary, room: String, key: String, fallback = null):
	var e := of(def, room)
	if e.has(key):
		return e[key]
	return DEFAULTS.get(type_of(def, room), {}).get(key, fallback)


static func num(def: Dictionary, room: String, key: String, fallback := 0.0) -> float:
	return float(param(def, room, key, fallback))


## Jeito de nascer da onda `index` (0 = a primeira): "ring"/"behind" na emboscada, "guard" na defesa das oferendas,
## "" nas outras.
static func spawn_of(def: Dictionary, room: String, index: int) -> String:
	match type_of(def, room):
		AMBUSH:
			var s = param(def, room, "spawn", [])
			if s is Array and not (s as Array).is_empty():
				return str(s[clampi(index, 0, s.size() - 1)])
			return "ring"
		OFFERING:
			return "guard"
	return ""


## Segundos de aviso no chão antes da onda nascer (a emboscada avisa mais tempo; `default` nas outras).
static func telegraph_of(def: Dictionary, room: String, default: float) -> float:
	if is_type(def, room, AMBUSH):
		return maxf(default, num(def, room, "telegraph", default))
	return default


## Segundos de atordoamento de quem nasce na onda (emboscada) ou no meio da luta (reagrupar, chamado do ritual).
static func daze_of(def: Dictionary, room: String) -> float:
	return maxf(0.0, num(def, room, "daze", 0.0))


## A emboscada dispara: o jogador já andou `trigger` m desde onde entrou na sala.
static func ambush_triggered(def: Dictionary, room: String, walked: float) -> bool:
	return is_type(def, room, AMBUSH) and walked >= num(def, room, "trigger", 5.0)


## `n` pontos em roda de `center` (x, z), a `radius` m, começando no ângulo `start` (radianos).
static func ring_points(center: Vector2, n: int, radius: float, start := 0.0) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in maxi(n, 0):
		var a := start + TAU * float(i) / float(maxi(n, 1))
		out.append(center + Vector2(cos(a), sin(a)) * radius)
	return out


## Raio da roda da emboscada (nunca a menos de MIN_RING m do jogador).
static func ring_radius(def: Dictionary, room: String) -> float:
	return maxf(MIN_RING, num(def, room, "ring", 6.0))


## Dano de um pulso do ritual em quem está na marca: fração da vida máxima (com teto).
static func pulse_damage(def: Dictionary, room: String, max_hp: float) -> float:
	return maxf(1.0, max_hp * clampf(num(def, room, "pulse_dmg", 0.1), 0.0, MAX_PULSE_DMG))


## O pulso de número `n` (1 = o primeiro) chama os lacaios do ritual.
static func pulse_summons(def: Dictionary, room: String, n: int) -> bool:
	var every := int(param(def, room, "summon_every", 2))
	return is_type(def, room, RITUAL) and every > 0 and n > 0 and n % every == 0 \
		and not (param(def, room, "summon", []) as Array).is_empty()


## Monstro do foco do ritual ("" = sem foco) e onde ele fica (metros a partir do centro da sala).
static func focus_kind(def: Dictionary, room: String) -> String:
	var f = param(def, room, "focus", {})
	return str(f.get("kind", "")) if f is Dictionary else ""


static func focus_offset(def: Dictionary, room: String) -> Vector2:
	var f = param(def, room, "focus", {})
	var at = f.get("at", [0.0, 0.0]) if f is Dictionary else [0.0, 0.0]
	if at is Array and (at as Array).size() == 2:
		return Vector2(float(at[0]), float(at[1]))
	return Vector2.ZERO


static func focus_name(def: Dictionary, room: String) -> String:
	var f = param(def, room, "focus", {})
	return str(f.get("name", "Foco da Corrupção")) if f is Dictionary else "Foco da Corrupção"


## As oferendas continuam intactas se a luta acabou em até `bonus_time` s.
static func offering_intact(def: Dictionary, room: String, secs: float) -> bool:
	return is_type(def, room, OFFERING) and secs <= num(def, room, "bonus_time", 90.0)


## Acúmulos a mais que a bênção da sala soma pelo encontro (oferendas intactas).
static func bonus_stacks(def: Dictionary, room: String, intact: bool) -> int:
	if not intact or not is_type(def, room, OFFERING):
		return 0
	return maxi(0, int(param(def, room, "bonus_stacks", 1)))


## Problemas dos encontros de `room` ([] = ok). Chamado pelo ExpeditionDefs.validate.
static func check_room(def: Dictionary, room: String, out: PackedStringArray) -> void:
	var raw = ExpeditionDefs.rooms(def).get(room, {}).get("encounter")
	if raw == null:
		return
	if not (raw is Dictionary):
		out.append("sala '%s': encounter precisa ser {\"type\": ...}" % room)
		return
	var t := str(raw.get("type", ""))
	if not t in TYPES:
		out.append("sala '%s': encontro '%s' desconhecido" % [room, t])
		return
	var k := ExpeditionDefs.kind_of(def, room)
	if k != str(ROOM_KIND[t]):
		out.append("sala '%s': encontro '%s' só em sala do tipo %s (é %s)" % [room, t, ROOM_KIND[t], k])
	if not ExpeditionDefs.has_waves(def, room):
		out.append("sala '%s': encontro '%s' precisa de ondas" % [room, t])
	match t:
		AMBUSH:
			for s in param(def, room, "spawn", []):
				if not str(s) in ["ring", "behind"]:
					out.append("sala '%s': emboscada com jeito de nascer '%s' desconhecido" % [room, s])
			if num(def, room, "trigger", 0.0) <= 0.0:
				out.append("sala '%s': emboscada sem distância de gatilho" % room)
		HUNT:
			ExpeditionDefs.check_groups(param(def, room, "regroup", []), room, "reagrupamento da caçada", out)
			var first := ExpeditionDefs.wave_groups(def, room, 0)
			if not first.any(func(g) -> bool: return g is Dictionary and bool(g.get("leader", false))):
				out.append("sala '%s': na caçada o líder vem na primeira onda" % room)
		RITUAL:
			if focus_kind(def, room) == "":
				out.append("sala '%s': ritual sem foco" % room)
			if num(def, room, "pulse", 0.0) < 2.0:
				out.append("sala '%s': pulso do ritual rápido demais (mínimo 2 s)" % room)
			if num(def, room, "pulse_warn", 0.0) < 0.8:
				out.append("sala '%s': o aviso do pulso precisa de ao menos 0,8 s" % room)
			if num(def, room, "pulse_dmg", 0.0) > MAX_PULSE_DMG:
				out.append("sala '%s': pulso do ritual acima de %d%% da vida" % [room, roundi(MAX_PULSE_DMG * 100.0)])
			var sm = param(def, room, "summon", [])
			if sm is Array and not (sm as Array).is_empty():
				ExpeditionDefs.check_groups(sm, room, "chamado do ritual", out)
		OFFERING:
			if not ExpeditionDefs.grants_reward(def, room):
				out.append("sala '%s': defesa das oferendas sem \"reward\": true" % room)
			if not (ExpeditionDefs.rooms(def)[room].get("shrine") is Dictionary):
				out.append("sala '%s': defesa das oferendas sem o baú (\"shrine\")" % room)
