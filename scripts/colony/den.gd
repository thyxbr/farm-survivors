class_name ColonyDen
extends Node3D
## Covil de monstros da Defesa da Cidade (ponto de interesse): acampamento goblin, ninho de slimes ou ruínas
## assombradas (ColonyData.POIS). Gerado da semente por ColonyNature, igual no servidor e nos clientes.
##
## Os guardas são inimigos comuns do servidor (não `siege`), presos ao covil (Enemy.den_id). Só existem
## enquanto há jogador por perto e é dia: acordam a DEN_WAKE m, somem a mais de DEN_SLEEP m e no entardecer.
## Os mortos voltam ao amanhecer. Matar o chefe limpa o covil de vez: recursos para a cidade, recompensa de RPG
## para cada jogador e um nó rico no centro. Não limpo, sobe de nível a cada DEN_GROW_DAYS dias e reforça a
## onda da noite na direção dele (Colony.den_dirs).
## Quem decide tudo é o servidor (ou o solo); o cliente só recebe nível e limpo (Lobby.city_den_state).

const PROPS := {
	"tent": preload("res://assets/models/tent.glb"),
	"campfire": preload("res://assets/models/campfire.glb"),
	"ruin_wall": preload("res://assets/models/ruin_wall.glb"),
	"ruin_pillar": preload("res://assets/models/ruin_pillar.glb"),
	"chest": preload("res://assets/models/chest.glb"),
	"crate": preload("res://assets/models/crate.glb"),
	"barrel": preload("res://assets/models/barrel.glb"),
	"rock": preload("res://assets/models/rock.glb"),
}
## Raio de colisão de cada peça do cenário (metros).
const PROP_RADIUS := {"tent": 1.6, "campfire": 0.6, "ruin_wall": 1.4, "ruin_pillar": 0.6, "chest": 0.6,
	"crate": 0.6, "barrel": 0.5, "rock": 0.9}

var id := 0
var kind := "goblin_camp"
var dir_index := 0
var level := 1
var cleared := false
var awake := false
## Dia em que o covil subiu de nível pela última vez (ou nasceu).
var grown_day := 1
var colony: Colony

## Quem ainda está de pé: [tipo, afixo, vida (-1 = cheia), chefe?]. Os mortos saem daqui até o amanhecer;
## quem some ao dormir guarda a vida aqui (o dano fica até o amanhecer).
var _roster: Array = []
var _guards: Array[Enemy] = []
var _entry := {}   # guarda no mapa -> entrada do _roster


func data() -> Dictionary:
	return ColonyData.POIS[kind]


func _ready() -> void:
	for p in data().props:
		var model := str(p[0])
		var at: Vector3 = p[1]
		if DisplayServer.get_name() != "headless":
			var inst: Node3D = PROPS[model].instantiate()
			inst.position = at
			inst.rotation.y = float(p[2])
			add_child(inst)
		var r := float(PROP_RADIUS.get(model, 0.6))
		var body := StaticBody3D.new()
		body.position = at
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var c := CylinderShape3D.new()
		c.radius = r
		c.height = 2.5
		cs.shape = c
		cs.position.y = 1.25
		body.add_child(cs)
		add_child(body)
		var g := global_position + at
		colony.obstacles.append([Vector2(g.x, g.z), r + 0.3])
	_refill()


## Guardas vivos agora (no mapa).
func guards() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for e in _guards:
		if is_instance_valid(e) and not e.dead and not e.is_queued_for_deletion():
			out.append(e)
	return out


func guards_alive() -> int:
	return guards().size()


## O chefe no mapa (null se o covil dorme ou já foi limpo).
func boss() -> Enemy:
	for e in guards():
		if bool(_entry[e][3]):
			return e
	return null


## Servidor/solo, ~2x por segundo de dia: acorda com jogador perto, dorme sem ninguém.
func tick(players: Array) -> void:
	if cleared:
		return
	var near := INF
	for p in players:
		if not p.dead:
			near = minf(near, _flat(p.global_position))
	if not awake and near <= ColonyData.DEN_WAKE:
		wake()
	elif awake and near > ColonyData.DEN_SLEEP:
		sleep()


## Os guardas que ainda estão de pé (e o chefe) nascem em volta do centro. Nunca à noite.
func wake() -> void:
	if cleared or awake or colony == null or colony.role == "client" or colony.phase != "day":
		return
	awake = true
	var hp := ColonyData.level_mult(level, ColonyData.DEN_LEVEL_HP)
	if colony.is_coop():
		hp *= 1.0 + ColonyData.TEAM_HP * (colony.team_size - 1)
	for g in _roster:
		var e := _spawn(str(g[0]), hp * (float(data().boss_hp) if bool(g[3]) else 1.0), str(g[1]))
		if float(g[2]) > 0.0:
			e.hp = minf(float(g[2]), e.max_hp)
			e.health_changed.emit(e)
		_entry[e] = g
		_guards.append(e)


## Os guardas somem (sem morrer: voltam do mesmo jeito quando o covil acordar de novo).
func sleep() -> void:
	awake = false
	_despawn()


## Amanhecer: os guardas mortos voltam e, a cada DEN_GROW_DAYS dias, o covil sobe de nível.
func dawn(day: int) -> void:
	if cleared:
		return
	if day - grown_day >= ColonyData.DEN_GROW_DAYS:
		grown_day = day
		if level < ColonyData.DEN_MAX_LEVEL:
			level += 1
			if colony and colony.role == "server":
				Lobby.city_den_state(id, level, cleared)
	_refill()


## Servidor/solo: o chefe caiu. O covil é limpo de vez.
func on_boss_killed() -> void:
	if cleared or colony == null or colony.role == "client":
		return
	cleared = true
	awake = false
	_despawn()
	var d := data()
	var c := global_position + Vector3.UP * 1.5
	colony.gain(ColonyData.scale_cost(d.reward, ColonyData.level_mult(level, 0.5)), c)
	var rw := ColonyData.night_reward(colony.day)
	if colony.role == "server":
		Lobby.city_den_reward(str(d.name), int(rw.gold), int(rw.xp))
	else:
		colony.solo_den_reward(int(rw.gold), int(rw.xp))
	var dep: Array = d.deposit
	var nid := colony.nature.add_rich(str(dep[0]), global_position, int(dep[1]))
	if colony.role == "server":
		Lobby.city_rich_node(nid, str(dep[0]), global_position.x, global_position.z, int(dep[1]))
		Lobby.city_den_state(id, level, cleared)
	colony.say("%s foi limpo! A cidade recebe %s, cada herói +%d ouro e +%d XP, e um depósito rico ficou lá." %
		[d.name, ColonyData.cost_text(ColonyData.scale_cost(d.reward, ColonyData.level_mult(level, 0.5))), rw.gold, rw.xp],
		Color(1, 0.85, 0.35))
	_show_cleared()
	colony._dirty()
	# solo: o prêmio já foi gravado no personagem; salva a cidade com o covil limpo para que carregar o save
	# (F9 ou continuar) não deixe limpar o mesmo covil de novo pelo mesmo prêmio
	if colony.role == "solo" and colony.world and colony.world.has_method("autosave"):
		colony.world.autosave()


## Cliente: o servidor mandou o estado do covil. fx = false no estado inicial (quem entra depois não vê a festa).
func net_set(new_level: int, is_cleared: bool, fx := true) -> void:
	level = new_level
	if is_cleared and not cleared:
		cleared = true
		if fx:
			_show_cleared()


func to_dict() -> Dictionary:
	return {"level": level, "cleared": cleared, "grown": grown_day}


func from_dict(d: Dictionary) -> void:
	_despawn()
	awake = false
	level = clampi(int(d.get("level", 1)), 1, ColonyData.DEN_MAX_LEVEL)
	cleared = bool(d.get("cleared", false))
	grown_day = int(d.get("grown", grown_day))
	_refill()


# ================================================================ interno
func _refill() -> void:
	_roster = []
	if cleared:
		return
	var d := data()
	for g in d.guards:
		for i in int(g[1]) + ColonyData.DEN_LEVEL_GUARDS * (level - 1):
			var affix := ""
			if float(d.get("elite", 0.0)) > 0.0 and randf() < float(d.elite):
				affix = ["blindado", "arcano", "agil"].pick_random()
			_roster.append([str(g[0]), affix, -1.0, false])
	_roster.append([str(d.boss), str(d.boss_affix), -1.0, true])


func _spawn(ekind: String, hp: float, affix: String) -> Enemy:
	var a := randf() * TAU
	var pos := global_position + Vector3(cos(a), 0, sin(a)) * randf_range(2.5, 7.0)
	var e := colony.spawn_enemy(ekind, pos, hp, affix, false)
	e.den_id = id
	e.den_center = global_position
	e.died.connect(_on_guard_died)
	return e


func _on_guard_died(e: Enemy) -> void:
	_guards.erase(e)
	var g: Array = _entry.get(e, [])
	_entry.erase(e)
	var i := _roster.find(g)
	if i >= 0:
		_roster.remove_at(i)
	if not g.is_empty() and bool(g[3]):
		on_boss_killed()


func _despawn() -> void:
	for e in _guards:
		if is_instance_valid(e) and not e.dead:
			if _entry.has(e):
				_entry[e][2] = e.hp   # volta com o mesmo dano quando o covil acordar de novo
			if e.died.is_connected(_on_guard_died):
				e.died.disconnect(_on_guard_died)
			if colony and colony.role == "server":
				Network.server_enemy_despawn(e)
			e.queue_free()
	_guards.clear()
	_entry.clear()


func _show_cleared() -> void:
	if DisplayServer.get_name() == "headless":
		return
	FX.burst(global_position + Vector3.UP * 1.2, Color(1, 0.85, 0.35), 50, 6.0, 0.16, 1.0)


func _flat(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()
