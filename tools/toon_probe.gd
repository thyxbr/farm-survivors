extends Node
## Sonda de desempenho do estilo toon, dentro do jogo de verdade. Ligada por `-- --toonprobe[=SEG]`
## (o autoload Toon a cria); imprime uma linha `[toonprobe]` a cada 5 s e, com `=SEG`, um resumo e fecha.
##   --toonprobe=70 --proberound=12   na Horda (`--geardemo --survival --hordedemo`): fixa a rodada, mantém
##                                    o jogador vivo e sem subir de nível, para a horda ficar cheia e girando
## Mede: tempo de quadro (média, p99 e pior), quadros em que nasceu inimigo x os outros, draw calls,
## triângulos, custo de ToonLook.apply, do gancho de cena e o tamanho dos caches. Desliga o vsync.
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


func _on_node_added(n: Node) -> void:
	if n is Enemy:
		_spawned = true


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last) / 1000.0
	_last = now
	_t += delta
	_hold_horde()
	_frames.append(ms)
	if _t >= WARMUP:
		if _warm.is_empty():
			_warm = ToonLook.stats.duplicate()
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
	_frames.clear()


func _summary() -> void:
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
	print("[toonprobe] RESUMO toon=%s contorno=%s quadros=%d media=%.2f ms p50=%.2f p99=%.2f pior=%.2f | quadro com nascimento=%.2f ms (%d) sem=%.2f ms (%d) | draw=%.0f tris=%.0f inimigos=%.1f | mats=%d hulls=%d juntas=%d" % [
		ToonLook.enabled(), ToonLook.enabled() and ToonLook.outline_enabled(), _all.size(), sum / maxf(1.0, _all.size()), _pct(_all, 0.5), _pct(_all, 0.99), _pct(_all, 1.0),
		_spawn_ms / maxf(1.0, _spawn_n), _spawn_n, _calm_ms / maxf(1.0, _calm_n), _calm_n,
		_dc / n, _prims / n, _enemies_sum / n, ToonLook._mats.size(), ToonLook._hulls.size(), ToonLook._merged.size()])
