class_name GroundCrater
extends Node3D
## Martelo de Energia: uma cratera (prefab scenes/vfx/hammer/ground_crater.tscn). O HammerSkill espalha várias em
## volta do impacto, uma logo depois da outra, na onda que corre pelo chão.
##   Decal    bacia escura, borda de terra levantada, rachaduras acesas e energia residual azul pulsando no fundo
##            (hammer_ground.gdshader, kind 0)
##   Sheet    um dos quadros de chão rachado da sprite sheet (51-54) deitado por cima, com os detalhes escuros
##            (hammer_sheet_mix.gdshader); o quadro foi desenhado em perspectiva, então o quad é esticado na
##            profundidade para a rachadura ficar redonda vista de cima
##   Pebbles  pedrinhas na borda (criadas aqui), que saltam para fora e assentam
##   Debris   pedras e poeira saltando no instante em que a cratera abre
##   Motes    energia residual subindo devagar
## Abre num estalo (APPEAR s), a energia vai apagando e no fim tudo some aos poucos; o nó se libera sozinho.

const APPEAR := 0.12
const SHEET_STRETCH := 1.75   ## o quadro da sheet foi visto de lado: estica a profundidade

@onready var decal: MeshInstance3D = $Decal
@onready var sheet: HammerSheet = $Sheet
@onready var pebbles: Node3D = $Pebbles
@onready var debris: CPUParticles3D = $Debris
@onready var motes: CPUParticles3D = $Motes

var size := 0.85
var life := 3.2
var seed_value := 0
var _t := 0.0
var _stones: Array[Dictionary] = []


func setup(cfg: HammerConfig, crater_size: float, seed_v: int) -> void:
	size = crater_size
	life = cfg.crater_life
	seed_value = seed_v


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	decal.scale = Vector3(size, 1.0, size)
	decal.set_instance_shader_parameter("seed", rng.randf() * 50.0)
	decal.set_instance_shader_parameter("appear", 0.0)
	decal.rotation.y = rng.randf() * TAU
	var f := rng.randi_range(HammerSheet.CRACKS.x, HammerSheet.CRACKS.y)
	sheet.play(Vector2i(f, f), 1.0)
	sheet.rotation = Vector3(-PI * 0.5, rng.randf() * TAU, 0.0)
	sheet.scale = Vector3(size * 2.0, size * 2.0 * SHEET_STRETCH, 1.0)
	sheet.set_param("reveal", 0.0)
	sheet.set_param("recolor", 0.35)
	# pedrinhas na borda
	var stone_mat: Material = load("res://assets/vfx/hammer/hammer_stone_mat.tres")
	var n := rng.randi_range(5, 8)
	for i in n:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(rng.randf_range(0.07, 0.16), rng.randf_range(0.05, 0.11), rng.randf_range(0.07, 0.15)) * clampf(size, 0.5, 1.6)
		b.material = stone_mat
		m.mesh = b
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / n
		var rest := Vector3(cos(a), 0.03, sin(a)) * size * rng.randf_range(0.6, 0.95)
		m.rotation = Vector3(rng.randf_range(-0.6, 0.6), rng.randf() * TAU, rng.randf_range(-0.6, 0.6))
		m.position = rest * 0.4
		m.scale = Vector3.ONE * 0.01
		pebbles.add_child(m)
		_stones.append({"node": m, "rest": rest, "hop": rng.randf_range(0.25, 0.5)})
	debris.amount = 10
	debris.emission_sphere_radius = size * 0.4
	debris.restart()
	debris.emitting = true
	(motes.mesh as QuadMesh).material = FXEpic._particle_mat(FXEpic._glow_tex(), true, true)
	motes.emission_box_extents = Vector3(size * 0.45, 0.05, size * 0.45)
	motes.emitting = true
	_apply(0.0)


func _process(delta: float) -> void:
	_t += delta
	_apply(_t)
	if _t >= life and not debris.emitting:
		queue_free()


func _apply(t: float) -> void:
	var a := clampf(t / APPEAR, 0.0, 1.0)
	var energy := clampf(1.0 - t / (life * 0.65), 0.12, 1.0)
	var fade := clampf((life - t) / (life * 0.35), 0.0, 1.0)
	decal.set_instance_shader_parameter("appear", a)
	decal.set_instance_shader_parameter("energy", energy * fade)
	decal.set_instance_shader_parameter("fade", fade)
	sheet.set_param("reveal", a)
	sheet.intensity = fade * (0.45 + 0.55 * energy)
	if t > life * 0.55 and motes.emitting:
		motes.emitting = false
	# pedrinhas: saltam do miolo para a borda e assentam; no fim afundam encolhendo
	var hop := clampf(t / 0.35, 0.0, 1.0)
	for s in _stones:
		var m: MeshInstance3D = s.node
		var p: Vector3 = (s.rest as Vector3) * lerpf(0.4, 1.0, hop)
		p.y += sin(hop * PI) * float(s.hop)
		m.position = p
		m.scale = Vector3.ONE * maxf(0.01, minf(hop * 3.0, 1.0) * fade)
