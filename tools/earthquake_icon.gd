extends SceneTree
## Gera o ícone da barra de ações do Terremoto Devastador (assets/ui/skills/sword_earthquake.png, 256 px) a partir
## da sprite sheet da habilidade: o quadro 26 (anel de energia aceso no chão rachado, placas subindo), ampliado e
## um pouco puxado para cima no recorte (o anel fica no meio do ícone).
##   godot --headless --path . --script res://tools/earthquake_icon.gd
const SHEET := "res://assets/vfx/earthquake/earthquake_sheet.webp"
const FRAME := 26
const OUT := "res://assets/ui/skills/sword_earthquake.png"


func _init() -> void:
	var src := Image.load_from_file(ProjectSettings.globalize_path(SHEET))
	src.convert(Image.FORMAT_RGBA8)
	var cell := src.get_width() / 8
	var pad := int(cell * 0.06)
	var frame := src.get_region(Rect2i((FRAME % 8) * cell + pad, (FRAME / 8) * cell + pad, cell - pad * 2, cell - pad * 2))
	frame.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	for y in 256:
		for x in 256:
			var c := frame.get_pixel(x, y)
			# um pouco mais de contraste e o miolo mais claro (lê melhor pequeno na barra)
			var lum := maxf(c.r, maxf(c.g, c.b))
			var out := c * (1.0 + 0.35 * smoothstep(0.5, 1.0, lum))
			out.a = 1.0
			frame.set_pixel(x, y, out)
	frame.save_png(ProjectSettings.globalize_path(OUT))
	print("ICON ", OUT)
	quit()
