extends Node
## Demonstração do Corte do Abismo (montante, tecla 2) dentro do jogo, num personagem descartável
## (user://demo_solo.json, apagado a cada vez: não mexe no save solo).
##   godot --path . res://scenes/world.tscn -- --weapon=iron_zweihander --dragdemo --nointro
## Leva o herói para um descampado fora da vila e põe goblins parados como bonecos de treino: um no fim da corrida (ela
## para nele), alguns em cima das garras e dois fora da área.
##   2  usa a habilidade   T  nova leva de goblins   L  câmera lenta (liga/desliga)
## `--auto`: usa a habilidade sozinha, conta quem levou dano e fecha. `--dragshots=<pasta>`: com --auto, salva capturas da
## tela ao longo da habilidade (folha de contato em <pasta>/drag_slash_sheet.png).

const SPOT := Vector3(-105, 0.3, 40)
const ID := "sword_drag"
const SHOT_TIMES := [0.05, 0.14, 0.28, 0.42, 0.56, 0.66, 0.72, 0.77, 0.82, 0.88, 0.95, 1.05, 1.2, 1.45, 1.7, 2.0]

var _player: Node
var _mobs: Array = []
var _ready_done := false
var _label: Label
var _slow := false
var _clock := 0.0


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


func _arg(prefix: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return ""


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
	var w := _arg("--weapon=")
	if w != "" and ItemDB.is_two_handed(w):
		want = w
	Econ.test_force_level(maxi(Game.level, maxi(int(ItemDB.ABILITIES[ID].level), CharRules.item_level(Balance.tables, want))))
	if Game.equipment.get("weapon", "") != want:
		if Game.count_item(want) == 0:
			Game.add_item(want)
		Game.equip(want)
	await get_tree().create_timer(0.5).timeout
	var spot := SPOT
	var sp := _arg("--spot=")
	if sp != "":   # --spot=x,z (outro chão: o aditivo some na neve branca)
		var v := sp.split(",")
		spot = Vector3(float(v[0]), 0.5, float(v[1]))
	_player.global_position = spot
	_player.velocity = Vector3.ZERO
	var look_f: Vector3 = -(_player.cam_yaw as Node3D).global_basis.z
	_player.model.rotation.y = atan2(look_f.x, look_f.z)
	var ang := _arg("--side=")
	if ang != "":   # câmera de lado (graus): a corrida vista de perfil
		_player.cam_yaw.rotation.y += deg_to_rad(float(ang))
	var dist := _arg("--dist=")
	if dist != "":
		_player.cam_dist_override = float(dist)
		_player._cam_dist = float(dist)
	await get_tree().create_timer(0.3).timeout
	_spawn_wave()
	_ready_done = true
	if "--auto" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.8).timeout
		var hp0 := {}
		for e in _mobs:
			hp0[e] = e.hp
		var shots := _arg("--dragshots=")
		var sm := _arg("--slowmo=")
		if sm != "":   # capturas em câmera lenta (o relógio das capturas é o do jogo)
			Engine.time_scale = float(sm)
		_player.use_slot(2)
		var started: bool = _player.ability == ID
		var imgs := []
		_clock = 0.0
		var times: Array = SHOT_TIMES
		var tl := _arg("--times=")
		if tl != "":   # --times=0.1,0.2,... (s do jogo desde o começo da habilidade)
			times = Array(tl.split(",")).map(func(x: String) -> float: return float(x))
		if shots != "":
			for st in times:
				while _clock < st:
					await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var img := get_viewport().get_texture().get_image()
				imgs.append([st, img])
		Engine.time_scale = 1.0
		await get_tree().create_timer(3.2).timeout
		var hit := 0
		for e in _mobs:
			if not is_instance_valid(e) or e.dead or e.hp < float(hp0[e]):
				hit += 1
		print("AUTO_OK começou=%s terminou=%s atingidos=%d de %d" % [started, _player.ability == "", hit, _mobs.size()])
		if shots != "":
			_sheet(imgs, shots)
		get_tree().quit()


## Folha de contato 4 x 4 com as capturas (reduzidas) e o instante de cada uma.
func _sheet(imgs: Array, dir: String) -> void:
	if imgs.is_empty():
		return
	var first: Image = imgs[0][1]
	var cw := 480
	var ch := int(cw * float(first.get_height()) / first.get_width())
	var cols := 4
	var rows := int(ceil(imgs.size() / float(cols)))
	var out := Image.create(cw * cols, ch * rows, false, Image.FORMAT_RGB8)
	for i in imgs.size():
		var im: Image = imgs[i][1]
		im.convert(Image.FORMAT_RGB8)
		im.save_png(dir.path_join("drag_%02d.png" % i))
		var sm := im.duplicate() as Image
		sm.resize(cw, ch, Image.INTERPOLATE_BILINEAR)
		out.blit_rect(sm, Rect2i(0, 0, cw, ch), Vector2i((i % cols) * cw, (i / cols) * ch))
	out.save_png(dir.path_join("drag_slash_sheet.png"))
	print("SHEET ", dir.path_join("drag_slash_sheet.png"))


## Goblins: um no fim da corrida (ela para nele), dois em cima das garras e dois fora da área.
func _spawn_wave() -> void:
	for e in _mobs:
		if is_instance_valid(e):
			e.queue_free()
	_mobs.clear()
	var cfg: DragSlashConfig = DragSlashAbilities.CONFIG
	var f: Vector3 = _player.facing()
	var side := f.cross(Vector3.UP)
	var origin: Vector3 = _player.global_position
	var stop := origin + f * (cfg.dash_distance - 0.5)
	var spots := [stop + f * (cfg.stop_distance + 0.4),
		stop + f * (cfg.claw_first + cfg.claw_step) + side * 0.3,
		stop + f * (cfg.claw_first + cfg.claw_step * 2.0) - side * 0.4,
		stop + side * 5.0, origin - f * 4.0]
	if "--nomobs" in OS.get_cmdline_user_args():
		spots = []
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
	_clock += _delta
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
	_label.text = "Corte do Abismo — demonstração\n" \
		+ "[2] usar   [Espaço/esquiva] cancela durante a corrida   [T] nova leva de goblins   [L] câmera lenta: %s\n" % ("LIGADA" if _slow else "desligada") \
		+ "habilidade 2: %s\n" % (ItemDB.ABILITIES[kit[1]].name if kit.size() > 1 else "?") \
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
