class_name VoidZone
extends Node3D
## Zona de Vazio (Arauto do Abismo): poça de escuridão no chão que nasce com AbyssRules.VOID_R0 m, cresce até
## VOID_R1 m em VOID_GROW s e fica até VOID_LIFE s, tirando espaço da sala; quem fica dentro leva dano a cada
## TICK s e anda devagar. Servidor e cliente criam a zona no mesmo ponto; só quem manda no chefe (`deal`: servidor
## ou solo) dá o dano. Desenho: disco preto com a borda carmim acesa (o limite lê de longe) e tufos de sombra.

const TICK := 0.6
const PUFF_EVERY := 0.4

## Dano por tique, já com o multiplicador do chefe; o nível ajusta contra cada jogador.
var dmg := 5.0
var level := 0
var deal := false
var _t := 0.0
var _tick := 0.0
var _puff_t := 0.0
var _disc: MeshInstance3D
var _mat: StandardMaterial3D
var _rim_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("void_zones")
	if DisplayServer.get_name() == "headless":
		return
	_disc = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 0.03
	cyl.radial_segments = 32
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(0.02, 0.0, 0.05, 0.0)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cyl.material = _mat
	_disc.mesh = cyl
	_disc.position.y = 0.06
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_disc)
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.92
	tor.outer_radius = 1.0
	tor.rings = 44
	tor.ring_segments = 4
	_rim_mat = StandardMaterial3D.new()
	_rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rim_mat.albedo_color = Color(1.0, 0.16, 0.4, 0.0)
	_rim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tor.material = _rim_mat
	ring.mesh = tor
	ring.scale = Vector3(1.0, 0.06, 1.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_disc.add_child(ring)
	_resize()


func radius() -> float:
	return AbyssRules.void_radius(_t)


func _resize() -> void:
	if _disc:
		var r := radius()
		_disc.scale = Vector3(r, 1.0, r)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= AbyssRules.VOID_LIFE:
		queue_free()
		return
	if _mat:
		_resize()
		var fade := clampf(_t / 0.4, 0.0, 1.0) * clampf((AbyssRules.VOID_LIFE - _t) / 1.2, 0.0, 1.0)
		_mat.albedo_color.a = 0.82 * fade
		_rim_mat.albedo_color.a = (0.75 + sin(_t * 4.0) * 0.2) * fade
		_puff_t -= delta
		if _puff_t <= 0.0 and fade > 0.3:
			_puff_t = PUFF_EVERY
			var r := radius()
			var a := randf() * TAU
			var d := sqrt(randf()) * r * 0.85
			FXToon.puff(global_position + Vector3(cos(a) * d, 0.3, sin(a) * d), randf_range(0.8, 1.3) * (0.6 + r * 0.15),
				AbyssFX.SHADE, {"vel": Vector3(0, 0.7, 0), "grow": 0.3, "hold": 0.4, "fade": 0.8})
	if not deal:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	var r := radius()
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead:
			continue
		var d := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length()
		if d <= r and absf(p.global_position.y - global_position.y) < 2.5:
			p.take_damage(Enemy.vs(level, p, dmg), global_position)
			if p.has_method("apply_chill"):
				p.apply_chill(1.0, true)
