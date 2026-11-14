class_name FileCharStore
extends CharStore
## Personagens em arquivos JSON (solo offline): o cliente Windows não leva o SQLite (DLL sem assinatura é
## barrada pelo Smart App Control), então o personagem solo mora num arquivo em user://.
## - Personagem: `path` (conta 1) ou `<path sem extensão>_<conta>.json` (outras contas, só em teste).
##   Gravação atômica: escreve `<arquivo>.tmp` inteiro e só então renomeia por cima do antigo; se a
##   escrita do temporário falhar, o arquivo anterior fica intacto.
## - Economia: uma linha JSON por registro em `<path sem extensão>_economy.jsonl` (só acrescenta).
##   Vai depois do personagem: numa queda entre os dois perde-se no máximo o registro, nunca o personagem.
## - Base local: `<path sem extensão>_base.json` ({"buildings": {id: {"level", "fund"}}, "donations": [...]}).
## - Partidas: `<path sem extensão>_runs.json` ({"next_id", "runs": [...]}, cada partida com a parte de
##   cada conta em "done"). Guarda as partidas recentes e o recorde de cada modo (o resto é podado).
## Doação e fim de partida mexem em dois arquivos (base/partidas + personagem): grava primeiro o da
## base/partidas e depois o personagem; se o personagem falhar, o arquivo da base/partidas volta ao que era.
## Assim nunca fica Ecos debitado sem a base creditada, nem partida concedida duas vezes.
## "Novo jogo" (delete_char) apaga o personagem e a economia; a base e os recordes locais continuam.

const SOLO_ACCOUNT := 1
## Partidas mais recentes guardadas no arquivo (além do recorde de cada modo).
const KEEP_RUNS := 20
## Nome da conta solo nos doadores e recordes (o mesmo da conta "local" do SQLite; a praça mostra "Você").
const SOLO_NAME := "local"

var path: String
## Teste: simula falha na escrita do temporário (grava pela metade e desiste antes de renomear).
var fail_next_write := false
## Teste: com fail_next_write, deixa passar esta quantidade de gravações antes da que falha.
var fail_after_writes := 0


func _init(p_path: String) -> void:
	path = p_path


func char_path(account_id: int) -> String:
	return path if account_id == SOLO_ACCOUNT else "%s_%d.json" % [path.get_basename(), account_id]


func economy_path() -> String:
	return path.get_basename() + "_economy.jsonl"


func base_path() -> String:
	return path.get_basename() + "_base.json"


func runs_path() -> String:
	return path.get_basename() + "_runs.json"


## Todos os arquivos deste armazenamento (personagem solo, base, partidas, temporários e economia), para apagar.
func files() -> Array[String]:
	var p := char_path(SOLO_ACCOUNT)
	return [p, p + ".tmp", economy_path(), base_path(), base_path() + ".tmp", runs_path(), runs_path() + ".tmp"]


## Apaga os arquivos do personagem solo, da base, das partidas e da economia (testes e wipe).
func remove_files() -> void:
	for f in files():
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func load_char(account_id: int) -> Variant:
	return _read_json(char_path(account_id))


## Lê um JSON (Dictionary) deste armazenamento; null se não existe ou está estragado (last_error diz).
func _read_json(p: String) -> Variant:
	if not FileAccess.file_exists(p):
		# no Windows o rename apaga o destino antes de mover: se o jogo caiu entre os dois passos,
		# o save inteiro está no .tmp. Recupera em vez de oferecer um personagem novo por cima dele.
		var tmp := p + ".tmp"
		if FileAccess.file_exists(tmp) and JSON.parse_string(FileAccess.get_file_as_string(tmp)) is Dictionary:
			DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(p))
		if not FileAccess.file_exists(p):
			last_error = ""
			return null
	var text := FileAccess.get_file_as_string(p)
	var d = JSON.parse_string(text)
	if not (d is Dictionary):
		# guarda a cópia estragada ao lado antes que um personagem novo grave por cima
		DirAccess.copy_absolute(ProjectSettings.globalize_path(p), ProjectSettings.globalize_path(p + ".invalido"))
		last_error = "arquivo inválido: %s (cópia em .invalido)" % p
		push_error("FileCharStore: %s" % last_error)
		return null
	last_error = ""
	return d


func save_char(account_id: int, state: Dictionary, rows: Array, at: int) -> bool:
	var d := state.duplicate(true)
	d["updated_at"] = at
	if not _write_atomic(char_path(account_id), JSON.stringify(d, "\t")):
		return false
	return rows.is_empty() or append_economy(rows)


func append_economy(rows: Array) -> bool:
	if rows.is_empty():
		return true
	var p := economy_path()
	var f := FileAccess.open(p, FileAccess.READ_WRITE if FileAccess.file_exists(p) else FileAccess.WRITE)
	if f == null:
		last_error = "não abriu %s (erro %d)" % [p, FileAccess.get_open_error()]
		return false
	f.seek_end()
	for r in rows:
		f.store_line(JSON.stringify(r))
	var err := f.get_error()
	f.close()
	last_error = "" if err == OK else "erro %d ao gravar %s" % [err, p]
	return err == OK


## Linhas da economia gravadas (testes e conferência).
func economy_rows() -> Array:
	var out := []
	var p := economy_path()
	if not FileAccess.file_exists(p):
		return out
	for line in FileAccess.get_file_as_string(p).split("\n", false):
		var r = JSON.parse_string(line)
		if r is Dictionary:
			out.append(r)
	return out


## Apaga o personagem e o temporário; o do solo leva junto o registro da economia ("Novo jogo").
func delete_char(account_id: int) -> bool:
	var p := char_path(account_id)
	var gone := [p, p + ".tmp"]
	if account_id == SOLO_ACCOUNT:
		gone.append(economy_path())
	for f in gone:
		if FileAccess.file_exists(f) and DirAccess.remove_absolute(ProjectSettings.globalize_path(f)) != OK:
			last_error = "não apagou %s" % f
			return false
	last_error = ""
	return true


# ================================================================ base local
func _base() -> Dictionary:
	var d = _read_json(base_path())
	var out := {"buildings": {}, "donations": []}
	if d is Dictionary:
		if d.get("buildings") is Dictionary:
			out.buildings = d.buildings
		if d.get("donations") is Array:
			out.donations = d.donations
	return out


func load_base() -> Dictionary:
	var out := {}
	var b: Dictionary = _base().buildings
	for id in b:
		if b[id] is Dictionary:
			out[id] = {"level": int(b[id].get("level", 0)), "fund": int(b[id].get("fund", 0))}
	return out


func save_donation(account_id: int, state: Dictionary, building_id: String, level: int, fund: int,
		amount: int, rows: Array, at: int) -> bool:
	var b := _base()
	b.buildings[building_id] = {"level": level, "fund": fund}
	b.donations.append({"account_id": account_id, "building_id": building_id, "amount": amount, "at": at})
	return _write_with_char(base_path(), b, account_id, state, rows, at)


func top_donors(building_id: String, limit: int) -> Array:
	var totals := {}   # conta -> soma; a ordem de inserção é a da primeira doação (desempate)
	for d in _base().donations:
		if d is Dictionary and str(d.get("building_id", "")) == building_id:
			var acc := int(d.get("account_id", 0))
			totals[acc] = int(totals.get(acc, 0)) + int(d.get("amount", 0))
	var order := totals.keys()   # ordem da primeira doação
	var ranked := order.duplicate()
	ranked.sort_custom(func(a, b) -> bool:
		return totals[a] > totals[b] or (totals[a] == totals[b] and order.find(a) < order.find(b)))
	var out := []
	for acc in ranked.slice(0, maxi(0, limit)):
		out.append({"name": _name(acc), "amount": int(totals[acc])})
	return out


# ================================================================ partidas
func _runs() -> Dictionary:
	var d = _read_json(runs_path())
	var out := {"next_id": 1, "runs": []}
	if d is Dictionary:
		out.next_id = maxi(1, int(d.get("next_id", 1)))
		if d.get("runs") is Array:
			out.runs = d.runs
	return out


func _find_run(runs: Dictionary, run_id: int) -> Variant:
	for r in runs.runs:
		if r is Dictionary and int(r.get("id", 0)) == run_id:
			return r
	return null


func start_run(mode: String, accounts: Array, at: int) -> int:
	var runs := _runs()
	var id := int(runs.next_id)
	runs.next_id = id + 1
	runs.runs.append({"id": id, "mode": mode, "started_at": at, "ended_at": null, "reached": 0,
		"players": accounts.duplicate(), "result": {}, "done": {}})
	_prune(runs)
	return id if _write_atomic(runs_path(), JSON.stringify(runs, "\t")) else 0


## Partidas guardadas no arquivo (testes e conferência).
func run_rows() -> Array:
	return _runs().runs


func run_player_done(run_id: int, account_id: int) -> bool:
	var r = _find_run(_runs(), run_id)
	return r is Dictionary and r.get("done") is Dictionary and r.done.has(str(account_id))


func save_run_player(account_id: int, state: Dictionary, run_id: int, entry: Dictionary, rows: Array, at: int) -> bool:
	if run_id <= 0:
		return save_char(account_id, state, rows, at)
	var runs := _runs()
	var r = _find_run(runs, run_id)
	if not (r is Dictionary):
		last_error = "partida %d não existe" % run_id
		return false
	if not (r.get("done") is Dictionary):
		r["done"] = {}
	r.done[str(account_id)] = {"reached": int(entry.get("reached", 0)), "ecos": int(entry.get("ecos", 0)),
		"gold": int(entry.get("gold", 0)), "xp": int(entry.get("xp", 0)), "build": entry.get("build", {})}
	return _write_with_char(runs_path(), runs, account_id, state, rows, at)


func close_run(run_id: int, reached: int, result: Dictionary, at: int) -> bool:
	var runs := _runs()
	var r = _find_run(runs, run_id)
	if not (r is Dictionary):
		last_error = "partida %d não existe" % run_id
		return false
	r["ended_at"] = at
	r["reached"] = reached
	r["result"] = result
	_prune(runs)
	return _write_atomic(runs_path(), JSON.stringify(runs, "\t"))


func best_run(mode: String) -> Dictionary:
	var best = _best_of(_runs(), mode)
	var out := {"reached": 0, "names": []}
	if best is Dictionary:
		out.reached = int(best.reached)
		var names := []
		for acc in (best.get("done", {}) as Dictionary):
			names.append(_name(int(acc)))
		names.sort()
		out.names = names
	return out


## Partida encerrada que foi mais longe no modo (empate: a mais antiga), ou null.
func _best_of(runs: Dictionary, mode: String) -> Variant:
	var best = null
	for r in runs.runs:
		if not (r is Dictionary) or r.get("mode") != mode or r.get("ended_at") == null or int(r.get("reached", 0)) <= 0:
			continue
		if best == null or int(r.reached) > int(best.reached) \
				or (int(r.reached) == int(best.reached) and int(r.id) < int(best.id)):
			best = r
	return best


## Mantém o arquivo pequeno: as KEEP_RUNS partidas mais recentes e o recorde de cada modo.
func _prune(runs: Dictionary) -> void:
	var list: Array = runs.runs
	if list.size() <= KEEP_RUNS:
		return
	var keep := {}
	for r in list.slice(list.size() - KEEP_RUNS):
		keep[int(r.get("id", 0))] = true
	for r in list:
		var mode = r.get("mode")
		var best = _best_of(runs, str(mode))
		if best is Dictionary:
			keep[int(best.id)] = true
	runs.runs = list.filter(func(r) -> bool: return keep.has(int(r.get("id", 0))))


## Nome de uma conta nos doadores e recordes. No solo só existe a conta local.
func _name(account_id: int) -> String:
	return SOLO_NAME if account_id == SOLO_ACCOUNT else "conta %d" % account_id


## Grava `data` em `p` e depois o personagem (com as linhas da economia). Se o personagem falhar, `p`
## volta ao conteúdo anterior (ou some, se não existia): ou os dois mudam, ou nenhum.
func _write_with_char(p: String, data: Dictionary, account_id: int, state: Dictionary, rows: Array, at: int) -> bool:
	var had := FileAccess.file_exists(p)
	var old := FileAccess.get_file_as_string(p) if had else ""
	if not _write_atomic(p, JSON.stringify(data, "\t")):
		return false
	var d := state.duplicate(true)
	d["updated_at"] = at
	if not _write_atomic(char_path(account_id), JSON.stringify(d, "\t")):
		var err := last_error
		var restored := _write_atomic(p, old) if had else DirAccess.remove_absolute(ProjectSettings.globalize_path(p)) == OK
		if not restored:
			push_error("FileCharStore: não desfez %s depois da falha no personagem" % p)
		last_error = err
		return false
	# a economia vai por último, como em save_char: numa queda perde-se no máximo o registro
	return rows.is_empty() or append_economy(rows)


func _write_atomic(p: String, text: String) -> bool:
	var tmp := p + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		last_error = "não abriu %s (erro %d)" % [tmp, FileAccess.get_open_error()]
		return false
	if fail_next_write and fail_after_writes > 0:
		fail_after_writes -= 1
	elif fail_next_write:
		fail_next_write = false
		f.store_string(text.substr(0, int(text.length() / 2.0)))   # temporário pela metade, como numa queda
		f.close()
		last_error = "falha simulada ao gravar %s" % tmp
		return false
	f.store_string(text)
	var err := f.get_error()
	f.close()
	if err != OK:
		last_error = "erro %d ao gravar %s" % [err, tmp]
		return false
	err = DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(p))
	if err != OK:
		last_error = "erro %d ao renomear %s" % [err, tmp]
		return false
	last_error = ""
	return true
