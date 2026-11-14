extends Node
## Mede o custo da Flecha do Vendaval com 4 arqueiros atirando juntos (o jogador local + 3 réplicas
## tocadas por play_remote) e 12 inimigos na frente, e tira prints da tensão, do disparo e da linha.
## Precisa de janela (não use --headless): a medida inclui o desenho.
##   godot --path . res://tools/gale_perf.tscn -- --weapon=short_bow [--gale-out=<pasta>] [--gale-solo]
## `--weapon=` usa um personagem novo em user://demo_solo.json (não mexe no save solo).
## Imprime "GALE_PERF ..." com a média de fps e o pior quadro de cada fase e fecha sozinho.

const ENEMIES := 12
const ROUNDS := 5            ## disparos de cada arqueiro na fase medida
const ROUND_TIME := 2.0      ## um disparo a cada 2 s (tensão 0,6 s + linha + recuperação)

var _out := ""
var _solo := false
var _frames: Array = []      ## duração de cada quadro (ms) da fase em medição
var _measuring := false
var player: Player
var _reps: Array = []
var _last_us := 0
var _round_us := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--gale-out="):
			_out = a.substr(11)
	_solo = "--gale-solo" in OS.get_cmdline_user_args()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await get_tree().create_timer(2.0).timeout
	player = get_tree().get_first_node_in_group("player")
	await _setup()
	await get_tree().create_timer(1.5).timeout
	var idle := await _measure(func(): return null, 4.0)
	_report("parado (12 inimigos, sem habilidade)", idle)
	if _out != "":
		await _shots()
	# primeira rodada à parte: inclui a compilação dos shaders no primeiro uso dos efeitos
	var warm := await _measure(_volley, ROUND_TIME)
	_report("primeira rodada (primeiro uso)", warm)
	var four := await _measure(_volley, ROUNDS * ROUND_TIME)
	_report("%d arqueiro(s) com a ultimate, 12 inimigos" % (1 if _solo else 4), four)
	get_tree().quit()


func _process(_delta: float) -> void:
	# relógio real: o delta de _process encolhe com Engine.time_scale (hit stop)
	var now := Time.get_ticks_usec()
	if _measuring and _last_us > 0:
		var ms := (now - _last_us) / 1000.0
		_frames.append(ms)
		if ms > 30.0:
			print("GALE_PERF quadro lento %.1f ms aos %.2f s da rodada (%s)" % [ms, (now - _round_us) / 1.0e6, player.ability])
	_last_us = now
	if player:
		Game.hp = Game.max_hp()   # os inimigos não interrompem a medida
		player.invuln = 1.0


## Lugar aberto: 12 inimigos em leque à frente do jogador e 3 réplicas ao lado dele.
func _setup() -> void:
	# gira a câmera até a mira ter 30 m livres (a praça tem o poço bem na frente do spawn)
	var yaw0: float = player.cam_yaw.rotation.y
	for k in 16:
		player.cam_yaw.rotation.y = yaw0 + k * TAU / 16.0
		await get_tree().physics_frame
		await get_tree().physics_frame
		var d0: Vector3 = BowAbilities._gale_dir(player)
		if BowAbilities._gale_length(player, player.global_position + Vector3.UP * BowAbilities.GALE_HEIGHT, d0) >= 30.0:
			break
	var dir: Vector3 = BowAbilities._gale_dir(player)
	var side := dir.cross(Vector3.UP).normalized()
	var all: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e.dead and not e.is_boss:
			all.append(e)
	all.sort_custom(func(a, b): return a.global_position.distance_to(player.global_position) < b.global_position.distance_to(player.global_position))
	var p0: Vector3 = player.global_position
	for i in mini(ENEMIES, all.size()):
		var e = all[i]
		e.max_hp = 1.0e7
		e.hp = e.max_hp
		e.global_position = p0 + dir * (6.0 + 2.0 * (i / 3)) + side * (float(i % 3) - 1.0) * 2.5 + Vector3.UP * 0.5
	print("GALE_PERF inimigos ", mini(ENEMIES, all.size()))
	if _solo:
		return
	for k in 3:
		var rp := Player.new()
		rp.remote = true
		get_tree().current_scene.add_child(rp)
		rp.global_position = p0 + side * (2.5 * (k + 1) * (1.0 if k % 2 == 0 else -1.0))
		rp.model.rotation.y = atan2(dir.x, dir.z)
		_reps.append(rp)


## Um disparo de cada arqueiro: o local por use_slot/release, as réplicas pelos eventos de rede.
func _volley() -> void:
	Game.fury = 100.0
	Game.level = 8
	player.use_slot(4)
	for rp in _reps:
		BowAbilities.play_remote(rp, "bow_gale", rp.global_position, Vector3.ZERO)
	await get_tree().create_timer(0.6).timeout
	BowAbilities.release(player)
	var dir: Vector3 = BowAbilities._gale_dir(player)
	for rp in _reps:
		BowAbilities.play_remote(rp, "bow_gale_fire", rp.global_position + Vector3.UP * BowAbilities.GALE_HEIGHT, dir * 0.5)


func _measure(action: Callable, seconds: float) -> Array:
	_frames = []
	_measuring = true
	var t := 0.0
	while t < seconds:
		_round_us = Time.get_ticks_usec()
		action.call()
		await get_tree().create_timer(ROUND_TIME, true, false, true).timeout
		t += ROUND_TIME
	_measuring = false
	return _frames


func _report(what: String, frames: Array) -> void:
	if frames.is_empty():
		return
	var total := 0.0
	var worst := 0.0
	for f in frames:
		total += f
		worst = maxf(worst, f)
	var sorted := frames.duplicate()
	sorted.sort()
	var p99: float = sorted[int(sorted.size() * 0.99)]
	print("GALE_PERF %s: %.1f fps médio, pior quadro %.1f ms, p99 %.1f ms (%d quadros)" % [what, frames.size() * 1000.0 / total, worst, p99, frames.size()])


## Prints: tensão no começo, no meio e cheia, o disparo e a linha.
func _shots() -> void:
	Game.fury = 100.0
	Game.level = 8
	player.use_slot(4)
	await _snap("1_tensao_comeco", func(): return player.ability_t >= 0.15)
	await _snap("2_tensao_meio", func(): return player.ability_t >= 0.6)
	await _snap("3_tensao_cheia", func(): return player.ability_t >= 1.15)   # logo antes do disparo automático
	await _snap("4_disparo", func(): return player.ability_data.get("fired", false) and player.ability_t - float(player.ability_data.fire_t) >= 0.05)
	await _snap("5_linha", func(): return player.ability_data.get("fired", false) and player.ability_t - float(player.ability_data.fire_t) >= 0.22)
	await get_tree().create_timer(1.5).timeout


## Print pela câmera do jogo e por uma câmera de lado (3/4, um pouco de cima) que mostra a pose e a linha.
## O jogo pausa enquanto tira as duas fotos do mesmo instante.
func _snap(name: String, when: Callable) -> void:
	var waited := 0
	while not when.call():
		await get_tree().process_frame
		waited += 1
		if waited % 300 == 0:
			print("GALE_PERF esperando ", name, " ability=", player.ability, " t=", player.ability_t)
	get_tree().paused = true   # o mundo congela (este nó segue: PROCESS_MODE_ALWAYS)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join("gale_%s.png" % name))
	var dir: Vector3 = player.facing()
	var side := dir.cross(Vector3.UP).normalized()
	var cam := Camera3D.new()
	cam.fov = 60.0
	get_tree().current_scene.add_child(cam)
	var p0: Vector3 = player.global_position
	var far := name.ends_with("linha") or name.ends_with("disparo")
	var eye := p0 + side * (9.0 if far else 3.2) + dir * (4.0 if far else 1.2) + Vector3.UP * (5.0 if far else 1.6)
	cam.look_at_from_position(eye, p0 + dir * (8.0 if far else 0.3) + Vector3.UP * 0.9)
	cam.make_current()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join("gale_%s_lado.png" % name))
	player.camera.make_current()
	cam.queue_free()
	get_tree().paused = false
	print("GALE_PERF print ", name)
