class_name GreatswordSupremeSlash
extends Node3D
## Lâmina Suprema (ultimate da montante): a sequência visual inteira, em cena própria
## (scenes/vfx/greatsword_supreme/greatsword_supreme_slash.tscn). GreatswordSupremeAbilities cria uma por ativação, na cena
## do mundo; ela vive mais que a habilidade e se libera sozinha (queue_free) quando o último efeito some.
## Tudo em energia sombria (a paleta das garras do Corte do Abismo: violeta, carmesim, miolo quase preto; DarkEnergy).
##   SwordPivot      segue a montante do herói a cada quadro: na origem o cabo (`blade_base`, nas mãos), o Y na direção
##                   da lâmina (até `blade_tip`), na escala do comprimento atual da energia
##     EnergySword   a energia que cobre a lâmina (malha sword_mesh, dark_blade_energy.gdshader): sobe da guarda até a
##                   ponta (`heat`) no começo da carga e então cresce junto com a carga, do tamanho da montante até
##                   `sword_length` (~3x a altura do herói). Só a lâmina: o cabo de verdade fica nas mãos
##     AuraShell     casca de chamas sombrias em volta dela (malha aura_mesh, dark_aura_*.gdshader): incha e tremula
##   (código)        fiapos escuros, faíscas violeta e lascas carmesim saindo da lâmina; energia sendo puxada para ela
##                   de todo lado na carga (Gather)
##   SwordLight      luz violeta na lâmina, crescendo com a carga
##   Impact          (top_level) no ponto em que a ponta bate no chão, virado na direção do golpe:
##     CrackDecal    a cratera em linha reta (`crack_width` = 3 m de largura): fundo escuro como um abismo, paredes,
##                   borda de terra partida, rachaduras para os lados e veias de energia acesas no fundo
##     Rim           placas de pedra partida (MultiMesh, dark_rock.gdshader) que saltam do chão nas duas bordas, uma
##                   depois da outra do herói para a frente (a cratera se abrindo), e afundam quando ela fecha
##     Rocks / Dirt  pedras e torrões arremessados para os lados (colidem com o chão: Ground)
##     Smoke / Sparks poeira escura e faíscas violeta ao longo da cratera
##     (código)      fumaça escura e faíscas subindo de dentro da cratera enquanto ela está aberta; DarkSouls: as almas
##                   que saem voando de dentro dela e fogem em várias direções
##     ImpactLight / AbyssLight  clarão violeta e o brilho carmesim do fundo
## Fases (tempos do GreatswordSupremeConfig, os mesmos da animação do herói):
##   CHARGE   espada erguida; a energia cobre a lâmina e cresce
##   SLASH    o corte: a espada acompanha a lâmina e, no fim, se inclina até a ponta tocar o chão no ponto do impacto
##   impacto  dano (sinal `impacted` com os inimigos na cratera: PhysicsShapeQueryParameters3D na camada dos inimigos),
##            a cratera abrindo, as almas, partículas, luz e tremor da câmera
##   FADE     a energia se desfaz; depois de `crack_hold` a cratera fecha (as placas afundam, o chão some com Tween);
##            DONE libera quando as almas também sumiram
## O dano é só do dono (`deal_damage`); nas réplicas é só o visual. `cancel()` antes do corte desfaz tudo sem dano.

signal impacted(center: Vector3, targets: Array)
signal finished

const ENEMY_MASK := 4      ## camada 3 ("enemies")
const WORLD_MASK := 1
const CANCEL_TIME := 0.25
const SWORD_DISSOLVE := 0.75   ## a energia se desfaz depois do impacto (s)
const CRACK_TEX := Vector2i(128, 768)   ## textura da cratera: largura x comprimento (px)
const DECAL_WIDTH := 1.5       ## a textura cobre a cratera mais a borda: largura do decal / largura da cratera
const TRENCH := 0.62           ## meia largura do fundo na textura (fração da meia largura do decal)
const SLAB_RISE := 0.2         ## tempo para uma placa da borda saltar (s)
## Proporções da malha da espada (comprimento 1 = das mãos à ponta).
const BLADE_FROM := 0.085          ## onde a lâmina sai da guarda
const BLADE_HALF_W := 0.042        ## meia-largura da lâmina na guarda
const BLADE_HALF_T := 0.016        ## meia-espessura na quina do meio
const GUARD_HALF_W := 0.17
const POMMEL_Y := -0.1
const AURA_PUFF := 2.3             ## a casca de chamas: quantas vezes a largura da lâmina

enum State { CHARGE, SLASH, FADE, DONE, CANCELED }

@export var config: GreatswordSupremeConfig

## O herói (posição e para onde olha até o corte) e as pontas da lâmina da montante dele (KnightLook: holder, tip).
var follow: Node3D
var blade_base: Node3D
var blade_tip: Node3D
var yaw := 0.0
var seed_value := 0
var deal_damage := false
## Só aquece os pipelines (GreatswordSupremeAbilities.prewarm_instances): desenha cada efeito uma vez, longe da vista,
## e se libera.
var warm_only := false

@onready var sword_pivot: Node3D = $SwordPivot
@onready var energy_sword: MeshInstance3D = $SwordPivot/EnergySword
@onready var aura: MeshInstance3D = $SwordPivot/AuraShell
@onready var sword_light: OmniLight3D = $SwordLight
@onready var impact_root: Node3D = $Impact
@onready var rocks: GPUParticles3D = $Impact/Rocks
@onready var dirt: GPUParticles3D = $Impact/Dirt
@onready var smoke: GPUParticles3D = $Impact/Smoke
@onready var sparks: GPUParticles3D = $Impact/Sparks
@onready var crack: Decal = $Impact/CrackDecal
@onready var rim: MultiMeshInstance3D = $Impact/Rim
@onready var light: OmniLight3D = $Impact/ImpactLight
@onready var abyss_light: OmniLight3D = $Impact/AbyssLight
var blade_wisps: GPUParticles3D
var blade_motes: GPUParticles3D
var blade_sparks: GPUParticles3D
var gather: GPUParticles3D
var abyss_smoke: GPUParticles3D
var abyss_motes: GPUParticles3D
## As almas da cratera (criadas no impacto; null antes e depois que todas somem).
var souls: DarkSouls

var state := State.CHARGE
var t := 0.0
var impact_at := -1.0
var impact_center := Vector3.ZERO
var hit_count := 0
## Quantas almas saíram da cratera (testes).
var souls_spawned := 0
var _origin := Vector3.ZERO
var _sword_fixed := false
var _fade_started := false
var _closed := false
var _hit := {}
var _len := 1.0           ## comprimento atual da energia (m)
var _blade_len := 1.4     ## comprimento da montante de verdade (m), medido no começo
var _slabs: Array[Dictionary] = []
var _close_k := 0.0       ## 0 = cratera aberta, 1 = fechada (as placas afundam)

static var _sword_mesh: ArrayMesh
static var _aura_mesh: ArrayMesh
static var _slab_mesh: ArrayMesh
## Texturas da cratera (geradas uma vez numa thread, divididas por todas as ativações).
static var _crack_albedo: ImageTexture
static var _crack_emission: ImageTexture
static var _crack_images: Array = []
static var _crack_task := -1


func _ready() -> void:
	if config == null:
		config = load("res://assets/vfx/greatsword_supreme/greatsword_supreme_config.tres")
	energy_sword.mesh = sword_mesh()
	aura.mesh = aura_mesh()
	energy_sword.set_instance_shader_parameter("seed", float(seed_value % 97) * 0.13)
	aura.set_instance_shader_parameter("seed", float(seed_value % 89) * 0.17)
	# energia da lâmina: fiapos, faíscas e lascas ao longo dela; na carga, faíscas puxadas para ela de todo lado
	blade_wisps = DarkEnergy.wisps(50, 0.6, 0.5)
	blade_motes = DarkEnergy.motes(80, 1.0, 0.12)
	blade_sparks = DarkEnergy.sparks(36, 0.6, 0.35)
	gather = DarkEnergy.motes(90, 0.7, 0.1)
	var gm := gather.process_material as ParticleProcessMaterial
	gm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	gm.emission_sphere_radius = 3.2
	gm.direction = Vector3.ZERO
	gm.spread = 180.0
	gm.initial_velocity_min = 0.0
	gm.initial_velocity_max = 0.5
	gm.gravity = Vector3.ZERO
	gm.radial_accel_min = -16.0
	gm.radial_accel_max = -10.0
	gm.tangential_accel_min = 2.0
	gm.tangential_accel_max = 5.0
	gm.turbulence_enabled = false
	for p: GPUParticles3D in _aura_particles():
		add_child(p)
		p.top_level = true
	# a cratera: fumaça escura e faíscas subindo de dentro dela enquanto está aberta
	abyss_smoke = DarkEnergy.wisps(int(70 * maxf(config.debris_amount, 0.1)), 1.6, 1.4)
	abyss_motes = DarkEnergy.motes(int(90 * maxf(config.debris_amount, 0.1)), 1.4, 0.12)
	for p: GPUParticles3D in [abyss_smoke, abyss_motes]:
		impact_root.add_child(p)
		var m := p.process_material as ParticleProcessMaterial
		m.emission_box_extents = Vector3(config.crack_width * 0.3, 0.05, config.crack_length() * 0.46)
		m.initial_velocity_max *= 1.6
		p.position = Vector3(0.0, 0.1, config.crack_center_offset())
	sparks.draw_pass_1 = FXEpic._spark_mesh()
	smoke.material_override = FXEpic._particle_mat(FXEpic._smoke_tex(), false)
	# partículas do impacto ao longo da cratera (material próprio: o comprimento vem da configuração)
	var half := config.crack_length() * 0.5
	var k := config.debris_amount
	for p: GPUParticles3D in [rocks, dirt, smoke, sparks]:
		p.amount = maxi(1, int(round(p.amount * maxf(k, 0.05))))
		var m := p.process_material.duplicate() as ParticleProcessMaterial
		m.emission_box_extents.z = half * 0.9
		m.emission_box_extents.x = config.crack_width * 0.45
		m.initial_velocity_max *= config.debris_speed / 10.0
		p.process_material = m
		p.position.z = config.crack_center_offset()
	crack.size = Vector3(config.crack_width * DECAL_WIDTH, 4.0, config.crack_length())
	crack.position = Vector3(0.0, 0.0, config.crack_center_offset())
	abyss_light.position.z = config.crack_center_offset()
	abyss_light.omni_range = maxf(config.crack_length() * 0.6, 4.0)
	_build_slabs()
	warm()
	if warm_only:
		_warm_pipelines()
		return
	_blade_len = _measure_blade()
	_len = _blade_len
	_follow_now()
	_set_energy(0.0, 0.0, 0.0)
	Sfx.play_at("portal", global_position + Vector3.UP * 2.0, 0.05, -4.0)


## Desenha a espada, a cratera e as partículas um instante (o Godot prepara o pipeline de desenho de cada uma no
## primeiro uso; sem isso a primeira ultimate da sessão engasgaria).
func _warm_pipelines() -> void:
	set_process(false)
	state = State.DONE
	_set_energy(0.5, 0.01, 0.01)
	sword_pivot.global_transform = Transform3D(Basis.IDENTITY, global_position)
	impact_root.global_position = global_position
	impact_root.visible = true
	_crack_textures()
	crack.texture_albedo = _crack_albedo
	crack.texture_emission = _crack_emission
	_pose_slabs(0.0)
	for p: GPUParticles3D in [rocks, dirt, smoke, sparks, abyss_smoke, abyss_motes] + _aura_particles():
		p.global_position = global_position
		p.restart()
	var s := DarkSouls.new()
	add_child(s)
	s.spawn(global_position, global_position + Vector3.FORWARD, 1.0, 1, 1.0, 0.3, 0.0, 1.0, 1)
	get_tree().create_timer(0.6).timeout.connect(queue_free)


## Antes do corte dá para desfazer (esquiva, morte, troca de arma).
func can_cancel() -> bool:
	return state == State.CHARGE


## Desfaz sem dano: a energia se apaga depressa.
func cancel() -> void:
	if not can_cancel():
		return
	state = State.CANCELED
	var a := float(energy_sword.get_instance_shader_parameter("intensity"))
	var h := float(energy_sword.get_instance_shader_parameter("heat"))
	var au := float(aura.get_instance_shader_parameter("intensity"))
	_aura_emitting(false)
	gather.emitting = false
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		_set_energy(h, a * v, au * v)
		sword_light.light_energy *= v, 1.0, 0.0, CANCEL_TIME)
	tw.tween_callback(_finish)


## Comprimento atual da energia na lâmina (m): do tamanho da montante até `sword_length` na carga.
func sword_len() -> float:
	return _len


func _process(delta: float) -> void:
	t += delta
	_follow_now()
	match state:
		State.CHARGE:
			var raise := config.raise_time
			var u := clampf((t - raise) / config.charge_time, 0.0, 1.0)
			# a energia cobre a lâmina da guarda até a ponta; depois cresce com a carga (a forma sobe rápido e assenta)
			var cover := smoothstep(0.0, config.cover_frac, u)
			var g := smoothstep(config.cover_frac * 0.5, 1.0, u)
			_len = lerpf(_blade_len * 1.04, config.sword_length, g)
			var pulse := 1.0 + 0.08 * sin(t * 14.0) * cover
			_set_energy(cover, config.sword_intensity * smoothstep(0.0, 0.12, u) * pulse, cover * (0.35 + 0.65 * g))
			sword_light.light_energy = (0.4 + 3.0 * g) * cover * pulse
			sword_light.omni_range = 4.0 + 5.0 * g
			if t > raise * 0.5 and not gather.emitting and u < 0.95:
				gather.emitting = true
			if u >= 0.95 and gather.emitting:
				gather.emitting = false
			if cover > 0.3 and not blade_wisps.emitting:
				_aura_emitting(true)
			for p: GPUParticles3D in [blade_wisps, blade_motes, blade_sparks]:
				p.amount_ratio = 0.35 + 0.65 * g
			_place_sword(0.0)
			if t >= config.charge_end():
				state = State.SLASH
				gather.emitting = false
				blade_wisps.emitting = false   # no corte a lâmina corre: a fumaça viraria pontos espalhados
				_origin = follow.global_position if _valid(follow) else global_position
				impact_center = _impact_point()
				Sfx.play_at("sword_swing_heavy", global_position + Vector3.UP * 2.0, 0.05, 2.0)
		State.SLASH:
			var u := clampf((t - config.charge_end()) / config.slash_time, 0.0, 1.0)
			_len = config.sword_length
			_set_energy(1.0, config.sword_intensity * (1.0 + 0.4 * u), 1.0)
			sword_light.light_energy = 3.4
			# no fim do corte a espada se inclina até a ponta tocar o chão no ponto do impacto
			_place_sword(smoothstep(0.7, 1.0, u))
			if t >= config.impact_time():
				_impact()
		State.FADE:
			var since := t - impact_at
			var d := clampf((since - 0.15) / SWORD_DISSOLVE, 0.0, 1.0)
			energy_sword.set_instance_shader_parameter("dissolve", smoothstep(0.2, 1.0, d))
			_set_energy(1.0, config.sword_intensity * (1.4 - 0.6 * d), 1.0 - smoothstep(0.0, 0.7, d))
			sword_light.light_energy = 3.4 * (1.0 - d)
			if d > 0.3 and blade_wisps.emitting:
				_aura_emitting(false)
			if d >= 1.0 and energy_sword.visible:
				energy_sword.visible = false
				aura.visible = false
			_pose_slabs(since)
			abyss_light.light_energy = (1.6 + 0.5 * sin(t * 5.0)) * (1.0 - _close_k) * smoothstep(0.0, 0.3, since)
			if since >= config.crack_hold and not _fade_started:
				_fade_out()
			if _closed and (souls == null or not is_instance_valid(souls)):
				_finish()


# ------------------------------------------------------------------- energia na espada
func _valid(n: Node3D) -> bool:
	return n != null and is_instance_valid(n) and n.is_inside_tree()


## Comprimento da montante nas mãos (do cabo à ponta), onde a energia começa.
func _measure_blade() -> float:
	if _valid(blade_base) and _valid(blade_tip):
		return maxf(blade_base.global_position.distance_to(blade_tip.global_position), 0.5)
	return 1.4


## Até o corte o nó raiz acompanha o herói (posição e direção).
func _follow_now() -> void:
	if state != State.CHARGE or not _valid(follow):
		return
	global_position = follow.global_position
	rotation = Vector3(0.0, yaw, 0.0)


## A energia no eixo da montante: o cabo nas mãos, a lâmina na direção do cabo para a ponta, no comprimento atual.
## `bend` 0..1 = quanto já se inclinou até a ponta tocar o chão no ponto do impacto.
func _place_sword(bend: float) -> void:
	if _sword_fixed:
		return
	var base: Vector3
	var dir: Vector3
	if _valid(blade_base) and _valid(blade_tip):
		base = blade_base.global_position
		dir = blade_tip.global_position - base
	else:   # sem a arma (réplica sem modelo): de pé sobre o herói
		base = global_position + Vector3.UP * 1.6
		dir = Vector3.UP
	dir = dir.normalized() if dir.length() > 0.001 else Vector3.UP
	# o gume da montante: o suporte da arma tem o Y contra o gume (KnightAnim._orient_by_path); a largura da energia vai
	# nesse eixo, para os fios ficarem onde estão os da montante (no corte, o fio vai na frente)
	var edge := Vector3.ZERO
	if _valid(blade_base):
		edge = -blade_base.global_basis.y
	edge -= dir * edge.dot(dir)
	if edge.length() < 0.01:   # sem a arma: na horizontal
		edge = dir.cross(Vector3.UP)
		if edge.length() < 0.01:
			edge = Vector3(cos(yaw), 0.0, -sin(yaw))
	edge = edge.normalized()
	var length := _len
	if bend > 0.0:
		var to_hit := impact_center - base
		# pelo caminho de cima (a lâmina pode estar apontando para trás): o caminho curto passaria de ponta para a câmera
		var q := KnightAnim.blade_turn(dir, to_hit.normalized(), bend)
		dir = (q * dir).normalized()
		edge = q * edge
		# ao tocar o chão, um fio para baixo: a lâmina entra cortando, não de chapa
		var down := Vector3.DOWN - dir * Vector3.DOWN.dot(dir)
		if down.length() > 0.01:
			down = down.normalized()
			edge = edge.slerp(down if edge.dot(down) >= 0.0 else -down, bend)
		edge = (edge - dir * edge.dot(dir)).normalized()
		length = lerpf(length, to_hit.length(), bend)
	var side := edge
	var flat := side.cross(dir).normalized()
	# a largura cresce menos que o comprimento: no tamanho da montante ela cobre a lâmina, grande fica uma lâmina larga
	var wk := config.sword_width * lerpf(1.6, 1.0, clampf((length - _blade_len) / maxf(config.sword_length - _blade_len, 0.01), 0.0, 1.0))
	sword_pivot.global_transform = Transform3D(Basis(side * length * wk, dir * length, flat * length * wk), base)
	# as partículas saem ao longo da lâmina (da guarda à ponta)
	var tip := base + dir * length
	for p: GPUParticles3D in [blade_wisps, blade_motes, blade_sparks]:
		DarkEnergy.along_blade(p, base + dir * length * BLADE_FROM, tip, 0.0, BLADE_HALF_W * length * wk * 1.6)
	gather.global_position = base + dir * length * 0.55
	sword_light.global_position = base + dir * length * 0.6


## `heat` = quanto da lâmina a energia cobre (0..1), o brilho dela e o da casca de chamas.
func _set_energy(heat: float, intensity: float, aura_k: float) -> void:
	energy_sword.set_instance_shader_parameter("heat", heat)
	energy_sword.set_instance_shader_parameter("intensity", intensity)
	aura.set_instance_shader_parameter("heat", heat)
	aura.set_instance_shader_parameter("intensity", aura_k)


func _aura_particles() -> Array[GPUParticles3D]:
	return [blade_wisps, blade_motes, blade_sparks, gather]


func _aura_emitting(on: bool) -> void:
	for p: GPUParticles3D in [blade_wisps, blade_motes, blade_sparks]:
		p.emitting = on and (p != blade_wisps or state == State.CHARGE)


# ------------------------------------------------------------------- malhas
## Malha da espada (comprimento 1 das mãos à ponta), feita uma vez: lâmina de seção em losango (quina no meio, gumes nas
## bordas) afinando até a ponta, guarda reta, cabo e pomo em losango. Faces planas (quinas nítidas). UV.x na lâmina vai
## de 0 no gume a 1 na quina; COLOR.r = 1 na lâmina e 0 no resto (dark_blade_energy.gdshader só desenha a lâmina).
static func sword_mesh() -> ArrayMesh:
	if _sword_mesh != null:
		return _sword_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	# lâmina: seções [y, meia-largura, meia-espessura]
	var secs := [[BLADE_FROM, BLADE_HALF_W, BLADE_HALF_T], [0.5, BLADE_HALF_W * 0.92, BLADE_HALF_T * 0.9],
		[0.86, BLADE_HALF_W * 0.8, BLADE_HALF_T * 0.8], [1.0, 0.0, 0.0]]
	for i in secs.size() - 1:
		var a: Array = secs[i]
		var b: Array = secs[i + 1]
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var ea := Vector3(sx * a[1], a[0], 0.0)
				var ra := Vector3(0.0, a[0], sz * a[2])
				var eb := Vector3(sx * b[1], b[0], 0.0)
				var rb := Vector3(0.0, b[0], sz * b[2])
				var out := Vector3(sx, 0.0, sz)
				_tri(st, [ea, ra, rb], [0.0, 1.0, 1.0], 1.0, out)
				if b[1] > 0.0:
					_tri(st, [ea, rb, eb], [0.0, 1.0, 0.0], 1.0, out)
	# base da lâmina (fecha a seção encostada na guarda)
	var s0: Array = secs[0]
	for sx in [-1.0, 1.0]:
		_tri(st, [Vector3(sx * s0[1], s0[0], 0), Vector3(0, s0[0], s0[2]), Vector3(0, s0[0], -s0[2])], [0.0, 1.0, 1.0], 1.0, Vector3.DOWN)
	# guarda, cabo e pomo
	_box(st, Vector3(-GUARD_HALF_W, 0.058, -0.03), Vector3(GUARD_HALF_W, BLADE_FROM, 0.03))
	_box(st, Vector3(-0.018, -0.075, -0.018), Vector3(0.018, 0.058, 0.018))
	var py := POMMEL_Y + 0.022
	var pr := 0.032
	var pts := [Vector3(pr, py, 0), Vector3(0, py, pr), Vector3(-pr, py, 0), Vector3(0, py, -pr)]
	for i in 4:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[(i + 1) % 4]
		var mid := (p0 + p1) * 0.5
		_tri(st, [p0, p1, Vector3(0, py + pr, 0)], [0.4, 0.4, 0.4], 0.0, Vector3(mid.x, 0.5, mid.z))
		_tri(st, [p0, p1, Vector3(0, POMMEL_Y - 0.01, 0)], [0.4, 0.4, 0.4], 0.0, Vector3(mid.x, -0.5, mid.z))
	st.generate_normals()
	_sword_mesh = st.commit()
	return _sword_mesh


## Casca das chamas (comprimento 1, como sword_mesh): um fuso liso em volta da lâmina, da guarda até passar um pouco da
## ponta, de seção elíptica (mais larga que grossa) AURA_PUFF vezes a lâmina. UV.y = 0 na guarda e 1 na ponta, UV.x = a
## volta. Normais suaves (o shader incha os vértices pela normal sem abrir as costuras).
static func aura_mesh() -> ArrayMesh:
	if _aura_mesh != null:
		return _aura_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 24
	var sides := 14
	var y0 := BLADE_FROM - 0.01
	var y1 := 1.06
	var grid := []
	for j in rings + 1:
		var v := float(j) / rings
		var y := lerpf(y0, y1, v)
		# meia-largura: cheia na guarda, afinando até a ponta (arredondada nas duas pontas)
		var hw := BLADE_HALF_W * AURA_PUFF * (1.0 - 0.45 * v) * sqrt(maxf(sin(PI * clampf(v * 0.5 + 0.5 * pow(v, 3.0), 0.0, 1.0)), 0.0) + 0.0001)
		hw *= smoothstep(0.0, 0.08, v) * 0.7 + 0.3
		if j == rings:
			hw = 0.0
		var row := []
		for s in sides + 1:
			var a := TAU * float(s) / sides
			row.append(Vector3(cos(a) * hw, y, sin(a) * hw * 0.55))
		grid.append(row)
	for j in rings:
		for s in sides:
			var u0 := float(s) / sides
			var u1 := float(s + 1) / sides
			var v0 := float(j) / rings
			var v1 := float(j + 1) / rings
			var quad := [[grid[j][s], u0, v0], [grid[j][s + 1], u1, v0], [grid[j + 1][s + 1], u1, v1], [grid[j + 1][s], u0, v1]]
			for idx in [0, 2, 1, 0, 3, 2]:
				st.set_uv(Vector2(quad[idx][1], quad[idx][2]))
				st.add_vertex(quad[idx][0])
	st.generate_normals()
	_aura_mesh = st.commit()
	return _aura_mesh


## Placa de pedra partida (base 1 x 1 em X/Z, altura 1 em Y a partir do chão): mais estreita em cima, com o topo
## quebrado em pontas de alturas diferentes. Faces planas. Feita uma vez (o MultiMesh varia tamanho e giro).
static func slab_mesh() -> ArrayMesh:
	if _slab_mesh != null:
		return _slab_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var b := [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5)]
	var tp := [Vector3(-0.36, 0.78, -0.3), Vector3(0.4, 1.0, -0.34), Vector3(0.32, 0.66, 0.36), Vector3(-0.3, 0.9, 0.3)]
	var peak := Vector3(0.05, 1.12, -0.04)
	for i in 4:
		var j := (i + 1) % 4
		_tri(st, [b[i], b[j], tp[j]], [0.4, 0.4, 0.4], 0.0, (b[i] + b[j]) * 0.5 + Vector3.UP * 0.2)
		_tri(st, [b[i], tp[j], tp[i]], [0.4, 0.4, 0.4], 0.0, (b[i] + b[j]) * 0.5 + Vector3.UP * 0.2)
		_tri(st, [tp[i], tp[j], peak], [0.4, 0.4, 0.4], 0.0, Vector3.UP + (tp[i] + tp[j]) * 0.5)
	st.generate_normals()
	_slab_mesh = st.commit()
	return _slab_mesh


## Triângulo com a face virada para `out` (acerta a ordem dos vértices para a normal plana sair para fora).
static func _tri(st: SurfaceTool, v: Array, ux: Array, part: float, out: Vector3) -> void:
	var n := ((v[1] as Vector3) - (v[0] as Vector3)).cross((v[2] as Vector3) - (v[0] as Vector3))
	var order := [0, 1, 2] if n.dot(out) < 0.0 else [0, 2, 1]   # o Godot usa a ordem horária como frente
	for i in order:
		st.set_color(Color(part, 0, 0))
		st.set_uv(Vector2(ux[i], 0.0))
		st.add_vertex(v[i])


static func _box(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var c := (a + b) * 0.5
	var corners := []
	for i in 8:
		corners.append(Vector3(a.x if (i & 1) == 0 else b.x, a.y if (i & 2) == 0 else b.y, a.z if (i & 4) == 0 else b.z))
	for f in [[0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4], [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]]:
		var q := [corners[f[0]], corners[f[1]], corners[f[2]], corners[f[3]]]
		var mid: Vector3 = ((q[0] as Vector3) + (q[2] as Vector3)) * 0.5
		_tri(st, [q[0], q[1], q[2]], [0.4, 0.4, 0.4], 0.0, mid - c)
		_tri(st, [q[0], q[2], q[3]], [0.4, 0.4, 0.4], 0.0, mid - c)


# ------------------------------------------------------------------- cratera
## Ponto do impacto: `impact_distance` à frente do herói, na altura do chão (o chão pode subir ou descer à frente).
func _impact_point() -> Vector3:
	var f := Vector3(sin(yaw), 0.0, cos(yaw))
	var p := _origin + f * config.impact_distance
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p - Vector3.UP * 6.0, WORLD_MASK)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			p.y = float(hit.position.y)
	return p


## Onde a cratera começa e termina no mundo (no chão do ponto do impacto).
func crater_ends() -> Array[Vector3]:
	var f := Vector3(sin(yaw), 0.0, cos(yaw))
	var a := impact_center + f * (config.crack_start - config.impact_distance)
	var b := impact_center + f * config.crack_beyond
	return [a, b]


## As placas das duas bordas (no espaço do nó Impact: +Z = a direção do golpe), sorteadas uma vez por ativação.
func _build_slabs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 7
	var l := config.crack_length()
	var z0 := config.crack_center_offset() - l * 0.5
	var half := config.crack_width * 0.5
	var n := maxi(2, int(l * config.rim_density))
	for side in [-1.0, 1.0]:
		for i in n:
			var v := (float(i) + rng.randf_range(0.15, 0.85)) / float(n)
			var taper := pow(maxf(sin(PI * v), 0.0), 0.5)
			var w := rng.randf_range(0.45, 0.85) * (0.5 + 0.5 * taper)
			var h := rng.randf_range(0.35, 0.8) * (0.4 + 0.6 * taper)
			var d := rng.randf_range(0.25, 0.45)
			var x: float = side * (half * (0.55 + 0.45 * taper) + d * 0.3 + rng.randf_range(-0.08, 0.12))
			_slabs.append({"pos": Vector3(x, 0.0, z0 + l * v), "size": Vector3(d, h, w),
				"tilt": float(side) * rng.randf_range(0.35, 0.75), "yaw": rng.randf_range(-0.35, 0.35),
				"at": l * v / maxf(config.open_speed, 1.0), "h": h})
	var mm := rim.multimesh.duplicate() as MultiMesh   # cada ativação com as suas placas
	rim.multimesh = mm
	mm.mesh = slab_mesh()
	mm.instance_count = _slabs.size()
	_pose_slabs(-1.0)


## Pose das placas `since` s depois do impacto: cada uma salta (passa um pouco da altura e volta) quando a cratera chega
## nela, a rachadura dela acesa esfriando; fechando (`_close_k`), afundam de volta no chão.
func _pose_slabs(since: float) -> void:
	var mm := rim.multimesh
	for i in _slabs.size():
		var s: Dictionary = _slabs[i]
		var r := clampf((since - float(s.at)) / SLAB_RISE, 0.0, 1.0) if since >= 0.0 else 0.0
		var ov := 1.0 + 2.7 * pow(r - 1.0, 3.0) + 1.7 * pow(r - 1.0, 2.0)   # ease out back
		ov = ov if r > 0.0 else 0.0
		var up := clampf(ov, 0.0, 1.15) * (1.0 - _close_k)
		var sz: Vector3 = s.size
		var b := Basis(Vector3.UP, float(s.yaw)) * Basis(Vector3.BACK, float(s.tilt)) * Basis.from_scale(sz)
		var p: Vector3 = (s.pos as Vector3) - Vector3.UP * float(s.h) * (1.05 - up)
		mm.set_instance_transform(i, Transform3D(b, p))
		var glow := (1.0 - smoothstep(0.0, 1.2, since - float(s.at))) * 1.4 + 0.25 if since >= float(s.at) else 0.0
		mm.set_instance_custom_data(i, Color(glow * (1.0 - _close_k), 0, 0, 0))


func _impact() -> void:
	state = State.FADE
	impact_at = t
	_place_sword(1.0)
	_sword_fixed = true   # a energia fica cravada enquanto se desfaz
	impact_root.global_position = impact_center
	impact_root.global_rotation = Vector3(0.0, yaw, 0.0)
	impact_root.visible = true
	_crack_textures()   # normalmente já prontas (warm, numa thread, desde o começo da carga)
	crack.texture_albedo = _crack_albedo
	crack.texture_emission = _crack_emission
	for p: GPUParticles3D in [rocks, dirt, smoke, sparks]:
		p.restart()
	for p: GPUParticles3D in [abyss_smoke, abyss_motes]:
		p.emitting = true
	# a cratera corre pelo chão do herói para a frente, com o fundo aceso, e esfria
	var l := config.crack_length()
	var open := l / maxf(config.open_speed, 1.0)
	var z0 := config.crack_center_offset() - l * 0.5
	crack.size.z = 0.3
	crack.position.z = z0 + 0.15
	crack.emission_energy = 4.0
	var tw := create_tween().set_parallel()
	tw.tween_method(func(v: float) -> void:
		crack.size.z = maxf(l * v, 0.3)
		crack.position.z = z0 + crack.size.z * 0.5, 0.0, 1.0, open).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(crack, "emission_energy", 1.6, 1.2).set_delay(open)
	light.light_energy = 4.0
	tw.tween_property(light, "light_energy", 0.8, 0.7).set_ease(Tween.EASE_OUT)
	# o capim some dentro da cratera (senão a esconde)
	var ends := crater_ends()
	_flatten(ends[0], ends[1], config.crack_width * 0.5 + 0.4, 1.0)
	# as almas saem de dentro dela
	souls = DarkSouls.new()
	impact_root.add_child(souls)
	souls.spawn(ends[0], ends[1], config.crack_width * 0.5, config.soul_count, config.soul_speed, config.soul_life,
		config.soul_stagger, config.soul_size, seed_value)
	souls_spawned = config.soul_count
	_shake_local(impact_center)
	Sfx.play_at("explode", impact_center, 0.05, 0.0)
	Sfx.play_at("slam", impact_center, 0.08, 0.0)
	Sfx.play_at("chop_stone", impact_center, 0.15, -4.0)
	Sfx.play_at("arcane_hit", impact_center, 0.1, -2.0)
	var targets := _collect_targets() if deal_damage else []
	hit_count = targets.size()
	impacted.emit(impact_center, targets)


## Inimigos na área do golpe: uma consulta de forma (esfera que cobre a cratera inteira) na camada dos inimigos, filtrada
## pela área exata (GreatswordSupremeRules.in_crater: do herói até a ponta da cratera, 3 m de largura, mais o raio em
## volta do ponto do golpe) e por quem já levou o golpe.
func _collect_targets() -> Array:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return []
	var ends := crater_ends()
	var mid := (_origin + ends[1]) * 0.5
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(_origin.distance_to(ends[1]) * 0.5 + config.cut_half_width, config.impact_radius) + 1.0
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.transform = Transform3D(Basis.IDENTITY, mid + Vector3.UP)
	q.collision_mask = ENEMY_MASK
	q.collide_with_areas = false
	q.collide_with_bodies = true
	var cands := []
	for r in space.intersect_shape(q, 64):
		var b = r.get("collider")
		if b == null or not is_instance_valid(b) or not b.is_in_group("enemies") or bool(b.get("dead")):
			continue
		cands.append({"id": b.get_instance_id(), "pos": b.global_position, "radius": float(b.get("radius")), "node": b})
	return GreatswordSupremeRules.pick_targets(cands, _origin, ends[1], impact_center, config.impact_radius,
		config.cut_half_width, _hit).map(func(x: Dictionary) -> Node: return x.node)


## Treme a câmera do jogador local conforme a distância até o impacto (também em quem só vê o golpe de outro).
func _shake_local(center: Vector3) -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null or config.shake_strength <= 0.0:
		return
	var lp = tree.current_scene.get("player")
	if lp == null or not is_instance_valid(lp) or not lp.is_inside_tree() or not lp.has_method("add_shake"):
		return
	var d := Vector2(lp.global_position.x - center.x, lp.global_position.z - center.z).length()
	var f := 1.0 - clampf(d / config.shake_range, 0.0, 1.0)
	if f > 0.0:
		lp.add_shake(config.shake_strength * f * f * (3.0 - 2.0 * f))


## Capim achatado ao longo da cratera (globais `fx_flatten`/`fx_flatten_to` do shader do capim). Um efeito por vez.
func _flatten(a: Vector3, b: Vector3, half_width: float, k: float) -> void:
	RenderingServer.global_shader_parameter_set("fx_flatten", Vector4(a.x, a.z, half_width, k))
	RenderingServer.global_shader_parameter_set("fx_flatten_to", Vector4(b.x, b.z, 1.0, 0.0))


# ------------------------------------------------------------------- dissipação
## A cratera fecha aos poucos (Tween): as placas afundam, o chão e a luz somem, a fumaça do fundo para.
func _fade_out() -> void:
	_fade_started = true
	for p: GPUParticles3D in [abyss_smoke, abyss_motes]:
		p.emitting = false
	var ft := config.fade_time
	var ends := crater_ends()
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "_close_k", 1.0, ft).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(crack, "modulate", Color(1, 1, 1, 0), ft).set_ease(Tween.EASE_IN)
	tw.tween_property(crack, "emission_energy", 0.0, ft * 0.7)
	tw.tween_property(light, "light_energy", 0.0, ft * 0.5)
	tw.tween_method(func(v: float) -> void: _flatten(ends[0], ends[1], config.crack_width * 0.5 + 0.4, v), 1.0, 0.0, ft)
	tw.chain().tween_callback(func() -> void: _closed = true)


func _finish() -> void:
	if state == State.DONE:
		return
	if impact_at >= 0.0:
		RenderingServer.global_shader_parameter_set("fx_flatten", Vector4.ZERO)
	state = State.DONE
	finished.emit()
	queue_free()


# ------------------------------------------------------------------- textura da cratera
## Começa a gerar as texturas da cratera numa thread (a habilidade chama ao começar: a carga dura mais que isso).
static func warm() -> void:
	if _crack_albedo != null or _crack_task >= 0:
		return
	_crack_task = WorkerThreadPool.add_task(_build_crack_images)


## As texturas prontas (espera a thread, se ainda não acabou).
static func _crack_textures() -> void:
	if _crack_albedo != null:
		return
	if _crack_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_crack_task)
		_crack_task = -1
	else:
		_build_crack_images()
	_crack_albedo = ImageTexture.create_from_image(_crack_images[0])
	_crack_emission = ImageTexture.create_from_image(_crack_images[1])


## A cratera vista de cima, em linha reta ao longo da textura (largura x comprimento = CRACK_TEX): o fundo como um abismo
## (escurece até quase preto no meio, com pedregulhos perto das paredes), a parede de borda irregular com a sombra, a
## borda de terra partida levantada, rachaduras finas para os lados e a terra chamuscada em volta. Na emissão, a fenda
## acesa no fundo e veias de energia violeta e carmesim. Fecha arredondada nas pontas. Determinística: gerada uma vez.
static func _build_crack_images() -> void:
	var w := CRACK_TEX.x
	var h := CRACK_TEX.y
	var alb := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var emi := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 5
	noise.frequency = 1.0
	var grain := FastNoiseLite.new()
	grain.seed = 9
	grain.frequency = 0.09
	var veins := FastNoiseLite.new()
	veins.seed = 13
	veins.frequency = 0.035
	veins.fractal_octaves = 3
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	# rachaduras finas saindo da borda para os lados: [v onde sai, lado, comprimento (u), inclinação]
	var branches := []
	for i in 22:
		branches.append([rng.randf_range(0.05, 0.95), -1.0 if i % 2 == 0 else 1.0, rng.randf_range(0.15, 0.36),
			rng.randf_range(-0.06, 0.06)])
	var violet := Color(0.62, 0.3, 1.0)
	var crimson := Color(1.0, 0.1, 0.32)
	for y in h:
		var v := (y + 0.5) / h
		var taper := pow(maxf(sin(PI * v), 0.0), 0.35)
		var c := noise.get_noise_1d(v * 7.0) * 0.05 + noise.get_noise_1d(v * 31.0 + 50.0) * 0.02
		var wall := TRENCH * taper * (0.92 + 0.16 * (noise.get_noise_1d(v * 23.0 + 9.0) * 0.5 + 0.5))
		for x in w:
			var u := (x + 0.5) / w * 2.0 - 1.0
			var du := absf(u - c)
			var g := grain.get_noise_2d(x, y) * 0.5 + 0.5
			var col := Color(0, 0, 0, 0)
			var glow := Color(0, 0, 0, 0)
			if du < wall:
				# fundo: quanto mais para o meio, mais fundo (mais escuro)
				var depth := 1.0 - du / maxf(wall, 0.001)
				var k := smoothstep(0.05, 0.75, depth)
				col = Color(0.15, 0.12, 0.13).lerp(Color(0.012, 0.004, 0.02), k)
				# pedregulhos e lascas perto das paredes
				col = col.lerp(Color(0.24, 0.2, 0.2), (1.0 - k) * smoothstep(0.62, 0.82, g) * 0.8)
				# sombra logo abaixo da parede
				col = col.lerp(Color(0.02, 0.015, 0.02), (1.0 - smoothstep(0.0, 0.12, depth)) * 0.7)
				col.a = 1.0
				var vn := veins.get_noise_2d(x * 1.6, y * 0.55)
				var vein := (1.0 - smoothstep(0.0, 0.07, absf(vn))) * smoothstep(0.2, 0.7, depth)
				var seam := (1.0 - smoothstep(0.0, 0.09, du / maxf(wall, 0.001))) * taper
				var e := clampf(seam * 1.1 + vein * 0.8, 0.0, 1.0)
				glow = violet.lerp(crimson, clampf(0.5 + vn * 2.0, 0.0, 1.0)) * e
				glow = glow.lerp(Color(1.0, 0.82, 1.0), seam * seam * 0.6)
			else:
				# borda de terra partida levantada, depois a terra chamuscada sumindo
				var out := du - wall
				var lip := exp(-pow((out - 0.05) / 0.06, 2.0)) * taper
				var scorch := (1.0 - smoothstep(0.0, 0.45, out)) * (0.25 + 0.75 * taper)
				var branch := 0.0
				for b in branches:
					var dd := (u - c) * float(b[1]) - wall
					if dd <= 0.0 or dd > float(b[2]):
						continue
					var line_v := float(b[0]) + dd * float(b[3]) * 5.0 + noise.get_noise_1d(dd * 25.0 + float(b[0]) * 100.0) * 0.004
					var thick := 0.003 * (1.0 - dd / float(b[2]))
					branch = maxf(branch, 1.0 - smoothstep(thick * 0.5, thick + 0.0008, absf(v - line_v)))
				col = Color(0.11, 0.085, 0.08).lerp(Color(0.33, 0.27, 0.22), lip * (0.6 + 0.4 * g))
				col = col.lerp(Color(0.02, 0.01, 0.02), branch * 0.9)
				col.a = clampf(maxf(maxf(lip, branch), scorch * (0.35 + 0.35 * g)), 0.0, 1.0)
				glow = violet * branch * 0.35 * taper
			col.a *= smoothstep(0.0, 0.03, v) * smoothstep(1.0, 0.97, v) * (1.0 - smoothstep(0.88, 1.0, absf(u)))
			alb.set_pixel(x, y, col)
			emi.set_pixel(x, y, Color(glow.r, glow.g, glow.b, 1.0))
	_crack_images = [alb, emi]
