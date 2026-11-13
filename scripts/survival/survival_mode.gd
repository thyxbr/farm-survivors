extends Node3D
## Desafio da Horda (estilo "survivors"): rodadas de inimigos sem fim na arena, gemas de XP,
## nível da partida com cartas de melhoria e bênçãos ao fim de cada rodada.
## Criado pelo mundo em start_survival(); fica na origem e é o pai dos inimigos e gemas.

const ENEMY := preload("res://scripts/enemies/enemy.gd")
const GEM := preload("res://scripts/survival/xp_gem.gd")
const PICKUP := preload("res://scripts/world/pickup.gd")
const UPG := preload("res://scripts/survival/upgrades.gd")
const WEAPONS := preload("res://scripts/survival/auto_weapons.gd")
const UI := preload("res://scripts/ui/survival_ui.gd")
const HUD := preload("res://scripts/ui/survival_hud.gd")

const ARENA_RADIUS := 31.0
const BOSS_EVERY := 5

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

var _queue: Array = []        # "levelup" | "round"
var _spawn_acc := 0.0
var _gold_start := 0
var _gem_sfx := 0.0


func _ready() -> void:
	Game.reset_run_mods()
	Game.run_mods.active = true
	Game.hp = Game.max_hp()
	Game.mp = Game.max_mp()
	Game.stamina = Game.max_stamina()
	Game.stats_changed.emit()
	_gold_start = Game.gold
	player.global_position = center + Vector3.UP * 0.5
	player.velocity = Vector3.ZERO
	FX.burst(player.global_position + Vector3.UP, Color(0.7, 0.4, 1.0), 50, 6.0, 0.12, 1.0, 1.0)
	FX.ring(center, Color(0.7, 0.4, 1.0, 0.9), 4.0, 0.7)

	weapons = WEAPONS.new()
	player.add_child(weapons)
	_apply({"type": "weapon", "id": "fogo"})

	hud = HUD.new()
	hud.survival = self
	add_child(hud)
	Game.notify.emit("Desafio da Horda! Sobreviva o máximo que puder.", Color(0.85, 0.6, 1.0))
	_start_round()


# ================================================================ rodadas
func _start_round() -> void:
	round_num += 1
	round_left = round_time
	phase = "fight"
	_spawn_acc = 0.0
	if round_num % BOSS_EVERY == 0:
		_spawn_boss()
		Game.notify.emit("Rodada %d — o Rei Goblin chegou!" % round_num, Color(1, 0.45, 0.3))
	else:
		Game.notify.emit("Rodada %d" % round_num, Color(1, 0.85, 0.4))
	Sfx.play("quest", 0.0)


func boss_alive() -> bool:
	return boss != null and is_instance_valid(boss) and not boss.dead


func _physics_process(delta: float) -> void:
	_gem_sfx = max(0.0, _gem_sfx - delta)
	if phase == "over" or player == null:
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
	if phase != "fight" or player.dead:
		return
	elapsed += delta
	round_left = max(0.0, round_left - delta)
	if round_left <= 0.0 and not boss_alive():
		_end_round()
		return
	var rate := 0.9 + 0.35 * (round_num - 1)
	if boss_alive():
		rate *= 0.5
	_spawn_acc += rate * delta
	var cap: int = min(80, 18 + round_num * 8)
	while _spawn_acc >= 1.0:
		_spawn_acc -= 1.0
		if alive_count() < cap:
			_spawn_enemy(_pick_kind(), _spawn_point())


func alive_count() -> int:
	var n := 0
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
	var total := 0.0
	for t in table:
		total += t[1]
	var r := randf() * total
	for t in table:
		r -= t[1]
		if r <= 0.0:
			return t[0]
	return "slime"


func _spawn_point() -> Vector3:
	var p := player.global_position
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


func _spawn_enemy(kind: String, pos: Vector3) -> Enemy:
	var e: Enemy = ENEMY.new()
	e.kind = kind
	e.horde = true
	e.hp_mult = 1.0 + 0.25 * (round_num - 1)
	e.dmg_mult = 1.0 + 0.12 * (round_num - 1)
	e.position = pos
	add_child(e)
	e.died.connect(_on_enemy_died)
	FX.burst(pos + Vector3.UP * 0.4, Color(0.5, 0.3, 0.7), 8, 3.0, 0.1, 0.5)
	return e


func _spawn_boss() -> void:
	var away := center - player.global_position
	away.y = 0
	var dir := away.normalized() if away.length() > 2.0 else Vector3.FORWARD
	var pos := player.global_position + dir * 14.0
	var q := pos - center
	q.y = 0
	if q.length() > ARENA_RADIUS - 3.0:
		pos = center + q.normalized() * (ARENA_RADIUS - 3.0)
	boss = _spawn_enemy("goblin_king", Vector3(pos.x, 0.3, pos.z))
	var tier: int = round_num / BOSS_EVERY
	boss.max_hp = 900.0 * (0.8 + 0.6 * tier)
	boss.hp = boss.max_hp
	boss.dmg_mult = 0.9 + 0.15 * tier
	FX.ring(boss.global_position, Color(1, 0.3, 0.1, 0.9), 6.0, 0.8)
	if world and world.hud:
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
	Game.notify.emit("Rodada %d concluída!" % round_num, Color(0.6, 1, 0.6))
	Sfx.play("levelup", 0.0)
	FX.ring(player.global_position, Color(0.9, 0.7, 1.0, 0.9), ARENA_RADIUS, 0.9)
	player.add_shake(0.25)
	for c in get_children():
		if c is Enemy and not c.dead:
			c._die()
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


# ================================================================ abates, gemas e XP
func _on_enemy_died(e: Enemy) -> void:
	if phase == "over":
		return
	kills += 1
	if Game.mod("lifesteal") > 0.0 and not player.dead:
		Game.hp = min(Game.max_hp(), Game.hp + Game.mod("lifesteal"))
	var pos := e.global_position + Vector3.UP * 0.6
	if e.is_boss:
		Game.notify.emit("Rei Goblin derrotado!", Color(1, 0.85, 0.3))
		for i in 8:
			_drop_gem("xp", 20, pos)
		_drop_gem("heal", 0, pos)
		_drop_gem("magnet", 0, pos)
		_drop_coin(pos, randi_range(20, 35))
		_reward_seeds(2, "seed_pumpkin")
		return
	var value := 1
	match e.kind:
		"goblin", "slime_grande":
			value = 20 if randf() < 0.08 else 5
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
	return int(6 + (run_level - 1) * 8 + pow(run_level - 1, 1.4))


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
	if mode == "round" and phase == "break":
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


func _add_mods(add: Dictionary) -> void:
	for k in add:
		Game.run_mods[k] += add[k]


# ================================================================ fim da partida
func on_player_died() -> void:
	if phase == "over":
		return
	phase = "over"
	_queue.clear()
	await get_tree().create_timer(1.6).timeout
	end_run("death")


## reason: "death" | "retreat" | "quit"
func end_run(reason: String) -> void:
	if end_reason != "":
		return
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
