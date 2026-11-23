class_name VoidZone
extends Node3D
## Zona de Vazio (Arauto do Abismo): poça de escuridão no chão que nasce com AbyssRules.VOID_R0 m, cresce até
## VOID_R1 m em VOID_GROW s e fica até VOID_LIFE s, tirando espaço da sala; quem fica dentro leva dano a cada
## TICK s e anda devagar. Servidor e cliente criam a zona no mesmo ponto; só quem manda no chefe (`deal`: servidor
## ou solo) dá o dano. Desenho: o Buraco Negro (BlackHoleFX): disco de acreção em espiral com o miolo preto,
## brasas subindo e um aro carmim aceso no raio do dano (o limite lê de longe).

const TICK := 0.6

## Dano por tique, já com o multiplicador do chefe; o nível ajusta contra cada jogador.
var dmg := 5.0
var level := 0
var deal := false
var _t := 0.0
var _tick := 0.0
var _hole: BlackHoleFX


func _ready() -> void:
	add_to_group("void_zones")
	if DisplayServer.get_name() == "headless":
		return
	_hole = BlackHoleFX.new()
	_hole.radius = radius()
	_hole.intensity = 0.0
	add_child(_hole)


func radius() -> float:
	return AbyssRules.void_radius(_t)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= AbyssRules.VOID_LIFE:
		queue_free()
		return
	if _hole:
		_hole.radius = radius()
		_hole.intensity = clampf(_t / 0.5, 0.0, 1.0) * clampf((AbyssRules.VOID_LIFE - _t) / 1.2, 0.0, 1.0)
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
