class_name CharacterService
extends RefCounted
## Único lugar que muda um personagem: o servidor dedicado (uma instância, várias contas) e o solo
## offline (conta 1 em user://solo.db) passam por aqui. Aplica CharRules, grava no banco numa transação
## e registra a economia. Sem autoload: recebe Db, BalanceTables e relógio.

## Operações que o cliente pode pedir. Conceder ouro/xp/itens e abates é só do servidor/solo.
const CLIENT_OPS := ["buy", "sell", "equip", "unequip", "consume", "cook", "spend_point", "start_quest",
	"complete_quest", "sort_inventory", "unlock_plot", "plant", "water", "fertilize", "harvest", "discard",
	"death_penalty", "buy_passive", "donate"]

## Assinatura posicional de cada op: tipos aceitos (TYPE_*) e quantos são opcionais no fim.
## `now` e o gerador de sorteio nunca vêm do cliente.
const ARGS := {
	"buy": {"types": [TYPE_STRING, TYPE_INT], "optional": 1},
	"sell": {"types": [TYPE_STRING], "optional": 0},
	"equip": {"types": [TYPE_STRING], "optional": 0},
	"unequip": {"types": [TYPE_STRING], "optional": 0},
	"consume": {"types": [TYPE_STRING], "optional": 0},
	"cook": {"types": [TYPE_STRING, TYPE_INT], "optional": 1},
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
	"donate": {"types": [TYPE_STRING, TYPE_INT], "optional": 0},
}

## Concessões dessas origens acontecem a cada coleta durante a partida: o registro é um só, no fim
## (finish_player, que também concede os Ecos da partida).
const UNLOGGED_SOURCES := ["horde_run", "city_night"]
## Recordes de partida que o servidor/solo grava no personagem (set_record).
const RECORD_KEYS := ["horde_best", "city_best"]
const SOLO_ACCOUNT := 1
const MAX_VITAL := 10000.0
## Limite de cada coordenada reportada pelo cliente (o mapa é bem menor).
const MAX_COORD := 10000.0
## Teto do ouro de teste por pedido (servidor em --test, usado pelo net_test).
const TEST_GOLD_MAX := 100000

var _db: Db
var _bt: BalanceTables
var _clock: Callable
var _rng := RandomNumberGenerator.new()
var _cache := {}      # account_id -> CharState
var _sessions := {}   # account_id -> session_id atual
var _dirty := {}      # account_id -> true: report mudou o cache e ainda não foi gravado


func _init(db: Db, bt: BalanceTables, clock: Callable = Callable()) -> void:
	_db = db
	_bt = bt
	_clock = clock
	_rng.randomize()


func _now() -> float:
	return float(_clock.call()) if _clock.is_valid() else Time.get_unix_time_from_system()


# ================================================================ carga
func load_or_create(account_id: int) -> CharState:
	if _cache.has(account_id):
		return _cache[account_id]
	var s := _read(account_id)
	if s == null:
		s = CharState.new_character(_bt)
		if not _save(account_id, s):
			push_error("CharacterService: não gravou personagem novo de %d: %s" % [account_id, _db.last_error])
			return s   # sem cache: a próxima chamada tenta de novo
	_cache[account_id] = s
	return s


## Grava e tira do cache (jogador saiu). Com `session_id` >= 0, só descarrega se for a sessão atual da
## conta: a desconexão tardia de uma conexão velha não derruba a sessão nova (só grava).
func unload(account_id: int, session_id: int = -1) -> void:
	if session_id >= 0 and _sessions.get(account_id, -1) != session_id:
		save(account_id)
		return
	if _cache.has(account_id):
		if not _save(account_id, _cache[account_id]):
			push_error("CharacterService: não gravou %d ao descarregar: %s" % [account_id, _db.last_error])
		_cache.erase(account_id)
	_sessions.erase(account_id)


func set_session(account_id: int, session_id: int) -> void:
	_sessions[account_id] = session_id


# ================================================================ operações
## Pedido do cliente. Devolve {"ok","err","events","state"}.
func apply(account_id: int, op: String, args: Array) -> Dictionary:
	if not (op in CLIENT_OPS):
		return _result(account_id, {"ok": false, "err": "op_invalida", "events": []})
	if not _args_ok(op, args):
		return _result(account_id, {"ok": false, "err": "args", "events": []})
	var s := load_or_create(account_id)
	if op == "donate":
		return _donate(account_id, s, args[0], args[1])
	var before := _holdings(s)
	var r := _dispatch(s, op, args)
	if r.ok:
		r = _persist(account_id, s, before, op, "passive" if op == "buy_passive" else "player", r, 0, args[0] if op == "buy_passive" else "")
	return _result(account_id, r)


## Concessão do servidor/solo (loot, missão, prêmio de partida).
func grant(account_id: int, gold: int, xp: int, items: Dictionary, source: String) -> Dictionary:
	var s := load_or_create(account_id)
	var before := _holdings(s)
	var r := CharRules.grant(s, _bt, gold, xp, items)
	if r.ok:
		var log_it := not (source in UNLOGGED_SOURCES)
		r = _persist(account_id, s, before if log_it else {}, "grant", source, r, xp if log_it else 0)
	return _result(account_id, r)


func kill(account_id: int, kind: String, xp: int) -> Dictionary:
	var s := load_or_create(account_id)
	var r := CharRules.kill(s, _bt, kind, xp)
	if r.ok:
		r = _persist(account_id, s, {}, "kill", "kill", r)
	return _result(account_id, r)


## Recorde de partida no personagem (servidor/solo): "city_best" (noites, int) ou "horde_best"
## ({"round", "kills", "time", "level"}, comparado por rodada e depois abates). Só grava se for melhor.
func set_record(account_id: int, key: String, value) -> Dictionary:
	if not (key in RECORD_KEYS):
		return _result(account_id, {"ok": false, "err": "chave_invalida", "events": []})
	var s := load_or_create(account_id)
	var old = s.flags.get(key)
	var better := false
	if key == "city_best":
		value = maxi(0, int(value))
		better = old == null or int(value) > int(old)
	else:
		if not (value is Dictionary):
			return _result(account_id, {"ok": false, "err": "valor_invalido", "events": []})
		var o: Dictionary = old if old is Dictionary else {}
		var rnd := int(value.get("round", 0))
		var best_round := int(o.get("round", -1))
		better = rnd > best_round or (rnd == best_round and int(value.get("kills", 0)) > int(o.get("kills", 0)))
	if not better:
		return _result(account_id, {"ok": true, "err": "", "events": []})
	s.flags[key] = value
	if not _save(account_id, s):
		push_error("CharacterService: recorde de %d não gravou: %s" % [account_id, _db.last_error])
		_cache.erase(account_id)
		return _result(account_id, {"ok": false, "err": "erro_banco", "events": []})
	return _result(account_id, {"ok": true, "err": "", "events": []})


## Estado de combate reportado pelo cliente. Só vale para a sessão atual da conta (uma conexão
## velha, já substituída, não sobrescreve a posição da nova). Gravado no próximo apply/unload.
func report(account_id: int, session_id: int, hp: float, mp: float, pos: Vector3, yaw: float) -> void:
	if not _cache.has(account_id) or _sessions.get(account_id, -1) != session_id:
		return
	if not (is_finite(hp) and is_finite(mp) and pos.is_finite() and is_finite(yaw)):
		return
	var s: CharState = _cache[account_id]
	s.hp = clampf(hp, 0.0, MAX_VITAL)
	s.mp = clampf(mp, 0.0, MAX_VITAL)
	s.world_pos = pos.clamp(-Vector3.ONE * MAX_COORD, Vector3.ONE * MAX_COORD)
	s.world_yaw = yaw
	_dirty[account_id] = true


## Grava as contas que só mudaram por report (o servidor chama de tempos em tempos). Devolve quantas.
func flush_dirty() -> int:
	var n := 0
	for account_id in _dirty.keys():
		if _cache.has(account_id) and _save(account_id, _cache[account_id]):
			n += 1
	_dirty.clear()
	return n


## Ouro de teste: só com o servidor em --test (`enabled`), 1..TEST_GOLD_MAX.
func grant_test_gold(account_id: int, amount: int, enabled: bool) -> Dictionary:
	if not enabled:
		return _result(account_id, {"ok": false, "err": "sem_teste", "events": []})
	if amount <= 0 or amount > TEST_GOLD_MAX:
		return _result(account_id, {"ok": false, "err": "valor_invalido", "events": []})
	return grant(account_id, amount, 0, {}, "test")


## Ecos de teste: só com o servidor em --test (`enabled`), 1..TEST_GOLD_MAX. Registrado como "ecos"/"test".
func grant_test_ecos(account_id: int, amount: int, enabled: bool) -> Dictionary:
	if not enabled:
		return _result(account_id, {"ok": false, "err": "sem_teste", "events": []})
	if amount <= 0 or amount > TEST_GOLD_MAX:
		return _result(account_id, {"ok": false, "err": "valor_invalido", "events": []})
	var s := load_or_create(account_id)
	var before := _holdings(s)
	s.ecos += amount
	return _result(account_id, _persist(account_id, s, before, "grant", "test", {"ok": true, "err": "", "events": []}))


## Obsoleta: a Task 4 apaga junto com os chamadores; use finish_player. Uma linha só, ouro em `amount` e xp + itens em `detail`.
## false (e push_error) se não gravou.
func run_summary(account_id: int, mode: String, gold: int, xp: int, items: Dictionary) -> bool:
	var ok := _db.exec("INSERT INTO economy_log(at, account_id, kind, amount, item_id, source, detail) VALUES(?,?,?,?,?,?,?)",
		[int(_now()), account_id, "run", gold, null, mode, JSON.stringify({"xp": xp, "items": items})])
	if not ok:
		push_error("CharacterService: run_summary de %d não gravou: %s" % [account_id, _db.last_error])
	return ok


# ================================================================ base, partidas e recordes
## Estado da base compartilhada: todas as construções (nível 0 as que ninguém tocou).
func base_state() -> Dictionary:
	var out := BaseRules.empty_state(_bt)
	for row in _db.query("SELECT building_id, level, fund FROM base_buildings"):
		out[row["building_id"]] = {"level": int(row["level"]), "fund": int(row["fund"])}
	return out


func base_bonus() -> Dictionary:
	return BaseRules.bonus(_bt, base_state())


## Maiores doadores de uma construção: [{"name", "amount"}], soma por conta, do maior para o menor.
func top_donors(building_id: String, limit := 5) -> Array:
	var out := []
	for row in _db.query("SELECT a.username AS name, SUM(d.amount) AS total FROM base_donations d
			JOIN accounts a ON a.id = d.account_id WHERE d.building_id = ?
			GROUP BY d.account_id ORDER BY total DESC, MIN(d.id) LIMIT ?", [building_id, limit]):
		out.append({"name": str(row["name"]), "amount": int(row["total"])})
	return out


## Abre o registro de uma partida. 0 se não gravou.
func start_run(mode: String, accounts: Array) -> int:
	if not _db.exec("INSERT INTO runs(mode, started_at, players) VALUES(?,?,?)", [mode, int(_now()), JSON.stringify(accounts)]):
		push_error("CharacterService: start_run não gravou: %s" % _db.last_error)
		return 0
	return _db.last_id()


## Fim da partida de um jogador: concede os Ecos e registra. Idempotente por (run_id, conta): repetir
## devolve ok sem conceder de novo. Com run_id <= 0 só concede e registra a economia.
## Ouro, xp e itens já foram concedidos durante a partida (grant); aqui só entram no registro.
func finish_player(run_id: int, account_id: int, mode: String, reached: int, gold: int, xp: int, items: Dictionary, build: Dictionary) -> Dictionary:
	var s := load_or_create(account_id)
	if run_id > 0 and not _db.query("SELECT 1 FROM run_players WHERE run_id = ? AND account_id = ?", [run_id, account_id]).is_empty():
		return _result(account_id, {"ok": true, "err": "", "events": [{"t": "ecos", "n": 0, "mode": mode, "reached": reached}]})
	var ecos := RewardRules.ecos(_bt, mode, reached)
	s.ecos += ecos
	var ok := _db.transaction(func():
		if not _write(account_id, s):
			return false
		if run_id > 0 and not _db.exec("INSERT INTO run_players(run_id, account_id, reached, ecos, gold, xp, build) VALUES(?,?,?,?,?,?,?)",
				[run_id, account_id, reached, ecos, gold, xp, JSON.stringify(build)]):
			return false
		return _db.exec("INSERT INTO economy_log(at, account_id, kind, amount, item_id, source, detail) VALUES(?,?,?,?,?,?,?)",
			[int(_now()), account_id, "run", gold, null, mode,
			JSON.stringify({"xp": xp, "items": items, "ecos": ecos, "run_id": run_id, "reached": reached})]))
	if not ok:
		push_error("CharacterService: finish_player de %d não gravou: %s" % [account_id, _db.last_error])
		_cache.erase(account_id)
		return _result(account_id, {"ok": false, "err": "erro_banco", "events": []})
	_dirty.erase(account_id)
	return _result(account_id, {"ok": true, "err": "", "events": [{"t": "ecos", "n": ecos, "mode": mode, "reached": reached}]})


func close_run(run_id: int, reached: int, result: Dictionary) -> bool:
	return _db.exec("UPDATE runs SET ended_at = ?, reached = ?, result = ? WHERE id = ?",
		[int(_now()), reached, JSON.stringify(result), run_id])


## Recorde de cada modo: a partida encerrada que foi mais longe (empate: a mais antiga) e quem jogou.
func records() -> Dictionary:
	var out := {}
	for mode in ["horde", "city"]:
		var best := {"reached": 0, "names": []}
		var rows := _db.query("SELECT id, reached FROM runs WHERE mode = ? AND ended_at IS NOT NULL AND reached > 0
			ORDER BY reached DESC, id ASC LIMIT 1", [mode])
		if not rows.is_empty():
			best.reached = int(rows[0]["reached"])
			for row in _db.query("SELECT a.username AS name FROM run_players p JOIN accounts a ON a.id = p.account_id
					WHERE p.run_id = ? ORDER BY a.username", [rows[0]["id"]]):
				best.names.append(str(row["name"]))
		out[mode] = best
	return out


## Grava todos os personagens em cache (o servidor desligando). Devolve quantos gravou.
func save_all() -> int:
	var n := 0
	for account_id in _cache.keys():
		if _save(account_id, _cache[account_id]):
			n += 1
		else:
			push_error("CharacterService: personagem %d não gravou ao desligar: %s" % [account_id, _db.last_error])
	return n


## Grava o personagem em cache sem descarregar.
func save(account_id: int) -> bool:
	return not _cache.has(account_id) or _save(account_id, _cache[account_id])


# ================================================================ interno
## Doação à base numa transação só: debita os Ecos, sobe a construção e registra a doação.
## BaseRules valida construção/valor/nível máximo; só então confere os Ecos contra o `used` (o que a
## construção aceita, nunca passa do que falta até o nível máximo): pedir 500 quando faltam 100 com
## 120 Ecos na mão doa 100.
func _donate(account_id: int, s: CharState, building: String, amount: int) -> Dictionary:
	var d := BaseRules.donate(base_state().get(building, {}), _bt, building, amount)
	if not d.ok:
		return _result(account_id, {"ok": false, "err": d.err, "events": []})
	if s.ecos < int(d.used):
		return _result(account_id, {"ok": false, "err": "sem_ecos", "events": []})
	s.ecos -= int(d.used)
	var ok := _db.transaction(func():
		if not _write(account_id, s):
			return false
		var at := int(_now())
		return _db.exec("INSERT OR REPLACE INTO base_buildings(building_id, level, fund) VALUES(?,?,?)",
				[building, d.level, d.fund]) \
			and _db.exec("INSERT INTO base_donations(account_id, building_id, amount, at) VALUES(?,?,?,?)",
				[account_id, building, d.used, at]) \
			and _log(at, account_id, "ecos", -int(d.used), building, "donation"))
	if not ok:
		push_error("CharacterService: doação de %d não gravou: %s" % [account_id, _db.last_error])
		_cache.erase(account_id)
		return _result(account_id, {"ok": false, "err": "erro_banco", "events": []})
	_dirty.erase(account_id)
	var r := _result(account_id, {"ok": true, "err": "", "events": [{"t": "donated", "building": building,
		"used": d.used, "level": d.level, "leveled": d.leveled}]})
	r["base"] = base_state()
	return r


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
		"consume": return CharRules.consume(s, _bt, a[0])
		"cook": return CharRules.cook(s, _bt, a[0], a[1] if a.size() > 1 else 1)
		"spend_point": return CharRules.spend_point(s, _bt, a[0])
		"start_quest": return CharRules.start_quest(s, _bt, a[0])
		"complete_quest": return CharRules.complete_quest(s, _bt, a[0])
		"sort_inventory": return CharRules.sort_inventory(s, _bt)
		"unlock_plot": return CharRules.unlock_plot(s, _bt)
		"plant": return CharRules.plant(s, _bt, a[0], a[1], a[2], _now())
		"water": return CharRules.water(s, _bt, a[0], _now())
		"fertilize": return CharRules.fertilize(s, _bt, a[0], _now())
		"harvest": return CharRules.harvest(s, _bt, a[0], _now(), _rng)
		"discard": return CharRules.discard(s, _bt, a[0])
		"death_penalty": return CharRules.death_penalty(s, _bt)
		"buy_passive": return CharRules.buy_passive(s, _bt, a[0])
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


## Grava estado + linhas da economia numa transação. Falha no banco: descarta o cache e relê do disco.
func _persist(account_id: int, s: CharState, before: Dictionary, kind: String, source: String, r: Dictionary, xp := 0, ecos_item := "") -> Dictionary:
	var after := _holdings(s)
	var ok := _db.transaction(func():
		if not _write(account_id, s):
			return false
		var at := int(_now())
		if xp > 0:
			if not _log(at, account_id, "xp", xp, null, source):
				return false
		if before.is_empty():
			return true
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
			if not _log(at, account_id, log_kind, d, item, source):
				return false
		return true)
	if ok:
		_dirty.erase(account_id)
		return r
	push_error("CharacterService: falha ao gravar %d: %s" % [account_id, _db.last_error])
	_cache.erase(account_id)
	return {"ok": false, "err": "erro_banco", "events": []}


func _log(at: int, account_id: int, kind: String, amount: int, item_id, source: String) -> bool:
	return _db.exec("INSERT INTO economy_log(at, account_id, kind, amount, item_id, source) VALUES(?,?,?,?,?,?)",
		[at, account_id, kind, amount, item_id, source])


func _result(account_id: int, r: Dictionary) -> Dictionary:
	var out := r.duplicate()
	out["state"] = load_or_create(account_id).to_dict()
	return out


func _save(account_id: int, s: CharState) -> bool:
	var ok := _db.transaction(func(): return _write(account_id, s))
	if ok:
		_dirty.erase(account_id)
	return ok


## Dentro de uma transação aberta.
func _write(account_id: int, s: CharState) -> bool:
	if account_id == SOLO_ACCOUNT:
		_db.exec("INSERT OR IGNORE INTO accounts(id, username, pass_hash, pass_salt, provider, created_at) VALUES(?,?,?,?,?,?)",
			[SOLO_ACCOUNT, "local", "", "", "local", int(_now())])
	var d := s.to_dict()
	var pos = d["world_pos"]
	var ok := _db.exec("INSERT INTO characters(account_id, level, xp, gold, ecos, stat_points, attributes, hp, mp, equipment, quests, flags, farm, world_pos, world_yaw, kills, updated_at)
		VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
		ON CONFLICT(account_id) DO UPDATE SET level=excluded.level, xp=excluded.xp, gold=excluded.gold, ecos=excluded.ecos,
		stat_points=excluded.stat_points, attributes=excluded.attributes, hp=excluded.hp, mp=excluded.mp,
		equipment=excluded.equipment, quests=excluded.quests, flags=excluded.flags, farm=excluded.farm,
		world_pos=excluded.world_pos, world_yaw=excluded.world_yaw, kills=excluded.kills, updated_at=excluded.updated_at",
		[account_id, s.level, s.xp, s.gold, s.ecos, s.stat_points, JSON.stringify(d["attributes"]), s.hp, s.mp,
		JSON.stringify(d["equipment"]), JSON.stringify(d["quests"]), JSON.stringify(d["flags"]),
		JSON.stringify(d["farm"]), JSON.stringify(pos), s.world_yaw, s.kills, int(_now())])
	if not ok or not _db.exec("DELETE FROM inventory WHERE account_id = ?", [account_id]):
		return false
	for i in s.inventory.size():
		if not _db.exec("INSERT INTO inventory(account_id, slot_index, item_id, qty) VALUES(?,?,?,?)",
				[account_id, i, s.inventory[i].id, s.inventory[i].qty]):
			return false
	if not _db.exec("DELETE FROM passives WHERE account_id = ?", [account_id]):
		return false
	for id in s.passives:
		if not _db.exec("INSERT INTO passives(account_id, passive_id, level) VALUES(?,?,?)", [account_id, id, int(s.passives[id])]):
			return false
	return true


func _read(account_id: int) -> CharState:
	var rows := _db.query("SELECT * FROM characters WHERE account_id = ?", [account_id])
	if rows.is_empty():
		return null
	var r := rows[0]
	var d := {"level": r["level"], "xp": r["xp"], "gold": r["gold"], "stat_points": r["stat_points"],
		"ecos": r["ecos"], "hp": r["hp"], "mp": r["mp"], "world_yaw": r["world_yaw"], "kills": r["kills"]}
	for k in ["attributes", "equipment", "quests", "flags", "farm", "world_pos"]:
		d[k] = JSON.parse_string(str(r[k]))   # world_pos nulo volta como null
	var inv := []
	for row in _db.query("SELECT item_id, qty FROM inventory WHERE account_id = ? ORDER BY slot_index", [account_id]):
		inv.append({"id": row["item_id"], "qty": row["qty"]})
	d["inventory"] = inv
	var pas := {}
	for row in _db.query("SELECT passive_id, level FROM passives WHERE account_id = ?", [account_id]):
		pas[row["passive_id"]] = row["level"]
	d["passives"] = pas
	return CharState.from_dict(d, _bt)
