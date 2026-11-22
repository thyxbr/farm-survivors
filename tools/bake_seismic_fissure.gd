extends SceneTree
## Gera as texturas do Decal das fissuras das Estacas Sísmicas a partir de um quadro da sheet de rachaduras:
##   godot --headless --path . -s tools/bake_seismic_fissure.gd
## Saídas (assets/vfx/seismic_spikes/):
##   seismic_fissure_albedo.png    terra escura só nas fissuras e no miolo da cratera (alfa = quão escuro é o pixel em
##                                 relação ao chão em volta); o chão cinza do desenho fica transparente: o Decal escurece
##                                 o terreno de verdade só onde ele racha.
##   seismic_fissure_emission.png  só as brasas laranja dentro das fissuras (o resto preto).
## A borda some num círculo (o Decal é quadrado; a área é redonda).

const SHEET := "res://assets/vfx/seismic_spikes/seismic_cracks_sheet.webp"
const FRAME := 24          ## chão inteiro rachado, cratera no meio, ainda sem poeira (quadros 20-27)
const SIZE := 512
const OUT := "res://assets/vfx/seismic_spikes/seismic_fissure_%s.png"


func _init() -> void:
	var src := Image.load_from_file(ProjectSettings.globalize_path(SHEET))
	var cell := src.get_region(Rect2i((FRAME % 8) * 128, (FRAME / 8) * 128, 128, 128))
	cell.convert(Image.FORMAT_RGBA8)
	cell.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	var albedo := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var emission := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	# nível do chão em volta: média do brilho (o chão cinza domina o quadro)
	var avg := 0.0
	for y in range(0, SIZE, 4):
		for x in range(0, SIZE, 4):
			avg += cell.get_pixel(x, y).get_luminance()
	avg /= float((SIZE / 4) * (SIZE / 4))
	for y in SIZE:
		for x in SIZE:
			var c := cell.get_pixel(x, y)
			var lum := c.get_luminance()
			var r := Vector2(x - SIZE * 0.5, y - SIZE * 0.5).length() / (SIZE * 0.5)
			var edge := 1.0 - smoothstep(0.78, 0.98, r)
			var dark := clampf((avg * 0.8 - lum) / (avg * 0.6), 0.0, 1.0)
			albedo.set_pixel(x, y, Color(0.07, 0.055, 0.045, dark * edge))
			var sat := c.s
			var ember := smoothstep(0.35, 0.65, sat) * smoothstep(0.08, 0.3, c.r - c.b)
			emission.set_pixel(x, y, Color(c.r * ember, c.g * ember, c.b * ember, 1.0) * edge)
	albedo.save_png(ProjectSettings.globalize_path(OUT % "albedo"))
	emission.save_png(ProjectSettings.globalize_path(OUT % "emission"))
	print("fissuras: chão médio %.3f -> %s" % [avg, OUT % "*"])
	quit()
