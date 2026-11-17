class_name AtlasView
extends Control
## Mapa-mundi interativo (tela cheia, aberto pelo M): todas as regiões lado a lado (MapRules.atlas_*), cada
## uma com a foto de cima (MapCapture) e o nome. A roda do mouse dá zoom em volta do cursor, arrastar move,
## clique duplo numa região aproxima nela. Passar o mouse sobre um NPC, a carruagem (com as saídas para os
## outros mapas), um lugar, o jogador ou um companheiro mostra uma ficha. Os nomes dos lugares aparecem com
## o zoom; os de todos os NPCs, de perto.

const C_SEA := Color(0.07, 0.085, 0.1)
const C_PLAYER := MapView.C_PLAYER
const C_PARTY := MapView.C_PARTY
const C_NPC := MapView.C_NPC
const C_QUEST := MapView.C_QUEST
const C_ROUTE := Color(0.95, 0.78, 0.4)
const C_LOCKED := Color(0.55, 0.52, 0.5)
const C_LABEL := Color(1, 0.95, 0.85)
## Escala máxima (pixels por metro).
const MAX_SCALE := 14.0
## A partir de que escala aparecem os nomes dos lugares e os de todos os NPCs.
const PLACES_AT := 2.6
const NPC_NAMES_AT := 6.0
const QUEST_NAMES_AT := 5.0
## Altura das barras de cima e de baixo (o "caber na tela" desconta).
const BARS_H := 170.0

var world: Node
var capture: MapCapture
## Centro da tela no atlas (metros) e escala (px/m); _goal_* é para onde o zoom/movimento está indo.
var center := Vector2.ZERO
var zoom := 3.0
var _goal_center := Vector2.ZERO
var _goal_zoom := 3.0
var _dragging := false
var _drag_moved := 0.0
var _mouse := Vector2(-1000, -1000)
## Pontos que respondem ao mouse, montados a cada desenho: {at, r, title, lines: [[texto, cor]], color}.
var _hits: Array = []
## Ficha sob o mouse ({} = nenhuma); `hover_title` fica exposto para os testes.
var hover_title := ""
var _t := 0.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	if capture:
		capture.captured.connect(func(_r: String) -> void: queue_redraw())
		for id in Regions.ORDER:
			capture.texture(id)
	resized.connect(_on_first_size, CONNECT_ONE_SHOT)


## Abre na região do jogador, cabendo na tela.
func _on_first_size() -> void:
	var p := _player()
	focus_region(Regions.region_at(p.global_position) if p else "vila", true)
	if p:
		center = MapRules.to_atlas(p.global_position).lerp(center, 0.5)
		_goal_center = center


func min_zoom() -> float:
	var b := MapRules.atlas_bounds().grow(30.0)
	return minf(size.x / b.size.x, (size.y - BARS_H) / b.size.y) if size.x > 0.0 else 1.0


## Aproxima numa região (a região inteira cabe na tela).
func focus_region(id: String, instant := false) -> void:
	var r := MapRules.atlas_rect(id).grow(12.0)
	_goal_center = r.get_center()
	_goal_zoom = clampf(minf(size.x / r.size.x, (size.y - BARS_H) / r.size.y), min_zoom(), MAX_SCALE)
	if instant:
		center = _goal_center
		zoom = _goal_zoom
	queue_redraw()


## Volta para o jogador, de perto.
func focus_player() -> void:
	var p := _player()
	if p == null:
		return
	_goal_center = MapRules.to_atlas(p.global_position)
	_goal_zoom = maxf(_goal_zoom, 5.0)


## Mostra o mundo inteiro.
func show_all() -> void:
	_goal_center = MapRules.atlas_bounds().get_center()
	_goal_zoom = min_zoom()


## Zoom por um fator em volta de um ponto da tela (o meio, sem mouse).
func zoom_by(factor: float, screen_at := Vector2(-1, -1)) -> void:
	if screen_at.x < 0.0:
		screen_at = size / 2.0
	var off := screen_at - size / 2.0
	var anchor := _goal_center + off / _goal_zoom
	_goal_zoom = clampf(_goal_zoom * factor, min_zoom(), MAX_SCALE)
	_goal_center = MapRules.zoom_center(anchor, off, _goal_zoom)
	_clamp_center()


func _process(delta: float) -> void:
	var k := 1.0 - exp(-delta * 14.0)
	var moving := center.distance_to(_goal_center) * zoom > 0.3 or absf(zoom - _goal_zoom) > 0.001
	if moving:
		center = center.lerp(_goal_center, k)
		zoom = lerpf(zoom, _goal_zoom, k)
		_clamp_center()
		queue_redraw()
	_t -= delta
	if _t <= 0.0:
		_t = 0.2   # NPCs, grupo e jogador se mexem
		queue_redraw()


## O centro da tela fica sempre sobre um mapa (de perto) ou perto dele (afastado, para ver o mundo
## inteiro): não se arrasta para onde não há mapa.
func _clamp_center() -> void:
	center = MapRules.clamp_to_land(center, _slack(zoom))
	_goal_center = MapRules.clamp_to_land(_goal_center, _slack(_goal_zoom))


## Mar permitido além da borda: só com o mundo inteiro na tela (o centro dele cai entre os mapas); vai a
## zero quando o zoom chega no dobro do afastado. De perto, a borda do mapa é o limite.
func _slack(z: float) -> float:
	var mz := min_zoom()
	var t := clampf((2.0 * mz - z) / mz, 0.0, 1.0)
	var b := MapRules.atlas_bounds().get_center()
	return b.distance_to(MapRules.clamp_to_land(b)) * t


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(1.2, mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.0 / 1.2, mb.position)
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if mb.double_click and mb.button_index == MOUSE_BUTTON_LEFT:
				var reg := region_under(mb.position)
				if reg != "":
					focus_region(reg)
			_dragging = mb.pressed
			_drag_moved = 0.0
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_mouse = mm.position
		if _dragging:
			_drag_moved += mm.relative.length()
			_goal_center -= mm.relative / zoom
			center -= mm.relative / zoom
			_clamp_center()
		queue_redraw()
		accept_event()
	elif event is InputEventMagnifyGesture:
		zoom_by((event as InputEventMagnifyGesture).factor, _mouse)
		accept_event()
	elif event is InputEventPanGesture:
		var d := (event as InputEventPanGesture).delta * 12.0 / zoom
		_goal_center += d
		center += d
		_clamp_center()
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_mouse = Vector2(-1000, -1000)
		queue_redraw()


func to_screen(a: Vector2) -> Vector2:
	return (a - center) * zoom + size / 2.0


func to_atlas(s: Vector2) -> Vector2:
	return (s - size / 2.0) / zoom + center


func region_under(s: Vector2) -> String:
	return MapRules.atlas_region_at(to_atlas(s))


func _player() -> Node3D:
	var p = world.get("player") if world else null
	return p if p != null and is_instance_valid(p) else null


func _screen_rect(id: String) -> Rect2:
	var r := MapRules.atlas_rect(id)
	return Rect2(to_screen(r.position), r.size * zoom)


# ================================================================ desenho
func _draw() -> void:
	_hits.clear()
	draw_rect(Rect2(Vector2.ZERO, size), C_SEA)
	_draw_grid()
	var rank := Game.rank()
	for id in Regions.ORDER:
		_draw_region(id, Regions.unlocked(id, rank))
	_draw_routes(rank)
	var places_a := clampf((zoom - PLACES_AT) / 0.8, 0.0, 1.0)
	for id in Regions.ORDER:
		_draw_areas(id, places_a)
	for id in Regions.ORDER:
		_draw_places(id, places_a, rank)
	_draw_npcs()
	_draw_quest()
	_draw_party()
	_draw_player()
	for id in Regions.ORDER:
		_draw_region_name(id, Regions.unlocked(id, rank))
	_draw_compass()
	_draw_hover(rank)


## Linhas finas de latitude no mar (dão sensação de mapa e de movimento ao arrastar).
func _draw_grid() -> void:
	var step := 50.0
	var tl := to_atlas(Vector2.ZERO)
	var br := to_atlas(size)
	var c := Color(1, 1, 1, 0.035)
	var x := floorf(tl.x / step) * step
	while x <= br.x:
		var sx := to_screen(Vector2(x, 0)).x
		draw_line(Vector2(sx, 0), Vector2(sx, size.y), c, 1.0)
		x += step
	var y := floorf(tl.y / step) * step
	while y <= br.y:
		var sy := to_screen(Vector2(0, y)).y
		draw_line(Vector2(0, sy), Vector2(size.x, sy), c, 1.0)
		y += step


## O mapa é um disco com a foto de cima (MapView.draw_map_disc) e a moldura dourada.
func _draw_region(id: String, open: bool) -> void:
	if not _screen_rect(id).intersects(Rect2(Vector2.ZERO, size).grow(20.0)):
		return
	var c := to_screen(MapRules.atlas_center(id))
	var rad := MapRules.radius(id) * zoom
	draw_circle(c + Vector2(6, 8), rad, Color(0, 0, 0, 0.45))
	var tex: Texture2D = capture.texture(id) if capture else null
	var cap := MapRules.capture_rect(id)
	var o: Vector3 = Regions.origin(id)
	MapView.draw_map_disc(self, c, rad, tex, (Vector2(o.x, o.z) - cap.position) / cap.size, MapRules.radius(id) / cap.size.x)
	if not open:
		draw_circle(c, rad, Color(0.05, 0.05, 0.07, 0.62))
	var hovered := region_under(_mouse) == id
	draw_arc(c, rad, 0, TAU, 96, Color(UITheme.GOLD, 0.95 if hovered else 0.6), 3.0 if hovered else 2.0, true)


## Região cujas saídas aparecem: a da carruagem sob o mouse ou, sem ela, a do jogador.
func _routes_from() -> String:
	for id in Regions.ORDER:
		if _mouse.distance_to(to_screen(MapRules.to_atlas(Regions.coach_point(id)))) <= 16.0:
			return id
	var p := _player()
	return Regions.region_at(p.global_position) if p else "vila"


## Saídas da carruagem: uma rota tracejada até a carruagem de cada outro mapa (dourada se o rank já libera
## o destino) e, onde ela cruza a borda do mapa, uma plaquinha com o nome do destino.
func _draw_routes(rank: String) -> void:
	var a := _routes_from()
	var pa := to_screen(MapRules.to_atlas(Regions.coach_point(a)))
	var font := UITheme.body()
	for e in MapRules.exits(a, rank):
		var b: String = e[0]
		var pb := to_screen(MapRules.to_atlas(Regions.coach_point(b)))
		var c := Color(C_ROUTE, 0.85) if e[1] else Color(C_LOCKED, 0.75)
		draw_dashed_line(pa, pb, Color(0, 0, 0, 0.55), 4.5, 12.0)
		draw_dashed_line(pa, pb, c, 2.5, 12.0)
		# a placa fica no mar entre os dois mapas (mais perto da saída); fora da tela, na beira dela
		var edge := _circle_exit(a, pa, pb).lerp(_circle_exit(b, pb, pa), 0.4)
		var screen := Rect2(Vector2(70, 80), size - Vector2(140, 200))   # sem cobrir as barras de cima e de baixo
		if not screen.has_point(edge) and screen.has_point(pa):
			edge = _exit_point(screen, pa, edge)
		var tag := ("%s  →" if e[1] else "%s  · Rank " + str(Regions.DATA[b].rank)) % Regions.display_name(b)
		var w := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var pill := Rect2(edge - Vector2(w / 2.0 + 9, 13), Vector2(w + 18, 24))
		draw_rect(pill, Color(0.06, 0.05, 0.04, 0.88))
		draw_rect(pill, c, false, 1.5)
		draw_string(font, pill.position + Vector2(9, 17), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			C_ROUTE if e[1] else Color(0.82, 0.79, 0.75))


## Onde o segmento p→q (p dentro do círculo da região) sai do círculo, na tela.
func _circle_exit(id: String, p: Vector2, q: Vector2) -> Vector2:
	var c := to_screen(MapRules.atlas_center(id))
	var r := MapRules.radius(id) * zoom
	var d := q - p
	var a := d.dot(d)
	if a < 0.001:
		return p
	var f := p - c
	var b := 2.0 * f.dot(d)
	var disc := b * b - 4.0 * a * (f.dot(f) - r * r)
	if disc < 0.0:
		return p
	return p + d * clampf((-b + sqrt(disc)) / (2.0 * a), 0.0, 1.0)


## Onde o segmento a→b (a dentro de `box`) sai do retângulo.
static func _exit_point(box: Rect2, a: Vector2, b: Vector2) -> Vector2:
	var d := b - a
	var t := 1.0
	if d.x > 0.0:
		t = minf(t, (box.end.x - a.x) / d.x)
	elif d.x < 0.0:
		t = minf(t, (box.position.x - a.x) / d.x)
	if d.y > 0.0:
		t = minf(t, (box.end.y - a.y) / d.y)
	elif d.y < 0.0:
		t = minf(t, (box.position.y - a.y) / d.y)
	return a + d * clampf(t, 0.0, 1.0)


func _draw_places(id: String, alpha: float, rank: String) -> void:
	var font := UITheme.body()
	for pl in MapRules.places(id):
		var at := to_screen(MapRules.to_atlas(pl[1]))
		if not _inside(at, 40.0):
			continue
		var coach: bool = pl[0] == "Carruagem da Guilda"
		if coach:
			_draw_coach(at)
			var lines: Array = [["Saídas para:", UITheme.DIM]]
			for e in MapRules.exits(id, rank):
				if e[1]:
					lines.append(["→  " + Regions.display_name(e[0]), UITheme.TEXT])
				else:
					lines.append(["→  %s  (Rank %s)" % [Regions.display_name(e[0]), Regions.DATA[e[0]].rank], C_LOCKED])
			lines.append(["Fale com o cocheiro para viajar.", UITheme.DIM])
			_hits.append({"at": at, "r": 14.0, "title": "Carruagem da Guilda", "lines": lines, "color": C_ROUTE})
		elif pl[0] != Regions.display_name(id):   # o centro do mapa com o nome dele: a ficha é a da região
			_hits.append({"at": at, "r": 10.0, "title": pl[0], "lines": [[Regions.display_name(id), UITheme.DIM]],
				"color": C_LABEL})
		if alpha <= 0.0 or (coach and zoom < NPC_NAMES_AT) or pl[0] == Regions.display_name(id):
			continue
		if not coach:
			draw_circle(at, 3.5, Color(0, 0, 0, 0.7 * alpha))
			draw_circle(at, 2.5, Color(C_LABEL, alpha))
		_text(at + Vector2(0, -10 if not coach else -18), pl[0], 15 if not coach else 12, Color(C_LABEL, alpha), font)


## Regiões de monstros do mapa `id`: mancha com contorno e "Nome · Nv a–b" (aparecem com o zoom, como os
## lugares); a ficha mostra a faixa.
func _draw_areas(id: String, alpha: float) -> void:
	var font := UITheme.body()
	var table: Dictionary = Balance.tables.get_table("regions")
	for item in MapRules.areas(id, table):
		var at := to_screen(MapRules.to_atlas(item[1]))
		if not _inside(at, 300.0):
			continue
		var info := Regions.area_info(table, item[2][0].id)
		var lines: Array = [[Regions.display_name(id), UITheme.DIM]]
		if info.level_min > 0:
			lines.push_front(["Monstros de nível %d a %d" % [info.level_min, info.level_max], UITheme.TEXT])
		_hits.append({"at": at, "r": 12.0, "title": info.name, "lines": lines, "color": MapView.C_AREA})
		if alpha <= 0.0:
			continue
		for a in item[2]:
			var pts := PackedVector2Array()
			for p in MapRules.area_outline(a):
				pts.append(to_screen(MapRules.to_atlas(Vector3(p.x, 0, p.y))))
			draw_colored_polygon(pts, Color(MapView.C_AREA, 0.12 * alpha))
			pts.append(pts[0])
			draw_polyline(pts, Color(MapView.C_AREA, 0.6 * alpha), 1.5, true)
		_text(at + Vector2(0, 5), item[0], 13, Color(1.0, 0.8, 0.65, alpha), font)


## Carruagem: um selo dourado com rodinhas.
func _draw_coach(at: Vector2) -> void:
	var s := clampf(zoom / 5.0, 0.8, 1.5)
	var body := Rect2(at + Vector2(-8, -6) * s, Vector2(16, 9) * s)
	draw_circle(at, 13.0 * s, Color(0, 0, 0, 0.55))
	draw_rect(body.grow(1.5), Color(0.12, 0.07, 0.02))
	draw_rect(body, C_ROUTE)
	for wx in [-5.0, 5.0]:
		draw_circle(at + Vector2(wx, 5) * s, 3.2 * s, Color(0.12, 0.07, 0.02))
		draw_circle(at + Vector2(wx, 5) * s, 1.8 * s, C_ROUTE)


func _draw_npcs() -> void:
	var font := UITheme.body()
	var s := clampf(zoom / 4.0, 0.8, 1.4)
	for n in get_tree().get_nodes_in_group("npc"):
		if not (n is Node3D):
			continue
		var at := to_screen(MapRules.to_atlas(n.global_position))
		if not _inside(at, 20.0):
			continue
		var nm := str(n.get("npc_name"))
		var mk = n.get("marker")
		var sym: String = mk.text if mk is Label3D else ""
		var lines: Array = []
		var r := 5.0 * s
		if sym == "":
			draw_circle(at, r + 1.5, Color(0, 0, 0, 0.75))
			draw_circle(at, r, C_NPC)
			lines.append(["Nenhuma missão agora.", UITheme.DIM])
		else:
			var col: Color = (mk as Label3D).modulate
			r = 9.0 * s
			draw_circle(at, r + 1.5, Color(0, 0, 0, 0.85))
			draw_circle(at, r, col)
			var fs := int(16 * s)
			var w := font.get_string_size(sym, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, at + Vector2(-w / 2.0, fs * 0.36), sym, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.1, 0.06, 0.02))
			lines.append([npc_status(sym, col), col])
		lines.append([Regions.display_name(Regions.region_at(n.global_position)), UITheme.DIM])
		_hits.append({"at": at, "r": maxf(r + 3.0, 9.0), "title": nm if nm != "" else "?", "lines": lines, "color": C_NPC})
		if nm != "" and (zoom >= NPC_NAMES_AT or (sym != "" and zoom >= QUEST_NAMES_AT)):
			_text(at + Vector2(0, r + 15), nm, 13, C_NPC, font)


## O que o !/? sobre a cabeça do NPC quer dizer (a cor separa história de contrato).
static func npc_status(sym: String, col: Color) -> String:
	if sym == "?":
		return "Missão pronta para entregar"
	if col.b > col.r:
		return "Contrato disponível"
	return "Missão da história disponível"


func _draw_quest() -> void:
	var hud = world.get("hud") if world else null
	if hud == null or not hud.has_method("_track_raw"):
		return
	var pos = hud._track_raw()
	if pos == null:
		return
	var at := to_screen(MapRules.to_atlas(pos))
	var pts := PackedVector2Array([at + Vector2(0, -9), at + Vector2(8, 0), at + Vector2(0, 9), at + Vector2(-8, 0)])
	draw_colored_polygon(pts, C_QUEST)
	pts.append(pts[0])
	draw_polyline(pts, Color(0.2, 0.08, 0.0), 1.5)
	_hits.append({"at": at, "r": 10.0, "title": "Missão rastreada", "lines": [[Regions.display_name(Regions.region_at(pos)),
		UITheme.DIM]], "color": C_QUEST})


func _draw_party() -> void:
	if not Network.is_online():
		return
	var font := UITheme.body()
	for peer in MapRules.shown_players(Network.remote_players.keys(), Party.others(), multiplayer.get_unique_id()):
		var rp = Network.remote_players.get(peer)
		if rp == null or not is_instance_valid(rp):
			continue
		var at := to_screen(MapRules.to_atlas(rp.global_position))
		draw_circle(at, 7.0, Color(0, 0, 0, 0.8))
		draw_circle(at, 5.5, C_PARTY)
		var n := str(Network.players.get(peer, {}).get("name", "?"))
		_text(at + Vector2(0, -11), n, 14, C_PARTY, font)
		_hits.append({"at": at, "r": 9.0, "title": n, "lines": [["Companheiro de grupo", C_PARTY],
			[Regions.display_name(Regions.region_at(rp.global_position)), UITheme.DIM]], "color": C_PARTY})


func _draw_player() -> void:
	var p := _player()
	if p == null:
		return
	var at := to_screen(MapRules.to_atlas(p.global_position))
	var fwd := Vector3(0, 0, -1)
	var cam = p.get("camera")
	if cam != null and is_instance_valid(cam):
		fwd = -(cam as Camera3D).global_basis.z
	var a := MapRules.heading(Vector3(fwd.x, 0, fwd.z))
	var s := clampf(zoom * 2.4, 10.0, 15.0)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 260.0)
	draw_arc(at, s + 5.0 + pulse * 4.0, 0, TAU, 32, Color(C_PLAYER, 0.5 - pulse * 0.3), 2.0)
	var pts := PackedVector2Array([Vector2(0, -s), Vector2(s * 0.7, s * 0.75), Vector2(0, s * 0.35), Vector2(-s * 0.7, s * 0.75)])
	for i in pts.size():
		pts[i] = at + pts[i].rotated(a)
	draw_colored_polygon(pts, C_PLAYER)
	pts.append(pts[0])
	draw_polyline(pts, Color(0.1, 0.07, 0.03), 2.0)
	_hits.append({"at": at, "r": s, "title": "Você", "lines": [[Regions.display_name(Regions.region_at(p.global_position)),
		UITheme.DIM]], "color": C_PLAYER})


## Nome da região em cima do retângulo dela (e o rank, se a carruagem ainda não vai para lá).
func _draw_region_name(id: String, open: bool) -> void:
	var r := _screen_rect(id)
	if not r.intersects(Rect2(Vector2.ZERO, size)):
		return
	var font := UITheme.serif()
	var fs := int(clampf(r.size.x / 11.0, 18.0, 34.0))
	var at := Vector2(r.get_center().x, r.position.y - 12.0)
	if at.y < fs + 4.0:
		at.y = maxf(r.position.y + fs + 6.0, fs + 6.0)   # região maior que a tela: o nome fica no alto
	_text(at, Regions.display_name(id), fs, UITheme.GOLD if open else C_LOCKED, font, 7)
	if not open:
		_text(r.get_center() + Vector2(0, 8), "Rank %s" % Regions.DATA[id].rank, int(fs * 0.9), C_LOCKED, font, 6)


func _draw_compass() -> void:
	var at := Vector2(size.x - 54, size.y - 70)
	var font := UITheme.serif()
	draw_circle(at, 26, Color(0, 0, 0, 0.5))
	draw_arc(at, 26, 0, TAU, 32, Color(UITheme.GOLD, 0.7), 1.5)
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -20), at + Vector2(6, 0), at + Vector2(-6, 0)]), UITheme.GOLD)
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, 20), at + Vector2(6, 0), at + Vector2(-6, 0)]), Color(UITheme.GOLD_DIM, 0.8))
	_text(at + Vector2(0, -32), "N", 16, UITheme.GOLD, font)


## Ficha do que está sob o mouse (o ponto mais perto); sem ponto, a região.
func _draw_hover(rank: String) -> void:
	hover_title = ""
	if _dragging and _drag_moved > 4.0:
		return
	var best := {}
	var best_d := INF
	for h in _hits:
		var d: float = _mouse.distance_to(h.at)
		if d <= float(h.r) and d < best_d:
			best = h
			best_d = d
	if best.is_empty():
		var reg := region_under(_mouse)
		if reg == "":
			return
		var lines: Array = []
		var p := _player()
		if p and Regions.region_at(p.global_position) == reg:
			lines.append(["Você está aqui.", C_PLAYER])
		if Regions.unlocked(reg, rank):
			lines.append(["Liberado para a carruagem.", UITheme.GOOD])
		else:
			lines.append(["A carruagem só vai com Rank %s." % Regions.DATA[reg].rank, UITheme.BAD])
		lines.append(["Clique duplo para aproximar.", UITheme.DIM])
		best = {"at": _mouse, "r": 0.0, "title": Regions.display_name(reg), "lines": lines, "color": UITheme.GOLD}
	else:
		draw_arc(best.at, float(best.r) + 3.0, 0, TAU, 28, Color(best.color, 0.95), 2.0)
	hover_title = str(best.title)
	_draw_card(best)


func _draw_card(h: Dictionary) -> void:
	var tf := UITheme.serif()
	var bf := UITheme.body()
	var w := tf.get_string_size(h.title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	for l in h.lines:
		w = maxf(w, bf.get_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x)
	var box := Rect2(Vector2.ZERO, Vector2(w + 28, 40 + 21 * h.lines.size()))
	box.position = _mouse + Vector2(18, 18)
	if box.end.x > size.x - 8:
		box.position.x = _mouse.x - box.size.x - 18
	if box.end.y > size.y - 8:
		box.position.y = _mouse.y - box.size.y - 18
	draw_rect(Rect2(box.position + Vector2(3, 4), box.size), Color(0, 0, 0, 0.4))
	draw_rect(box, UITheme.BG)
	draw_rect(box, Color(h.color, 0.85), false, 1.5)
	draw_string(tf, box.position + Vector2(14, 28), h.title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, h.color)
	var y := 52.0
	for l in h.lines:
		draw_string(bf, box.position + Vector2(14, y), l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, l[1])
		y += 21.0


func _inside(at: Vector2, margin := 0.0) -> bool:
	return at.x >= -margin and at.y >= -margin and at.x <= size.x + margin and at.y <= size.y + margin


## Texto centrado em `at` (linha de base), com contorno escuro.
func _text(at: Vector2, s: String, fs: int, c: Color, font: Font, outline := 4) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := at - Vector2(w / 2.0, 0)
	draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, Color(0, 0, 0, 0.85 * c.a))
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
