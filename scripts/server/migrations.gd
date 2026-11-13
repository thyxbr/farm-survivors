class_name Migrations
extends RefCounted
## Migrações versionadas do banco. Cada item de MIGRATIONS é a versão (índice + 1) e é uma lista de comandos SQL.
## Nunca edite uma migração já publicada: acrescente outra no fim.

const MIGRATIONS := [
	# v1: fundação (spec §5.2)
	[
		"CREATE TABLE accounts (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			username TEXT NOT NULL COLLATE NOCASE UNIQUE,
			pass_hash TEXT NOT NULL,
			pass_salt TEXT NOT NULL,
			provider TEXT NOT NULL DEFAULT 'password',
			provider_uid TEXT,
			is_admin INTEGER NOT NULL DEFAULT 0,
			created_at INTEGER NOT NULL,
			last_login INTEGER
		)",
		"CREATE TABLE sessions (
			token TEXT PRIMARY KEY,
			account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
			expires_at INTEGER NOT NULL
		)",
		"CREATE INDEX idx_sessions_account ON sessions(account_id)",
		"CREATE TABLE characters (
			account_id INTEGER PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
			level INTEGER NOT NULL DEFAULT 1,
			xp INTEGER NOT NULL DEFAULT 0,
			gold INTEGER NOT NULL DEFAULT 0,
			ecos INTEGER NOT NULL DEFAULT 0,
			stat_points INTEGER NOT NULL DEFAULT 0,
			attributes TEXT NOT NULL DEFAULT '{}',
			hp REAL NOT NULL DEFAULT 0,
			mp REAL NOT NULL DEFAULT 0,
			equipment TEXT NOT NULL DEFAULT '{}',
			quests TEXT NOT NULL DEFAULT '{}',
			flags TEXT NOT NULL DEFAULT '{}',
			farm TEXT NOT NULL DEFAULT '{}',
			world_pos TEXT NOT NULL DEFAULT '{}',
			updated_at INTEGER NOT NULL DEFAULT 0
		)",
		# a mochila é ordenada: slot_index preserva a posição de cada pilha
		"CREATE TABLE inventory (
			account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
			slot_index INTEGER NOT NULL,
			item_id TEXT NOT NULL,
			qty INTEGER NOT NULL DEFAULT 1,
			PRIMARY KEY (account_id, slot_index)
		)",
		"CREATE TABLE passives (
			account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
			passive_id TEXT NOT NULL,
			level INTEGER NOT NULL DEFAULT 1,
			PRIMARY KEY (account_id, passive_id)
		)",
		"CREATE TABLE base_buildings (
			building_id TEXT PRIMARY KEY,
			level INTEGER NOT NULL DEFAULT 0,
			fund INTEGER NOT NULL DEFAULT 0
		)",
		"CREATE TABLE base_donations (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			account_id INTEGER NOT NULL REFERENCES accounts(id),
			building_id TEXT NOT NULL,
			amount INTEGER NOT NULL,
			at INTEGER NOT NULL
		)",
		"CREATE TABLE balance_tables (
			name TEXT PRIMARY KEY,
			data TEXT NOT NULL,
			version INTEGER NOT NULL DEFAULT 1,
			updated_at INTEGER NOT NULL DEFAULT 0,
			updated_by INTEGER
		)",
		"CREATE TABLE balance_history (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			name TEXT NOT NULL,
			data TEXT NOT NULL,
			version INTEGER NOT NULL,
			at INTEGER NOT NULL,
			by_account INTEGER
		)",
		"CREATE TABLE runs (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			mode TEXT NOT NULL,
			started_at INTEGER NOT NULL,
			ended_at INTEGER,
			reached INTEGER NOT NULL DEFAULT 0,
			players TEXT NOT NULL DEFAULT '[]',
			result TEXT NOT NULL DEFAULT '{}'
		)",
		"CREATE TABLE run_players (
			run_id INTEGER NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
			account_id INTEGER NOT NULL REFERENCES accounts(id),
			reached INTEGER NOT NULL DEFAULT 0,
			ecos INTEGER NOT NULL DEFAULT 0,
			gold INTEGER NOT NULL DEFAULT 0,
			xp INTEGER NOT NULL DEFAULT 0,
			build TEXT NOT NULL DEFAULT '{}',
			PRIMARY KEY (run_id, account_id)
		)",
		"CREATE TABLE economy_log (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			at INTEGER NOT NULL,
			account_id INTEGER NOT NULL,
			kind TEXT NOT NULL,
			amount INTEGER NOT NULL DEFAULT 0,
			item_id TEXT,
			source TEXT
		)",
		"CREATE INDEX idx_economy_account ON economy_log(account_id, at)",
	],
	# v2: o CharState guarda direção e abates, que a v1 não tinha
	[
		"ALTER TABLE characters ADD COLUMN world_yaw REAL NOT NULL DEFAULT 0",
		"ALTER TABLE characters ADD COLUMN kills INTEGER NOT NULL DEFAULT 0",
	],
]


## Aplica as migrações que faltam, cada uma numa transação, e devolve a versão final (-1 se alguma falhou).
## Idempotente: rodar de novo num banco atualizado não faz nada.
static func apply(db: Db) -> int:
	if not db.exec("CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL, applied_at INTEGER NOT NULL)"):
		push_error("Migrations: não criou schema_version: %s" % db.last_error)
		return -1
	var rows := db.query("SELECT COALESCE(MAX(version), 0) AS v FROM schema_version")
	var current := int(rows[0]["v"]) if not rows.is_empty() else 0
	for v in range(current + 1, MIGRATIONS.size() + 1):
		var stmts: Array = MIGRATIONS[v - 1]
		var ok := db.transaction(func():
			for s in stmts:
				if not db.exec(s):
					push_error("Migrations: v%d falhou: %s" % [v, db.last_error])
					return false
			return db.exec("INSERT INTO schema_version(version, applied_at) VALUES(?, ?)", [v, int(Time.get_unix_time_from_system())]))
		if not ok:
			return -1
		current = v
	return current
