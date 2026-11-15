class_name IconCache
extends RefCounted
## Ícones de item guardados em disco, uma pasta por versão do jogo: `<root>/<versão>/<id>.png`.
## Script puro: não cita autoload, para rodar no executor unitário.


static func path_for(root: String, version: String, id: String) -> String:
	return "%s/%s/%s.png" % [root, _safe(version), _safe(id)]


## Textura guardada, ou null se o arquivo não existe ou não é um PNG válido.
static func load_icon(root: String, version: String, id: String) -> Texture2D:
	var path := path_for(root, version, id)
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	# confere a assinatura antes: `load_png_from_buffer` imprime erro no log com lixo
	if bytes.size() < 8 or bytes.slice(0, 8) != PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]):
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


static func save_icon(root: String, version: String, id: String, img: Image) -> bool:
	var path := path_for(root, version, id)
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return false
	return img.save_png(path) == OK


## Apaga as pastas de outras versões (`keep_version` "" apaga todas); devolve quantas apagou.
static func prune(root: String, keep_version: String) -> int:
	var dir := DirAccess.open(root)
	if dir == null:
		return 0
	var keep := _safe(keep_version) if keep_version != "" else ""
	var removed := 0
	for sub in dir.get_directories():
		if sub == keep:
			continue
		var d := DirAccess.open(root + "/" + sub)
		if d == null:
			continue
		for f in d.get_files():
			d.remove(f)
		if dir.remove(sub) == OK:
			removed += 1
	return removed


## Só letras, números, `_`, `-` e `.` isolado: um id não consegue sair da pasta.
static func _safe(s: String) -> String:
	var out := ""
	for ch in s:
		var ok := (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "_" or ch == "-"
		out += ch if ok or (ch == "." and not out.ends_with(".")) else "_"
	return out.trim_prefix(".").trim_suffix(".") if out.strip_edges() != "" else "_"
