extends Node3D
## Cena do modo Defesa da Cidade: começa num mapa vazio (clareira cercada de floresta) onde o jogador
## posiciona todas as construções. Monta o terreno, o ciclo de luz dia/noite, o jogador e os HUDs,
## e repassa a entrada para o modo construção e para o exército. O estado fica em Colony (colony.gd).
##
## O ouro da cidade é o caixa da partida (Colony.treasury); o personagem é o do jogo (save solo no solo,
## o do servidor em grupo) e só ganha as recompensas por noite e o XP dos abates.
##
## role = "solo" (um jogador, com save da cidade), "server" (cidade em grupo simulada no servidor dedicado,
## sem jogador nem tela; criada pelo Lobby) ou "client" (réplica da cidade em grupo no PC do jogador).

const PLAYER := preload("res://scripts/player/player.gd")
const HUD := preload("res://scripts/ui/hud.gd")
const COLONY_HUD := preload("res://scripts/ui/colony_hud.gd")
const COLONY_UI := preload("res://scripts/ui/colony_ui.gd")
const GAME_MENU := preload("res://scripts/ui/game_menu.gd")
const DIALOGUE := preload("res://scripts/ui/dialogue_ui.gd")
const PAUSE := preload("res://scripts/ui/pause_menu.gd")
const COLONY := preload("res://scripts/colony/colony.gd")
const BUILD := preload("res://scripts/colony/build_mode.gd")
const CHAT := preload("res://scripts/ui/chat_ui.gd")
const GROUND := preload("res://scripts/world/ground.gd")
const M := {
	"tree_pine": preload("res://assets/models/tree_pine.glb"),
	"tree_oak": preload("res://assets/models/tree_oak.glb"),
	"tree_fir": preload("res://assets/models/tree_fir.glb"),
	"tree_birch": preload("res://assets/models/tree_birch.glb"),
	"tree_maple": preload("res://assets/models/tree_maple.glb"),
	"rock": preload("res://assets/models/rock.glb"),
}

const MAP_HALF := ColonyData.MAP_HALF
const CLEARING := 52.0
const SPAWN := Vector3(0, 0.5, 10)

var role := "solo"
## Semente do mapa (a mesma no servidor e nos clientes da cidade em grupo).
var map_seed := 7731
## Servidor: jogadores na sala quando a partida começou.
var coop_players := 1
## Servidor: bônus da base fixados no começo da partida (o Lobby preenche antes do add_child).
var base_bonus := {}
## Chefe atual (o Network preenche quando o Rei Goblin chega pela rede).
var boss: Enemy = null
var player: Player
var hud
var colony_hud
var ui_layer: CanvasLayer
var modal: Control = null
var colony: Colony
var build: Node3D
var rng := RandomNumberGenerator.new()
## Solo: o que o personagem levou da partida que acabou (a tela de derrota mostra).
var last_run := {}
var ground: Node3D

var _sun: DirectionalLight3D
var _env: Environment
var _sky: ProceduralSkyMaterial
var _light := -1.0
var _respawn_t := -1.0


func _ready() -> void:
	if role == "solo" and Network.is_client() and Lobby.joining_city:
		role = "client"
		map_seed = Lobby.city_seed
	rng.seed = map_seed
	if role != "server":
		_setup_input()
		_build_environment()
	_build_ground()
	colony = COLONY.new()
	colony.world = self
	colony.role = role
	if role == "server":
		colony.day_length = Lobby.city_day_time
		colony.first_day_bonus = Lobby.city_first_bonus
	add_child(colony)
	_scatter_nature()
	_build_borders()
	if role == "server":
		# servidor: só o mapa e a simulação; os jogadores chegam como réplicas
		colony.new_coop(coop_players, base_bonus)
		return

	var saved = null
	if role == "solo":
		# o personagem é o do save solo (antes de criar o jogador, que lê o equipamento); a cidade, a do save
		Econ.ensure_solo()
		saved = _read_colony_save() if Game.colony_continue else null
		if saved == null:
			Game.colony_continue = false
			_summarize_abandoned()
			# bônus da base fixados agora (a cidade salva guarda os seus) e a partida aberta no registro
			colony.new_colony(Hub.base_bonus())
			colony.run_rewards["run_id"] = Econ.run_start("city")
	# o jogador nasce na cidade (a posição de Valdoria do personagem fica onde está)
	Game.spawn_position = null

	player = PLAYER.new()
	player.spawn_point = SPAWN
	add_child(player)
	player.add_to_group("colony_units")
	player.died.connect(_on_player_died)

	hud = HUD.new()
	hud.player = player
	hud.hide_quests = true
	hud.boss_top = 78.0
	hud.help_text = ("WASD mover · Shift correr · Espaço pular · Ctrl esquivar · Clique atacar\n" +
		"B construir (1–0 escolhe · roda/R gira · X demolir) · E usar construção\n" +
		"G exército segue/defende · V ponto de reunião aqui · N chamar a noite\n" +
		"1/2/3 magias · R/F poções · I inventário · C personagem\n" +
		"F5 salvar · F9 carregar · Esc pausa · H esconder ajuda")
	if role == "client":
		hud.help_text = hud.help_text.replace("N chamar a noite", "N votar pela noite").replace("F5 salvar · F9 carregar · ", "")
	add_child(hud)
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui_layer)

	build = BUILD.new()
	build.world = self
	build.colony = colony
	add_child(build)
	colony_hud = COLONY_HUD.new()
	colony_hud.colony = colony
	colony_hud.build = build
	add_child(colony_hud)

	if role == "client":
		var chat := CHAT.new()
		chat.world = self
		add_child(chat)
		Game.notify.emit("Defesa da Cidade em grupo: o cofre é de todos. Aperte B para construir.", Color(1, 0.9, 0.6))
		Lobby.city_ready(self)
		return
	if saved != null:
		colony.from_dict(saved)
		var pp: Array = saved.get("player") if saved.get("player") is Array else []
		if pp.size() >= 3:
			player.global_position = Vector3(float(pp[0]), float(pp[1]), float(pp[2]))
			if pp.size() >= 4:
				player.model.rotation.y = float(pp[3])
		Game.notify.emit("Cidade carregada: dia %d." % colony.day, Color(0.7, 1.0, 0.7))
	else:
		Game.notify.emit("Bem-vindo! Aperte B e posicione a Prefeitura na clareira.", Color(1, 0.9, 0.6))
	if "--colonydemo" in OS.get_cmdline_user_args():
		_demo_city.call_deferred()


func _exit_tree() -> void:
	if role == "client":
		Lobby.city_closed(self)


## Network: onde os monstros replicados ficam (dentro da Colony, como no servidor).
func enemy_parent() -> Node:
	return colony


## Cliente: a cidade chegou do servidor (entra perto da prefeitura, se já existir).
func on_city_synced() -> void:
	if colony.hall and is_instance_valid(colony.hall) and player:
		var h := colony.hall
		player.global_position = h.global_position + h.global_basis.z * (h.size.y / 2.0 + 3.0) + Vector3.UP * 0.5
	if colony.phase == "setup":
		Game.notify.emit("Ninguém fundou a cidade ainda: aperte B e posicione a Prefeitura na clareira.", Color(1, 0.9, 0.6))


## Cliente: recompensa de uma noite vencida (aviso grande no centro).
func on_reward(n: int, gold: int, xp: int, items: Array) -> void:
	if colony_hud and colony_hud.has_method("show_reward"):
		colony_hud.show_reward(n, gold, xp, items)


## Cliente: a partida acabou (a cidade caiu ou todos saíram).
func show_results(info: Dictionary) -> void:
	if build and build.active:
		build.set_active(false)
	if modal != null:
		modal.queue_free()
		modal = null
	var ui := COLONY_UI.new()
	ui.mode = "results"
	ui.colony = colony
	ui.world = self
	ui.results = info
	_open_modal(ui)


# ================================================================ entrada
func _setup_input() -> void:
	var keys := {"build_mode": KEY_B, "army_mode": KEY_G, "rally_point": KEY_V, "call_night": KEY_N,
		"build_rotate": KEY_R, "build_demolish": KEY_X}
	for a in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
			var ev := InputEventKey.new()
			ev.physical_keycode = keys[a]
			InputMap.action_add_event(a, ev)


func _unhandled_input(event: InputEvent) -> void:
	if modal != null or player == null:
		return
	if event.is_action_pressed("pause"):
		if build.active:
			build.set_active(false)
		else:
			var p := PAUSE.new()
			p.mode = "pause"
			p.player_pos = player.global_position
			p.player_yaw = player.model.rotation.y
			_open_modal(p)
		get_viewport().set_input_as_handled()
		return
	if player.dead or colony.phase == "over":
		return
	if event.is_action_pressed("build_mode"):
		build.toggle()
	elif event.is_action_pressed("army_mode"):
		colony.toggle_army_mode()
	elif event.is_action_pressed("rally_point"):
		_set_rally_here()
	elif event.is_action_pressed("call_night"):
		if colony.phase == "day":
			colony.start_night()
	elif event.is_action_pressed("inventory"):
		_open_menu(0)
	elif event.is_action_pressed("character"):
		_open_menu(1)
	elif build.active:
		_build_input(event)


func _build_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k >= KEY_1 and k <= KEY_9:
			build.select_index(k - KEY_1)
			get_viewport().set_input_as_handled()
			return
		if k == KEY_0:
			build.select_index(9)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("build_rotate"):
		build.rotate_step(1)
	elif event.is_action_pressed("build_demolish"):
		build.select("demolish" if build.selected != "demolish" else "house")
		Sfx.play("click", 0.0)
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				build.rotate_step(1)
			MOUSE_BUTTON_WHEEL_DOWN:
				build.rotate_step(-1)
			MOUSE_BUTTON_LEFT:
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
					build.try_place()
			MOUSE_BUTTON_RIGHT:
				build.set_active(false)


func _set_rally_here() -> void:
	if colony.hall == null or not is_instance_valid(colony.hall):
		Game.notify.emit("Funde a cidade primeiro.", Color(1, 0.8, 0.5))
		return
	var p := player.global_position
	if Vector2(p.x - colony.hall.global_position.x, p.z - colony.hall.global_position.z).length() > ColonyData.CITY_RADIUS + 10.0:
		Game.notify.emit("O ponto de reunião precisa ficar perto da cidade.", Color(1, 0.8, 0.5))
		return
	colony.set_rally(p)
	if colony.army_mode == "follow" and role == "solo":   # no grupo o servidor já devolve o exército ao posto
		colony.toggle_army_mode()


# ================================================================ UI modal
func _open_menu(tab: int) -> void:
	var m := GAME_MENU.new()
	m.start_tab = tab
	_open_modal(m)


func open_dialogue(speaker: String, pages: Array, _focus: Node3D = null) -> void:
	var d := DIALOGUE.new()
	d.speaker = speaker
	d.pages = pages
	_open_modal(d)


func open_building_menu(b: ColonyBuilding) -> void:
	if build.active:
		build.set_active(false)
	var ui := COLONY_UI.new()
	ui.mode = "building"
	ui.building = b
	ui.colony = colony
	ui.world = self
	_open_modal(ui)


func _open_modal(c: Control) -> void:
	if modal != null:
		return
	modal = c
	ui_layer.add_child(c)
	c.closed.connect(_on_modal_closed)
	_set_paused(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.visible = false
	colony_hud.visible = false


## Em grupo a cidade não para: só o controle do jogador fica travado.
func _set_paused(on: bool) -> void:
	if role == "client":
		if player:
			player.input_locked = on
	else:
		get_tree().paused = on


func _on_modal_closed() -> void:
	modal = null
	_set_paused(false)
	hud.visible = true
	colony_hud.visible = true
	if player and not player.dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ================================================================ morte e derrota
func _on_player_died() -> void:
	if build.active:
		build.set_active(false)
	_respawn_t = 6.0
	Game.notify.emit("Você caiu! Renasce na prefeitura em 6 s (as torres seguem lutando).", Color(1, 0.6, 0.5))


func _respawn() -> void:
	var lost := colony.healer_fee(0.05) if role == "solo" else 0
	var at := SPAWN
	if colony.hall and is_instance_valid(colony.hall):
		at = colony.hall.global_position + colony.hall.global_basis.z * (colony.hall.size.y / 2.0 + 2.0) + Vector3.UP * 0.5
	player.revive(at)
	if lost > 0:
		Game.notify.emit("Os curandeiros cobraram %d ouro do caixa da cidade." % lost, Color(1, 0.75, 0.5))


func on_defeat() -> void:
	if role == "server":
		Lobby.city_defeat()
		return
	if role == "client":
		return   # o resultado chega do servidor (show_results)
	if build.active:
		build.set_active(false)
	_summarize_run()
	await get_tree().create_timer(2.5).timeout
	if modal != null:
		modal.queue_free()
		modal = null
	var ui := COLONY_UI.new()
	ui.mode = "defeat"
	ui.colony = colony
	ui.world = self
	_open_modal(ui)


# ================================================================ salvar / carregar
## Save da cidade (a partida: construções, exército, caixa, recompensas já ganhas). O personagem não vai
## aqui: ele está no save solo, gravado a cada concessão.
func save_colony() -> bool:
	if role != "solo":
		if role == "client":
			Game.notify.emit("Na cidade em grupo não há save: as recompensas vão para o seu personagem a cada amanhecer.", Color(1, 0.8, 0.5))
		return false
	if colony.phase != "day" and colony.phase != "setup":
		Game.notify.emit("Só dá para salvar de dia.", Color(1, 0.6, 0.5))
		return false
	if colony.phase == "setup":
		Game.notify.emit("Funde a cidade antes de salvar.", Color(1, 0.6, 0.5))
		return false
	var data := colony.to_dict()
	data["player"] = [player.global_position.x, player.global_position.y, player.global_position.z, player.model.rotation.y]
	data["time"] = Time.get_datetime_string_from_system(false, true)
	var f := FileAccess.open(Game.colony_save_path, FileAccess.WRITE)
	if f == null:
		Game.notify.emit("Falha ao salvar!", UITheme.BAD)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	Game.notify.emit("Cidade salva (dia %d)." % colony.day, Color(0.7, 1.0, 0.7))
	return true


func autosave() -> void:
	if role == "solo":
		save_colony()


func quick_save() -> void:
	save_colony()


func quick_load() -> void:
	if role == "solo" and Game.has_colony_save():
		Game.start_colony(true)


func _read_colony_save():
	var f := FileAccess.open(Game.colony_save_path, FileAccess.READ)
	if f == null:
		return null
	var data = JSON.parse_string(f.get_as_text())
	return data if data is Dictionary else null


## Solo, fim da partida (a cidade caiu): fecha a partida no registro (Econ.run_finish: Ecos pelas noites
## seguradas, uma linha com o que o personagem ganhou) e o caixa some com a cidade. O save continua
## ("Carregar o último save"), mas marcado como encerrado ("done"), para a partida não fechar duas vezes.
func _summarize_run() -> void:
	if role != "solo":
		return
	colony.flush_siege_xp()   # abates da noite em que a cidade caiu
	last_run = colony.run_rewards.duplicate(true)
	last_run["ecos"] = _write_summary(colony.run_rewards, maxi(0, colony.day - 1))
	colony.run_rewards = {"gold": 0, "xp": 0, "items": [], "run_id": int(last_run.get("run_id", 0)), "done": true}
	_clear_saved_run()


## Solo, cidade nova por cima de uma salva: a partida salva foi abandonada — o resumo dela entra agora.
func _summarize_abandoned() -> void:
	var old = _read_colony_save()
	if old == null or not (old.get("run") is Dictionary):
		return
	_write_summary(old.run, maxi(0, int(old.get("day", 1)) - 1))
	_clear_saved_run()


## Fecha a partida `run` (run_rewards) com `nights` noites seguradas. Devolve os Ecos ganhos.
## Partida já encerrada ("done") ou save antigo sem partida ({}) não fecham de novo.
func _write_summary(run: Dictionary, nights: int) -> int:
	if run.is_empty() or run.get("done", false):
		return 0
	var list: Array = run.get("items") if run.get("items") is Array else []
	var items := {}
	for id in list:
		items[str(id)] = int(items.get(str(id), 0)) + 1
	return Econ.run_finish(int(run.get("run_id", 0)), "city", nights, int(run.get("gold", 0)), int(run.get("xp", 0)), items)


func _clear_saved_run() -> void:
	var data = _read_colony_save()
	if data == null or not (data.get("run") is Dictionary) or data.run.is_empty() or data.run.get("done", false):
		return
	data["run"] = {"run_id": int(data.run.get("run_id", 0)), "done": true}
	var f := FileAccess.open(Game.colony_save_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()


# ================================================================ luz do dia
func _process(_delta: float) -> void:
	if role == "server":
		return
	if _respawn_t > 0.0:
		_respawn_t -= _delta
		if _respawn_t <= 0.0 and player.dead and colony.phase != "over":
			_respawn()
	var target := colony.daylight()
	var l := _light + clampf(target - _light, -_delta * 0.6, _delta * 0.6) if _light >= 0.0 else target
	if absf(l - _light) > 0.004:
		_light = l
		_apply_light(l)


func _apply_light(l: float) -> void:
	var dusk := Color(1.0, 0.55, 0.3)
	var noon := Color(1.0, 0.95, 0.86)
	var night := Color(0.45, 0.55, 0.95)
	var c := night.lerp(dusk, smoothstep(0.0, 0.45, l)).lerp(noon, smoothstep(0.45, 1.0, l))
	_sun.light_color = c
	_sun.light_energy = lerpf(0.22, 1.25, l)
	_sun.rotation_degrees = Vector3(lerpf(-14.0, -48.0, l), -35.0, 0.0)
	_sky.sky_top_color = Color(0.03, 0.04, 0.11).lerp(Color(0.28, 0.48, 0.82), l)
	var hz := Color(0.08, 0.09, 0.18).lerp(Color(0.95, 0.55, 0.35), smoothstep(0.0, 0.5, l) * (1.0 - smoothstep(0.5, 1.0, l)))
	hz = hz.lerp(Color(0.72, 0.8, 0.9), smoothstep(0.5, 1.0, l))
	_sky.sky_horizon_color = hz
	_sky.ground_horizon_color = hz
	_env.fog_light_color = hz
	_env.ambient_light_energy = lerpf(0.3, 0.9, l)
	_env.tonemap_exposure = lerpf(1.1, 0.95, l)


# ================================================================ mapa
func _build_environment() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	_sky = ProceduralSkyMaterial.new()
	_sky.sky_top_color = Color(0.28, 0.48, 0.82)
	_sky.sky_horizon_color = Color(0.72, 0.8, 0.9)
	_sky.ground_horizon_color = Color(0.72, 0.8, 0.9)
	_sky.ground_bottom_color = Color(0.2, 0.25, 0.2)
	_sky.sun_angle_max = 20.0
	sky.sky_material = _sky
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 0.9
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 0.95
	_env.glow_enabled = true
	_env.glow_intensity = 0.6
	_env.glow_bloom = 0.05
	_env.ssao_enabled = true
	_env.ssao_radius = 1.2
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.72, 0.8, 0.9)
	_env.fog_density = 0.003
	_env.fog_sky_affect = 0.2
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.1
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-48, -35, 0)
	_sun.light_energy = 1.25
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 90.0
	add_child(_sun)


func _build_ground() -> void:
	ground = GROUND.new()
	add_child(ground)
	ground.setup(MAP_HALF)
	ground.border_mountains(55.0)   # serra em volta (fora da borda, só visual)
	ground.build_terrain()
	# clareira central (onde vai a prefeitura)
	ground.add_disc(Vector3.ZERO, ColonyData.HALL_ZONE, Color(0.5, 0.5, 0.28), 1.6, 0.85)


func _prop(model: String, pos: Vector3, yaw: float, s: float, radius: float) -> void:
	var inst: Node3D = M[model].instantiate()
	inst.position = pos
	inst.rotation.y = yaw
	inst.scale = Vector3.ONE * s
	add_child(inst)
	if radius <= 0.0:
		return
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = radius * s
	c.height = 3.0
	cs.shape = c
	cs.position.y = 1.5
	body.add_child(cs)
	add_child(body)
	colony.obstacles.append([Vector2(pos.x, pos.z), radius * s + 0.3])


func _scatter_nature() -> void:
	# bosques: aglomerados de árvores longe da clareira, com campos abertos entre eles (onde ficam os animais)
	var groves := 26
	for g in groves:
		var a := rng.randf() * TAU
		var d := rng.randf_range(CLEARING + 6.0, MAP_HALF - 14.0)
		var c := Vector3(cos(a) * d, 0, sin(a) * d)
		c.x = clampf(c.x, -MAP_HALF + 10, MAP_HALF - 10)
		c.z = clampf(c.z, -MAP_HALF + 10, MAP_HALF - 10)
		var n := rng.randi_range(5, 11)
		for i in n:
			var p := c + Vector3(rng.randf_range(-9, 9), 0, rng.randf_range(-9, 9))
			if Vector2(p.x, p.z).length() < CLEARING:
				continue
			var r := rng.randf()
			if r < 0.4:
				_prop("tree_pine", p, rng.randf() * TAU, rng.randf_range(0.9, 1.5), 0.35)
			elif r < 0.55:
				_prop("tree_fir", p, rng.randf() * TAU, rng.randf_range(0.9, 1.4), 0.32)
			elif r < 0.68:
				_prop("tree_birch", p, rng.randf() * TAU, rng.randf_range(0.9, 1.3), 0.25)
			elif r < 0.78:
				_prop("tree_maple", p, rng.randf() * TAU, rng.randf_range(0.9, 1.2), 0.4)
			else:
				_prop("tree_oak", p, rng.randf() * TAU, rng.randf_range(0.9, 1.3), 0.4)
	# árvores e pedras soltas
	var placed := 0
	var tries := 0
	while placed < 70 and tries < 2000:
		tries += 1
		var p := Vector3(rng.randf_range(-MAP_HALF + 8, MAP_HALF - 8), 0, rng.randf_range(-MAP_HALF + 8, MAP_HALF - 8))
		if Vector2(p.x, p.z).length() < CLEARING - 4.0:
			continue
		if rng.randf() < 0.55:
			_prop("rock", p, rng.randf() * TAU, rng.randf_range(0.6, 1.5), 0.65)
		else:
			_prop("tree_oak", p, rng.randf() * TAU, rng.randf_range(0.8, 1.2), 0.4)
		placed += 1
	# algumas pedras decorativas (sem colisão) na clareira
	for i in 8:
		var a := rng.randf() * TAU
		var p := Vector3(cos(a), 0, sin(a)) * rng.randf_range(34.0, 48.0)
		_prop("rock", p, rng.randf() * TAU, rng.randf_range(0.4, 0.7), 0.6)
	if DisplayServer.get_name() == "headless":
		return
	ground.scatter_grass(map_seed + 7, 0.55, [], [[Vector2.ZERO, ColonyData.HALL_ZONE]])


func _build_borders() -> void:
	for side in [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(MAP_HALF * 2 + 4 if side.x == 0 else 2.0, 20, MAP_HALF * 2 + 4 if side.z == 0 else 2.0)
		cs.shape = b
		body.position = side * (MAP_HALF + 1) + Vector3.UP * 10
		body.add_child(cs)
		add_child(body)
	var t := -MAP_HALF
	while t <= MAP_HALF:
		for edge in 4:
			var d := MAP_HALF - rng.randf_range(0, 7)
			var p: Vector3
			match edge:
				0: p = Vector3(t, 0, -d)
				1: p = Vector3(t, 0, d)
				2: p = Vector3(d, 0, t)
				_: p = Vector3(-d, 0, t)
			_prop("tree_pine", p, rng.randf() * TAU, rng.randf_range(1.1, 1.8), 0.0)
		t += rng.randf_range(4.0, 6.5)


# ================================================================ demonstração (screenshots)
## `--colonydemo` monta uma cidade de exemplo; `--night` já começa o ataque.
func _demo_city() -> void:
	colony.treasury = 99999
	var c := colony
	c.place("town_hall", Vector3(0, 0, -4), 0.0, true)
	for p in [Vector3(-10, 0, -6), Vector3(10, 0, -6), Vector3(-10, 0, 2), Vector3(10, 0, 2)]:
		c.place("house", p, PI / 2 if p.x < 0 else -PI / 2, true)
	c.place("farm", Vector3(-12, 0, -16), 0.0, true)
	c.place("market", Vector3(9, 0, -15), 0.0, true)
	c.place("barracks", Vector3(0, 0, 10), PI, true)
	# muralha com portão ao sul
	for i in 9:
		var x := -16.0 + i * 4.0
		c.place("gate" if i == 4 else "wall", Vector3(x, 0, 18), 0.0, true, 2 if i % 3 == 0 else 1)
		c.place("wall", Vector3(x, 0, -24), 0.0, true)
	for i in 10:
		var z := -22.0 + i * 4.0
		c.place("wall", Vector3(-18, 0, z), PI / 2, true)
		c.place("wall", Vector3(18, 0, z), PI / 2, true)
	c.place("spikes", Vector3(0, 0, 22), 0.0, true)
	c.place("archer_tower", Vector3(-14, 0, 14), 0.0, true)
	c.place("archer_tower", Vector3(14, 0, 14), 0.0, true, 2)
	c.place("cannon_tower", Vector3(0, 0, -19), 0.0, true)
	c.place("mage_tower", Vector3(14, 0, -19), 0.0, true, 3)
	c.citizens = 20
	for u in ["soldier", "soldier", "archer", "archer", "knight", "militia"]:
		c.spawn_soldier(u, Vector3(randf_range(-3, 3), 0, 12))
	c.set_rally(Vector3(0, 0, 14), true)
	player.global_position = Vector3(6, 0.5, 30)
	player.model.rotation.y = PI
	player.cam_yaw.rotation.y = 0.0
	colony.treasury = 640
	var args := OS.get_cmdline_user_args()
	if "--night" in args:
		c.phase_t = 0.1
	# --ui=build | hall | barracks abre a tela correspondente
	await get_tree().create_timer(0.8).timeout
	if "--ui=build" in args:
		player.global_position = Vector3(-8, 0.5, 4)
		player.cam_yaw.rotation.y = PI
		build.set_active(true)
		build.select("archer_tower")
	if "--ui=hunt" in args:
		var a: Node3D = null
		for n in get_tree().get_nodes_in_group("animals"):
			if n.kind == "deer" or a == null:
				a = n
		if a:
			var at := a.global_position + Vector3(4.5, 0.5, 4.5)
			player.global_position = at
			var to := a.global_position - at
			player.cam_yaw.rotation.y = atan2(-to.x, -to.z)
	for b in c.buildings():
		if ("--ui=hall" in args and b.kind == "town_hall") or ("--ui=barracks" in args and b.kind == "barracks"):
			b.hp = b.max_hp * 0.7
			open_building_menu(b)
			break
