extends SceneTree
## Folha de contato da passada do cavaleiro: N cópias vistas de lado, cada uma numa fase do ciclo, com a
## luz do jogo. Também mede o ciclo inteiro (pé de apoio deslizando, pé afundando no chão, joelho máximo).
## Precisa de janela (não use --headless) e do --import feito antes:
##   godot --path . --resolution 2000x520 --script res://tools/gait_shot.gd -- <saida.png> [vel] [corre 0..1]
## vel em m/s (padrão 5,2 = WALK_SPEED); corre = KnightAnim run (0 andar normal, 1 correndo).

const N := 8

var _frames := 0
var _out := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0]
	var speed := float(args[1]) if args.size() > 1 else 5.2
	var run := float(args[2]) if args.size() > 2 else 0.0
	var move := clampf(speed / 5.2, 0.0, 1.0)
	WorldLighting.build(root)
	var scene := load("res://assets/models/knight.glb") as PackedScene

	_probe = scene.instantiate() as Node3D
	root.add_child(_probe)
	_args = [speed, move, run]
	for i in N:
		var m := scene.instantiate() as Node3D
		root.add_child(m)
		m.position.z = i * 1.25
		var ri := KnightAnim.rig(m)
		var p := KnightAnim.locomotion_pose(ri, TAU * i / N, move, run)
		KnightAnim.apply(ri, p, 1.0)
		KnightAnim.apply(ri, p, 1.0)   # segunda vez: a altura do modelo usa as rotações já aplicadas
	# chão
	var g := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2, 0.02, N * 1.25 + 1.0)
	g.mesh = bm
	g.position = Vector3(0, -0.01, (N - 1) * 1.25 / 2.0)
	root.add_child(g)


var _probe: Node3D
var _args: Array


## Anda o ciclo em passos pequenos com o corpo avançando `speed` e acompanha o pé no chão.
func _measure(r: Dictionary, speed: float, move: float, run: float) -> void:
	var w := KnightAnim.cadence(r, speed, move, run)
	print("cadência %.1f rad/s = %.2f passos/s" % [w, w / PI])
	var duty := KnightAnim.gait_duty(move, run)
	var steps := 400
	var dt := TAU / w / steps
	var min_y := 9.0
	var max_knee := 0.0
	var stance_z: Array = []
	var stance_y: Array = []
	var model: Node3D = r.model
	for i in steps:
		var ph := TAU * i / steps
		var p := KnightAnim.locomotion_pose(r, ph, move, run)
		KnightAnim.apply(r, p, 1.0)
		KnightAnim.apply(r, p, 1.0)
		var body_z := speed * dt * i - model.global_position.z
		max_knee = maxf(max_knee, r.KneeL.rotation.x)
		var low := _lowest(r.AnkleL)
		min_y = minf(min_y, minf(low.y, _lowest(r.AnkleR).y))
		var u := float(i) / steps
		if u > 0.15 * duty and u < 0.55 * duty:   # do pé chato até antes do calcanhar subir
			stance_z.append(r.AnkleL.global_position.z + body_z)
			stance_y.append(low.y)
	var slip: float = stance_z.max() - stance_z.min()
	print("duty %.2f | joelho máx %.0f° | pé mais baixo %.3f m | apoio: tornozelo desliza %.3f m, altura %.3f..%.3f m" % [
		duty, rad_to_deg(max_knee), min_y, slip, stance_y.min(), stance_y.max()])


## Ponto mais baixo das malhas do pé (coordenadas do mundo).
func _lowest(ankle: Node3D) -> Vector3:
	var best := Vector3(0, 99, 0)
	for mi: MeshInstance3D in ankle.find_children("*", "MeshInstance3D", true, false):
		var mdt := mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
		for v in mdt:
			var g := mi.global_transform * v
			if g.y < best.y:
				best = g
	return best


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_probe.position.x = 50.0
		_measure(KnightAnim.rig(_probe), _args[0], _args[1], _args[2])
		_probe.queue_free()
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 2.3
		cam.position = Vector3(6.0, 1.0, (N - 1) * 1.25 / 2.0)
		cam.rotation_degrees.y = 90.0
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		root.add_child(cam)
		cam.current = true
	if _frames < 12:
		return false
	root.get_texture().get_image().save_png(_out)
	print("SHOT ", _out)
	return true
