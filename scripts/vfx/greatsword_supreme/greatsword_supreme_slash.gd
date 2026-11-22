class_name GreatswordSupremeSlash
extends Node3D
## Lâmina Suprema (ultimate da montante): a sequência visual inteira, em cena própria
## (scenes/vfx/greatsword_supreme/greatsword_supreme_slash.tscn). GreatswordSupremeAbilities cria uma por ativação, na cena
## do mundo; ela vive mais que a habilidade e se libera sozinha (queue_free) quando o último efeito some.
##   SwordPivot      segue a montante do herói a cada quadro: na origem o cabo (`blade_base`, nas mãos), o Y na direção
##                   da lâmina (até `blade_tip`), na escala do comprimento da espada de energia
##     EnergySword   a espada gigante em chamas: malha 3D de espada (sword_mesh: lâmina com quina e ponta, guarda, cabo
##                   e pomo) com o shader de fogo (supreme_blade.gdshader): ferro escuro que pega fogo da guarda à ponta
##                   (`heat`), chamas de ruído subindo, fio aceso e miolo incandescente. O cabo dela fica nas mãos do herói
##     FlameSheet    as chamas da sprite sheet (flame_sword_sheet.webp, 8 x 4) em volta da lâmina, aditivas
##                   (supreme_flame_sheet.gdshader): acendem na carga (FLAME_IGNITE), dançam enquanto ela está formada
##                   (FLAME_LOOP) e se apagam no fim (FLAME_OUT)
##     Embers / BladeSparks / BladeSmoke  aura de GPUParticles3D ao longo da lâmina: brasas, faíscas e fumaça leve
##                   (no mundo: no corte deixam o rastro da espada)
##   Impact          (top_level) no ponto em que a ponta da espada bate no chão, virado na direção do golpe:
##     CrackDecal    a rachadura em linha reta no chão (o chão dividido pelo golpe), do herói até além da ponta
##     CrackFire     rastro de fogo ao longo da rachadura (chamas em gota, aditivas), que vai diminuindo até se apagar
##     Rocks / Dirt  pedras e torrões arremessados para os lados ao longo da rachadura (colidem com o chão: Ground)
##     Smoke / Sparks poeira e fagulhas ao longo da rachadura
##     ImpactLight   clarão alaranjado
## Fases (tempos do GreatswordSupremeConfig, os mesmos da animação do herói):
##   CHARGE   espada erguida; a espada de energia se forma do pomo até a ponta, no comprimento todo
##   SLASH    o corte: a espada acompanha a lâmina e, no fim, se inclina até a ponta tocar o chão no ponto do impacto
##   impacto  dano (sinal `impacted` com os inimigos na área: PhysicsShapeQueryParameters3D na camada dos inimigos),
##            a rachadura abrindo, partículas, luz e tremor da câmera
##   FADE     a espada se desfaz; depois de `crack_hold` a rachadura e a luz somem com Tween; DONE libera
## O dano é só do dono (`deal_damage`); nas réplicas é só o visual. `cancel()` antes do corte desfaz tudo sem dano.

signal impacted(center: Vector3, targets: Array)
signal finished

const ENEMY_MASK := 4      ## camada 3 ("enemies")
const WORLD_MASK := 1
const CANCEL_TIME := 0.25
const SWORD_DISSOLVE := 0.75   ## a espada se apaga depois do impacto (s)
const CRACK_OPEN := 0.18   ## tempo para a rachadura correr até o tamanho todo (s)
const CRACK_TEX := Vector2i(96, 768)   ## textura da rachadura: largura x comprimento (px)
const CRACK_FIRE_FULL := 0.8   ## quanto o fogo da rachadura fica forte antes de começar a diminuir (s)
## Quadros da sprite sheet das chamas (8 x 4): 1-15 o ferro pegando fogo até o miolo branco; 15-21 a espada em chamas
## (toca em vaivém enquanto ela está formada); 22-28 o fogo se apagando.
const FLAME_IGNITE := Vector2(1.0, 15.0)
const FLAME_LOOP := Vector2(15.0, 21.0)
const FLAME_OUT := Vector2(22.0, 28.0)
const FLAME_FPS := 11.0
## Proporções da malha da espada (comprimento 1 = das mãos à ponta), na medida da espada desenhada na sheet.
const BLADE_FROM := 0.085          ## onde a lâmina sai da guarda
const BLADE_HALF_W := 0.042        ## meia-largura da lâmina na guarda
const BLADE_HALF_T := 0.016        ## meia-espessura na quina do meio
const GUARD_HALF_W := 0.17
const POMMEL_Y := -0.1

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
@onready var flame_sheet: MeshInstance3D = $SwordPivot/FlameSheet
@onready var embers: GPUParticles3D = $SwordPivot/Embers
@onready var blade_sparks: GPUParticles3D = $SwordPivot/BladeSparks
@onready var blade_smoke: GPUParticles3D = $SwordPivot/BladeSmoke
@onready var impact_root: Node3D = $Impact
@onready var rocks: GPUParticles3D = $Impact/Rocks
@onready var dirt: GPUParticles3D = $Impact/Dirt
@onready var smoke: GPUParticles3D = $Impact/Smoke
@onready var sparks: GPUParticles3D = $Impact/Sparks
@onready var crack: Decal = $Impact/CrackDecal
@onready var crack_fire: GPUParticles3D = $Impact/CrackFire
@onready var light: OmniLight3D = $Impact/ImpactLight

var state := State.CHARGE
var t := 0.0
var impact_at := -1.0
var impact_center := Vector3.ZERO
var hit_count := 0
var _origin := Vector3.ZERO
var _sword_fixed := false
var _fade_started := false
var _hit := {}

static var _sword_mesh: ArrayMesh
## Texturas da rachadura (geradas uma vez numa thread, divididas por todas as ativações).
static var _crack_albedo: ImageTexture
static var _crack_emission: ImageTexture
static var _crack_images: Array = []
static var _crack_task := -1
## Textura da chama do rastro na rachadura (uma gota de fogo, gerada uma vez) e o material dela.
static var _flame_mat: StandardMaterial3D


func _ready() -> void:
	if config == null:
		config = load("res://assets/vfx/greatsword_supreme/greatsword_supreme_config.tres")
	energy_sword.mesh = sword_mesh()
	# aura da espada: brasas e faíscas aditivas, fumaça normal (material de processo próprio: o tamanho da caixa
	# de emissão acompanha a lâmina, _place_sword)
	embers.material_override = FXEpic._particle_mat(FXEpic._glow_tex(), true, true)
	blade_sparks.material_override = FXEpic._particle_mat(FXEpic._glow_tex(), true, true)
	blade_smoke.material_override = FXEpic._particle_mat(FXEpic._smoke_tex(), false)
	for p: GPUParticles3D in _aura():
		p.process_material = p.process_material.duplicate()
	sparks.material_override = FXEpic._particle_mat(FXEpic._glow_tex(), true, true)
	smoke.material_override = FXEpic._particle_mat(FXEpic._smoke_tex(), false)
	# partículas ao longo da rachadura (material próprio: o comprimento vem da configuração)
	var half := config.crack_length() * 0.5
	var k := config.debris_amount
	for p: GPUParticles3D in [rocks, dirt, smoke, sparks]:
		p.amount = maxi(1, int(round(p.amount * maxf(k, 0.05))))
		var m := p.process_material.duplicate() as ParticleProcessMaterial
		m.emission_box_extents.z = half * 0.9
		m.initial_velocity_max *= config.debris_speed / 10.0
		p.process_material = m
		p.position.z = config.crack_center_offset()
	crack.size = Vector3(config.crack_width, 4.0, config.crack_length())
	crack.position = Vector3(0.0, 0.0, config.crack_center_offset())
	# o rastro de fogo ao longo da rachadura inteira
	crack_fire.material_override = flame_material()
	var fm := crack_fire.process_material.duplicate() as ParticleProcessMaterial
	fm.emission_box_extents = Vector3(config.crack_width * 0.08, 0.02, config.crack_length() * 0.46)
	crack_fire.process_material = fm
	crack_fire.position.z = config.crack_center_offset()
	warm()
	if warm_only:
		_warm_pipelines()
		return
	_follow_now()
	_set_sword(0.0, 0.0)
	Sfx.play_at("portal", global_position + Vector3.UP * 2.0, 0.05, -4.0)


## Desenha a espada, a rachadura e as partículas um instante (o Godot prepara o pipeline de desenho de cada uma no
## primeiro uso; sem isso a primeira ultimate da sessão engasgaria).
func _warm_pipelines() -> void:
	set_process(false)
	state = State.DONE
	_set_sword(0.5, 0.01)
	_set_fire(0.5, 10.0, 0.01)
	sword_pivot.global_transform = Transform3D(Basis.IDENTITY, global_position)
	impact_root.global_position = global_position
	impact_root.visible = true
	_crack_textures()
	crack.texture_albedo = _crack_albedo
	crack.texture_emission = _crack_emission
	for p: GPUParticles3D in [rocks, dirt, smoke, sparks, crack_fire] + _aura():
		p.restart()
	get_tree().create_timer(0.6).timeout.connect(queue_free)


## Antes do corte dá para desfazer (esquiva, morte, troca de arma).
func can_cancel() -> bool:
	return state == State.CHARGE


## Desfaz sem dano: a espada de energia se apaga depressa.
func cancel() -> void:
	if not can_cancel():
		return
	state = State.CANCELED
	var a := float(energy_sword.get_instance_shader_parameter("intensity"))
	var g := float(energy_sword.get_instance_shader_parameter("grow"))
	var fl := float(flame_sheet.get_instance_shader_parameter("intensity"))
	_aura_emitting(false)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		_set_sword(g, a * v)
		flame_sheet.set_instance_shader_parameter("intensity", fl * v), 1.0, 0.0, CANCEL_TIME)
	tw.tween_callback(_finish)


func _process(delta: float) -> void:
	t += delta
	_follow_now()
	match state:
		State.CHARGE:
			var raise := config.raise_time
			var u := clampf((t - raise) / config.charge_time, 0.0, 1.0)
			# a espada de ferro se forma depressa do pomo até a ponta; depois pega fogo da guarda para a ponta, como na
			# sheet (FLAME_IGNITE), e fica em chamas até o fim da carga
			_set_sword(smoothstep(0.0, 1.0, u / 0.22), config.sword_intensity * smoothstep(0.0, 0.08, u))
			var ign := clampf((u - 0.12) / 0.73, 0.0, 1.0)
			var frame := lerpf(FLAME_IGNITE.x, FLAME_IGNITE.y, ign) if ign < 1.0 else _loop_frame()
			_set_fire(smoothstep(0.0, 1.0, ign), frame, smoothstep(0.0, 0.2, ign))
			if ign > 0.25 and not embers.emitting:
				_aura_emitting(true)
			_place_sword(0.0)
			if t >= config.charge_end():
				state = State.SLASH
				_origin = follow.global_position if _valid(follow) else global_position
				impact_center = _impact_point()
				Sfx.play_at("sword_swing_heavy", global_position + Vector3.UP * 2.0, 0.05, 2.0)
		State.SLASH:
			var u := clampf((t - config.charge_end()) / config.slash_time, 0.0, 1.0)
			_set_sword(1.0, config.sword_intensity * (1.0 + 0.3 * u))
			_set_fire(1.0, _loop_frame(), 1.0)
			# no fim do corte a espada se inclina até a ponta tocar o chão no ponto do impacto
			_place_sword(smoothstep(0.7, 1.0, u))
			if t >= config.impact_time():
				_impact()
		State.FADE:
			var since := t - impact_at
			var d := clampf((since - 0.15) / SWORD_DISSOLVE, 0.0, 1.0)
			# o fogo se apaga (FLAME_OUT), a lâmina esfria e se desfaz
			energy_sword.set_instance_shader_parameter("dissolve", smoothstep(0.45, 1.0, d))
			_set_sword(1.0, config.sword_intensity * (1.3 - 0.5 * d))
			_set_fire(1.0 - d, lerpf(FLAME_OUT.x, FLAME_OUT.y, d) if d > 0.0 else _loop_frame(), 1.0 - smoothstep(0.7, 1.0, d))
			if d > 0.4 and embers.emitting:
				_aura_emitting(false)
			if d >= 1.0 and energy_sword.visible:
				energy_sword.visible = false
				flame_sheet.visible = false
			if since >= config.crack_hold and not _fade_started:
				_fade_out()


# ------------------------------------------------------------------- espada de energia
func _valid(n: Node3D) -> bool:
	return n != null and is_instance_valid(n) and n.is_inside_tree()


## Até o corte o nó raiz acompanha o herói (posição e direção).
func _follow_now() -> void:
	if state != State.CHARGE or not _valid(follow):
		return
	global_position = follow.global_position
	rotation = Vector3(0.0, yaw, 0.0)


## A espada de energia no eixo da montante: o cabo nas mãos, a lâmina na direção do cabo para a ponta.
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
	# o gume da montante: o suporte da arma tem o Y contra o gume (KnightAnim._orient_by_path); a largura da espada de
	# fogo vai nesse eixo, para os fios ficarem onde estão os da montante (no corte, o fio vai na frente)
	var edge := Vector3.ZERO
	if _valid(blade_base):
		edge = -blade_base.global_basis.y
	edge -= dir * edge.dot(dir)
	if edge.length() < 0.01:   # sem a arma: na horizontal
		edge = dir.cross(Vector3.UP)
		if edge.length() < 0.01:
			edge = Vector3(cos(yaw), 0.0, -sin(yaw))
	edge = edge.normalized()
	var length := config.sword_length
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
	sword_pivot.global_transform = Transform3D(
		Basis(side * length * config.sword_width, dir * length, flat * length * config.sword_width), base)
	# a aura sai ao longo da lâmina (da guarda à ponta); nós top_level, sem a escala do pivô, que esticaria as partículas
	var aura := Transform3D(Basis(side, dir, flat), base + dir * length * 0.55)
	var ext := Vector3(BLADE_HALF_W * length * config.sword_width * 1.3, length * 0.45, BLADE_HALF_T * length * 2.0)
	for p: GPUParticles3D in _aura():
		p.global_transform = aura
		(p.process_material as ParticleProcessMaterial).emission_box_extents = ext


func _set_sword(grow: float, intensity: float) -> void:
	energy_sword.set_instance_shader_parameter("grow", grow)
	energy_sword.set_instance_shader_parameter("intensity", intensity)


## Fogo da espada: `heat` 0..1 no shader da lâmina (sobe da guarda para a ponta), o quadro da sheet das chamas e o
## brilho delas.
func _set_fire(heat: float, frame: float, flames: float) -> void:
	energy_sword.set_instance_shader_parameter("heat", heat)
	flame_sheet.set_instance_shader_parameter("frame", frame)
	flame_sheet.set_instance_shader_parameter("intensity", flames)


## Quadro das chamas em vaivém por FLAME_LOOP (a espada formada, o fogo dançando).
func _loop_frame() -> float:
	var span := FLAME_LOOP.y - FLAME_LOOP.x
	return FLAME_LOOP.x + pingpong(t * FLAME_FPS, span)


func _aura() -> Array[GPUParticles3D]:
	return [embers, blade_sparks, blade_smoke]


func _aura_emitting(on: bool) -> void:
	for p: GPUParticles3D in _aura():
		p.emitting = on


## Malha da espada (comprimento 1 das mãos à ponta), feita uma vez: lâmina de seção em losango (quina no meio, gumes nas
## bordas) afinando até a ponta, guarda reta, cabo e pomo em losango. Faces planas (quinas nítidas). UV.x na lâmina vai
## de 0 no gume a 1 na quina; COLOR.r = 1 na lâmina e 0 no resto (supreme_blade.gdshader).
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


# ------------------------------------------------------------------- impacto
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


func _impact() -> void:
	state = State.FADE
	impact_at = t
	_place_sword(1.0)
	_sword_fixed = true   # a espada de energia fica cravada enquanto se desfaz
	impact_root.global_position = impact_center
	impact_root.global_rotation = Vector3(0.0, yaw, 0.0)
	impact_root.visible = true
	_crack_textures()   # normalmente já prontas (warm, numa thread, desde o começo da carga)
	crack.texture_albedo = _crack_albedo
	crack.texture_emission = _crack_emission
	for p: GPUParticles3D in [rocks, dirt, smoke, sparks]:
		p.restart()
	# a rachadura corre pelo chão num estalo, com as brasas acesas, e esfria
	crack.scale = Vector3(0.6, 1.0, 0.05)
	crack.emission_energy = 5.0
	# o fogo acende na rachadura e vai diminuindo até se apagar (menos chamas a cada instante)
	crack_fire.amount_ratio = 1.0
	crack_fire.emitting = true
	var ft := create_tween()
	ft.tween_interval(CRACK_FIRE_FULL)
	var dim := maxf(config.crack_hold + config.fade_time * 0.4 - CRACK_FIRE_FULL, 0.3)
	ft.tween_property(crack_fire, "amount_ratio", 0.0, dim).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	ft.tween_callback(func() -> void: crack_fire.emitting = false)
	var tw := create_tween().set_parallel()
	tw.tween_property(crack, "scale", Vector3.ONE, CRACK_OPEN).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(crack, "emission_energy", 1.4, 1.0)
	light.light_energy = 3.5
	tw.tween_property(light, "light_energy", 1.0, 0.6).set_ease(Tween.EASE_OUT)
	_shake_local(impact_center)
	Sfx.play_at("explode", impact_center, 0.05, 0.0)
	Sfx.play_at("slam", impact_center, 0.08, 0.0)
	Sfx.play_at("chop_stone", impact_center, 0.15, -4.0)
	var targets := _collect_targets() if deal_damage else []
	hit_count = targets.size()
	impacted.emit(impact_center, targets)


## Inimigos na área do golpe: uma consulta de forma (esfera que cobre o ponto do impacto e o caminho da lâmina) na
## camada dos inimigos, filtrada pela área exata (GreatswordSupremeRules) e por quem já levou o golpe.
func _collect_targets() -> Array:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return []
	var mid := (_origin + impact_center) * 0.5
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(config.impact_radius + _origin.distance_to(impact_center) * 0.5, config.impact_radius) + 1.0
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
	return GreatswordSupremeRules.pick_targets(cands, _origin, impact_center, config.impact_radius, config.cut_half_width,
		_hit).map(func(x: Dictionary) -> Node: return x.node)


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


# ------------------------------------------------------------------- dissipação
## A rachadura e a luz somem aos poucos (Tween) e o nó se libera no fim.
func _fade_out() -> void:
	_fade_started = true
	var ft := config.fade_time
	var tw := create_tween().set_parallel()
	tw.tween_property(crack, "modulate", Color(1, 1, 1, 0), ft).set_ease(Tween.EASE_IN)
	tw.tween_property(crack, "emission_energy", 0.0, ft * 0.7)
	tw.tween_property(light, "light_energy", 0.0, ft * 0.5)
	tw.chain().tween_callback(_finish)


func _finish() -> void:
	if state == State.DONE:
		return
	state = State.DONE
	finished.emit()
	queue_free()


# ------------------------------------------------------------------- textura da rachadura
## Começa a gerar as texturas da rachadura numa thread (a habilidade chama ao começar: a carga dura mais que isso).
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


## Rachadura vista de cima, em linha reta ao longo da textura (largura x comprimento = CRACK_TEX): a fenda escura e
## irregular no meio, mais larga no centro e fechando nas pontas, com a borda de terra levantada, rachaduras finas
## saindo para os lados e brasas no fundo (emissão). Determinística (mesma semente sempre): gerada uma vez.
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
	grain.frequency = 0.08
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	# rachaduras finas para os lados: [v onde sai, lado, comprimento (u), inclinação]
	var branches := []
	for i in 14:
		branches.append([rng.randf_range(0.08, 0.92), -1.0 if i % 2 == 0 else 1.0, rng.randf_range(0.35, 0.85),
			rng.randf_range(-0.05, 0.05)])
	var centers := PackedFloat32Array()
	centers.resize(h)
	for y in h:
		var v := (y + 0.5) / h
		centers[y] = noise.get_noise_1d(v * 9.0) * 0.12 + noise.get_noise_1d(v * 37.0 + 50.0) * 0.045
	for b in branches:
		b.append(centers[clampi(int(float(b[0]) * h), 0, h - 1)])
	for y in h:
		var v := (y + 0.5) / h
		var taper := pow(sin(PI * v), 0.6)
		var c: float = centers[y]
		var wid := 0.05 + 0.2 * taper
		for x in w:
			var u := (x + 0.5) / w * 2.0 - 1.0
			var d := absf(u - c)
			var fissure := 1.0 - smoothstep(wid * 0.55, wid, d)
			var rim := exp(-pow((d - wid * 1.1) / 0.07, 2.0)) * taper
			var scorch := (1.0 - smoothstep(0.0, 0.85, d)) * taper
			var branch := 0.0
			for b in branches:
				var du := (u - float(b[4])) * float(b[1])
				if du <= 0.0 or du > float(b[2]):
					continue
				var line_v := float(b[0]) + du * float(b[3]) * 6.0 + noise.get_noise_1d(du * 20.0 + float(b[0]) * 100.0) * 0.004
				var thick := 0.0035 * (1.0 - du / float(b[2]))
				branch = maxf(branch, 1.0 - smoothstep(thick * 0.5, thick + 0.0008, absf(v - line_v)))
			var g := grain.get_noise_2d(x, y) * 0.5 + 0.5
			var col := Color(0.12, 0.09, 0.07).lerp(Color(0.33, 0.25, 0.18), rim * 0.8)
			col = col.lerp(Color(0.02, 0.015, 0.012), maxf(fissure, branch * 0.9))
			var alpha := maxf(maxf(fissure, branch), maxf(rim * 0.85, scorch * (0.35 + 0.3 * g)))
			alpha *= smoothstep(0.0, 0.04, v) * smoothstep(1.0, 0.96, v) * (1.0 - smoothstep(0.85, 1.0, absf(u)))
			alb.set_pixel(x, y, Color(col.r, col.g, col.b, clampf(alpha, 0.0, 1.0)))
			var glow := (1.0 - smoothstep(0.0, wid * 0.5, d)) * taper + branch * 0.35
			emi.set_pixel(x, y, Color(1.0, 0.45, 0.1).lerp(Color(1.0, 0.85, 0.5), clampf(glow - 0.6, 0.0, 1.0)) * clampf(glow, 0.0, 1.0))
	_crack_images = [alb, emi]


## Material das chamas do rastro na rachadura: uma gota de fogo (base redonda, ponta para cima, borda tremida), aditiva,
## com a cor das partículas (a rampa vai do amarelo ao vermelho e apaga). Gerada uma vez.
static func flame_material() -> StandardMaterial3D:
	if _flame_mat != null:
		return _flame_mat
	var w := 64
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 3
	noise.frequency = 0.09
	for y in h:
		var v := 1.0 - (y + 0.5) / h   # 0 = base, 1 = ponta
		for x in w:
			var u := (x + 0.5) / w * 2.0 - 1.0
			# meia-largura da gota: cheia embaixo, afinando até a ponta, tremida pelo ruído
			var half := 0.78 * pow(1.0 - v, 0.75) * smoothstep(0.0, 0.18, v + 0.06)
			half *= 0.85 + 0.3 * (noise.get_noise_2d(x * 1.5, y) * 0.5 + 0.5)
			var a := 1.0 - smoothstep(half * 0.45, half, absf(u))
			a *= 1.0 - smoothstep(0.75, 1.0, v)
			var core := (1.0 - smoothstep(0.0, half * 0.5, absf(u))) * (1.0 - smoothstep(0.2, 0.6, v))
			var c := 0.75 + 0.25 * core
			img.set_pixel(x, y, Color(c, c, c, clampf(a, 0.0, 1.0)))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shadow_to_opacity = false
	_flame_mat = m
	return _flame_mat
