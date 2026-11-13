extends Node
## Multiplayer: servidor dedicado (headless) + clientes, via ENet (UDP).
##
## Servidor:  godot --headless --path . -- --server [--port=7777]
## Cliente:   menu principal → Multiplayer → Entrar.
##
## Modelo: o servidor é dono dos inimigos (IA, vida, morte). Cada cliente é dono do próprio
## personagem (movimento, atributos, inventário, save local) e envia a posição ~20x/s.
## Todas as RPCs passam por este autoload (/root/Network existe igual em todos os peers).

signal join_failed(reason: String)
signal players_changed

const DEFAULT_PORT := 7777
## Endereço sugerido no menu "Entrar". Troque pelo IP/domínio do seu servidor antes de exportar.
const DEFAULT_ADDRESS := "127.0.0.1"
const MAX_PLAYERS := 8
const SEND_RATE := 20.0
const CONNECT_TIMEOUT := 8.0
const WORLD_SCENE := "res://scenes/world.tscn"
const PLAYER := preload("res://scripts/player/player.gd")
const ENEMY := preload("res://scripts/enemies/enemy.gd")
const FIREBALL := preload("res://scripts/player/fireball.gd")

const STATES := ["idle", "wander", "chase", "return", "attack", "dead"]
const ATTACK_KINDS := ["swing", "lunge", "slam"]
const SNAP_STRIDE := 10   # id, x, y, z, yaw, hp, state, attack_timer, attack_kind, flags

enum Mode { OFFLINE, SERVER, CLIENT }

var mode := Mode.OFFLINE
var port := DEFAULT_PORT
## peer_id -> {"name": String, "weapon": String, "armor": String, "ready": bool}
var players := {}
var my_name := ""
## Mensagem mostrada no menu principal depois de uma desconexão.
var last_error := ""
var world: Node = null
var enemies := {}         # net_id -> Enemy (servidor: reais; cliente: réplicas)
var remote_players := {}  # peer_id -> Player (réplica)

var _next_enemy_id := 1
var snapshots_received := 0
var _stats_t := 0.0
var _snapshots_sent := 0
var _snap_t := 0.0
var _connect_t := 0.0
var _pending := {}        # servidor: peer_id -> segundos até expulsar quem não se registrou


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--port="):
			port = int(a.substr(7))
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
func start_server() -> void:
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
	if is_server() and players.has(id):
		print("[server] %s saiu (%d online)" % [players[id].name, players.size() - 1])
		players.erase(id)
		_remove_remote_player(id)
		for pid in _ready_peers():
			_player_left.rpc_id(pid, id)
		players_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _register(player_name: String, client_version: String, weapon: String, armor: String) -> void:
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
	var name_clean := _clean_name(player_name)
	players[id] = {"name": name_clean, "weapon": weapon, "armor": armor, "ready": false}
	print("[server] %s entrou (peer %d, %d online)" % [name_clean, id, players.size()])
	_accepted.rpc_id(id, players)
	for pid in _ready_peers():
		if pid != id:
			_player_joined.rpc_id(pid, id, players[id])
	players_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _client_ready() -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_server() or not players.has(id):
		return
	players[id].ready = true
	for net_id in enemies:
		var e: Enemy = enemies[net_id]
		if is_instance_valid(e) and not e.dead:
			_enemy_spawned.rpc_id(id, net_id, e.kind, e.global_position, e.model.rotation.y, e.max_hp, e.hp)


func _clean_name(n: String) -> String:
	var s := n.strip_edges().substr(0, 16)
	if s == "":
		s = "Aventureiro"
	var base := s
	var i := 2
	var taken := true
	while taken:
		taken = false
		for pid in players:
			if players[pid].name == s:
				taken = true
				s = "%s %d" % [base, i]
				i += 1
				break
	return s


func _kick_later(id: int) -> void:
	await get_tree().create_timer(0.5).timeout
	if multiplayer.multiplayer_peer and is_server():
		multiplayer.multiplayer_peer.disconnect_peer(id)


func _ready_peers() -> Array:
	var out := []
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	for pid in players:
		if not players[pid].ready:
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
	elif mode == Mode.CLIENT and _connect_t > 0:
		_connect_t -= delta
		if _connect_t <= 0:
			_fail("O servidor não respondeu. Confira o endereço e se a porta UDP está liberada.")


# ---------------------------------------------------------------- inimigos (servidor)
func server_register_enemy(e: Enemy) -> void:
	e.net_id = _next_enemy_id
	_next_enemy_id += 1
	enemies[e.net_id] = e
	for pid in _ready_peers():
		_enemy_spawned.rpc_id(pid, e.net_id, e.kind, e.global_position, e.model.rotation.y, e.max_hp, e.hp)


func unregister_enemy(e: Enemy) -> void:
	if enemies.get(e.net_id) == e:
		enemies.erase(e.net_id)


func server_enemy_killed(e: Enemy) -> void:
	var pos := e.global_position
	for pid in e.contributors:
		if players.has(pid):
			_kill_reward.rpc_id(pid, e.kind, int(e.data.xp), pos)
	for pid in _ready_peers():
		_enemy_died.rpc_id(pid, e.net_id)


func _send_enemy_snapshot() -> void:
	var peers := _ready_peers()
	if peers.is_empty() or enemies.is_empty():
		return
	var snap := PackedFloat32Array()
	for net_id in enemies:
		var e: Enemy = enemies[net_id]
		if not is_instance_valid(e) or e.dead:
			continue
		var p := e.global_position
		var flags := (1 if e.slow_timer > 0 else 0) | (2 if e.enraged else 0)
		snap.append_array([net_id, p.x, p.y, p.z, e.model.rotation.y, e.hp,
			max(0, STATES.find(e.state)), e.attack_timer, max(0, ATTACK_KINDS.find(e.attack_kind)), flags])
	_snapshots_sent += 1
	for pid in peers:
		_enemy_snapshot.rpc_id(pid, snap)


@rpc("any_peer", "call_remote", "reliable")
func _hit_enemy(net_id: int, amount: float, from_pos: Vector3, crit: bool, slow: float) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_server() or not players.has(id):
		return
	var e: Enemy = enemies.get(net_id)
	if e == null or not is_instance_valid(e) or e.dead:
		return
	amount = clampf(amount, 0.0, 5000.0)
	if amount > 0.0:
		for pid in _ready_peers():
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
	_apply_remote_state(id, pos, yaw, vel, flags, combo, attack_t)
	for pid in _ready_peers():
		if pid != id:
			_player_state_relay.rpc_id(pid, id, pos, yaw, vel, flags, combo, attack_t)


@rpc("any_peer", "call_remote", "reliable")
func _player_look(weapon: String, armor: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_server() or not players.has(id):
		return
	players[id].weapon = weapon
	players[id].armor = armor
	_apply_remote_look(id)
	for pid in _ready_peers():
		if pid != id:
			_player_look_relay.rpc_id(pid, id, weapon, armor)


@rpc("any_peer", "call_remote", "reliable")
func _player_event(kind: String, a: Vector3, b: Vector3) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_server() or not players.has(id):
		return
	for pid in _ready_peers():
		if pid != id:
			_player_event_relay.rpc_id(pid, id, kind, a, b)


# ================================================================ cliente
## Conecta em "host" ou "host:porta". O personagem (Game) já deve estar carregado.
func join(address: String, player_name: String) -> void:
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
	my_name = player_name
	last_error = ""
	_connect_t = CONNECT_TIMEOUT


func leave() -> void:
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.OFFLINE
	players.clear()
	enemies.clear()
	remote_players.clear()
	_connect_t = 0.0


func _on_connected_to_server() -> void:
	_no_throttle(1)
	_register.rpc_id(1, my_name, version(), Game.equipment.weapon, Game.equipment.armor)


func _on_connection_failed() -> void:
	_fail("Não foi possível conectar ao servidor.")


func _fail(reason: String) -> void:
	leave()
	join_failed.emit(reason)


func _on_server_disconnected() -> void:
	var in_world := world != null
	if in_world:
		autosave()
	leave()
	if in_world:
		last_error = "Conexão com o servidor perdida. Seu progresso foi salvo."
		Game.go_to_menu()


@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String) -> void:
	_fail(reason)


@rpc("authority", "call_remote", "reliable")
func _accepted(all_players: Dictionary) -> void:
	_connect_t = 0.0
	players = all_players
	var me: int = multiplayer.get_unique_id()
	if players.has(me):
		my_name = players[me].name
	get_tree().paused = false
	get_tree().change_scene_to_file(WORLD_SCENE)


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


## Salva o personagem local (o progresso no multiplayer fica no PC de cada jogador).
func autosave() -> void:
	if world == null or world.get("player") == null:
		return
	var p: Player = world.player
	if is_instance_valid(p):
		Game.save_game(p.global_position if not p.dead else Vector3(0, 0.5, 6), p.model.rotation.y)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_client():
		autosave()


# ---------------------------------------------------------------- envio (cliente)
func send_player_state(pos: Vector3, yaw: float, vel: Vector3, flags: int, combo: int, attack_t: float) -> void:
	if is_client() and world:
		_player_state.rpc_id(1, pos, yaw, vel, flags, combo, attack_t)


func send_look(weapon: String, armor: String) -> void:
	if is_client():
		_player_look.rpc_id(1, weapon, armor)


func send_event(kind: String, a := Vector3.ZERO, b := Vector3.ZERO) -> void:
	if is_client() and world:
		_player_event.rpc_id(1, kind, a, b)


func client_hit_enemy(net_id: int, amount: float, from_pos: Vector3, crit: bool, slow := 0.0) -> void:
	if is_client():
		_hit_enemy.rpc_id(1, net_id, amount, from_pos, crit, slow)


func request_boss() -> void:
	if is_client():
		_request_boss.rpc_id(1)


# ---------------------------------------------------------------- recebimento (cliente)
@rpc("authority", "call_remote", "reliable")
func _player_joined(id: int, info: Dictionary) -> void:
	players[id] = info
	Game.notify.emit("%s entrou no mundo." % info.name, Color(0.6, 0.9, 1.0))
	players_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _player_left(id: int) -> void:
	if players.has(id):
		Game.notify.emit("%s saiu." % players[id].name, Color(0.7, 0.75, 0.85))
	players.erase(id)
	_remove_remote_player(id)
	players_changed.emit()


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _player_state_relay(id: int, pos: Vector3, yaw: float, vel: Vector3, flags: int, combo: int, attack_t: float) -> void:
	_apply_remote_state(id, pos, yaw, vel, flags, combo, attack_t)


@rpc("authority", "call_remote", "reliable")
func _player_look_relay(id: int, weapon: String, armor: String) -> void:
	if players.has(id):
		players[id].weapon = weapon
		players[id].armor = armor
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
func _enemy_spawned(net_id: int, kind: String, pos: Vector3, yaw: float, max_hp: float, hp: float) -> void:
	if world == null or enemies.has(net_id):
		return
	var e := ENEMY.new()
	e.kind = kind
	e.puppet = true
	e.net_id = net_id
	e.position = pos
	world.add_child(e)
	e.max_hp = max_hp
	e.hp = hp
	e.model.rotation.y = yaw
	e.set_net_target(pos, yaw)
	enemies[net_id] = e
	if e.is_boss:
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
	Game.on_enemy_killed(kind, xp)
	if ENEMY.TYPES[kind].get("boss", false):
		Game.flags["king_dead"] = true
	if world:
		ENEMY.drop_loot(world, kind, pos)


# ---------------------------------------------------------------- réplicas de jogadores
func _apply_remote_state(id: int, pos: Vector3, yaw: float, vel: Vector3, flags: int, combo: int, attack_t: float) -> void:
	if world == null:
		return
	var rp: Player = remote_players.get(id)
	if rp == null or not is_instance_valid(rp):
		rp = PLAYER.new()
		rp.remote = true
		rp.peer_id = id
		rp.display_name = players[id].name if players.has(id) else "?"
		rp.position = pos
		world.add_child(rp)
		remote_players[id] = rp
		_apply_remote_look(id)
	rp.apply_net_state(pos, yaw, vel, flags, combo, attack_t)


func _apply_remote_look(id: int) -> void:
	var rp: Player = remote_players.get(id)
	if rp and is_instance_valid(rp) and players.has(id):
		rp.apply_look(players[id].get("weapon", ""), players[id].get("armor", ""))


func _remove_remote_player(id: int) -> void:
	var rp: Player = remote_players.get(id)
	remote_players.erase(id)
	if rp and is_instance_valid(rp):
		rp.queue_free()
