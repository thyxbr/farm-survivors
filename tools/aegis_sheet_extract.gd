extends SceneTree
## Recorta da sprite sheet da Égide (assets/vfx/aegis/aegis_sheet.webp, grade 8 x 8 de 128 px) as texturas das
## placas 3D, para elas terem a cara da sheet (o círculo do chão é redesenhado por vetor em aegis_rune_circle,
## nítido de perto; a textura de 128 px esticada no chão ficava borrada):
##   aegis_plate.png         o losango grande com o escudo (quadro 15), recortado rente às pontas.
##   aegis_plate_cracked.png o mesmo losango já rachado (quadro 42), mesmo recorte.
##   godot --headless --path . --script res://tools/aegis_sheet_extract.gd
## Imprime as caixas medidas (para conferir se a sheet mudar).

const SHEET := "res://assets/vfx/aegis/aegis_sheet.webp"
const OUT := "res://assets/vfx/aegis/"
const CELL := 128
const PLATE_FRAME := 15
const CRACKED_FRAME := 42
const LUM := 0.3


func _init() -> void:
	var sheet := Image.load_from_file(SHEET)
	sheet.convert(Image.FORMAT_RGBA8)
	var box := _plate_box(_cell(sheet, PLATE_FRAME))
	print("placa: ", box, " proporção alto/largo %.3f" % (float(box.size.y) / box.size.x))
	_save_plate(_cell(sheet, PLATE_FRAME), box, "aegis_plate.png")
	var cbox := _cracked_box(_cell(sheet, CRACKED_FRAME), box)
	print("placa rachada: ", cbox)
	_save_plate(_cell(sheet, CRACKED_FRAME), cbox, "aegis_plate_cracked.png")
	quit()


func _cell(sheet: Image, f: int) -> Image:
	return sheet.get_region(Rect2i((f % 8) * CELL, (f / 8) * CELL, CELL, CELL))


func _lum(c: Color) -> float:
	return maxf(c.r, maxf(c.g, c.b))


## Caixa dos pixels acesos de `img` dentro de `area`.
func _bbox(img: Image, area: Rect2i) -> Rect2i:
	var lo := Vector2i(9999, 9999)
	var hi := Vector2i(-1, -1)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if _lum(img.get_pixel(x, y)) > LUM:
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	if hi.x < 0:
		return Rect2i()
	return Rect2i(lo, hi - lo + Vector2i.ONE)


## Losango do meio do quadro das três placas: só a faixa central (as placas dos lados ficam de fora).
func _plate_box(cell: Image) -> Rect2i:
	return _bbox(cell, Rect2i(33, 0, 62, CELL))


## No quadro rachado os vizinhos encostam: acha as pontas de cima e de baixo na coluna do meio e usa a mesma
## proporção do losango inteiro para a largura.
func _cracked_box(cell: Image, ref: Rect2i) -> Rect2i:
	var cx := CELL / 2
	var top := -1
	var bottom := -1
	for y in CELL:
		for x in range(cx - 3, cx + 4):
			if _lum(cell.get_pixel(x, y)) > LUM * 2.0:
				if top < 0:
					top = y
				bottom = y
	var h := bottom - top + 1
	var w := int(round(h * float(ref.size.x) / ref.size.y))
	return Rect2i(cx - w / 2, top, w, h)


func _save_plate(cell: Image, box: Rect2i, file: String) -> void:
	var part := cell.get_region(box)
	part.resize(256, 384, Image.INTERPOLATE_LANCZOS)
	part.save_png(OUT + file)
