extends Node
## Grupo do multiplayer (até PartyBook.MAX_MEMBERS jogadores).
##
## Servidor: guarda os grupos (PartyBook), recebe os pedidos (convidar, aceitar, recusar, sair, expulsar),
## a vida de cada membro, e manda a cada jogador o estado do grupo dele. No abate, Network usa
## `server_kill_rewards` (PartyRules): o XP do monstro é dividido entre o grupo em Valdoria e o abate conta
## na missão de quem está perto do combate.
## Cliente: o estado do grupo (`members`), o convite recebido (`invite`) e os pedidos.
## As RPCs moram aqui (e não no Network, cujos ids de RPC seguem a ordem alfabética).

## Cliente: o grupo mudou (entrou, saiu, vida, nível, zona).
signal changed
## Cliente: chegou ou sumiu um convite.
signal invite_changed

## Segundos entre os envios de vida (cliente) e de estado do grupo (servidor).
const PULSE := 1.0

var book := PartyBook.new()
## Servidor: peer -> fração de vida (0..1) informada pelo cliente.
var _hp := {}
var _pulse_t := 0.0

## Cliente: membros do grupo [{"peer", "name", "level", "hp", "zone", "leader": bool}] ([] = sem grupo).
var members: Array = []
## Cliente: convite esperando resposta {"from": peer, "name": nome} ou {}.
var invite := {}
var _sent_hp := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _physics_process(delta: float) -> void:
	_pulse_t -= delta
	if _pulse_t > 0.0:
		return
	_pulse_t = PULSE
	if Network.is_server():
		for to in book.tick(PULSE):
			_server_msg(to, "O convite para o grupo expirou.")
		if not book.party_of.is_empty():
			_push_all()
	elif Network.is_client() and in_party():
		_client_send_hp()


# ================================================================ cliente
func in_party() -> bool:
	return not members.is_empty()


## Peers do meu grupo, sem contar eu.
func others() -> Array:
	var me := multiplayer.get_unique_id()
	var out: Array = []
	for m in members:
		if int(m.peer) != me:
			out.append(int(m.peer))
	return out


func is_member(peer: int) -> bool:
	for m in members:
		if int(m.peer) == peer:
			return true
	return false


func am_leader() -> bool:
	var me := multiplayer.get_unique_id()
	for m in members:
		if int(m.peer) == me:
			return bool(m.leader)
	return false


func request_invite(peer: int) -> void:
	_send("invite", peer, "")


## Convida pelo nome da conta (comando do chat).
func request_invite_name(player_name: String) -> void:
	_send("invite_name", 0, player_name)


func answer_invite(accept: bool) -> void:
	if invite.is_empty():
		return
	_send("accept" if accept else "decline", 0, "")
	invite = {}
	invite_changed.emit()


func request_leave() -> void:
	_send("leave", 0, "")


func request_kick(peer: int) -> void:
	_send("kick", peer, "")


func client_reset() -> void:
	members = []
	invite = {}
	_sent_hp = -1.0
	changed.emit()
	invite_changed.emit()


func _send(op: String, peer: int, text: String) -> void:
	if Network.is_client():
		_party_req.rpc_id(1, op, peer, text)


func _client_send_hp() -> void:
	var w = Network.world
	if w == null or w.get("player") == null or not is_instance_valid(w.player):
		return
	var frac := clampf(Game.hp / maxf(1.0, Game.max_hp()), 0.0, 1.0)
	if w.player.dead:
		frac = 0.0
	if absf(frac - _sent_hp) < 0.01:
		return
	_sent_hp = frac
	_party_hp.rpc_id(1, frac)


@rpc("authority", "call_remote", "reliable")
func _party_state(list: Array) -> void:
	var had := in_party()
	members = list
	if had and not in_party():
		Game.notify.emit("Você saiu do grupo.", Color(0.75, 0.8, 0.9))
	_sent_hp = -1.0
	changed.emit()


@rpc("authority", "call_remote", "reliable")
func _party_invite(from: int, from_name: String) -> void:
	invite = {"from": from, "name": from_name} if from != 0 else {}
	if from != 0:
		Game.notify.emit("%s convidou você para o grupo. [Y] aceitar · [N] recusar" % from_name, Color(0.6, 0.95, 0.7))
		Sfx.play("pickup", -4.0)
	invite_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _party_msg(text: String) -> void:
	Game.notify.emit(text, Color(0.6, 0.95, 0.7))
	Network.chat_received.emit("", text)


# ================================================================ servidor
@rpc("any_peer", "call_remote", "reliable")
func _party_req(op: String, peer: int, text: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not Network.is_server() or not Network.players.has(id):
		return
	match op:
		"invite", "invite_name":
			var to := peer if op == "invite" else _peer_by_name(text)
			if not Network.players.has(to):
				_server_msg(id, PartyBook.explain("sem_jogador"))
				return
			var err := book.invite(id, to)
			if err != "":
				_server_msg(id, PartyBook.explain(err))
				return
			_party_invite.rpc_id(to, id, _name(id))
			_server_msg(id, "Convite enviado para %s." % _name(to))
		"accept":
			var from := int(book.invites.get(id, {}).get("from", 0))
			var err := book.accept(id)
			if err != "":
				_server_msg(id, PartyBook.explain(err))
				return
			for m in book.members(id):
				if m != id:
					_server_msg(m, "%s entrou no grupo." % _name(id))
			_server_msg(id, "Você entrou no grupo de %s." % _name(from))
			print("[server] grupo: %s entrou (%s)" % [_name(id), ", ".join(book.members(id).map(_name))])
			_push_all()
		"decline":
			var from := book.decline(id)
			if from != 0 and Network.players.has(from):
				_server_msg(from, "%s recusou o convite." % _name(id))
		"leave":
			_server_leave(id, "%s saiu do grupo.")
		"kick":
			var before := book.members(id)
			var err := book.kick(id, peer)
			if err != "":
				_server_msg(id, PartyBook.explain(err))
				return
			_server_msg(peer, "Você foi removido do grupo.")
			for m in before:
				if m != peer and Network.players.has(m):
					_server_msg(m, "%s foi removido do grupo." % _name(peer))
					if not book.in_party(m):
						_party_state.rpc_id(m, [])
			if Network.players.has(peer):
				_party_state.rpc_id(peer, [])
			_push_all()


@rpc("any_peer", "call_remote", "reliable")
func _party_hp(frac: float) -> void:
	var id := multiplayer.get_remote_sender_id()
	if Network.is_server() and Network.players.has(id) and is_finite(frac):
		_hp[id] = clampf(frac, 0.0, 1.0)


func _server_leave(id: int, msg: String) -> void:
	var before := book.members(id)
	if book.leave(id) != "":
		return
	for m in before:
		if m != id and Network.players.has(m):
			_server_msg(m, msg % _name(id))
			if not book.in_party(m):
				_party_state.rpc_id(m, [])
	if Network.players.has(id):
		_party_state.rpc_id(id, [])
	_push_all()


## Servidor: o peer saiu do jogo (Network._drop_player).
func server_peer_gone(id: int) -> void:
	_hp.erase(id)
	if book.in_party(id):
		var before := book.members(id)
		book.drop(id)
		for m in before:
			if m != id and Network.players.has(m):
				_server_msg(m, "%s saiu do grupo." % _name(id))
				if not book.in_party(m):
					_party_state.rpc_id(m, [])
		_push_all()
	else:
		book.drop(id)


## Servidor: o estado de cada grupo para os membros dele (nome, nível, vida, zona, líder).
func _push_all() -> void:
	var done := {}
	for peer in book.party_of:
		var id := int(book.party_of[peer])
		if done.has(id):
			continue
		done[id] = true
		var list: Array = []
		var lead := book.leader(peer)
		for m in book.members(peer):
			list.append({"peer": m, "name": _name(m), "level": _level(m), "hp": float(_hp.get(m, 1.0)),
				"zone": Network.zone_of(m), "leader": m == lead})
		for m in book.members(peer):
			if Network.players.has(m):
				_party_state.rpc_id(m, list)


## Servidor: recompensas do abate de `e` (PartyRules.kill_rewards) para quem acertou e o grupo dele.
func server_kill_rewards(xp: int, contributors: Array, at: Vector3, zone: String) -> Dictionary:
	var zones := {}
	for pid in Network.players:
		zones[pid] = Network.zone_of(pid)
	return PartyRules.kill_rewards(xp, contributors, book.teams(), Network.last_pos, zones, at, zone)


func _server_msg(peer: int, text: String) -> void:
	if Network.players.has(peer):
		_party_msg.rpc_id(peer, text)


func _peer_by_name(n: String) -> int:
	var want := n.strip_edges().to_lower()
	for pid in Network.players:
		if str(Network.players[pid].name).to_lower() == want:
			return pid
	return 0


func _name(peer: int) -> String:
	return str(Network.players[peer].name) if Network.players.has(peer) else "?"


func _level(peer: int) -> int:
	var account := int(Network.players[peer].get("account", 0)) if Network.players.has(peer) else 0
	if account <= 0 or Network.characters == null:
		return 1
	return Network.characters.load_or_create(account).level
