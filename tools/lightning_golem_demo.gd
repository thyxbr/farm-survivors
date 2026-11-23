extends Node
## Demonstração do Raio e Onda de Choque no Golem de Cristal (a pancada em área dele, `slam_fx: "lightning"`), num
## personagem descartável (user://demo_solo.json: não mexe no save solo).
##   godot --path . res://scenes/world.tscn -- --level=60 --weapon=iron_sword --nointro --hora=12 --weather=sol --golemdemo
## Leva o herói para um descampado fora da vila e põe um Golem de Cristal na frente dele, já com a pancada como
## próximo ataque. A vida do herói enche sozinha.   T  outro golem   L  câmera lenta
## Com --golemshot=<pasta> espera o golem levantar os punhos, grava os quadros da pancada pela câmera do jogo
## (use com --fixed-fps 30) e fecha: o teste visual na cena de verdade (terreno, câmera, luz do dia ou da noite).

const SPOT := Vector3(-105, 0.3, 40)
const FRAMES := 40

var _player: Node
var _golem: Enemy
var _ready_done := false
var _slow := false
var _recording := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup()


func _setup() -> void:
	while true:
		await get_tree().create_timer(0.5).timeout
		for p in get_tree().get_nodes_in_group("players"):
			if not p.remote:
				_player = p
		if _player != null and Game.char_class != "":
			break
	await get_tree().create_timer(0.5).timeout
	_player.global_position = SPOT
	_player.velocity = Vector3.ZERO
	await get_tree().create_timer(0.3).timeout
	_spawn()
	_ready_done = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--golemshot="):
			_shot(a.trim_prefix("--golemshot="))


func _spawn() -> void:
	if is_instance_valid(_golem):
		_golem.queue_free()
	_golem = Enemy.new()
	_golem.kind = "golem_cristal"
	get_tree().current_scene.add_child(_golem)
	var f: Vector3 = _player.facing()
	_golem.global_position = _player.global_position + f * 2.4
	_golem.home = _golem.global_position
	_golem.attack_count = 1   # o próximo ataque já é a pancada (a cada 2)


## Grava a pancada: espera o ataque "slam" começar e salva FRAMES quadros a partir de pouco antes do raio.
func _shot(dir: String) -> void:
	_recording = true
	DirAccess.make_dir_recursive_absolute(dir)
	var waited := 0.0
	while not (is_instance_valid(_golem) and _golem.state == "attack" and _golem.attack_kind == "slam"):
		await get_tree().process_frame
		waited += get_process_delta_time()
		if waited > 30.0:
			print("GOLEMSHOT sem pancada em 30 s (estado=%s)" % (_golem.state if is_instance_valid(_golem) else "sumiu"))
			get_tree().quit(1)
			return
	while _golem.attack_timer < _golem._hit_time() - 0.2:
		await get_tree().process_frame
	for i in FRAMES:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%03d.png" % [dir, i])
	var left := get_tree().current_scene.find_children("*", "LightningShockwaveFX", true, false).size()
	print("GOLEMSHOT ", dir, " quadros=", FRAMES, " efeitos na cena=", left, " vida do herói=", Game.hp, "/", Game.max_hp())
	get_tree().quit()


func _process(_delta: float) -> void:
	if not _ready_done:
		return
	if not _recording:
		Game.hp = Game.max_hp()   # o herói não morre na demonstração (na gravação a vida fica: mostra o dano)
	if _slow:
		Engine.time_scale = 0.3


func _unhandled_input(ev: InputEvent) -> void:
	if not _ready_done or not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	match ev.keycode:
		KEY_T:
			_spawn()
		KEY_L:
			_slow = not _slow
			if not _slow:
				Engine.time_scale = 1.0
