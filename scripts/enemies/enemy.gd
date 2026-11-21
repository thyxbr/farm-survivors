class_name Enemy
extends CharacterBody3D
## Inimigo genérico (slime, goblin, rei goblin) com IA simples de estados.

signal died(enemy: Enemy)
signal health_changed(enemy: Enemy)

const PICKUP := preload("res://scripts/world/pickup.gd")
const ENEMY_ARROW := preload("res://scripts/enemies/enemy_arrow.gd")
const PROVOKE_TIME := 4.0   # ver `provoked`
## Até onde (m) o monstro olha à frente antes de dar um passo: se o passo cai na zona da guarda, ele para.
const WARD_LOOKAHEAD := 1.5
## Tipos de inimigo: vêm de data/balance/enemies.json (autoload Balance). "ai" muda o comportamento,
## "tint" recolore o modelo, "bld" multiplica o dano em construções, "gear" lista as peças opcionais do
## modelo que a variante usa (EnemyGear), "shot": "bolt" troca a flecha por um projétil mágico e "chill"
## são os segundos de lentidão que o golpe corpo a corpo deixa no jogador.
static var TYPES: Dictionary = {}

@export var kind := "slime"
## Desafio da Horda: persegue sempre o jogador, não volta para casa e não dá XP/loot do RPG.
var horde := false
var hp_mult := 1.0
var dmg_mult := 1.0
var speed_mult := 1.0
## Versão de elite (maior, dourada, mais vida; o servidor manda junto no spawn). Na Horda, com os números da
## horda; no mundo (com nível), os do "elite" de data/balance/progression.json.
var elite := false
## Nível do monstro (0 = sem nível: Horda e cidade, com os números de hoje). Com nível, vida, dano, XP e ouro
## seguem as curvas de ProgressionRules, e o modelo ganha a tinta e a escala da camada.
var level := 0
## Região com nome onde o monstro nasceu ("" = fora de região; Regions.area_at). Missões com "region" só contam
## abates de monstros daqui. O servidor e o solo põem a do ponto de nascimento; a réplica recebe no spawn.
var area := ""
## Dormindo: monstro do mundo parado (idle/wander, no chão) sem jogador a menos de `sleep_radius` não roda IA nem
## física (com ~300 monstros nos mapas é isso que segura o servidor). Confere de novo a cada SLEEP_CHECK s;
## levar dano acorda na hora. 0 no raio = nunca dorme. Raio em data/balance/rules.json, "enemy_sleep_radius".
var asleep := false
var sleep_radius := 0.0
## Longe da câmera (ver _update_far): a réplica fica parada além de FAR_STILL e todo monstro em repouso some
## além de FAR_HIDE; a margem evita ficar trocando na fronteira.
const FAR_STILL := 60.0
const FAR_HIDE := 110.0
const FAR_MARGIN := 10.0
var still := false
var _far_t := 0.0
var _sleep_t := 0.0
const SLEEP_CHECK := 0.5
## Tamanho do modelo além de data.scale (elite e camada de nível).
var size_mult := 1.0
## Goblin Dourado no mundo: foge até esta distância (m) do ponto onde nasceu e volta rodeando.
const FLEE_LEASH := 18.0
## Goblin Dourado que fugiu: some sem contar como abate.
var escaped := false
var born_t := 0.0

var data: Dictionary
var display_name := ""
var max_hp := 1.0
var hp := 1.0
var radius := 0.5
var dead := false
var is_boss := false
## Chefe de dungeon (EnemySpawn.chief): conta como chefe mesmo sendo de um tipo comum (a Slime Rainha).
var chief := false
var state := "idle"
var state_timer := 0.0
var attack_cd := 0.0
var attack_timer := 0.0
var attack_kind := "swing"
var attack_count := 0
## Kobold: onde a dinamite do ataque "throw" cai (o servidor escolhe; a réplica recebe o deslocamento nos bits altos de flags).
var throw_point := Vector3.ZERO
var _dyn: MeshInstance3D = null
var hit_done := false
var slow_timer := 0.0
## Marca tóxica (arma encantada com Veneno): enquanto venom_timer > 0, todo dano recebido vale
## (1 + venom_amp). Estado do dono do inimigo (servidor ou solo); as réplicas pedem por apply_venom.
var venom_amp := 0.0
var venom_timer := 0.0
var stagger := 0.0
## Segundos em que o inimigo segue perseguindo depois de levar dano, mesmo com o jogador longe.
## Sem isso, um acerto de longe (ou, no servidor, antes de chegar a posição nova do jogador)
## fazia o inimigo desistir na hora, voltar para casa e curar a vida toda, apagando o dano.
var provoked := 0.0
## Segundos que o monstro está dentro da zona da guarda (VillageWard); passou de DOOM, a guarda abate.
var ward_t := 0.0
var home := Vector3.ZERO
var wander_target := Vector3.ZERO
var enraged := false
var summoned := false
var model: Node3D
var parts := {}
var meshes: Array[MeshInstance3D] = []
var anim_t := 0.0
var bar_root: Node3D
var bar_fg: MeshInstance3D
## Nome sobre a cabeça e, em cima dele, o ícone de alvo de missão (só no cliente/solo, fora da Horda).
var name_tag: Label3D
var quest_icon: Sprite3D
static var _quest_tex: ImageTexture
const NAME_RANGE := 30.0     # metros: mais longe que isso o nome some (menos poluição no campo aberto)
## Cor da placa (nível do monstro − nível do jogador): até PLATE_LOW cinza, de PLATE_HIGH amarelo, de
## ProgressionRules.danger_diff vermelho (e o monstro ganha dano e resistência contra esse jogador, ver vs());
## no meio, branco.
const PLATE_LOW := -5
const PLATE_HIGH := 3
const PLATE_DANGER_COLOR := Color(1.0, 0.35, 0.3)
## Camadas de piscar (acerto) e de lentidão: iguais para todos os inimigos, ninguém altera depois de criar.
static var _overlay_hit: StandardMaterial3D
static var _overlay_slow: StandardMaterial3D
static var _bar_meshes: Array[QuadMesh] = []      # fundo e frente da barra de vida, com o material
var _overlay_base: Material = null
var _overlay_now: Material = null     # o que está nas malhas agora (ver _set_overlay)
var _flash_t := 0.0

## Multiplayer: id comum entre servidor e clientes.
var net_id := 0
## Cliente: réplica de um inimigo do servidor (sem IA; segue os snapshots).
var puppet := false
## Servidor: peers que acertaram este inimigo (todos ganham XP e loot ao matar).
var contributors := {}
var last_hitter := 0
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
## Recarga do ataque especial (segundos), à parte da do golpe: teia da Tecelã, língua do Bocarrão.
var web_cd := 0.0
## Toupeira-Broca (ai "burrow"): segundos debaixo da terra, segundos na superfície desde que saiu, o monte de
## terra que anda por cima dela e a camada de colisão normal (zerada enquanto está enterrada).
var dig_t := 0.0
var surface_t := 0.0
var _dirt: MeshInstance3D = null
var _layer := 4
var _dust_t := 0.0
## Mãe-Verme (ai "worm"): ataques feitos desde que saiu do chão e o relógio da conferência do fosso.
var worm_hits := 0
var _leash_t := 0.0
## Mãe-Verme, habilidades de chefe (BossRules): especiais já feitos, mergulhos de fúria pendentes, semente do
## Desmoronamento (vai no snapshot), pontos das pedras e das Poças de Ácido do golpe atual, a entrada já mostrada
## a este jogador, o visual da fúria (cristais vermelhos) e a aura de partículas.
var _specials := 0
var _fury_dives := 0
var boss_seed := 0
var _rock_pts: Array = []
var _acid_pts: Array = []
var _intro_shown := false
var _fury_look := false
var _fury_saved := {}
var _boss_aura: CPUParticles3D = null
## Bocarrão: até onde a língua vai no ataque em curso (só para o desenho).
var tongue_len := 0.0
const SPIDER_PARTS := ["Abdomen", "Leg0L", "Leg1L", "Leg2L", "Leg3L", "Leg0R", "Leg1R", "Leg2R", "Leg3R"]
## Goblin e esqueleto: "bow", "staff" ou "" (EnemyPose) e as medidas dos braços para o IK.
var weapon := ""
var _rig := {}
static var _nock_mesh: Mesh


func _ready() -> void:
	data = TYPES[kind]
	if not horde and not puppet:
		sleep_radius = float(Balance.tables.get_table("rules").get("enemy_sleep_radius", 0.0))
		_sleep_t = randf() * SLEEP_CHECK   # espalha as conferências pelos quadros
	_far_t = randf() * SLEEP_CHECK
	display_name = data.name
	if elite:
		display_name += " de Elite"
	if level > 0:
		display_name = "Nv %d %s" % [level, display_name]
	var prog: Dictionary = Balance.tables.get_table("progression")
	var m := ProgressionRules.enemy_mults(Balance.tables, kind, level)
	hp_mult *= m.hp
	dmg_mult *= m.dmg
	var shade := Color.WHITE
	size_mult = 1.3 if elite else 1.0
	if level > 0:
		var tier: Dictionary = prog.get("tiers", [{}])[ProgressionRules.tier_of(Balance.tables, level) - 1]
		shade = tier.get("tint", Color.WHITE)
		size_mult = float(tier.get("scale", 1.0))
		var rank := ProgressionRules.rank_mults(Balance.tables, kind, chief)   # campeões e chefes
		hp_mult *= rank.hp
		dmg_mult *= rank.dmg
		if elite and not horde:   # elite do mundo (a da Horda já vem com os números dela)
			hp_mult *= float(prog.get("elite", {}).get("hp", 1.0))
			dmg_mult *= float(prog.get("elite", {}).get("dmg", 1.0))
			size_mult *= float(prog.get("elite", {}).get("scale", 1.0))
	max_hp = data.hp * hp_mult
	hp = max_hp
	radius = data.radius * (1.2 if elite else 1.0)
	is_boss = data.get("boss", false) or chief
	add_to_group("enemies")
	collision_layer = _layer
	collision_mask = 1 | 2 | 4 | MapRiver.WALL_LAYER
	if data.get("ai", "") == "worm":   # Mãe-Verme: só o terreno a segura; ninguém a empurra (os outros batem nela)
		collision_mask = 1
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = max(data.height, radius * 2.0)
	col.shape = cap
	col.position.y = cap.height / 2.0
	add_child(col)

	model = EnemyModel.instance(kind, data, shade)  # tintura, toon e peças juntadas: montado uma vez por tipo
	model.scale = Vector3.ONE * data.scale * size_mult
	add_child(model)
	if elite:
		_make_elite_glow()
	for n in ["LegL", "LegR", "ArmL", "ArmR", "Body", "Head", "Tail", "Jaw", "Drill"]:   # Tail e Jaw: raptor; Drill: toupeira
		parts[n] = model.find_child(n, true, false)
	if data.model == "worm":   # Mãe-Verme: o segundo osso do corpo
		parts["Neck"] = model.find_child("Neck", true, false)
	if data.model == "mole":   # Toupeira: o segundo osso de cada membro (cotovelo e joelho)
		for n in ["ElbowL", "ElbowR", "KneeL", "KneeR"]:
			parts[n] = model.find_child(n, true, false)
	if data.model in ["spider", "centipede"]:   # Tecelã e Centopeia: abdômen e as pernas (Leg0L..Leg3R)
		for n in SPIDER_PARTS:
			parts[n] = model.find_child(n, true, false)
	for n in ["Tongue", "VineL", "VineR", "WingL", "WingR"]:   # Bocarrão, Flor-faminta e Asa-couro
		parts[n] = model.find_child(n, true, false)
	if data.model in ["goblin", "skeleton"]:   # cotovelos, arco e cajado (EnemyPose)
		for n in ["ElbowL", "ElbowR"]:
			parts[n] = model.find_child(n, true, false)
		parts["Bow"] = model.find_child("Opt_Bow", true, false)
		parts["Staff"] = model.find_child("Opt_Staff", true, false)
		weapon = EnemyPose.weapon_of(data.get("gear", []))
		_rig = EnemyPose.rig(parts)
		if weapon == "bow" and parts.Body and DisplayServer.get_name() != "headless":
			parts["Nock"] = _make_nock(parts.Body)
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_in_group(ToonLook.OUTLINE_GROUP):      # a casca de contorno não pisca nem tinge
			meshes.append(mi)
	if is_boss or data.get("elite", false):
		var aura := OmniLight3D.new()
		aura.light_color = Color(1, 0.3, 0.1) if is_boss else data.color
		aura.light_energy = 1.5 if is_boss else 1.1
		aura.omni_range = 6.0 if is_boss else 4.0
		aura.position.y = 2.0 if is_boss else 1.4
		add_child(aura)
	if data.get("ai", "") == "bomber":
		var glow := OmniLight3D.new()
		glow.light_color = data.color
		glow.light_energy = 0.8
		glow.omni_range = 2.5
		glow.position.y = 0.6
		add_child(glow)

	if _overlay_hit == null:
		_overlay_hit = _flat_mat(Color(1, 1, 1, 0.7))
		_overlay_slow = _flat_mat(Color(0.4, 0.75, 1.0, 0.35))

	if not is_boss:
		_make_health_bar()
		if data.get("elite", false):
			bar_root.visible = true
	if not horde and not Network.is_server():
		_make_name_tag()
	home = global_position
	wander_target = home
	state_timer = randf_range(1.0, 3.0)
	model.rotation.y = randf() * TAU
	if horde:
		state = "chase"
	if data.get("ai", "") == "worm":
		_make_boss_aura()
		if not puppet:
			_set_state("burrow")   # a Mãe-Verme começa enterrada: a entrada da luta é ela saindo do chão
	if Network.is_server():
		Network.server_register_enemy(self)


## Elite: anel dourado no chão e brilho, para ser lido de longe no meio da horda.
func _make_elite_glow() -> void:
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = radius + 0.25
	tor.outer_radius = radius + 0.45
	tor.rings = 24
	tor.ring_segments = 6
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.8, 0.25, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(1.0, 0.7, 0.2)
	m.emission_energy_multiplier = 2.5
	tor.material = m
	ring.mesh = tor
	ring.scale = Vector3(1, 0.15, 1)
	ring.position.y = 0.08
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.3)
	light.light_energy = 1.2
	light.omni_range = 3.5
	light.position.y = 1.0
	add_child(light)


## Flecha encaixada no arco enquanto o arqueiro puxa a corda (EnemyPose posiciona; some ao soltar).
## Haste ao longo do eixo y, com a ponta em +y.
func _make_nock(body: Node3D) -> MeshInstance3D:
	if _nock_mesh == null:
		var shaft := CylinderMesh.new()
		shaft.top_radius = 0.011
		shaft.bottom_radius = 0.011
		shaft.height = EnemyPose.ARROW_LEN
		shaft.radial_segments = 5
		shaft.rings = 1
		var tip := CylinderMesh.new()
		tip.top_radius = 0.0
		tip.bottom_radius = 0.026
		tip.height = 0.07
		tip.radial_segments = 5
		tip.rings = 1
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color(0.45, 0.3, 0.15)
		var iron := StandardMaterial3D.new()
		iron.albedo_color = Color(0.72, 0.72, 0.78)
		var m := ArrayMesh.new()
		var st := SurfaceTool.new()
		st.append_from(shaft, 0, Transform3D.IDENTITY)
		st.commit(m)
		m.surface_set_material(0, wood)
		st = SurfaceTool.new()
		st.append_from(tip, 0, Transform3D(Basis(), Vector3(0, EnemyPose.ARROW_LEN * 0.5, 0)))
		st.commit(m)
		m.surface_set_material(1, iron)
		_nock_mesh = m
	var mi := MeshInstance3D.new()
	mi.name = "Nock"
	mi.mesh = _nock_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	body.add_child(mi)
	return mi


func _exit_tree() -> void:
	if net_id != 0:
		Network.unregister_enemy(self)


static func _flat_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func ai() -> String:
	return data.get("ai", "melee")


## A horda fica parada enquanto o grupo escolhe as cartas de nível (survival_mode.frozen).
## No servidor/solo o pai é o modo sobrevivência; na réplica do cliente, o mundo.
func _horde_frozen() -> bool:
	if not horde or get_parent() == null:
		return false
	if get_parent().get("frozen") == true:
		return true
	var sv = get_parent().get("survival")
	return sv != null and is_instance_valid(sv) and sv.get("frozen") == true


func _make_health_bar() -> void:
	bar_root = Node3D.new()
	bar_root.position.y = data.height * data.scale * (size_mult if level > 0 else 1.0) + 0.45
	add_child(bar_root)
	if _bar_meshes.is_empty():      # as duas malhas (e os materiais) servem para todas as barras
		for spec in [[Vector2(1.0, 0.12), Color(0, 0, 0, 0.7), 0], [Vector2(0.96, 0.08), Color(0.85, 0.15, 0.1), 1]]:
			var q := QuadMesh.new()
			q.size = spec[0]
			q.material = _bar_mat(spec[1], spec[2])
			_bar_meshes.append(q)
	var bg := MeshInstance3D.new()
	bg.mesh = _bar_meshes[0]
	bar_root.add_child(bg)
	bar_fg = MeshInstance3D.new()
	bar_fg.mesh = _bar_meshes[1]
	bar_root.add_child(bar_fg)
	bar_root.visible = false


func _make_name_tag() -> void:
	var top: float = data.height * data.scale * size_mult
	name_tag = Label3D.new()
	name_tag.text = display_name
	name_tag.font_size = 32
	name_tag.outline_size = 8
	name_tag.pixel_size = 0.00075 if not is_boss else 0.001   # fixed_size: tamanho na tela, não no mundo
	name_tag.fixed_size = true
	name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_tag.no_depth_test = true
	name_tag.render_priority = 2
	name_tag.outline_render_priority = 1
	name_tag.modulate = _own_plate_color()
	if level > 0:
		_update_plate_color()
		Game.leveled_up.connect(_update_plate_color)
	name_tag.position.y = top + (0.75 if not is_boss else 0.5)
	name_tag.visibility_range_end = NAME_RANGE * (2.0 if is_boss else 1.0)
	add_child(name_tag)
	quest_icon = Sprite3D.new()
	quest_icon.texture = _quest_texture()
	quest_icon.pixel_size = 0.0024
	quest_icon.fixed_size = true
	quest_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	quest_icon.no_depth_test = true
	quest_icon.render_priority = 2
	quest_icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	quest_icon.position.y = name_tag.position.y
	quest_icon.offset.y = 18.0     # em pixels do ícone: fica logo acima do nome a qualquer distância
	quest_icon.visibility_range_end = name_tag.visibility_range_end
	add_child(quest_icon)
	Game.quests_changed.connect(_update_quest_icon)
	_update_quest_icon()


## Cor própria da placa: chefe laranja, elite dourada, comum quase branca.
func _own_plate_color() -> Color:
	if is_boss:
		return Color(1.0, 0.45, 0.25)
	if elite or data.get("elite", false):
		return Color(1.0, 0.8, 0.35)
	return Color(1.0, 0.92, 0.85)


## Cor da placa pela diferença de nível para o jogador local: bem abaixo cinza, perto branco, acima amarelo,
## muito acima vermelho. Chefes e elites mantêm a cor própria, menos no vermelho (que avisa do bônus de vs()).
func _update_plate_color(_new_level := 0) -> void:
	if name_tag == null:
		return
	var diff := level - Game.level
	if diff >= ProgressionRules.danger_diff(Balance.tables):
		name_tag.modulate = PLATE_DANGER_COLOR
	elif is_boss or elite or data.get("elite", false):
		name_tag.modulate = _own_plate_color()
	elif diff <= PLATE_LOW:
		name_tag.modulate = Color(0.6, 0.6, 0.6)
	elif diff >= PLATE_HIGH:
		name_tag.modulate = Color(1.0, 0.85, 0.3)
	else:
		name_tag.modulate = Color(1.0, 1.0, 1.0)


## Ícone de missão: só aparece se uma missão ativa conta o abate deste tipo (some quando fica pronta).
func _update_quest_icon() -> void:
	if quest_icon == null or dead:
		return
	quest_icon.visible = CharRules.is_quest_target(Game.quests, ItemDB.QUESTS, kind, area)


## Escudo dourado com "!" escuro, desenhado uma vez e usado por todos os inimigos.
static func _quest_texture() -> ImageTexture:
	if _quest_tex:
		return _quest_tex
	const S := 24
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	var dark := Color(0.2, 0.1, 0.02)
	var gold := Color(1.0, 0.78, 0.2)
	var light := Color(1.0, 0.93, 0.55)
	var c := (S - 1) / 2.0
	for y in S:
		for x in S:
			var d := absf(x - c) + absf(y - c)      # losango
			if d <= c - 2.0:
				img.set_pixel(x, y, light if x + y < S - 3 else gold)
			elif d <= c:
				img.set_pixel(x, y, dark)
	for y in range(6, 14):                         # "!": traço e ponto
		for x in range(11, 13):
			img.set_pixel(x, y, dark)
	for y in range(15, 17):
		for x in range(11, 13):
			img.set_pixel(x, y, dark)
	_quest_tex = ImageTexture.create_from_image(img)
	return _quest_tex


static func _bar_mat(c: Color, priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.no_depth_test = true
	m.render_priority = priority
	return m


func _physics_process(delta: float) -> void:
	if not horde and not is_boss:
		_far_t -= delta
		if _far_t <= 0.0:
			_far_t = SLEEP_CHECK
			_update_far()
	if puppet:
		if not still:
			_puppet_process(delta)
		return
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	if dead:
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		return
	if _horde_frozen():
		velocity = Vector3.ZERO
		return
	if sleep_radius > 0.0:
		_sleep_t -= delta
		if _sleep_t <= 0.0:
			_sleep_t = SLEEP_CHECK
			asleep = should_sleep(state, is_on_floor(), is_boss, _player_within(sleep_radius))
		if asleep:
			return
	born_t += delta
	attack_cd = max(0.0, attack_cd - delta)
	web_cd = maxf(0.0, web_cd - delta)
	slow_timer = max(0.0, slow_timer - delta)
	venom_timer = maxf(0.0, venom_timer - delta)
	if ai() == "burrow" and state != "burrow":
		surface_t += delta
	if ai() == "worm":
		_worm_leash(delta)
	stagger = max(0.0, stagger - delta)
	provoked = maxf(0.0, provoked - delta)
	_update_flash(delta)
	if not horde and _ward_doom(delta):
		return

	var player := _nearest_player()
	if ai() == "worm":
		player = _worm_in_pit("near")   # a Mãe-Verme só vê quem está dentro do fosso (null = ninguém)
	var to_player := Vector3.ZERO
	var dist := INF
	if player and not player.dead:
		to_player = player.global_position - global_position
		to_player.y = 0
		dist = to_player.length()

	_track_target(player, delta)
	# Égide Cristalina: com o alvo atrás da coroa (ele dentro, este monstro fora), o alvo vira a própria parede:
	# a distância é até a coroa e o golpe vai para o escudo de quem ergueu (AegisWalls.blocking)
	var strike: Node = player
	if dist < INF and ai() != "worm":
		var wall := AegisWalls.blocking(self, player)
		if not wall.is_empty():
			var c := AegisWalls.center(wall)
			to_player = Vector3(c.x - global_position.x, 0.0, c.z - global_position.z)
			dist = maxf(to_player.length() - AegisWalls.radius_now(wall), 0.05)
			strike = wall.caster

	var spd: float = data.speed * speed_mult * (0.45 if slow_timer > 0 else 1.0) * (1.3 if enraged else 1.0)
	var move := Vector3.ZERO
	var face := Vector3.ZERO

	match state:
		"idle":
			state_timer -= delta
			if dist < data.aggro or (horde and dist < INF):
				_set_state("chase")
			elif state_timer <= 0:
				wander_target = home + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
				_set_state("wander")
		"wander":
			var to := wander_target - global_position
			to.y = 0
			if dist < data.aggro:
				_set_state("chase")
			elif to.length() < 0.6 or state_timer > 6.0 or _stuck_t > 0.4:
				state_timer = randf_range(2.0, 4.5)
				state = "idle"
			else:
				move = to.normalized() * spd * 0.4
				state_timer += delta
		"chase":
			if ai() == "worm":
				# Mãe-Verme: não anda na superfície; morde perto, cospe ácido longe e, depois de alguns ataques,
				# mergulha para sair debaixo do alvo. Sem ninguém no fosso, mergulha e volta para casa.
				if dist < INF:
					face = to_player
				if not _worm_target_ok(player):
					_worm_dive()
				elif worm_hits >= BossRules.surface_attacks(int(data.get("surface_attacks", 3)), _fury_dives) \
						and attack_cd <= 0:
					_worm_dive()
				elif attack_cd <= 0:
					_begin_attack(dist)
			elif horde and ai() != "melee" and ai() != "bomber" and ai() != "pack":
				if dist == INF:
					_set_state("idle")
				else:
					var r := _ranged_move(to_player, dist, spd)
					move = r[0]
					face = r[1]
			elif horde:
				if dist == INF:
					_set_state("idle")
				elif dist <= data.reach and attack_cd <= 0:
					_begin_attack()
				elif dist > data.reach * 0.8:
					move = to_player.normalized() * spd
			elif global_position.distance_to(home) > 45.0 or dist == INF \
					or (dist > data.aggro * 1.9 and provoked <= 0.0):
				_set_state("return")   # sem alvo (morreu ou entrou na vila, sob a guarda) também volta
			elif ai() == "ranged" or ai() == "caster" or ai() == "flee":
				# arqueiro e mago no mundo: guardam distância, rodeiam e só atiram com o caminho livre;
				# o Goblin Dourado foge (antes caía no corpo a corpo: corria para cima e só empurrava)
				var r := _ranged_move(to_player, dist, spd)
				move = r[0]
				face = r[1]
			elif ai() == "burrow" and BurrowRules.should_dig(dist, surface_t, data):
				_set_state("burrow")   # Toupeira: afunda e vai por baixo da terra até o alvo
				dig_t = 0.0
			elif (dist <= data.reach or _web_ready(dist)) and attack_cd <= 0:
				_begin_attack(dist)
			elif dist > data.reach * 0.8:
				if ai() == "pack":
					move = _pack_dir(to_player, dist) * spd
				elif ai() == "flyer":
					move = _fly_dir(to_player, dist) * spd
				else:
					move = _flank_dir(to_player, dist) * spd
			if face == Vector3.ZERO:
				face = to_player
		"return":
			if ai() == "worm":
				_worm_dive()
			var to := home - global_position
			to.y = 0
			if dist < data.aggro * 0.7:
				_set_state("chase")
			elif to.length() < 1.0:
				hp = max_hp
				contributors.clear()   # curou tudo em casa: quem tinha acertado antes não leva XP, loot nem abate depois
				health_changed.emit(self)
				_set_state("idle")
			else:
				move = to.normalized() * spd
		"burrow":
			dig_t += delta
			var tgt: Vector3 = player.global_position if player and not player.dead else global_position
			var going_home := false
			if ai() == "worm":   # o Mergulho sai debaixo de quem está mais longe dela no fosso
				var far = _worm_far_target()
				going_home = far == null
				tgt = home if going_home else BurrowRules.clamp_to_leash(far.global_position, home, _worm_leash_size())
			var fury := 1.6 if enraged and ai() == "worm" else 1.0   # na fúria a Mãe-Verme cava mais rápido
			var nxt := BurrowRules.dig_step(global_position, tgt, float(data.dig_speed) * speed_mult * fury, delta)
			move = (nxt - global_position) / maxf(delta, 0.0001)
			move.y = 0.0
			face = move
			if going_home:
				if Vector2(home.x - global_position.x, home.z - global_position.z).length() < 1.0:
					pass   # em casa, sem ninguém: fica enterrada esperando (a próxima luta começa com a entrada)
			elif BurrowRules.should_emerge(global_position, tgt, dig_t, data):
				_begin_emerge()
		"attack":
			_update_attack(delta, strike, to_player, dist)
			if attack_kind == "lunge" and attack_timer > 0.35 and attack_timer < 0.6:
				move = model_forward() * spd * (2.0 if ai() in ["pack", "weaver", "flyer"] else 3.2)
			elif dist < INF and (attack_timer < 0.35 or ((attack_kind in ["shoot", "web", "tongue", "cast"])
					and attack_timer < _hit_time())):
				face = _aim_dir(to_player, dist) if attack_kind == "shoot" else to_player
			# golpe comum: dá um passo para dentro enquanto arma, para o golpe não sair no vazio
			if attack_kind in ["swing", "slam"] and attack_timer < _hit_time() and dist > data.reach * 0.6 \
					and dist < data.reach * 1.8 and ai() != "plant":
				move = to_player.normalized() * spd * 0.45

	if stagger > 0:
		move = Vector3.ZERO
	elif state in ["chase", "wander", "return"]:
		move = _steer(move, delta)
	# a guarda da vila: nenhum passo para dentro da zona protegida (o bando para na cerca)
	if not horde and move.length() > 0.01 			and VillageWard.blocks_step(global_position, global_position + move.normalized() * WARD_LOOKAHEAD):
		move = Vector3.ZERO
		if state == "wander":
			state_timer = 7.0   # desiste do passeio (vira idle no próximo quadro)
	if face == Vector3.ZERO and move.length() > 0.1:
		face = move
	if face.length() > 0.01:
		var turn := 14.0 if state == "attack" and attack_kind == "shoot" else 9.0
		model.rotation.y = lerp_angle(model.rotation.y, atan2(face.x, face.z), turn * delta)

	var accel := 30.0
	velocity.x = move_toward(velocity.x, move.x, accel * delta)
	velocity.z = move_toward(velocity.z, move.z, accel * delta)
	if ai() == "worm" and state != "burrow":   # Mãe-Verme fincada no chão: não escorrega nem é empurrada
		velocity.x = 0.0
		velocity.z = 0.0
	move_and_slide()
	if ai() != "worm":
		AegisWalls.keep_out(self, radius)   # Égide erguida por perto: não entra (e é empurrado enquanto ela se forma)
	_check_stuck(move, delta)
	_animate(delta, Vector2(velocity.x, velocity.z).length())
	if bar_root and bar_root.visible:
		bar_fg.scale.x = max(0.001, hp / max_hp)
		bar_fg.position.x = 0.0


## Longe da câmera o monstro do mundo some da tela, e a réplica do cliente para de seguir e de animar (os
## snapshots continuam chegando; ao voltar ela pula para onde o servidor diz). Quem decide (solo) só some
## dormindo. Sem câmera (servidor dedicado) não faz nada. Chefes e a Horda ficam de fora.
func _update_far() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or dead:
		return
	var d := global_position.distance_to(cam.global_position)
	if puppet:
		var calm: bool = state in ["idle", "wander"] or d > FAR_HIDE + FAR_MARGIN
		still = calm and d > (FAR_STILL if still else FAR_STILL + FAR_MARGIN)
	var rest := still if puppet else asleep
	var show := not rest or d < (FAR_HIDE if not visible else FAR_HIDE + FAR_MARGIN)
	if show != visible:
		visible = show
		if show and puppet:
			global_position = _net_pos
			reset_physics_interpolation()


## A guarda da vila (solo/servidor): monstro dentro da zona protegida leva a flecha de um guarda depois de
## VillageWard.DOOM segundos. true = morreu agora (o quadro para aqui).
func _ward_doom(delta: float) -> bool:
	if not VillageWard.inside(global_position, VillageWard.KILL_MARGIN):
		ward_t = 0.0
		return false
	ward_t += delta
	if ward_t < VillageWard.DOOM:
		return false
	guard_kill()
	return true


## Abatido pela guarda da vila: morre sem dar XP, loot nem abate de missão a ninguém (nem a quem já tinha
## acertado). No servidor as réplicas recebem a morte com o aviso da guarda.
func guard_kill() -> void:
	if dead or puppet:
		return
	contributors.clear()
	last_hitter = 0
	if Network.is_server():
		Network.server_enemy_guard_killed(self)
	die_visual()
	guard_fx()


## Aviso sobre o monstro abatido pela guarda (solo, servidor e réplicas).
func guard_fx() -> void:
	var top: Vector3 = global_position + Vector3.UP * (data.height * data.scale + 0.4)
	FX.damage_number(top, "Abatido pela guarda", Color(0.75, 0.82, 0.95), 40)


## Regra do sono (pura): parado ou passeando, no chão, sem chefe e sem jogador perto.
static func should_sleep(st: String, on_floor: bool, boss: bool, player_near: bool) -> bool:
	return not boss and on_floor and not player_near and st in ["idle", "wander"]


## Algum jogador vivo do mesmo mundo a menos de `r` metros.
func _player_within(r: float) -> bool:
	var w := get_world_3d()
	var r2 := r * r
	for p in get_tree().get_nodes_in_group("players"):
		if not p.dead and p.get_world_3d() == w and global_position.distance_squared_to(p.global_position) < r2:
			return true
	return false


## Jogador vivo mais próximo (no multiplayer, o servidor tem réplicas de todos).
## A horda só persegue quem está no desafio (get_parent() é o modo sobrevivência).
func _nearest_player() -> Player:
	var best: Player = null
	var best_d := INF
	var pool: Array = get_parent().targets() if horde and get_parent().has_method("targets") 		else get_tree().get_nodes_in_group("players")
	var w := get_world_3d()
	for p in pool:
		if p.dead or p.get_world_3d() != w:   # o servidor roda Valdoria e a cidade em mundos separados
			continue
		if not horde and VillageWard.inside(p.global_position):
			continue   # quem está na vila (ou na Horta) está sob a proteção da guarda: o monstro não persegue
		var d := global_position.distance_squared_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


func model_forward() -> Vector3:
	return Vector3(sin(model.rotation.y), 0, cos(model.rotation.y))


func _set_state(s: String) -> void:
	state = s
	state_timer = 0.0
	if ai() in ["burrow", "worm"]:
		if s == "burrow":
			_set_buried(true)
		elif s != "attack":   # no "attack" quem desenterra é o golpe de emergir (_emerge_hit)
			_set_buried(false)
	if s == "chase" and bar_root and not horde:
		bar_root.visible = true
	if s == "chase" and ai() == "pack" and not horde:
		_alert_pack()


## Bando (raptor): quem vê o jogador chama os do mesmo tipo que estão por perto, e o bando ataca junto.
func _alert_pack() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != self and e.kind == kind and not e.dead and (e.state == "idle" or e.state == "wander") 				and e.global_position.distance_to(global_position) < 14.0:
			e._set_state("chase")


## Bando: de longe, cada membro abre para um lado (um vem de frente, os outros pelos flancos) e fecha o
## cerco ao chegar perto. O lado sai do id, então é o mesmo no servidor e em cada nascimento.
func _pack_dir(to_player: Vector3, dist: float) -> Vector3:
	var dir := to_player.normalized()
	var slot := (net_id if net_id != 0 else get_instance_id()) % 3
	var ang: float = [0.0, 0.75, -0.75][slot] * clampf((dist - data.reach * 1.5) / 6.0, 0.0, 1.0)
	return dir.rotated(Vector3.UP, ang)


## Arqueiro, xamã e goblin dourado: mantêm distância (ou fogem) em vez de correr para cima.
## Devolve [movimento, direção para olhar].
func _ranged_move(to_player: Vector3, dist: float, spd: float) -> Array:
	var dir := to_player.normalized() if dist > 0.01 else Vector3.FORWARD
	var side := dir.cross(Vector3.UP) * (1.0 if net_id % 2 == 0 else -1.0)
	var move := Vector3.ZERO
	if ai() == "flee":
		if dist < 16.0:
			move = (-dir + side * 0.5).normalized() * spd
		else:
			move = side * spd * 0.4
		# não sai da arena: puxa para o centro perto da borda
		var sv := get_parent()
		if sv and sv.get("center") != null:
			var to_c: Vector3 = sv.center - global_position
			to_c.y = 0
			if to_c.length() > sv.ARENA_RADIUS - 4.0:
				move = (move.normalized() + to_c.normalized() * 1.6).normalized() * spd
		elif not horde:
			# no mundo: corre em volta do ponto dele em vez de sumir no mapa (dá para encurralar)
			var to_h := home - global_position
			to_h.y = 0
			if to_h.length() > FLEE_LEASH:
				move = (move.normalized() + to_h.normalized() * 1.6).normalized() * spd
		return [move, move if move.length() > 0.1 else dir]
	var keep: float = data.get("keep", 7.0)
	# rodeia trocando de lado de tempos em tempos (cada um no seu ritmo), em vez de ficar parado na mira
	if fmod(born_t + float(_uid() % 7), 7.0) > 4.0:
		side = -side
	var clear := ai() != "ranged" or _line_clear(dist)
	if dist < keep * 0.7:
		move = (-dir + side * 0.4).normalized() * spd * 0.9
	elif dist > data.reach * 0.85:
		move = dir * spd
	elif not clear:
		move = (side + dir * 0.3).normalized() * spd * 0.8   # árvore ou pedra no meio: anda de lado até abrir a linha
	else:
		move = side * spd * 0.35
	if dist <= data.reach and attack_cd <= 0 and clear:
		_begin_attack()
		move = Vector3.ZERO
	return [move, dir]


# ------------------------------------------------------------ ataques
## Ataque especial de meia distância pronto? Tecelã: teia; Bocarrão: língua que puxa; Kobold: dinamite.
func _web_ready(dist: float) -> bool:
	if web_cd > 0.0 or dist <= data.reach * 1.4:
		return false
	if data.has("throw_range"):   # Kobold: dinamite de meia distância (colado, vai de picareta)
		return dist > data.reach * 1.6 and dist < float(data.throw_range)
	match ai():
		"weaver":
			return dist > data.reach * 1.6 and dist < float(data.get("web_range", 10.0))
		"frog":
			return dist < float(data.get("tongue_range", 7.0))
	return false


## Asa-couro: de longe, chega rodeando (cada um para um lado) em vez de vir reto.
func _fly_dir(to_player: Vector3, dist: float) -> Vector3:
	var side := 1.0 if (net_id if net_id != 0 else get_instance_id()) % 2 == 0 else -1.0
	var ang := side * 0.9 * clampf((dist - data.reach * 1.3) / 5.0, 0.0, 1.0)
	return to_player.normalized().rotated(Vector3.UP, ang + sin(born_t * 1.3) * 0.25)


func _uid() -> int:
	return net_id if net_id != 0 else get_instance_id()


## Corpo a corpo comum no mundo: de longe, cada um chega por um ângulo um pouco diferente (o grupo abre em
## leque e cerca em vez de vir em fila, um atrás do outro); perto, vai reto.
func _flank_dir(to_player: Vector3, dist: float) -> Vector3:
	var dir := to_player.normalized()
	if horde:
		return dir
	var ang: float = [0.0, 0.45, -0.45][_uid() % 3] * clampf((dist - data.reach * 2.0) / 6.0, 0.0, 1.0)
	return dir.rotated(Vector3.UP, ang)


# ------------------------------------------------------------ desvio de obstáculos
## Antes o monstro andava em linha reta até o alvo e ficava empurrando o tronco da árvore (não existe malha de
## navegação no mundo). Agora, a cada STEER_EVERY segundos, dois raios paralelos (largura do corpo) olham à
## frente; com o caminho fechado, ele escolhe um lado e gira a direção até achar passagem, e mantém esse lado
## enquanto contorna (sem ficar indo e voltando). Encostado no obstáculo, escorrega pela borda; se mesmo assim
## não sai do lugar, troca de lado (_check_stuck).
const STEER_EVERY := 0.15
const STEER_ANGLES := [0.45, 0.85, 1.25, 1.7, 2.2]
const STEER_HEIGHT := 0.45     # altura dos raios: acima dos degraus do chão, abaixo da copa das árvores
var _steer_t := 0.0
var _steer_ang := 0.0          # quanto a direção desejada gira (rad) até a próxima conferência
var _detour := 0               # lado do contorno: 1 (esquerda), -1 (direita), 0 = caminho livre
var _stuck_t := 0.0
var _unstick_t := 0.0
var _los_t := 0.0
var _los_ok := true
## Alvo atual e a velocidade estimada dele (para a flecha mirar adiante).
var _tgt: Player = null
var _tgt_prev := Vector3.ZERO
var _tgt_vel := Vector3.ZERO


func _steer(move: Vector3, delta: float) -> Vector3:
	var spd := Vector2(move.x, move.z).length()
	if spd < 0.05 or data.speed <= 0.0:
		return move
	var dir := Vector3(move.x, 0.0, move.z) / spd
	_unstick_t = maxf(0.0, _unstick_t - delta)
	_steer_t -= delta
	if _steer_t <= 0.0:
		_steer_t = STEER_EVERY * randf_range(0.8, 1.25)
		_steer_ang = _pick_angle(dir, spd)
	var out := dir.rotated(Vector3.UP, _steer_ang)
	var n := _blocking_normal()
	if n != Vector3.ZERO and out.dot(n) < 0.0:
		# encostado: segue a borda do obstáculo para o lado do contorno
		var along := out.slide(n)
		if along.length() < 0.35:
			if _detour == 0:
				_detour = 1 if Vector3.UP.cross(dir).dot(n.cross(Vector3.UP)) >= 0.0 else -1
			along = Vector3.UP.cross(dir) * float(_detour)
			along = along.slide(n)
		out = (along.normalized() + n * 0.2).normalized()
	return Vector3(out.x * spd, move.y, out.z * spd)


func _pick_angle(dir: Vector3, spd: float) -> float:
	if _unstick_t > 0.0:
		return _steer_ang
	var look := clampf(radius + 0.9 + spd * 0.3, 1.4, 3.4)
	if _free(dir, look) >= 0.999:
		_detour = 0
		return 0.0
	if _detour == 0:
		var l := _free(dir.rotated(Vector3.UP, 0.8), look)
		var r := _free(dir.rotated(Vector3.UP, -0.8), look)
		if absf(l - r) > 0.05:
			_detour = 1 if l > r else -1
		else:
			_detour = 1 if _uid() % 2 == 0 else -1
	for a: float in STEER_ANGLES:
		if _free(dir.rotated(Vector3.UP, a * _detour), look * 0.8) >= 0.999:
			return a * _detour
	for a: float in STEER_ANGLES:
		if _free(dir.rotated(Vector3.UP, -a * _detour), look * 0.8) >= 0.999:
			_detour = -_detour
			return a * _detour
	return 2.2 * _detour


## Fração livre (0..1) do caminho `dir` até `dist` metros, com dois raios na largura do corpo. Batidas no chão
## (normal para cima: rampa, morro) não contam.
func _free(dir: Vector3, dist: float) -> float:
	var space := get_world_3d().direct_space_state
	var side := Vector3.UP.cross(dir).normalized() * radius * 0.85
	var best := 1.0
	for off in [side, -side]:
		var from: Vector3 = global_position + Vector3.UP * STEER_HEIGHT + off
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * dist, 1, [get_rid()])
		var hit := space.intersect_ray(q)
		if hit.is_empty() or (hit.normal as Vector3).y > 0.6:
			continue
		best = minf(best, from.distance_to(hit.position) / dist)
	return best


## Normal (horizontal) do que o monstro empurra agora: obstáculo do mapa ou outro monstro (não o jogador).
func _blocking_normal() -> Vector3:
	var sum := Vector3.ZERO
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_collider() is Player:
			continue
		var n := c.get_normal()
		if absf(n.y) < 0.5:
			sum += Vector3(n.x, 0.0, n.z)
	return sum.normalized() if sum.length() > 0.01 else Vector3.ZERO


## Quer andar mas quase não sai do lugar por um tempo: troca o lado do contorno e força a volta por ele.
func _check_stuck(move: Vector3, delta: float) -> void:
	var want := Vector2(move.x, move.z).length()
	var got := Vector2(get_real_velocity().x, get_real_velocity().z).length()
	if state in ["chase", "wander", "return"] and stagger <= 0.0 and want > 0.8 and got < want * 0.3:
		_stuck_t += delta
	else:
		_stuck_t = maxf(0.0, _stuck_t - delta * 2.0)
	if _stuck_t > 0.6:
		_stuck_t = 0.45 if state == "wander" else 0.0   # passeando: desiste do ponto (ver "wander")
		_detour = -_detour if _detour != 0 else (1 if _uid() % 2 == 0 else -1)
		_steer_ang = 1.5 * _detour
		_unstick_t = 0.7
		_steer_t = 0.7


## Linha livre do arco (ou do cajado) até o alvo, sem árvore, pedra ou parede no meio (conferida a cada 0,25 s).
func _line_clear(dist: float) -> bool:
	if _tgt == null or not is_instance_valid(_tgt) or dist > data.reach * 1.2:
		return true
	_los_t -= get_physics_process_delta_time()
	if _los_t > 0.0:
		return _los_ok
	_los_t = 0.25
	var from := global_position + Vector3.UP * 1.0 * float(data.scale)
	var q := PhysicsRayQueryParameters3D.create(from, _tgt.global_position + Vector3.UP * 1.0, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	_los_ok = hit.is_empty() or (hit.normal as Vector3).y > 0.6
	return _los_ok


## Guarda o alvo e estima a velocidade dele pelo deslocamento (no servidor, o jogador é réplica e não tem
## velocity confiável).
func _track_target(player: Player, delta: float) -> void:
	if player != _tgt:
		_tgt = player
		_tgt_vel = Vector3.ZERO
		if player:
			_tgt_prev = player.global_position
		return
	if player == null or delta <= 0.0:
		return
	var v := (player.global_position - _tgt_prev) / delta
	v.y = 0.0
	if v.length() > 15.0:     # teleporte ou correção de rede: não é velocidade
		v = Vector3.ZERO
	_tgt_vel = _tgt_vel.lerp(v, 0.12)
	_tgt_prev = player.global_position


## Direção da flecha: onde o alvo vai estar quando ela chegar (um pouco menos, para não ser perfeita).
func _aim_dir(to_player: Vector3, dist: float) -> Vector3:
	var lead := _tgt_vel * (dist / ENEMY_ARROW.SPEED) * 0.7
	var aim := to_player + lead
	aim.y = 0.0
	return aim if aim.length() > 0.01 else to_player


func _begin_attack(dist := 0.0) -> void:
	state = "attack"
	attack_timer = 0.0
	hit_done = false
	attack_count += 1
	match ai():
		"ranged":
			attack_kind = "shoot"
			return
		"caster":
			attack_kind = "cast"
			return
		"bomber":
			attack_kind = "fuse"
			FX.telegraph(global_position, data.blast, _hit_time())
			return
		"pack":
			attack_kind = "lunge"   # bote com mordida (o salto para a frente fica no estado "attack")
			return
		"weaver":
			if _web_ready(dist):
				attack_kind = "web"
				web_cd = float(data.get("web_cd", 6.0)) * randf_range(0.85, 1.15)
			else:
				attack_kind = "lunge"
			return
		"frog":
			if _web_ready(dist):
				attack_kind = "tongue"
				tongue_len = dist
				web_cd = float(data.get("tongue_cd", 5.0)) * randf_range(0.85, 1.15)
			else:
				attack_kind = "lunge"   # bote curto com pulo
				velocity.y = 3.5
			return
		"flyer":
			attack_kind = "lunge"   # rasante
			return
		"worm":
			attack_kind = BossRules.worm_attack(worm_hits, _specials, dist, float(data.reach))
			worm_hits += 1
			match attack_kind:
				"slam":   # mordida que bate no chão em volta
					FX.telegraph(global_position, _slam_radius(), 0.9)
				"quake":
					_specials += 1
					_quake_warn(0.0)
				"rockfall":
					_specials += 1
					boss_seed = randi() & 0xFFFF
					_rock_pts = _rockfall_targets(global_position)
					_rockfall_warn(0.0)
				"acid_rain":
					var far = _worm_far_target()   # as Poças caem em quem está mais longe dela no fosso
					var aim: Vector3 = far.global_position if far != null else global_position + model_forward() * 8.0
					throw_point = BurrowRules.clamp_to_leash(aim, home, _worm_leash_size())
					_acid_pts = BossRules.acid_points(global_position, throw_point)
					_acid_warn(0.0)
			return
	if data.has("throw_range") and _web_ready(dist) and _tgt != null and is_instance_valid(_tgt):
		attack_kind = "throw"
		web_cd = float(data.get("throw_cd", 5.0)) * randf_range(0.85, 1.15)
		throw_point = ThrowRules.target(global_position, _tgt.global_position, float(data.throw_range))
		var to := throw_point - global_position
		if to.length() > 0.01:
			model.rotation.y = atan2(to.x, to.z)
		FX.telegraph(throw_point, data.blast, _hit_time())
		return
	if data.model == "slime":
		attack_kind = "lunge"
		velocity.y = 4.5
	elif (is_boss and attack_count % 3 == 0) or (data.has("slam_every") and attack_count % int(data.slam_every) == 0):
		attack_kind = "slam"
		FX.telegraph(global_position, _slam_radius(), 0.9)
	else:
		attack_kind = "swing"


func _slam_radius() -> float:
	return 5.0 if is_boss else 3.6


func _attack_duration() -> float:
	match attack_kind:
		"slam":
			return 1.6
		"lunge":
			return 1.0
		"shoot":
			return 1.0
		"cast":
			return 1.3
		"fuse":
			return 1.2
		"web":
			return 1.0
		"tongue":
			return 1.2
		"throw":
			return 1.3
		"emerge":
			return 1.7
		"quake":
			return float(BossRules.quake_ring(BossRules.QUAKE_RINGS - 1).t) + 0.5
		"rockfall":
			return 2.4
		"acid_rain":
			return 1.6
	return 0.95 if not is_boss else 1.1


func _hit_time() -> float:
	match attack_kind:
		"slam":
			return 0.9
		"lunge":
			return 0.45
		"shoot":
			return 0.6
		"cast":
			return 0.75
		"fuse":
			return 0.95
		"web":
			return 0.55
		"tongue":
			return 0.5
		"throw":
			return 1.0
		"emerge":
			return 1.0
		"quake":
			return float(BossRules.quake_ring(0).t)
		"rockfall":
			return 1.8
		"acid_rain":
			return 1.1
	return 0.5 if not is_boss else 0.6


## player: o alvo do ataque.
func _update_attack(delta: float, player, to_player: Vector3, dist: float) -> void:
	attack_timer += delta
	_update_dynamite()
	_boss_tick(false, attack_timer - delta, attack_timer)
	if not hit_done and attack_timer >= _hit_time():
		hit_done = true
		if attack_kind == "shoot":
			_shoot(false)
		elif attack_kind == "web":
			_shoot_web(false)
		elif attack_kind == "tongue":
			_lash_tongue(player, to_player, dist)
		elif attack_kind == "cast":
			_cast_heal(false)
		elif attack_kind == "fuse":
			_explode(false)
			return
		elif attack_kind == "throw":
			_dynamite_blast(false)
		elif attack_kind == "emerge":
			_emerge_hit(false)
		elif attack_kind == "quake":
			pass   # os anéis acertam em _boss_tick, cada um na sua hora
		elif attack_kind == "rockfall":
			_rockfall_hit(false)
		elif attack_kind == "acid_rain":
			_acid_hit(false)
		elif attack_kind == "slam":
			var sr := _slam_radius()
			Sfx.play_at("slam", global_position, 0.0)
			FXToon.slam(global_position, sr)
			if player and dist <= sr:
				player.take_damage(vs(level, player, data.damage * dmg_mult * 1.4), global_position)
			if player is Player:
				player.add_shake(0.4)
		elif player and dist <= data.reach * 1.3 + 0.3:
			var facing_ok := model_forward().dot(to_player.normalized()) > 0.2 or dist < 1.0
			if facing_ok:
				player.take_damage(vs(level, player, data.damage * dmg_mult * randf_range(0.9, 1.1)), global_position)
				if data.has("chill") and player.has_method("apply_chill"):
					player.apply_chill(float(data.chill), data.get("chill_venom", false))
		if attack_kind == "swing" or (attack_kind == "lunge" and data.model in ["raptor", "spider", "centipede", "frog", "bat"]):
			Sfx.play_at("swing", global_position, 0.15, -4.0)
	if attack_timer >= _attack_duration():
		attack_cd = data.cooldown * (0.7 if enraged else 1.0) * randf_range(0.8, 1.2)
		_set_state("chase")


## Ataques especiais dos monstros novos. visual: réplica no cliente (só efeitos; o servidor aplica o dano).
func _shoot(visual: bool) -> void:
	var bolt: bool = data.get("shot", "") == "bolt"
	Sfx.play_at("bow_shot", global_position, 0.1, -5.0)
	var origin := _muzzle()
	var dir := model_forward()
	if not visual and _tgt != null and is_instance_valid(_tgt) and not _tgt.dead:
		# mira onde o alvo vai estar (e vira o corpo para lá, para a réplica no cliente atirar igual)
		var to := _tgt.global_position - global_position
		to.y = 0.0
		dir = _aim_dir(to, to.length()).normalized()
		model.rotation.y = atan2(dir.x, dir.z)
	var arrow := ENEMY_ARROW.new()
	arrow.acid = data.get("shot", "") == "acid"
	arrow.direction = dir
	arrow.damage = 0.0 if visual else data.damage * dmg_mult
	arrow.level = level
	arrow.source = get_parent()
	arrow.magic = bolt or arrow.acid
	get_parent().add_child(arrow)
	arrow.global_position = origin


## De onde sai a flecha ou o raio: o arco (na linha da mira) ou a gema do cajado, pela pose deste quadro.
func _muzzle() -> Vector3:
	var fallback: Vector3 = global_position + Vector3.UP * 1.1 * float(data.scale) + model_forward() * 0.6
	if _rig.is_empty() or parts.get("Body") == null:
		return fallback
	var p := fallback
	if weapon == "staff" and parts.get("Staff") != null:
		p = (parts.Staff as Node3D).global_transform * (_rig.gem as Vector3)
	elif weapon == "bow":
		p = (parts.Body as Node3D).global_transform * (_rig.muzzle as Vector3)
	# o projétil voa reto na altura em que sai: fica na faixa do peito do jogador para poder acertar
	p.y = clampf(p.y, global_position.y + 0.7, global_position.y + 1.5)
	return p


## Bocarrão: a língua acerta quem está na frente, até tongue_range, e puxa para perto da boca (o empurrão do
## golpe sai de trás do jogador). Logo depois vem o bote.
func _lash_tongue(player, to_player: Vector3, dist: float) -> void:
	Sfx.play_at("slime", global_position, 0.2, -2.0)
	if player == null or not (player is Player) or dist > float(data.get("tongue_range", 7.0)) + 0.8:
		return
	if model_forward().dot(to_player.normalized()) < 0.75:
		return   # saiu da frente: a língua passa vazia
	var dir := to_player.normalized()
	player.take_damage(vs(level, player, data.damage * dmg_mult * 0.6), player.global_position + dir)
	attack_cd = 0.0


## Tecelã: bola de teia que prende quem acerta (dano menor que o bote).
func _shoot_web(visual: bool) -> void:
	Sfx.play_at("bow_shot", global_position, 0.25, -8.0)
	var ball := ENEMY_ARROW.new()
	ball.web = true
	ball.web_secs = float(data.get("web_secs", 1.8))
	ball.direction = model_forward()
	ball.damage = 0.0 if visual else data.damage * dmg_mult * 0.5
	ball.level = level
	ball.source = get_parent()
	get_parent().add_child(ball)
	ball.global_position = global_position + Vector3.UP * 0.55 * float(data.scale) + model_forward() * 0.7


func _cast_heal(visual: bool) -> void:
	var r: float = data.heal_radius
	FXToon.heal_pulse(global_position, r)
	Sfx.play_at("heal", global_position, 0.1, -6.0)
	if visual:
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or e.dead or e.horde != horde or e.is_boss:
			continue
		if e.global_position.distance_to(global_position) <= r and e.hp < e.max_hp:
			e.hp = minf(e.max_hp, e.hp + e.max_hp * 0.25)
			e.health_changed.emit(e)
			FXToon.heal_touch(e.global_position)


func _explode(visual: bool) -> void:
	var r: float = data.blast
	Sfx.play_at("explode", global_position, 0.1, -2.0)
	FXToon.blast(global_position, r)
	if visual:
		return
	var pool: Array = get_parent().targets() if get_parent().has_method("targets") else get_tree().get_nodes_in_group("players")
	for p in pool:
		if not p.dead and p.global_position.distance_to(global_position) <= r:
			p.take_damage(vs(level, p, data.damage * dmg_mult), global_position)
			p.add_shake(0.35)
	_die()


## Toupeira: chegou debaixo do alvo (ou cansou de cavar): aviso no chão e, no _hit_time, sai com dano em área.
func _begin_emerge() -> void:
	_set_state("attack")
	attack_kind = "emerge"
	attack_timer = 0.0
	hit_done = false
	attack_count += 1
	FX.telegraph(global_position, float(data.emerge_radius), _hit_time())


## Sai do chão: mostra o modelo, terra voando e dano em quem está no círculo. visual: réplica (sem dano).
func _emerge_hit(visual: bool) -> void:
	_set_buried(false)
	surface_t = 0.0
	worm_hits = 0
	if ai() == "worm":
		if not visual and _fury_dives > 0:
			_fury_dives -= 1
		_boss_intro()
	var r := float(data.emerge_radius)
	Sfx.play_at("slam", global_position, 0.1)
	FXToon.slam(global_position, r)
	if visual:
		return
	var pool: Array = get_parent().targets() if get_parent().has_method("targets") else get_tree().get_nodes_in_group("players")
	for p in pool:
		if not p.dead and p.global_position.distance_to(global_position) <= r:
			p.take_damage(vs(level, p, data.damage * dmg_mult * 1.3), global_position)
			p.add_shake(0.35)


## Mãe-Verme: meio-tamanho (x, z) do retângulo do fosso em volta de `home`.
func _worm_leash_size() -> Vector2:
	var l: Array = data.get("leash", [20, 15])
	return Vector2(float(l[0]), float(l[1]))


## Mãe-Verme: o alvo vale se está vivo e dentro do fosso.
func _worm_target_ok(player) -> bool:
	return player != null and not player.dead and BurrowRules.in_leash(player.global_position, home, _worm_leash_size())


## Mãe-Verme: o jogador vivo dentro do fosso mais perto (`which` = "near": cuspe, mordida, quem ela encara)
## ou mais longe dela ("far": as Poças e o Mergulho). null = ninguém no fosso. Quem está fora do fosso não conta:
## senão um jogador logo fora faria ela mergulhar sem parar.
func _worm_in_pit(which: String) -> Player:
	var cand: Array = []
	var pos: Array = []
	for p in _boss_pool():
		if not p.dead and BurrowRules.in_leash(p.global_position, home, _worm_leash_size()):
			cand.append(p)
			pos.append(p.global_position)
	var i := BossRules.nearest_index(global_position, pos) if which == "near" \
		else BossRules.farthest_index(global_position, pos)
	return cand[i] if i >= 0 else null


func _worm_far_target() -> Player:
	return _worm_in_pit("far")


## Mãe-Verme: mergulha (o estado "burrow" decide para onde: debaixo do alvo ou de volta para casa).
func _worm_dive() -> void:
	_set_state("burrow")
	dig_t = 0.0


## Mãe-Verme: a cada 1 s confere o fosso; sem ninguém e ferida, volta à vida cheia (reset de chefe).
func _worm_leash(delta: float) -> void:
	_leash_t -= delta
	if _leash_t > 0.0:
		return
	_leash_t = 1.0
	var n := 0
	var pool: Array = get_parent().targets() if get_parent().has_method("targets") else get_tree().get_nodes_in_group("players")
	for p in pool:
		if not p.dead and BurrowRules.in_leash(p.global_position, home, _worm_leash_size()):
			n += 1
	if BurrowRules.worm_should_reset(n, hp, max_hp):
		hp = max_hp
		enraged = false
		summoned = false
		contributors.clear()
		_fury_dives = 0
		_specials = 0
		_intro_shown = false
		_set_fury_look(false)
		health_changed.emit(self)


## Quem pode levar os golpes do chefe (no solo/servidor): a lista do modo (Horda) ou os jogadores do mundo.
func _boss_pool() -> Array:
	return get_parent().targets() if get_parent().has_method("targets") else get_tree().get_nodes_in_group("players")


## O jogador desta tela (null no servidor dedicado).
func _local_player() -> Node3D:
	var w := get_tree().current_scene
	return w.get("player") if w != null else null


## Entrada de chefe: a primeira vez que sai do chão perto deste jogador, a tela treme, ela ruge e o nome aparece
## em destaque (o letreiro das regiões). De novo só depois de um reset.
func _boss_intro() -> void:
	if _intro_shown:
		return
	var lp := _local_player()
	if lp == null or lp.global_position.distance_to(global_position) > 30.0:
		return
	_intro_shown = true
	if lp.has_method("add_shake"):
		lp.add_shake(0.9)
	Sfx.play_at("slam", global_position, 0.0)
	var w := get_tree().current_scene
	var hud = w.get("hud") if w != null else null
	if hud != null and hud.get("region_banner") != null:
		hud.region_banner.show_area(data.name, "Chefe da Geleira de Cristal")


## Partículas de cristal e poeira subindo do corpo o tempo todo (presas ao modelo: somem quando ela afunda).
func _make_boss_aura() -> void:
	if DisplayServer.get_name() == "headless" or model == null:
		return
	var p := CPUParticles3D.new()
	p.amount = 28
	p.lifetime = 2.2
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.3
	p.position = Vector3(0, 2.2, 0)
	p.direction = Vector3.UP
	p.spread = 30.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.3
	p.gravity = Vector3(0, 0.3, 0)
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.14
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = BossFX.CYAN
	box.material = m
	p.mesh = box
	model.add_child(p)
	_boss_aura = p


## Material com brilho próprio (na Mãe-Verme: cristais, olhos e runas). As peças do modelo são juntadas numa
## malha só com o material toon (sem o nome do Blender), então é o brilho que as reconhece.
static func _glows(m: Material) -> bool:
	if m is ShaderMaterial:
		var e = (m as ShaderMaterial).get_shader_parameter("emission")
		return e is Color and (e as Color).get_luminance() > 0.05
	if m is StandardMaterial3D:
		return (m as StandardMaterial3D).emission_enabled
	return false


## Fúria: os cristais, as runas e os olhos passam de ciano/âmbar para vermelho (e a aura também); `on` = false
## devolve as cores. Troca só as superfícies que brilham (_glows); o resto do corpo fica como está.
func _set_fury_look(on: bool) -> void:
	if on == _fury_look:
		return
	_fury_look = on
	for mi: MeshInstance3D in meshes:
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			var cur := mi.get_surface_override_material(s)
			var now: Material = cur if cur != null else src
			if now == null or not _glows(now):
				continue
			var key := "%d:%d" % [mi.get_instance_id(), s]
			if on:
				_fury_saved[key] = cur
				var red: Material = now.duplicate()
				if red is ShaderMaterial:
					(red as ShaderMaterial).set_shader_parameter("albedo", Color(1.0, 0.25, 0.18))
					(red as ShaderMaterial).set_shader_parameter("emission", BossFX.RED)
				elif red is StandardMaterial3D:
					(red as StandardMaterial3D).albedo_color = Color(1.0, 0.25, 0.18)
					(red as StandardMaterial3D).emission = BossFX.RED
				mi.set_surface_override_material(s, red)
			elif _fury_saved.has(key):
				mi.set_surface_override_material(s, _fury_saved[key])
	if not on:
		_fury_saved.clear()
	if _boss_aura != null:
		(_boss_aura.mesh.material as StandardMaterial3D).albedo_color = BossFX.RED if on else BossFX.CYAN


## Onda de Cristais: avisos dos anéis (cada um enche até a sua hora). `elapsed` = quanto do golpe já passou.
func _quake_warn(elapsed: float) -> void:
	var c := _net_pos if puppet else global_position
	for i in BossRules.QUAKE_RINGS:
		var q := BossRules.quake_ring(i)
		if float(q.t) > elapsed:
			BossFX.ring_warning(c, float(q.r), float(q.w), float(q.t) - elapsed)
	var lp := _local_player()
	if lp != null and lp.has_method("add_shake") and lp.global_position.distance_to(c) < 30.0:
		lp.add_shake(0.35)


## Desmoronamento: pedras sorteadas pela semente em volta de `center` e uma sob cada jogador por perto que esteja
## no fosso dela (a mesma região do mapa: servidor e réplica sabem sem trocar nada). Quem passa fora do fosso,
## ainda que perto (o Salão do Cavaleiro é vizinho), não entra na luta.
func _rockfall_targets(center: Vector3) -> Array:
	var pts := BossRules.rockfall_points(boss_seed, center, BossRules.ROCK_SPREAD, BossRules.ROCKS)
	var arena := Regions.area_at(center)
	for p in get_tree().get_nodes_in_group("players"):
		if not p.dead and p.global_position.distance_to(center) < 25.0 and arena != "" 				and Regions.area_at(p.global_position) == arena:
			pts.append(Vector3(p.global_position.x, center.y, p.global_position.z))
	return pts


func _rockfall_warn(elapsed: float) -> void:
	var left := maxf(0.2, _hit_time() - elapsed)
	for p in _rock_pts:
		FX.telegraph(p, 2.2, left)
	var lp := _local_player()
	if lp != null and lp.has_method("add_shake") and lp.global_position.distance_to(global_position) < 30.0:
		lp.add_shake(0.6)   # o rugido que faz o teto ceder
	Sfx.play_at("slam", global_position, 0.0, 2.0)


func _rockfall_hit(visual: bool) -> void:
	if visual:
		return
	var dmg: float = data.damage * dmg_mult * 1.4
	for p in _boss_pool():
		if p.dead:
			continue
		for pt in _rock_pts:
			if Vector2(p.global_position.x - pt.x, p.global_position.z - pt.z).length() <= 2.2:
				p.take_damage(vs(level, p, dmg), pt)
				break


## Poças de Ácido: avisos onde as três bolhas vão cair e as bolhas voando da boca.
func _acid_warn(elapsed: float) -> void:
	var left := maxf(0.2, _hit_time() - elapsed)
	var mouth := (_net_pos if puppet else global_position) + Vector3.UP * 4.2
	for p in _acid_pts:
		FX.telegraph(p, 1.8, left)
		BossFX.lob(mouth, p + Vector3.UP * 0.2, left, 3.0)
	Sfx.play_at("slime", global_position, 0.2, -2.0)


## As bolhas caem: respingo e uma poça em cada ponto (a poça dói por alguns segundos; só o servidor/solo dá dano).
func _acid_hit(visual: bool) -> void:
	var tick: float = data.damage * dmg_mult * 0.25
	for pt in _acid_pts:
		FX.burst(pt + Vector3.UP * 0.3, BossFX.ACID, 12, 3.0, 0.14, 0.6)
		var pool := AcidPool.new()
		pool.dmg = tick
		pool.level = level
		pool.deal = not visual
		get_parent().add_child(pool)
		pool.global_position = pt
	if visual:
		return
	var dmg: float = data.damage * dmg_mult * 0.6
	for p in _boss_pool():
		if p.dead:
			continue
		for pt in _acid_pts:
			if Vector2(p.global_position.x - pt.x, p.global_position.z - pt.z).length() <= 1.8:
				p.take_damage(vs(level, p, dmg), pt)
				break


## A cada quadro de um golpe de chefe entre t0 e t1 (s desde o início): anéis da Onda que irrompem agora e as
## pedras do Desmoronamento que começam a cair (para chegar ao chão no _hit_time). visual: réplica (sem dano).
func _boss_tick(visual: bool, t0: float, t1: float) -> void:
	if state != "attack":
		return
	var c := _net_pos if puppet else global_position
	if attack_kind == "quake":
		for i in BossRules.QUAKE_RINGS:
			var q := BossRules.quake_ring(i)
			if t0 < float(q.t) and float(q.t) <= t1:
				BossFX.crystal_ring(c, float(q.r), clampi(int(float(q.r) * 2.4), 8, 40),
					BossFX.RED if enraged else BossFX.CYAN)
				Sfx.play_at("slam", c, 0.1, -3.0)
				if not visual:
					for p in _boss_pool():
						var d := Vector2(p.global_position.x - c.x, p.global_position.z - c.z).length()
						if not p.dead and BossRules.in_quake_ring(d, i):
							p.take_damage(vs(level, p, data.damage * dmg_mult * 1.1), c)
	elif attack_kind == "rockfall":
		var drop := _hit_time() - 0.55
		if t0 < drop and drop <= t1:
			for pt in _rock_pts:
				BossFX.falling_rock(pt, 0.55)


## Réplica: começa a desenhar um golpe de chefe que o snapshot acabou de trazer (`atk_t` s já passados).
func _replica_boss_start(flags: int, atk_t: float) -> void:
	match attack_kind:
		"quake":
			_quake_warn(atk_t)
		"rockfall":
			boss_seed = BossRules.unpack_seed(flags)
			_rock_pts = _rockfall_targets(_net_pos)
			_rockfall_warn(atk_t)
		"acid_rain":
			throw_point = _net_pos + ThrowRules.unpack_offset(flags)
			_acid_pts = BossRules.acid_points(_net_pos, throw_point)
			_acid_warn(atk_t)


## Enterrada: some o modelo, a barra e a colisão (não pode ser alvo); aparece o monte de terra que anda.
func _set_buried(on: bool) -> void:
	if model:
		model.visible = not on
	collision_layer = 0 if on else _layer
	# fora do grupo "enemies" enquanto enterrada: golpes, flechas, magias, encantos e mira não a acham (e nada de
	# roubo de vida ou fúria batendo num monte de terra); volta ao sair do chão, se não morreu
	if on:
		remove_from_group("enemies")
	elif not dead and not is_in_group("enemies"):
		add_to_group("enemies")
	if bar_root and on:
		bar_root.visible = false
	if name_tag:
		name_tag.visible = not on
	if on and _dirt == null and DisplayServer.get_name() != "headless":
		_dirt = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.85
		sm.height = 0.7
		sm.radial_segments = 10
		sm.rings = 5
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.36, 0.26, 0.18)
		m.roughness = 1.0
		sm.material = m
		_dirt.mesh = sm
		_dirt.position = Vector3(0, 0.02, 0)
		add_child(_dirt)
	if _dirt:
		_dirt.visible = on


## Kobold: a dinamite cai em throw_point e explode em área (quem jogou não morre).
func _dynamite_blast(visual: bool) -> void:
	var r: float = data.blast
	Sfx.play_at("explode", throw_point, 0.1, -2.0)
	FXToon.blast(throw_point, r)
	if visual:
		return
	var pool: Array = get_parent().targets() if get_parent().has_method("targets") else get_tree().get_nodes_in_group("players")
	var walls_hit := {}   # Égide: a explosão do lado de fora bate na coroa (uma vez por escudo), não em quem está dentro
	for p in pool:
		if not p.dead and p.global_position.distance_to(throw_point) <= r:
			var ws := AegisWalls.shielded(p.global_position, throw_point, self)
			if not ws.is_empty():
				for w in ws:
					walls_hit[w.caster] = true
				continue
			p.take_damage(vs(level, p, data.damage * dmg_mult * 1.2), throw_point)
			p.add_shake(0.3)
	for caster in walls_hit:
		if is_instance_valid(caster) and not caster.dead:
			caster.take_damage(vs(level, caster, data.damage * dmg_mult * 1.2), throw_point)


## A banana de dinamite voando em arco da mão até throw_point (só visual; some fora do arremesso).
func _update_dynamite() -> void:
	var flying := state == "attack" and attack_kind == "throw" and attack_timer >= 0.35 and attack_timer < _hit_time()
	if not flying:
		if _dyn:
			_dyn.visible = false
		return
	if _dyn == null:
		if DisplayServer.get_name() == "headless":
			return
		_dyn = MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.06
		c.bottom_radius = 0.06
		c.height = 0.32
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.75, 0.12, 0.1)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.45, 0.1)
		m.emission_energy_multiplier = 0.4
		c.material = m
		_dyn.mesh = c
		_dyn.top_level = true
		add_child(_dyn)
	var t := inverse_lerp(0.35, _hit_time(), attack_timer)
	var hand := global_position + Vector3.UP * 1.1 * float(data.scale)
	_dyn.visible = true
	_dyn.global_position = ThrowRules.arc(hand, throw_point + Vector3.UP * 0.15, t, 2.5)
	_dyn.rotation = Vector3(t * 9.0, 0.0, t * 5.0)


# ------------------------------------------------------------ dano
func take_damage(amount: float, from_pos: Vector3, crit: bool, slow := 0.0, stun := 0.0, pull := 0.0) -> void:
	if dead or BurrowRules.hidden(state, attack_kind, hit_done):
		return
	asleep = false
	_sleep_t = SLEEP_CHECK
	if puppet:
		# o servidor decide; os números de dano chegam de volta em show_hit()
		Network.client_hit_enemy(net_id, amount, from_pos, crit, slow, stun, pull)
		return
	amount = incoming(amount)
	if last_hitter != 0:
		contributors[last_hitter] = true
	if slow > 0.0:
		apply_slow(slow)
	if horde and get_parent().has_method("on_enemy_damaged"):
		# placar do Desafio da Horda (last_hitter = quem acertou no multiplayer; 0 no solo)
		get_parent().on_enemy_damaged(last_hitter, minf(amount, maxf(hp, 0.0)))
	hp -= amount
	health_changed.emit(self)
	var top: Vector3 = global_position + Vector3.UP * (data.height * data.scale + 0.2)
	FX.damage_number(top, ("%d!" if crit else "%d") % int(round(amount)),
		Color(1, 0.85, 0.2) if crit else Color.WHITE, 64 if crit else 48)
	FXToon.hit_splat(global_position + Vector3.UP * data.height * data.scale * 0.5, data.color, 3 if horde else 5)
	_flash_t = 0.1
	provoked = PROVOKE_TIME
	if state in ["idle", "wander", "return"]:
		_set_state("chase")
	if bar_root:
		bar_root.visible = true
	if not is_boss and ai() != "plant":   # a Flor-faminta tem raiz: não recua
		var heavy: bool = data.get("elite", false) or elite or data.model == "golem"   # campeões, elites e o Golem quase não recuam
		var kb := global_position - from_pos
		kb.y = 0
		if kb.length() > 0.01:
			# `pull` > 0: em vez de empurrar, puxa (m/s) em direção a quem bateu (Turbilhão)
			kb = kb.normalized() * ((-pull) if pull > 0.0 else (6.0 if data.model == "slime" else 4.0)) * (0.3 if heavy else 1.0)
			velocity.x = kb.x
			velocity.z = kb.z
		if (state != "attack" and not heavy) or (crit and attack_kind != "fuse"):
			stagger = 0.3
			if state == "attack":
				_set_state("chase")
	if is_boss and not enraged and hp < max_hp * 0.5:
		enraged = true
		if ai() == "worm":
			_fury_dives = BossRules.FURY_DIVES
			_set_fury_look(true)
		Game.notify.emit("%s está enfurecido!" % data.name, Color(1, 0.4, 0.3))
		if not summoned:
			summoned = true
			get_parent().call_deferred("summon_minions", global_position, 2, str(data.get("summon", "goblin")), level)
	if hp <= 0:
		_die()
	elif stun > 0.0:
		apply_stun(stun)


## Atordoamento: para de andar por t segundos e perde o golpe em andamento (chefes são imunes).
func apply_stun(t: float) -> void:
	if puppet:
		Network.client_hit_enemy(net_id, 0.0, global_position, false, 0.0, t)
		return
	if dead or is_boss or BurrowRules.hidden(state, attack_kind, hit_done):
		return
	stagger = max(stagger, t)
	attack_cd = max(attack_cd, t)   # sem golpe novo durante o atordoamento (o stagger de um golpe comum fica como está)
	if state == "attack":
		_set_state("chase")


## Dano que este inimigo leva de um acerto de `amount` (maior se estiver com a marca tóxica, menor se estiver
## bem acima do nível de quem bateu: placa vermelha).
func incoming(amount: float) -> float:
	var a := amount * (1.0 + venom_amp) if venom_timer > 0.0 else amount
	if level > 0:
		var foe := Game.level
		if Network.is_server():
			foe = Party._level(last_hitter) if last_hitter != 0 else 0
		a *= float(ProgressionRules.danger_mults(Balance.tables, level, foe).taken)
	return a


## Nível de quem leva o golpe: o personagem do peer no servidor, o jogador local no solo. 0 = desconhecido.
static func foe_level(p) -> int:
	if not (p is Player):
		return 0
	if p.remote:
		return Party._level(p.peer_id) if Network.is_server() else 0
	return Game.level


## Dano `amount` de um monstro de nível `enemy_level` no jogador `p`, com o bônus do monstro bem acima dele
## (placa vermelha). Também usado pelos projéteis (EnemyArrow.level).
static func vs(enemy_level: int, p, amount: float) -> float:
	if enemy_level <= 0:
		return amount
	return amount * float(ProgressionRules.danger_mults(Balance.tables, enemy_level, foe_level(p)).dmg)


## Marca tóxica: por `secs` segundos, todo dano recebido vale (1 + amp). Não empilha: fica a mais forte.
func apply_venom(amp: float, secs: float) -> void:
	if puppet:
		Network.client_mark_enemy(net_id, amp, secs)
		return
	if amp <= 0.0 or secs <= 0.0:
		return
	if venom_timer <= 0.0 or amp >= venom_amp:
		venom_amp = amp
	venom_timer = maxf(venom_timer, secs)


func apply_slow(t: float) -> void:
	if puppet:
		Network.client_hit_enemy(net_id, 0.0, global_position, false, t)
		return
	slow_timer = max(slow_timer, t)


func _update_flash(delta: float) -> void:
	_flash_t = max(0.0, _flash_t - delta)
	var over: Material = _overlay_base
	if _flash_t > 0:
		over = _overlay_hit
	elif slow_timer > 0:
		over = _overlay_slow
	_set_overlay(over)


## Troca a camada de todas as malhas, só quando ela muda (antes conferia peça por peça a cada passo).
func _set_overlay(over: Material) -> void:
	if over == _overlay_now:
		return
	_overlay_now = over
	for m in meshes:
		m.material_overlay = over


func _die() -> void:
	if Network.is_server():
		# XP, missões e loot de cada jogador que acertou: o servidor concede (CharacterService + pickups)
		Network.server_enemy_killed(self)
	elif not horde:
		# solo: XP, missão e o chefe derrotado (king_dead) ficam com as regras (Econ.kill)
		Game.on_enemy_killed(kind, xp_reward(), level, area)
		drop_loot(get_parent(), kind, global_position, true, level, elite, is_boss)
	die_visual()


## XP do abate: a do tipo pela curva do nível (sem nível, a de hoje).
func xp_reward() -> int:
	return roundi(float(data.xp) * float(ProgressionRules.enemy_mults(Balance.tables, kind, level).xp))


## Morte sem regras de jogo (também usada pelas réplicas no cliente).
func die_visual() -> void:
	dead = true
	state = "dead"
	remove_from_group("enemies")
	collision_layer = 0
	collision_mask = 1
	_set_overlay(null)
	if bar_root:
		bar_root.visible = false
	if name_tag:
		name_tag.visible = false
		quest_icon.visible = false
	Sfx.play_at("slime" if data.model == "slime" else "enemy_die", global_position, 0.1, -4.0 if horde else 0.0)
	if data.has("death_blast"):
		_death_blast()
	died.emit(self)
	# acende azul e se desfaz em cacos (FXShatter); o nó sai assim que o modelo some
	FXShatter.play(self, model, meshes, model.scale.x, is_boss, queue_free)


## Golem de Cristal: ao morrer, aviso no chão e, `death_delay` s depois, os estilhaços estouram em `death_blast` m.
## Só quem manda no monstro (servidor ou solo) aplica o dano; a réplica mostra o aviso e o estouro. Não depende
## deste nó (que some no FXShatter): o timer leva só valores copiados.
func _death_blast() -> void:
	var pos := global_position
	var r := float(data.death_blast)
	var delay := float(data.get("death_delay", 0.8))
	var deal := not puppet
	var lvl := level
	var dmg: float = data.damage * dmg_mult
	var parent := get_parent()
	var tree := get_tree()
	FX.telegraph(pos, r, delay)
	if deal:
		print("death_blast ", kind)
	tree.create_timer(delay).timeout.connect(func() -> void:
		Sfx.play_at("explode", pos, 0.1, -2.0)
		FXToon.blast(pos, r)
		if not deal or not is_instance_valid(parent):
			return
		var pool: Array = parent.targets() if parent.has_method("targets") else tree.get_nodes_in_group("players")
		for p in pool:
			if is_instance_valid(p) and not p.dead and p.global_position.distance_to(pos) <= r:
				p.take_damage(Enemy.vs(lvl, p, dmg), pos)
				p.add_shake(0.3))


## Solo: sorteio do loot (LootRules, o mesmo do servidor) em pickups no chão.
static func drop_loot(parent: Node, enemy_kind: String, pos: Vector3, with_gold := true, level := 0, elite := false,
		boss := false) -> void:
	boss = boss or TYPES.get(enemy_kind, {}).get("boss", false)
	var extra := DungeonRules.extra_loot(Balance.tables, Regions.region_at(pos), boss)
	var loot := LootRules.roll(Balance.tables, enemy_kind, _loot_rng(), Game.char_class, level, elite, extra)
	_spawn_loot(parent, pos, int(loot.gold) if with_gold else 0, loot.items)


static func _spawn_loot(parent: Node, pos: Vector3, gold: int, items: Dictionary) -> void:
	if gold > 0:
		PICKUP.spawn(parent, "", gold, pos + Vector3.UP * 0.8)
	for id in items:
		for i in int(items[id]):
			PICKUP.spawn(parent, id, 1, pos + Vector3.UP * 0.8)


static var _rng: RandomNumberGenerator = null


static func _loot_rng() -> RandomNumberGenerator:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	return _rng


# ------------------------------------------------------------ réplica (cliente)
func set_net_target(pos: Vector3, yaw: float) -> void:
	_net_pos = pos
	_net_yaw = yaw


func apply_snapshot(pos: Vector3, yaw: float, new_hp: float, new_state: String, atk_t: float, atk_kind: String, flags: int) -> void:
	_net_pos = pos
	_net_yaw = yaw
	if new_hp != hp:
		if new_hp < hp - 0.5 and _flash_t <= 0.0:
			_flash_t = 0.06
		hp = new_hp
		health_changed.emit(self)
	slow_timer = 0.25 if flags & 1 else 0.0
	var now_enraged := flags & 2 != 0
	if now_enraged and not enraged and (not horde or get_tree().current_scene.get("survival") != null):
		Game.notify.emit("%s está enfurecido!" % data.name, Color(1, 0.4, 0.3))
	enraged = now_enraged
	if ai() == "worm":
		_set_fury_look(enraged)
		if new_state == "burrow" and new_hp >= max_hp:
			_intro_shown = false   # voltou para casa cheia: a próxima luta tem entrada de novo
	if new_state == "attack":
		if state != "attack":
			attack_kind = atk_kind
			attack_timer = atk_t
			hit_done = atk_t >= _hit_time()
			if attack_kind == "slam":
				FX.telegraph(global_position, _slam_radius(), 0.9)
			elif attack_kind == "fuse":
				FX.telegraph(global_position, data.blast, maxf(0.2, _hit_time() - atk_t))
			elif attack_kind == "throw":
				_replica_throw(flags, atk_t)
			elif attack_kind == "emerge":
				FX.telegraph(_net_pos, float(data.emerge_radius), maxf(0.2, _hit_time() - atk_t))
			elif attack_kind in ["quake", "rockfall", "acid_rain"]:
				_replica_boss_start(flags, atk_t)
		elif atk_t < attack_timer - 0.3:
			# um novo ataque começou entre dois snapshots
			attack_kind = atk_kind
			attack_timer = atk_t
			hit_done = atk_t >= _hit_time()
			if attack_kind == "throw":
				_replica_throw(flags, atk_t)
			elif attack_kind in ["quake", "rockfall", "acid_rain"]:
				_replica_boss_start(flags, atk_t)
	if new_state != state:
		_set_state(new_state)
	if ai() in ["burrow", "worm"]:
		# réplica que chega no meio do "emergir", já depois do golpe, aparece na hora (o servidor já a mostra)
		_set_buried(BurrowRules.hidden(state, attack_kind, hit_done))


## Réplica: o ponto da dinamite = posição do snapshot + o deslocamento que vem nos bits altos de flags.
func _replica_throw(flags: int, atk_t: float) -> void:
	throw_point = _net_pos + ThrowRules.unpack_offset(flags)
	if atk_t < _hit_time():
		FX.telegraph(throw_point, data.blast, maxf(0.2, _hit_time() - atk_t))


func show_hit(amount: float, crit: bool) -> void:
	if dead:
		return
	var top: Vector3 = global_position + Vector3.UP * (data.height * data.scale + 0.2)
	FX.damage_number(top, ("%d!" if crit else "%d") % int(round(amount)),
		Color(1, 0.85, 0.2) if crit else Color.WHITE, 64 if crit else 48)
	FXToon.hit_splat(global_position + Vector3.UP * data.height * data.scale * 0.5, data.color, 5)
	_flash_t = 0.1
	if bar_root:
		bar_root.visible = true


func _puppet_process(delta: float) -> void:
	if dead:
		return
	_update_flash(delta)
	if _horde_frozen():
		return
	var prev := global_position
	if global_position.distance_to(_net_pos) > 6.0:
		global_position = _net_pos
	else:
		global_position = global_position.lerp(_net_pos, 1.0 - exp(-12.0 * delta))
	model.rotation.y = lerp_angle(model.rotation.y, _net_yaw, 1.0 - exp(-12.0 * delta))
	if state == "attack":
		var before := attack_timer
		attack_timer += delta
		_update_dynamite()
		_boss_tick(true, before, attack_timer)
		if not hit_done and before < _hit_time() and attack_timer >= _hit_time():
			hit_done = true
			if attack_kind == "slam":
				Sfx.play_at("slam", global_position, 0.0)
				FXToon.slam(global_position, _slam_radius())
			elif attack_kind == "shoot":
				_shoot(true)
			elif attack_kind == "web":
				_shoot_web(true)
			elif attack_kind == "tongue":
				Sfx.play_at("slime", global_position, 0.2, -2.0)
			elif attack_kind == "cast":
				_cast_heal(true)
			elif attack_kind == "fuse":
				_explode(true)
			elif attack_kind == "throw":
				_dynamite_blast(true)
			elif attack_kind == "emerge":
				_emerge_hit(true)
			elif attack_kind == "rockfall":
				_rockfall_hit(true)
			elif attack_kind == "acid_rain":
				_acid_hit(true)
			elif attack_kind == "swing":
				Sfx.play_at("swing", global_position, 0.15, -4.0)
	var hspeed := Vector2(global_position.x - prev.x, global_position.z - prev.z).length() / maxf(delta, 0.0001)
	_animate(delta, hspeed)
	if bar_root and bar_root.visible:
		bar_fg.scale.x = max(0.001, hp / max_hp)


# ------------------------------------------------------------ animação procedural
func _animate(delta: float, hspeed: float) -> void:
	anim_t += delta * (3.0 + hspeed * 2.0)
	var s := sin(anim_t)
	var k := 1.0 - exp(-12.0 * delta)
	if data.model == "slime":
		var body: Node3D = parts.Body
		var sq := 1.0 + s * 0.12
		var target := Vector3(1.0 / sqrt(sq), sq, 1.0 / sqrt(sq))
		if state == "attack":
			var t := attack_timer
			if t < 0.3:
				target = Vector3(1.3, 0.6, 1.3)
			elif t < 0.6:
				target = Vector3(0.8, 1.4, 0.8)
		body.scale = body.scale.lerp(target, k)
		return
	if data.model == "raptor":
		_animate_raptor(hspeed, s, k)
		return
	if data.model in ["spider", "centipede"]:
		_animate_spider(hspeed, k)
		return
	if data.model == "plant":
		_animate_plant(k)
		return
	if data.model == "frog":
		_animate_frog(hspeed, k)
		return
	if data.model == "bat":
		_animate_bat(hspeed, k)
		return
	if data.model == "golem":
		_animate_golem(hspeed, s, k)
		return
	if data.model == "mole":
		_animate_mole(delta, hspeed, s, k)
		return
	if data.model == "worm":
		_animate_worm(k)
		return
	var amp: float = clamp(hspeed / 4.0, 0.0, 1.0) * 0.8
	var at := attack_timer
	var ht := _hit_time()
	var kk := k if not (state == "attack" and at >= ht and at < ht + 0.12) else 1.0 - exp(-40.0 * delta)
	EnemyPose.humanoid(parts, _rig, {"state": state, "kind": attack_kind, "t": at, "ht": ht,
		"dur": _attack_duration(), "amp": amp, "s": s, "weapon": weapon}, k, kk)


## Raptor: passada de ave (pernas longas, corpo balançando pouco), cauda que serpenteia e bote com a boca aberta.
## Pivôs: rotação x positiva abaixa a frente (cabeça, mandíbula) e leva a perna para trás.
func _animate_raptor(hspeed: float, s: float, k: float) -> void:
	var amp: float = clamp(hspeed / 5.0, 0.0, 1.0) * 0.75
	var leg_l := s * amp
	var leg_r := -s * amp
	var body_x := -absf(cos(anim_t)) * amp * 0.08
	var head_x := sin(anim_t * 2.0) * amp * 0.1
	var jaw := 0.04 + maxf(0.0, sin(anim_t * 0.37)) * 0.12 * (1.0 - amp)   # respira de boca entreaberta parado
	if state == "attack" and attack_kind == "lunge":
		var t := attack_timer
		if t < 0.35:          # arma o bote: agacha, levanta a cabeça e abre a boca
			body_x = 0.12
			head_x = -0.35
			jaw = 0.75
			leg_l = -0.35
			leg_r = 0.25
		elif t < 0.6:         # salta para a frente e fecha a boca na hora do acerto
			body_x = -0.2
			head_x = 0.3
			jaw = 0.0 if t >= _hit_time() else 0.8
			leg_l = 0.7
			leg_r = -0.6
		else:
			body_x = 0.05
			head_x = 0.1
			jaw = 0.15
	var snap := 1.0 - exp(-40.0 * get_physics_process_delta_time())
	parts.LegL.rotation.x = lerp(parts.LegL.rotation.x, leg_l, k)
	parts.LegR.rotation.x = lerp(parts.LegR.rotation.x, leg_r, k)
	parts.Body.rotation.x = lerp(parts.Body.rotation.x, body_x, k)
	parts.Head.rotation.x = lerp(parts.Head.rotation.x, head_x, k)
	parts.ArmL.rotation.x = lerp(parts.ArmL.rotation.x, s * 0.15, k)
	parts.ArmR.rotation.x = lerp(parts.ArmR.rotation.x, -s * 0.15, k)
	if parts.Jaw:
		parts.Jaw.rotation.x = lerp(parts.Jaw.rotation.x, jaw, snap if jaw == 0.0 else k)
	if parts.Tail:
		parts.Tail.rotation.y = sin(anim_t * 0.5) * (0.12 + amp * 0.15)
		parts.Tail.rotation.x = -body_x * 0.8


## Tecelã: oito patas em dois grupos alternados (1 e 3 de um lado com 2 e 4 do outro), cada pata varrendo e
## levantando na sua vez; o abdômen respira. No bote ergue a frente com as patas dianteiras e desce mordendo;
## na teia ergue a frente e cospe. Pivôs das pernas no quadril: y varre para a frente e para trás, z levanta.
func _animate_spider(hspeed: float, k: float) -> void:
	var amp: float = clamp(hspeed / 4.0, 0.0, 1.0)
	var walk := anim_t * 1.7
	var body_x := 0.0
	var head_x := 0.0
	var front_lift := 0.0
	if state == "attack" and (attack_kind == "lunge" or attack_kind == "web"):
		var t := attack_timer
		if t < _hit_time():          # arma: frente para cima, patas da frente no ar, quelíceras abertas
			body_x = -0.28
			head_x = -0.45
			front_lift = 0.7
		elif t < _hit_time() + 0.25:  # morde (ou cospe) descendo a frente
			body_x = 0.18 if attack_kind == "lunge" else -0.1
			head_x = 0.35
			front_lift = 0.15
	for i in 4:
		for side in 2:
			var leg: Node3D = parts.get("Leg%d%s" % [i, "L" if side == 0 else "R"])
			if leg == null:
				continue
			var sgn := 1.0 if side == 0 else -1.0
			var ph := walk + (PI if (i + side) % 2 == 1 else 0.0)
			var swing := sin(ph) * 0.32 * amp + sin(anim_t * 0.6 + i) * 0.03 * (1.0 - amp)
			var lift := maxf(0.0, cos(ph)) * 0.3 * amp
			if i == 0:
				lift = maxf(lift, front_lift)
			leg.rotation.y = lerp(leg.rotation.y, swing * sgn, k)
			leg.rotation.z = lerp(leg.rotation.z, lift * sgn, k)
	parts.Body.rotation.x = lerp(parts.Body.rotation.x, body_x + sin(walk * 2.0) * 0.03 * amp, k)
	if parts.Head:
		parts.Head.rotation.x = lerp(parts.Head.rotation.x, head_x, k)
	var abd: Node3D = parts.get("Abdomen")
	if abd:
		var br := 1.0 + sin(anim_t * 0.8) * 0.035
		abd.scale = abd.scale.lerp(Vector3(br, br, br), k)
		abd.rotation.x = lerp(abd.rotation.x, 0.12 if attack_kind == "web" and state == "attack" else 0.0, k)


## Golem de Cristal: passada pesada balançando o tronco de lado, braços pendulares; golpe comum = soco do braço
## direito; pancada (slam) = ergue os dois punhos acima da cabeça e bate no chão no _hit_time.
## Pivôs: rotação x positiva leva perna/braço para trás (negativa ergue para a frente).
func _animate_golem(hspeed: float, s: float, k: float) -> void:
	var amp: float = clamp(hspeed / 2.5, 0.0, 1.0)
	var leg := s * 0.4 * amp
	var arm_l := -s * 0.25 * amp
	var arm_r := s * 0.25 * amp
	var body_x := 0.06 + sin(anim_t * 0.4) * 0.02 * (1.0 - amp)   # curvado, respirando parado
	var body_z := sin(anim_t) * 0.07 * amp
	if state == "attack":
		var t := attack_timer
		var ht := _hit_time()
		if attack_kind == "slam":
			if t < ht:
				var u := clampf(t / ht, 0.0, 1.0)
				arm_l = lerpf(-0.3, -2.7, u)
				arm_r = arm_l
				body_x = lerpf(0.06, -0.2, u)
			elif t < ht + 0.4:
				arm_l = -0.7
				arm_r = -0.7
				body_x = 0.35
		elif attack_kind == "swing":
			if t < ht:
				arm_r = lerpf(0.0, -1.9, clampf(t / ht, 0.0, 1.0))
				body_z = -0.08
			elif t < ht + 0.3:
				arm_r = -0.5
				body_x = 0.2
				body_z = 0.1
	parts.LegL.rotation.x = lerp(parts.LegL.rotation.x, leg, k)
	parts.LegR.rotation.x = lerp(parts.LegR.rotation.x, -leg, k)
	parts.ArmL.rotation.x = lerp(parts.ArmL.rotation.x, arm_l, k)
	parts.ArmR.rotation.x = lerp(parts.ArmR.rotation.x, arm_r, k)
	parts.Body.rotation.x = lerp(parts.Body.rotation.x, body_x, k)
	parts.Body.rotation.z = lerp(parts.Body.rotation.z, body_z, k)


## Toupeira-Broca, em dois ossos por membro: braço (ArmL/ArmR) + antebraço (ElbowL/ElbowR), coxa (LegL/LegR) +
## canela (KneeL/KneeR). Anda curvada, o joelho dobra quando a perna volta e os antebraços balançam soltos; a broca
## gira sempre (mais rápido no ataque). Golpe comum = arma a garra no alto (cotovelo dobrado) e rasga para baixo
## esticando o antebraço; emergir = sai com os dois braços para cima. Enterrada, só o monte de terra anda.
## Rotação x: positiva leva braço/perna/canela para trás; negativa no cotovelo dobra o antebraço para cima.
func _animate_mole(delta: float, hspeed: float, s: float, k: float) -> void:
	if _dirt and _dirt.visible:
		var w := 1.0 + sin(anim_t * 3.0) * 0.08
		_dirt.scale = Vector3(w, 1.0 / w, w)
		_dust_t -= delta
		if _dust_t <= 0.0:   # terra espirrando enquanto o monte anda
			_dust_t = 0.18
			FX.burst(global_position + Vector3.UP * 0.3, Color(0.45, 0.33, 0.22), 5, 2.2, 0.12, 0.5)
	var amp: float = clamp(hspeed / 3.5, 0.0, 1.0)
	var idle := 1.0 - amp
	var leg := s * 0.5 * amp
	var c := cos(anim_t)
	# o joelho dobra enquanto a perna volta para a frente (fase de cada lado), parado fica levemente dobrado
	var knee_l := maxf(0.0, c) * 0.8 * amp + 0.08
	var knee_r := maxf(0.0, -c) * 0.8 * amp + 0.08
	var arm_l := -s * 0.35 * amp - 0.2
	var arm_r := s * 0.35 * amp - 0.2
	# antebraços soltos: seguem o balanço do braço com atraso e respiram parados
	var elb_l := -0.35 - c * 0.25 * amp - sin(anim_t * 0.6) * 0.06 * idle
	var elb_r := -0.35 + c * 0.25 * amp - sin(anim_t * 0.6 + 1.0) * 0.06 * idle
	var body_x := 0.08 + sin(anim_t * 0.5) * 0.03 * idle
	var body_y := s * 0.08 * amp
	var head_x := sin(anim_t * 0.7) * 0.05 * idle
	var spin := 10.0
	if state == "attack":
		var t := attack_timer
		var ht := _hit_time()
		spin = 30.0
		if attack_kind == "emerge":
			if t >= ht and t < ht + 0.5:
				arm_l = -2.3
				arm_r = -2.3
				elb_l = -0.8
				elb_r = -0.8
				body_x = -0.25
				head_x = -0.3
		elif t < ht:      # arma: braço para cima, garra erguida com o cotovelo bem dobrado, corpo torcido
			var u := clampf(t / ht, 0.0, 1.0)
			arm_r = lerpf(-0.2, -1.5, u)
			elb_r = lerpf(-0.35, -1.5, u)
			elb_l = -0.6
			body_y = 0.25 * u
			head_x = -0.2
		elif t < ht + 0.3:   # rasga para baixo: o braço desce e o antebraço estica
			arm_r = -0.5
			elb_r = -0.05
			arm_l = -1.0
			elb_l = -0.9
			body_x = 0.25
			body_y = -0.2
	parts.LegL.rotation.x = lerp(parts.LegL.rotation.x, leg, k)
	parts.LegR.rotation.x = lerp(parts.LegR.rotation.x, -leg, k)
	parts.ArmL.rotation.x = lerp(parts.ArmL.rotation.x, arm_l, k)
	parts.ArmR.rotation.x = lerp(parts.ArmR.rotation.x, arm_r, k)
	for pair in [["KneeL", knee_l], ["KneeR", knee_r], ["ElbowL", elb_l], ["ElbowR", elb_r]]:
		var j: Node3D = parts.get(pair[0])
		if j:
			j.rotation.x = lerp(j.rotation.x, float(pair[1]), k)
	parts.Body.rotation.x = lerp(parts.Body.rotation.x, body_x, k)
	parts.Body.rotation.y = lerp(parts.Body.rotation.y, body_y, k)
	if parts.Head:
		parts.Head.rotation.x = lerp(parts.Head.rotation.x, head_x, k)
	if parts.Drill:
		parts.Drill.rotation.z += spin * delta


## Mãe-Verme: o corpo balança devagar, o pescoço (segundo osso) ondula e a boca respira (pétalas no Jaw, por
## escala). Mordida = recua o pescoço com a boca aberta e desce de uma vez; cuspe = ergue a cabeça e escancara;
## emergir = o corpo sobe do chão no golpe. Rotação x positiva leva o topo para a frente.
func _animate_worm(k: float) -> void:
	var neck: Node3D = parts.get("Neck")
	var neck_x := sin(anim_t * 0.6) * 0.07
	var neck_z := sin(anim_t * 0.45) * 0.09
	var body_z := sin(anim_t * 0.3 + 1.0) * 0.03
	var head_x := sin(anim_t * 0.8 + 1.0) * 0.08
	var jaw := 1.0 + sin(anim_t * 1.3) * 0.06
	var rise := 0.0
	if state == "attack":
		var t := attack_timer
		var ht := _hit_time()
		var u := clampf(t / ht, 0.0, 1.0)
		match attack_kind:
			"slam":
				if t < ht:
					neck_x = lerpf(0.0, -0.4, u)
					head_x = -0.3
					jaw = lerpf(1.0, 1.35, u)
				elif t < ht + 0.35:
					neck_x = 0.6
					head_x = 0.4
					jaw = 0.8
			"shoot":
				if t < ht:
					head_x = lerpf(0.0, -0.35, u)
					jaw = lerpf(1.0, 1.4, u)
				elif t < ht + 0.3:
					neck_x = 0.2
					head_x = 0.2
					jaw = 1.2
			"emerge":
				if t >= ht:
					rise = clampf((t - ht) / 0.35, 0.0, 1.0)
					jaw = 1.4
				else:
					rise = 0.0
			"quake":   # ergue-se toda e bate o corpo no chão; fica baixa enquanto os anéis abrem
				if t < ht:
					neck_x = lerpf(0.0, -0.5, u)
					head_x = -0.4
					jaw = 1.3
				else:
					neck_x = 0.75
					head_x = 0.5
					jaw = 0.85
					body_z = sin(t * 25.0) * 0.04
			"rockfall":   # rugido: cabeça para o teto, boca escancarada, tremendo
				neck_x = -0.3
				head_x = -0.7
				jaw = 1.55
				body_z = sin(t * 30.0) * 0.05
			"acid_rain":
				if t < ht:
					head_x = lerpf(0.0, -0.5, u)
					jaw = lerpf(1.0, 1.5, u)
				else:
					neck_x = 0.25
					head_x = 0.25
					jaw = 1.2
	if state == "attack" and attack_kind == "emerge":
		parts.Body.position.y = lerpf(-4.0, 0.0, rise)
	else:
		parts.Body.position.y = lerp(parts.Body.position.y, 0.0, k)
	parts.Body.rotation.z = lerp(parts.Body.rotation.z, body_z, k)
	if neck:
		neck.rotation.x = lerp(neck.rotation.x, neck_x, k)
		neck.rotation.z = lerp(neck.rotation.z, neck_z, k)
	if parts.Head:
		parts.Head.rotation.x = lerp(parts.Head.rotation.x, head_x, k)
	if parts.Jaw:
		parts.Jaw.scale = parts.Jaw.scale.lerp(Vector3(jaw, jaw, jaw), k)


## Flor-faminta: balança devagar com a boca entreaberta; ao ver alguém perto abre a boca; no bote estica o caule e
## fecha a boca; na pancada (slam) os cipós varrem o chão em volta.
func _animate_plant(k: float) -> void:
	var sway := sin(anim_t * 0.5) * 0.06
	var open := 0.12 + maxf(0.0, sin(anim_t * 0.9)) * 0.08
	var body_x := sway
	var vine := sin(anim_t * 0.7) * 0.15
	if state == "chase":
		open = 0.45
		body_x = -0.12
	if state == "attack":
		var t := attack_timer
		var ht := _hit_time()
		if attack_kind == "slam":
			vine = -1.1 if t < ht else 0.9
			open = 0.6
			body_x = -0.2
		elif t < ht:
			open = 0.8
			body_x = -0.35
		elif t < ht + 0.3:
			open = 0.0
			body_x = 0.45
	parts.Body.rotation.x = lerp(parts.Body.rotation.x, body_x, k)
	if parts.Head:
		parts.Head.rotation.x = lerp(parts.Head.rotation.x, -open * 0.6, k)
	if parts.Jaw:
		parts.Jaw.rotation.x = lerp(parts.Jaw.rotation.x, open * 0.45, k)
	if parts.VineL:
		parts.VineL.rotation.y = lerp(parts.VineL.rotation.y, vine, k)
	if parts.VineR:
		parts.VineR.rotation.y = lerp(parts.VineR.rotation.y, -vine, k)


## Bocarrão: anda aos pulinhos (o corpo sobe e desce com as patas de trás), o papo pulsa parado; a língua
## estica até o jogador no ataque e volta; no bote abre a boca inteira.
func _animate_frog(hspeed: float, k: float) -> void:
	var amp: float = clamp(hspeed / 2.5, 0.0, 1.0)
	var hop := absf(sin(anim_t * 1.2)) * amp
	var jaw := 0.03 + maxf(0.0, sin(anim_t * 1.6)) * 0.04 * (1.0 - amp)
	var body_x := -hop * 0.12
	var stretch := 1.0
	if state == "attack":
		var t := attack_timer
		var ht := _hit_time()
		if attack_kind == "tongue":
			jaw = 0.5
			if t >= ht - 0.15 and t < ht + 0.3:   # sai, alcança e volta
				var reach := tongue_len if tongue_len > 0.0 else float(data.get("tongue_range", 7.0)) * 0.7
				var f := 1.0 - absf((t - (ht + 0.075)) / 0.225)
				stretch = 1.0 + maxf(0.0, f) * reach / 0.6
		elif t < ht:
			jaw = 0.7
			body_x = -0.25
		elif t < ht + 0.25:
			jaw = 0.0
			body_x = 0.2
	parts.Body.rotation.x = lerp(parts.Body.rotation.x, body_x, k)
	parts.Body.position.y = lerp(parts.Body.position.y, 0.4 + hop * 0.18, k)
	if parts.Jaw:
		parts.Jaw.rotation.x = lerp(parts.Jaw.rotation.x, jaw, k)
	if parts.Tongue:
		parts.Tongue.scale.z = stretch
	for n in ["LegL", "LegR"]:
		if parts[n]:
			parts[n].rotation.x = lerp(parts[n].rotation.x, -hop * 0.5, k)
	for n in ["ArmL", "ArmR"]:
		if parts[n]:
			parts[n].rotation.x = lerp(parts[n].rotation.x, hop * 0.3, k)


## Asa-couro: bate as asas sem parar (mais rápido voando), o corpo sobe e desce no ritmo; no rasante desce até
## a altura do jogador com as asas abertas para trás e sobe de volta.
func _animate_bat(hspeed: float, k: float) -> void:
	var beat := anim_t * 2.2
	var flap := sin(beat) * (0.55 + clampf(hspeed / 5.0, 0.0, 1.0) * 0.2)
	var y := sin(beat - 0.6) * 0.08
	var body_x := 0.0
	if state == "attack" and attack_kind == "lunge":
		var t := attack_timer
		var ht := _hit_time()
		if t < ht + 0.15:
			var f := clampf(t / maxf(ht, 0.01), 0.0, 1.0)
			y = -0.75 * f
			body_x = 0.35 * f
			flap = -0.5
		else:
			y = -0.3
			body_x = -0.2
	parts.Body.position.y = lerp(parts.Body.position.y, 1.5 + y, k)
	parts.Body.rotation.x = lerp(parts.Body.rotation.x, body_x, k)
	if parts.WingL:
		parts.WingL.rotation.z = flap
	if parts.WingR:
		parts.WingR.rotation.z = -flap
	if parts.Head:
		parts.Head.rotation.x = lerp(parts.Head.rotation.x, -body_x * 0.5, k)
