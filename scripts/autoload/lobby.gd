extends Node
## Navegação entre a praça, Valdoria e a cidade, e a Defesa da Cidade em grupo.
##
## Ao entrar no servidor (e no solo, pelo menu) o jogador cai na praça da cidade (hub.tscn, autoload Hub):
## de lá segue a estrada para Valdoria (o mundo do RPG), entra no portal da Horda ou abre/entra na sala da
## Defesa da Cidade cooperativa.
##
## A cidade em grupo roda no servidor dentro de um SubViewport com mundo 3D próprio (física separada
## de Valdoria, que continua rodando). O servidor simula tudo (Colony role "server"): economia, ondas,
## torres, soldados e animais. Cada cliente carrega colony.tscn com role "client" e recebe réplicas:
## construções, soldados e animais por aqui; os monstros pela replicação normal do Network (zona "city").
## As ações dos jogadores (construir, melhorar, recrutar...) viram pedidos que o servidor valida.
## Todas as RPCs da sala e da cidade passam por este autoload (/root/Lobby existe igual em todos os peers).

signal changed   # cliente: sala, recorde ou lista de jogadores mudou

const HUB_SCENE := "res://scenes/hub.tscn"
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
## Resultado da última partida (mostrado na praça ao voltar).
var last_result := {}
## Cliente: a cena da cidade que está carregando deve entrar como réplica.
var joining_city := false
var city_seed := 0
## Cliente: colony_world (role "client") em uso.
var city: Node = null
## Onde o personagem estava em Valdoria (a praça guarda ao montar; go_world devolve ao Game.spawn_position).
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
## Recorde da Defesa: vem do banco (CharacterService.records().city, persiste entre deploys) na subida do
## servidor e depois de cada partida; durante a partida sobe com as noites vencidas (_update_record).
var _record := {"day": 0, "names": []}
var _record_loaded := false
var _present := {}              # peers que estavam na cidade quando a noite começou
## peer -> {"gold", "xp", "items": [], "account", "nights"} somado na partida (nights: noites em que estava presente)
var _rewards := {}
## Registro da partida em runs (CharacterService.start_run) e o bônus da base fixado no começo dela.
var _run_id := 0
var _bonus := {}
## Duração do dia na cidade (--city-day=SEG encurta para os testes).
var city_day_time := ColonyData.DAY_LENGTH
var city_first_bonus := ColonyData.FIRST_DAY_BONUS


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--city-day="):
			city_day_time = maxf(5.0, float(a.substr(11)))
			city_first_bonus = 0.0


# ================================================================ cliente: navegação
## O servidor aceitou a conexão: todo mundo chega pela praça.
func on_accepted() -> void:
	_last_world_pos = Game.spawn_position
	_last_world_yaw = Game.spawn_yaw
	last_result = {}
	get_tree().change_scene_to_file(HUB_SCENE)


## Está na praça ou na cidade em grupo (para a desconexão voltar ao menu).
func in_session() -> bool:
	var s := get_tree().current_scene
	return s != null and (s.get("role") == "hub" or s.get("role") == "client")


## Da praça para Valdoria (a estrada; o portal da Horda passa por Hub.go_horde).
func go_world() -> void:
	joining_city = false
	# a praça deixa de ser o mundo do cliente já agora: quem espera Valdoria montar (Network.world) não a
	# confunde com a praça que ainda está na tela até a troca de cena
	if Network.world != null and Network.world.get("role") == "hub":
		Network.world_closed(Network.world)
	if Game.hp <= 0.0:
		Game.hp = Game.max_hp()
	Game.spawn_position = _last_world_pos
	Game.spawn_yaw = _last_world_yaw
	get_tree().paused = false
	get_tree().change_scene_to_file(WORLD_SCENE)


## De Valdoria, da Horda ou da cidade de volta à praça (online e solo; salva o personagem antes).
## save_pos = false: não grava onde o jogador está (a arena da Horda que veio da praça; vale o de antes).
func go_hub(save_pos := true) -> void:
	var w := get_tree().current_scene
	if save_pos and w != null and w.get("role") == null and w.get("player") != null and is_instance_valid(w.player):
		var p: Player = w.player
		if not p.dead and not Game.run_mods.get("active", false):
			_last_world_pos = p.global_position
			_last_world_yaw = p.model.rotation.y
	save_character()
	Game.reset_run_mods()
	Hub.pending_horde = false
	Hub.horde_return = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(HUB_SCENE)


## Manda vida/mana e a última posição em Valdoria ao servidor (a cidade não muda onde ele está no RPG).
func save_character() -> void:
	if Game.run_mods.get("active", false):
		return
	if _last_world_pos == null and not Network.is_online():
		return   # solo sem posição guardada (cidade aberta direto do menu): o solo.db já tem a dele
	var pos: Vector3 = _last_world_pos if _last_world_pos != null else VILLAGE_SPAWN
	Econ.report_vitals(pos, _last_world_yaw)


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
	if not _record_loaded and Network.characters != null:
		_record_loaded = true
		_load_record()
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


# ---------------------------------------------------------------- sala (servidor)
@rpc("any_peer", "call_remote", "reliable")
func _room_msg(kind: String) -> void:
	var id := _sender()
	if id == 0:
		return
	var in_hub := Network.zone_of(id) == "hub"
	match kind:
		"create", "join":
			if not in_hub:
				return
			if _room.is_empty():
				_room = {"state": "open", "leader": id, "members": {id: false}, "names": {id: _name(id)}, "seed": 0}
				print("[server] %s abriu a sala da Defesa da Cidade" % _name(id))
				_hub_say("%s abriu uma sala da Defesa da Cidade em grupo." % _name(id), Color(1, 0.85, 0.5))
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


## Entrar na partida em andamento (direto da praça).
func _room_msg_enter(id: int) -> void:
	if _room.is_empty() or _room.state != "running" or _city == null:
		return
	if Network.zone_of(id) != "hub":
		return
	if Network.zone_peers("city").size() >= ColonyData.COOP_MAX_PLAYERS:
		_notice.rpc_id(id, "A cidade está cheia (%d jogadores)." % ColonyData.COOP_MAX_PLAYERS)
		return
	_room.members[id] = true
	_room.names[id] = _name(id)
	_reward_acc(id)   # quem entra no meio também fecha a partida (Ecos pelas noites em que esteve)
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


func _hub_say(text: String, color: Color) -> void:
	for pid in Network.zone_peers("hub"):
		_city_say.rpc_id(pid, text, color)


func _start_city() -> void:
	var seed := randi() % 1000000 + 1
	_room.state = "running"
	_room.seed = seed
	for pid in _room.members:
		_room.members[pid] = true
	_present.clear()
	_rewards.clear()
	var accounts: Array = []
	for pid in _room.members:
		_reward_acc(pid)
		if int(_rewards[pid].account) > 0:
			accounts.append(int(_rewards[pid].account))
	_run_id = 0
	_bonus = {}
	if Network.characters != null:
		_run_id = Network.characters.start_run("city", accounts)
		_bonus = Network.characters.base_bonus()   # fixado agora: doações no meio da partida não mudam
	_vp = SubViewport.new()
	_vp.own_world_3d = true          # física e mundo separados de Valdoria
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	_city = load(COLONY_SCENE).instantiate()
	_city.role = "server"
	_city.map_seed = seed
	_city.coop_players = _room.members.size()
	_city.base_bonus = _bonus
	_vp.add_child(_city)
	print("[server] Defesa da Cidade em grupo começou (%d jogadores, mapa %d)" % [_room.members.size(), seed])
	for pid in _room.members:
		_city_go.rpc_id(pid, seed)
	_hub_say("A Defesa da Cidade começou! Quem estiver na praça ainda pode entrar.", Color(1, 0.85, 0.5))


## Um jogador saiu da cidade (voltou à praça, caiu a conexão...).
func server_city_left(id: int) -> void:
	_present.erase(id)
	if _room.is_empty():
		return
	_room.members.erase(id)
	if _room.state == "running" and _colony() != null:
		_colony().say("%s saiu da cidade." % _name(id), Color(0.8, 0.8, 0.9))
	if _room.members.is_empty() or (_room.state == "running" and Network.zone_peers("city").is_empty()
			and _room.members.keys().all(func(pid) -> bool: return Network.zone_of(pid) != "hub")):
		if _room.state == "running":
			_end_city("abandon", [id])   # quem saiu por último também vê o resumo na praça
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
	var names: Array = []
	for pid in _room.get("names", {}):
		names.append(_room.names[pid])
	print("[server] Defesa da Cidade terminou (%s): %d noites, %d abates" % [reason, nights, kills])
	var to: Array = Network.zone_peers("city")
	for pid in extra_peers:
		if Network.players.has(pid) and not (pid in to):
			to.append(pid)
	var ecos := _city_summaries(nights, to)
	if _run_id > 0 and Network.characters != null:
		Network.characters.close_run(_run_id, nights, {"reason": reason, "kills": kills})
	_run_id = 0
	_update_record(nights)
	_load_record()
	Hub.server_records_changed()
	for pid in to:
		var r: Dictionary = _rewards.get(pid, {"gold": 0, "xp": 0, "items": []})
		_city_over.rpc_id(pid, {"reason": reason, "nights": nights, "kills": kills, "gold": r.gold, "xp": r.xp,
			"items": r.items, "names": names, "record": _record.day, "ecos": int(ecos.get(pid, 0))})
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


## Fim da partida de cada conta que passou pela cidade (CharacterService.finish_player: Ecos pelas
## noites em que esteve presente e uma linha no registro — as concessões da noite não são registradas
## uma a uma) e o recorde de noites no personagem de quem viu o fim. Devolve peer -> Ecos ganhos.
## Por conta, não por peer: quem caiu e voltou no meio da partida tem dois peers e fecha uma vez só, somado.
func _city_summaries(nights: int, to: Array) -> Dictionary:
	var out := {}
	if Network.characters == null:
		return out
	var by_account := {}   # conta -> {"gold", "xp", "items": {id: n}, "nights", "peers": []}
	for pid in _rewards:
		var r: Dictionary = _rewards[pid]
		var account := int(r.get("account", 0))
		if account <= 0:
			continue
		if not by_account.has(account):
			by_account[account] = {"gold": 0, "xp": 0, "items": {}, "nights": 0, "peers": []}
		var t: Dictionary = by_account[account]
		t.gold += int(r.gold)
		t.xp += int(r.xp)
		t.nights += int(r.get("nights", 0))
		t.peers.append(pid)
		for id in r.items:
			t.items[id] = int(t.items.get(id, 0)) + 1
	for account in by_account:
		var t: Dictionary = by_account[account]
		var res: Dictionary = Network.characters.finish_player(_run_id, account, "city", int(t.nights),
			int(t.gold), int(t.xp), t.items, {})
		var n := 0
		for e in Econ.events_of(res):
			if e is Dictionary and e.get("t") == "ecos":
				n = int(e.get("n", 0))
		for pid in t.peers:
			out[pid] = n
			Econ.server_push(pid, res)   # só chega a quem ainda está conectado
	for pid in to:
		Econ.server_record(pid, "city_best", nights)
	return out


## Acumulado da partida do peer (criado na primeira vez, com a conta: quem cair ainda fecha a partida).
func _reward_acc(pid: int) -> Dictionary:
	if not _rewards.has(pid):
		_rewards[pid] = {"gold": 0, "xp": 0, "items": [], "account": Econ.account_of(pid), "nights": 0}
	return _rewards[pid]


## Servidor: recorde da Defesa a partir das partidas registradas (persiste entre deploys).
func _load_record() -> void:
	if Network.characters == null:
		return
	var rec: Dictionary = Network.characters.records().get("city", {})
	if int(rec.get("reached", 0)) > 0:
		_record = {"day": int(rec.reached), "names": (rec.get("names", []) as Array).duplicate()}


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
	_reward_acc(id)
	Network.server_set_zone(id, "city")
	c.team_size = city_team_size()
	var full := c.net_full()
	full["bonus"] = c.base_bonus   # o cliente aplica antes das construções (vida da prefeitura)
	_city_full.rpc_id(id, full)
	Network.send_zone_enemies(id, "city")
	for e in c.live_enemies():
		if e.affix != "" and e.net_id != 0:
			_city_enemy_meta.rpc_id(id, e.net_id, e.affix)
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
			Econ.server_kill(pid, e.kind, xp)
			_city_xp.rpc_id(pid, e.kind, xp)


func city_night_started() -> void:
	_present.clear()
	for pid in Network.zone_peers("city"):
		_present[pid] = true


## Amanheceu depois da noite n: cada jogador que segurou a noite ganha ouro e XP no próprio personagem;
## nas noites de chefe, um baú com equipamento (raridade sobe com a noite).
func city_night_survived(n: int) -> void:
	var rw := ColonyData.night_reward(n)
	for pid in Network.zone_peers("city"):
		if not _present.has(pid):
			continue
		var items := ColonyData.night_chest(n)
		var acc := _reward_acc(pid)
		acc.nights = int(acc.get("nights", 0)) + 1
		var got := {}
		for id in items:
			got[id] = int(got.get(id, 0)) + 1
		# o servidor concede no personagem (resumo da partida no fim, em _end_city) e só depois avisa
		var r := Econ.server_grant(pid, int(rw.gold), int(rw.xp), got, "city_night", 0, true)
		if r.ok:
			acc.gold += int(rw.gold)
			acc.xp += int(rw.xp)
			acc.items.append_array(items)
		Econ.server_record(pid, "city_best", n)
		_city_reward.rpc_id(pid, n, int(rw.gold), int(rw.xp), items)
	_update_record(n)
	_broadcast_room()


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
		go_hub()


@rpc("authority", "call_remote", "reliable")
func _city_full(d: Dictionary) -> void:
	var c := _colony()
	if c == null:
		return
	# bônus da base fixado pelo servidor no começo da partida (antes das construções: vida da prefeitura)
	if d.get("bonus") is Dictionary:
		c.base_bonus = (d.bonus as Dictionary).duplicate()
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
func _city_xp(_kind: String, _xp: int) -> void:
	# o XP e o abate chegam pelo Econ (estado do servidor); aqui só o efeito do cliente
	Game.kill_lifesteal()


@rpc("authority", "call_remote", "reliable")
func _city_reward(n: int, gold: int, xp: int, items: Array) -> void:
	# o servidor já concedeu (ouro, XP, baú e recorde chegam pelo Econ): aqui só o aviso
	var got: Array[String] = []
	for id in items:
		if ItemDB.ITEMS.has(str(id)) and str(id) != "health_potion":
			got.append(ItemDB.ITEMS[str(id)].name)
	Game.notify.emit("Noite %d vencida! Recompensa: +%d ouro e +%d XP para o seu personagem." % [n, gold, xp], Color(1, 0.85, 0.35))
	if not got.is_empty():
		Game.notify.emit("Baú da noite %d: %s!" % [n, ", ".join(got)], ItemDB.rarity_color(str(items[0])))
	Sfx.play("quest", 0.0, -2.0)
	save_character()
	if city and city.has_method("on_reward"):
		city.on_reward(n, gold, xp, items)


@rpc("authority", "call_remote", "reliable")
func _city_over(info: Dictionary) -> void:
	last_result = info
	changed.emit()
	save_character()   # o recorde de noites vem do servidor (estado do personagem)
	if city and city.has_method("show_results"):
		city.show_results(info)
