extends RefCounted
## VillageLayout: a planta da vila (scenes/village.tscn) não pode ter construção dentro de outra, casa em cima
## da rua (a não ser a borda de um alpendre) nem nada fora da cerca. Mexeu na cena no editor? Rode este teste.

## As construções vêm de scenes/village.tscn (VillageLayout.buildings()) e podem ter qualquer giro, então
## a pegada é um retângulo girado: [cantos (4 × Vector2), descrição].


## Pegada (largura, profundidade) de uma construção.
func _size(b: Dictionary) -> Vector2:
	if VillageLayout.HOUSE_SIZE.has(b.model):
		var s: Vector3 = VillageLayout.HOUSE_SIZE[b.model]
		return Vector2(s.x, s.z)
	return VillageLayout.FOOTPRINT[b.model]


func _foot(b: Dictionary) -> Array:
	var sz := _size(b)
	var xf := VillageLayout.xform(b)
	var out: Array = []
	for c in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]:
		var p: Vector3 = xf * Vector3(c.x * sz.x / 2.0, 0, c.z * sz.y / 2.0)
		out.append(Vector2(p.x, p.z))
	return [out, "%s (%s em %s)" % [b.name, b.model, str(b.pos)]]


func _all(only_houses := false) -> Array:
	var out: Array = []
	for b in (VillageLayout.houses() if only_houses else VillageLayout.buildings()):
		out.append(_foot(b))
	return out


## Retângulo do chão que cobre os cantos.
func _bounds(pts: Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r


## Dois retângulos girados se cruzam (eixos separadores), com folga de 5 cm.
func _overlap(a: Array, b: Array) -> bool:
	for poly in [a, b]:
		for i in 4:
			var e: Vector2 = poly[(i + 1) % 4] - poly[i]
			var axis := Vector2(-e.y, e.x).normalized()
			var amin := INF
			var amax := -INF
			var bmin := INF
			var bmax := -INF
			for p in a:
				amin = minf(amin, axis.dot(p))
				amax = maxf(amax, axis.dot(p))
			for p in b:
				bmin = minf(bmin, axis.dot(p))
				bmax = maxf(bmax, axis.dot(p))
			if amax - 0.05 <= bmin or bmax - 0.05 <= amin:
				return false
	return true


func test_scene_has_the_village() -> void:
	var count := {}
	for b in VillageLayout.buildings():
		count[b.model] = int(count.get(b.model, 0)) + 1
	T.ok(VillageLayout.houses().size() >= 6, "casas na cena (%d)" % VillageLayout.houses().size())
	for m in ["well", "shop_merchant", "shop_alchemist", "shop_smithy"]:
		T.eq(int(count.get(m, 0)), 1, "um %s na cena" % m)
	for b in VillageLayout.buildings():
		T.ok(VillageLayout.HOUSE_SIZE.has(b.model) or VillageLayout.FOOTPRINT.has(b.model),
			"%s tem tamanho conhecido" % b.name)
		T.ok(int(b.palette) < VillageLayout.PALETTES.size(), "%s com paleta que existe" % b.name)


func test_houses_do_not_overlap() -> void:
	var hs := _all()
	for i in hs.size():
		for j in range(i + 1, hs.size()):
			T.ok(not _overlap(hs[i][0], hs[j][0]), "%s não encosta em %s" % [hs[i][1], hs[j][1]])


func test_houses_inside_fence() -> void:
	var fence: Rect2 = VillageLayout.BOUNDS
	for h in _all():
		T.ok(fence.encloses(_bounds(h[0])), "%s dentro da cerca" % h[1])


func test_houses_off_the_streets() -> void:
	for h in _all(true):
		for st in VillageLayout.STREETS:
			var c: Vector3 = st[0]
			var sz: Vector2 = st[1]
			var road := Rect2(c.x - sz.x / 2.0, c.z - sz.y / 2.0, sz.x, sz.y)
			var inter: Rect2 = _bounds(h[0]).intersection(road)
			T.ok(inter.get_area() < 0.6, "%s fora da rua em %s (%.2f m²)" % [h[1], str(c), inter.get_area()])


func test_event_spots() -> void:
	T.eq(VillageLayout.GIFTS.size(), 8, "8 presentes, como a missão pede")
	T.eq(VillageLayout.deliveries().size(), 6, "6 casas de entrega (delivery) na cena, como a missão pede")
	var fence: Rect2 = VillageLayout.BOUNDS
	for g in VillageLayout.GIFTS:
		T.ok(not fence.has_point(Vector2(g.x, g.z)), "presente %s fora da vila" % str(g))
		T.ok(absf(g.x) < 118.0 and absf(g.z) < 118.0, "presente %s dentro do mapa" % str(g))


func test_palette_swap() -> void:
	var pal: Array = VillageLayout.PALETTES[2]
	T.eq(VillageLayout._swap("p_roof", Color(0.5, 0.1, 0.1), pal), pal[1], "telhado troca de cor")
	T.eq(VillageLayout._swap("v_shutter_green", Color(0, 0.3, 0), pal), pal[2], "veneziana troca de cor")
	var c := Color(0.5, 0.5, 0.5)
	T.eq(VillageLayout._swap("v_timber", c, pal), c, "madeira fica como está")
	T.eq(VillageLayout._swap("v_plaster_dark", c, pal), c, "reboco escuro do térreo fica como está")
	T.ok(VillageLayout._swap("v_plaster", c, pal) != c, "reboco muda de tom")
