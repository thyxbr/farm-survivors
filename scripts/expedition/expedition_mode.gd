extends Node3D
## Uma expedição roguelite em andamento (solo por enquanto). Criada pelo mundo em start_expedition(), como o
## Desafio da Horda: o Hub (a vila) continua montado e a expedição é montada à parte, longe de tudo
## (MapData.EXTRA_ORIGINS), pelo MapLoader de sempre. Na volta à Guilda tudo o que ela montou é desfeito.
##
## Divisão de trabalho:
##   ExpeditionDefs — o grafo das salas (dados).
##   ExpeditionRun  — o estado da run (fase, sala atual, salas limpas, resultado); puro, testado à parte.
##   este nó        — monta/desmonta o mapa, cria os monstros (EnemySpawn + DungeonRules, sem volta), descobre em que
##                    sala o jogador está, avisa a run e leva o jogador de volta à Guilda.
##
## Fim da expedição (sempre volta à Guilda, sem penalidade nem prêmio novo nesta etapa):
##   vitória  — o chefe cai: abre um portal dourado na sala dele.
##   abandono — o portal da entrada (ou "Abandonar" no menu de pausa).
##   derrota  — o jogador cai: volta à Guilda com a vida cheia (sem a perda de ouro da morte comum).
## O ouro, o XP e o saque dos monstros seguem as regras normais do jogo (Econ), sem mudança.
##
## Melhorias temporárias (ExpeditionUpgrades): limpar uma sala com "reward" abre a escolha de 1 de 3
## (expedition_reward_ui.gd, modal: o jogo para até escolher). O que vale é o ExpeditionRun.modifiers;
## _sync_mods refaz Game.run_mods a partir dele (nunca soma por cima), e a volta à Guilda zera run_mods.

signal finished(summary: Dictionary)

const ENEMY := preload("res://scripts/enemies/enemy.gd")
const PORTAL := preload("res://scripts/expedition/expedition_portal.gd")
const REWARD_UI := preload("res://scripts/ui/expedition_reward_ui.gd")
## Igual ao world.DUNGEON_LEASH: em corredor o monstro larga o jogador a 24 m de casa.
const LEASH := 24.0
const DEATH_DELAY := 1.8
const ROOM_SCAN := 0.2
## Espera a tela escurecer (world._teleport leva 0.4 s) antes de desmontar o mapa.
const FADE_WAIT := 0.45
## Meta do Enemy que já recebeu o balanceamento da expedição (valor: o papel, ExpeditionBalance.ROLES).
const TUNED := &"expedition_role"

var world: Node
var player: Player
var run: ExpeditionRun
var map_id := ""
var map_root: MapRoot
## Pontos de monstro do MapLoader (um por monstro), cada um com "room" (sala onde nasce) e "node".
var entries: Array = []
## Sala -> MapDungeonRoom (pelo nome do nó, o mesmo do ExpeditionDefs).
var rooms := {}
var exit_portal: Node3D
var victory_portal: Node3D
var arrive_point := Vector3.ZERO
## O jogador já chegou na área da expedição (o teleporte da entrada leva 0.4 s).
var arrived := false
## O que o MapLoader pôs no mundo (raiz do mapa e o resto): sai na volta.
var _built: Array = []
var _scan := 0.0
var _returning := false
var _rng := RandomNumberGenerator.new()
## Sorteio das melhorias (semente da run, separado do dos monstros).
var _reward_rng := RandomNumberGenerator.new()
## Tela da escolha de melhoria aberta agora (null = nenhuma).
var reward_ui: Control = null


## Prepara a expedição `id`. false se ela não existe ou a definição está quebrada.
func setup(w: Node, p: Player, id: String) -> bool:
	world = w
	player = p
	run = ExpeditionRun.create(id)
	if run == null:
		return false
	map_id = ExpeditionDefs.map_of(id)
	name = "Expedition_" + id
	return true


## Monta o mapa, cria os monstros, começa a run e leva o jogador à chegada. false se o mapa não montou.
func begin() -> bool:
	var before := {}
	for c in world.get_children():
		before[c] = true
	var sink: Array = []
	map_root = MapLoader.build(world, map_id, sink)
	if map_root == null:
		return false
	world.maps[map_id] = map_root
	for c in world.get_children():
		if not before.has(c):
			_built.append(c)
	for r: MapDungeonRoom in map_root.pieces(MapDungeonRoom):
		rooms[str(r.name)] = r
	for r in ExpeditionDefs.rooms(run.def):
		if not rooms.has(r):
			push_error("Expedição %s: sala '%s' do ExpeditionDefs não existe na cena %s" % [run.expedition_id, r, map_id])
	entries = sink
	for e in entries:
		e["room"] = room_at(e.pos)
	run.players = 1   # solo; no coop, quantos entraram (DungeonRules.population usa)
	_rng.randomize()
	run.run_seed = _rng.seed
	_reward_rng.seed = hash(run.run_seed)
	if not world.child_entered_tree.is_connected(_on_world_child):
		world.child_entered_tree.connect(_on_world_child)
	_spawn_all()
	arrive_point = world.landmarks.get(map_id + ":arrive", MapData.origin(map_id))
	exit_portal = _portal("exit", "", world.landmarks.get(map_id + ":exit", arrive_point + Vector3(0, 0, 4)))
	# como na Horda: bônus temporários da run valem só aqui, e a posição não é salva dentro da expedição
	Game.reset_run_mods()
	Game.run_mods.active = true
	run.start()
	world.close_ui()
	world._teleport(arrive_point, ExpeditionDefs.display_name(run.expedition_id), "EXPEDIÇÃO")
	# chega olhando para a próxima sala (vira junto com o teleporte, com a tela já escura)
	var nexts := ExpeditionDefs.next_of(run.def, str(run.def.start))
	var ahead: Node3D = rooms.get(nexts[0]) if not nexts.is_empty() else null
	if ahead != null:
		var d := ahead.global_position - arrive_point
		get_tree().create_timer(FADE_WAIT).timeout.connect(_face.bind(atan2(d.x, d.z)))
	return true


func _face(yaw: float) -> void:
	if player != null and is_instance_valid(player) and not _returning:
		player.model.rotation.y = yaw
		player.cam_yaw.rotation.y = yaw + PI


# ================================================================ salas
## Sala onde fica a posição global ("" = corredor ou fora da expedição).
func room_at(pos: Vector3) -> String:
	var p := Vector2(pos.x, pos.z)
	for id in rooms:
		var r: MapDungeonRoom = rooms[id]
		if not is_instance_valid(r):
			continue
		var c := Vector2(r.global_position.x, r.global_position.z)
		if r.contains(c, p):
			return id
	return ""


## Monstros vivos que nasceram na sala.
func alive_in(room: String) -> int:
	var n := 0
	for e in entries:
		if e.room == room and is_instance_valid(e.node) and not e.node.dead:
			n += 1
	return n


func _process(delta: float) -> void:
	if run == null or not run.is_active() or player == null:
		return
	run.tick(delta)
	# escolha pendente sem tela (alguém fechou a janela por fora): reabre com as mesmas opções
	if run.has_pending_reward() and not _reward_open() and not player.dead:
		_open_reward_ui()
	_scan -= delta
	if _scan > 0.0:
		return
	_scan = ROOM_SCAN
	var inside := ExpeditionDefs.is_inside(player.global_position)
	if inside:
		arrived = true
	elif arrived and not player.dead:
		# saiu da área por outro caminho (caiu do mapa e voltou ao spawn da vila, teleporte...): conta como abandono
		request_return()
		return
	var r := room_at(player.global_position)
	if r != "" and r != run.current_room and run.enter_room(r):
		_on_room_entered(r)


func _on_room_entered(room: String) -> void:
	var kind := ExpeditionDefs.kind_of(run.def, room)
	if ExpeditionDefs.needs_clear(run.def, room) and not run.is_cleared(room):
		Game.notify.emit("%s: %d inimigo(s)" % [room, alive_in(room)], Color(1, 0.75, 0.5))
	elif kind == "rest":
		Game.notify.emit("%s: um momento de calma antes do chefe." % room, Color(0.7, 0.9, 1.0))
	_check_room(room)


## Limpa a sala (na run) quando ela já foi visitada e não tem mais monstro vivo.
func _check_room(room: String) -> void:
	if room == "" or not run.is_active() or not run.visited.has(room) or run.is_cleared(room):
		return
	if alive_in(room) > 0:
		return
	var had_fight := ExpeditionDefs.needs_clear(run.def, room)
	run.clear_room(room)
	if run.outcome == ExpeditionRun.VICTORY:
		_on_victory(room)
	elif had_fight:
		Game.notify.emit("Sala limpa: %s (%d%% da expedição)" % [room, roundi(run.progress() * 100.0)],
			Color(0.6, 1.0, 0.6))
		_offer_next_reward.call_deferred()   # fora do sinal de morte do monstro


# ================================================================ melhorias temporárias
## Abre a escolha da próxima sala limpa que ainda deve recompensa (uma por vez; as outras esperam a vez).
func _offer_next_reward() -> void:
	if _returning or not run.is_active() or run.has_pending_reward() or player == null or player.dead:
		return
	for room in run.rooms_awaiting_reward():
		var choices := ExpeditionUpgrades.roll(_reward_rng, run.modifiers)
		if run.offer_reward(room, choices):
			_open_reward_ui()
			return


func _reward_open() -> bool:
	return reward_ui != null and is_instance_valid(reward_ui) and not reward_ui.is_queued_for_deletion()


## Tela modal da escolha (pausa o jogo como as cartas da Horda). Fecha o que estiver aberto antes.
func _open_reward_ui() -> void:
	if _reward_open() or not run.has_pending_reward():
		return
	if world.modal != null:
		world.close_ui()
	var ui: Control = REWARD_UI.new()
	ui.expedition = self
	ui.room = str(run.pending_reward.room)
	ui.choices = (run.pending_reward.choices as Array).duplicate()
	ui.taken = run.modifiers.duplicate()
	reward_ui = ui
	world._open_modal(ui)
	Sfx.play("levelup", 0.0)


## Chamado pela tela: aplica a melhoria escolhida. false se a escolha não vale (já escolhida, fora da run...).
func choose_reward(upgrade: String) -> bool:
	if _returning or not run.choose_reward(upgrade):
		return false
	_sync_mods()
	Sfx.play("pickup", 0.0)
	Game.notify.emit("Melhoria: %s (%s)" % [ExpeditionUpgrades.display_name(upgrade),
		ExpeditionUpgrades.info(upgrade).desc], Color(0.85, 0.75, 1.0))
	_offer_next_reward.call_deferred()
	return true


## Refaz Game.run_mods a partir das melhorias da run (padrão + soma). A vida máxima que sobe vem cheia.
func _sync_mods() -> void:
	var old_max := Game.max_hp()
	var mods := ExpeditionUpgrades.apply_to(_base_run_mods(), run.modifiers)
	for k in mods:
		Game.run_mods[k] = mods[k]
	Game.run_mods.active = true
	var new_max := Game.max_hp()
	if new_max > old_max:
		Game.hp += new_max - old_max
	Game.hp = minf(Game.hp, new_max)
	Game.stats_changed.emit()


static func _base_run_mods() -> Dictionary:
	var keep := Game.run_mods
	Game.reset_run_mods()
	var base := Game.run_mods
	Game.run_mods = keep
	return base


func _close_reward_ui() -> void:
	if _reward_open():
		if world.modal == reward_ui:
			world.close_ui()
		else:
			reward_ui.queue_free()
	reward_ui = null


func _on_victory(room: String) -> void:
	Game.notify.emit("Vitória! O chefe caiu. Um portal para a Guilda se abriu.", Color(1, 0.85, 0.35))
	var r: MapDungeonRoom = rooms.get(room)
	var at: Vector3 = r.global_position if r != null else arrive_point
	victory_portal = _portal("exit", "victory", Vector3(at.x, 0.0, at.z))


# ================================================================ monstros
## Cria todos os monstros da expedição de uma vez (como as dungeons do mundo). Vaga extra de um ponto
## (slot >= DungeonRules.population) só nasce com mais jogadores na run. Ninguém volta depois de morto.
func _spawn_all() -> void:
	for e in entries:
		var base := int(e.get("base", 1))
		if int(e.get("slot", 0)) >= DungeonRules.population(Balance.tables, base, run.players):
			continue
		_spawn(e)


## Como world._spawn, mas sem volta (o morto não renasce) e avisando esta expedição.
func _spawn(entry: Dictionary) -> void:
	var en: Enemy = ENEMY.new()
	en.kind = entry.kind
	en.elite = entry.get("elite", false)
	en.area = str(entry.get("area", ""))
	en.chief = bool(entry.get("chief", false))
	en.arena = entry.get("arena", Rect2())
	if not en.arena.has_area():
		en.leash = LEASH
	# nível da sala (ExpeditionBalance) no lugar do nível da cena; vida e dano com o multiplicador da expedição
	var lv := ExpeditionBalance.level_range(run.def, str(entry.get("room", "")), int(entry.get("level", 0)),
		int(entry.get("level_max", 0)))
	en.level = ProgressionRules.spawn_level(Balance.tables, lv.x, lv.y, en.elite, _rng)
	_tune(en, ExpeditionBalance.role_of(bool(entry.get("boss", false)) or en.chief))
	en.position = entry.pos + Vector3.UP * 0.2
	world.add_child(en)   # filhos do mundo, como os monstros das dungeons (world.summon_minions e afins)
	entry.node = en
	en.died.connect(_on_enemy_died.bind(entry))


## Multiplicador de vida e dano da expedição (ExpeditionBalance) num monstro que ainda não entrou no mundo: o
## Enemy._ready multiplica hp_mult/dmg_mult pela curva de nível e pela categoria, como faz com os da Horda.
## Uma vez só por monstro (a marca evita somar de novo quando o lacaio passa pelo _on_world_child).
func _tune(en: Enemy, role: String) -> void:
	if en.has_meta(TUNED):
		return
	var m := ExpeditionBalance.mults(run.def, role)
	en.hp_mult *= float(m.hp)
	en.dmg_mult *= float(m.dmg)
	en.set_meta(TUNED, role)


## Monstro que nasce no mundo durante a expedição sem passar pelo _spawn (brotos da Espinheira, lacaios
## invocados): se nasce na área da expedição, recebe o balanceamento de lacaio. Chega aqui antes do _ready dele.
func _on_world_child(n: Node) -> void:
	if _returning or run == null or not (n is Enemy):
		return
	var en := n as Enemy
	if en.horde or en.has_meta(TUNED) or not ExpeditionDefs.is_inside(en.global_position):
		return
	_tune(en, ExpeditionBalance.role_of(false, true))


func _on_enemy_died(_en: Enemy, entry: Dictionary) -> void:
	entry.node = null
	_check_room(str(entry.get("room", "")))


# ================================================================ fim e volta à Guilda
## Portal "Voltar à Guilda" (ou "Abandonar" no menu): antes do fim é abandono.
func request_return() -> void:
	if _returning:
		return
	if run.is_active():
		run.abandon()
	_return_to_hub()


## Chamado pelo mundo quando o jogador cai durante a expedição.
func on_player_died() -> void:
	if _returning or not run.is_active():
		return
	run.fail()
	Game.notify.emit("Você caiu na expedição. Voltando à Guilda...", Color(1, 0.55, 0.45))
	await get_tree().create_timer(DEATH_DELAY).timeout
	_return_to_hub()


func _return_to_hub() -> void:
	if _returning:
		return
	_returning = true
	if world.child_entered_tree.is_connected(_on_world_child):
		world.child_entered_tree.disconnect(_on_world_child)
	world.expedition = null   # daqui em diante a morte e o menu voltam ao normal
	_close_reward_ui()        # a escolha não sobrevive à volta (a run já descartou a pendente)
	Game.reset_run_mods()     # melhorias temporárias saem aqui; a vida não passa do máximo sem elas
	Game.hp = minf(Game.hp, Game.max_hp())
	Game.stats_changed.emit()
	var hub: Vector3 = world.HORDE_RETURN   # na frente do portal da expedição, na vila
	if player.dead:
		player.revive(hub)
		player.invuln = 1.0
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		world.close_ui()
		world._teleport(hub, Regions.display_name("vila"), "VOLTA DA EXPEDIÇÃO")
		await get_tree().create_timer(FADE_WAIT).timeout
	_teardown()
	run.mark_returned()
	var s := run.summary()
	var how := {ExpeditionRun.VICTORY: "Vitória", ExpeditionRun.DEFEAT: "Derrota",
		ExpeditionRun.ABANDON: "Expedição abandonada"}
	Game.notify.emit("%s — %d/%d salas limpas em %d s." % [how.get(run.outcome, "Fim"), int(s.rooms_cleared),
		int(s.rooms_to_clear), int(s.elapsed)], Color(0.85, 0.8, 1.0))
	finished.emit(s)
	queue_free()


## Desfaz tudo o que a expedição pôs no mundo: mapa, portais, monstros (e lacaios invocados), saques e efeitos
## que ficaram na área dela, e os registros do mapa no mundo (landmarks, maps, capim).
func _teardown() -> void:
	for e in entries:
		if is_instance_valid(e.node):
			e.node.queue_free()
		e.node = null
	for n in _built + [exit_portal, victory_portal]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	for c in world.get_children():
		if c != player and c != self and c is Node3D and ExpeditionDefs.is_inside((c as Node3D).global_position):
			c.queue_free()
	var prefix := map_id + ":"
	for k in world.landmarks.keys():
		if str(k).begins_with(prefix):
			world.landmarks.erase(k)
	world.maps.erase(map_id)
	world.grass_areas.erase(map_id)
	if world.hud != null and world.hud.boss != null and (not is_instance_valid(world.hud.boss)
			or ExpeditionDefs.is_inside(world.hud.boss.global_position)):
		world.hud.boss = null
	map_root = null


func _portal(action: String, look: String, at: Vector3) -> Node3D:
	var p: Node3D = PORTAL.new()
	p.action = action
	p.look = look
	p.expedition_id = run.expedition_id
	world.add_child(p)
	p.global_position = at
	return p
