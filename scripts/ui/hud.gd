extends CanvasLayer
## HUD em estilo ARPG, enxuto (ocupa só as bordas da tela):
## - globos de vida e mana compactos nas pontas da barra de ações, com camada "fantasma" do dano recebido;
## - barra de ações com ícones, tecla de atalho e recarga radial (World of Warcraft);
## - vigor contextual (some quando cheio), XP segmentada, mira que mostra a tensão do arco;
## - placa do personagem, rastreador de missões, avisos de saque com cor de raridade;
## - barra do chefe com rastro de dano (Dark Souls) e vinheta vermelha com vida baixa.

var player: Player
var boss: Enemy
## Defesa da Cidade: texto de ajuda próprio e sem o painel de missões.
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
var quest_box: VBoxContainer
var notif_box: VBoxContainer
var loot_box: VBoxContainer
var prompt_box: HBoxContainer
var prompt: Label
var slots := {}
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

const SPELL_ICONS := {"fireball": "fireball", "heal": "heal", "frost_nova": "frost"}


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

	Game.notify.connect(_on_notify)
	Game.item_looted.connect(_on_loot)
	Game.stats_changed.connect(_refresh_static)
	Game.inventory_changed.connect(_refresh_static)
	Game.quests_changed.connect(_refresh_quests)
	_refresh_static()
	_refresh_quests()


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
	name_label = UITheme.outlined("Cavaleiro", 16, UITheme.TEXT, 4)
	info.add_child(name_label)
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
	_ignore_all(plate)


## Rastreador de missões (superior direito).
func _build_quests() -> void:
	quest_box = VBoxContainer.new()
	quest_box.add_theme_constant_override("separation", 2)
	_anchor(quest_box, 1, 0, -300, 16, 284, 0)
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
	slots["attack"] = _action(bar, "M1")
	_gap(bar)
	for id in ["fireball", "heal", "frost_nova"]:
		var s := _action(bar, ItemDB.SPELLS[id].key)
		s.icon_kind = SPELL_ICONS[id]
		slots[id] = s
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
		"WASD mover · Shift correr · Espaço pular · Ctrl/Clique dir. esquivar\n" +
		"Clique esq.: atacar — espada: combo · cajado: projéteis · arco: segure e solte\n" +
		"1 Bola de Fogo · 2 Cura · 3 Nova Gélida · R/F poções · Q comer · T trocar\n" +
		"E interagir · I inventário · C personagem · J missões\n" +
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
func _process(delta: float) -> void:
	_t += delta
	hp_orb.set_values(Game.hp, Game.max_hp())
	mp_orb.set_values(Game.mp, Game.max_mp())
	st_bar.max_value = Game.max_stamina()
	st_bar.value = Game.stamina
	var st_full := Game.stamina >= Game.max_stamina() - 0.5
	st_bar.modulate.a = move_toward(st_bar.modulate.a, 0.0 if st_full else 1.0, delta * 3.0)
	xp_bar.max_value = Game.xp_to_next()
	xp_bar.value = Game.xp

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
	_update_food()

	# Desafio da Horda: esconde as missões e desce a barra do chefe para não cobrir o HUD da horda
	var horde: bool = Game.run_mods.active
	quest_box.visible = not horde and not hide_quests
	boss_panel.offset_top = 76.0 if horde else boss_top
	boss_panel.offset_bottom = boss_panel.offset_top + 40.0
	if boss and is_instance_valid(boss) and not boss.dead and boss.state != "idle" and boss.state != "wander" and player \
			and player.global_position.distance_to(boss.global_position) < 40.0:
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
	a.queue_redraw()
	for id in ["fireball", "heal", "frost_nova"]:
		var sp: Dictionary = ItemDB.SPELLS[id]
		var s: ItemSlot = slots[id]
		var cd: float = player.cooldowns[id]
		s.border_override = Color(0.6, 0.45, 1.0)
		if not Game.knows_spell(id):
			s.dim = true
			s.cooldown = 0.0
			s.cooldown_text = ""
			s.info_text = "Nv %d" % sp.level
		else:
			s.dim = Game.mp < sp.cost
			s.cooldown = clampf(cd / maxf(sp.cooldown * Game.cooldown_mult(), 0.01), 0.0, 1.0)
			s.cooldown_text = ("%.1f" % cd) if cd > 0.0 else ""
			s.info_text = "" if cd > 0.0 else "%d" % sp.cost
		s.queue_redraw()


func _refresh_static() -> void:
	level_label.text = str(Game.level)
	var n: String = str(Game.settings.get("player_name", ""))
	name_label.text = n if n != "" else "Cavaleiro"
	var cls := Game.weapon_class()
	class_label.text = ItemDB.CLASS_NAMES[cls]
	gold_label.text = "◆ %d" % Game.gold
	points_chip.visible = Game.stat_points > 0
	(points_chip.get_child(0) as Label).text = "+%d [C]" % Game.stat_points
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
	s.queue_redraw()
	# chips de bônus: cria/remove só quando a lista muda, o texto atualiza todo quadro
	for id in _buff_chips.keys():
		if not Game.food_buffs.has(id):
			_buff_chips[id].panel.queue_free()
			_buff_chips.erase(id)
	for id in Game.food_buffs:
		var it := ItemDB.get_item(id)
		var c: Color = it.get("color", UITheme.GOLD)
		if not _buff_chips.has(id):
			var p := PanelContainer.new()
			p.add_theme_stylebox_override("panel", UITheme._box(Color(0.05, 0.04, 0.03, 0.7), c.darkened(0.3), 1, 9, 6, 1))
			var hb := HBoxContainer.new()
			hb.add_theme_constant_override("separation", 4)
			var icon := ItemSlot.new(18)
			icon.item_id = id
			hb.add_child(icon)
			var l := UITheme.label("", 12, c.lightened(0.2))
			hb.add_child(l)
			p.add_child(hb)
			_ignore_all(p)
			buff_box.add_child(p)
			_buff_chips[id] = {"panel": p, "label": l}
		var t: float = Game.food_buffs[id]
		var chip: Dictionary = _buff_chips[id]
		chip.label.text = "%ds" % int(ceil(t))
		chip.panel.modulate.a = 0.45 + 0.55 * abs(sin(t * 6.0)) if t < 5.0 else 1.0


func _refresh_quests() -> void:
	for c in quest_box.get_children():
		c.queue_free()
	var any := false
	for id in Game.quests:
		var q: Dictionary = Game.quests[id]
		if q.state == "done":
			continue
		if not any:
			var hdr := UITheme.outlined("MISSÕES", 11, UITheme.GOLD_DIM, 3)
			hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			quest_box.add_child(hdr)
			any = true
		var d: Dictionary = ItemDB.QUESTS[id]
		var title := UITheme.outlined(("★ " if q.state == "ready" else "◆ ") + d.name, 15,
			UITheme.GOOD if q.state == "ready" else UITheme.GOLD, 4)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		quest_box.add_child(title)
		var txt := "Volte para %s" % d.giver if q.state == "ready" else "%s: %d/%d" % [_target_name(d.target), q.progress, d.count]
		var l := UITheme.outlined(txt, 13, UITheme.TEXT, 3)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		quest_box.add_child(l)
		if q.state == "active":
			var pb := UITheme.bar(UITheme.XP, 140, 3)
			pb.max_value = d.count
			pb.value = q.progress
			pb.size_flags_horizontal = Control.SIZE_SHRINK_END
			quest_box.add_child(pb)
		var gap := Control.new()
		gap.custom_minimum_size.y = 4
		quest_box.add_child(gap)
	_ignore_all(quest_box)


func _target_name(t: String) -> String:
	return {"slime": "Slimes derrotados", "goblin": "Goblins derrotados", "goblin_king": "Rei Goblin derrotado"}.get(t, t)


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
