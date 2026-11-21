class_name AegisPlate
extends Node3D
## Égide Cristalina: uma placa de proteção em losango (prefab scenes/vfx/aegis/aegis_plate.tscn), com a arte
## do losango da sprite sheet (aegis_plate.png; rachada: aegis_plate_cracked.png).
## Objeto próprio (malha + material com parâmetros por instância), para cada placa poder rachar, piscar e
## cair sozinha. O losango fica no plano XY com a frente em +Z (a barreira vira +Z para fora) e a ponta
## comprida em +Y. A rachadura é a filha Crack (prefab aegis_crack).

const WIDTH := 1.0      ## largura do losango (m, antes da escala do nó: a barreira escala x = largura, y = altura)
const HEIGHT := 1.0     ## altura do losango
const BULGE := 0.06     ## o centro sai para a frente: facetas de cristal

## 0..1: sorteio da placa (umas racham antes, outras depois). A barreira sorteia ao montar.
var bias := 0.5
## Altura normalizada na barreira (0 = embaixo, 1 = topo): ordem de formação.
var h01 := 0.0
var shed := false       ## já caiu sozinha (escudo fraco)

@onready var crystal: MeshInstance3D = $Crystal
@onready var crack: AegisCrack = $Crack

var _appear := 0.0
var _fade := 1.0
var _flash := 0.0
var _damage := 0.0
var _shed_t := -1.0
var _impact := Vector2(0.5, 0.35)
var _base_scale := Vector3.ONE

static var _mesh: ArrayMesh


## Malha do losango (compartilhada por todas as placas e rachaduras): 4 facetas com o centro saliente.
## UV: centro em (0,5; 0,5); pontas em (0,5; 0) em cima, (1; 0,5) à direita, (0,5; 1) embaixo, (0; 0,5).
static func diamond_mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	var c := Vector3(0, 0, BULGE)
	var top := Vector3(0, HEIGHT * 0.5, 0)
	var right := Vector3(WIDTH * 0.5, 0, 0)   # visto de frente (de +Z), a direita da tela é +X do nó
	var bottom := Vector3(0, -HEIGHT * 0.5, 0)
	var left := Vector3(-WIDTH * 0.5, 0, 0)
	var uv_c := Vector2(0.5, 0.5)
	var corners := [[top, Vector2(0.5, 0.0)], [left, Vector2(0.0, 0.5)], [bottom, Vector2(0.5, 1.0)], [right, Vector2(1.0, 0.5)]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var a: Array = corners[i]
		var b: Array = corners[(i + 1) % 4]
		var n: Vector3 = (b[0] - c).cross(a[0] - c).normalized()
		if n.z < 0.0:
			n = -n
		for v in [[c, uv_c], a, b]:
			st.set_normal(n)
			st.set_uv(v[1])
			st.add_vertex(v[0])
	_mesh = st.commit()
	return _mesh


func _ready() -> void:
	crystal.mesh = diamond_mesh()
	crack.mesh = diamond_mesh()
	_base_scale = scale
	_apply()


## 0..1: formação (cresce de baixo para cima dentro do losango, com um fio de luz na frente).
func set_appear(a: float) -> void:
	_appear = clampf(a, 0.0, 1.0)
	_apply()


func appear() -> float:
	return _appear


func set_fade(f: float) -> void:
	_fade = clampf(f, 0.0, 1.0)
	_apply()


func set_flash(f: float) -> void:
	_flash = maxf(f, 0.0)
	_apply()


## Racha até `c` (0..1). `impact_uv` = onde nasce a rachadura no losango.
func set_damage(c: float, impact_uv := Vector2(0.5, 0.35)) -> void:
	if c <= _damage:
		return
	if _damage <= 0.0:
		_impact = impact_uv   # a arte rachada nasce do primeiro golpe
	_damage = clampf(c, 0.0, 1.0)
	crack.set_crack(_damage, impact_uv, bias * 13.7)
	_apply()


func damage() -> float:
	return _damage


## Escudo fraco: a placa se solta e some sozinha em `time` (a barreira solta os fragmentos).
func shed_off(time := 0.45) -> void:
	if shed:
		return
	shed = true
	_shed_t = 0.0
	set_meta("shed_time", time)


## A placa ainda aparece?
func visible_amount() -> float:
	return _fade * _appear if visible else 0.0


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = move_toward(_flash, 0.0, delta * 4.0)
		_apply()
	if _shed_t >= 0.0:
		_shed_t += delta
		var k := clampf(_shed_t / float(get_meta("shed_time", 0.45)), 0.0, 1.0)
		# cai um pouco, gira e apaga
		position += -transform.basis.z * delta * 0.25 + Vector3.DOWN * delta * 1.2 * k
		rotate_object_local(Vector3.FORWARD, delta * 2.0)
		set_fade(1.0 - k)
		if k >= 1.0:
			_shed_t = -1.0
			visible = false


func _apply() -> void:
	if crystal == null:
		return
	crystal.set_instance_shader_parameter("appear", _appear)
	crystal.set_instance_shader_parameter("fade", _fade)
	crystal.set_instance_shader_parameter("flash", _flash)
	crystal.set_instance_shader_parameter("damage", _damage)
	crystal.set_instance_shader_parameter("impact", _impact)
	crystal.set_instance_shader_parameter("seed", bias)
	crack.set_fade(_fade * smoothstep(0.6, 1.0, _appear))
	# brota: começa pequena e chega à escala cheia junto com a formação
	scale = _base_scale * lerpf(0.55, 1.0, 1.0 - pow(1.0 - _appear, 3.0))
