extends SceneTree
## Gera o ícone da barra de ações da Lâmina Suprema (assets/ui/skills/sword_supreme.png, 256 px) a partir da sprite
## sheet da habilidade: o quadro 46 (a espada de energia cravada no chão), um pouco ampliado e mais brilhante.
##   godot --headless --path . --script res://tools/supreme_icon.gd
const SHEET := "res://assets/vfx/greatsword_supreme/supreme_sheet.webp"
const FRAME := 46
const ZOOM := 0.82   ## fração do quadro que entra no ícone (centrada um pouco abaixo do meio: o chão)
const OUT := "res://assets/ui/skills/sword_supreme.png"


func _init() -> void:
	var src := Image.load_from_file(ProjectSettings.globalize_path(SHEET))
	src.convert(Image.FORMAT_RGBA8)
	var cell := src.get_width() / 8
	var side := int(cell * ZOOM)
	var ox := (FRAME % 8) * cell + (cell - side) / 2
	var oy := (FRAME / 8) * cell + int((cell - side) * 0.7)
	var frame := src.get_region(Rect2i(ox, oy, side, side))
	frame.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	for y in 256:
		for x in 256:
			var c := frame.get_pixel(x, y)
			var out := Color(minf(c.r * 1.2, 1.0), minf(c.g * 1.15, 1.0), minf(c.b * 1.1, 1.0), 1.0)
			frame.set_pixel(x, y, out)
	frame.save_png(ProjectSettings.globalize_path(OUT))
	print("ICON ", OUT)
	quit()
