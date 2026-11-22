extends SceneTree
## Grito do Bastião: prepara a sprite sheet dos escudos azuis (8 x 8 quadros de 128 px, fundo preto puro) e o ícone
## da barra de ações.
##   godot --headless --path . --script res://tools/party_shield_sheet_bake.gd
##
## A arte de origem (assets/vfx/party_shield/party_shield_sheet_source.webp) tem as colunas na grade, mas as linhas
## 1 e 2 (formação) estão deslocadas para cima e vazam para a linha de baixo; a linha 5 tem só o topo da 6. Aqui cada
## linha é recortada em volta da faixa onde a arte está de verdade (BAND_CENTER, medido pelo perfil de brilho) e
## colada centrada na célula dela, com as bordas de cima e de baixo apagadas (nada vaza para o quadro vizinho). O
## número de cada quadro continua o mesmo da arte (PartyShieldRules.FORM_*, ORBIT_*, FADE_*):
##   1..18  formação (faísca, escudos subindo, anel se fechando)
##   24..39 órbita (anel com os escudos girando, em laço)
##   48..58 dissipação (o anel vira partículas pequenas)
## Os quadros vazios (0, 19..23, 40..47, 59..63) ficam pretos. O ícone (assets/ui/skills/sword_rally.png) é o quadro
## 26, ampliado e com um pouco mais de contraste.
const SRC := "res://assets/vfx/party_shield/party_shield_sheet_source.webp"
const OUT := "res://assets/vfx/party_shield/party_shield_sheet.png"
const ICON := "res://assets/ui/skills/sword_rally.png"
const ICON_FRAME := 26
const CELL := 128
## Centro vertical (px na imagem de origem) da arte de cada linha; -1 = linha sem quadros (fica preta).
const BAND_CENTER := [74, 174, 272, 446, 578, -1, 826, 958]
## Quadros com arte (os outros ficam pretos).
const USED := [[1, 18], [24, 39], [48, 58]]
## Altura (px) da faixa apagada em cima e embaixo de cada quadro.
const FEATHER := 10


func _init() -> void:
	var src := Image.load_from_file(ProjectSettings.globalize_path(SRC))
	src.convert(Image.FORMAT_RGBA8)
	var out := Image.create(CELL * 8, CELL * 8, false, Image.FORMAT_RGBA8)
	out.fill(Color.BLACK)
	for f in 64:
		if not _used(f):
			continue
		var row := f / 8
		var col := f % 8
		var top: int = int(BAND_CENTER[row]) - CELL / 2
		for y in CELL:
			var sy := top + y
			if sy < 0 or sy >= src.get_height():
				continue
			var fade := smoothstep(0.0, float(FEATHER), float(y)) * smoothstep(0.0, float(FEATHER), float(CELL - 1 - y))
			for x in CELL:
				var c := src.get_pixel(col * CELL + x, sy)
				var o := Color(c.r * fade, c.g * fade, c.b * fade, 1.0)
				out.set_pixel(col * CELL + x, row * CELL + y, o)
	out.save_png(ProjectSettings.globalize_path(OUT))
	print("SHEET ", OUT)
	var pad := 6
	var icon := out.get_region(Rect2i((ICON_FRAME % 8) * CELL + pad, (ICON_FRAME / 8) * CELL + pad, CELL - pad * 2, CELL - pad * 2))
	icon.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	for y in 256:
		for x in 256:
			var c := icon.get_pixel(x, y)
			var lum := maxf(c.r, maxf(c.g, c.b))
			var o := c * (1.0 + 0.45 * smoothstep(0.35, 1.0, lum))
			o.a = 1.0
			icon.set_pixel(x, y, o)
	icon.save_png(ProjectSettings.globalize_path(ICON))
	print("ICON ", ICON)
	quit()


func _used(f: int) -> bool:
	for r in USED:
		if f >= r[0] and f <= r[1]:
			return true
	return false
