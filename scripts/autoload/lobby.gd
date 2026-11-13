extends Node
## Salão central do multiplayer e a Defesa da Cidade em grupo.
##
## Ao entrar no servidor o jogador cai no salão (lobby.tscn): vê quem está online e onde está,
## vai para Valdoria (o mundo do RPG) ou abre/entra na sala da Defesa da Cidade cooperativa.
##
## A cidade em grupo roda no servidor dentro de um SubViewport com mundo 3D próprio (física separada
## de Valdoria, que continua rodando). O servidor simula tudo (Colony role "server"): economia, ondas,
## torres, soldados e animais. Cada cliente carrega colony.tscn com role "client" e recebe réplicas:
## construções, soldados e animais por aqui; os monstros pela replicação normal do Network (zona "city").
## As ações dos jogadores (construir, melhorar, recrutar...) viram pedidos que o servidor valida.
## Todas as RPCs da sala e da cidade passam por este autoload (/root/Lobby existe igual em todos os peers).

signal changed   # cliente: sala, recorde ou lista de jogadores mudou

const LOBBY_SCENE := "res://scenes/lobby.tscn"
const WORLD_SCENE := "res://scenes/world.tscn"
const COLONY_SCENE := "res://scenes/colony.tscn"
const SNAP_RATE := 8.0
const STATE_RATE := 2.0
const VILLAGE_SPAWN := Vector3(0, 0.5, 6)

# ================================================================ cliente
## Sala vista pelo servidor: {"state": "open"|"running", "leader": id, "members": [ids], "ready": [ids],
## "names": {id: nome}, "day": int, "phase": String, "max": int}. Vazio = nenhuma sala.
var room := {}
## Melhor partida do servidor: {"day": noites, "names": [nomes]}.
var record := {}
## Resultado da última partida (mostrado no salão ao voltar).
var last_result := {}
## Cliente: a cena da cidade que está carregando deve entrar como réplica.
var joining_city := false
var city_seed := 0
## Cliente: colony_world (role "client") em uso.
var city: Node = null
var _last_world_pos = null
var _last_world_yaw := 0.0

# ================================================================ servidor
## {"state": "open"|"running", "leader": id, "members": {id: pronto}, "names": {id: nome}, "seed": int}
var _room := {}
var _vp: SubViewport = null
var _city: Node = null          # colony_world com role "server"
var _snap_t := 0.0
var _state_t := 0.0
var _room_t := 0.0
var _force_t := 0.0
var _record := {"day": 0, "names": []}
var _present := {}              # peers que estavam na cidade quando a noite começou
var _rewards := {}              # peer -> {"gold", "xp", "items": []} somado na partida
## Duração do dia na cidade (--city-day=SEG encurta para os testes).
var city_day_time := ColonyData.DAY_LENGTH
var city_first_bonus := ColonyData.FIRST_DAY_BONUS
## Baús de recompensa no chão: id -> {"n": noite, "pos": Vector3, "loot": {peer: [itens]}}.
var _chests := {}
var _chest_id := 0
## --city-chests: baú em toda noite vencida (para os testes não esperarem a noite de chefe).
var chests_every_night := false
const CHEST_REACH := 6.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--city-day="):
			city_day_time = maxf(5.0, float(a.substr(11)))
			city_first_bonus = 0.0
		elif a == "--city-chests":
			chests_every_night = true


# ================================================================ cliente: navegação
## O servidor aceitou a conexão: todo mundo chega pelo salão.
func on_accepted() -> void:
	_last_world_pos = Game.spawn_position
	_last_world_yaw = Game.spawn_yaw
	last_result = {}
	get_tree().change_scene_to_file(LOBBY_SCENE)


## A cena do salão terminou de montar.
func lobby_ready() -> void:
	joining_city = false
	if Network.is_client():
		_enter_lobby.rpc_id(1)


## Está no salão ou na cidade em grupo (para a desconexão voltar ao menu).
func in_session() -> bool:
	var s := get_tree().current_scene
	return s != null and (s.get("is_lobby") == true or s.get("role") == "client")


func go_world() -> void:
	joining_city = false
	if Game.hp <= 0.0:
		Game.hp = Game.max_hp()
	Game.spawn_position = _last_world_pos
	Game.spawn_yaw = _last_world_yaw
	get_tree().paused = false
	get_tree().change_scene_to_file(WORLD_SCENE)


## De Valdoria ou da cidade de volta ao salão (salva o personagem antes).
func go_lobby() -> void:
	var w := Network.world
	if w != null and w.get("role") == null and w.get("player") != null and is_instance_valid(w.player):
		var p: Player = w.player
		if not p.dead:
			_last_world_pos = p.global_position
			_last_world_yaw = p.model.rotation.y
	save_character()
	Game.reset_run_mods()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(LOBBY_SCENE)


## Salva o personagem na última posição em Valdoria (a cidade não muda onde ele está no RPG).
func save_character() -> void:
	if Game.run_mods.get("active", false):
		return
	var pos = _last_world_pos if _last_world_pos != null else VILLAGE_SPAWN
	Game.save_game(pos, _last_world_yaw)


func client_reset() -> void:
	room = {}
	record = {}
	joining_city = false
	city = null
	changed.emit()


# ---------------------------------------------------------------- sala (cliente)
## "create", "join", "leave", "ready", "unready", "start" ou "enter" (entrar na partida em andamento).
func room_send(kind: String) -> void:
	if Network.is_client():
		_room_msg.rpc_id(1, kind)


func my_id() -> int:
	return multiplayer.get_unique_id()


func in_room() -> bool:
	return my_id() in room.get("members", [])


func is_leader() -> bool:
	return int(room.get("leader", 0)) == my_id()


func is_ready() -> bool:
	return my_id() in room.get("ready", [])


# ---------------------------------------------------------------- cidade (cliente)
## A cena da cidade (role "client") terminou de montar.
func city_ready(w: Node) -> void:
	city = w
	Network.world = w
	if Network.is_client():
		_city_ready.rpc_id(1)


func city_closed(w: Node) -> void:
	if city == w:
		city = null
	Network.world_closed(w)


func city_request(action: String, args: Array) -> void:
	if Network.is_client():
		_city_req.rpc_id(1, action, args)


func city_hit_animal(net_id: int, amount: float, from_pos: Vector3, slow: float) -> void:
	if Network.is_client():
		_city_hit_animal.rpc_id(1, net_id, amount, from_pos, slow)


## O que este jogador está posicionando no modo construção (kind "" = saiu do modo).
func city_ghost(kind: String, x: float, z: float, rot: float, ok: bool, target: int) -> void:
	if Network.is_client():
		_city_ghost.rpc_id(1, kind, x, z, rot, ok, target)


func city_chest_open(id: int) -> void:
	if Network.is_client():
		_city_chest_open.rpc_id(1, id)


## Pega o item `index` (conferido pelo id) do seu saque no baú; index -1 pega tudo.
func city_chest_take(id: int, index: int, item_id: String) -> void:
	if Network.is_client():
		_city_chest_take.rpc_id(1, id, index, item_id)


func _colony() -> Colony:
	if Network.is_server():
		return _city.colony if _city != null and is_instance_valid(_city) else null
	return city.colony if city != null and is_instance_valid(city) else null


# ================================================================ servidor
func is_city_node(n: Node) -> bool:
	return _city != null and is_instance_valid(_city) and _city.is_ancestor_of(n)


func server_city_root() -> Node:
	return _city if _city != null and is_instance_valid(_city) else null


func city_team_size() -> int:
	return maxi(1, Network.zone_peers("city").size())


func _physics_process(delta: float) -> void:
	if not Network.is_server():
		return
	var c := _colony()
	if c != null:
		_state_t -= delta
		if c.state_dirty() or _state_t <= 0.0:
			_state_t = 1.0 / STATE_RATE
			var st := c.net_state()
			for pid in Network.zone_peers("city"):
				_city_state.rpc_id(pid, st)
		_snap_t -= delta
		_force_t -= delta
		if _snap_t <= 0.0:
			_snap_t = 1.0 / SNAP_RATE
			var force := _force_t <= 0.0
			if force:
				_force_t = 2.0
			var snap := c.net_snapshot(force)
			var peers := Network.zone_peers("city")
			if not peers.is_empty():
				for pid in peers:
					_city_snap.rpc_id(pid, snap[0], snap[1], snap[2])
	if not _room.is_empty():
		_room_t -= delta
		if _room_t <= 0.0:
			_room_t = 3.0
			_broadcast_room()


func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if Network.is_server() and Network.players.has(id) else 0


func _name(id: int) -> String:
	if Network.players.has(id):
		return str(Network.players[id].name)
	return str(_room.get("names", {}).get(id, "?"))


@rpc("any_peer", "call_remote", "reliable")
func _enter_lobby() -> void:
	var id := _sender()
	if id == 0:
		return
	Network.server_set_zone(id, "lobby")
	_room_state.rpc_id(id, _room_view(), _record)


# ---------------------------------------------------------------- sala (servidor)
@rpc("any_peer", "call_remote", "reliable")
func _room_msg(kind: String) -> void:
	var id := _sender()
	if id == 0:
		return
	var in_lobby := Network.zone_of(id) == "lobby"
	match kind:
		"create", "join":
			if not in_lobby:
				return
			if _room.is_empty():
				_room = {"state": "open", "leader": id, "members": {id: false}, "names": {id: _name(id)}, "seed": 0}
				print("[server] %s abriu a sala da Defesa da Cidade" % _name(id))
				_lobby_say("%s abriu uma sala da Defesa da Cidade em grupo." % _name(id), Color(1, 0.85, 0.5))
			elif _room.state == "open":
				if _room.members.size() >= ColonyData.COOP_MAX_PLAYERS:
					_notice.rpc_id(id, "A sala está cheia.")
					return
				_room.members[id] = false
				_room.names[id] = _name(id)
			else:
				_room_msg_enter(id)
				return
		"leave":
			if _room.is_empty() or not _room.members.has(id) or _room.state != "open":
				return
			_room.members.erase(id)
			if _room.members.is_empty():
				_room = {}
			elif _room.leader == id:
				_room.leader = _room.members.keys()[0]
		"ready", "unready":
			if not _room.is_empty() and _room.members.has(id) and _room.state == "open":
				_room.members[id] = kind == "ready"
		"start":
			if _room.is_empty() or _room.state != "open" or _room.leader != id:
				return
			for pid in _room.members:
				if pid != id and not _room.members[pid]:
					_notice.rpc_id(id, "Espere todos ficarem prontos.")
					return
			_start_city()
		"enter":
			_room_msg_enter(id)
			return
	_broadcast_room()


## Entrar na partida em andamento (direto do salão).
func _room_msg_enter(id: int) -> void:
	if _room.is_empty() or _room.state != "running" or _city == null:
		return
	if Network.zone_of(id) != "lobby":
		return
	if Network.zone_peers("city").size() >= ColonyData.COOP_MAX_PLAYERS:
		_notice.rpc_id(id, "A cidade está cheia (%d jogadores)." % ColonyData.COOP_MAX_PLAYERS)
		return
	_room.members[id] = true
	_room.names[id] = _name(id)
	_city_go.rpc_id(id, int(_room.seed))
	_broadcast_room()


func _room_view() -> Dictionary:
	if _room.is_empty():
		return {}
	var ready: Array = []
	for pid in _room.members:
		if _room.members[pid]:
			ready.append(pid)
	var v := {"state": _room.state, "leader": _room.leader, "members": _room.members.keys(), "ready": ready,
		"names": _room.names.duplicate(), "max": ColonyData.COOP_MAX_PLAYERS}
	var c := _colony()
	if c != null:
		v["day"] = c.day
		v["phase"] = c.phase
		v["in_city"] = Network.zone_peers("city")
	return v


func _broadcast_room() -> void:
	var v := _room_view()
	for pid in Network._all_peers():
		_room_state.rpc_id(pid, v, _record)


func _lobby_say(text: String, color: Color) -> void:
	for pid in Network.zone_peers("lobby"):
		_city_say.rpc_id(pid, text, color)


func _start_city() -> void:
	var seed := randi() % 1000000 + 1
	_room.state = "running"
	_room.seed = seed
	for pid in _room.members:
		_room.members[pid] = true
	_present.clear()
	_rewards.clear()
	_chests.clear()
	_vp = SubViewport.new()
	_vp.own_world_3d = true          # física e mundo separados de Valdoria
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	_city = load(COLONY_SCENE).instantiate()
	_city.role = "server"
	_city.map_seed = seed
	_city.coop_players = _room.members.size()
	_vp.add_child(_city)
	print("[server] Defesa da Cidade em grupo começou (%d jogadores, mapa %d)" % [_room.members.size(), seed])
	for pid in _room.members:
		_city_go.rpc_id(pid, seed)
	_lobby_say("A Defesa da Cidade começou! Quem estiver no salão ainda pode entrar.", Color(1, 0.85, 0.5))


## Um jogador saiu da cidade (voltou ao salão, caiu a conexão...).
func server_city_left(id: int) -> void:
	_present.erase(id)
	_flush_chests(id)
	if _room.is_empty():
		return
	_room.members.erase(id)
	if _room.state == "running" and _colony() != null:
		_colony().say("%s saiu da cidade." % _name(id), Color(0.8, 0.8, 0.9))
	if _room.members.is_empty() or (_room.state == "running" and Network.zone_peers("city").is_empty()
			and _room.members.keys().all(func(pid) -> bool: return Network.zone_of(pid) != "lobby")):
		if _room.state == "running":
			_end_city("abandon", [id])   # quem saiu por último também vê o resumo no salão
		else:
			_room = {}
	elif _room.leader == id:
		_room.leader = _room.members.keys()[0]
	_broadcast_room()


func server_peer_gone(id: int, was_city: bool) -> void:
	if was_city:
		server_city_left(id)
	elif not _room.is_empty() and _room.members.has(id):
		_room.members.erase(id)
		if _room.members.is_empty() and _room.state == "open":
			_room = {}
		elif not _room.members.is_empty() and _room.leader == id:
			_room.leader = _room.members.keys()[0]
		if _room.is_empty() or _room.state == "open":
			_broadcast_room()
		elif Network.zone_peers("city").is_empty():
			_end_city("abandon")


## Fim da partida: "defeat" (a prefeitura caiu) ou "abandon" (todos saíram).
func _end_city(reason: String, extra_peers: Array = []) -> void:
	var c := _colony()
	var nights := 0
	var kills := 0
	if c != null:
		nights = maxi(0, c.day - 1)
		kills = c.total_kills
	_update_record(nights)
	var names: Array = []
	for pid in _room.get("names", {}):
		names.append(_room.names[pid])
	print("[server] Defesa da Cidade terminou (%s): %d noites, %d abates" % [reason, nights, kills])
	var to: Array = Network.zone_peers("city")
	for pid in extra_peers:
		if Network.players.has(pid) and not (pid in to):
			to.append(pid)
	for pid in to:
		_flush_chests(pid)   # o que ficou nos baús vai para a mochila antes do resumo
	_chests.clear()
	for pid in to:
		var r: Dictionary = _rewards.get(pid, {"gold": 0, "xp": 0, "items": []})
		_city_over.rpc_id(pid, {"reason": reason, "nights": nights, "kills": kills, "gold": r.gold, "xp": r.xp,
			"items": r.items, "names": names, "record": _record.day})
	_room = {}
	_present.clear()
	var vp := _vp
	_vp = null
	if _city != null and is_instance_valid(_city):
		# para tudo na hora: nada mais nasce (um monstro novo seria registrado como de Valdoria)
		_city.process_mode = Node.PROCESS_MODE_DISABLED
		for e in _city.colony.live_enemies():
			Network.unregister_enemy(e)
	_city = null
	_broadcast_room()
	if vp != null:
		# deixa os clientes verem a queda antes de sumir com tudo
		await get_tree().create_timer(1.0).timeout
		vp.queue_free()


func _update_record(nights: int) -> void:
	if nights <= int(_record.day):
		return
	var names: Array = []
	for pid in _room.get("names", {}):
		names.append(_room.names[pid])
	_record = {"day": nights, "names": names}


# ---------------------------------------------------------------- cidade (servidor)
@rpc("any_peer", "call_remote", "reliable")
func _city_ready() -> void:
	var id := _sender()
	if id == 0:
		return
	var c := _colony()
	if c == null or _room.is_empty() or _room.state != "running":
		_city_closed.rpc_id(id, "A partida já terminou.")
		return
	if not _room.members.has(id):
		_room.members[id] = true
		_room.names[id] = _name(id)
	Network.server_set_zone(id, "city")
	c.team_size = city_team_size()
	_city_full.rpc_id(id, c.net_full())
	Network.send_zone_enemies(id, "city")
	for e in c.live_enemies():
		if e.affix != "" and e.net_id != 0:
			_city_enemy_meta.rpc_id(id, e.net_id, e.affix)
	for cid in _chests:
		_send_chest(id, cid)
	if c.phase == "night":
		_present[id] = true
	c.say("%s chegou à cidade (%d jogador(es))." % [_name(id), c.team_size], Color(0.6, 0.9, 1.0))
	_broadcast_room()


@rpc("any_peer", "call_remote", "reliable")
func _city_req(action: String, args: Array) -> void:
	var id := _sender()
	var c := _colony()
	if id == 0 or c == null or Network.zone_of(id) != "city" or c.phase == "over":
		return
	var err := c.net_request(id, action, args)
	if err != "":
		_notice.rpc_id(id, err)


@rpc("any_peer", "call_remote", "reliable")
func _city_hit_animal(net_id: int, amount: float, from_pos: Vector3, slow: float) -> void:
	var id := _sender()
	var c := _colony()
	if id == 0 or c == null or Network.zone_of(id) != "city":
		return
	var a = c.amap.get(net_id)
	if a == null or not is_instance_valid(a) or a.dead:
		return
	if amount > 0.0:
		a.take_damage(clampf(amount, 0.0, 5000.0), from_pos, false, minf(slow, 10.0))
	elif slow > 0.0:
		a.apply_slow(minf(slow, 10.0))


## Monstro da cidade morto: ouro no cofre e XP para quem acertou.
func server_city_kill(e: Enemy) -> void:
	var c := _colony()
	if c != null:
		c.on_net_kill(e)
	var xp := int(e.data.xp * 0.5 * (2.0 if e.affix != "" else 1.0))
	for pid in e.contributors:
		if Network.zone_of(pid) == "city":
			_city_xp.rpc_id(pid, e.kind, xp)


func city_night_started() -> void:
	_present.clear()
	for pid in Network.zone_peers("city"):
		_present[pid] = true


## Amanheceu depois da noite n: cada jogador que segurou a noite ganha ouro e XP no próprio personagem;
## nas noites de chefe aparece um baú perto da prefeitura com o saque de cada um (raridade sobe com a noite).
func city_night_survived(n: int) -> void:
	var rw := ColonyData.night_reward(n)
	var chest_night := n % ColonyData.BOSS_EVERY == 0 or chests_every_night
	var loot := {}
	for pid in Network.zone_peers("city"):
		if not _present.has(pid):
			continue
		var acc := _reward_acc(pid)
		acc.gold += int(rw.gold)
		acc.xp += int(rw.xp)
		_city_reward.rpc_id(pid, n, int(rw.gold), int(rw.xp), chest_night)
		if chest_night:
			var items: Array = []
			var it := _roll_item(n)
			if it != "":
				items.append(it)
			items.append("health_potion")
			items.append("health_potion")
			loot[pid] = items
	if not loot.is_empty():
		_spawn_chest(n, loot)
	_update_record(n)
	_broadcast_room()


func _reward_acc(pid: int) -> Dictionary:
	if not _rewards.has(pid):
		_rewards[pid] = {"gold": 0, "xp": 0, "items": []}
	return _rewards[pid]


# ---------------------------------------------------------------- baús (servidor)
func _spawn_chest(n: int, loot: Dictionary) -> void:
	var c := _colony()
	if c == null:
		return
	_chest_id += 1
	var pos := c.chest_spot()
	_chests[_chest_id] = {"n": n, "pos": pos, "loot": loot}
	c.chests[_chest_id] = pos
	print("[server] baú %d da noite %d em (%.1f, %.1f) para %d jogador(es)" % [_chest_id, n, pos.x, pos.z, loot.size()])
	for pid in Network.zone_peers("city"):
		_send_chest(pid, _chest_id)
	c.say("Um baú da noite %d apareceu na frente da prefeitura! Cada um que segurou a noite tem o seu saque lá dentro." % n,
		Color(1, 0.85, 0.35))


func _send_chest(pid: int, id: int) -> void:
	var ch: Dictionary = _chests[id]
	var mine: Array = ch.loot.get(pid, [])
	_city_chest_add.rpc_id(pid, id, int(ch.n), ch.pos.x, ch.pos.z, _best_rarity(mine), mine.size())


static func _best_rarity(items: Array) -> String:
	var best := ""
	for id in items:
		var r := ItemDB.rarity_of(str(id))
		if best == "" or ItemDB.RARITY[r].rank > ItemDB.RARITY[best].rank:
			best = r
	return best


func _remove_chest(id: int) -> void:
	_chests.erase(id)
	var c := _colony()
	if c != null:
		c.chests.erase(id)
	_to_city("_city_chest_del", [id])


## O jogador saiu da cidade (ou a partida acabou): o que ele deixou nos baús vai direto para a mochila.
func _flush_chests(pid: int) -> void:
	var left: Array = []
	for cid in _chests.keys():
		var ch: Dictionary = _chests[cid]
		if ch.loot.has(pid):
			left.append_array(ch.loot[pid])
			ch.loot.erase(pid)
		if ch.loot.is_empty():
			_remove_chest(cid)
	if left.is_empty():
		return
	_reward_acc(pid).items.append_array(left)
	if pid in Network._all_peers():
		_city_chest_auto.rpc_id(pid, left)


func _near_chest(pid: int, id: int) -> bool:
	var rp = Network.remote_players.get(pid)
	if rp == null or not is_instance_valid(rp):
		return true   # ainda sem posição no servidor: confia
	var p: Vector3 = _chests[id].pos
	return Vector2(rp.global_position.x - p.x, rp.global_position.z - p.z).length() <= CHEST_REACH


@rpc("any_peer", "call_remote", "reliable")
func _city_chest_open(id: int) -> void:
	var pid := _sender()
	if pid == 0 or _colony() == null or Network.zone_of(pid) != "city" or not _chests.has(id):
		return
	if not _near_chest(pid, id):
		_notice.rpc_id(pid, "Chegue mais perto do baú.")
		_city_chest_loot.rpc_id(pid, id, [], false)
		return
	var mine: Array = _chests[id].loot.get(pid, [])
	_city_chest_loot.rpc_id(pid, id, mine, true)
	for other in Network.zone_peers("city"):
		if other != pid:
			_city_chest_fx.rpc_id(other, id, pid)


@rpc("any_peer", "call_remote", "reliable")
func _city_chest_take(id: int, index: int, item_id: String) -> void:
	var pid := _sender()
	if pid == 0 or _colony() == null or Network.zone_of(pid) != "city" or not _chests.has(id):
		return
	var ch: Dictionary = _chests[id]
	var mine: Array = ch.loot.get(pid, [])
	if mine.is_empty() or not _near_chest(pid, id):
		return
	var given: Array = []
	if index < 0:
		given = mine.duplicate()
		mine.clear()
	else:
		# confere pelo id (cliques rápidos podem chegar com a lista já mudada)
		var i := index if index < mine.size() and str(mine[index]) == item_id else mine.find(item_id)
		if i < 0:
			return
		given.append(mine[i])
		mine.remove_at(i)
	_reward_acc(pid).items.append_array(given)
	_city_chest_given.rpc_id(pid, id, given, mine)
	var who := _name(pid)
	for it in given:
		var r := ItemDB.rarity_of(str(it))
		if ItemDB.RARITY[r].rank >= ItemDB.RARITY["rare"].rank:
			for other in Network.zone_peers("city"):
				if other != pid:
					_city_say.rpc_id(other, "%s pegou %s (%s) do baú!" % [who, ItemDB.get_item(str(it)).get("name", it), ItemDB.RARITY[r].name],
						ItemDB.RARITY[r].color)
	if mine.is_empty():
		ch.loot.erase(pid)
	if ch.loot.is_empty():
		await get_tree().create_timer(1.5).timeout   # deixa a tampa aberta um instante antes de sumir
		if _chests.get(id) == ch:
			_remove_chest(id)


# ---------------------------------------------------------------- fantasma da construção (servidor)
@rpc("any_peer", "call_remote", "unreliable_ordered", 4)
func _city_ghost(kind: String, x: float, z: float, rot: float, ok: bool, target: int) -> void:
	var id := _sender()
	if id == 0 or Network.zone_of(id) != "city" or _colony() == null:
		return
	if kind != "" and kind != "demolish" and not ColonyData.BUILDINGS.has(kind):
		return
	for pid in Network.zone_peers("city"):
		if pid != id:
			_city_ghost_of.rpc_id(pid, id, kind, x, z, rot, ok, target)


func _roll_item(n: int) -> String:
	for entry in ColonyData.chest_rarities(n):
		if randf() < float(entry[1]):
			var pool: Array = []
			for id in ItemDB.ITEMS:
				if ItemDB.is_equippable(id) and ItemDB.rarity_of(id) == entry[0]:
					pool.append(id)
			if not pool.is_empty():
				return pool.pick_random()
	return ""


func city_defeat() -> void:
	if _city != null:
		_end_city("defeat")


func city_say(text: String, color: Color) -> void:
	for pid in Network.zone_peers("city"):
		_city_say.rpc_id(pid, text, color)


func _to_city(method: String, args: Array) -> void:
	for pid in Network.zone_peers("city"):
		callv("rpc_id", [pid, method] + args)


func city_building_added(b: ColonyBuilding) -> void:
	_to_city("_city_bld_add", [b.net_id, b.kind, b.global_position.x, b.global_position.z, b.rotation.y, b.level, b.hp, b.invested])


func city_building_changed(b: ColonyBuilding) -> void:
	b.net_sent_hp = b.hp
	_to_city("_city_bld_set", [b.net_id, b.level, b.hp, b.invested])


func city_building_removed(b: ColonyBuilding, destroyed: bool) -> void:
	_to_city("_city_bld_del", [b.net_id, destroyed])


func city_soldier_added(s: ColonySoldier) -> void:
	_to_city("_city_sol_add", [s.net_id, s.unit, s.position.x, s.position.z, s.hp])


func city_soldier_removed(s: ColonySoldier, died: bool) -> void:
	_to_city("_city_sol_del", [s.net_id, died])


func city_animal_added(a: ColonyAnimal) -> void:
	_to_city("_city_ani_add", [a.net_id, a.kind, a.position.x, a.position.z])


func city_animal_removed(a: ColonyAnimal, killed: bool) -> void:
	_to_city("_city_ani_del", [a.net_id, killed])


func city_enemy_meta(e: Enemy) -> void:
	if e.net_id != 0:
		_to_city("_city_enemy_meta", [e.net_id, e.affix])


## Disparo de torre/arqueiro (só visual nos clientes).
func city_shot(kind: String, from: Vector3, target: Enemy, splash: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var peers := Network.zone_peers("city")
	for pid in peers:
		_city_shot.rpc_id(pid, kind, from, target.net_id, target.global_position, splash)


# ================================================================ RPCs recebidas pelo cliente
@rpc("authority", "call_remote", "reliable")
func _room_state(v: Dictionary, rec: Dictionary) -> void:
	room = v
	record = rec
	changed.emit()


@rpc("authority", "call_remote", "reliable")
func _notice(text: String) -> void:
	Game.notify.emit(text, Color(1, 0.7, 0.5))


@rpc("authority", "call_remote", "reliable")
func _city_say(text: String, color: Color) -> void:
	Game.notify.emit(text, color)


@rpc("authority", "call_remote", "reliable")
func _city_go(seed: int) -> void:
	city_seed = seed
	joining_city = true
	save_character()
	Game.reset_run_mods()
	get_tree().paused = false
	get_tree().change_scene_to_file(COLONY_SCENE)


@rpc("authority", "call_remote", "reliable")
func _city_closed(reason: String) -> void:
	Game.notify.emit(reason, Color(1, 0.7, 0.5))
	if city != null:
		go_lobby()


@rpc("authority", "call_remote", "reliable")
func _city_full(d: Dictionary) -> void:
	var c := _colony()
	if c == null:
		return
	for b in d.get("buildings", []):
		c.net_building_add(int(b[0]), str(b[1]), float(b[2]), float(b[3]), float(b[4]), int(b[5]), float(b[6]), int(b[7]), false)
	for s in d.get("soldiers", []):
		c.net_soldier_add(int(s[0]), str(s[1]), float(s[2]), float(s[3]), float(s[4]), false)
	for a in d.get("animals", []):
		c.net_animal_add(int(a[0]), str(a[1]), float(a[2]), float(a[3]))
	c.apply_state(d.get("state", {}))
	if city and city.has_method("on_city_synced"):
		city.on_city_synced()


@rpc("authority", "call_remote", "reliable")
func _city_state(st: Dictionary) -> void:
	var c := _colony()
	if c:
		c.apply_state(st)


@rpc("authority", "call_remote", "unreliable_ordered", 3)
func _city_snap(ss: PackedFloat32Array, aa: PackedFloat32Array, bh: PackedFloat32Array) -> void:
	var c := _colony()
	if c:
		c.apply_snapshot(ss, aa, bh)


@rpc("authority", "call_remote", "reliable")
func _city_bld_add(id: int, kind: String, x: float, z: float, rot: float, level: int, hp: float, invested: int) -> void:
	var c := _colony()
	if c:
		c.net_building_add(id, kind, x, z, rot, level, hp, invested)


@rpc("authority", "call_remote", "reliable")
func _city_bld_set(id: int, level: int, hp: float, invested: int) -> void:
	var c := _colony()
	if c:
		c.net_building_set(id, level, hp, invested)


@rpc("authority", "call_remote", "reliable")
func _city_bld_del(id: int, destroyed: bool) -> void:
	var c := _colony()
	if c:
		c.net_building_remove(id, destroyed)


@rpc("authority", "call_remote", "reliable")
func _city_sol_add(id: int, unit: String, x: float, z: float, hp: float) -> void:
	var c := _colony()
	if c:
		c.net_soldier_add(id, unit, x, z, hp)


@rpc("authority", "call_remote", "reliable")
func _city_sol_del(id: int, died: bool) -> void:
	var c := _colony()
	if c:
		c.net_soldier_remove(id, died)


@rpc("authority", "call_remote", "reliable")
func _city_ani_add(id: int, kind: String, x: float, z: float) -> void:
	var c := _colony()
	if c:
		c.net_animal_add(id, kind, x, z)


@rpc("authority", "call_remote", "reliable")
func _city_ani_del(id: int, killed: bool) -> void:
	var c := _colony()
	if c:
		c.net_animal_remove(id, killed)


@rpc("authority", "call_remote", "reliable")
func _city_enemy_meta(net_id: int, affix: String) -> void:
	var e: Enemy = Network.enemies.get(net_id)
	if e and is_instance_valid(e) and not e.dead and ColonyData.AFFIXES.has(affix):
		e.set_affix(affix)


@rpc("authority", "call_remote", "unreliable")
func _city_shot(kind: String, from: Vector3, target_id: int, target_pos: Vector3, splash: float) -> void:
	var c := _colony()
	if c == null:
		return
	var s := preload("res://scripts/colony/tower_shot.gd").new()
	s.kind = kind
	s.visual_only = true
	s.splash = splash
	var e = Network.enemies.get(target_id)
	if e != null and is_instance_valid(e) and not e.dead:
		s.target = e
	s.aim_point = target_pos + Vector3.UP * 0.7
	c.add_child(s)
	s.global_position = from
	match kind:
		"ball":
			Sfx.play_at("explode", from, 0.15, -10.0)
		"bolt":
			Sfx.play_at("zap", from, 0.15, -10.0)
		_:
			Sfx.play_at("swing", from, 0.25, -14.0)


@rpc("authority", "call_remote", "reliable")
func _city_xp(kind: String, xp: int) -> void:
	if Enemy.TYPES.has(kind):
		Game.on_enemy_killed(kind, maxi(0, xp))


@rpc("authority", "call_remote", "reliable")
func _city_reward(n: int, gold: int, xp: int, chest: bool) -> void:
	Game.add_gold(gold)
	Game.add_xp(xp)
	Game.flags["city_best"] = maxi(int(Game.flags.get("city_best", 0)), n)
	Game.notify.emit("Noite %d vencida! Recompensa: +%d ouro e +%d XP para o seu personagem." % [n, gold, xp], Color(1, 0.85, 0.35))
	Sfx.play("quest", 0.0, -2.0)
	save_character()
	if city and city.has_method("on_reward"):
		city.on_reward(n, gold, xp, chest)


# ---------------------------------------------------------------- baús e fantasmas (cliente)
@rpc("authority", "call_remote", "reliable")
func _city_chest_add(id: int, n: int, x: float, z: float, rarity: String, count: int) -> void:
	if city and city.has_method("on_chest_add"):
		city.on_chest_add(id, n, x, z, rarity, count)


@rpc("authority", "call_remote", "reliable")
func _city_chest_del(id: int) -> void:
	if city and city.has_method("on_chest_del"):
		city.on_chest_del(id)


@rpc("authority", "call_remote", "reliable")
func _city_chest_fx(id: int, pid: int) -> void:
	if city and city.has_method("on_chest_fx"):
		city.on_chest_fx(id, pid)


@rpc("authority", "call_remote", "reliable")
func _city_chest_loot(id: int, items: Array, ok: bool) -> void:
	if city and city.has_method("on_chest_loot"):
		city.on_chest_loot(id, _clean_items(items), ok)


@rpc("authority", "call_remote", "reliable")
func _city_chest_given(id: int, given: Array, left: Array) -> void:
	_receive_items(_clean_items(given))
	if city and city.has_method("on_chest_given"):
		city.on_chest_given(id, _clean_items(given), _clean_items(left))


## Itens que ficaram no baú quando você saiu da cidade (ou a partida acabou).
@rpc("authority", "call_remote", "reliable")
func _city_chest_auto(items: Array) -> void:
	var list := _clean_items(items)
	if list.is_empty():
		return
	_receive_items(list, true)
	var names: Array[String] = []
	for id in list:
		if id != "health_potion":
			names.append(str(ItemDB.ITEMS[id].name))
	var extra := (": " + ", ".join(names)) if not names.is_empty() else ""
	Game.notify.emit("O que você deixou no baú foi para a mochila%s." % extra, Color(1, 0.85, 0.35))


@rpc("authority", "call_remote", "unreliable_ordered", 4)
func _city_ghost_of(pid: int, kind: String, x: float, z: float, rot: float, ok: bool, target: int) -> void:
	if city and city.has_method("on_remote_ghost"):
		city.on_remote_ghost(pid, kind, x, z, rot, ok, target)


static func _clean_items(items: Array) -> Array:
	var out: Array = []
	for id in items:
		if ItemDB.ITEMS.has(str(id)):
			out.append(str(id))
	return out


func _receive_items(items: Array, silent := false) -> void:
	if items.is_empty():
		return
	for id in items:
		Game.add_item(str(id), 1, silent)
	save_character()


@rpc("authority", "call_remote", "reliable")
func _city_over(info: Dictionary) -> void:
	last_result = info
	changed.emit()
	Game.flags["city_best"] = maxi(int(Game.flags.get("city_best", 0)), int(info.get("nights", 0)))
	save_character()
	if city and city.has_method("show_results"):
		city.show_results(info)
