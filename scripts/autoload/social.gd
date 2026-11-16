extends Node
## Social do multiplayer: amigos (guardados no banco do servidor, FriendStore) e sussurros (mensagem privada).
##
## Servidor: recebe os pedidos (adicionar pelo nome, aceitar, recusar/cancelar/desfazer), manda a cada
## jogador a lista dele com quem está online, onde e em que nível, e avisa os amigos quando alguém entra
## ou sai. A lista vai de novo quando algo muda (entrada, saída, troca de zona, pedido) e a cada
## REFRESH segundos (o mapa em que o amigo está muda andando). Sussurro: só para quem está online.
## Cliente: a lista (`friends`), os pedidos e o sussurro. As RPCs moram aqui (não no Network).

## Cliente: a lista de amigos ou de pedidos mudou.
signal changed
## Cliente: sussurro recebido (`incoming`) ou o eco do que eu mandei.
signal whisper(from: String, to: String, text: String, incoming: bool)

const REFRESH := 5.0

## Cliente: [{"id", "name", "state" ("accepted" | "in" | "out"), "online", "peer", "zone", "region", "level",
## "last_login"}], ordenada por nome.
var friends: Array = []
## Cliente: de quem veio o último sussurro (/r responde).
var last_whisper_from := ""

var _store: FriendStore = null
var _dirty := false
var _refresh_t := 0.0
var _online := {}   # servidor: contas online no último envio
var _limit := TokenBuckets.new(6.0, 0.5)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Network.players_changed.connect(func() -> void: _dirty = true)


func _physics_process(delta: float) -> void:
	if not Network.is_server():
		return
	_refresh_t -= delta
	if _dirty or _refresh_t <= 0.0:
		_dirty = false
		_refresh_t = REFRESH
		_server_push_all()


# ================================================================ cliente
func request_add(player_name: String) -> void:
	if Network.is_client() and player_name.strip_edges() != "":
		_social_req.rpc_id(1, "add", player_name.strip_edges(), 0)


func accept(account: int) -> void:
	if Network.is_client():
		_social_req.rpc_id(1, "accept", "", account)


## Recusa um pedido recebido, cancela um enviado ou desfaz a amizade.
func remove(account: int) -> void:
	if Network.is_client():
		_social_req.rpc_id(1, "remove", "", account)


func send_whisper(to_name: String, text: String) -> void:
	var t := Network.clean_chat(text)
	if Network.is_client() and to_name.strip_edges() != "" and t != "":
		_whisper_send.rpc_id(1, to_name.strip_edges(), t)


## Estado da relação com o jogador `player_name` ("accepted", "in", "out" ou "").
func state_of(player_name: String) -> String:
	for f in friends:
		if str(f.name).to_lower() == player_name.to_lower():
			return str(f.state)
	return ""


func online_count() -> int:
	var n := 0
	for f in friends:
		if f.state == "accepted" and f.online:
			n += 1
	return n


func pending_in() -> int:
	return friends.filter(func(f: Dictionary) -> bool: return f.state == "in").size()


func client_reset() -> void:
	friends = []
	last_whisper_from = ""
	changed.emit()


@rpc("authority", "call_remote", "reliable")
func _friends(list: Array) -> void:
	friends = list
	changed.emit()


@rpc("authority", "call_remote", "reliable")
func _social_msg(text: String) -> void:
	Game.notify.emit(text, Color(0.75, 0.85, 1.0))
	Network.chat_received.emit("", text)


@rpc("authority", "call_remote", "reliable")
func _whisper_in(from: String, to: String, text: String, incoming: bool) -> void:
	if incoming:
		last_whisper_from = from
		Sfx.play("click", 0.0)
	whisper.emit(from, to, text, incoming)


# ================================================================ servidor
func _db_store() -> FriendStore:
	if _store == null and Network.db != null:
		_store = FriendStore.new(Network.db)
	return _store


@rpc("any_peer", "call_remote", "reliable")
func _social_req(op: String, text: String, account: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not Network.is_server() or not Network.players.has(id) or _db_store() == null:
		return
	if not _limit.allow(id, Time.get_ticks_msec() / 1000.0):
		_msg(id, "Calma! Espere alguns segundos.")
		return
	var me := Econ.account_of(id)
	if me <= 0:
		return
	var r: Dictionary
	match op:
		"add":
			r = _store.request(me, text.substr(0, 32))
		"accept":
			r = _store.accept(me, account)
		"remove":
			r = _store.remove(me, account)
		_:
			return
	if not r.ok:
		_msg(id, FriendStore.explain(r.err))
		return
	var other := int(r.id)
	var my_name := str(Network.players[id].name)
	var other_peer := _peer_of(other)
	var other_name := _name_of_account(other)
	match op:
		"add":
			if r.get("accepted", false):
				_msg(id, "Agora você e %s são amigos." % other_name)
				_msg(other_peer, "Agora você e %s são amigos." % my_name)
			else:
				_msg(id, "Pedido de amizade enviado para %s." % other_name)
				_msg(other_peer, "%s quer ser seu amigo. Aceite na aba Amigos [O]." % my_name)
		"accept":
			_msg(id, "Agora você e %s são amigos." % other_name)
			_msg(other_peer, "%s aceitou seu pedido de amizade." % my_name)
	print("[server] amigos: %s %s %s" % [my_name, op, other_name])
	_dirty = true


@rpc("any_peer", "call_remote", "reliable")
func _whisper_send(to_name: String, text: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not Network.is_server() or not Network.players.has(id):
		return
	var t := Network.clean_chat(text)
	if t == "" or not Network.chat_allow(id):
		return
	var to := 0
	for pid in Network.players:
		if str(Network.players[pid].name).to_lower() == to_name.to_lower():
			to = pid
	var from := str(Network.players[id].name)
	if to == 0:
		_msg(id, "%s não está online." % to_name)
		return
	if to == id:
		_msg(id, "Você não pode sussurrar para si mesmo.")
		return
	var to_real := str(Network.players[to].name)
	_whisper_in.rpc_id(to, from, to_real, t, true)
	_whisper_in.rpc_id(id, from, to_real, t, false)


## Servidor: manda a cada jogador online a lista dele e avisa os amigos de quem entrou ou saiu.
func _server_push_all() -> void:
	if _db_store() == null:
		return
	var now_online := {}
	for pid in Network.players:
		var acc := Econ.account_of(pid)
		if acc > 0:
			now_online[acc] = pid
	for acc in now_online:
		if not _online.has(acc):
			_tell_friends(acc, "%s está online." % _name_of_account(acc))
	for acc in _online:
		if not now_online.has(acc):
			_tell_friends(acc, "%s saiu do jogo." % _name_of_account(acc))
	_online = now_online
	for acc in now_online:
		var list: Array = []
		for f in _store.list(acc):
			var peer := int(now_online.get(f.id, 0))
			var e: Dictionary = f.duplicate()
			e["online"] = peer != 0
			e["peer"] = peer
			e["zone"] = Network.zone_of(peer) if peer != 0 else ""
			e["region"] = ""
			e["level"] = 0
			if peer != 0 and f.state == "accepted":
				var pos = Network.last_pos.get(peer)
				if pos is Vector3 and e.zone == "world":
					e.region = Regions.display_name(Regions.region_at(pos))
				if Network.characters != null:
					e.level = Network.characters.load_or_create(int(f.id)).level
			list.append(e)
		_friends.rpc_id(int(now_online[acc]), list)


func _tell_friends(acc: int, text: String) -> void:
	for f in _store.friend_ids(acc):
		var peer := _peer_of(f)
		if peer != 0:
			_msg(peer, text)


func _peer_of(account: int) -> int:
	for pid in Network.players:
		if Econ.account_of(pid) == account:
			return pid
	return 0


func _name_of_account(account: int) -> String:
	var peer := _peer_of(account)
	if peer != 0:
		return str(Network.players[peer].name)
	var rows := Network.db.query("SELECT username FROM accounts WHERE id = ?", [account]) if Network.db else []
	return str(rows[0].username) if not rows.is_empty() else "?"


func _msg(peer: int, text: String) -> void:
	if peer != 0 and Network.players.has(peer):
		_social_msg.rpc_id(peer, text)
