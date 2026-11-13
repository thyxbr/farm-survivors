extends CanvasLayer
## HUD: barras de vida/mana/vigor, XP, magias, missão atual, notificações, prompt de interação e barra do chefe.

var player: Player
var boss: Enemy

var hp_bar: ProgressBar
var mp_bar: ProgressBar
var st_bar: ProgressBar
var xp_bar: ProgressBar
var hp_text: Label
var mp_text: Label
var level_label: Label
var gold_label: Label
var points_label: Label
var quest_box: VBoxContainer
var notif_box: VBoxContainer
var prompt: Label
var slots := {}
var boss_panel: Control
var boss_bar: ProgressBar
var boss_name: Label
var help_panel: PanelContainer
var buff_box: HBoxContainer
var _buff_labels := {}   # id da comida -> Label


func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)

	# --- canto superior esquerdo: status
	var status := VBoxContainer.new()
	status.position = Vector2(24, 20)
	status.add_theme_constant_override("separation", 5)
	root.add_child(status)
	var head := HBoxContainer.new()
	level_label = UITheme.label("Nv 1", 22, UITheme.GOLD)
	head.add_child(level_label)
	points_label = UITheme.label("", 16, Color(1, 0.85, 0.3))
	head.add_child(points_label)
	status.add_child(head)
	hp_bar = _stat_bar(status, Color(0.75, 0.12, 0.12), 300, 22)
	hp_text = _bar_label(hp_bar)
	mp_bar = _stat_bar(status, Color(0.18, 0.35, 0.85), 260, 16)
	mp_text = _bar_label(mp_bar, 13)
	st_bar = _stat_bar(status, Color(0.3, 0.7, 0.25), 220, 10)
	xp_bar = _stat_bar(status, Color(0.85, 0.7, 0.25), 300, 6)
	gold_label = UITheme.label("", 18, Color(1, 0.85, 0.35))
	gold_label.add_theme_constant_override("outline_size", 5)
	gold_label.add_theme_color_override("font_outline_color", Color.BLACK)
	level_label.add_theme_constant_override("outline_size", 5)
	level_label.add_theme_color_override("font_outline_color", Color.BLACK)
	status.add_child(gold_label)

	# --- missão atual (superior direito)
	quest_box = VBoxContainer.new()
	_anchor(quest_box, 1, 0, -374, 24, 350, 0)
	quest_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	quest_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(quest_box)

	# --- notificações (esquerda, meio)
	notif_box = VBoxContainer.new()
	_anchor(notif_box, 0, 0.5, 24, -60, 520, 0)
	root.add_child(notif_box)

	# --- mira
	var cross := ColorRect.new()
	cross.color = Color(1, 1, 1, 0.6)
	_anchor(cross, 0.5, 0.5, -2, -2, 4, 4)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cross)

	# --- barra de ações (inferior central)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(bottom)
	for id in ["fireball", "heal", "frost_nova"]:
		var sp: Dictionary = ItemDB.SPELLS[id]
		slots[id] = _slot(bottom, sp.key, sp.name, Color(0.55, 0.35, 0.9))
	slots["health_potion"] = _slot(bottom, "R", "Poção Vida", Color(0.8, 0.2, 0.2))
	slots["mana_potion"] = _slot(bottom, "F", "Poção Mana", Color(0.25, 0.4, 0.95))
	slots["food"] = _slot(bottom, "Q", "Comida", Color(0.95, 0.6, 0.2))
	slots.food.panel.custom_minimum_size = Vector2(132, 72)
	slots.food.title.clip_text = true
	slots.food.title.custom_minimum_size.x = 118
	var bw := bottom.get_combined_minimum_size().x
	_anchor(bottom, 0.5, 1, -bw / 2.0, -96, bw, 76)

	# bônus de comida ativos (acima da barra de ações)
	buff_box = HBoxContainer.new()
	buff_box.add_theme_constant_override("separation", 18)
	buff_box.alignment = BoxContainer.ALIGNMENT_CENTER
	buff_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(buff_box, 0.5, 1, -450, -126, 900, 26)
	root.add_child(buff_box)

	prompt = UITheme.label("", 22, Color(1, 0.95, 0.75))
	prompt.add_theme_constant_override("outline_size", 6)
	prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor(prompt, 0.5, 1, -300, -162, 600, 30)
	root.add_child(prompt)

	# --- chefe
	boss_panel = VBoxContainer.new()
	_anchor(boss_panel, 0.5, 0, -300, 24, 600, 50)
	boss_name = UITheme.label("Rei Goblin", 24, Color(1, 0.55, 0.4))
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_panel.add_child(boss_name)
	boss_bar = UITheme.bar(Color(0.7, 0.1, 0.08), 600, 18)
	boss_panel.add_child(boss_bar)
	boss_panel.visible = false
	root.add_child(boss_panel)

	# --- ajuda
	help_panel = PanelContainer.new()
	var help := UITheme.label(
		"WASD mover · Mouse câmera · Shift correr · Espaço pular\n" +
		"Clique esq. atacar (combo x3) · Clique dir./Ctrl esquivar\n" +
		"1 Bola de Fogo · 2 Cura · 3 Nova Gélida · R/F poções\n" +
		"Q comer · T trocar comida · Horta ao sul da vila\n" +
		"E interagir · I inventário · C personagem · J missões\n" +
		"F5 salvar · F9 carregar · Esc pausa · H esconder ajuda", 15, UITheme.DIM)
	help_panel.add_child(help)
	root.add_child(help_panel)
	var hs := help_panel.get_combined_minimum_size()
	_anchor(help_panel, 1, 1, -hs.x - 20, -hs.y - 20, hs.x, hs.y)

	Game.notify.connect(_on_notify)
	Game.stats_changed.connect(_refresh_static)
	Game.inventory_changed.connect(_refresh_static)
	Game.quests_changed.connect(_refresh_quests)
	_refresh_static()
	_refresh_quests()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_H:
		help_panel.visible = not help_panel.visible


func _anchor(c: Control, ax: float, ay: float, ox: float, oy: float, w: float, h: float) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = ox
	c.offset_top = oy
	c.offset_right = ox + w
	c.offset_bottom = oy + h


func _stat_bar(parent: Control, c: Color, w: float, h: float) -> ProgressBar:
	var b := UITheme.bar(c, w, h)
	parent.add_child(b)
	return b


func _bar_label(b: ProgressBar, size := 15) -> Label:
	var l := UITheme.label("", size)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	b.add_child(l)
	return l


func _slot(parent: Control, key: String, title: String, c: Color) -> Dictionary:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(92, 72)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.08, 0.85)
	sb.border_color = c
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var k := UITheme.label(key, 22, c.lightened(0.4))
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(k)
	var t := UITheme.label(title, 12)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var info := UITheme.label("", 13, UITheme.DIM)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(info)
	parent.add_child(p)
	return {"panel": p, "info": info, "title": t}


func _process(_delta: float) -> void:
	hp_bar.max_value = Game.max_hp()
	hp_bar.value = Game.hp
	hp_text.text = "%d / %d" % [int(ceil(Game.hp)), int(Game.max_hp())]
	mp_bar.max_value = Game.max_mp()
	mp_bar.value = Game.mp
	mp_text.text = "%d / %d" % [int(Game.mp), int(Game.max_mp())]
	st_bar.max_value = Game.max_stamina()
	st_bar.value = Game.stamina
	xp_bar.max_value = Game.xp_to_next()
	xp_bar.value = Game.xp

	if player:
		for id in ["fireball", "heal", "frost_nova"]:
			var sp: Dictionary = ItemDB.SPELLS[id]
			var s: Dictionary = slots[id]
			if not Game.knows_spell(id):
				s.info.text = "Nv %d" % sp.level
				s.panel.modulate = Color(1, 1, 1, 0.35)
			elif player.cooldowns[id] > 0:
				s.info.text = "%.1fs" % player.cooldowns[id]
				s.panel.modulate = Color(0.6, 0.6, 0.6)
			else:
				s.info.text = "%d MP" % sp.cost
				s.panel.modulate = Color.WHITE if Game.mp >= sp.cost else Color(0.6, 0.6, 1.0, 0.7)
		var t := player.interact_target
		prompt.text = "[E] " + t.interact_prompt() if t else ""

	_update_food()

	# Desafio da Horda: esconde as missões e desce a barra do chefe para não cobrir o HUD da horda
	var horde: bool = Game.run_mods.active
	quest_box.visible = not horde
	boss_panel.offset_top = 96.0 if horde else 24.0
	boss_panel.offset_bottom = boss_panel.offset_top + 50.0
	if boss and is_instance_valid(boss) and not boss.dead and boss.state != "idle" and boss.state != "wander" and player \
			and player.global_position.distance_to(boss.global_position) < 40.0:
		boss_panel.visible = true
		boss_bar.max_value = boss.max_hp
		boss_bar.value = boss.hp
		boss_name.text = boss.display_name + (" — ENFURECIDO" if boss.enraged else "")
	else:
		boss_panel.visible = false


func _refresh_static() -> void:
	level_label.text = "Nível %d" % Game.level
	points_label.text = "   +%d pontos (C)" % Game.stat_points if Game.stat_points > 0 else ""
	gold_label.text = "◆ %d ouro" % Game.gold
	for id in ["health_potion", "mana_potion"]:
		var n := Game.count_item(id)
		slots[id].info.text = "x%d" % n
		slots[id].panel.modulate = Color.WHITE if n > 0 else Color(1, 1, 1, 0.4)
	Game.ensure_selected_food()
	var f := Game.selected_food
	slots.food.title.text = ItemDB.get_item(f).name if f != "" else "Sem comida"


func _update_food() -> void:
	var f := Game.selected_food
	var s: Dictionary = slots.food
	if f == "":
		s.info.text = "T troca"
		s.panel.modulate = Color(1, 1, 1, 0.4)
	elif Game.eat_cooldown > 0.0:
		s.info.text = "%.1fs" % Game.eat_cooldown
		s.panel.modulate = Color(0.6, 0.6, 0.6)
	else:
		s.info.text = "x%d" % Game.count_item(f)
		s.panel.modulate = Color.WHITE
	# chips de bônus: cria/remove só quando a lista muda, o texto atualiza todo quadro
	for id in _buff_labels.keys():
		if not Game.food_buffs.has(id):
			_buff_labels[id].queue_free()
			_buff_labels.erase(id)
	for id in Game.food_buffs:
		var it := ItemDB.get_item(id)
		if not _buff_labels.has(id):
			var l := UITheme.label("", 17, it.get("color", UITheme.GOLD))
			l.add_theme_constant_override("outline_size", 6)
			l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			buff_box.add_child(l)
			_buff_labels[id] = l
		var t: float = Game.food_buffs[id]
		var lab: Label = _buff_labels[id]
		lab.text = "%s %ds" % [it.buff.name, int(ceil(t))]
		lab.modulate.a = 0.45 + 0.55 * abs(sin(t * 6.0)) if t < 5.0 else 1.0


func _refresh_quests() -> void:
	for c in quest_box.get_children():
		c.queue_free()
	for id in Game.quests:
		var q: Dictionary = Game.quests[id]
		if q.state == "done":
			continue
		var d: Dictionary = ItemDB.QUESTS[id]
		var title := UITheme.label("◆ " + d.name, 19, UITheme.GOLD)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		quest_box.add_child(title)
		var txt := "Volte para %s" % d.giver if q.state == "ready" else "%s: %d/%d" % [_target_name(d.target), q.progress, d.count]
		var l := UITheme.label(txt, 16)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		quest_box.add_child(l)


func _target_name(t: String) -> String:
	return {"slime": "Slimes derrotados", "goblin": "Goblins derrotados", "goblin_king": "Rei Goblin derrotado"}.get(t, t)


func _on_notify(text: String, color: Color) -> void:
	var l := UITheme.label(text, 20, color)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	notif_box.add_child(l)
	while notif_box.get_child_count() > 7:
		notif_box.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(3.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)
