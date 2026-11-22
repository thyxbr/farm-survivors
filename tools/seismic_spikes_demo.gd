extends Node
## Demonstração das Estacas Sísmicas (habilidade 3 da montante), num personagem descartável
## (user://demo_solo.json, apagado a cada vez: não mexe no save solo).
##   godot --path . res://scenes/world.tscn -- --weapon=iron_zweihander --spikesdemo --nointro
## Sobe para o nível 5, leva o herói para um descampado fora da vila e põe goblins em volta do ponto do golpe, em
## distâncias diferentes dentro do raio (a erupção chega em cada um num momento) e dois fora dele.
##   3  usa a habilidade   T  nova leva de goblins   Y  zera a recarga   L  câmera lenta (liga/desliga)
## Com --spikesshot=<saida.png> usa a habilidade sozinho, fotografa a linha do tempo pela câmera do jogo (folha de
## contato 4 x 3) e fecha: o teste visual na cena do jogo de verdade (terreno, câmera, goblins).

const SPOT := Vector3(-105, 0.3, 40)
const CELL := Vector2i(480, 270)
const ID := "sword_spikes"

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
	await get_tree().create_timer(0.3).timeout
	if not ("--nomobs" in OS.get_cmdline_user_args()):   # --nomobs: sem goblins (para ver a pose)
		_spawn_wave()
	_ready_done = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--spikesshot="):
			_shot(a.trim_prefix("--spikesshot="))


## Usa a habilidade e fotografa a sequência (câmera do jogo), depois fecha o jogo.
func _shot(out: String) -> void:
	await get_tree().create_timer(1.5).timeout
	var cfg: SeismicSpikesConfig = SeismicSpikesAbilities.CONFIG
	var it := cfg.impact_time()
	var et := cfg.quake_time()
	var times := [cfg.windup_time * 0.5, cfg.windup_time, it + 0.03, it + cfg.crack_time * 0.5, et + 0.05, et + 0.3,
		et + 0.6, et + 0.9, cfg.pull_start() + cfg.pull_time * 0.5, cfg.pull_end() + 0.1, cfg.total_time(),
		cfg.pull_end() + cfg.fade_time + 0.4]
	var shots: Array[Image] = []
	_player.cooldowns[ID] = 0.0
	_player.cast(ID)
	var t0 := Time.get_ticks_msec()
	for at in times:
		while (Time.get_ticks_msec() - t0) / 1000.0 < float(at):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		if shots.size() in [3, 7, 8]:   # alguns quadros em tamanho cheio, para olhar de perto
			img.save_png(out.get_basename() + "_%d.png" % shots.size())
		img.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
		shots.append(img)
		var alive := _mobs.filter(func(e): return is_instance_valid(e) and not e.dead).size()
		print("SPIKESSHOT t=%.2f habilidade=%s goblins vivos=%d" % [at, _player.ability, alive])
	var sheet := Image.create(CELL.x * 4, CELL.y * 3, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, CELL), Vector2i((i % 4) * CELL.x, (i / 4) * CELL.y))
	sheet.save_png(out)
	var left := get_tree().current_scene.find_children("*", "SeismicSpikesAoE", true, false).size()
	print("SPIKESSHOT ", out, " — sobrando na cena: ", left)
	get_tree().quit()


## Goblins em volta do ponto do golpe (à frente do herói): em três distâncias dentro do raio e dois fora dele.
func _spawn_wave() -> void:
	for e in _mobs:
		if is_instance_valid(e):
			e.queue_free()
	_mobs.clear()
	var cfg: SeismicSpikesConfig = SeismicSpikesAbilities.CONFIG
	var f: Vector3 = _player.facing()
	var center: Vector3 = SeismicSpikesAbilities.impact_point(_player.global_position, atan2(f.x, f.z))
	var offs := []
	for i in 9:
		var a := TAU * i / 9.0
		offs.append(Vector3(cos(a), 0, sin(a)) * cfg.radius * [0.3, 0.6, 0.88][i % 3])
	offs.append(Vector3(cfg.radius + 4.0, 0, 0))
	offs.append(Vector3(-cfg.radius - 4.0, 0, 1.0))
	for off in offs:
		var e := Enemy.new()
		e.kind = "goblin"
		get_tree().current_scene.add_child(e)
		e.global_position = center + off
		e.home = e.global_position
		_mobs.append(e)


func _process(_delta: float) -> void:
	if not _ready_done or not is_instance_valid(_player):
		return
	Game.hp = Game.max_hp()   # o herói não morre na demonstração
	if _player.ability != ID and float(_player.cooldowns.get(ID, 0.0)) > 0.0:
		_player.cooldowns[ID] = 0.0
	if _slow and not FXEpic._hs_active:
		Engine.time_scale = 0.3
	var alive := 0
	for e in _mobs:
		if is_instance_valid(e) and not e.dead:
			alive += 1
	var kit := Game.ability_kit()
	_label.text = "Estacas Sísmicas — demonstração\n" \
		+ "[3] usar   [T] nova leva de goblins   [Y] zerar recarga   [L] câmera lenta: %s\n" % ("LIGADA" if _slow else "desligada") \
		+ "habilidade 3: %s   habilidade 5: %s\n" % [ItemDB.ABILITIES[kit[2]].name if kit.size() > 2 else "?",
			ItemDB.ABILITIES[kit[4]].name if kit.size() > 4 else "-"] \
		+ "goblins vivos: %d" % alive


func _unhandled_input(ev: InputEvent) -> void:
	if not _ready_done or not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	match ev.keycode:
		KEY_T:
			_spawn_wave()
		KEY_Y:
			_player.cooldowns[ID] = 0.0
		KEY_L:
			_slow = not _slow
			if not _slow and not FXEpic._hs_active:
				Engine.time_scale = 1.0
