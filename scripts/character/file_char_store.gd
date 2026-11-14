class_name FileCharStore
extends CharStore
## Personagens em arquivos JSON (solo offline): o cliente Windows não leva o SQLite (DLL sem assinatura é
## barrada pelo Smart App Control), então o personagem solo mora num arquivo em user://.
## - Personagem: `path` (conta 1) ou `<path sem extensão>_<conta>.json` (outras contas, só em teste).
##   Gravação atômica: escreve `<arquivo>.tmp` inteiro e só então renomeia por cima do antigo; se a
##   escrita do temporário falhar, o arquivo anterior fica intacto.
## - Economia: uma linha JSON por registro em `<path sem extensão>_economy.jsonl` (só acrescenta).
##   Vai depois do personagem: numa queda entre os dois perde-se no máximo o registro, nunca o personagem.

const SOLO_ACCOUNT := 1

var path: String
## Teste: simula falha na escrita do temporário (grava pela metade e desiste antes de renomear).
var fail_next_write := false


func _init(p_path: String) -> void:
	path = p_path


func char_path(account_id: int) -> String:
	return path if account_id == SOLO_ACCOUNT else "%s_%d.json" % [path.get_basename(), account_id]


func economy_path() -> String:
	return path.get_basename() + "_economy.jsonl"


## Todos os arquivos deste armazenamento (personagem solo, temporário e economia), para apagar.
func files() -> Array[String]:
	var p := char_path(SOLO_ACCOUNT)
	return [p, p + ".tmp", economy_path()]


## Apaga os arquivos do personagem solo e da economia (testes e wipe).
func remove_files() -> void:
	for f in files():
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func load_char(account_id: int) -> Variant:
	var p := char_path(account_id)
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


func _write_atomic(p: String, text: String) -> bool:
	var tmp := p + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		last_error = "não abriu %s (erro %d)" % [tmp, FileAccess.get_open_error()]
		return false
	if fail_next_write:
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
