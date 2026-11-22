extends Node
## Demonstração da Dança do Abismo (montante, tecla 3) dentro do jogo, num personagem descartável
## (user://demo_solo.json, apagado a cada vez: não mexe no save solo).
##   godot --path . res://scenes/world.tscn -- --weapon=iron_zweihander --darkcombodemo --nointro
## Leva o herói para um descampado fora da vila e põe goblins à frente dele, no caminho do combo (o deslize anda ~3 m),
## e dois longe dos lados (fora do alcance), parados como bonecos de treino.
##   3  usa a habilidade   T  nova leva de goblins   L  câmera lenta (liga/desliga)
## `--auto`: usa a habilidade sozinha, conta os acertos e fecha. `--nomobs`: sem goblins (para ver a pose). `--shotdir=<pasta>`:
## salva um quadro da tela a cada `--shotstep=<s>` (padrão 0,25 s) do combo nessa pasta.

const SPOT := Vector3(-105, 0.3, 40)
const ID := "sword_dark_combo"

var _player: Node
var _mobs: Array = []
var _ready_done := false
var _label: Label
var _slow := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(20, 120)
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	_label.text = "Preparando a demonstração..."
	layer.add_child(_label)
	_setup()


func _setup() -> void:
	while true:
		await get_tree().create_timer(0.5).timeout
		for p in get_tree().get_nodes_in_group("players"):
			if not p.remote:
				_player = p
		if _player != null and Game.char_class != "" and Game.equipment.get("weapon", "") != "":
			break
	await get_tree().create_timer(0.5).timeout
	var want := "iron_zweihander"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--weapon=") and ItemDB.is_two_handed(a.substr(9)):
			want = a.substr(9)
	# nível da ultimate: as quatro habilidades da montante liberadas
	Econ.test_force_level(maxi(Game.level, maxi(int(ItemDB.ABILITIES.sword_supreme.level), CharRules.item_level(Balance.tables, want))))
	if Game.equipment.get("weapon", "") != want:
		if Game.count_item(want) == 0:
			Game.add_item(want)
		Game.equip(want)
	await get_tree().create_timer(0.5).timeout
	_player.global_position = SPOT
	_player.velocity = Vector3.ZERO
	var look_f: Vector3 = -(_player.cam_yaw as Node3D).global_basis.z
	_player.model.rotation.y = atan2(look_f.x, look_f.z)
	await get_tree().create_timer(0.3).timeout
	if not ("--nomobs" in OS.get_cmdline_user_args()):
		_spawn_wave()
	_ready_done = true
	if "--auto" in OS.get_cmdline_user_args():
		_auto()


func _auto() -> void:
	var dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			dir = a.substr(10)
		elif a.begins_with("--democam="):   # graus em volta do herói, distância (ex.: 90,3.5: de lado, perto)
			var c := a.substr(10).split(",")
			_player.cam_yaw.rotation.y += deg_to_rad(float(c[0]))
			if c.size() > 1:
				_player.cam_dist_override = float(c[1])
				_player._cam_dist = float(c[1])
	await get_tree().create_timer(0.8).timeout
	var hp0 := {}
	for e in _mobs:
		hp0[e] = e.hp
	var pos0: Vector3 = _player.global_position
	_player.use_slot(3)
	var started: bool = _player.ability == ID
	var data: Dictionary = _player.ability_data
	var step := 0.25
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotstep="):
			step = float(a.substr(11))
	var marks := []
	var tt := 0.05
	while tt < GreatswordDarkComboAbilities.total_time():
		marks.append(["%02d_%.2fs" % [marks.size(), tt], tt])
		tt += step
	for m in marks:
		while _player.ability == ID and float(_player.ability_t) < float(m[1]):
			await get_tree().process_frame
		if dir != "":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/combo_%s.png" % [dir, m[0]])
	while _player.ability == ID:
		await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	var hit := 0
	var outside_hit := 0
	for i in _mobs.size():
		var e = _mobs[i]
		var was_hit: bool = not is_instance_valid(e) or e.dead or e.hp < float(hp0[e])
		if i < _mobs.size() - 2:
			hit += int(was_hit)
		else:
			outside_hit += int(was_hit)
	var moved := Vector2(_player.global_position.x - pos0.x, _player.global_position.z - pos0.z).length()
	print("AUTO_OK começou=%s terminou=%s acertos=%d atingidos=%d de %d fora_atingidos=%d andou=%.2f m" % [started,
		_player.ability == "", int(data.get("hits", 0)), hit, _mobs.size() - 2, outside_hit, moved])
	get_tree().quit()


## Goblins à frente do herói, no caminho do combo, e dois longe dos lados.
func _spawn_wave() -> void:
	for e in _mobs:
		if is_instance_valid(e):
			e.queue_free()
	_mobs.clear()
	var origin: Vector3 = _player.global_position
	var yaw: float = _player.model.rotation.y
	var f := Vector3(sin(yaw), 0.0, cos(yaw))
	var r := Vector3(f.z, 0.0, -f.x)
	var spots := []
	for i in 6:
		spots.append(origin + f * (2.2 + 1.1 * i) + r * (0.9 if i % 2 == 0 else -0.9))
	spots.append(origin + r * 9.0 + f * 3.0)
	spots.append(origin - r * 9.0 + f * 3.0)
	for p in spots:
		var e := Enemy.new()
		e.kind = "goblin"
		get_tree().current_scene.add_child(e)
		e.global_position = p
		e.home = p
		_mobs.append(e)
	await get_tree().create_timer(0.15).timeout
	for e in _mobs:
		if is_instance_valid(e):
			e.set_physics_process(false)


func _process(_delta: float) -> void:
	if not _ready_done or not is_instance_valid(_player):
		return
	Game.hp = Game.max_hp()
	Game.stamina = Game.max_stamina()
	if _player.ability != "sword_supreme":
		Game.fury = 100.0   # a Lâmina Suprema sempre pronta
	if _slow and not FXEpic._hs_active:
		Engine.time_scale = 0.3
	var alive := 0
	for e in _mobs:
		if is_instance_valid(e) and not e.dead:
			alive += 1
	var kit := Game.ability_kit()
	var names := []
	for k in kit:
		names.append(ItemDB.ABILITIES[k].name)
	_label.text = "Montante sombria — demonstração\n" \
		+ "[1] Ciclone de Aço  [2] Corte do Abismo  [3] Dança do Abismo  [4] Lâmina Suprema (fúria sempre cheia)\n" \
		+ "[R] zera as recargas   [T] nova leva de goblins   [L] câmera lenta: %s\n" % ("LIGADA" if _slow else "desligada") \
		+ "teclas: %s\n" % ", ".join(names) \
		+ "goblins vivos: %d" % alive


func _unhandled_input(ev: InputEvent) -> void:
	if not _ready_done or not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	match ev.keycode:
		KEY_T:
			_spawn_wave()
		KEY_R:
			for k in _player.cooldowns.keys():
				_player.cooldowns[k] = 0.0
		KEY_L:
			_slow = not _slow
			if not _slow and not FXEpic._hs_active:
				Engine.time_scale = 1.0
