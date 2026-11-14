extends Node
## Mede o custo da Chuva de Meteoros com 4 magos canalizando juntos (o jogador local + 3 réplicas tocadas
## por play_remote) e 12 inimigos dentro das áreas, e tira prints do preparo, da chuva de longe e de perto
## e de um impacto, mais uma folha de contato com todos.
## Precisa de janela (não use --headless): a medida inclui o desenho.
##   godot --path . res://tools/meteor_perf.tscn -- --weapon=apprentice_staff [--meteor-out=<pasta>] [--meteor-solo]
## `--weapon=` usa um personagem novo em user://demo_solo.json (não mexe no save solo).
## Imprime "METEOR_PERF ..." com a média de fps e o pior quadro de cada fase e fecha sozinho.

const ENEMIES := 12
const ROUNDS := 3
const ROUND_TIME := 5.2      ## uma chuva inteira (preparo 0,5 + 4,0 s) e os últimos meteoros caindo
const SHOTS := ["meteor_1_preparo", "meteor_2_chuva_longe", "meteor_3_chuva_perto", "meteor_4_impacto"]

var _out := ""
var _solo := false
var _frames: Array = []      ## duração de cada quadro (ms) da fase em medição
var _gpu: Array = []         ## tempo de GPU de cada quadro (ms)
var _cpu: Array = []         ## tempo de CPU do desenho de cada quadro (ms)
var _proc: Array = []        ## tempo de process + physics de cada quadro (ms)
var _measuring := false
var player: Player
var _reps: Array = []
var _rep_centers: Array = []
var _center := Vector3.ZERO
var _enemies: Array = []     ## [inimigo, posição na área]
var _aim := Vector2.ZERO     ## (yaw, pitch) da câmera que mira em _center
var _last_us := 0
var _round_us := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--meteor-out="):
			_out = a.substr(13)
	_solo = "--meteor-solo" in OS.get_cmdline_user_args()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	await get_tree().create_timer(2.0).timeout
	player = get_tree().get_first_node_in_group("player")
	await _setup()
	await get_tree().create_timer(1.5).timeout
	var idle := await _measure(func(): return null, 4.0, 4.0)
	_report("parado (12 inimigos, sem habilidade)", idle)
	if _out != "":
		await _shots()
		await get_tree().create_timer(1.0).timeout
	# primeira rodada à parte: inclui a compilação dos shaders no primeiro uso (sem prints antes)
	var warm := await _measure(_volley, ROUND_TIME, ROUND_TIME)
	_report("primeira rodada", warm)
	var four := await _measure(_volley, ROUNDS * ROUND_TIME, ROUND_TIME)
	_report("%d mago(s) com a ultimate, 12 inimigos" % (1 if _solo else 4), four)
	print("METEOR_PERF partículas reservadas no fim: %d" % FXEpic._active_amount)
	await get_tree().create_timer(3.0).timeout
	print("METEOR_PERF partículas reservadas 3 s depois: %d" % FXEpic._active_amount)
	get_tree().quit()


func _process(_delta: float) -> void:
	# relógio real: o delta de _process encolhe com Engine.time_scale (hit stop)
	var now := Time.get_ticks_usec()
	if _measuring and _last_us > 0:
		var ms := (now - _last_us) / 1000.0
		_frames.append(ms)
		var vp := get_viewport().get_viewport_rid()
		_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
		_proc.append((Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
		if ms > 30.0:
			print("METEOR_PERF quadro lento %.1f ms aos %.2f s da rodada (%s %.2f)" % [ms, (now - _round_us) / 1.0e6, player.ability, player.ability_t])
	_last_us = now
	if player:
		Game.hp = Game.max_hp()   # os inimigos não interrompem a medida
		player.invuln = 1.0
	for pair in _enemies:
		if is_instance_valid(pair[0]):
			pair[0].stagger = 0.5   # não correm atrás do jogador: a mira (que acerta inimigos) fica na área


## Lugar aberto: gira a câmera até a mira cair a 9-14 m no chão; 12 inimigos dentro da área e 3 réplicas
## ao lado do jogador, cada uma com a sua área ao lado da dele (as quatro se sobrepõem em parte).
func _setup() -> void:
	# campo aberto: a casa do slime mais perto (a praça do começo é apertada entre casas)
	var home := Vector3.INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.kind == "slime" and not e.is_boss and (home == Vector3.INF or e.home.distance_to(player.global_position) < home.distance_to(player.global_position)):
			home = e.home
	if home != Vector3.INF:
		player.global_position = home + Vector3(3.0, 0.5, 3.0)   # ao lado (em cima do slime ele carregaria o jogador)
		player.velocity = Vector3.ZERO
		player._snap_visuals()
		for k in 30:
			await get_tree().physics_frame
	var yaw0: float = player.cam_yaw.rotation.y
	var best := -1.0
	var best_yaw := yaw0
	for k in 16:
		player.cam_yaw.rotation.y = yaw0 + k * TAU / 16.0
		await get_tree().physics_frame
		await get_tree().physics_frame
		var c := StaffAbilities._meteor_center(player)
		var dd := Vector2(c.x - player.global_position.x, c.z - player.global_position.z).length()
		var flat := absf(c.y - player.global_position.y) < 1.5
		if flat and dd > best:
			best = dd
			best_yaw = player.cam_yaw.rotation.y
	player.cam_yaw.rotation.y = best_yaw
	# câmera um pouco mais alta: a área fica a ~11 m (a mira padrão cai a ~6-8 m)
	for k in 12:
		await get_tree().physics_frame
		await get_tree().physics_frame
		var c := StaffAbilities._meteor_center(player)
		if Vector2(c.x - player.global_position.x, c.z - player.global_position.z).length() >= 10.5:
			break
		player.cam_pitch.rotation.x += 0.03
	await get_tree().physics_frame
	_center = StaffAbilities._meteor_center(player)
	_aim = Vector2(player.cam_yaw.rotation.y, player.cam_pitch.rotation.x)
	# o mouse de verdade giraria a câmera (modo capturado) e tiraria a mira da área no meio da medida
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var p0: Vector3 = player.global_position
	var dir := Vector3(_center.x - p0.x, 0.0, _center.z - p0.z).normalized()
	var side := dir.cross(Vector3.UP).normalized()
	var all: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e.dead and not e.is_boss:
			all.append(e)
	all.sort_custom(func(a, b): return a.global_position.distance_to(player.global_position) < b.global_position.distance_to(player.global_position))
	for i in mini(ENEMIES, all.size()):
		var e = all[i]
		e.max_hp = 1.0e7
		e.hp = e.max_hp
		var a := i * TAU / ENEMIES + 0.3
		var r := 1.5 + 3.0 * float(i % 3) / 2.0
		e.global_position = _center + Vector3(cos(a), 0.0, sin(a)) * r + Vector3.UP * 0.5
		_enemies.append([e, e.global_position])
	for k in 20:
		await get_tree().physics_frame
	print("METEOR_PERF inimigos %d, centro a %.1f m (jogador a %.2f m do lugar)" % [mini(ENEMIES, all.size()),
		Vector2(_center.x - p0.x, _center.z - p0.z).length(), Vector2(player.global_position.x - p0.x, player.global_position.z - p0.z).length()])
	if _solo:
		return
	for k in 3:
		var rp := Player.new()
		rp.remote = true
		get_tree().current_scene.add_child(rp)
		var off := side * (2.5 * (k + 1) * (1.0 if k % 2 == 0 else -1.0))
		rp.global_position = p0 + off
		rp._net_pos = rp.global_position   # sem pacotes de rede: senão _remote_process a puxa para a origem
		rp.apply_look(Game.equipment.duplicate())
		rp.model.rotation.y = atan2(dir.x, dir.z)
		_reps.append(rp)
		_rep_centers.append(_center + off * 1.2)


## Uma chuva de cada mago: o local por use_slot (canaliza até o fim sozinho), as réplicas pelo evento.
func _volley() -> void:
	for pair in _enemies:   # o empurrão das explosões espalha os inimigos: volta cada um ao lugar
		if is_instance_valid(pair[0]):
			pair[0].global_position = pair[1]
			pair[0].velocity = Vector3.ZERO
	player.cam_yaw.rotation.y = _aim.x
	player.cam_pitch.rotation.x = _aim.y
	Game.fury = 100.0
	Game.level = 8
	player.cooldowns.meteor_rain = 0.0
	player.use_slot(4)
	for i in _reps.size():
		StaffAbilities.play_remote(_reps[i], "meteor_rain", _rep_centers[i], Vector3(randi() % 16777216, 0, 0))


## Mede `seconds` chamando `action` a cada `every` s (relógio real ignorando a pausa).
func _measure(action: Callable, seconds: float, every: float) -> Array:
	_frames = []
	_gpu = []
	_cpu = []
	_proc = []
	_measuring = true
	var t := 0.0
	while t < seconds - 0.001:
		_round_us = Time.get_ticks_usec()
		action.call()
		await get_tree().create_timer(every, true, false, true).timeout
		t += every
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
	print("METEOR_PERF %s: %.1f fps médio, pior quadro %.1f ms, p99 %.1f ms (%d quadros); médias: GPU %.1f ms, CPU do desenho %.1f ms, process+physics %.1f ms; %d chamadas de desenho"
		% [what, frames.size() * 1000.0 / total, worst, p99, frames.size(), _avg(_gpu), _avg(_cpu), _avg(_proc),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])


func _avg(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var t := 0.0
	for x in a:
		t += float(x)
	return t / a.size()


## Prints: o preparo, a chuva de longe e de perto e um impacto; depois a folha de contato.
func _shots() -> void:
	_volley()
	await _snap(SHOTS[0], func(): return player.ability_t >= 0.38)
	await _snap(SHOTS[1], func(): return player.ability_t >= 1.9)
	await _snap(SHOTS[2], func(): return player.ability_t >= 2.6)
	await _snap(SHOTS[3], func(): return _just_landed() != null)
	await get_tree().create_timer(2.5).timeout
	_contact_sheet()


## Meteoro do jogador local que caiu agora há pouco (a explosão no auge).
func _just_landed() -> Node3D:
	for n in get_tree().current_scene.get_children():
		if n is StaffAbilities.MeteorStrike and n.caster == player and n.landed:
			var since: float = n.age() - StaffAbilities.METEOR_FALL
			if since >= 0.07 and since <= 0.14 and n.target.distance_to(_center) < 6.0:
				return n
	return null


## Print pela câmera do jogo e por uma câmera de lado escolhida para cada momento. O jogo pausa
## enquanto tira as duas fotos do mesmo instante.
func _snap(name: String, when: Callable) -> void:
	var waited := 0
	while not when.call():
		await get_tree().process_frame
		waited += 1
		if waited % 600 == 0:
			print("METEOR_PERF esperando ", name, " ability=", player.ability, " t=", player.ability_t)
	var focus := Vector3.ZERO
	var hit := _just_landed()
	if hit:
		focus = hit.target
	get_tree().paused = true   # o mundo congela (este nó segue: PROCESS_MODE_ALWAYS)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join("%s.png" % name))
	var p0: Vector3 = player.global_position
	var dir := Vector3(_center.x - p0.x, 0.0, _center.z - p0.z).normalized()
	var side := dir.cross(Vector3.UP).normalized()
	var mid := (p0 + _center) * 0.5
	var eye: Vector3
	var look: Vector3
	match name:
		"meteor_1_preparo":   # de frente para o mago, um pouco de lado: cajado erguido e o anel de brasas
			eye = p0 + dir * 3.6 + side * 1.8 + Vector3.UP * 1.5
			look = p0 + Vector3.UP * 1.5
		"meteor_2_chuva_longe":   # de lado e de longe: o mago, o céu escuro e a chuva inteira
			eye = mid + side * 19.0 - dir * 4.0 + Vector3.UP * 6.0
			look = mid + dir * 2.0 + Vector3.UP * 4.5
		"meteor_3_chuva_perto":   # dentro da chuva, olhando para cima
			eye = _center - side * 6.5 - dir * 2.0 + Vector3.UP * 1.6
			look = _center + Vector3.UP * 4.0
		_:   # o impacto de perto
			var f := focus if focus != Vector3.ZERO else _center
			eye = f - side * 4.5 - dir * 2.5 + Vector3.UP * 2.0
			look = f + Vector3.UP * 0.8
	var cam := Camera3D.new()
	cam.fov = 65.0
	get_tree().current_scene.add_child(cam)
	cam.look_at_from_position(eye, look)
	cam.make_current()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join("%s_lado.png" % name))
	player.camera.make_current()
	cam.queue_free()
	# quadros ainda pausados: o tempo gasto salvando o PNG não vira um delta gigante depois da pausa
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().paused = false
	print("METEOR_PERF print ", name)


## Folha de contato: os 8 prints (jogo à esquerda, câmera de lado à direita), em 800x450 cada.
func _contact_sheet() -> void:
	var w := 800
	var h := 450
	var sheet := Image.create(w * 2, h * SHOTS.size(), false, Image.FORMAT_RGB8)
	for i in SHOTS.size():
		for j in 2:
			var path: String = _out.path_join("%s%s.png" % [SHOTS[i], "" if j == 0 else "_lado"])
			var img := Image.load_from_file(path)
			if img == null:
				continue
			img.convert(Image.FORMAT_RGB8)
			img.resize(w, h, Image.INTERPOLATE_BILINEAR)
			sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(j * w, i * h))
	sheet.save_png(_out.path_join("meteor_all.png"))
	print("METEOR_PERF folha ", _out.path_join("meteor_all.png"))
