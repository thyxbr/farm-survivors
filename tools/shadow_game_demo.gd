extends Node
## Demonstração, na cena do jogo, dos três efeitos sombrios pintados nos monstros que os usam, com um personagem
## descartável (user://demo_solo.json: não mexe no save solo):
##   --shadowdemo=mago     Esqueleto Mago: o projétil é a Esfera Sombria (ShadowOrbFX)
##   --shadowdemo=bomba    Slime Explosivo: a explosão nova (ExplosionFX, por FXToon.blast)
##   --shadowdemo=arauto   Arauto do Abismo: Rajada de Sombras = Lâminas Rúnicas (RuneBladesFX) e Zonas de Vazio =
##                         Buraco Negro (BlackHoleFX); de longe ele dá três rajadas e depois abre as zonas
##   godot --path . res://scenes/world.tscn -- --level=60 --weapon=iron_sword --nointro --hora=12 --weather=sol --shadowdemo=arauto
## A vida do herói enche sozinha.   T  põe o monstro de novo   L  câmera lenta
## Com --shadowshot=<pasta> grava os quadros pela câmera do jogo (use com --fixed-fps 30) e fecha:
##   mago: 50 quadros a partir do disparo; arauto: 70 da primeira rajada (pasta/volley) e 120, um a cada dois, das
##   zonas (pasta/voids).

const SPOT := Vector3(-105, 0.3, 40)

var _player: Node
var _mob: Enemy
var _which := "mago"
var _ready_done := false
var _slow := false
var _recording := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shadowdemo="):
			_which = a.trim_prefix("--shadowdemo=")
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
	# recua: à frente do ponto há um pinheiro que taparia o monstro
	_player.global_position = SPOT - (_player.facing() as Vector3) * 15.0 + Vector3.UP * 1.5
	_player.velocity = Vector3.ZERO
	await get_tree().create_timer(0.8).timeout
	_spawn()
	_ready_done = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shadowshot="):
			_shot(a.trim_prefix("--shadowshot="))


func _spawn() -> void:
	if is_instance_valid(_mob):
		_mob.queue_free()
	_mob = Enemy.new()
	_mob.kind = {"arauto": "arauto_abismo", "bomba": "slime_explosivo"}.get(_which, "esqueleto_mago")
	get_tree().current_scene.add_child(_mob)
	var f: Vector3 = _player.facing()
	_mob.global_position = _player.global_position + f * (11.0 if _which == "arauto" else 8.0)
	_mob.home = _mob.global_position


func _wait_attack(kind: String, limit: float) -> bool:
	var waited := 0.0
	while not (is_instance_valid(_mob) and _mob.state == "attack" and _mob.attack_kind == kind):
		await get_tree().process_frame
		waited += get_process_delta_time()
		if waited > limit:
			print("SHADOWSHOT sem o golpe '%s' em %d s (estado=%s golpe=%s)" % [kind, int(limit),
				_mob.state if is_instance_valid(_mob) else "sumiu", _mob.attack_kind if is_instance_valid(_mob) else "-"])
			return false
	return true


func _frames(dir: String, n: int, every: int) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for i in n * every:
		await RenderingServer.frame_post_draw
		if i % every == 0:
			get_viewport().get_texture().get_image().save_png("%s/%03d.png" % [dir, i / every])


func _shot(dir: String) -> void:
	_recording = true
	var hp0: float = Game.hp
	if _which == "arauto":
		if not await _wait_attack("volley", 40.0):
			get_tree().quit(1)
			return
		await _frames(dir + "/volley", 70, 1)
		if not await _wait_attack("voids", 60.0):
			get_tree().quit(1)
			return
		await _frames(dir + "/voids", 120, 2)
	elif _which == "bomba":
		if not await _wait_attack("fuse", 40.0):
			get_tree().quit(1)
			return
		await _frames(dir, 80, 1)
	else:
		if not await _wait_attack("shoot", 40.0):
			get_tree().quit(1)
			return
		await _frames(dir, 50, 1)
	print("SHADOWSHOT ", _which, " ", dir, " vida do herói ", hp0, " -> ", Game.hp)
	get_tree().quit()


func _process(_delta: float) -> void:
	if not _ready_done:
		return
	if not _recording or Game.hp < Game.max_hp() * 0.3:
		Game.hp = Game.max_hp()
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
