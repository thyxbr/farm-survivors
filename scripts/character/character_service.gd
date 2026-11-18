class_name CharacterService
extends RefCounted
## Único lugar que muda um personagem: o servidor dedicado (uma instância, várias contas) e o solo
## offline (conta 1) passam por aqui. Aplica CharRules, grava numa escrita só (personagem + economia)
## e registra a economia. Sem autoload: recebe o armazenamento (CharStore), BalanceTables e relógio.
## Servidor: SqliteCharStore (SQLite); solo: FileCharStore (JSON em user://). Mesmas regras, uma economia.

## Só servidor em --test (net_test): deixa "choose_class" valer de novo, para o teste passar pelas quatro armas.
var allow_reclass := false

## Operações que o cliente pode pedir. Conceder ouro/xp/itens e abates é só do servidor/solo.
const CLIENT_OPS := ["buy", "sell", "equip", "unequip", "consume", "cook", "craft", "spend_point", "start_quest",
	"complete_quest", "sort_inventory", "unlock_plot", "plant", "water", "fertilize", "harvest", "discard",
	"death_penalty", "buy_passive", "enchant", "rank_up", "quest_mark", "choose_class",
	"learn_talent", "reset_talents", "ack_prog_notice"]

## Assinatura posicional de cada op: tipos aceitos (TYPE_*) e quantos são opcionais no fim.
## `now` e o gerador de sorteio nunca vêm do cliente.
const ARGS := {
	"buy": {"types": [TYPE_STRING, TYPE_INT], "optional": 1},
	"sell": {"types": [TYPE_STRING], "optional": 0},
	"equip": {"types": [TYPE_STRING], "optional": 0},
	"unequip": {"types": [TYPE_STRING], "optional": 0},
	"consume": {"types": [TYPE_STRING], "optional": 0},
	"cook": {"types": [TYPE_STRING, TYPE_INT], "optional": 1},
	"craft": {"types": [TYPE_STRING, TYPE_INT], "optional": 1},
	"spend_point": {"types": [TYPE_STRING], "optional": 0},
	"start_quest": {"types": [TYPE_STRING], "optional": 0},
	"complete_quest": {"types": [TYPE_STRING], "optional": 0},
	"sort_inventory": {"types": [], "optional": 0},
	"unlock_plot": {"types": [], "optional": 0},
	"plant": {"types": [TYPE_INT, TYPE_STRING, TYPE_BOOL], "optional": 0},
	"water": {"types": [TYPE_INT], "optional": 0},
	"fertilize": {"types": [TYPE_INT], "optional": 0},
	"harvest": {"types": [TYPE_INT], "optional": 0},
	"discard": {"types": [TYPE_STRING], "optional": 0},
	"death_penalty": {"types": [], "optional": 0},
	"buy_passive": {"types": [TYPE_STRING], "optional": 0},
	"enchant": {"types": [TYPE_STRING], "optional": 0},
	"rank_up": {"types": [], "optional": 0},
	"quest_mark": {"types": [TYPE_STRING, TYPE_INT], "optional": 0},
	"choose_class": {"types": [TYPE_STRING, TYPE_STRING, TYPE_STRING], "optional": 1},
	"learn_talent": {"types": [TYPE_STRING], "optional": 0},
	"reset_talents": {"types": [], "optional": 0},
	"ack_prog_notice": {"types": [], "optional": 0},
}

## Concessões dessas origens acontecem a cada coleta durante a partida: o registro é um só, no fim
## (finish_player, que também concede os Ecos da partida).
const UNLOGGED_SOURCES := ["horde_run", "city_night"]
## Concessões de jogo na vila que recebem o bônus de comida (XP/ouro). Fora daqui: Horda (o cliente já
## aplica mod()), admin, teste, venda, compra, coleta de material, demo.
const FOOD_SOURCES := ["loot", "gold", "xp", "party_xp"]
## Recordes de partida que o servidor/solo grava no personagem (set_record).
const RECORD_KEYS := ["horde_best", "city_best"]
const SOLO_ACCOUNT := 1
const MAX_VITAL := 10000.0
## Limite de cada coordenada reportada pelo cliente (o mapa é bem menor).
const MAX_COORD := 10000.0
## Teto do ouro de teste por pedido (servidor em --test, usado pelo net_test).
const TEST_GOLD_MAX := 100000

var _store: CharStore
var _bt: BalanceTables
var _clock: Callable
var _rng := RandomNumberGenerator.new()
## Tudo abaixo é por PERSONAGEM (char_id); uma conta pode ter vários (create_character/list_characters).
## No solo o personagem 1 é o da conta 1.
var _cache := {}      # char_id -> CharState
var _sessions := {}   # char_id -> session_id atual
var _dirty := {}      # char_id -> true: report mudou o cache e ainda não foi gravado
var _owners := {}     # char_id -> conta dona (registro da economia)


func _init(store: CharStore, bt: BalanceTables, clock: Callable = Callable()) -> void:
	_store = store
	_bt = bt
	_clock = clock
	_rng.randomize()


func _now() -> float:
	return float(_clock.call()) if _clock.is_valid() else Time.get_unix_time_from_system()


# ================================================================ carga
func load_or_create(char_id: int) -> CharState:
	if _cache.has(char_id):
		return _cache[char_id]
	var s := _read(char_id)
	if s == null:
		s = CharState.new_character(_bt)
		if not _save(char_id, s):
			push_error("CharacterService: não gravou personagem novo de %d: %s" % [char_id, _store.last_error])
			return s   # sem cache: a próxima chamada tenta de novo
	else:
		# personagem de antes da progressão por nível (pontos devolvidos) ou da coleta com ferramenta (ganha as
		# de pedra): gravado já na carga
		var migrated := CharRules.migrate_progression(s, _bt)
		migrated = CharRules.migrate_tools(s, _bt) or migrated
		if migrated and not _save(char_id, s):
			push_error("CharacterService: não gravou a migração de %d: %s" % [char_id, _store.last_error])
			return s   # sem cache: a próxima carga migra de novo
	_cache[char_id] = s
	return s


## Conta dona do personagem (guardada depois da primeira consulta).
func owner_of(char_id: int) -> int:
	if not _owners.has(char_id):
		_owners[char_id] = _store.owner_of(char_id)
	return int(_owners[char_id])


# ================================================================ seleção de personagem
## Personagens da conta para a tela de seleção ([{"id", "level", "char_class", "body", "equipment", ...}]).
## Quem está no cache (ainda não gravado) aparece com o estado do cache.
func list_characters(account_id: int) -> Array:
	var out := _store.list_chars(account_id)
	for e in out:
		var id := int(e.id)
		if _cache.has(id):
			var s: CharState = _cache[id]
			e.level = s.level
			e.char_class = s.char_class
			e.body = s.body
			e.hair = s.hair
			e.equipment = s.equipment.duplicate()
	return out


## Tamanho do nome do herói.
const NAME_MIN := 3
const NAME_MAX := 16


## Nome do herói limpo (sem espaços nas pontas) ou "" se não vale: 3 a 16 letras (com acento) ou
## números, começando por letra, sem espaços. A mesma regra no cliente (aviso na hora) e no servidor.
static func clean_name(name: String) -> String:
	var n := name.strip_edges()
	if n.length() < NAME_MIN or n.length() > NAME_MAX:
		return ""
	var re := RegEx.create_from_string("^\\p{L}[\\p{L}\\p{N}]*$")
	return n if re.search(n) != null else ""


## Cria um personagem da conta com nome, classe, corpo e penteado (a mesma regra de "choose_class").
## Devolve {"ok", "err", "id"}; err "nome_invalido" ou "nome_em_uso" quando o nome não serve.
func create_character(account_id: int, name: String, cls: String, body: String, hair := "") -> Dictionary:
	var clean := clean_name(name)
	if clean == "":
		return {"ok": false, "err": "nome_invalido", "id": 0}
	if _store.name_taken(clean):
		return {"ok": false, "err": "nome_em_uso", "id": 0}
	var s := CharState.new_character(_bt)
	var r := _dispatch(s, "choose_class", [cls, body, hair])
	if not r.ok:
		return {"ok": false, "err": str(r.err), "id": 0}
	var id := _store.create_char(account_id, clean, s.to_dict(), int(_now()))
	if id <= 0:
		if _store.last_error == "nome_em_uso" or _store.name_taken(clean):
			return {"ok": false, "err": "nome_em_uso", "id": 0}
		push_error("CharacterService: não criou personagem da conta %d: %s" % [account_id, _store.last_error])
		return {"ok": false, "err": "erro_banco", "id": 0}
	_owners[id] = account_id
	return {"ok": true, "err": "", "id": id}


## Nome do personagem ("" sem nome: solo e testes antigos).
func name_of(char_id: int) -> String:
	return _store.name_of(char_id)


## Texto para o jogador de um erro de criação.
static func explain_create(err: String) -> String:
	match err:
		"nome_invalido":
			return "Nome inválido: de %d a %d letras ou números, começando por letra, sem espaços." % [NAME_MIN, NAME_MAX]
		"nome_em_uso":
			return "Já existe um herói com esse nome. Escolha outro."
		"penteado_invalido":
			return "Esse penteado não existe para esse corpo."
	return "Não deu para criar o herói (%s)." % err


## Exclui um personagem da conta (some do cache sem gravar). false se não é da conta ou o banco falhou.
func delete_character(account_id: int, char_id: int) -> bool:
	if char_id <= 0 or owner_of(char_id) != account_id:
		return false
	_cache.erase(char_id)
	_dirty.erase(char_id)
	_sessions.erase(char_id)
	if not _store.delete_char(char_id):
		push_error("CharacterService: não excluiu o personagem %d: %s" % [char_id, _store.last_error])
		return false
	_owners.erase(char_id)
	return true


## Grava e tira do cache (jogador saiu). Com `session_id` >= 0, só descarrega se for a sessão atual da
## conta: a desconexão tardia de uma conexão velha não derruba a sessão nova (só grava).
func unload(char_id: int, session_id: int = -1) -> void:
	if session_id >= 0 and _sessions.get(char_id, -1) != session_id:
		save(char_id)
		return
	if _cache.has(char_id):
		if not _save(char_id, _cache[char_id]):
			push_error("CharacterService: não gravou %d ao descarregar: %s" % [char_id, _store.last_error])
		_cache.erase(char_id)
	_sessions.erase(char_id)


func set_session(char_id: int, session_id: int) -> void:
	_sessions[char_id] = session_id


# ================================================================ operações
## Pedido do cliente. Devolve {"ok","err","events","state"}.
func apply(char_id: int, op: String, args: Array) -> Dictionary:
	if not (op in CLIENT_OPS):
		return _result(char_id, {"ok": false, "err": "op_invalida", "events": []})
	if not _args_ok(op, args):
		return _result(char_id, {"ok": false, "err": "args", "events": []})
	var s := load_or_create(char_id)
	if allow_reclass and op == "choose_class":
		s.char_class = ""
		s.body = ""
	if s.char_class == "" and op != "choose_class" and op != "ack_prog_notice":
		return _result(char_id, {"ok": false, "err": "sem_classe", "events": []})
	# modo admin: recursos no teto antes de cada pedido (a reposição não entra no registro da economia)
	AdminRules.top_up(s, _bt)
	# a arma inicial da classe não é negócio: não entra no registro da economia
	var before := {} if op == "choose_class" else _holdings(s)
	var r := _dispatch(s, op, args)
	if r.ok:
		# passivas e encantos gastam Ecos: a linha de Ecos diz em quê (id da passiva ou "enchant")
		var source := "player"
		var ecos_item := ""
		if op == "buy_passive":
			source = "passive"
			ecos_item = args[0]
		elif op == "enchant":
			source = "enchant"
			ecos_item = "enchant"
		r = _persist(char_id, s, before, op, source, r, 0, ecos_item)
		AdminRules.top_up(s, _bt)   # a tela já mostra cheio de novo (grava na próxima escrita)
	return _result(char_id, r)


## Concessão do servidor/solo (loot, missão, prêmio de partida).
func grant(char_id: int, gold: int, xp: int, items: Dictionary, source: String) -> Dictionary:
	var s := load_or_create(char_id)
	var before := _holdings(s)
	if source in FOOD_SOURCES and gold >= 0 and xp >= 0:
		gold = int(round(gold * CharRules.food_mult(s, _bt, "gold", _now())))
		xp = int(round(xp * CharRules.food_mult(s, _bt, "xp", _now())))
	var r := CharRules.grant(s, _bt, gold, xp, items)
	if r.ok:
		var log_it := not (source in UNLOGGED_SOURCES)
		r = _persist(char_id, s, before if log_it else {}, "grant", source, r, xp if log_it else 0)
	return _result(char_id, r)


## Coleta de um veio ou árvore (`g` vem de WorldHarvest.gather): itens + XP da profissão de coleta.
func gather(char_id: int, g: Dictionary) -> Dictionary:
	var s := load_or_create(char_id)
	var before := _holdings(s)
	var r := CharRules.gather(s, _bt, g)
	if r.ok:
		r = _persist(char_id, s, before, "grant", "gather", r, 0)
	return _result(char_id, r)


func kill(char_id: int, kind: String, xp: int, enemy_level := 0, group_level := 0, area := "") -> Dictionary:
	var s := load_or_create(char_id)
	if xp >= 0:
		xp = int(round(xp * CharRules.food_mult(s, _bt, "xp", _now())))
	var r := CharRules.kill(s, _bt, kind, xp, enemy_level, group_level, area)
	if r.ok:
		r = _persist(char_id, s, {}, "kill", "kill", r)
	return _result(char_id, r)


## Recorde de partida no personagem (servidor/solo): "city_best" (noites, int) ou "horde_best"
## ({"round", "kills", "time", "level"}, comparado por rodada e depois abates). Só grava se for melhor.
func set_record(char_id: int, key: String, value) -> Dictionary:
	if not (key in RECORD_KEYS):
		return _result(char_id, {"ok": false, "err": "chave_invalida", "events": []})
	var s := load_or_create(char_id)
	var old = s.flags.get(key)
	var better := false
	if key == "city_best":
		value = maxi(0, int(value))
		better = old == null or int(value) > int(old)
	else:
		if not (value is Dictionary):
			return _result(char_id, {"ok": false, "err": "valor_invalido", "events": []})
		var o: Dictionary = old if old is Dictionary else {}
		var rnd := int(value.get("round", 0))
		var best_round := int(o.get("round", -1))
		better = rnd > best_round or (rnd == best_round and int(value.get("kills", 0)) > int(o.get("kills", 0)))
	if not better:
		return _result(char_id, {"ok": true, "err": "", "events": []})
	s.flags[key] = value
	if not _save(char_id, s):
		push_error("CharacterService: recorde de %d não gravou: %s" % [char_id, _store.last_error])
		_cache.erase(char_id)
		return _result(char_id, {"ok": false, "err": "erro_banco", "events": []})
	return _result(char_id, {"ok": true, "err": "", "events": []})


## Estado de combate reportado pelo cliente. Só vale para a sessão atual da conta (uma conexão
## velha, já substituída, não sobrescreve a posição da nova). Gravado no próximo apply/unload.
func report(char_id: int, session_id: int, hp: float, mp: float, pos: Vector3, yaw: float, fury := 0.0) -> void:
	if not _cache.has(char_id) or _sessions.get(char_id, -1) != session_id:
		return
	if not (is_finite(hp) and is_finite(mp) and pos.is_finite() and is_finite(yaw) and is_finite(fury)):
		return
	var s: CharState = _cache[char_id]
	s.hp = clampf(hp, 0.0, MAX_VITAL)
	s.mp = clampf(mp, 0.0, MAX_VITAL)
	s.fury = clampf(fury, 0.0, CharState.FURY_MAX)
	s.world_pos = pos.clamp(-Vector3.ONE * MAX_COORD, Vector3.ONE * MAX_COORD)
	s.world_yaw = yaw
	_dirty[char_id] = true


## Grava as contas que só mudaram por report (o servidor chama de tempos em tempos). Devolve quantas.
func flush_dirty() -> int:
	var n := 0
	for char_id in _dirty.keys():
		if _cache.has(char_id) and _save(char_id, _cache[char_id]):
			n += 1
	_dirty.clear()
	return n


## Ouro de teste: só com o servidor em --test (`enabled`), 1..TEST_GOLD_MAX.
func grant_test_gold(char_id: int, amount: int, enabled: bool) -> Dictionary:
	if not enabled:
		return _result(char_id, {"ok": false, "err": "sem_teste", "events": []})
	if amount <= 0 or amount > TEST_GOLD_MAX:
		return _result(char_id, {"ok": false, "err": "valor_invalido", "events": []})
	return grant(char_id, amount, 0, {}, "test")


## Ecos de teste: só com o servidor em --test (`enabled`), 1..TEST_GOLD_MAX. Registrado como "ecos"/"test".
func grant_test_ecos(char_id: int, amount: int, enabled: bool) -> Dictionary:
	if not enabled:
		return _result(char_id, {"ok": false, "err": "sem_teste", "events": []})
	if amount <= 0 or amount > TEST_GOLD_MAX:
		return _result(char_id, {"ok": false, "err": "valor_invalido", "events": []})
	var s := load_or_create(char_id)
	var before := _holdings(s)
	s.ecos += amount
	return _result(char_id, _persist(char_id, s, before, "grant", "test", {"ok": true, "err": "", "events": []}))


## Itens de teste: só com o servidor em --test (`enabled`); 1 a MAX_COUNT de cada item conhecido.
func grant_test_items(char_id: int, items: Dictionary, enabled: bool) -> Dictionary:
	if not enabled:
		return _result(char_id, {"ok": false, "err": "sem_teste", "events": []})
	var known: Dictionary = _bt.get_table("items")
	var clean := {}
	for id in items:
		var n = items[id]
		if not (id is String) or not known.has(id) or not CharRules._valid_count(n):
			return _result(char_id, {"ok": false, "err": "valor_invalido", "events": []})
		clean[id] = n
	if clean.is_empty():
		return _result(char_id, {"ok": false, "err": "valor_invalido", "events": []})
	return grant(char_id, 0, 0, clean, "test")


## Liga/desliga o modo admin (AdminRules). `allowed` é decidido por quem chama: solo sempre, servidor
## só para contas em ADMIN_USERS. Registrado na economia com origem "admin".
func set_admin(char_id: int, on: bool, allowed: bool) -> Dictionary:
	if not allowed:
		return _result(char_id, {"ok": false, "err": "sem_permissao", "events": [CharRules._notify(
				"Só administradores podem usar o modo admin.", CharRules.C_BAD)]})
	var s := load_or_create(char_id)
	var before := _holdings(s)
	var r := AdminRules.set_on(s, _bt, on)
	return _result(char_id, _persist(char_id, s, before, "grant", "admin", r))


## Modo admin: põe um item qualquer na mochila (AdminRules.give recusa com o modo desligado).
## Registrado na economia com origem "admin".
func admin_give(char_id: int, id: String, qty: int) -> Dictionary:
	var s := load_or_create(char_id)
	var before := _holdings(s)
	var r := AdminRules.give(s, _bt, id, qty)
	if not r.ok:
		return _result(char_id, r)
	return _result(char_id, _persist(char_id, s, before, "grant", "admin", r))


# ================================================================ partidas e recordes
## Abre o registro de uma partida. 0 se não gravou.
func start_run(mode: String, accounts: Array) -> int:
	var id := _store.start_run(mode, accounts, int(_now()))
	if id <= 0:
		push_error("CharacterService: start_run não gravou: %s" % _store.last_error)
		return 0
	return id


## Fim da partida de um jogador: concede os Ecos e registra. Idempotente por (run_id, conta): repetir
## devolve ok sem conceder de novo. Com run_id <= 0 só concede e registra a economia.
## Ouro, xp e itens já foram concedidos durante a partida (grant); aqui só entram no registro.
func finish_player(run_id: int, char_id: int, mode: String, reached: int, gold: int, xp: int, items: Dictionary, build: Dictionary) -> Dictionary:
	var s := load_or_create(char_id)
	if run_id > 0 and _store.run_player_done(run_id, char_id):
		return _result(char_id, {"ok": true, "err": "", "events": [{"t": "ecos", "n": 0, "mode": mode, "reached": reached}]})
	var ecos := RewardRules.ecos(_bt, mode, reached)
	s.ecos += ecos
	var at := int(_now())
	var rows := [_row(at, char_id, "run", gold, null, mode,
		JSON.stringify({"xp": xp, "items": items, "ecos": ecos, "run_id": run_id, "reached": reached}))]
	if ecos > 0:
		# linha própria dos Ecos ganhos (fonte = modo), para somar "Ecos por fonte" sem abrir o detail
		rows.append(_row(at, char_id, "ecos", ecos, null, mode))
	var entry := {"reached": reached, "ecos": ecos, "gold": gold, "xp": xp, "build": build}
	if not _store.save_run_player(char_id, s.to_dict(), run_id, entry, rows, at):
		push_error("CharacterService: finish_player de %d não gravou: %s" % [char_id, _store.last_error])
		_cache.erase(char_id)
		return _result(char_id, {"ok": false, "err": "erro_banco", "events": []})
	_dirty.erase(char_id)
	return _result(char_id, {"ok": true, "err": "", "events": [{"t": "ecos", "n": ecos, "mode": mode, "reached": reached}]})


func close_run(run_id: int, reached: int, result: Dictionary) -> bool:
	var ok := _store.close_run(run_id, reached, result, int(_now()))
	if not ok:
		push_error("CharacterService: close_run %d não gravou: %s" % [run_id, _store.last_error])
	return ok


## Recorde de cada modo: a partida encerrada que foi mais longe (empate: a mais antiga) e quem jogou.
func records() -> Dictionary:
	var out := {}
	for mode in ["horde", "city"]:
		out[mode] = _store.best_run(mode)
	return out


## Grava todos os personagens em cache (o servidor desligando). Devolve quantos gravou.
func save_all() -> int:
	var n := 0
	for char_id in _cache.keys():
		if _save(char_id, _cache[char_id]):
			n += 1
		else:
			push_error("CharacterService: personagem %d não gravou ao desligar: %s" % [char_id, _store.last_error])
	return n


## Grava o personagem em cache sem descarregar.
func save(char_id: int) -> bool:
	return not _cache.has(char_id) or _save(char_id, _cache[char_id])


# ================================================================ interno
func _args_ok(op: String, args: Array) -> bool:
	var spec: Dictionary = ARGS[op]
	var types: Array = spec["types"]
	if args.size() > types.size() or args.size() < types.size() - int(spec["optional"]):
		return false
	for i in args.size():
		if typeof(args[i]) != types[i]:
			return false
	return true


func _dispatch(s: CharState, op: String, a: Array) -> Dictionary:
	match op:
		"buy": return CharRules.buy(s, _bt, a[0], a[1] if a.size() > 1 else 1)
		"sell": return CharRules.sell(s, _bt, a[0])
		"equip": return CharRules.equip(s, _bt, a[0])
		"unequip": return CharRules.unequip(s, _bt, a[0])
		"consume": return CharRules.consume(s, _bt, a[0], _now())
		"cook": return CharRules.cook(s, _bt, a[0], a[1] if a.size() > 1 else 1)
		"craft": return CraftRules.craft(s, _bt, a[0], a[1] if a.size() > 1 else 1, _rng)
		"spend_point": return CharRules.spend_point(s, _bt, a[0])
		"start_quest": return CharRules.start_quest(s, _bt, a[0])
		"complete_quest": return CharRules.complete_quest(s, _bt, a[0], _now())
		"rank_up": return CharRules.rank_up(s, _bt)
		"choose_class": return CharRules.choose_class(s, _bt, a[0], a[1], a[2] if a.size() > 2 else "")
		"quest_mark": return CharRules.quest_mark(s, _bt, a[0], a[1])
		"sort_inventory": return CharRules.sort_inventory(s, _bt)
		"unlock_plot": return CharRules.unlock_plot(s, _bt)
		"plant": return CharRules.plant(s, _bt, a[0], a[1], a[2], _now())
		"water": return CharRules.water(s, _bt, a[0], _now())
		"fertilize": return CharRules.fertilize(s, _bt, a[0], _now())
		"harvest": return CharRules.harvest(s, _bt, a[0], _now(), _rng)
		"discard": return CharRules.discard(s, _bt, a[0])
		"death_penalty": return CharRules.death_penalty(s, _bt)
		"buy_passive": return CharRules.buy_passive(s, _bt, a[0])
		"learn_talent": return CharRules.learn_talent(s, _bt, a[0])
		"reset_talents": return CharRules.reset_talents(s, _bt)
		"ack_prog_notice": return CharRules.ack_prog_notice(s)
		"enchant": return EnchantRules.enchant(s, _bt, a[0])
	return {"ok": false, "err": "op_invalida", "events": []}


## Posse por id (inventário + equipado) e ouro: equipar/desequipar não muda a posse, então não gera linha.
func _holdings(s: CharState) -> Dictionary:
	var h := {"": s.gold, "$ecos": s.ecos}   # chave "" = ouro; "$ecos" = Ecos (não colide com id de item)
	for slot in s.inventory:
		h[slot.id] = int(h.get(slot.id, 0)) + int(slot.qty)
	for k in s.equipment:
		var id: String = s.equipment[k]
		if id != "":
			h[id] = int(h.get(id, 0)) + 1
	return h


## Grava estado + linhas da economia numa escrita só. Falha: descarta o cache e relê do armazenamento.
func _persist(char_id: int, s: CharState, before: Dictionary, kind: String, source: String, r: Dictionary, xp := 0, ecos_item := "") -> Dictionary:
	var after := _holdings(s)
	var at := int(_now())
	var rows := []
	if xp > 0:
		rows.append(_row(at, char_id, "xp", xp, null, source))
	if not before.is_empty():
		var ids := {}
		for k in before:
			ids[k] = true
		for k in after:
			ids[k] = true
		for k in ids:
			var d := int(after.get(k, 0)) - int(before.get(k, 0))
			if d == 0:
				continue
			var log_kind := kind
			var item = k
			if k == "":
				item = null
			elif k == "$ecos":
				log_kind = "ecos"
				item = ecos_item if ecos_item != "" else null
			rows.append(_row(at, char_id, log_kind, d, item, source))
	if _store.save_char(char_id, s.to_dict(), rows, at):
		_dirty.erase(char_id)
		return r
	push_error("CharacterService: falha ao gravar %d: %s" % [char_id, _store.last_error])
	_cache.erase(char_id)
	return {"ok": false, "err": "erro_banco", "events": []}


## Linha da economia do personagem: a conta é a dona dele.
func _row(at: int, char_id: int, kind: String, amount: int, item_id, source: String, detail = null) -> Dictionary:
	return CharStore.row(at, owner_of(char_id), kind, amount, item_id, source, detail, char_id)


func _result(char_id: int, r: Dictionary) -> Dictionary:
	var out := r.duplicate()
	out["state"] = load_or_create(char_id).to_dict()
	return out


func _save(char_id: int, s: CharState) -> bool:
	var ok := _store.save_char(char_id, s.to_dict(), [], int(_now()))
	if ok:
		_dirty.erase(char_id)
	return ok


func _read(char_id: int) -> CharState:
	var d = _store.load_char(char_id)
	if not (d is Dictionary):
		return null
	return CharState.from_dict(d, _bt)
