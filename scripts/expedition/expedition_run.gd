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
##
## Encontros (ondas): start_encounter tranca a run na sala de luta (`locked_room`: can_enter só aceita ela) e
## começa a onda 1; advance_wave passa para a próxima; clear_room só aceita a sala depois da última onda e
## destranca. Uma sala começa o encontro uma vez só: limpa, nunca mais tranca nem gera onda.
##
## Altares (kit temporário, ExpeditionSkills): a run começa sem habilidade (`skills` vazio: só o ataque básico).
## offer_altar abre a escolha do altar da sala (opções já sorteadas, guardadas por altar em `pending_altar`: fechar
## a tela e voltar mostra as mesmas, sem sortear de novo); choose_skill põe a habilidade em `skills` e gasta o altar
## (`altars_used`): cada altar serve uma vez só. A escolha de altar não prende o jogador na sala. O fim da run
## descarta as escolhas pendentes; `skills` morre com a run (nada é salvo no personagem).
## O Altar Ancestral (ExpeditionDefs "mode": "evolve") mistura nas opções melhorias de habilidade e bênçãos de run
## (ExpeditionSkills.roll_evolution): escolher uma delas soma 1 acúmulo em `modifiers` (como as bênçãos) em vez de
## pôr uma habilidade no kit. A validação é a mesma para os dois altares (altar_option_valid).
##
## Santuários (salas de evento, recompensa e descanso; run_shrine.gd): cada um serve uma vez por run
## (`shrines_used`: sala -> o que foi feito). choose_event aplica a escolha do evento (ExpeditionEvents: a bênção de
## evento vai para `modifiers`; o custo em vida quem cobra é o modo); rest devolve quanto da vida curar. A sala de
## recompensa usa a mesma escolha de bênção das salas de luta (offer_reward), só que pelo santuário. A bênção de
## uma sala de elite soma mais de um acúmulo (ExpeditionDefs.reward_stacks).
##
## Encontros especiais (ExpeditionEncounters; "encounter" na sala): o que já aconteceu em cada um fica em
## `encounters` (sala -> {"t0": segundos de run em que trancou, ...}), para nada se repetir ao voltar à sala:
##   ritual   — break_focus: o foco quebrado interrompe o ritual uma vez só e corta as ondas que ainda não vieram
##              (`wave_cap`); a sala só é limpa com o foco quebrado.
##   hunt     — regroup: cada reagrupamento do bando gasta um dos `regroups` da sala; prey_down marca o líder caído.
##   offering — clear_room guarda se as oferendas ficaram intactas (venceu em até `bonus_time` s); a bênção do baú
##              soma o acúmulo a mais (offer_reward). O baú (santuário da sala) só acende com a sala limpa.
##   ambush   — só o "sprung" (a emboscada já disparou): start_encounter só acontece uma vez por sala.

signal phase_changed(phase: String)
signal room_entered(room: String)
signal room_cleared(room: String)
signal wave_started(room: String, wave: int, total: int)
signal room_locked(room: String)
signal room_unlocked(room: String)
signal reward_offered(room: String, choices: Array)
signal reward_chosen(room: String, upgrade: String)
signal altar_offered(room: String, choices: Array)
signal skill_chosen(room: String, skill: String)
signal altar_upgrade_chosen(room: String, upgrade: String)
signal event_chosen(room: String, option: String)
signal rested(room: String, fraction: float)
signal focus_broken(room: String)
signal pack_regrouped(room: String, left: int)

const IDLE := "idle"
const ACTIVE := "active"
const ENDED := "ended"
const RETURNED := "returned"
const VICTORY := "victory"
const DEFEAT := "defeat"
const ABANDON := "abandon"

var expedition_id := ""
var def: Dictionary = {}
## Classe do personagem (Game.char_class; "" = sem identidade): as bênçãos de classe (ExpeditionClasses) só valem
## para ela. O modo da expedição põe aqui ao montar a run; nada é salvo.
var char_class := ""
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
## Sala trancada pelo encontro em andamento ("" = nenhuma): ninguém sai dela até a última onda cair.
var locked_room := ""
## Onda atual de cada sala que já começou o encontro: sala -> número da onda (1 = a primeira).
var waves := {}
## Habilidades levadas dos altares nesta run (ids de ItemDB.ABILITIES), na ordem em que foram escolhidas: a ordem
## das teclas 1, 2, 3... da barra durante a expedição.
var skills: Array[String] = []
## Altares já usados: sala -> habilidade escolhida.
var altars_used := {}
## Opções já sorteadas de cada altar ainda não usado: sala -> [ids] (o altar mostra sempre as mesmas).
var pending_altar := {}
## Santuários já usados: sala -> o que foi feito (id da opção do evento, "rest").
var shrines_used := {}
## Estado dos encontros especiais que já começaram: sala -> {"t0", "type", "focus", "regroups", "prey", "intact"}.
var encounters := {}
## Teto de ondas de uma sala (o ritual interrompido corta as que não vieram): sala -> última onda.
var wave_cap := {}


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
	if is_locked():
		return room == locked_room    # luta em andamento: as passagens estão fechadas
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
	if waves.has(room) and int(waves[room]) < wave_total(room):
		return false   # ainda há onda por vir
	if encounters.has(room) and ExpeditionEncounters.is_type(def, room, ExpeditionEncounters.RITUAL) \
			and not is_focus_broken(room):
		return false   # o ritual em andamento só acaba com o foco quebrado
	if encounters.has(room) and ExpeditionEncounters.is_type(def, room, ExpeditionEncounters.OFFERING):
		encounters[room]["intact"] = ExpeditionEncounters.offering_intact(def, room, encounter_time(room))
	cleared[room] = true
	if locked_room == room:
		locked_room = ""
		room_unlocked.emit(room)
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


# ================================================================ encontros (ondas e salas trancadas)
## Há uma sala trancada por luta agora.
func is_locked() -> bool:
	return locked_room != ""


## Quantas ondas a luta de `room` tem (0 = sala sem luta). O ritual interrompido corta as que não vieram.
func wave_total(room: String) -> int:
	var n := ExpeditionDefs.wave_count(def, room)
	return mini(n, int(wave_cap[room])) if wave_cap.has(room) else n


## Onda em que `room` está (1 = a primeira; 0 = o encontro ainda não começou ou a sala não tem luta).
func current_wave(room: String) -> int:
	return int(waves.get(room, 0))


## Depois da onda atual ainda vem outra.
func has_next_wave(room: String) -> bool:
	return waves.has(room) and current_wave(room) < wave_total(room)


## `room` pode começar a luta agora: run ativa, é a sala atual, precisa ser limpa, não está limpa e o encontro
## dela nunca começou (sala limpa não volta a ter onda).
func can_start_encounter(room: String) -> bool:
	return is_active() and room == current_room and ExpeditionDefs.needs_clear(def, room) \
		and not cleared.has(room) and not waves.has(room) and not is_locked()


## Tranca a sala atual e começa a onda 1. false se não pode (ver can_start_encounter).
func start_encounter(room: String) -> bool:
	if not can_start_encounter(room):
		return false
	locked_room = room
	waves[room] = 1
	var t := ExpeditionEncounters.type_of(def, room)
	if t != "":
		encounters[room] = {"type": t, "t0": elapsed}
		if t == ExpeditionEncounters.AMBUSH:
			encounters[room]["sprung"] = true
	room_locked.emit(room)
	wave_started.emit(room, 1, wave_total(room))
	return true


## A onda atual de `room` caiu inteira e vem outra: passa para ela. false se não há luta trancada nessa sala ou
## se a atual já era a última (aí quem chama limpa a sala com clear_room).
func advance_wave(room: String) -> bool:
	if not is_active() or locked_room != room or cleared.has(room) or not has_next_wave(room):
		return false
	waves[room] = current_wave(room) + 1
	wave_started.emit(room, current_wave(room), wave_total(room))
	return true


# ================================================================ encontros especiais (ExpeditionEncounters)
## Tipo do encontro especial da sala ("" = luta tradicional).
func encounter_type(room: String) -> String:
	return ExpeditionEncounters.type_of(def, room)


## Segundos desde que a luta especial de `room` trancou (0 se ainda não começou).
func encounter_time(room: String) -> float:
	if not encounters.has(room):
		return 0.0
	return maxf(0.0, elapsed - float(encounters[room].get("t0", elapsed)))


## O foco do ritual de `room` já foi quebrado.
func is_focus_broken(room: String) -> bool:
	return str(encounters.get(room, {}).get("focus", "")) == "broken"


## O foco do ritual de `room` caiu: interrompe o ritual (uma vez só) e corta as ondas que ainda não vieram (a que
## está de pé, ou já anunciada, termina normalmente). false se não há ritual em andamento nessa sala ou se o foco já
## estava quebrado.
func break_focus(room: String) -> bool:
	if not is_active() or not encounters.has(room) or cleared.has(room) or is_focus_broken(room):
		return false
	if not ExpeditionEncounters.is_type(def, room, ExpeditionEncounters.RITUAL):
		return false
	encounters[room]["focus"] = "broken"
	wave_cap[room] = maxi(1, current_wave(room))
	focus_broken.emit(room)
	return true


## Reagrupamentos que o bando da caçada de `room` ainda tem.
func regroups_left(room: String) -> int:
	if not ExpeditionEncounters.is_type(def, room, ExpeditionEncounters.HUNT):
		return 0
	var used := int(encounters.get(room, {}).get("regroups", 0))
	return maxi(0, int(ExpeditionEncounters.param(def, room, "regroups", 0)) - used)


## O bando da caçada de `room` se reagrupa (gasta um reagrupamento). false se a caçada não está em andamento, o
## líder já caiu ou não sobra reagrupamento.
func regroup(room: String) -> bool:
	if not is_active() or locked_room != room or not encounters.has(room) or is_prey_down(room):
		return false
	if regroups_left(room) <= 0:
		return false
	encounters[room]["regroups"] = int(encounters[room].get("regroups", 0)) + 1
	pack_regrouped.emit(room, regroups_left(room))
	return true


func is_prey_down(room: String) -> bool:
	return str(encounters.get(room, {}).get("prey", "")) == "down"


## O líder da caçada de `room` caiu (o bando que sobrou se dispersa). false se já tinha caído ou não é caçada.
func mark_prey_down(room: String) -> bool:
	if not is_active() or not encounters.has(room) or is_prey_down(room):
		return false
	if not ExpeditionEncounters.is_type(def, room, ExpeditionEncounters.HUNT):
		return false
	encounters[room]["prey"] = "down"
	return true


## A Defesa das Oferendas de `room` acabou com as oferendas intactas (só depois de limpa).
func is_offering_intact(room: String) -> bool:
	return bool(encounters.get(room, {}).get("intact", false))


## Acúmulos a mais da bênção da sala pelo encontro (oferendas intactas = +bonus_stacks).
func encounter_bonus_stacks(room: String) -> int:
	return ExpeditionEncounters.bonus_stacks(def, room, is_offering_intact(room))


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
	if not is_active() or not ExpeditionDefs.grants_reward(def, room) or is_rewarded(room) or has_pending_reward():
		return false
	# sala de luta: depois de limpa; sala sem luta (recompensa, altar): depois de visitada
	return cleared.has(room) if ExpeditionDefs.needs_clear(def, room) else visited.has(room)


## Salas de luta limpas que dão recompensa e ainda não deram (na ordem em que foram visitadas). As salas sem luta
## (recompensa, altar) não entram: a bênção delas sai pelo santuário/altar.
func rooms_awaiting_reward() -> Array[String]:
	var out: Array[String] = []
	for r in visited:
		if cleared.has(r) and ExpeditionDefs.reward_on_clear(def, r) and not is_rewarded(r):
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
	pending_reward = {"room": room, "choices": valid,
		"stacks": ExpeditionDefs.reward_stacks(def, room) + encounter_bonus_stacks(room)}
	reward_offered.emit(room, valid)
	return true


## O jogador escolheu `upgrade` entre as opções pendentes. false (e nada muda) se não há escolha em aberto, a
## run acabou ou a melhoria não estava entre as opções.
func choose_reward(upgrade: String) -> bool:
	if not is_active() or not has_pending_reward() or not (pending_reward.choices as Array).has(upgrade):
		return false
	var room := str(pending_reward.room)
	var stacks := int(pending_reward.get("stacks", 1))
	pending_reward = {}
	rewards[room] = upgrade
	add_modifier(upgrade, stacks)
	reward_chosen.emit(room, upgrade)
	return true


## Acúmulos que a escolha pendente soma (1 = normal; 2 = bênção de elite; 0 = nenhuma escolha aberta).
func pending_stacks() -> int:
	return int(pending_reward.get("stacks", 1)) if has_pending_reward() else 0


## Soma `stacks` acúmulos de `upgrade` em `modifiers`, sem passar do máximo (ExpeditionUpgrades.max_stacks).
## Devolve quantos entraram de fato.
func add_modifier(upgrade: String, stacks := 1) -> int:
	if not ExpeditionUpgrades.has(upgrade):
		return 0
	var now := int(modifiers.get(upgrade, 0))
	var n := clampi(stacks, 0, ExpeditionUpgrades.max_stacks(upgrade) - now)
	if n > 0:
		modifiers[upgrade] = now + n
	return n


# ================================================================ santuários (evento, recompensa, descanso)
## O santuário de `room` pode ser usado agora: run ativa, sala com santuário, visitada, nada trancado nem escolha
## em aberto, e ainda não usado (na sala de recompensa: a bênção dela ainda não saiu).
func shrine_ready(room: String) -> bool:
	if not is_active() or not ExpeditionDefs.has_shrine(def, room) or not visited.has(room):
		return false
	if is_locked() or has_pending_reward():
		return false
	if ExpeditionDefs.shrine_needs_clear(def, room) and not cleared.has(room):
		return false   # o baú da Defesa das Oferendas fica lacrado até o último guardião cair
	return not is_shrine_used(room)


## O santuário de `room` já foi usado (no baú de recompensa: a bênção dele já saiu ou está na tela).
func is_shrine_used(room: String) -> bool:
	if ExpeditionDefs.shrine_kind(def, room) == "reward":
		return is_rewarded(room)
	return shrines_used.has(room)


## O jogador escolheu `option` no evento de `room`: a bênção da opção (se houver) entra em `modifiers` e o
## santuário fica gasto. Devolve a opção (ExpeditionEvents) para o modo cobrar o custo; {} se não vale.
func choose_event(room: String, option: String) -> Dictionary:
	if not shrine_ready(room):
		return {}
	var o := ExpeditionEvents.option(ExpeditionDefs.event_of(def, room), option)
	if o.is_empty():
		return {}
	shrines_used[room] = option
	var up := str(o.get("upgrade", ""))
	if up != "":
		add_modifier(up, 1)
	event_chosen.emit(room, option)
	return o


## Descanso em `room`: gasta o santuário e devolve a fração da vida máxima a curar (0 = não pode descansar).
func rest(room: String) -> float:
	var f := ExpeditionDefs.heal_of(def, room)
	if f <= 0.0 or not shrine_ready(room):
		return 0.0
	shrines_used[room] = "rest"
	rested.emit(room, f)
	return f


# ================================================================ altares (kit temporário de habilidades)
## O altar de `room` já foi usado.
func is_altar_used(room: String) -> bool:
	return altars_used.has(room)


## O altar de `room` está desperto: run ativa, sala com altar, já visitada, não usado e (sala de luta) já limpa.
func altar_ready(room: String) -> bool:
	if not is_active() or not ExpeditionDefs.has_altar(def, room) or altars_used.has(room) or not visited.has(room):
		return false
	return not ExpeditionDefs.altar_needs_clear(def, room) or cleared.has(room)


## O altar de `room` já sorteou opções (e elas ainda não foram usadas).
func has_altar_offer(room: String) -> bool:
	return not altar_choices(room).is_empty()


## Abre a escolha do altar de `room` com as opções `choices` (ids já sorteados, ExpeditionSkills.roll). Se o altar
## já tinha opções guardadas (a tela foi fechada sem escolher), ficam as dele e `choices` é ignorado: não há como
## sortear de novo. false se o altar não está desperto ou se não há opção válida.
func offer_altar(room: String, choices: Array) -> bool:
	if not altar_ready(room):
		return false
	if has_altar_offer(room):
		return true
	var valid: Array[String] = []
	for c in choices:
		var id := str(c)
		if altar_option_valid(room, id) and not valid.has(id):
			valid.append(id)
	if valid.is_empty():
		return false
	pending_altar[room] = valid
	altar_offered.emit(room, valid)
	return true


## Opções guardadas do altar de `room` que ainda valem (sem as que o jogador já levou em outro altar); [] = nenhuma.
func altar_choices(room: String) -> Array:
	var out: Array = []
	if not altar_ready(room):
		return out
	for id in pending_altar.get(room, []):
		if altar_option_valid(room, str(id)):
			out.append(id)
	return out


## `id` ainda vale como opção do altar de `room`: habilidade nova que pode sair e ainda não foi levada (com vaga no
## kit); no altar de evolução também melhoria de uma habilidade levada que não chegou ao máximo, ou bênção de run
## (do sorteio) que não chegou ao máximo.
func altar_option_valid(room: String, id: String) -> bool:
	match ExpeditionSkills.option_kind(id):
		"skill":
			return ExpeditionSkills.can_offer(id) and not skills.has(id) and skills.size() < ExpeditionSkills.MAX_SKILLS
		"ability":
			return _evolves(room) and skills.has(ExpeditionUpgrades.ability_of(id)) \
				and ExpeditionUpgrades.can_take(id, modifiers)
		"boon":
			return _evolves(room) and boon_offerable(id) and ExpeditionUpgrades.can_take(id, modifiers)
	return false


## Bênção que pode sair num sorteio desta run: as comuns e as da classe do personagem (com a habilidade que ela pede).
func boon_offerable(id: String) -> bool:
	return ExpeditionUpgrades.in_pool(id) or ExpeditionUpgrades.in_class_pool(id, char_class, skills)


## Contexto do sorteio das bênçãos (ExpeditionUpgrades.roll): a classe e as habilidades levadas.
func roll_context() -> Dictionary:
	return {"class": char_class, "skills": skills.duplicate()}


func _evolves(room: String) -> bool:
	return ExpeditionDefs.altar_mode(def, room) == ExpeditionDefs.ALTAR_EVOLVE


## O jogador escolheu `skill` no altar de `room` e o altar fica gasto: habilidade nova entra no kit da run; melhoria
## de habilidade ou bênção (altar de evolução) soma 1 acúmulo em `modifiers`. false (e nada muda) se o altar não tem
## escolha em aberto, a run acabou ou a opção não estava entre as do altar.
func choose_skill(room: String, skill: String) -> bool:
	if not is_active() or not altar_choices(room).has(skill):
		return false
	pending_altar.erase(room)
	altars_used[room] = skill
	if ExpeditionSkills.option_kind(skill) == "skill":
		skills.append(skill)
		skill_chosen.emit(room, skill)
	else:
		add_modifier(skill, 1)
		altar_upgrade_chosen.emit(room, skill)
	return true


## O altar de `room` não tem mais habilidade para ensinar: fica gasto sem habilidade (o modo oferece a bênção da
## sala no lugar, se ela tiver). false se o altar não estava desperto.
func spend_altar(room: String) -> bool:
	if not altar_ready(room):
		return false
	pending_altar.erase(room)
	altars_used[room] = ""
	return true


## Encerra com `result` (VICTORY, DEFEAT ou ABANDON). false se não estava em andamento.
func finish(result: String) -> bool:
	if not is_active() or not result in [VICTORY, DEFEAT, ABANDON]:
		return false
	pending_reward = {}   # a escolha que ficou aberta morre com a run
	pending_altar = {}
	locked_room = ""      # e a sala trancada também
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
		"modifiers": modifiers.duplicate(), "rewards": rewards.size(), "skills": skills.duplicate(),
		"shrines": shrines_used.duplicate(), "encounters": encounters.duplicate(true)}


func _set_phase(p: String) -> void:
	phase = p
	phase_changed.emit(p)
