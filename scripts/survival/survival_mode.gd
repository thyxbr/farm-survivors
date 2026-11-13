extends Node3D
## Desafio da Horda (estilo "survivors"): rodadas de inimigos sem fim na arena, gemas de XP,
## nível da partida com cartas de melhoria e bênçãos ao fim de cada rodada.
## Criado pelo mundo em start_survival(); fica na origem e é o pai dos inimigos e gemas.
##
## role:
##   "solo"   — offline: faz tudo localmente.
##   "server" — servidor dedicado: dono das rodadas, do spawn e dos abates; não tem jogador local.
##              Os inimigos nascem como filhos deste nó e são replicados pelo Network como os outros.
##   "client" — multiplayer: jogador local, armas automáticas, gemas, XP da partida, cartas e bênçãos
##              (cada jogador tem os seus). Rodadas e abates chegam do servidor via Network.

const ENEMY := preload("res://scripts/enemies/enemy.gd")
const GEM := preload("res://scripts/survival/xp_gem.gd")
const PICKUP := preload("res://scripts/world/pickup.gd")
const UPG := preload("res://scripts/survival/upgrades.gd")
const WEAPONS := preload("res://scripts/survival/auto_weapons.gd")
const UI := preload("res://scripts/ui/survival_ui.gd")
const HUD := preload("res://scripts/ui/survival_hud.gd")

const ARENA_RADIUS := 31.0
const BOSS_EVERY := 5
## Ritmo em "dente de serra" dentro de cada ciclo de 5 rodadas: a pressão sobe até a rodada 4 do ciclo e
## alivia na rodada do chefe (que já é o desafio). Cada ciclo começa mais forte que o anterior.
const SAW := [0.85, 1.0, 1.1, 1.25, 0.7]
## Servidor: tempo máximo esperando todos escolherem a bênção antes de começar a próxima rodada.
const BREAK_TIMEOUT := 30.0

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

## Multiplayer: peer_id -> {"name": String, "dead": bool, "ready": bool} (no cliente, a cópia do servidor).
var team := {}
## Cliente: posição na roda de chegada (para o grupo não nascer empilhado).
var my_slot := 0
## Cliente: já escolheu a bênção e espera os outros jogadores.
var waiting := false
## Maldição da rodada atual (id em UPG.AFFIXES, "" = nenhuma).
var affix := ""
## Placar local (solo): dano causado. No grupo, dano/abates/quedas vêm do servidor em team[pid].
var my_dmg := 0.0
var combos_done := 0
## Cliente: combos formados com o grupo. combo -> {"partner", "near", "mine": [armas], "plv"}
var active_combos := {}
var _known_combos := {}
var _combo_t := 0.0
var _build_t := 0.0
var _team_t := 0.0
var _siege_done := false

var _queue: Array = []        # "levelup" | "round"
var _spawn_acc := 0.0
var _gold_start := 0
var _gem_sfx := 0.0
var _break_t := 0.0


func _ready() -> void:
	if role == "server":
		for pid in team:
			team[pid].merge({"dmg": 0.0, "kills": 0, "falls": 0, "build": {}})
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
		Game.notify.emit("Desafio da Horda em grupo: %s." % ", ".join(_names()), Color(0.85, 0.6, 1.0))
		return
	Game.notify.emit("Desafio da Horda! Sobreviva o máximo que puder.", Color(0.85, 0.6, 1.0))
	_start_round()


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


# ================================================================ rodadas
## Solo e servidor: começa a próxima rodada (no cliente, ela chega em net_round_start).
func _start_round() -> void:
	round_num += 1
	round_left = round_time
	phase = "fight"
	_spawn_acc = 0.0
	_siege_done = false
	var boss_round := round_num % BOSS_EVERY == 0
	affix = ""
	if round_num >= UPG.AFFIX_FROM and not boss_round:
		affix = UPG.AFFIXES.keys().pick_random()
	if boss_round:
		_spawn_boss()
	if role == "server":
		for pid in team:
			team[pid].dead = false
			team[pid].ready = false
		_send_all("_horde_round_start", [round_num, round_time, affix])
		_send_team()
		return
	_announce_round(boss_round)


func _announce_round(boss_round: bool) -> void:
	if boss_round:
		Game.notify.emit("Rodada %d — o Rei Goblin chegou!" % round_num, Color(1, 0.45, 0.3))
	else:
		Game.notify.emit("Rodada %d" % round_num, Color(1, 0.85, 0.4))
	if affix != "":
		var a: Dictionary = UPG.AFFIXES[affix]
		Game.notify.emit("Maldição: %s — %s" % [a.name, a.desc], Color(1, 0.5, 0.4))
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
		# só o relógio da HUD: o fim da rodada é decidido pelo servidor
		if phase == "fight":
			elapsed += delta
			round_left = max(0.0, round_left - delta)
		_combo_t -= delta
		if _combo_t <= 0.0:
			_combo_t = 0.25
			_update_combos()
		_build_t -= delta
		if _build_t <= 0.0:
			send_build()
		return
	if phase != "fight" or player.dead:
		return
	elapsed += delta
	round_left = max(0.0, round_left - delta)
	if round_left <= 0.0 and not boss_alive():
		_end_round()
		return
	_spawn_tick(delta)


func _server_process(delta: float) -> void:
	# placar (dano, abates, builds) para o Tab de todos
	_team_t -= delta
	if _team_t <= 0.0:
		_team_t = 1.0
		_send_team()
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
	if not targets().is_empty():
		_spawn_tick(delta)


## Mais jogadores, mais inimigos (e mais resistentes). O ritmo segue o dente de serra (SAW) e a maldição.
func _spawn_tick(delta: float) -> void:
	var n := _team_size()
	var rate := (1.0 + 0.42 * (round_num - 1)) * float(SAW[(round_num - 1) % BOSS_EVERY]) \
		* (1.0 + 0.7 * (n - 1)) * _affix_val("rate")
	if boss_alive():
		rate *= 0.5
	_spawn_acc += rate * delta
	var cap: int = min(90 + 30 * (n - 1), int((20 + round_num * 9) * (1.0 + 0.5 * (n - 1))))
	while _spawn_acc >= 1.0:
		_spawn_acc -= 1.0
		if alive_count() < cap:
			_spawn_enemy(_pick_kind(), _spawn_point(), -1.0, -1.0, randf() < elite_chance())
	# cerco: uma vez por rodada (a partir da 3ª), um anel de inimigos fecha em volta de alguém
	if not _siege_done and round_num >= 3 and round_left <= round_time * 0.55 and not boss_alive():
		_siege_done = true
		_start_siege()


# ---------------------------------------------------------------- escala de dificuldade
## Vida: cresce um pouco mais rápido que linear, para a partida ter um fim natural lá pela rodada 15-20.
func hp_scale() -> float:
	var r := float(round_num - 1)
	return 1.0 + 0.3 * r + 0.012 * r * r


func dmg_scale() -> float:
	return 1.0 + 0.14 * (round_num - 1)


func speed_scale() -> float:
	return 1.0 + minf(0.25, 0.015 * (round_num - 1))


func elite_chance() -> float:
	if round_num < 3:
		return 0.0
	return minf(0.12, 0.015 + 0.008 * (round_num - 3)) * _affix_val("elite")


func _affix_val(k: String) -> float:
	return float(UPG.AFFIXES.get(affix, {}).get(k, 1.0))


func _start_siege() -> void:
	var t := targets()
	if t.is_empty():
		return
	var tgt: Player = t.pick_random()
	_notice("Cerco! A horda fecha um círculo — abram caminho!", Color(1, 0.55, 0.3))
	FX.telegraph(tgt.global_position, 11.0, 1.2)
	await get_tree().create_timer(1.2, false).timeout
	if phase != "fight" or not is_instance_valid(tgt):
		return
	var p := tgt.global_position
	var n: int = min(22, 8 + round_num)
	for i in n:
		var a := TAU * i / n
		var q := p + Vector3(cos(a), 0, sin(a)) * 11.0
		var off := q - center
		off.y = 0
		if off.length() > ARENA_RADIUS - 1.0:
			q = center + off.normalized() * (ARENA_RADIUS - 1.0)
		_spawn_enemy("slime_veloz" if i % 3 == 0 else "slime", Vector3(q.x, 0.2, q.z))


## Aviso para quem está na partida (no servidor, vai para o grupo todo).
func _notice(text: String, color: Color) -> void:
	if role == "server":
		_send_all("_horde_notice", [text])
	else:
		Game.notify.emit(text, color)


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
	var table := [["slime", 1.0]]
	if round_num >= 2:
		table.append(["slime_veloz", 0.3])
	if round_num >= 3:
		table.append(["goblin", 0.35 + 0.05 * round_num])
	if round_num >= 4:
		table.append(["slime_grande", 0.2 + 0.03 * round_num])
	if round_num >= 7:
		table.append(["goblin_bruto", 0.08 + 0.015 * round_num])
	var total := 0.0
	for t in table:
		total += t[1]
	var r := randf() * total
	for t in table:
		r -= t[1]
		if r <= 0.0:
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


## hp_mult < 0: escala normal da rodada. Tudo é definido antes de entrar na árvore: no servidor o
## inimigo é anunciado aos clientes (com a vida máxima) assim que entra.
func _spawn_enemy(kind: String, pos: Vector3, hp_mult := -1.0, dmg_mult := -1.0, elite := false) -> Enemy:
	var e: Enemy = ENEMY.new()
	e.kind = kind
	e.horde = true
	var team_hp := 1.0 + 0.35 * (_team_size() - 1)
	e.hp_mult = (hp_mult if hp_mult > 0.0 else hp_scale() * _affix_val("hp")) * team_hp
	e.dmg_mult = dmg_mult if dmg_mult > 0.0 else dmg_scale() * _affix_val("dmg")
	e.spd_mult = speed_scale() * _affix_val("speed")
	if elite:
		e.elite = true
		e.hp_mult *= 3.2
		e.dmg_mult *= 1.3
		e.spd_mult *= 1.08
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
	# vida base do rei (900) x (0.75 + 0.75 por chefe já enfrentado)
	boss = _spawn_enemy("goblin_king", Vector3(pos.x, 0.3, pos.z), 0.75 + 0.75 * tier, 0.9 + 0.18 * tier)
	FX.ring(boss.global_position, Color(1, 0.3, 0.1, 0.9), 6.0, 0.8)
	# a partir do 2º rei, ele chega com guardas de elite
	if tier >= 2:
		for i in mini(tier, 4):
			var a := TAU * i / mini(tier, 4)
			_spawn_enemy("goblin", Vector3(pos.x + cos(a) * 2.5, 0.3, pos.z + sin(a) * 2.5), -1.0, -1.0, true)
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
	for c in get_children():
		if c is Enemy and not c.dead:
			c._die()
	if role == "server":
		_break_t = BREAK_TIMEOUT
		for pid in team:
			team[pid].dead = false   # quem caiu volta no fim da rodada
			team[pid].ready = false
		print("[server] Desafio da Horda: rodada %d concluída (%d abates)" % [round_num, kills])
		_send_all("_horde_round_end", [round_num])
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


# ---------------------------------------------------------------- cliente: mensagens do servidor
func net_round_start(n: int, t: float, aff := "") -> void:
	if phase == "over":
		return
	round_num = n
	round_time = t
	round_left = t
	phase = "fight"
	waiting = false
	affix = aff if UPG.AFFIXES.has(aff) else ""
	_announce_round(n % BOSS_EVERY == 0)


func net_round_end(n: int) -> void:
	if phase == "over":
		return
	round_num = n
	phase = "break"
	rounds_cleared += 1
	_round_cleared()


func net_kill(kind: String, pos: Vector3, tier: int) -> void:
	if phase == "over":
		return
	kills += 1
	_kill_drops(kind, pos, tier)


func net_team(t: Dictionary) -> void:
	team = t


# ================================================================ abates, gemas e XP
func _on_enemy_died(e: Enemy) -> void:
	if phase == "over":
		return
	kills += 1
	var pos := e.global_position + Vector3.UP * 0.6
	var tier := 2 if e.is_boss else (1 if e.elite else 0)
	if role == "server":
		if team.has(e.last_hitter):
			team[e.last_hitter].kills += 1
		# cada jogador solta e coleta as próprias gemas (como o loot pessoal do RPG)
		_send_all("_horde_kill", [e.kind, pos, tier])
		return
	_kill_drops(e.kind, pos, tier)


## Dano causado à horda (placar). pid = 0 no solo.
func on_enemy_damaged(pid: int, amount: float) -> void:
	if role == "server":
		if team.has(pid):
			team[pid].dmg += amount
	elif role == "solo":
		my_dmg += amount


## tier: 0 comum · 1 elite · 2 chefe.
func _kill_drops(kind: String, pos: Vector3, tier: int) -> void:
	if Game.mod("lifesteal") > 0.0 and not player.dead:
		Game.hp = min(Game.max_hp(), Game.hp + Game.mod("lifesteal"))
	if tier == 1:
		for i in 3:
			_drop_gem("xp", 10, pos)
		if randf() < 0.35:
			_drop_gem("heal", 0, pos)
		_drop_coin(pos, randi_range(3, 8))
		return
	if tier == 2:
		Game.notify.emit("Rei Goblin derrotado!", Color(1, 0.85, 0.3))
		for i in 8:
			_drop_gem("xp", 20, pos)
		_drop_gem("heal", 0, pos)
		_drop_gem("magnet", 0, pos)
		_drop_coin(pos, randi_range(20, 35))
		_reward_seeds(2, "seed_pumpkin")
		return
	var value := 1
	match kind:
		"goblin", "slime_grande":
			value = 20 if randf() < 0.08 else 5
		"goblin_bruto":
			value = 12
		_:
			value = 5 if randf() < 0.04 else 1
	_drop_gem("xp", value, pos)
	var r := randf()
	if r < 0.012:
		_drop_gem("heal", 0, pos)
	elif r < 0.019:
		_drop_gem("magnet", 0, pos)
	elif r < 0.08:
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
	return int(6 + (run_level - 1) * 9 + pow(run_level - 1, 1.45))


func add_xp(amount: float) -> void:
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
	if _queue.is_empty() or phase == "over" or player.dead or world.modal != null:
		return
	var mode: String = _queue.pop_front()
	var ui = UI.new()
	ui.mode = mode
	ui.survival = self
	if mode == "levelup":
		ui.choices = UPG.roll_level_choices(weapon_levels, passive_levels, 3, team_weapons())
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
	if mode == "round" and phase == "break":
		if role == "client":
			# a próxima rodada começa quando todo o grupo escolher (ou o servidor cansar de esperar)
			waiting = true
			Network.horde_send("ready")
		else:
			_start_round()
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
	send_build()


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
	_queue.clear()
	var xp_reward := kills * 2 + rounds_cleared * 25
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


func server_player_dead(pid: int) -> void:
	if not team.has(pid) or phase != "fight":
		return
	team[pid].dead = true
	team[pid].falls = int(team[pid].get("falls", 0)) + 1
	_send_team()
	_check_wipe()


## Build e vida do jogador (já conferidas pelo Network), mostradas no Tab e usadas nos combos.
func server_player_build(pid: int, build: Dictionary) -> void:
	if team.has(pid):
		team[pid].build = build


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
	print("[server] Desafio da Horda terminou (%s): %d rodadas, %d abates" % [reason, rounds_cleared, kills])
	_send_all("_horde_over", [reason])
	for c in get_children():
		if c is Enemy and not c.dead:
			c._die()
	if world and world.get("survival") == self:
		world.survival = null
	Network.horde_run_ended(self)
	queue_free()


# ================================================================ grupo: build, combos e placar
## Build e vida deste jogador (enviada ao servidor no grupo; mostrada no Tab).
func my_build() -> Dictionary:
	var hp_ratio := 0.0 if (player == null or player.dead) else clampf(Game.hp / maxf(Game.max_hp(), 1.0), 0.0, 1.0)
	return {"lv": run_level, "hp": hp_ratio, "w": weapon_levels.duplicate(), "p": passive_levels.duplicate(),
		"b": blessing_counts.duplicate(), "c": combos_done}


func send_build() -> void:
	_build_t = 1.0
	if role == "client" and phase != "over":
		Network.horde_send_build(my_build())


func _my_id() -> int:
	return multiplayer.get_unique_id() if role == "client" else 0


## Armas dos colegas (id -> maior nível), para sortear cartas que formam combo.
func team_weapons() -> Dictionary:
	var out := {}
	if role != "client":
		return out
	var me := _my_id()
	for pid in team:
		if pid == me:
			continue
		var w: Dictionary = team[pid].get("build", {}).get("w", {})
		for id in w:
			out[id] = maxi(int(out.get(id, 0)), int(w[id]))
	return out


## Texto para a carta: a arma nova formaria combo com algum colega?
func combo_hint(choice: Dictionary) -> String:
	if role != "client" or choice.get("type", "") != "weapon" or weapon_levels.has(choice.id):
		return ""
	var me := _my_id()
	for pid in team:
		if pid == me:
			continue
		var w: Dictionary = team[pid].get("build", {}).get("w", {})
		for theirs in w:
			var cid := UPG.combo_for(choice.id, theirs)
			if cid != "" and not active_combos.has(cid):
				return "Combo com %s: %s" % [team[pid].name, UPG.COMBOS[cid].name]
	return ""


## Combos possíveis com o grupo: minha arma + arma par de um colega vivo; "near" = colega a até COMBO_RANGE.
func _update_combos() -> void:
	var me := _my_id()
	var now := {}
	for pid in team:
		if pid == me:
			continue
		var m: Dictionary = team[pid]
		var w: Dictionary = m.get("build", {}).get("w", {})
		if w.is_empty():
			continue
		var rp: Player = Network.remote_players.get(pid)
		var near: bool = rp != null and is_instance_valid(rp) and not rp.dead and not m.get("dead", false) \
			and player != null and not player.dead \
			and rp.global_position.distance_to(player.global_position) <= UPG.COMBO_RANGE
		for mine in weapon_levels:
			for theirs in w:
				var cid := UPG.combo_for(mine, theirs)
				if cid == "":
					continue
				var plv := int(w[theirs])
				if not now.has(cid):
					now[cid] = {"partner": str(m.name), "near": near, "mine": [mine], "plv": plv}
					continue
				var cur: Dictionary = now[cid]
				if not (mine in cur.mine):
					cur.mine.append(mine)
				if (near and not cur.near) or (near == cur.near and plv > cur.plv):
					cur.partner = str(m.name)
					cur.near = near
					cur.plv = plv
	for cid in now:
		if not _known_combos.has(cid):
			_known_combos[cid] = true
			var c: Dictionary = UPG.COMBOS[cid]
			Game.notify.emit("Combo com %s: %s (%s + %s) — fiquem perto!" % [now[cid].partner, c.name,
				UPG.WEAPONS[c.a].name, UPG.WEAPONS[c.b].name], c.color)
			Sfx.play("levelup", 0.0, -6.0)
	active_combos = now


## Linhas do placar (Tab): uma por jogador, ordenadas por dano.
func scoreboard_rows() -> Array:
	var rows: Array = []
	if role != "client":
		var n: String = str(Game.settings.get("player_name", ""))
		rows.append({"name": n if n != "" else "Você", "me": true, "dead": player != null and player.dead,
			"dmg": my_dmg, "kills": kills, "falls": 0, "build": my_build()})
		return rows
	var me := _my_id()
	for pid in team:
		var m: Dictionary = team[pid]
		rows.append({"name": str(m.get("name", "?")), "me": pid == me, "dead": bool(m.get("dead", false)),
			"dmg": float(m.get("dmg", 0.0)), "kills": int(m.get("kills", 0)), "falls": int(m.get("falls", 0)),
			"build": my_build() if pid == me else m.get("build", {})})
	rows.sort_custom(func(a, b) -> bool: return a.dmg > b.dmg)
	return rows
