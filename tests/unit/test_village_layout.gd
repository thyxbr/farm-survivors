extends RefCounted
## VillageLayout: a planta da vila não pode ter casa dentro de casa, casa em cima da rua (a não ser a borda
## de um alpendre) nem nada fora da cerca. As seis casas da praça e as três lojas ficam onde sempre ficaram.

## As seis casas da praça e as lojas (world.gd): [centro, yaw, largura, profundidade].
const OLD := [
	[Vector3(-13, 0, -6), PI / 2, 5.2, 4.2], [Vector3(-13, 0, 7), PI / 2, 5.2, 4.2],
	[Vector3(13, 0, -6), -PI / 2, 5.2, 4.2], [Vector3(13, 0, 7), -PI / 2, 5.2, 4.2],
	[Vector3(-5, 0, 16), PI, 5.2, 4.2], [Vector3(6, 0, 16), PI, 5.2, 4.2],
	[Vector3(9.4, 0, 0.5), -PI / 2, 5.2, 3.6], [Vector3(-12, 0, 0.5), PI / 2, 4.4, 3.8],
	[Vector3(-10.5, 0, 13), 0.0, 4.6, 4.6],
]


## Retângulo no chão (x, z) de uma pegada girada em múltiplos de 90°.
func _rect(c: Vector3, yaw: float, w: float, d: float) -> Rect2:
	var quarter := absf(roundf(yaw / (PI / 2))) as int % 2 == 1
	var sx := d if quarter else w
	var sz := w if quarter else d
	return Rect2(c.x - sx / 2.0, c.z - sz / 2.0, sx, sz)


func _houses() -> Array:
	var out: Array = []
	for h in VillageLayout.HOUSES:
		var size: Vector3 = VillageLayout.HOUSE_SIZE[h[2]]
		out.append([_rect(h[0], h[1], size.x, size.z), "%s em %s" % [h[2], str(h[0])]])
	return out


func test_houses_do_not_overlap() -> void:
	var hs := _houses()
	for h in OLD:
		hs.append([_rect(h[0], h[1], h[2], h[3]), "casa antiga em %s" % str(h[0])])
	for i in hs.size():
		for j in range(i + 1, hs.size()):
			var a: Rect2 = hs[i][0]
			var b: Rect2 = hs[j][0]
			T.ok(not a.grow(-0.05).intersects(b.grow(-0.05)), "%s não encosta em %s" % [hs[i][1], hs[j][1]])


func test_houses_inside_fence() -> void:
	var fence: Rect2 = VillageLayout.BOUNDS
	for h in _houses():
		T.ok(fence.encloses(h[0]), "%s dentro da cerca" % h[1])


func test_houses_off_the_streets() -> void:
	for h in _houses():
		for st in VillageLayout.STREETS:
			var c: Vector3 = st[0]
			var sz: Vector2 = st[1]
			var road := Rect2(c.x - sz.x / 2.0, c.z - sz.y / 2.0, sz.x, sz.y)
			var inter: Rect2 = (h[0] as Rect2).intersection(road)
			T.ok(inter.get_area() < 0.6, "%s fora da rua em %s (%.2f m²)" % [h[1], str(c), inter.get_area()])


func test_event_spots() -> void:
	T.eq(VillageLayout.GIFTS.size(), 8, "8 presentes, como a missão pede")
	T.eq(VillageLayout.DELIVERY.size(), 6, "6 casas de entrega, como a missão pede")
	for i in VillageLayout.DELIVERY:
		T.ok(i >= 0 and i < VillageLayout.HOUSES.size(), "casa de entrega %d existe" % i)
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
