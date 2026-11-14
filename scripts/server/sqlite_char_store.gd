class_name SqliteCharStore
extends CharStore
## Personagens no SQLite (servidor dedicado; tabelas characters, inventory, passives e economy_log das
## Migrations), mais a base compartilhada (base_buildings, base_donations) e as partidas (runs, run_players).
## Cada gravação é uma transação: personagem, mochila, passivas, linhas da economia e o que vier junto
## (doação, fim de partida).

const SOLO_ACCOUNT := 1

var db: Db


func _init(p_db: Db) -> void:
	db = p_db


func load_char(account_id: int) -> Variant:
	var rows := db.query("SELECT * FROM characters WHERE account_id = ?", [account_id])
	if rows.is_empty():
		last_error = db.last_error
		return null
	var r := rows[0]
	var d := {"level": r["level"], "xp": r["xp"], "gold": r["gold"], "stat_points": r["stat_points"],
		"ecos": r["ecos"], "hp": r["hp"], "mp": r["mp"], "world_yaw": r["world_yaw"], "kills": r["kills"],
		"updated_at": r["updated_at"]}
	for k in ["attributes", "equipment", "quests", "flags", "farm", "world_pos"]:
		d[k] = JSON.parse_string(str(r[k]))   # world_pos nulo volta como null
	var inv := []
	for row in db.query("SELECT item_id, qty FROM inventory WHERE account_id = ? ORDER BY slot_index", [account_id]):
		inv.append({"id": row["item_id"], "qty": row["qty"]})
	d["inventory"] = inv
	var pas := {}
	for row in db.query("SELECT passive_id, level FROM passives WHERE account_id = ?", [account_id]):
		pas[row["passive_id"]] = row["level"]
	d["passives"] = pas
	return d


func save_char(account_id: int, state: Dictionary, rows: Array, at: int) -> bool:
	var ok := db.transaction(func() -> bool:
		return _write(account_id, state, at) and _insert_rows(rows))
	last_error = "" if ok else db.last_error
	return ok


func append_economy(rows: Array) -> bool:
	var ok := db.transaction(func() -> bool: return _insert_rows(rows)) if rows.size() > 1 else _insert_rows(rows)
	last_error = "" if ok else db.last_error
	return ok


func delete_char(account_id: int) -> bool:
	var ok := db.transaction(func() -> bool:
		return db.exec("DELETE FROM inventory WHERE account_id = ?", [account_id]) \
			and db.exec("DELETE FROM passives WHERE account_id = ?", [account_id]) \
			and db.exec("DELETE FROM characters WHERE account_id = ?", [account_id]))
	last_error = "" if ok else db.last_error
	return ok


# ================================================================ base compartilhada
func load_base() -> Dictionary:
	var out := {}
	for row in db.query("SELECT building_id, level, fund FROM base_buildings"):
		out[row["building_id"]] = {"level": int(row["level"]), "fund": int(row["fund"])}
	return out


func save_donation(account_id: int, state: Dictionary, building_id: String, level: int, fund: int,
		amount: int, rows: Array, at: int) -> bool:
	var ok := db.transaction(func() -> bool:
		return _write(account_id, state, at) \
			and db.exec("INSERT OR REPLACE INTO base_buildings(building_id, level, fund) VALUES(?,?,?)",
				[building_id, level, fund]) \
			and db.exec("INSERT INTO base_donations(account_id, building_id, amount, at) VALUES(?,?,?,?)",
				[account_id, building_id, amount, at]) \
			and _insert_rows(rows))
	last_error = "" if ok else db.last_error
	return ok


func top_donors(building_id: String, limit: int) -> Array:
	var out := []
	for row in db.query("SELECT a.username AS name, SUM(d.amount) AS total FROM base_donations d
			JOIN accounts a ON a.id = d.account_id WHERE d.building_id = ?
			GROUP BY d.account_id ORDER BY total DESC, MIN(d.id) LIMIT ?", [building_id, limit]):
		out.append({"name": str(row["name"]), "amount": int(row["total"])})
	return out


# ================================================================ partidas
func start_run(mode: String, accounts: Array, at: int) -> int:
	if not db.exec("INSERT INTO runs(mode, started_at, players) VALUES(?,?,?)", [mode, at, JSON.stringify(accounts)]):
		last_error = db.last_error
		return 0
	last_error = ""
	return db.last_id()


func run_player_done(run_id: int, account_id: int) -> bool:
	return not db.query("SELECT 1 FROM run_players WHERE run_id = ? AND account_id = ?", [run_id, account_id]).is_empty()


func save_run_player(account_id: int, state: Dictionary, run_id: int, entry: Dictionary, rows: Array, at: int) -> bool:
	var ok := db.transaction(func() -> bool:
		if not _write(account_id, state, at):
			return false
		if run_id > 0 and not db.exec("INSERT INTO run_players(run_id, account_id, reached, ecos, gold, xp, build) VALUES(?,?,?,?,?,?,?)",
				[run_id, account_id, int(entry.get("reached", 0)), int(entry.get("ecos", 0)), int(entry.get("gold", 0)),
				int(entry.get("xp", 0)), JSON.stringify(entry.get("build", {}))]):
			return false
		return _insert_rows(rows))
	last_error = "" if ok else db.last_error
	return ok


func close_run(run_id: int, reached: int, result: Dictionary, at: int) -> bool:
	var ok := db.exec("UPDATE runs SET ended_at = ?, reached = ?, result = ? WHERE id = ?",
		[at, reached, JSON.stringify(result), run_id])
	last_error = "" if ok else db.last_error
	return ok


func best_run(mode: String) -> Dictionary:
	var best := {"reached": 0, "names": []}
	var rows := db.query("SELECT id, reached FROM runs WHERE mode = ? AND ended_at IS NOT NULL AND reached > 0
		ORDER BY reached DESC, id ASC LIMIT 1", [mode])
	if not rows.is_empty():
		best.reached = int(rows[0]["reached"])
		for row in db.query("SELECT a.username AS name FROM run_players p JOIN accounts a ON a.id = p.account_id
				WHERE p.run_id = ? ORDER BY a.username", [rows[0]["id"]]):
			best.names.append(str(row["name"]))
	return best


func close() -> void:
	db.close()


## Dentro de uma transação aberta. A conta local (solo, id 1) é criada na primeira gravação.
func _write(account_id: int, d: Dictionary, at: int) -> bool:
	if account_id == SOLO_ACCOUNT:
		db.exec("INSERT OR IGNORE INTO accounts(id, username, pass_hash, pass_salt, provider, created_at) VALUES(?,?,?,?,?,?)",
			[SOLO_ACCOUNT, "local", "", "", "local", at])
	var ok := db.exec("INSERT INTO characters(account_id, level, xp, gold, ecos, stat_points, attributes, hp, mp, equipment, quests, flags, farm, world_pos, world_yaw, kills, updated_at)
		VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
		ON CONFLICT(account_id) DO UPDATE SET level=excluded.level, xp=excluded.xp, gold=excluded.gold, ecos=excluded.ecos,
		stat_points=excluded.stat_points, attributes=excluded.attributes, hp=excluded.hp, mp=excluded.mp,
		equipment=excluded.equipment, quests=excluded.quests, flags=excluded.flags, farm=excluded.farm,
		world_pos=excluded.world_pos, world_yaw=excluded.world_yaw, kills=excluded.kills, updated_at=excluded.updated_at",
		[account_id, d["level"], d["xp"], d["gold"], int(d.get("ecos", 0)), d["stat_points"], JSON.stringify(d["attributes"]), d["hp"], d["mp"],
		JSON.stringify(d["equipment"]), JSON.stringify(d["quests"]), JSON.stringify(d["flags"]),
		JSON.stringify(d["farm"]), JSON.stringify(d["world_pos"]), d["world_yaw"], d["kills"], at])
	if not ok or not db.exec("DELETE FROM inventory WHERE account_id = ?", [account_id]):
		return false
	var inv: Array = d["inventory"]
	for i in inv.size():
		if not db.exec("INSERT INTO inventory(account_id, slot_index, item_id, qty) VALUES(?,?,?,?)",
				[account_id, i, inv[i]["id"], inv[i]["qty"]]):
			return false
	if not db.exec("DELETE FROM passives WHERE account_id = ?", [account_id]):
		return false
	var pas: Dictionary = d.get("passives", {})
	for id in pas:
		if not db.exec("INSERT INTO passives(account_id, passive_id, level) VALUES(?,?,?)", [account_id, id, int(pas[id])]):
			return false
	return true


func _insert_rows(rows: Array) -> bool:
	for r in rows:
		if not db.exec("INSERT INTO economy_log(at, account_id, kind, amount, item_id, source, detail) VALUES(?,?,?,?,?,?,?)",
				[r["at"], r["account_id"], r["kind"], r["amount"], r["item_id"], r["source"], r["detail"]]):
			return false
	return true
