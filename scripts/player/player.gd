class_name Player
extends CharacterBody3D
## Cavaleiro controlado pelo jogador: movimento, câmera em 3ª pessoa, combo de espada, esquiva e magias.

signal died

const FIREBALL := preload("res://scripts/player/fireball.gd")
const PROJECTILE := preload("res://scripts/player/projectile.gd")
const AUTO_WEAPONS := preload("res://scripts/survival/auto_weapons.gd")

## Ataque básico do cetro: alcance (m) e cor da esfera de luz.
const LIGHT_ORB_RANGE := 12.0
const LIGHT_ORB_COLOR := Color(1.0, 0.92, 0.6)

const WALK_SPEED := 5.2
const SPRINT_SPEED := 8.6
const SWING_STAMINA_MIN := 5.0   ## fôlego mínimo para começar um golpe básico
const ARROW_STAMINA := 3.0       ## fôlego de cada flecha
const JUMP_VELOCITY := 7.0
const GRAVITY := 20.0
const DODGE_SPEED := 13.0
const DODGE_TIME := 0.36
const SWING_TIMES := [0.42, 0.42, 0.6]
const SWING_MULT := [1.0, 1.1, 1.6]
## Espada com escudo: combo de 4 golpes (KnightMovesShield: três do combo e o giro no fim), mais longos que os
## da espada sozinha; o dano de cada um acompanha a duração (mesmo dano por segundo do combo da espada).
const SHIELD_SWING_TIMES := [0.5, 0.5, 0.6, 0.75]
const SHIELD_SWING_MULT := [1.2, 1.3, 1.5, 2.0]
## Montante (espada de duas mãos, item "two_handed"): o combo do Mixamo "Two Hand Club Combo" (KnightMovesGreat), no
## ritmo dos três primeiros golpes da espada com escudo; alcance maior, varrem um arco mais aberto e o terceiro (a
## varrida na horizontal) acerta em área à frente. O dano da arma já é maior; por segundo fica um pouco abaixo da
## espada, em troca de pegar vários de uma vez (o mesmo de quando os golpes duravam 0,62 / 0,62 / 0,9 s com
## multiplicadores 1,0 / 1,1 / 1,7: o dano de cada golpe acompanha a duração).
const GREAT_SWING_TIMES := [0.5, 0.5, 0.6]
const GREAT_SWING_MULT := [0.81, 0.89, 1.13]
const GREAT_REACH := 3.0          ## alcance dos dois primeiros golpes (m; a espada tem 2,4)
const GREAT_ARC := -0.1           ## cosseno do arco atingido (a espada usa 0,3: ~145° contra ~110°)
const GREAT_SLAM_AHEAD := 1.5     ## o golpe final acerta em volta deste ponto à frente (m)
const GREAT_SLAM_RADIUS := 1.9
const SHIELD_SPIN_PUSH := 4.0   ## o giro avança mais que um golpe comum (m/s)
const PUNCH_TIMES := [0.3, 0.32, 0.5]   # sem arma: jab, direto e uppercut, mais rápidos que a espada
const STAFF_TIMES := [0.4, 0.4, 0.6]
const BOW_FULL := 0.85        # segundos para tensionar o arco por completo
const BOW_RECOVER := 0.35     # soltou: a mão da corda escapa e o arco baixa (ou encaixa a próxima, mirando)
const BOW_MIN_DRAW := 0.22    # segundos de tensão antes de poder atirar mirando (clique antes: atira ao chegar)
## Tiro rápido (clique esquerdo sem mirar): puxa até BOW_SNAP_CHARGE em BOW_SNAP_TIME segundos e solta sozinho.
const BOW_SNAP_TIME := 0.3
const BOW_SNAP_CHARGE := 0.55
const ARROW_AIM_RANGE := 30.0  # a compensação da queda da flecha mira no máximo até aqui (m)
const AIM_FOV := 52.0         # campo de visão mirando com o arco (normal: 70)
const CAM_SIDE := 0.45        # câmera um pouco à direita do jogador (m)
const AIM_CAM_SIDE := 0.8     # mirando com o arco: sobre o ombro direito
const AIM_CAM_CLOSER := 1.2   # e mais perto (m)
## Distância da câmera escolhida na rodinha do mouse (m): perto o bastante para não perder o personagem de
## vista, longe só um pouco além do padrão (4 m) para enxergar o alvo por cima de asas e capas grandes.
const CAM_DIST_MIN := 2.4
const CAM_DIST_MAX := 6.0
const CAM_DIST_STEP := 0.4
## Com asas nas costas a câmera sobe (m) e olha por cima delas: o alvo fica acima da envergadura.
const CAM_WINGS_UP := 0.45
## Ganho da aproximação exponencial da velocidade (chão: andando, parando, invertendo; ar).
const ACCEL_RUN := 14.0
const ACCEL_STOP := 18.0
const ACCEL_TURN := 22.0
const ACCEL_AIR := 4.0

var dead := false
var cam_yaw: Node3D
var cam_pitch: Node3D
var spring: SpringArm3D
var camera: Camera3D
var model: Node3D
## Corpo do modelo montado ("m"/"f"): o jogador local segue Game.body e as réplicas o "body" do visual.
var model_body := "m"
var parts := {}
## Referências do visual da arma (KnightLook.apply): classe, suporte, ponta, flecha.
var look := {"class": "sword", "holder": null, "tip": null, "arrow": null, "arm": null, "elbow": null, "counter": 0.0}
## Arco: mirando (segurando o botão direito), tensionando e quanto já tensionou; tiro rápido (sem mirar) e
## tiro pedido antes da tensão mínima; o zoom da mira (0..1, suavizado).
var aiming := false
var drawing := false
var draw_t := 0.0
## Quando (s, relógio do jogo) a tensão chegou ao máximo neste tiro; -1 = ainda não. Crescente Gêmeo: soltura perfeita.
var _bow_full_at := -1.0
var _bow_snap := false
var _shot_queued := false
var _aim_zoom := 0.0

var anim_t := 0.0
var idle_t := 0.0
## Animação procedural: amplitude da passada, inclinação, curva e impacto da aterrissagem (suavizados).
var _amp := 0.0      # 0..1: quanto está andando (suavizado)
var _run := 0.0      # 0..1: quanto está correndo
var _air := 0.0      # 0..1: quanto está no ar
var _cycle_w := 0.0  # 0..1: quanto o ciclo da passada ignora a suavização (KnightAnim.follow_cycle)
var _cast_t := 99.0  # segundos desde a última magia (a pose toca até KnightMoves.CAST_TIME)
var _cast_kind := "fireball"
var _lean := 0.0
var _bank := 0.0
var _land := 0.0
var _air_vy := 0.0
var _was_floor := true
var _prev_yaw := 0.0
var _prev_hvel := Vector3.ZERO
## Capa com física (CapeRig) e câmera: posição da última física, para detectar teleportes.
var cape: CapeRig
var _last_pos := Vector3.ZERO
var _cam_y := 0.0
var attacking := false
var attack_timer := 0.0
var combo := 0
var combo_window := 0.0
var buffered_attack := false
var hit_done := false
## Bola de Fogo do cajado crescendo na gema (MageStaffAttack.tick_orb); null fora da carga.
var fireball_orb: Node3D = null
var dodge_timer := 0.0
var dodge_dir := Vector3.ZERO
var _dodge_age := 0.0   ## há quanto tempo a esquiva atual começou (anima o rolamento; réplicas também)
var invuln := 0.0
## Lentidão deixada pela Slime de Gelo (segundos restantes); ver apply_chill.
var chill_t := 0.0
## Preso na teia da Tecelã (segundos restantes): anda bem mais devagar; ver apply_web.
var web_t := 0.0
const CHILL_SPEED := 0.6
const WEB_SPEED := 0.3
var cast_timer := 0.0
var stamina_delay := 0.0
## Escudo levantado (botão direito segurado com escudo na mão secundária; regras em ShieldRules).
var blocking := false
var _block_w := 0.0          ## 0..1: quanto o braço do escudo já subiu (suavizado, anima a pose)
var _block_chain := 0        ## golpes defendidos em sequência (cada um custa mais fôlego)
var _block_since := 99.0     ## segundos desde o último golpe defendido (zera a sequência)
var guard_break_t := 0.0     ## guarda quebrada: segundos sem poder levantar o escudo
var shake := 0.0
## Quanto a câmera recua (m) além da distância normal: a habilidade pede, _process aproxima suave.
var cam_back := 0.0
var _cam_back_now := 0.0
## Quanto a câmera inclina para cima (rad), pedido por habilidade (Martelo de Energia: o círculo fica no alto).
var cam_tilt := 0.0
var _cam_tilt_now := 0.0
## Distância base atual (persegue Game.settings.cam_zoom) e altura extra por causa das asas.
var _cam_dist := 4.0
var _cam_up := 0.0
var _has_wings := false
var _wings_check := 0.0
var _zoom_save_t := -1.0   # grava a distância escolhida pouco depois da última volta da rodinha
## Distância fixa pedida por ferramenta (--cam=graus,dist das capturas); 0 = usa a da rodinha.
var cam_dist_override := 0.0
## Habilidade de arma em execução (SwordAbilities): id ("" = nenhuma), tempo desde o início e
## rascunho dela ("nodes" são liberados e "mask" restaurada por end_ability()).
var ability := ""
var ability_t := 0.0
var ability_data := {}
var ability_slot := 0   ## slot (1..5) da tecla que começou a habilidade em execução (0 = nenhum)
var cooldowns := _make_cooldowns()   # todas as habilidades: a recarga continua ao trocar de arma
var interact_target: Node3D = null
## Veio ou árvore ao alcance de F (GatherAction.nearest; null coletando ou sem nada perto).
var gather_target: Node3D = null
## Ferramenta na mão durante a coleta (vira a arma do visual; "" = a arma equipada de sempre).
var gather_tool := ""
var spawn_point := Vector3(0, 0.5, 116)   # o world troca pelo landmark village_spawn (estrada do sul)
var _footstep := 0.0

## Multiplayer: réplica de outro jogador (sem câmera, sem input, sem atributos locais).
var remote := false
var peer_id := 0
var display_name := ""
## Título mostrado acima do nome ("" = sem título).
var display_title := ""
## Bloqueia o controle sem pausar a árvore (menus abertos no multiplayer).
var input_locked := false
## A tecla E que fechou o diálogo/janela não pode reabrir a conversa: só volta a valer depois de soltar.
var interact_wait_release := false
## Desafio da Horda em grupo: parado enquanto o grupo escolhe as cartas de nível.
var horde_frozen := false
## Digitando no chat: as teclas vão para a caixa de texto, não para o personagem.
var chat_typing := false
## Emote em andamento (KnightEmotes.KINDS) ou "". Andar, pular ou abrir o chat cancela.
var emote := ""
var _autoswing := "--autoswing" in OS.get_cmdline_user_args()
var _emote_t := 0.0
var name_tag: Label3D
var title_tag: Label3D
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_floor := true
var _net_vel := Vector3.ZERO
var _net_age := 0.0
var _net_send_t := 0.0


func _ready() -> void:
	add_to_group("players")
	if remote:
		_ready_remote()
		return
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 4 | 8 | MapRiver.WALL_LAYER   # 32: paredes do rio (a câmera não bate nelas)
	floor_snap_length = 0.4
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)

	model_body = KnightLook.body_key(Game.body)
	_build_model()

	# o suporte da câmera fica fora da hierarquia interpolada: o mouse gira na hora, e
	# _process o coloca sobre a posição interpolada do jogador a cada quadro.
	cam_yaw = Node3D.new()
	cam_yaw.top_level = true
	cam_yaw.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(cam_yaw)
	cam_pitch = Node3D.new()
	cam_pitch.rotation.x = -0.25
	cam_yaw.add_child(cam_pitch)
	spring = SpringArm3D.new()
	_cam_dist = clampf(float(Game.settings.get("cam_zoom", 4.0)), CAM_DIST_MIN, CAM_DIST_MAX)
	spring.spring_length = _cam_dist
	spring.collision_mask = 1
	spring.margin = 0.2
	spring.position.x = CAM_SIDE
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	spring.shape = sphere
	spring.add_excluded_object(get_rid())
	cam_pitch.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.far = 650.0   # a serra em volta do mapa fica a até ~400 m
	spring.add_child(camera)
	camera.current = true

	if Game.spawn_position != null:
		global_position = Game.spawn_position
		model.rotation.y = Game.spawn_yaw
		cam_yaw.rotation.y = Game.spawn_yaw + PI
		Game.spawn_position = null
	else:
		global_position = spawn_point
		model.rotation.y = PI
	_snap_visuals()
	Game.inventory_changed.connect(_update_equipment_visual)
	Game.enchant_changed.connect(_update_equipment_visual)
	Game.leveled_up.connect(_on_level_up)
	Game.food_eaten.connect(_on_food_eaten)
	_vfx_setup()
	Game.kit_changed.connect(end_ability)   # só o jogador local: réplicas saem antes, em _ready_remote
	# o próprio nome e título em cima da cabeça (as réplicas montam o delas em _ready_remote)
	display_name = Game.hero_name()
	display_title = Game.hero_title()
	_make_name_tag(Color(1.0, 0.97, 0.85), 0.003, 2.05)
	Game.stats_changed.connect(_refresh_own_tag)
	Network.players_changed.connect(_refresh_own_tag)
	_update_equipment_visual()
	FXEpic.prewarm()   # shaders dos efeitos prontos: a primeira habilidade não engasga
	FXEpic.prewarm_instances.call_deferred(self)   # e os pipelines de desenho de cada tipo de efeito
	StaffAbilities.prewarm()   # rocha, halo e céu da Chuva de Meteoros (malhas e materiais compartilhados)
	StaffAbilities.prewarm_instances.call_deferred(self)
	FireballProjectile.prewarm_instances.call_deferred(self)   # Bola de Fogo do ataque básico do cajado
	GreatswordSupremeAbilities.prewarm_instances.call_deferred(self)   # espada de energia, rachadura e partículas da Lâmina Suprema
	DragSlashAbilities.prewarm_instances.call_deferred(self)   # fagulhas, rastro e garras do Corte do Abismo
	GreatswordSpinAbilities.prewarm_instances.call_deferred(self)   # rastro sombrio e partículas do Ciclone de Aço
	GreatswordDarkComboAbilities.prewarm_instances.call_deferred(self)   # rastro sombrio, explosões e garras da Dança do Abismo
	FlameChannelAbilities.prewarm_instances.call_deferred(self)   # círculo, labareda, brasas e calor da Canalização de Fogo
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_model() -> void:
	# jogador e réplicas são interpolados entre os passos de física (movimento liso em telas >60 Hz)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	model = KnightLook.instance(model_body)
	add_child(model)
	if not remote:
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parts = KnightAnim.rig(model)
	var cape_mesh := model.find_child("Cape", true, false) as MeshInstance3D
	if cape_mesh:
		cape = CapeRig.attach(cape_mesh)
	if cape:
		cape.add_capsule(parts.LegL, 0.11, 0.95, Vector3(0, -0.45, 0))
		cape.add_capsule(parts.LegR, 0.11, 0.95, Vector3(0, -0.45, 0))
		# tronco: a cápsula acompanha o peito (a capa sai dos ombros); mesma posição de antes em repouso
		var chest: Node3D = parts.get("Chest")
		if chest:
			cape.add_capsule(chest, 0.14, 0.75, Vector3(0, 0.25, 0.02) - chest.position)
		else:
			cape.add_capsule(parts.Body, 0.14, 0.75, Vector3(0, 0.25, 0.02))


## Troca o modelo pelo do corpo `b` ("m"/"f"): o rabo de cavalo e as proporções vêm do GLB, então o
## cavaleiro inteiro é refeito (pivôs, capa, aura). O equipamento é remontado logo depois por apply_look.
func _rebuild_body(b: String) -> void:
	var yaw := model.rotation.y
	var old := model
	remove_child(old)
	old.queue_free()
	vfx_aura = null    # era filha do modelo antigo
	cape = null
	model_body = b
	_build_model()
	model.rotation.y = yaw
	_prev_yaw = yaw
	look["holder"] = null
	_snap_visuals()


## Depois de um teleporte: sem interpolação do ponto antigo ao novo e capa de volta ao repouso.
func _snap_visuals() -> void:
	_last_pos = global_position
	_cam_y = global_position.y
	reset_physics_interpolation()
	if cape:
		cape.reset()
	var back_cape = model.get_meta("back_cape") if model and model.has_meta("back_cape") else null
	if back_cape != null and is_instance_valid(back_cape):
		back_cape.reset()
	if cam_yaw:
		cam_yaw.global_position = global_position + Vector3.UP * KnightLook.body_y(self, 1.55)


func _check_teleport() -> void:
	if global_position.distance_to(_last_pos) > 3.0:
		_snap_visuals()
	_last_pos = global_position


func _process(delta: float) -> void:
	if remote or cam_yaw == null:
		return
	# câmera sobre a posição interpolada; na vertical segue com leve atraso (degraus, pulos)
	var o := get_global_transform_interpolated().origin
	_cam_y = lerpf(_cam_y, o.y, 1.0 - exp(-12.0 * delta))
	_cam_y = clampf(_cam_y, o.y - 0.6, o.y + 0.6)
	_update_cam_framing(delta)
	cam_yaw.global_position = Vector3(o.x, _cam_y + 1.55 + _cam_up, o.z)
	_vfx_sync()
	# mirando com o arco a câmera fecha e vai para cima do ombro direito: o corpo fica de lado, à esquerda
	# da mira, com o arco e a corda à vista (a Flecha do Vendaval mexe no FOV sozinha)
	var zoom_to := 1.0 if aiming and look["class"] == "bow" and not dead else 0.0
	_aim_zoom = lerpf(_aim_zoom, zoom_to, 1.0 - exp(-10.0 * delta))
	if ability == "" and camera:
		camera.fov = lerpf(70.0, AIM_FOV, _aim_zoom)
	spring.position.x = lerpf(CAM_SIDE, AIM_CAM_SIDE, _aim_zoom)
	# recuo pedido por habilidade (e a aproximação da mira): soma só a diferença, a distância base fica intacta
	var back := lerpf(_cam_back_now, cam_back - AIM_CAM_CLOSER * _aim_zoom, 1.0 - exp(-6.0 * delta))
	_cam_back_now = back
	spring.spring_length = maxf(_cam_dist + back, 1.2)
	_cam_tilt_now = lerpf(_cam_tilt_now, cam_tilt, 1.0 - exp(-6.0 * delta))
	if camera:
		camera.rotation.x = _cam_tilt_now


## Zoom da rodinha (suave) e altura extra quando há asas nas costas.
func _update_cam_framing(delta: float) -> void:
	var want := clampf(float(Game.settings.get("cam_zoom", 4.0)), CAM_DIST_MIN, CAM_DIST_MAX)
	if cam_dist_override > 0.0:
		want = cam_dist_override
	_cam_dist = lerpf(_cam_dist, want, 1.0 - exp(-10.0 * delta))
	_wings_check -= delta
	if _wings_check <= 0.0:
		_wings_check = 0.5   # o visual pode trocar a qualquer hora (equipar, trocar de corpo)
		_has_wings = model != null and model.find_child("BackWings", true, false) != null
	_cam_up = lerpf(_cam_up, CAM_WINGS_UP if _has_wings else 0.0, 1.0 - exp(-6.0 * delta))
	if _zoom_save_t >= 0.0:
		_zoom_save_t -= delta
		if _zoom_save_t < 0.0:
			Game.save_settings()


func _ready_remote() -> void:
	# sem colisão: a réplica só mostra onde o outro jogador está
	collision_layer = 0
	collision_mask = 0
	_build_model()
	_net_pos = position
	_snap_visuals()
	_make_name_tag(Color(0.75, 0.9, 1.0), 0.006, 2.25)


## Nome em cima da cabeça e, acima dele, o título (menor, dourado). Vale para o jogador e as réplicas.
## `px` = tamanho do pixel do texto (o próprio jogador usa menor: a câmera fica bem perto); `y` = altura do nome.
func _make_name_tag(color: Color, px: float, y: float) -> void:
	name_tag = Label3D.new()
	name_tag.font_size = 40
	name_tag.outline_size = 8
	name_tag.pixel_size = px
	name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_tag.modulate = color
	name_tag.position.y = y
	add_child(name_tag)
	title_tag = Label3D.new()
	title_tag.font_size = 30
	title_tag.outline_size = 8
	title_tag.pixel_size = px
	title_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title_tag.modulate = Color(1.0, 0.82, 0.4)
	title_tag.position.y = y + px * 40.0   # logo acima do nome, sem encostar
	add_child(title_tag)
	set_display_name(display_name)
	set_title(display_title)


## Jogador local: nome do herói e título escolhido (mudam ao trocar de título ou ao entrar no servidor).
func _refresh_own_tag() -> void:
	set_display_name(Game.hero_name())
	set_title(Game.hero_title())


func _unhandled_input(event: InputEvent) -> void:
	if remote or input_locked or Loading.covering:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s: float = Game.settings.mouse_sensitivity * 0.01
		var inv := -1.0 if Game.settings.invert_y else 1.0
		cam_yaw.rotate_y(-event.relative.x * s)
		cam_pitch.rotation.x = clamp(cam_pitch.rotation.x - event.relative.y * s * inv, -1.25, 0.6)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED 			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var step := -CAM_DIST_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else CAM_DIST_STEP
		var cur := float(Game.settings.get("cam_zoom", 4.0))
		Game.settings["cam_zoom"] = clampf(cur + step, CAM_DIST_MIN, CAM_DIST_MAX)
		_zoom_save_t = 1.0
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Saiu da árvore (réplica removida porque o jogador saiu ou trocou de zona, troca de cena): fim duro da
## habilidade, senão os nós dela fora do jogador (o céu da Chuva de Meteoros, na raiz da cena) ficariam
## órfãos. end_ability só libera nós e restaura estado (nada de efeito novo), então é seguro mesmo com a
## cena sendo desmontada.
func _exit_tree() -> void:
	if ability != "":
		end_ability()
	if fireball_orb and is_instance_valid(fireball_orb):
		fireball_orb.queue_free()
	fireball_orb = null


func _physics_process(delta: float) -> void:
	if remote:
		_remote_process(delta)
	else:
		_local_process(delta)
	_check_teleport()


func _local_process(delta: float) -> void:
	if Network.is_client():
		_net_send(delta)
	if _autoswing:   # depuração (--autoswing, ver Game._debug_screenshot): golpeia sem parar
		Game.stamina = Game.max_stamina()
		_try_attack()
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	if dead:
		velocity.x = move_toward(velocity.x, 0, 20 * delta)
		velocity.z = move_toward(velocity.z, 0, 20 * delta)
		move_and_slide()
		MageStaffAttack.tick_orb(self)   # morto: a bola da carga some
		return

	_tick_timers(delta)
	_regen(delta)

	var loading: bool = Loading.covering   # tela de carregamento: sem controle até ela abrir
	if input_locked or horde_frozen or chat_typing or loading:
		end_ability()
		_disarm_heal()
		_disarm_area()
	if input_locked or horde_frozen or chat_typing or loading:
		aiming = false
		velocity.x = move_toward(velocity.x, 0, 45 * delta)
		velocity.z = move_toward(velocity.z, 0, 45 * delta)
		move_and_slide()
		_update_attack(delta)
		_animate(delta)
		_update_camera(delta)
		return

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var fwd := -cam_yaw.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var right := cam_yaw.global_basis.x
	right.y = 0
	right = right.normalized()
	var dir := (right * input.x + fwd * -input.y)
	if dir.length() > 1.0:
		dir = dir.normalized()

	var busy := ability != ""
	_update_block(delta, busy)
	var sprinting := Input.is_action_pressed("sprint") and dir.length() > 0.1 and Game.stamina > 1.0 and not attacking and not drawing \
		and not busy and not blocking
	if sprinting:
		Game.stamina = max(0.0, Game.stamina - 20.0 * delta)
		stamina_delay = 0.6
	var speed := (SPRINT_SPEED if sprinting else WALK_SPEED) * Game.speed_multiplier()
	if chill_t > 0.0:
		chill_t -= delta
		speed *= CHILL_SPEED
	if web_t > 0.0:
		web_t -= delta
		speed *= WEB_SPEED
	if attacking:
		speed *= 0.3 if look["class"] == "sword" else 0.55
	elif drawing:
		speed *= 0.45
	elif cast_timer > 0:
		speed *= 0.6
	if blocking:
		speed *= ShieldRules.MOVE_SPEED
	elif guard_break_t > 0.0:
		speed *= 0.35   # cambaleando depois da guarda quebrada

	if busy:
		# controla a velocidade horizontal (e pode terminar); recebe a direção pedida pelo jogador
		# (relativa à câmera) e a velocidade de andar, para habilidades que andam devagar
		_ab_module(ability).tick(self, delta, dir, speed)
	elif dodge_timer > 0:
		dodge_timer -= delta
		velocity.x = dodge_dir.x * DODGE_SPEED
		velocity.z = dodge_dir.z * DODGE_SPEED
	else:
		# aproximação exponencial: arranca rápido e assenta suave; inverter a direção freia mais forte
		var hv := Vector3(velocity.x, 0, velocity.z)
		var target := dir * speed
		var rate := ACCEL_AIR
		if is_on_floor():
			if target.length() < 0.1:
				rate = ACCEL_STOP
			elif hv.dot(target) < 0.0:
				rate = ACCEL_TURN
			else:
				rate = ACCEL_RUN
		hv = hv.lerp(target, 1.0 - exp(-rate * delta))
		if target == Vector3.ZERO and hv.length() < 0.05:
			hv = Vector3.ZERO
		velocity.x = hv.x
		velocity.z = hv.z

	if Input.is_action_just_pressed("jump") and is_on_floor() and not attacking and dodge_timer <= 0 and not busy:
		velocity.y = JUMP_VELOCITY
	# com arco o botão direito mira: o mesmo clique não esquiva (a esquiva fica no Ctrl/Alt)
	var aim_click: bool = look["class"] == "bow" and Input.is_action_just_pressed("aim")
	# com escudo o botão direito levanta o escudo (_update_block): o mesmo clique também não esquiva
	if has_shield() and Input.is_action_just_pressed("aim"):
		aim_click = true
	# habilidade preparada: o clique esquerdo confirma em vez de dar o ataque básico
	var armed_click := false
	if heal_armed:
		_update_heal_aim(delta)
		if heal_armed and Input.is_action_just_pressed("attack"):
			armed_click = true   # esquerdo: cura quem está marcado (o aliado na mira; sem aliado, você)
			confirm_heal(heal_target)
		elif heal_armed and Input.is_action_just_pressed("aim"):
			aim_click = true     # direito: cura em você mesmo (e não esquiva)
			confirm_heal(null)
		elif heal_armed and Input.is_action_just_pressed("dodge"):
			_disarm_heal()       # esquiva pelo teclado desiste da Cura
	if area_armed != "":
		_update_area_aim(delta)
		if area_armed != "" and Input.is_action_just_pressed("attack"):
			armed_click = true   # esquerdo: solta a habilidade no círculo
			confirm_area()
		elif area_armed != "" and Input.is_action_just_pressed("aim"):
			aim_click = true     # direito: desiste (e não esquiva)
			_disarm_area()
		elif area_armed != "" and Input.is_action_just_pressed("dodge"):
			_disarm_area()
	if Input.is_action_just_pressed("dodge") and not aim_click:
		_dodge_pressed(dir)
	if look["class"] != "bow" or busy:
		aiming = false
	if busy:
		pass   # habilidade em execução: sem ataque nem arco
	elif look["class"] == "bow":
		_update_bow(delta)
	elif Input.is_action_just_pressed("attack") and not armed_click:
		_try_attack()
	for i in ItemDB.SLOT_COUNT:
		if Input.is_action_just_pressed("spell_%d" % (i + 1)):
			use_slot(i + 1)
	# soltou a tecla da habilidade em execução (ex.: o arqueiro solta a flecha ao largar a tecla)
	if ability != "" and ability_slot >= 1 and Input.is_action_just_released("spell_%d" % ability_slot):
		_ab_module(ability).release(self)
	if Input.is_action_just_pressed("potion"):
		_quick_potion("health_potion")
	# F divide a tecla: perto de um veio/árvore coleta (ou para de coletar); longe, toma a poção de mana
	gather_target = GatherAction.nearest(self) if ability == "" else null
	var gather_key := Input.is_action_just_pressed("gather")
	var gathered := false
	if gather_key and ability == GatherAction.ID:
		end_ability()
		gathered = true
	elif gather_key and gather_target and ability == "":
		start_gather(gather_target)
		gathered = true
	if Input.is_action_just_pressed("mana_potion") and not gathered:
		_quick_potion("mana_potion")
	if Input.is_action_just_pressed("eat"):
		Game.eat_selected()
	if Input.is_action_just_pressed("food_next"):
		Game.cycle_food()
	var scene := get_tree().current_scene
	# F5/F9: no solo grava/relê o save solo; no online não fazem nada (o personagem mora no servidor)
	if Input.is_action_just_pressed("quicksave"):
		if scene.has_method("quick_save"):
			scene.quick_save()
		else:
			Econ.quick_save(global_position, model.rotation.y)
	if Input.is_action_just_pressed("quickload"):
		if scene.has_method("quick_load"):
			scene.quick_load()
			return
		elif Econ.quick_load():
			return

	_find_interact_target()
	if interact_wait_release and not Input.is_action_pressed("interact"):
		interact_wait_release = false
	if Input.is_action_just_pressed("interact") and interact_target and not interact_wait_release:
		interact_target.interact(self)

	# orientação do modelo: mira para frente da câmera ao atacar/conjurar, senão para onde anda
	var face := Vector3.ZERO
	if attacking or cast_timer > 0 or drawing or aiming or blocking:
		face = fwd
	elif dodge_timer > 0:
		face = dodge_dir
	elif dir.length() > 0.1:
		face = dir
	if face != Vector3.ZERO and not busy:   # a habilidade mantém a direção em que começou
		var turn := 22.0 if (attacking or cast_timer > 0 or drawing or dodge_timer > 0) else 13.0
		model.rotation.y = lerp_angle(model.rotation.y, atan2(face.x, face.z), 1.0 - exp(-turn * delta))

	move_and_slide()
	if global_position.y < -25:
		global_position = spawn_point
		velocity = Vector3.ZERO

	_update_attack(delta)
	_animate(delta)
	_update_camera(delta)


func _tick_timers(delta: float) -> void:
	invuln = max(0.0, invuln - delta)
	cast_timer = max(0.0, cast_timer - delta)
	stamina_delay = max(0.0, stamina_delay - delta)
	for k in cooldowns:
		cooldowns[k] = max(0.0, cooldowns[k] - delta)
	Game.tick_buffs(delta)


func _regen(delta: float) -> void:
	if Game.admin_mode():
		# modo admin: vida, mana, fôlego e fúria sempre cheios
		Game.hp = Game.max_hp()
		Game.mp = Game.max_mp()
		Game.stamina = Game.max_stamina()
		Game.fury = Game.FURY_MAX
		return
	Game.mp = min(Game.max_mp(), Game.mp + Game.mp_regen() * delta)
	Game.hp = min(Game.max_hp(), Game.hp + Game.hp_regen() * delta)
	if stamina_delay <= 0:
		var regen := 32.0 * (ShieldRules.REGEN_MULT if blocking else 1.0)   # escudo erguido recupera devagar
		Game.stamina = min(Game.max_stamina(), Game.stamina + regen * delta)


func facing() -> Vector3:
	return Vector3(sin(model.rotation.y), 0, cos(model.rotation.y))


# ------------------------------------------------------------ escudo
## Escudo na mão secundária (o item pede espada): o botão direito segurado defende (ShieldRules).
func has_shield() -> bool:
	if remote or look.get("class", "") != "sword" or _unarmed():
		return false
	var off: String = Game.equipment.get("offhand", "")
	return off != "" and str(ItemDB.get_item(off).get("needs", "")) == "sword"


## Botão direito segurado com escudo: levanta (com fôlego, sem guarda quebrada, sem golpe/esquiva/habilidade).
func _update_block(delta: float, busy: bool) -> void:
	_block_since += delta
	if _block_since > ShieldRules.CHAIN_RESET:
		_block_chain = 0
	guard_break_t = maxf(0.0, guard_break_t - delta)
	var want := has_shield() and Input.is_action_pressed("aim") and not heal_armed and area_armed == ""
	blocking = want and not busy and not attacking and dodge_timer <= 0 and guard_break_t <= 0.0 \
		and Game.stamina > 0.5 and not dead


## Golpe segurado pelo escudo: só passa `amount` (o que o escudo não segurou), empurra um pouco e faísca.
func _take_blocked(amount: float, from_pos: Vector3) -> void:
	_block_fx(from_pos)
	var push := global_position - from_pos
	push.y = 0
	if push.length() > 0.01:
		push = push.normalized() * (1.5 + 0.6 * minf(_block_chain, 4))   # cada golpe seguido empurra mais
		velocity.x = push.x
		velocity.z = push.z
	invuln = 0.3
	Game.add_fury(amount / Game.max_hp() * 15.0)
	if amount >= 0.5:
		var chip: float = max(1.0, amount * Game.damage_taken_mult())
		Game.hp -= chip
		FX.damage_number(global_position + Vector3.UP * KnightLook.body_y(self, 2.0), str(int(round(chip))), Color(0.75, 0.8, 0.9), 44)
	Game.stats_changed.emit()
	if Game.hp <= 0:
		_die()


## Fôlego acabou com o escudo erguido: o braço cai, cambaleia e fica um tempo sem defender.
func _guard_break() -> void:
	blocking = false
	guard_break_t = ShieldRules.BREAK_TIME
	_block_chain = 0
	Game.notify.emit("Guarda quebrada!", Color(1, 0.55, 0.35))
	Sfx.play("slam", 0.1, -4.0)
	add_shake(0.45)


## Faíscas e som de metal no escudo, do lado de onde veio o golpe.
func _block_fx(from_pos: Vector3) -> void:
	var to := from_pos - global_position
	to.y = 0
	var side := to.normalized() if to.length() > 0.01 else facing()
	FX.burst(global_position + Vector3.UP * KnightLook.body_y(self, 1.05) + side * 0.45, Color(1.0, 0.85, 0.45), 14, 3.5, 0.08, 0.35)
	Sfx.play("sword_hit", 0.12, -2.0)
	add_shake(0.12 + 0.05 * minf(_block_chain, 4))


# ------------------------------------------------------------ esquiva
## Tecla de esquiva: com habilidade em execução, só esquiva se ela puder ser cancelada agora. O módulo
## encerra a habilidade (dodge_cancel): a Chuva de Meteoros termina "macia", deixando cair o que está no ar.
func _dodge_pressed(dir: Vector3) -> void:
	if ability != "":
		var m := _ab_module(ability)
		if not m.can_dodge_cancel(self):
			return
		m.dodge_cancel(self)
		end_ability()   # garante o fim mesmo se o módulo não encerrar
	_try_dodge(dir)


func _try_dodge(dir: Vector3) -> void:
	if dodge_timer > 0 or not is_on_floor() or Game.stamina < 20.0:
		return
	Game.stamina -= 20.0
	stamina_delay = 0.7
	dodge_dir = dir.normalized() if dir.length() > 0.1 else facing()
	dodge_timer = DODGE_TIME
	invuln = DODGE_TIME + 0.08
	model.rotation.y = atan2(dodge_dir.x, dodge_dir.z)   # rola já virado para onde vai
	attacking = false
	buffered_attack = false
	_cancel_draw()
	Sfx.play("dodge", 0.1, -4.0)


# ------------------------------------------------------------ ataque corpo a corpo
func _try_attack() -> void:
	if dodge_timer > 0:
		return
	if attacking:
		if MageStaffAttack.active(self):
			if combo == MageStaffAttack.RECOVER:
				buffered_attack = true   # clicou na volta do cajado: a próxima carga começa logo em seguida
			return
		if attack_timer > _swing_time(combo) * 0.35:
			buffered_attack = true
		return
	_start_swing()


## Fôlego de um golpe básico (o combo custa um pouco mais a cada golpe): espada 5/6/7 (o giro do combo com
## escudo, 4º golpe, 8), cajado 2,5/3/3,5.
static func swing_stamina(staff: bool, hit: int) -> float:
	return (2.0 + hit * 0.5) if staff else (4.0 + hit * 1.0)


func _start_swing() -> void:
	if Game.stamina < SWING_STAMINA_MIN:
		Game.notify.emit("Sem fôlego!", Color(1, 0.8, 0.5))
		return
	if MageStaffAttack.active(self):
		MageStaffAttack.begin(self)   # cajado: Bola de Fogo (clique ou segurar)
		return
	combo = (combo % _combo_len()) + 1 if combo_window > 0 else 1
	attacking = true
	_recover_t = -1.0
	if _dense_combo():
		_swing_from = KnightAnim.capture_pose(parts)   # o golpe nasce da pose em que o corpo está
	attack_timer = 0.0
	hit_done = false
	var staff: bool = look["class"] == "staff"
	Game.stamina = maxf(0.0, Game.stamina - swing_stamina(staff, combo) * (1.4 if _great() else 1.0))
	stamina_delay = 0.4
	if staff:
		Sfx.play("staff_wind", 0.15, -8.0)
		return
	if is_on_floor():
		var f := facing()
		var push := 1.5 if _unarmed() else (2.2 if _great() else 3.0)   # o soco é um passo curto, não uma estocada
		if _great() and _finisher():
			push = 3.4   # o golpe final da montante salta à frente
		if _shield_combo() and _finisher():
			push = SHIELD_SPIN_PUSH
		velocity.x += f.x * push
		velocity.z += f.z * push
	Sfx.play(_attack_sound(), 0.1, -3.0 if _unarmed() else 0.0)


func _update_attack(delta: float) -> void:
	if not attacking:
		combo_window = max(0.0, combo_window - delta)
		return
	if MageStaffAttack.active(self):
		if input_locked or horde_frozen or chat_typing or Loading.covering:
			MageStaffAttack.cancel(self)
			return
		MageStaffAttack.update(self, delta, Input.is_action_pressed("attack"))
		return
	attack_timer += delta
	var dur := _swing_time(combo)
	var t := attack_timer / dur
	if t >= (0.35 if look["class"] == "staff" else (KnightMovesGreat.HIT_AT if _great() else 0.42)) and not hit_done:
		hit_done = true
		match look["class"]:
			"staff":
				_scepter_shot()   # o cajado (Bola de Fogo) sai antes, por MageStaffAttack
			"bow":
				pass   # o disparo do arco acontece ao soltar o botão
			_:
				_do_hit()
	if t >= 1.0:
		attacking = false
		combo_window = 0.45
		if not (look["class"] == "bow" and aiming):   # mirando o arco continua de lado: sem desgirar
			_end_swing_twist()
		if buffered_attack:
			buffered_attack = false
			_start_swing()


func _do_hit() -> void:
	var shield := _shield_combo()
	var great := _great()
	var mult: float = (SHIELD_SWING_MULT if shield else (GREAT_SWING_MULT if great else SWING_MULT))[clampi(combo, 1, _combo_len()) - 1]
	var fist := _unarmed()
	var fin := _finisher()
	var reach := (2.2 if fin else 2.0) if fist else (2.9 if fin else 2.4)
	if great:
		reach = GREAT_SLAM_AHEAD + GREAT_SLAM_RADIUS if fin else GREAT_REACH
	var hit_any := false
	var flesh := false   # acertou algo que não é slime: lâmina em carne; só slime: só a lâmina
	var hit_enemy := false
	var f := facing()
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var to: Vector3 = e.global_position - global_position
		to.y = 0
		var dist := to.length()
		if dist > reach + e.radius:
			continue
		if great and fin:
			var c: Vector3 = global_position + f * GREAT_SLAM_AHEAD
			if Vector2(e.global_position.x - c.x, e.global_position.z - c.z).length() > GREAT_SLAM_RADIUS + e.radius:
				continue
		elif great:
			if dist > 0.6 and f.dot(to.normalized()) < GREAT_ARC:
				continue
		elif (not fin or fist) and dist > 0.6 and f.dot(to.normalized()) < 0.3:
			continue
		var crit: bool = randf() < Game.crit_chance()
		var dmg: float = EnchantHit.scale(e, Game.melee_damage() * mult * randf_range(0.9, 1.1) * (1.8 if crit else 1.0))
		e.take_damage(dmg, global_position, crit, 2.5 if _weapon_fx() == "slow" else 0.0, 0.0, 0.0, EnchantHit.mix())
		Game.on_damage_dealt(dmg, e.max_hp)
		EnchantHit.on_hit(e, dmg)   # efeito do elemento da arma encantada
		hit_any = true
		hit_enemy = true
		flesh = flesh or str(e.data.get("model", "")) != "slime"
	if hit_enemy and fist:
		Sfx.play("punch_hit", 0.12)
	elif hit_enemy:
		Sfx.play(Sfx.sword_hit(flesh, Sfx.heavy_sword(_weapon_id())), 0.1)
	if great and fin:
		add_shake(0.3)   # golpe final da montante: a câmera dá um tranco, acertando alguém ou não
	if hit_any:
		add_shake(0.22 if fin else 0.12)


func _swing_time(c: int) -> float:
	match look["class"]:
		"staff":
			if not _is_scepter():
				return MageStaffAttack.phase_time(c)
			return STAFF_TIMES[clampi(c, 1, 3) - 1]
		"bow":
			return BOW_RECOVER
	if _shield_combo():
		return SHIELD_SWING_TIMES[clampi(c, 1, SHIELD_SWING_TIMES.size()) - 1]
	if _great():
		return GREAT_SWING_TIMES[clampi(c, 1, 3) - 1]
	return (PUNCH_TIMES if _unarmed() else SWING_TIMES)[clampi(c, 1, 3) - 1]


## Espada com escudo na outra mão (do jogo local ou, numa réplica, do último visual recebido): o golpe básico
## é o combo de 4 golpes de KnightMovesShield.
func _shield_combo() -> bool:
	if look["class"] != "sword" or _unarmed():
		return false
	var off := str(_last_look.get("offhand", "")) if remote else str(Game.equipment.get("offhand", ""))
	return off != "" and str(ItemDB.get_item(off).get("needs", "")) == "sword"


## Montante na mão (do jogo local ou, numa réplica, do último visual recebido): golpes de duas mãos.
func _great() -> bool:
	return look["class"] == "sword" and ItemDB.is_two_handed(_weapon_id())


## Golpes do combo básico: 4 com espada e escudo, 3 nos outros.
func _combo_len() -> int:
	return SHIELD_SWING_TIMES.size() if _shield_combo() else 3


## O golpe atual é o último do combo (giro da espada, uppercut, leque do cajado): mais alcance e tranco.
func _finisher() -> bool:
	return combo >= _combo_len()


## Combo tirado do Mixamo (espada com escudo, montante): trilhas densas que emendam umas nas outras e nascem da pose
## em que o corpo está (KnightAnim.capture_pose).
func _dense_combo() -> bool:
	return _shield_combo() or _great()


## Fim do golpe: o giro do tronco volta. Nos combos do Mixamo (_dense_combo) as trilhas emendam pelo giro em -PI..PI
## (KnightAnim.unwind_twist), sem pular a pose; nos outros o giro zera na hora.
func _end_swing_twist() -> void:
	if _dense_combo():
		KnightAnim.unwind_twist(parts)
		_swing_from = KnightAnim.capture_pose(parts)   # se nenhum golpe emendar, a volta sai daqui
		_recover_t = 0.0
	else:
		KnightAnim.reset_twist(parts)


## Arma equipada: a do jogo local ou, numa réplica de outro jogador, a do último visual recebido.
func _weapon_id() -> String:
	return str(_last_look.get("weapon", "")) if remote else str(Game.equipment.weapon)


## Sem arma na mão (a classe cai em "sword", mas o golpe é o soco).
func _unarmed() -> bool:
	return look["class"] == "sword" and _weapon_id() == ""


## Som do golpe (do jogador local e das réplicas), pela classe da arma que ele carrega.
func _attack_sound() -> String:
	match look["class"]:
		"staff":
			return "staff_wind"
		"bow":
			return "bow_shot"
	if _unarmed():
		return "punch"
	return "sword_swing_heavy" if Sfx.heavy_sword(_weapon_id()) else "sword_swing"


func _weapon_fx() -> String:
	return ItemDB.get_item(Game.equipment.weapon).get("fx", "")


func _weapon_color() -> Color:
	return ItemDB.get_item(Game.equipment.weapon).get("color", Color(0.6, 0.8, 1.0))


# ------------------------------------------------------------ ataque à distância (cajado e arco)
## Para onde a câmera aponta: o que o raio da câmera acerta (cenário e inimigos) em até 80 m, ou o fim do raio.
func aim_point() -> Vector3:
	var from := camera.global_position
	var to := from - camera.global_basis.z * 80.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else to


## Direção da mira: do ponto de origem até onde a câmera aponta.
func aim_dir(origin: Vector3) -> Vector3:
	return (aim_point() - origin).normalized()


## De onde saem as magias: a gema do cajado, ou a mão esquerda sem cajado.
func spell_origin() -> Vector3:
	if look["class"] == "staff":
		return weapon_tip()
	var hand := model.find_child("ArmL_Hand", true, false) as MeshInstance3D
	if hand and hand.is_inside_tree():
		return hand.global_transform * hand.get_aabb().get_center() + facing() * 0.25
	return global_position + Vector3.UP * KnightLook.body_y(self, 1.3) + facing() * 0.6


func weapon_tip() -> Vector3:
	var tip: Node3D = look.get("tip")
	if tip and is_instance_valid(tip) and tip.is_inside_tree():
		return tip.global_position
	return global_position + Vector3.UP * KnightLook.body_y(self, 1.3) + facing() * 0.6


## O cetro usa o visual e a animação do cajado (look["class"] == "staff"); só o ataque e o kit mudam.
func _is_scepter() -> bool:
	return ItemDB.weapon_class(_weapon_id()) == "scepter"


## Cetro: esfera de luz curta (alcance LIGHT_ORB_RANGE), dourada e branca; o dano escala com INT (melee_damage).
## O 3º golpe do combo é mais forte.
func _scepter_shot() -> void:
	var origin := weapon_tip()
	var d := aim_dir(origin)
	var crit: bool = randf() < Game.crit_chance()
	_spawn_projectile("light_orb", origin, d, Game.melee_damage() * (1.25 if combo == 3 else 1.0) * (1.8 if crit else 1.0), crit, 0)
	Network.send_event("light_orb", origin, d)
	Sfx.play("arcane_cast", 0.12, -4.0)


## Arco: segurar o botão direito mira (o arco sobe, a flecha encaixa e a corda vem até o queixo) e o clique
## esquerdo dispara (dano e alcance crescem com a tensão). Mirando, depois de cada tiro ele encaixa a próxima
## sozinho. Soltar o botão direito sem atirar baixa o arco. Clique esquerdo sem mirar = tiro rápido: puxa
## pela metade bem depressa e solta sozinho.
func _update_bow(delta: float) -> void:
	aiming = Input.is_action_pressed("aim") and dodge_timer <= 0
	var shoot := Input.is_action_just_pressed("attack")
	if attacking and aiming and shoot:
		_shot_queued = true   # clicou ainda na recuperação: atira assim que a próxima flecha estiver puxada
	if not drawing and not attacking and dodge_timer <= 0 and (aiming or shoot):
		if Game.stamina < ARROW_STAMINA:
			if shoot or Input.is_action_just_pressed("aim"):
				Game.notify.emit("Sem fôlego!", Color(1, 0.8, 0.5))
			_shot_queued = false
			return
		drawing = true
		draw_t = 0.0
		_bow_full_at = -1.0
		_bow_snap = not aiming
		_shot_queued = aiming and (_shot_queued or shoot)
		Sfx.play("bow_draw", 0.05, -4.0)
		shoot = false   # o clique que começou o tiro rápido não conta de novo
	if not aiming and not drawing:
		_shot_queued = false
	if not drawing:
		return
	stamina_delay = 0.4
	var was := draw_t
	if _bow_snap:
		draw_t = min(draw_t + delta * BOW_FULL * BOW_SNAP_CHARGE / BOW_SNAP_TIME, BOW_FULL)
		if aiming:
			_bow_snap = false   # começou a mirar no meio do tiro rápido: vira tiro mirado
		elif bow_charge() >= BOW_SNAP_CHARGE:
			release_arrow()
		return
	draw_t = min(draw_t + delta, BOW_FULL)
	if was < BOW_FULL and draw_t >= BOW_FULL:
		Sfx.play("bow_full", 0.05, -6.0)
		_bow_full_at = Time.get_ticks_msec() / 1000.0
		if _weapon_fx() == "crescent":   # o instante da soltura perfeita: a lua acende na ponta do arco
			HolyFX.star(weapon_tip(), BowMythic.MOON, 0.45)
	if not aiming:
		_cancel_draw()   # baixou o arco sem atirar
		return
	if shoot:
		_shot_queued = true
	if _shot_queued and draw_t >= BOW_MIN_DRAW:
		release_arrow()


## Inclinação da mira do arco a partir do ombro (o braço e a flecha apontam para onde a câmera mira).
## Réplicas não têm a câmera do dono: miram na horizontal (e a Flecha do Vendaval, que voa na horizontal).
func _update_aim_pitch() -> void:
	var pitch := 0.0
	if not remote and camera and ability != "bow_gale":   # o Vendaval sai na horizontal: o braço também
		var shoulder := global_position + Vector3.UP * KnightLook.body_y(self, 1.42)
		pitch = clampf(asin(clampf(aim_dir(shoulder).y, -1.0, 1.0)), -0.9, 0.9)
	parts["aim_pitch"] = lerpf(float(parts.get("aim_pitch", 0.0)), pitch, 0.35)


func bow_charge() -> float:
	return clampf(draw_t / BOW_FULL, 0.0, 1.0) if drawing else 0.0


## Flecha na linha da mira: a câmera fica sobre o ombro direito e o arco à esquerda dela, então uma flecha
## que saísse do arco só cruzaria a mira num ponto (e passaria à esquerda de quem está mais perto). Ela voa
## na linha da câmera, nascendo na altura do arco; o visual começa no arco e encaixa na linha em seguida
## (projectile.gd, vis_offset). A direção sobe o bastante para a queda da flecha terminar no ponto mirado.
## Devolve [origem, direção, deslocamento do visual]. Réplicas (sem câmera): do arco para a mira.
func arrow_launch(spd: float) -> Array:
	var tip := weapon_tip()
	if remote or camera == null or not camera.is_inside_tree():
		return [tip, aim_dir(tip), Vector3.ZERO]
	var co := camera.global_position
	var f := -camera.global_basis.z
	var start := co + f * maxf((tip - co).dot(f), 0.5)
	var target := aim_point()
	var t := minf(start.distance_to(target), ARROW_AIM_RANGE) / maxf(spd, 1.0)   # sem alvo: o raio vai a 80 m
	target += Vector3.UP * 0.5 * PROJECTILE.ARROW_DROP * t * t
	return [start, (target - start).normalized(), tip - start]


func release_arrow() -> void:
	var charge := bow_charge()
	drawing = false
	draw_t = 0.0
	Game.stamina = max(0.0, Game.stamina - ARROW_STAMINA)
	var spd := lerpf(22.0, 42.0, charge)
	var launch := arrow_launch(spd)
	var origin: Vector3 = launch[0]
	var dir: Vector3 = launch[1]
	var full := charge >= 0.99
	var fx := _weapon_fx()
	var crit: bool = randf() < Game.crit_chance() + (0.1 if full else 0.0)
	# Crescente Gêmeo: soltar logo depois da tensão máxima = crítico garantido e a flecha fantasma
	var perfect := fx == "crescent" and full and BowMythicRules.perfect_release(_bow_full_at, Time.get_ticks_msec() / 1000.0)
	if perfect:
		crit = true
	var dmg := Game.melee_damage() * lerpf(0.45, 1.5, charge) * (1.8 if crit else 1.0)
	_bow_snap = false
	_shot_queued = false
	var pierce := 2 if full else 0
	if fx == "pierce":
		pierce += 2
	var dirs := [dir]
	if full and fx == "multishot":
		dirs = [dir.rotated(Vector3.UP, -0.1), dir, dir.rotated(Vector3.UP, 0.1)]
	for d in dirs:
		var ar = _spawn_projectile("arrow", origin, d, dmg, crit, pierce, spd)
		ar.vis_offset = launch[2]
		ar.full = full
		if fx == "gale" and full:
			ar.bounces = int(BowMythicRules.GALE.bounces)
		Network.send_event("arrow", origin, BowMythicRules.encode_dir(d, full))
	if BowMythicRules.is_mythic_fx(fx) and full:
		FXToon.muzzle(weapon_tip(), dir, BowMythic.trail_palette(fx), 8, 1.3)
	if fx == "gale" and full:
		_gale_leap(dir)
	if perfect:
		_crescent_perfect(dmg, spd)
	attacking = true
	combo = 1
	attack_timer = 0.0
	hit_done = true
	Sfx.play("bow_shot", 0.08, 0.0 if full else -3.0)
	if full:
		add_shake(0.06)


## Rei dos Ventos: o tiro tensionado joga o arqueiro para trás (a esquiva do jogo, na direção oposta à mira).
func _gale_leap(dir: Vector3) -> void:
	var back := Vector3(-dir.x, 0.0, -dir.z)
	if back.length() < 0.1:
		return
	dodge_dir = back.normalized()
	dodge_timer = float(BowMythicRules.GALE.dash)
	invuln = maxf(invuln, dodge_timer + 0.05)
	FXToon.ground_gust(global_position, 2.2, FXToon.WIND, 0.4)


## Crescente Gêmeo: soltura perfeita. A lua estoura na ponta do arco e uma flecha fantasma repete o tiro.
func _crescent_perfect(dmg: float, spd: float) -> void:
	HolyFX.star(weapon_tip(), BowMythic.MOON, 0.8)
	HolyFX.sparkles(weapon_tip(), BowMythic.MOON, 12, 0.4, 2.5, 0.3, 0.2)
	Sfx.play("bow_full", 0.05, -2.0)
	get_tree().create_timer(float(BowMythicRules.CRESCENT.ghost_delay)).timeout.connect(
		_crescent_ghost.bind(dmg * float(BowMythicRules.CRESCENT.ghost_dmg), spd))


func _crescent_ghost(dmg: float, spd: float) -> void:
	if dead or not is_inside_tree():
		return
	var launch := arrow_launch(spd)
	var ar = _spawn_projectile("arrow", launch[0], launch[1], dmg, true, 2, spd, "", BowMythic.MOON.core)
	ar.vis_offset = launch[2]
	ar.trail = BowMythic.MOON
	Network.send_event("arrow", launch[0], launch[1])
	HolyFX.star(weapon_tip(), BowMythic.MOON, 0.5)


func _cancel_draw() -> void:
	drawing = false
	draw_t = 0.0
	_bow_full_at = -1.0
	_bow_snap = false
	_shot_queued = false


func _spawn_projectile(kind: String, origin: Vector3, d: Vector3, dmg: float, crit: bool, pierce: int, spd := 30.0, fx_override := "", color_override := Color(0, 0, 0, 0)) -> Node:
	var p := PROJECTILE.new()
	p.kind = kind
	p.direction = d
	p.damage = dmg
	p.crit = crit
	p.pierce = pierce
	p.fx = _weapon_fx() if _weapon_fx() != "multishot" else ""
	p.color = _weapon_color()
	p.element = Sfx.staff_element(_weapon_id())
	if fx_override != "":
		p.fx = fx_override
	if color_override.a > 0.0:
		p.color = color_override
	if kind == "light_orb":
		p.color = LIGHT_ORB_COLOR
	p.speed = spd if kind == "arrow" else 26.0
	p.life = 1.8 if kind == "arrow" else (LIGHT_ORB_RANGE / 26.0 if kind == "light_orb" else 1.2)
	if kind == "holy_lance":   # Lança de Luz: rápida, longa e sem o efeito da arma (o dano já é dela)
		p.fx = ""
		p.color = HolyFX.GOLD
		p.speed = ScepterAbilities.LANCE_SPEED
		p.life = ScepterAbilities.LANCE_RANGE / ScepterAbilities.LANCE_SPEED
	get_tree().current_scene.add_child(p)
	p.global_position = origin
	return p


# ------------------------------------------------------------ magias
static func _make_cooldowns() -> Dictionary:
	var d := {}
	for id in ItemDB.ABILITIES:
		d[id] = 0.0
	return d


## Usa a habilidade do slot (1..5) do kit da arma equipada; slot sem habilidade não faz nada.
func use_slot(slot: int) -> void:
	for id in Game.ability_kit():
		if ItemDB.ABILITIES[id].slot == slot:
			var before := ability
			cast(id)
			if before == "" and ability != "":   # só quando este cast começou a habilidade
				ability_slot = slot
			return


func cast(id: String) -> void:
	var sp: Dictionary = ItemDB.ABILITIES[id]
	if id == "heal" and heal_armed:
		_disarm_heal()   # a mesma tecla de novo desiste da Cura
		return
	if area_armed != "" and not _area_confirming:
		var same := area_armed == id
		_disarm_area()   # outra habilidade (ou a mesma tecla de novo) desiste da área preparada
		if same:
			return
	if id != "heal":
		_disarm_heal()
	if not Game.knows_ability(id):
		Game.notify.emit("%s exige nível %d" % [sp.name, sp.level], Color(1, 0.6, 0.6))
		Sfx.play("error", 0.0, -6.0)
		return
	if cooldowns[id] > 0 or attacking or dodge_timer > 0 or ability != "":
		return
	if sp.ultimate and not Game.fury_full():
		Game.notify.emit("Fúria incompleta!", Color(1.0, 0.55, 0.3))
		return
	if sp.cost > 0 and Game.mp < sp.cost:
		Game.notify.emit("Mana insuficiente!", Color(0.6, 0.7, 1.0))
		Sfx.play("error", 0.0, -6.0)
		return
	if sp.get("aim", "") == "ground" and not _area_confirming:
		_arm_area(id)   # a mana e a recarga só saem na confirmação (confirm_area)
		return
	# habilidade de arma (espada, cajado, arco): o módulo da classe executa. Ainda sem implementação
	# (ready == false): "Em breve", sem custo nem recarga. As magias antigas seguem no match abaixo.
	if not id in ["heal", "frost_nova"]:
		var cd_mult := Game.cooldown_mult()   # antes do use(): o buff que a habilidade dá não encurta a própria recarga
		if not sp.ready or not _ab_module(id).use(self, id):
			Game.notify.emit("Em breve!", Color(0.85, 0.8, 0.65))
			return
		# a ultimate zera a fúria só quando realmente começa; recarga tem dono único: aqui
		if sp.ultimate:
			Game.fury = 0.0
		if sp.cost > 0:
			Game.mp -= sp.cost
		cooldowns[id] = Game.ability_cooldown(id, ItemDB.cooldown_of(id), cd_mult)
		Game.stats_changed.emit()
		return
	_cancel_draw()
	if id == "heal":
		_arm_heal()   # a mana e a recarga só saem na confirmação (confirm_heal)
		return
	if sp.cost > 0:
		Game.mp -= sp.cost
	cooldowns[id] = sp.cooldown * Game.cooldown_mult()
	cast_timer = 0.4
	_start_cast_pose(id)
	if id == "frost_nova":
		_cast_frost_nova()
	Game.stats_changed.emit()


## Vida recebida de uma Cura (a própria no solo, ou a de um healer vinda do servidor).
func receive_heal(amount: float) -> void:
	if dead:   # caído não é curado (o servidor também pula, mas o estado dele pode estar atrasado)
		return
	var gained := minf(amount, Game.max_hp() - Game.hp)
	Game.hp = min(Game.max_hp(), Game.hp + amount)
	_heal_fx()
	FX.damage_number(global_position + Vector3.UP * KnightLook.body_y(self, 2.2), "+%d" % maxf(gained, 0.0), Color(0.4, 1.0, 0.5))
	Game.stats_changed.emit()


# ------------------------------------------------------------ Cura com mira
## A tecla da Cura prepara a magia (mãos brilhando); enquanto preparada, o aliado mais perto do centro da
## mira (até HEAL_RANGE m, à vista) ganha a borda verde (TargetHighlight) — sem aliado na mira, a borda fica
## em você. O clique esquerdo confirma: cura quem está marcado (não dá o ataque básico); o botão direito
## cura sempre você mesmo. A tecla de novo, a esquiva pelo teclado,
## uma habilidade, a morte ou HEAL_ARM_TIME s sem confirmar desistem (sem gastar mana nem recarga).
const HEAL_RANGE := 25.0
const HEAL_ARM_TIME := 8.0
const HEAL_AIM_SCREEN := 0.09   ## quão longe do centro da tela (fração da altura) o aliado ainda conta como mirado
var heal_armed := false
var heal_target: Node3D = null
var _heal_arm_t := 0.0
var _heal_charge: Node3D
static var _heal_hint_done := false


func _arm_heal() -> void:
	heal_armed = true
	_heal_arm_t = HEAL_ARM_TIME
	heal_target = null
	var tip: Node3D = look.get("tip")
	_heal_charge = HolyFX.charge_stream(tip if tip and is_instance_valid(tip) else model)
	Sfx.play("arcane_cast", 0.1, -12.0)
	if not _heal_hint_done:
		_heal_hint_done = true
		Game.notify.emit("Cura pronta: clique esquerdo cura o aliado na mira · botão direito cura você", Color(0.55, 1.0, 0.6))


func _disarm_heal() -> void:
	if not heal_armed:
		return
	heal_armed = false
	_mark_heal_target(heal_target, false)
	heal_target = null
	if _heal_charge and is_instance_valid(_heal_charge):
		_heal_charge.queue_free()
	_heal_charge = null


## Um quadro com a Cura preparada: troca a borda para quem está na mira e desiste quando não dá mais.
func _update_heal_aim(delta: float) -> void:
	_heal_arm_t -= delta
	if heal_target != null and not is_instance_valid(heal_target):
		heal_target = null   # o marcado saiu (trocou de zona, desconectou)
	if _heal_arm_t <= 0.0 or dead or ability != "" or not _is_scepter():
		_disarm_heal()
		return
	var t := _find_heal_target()
	if t == null:
		t = self
	if t != heal_target:
		_mark_heal_target(heal_target, false)
		heal_target = t
		_mark_heal_target(t, true)


func _mark_heal_target(p: Node3D, on: bool) -> void:
	if p != null and is_instance_valid(p) and p.has_method("set_heal_highlight"):
		p.set_heal_highlight(on)


## Aliado (réplica viva e à vista, até HEAL_RANGE m) mais perto do centro da mira, ou null.
func _find_heal_target() -> Node3D:
	if camera == null or not camera.is_inside_tree():
		return null
	var size := get_viewport().get_visible_rect().size
	var center := size * 0.5
	var best: Node3D = null
	var best_d := size.y * HEAL_AIM_SCREEN
	for p in get_tree().get_nodes_in_group("players"):
		if p == self or not p.remote or p.dead or not p.is_visible_in_tree():
			continue
		var chest: Vector3 = p.global_position + Vector3.UP * KnightLook.body_y(p, 1.0)
		if chest.distance_to(global_position) > HEAL_RANGE or camera.is_position_behind(chest):
			continue
		# a silhueta toda conta: peito, cabeça e pés
		var d := camera.unproject_position(chest).distance_to(center)
		d = minf(d, camera.unproject_position(p.global_position + Vector3.UP * KnightLook.body_y(p, 1.9)).distance_to(center))
		d = minf(d, camera.unproject_position(p.global_position + Vector3.UP * 0.25).distance_to(center))
		if d < best_d and _sees(p, chest):
			best = p
			best_d = d
	return best


## Nada do cenário entre a câmera e `at` (no corpo de `p`).
func _sees(p: Node3D, at: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(camera.global_position, at, 1)
	q.exclude = [get_rid(), (p as CollisionObject3D).get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Solta a Cura preparada em `target` (outro jogador) ou, sem alvo (null ou você), em você.
## Online o servidor decide e manda a vida (_you_were_healed); no solo cura direto.
func confirm_heal(target: Node3D = null) -> void:
	_disarm_heal()
	var sp: Dictionary = ItemDB.ABILITIES.heal
	if dead or cooldowns.heal > 0.0 or Game.mp < sp.cost:
		return
	var ally: Node3D = target if target != null and target != self and is_instance_valid(target) and target.get("remote") else null
	Game.mp -= sp.cost
	cooldowns.heal = sp.cooldown * Game.cooldown_mult()
	cast_timer = 0.4
	_start_cast_pose("heal")
	if Network.is_client():
		Network.request_heal(ally.peer_id if ally else 0)
	else:
		receive_heal(Game.heal_amount())
	if ally:
		HolyFX.heal_beam(spell_origin(), ally, true)
		Sfx.play_at("heal", global_position, 0.05, -6.0)
		Network.send_event("heal", global_position, ally.global_position)
	else:
		Network.send_event("heal", global_position, Vector3.ZERO)
	Game.stats_changed.emit()


# ------------------------------------------------------------ habilidade com mira no chão
## Habilidades com `aim: "ground"` (ItemDB.ABILITIES): a tecla prepara e mostra o círculo no chão onde a
## câmera aponta, limitado a `aim_range` m do jogador; o clique esquerdo confirma (em vez do ataque
## básico) e a habilidade cai ali; o botão direito desiste
## (o módulo da classe lê `area_point`). A tecla de novo, outra habilidade, a esquiva pelo teclado, a morte
## ou AREA_ARM_TIME s sem confirmar desistem (sem gastar mana nem recarga).
const AREA_ARM_TIME := 8.0
var area_armed := ""             ## id da habilidade esperando o ponto ("" = nenhuma)
var area_point := Vector3.ZERO   ## onde a habilidade cai (o último ponto mirado)
var _area_arm_t := 0.0
var _area_mark: Node3D
var _area_confirming := false
static var _area_hint_done := false


func _arm_area(id: String) -> void:
	_disarm_heal()
	area_armed = id
	_area_arm_t = AREA_ARM_TIME
	area_point = _area_target(id)
	_area_mark = HolyFX.area_marker(float(ItemDB.ABILITIES[id].aim_radius))
	if _area_mark:
		get_tree().current_scene.add_child(_area_mark)
		_area_mark.global_position = area_point
	Sfx.play("arcane_cast", 0.1, -12.0)
	if not _area_hint_done:
		_area_hint_done = true
		Game.notify.emit("Escolha onde a habilidade cai: clique esquerdo confirma · botão direito cancela", Color(1.0, 0.87, 0.4))


func _disarm_area() -> void:
	if area_armed == "":
		return
	area_armed = ""
	if _area_mark and is_instance_valid(_area_mark):
		_area_mark.queue_free()
	_area_mark = null


## Um quadro com a área preparada: o círculo segue a mira; desiste quando não dá mais.
func _update_area_aim(delta: float) -> void:
	_area_arm_t -= delta
	if _area_arm_t <= 0.0 or dead or ability != "" or not (area_armed in Game.ability_kit()):
		_disarm_area()
		return
	area_point = _area_target(area_armed)
	if _area_mark and is_instance_valid(_area_mark):
		_area_mark.global_position = area_point


## Ponto no chão onde a habilidade `id` cairia agora: onde a câmera aponta, limitado a `aim_range` m do
## jogador no plano e baixado até o chão do cenário (sem chão por perto: a altura do jogador).
func _area_target(id: String) -> Vector3:
	var target := aim_point()
	var origin := global_position
	var flat := Vector3(target.x - origin.x, 0.0, target.z - origin.z)
	var reach: float = ItemDB.ABILITIES[id].aim_range
	if flat.length() > reach:
		flat = flat.normalized() * reach
	var p := origin + flat
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, maxf(origin.y, target.y) + 6.0, p.z),
		Vector3(p.x, minf(origin.y, target.y) - 12.0, p.z), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else Vector3(p.x, origin.y, p.z)


## Solta a habilidade preparada no ponto mirado (gasta mana e recarga como um uso normal).
func confirm_area() -> void:
	if area_armed == "":
		return
	var id := area_armed
	area_point = _area_target(id)
	_disarm_area()
	_area_confirming = true
	cast(id)
	_area_confirming = false


## Liga/desliga a borda de alvo da Cura neste jogador (TargetHighlight sob o modelo).
func set_heal_highlight(on: bool) -> void:
	if model == null:
		return
	var hl := model.get_node_or_null("HealMark")
	if on and hl == null and not Network.is_server():
		hl = TargetHighlight.new()
		hl.name = "HealMark"
		model.add_child(hl)
	elif not on and hl:
		hl.name = "HealMarkOld"   # o nome fica livre já: ligar de novo no mesmo quadro cria outro
		hl.queue_free()


## Módulo da classe da arma dona da habilidade `id` (ou do `kind` de um evento remoto).
## Um id de ABILITIES usa a `class`; um kind que não é id (ex.: "bow_gale_fire", "meteor_rain_end") cai no prefixo.
func _ab_module(id: String) -> Object:
	if id == GatherAction.ID:
		return GatherAction
	if id.begins_with(ShieldAbilities.ID):   # a Égide (e os eventos dela) é da espada, mas tem módulo próprio
		return ShieldAbilities
	if id.begins_with(HammerAbilities.ID):   # o Martelo de Energia (e o cancelamento) também tem módulo próprio
		return HammerAbilities
	if id.begins_with(DarkTauntAbilities.ID):   # o Círculo da Provocação Sombria (e o cancelamento) também
		return DarkTauntAbilities
	if id.begins_with(EarthquakeAbilities.ID):  # o Terremoto Devastador (e o cancelamento) também
		return EarthquakeAbilities
	if id.begins_with(PartyShieldAbilities.ID):  # o Grito do Bastião (e o cancelamento) também
		return PartyShieldAbilities
	if id.begins_with(DragSlashAbilities.ID):   # o Corte do Abismo da montante (e o corte e o cancelamento) também
		return DragSlashAbilities
	if id.begins_with(GreatswordSupremeAbilities.ID):   # a Lâmina Suprema da montante (e o cancelamento) também
		return GreatswordSupremeAbilities
	if id.begins_with(GreatswordSpinAbilities.ID):   # o Ciclone de Aço da montante (e o cancelamento) também
		return GreatswordSpinAbilities
	if id.begins_with(GreatswordDarkComboAbilities.ID):   # a Dança do Abismo da montante (e o cancelamento) também
		return GreatswordDarkComboAbilities
	if id.begins_with(FlameChannelAbilities.ID):   # a Canalização de Fogo do cajado (e o fim) também
		return FlameChannelAbilities
	var cls := ""
	if ItemDB.ABILITIES.has(id):
		cls = ItemDB.ABILITIES[id]["class"]
	elif id.begins_with("sword_"):
		cls = "sword"
	elif id.begins_with("bow_"):
		cls = "bow"
	elif id.begins_with("meteor"):
		cls = "staff"
	elif id.begins_with("scepter_"):
		cls = "scepter"
	match cls:
		"staff":
			return StaffAbilities
		"bow":
			return BowAbilities
		"scepter":
			return ScepterAbilities
	return SwordAbilities


## O `kind` de um evento remoto é de uma habilidade de arma (e não de uma magia antiga ou emote)?
func _is_ability_kind(kind: String) -> bool:
	var weapon_ability: bool = ItemDB.ABILITIES.has(kind) and not (kind in ["heal", "frost_nova"])
	var by_prefix: bool = kind.begins_with("sword_") or kind.begins_with("bow_") or kind.begins_with("meteor") or kind.begins_with("scepter_") \
		or kind.begins_with(FlameChannelAbilities.ID)
	return weapon_ability or by_prefix or kind == GatherAction.ID


## Começa a habilidade de arma `id` (use do módulo e, nas réplicas, play_remote).
func begin_ability(id: String, data := {}) -> void:
	end_ability()
	ability = id
	ability_t = 0.0
	ability_data = data
	attacking = false
	buffered_attack = false
	_cancel_draw()


## Encerra a habilidade em execução (fim normal, esquiva no preparo, morte, menu, troca de arma):
## sem estado, sem velocidade especial, colisão e Engine.time_scale de volta ao normal.
func end_ability() -> void:
	if ability == "":
		return
	if ability == GatherAction.ID and gather_tool != "":
		gather_tool = ""   # guarda a ferramenta: a arma equipada volta para a mão
		refresh_look.call_deferred()
	# fim próprio da habilidade (ex.: a Égide dissolve a barreira e começa a recarga), por qualquer caminho
	var on_end: Callable = ability_data.get("on_end", Callable())
	if on_end.is_valid():
		on_end.call()
	if ability == GatherAction.ID and not remote:
		var gn = ability_data.get("node")
		if gn != null and is_instance_valid(gn):
			Econ.release_node(int(gn.node_id))   # online: o nó fica livre para os outros
	for n in ability_data.get("nodes", []):
		if is_instance_valid(n):
			n.queue_free()
	if ability_data.has("mask"):
		collision_mask = ability_data.mask
	if ability_data.has("yaw0"):
		model.rotation.y = float(ability_data.yaw0)
	if ability_data.has("fov0") and camera:
		camera.fov = float(ability_data.fov0)   # a habilidade mexeu no FOV (Flecha do Vendaval)
	if not remote:
		velocity.x = 0.0
		velocity.z = 0.0
		Engine.time_scale = 1.0
		cam_back = 0.0
		cam_tilt = 0.0
	ability = ""
	ability_t = 0.0
	ability_slot = 0
	ability_data = {}


func _cast_frost_nova() -> void:
	var radius := 6.5
	_frost_fx(radius)
	Network.send_event("frost_nova", global_position)
	add_shake(0.15)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		if e.global_position.distance_to(global_position) <= radius + e.radius:
			var nova_dmg := (15.0 + Game.spell_power() * 2.0) * Game.damage_mult()
			e.take_damage(nova_dmg, global_position, false, 4.0, float(Game.talent_mods.get("nova_stun", 0.0)), 0.0, "gelo")
			Game.add_fury_from_damage(nova_dmg, e.max_hp)


func _frost_fx(radius: float) -> void:
	FXToon.frost_nova(global_position, radius)
	Sfx.play_at("frost", global_position, 0.0)


func _heal_fx() -> void:
	HolyFX.heal_burst(global_position, false, self)
	Sfx.play_at("heal", global_position, 0.0)


func _quick_potion(id: String) -> void:
	if Game.count_item(id) <= 0:
		Game.notify.emit("Sem %s!" % ItemDB.get_item(id).name, Color(1, 0.6, 0.6))
		return
	if Game.use_item(id):
		Sfx.play("heal", 0.0, -4.0)
		FX.burst(global_position + Vector3.UP, Color(1, 0.35, 0.35) if id == "health_potion" else Color(0.4, 0.5, 1), 20, 2.5, 0.08, 0.8, 2.0)


# ------------------------------------------------------------ comida
func _on_food_eaten(id: String) -> void:
	if dead or not is_inside_tree():
		return
	var it := ItemDB.get_item(id)
	var c: Color = it.get("color", ItemDB.CROPS[id].color if ItemDB.CROPS.has(id) else Color(0.6, 1, 0.5))
	Sfx.play("eat", 0.1)
	FX.burst(global_position + Vector3.UP * KnightLook.body_y(self, 1.5), c, 18, 2.2, 0.08, 0.6, -4.0)
	if it.has("buff"):
		FX.ring(global_position, Color(c.r, c.g, c.b, 0.85), 2.2, 0.5)
		FX.burst(global_position + Vector3.UP * KnightLook.body_y(self, 0.3), c, 30, 3.5, 0.1, 1.0, 3.0)
		Sfx.play("heal", 0.0, -5.0)
	match it.get("special", ""):
		"fire_nova":
			_food_fire_nova()
		"frost_nova":
			_food_frost_nova()


## Chili do Dragão: explosão de fogo que empurra e queima tudo em volta.
func _food_fire_nova() -> void:
	var radius := 7.5
	FX.ring(global_position, Color(1, 0.45, 0.1, 0.95), radius, 0.55)
	FX.burst(global_position + Vector3.UP * KnightLook.body_y(self, 0.6), Color(1, 0.5, 0.1), 70, 10.0, 0.16, 0.8, -1.0)
	FX.burst(global_position + Vector3.UP * KnightLook.body_y(self, 1.0), Color(1, 0.85, 0.3), 40, 6.0, 0.12, 0.6, 2.0)
	Sfx.play("explode", 0.05)
	add_shake(0.35)
	var dmg := (40.0 + Game.level * 6.0 + Game.spell_power() * 2.0) * Game.damage_mult()
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		if e.global_position.distance_to(global_position) <= radius + e.radius:
			e.take_damage(dmg, global_position, false, 0.0, 0.0, 0.0, "fogo")
			Game.add_fury_from_damage(dmg, e.max_hp)


## Chá de Menta Gélida: congela (lentidão forte) e fere os inimigos próximos.
func _food_frost_nova() -> void:
	var radius := 8.0
	FXToon.frost_nova(global_position, radius)
	Sfx.play("frost", 0.0)
	add_shake(0.2)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		if e.global_position.distance_to(global_position) <= radius + e.radius:
			var food_dmg := (12.0 + Game.level * 3.0) * Game.damage_mult()
			e.take_damage(food_dmg, global_position, false, 6.0, 0.0, 0.0, "gelo")
			Game.add_fury_from_damage(food_dmg, e.max_hp)


# ------------------------------------------------------------ dano e morte
## Golpe gelado (Slime de Gelo) ou veneno paralisante (Centopeia, `venom`): anda mais devagar por `secs`.
## Não acumula, só renova; muda só o aviso e a cor.
func apply_chill(secs: float, venom := false) -> void:
	if remote:
		if Network.is_server() and not dead:
			Network.server_chill_player(peer_id, secs, venom)
		return
	if dead or secs <= 0.0:
		return
	var col := Color(0.55, 0.9, 0.3) if venom else Color(0.6, 0.85, 1.0)
	if chill_t <= 0.0:
		Game.notify.emit("Veneno: mais lento por um instante." if venom
			else "Você está congelando: mais lento por um instante.", col)
	chill_t = maxf(chill_t, secs)
	FX.burst(global_position + Vector3.UP, col, 14, 2.5, 0.1, 0.6)


## Teia da Tecelã: quase parado por `secs`. Não acumula, só renova.
func apply_web(secs: float, roots := false) -> void:
	if remote:
		if Network.is_server() and not dead:
			Network.server_web_player(peer_id, secs, roots)
		return
	if dead or secs <= 0.0:
		return
	if web_t <= 0.0:
		Game.notify.emit("Preso pelas raízes! Mal consegue andar." if roots else "Preso na teia! Mal consegue andar.",
			Color(0.85, 0.5, 0.6) if roots else Color(0.9, 0.9, 0.95))
	web_t = maxf(web_t, secs)
	FX.burst(global_position + Vector3.UP * KnightLook.body_y(self, 0.8), Color(0.92, 0.92, 0.96), 18, 2.0, 0.12, 0.7)


func take_damage(amount: float, from_pos: Vector3) -> void:
	if remote:
		# no servidor, o golpe de um inimigo na réplica vira dano no PC do dono
		if Network.is_server() and not dead:
			Network.server_damage_player(peer_id, amount, from_pos)
		return
	if dead or invuln > 0 or Loading.covering:   # coberto pela tela de carregamento: imune
		return
	var final_dmg: float = max(1.0, amount * Game.damage_taken_mult())
	# Égide Cristalina erguida: o escudo absorve primeiro (integridade própria); só o que sobra chega à vida
	if ability == ShieldAbilities.ID:
		final_dmg = ShieldAbilities.absorb(self, final_dmg, from_pos)
		if final_dmg <= 0.0:
			# imunidade curta: o escudo segura cada golpe, mas vários monstros batendo juntos o desgastam
			invuln = ShieldAbilities.SHIELD_INVULN
			add_shake(0.12)
			return
	if Game.admin_mode():
		return
	if blocking and ShieldRules.in_front(global_position, facing(), from_pos):
		var res := ShieldRules.resolve(amount, Game.stamina, _block_chain, ItemDB.get_item(Game.equipment.get("offhand", "")))
		Game.stamina = res.stamina
		stamina_delay = 0.8
		_block_since = 0.0
		_block_chain += 1
		if res.broke:
			_guard_break()   # sem fôlego: o golpe entra cheio (segue abaixo)
		else:
			_take_blocked(res.damage, from_pos)
			return
	Game.hp -= final_dmg
	Game.add_fury(final_dmg / Game.max_hp() * 25.0)
	invuln = 0.45
	if ability == GatherAction.ID:
		end_ability()   # apanhou: larga a coleta (o progresso fica no nó)
	if ability != "sword_whirl":   # o Turbilhão é imune a empurrão
		var kb := global_position - from_pos
		kb.y = 0
		if kb.length() > 0.01:
			kb = kb.normalized() * 6.0
			velocity.x = kb.x
			velocity.z = kb.z
		velocity.y = 3.0
	FX.damage_number(global_position + Vector3.UP * KnightLook.body_y(self, 2.0), str(int(round(final_dmg))), Color(1, 0.3, 0.25), 56)
	FX.burst(global_position + Vector3.UP, Color(0.8, 0.05, 0.05), 12, 3.0)
	Sfx.play("hurt")
	add_shake(0.3)
	_flash()
	Game.stats_changed.emit()
	if Game.hp <= 0:
		_die()


## Camada que cada peça tinha antes do clarão de dano (brilho do encantamento, contorno da aura, neve):
## o clarão devolve a mesma camada ao acabar em vez de apagar tudo.
var _flash_prev := {}       # MeshInstance3D -> Material (ou null)
var _flash_over: Material


func _flash() -> void:
	var over := StandardMaterial3D.new()
	over.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	over.albedo_color = Color(1, 0.2, 0.2, 0.5)
	over.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_clear_flash()
	_flash_over = over
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if mi.has_meta("enchant_skip_overlay"):
			continue
		_flash_prev[mi] = mi.material_overlay
		mi.material_overlay = over
	get_tree().create_timer(0.12).timeout.connect(_clear_flash.bind(over))


## `of` = o clarão que marcou este fim (um clarão mais novo não é desfeito pelo relógio do anterior).
func _clear_flash(of: Material = null) -> void:
	if of != null and of != _flash_over:
		return
	for mi in _flash_prev:
		# só devolve se a peça ainda está com o clarão: quem trocou a camada no meio (encanto novo) fica
		if is_instance_valid(mi) and mi.material_overlay == _flash_over:
			mi.material_overlay = _flash_prev[mi]
	_flash_prev.clear()
	_flash_over = null


func _die() -> void:
	dead = true
	end_ability()
	_disarm_heal()
	_disarm_area()
	Game.hp = 0
	Game.clear_buffs()
	attacking = false
	_cancel_draw()
	Sfx.play("death", 0.0)
	KnightAnim.die(parts, create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS), look.get("holder"))
	died.emit()


func revive(pos: Vector3) -> void:
	dead = false
	Game.hp = Game.max_hp()
	Game.mp = Game.max_mp()
	Game.stamina = Game.max_stamina()
	global_position = pos
	velocity = Vector3.ZERO
	KnightAnim.revive(parts)
	invuln = 2.0
	Game.stats_changed.emit()


# ------------------------------------------------------------ coleta (F)
## F perto de um veio/árvore: confere profissão e ferramenta e começa a bater (GatherAction); senão avisa o motivo.
func start_gather(node: Node3D) -> void:
	if dead or remote or attacking or dodge_timer > 0 or ability != "" or not is_on_floor():
		return
	var plan: Dictionary = node.gather_plan()
	if plan.ok and plan.has("equip"):
		Game.equip(str(plan.equip))   # espaço vazio: equipa a melhor da mochila (o servidor confere na coleta)
	if not plan.ok:
		Game.notify.emit(plan.msg, CharRules.C_BAD)
		return
	_cancel_draw()
	aiming = false
	GatherAction.start(self, node, plan)


## Refaz o visual do equipamento agora (a ferramenta da coleta entrou ou saiu da mão).
func refresh_look() -> void:
	if not remote and is_inside_tree():
		_update_equipment_visual()


# ------------------------------------------------------------ interação
func _find_interact_target() -> void:
	var best: Node3D = null
	var best_d := 3.0
	for n in get_tree().get_nodes_in_group("interactable"):
		# alvos grandes medem a partir da borda, não do centro
		var d: float = n.interact_distance(global_position) if n.has_method("interact_distance") \
			else n.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = n
	interact_target = best


# ------------------------------------------------------------ visual
var _last_look := {}
var _slash_combo := 0       ## golpe do combo cujo corte já foi desenhado (ver _slash_fx)
var _slash_t := 0.0
var _slash_done := false
var _slash_el := ""         ## elemento do encantamento da arma: dá a cor do corte
var _swing_from := {}       ## pose do corpo quando o golpe do combo com escudo começou (KnightAnim.capture_pose)
var _recover_t := -1.0      ## s desde que o combo com escudo parou (volta à locomoção); < 0 = fora da volta


func _update_equipment_visual() -> void:
	var l: Dictionary = Game.equipment.duplicate()
	if gather_tool != "":
		l["weapon"] = gather_tool   # coletando: a picareta/machado no lugar da arma (as réplicas veem pelo look)
	l["body"] = Game.body   # o servidor troca pelo corpo gravado; aqui troca o modelo local na hora
	l["hair"] = Game.hair   # penteado: idem
	l["fx"] = _vfx_state()   # auras e encanto vão junto com o visual (os outros jogadores veem)
	if l == _last_look:
		return
	apply_look(l)
	Network.send_look(l)


func apply_look(l: Dictionary) -> void:
	# só os efeitos mudaram (buff entrou/saiu): não precisa remontar o equipamento
	var gear_same: bool = _look_gear(l) == _look_gear(_last_look) and look["holder"] != null
	_last_look = l.duplicate(true)
	if gear_same:
		_vfx_apply(l.get("fx", {}), false)
		return
	var b := KnightLook.body_key(l.get("body", ""))
	if b != model_body:
		_rebuild_body(b)
	var old_class: String = look["class"]
	look = KnightLook.apply(model, l)
	_vfx_apply(l.get("fx", {}), true)
	if old_class != look["class"]:
		attacking = false
		combo = 0
		_cancel_draw()
		KnightAnim.reset_twist(parts)


func _on_level_up(lvl: int) -> void:
	Sfx.play("level_up_fanfare", 0.0)
	LevelUpFX.play(self, lvl)


func add_shake(amount: float) -> void:
	if remote:
		if Network.is_server():
			Network.server_shake_player(peer_id, amount)
		return
	shake = max(shake, amount)


# ------------------------------------------------------------ multiplayer
const NF_FLOOR := 1
const NF_ATTACK := 2
const NF_DODGE := 4
const NF_CAST := 8
const NF_DEAD := 16
const NF_DRAW := 32
const NF_ABILITY := 64   ## habilidade de arma em execução (qual: pelo evento SwordAbilities.play_remote)
const NF_BLOCK := 128    ## escudo levantado


func _net_send(delta: float) -> void:
	_net_send_t -= delta
	if _net_send_t > 0.001:
		return
	_net_send_t = maxf(_net_send_t + 1.0 / Network.SEND_RATE, 0.0)
	var flags := (NF_FLOOR if is_on_floor() else 0) | (NF_ATTACK if attacking else 0) \
		| (NF_DODGE if dodge_timer > 0 else 0) | (NF_CAST if cast_timer > 0 else 0) | (NF_DEAD if dead else 0) | (NF_DRAW if drawing else 0) \
		| (NF_ABILITY if ability != "" else 0) | (NF_BLOCK if blocking else 0)
	Network.send_player_state(global_position, model.rotation.y, velocity, flags, combo, attack_timer)


func apply_net_state(pos: Vector3, yaw: float, vel: Vector3, flags: int, c: int, attack_t: float) -> void:
	_net_pos = pos
	_net_yaw = yaw
	velocity = vel
	_net_vel = vel
	_net_age = 0.0
	_net_floor = flags & NF_FLOOR != 0
	dodge_timer = 0.12 if flags & NF_DODGE else 0.0
	blocking = flags & NF_BLOCK != 0
	cast_timer = 0.15 if flags & NF_CAST else 0.0
	if flags & NF_DRAW:
		if not drawing:
			draw_t = 0.0
		drawing = true
	else:
		drawing = false
	if flags & NF_ATTACK:
		if not attacking or c != combo:
			Sfx.play_at(_attack_sound(), global_position, 0.1, -6.0)
		if attacking and c != combo:
			_end_swing_twist()   # golpe seguinte do combo: a trilha nova começa com o giro em -PI..PI
		if (not attacking or c != combo) and _dense_combo():
			_swing_from = KnightAnim.capture_pose(parts)
		attacking = true
		combo = clampi(c, 1, _combo_len())
		attack_timer = attack_t
	elif attacking:
		attacking = false
		_end_swing_twist()
	# a habilidade da réplica termina sozinha pelo tempo; o estado sem a flag a encerra antes (esquiva,
	# morte). Uma folga ignora estado atrasado que chegue depois do evento de início. Sem morte, o fim é o
	# macio do módulo (o da esquiva): a Chuva de Meteoros deixa os meteoros no ar caírem, mesmo se o estado
	# chegar antes do evento "meteor_rain_end"; morto, fim duro.
	if flags & NF_ABILITY == 0 and ability != "" and ability_t > 0.2:
		if flags & NF_DEAD == 0:
			_ab_module(ability).dodge_cancel(self)
		end_ability()
	var now_dead := flags & NF_DEAD != 0
	if now_dead and not dead:
		dead = true
		attacking = false
		KnightAnim.die(parts, create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS), look.get("holder"))
	elif dead and not now_dead:
		dead = false
		KnightAnim.revive(parts)


func set_display_name(n: String) -> void:
	display_name = n
	if name_tag:
		name_tag.text = n
		name_tag.visible = n != ""


func set_title(t: String) -> void:
	display_title = t
	if title_tag:
		title_tag.text = "« %s »" % t if t != "" else ""
		title_tag.visible = t != "" and display_name != ""


func _remote_process(delta: float) -> void:
	# entre pacotes (20/s) segue andando na última velocidade conhecida, em vez de parar e dar tranco
	_net_age += delta
	var target := _net_pos + Vector3(_net_vel.x, 0, _net_vel.z) * minf(_net_age, 0.2)
	if global_position.distance_to(target) > 8.0:
		global_position = target
	else:
		global_position = global_position.lerp(target, 1.0 - exp(-12.0 * delta))
	model.rotation.y = lerp_angle(model.rotation.y, _net_yaw, 1.0 - exp(-15.0 * delta))
	if dead:
		end_ability()
		return
	if ability != "":
		_ab_module(ability).tick(self, delta)
	dodge_timer = max(0.0, dodge_timer - delta)
	cast_timer = max(0.0, cast_timer - delta)
	if attacking:
		attack_timer = minf(attack_timer + delta, _swing_time(combo))
	if drawing:
		draw_t = min(draw_t + delta, BOW_FULL)
	_animate(delta)


## Emote do jogador local (teclas 1–3 na praça): toca aqui e avisa os outros pelo _player_event.
func play_emote(kind: String) -> void:
	if remote or dead or not (kind in KnightEmotes.KINDS) or not is_on_floor() or chat_typing:
		return
	_start_emote(kind)
	Network.send_event("emote", Vector3(KnightEmotes.KINDS.find(kind), 0, 0))


func _start_emote(kind: String) -> void:
	emote = kind
	_emote_t = 0.0


## Começa a pose de conjuração (jogador local e réplicas, pelo evento da magia).
func _start_cast_pose(kind: String) -> void:
	_cast_kind = kind
	_cast_t = 0.0


## Jogador (este, réplica ou o local) mais perto de `pos`, a até 4 m; null se nenhum.
func _player_near(pos: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := 4.0
	for p in get_tree().get_nodes_in_group("players"):
		var d: float = p.global_position.distance_to(pos)
		if d < best_d:
			best = p
			best_d = d
	return best


## Efeitos das ações de outro jogador (só visuais: o dano já foi enviado pelo dono).
func play_remote_event(kind: String, a: Vector3, b: Vector3) -> void:
	if _is_ability_kind(kind):
		_ab_module(kind).play_remote(self, kind, a, b)
		return
	match kind:
		"staff_fireball":
			MageStaffAttack.play_remote(self, a, b)
		"fireball":
			_start_cast_pose(kind)
			_cast_t = KnightMoves.CAST_RELEASE * KnightMoves.CAST_TIME   # o evento chega no disparo
			var fb := FIREBALL.new()
			fb.direction = b
			fb.visual_only = true
			get_tree().current_scene.add_child(fb)
			fb.global_position = a
			Sfx.play_at("fire", a, 0.08, -4.0)
		"frost_nova":
			_start_cast_pose(kind)
			_frost_fx(6.5)
		"heal":
			_start_cast_pose(kind)
			var tgt := _player_near(b) if b != Vector3.ZERO else null
			if tgt:
				# Cura num aliado: a esfera voa até ele (se for eu, o meu receive_heal já mostra a cura)
				HolyFX.heal_beam(spell_origin(), tgt, tgt.remote)
				Sfx.play_at("heal", a, 0.05, -8.0)
			else:
				_heal_fx()
		"bolt", "arrow", "light_orb":
			var p := PROJECTILE.new()
			p.kind = kind
			p.direction = b.normalized()
			p.visual_only = true
			if kind == "arrow":   # arco mítico: a réplica mostra fenda, chuva e espinheiro (o dano é do dono)
				var rfx := str(ItemDB.get_item(_last_look.get("weapon", "")).get("fx", ""))
				if BowMythicRules.is_mythic_fx(rfx):
					p.fx = rfx
					p.full = BowMythicRules.decode_full(b)
			p.color = LIGHT_ORB_COLOR if kind == "light_orb" else ItemDB.get_item(_last_look.get("weapon", "")).get("color", Color(0.6, 0.8, 1.0))
			p.element = Sfx.staff_element(_weapon_id())
			if kind != "arrow":
				Sfx.play_at(p.element + "_cast", a, 0.12, -8.0)
			p.speed = 34.0 if kind == "arrow" else 26.0
			p.life = 1.6 if kind == "arrow" else (LIGHT_ORB_RANGE / 26.0 if kind == "light_orb" else 1.2)
			get_tree().current_scene.add_child(p)
			p.global_position = a
		"zap":
			AUTO_WEAPONS.bolt_fx(get_tree().current_scene, a)
			Sfx.play_at("zap", a, 0.15, -8.0)
		"combo":
			AUTO_WEAPONS.combo_fx_index(get_tree().current_scene, int(b.x), a)
		"emote":
			# índice em KnightEmotes.KINDS; -1 = o dono cancelou (andou, abriu o chat...); outros fora da lista: ignora
			var i := int(a.x)
			if i == -1:
				emote = ""
			elif i >= 0 and i < KnightEmotes.KINDS.size():
				_start_emote(KnightEmotes.KINDS[i])
		"horde_gear":
			# armas automáticas do Desafio da Horda girando em volta do outro jogador
			var aw: Node = get_node_or_null("HordeGear")
			if a == Vector3.ZERO and b == Vector3.ZERO:
				if aw:
					aw.queue_free()
				return
			if aw == null:
				aw = AUTO_WEAPONS.new()
				aw.name = "HordeGear"
				aw.visual_only = true
				add_child(aw)
			aw.apply_gear(a, b)


func _update_camera(delta: float) -> void:
	shake = max(0.0, shake - delta * 1.2)
	camera.h_offset = randf_range(-1, 1) * shake * 0.4
	camera.v_offset = randf_range(-1, 1) * shake * 0.4


func _animate(delta: float) -> void:
	var hvel := Vector3(velocity.x, 0, velocity.z)
	var hspeed := hvel.length()
	var on_floor := _net_floor if remote else is_on_floor()
	idle_t += delta
	var k := 1.0 - exp(-14.0 * delta)

	# quanto anda (0..1) e quanto corre (0..1), suavizados: as transições parado/andar/correr misturam
	# as poses em vez de trocar de uma vez (parar é um pouco mais lento que arrancar)
	var move_t := clampf(hspeed / WALK_SPEED, 0.0, 1.0) if on_floor else 0.0
	# a pose de corrida mede a passada sem o bônus de velocidade (agilidade, botas, buffs): com bônus, andar
	# passava de WALK_SPEED e o corpo seguia na pose de corrida mesmo sem o Shift
	var gait := hspeed if remote else hspeed / maxf(Game.speed_multiplier(), 0.01)
	var run_t := clampf((gait - WALK_SPEED) / (SPRINT_SPEED - WALK_SPEED), 0.0, 1.0)
	_amp = lerpf(_amp, move_t, 1.0 - exp(-(10.0 if move_t > _amp else 6.0) * delta))
	_run = lerpf(_run, run_t, 1.0 - exp(-6.0 * delta))
	_air = lerpf(_air, 0.0 if on_floor else 1.0, 1.0 - exp(-12.0 * delta))
	# a fase avança pela distância percorrida: meia volta = uma passada, então o pé não desliza
	anim_t += delta * KnightAnim.cadence(parts, hspeed, _amp, _run)

	# inclinação extra para a frente ao arrancar (e para trás ao frear); a da velocidade vem de
	# KnightAnim.locomotion_pose. Para o lado nas curvas.
	var fwd := Vector3(sin(model.rotation.y), 0, cos(model.rotation.y))
	var accel := (hvel - _prev_hvel) / maxf(delta, 0.001)
	_prev_hvel = hvel
	if remote:
		accel = Vector3.ZERO   # a velocidade da réplica muda aos saltos (pacotes): só a local dá aceleração confiável
	var lean_t := 0.0
	if on_floor:
		lean_t = clampf(accel.dot(fwd) * KnightAnim.LEAN_ACCEL, KnightAnim.LEAN_MIN, KnightAnim.LEAN_ACCEL_MAX)
	_lean = lerpf(_lean, lean_t, 1.0 - exp(-8.0 * delta))
	var yaw_rate := wrapf(model.rotation.y - _prev_yaw, -PI, PI) / maxf(delta, 0.001)
	_prev_yaw = model.rotation.y
	# sem inclinação de curva na esquiva nem nas habilidades (o Turbilhão gira o modelo de propósito)
	var bank_t := clampf(-yaw_rate * hspeed * 0.012, -0.18, 0.18) if on_floor and dodge_timer <= 0 and ability == "" else 0.0
	_bank = lerpf(_bank, bank_t, 1.0 - exp(-8.0 * delta))
	model.rotation.z = _bank

	# aterrissagem: agacha conforme a velocidade da queda, depois volta
	if not on_floor:
		_air_vy = velocity.y
	elif not _was_floor and _air_vy < -3.0:
		_land = clampf(-_air_vy / 14.0, 0.3, 1.0)
	_was_floor = on_floor
	_land = move_toward(_land, 0.0, delta * 3.5)
	var land := _land * _land * (3.0 - 2.0 * _land)

	# pose: parado -> andar/correr -> ar, misturados pelos pesos suavizados
	var p := KnightAnim.blend(KnightAnim.idle_pose(idle_t), KnightAnim.locomotion_pose(parts, anim_t, _amp, _run), _amp)
	KnightAnim.weapon_carry(p, look["class"], _amp, _run)   # cajado firme, arco pendurado
	var great := _great() and not dead
	if great:
		KnightAnim.great_carry(p, _amp, _run)   # montante: guarda parado, no ombro andando
	if _air > 0.001:
		p = KnightAnim.blend(p, KnightAnim.air_pose(clampf(velocity.y / JUMP_VELOCITY, -1.0, 1.0)), _air)
	KnightAnim.add_landing(p, land)
	p.body_x += _lean * (1.0 - _air)
	# a cabeça compensa parte da inclinação e continua olhando para a frente
	p.head_x -= (_lean + land * KnightAnim.LAND_BODY_X) * 0.5
	if dodge_timer > 0:
		_dodge_age += delta
		KnightAnim.dodge_pose(p, _dodge_age / DODGE_TIME)
	else:
		_dodge_age = 0.0
	# andando, o ciclo segue a pose sem o atraso da suavização (some na esquiva e volta aos poucos)
	_cycle_w = lerpf(_cycle_w, 0.0 if dodge_timer > 0 or ability != "" else _amp * (1.0 - _air), 1.0 - exp(-6.0 * delta))
	KnightAnim.follow_cycle(p, _cycle_w)

	# emote: andar, pular, abrir o chat (ou cair, atacar, esquivar) cancela; senão a pose dele manda
	if emote != "":
		_emote_t += delta
		var d := KnightEmotes.duration(emote)
		var moved := hspeed > 1.0 or not on_floor or dead or attacking or dodge_timer > 0 or chat_typing
		if moved or (d > 0.0 and _emote_t >= d):
			emote = ""
			if moved and not remote:
				Network.send_event("emote", Vector3(-1, 0, 0))   # as réplicas param junto (o fim natural cada uma vê sozinha)
		else:
			p = KnightEmotes.pose(emote, _emote_t)

	# golpes, arco e magias: trilhas de KnightMoves por cima da locomoção
	var cls: String = look["class"]
	_cast_t += delta
	if attacking or _recover_t >= KnightAnim.SHIELD_RECOVER:
		_recover_t = -1.0   # golpe em curso (a réplica emendou outro) ou a volta acabou
	elif _recover_t >= 0.0:
		_recover_t += delta
	var arrow: Node3D = look.get("arrow")
	if arrow and is_instance_valid(arrow):
		arrow.visible = drawing or ((ability == "bow_triple" and ability_t < BowAbilities.TRIPLE_DRAW) or (ability == "bow_frost" and ability_t < BowAbilities.FROST_DRAW)
			or (ability == "bow_gale" and not ability_data.get("fired", false)))
	if cls == "bow" and (drawing or attacking or ability.begins_with("bow_")):
		_update_aim_pitch()
	if great and (ability != "" or dodge_timer > 0 or emote != ""):
		p.erase("tool")         # habilidades, esquiva e emotes têm braços próprios: a esquerda só acompanha o cabo
		p["two_hand"] = 1.0 if ability != "" else 0.0
	if ability != "":
		_ab_module(ability).pose(self, p)
	elif cls == "bow" and drawing:
		KnightAnim.bow_draw_pose(p, bow_charge(), _amp)
	elif cls == "bow" and attacking:
		KnightAnim.bow_release_pose(p, attack_timer / BOW_RECOVER, _amp, aiming)
	elif attacking and cls == "staff" and MageStaffAttack.active(self):
		MageStaffAttack.pose(self, p, _amp)
	elif attacking and cls == "staff":
		KnightAnim.staff_pose(p, combo, attack_timer / _swing_time(combo), _amp)
	elif attacking and cls == "sword" and _unarmed():
		KnightAnim.punch_pose(p, combo, attack_timer / _swing_time(combo), _amp)
	elif attacking and cls == "sword" and _shield_combo():
		KnightAnim.shield_combo_pose(p, combo, attack_timer / _swing_time(combo), _amp, _swing_from)
		_slash_fx()
	elif _recover_t >= 0.0 and dodge_timer <= 0.0 and not dead and cls == "sword" and _shield_combo():
		KnightAnim.shield_recover_pose(p, _swing_from, _recover_t / KnightAnim.SHIELD_RECOVER)
	elif attacking and cls == "sword" and great:
		KnightAnim.great_pose(p, combo, attack_timer / _swing_time(combo), _amp, _swing_from)
		_slash_fx()
	elif _recover_t >= 0.0 and dodge_timer <= 0.0 and not dead and great:
		KnightAnim.great_recover_pose(p, _swing_from, _recover_t / KnightAnim.SHIELD_RECOVER)
	elif attacking and cls == "sword":
		KnightAnim.sword_pose(p, combo, attack_timer / _swing_time(combo), _amp)
		_slash_fx()
	elif _cast_t < KnightMoves.CAST_TIME:
		KnightAnim.cast_pose(p, _cast_kind, _cast_t / KnightMoves.CAST_TIME, _amp, cls == "staff")
	# escudo: sobe rápido (~0,12 s) e desce um pouco mais devagar; o golpe defendido dá um tranco no braço
	var up := blocking and ability == "" and not attacking and dodge_timer <= 0 and not dead
	_block_w = move_toward(_block_w, 1.0 if up else 0.0, delta * (8.0 if up else 5.0))
	if _block_w > 0.001:
		var hv_m := model.global_basis.inverse() * Vector3(velocity.x, 0.0, velocity.z)
		var guard_mv := Vector2(hv_m.x, hv_m.z) / (WALK_SPEED * ShieldRules.MOVE_SPEED)
		KnightAnim.shield_block_pose(p, _block_w, maxf(0.0, 1.0 - _block_since / 0.25), parts, anim_t, guard_mv)
	if ability != "" or drawing or attacking or _cast_t < KnightMoves.CAST_TIME:
		KnightAnim.hips_follow(p)
	KnightAnim.apply(parts, p, k)

	KnightAnim.hold_weapon_upright(look, parts)
	MageStaffAttack.tick_orb(self)   # Bola de Fogo na gema durante a carga (depois da pose: a gema já está no lugar)
	KnightAnim.sway_ponytail(parts, delta)
	if cls == "bow":
		KnightAnim.bow_string(look, parts)   # corda nos dedos, arco envergando, flecha na linha

	if on_floor and hspeed > 1.0:
		_footstep -= delta * hspeed
		if _footstep <= 0:
			_footstep = 2.2


# ------------------------------------------------------------ efeitos visuais
## Auras (buffs de comida e habilidades) e brilho de encantamento da arma.
## O estado viaja dentro do visual do jogador (`look["fx"]`), então as réplicas dos outros
## jogadores mostram os mesmos efeitos. Formato: {"auras": [estilos], "en": elemento, "lv": nível}.
## As auras são declaradas pelo cliente (só cosméticas). O encanto (en/lv) vem do personagem:
## aqui, do espelho no Game; para os outros, o servidor preenche com o que ele gravou.
## Linha de comando (para capturas): `--buffs=spicy_soup,mint_tea`, `--auras=escudo,vento`, `--vfxwalk`, `--aimdemo`.
var vfx_aura: BuffAura
var vfx_ability_auras := {}    # estilo -> true (auras ligadas por habilidades)
var _vfx_sent := {}


func _vfx_setup() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--buffs="):
			for id in a.substr(8).split(","):
				Game.buffs[id] = 600.0
		elif a.begins_with("--auras="):
			for st in a.substr(8).split(","):
				vfx_ability_auras[st] = true
		elif a == "--vfxwalk":
			_vfx_walk_demo()
		elif a.begins_with("--rundemo"):   # capturas da corrida: `--rundemo` anda reto, `--rundemo=sprint` corre
			_run_demo(a.ends_with("=sprint"))
		elif a == "--aimdemo":   # capturas da mira do arco: segura o botão direito
			Input.action_press.call_deferred("aim")


## `--rundemo[=sprint]`: anda (ou corre) em linha reta sozinho e imprime a inclinação do tronco no mundo, para
## conferir a marcha no jogo de verdade. Com `--runshots=<arquivo.png>` salva uma tira de 8 quadros de uma
## passada, recortados em volta do personagem na câmera do jogo, e fecha. Com `--runside`, de lado.
func _run_demo(sprint: bool) -> void:
	await get_tree().create_timer(1.0).timeout
	# `--runside`: corre para a direita da câmera (a tira mostra o personagem de lado)
	Input.action_press("move_right" if "--runside" in OS.get_cmdline_user_args() else "move_forward")
	if sprint:
		Input.action_press("sprint")
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--runshots="):
			out = a.substr(11)
	await get_tree().create_timer(0.9).timeout
	var chest: Node3D = parts.get("Chest")
	print("rundemo: vel %.1f m/s | quadril %.1f° | peito %.1f° | cabeça %.1f°" % [
		Vector2(velocity.x, velocity.z).length(),
		rad_to_deg(parts.Body.global_basis.get_euler().x - model.global_basis.get_euler().x),
		rad_to_deg(chest.global_basis.get_euler().x) if chest else 0.0,
		rad_to_deg(parts.Head.global_basis.get_euler().x)])
	if out == "":
		return
	const N := 8
	const W := 300
	const H := 380
	var strip := Image.create(W * N, H, false, Image.FORMAT_RGBA8)
	var last := anim_t
	var done := 0.0     # fase andada desde o começo da captura (anim_t pode dar a volta)
	for i in N:
		while done < TAU * i / N:   # um quadro a cada oitavo da passada
			await get_tree().process_frame
			done += absf(wrapf(anim_t - last, -PI, PI))
			last = anim_t
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		var c := get_viewport().get_camera_3d().unproject_position(global_position + Vector3.UP * 0.9)
		c *= Vector2(img.get_size()) / get_viewport().get_visible_rect().size   # a imagem pode ter outra escala
		var rect := Rect2i(int(c.x) - W / 2, int(c.y) - H / 2, W, H).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		strip.blit_rect(img, rect, Vector2i(W * i, 0))
	strip.save_png(out)
	print("RUNSHOTS ", out)
	get_tree().quit()


## `--vfxwalk`: anda em zigue-zague, pula e ataca sozinho (para gravar os efeitos em movimento).
func _vfx_walk_demo() -> void:
	await get_tree().create_timer(1.0).timeout
	var t := 0
	while is_inside_tree():
		Input.action_press("move_forward")
		if t % 6 < 3:
			Input.action_press("move_left")
			Input.action_release("move_right")
		else:
			Input.action_press("move_right")
			Input.action_release("move_left")
		if t % 2 == 1:
			Input.action_press("attack")
			await get_tree().create_timer(0.1).timeout
			Input.action_release("attack")
		if t % 5 == 4:
			Input.action_press("jump")
			await get_tree().create_timer(0.1).timeout
			Input.action_release("jump")
		t += 1
		await get_tree().create_timer(0.5).timeout


## Liga ou desliga uma aura por habilidade (estilos em BuffAura.STYLES). Soma com as de comida.
func set_ability_aura(style: String, on: bool) -> void:
	if on:
		vfx_ability_auras[style] = true
	else:
		vfx_ability_auras.erase(style)
	_update_equipment_visual()


## Efeitos que este jogador deveria estar mostrando agora.
func _vfx_state() -> Dictionary:
	var want := vfx_ability_auras.duplicate()
	for id in Game.buffs:
		want[BuffAura.style_for(id)] = true
	var auras: Array = []
	for st in BuffAura.STYLES:     # ordem fixa: o mesmo conjunto dá sempre o mesmo dicionário
		if want.has(st):
			auras.append(st)
	var e := Game.weapon_enchant() if gather_tool == "" else {"el": "", "lv": 0}   # ferramenta não brilha
	return {"auras": auras, "en": e.el, "lv": e.lv}


## Buff entrou ou saiu: reenvia o visual (local e pela rede).
func _vfx_sync() -> void:
	var st := _vfx_state()
	if st != _vfx_sent:
		_vfx_sent = st
		_update_equipment_visual()


## Equipamento sem os efeitos (para saber se as peças precisam ser remontadas).
func _look_gear(l: Dictionary) -> Dictionary:
	var g := l.duplicate()
	g.erase("fx")
	return g


## Mostra os efeitos `fx` neste personagem (local ou réplica). `rebuilt` = as peças do modelo
## acabaram de ser refeitas, então o contorno da aura precisa ser recolocado nelas.
## Corte desenhado do golpe de espada em curso, uma vez por golpe. Chamado de _animate, por onde passam
## o jogador local e as réplicas (que recebem combo e attack_timer pelo estado de rede).
func _slash_fx() -> void:
	var c := clampi(combo, 1, _combo_len())
	if c != _slash_combo or attack_timer < _slash_t - 0.1:   # outro golpe do combo, ou o relógio voltou
		_slash_done = false
	_slash_combo = c
	_slash_t = attack_timer
	var shield := _shield_combo()
	var great := _great()
	var at: float = (KnightMovesShield.SLASH[c - 1].at if shield else (KnightMovesGreat.SLASH[c - 1].at if great else FXToon.SWORD_COMBO[c - 1].at))
	if _slash_done or attack_timer / _swing_time(c) < at:
		return
	_slash_done = true
	if shield:
		FXToon.shield_combo_slash(self, model.rotation.y, c, _swing_time(c), slash_color())
	elif great:
		FXToon.great_slash(self, model.rotation.y, c, _swing_time(c), slash_color())
	else:
		FXToon.sword_slash(self, model.rotation.y, c, slash_color())


## Cor dos efeitos desenhados dos golpes: a do elemento do encantamento da arma ou, sem ele, a da arma.
func slash_color() -> Color:
	if EnchantFX.ELEMENTS.has(_slash_el):
		return EnchantFX.ELEMENTS[_slash_el].color
	return ItemDB.get_item(_weapon_id()).get("color", Color(0.75, 0.88, 1.0))


func _vfx_apply(fx: Dictionary, rebuilt: bool) -> void:
	if Network.is_server():
		return   # servidor dedicado: ninguém vê
	_slash_el = str(fx.get("en", "")) if int(fx.get("lv", 0)) > 0 else ""
	var auras: Array = fx.get("auras", [])
	if vfx_aura == null and not auras.is_empty():
		vfx_aura = BuffAura.new()
		model.add_child(vfx_aura)
	if vfx_aura:
		vfx_aura.set_styles(auras)
		if rebuilt:
			vfx_aura.refresh()
	EnchantFX.apply(look, str(fx.get("en", "")), int(fx.get("lv", 0)))
