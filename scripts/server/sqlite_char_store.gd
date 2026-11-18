class_name SqliteCharStore
extends CharStore
## Personagens no SQLite (servidor dedicado; tabelas characters, inventory, passives e economy_log das
## Migrations), mais as partidas (runs, run_players). Uma conta tem vários personagens (id próprio);
## mochila e passivas são do personagem; economia e partidas são da conta (owner_of).
## Cada gravação é uma transação: personagem, mochila, passivas, linhas da economia e o que vier junto
## (fim de partida).

const SOLO_ACCOUNT := 1

var db: Db


func _init(p_db: Db) -> void:
	db = p_db


func load_char(char_id: int) -> Variant:
	var rows := db.query("SELECT * FROM characters WHERE id = ?", [char_id])
	if rows.is_empty():
		last_error = db.last_error
		return null
	var r := rows[0]
	var d := {"level": r["level"], "xp": r["xp"], "gold": r["gold"], "stat_points": r["stat_points"],
		"ecos": r["ecos"], "hp": r["hp"], "mp": r["mp"], "world_yaw": r["world_yaw"], "kills": r["kills"],
		"updated_at": r["updated_at"]}
	d["char_class"] = str(r["char_class"])
	d["body"] = str(r["body"])
	d["hair"] = str(r["hair"])
	for k in ["attributes", "equipment", "quests", "flags", "farm", "world_pos", "enchants", "talents"]:
		d[k] = JSON.parse_string(str(r[k]))   # world_pos nulo volta como null
	var inv := []
	for row in db.query("SELECT item_id, qty FROM inventory WHERE char_id = ? ORDER BY slot_index", [char_id]):
		inv.append({"id": row["item_id"], "qty": row["qty"]})
	d["inventory"] = inv
	var pas := {}
	for row in db.query("SELECT passive_id, level FROM passives WHERE char_id = ?", [char_id]):
		pas[row["passive_id"]] = row["level"]
	d["passives"] = pas
	return d


func owner_of(char_id: int) -> int:
	var rows := db.query("SELECT account_id FROM characters WHERE id = ?", [char_id])
	return int(rows[0]["account_id"]) if not rows.is_empty() else char_id


func create_char(account_id: int, name: String, state: Dictionary, at: int) -> int:
	if name_taken(name):
		last_error = "nome_em_uso"
		return 0
	var box := [0]   # a lambda captura locais por valor: o id volta dentro do Array
	var ok := db.transaction(func() -> bool:
		if not db.exec("INSERT INTO characters(account_id, name, created_at, updated_at) VALUES(?,?,?,?)",
				[account_id, name, at, at]):
			return false
		box[0] = db.last_id()
		return _write(box[0], state, at))
	last_error = "" if ok else db.last_error
	return int(box[0]) if ok else 0


func list_chars(account_id: int) -> Array:
	var out := []
	for r in db.query("SELECT id, name, level, char_class, body, hair, equipment, updated_at FROM characters
			WHERE account_id = ? ORDER BY id", [account_id]):
		var eq = JSON.parse_string(str(r["equipment"]))
		out.append({"id": int(r["id"]), "name": str(r["name"]), "level": int(r["level"]), "char_class": str(r["char_class"]),
			"body": str(r["body"]), "hair": str(r["hair"]), "equipment": eq if eq is Dictionary else {}, "updated_at": int(r["updated_at"])})
	return out


func name_of(char_id: int) -> String:
	var rows := db.query("SELECT name FROM characters WHERE id = ?", [char_id])
	return str(rows[0]["name"]) if not rows.is_empty() else ""


func name_taken(name: String) -> bool:
	return name.strip_edges() != "" and not db.query("SELECT 1 FROM characters WHERE name = ?", [name.strip_edges()]).is_empty()


func account_by_char_name(name: String) -> int:
	var rows := db.query("SELECT account_id FROM characters WHERE name = ? AND name != ''", [name.strip_edges()])
	return int(rows[0]["account_id"]) if not rows.is_empty() else 0


func save_char(char_id: int, state: Dictionary, rows: Array, at: int) -> bool:
	var ok := db.transaction(func() -> bool:
		return _write(char_id, state, at) and _insert_rows(rows))
	last_error = "" if ok else db.last_error
	return ok


func append_economy(rows: Array) -> bool:
	var ok := db.transaction(func() -> bool: return _insert_rows(rows)) if rows.size() > 1 else _insert_rows(rows)
	last_error = "" if ok else db.last_error
	return ok


## Mochila e passivas saem junto (ON DELETE CASCADE).
func delete_char(char_id: int) -> bool:
	var ok := db.exec("DELETE FROM characters WHERE id = ?", [char_id])
	last_error = "" if ok else db.last_error
	return ok


# ================================================================ partidas
func start_run(mode: String, accounts: Array, at: int) -> int:
	if not db.exec("INSERT INTO runs(mode, started_at, players) VALUES(?,?,?)", [mode, at, JSON.stringify(accounts)]):
		last_error = db.last_error
		return 0
	last_error = ""
	return db.last_id()


func run_player_done(run_id: int, char_id: int) -> bool:
	return not db.query("SELECT 1 FROM run_players WHERE run_id = ? AND account_id = ?", [run_id, owner_of(char_id)]).is_empty()


func save_run_player(char_id: int, state: Dictionary, run_id: int, entry: Dictionary, rows: Array, at: int) -> bool:
	var account_id := owner_of(char_id)
	var ok := db.transaction(func() -> bool:
		if not _write(char_id, state, at):
			return false
		# partida inexistente (id inválido): concede mesmo assim, só sem a linha em run_players
		var has_run := run_id > 0 and not db.query("SELECT 1 FROM runs WHERE id = ?", [run_id]).is_empty()
		var cname := name_of(char_id)
		if has_run and not db.exec("INSERT INTO run_players(run_id, account_id, reached, ecos, gold, xp, build, char_name) VALUES(?,?,?,?,?,?,?,?)",
				[run_id, account_id, int(entry.get("reached", 0)), int(entry.get("ecos", 0)), int(entry.get("gold", 0)),
				int(entry.get("xp", 0)), JSON.stringify(entry.get("build", {})), cname if cname != "" else null]):
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
		# o nome do herói que jogou (partidas de antes dos nomes: o da conta)
		for row in db.query("SELECT COALESCE(p.char_name, a.username) AS name FROM run_players p
				JOIN accounts a ON a.id = p.account_id WHERE p.run_id = ? ORDER BY name COLLATE NOCASE", [rows[0]["id"]]):
			best.names.append(str(row["name"]))
	return best


func close() -> void:
	db.close()


## Dentro de uma transação aberta. Personagem que ainda não existe (solo e testes, que usam personagem N
## da conta N): a linha é criada com id = conta = `char_id`; a conta local (solo, id 1) é criada junto.
func _write(char_id: int, d: Dictionary, at: int) -> bool:
	if db.query("SELECT 1 FROM characters WHERE id = ?", [char_id]).is_empty():
		if char_id == SOLO_ACCOUNT:
			db.exec("INSERT OR IGNORE INTO accounts(id, username, pass_hash, pass_salt, provider, created_at) VALUES(?,?,?,?,?,?)",
				[SOLO_ACCOUNT, "local", "", "", "local", at])
		if not db.exec("INSERT INTO characters(id, account_id, created_at) VALUES(?,?,?)", [char_id, char_id, at]):
			return false
	var ok := db.exec("UPDATE characters SET level=?, xp=?, gold=?, ecos=?, stat_points=?, attributes=?, hp=?, mp=?,
		equipment=?, quests=?, flags=?, farm=?, world_pos=?, world_yaw=?, kills=?, enchants=?, char_class=?, body=?,
		hair=?, talents=?, updated_at=? WHERE id = ?",
		[d["level"], d["xp"], d["gold"], int(d.get("ecos", 0)), d["stat_points"], JSON.stringify(d["attributes"]), d["hp"], d["mp"],
		JSON.stringify(d["equipment"]), JSON.stringify(d["quests"]), JSON.stringify(d["flags"]),
		JSON.stringify(d["farm"]), JSON.stringify(d["world_pos"]), d["world_yaw"], d["kills"],
		JSON.stringify(d.get("enchants", {})), str(d.get("char_class", "")), str(d.get("body", "")), str(d.get("hair", "")),
		JSON.stringify(d.get("talents", {})), at, char_id])
	if not ok or not db.exec("DELETE FROM inventory WHERE char_id = ?", [char_id]):
		return false
	var inv: Array = d["inventory"]
	for i in inv.size():
		if not db.exec("INSERT INTO inventory(char_id, slot_index, item_id, qty) VALUES(?,?,?,?)",
				[char_id, i, inv[i]["id"], inv[i]["qty"]]):
			return false
	if not db.exec("DELETE FROM passives WHERE char_id = ?", [char_id]):
		return false
	var pas: Dictionary = d.get("passives", {})
	for id in pas:
		if not db.exec("INSERT INTO passives(char_id, passive_id, level) VALUES(?,?,?)", [char_id, id, int(pas[id])]):
			return false
	return true


func _insert_rows(rows: Array) -> bool:
	for r in rows:
		var cid := int(r.get("char_id", 0))
		if not db.exec("INSERT INTO economy_log(at, account_id, kind, amount, item_id, source, detail, char_id) VALUES(?,?,?,?,?,?,?,?)",
				[r["at"], r["account_id"], r["kind"], r["amount"], r["item_id"], r["source"], r["detail"],
				cid if cid > 0 else null]):
			return false
	return true
