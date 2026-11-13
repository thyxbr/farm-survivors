extends Node3D
## Desafio da Horda (estilo "survivors"): rodadas de inimigos sem fim na arena, gemas de XP,
## nível da partida com cartas de melhoria, bênçãos ao fim de cada rodada, eventos aleatórios
## (horde_events.gd) e o desafio da Caçada.
## Criado pelo mundo em start_survival(); fica na origem e é o pai dos inimigos e gemas.
##
## role:
##   "solo"   — offline: faz tudo localmente (as cartas pausam a árvore).
##   "server" — servidor dedicado: dono das rodadas, do spawn, dos abates, dos eventos e do NÍVEL DO
##              GRUPO (o XP das gemas de todos soma num só nível). Ao subir de nível congela a horda
##              até todos escolherem a carta ou o tempo (Network.horde_pick_time) acabar.
##   "client" — multiplayer: jogador local, armas automáticas e gemas próprias; manda o XP das gemas
##              para o servidor e recebe nível, rodadas, eventos e abates dele. Cartas e bênçãos são
##              de cada jogador (cada um monta a própria build).

const ENEMY := preload("res://scripts/enemies/enemy.gd")
const GEM := preload("res://scripts/survival/xp_gem.gd")
const PICKUP := preload("res://scripts/world/pickup.gd")
const UPG := preload("res://scripts/survival/upgrades.gd")
const EVT := preload("res://scripts/survival/horde_events.gd")
const WEAPONS := preload("res://scripts/survival/auto_weapons.gd")
const UI := preload("res://scripts/ui/survival_ui.gd")
const HUD := preload("res://scripts/ui/survival_hud.gd")

const ARENA_RADIUS := 31.0
const BOSS_EVERY := 5
## Servidor: tempo máximo esperando todos escolherem a bênção antes de começar a próxima rodada.
const BREAK_TIMEOUT := 30.0
## Chuva de Meteoros: raio do impacto e tempo de queda (o círculo de aviso dura isso).
const METEOR_RADIUS := 3.2
const METEOR_FALL := 1.4
## Goblin Dourado foge da arena depois de tantos segundos.
const GOLD_ESCAPE := 22.0

var role := "solo"
var world: Node
var player: Player
var center := Vector3.ZERO
var round_time := 45.0

var phase := "fight"          # fight | break | over
var round_num := 0
var rounds_cleared := 0
var round_left := 0.0
var elapsed := 0.0
var kills := 0
var run_level := 1
var run_xp := 0.0
var weapon_levels := {}
var passive_levels := {}
var blessing_counts := {}
var weapons: Node3D
var hud: CanvasLayer
var boss: Enemy = null
var end_reason := ""
var rewards := {}
var new_record := false
var seeds_won := 0
var hunts_won := 0

## Evento da rodada atual ("" = nenhum) e a Caçada (hunt_target = 0: sem desafio nesta rodada).
var event := ""
var hunt_target := 0
var hunt_kills := 0
var hunt_done := false

## Multiplayer: peer_id -> {"name", "dead", "ready" (bênção), "lv_ready" (carta de nível)}
## (no cliente, a cópia do servidor).
var team := {}
## Cliente: posição na roda de chegada (para o grupo não nascer empilhado).
var my_slot := 0
## Cliente: já escolheu a bênção e espera os outros jogadores.
var waiting := false
## Multiplayer: horda congelada enquanto o grupo escolhe as cartas de nível.
var frozen := false
## Segundos até acabar a escolha das cartas de nível (lv_*) e da bênção do intervalo (break_*).
## No servidor lv_left é o relógio de verdade; no cliente, só a contagem mostrada na tela.
var lv_left := 0.0
var lv_total := 1.0
var break_left := 0.0
var break_total := 1.0
## Cliente: já escolheu as cartas deste nível e espera o grupo.
var lv_waiting := false
## Só para screenshots (--hordedemo=grupo): mostra o painel do grupo offline.
var demo_group := false

var _queue: Array = []        # "levelup" | "round"
var _spawn_acc := 0.0
var _gold_start := 0
var _gem_sfx := 0.0
var _break_t := 0.0
var _round_t := 0.0           # segundos de luta desde o começo da rodada
var _last_event := ""
var _meteor_t := 0.0
var _meteors: Array = []      # {"pos": Vector3, "t": float, "node": Node3D}
var _gold_spawns: Array = []  # instantes (_round_t) para soltar Goblins Dourados
var _champ_spawns: Array = [] # instantes para soltar Campeões
## Servidor: níveis ganhos que ainda vão abrir uma escolha; estado de XP a reenviar.
var _lv_pending := 0
var _state_dirty := false
var _state_t := 0.0
## Cliente: cartas de nível que faltam escolher; XP de gemas a mandar ao servidor.
var _lv_picks_left := 0
var _xp_out := 0.0
var _xp_t := 0.0


func _ready() -> void:
	if role == "server":
		print("[server] Desafio da Horda começou: %s" % ", ".join(_names()))
		_start_round()
		return
	Game.reset_run_mods()
	Game.run_mods.active = true
	Game.hp = Game.max_hp()
	Game.mp = Game.max_mp()
	Game.stamina = Game.max_stamina()
	Game.stats_changed.emit()
	_gold_start = Game.gold
	player.global_position = center + _slot_offset() + Vector3.UP * 0.5
	player.velocity = Vector3.ZERO
	FX.burst(player.global_position + Vector3.UP, Color(0.7, 0.4, 1.0), 50, 6.0, 0.12, 1.0, 1.0)
	FX.ring(center, Color(0.7, 0.4, 1.0, 0.9), 4.0, 0.7)

	weapons = WEAPONS.new()
	weapons.survival = self
	player.add_child(weapons)
	_apply({"type": "weapon", "id": "fogo"})

	hud = HUD.new()
	hud.survival = self
	add_child(hud)
	if role == "client":
		# a rodada 1 chega do servidor logo em seguida (_horde_round_start)
		Game.notify.emit("Desafio da Horda em grupo: %s. O nível é do grupo!" % ", ".join(_names()), Color(0.85, 0.6, 1.0))
		return
	Game.notify.emit("Desafio da Horda! Sobreviva o máximo que puder.", Color(0.85, 0.6, 1.0))
	_start_round()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hordedemo"):
			_demo.call_deferred(a.get_slice("=", 1) if "=" in a else "")


## Depuração (screenshots): `--survival --hordedemo[=cards|grupo|espera]` monta uma build de exemplo.
func _demo(what: String) -> void:
	await get_tree().create_timer(0.4).timeout
	run_level = 9
	run_xp = xp_needed() * 0.62
	for w in [["laminas", 3], ["raio", 2], ["fogo", 2]]:
		for i in w[1]:
			_apply({"type": "weapon", "id": w[0]})
	for p in [["poder", 3], ["ima", 1], ["armadura", 2], ["celeridade", 1], ["vigor", 1]]:
		for i in p[1]:
			_apply({"type": "passive", "id": p[0]})
	for b in ["furia", "vento", "furia"]:
		_apply({"type": "blessing", "id": b})
	round_num = 4
	kills = 187
	hunt_target = 45
	hunt_kills = 28
	if event == "":
		event = "meteoros"
	if what in ["grupo", "espera"]:
		demo_group = true
		team = {1: {"name": Network.my_name if Network.my_name != "" else "Você", "dead": false, "ready": false, "lv_ready": what != "espera"},
			2: {"name": "Ana", "dead": false, "ready": false, "lv_ready": true},
			3: {"name": "Beto", "dead": true, "ready": false, "lv_ready": false}}
	if what == "espera":
		team[1].lv_ready = true
		frozen = true
		lv_left = 12.0
		lv_total = 20.0
	if what == "cards":
		_queue.append("levelup")
		_try_open_next()


func _exit_tree() -> void:
	_clear_meteors()
	if player and is_instance_valid(player):
		player.horde_frozen = false


func _names() -> Array[String]:
	var out: Array[String] = []
	for pid in team:
		out.append(str(team[pid].name))
	return out


func _slot_offset() -> Vector3:
	if role != "client" or team.size() <= 1:
		return Vector3.ZERO
	var a := TAU * my_slot / team.size()
	return Vector3(cos(a), 0, sin(a)) * 2.5


## Jogadores que os inimigos da horda perseguem (lido por Enemy._nearest_player).
func targets() -> Array:
	var out := []
	match role:
		"solo":
			if player and not player.dead:
				out.append(player)
		"server":
			for pid in team:
				if team[pid].dead:
					continue
				var rp: Player = Network.remote_players.get(pid)
				if rp and is_instance_valid(rp) and not rp.dead:
					out.append(rp)
	return out


func _team_size() -> int:
	return max(1, team.size()) if role == "server" else 1


func is_group() -> bool:
	return (role == "client" or demo_group) and team.size() > 1


# ================================================================ rodadas
## Solo e servidor: começa a próxima rodada (no cliente, ela chega em net_round_start).
func _start_round() -> void:
	round_num += 1
	round_left = round_time
	phase = "fight"
	_spawn_acc = 0.0
	_round_t = 0.0
	var boss_round := round_num % BOSS_EVERY == 0
	event = EVT.roll_event(round_num, boss_round, _last_event)
	if event != "":
		_last_event = event
	hunt_target = EVT.roll_hunt(round_num, boss_round, _team_size(), round_time)
	hunt_kills = 0
	hunt_done = false
	if Network.horde_force_event != "" and not boss_round:
		event = Network.horde_force_event   # --horde-event=ID (testes e screenshots)
	_setup_event()
	if boss_round:
		_spawn_boss()
	if role == "server":
		for pid in team:
			team[pid].dead = false
			team[pid].ready = false
		_send_all("_horde_round_start", [round_num, round_time, event, hunt_target])
		_send_team()
		_event_start()
		return
	_announce_round(boss_round)
	_event_start()


func _announce_round(boss_round: bool) -> void:
	if boss_round:
		Game.notify.emit("Rodada %d — o Rei Goblin chegou!" % round_num, Color(1, 0.45, 0.3))
	else:
		Game.notify.emit("Rodada %d" % round_num, Color(1, 0.85, 0.4))
	if event != "":
		Game.notify.emit("Evento: %s — %s" % [EVT.event_name(event), EVT.event_desc(event)], EVT.event_color(event))
	if hunt_target > 0:
		Game.notify.emit("Caçada: abata %d inimigos nesta rodada para ganhar um baú!" % hunt_target, EVT.HUNT.color)
	Sfx.play("quest", 0.0)


func boss_alive() -> bool:
	return boss != null and is_instance_valid(boss) and not boss.dead


func _physics_process(delta: float) -> void:
	_gem_sfx = max(0.0, _gem_sfx - delta)
	if phase == "over":
		return
	if role == "server":
		_server_process(delta)
		return
	if player == null:
		return
	# mantém o jogador dentro da arena
	var off := player.global_position - center
	off.y = 0
	if off.length() > ARENA_RADIUS:
		var n := off.normalized()
		player.global_position = Vector3(center.x, player.global_position.y, center.z) + n * ARENA_RADIUS
		var outward := Vector3(player.velocity.x, 0, player.velocity.z).dot(n)
		if outward > 0:
			player.velocity -= n * outward
	if role == "client":
		_client_process(delta)
		return
	if phase != "fight" or player.dead or frozen:
		return
	elapsed += delta
	round_left = max(0.0, round_left - delta)
	if round_left <= 0.0 and not boss_alive():
		_end_round()
		return
	_event_tick(delta)
	_spawn_tick(delta)


func _client_process(delta: float) -> void:
	player.horde_frozen = frozen
	if frozen:
		lv_left = maxf(0.0, lv_left - delta)
	elif phase == "break":
		break_left = maxf(0.0, break_left - delta)
	# o XP das gemas vai em lotes para o servidor (o nível é do grupo)
	_xp_t -= delta
	if _xp_out > 0.0 and _xp_t <= 0.0:
		_xp_t = 0.15
		Network.horde_xp(_xp_out)
		_xp_out = 0.0
	# só o relógio da HUD e os meteoros: o fim da rodada é decidido pelo servidor
	if phase == "fight" and not frozen:
		elapsed += delta
		_round_t += delta
		round_left = max(0.0, round_left - delta)
		_update_meteors(delta)


func _server_process(delta: float) -> void:
	_state_t -= delta
	if _state_dirty and _state_t <= 0.0:
		_state_t = 0.25
		_state_dirty = false
		_send_all("_horde_state", [run_level, run_xp])
	if frozen:
		lv_left -= delta
		if lv_left <= 0.0 or _all_lv_ready():
			_end_freeze()
		return
	if _lv_pending > 0:
		_begin_freeze()
		return
	if phase == "break":
		_break_t -= delta
		if _break_t <= 0.0 or _all_ready():
			_start_round()
		return
	if phase != "fight":
		return
	elapsed += delta
	round_left = max(0.0, round_left - delta)
	if round_left <= 0.0 and not boss_alive():
		_end_round()
		return
	_event_tick(delta)
	if not targets().is_empty():
		_spawn_tick(delta)


## Mais jogadores, mais inimigos (e um pouco mais resistentes).
func _spawn_tick(delta: float) -> void:
	var n := _team_size()
	var rate := (0.9 + 0.35 * (round_num - 1)) * (1.0 + 0.6 * (n - 1))
	if boss_alive():
		rate *= 0.5
	if event == "enxame":
		rate *= 2.0
	_spawn_acc += rate * delta
	var cap: int = min(80 + 25 * (n - 1), int((18 + round_num * 8) * (1.0 + 0.5 * (n - 1))))
	if event == "enxame":
		cap = int(cap * 1.5)
	while _spawn_acc >= 1.0:
		_spawn_acc -= 1.0
		if alive_count() < cap:
			_spawn_enemy(_pick_kind(), _spawn_point())


func alive_count() -> int:
	var n := 0
	if role == "client":
		for e in Network.enemies.values():
			if is_instance_valid(e) and e.horde and not e.dead:
				n += 1
		return n
	for c in get_children():
		if c is Enemy and not c.dead:
			n += 1
	return n


func _pick_kind() -> String:
	if event == "enxame" and randf() < 0.65:
		return "slime_veloz"
	var r := round_num
	var table := [["slime", 1.0]]
	if r >= 2:
		table.append(["slime_veloz", 0.3])
	if r >= 3:
		table.append(["goblin", 0.35 + 0.05 * r])
		table.append(["slime_explosivo", 0.12 + 0.02 * r])
	if r >= 4:
		table.append(["slime_grande", 0.2 + 0.03 * r])
		table.append(["goblin_arqueiro", 0.12 + 0.02 * r])
	if r >= 6:
		table.append(["slime_mae", 0.15])
		table.append(["goblin_xama", 0.06 + 0.01 * r])
	var total := 0.0
	for t in table:
		total += t[1]
	var x := randf() * total
	for t in table:
		x -= t[1]
		if x <= 0.0:
			return t[0]
	return "slime"


## Posição de um jogador vivo (no servidor, um sorteado do grupo) para nascer inimigos em volta.
func _focus_pos() -> Vector3:
	var t := targets()
	if t.is_empty():
		return player.global_position if player else center
	return t.pick_random().global_position


func _spawn_point() -> Vector3:
	var p := _focus_pos()
	for i in 8:
		var a := randf() * TAU
		var q := p + Vector3(cos(a), 0, sin(a)) * randf_range(16.0, 24.0)
		if Vector2(q.x - center.x, q.z - center.z).length() < ARENA_RADIUS - 1.0:
			return Vector3(q.x, 0.2, q.z)
	# jogador encostado na borda: nasce do lado oposto da arena
	var away := (center - p)
	away.y = 0
	var dir := away.normalized() if away.length() > 0.1 else Vector3.FORWARD
	var q2 := center + dir.rotated(Vector3.UP, randf_range(-0.8, 0.8)) * (ARENA_RADIUS - 3.0)
	return Vector3(q2.x, 0.2, q2.z)


## Ponto dentro da arena (puxa para dentro o que cair perto da borda).
func _clamp_arena(q: Vector3, margin := 2.0) -> Vector3:
	var off := q - center
	off.y = 0
	if off.length() > ARENA_RADIUS - margin:
		off = off.normalized() * (ARENA_RADIUS - margin)
	return Vector3(center.x + off.x, 0.2, center.z + off.z)


## hp_mult < 0: escala normal da rodada. Tudo é definido antes de entrar na árvore: no servidor o
## inimigo é anunciado aos clientes (com a vida máxima) assim que entra.
func _spawn_enemy(kind: String, pos: Vector3, hp_mult := -1.0, dmg_mult := -1.0) -> Enemy:
	var e: Enemy = ENEMY.new()
	e.kind = kind
	e.horde = true
	var team_hp := 1.0 + 0.3 * (_team_size() - 1)
	e.hp_mult = (hp_mult if hp_mult > 0.0 else 1.0 + 0.25 * (round_num - 1)) * team_hp
	e.dmg_mult = dmg_mult if dmg_mult > 0.0 else 1.0 + 0.12 * (round_num - 1)
	match event:
		"lua_sangue":
			e.speed_mult = 1.3
			e.dmg_mult *= 1.25
		"enxame":
			if hp_mult <= 0.0:
				e.hp_mult *= 0.6
	e.position = pos
	add_child(e)
	e.died.connect(_on_enemy_died)
	FX.burst(pos + Vector3.UP * 0.4, Color(0.5, 0.3, 0.7), 8, 3.0, 0.1, 0.5)
	return e


func _spawn_boss() -> void:
	var p := _focus_pos()
	var away := center - p
	away.y = 0
	var dir := away.normalized() if away.length() > 2.0 else Vector3.FORWARD
	var pos := p + dir * 14.0
	var q := pos - center
	q.y = 0
	if q.length() > ARENA_RADIUS - 3.0:
		pos = center + q.normalized() * (ARENA_RADIUS - 3.0)
	var tier: int = round_num / BOSS_EVERY
	# vida base do rei (900) x (0.8 + 0.6 por chefe já enfrentado)
	boss = _spawn_enemy("goblin_king", Vector3(pos.x, 0.3, pos.z), 0.8 + 0.6 * tier, 0.9 + 0.15 * tier)
	FX.ring(boss.global_position, Color(1, 0.3, 0.1, 0.9), 6.0, 0.8)
	if role != "server" and world and world.hud:
		world.hud.boss = boss


## Chamado pelo Rei Goblin enfurecido (get_parent().summon_minions).
func summon_minions(pos: Vector3, n: int) -> void:
	if phase == "over":
		return
	for i in n + 1:
		var a := TAU * i / (n + 1)
		_spawn_enemy("goblin", pos + Vector3(cos(a) * 4.0, 0.3, sin(a) * 4.0))


func _end_round() -> void:
	phase = "break"
	rounds_cleared += 1
	_clear_meteors()
	for c in get_children():
		if c is Enemy and not c.dead:
			if c.kind == "goblin_dourado":
				c.escaped = true   # o pulso de fim de rodada não entrega o tesouro de graça
			c._die()
	if role == "server":
		_break_t = BREAK_TIMEOUT
		for pid in team:
			team[pid].dead = false   # quem caiu volta no fim da rodada
			team[pid].ready = false
		print("[server] Desafio da Horda: rodada %d concluída (%d abates)" % [round_num, kills])
		_send_all("_horde_round_end", [round_num, BREAK_TIMEOUT])
		_send_team()
		return
	_round_cleared()


## Solo e cliente: efeitos, cura, sementes e a escolha da bênção.
func _round_cleared() -> void:
	Game.notify.emit("Rodada %d concluída!" % round_num, Color(0.6, 1, 0.6))
	Sfx.play("levelup", 0.0)
	if player.dead:
		player.revive(center + _slot_offset() + Vector3.UP * 0.5)
		Game.hp = Game.max_hp() * 0.5
		Game.notify.emit("Seu grupo sobreviveu: você está de volta!", Color(0.6, 1, 0.8))
	FX.ring(player.global_position, Color(0.9, 0.7, 1.0, 0.9), ARENA_RADIUS, 0.9)
	player.add_shake(0.25)
	Game.hp = min(Game.max_hp(), Game.hp + Game.max_hp() * 0.3)
	Game.stats_changed.emit()
	_reward_seeds(1 + round_num / 3)
	await get_tree().create_timer(0.9, false).timeout
	if phase != "break":
		return
	vacuum_gems()
	await get_tree().create_timer(1.2, false).timeout
	if phase != "break":
		return
	_queue.append("round")
	_try_open_next()


# ================================================================ eventos e Caçada (solo e servidor)
func _setup_event() -> void:
	_meteor_t = 2.5
	_gold_spawns = []
	_champ_spawns = []
	match event:
		"febre_ouro":
			_gold_spawns = [3.0, round_time * 0.35, round_time * 0.65]
		"campeoes":
			_champ_spawns = [1.5, round_time * 0.5]


## O que acontece logo no começo da rodada.
func _event_start() -> void:
	if role == "client":
		return
	if event == "emboscada":
		var n: int = 7 + round_num
		for t in (targets() if not targets().is_empty() else [player]):
			if t == null:
				continue
			for i in n:
				var a := TAU * i / n
				var q: Vector3 = t.global_position + Vector3(cos(a), 0, sin(a)) * 9.0
				_spawn_enemy(_pick_kind(), _clamp_arena(q))


func _event_tick(delta: float) -> void:
	_round_t += delta
	match event:
		"meteoros":
			_meteor_t -= delta
			if _meteor_t <= 0.0:
				_meteor_t = maxf(0.55, 1.5 - 0.25 * (_team_size() - 1))
				var p := _focus_pos() + Vector3(randf_range(-3.5, 3.5), 0, randf_range(-3.5, 3.5))
				_drop_meteor(_clamp_arena(p, 1.0))
	if not _gold_spawns.is_empty() and _round_t >= _gold_spawns[0]:
		_gold_spawns.pop_front()
		var g := _spawn_enemy("goblin_dourado", _spawn_point(), 1.0 + 0.2 * round_num)
		_say("Um Goblin Dourado apareceu! Pegue-o antes que fuja!", Color(1, 0.85, 0.3))
		FX.ring(g.global_position, Color(1, 0.85, 0.3, 0.9), 3.0, 0.6)
	if not _champ_spawns.is_empty() and _round_t >= _champ_spawns[0]:
		_champ_spawns.pop_front()
		for i in 1 + (_team_size() - 1) / 2:
			_spawn_enemy("goblin_campeao", _spawn_point())
		_say("Um Campeão Goblin entrou na arena!", Color(1, 0.45, 0.3))
	for c in get_children():
		if c is Enemy and c.kind == "goblin_dourado" and not c.dead and c.born_t > GOLD_ESCAPE:
			c.escaped = true
			FX.burst(c.global_position + Vector3.UP, Color(1, 0.85, 0.3), 30, 5.0, 0.12, 0.8, 2.0)
			c._die()
			_say("O Goblin Dourado escapou...", Color(0.85, 0.75, 0.5))
	_update_meteors(delta)


## Aviso para quem está jogando (no servidor, para o grupo).
func _say(text: String, color: Color) -> void:
	if role == "server":
		_send_all("_horde_fx", ["say:" + text, Vector3(color.r, color.g, color.b)])
	else:
		Game.notify.emit(text, color)


func _drop_meteor(pos: Vector3) -> void:
	if role == "server":
		_send_all("_horde_fx", ["meteor", pos])
		_meteors.append({"pos": pos, "t": METEOR_FALL, "node": null})
		return
	_meteor_visual(pos)


## Cliente e solo: círculo de aviso e a pedra caindo do céu.
func _meteor_visual(pos: Vector3) -> void:
	FX.telegraph(pos, METEOR_RADIUS, METEOR_FALL)
	var rock := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.7
	s.height = 1.4
	s.radial_segments = 8
	s.rings = 4
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.35, 0.18, 0.1)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.45, 0.1)
	m.emission_energy_multiplier = 2.5
	s.material = m
	rock.mesh = s
	add_child(rock)
	rock.global_position = pos + Vector3(6, 28, 3)
	_meteors.append({"pos": pos, "t": METEOR_FALL, "node": rock})


func _update_meteors(delta: float) -> void:
	for i in range(_meteors.size() - 1, -1, -1):
		var m: Dictionary = _meteors[i]
		m.t -= delta
		var node: Node3D = m.node
		if node and is_instance_valid(node):
			var k := clampf(1.0 - m.t / METEOR_FALL, 0.0, 1.0)
			node.global_position = (m.pos + Vector3(6, 28, 3)).lerp(m.pos + Vector3.UP * 0.4, k * k)
		if m.t <= 0.0:
			_meteors.remove_at(i)
			if node and is_instance_valid(node):
				node.queue_free()
			_meteor_impact(m.pos)


func _meteor_impact(pos: Vector3) -> void:
	if role != "server":
		Sfx.play_at("explode", pos, 0.15, -3.0)
		FX.ring(pos, Color(1.0, 0.5, 0.15, 0.95), METEOR_RADIUS, 0.4)
		FX.burst(pos + Vector3.UP * 0.3, Color(1.0, 0.45, 0.1), 40, 7.0, 0.16, 0.7)
		FX.burst(pos + Vector3.UP * 0.3, Color(0.3, 0.25, 0.2), 16, 3.0, 0.25, 1.0, 1.0)
		if player and player.global_position.distance_to(pos) < 10.0:
			player.add_shake(0.3)
	if role == "client":
		return
	for t in targets():
		if t.global_position.distance_to(pos) <= METEOR_RADIUS:
			t.take_damage(16.0 + 3.0 * round_num, pos)
	for c in get_children():
		if c is Enemy and not c.dead and not c.is_boss and c.global_position.distance_to(pos) <= METEOR_RADIUS:
			c.take_damage(60.0 + 12.0 * round_num, pos, false)


func _clear_meteors() -> void:
	for m in _meteors:
		if m.node and is_instance_valid(m.node):
			m.node.queue_free()
	_meteors.clear()


func _hunt_complete() -> void:
	if role == "server":
		print("[server] Desafio da Horda: Caçada concluída na rodada %d" % round_num)
		_send_all("_horde_bonus", ["cacada"])
		return
	_hunt_reward()


## Solo e cliente: baú da Caçada — gemas, moedas e um coração em volta do jogador.
func _hunt_reward() -> void:
	hunt_done = true
	hunts_won += 1
	Game.notify.emit("Caçada concluída! Um baú de recompensas se abre.", EVT.HUNT.color)
	Sfx.play("levelup", 0.0)
	if player == null:
		return
	var pos := player.global_position + Vector3.UP * 0.8
	FX.ring(player.global_position, Color(0.5, 0.9, 1.0, 0.9), 5.0, 0.6)
	FX.burst(pos, Color(1.0, 0.85, 0.3), 40, 5.0, 0.12, 0.9, 3.0)
	for i in 6:
		_drop_gem("xp", 5 + round_num, pos)
	_drop_gem("heal", 0, pos)
	_drop_coin(pos, randi_range(8, 14) + 2 * round_num)


# ---------------------------------------------------------------- cliente: mensagens do servidor
func net_round_start(n: int, t: float, ev: String, hunt: int) -> void:
	if phase == "over":
		return
	# bênção que ficou aberta (o tempo do intervalo acabou): sorteia
	if world.modal != null and world.modal.get_script() == UI and world.modal.mode == "round":
		world.modal.auto_pick()
	_queue.erase("round")
	round_num = n
	round_time = t
	round_left = t
	phase = "fight"
	waiting = false
	event = ev if EVT.EVENTS.has(ev) else ""
	hunt_target = hunt
	hunt_kills = 0
	hunt_done = false
	_round_t = 0.0
	break_left = 0.0
	_announce_round(n % BOSS_EVERY == 0)


func net_round_end(n: int, break_t: float) -> void:
	if phase == "over":
		return
	round_num = n
	phase = "break"
	rounds_cleared += 1
	_clear_meteors()
	break_left = break_t
	break_total = maxf(break_t, 1.0)
	_round_cleared()


func net_kill(kind: String, pos: Vector3, was_boss: bool) -> void:
	if phase == "over":
		return
	kills += 1
	if phase == "fight" and hunt_target > 0 and not hunt_done:
		hunt_kills += 1
	_kill_drops(kind, pos, was_boss)


func net_team(t: Dictionary) -> void:
	team = t


func net_state(level: int, xp: float) -> void:
	run_level = level
	run_xp = xp


func net_fx(kind: String, pos: Vector3) -> void:
	if phase == "over":
		return
	if kind == "meteor":
		_meteor_visual(pos)
	elif kind.begins_with("say:"):
		Game.notify.emit(kind.substr(4), Color(pos.x, pos.y, pos.z))


func net_bonus(kind: String) -> void:
	if kind == "cacada" and phase != "over":
		_hunt_reward()


## O grupo subiu de nível: a horda congela e cada um escolhe a(s) carta(s).
func net_levelup(level: int, xp: float, picks: int, timeout: float) -> void:
	if phase == "over":
		return
	run_level = level
	run_xp = xp
	frozen = true
	lv_waiting = false
	lv_left = timeout
	lv_total = maxf(timeout, 1.0)
	_lv_picks_left += picks
	for i in picks:
		_queue.push_front("levelup")
	Sfx.play("levelup", 0.0)
	FX.ring(player.global_position, Color(0.4, 0.8, 1.0, 0.9), 3.0, 0.6)
	FX.burst(player.global_position + Vector3.UP * 0.2, Color(0.4, 0.8, 1.0), 40, 5.0, 0.1, 1.0, 3.0)
	Game.notify.emit("O grupo subiu para o nível %d! A horda para até todos escolherem." % level, Color(0.5, 0.85, 1.0))
	# inventário, pausa etc. fecham: a escolha é para todos ao mesmo tempo
	if world.modal != null and world.modal.get_script() != UI:
		world.modal.queue_free()
		world._on_modal_closed()
	_try_open_next.call_deferred()


## Todos escolheram (ou o tempo acabou): a horda volta a se mover.
func net_resume(level: int, xp: float) -> void:
	run_level = level
	run_xp = xp
	if not frozen:
		return
	frozen = false
	lv_waiting = false
	lv_left = 0.0
	var forced := 0
	if world.modal != null and world.modal.get_script() == UI and world.modal.mode == "levelup":
		world.modal.auto_pick()
		forced += 1
	while _queue.has("levelup"):
		_queue.erase("levelup")
		choose(UPG.roll_level_choices(weapon_levels, passive_levels).pick_random())
		forced += 1
	_lv_picks_left = 0
	if forced > 0:
		Game.notify.emit("Tempo esgotado: carta escolhida ao acaso.", Color(1, 0.75, 0.45))
	if player:
		player.horde_frozen = false
	_try_open_next.call_deferred()


# ================================================================ abates, gemas e XP
func _on_enemy_died(e: Enemy) -> void:
	if phase == "over":
		return
	if e.escaped:
		return
	kills += 1
	if phase == "fight" and hunt_target > 0 and not hunt_done:
		hunt_kills += 1
		if hunt_kills >= hunt_target:
			hunt_done = true
			_hunt_complete()
	var pos := e.global_position + Vector3.UP * 0.6
	# Slime Mãe se divide ao morrer
	if e.data.has("split") and phase == "fight":
		_split.call_deferred(e.data.split[0], int(e.data.split[1]), e.global_position)
	if role == "server":
		# cada jogador solta e coleta as próprias gemas (como o loot pessoal do RPG)
		_send_all("_horde_kill", [e.kind, pos, e.is_boss])
		return
	_kill_drops(e.kind, pos, e.is_boss)


func _split(kind: String, n: int, pos: Vector3) -> void:
	if phase != "fight":
		return
	for i in n:
		var a := TAU * i / n + randf() * 0.5
		_spawn_enemy(kind, _clamp_arena(pos + Vector3(cos(a), 0, sin(a)) * 1.2, 1.0))


func _kill_drops(kind: String, pos: Vector3, was_boss: bool) -> void:
	if Game.mod("lifesteal") > 0.0 and not player.dead:
		Game.hp = min(Game.max_hp(), Game.hp + Game.mod("lifesteal"))
	var xp_mult := 2 if event == "lua_sangue" else 1
	if was_boss:
		Game.notify.emit("Rei Goblin derrotado!", Color(1, 0.85, 0.3))
		for i in 8:
			_drop_gem("xp", 20, pos)
		_drop_gem("heal", 0, pos)
		_drop_gem("magnet", 0, pos)
		_drop_coin(pos, randi_range(20, 35))
		_reward_seeds(2, "seed_pumpkin")
		return
	match kind:
		"goblin_dourado":
			Game.notify.emit("Goblin Dourado abatido! Chuva de ouro!", Color(1, 0.85, 0.3))
			for i in 3:
				_drop_coin(pos, randi_range(8, 15) + round_num)
			for i in 3:
				_drop_gem("xp", 20 * xp_mult, pos)
			_drop_gem("magnet", 0, pos)
			return
		"goblin_campeao":
			for i in 4:
				_drop_gem("xp", 20 * xp_mult, pos)
			_drop_coin(pos, randi_range(8, 15))
			if randf() < 0.5:
				_drop_gem("heal", 0, pos)
			return
	var value := 1
	match kind:
		"goblin", "slime_grande", "goblin_arqueiro", "goblin_xama", "slime_mae":
			value = 20 if randf() < 0.08 else 5
		_:
			value = 5 if randf() < 0.04 else 1
	_drop_gem("xp", value * xp_mult, pos)
	var r := randf()
	var coin_chance := 0.24 if event == "febre_ouro" else 0.08
	if r < 0.012:
		_drop_gem("heal", 0, pos)
	elif r < 0.019:
		_drop_gem("magnet", 0, pos)
	elif r < coin_chance:
		_drop_coin(pos, randi_range(1, 3))


## Sementes de recompensa (levadas para a Horta). Rodadas mais altas liberam sementes raras.
func _reward_seeds(n: int, first := "") -> void:
	var pool := ["seed_carrot", "seed_wheat", "seed_tomato"]
	if round_num >= 3:
		pool += ["seed_pepper", "seed_mint"]
	if round_num >= 5:
		pool.append("seed_pumpkin")
	var got := {}
	for i in n:
		var id: String = first if (i == 0 and first != "") else pool.pick_random()
		got[id] = got.get(id, 0) + 1
	var parts: Array[String] = []
	for id in got:
		Game.add_item(id, got[id], true)
		seeds_won += got[id]
		parts.append("%s x%d" % [ItemDB.get_item(id).name, got[id]])
	Game.notify.emit("Recompensa: " + ", ".join(parts), Color(0.75, 1.0, 0.5))


func _drop_gem(kind: String, value: int, pos: Vector3) -> void:
	var g := GEM.new()
	g.kind = kind
	g.value = value
	g.survival = self
	g.position = pos
	add_child(g)


func _drop_coin(pos: Vector3, amount: int) -> void:
	var p := PICKUP.new()
	p.item_id = ""
	p.amount = max(1, int(round(amount * Game.mod("gold"))))
	add_child(p)
	p.global_position = pos


func vacuum_gems() -> void:
	for g in get_tree().get_nodes_in_group("xp_gems"):
		g.pulled = true


func collect_gem(g: Node) -> void:
	if phase == "over":
		return
	match g.kind:
		"heal":
			var amount := Game.max_hp() * 0.25
			Game.hp = min(Game.max_hp(), Game.hp + amount)
			FX.damage_number(player.global_position + Vector3.UP * 2.2, "+%d" % amount, Color(0.4, 1.0, 0.5))
			Sfx.play("heal", 0.0)
			Game.stats_changed.emit()
		"magnet":
			vacuum_gems()
			Sfx.play("pickup", 0.0)
		_:
			if _gem_sfx <= 0.0:
				_gem_sfx = 0.05
				Sfx.play("gem", 0.12, -6.0)
			add_xp(g.value)


func xp_needed() -> int:
	return int(6 + (run_level - 1) * 8 + pow(run_level - 1, 1.4))


## Solo: soma no nível da partida. Cliente: o XP vai para o nível do grupo, no servidor.
func add_xp(amount: float) -> void:
	if role == "client":
		_xp_out += amount * Game.mod("xp")
		return
	if role == "server":
		return
	run_xp += amount * Game.mod("xp")
	var leveled := false
	while run_xp >= xp_needed():
		run_xp -= xp_needed()
		run_level += 1
		_queue.append("levelup")
		leveled = true
	if leveled:
		Sfx.play("levelup", 0.0)
		FX.ring(player.global_position, Color(0.4, 0.8, 1.0, 0.9), 3.0, 0.6)
		FX.burst(player.global_position + Vector3.UP * 0.2, Color(0.4, 0.8, 1.0), 40, 5.0, 0.1, 1.0, 3.0)
		_try_open_next.call_deferred()


# ================================================================ escolhas
func _try_open_next() -> void:
	if _queue.is_empty() or phase == "over" or world.modal != null:
		return
	# no grupo, quem está caído também escolhe as cartas de nível (o jogo espera por todos)
	if player.dead and not (role == "client" and _queue[0] == "levelup"):
		return
	var mode: String = _queue.pop_front()
	var ui = UI.new()
	ui.mode = mode
	ui.survival = self
	if mode == "levelup":
		ui.choices = UPG.roll_level_choices(weapon_levels, passive_levels)
	else:
		ui.choices = UPG.roll_blessings()
	world._open_modal(ui)
	ui.closed.connect(_on_choice_closed.bind(mode))


func describe(choice: Dictionary) -> Dictionary:
	return UPG.describe(choice, weapon_levels, passive_levels, blessing_counts)


## Chamado pela tela de cartas.
func choose(choice: Dictionary) -> void:
	_apply(choice)
	Sfx.play("pickup", 0.0)


func _on_choice_closed(mode: String) -> void:
	if phase == "over":
		return
	if mode == "levelup" and role == "client":
		_lv_picks_left = maxi(0, _lv_picks_left - 1)
		if _lv_picks_left == 0 and frozen and not lv_waiting:
			lv_waiting = true
			Network.horde_send("lv_ready")
	if mode == "round" and phase == "break":
		if role == "client":
			# a próxima rodada começa quando todo o grupo escolher (ou o servidor cansar de esperar)
			waiting = true
			Network.horde_send("ready")
		else:
			_start_round()
	if role == "client" and frozen:
		player.horde_frozen = true
	_try_open_next.call_deferred()


func _apply(choice: Dictionary) -> void:
	var old_max := Game.max_hp()
	match choice.type:
		"weapon":
			var lv: int = weapon_levels.get(choice.id, 0) + 1
			weapon_levels[choice.id] = lv
			weapons.set_level(choice.id, lv)
		"passive":
			passive_levels[choice.id] = passive_levels.get(choice.id, 0) + 1
			_add_mods(UPG.PASSIVES[choice.id].add)
		"blessing":
			blessing_counts[choice.id] = blessing_counts.get(choice.id, 0) + 1
			var b: Dictionary = UPG.BLESSINGS[choice.id]
			_add_mods(b.add)
			if b.get("heal", false):
				Game.hp = Game.max_hp()
		"heal":
			Game.hp = min(Game.max_hp(), Game.hp + Game.max_hp() * 0.4)
	if Game.max_hp() > old_max:
		Game.hp += Game.max_hp() - old_max
	Game.hp = min(Game.hp, Game.max_hp())
	Game.stats_changed.emit()
	if weapons:
		weapons.send_gear()


func _add_mods(add: Dictionary) -> void:
	for k in add:
		Game.run_mods[k] += add[k]


# ================================================================ fim da partida
func on_player_died() -> void:
	if phase == "over":
		return
	if role == "client":
		# no grupo, cair não encerra: volta no fim da rodada se alguém sobreviver
		Network.horde_send("dead")
		if team.size() > 1:
			Game.notify.emit("Você caiu! Se o grupo sobreviver à rodada, você volta.", Color(1, 0.55, 0.45))
		return
	phase = "over"
	_queue.clear()
	await get_tree().create_timer(1.6).timeout
	end_run("death")


## reason: "death" | "retreat" | "quit". from_server: o servidor encerrou a partida do grupo
## (então não precisa avisá-lo de volta).
func end_run(reason: String, from_server := false) -> void:
	if end_reason != "":
		return
	if role == "server":
		_server_end(reason)
		return
	if role == "client" and not from_server:
		Network.horde_send("leave")
	end_reason = reason
	phase = "over"
	frozen = false
	if player:
		player.horde_frozen = false
	_queue.clear()
	_clear_meteors()
	var xp_reward := kills * 2 + rounds_cleared * 25 + hunts_won * 20
	rewards = {"xp": xp_reward, "gold": max(0, Game.gold - _gold_start)}
	var best: Dictionary = Game.flags.get("horde_best", {})
	var best_round := int(best.get("round", -1))
	if rounds_cleared > best_round or (rounds_cleared == best_round and kills > int(best.get("kills", 0))):
		new_record = true
		Game.flags["horde_best"] = {"round": rounds_cleared, "kills": kills, "time": int(elapsed), "level": run_level}
	_open_results.call_deferred()


func _open_results() -> void:
	if world.modal != null:
		world.modal.queue_free()
		world.modal = null
	var ui = UI.new()
	ui.mode = "results"
	ui.survival = self
	world._open_modal(ui)
	ui.closed.connect(_return_to_village)


func _return_to_village() -> void:
	if weapons:
		weapons.clear_gear()
		weapons.queue_free()
	Game.reset_run_mods()
	if world.hud and world.hud.boss == boss:
		world.hud.boss = null
	player.horde_frozen = false
	player.revive(world.VILLAGE_SPAWN)
	player.invuln = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	world.survival = null
	queue_free()
	Game.notify.emit("Desafio encerrado: %d rodadas, %d abates." % [rounds_cleared, kills], Color(0.85, 0.6, 1.0))
	if rewards.gold > 0:
		Game.notify.emit("+%d ouro coletado" % rewards.gold, Color(1, 0.85, 0.3))
	if rewards.xp > 0:
		Game.add_xp(rewards.xp)


# ================================================================ servidor: grupo
func _send_all(method: String, args: Array) -> void:
	for pid in team.keys():
		Network.horde_rpc(pid, method, args)


func _send_team() -> void:
	_send_all("_horde_team", [team])


func _all_ready() -> bool:
	for pid in team:
		if not team[pid].ready:
			return false
	return true


func _all_lv_ready() -> bool:
	for pid in team:
		if not team[pid].get("lv_ready", true):
			return false
	return true


## XP das gemas de um jogador. O nível é do grupo: cada um traz a sua parte (dividida pelo tamanho
## do grupo, já que cada jogador vê as gemas de todos os abates).
func server_add_xp(pid: int, amount: float) -> void:
	if phase == "over" or not team.has(pid):
		return
	run_xp += clampf(amount, 0.0, 500.0) / float(_team_size())
	while run_xp >= xp_needed():
		run_xp -= xp_needed()
		run_level += 1
		_lv_pending += 1
	_state_dirty = true


func _begin_freeze() -> void:
	var picks := _lv_pending
	_lv_pending = 0
	frozen = true
	lv_left = Network.horde_pick_time
	for pid in team:
		team[pid].lv_ready = false
	print("[server] Desafio da Horda: grupo subiu para o nível %d (%d carta(s)), horda congelada" % [run_level, picks])
	_send_all("_horde_levelup", [run_level, run_xp, picks, Network.horde_pick_time])
	_send_team()


func _end_freeze() -> void:
	frozen = false
	var missing: Array[String] = []
	for pid in team:
		if not team[pid].get("lv_ready", true):
			missing.append(str(team[pid].name))
		team[pid].lv_ready = true
	if not missing.is_empty():
		print("[server] Desafio da Horda: tempo de escolha esgotado (%s)" % ", ".join(missing))
	_send_all("_horde_resume", [run_level, run_xp])
	_send_team()


func server_player_lv_ready(pid: int) -> void:
	if team.has(pid) and frozen:
		team[pid].lv_ready = true
		_send_team()


func server_player_dead(pid: int) -> void:
	if not team.has(pid) or phase != "fight":
		return
	team[pid].dead = true
	_send_team()
	_check_wipe()


func server_player_ready(pid: int) -> void:
	if team.has(pid) and phase == "break":
		team[pid].ready = true
		_send_team()


## Retirada, abandono ou desconexão de um jogador do grupo.
func server_player_left(pid: int) -> void:
	if not team.has(pid) or phase == "over":
		return
	print("[server] %s saiu do Desafio da Horda" % team[pid].name)
	team.erase(pid)
	if team.is_empty():
		_server_end("quit")
		return
	_send_team()
	_check_wipe()


func _check_wipe() -> void:
	if phase != "fight":
		return
	for pid in team:
		if not team[pid].dead:
			return
	phase = "over"
	await get_tree().create_timer(1.6).timeout
	_server_end("death")


func _server_end(reason: String) -> void:
	if end_reason != "":
		return
	end_reason = reason
	phase = "over"
	frozen = false
	print("[server] Desafio da Horda terminou (%s): %d rodadas, %d abates" % [reason, rounds_cleared, kills])
	_send_all("_horde_over", [reason])
	for c in get_children():
		if c is Enemy and not c.dead:
			c._die()
	if world and world.get("survival") == self:
		world.survival = null
	Network.horde_run_ended(self)
	queue_free()
