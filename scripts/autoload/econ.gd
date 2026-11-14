extends Node
## Econ: a única porta para mudar o personagem (ouro, itens, XP, equipamento, missões, horta).
##
## O `Game` virou espelho: guarda o estado para a UI e o combate lerem, mas quem decide é o CharacterService.
## - Solo offline: o serviço roda aqui mesmo, sobre um arquivo local (`user://solo_character.json`, conta
##   local 1, FileCharStore — o cliente não leva o SQLite, que é só do servidor). Cada pedido é aplicado
##   na hora (síncrono): o resultado chega antes de `request()` voltar.
## - Online (cliente): `request()` manda `_econ_req` ao servidor, que aplica no `Network.characters` e
##   responde só ao remetente com `_econ_res` (estado completo + eventos). Pedidos do mesmo peer chegam
##   em ordem (RPC confiável), então clique duplo vira dois pedidos processados em sequência.
## - Defesa da Cidade: o ouro da cidade é o caixa da partida (Colony.treasury), fora do personagem; o
##   personagem só recebe as recompensas por noite (solo: grant aqui; em grupo: o servidor).
##
## Todas as RPCs novas moram aqui (e não no Network): o Godot numera as RPCs de cada nó em ordem
## alfabética, e uma RPC nova no Network mudaria o id do `_register` que clientes antigos usam para
## receber a mensagem "atualize o jogo". Este autoload existe no mesmo caminho em servidor e clientes.
##
## Tabelas de balanceamento pela rede: o servidor manda `BalanceTables.encode(Balance.tables.to_dict())`
## (o mesmo formato dos JSON; as tabelas de Balance ficam sempre decodificadas) e o cliente aplica
## `Balance.apply(BalanceTables.decode(d))`. Os eventos das regras levam Color direto (RPC do Godot
## serializa Color nativamente).

## Resposta de um pedido (as UIs que precisavam do `bool` de retorno escutam isto).
signal result(op: String, ok: bool, err: String)
## O mesmo, com os argumentos do pedido e os eventos (efeitos visuais: colheita, cozinha).
signal done(op: String, args: Array, ok: bool, err: String, events: Array)

const SOLO_ACCOUNT := CharacterService.SOLO_ACCOUNT
const PICKUP := preload("res://scripts/world/pickup.gd")
## Sessão fixa do solo (o servidor usa o peer id; aqui só existe uma).
const SOLO_SESSION := 0
## Servidor: intervalo mínimo entre relatórios de vida/posição do mesmo peer (o resto é ignorado).
const REPORT_MIN_MS := 1000
## Servidor: de quanto em quanto tempo grava as contas que só mudaram por relatório.
const FLUSH_EVERY := 60.0
## Servidor: de quanto em quanto tempo limpa os pickups expirados.
const PURGE_EVERY := 10.0
## seq das respostas que o servidor manda sem pedido (concessões: abate, loot, prêmios de partida).
const PUSH_SEQ := -1
## Servidor: limite de pedidos por peer (balde de fichas: rajada, fichas por segundo). Acima dele o pedido é
## recusado com "devagar" sem tocar no banco. A coleta de loot tem balde próprio, mais folgado (a Horda
## derruba muitos pickups de uma vez); o cliente devolve ao chão o pickup recusado com "devagar".
const REQ_BURST := 10.0
const REQ_RATE := 5.0
const CLAIM_BURST := 30.0
const CLAIM_RATE := 10.0

## Arquivo do personagem solo (`--solo-save=CAMINHO` troca). Ao lado ficam a economia (*_economy.jsonl),
## a base local (*_base.json) e as partidas/recordes (*_runs.json): FileCharStore.
## O user://solo.db da 0.8.0 (SQLite) é ignorado.
var solo_save_path := "user://solo_character.json"
## Testes adiantam o relógio (horta). Vale para o serviço local e para o desenho dos canteiros.
var time_offset := 0.0
## Relatórios de vida/posição enviados (o net_test confere o envio periódico).
var reports_sent := 0
## Cliente online: concessões tentadas no próprio cliente (bug: quem concede é o servidor). O net_test exige 0.
var client_grant_errors := 0

var _store: FileCharStore = null
var _svc: CharacterService = null
var _solo_loaded := false
var _wipe_on_open := false
var _seq := 0
var _pending := {}   # cliente: seq -> {"op", "args"}
var _report_t := 0.0
var _test_server := false
var _last_report := {}   # servidor: peer -> Time.get_ticks_msec() do último relatório aceito
var _flush_t := FLUSH_EVERY
## Servidor: loot no chão de cada jogador (pickups com net_id).
var pickups := PickupRegistry.new()
var _loot_rng := RandomNumberGenerator.new()
var _purge_t := PURGE_EVERY
var _req_limit := TokenBuckets.new(REQ_BURST, REQ_RATE)
var _claim_limit := TokenBuckets.new(CLAIM_BURST, CLAIM_RATE)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	var explicit := false
	for a in args:
		if a.begins_with("--solo-save="):
			solo_save_path = a.substr(12)
			explicit = true
	if "--smoketest" in args:
		# o smoke test começa sempre de um personagem novo, num arquivo só dele
		if not explicit:
			solo_save_path = "user://smoketest_solo.json"
		_wipe_on_open = true
	elif "--colonytest" in args:
		# idem para o teste da Defesa da Cidade
		if not explicit:
			solo_save_path = "user://colonytest_solo.json"
		_wipe_on_open = true
	elif "--hubtest" in args:
		# idem para o teste da praça
		if not explicit:
			solo_save_path = "user://hubtest_solo.json"
		_wipe_on_open = true
	_test_server = "--test" in args
	_report_t = Network.autosave_interval
	_loot_rng.randomize()


func now() -> float:
	return Time.get_unix_time_from_system() + time_offset


# ================================================================ pedidos
## Pede uma operação do CharacterService.CLIENT_OPS. A resposta chega por `result`/`done` (no solo,
## antes desta função voltar). Online o pedido segue como está: o servidor recusa op/args inválidos.
func request(op: String, args: Array = []) -> void:
	if Network.is_client():
		_seq += 1
		_pending[_seq] = {"op": op, "args": args.duplicate(true)}
		if op == "claim_pickup":
			# fora de CLIENT_OPS: o servidor confere dono, validade e distância (PickupRegistry)
			_claim_pickup.rpc_id(1, _seq, int(args[0]) if not args.is_empty() else 0)
		else:
			_econ_req.rpc_id(1, _seq, op, args)
		return
	if op == "claim_pickup":
		# pickup do servidor só existe online
		_deliver(op, args, {"ok": false, "err": "op_invalida", "events": [], "state": {}})
		return
	if Network.is_server():
		push_error("Econ.request no servidor: use Network.characters (%s)" % op)
		return
	if not ensure_solo():
		_deliver(op, args, {"ok": false, "err": "sem_banco", "events": [], "state": {}})
		return
	var r := _svc.apply(SOLO_ACCOUNT, op, args)
	_deliver(op, args, r)
	if op == "donate" and r.ok:
		Hub.refresh_solo()   # a base mudou: a praça redesenha (online quem avisa é o servidor)


## Concessão (loot, missão, prêmio de partida). Só offline: online quem concede é o servidor
## (server_grant/server_kill/pickups) e a chamada no cliente vira erro, para achar as que ficaram para trás.
## `silent` não mostra o aviso de item ganho (o antigo add_item(..., true)). true se concedeu.
func grant(gold: int, xp: int, items: Dictionary, source: String, silent := false) -> bool:
	if Network.is_online():
		client_grant_errors += 1
		push_error("concessão no cliente online: %s (ouro %d, xp %d, itens %s)" % [source, gold, xp, items])
		return false
	if not ensure_solo():
		return false
	var r := _svc.grant(SOLO_ACCOUNT, gold, xp, items, source)
	if silent:
		r.events = r.events.filter(func(e: Dictionary) -> bool: return e.get("t") != "looted")
	_deliver("grant", [gold, xp, items, source], r)
	return bool(r.get("ok", false))


## Abate (XP, contagem, progresso de missão, chefe). Só offline, como grant().
func kill(kind: String, xp: int) -> void:
	if Network.is_online():
		client_grant_errors += 1
		push_error("concessão no cliente online: abate de %s (xp %d)" % [kind, xp])
		return
	if not ensure_solo():
		return
	_deliver("kill", [kind, xp], _svc.kill(SOLO_ACCOUNT, kind, xp))


## Começo de uma partida no solo: abre o registro (runs) e devolve o run_id. Online não faz nada (0): quem
## registra é o servidor.
func run_start(mode: String) -> int:
	if Network.is_online() or not ensure_solo():
		return 0
	return _svc.start_run(mode, [SOLO_ACCOUNT])


## Fim de uma partida no solo: concede os Ecos (CharacterService.finish_player), fecha o registro da partida
## (vale para o recorde) e entrega o estado. Devolve os Ecos ganhos. Online não faz nada (0).
func run_finish(run_id: int, mode: String, reached: int, gold: int, xp: int, items: Dictionary, build := {}) -> int:
	if Network.is_online() or not ensure_solo():
		return 0
	var r := _svc.finish_player(run_id, SOLO_ACCOUNT, mode, reached, gold, xp, items, build)
	if r.ok and run_id > 0:
		_svc.close_run(run_id, reached, {})
	_deliver("run_finish", [run_id, mode, reached], r)
	if not r.ok:
		return 0
	for e in r.events:
		if e.get("t") == "ecos":
			return int(e.get("n", 0))
	return 0


## Solo: estado da base local ({id: {"level", "fund"}}). Online {}: a base é do servidor (Hub.base).
func base_state() -> Dictionary:
	if Network.is_online() or not ensure_solo():
		return {}
	return _svc.base_state()


## Solo: bônus da base local. Online {} (Hub.base_bonus() usa a base que veio do servidor).
func base_bonus() -> Dictionary:
	if Network.is_online() or not ensure_solo():
		return {}
	return _svc.base_bonus()


## Solo: recorde de cada modo ({"horde": {"reached", "names"}, "city": ...}). Online {} (Hub.records).
func records() -> Dictionary:
	if Network.is_online() or not ensure_solo():
		return {}
	return _svc.records()


## Solo: maiores doadores de uma construção ([{"name", "amount"}]). Online [] (vem em Hub.base).
func top_donors(id: String, limit := 5) -> Array:
	if Network.is_online() or not ensure_solo():
		return []
	return _svc.top_donors(id, limit)


## Recorde de partida (horde_best/city_best) no personagem solo. Online só no espelho: o servidor grava
## (CharacterService.set_record) e manda o estado.
func set_record(key: String, value) -> void:
	if not (key in ["horde_best", "city_best"]):
		return
	Game.flags[key] = value
	if Network.is_online() or not ensure_solo():
		return
	var s := _svc.load_or_create(SOLO_ACCOUNT)
	s.flags[key] = value
	_svc.save(SOLO_ACCOUNT)


## Cliente online, servidor em --test: pede ouro de teste (resposta como op "test_gold").
func request_test_gold(amount: int) -> void:
	if not Network.is_client():
		return
	_seq += 1
	_pending[_seq] = {"op": "test_gold", "args": [amount]}
	_grant_test_gold.rpc_id(1, _seq, amount)


## Cliente online, servidor em --test: pede Ecos de teste (resposta como op "test_ecos").
func request_test_ecos(amount: int) -> void:
	if not Network.is_client():
		return
	_seq += 1
	_pending[_seq] = {"op": "test_ecos", "args": [amount]}
	_grant_test_ecos.rpc_id(1, _seq, amount)


func pending_count() -> int:
	return _pending.size()


## Cliente saiu do servidor (Network.leave): pedidos sem resposta falham com "sem_conexao" (as UIs
## que esperam não ficam travadas) e o solo é recarregado do save solo na próxima vez (nunca roda
## sobre o estado que veio do servidor).
func client_reset() -> void:
	var waiting := _pending
	_pending = {}
	for seq in waiting:
		_finish(str(waiting[seq].op), waiting[seq].args, false, "sem_conexao", [], {})
	_solo_loaded = false


# ================================================================ vida, mana e posição
## Combate é do cliente: vida/mana/posição vão ao serviço de tempos em tempos e ao trocar de zona.
func report_vitals(pos: Vector3, yaw: float) -> void:
	if Network.is_client():
		if multiplayer.multiplayer_peer == null or \
				multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			return
		_econ_report.rpc_id(1, Game.hp, Game.mp, pos, yaw, Game.fury)
		reports_sent += 1
	elif not Network.is_online() and _solo_loaded and _svc != null:
		_svc.report(SOLO_ACCOUNT, SOLO_SESSION, Game.hp, Game.mp, pos, yaw, Game.fury)
		_svc.save(SOLO_ACCOUNT)
		reports_sent += 1


## F5 offline: grava vida e posição (o resto já foi gravado a cada pedido). Online não faz nada.
func quick_save(pos: Vector3, yaw: float) -> bool:
	if Network.is_online():
		return false
	if Game.run_mods.get("active", false):
		Game.notify.emit("Não é possível salvar durante o desafio.", Color(1, 0.6, 0.5))
		return false
	if not ensure_solo():
		Game.notify.emit("Falha ao salvar!", Color(1, 0.4, 0.4))
		return false
	report_vitals(pos, yaw)
	Game.notify.emit("Jogo salvo.", Color(0.7, 1.0, 0.7))
	return true


## F9 offline: relê o personagem do save solo e recomeça Valdoria nele. Online não faz nada.
func quick_load() -> bool:
	if Network.is_online() or not has_solo():
		return false
	if not reload_solo():
		return false
	Game.reset_run_mods()
	get_tree().paused = false
	get_tree().change_scene_to_file(Game.WORLD_SCENE)
	return true


func _physics_process(delta: float) -> void:
	if Network.is_server():
		# relatórios só mexem no cache: a gravação é do servidor, em lote, não a cada pedido do cliente
		_flush_t -= delta
		if _flush_t <= 0.0:
			_flush_t = FLUSH_EVERY
			if Network.characters != null:
				Network.characters.flush_dirty()
		_purge_t -= delta
		if _purge_t <= 0.0:
			_purge_t = PURGE_EVERY
			pickups.purge_expired()
		return
	# solo: relatório periódico (online o Network cuida, com o mesmo intervalo)
	if Network.is_online() or not _solo_loaded:
		return
	_report_t -= delta
	if _report_t > 0.0:
		return
	_report_t = Network.autosave_interval
	var w := get_tree().current_scene
	if w == null or w.get("role") != null or Game.run_mods.get("active", false):
		return
	var p = w.get("player")
	if p is Player and is_instance_valid(p) and not p.dead:
		report_vitals(p.global_position, p.model.rotation.y)


# ================================================================ solo (user://solo_character.json)
## Abre o armazenamento local e carrega o personagem solo no Game (se ainda não estiver carregado).
func ensure_solo() -> bool:
	if _solo_loaded and _svc != null:
		return true
	return start_solo()


## Abre o save solo e aplica o personagem salvo (vida, mana e posição inclusive).
func start_solo() -> bool:
	if not _open_store():
		return false
	if Balance.from_server:
		Balance.reload_local()   # o solo usa as tabelas da versão, não as do último servidor
	if _svc != null:
		_svc.save(SOLO_ACCOUNT)
	_svc = CharacterService.new(_store, Balance.tables, now)
	_svc.set_session(SOLO_ACCOUNT, SOLO_SESSION)
	var s := _svc.load_or_create(SOLO_ACCOUNT)
	_solo_loaded = true
	Game.apply_state(s.to_dict(), true)
	return true


## Fecha o armazenamento e o serviço e abre tudo de novo a partir do arquivo (F9 e testes de persistência).
func reload_solo() -> bool:
	if _svc != null:
		_svc.save(SOLO_ACCOUNT)
	_svc = null
	_solo_loaded = false
	if _store != null:
		_store.close()
		_store = null
	return start_solo()


## Existe personagem solo salvo neste PC?
func has_solo() -> bool:
	if not _open_store():
		return false
	return _store.load_char(SOLO_ACCOUNT) is Dictionary


## "Nível 3 — 2026-11-13 18:20:05" do personagem solo ("" se não houver).
func solo_info() -> String:
	if not _open_store():
		return ""
	var d = _store.load_char(SOLO_ACCOUNT)
	if not (d is Dictionary):
		return ""
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	return "Nível %d — %s" % [int(d.get("level", 1)),
		Time.get_datetime_string_from_unix_time(int(d.get("updated_at", 0)) + bias, true)]


## "Novo jogo": apaga o personagem solo (o menu pergunta antes) e começa um novo.
func reset_solo() -> bool:
	if not _open_store():
		return false
	if _svc != null:
		_svc.unload(SOLO_ACCOUNT)
	_svc = null
	_solo_loaded = false
	var ok := _store.delete_char(SOLO_ACCOUNT)
	if not ok:
		push_error("Econ: não apagou o personagem solo: %s" % _store.last_error)
	return start_solo() and ok


func _open_store() -> bool:
	if _store != null:
		return true
	_store = FileCharStore.new(solo_save_path)
	if _wipe_on_open:
		_wipe_on_open = false
		_store.remove_files()   # personagem, temporário e registro da economia
	return true


## Demos de screenshot (`--farmdemo`/`--geardemo`/`--weapon=`): personagem novo num arquivo à parte,
## apagado a cada vez (não mexe no save solo). Chamado pelo Game antes do _ready deste autoload.
func start_scratch_solo(path: String) -> bool:
	if _store != null:
		_store.close()
		_store = null
	_svc = null
	_solo_loaded = false
	solo_save_path = path
	_wipe_on_open = true
	return start_solo()


# ================================================================ entrega do resultado
## Dados extras do resultado (colheita) viram eventos, que é o que atravessa a rede.
static func events_of(r: Dictionary) -> Array:
	var ev: Array = r.get("events", []).duplicate()
	if r.has("harvest"):
		var h: Dictionary = r.harvest.duplicate()
		h["t"] = "harvest"
		ev.append(h)
	return ev


func _deliver(op: String, args: Array, r: Dictionary) -> void:
	_finish(op, args, bool(r.get("ok", false)), str(r.get("err", "")), events_of(r), r.get("state", {}))


func _finish(op: String, args: Array, ok: bool, err: String, events: Array, state: Dictionary) -> void:
	if not state.is_empty():
		Game.apply_state(state)
	Game.apply_events(events)
	Game.after_op(op, args, ok, events)
	done.emit(op, args, ok, err, events)
	result.emit(op, ok, err)


# ================================================================ servidor
## Logo antes do _accepted: tabelas e estado inicial (o cliente aplica antes de trocar de cena).
func server_send_initial(peer: int, account: int) -> void:
	_balance.rpc_id(peer, BalanceTables.encode(Balance.tables.to_dict()))
	var s := Network.characters.load_or_create(account)
	_econ_res.rpc_id(peer, 0, true, "", [], s.to_dict())


## Servidor: o peer saiu (esquece o relógio do relatório).
func server_peer_gone(peer: int) -> void:
	_last_report.erase(peer)
	_req_limit.forget(peer)
	_claim_limit.forget(peer)
	pickups.drop_peer(peer)


## Servidor: o peer trocou de zona; o loot que ficou no chão da zona antiga some (o cliente já trocou de cena).
## Sair de Valdoria leva junto o loot da Horda (a partida acontece dentro dela).
func server_peer_zone_left(peer: int, old_zone: String) -> void:
	pickups.drop_peer(peer, old_zone)
	if old_zone == "world":
		pickups.drop_peer(peer, "horde")


## Conta do peer (0 se não está no jogo).
func account_of(peer: int) -> int:
	return int(Network.players[peer].get("account", 0)) if Network.players.has(peer) else 0


## Servidor: manda ao peer o estado e os eventos de uma concessão (resposta sem pedido, seq PUSH_SEQ).
func server_push(peer: int, r: Dictionary, extra_events: Array = []) -> void:
	if not Network.is_server() or not Network.players.has(peer):
		return
	_econ_res.rpc_id(peer, PUSH_SEQ, bool(r.get("ok", false)), str(r.get("err", "")),
		events_of(r) + extra_events, r.get("state", {}))


## Servidor: concede ao personagem do peer e avisa o cliente. `account` > 0 serve para quem já saiu da
## lista de jogadores (desconexão no meio da partida): aí só grava. `silent` tira os avisos de item.
func server_grant(peer: int, gold: int, xp: int, items: Dictionary, source: String, account := 0,
		silent := false, extra_events: Array = []) -> Dictionary:
	if account <= 0:
		account = account_of(peer)
	if account <= 0 or Network.characters == null:
		return {"ok": false, "err": "sem_sessao", "events": [], "state": {}}
	var r := Network.characters.grant(account, gold, xp, items, source)
	if silent:
		r.events = r.events.filter(func(e: Dictionary) -> bool: return e.get("t") != "looted")
	server_push(peer, r, extra_events)
	return r


## Servidor: abate (XP, contagem, missões, chefe) no personagem do peer.
func server_kill(peer: int, kind: String, xp: int) -> Dictionary:
	var account := account_of(peer)
	if account <= 0 or Network.characters == null:
		return {"ok": false, "err": "sem_sessao", "events": [], "state": {}}
	var r := Network.characters.kill(account, kind, xp)
	server_push(peer, r)
	return r


## Servidor: recorde de partida no personagem (só sobe) e avisa o cliente.
func server_record(peer: int, key: String, value, account := 0) -> void:
	if account <= 0:
		account = account_of(peer)
	if account <= 0 or Network.characters == null:
		return
	var r := Network.characters.set_record(account, key, value)
	if r.ok:
		server_push(peer, r)


## Servidor: um pickup no chão só para o peer (o cliente cria o nó e pede a coleta pelo net_id).
## Um pickup por coisa: ouro sozinho ou um item com a quantidade (como os nós do solo).
func server_spawn_pickup(peer: int, zone: String, pos: Vector3, gold: int, items: Dictionary) -> int:
	if not Network.players.has(peer) or (gold <= 0 and items.is_empty()):
		return 0
	var id := pickups.spawn(peer, zone, pos, gold, items)
	_pickup_spawned.rpc_id(peer, id, gold, items, pos)
	return id


## Servidor: sorteio do loot de um inimigo (LootRules) para um jogador, em pickups (um sorteio por jogador).
func server_drop_loot(peer: int, kind: String, pos: Vector3, zone := "world") -> void:
	var loot := LootRules.roll(Balance.tables, kind, _loot_rng)
	if int(loot.gold) > 0:
		server_spawn_pickup(peer, zone, pos, int(loot.gold), {})
	for id in loot.items:
		server_spawn_pickup(peer, zone, pos, 0, {id: int(loot.items[id])})


func _sender_account() -> int:
	if not Network.is_server() or Network.characters == null:
		return 0
	var id := multiplayer.get_remote_sender_id()
	return int(Network.players[id].get("account", 0)) if Network.players.has(id) else 0


## Pedido sem sessão (ainda não aceito, já derrubado): responde a falha para o cliente não ficar esperando.
func _reply_no_session(seq: int) -> void:
	if Network.is_server():
		_econ_res.rpc_id(multiplayer.get_remote_sender_id(), seq, false, "sem_sessao", [], {})


@rpc("any_peer", "call_remote", "reliable")
func _econ_req(seq: int, op: String, args: Array) -> void:
	var account := _sender_account()
	if account <= 0:
		_reply_no_session(seq)
		return
	var peer := multiplayer.get_remote_sender_id()
	if not _req_limit.allow(peer, Time.get_ticks_msec() / 1000.0):
		_econ_res.rpc_id(peer, seq, false, "devagar", [], {})
		return
	var r := Network.characters.apply(account, op, args)
	_econ_res.rpc_id(multiplayer.get_remote_sender_id(), seq, r.ok, r.err, events_of(r), r.state)
	if op == "donate" and r.ok:
		# a base é de todos: o servidor manda o estado novo a quem está conectado
		Hub.server_base_changed(account, r.events)


## Só atualiza o cache (CharacterService.report); grava no próximo pedido, na saída ou no flush periódico.
## Um relatório por segundo por peer, no máximo (os legítimos vêm a cada autosave ou troca de zona).
@rpc("any_peer", "call_remote", "reliable")
func _econ_report(hp: float, mp: float, pos: Vector3, yaw: float, fury: float) -> void:
	var account := _sender_account()
	if account <= 0:
		return
	var peer := multiplayer.get_remote_sender_id()
	var now_ms := Time.get_ticks_msec()
	if _last_report.has(peer) and now_ms - int(_last_report[peer]) < REPORT_MIN_MS:
		return
	_last_report[peer] = now_ms
	Network.characters.report(account, peer, hp, mp, pos, yaw, fury)


## Só com o servidor em --test (net_test): ouro para os testes de compra.
@rpc("any_peer", "call_remote", "reliable")
func _grant_test_gold(seq: int, amount: int) -> void:
	var account := _sender_account()
	if account <= 0:
		_reply_no_session(seq)
		return
	var r := Network.characters.grant_test_gold(account, amount, _test_server)
	_econ_res.rpc_id(multiplayer.get_remote_sender_id(), seq, r.ok, r.err, events_of(r), r.state)


## Só com o servidor em --test (net_test): Ecos para os testes de passiva e doação.
@rpc("any_peer", "call_remote", "reliable")
func _grant_test_ecos(seq: int, amount: int) -> void:
	var account := _sender_account()
	if account <= 0:
		_reply_no_session(seq)
		return
	var r := Network.characters.grant_test_ecos(account, amount, _test_server)
	_econ_res.rpc_id(multiplayer.get_remote_sender_id(), seq, r.ok, r.err, events_of(r), r.state)


## Coleta de um pickup do servidor: confere dono, se já foi pego, validade e distância (última posição
## recebida do jogador, na mesma zona) e concede. Loot da Horda conta para o resumo da partida.
@rpc("any_peer", "call_remote", "reliable")
func _claim_pickup(seq: int, net_id: int) -> void:
	var account := _sender_account()
	if account <= 0:
		_reply_no_session(seq)
		return
	var peer := multiplayer.get_remote_sender_id()
	if not _claim_limit.allow(peer, Time.get_ticks_msec() / 1000.0):
		_econ_res.rpc_id(peer, seq, false, "devagar", [], {})
		return
	var zone := pickups.zone_of(net_id)
	var pos: Vector3 = Network.last_pos.get(peer, Vector3.INF)
	# a Horda acontece dentro de Valdoria (mesmas coordenadas)
	if Network.zone_of(peer) != ("world" if zone == "horde" else zone):
		pos = Vector3.INF
	var c := pickups.claim(net_id, peer, pos)
	if not c.ok:
		_econ_res.rpc_id(peer, seq, false, str(c.err), [], {})
		return
	var horde := zone == "horde"
	var r := Network.characters.grant(account, int(c.gold), 0, c.items, "horde_run" if horde else "loot")
	if not r.ok:
		# não concedeu (erro no banco): o pickup volta ao chão, o cliente pode tentar de novo
		pickups.restore(net_id, c.entry)
		_econ_res.rpc_id(peer, seq, false, str(r.err), [], {})
		return
	if horde and Network.horde_run != null and is_instance_valid(Network.horde_run):
		Network.horde_run.server_note_gain(peer, int(c.gold), c.items)
	_econ_res.rpc_id(peer, seq, r.ok, r.err, events_of(r), r.state)


# ================================================================ cliente
@rpc("authority", "call_remote", "reliable")
func _balance(tables: Dictionary) -> void:
	Balance.apply(BalanceTables.decode(tables), true)


## seq 0 = estado inicial (na aceitação): aplica tudo, vida/mana/posição inclusive.
@rpc("authority", "call_remote", "reliable")
func _econ_res(seq: int, ok: bool, err: String, events: Array, state: Dictionary) -> void:
	if seq == 0:
		Game.apply_state(state, true)
		return
	if seq == PUSH_SEQ:
		# concessão do servidor (abate, loot, prêmio): estado novo + eventos, sem pedido pendente
		_finish("push", [], ok, err, events, state)
		return
	var req: Dictionary = _pending.get(seq, {"op": "", "args": []})
	_pending.erase(seq)
	_finish(str(req.op), req.args, ok, err, events, state)


## Servidor → dono: pickup novo no chão (ouro ou um item). O nó pede a coleta com request("claim_pickup").
@rpc("authority", "call_remote", "reliable")
func _pickup_spawned(net_id: int, gold: int, items: Dictionary, pos: Vector3) -> void:
	var w := Network.world
	if w == null or not is_instance_valid(w):
		return
	# na Horda o loot fica dentro da partida (some com ela)
	var parent: Node = w
	var sv = w.get("survival")
	if sv != null and is_instance_valid(sv) and sv.get("role") == "client":
		parent = sv
	if gold > 0:
		PICKUP.spawn(parent, "", gold, pos, net_id)
		return
	for id in items:
		if ItemDB.ITEMS.has(str(id)):
			PICKUP.spawn(parent, str(id), int(items[id]), pos, net_id)
		return
