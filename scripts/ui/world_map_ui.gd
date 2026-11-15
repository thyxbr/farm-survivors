extends Control
## Livro do mapa e do grupo (BookWindow, docs/INTERFACE_GRIMORIO.md), com duas abas:
## - Mapa [M]: à esquerda a região vista de cima (MapView) com o seletor de mapas (os que a guilda ainda não
##   libera mostram o rank); à direita o nome, a legenda, os lugares e onde estão os companheiros de grupo.
## - Grupo [P]: à esquerda os membros (nível, vida, onde estão; o líder expulsa) e sair do grupo; à direita
##   o convite recebido e quem está online para convidar. No solo explica que o grupo é do multiplayer.

signal closed

const TAB_MAP := 0
const TAB_PARTY := 1
const MAP_SIDE := 548.0

var world: Node
var capture: MapCapture
## Aba aberta primeiro (TAB_MAP ou TAB_PARTY).
var start_tab := TAB_MAP
var book: BookWindow
var view: MapView
var _region := "vila"
var _map_left: VBoxContainer
var _map_right: VBoxContainer
var _party_left: VBoxContainer
var _party_right: VBoxContainer
var _region_row: HBoxContainer
var _t := 0.0
var _last_key := "-"
var _hp_bars := {}   # peer -> ProgressBar
var _where_labels := {}   # peer -> [Label, membro]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	book = BookWindow.new()
	add_child(book)
	var p3 = world.get("player") if world else null
	_region = Regions.region_at(p3.global_position) if p3 != null else "vila"
	book.add_page("Mapa", "M", "world_map", _build_map())
	book.add_page("Grupo", "P", "party", _build_party())
	book.closed.connect(_close)
	book.show_page(start_tab)
	Party.changed.connect(_refresh_party)
	Party.invite_changed.connect(_refresh_party)
	Network.players_changed.connect(_refresh_party)
	_show_region(_region)
	_refresh_party()


func _spread() -> Array:
	var spread := HBoxContainer.new()
	spread.add_theme_constant_override("separation", int(BookLayout.SPINE))
	var out: Array = [spread]
	for i in 2:
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 10)
		spread.add_child(v)
		out.append(v)
	return out


## Tira os filhos na hora (queue_free sozinho deixaria o conteúdo velho na página até o fim do quadro).
func _clear(box: Control) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _wrap(l: Label, w := 560.0) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = w
	return l


# ================================================================ mapa
func _build_map() -> Control:
	var s := _spread()
	_map_left = s[1]
	_map_right = s[2]
	_region_row = HBoxContainer.new()
	_region_row.add_theme_constant_override("separation", 6)
	_map_left.add_child(_region_row)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UITheme._box(Color(UITheme.INK.r, UITheme.INK.g, UITheme.INK.b, 0.12),
		UITheme.INK, 2, 3, 3, 3))
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_map_left.add_child(frame)
	view = MapView.new()
	view.mode = "full"
	view.world = world
	view.capture = capture
	view.custom_minimum_size = Vector2(MAP_SIDE, MAP_SIDE)
	frame.add_child(view)
	return s[0]


func _show_region(region: String) -> void:
	_region = region
	view.region = region
	_clear(_region_row)
	for id in Regions.ORDER:
		var open := Regions.unlocked(id, Game.rank())
		var short := Regions.display_name(id).get_slice(" ", 0)
		var b := UITheme.button(short if open else "%s · %s" % [short, Regions.DATA[id].rank], _show_region.bind(id), 0)
		b.custom_minimum_size = Vector2(0, 36)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		b.button_pressed = id == region
		b.disabled = not open and id != region
		b.focus_mode = Control.FOCUS_NONE
		if not open:
			b.tooltip_text = "A carruagem só vai para lá com Rank %s." % Regions.DATA[id].rank
		_region_row.add_child(b)
	_refresh_map_side()
	view.queue_redraw()


func _refresh_map_side() -> void:
	_clear(_map_right)
	_map_right.add_child(UITheme.ink(Regions.display_name(_region), 30, UITheme.INK, true))
	var here := ""
	var p3 = world.get("player") if world else null
	if p3 != null:
		here = Regions.region_at(p3.global_position)
	_map_right.add_child(UITheme.ink("Você está aqui." if here == _region else "Viagem pela carruagem da guilda.", 15, UITheme.INK_DIM))
	_map_right.add_child(UITheme.ink_section("Legenda"))
	var legend := GridContainer.new()
	legend.columns = 2
	legend.add_theme_constant_override("h_separation", 26)
	legend.add_theme_constant_override("v_separation", 4)
	legend.add_child(_legend(MapView.C_PLAYER, "você (seta na direção da câmera)"))
	legend.add_child(_legend(MapView.C_NPC, "personagens"))
	legend.add_child(_legend(MapView.C_QUEST, "missão rastreada"))
	if Network.is_online():
		legend.add_child(_legend(MapView.C_PARTY, "companheiros de grupo"))
	_map_right.add_child(legend)
	_map_right.add_child(UITheme.ink_section("Lugares"))
	for pl in MapRules.places(_region):
		_map_right.add_child(UITheme.ink("·  " + str(pl[0]), 16))
	if Network.is_online():
		_map_right.add_child(UITheme.ink_section("Grupo"))
		if not Party.in_party():
			_map_right.add_child(_wrap(UITheme.ink("Sem grupo. No mapa só aparecem os companheiros de grupo [P].", 15, UITheme.INK_DIM), 500))
		for m in Party.members:
			if int(m.peer) == multiplayer.get_unique_id():
				continue
			_map_right.add_child(UITheme.ink("%s — %s" % [m.name, _where(m)], 16))
	_map_right.add_child(UITheme.spacer())


func _legend(c: Color, text: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var dot := ColorRect.new()
	dot.color = UITheme.on_paper(c)
	dot.custom_minimum_size = Vector2(12, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(dot)
	h.add_child(UITheme.ink(text, 15))
	return h


## Onde o companheiro está, em palavras: zona, mapa e distância (e se o abate conta na missão dele).
func _where(m: Dictionary) -> String:
	var zone := str(m.get("zone", ""))
	if zone == "hub":
		return "na praça"
	if zone == "city":
		return "na Defesa da Cidade"
	var rp = Network.remote_players.get(int(m.peer))
	var p3 = world.get("player") if world else null
	if rp == null or not is_instance_valid(rp) or p3 == null:
		return "em Valdoria"
	var where := Regions.display_name(Regions.region_at(rp.global_position))
	var d: Vector3 = rp.global_position - p3.global_position
	var dist := Vector2(d.x, d.z).length()
	if dist <= PartyRules.SHARE_RANGE:
		return "%s, perto (%d m)" % [where, int(dist)]
	return "%s, longe (%d m) — abates não contam na missão" % [where, int(dist)]


# ================================================================ grupo
func _build_party() -> Control:
	var s := _spread()
	_party_left = s[1]
	_party_right = s[2]
	return s[0]


## O servidor manda o grupo a cada segundo: só refaz a página quando algo além da vida mudou (refazer
## botões debaixo do mouse a cada segundo atrapalharia o clique); a vida atualiza nas barras.
func _party_key() -> String:
	var k := "%s|%s|" % [Network.is_online(), Party.invite]
	for m in Party.members:
		k += "%d:%s:%d:%s:%s;" % [int(m.peer), m.get("name", ""), int(m.get("level", 1)), m.get("leader", false), m.get("zone", "")]
	for pid in Network.players:
		k += "%d:%s," % [int(pid), Network.zone_of(int(pid))]
	return k


func _refresh_party() -> void:
	if not is_inside_tree() or _party_left == null:
		return
	var key := _party_key()
	if key == _last_key:
		for m in Party.members:
			if _hp_bars.has(int(m.peer)):
				_hp_bars[int(m.peer)].value = float(m.get("hp", 1.0))
		return
	_last_key = key
	_hp_bars.clear()
	_where_labels.clear()
	_clear(_party_left)
	_clear(_party_right)
	_party_left.add_child(UITheme.ink("Grupo", 30, UITheme.INK, true))
	_party_left.add_child(_wrap(UITheme.ink("Quem está no grupo divide o XP dos monstros. O abate conta na missão de"
		+ " quem estiver perto do combate (até %d m)." % int(PartyRules.SHARE_RANGE), 15, UITheme.INK_DIM)))
	if not Network.is_online():
		_party_left.add_child(_wrap(UITheme.ink("O grupo é do multiplayer: entre em um servidor para jogar com outras pessoas.", 17)))
		_party_right.add_child(UITheme.spacer())
		if book.current_page() == TAB_MAP:
			_refresh_map_side()
		return
	var me := multiplayer.get_unique_id()
	_party_left.add_child(UITheme.ink_section("Membros  %d/%d" % [Party.members.size() if Party.in_party() else 1, PartyBook.MAX_MEMBERS]))
	if not Party.in_party():
		_party_left.add_child(_wrap(UITheme.ink("Você ainda não está em um grupo. Convide alguém da lista ao lado.", 16, UITheme.INK_DIM)))
	else:
		var lead := Party.am_leader()
		for m in Party.members:
			_party_left.add_child(_member_row(m, lead and int(m.peer) != me, int(m.peer) == me))
		var leave := UITheme.button("Sair do grupo", Party.request_leave, 200)
		leave.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_party_left.add_child(leave)
	_party_left.add_child(UITheme.ink_section("Pelo chat"))
	_party_left.add_child(_wrap(UITheme.ink("/grupo NOME convida  ·  /grupo sair  ·  /grupo expulsar NOME", 15, UITheme.INK_DIM)))

	if not Party.invite.is_empty():
		_party_right.add_child(UITheme.ink_section("Convite"))
		_party_right.add_child(_wrap(UITheme.ink("%s convidou você para o grupo." % Party.invite.get("name", "?"), 17), 500))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(UITheme.button("Aceitar  Y", Party.answer_invite.bind(true), 160))
		row.add_child(UITheme.button("Recusar  N", Party.answer_invite.bind(false), 160))
		_party_right.add_child(row)
	_party_right.add_child(UITheme.ink_section("Online"))
	var can_invite := not Party.in_party() or (Party.am_leader() and Party.members.size() < PartyBook.MAX_MEMBERS)
	var any := false
	for pid in Network.players:
		if int(pid) == me or Party.is_member(int(pid)):
			continue
		any = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(UITheme.ink(str(Network.players[pid].name), 18))
		row.add_child(UITheme.ink(_zone_name(Network.zone_of(int(pid))), 14, UITheme.INK_DIM))
		row.add_child(UITheme.spacer())
		if can_invite:
			row.add_child(UITheme.button("Convidar", _invite.bind(int(pid)), 130))
		_party_right.add_child(row)
	if not any:
		_party_right.add_child(UITheme.ink("Ninguém mais online agora.", 16, UITheme.INK_DIM))
	elif not can_invite:
		_party_right.add_child(_wrap(UITheme.ink("Só o líder convida (e o grupo tem no máximo %d)." % PartyBook.MAX_MEMBERS, 15, UITheme.INK_DIM), 500))
	if book.current_page() == TAB_MAP:
		_refresh_map_side()


func _member_row(m: Dictionary, can_kick: bool, mine: bool) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.ink_inset(10))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	p.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	v.add_child(top)
	var who := "%s%s" % ["♛ " if m.get("leader", false) else "", m.get("name", "?")]
	top.add_child(UITheme.ink(who, 19, UITheme.INK_RED if mine else UITheme.INK, true))
	top.add_child(UITheme.ink("Nv %d" % int(m.get("level", 1)), 15, UITheme.INK_DIM))
	top.add_child(UITheme.spacer())
	if can_kick:
		var k := UITheme.button("Expulsar", Party.request_kick.bind(int(m.peer)), 110)
		k.custom_minimum_size.y = 32
		top.add_child(k)
	var bar := UITheme.ink_bar(UITheme.HP, 300, 9)
	bar.max_value = 1.0
	bar.step = 0.001
	bar.value = float(m.get("hp", 1.0))
	v.add_child(bar)
	_hp_bars[int(m.peer)] = bar
	if not mine:
		var where := UITheme.ink(_where(m), 14, UITheme.INK_DIM)
		v.add_child(where)
		_where_labels[int(m.peer)] = [where, m]
	return p


func _zone_name(zone: String) -> String:
	match zone:
		"world": return "em Valdoria"
		"city": return "na Defesa da Cidade"
	return "na praça"


func _invite(peer: int) -> void:
	Party.request_invite(peer)
	Sfx.play("click", 0.0)


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or book == null:
		return
	_t = 1.0
	# a distância dos companheiros muda andando
	if book.current_page() == TAB_MAP:
		_refresh_map_side()
	else:
		for peer in _where_labels:
			_where_labels[peer][0].text = _where(_where_labels[peer][1])


func _close() -> void:
	closed.emit()
	queue_free()
