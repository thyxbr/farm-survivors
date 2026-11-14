class_name SqliteCharStore
extends CharStore
## Personagens no SQLite (servidor dedicado; tabelas characters, inventory e economy_log das Migrations).
## Cada save_char é uma transação: personagem, mochila e linhas da economia juntos.

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
		"hp": r["hp"], "mp": r["mp"], "world_yaw": r["world_yaw"], "kills": r["kills"],
		"updated_at": r["updated_at"]}
	for k in ["attributes", "equipment", "quests", "flags", "farm", "world_pos"]:
		d[k] = JSON.parse_string(str(r[k]))   # world_pos nulo volta como null
	var inv := []
	for row in db.query("SELECT item_id, qty FROM inventory WHERE account_id = ? ORDER BY slot_index", [account_id]):
		inv.append({"id": row["item_id"], "qty": row["qty"]})
	d["inventory"] = inv
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
			and db.exec("DELETE FROM characters WHERE account_id = ?", [account_id]))
	last_error = "" if ok else db.last_error
	return ok


func close() -> void:
	db.close()


## Dentro de uma transação aberta. A conta local (solo, id 1) é criada na primeira gravação.
func _write(account_id: int, d: Dictionary, at: int) -> bool:
	if account_id == SOLO_ACCOUNT:
		db.exec("INSERT OR IGNORE INTO accounts(id, username, pass_hash, pass_salt, provider, created_at) VALUES(?,?,?,?,?,?)",
			[SOLO_ACCOUNT, "local", "", "", "local", at])
	var ok := db.exec("INSERT INTO characters(account_id, level, xp, gold, stat_points, attributes, hp, mp, equipment, quests, flags, farm, world_pos, world_yaw, kills, updated_at)
		VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
		ON CONFLICT(account_id) DO UPDATE SET level=excluded.level, xp=excluded.xp, gold=excluded.gold,
		stat_points=excluded.stat_points, attributes=excluded.attributes, hp=excluded.hp, mp=excluded.mp,
		equipment=excluded.equipment, quests=excluded.quests, flags=excluded.flags, farm=excluded.farm,
		world_pos=excluded.world_pos, world_yaw=excluded.world_yaw, kills=excluded.kills, updated_at=excluded.updated_at",
		[account_id, d["level"], d["xp"], d["gold"], d["stat_points"], JSON.stringify(d["attributes"]), d["hp"], d["mp"],
		JSON.stringify(d["equipment"]), JSON.stringify(d["quests"]), JSON.stringify(d["flags"]),
		JSON.stringify(d["farm"]), JSON.stringify(d["world_pos"]), d["world_yaw"], d["kills"], at])
	if not ok or not db.exec("DELETE FROM inventory WHERE account_id = ?", [account_id]):
		return false
	var inv: Array = d["inventory"]
	for i in inv.size():
		if not db.exec("INSERT INTO inventory(account_id, slot_index, item_id, qty) VALUES(?,?,?,?)",
				[account_id, i, inv[i]["id"], inv[i]["qty"]]):
			return false
	return true


func _insert_rows(rows: Array) -> bool:
	for r in rows:
		if not db.exec("INSERT INTO economy_log(at, account_id, kind, amount, item_id, source, detail) VALUES(?,?,?,?,?,?,?)",
				[r["at"], r["account_id"], r["kind"], r["amount"], r["item_id"], r["source"], r["detail"]]):
			return false
	return true
