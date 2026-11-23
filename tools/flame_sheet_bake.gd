extends SceneTree
## Canalização de Fogo (mago, tecla 1): mede as duas sprite sheets (8 x 8 quadros de 128 px, fundo preto) e grava as
## versões limpas que o jogo usa.
##  - assets/vfx/flame_channel/flame_circle_sheet.webp: o círculo mágico de fogo (aparece, gira, vira um anel de chamas,
##    apaga). Linhas da grade claras entre os quadros.
##  - assets/vfx/flame_channel/flame_jet_sheet.webp: a labareda vista de lado (nasce à esquerda e corre para a direita),
##    com quadros vazios no meio. Linhas da grade cinza-escuras.
## Imprime, por quadro, o brilho médio, o retângulo do que acende e o centro (para escolher os trechos de cada fase em
## FlameChannelVFX) e grava *_clean.png: as linhas da grade (e `MARGIN` px de cada borda do quadro) zeradas, para a soma
## aditiva não desenhar a grade; a borda do quadro esmaece em FEATHER px (a chama cortada no quadro não termina reta).
##   godot --headless --path . --script res://tools/flame_sheet_bake.gd
const CELLS := 8
const MARGIN := 3     ## px de cada borda do quadro zerados (as linhas da grade têm ~2 px)
const FEATHER := 10   ## px depois da margem em que o quadro esmaece até o valor cheio

const SHEETS := {
	"res://assets/vfx/flame_channel/flame_circle_sheet.webp": "res://assets/vfx/flame_channel/flame_circle_clean.png",
	"res://assets/vfx/flame_channel/flame_jet_sheet.webp": "res://assets/vfx/flame_channel/flame_jet_clean.png",
}


func _init() -> void:
	for src in SHEETS:
		_measure(src)
		_clean(src, SHEETS[src])
	_icon("res://assets/vfx/flame_channel/flame_circle_clean.png", "res://assets/vfx/flame_channel/flame_jet_clean.png",
		"res://assets/ui/skills/staff_flame.png")
	quit()


## Ícone da barra (256 px): a labareda (quadro 24 da sheet B) saindo do círculo girando (quadro 40 da sheet A), somados
## como no jogo (aditivo).
func _icon(circle: String, jet: String, dst: String) -> void:
	var out := Image.create(256, 256, false, Image.FORMAT_RGB8)
	out.fill(Color.BLACK)
	var layers := [[jet, 24, Rect2i(40, 8, 236, 236)], [circle, 40, Rect2i(-6, 54, 150, 150)]]
	for l in layers:
		var src := Image.load_from_file(ProjectSettings.globalize_path(l[0]))
		src.convert(Image.FORMAT_RGB8)
		var cell := src.get_width() / CELLS
		var f: int = l[1]
		var img := src.get_region(Rect2i((f % CELLS) * cell, (f / CELLS) * cell, cell, cell))
		var r: Rect2i = l[2]
		img.resize(r.size.x, r.size.y, Image.INTERPOLATE_LANCZOS)
		for y in r.size.y:
			for x in r.size.x:
				var px := r.position + Vector2i(x, y)
				if px.x < 0 or px.y < 0 or px.x >= 256 or px.y >= 256:
					continue
				var a := out.get_pixelv(px)
				var b := img.get_pixel(x, y)
				out.set_pixelv(px, Color(minf(a.r + b.r, 1.0), minf(a.g + b.g, 1.0), minf(a.b + b.b, 1.0)))
	out.save_png(ProjectSettings.globalize_path(dst))
	print("ícone ", dst)


func _lum(c: Color) -> float:
	return maxf(c.r, maxf(c.g, c.b))


func _measure(path: String) -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	img.convert(Image.FORMAT_RGBA8)
	var cw := img.get_width() / CELLS
	var ch := img.get_height() / CELLS
	print("== %s: %dx%d, quadro %dx%d" % [path.get_file(), img.get_width(), img.get_height(), cw, ch])
	# perfil das colunas perto da primeira divisa (onde fica a linha da grade)
	var prof := ""
	for x in range(cw - 4, cw + 4):
		var s := 0.0
		for y in img.get_height():
			s += _lum(img.get_pixel(x, y))
		prof += " x%d=%.2f" % [x, s / img.get_height()]
	print("grade:" + prof)
	for f in CELLS * CELLS:
		var x0 := (f % CELLS) * cw
		var y0 := (f / CELLS) * ch
		var mn := Vector2i(cw, ch)
		var mx := Vector2i(-1, -1)
		var sum := 0.0
		var bright := 0
		var cx := 0.0
		var cy := 0.0
		for y in range(MARGIN, ch - MARGIN):
			for x in range(MARGIN, cw - MARGIN):
				var l := _lum(img.get_pixel(x0 + x, y0 + y))
				sum += l
				if l > 0.3:
					bright += 1
					cx += x
					cy += y
					mn = Vector2i(mini(mn.x, x), mini(mn.y, y))
					mx = Vector2i(maxi(mx.x, x), maxi(mx.y, y))
		var line := "f%02d media=%.3f acesos=%d" % [f, sum / (cw * ch), bright]
		if bright > 0:
			line += " box=(%d,%d)-(%d,%d) massa=(%.2f,%.2f)" % [mn.x, mn.y, mx.x, mx.y, cx / bright / cw, cy / bright / ch]
		print(line)


func _clean(src: String, dst: String) -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(src))
	img.convert(Image.FORMAT_RGB8)
	var cw := img.get_width() / CELLS
	var ch := img.get_height() / CELLS
	for y in img.get_height():
		var ly := y % ch
		var ey := mini(ly, ch - 1 - ly)
		for x in img.get_width():
			var lx := x % cw
			var e := mini(mini(lx, cw - 1 - lx), ey)
			if e >= MARGIN + FEATHER:
				continue
			var k := clampf(float(e - MARGIN) / FEATHER, 0.0, 1.0)
			k = k * k * (3.0 - 2.0 * k)
			img.set_pixel(x, y, img.get_pixel(x, y) * k)
	img.save_png(ProjectSettings.globalize_path(dst))
	print("gravado ", dst)
