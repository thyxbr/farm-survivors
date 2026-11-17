extends Node
## Sonda de desempenho do estilo toon, dentro do jogo de verdade. Ligada por `-- --toonprobe[=SEG]`
## (o autoload Toon a cria); imprime uma linha `[toonprobe]` a cada 5 s e, com `=SEG`, um resumo e fecha.
##   --toonprobe=70 --proberound=12   na Horda (`--geardemo --survival --hordedemo`): fixa a rodada, mantém
##                                    o jogador vivo e sem subir de nível, para a horda ficar cheia e girando
## Mede: tempo de quadro (média, p99 e pior), quadros em que nasceu inimigo x os outros, draw calls,
## triângulos, custo de ToonLook.apply, do gancho de cena e o tamanho dos caches. Desliga o vsync.
## A linha `FASES` separa o quadro em física, process e desenho (média real, medida entre os sinais do
## motor; os monitores TIME_PROCESS/TIME_PHYSICS_PROCESS da linha `PARTES` são o pico de um passo, não a
## soma) e conta os passos de física por quadro: perto de 8, o teto do motor, o jogo está em espiral
## (cada quadro lento pede mais passos, que deixam o próximo mais lento). Números em docs/desempenho/.
## O resumo traz um CENSO da cena (malhas, superfícies e triângulos por grupo e por distância da câmera) e
## `--probex=` desliga partes do jogo para medir quanto custam (ver _experiment).
## Com `--notoon` mede a mesma coisa sem o estilo. Números em docs/ESTILO_TOON.md.

const WARMUP := 10.0                      # carga da cena e compilação de shaders ficam fora do resumo

var _limit := 0.0
var _round := 0
var _t := 0.0
var _last := 0
var _frames: PackedFloat32Array = []      # ms, janela de 5 s
var _all: PackedFloat32Array = []         # ms, a partida toda (depois do aquecimento)
var _spawn_ms := 0.0
var _spawn_n := 0
var _calm_ms := 0.0
var _calm_n := 0
var _spawned := false
var _dc := 0.0
var _prims := 0.0
var _samples := 0
var _enemies_sum := 0.0
var _next := 5.0
var _proc := 0.0
var _warm := {}                           # ToonLook.stats no fim do aquecimento
var _phys := 0.0
var _rcpu := 0.0
var _rgpu := 0.0
## Fases do quadro (usec acumulados): física = do primeiro passo até o começo do process; process = até o
## começo do desenho; desenho = frame_pre_draw até frame_post_draw. Um conjunto por janela de 5 s e outro
## para o resumo.
var _phase := {"fis": 0, "proc": 0, "draw": 0}
var _phase_all := {"fis": 0, "proc": 0, "draw": 0}
var _mark_phys := 0
var _mark_proc := 0
var _mark_draw := 0
var _steps0 := 0          # Engine.get_physics_frames() no começo da janela de 5 s
var _steps_all0 := -1     # idem, no fim do aquecimento


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--toonprobe="):
			_limit = float(a.get_slice("=", 1))
		elif a.begins_with("--proberound="):
			_round = int(a.get_slice("=", 1))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	get_tree().node_added.connect(_on_node_added)
	_last = Time.get_ticks_usec()
	_steps0 = Engine.get_physics_frames()
	get_tree().physics_frame.connect(_on_physics_frame)
	get_tree().process_frame.connect(_on_process_frame)
	RenderingServer.frame_pre_draw.connect(_on_pre_draw)
	RenderingServer.frame_post_draw.connect(_on_post_draw)


var _xdone := false


## Experimentos (`--probex=a,b`): desliga uma coisa para medir quanto ela custa. Compare sempre com uma rodada
## sem nada, com o clima e a hora fixos (`--weather=sol --hora=12 --season=verao`): sem isso os draw calls
## mudam de uma rodada para outra.
##   noshadow        sem a sombra do sol
##   off:<script>    para o _process e o _physics_process de todo nó com esse script (ex.: off:hud)
##   hide:<script>   esconde todo nó com esse script
##   procs           lista quantos nós de cada script rodam por quadro
func _experiment() -> void:
	var x := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--probex="):
			x = a.get_slice("=", 1)
	if x == "":
		return
	var scripted: Array = []
	for n in get_tree().root.find_children("*", "", true, false):
		if n.get_script() != null:
			scripted.append(n)
	for k in x.split(",", false):
		if k.begins_with("off:") or k.begins_with("hide:"):
			for n in scripted:
				if (n.get_script() as Script).resource_path.get_file() == k.get_slice(":", 1) + ".gd":
					if k.begins_with("off:"):
						n.set_process(false)
						n.set_physics_process(false)
					elif n is Node3D or n is CanvasItem or n is CanvasLayer:
						n.visible = false
		elif k == "noshadow":
			for l in get_tree().current_scene.find_children("*", "DirectionalLight3D", true, false):
				l.shadow_enabled = false
		elif k == "procs":
			var cnt := {}
			for n in scripted:
				var f: String = (n.get_script() as Script).resource_path.get_file()
				var e: Array = cnt.get(f, [0, 0, 0])
				e[0] += 1
				if n.is_processing():
					e[1] += 1
				if n.is_physics_processing():
					e[2] += 1
				cnt[f] = e
			for f in cnt:
				if cnt[f][1] + cnt[f][2] > 0:
					print("[toonprobe] PROC %-28s nós=%4d process=%4d physics=%4d" % [f, cnt[f][0], cnt[f][1], cnt[f][2]])
	print("[toonprobe] EXPERIMENTO ", x)


func _on_physics_frame() -> void:
	if _mark_phys == 0:
		_mark_phys = Time.get_ticks_usec()


func _on_process_frame() -> void:
	_mark_proc = Time.get_ticks_usec()
	if _mark_phys != 0:
		_add_phase("fis", _mark_proc - _mark_phys)
	_mark_phys = 0


func _on_pre_draw() -> void:
	_mark_draw = Time.get_ticks_usec()
	_add_phase("proc", _mark_draw - _mark_proc)


func _on_post_draw() -> void:
	_add_phase("draw", Time.get_ticks_usec() - _mark_draw)


func _add_phase(k: String, usec: int) -> void:
	_phase[k] += usec
	if _t >= WARMUP:
		_phase_all[k] += usec


func _phases(p: Dictionary, frames: float, steps: int) -> String:
	return "física=%.2f ms (%.2f passos por quadro, %.2f ms por passo) process=%.2f ms desenho=%.2f ms" % [
		p.fis / 1000.0 / frames, steps / frames, p.fis / 1000.0 / maxf(1.0, steps), p.proc / 1000.0 / frames, p.draw / 1000.0 / frames]


func _on_node_added(n: Node) -> void:
	if n is Enemy:
		_spawned = true


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last) / 1000.0
	_last = now
	_t += delta
	_hold_horde()
	if _t > 6.0 and not _xdone:
		_xdone = true
		_experiment()
	_frames.append(ms)
	if _t >= WARMUP:
		if _warm.is_empty():
			_warm = ToonLook.stats.duplicate()
			_steps_all0 = Engine.get_physics_frames()
			ToonLook.stats.apply_max_usec = 0
		_all.append(ms)
		if _spawned:
			_spawn_ms += ms
			_spawn_n += 1
		else:
			_calm_ms += ms
			_calm_n += 1
		_dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		_prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		_enemies_sum += get_tree().get_nodes_in_group("enemies").size()
		_samples += 1
		var rid := get_viewport().get_viewport_rid()
		_proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		_phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		_rcpu += RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu()
		_rgpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	_spawned = false
	if _t >= _next:
		_next += 5.0
		_line()
	if _limit > 0.0 and _t >= _limit:
		_summary()
		get_tree().quit()


## Horda: rodada fixa, sem fim de rodada, jogador vivo e sem carta de nível (que pausaria a horda).
func _hold_horde() -> void:
	if _round <= 0:
		return
	var w = get_tree().current_scene
	var s = w.get("survival") if w else null
	if s == null or not is_instance_valid(s):
		return
	s.round_num = _round
	s.round_left = 60.0
	s.run_xp = 0.0
	s.run_level = 60          # nível alto: nenhuma gema fecha um nível
	s._queue.clear()
	if s.player and is_instance_valid(s.player):
		s.player.invuln = 5.0
	Game.hp = Game.max_hp()


func _pct(a: PackedFloat32Array, p: float) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return s[mini(s.size() - 1, int(s.size() * p))]


func _line() -> void:
	var sum := 0.0
	for x in _frames:
		sum += x
	var ts: Dictionary = ToonLook.stats
	var hs: Dictionary = get_parent().stats
	var w = get_tree().current_scene
	var sv = w.get("survival") if w else null
	if sv != null and is_instance_valid(sv):
		print("[toonprobe] horda: fase=%s congelada=%s vivos=%d abates=%d pausa=%s modal=%s process=%.2f ms fisica=%.2f ms" % [sv.phase, sv.frozen,
			sv.alive_count(), sv.kills, get_tree().paused, w.get("modal") != null,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	print("[toonprobe] t=%.0f toon=%s quadro=%.2f ms (p99 %.2f, pior %.2f) draw=%d tris=%d inimigos=%d | apply=%d (%.1f ms no total, pior %.2f ms) cascas=%d (%.1f ms) contornos=%d mats=%d hulls=%d juntas=%d | gancho: %d vistas, %d convertidas, %.1f ms, pior quadro %.2f ms (lote %d)" % [
		_t, ToonLook.enabled(), sum / maxf(1.0, _frames.size()), _pct(_frames, 0.99), _pct(_frames, 1.0),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		get_tree().get_nodes_in_group("enemies").size(),
		ts.apply, ts.apply_usec / 1000.0, ts.apply_max_usec / 1000.0, ts.hulls, ts.hull_usec / 1000.0,
		ts.outlines, ToonLook._mats.size(), ToonLook._hulls.size(), ToonLook._merged.size(),
		hs.seen, hs.converted, hs.usec / 1000.0, hs.max_frame_usec / 1000.0, hs.max_batch])
	print("[toonprobe] FASES (média por quadro, últimos 5 s) ", _phases(_phase, maxf(1.0, _frames.size()), Engine.get_physics_frames() - _steps0))
	_steps0 = Engine.get_physics_frames()
	for k in _phase:
		_phase[k] = 0
	_frames.clear()


## Censo do que está na cena: por grupo (o segundo nível abaixo da cena e o tipo do dono), quantas malhas
## visíveis, quantas superfícies (cada uma é ao menos um draw call por passada), triângulos e quantas não
## têm distância de sumiço (`visibility_range_end`). Também separa por distância da câmera.
func _census() -> void:
	var scene := get_tree().current_scene
	var cam := get_viewport().get_camera_3d()
	if scene == null or cam == null:
		return
	var groups := {}
	var rings := {}
	var total := [0, 0, 0]
	for n in scene.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		var surf := 0
		var tris := 0
		var mesh: Mesh = null
		var mult := 1
		if g is MeshInstance3D:
			mesh = g.mesh
		elif g is MultiMeshInstance3D and g.multimesh != null:
			mesh = g.multimesh.mesh
			mult = g.multimesh.visible_instance_count if g.multimesh.visible_instance_count >= 0 else g.multimesh.instance_count
		if mesh == null:
			continue
		surf = mesh.get_surface_count()
		for i in surf:
			var arr_len := 0
			if mesh is ArrayMesh:
				arr_len = mesh.surface_get_array_index_len(i)
				if arr_len == 0:
					arr_len = mesh.surface_get_array_len(i)
			else:
				var a := mesh.surface_get_arrays(i)
				arr_len = (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() if a[Mesh.ARRAY_INDEX] != null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			tris += arr_len / 3 * mult
		var key := _census_key(scene, g)
		var e: Array = groups.get(key, [0, 0, 0, 0])
		e[0] += 1
		e[1] += surf
		e[2] += tris
		if g.visibility_range_end <= 0.0:
			e[3] += 1
		groups[key] = e
		var d := cam.global_position.distance_to(g.global_position)
		var ring := "0-40 m" if d < 40.0 else ("40-80 m" if d < 80.0 else ("80-150 m" if d < 150.0 else "150+ m"))
		var r: Array = rings.get(ring, [0, 0, 0])
		r[0] += 1
		r[1] += surf
		r[2] += tris
		rings[ring] = r
		total[0] += 1
		total[1] += surf
		total[2] += tris
	print("[toonprobe] CENSO total: %d malhas visíveis, %d superfícies, %d triângulos" % total)
	for k in ["0-40 m", "40-80 m", "80-150 m", "150+ m"]:
		var r: Array = rings.get(k, [0, 0, 0])
		print("[toonprobe] CENSO distância %s: %d malhas, %d superfícies, %d triângulos" % [k, r[0], r[1], r[2]])
	var keys := groups.keys()
	keys.sort_custom(func(a, b): return groups[a][1] > groups[b][1])
	for k in keys.slice(0, 40):
		var e: Array = groups[k]
		print("[toonprobe] CENSO %-46s malhas=%5d superfícies=%5d tris=%8d sem_sumiço=%5d" % [k, e[0], e[1], e[2], e[3]])


func _census_key(scene: Node, g: Node) -> String:
	var owner_kind := ""
	var top := g
	var n: Node = g
	while n != null and n != scene:
		if owner_kind == "" and n.get_script() != null and n != g:
			owner_kind = (n.get_script() as Script).resource_path.get_file().get_basename()
		top = n
		n = n.get_parent()
	var second := top
	n = g
	while n != null and n.get_parent() != top and n != top:
		n = n.get_parent()
	if n != null and n != top:
		second = n
	var nm := String(second.name).rstrip("0123456789@_")
	return "%s/%s [%s]" % [String(top.name).rstrip("0123456789@_"), nm, owner_kind]


func _summary() -> void:
	_census()
	var sum := 0.0
	for x in _all:
		sum += x
	var n := maxf(1.0, _samples)
	var ts: Dictionary = ToonLook.stats
	var ap: int = ts.apply - _warm.get("apply", 0)
	print("[toonprobe] DEPOIS DO AQUECIMENTO apply=%d (%.2f ms cada, pior %.2f ms) cascas novas=%d (%.1f ms) contornos novos=%d" % [
		ap, (ts.apply_usec - _warm.get("apply_usec", 0)) / 1000.0 / maxf(1.0, ap), ts.apply_max_usec / 1000.0,
		ts.hulls - _warm.get("hulls", 0), (ts.hull_usec - _warm.get("hull_usec", 0)) / 1000.0, ts.outlines - _warm.get("outlines", 0)])
	print("[toonprobe] PARTES process=%.2f ms fisica=%.2f ms render_cpu=%.2f ms render_gpu=%.2f ms (médias por quadro)" % [
		_proc / n, _phys / n, _rcpu / n, _rgpu / n])
	print("[toonprobe] FASES RESUMO (média por quadro) ", _phases(_phase_all, maxf(1.0, _all.size()), Engine.get_physics_frames() - maxi(0, _steps_all0)))
	print("[toonprobe] RESUMO toon=%s contorno=%s quadros=%d media=%.2f ms p50=%.2f p99=%.2f pior=%.2f | quadro com nascimento=%.2f ms (%d) sem=%.2f ms (%d) | draw=%.0f tris=%.0f inimigos=%.1f | mats=%d hulls=%d juntas=%d" % [
		ToonLook.enabled(), ToonLook.enabled() and ToonLook.outline_enabled(), _all.size(), sum / maxf(1.0, _all.size()), _pct(_all, 0.5), _pct(_all, 0.99), _pct(_all, 1.0),
		_spawn_ms / maxf(1.0, _spawn_n), _spawn_n, _calm_ms / maxf(1.0, _calm_n), _calm_n,
		_dc / n, _prims / n, _enemies_sum / n, ToonLook._mats.size(), ToonLook._hulls.size(), ToonLook._merged.size()])
