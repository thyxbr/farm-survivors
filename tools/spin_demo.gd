extends Node
## Demonstração do Ciclone de Aço (montante, tecla 1) dentro do jogo, num personagem descartável
## (user://demo_solo.json, apagado a cada vez: não mexe no save solo).
##   godot --path . res://scenes/world.tscn -- --weapon=iron_zweihander --spindemo --nointro
## Leva o herói para um descampado fora da vila e põe goblins em volta dele, dentro do alcance do giro, e alguns mais
## longe (fora dele), parados como bonecos de treino.
##   1  usa a habilidade   T  nova leva de goblins   L  câmera lenta (liga/desliga)
## `--auto`: usa a habilidade sozinha, conta os cortes e fecha. `--nomobs`: sem goblins (para ver a pose). `--shotdir=<pasta>`: salva quadros da tela
## (início, aceleração, giro, desaceleração, fim) nessa pasta.

const SPOT := Vector3(-105, 0.3, 40)
const ID := "sword_spin"

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
	Econ.test_force_level(maxi(Game.level, maxi(int(ItemDB.ABILITIES[ID].level), CharRules.item_level(Balance.tables, want))))
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
	_player.use_slot(1)
	var started: bool = _player.ability == ID
	var skill = _player.ability_data.get("skill")
	var d := GreatswordSpinAbilities.durations()
	var marks := [["1_inicio", d[0] + 0.06], ["2_acelera", d[0] + d[1] * 0.6], ["3_giro", d[0] + d[1] + d[2] * 0.5],
		["4_desacelera", d[0] + d[1] + d[2] + d[3] * 0.5], ["5_fim", GreatswordSpinAbilities.total_time() - 0.05]]
	for m in marks:
		while _player.ability == ID and float(_player.ability_t) < float(m[1]):
			await get_tree().process_frame
		if dir != "":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/spin_%s.png" % [dir, m[0]])
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
	print("AUTO_OK começou=%s terminou=%s cortes=%d atingidos=%d de %d fora_atingidos=%d" % [started, _player.ability == "",
		skill.hit_count if is_instance_valid(skill) else -1, hit, _mobs.size() - 2, outside_hit])
	get_tree().quit()


## Goblins em volta do herói, dentro do alcance do giro, e dois fora dele.
func _spawn_wave() -> void:
	for e in _mobs:
		if is_instance_valid(e):
			e.queue_free()
	_mobs.clear()
	var cfg: GreatswordSpinConfig = GreatswordSpinAbilities.CONFIG
	var origin: Vector3 = _player.global_position
	var spots := []
	for i in 6:
		var a := TAU * i / 6.0 + 0.3
		spots.append(origin + Vector3(cos(a), 0.0, sin(a)) * cfg.radius * (0.55 if i % 2 == 0 else 0.85))
	spots.append(origin + Vector3(cfg.radius + 4.0, 0.0, 0.0))
	spots.append(origin + Vector3(-cfg.radius - 4.0, 0.0, 1.0))
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
	if _slow and not FXEpic._hs_active:
		Engine.time_scale = 0.3
	var alive := 0
	for e in _mobs:
		if is_instance_valid(e) and not e.dead:
			alive += 1
	var kit := Game.ability_kit()
	_label.text = "Ciclone de Aço — demonstração\n" \
		+ "[1] usar   [T] nova leva de goblins   [L] câmera lenta: %s\n" % ("LIGADA" if _slow else "desligada") \
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
