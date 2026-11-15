extends RefCounted
## IconCache: ícones de item guardados em disco, por versão do jogo.

const ROOT := "user://test_icons"


func _clean() -> void:
	IconCache.prune(ROOT, "")


func test_roundtrip() -> void:
	_clean()
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	T.ok(IconCache.load_icon(ROOT, "1.0.0", "sword") == null, "sem arquivo devolve null")
	T.ok(IconCache.save_icon(ROOT, "1.0.0", "sword", img), "salva")
	var tex := IconCache.load_icon(ROOT, "1.0.0", "sword")
	T.ok(tex != null and tex.get_width() == 8, "lê o que salvou")
	_clean()


func test_other_version_is_ignored_and_pruned() -> void:
	_clean()
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	IconCache.save_icon(ROOT, "1.0.0", "sword", img)
	T.ok(IconCache.load_icon(ROOT, "1.1.0", "sword") == null, "ícone de outra versão não vale")
	T.eq(IconCache.prune(ROOT, "1.1.0"), 1, "apaga a pasta da versão antiga")
	T.ok(IconCache.load_icon(ROOT, "1.0.0", "sword") == null, "o arquivo antigo sumiu")


func test_corrupt_file_is_ignored() -> void:
	_clean()
	var p := IconCache.path_for(ROOT, "1.0.0", "sword")
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string("isto não é um png")
	f.close()
	T.ok(IconCache.load_icon(ROOT, "1.0.0", "sword") == null, "arquivo corrompido devolve null, sem erro")
	_clean()


func test_id_cannot_escape_the_folder() -> void:
	T.ok(not IconCache.path_for(ROOT, "1.0.0", "../../save").contains(".."), "id com .. não sai da pasta")
