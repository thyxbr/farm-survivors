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
## Espaço para o futuro sem mexer no resto: `players` (coop: quantos estão na run; o modo usa no
## DungeonRules.population) e `run_seed` (sorteios da run).
##
## Recompensas (melhorias temporárias, ExpeditionUpgrades): limpar uma sala com "reward" deixa uma escolha
## pendente (offer_reward, com as opções já sorteadas); enquanto ela está pendente a run não deixa ir a outra sala.
## choose_reward grava a melhoria em `modifiers` ({id: acúmulos}) e marca a sala em `rewards`: cada sala dá no
## máximo uma recompensa, por mais que a escolha seja reaberta. O fim da run descarta a escolha pendente.

signal phase_changed(phase: String)
signal room_entered(room: String)
signal room_cleared(room: String)
signal reward_offered(room: String, choices: Array)
signal reward_chosen(room: String, upgrade: String)

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
## Melhorias temporárias escolhidas nesta run: id (ExpeditionUpgrades) -> acúmulos.
var modifiers := {}
## Salas que já deram recompensa: sala -> melhoria escolhida ("" = não havia nada para oferecer).
var rewards := {}
## Escolha em aberto: {"room": sala, "choices": [ids]}; vazio = nenhuma.
var pending_reward := {}


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
	if has_pending_reward():
		return room == current_room   # escolha a melhoria antes de seguir
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


# ================================================================ recompensas (melhorias temporárias)
## Há uma melhoria esperando ser escolhida.
func has_pending_reward() -> bool:
	return not pending_reward.is_empty()


## A sala `room` já deu (ou está dando) a recompensa dela.
func is_rewarded(room: String) -> bool:
	return rewards.has(room) or str(pending_reward.get("room", "")) == room


## `room` pode oferecer a recompensa agora: run ativa, sala de recompensa já limpa, ainda não recompensada e
## nenhuma outra escolha em aberto.
func can_offer_reward(room: String) -> bool:
	return is_active() and cleared.has(room) and ExpeditionDefs.grants_reward(def, room) \
		and not is_rewarded(room) and not has_pending_reward()


## Salas limpas que dão recompensa e ainda não deram (na ordem em que foram visitadas).
func rooms_awaiting_reward() -> Array[String]:
	var out: Array[String] = []
	for r in visited:
		if cleared.has(r) and ExpeditionDefs.grants_reward(def, r) and not is_rewarded(r):
			out.append(r)
	return out


## Abre a escolha da sala `room` com as opções `choices` (ids de ExpeditionUpgrades, já sorteados). Sem opção
## válida a sala conta como recompensada sem nada (ninguém fica preso). false se a sala não pode oferecer.
func offer_reward(room: String, choices: Array) -> bool:
	if not can_offer_reward(room):
		return false
	var valid: Array[String] = []
	for c in choices:
		if ExpeditionUpgrades.can_take(str(c), modifiers) and not valid.has(str(c)):
			valid.append(str(c))
	if valid.is_empty():
		rewards[room] = ""
		return false
	pending_reward = {"room": room, "choices": valid}
	reward_offered.emit(room, valid)
	return true


## O jogador escolheu `upgrade` entre as opções pendentes. false (e nada muda) se não há escolha em aberto, a
## run acabou ou a melhoria não estava entre as opções.
func choose_reward(upgrade: String) -> bool:
	if not is_active() or not has_pending_reward() or not (pending_reward.choices as Array).has(upgrade):
		return false
	var room := str(pending_reward.room)
	pending_reward = {}
	rewards[room] = upgrade
	modifiers[upgrade] = int(modifiers.get(upgrade, 0)) + 1
	reward_chosen.emit(room, upgrade)
	return true


## Encerra com `result` (VICTORY, DEFEAT ou ABANDON). false se não estava em andamento.
func finish(result: String) -> bool:
	if not is_active() or not result in [VICTORY, DEFEAT, ABANDON]:
		return false
	pending_reward = {}   # a escolha que ficou aberta morre com a run
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
		"rooms_visited": visited.size(), "progress": progress(), "elapsed": elapsed,
		"modifiers": modifiers.duplicate(), "rewards": rewards.size()}


func _set_phase(p: String) -> void:
	phase = p
	phase_changed.emit(p)
