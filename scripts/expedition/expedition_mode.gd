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
##
## Encontros por ondas: ao entrar numa sala de luta ainda não limpa, as barreiras (room_barrier.gd) sobem nas
## bocas dos corredores e no portão do chefe, a run tranca a sala e a onda 1 nasce (marcada no chão antes). Cada
## onda só nasce quando a anterior caiu inteira; as quantidades vêm do "waves" da sala no ExpeditionDefs. Sair da
## sala por outro jeito (passo rápido, teleporte) devolve o jogador para dentro. A última onda solta as barreiras,
## limpa a sala na run e abre a bênção (uma vez só). Sala limpa nunca mais tranca nem gera monstro.
##
## Kit de habilidades da run (ExpeditionSkills): a expedição começa só com o ataque básico (Game.begin_run_kit:
## a barra e as teclas só valem para o que foi levado dos altares). Cada sala com "altar" no ExpeditionDefs ganha um
## Altar da Deusa (skill_altar.gd), que desperta quando a sala é visitada (e, numa sala de luta, limpa); [E] nele
## abre a escolha de 1 de 3 habilidades do kit do personagem (skill_altar_ui.gd). A escolhida vai para o
## ExpeditionRun.skills e o Game.run_kit espelha. A volta à Guilda (ou a saída para o menu) devolve o kit normal.
##
## Salas sem luta com santuário (run_shrine.gd; "shrine" no ExpeditionDefs), cada um uma vez por run:
##   event  — abre a escolha do evento (expedition_event_ui.gd, ExpeditionEvents): custo em vida + bênção de evento.
##   reward — o baú da Câmara das Oferendas abre a escolha de bênção de sempre (expedition_reward_ui.gd).
##   rest   — a fonte cura uma fração da vida máxima (Game.hp; nada muda na vida máxima nem no save).
## Elites: o líder da onda ("leader" no ExpeditionDefs) nasce com nome, balanceamento de elite e a barra no alto
## da tela; abaixo de "call_at" da vida chama reforços (uma vez). A bênção da sala de elite soma em dobro.

signal finished(summary: Dictionary)

const ENEMY := preload("res://scripts/enemies/enemy.gd")
const PORTAL := preload("res://scripts/expedition/expedition_portal.gd")
const REWARD_UI := preload("res://scripts/ui/expedition_reward_ui.gd")
const BARRIER := preload("res://scripts/expedition/room_barrier.gd")
const ALTAR := preload("res://scripts/expedition/skill_altar.gd")
const ALTAR_UI := preload("res://scripts/ui/skill_altar_ui.gd")
const SHRINE := preload("res://scripts/expedition/run_shrine.gd")
const EVENT_UI := preload("res://scripts/ui/expedition_event_ui.gd")
## Segundos entre trancar a sala e a primeira onda nascer, e entre uma onda cair e a próxima nascer (o lugar de
## cada monstro fica marcado no chão nesse tempo).
const FIRST_WAVE_DELAY := 0.9
const WAVE_DELAY := 1.4
## Ninguém da onda nasce a menos disso do jogador (m).
const SPAWN_CLEAR := 5.0
## Na hora de brotar, a marca a menos disso do jogador troca de lugar (m).
const SPAWN_ON_PLAYER := 2.5
## Barreira: quanto ela fica para dentro da sala a partir da borda, e quem estiver mais perto que isso dela ao
## trancar é empurrado para dentro (m).
const BARRIER_INSET := 0.6
const BARRIER_PUSH := 1.6
## A sala só tranca com o jogador a pelo menos isso das bocas dela (m): a cerca sobe atrás dele, com espaço para
## a câmera (que bate na cerca) não ficar colada nas costas.
const ENTER_DEPTH := 4.0
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
## Sala -> barreiras que fecham as passagens dela (só salas com luta).
var barriers := {}
## Sala cuja próxima onda já foi anunciada e está para nascer ("" = nenhuma).
var wave_pending := ""
## Último ponto do jogador dentro da sala trancada (para onde ele volta se sair por fora das barreiras).
var _last_inside := Vector3.ZERO
var _dungeon: MapDungeon
## Sala -> Altar da Deusa dela (skill_altar.gd).
var altars := {}
## Tela de escolha do altar aberta agora (null = nenhuma).
var altar_ui: Control = null
## Sorteio das habilidades dos altares (semente da run, separado dos outros).
var _altar_rng := RandomNumberGenerator.new()
## Sala -> santuário dela (run_shrine.gd: evento, recompensa, descanso).
var shrines := {}
## Tela do evento aberta agora (null = nenhuma).
var event_ui: Control = null
## Líderes de elite vivos: [{"entry", "room", "called"}].
var _leaders: Array = []


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
	var ds := map_root.pieces(MapDungeon)
	_dungeon = ds[0] if not ds.is_empty() else null
	# salas por ondas nascem pelo ExpeditionDefs na hora da luta: ponto de monstro da cena nelas fica de fora
	for e in sink:
		e["room"] = room_at(e.pos)
		if ExpeditionDefs.has_waves(run.def, str(e.room)):
			push_warning("Expedição %s: ponto de monstro da cena ignorado na sala por ondas '%s'" % [run.expedition_id, e.room])
			continue
		entries.append(e)
	_build_barriers()
	_build_altars()
	_build_shrines()
	run.players = 1   # solo; no coop, quantos entraram (DungeonRules.population usa)
	_rng.randomize()
	run.run_seed = _rng.seed
	_reward_rng.seed = hash(run.run_seed)
	_altar_rng.seed = hash([run.run_seed, "altar"])
	if not world.child_entered_tree.is_connected(_on_world_child):
		world.child_entered_tree.connect(_on_world_child)
	_spawn_all()
	arrive_point = world.landmarks.get(map_id + ":arrive", MapData.origin(map_id))
	exit_portal = _portal("exit", "", world.landmarks.get(map_id + ":exit", arrive_point + Vector3(0, 0, 4)))
	# como na Horda: bônus temporários da run valem só aqui, e a posição não é salva dentro da expedição
	Game.reset_run_mods()
	Game.run_mods.active = true
	Game.begin_run_kit()   # só o ataque básico: as habilidades vêm dos altares
	run.start()
	refresh_altars()
	refresh_shrines()
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
	if run.is_locked() and not player.dead:
		_hold_in_room(r)
	elif r != "" and r != run.current_room and run.enter_room(r):
		_on_room_entered(r)
	elif r != "" and r == run.current_room and run.can_start_encounter(r) and _deep_inside(r) and not player.dead:
		_start_encounter(r)   # entrou na borda e agora avançou: a luta começa
	_check_leaders()
	refresh_altars()
	refresh_shrines()
	_update_hud()


func _on_room_entered(room: String) -> void:
	var kind := ExpeditionDefs.kind_of(run.def, room)
	var first := not run.is_cleared(room) and not _announced.has(room)
	if first:
		_announced[room] = true
		_announce(room, kind)
	if run.can_start_encounter(room):
		if _deep_inside(room):
			_start_encounter(room)
		return   # ainda na borda: tranca quando ele avançar (o _process confere)
	_check_room(room)


## Salas já anunciadas nesta run (o letreiro da etapa sai só na primeira visita).
var _announced := {}


## Etapa da sala na rota (0 = a chegada) e quantas etapas a rota tem até o chefe.
func stage_of(room: String) -> Vector2i:
	var route := ExpeditionDefs.route(run.def)
	return Vector2i(route.find(room), route.size() - 1)


## Letreiro e aviso da primeira visita: a etapa e o que a sala tem.
func _announce(room: String, kind: String) -> void:
	var st := stage_of(room)
	var tag := "Etapa %d/%d" % [st.x, st.y] if st.x > 0 else ""
	var what := {
		"combat": "Combate", "elite": "Elite", "altar": "Altar da Deusa — uma nova habilidade",
		"event": "Evento — examine o santuário", "reward": "Recompensa — abra o baú das oferendas",
		"rest": "Descanso", "boss": "Chefe",
	}
	var sub := str(what.get(kind, ""))
	if kind == "rest" and ExpeditionDefs.heal_of(run.def, room) > 0.0:
		sub = "Descanso — a fonte cura uma vez"
	elif kind == "rest":
		sub = "O ar pesa: a Rainha espera além do portão"
	if tag != "" and not kind in ["combat", "elite", "boss"]:
		_banner(room.to_upper(), "%s · %s" % [tag, sub])   # a luta tem o letreiro da onda logo em seguida
	if tag != "":
		var c := Color(1.0, 0.7, 0.4) if kind in ["elite", "boss"] else Color(0.8, 0.9, 1.0)
		Game.notify.emit("%s — %s: %s" % [tag, room, sub], c)


## Limpa a sala (na run) quando ela já foi visitada e não tem mais monstro vivo. Numa luta trancada, a onda que
## caiu chama a próxima; só a última limpa a sala e solta as barreiras.
func _check_room(room: String) -> void:
	if room == "" or not run.is_active() or not run.visited.has(room) or run.is_cleared(room):
		return
	if wave_pending == room or alive_in(room) > 0:
		return
	var had_fight := ExpeditionDefs.needs_clear(run.def, room)
	if had_fight and run.current_wave(room) == 0:
		return   # o encontro ainda não começou (o jogador não chegou a entrar de verdade)
	if run.advance_wave(room):
		_queue_wave(room, WAVE_DELAY)
		_update_hud()
		return
	if not run.clear_room(room):
		return
	_set_barriers(room, false)
	_update_hud()
	if run.outcome == ExpeditionRun.VICTORY:
		_on_victory(room)
	elif had_fight:
		if ExpeditionDefs.kind_of(run.def, room) == "elite":
			_banner("ELITE DERROTADA", "%s — a bênção vale em dobro" % room)
		else:
			_banner("SALA LIBERADA", "%s — as passagens se abriram" % room)
		Sfx.play("levelup", 0.0)
		Game.notify.emit("Sala limpa: %s (%d%% da expedição)" % [room, roundi(run.progress() * 100.0)],
			Color(0.6, 1.0, 0.6))
		_offer_next_reward.call_deferred()   # fora do sinal de morte do monstro


# ================================================================ encontros (ondas e barreiras)
## Tranca a sala, sobe as barreiras e anuncia a primeira onda (a sala sem "waves" — o chefe — já tem os monstros
## dela de pé desde a montagem).
func _start_encounter(room: String) -> void:
	if not run.start_encounter(room):
		return
	_set_barriers(room, true)
	_push_inside(room)
	_last_inside = player.global_position
	Sfx.play("hit", 0.08, -4.0)
	if ExpeditionDefs.has_waves(run.def, room):
		_queue_wave(room, FIRST_WAVE_DELAY)
	else:
		# sala de chefe: o letreiro com o nome dela (portão, dungeon_fx) e a barra do chefe já anunciam a luta
		var msg := "%s: as passagens se fecharam!" % room
		if ExpeditionDefs.kind_of(run.def, room) == "boss":
			msg += " Derrote o chefe para sair."
		else:
			_banner("SALA TRANCADA", "Derrote todos os inimigos")
		Game.notify.emit(msg, Color(1, 0.6, 0.45))
		_check_room(room)


## Anuncia a onda atual da sala, marca no chão onde cada monstro vai nascer e cria todos depois de `delay` s.
func _queue_wave(room: String, delay: float) -> void:
	var n := run.current_wave(room)
	var total := run.wave_total(room)
	var plan := _wave_plan(room, n - 1)
	wave_pending = room
	_banner("ONDA %d/%d" % [n, total], "%s — %d inimigo(s)" % [room, plan.size()])
	for p in plan:
		p["mark"] = _spawn_mark(p.pos, delay)
	get_tree().create_timer(delay, false).timeout.connect(_spawn_wave.bind(room, n, plan))


## Marca no chão de onde um monstro vai brotar: um disco de seiva verde que cresce e pulsa até a hora (verde,
## para não confundir com o aviso vermelho de ataque em área).
func _spawn_mark(pos: Vector3, life: float) -> Node3D:
	if DisplayServer.get_name() == "headless":
		return null
	var mi := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.85
	disc.bottom_radius = 0.85
	disc.height = 0.02
	disc.radial_segments = 24
	disc.rings = 1
	mi.mesh = disc
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.9))
	g.set_color(1, Color(1, 1, 1, 0.0))
	g.add_point(0.55, Color(1, 1, 1, 0.25))
	g.add_point(0.8, Color(1, 1, 1, 0.7))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = gt
	m.albedo_color = Color(0.45, 1.0, 0.45, 0.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	mi.global_position = pos + Vector3.UP * 0.06
	mi.scale = Vector3(0.2, 1.0, 0.2)
	var tw := mi.create_tween()
	tw.set_parallel()
	tw.tween_property(mi, "scale", Vector3.ONE, life * 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.85, life * 0.3)
	tw.tween_property(mi, "rotation:y", TAU * 0.6, life)
	tw.chain().tween_callback(mi.queue_free)
	FX.ring(pos, Color(0.5, 1.0, 0.5), 1.3, life * 0.5)
	return mi


## Quem nasce na onda `index` (0 = a primeira) e onde: [{"kind", "elite", "pos"}]. Cada grupo do ExpeditionDefs
## cresce pelo DungeonRules.population quando a run tem mais jogadores.
func _wave_plan(room: String, index: int) -> Array:
	var out: Array = []
	for g in ExpeditionDefs.wave_groups(run.def, room, index):
		var count := DungeonRules.population(Balance.tables, int(g.get("count", 1)), run.players)
		for i in count:
			out.append({"kind": str(g.kind), "elite": bool(g.get("elite", false)),
				"leader": bool(g.get("leader", false)) and i == 0, "pos": _spawn_point(room, out)})
	return out


func _spawn_wave(room: String, n: int, plan: Array) -> void:
	if wave_pending == room:
		wave_pending = ""
	if _returning or not run.is_active() or run.locked_room != room or run.current_wave(room) != n:
		return
	# a sala é a arena da onda: o monstro já vem para cima do jogador e não sai dela
	var r: MapDungeonRoom = rooms.get(room)
	var arena := Rect2(Vector2(r.global_position.x, r.global_position.z) - r.size / 2.0, r.size) if r != null else Rect2()
	var me := Vector2(player.global_position.x, player.global_position.z)
	for p in plan:
		# o jogador pisou na marca durante o aviso: o monstro brota em outro lugar, nunca em cima dele
		if me.distance_to(Vector2(p.pos.x, p.pos.z)) < SPAWN_ON_PLAYER:
			p.pos = _spawn_point(room, plan.filter(func(o) -> bool: return o != p))
		var entry := {"kind": p.kind, "elite": p.elite, "pos": p.pos, "room": room, "wave": n, "arena": arena,
			"leader": bool(p.get("leader", false))}
		entries.append(entry)
		_spawn(entry)
		if entry.leader:
			_on_leader_spawned(entry)
		FX.burst(p.pos + Vector3.UP * 0.5, Color(0.55, 0.9, 0.4), 14, 3.0, 0.12, 0.5)
	Sfx.play("hit", 0.08, -6.0)
	_check_room(room)   # onda vazia (ou já morta): segue o fluxo


## Ponto de nascimento dentro da sala: chão, longe do jogador e dos outros da mesma onda.
func _spawn_point(room: String, taken: Array) -> Vector3:
	var r: MapDungeonRoom = rooms.get(room)
	if r == null:
		return arrive_point
	var c := r.global_position
	var c2 := Vector2(c.x, c.z)
	var best := c
	var best_score := -INF
	for i in 28:
		var off := Vector2(_rng.randf_range(-0.42, 0.42) * r.size.x, _rng.randf_range(-0.42, 0.42) * r.size.y)
		var p2 := c2 + off
		if not r.contains(c2, p2) or not _walkable(Vector3(p2.x, c.y, p2.y)):
			continue
		var p := Vector3(p2.x, c.y, p2.y)
		var d := Vector2(player.global_position.x, player.global_position.z).distance_to(p2)
		var near := INF
		for t in taken:
			near = minf(near, Vector2(t.pos.x, t.pos.z).distance_to(p2))
		var score := minf(d, SPAWN_CLEAR + 1.0) + minf(near, 2.5)
		if score > best_score:
			best_score = score
			best = p
		if d >= SPAWN_CLEAR and near >= 2.0:
			break
	return best


func _walkable(p: Vector3) -> bool:
	if _dungeon == null or map_root == null:
		return true
	var l := map_root.to_local(p)
	return _dungeon.walkable(Vector2(l.x, l.z))


## Barreiras de cada sala com luta: onde os corredores cruzam a borda da sala (MapDungeonPath) e o portão da sala
## do chefe (MapDungeon.boss_entrance). Nascem abertas.
func _build_barriers() -> void:
	var paths: Array = []
	for pth: MapDungeonPath in map_root.pieces(MapDungeonPath):
		var pts: Array = []
		for c in pth.get_children():
			if c is MapWaypoint:
				pts.append((c as Node3D).global_position)
		paths.append({"path": pth, "pts": pts})
	for room in rooms:
		if not ExpeditionDefs.needs_clear(run.def, room):
			continue
		var r: MapDungeonRoom = rooms[room]
		var list: Array = []
		for p in paths:
			for i in range(p.pts.size() - 1):
				_cross(room, r, p.pts[i], p.pts[i + 1], float(p.path.width), float(p.path.height), list)
		if r.boss and _dungeon != null:
			var g := _dungeon.boss_entrance()
			if not g.is_empty():
				var dir := Vector2(g.dir)
				var at := map_root.to_global(Vector3(g.pos.x, 0.0, g.pos.y)) + Vector3(dir.x, 0.0, dir.y) * (BARRIER_INSET + 0.4)
				list.append(_barrier(room, at, Vector3(dir.x, 0.0, dir.y), float(g.opening) + 0.8,
					maxf(float(g.height), 6.0)))
		barriers[room] = list


## Barreira onde o trecho a→b de um corredor cruza a borda da sala (para dentro dela BARRIER_INSET).
func _cross(room: String, r: MapDungeonRoom, a: Vector3, b: Vector3, w: float, h: float, out: Array) -> void:
	var c := Vector2(r.global_position.x, r.global_position.z)
	var seg_len := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
	if seg_len < 0.01:
		return
	var steps := maxi(2, ceili(seg_len / 0.2))
	var dir := (b - a)
	dir.y = 0.0
	dir = dir.normalized()
	var prev := r.contains(c, Vector2(a.x, a.z))
	for s in range(1, steps + 1):
		var p := a.lerp(b, float(s) / steps)
		var now := r.contains(c, Vector2(p.x, p.z))
		if now != prev:
			var inward := dir if now else -dir   # entrando na sala: para dentro é o sentido do trecho
			var edge := a.lerp(b, (s - 0.5) / steps)
			edge.y = r.global_position.y
			out.append(_barrier(room, edge + inward * BARRIER_INSET, inward, w + 0.8, h + 0.4))
		prev = now


func _barrier(room: String, at: Vector3, inward: Vector3, w: float, h: float) -> StaticBody3D:
	var b: StaticBody3D = BARRIER.new()
	b.room = room
	b.width = w
	b.height = h
	b.inward = inward.normalized()
	b.position = at   # o mundo fica na origem: posição local = global (o _ready já se vira com ela)
	b.name = "RoomBarrier"
	world.add_child(b)
	return b


func _set_barriers(room: String, on: bool) -> void:
	for b in barriers.get(room, []):
		if is_instance_valid(b):
			b.set_locked(on)


## O jogador já passou ENTER_DEPTH das bocas da sala (longe de todas as barreiras dela).
func _deep_inside(room: String) -> bool:
	for b in barriers.get(room, []):
		if is_instance_valid(b) and b.spans(player.global_position) and b.depth_of(player.global_position) < ENTER_DEPTH:
			return false
	return true


## Quem ficou em cima da linha da barreira na hora de trancar vai um pouco para dentro (não fica do lado de fora).
func _push_inside(room: String) -> void:
	for b in barriers.get(room, []):
		if not is_instance_valid(b) or not b.spans(player.global_position):
			continue
		var d: float = b.depth_of(player.global_position)
		if d < BARRIER_PUSH and d > -BARRIER_PUSH * 2.0:
			player.global_position += b.inward * (BARRIER_PUSH - d)
			player.velocity = Vector3.ZERO


## Sala trancada: o jogador só pode estar dentro dela. Fora (passo rápido pela barreira, teleporte, empurrão),
## volta para o último ponto lá dentro.
func _hold_in_room(r: String) -> void:
	if r == run.locked_room:
		_last_inside = player.global_position
		return
	player.global_position = _last_inside
	player.velocity = Vector3.ZERO
	Game.notify.emit("As raízes fecham a passagem: vença a luta primeiro.", Color(1, 0.6, 0.45))


func _banner(title: String, sub: String) -> void:
	if world.hud != null and world.hud.region_banner != null:
		world.hud.region_banner.show_area(title, sub)


## Linha da luta no alto da tela (HUD): sala, onda e quantos faltam. Some fora de luta e na sala do chefe (lá a
## barra do chefe já diz tudo, e as duas juntas cobriam o alto da tela).
func _update_hud() -> void:
	if world.hud == null or not world.hud.has_method("set_encounter"):
		return
	if not run.is_active() or not run.is_locked() or ExpeditionDefs.kind_of(run.def, run.locked_room) == "boss":
		world.hud.set_encounter("", "")
		return
	var room := run.locked_room
	var title := "%s — Onda %d/%d" % [room, run.current_wave(room), run.wave_total(room)]
	var info := ""
	if wave_pending == room:
		info = "A onda está chegando..."
	else:
		var n := alive_in(room)
		info = "%d inimigo%s restante%s" % [n, "" if n == 1 else "s", "" if n == 1 else "s"]
	world.hud.set_encounter(title, info)


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
	ui.stacks = run.pending_stacks()
	match ExpeditionDefs.kind_of(run.def, ui.room):
		"elite":
			ui.title_text = "Elite derrotada: %s" % ui.room
			ui.subtitle_text = "O líder caiu e o pântano se curva."
		"reward":
			ui.title_text = ui.room
			ui.subtitle_text = "As oferendas dos que vieram antes guardam uma bênção para você."
		"altar":
			ui.title_text = ui.room
			ui.subtitle_text = "A Deusa não tem mais o que ensinar, mas abençoa a sua jornada."
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
## Cria os monstros dos pontos da cena (hoje só o chefe: as salas por ondas nascem na hora da luta). Vaga extra de um ponto
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
	# o bônus de nível da elite não passa do teto da expedição (a placa vermelha de perigo nunca liga)
	en.level = mini(en.level, maxi(lv.y, ExpeditionBalance.max_level(run.def)))
	_tune(en, ExpeditionBalance.role_of(bool(entry.get("boss", false)) or en.chief,
		bool(entry.get("summoned", false)), bool(entry.get("leader", false))))
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


# ================================================================ altares (kit temporário de habilidades)
## Um Altar da Deusa em cada sala com "altar" no ExpeditionDefs, no lugar marcado (a partir do centro da sala).
func _build_altars() -> void:
	for room in ExpeditionDefs.altar_rooms(run.def):
		var r: MapDungeonRoom = rooms.get(room)
		if r == null:
			continue
		var off := ExpeditionDefs.altar_offset(run.def, room)
		var a: StaticBody3D = ALTAR.new()
		a.expedition = self
		a.room = room
		a.name = "SkillAltar"
		a.position = Vector3(r.global_position.x + off.x, r.global_position.y, r.global_position.z + off.y)
		world.add_child(a)
		# vira para o caminho (o centro da sala), de frente para quem chega
		var to := Vector3(r.global_position.x, a.position.y, r.global_position.z)
		if to.distance_to(a.position) > 0.1:
			a.look_at(to, Vector3.UP)
			a.rotate_y(PI)
		altars[room] = a


## Põe cada altar no estado que a run diz (dormindo, desperto ou gasto).
func refresh_altars() -> void:
	for room in altars:
		var a = altars[room]
		if not is_instance_valid(a):
			continue
		var s: String = ALTAR.DORMANT
		if run.is_altar_used(room):
			s = ALTAR.USED
		elif run.altar_ready(room):
			s = ALTAR.READY
		a.set_state(s)


func _altar_open() -> bool:
	return altar_ui != null and is_instance_valid(altar_ui) and not altar_ui.is_queued_for_deletion()


## [E] no altar de `room`: sorteia (uma vez por altar) até 3 habilidades do kit do personagem e abre a escolha.
## false se não abriu (altar dormindo ou gasto, luta em andamento, outra escolha na tela, nada para oferecer).
func open_altar(room: String) -> bool:
	if _returning or player == null or player.dead or not run.altar_ready(room) or run.is_locked():
		return false
	if _altar_open() or _reward_open() or _event_open() or run.has_pending_reward():
		return false
	var choices: Array = run.altar_choices(room)
	if choices.is_empty():
		choices = ExpeditionSkills.roll(_altar_rng, Game.full_ability_kit(), run.skills)
	if not run.offer_altar(room, choices):
		# nada mais a ensinar: a sala com bênção dá a bênção no lugar (o altar se apaga)
		if ExpeditionDefs.grants_reward(run.def, room) and run.spend_altar(room):
			refresh_altars()
			Game.notify.emit("A Deusa não tem mais o que ensinar a esta arma: ela concede uma bênção.",
				Color(0.7, 0.9, 1.0))
			_offer_room_reward(room)
			return true
		Game.notify.emit("A Deusa não tem mais o que ensinar a esta arma.", Color(0.7, 0.9, 1.0))
		return false
	if world.modal != null:
		world.close_ui()
	var ui: Control = ALTAR_UI.new()
	ui.expedition = self
	ui.room = room
	ui.choices = run.altar_choices(room)
	ui.owned = run.skills.duplicate()
	altar_ui = ui
	world._open_modal(ui)
	Sfx.play("levelup", 0.0)
	return true


## Chamado pela tela do altar: a habilidade entra no kit da run e o altar se apaga. false se a escolha não vale.
func choose_skill(skill: String) -> bool:
	if _returning or not _altar_open():
		return false
	var room: String = altar_ui.room
	if not run.choose_skill(room, skill):
		return false
	Game.set_run_kit(run.skills)
	refresh_altars()
	var kit := Game.ability_kit()
	var key := kit.find(skill) + 1
	Sfx.play("pickup", 0.0)
	_banner("NOVA HABILIDADE", "%s — tecla %d" % [str(ItemDB.ABILITIES[skill].name), key])
	Game.notify.emit("A Deusa concede: %s  [tecla %d]" % [str(ItemDB.ABILITIES[skill].name), key],
		Color(0.55, 1.0, 0.85))
	return true


func _close_altar_ui() -> void:
	if _altar_open():
		if world.modal == altar_ui:
			world.close_ui()
		else:
			altar_ui.queue_free()
	altar_ui = null


# ================================================================ santuários (evento, recompensa, descanso)
## Um santuário em cada sala com "shrine" no ExpeditionDefs, no lugar marcado (a partir do centro da sala).
func _build_shrines() -> void:
	for room in ExpeditionDefs.shrine_rooms(run.def):
		var r: MapDungeonRoom = rooms.get(room)
		if r == null:
			continue
		var off := ExpeditionDefs.shrine_offset(run.def, room)
		var sh: StaticBody3D = SHRINE.new()
		sh.expedition = self
		sh.room = room
		sh.kind = ExpeditionDefs.kind_of(run.def, room)
		sh.name = "RunShrine"
		sh.position = Vector3(r.global_position.x + off.x, r.global_position.y, r.global_position.z + off.y)
		world.add_child(sh)
		var to := Vector3(r.global_position.x, sh.position.y, r.global_position.z + r.size.y)
		if to.distance_to(sh.position) > 0.1:
			sh.look_at(to, Vector3.UP)
			sh.rotate_y(PI)
		shrines[room] = sh


## Santuário pronto (aceso, [E]) ou gasto.
func refresh_shrines() -> void:
	for room in shrines:
		var sh = shrines[room]
		if is_instance_valid(sh):
			sh.set_state(SHRINE.USED if run.is_shrine_used(room) else SHRINE.READY)


func _event_open() -> bool:
	return event_ui != null and is_instance_valid(event_ui) and not event_ui.is_queued_for_deletion()


## [E] no santuário de `room`: evento abre a escolha, recompensa abre a bênção, descanso cura. false se nada abriu.
func use_shrine(room: String) -> bool:
	if _returning or player == null or player.dead or not run.shrine_ready(room):
		return false
	if _altar_open() or _reward_open() or _event_open():
		return false
	match ExpeditionDefs.kind_of(run.def, room):
		"event":
			return _open_event_ui(room)
		"reward":
			return _offer_room_reward(room)
		"rest":
			return _rest(room)
	return false


## Bênção de uma sala sem luta (Câmara das Oferendas, Altar Ancestral sem habilidade): mesma escolha das salas
## limpas, aberta na hora.
func _offer_room_reward(room: String) -> bool:
	var choices := ExpeditionUpgrades.roll(_reward_rng, run.modifiers)
	if not run.offer_reward(room, choices):
		Game.notify.emit("As oferendas já não têm o que dar: todas as bênçãos estão no máximo.", Color(0.8, 0.8, 0.7))
		refresh_shrines()
		return false
	_open_reward_ui()
	return true


func _open_event_ui(room: String) -> bool:
	var ev := ExpeditionDefs.event_of(run.def, room)
	if not ExpeditionEvents.has(ev):
		return false
	if world.modal != null:
		world.close_ui()
	var ui: Control = EVENT_UI.new()
	ui.expedition = self
	ui.room = room
	ui.event_id = ev
	event_ui = ui
	world._open_modal(ui)
	Sfx.play("hit", 0.05, -8.0)
	return true


## Chamado pela tela do evento: aplica a opção (custo em vida e bênção de evento). false se não vale.
func choose_event(option: String) -> bool:
	if _returning or not _event_open():
		return false
	var room: String = event_ui.room
	var o := run.choose_event(room, option)
	if o.is_empty():
		return false
	var cost := float(o.get("hp_cost", 0.0))
	if cost > 0.0:
		Game.hp = ExpeditionEvents.hp_after(Game.hp, cost)
		FX.burst(player.global_position + Vector3.UP * 1.0, Color(0.8, 0.1, 0.12), 16, 2.4, 0.08, 0.6)
		Sfx.play("hit", 0.0, -2.0)
	_sync_mods()
	refresh_shrines()
	var up := str(o.get("upgrade", ""))
	if up != "":
		_banner(ExpeditionUpgrades.display_name(up).to_upper(), ExpeditionUpgrades.info(up).desc)
		Game.notify.emit("%s: %s (%s)" % [room, ExpeditionUpgrades.display_name(up), ExpeditionUpgrades.info(up).desc],
			Color(1.0, 0.6, 0.55))
		Sfx.play("pickup", 0.0)
	else:
		Game.notify.emit("%s: você deixa a oferenda em paz." % room, Color(0.8, 0.8, 0.75))
	return true


func _close_event_ui() -> void:
	if _event_open():
		if world.modal == event_ui:
			world.close_ui()
		else:
			event_ui.queue_free()
	event_ui = null


## A fonte do descanso: cura a fração da sala uma vez (com a vida cheia não gasta).
func _rest(room: String) -> bool:
	var top := Game.max_hp()
	if Game.hp >= top - 0.5:
		Game.notify.emit("Você já está descansado: a fonte espera por quando precisar.", Color(0.7, 0.9, 1.0))
		return false
	var f := run.rest(room)
	if f <= 0.0:
		return false
	var before := Game.hp
	Game.hp = minf(top, Game.hp + top * f)
	Game.stats_changed.emit()
	refresh_shrines()
	FX.burst(player.global_position + Vector3.UP * 1.0, Color(0.55, 1.0, 0.8), 22, 2.8, 0.08, 0.8, -2.0)
	FX.ring(player.global_position + Vector3.UP * 0.08, Color(0.55, 1.0, 0.8), 2.4, 0.7)
	Sfx.play("levelup", 0.0)
	_banner("DESCANSO", "+%d de vida" % roundi(Game.hp - before))
	Game.notify.emit("A fonte das raízes cura %d de vida." % roundi(Game.hp - before), Color(0.55, 1.0, 0.8))
	return true


# ================================================================ elites (líder com nome e reforços)
## O líder acabou de nascer: nome na placa, barra no alto da tela e a vigia dos reforços.
func _on_leader_spawned(entry: Dictionary) -> void:
	var room := str(entry.room)
	var info := ExpeditionDefs.leader_of(run.def, room)
	var en: Enemy = entry.get("node")
	if en == null or not is_instance_valid(en):
		return
	var nm := str(info.get("name", en.display_name))
	en.display_name = "Nv %d %s" % [en.level, nm] if en.level > 0 else nm
	if en.name_tag != null:
		en.name_tag.text = en.display_name
	if world.hud != null:
		world.hud.boss = en   # a barra do alto da tela (some a 40 m, como a do chefe)
	_leaders.append({"entry": entry, "room": room, "called": false})
	_banner(nm.to_upper(), "Elite — derrote o líder")
	Game.notify.emit("%s entra na luta!" % nm, Color(1.0, 0.7, 0.35))


## Líder abaixo da fração de vida do "call_at": chama os reforços (uma vez).
func _check_leaders() -> void:
	for l in _leaders:
		var en = l.entry.get("node")
		if l.called or en == null or not is_instance_valid(en) or en.dead or en.max_hp <= 0.0:
			continue
		var info := ExpeditionDefs.leader_of(run.def, str(l.room))
		if en.hp / en.max_hp <= float(info.get("call_at", 0.5)):
			l.called = true
			_leader_call(l, info)
	_leaders = _leaders.filter(func(l) -> bool: return not l.called and is_instance_valid(l.entry.get("node")))


func _leader_call(l: Dictionary, info: Dictionary) -> void:
	var room := str(l.room)
	if run.locked_room != room:
		return
	var r: MapDungeonRoom = rooms.get(room)
	var arena := Rect2(Vector2(r.global_position.x, r.global_position.z) - r.size / 2.0, r.size) if r != null else Rect2()
	var placed: Array = []
	for g in info.get("call", []):
		var count := DungeonRules.population(Balance.tables, int(g.get("count", 1)), run.players)
		for i in count:
			var p := {"pos": _spawn_point(room, placed)}
			placed.append(p)
			var entry := {"kind": str(g.kind), "elite": false, "pos": p.pos, "room": room,
				"wave": run.current_wave(room), "arena": arena, "summoned": true}
			entries.append(entry)
			_spawn(entry)
			FX.burst(p.pos + Vector3.UP * 0.5, Color(0.9, 0.5, 0.3), 14, 3.0, 0.12, 0.5)
	var nm := str(info.get("name", "O líder"))
	_banner("REFORÇOS", "%s chama o pântano!" % nm)
	Game.notify.emit("%s chama reforços!" % nm, Color(1.0, 0.55, 0.35))
	Sfx.play("hit", 0.05, -3.0)


## Saída sem passar pela volta (o mundo caiu inteiro: menu, troca de personagem): o kit normal volta mesmo assim.
func _exit_tree() -> void:
	if not _returning:
		Game.end_run_kit()


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
	_close_altar_ui()
	_close_event_ui()
	Game.end_run_kit()        # as habilidades dos altares saem aqui: volta o kit permanente da arma
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
	for list in barriers.values():
		for b in list:
			if is_instance_valid(b):
				b.queue_free()
	barriers.clear()
	for a in altars.values():
		if is_instance_valid(a):
			a.queue_free()
	altars.clear()
	for sh in shrines.values():
		if is_instance_valid(sh):
			sh.queue_free()
	shrines.clear()
	_leaders.clear()
	wave_pending = ""
	if world.hud != null and world.hud.has_method("set_encounter"):
		world.hud.set_encounter("", "")
	for n in _built + [exit_portal, victory_portal]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	for c in world.get_children():
		if c != player and c != self and c is Node3D and ExpeditionDefs.is_inside((c as Node3D).global_position):
			c.queue_free()
	# luzes de fogo do mapa (MapLight "piscando") que o MapLoader registrou no mundo saem junto com o mapa
	if "flicker_lights" in world:
		world.flicker_lights = world.flicker_lights.filter(func(fl) -> bool:
			return is_instance_valid(fl[0]) and not ExpeditionDefs.is_inside((fl[0] as Node3D).global_position))
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
