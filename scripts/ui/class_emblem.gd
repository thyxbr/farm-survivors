class_name ClassEmblem
extends Control
## Emblema da classe: escudo com borda dourada e o símbolo da classe na cor dela, desenhado por código
## (vale em qualquer tamanho). Usado na tela de criação; `draw()` serve a quem desenha sem nó (placa de nome).
## Classe nova = um símbolo novo em `_symbol()` e o campo "emblem" em data/balance/classes.json.
## Sem autoloads: o executor de testes unitários (-s) carrega este script.

const KINDS := ["warrior", "archer", "mage", "healer"]
const GOLD := Color(0.86, 0.68, 0.32)   ## o mesmo de UITheme.GOLD
const FILL := Color(0.07, 0.05, 0.04)

## Símbolo desenhado ("" ou desconhecido = só o escudo).
var kind := "":
	set(v):
		kind = v
		queue_redraw()
var color := Color.WHITE:
	set(v):
		color = v
		queue_redraw()


## Emblema de uma linha da tabela "classes" (campos "emblem" e "color"), quadrado de `size` px.
static func for_class(row: Dictionary, size: float) -> ClassEmblem:
	var e := ClassEmblem.new()
	e.kind = str(row.get("emblem", ""))
	var c = row.get("color", Color.WHITE)
	e.color = c if c is Color else Color.WHITE
	e.custom_minimum_size = Vector2(size, size)
	e.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return e


func _draw() -> void:
	draw(self, kind, color, Rect2(Vector2.ZERO, size))


## Desenha o emblema dentro de `r` (centrado, quadrado do menor lado). As medidas vêm de uma caixa 64×64.
static func draw(ci: CanvasItem, kind: String, col: Color, r: Rect2) -> void:
	var s := minf(r.size.x, r.size.y) / 64.0
	var o := r.position + (r.size - Vector2(64, 64) * s) * 0.5
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	# escudo: topo com pontas, laterais retas até a metade e base em curva até a ponta
	var outer := _shield(P, 3.0, 56.0, 12.0, 32.0, 61.0, 46.0, 45.0, 56.0)
	ci.draw_colored_polygon(outer, FILL)
	ci.draw_polyline(outer + PackedVector2Array([outer[0]]), GOLD, maxf(1.0, 2.0 * s), true)
	var inner := _shield(P, 7.0, 52.0, 15.0, 32.0, 57.0, 44.0, 43.0, 52.5)
	ci.draw_polyline(inner + PackedVector2Array([inner[0]]), Color(col, 0.55), maxf(1.0, 1.2 * s), true)
	# símbolo a 68% do escudo, centrado um pouco abaixo do meio
	var S := func(x: float, y: float) -> Vector2: return P.call(32.0 + (x - 32.0) * 0.68, 33.0 + (y - 32.0) * 0.68)
	_symbol(ci, kind, col, S, s * 0.68)


## Contorno do escudo: (32, top) → (right, shoulder) → (right, mid) → curva até (32, tip) → espelhado.
static func _shield(P: Callable, top: float, right: float, shoulder: float, mid: float, tip: float,
		c1y: float, c2x: float, c2y: float) -> PackedVector2Array:
	var left := 64.0 - right
	var pts := PackedVector2Array([P.call(32.0, top), P.call(right, shoulder), P.call(right, mid)])
	for i in range(1, 9):   # direita: (right, mid) → (32, tip)
		pts.append(_bez(P.call(right, mid), P.call(right, c1y), P.call(c2x, c2y), P.call(32.0, tip), i / 8.0))
	for i in range(1, 9):   # esquerda, espelhada: (32, tip) → (left, mid)
		pts.append(_bez(P.call(32.0, tip), P.call(64.0 - c2x, c2y), P.call(left, c1y), P.call(left, mid), i / 8.0))
	pts.append(P.call(left, shoulder))
	return pts


static func _bez(a: Vector2, b: Vector2, c: Vector2, d: Vector2, t: float) -> Vector2:
	return a.bezier_interpolate(b, c, d, t)


static func _symbol(ci: CanvasItem, kind: String, col: Color, S: Callable, s: float) -> void:
	match kind:
		"warrior":   # espada vertical: lâmina, guarda, punho e pomo
			ci.draw_colored_polygon(PackedVector2Array([S.call(32, 12), S.call(35, 16), S.call(35, 40),
				S.call(29, 40), S.call(29, 16)]), col)
			ci.draw_colored_polygon(_rect(S, 22, 40, 20, 4), col)
			ci.draw_colored_polygon(_rect(S, 30, 44, 4, 8), col)
			ci.draw_circle(S.call(32, 54), 2.6 * s, col)
		"archer":   # arco com corda e flecha
			var arc := PackedVector2Array()
			for i in 13:
				var t := i / 12.0
				arc.append(S.call(24, 12).lerp(S.call(46, 32), t).lerp(S.call(46, 32).lerp(S.call(24, 52), t), t))
			ci.draw_polyline(arc, col, 3.2 * s, true)
			ci.draw_line(S.call(24, 12), S.call(24, 52), col, 1.4 * s, true)
			ci.draw_line(S.call(20, 32), S.call(46, 32), col, 2.6 * s, true)
			ci.draw_colored_polygon(PackedVector2Array([S.call(50, 32), S.call(43, 28), S.call(43, 36)]), col)
			ci.draw_line(S.call(20, 32), S.call(16, 29), col, 2.0 * s, true)
			ci.draw_line(S.call(20, 32), S.call(16, 35), col, 2.0 * s, true)
		"mage":   # cajado com estrela de 4 pontas
			ci.draw_line(S.call(22, 54), S.call(38, 22), col, 3.2 * s, true)
			ci.draw_colored_polygon(PackedVector2Array([S.call(42, 10), S.call(44.5, 17.5), S.call(52, 20),
				S.call(44.5, 22.5), S.call(42, 30), S.call(39.5, 22.5), S.call(32, 20), S.call(39.5, 17.5)]), col)
			ci.draw_circle(S.call(26, 20), 1.8 * s, col)
			ci.draw_circle(S.call(50, 34), 1.5 * s, col)
		"healer":   # sol: disco e oito raios
			ci.draw_circle(S.call(32, 32), 8.0 * s, col)
			for a in [[32, 12, 32, 19], [32, 45, 32, 52], [12, 32, 19, 32], [45, 32, 52, 32]]:
				ci.draw_line(S.call(a[0], a[1]), S.call(a[2], a[3]), col, 3.0 * s, true)
			for a in [[18, 18, 22, 22], [46, 18, 42, 22], [18, 46, 22, 42], [46, 46, 42, 42]]:
				ci.draw_line(S.call(a[0], a[1]), S.call(a[2], a[3]), col, 2.0 * s, true)


static func _rect(S: Callable, x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([S.call(x, y), S.call(x + w, y), S.call(x + w, y + h), S.call(x, y + h)])
