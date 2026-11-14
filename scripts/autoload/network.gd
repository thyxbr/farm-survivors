extends Node
## Multiplayer: servidor dedicado (headless) + clientes, via ENet (UDP).
##
## Servidor:  godot --headless --path . -- --server [--port=7777] [--http-port=8080] [--db=user://server.db]
## Cliente:   menu principal → Multiplayer → Entrar (login pela API HTTP; o ENet recebe o token da sessão).
##
## Modelo: o servidor é dono dos inimigos (IA, vida, morte) e do personagem de cada conta (ouro, itens,
## XP, equipamento, missões, horta — no banco, pelo CharacterService; os pedidos passam pelo autoload Econ).
## O cliente é dono do combate (movimento, vida/mana) e envia a posição ~20x/s.
## As RPCs deste autoload ficam como estão (o id de cada uma segue a ordem alfabética e o _register
## precisa do mesmo id para clientes antigos); as RPCs novas moram no Econ.
##
## Desafio da Horda em grupo: quem entra no portal abre uma fila (HORDE_LOBBY_TIME s) e todos os
## outros jogadores recebem o convite. Quem aceita entra junto na mesma arena: o servidor cria um
## survival_mode com role "server" (rodadas, spawn, abates) e cada cliente um com role "client".

signal join_failed(reason: String)
signal players_changed
## Cliente: a fila do Desafio da Horda mudou (convite novo, alguém aceitou, fila fechou).
signal horde_changed
## Cliente: mensagem de chat (nome vazio = aviso do servidor).
signal chat_received(from: String, text: String)

const DEFAULT_PORT := 7777
## Endereço sugerido no menu "Entrar". Troque pelo IP/domínio do seu servidor antes de exportar.
const DEFAULT_ADDRESS := "infra-farm-survivors.yy2dhi.easypanel.host"
const MAX_PLAYERS := 8
const SEND_RATE := 20.0
const CONNECT_TIMEOUT := 8.0
const WORLD_SCENE := "res://scenes/world.tscn"
const PLAYER := preload("res://scripts/player/player.gd")
const ENEMY := preload("res://scripts/enemies/enemy.gd")
const FIREBALL := preload("res://scripts/player/fireball.gd")
const UPG := preload("res://scripts/survival/upgrades.gd")

const STATES := ["idle", "wander", "chase", "return", "attack", "dead"]
const ATTACK_KINDS := ["swing", "lunge", "slam", "shoot", "fuse", "cast"]
const SNAP_STRIDE := 10   # id, x, y, z, yaw, hp, state, attack_timer, attack_kind, flags
## Tempo da fila do Desafio da Horda (cai para HORDE_LOBBY_ALL quando todos já responderam).
const HORDE_LOBBY_TIME := 15.0
const HORDE_LOBBY_ALL := 3.0
## Chat: tamanho máximo da mensagem e limite de mensagens por janela de tempo (anti-spam).
const CHAT_MAX := 120
const CHAT_BURST := 5
const CHAT_WINDOW := 6.0

enum Mode { OFFLINE, SERVER, CLIENT }

var mode := Mode.OFFLINE
var port := DEFAULT_PORT
## peer_id -> {"name": String (nome da conta), "account": int, "admin": bool, "look": Dictionary (espaço -> item),
## "ready": bool, "zone": String}
var players := {}
var my_name := ""
## Cliente: token da sessão (do Auth.login) mandado no _register.
var my_token := ""
## Mensagem mostrada no menu principal depois de uma desconexão.
var last_error := ""
var world: Node = null
var enemies := {}         # net_id -> Enemy (servidor: reais; cliente: réplicas)
var remote_players := {}  # peer_id -> Player (réplica)

## Servidor: banco SQLite, contas e API HTTP de login (abertos em start_server).
var db: Db = null
var accounts: AccountStore = null
var auth_http: AuthHttp = null
## Servidor: personagens das contas (sessão = peer id do ENet).
var characters: CharacterService = null
var http_port := 0
var db_path := ""
var admin_users := PackedStringArray()

var _next_enemy_id := 1
var snapshots_received := 0
var _stats_t := 0.0
var _snapshots_sent := 0
var _snap_t := 0.0
var _connect_t := 0.0
## Segundos entre os saves automáticos do cliente (--autosave=N nos testes).
var autosave_interval := 120.0
var _autosave_t := 120.0
var _pending := {}        # servidor: peer_id -> segundos até expulsar quem não se registrou
var _chat_log := {}       # servidor: peer_id -> [instantes das últimas mensagens]

## Servidor: fila aberta {"leader": id, "members": {id: true}, "declined": {id: true}, "t": s} ou {}.
var _lobby := {}
## Servidor: partida em andamento (survival_mode com role "server").
var horde_run: Node = null
## Servidor: duração da rodada (--horde-round=SEG encurta para os testes).
var horde_round_time := 45.0
## Servidor: tempo máximo para o grupo escolher as cartas de nível (--horde-pick=SEG encurta nos testes).
var horde_pick_time := 20.0
## Força um evento em toda rodada (--horde-event=ID, para testes e screenshots; vale também offline).
var horde_force_event := ""
## Cliente: fila vista pelo servidor {"leader": nome, "members": [ids], "names": [nomes], "declined": [ids]}.
var horde_lobby := {}
## Cliente: segundos até a fila fechar (contado localmente).
var horde_lobby_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	var args := OS.get_cmdline_user_args()
	http_port = int(OS.get_environment("HTTP_PORT")) if OS.get_environment("HTTP_PORT") != "" else 8080
	db_path = OS.get_environment("DB_PATH") if OS.get_environment("DB_PATH") != "" else "user://server.db"
	admin_users = _split_names(OS.get_environment("ADMIN_USERS"))
	for a in args:
		if a.begins_with("--port="):
			port = int(a.substr(7))
		elif a.begins_with("--horde-round="):
			horde_round_time = maxf(3.0, float(a.substr(14)))
		elif a.begins_with("--horde-pick="):
			horde_pick_time = maxf(2.0, float(a.substr(13)))
		elif a.begins_with("--horde-event="):
			horde_force_event = a.substr(14)
		elif a.begins_with("--http-port="):
			http_port = int(a.substr(12))
		elif a.begins_with("--db="):
			db_path = a.substr(5)
		elif a.begins_with("--admins="):
			admin_users = _split_names(a.substr(9))
		elif a.begins_with("--autosave="):
			autosave_interval = maxf(1.0, float(a.substr(11)))
	if "--server" in args:
		start_server.call_deferred()


func is_online() -> bool:
	return mode != Mode.OFFLINE


func is_server() -> bool:
	return mode == Mode.SERVER


func is_client() -> bool:
	return mode == Mode.CLIENT


func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "dev"))


# ================================================================ servidor
## "ana, bob" -> ["ana", "bob"] (sem vazios).
func _split_names(csv: String) -> PackedStringArray:
	var out := PackedStringArray()
	for n in csv.split(","):
		if n.strip_edges() != "":
			out.append(n.strip_edges())
	return out


func start_server() -> void:
	db = Db.open(db_path)
	if db == null:
		printerr("[server] não foi possível abrir o banco em %s" % db_path)
		get_tree().quit(1)
		return
	if http_port < 1 or http_port > 65535:
		printerr("[server] porta HTTP inválida: %d (use 1-65535)" % http_port)
		get_tree().quit(1)
		return
	Migrations.apply(db)
	accounts = AccountStore.new(db, admin_users)
	characters = CharacterService.new(db, Balance.tables)
	for n in accounts.missing_admins():
		var msg := "[server] aviso: admin '%s' ainda não tem conta — crie a conta antes que outro jogador registre esse nome" % n
		print(msg)
		push_warning(msg)
	auth_http = AuthHttp.new()
	auth_http.name = "AuthHttp"
	add_child(auth_http)
	if auth_http.start(http_port, accounts) == OK:
		print("[server] API de login em TCP %d (banco: %s)" % [http_port, db_path])
	else:
		get_tree().quit(1)
		return
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		printerr("[server] não foi possível abrir a porta UDP %d (erro %d)" % [port, err])
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	mode = Mode.SERVER
	Engine.max_fps = 60
	print("[server] Ecos de Valdoria v%s ouvindo em UDP %d (máx. %d jogadores)" % [version(), port, MAX_PLAYERS])
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_peer_connected(id: int) -> void:
	if is_server():
		_pending[id] = 10.0
		_no_throttle(id)


## O ENet derruba pacotes não confiáveis quando acha que a rede oscila (o "throttle").
## Para snapshots pequenos de 20/s isso só atrapalha: mantém o envio sempre em 100%.
func _no_throttle(id: int) -> void:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return
	var pp := enet.get_peer(id)
	if pp:
		pp.throttle_configure(5000, ENetPacketPeer.PACKET_THROTTLE_SCALE, 0)


func _on_peer_disconnected(id: int) -> void:
	_pending.erase(id)
	_chat_log.erase(id)
	if is_server() and players.has(id):
		print("[server] %s saiu (%d online)" % [players[id].name, players.size() - 1])
		_drop_player(id)


## Servidor: tira o jogador do jogo (saiu ou foi substituído por uma conexão nova da mesma conta).
func _drop_player(id: int) -> void:
	var was_city: bool = players[id].get("zone", "") == "city"
	var account := int(players[id].get("account", 0))
	players.erase(id)
	_remove_remote_player(id)
	for pid in _all_peers():
		_player_left.rpc_id(pid, id)
	players_changed.emit()
	_horde_peer_gone(id)
	Lobby.server_peer_gone(id, was_city)
	if characters != null and account > 0:
		# por sessão: a queda tardia de uma conexão velha não descarrega a sessão nova
		characters.unload(account, id)


@rpc("any_peer", "call_remote", "reliable")
## Assinatura estável entre versões: (token, versão, visual, extra). O 1º argumento já foi o nome digitado
## (também texto); os dois últimos ficam sem tipo para que um cliente de versão antiga (que mandava arma e
## armadura como texto) ainda chegue à checagem de versão e receba a mensagem "atualize o jogo" em vez de
## um erro de RPC. Não mude a quantidade de argumentos.
func _register(token: String, client_version: String, _look = {}, _extra = "") -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		return
	_pending.erase(id)
	if client_version != version():
		print("[server] recusado peer %d: versão %s (servidor %s)" % [id, client_version, version()])
		_rejected.rpc_id(id, "Versão diferente do servidor (sua: %s, servidor: %s). Atualize o jogo." % [client_version, version()])
		_kick_later(id)
		return
	var acc: Dictionary = accounts.resolve_token(token) if accounts != null else {}
	if acc.is_empty():
		print("[server] recusado peer %d: token inválido ou expirado" % id)
		_rejected.rpc_id(id, "Sessão expirada. Entre de novo.")
		_kick_later(id)
		return
	var account := int(acc.id)
	# uma sessão por conta: a conexão antiga cai antes de aceitar a nova
	for old in players.keys():
		if int(players[old].get("account", 0)) == account:
			print("[server] %s entrou de novo (peer %d): derrubando o peer %d" % [acc.name, id, old])
			_drop_player(old)
			_rejected.rpc_id(old, "Sua conta entrou no jogo em outro lugar. Esta conexão foi encerrada.")
			_kick_later(old)
	characters.set_session(account, id)
	# o visual vem do personagem guardado no servidor (o `look` do cliente fica só pela assinatura estável)
	var char_look: Dictionary = characters.load_or_create(account).equipment
	# todo jogador começa no salão (lobby); "ready" = já carregou a cena da zona em que está
	players[id] = {"name": str(acc.name), "account": account, "admin": bool(acc.get("is_admin", false)),
		"look": _clean_look(char_look), "ready": false, "zone": "lobby"}
	print("[server] %s entrou (peer %d, conta %d, %d online)" % [acc.name, id, account, players.size()])
	# tabelas e personagem antes do _accepted (mesmo canal confiável: chegam antes da troca de cena)
	Econ.server_send_initial(id, account)
	_accepted.rpc_id(id, players)
	for pid in _all_peers():
		if pid != id:
			_player_joined.rpc_id(pid, id, players[id])
	players_changed.emit()


## O cliente terminou de carregar Valdoria (o mundo do RPG).
@rpc("any_peer", "call_remote", "reliable")
func _client_ready() -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_server() or not players.has(id):
		return
	server_set_zone(id, "world")
	# quem entrou enquanto este jogador carregava o mapa não foi anunciado para ele: manda todos agora
	for pid in players:
		if pid != id:
			_player_joined.rpc_id(id, pid, players[pid])
	send_zone_enemies(id, "world")
	if not _lobby.is_empty():
		_horde_lobby.rpc_id(id, _lobby_state())


# ---------------------------------------------------------------- zonas (salão, Valdoria, cidade)
## Servidor: o jogador mudou de zona ("lobby", "world" ou "city"). Sai da anterior e avisa todos.
func server_set_zone(id: int, zone: String) -> void:
	if not players.has(id):
		return
	var old: String = players[id].get("zone", "lobby")
	_remove_remote_player(id)
	players[id].zone = zone
	players[id].ready = true
	if old != zone:
		print("[server] %s: %s -> %s" % [players[id].name, old, zone])
		if old == "world":
			_horde_peer_gone(id)
		if old == "city":
			Lobby.server_city_left(id)
	for pid in _all_peers():
		_player_zone.rpc_id(pid, id, zone)
	players_changed.emit()


func zone_of(id: int) -> String:
	return str(players[id].get("zone", "lobby")) if players.has(id) else ""


## Servidor: jogadores conectados que já carregaram a zona.
func zone_peers(zone: String) -> Array:
	var out := []
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	for pid in players:
		if not players[pid].ready or players[pid].get("zone", "lobby") != zone:
			continue
		var pp := enet.get_peer(pid) if enet else null
		if pp == null or pp.get_state() == ENetPacketPeer.STATE_CONNECTED:
			out.append(pid)
	return out


## Servidor: todos os jogadores registrados (qualquer zona).
func _all_peers() -> Array:
	var out := []
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	for pid in players:
		var pp := enet.get_peer(pid) if enet else null
		if pp == null or pp.get_state() == ENetPacketPeer.STATE_CONNECTED:
			out.append(pid)
	return out


## Servidor: manda ao jogador os inimigos vivos de uma zona.
func send_zone_enemies(id: int, zone: String) -> void:
	for net_id in enemies:
		var e: Enemy = enemies[net_id]
		if is_instance_valid(e) and not e.dead and e.net_zone == zone:
			_enemy_spawned.rpc_id(id, net_id, e.kind, e.global_position, e.model.rotation.y, e.max_hp, e.hp, _enemy_flags(e))


@rpc("authority", "call_remote", "reliable")
func _player_zone(id: int, zone: String) -> void:
	if players.has(id):
		players[id].zone = zone
	var me := multiplayer.get_unique_id()
	if id != me and zone != zone_of(me):
		_remove_remote_player(id)
	players_changed.emit()


func _kick_later(id: int) -> void:
	await get_tree().create_timer(0.5).timeout
	# o cliente recusado costuma sair sozinho antes disso
	if multiplayer.multiplayer_peer and is_server() and id in multiplayer.get_peers():
		multiplayer.multiplayer_peer.disconnect_peer(id)


## Servidor: jogadores em Valdoria (o mundo do RPG) que já carregaram o mapa.
func _ready_peers() -> Array:
	var out := []
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	for pid in players:
		if not players[pid].ready or players[pid].get("zone", "lobby") != "world":
			continue
		# quem está desconectando ainda aparece na lista por alguns quadros
		var pp := enet.get_peer(pid) if enet else null
		if pp == null or pp.get_state() == ENetPacketPeer.STATE_CONNECTED:
			out.append(pid)
	return out


func _physics_process(delta: float) -> void:
	if is_server():
		for id in _pending.keys():
			_pending[id] -= delta
			if _pending[id] <= 0:
				_pending.erase(id)
				multiplayer.multiplayer_peer.disconnect_peer(id)
		_stats_t += delta
		if _stats_t >= (5.0 if "--netstats" in OS.get_cmdline_user_args() else 300.0):
			print("[server] %d online, %d inimigos, %d fps, %d snapshots/s" % [players.size(), enemies.size(),
				Engine.get_frames_per_second(), int(_snapshots_sent / _stats_t)])
			_stats_t = 0.0
			_snapshots_sent = 0
		_snap_t -= delta
		if _snap_t <= 0.001:
			_snap_t = maxf(_snap_t + 1.0 / SEND_RATE, 0.0)
			_send_enemy_snapshot()
		if not _lobby.is_empty():
			_lobby.t -= delta
			if _lobby.t <= 0.0:
				_horde_launch()
	elif mode == Mode.CLIENT:
		if not horde_lobby.is_empty():
			horde_lobby_t = maxf(0.0, horde_lobby_t - delta)
		# vida, mana e posição vão ao servidor de tempos em tempos (o resto ele grava a cada pedido)
		if world != null and _connect_t <= 0:
			_autosave_t -= delta
			if _autosave_t <= 0.0:
				_autosave_t = autosave_interval
				if not Game.run_mods.get("active", false):
					autosave()
		if _connect_t > 0:
			_connect_t -= delta
			if _connect_t <= 0:
				_fail("O servidor não respondeu. Confira o endereço e se a porta UDP está liberada.")


# ---------------------------------------------------------------- inimigos (servidor)
func server_register_enemy(e: Enemy) -> void:
	e.net_id = _next_enemy_id
	_next_enemy_id += 1
	e.net_zone = "city" if Lobby.is_city_node(e) else "world"
	enemies[e.net_id] = e
	for pid in _enemy_peers(e):
		_enemy_spawned.rpc_id(pid, e.net_id, e.kind, e.global_position, e.model.rotation.y, e.max_hp, e.hp, _enemy_flags(e))


## Bits do spawn: 1 = horda, 2 = elite da horda.
static func _enemy_flags(e: Enemy) -> int:
	return (1 if e.horde else 0) | (2 if e.elite else 0)


## Quem vê este inimigo: Valdoria ou a cidade em grupo.
func _enemy_peers(e: Enemy) -> Array:
	return zone_peers("city") if e.net_zone == "city" else _ready_peers()


func unregister_enemy(e: Enemy) -> void:
	if enemies.get(e.net_id) == e:
		enemies.erase(e.net_id)


func server_enemy_killed(e: Enemy) -> void:
	var pos := e.global_position
	if e.net_zone == "city":
		# cidade em grupo: o ouro vai para o cofre e quem acertou ganha XP (sem loot no chão)
		Lobby.server_city_kill(e)
	elif not e.horde:
		# a horda não dá XP/loot do RPG: as gemas vêm pelo _horde_kill do modo sobrevivência
		for pid in e.contributors:
			if players.has(pid):
				_kill_reward.rpc_id(pid, e.kind, int(e.data.xp), pos)
	for pid in _enemy_peers(e):
		_enemy_died.rpc_id(pid, e.net_id)


func _send_enemy_snapshot() -> void:
	if enemies.is_empty():
		return
	# PackedFloat32Array é copiado por valor: um array local por zona
	var snap_world := PackedFloat32Array()
	var snap_city := PackedFloat32Array()
	for net_id in enemies:
		var e: Enemy = enemies[net_id]
		if not is_instance_valid(e) or e.dead:
			continue
		var p := e.global_position
		var flags := (1 if e.slow_timer > 0 else 0) | (2 if e.enraged else 0)
		var row := [net_id, p.x, p.y, p.z, e.model.rotation.y, e.hp,
			max(0, STATES.find(e.state)), e.attack_timer, max(0, ATTACK_KINDS.find(e.attack_kind)), flags]
		if e.net_zone == "city":
			snap_city.append_array(row)
		else:
			snap_world.append_array(row)
	for zone in ["world", "city"]:
		var snap: PackedFloat32Array = snap_world if zone == "world" else snap_city
		if snap.is_empty():
			continue
		var peers := _ready_peers() if zone == "world" else zone_peers(zone)
		if peers.is_empty():
			continue
		_snapshots_sent += 1
		for pid in peers:
			_enemy_snapshot.rpc_id(pid, snap)


@rpc("any_peer", "call_remote", "reliable")
func _hit_enemy(net_id: int, amount: float, from_pos: Vector3, crit: bool, slow: float) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_server() or not players.has(id):
		return
	var e: Enemy = enemies.get(net_id)
	if e == null or not is_instance_valid(e) or e.dead or e.net_zone != zone_of(id):
		return
	amount = clampf(amount, 0.0, 5000.0)
	if amount > 0.0:
		for pid in _enemy_peers(e):
			_enemy_hit_fx.rpc_id(pid, net_id, amount, crit)
		e.last_hitter = id
		e.take_damage(amount, from_pos, crit)
		e.last_hitter = 0
	if slow > 0.0 and not e.dead:
		e.apply_slow(minf(slow, 10.0))


@rpc("any_peer", "call_remote", "reliable")
func _request_boss() -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_server() and players.has(id) and world and world.has_method("server_spawn_boss"):
		world.server_spawn_boss()


# ---------------------------------------------------------------- jogadores (servidor)
func server_damage_player(peer_id: int, amount: float, from_pos: Vector3) -> void:
	if players.has(peer_id):
		_you_were_hit.rpc_id(peer_id, amount, from_pos)


func server_shake_player(peer_id: int, amount: float) -> void:
	if players.has(peer_id):
		_shake.rpc_id(peer_id, amount)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _player_state(pos: Vector3, yaw: float, vel: Vector3, flags: int, combo: int, attack_t: float) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_server() or not players.has(id) or not players[id].ready:
		return
	var zone := zone_of(id)
	if zone == "lobby":
		return
	_apply_remote_state(id, pos, yaw, vel, flags, combo, attack_t)
	for pid in zone_peers(zone):
		if pid != id:
			_player_state_relay.rpc_id(pid, id, pos, yaw, vel, flags, combo, attack_t)


@rpc("any_peer", "call_remote", "reliable")
func _player_look(look: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_server() or not players.has(id):
		return
	players[id].look = _clean_look(look)
	_apply_remote_look(id)
	for pid in _all_peers():
		if pid != id:
			_player_look_relay.rpc_id(pid, id, players[id].look)


## Só espaços e itens conhecidos (o dicionário vem do cliente).
func _clean_look(look: Dictionary) -> Dictionary:
	var out := {}
	for s in ItemDB.SLOTS:
		var v := str(look.get(s, ""))
		out[s] = v if ItemDB.ITEMS.has(v) else ""
	return out


@rpc("any_peer", "call_remote", "reliable")
func _player_event(kind: String, a: Vector3, b: Vector3) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_server() or not players.has(id):
		return
	for pid in zone_peers(zone_of(id)):
		if pid != id:
			_player_event_relay.rpc_id(pid, id, kind, a, b)


# ================================================================ cliente
## Conecta em "host" ou "host:porta" com o token da sessão (Auth.login). O personagem (Game) já deve estar carregado.
func join(address: String, token: String) -> void:
	leave()
	var host := address.strip_edges()
	var p := DEFAULT_PORT
	if host.count(":") == 1:
		p = int(host.get_slice(":", 1))
		host = host.get_slice(":", 0)
	if host == "":
		join_failed.emit("Digite o endereço do servidor.")
		return
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(host, p)
	if err != OK:
		join_failed.emit("Não foi possível conectar em %s:%d (erro %d)." % [host, p, err])
		return
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	my_token = token
	my_name = ""
	last_error = ""
	_connect_t = CONNECT_TIMEOUT
	_autosave_t = autosave_interval


func leave() -> void:
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		if enet != null and enet.host != null:
			enet.host.flush()   # o último relatório de vida/posição sai antes de fechar
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.OFFLINE
	players.clear()
	enemies.clear()
	remote_players.clear()
	horde_lobby = {}
	_connect_t = 0.0
	Lobby.client_reset()


func _on_connected_to_server() -> void:
	_no_throttle(1)
	_register.rpc_id(1, my_token, version(), Game.equipment.duplicate(), "")


func _on_connection_failed() -> void:
	_fail("Não foi possível conectar ao servidor.")


func _fail(reason: String) -> void:
	leave()
	join_failed.emit(reason)


func _on_server_disconnected() -> void:
	var in_world := world != null or Lobby.in_session()
	if in_world:
		autosave()
	leave()
	if in_world:
		last_error = "Conexão com o servidor perdida. Seu progresso fica salvo no servidor."
		Game.go_to_menu()


@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String) -> void:
	var why := explain_rejection(reason, version())
	if world != null or Lobby.in_session():
		# já estava jogando (a conta entrou em outro lugar): salva e volta ao menu com o aviso
		autosave()
		leave()
		last_error = why
		join_failed.emit(why)
		Game.go_to_menu()
		return
	_fail(why)


## O texto de recusa vem do servidor, que pode ser o antigo: quando o jogador já atualizou e o servidor
## ainda não (o deploy leva alguns minutos depois da release), "Atualize o jogo" estaria errado.
func explain_rejection(reason: String, mine: String) -> String:
	var m := RegEx.create_from_string("servidor: v?([0-9][0-9.]*)").search(reason)
	if reason.begins_with("Versão diferente") and m \
			and Updater.compare_versions(mine, m.get_string(1)) > 0:
		return "O servidor ainda está na v%s e está sendo atualizado para a v%s. Tente de novo em alguns minutos." \
			% [m.get_string(1), mine]
	return reason


@rpc("authority", "call_remote", "reliable")
func _accepted(all_players: Dictionary) -> void:
	_connect_t = 0.0
	players = all_players
	var me: int = multiplayer.get_unique_id()
	if players.has(me):
		my_name = players[me].name
	get_tree().paused = false
	# todo mundo chega pelo salão (lobby): de lá vai para Valdoria ou para a Defesa da Cidade em grupo
	Lobby.on_accepted()


## Chamado pelo mundo quando terminou de montar a cena.
func world_ready(w: Node) -> void:
	world = w
	if is_client():
		_client_ready.rpc_id(1)


func world_closed(w: Node) -> void:
	if world == w:
		world = null
		enemies.clear()
		remote_players.clear()


## Manda vida, mana e posição ao servidor (o personagem mora lá; os pedidos já foram gravados).
func autosave() -> void:
	# no salão e na cidade em grupo o personagem fica onde estava em Valdoria
	if world == null or world.get("role") != null:
		if is_online():
			Lobby.save_character()
		return
	if world.get("player") == null:
		return
	var p: Player = world.player
	if is_instance_valid(p):
		Econ.report_vitals(p.global_position if not p.dead else Vector3(0, 0.5, 6), p.model.rotation.y)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_client():
		autosave()


# ---------------------------------------------------------------- envio (cliente)
func send_player_state(pos: Vector3, yaw: float, vel: Vector3, flags: int, combo: int, attack_t: float) -> void:
	if is_client() and world:
		_player_state.rpc_id(1, pos, yaw, vel, flags, combo, attack_t)


func send_look(look: Dictionary) -> void:
	if is_client():
		_player_look.rpc_id(1, look)


func send_event(kind: String, a := Vector3.ZERO, b := Vector3.ZERO) -> void:
	if is_client() and world:
		_player_event.rpc_id(1, kind, a, b)


func client_hit_enemy(net_id: int, amount: float, from_pos: Vector3, crit: bool, slow := 0.0) -> void:
	if is_client():
		_hit_enemy.rpc_id(1, net_id, amount, from_pos, crit, slow)


func request_boss() -> void:
	if is_client():
		_request_boss.rpc_id(1)


## Desafio da Horda: build e vida deste jogador (o survival_mode manda a cada segundo).
func horde_send_build(build: Dictionary) -> void:
	if is_client() and multiplayer.multiplayer_peer != null:
		_horde_build.rpc_id(1, build)


## Desafio da Horda: "request" (abrir/entrar na fila), "accept", "decline", "dead", "ready" (bênção
## escolhida) ou "leave" (retirada/abandono).
func horde_send(kind: String) -> void:
	if is_client():
		_horde_msg.rpc_id(1, kind)


func request_horde() -> void:
	horde_send("request")


## XP das gemas coletadas (o nível da horda é do grupo).
func horde_xp(amount: float) -> void:
	if is_client() and amount > 0.0:
		_horde_xp.rpc_id(1, amount)


## Chat: manda uma mensagem para todos os jogadores online.
func send_chat(text: String) -> void:
	var t := _clean_chat(text)
	if is_client() and t != "":
		_chat_send.rpc_id(1, t)


func horde_answer(accept: bool) -> void:
	horde_send("accept" if accept else "decline")
	# resposta otimista: o painel atualiza na hora; o servidor confirma em seguida
	if not horde_lobby.is_empty():
		var me := multiplayer.get_unique_id()
		var members: Array = horde_lobby.get("members", []).filter(func(x) -> bool: return x != me)
		var declined: Array = horde_lobby.get("declined", []).filter(func(x) -> bool: return x != me)
		if accept:
			members.append(me)
		else:
			declined.append(me)
		horde_lobby.members = members
		horde_lobby.declined = declined
		horde_changed.emit()


## Cliente: estou na fila?
func in_horde_lobby() -> bool:
	return multiplayer.get_unique_id() in horde_lobby.get("members", [])


## Cliente: recebi um convite que ainda não respondi?
func horde_invite_pending() -> bool:
	if horde_lobby.is_empty():
		return false
	var me := multiplayer.get_unique_id()
	return not (me in horde_lobby.get("members", [])) and not (me in horde_lobby.get("declined", []))


# ---------------------------------------------------------------- recebimento (cliente)
@rpc("authority", "call_remote", "reliable")
func _player_joined(id: int, info: Dictionary) -> void:
	var known := players.has(id)
	players[id] = info
	if not known:
		Game.notify.emit("%s chegou ao servidor." % info.name, Color(0.6, 0.9, 1.0))
		chat_received.emit("", "%s chegou ao servidor." % info.name)
	# a réplica pode ter sido criada antes (pelo estado) sem nome nem visual
	var rp: Player = remote_players.get(id)
	if rp and is_instance_valid(rp):
		rp.set_display_name(info.name)
	_apply_remote_look(id)
	players_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _player_left(id: int) -> void:
	if players.has(id):
		Game.notify.emit("%s saiu." % players[id].name, Color(0.7, 0.75, 0.85))
		chat_received.emit("", "%s saiu." % players[id].name)
	players.erase(id)
	_remove_remote_player(id)
	players_changed.emit()


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _player_state_relay(id: int, pos: Vector3, yaw: float, vel: Vector3, flags: int, combo: int, attack_t: float) -> void:
	_apply_remote_state(id, pos, yaw, vel, flags, combo, attack_t)


@rpc("authority", "call_remote", "reliable")
func _player_look_relay(id: int, look: Dictionary) -> void:
	if players.has(id):
		players[id].look = look
	_apply_remote_look(id)


@rpc("authority", "call_remote", "reliable")
func _player_event_relay(id: int, kind: String, a: Vector3, b: Vector3) -> void:
	var rp: Player = remote_players.get(id)
	if rp == null or not is_instance_valid(rp):
		return
	rp.play_remote_event(kind, a, b)


@rpc("authority", "call_remote", "reliable")
func _you_were_hit(amount: float, from_pos: Vector3) -> void:
	if world and world.player:
		world.player.take_damage(amount, from_pos)


@rpc("authority", "call_remote", "unreliable")
func _shake(amount: float) -> void:
	if world and world.player:
		world.player.add_shake(amount)


@rpc("authority", "call_remote", "reliable")
func _enemy_spawned(net_id: int, kind: String, pos: Vector3, yaw: float, max_hp: float, hp: float, flags: int) -> void:
	if world == null or enemies.has(net_id):
		return
	var horde := flags & 1 != 0
	var e := ENEMY.new()
	e.kind = kind
	e.puppet = true
	e.horde = horde
	e.elite = flags & 2 != 0
	e.net_id = net_id
	e.position = pos
	# na cidade os monstros ficam dentro da Colony (as torres e o HUD contam por lá)
	var parent: Node = world.enemy_parent() if world.has_method("enemy_parent") else world
	parent.add_child(e)
	e.max_hp = max_hp
	e.hp = hp
	e.model.rotation.y = yaw
	e.set_net_target(pos, yaw)
	enemies[net_id] = e
	if e.is_boss:
		if horde:
			# chefe da horda: só importa para quem está no desafio
			var sv := _horde_survival()
			if sv != null:
				sv.boss = e
				if world.get("hud"):
					world.hud.boss = e
			return
		world.boss = e
		if world.get("hud"):
			world.hud.boss = e


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _enemy_snapshot(snap: PackedFloat32Array) -> void:
	snapshots_received += 1
	var i := 0
	while i + SNAP_STRIDE <= snap.size():
		var e: Enemy = enemies.get(int(snap[i]))
		if e and is_instance_valid(e) and not e.dead:
			e.apply_snapshot(Vector3(snap[i + 1], snap[i + 2], snap[i + 3]), snap[i + 4], snap[i + 5],
				STATES[int(snap[i + 6])], snap[i + 7], ATTACK_KINDS[int(snap[i + 8])], int(snap[i + 9]))
		i += SNAP_STRIDE


@rpc("authority", "call_remote", "reliable")
func _enemy_hit_fx(net_id: int, amount: float, crit: bool) -> void:
	var e: Enemy = enemies.get(net_id)
	if e and is_instance_valid(e):
		e.show_hit(amount, crit)


@rpc("authority", "call_remote", "reliable")
func _enemy_died(net_id: int) -> void:
	var e: Enemy = enemies.get(net_id)
	enemies.erase(net_id)
	if e and is_instance_valid(e) and not e.dead:
		e.die_visual()


@rpc("authority", "call_remote", "reliable")
func _kill_reward(kind: String, xp: int, pos: Vector3) -> void:
	# Task 9: XP e loot passam a ser concedidos pelo servidor; até lá o Econ recusa no cliente (push_error)
	Game.on_enemy_killed(kind, xp)
	if world:
		ENEMY.drop_loot(world, kind, pos)


# ---------------------------------------------------------------- réplicas de jogadores
func _apply_remote_state(id: int, pos: Vector3, yaw: float, vel: Vector3, flags: int, combo: int, attack_t: float) -> void:
	# servidor: a réplica fica na zona do jogador (Valdoria ou a cidade); cliente: só quem está na mesma zona
	var parent: Node = world
	if is_server():
		parent = Lobby.server_city_root() if zone_of(id) == "city" else world
	elif zone_of(id) != zone_of(multiplayer.get_unique_id()):
		return
	if parent == null:
		return
	var rp: Player = remote_players.get(id)
	if rp == null or not is_instance_valid(rp):
		rp = PLAYER.new()
		rp.remote = true
		rp.peer_id = id
		rp.display_name = players[id].name if players.has(id) else "?"
		rp.position = pos
		parent.add_child(rp)
		remote_players[id] = rp
		if is_server() and zone_of(id) == "city":
			rp.add_to_group("colony_units")   # os monstros do cerco atacam quem está na cidade
		_apply_remote_look(id)
	rp.apply_net_state(pos, yaw, vel, flags, combo, attack_t)


func _apply_remote_look(id: int) -> void:
	var rp: Player = remote_players.get(id)
	if rp and is_instance_valid(rp) and players.has(id):
		rp.apply_look(players[id].get("look", {}))


func _remove_remote_player(id: int) -> void:
	var rp: Player = remote_players.get(id)
	remote_players.erase(id)
	if rp and is_instance_valid(rp):
		rp.queue_free()


# ================================================================ Desafio da Horda em grupo
# ---------------------------------------------------------------- servidor
@rpc("any_peer", "call_remote", "reliable")
func _horde_msg(kind: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_server() or not players.has(id) or not players[id].ready:
		return
	var run: Node = horde_run if horde_run != null and is_instance_valid(horde_run) else null
	match kind:
		"request":
			_server_horde_request(id)
		"accept", "decline":
			_server_horde_answer(id, kind == "accept")
		"dead":
			if run:
				run.server_player_dead(id)
		"ready":
			if run:
				run.server_player_ready(id)
		"lv_ready":
			if run:
				run.server_player_lv_ready(id)
		"leave":
			if run:
				run.server_player_left(id)


@rpc("any_peer", "call_remote", "reliable")
func _horde_xp(amount: float) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_server() or not players.has(id):
		return
	if horde_run != null and is_instance_valid(horde_run):
		horde_run.server_add_xp(id, amount)


## Cliente → servidor: build e vida do jogador na horda (placar do Tab e combos do grupo).
@rpc("any_peer", "call_remote", "reliable")
func _horde_build(build: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_server() or not players.has(id):
		return
	if horde_run != null and is_instance_valid(horde_run):
		horde_run.server_player_build(id, _clean_build(build))


## Só armas, passivas e bênçãos conhecidas, com números nos limites (o dicionário vem do cliente).
static func _clean_build(b: Dictionary) -> Dictionary:
	var out := {"lv": clampi(int(b.get("lv", 1)), 1, 999), "hp": clampf(float(b.get("hp", 0.0)), 0.0, 1.0),
		"c": clampi(int(b.get("c", 0)), 0, 1000000), "w": {}, "p": {}, "b": {}}
	for key in [["w", UPG.WEAPONS, UPG.MAX_LEVEL], ["p", UPG.PASSIVES, UPG.MAX_LEVEL], ["b", UPG.BLESSINGS, 99]]:
		var src = b.get(key[0], {})
		if not (src is Dictionary):
			continue
		for id in src:
			if key[1].has(str(id)):
				out[key[0]][str(id)] = clampi(int(src[id]), 0, key[2])
	return out


func _server_horde_request(id: int) -> void:
	if horde_run != null and is_instance_valid(horde_run):
		var names: Array[String] = []
		for pid in horde_run.team:
			names.append(str(horde_run.team[pid].name))
		_horde_notice.rpc_id(id, "Já há um Desafio da Horda em andamento (%s). Aguarde terminar." % ", ".join(names))
		return
	if not _lobby.is_empty():
		_server_horde_answer(id, true)   # já existe fila: entra nela
		return
	_lobby = {"leader": id, "members": {id: true}, "declined": {}, "t": HORDE_LOBBY_TIME}
	print("[server] %s abriu o Desafio da Horda" % players[id].name)
	_lobby_check_answered()
	_broadcast_lobby()


func _server_horde_answer(id: int, accept: bool) -> void:
	if _lobby.is_empty():
		if accept and players.has(id):
			_horde_notice.rpc_id(id, "O convite já expirou.")
		return
	if accept:
		_lobby.members[id] = true
		_lobby.declined.erase(id)
	else:
		_lobby.members.erase(id)
		_lobby.declined[id] = true
	if _lobby.members.is_empty():
		_lobby = {}
		print("[server] fila do Desafio da Horda cancelada")
	else:
		if not _lobby.members.has(_lobby.leader):
			_lobby.leader = _lobby.members.keys()[0]
		_lobby_check_answered()
	_broadcast_lobby()


## Todos os jogadores online já responderam: começa logo (alguns segundos para se preparar).
func _lobby_check_answered() -> void:
	for pid in _ready_peers():
		if not _lobby.members.has(pid) and not _lobby.declined.has(pid):
			return
	_lobby.t = minf(_lobby.t, HORDE_LOBBY_ALL)


func _lobby_state() -> Dictionary:
	if _lobby.is_empty():
		return {}
	var names: Array[String] = []
	for pid in _lobby.members:
		if players.has(pid):
			names.append(str(players[pid].name))
	return {"leader": str(players[_lobby.leader].name) if players.has(_lobby.leader) else "?",
		"members": _lobby.members.keys(), "names": names, "declined": _lobby.declined.keys(), "t": _lobby.t}


func _broadcast_lobby() -> void:
	var st := _lobby_state()
	for pid in _ready_peers():
		_horde_lobby.rpc_id(pid, st)


func _horde_launch() -> void:
	var team := {}
	for pid in _lobby.members:
		if not players.has(pid) or not players[pid].ready:
			continue
		var rp: Player = remote_players.get(pid)
		if rp and is_instance_valid(rp) and rp.dead:
			_horde_notice.rpc_id(pid, "Você estava caído e ficou fora do Desafio da Horda.")
			continue
		team[pid] = {"name": players[pid].name, "dead": false, "ready": false, "lv_ready": true}
	_lobby = {}
	_broadcast_lobby()
	if team.is_empty() or world == null or not world.has_method("server_start_horde"):
		return
	# os clientes montam a partida antes da rodada 1 chegar (RPCs confiáveis chegam em ordem)
	var slot := 0
	for pid in team:
		_horde_start.rpc_id(pid, team, slot, horde_round_time)
		slot += 1
	horde_run = world.server_start_horde(team, horde_round_time)


func horde_run_ended(run: Node) -> void:
	if horde_run == run:
		horde_run = null


## Servidor: manda uma RPC da horda para um jogador (usado pelo survival_mode do servidor).
func horde_rpc(pid: int, method: String, args: Array) -> void:
	if players.has(pid):
		callv("rpc_id", [pid, method] + args)


func _horde_peer_gone(id: int) -> void:
	if not _lobby.is_empty():
		var was_member: bool = _lobby.members.has(id)
		_lobby.declined.erase(id)
		if was_member:
			_server_horde_answer(id, false)
			if not _lobby.is_empty():
				_lobby.declined.erase(id)
		else:
			_lobby_check_answered()
			_broadcast_lobby()
	if horde_run != null and is_instance_valid(horde_run):
		horde_run.server_player_left(id)


# ---------------------------------------------------------------- cliente
func _horde_survival() -> Node:
	if world == null:
		return null
	var sv = world.get("survival")
	return sv if sv != null and sv.get("role") == "client" else null


@rpc("authority", "call_remote", "reliable")
func _horde_lobby(state: Dictionary) -> void:
	var was_open := not horde_lobby.is_empty()
	horde_lobby = state
	horde_lobby_t = float(state.get("t", 0.0))
	if not was_open and not state.is_empty() and horde_invite_pending() and _horde_survival() == null:
		Game.notify.emit("%s abriu o Portal do Desafio! [Y] entrar · [N] recusar" % state.leader, Color(0.85, 0.6, 1.0))
		Sfx.play("quest", 0.0)
	horde_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _horde_start(team: Dictionary, slot: int, round_time: float) -> void:
	horde_lobby = {}
	horde_changed.emit()
	if world and world.has_method("start_survival_net"):
		world.start_survival_net(team, slot, round_time)


@rpc("authority", "call_remote", "reliable")
func _horde_round_start(n: int, t: float, event: String, hunt: int) -> void:
	var sv := _horde_survival()
	if sv:
		sv.net_round_start(n, t, event, hunt)


@rpc("authority", "call_remote", "reliable")
func _horde_round_end(n: int, break_t: float) -> void:
	var sv := _horde_survival()
	if sv:
		sv.net_round_end(n, break_t)


@rpc("authority", "call_remote", "reliable")
func _horde_levelup(level: int, xp: float, picks: int, timeout: float) -> void:
	var sv := _horde_survival()
	if sv:
		sv.net_levelup(level, xp, clampi(picks, 1, 20), timeout)


@rpc("authority", "call_remote", "reliable")
func _horde_resume(level: int, xp: float) -> void:
	var sv := _horde_survival()
	if sv:
		sv.net_resume(level, xp)


@rpc("authority", "call_remote", "reliable")
func _horde_state(level: int, xp: float) -> void:
	var sv := _horde_survival()
	if sv:
		sv.net_state(level, xp)


@rpc("authority", "call_remote", "reliable")
func _horde_fx(kind: String, pos: Vector3) -> void:
	var sv := _horde_survival()
	if sv:
		sv.net_fx(kind, pos)


@rpc("authority", "call_remote", "reliable")
func _horde_bonus(kind: String) -> void:
	var sv := _horde_survival()
	if sv:
		sv.net_bonus(kind)


@rpc("authority", "call_remote", "reliable")
func _horde_kill(kind: String, pos: Vector3, tier: int) -> void:
	var sv := _horde_survival()
	if sv and ENEMY.TYPES.has(kind):
		sv.net_kill(kind, pos, clampi(tier, 0, 2))


@rpc("authority", "call_remote", "reliable")
func _horde_team(team: Dictionary) -> void:
	var sv := _horde_survival()
	if sv:
		sv.net_team(team)


@rpc("authority", "call_remote", "reliable")
func _horde_over(reason: String) -> void:
	var sv := _horde_survival()
	if sv:
		sv.end_run(reason, true)


@rpc("authority", "call_remote", "reliable")
func _horde_notice(text: String) -> void:
	Game.notify.emit(text, Color(1, 0.7, 0.5))


# ================================================================ chat
func _clean_chat(text: String) -> String:
	var t := ""
	for ch in text.strip_edges():
		# sem quebras de linha nem caracteres de controle
		t += " " if ch.unicode_at(0) < 32 else ch
	return t.strip_edges().substr(0, CHAT_MAX)


@rpc("any_peer", "call_remote", "reliable")
func _chat_send(text: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_server() or not players.has(id) or not players[id].ready:
		return
	var t := _clean_chat(text)
	if t == "":
		return
	var now := Time.get_ticks_msec() / 1000.0
	var recent: Array = _chat_log.get(id, []).filter(func(x: float) -> bool: return now - x < CHAT_WINDOW)
	if recent.size() >= CHAT_BURST:
		_chat_msg.rpc_id(id, "", "Calma! Espere alguns segundos para mandar outra mensagem.")
		return
	recent.append(now)
	_chat_log[id] = recent
	var from: String = players[id].name
	print("[chat] %s: %s" % [from, t])
	# o chat é do servidor inteiro: salão, Valdoria e a cidade em grupo
	for pid in _all_peers():
		if players[pid].ready:
			_chat_msg.rpc_id(pid, from, t)


@rpc("authority", "call_remote", "reliable")
func _chat_msg(from: String, text: String) -> void:
	chat_received.emit(from, text)
