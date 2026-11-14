class_name FuryRing
extends Control
## Anel de fúria em volta do slot da ultimate: arco de 0 a 360° proporcional à fúria;
## quando cheio, pulsa e brilha. Fica por cima do slot, sem pegar o mouse.

const COR := Color(1.0, 0.42, 0.12)
const COR_CHEIO := Color(1.0, 0.7, 0.25)

var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 3.0
	var frac := clampf(Game.fury / Game.FURY_MAX, 0.0, 1.0)
	# trilho escuro
	draw_arc(c, r, 0.0, TAU, 48, Color(0, 0, 0, 0.55), 4.0, true)
	if frac <= 0.0:
		return
	var full := Game.fury_full()
	var col := COR
	var width := 3.0
	if full:
		var p := 0.5 + 0.5 * sin(_t * 7.0)
		col = COR.lerp(COR_CHEIO, p)
		width = 3.0 + p * 1.5
		# brilho: halos largos e transparentes por trás do anel
		draw_arc(c, r, 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.18 + 0.18 * p), width + 6.0, true)
		draw_arc(c, r, 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.3 + 0.2 * p), width + 3.0, true)
	draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * frac, maxi(8, int(48 * frac)), col, width, true)
