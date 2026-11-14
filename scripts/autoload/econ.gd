extends Node
## Econ: a única porta para mudar o personagem (ouro, itens, XP, equipamento, missões, horta).
##
## O `Game` virou espelho: guarda o estado para a UI e o combate lerem, mas quem decide é o CharacterService.
## - Solo offline: o serviço roda aqui mesmo, sobre `user://solo.db` (conta local 1). Cada pedido é
##   aplicado na hora (síncrono): o resultado chega antes de `request()` voltar.
## - Online (cliente): `request()` manda `_econ_req` ao servidor, que aplica no `Network.characters` e
##   responde só ao remetente com `_econ_res` (estado completo + eventos). Pedidos do mesmo peer chegam
##   em ordem (RPC confiável), então clique duplo vira dois pedidos processados em sequência.
## - Defesa da Cidade solo (até a Task 10): personagem em memória ("sandbox"), salvo no save da cidade;
##   as mesmas regras (CharRules), sem banco.
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
## Sessão fixa do solo (o servidor usa o peer id; aqui só existe uma).
const SOLO_SESSION := 0
## Servidor: intervalo mínimo entre relatórios de vida/posição do mesmo peer (o resto é ignorado).
const REPORT_MIN_MS := 1000
## Servidor: de quanto em quanto tempo grava as contas que só mudaram por relatório.
const FLUSH_EVERY := 60.0

var solo_db_path := "user://solo.db"
## Testes adiantam o relógio (horta). Vale para o serviço local e para o desenho dos canteiros.
var time_offset := 0.0
## Defesa da Cidade solo: personagem em memória, fora do solo.db.
var sandbox := false
## Relatórios de vida/posição enviados (o net_test confere o envio periódico).
var reports_sent := 0

var _db: Db = null
var _svc: CharacterService = null
var _solo_loaded := false
var _wipe_on_open := false
var _seq := 0
var _pending := {}   # cliente: seq -> {"op", "args"}
var _report_t := 0.0
var _test_server := false
var _last_report := {}   # servidor: peer -> Time.get_ticks_msec() do último relatório aceito
var _flush_t := FLUSH_EVERY


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	var explicit := false
	for a in args:
		if a.begins_with("--solo-db="):
			solo_db_path = a.substr(10)
			explicit = true
	if "--smoketest" in args:
		# o smoke test começa sempre de um personagem novo, num banco só dele
		if not explicit:
			solo_db_path = "user://smoketest_solo.db"
		_wipe_on_open = true
	_test_server = "--test" in args
	_report_t = Network.autosave_interval


func now() -> float:
	return Time.get_unix_time_from_system() + time_offset


# ================================================================ pedidos
## Pede uma operação do CharacterService.CLIENT_OPS. A resposta chega por `result`/`done` (no solo,
## antes desta função voltar). Online o pedido segue como está: o servidor recusa op/args inválidos.
func request(op: String, args: Array = []) -> void:
	if Network.is_client():
		_seq += 1
		_pending[_seq] = {"op": op, "args": args.duplicate(true)}
		_econ_req.rpc_id(1, _seq, op, args)
		return
	if Network.is_server():
		push_error("Econ.request no servidor: use Network.characters (%s)" % op)
		return
	if sandbox:
		_deliver(op, args, _sandbox(func(s: CharState) -> Dictionary: return _local_svc().apply_to(s, op, args)))
		return
	if not ensure_solo():
		_deliver(op, args, {"ok": false, "err": "sem_banco", "events": [], "state": {}})
		return
	_deliver(op, args, _svc.apply(SOLO_ACCOUNT, op, args))


## Concessão (loot, missão, prêmio de partida). Só offline: online quem concede é o servidor
## (Task 9) e a chamada no cliente vira erro, para achar as que ficaram para trás.
## `silent` não mostra o aviso de item ganho (o antigo add_item(..., true)).
func grant(gold: int, xp: int, items: Dictionary, source: String, silent := false) -> void:
	if Network.is_online():
		push_error("concessão no cliente online: %s (ouro %d, xp %d, itens %s)" % [source, gold, xp, items])
		return
	var r: Dictionary
	if sandbox:
		r = _sandbox(func(s: CharState) -> Dictionary: return CharRules.grant(s, Balance.tables, gold, xp, items))
	elif ensure_solo():
		r = _svc.grant(SOLO_ACCOUNT, gold, xp, items, source)
	else:
		return
	if silent:
		r.events = r.events.filter(func(e: Dictionary) -> bool: return e.get("t") != "looted")
	_deliver("grant", [gold, xp, items, source], r)


## Abate (XP, contagem, progresso de missão, chefe). Só offline, como grant().
func kill(kind: String, xp: int) -> void:
	if Network.is_online():
		push_error("concessão no cliente online: abate de %s (xp %d)" % [kind, xp])
		return
	var r: Dictionary
	if sandbox:
		r = _sandbox(func(s: CharState) -> Dictionary: return CharRules.kill(s, Balance.tables, kind, xp))
	elif ensure_solo():
		r = _svc.kill(SOLO_ACCOUNT, kind, xp)
	else:
		return
	_deliver("kill", [kind, xp], r)


## Recorde de partida (horde_best/city_best) no personagem solo. Online fica com o servidor (Task 9/10).
func set_record(key: String, value) -> void:
	if not (key in ["horde_best", "city_best"]):
		return
	Game.flags[key] = value
	if Network.is_online() or sandbox or not ensure_solo():
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


func pending_count() -> int:
	return _pending.size()


## Cliente saiu do servidor (Network.leave): pedidos sem resposta falham com "sem_conexao" (as UIs
## que esperam não ficam travadas) e o solo é recarregado do solo.db na próxima vez (nunca roda
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
	if sandbox:
		return
	if Network.is_client():
		if multiplayer.multiplayer_peer == null or \
				multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			return
		_econ_report.rpc_id(1, Game.hp, Game.mp, pos, yaw)
		reports_sent += 1
	elif not Network.is_online() and _solo_loaded and _svc != null:
		_svc.report(SOLO_ACCOUNT, SOLO_SESSION, Game.hp, Game.mp, pos, yaw)
		_svc.save(SOLO_ACCOUNT)
		reports_sent += 1


## F5 offline: grava vida e posição (o resto já foi gravado a cada pedido). Online não faz nada.
func quick_save(pos: Vector3, yaw: float) -> bool:
	if Network.is_online() or sandbox:
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


## F9 offline: relê o personagem do solo.db e recomeça Valdoria nele. Online não faz nada.
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
		return
	# solo: relatório periódico (online o Network cuida, com o mesmo intervalo)
	if Network.is_online() or sandbox or not _solo_loaded:
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


# ================================================================ solo (user://solo.db)
## Abre o banco local e carrega o personagem solo no Game (se ainda não estiver carregado).
func ensure_solo() -> bool:
	if _solo_loaded and _svc != null and not sandbox:
		return true
	return start_solo()


## Sai do sandbox, abre o solo.db e aplica o personagem salvo (vida, mana e posição inclusive).
func start_solo() -> bool:
	sandbox = false
	if not _open_db():
		return false
	if Balance.from_server:
		Balance.reload_local()   # o solo usa as tabelas da versão, não as do último servidor
	if _svc != null:
		_svc.save(SOLO_ACCOUNT)
	_svc = CharacterService.new(_db, Balance.tables, now)
	_svc.set_session(SOLO_ACCOUNT, SOLO_SESSION)
	var s := _svc.load_or_create(SOLO_ACCOUNT)
	_solo_loaded = true
	Game.apply_state(s.to_dict(), true)
	return true


## Fecha o banco e o serviço e abre tudo de novo a partir do arquivo (F9 e testes de persistência).
func reload_solo() -> bool:
	if _svc != null:
		_svc.save(SOLO_ACCOUNT)
	_svc = null
	_solo_loaded = false
	if _db != null:
		_db.close()
		_db = null
	return start_solo()


## Existe personagem solo salvo neste PC?
func has_solo() -> bool:
	if not _open_db():
		return false
	return not _db.query("SELECT 1 FROM characters WHERE account_id = ?", [SOLO_ACCOUNT]).is_empty()


## "Nível 3 — 2026-11-13 18:20:05" do personagem solo ("" se não houver).
func solo_info() -> String:
	if not _open_db():
		return ""
	var rows := _db.query("SELECT level, updated_at FROM characters WHERE account_id = ?", [SOLO_ACCOUNT])
	if rows.is_empty():
		return ""
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	return "Nível %d — %s" % [int(rows[0]["level"]),
		Time.get_datetime_string_from_unix_time(int(rows[0]["updated_at"]) + bias, true)]


## "Novo jogo": apaga o personagem solo (o menu pergunta antes) e começa um novo.
func reset_solo() -> bool:
	if not _open_db():
		return false
	if _svc != null:
		_svc.unload(SOLO_ACCOUNT)
	_svc = null
	_solo_loaded = false
	var ok := _db.transaction(func() -> bool:
		return _db.exec("DELETE FROM inventory WHERE account_id = ?", [SOLO_ACCOUNT]) \
			and _db.exec("DELETE FROM characters WHERE account_id = ?", [SOLO_ACCOUNT]))
	if not ok:
		push_error("Econ: não apagou o personagem solo: %s" % _db.last_error)
	return start_solo() and ok


func _open_db() -> bool:
	if _db != null:
		return true
	if _wipe_on_open:
		_wipe_on_open = false
		for f in [solo_db_path, solo_db_path + "-journal"]:
			if FileAccess.file_exists(f):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	_db = Db.open(solo_db_path)
	if _db == null:
		push_error("Econ: não abriu o banco solo em %s" % solo_db_path)
		return false
	Migrations.apply(_db)
	return true


# ================================================================ sandbox (Defesa da Cidade solo)
## Personagem em memória (novo, ou o do save da cidade). Sai dele com start_solo() ou end_sandbox().
func begin_sandbox(state: Dictionary = {}) -> void:
	sandbox = true
	Game.apply_state(state if not state.is_empty() else CharState.new_character(Balance.tables).to_dict(), true)


func end_sandbox() -> void:
	sandbox = false


## Serviço sem banco, só para apply_to (validação de op/args + regras).
func _local_svc() -> CharacterService:
	return CharacterService.new(null, Balance.tables, now)


## Aplica `fn(s)` sobre o personagem do espelho e devolve o resultado com o estado novo.
func _sandbox(fn: Callable) -> Dictionary:
	var s := CharState.from_dict(Game.mirror_dict(), Balance.tables)
	var r: Dictionary = fn.call(s)
	r = r.duplicate()
	r["state"] = s.to_dict()
	return r


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
	var r := Network.characters.apply(account, op, args)
	_econ_res.rpc_id(multiplayer.get_remote_sender_id(), seq, r.ok, r.err, events_of(r), r.state)


## Só atualiza o cache (CharacterService.report); grava no próximo pedido, na saída ou no flush periódico.
## Um relatório por segundo por peer, no máximo (os legítimos vêm a cada autosave ou troca de zona).
@rpc("any_peer", "call_remote", "reliable")
func _econ_report(hp: float, mp: float, pos: Vector3, yaw: float) -> void:
	var account := _sender_account()
	if account <= 0:
		return
	var peer := multiplayer.get_remote_sender_id()
	var now_ms := Time.get_ticks_msec()
	if _last_report.has(peer) and now_ms - int(_last_report[peer]) < REPORT_MIN_MS:
		return
	_last_report[peer] = now_ms
	Network.characters.report(account, peer, hp, mp, pos, yaw)


## Só com o servidor em --test (net_test): ouro para os testes de compra.
@rpc("any_peer", "call_remote", "reliable")
func _grant_test_gold(seq: int, amount: int) -> void:
	var account := _sender_account()
	if account <= 0:
		_reply_no_session(seq)
		return
	var r := Network.characters.grant_test_gold(account, amount, _test_server)
	_econ_res.rpc_id(multiplayer.get_remote_sender_id(), seq, r.ok, r.err, events_of(r), r.state)


# ================================================================ cliente
@rpc("authority", "call_remote", "reliable")
func _balance(tables: Dictionary) -> void:
	Balance.apply(BalanceTables.decode(tables), true)


## seq 0 = estado inicial (na aceitação): aplica tudo, vida/mana/posição inclusive.
@rpc("authority", "call_remote", "reliable")
func _econ_res(seq: int, ok: bool, err: String, events: Array, state: Dictionary) -> void:
	if seq == 0:
		sandbox = false
		Game.apply_state(state, true)
		return
	var req: Dictionary = _pending.get(seq, {"op": "", "args": []})
	_pending.erase(seq)
	_finish(str(req.op), req.args, ok, err, events, state)
