extends SceneTree
## Gera o ícone da barra de ações do Martelo de Energia (assets/ui/skills/sword_hammer.png, 256 px) a partir da
## sprite sheet da habilidade: o quadro 24 (martelo saindo do círculo), ampliado, com o martelo puxado para o azul
## elétrico e o círculo dourado, como no jogo.
##   godot --headless --path . --script res://tools/hammer_icon.gd
const SHEET := "res://assets/vfx/hammer/hammer_sheet.webp"
const FRAME := 24
const OUT := "res://assets/ui/skills/sword_hammer.png"


func _init() -> void:
	var src := Image.load_from_file(ProjectSettings.globalize_path(SHEET))
	src.convert(Image.FORMAT_RGBA8)
	var cell := src.get_width() / 8
	var frame := src.get_region(Rect2i((FRAME % 8) * cell, (FRAME / 8) * cell, cell, cell))
	frame.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	for y in 256:
		for x in 256:
			var c := frame.get_pixel(x, y)
			var lum := maxf(c.r, maxf(c.g, c.b))
			# de cima até o círculo (~62% da altura) é o martelo: azul elétrico com o miolo branco
			var hammer := 1.0 - smoothstep(0.55, 0.68, y / 256.0)
			var blue := Color(0.08, 0.32, 1.0).lerp(Color(0.85, 0.95, 1.0), smoothstep(0.55, 1.0, lum)) * (lum * 1.3)
			var out := c.lerp(blue, hammer * 0.85)
			out.a = 1.0
			frame.set_pixel(x, y, out)
	frame.save_png(ProjectSettings.globalize_path(OUT))
	print("ICON ", OUT)
	quit()
