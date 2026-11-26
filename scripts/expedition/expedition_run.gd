class_name ExpeditionRun
extends RefCounted
## Estado de UMA expedição (puro: sem cena, sem rede, sem autoload). Quem monta o mapa e cria os monstros é o
## modo da expedição (scripts/expedition/expedition_mode.gd); ele só avisa aqui o que aconteceu (entrou numa sala,
## limpou uma sala, morreu, saiu) e lê daqui a fase, a sala atual e o progresso.
##
## Fases:  idle ──start()──▶ active ──finish()──▶ ended ──mark_returned()──▶ returned
## Resultado (outcome, só a partir de ended): "victory" (limpou a sala de chefe), "defeat" (caiu) ou "abandon"
## (voltou à Guilda antes do fim).
##
## Espaço para o futuro sem mexer no resto: `modifiers` (bônus/maldições temporários da run), `players` (coop:
## quantos estão na run; o modo usa no DungeonRules.population) e `run_seed` (sorteios da run).

signal phase_changed(phase: String)
signal room_entered(room: String)
signal room_cleared(room: String)

const IDLE := "idle"
const ACTIVE := "active"
const ENDED := "ended"
const RETURNED := "returned"
const VICTORY := "victory"
const DEFEAT := "defeat"
const ABANDON := "abandon"

var expedition_id := ""
var def: Dictionary = {}
var phase := IDLE
var outcome := ""
var current_room := ""
## Salas visitadas, na ordem da primeira visita.
var visited: Array[String] = []
## Salas limpas: nome -> true.
var cleared := {}
## Segundos de expedição (só conta na fase active).
var elapsed := 0.0
var players := 1
var run_seed := 0
var modifiers := {}


## Nova run para a expedição `id` (null se a expedição não existe ou a definição está quebrada).
static func create(id: String) -> ExpeditionRun:
	var d := ExpeditionDefs.get_def(id)
	if d.is_empty() or not ExpeditionDefs.validate(d).is_empty():
		return null
	var r := ExpeditionRun.new()
	r.expedition_id = id
	r.def = d
	return r


func is_active() -> bool:
	return phase == ACTIVE


## Acabou (vitória, derrota ou abandono), voltando ou já de volta à Guilda.
func is_over() -> bool:
	return phase == ENDED or phase == RETURNED


## Começa na sala de chegada. false se já tinha começado.
func start() -> bool:
	if phase != IDLE:
		return false
	_set_phase(ACTIVE)
	enter_room(str(def.start))
	return true


## Pode entrar em `room` agora? A sala atual, uma já visitada (voltar) ou uma que a atual abre (`next`).
func can_enter(room: String) -> bool:
	if not is_active() or not ExpeditionDefs.rooms(def).has(room):
		return false
	if current_room == "":
		return room == str(def.start)
	return room == current_room or visited.has(room) or ExpeditionDefs.next_of(def, current_room).has(room)


## O jogador chegou em `room`. false (e nada muda) se a sala não está ao alcance pelo grafo.
func enter_room(room: String) -> bool:
	if not can_enter(room):
		return false
	if room == current_room:
		return true
	current_room = room
	if not visited.has(room):
		visited.append(room)
	room_entered.emit(room)
	return true


## Todos os monstros de `room` caíram. Limpar a sala de chefe conclui a expedição com vitória. Só vale para sala
## visitada; false se não mudou nada (já limpa, fora da run ou sala nunca visitada).
func clear_room(room: String) -> bool:
	if not is_active() or not visited.has(room) or cleared.has(room):
		return false
	cleared[room] = true
	room_cleared.emit(room)
	if ExpeditionDefs.kind_of(def, room) == "boss":
		finish(VICTORY)
	return true


func is_cleared(room: String) -> bool:
	return cleared.has(room)


## Fração das salas de luta já limpas (0..1).
func progress() -> float:
	var need := ExpeditionDefs.clear_rooms(def)
	if need.is_empty():
		return 1.0
	var n := 0
	for r in need:
		if cleared.has(r):
			n += 1
	return float(n) / need.size()


## Encerra com `result` (VICTORY, DEFEAT ou ABANDON). false se não estava em andamento.
func finish(result: String) -> bool:
	if not is_active() or not result in [VICTORY, DEFEAT, ABANDON]:
		return false
	outcome = result
	_set_phase(ENDED)
	return true


func fail() -> bool:
	return finish(DEFEAT)


func abandon() -> bool:
	return finish(ABANDON)


## O jogador chegou de volta à Guilda. false se a run ainda não tinha acabado.
func mark_returned() -> bool:
	if phase != ENDED:
		return false
	_set_phase(RETURNED)
	return true


func tick(delta: float) -> void:
	if is_active():
		elapsed += delta


## Resumo para a tela/aviso do fim e, no futuro, para as recompensas permanentes.
func summary() -> Dictionary:
	return {"expedition": expedition_id, "phase": phase, "outcome": outcome, "room": current_room,
		"rooms_cleared": cleared.size(), "rooms_to_clear": ExpeditionDefs.clear_rooms(def).size(),
		"rooms_visited": visited.size(), "progress": progress(), "elapsed": elapsed}


func _set_phase(p: String) -> void:
	phase = p
	phase_changed.emit(p)
