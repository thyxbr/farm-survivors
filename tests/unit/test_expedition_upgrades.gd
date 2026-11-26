extends RefCounted
## Melhorias temporárias da expedição (ExpeditionUpgrades) e a recompensa das salas no ExpeditionRun:
## sorteio, soma em run_mods, uma recompensa por sala, escolha obrigatória antes de seguir e descarte no fim.


## Um run_mods recém-zerado (o mesmo formato de Game.reset_run_mods, sem precisar do autoload).
const BASE := {"active": true, "damage": 1.0, "max_hp": 1.0, "max_hp_flat": 0.0, "speed": 1.0, "defense": 0.0,
	"regen": 0.0, "crit": 0.0, "cooldown": 1.0, "area": 1.0, "magnet": 1.0, "xp": 1.0, "gold": 1.0,
	"lifesteal": 0.0, "cdr": 0.0}


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001


func _run() -> ExpeditionRun:
	var r := ExpeditionRun.create("pantano")
	r.start()
	return r


## Leva a run até a sala `room` (seguindo o grafo) e a limpa.
func _clear(r: ExpeditionRun, room: String) -> void:
	r.enter_room(room)
	r.clear_room(room)


func _rng(s: int) -> RandomNumberGenerator:
	var g := RandomNumberGenerator.new()
	g.seed = s
	return g


# ================================================================ tabela
func test_table_is_valid() -> void:
	var problems := ExpeditionUpgrades.validate()
	for p in problems:
		T.ok(false, p)
	T.eq(problems.size(), 0, "tabela de melhorias sem problemas")
	T.ok(ExpeditionUpgrades.DATA.size() >= 3 and ExpeditionUpgrades.DATA.size() <= 6, "entre 3 e 6 melhorias")
	for id in ExpeditionUpgrades.DATA:
		for k in ExpeditionUpgrades.DATA[id].add:
			T.ok(BASE.has(k), "%s mexe em %s, que existe em run_mods" % [id, k])


func test_roll_gives_distinct_choices_and_is_seeded() -> void:
	var a := ExpeditionUpgrades.roll(_rng(42), {})
	T.eq(a.size(), ExpeditionUpgrades.CHOICES, "3 opções")
	var seen := {}
	for id in a:
		T.ok(ExpeditionUpgrades.has(id), "%s existe" % id)
		T.ok(not seen.has(id), "sem repetição (%s)" % id)
		seen[id] = true
	T.eq(ExpeditionUpgrades.roll(_rng(42), {}), a, "mesma semente, mesmas opções")


func test_roll_skips_maxed_upgrades() -> void:
	var taken := {}
	var ids := ExpeditionUpgrades.DATA.keys()
	for i in ids.size() - 1:
		taken[ids[i]] = ExpeditionUpgrades.MAX_STACKS
	for s in 10:
		var out := ExpeditionUpgrades.roll(_rng(s), taken)
		T.eq(out.size(), 1, "só a que não está no máximo")
		T.eq(out[0], str(ids[-1]), "a que sobrou")
	taken[ids[-1]] = ExpeditionUpgrades.MAX_STACKS
	T.eq(ExpeditionUpgrades.roll(_rng(1), taken).size(), 0, "tudo no máximo: nada a oferecer")


func test_total_mods_stack_and_apply_to_base() -> void:
	var taken := {"furia": 2, "seiva": 1, "casca": 1, "nevoa": 3, "sussurro": 1}
	var mods := ExpeditionUpgrades.apply_to(BASE, taken)
	T.ok(_near(mods.damage, 1.24), "dano: 1 + 2 x 12%% = %.2f" % mods.damage)
	T.ok(_near(mods.max_hp, 1.15), "vida máxima +15%")
	T.ok(_near(mods.defense, 5.0), "defesa +5")
	T.ok(_near(mods.speed, 1.24), "velocidade 1 + 3 x 8%")
	T.ok(_near(mods.cdr, 0.08), "recarga -8%")
	T.ok(_near(mods.crit, 0.0) and _near(mods.cooldown, 1.0), "o resto de run_mods intacto")
	T.ok(_near(BASE.damage, 1.0) and _near(BASE.cdr, 0.0), "apply_to não mexe na base")
	T.eq(ExpeditionUpgrades.apply_to(BASE, {}), BASE, "sem melhorias = run_mods padrão (removidas)")
	var capped := ExpeditionUpgrades.total_mods({"furia": 99, "inexistente": 3})
	T.ok(_near(capped.damage, 0.12 * ExpeditionUpgrades.MAX_STACKS), "acúmulo limitado ao máximo")
	T.eq(capped.size(), 1, "melhoria desconhecida não soma nada")


func test_level_text() -> void:
	T.eq(ExpeditionUpgrades.level_text("furia", {}), "Nv 1/5", "primeira")
	T.eq(ExpeditionUpgrades.level_text("furia", {"furia": 2}), "Nv 3/5", "terceiro acúmulo")


# ================================================================ salas que dão recompensa
func test_reward_rooms_in_the_swamp() -> void:
	var d := ExpeditionDefs.get_def("pantano")
	var rooms := ExpeditionDefs.reward_rooms(d)
	T.ok(rooms.size() >= 1, "o Pântano tem salas com recompensa")
	for r in rooms:
		T.ok(ExpeditionDefs.kind_of(d, r) in ExpeditionDefs.REWARD_KINDS, "%s é sala de luta" % r)
	T.ok(not ExpeditionDefs.grants_reward(d, "Trono da Rainha"), "sala de chefe não dá recompensa")
	T.ok(not ExpeditionDefs.grants_reward(d, "Entrada"), "chegada não dá recompensa")
	var bad := {"start": "A", "rooms": {"A": {"kind": "start", "reward": true, "next": ["B"]},
		"B": {"kind": "boss", "reward": true, "next": []}}}
	T.ok(ExpeditionDefs.validate(bad).size() >= 2, "recompensa em sala que não é de luta é erro")


func test_ids_follow_the_order() -> void:
	T.ok(ExpeditionDefs.ids().size() >= 1 and ExpeditionDefs.ids()[0] == "pantano", "Pântano é a primeira expedição")
	for id in ExpeditionDefs.ids():
		T.ok(ExpeditionDefs.has(id), "%s existe" % id)
		T.ok(str(ExpeditionDefs.get_def(id).get("desc", "")) != "", "%s tem descrição para a Guilda" % id)
		T.ok(str(ExpeditionDefs.get_def(id).get("boss", "")) != "", "%s diz qual é o chefe" % id)


# ================================================================ fluxo da recompensa na run
func test_reward_only_after_clearing() -> void:
	var r := _run()
	T.ok(not r.can_offer_reward("Encruzilhada"), "sala não visitada não recompensa")
	r.enter_room("Encruzilhada")
	T.ok(not r.offer_reward("Encruzilhada", ["furia", "seiva", "casca"]), "sala com monstros não recompensa")
	r.clear_room("Encruzilhada")
	T.eq(r.rooms_awaiting_reward(), ["Encruzilhada"] as Array[String], "sala limpa esperando a recompensa")
	T.ok(r.offer_reward("Encruzilhada", ["furia", "seiva", "casca"]), "limpa: oferece")
	T.ok(r.has_pending_reward(), "escolha pendente")
	T.eq(r.rooms_awaiting_reward().size(), 0, "a pendente não aparece de novo")


func test_reward_is_granted_once_per_room() -> void:
	var r := _run()
	_clear(r, "Encruzilhada")
	r.offer_reward("Encruzilhada", ["furia", "seiva", "casca"])
	T.ok(not r.offer_reward("Encruzilhada", ["nevoa", "sussurro", "casca"]), "não reabre com outras opções")
	T.ok(not r.choose_reward("nevoa"), "não escolhe o que não foi oferecido")
	T.ok(r.choose_reward("furia"), "escolhe uma das opções")
	T.eq(r.modifiers, {"furia": 1}, "registrada no estado da run")
	T.eq(r.rewards, {"Encruzilhada": "furia"}, "sala marcada como recompensada")
	T.ok(not r.choose_reward("seiva"), "não escolhe duas vezes")
	T.ok(not r.offer_reward("Encruzilhada", ["seiva", "casca", "nevoa"]), "a mesma sala não recompensa de novo")
	T.ok(not r.clear_room("Encruzilhada"), "limpar de novo não muda nada")
	T.eq(r.modifiers, {"furia": 1}, "continua uma melhoria só")


func test_cannot_advance_while_choosing() -> void:
	var r := _run()
	_clear(r, "Encruzilhada")
	r.offer_reward("Encruzilhada", ["furia", "seiva", "casca"])
	T.ok(not r.can_enter("Clareira Funda") and not r.enter_room("Clareira Funda"), "não segue com a escolha aberta")
	T.ok(not r.enter_room("Entrada"), "nem volta")
	T.eq(r.current_room, "Encruzilhada", "fica na sala")
	r.choose_reward("seiva")
	T.ok(r.enter_room("Clareira Funda"), "escolheu: segue")


func test_rewards_stack_across_rooms() -> void:
	var r := _run()
	_clear(r, "Encruzilhada")
	r.offer_reward("Encruzilhada", ["furia", "seiva", "casca"])
	r.choose_reward("furia")
	_clear(r, "Clareira Funda")
	T.ok(r.offer_reward("Clareira Funda", ["furia", "nevoa", "sussurro"]), "segunda sala oferece")
	r.choose_reward("furia")
	T.eq(r.modifiers, {"furia": 2}, "a mesma melhoria acumula")
	T.ok(_near(ExpeditionUpgrades.apply_to(BASE, r.modifiers).damage, 1.24), "dano acumulado")
	T.eq(int(r.summary().rewards), 2, "resumo conta as recompensas")
	T.eq(r.summary().modifiers, {"furia": 2}, "resumo traz as melhorias")


func test_no_valid_choice_never_blocks() -> void:
	var r := _run()
	_clear(r, "Encruzilhada")
	T.ok(not r.offer_reward("Encruzilhada", []), "sem opção não abre escolha")
	T.ok(not r.has_pending_reward() and r.is_rewarded("Encruzilhada"), "a sala conta como recompensada")
	T.ok(r.enter_room("Clareira Funda"), "e o jogador segue")
	_clear(r, "Clareira Funda")
	T.ok(r.offer_reward("Clareira Funda", ["inexistente", "furia", "furia"]), "opções inválidas e repetidas filtradas")
	T.eq(r.pending_reward.choices, ["furia"] as Array[String], "fica só a válida")


func test_end_of_run_discards_pending_choice() -> void:
	for how in [ExpeditionRun.ABANDON, ExpeditionRun.DEFEAT]:
		var r := _run()
		_clear(r, "Encruzilhada")
		r.offer_reward("Encruzilhada", ["furia", "seiva", "casca"])
		r.finish(how)
		T.ok(not r.has_pending_reward(), "%s: escolha pendente descartada" % how)
		T.ok(not r.choose_reward("furia"), "%s: não escolhe depois do fim" % how)
		T.ok(not r.offer_reward("Clareira Funda", ["furia"]), "%s: nada oferecido depois do fim" % how)
		T.eq(r.modifiers.size(), 0, "%s: nada aplicado" % how)


func test_new_run_starts_clean() -> void:
	var a := _run()
	_clear(a, "Encruzilhada")
	a.offer_reward("Encruzilhada", ["furia", "seiva", "casca"])
	a.choose_reward("casca")
	a.abandon()
	var b := _run()
	T.eq(b.modifiers.size(), 0, "run nova sem as melhorias da anterior")
	T.eq(b.rewards.size(), 0, "nem as recompensas")
	T.ok(not b.has_pending_reward(), "nem escolha pendente")
