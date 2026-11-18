class_name CraftAnim
extends Control
## Animação do craft por cima da bancada (CraftingUI): o item aparece no centro sendo trabalhado (batidas,
## faíscas e um anel de progresso) e o desfecho só aparece quando o servidor responde: brilho na cor da
## raridade e o nome completo do que saiu, ou o item rachando com fumaça e os materiais que voltaram.
##   start(item, station)  ->  resolve(itens, falhas, devolvidos)  ->  sinal finished
## cancel() fecha sem desfecho (pedido recusado).

signal finished

enum { IDLE, WORK, RESULT }

const WORK_TIME := 1.25      # tempo mínimo "trabalhando" antes do desfecho
const HIT_EVERY := 0.36
const HOLD_TIME := 4.0       # o desfecho some sozinho depois disso
const ICON := 168.0
const VERBS := {"forge": "Forjando", "leather": "Costurando", "alchemy": "Destilando"}

var phase := IDLE
var _t := 0.0
var _item := ""
var _station := ""
var _tex: Texture2D
var _hits := 0
var _sparks: Array = []      # [{p, v, life, max, col, size}]
var _result = null           # {"items": [[id, qty]], "fails": int, "back": {id: qty}}
var _success := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)


func active() -> bool:
	return phase != IDLE


## Começa a trabalhar no item `item_id` (o que a receita promete) na estação dada.
func start(item_id: String, station: String) -> void:
	_item = item_id
	_station = station
	_tex = _icon(item_id)
	_result = null
	_sparks.clear()
	_hits = 0
	_t = 0.0
	phase = WORK
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	if station != "forge":
		Sfx.play("cook", 0.1)
	queue_redraw()


## Resposta do servidor: `items` = [[id, qtd]] que saíram; `fails` = quantas falharam; `back` = o que voltou.
func resolve(items: Array, fails: int, back: Dictionary) -> void:
	if phase == IDLE:
		return
	_result = {"items": items, "fails": fails, "back": back}


func cancel() -> void:
	if phase != IDLE:
		_end()


## Fecha o desfecho (clique ou tecla). Durante o trabalho não faz nada.
func skip() -> void:
	if phase == RESULT and _t > 0.35:
		_end()


func _end() -> void:
	phase = IDLE
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	finished.emit()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		accept_event()
		skip()


## Ícone do item base: a variante de qualidade/bônus tem o mesmo desenho, e o do base já está pronto.
func _icon(id: String) -> Texture2D:
	var bid := ItemQuality.base(id)
	var tex := ItemSlot.item_art(bid)
	return tex if tex != null else ItemIcons.icon(bid, _icon_ready.bind(bid))


## O ícone 3D (itens sem arte pintada) ficou pronto no cache.
func _icon_ready(bid: String) -> void:
	if bid == ItemQuality.base(_item) and _tex == null:
		_tex = ItemIcons.icon(bid, Callable())


func _process(delta: float) -> void:
	_t += delta
	for s in _sparks:
		s.life -= delta
		s.p += s.v * delta
		s.v.y += s.get("grav", 520.0) * delta
	_sparks = _sparks.filter(func(s: Dictionary) -> bool: return s.life > 0.0)
	if phase == WORK:
		var hits := int(_t / HIT_EVERY) + 1
		if hits > _hits:
			_hits = hits
			_hit()
		if _t >= WORK_TIME and _result != null:
			_reveal()
	elif phase == RESULT and _t >= HOLD_TIME:
		_end()
		return
	queue_redraw()


## Uma batida: som e um leque de faíscas saindo do item.
func _hit() -> void:
	if _station == "forge":
		Sfx.play("anvil", 0.12, -4.0)
	var c := size * 0.5 + Vector2(0, -30)
	var warm := _station == "forge"
	for i in 14:
		var a := _rng.randf_range(-PI, 0.0)
		var sp := _rng.randf_range(140.0, 420.0)
		var col := Color(1.0, _rng.randf_range(0.55, 0.9), 0.25) if warm else (
			Color(0.6, 1.0, 0.7) if _station == "alchemy" else Color(0.95, 0.85, 0.6))
		_sparks.append({"p": c + Vector2(_rng.randf_range(-30, 30), _rng.randf_range(-10, 30)),
			"v": Vector2(cos(a), sin(a)) * sp, "life": _rng.randf_range(0.3, 0.7), "max": 0.7, "col": col,
			"size": _rng.randf_range(1.5, 3.5)})


func _reveal() -> void:
	var items: Array = _result.items
	_success = not items.is_empty()
	phase = RESULT
	_t = 0.0
	_sparks.clear()
	var c := size * 0.5 + Vector2(0, -30)
	if _success:
		_item = str(items[0][0])
		_tex = _icon(_item)
		Sfx.play("gem", 0.05)
		Sfx.play("quest", 0.02, -3.0)
		var rc := ItemDB.rarity_color(_item)
		for i in 46:
			var a := _rng.randf_range(0.0, TAU)
			var sp := _rng.randf_range(120.0, 520.0)
			_sparks.append({"p": c, "v": Vector2(cos(a), sin(a)) * sp, "life": _rng.randf_range(0.5, 1.2), "max": 1.2,
				"col": rc.lerp(Color.WHITE, _rng.randf_range(0.2, 0.7)), "size": _rng.randf_range(2.0, 4.5), "grav": 160.0})
	else:
		Sfx.play("error", 0.02)
		Sfx.play("hit", 0.1, -5.0)
		for i in 16:   # fumaça subindo devagar
			_sparks.append({"p": c + Vector2(_rng.randf_range(-70, 70), _rng.randf_range(-20, 60)),
				"v": Vector2(_rng.randf_range(-30, 30), _rng.randf_range(-90, -30)), "life": _rng.randf_range(0.9, 1.9),
				"max": 1.9, "col": Color(0.42, 0.4, 0.4), "size": _rng.randf_range(14.0, 30.0), "grav": -20.0, "smoke": true})


# ================================================================ desenho
func _draw() -> void:
	if phase == IDLE:
		return
	var c := size * 0.5 + Vector2(0, -30)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.015, 0.01, 0.94))
	if phase == WORK:
		_draw_work(c)
	elif _success:
		_draw_success(c)
	else:
		_draw_fail(c)
	for s in _sparks:
		var k := clampf(float(s.life) / float(s.max), 0.0, 1.0)
		var col: Color = s.col
		if s.get("smoke", false):
			draw_circle(s.p, float(s.size) * (1.6 - k * 0.6), Color(col.r, col.g, col.b, 0.28 * k))
		else:
			draw_circle(s.p, float(s.size) * (0.4 + k * 0.6), Color(col.r, col.g, col.b, k))


func _draw_icon(center: Vector2, sz: float, mod: Color) -> void:
	var r := Rect2(center - Vector2(sz, sz) * 0.5, Vector2(sz, sz))
	if _tex != null:
		draw_texture_rect(_tex, r, false, mod)
	else:
		IconPainter.draw(self, IconPainter.kind_for(_item), IconPainter.color_for(_item) * mod, r.grow(-sz * 0.12))


func _draw_work(c: Vector2) -> void:
	var since := fmod(_t, HIT_EVERY)
	var punch := exp(-since * 14.0)                      # 1 na batida, some rápido
	var prog := clampf(_t / WORK_TIME, 0.0, 1.0)
	var glow := Color(1.0, 0.55, 0.15) if _station == "forge" else (
		Color(0.45, 0.95, 0.6) if _station == "alchemy" else Color(0.9, 0.75, 0.5))
	# brasa atrás do item, mais forte a cada batida
	for i in 5:
		draw_circle(c, ICON * (0.42 + i * 0.13), Color(glow.r, glow.g, glow.b, (0.06 + 0.05 * punch) * (1.0 - i / 5.0) + 0.02))
	# anel de progresso; depois de cheio gira esperando a resposta
	var rad := ICON * 0.72
	draw_arc(c, rad, 0.0, TAU, 64, Color(1, 1, 1, 0.08), 5.0, true)
	if prog < 1.0:
		draw_arc(c, rad, -PI / 2.0, -PI / 2.0 + TAU * prog, 64, glow, 5.0, true)
	else:
		var a := _t * 5.0
		draw_arc(c, rad, a, a + PI * 1.3, 48, glow, 5.0, true)
	# o item: escuro no começo, vai tomando cor; treme e achata a cada batida
	var shade := lerpf(0.22, 0.85, prog)
	var off := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 7.0 * punch
	var sz := ICON * (1.0 - 0.08 * punch)
	_draw_icon(c + off + Vector2(0, 6.0 * punch), sz, Color(shade, shade * (0.92 + 0.08 * prog), shade * (0.85 + 0.15 * prog)))
	if punch > 0.25:
		draw_circle(c + Vector2(0, 10), ICON * 0.2 * punch, Color(1, 0.95, 0.8, 0.45 * punch))
	var dots := ".".repeat(1 + int(_t * 3.0) % 3)
	_center_text("%s%s" % [VERBS.get(_station, "Fabricando"), dots], c.y + ICON * 0.72 + 44, 26, UITheme.GOLD, true)


func _draw_success(c: Vector2) -> void:
	var rc := ItemDB.rarity_color(_item)
	var inn := clampf(_t / 0.35, 0.0, 1.0)
	# raios girando na cor da raridade
	var n := 14
	for i in n:
		var a := _t * 0.5 + TAU * i / n
		var w := 0.05 if i % 2 == 0 else 0.03
		var len := ICON * ((1.7 if i % 2 == 0 else 1.25) + 0.2 * sin(_t * 3.0 + i)) * inn
		# draw_primitive não triangula: o raio de tamanho zero do primeiro quadro não dá erro
		var ray := Color(rc.r, rc.g, rc.b, 0.13)
		draw_primitive(PackedVector2Array([c, c + Vector2(cos(a - w), sin(a - w)) * len, c + Vector2(cos(a + w), sin(a + w)) * len]),
			PackedColorArray([ray, ray, ray]), PackedVector2Array())
	for i in 5:
		draw_circle(c, ICON * (0.4 + i * 0.14), Color(rc.r, rc.g, rc.b, 0.09 * (1.0 - i / 5.0) + 0.02))
	# onda de choque
	var wave := clampf(_t / 0.6, 0.0, 1.0)
	if wave < 1.0:
		draw_arc(c, ICON * (0.5 + 1.6 * wave), 0.0, TAU, 72, Color(1, 1, 1, 0.6 * (1.0 - wave)), 6.0 * (1.0 - wave) + 1.0, true)
	# o item salta e assenta
	var pop := 1.0 + 0.4 * exp(-_t * 6.0) * cos(_t * 16.0)
	_draw_icon(c + Vector2(0, sin(_t * 2.2) * 4.0), ICON * pop, Color.WHITE)
	var flash := 1.0 - clampf(_t / 0.3, 0.0, 1.0)
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.55 * flash))
	# textos
	var y := c.y + ICON * 0.72 + 40
	_center_text("Sucesso!", y, 34, UITheme.GOLD, true)
	var items: Array = _result.items
	var it := ItemDB.get_item(_item)
	y += 36
	_center_text(_qty_name(items[0]), y, 24, rc)
	if it.has("quality"):
		y += 26
		_center_text("Qualidade %s" % ItemQuality.NAMES.get(it.quality, it.quality), y, 18, Color(1, 0.9, 0.6))
	if it.has("affix"):
		y += 26
		_center_text("✦ Bônus de ofício: %s" % ItemDB.format_stat(str(it.affix_stat), float(it.affix_value)), y, 18, UITheme.GOOD)
	for i in range(1, mini(items.size(), 5)):
		y += 24
		_center_text(_qty_name(items[i]), y, 17, ItemDB.rarity_color(str(items[i][0])))
	if items.size() > 5:
		y += 22
		_center_text("e mais %d" % (items.size() - 5), y, 15, UITheme.DIM)
	if int(_result.fails) > 0:
		y += 28
		_center_text("%d falh%s · voltou: %s" % [int(_result.fails), "ou" if int(_result.fails) == 1 else "aram", _back_text()], y, 16, UITheme.BAD)
	_hint()


func _draw_fail(c: Vector2) -> void:
	var shake := exp(-_t * 7.0)
	var off := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 12.0 * shake
	var apart := clampf((_t - 0.15) / 0.7, 0.0, 1.0)
	apart = 1.0 - pow(1.0 - apart, 3.0)
	for i in 4:
		draw_circle(c, ICON * (0.45 + i * 0.15), Color(0.7, 0.12, 0.08, 0.07 * (1.0 - i / 4.0) + 0.015))
	var mod := Color(0.5, 0.36, 0.34).lerp(Color(0.28, 0.2, 0.2), apart)
	var half := ICON * 0.5
	if _tex != null:
		var ts := _tex.get_size()
		# duas metades que se afastam e tombam
		for side in [-1, 1]:
			var src := Rect2(0.0 if side < 0 else ts.x * 0.5, 0, ts.x * 0.5, ts.y)
			var pivot: Vector2 = c + off + Vector2(side * (apart * 26.0), apart * 14.0)
			draw_set_transform(pivot, side * apart * 0.22, Vector2.ONE)
			draw_texture_rect_region(_tex, Rect2(-half if side < 0 else 0.0, -half, half, ICON), src, mod)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		_draw_icon(c + off, ICON, mod)
	# rachadura no meio
	var crack := PackedVector2Array()
	var steps := 9
	for i in steps + 1:
		var k := float(i) / steps
		crack.append(c + off + Vector2((12.0 if i % 2 == 0 else -12.0) * (1.0 - absf(k - 0.5)), lerpf(-half, half, k)))
	var show := clampf(_t / 0.18, 0.0, 1.0)
	var upto := maxi(2, int(crack.size() * show))
	draw_polyline(crack.slice(0, upto), Color(1.0, 0.5, 0.3, 0.9 * (1.0 - apart * 0.6)), 3.0, true)
	var flash := 1.0 - clampf(_t / 0.25, 0.0, 1.0)
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.9, 0.15, 0.1, 0.3 * flash))
	var y := c.y + ICON * 0.72 + 40
	_center_text("Falhou!", y, 34, UITheme.BAD, true)
	y += 34
	var n := int(_result.fails)
	_center_text("O material não aguentou." if n <= 1 else "%d tentativas falharam." % n, y, 18, UITheme.TEXT)
	y += 28
	if (_result.back as Dictionary).is_empty():
		_center_text("Nada pôde ser aproveitado.", y, 16, UITheme.DIM)
	else:
		_center_text("Voltou para a mochila: %s" % _back_text(), y, 16, UITheme.GOOD)
	_hint()


func _qty_name(entry: Array) -> String:
	var n := int(entry[1])
	return "%s%s" % [ItemDB.get_item(str(entry[0])).get("name", entry[0]), " x%d" % n if n > 1 else ""]


func _back_text() -> String:
	var parts: Array[String] = []
	var back: Dictionary = _result.back
	for id in back:
		parts.append("%d %s" % [int(back[id]), ItemDB.get_item(str(id)).get("name", id)])
	return ", ".join(parts) if not parts.is_empty() else "nada"


func _hint() -> void:
	if _t > 0.8:
		_center_text("Clique para continuar", size.y - 46, 15, Color(UITheme.DIM, 0.6 + 0.4 * sin(_t * 3.0)))


func _center_text(text: String, y: float, fs: int, col: Color, serif := false) -> void:
	var font: Font = UITheme.serif() if serif else ThemeDB.fallback_font
	draw_string_outline(font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, 6, Color(0, 0, 0, 0.85))
	draw_string(font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, col)
