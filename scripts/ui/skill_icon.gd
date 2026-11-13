class_name SkillIcon
extends Control
## Ícone de uma habilidade do Desafio da Horda (arma automática, passiva ou bênção): quadro na cor
## da habilidade, desenho vetorial no meio e pontinhos de nível embaixo (1..MAX_LEVEL).
## Usado na HUD da horda e nas cartas de escolha.

const UPG := preload("res://scripts/survival/upgrades.gd")

## Desenho de cada habilidade (tipos do IconPainter; "bolt" e "clock" são desenhados aqui).
const KINDS := {
	"fogo": "fireball", "laminas": "saber", "raio": "bolt", "aura": "frost",
	"poder": "greatsword", "celeridade": "clock", "vigor": "heart", "botas": "boot", "ima": "magnet",
	"alcance": "orb", "armadura": "shield", "regeneracao": "heal", "heal": "potion",
}

var type := "weapon"      # weapon | passive | blessing | heal
var id := ""
var level := 0            # 0 = nova (sem pontos acesos)
var show_pips := true
var highlight := false    # a carta mostra o próximo nível aceso em dourado


func _init(size_px := 52) -> void:
	custom_minimum_size = Vector2(size_px, size_px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(t: String, skill_id: String, lv: int) -> SkillIcon:
	type = t
	id = skill_id
	level = lv
	queue_redraw()
	return self


func color() -> Color:
	match type:
		"weapon":
			return UPG.WEAPONS[id].color if UPG.WEAPONS.has(id) else Color.WHITE
		"passive":
			return UPG.PASSIVES[id].color if UPG.PASSIVES.has(id) else Color.WHITE
		"blessing":
			return UPG.BLESSINGS[id].color if UPG.BLESSINGS.has(id) else UITheme.GOLD
	return Color(1, 0.4, 0.4)


func _draw() -> void:
	var c := color()
	var r := Rect2(Vector2.ZERO, size)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.05, 0.05, 0.92).lerp(c, 0.12)
	bg.border_color = c.darkened(0.15) if not highlight else Color(1, 0.88, 0.45)
	bg.set_border_width_all(2 if not highlight else 3)
	bg.set_corner_radius_all(int(size.x * 0.18))
	bg.shadow_color = Color(0, 0, 0, 0.45)
	bg.shadow_size = 4
	draw_style_box(bg, r)
	var pips_h := size.y * 0.16 if show_pips and type in ["weapon", "passive"] else 0.0
	var pad := size.x * 0.14
	var ir := Rect2(Vector2(pad, pad * 0.8), Vector2(size.x - pad * 2, size.y - pad * 1.6 - pips_h))
	var side := minf(ir.size.x, ir.size.y)
	ir = Rect2(ir.position + (ir.size - Vector2(side, side)) * 0.5, Vector2(side, side))
	var kind: String = KINDS.get(id, "amulet" if type == "blessing" else "orb")
	_glyph(kind, c, ir)
	if pips_h > 0.0:
		var n := UPG.MAX_LEVEL
		var pr := size.x * 0.055
		var gap := pr * 2.7
		var x0 := size.x * 0.5 - gap * (n - 1) * 0.5
		var y := size.y - pips_h * 0.75
		for i in n:
			var on := i < level
			var next := highlight and i == level
			var col := c.lightened(0.25) if on else (Color(1, 0.88, 0.45) if next else Color(0, 0, 0, 0.55))
			draw_circle(Vector2(x0 + gap * i, y), pr, col)
			if not on and not next:
				draw_arc(Vector2(x0 + gap * i, y), pr, 0, TAU, 12, c.darkened(0.4), 1.0, true)


func _glyph(kind: String, c: Color, r: Rect2) -> void:
	var P := func(x: float, y: float) -> Vector2: return r.position + Vector2(x, y) * r.size
	var S := r.size.x
	var ol := IconPainter.OUTLINE
	match kind:
		"bolt":
			var pts := PackedVector2Array([P.call(0.58, 0.04), P.call(0.22, 0.56), P.call(0.47, 0.56),
				P.call(0.36, 0.96), P.call(0.8, 0.4), P.call(0.54, 0.4), P.call(0.7, 0.04)])
			draw_colored_polygon(pts, Color(1, 0.92, 0.4).lerp(c, 0.25))
			pts.append(pts[0])
			draw_polyline(pts, ol, maxf(1.0, S * 0.04), true)
		"clock":
			draw_circle(P.call(0.5, 0.52), S * 0.4, ol)
			draw_circle(P.call(0.5, 0.52), S * 0.36, c.lightened(0.3))
			draw_line(P.call(0.5, 0.52), P.call(0.5, 0.27), ol, maxf(2.0, S * 0.07), true)
			draw_line(P.call(0.5, 0.52), P.call(0.68, 0.6), ol, maxf(2.0, S * 0.07), true)
			draw_line(P.call(0.38, 0.06), P.call(0.62, 0.06), ol, maxf(2.0, S * 0.08), true)
		"heart":
			var hp := PackedVector2Array()
			for i in 33:
				var t := TAU * i / 32.0
				var x := 16.0 * pow(sin(t), 3)
				var y := -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
				hp.append(P.call(0.5 + x / 38.0, 0.48 + y / 38.0))
			draw_colored_polygon(hp, Color(0.95, 0.25, 0.32))
			draw_polyline(hp, ol, maxf(1.0, S * 0.04), true)
		"magnet":
			var w := maxf(3.0, S * 0.17)
			draw_arc(P.call(0.5, 0.45), S * 0.27, 0.0, PI, 20, ol, w + 3.0, true)
			draw_arc(P.call(0.5, 0.45), S * 0.27, 0.0, PI, 20, Color(0.9, 0.2, 0.2), w, true)
			for x in [0.23, 0.77]:
				draw_line(P.call(x, 0.45), P.call(x, 0.12), ol, w + 3.0)
				draw_line(P.call(x, 0.45), P.call(x, 0.24), Color(0.9, 0.2, 0.2), w)
				draw_line(P.call(x, 0.24), P.call(x, 0.12), Color(0.85, 0.85, 0.9), w)
		_:
			IconPainter.draw(self, kind, c, r)
