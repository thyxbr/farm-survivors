class_name HordeIcon
extends Control
## Ícone compacto do Desafio da Horda (arma automática, passiva, bênção ou combo), desenhado por código.
## Margem interna de ~20% (o desenho não encosta na borda); nível ou "×N" num selo fora do desenho; apagado quando inativo.

const UPG := preload("res://scripts/survival/upgrades.gd")

var kind := "weapon"     # weapon | passive | blessing | combo
var id := ""
var level := 0
var count := 0
var dim := false
var glow := false
var _t := 0.0


func _init(sz := 28.0, k := "weapon", i := "", lv := 0) -> void:
	custom_minimum_size = Vector2(sz, sz)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	kind = k
	id = i
	level = lv


## Preenche uma linha de armas (maiores) e outra de passivas + bênçãos (menores). Também usado pelo placar.
static func fill_build(wrow: HBoxContainer, xrow: HBoxContainer, w: Dictionary, p: Dictionary, b: Dictionary,
		big: float, small: float) -> void:
	for c in wrow.get_children():
		c.queue_free()
	if xrow != wrow:
		for c in xrow.get_children():
			c.queue_free()
	for id in UPG.WEAPONS:
		if w.has(id):
			wrow.add_child(HordeIcon.new(big, "weapon", id, int(w[id])))
	for id in UPG.PASSIVES:
		if p.has(id):
			xrow.add_child(HordeIcon.new(small, "passive", id, int(p[id])))
	for id in UPG.BLESSINGS:
		if b.has(id):
			var ic := HordeIcon.new(small, "blessing", id)
			ic.count = int(b[id])
			xrow.add_child(ic)


func setup(k: String, i: String, lv := 0, n := 0) -> void:
	if k == kind and i == id and lv == level and n == count:
		return
	kind = k
	id = i
	level = lv
	count = n
	queue_redraw()


func _process(delta: float) -> void:
	if glow:
		_t += delta
		queue_redraw()


func color() -> Color:
	match kind:
		"weapon":
			return UPG.WEAPONS.get(id, {}).get("color", Color.WHITE)
		"passive":
			return UPG.PASSIVES.get(id, {}).get("color", Color.WHITE)
		"blessing":
			return UPG.BLESSINGS.get(id, {}).get("color", Color.WHITE)
		"combo":
			return UPG.COMBOS.get(id, {}).get("color", Color.WHITE)
	return Color.WHITE


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var c := color()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.045, 0.045, 0.82)
	sb.set_corner_radius_all(int(size.x * 0.22))
	sb.border_color = c.darkened(0.35) if not glow else c.lerp(Color.WHITE, 0.25 + 0.25 * sin(_t * 6.0))
	sb.set_border_width_all(2 if glow else 1)
	draw_style_box(sb, r)
	# margem interna (variante B dos protótipos): o desenho não encosta na borda
	var ir := r.grow(-size.x * (0.22 if kind == "weapon" else 0.2))
	_glyph(ir, c)
	if dim:
		draw_style_box(_shade(), r)
	# nível (dourado no máximo) ou "×N" num selo fora do desenho, no canto inferior direito
	if level > 0 and (kind == "weapon" or kind == "passive"):
		badge(self, str(level), Vector2(size.x + 6, size.y + 6), c.darkened(0.35),
			Color(1, 0.85, 0.35) if level >= UPG.MAX_LEVEL else Color(1, 1, 1))
	elif count > 1:
		badge(self, "×%d" % count, Vector2(size.x + 6, size.y + 6), c.darkened(0.35), Color(1, 1, 1))


## Selo arredondado com texto curto; anchor = canto inferior direito do selo. Também usado na barra de ações.
static func badge(ci: CanvasItem, text: String, anchor: Vector2, border: Color, col: Color, fs := 10, h := 15.0,
		center := false) -> void:
	var font := ThemeDB.fallback_font
	var w := maxf(h, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 8.0)
	var pos := Vector2(anchor.x - (w * 0.5 if center else w), anchor.y - h)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.086, 0.07, 0.06, 0.96)
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(h * 0.5))
	ci.draw_style_box(sb, Rect2(pos, Vector2(w, h)))
	ci.draw_string(font, Vector2(pos.x, pos.y + h * 0.5 + fs * 0.36), text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, col)


func _shade() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0.6)
	s.set_corner_radius_all(int(size.x * 0.22))
	return s


## Desenho do símbolo dentro de r (coordenadas 0..1 mapeadas para r).
func _glyph(r: Rect2, c: Color) -> void:
	var P := func(x: float, y: float) -> Vector2: return r.position + Vector2(x, y) * r.size
	var S := r.size.x
	var ol := Color(0.03, 0.03, 0.03, 0.9)
	var lw := maxf(1.0, S * 0.06)
	match kind:
		"combo":
			var a: String = UPG.COMBOS[id].a
			var b: String = UPG.COMBOS[id].b
			var ca: Color = UPG.WEAPONS[a].color
			var cb: Color = UPG.WEAPONS[b].color
			draw_circle(P.call(0.36, 0.5), S * 0.3 + lw, ol)
			draw_circle(P.call(0.64, 0.5), S * 0.3 + lw, ol)
			draw_circle(P.call(0.36, 0.5), S * 0.3, ca)
			draw_circle(P.call(0.64, 0.5), S * 0.3, Color(cb.r, cb.g, cb.b, 0.85))
			draw_circle(P.call(0.5, 0.5), S * 0.11, Color(1, 1, 1, 0.95))
			return
		"weapon":
			match id:
				"fogo":
					IconPainter.draw(self, "fireball", c, r.grow(S * 0.12))
				"aura":
					IconPainter.draw(self, "frost", c, r.grow(S * 0.12))
				"raio":
					_poly(P, [Vector2(0.58, 0.02), Vector2(0.18, 0.56), Vector2(0.46, 0.56), Vector2(0.36, 0.98),
						Vector2(0.84, 0.4), Vector2(0.54, 0.4), Vector2(0.7, 0.02)], Color(1.0, 0.92, 0.45), ol, lw)
				"laminas":
					draw_arc(P.call(0.5, 0.5), S * 0.42, 0, TAU, 32, Color(c.r, c.g, c.b, 0.5), lw, true)
					for ang in [PI * 0.25, PI * 0.75]:
						var d := Vector2(cos(ang), sin(ang))
						var n := Vector2(-d.y, d.x)
						var cen := Vector2(0.5, 0.5)
						_poly(P, [cen - d * 0.42, cen + n * 0.08, cen + d * 0.42, cen - n * 0.08], Color(0.85, 0.92, 1.0), ol, lw * 0.7)
			return
		"passive":
			match id:
				"poder":
					IconPainter.draw(self, "sword", c, r.grow(S * 0.12))
				"celeridade":
					_poly(P, [Vector2(0.2, 0.08), Vector2(0.8, 0.08), Vector2(0.56, 0.5), Vector2(0.8, 0.92),
						Vector2(0.2, 0.92), Vector2(0.44, 0.5)], c, ol, lw)
				"vigor":
					_heart(P, S, c, ol, lw)
				"botas":
					IconPainter.draw(self, "boot", c, r.grow(S * 0.12))
				"ima":
					draw_arc(P.call(0.5, 0.42), S * 0.3, 0, PI, 20, ol, S * 0.26, true)
					draw_arc(P.call(0.5, 0.42), S * 0.3, 0, PI, 20, c, S * 0.18, true)
					for x in [0.2, 0.8]:
						draw_rect(Rect2(P.call(x - 0.09, 0.12), Vector2(S * 0.18, S * 0.3)), Color(0.9, 0.9, 0.95))
				"alcance":
					for k in 3:
						draw_arc(P.call(0.5, 0.5), S * (0.14 + 0.14 * k), 0, TAU, 28, c.lightened(0.1 * k), lw, true)
				"armadura":
					IconPainter.draw(self, "shield", c, r.grow(S * 0.12))
				"regeneracao":
					IconPainter.draw(self, "heal", c, r.grow(S * 0.12))
			return
		"blessing":
			match id:
				"vida":
					_heart(P, S, c, ol, lw)
				"sangue":
					_poly(P, [Vector2(0.5, 0.05), Vector2(0.78, 0.55), Vector2(0.72, 0.8), Vector2(0.5, 0.94),
						Vector2(0.28, 0.8), Vector2(0.22, 0.55)], c, ol, lw)
				"ouro":
					draw_circle(P.call(0.5, 0.5), S * 0.4 + lw, ol)
					draw_circle(P.call(0.5, 0.5), S * 0.4, c)
					draw_circle(P.call(0.5, 0.5), S * 0.24, c.darkened(0.25))
				"sorte":
					for v in [Vector2(0.5, 0.3), Vector2(0.3, 0.6), Vector2(0.7, 0.6)]:
						draw_circle(P.call(v.x, v.y), S * 0.2 + lw, ol)
					for v in [Vector2(0.5, 0.3), Vector2(0.3, 0.6), Vector2(0.7, 0.6)]:
						draw_circle(P.call(v.x, v.y), S * 0.2, c)
				"sabedoria":
					IconPainter.draw(self, "orb", c, r.grow(S * 0.12))
				"furia":
					IconPainter.draw(self, "fireball", c, r.grow(S * 0.12))
				_:
					var pts: Array = []
					for k in 8:
						var ang := TAU * k / 8.0 - PI / 2.0
						var rad := 0.46 if k % 2 == 0 else 0.18
						pts.append(Vector2(0.5, 0.5) + Vector2(cos(ang), sin(ang)) * rad)
					_poly(P, pts, c, ol, lw)


func _heart(P: Callable, S: float, c: Color, ol: Color, lw: float) -> void:
	for x in [0.32, 0.68]:
		draw_circle(P.call(x, 0.36), S * 0.22 + lw, ol)
	_poly(P, [Vector2(0.1, 0.45), Vector2(0.9, 0.45), Vector2(0.5, 0.92)], c, ol, lw)
	for x in [0.32, 0.68]:
		draw_circle(P.call(x, 0.36), S * 0.22, c)
	draw_rect(Rect2(P.call(0.3, 0.38), Vector2(S * 0.4, S * 0.16)), c)


func _poly(P: Callable, pts: Array, fill: Color, ol: Color, lw: float) -> void:
	var arr := PackedVector2Array()
	for p in pts:
		arr.append(P.call(p.x, p.y))
	draw_colored_polygon(arr, fill)
	arr.append(arr[0])
	draw_polyline(arr, ol, lw, true)
