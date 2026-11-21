extends SceneTree
## Círculo da Provocação Sombria: prepara as duas sprite sheets (8 x 8 quadros de 128 px cada).
##  1. assets/vfx/dark_taunt/dark_taunt_sheet.webp (círculo, mãos, fumaça; fundo preto): só mede. Imprime, por
##     quadro, o retângulo do que acende (para achar a elipse do círculo desenhado em perspectiva e o quanto
##     esticar no chão: DarkTauntSheet.CIRCLE_ASPECT) e o brilho médio (quais quadros estão vazios).
##  2. assets/vfx/dark_taunt/taunt_eyes_source.webp (olhos vermelhos sobre um fundo cinza que escurece quadro a
##     quadro, com as linhas da grade): o fundo não é preto, então não dá para somar. Gera taunt_eyes.png com
##     alfa de verdade: por quadro, a cor de fundo é a mediana da borda; o alfa é o quanto o pixel escureceu em
##     relação ao fundo (o contorno escuro dos olhos) e a cor é o que sobra de luz por cima (o brilho vermelho),
##     pré-multiplicada (o shader usa blend_premul_alpha). As linhas da grade e a borda viram transparente.
##  3. assets/ui/skills/sword_taunt.png (ícone da barra, 256 px): o quadro 30 da sheet (mãos erguidas sobre o
##     círculo) com o par de olhos do quadro 22 por cima, no alto.
##   godot --headless --path . --script res://tools/taunt_sheet_bake.gd
const CELLS := 8
const MARGIN := 6   # px da borda de cada quadro ignorados (linhas da grade)


func _init() -> void:
	_measure("res://assets/vfx/dark_taunt/dark_taunt_sheet.webp")
	_bake_eyes("res://assets/vfx/dark_taunt/taunt_eyes_source.webp", "res://assets/vfx/dark_taunt/taunt_eyes.png")
	_icon("res://assets/vfx/dark_taunt/dark_taunt_sheet.webp", "res://assets/vfx/dark_taunt/taunt_eyes.png", "res://assets/ui/skills/sword_taunt.png")
	quit()


func _measure(path: String) -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	img.convert(Image.FORMAT_RGBA8)
	var cw := img.get_width() / CELLS
	var ch := img.get_height() / CELLS
	print("sheet %dx%d, quadro %dx%d" % [img.get_width(), img.get_height(), cw, ch])
	for f in CELLS * CELLS:
		var x0 := (f % CELLS) * cw
		var y0 := (f / CELLS) * ch
		var mn := Vector2i(cw, ch)
		var mx := Vector2i(-1, -1)
		var sum := 0.0
		var bright := 0
		for y in ch:
			for x in cw:
				var c := img.get_pixel(x0 + x, y0 + y)
				var l := maxf(c.r, maxf(c.g, c.b))
				sum += l
				if l > 0.35:   # só o traço aceso (não a fumaça escura)
					bright += 1
					mn = Vector2i(mini(mn.x, x), mini(mn.y, y))
					mx = Vector2i(maxi(mx.x, x), maxi(mx.y, y))
		var line := "f%02d media=%.3f acesos=%d" % [f, sum / (cw * ch), bright]
		if bright > 0:
			var w := mx.x - mn.x + 1
			var h := mx.y - mn.y + 1
			line += " box=(%d,%d)-(%d,%d) %dx%d aspect=%.2f centro=(%.3f,%.3f)" % [mn.x, mn.y, mx.x, mx.y, w, h,
				float(h) / float(w), (mn.x + mx.x) * 0.5 / cw, (mn.y + mx.y) * 0.5 / ch]
		print(line)


func _bake_eyes(src: String, dst: String) -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(src))
	img.convert(Image.FORMAT_RGBA8)
	var cw := img.get_width() / CELLS
	var ch := img.get_height() / CELLS
	var out := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	for f in CELLS * CELLS:
		var x0 := (f % CELLS) * cw
		var y0 := (f / CELLS) * ch
		# fundo do quadro: mediana do anel logo dentro da margem (fora dos olhos)
		var ring: Array[Color] = []
		for i in range(MARGIN, cw - MARGIN):
			for j in [MARGIN, MARGIN + 3, ch - MARGIN - 1, ch - MARGIN - 4]:
				ring.append(img.get_pixel(x0 + i, y0 + j))
				ring.append(img.get_pixel(x0 + j, y0 + i))
		var bg := _median(ring)
		var bg_l := maxf(bg.g, bg.b)   # o fundo é cinza/azulado: g e b não sobem com o vermelho dos olhos
		var peak := 0.0
		for y in range(MARGIN, ch - MARGIN):
			for x in range(MARGIN, cw - MARGIN):
				var c := img.get_pixel(x0 + x, y0 + y)
				# escurecimento: o contorno preto dos olhos cobrindo o fundo
				var a := clampf((bg_l - maxf(c.g, c.b) - 0.025) / maxf(bg_l, 0.12), 0.0, 1.0)
				# luz que sobra por cima do fundo coberto (o brilho vermelho/laranja)
				var e := Color(maxf(c.r - bg.r * (1.0 - a), 0.0), maxf(c.g - bg.g * (1.0 - a), 0.0), maxf(c.b - bg.b * (1.0 - a), 0.0))
				# sem matiz vermelho o resto é ruído do fundo
				var red := clampf((c.r - maxf(c.g, c.b)) * 4.0, 0.0, 1.0)
				e = Color(e.r * red, e.g * red, e.b * red)
				# a luz também cobre: o alfa final é o maior dos dois (o vermelho intenso fica opaco)
				var cover := clampf(maxf(a, maxf(e.r, maxf(e.g, e.b)) * 1.4), 0.0, 1.0)
				# borda do quadro some de mansinho (nada de retângulo)
				var ex := minf(x - MARGIN, cw - MARGIN - 1 - x)
				var ey := minf(y - MARGIN, ch - MARGIN - 1 - y)
				var soft := clampf(minf(ex, ey) / 8.0, 0.0, 1.0)
				peak = maxf(peak, cover)
				out.set_pixel(x0 + x, y0 + y, Color(e.r * soft, e.g * soft, e.b * soft, cover * soft))
		print("olhos f%02d fundo=(%.2f,%.2f,%.2f) pico=%.2f" % [f, bg.r, bg.g, bg.b, peak])
	out.save_png(ProjectSettings.globalize_path(dst))
	print("gravado ", dst)


func _median(cs: Array[Color]) -> Color:
	var rs := cs.map(func(c: Color) -> float: return c.r)
	var gs := cs.map(func(c: Color) -> float: return c.g)
	var bs := cs.map(func(c: Color) -> float: return c.b)
	rs.sort()
	gs.sort()
	bs.sort()
	var m := cs.size() / 2
	return Color(rs[m], gs[m], bs[m])


func _icon(sheet: String, eyes: String, dst: String) -> void:
	var src := Image.load_from_file(ProjectSettings.globalize_path(sheet))
	src.convert(Image.FORMAT_RGBA8)
	var cell := src.get_width() / CELLS
	var f := 30
	var img := src.get_region(Rect2i((f % CELLS) * cell, (f / CELLS) * cell, cell, cell))
	img.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	var ey := Image.load_from_file(ProjectSettings.globalize_path(eyes))
	ey.convert(Image.FORMAT_RGBA8)
	var ec := ey.get_width() / CELLS
	var e := 22
	# só a faixa dos olhos, ampliada sobre a parte de cima do ícone
	var band := ey.get_region(Rect2i((e % CELLS) * ec + 10, (e / CELLS) * ec + 38, ec - 20, 52))
	band.resize(200, 96, Image.INTERPOLATE_LANCZOS)
	for y in band.get_height():
		for x in band.get_width():
			var c := band.get_pixel(x, y)   # pré-multiplicada: cor + fundo x (1 - alfa)
			var px := Vector2i(28 + x, 4 + y)
			var under := img.get_pixelv(px)
			var glow := Color(c.r * 1.8, c.g * 1.4, c.b * 1.4)
			img.set_pixelv(px, Color(minf(glow.r + under.r * (1.0 - c.a), 1.0), minf(glow.g + under.g * (1.0 - c.a), 1.0),
				minf(glow.b + under.b * (1.0 - c.a), 1.0), 1.0))
	img.save_png(ProjectSettings.globalize_path(dst))
	print("ícone ", dst)
