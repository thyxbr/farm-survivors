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
## Cliente: chegou a lista de personagens da conta (tela de seleção). `created` = id recém-criado (0 = nenhum).
signal char_list_changed(list: Array, created: int, err: String)
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
const ATTACK_KINDS := ["swing", "lunge", "slam", "shoot", "fuse", "cast", "web", "tongue"]
const SNAP_STRIDE := 10   # id, x, y, z, yaw, hp, state, attack_timer, attack_kind, flags
## Tempo da fila do Desafio da Horda (cai para HORDE_LOBBY_ALL quando todos já responderam).
const HORDE_LOBBY_TIME := 15.0
const HORDE_LOBBY_ALL := 3.0
## Quem aceitou o convite ainda carregando Valdoria: a partida espera por ele de HORDE_TRAVEL_STEP em
## HORDE_TRAVEL_STEP segundos, até HORDE_TRAVEL_WAIT no total; quem não chegou fica fora.
const HORDE_TRAVEL_WAIT := 12.0
const HORDE_TRAVEL_STEP := 0.5
## Chat: tamanho máximo da mensagem e limite de mensagens por janela de tempo (anti-spam).
const CHAT_MAX := 120
const CHAT_BURST := 5
const CHAT_WINDOW := 6.0

enum Mode { OFFLINE, SERVER, CLIENT }

var mode := Mode.OFFLINE
var port := DEFAULT_PORT
## peer_id -> {"name": String (nome da conta), "account": int, "char": int (personagem), "admin": bool, "look": Dictionary (espaço -> item),
## "ready": bool, "zone": String}
var players := {}
var my_name := ""
## Personagens por conta (tela de seleção; cabem em volta da fogueira).
const MAX_CHARACTERS := 4
const CHAR_SELECT_SCENE := "res://scenes/char_select.tscn"
## Cliente: token da sessão (do Auth.login) mandado no _register.
var my_token := ""
## Cliente: endereço da última conexão (join), para voltar à seleção de personagem (rejoin).
var my_address := ""
## Mensagem mostrada no menu principal depois de uma desconexão.
var last_error := ""
var world: Node = null
var enemies := {}         # net_id -> Enemy (servidor: reais; cliente: réplicas)
var remote_players := {}  # peer_id -> Player (réplica)
## Servidor: última posição recebida de cada jogador na zona atual (coleta de pickups confere a distância).
var last_pos := {}        # peer_id -> Vector3
var _last_heal := {}      # peer_id -> instante (s) da última Cura de healer aceita
var _last_ally := {}      # peer_id -> {id da habilidade: instante (s)} do último buff em aliados aceito

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
var _shut_down := false   # servidor: personagens já gravados na saída

## Servidor: contas logadas que ainda estão na tela de seleção de personagem (fora de `players`).
## peer_id -> {"name", "account", "admin"}
var _selecting := {}
## Cliente: personagens da conta (o último _char_list do servidor).
var char_list: Array = []
## Cliente: nome da conta logada (vem com a lista de personagens; no jogo aparece o nome do herói).
var account_name := ""
## Cliente: id do personagem que o servidor acabou de criar (a seleção abre com ele escolhido; 0 = nenhum).
var char_created := 0

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
	if OS.get_environment("DB_REQUIRE_MOUNT") == "1" and not _db_dir_is_mounted():
		get_tree().quit(1)
		return
	db = Db.open(db_path)
	if db == null:
		printerr("[server] não foi possível abrir o banco em %s" % db_path)
		get_tree().quit(1)
		return
	if http_port < 1 or http_port > 65535:
		printerr("[server] porta HTTP inválida: %d (use 1-65535)" % http_port)
		get_tree().quit(1)
		return
	if not Migrations.ensure_latest(db):
		printerr("[server] migração do banco %s falhou (ou o banco é de uma versão mais nova): não subo" % db_path)
		get_tree().quit(1)
		return
	accounts = AccountStore.new(db, admin_users)
	characters = CharacterService.new(SqliteCharStore.new(db), Balance.tables)
	characters.allow_reclass = "--test" in OS.get_cmdline_user_args()
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


## DB_REQUIRE_MOUNT=1 (imagem Docker): a pasta do banco tem que ser um volume montado (/proc/mounts),
## senão o banco ficaria na camada do container e o próximo deploy apagaria todas as contas.
func _db_dir_is_mounted() -> bool:
	var dir := ProjectSettings.globalize_path(db_path).get_base_dir()
	var mounts := Mounts.read_proc_mounts()
	if mounts.is_empty():
		var out := []
		OS.execute("cat", ["/proc/mounts"], out)
		mounts = "".join(out)
	if Mounts.is_mount_point(dir, mounts):
		return true
	printerr("[server] DB_REQUIRE_MOUNT=1 e a pasta do banco (%s) não é um volume montado: monte um volume em %s " % [dir, dir]
		+ "(no Easypanel: Mounts → Volume em /data) ou rode com DB_REQUIRE_MOUNT=0 para testar sem guardar as contas")
	return false


## Servidor desligando (pedido de fechar ou saída da árvore no quit): grava todos os personagens em memória.
## Idempotente (pode vir do pedido de fechar e da saída da árvore).
func _server_shutdown() -> void:
	if characters == null or _shut_down:
		return
	_shut_down = true
	var n := characters.save_all()
	print("[server] desligando: %d personagem(ns) gravado(s)" % n)


func _exit_tree() -> void:
	if is_server():
		_server_shutdown()


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
	_selecting.erase(id)
	_chat_log.erase(id)
	Econ.server_peer_gone(id)
	if is_server() and players.has(id):
		print("[server] %s saiu (%d online)" % [players[id].name, players.size() - 1])
		_drop_player(id)


## Servidor: tira o jogador do jogo (saiu ou foi substituído por uma conexão nova da mesma conta).
func _drop_player(id: int) -> void:
	var char_id := int(players[id].get("char", 0))
	players.erase(id)
	last_pos.erase(id)
	_last_heal.erase(id)
	_last_ally.erase(id)
	_remove_remote_player(id)
	for pid in _all_peers():
		_player_left.rpc_id(pid, id)
	players_changed.emit()
	_horde_peer_gone(id)
	Party.server_peer_gone(id)
	if characters != null and char_id > 0:
		# por sessão: a queda tardia de uma conexão velha não descarrega a sessão nova
		characters.unload(char_id, id)


@rpc("any_peer", "call_remote", "reliable")
## Assinatura estável entre versões: (token, versão, visual, extra). O 1º argumento já foi o nome digitado
## (também texto); os dois últimos ficam sem tipo para que um cliente de versão antiga (que mandava arma e
## armadura como texto) ainda chegue à checagem de versão e receba a mensagem "atualize o jogo" em vez de
## um erro de RPC. Não mude a quantidade de argumentos.
func _register(token: String, client_version: String, _look = {}, _extra = "") -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id) or _selecting.has(id):
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
	# uma sessão por conta: a conexão antiga (jogando ou ainda na seleção) cai antes de aceitar a nova
	for old in players.keys() + _selecting.keys():
		var info: Dictionary = players.get(old, _selecting.get(old, {}))
		if int(info.get("account", 0)) == account:
			print("[server] %s entrou de novo (peer %d): derrubando o peer %d" % [acc.name, id, old])
			if players.has(old):
				_drop_player(old)
			_selecting.erase(old)
			_rejected.rpc_id(old, "Sua conta entrou no jogo em outro lugar. Esta conexão foi encerrada.")
			_kick_later(old)
	# a conta fica na tela de seleção (fora do jogo) até escolher um personagem (_char_req "enter")
	_selecting[id] = {"name": str(acc.name), "account": account, "admin": bool(acc.get("is_admin", false))}
	print("[server] %s na seleção de personagem (peer %d, conta %d)" % [acc.name, id, account])
	Econ.server_send_balance(id)
	_char_list.rpc_id(id, characters.list_characters(account), 0, "", str(acc.name))


# ---------------------------------------------------------------- seleção de personagem
## Pedido da tela de seleção: "create" [nome, classe, corpo], "delete" [id] ou "enter" [id]. Só para quem está
## na seleção; o personagem precisa ser da conta. Responde com a lista nova (_char_list).
@rpc("any_peer", "call_remote", "reliable")
func _char_req(op: String, args: Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_server() or not _selecting.has(id) or characters == null:
		return
	var account := int(_selecting[id].account)
	var acc_name := str(_selecting[id].name)
	var list := characters.list_characters(account)
	match op:
		"create":
			if args.size() != 3 or not (args[0] is String) or not (args[1] is String) or not (args[2] is String):
				return
			if list.size() >= MAX_CHARACTERS:
				_char_list.rpc_id(id, list, 0, "Você já tem %d personagens. Exclua um para criar outro." % MAX_CHARACTERS,
					acc_name)
				return
			var r := characters.create_character(account, args[0], args[1], args[2])
			if r.ok:
				print("[server] %s criou o personagem %d: %s (%s)" % [acc_name, r.id, characters.name_of(r.id), args[1]])
			_char_list.rpc_id(id, characters.list_characters(account), int(r.id),
				"" if r.ok else CharacterService.explain_create(str(r.err)), acc_name)
		"delete":
			if args.size() != 1 or not (args[0] is int):
				return
			var ok := characters.delete_character(account, args[0])
			_char_list.rpc_id(id, characters.list_characters(account), 0,
				"" if ok else "Não deu para excluir o personagem.", acc_name)
		"enter":
			if args.size() != 1 or not (args[0] is int):
				return
			if characters.owner_of(args[0]) != account or not list.any(func(e: Dictionary) -> bool: return int(e.id) == args[0]):
				_char_list.rpc_id(id, list, 0, "Personagem não encontrado.", acc_name)
				return
			_enter_world(id, args[0])


## Servidor: a conta da seleção entra no jogo com o personagem `char_id` (o que o _register fazia antes).
func _enter_world(id: int, char_id: int) -> void:
	var sel: Dictionary = _selecting[id]
	_selecting.erase(id)
	characters.set_session(char_id, id)
	# o visual vem do personagem guardado no servidor (o `look` do cliente fica só pela assinatura estável)
	var char_look: Dictionary = characters.load_or_create(char_id).equipment
	# no jogo aparece o nome do herói (chat, nome em cima, grupo, Horda); sem nome, o da conta
	var shown := characters.name_of(char_id)
	if shown == "":
		shown = str(sel.name)
	# zona "loading" até o cliente terminar de carregar Valdoria (_client_ready); "ready" = já carregou
	players[id] = {"name": shown, "account": int(sel.account), "char": char_id, "admin": bool(sel.admin),
		"look": _clean_look(char_look, char_id), "ready": false, "zone": "loading"}
	print("[server] %s entrou com %s (personagem %d, peer %d, conta %d, %d online)" % [sel.name, shown, char_id, id,
		sel.account, players.size()])
	# tabelas e personagem antes do _accepted (mesmo canal confiável: chegam antes da troca de cena)
	Econ.server_send_initial(id, char_id)
	Weather.server_send_clock(id)   # estação, hora do jogo e clima pelo relógio do servidor
	_accepted.rpc_id(id, players)
	for pid in _all_peers():
		if pid != id:
			_player_joined.rpc_id(pid, id, players[id])
	players_changed.emit()


## Cliente: lista de personagens da conta (chega depois do login e a cada criar/excluir).
## `created` = id do personagem que acabou de ser criado (0 = nenhum); `err` = aviso para a tela;
## `account` = nome da conta (a seleção mostra).
@rpc("authority", "call_remote", "reliable")
func _char_list(list: Array, created: int, err: String, account: String) -> void:
	_connect_t = 0.0
	char_list = list
	account_name = account
	if is_client() and _auto_pick_character(list, created, err):
		return
	if created > 0:
		char_created = created
	char_list_changed.emit(list, created, err)
	# fora da seleção (menu principal depois do login, tela de criação depois de criar): abre a seleção.
	# Erro na tela de criação fica nela (a tela mostra o aviso).
	var scene := get_tree().current_scene
	if err == "" and (scene == null or scene.scene_file_path != CHAR_SELECT_SCENE):
		Loading.go(CHAR_SELECT_SCENE)


## Testes e demos (Game.harness_class): sem tela, entra no primeiro personagem ou cria um com a classe pedida.
func _auto_pick_character(list: Array, created: int, err: String) -> bool:
	if Game.skip_auto_class:
		return false
	var pick := Game.harness_class(OS.get_cmdline_user_args())
	if pick[0] == "":
		return false
	if created > 0:
		char_enter(created)
	elif not list.is_empty():
		char_enter(int(list[0].id))
	elif err == "":
		char_create(account_name, pick[0], pick[1])   # o herói dos testes leva o nome da conta
	else:
		_fail(err)
	return true


## Cliente: pedidos da tela de seleção.
func char_create(name: String, cls: String, body: String) -> void:
	if is_client():
		_char_req.rpc_id(1, "create", [name, cls, body])


func char_delete(char_id: int) -> void:
	if is_client():
		_char_req.rpc_id(1, "delete", [char_id])


func char_enter(char_id: int) -> void:
	if is_client():
		_char_req.rpc_id(1, "enter", [char_id])


## O cliente terminou de carregar Valdoria (o mundo do RPG).
@rpc("any_peer", "call_remote", "reliable")
func _client_ready() -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_server() or not players.has(id):
		return
	# personagem sem classe não entra em zona nenhuma: o cliente legítimo passa antes pela tela de criação
	# (choose_class pelo Econ) e só carrega Valdoria depois; fica em "loading" até escolher
	if not server_has_class(id):
		_horde_notice.rpc_id(id, "Escolha sua classe antes de entrar no mundo.")
		return
	server_set_zone(id, "world")
	# quem entrou enquanto este jogador carregava o mapa não foi anunciado para ele: manda todos agora
	for pid in players:
		if pid != id:
			_player_joined.rpc_id(id, pid, players[pid])
	send_zone_enemies(id)
	Hub.server_send_state(id)   # recordes (o mestre das passivas e o quadro da vila mostram)
	if not _lobby.is_empty():
		_horde_lobby.rpc_id(id, _lobby_state())


# ---------------------------------------------------------------- zonas ("loading" e Valdoria)
## Servidor: o jogador mudou de zona ("loading" ou "world"). Sai da anterior e avisa todos.
func server_set_zone(id: int, zone: String) -> void:
	if not players.has(id):
		return
	var old: String = players[id].get("zone", "loading")
	_remove_remote_player(id)
	last_pos.erase(id)   # outra zona, outras coordenadas
	players[id].zone = zone
	players[id].ready = true
	if old != zone:
		print("[server] %s: %s -> %s" % [players[id].name, old, zone])
		if old == "world":
			_horde_peer_gone(id)
		Econ.server_peer_zone_left(id, old)
	for pid in _all_peers():
		_player_zone.rpc_id(pid, id, zone)
	players_changed.emit()


## Servidor: o personagem guardado da conta do peer já tem classe (sem classe não entra em modo nenhum).
func server_has_class(id: int) -> bool:
	if not players.has(id) or characters == null:
		return false
	var char_id := int(players[id].get("char", 0))
	return char_id > 0 and characters.load_or_create(char_id).char_class != ""


## Servidor: a réplica do jogador está caída (flag NF_DEAD do último estado que ele mandou).
func server_peer_dead(id: int) -> bool:
	var rp: Player = remote_players.get(id)
	return rp != null and is_instance_valid(rp) and rp.dead


func zone_of(id: int) -> String:
	return str(players[id].get("zone", "loading")) if players.has(id) else ""


## Servidor: jogadores conectados que já carregaram a zona.
func zone_peers(zone: String) -> Array:
	var out := []
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	for pid in players:
		if not players[pid].ready or players[pid].get("zone", "loading") != zone:
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


## Servidor: manda ao jogador os inimigos vivos de Valdoria.
func send_zone_enemies(id: int) -> void:
	for net_id in enemies:
		var e: Enemy = enemies[net_id]
		if is_instance_valid(e) and not e.dead:
			_enemy_spawned.rpc_id(id, net_id, e.kind, e.global_position, e.model.rotation.y, e.max_hp, e.hp, _enemy_flags(e), e.level,
				e.area)


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
		if not players[pid].ready or players[pid].get("zone", "loading") != "world":
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
			# tempo de script por quadro (ms): o servidor trava em 60 fps, então o fps só cai quando já passou do limite
			print("[server] %d online, %d inimigos, %d fps, %d snapshots/s, process %.2f ms, physics %.2f ms" % [
				players.size(), enemies.size(), Engine.get_frames_per_second(), int(_snapshots_sent / _stats_t),
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
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
	enemies[e.net_id] = e
	for pid in _enemy_peers(e):
		_enemy_spawned.rpc_id(pid, e.net_id, e.kind, e.global_position, e.model.rotation.y, e.max_hp, e.hp, _enemy_flags(e), e.level,
			e.area)


## Bits do spawn: 1 = horda, 2 = elite (da horda ou do mundo).
static func _enemy_flags(e: Enemy) -> int:
	return (1 if e.horde else 0) | (2 if e.elite else 0) | (4 if e.chief else 0)


## Quem vê os inimigos: os jogadores em Valdoria.
func _enemy_peers(_e: Enemy) -> Array:
	return _ready_peers()


func unregister_enemy(e: Enemy) -> void:
	if enemies.get(e.net_id) == e:
		enemies.erase(e.net_id)


func server_enemy_killed(e: Enemy) -> void:
	var pos := e.global_position
	if not e.horde:
		# a horda não dá XP/loot do RPG: as gemas vêm pelo _horde_kill do modo sobrevivência.
		# Cada jogador que acertou ganha o próprio sorteio de loot. O XP é dividido com o grupo de quem
		# acertou (em Valdoria) e o abate conta na missão de quem está perto do combate (PartyRules).
		var hitters: Array = []
		for pid in e.contributors:
			if players.has(pid) and zone_of(pid) == "world":
				hitters.append(pid)
		var rewards := Party.server_kill_rewards(e.xp_reward(), hitters, pos, "world")
		# em grupo, a diferença de nível usa o maior nível entre quem recebe do mesmo grupo
		# (um estranho de nível alto que só acertou o monstro não derruba o XP de ninguém)
		var levels := {}
		for pid in rewards:
			levels[pid] = Party._level(pid)
		var group_levels := PartyRules.group_levels(rewards.keys(), Party.book.teams(), levels)
		for pid in rewards:
			if not players.has(pid):
				continue
			var r: Dictionary = rewards[pid]
			var group_level := int(group_levels.get(pid, 1))
			if r.kill:
				Econ.server_kill(pid, e.kind, int(r.xp), e.level, group_level, e.area)
			elif int(r.xp) > 0:
				# quem está longe também leva o ajuste de nível (o abate perto o aplica em CharRules.kill)
				var far_xp := int(r.xp)
				if e.level > 0:
					far_xp = int(round(far_xp * ProgressionRules.xp_diff_mult(Balance.tables, e.level, group_level)))
				Econ.server_grant(pid, 0, far_xp, {}, "party_xp", 0, false,
					[{"t": "notify", "text": "+%d XP do grupo (longe demais para contar na missão)" % far_xp,
						"color": Color(0.7, 0.85, 1.0)}])
			if r.loot:
				Econ.server_drop_loot(pid, e.kind, pos, "world", e.level, e.elite, e.chief)
				_kill_reward.rpc_id(pid, e.kind, int(r.xp), pos)
	for pid in _enemy_peers(e):
		_enemy_died.rpc_id(pid, e.net_id)


## Monstro abatido pela guarda da vila (Enemy.guard_kill): ninguém ganha nada, as réplicas só veem a morte.
func server_enemy_guard_killed(e: Enemy) -> void:
	for pid in _enemy_peers(e):
		_enemy_guarded.rpc_id(pid, e.net_id)


## Inimigo que some sem morrer (guarda de covil que voltou a dormir): sem recompensa, só sai das réplicas.
func server_enemy_despawn(e: Enemy) -> void:
	if e.net_id == 0:
		return
	for pid in _enemy_peers(e):
		_enemy_gone.rpc_id(pid, e.net_id)
	unregister_enemy(e)


func _send_enemy_snapshot() -> void:
	if enemies.is_empty():
		return
	var snap_world := PackedFloat32Array()
	for net_id in enemies:
		var e: Enemy = enemies[net_id]
		if not is_instance_valid(e) or e.dead:
			continue
		var p := e.global_position
		var flags := (1 if e.slow_timer > 0 else 0) | (2 if e.enraged else 0)
		var row := [net_id, p.x, p.y, p.z, e.model.rotation.y, e.hp,
			max(0, STATES.find(e.state)), e.attack_timer, max(0, ATTACK_KINDS.find(e.attack_kind)), flags]
		snap_world.append_array(row)
	if snap_world.is_empty():
		return
	var peers := _ready_peers()
	if peers.is_empty():
		return
	_snapshots_sent += 1
	for pid in peers:
		_enemy_snapshot.rpc_id(pid, snap_world)


## Marca tóxica pedida por um cliente: mesmas conferências de um acerto (zona e alcance) e os valores
## limitados ao que a tabela permite (o cliente não escolhe quanto dano a mais o alvo leva).
@rpc("any_peer", "call_remote", "reliable")
func _mark_enemy(net_id: int, amp: float, secs: float) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_server() or not players.has(id):
		return
	var e: Enemy = enemies.get(net_id)
	if e == null or not is_instance_valid(e) or e.dead or zone_of(id) != "world":
		return
	if not HitGuard.accepts(0.0, last_pos.get(id, Vector3.INF), e.global_position):
		return
	var max_amp := EnchantRules.max_effect(Balance.tables, "veneno")
	var max_secs := float(Balance.tables.get_table("enchant").get("effects", {}).get("veneno", {}).get("secs", 0.0))
	if not is_finite(amp) or not is_finite(secs) or max_amp <= 0.0 or max_secs <= 0.0:
		return
	e.apply_venom(clampf(amp, 0.0, max_amp), clampf(secs, 0.0, max_secs))


@rpc("any_peer", "call_remote", "reliable")
func _hit_enemy(net_id: int, amount: float, from_pos: Vector3, crit: bool, slow: float, stun := 0.0, pull := 0.0) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_server() or not players.has(id):
		return
	var e: Enemy = enemies.get(net_id)
	if e == null or not is_instance_valid(e) or e.dead or zone_of(id) != "world":
		return
	amount = clampf(amount, 0.0, 5000.0)
	# acerto de dano quase zero ou de longe (última posição recebida) não conta: nem dano, nem lentidão,
	# nem "quem acertou" (que dá XP e sorteio de loot no abate)
	if not HitGuard.accepts(amount, last_pos.get(id, Vector3.INF), e.global_position):
		return
	if amount > 0.0:
		e.last_hitter = id   # antes do número: incoming() usa o nível de quem bateu (monstro bem acima resiste)
		for pid in _enemy_peers(e):
			_enemy_hit_fx.rpc_id(pid, net_id, e.incoming(amount), crit)   # o número já com a marca tóxica
		e.take_damage(amount, from_pos, crit, 0.0, 0.0, clampf(pull, 0.0, 6.0))
		e.last_hitter = 0
	if slow > 0.0 and not e.dead:
		e.apply_slow(minf(slow, 10.0))
	if stun > 0.0 and not e.dead:
		e.apply_stun(minf(stun, 3.0))


## Servidor: só a conta de classe healer cura, no máximo uma vez a cada HealRules.MIN_INTERVAL. O valor vem do
## personagem gravado no servidor (CharRules.heal_amount), nunca do cliente. Cura um jogador só: o aliado
## `target_peer` mirado (mesma zona, a até HealRules.TARGET_RANGE m) ou, sem alvo válido, o próprio healer.
@rpc("any_peer", "call_remote", "reliable")
func _request_heal(target_peer: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_server() or not players.has(id) or characters == null:
		return
	var char_id := int(players[id].get("char", 0))
	if char_id <= 0:
		return
	var s := characters.load_or_create(char_id)
	if s.char_class != "healer" or server_peer_dead(id):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if not HealRules.interval_ok(_last_heal.get(id, -INF), now):
		return
	_last_heal[id] = now
	var amount := CharRules.heal_amount(s, Balance.tables)
	var radius_bonus := float(CharRules.talent_mods(Balance.tables, s).get("ally_radius", 0.0))
	var pid := HealRules.heal_target(id, target_peer, zone_peers(zone_of(id)), last_pos, radius_bonus)
	if not server_peer_dead(pid):   # caído não recebe cura
		_you_were_healed.rpc_id(pid, amount, id)


## Servidor: Escudo de Luz / Banquete do Herói. O cliente manda só o id da habilidade; o buff vem de
## HealRules.ALLY_BUFFS. Mesmas regras da Cura (healer, vivo, intervalo por habilidade, mesma zona, 8 m).
## O Banquete também cura por completo. Quem pede (o healer) está sempre entre os alvos.
@rpc("any_peer", "call_remote", "reliable")
func _request_ally_buff(ability_id: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_server() or not players.has(id) or characters == null or not HealRules.ALLY_BUFFS.has(ability_id):
		return
	var char_id := int(players[id].get("char", 0))
	if char_id <= 0:
		return
	var s := characters.load_or_create(char_id)
	if s.char_class != "healer" or server_peer_dead(id):
		return
	# servidor em --test (allow_reclass): os personagens do net_test ficam no nível 1 e não há como subir; o gate
	# em si é testado em test_heal_rules.gd
	if not characters.allow_reclass and not HealRules.level_ok(s.level, int(ItemDB.ABILITIES[ability_id].level)):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var mine: Dictionary = _last_ally.get(id, {})
	if not HealRules.interval_ok(mine.get(ability_id, -INF), now, ability_id):
		return
	mine[ability_id] = now
	_last_ally[id] = mine
	var buff: String = HealRules.ALLY_BUFFS[ability_id]
	var tm := CharRules.talent_mods(Balance.tables, s)
	# a duração leva o talento do healer que conjurou (o servidor manda os segundos; o cliente só limita)
	var secs := HealRules.ally_buff_seconds(float(ItemDB.BUFFS[buff].time), float(tm.get("ability_time:" + ability_id, 0.0)))
	for pid in HealRules.targets(id, zone_peers(zone_of(id)), last_pos, float(tm.get("ally_radius", 0.0))):
		if server_peer_dead(pid):
			continue
		_you_got_buff.rpc_id(pid, buff, secs)
		if ability_id == "scepter_ult":
			_you_were_healed.rpc_id(pid, HealRules.ULT_HEAL, id)


@rpc("any_peer", "call_remote", "reliable")
func _request_boss() -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_server() and players.has(id) and world and world.has_method("server_spawn_boss"):
		world.server_spawn_boss()


# ---------------------------------------------------------------- jogadores (servidor)
func server_damage_player(peer_id: int, amount: float, from_pos: Vector3) -> void:
	if players.has(peer_id):
		_you_were_hit.rpc_id(peer_id, amount, from_pos)


func server_chill_player(peer_id: int, secs: float) -> void:
	if players.has(peer_id):
		_you_were_chilled.rpc_id(peer_id, secs)


func server_web_player(peer_id: int, secs: float) -> void:
	if players.has(peer_id):
		_you_were_webbed.rpc_id(peer_id, secs)


func server_shake_player(peer_id: int, amount: float) -> void:
	if players.has(peer_id):
		_shake.rpc_id(peer_id, amount)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _player_state(pos: Vector3, yaw: float, vel: Vector3, flags: int, combo: int, attack_t: float) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_server() or not players.has(id) or not players[id].ready:
		return
	var zone := zone_of(id)
	_apply_remote_state(id, pos, yaw, vel, flags, combo, attack_t)
	for pid in zone_peers(zone):
		if pid != id:
			_player_state_relay.rpc_id(pid, id, pos, yaw, vel, flags, combo, attack_t)


@rpc("any_peer", "call_remote", "reliable")
func _player_look(look: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_server() or not players.has(id):
		return
	players[id].look = _clean_look(look, int(players[id].get("char", 0)))
	_relay_look(id)


func _relay_look(id: int) -> void:
	_apply_remote_look(id)
	for pid in _all_peers():
		if pid != id:
			_player_look_relay.rpc_id(pid, id, players[id].look)


## Servidor: o equipamento ou o encanto do peer mudou (encantou, equipou ou desequipou): refaz o
## visual dele com o que está gravado no personagem (peças e brilho juntos, para a réplica nunca
## receber o brilho novo com a arma antiga) e avisa os outros jogadores. As auras ficam como estavam.
func server_refresh_look(peer: int) -> void:
	if not is_server() or not players.has(peer) or characters == null:
		return
	var char_id := int(players[peer].get("char", 0))
	if char_id <= 0:
		return
	var fresh: Dictionary = characters.load_or_create(char_id).equipment.duplicate()
	fresh["fx"] = players[peer].look.get("fx", {})
	fresh = _clean_look(fresh, char_id)
	if fresh == players[peer].look:
		return
	players[peer].look = fresh
	_relay_look(peer)


## Servidor: encanto ({"el", "lv"}) da arma que a conta tem equipada, lido do personagem gravado.
func server_weapon_enchant(char_id: int) -> Dictionary:
	if char_id <= 0 or characters == null:
		return {"el": "", "lv": 0}
	var s := characters.load_or_create(char_id)
	return EnchantRules.of(s, s.equipment.get("weapon", ""))


## Só espaços e itens conhecidos (o dicionário vem do cliente). O encanto mostrado nunca vem do
## cliente: é o da arma equipada do personagem `char_id` no servidor (conta 0 = sem encanto).
func _clean_look(look: Dictionary, char_id := 0) -> Dictionary:
	var out := {}
	for s in ItemDB.SLOTS:
		var v := str(look.get(s, ""))
		out[s] = v if ItemDB.ITEMS.has(v) else ""
	var fx := _clean_fx(look.get("fx"))
	var e := server_weapon_enchant(char_id)
	if str(ItemDB.get_item(out.weapon).get("type", "")) == "tool":
		e = {"el": "", "lv": 0}   # coletando: a ferramenta na mão não leva o brilho da arma encantada
	fx.en = e.el
	fx.lv = e.lv
	out["fx"] = fx
	out["body"] = server_body(char_id)   # o corpo (m/f) vem do personagem gravado, nunca do cliente
	return out


## Servidor: corpo escolhido pela conta ("m", "f" ou "" se ainda não escolheu), lido do personagem gravado.
func server_body(char_id: int) -> String:
	if char_id <= 0 or characters == null:
		return ""
	return characters.load_or_create(char_id).body


## Efeitos visuais do jogador (auras e encanto): só estilos e elementos conhecidos, sem repetir.
func _clean_fx(fx) -> Dictionary:
	var out := {"auras": [], "en": "", "lv": 0}
	if not (fx is Dictionary):
		return out
	var auras = fx.get("auras")
	if auras is Array:
		for st in BuffAura.STYLES:
			if st in auras:
				out.auras.append(st)
	var en := str(fx.get("en", ""))
	var lv = fx.get("lv", 0)
	if EnchantFX.ELEMENTS.has(en) and (lv is int or lv is float):
		out.lv = clampi(int(lv), 0, EnchantFX.MAX_LEVEL)
		out.en = en if out.lv > 0 else ""
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
	my_address = address
	my_name = ""
	last_error = ""
	_connect_t = CONNECT_TIMEOUT
	_autosave_t = autosave_interval


## "Trocar de personagem": fecha a conexão e entra de novo com o mesmo token. O servidor tira o herói do
## jogo e responde com a lista da conta (_char_list), como depois do login. false = sem sessão para reusar.
func rejoin() -> bool:
	if my_token == "" or my_address == "":
		return false
	join(my_address, my_token)
	return is_client()


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
	char_list = []
	account_name = ""
	_connect_t = 0.0
	Econ.client_reset()
	Hub.client_reset()
	Party.client_reset()
	Social.client_reset()
	Weather.clear_server_time()


func _on_connected_to_server() -> void:
	_no_throttle(1)
	_register.rpc_id(1, my_token, version(), Game.equipment.duplicate(), "")


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
		last_error = "Conexão com o servidor perdida. Seu progresso fica salvo no servidor."
		Game.go_to_menu()


@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String) -> void:
	var why := explain_rejection(reason, version())
	if world != null:
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
	# todo mundo entra direto em Valdoria, onde o personagem estava (Game.spawn_position veio do servidor)
	if Game.hp <= 0.0:
		Game.hp = Game.max_hp()
	Game.go_to_world()   # sem classe ainda: passa antes pela tela de criação


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
	if world == null or world.get("player") == null:
		return
	var p: Player = world.player
	if is_instance_valid(p):
		Econ.report_vitals(p.global_position if not p.dead else Vector3(0, 0.5, 6), p.model.rotation.y)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_client():
		autosave()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST and is_server():
		_server_shutdown()


# ---------------------------------------------------------------- envio (cliente)
func send_player_state(pos: Vector3, yaw: float, vel: Vector3, flags: int, combo: int, attack_t: float) -> void:
	if is_client() and world:
		_player_state.rpc_id(1, pos, yaw, vel, flags, combo, attack_t)


func send_look(look: Dictionary) -> void:
	if is_client():
		_player_look.rpc_id(1, look)


## Healer (cliente): pede ao servidor a Cura no aliado `target_peer` (0 = em si mesmo). Sem valor: o servidor calcula.
func request_heal(target_peer := 0) -> void:
	if is_client():
		_request_heal.rpc_id(1, target_peer)


## Healer (cliente): pede o Escudo de Luz / Banquete do Herói para si e os aliados por perto.
func request_ally_buff(ability_id: String) -> void:
	if is_client():
		_request_ally_buff.rpc_id(1, ability_id)


func send_event(kind: String, a := Vector3.ZERO, b := Vector3.ZERO) -> void:
	if is_client() and world:
		_player_event.rpc_id(1, kind, a, b)


func client_hit_enemy(net_id: int, amount: float, from_pos: Vector3, crit: bool, slow := 0.0, stun := 0.0, pull := 0.0) -> void:
	if is_client():
		_hit_enemy.rpc_id(1, net_id, amount, from_pos, crit, slow, stun, pull)


## Marca tóxica da arma encantada com Veneno (ver Enemy.apply_venom): quem aplica é o servidor.
func client_mark_enemy(net_id: int, amp: float, secs: float) -> void:
	if is_client():
		_mark_enemy.rpc_id(1, net_id, amp, secs)


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


@rpc("authority", "call_remote", "reliable")
func _you_were_healed(amount: float, _from_peer: int) -> void:
	if world and world.player:
		world.player.receive_heal(amount)


## Buff de um healer aliado. O cliente só aplica ids que existem em buffs.json.
@rpc("authority", "call_remote", "reliable")
func _you_got_buff(buff_id: String, secs: float) -> void:
	if world and world.player and ItemDB.BUFFS.has(buff_id) and secs > 0.0 and secs <= HealRules.MAX_BUFF_SECS:
		Game.add_buff(buff_id, secs)


@rpc("authority", "call_remote", "reliable")
func _you_were_chilled(secs: float) -> void:
	if world and world.player:
		world.player.apply_chill(secs)


@rpc("authority", "call_remote", "reliable")
func _you_were_webbed(secs: float) -> void:
	if world and world.player:
		world.player.apply_web(secs)


@rpc("authority", "call_remote", "unreliable")
func _shake(amount: float) -> void:
	if world and world.player:
		world.player.add_shake(amount)


@rpc("authority", "call_remote", "reliable")
func _enemy_spawned(net_id: int, kind: String, pos: Vector3, yaw: float, max_hp: float, hp: float, flags: int,
		level: int, area: String) -> void:
	if world == null or enemies.has(net_id):
		return
	var horde := flags & 1 != 0
	var e := ENEMY.new()
	e.kind = kind
	e.puppet = true
	e.horde = horde
	e.elite = flags & 2 != 0
	e.chief = flags & 4 != 0
	e.level = level
	e.area = area   # a região do ponto de nascimento (o servidor conta a missão por ela)
	e.net_id = net_id
	e.position = pos
	# a cena pode escolher onde os monstros ficam (enemy_parent)
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
func _enemy_gone(net_id: int) -> void:
	var e: Enemy = enemies.get(net_id)
	enemies.erase(net_id)
	if e and is_instance_valid(e):
		e.queue_free()


@rpc("authority", "call_remote", "reliable")
func _enemy_died(net_id: int) -> void:
	var e: Enemy = enemies.get(net_id)
	enemies.erase(net_id)
	if e and is_instance_valid(e) and not e.dead:
		e.die_visual()


@rpc("authority", "call_remote", "reliable")
func _enemy_guarded(net_id: int) -> void:
	var e: Enemy = enemies.get(net_id)
	enemies.erase(net_id)
	if e and is_instance_valid(e) and not e.dead:
		e.die_visual()
		e.guard_fx()


@rpc("authority", "call_remote", "reliable")
func _kill_reward(_kind: String, _xp: int, _pos: Vector3) -> void:
	# só o efeito no cliente: XP e abate chegam pelo Econ (estado do servidor) e o loot por _pickup_spawned
	Game.kill_lifesteal()


# ---------------------------------------------------------------- réplicas de jogadores
func _apply_remote_state(id: int, pos: Vector3, yaw: float, vel: Vector3, flags: int, combo: int, attack_t: float) -> void:
	# servidor: a réplica fica em Valdoria; cliente: só quem está na mesma zona
	var parent: Node = world
	if is_server():
		last_pos[id] = pos
		if zone_of(id) != "world":
			return
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
		# já nasce com o corpo do visual conhecido (sem montar o masculino para trocar em seguida)
		rp.model_body = KnightLook.body_key(players[id].get("look", {}).get("body", "")) if players.has(id) else "m"
		rp.position = pos
		parent.add_child(rp)
		remote_players[id] = rp
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
	if kind in ["request", "accept"] and not server_has_class(id):
		_horde_notice.rpc_id(id, "Escolha sua classe antes de entrar no Desafio da Horda.")
		return
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


## A fila vai a quem está em Valdoria.
func _broadcast_lobby() -> void:
	var st := _lobby_state()
	for pid in _ready_peers():
		_horde_lobby.rpc_id(pid, st)


func _horde_launch() -> void:
	# alguém da fila ainda está carregando Valdoria: adia um pouco, até HORDE_TRAVEL_WAIT
	var waited := float(_lobby.get("travel", 0.0))
	if waited < HORDE_TRAVEL_WAIT:
		for pid in _lobby.members:
			if players.has(pid) and zone_of(pid) == "loading":
				_lobby["travel"] = waited + HORDE_TRAVEL_STEP
				_lobby.t = HORDE_TRAVEL_STEP
				return
	var team := {}
	for pid in _lobby.members:
		if not players.has(pid) or not players[pid].ready or not server_has_class(pid):
			continue
		# a partida acontece em Valdoria: só entra quem está lá
		if zone_of(pid) != "world":
			_horde_notice.rpc_id(pid, "Você não chegou a tempo ao portal.")
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
	if not chat_allow(id):
		return
	var from: String = players[id].name
	print("[chat] %s: %s" % [from, t])
	# o chat é do servidor inteiro
	for pid in _all_peers():
		if players[pid].ready:
			_chat_msg.rpc_id(pid, from, t)


## Servidor: anti-spam do chat (vale também para os sussurros do Social). false = avisou o peer e recusou.
func chat_allow(id: int) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	var recent: Array = _chat_log.get(id, []).filter(func(x: float) -> bool: return now - x < CHAT_WINDOW)
	if recent.size() >= CHAT_BURST:
		_chat_msg.rpc_id(id, "", "Calma! Espere alguns segundos para mandar outra mensagem.")
		return false
	recent.append(now)
	_chat_log[id] = recent
	return true


## Texto de chat limpo (sem quebras nem controle, até CHAT_MAX); "" se não sobrou nada.
func clean_chat(text: String) -> String:
	return _clean_chat(text)


@rpc("authority", "call_remote", "reliable")
func _chat_msg(from: String, text: String) -> void:
	chat_received.emit(from, text)
