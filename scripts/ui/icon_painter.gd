class_name IconPainter
extends RefCounted
## Ícones vetoriais desenhados por código (sem texturas): armas, armaduras, poções, comida, magias...
## Coordenadas em espaço unitário (0..1, y para baixo) mapeadas para o retângulo de destino.

const OUTLINE := Color(0.05, 0.04, 0.035, 0.95)
const METAL := Color(0.78, 0.8, 0.85)
const WOOD := Color(0.5, 0.33, 0.17)
const GOLDC := Color(0.92, 0.72, 0.3)
const LEATHER := Color(0.42, 0.27, 0.13)


## Tipo de ícone para um item.
static func kind_for(id: String) -> String:
	var it := ItemDB.get_item(id)
	if it.is_empty():
		return ""
	match it.type:
		"weapon":
			match ItemDB.weapon_class(id):
				"staff":
					return "staff"
				"bow":
					return "bow"
			match it.get("shape", ""):
				"cleaver":
					return "cleaver"
				"great":
					return "greatsword"
				"saber":
					return "saber"
			return "sword"
		"armor":
			return "chest"
		"gear":
			match it.slot:
				"head":
					return "hat" if id == "wizard_hat" else ("hood" if id.ends_with("hood") or id == "leather_cap" else "helm")
				"hands":
					return "glove"
				"feet":
					return "boot"
				"offhand":
					return {"sword": "shield", "staff": "orb", "bow": "quiver"}.get(it.get("needs", ""), "shield")
				"amulet":
					return "amulet"
				"ring":
					return "ring"
		"consumable":
			return "potion"
		"food":
			return "bread" if id == "bread" else "bowl"
		"crop":
			return "wheat" if id == "wheat" else "crop"
		"seed":
			return "seed"
		"material":
			return {"slime_gel": "gel", "goblin_ear": "ear", "goblin_crown": "crown"}.get(id, "gel")
	return "gel"


## Cor principal do ícone de um item.
static func color_for(id: String) -> Color:
	var it := ItemDB.get_item(id)
	if it.has("color"):
		return it.color
	match it.get("type", ""):
		"consumable":
			return Color(0.9, 0.15, 0.18) if it.has("heal_hp") else Color(0.25, 0.4, 1.0)
		"seed":
			return ItemDB.CROPS[it.crop].color
		"crop":
			return ItemDB.CROPS[id].color if ItemDB.CROPS.has(id) else Color(0.6, 0.8, 0.3)
		"material":
			return {"slime_gel": Color(0.35, 0.9, 0.4), "goblin_ear": Color(0.45, 0.6, 0.25), "goblin_crown": GOLDC}.get(id, Color.GRAY)
	return Color(0.7, 0.7, 0.7)


## Ícone padrão de um espaço de equipamento vazio.
static func slot_kind(slot: String) -> String:
	return {"weapon": "sword", "offhand": "shield", "head": "helm", "armor": "chest", "hands": "glove",
		"feet": "boot", "amulet": "amulet", "ring": "ring"}.get(slot, "")


static func draw(ci: CanvasItem, kind: String, col: Color, r: Rect2, ghost := false) -> void:
	var ol := Color(0, 0, 0, 0) if ghost else OUTLINE
	var metal := col if ghost else METAL
	var wood := col if ghost else WOOD
	var gold := col if ghost else GOLDC
	var lw := maxf(1.0, r.size.x * 0.03)
	var P := func(x: float, y: float) -> Vector2: return r.position + Vector2(x, y) * r.size
	var S := r.size.x
	match kind:
		"sword", "saber", "greatsword", "cleaver":
			var bw: float = {"sword": 0.09, "saber": 0.07, "greatsword": 0.12, "cleaver": 0.22}[kind]
			var tip := Vector2(0.86, 0.14) if kind != "greatsword" else Vector2(0.9, 0.1)
			var base := Vector2(0.36, 0.64)
			var blade_end := tip - Vector2(0.06, -0.06) if kind != "cleaver" else tip
			_bar(ci, P, base, blade_end, bw, col, ol, lw)
			if kind != "cleaver":
				_poly(ci, P, [blade_end + Vector2(-bw * 0.35, -bw * 0.35), tip, blade_end + Vector2(bw * 0.35, bw * 0.35)], col, ol, lw)
			_bar(ci, P, Vector2(0.2, 0.5), Vector2(0.5, 0.8), 0.07, gold, ol, lw)
			_bar(ci, P, Vector2(0.34, 0.66), Vector2(0.17, 0.83), 0.06, wood if not ghost else col, ol, lw)
			_circle(ci, P.call(0.14, 0.86), S * 0.05, gold, ol, lw)
			if not ghost:
				_bar(ci, P, base + Vector2(0.04, -0.04), blade_end - Vector2(0.02, -0.02), bw * 0.22, col.lightened(0.45), Color(0, 0, 0, 0), 0)
		"staff":
			_bar(ci, P, Vector2(0.18, 0.9), Vector2(0.66, 0.34), 0.06, wood if not ghost else col, ol, lw)
			_bar(ci, P, Vector2(0.62, 0.42), Vector2(0.58, 0.24), 0.035, wood if not ghost else col, ol, lw)
			_bar(ci, P, Vector2(0.62, 0.42), Vector2(0.84, 0.36), 0.035, wood if not ghost else col, ol, lw)
			if not ghost:
				ci.draw_circle(P.call(0.73, 0.27), S * 0.2, Color(col.r, col.g, col.b, 0.22))
			_circle(ci, P.call(0.73, 0.27), S * 0.11, col, ol, lw)
			if not ghost:
				ci.draw_circle(P.call(0.7, 0.24), S * 0.035, Color(1, 1, 1, 0.8))
		"bow":
			var c: Vector2 = P.call(0.18, 0.5)
			var rad := S * 0.44
			ci.draw_arc(c, rad, -1.15, 1.15, 16, ol, S * 0.1 + lw, true)
			ci.draw_arc(c, rad, -1.15, 1.15, 16, col, S * 0.08, true)
			var a1 := c + Vector2(cos(-1.15), sin(-1.15)) * rad
			var a2 := c + Vector2(cos(1.15), sin(1.15)) * rad
			ci.draw_line(a1, a2, Color(0.9, 0.88, 0.8, 0.9) if not ghost else col, maxf(1.0, S * 0.02), true)
			_bar(ci, P, Vector2(0.12, 0.5), Vector2(0.8, 0.5), 0.03, wood if not ghost else col, ol, lw * 0.6)
			_poly(ci, P, [Vector2(0.78, 0.43), Vector2(0.92, 0.5), Vector2(0.78, 0.57)], metal, ol, lw)
			_poly(ci, P, [Vector2(0.1, 0.44), Vector2(0.2, 0.5), Vector2(0.1, 0.56)], Color(0.85, 0.25, 0.2) if not ghost else col, ol, lw * 0.6)
		"helm":
			_poly(ci, P, _arc_pts(Vector2(0.5, 0.5), 0.3, PI, TAU, 10) + [Vector2(0.8, 0.8), Vector2(0.2, 0.8)], col, ol, lw)
			if not ghost:
				ci.draw_rect(Rect2(P.call(0.28, 0.52), r.size * Vector2(0.44, 0.06)), Color(0.05, 0.05, 0.05))
				_bar(ci, P, Vector2(0.5, 0.2), Vector2(0.5, 0.8), 0.05, col.lightened(0.3), Color(0, 0, 0, 0), 0)
		"hat":
			_poly(ci, P, [Vector2(0.55, 0.08), Vector2(0.74, 0.7), Vector2(0.28, 0.7)], col, ol, lw)
			_poly(ci, P, _ellipse(Vector2(0.5, 0.72), 0.4, 0.1, 14), col.darkened(0.2), ol, lw)
			if not ghost:
				_bar(ci, P, Vector2(0.31, 0.63), Vector2(0.71, 0.63), 0.06, GOLDC, Color(0, 0, 0, 0), 0)
		"hood":
			_poly(ci, P, _arc_pts(Vector2(0.5, 0.52), 0.32, PI, TAU, 10) + [Vector2(0.86, 0.86), Vector2(0.14, 0.86)], col, ol, lw)
			if not ghost:
				_poly(ci, P, _ellipse(Vector2(0.5, 0.6), 0.17, 0.2, 12), Color(0.04, 0.03, 0.03), Color(0, 0, 0, 0), 0)
		"chest":
			_poly(ci, P, [Vector2(0.18, 0.22), Vector2(0.38, 0.14), Vector2(0.5, 0.24), Vector2(0.62, 0.14),
				Vector2(0.82, 0.22), Vector2(0.88, 0.46), Vector2(0.73, 0.5), Vector2(0.7, 0.86), Vector2(0.3, 0.86),
				Vector2(0.27, 0.5), Vector2(0.12, 0.46)], col, ol, lw)
			if not ghost:
				_bar(ci, P, Vector2(0.5, 0.3), Vector2(0.5, 0.8), 0.04, col.lightened(0.3), Color(0, 0, 0, 0), 0)
				_bar(ci, P, Vector2(0.3, 0.66), Vector2(0.7, 0.66), 0.05, col.darkened(0.35), Color(0, 0, 0, 0), 0)
		"glove":
			for i in 4:
				var x := 0.33 + i * 0.1
				_bar(ci, P, Vector2(x, 0.48), Vector2(x, 0.2 + abs(i - 1.5) * 0.05), 0.08, col, ol, lw)
			_bar(ci, P, Vector2(0.3, 0.62), Vector2(0.16, 0.42), 0.09, col, ol, lw)
			_poly(ci, P, [Vector2(0.28, 0.42), Vector2(0.7, 0.42), Vector2(0.7, 0.75), Vector2(0.3, 0.75)], col, ol, lw)
			_poly(ci, P, [Vector2(0.26, 0.74), Vector2(0.74, 0.74), Vector2(0.76, 0.9), Vector2(0.24, 0.9)], col.darkened(0.25), ol, lw)
		"boot":
			_poly(ci, P, [Vector2(0.32, 0.12), Vector2(0.62, 0.12), Vector2(0.62, 0.58), Vector2(0.84, 0.68),
				Vector2(0.88, 0.86), Vector2(0.28, 0.86), Vector2(0.3, 0.58)], col, ol, lw)
			_poly(ci, P, [Vector2(0.3, 0.12), Vector2(0.64, 0.12), Vector2(0.64, 0.24), Vector2(0.3, 0.24)], col.darkened(0.25), ol, lw)
			if not ghost:
				_bar(ci, P, Vector2(0.28, 0.83), Vector2(0.88, 0.83), 0.05, Color(0.15, 0.1, 0.06), Color(0, 0, 0, 0), 0)
		"shield":
			_poly(ci, P, [Vector2(0.18, 0.14), Vector2(0.82, 0.14), Vector2(0.82, 0.48), Vector2(0.5, 0.9), Vector2(0.18, 0.48)], col, ol, lw)
			if not ghost:
				_bar(ci, P, Vector2(0.5, 0.2), Vector2(0.5, 0.78), 0.07, GOLDC, Color(0, 0, 0, 0), 0)
				_bar(ci, P, Vector2(0.26, 0.38), Vector2(0.74, 0.38), 0.07, GOLDC, Color(0, 0, 0, 0), 0)
				_circle(ci, P.call(0.5, 0.38), S * 0.07, GOLDC, ol, lw)
		"orb":
			if not ghost:
				ci.draw_circle(P.call(0.5, 0.5), S * 0.4, Color(col.r, col.g, col.b, 0.18))
				ci.draw_circle(P.call(0.5, 0.5), S * 0.32, Color(col.r, col.g, col.b, 0.3))
			_circle(ci, P.call(0.5, 0.5), S * 0.24, col, ol, lw)
			if not ghost:
				ci.draw_circle(P.call(0.43, 0.42), S * 0.07, Color(1, 1, 1, 0.75))
		"quiver":
			for i in 3:
				var x := 0.48 + i * 0.09
				_bar(ci, P, Vector2(x - 0.18, 0.4), Vector2(x, 0.1), 0.03, metal, ol, lw * 0.5)
				_poly(ci, P, [Vector2(x - 0.03, 0.13), Vector2(x + 0.02, 0.06), Vector2(x + 0.04, 0.15)], Color(0.9, 0.3, 0.25) if not ghost else col, Color(0, 0, 0, 0), 0)
			_bar(ci, P, Vector2(0.28, 0.88), Vector2(0.56, 0.36), 0.2, col, ol, lw)
		"amulet":
			ci.draw_arc(P.call(0.5, 0.4), S * 0.27, PI * 1.05, TAU * 0.98, 16, gold, maxf(1.5, S * 0.04), true)
			_poly(ci, P, [Vector2(0.5, 0.5), Vector2(0.64, 0.66), Vector2(0.5, 0.86), Vector2(0.36, 0.66)], col, ol, lw)
			if not ghost:
				ci.draw_circle(P.call(0.47, 0.62), S * 0.035, Color(1, 1, 1, 0.7))
		"ring":
			ci.draw_arc(P.call(0.5, 0.6), S * 0.24, 0, TAU, 24, ol, S * 0.1 + lw, true)
			ci.draw_arc(P.call(0.5, 0.6), S * 0.24, 0, TAU, 24, gold, S * 0.08, true)
			_poly(ci, P, [Vector2(0.5, 0.18), Vector2(0.62, 0.3), Vector2(0.5, 0.42), Vector2(0.38, 0.3)], col, ol, lw)
		"potion":
			_poly(ci, P, [Vector2(0.42, 0.2), Vector2(0.58, 0.2), Vector2(0.58, 0.4), Vector2(0.42, 0.4)], Color(0.7, 0.8, 0.85, 0.6) if not ghost else col, ol, lw)
			_circle(ci, P.call(0.5, 0.62), S * 0.27, Color(0.7, 0.8, 0.85, 0.35) if not ghost else col, ol, lw)
			if not ghost:
				_poly(ci, P, _arc_pts(Vector2(0.5, 0.62), 0.24, -0.3, PI + 0.3, 12), col, Color(0, 0, 0, 0), 0)
				ci.draw_circle(P.call(0.42, 0.55), S * 0.05, Color(1, 1, 1, 0.7))
				_poly(ci, P, [Vector2(0.4, 0.12), Vector2(0.6, 0.12), Vector2(0.6, 0.22), Vector2(0.4, 0.22)], WOOD, ol, lw)
		"bowl":
			if not ghost:
				for i in 3:
					var x := 0.36 + i * 0.14
					ci.draw_polyline(PackedVector2Array([P.call(x, 0.4), P.call(x + 0.04, 0.3), P.call(x, 0.2), P.call(x + 0.04, 0.1)]),
						Color(1, 1, 1, 0.45), maxf(1.0, S * 0.025), true)
			_poly(ci, P, _ellipse(Vector2(0.5, 0.52), 0.36, 0.09, 14), col, ol, lw)
			_poly(ci, P, _arc_pts(Vector2(0.5, 0.52), 0.36, 0, PI, 12), WOOD if not ghost else col, ol, lw)
		"bread":
			_poly(ci, P, _ellipse(Vector2(0.5, 0.56), 0.38, 0.24, 16), col, ol, lw)
			if not ghost:
				for i in 3:
					var x := 0.36 + i * 0.13
					ci.draw_line(P.call(x, 0.46), P.call(x + 0.08, 0.62), col.darkened(0.35), maxf(1.0, S * 0.03), true)
		"crop":
			_circle(ci, P.call(0.5, 0.6), S * 0.26, col, ol, lw)
			_poly(ci, P, [Vector2(0.5, 0.36), Vector2(0.36, 0.14), Vector2(0.48, 0.2)], Color(0.3, 0.75, 0.25) if not ghost else col, ol, lw)
			_poly(ci, P, [Vector2(0.5, 0.36), Vector2(0.66, 0.12), Vector2(0.56, 0.24)], Color(0.3, 0.75, 0.25) if not ghost else col, ol, lw)
			if not ghost:
				ci.draw_circle(P.call(0.41, 0.52), S * 0.05, Color(1, 1, 1, 0.45))
		"wheat":
			ci.draw_line(P.call(0.5, 0.92), P.call(0.5, 0.2), Color(0.7, 0.6, 0.25), maxf(1.0, S * 0.03), true)
			for i in 4:
				var y := 0.22 + i * 0.12
				_poly(ci, P, _ellipse(Vector2(0.42, y + 0.04), 0.07, 0.045, 8), col, ol, lw * 0.6)
				_poly(ci, P, _ellipse(Vector2(0.58, y + 0.04), 0.07, 0.045, 8), col, ol, lw * 0.6)
		"seed":
			_poly(ci, P, [Vector2(0.3, 0.32), Vector2(0.7, 0.32), Vector2(0.8, 0.86), Vector2(0.2, 0.86)], LEATHER if not ghost else col, ol, lw)
			_bar(ci, P, Vector2(0.3, 0.32), Vector2(0.7, 0.32), 0.06, LEATHER.darkened(0.3) if not ghost else col, ol, lw)
			for v in [Vector2(0.42, 0.2), Vector2(0.55, 0.16), Vector2(0.5, 0.26)]:
				_circle(ci, P.call(v.x, v.y), S * 0.05, col, ol, lw * 0.6)
		"gel":
			_poly(ci, P, _arc_pts(Vector2(0.5, 0.66), 0.32, PI, TAU, 12) + [Vector2(0.82, 0.8), Vector2(0.18, 0.8)], col, ol, lw)
			if not ghost:
				ci.draw_circle(P.call(0.4, 0.52), S * 0.06, Color(1, 1, 1, 0.6))
		"ear":
			_poly(ci, P, [Vector2(0.2, 0.75), Vector2(0.86, 0.14), Vector2(0.62, 0.82)], col, ol, lw)
		"crown":
			_poly(ci, P, [Vector2(0.16, 0.74), Vector2(0.16, 0.32), Vector2(0.33, 0.52), Vector2(0.5, 0.24),
				Vector2(0.67, 0.52), Vector2(0.84, 0.32), Vector2(0.84, 0.74)], col, ol, lw)
			if not ghost:
				_circle(ci, P.call(0.5, 0.62), S * 0.06, Color(0.9, 0.1, 0.15), ol, lw * 0.6)
		# ---- magias e ações do HUD
		"fireball":
			_poly(ci, P, [Vector2(0.3, 0.7), Vector2(0.4, 0.2), Vector2(0.5, 0.45), Vector2(0.62, 0.1), Vector2(0.74, 0.7)], Color(1, 0.55, 0.1), ol, lw)
			_circle(ci, P.call(0.52, 0.66), S * 0.22, Color(1, 0.45, 0.08), ol, lw)
			ci.draw_circle(P.call(0.52, 0.68), S * 0.11, Color(1, 0.9, 0.45))
		"heal":
			_poly(ci, P, [Vector2(0.4, 0.15), Vector2(0.6, 0.15), Vector2(0.6, 0.4), Vector2(0.85, 0.4), Vector2(0.85, 0.6),
				Vector2(0.6, 0.6), Vector2(0.6, 0.85), Vector2(0.4, 0.85), Vector2(0.4, 0.6), Vector2(0.15, 0.6),
				Vector2(0.15, 0.4), Vector2(0.4, 0.4)], Color(0.35, 0.95, 0.45), ol, lw)
		"frost":
			for i in 3:
				var a := i * PI / 3.0
				var d := Vector2(cos(a), sin(a)) * 0.36
				ci.draw_line(P.call(0.5 - d.x, 0.5 - d.y), P.call(0.5 + d.x, 0.5 + d.y), Color(0.7, 0.92, 1.0), maxf(2.0, S * 0.07), true)
			_circle(ci, P.call(0.5, 0.5), S * 0.09, Color(0.85, 0.97, 1.0), ol, lw)


# ------------------------------------------------------------------ primitivas
static func _poly(ci: CanvasItem, P: Callable, pts: Array, fill: Color, ol: Color, lw: float) -> void:
	var arr := PackedVector2Array()
	for p in pts:
		arr.append(P.call(p.x, p.y))
	if arr.size() < 3:
		return
	ci.draw_colored_polygon(arr, fill)
	if ol.a > 0.0 and lw > 0.0:
		arr.append(arr[0])
		ci.draw_polyline(arr, ol, lw, true)


## Barra grossa entre dois pontos (espessura em unidades do ícone).
static func _bar(ci: CanvasItem, P: Callable, a: Vector2, b: Vector2, w: float, fill: Color, ol: Color, lw: float) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x) * w * 0.5
	_poly(ci, P, [a + n, b + n, b - n, a - n], fill, ol, lw)


static func _circle(ci: CanvasItem, c: Vector2, rad: float, fill: Color, ol: Color, lw: float) -> void:
	if ol.a > 0.0 and lw > 0.0:
		ci.draw_circle(c, rad + lw * 0.8, ol)
	ci.draw_circle(c, rad, fill)


static func _arc_pts(c: Vector2, rad: float, a0: float, a1: float, n: int) -> Array:
	var out := []
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		out.append(c + Vector2(cos(a), sin(a)) * rad)
	return out


static func _ellipse(c: Vector2, rx: float, ry: float, n: int) -> Array:
	var out := []
	for i in n:
		var a := TAU * i / n
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return out
