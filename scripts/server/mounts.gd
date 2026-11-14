class_name Mounts
extends RefCounted
## Confere se a pasta do banco é um ponto de montagem (volume do Easypanel/Docker) lendo /proc/mounts (Linux).
## Com DB_REQUIRE_MOUNT=1 (o Dockerfile define) o servidor se recusa a subir sem o volume: sem ele o banco
## ficaria na camada do container e cada deploy apagaria todas as contas.


## `dir` aparece como ponto de montagem (2º campo) em alguma linha de `mounts_text` (formato do /proc/mounts)?
## Espaços e afins vêm escapados em octal no arquivo ("\040"). Barra no fim de `dir` não importa.
static func is_mount_point(dir: String, mounts_text: String) -> bool:
	var want := _norm(dir)
	if want.is_empty():
		return false
	for line in mounts_text.split("\n", false):
		var f := line.strip_edges().split(" ", false)
		if f.size() >= 2 and _norm(_unescape(f[1])) == want:
			return true
	return false


## Conteúdo do /proc/mounts ("" se não deu para ler). Os arquivos do /proc dizem tamanho 0: lê linha a linha.
static func read_proc_mounts() -> String:
	var f := FileAccess.open("/proc/mounts", FileAccess.READ)
	if f == null:
		return ""
	var out := PackedStringArray()
	while true:
		var line := f.get_line()
		if f.eof_reached() and line.is_empty():
			break
		out.append(line)
		if out.size() > 100000:
			break
	return "\n".join(out)


static func _norm(p: String) -> String:
	var s := p.strip_edges()
	while s.length() > 1 and s.ends_with("/"):
		s = s.substr(0, s.length() - 1)
	return s


## "\040" -> " " (o kernel escapa espaço, tab, quebra de linha e barra invertida em octal).
static func _unescape(s: String) -> String:
	if s.find("\\") < 0:
		return s
	var out := ""
	var i := 0
	while i < s.length():
		if s[i] == "\\" and i + 3 < s.length() and s.substr(i + 1, 3).is_valid_int():
			out += char(_octal(s.substr(i + 1, 3)))
			i += 4
		else:
			out += s[i]
			i += 1
	return out


static func _octal(digits: String) -> int:
	var v := 0
	for c in digits:
		v = v * 8 + int(c)
	return v
