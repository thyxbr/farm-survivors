extends Node
## Demonstração, na cena do jogo, dos três efeitos sombrios pintados nos monstros que os usam, com um personagem
## descartável (user://demo_solo.json: não mexe no save solo):
##   --shadowdemo=mago     Esqueleto Mago: o projétil é a Esfera Sombria (ShadowOrbFX)
##   --shadowdemo=bomba    Slime Explosivo: a explosão nova (ExplosionFX, por FXToon.blast)
##   --shadowdemo=sentinela Sentinela da Nevasca: Estacas, Sopro e o urro com o gelo pintado (IceFX)
##   --shadowdemo=verme    Mãe-Verme: cuspe de ácido, Onda de Cristais, Poças de Ácido e Desmoronamento (WormFX)
##   --shadowdemo=espinheira Espinheira: Raízes, Brotos com a seiva, Garra e, na fúria, Esporos e Raízes em leque
##                         (ThornFX); grava pasta/roots, sprouts, claw, spores e roots_fury
##   --shadowdemo=arauto   Arauto do Abismo: Rajada de Sombras = Lâminas Rúnicas (RuneBladesFX) e Zonas de Vazio =
##                         Buraco Negro (BlackHoleFX); de longe ele dá três rajadas e depois abre as zonas
##   godot --path . res://scenes/world.tscn -- --level=60 --weapon=iron_sword --nointro --hora=12 --weather=sol --shadowdemo=arauto
## A vida do herói enche sozinha.   T  põe o monstro de novo   L  câmera lenta
## Com --shadowshot=<pasta> grava os quadros pela câmera do jogo (use com --fixed-fps 30) e fecha:
##   mago: 50 quadros a partir do disparo; arauto: 70 da primeira rajada (pasta/volley) e 120, um a cada dois, das
##   zonas (pasta/voids); verme: pasta/spit, pasta/quake, pasta/acid e pasta/rockfall.

const SPOT := Vector3(-105, 0.3, 40)

var _player: Node
var _mob: Enemy
var _which := "mago"
var _ready_done := false
var _slow := false
var _recording := false
var _was_burrow := false


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
	_mob.kind = {"arauto": "arauto_abismo", "bomba": "slime_explosivo", "sentinela": "sentinela_nevasca",
		"verme": "mae_verme", "espinheira": "espinheira"}.get(_which, "esqueleto_mago")
	get_tree().current_scene.add_child(_mob)
	var f: Vector3 = _player.facing()
	_mob.global_position = _player.global_position + f * (11.0 if _which in ["arauto", "sentinela"] else 13.0 if _which in ["verme", "espinheira"] else 8.0)
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
	elif _which == "sentinela":
		# de longe ela abre com as Estacas, depois o Sopro; com pouca vida, o urro da nevasca
		if not await _wait_attack("icicles", 40.0):
			get_tree().quit(1)
			return
		await _frames(dir + "/icicles", 110, 1)
		if not await _wait_attack("breath", 60.0):
			get_tree().quit(1)
			return
		await _frames(dir + "/breath", 90, 2)
		_mob.hp = _mob.max_hp * 0.2
		if await _wait_attack("blizzard", 40.0):
			await _frames(dir + "/roar", 60, 1)
	elif _which == "verme":
		# de longe: cuspe, Onda de Cristais e Poças; mergulha e, na subida seguinte, o Desmoronamento
		# os golpes vêm na ordem da luta: grava cada um na primeira vez que aparece
		var todo := {"shoot": ["spit", 45, 1], "quake": ["quake", 115, 1], "acid_rain": ["acid", 110, 2],
			"rockfall": ["rockfall", 110, 1]}
		var waited := 0.0
		while not todo.is_empty() and waited < 180.0:
			await get_tree().process_frame
			waited += get_process_delta_time()
			if is_instance_valid(_mob) and _mob.state == "attack" and todo.has(_mob.attack_kind):
				var step: Array = todo[_mob.attack_kind]
				todo.erase(_mob.attack_kind)
				await _frames(dir + "/" + step[0], step[1], step[2])
		if not todo.is_empty():
			print("SHADOWSHOT faltou ", todo.keys())
	elif _which == "espinheira":
		# Raízes de longe; depois os Brotos (o 4º golpe do ciclo), a Garra quando ela chega perto e, já na fúria,
		# os Esporos e as Raízes em leque (o contador de golpes é adiantado para não esperar os ciclos)
		if not await _wait_attack("roots", 40.0):
			get_tree().quit(1)
			return
		await _frames(dir + "/roots", 100, 1)
		_mob._thorn_n = 3
		if await _wait_attack("sprouts", 40.0):
			await _frames(dir + "/sprouts", 100, 1)
		if await _wait_attack("swing", 40.0):
			await _frames(dir + "/claw", 60, 1)
		_mob.enraged = true
		_mob._thorn_n = 7
		if await _wait_attack("spores", 40.0):
			await _frames(dir + "/spores", 90, 2)
		_player.global_position = _mob.global_position - (_mob.model_forward() as Vector3) * -14.0 + Vector3.UP * 1.0
		_player.velocity = Vector3.ZERO
		if await _wait_attack("roots", 40.0):
			await _frames(dir + "/roots_fury", 100, 1)
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
	# a Mãe-Verme sai do chão debaixo do herói e só morderia: ao sair, o herói recua para ela usar os golpes de longe
	if _which == "verme" and is_instance_valid(_mob):
		if _was_burrow and _mob.state != "burrow":
			var back: Vector3 = _mob.home - _mob.global_position
			back.y = 0.0
			back = back.normalized() if back.length() > 3.0 else -(_player.facing() as Vector3)
			_player.global_position = _mob.global_position + back * 11.0 + Vector3.UP * 0.5
			_player.velocity = Vector3.ZERO
		_was_burrow = _mob.state == "burrow"


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
