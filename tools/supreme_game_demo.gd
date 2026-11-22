extends Node
## Demonstração da Lâmina Suprema (ultimate da montante, tecla 4) dentro do jogo, num personagem descartável
## (user://demo_solo.json, apagado a cada vez: não mexe no save solo).
##   godot --path . res://scenes/world.tscn -- --weapon=eclipse_greatsword --supremedemo --nointro
## (--nointro pula a abertura do personagem novo, que trava o herói até terminar)
## Sobe para o nível 8 (a ultimate libera nele), leva o herói para um descampado fora da vila e põe goblins no ponto do golpe
## e no caminho do corte (dentro da área do golpe) e alguns mais longe (fora dela), parados como bonecos de treino.
##   4  usa a habilidade   T  nova leva de goblins   L  câmera lenta (liga/desliga)
## A fúria enche sozinha depois de cada golpe e a vida não acaba.

const SPOT := Vector3(-105, 0.3, 40)
const ID := "sword_supreme"

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
	# espera o mundo e o jogador local
	while true:
		await get_tree().create_timer(0.5).timeout
		for p in get_tree().get_nodes_in_group("players"):
			if not p.remote:
				_player = p
		if _player != null and Game.char_class != "" and Game.equipment.get("weapon", "") != "":
			break
	await get_tree().create_timer(0.5).timeout
	# a montante de --weapon= (ou a de ferro): o personagem sobe ao nível que ela pede (a Eclipse pede 44) e ao da
	# ultimate, senão o equipar do --weapon= falha e a tecla 4 continua o Turbilhão
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
	# de costas para a câmera (como andando): o golpe vai para onde a câmera olha
	var look_f: Vector3 = -(_player.cam_yaw as Node3D).global_basis.z
	_player.model.rotation.y = atan2(look_f.x, look_f.z)
	await get_tree().create_timer(0.3).timeout
	_spawn_wave()
	_ready_done = true
	# `--auto`: usa a habilidade na tecla 4 sozinha, conta quem levou dano e fecha (conferência rápida, sem o smoke test)
	if "--auto" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.6).timeout
		var hp0 := {}
		for e in _mobs:
			hp0[e] = e.hp
		_player.use_slot(4)
		var started: bool = _player.ability == ID
		await get_tree().create_timer(GreatswordSupremeAbilities.total_time() + 0.3).timeout
		var hit := 0
		for e in _mobs:
			if not is_instance_valid(e) or e.dead or e.hp < float(hp0[e]):
				hit += 1
		print("AUTO_OK começou=%s terminou=%s (habilidade \"%s\" t=%.2f de %.2f) atingidos=%d de %d" % [started, _player.ability == "",
			_player.ability, _player.ability_t, GreatswordSupremeAbilities.total_time(), hit, _mobs.size()])
		get_tree().quit()


## Goblins no ponto do golpe (à frente do herói) e no caminho do corte, e alguns fora da área.
func _spawn_wave() -> void:
	for e in _mobs:
		if is_instance_valid(e):
			e.queue_free()
	_mobs.clear()
	var cfg: GreatswordSupremeConfig = GreatswordSupremeAbilities.CONFIG
	var f: Vector3 = _player.facing()
	var side := f.cross(Vector3.UP)
	var origin: Vector3 = _player.global_position
	var center: Vector3 = origin + f * cfg.impact_distance
	var spots := []
	for i in 6:
		var a := TAU * i / 6.0
		spots.append(center + (side * cos(a) + f * sin(a)) * cfg.impact_radius * (0.35 if i % 2 == 0 else 0.75))
	spots.append(origin + f * 1.3 + side * 0.5)   # no caminho do corte
	spots.append(center + side * (cfg.impact_radius + 4.0))
	spots.append(center - side * (cfg.impact_radius + 4.0))
	for p in spots:
		var e := Enemy.new()
		e.kind = "goblin"
		get_tree().current_scene.add_child(e)
		e.global_position = p
		e.home = p
		_mobs.append(e)
	# parados no lugar, como bonecos de treino: dá para ver quem está dentro da área (o empurrão do golpe ainda mexe)
	await get_tree().create_timer(0.15).timeout
	for e in _mobs:
		if is_instance_valid(e):
			e.set_physics_process(false)


func _process(_delta: float) -> void:
	if not _ready_done or not is_instance_valid(_player):
		return
	Game.hp = Game.max_hp()   # o herói não morre na demonstração
	# fora da habilidade a fúria enche sozinha (dá para repetir logo)
	if _player.ability != ID and Game.fury < 100.0:
		Game.fury = 100.0
		Game.stats_changed.emit()
	# câmera lenta: reaplica depois que o hitstop devolve o tempo normal
	if _slow and not FXEpic._hs_active:
		Engine.time_scale = 0.3
	var alive := 0
	for e in _mobs:
		if is_instance_valid(e) and not e.dead:
			alive += 1
	var kit := Game.ability_kit()
	_label.text = "Lâmina Suprema — demonstração\n" \
		+ "[4] usar   [Espaço/esquiva] cancela durante a carga   [T] nova leva de goblins   [L] câmera lenta: %s\n" % ("LIGADA" if _slow else "desligada") \
		+ "habilidade 4: %s\n" % (ItemDB.ABILITIES[kit[3]].name if kit.size() > 3 else "?") \
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
