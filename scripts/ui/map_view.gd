class_name MapView
extends Control
## Desenho do mapa visto de cima (MapCapture) com os marcadores: o jogador (seta na direção da câmera),
## os companheiros de grupo (no multiplayer só o grupo aparece), os NPCs, o destino da missão rastreada e,
## no mapa grande, os nomes dos lugares. Modo "mini" segue o jogador (raio MapRules.MINI_RADIUS); modo
## "full" mostra a região inteira (`region`).

const C_BG := Color(0.13, 0.17, 0.12)
const C_PLAYER := Color(1.0, 0.95, 0.7)
const C_PARTY := Color(0.4, 1.0, 0.55)
const C_NPC := Color(1.0, 0.82, 0.3)
const C_QUEST := Color(1.0, 0.6, 0.15)

var mode := "mini"
## Região mostrada no modo "full" ("" = a do jogador).
var region := ""
var world: Node
var capture: MapCapture
var _t := 0.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if capture:
		capture.captured.connect(func(_r: String) -> void: queue_redraw())


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = 0.05 if mode == "mini" else 0.2
		queue_redraw()


func _player() -> Node3D:
	var p = world.get("player") if world else null
	return p if p != null and is_instance_valid(p) else null


## Região que está sendo mostrada.
func shown_region() -> String:
	var p := _player()
	if mode == "full" and region != "":
		return region
	return Regions.region_at(p.global_position) if p else "vila"


## Pedaço do mundo (plano XZ) que cabe no controle.
func view_rect() -> Rect2:
	var reg := shown_region()
	var p := _player()
	if mode == "mini" and p:
		var r := MapRules.MINI_RADIUS
		return Rect2(p.global_position.x - r, p.global_position.z - r, r * 2.0, r * 2.0)
	return MapRules.rect(reg)


func world_to_local(pos: Vector3) -> Vector2:
	var v := view_rect()
	return Vector2((pos.x - v.position.x) / v.size.x * size.x, (pos.z - v.position.y) / v.size.y * size.y)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), C_BG)
	var reg := shown_region()
	_draw_terrain(reg)
	var full := mode == "full"
	_draw_npcs(reg, full)
	if full:
		var font := UITheme.body()
		for pl in MapRules.places(reg):
			var at := world_to_local(pl[1])
			var fs := 15 if pl[0] != "Carruagem da Guilda" else 12
			var w := font.get_string_size(pl[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string_outline(font, at + Vector2(-w / 2.0, -8), pl[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.85))
			draw_string(font, at + Vector2(-w / 2.0, -8), pl[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.95, 0.85))
			draw_circle(at, 3.0, Color(1, 0.95, 0.85, 0.9))
	_draw_quest(reg)
	_draw_party(reg, full)
	_draw_player(reg)
	if not full:
		var font := UITheme.body()
		draw_string_outline(font, Vector2(size.x / 2.0 - 5, 15), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.9))
		draw_string(font, Vector2(size.x / 2.0 - 5, 15), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.9, 0.6))


## A foto da região recortada pelo pedaço visível (o que passa da borda do mapa fica com o fundo).
func _draw_terrain(reg: String) -> void:
	var tex: Texture2D = capture.texture(reg) if capture else null
	if tex == null:
		return
	var v := view_rect()
	var m := MapRules.rect(reg)
	var vis := v.intersection(m)
	if vis.size.x <= 0.0 or vis.size.y <= 0.0:
		return
	var ts := Vector2(tex.get_width(), tex.get_height())
	var src := Rect2((vis.position - m.position) / m.size * ts, vis.size / m.size * ts)
	var dst := Rect2((vis.position - v.position) / v.size * size, vis.size / v.size * size)
	draw_texture_rect_region(tex, dst, src)


func _inside(at: Vector2, margin := 0.0) -> bool:
	return at.x >= -margin and at.y >= -margin and at.x <= size.x + margin and at.y <= size.y + margin


## Leva um ponto fora do minimapa para a borda (os marcadores ficam visíveis apontando a direção).
func _clamp_edge(at: Vector2, margin: float) -> Vector2:
	return Vector2(clampf(at.x, margin, size.x - margin), clampf(at.y, margin, size.y - margin))


## NPCs da região: um ponto dourado; quem tem missão (o mesmo !/? de cima da cabeça) ganha um selo com o
## símbolo, que no minimapa fica preso na borda quando o NPC está fora do raio. No mapa grande, o nome de
## quem tem missão (todos os nomes juntos não cabem na vila).
func _draw_npcs(reg: String, full: bool) -> void:
	var font := UITheme.body()
	var s := 1.0 if full else 0.9
	for n in get_tree().get_nodes_in_group("npc"):
		if not (n is Node3D) or Regions.region_at(n.global_position) != reg:
			continue
		var at := world_to_local(n.global_position)
		var mk = n.get("marker")
		var sym: String = mk.text if mk is Label3D else ""
		if sym == "":
			if not _inside(at, 6.0):
				continue
			draw_circle(at, 5.5 * s, Color(0, 0, 0, 0.75))
			draw_circle(at, 4.0 * s, C_NPC)
		else:
			if mode == "mini":
				at = _clamp_edge(at, 10.0)
			elif not _inside(at):
				continue
			var r := 9.0 * s
			draw_circle(at, r + 1.5, Color(0, 0, 0, 0.85))
			draw_circle(at, r, (mk as Label3D).modulate)
			var fs := int(16 * s)
			var w := font.get_string_size(sym, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, at + Vector2(-w / 2.0, fs * 0.36), sym, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.1, 0.06, 0.02))
		if full and sym != "":
			var nm := str(n.get("npc_name"))
			var w2 := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			var p := at + Vector2(-w2 / 2.0, 22)
			draw_string_outline(font, p, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.9))
			draw_string(font, p, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_NPC)


func _draw_quest(reg: String) -> void:
	var hud = world.get("hud") if world else null
	if hud == null or not hud.has_method("track_pos"):
		return
	var pos = hud.track_pos()
	if pos == null or Regions.region_at(pos) != reg:
		return
	var at := world_to_local(pos)
	if mode == "mini":
		at = _clamp_edge(at, 7.0)
	elif not _inside(at):
		return
	var pts := PackedVector2Array([at + Vector2(0, -8), at + Vector2(7, 0), at + Vector2(0, 8), at + Vector2(-7, 0)])
	draw_colored_polygon(pts, C_QUEST)
	pts.append(pts[0])
	draw_polyline(pts, Color(0.2, 0.08, 0.0), 1.5)


func _draw_party(reg: String, full: bool) -> void:
	if not Network.is_online():
		return
	var me := multiplayer.get_unique_id()
	var font := UITheme.body()
	for peer in MapRules.shown_players(Network.remote_players.keys(), Party.others(), me):
		var rp = Network.remote_players.get(peer)
		if rp == null or not is_instance_valid(rp) or Regions.region_at(rp.global_position) != reg:
			continue
		var at := world_to_local(rp.global_position)
		if mode == "mini":
			at = _clamp_edge(at, 6.0)
		elif not _inside(at):
			continue
		draw_circle(at, 6.0, Color(0, 0, 0, 0.8))
		draw_circle(at, 4.5, C_PARTY)
		if full:
			var n := str(Network.players.get(peer, {}).get("name", "?"))
			draw_string_outline(font, at + Vector2(8, 5), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.9))
			draw_string(font, at + Vector2(8, 5), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_PARTY)


func _draw_player(reg: String) -> void:
	var p := _player()
	if p == null or Regions.region_at(p.global_position) != reg:
		return
	var at := world_to_local(p.global_position)
	var fwd := Vector3(0, 0, -1)
	var cam = p.get("camera")
	if cam != null and is_instance_valid(cam):
		fwd = -(cam as Camera3D).global_basis.z
	var a := MapRules.heading(Vector3(fwd.x, 0, fwd.z))
	var s := 9.0 if mode == "mini" else 11.0
	var pts := PackedVector2Array([Vector2(0, -s), Vector2(s * 0.7, s * 0.75), Vector2(0, s * 0.35), Vector2(-s * 0.7, s * 0.75)])
	for i in pts.size():
		pts[i] = at + pts[i].rotated(a)
	draw_colored_polygon(pts, C_PLAYER)
	pts.append(pts[0])
	draw_polyline(pts, Color(0.1, 0.07, 0.03), 2.0)
