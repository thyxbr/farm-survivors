extends SceneTree
## Custo do ToonLook numa multidão: N goblins parados com a luz do jogo, com e sem o estilo.
## Imprime draw calls, objetos e tempo médio de quadro. Precisa de janela (sem --headless):
##   godot --path . --resolution 1280x720 --script res://tools/toon_cost.gd -- 80 [toon] [merge] [move]
## `merge` junta as cascas por grupo de peças (como os inimigos do jogo); `move` desloca todos os goblins a
## cada quadro, para pesar também a atualização das transformações (parados, só pesa o desenho).

var _frames := 0
var _t0 := 0
var _toon := false
var _n := 80
var _merge := false
var _move := false
var _goblins: Array[Node3D] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_n = int(args[0]) if args.size() > 0 else 80
	_toon = "toon" in args
	_merge = "merge" in args
	_move = "move" in args
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	WorldLighting.build(root)
	var scene := load("res://assets/models/goblin.glb") as PackedScene
	var side := int(ceil(sqrt(_n)))
	for i in _n:
		var g := scene.instantiate() as Node3D
		EnemyGear.apply(g, ["Club"])
		root.add_child(g)
		g.position = Vector3((i % side - side / 2.0) * 1.4, 0, -(i / side) * 1.4)
		if _toon:
			ToonLook.apply(g, true, _merge)
		_goblins.append(g)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 7, 9), Vector3(0, 0.8, -side * 0.7))
	cam.current = true


func _process(_delta: float) -> bool:
	_frames += 1
	if _move:
		for g in _goblins:
			g.position.x += 0.002 * (1.0 if _frames % 120 < 60 else -1.0)
			g.rotation.y += 0.01
	if _frames == 60:
		_t0 = Time.get_ticks_usec()
	if _frames < 360:
		return false
	var ms := (Time.get_ticks_usec() - _t0) / 300.0 / 1000.0
	print("COST toon=%s merge=%s move=%s n=%d draw_calls=%d objects=%d prims=%d frame_ms=%.2f" % [_toon, _merge, _move, _n,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), ms])
	return true
