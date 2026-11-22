extends CanvasLayer
## HUD em estilo ARPG, enxuto (ocupa só as bordas da tela):
## - globos de vida e mana compactos nas pontas da barra de ações, com camada "fantasma" do dano recebido;
## - barra de ações com ícones, tecla de atalho e recarga radial (World of Warcraft);
## - vigor contextual (some quando cheio), XP segmentada, mira que mostra a tensão do arco;
## - placa do personagem, rastreador de missões, avisos de saque com cor de raridade;
## - barra do chefe com rastro de dano (Dark Souls) e vinheta vermelha com vida baixa.

var player: Player
var boss: Enemy
## Texto de ajuda próprio e painel de missões escondido (cenas que não são Valdoria).
var help_text := ""
var hide_quests := false
var boss_top := 24.0

var root: Control
var hp_orb: StatOrb
var mp_orb: StatOrb
var st_bar: ProgressBar
var xp_bar: ProgressBar
var level_label: Label
var name_label: Label
var gold_label: Label
var class_label: Label
var points_chip: PanelContainer
## Pontos de talento livres ("+N talento [K]"), ao lado dos de atributo.
var talent_chip: PanelContainer
## Rank da guilda ao lado do nome (some antes do registro).
var rank_chip: PanelContainer
var season_badge: SeasonBadge
var quest_box: VBoxContainer
var notif_box: VBoxContainer
var loot_box: VBoxContainer
var prompt_box: HBoxContainer
var prompt: Label
## Coleta (F): aviso perto do veio/árvore e, batendo, a barra de progresso com a ferramenta e a maestria.
var gather_prompt: HBoxContainer
var gather_prompt_label: Label
var gather_box: VBoxContainer
var gather_title: Label
var gather_bar: ProgressBar
var gather_info: Label
var slots := {}
var _slot_ids: Array[String] = ["", "", "", "", ""]   # id da habilidade em cada slot 1..ItemDB.SLOT_COUNT
var _fury_ring: Control   # anel de fúria em volta do slot 4 (escondido quando ali não há ultimate)
var _kit_class := ""
var boss_panel: VBoxContainer
var boss_bar: GhostBar
var boss_name: Label
var help_panel: PanelContainer
var help_hint: Label
var buff_box: HBoxContainer
var crosshair: Crosshair
var vignette: TextureRect
var dock: Control
var _buff_chips := {}   # id da comida -> {"panel", "label"}
var _last_hp := -1.0
var _hurt := 0.0
var _t := 0.0
## Destino do rastreador de missões (StoryRules.destination) e a bússola que aponta para ele.
var _track_dest := {}
var _compass: CompassArrow
var _compass_label: Label
## Nome do mapa do destino quando ele fica em outro mapa (a bússola aponta a carruagem).
var _compass_far := ""
## Minimapa (só em Valdoria, ver add_minimap) e quadros do grupo (multiplayer).
const MINIMAP_SIZE := 196.0
## Largura do rastreador de missões (canto superior direito).
const QUEST_W := 330.0
var minimap: MapView
## Moldura e dica do minimapa: somem no Desafio da Horda (a arena é um mapa à parte, sem foto de cima).
var _minimap_frame: Control
var _minimap_hint: Label
## Região com nome onde o jogador está (Regions.area_at, a cada AREA_SCAN s) e a última anunciada no letreiro.
var region_banner: RegionBanner
var area_now := ""
var _area_shown := ""
var _area_scan := 0.0
const AREA_SCAN := 0.5
var party_frames: PartyFrames



func _ready() -> void:
	layer = 5
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)

	# vinheta de dano / vida baixa
	vignette = TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.05, 1.05)
	var g := Gradient.new()
	g.set_color(0, Color(0.6, 0.0, 0.0, 0.0))
	g.set_color(1, Color(0.6, 0.0, 0.0, 0.85))
	g.add_point(0.55, Color(0.6, 0, 0, 0.0))
	gt.gradient = g
	vignette.texture = gt
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.modulate.a = 0.0
	root.add_child(vignette)

	_build_plate()
	_build_quests()
	_build_feeds()
	crosshair = Crosshair.new()
	crosshair.hud = self
	_anchor(crosshair, 0.5, 0.5, -40, -40, 80, 80)
	root.add_child(crosshair)
	_build_dock()
	_build_boss()
	_build_help()
	region_banner = RegionBanner.new()
	root.add_child(region_banner)
	if Network.is_online():
		party_frames = PartyFrames.new()
		party_frames.player = player
		party_frames.position = Vector2(16, 66)
		root.add_child(party_frames)

	Game.notify.connect(_on_notify)
	Game.item_looted.connect(_on_loot)
	Game.stats_changed.connect(_refresh_static)
	Game.stats_changed.connect(_check_prog_notice)
	Game.inventory_changed.connect(_refresh_static)
	Game.kit_changed.connect(_refresh_kit)
	Game.quests_changed.connect(_refresh_quests)
	Game.quests_changed.connect(_refresh_static)
	Game.inventory_changed.connect(_refresh_quests)   # coleta: o progresso vem da mochila
	_refresh_static()
	_refresh_quests()
	_check_prog_notice()


## Minimapa no canto superior direito (Valdoria); a estação e as missões descem para baixo dele.
func add_minimap(world: Node, capture: MapCapture) -> void:
	if minimap != null:
		return
	var frame := PanelContainer.new()
	# redondo: o MapView desenha o disco e a moldura; o painel só posiciona
	var round := StyleBoxEmpty.new()
	round.set_content_margin_all(3)
	frame.add_theme_stylebox_override("panel", round)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(frame, 1, 0, -MINIMAP_SIZE - 22, 12, MINIMAP_SIZE + 6, MINIMAP_SIZE + 6)
	root.add_child(frame)
	minimap = MapView.new()
	minimap.mode = "mini"
	minimap.world = world
	minimap.capture = capture
	minimap.custom_minimum_size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	frame.add_child(minimap)
	_minimap_frame = frame
	var hint := UITheme.outlined("[M] mapa", 12, Color(0.85, 0.8, 0.65, 0.85), 3)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.clip_text = true
	_anchor(hint, 1, 0, -MINIMAP_SIZE - 20, MINIMAP_SIZE + 20, MINIMAP_SIZE + 2, 16)
	root.add_child(hint)
	_minimap_hint = hint
	var below := MINIMAP_SIZE + 22.0
	season_badge.offset_top += below
	season_badge.offset_bottom += below
	quest_box.offset_top += below
	quest_box.offset_bottom += below


## Região com nome: o letreiro ao chegar numa região nova (MapRules.entered) e o nome sob o minimapa.
func _update_area() -> void:
	if player == null or Game.run_mods.active:
		return
	var table: Dictionary = Balance.tables.get_table("regions")
	area_now = Regions.area_at(player.global_position)
	if MapRules.entered(_area_shown, area_now):
		var i := Regions.area_info(table, area_now)
		var sub := "Nível %d a %d" % [i.level_min, i.level_max] if i.level_min > 0 else ""
		if i.level_min > 0 and i.level_max == i.level_min:
			sub = "Nível %d" % i.level_min
		region_banner.show_area(i.name, sub)
	if area_now != "":
		_area_shown = area_now
	if _minimap_hint != null:
		_minimap_hint.text = ("%s  [M]" % Regions.area_label(table, area_now)) if area_now != "" else "[M] mapa"


## Destino da missão rastreada no mapa atual (ou a carruagem, se ele é em outro mapa); null = nenhum.
func track_pos():
	return _track_pos()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_H:
		help_panel.visible = not help_panel.visible
		help_hint.visible = not help_panel.visible


func _anchor(c: Control, ax: float, ay: float, ox: float, oy: float, w: float, h: float) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = ox
	c.offset_top = oy
	c.offset_right = ox + w
	c.offset_bottom = oy + h


func _ignore_all(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_all(c)


# ================================================================ construção
## Placa do personagem (canto superior esquerdo): nível, nome, arma, ouro, pontos livres.
func _build_plate() -> void:
	var plate := HBoxContainer.new()
	plate.add_theme_constant_override("separation", 8)
	plate.position = Vector2(16, 14)
	root.add_child(plate)
	var badge := PanelContainer.new()
	var bs := UITheme._box(Color(0.08, 0.06, 0.04, 0.85), UITheme.GOLD_DIM, 2, 21, 0, 0)
	badge.add_theme_stylebox_override("panel", bs)
	badge.custom_minimum_size = Vector2(42, 42)
	level_label = UITheme.heading("1", 19, Color(1, 0.88, 0.5))
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(level_label)
	plate.add_child(badge)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", -2)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	name_label = UITheme.outlined("Cavaleiro", 16, UITheme.TEXT, 4)
	name_row.add_child(name_label)
	rank_chip = PanelContainer.new()
	rank_chip.add_theme_stylebox_override("panel", UITheme._box(Color(0.12, 0.2, 0.36, 0.92), Color(0.55, 0.8, 1.0), 1, 6, 6, 0))
	rank_chip.add_child(UITheme.label("D", 12, Color(0.85, 0.93, 1.0)))
	rank_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(rank_chip)
	info.add_child(name_row)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	class_label = UITheme.outlined("", 13, UITheme.GOLD, 4)
	line.add_child(class_label)
	gold_label = UITheme.outlined("", 13, Color(1, 0.85, 0.35), 4)
	line.add_child(gold_label)
	info.add_child(line)
	plate.add_child(info)
	points_chip = PanelContainer.new()
	points_chip.add_theme_stylebox_override("panel", UITheme._box(Color(1, 0.78, 0.25, 0.9), Color(1, 0.92, 0.6), 1, 8, 6, 1))
	points_chip.add_child(UITheme.label("", 12, Color(0.12, 0.08, 0.02)))
	points_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plate.add_child(points_chip)
	talent_chip = PanelContainer.new()
	talent_chip.add_theme_stylebox_override("panel", UITheme._box(Color(0.55, 0.8, 1.0, 0.9), Color(0.85, 0.95, 1.0), 1, 8, 6, 1))
	talent_chip.add_child(UITheme.label("", 12, Color(0.03, 0.08, 0.16)))
	talent_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plate.add_child(talent_chip)
	_ignore_all(plate)


## Estação e hora do jogo (superior direito) e, embaixo, o rastreador de missões.
func _build_quests() -> void:
	season_badge = SeasonBadge.new()
	_anchor(season_badge, 1, 0, -300, 14, 284, 0)
	season_badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	season_badge.offset_left = season_badge.offset_right   # largura pelo conteúdo, encostado à direita
	root.add_child(season_badge)
	quest_box = VBoxContainer.new()
	quest_box.add_theme_constant_override("separation", 2)
	_anchor(quest_box, 1, 0, -QUEST_W - 16, 72, QUEST_W, 0)
	quest_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	quest_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(quest_box)


func _build_feeds() -> void:
	notif_box = VBoxContainer.new()
	notif_box.add_theme_constant_override("separation", 4)
	_anchor(notif_box, 0, 0.5, 16, -60, 440, 0)
	notif_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(notif_box)
	loot_box = VBoxContainer.new()
	loot_box.add_theme_constant_override("separation", 4)
	loot_box.alignment = BoxContainer.ALIGNMENT_END
	_anchor(loot_box, 1, 0.5, -300, -20, 284, 0)
	loot_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(loot_box)


## Doca inferior: globo de vida · vigor / barra de ações / XP · globo de mana.
func _build_dock() -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	hp_orb = StatOrb.new(78)
	hp_orb.color = UITheme.HP
	hp_orb.low_warning = true
	h.add_child(hp_orb)
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 3)
	mid.alignment = BoxContainer.ALIGNMENT_END
	h.add_child(mid)
	mp_orb = StatOrb.new(78)
	mp_orb.color = UITheme.MP
	h.add_child(mp_orb)

	st_bar = UITheme.bar(UITheme.STAMINA, 100, 3)
	st_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(st_bar)
	var plate := PanelContainer.new()
	# folga em cima e embaixo para os selos de tecla e de texto, que ficam para fora dos espaços
	var plate_sb := UITheme._box(Color(0.04, 0.035, 0.03, 0.55), Color(0, 0, 0, 0), 0, 6, 8, 10)
	plate_sb.content_margin_bottom = 12
	plate.add_theme_stylebox_override("panel", plate_sb)
	mid.add_child(plate)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 7)
	plate.add_child(bar)
	# o ataque básico (clique esquerdo) continua igual, só não ocupa a barra: o espaço fica escondido (o resto do HUD
	# ainda o atualiza) e a barra começa nas habilidades 1..5
	slots["attack"] = _action(bar, "M1")
	slots["attack"].visible = false
	for n in range(1, ItemDB.SLOT_COUNT + 1):
		slots["slot_%d" % n] = _action(bar, str(n))
	var ring := FuryRing.new()   # anel de fúria em volta do slot da ultimate, um pouco para fora do slot
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring.offset_left = -4
	ring.offset_top = -4
	ring.offset_right = 4
	ring.offset_bottom = 4
	slots["slot_4"].add_child(ring)
	_fury_ring = ring
	_refresh_kit()
	_gap(bar)
	slots["health_potion"] = _action(bar, "R")
	slots["mana_potion"] = _action(bar, "F")
	slots["food"] = _action(bar, "Q")
	xp_bar = UITheme.bar(UITheme.XP, 100, 4)
	xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ticks := XPTicks.new()
	ticks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	xp_bar.add_child(ticks)
	mid.add_child(xp_bar)
	_ignore_all(h)
	var w := h.get_combined_minimum_size().x
	var hh := h.get_combined_minimum_size().y
	_anchor(h, 0.5, 1, -w / 2.0, -hh - 8, w, hh)
	root.add_child(h)
	dock = h

	# bônus de comida ativos e prompt de interação (acima da doca)
	buff_box = HBoxContainer.new()
	buff_box.add_theme_constant_override("separation", 5)
	buff_box.alignment = BoxContainer.ALIGNMENT_CENTER
	buff_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(buff_box, 0.5, 1, -450, -hh - 34, 900, 22)
	root.add_child(buff_box)
	prompt_box = HBoxContainer.new()
	prompt_box.add_theme_constant_override("separation", 8)
	prompt_box.alignment = BoxContainer.ALIGNMENT_CENTER
	prompt_box.add_child(UITheme.keycap("E", 13))
	prompt = UITheme.outlined("", 17, Color(1, 0.95, 0.78), 5)
	prompt_box.add_child(prompt)
	_ignore_all(prompt_box)
	_anchor(prompt_box, 0.5, 1, -350, -hh - 70, 700, 30)
	root.add_child(prompt_box)
	gather_prompt = HBoxContainer.new()
	gather_prompt.add_theme_constant_override("separation", 8)
	gather_prompt.alignment = BoxContainer.ALIGNMENT_CENTER
	gather_prompt.add_child(UITheme.keycap("F", 13))
	gather_prompt_label = UITheme.outlined("", 17, Color(1, 0.95, 0.78), 5)
	gather_prompt.add_child(gather_prompt_label)
	_ignore_all(gather_prompt)
	_anchor(gather_prompt, 0.5, 1, -350, -hh - 102, 700, 30)
	gather_prompt.visible = false
	root.add_child(gather_prompt)
	gather_box = VBoxContainer.new()
	gather_box.add_theme_constant_override("separation", 3)
	gather_box.alignment = BoxContainer.ALIGNMENT_CENTER
	gather_title = UITheme.outlined("", 16, Color(1, 0.95, 0.78), 5)
	gather_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gather_box.add_child(gather_title)
	gather_bar = UITheme.bar(Color(0.95, 0.75, 0.3), 300, 16)
	gather_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	gather_box.add_child(gather_bar)
	gather_info = UITheme.outlined("", 13, Color(0.85, 0.85, 0.8), 4)
	gather_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gather_box.add_child(gather_info)
	_ignore_all(gather_box)
	_anchor(gather_box, 0.5, 1, -200, -hh - 150, 400, 64)   # acima da doca, longe do personagem (que fica no meio)
	gather_box.visible = false
	root.add_child(gather_box)


## Aviso de F perto de um veio/árvore e a barra da coleta em andamento (GatherAction).
func _update_gather() -> void:
	var gathering: bool = player.ability == GatherAction.ID and not player.dead
	var g: Node3D = player.gather_target
	gather_prompt.visible = g != null and not gathering and not player.dead
	if gather_prompt.visible:
		var plan: Dictionary = g.gather_plan()
		gather_prompt_label.text = "%s: %s" % [g.verb(), g.item_name()] if plan.ok else plan.msg
		gather_prompt_label.add_theme_color_override("font_color",
			Color(1, 0.95, 0.78) if plan.ok else Color(1.0, 0.55, 0.45))
	gather_box.visible = gathering
	if not gathering:
		gather_bar.value = 0.0
		return
	var d: Dictionary = player.ability_data
	var node = d.get("node")
	if node == null or not is_instance_valid(node):
		return
	gather_title.text = "%s %s" % ["Cortando" if node.is_tree() else "Minerando", node.item_name()]
	# barra contínua: sobe junto com o golpe em andamento (sem número de golpes)
	gather_bar.value = lerpf(gather_bar.value, GatherAction.bar_ratio(player) * gather_bar.max_value, 0.5)
	var prof: String = node.prof
	gather_info.text = "%s · Maestria %d (+%d%%)" % [ItemDB.get_item(str(d.tool)).get("name", ""),
		Game.prof_level(prof), roundi((GatherRules.mastery_mult(Game.prof_level(prof)) - 1.0) * 100.0)]


func _action(parent: Control, key: String) -> ItemSlot:
	var s := ItemSlot.new(44)
	s.badges = true
	s.key_text = key
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(s)
	return s


func _gap(parent: Control) -> void:
	var c := Control.new()
	c.custom_minimum_size.x = 2
	parent.add_child(c)


func _build_boss() -> void:
	boss_panel = VBoxContainer.new()
	boss_panel.add_theme_constant_override("separation", 2)
	_anchor(boss_panel, 0.5, 0, -260, 24, 520, 40)
	boss_name = UITheme.outlined("Rei Goblin", 17, Color(1, 0.62, 0.45), 5)
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_panel.add_child(boss_name)
	boss_bar = GhostBar.new()
	boss_bar.custom_minimum_size = Vector2(520, 9)
	boss_panel.add_child(boss_bar)
	boss_panel.visible = false
	_ignore_all(boss_panel)
	root.add_child(boss_panel)


func _build_help() -> void:
	help_panel = PanelContainer.new()
	help_panel.add_theme_stylebox_override("panel", UITheme.frame_box(Color(0.04, 0.035, 0.03, 0.78), Color(0.3, 0.25, 0.18), 12))
	var help := UITheme.label(help_text if help_text != "" else
		"WASD mover · Shift correr · Espaço pular · Ctrl/Clique dir. esquivar (com arco: Ctrl)\n" +
		"Clique esq.: atacar — espada: combo · cajado: projéteis · arco: dir. mira e puxa, esq. atira\n" +
		"1–3 habilidades da arma · 4 ultimate (fúria cheia) · R/F poções · Q comer · T trocar\n" +
		"E interagir · I inventário · C personagem · J missões · M mapa · P grupo · O amigos\n" +
		"F5 salvar · F9 carregar · Esc pausa · H esconder ajuda", 13, UITheme.DIM)
	help_panel.add_child(help)
	help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(help_panel)
	var hs := help_panel.get_combined_minimum_size()
	# canto inferior direito; começa escondida (H mostra) para não poluir a tela
	_anchor(help_panel, 1, 1, -hs.x - 14, -hs.y - 30, hs.x, hs.y)
	help_panel.visible = false
	help_hint = UITheme.outlined("[H] ajuda", 12, Color(0.8, 0.76, 0.66, 0.55), 3)
	help_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	help_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(help_hint, 1, 1, -314, -24, 300, 18)
	root.add_child(help_hint)


# ================================================================ atualização
var _drawn := {}      # ItemSlot -> assinatura do que está desenhado (ver _redraw)


func _process(delta: float) -> void:
	_t += delta
	hp_orb.set_values(Game.hp, Game.max_hp())
	mp_orb.set_values(Game.mp, Game.max_mp())
	st_bar.max_value = Game.max_stamina()
	st_bar.value = Game.stamina
	var st_full := Game.stamina >= Game.max_stamina() - 0.5
	st_bar.modulate.a = move_toward(st_bar.modulate.a, 0.0 if st_full else 1.0, delta * 3.0)
	# no nível máximo (xp_to_next = 0) a barra fica cheia
	var xp_need := Game.xp_to_next()
	xp_bar.max_value = maxi(xp_need, 1)
	xp_bar.value = Game.xp if xp_need > 0 else 1

	# vinheta: pisca ao levar dano e pulsa com vida baixa
	if _last_hp >= 0.0 and Game.hp < _last_hp - 0.5:
		_hurt = clampf((_last_hp - Game.hp) / maxf(Game.max_hp(), 1.0) * 4.0, 0.25, 0.8)
	_last_hp = Game.hp
	_hurt = maxf(0.0, _hurt - delta * 1.6)
	var low := 0.0
	var ratio := Game.hp / maxf(Game.max_hp(), 1.0)
	if ratio < 0.25 and Game.hp > 0.0:
		low = (0.25 - ratio) * 2.4 * (0.6 + 0.4 * sin(_t * 5.0))
	vignette.modulate.a = clampf(maxf(_hurt, low), 0.0, 0.9)

	if player:
		_update_actions()
		var t := player.interact_target
		prompt_box.visible = t != null and not player.dead
		if t:
			prompt.text = t.interact_prompt()
		_update_gather()
	_update_food()
	_update_compass()
	_area_scan -= delta
	if _area_scan <= 0.0:
		_area_scan = AREA_SCAN
		_update_area()

	# Desafio da Horda: esconde as missões e desce a barra do chefe para não cobrir o HUD da horda
	var horde: bool = Game.run_mods.active
	quest_box.visible = not horde and not hide_quests
	if _minimap_frame != null:
		_minimap_frame.visible = not horde
		_minimap_hint.visible = not horde
	season_badge.visible = not horde
	boss_panel.offset_top = 76.0 if horde else boss_top
	boss_panel.offset_bottom = boss_panel.offset_top + 40.0
	# chefe de dungeon: a barra aparece ao entrar na sala, mesmo antes de ele notar o jogador
	var boss_d := INF
	if boss and is_instance_valid(boss) and player:
		boss_d = player.global_position.distance_to(boss.global_position)
	if boss_d < 40.0 and not boss.dead \
			and ((boss.state != "idle" and boss.state != "wander") or (boss.chief and boss_d < 25.0)):
		boss_panel.visible = true
		boss_bar.set_values(boss.hp, boss.max_hp)
		boss_bar.fill = Color(0.75, 0.1, 0.06) if not boss.enraged else Color(0.75, 0.1, 0.06).lerp(Color(1, 0.35, 0.1), 0.5 + 0.5 * sin(_t * 8.0))
		boss_name.text = boss.display_name + ("  —  ENFURECIDO" if boss.enraged else "")
	else:
		boss_panel.visible = false


func _update_actions() -> void:
	var a: ItemSlot = slots.attack
	if a.item_id != Game.equipment.weapon:
		a.set_state(Game.equipment.weapon)
	a.cooldown = 0.0
	a.cooldown_text = ""
	if player.drawing:
		a.cooldown = 1.0 - player.bow_charge()
	_redraw(a)
	if _kit_class != Game.weapon_class():   # carregar jogo troca a arma sem passar pelo equipar
		_refresh_kit()
	for n in range(1, ItemDB.SLOT_COUNT + 1):
		var s: ItemSlot = slots["slot_%d" % n]
		var id: String = _slot_ids[n - 1]
		if id == "":
			continue
		var sp: Dictionary = ItemDB.ABILITIES[id]
		var cd: float = player.cooldowns[id]
		s.border_override = Color(1.0, 0.7, 0.25) if sp.ultimate else Color(0.6, 0.45, 1.0)
		if not Game.knows_ability(id):
			s.dim = true
			s.cooldown = 0.0
			s.cooldown_text = ""
			s.info_text = "Nv %d" % sp.level
		else:
			s.dim = sp.cost > 0 and Game.mp < sp.cost
			s.cooldown = clampf(cd / maxf(ItemDB.cooldown_of(id) * Game.cooldown_mult(), 0.01), 0.0, 1.0)
			s.cooldown_text = ("%.1f" % cd) if cd > 0.0 else ""
			s.info_text = "" if cd > 0.0 or sp.cost <= 0 else "%d" % sp.cost
		_redraw(s)


## Redesenha o slot só quando o que ele mostra mudou (antes eram 6 slots redesenhados a cada quadro).
func _redraw(s: ItemSlot) -> void:
	var sig := hash([s.item_id, s.icon_kind, s.ghost_kind, s.qty, s.info_text, s.cooldown, s.cooldown_text, s.dim, s.border_override])
	if _drawn.get(s) != sig:
		_drawn[s] = sig
		s.queue_redraw()


## Monta os ícones dos slots a partir do kit da arma equipada. Os slots 1-4 aparecem sempre; o 5 (Julgamento de
## Luz do cetro, Grito do Bastião da espada com escudo, Fúria Picante da montante) só quando o kit tem habilidade nele.
func _refresh_kit() -> void:
	_kit_class = Game.weapon_class()
	_slot_ids = ["", "", "", "", ""]
	for id in Game.ability_kit():
		_slot_ids[ItemDB.ABILITIES[id].slot - 1] = id
	for n in range(1, ItemDB.SLOT_COUNT + 1):
		var s: ItemSlot = slots["slot_%d" % n]
		var id: String = _slot_ids[n - 1]
		s.visible = n <= 4 or id != ""
		s.icon_kind = ItemDB.ABILITIES[id].icon if id != "" else ""
		s.icon_tex = ItemSlot.skill_art(id)
		s.dim = id == ""
		s.cooldown = 0.0
		s.cooldown_text = ""
		s.info_text = ""
		s.queue_redraw()
	# o anel de fúria só em volta de uma ultimate (com escudo o slot 4 é o Martelo de Energia, com recarga)
	if _fury_ring != null:
		var u4: String = _slot_ids[3]
		_fury_ring.visible = u4 == "" or bool(ItemDB.ABILITIES[u4].ultimate)
	# a tecla 5 aparece e some com o escudo (Grito do Bastião): a doca volta a ficar centrada na largura nova
	if dock != null:
		_center_dock.call_deferred()


## Recentraliza a doca inferior na largura que ela tem agora (slots que aparecem ou somem mudam a largura).
func _center_dock() -> void:
	if dock == null or not is_instance_valid(dock):
		return
	var ms := dock.get_combined_minimum_size()
	_anchor(dock, 0.5, 1, -ms.x / 2.0, -ms.y - 8, ms.x, ms.y)


func _refresh_static() -> void:
	level_label.text = str(Game.level)
	var n: String = Game.hero_name()
	name_label.text = n if n != "" else "Cavaleiro"
	class_label.text = Game.class_display_name()
	gold_label.text = "◆ ∞  ADMIN" if Game.admin_mode() else "◆ %d" % Game.gold
	rank_chip.visible = Game.quest_state("registro") == "done"
	(rank_chip.get_child(0) as Label).text = "RANK %s" % Game.rank()
	points_chip.visible = Game.stat_points > 0
	(points_chip.get_child(0) as Label).text = "+%d [C]" % Game.stat_points
	var tp := Game.talent_points() if Game.char_class != "" else 0
	talent_chip.visible = tp > 0
	(talent_chip.get_child(0) as Label).text = "+%d talento [K]" % tp
	for id in ["health_potion", "mana_potion"]:
		var c := Game.count_item(id)
		var s: ItemSlot = slots[id]
		s.set_state(id, 0)
		s.info_text = "x%d" % c
		s.dim = c <= 0
	Game.ensure_selected_food()


func _update_food() -> void:
	var f := Game.selected_food
	var s: ItemSlot = slots.food
	if s.item_id != f:
		s.set_state(f, Game.count_item(f) if f != "" else 0)
	if f == "":
		s.info_text = "T troca"
		s.ghost_kind = "bowl"
		s.dim = true
		s.cooldown = 0.0
		s.cooldown_text = ""
	else:
		s.qty = 0
		s.info_text = "x%d" % Game.count_item(f)
		s.dim = false
		s.cooldown = clampf(Game.eat_cooldown / Game.EAT_COOLDOWN, 0.0, 1.0)
		s.cooldown_text = ("%.1f" % Game.eat_cooldown) if Game.eat_cooldown > 0.0 else ""
	_redraw(s)
	# chips de bônus: cria/remove só quando a lista muda, o texto atualiza todo quadro
	for id in _buff_chips.keys():
		if not Game.buffs.has(id):
			_buff_chips[id].panel.queue_free()
			_buff_chips.erase(id)
	for id in Game.buffs:
		var row: Dictionary = ItemDB.BUFFS.get(id, {})
		var c: Color = row.get("color", UITheme.GOLD)
		if not _buff_chips.has(id):
			var p := PanelContainer.new()
			p.add_theme_stylebox_override("panel", UITheme._box(Color(0.05, 0.04, 0.03, 0.7), c.darkened(0.3), 1, 9, 6, 1))
			var hb := HBoxContainer.new()
			hb.add_theme_constant_override("separation", 4)
			hb.add_child(ItemSlot.for_buff(id, 18))
			var l := UITheme.label("", 12, c.lightened(0.2))
			hb.add_child(l)
			p.add_child(hb)
			_ignore_all(p)
			buff_box.add_child(p)
			_buff_chips[id] = {"panel": p, "label": l}
		var t: float = Game.buffs[id]
		var chip: Dictionary = _buff_chips[id]
		chip.label.text = "%ds" % int(ceil(t))
		chip.panel.modulate.a = 0.45 + 0.55 * abs(sin(t * 6.0)) if t < 5.0 else 1.0


func _refresh_quests() -> void:
	for c in quest_box.get_children():
		c.queue_free()
	_compass = null
	_compass_label = null
	var qt: Dictionary = ItemDB.QUESTS
	var counts := _quest_counts()
	var main: Array = []
	var sides: Array = []
	for id in Game.quests:
		if qt.has(id) and Game.quests[id].state != "done":
			(sides if StoryRules.is_side(qt, id) else main).append(id)
	var cur := StoryRules.current(qt, Game.quests)
	if cur != "" and StoryRules.state(Game.quests, cur) == "none" and not cur in main:
		main.append(cur)   # a próxima da história ainda não aceita: "fale com Fulano" (ou falta rank)
	var shown: Array = main + sides.slice(0, 3)
	if shown.is_empty():
		_track_dest = {}
		return
	var first := true
	var last_kind := ""
	for id in shown:
		var side_hdr: bool = StoryRules.is_side(qt, id)
		if ("side" if side_hdr else "main") != last_kind:
			last_kind = "side" if side_hdr else "main"
			var hdr := UITheme.outlined("CONTRATOS" if side_hdr else "HISTÓRIA", 14,
				Color(0.45, 0.65, 0.85) if side_hdr else UITheme.GOLD_DIM, 3)
			hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			quest_box.add_child(hdr)
		var d: Dictionary = qt[id]
		var st := StoryRules.state(Game.quests, id)
		var side: bool = StoryRules.is_side(qt, id)
		# conversa ativa já "pode entregar", mas o jogador ainda tem que ir até lá: fica dourada, como as outras
		var turn := StoryRules.turnable(qt, Game.quests, id, counts) and CharRules.quest_type(d) != "talk"
		var icon := "!" if st == "none" else ("★" if turn else "◆")
		var tint: Color = UITheme.GOOD if turn else (Color(0.6, 0.82, 1.0) if side else UITheme.GOLD)
		var title := UITheme.outlined("%s %s" % [icon, d.name], 19, tint, 5)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		quest_box.add_child(title)
		var txt := ""
		var prog := StoryRules.progress(qt, Game.quests, id, counts)
		if st == "none":
			var need := StoryRules.needs_rank(qt, id)
			if not StoryRules.rank_ge(Game.access_rank(), need):
				txt = "Exige Rank %s: faça contratos e peça promoção à Lina" % need
			else:
				txt = "Fale com %s" % StoryDialogue.NAMES.get(StoryRules.giver(qt, id), d.giver)
		elif turn:
			txt = "Volte para %s" % d.get("turn_in", d.giver)
		elif CharRules.quest_type(d) == "talk":
			txt = str(d.get("objective", "Fale com %s" % d.get("turn_in", d.giver)))
		else:
			txt = "%s: %d/%d" % [StoryRules.objective(d, Balance.tables.get_table("regions")), prog[0], prog[1]]
		var l := UITheme.outlined(txt, 16, UITheme.TEXT, 4)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = QUEST_W
		quest_box.add_child(l)
		if st == "active" and not turn and CharRules.quest_type(d) != "talk":
			var pb := UITheme.bar(Color(0.4, 0.65, 0.95) if side else UITheme.XP, 170, 4)
			pb.max_value = prog[1]
			pb.value = prog[0]
			pb.size_flags_horizontal = Control.SIZE_SHRINK_END
			quest_box.add_child(pb)
		if first:
			# bússola do objetivo: seta virada para onde ir (relativa à câmera) e a distância
			_track_dest = StoryRules.destination(qt, Game.quests, id, counts)
			if st == "none" and not StoryRules.rank_ge(Game.access_rank(), StoryRules.needs_rank(qt, id)):
				_track_dest = {"npc": "lina"}   # falta rank: a bússola leva à guilda
			var row := HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_END
			row.add_theme_constant_override("separation", 6)
			_compass_label = UITheme.outlined("", 16, UITheme.GOLD, 4)
			row.add_child(_compass_label)
			_compass = CompassArrow.new()
			_compass.custom_minimum_size = Vector2(24, 24)
			row.add_child(_compass)
			quest_box.add_child(row)
		first = false
		var gap := Control.new()
		gap.custom_minimum_size.y = 4
		quest_box.add_child(gap)
	_ignore_all(quest_box)


func _quest_counts() -> Dictionary:
	var c := {}
	for id in ItemDB.QUESTS:
		var q: Dictionary = ItemDB.QUESTS[id]
		for item in StoryRules.count_ids(q):
			c[item] = Game.count_item(item)
	return c


## Posição do destino do rastreador (NPC da história ou área da missão); null = nenhum.
func _track_pos():
	var p = _track_raw()
	if p == null or player == null:
		return p
	var here := Regions.region_at(player.global_position)
	if Regions.region_at(p) != here:
		_compass_far = Regions.display_name(Regions.region_at(p))
		return Regions.exit_point(here)
	_compass_far = ""
	return p


## Posição do destino como está (pode ser em outro mapa).
func _track_raw():
	if _track_dest.has("npc"):
		for n in get_tree().get_nodes_in_group("npc"):
			if n.npc_id == _track_dest.npc:
				return (n as Node3D).global_position
		return null
	if _track_dest.has("pos"):
		var v: Vector2 = _track_dest.pos
		return Vector3(v.x, 0, v.y)
	return null


func _update_compass() -> void:
	if _compass == null or not is_instance_valid(_compass) or player == null or player.camera == null:
		return
	var pos = _track_pos()
	_compass.visible = pos != null
	if pos == null:
		_compass_label.text = ""
		return
	var to: Vector3 = pos - player.global_position
	to.y = 0.0
	var dist := to.length()
	var cb := player.camera.global_basis
	var fwd := -cb.z
	fwd.y = 0.0
	var right := cb.x
	right.y = 0.0
	_compass.angle = atan2(to.normalized().dot(right.normalized()), to.normalized().dot(fwd.normalized()))
	_compass.near = dist < 4.0
	if _compass_far != "":
		var via := "saída" if Regions.is_dungeon(Regions.region_at(player.global_position)) else "carruagem"
		_compass_label.text = "%s → %s · %d m" % [via, _compass_far, int(dist)]
	else:
		_compass_label.text = "aqui" if dist < 4.0 else "%d m" % int(dist)


## Personagem migrado para a progressão por nível: avisa uma vez que os pontos voltaram.
func _check_prog_notice() -> void:
	if Game.take_prog_notice():
		_on_notify("Seus pontos de atributo foram devolvidos: a progressão mudou. Distribua de novo na ficha (C).", Color(1.0, 0.85, 0.3))


func _on_notify(text: String, color: Color) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme._box(Color(0.03, 0.025, 0.02, 0.45), Color(0, 0, 0, 0), 0, 4, 8, 2))
	var l := UITheme.outlined(text, 14, color, 4)
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	notif_box.add_child(p)
	while notif_box.get_child_count() > 5:
		notif_box.get_child(0).free()
	_fade_out(p, 3.5)


## Aviso de saque com ícone e nome na cor da raridade (lado direito).
func _on_loot(id: String, qty: int) -> void:
	var it := ItemDB.get_item(id)
	var p := PanelContainer.new()
	var rc := ItemDB.rarity_color(id) if ItemDB.is_equippable(id) else Color(0.85, 1.0, 0.7)
	var sb := UITheme._box(Color(0.03, 0.025, 0.02, 0.55), Color(0, 0, 0, 0), 0, 4, 6, 2)
	sb.border_width_right = 3
	sb.border_color = rc
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	var l := UITheme.outlined(it.name + ("  x%d" % qty if qty > 1 else ""), 14, rc, 4)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(l)
	var icon := ItemSlot.new(26)
	icon.item_id = id
	hb.add_child(icon)
	p.add_child(hb)
	_ignore_all(p)
	loot_box.add_child(p)
	while loot_box.get_child_count() > 5:
		loot_box.get_child(0).free()
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.15)
	_fade_out(p, 4.0)
	if ItemDB.is_equippable(id) and ItemDB.RARITY[ItemDB.rarity_of(id)].rank >= 3:
		Sfx.play("levelup", 0.0, -8.0)


func _fade_out(c: Control, after: float) -> void:
	var tw := c.create_tween()
	tw.tween_interval(after)
	tw.tween_property(c, "modulate:a", 0.0, 0.8)
	tw.tween_callback(c.queue_free)


# ================================================================ widgets
## Barra com rastro: a parte perdida fica clara por um instante e escorre devagar.
class GhostBar extends Control:
	var fill := Color(0.75, 0.1, 0.06)
	var ratio := 1.0
	var ghost := 1.0
	var _hold := 0.0

	func set_values(v: float, m: float) -> void:
		var r := clampf(v / maxf(m, 1.0), 0.0, 1.0)
		if r < ratio - 0.0005:
			_hold = 0.6
		ratio = r

	func _process(delta: float) -> void:
		_hold -= delta
		if ghost < ratio:
			ghost = ratio
		elif _hold <= 0.0:
			ghost = move_toward(ghost, ratio, delta * 0.5)
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r.grow(3), Color(0, 0, 0, 0.85))
		draw_rect(r.grow(2), UITheme.GOLD_DIM, false, 1.0)
		draw_rect(r, Color(0.08, 0.03, 0.03))
		draw_rect(Rect2(r.position, Vector2(r.size.x * ghost, r.size.y)), Color(1.0, 0.82, 0.45, 0.85))
		draw_rect(Rect2(r.position, Vector2(r.size.x * ratio, r.size.y)), fill)
		draw_rect(Rect2(r.position, Vector2(r.size.x * ratio, 2)), fill.lightened(0.35))
		# ornamentos nas pontas
		for x in [-8.0, r.size.x + 8.0]:
			var c := Vector2(x, r.size.y * 0.5)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -5), c + Vector2(4, 0), c + Vector2(0, 5), c + Vector2(-4, 0)]), UITheme.GOLD)


## Marcas a cada 10% sobre a barra de XP.
class XPTicks extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for i in range(1, 10):
			var x := size.x * i / 10.0
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0, 0, 0, 0.7), 1.0)


## Mira: ponto (espada), losango (cajado) ou anel que enche ao tensionar o arco.
class Crosshair extends Control:
	var hud: Node

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var p: Player = hud.player if hud else null
		var cls: String = p.look["class"] if p else "sword"
		var white := Color(1, 1, 1, 0.75)
		var shadow := Color(0, 0, 0, 0.6)
		match cls:
			"bow":
				var ch := p.bow_charge() if p else 0.0
				var gap := lerpf(14.0, 5.0, ch)
				for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
					draw_line(c + d * gap, c + d * (gap + 7), shadow, 3.0)
					draw_line(c + d * gap, c + d * (gap + 7), white, 1.5)
				if p and p.drawing:
					var full := ch >= 0.99
					var col := Color(1, 0.85, 0.3) if full else Color(1, 1, 1, 0.8)
					draw_arc(c, 22, 0, TAU, 40, Color(0, 0, 0, 0.45), 4.0, true)
					draw_arc(c, 22, -PI / 2, -PI / 2 + TAU * ch, 40, col, 3.0, true)
			"staff":
				var pts := PackedVector2Array([c + Vector2(0, -6), c + Vector2(6, 0), c + Vector2(0, 6), c + Vector2(-6, 0), c + Vector2(0, -6)])
				draw_polyline(pts, shadow, 3.0, true)
				draw_polyline(pts, Color(0.75, 0.85, 1.0, 0.9), 1.5, true)
			_:
				draw_circle(c, 3.0, shadow)
				draw_circle(c, 2.0, white)


## Seta da bússola do rastreador: aponta para o destino (0 = para a frente da câmera); perto dele vira um
## losango pulsando.
class CompassArrow extends Control:
	var angle := 0.0
	var near := false
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		if near:
			var r := 5.0 + sin(_t * 6.0) * 1.5
			var d := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
			draw_colored_polygon(d, UITheme.GOOD)
			return
		var pts := PackedVector2Array([Vector2(0, -9), Vector2(7, 7), Vector2(0, 3), Vector2(-7, 7)])
		var out := PackedVector2Array()
		for p in pts:
			out.append(c + p.rotated(angle))
		var shadow := PackedVector2Array()
		for p in out:
			shadow.append(p + Vector2(1, 1.5))
		draw_colored_polygon(shadow, Color(0, 0, 0, 0.6))
		draw_colored_polygon(out, UITheme.GOLD)
