extends RefCounted
## Item que não é equipamento (poção, material, colheita, semente, comida) tem arte pintada em
## assets/ui/items/<id>.png. Item novo sem arte cai no ícone 3D genérico da família e destoa do resto;
## semente nova precisa sair do mesmo saquinho das outras (docs/ICONES_PROMPTS.md, "Semente nova").

const ITEMS_JSON := "res://data/balance/items.json"
const ART := "res://assets/ui/items/%s.png"
const PAINTED := ["consumable", "material", "seed", "crop", "food"]


func _items() -> Dictionary:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ITEMS_JSON))
	return d.get("ITEMS", d)


func test_every_non_gear_item_has_painted_art() -> void:
	var items := _items()
	T.ok(items.size() > 0, "items.json carregou")
	for id in items:
		if str(items[id].get("type", "")) in PAINTED or items[id].has("art"):
			var art := str(items[id].get("art", id))
			T.ok(ResourceLoader.exists(ART % art), "arte pintada de %s em assets/ui/items (%s)" % [id, art])


func test_every_seed_has_a_matching_crop_and_art() -> void:
	var items := _items()
	for id: String in items:
		if str(items[id].get("type", "")) != "seed":
			continue
		var crop := id.trim_prefix("seed_")
		T.ok(items.has(crop), "semente %s tem a colheita %s" % [id, crop])
		T.ok(ResourceLoader.exists(ART % id), "saquinho de %s em assets/ui/items" % id)


func test_art_is_square_256() -> void:
	for f in DirAccess.get_files_at("res://assets/ui/items"):
		if not f.ends_with(".png"):
			continue
		var tex: Texture2D = load("res://assets/ui/items/" + f)
		T.ok(tex != null and tex.get_width() == 256 and tex.get_height() == 256, "%s tem 256x256" % f)
