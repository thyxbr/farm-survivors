class_name SwordVortexFX
extends Node3D
## Vórtice Sombrio (SwordVortexAbilities): o visual inteiro, feito em código. Um por ativação, na cena do mundo; segue
## o herói, vive um pouco mais que a habilidade (a meia-lua se desfazendo) e se libera sozinho.
## O giro (medido na referência: o anel tem ~3,4x a altura do personagem, aqui ~2,4 m de raio):
##   lens      a lente: disco na altura da cintura, vidro escuro translúcido com riscos em espiral por dentro, fumaça
##             grossa e a borda violeta acesa (forte na cabeça, com halo) que se apaga uma volta atrás da lâmina
##             (vortex_lens*.gdshader); balança um pouco (não fica chapada na horizontal)
##   orbit     tufos de fumaça (MultiMesh, smoke_flip.gdshader tocando fumaca_folha.png, 4x4 quadros de uma baforada)
##             que nascem na cabeça do giro em toda a altura do corpo, são arrastados em volta do herói pelo giro
##             (perdendo velocidade) e se desfazem
##   rings     a parede do redemoinho: fitas em pé com a fumaça pintada arrastada (fumaca_faixa.png, smoke_strip) e a
##             fita baixa rente ao chão
##   tails     rabos pendurados da lente ao chão com o fiapo pintado (fumaca_fiapo.png)
##   cut       o corte aceso: LayeredSlashTrail preso à lâmina de verdade (cabo e ponta a cada quadro), esticado além da
##             ponta até a borda da lente; sobe, desce e inclina com o braço, como a lâmina. Vida curta (meia volta):
##             mais longa, girando, vira um disco cheio
##   edge      um tubo de luz fraco na borda da lente, atrás do corte (o brilho que fica da volta anterior)
##   smoke     a fumaça negra: tufos grandes soltos ao longo da altura da parede, na cabeça do giro, que ficam no ar
##             e desenham o anel de fumaça atrás da lâmina
##   head      o brilho largo da cabeça do giro (onde a lâmina está), branco-violeta
##   tails     rabos de fumaça preta pendurados da lente até o chão, que ficam para trás no giro
##   wisps     fumaça escura e faíscas violeta soltas pela ponta enquanto gira
##   light     luz violeta no chão, com a força do giro
##   spin_hit  o alvo pisca dourado (Enemy.flash_with + gold_flash.gdshader) e solta faíscas laranja
##   finale    no começo do golpe final: clarão violeta enorme, risco de luz na horizontal e raios para cima; no fim
##             dele: a meia-lua de fumaça negra e violeta pelo caminho que a lâmina fez, bem maior que ela, que fica no
##             ar e se desfaz da cauda para a cabeça, com fumaça e faíscas ao longo
##   final_hit lascas escuras voando do alvo, faíscas e o clarão dourado
## Todas as cores na paleta da energia sombria (DarkEnergy); `color` = o violeta das partes aditivas.

const VIOLET := Color(0.55, 0.22, 1.0)
const VORTEX_MAT := preload("res://assets/vfx/sword_vortex/vortex_mat.tres")
const LENS_MAT := preload("res://assets/vfx/sword_vortex/vortex_lens_mat.tres")
const EDGE_SHADER := preload("res://shaders/sword_vortex/edge_tube.gdshader")
const NOISE_TEX := preload("res://assets/vfx/slash_layers/slash_noise.tres")
const EDGE_R := 0.82        ## o corte aceso corre nesta fração do raio da lente
const EDGE_H := 0.32        ## altura do tubo (m)
const EDGE_SKIRT := 0.75    ## a saia: o rastro da lâmina descendo da borda acesa e se apagando (m)
const EDGE_W := 0.45        ## largura do tubo deitado (m)
const EDGE_TURN := 0.9      ## quanto da volta o corte aceso cobre atrás da lâmina
const CUT_REACH := 0.7      ## o corte passa da ponta da lâmina até perto da borda da lente (m)
const EDGE_DIM := 0.35      ## o tubo da borda fica fraco: quem acende é o corte da lâmina
const LENS_H := 0.95       ## altura da lente (m)
const LENS_R := 2.4        ## raio da lente (m)
const LENS_SEG := 72       ## segmentos na volta
const LENS_RINGS := 6      ## segmentos no raio
const LENS_TURN := 1.1     ## quantas voltas a lente cobre atrás da cabeça
## Rabos de fumaça: atraso atrás da cabeça (rad) e quanto o pé se afasta para fora (m).
const TAILS := [[0.9, 0.25], [2.3, 0.4], [3.7, 0.15]]
const FLASH_SHADER := preload("res://shaders/sword_vortex/soft_flash.gdshader")
const GOLD_SHADER := preload("res://shaders/sword_vortex/gold_flash.gdshader")
const TEX_FLASH_SHADER := preload("res://shaders/sword_vortex/tex_flash.gdshader")
const FLARE_TEX := preload("res://assets/vfx/sword_vortex/clarao.png")
const ORANGE := Color(1.0, 0.55, 0.2)
## Fitas em espiral: altura do meio (m), raio do meio (m), largura (m), inclinação da fita (rad: 0 = deitada,
## PI/2 = em pé; a borda de fora fica mais alta, como a parede de um redemoinho), sobe e desce na volta (m), atraso da
## cabeça em relação à ponta da lâmina (rad), quanto arco a fita cobre (rad) e quanto a cauda sobe ou desce (m).
const RINGS := [
	{"h": 0.12, "r": 2.35, "w": 0.3, "slope": 0.4, "tilt": 0.05, "lag": 0.5, "arc": 5.5, "rise": 0.0, "rim": 2.0},
	# parede pintada: do joelho até acima da lente, quase em pé; duas, em raios e atrasos diferentes
	{"h": 0.55, "r": 2.3, "w": 0.8, "slope": 1.4, "tilt": 0.08, "lag": 0.1, "arc": 4.2, "rise": -0.1, "strip": true},
]
const STRIP_MAT := preload("res://assets/vfx/sword_vortex/smoke_wall_mat.tres")
const TAIL_MAT := preload("res://assets/vfx/sword_vortex/smoke_tail_mat.tres")
const SHEET_SHADER := preload("res://shaders/sword_vortex/smoke_flip.gdshader")
const SHEET_TEX := preload("res://assets/vfx/sword_vortex/fumaca_folha.png")
const ORBIT_MAX := 480          ## tufos ao mesmo tempo
const ORBIT_RATE := 75.0       ## tufos por segundo com o giro cheio
const ORBIT_DRAG := 1.6         ## quanto o tufo perde da velocidade do giro (1/s)
const SMOKE_DARK := Color(0.045, 0.012, 0.08)
const SMOKE_VIOLET := Color(0.2, 0.06, 0.36)
const SEG := 48
const CRESCENT_LIFE := 1.5
const CRESCENT_IN := 0.7
const CRESCENT_OUT := 4.4
const CRESCENT_MIN_ARC := 2.6   ## a meia-lua cobre pelo menos ~150°
const CRESCENT_SEG := 40
const CRESCENT_DIAG := 1.1      ## quanto o começo da meia-lua fica acima da cabeça (m)

var follow: Node3D
var model: Node3D
var blade_base: Node3D
var blade_tip: Node3D
var color := VIOLET

var _head: MeshInstance3D
var _orbit: MultiMeshInstance3D
var _puffs: Array[Dictionary] = []
var _puff_acc := 0.0
var _prev_head := 0.0
var _spin_w := 0.0          ## velocidade do giro agora (rad/s)
var _lens: MeshInstance3D
var _lens_mesh := ImmediateMesh.new()
var _edge: MeshInstance3D
var _edge_mesh := ImmediateMesh.new()
var _cut: LayeredSlashTrail
var _tails: MeshInstance3D
var _tails_mesh := ImmediateMesh.new()
var _rings: Array[MeshInstance3D] = []
var _ring_mesh: Array[ImmediateMesh] = []
var _light: OmniLight3D
var _wisps: GPUParticles3D
var _motes: GPUParticles3D
var _gold: ShaderMaterial
var _spin := 0.0          ## força do giro agora (0..1)
var _fade := 1.0          ## apagar no fim (stop/finish)
var _ending := false
var _t := 0.0
var _fin_rec := false
var _fin_pts: Array[Vector3] = []
var _fin_center := Vector3.ZERO
var _crescent: MeshInstance3D
var _crescent_mesh := ImmediateMesh.new()
var _core: MeshInstance3D
var _core_mesh := ImmediateMesh.new()
var _puff: MeshInstance3D
var _puff_mesh := ImmediateMesh.new()
var _cres_a0 := 0.0
var _cres_a1 := 0.0
var _cres_h := 1.0
var _crescent_t := -1.0
var _head_angle := 0.0


func _ready() -> void:
	top_level = true
	# sem rastro na lâmina: deitada e girando, ele vira um disco cheio no chão; a lente e as fitas (puxadas pela ponta)
	# já são o rastro do giro
	_lens = _mesh_node(_lens_mesh, LENS_MAT)
	var em := ShaderMaterial.new()
	em.shader = EDGE_SHADER
	em.set_shader_parameter("noise_tex", NOISE_TEX)
	em.render_priority = 3
	_edge = _mesh_node(_edge_mesh, em)
	_cut = LayeredSlashTrail.new()
	add_child(_cut)
	_cut.base_node = blade_base
	_cut.tip_node = blade_tip
	_cut.lifetime = 0.3   # uma volta: com a lâmina subindo em rosca, as voltas ficam em níveis diferentes (não vira disco)
	_cut.arc_life = 1.6
	# o corte vai do cabo até a borda da lente: espada curta estica além da ponta, a montante quase não precisa
	var blade_len := 1.0
	if _valid(blade_base) and _valid(blade_tip):
		blade_len = blade_base.global_position.distance_to(blade_tip.global_position)
	_cut.reach = clampf(CUT_REACH + 0.9 - blade_len, 0.15, CUT_REACH)
	_cut.hilt = 0.1   # largo: do cabo (a cabeça do corte grossa, como na referência)
	_cut.min_speed = 4.0
	_cut.full_speed = 12.0
	_cut.emitting = false
	_cut.set_color(color)
	_cut.show_arcs = false
	_cut.head_w = 1.0
	_cut.tail_pow = 1.6
	# brilho largo na cabeça do giro (quad virado para a câmera, soft_flash)
	_head = MeshInstance3D.new()
	var hq := QuadMesh.new()
	var hm := ShaderMaterial.new()
	hm.shader = FLASH_SHADER
	hq.material = hm
	_head.mesh = hq
	_head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_head.top_level = true
	_head.scale = Vector3(1.3, 0.6, 1.0)
	_head.set_instance_shader_parameter("col", Vector3(color.r, color.g, color.b))
	_head.set_instance_shader_parameter("stretch", 1.6)
	_head.set_instance_shader_parameter("intensity", 0.0)
	add_child(_head)
	_tails = _mesh_node(_tails_mesh, TAIL_MAT)
	_tails.set_instance_shader_parameter("rim_pos", 2.0)
	_tails.set_instance_shader_parameter("smoke_col", Vector3(0.02, 0.005, 0.04))
	for i in RINGS.size():
		var m := MeshInstance3D.new()
		var im := ImmediateMesh.new()
		m.mesh = im
		m.material_override = STRIP_MAT if RINGS[i].get("strip", false) else VORTEX_MAT
		m.top_level = true
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.extra_cull_margin = 4.0
		m.set_instance_shader_parameter("seed", randf() * 10.0)
		m.set_instance_shader_parameter("intensity", 1.0)
		m.set_instance_shader_parameter("rim_pos", float(RINGS[i].get("rim", 2.0)))   # 2 = só fumaça
		add_child(m)
		m.global_transform = Transform3D.IDENTITY
		_rings.append(m)
		_ring_mesh.append(im)
	_crescent = MeshInstance3D.new()
	_crescent.mesh = _crescent_mesh
	_crescent.material_override = VORTEX_MAT
	_crescent.top_level = true
	_crescent.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_crescent.extra_cull_margin = 8.0
	_crescent.set_instance_shader_parameter("seed", randf() * 10.0)
	_crescent.set_instance_shader_parameter("smoke_col", Vector3(0.08, 0.02, 0.14))
	_crescent.set_instance_shader_parameter("rim_pos", 2.0)   # sem fio aceso: só fumaça
	_crescent.set_instance_shader_parameter("soft", 1.0)
	add_child(_crescent)
	_crescent.global_transform = Transform3D.IDENTITY
	# a fumaça que sobe da meia-lua: outra camada de nuvem, mais alta e inclinada (a borda de fora mais alta), que vai
	# subindo enquanto se desfaz; dá volume ao corte (sem ela a meia-lua é uma fita chata)
	_puff = MeshInstance3D.new()
	_puff.mesh = _puff_mesh
	_puff.material_override = VORTEX_MAT
	_puff.top_level = true
	_puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_puff.extra_cull_margin = 8.0
	_puff.sorting_offset = -0.1
	_puff.set_instance_shader_parameter("seed", randf() * 10.0 + 3.0)
	_puff.set_instance_shader_parameter("smoke_col", Vector3(0.13, 0.035, 0.2))
	_puff.set_instance_shader_parameter("rim_pos", 2.0)   # sem fio aceso
	_puff.set_instance_shader_parameter("soft", 1.0)
	_puff.set_instance_shader_parameter("intensity", 0.8)
	add_child(_puff)
	_puff.global_transform = Transform3D.IDENTITY
	# o fio negro no meio da meia-lua
	_core = MeshInstance3D.new()
	_core.mesh = _core_mesh
	_core.material_override = VORTEX_MAT
	_core.top_level = true
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_core.extra_cull_margin = 8.0
	_core.sorting_offset = 0.2
	_core.set_instance_shader_parameter("seed", randf() * 10.0)
	_core.set_instance_shader_parameter("smoke_col", Vector3(0.01, 0.0, 0.02))
	_core.set_instance_shader_parameter("rim_pos", 2.0)
	add_child(_core)
	_core.global_transform = Transform3D.IDENTITY
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 0.0
	_light.omni_range = 5.5
	_light.shadow_enabled = false
	add_child(_light)
	_wisps = DarkEnergy.wisps(40, 1.0, 1.0)   # fiapos que sobem da cabeça do giro
	_orbit = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = SHEET_SHADER
	mat.set_shader_parameter("sheet", SHEET_TEX)
	q.material = mat
	mm.mesh = q
	mm.instance_count = ORBIT_MAX
	mm.visible_instance_count = 0
	_orbit.multimesh = mm
	_orbit.top_level = true
	_orbit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_orbit.extra_cull_margin = 6.0
	add_child(_orbit)
	_orbit.global_transform = Transform3D.IDENTITY
	_motes = DarkEnergy.motes(40, 0.7, 0.08)
	for p: GPUParticles3D in [_wisps, _motes]:
		add_child(p)
		p.top_level = true
		p.amount_ratio = 0.0
		p.emitting = true
	_gold = ShaderMaterial.new()
	_gold.shader = GOLD_SHADER
	if _valid(follow):
		global_position = follow.global_position


func _valid(n: Variant) -> bool:   # sem tipo: pode chegar um nó já liberado
	return n != null and is_instance_valid(n) and n.is_inside_tree()


## Tempo da habilidade (SwordVortexAbilities.tick): a força do giro e a gravação do caminho do golpe final.
func set_phase(t: float) -> void:
	var fin := SwordVortexAbilities.finale_at()
	var w := SwordVortexAbilities.WINDUP
	var f := SwordVortexAbilities.FINALE
	_spin = smoothstep(w - 0.08, w + 0.22, t) * (1.0 - smoothstep(fin + f, fin + f + 0.2, t))
	_fin_rec = t >= fin - 0.02 and t <= fin + f + 0.02


## Começo do golpe final: o clarão, o risco de luz e os raios, à frente de onde a lâmina passa.
func finale_start() -> void:
	_fin_pts.clear()
	if not _valid(follow) or not _valid(blade_tip):
		return
	_fin_center = follow.global_position
	var tip := blade_tip.global_position
	var out := tip - _fin_center
	out.y = 0.0
	out = out.normalized() if out.length() > 0.01 else Vector3.FORWARD
	var at := _fin_center + out * 1.6 + Vector3.UP * 1.0
	var pal := {"core": Color.WHITE, "mid": color.lerp(Color.WHITE, 0.6), "edge": color.lerp(Color.WHITE, 0.2)}
	# o clarão pintado (clarao.png), duas cópias: uma grande que gira pouco e uma menor, girada e mais rápida, para os
	# raios não ficarem iguais; por baixo um brilho macio largo (o bloom)
	_tex_flash(at, color, 1.0, 7.5, 0.26, 0.25)
	_tex_flash(at, color.lerp(Color.WHITE, 0.4), 0.8, 4.5, 0.18, -0.6, 0.5)
	_soft_flash(at, color, 1.4, 9.0, 0.24, 2.2)
	FXEpic.smoke(at + out * 0.6, Color(0.05, 0.015, 0.08, 0.85), 14, 1.4, 0.9)   # a nuvem escura atrás do clarão
	FXEpic.flash(at, color, 10.0, 12.0, 0.45)
	# risco de luz deitado, atravessando a tela (o "lens flare" das referências)
	var side := Vector3.UP.cross(out).normalized()
	var streak_pal := {"core": Color.WHITE, "mid": ORANGE.lerp(Color.WHITE, 0.4), "edge": ORANGE}
	FXToon.streak(at - side * 9.0, at + side * 9.0, 0.035, streak_pal,
		{"billboard": true, "shadow": false, "sweep": 0.04, "hold": 0.06, "fade": 0.22, "peak": 0.5, "lead": 0.5})
	# raios para cima, em leque
	for i in 6:
		var d := (Vector3.UP * 1.2 + side * randf_range(-1.1, 1.1) + out * randf_range(-0.4, 0.4)).normalized()
		FXToon.streak(at + d * 0.3, at + d * randf_range(3.0, 5.5), randf_range(0.035, 0.07), pal,
			{"billboard": true, "shadow": false, "sweep": 0.05, "hold": 0.05, "fade": 0.3, "peak": 0.45,
			"lead": 0.3, "delay": randf_range(0.0, 0.05)})


## Fim do golpe final: a meia-lua de fumaça fica no ar pelo caminho que a lâmina fez.
func finale_end() -> void:
	if _fin_pts.size() < 3:
		return
	_crescent_t = 0.0
	_crescent_arc()
	# faíscas e fumaça ao longo da meia-lua, saindo para onde o golpe corria (da cauda para a cabeça)
	for i in 8:
		var u := 0.08 + 0.84 * float(i) / 7.0
		var p := _crescent_point(u, 0.5)
		var tan := (_crescent_point(u - 0.05, 0.5) - p).normalized()
		FXEpic.sparks(p, tan + Vector3.UP * 0.12, ORANGE, 20, 15.0, 0.6)
		if i % 2 == 0:
			FXEpic.smoke(_crescent_point(u + 0.05, 0.72), Color(0.1, 0.03, 0.16, 0.55), 6, 1.0, 1.6)


## Corte do giro em `e`: clarão dourado e faíscas laranja para onde a lâmina corre.
func spin_hit(e: Node3D) -> void:
	if e.has_method("flash_with"):
		e.flash_with(_gold, 0.16)
	var to := e.global_position - global_position
	to.y = 0.0
	var along := Vector3.UP.cross(to).normalized() if to.length() > 0.01 else Vector3.UP
	FXEpic.sparks(e.global_position + Vector3.UP * 0.9, along + Vector3.UP * 0.3, ORANGE, 10, 8.0, 0.3)


## Golpe final em `e`: lascas escuras voando, faíscas e o clarão dourado.
func final_hit(e: Node3D) -> void:
	if e.has_method("flash_with"):
		e.flash_with(_gold, 0.22)
	var at := e.global_position + Vector3.UP * 0.9
	var out := e.global_position - global_position
	out.y = 0.0
	out = out.normalized() if out.length() > 0.01 else Vector3.FORWARD
	FXEpic.sparks(at, out + Vector3.UP * 0.4, ORANGE, 18, 11.0, 0.45)
	var root := FX._scene()
	if root == null:
		return
	for i in 28:
		var s := Shard.new()
		root.add_child(s)
		s.global_position = at + Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.4), randf_range(-0.3, 0.3))
		s.vel = (out * randf_range(0.8, 2.5) + Vector3.UP * randf_range(3.0, 6.5) + _rand_flat() * 1.8)
		s.size = randf_range(0.09, 0.22)
		s.spin = Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12))


## Parar depressa (esquiva, morte, troca de arma).
func stop() -> void:
	_ending = true
	_cut.emitting = false
	var tw := create_tween()
	tw.tween_property(self, "_fade", 0.0, 0.15)
	tw.tween_callback(queue_free)


## Fim natural: as fitas se apagam, a meia-lua termina de se desfazer, e libera.
func finish() -> void:
	_ending = true
	_cut.emitting = false
	get_tree().create_timer(CRESCENT_LIFE + 0.4).timeout.connect(queue_free)


func _process(delta: float) -> void:
	_t += delta
	if _valid(follow):
		global_position = follow.global_position
	var s := _spin * _fade
	_light.global_position = global_position + Vector3.UP * 0.35
	_light.light_energy = 2.4 * s
	if _valid(blade_tip):
		var tip := blade_tip.global_position
		if _fin_rec:
			_fin_pts.append(tip)
		var rel := tip - global_position
		_head_angle = atan2(rel.x, rel.z)
		# a fumaça sai da cabeça do giro, na altura inteira da parede (do joelho ao peito)
		var hd := Vector3(sin(_head_angle), 0.0, cos(_head_angle))
		var foot := global_position + hd * (LENS_R * 0.95) + Vector3.UP * 0.15
		DarkEnergy.along_blade(_wisps, foot, foot + Vector3.UP * 1.4, 0.0, 0.35)
		_wisps.amount_ratio = s
		_motes.global_position = tip
		_motes.amount_ratio = s
		_head.global_position = global_position + hd * (LENS_R * 0.88) + Vector3.UP * (LENS_H - 0.05)
		_head.set_instance_shader_parameter("intensity", 0.8 * s)
	for i in _rings.size():
		_build_ring(i, s)
	_step_orbit(delta, s)
	_build_lens(s)
	_build_edge(s)
	_cut.emitting = s > 0.3 and not _ending
	_cut.intensity = _fade
	_build_tails(s)
	_build_crescent(delta)


func _mesh_node(m: ImmediateMesh, mat: Material) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = m
	n.material_override = mat
	n.top_level = true
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.extra_cull_margin = 6.0
	n.set_instance_shader_parameter("seed", randf() * 10.0)
	add_child(n)
	n.global_transform = Transform3D.IDENTITY
	return n


# --- fumaça em volta ---------------------------------------------------------------------------------------------

func _step_orbit(delta: float, s: float) -> void:
	if delta > 0.0:
		var w := wrapf(_head_angle - _prev_head, -PI, PI) / delta
		_spin_w = lerpf(_spin_w, w, 1.0 - exp(-10.0 * delta))
	_prev_head = _head_angle
	# nascem na cabeça do giro, do joelho ao peito, perto da borda da lente
	_puff_acc += delta * ORBIT_RATE * s
	while _puff_acc >= 1.0 and _puffs.size() < ORBIT_MAX:
		_puff_acc -= 1.0
		var hgt := LENS_H + 0.55 - 1.4 * pow(randf(), 0.7)   # mais perto da lente, escorrendo até o chão
		_puffs.append({"a": _head_angle - randf_range(0.0, 0.5), "r": LENS_R * randf_range(0.88, 1.02),
			"y": hgt, "w": _spin_w * randf_range(0.55, 0.85), "vy": randf_range(-0.35, 0.1), "t": 0.0,
			"life": randf_range(0.5, 0.8), "size": randf_range(0.5, 0.85),
			"violet": randf() < 0.15, "rot": randf() * TAU})
	if _puff_acc >= 1.0:
		_puff_acc = 0.0
	var mm := _orbit.multimesh
	var i := 0
	var n := 0
	while i < _puffs.size():
		var p: Dictionary = _puffs[i]
		p.t = float(p.t) + delta
		var k := float(p.t) / float(p.life)
		if k >= 1.0:
			_puffs.remove_at(i)
			continue
		p.w = float(p.w) * exp(-ORBIT_DRAG * delta)
		p.a = float(p.a) + float(p.w) * delta
		p.r = float(p.r) + 0.15 * delta          # abre devagar para fora
		p.y = float(p.y) + float(p.vy) * delta
		var pos := global_position + Vector3(sin(p.a), 0.0, cos(p.a)) * float(p.r) + Vector3.UP * float(p.y)
		var sz := float(p.size) * (0.8 + 0.6 * k)
		# esticado na direção do giro (rastro de movimento), mais redondo quando perde velocidade
		var str := 1.0
		mm.set_instance_transform(n, Transform3D(Basis.from_scale(Vector3(sz * str, sz, sz)), pos))
		# a baforada nasce no quadro 2 (já formada) e se desfaz até o 15
		mm.set_instance_custom_data(n, Color(lerpf(2.0, 15.0, k), float(p.rot), 0.0, 0.0))
		var c: Color = SMOKE_VIOLET if p.violet else SMOKE_DARK
		var alpha := smoothstep(0.0, 0.1, k) * (0.35 if p.violet else 0.5) * _fade   # quem some é a folha
		mm.set_instance_color(n, Color(c.r, c.g, c.b, alpha))
		n += 1
		i += 1
	mm.visible_instance_count = n


# --- lente --------------------------------------------------------------------------------------------------------

## Ponto da lente no ângulo `a` e raio `r` (m): o plano balança devagar (inclinação ~0,12 rad girando).
func _lens_point(a: float, r: float) -> Vector3:
	var d := Vector3(sin(a), 0.0, cos(a))
	var wob := 0.12 * r * sin(a - _t * 2.2)
	return global_position + d * r + Vector3.UP * (LENS_H + wob)


## O corte aceso: duas fitas em cruz (em pé e deitada) seguindo a borda da lente, formando um tubo de luz com
## espessura; afina na cauda. O shader acende a frente (lado da câmera) e apaga o fundo.
func _build_edge(s: float) -> void:
	_edge_mesh.clear_surfaces()
	if s < 0.01:
		return
	_edge.set_instance_shader_parameter("center", global_position)
	_edge.set_instance_shader_parameter("intensity", _fade * EDGE_DIM)
	var r := LENS_R * (0.75 + 0.25 * s) * EDGE_R
	var col := Color(1, 1, 1, s)
	_edge_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for pass_i in 3:
		var prev_a := Vector3.ZERO
		var prev_b := Vector3.ZERO
		var prev_u := 0.0
		for k in LENS_SEG + 1:
			var u := float(k) / float(LENS_SEG) * EDGE_TURN
			var ang := _head_angle - u * TAU
			var p := _lens_point(ang, r)
			var taper := 1.0 - 0.6 * (u / EDGE_TURN)
			var off: Vector3
			var a: Vector3
			var b: Vector3
			if pass_i == 0:
				off = Vector3.UP * EDGE_H * 0.5 * taper
				a = p - off
				b = p + off
			elif pass_i == 1:
				off = Vector3(sin(ang), 0.0, cos(ang)) * EDGE_W * 0.5 * taper
				a = p - off
				b = p + off
			else:
				# saia: da borda para baixo, um pouco para dentro (a lâmina passou inclinada)
				a = p - Vector3.UP * EDGE_SKIRT * taper - Vector3(sin(ang), 0.0, cos(ang)) * 0.15
				b = p
			var c := col if pass_i < 2 else Color(1, 0, 1, s)   # G = 0: o shader desenha a saia
			if k > 0:
				_v(_edge_mesh, prev_a, Vector2(prev_u, 0.0), c)
				_v(_edge_mesh, prev_b, Vector2(prev_u, 1.0), c)
				_v(_edge_mesh, b, Vector2(u / EDGE_TURN, 1.0), c)
				_v(_edge_mesh, prev_a, Vector2(prev_u, 0.0), c)
				_v(_edge_mesh, b, Vector2(u / EDGE_TURN, 1.0), c)
				_v(_edge_mesh, a, Vector2(u / EDGE_TURN, 0.0), c)
			prev_a = a
			prev_b = b
			prev_u = u / EDGE_TURN
	_edge_mesh.surface_end()


func _build_lens(s: float) -> void:
	_lens_mesh.clear_surfaces()
	if s < 0.01:
		return
	_lens_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color(1, 1, 1, s)
	var r_max := LENS_R * (0.75 + 0.25 * s)   # abre com o giro
	for i in LENS_SEG:
		var u0 := float(i) / float(LENS_SEG) * LENS_TURN
		var u1 := float(i + 1) / float(LENS_SEG) * LENS_TURN
		var a0 := _head_angle - u0 * TAU
		var a1 := _head_angle - u1 * TAU
		for j in LENS_RINGS:
			var v0 := float(j) / float(LENS_RINGS)
			var v1 := float(j + 1) / float(LENS_RINGS)
			var p00 := _lens_point(a0, v0 * r_max)
			var p01 := _lens_point(a0, v1 * r_max)
			var p10 := _lens_point(a1, v0 * r_max)
			var p11 := _lens_point(a1, v1 * r_max)
			_v(_lens_mesh, p00, Vector2(u0, v0), col)
			_v(_lens_mesh, p01, Vector2(u0, v1), col)
			_v(_lens_mesh, p11, Vector2(u1, v1), col)
			_v(_lens_mesh, p00, Vector2(u0, v0), col)
			_v(_lens_mesh, p11, Vector2(u1, v1), col)
			_v(_lens_mesh, p10, Vector2(u1, v0), col)
	_lens_mesh.surface_end()


## Rabos de fumaça preta: da borda da lente até o chão, curvados para fora, finos no pé; ficam para trás no giro.
func _build_tails(s: float) -> void:
	_tails_mesh.clear_surfaces()
	if s < 0.05:
		return
	_tails_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color(1, 1, 1, s)
	for t in TAILS:
		var a := _head_angle - float(t[0])
		var tan := Vector3(cos(a), 0.0, -sin(a))
		var out := float(t[1])
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		var prev_u := 0.0
		for k in 13:
			var u := float(k) / 12.0                      # 0 = em cima (na lente), 1 = no chão
			var aa := a + u * u * 0.6                       # o pé fica para trás no giro
			var d := Vector3(sin(aa), 0.0, cos(aa))
			var r := LENS_R * 0.9 + out * sin(u * PI) + 0.1 * sin(_t * 6.0 + u * 4.0)
			var y := lerpf(LENS_H - 0.05, 0.02, u)
			var p := global_position + d * r + Vector3.UP * y
			var half := tan * 0.32   # a forma (larga em cima, fina embaixo) é a do fiapo pintado
			if k > 0:
				_v(_tails_mesh, prev_l, Vector2(prev_u, 0.0), col)
				_v(_tails_mesh, prev_r, Vector2(prev_u, 1.0), col)
				_v(_tails_mesh, p + half, Vector2(u, 1.0), col)
				_v(_tails_mesh, prev_l, Vector2(prev_u, 0.0), col)
				_v(_tails_mesh, p + half, Vector2(u, 1.0), col)
				_v(_tails_mesh, p - half, Vector2(u, 0.0), col)
			prev_l = p - half
			prev_r = p + half
			prev_u = u
	_tails_mesh.surface_end()


# --- fitas em espiral --------------------------------------------------------------------------------------------

func _build_ring(i: int, s: float) -> void:
	var im := _ring_mesh[i]
	im.clear_surfaces()
	if s < 0.01:
		return
	var r: Dictionary = RINGS[i]
	var c := global_position
	var head := _head_angle - float(r.lag)
	var arc := float(r.arc) * (0.35 + 0.65 * s)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var prev_in := Vector3.ZERO
	var prev_out := Vector3.ZERO
	var prev_u := 0.0
	for k in SEG + 1:
		var u := float(k) / float(SEG)          # 0 = cabeça (junto da lâmina), 1 = cauda
		var a := head - u * arc                  # o giro aumenta o ângulo: a cauda fica atrás
		var dir := Vector3(sin(a), 0.0, cos(a))
		var y := float(r.h) + float(r.tilt) * sin(a + _t * 1.5) + float(r.rise) * u
		# a fita afina na cauda; a borda de fora fica mais alta (a parede do redemoinho)
		var half := float(r.w) * 0.5 * (1.0 - 0.5 * u) * (0.6 + 0.4 * s)
		var sl := float(r.slope)
		var off := dir * cos(sl) * half + Vector3.UP * sin(sl) * half
		var mid := c + dir * float(r.r) + Vector3.UP * y
		var pin := mid - off
		var pout := mid + off
		if k > 0:
			var c0 := Color(1, 1, 1, s)
			_v(im, prev_in, Vector2(prev_u, 0.0), c0)
			_v(im, prev_out, Vector2(prev_u, 1.0), c0)
			_v(im, pout, Vector2(u, 1.0), c0)
			_v(im, prev_in, Vector2(prev_u, 0.0), c0)
			_v(im, pout, Vector2(u, 1.0), c0)
			_v(im, pin, Vector2(u, 0.0), c0)
		prev_in = pin
		prev_out = pout
		prev_u = u
	im.surface_end()


# --- meia-lua do golpe final -------------------------------------------------------------------------------------

## Arco da meia-lua a partir do caminho gravado da ponta: ângulo de começo e de fim (o giro aumenta o ângulo; pelo
## menos CRESCENT_MIN_ARC, estendido para trás) e a altura média do corte.
func _crescent_arc() -> void:
	var p0 := _fin_pts[0] - _fin_center
	var p1 := _fin_pts[_fin_pts.size() - 1] - _fin_center
	_cres_a1 = atan2(p1.x, p1.z)
	var span := wrapf(_cres_a1 - atan2(p0.x, p0.z), 0.0, TAU)
	_cres_a0 = _cres_a1 - maxf(span, CRESCENT_MIN_ARC)
	var h := 0.0
	for p in _fin_pts:
		h += p.y - _fin_center.y
	_cres_h = clampf(h / float(_fin_pts.size()), 0.7, 1.3)


## Ponto da meia-lua: `u` 0 = fim do golpe (a cabeça, mais nova) .. 1 = começo; `f` 0..1 entre o raio de dentro e o de
## fora (a borda de fora um pouco mais alta).
func _crescent_point(u: float, f: float, lift := 0.0, tilt := 0.0) -> Vector3:
	var a := lerpf(_cres_a1, _cres_a0, u)
	var r := lerpf(CRESCENT_IN, CRESCENT_OUT, f)
	# o corte é diagonal (o começo mais alto, a cabeça desce perto do chão): deitada na horizontal, a meia-lua vista
	# de lado vira uma linha fina
	var diag := (u - 0.5) * CRESCENT_DIAG
	return _fin_center + Vector3(sin(a), 0.0, cos(a)) * r + Vector3.UP * (_cres_h + diag + 0.2 * f + lift + tilt * f)


func _build_crescent(delta: float) -> void:
	_crescent_mesh.clear_surfaces()
	if _crescent_t < 0.0:
		_core_mesh.clear_surfaces()
		_puff_mesh.clear_surfaces()
		return
	_crescent_t += delta
	var k := _crescent_t / CRESCENT_LIFE
	if k >= 1.0:
		_crescent_t = -1.0
		return
	# corpo: largo no meio e fino nas pontas; o fio negro: estreito, no meio do corpo
	# a borda de fora sobe (tilt): a meia-lua tem altura e não some vista de lado
	# a fumaça roxa some antes; o fio negro, grosso e de pontas afiadas, é o último a ir (como na referência)
	_band(_crescent_mesh, minf(k * 1.3, 1.0), 0.45, 1.0, 0.0, 0.9)
	_band(_core_mesh, k * 0.8, 0.3, 0.62, 0.0, 0.45, 1.6)
	# a nuvem de cima: nasce um pouco depois e sobe enquanto se desfaz
	_band(_puff_mesh, clampf(k * 1.05 - 0.05, 0.0, 1.0), 0.18, 0.92, 0.15 + 0.6 * k, 1.1)


## Fita da meia-lua entre as frações `f0` e `f1` do raio (no meio do arco; nas pontas as duas se juntam em 0,52).
## A idade de cada ponto cresce com o tempo `k`, da cauda (começo do golpe) para a cabeça: ela se desfaz em pedaços.
func _band(m: ImmediateMesh, k: float, f0: float, f1: float, lift := 0.0, tilt := 0.0, taper := 0.7) -> void:
	m.clear_surfaces()
	if k >= 1.0:
		return
	m.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color(1, 1, 1, 1.0 - smoothstep(0.75, 1.0, k))
	var pa := Vector3.ZERO
	var pb := Vector3.ZERO
	var pu := 0.0
	for i in CRESCENT_SEG + 1:
		var u := float(i) / float(CRESCENT_SEG)
		var age := clampf(u * 0.5 + k * 0.95, 0.0, 1.0)
		var w := pow(sin(PI * clampf(u * 0.92 + 0.04, 0.0, 1.0)), taper)   # taper alto = pontas afiadas
		var mid := (f0 + f1) * 0.5
		var a := _crescent_point(u, lerpf(mid, f0, w), lift, tilt)
		var b := _crescent_point(u, lerpf(mid, f1, w), lift, tilt)
		if i > 0:
			_v(m, pa, Vector2(pu, 0.0), col)
			_v(m, pb, Vector2(pu, 1.0), col)
			_v(m, b, Vector2(age, 1.0), col)
			_v(m, pa, Vector2(pu, 0.0), col)
			_v(m, b, Vector2(age, 1.0), col)
			_v(m, a, Vector2(age, 0.0), col)
		pa = a
		pb = b
		pu = age
	m.surface_end()


## Clarão pintado em `at` (tex_flash.gdshader + clarao.png): abre de 25% a `size` m bem rápido (o soco), gira
## `turn` rad enquanto vive e apaga em `time` s; `rot0` = giro inicial.
func _tex_flash(at: Vector3, col: Color, gain: float, size: float, time: float, turn: float, rot0 := 0.0) -> void:
	var root := FX._scene()
	if root == null:
		return
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = TEX_FLASH_SHADER
	mat.set_shader_parameter("flare", FLARE_TEX)
	qm.material = mat
	q.mesh = qm
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	q.extra_cull_margin = size
	q.set_instance_shader_parameter("col", Vector3(col.r, col.g, col.b))
	q.set_instance_shader_parameter("intensity", gain)
	q.set_instance_shader_parameter("spin", rot0)
	root.add_child(q)
	q.global_position = at
	q.scale = Vector3.ONE * size * 0.25
	var tw := q.create_tween().set_parallel(true)
	tw.tween_property(q, "scale", Vector3.ONE * size, time * 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_method(func(v: float) -> void: q.set_instance_shader_parameter("spin", v), rot0, rot0 + turn, time)
	tw.tween_method(func(v: float) -> void: q.set_instance_shader_parameter("intensity", v), gain, 0.0, time) \
		.set_delay(time * 0.15).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_callback(q.queue_free)


## Clarão suave em `at` (soft_flash.gdshader): abre de 40% a `size` m e apaga em `time` s. `stretch` > 1 achata num
## risco horizontal.
func _soft_flash(at: Vector3, col: Color, gain: float, size: float, time: float, stretch: float) -> void:
	var root := FX._scene()
	if root == null:
		return
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = FLASH_SHADER
	qm.material = mat
	q.mesh = qm
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	q.extra_cull_margin = size
	q.set_instance_shader_parameter("col", Vector3(col.r, col.g, col.b))
	q.set_instance_shader_parameter("stretch", stretch)
	q.set_instance_shader_parameter("intensity", gain)
	root.add_child(q)
	q.global_position = at
	q.scale = Vector3.ONE * size * 0.4
	var tw := q.create_tween().set_parallel(true)
	tw.tween_property(q, "scale", Vector3.ONE * size, time * 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_method(func(v: float) -> void: q.set_instance_shader_parameter("intensity", v), gain, 0.0, time)
	tw.chain().tween_callback(q.queue_free)


static func _v(m: ImmediateMesh, p: Vector3, uv: Vector2, c: Color) -> void:
	m.surface_set_uv(uv)
	m.surface_set_color(c)
	m.surface_add_vertex(p)


static func _rand_flat() -> Vector3:
	var a := randf() * TAU
	return Vector3(sin(a), 0.0, cos(a))


## Lasca escura que voa do alvo no golpe final: sobe girando, cai e some encolhendo.
class Shard extends MeshInstance3D:
	static var _mesh: BoxMesh
	var vel := Vector3.ZERO
	var spin := Vector3.ZERO
	var life := 0.0
	var max_life := randf_range(0.7, 1.1)
	var size := randf_range(0.06, 0.14)

	func _ready() -> void:
		if _mesh == null:
			_mesh = BoxMesh.new()
			_mesh.size = Vector3(1.0, 0.35, 0.7)
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.1, 0.12, 0.22)
			m.emission_enabled = true
			m.emission = Color(0.18, 0.12, 0.45)
			m.emission_energy_multiplier = 0.6
			m.roughness = 0.4
			_mesh.material = m
		mesh = _mesh
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		scale = Vector3.ONE * size

	func _process(delta: float) -> void:
		life += delta
		if life >= max_life:
			queue_free()
			return
		vel += Vector3.DOWN * 9.0 * delta
		vel *= exp(-0.8 * delta)
		global_position += vel * delta
		rotation += spin * delta
		scale = Vector3.ONE * size * (1.0 - smoothstep(0.7, 1.0, life / max_life))
