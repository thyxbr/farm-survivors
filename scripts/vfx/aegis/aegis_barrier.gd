class_name AegisBarrier
extends Node3D
## Égide Cristalina: o efeito visual inteiro (prefab scenes/vfx/aegis/aegis_barrier.tscn). Só visual: quem
## decide integridade, absorção e quebra é AegisRules (via ShieldAbilities); aqui só chegam a fração de
## integridade (set_integrity), os golpes (impact) e os fins (shatter/dissolve).
##
## Sequência: o círculo do chão se desenha (circle_form_time) e os anéis começam a girar; as placas em losango
## brotam de baixo para cima (barrier_form_time) formando uma coroa de losangos em volta do personagem (e de
## quem estiver junto: o raio cabe um grupo). Golpes racham as
## placas (mais perto do golpe e mais quanto menor a integridade); fraco, o escudo solta lascas e perde
## placas. Zerado: tudo racha, pulsa (break_delay) e estoura em fragmentos e faíscas; o círculo apaga.
## Soltar a tecla dissolve o escudo sem estouro. Nos dois fins o nó se libera sozinho.

signal finished

const PLATE := preload("res://scenes/vfx/aegis/aegis_plate.tscn")
const SHARDS := preload("res://scenes/vfx/aegis/aegis_shards.tscn")
const DISSIPATE := preload("res://scenes/vfx/aegis/aegis_dissipate.tscn")
const DEFAULT_CONFIG := preload("res://assets/vfx/aegis/aegis_config.tres")

const LIGHT_ENERGY := 1.4
const PLATE_GROW := 0.38          ## fração de barrier_form_time que cada placa leva para se formar
const SHEET_SPAN := 0.95          ## fração da largura do quadro que a coroa ocupa na sheet (quebra)

enum State { FORMING, ACTIVE, BREAKING, SHATTERED, DISSOLVING }

@export var config: AegisConfig

@onready var ground: AegisGroundCircle = $GroundCircle
@onready var rings: AegisRings = $Rings
@onready var plates_root: Node3D = $Plates
@onready var sheet: AegisFlipbook = $Sheet
@onready var light: OmniLight3D = $Light

var state := State.FORMING
var plates: Array[AegisPlate] = []
var integrity := 1.0              ## última fração recebida (0..1)
var _t := 0.0
var _state_t := 0.0
var _end_time := 0.0              ## quando o nó se libera (contado em _state_t do fim)
var _hit_point := Vector3.ZERO    ## último golpe (global)
var _flash_light := 0.0


func _ready() -> void:
	if config == null:
		config = DEFAULT_CONFIG
	ground.radius = config.circle_radius
	ground.form_time = config.circle_form_time
	ground.motes_per_second = config.ground_motes
	rings.radius = config.circle_radius
	rings.speed = config.ring_speed
	rings.fade_in_time = config.circle_form_time
	ground.setup()
	rings.setup()
	_build_plates()
	# a sheet desenha a coroa inteira num quadro: o billboard só entra na quebra (as peças 3D já usam a arte dela)
	var w := config.shield_width * 2.0 / SHEET_SPAN
	sheet.scale = Vector3(w, w, 1.0)
	sheet.position = Vector3(0.0, config.shield_height * 0.5, 0.0)
	sheet.intensity = 0.0
	light.light_energy = 0.0


# ------------------------------------------------------------------ montagem
## Coroa de losangos (como na sprite sheet): `rows` fileiras em volta do personagem, na parede de um cilindro
## de raio `width`; cada fileira desencontrada meio losango da anterior, para as pontas se encaixarem nos vãos.
## Losangos da mesma fileira se tocam pelas pontas dos lados; a altura sai de `height` (a coroa toda).
## Devolve [{pos, normal, h01, size}] no espaço local, de baixo para cima (ordem de formação). A quantidade é
## arredondada para fileiras completas (count / rows por fileira).
static func layout(count: int, width: float, height: float, rows := 2) -> Array:
	rows = maxi(rows, 1)
	var per := maxi(3, int(round(float(count) / rows)))
	var size := plate_size(count, width, height, rows)
	var out: Array = []
	for r in rows:
		var y := size.y * 0.5 + r * size.y * 0.5
		var rad := width * (1.0 - 0.035 * r)   # a coroa fecha um pouco para cima
		for i in per:
			var a := (float(i) + 0.5 * float(r % 2)) * TAU / per
			var n := Vector3(sin(a), 0.0, cos(a))
			out.append({"pos": n * rad + Vector3.UP * y, "normal": n, "size": size,
				"h01": clampf((y - size.y * 0.5) / maxf(height - size.y, 0.01), 0.0, 1.0)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.pos.y < b.pos.y)
	return out


## Largura e altura de cada losango (m) para a coroa de `rows` fileiras e `count` placas.
static func plate_size(count: int, width: float, height: float, rows := 2) -> Vector2:
	rows = maxi(rows, 1)
	var per := maxi(3, int(round(float(count) / rows)))
	var w := TAU * width / per
	var h := height / (1.0 + 0.5 * float(rows - 1))
	return Vector2(w * 1.15, h)   # as pontas dos lados se sobrepõem um pouco, como na sprite


func _build_plates() -> void:
	for c in plates_root.get_children():
		c.queue_free()
	plates.clear()
	var pts := layout(config.plate_count, config.shield_width, config.shield_height, config.plate_rows)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(get_instance_id())
	for p in pts:
		var plate: AegisPlate = PLATE.instantiate()
		var n: Vector3 = p.normal
		var b := Basis(Vector3.UP.cross(n).normalized(), Vector3.UP, n)
		var sz: Vector2 = p.size
		plate.transform = Transform3D(b * Basis.from_scale(Vector3(sz.x, sz.y, 1.0)), p.pos)
		plate.bias = rng.randf()
		plate.h01 = p.h01
		plates_root.add_child(plate)
		plate.crack.set_intensity(config.crack_intensity)
		var m := plate.crystal.material_override as ShaderMaterial
		if m:
			m.set_shader_parameter("glow", config.plate_glow)
			m.set_shader_parameter("fill_alpha", config.plate_fill)
		plates.append(plate)


# ------------------------------------------------------------------ estado
## Fração de integridade (0..1) vinda das regras. `hit_point` = onde foi o golpe (global; ZERO = sem ponto).
func set_integrity(frac: float, hit_point := Vector3.ZERO) -> void:
	if state >= State.BREAKING:
		return
	integrity = clampf(frac, 0.0, 1.0)
	if hit_point != Vector3.ZERO:
		_hit_point = hit_point
	var reach := config.shield_width * 1.7
	var to_local := global_transform.affine_inverse()
	var hit_l := to_local * _hit_point if _hit_point != Vector3.ZERO else Vector3(0, config.shield_height * 0.5, config.shield_width)
	for plate in plates:
		var near := 1.0 - clampf(plate.position.distance_to(hit_l) / reach, 0.0, 1.0)
		var c := AegisRules.plate_crack(integrity, plate.bias, near, config.crack_spread)
		plate.set_damage(c, _impact_uv(plate, hit_l))
	_shed_plates()


## Golpe recebido (sem mudar a integridade): clarão nas placas perto do ponto, lascas nas rachadas.
func impact(hit_point: Vector3) -> void:
	if state >= State.BREAKING:
		return
	_hit_point = hit_point
	var hit_l := global_transform.affine_inverse() * hit_point
	var reach := config.shield_width * 1.4
	var chips := 0
	for plate in plates:
		if plate.shed:
			continue
		var near := 1.0 - clampf(plate.position.distance_to(hit_l) / reach, 0.0, 1.0)
		plate.set_flash(near * 1.2)
		if near > 0.3 and plate.damage() > 0.45 and chips < 3:
			chips += 1
			_chip(plate, 2 + int(plate.damage() * 3.0))
	ground.boost = 0.8
	rings.boost = 0.8
	_flash_light = 1.0


## Integridade zerada: tudo racha, pulsa e estoura em fragmentos.
func shatter() -> void:
	if state >= State.BREAKING:
		return
	_finish_forming()
	state = State.BREAKING
	_state_t = 0.0
	for plate in plates:
		plate.set_damage(1.0, _impact_uv(plate, global_transform.affine_inverse() * _hit_point))


## Fim sem quebra (soltou a tecla, esquivou, morreu...): as placas se desfazem de cima para baixo.
func dissolve() -> void:
	if state >= State.BREAKING:
		return
	state = State.DISSOLVING
	_state_t = 0.0
	var time := config.dissipate_time * 0.5
	ground.fade_out(time)
	rings.fade_out(time * 0.8)
	sheet.fade_out(time * 0.6)
	_spawn_dissipate(0.35, time)
	_end_time = time + 0.1


## Fim genérico (Player.end_ability chama em "soft_nodes"): quebrado continua a quebra; senão dissolve.
func finish() -> void:
	if state < State.BREAKING:
		dissolve()


func is_broken() -> bool:
	return state == State.BREAKING or state == State.SHATTERED


## 0..1: quanto da barreira já se formou (média das placas).
func formed() -> float:
	if plates.is_empty():
		return 0.0
	var s := 0.0
	for p in plates:
		s += p.appear()
	return s / plates.size()


# ------------------------------------------------------------------ quadro a quadro
func _process(delta: float) -> void:
	_t += delta
	_state_t += delta
	_flash_light = move_toward(_flash_light, 0.0, delta * 3.0)
	match state:
		State.FORMING, State.ACTIVE:
			_form_tick()
			light.light_energy = LIGHT_ENERGY * formed() * (1.0 + _flash_light)
		State.BREAKING:
			var k := clampf(_state_t / maxf(config.break_delay, 0.001), 0.0, 1.0)
			# pulsação: o brilho sobe e o escudo incha um pouco antes de estourar
			var pulse := sin(k * PI * 2.5) * 0.5 + 0.5
			for plate in plates:
				if plate.visible:
					plate.set_flash(0.15 + k * 0.6 + pulse * 0.25)
			plates_root.scale = Vector3.ONE * (1.0 + 0.07 * k * k)
			light.light_energy = LIGHT_ENERGY * (1.5 + 2.5 * k)
			ground.boost = 1.0 + k
			if k >= 1.0:
				_explode()
		State.SHATTERED:
			var k := clampf(_state_t / maxf(config.dissipate_time, 0.001), 0.0, 1.0)
			light.light_energy = LIGHT_ENERGY * 3.0 * (1.0 - k) * (1.0 - k)
			if _state_t >= _end_time:
				_done()
		State.DISSOLVING:
			var k := clampf(_state_t / maxf(_end_time - 0.1, 0.01), 0.0, 1.0)
			for plate in plates:
				# de cima para baixo
				var local_k := clampf(k * 1.6 - (1.0 - plate.h01) * 0.6, 0.0, 1.0)
				plate.set_fade(minf(plate.visible_amount(), 1.0 - local_k) if plate.visible else 0.0)
			light.light_energy = LIGHT_ENERGY * (1.0 - k)
			if _state_t >= _end_time:
				_done()


func _form_tick() -> void:
	var start := config.circle_form_time * 0.6
	var grow := maxf(config.barrier_form_time * PLATE_GROW, 0.01)
	var spread := maxf(config.barrier_form_time - grow, 0.0)
	var all := true
	for plate in plates:
		if plate.shed:
			continue
		var a := clampf((_t - start - plate.h01 * spread) / grow, 0.0, 1.0)
		if a > plate.appear():
			plate.set_appear(a)
		if a < 1.0:
			all = false
	if all and state == State.FORMING:
		state = State.ACTIVE


func _finish_forming() -> void:
	for plate in plates:
		if not plate.shed:
			plate.set_appear(1.0)


## Integridade baixa: as placas mais rachadas se soltam (até 30% delas com o escudo quase zerado).
func _shed_plates() -> void:
	if integrity >= config.shed_below or config.shed_below <= 0.0:
		return
	var want := int(floor((config.shed_below - integrity) / config.shed_below * plates.size() * 0.3))
	var gone := 0
	for p in plates:
		if p.shed:
			gone += 1
	if gone >= want:
		return
	var order := plates.duplicate()
	order.sort_custom(func(a: AegisPlate, b: AegisPlate) -> bool: return a.damage() > b.damage())
	for p in order:
		if gone >= want:
			break
		if not p.shed and p.appear() >= 1.0:
			p.shed_off()
			_chip(p, 4)
			gone += 1


func _explode() -> void:
	state = State.SHATTERED
	_state_t = 0.0
	var pts := PackedVector3Array()
	var nrm := PackedVector3Array()
	for plate in plates:
		if plate.visible and not plate.shed:
			pts.append(plate.global_position)
			nrm.append(plate.global_basis.z.normalized())
		plate.visible = false
	var life := config.dissipate_time
	if not pts.is_empty():
		var sh: AegisShards = SHARDS.instantiate()
		_fx_root().add_child(sh)
		sh.global_position = Vector3.ZERO
		sh.burst(pts, nrm, config.shard_intensity, life)
	_spawn_dissipate(config.shard_intensity, life)
	sheet.intensity = config.sheet_intensity
	sheet.play(AegisFlipbook.BREAK, life)
	sheet.fade_out(life)
	ground.fade_out(life)
	rings.fade_out(life * 0.6)
	_end_time = life + 0.1


func _spawn_dissipate(intensity: float, time: float) -> void:
	var dp: AegisDissipate = DISSIPATE.instantiate()
	_fx_root().add_child(dp)
	dp.global_position = global_position
	dp.burst(config.shield_width, config.shield_height, intensity, time)


func _chip(plate: AegisPlate, count: int) -> void:
	var sh: AegisShards = SHARDS.instantiate()
	_fx_root().add_child(sh)
	sh.global_position = Vector3.ZERO
	sh.chip(plate.global_position, plate.global_basis.z.normalized(), count)


## Onde a rachadura nasce no losango: o lado da placa virado para o golpe.
func _impact_uv(plate: AegisPlate, hit_l: Vector3) -> Vector2:
	var d := plate.transform.affine_inverse() * hit_l
	var v := Vector2(d.x, -d.y)
	if v.length() < 0.001:
		return Vector2(0.5, 0.4)
	v = v.normalized() * 0.28
	return Vector2(0.5, 0.5) + v


## Fragmentos e faíscas ficam no mundo (não andam com o jogador) e sobrevivem a este nó.
func _fx_root() -> Node:
	var scene := get_tree().current_scene if is_inside_tree() else null
	return scene if scene else get_parent()


func _done() -> void:
	if is_queued_for_deletion():
		return
	finished.emit()
	queue_free()
