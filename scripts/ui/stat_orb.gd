class_name StatOrb
extends Control
## Globo de vida/mana: líquido com ondinha, camada "fantasma" que desce atrasada mostrando o dano
## recebido e aro dourado. Pisca em vermelho quando a vida está baixa.

var color := Color(0.75, 0.1, 0.1)
var value := 1.0
var max_value := 1.0
var low_warning := false
var _ghost := 1.0
var _ghost_hold := 0.0
var _shown := 1.0
var _t := 0.0


func _init(diameter := 116.0) -> void:
	custom_minimum_size = Vector2(diameter, diameter)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_values(v: float, m: float) -> void:
	var r := clampf(v / maxf(m, 1.0), 0.0, 1.0)
	if r < _shown - 0.001:
		_ghost_hold = 0.5
	value = v
	max_value = m


func _process(delta: float) -> void:
	_t += delta
	var r := clampf(value / maxf(max_value, 1.0), 0.0, 1.0)
	_shown = move_toward(_shown, r, delta * 2.5) if r > _shown else r
	_ghost_hold -= delta
	if _ghost < _shown:
		_ghost = _shown
	elif _ghost_hold <= 0.0:
		_ghost = move_toward(_ghost, _shown, delta * 0.6)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var R := minf(size.x, size.y) * 0.5 - 5.0
	draw_circle(c, R + 5.0, Color(0.02, 0.02, 0.02, 0.9))
	draw_circle(c, R, Color(0.06, 0.04, 0.04))
	_liquid(c, R, _ghost, Color(1.0, 0.85, 0.55, 0.55), 0.0)
	_liquid(c, R, _shown, color, 2.0)
	# reflexo de vidro
	var hl := PackedVector2Array()
	for i in 13:
		var a := lerpf(PI * 1.1, PI * 1.75, i / 12.0)
		hl.append(c + Vector2(cos(a), sin(a)) * R * 0.82)
	for i in 13:
		var a := lerpf(PI * 1.75, PI * 1.1, i / 12.0)
		hl.append(c + Vector2(cos(a), sin(a)) * R * 0.62 + Vector2(R * 0.06, R * 0.08))
	draw_colored_polygon(hl, Color(1, 1, 1, 0.12))
	# aro
	var rim := UITheme.GOLD
	if low_warning and value / maxf(max_value, 1.0) < 0.25:
		rim = UITheme.GOLD.lerp(Color(1, 0.15, 0.1), 0.5 + 0.5 * sin(_t * 8.0))
	draw_arc(c, R + 2.0, 0, TAU, 48, Color(0, 0, 0, 0.9), 5.0, true)
	draw_arc(c, R + 2.0, 0, TAU, 48, rim.darkened(0.15), 2.5, true)
	draw_arc(c, R + 4.5, PI * 1.15, PI * 1.85, 16, rim.lightened(0.2), 1.5, true)
	# texto
	var font := ThemeDB.fallback_font
	var txt := "%d / %d" % [int(ceil(value)), int(max_value)]
	var p := Vector2(0, c.y + 6)
	draw_string_outline(font, p, txt, HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, 5, Color(0, 0, 0, 0.95))
	draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, Color(1, 1, 1))


## Segmento do círculo abaixo do nível do líquido, com ondinha na superfície.
func _liquid(c: Vector2, R: float, ratio: float, col: Color, wave: float) -> void:
	if ratio <= 0.001:
		return
	var pts := PackedVector2Array()
	if ratio >= 0.999:
		for i in 48:
			var a := TAU * i / 48.0
			pts.append(c + Vector2(cos(a), sin(a)) * R)
		draw_colored_polygon(pts, col)
		return
	var k := 1.0 - 2.0 * ratio            # nível em fração do raio (y para baixo)
	var a1 := asin(clampf(k, -1.0, 1.0))
	var n := 28
	for i in n + 1:
		var a := lerpf(a1, PI - a1, float(i) / n)
		pts.append(c + Vector2(cos(a), sin(a)) * R)
	# superfície: do lado esquerdo de volta ao direito, com onda
	var left := pts[pts.size() - 1]
	var right := pts[0]
	var m := 10
	wave *= clampf(ratio * 5.0, 0.0, 1.0) * clampf((1.0 - ratio) * 5.0, 0.0, 1.0)   # sem onda nas pontas
	for i in range(1, m):
		var x := lerpf(left.x, right.x, float(i) / m)
		var y := left.y + sin(_t * 3.0 + x * 0.12) * wave
		pts.append(Vector2(x, y))
	draw_colored_polygon(pts, col)
	# faixa mais clara na superfície
	if wave > 0.0:
		draw_line(Vector2(left.x + 2, left.y), Vector2(right.x - 2, right.y), col.lightened(0.35), 1.5, true)
