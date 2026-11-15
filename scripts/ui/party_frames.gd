class_name PartyFrames
extends VBoxContainer
## Quadros do grupo na HUD (multiplayer, abaixo da placa do personagem): nome, nível, vida e mana de cada
## companheiro, os buffs de comida ativos (ícone e segundos restantes, piscando nos últimos 5 s), coroa no
## líder e um aviso quando ele está longe do combate (o abate não conta na missão dele), caído ou carregando.
## Embaixo, o convite recebido: [Y] aceitar · [N] recusar (as teclas funcionam com o mouse preso na câmera;
## enquanto o convite da Horda está aberto, Y/N ficam com ele).

const W := 210.0
const BUFF_ICON := 20.0

## Jogador local (para medir a distância até os companheiros).
var player: Node3D
var _rows := VBoxContainer.new()
var _title: Label
var _invite: PanelContainer
var _invite_text: Label
## peer -> {"bar", "mp", "tag", "buffs" (HBox), "chips" ({comida: [painel, rótulo]}), "info"}
var _bars := {}
var _t := 0.0
var _key := "-"


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = UITheme.outlined("", 13, UITheme.GOLD, 4)
	add_child(_title)
	_rows.add_theme_constant_override("separation", 4)
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rows)
	_invite = PanelContainer.new()
	_invite.add_theme_stylebox_override("panel", UITheme._box(Color(0.05, 0.1, 0.06, 0.88), Color(0.45, 0.9, 0.55), 1, 6, 8, 5))
	_invite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_invite_text = UITheme.outlined("", 13, Color(0.8, 1.0, 0.85), 4)
	_invite_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_invite_text.custom_minimum_size.x = W
	_invite.add_child(_invite_text)
	add_child(_invite)
	Party.changed.connect(_rebuild)
	Party.invite_changed.connect(_refresh_invite)
	_rebuild()
	_refresh_invite()


func _rebuild() -> void:
	# o servidor manda o grupo a cada segundo: com os mesmos membros só vida, mana, buffs e zona mudam
	var key := ""
	for m in Party.members:
		key += "%d:%s:%d:%s;" % [int(m.peer), m.get("name", ""), int(m.get("level", 1)), m.get("leader", false)]
	if key == _key:
		for m in Party.members:
			if _bars.has(int(m.peer)):
				var e: Dictionary = _bars[int(m.peer)]
				e.bar.value = float(m.get("hp", 1.0))
				e.mp.value = float(m.get("mp", 1.0))
				e.info = m
		_update_tags()
		_update_buffs()
		return
	_key = key
	for c in _rows.get_children():
		c.queue_free()
	_bars.clear()
	var others := Party.others()
	_title.visible = Party.in_party()
	_title.text = "GRUPO %d/%d   [P]" % [Party.members.size(), PartyBook.MAX_MEMBERS]
	for m in Party.members:
		var peer := int(m.peer)
		if not (peer in others):
			continue
		_rows.add_child(_row(m))
	_update_tags()
	_update_buffs()


func _row(m: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme._box(Color(0.04, 0.035, 0.03, 0.72), Color(0.3, 0.26, 0.18), 1, 5, 7, 3))
	p.custom_minimum_size.x = W
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 5)
	v.add_child(top)
	if bool(m.get("leader", false)):
		top.add_child(UITheme.outlined("♛", 13, UITheme.GOLD, 3))
	top.add_child(UITheme.outlined(str(m.get("name", "?")), 14, Color(0.6, 0.95, 0.7), 4))
	top.add_child(UITheme.spacer())
	top.add_child(UITheme.outlined("Nv %d" % int(m.get("level", 1)), 12, UITheme.DIM, 3))
	var bar := _bar(UITheme.HP, 7, float(m.get("hp", 1.0)))
	v.add_child(bar)
	var mp := _bar(UITheme.MP, 4, float(m.get("mp", 1.0)))
	v.add_child(mp)
	var buffs := HBoxContainer.new()
	buffs.add_theme_constant_override("separation", 4)
	v.add_child(buffs)
	var tag := UITheme.outlined("", 11, Color(1.0, 0.75, 0.45), 3)
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.custom_minimum_size.x = W - 14
	v.add_child(tag)
	_bars[int(m.peer)] = {"bar": bar, "mp": mp, "tag": tag, "buffs": buffs, "chips": {}, "info": m}
	_ignore_all(p)
	return p


func _bar(c: Color, h: float, value: float) -> ProgressBar:
	var b := UITheme.bar(c, W - 14, h)
	b.max_value = 1.0
	b.step = 0.001
	b.value = value
	return b


func _ignore_all(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_all(c)


## Ícones dos buffs de comida de cada companheiro: cria/remove quando a lista muda; o tempo conta aqui.
func _update_buffs() -> void:
	for peer in _bars:
		var e: Dictionary = _bars[peer]
		var m: Dictionary = e.info
		var want: Dictionary = m.get("buffs", {})
		var chips: Dictionary = e.chips
		for id in chips.keys():
			if not want.has(id) or Party.buff_left(m, id) <= 0.0:
				chips[id][0].queue_free()
				chips.erase(id)
		for id in want:
			var left := Party.buff_left(m, id)
			if left <= 0.0:
				continue
			if not chips.has(id):
				chips[id] = _chip(id)
				e.buffs.add_child(chips[id][0])
			var lbl: Label = chips[id][1]
			lbl.text = "%dm" % int(ceil(left / 60.0)) if left >= 100.0 else "%ds" % int(ceil(left))
			chips[id][0].modulate.a = 0.45 + 0.55 * absf(sin(left * 6.0)) if left < 5.0 else 1.0
		e.buffs.visible = not chips.is_empty()


## Ícone da comida (o mesmo da barra de ações) com o tempo ao lado, na cor da comida.
func _chip(id: String) -> Array:
	var it := ItemDB.get_item(id)
	var c: Color = it.get("color", UITheme.GOLD)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme._box(Color(0.05, 0.04, 0.03, 0.7), c.darkened(0.3), 1, 7, 3, 0))
	p.tooltip_text = str(it.get("name", id))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 2)
	p.add_child(hb)
	var icon := ItemSlot.new(BUFF_ICON)
	icon.item_id = id
	hb.add_child(icon)
	var l := UITheme.outlined("", 11, c.lightened(0.25), 3)
	hb.add_child(l)
	_ignore_all(p)
	return [p, l]


## Aviso de cada companheiro: caído, em outra zona, longe do combate ou nada.
func _update_tags() -> void:
	var my_zone := Network.zone_of(multiplayer.get_unique_id()) if Network.is_online() else ""
	for peer in _bars:
		var e: Dictionary = _bars[peer]
		var m: Dictionary = e.info
		var tag: Label = e.tag
		var text := ""
		var zone := str(m.get("zone", ""))
		if zone != my_zone:
			text = "carregando" if zone == "loading" else "em outro lugar"
		elif float(m.get("hp", 1.0)) <= 0.0:
			text = "caído"
		else:
			var rp = Network.remote_players.get(peer)
			if player != null and rp != null and is_instance_valid(rp):
				var d: Vector3 = (rp as Node3D).global_position - player.global_position
				if Vector2(d.x, d.z).length() > PartyRules.SHARE_RANGE:
					text = "longe (%d m): abates não contam na missão" % int(Vector2(d.x, d.z).length())
		tag.text = text
		tag.visible = text != ""


func _refresh_invite() -> void:
	_invite.visible = not Party.invite.is_empty()
	if _invite.visible:
		_invite_text.text = "%s convida você para o grupo\n[Y] aceitar   ·   [N] recusar" % Party.invite.get("name", "?")


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.25
	_update_tags()
	_update_buffs()


func _unhandled_input(event: InputEvent) -> void:
	if Party.invite.is_empty() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if Network.horde_invite_pending() or Network.in_horde_lobby():
		return   # Y/N respondem o convite da Horda primeiro
	match event.physical_keycode:
		KEY_Y:
			get_viewport().set_input_as_handled()
			Party.answer_invite(true)
		KEY_N:
			get_viewport().set_input_as_handled()
			Party.answer_invite(false)
