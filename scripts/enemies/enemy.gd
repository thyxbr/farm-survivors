class_name Enemy
extends CharacterBody3D
## Inimigo genérico (slime, goblin, rei goblin) com IA simples de estados.

signal died(enemy: Enemy)
signal health_changed(enemy: Enemy)

const PICKUP := preload("res://scripts/world/pickup.gd")
const ENEMY_ARROW := preload("res://scripts/enemies/enemy_arrow.gd")
const PROVOKE_TIME := 4.0   # ver `provoked`
## Bit do snapshot de rede: provocado (olhos vermelhos nas réplicas). Acima dos bits que ThrowRules e BossRules
## usam (2..17); o snapshot é float32, exato até 2^24.
const TAUNT_FLAG := 1 << 20
const TAUNT_INDICATOR := preload("res://scenes/vfx/dark_taunt/taunt_indicator.tscn")
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
## Nome, ícone de missão e barra de vida ficam juntos neste nó; some quando a câmera não vê o monstro (parede
## ou morro no meio), já que as placas desenham por cima de tudo (no_depth_test).
var _plates: Node3D
var _occ_t := 0.0
const OCCLUDE_CHECK := 0.2
const OCCLUDE_MASK := 1   # camada "world"
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
## Sala do chefe de dungeon (x, z do mundo; vazio = sem arena): o chefe só enxerga quem está dentro dela, persegue
## qualquer um lá dentro e, quando todos saem, perde o agro, volta para casa e se cura.
var arena := Rect2()
## Até quantos metros de casa persegue antes de desistir e voltar (na dungeon é curto: andar pelos corredores não
## junta um trem de monstros atrás do jogador).
var leash := 45.0
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
## Status elementais (queimadura, veneno, lentidão de gelo, congelamento): StatusEffects, filho do inimigo.
## O dono roda os pulsos; a réplica só recebe o bitmask pelo snapshot.
var status: StatusEffects
## Efeito do status no corpo (contorno + partículas). Só onde há tela: o servidor não monta.
var status_aura: StatusAura = null
## Dano sem impacto (pulso de status): não faz recuar nem cancela o ataque (take_damage).
var no_flinch := false
var stagger := 0.0
## Segundos em que o inimigo segue perseguindo depois de levar dano, mesmo com o jogador longe.
## Sem isso, um acerto de longe (ou, no servidor, antes de chegar a posição nova do jogador)
## fazia o inimigo desistir na hora, voltar para casa e curar a vida toda, apagando o dano.
var provoked := 0.0
## Círculo da Provocação Sombria (DarkTauntAbilities): enquanto taunt_t > 0 o único alvo é `taunt_by` (o herói que
## provocou): _nearest_player() devolve ele, então a perseguição, a mira e os golpes de sempre vão para ele. Enquanto
## held_t > 0 as mãos sombrias seguram: não anda nem começa golpe. Estado do dono do inimigo (servidor ou solo); as
## réplicas pedem por apply_taunt e só mostram os olhos (bit TAUNT_FLAG do snapshot).
var taunt_t := 0.0
var taunt_by: Node3D = null
var held_t := 0.0
## Olhos vermelhos sobre a cabeça enquanto provocado (TauntIndicator; criado na primeira vez, sem servidor dedicado).
var taunt_eyes: Node3D = null
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
var _flash_mat: Material   ## camada do clarão no lugar da branca (flash_with), até o clarão acabar

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
## Alfa da Matilha: segundos de pressa que o uivo deu a este lobo (anda HOWL_HASTE vezes mais rápido).
var haste_t := 0.0
const HOWL_HASTE := 1.35
const WOLF_SIDES := ["FL", "FR", "BL", "BR"]
## Lobo: o repouso de cada pata no espaço do modelo (quadril, joelho, tornozelo e apoio, no plano y/z) e o ciclo
## do trote; Gralha: o ciclo da batida de asa. Ver _animate_wolf e _animate_crow.
var _wolf_rest := {}
var _leech_rest := {}   # Sanguessuga: posições de repouso do corpo e da cabeça (lidas no primeiro quadro)
var _toad_rest := {}    # Sapo-Bufo: posição de repouso de cada pivô (lida no primeiro quadro)
var _gait_ph := 0.0
var _gait_amp := 0.0
var _crow_ph := 0.0
## Relógio da animação (soma o delta de _animate): o ciclo parado (respirar, abanar a cauda) segue o mesmo tempo
## no jogo e no laboratório (tools/monster_lab.tscn).
var _life_t := 0.0
## Toupeira-Broca (ai "burrow"): segundos debaixo da terra, segundos na superfície desde que saiu, o monte de
## terra que anda por cima dela e a camada de colisão normal (zerada enquanto está enterrada).
var dig_t := 0.0
var surface_t := 0.0
var _dirt: MeshInstance3D = null
var _layer := 4
var _dust_t := 0.0
## Mãe-Verme (ai "worm"): ataques feitos desde que saiu do chão e o relógio da conferência do fosso.
var worm_hits := 0
## Espinheira (ai "thorn"): golpes dados na luta, a origem e as direções das Raízes da vez, quem elas já pegaram,
## os pontos das Nuvens de Esporos e o relógio da cura dos Brotos (e do galho que liga cada broto a ela).
var _thorn_n := 0
var _root_origin := Vector3.ZERO
var _root_dirs: Array = []
var _root_hit := {}
var _spore_pts: Array = []
var _thorn_t := 0.0
## Sentinela da Nevasca (ai "blizzard"): a luta montada (sala, chão, pontos e nós dos braseiros, relógios de
## reacender e os acesos), golpes e sopros já dados, o urro da nevasca pendente/dado, a nevasca soprando, a
## exposição de cada jogador (e a do jogador desta tela, só para o desenho), os relógios, a entrada já mostrada, a
## neve da sala, o sopro em curso (yaw inicial, sentido, o aviso no chão), os pontos das estacas e o da patada.
var _blz_ready := false
var _blz_room := Rect2()
var _blz_floor := 0.0
var _blz_pts: Array = []
var _blz_braziers: Array = []
var _blz_relight: Array = []
var _blz_mask := BlizzardRules.MASK_ALL
var _blz_n := 0
var _blz_breaths := 0
var _blz_roar := false
var _blz_roared := false
var _blz_storm := false
var _blz_exposure := {}
var _blz_local := 0.0
var _blz_tick := 0.0
var _blz_gust_t := 0.0
var _blz_intro := false
var _blz_snow: CPUParticles3D = null
var _breath_start := 0.0
var _breath_sign := 1.0
var _breath_cone: BlizzardFX.ConeWarning = null
var _breath_fx_t := 0.0
var _spike_pts: Array = []
var _paw_at := Vector3.ZERO
var _leash_t := 0.0
## Arauto do Abismo (ai "herald"): a fase, golpes dados nela, de onde e para onde vai o golpe da vez, os pontos
## das Zonas de Vazio ou da Miragem e, na cópia, os segundos de vida.
var _abyss_phase := 1
var _abyss_n := 0
var _abyss_origin := Vector3.ZERO
var _abyss_dir := Vector3.FORWARD
var _abyss_pts: Array = []
var _abyss_t := 0.0
## Forjador Rúnico (ai "forge"): golpes dados na luta, a origem e a direção da Martelada da vez, o Escudo Rúnico
## (de pé, quantos já ergueu, há quanto tempo o último caiu, o desenho dele) e os relógios.
var _forge_n := 0
var _forge_origin := Vector3.ZERO
var _forge_dir := Vector3.BACK
var shielded := false
var _forge_shields := 0
var _forge_since := 0.0
var _forge_ward: Node3D = null
var _forge_t := 0.0
var _forge_immune_t := 0.0
## Afinidade elemental: tempo até a próxima dica (Fraco!/Resistiu/Imune) sobre o número de dano.
const HINT_GAP := 0.6
var _hint_t := 0.0
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
	status = StatusEffects.new(self)
	add_child(status)
	if not horde and not puppet:
		sleep_radius = float(Balance.tables.get_table("rules").get("enemy_sleep_radius", 0.0))
		_sleep_t = randf() * SLEEP_CHECK   # espalha as conferências pelos quadros
	_far_t = randf() * SLEEP_CHECK
	_occ_t = randf() * OCCLUDE_CHECK
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
	if not model.find_children("*", "Skeleton3D", true, false).is_empty():
		PivotSkin.ensure(model)    # malha com pele (monstro gerado por IA): os ossos seguem os pivôs animados
	if elite:
		_make_elite_glow()
	for n in ["LegL", "LegR", "ArmL", "ArmR", "Body", "Head", "Tail", "Jaw", "Drill"]:   # Tail e Jaw: raptor e lobo; Drill: toupeira
		parts[n] = model.find_child(n, true, false)
	if data.model == "leech":   # Sanguessuga do Lodo: cadeia Head < Body > Tail > Tail2 > Tail3
		for n in ["Tail2", "Tail3"]:
			parts[n] = model.find_child(n, true, false)
	if data.model == "toad":   # Sapo-Bufo: mão e pé (apoio no chão) abaixo das patas
		for n in ["HandL", "HandR", "FootL", "FootR"]:
			parts[n] = model.find_child(n, true, false)
	if data.model in ["wolf", "turtle"]:   # Lobo e Tartaruga-Musgo: quatro patas em três ossos (Leg > Knee > Paw) e o apoio (Foot)
		for sd in WOLF_SIDES:
			for b in ["Leg", "Knee", "Paw", "Foot"]:
				parts[b + sd] = model.find_child(b + sd, true, false)
		parts["Tail2"] = model.find_child("Tail2", true, false)
	if data.model == "crow":   # Gralha: asa em três ossos (ombro, cotovelo, punho) e a cauda
		for n in ["WingL2", "WingL3", "WingR2", "WingR3"]:
			parts[n] = model.find_child(n, true, false)
	if data.model == "yeti":   # Ieti: cotovelos
		for n in ["ElbowL", "ElbowR"]:
			parts[n] = model.find_child(n, true, false)
	if data.model == "worm":   # Mãe-Verme: o segundo osso do corpo
		parts["Neck"] = model.find_child("Neck", true, false)
	if data.model == "mole":   # Toupeira: o segundo osso de cada membro (cotovelo e joelho)
		for n in ["ElbowL", "ElbowR", "KneeL", "KneeR"]:
			parts[n] = model.find_child(n, true, false)
	if data.model == "thorn_tree":   # Espinheira: cotovelos, joelhos, mãos, a copa, os galhos dos lados e os cipós
		for n in ["ElbowL", "ElbowR", "KneeL", "KneeR", "HandL", "HandR", "Crown", "BoughL", "BoughR", "Hang0", "Hang1",
				"Hang2", "Hang3"]:
			parts[n] = model.find_child(n, true, false)
	if data.model == "forge_golem":   # Forjador: cotovelos, joelhos, mãos, o martelo, a fornalha e o que balança
		for n in ["ElbowL", "ElbowR", "KneeL", "KneeR", "HandL", "HandR", "Hammer", "HammerChain", "Door", "Fire", "Lid",
				"Tasset0", "Tasset1", "Tasset2", "Tasset3", "Chain0", "Chain1", "Stack0", "Stack1", "Stack2"]:
			parts[n] = model.find_child(n, true, false)
	if data.model == "sentinel":   # Sentinela: patas em três ossos (como o lobo), pescoço, cauda, juba, ombreiras
		for sd in WOLF_SIDES:
			for b in ["Leg", "Knee", "Paw", "Foot"]:
				parts[b + sd] = model.find_child(b + sd, true, false)
		for n in ["Neck", "Tail2", "Tail3", "Mane0", "Mane1", "Mane2", "Mane3", "PlateL", "PlateR", "Crest", "Muzzle"]:
			parts[n] = model.find_child(n, true, false)
	if data.model in ["spider", "centipede"]:   # Tecelã e Centopeia: abdômen e as pernas (Leg0L..Leg3R)
		for n in SPIDER_PARTS:
			parts[n] = model.find_child(n, true, false)
	for n in ["Tongue", "VineL", "VineR", "WingL", "WingR"]:   # Bocarrão, Flor-faminta e Asa-couro
		parts[n] = model.find_child(n, true, false)
	if data.model in ["goblin", "skeleton", "brejeiro"]:   # cotovelos, arco e cajado (EnemyPose); o Brejeiro tem os pivôs do goblin
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
	# brilho do bomber (o slime é a própria brasa); o Sapo-Bufo não: a luz laranja pintava o sapo inteiro e as
	# glândulas já vêm pintadas de laranja
	if data.get("ai", "") == "bomber" and data.model != "toad":
		var glow := OmniLight3D.new()
		glow.light_color = data.color
		glow.light_energy = 0.8
		glow.omni_range = 2.5
		glow.position.y = 0.6
		add_child(glow)

	if not Network.is_server():
		status_aura = StatusAura.new()
		status_aura.height = float(data.height)
		model.add_child(status_aura)
		status.mask_changed.connect(status_aura.set_mask)

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
	_abyss_setup()   # Arauto do Abismo e as cópias (não faz nada nos outros)
	if data.get("ai", "") == "forge":
		summoned = true   # o Forjador não chama lacaios ao enfurecer: a fase 2 dele é o superaquecimento
	if data.get("ai", "") == "blizzard":
		summoned = true   # a Sentinela não chama lacaios na fúria: a fase 2 dela é a nevasca
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


func _plate_parent() -> Node3D:
	if _plates == null:
		_plates = Node3D.new()
		_plates.name = "Plates"
		add_child(_plates)
	return _plates


## Esconde as placas quando há chão ou parede (camada world) entre a câmera e a cabeça do monstro: dentro das
## dungeons os nomes não aparecem mais através das paredes.
func _update_occlusion() -> void:
	if _plates == null or not visible:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var head: Vector3 = global_position + Vector3.UP * (float(data.height) * float(data.scale) * size_mult * 0.8)
	var from := cam.global_position
	if from.distance_to(head) > NAME_RANGE * 2.0:
		return   # longe demais: o visibility_range já tira o nome
	var q := PhysicsRayQueryParameters3D.create(from, head, OCCLUDE_MASK)
	_plates.visible = get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _make_health_bar() -> void:
	bar_root = Node3D.new()
	bar_root.position.y = data.height * data.scale * (size_mult if level > 0 else 1.0) + 0.45
	_plate_parent().add_child(bar_root)
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
	_plate_parent().add_child(name_tag)
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
	_plate_parent().add_child(quest_icon)
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
	if not dead and (ai() == "thorn" or data.get("sprout", false)):
		_thorn_process(delta)
	if ai() == "blizzard":
		_blizzard_process(delta)
	if not dead and ai() == "herald":
		_abyss_process(delta)
	if not dead and (ai() == "forge" or data.get("rune", false)):
		_forge_process(delta)
	if _plates != null:
		_occ_t -= delta
		if _occ_t <= 0.0:
			_occ_t = OCCLUDE_CHECK
			_update_occlusion()
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
		_slide()
		return
	if _horde_frozen():
		velocity = Vector3.ZERO
		return
	status.tick(delta)
	if dead:
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
	if ai() == "burrow" and state != "burrow":
		surface_t += delta
	if ai() == "worm":
		_worm_leash(delta)
	stagger = max(0.0, stagger - delta)
	provoked = maxf(0.0, provoked - delta)
	_taunt_tick(delta)
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

	haste_t = maxf(0.0, haste_t - delta)
	var spd: float = data.speed * speed_mult * (0.45 if slow_timer > 0 else 1.0) * (1.3 if enraged else 1.0) \
			* (HOWL_HASTE if haste_t > 0.0 else 1.0)
	var move := Vector3.ZERO
	var face := Vector3.ZERO

	match state:
		"idle":
			state_timer -= delta
			if arena.has_area() and dist == INF and hp < max_hp:
				_heal_home()   # ninguém na sala: quem bateu de fora não deixa o chefe ferido
			if dist < data.aggro or (horde and dist < INF) or (arena.has_area() and dist < INF):
				_set_state("chase")
			elif state_timer <= 0:
				wander_target = home + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
				_set_state("wander")
		"wander":
			var to := wander_target - global_position
			to.y = 0
			if dist < data.aggro or (arena.has_area() and dist < INF):
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
			elif dist == INF or (not arena.has_area() and (global_position.distance_to(home) > leash
					or (dist > data.aggro * 1.9 and provoked <= 0.0))):
				_set_state("return")   # sem alvo (morreu ou entrou na vila, sob a guarda) também volta
			elif ai() == "ranged" or ai() == "caster" or ai() == "flee":
				# arqueiro e mago no mundo: guardam distância, rodeiam e só atiram com o caminho livre;
				# o Goblin Dourado foge (antes caía no corpo a corpo: corria para cima e só empurrava)
				var r := _ranged_move(to_player, dist, spd)
				move = r[0]
				face = r[1]
			elif ai() == "thorn" and attack_cd <= 0 and dist <= ThornRules.ROOT_LEN:
				_begin_attack(dist)   # Espinheira: garra perto, raízes longe
			elif ai() == "blizzard" and attack_cd <= 0 and dist <= BlizzardRules.CAST_RANGE:
				_begin_attack(dist)   # Sentinela: patada perto, sopro e estacas de qualquer distância
			elif ai() == "herald" and attack_cd <= 0 and dist <= AbyssRules.VOLLEY_RANGE:
				_begin_attack(dist)   # Arauto: garra perto, rajada longe, e os golpes de cada fase
			elif ai() == "forge" and attack_cd <= 0 and (dist <= ForgeRules.HAMMER_RANGE or _forge_wants_shield()):
				_begin_attack(dist)   # Forjador: martela de longe (o cone tem 9 m); o escudo sobe de onde ele estiver
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
			if dist < data.aggro * 0.7 or (arena.has_area() and dist < INF):
				_set_state("chase")
			elif to.length() < 1.0:
				_heal_home()
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

	if stagger > 0 or held_t > 0.0:
		move = Vector3.ZERO   # atordoado ou preso pelas mãos sombrias
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
	_slide()
	if ai() != "worm":
		AegisWalls.keep_out(self, radius)   # Égide erguida por perto: não entra (e é empurrado enquanto ela se forma)
	_check_stuck(move, delta)
	_animate_lod(delta, Vector2(velocity.x, velocity.z).length())
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
	var tb := _taunter()
	if tb != null:
		return tb   # provocado (Círculo da Provocação Sombria): só existe quem provocou
	var best: Player = null
	var best_d := INF
	var pool: Array = get_parent().targets() if horde and get_parent().has_method("targets") 		else get_tree().get_nodes_in_group("players")
	var w := get_world_3d()
	for p in pool:
		if p.dead or p.get_world_3d() != w:   # o servidor roda Valdoria e a cidade em mundos separados
			continue
		if not horde and VillageWard.inside(p.global_position):
			continue   # quem está na vila (ou na Horta) está sob a proteção da guarda: o monstro não persegue
		if not in_arena(p.global_position):
			continue   # chefe de dungeon: quem está fora da sala dele não existe
		var d :=global_position.distance_squared_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


## Volta à vida cheia: quem tinha acertado antes não leva XP, loot nem abate depois.
func _heal_home() -> void:
	hp = max_hp
	contributors.clear()
	health_changed.emit(self)


## Se o ponto fica dentro da arena (sempre, para quem não tem arena).
func in_arena(p: Vector3) -> bool:
	return not arena.has_area() or arena.has_point(Vector2(p.x, p.z))


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
	if data.has("howl_cd"):   # Alfa da Matilha: uiva chegando, antes de morder
		return dist < float(data.aggro)
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
			if data.has("howl_cd") and _web_ready(dist):
				attack_kind = "howl"   # Alfa: para, uiva e acelera os lobos em volta
				web_cd = float(data.howl_cd) * randf_range(0.85, 1.15)
			else:
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
		"thorn":
			_thorn_begin(dist)
			return
		"blizzard":
			_sentinel_begin(dist)
			return
		"herald":
			_abyss_begin(dist)
			return
		"forge":
			_forge_begin(dist)
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
	if data.model in ["slime", "leech"]:   # Sanguessuga: o mesmo bote com pulo do Slime que ela substitui
		attack_kind = "lunge"
		velocity.y = 4.5
	elif data.model in ["turtle", "mosquito"]:   # Pernilongo: o rasante da Asa-couro com os números do Slime Veloz
		attack_kind = "lunge"   # mesmo bote do Slime de Gelo que ela substitui, sem o pulo: estica o pescoço e morde
	elif (is_boss and attack_count % 3 == 0) or (data.has("slam_every") and attack_count % int(data.slam_every) == 0):
		attack_kind = "slam"
		FX.telegraph(global_position, _slam_radius(), 0.9)
	else:
		attack_kind = "swing"


func _slam_radius() -> float:
	return 5.0 if is_boss else 3.6


## O visual da pancada em área. `slam_fx: "lightning"` (Golem de Cristal): um raio cai no próprio monstro e a onda
## de choque elétrica abre até o raio do golpe (LightningShockwaveFX); os outros levantam a poeira de sempre.
func _slam_visual(sr: float) -> void:
	if str(data.get("slam_fx", "")) == "lightning":
		Sfx.play_at("zap", global_position, 0.1, 3.0)
		LightningShockwaveFX.cast(get_parent(), FXToon.ground_frame(global_position, sr * 0.7), sr, self)
	else:
		FXToon.slam(global_position, sr)


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
		"howl":
			return 1.3
		"emerge":
			return 1.7
		"quake":
			return float(BossRules.quake_ring(BossRules.QUAKE_RINGS - 1).t) + 0.5
		"rockfall":
			return 2.4
		"acid_rain":
			return 1.6
		"roots":
			return ThornRules.root_time(ThornRules.ROOT_SEGS - 1) + 0.7
		"sprouts":
			return 2.0
		"spores":
			return 2.2
		"breath":
			return BlizzardRules.BREATH_T0 + BlizzardRules.BREATH_TIME + 0.6
		"icicles":
			return 2.6
		"blizzard":
			return 3.0
		"hammer":
			return _forge_time(ForgeRules.HAMMER_DUR)
		"vent":
			return _forge_time(ForgeRules.VENT_DUR)
		"rune_shield":
			return ForgeRules.SHIELD_DUR
	if ai() == "thorn":
		return 1.6   # garra: a árvore é lenta para armar e para voltar
	if ai() == "blizzard":
		return 1.7   # patada
	if ai() == "herald":
		return AbyssRules.duration(attack_kind)
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
		"howl":
			return 0.55
		"emerge":
			return 1.0
		"quake":
			return float(BossRules.quake_ring(0).t)
		"rockfall":
			return 1.8
		"acid_rain":
			return 1.1
		"roots":
			return ThornRules.root_time(0)
		"sprouts":
			return 1.2
		"spores":
			return 1.4
		"breath":
			return BlizzardRules.BREATH_T0
		"icicles":
			return BlizzardRules.SPIKE_T
		"blizzard":
			return 1.2
		"hammer":
			return _forge_time(ForgeRules.HAMMER_T)
		"vent":
			return _forge_time(ForgeRules.VENT_T)
		"rune_shield":
			return ForgeRules.SHIELD_T
	if ai() == "thorn":
		return 0.9
	if ai() == "blizzard":
		return 0.85
	if ai() == "herald":
		return AbyssRules.hit_time(attack_kind)
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
		elif attack_kind == "howl":
			_howl(false)
		elif attack_kind == "emerge":
			_emerge_hit(false)
		elif attack_kind == "quake":
			pass   # os anéis acertam em _boss_tick, cada um na sua hora
		elif attack_kind == "rockfall":
			_rockfall_hit(false)
		elif attack_kind == "acid_rain":
			_acid_hit(false)
		elif attack_kind == "roots":
			pass   # cada trecho acerta na sua hora, em _boss_tick
		elif attack_kind == "sprouts":
			_thorn_sprouts()
		elif attack_kind == "spores":
			_spore_hit(false)
		elif attack_kind == "swing" and ai() == "thorn":
			_thorn_claw(false)
		elif attack_kind == "breath":
			pass   # o cone acerta a cada tique, em _boss_tick
		elif attack_kind == "icicles":
			_icicles_hit(false)
		elif attack_kind == "blizzard":
			_blizzard_roar(false)
		elif attack_kind == "swing" and ai() == "blizzard":
			_sentinel_paw(false)
		elif ai() == "herald":
			_abyss_hit(false)
		elif attack_kind == "hammer":
			_forge_hammer(false)
		elif attack_kind == "vent":
			_forge_vent(false)
		elif attack_kind == "rune_shield":
			_forge_shield_up()
		elif attack_kind == "slam":
			var sr := _slam_radius()
			Sfx.play_at("slam", global_position, 0.0)
			_slam_visual(sr)
			if data.has("chill"):   # Ieti: o soco no chão levanta gelo em volta
				FXToon.frost_nova(global_position, sr * 0.8)
			if player and dist <= sr:
				player.take_damage(vs(level, player, data.damage * dmg_mult * 1.4), global_position)
				if data.has("chill") and player.has_method("apply_chill"):
					player.apply_chill(float(data.chill) * 1.5)
			if player is Player:
				player.add_shake(0.4)
		elif player and dist <= data.reach * 1.3 + 0.3:
			var facing_ok := model_forward().dot(to_player.normalized()) > 0.2 or dist < 1.0
			if facing_ok:
				player.take_damage(vs(level, player, data.damage * dmg_mult * randf_range(0.9, 1.1)), global_position)
				if data.has("chill") and player.has_method("apply_chill"):
					player.apply_chill(float(data.chill), data.get("chill_venom", false))
		if attack_kind == "swing" or (attack_kind == "lunge" and data.model in ["raptor", "spider", "centipede", "frog", "bat", "wolf", "turtle", "mosquito", "leech"]):
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
	arrow.ice = data.get("shot", "") == "ice"   # Gralha-de-Cristal: estilhaço de gelo que deixa lento
	arrow.chill = float(data.get("chill", 0.0)) if arrow.ice else 0.0
	arrow.magic = bolt or arrow.acid or arrow.ice
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
			# os geodos brotam antes e estouram na hora do anel (o dano e o som são do _boss_tick)
			BossFX.geode_ring(c, float(q.r), clampi(int(float(q.r) * 2.1), 8, 32), float(q.t) - elapsed, enraged)
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
		WormFX.acid_splash(BossFX._root(), pt, 2.9)
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
				Sfx.play_at("slam", c, 0.1, -3.0)
				if not visual:
					for p in _boss_pool():
						var d := Vector2(p.global_position.x - c.x, p.global_position.z - c.z).length()
						if not p.dead and BossRules.in_quake_ring(d, i):
							p.take_damage(vs(level, p, data.damage * dmg_mult * 1.1), c)
	elif attack_kind == "roots":
		_roots_tick(visual, t0, t1)
	elif attack_kind == "breath":
		_breath_tick(visual, t0, t1)
	elif attack_kind == "icicles":
		var fall := _hit_time() - BlizzardRules.SPIKE_FALL
		if t0 < fall and fall <= t1:
			for pt in _spike_pts:
				BlizzardFX.falling_spike(pt, BlizzardRules.SPIKE_FALL)
	elif ai() == "herald":
		_abyss_tick(visual, t0, t1)
	elif attack_kind == "rockfall":
		var drop := _hit_time() - 0.55
		if t0 < drop and drop <= t1:
			for pt in _rock_pts:
				BossFX.falling_rock(pt, 0.55)


## Réplica: começa a desenhar um golpe de chefe que o snapshot acabou de trazer (`atk_t` s já passados).
func _replica_boss_start(flags: int, atk_t: float) -> void:
	if ai() == "blizzard":
		_sentinel_replica_start(flags, atk_t)
		return
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
		"roots":
			_root_origin = _net_pos
			_root_dirs = ThornRules.root_dirs(ThrowRules.unpack_offset(flags), flags & 2 != 0)
			_roots_warn(atk_t)
		"spores":
			boss_seed = BossRules.unpack_seed(flags)
			_spore_pts = _spore_targets(_net_pos)
			_spores_warn(atk_t)
		"sprouts":
			_sprouts_warn(_net_pos, atk_t)
		"swing":
			_claw_warn(atk_t)


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
## `element`: elemento do golpe, um nome ("fogo") ou uma mistura ({"fisico": 0.8, "fogo": 0.2}); ver ElementRules.
## O % de cada elemento é o da ficha do Bestiário; imune (0%) não leva dano nem recua.
func take_damage(amount: float, from_pos: Vector3, crit: bool, slow := 0.0, stun := 0.0, pull := 0.0, element = "fisico") -> void:
	if dead or BurrowRules.hidden(state, attack_kind, hit_done):
		return
	asleep = false
	_sleep_t = SLEEP_CHECK
	if shielded:
		_forge_immune(from_pos)   # Escudo Rúnico de pé: nada entra (nem vai ao servidor)
		return
	if puppet:
		# o servidor decide (inclusive o elemento); os números de dano chegam de volta em show_hit()
		Network.client_hit_enemy(net_id, amount, from_pos, crit, slow, stun, pull, element)
		return
	if ai() == "herald" and _abyss_struck():
		return   # era uma cópia da Miragem: desfaz-se sem levar dano
	var em := element_mult(element)
	if em <= 0.0:
		_element_immune()
		return
	amount = incoming(amount) * em
	if ai() == "forge":
		amount = ForgeRules.taken(amount, false, enraged)   # superaquecido leva mais dano
	if last_hitter != 0:
		contributors[last_hitter] = true
	if slow > 0.0:
		apply_slow(slow)
	if horde and get_parent().has_method("on_enemy_damaged"):
		# placar do Desafio da Horda (last_hitter = quem acertou no multiplayer; 0 no solo)
		get_parent().on_enemy_damaged(last_hitter, minf(amount, maxf(hp, 0.0)))
	hp -= amount
	health_changed.emit(self)
	_hit_number(amount, crit, em)
	FXToon.hit_splat(global_position + Vector3.UP * data.height * data.scale * 0.5, data.color, 3 if horde else 5)
	_flash_t = 0.1
	provoked = PROVOKE_TIME
	if state in ["idle", "wander", "return"]:
		_set_state("chase")
	if bar_root:
		bar_root.visible = true
	if not is_boss and ai() != "plant":   # a Flor-faminta tem raiz: não recua
		var heavy: bool = data.get("elite", false) or elite or data.model in ["golem", "yeti"]   # campeões, elites, o Golem e o Ieti quase não recuam
		var kb := global_position - from_pos
		kb.y = 0
		if kb.length() > 0.01:
			# `pull` > 0: em vez de empurrar, puxa (m/s) em direção a quem bateu (Turbilhão, fenda do Abismo);
			# `pull` < 0: empurra com essa força em vez da padrão (Rei dos Ventos)
			kb = kb.normalized() * ((-pull) if pull != 0.0 else (6.0 if data.model == "slime" else 4.0)) * (0.3 if heavy else 1.0)
			velocity.x = kb.x
			velocity.z = kb.z
		if not no_flinch and ((state != "attack" and not heavy) or (crit and attack_kind != "fuse")):
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


## Círculo da Provocação Sombria: as mãos seguram por `hold` s (sem andar nem golpear, o golpe em andamento se
## perde; chefes não ficam presos) e o inimigo fica provocado por `taunt` s depois disso: o alvo dele passa a ser
## `by` (o herói), seja quem for que ele perseguia antes (ver _nearest_player). Não empilha nem renova numa
## mesma ativação (DarkTauntSkill já filtra quem foi agarrado); outra ativação substitui. Réplica: pede ao servidor.
func apply_taunt(by: Node3D, hold: float, taunt: float) -> void:
	if puppet:
		Network.client_taunt_enemy(net_id, hold, taunt)
		return
	if dead or by == null or BurrowRules.hidden(state, attack_kind, hit_done):
		return
	var tt := DarkTauntRules.taunt_times(hold, taunt, is_boss)
	asleep = false
	_sleep_t = SLEEP_CHECK
	if tt.x > 0.0:
		held_t = maxf(held_t, tt.x)
		attack_cd = maxf(attack_cd, tt.x)   # preso: nenhum golpe novo
		if state == "attack" and attack_kind != "emerge":
			_set_state("chase")   # o golpe em andamento se perde
		velocity.x = 0.0
		velocity.z = 0.0
	if tt.y > 0.0:
		taunt_by = by
		taunt_t = tt.y
		provoked = maxf(provoked, tt.y)   # não desiste da perseguição por distância enquanto provocado
		if state in ["idle", "wander", "return"]:
			_set_state("chase")
		_set_taunt_look(true)


## Quem provocou, enquanto a provocação vale (vivo, no mesmo mundo, fora da vila, na sala do chefe). Quando deixa
## de valer (morreu, saiu do jogo, entrou na vila), a provocação acaba ali: volta a IA de sempre.
func _taunter() -> Player:
	if taunt_t <= 0.0:
		return null
	var p := taunt_by as Player
	var ok := p != null and is_instance_valid(p) and p.is_inside_tree() and DarkTauntRules.taunter_ok(not p.dead,
		p.get_world_3d() == get_world_3d(), not horde and VillageWard.inside(p.global_position), in_arena(p.global_position))
	if not ok:
		_clear_taunt()
		return null
	return p


func _taunt_tick(delta: float) -> void:
	held_t = maxf(0.0, held_t - delta)
	if taunt_t > 0.0:
		taunt_t = maxf(0.0, taunt_t - delta)
		if taunt_t <= 0.0:
			_clear_taunt()
		else:
			_taunter()   # confere se o herói ainda vale (senão já encerra)


## Fim da provocação (tempo, morte do herói ou do inimigo): solta as mãos e apaga os olhos.
func _clear_taunt() -> void:
	taunt_t = 0.0
	taunt_by = null
	held_t = 0.0
	_set_taunt_look(false)


## Liga/desliga os olhos vermelhos (TauntIndicator). Sem cena visual (servidor dedicado) não cria nada.
func _set_taunt_look(on: bool) -> void:
	var showing := taunt_eyes != null and is_instance_valid(taunt_eyes) and bool(taunt_eyes.get("active"))
	if on == showing:
		return
	if on:
		if dead or FX._scene() == null:
			return
		if taunt_eyes == null or not is_instance_valid(taunt_eyes) or taunt_eyes.is_queued_for_deletion():
			taunt_eyes = TAUNT_INDICATOR.instantiate()
			add_child(taunt_eyes)
			taunt_eyes.attach(self)
		taunt_eyes.show_eyes()
	elif taunt_eyes != null and is_instance_valid(taunt_eyes):
		taunt_eyes.hide_eyes()


## Topo do inimigo (m acima da origem), o mesmo da barra de vida.
func head_top() -> float:
	return float(data.height) * float(data.scale) * (size_mult if level > 0 else 1.0)


## Dano que este inimigo leva de um acerto de `amount` (menor se estiver bem acima do nível de quem bateu:
## placa vermelha).
func incoming(amount: float) -> float:
	var a := amount
	if level > 0:
		var foe := Game.level
		if Network.is_server():
			foe = Party._level(last_hitter) if last_hitter != 0 else 0
		a *= float(ProgressionRules.danger_mults(Balance.tables, level, foe).taken)
	return a


## Multiplicador elemental de um golpe neste monstro (a régua da ficha do Bestiário; ElementRules.mult).
func element_mult(element) -> float:
	return ElementRules.mult(Balance.tables, kind, element)


## Número de dano: crítico dourado e maior; fraco/resistente com a cor da afinidade e uma dica curta por cima
## (no máximo uma a cada HINT_GAP s, para a rajada de golpes não virar uma parede de palavras).
func _hit_number(amount: float, crit: bool, em: float) -> void:
	var top: Vector3 = global_position + Vector3.UP * (data.height * data.scale + 0.2)
	var base := Color(1, 0.85, 0.2) if crit else Color.WHITE
	FX.damage_number(top, ("%d!" if crit else "%d") % int(round(amount)),
		ElementRules.hint_color(em, base), 64 if crit else 48)
	var word := ElementRules.hint(em)
	if word != "" and _hint_t <= 0.0:
		_hint_t = HINT_GAP
		FX.damage_number(top + Vector3.UP * 0.45, word, ElementRules.hint_color(em, base), 34)


## Golpe de um elemento a que o monstro é imune: só a palavra, sem dano nem recuo (mas ele percebe quem bateu).
func _element_immune() -> void:
	provoked = PROVOKE_TIME
	if not puppet and state in ["idle", "wander", "return"]:
		_set_state("chase")
	if _hint_t > 0.0:
		return
	_hint_t = HINT_GAP
	var top: Vector3 = global_position + Vector3.UP * (data.height * data.scale + 0.2)
	FX.damage_number(top, "Imune", ElementRules.C_IMMUNE, 44)


## "Resistiu" na cor do elemento: a resistência total barrou um status que teria pego (EnchantHit.try_status).
## Mesmo intervalo do "Imune" para não empilhar textos.
func show_resisted(el: String) -> void:
	if _hint_t > 0.0 or not EnchantFX.ELEMENTS.has(el):
		return
	_hint_t = HINT_GAP
	var top: Vector3 = global_position + Vector3.UP * (data.height * data.scale + 0.2)
	FX.damage_number(top, "Resistiu", EnchantFX.ELEMENTS[el].color, 40)


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


## Status elemental (StatusEffects): a réplica pede ao servidor; o dono aplica com quem bateu por último.
func apply_status(el: String, power: float, secs: float) -> void:
	if puppet:
		Network.client_apply_status(net_id, el, power, secs)
		return
	status.apply(el, power, secs, last_hitter)


func apply_slow(t: float) -> void:
	if puppet:
		Network.client_hit_enemy(net_id, 0.0, global_position, false, t)
		return
	slow_timer = max(slow_timer, t)


## Clarão com uma camada própria (`mat`, material_overlay) por `time` s, no lugar do branco do acerto
## (o dourado do Vórtice Sombrio). Só visual, no cliente que chamou.
func flash_with(mat: Material, time: float) -> void:
	_flash_t = maxf(_flash_t, time)
	_flash_mat = mat


func _update_flash(delta: float) -> void:
	_flash_t = max(0.0, _flash_t - delta)
	_hint_t = maxf(0.0, _hint_t - delta)
	var over: Material = _overlay_base
	if _flash_t <= 0.0:
		_flash_mat = null
	if _flash_t > 0:
		over = _flash_mat if _flash_mat != null else _overlay_hit
	elif status_aura != null and status_aura.rim != null:
		over = status_aura.rim   # status elemental: contorno na cor do efeito (o de gelo cobre a lentidão)
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
		# o loot sai antes do abate: o bestiário registra o espólio que caiu
		var drops := drop_loot(get_parent(), kind, global_position, true, level, elite, is_boss)
		Game.on_enemy_killed(kind, xp_reward(), level, area, drops)
	die_visual()


## XP do abate: a do tipo pela curva do nível (sem nível, a de hoje).
func xp_reward() -> int:
	return roundi(float(data.xp) * float(ProgressionRules.enemy_mults(Balance.tables, kind, level).xp))


## Morte sem regras de jogo (também usada pelas réplicas no cliente).
func die_visual() -> void:
	dead = true
	state = "dead"
	status.set_mask(0)   # morto não queima: a aura some junto
	remove_from_group("enemies")
	collision_layer = 0
	collision_mask = 1
	_set_overlay(null)
	_clear_taunt()
	if taunt_eyes != null and is_instance_valid(taunt_eyes):
		taunt_eyes.queue_free()   # morreu: o indicador sai junto, sem esperar o apagar
		taunt_eyes = null
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


## Solo: sorteio do loot (LootRules, o mesmo do servidor). O ouro e os itens entram direto no inventário e o
## espólio voa do monstro até o jogador (Econ.show_loot). Devolve o que saiu da tabela do monstro (antes da
## troca por classe), para o bestiário.
static func drop_loot(parent: Node, enemy_kind: String, pos: Vector3, with_gold := true, level := 0, elite := false,
		boss := false) -> Dictionary:
	boss = boss or TYPES.get(enemy_kind, {}).get("boss", false)
	var extra := DungeonRules.extra_loot(Balance.tables, Regions.region_at(pos), boss)
	var loot := LootRules.roll(Balance.tables, enemy_kind, _loot_rng(), Game.char_class, level, elite, extra)
	var gold := int(loot.gold) if with_gold else 0
	if gold > 0 or not loot.items.is_empty():
		if Econ.grant(gold, 0, loot.items, "loot"):
			Econ.show_loot(pos, gold, loot.items, parent)
	return loot.get("rolled", {})


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


func apply_snapshot(pos: Vector3, yaw: float, new_hp: float, new_state: String, atk_t: float, atk_kind: String, flags: int,
		status_mask := 0) -> void:
	status.set_mask(status_mask)
	_net_pos = pos
	_net_yaw = yaw
	if new_hp != hp:
		if new_hp < hp - 0.5 and _flash_t <= 0.0:
			_flash_t = 0.06
		hp = new_hp
		health_changed.emit(self)
	slow_timer = 0.25 if flags & 1 else 0.0
	_set_taunt_look(flags & TAUNT_FLAG != 0)
	var now_enraged := flags & 2 != 0
	if now_enraged and not enraged and (not horde or get_tree().current_scene.get("survival") != null):
		Game.notify.emit("%s está enfurecido!" % data.name, Color(1, 0.4, 0.3))
	enraged = now_enraged
	if ai() == "forge":
		_forge_set_shield(flags & ForgeRules.SHIELD_FLAG != 0)
	if ai() == "worm":
		_set_fury_look(enraged)
		if new_state == "burrow" and new_hp >= max_hp:
			_intro_shown = false   # voltou para casa cheia: a próxima luta tem entrada de novo
	if ai() == "blizzard":
		_blizzard_snapshot(flags)
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
			elif attack_kind in ["quake", "rockfall", "acid_rain", "roots", "spores", "sprouts"] \
					or (attack_kind == "swing" and ai() == "thorn"):
				_replica_boss_start(flags, atk_t)
			elif ai() == "blizzard":
				_replica_boss_start(flags, atk_t)
			elif ai() == "herald":
				_replica_abyss_start(flags, atk_t)
			elif attack_kind in ["hammer", "vent", "rune_shield"]:
				_forge_replica_start(flags, atk_t)
		elif atk_t < attack_timer - 0.3:
			# um novo ataque começou entre dois snapshots
			attack_kind = atk_kind
			attack_timer = atk_t
			hit_done = atk_t >= _hit_time()
			if attack_kind == "throw":
				_replica_throw(flags, atk_t)
			elif attack_kind in ["quake", "rockfall", "acid_rain", "roots", "spores", "sprouts"] \
					or (attack_kind == "swing" and ai() == "thorn"):
				_replica_boss_start(flags, atk_t)
			elif ai() == "blizzard":
				_replica_boss_start(flags, atk_t)
			elif ai() == "herald":
				_replica_abyss_start(flags, atk_t)
			elif attack_kind in ["hammer", "vent", "rune_shield"]:
				_forge_replica_start(flags, atk_t)
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


## `em` = multiplicador elemental do golpe (o servidor manda junto): muda a cor e põe a dica (Fraco!/Resistiu);
## 0 = imune, só a palavra.
func show_hit(amount: float, crit: bool, em := 1.0) -> void:
	if dead:
		return
	if em <= 0.0:
		_element_immune()
		return
	_hit_number(amount, crit, em)
	FXToon.hit_splat(global_position + Vector3.UP * data.height * data.scale * 0.5, data.color, 5)
	_flash_t = 0.1
	if data.model == "thorn_tree":
		_thorn_leaves(8 if crit else 4)   # cada pancada arranca folhas da copa
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
				_slam_visual(_slam_radius())
				if data.has("chill"):
					FXToon.frost_nova(global_position, _slam_radius() * 0.8)
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
			elif attack_kind == "howl":
				_howl(true)
			elif attack_kind == "emerge":
				_emerge_hit(true)
			elif attack_kind == "rockfall":
				_rockfall_hit(true)
			elif attack_kind == "acid_rain":
				_acid_hit(true)
			elif attack_kind == "spores":
				_spore_hit(true)
			elif attack_kind == "swing" and ai() == "thorn":
				_thorn_claw(true)
			elif attack_kind == "icicles":
				_icicles_hit(true)
			elif attack_kind == "blizzard":
				_blizzard_roar(true)
			elif attack_kind == "swing" and ai() == "blizzard":
				_sentinel_paw(true)
			elif ai() == "herald":
				_abyss_hit(true)
			elif attack_kind == "hammer":
				_forge_hammer(true)
			elif attack_kind == "vent":
				_forge_vent(true)
			elif attack_kind == "swing":
				Sfx.play_at("swing", global_position, 0.15, -4.0)
	var hspeed := Vector2(global_position.x - prev.x, global_position.z - prev.z).length() / maxf(delta, 0.0001)
	_animate_lod(delta, hspeed)
	if bar_root and bar_root.visible:
		bar_fg.scale.x = max(0.001, hp / max_hp)


# ------------------------------------------------------------ animação procedural
## Animação por distância (só onde há câmera; o servidor dedicado anima tudo): perto e na tela anima a cada
## passo de física; mais longe, a cada 2 ou 3 passos, e fora da tela a cada 2 (perto) ou 4. O tempo pulado
## vai junto (`delta` somado), então o movimento chega ao mesmo lugar, só com menos quadros. Ataque e chefe
## sempre a cada passo. Animar era ~40% do custo dos monstros acordados (perfil do pântano, 2026-11-22).
const ANIM_LOD_CHECK := 0.25   # s entre reavaliações da faixa
const ANIM_NEAR := 25.0        # m: até aqui, na tela, a cada passo
const ANIM_MID := 60.0         # m: até aqui, na tela, a cada 2 passos (além: 3)
const ANIM_CLOSE := 8.0        # m: tão perto que conta como na tela (borda da tela, câmera girando)
var _anim_every := 1
var _anim_n := 0
var _anim_acc := 0.0
var _anim_lod_t := 0.0


func _animate_lod(delta: float, hspeed: float) -> void:
	_anim_lod_t -= delta
	if _anim_lod_t <= 0.0:
		_anim_lod_t = ANIM_LOD_CHECK
		_anim_every = _anim_rate()
	_anim_acc += delta
	_anim_n += 1
	if _anim_n < _anim_every and state != "attack":
		return
	_animate(_anim_acc, hspeed)
	_anim_acc = 0.0
	_anim_n = 0


## De quantos em quantos passos de física este monstro anima agora (1 = todo passo).
func _anim_rate() -> int:
	if is_boss:
		return 1
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 1
	var p := global_position + Vector3.UP
	var d2 := p.distance_squared_to(cam.global_position)
	if d2 < ANIM_CLOSE * ANIM_CLOSE:
		return 1
	if not cam.is_position_in_frustum(p):
		return 2 if d2 < ANIM_NEAR * ANIM_NEAR else 4
	if d2 < ANIM_NEAR * ANIM_NEAR:
		return 1
	return 2 if d2 < ANIM_MID * ANIM_MID else 3


## move_and_slide, menos para quem está parado no chão: sem velocidade não há o que mover nem colidir, e a
## colisão era a outra metade do custo dos monstros acordados. A cada REST_RECHECK passos parado desliza mesmo
## assim, para o "no chão" não ficar velho (chão que some, empurrão por posição).
const REST_RECHECK := 30
var _rest_n := 0


func _slide() -> void:
	if is_on_floor() and velocity.y <= 0.0 and absf(velocity.x) < 0.001 and absf(velocity.z) < 0.001 			and _rest_n < REST_RECHECK:
		_rest_n += 1
		velocity.y = 0.0
		return
	_rest_n = 0
	move_and_slide()


func _animate(delta: float, hspeed: float) -> void:
	_life_t += delta
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
	if data.model == "toad":
		_animate_toad(hspeed, k)
		return
	if data.model in ["bat", "mosquito"]:
		_animate_bat(hspeed, k)
		return
	if data.model == "leech":
		_animate_leech(delta, hspeed)
		return
	if data.model == "crow":
		_animate_crow(delta, hspeed, k)
		return
	if data.model in ["wolf", "turtle"]:
		_animate_wolf(delta, hspeed)
		return
	if data.model == "yeti":
		_animate_yeti(delta, hspeed, k)
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
	if data.model == "thorn_tree":
		_animate_thorn(hspeed, s, k)
		return
	if data.model == "sentinel":
		_animate_sentinel(delta, hspeed)
		return
	if data.model == "void_herald":
		_animate_herald(delta, hspeed, k)
		return
	if data.model == "forge_golem":
		_animate_forge(hspeed, s, k)
		return
	if data.model == "forge_rune":
		_animate_rune(k)
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


## Sapo-Bufo (pivôs do sapo com o Body no centro da barriga, patas filhas da raiz): anda em pulinhos, com o corpo
## agachando antes, o sapo todo no ar com as pernas para trás e as mãos para a frente, e amassando ao pousar. No pavio
## do bomber (`fuse`) para de pular, o Body incha (escala; o pivô sobe para a barriga não afundar) e treme cada vez
## mais rápido até estourar no acerto.
func _animate_toad(hspeed: float, k: float) -> void:
	var body: Node3D = parts.Body
	if _toad_rest.is_empty():
		for n in ["Body", "ArmL", "ArmR", "LegL", "LegR"]:
			if parts[n]:
				_toad_rest[n] = (parts[n] as Node3D).position
	var amp := clampf(hspeed / 2.0, 0.0, 1.0)
	var u := fposmod(anim_t * 0.15, 1.0)   # um pulo por ciclo: agacha, voa, pousa, descansa
	var lift := 0.0
	var air := 0.0       # 0..1..0 durante o voo
	var pitch := 0.0
	var squash := 0.0    # > 0 amassa (agachado/pousando), < 0 estica (no ar)
	if u < 0.15:
		squash = sin(u / 0.15 * PI) * 0.6
	elif u < 0.75:
		var a := (u - 0.15) / 0.6
		lift = 4.0 * a * (1.0 - a) * 0.2
		air = sin(a * PI)
		pitch = -0.22 * cos(a * PI)   # nariz para cima na saída, para baixo na chegada
		squash = -air * 0.6
	elif u < 0.95:
		squash = sin((u - 0.75) / 0.2 * PI)
	lift *= amp
	air *= amp
	pitch *= amp
	squash *= amp
	var swell := 1.0 + sin(_life_t * 2.2) * 0.02   # respira parado
	var shake := Vector3.ZERO
	if state == "attack" and attack_kind == "fuse":
		var f := clampf(attack_timer / maxf(_hit_time(), 0.01), 0.0, 1.0)
		var e := f * f * (3.0 - 2.0 * f)
		swell = 1.0 + 0.5 * e + sin(_life_t * (12.0 + 40.0 * f)) * 0.04 * f   # incha pulsando cada vez mais rápido
		var sa := 0.01 + 0.035 * f * f
		shake = Vector3(sin(_life_t * 57.0) * sa, 0.0, cos(_life_t * 43.0) * sa)
		lift = 0.0
		air = 0.0
		pitch = 0.0
		squash = 0.0
	var rest_y: float = (_toad_rest.Body as Vector3).y
	var sq := Vector3(1.0 + squash * 0.06, 1.0 - squash * 0.1, 1.0 + squash * 0.06)
	body.scale = body.scale.lerp(sq * swell, k)
	var by := rest_y + lift - squash * 0.03 + (swell - 1.0) * (rest_y - 0.06)   # 0,06: a barriga no chão
	body.position = body.position.lerp(Vector3(shake.x, by, (_toad_rest.Body as Vector3).z + shake.z), k)
	body.rotation.x = lerpf(body.rotation.x, pitch, k)
	# as patas não crescem, mas a raiz delas acompanha a pele inchada: o pivô se afasta do meio na mesma proporção, só
	# no chão (x e z), e a pata abre como a de um sapo estufado; sem isso a coxa (no Body) se descolava da canela
	var spread := 1.0 + (swell - 1.0) * 1.0
	for n in ["LegL", "LegR"]:
		var leg: Node3D = parts[n]
		if leg:
			var lr: Vector3 = _toad_rest[n]
			leg.position = leg.position.lerp(Vector3(lr.x * spread, lr.y + lift, lr.z * spread), k)
			leg.rotation.x = lerpf(leg.rotation.x, air * 0.55, k)   # no ar as pernas esticam para trás
			var foot: Node3D = parts["Foot" + n.substr(3)]
			if foot:
				foot.rotation.x = lerpf(foot.rotation.x, air * 0.45, k)
	for n in ["ArmL", "ArmR"]:
		var arm: Node3D = parts[n]
		if arm:
			var ar: Vector3 = _toad_rest[n]
			arm.position = arm.position.lerp(Vector3(ar.x * spread, ar.y + lift, ar.z * spread), k)
			arm.rotation.x = lerpf(arm.rotation.x, -air * 0.4, k)   # mãos para a frente, prontas para pousar
			var hand: Node3D = parts["Hand" + n.substr(3)]
			if hand:
				hand.rotation.x = lerpf(hand.rotation.x, air * 0.3, k)


## Asa-couro: bate as asas sem parar (mais rápido voando), o corpo sobe e desce no ritmo; no rasante desce até
## a altura do jogador com as asas abertas para trás e sobe de volta.
func _animate_bat(hspeed: float, k: float) -> void:
	# Pernilongo do Brejo: o mesmo voo com zumbido (batida rápida e curta) e o abdômen balançando (Tail)
	var buzz: bool = data.model == "mosquito"
	var beat := anim_t * 2.2
	var flap := sin(beat) * (0.55 + clampf(hspeed / 5.0, 0.0, 1.0) * 0.2)
	if buzz:   # ~18 batidas por segundo, parado ou voando (a 60 quadros a asa vira um borrão tremendo, como de verdade)
		flap = sin((_life_t + float(_uid() % 7)) * TAU * 18.0) * 0.5
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
	elif state == "attack" and attack_kind == "shoot":   # Gralha: empina, abre as asas e cospe o estilhaço
		var t := attack_timer
		var ht := _hit_time()
		if t < ht:
			var f := clampf(t / maxf(ht, 0.01), 0.0, 1.0)
			body_x = -0.35 * f
			flap = 0.7 * f
			y = 0.15 * f
		elif t < ht + 0.25:
			body_x = 0.3
			flap = -0.3
	parts.Body.position.y = lerp(parts.Body.position.y, 1.5 + y, k)
	parts.Body.rotation.x = lerp(parts.Body.rotation.x, body_x, k)
	if parts.WingL:
		parts.WingL.rotation.z = flap
	if parts.WingR:
		parts.WingR.rotation.z = -flap
	if parts.Head:
		parts.Head.rotation.x = lerp(parts.Head.rotation.x, -body_x * 0.5, k)
	if parts.Tail:   # abdômen: balança devagar atrás do voo e encolhe para a frente no rasante
		parts.Tail.rotation.x = lerp(parts.Tail.rotation.x, sin(anim_t * 0.9) * 0.12 + body_x * 0.6, k)


## Sanguessuga do Lodo: rasteja com uma onda de lado a lado que corre da cabeça à cauda (cada gomo segue o da frente
## com atraso) e o corpo quica de leve; parada, a cabeça sobe e desce farejando. Bote: ergue a frente encolhendo o
## pescoço, dispara a cabeça para a frente e para baixo e gruda; a cauda fica no chão.
func _animate_leech(delta: float, hspeed: float) -> void:
	var body: Node3D = parts.Body
	var head: Node3D = parts.Head
	if body == null or head == null:
		return
	if _leech_rest.is_empty():
		_leech_rest = {"body_y": body.position.y, "head_z": head.position.z}
	var k := 1.0 - exp(-12.0 * delta)
	var kf := 1.0 - exp(-28.0 * delta)
	_gait_amp = lerpf(_gait_amp, clampf(hspeed / 2.8, 0.0, 1.0), 1.0 - exp(-6.0 * delta))
	var amp := _gait_amp
	_gait_ph = fmod(_gait_ph + delta * (0.5 + hspeed * 0.35), 1.0)
	var ph := _gait_ph * TAU
	var tt := _life_t + float(_uid() % 11)
	var wave := 0.42 * amp + 0.08 * (1.0 - amp)     # direção de cada gomo: a onda anda da frente para trás
	var lag := 1.1
	var dir := [wave * sin(ph + lag), wave * 0.5 * sin(ph), wave * sin(ph - lag), wave * sin(ph - 2.0 * lag),
		wave * sin(ph - 3.0 * lag)]                  # Head, Body, Tail, Tail2, Tail3
	var dy := 0.02 * amp * sin(ph * 2.0)
	var head_x := -0.06 * amp * sin(ph * 2.0 + 0.5) - 0.1 * (0.5 + 0.5 * sin(tt * 0.9)) * (1.0 - amp)
	var body_x := 0.0
	var tail_x := 0.0
	var reach := 0.0
	if state == "attack" and attack_kind == "lunge":
		var t := attack_timer
		var ht := _hit_time()
		var coil := smoothstep(0.0, 0.3, t)
		var strike := smoothstep(0.3, ht, t)
		var back := smoothstep(0.6, 1.0, t)
		for i in dir.size():
			dir[i] = float(dir[i]) * (1.0 - coil) * (1.0 - strike) + float(dir[i]) * back
		if t < 0.3:
			head_x = -0.7 * coil
			body_x = -0.15 * coil
			tail_x = 0.15 * coil
			reach = -0.05 * coil
		else:
			head_x = lerpf(lerpf(-0.7, 0.35, strike), 0.0, back)
			body_x = lerpf(lerpf(-0.15, 0.05, strike), 0.0, back)
			tail_x = lerpf(lerpf(0.15, -0.05, strike), 0.0, back)
			reach = lerpf(lerpf(-0.05, 0.12, strike), 0.0, back)
	body.position.y = lerpf(body.position.y, float(_leech_rest.body_y) + dy, k)
	body.rotation.x = lerpf(body.rotation.x, body_x, kf)
	body.rotation.y = lerp_angle(body.rotation.y, float(dir[1]), k)
	head.rotation.x = lerpf(head.rotation.x, head_x, kf if state == "attack" else k)
	head.rotation.y = lerp_angle(head.rotation.y, float(dir[0]) - float(dir[1]), k)
	head.position.z = lerpf(head.position.z, float(_leech_rest.head_z) + reach, kf)
	var prev := float(dir[1])
	var i := 2
	for n in ["Tail", "Tail2", "Tail3"]:
		var seg: Node3D = parts.get(n)
		if seg:
			seg.rotation.y = lerp_angle(seg.rotation.y, float(dir[i]) - prev, k)
			if n == "Tail":
				seg.rotation.x = lerpf(seg.rotation.x, tail_x, kf)
		prev = float(dir[i])
		i += 1


## Alfa da Matilha: uivo que acelera os lobos por perto (servidor/solo); a réplica só mostra o anel e o som.
func _howl(visual: bool) -> void:
	Sfx.play_at("frost_cast", global_position, 0.05, 2.0)
	var r := float(data.get("howl_radius", 14.0))
	FXToon.ring_wave(global_position + Vector3.UP * 0.15, r * 0.5, 0.14, FXToon.MIST)
	FXToon.ring_wave(global_position + Vector3.UP * 0.15, r, 0.1, FXToon.ICE, 0.2, 0.15)
	if visual:
		return
	var kinds: Array = data.get("howl_kinds", [kind])
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead or e.horde != horde or not (e.kind in kinds):
			continue
		if e.global_position.distance_to(global_position) <= r:
			e.haste_t = float(data.get("howl_secs", 6.0))


## Ponto do plano da pata: (y, z) do modelo; o ângulo cresce no mesmo sentido da rotação x (positiva leva para trás
## o que pende para baixo).
static func _pl(v: Vector3) -> Vector2:
	return Vector2(v.y, v.z)


static func _ang(v: Vector2) -> float:
	return atan2(v.y, v.x)


static func _rot(v: Vector2, a: float) -> Vector2:
	return v.rotated(a)


## Repouso das patas do lobo, lido dos pivôs do modelo (quadril = Leg, joelho = Knee, tornozelo = Paw, apoio = Foot).
func _wolf_setup() -> bool:
	if not _wolf_rest.is_empty():
		return true
	for sd in WOLF_SIDES:
		var leg: Node3D = parts.get("Leg" + sd)
		var knee: Node3D = parts.get("Knee" + sd)
		var paw: Node3D = parts.get("Paw" + sd)
		var foot: Node3D = parts.get("Foot" + sd)
		if leg == null or knee == null or paw == null or foot == null:
			return false
		var h := _pl(leg.position)
		var kn := h + _pl(knee.position)
		var a := kn + _pl(paw.position)
		var f := a + _pl(foot.position)
		var up := _ang(kn - h)
		var lo := _ang(a - kn)
		var bend := signf(wrapf(up - _ang(a - h), -PI, PI))
		_wolf_rest[sd] = {"h": h, "k": kn, "a": a, "f": f, "l1": (kn - h).length(), "l2": (a - kn).length(),
			"up": up, "lo": lo, "ft": _ang(f - a), "d": f - a, "bend": bend if bend != 0.0 else 1.0}
	_wolf_rest["body_y"] = (parts.Body as Node3D).position.y
	_wolf_rest["body_z"] = (parts.Body as Node3D).position.z
	_wolf_rest["head_z"] = (parts.Head as Node3D).position.z
	return true


## IK de uma pata: o quadril desce/sobe e vai para a frente/trás com o corpo (dy, pitch, bz), o apoio vai para `foot`
## (plano y/z do modelo) e o
## último osso fica inclinado `tilt` em relação ao repouso. Devolve as rotações x de Leg, Knee e Paw.
func _wolf_leg(sd: String, dy: float, pitch: float, foot: Vector2, tilt: float, bz := 0.0) -> Vector3:
	var r: Dictionary = _wolf_rest[sd]
	var h: Vector2 = r.h
	h = Vector2(h.x + dy - h.y * sin(pitch), h.y + bz)   # o corpo gira em volta do próprio pivô (z = 0) e anda bz
	var a_t: Vector2 = foot - _rot(r.d, tilt)
	var d := a_t - h
	var l1: float = r.l1
	var l2: float = r.l2
	var dist := clampf(d.length(), absf(l1 - l2) + 0.01, l1 + l2 - 0.005)
	var ca := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var up := _ang(d) + float(r.bend) * acos(ca)
	var kn := h + Vector2(cos(up), sin(up)) * l1
	var lo := _ang(a_t - kn)
	var rl := wrapf(up - float(r.up), -PI, PI)
	var rk := wrapf(lo - float(r.lo), -PI, PI) - rl
	var rp := tilt - rl - rk
	return Vector3(rl, rk, rp)


## Lobo da Geada: trote em diagonal com as patas de verdade (três ossos, IK: o apoio fica no chão enquanto o corpo
## passa e a pata dobra no joelho e no punho para voltar à frente), corpo quicando duas vezes por passada, cabeça
## compensando e cauda atrasada. Bote com impulso: recolhe o corpo para trás e para baixo sobre as traseiras, dispara
## para a frente esticando o pescoço e morde no acerto, aterrissa com o peso indo para a frente e volta. Uivo (Alfa):
## senta nas traseiras e ergue a cabeça.
func _animate_wolf(delta: float, hspeed: float) -> void:
	if not _wolf_setup():
		return
	var k := 1.0 - exp(-14.0 * delta)
	var kf := 1.0 - exp(-30.0 * delta)
	# Tartaruga-Musgo: o mesmo esqueleto com patas curtas; passos curtos e rápidos, corpo e cauda quase parados
	var turtle: bool = data.model == "turtle"
	_gait_amp = lerpf(_gait_amp, clampf(hspeed / (2.6 if turtle else 5.0), 0.0, 1.0), 1.0 - exp(-6.0 * delta))
	var amp := _gait_amp
	var freq := 0.45 + hspeed * 0.2                       # passadas por segundo (1,6 no trote de caça)
	if turtle:
		freq = 0.5 + hspeed * 0.42
	_gait_ph = fmod(_gait_ph + delta * freq, 1.0)
	var stride := clampf(hspeed / maxf(freq, 0.1) * 0.55, 0.0, 1.0)
	var lift := 0.06 + 0.1 * amp
	if turtle:
		stride = clampf(hspeed / maxf(freq, 0.1) * 0.5 / float(data.scale), 0.0, 0.34)
		lift = 0.03 + 0.05 * amp
	var ph := _gait_ph * TAU
	var tt := _life_t + float(_uid() % 13)
	# corpo: quica duas vezes por passada, balança um pouco o nariz; parado respira
	var dy := -0.02 * amp + 0.03 * amp * cos(ph * 2.0) + 0.008 * sin(tt * 1.6) * (1.0 - amp)
	var pitch := 0.035 * amp * sin(ph)
	var head_x := 0.14 * amp - pitch * 0.8 + 0.05 * amp * sin(ph * 2.0 + 0.6) + 0.03 * sin(tt * 0.5) * (1.0 - amp)
	var head_y := sin(tt * 0.37) * 0.22 * (1.0 - amp)
	var jaw := 0.02 + maxf(0.0, sin(tt * 4.0)) * 0.07 * (1.0 - amp) + 0.05 * amp
	# cauda: a base balança com a passada (parado, abana devagar) e a ponta vem atrasada e mais aberta
	var wag := 1.15
	var tail_y := sin(ph - 0.8) * 0.35 * amp + sin(tt * wag) * 0.3 * (1.0 - amp)
	var tail2_y := sin(ph - 1.9) * 0.5 * amp + sin(tt * wag - 1.0) * 0.45 * (1.0 - amp)
	var tail_x := -0.05 - 0.2 * amp + 0.08 * sin(ph * 2.0 - 1.0) * amp
	var tail2_x := 0.1 * sin(ph * 2.0 - 2.0) * amp + 0.05 * sin(tt * 0.7) * (1.0 - amp)
	if turtle:
		dy *= 0.5
		pitch *= 0.5
		head_x *= 0.6
		tail_y *= 0.5
		tail2_y *= 0.5
	# apoios: deslocamento (dz para a frente, dyf para cima) e inclinação do último osso por pata
	var feet := {}
	for sd in WOLF_SIDES:
		var off := 0.0 if sd in ["FL", "BR"] else 0.5
		var u := fmod(_gait_ph + off, 1.0)
		var dz := 0.0
		var up := 0.0
		var tilt := 0.0
		if u < 0.6:   # apoio: a pata fica no chão e vai para trás
			dz = stride * (0.5 - u / 0.6)
		else:         # no ar: volta para a frente subindo, punho/jarrete dobrados
			var v := (u - 0.6) / 0.4
			var e := v * v * (3.0 - 2.0 * v)
			dz = stride * (-0.5 + e)
			up = lift * sin(PI * v)
			tilt = (1.1 if sd.begins_with("F") else -0.6) * sin(PI * v) * amp * (0.35 if turtle else 1.0)
		feet[sd] = [dz, up, tilt]

	var bz := 0.0         # corpo para a frente (+) ou para trás (-), em metros
	var reach := 0.0      # pescoço esticando a cabeça para a frente
	if state == "attack" and attack_kind == "lunge" and turtle:
		# bote da tartaruga: recolhe o pescoço com o bico aberto e a frente erguida, dispara o pescoço para a frente
		# (o corpo dá um passo curto com as patas da frente) e fecha o bico no acerto; depois volta devagar
		var t := attack_timer
		var ht := _hit_time()
		var coil := smoothstep(0.0, 0.3, t)
		var shot := smoothstep(0.3, ht, t)
		var air := clampf((t - 0.3) / 0.3, 0.0, 1.0)
		var back := smoothstep(0.6, 1.0, t)
		head_y = 0.0
		tail_y = 0.0
		tail2_y = 0.0
		if t < 0.3:
			reach = -0.06 * coil
			head_x = -0.18 * coil
			jaw = 0.8 * coil
			bz = -0.04 * coil
			dy = -0.02 * coil
			pitch = -0.05 * coil
		else:
			reach = lerpf(lerpf(-0.06, 0.13, shot), 0.0, back)
			head_x = lerpf(lerpf(-0.18, 0.14, shot), 0.0, back)
			jaw = 0.8 if t < ht else lerpf(0.0, 0.05, back)
			bz = lerpf(lerpf(-0.04, 0.05, shot), 0.0, back)
			dy = lerpf(-0.02, 0.0, shot)
			pitch = lerpf(lerpf(-0.05, 0.06, shot), 0.0, back)
		tail_x = 0.15 * coil * (1.0 - back)
		for sd in WOLF_SIDES:
			if sd.begins_with("F") and t >= 0.3:
				feet[sd] = [0.14 * air * (1.0 - back), 0.05 * sin(PI * air), 0.0]
			else:
				feet[sd] = [0.0, 0.0, 0.0]
	elif state == "attack" and attack_kind == "lunge":
		# bote com impulso: recolhe o corpo para trás e para baixo sobre as traseiras (as patas ficam no chão, as da
		# frente inclinam), mira de cabeça baixa rosnando; dispara para a frente esticando o pescoço, abre a boca no ar
		# e fecha no acerto; aterrissa com o peso ainda indo para a frente e volta ao lugar.
		var t := attack_timer
		var ht := _hit_time()
		var coil := smoothstep(0.0, 0.3, t)
		var go := clampf((t - 0.3) / 0.3, 0.0, 1.0)
		var shot := 1.0 - pow(1.0 - go, 3.0)              # sai rápido e desacelera no fim do salto
		var air := clampf((t - 0.35) / 0.25, 0.0, 1.0)
		var land := smoothstep(0.6, 0.75, t)
		var rest := smoothstep(0.75, 1.0, t)
		head_y = 0.0
		tail_y = 0.0
		tail2_y = 0.0
		if t < 0.3:           # recolhe
			bz = -0.2 * coil
			dy = -0.13 * coil
			pitch = 0.03 * coil
			head_x = 0.14 * coil
			reach = -0.03 * coil
			jaw = 0.12 * coil
			tail_x = 0.2 * coil
			tail2_x = 0.1 * coil
			for sd in WOLF_SIDES:
				feet[sd] = [0.0, 0.0, 0.0]
		elif t < 0.6:         # dispara: o corpo atravessa para a frente, as traseiras empurram e as dianteiras alcançam
			bz = lerpf(-0.2, 0.24, shot)
			dy = lerpf(-0.13, 0.0, go) + 0.12 * sin(PI * air)
			pitch = lerpf(0.03, 0.1, go)
			head_x = lerpf(0.14, -0.06, shot) if t < ht else 0.16
			reach = lerpf(-0.03, 0.09, shot)
			jaw = 0.0 if t >= ht else lerpf(0.12, 0.45, smoothstep(0.3, 0.4, t))
			tail_x = lerpf(0.2, -0.3, shot)
			tail2_x = lerpf(0.1, -0.2, shot)
			for sd in WOLF_SIDES:
				if sd.begins_with("F"):   # saem do chão logo no começo e vão à frente
					feet[sd] = [0.5 * air, 0.24 * sin(PI * air), -0.55 * sin(PI * air)]
				elif t < 0.38:            # traseiras ainda no chão: o corpo passa por cima, elas esticam empurrando
					feet[sd] = [0.0, 0.0, 0.0]
				else:
					var h := clampf((t - 0.38) / 0.22, 0.0, 1.0)
					feet[sd] = [-0.15 * h, 0.12 * sin(PI * h), 0.6 * sin(PI * h)]
		else:                 # aterrissa (o peso afunda e ainda empurra para a frente) e volta
			bz = lerpf(lerpf(0.24, 0.1, land), 0.0, rest)
			dy = lerpf(lerpf(0.0, -0.07, land), 0.0, rest)
			pitch = lerpf(lerpf(0.1, 0.05, land), 0.0, rest)
			head_x = lerpf(0.16, 0.06, rest)
			reach = lerpf(0.09, 0.0, land)
			jaw = lerpf(0.0, 0.05, rest)
			tail_x = lerpf(-0.3, -0.05, rest)
			tail2_x = lerpf(-0.2, 0.0, rest)
			for sd in WOLF_SIDES:
				var f0: Array = [0.5, 0.0, 0.0] if sd.begins_with("F") else [-0.15, 0.0, 0.0]
				var w := land
				feet[sd] = [lerpf(f0[0], 0.0, w), lerpf(f0[1], 0.0, w), lerpf(f0[2], 0.0, w)]
	elif state == "attack" and attack_kind == "howl":
		var u := smoothstep(0.0, 0.4, attack_timer) * (1.0 - smoothstep(1.0, 1.3, attack_timer))
		dy = -0.08 * u
		pitch = -0.3 * u          # senta nas traseiras: o peito sobe, o quadril desce
		head_x = -0.75 * u
		head_y = 0.0
		jaw = 0.4 * u
		tail_x = 0.25 * u
		tail2_x = 0.2 * u
		tail_y *= 1.0 - u
		tail2_y *= 1.0 - u
		for sd in WOLF_SIDES:
			feet[sd] = [0.0, 0.0, 0.0]

	var body: Node3D = parts.Body
	body.position.y = lerpf(body.position.y, float(_wolf_rest.body_y) + dy, kf)
	body.position.z = lerpf(body.position.z, float(_wolf_rest.body_z) + bz, kf)
	body.rotation.x = lerpf(body.rotation.x, pitch, kf)
	var bdy := body.position.y - float(_wolf_rest.body_y)
	var bdz := body.position.z - float(_wolf_rest.body_z)
	for sd in WOLF_SIDES:
		var r: Dictionary = _wolf_rest[sd]
		var fz: Array = feet[sd]
		var f: Vector2 = r.f
		var ang := _wolf_leg(sd, bdy, body.rotation.x, Vector2(f.x + float(fz[1]), f.y + float(fz[0])), float(fz[2]), bdz)
		var leg: Node3D = parts["Leg" + sd]
		leg.position.y = float((r.h as Vector2).x) + bdy - float((r.h as Vector2).y) * sin(body.rotation.x)
		leg.position.z = float((r.h as Vector2).y) + bdz
		leg.rotation.x = lerp_angle(leg.rotation.x, ang.x, kf)
		(parts["Knee" + sd] as Node3D).rotation.x = lerp_angle((parts["Knee" + sd] as Node3D).rotation.x, ang.y, kf)
		(parts["Paw" + sd] as Node3D).rotation.x = lerp_angle((parts["Paw" + sd] as Node3D).rotation.x, ang.z, kf)
	parts.Head.rotation.x = lerpf(parts.Head.rotation.x, head_x, kf if state == "attack" else k)
	parts.Head.rotation.y = lerpf(parts.Head.rotation.y, head_y, k)
	parts.Head.position.z = lerpf(parts.Head.position.z, float(_wolf_rest.head_z) + reach, kf)
	if parts.Jaw:
		parts.Jaw.rotation.x = lerpf(parts.Jaw.rotation.x, jaw, kf if jaw < parts.Jaw.rotation.x else k)
	if parts.Tail:
		parts.Tail.rotation.y = lerpf(parts.Tail.rotation.y, tail_y, k)
		parts.Tail.rotation.x = lerpf(parts.Tail.rotation.x, tail_x, k)
	var tail2: Node3D = parts.get("Tail2")
	if tail2:
		tail2.rotation.y = lerpf(tail2.rotation.y, tail2_y, k)
		tail2.rotation.x = lerpf(tail2.rotation.x, tail2_x, k)


## Gralha-de-Cristal: batida de asa em onda (o ombro puxa, o cotovelo e o punho vêm atrasados), dobrando a asa para
## trás na subida e abrindo na descida; de tempos em tempos plana com as asas abertas. O corpo sobe na descida da
## asa, a cabeça compensa e a cauda abre e fecha. Tiro: empina com as asas no alto e, no disparo, dá uma batida forte
## para baixo esticando a cabeça para a frente.
func _animate_crow(delta: float, hspeed: float, k: float) -> void:
	var tt := _life_t + float(_uid() % 11)
	var glide := smoothstep(0.55, 0.9, sin(tt * 0.45)) * (1.0 - clampf(hspeed / 6.0, 0.0, 0.6))
	var freq := 2.3 + clampf(hspeed / 5.0, 0.0, 1.0) * 0.6
	_crow_ph = fmod(_crow_ph + delta * freq * TAU * (1.0 - 0.7 * glide), TAU)
	var ph := _crow_ph
	var beat := 1.0 - glide
	var sh := 0.1 + 0.55 * sin(ph) * beat + 0.05 * sin(tt * 2.0) * glide
	var el := 0.22 * sin(ph - 0.7) * beat
	var wr := 0.3 * sin(ph - 1.3) * beat
	var fold := maxf(0.0, cos(ph)) * 0.55 * beat         # na subida (o ombro subindo) a asa recolhe para trás
	var twist := 0.18 * sin(ph - 0.4) * beat
	var y := -0.08 * sin(ph + 0.5) * beat + 0.05 * sin(tt * 0.9) * glide
	var body_x := 0.05 * sin(ph) * beat + 0.06 * clampf(hspeed / 5.0, 0.0, 1.0)
	var head_x := -body_x * 0.7 + 0.06 * sin(ph + 1.0) * beat
	var tail_x := 0.12 * sin(ph - 1.2) * beat - 0.05 * glide
	if state == "attack" and attack_kind == "shoot":
		var t := attack_timer
		var ht := _hit_time()
		var u := smoothstep(0.0, ht, t)
		var back := smoothstep(ht + 0.1, ht + 0.45, t)
		if t < ht:                  # empina e abre as asas no alto
			sh = lerpf(sh, 0.9, u)
			el = lerpf(el, 0.2, u)
			wr = lerpf(wr, 0.3, u)
			fold = lerpf(fold, 0.0, u)
			body_x = lerpf(body_x, -0.3, u)
			head_x = lerpf(head_x, -0.25, u)
			y = lerpf(y, 0.12, u)
		else:                       # batida forte para baixo, cabeça para a frente (o estilhaço sai do bico)
			var w := 1.0 - back
			sh = lerpf(sh, -0.55, w)
			el = lerpf(el, -0.25, w)
			wr = lerpf(wr, -0.35, w)
			fold = lerpf(fold, 0.0, w)
			body_x = lerpf(body_x, 0.25, w)
			head_x = lerpf(head_x, 0.35, w)
			y = lerpf(y, -0.1, w)
	var kf := 1.0 - exp(-30.0 * delta)
	parts.Body.position.y = lerpf(parts.Body.position.y, 1.5 + y, kf)
	parts.Body.rotation.x = lerpf(parts.Body.rotation.x, body_x, k)
	if parts.Head:
		parts.Head.rotation.x = lerpf(parts.Head.rotation.x, head_x, k)
	if parts.Tail:
		parts.Tail.rotation.x = lerpf(parts.Tail.rotation.x, tail_x, k)
	for sd in [["L", 1.0], ["R", -1.0]]:
		var sg: float = sd[1]
		var w1: Node3D = parts.get("Wing" + sd[0])
		var w2: Node3D = parts.get("Wing" + sd[0] + "2")
		var w3: Node3D = parts.get("Wing" + sd[0] + "3")
		if w1:
			w1.rotation.z = lerpf(w1.rotation.z, sh * sg, kf)
		if w2:
			w2.rotation.z = lerpf(w2.rotation.z, el * sg, kf)
			w2.rotation.y = lerpf(w2.rotation.y, fold * sg, kf)
		if w3:
			w3.rotation.z = lerpf(w3.rotation.z, wr * sg, kf)
			w3.rotation.y = lerpf(w3.rotation.y, fold * 1.3 * sg, kf)
			w3.rotation.x = lerpf(w3.rotation.x, twist, kf)


## Ieti Glacial: andar pesado, o corpo rolando para o lado da perna de apoio e quicando, braços balançando contra as
## pernas com o cotovelo atrasado (sempre um pouco dobrado); parado respira com os ombros. Pancada no chão: ergue os
## dois braços acima da cabeça com os cotovelos dobrados para trás e desce de uma vez curvando o tronco. Golpe comum:
## puxa o braço direito para trás girando o tronco e solta num gancho.
func _animate_yeti(delta: float, hspeed: float, k: float) -> void:
	var kf := 1.0 - exp(-30.0 * delta)
	var amp := clampf(hspeed / 2.6, 0.0, 1.0)
	var ph := anim_t
	var tt := _life_t + float(_uid() % 7)
	var leg := 0.42 * sin(ph) * amp
	var roll := 0.07 * sin(ph) * amp
	var bob := 0.04 * absf(cos(ph)) * amp
	var breathe := sin(tt * 1.4) * (1.0 - amp)
	var body_x := 0.1 + 0.05 * amp + 0.025 * breathe
	var body_y := 0.0
	var arm_l := -0.32 * sin(ph) * amp + 0.04 * breathe
	var arm_r := 0.32 * sin(ph) * amp + 0.04 * breathe
	var elb_l := -0.3 - 0.25 * maxf(0.0, sin(ph - 0.7)) * amp
	var elb_r := -0.3 - 0.25 * maxf(0.0, -sin(ph - 0.7)) * amp
	var head_x := -0.05 + 0.04 * sin(ph * 2.0) * amp
	var lift := bob
	if state == "attack":
		var t := attack_timer
		var ht := _hit_time()
		if attack_kind == "slam":
			var up := smoothstep(0.0, ht * 0.8, t)
			var down := smoothstep(ht * 0.8, ht, t)
			var back := smoothstep(ht + 0.3, _attack_duration(), t)
			var arms := lerpf(lerpf(0.0, -2.7, up), -0.45, down)
			var elb := lerpf(lerpf(-0.3, -1.1, up), -0.15, down)
			body_x = lerpf(lerpf(0.1, -0.12, up), 0.45, down)
			lift = lerpf(lerpf(0.0, 0.06, up), -0.12, down)
			head_x = lerpf(lerpf(-0.05, -0.3, up), 0.2, down)
			arm_l = lerpf(arms, arm_l, back)
			arm_r = arm_l
			elb_l = lerpf(elb, elb_l, back)
			elb_r = elb_l
			body_x = lerpf(body_x, 0.12, back)
			lift = lerpf(lift, 0.0, back)
			roll = 0.0
			leg = 0.0
		elif attack_kind == "swing":
			var wind := smoothstep(0.0, ht * 0.85, t)
			var hit := smoothstep(ht * 0.85, ht, t)
			var back := smoothstep(ht + 0.15, _attack_duration(), t)
			arm_r = lerpf(lerpf(arm_r, 0.75, wind), -1.6, hit)
			elb_r = lerpf(lerpf(elb_r, -1.0, wind), -0.25, hit)
			body_y = lerpf(lerpf(0.0, 0.35, wind), -0.4, hit)
			body_x = lerpf(body_x, 0.25, hit)
			arm_r = lerpf(arm_r, -0.1, back)
			elb_r = lerpf(elb_r, -0.3, back)
			body_y = lerpf(body_y, 0.0, back)
	var body: Node3D = parts.Body
	body.rotation.x = lerpf(body.rotation.x, body_x, kf)
	body.rotation.y = lerpf(body.rotation.y, body_y, kf)
	body.rotation.z = lerpf(body.rotation.z, roll, k)
	parts.LegL.rotation.x = lerpf(parts.LegL.rotation.x, leg, k)
	parts.LegR.rotation.x = lerpf(parts.LegR.rotation.x, -leg, k)
	parts.ArmL.rotation.x = lerpf(parts.ArmL.rotation.x, arm_l, kf)
	parts.ArmR.rotation.x = lerpf(parts.ArmR.rotation.x, arm_r, kf)
	parts.ArmL.rotation.z = lerpf(parts.ArmL.rotation.z, 0.06 + 0.03 * breathe, k)
	parts.ArmR.rotation.z = lerpf(parts.ArmR.rotation.z, -0.06 - 0.03 * breathe, k)
	if parts.get("ElbowL"):
		parts.ElbowL.rotation.x = lerpf(parts.ElbowL.rotation.x, elb_l, kf)
	if parts.get("ElbowR"):
		parts.ElbowR.rotation.x = lerpf(parts.ElbowR.rotation.x, elb_r, kf)
	parts.Head.rotation.x = lerpf(parts.Head.rotation.x, head_x, k)
	parts.Head.rotation.z = lerpf(parts.Head.rotation.z, -roll * 0.6, k)
	if not body.has_meta("rest_y"):
		body.set_meta("rest_y", body.position.y)
	body.position.y = lerpf(body.position.y, float(body.get_meta("rest_y")) + lift, kf)


# ------------------------------------------------------------ Espinheira, a Guardiã-Raiz (chefe do Bosque)
## Regras em ThornRules. Garra perto (varre a frente, pega todos ali), Raízes em linha até quem está mais longe
## (três em leque na fúria), Brotos que a curam enquanto vivem e, na fúria, Nuvens de Esporos que crescem.
## O servidor (ou o solo) decide e dá o dano; a réplica no cliente refaz o desenho pela direção/semente do snapshot.
const SPROUT_KIND := "broto_espinheiro"
const THORN_TICK := 0.5


func _thorn_begin(dist: float) -> void:
	attack_kind = ThornRules.attack(_thorn_n, enraged, dist, float(data.reach), _sprouts_near(global_position).size())
	_thorn_n += 1
	match attack_kind:
		"swing":
			_claw_warn(0.0)
		"roots":
			var tgt = _thorn_far_target()
			var aim: Vector3 = tgt.global_position if tgt != null else global_position + model_forward() * 10.0
			var to := Vector3(aim.x - global_position.x, 0.0, aim.z - global_position.z)
			if to.length() > 0.01:
				model.rotation.y = atan2(to.x, to.z)
			_root_origin = global_position
			_root_dirs = ThornRules.root_dirs(to, enraged)
			throw_point = global_position + (_root_dirs[_root_dirs.size() / 2] as Vector3) * ThornRules.ROOT_LEN
			_root_hit = {}
			_roots_warn(0.0)
		"sprouts":
			_sprouts_warn(global_position, 0.0)
		"spores":
			boss_seed = randi() & 0xFFFF
			_spore_pts = _spore_targets(global_position)
			_spores_warn(0.0)


## Quem está mais longe dela entre os que estão na luta: as Raízes punem quem fica atacando de longe.
func _thorn_far_target() -> Player:
	var best: Player = null
	var best_d := -1.0
	for p in _boss_pool():
		if p.dead or not (p is Player):
			continue
		var d := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length()
		if d <= ThornRules.ROOT_LEN and d > best_d:
			best_d = d
			best = p
	return best if best != null else (_tgt if _tgt is Player else null)


## Centro da varrida da garra: um pouco à frente dela.
func _claw_center() -> Vector3:
	var c := _net_pos if puppet else global_position
	return c + model_forward() * 2.0


func _claw_warn(elapsed: float) -> void:
	FX.telegraph(_claw_center(), 2.8, maxf(0.2, _hit_time() - elapsed))


## A garra desce: rasgos e espinhos no chão à frente; pega todos dentro do círculo avisado.
func _thorn_claw(visual: bool) -> void:
	var c := _claw_center()
	Sfx.play_at("slam", c, 0.1, -2.0)
	ThornFX.claw(BossFX._root(), c, 2.8, model_forward())
	if visual:
		return
	for p in _boss_pool():
		if p.dead:
			continue
		if Vector2(p.global_position.x - c.x, p.global_position.z - c.z).length() <= 2.8:
			p.take_damage(vs(level, p, data.damage * dmg_mult * randf_range(0.95, 1.1)), global_position)
			if p is Player:
				p.add_shake(0.35)


## Aviso das Raízes: uma faixa de pontos vermelhos em cada linha, cada um cheio até a hora do seu trecho.
func _roots_warn(elapsed: float) -> void:
	for d in _root_dirs:
		for i in ThornRules.ROOT_SEGS:
			var left := ThornRules.root_time(i) - elapsed
			if left > 0.0:
				FX.telegraph(ThornRules.root_point(_root_origin, d, i), ThornRules.ROOT_HALF, left)
	Sfx.play_at("slam", _root_origin, 0.2, -6.0)


## Trechos das Raízes que irrompem entre t0 e t1: espinhos saindo do chão e, no servidor/solo, o golpe e a prisão
## em quem está no trecho (cada jogador leva uma vez por golpe, mesmo onde as linhas do leque se cruzam).
func _roots_tick(visual: bool, t0: float, t1: float) -> void:
	for i in ThornRules.ROOT_SEGS:
		var ti := ThornRules.root_time(i)
		if not (t0 < ti and ti <= t1):
			continue
		for d in _root_dirs:
			var at := ThornRules.root_point(_root_origin, d, i)
			ThornFX.root_burst(BossFX._root(), at, d, ThornRules.ROOT_HALF, 1.5 + 0.06 * i)
		if i % 3 == 0:
			Sfx.play_at("slam", ThornRules.root_point(_root_origin, _root_dirs[0], i), 0.2, -8.0)
		if visual:
			continue
		for p in _boss_pool():
			if p.dead or _root_hit.has(p.get_instance_id()):
				continue
			for d in _root_dirs:
				if ThornRules.root_segment(_root_origin, d, p.global_position) == i:
					_root_hit[p.get_instance_id()] = true
					p.take_damage(vs(level, p, data.damage * dmg_mult * 1.2), ThornRules.root_point(_root_origin, d, i))
					if p.has_method("apply_web"):
						p.apply_web(ThornRules.ROOT_SNARE, true)
					break


## Aviso dos Brotos: um círculo de runas em cada ponto onde um vai nascer e, ali, o monte de terra que treme e
## estoura com as gavinhas na hora em que o broto nasce (ThornFX).
func _sprouts_warn(center: Vector3, elapsed: float) -> void:
	var left := maxf(0.2, 1.2 - elapsed)
	for pt in ThornRules.sprout_points(center, model_forward()):
		FXToon.rune_circle(pt, 1.3, 0.3, left)
		ThornFX.sprout_rise(BossFX._root(), pt, 1.2 - elapsed)
	Sfx.play_at("slam", center, 0.4, -4.0)


## Os Brotos nascem (só quem manda nela: o servidor anuncia cada um aos clientes como um monstro comum).
func _thorn_sprouts() -> void:
	if puppet:
		return
	var parent := get_parent()
	for pt in ThornRules.sprout_points(global_position, model_forward()):
		var e: Enemy = (get_script() as GDScript).new()
		e.kind = SPROUT_KIND
		e.level = level
		e.area = area
		e.arena = arena
		e.position = pt + Vector3.UP * 0.3
		parent.add_child(e)


## Brotos vivos perto de `center` (os que ligam a ela e a curam).
func _sprouts_near(center: Vector3) -> Array:
	var out := []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Enemy and e.kind == SPROUT_KIND and not e.dead and e.global_position.distance_to(center) < 30.0:
			out.append(e)
	return out


## Pontos das Nuvens de Esporos: sorteados pela semente em volta dela e um sob cada jogador por perto que esteja na
## mesma sala (a mesma região do mapa: servidor e réplica sabem sem trocar nada; fora de sala, basta estar perto).
func _spore_targets(center: Vector3) -> Array:
	var pts := ThornRules.spore_points(boss_seed, center)
	var room := Regions.area_at(center)
	for p in get_tree().get_nodes_in_group("players"):
		if not p.dead and p.global_position.distance_to(center) < 25.0 \
				and (room == "" or Regions.area_at(p.global_position) == room):
			pts.append(Vector3(p.global_position.x, center.y, p.global_position.z))
	return pts


func _spores_warn(elapsed: float) -> void:
	var left := maxf(0.2, _hit_time() - elapsed)
	for pt in _spore_pts:
		FX.telegraph(pt, ThornRules.SPORE_R0, left)
		ThornFX.spore_pod(BossFX._root(), pt, _hit_time() - elapsed)
	var lp := _local_player()
	if lp != null and lp.has_method("add_shake") and lp.global_position.distance_to(global_position) < 30.0:
		lp.add_shake(0.4)
	Sfx.play_at("slime", global_position, 0.0, 0.0)


## As nuvens nascem (o cogumelo de cada ponto estoura agora, ThornFX.spore_pod) e ficam crescendo (só o
## servidor/solo dá dano).
func _spore_hit(visual: bool) -> void:
	for pt in _spore_pts:
		var cloud := SporeCloud.new()
		cloud.dmg = data.damage * dmg_mult * 0.22
		cloud.level = level
		cloud.deal = not visual
		get_parent().add_child(cloud)
		cloud.global_position = pt


## A cada THORN_TICK s: a Espinheira recebe a cura dos brotos vivos (servidor/solo) e, em toda tela, uma gota de
## seiva voa em arco de cada broto até ela. O broto sem árvore em luta por perto murcha (some sem recompensa).
func _thorn_process(delta: float) -> void:
	_thorn_t -= delta
	if _thorn_t > 0.0:
		return
	_thorn_t = THORN_TICK
	if data.get("sprout", false):
		if puppet:
			return
		for e in get_tree().get_nodes_in_group("enemies"):
			if e is Enemy and e.ai() == "thorn" and not e.dead and e.state in ["chase", "attack"] \
					and e.global_position.distance_to(global_position) < 30.0:
				return
		wither()
		return
	var sprouts := _sprouts_near(global_position)
	if sprouts.is_empty():
		return
	var heart := global_position + Vector3.UP * 2.2
	for sp in sprouts:
		ThornFX.sap(BossFX._root(), sp.global_position + Vector3.UP * 0.8, heart)
	if puppet or hp >= max_hp or state == "idle":
		return
	hp = minf(max_hp, hp + ThornRules.sprout_heal(max_hp, sprouts.size(), THORN_TICK))
	health_changed.emit(self)
	FXToon.heal_touch(heart, 2, 0.6)


## Some sem morrer e sem recompensa (broto da Espinheira quando a luta acabou).
func wither() -> void:
	if dead or puppet:
		return
	if Network.is_server():
		Network.server_enemy_despawn(self)
	FX.burst(global_position + Vector3.UP * 0.6, Color(0.3, 0.22, 0.14), 12, 2.5, 0.12, 0.6)
	dead = true
	queue_free()


## Espinheira: passada pesada de raiz (joelho dobra quando a perna volta; cada pisada levanta terra e derruba
## folhas), braços compridos balançando com atraso e as mãos de garra abrindo e fechando, a copa ondulando com os
## galhos dos lados e os cipós pendurados cada um no seu tempo, o queixo respirando e folhas caindo o tempo todo.
## Golpes: a garra arma com o corpo indo para trás e para baixo e o braço direito subindo de mão aberta, depois
## varre para a frente; as Raízes erguem os dois braços e cravam as garras no chão (ficam lá enquanto as raízes
## correm); os Brotos são um rugido com os braços abertos e a copa tremendo; os Esporos curvam o tronco e a copa
## bombeia. Rotação x positiva: topo para a frente, perna/braço para trás, queixo abre, mão fecha.
func _animate_thorn(hspeed: float, s: float, k: float) -> void:
	var body: Node3D = parts.Body
	if not _rig.has("body_rest"):
		_rig["body_rest"] = body.position
		_rig["step"] = 0.0
		_rig["hit"] = false
		if parts.get("Crown") != null and not puppet_headless():
			_rig["leaves"] = BossFX.leaf_fall(parts.Crown, 1.7, 1.2)
	var amp := clampf(hspeed / 2.6, 0.0, 1.0)
	var idle := 1.0 - amp
	var c := cos(anim_t)
	var lt := _life_t
	var leg := s * 0.38 * amp
	var knee_l := maxf(0.0, c) * 0.7 * amp + 0.06
	var knee_r := maxf(0.0, -c) * 0.7 * amp + 0.06
	var arm_l := -s * 0.3 * amp - 0.06 + sin(lt * 0.7) * 0.035 * idle
	var arm_r := s * 0.3 * amp - 0.06 + sin(lt * 0.7 + 1.3) * 0.035 * idle
	var elb_l := -0.2 - c * 0.2 * amp - sin(lt * 0.6) * 0.06 * idle
	var elb_r := -0.2 + c * 0.2 * amp - sin(lt * 0.6 + 1.0) * 0.06 * idle
	# mãos: soltas, abrem e fecham devagar; andando seguem o braço com atraso
	var hand_l := 0.12 + sin(lt * 0.9 + 0.5) * 0.14 * idle + sin(anim_t - 0.9) * 0.2 * amp
	var hand_r := 0.12 + sin(lt * 0.9 + 2.1) * 0.14 * idle - sin(anim_t - 0.9) * 0.2 * amp
	var body_x := 0.07 + sin(lt * 0.55) * 0.025 * idle
	var body_y := s * 0.07 * amp + sin(lt * 0.33) * 0.03 * idle
	var body_z := sin(anim_t) * 0.05 * amp   # o peso passa de uma raiz para a outra
	var off := Vector3(0.0, -absf(s) * 0.07 * amp + sin(lt * 1.1) * 0.02 * idle, 0.0)
	var head_x := sin(lt * 0.45 + 0.7) * 0.025 * idle
	var crown_x := sin(lt * 0.5) * 0.04 - body_x * 0.3 - absf(s) * 0.05 * amp
	var crown_z := sin(lt * 0.7 + 0.4) * 0.05 - body_z * 1.3
	var crown_s := 1.0
	var bough := sin(lt * 0.8 - 0.9) * 0.05 + sin(anim_t - 1.1) * 0.07 * amp   # galhos dos lados: atrasados
	var shake := 0.0   # tremor da copa (galhos e cipós chacoalham junto)
	var jaw := 0.04 + sin(lt * 1.2) * 0.03
	if state == "attack":
		var t := attack_timer
		var ht := _hit_time()
		var u := clampf(t / ht, 0.0, 1.0)
		var e := u * u * (3.0 - 2.0 * u)
		match attack_kind:
			"swing":
				if t < ht:   # arma: recua e afunda, gira o tronco, braço direito sobe por trás de mão aberta
					off = Vector3(0.0, -0.18 * e, -0.32 * e)
					body_y = 0.42 * e
					body_x = 0.02
					arm_r = -2.3 * e
					elb_r = -0.9 * e
					hand_r = -0.5 * e
					arm_l = -0.5 * e
					hand_l = 0.4 * e
					jaw = 0.25 * e
					head_x = -0.04 * e
				elif t < ht + 0.35:   # varre: o corpo vai para a frente e o braço desce cruzando, mão em gancho
					off = Vector3(0.0, -0.1, 0.34)
					body_y = -0.48
					body_x = 0.34
					arm_r = -0.45
					elb_r = -0.1
					hand_r = 0.55
					arm_l = 0.3
					jaw = 0.38
					shake = 1.0
			"roots":
				var dur := _attack_duration()
				if t < ht - 0.25:   # os dois braços sobem de mãos abertas, o tronco recua
					var w := clampf(t / (ht - 0.25), 0.0, 1.0)
					w = w * w * (3.0 - 2.0 * w)
					off = Vector3(0.0, -0.08 * w, -0.25 * w)
					arm_l = -2.6 * w
					arm_r = -2.6 * w
					elb_l = -0.5 * w
					elb_r = -0.5 * w
					hand_l = -0.5 * w
					hand_r = -0.5 * w
					body_x = -0.04
					jaw = 0.3 * w
				elif t < dur - 0.35:   # crava as garras no chão e segura enquanto as raízes correm
					off = Vector3(0.0, -0.32, 0.22)
					body_x = 0.5
					arm_l = -0.2
					arm_r = -0.2
					elb_l = -0.15
					elb_r = -0.15
					hand_l = 0.35
					hand_r = 0.35
					knee_l = 0.45
					knee_r = 0.45
					leg = -0.2
					jaw = 0.4
					shake = 0.6
			"sprouts":
				if t < ht + 0.5:   # rugido: braços abertos com as garras para cima, copa tremendo
					arm_l = -1.4 * e
					arm_r = -1.4 * e
					elb_l = -1.1 * e
					elb_r = -1.1 * e
					hand_l = -0.6 * e
					hand_r = -0.6 * e
					body_x = -0.1 * e
					off = Vector3(0.0, 0.05 * e, -0.1 * e)
					jaw = 0.5 * e
					head_x = -0.05 * e
					shake = 1.4 * e
			"spores":
				if t < ht + 0.4:   # curva o tronco, braços para trás, a copa incha e solta
					body_x = 0.38 * e
					off = Vector3(0.0, -0.18 * e, 0.06 * e)
					arm_l = 0.45 * e
					arm_r = 0.45 * e
					elb_l = -0.3
					elb_r = -0.3
					hand_l = 0.5 * e
					hand_r = 0.5 * e
					jaw = 0.45 * e
					crown_s = 1.0 + 0.1 * e
					crown_x = 0.25 * e
					shake = 1.0 if t < ht else 0.3
		# o golpe acerta: folhas arrancadas da copa (uma vez por golpe)
		if t >= ht and not _rig.hit:
			_rig.hit = true
			_thorn_leaves(14 if attack_kind in ["sprouts", "spores"] else 9)
		elif t < ht:
			_rig.hit = false
	else:
		_rig.hit = false
	if stagger > 0.0 or _flash_t > 0.0:
		shake = maxf(shake, 0.8)   # pancada: a copa estremece
	var sh := shake * sin(lt * 31.0)
	var sh2 := shake * sin(lt * 27.0 + 1.0)
	crown_z += sh * 0.05
	crown_x += sh2 * 0.035
	# pisada: quando uma raiz bate no chão, terra espirra, folhas caem e quem está perto sente o tranco
	if amp > 0.35 and state != "attack":
		var step := signf(s)
		if step != 0.0 and step != float(_rig.step):
			_rig.step = step
			_thorn_step("KneeL" if step > 0.0 else "KneeR")
	var roots_pose := state == "attack" and attack_kind == "roots"
	parts.LegL.rotation.x = lerp(parts.LegL.rotation.x, leg, k)
	parts.LegR.rotation.x = lerp(parts.LegR.rotation.x, leg if roots_pose else -leg, k)
	parts.ArmL.rotation.x = lerp(parts.ArmL.rotation.x, arm_l, k)
	parts.ArmR.rotation.x = lerp(parts.ArmR.rotation.x, arm_r, k)
	for pair in [["KneeL", knee_l], ["KneeR", knee_r], ["ElbowL", elb_l], ["ElbowR", elb_r], ["HandL", hand_l],
			["HandR", hand_r]]:
		var j: Node3D = parts.get(pair[0])
		if j:
			j.rotation.x = lerp(j.rotation.x, float(pair[1]), k)
	body.rotation.x = lerp(body.rotation.x, body_x, k)
	body.rotation.y = lerp(body.rotation.y, body_y, k)
	body.rotation.z = lerp(body.rotation.z, body_z, k)
	body.position = body.position.lerp(_rig.body_rest + off, k)
	if parts.Head:
		parts.Head.rotation.x = lerp(parts.Head.rotation.x, head_x, k)
	var crown: Node3D = parts.get("Crown")
	if crown:
		crown.rotation.x = lerp(crown.rotation.x, crown_x, k)
		crown.rotation.z = lerp(crown.rotation.z, crown_z, k)
		crown.scale = crown.scale.lerp(Vector3.ONE * crown_s, k)
	# galhos mestres dos lados: seguem a copa com atraso (um sobe quando o outro desce) e tremem com ela
	for pair in [["BoughL", 1.0], ["BoughR", -1.0]]:
		var bn: Node3D = parts.get(pair[0])
		if bn:
			var sd: float = pair[1]
			bn.rotation.z = lerp(bn.rotation.z, bough * sd + sh2 * 0.05, k)
			bn.rotation.x = lerp(bn.rotation.x, sin(lt * 0.6 + sd) * 0.03 + sh * 0.04 * sd, k)
	# cipós pendurados: pêndulos, cada um com o seu tempo; andando ficam para trás
	for i in 4:
		var hn: Node3D = parts.get("Hang%d" % i)
		if hn:
			var ph := i * 1.7
			hn.rotation.x = lerp(hn.rotation.x, sin(lt * 1.3 + ph) * 0.1 + sin(anim_t - 1.4 + ph) * 0.22 * amp
				- 0.18 * amp + sh * 0.25, k)
			hn.rotation.z = lerp(hn.rotation.z, sin(lt * 1.05 + ph * 1.3) * 0.12 - crown_z * 0.8 + sh2 * 0.25, k)
	if parts.Jaw:
		parts.Jaw.rotation.x = lerp(parts.Jaw.rotation.x, jaw, k)


## Sem tela (servidor dedicado, testes headless): nada de partículas.
func puppet_headless() -> bool:
	return DisplayServer.get_name() == "headless"


## Folhas arrancadas da copa.
func _thorn_leaves(n: int) -> void:
	var crown: Node3D = parts.get("Crown")
	if crown != null and is_inside_tree():
		BossFX.leaf_burst(crown.global_position + Vector3.UP * 1.2 * float(data.scale), n, 1.6)


## Pisada de uma raiz: terra, algumas folhas e um tranco em quem está perto.
func _thorn_step(knee: String) -> void:
	var kn: Node3D = parts.get(knee)
	if kn == null or not is_inside_tree() or puppet_headless():
		return
	var at := Vector3(kn.global_position.x, global_position.y + 0.1, kn.global_position.z)
	FX.burst(at, Color(0.34, 0.25, 0.16), 7, 2.4, 0.12, 0.5)
	_thorn_leaves(3)
	var lp := _local_player()
	if lp != null and lp.has_method("add_shake") and lp.global_position.distance_to(global_position) < 14.0:
		lp.add_shake(0.08)


# ------------------------------------------------------------ Arauto do Abismo (chefe final, dungeon do Abismo)
## Regras em AbyssRules. Três fases pela vida. Fase 1: Rajada de Sombras em leque (longe), Garra em arco (perto) e
## Zonas de Vazio que ficam no chão e crescem. Fase 2 (abaixo de 65%): Miragem, ele some e reaparece em roda com
## cópias (monstros "sombra_arauto", que o servidor anuncia como qualquer monstro); todos atacam, acertar uma cópia
## a desfaz e acertar o verdadeiro desfaz todas. A PISTA: só o verdadeiro tem a sombra no chão e a fenda da máscara
## acesa (vem do tipo do monstro, então toda tela vê igual). Fase 3 (abaixo de 30%): Colapso, ele vai para o
## centro da sala, puxa todos e solta a explosão em anéis de dentro para fora, com vãos seguros.
## O servidor (ou o solo) decide e dá o dano; a réplica refaz o desenho pela direção/semente do snapshot. O puxão
## é aplicado em cada tela no jogador dela (o cliente é dono da própria posição).
const ECHO_KIND := "sombra_arauto"
const HERALD_PARTS := ["ElbowL", "ElbowR", "HandL", "HandR", "Halo", "Core", "Cape", "Sash", "Charm0", "Charm1",
	"SleeveL", "SleeveR", "Tatter0", "Tatter1", "Tatter2", "Tatter3", "Tatter4", "Tatter5", "Wisp0", "Wisp1", "Wisp2",
	"Wisp3"]
## Ângulo (graus, no chão) de cada tira da barra e de cada fiapo, para abrirem para fora (ver bosses.py).
const HERALD_TATTER_DEG := [15.0, 75.0, 135.0, 195.0, 255.0, 315.0]
const HERALD_WISP_DEG := [60.0, 150.0, 240.0, 330.0]


## Cópia de sombra da Miragem.
func is_echo() -> bool:
	return bool(data.get("echo", false))


## No _ready do Arauto e das cópias: os pivôs do modelo, a sombra no chão (só o verdadeiro) e, na cópia, tudo o
## que a deixa igual ao chefe por fora (mesma luz, mesma placa, sem barra de vida) menos a pista.
func _abyss_setup() -> void:
	if ai() != "herald":
		return
	summoned = true   # sem lacaios na metade da vida: as fases dele são outras
	for n in HERALD_PARTS:
		parts[n] = model.find_child(n, true, false)
	# luz própria, fria, à frente e acima dele: a sala do Abismo é escura e vermelha, e sem ela o manto vira silhueta
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.8, 0.72, 1.0)
	fill.light_energy = 2.6
	fill.omni_range = 7.5
	fill.shadow_enabled = false
	fill.position = Vector3(0, 3.4, 2.6)
	model.add_child(fill)
	if not is_echo():
		_rig["shadow"] = AbyssFX.ground_shadow(self, 1.7 * float(data.scale) * size_mult)
		return
	if bar_root != null:
		bar_root.queue_free()
		bar_root = null
		bar_fg = null
	var aura := OmniLight3D.new()
	aura.light_color = Color(1, 0.3, 0.1)
	aura.light_energy = 1.5
	aura.omni_range = 6.0
	aura.position.y = 2.0
	add_child(aura)
	if name_tag != null:
		name_tag.pixel_size = 0.001
		name_tag.position.y = float(data.height) * float(data.scale) * size_mult + 0.5
		name_tag.visibility_range_end = NAME_RANGE * 2.0
		name_tag.modulate = Color(1.0, 0.45, 0.25)
		if Game.leveled_up.is_connected(_update_plate_color):
			Game.leveled_up.disconnect(_update_plate_color)
	attack_cd = randf_range(1.5, 2.6)
	if not puppet:
		state = "chase"
	if puppet_headless():
		return
	for mi in meshes:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# a fenda da máscara apagada (o halo, que é filho da cabeça, continua aceso)
	var head: Node3D = parts.get("Head")
	var halo: Node3D = parts.get("Halo")
	if head == null:
		return
	for mi: MeshInstance3D in head.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.is_in_group(ToonLook.OUTLINE_GROUP) or (halo != null and halo.is_ancestor_of(mi)):
			continue
		for si in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(si)
			if src == null or not _glows(src):
				continue
			var off: Material = src.duplicate()
			if off is ShaderMaterial:
				(off as ShaderMaterial).set_shader_parameter("albedo", Color(0.05, 0.03, 0.07))
				(off as ShaderMaterial).set_shader_parameter("emission", Color(0, 0, 0))
			elif off is StandardMaterial3D:
				(off as StandardMaterial3D).albedo_color = Color(0.05, 0.03, 0.07)
				(off as StandardMaterial3D).emission_enabled = false
			mi.set_surface_override_material(si, off)


## A sala do chefe (x, z do mundo). O servidor e o solo já têm (`arena`); a réplica acha a sala do mapa onde está.
func _abyss_room() -> Rect2:
	if arena.has_area():
		return arena
	if _rig.has("room"):
		return _rig.room
	var w := get_tree().current_scene
	var maps = w.get("maps") if w != null else null
	if maps is Dictionary:
		for root in (maps as Dictionary).values():
			if root is MapRoot:
				var r := MapLoader.boss_arena(root, _net_pos if puppet else global_position)
				if r.has_area():
					_rig["room"] = r
					return r
	return Rect2()


## O centro da sala na altura dele (sem sala: a casa dele; na réplica sem sala, onde ele está).
func _abyss_center() -> Vector3:
	var p := _net_pos if puppet else global_position
	var room := _abyss_room()
	if room.has_area():
		var c := room.get_center()
		return Vector3(c.x, p.y, c.y)
	return p if puppet else Vector3(home.x, p.y, home.z)


## Cópias vivas por perto.
func _abyss_echoes() -> Array:
	var out := []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Enemy and e.kind == ECHO_KIND and not e.dead and e.global_position.distance_to(global_position) < 45.0:
			out.append(e)
	return out


## O Arauto verdadeiro em luta por perto (null = a luta acabou: as cópias se desfazem).
func _abyss_master() -> Enemy:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Enemy and e.ai() == "herald" and not e.is_echo() and not e.dead and e.state in ["chase", "attack"] \
				and e.global_position.distance_to(global_position) < 45.0:
			return e
	return null


## Jogadores na luta, iguais no servidor e na réplica: vivos, perto dele e dentro da sala (sem sala, só perto).
func _abyss_players(center: Vector3) -> Array:
	var room := _abyss_room()
	var out := []
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead or p.global_position.distance_to(center) > 30.0:
			continue
		if room.has_area() and not room.has_point(Vector2(p.global_position.x, p.global_position.z)):
			continue
		out.append(p)
	return out


## Todo passo de física, em toda tela: a cópia envelhece e some quando a luta acaba; o verdadeiro troca de fase
## pela vida (o servidor/solo manda; a réplica acompanha para o desenho) e, no Colapso, puxa o jogador desta tela.
func _abyss_process(delta: float) -> void:
	if is_echo():
		if not puppet:
			_abyss_t += delta
			if _abyss_t >= AbyssRules.ECHO_LIFE or (_abyss_t > 0.5 and _abyss_master() == null):
				echo_pop()
		return
	if state == "attack" and attack_kind == "collapse" and attack_timer < AbyssRules.PULL_T:
		_abyss_pull(delta)
	if not puppet and state in ["chase", "attack"] and hp > max_hp * _herald_debug_hp():
		hp = max_hp * _herald_debug_hp()   # capturas: --heraldhp=0.6 leva a luta direto para a fase 2
		health_changed.emit(self)
	var ph := AbyssRules.phase(hp / maxf(max_hp, 1.0))
	if puppet:
		if ph == 3 and _abyss_phase < 3:
			Game.notify.emit("O Abismo desaba em volta do Arauto!", Color(1, 0.3, 0.45))
		_abyss_phase = ph
		# Miragem: a réplica pula para onde ele reapareceu (deslizando até lá, entregaria quem é o verdadeiro)
		if state == "attack" and attack_kind == "mirage" and attack_timer >= _hit_time():
			global_position = _net_pos
		return
	if ph == _abyss_phase:
		return
	var rising := ph > _abyss_phase
	_abyss_phase = ph
	_abyss_n = 0
	enraged = ph >= 2
	if rising:
		attack_cd = minf(attack_cd, 0.8)
		Game.notify.emit("O Arauto do Abismo se desfaz em sombras!" if ph == 2 else "O Abismo desaba em volta do Arauto!",
			Color(1, 0.3, 0.45))
	else:   # voltou para casa e se curou: a luta recomeça do início
		for e in _abyss_echoes():
			e.echo_pop()


static var _herald_hp := -1.0


## Depuração (capturas de tela): `--heraldhp=<fração>` na linha de comando limita a vida do Arauto em luta, para
## fotografar as fases 2 e 3 sem precisar bater nele. Sem a opção, 1 (não muda nada).
static func _herald_debug_hp() -> float:
	if _herald_hp < 0.0:
		_herald_hp = 1.0
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--heraldhp="):
				_herald_hp = clampf(float(a.substr(11)), 0.05, 1.0)
	return _herald_hp


## O puxão do Colapso no jogador desta tela (solo e cliente; o servidor dedicado não tem jogador local).
func _abyss_pull(delta: float) -> void:
	var lp := _local_player()
	if lp == null or not (lp is CharacterBody3D) or lp.get("dead") == true:
		return
	var c := _net_pos if puppet else global_position
	if lp.global_position.distance_to(c) > 30.0:
		return
	var room := _abyss_room()
	if room.has_area() and not room.grow(1.0).has_point(Vector2(lp.global_position.x, lp.global_position.z)):
		return
	var step := AbyssRules.pull_step(lp.global_position, c, delta) - lp.global_position
	# anda rente ao chão: onde bate (rampa, degrau, pilar), o resto do passo escorrega pela superfície
	var body := lp as CharacterBody3D
	for i in 3:
		if step.length() < 0.0001:
			break
		var col := body.move_and_collide(step)
		if col == null:
			break
		step = col.get_remainder().slide(col.get_normal())


func _abyss_begin(dist: float) -> void:
	if is_echo():
		attack_kind = AbyssRules.echo_attack(dist, float(data.reach))
	else:
		attack_kind = AbyssRules.attack(_abyss_n, _abyss_phase, dist, float(data.reach), _abyss_echoes().size())
		_abyss_n += 1
	stagger = AbyssRules.hit_time(attack_kind)   # parado enquanto arma: o aviso no chão não sai do lugar
	_abyss_origin = global_position
	match attack_kind:
		"swing", "volley":
			var aim: Vector3 = _tgt.global_position if _tgt != null and is_instance_valid(_tgt) \
				else global_position + model_forward() * 8.0
			var to := Vector3(aim.x - global_position.x, 0.0, aim.z - global_position.z)
			_abyss_dir = to.normalized() if to.length() > 0.01 else model_forward()
			model.rotation.y = atan2(_abyss_dir.x, _abyss_dir.z)
			throw_point = global_position + _abyss_dir * 4.0   # a direção vai no snapshot
		"voids":
			boss_seed = randi() & 0xFFFF
			_abyss_pts = _void_targets(global_position)
		"mirage":
			boss_seed = randi() & 0xFFFF
			_abyss_pts = AbyssRules.mirage_points(boss_seed, _abyss_center(), _abyss_room(),
				AbyssRules.echo_count(_abyss_phase))
		"collapse":
			var c := _abyss_center()
			AbyssFX.vanish(global_position, float(data.height))
			global_position = Vector3(c.x, global_position.y, c.z)
			velocity = Vector3.ZERO
			_abyss_origin = global_position
			AbyssFX.vanish(global_position, float(data.height))
	_abyss_warn(0.0)


## Dano base dos golpes: o do tipo com o multiplicador de nível; a cópia é um monstro comum nos dados (fica
## abaixo dos campeões nas tabelas) e bate com "echo_power" vezes isso, perto da metade do verdadeiro.
func _abyss_dmg() -> float:
	return data.damage * dmg_mult * float(data.get("echo_power", 1.0))


## Quantos projéteis a Rajada deste tem: a cópia atira menos.
func _abyss_shots() -> int:
	return 3 if is_echo() else AbyssRules.volley_shots(AbyssRules.phase(hp / maxf(max_hp, 1.0)))


## Pontos das Zonas de Vazio: sorteados pela semente em volta dele (dentro da sala) e um sob cada jogador na luta.
func _void_targets(center: Vector3) -> Array:
	var pts := AbyssRules.void_points(boss_seed, center, _abyss_room())
	for p in _abyss_players(center):
		pts.append(Vector3(p.global_position.x, center.y, p.global_position.z))
	return pts


## O aviso no chão do golpe da vez (`elapsed` = quanto do golpe já passou; a réplica entra no meio).
func _abyss_warn(elapsed: float) -> void:
	var c := _abyss_origin
	var left := maxf(0.2, _hit_time() - elapsed)
	match attack_kind:
		"swing":
			AbyssFX.arc_warning(c, _abyss_dir, AbyssRules.CLAW_R, AbyssRules.CLAW_HALF, left)
		"volley":
			var blade_pts: Array = []
			var blade_dirs: Array = AbyssRules.volley_dirs(_abyss_dir, _abyss_shots())
			for d in blade_dirs:
				AbyssFX.line_warning(c + d * 1.4, c + d * 15.0, 0.4, left)
				blade_pts.append(_abyss_muzzle(c, d))
			if FX._scene() != null:   # as lâminas nascem no ar em leque aberto, uma a uma, e fecham na mira
				var hover: Array = []
				for d in blade_dirs:
					var ang: float = _abyss_dir.signed_angle_to(d, Vector3.UP) * 3.2
					hover.append(c + _abyss_dir.rotated(Vector3.UP, ang) * 2.3
						+ Vector3.UP * (_abyss_muzzle(c, d).y - c.y + 0.9 - absf(ang) * 0.35))
				RuneBladesFX.charge(FX._scene(), blade_pts, blade_dirs, left, 1.9, RuneBladesFX.RED, hover)
			Sfx.play_at("heal", c, 0.3, -8.0)
		"voids":
			for pt in _abyss_pts:
				FX.telegraph(pt, AbyssRules.VOID_R0, left)
			Sfx.play_at("slime", c, 0.0, -2.0)
		"mirage":
			for pt in _abyss_pts:
				FXToon.rune_circle(pt, 1.5, 0.3, left)
			Sfx.play_at("heal", c, 0.5, -6.0)
		"collapse":
			for i in AbyssRules.COLLAPSE_RINGS:
				var q := AbyssRules.collapse_ring(i)
				var t := float(q.t) - elapsed
				if t <= 0.0:
					continue
				if i == 0:
					FX.telegraph(c, float(q.r1), t)
				else:
					BossFX.ring_warning(c, (float(q.r0) + float(q.r1)) / 2.0, float(q.r1) - float(q.r0), t)
			Sfx.play_at("slam", c, 0.0, 2.0)
			var lp := _local_player()
			if lp != null and lp.has_method("add_shake") and lp.global_position.distance_to(c) < 30.0:
				lp.add_shake(0.7)


## A hora do golpe: a Garra, a Rajada, as Zonas e a Miragem (as faixas do Colapso estouram em _abyss_tick).
func _abyss_hit(visual: bool) -> void:
	match attack_kind:
		"swing":
			_abyss_claw(visual)
		"volley":
			_abyss_volley(visual)
		"voids":
			_abyss_voids(visual)
		"mirage":
			_abyss_mirage(visual)


## A Garra varre o arco avisado: rasgos de sombra em leque; pega todos dentro do setor.
func _abyss_claw(visual: bool) -> void:
	var c := _abyss_origin
	Sfx.play_at("swing", c, 0.0, 0.0)
	Sfx.play_at("slam", c, 0.2, -6.0)
	for i in 5:
		var d := _abyss_dir.rotated(Vector3.UP, deg_to_rad(AbyssRules.CLAW_HALF * (i - 2) / 2.4))
		FXToon.streak(c + d * 1.2 + Vector3.UP * 0.1, c + d * AbyssRules.CLAW_R + Vector3.UP * 0.1, 0.3, AbyssFX.VOID,
			{"sweep": 0.1, "hold": 0.12, "fade": 0.3, "delay": 0.02 * i})
	FXToon.thorns(c + _abyss_dir * 2.8, Basis.IDENTITY, 0.6, 2.2, 7, 1.4, 0.2)
	if visual:
		return
	for p in _boss_pool():
		if p.dead or not AbyssRules.in_claw(c, _abyss_dir, p.global_position):
			continue
		p.take_damage(vs(level, p, _abyss_dmg() * randf_range(0.95, 1.1)), c)
		if p is Player:
			p.add_shake(0.35)


## De onde sai cada lâmina da Rajada (as lâminas do preparo nascem nos mesmos pontos).
func _abyss_muzzle(c: Vector3, d: Vector3) -> Vector3:
	return c + Vector3.UP * clampf(float(data.height) * float(data.scale) * 0.3, 0.8, 1.4) + d * 1.3


## A Rajada sai: uma lâmina rúnica por direção do leque (a réplica desenha as mesmas, sem dano).
func _abyss_volley(visual: bool) -> void:
	var c := _abyss_origin
	Sfx.play_at("bow_shot", c, 0.3, -3.0)
	var y := clampf(float(data.height) * float(data.scale) * 0.3, 0.8, 1.4)
	for d in AbyssRules.volley_dirs(_abyss_dir, _abyss_shots()):
		var orb := ENEMY_ARROW.new()
		orb.blade = true
		orb.direction = d
		orb.damage = 0.0 if visual else _abyss_dmg() * 0.6
		orb.level = level
		orb.source = get_parent()
		get_parent().add_child(orb)
		orb.global_position = c + Vector3.UP * y + (d as Vector3) * 1.3
	FXToon.puff(c + Vector3.UP * y + _abyss_dir * 1.2, 2.2, AbyssFX.VOID, {"vel": _abyss_dir * 3.0, "grow": 0.1, "hold": 0.1,
		"fade": 0.35})


## As Zonas de Vazio nascem: um estouro de sombra em cada ponto e a zona que fica crescendo.
func _abyss_voids(visual: bool) -> void:
	for pt in _abyss_pts:
		FXToon.puff(pt + Vector3.UP * 0.5, 2.4, AbyssFX.VOID, {"grow": 0.15, "hold": 0.2, "fade": 0.5})
		var zone := VoidZone.new()
		zone.dmg = data.damage * dmg_mult * 0.12
		zone.level = level
		zone.deal = not visual
		get_parent().add_child(zone)
		zone.global_position = pt
	Sfx.play_at("slam", _abyss_origin, 0.3, -4.0)


## A Miragem acontece: fumaça onde ele estava e em cada ponto da roda; quem manda nele (servidor/solo) o leva
## para o primeiro ponto e cria uma cópia em cada um dos outros, todos virados para o centro.
func _abyss_mirage(visual: bool) -> void:
	var h := float(data.height) * float(data.scale)
	AbyssFX.vanish(_abyss_origin, h)
	Sfx.play_at("slam", _abyss_origin, 0.4, -4.0)
	for pt in _abyss_pts:
		AbyssFX.vanish(pt, h)
	if visual or _abyss_pts.is_empty():
		return
	var c := _abyss_center()
	var p0: Vector3 = _abyss_pts[0]
	global_position = Vector3(p0.x, global_position.y, p0.z)
	velocity = Vector3.ZERO
	model.rotation.y = atan2(c.x - p0.x, c.z - p0.z)
	var parent := get_parent()
	for i in range(1, _abyss_pts.size()):
		var pt: Vector3 = _abyss_pts[i]
		var e: Enemy = (get_script() as GDScript).new()
		e.kind = ECHO_KIND
		e.level = level
		e.area = area
		e.arena = arena
		e.position = Vector3(pt.x, global_position.y + 0.1, pt.z)
		parent.add_child(e)
		e.model.rotation.y = atan2(c.x - pt.x, c.z - pt.z)


## A cada quadro do Colapso entre t0 e t1 (s desde o início): riscos do puxão e as faixas que estouram agora.
func _abyss_tick(visual: bool, t0: float, t1: float) -> void:
	if attack_kind != "collapse":
		return
	var c := _net_pos if puppet else global_position
	if t1 < AbyssRules.PULL_T and int(t0 / 0.1) != int(t1 / 0.1):
		AbyssFX.pull_streaks(c, 13.0, 3)
	for i in AbyssRules.COLLAPSE_RINGS:
		var q := AbyssRules.collapse_ring(i)
		if not (t0 < float(q.t) and float(q.t) <= t1):
			continue
		AbyssFX.ring_blast(c, float(q.r0), float(q.r1))
		Sfx.play_at("explode", c, 0.1 * i, -1.0)
		var lp := _local_player()
		if lp != null and lp.has_method("add_shake") and lp.global_position.distance_to(c) < 30.0:
			lp.add_shake(0.5)
		if visual:
			continue
		for p in _abyss_players(c):
			var d := Vector2(p.global_position.x - c.x, p.global_position.z - c.z).length()
			if AbyssRules.in_collapse_ring(d, i):
				p.take_damage(vs(level, p, data.damage * dmg_mult * 1.25), c)


## Réplica: começa a desenhar um golpe do Arauto que o snapshot acabou de trazer (`atk_t` s já passados).
func _replica_abyss_start(flags: int, atk_t: float) -> void:
	_abyss_origin = _net_pos
	match attack_kind:
		"swing", "volley":
			var off := ThrowRules.unpack_offset(flags)
			_abyss_dir = off.normalized() if off.length() > 0.01 else model_forward()
		"voids":
			boss_seed = BossRules.unpack_seed(flags)
			_abyss_pts = _void_targets(_net_pos)
		"mirage":
			boss_seed = BossRules.unpack_seed(flags)
			_abyss_pts = AbyssRules.mirage_points(boss_seed, _abyss_center(), _abyss_room(),
				AbyssRules.echo_count(AbyssRules.phase(hp / maxf(max_hp, 1.0))))
		"collapse":
			AbyssFX.vanish(global_position, float(data.height))
			global_position = _net_pos
			AbyssFX.vanish(global_position, float(data.height))
	if atk_t < _hit_time() or attack_kind == "collapse":
		_abyss_warn(atk_t)


## Levou um golpe. true = o golpe não conta (era uma cópia, que se desfaz). No verdadeiro, com cópias vivas, o
## golpe desfaz todas e corta o que ele estava fazendo (menos o Colapso).
func _abyss_struck() -> bool:
	if is_echo():
		echo_pop()
		return true
	var echoes := _abyss_echoes()
	if echoes.is_empty():
		return false
	for e in echoes:
		e.echo_pop()
	attack_cd = maxf(attack_cd, AbyssRules.ECHO_BREAK)
	if state == "attack" and attack_kind != "collapse":
		_set_state("chase")
	FX.damage_number(global_position + Vector3.UP * (float(data.height) * float(data.scale) + 0.8), "Miragem desfeita!",
		Color(1.0, 0.5, 0.65), 44)
	return false


## A cópia se desfaz em fumaça, sem morrer e sem recompensa.
func echo_pop() -> void:
	if dead or puppet:
		return
	if Network.is_server():
		Network.server_enemy_despawn(self)
	gone_fx()
	dead = true
	queue_free()


## O desenho de um monstro que some sem morrer (a réplica chama quando o servidor avisa): a cópia vira fumaça.
func gone_fx() -> void:
	if is_echo() and is_inside_tree():
		AbyssFX.vanish(global_position, float(data.height) * float(data.scale))
		Sfx.play_at("slime", global_position, 0.4, -6.0)


## Arauto: flutua (o corpo sobe e desce devagar e inclina para a frente quando anda), os braços compridos pendem e
## balançam com atraso, as mãos de garra abrem e fecham, a cabeça pende de lado, o halo gira no próprio eixo (mais
## rápido a cada fase), o núcleo pulsa, e a capa, o tabardo, os amuletos, as tiras da barra, as tiras das mangas
## e os fiapos de sombra ficam para trás, cada um no seu tempo. Fiapos caem do manto e brasas sobem do halo.
## Golpes: todos armam com o corpo indo para trás e para baixo. Garra: o braço direito abre para o lado de mão
## aberta e varre cruzando a frente. Rajada: os braços fecham no peito (o núcleo incha) e se jogam para a frente.
## Zonas: sobe com os braços abertos para o alto e desce batendo. Miragem: encolhe com os braços cruzados sobre a
## máscara até sumir, e reaparece abrindo. Colapso: braços para o alto enquanto puxa (núcleo enorme, halo
## disparado), comprime no peito e solta de braços abertos e peito para fora.
## Rotação x positiva: topo para a frente, braço para trás, mão fecha; z positiva abre o braço esquerdo.
func _animate_herald(delta: float, hspeed: float, k: float) -> void:
	var body: Node3D = parts.Body
	if not _rig.has("body_rest"):
		_rig["body_rest"] = body.position
		_rig["spin"] = 0.0
		_rig["hit"] = false
		if not puppet_headless():
			_rig["shreds"] = AbyssFX.shreds(body, 0.55, -0.95)
			if parts.get("Halo") != null:
				_rig["embers"] = AbyssFX.halo_embers(parts.Halo, 0.86)
	var amp := clampf(hspeed / 2.4, 0.0, 1.0)
	var idle := 1.0 - amp
	var lt := _life_t
	var ph := AbyssRules.phase(hp / maxf(max_hp, 1.0))
	var off := Vector3(0.0, sin(lt * 1.5) * 0.09, 0.0)
	var body_x := 0.04 + 0.15 * amp + sin(lt * 0.6) * 0.02
	var body_y := sin(lt * 0.4) * 0.05 * idle
	var body_z := sin(lt * 0.75) * 0.025
	var scale_b := 1.0
	var arm_lx := 0.08 + 0.3 * amp + sin(lt * 0.8) * 0.05
	var arm_rx := 0.08 + 0.3 * amp + sin(lt * 0.8 + 1.4) * 0.05
	var arm_lz := 0.04 + sin(lt * 0.6) * 0.04
	var arm_rz := -0.04 - sin(lt * 0.6 + 0.8) * 0.04
	var elb_l := -0.18 - sin(lt * 0.7) * 0.08 - 0.2 * amp
	var elb_r := -0.18 - sin(lt * 0.7 + 1.1) * 0.08 - 0.2 * amp
	var hand_l := 0.1 + sin(lt * 1.1) * 0.2
	var hand_r := 0.1 + sin(lt * 1.1 + 2.0) * 0.2
	var head_x := sin(lt * 0.5 + 0.6) * 0.04 - 0.06 * amp
	var head_y := sin(lt * 0.3) * 0.1 * idle
	var head_z := sin(lt * 0.37 + 1.0) * 0.07
	var cape_x := 0.03 + 0.24 * amp + sin(lt * 0.9 - 0.6) * 0.035
	var sash_x := 0.26 * amp + sin(lt * 1.0 - 0.9) * 0.04
	var trail := 0.3 * amp      # tiras e fiapos ficam para trás quando ele anda
	var flare := 0.0            # e abrem para fora nos golpes
	var core_s := 1.0 + sin(lt * 3.0) * 0.07
	var spin: float = [0.4, 1.0, 2.2][ph - 1]
	var shake := 0.0
	if state == "attack":
		var t := attack_timer
		var ht := _hit_time()
		var dur := _attack_duration()
		var u := clampf(t / ht, 0.0, 1.0)
		var e := u * u * (3.0 - 2.0 * u)
		match attack_kind:
			"swing":
				if t < ht:   # arma: recua e afunda, torce o tronco, o braço direito abre para o lado de mão aberta
					off = Vector3(0.0, -0.22 * e, -0.38 * e)
					body_y = 0.5 * e
					body_x = -0.04
					arm_rz = -1.45 * e
					arm_rx = 0.35 * e
					elb_r = -0.5 * e
					hand_r = -0.6 * e
					arm_lx = -0.5 * e
					elb_l = -0.9 * e
					hand_l = 0.5 * e
					head_y = -0.3 * e
					spin = 3.0
				elif t < ht + 0.4:   # varre: o corpo vai para a frente e o braço cruza o peito, mão em gancho
					off = Vector3(0.0, -0.1, 0.42)
					body_y = -0.6
					body_x = 0.3
					arm_rz = 0.55
					arm_rx = -1.25
					elb_r = -0.25
					hand_r = 0.6
					arm_lx = 0.5
					arm_lz = 0.3
					head_y = 0.25
					flare = 0.8
					cape_x = 0.5
			"volley":
				if t < ht:   # recua, os braços fecham no peito e o núcleo incha
					off = Vector3(0.0, -0.16 * e, -0.3 * e)
					body_x = -0.12 * e
					arm_lx = -0.75 * e
					arm_rx = -0.75 * e
					arm_lz = -0.42 * e
					arm_rz = 0.42 * e
					elb_l = -1.5 * e
					elb_r = -1.5 * e
					hand_l = 0.6 * e
					hand_r = 0.6 * e
					head_x = 0.12 * e
					core_s = 1.0 + 0.7 * e + sin(lt * 16.0) * 0.06
					spin = 4.0
					shake = 0.5 * e
				elif t < ht + 0.45:   # joga os braços para a frente, mãos abertas
					off = Vector3(0.0, -0.05, 0.3)
					body_x = 0.3
					arm_lx = -1.5
					arm_rx = -1.5
					arm_lz = 0.25
					arm_rz = -0.25
					elb_l = -0.1
					elb_r = -0.1
					hand_l = -0.7
					hand_r = -0.7
					core_s = 0.7
					cape_x = 0.55
					flare = 0.6
			"voids":
				if t < ht:   # sobe com os braços abertos para o alto, a cabeça para trás
					off = Vector3(0.0, 0.4 * e, -0.15 * e)
					body_x = -0.14 * e
					arm_lx = -0.7 * e
					arm_rx = -0.7 * e
					arm_lz = 1.5 * e
					arm_rz = -1.5 * e
					elb_l = -0.5 * e
					elb_r = -0.5 * e
					hand_l = -0.6 * e
					hand_r = -0.6 * e
					head_x = -0.25 * e
					spin = 3.0
					flare = 0.4 * e
				elif t < ht + 0.5:   # desce batendo as mãos para baixo
					off = Vector3(0.0, -0.3, 0.12)
					body_x = 0.36
					arm_lx = -0.5
					arm_rx = -0.5
					arm_lz = 0.2
					arm_rz = -0.2
					elb_l = -0.1
					elb_r = -0.1
					hand_l = 0.5
					hand_r = 0.5
					head_x = 0.15
					flare = 1.0
					cape_x = -0.2
			"mirage":
				if t < ht:   # encolhe, os braços cruzam sobre a máscara, e some
					off = Vector3(0.0, -0.2 * e, -0.12 * e)
					body_x = 0.3 * e
					arm_lx = -1.2 * e
					arm_rx = -1.2 * e
					arm_lz = -0.5 * e
					arm_rz = 0.5 * e
					elb_l = -1.7 * e
					elb_r = -1.7 * e
					hand_l = 0.4 * e
					hand_r = 0.4 * e
					head_x = 0.2 * e
					spin = 6.0
					shake = e
					scale_b = 1.0 - smoothstep(ht - 0.3, ht, t)
				else:   # reaparece abrindo os braços
					scale_b = smoothstep(ht + 0.05, ht + 0.4, t)
					if t < ht + 0.6:
						arm_lz = 0.9
						arm_rz = -0.9
						hand_l = -0.5
						hand_r = -0.5
						flare = 0.8
			"collapse":
				if t < AbyssRules.PULL_T:   # puxa: braços para o alto, o núcleo enorme, o halo disparado
					var w := clampf(t / 0.6, 0.0, 1.0)
					w = w * w * (3.0 - 2.0 * w)
					off = Vector3(0.0, 0.45 * w, -0.1 * w)
					body_x = -0.1 * w
					arm_lx = -2.7 * w
					arm_rx = -2.7 * w
					arm_lz = 0.3 * w
					arm_rz = -0.3 * w
					elb_l = -0.3
					elb_r = -0.3
					hand_l = -0.6 * w
					hand_r = -0.6 * w
					head_x = -0.28 * w
					core_s = 1.0 + 0.9 * w + sin(lt * 15.0) * 0.08
					spin = 8.0
					shake = 0.6
					cape_x = -0.25 * w
					flare = -0.5 * w
				elif t < ht:   # comprime: desce fechando os braços no peito
					var c := clampf((t - AbyssRules.PULL_T) / (ht - AbyssRules.PULL_T), 0.0, 1.0)
					off = Vector3(0.0, 0.45 - 0.8 * c, -0.25 * c)
					body_x = 0.42 * c
					arm_lx = lerpf(-2.7, -0.9, c)
					arm_rx = lerpf(-2.7, -0.9, c)
					arm_lz = -0.5 * c
					arm_rz = 0.5 * c
					elb_l = -1.7 * c
					elb_r = -1.7 * c
					hand_l = 0.6
					hand_r = 0.6
					head_x = 0.2 * c
					core_s = 1.9 - 0.6 * c + sin(lt * 20.0) * 0.1
					spin = 11.0
					shake = 1.0
				elif t < dur - 0.5:   # solta: braços abertos, peito para fora, cabeça para trás
					off = Vector3(0.0, 0.3, 0.1)
					body_x = -0.26
					arm_lx = -0.4
					arm_rx = -0.4
					arm_lz = 1.5
					arm_rz = -1.5
					elb_l = -0.2
					elb_r = -0.2
					hand_l = -0.7
					hand_r = -0.7
					head_x = -0.32
					core_s = 0.6
					cape_x = 0.6
					flare = 1.0
					spin = 3.0
	if is_echo():
		scale_b *= smoothstep(0.0, 0.35, lt)   # a cópia nasce abrindo, como ele ao reaparecer
	if _flash_t > 0.0:
		shake = maxf(shake, 0.7)   # pancada: o manto estremece
	var sh := shake * sin(lt * 33.0)
	var sh2 := shake * sin(lt * 27.0 + 1.0)
	var hit_now := state == "attack" and attack_timer >= _hit_time() and attack_timer < _hit_time() + 0.15
	var kf := 1.0 - exp(-34.0 * delta) if hit_now else k
	var ks := 1.0 - exp(-5.0 * delta)   # peças penduradas: seguem devagar
	body.rotation.x = lerp(body.rotation.x, body_x + sh2 * 0.015, kf)
	body.rotation.y = lerp(body.rotation.y, body_y, kf)
	body.rotation.z = lerp(body.rotation.z, body_z + sh * 0.02, kf)
	body.position = body.position.lerp(_rig.body_rest + off, kf)
	body.scale = Vector3.ONE * maxf(scale_b, 0.02)
	parts.ArmL.rotation.x = lerp(parts.ArmL.rotation.x, arm_lx, kf)
	parts.ArmL.rotation.z = lerp(parts.ArmL.rotation.z, arm_lz, kf)
	parts.ArmR.rotation.x = lerp(parts.ArmR.rotation.x, arm_rx, kf)
	parts.ArmR.rotation.z = lerp(parts.ArmR.rotation.z, arm_rz, kf)
	for pair in [["ElbowL", elb_l], ["ElbowR", elb_r], ["HandL", hand_l], ["HandR", hand_r]]:
		var j: Node3D = parts.get(pair[0])
		if j:
			j.rotation.x = lerp(j.rotation.x, float(pair[1]), kf)
	if parts.Head:
		parts.Head.rotation.x = lerp(parts.Head.rotation.x, head_x, k)
		parts.Head.rotation.y = lerp(parts.Head.rotation.y, head_y, k)
		parts.Head.rotation.z = lerp(parts.Head.rotation.z, head_z, k)
	var halo: Node3D = parts.get("Halo")
	if halo:
		_rig.spin = lerpf(float(_rig.spin), spin, 1.0 - exp(-3.0 * delta))
		halo.rotation.z = wrapf(halo.rotation.z + float(_rig.spin) * delta, -PI, PI)
	var core: Node3D = parts.get("Core")
	if core:
		core.scale = core.scale.lerp(Vector3.ONE * core_s, k)
		core.rotation.z = wrapf(core.rotation.z + delta * (1.5 + spin), -PI, PI)
	var cape: Node3D = parts.get("Cape")
	if cape:
		cape.rotation.x = lerp(cape.rotation.x, cape_x + sh * 0.03, ks)
		cape.rotation.z = lerp(cape.rotation.z, sin(lt * 0.7 - 1.2) * 0.03 - body_z * 1.5, ks)
	var sash: Node3D = parts.get("Sash")
	if sash:
		sash.rotation.x = lerp(sash.rotation.x, sash_x - body_x * 0.8 + sh2 * 0.1, ks)
		sash.rotation.z = lerp(sash.rotation.z, sin(lt * 1.2 - 0.5) * 0.05, ks)
	for i in 2:
		var ch: Node3D = parts.get("Charm%d" % i)
		if ch:
			ch.rotation.x = lerp(ch.rotation.x, sin(lt * 1.5 + i * 2.0) * 0.12 + trail * 1.2 - body_x, ks)
			ch.rotation.z = lerp(ch.rotation.z, sin(lt * 1.25 + i) * 0.1 + sh * 0.2, ks)
	for pair in [["SleeveL", arm_lx, arm_lz], ["SleeveR", arm_rx, arm_rz]]:
		var sl: Node3D = parts.get(pair[0])
		if sl:   # as tiras da manga pendem para baixo qualquer que seja o braço
			sl.rotation.x = lerp(sl.rotation.x, -float(pair[1]) * 0.7 + sin(lt * 1.3) * 0.08, ks)
			sl.rotation.z = lerp(sl.rotation.z, -float(pair[2]) * 0.7 + sh * 0.15, ks)
	# tiras da barra e fiapos de sombra: pêndulos, cada um com o seu tempo; abrem para fora nos golpes
	for i in HERALD_TATTER_DEG.size():
		var tn: Node3D = parts.get("Tatter%d" % i)
		if tn:
			var a := deg_to_rad(HERALD_TATTER_DEG[i])
			var open := flare * 0.5 + sin(lt * 1.3 + i * 1.7) * 0.07
			tn.rotation.x = lerp(tn.rotation.x, -open * sin(a) + trail + sh * 0.15, ks)
			tn.rotation.z = lerp(tn.rotation.z, open * cos(a) + sin(lt * 1.05 + i * 2.3) * 0.06 + sh2 * 0.15, ks)
	for i in HERALD_WISP_DEG.size():
		var wn: Node3D = parts.get("Wisp%d" % i)
		if wn:
			var a := deg_to_rad(HERALD_WISP_DEG[i])
			var open := flare * 0.6 + 0.12 + sin(lt * 1.7 + i * 1.3) * 0.14
			wn.rotation.x = lerp(wn.rotation.x, -open * sin(a) + trail * 1.6, ks)
			wn.rotation.z = lerp(wn.rotation.z, open * cos(a) + sin(lt * 1.4 + i * 2.1) * 0.1, ks)
			wn.rotation.y = sin(lt * 0.9 + i * 1.9) * 0.35
	# os fiapos caem mais a cada fase
	var shreds: CPUParticles3D = _rig.get("shreds")
	if shreds != null:
		shreds.speed_scale = [1.0, 1.5, 2.2][ph - 1]


# ------------------------------------------------------------ Forjador Rúnico (chefe das Galerias Profundas)
## Regras em ForgeRules. Martelada em cone à frente (pega todos no cone e deixa faixas de metal derretido), Respiro
## da Fornalha em volta dele (para quem fica colado nas costas), Escudo Rúnico (imune até o grupo quebrar as 3
## runas que nascem na sala; ele continua atacando) e, abaixo de metade da vida, superaquecido: golpes mais
## rápidos, mais faixas, e leva mais dano. O servidor (ou o solo) decide e dá o dano; a réplica no cliente refaz
## o desenho pela direção do snapshot e sabe do escudo por um bit de `flags`.
const RUNE_KIND := "runa_forjador"
const FORGE_TICK := 0.5
const FORGE_WARD_R := 3.3
const FORGE_WARD_H := 5.4
## Onde a cabeça do martelo bate, em metros à frente dele.
const FORGE_REACH := 5.6


func _forge_begin(dist: float) -> void:
	attack_kind = ForgeRules.attack(_forge_n, dist, _forge_wants_shield())
	if attack_kind != "rune_shield":
		_forge_n += 1
	match attack_kind:
		"hammer":
			var to := Vector3.ZERO
			if _tgt != null and is_instance_valid(_tgt):
				to = _tgt.global_position - global_position
			to.y = 0.0
			if to.length() < 0.01:
				to = model_forward()
			model.rotation.y = atan2(to.x, to.z)
			_forge_origin = global_position
			_forge_dir = to.normalized()
			throw_point = global_position + _forge_dir * ForgeRules.CONE_LEN
			_hammer_warn(0.0)
		"vent":
			_vent_warn(0.0)
		"rune_shield":
			boss_seed = randi() & 0xFFFF
			_shield_warn(0.0)


func _forge_wants_shield() -> bool:
	return ForgeRules.should_shield(hp / maxf(max_hp, 1.0), _forge_shields, _forge_since, shielded)


## Tempo dos golpes dele (aviso e duração): mais curtos quando superaquecido.
func _forge_time(base: float) -> float:
	return base * ForgeRules.time_scale(enraged)


func _hammer_warn(elapsed: float) -> void:
	ForgeFX.cone_warning(_forge_origin, _forge_dir, ForgeRules.CONE_LEN, ForgeRules.CONE_HALF,
		maxf(0.2, _hit_time() - elapsed))
	Sfx.play_at("anvil", _forge_origin, 0.1, -5.0)


## O martelo bate: pancada no chão à frente, a onda corre pelo cone e as faixas de metal derretido ficam. Pega
## todos dentro do cone avisado (só o servidor/solo dá o dano).
func _forge_hammer(visual: bool) -> void:
	var at := _forge_origin + _forge_dir * FORGE_REACH * float(data.scale)
	Sfx.play_at("slam", at, 0.05, 2.0)
	Sfx.play_at("anvil", at, 0.1, 0.0)
	ForgeFX.hammer_impact(at, _forge_origin, _forge_dir, ForgeRules.CONE_LEN, ForgeRules.CONE_HALF)
	var lp := _local_player()
	if lp != null and lp.has_method("add_shake") and lp.global_position.distance_to(_forge_origin) < 30.0:
		lp.add_shake(0.55)
	for d in ForgeRules.trail_dirs(_forge_dir, enraged):
		var tr := MoltenTrail.new()
		tr.origin = _forge_origin
		tr.dir = d
		tr.life = ForgeRules.trail_life(enraged)
		tr.dmg = data.damage * dmg_mult * ForgeRules.TRAIL_DMG
		tr.level = level
		tr.deal = not visual
		get_parent().add_child(tr)
	if visual:
		return
	for p in _boss_pool():
		if p.dead:
			continue
		if ForgeRules.in_cone(_forge_origin, _forge_dir, p.global_position):
			p.take_damage(vs(level, p, data.damage * dmg_mult * 1.5), _forge_origin)


func _vent_warn(elapsed: float) -> void:
	var c := _net_pos if puppet else global_position
	FX.telegraph(c, ForgeRules.VENT_R, maxf(0.2, _hit_time() - elapsed))
	Sfx.play_at("fire", c, 0.1, -2.0)


## Respiro da Fornalha: labaredas saem pelas frestas e queimam todos em volta dele.
func _forge_vent(visual: bool) -> void:
	var c := _net_pos if puppet else global_position
	Sfx.play_at("explode", c, 0.1, -3.0)
	ForgeFX.vent_burst(c, ForgeRules.VENT_R)
	if visual:
		return
	for p in _boss_pool():
		if p.dead:
			continue
		if Vector2(p.global_position.x - c.x, p.global_position.z - c.z).length() <= ForgeRules.VENT_R:
			p.take_damage(vs(level, p, data.damage * dmg_mult * 1.2), c)


func _shield_warn(elapsed: float) -> void:
	var c := _net_pos if puppet else global_position
	FXToon.rune_circle(c, FORGE_WARD_R * 1.3, 0.3, maxf(0.2, _hit_time() - elapsed))
	Sfx.play_at("arcane_cast", c, 0.0, 0.0)


## O punho bate no chão e o Escudo Rúnico sobe: as runas nascem espalhadas pela sala (só quem manda nele: o
## servidor anuncia cada uma aos clientes como um monstro comum, e o escudo vai no snapshot).
func _forge_shield_up() -> void:
	if puppet:
		return
	_forge_shields += 1
	_forge_set_shield(true)
	var facing := model_forward()
	if _tgt != null and is_instance_valid(_tgt):
		var to := Vector3(_tgt.global_position.x - home.x, 0.0, _tgt.global_position.z - home.z)
		if to.length() > 2.0:
			facing = to
	var parent := get_parent()
	for pt in ForgeRules.rune_points(boss_seed, home, facing):
		var at := Vector3(pt.x, global_position.y + 0.3, pt.z)
		if arena.has_area():   # nunca fora da sala dele
			at.x = clampf(at.x, arena.position.x + 2.0, arena.end.x - 2.0)
			at.z = clampf(at.z, arena.position.y + 2.0, arena.end.y - 2.0)
		var e: Enemy = (get_script() as GDScript).new()
		e.kind = RUNE_KIND
		e.level = level
		e.area = area
		e.arena = arena
		e.position = at
		parent.add_child(e)
		ForgeFX.rune_pop(at, false)


## Runas vivas do escudo por perto.
func _runes_near() -> Array:
	var out := []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Enemy and e.kind == RUNE_KIND and not e.dead and e.global_position.distance_to(global_position) < 70.0:
			out.append(e)
	return out


## Liga/desliga o escudo (servidor/solo: pela regra; réplica: pelo bit do snapshot): a torre de luz em volta dele,
## o aviso na tela de quem está na luta e o som.
func _forge_set_shield(on: bool, quiet := false) -> void:
	if on == shielded:
		return
	shielded = on
	var c := _net_pos if puppet else global_position
	var lp := _local_player()
	var near: bool = lp != null and lp.global_position.distance_to(c) < 45.0
	if on:
		_forge_ward = ForgeFX.ward(self, FORGE_WARD_R, FORGE_WARD_H)
		Sfx.play_at("anvil", c, 0.0, 2.0)
		if near and not quiet:
			Game.notify.emit("Escudo Rúnico! Quebrem as %d runas da sala." % ForgeRules.RUNES, Color(1.0, 0.75, 0.3))
	else:
		ForgeFX.ward_drop(_forge_ward, c, FORGE_WARD_R, FORGE_WARD_H)
		_forge_ward = null
		_forge_since = 0.0
		if not quiet:
			Sfx.play_at("explode", c, 0.1, -2.0)
			if near:
				Game.notify.emit("O Escudo Rúnico caiu!", Color(1.0, 0.9, 0.5))
				if lp.has_method("add_shake"):
					lp.add_shake(0.4)


## Golpe que bate no escudo: nada entra; um "Imune" e faíscas (no máximo um a cada 0,4 s).
func _forge_immune(from_pos: Vector3) -> void:
	if _forge_immune_t > 0.0:
		return
	_forge_immune_t = 0.4
	var top: Vector3 = global_position + Vector3.UP * (data.height * data.scale + 0.2)
	FX.damage_number(top, "Imune", ForgeFX.AMBER, 44)
	Sfx.play_at("anvil", global_position, 0.25, -9.0)
	var out := Vector3(from_pos.x - global_position.x, 0.0, from_pos.z - global_position.z)
	if out.length() > 0.1 and DisplayServer.get_name() != "headless":
		out = out.normalized()
		FXToon.impact_sparks(global_position + out * FORGE_WARD_R + Vector3.UP * 1.6, out, 4, 60.0, ForgeFX.RUNE)


## Entrada de chefe: a primeira vez que ele parte para cima perto deste jogador, o chão treme e o nome aparece
## em destaque. De novo só depois de um reset.
func _forge_intro() -> void:
	if _intro_shown:
		return
	var lp := _local_player()
	if lp == null or lp.global_position.distance_to(global_position) > 32.0:
		return
	_intro_shown = true
	if lp.has_method("add_shake"):
		lp.add_shake(0.7)
	Sfx.play_at("anvil", global_position, 0.0, 3.0)
	Sfx.play_at("slam", global_position, 0.0)
	var w := get_tree().current_scene
	var hud = w.get("hud") if w != null else null
	if hud != null and hud.get("region_banner") != null:
		hud.region_banner.show_area(data.name, "Chefe das Galerias Profundas")


## Todo quadro de física: o relógio do escudo e da próxima vez, a cor de brasa da fase 2 e, a cada FORGE_TICK s,
## as correntes de luz das runas até ele, a queda do escudo quando não sobra runa e o reset da luta. A runa sem
## Forjador de escudo erguido por perto se desfaz (some sem recompensa).
func _forge_process(delta: float) -> void:
	_forge_immune_t = maxf(0.0, _forge_immune_t - delta)
	if data.get("rune", false):
		_forge_t -= delta
		if _forge_t > 0.0:
			return
		_forge_t = FORGE_TICK
		if puppet:
			return
		for e in get_tree().get_nodes_in_group("enemies"):
			if e is Enemy and e.ai() == "forge" and not e.dead and e.shielded \
					and e.global_position.distance_to(global_position) < 70.0:
				return
		wither()
		return
	if not puppet and not shielded and state in ["chase", "attack"]:
		_forge_since += delta
	if state in ["chase", "attack"]:
		_forge_intro()
	if enraged != _fury_look:
		_set_fury_look(enraged)   # superaquecido: fornalha, runas e frestas em brasa
	_forge_t -= delta
	if _forge_t > 0.0:
		return
	_forge_t = FORGE_TICK
	var runes := _runes_near()
	if shielded:
		var heart := global_position + Vector3.UP * 2.3 * float(data.scale)
		for r in runes:
			ForgeFX.rune_link(r.global_position + Vector3.UP * 1.3, heart)
	if puppet:
		return
	if shielded and ForgeRules.shield_down(runes.size()):
		_forge_set_shield(false)
	# a luta acabou (voltou para casa e se curou): escudo, runas, fase e contadores voltam ao começo
	if state in ["idle", "wander"] and hp >= max_hp and (shielded or enraged or _forge_shields > 0 or _forge_n > 0):
		_forge_set_shield(false, true)
		for r in runes:
			r.wither()
		_forge_shields = 0
		_forge_n = 0
		_forge_since = 0.0
		enraged = false
		_intro_shown = false


## Forjador: passada pesada de pedra (o joelho dobra quando a perna volta; cada pisada levanta poeira e fagulhas
## e treme a tela), braço esquerdo balançando com atraso, o martelo em pé na mão direita oscilando no próprio
## tempo com a corrente pendurada, escarcelas que abrem com as pernas, correntes do cinto em pêndulo, a tampa da
## chaminé batendo, as labaredas tremendo e o tronco respirando como um fole; as chaminés soltam fuligem.
## Golpes: a Martelada arma com o corpo indo para trás e para baixo e o martelo subindo por cima do ombro, depois
## desce em arco e fica cravado no chão; o Respiro recua, escancara a porta da fornalha e estufa o peito; o
## Escudo ergue o punho esquerdo e o crava no chão. Superaquecido: porta entreaberta, tampa batendo sem parar,
## tremor. Rotação x positiva: topo para a frente, perna/braço para trás, queixo abre.
func _animate_forge(hspeed: float, s: float, k: float) -> void:
	var body: Node3D = parts.Body
	if not _rig.has("body_rest"):
		_rig["body_rest"] = body.position
		_rig["step"] = 0.0
		_rig["puff"] = 0.0
		_rig["hot"] = false
		_rig["sparks"] = ForgeFX.sparks(parts.Fire) if parts.get("Fire") != null and not puppet_headless() else null
	var hot := enraged
	var amp := clampf(hspeed / 2.0, 0.0, 1.0)
	var idle := 1.0 - amp
	var c := cos(anim_t)
	var lt := _life_t
	var kf := 1.0 - pow(1.0 - k, 3.0)   # golpes: mais firme que o balanço
	var leg := s * 0.4 * amp
	var knee_l := maxf(0.0, c) * 0.65 * amp + 0.04
	var knee_r := maxf(0.0, -c) * 0.65 * amp + 0.04
	var arm_l := -s * 0.26 * amp - 0.05 + sin(lt * 0.7) * 0.03 * idle
	var arm_r := 0.04 + sin(lt * 0.7 + 1.3) * 0.02 * idle + s * 0.05 * amp   # o braço do martelo quase não balança
	var arm_lz := 0.0
	var arm_rz := 0.0
	var elb_l := -0.22 - c * 0.16 * amp - sin(lt * 0.6) * 0.05 * idle
	var elb_r := -0.3
	var hand_l := 0.1 + sin(lt * 0.9) * 0.1 * idle
	# ângulo do cabo do martelo no mundo (0 = em pé, positivo = tomba para a frente): apoiado um pouco para trás
	var ham := -0.14 + sin(lt * 0.5) * 0.035 * idle + sin(anim_t - 1.0) * 0.08 * amp
	var body_x := 0.05 + sin(lt * 0.5) * 0.02 * idle
	var body_y := s * 0.06 * amp
	var body_z := s * 0.045 * amp
	var off := Vector3(0.0, -absf(s) * 0.09 * amp + sin(lt * 1.0) * 0.03 * idle, 0.0)
	var head_x := sin(lt * 0.45 + 0.7) * 0.03 * idle
	var head_y := sin(lt * 0.3) * 0.14 * idle
	var jaw := 0.02 + maxf(0.0, sin(lt * 1.1)) * 0.05
	var door := 0.45 if hot else 0.0
	var fire := 1.0 + sin(lt * 9.0) * 0.12 + sin(lt * 14.3) * 0.08 + (0.45 if hot else 0.0)
	var lid := maxf(0.0, sin(lt * (6.0 if hot else 2.2))) * (0.55 if hot else 0.16)
	var shake := 0.3 if hot else 0.0
	if state == "attack":
		var t := attack_timer
		var ht := _hit_time()
		var u := clampf(t / ht, 0.0, 1.0)
		var e := u * u * (3.0 - 2.0 * u)
		k = kf
		match attack_kind:
			"hammer":
				var arm_t := ht * 0.78
				if t < arm_t:   # arma: recua e afunda, o tronco vira para o lado do martelo e ele sobe por cima do ombro
					var w := clampf(t / arm_t, 0.0, 1.0)
					w = w * w * (3.0 - 2.0 * w)
					off = Vector3(0.0, -0.24 * w, -0.42 * w)
					body_x = -0.2 * w
					body_y = -0.3 * w
					arm_r = -2.1 * w
					elb_r = -0.3 - 0.5 * w
					ham = -0.14 - 0.95 * w
					arm_l = 0.45 * w
					elb_l = -0.5 * w
					knee_l = 0.3 * w
					knee_r = 0.3 * w
					leg = 0.12 * w
					jaw = 0.3 * w
					head_x = -0.12 * w
					lid = 0.5 * w
				elif t < ht + 0.75:   # desce em arco e fica cravado no chão à frente
					var w := clampf((t - arm_t) / maxf(ht - arm_t, 0.01), 0.0, 1.0)
					w = w * w
					off = Vector3(0.0, -0.24, -0.42).lerp(Vector3(0.0, -0.26, 0.5), w)
					body_x = lerpf(-0.2, 0.34, w)
					body_y = lerpf(-0.3, 0.12, w)
					arm_r = lerpf(-2.1, -1.0, w)
					elb_r = lerpf(-0.8, -0.1, w)
					ham = lerpf(-1.09, 1.78, w)
					arm_l = 0.5
					elb_l = -0.3
					knee_l = 0.35
					knee_r = 0.35
					jaw = 0.42
					head_x = 0.1
					shake = maxf(shake, 1.0 if t >= ht and t < ht + 0.25 else 0.0)
					k = 1.0 - pow(1.0 - k, 2.0)
			"vent":
				if t < ht:   # recua, braços abrem, a porta escancara e o fogo cresce
					off = Vector3(0.0, -0.14 * e, -0.3 * e)
					body_x = -0.26 * e
					arm_lz = 0.5 * e
					arm_rz = -0.3 * e
					arm_l = 0.2 * e
					elb_l = -0.6 * e
					door = 1.9 * e
					fire = 1.0 + 1.7 * e
					jaw = 0.5 * e
					head_x = -0.2 * e
					shake = maxf(shake, e)
					lid = 0.6
				elif t < ht + 0.55:   # estufa o peito para a frente e solta as labaredas
					off = Vector3(0.0, 0.06, 0.3)
					body_x = 0.3
					arm_lz = 0.7
					arm_rz = -0.35
					elb_l = -0.2
					door = 2.1
					fire = 2.8
					jaw = 0.6
					shake = 1.0
			"rune_shield":
				var up_t := ht * 0.72
				if t < up_t:   # ergue o punho esquerdo, o tronco recua
					var w := clampf(t / up_t, 0.0, 1.0)
					w = w * w * (3.0 - 2.0 * w)
					off = Vector3(0.0, -0.1 * w, -0.25 * w)
					body_x = -0.18 * w
					body_y = 0.25 * w
					arm_l = -2.7 * w
					elb_l = -0.3 * w
					hand_l = 0.7 * w
					head_x = -0.18 * w
					jaw = 0.3 * w
				elif t < ht + 0.6:   # crava o punho no chão: o círculo de runas se fecha e o escudo sobe
					var w := clampf((t - up_t) / maxf(ht - up_t, 0.01), 0.0, 1.0)
					w = w * w
					off = Vector3(0.0, -0.1, -0.25).lerp(Vector3(0.0, -0.42, 0.34), w)
					body_x = lerpf(-0.18, 0.62, w)
					body_y = lerpf(0.25, -0.1, w)
					arm_l = lerpf(-2.7, -0.75, w)
					elb_l = -0.15
					hand_l = 0.7
					knee_l = 0.45
					knee_r = 0.45
					jaw = 0.45
					shake = maxf(shake, 1.0 if t >= ht and t < ht + 0.25 else 0.0)
					k = 1.0 - pow(1.0 - k, 2.0)
	if stagger > 0.0 or _flash_t > 0.0:
		shake = maxf(shake, 0.6)
	var sh := shake * sin(lt * 37.0)
	var sh2 := shake * sin(lt * 29.0 + 1.0)
	body_z += sh * 0.012
	# pisada: poeira, fagulhas e o tranco em quem está perto
	if amp > 0.35 and state != "attack":
		var step := signf(s)
		if step != 0.0 and step != float(_rig.step):
			_rig.step = step
			_forge_step("KneeL" if step > 0.0 else "KneeR")
	# chaminés: fuligem de tempos em tempos (sem parar e com fogo quando superaquecido)
	if lt - float(_rig.puff) > (0.16 if hot else 0.5) and is_inside_tree() and not puppet_headless():
		_rig.puff = lt
		var st: Node3D = parts.get("Stack%d" % (randi() % 3))
		if st != null:
			ForgeFX.stack_puff(st.global_position, hot)
	if hot != bool(_rig.hot):
		_rig.hot = hot
		var sp: CPUParticles3D = _rig.sparks
		if sp != null:
			sp.amount = 44 if hot else 18
	parts.LegL.rotation.x = lerp(parts.LegL.rotation.x, leg, k)
	parts.LegR.rotation.x = lerp(parts.LegR.rotation.x, -leg if state != "attack" else leg, k)
	parts.ArmL.rotation.x = lerp(parts.ArmL.rotation.x, arm_l, k)
	parts.ArmR.rotation.x = lerp(parts.ArmR.rotation.x, arm_r, k)
	parts.ArmL.rotation.z = lerp(parts.ArmL.rotation.z, arm_lz, k)
	parts.ArmR.rotation.z = lerp(parts.ArmR.rotation.z, arm_rz, k)
	# o cabo: o punho dobra o que der e o resto gira o martelo dentro da mão
	var hand_r := clampf(ham - body_x - arm_r - elb_r, -0.7, 0.7)
	var ham_x := ham - body_x - arm_r - elb_r - hand_r
	for pair in [["KneeL", knee_l], ["KneeR", knee_r], ["ElbowL", elb_l], ["ElbowR", elb_r], ["HandL", hand_l],
			["HandR", hand_r], ["Hammer", ham_x]]:
		var j: Node3D = parts.get(pair[0])
		if j:
			j.rotation.x = lerp_angle(j.rotation.x, float(pair[1]), k)
	body.rotation.x = lerp(body.rotation.x, body_x, k)
	body.rotation.y = lerp(body.rotation.y, body_y, k)
	body.rotation.z = lerp(body.rotation.z, body_z, k)
	body.position = body.position.lerp(_rig.body_rest + off, k)
	if parts.Head:
		parts.Head.rotation.x = lerp(parts.Head.rotation.x, head_x + sh2 * 0.02, k)
		parts.Head.rotation.y = lerp(parts.Head.rotation.y, head_y, k)
	if parts.Jaw:
		parts.Jaw.rotation.x = lerp(parts.Jaw.rotation.x, jaw + absf(sh) * 0.08, k)
	var dn: Node3D = parts.get("Door")
	if dn:
		dn.rotation.y = lerp(dn.rotation.y, door + sh * 0.06, k)
	var fn: Node3D = parts.get("Fire")
	if fn:
		fn.scale = fn.scale.lerp(Vector3(1.0 + (fire - 1.0) * 0.3, fire, 1.0 + (fire - 1.0) * 0.3), k)
	var ln: Node3D = parts.get("Lid")
	if ln:
		ln.rotation.x = lerp(ln.rotation.x, lid + absf(sh2) * 0.2, k)
	# escarcelas: as da frente abrem quando a perna de baixo vem para a frente, as de trás quando ela volta
	var leg_l: float = parts.LegL.rotation.x
	var leg_r: float = parts.LegR.rotation.x
	for i in 4:
		var tn: Node3D = parts.get("Tasset%d" % i)
		if tn:
			var lr := leg_l if i in [0, 3] else leg_r
			var push := minf(0.0, lr) * 0.9 if i < 2 else maxf(0.0, lr) * 0.9
			tn.rotation.x = lerp(tn.rotation.x, push + sin(anim_t - 1.2 + i) * 0.07 * amp + sin(lt * 1.3 + i * 1.7) * 0.02
				- body_x * 0.6 + sh * 0.05, k)
	# correntes do cinto e a do martelo: pêndulos que ficam para trás e voltam, cada uma no seu tempo
	for i in 2:
		var cn: Node3D = parts.get("Chain%d" % i)
		if cn:
			var ph := i * 2.1
			cn.rotation.x = lerp(cn.rotation.x, sin(lt * 1.4 + ph) * 0.06 + sin(anim_t - 1.5 + ph) * 0.3 * amp - body_x * 0.8
				+ sh * 0.2, k)
			cn.rotation.z = lerp(cn.rotation.z, sin(lt * 1.1 + ph) * 0.05 - body_z * 1.2 + sh2 * 0.15, k)
	var hc: Node3D = parts.get("HammerChain")
	if hc:
		hc.rotation.x = lerp_angle(hc.rotation.x, clampf(-ham, -2.2, 1.3) + sin(lt * 1.7) * 0.08 + sin(anim_t - 1.8) * 0.2 * amp, k * 0.6)
		hc.rotation.z = lerp(hc.rotation.z, sin(lt * 1.2 + 0.6) * 0.07 + sh * 0.2, k)


## Pisada: poeira de pedra, fagulhas do ferro no chão, o som e um tranco em quem está perto.
func _forge_step(knee: String) -> void:
	var kn: Node3D = parts.get(knee)
	if kn == null or not is_inside_tree() or puppet_headless():
		return
	var at := Vector3(kn.global_position.x, global_position.y + 0.1, kn.global_position.z) + model_forward() * 0.3
	FX.burst(at, Color(0.4, 0.36, 0.33), 8, 2.6, 0.13, 0.5)
	FX.burst(at, Color(1.0, 0.6, 0.2), 4, 3.2, 0.06, 0.4)
	Sfx.play_at("chop_stone", at, 0.2, -10.0)
	var lp := _local_player()
	if lp != null and lp.has_method("add_shake") and lp.global_position.distance_to(global_position) < 14.0:
		lp.add_shake(0.1)


## Runa do escudo: brota do chão, pulsa e balança devagar; treme quando leva pancada.
func _animate_rune(k: float) -> void:
	var body: Node3D = parts.Body
	if body == null:
		return
	var lt := _life_t
	var rise := clampf(lt / 0.45, 0.0, 1.0)
	rise = 1.0 - (1.0 - rise) * (1.0 - rise)
	var hit := 1.0 if _flash_t > 0.0 else 0.0
	body.position.y = lerpf(-1.7, 0.0, rise)
	body.rotation.z = lerp(body.rotation.z, sin(lt * 1.3) * 0.025 + hit * sin(lt * 41.0) * 0.07, k)
	body.rotation.x = lerp(body.rotation.x, sin(lt * 1.1 + 0.8) * 0.02 + hit * sin(lt * 33.0) * 0.06, k)
	body.scale = Vector3.ONE * (1.0 + sin(lt * 3.2) * 0.02)


## Réplica: começa a desenhar um golpe do Forjador que o snapshot acabou de trazer (`atk_t` s já passados).
func _forge_replica_start(flags: int, atk_t: float) -> void:
	match attack_kind:
		"hammer":
			_forge_origin = _net_pos
			var off := ThrowRules.unpack_offset(flags)
			_forge_dir = off.normalized() if off.length() > 0.01 else Vector3(sin(_net_yaw), 0.0, cos(_net_yaw))
			_hammer_warn(atk_t)
		"vent":
			_vent_warn(atk_t)
		"rune_shield":
			_shield_warn(atk_t)


# ------------------------------------------------------------ Sentinela da Nevasca (chefe do Pico)
## Regras em BlizzardRules. Patada perto (pega todos na frente dela), Sopro Congelante em cone que gira (dano,
## lentidão e apaga braseiros), Estacas de Gelo que caem do teto e ficam no chão soltando frio e, na fúria, a
## Nevasca: quem fica longe de um braseiro aceso vai congelando. O servidor (ou o solo) decide e dá o dano; a
## réplica refaz o desenho pela direção/semente do snapshot, e os braseiros acesos vêm nos bits altos de `flags`.
const SENTINEL_GAIT := {"FL": 0.0, "BR": 0.25, "FR": 0.5, "BL": 0.75}
const SENTINEL_STANCE := 0.68
const PAW_RADIUS := 3.2


## Monta a luta (uma vez, no primeiro quadro: a casa dela já está no lugar): a sala, os quatro braseiros e a neve.
func _sentinel_setup() -> void:
	_blz_ready = true
	_blz_room = _sentinel_room()
	_blz_floor = _sentinel_floor()
	_blz_pts = BlizzardRules.brazier_points(_blz_room, _blz_floor)
	_blz_relight = []
	for pt in _blz_pts:
		_blz_relight.append(0.0)
		var b := BlizzardBrazier.new()
		b.top_level = true
		add_child(b)
		b.global_position = pt
		_blz_braziers.append(b)
	_blz_snow = BlizzardFX.snowstorm(self, _blz_room, _blz_floor)


## A sala da luta (x, z do mundo): a arena do chefe (servidor/solo), a sala de chefe do mapa onde ela está (réplica:
## o portal de volta que o mapa monta em cada sala de chefe guarda o retângulo) ou, fora de sala, a sala padrão.
func _sentinel_room() -> Rect2:
	if arena.has_area():
		return arena
	var w := get_tree().current_scene
	if w != null:
		for c in w.get_children():
			if str(c.name).begins_with("BossPortal_") and c.get("arena") is Rect2 \
					and (c.get("arena") as Rect2).has_point(Vector2(home.x, home.z)):
				return c.get("arena")
	return BlizzardRules.default_room(home)


## Altura do chão debaixo da casa dela.
func _sentinel_floor() -> float:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(home + Vector3.UP * 2.0, home - Vector3.UP * 6.0, 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			return (hit.position as Vector3).y
	return home.y


func _in_sentinel_room(p: Vector3) -> bool:
	return _blz_room.has_point(Vector2(p.x, p.z))


## Braseiros acesos (bit i = braseiro i): vai no snapshot.
func brazier_mask() -> int:
	return BlizzardRules.lit_mask(_blz_relight) if _blz_ready else BlizzardRules.MASK_ALL


## Acende/apaga os braseiros conforme `mask` (o servidor/solo pelos relógios, a réplica pelo snapshot).
func _sentinel_braziers(mask: int) -> void:
	if mask == _blz_mask:
		return
	_blz_mask = mask
	for i in _blz_braziers.size():
		(_blz_braziers[i] as BlizzardBrazier).set_lit(mask & (1 << i) != 0)


## Réplica: os braseiros acesos que o snapshot trouxe.
func _blizzard_snapshot(flags: int) -> void:
	if not _blz_ready:
		_sentinel_setup()
	_sentinel_braziers(BlizzardRules.unpack_mask(flags))


func _sentinel_storm(on: bool) -> void:
	if on == _blz_storm:
		return
	_blz_storm = on
	for b in _blz_braziers:
		(b as BlizzardBrazier).set_storm(on)
	if _blz_snow != null:
		_blz_snow.emitting = on


## A cada quadro: os relógios dos braseiros, a entrada da luta e a Nevasca (a exposição de cada jogador da sala, o
## dano e a lentidão que crescem com ela; só o servidor/solo dá o dano, toda tela mostra a neve e a geada).
func _blizzard_process(delta: float) -> void:
	if not _blz_ready:
		_sentinel_setup()
	if dead:
		_sentinel_storm(false)
		if _breath_cone != null and is_instance_valid(_breath_cone):
			_breath_cone.finish()
		return
	var fighting := state in ["chase", "attack"]
	if puppet:
		if not enraged:
			_blz_roared = false
		elif state == "attack" and attack_kind != "blizzard":
			_blz_roared = true   # chegou com a luta andando: a nevasca já sopra
	else:
		if not fighting and hp >= max_hp and (enraged or _blz_n > 0):
			# ninguém na sala e ela curada: a luta recomeça do zero
			enraged = false
			_blz_roar = false
			_blz_roared = false
			_blz_n = 0
			_blz_breaths = 0
			_blz_relight = BlizzardRules.relight_step(_blz_relight, 1000.0)
		if enraged and not _blz_roared and not _blz_roar and not (state == "attack" and attack_kind == "blizzard"):
			_blz_roar = true   # a fúria começou: o próximo golpe chama a nevasca
		_blz_relight = BlizzardRules.relight_step(_blz_relight, delta)
		_sentinel_braziers(BlizzardRules.lit_mask(_blz_relight))
	if state != "attack" and _breath_cone != null and is_instance_valid(_breath_cone):
		_breath_cone.finish()
	if fighting and not _blz_intro:
		_sentinel_intro()
	elif not fighting and hp >= max_hp:
		_blz_intro = false
	var storm := enraged and fighting and _blz_roared
	_sentinel_storm(storm)
	if not storm:
		_blz_exposure.clear()
		_blz_local = 0.0
		return
	_blz_gust_t -= delta
	if _blz_gust_t <= 0.0:
		_blz_gust_t = 0.22
		BlizzardFX.storm_gust(_blz_room, _blz_floor)
	_blz_tick -= delta
	if _blz_tick > 0.0:
		return
	_blz_tick = BlizzardRules.BLIZZARD_TICK
	# a geada no jogador desta tela (só o desenho: cada tela faz a mesma conta com os mesmos braseiros)
	var lp := _local_player()
	if lp != null and not lp.get("dead") and _in_sentinel_room(lp.global_position):
		_blz_local = BlizzardRules.exposure_step(_blz_local, BlizzardRules.BLIZZARD_TICK,
			BlizzardRules.sheltered(lp.global_position, _blz_pts, _blz_mask))
		if _blz_local > 0.12:
			BlizzardFX.frostbite(lp.global_position, _blz_local)
	else:
		_blz_local = 0.0
	if puppet:
		return
	var tick: float = data.damage * dmg_mult * 0.45
	for p in _boss_pool():
		var id: int = p.get_instance_id()
		if p.dead or not _in_sentinel_room(p.global_position):
			_blz_exposure.erase(id)
			continue
		var safe := BlizzardRules.sheltered(p.global_position, _blz_pts, _blz_mask)
		var e := BlizzardRules.exposure_step(float(_blz_exposure.get(id, 0.0)), BlizzardRules.BLIZZARD_TICK, safe)
		_blz_exposure[id] = e
		if safe or e <= 0.0:
			continue
		p.take_damage(vs(level, p, BlizzardRules.blizzard_damage(tick, e)), p.global_position + Vector3.UP * 3.0)
		var chill := BlizzardRules.blizzard_chill(e)
		if chill > 0.0 and p.has_method("apply_chill"):
			p.apply_chill(chill)


## Entrada da luta: a primeira vez que ela parte para cima perto deste jogador, a tela treme e o nome aparece em
## destaque (o letreiro das regiões). De novo só depois de um reset.
func _sentinel_intro() -> void:
	var lp := _local_player()
	if lp == null or lp.global_position.distance_to(global_position) > 30.0:
		return
	_blz_intro = true
	if lp.has_method("add_shake"):
		lp.add_shake(0.7)
	Sfx.play_at("frost", global_position, 0.0, 2.0)
	var w := get_tree().current_scene
	var hud = w.get("hud") if w != null else null
	if hud != null and hud.get("region_banner") != null:
		hud.region_banner.show_area(data.name, "Guardiã do Pico")


func _sentinel_begin(dist: float) -> void:
	if not _blz_ready:
		_sentinel_setup()
	attack_kind = BlizzardRules.attack(_blz_n, dist, float(data.reach), _blz_roar)
	if attack_kind != "blizzard":
		_blz_n += 1
	match attack_kind:
		"swing":
			_paw_warn(0.0)
		"breath":
			var aim := model.rotation.y
			if _tgt != null and is_instance_valid(_tgt):
				var to: Vector3 = _tgt.global_position - global_position
				if Vector2(to.x, to.z).length() > 0.05:
					aim = BlizzardRules.yaw_of(to)
			var sgn := BlizzardRules.sweep_sign(_blz_breaths)
			_blz_breaths += 1
			# a mesma conta que a réplica faz com o snapshot (a direção vai em 256 passos)
			var off := BlizzardRules.breath_offset(BlizzardRules.breath_start(aim, sgn, enraged), sgn)
			var got := BlizzardRules.breath_unpack(ThrowRules.unpack_offset(ThrowRules.pack_flags(0, off)))
			_breath_start = got[0]
			_breath_sign = got[1]
			throw_point = global_position + BlizzardRules.breath_offset(_breath_start, _breath_sign)
			model.rotation.y = _breath_start
			_breath_warn(0.0)
		"icicles":
			boss_seed = randi() & 0xFFFF
			_spike_pts = _spike_targets(global_position)
			_spikes_warn(0.0)
		"blizzard":
			_blz_roar = false
			_roar_warn(0.0)


## Réplica: começa a desenhar um golpe dela que o snapshot acabou de trazer (`atk_t` s já passados).
func _sentinel_replica_start(flags: int, atk_t: float) -> void:
	if not _blz_ready:
		_sentinel_setup()
	match attack_kind:
		"swing":
			_paw_warn(atk_t)
		"breath":
			var got := BlizzardRules.breath_unpack(ThrowRules.unpack_offset(flags))
			_breath_start = got[0]
			_breath_sign = got[1]
			_breath_warn(atk_t)
		"icicles":
			boss_seed = BossRules.unpack_seed(flags)
			_spike_pts = _spike_targets(_net_pos)
			_spikes_warn(atk_t)
		"blizzard":
			_roar_warn(atk_t)


## Centro da patada: à frente dela (fica onde foi avisado, mesmo que ela dê um passo enquanto arma).
func _paw_warn(elapsed: float) -> void:
	var c := _net_pos if puppet else global_position
	_paw_at = c + model_forward() * 3.4 * float(data.scale)
	FX.telegraph(_paw_at, PAW_RADIUS, maxf(0.2, _hit_time() - elapsed))


## A pata desce: o chão racha em gelo; pega todos dentro do círculo avisado e os deixa lentos.
func _sentinel_paw(visual: bool) -> void:
	var c := _paw_at
	Sfx.play_at("slam", c, 0.1, -1.0)
	FXToon.slam(c, PAW_RADIUS)
	BlizzardFX.spike_impact(c, PAW_RADIUS * 0.8)
	var lp := _local_player()
	if lp != null and lp.has_method("add_shake") and lp.global_position.distance_to(c) < 16.0:
		lp.add_shake(0.35)
	if visual:
		return
	for p in _boss_pool():
		if p.dead:
			continue
		if Vector2(p.global_position.x - c.x, p.global_position.z - c.z).length() <= PAW_RADIUS:
			p.take_damage(vs(level, p, data.damage * dmg_mult * randf_range(1.0, 1.15)), global_position)
			if p.has_method("apply_chill"):
				p.apply_chill(1.5)


## Aviso do Sopro: o cone no chão (enche até ela soltar o ar) e o arco que ele vai varrer, com setas no sentido
## do giro. O desenho segue o cone até o fim do sopro.
func _breath_warn(elapsed: float) -> void:
	var c := _net_pos if puppet else global_position
	if _breath_cone != null and is_instance_valid(_breath_cone):
		_breath_cone.finish()
	_breath_cone = BlizzardFX.cone_warning(Vector3(c.x, _blz_floor, c.z), BlizzardRules.BREATH_RANGE,
		BlizzardRules.BREATH_HALF, self)
	_breath_fx_t = 0.0
	if elapsed < BlizzardRules.BREATH_T0:
		Sfx.play_at("staff_wind", c, 0.0, 3.0)


## O Sopro a cada quadro entre t0 e t1: gira o cone (e ela com ele), move o aviso, solta o jato de frio e, a cada
## BREATH_TICK s, acerta quem está dentro (dano e lentidão) e apaga os braseiros no caminho.
func _breath_tick(visual: bool, t0: float, t1: float) -> void:
	var c := _net_pos if puppet else global_position
	var ang := BlizzardRules.breath_angle(_breath_start, _breath_sign, t1, enraged)
	if not puppet:
		model.rotation.y = ang
		throw_point = global_position + BlizzardRules.breath_offset(_breath_start, _breath_sign)
	var t_end := BlizzardRules.BREATH_T0 + BlizzardRules.BREATH_TIME
	if _breath_cone != null and is_instance_valid(_breath_cone):
		_breath_cone.global_position = Vector3(c.x, _blz_floor + 0.07, c.z)
		_breath_cone.yaw = ang
		_breath_cone.ahead = BlizzardRules.breath_angle(_breath_start, _breath_sign, t_end, enraged) - ang
		_breath_cone.reveal = clampf(t1 / BlizzardRules.BREATH_T0, 0.0, 1.0)
		if t1 > t_end:
			_breath_cone.finish()
	if not BlizzardRules.breath_active(t1):
		return
	var first := t0 < BlizzardRules.BREATH_T0
	if first:
		Sfx.play_at("frost", c, 0.05, 2.0)
		var lp := _local_player()
		if lp != null and lp.has_method("add_shake") and lp.global_position.distance_to(c) < 30.0:
			lp.add_shake(0.45)
	_breath_fx_t -= t1 - t0
	if _breath_fx_t <= 0.0 and not puppet_headless():
		_breath_fx_t = 0.07
		var mz: Node3D = parts.get("Muzzle")
		var mouth: Vector3 = mz.global_position if mz != null else c + Vector3.UP * 2.0
		BlizzardFX.breath_gust(mouth, _blz_floor, ang, BlizzardRules.BREATH_RANGE, BlizzardRules.BREATH_HALF)
	if visual:
		return
	var k0 := floori((t0 - BlizzardRules.BREATH_T0) / BlizzardRules.BREATH_TICK)
	var k1 := floori((t1 - BlizzardRules.BREATH_T0) / BlizzardRules.BREATH_TICK)
	if not first and k1 == k0:
		return
	for p in _boss_pool():
		if not p.dead and BlizzardRules.in_cone(c, ang, p.global_position):
			p.take_damage(vs(level, p, data.damage * dmg_mult * 0.3), c)
			if p.has_method("apply_chill"):
				p.apply_chill(BlizzardRules.BREATH_CHILL)
	var out := BlizzardRules.cone_braziers(c, ang, _blz_pts)
	for i in _blz_relight.size():
		if out & (1 << i) != 0 and float(_blz_relight[i]) <= 0.0:
			_blz_relight[i] = BlizzardRules.RELIGHT
	_sentinel_braziers(BlizzardRules.lit_mask(_blz_relight))


## Pontos das Estacas: sorteados pela semente em volta dela (mais duas na fúria) e um sob cada jogador que esteja
## na sala (servidor e réplica sabem sem trocar nada).
func _spike_targets(center: Vector3) -> Array:
	var at := Vector3(center.x, _blz_floor, center.z)
	var pts := BlizzardRules.spike_points(boss_seed, at, _blz_room, BlizzardRules.SPIKES + (2 if enraged else 0))
	for p in get_tree().get_nodes_in_group("players"):
		if not p.dead and p.global_position.distance_to(center) < 25.0 and _in_sentinel_room(p.global_position):
			pts.append(BlizzardRules.clamp_to_room(Vector3(p.global_position.x, _blz_floor, p.global_position.z), _blz_room, 0.5))
	return pts


func _spikes_warn(elapsed: float) -> void:
	var left := maxf(0.2, _hit_time() - elapsed)
	for pt in _spike_pts:
		FX.telegraph(pt, BlizzardRules.SPIKE_R, left)
	var lp := _local_player()
	if lp != null and lp.has_method("add_shake") and lp.global_position.distance_to(global_position) < 30.0:
		lp.add_shake(0.5)   # o urro que solta o gelo do teto
	Sfx.play_at("slam", global_position, 0.0, 1.0)


## As estacas cravam: estilhaços em cada ponto e a estaca que fica no chão soltando frio (só o servidor/solo dá o
## dano, o da queda e o de quem encosta depois).
func _icicles_hit(visual: bool) -> void:
	for pt in _spike_pts:
		BlizzardFX.spike_impact(pt, BlizzardRules.SPIKE_R)
		var sp := IceSpike.new()
		sp.dmg = data.damage * dmg_mult * 0.2
		sp.level = level
		sp.deal = not visual
		get_parent().add_child(sp)
		sp.global_position = pt
	if not _spike_pts.is_empty():
		Sfx.play_at("frost", _spike_pts[0], 0.1, 0.0)
	if visual:
		return
	var dmg: float = data.damage * dmg_mult * 1.1
	for p in _boss_pool():
		if p.dead:
			continue
		for pt in _spike_pts:
			if Vector2(p.global_position.x - pt.x, p.global_position.z - pt.z).length() <= BlizzardRules.SPIKE_R:
				p.take_damage(vs(level, p, dmg), pt)
				if p.has_method("apply_chill"):
					p.apply_chill(2.0)
				break


func _roar_warn(elapsed: float) -> void:
	if elapsed > 0.5:
		return
	var lp := _local_player()
	if lp != null and lp.has_method("add_shake") and lp.global_position.distance_to(global_position) < 30.0:
		lp.add_shake(0.8)
	Sfx.play_at("frost", global_position, 0.0, 3.0)
	if FX._scene() != null:   # a cúpula de riscos de gelo abre em volta dela
		var c := _net_pos if puppet else global_position
		IceFX.roar(FX._scene(), Vector3(c.x, _blz_floor, c.z), 5.5)


## O urro termina: a nevasca toma a sala (os braseiros passam a mostrar o abrigo).
func _blizzard_roar(_visual: bool) -> void:
	_blz_roared = true
	var c := _net_pos if puppet else global_position
	FXToon.ring_wave(c + Vector3.UP * 0.15, 9.0, 0.2, BlizzardFX.RIME, 0.3)
	FXToon.ring_wave(c + Vector3.UP * 0.15, 16.0, 0.14, FXToon.MIST, 0.5, 0.12)
	for i in 8:
		var a := TAU * i / 8.0
		FXToon.puff(c + Vector3(cos(a) * 2.5, 1.5, sin(a) * 2.5), randf_range(2.4, 3.2), BlizzardFX.RIME if i % 2 else FXToon.MIST,
			{"vel": Vector3(cos(a) * 8.0, 0.5, sin(a) * 8.0), "grow": 0.15, "hold": 0.2, "fade": 0.6})
	Sfx.play_at("staff_wind", c, 0.0, 4.0)
	var lp := _local_player()
	if lp != null and lp.global_position.distance_to(c) < 40.0:
		Game.notify.emit("A nevasca começou! Fique perto de um braseiro aceso.", Color(0.6, 0.85, 1.0))


## Pisada de uma pata: neve levantada, lascas de gelo e um tranco em quem está perto.
func _sentinel_step(sd: String) -> void:
	var ft: Node3D = parts.get("Foot" + sd)
	if ft == null or not is_inside_tree() or puppet_headless():
		return
	var at := Vector3(ft.global_position.x, global_position.y + 0.1, ft.global_position.z)
	FX.burst(at, Color(0.85, 0.93, 1.0), 6, 2.2, 0.1, 0.45)
	if sd.begins_with("F"):
		FXToon.puff(at + Vector3.UP * 0.2, 0.9, FXToon.MIST, {"vel": Vector3(0, 0.5, 0), "grow": 0.12, "hold": 0.1, "fade": 0.4})
		var lp := _local_player()
		if lp != null and lp.has_method("add_shake") and lp.global_position.distance_to(global_position) < 14.0:
			lp.add_shake(0.07)


## Sentinela da Nevasca: passo pesado em quatro tempos com as patas de verdade (três ossos, IK do Lobo da Geada:
## o apoio fica no chão enquanto o corpo passa), o corpo balançando o peso de um lado para o outro, pescoço e
## cabeça compensando, a cauda em três ossos ondulando com atraso, as mechas da juba e as ombreiras de gelo
## respirando, lascas de geada caindo do corpo e o hálito frio saindo da boca.
## Golpes: a patada recolhe o corpo para trás e para baixo e ergue a pata direita, depois o corpo avança e a pata
## crava; o Sopro planta as patas, recua enchendo o peito com a cabeça no alto e as ombreiras abrindo, e solta o
## ar de cabeça baixa e boca escancarada, tremendo; as Estacas empinam nas traseiras urrando para o teto e batem as
## dianteiras no chão; a Nevasca é um urro longo de cabeça erguida, ombreiras abertas e cristais acesos.
## Rotação x positiva: frente do corpo/cabeça para baixo, cauda para cima, mecha para trás, queixo abre.
func _animate_sentinel(delta: float, hspeed: float) -> void:
	if not _wolf_setup():
		return
	if not _rig.has("hit"):
		_rig["hit"] = false
		_rig["breath_t"] = randf_range(1.0, 3.0)
		if parts.get("Crest") != null and not puppet_headless():
			_rig["frost"] = BlizzardFX.frost_fall(parts.Crest, 1.5)
	var sc: float = float(data.scale) * size_mult
	var k := 1.0 - exp(-10.0 * delta)
	var kf := 1.0 - exp(-22.0 * delta)
	var ks := 1.0 - exp(-5.0 * delta)        # peças soltas: chegam atrasadas
	_gait_amp = lerpf(_gait_amp, clampf(hspeed / 2.2, 0.0, 1.0), 1.0 - exp(-5.0 * delta))
	var amp := _gait_amp
	var idle := 1.0 - amp
	var mspeed := hspeed / maxf(sc, 0.01)                    # velocidade nas medidas do modelo
	var freq := 0.3 + mspeed * 0.36                          # passadas por segundo
	var prev_ph := _gait_ph
	_gait_ph = fmod(_gait_ph + delta * freq, 1.0)
	var stride := clampf(mspeed * SENTINEL_STANCE / maxf(freq, 0.1), 0.0, 1.35)
	var lift := (0.16 + 0.14 * amp) * smoothstep(0.0, 0.25, amp)
	var ph := _gait_ph * TAU
	var lt := _life_t
	# corpo: afunda a cada apoio das dianteiras, o peso vai de um lado para o outro; parado, respira
	var dy := -0.05 * amp + 0.05 * amp * cos(ph * 2.0) + 0.025 * sin(lt * 1.3) * idle
	var pitch := 0.03 * amp * sin(ph * 2.0 + 0.5)
	var roll := 0.05 * amp * sin(ph)
	var sway := 0.04 * amp * sin(ph + 0.8)
	var bz := 0.0
	var neck_x := 0.1 * amp - pitch + 0.05 * amp * sin(ph * 2.0 + 1.0) + 0.04 * sin(lt * 0.5) * idle
	var neck_y := sin(lt * 0.31) * 0.28 * idle + 0.06 * sin(ph) * amp
	var head_x := -neck_x * 0.5 + 0.05 * sin(lt * 0.7 + 1.0) * idle
	var head_y := neck_y * 0.6
	var jaw := 0.03 + maxf(0.0, sin(lt * 1.3)) * 0.08 * idle + 0.04 * amp
	var tail_x := -0.04 + 0.06 * sin(ph * 2.0 - 1.0) * amp
	var tail_y := [sin(ph - 0.6) * 0.22 * amp + sin(lt * 0.8) * 0.18 * idle,
		sin(ph - 1.6) * 0.32 * amp + sin(lt * 0.8 - 0.9) * 0.28 * idle,
		sin(ph - 2.6) * 0.42 * amp + sin(lt * 0.8 - 1.8) * 0.38 * idle]
	var tail_b := [0.0, 0.08 * sin(ph * 2.0 - 2.0) * amp + 0.05 * sin(lt * 0.6) * idle,
		0.12 * sin(ph * 2.0 - 3.0) * amp + 0.08 * sin(lt * 0.6 - 1.0) * idle]
	var mane_back := 0.14 * amp          # a juba fica para trás andando
	var flare := 0.03 + 0.035 * sin(lt * 1.3) + 0.05 * amp * absf(sin(ph))   # ombreiras: respiram
	var crest_s := 1.0 + 0.03 * sin(lt * 2.0)
	var shake := 0.0
	var feet := {}
	for sd in WOLF_SIDES:
		var off: float = SENTINEL_GAIT[sd]
		var u := fmod(_gait_ph + off, 1.0)
		var dz := 0.0
		var upf := 0.0
		var tilt := 0.0
		if u < SENTINEL_STANCE:
			dz = stride * (0.5 - u / SENTINEL_STANCE)
		else:
			var v := (u - SENTINEL_STANCE) / (1.0 - SENTINEL_STANCE)
			var ee := v * v * (3.0 - 2.0 * v)
			dz = stride * (-0.5 + ee)
			upf = lift * sin(PI * v)
			tilt = (0.7 if sd.begins_with("F") else -0.45) * sin(PI * v) * amp
		feet[sd] = [dz, upf, tilt]
		if amp > 0.35 and state != "attack" and fmod(prev_ph + off, 1.0) > u:
			_sentinel_step(sd)   # a pata acabou de pousar
	if state == "attack":
		var t := attack_timer
		var ht := _hit_time()
		var e := smoothstep(0.0, 1.0, clampf(t / ht, 0.0, 1.0))
		for sd in WOLF_SIDES:
			feet[sd] = [0.0, 0.0, 0.0]
		neck_y = 0.0
		head_y = 0.0
		match attack_kind:
			"swing":
				if t < ht:   # arma: corpo para trás e para baixo, pata direita no alto, cabeça baixa rosnando
					bz = -0.5 * e
					dy = -0.28 * e
					pitch = -0.07 * e
					roll = 0.1 * e
					feet["FR"] = [0.1 * e, 1.0 * e, -0.9 * e]
					feet["FL"] = [0.2 * e, 0.0, 0.0]
					neck_x = 0.22 * e
					neck_y = 0.22 * e
					head_x = -0.1 * e
					jaw = 0.3 * e
					tail_x = 0.3 * e
					flare = 0.25 * e
					mane_back = -0.1 * e
				elif t < ht + 0.4:   # crava: o corpo avança e a pata desce na frente
					bz = 0.55
					dy = -0.22
					pitch = 0.15
					roll = -0.12
					feet["FR"] = [1.0, 0.0, 0.25]
					feet["FL"] = [0.2, 0.0, 0.0]
					neck_x = -0.08
					neck_y = -0.2
					jaw = 0.5
					tail_x = -0.2
					flare = 0.35
					shake = 1.0
					mane_back = 0.4
			"breath":
				var t0 := BlizzardRules.BREATH_T0
				for sd in WOLF_SIDES:   # planta as patas: dianteiras à frente, traseiras para trás
					feet[sd] = [0.3 * e if sd.begins_with("F") else -0.25 * e, 0.0, 0.0]
				if t < t0:   # enche o peito: recua, cabeça no alto, ombreiras abrindo
					bz = -0.38 * e
					dy = -0.22 * e
					pitch = -0.1 * e
					neck_x = -0.55 * e
					head_x = -0.15 * e
					jaw = 0.08 * e
					flare = 0.1 + 0.28 * e
					crest_s = 1.0 + 0.16 * e
					tail_x = 0.35 * e
					shake = 0.3 * e
					mane_back = -0.2 * e
				elif t < t0 + BlizzardRules.BREATH_TIME:   # solta o ar: cabeça baixa e à frente, boca escancarada
					bz = 0.22
					dy = -0.3
					pitch = 0.12
					neck_x = 0.2 + 0.03 * sin(lt * 9.0)
					head_x = 0.06
					jaw = 0.78
					flare = 0.55
					crest_s = 1.22
					tail_x = 0.22
					tail_y = [0.0, 0.05 * sin(lt * 7.0), 0.1 * sin(lt * 7.0 - 1.0)]
					shake = 1.0
					mane_back = 0.5
			"icicles":
				if t < ht - 0.3:   # empina nas traseiras urrando para o teto
					var w := smoothstep(0.0, 0.7, t)
					pitch = -0.5 * w
					dy = 0.1 * w
					bz = -0.3 * w
					for sd in ["FL", "FR"]:
						feet[sd] = [0.2 * w, 1.0 * w, -0.5 * w]
					neck_x = -0.55 * w
					head_x = -0.2 * w
					jaw = 0.75 * w
					flare = 0.35 * w
					crest_s = 1.0 + 0.2 * w
					tail_x = -0.3 * w
					shake = 0.8 * w
					mane_back = -0.25 * w
				elif t < ht + 0.5:   # bate as dianteiras no chão
					pitch = 0.1
					dy = -0.26
					bz = 0.2
					for sd in ["FL", "FR"]:
						feet[sd] = [0.35, 0.0, 0.0]
					neck_x = 0.2
					jaw = 0.3
					flare = 0.2
					shake = 1.0
					mane_back = 0.35
			"blizzard":
				var dur := _attack_duration()
				var w := smoothstep(0.0, 0.6, t) * (1.0 - smoothstep(dur - 0.5, dur, t))
				for sd in WOLF_SIDES:
					feet[sd] = [0.25 * w if sd.begins_with("F") else -0.2 * w, 0.0, 0.0]
				dy = -0.16 * w
				pitch = -0.2 * w
				neck_x = -0.85 * w
				head_x = -0.22 * w
				jaw = 0.85 * w
				flare = 0.62 * w
				crest_s = 1.0 + 0.3 * w
				tail_x = 0.5 * w
				shake = 1.5 * w
				mane_back = -0.3 * w
		# o golpe acerta: lascas de gelo arrancadas da couraça (uma vez por golpe)
		if t >= ht and not _rig.hit:
			_rig.hit = true
			var crest: Node3D = parts.get("Crest")
			if crest != null and is_inside_tree():
				BlizzardFX.frost_burst(crest.global_position, 18, 1.4 * sc)
		elif t < ht:
			_rig.hit = false
	else:
		_rig.hit = false
		# hálito frio: de tempos em tempos um tufo de névoa sai da boca
		_rig.breath_t = float(_rig.breath_t) - delta
		if float(_rig.breath_t) <= 0.0:
			_rig.breath_t = randf_range(2.2, 3.6)
			var mz: Node3D = parts.get("Muzzle")
			if mz != null and is_inside_tree() and not puppet_headless():
				FXToon.puff(mz.global_position, 0.8 * sc, FXToon.MIST,
					{"vel": model_forward() * 1.6 + Vector3(0, -0.3, 0), "grow": 0.25, "hold": 0.2, "fade": 0.7})
	if stagger > 0.0 or _flash_t > 0.0:
		shake = maxf(shake, 0.6)   # pancada: a couraça estremece
	var sh := shake * sin(lt * 37.0)
	var sh2 := shake * sin(lt * 31.0 + 1.0)
	var body: Node3D = parts.Body
	body.position.y = lerpf(body.position.y, float(_wolf_rest.body_y) + dy, kf)
	body.position.z = lerpf(body.position.z, float(_wolf_rest.body_z) + bz, kf)
	body.rotation.x = lerpf(body.rotation.x, pitch, kf)
	body.rotation.z = lerpf(body.rotation.z, roll + sh * 0.006, k)
	body.rotation.y = lerpf(body.rotation.y, sway, k)
	var bdy := body.position.y - float(_wolf_rest.body_y)
	var bdz := body.position.z - float(_wolf_rest.body_z)
	for sd in WOLF_SIDES:
		var r: Dictionary = _wolf_rest[sd]
		var fz: Array = feet[sd]
		var f: Vector2 = r.f
		var ang := _wolf_leg(sd, bdy, body.rotation.x, Vector2(f.x + float(fz[1]), f.y + float(fz[0])), float(fz[2]), bdz)
		var leg: Node3D = parts["Leg" + sd]
		leg.position.y = float((r.h as Vector2).x) + bdy - float((r.h as Vector2).y) * sin(body.rotation.x)
		leg.position.z = float((r.h as Vector2).y) + bdz
		leg.rotation.x = lerp_angle(leg.rotation.x, ang.x, kf)
		(parts["Knee" + sd] as Node3D).rotation.x = lerp_angle((parts["Knee" + sd] as Node3D).rotation.x, ang.y, kf)
		(parts["Paw" + sd] as Node3D).rotation.x = lerp_angle((parts["Paw" + sd] as Node3D).rotation.x, ang.z, kf)
	var neck: Node3D = parts.get("Neck")
	if neck:
		neck.rotation.x = lerpf(neck.rotation.x, neck_x + sh2 * 0.012, k)
		neck.rotation.y = lerpf(neck.rotation.y, neck_y, ks)
	parts.Head.rotation.x = lerpf(parts.Head.rotation.x, head_x, k)
	parts.Head.rotation.y = lerpf(parts.Head.rotation.y, head_y + sh * 0.012, ks)
	if parts.Jaw:
		parts.Jaw.rotation.x = lerpf(parts.Jaw.rotation.x, jaw + sh2 * 0.02, k)
	for i in 3:
		var tn: Node3D = parts.get(["Tail", "Tail2", "Tail3"][i])
		if tn:
			tn.rotation.y = lerpf(tn.rotation.y, float(tail_y[i]), ks)
			tn.rotation.x = lerpf(tn.rotation.x, (tail_x if i == 0 else tail_x * 0.5) + float(tail_b[i]), ks)
	# mechas da juba: pêndulos, cada grupo no seu tempo; andando ficam para trás, no golpe são jogadas
	for i in 4:
		var mn: Node3D = parts.get("Mane%d" % i)
		if mn:
			var p2 := i * 1.7
			mn.rotation.x = lerpf(mn.rotation.x, mane_back + sin(ph * 2.0 - 1.0 - i * 0.7) * 0.1 * amp
				+ sin(lt * 1.1 + p2) * 0.05 + sh * 0.05, ks)
			mn.rotation.z = lerpf(mn.rotation.z, sin(ph - 0.8 - i) * 0.09 * amp + sin(lt * 0.9 + p2 * 1.3) * 0.04
				- body.rotation.z * 1.5 + sh2 * 0.05, ks)
	# ombreiras: abrem para fora (como guelras) e tremem
	for pair in [["PlateL", 1.0], ["PlateR", -1.0]]:
		var pn: Node3D = parts.get(pair[0])
		if pn:
			pn.rotation.z = lerpf(pn.rotation.z, (flare + sh * 0.04) * float(pair[1]), k)
	var cr: Node3D = parts.get("Crest")
	if cr:
		cr.scale = cr.scale.lerp(Vector3.ONE * crest_s, k)
		cr.rotation.z = sh2 * 0.02
