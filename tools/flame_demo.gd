extends Node
## Demonstração da Canalização de Fogo (mago com cajado, tecla 1) dentro do jogo, num personagem descartável
## (user://demo_solo.json, apagado a cada vez: não mexe no save solo).
##   godot --path . res://scenes/world.tscn -- --weapon=apprentice_staff --flamedemo --nointro
## Leva o mago para um descampado fora da vila e põe goblins à frente dele, dentro da labareda (`length` da configuração), e um mais longe
## (fora dela), parados como bonecos de treino. Mana infinita na demonstração.
##   1  segura para canalizar   T  nova leva de goblins   L  câmera lenta (liga/desliga)
## `--auto`: canaliza sozinho por `--hold=<s>` (padrão 2,2), solta, conta os tiques e fecha. `--nomobs`: sem goblins.
## `--shotdir=<pasta>`: salva quadros da tela (preparo, labareda, labareda tarde, fade-out) nessa pasta.
## `--democam=graus,dist`: gira a câmera em volta do mago (ex.: 90,4: de lado).

const SPOT := Vector3(-105, 0.3, 40)
const ID := "staff_flame"

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
	var want := "apprentice_staff"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--weapon=") and ItemDB.weapon_class(a.substr(9)) == "staff":
			want = a.substr(9)
	Econ.test_force_level(maxi(Game.level, CharRules.item_level(Balance.tables, want)))
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
	var hold := 2.2
	var cam := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			dir = a.substr(10)
		elif a.begins_with("--hold="):
			hold = float(a.substr(7))
		elif a.begins_with("--democam="):
			cam = a.substr(10).split(",")
	await get_tree().create_timer(1.0).timeout
	var hp0 := {}
	for e in _mobs:
		hp0[e] = e.hp
	# o mago canaliza para onde a câmera olha agora (os goblins estão lá); --democam gira a câmera depois e trava a
	# direção dele, para filmar de lado
	_player.use_slot(1)
	if cam.size() > 0:
		_player.ability_data["lock_yaw"] = true
		_player.cam_yaw.rotation.y += deg_to_rad(float(cam[0]))
		if cam.size() > 1:
			_player.cam_dist_override = float(cam[1])
			_player._cam_dist = float(cam[1])
	var started: bool = _player.ability == ID
	var skill = _player.ability_data.get("skill")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--flamehide=") and is_instance_valid(skill):   # ex.: Smoke,Embers (para ajustar cada camada)
			for n in a.substr(12).split(","):
				var node := (skill as Node).get_node_or_null(n) as Node3D
				if node:
					node.visible = false
	var cfg: FlameChannelConfig = FlameChannelAbilities.CONFIG
	var marks := [["1_preparo", cfg.windup_time * 0.6], ["2_labareda", cfg.windup_time + 0.5], ["3_labareda", hold - 0.1]]
	for m in marks:
		while _player.ability == ID and float(_player.ability_t) < float(m[1]):
			await get_tree().process_frame
		await _shot(dir, m[0])
	var ticks: int = skill.hit_count if is_instance_valid(skill) else -1
	FlameChannelAbilities.release(_player)
	await get_tree().create_timer(cfg.fade_time * 0.4).timeout
	await _shot(dir, "4_fade")
	await get_tree().create_timer(1.2).timeout
	var hit := 0
	var outside_hit := 0
	for i in _mobs.size():
		var e = _mobs[i]
		var was_hit: bool = not is_instance_valid(e) or e.dead or e.hp < float(hp0[e])
		if i < _mobs.size() - 1:
			hit += int(was_hit)
		else:
			outside_hit += int(was_hit)
	print("AUTO_OK começou=%s terminou=%s tiques=%d atingidos=%d de %d fora_atingidos=%d cena_liberada=%s" % [started,
		_player.ability == "", ticks, hit, _mobs.size() - 1, outside_hit, not is_instance_valid(skill)])
	get_tree().quit()


func _shot(dir: String, name: String) -> void:
	if dir == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/flame_%s.png" % [dir, name])


## Goblins à frente do mago, dentro da labareda, e um depois do alcance.
func _spawn_wave() -> void:
	for e in _mobs:
		if is_instance_valid(e):
			e.queue_free()
	_mobs.clear()
	var cfg: FlameChannelConfig = FlameChannelAbilities.CONFIG
	var origin: Vector3 = _player.global_position
	var f: Vector3 = -(_player.cam_yaw as Node3D).global_basis.z
	f.y = 0.0
	f = f.normalized()
	var side := Vector3(-f.z, 0.0, f.x)
	var spots := [origin + f * 1.8, origin + f * 3.0 + side * 0.7, origin + f * 3.4 - side * 0.8, origin + f * (cfg.length - 0.3),
		origin + f * (cfg.length + 3.5)]
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
	Game.mp = Game.max_mp()
	if _slow and not FXEpic._hs_active:
		Engine.time_scale = 0.3
	var alive := 0
	for e in _mobs:
		if is_instance_valid(e) and not e.dead:
			alive += 1
	var kit := Game.ability_kit()
	_label.text = "Canalização de Fogo — demonstração\n" \
		+ "[1] segure para canalizar   [T] nova leva de goblins   [L] câmera lenta: %s\n" % ("LIGADA" if _slow else "desligada") \
		+ "habilidade 1: %s\n" % (ItemDB.ABILITIES[kit[0]].name if kit.size() > 0 else "?") \
		+ "goblins vivos: %d" % alive


func _unhandled_input(ev: InputEvent) -> void:
	if not _ready_done or not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	match ev.keycode:
		KEY_T:
			_spawn_wave()
		KEY_L:
			_slow = not _slow
			if not _slow and not FXEpic._hs_active:
				Engine.time_scale = 1.0
