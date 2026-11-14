extends Node3D
## Esquiva quadro a quadro, vista de lado: o cavaleiro correndo, esquiva (KnightAnim.dodge_pose) e volta
## a correr, com o modelo avançando na velocidade real (DODGE_SPEED). Cada cópia é um instante, espaçadas
## pela distância percorrida; uma risca no chão marca onde o pé de apoio estava no quadro anterior.
## Precisa de janela (sem --headless):
##   godot --path . --resolution 1900x500 res://tools/dodge_strip.tscn -- <saida.png>

const KNIGHT := preload("res://assets/models/knight.glb")
const DT := 1.0 / 60.0
const SHOW_EVERY := 3          ## um boneco a cada 3 quadros (20 por segundo)
const RUN_BEFORE := 0.07
const AFTER := 0.17
const LOOK := {"weapon": "iron_sword", "armor": "royal_plate", "head": "knight_helm", "hands": "iron_gauntlets",
	"feet": "iron_greaves"}
const PIVOTS := ["Pelvis", "Body", "Head", "LegL", "LegR", "KneeL", "KneeR", "AnkleL", "AnkleR", "ArmL", "ArmR",
	"ElbowL", "ElbowR"]

var _frames := 0
var _out := ""


func _ready() -> void:
	_out = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://dodge.png"
	WorldLighting.build(self)
	var dodge_t := 0.36
	var total := RUN_BEFORE + dodge_t + AFTER
	var steps := int(total / DT)
	var sim := KNIGHT.instantiate() as Node3D
	add_child(sim)
	var lk := KnightLook.apply(sim, LOOK)
	var holder: Node3D = lk.get("holder")
	var r := KnightAnim.rig(sim)
	var x := 0.0
	var phase := 0.0
	var shown := 0
	for i in steps:
		var t := i * DT
		var in_dodge := t >= RUN_BEFORE and t < RUN_BEFORE + dodge_t
		var speed := 13.0 if in_dodge else 5.2
		phase += DT * KnightAnim.cadence(r, speed, 1.0, 0.0)
		var p := KnightAnim.blend(KnightAnim.idle_pose(t), KnightAnim.locomotion_pose(r, phase, 1.0, 0.0), 1.0)
		if in_dodge:
			KnightAnim.dodge_pose(p, (t - RUN_BEFORE) / dodge_t)
		KnightAnim.apply(r, p, 1.0 - exp(-14.0 * DT))
		KnightAnim.hold_weapon_upright(lk, r)
		if in_dodge:
			var low := _lowest(sim, holder)
			var sw := _lowest(holder, null)
			print("u %.2f  rolamento %4.0f°  mais baixo %.3f m (%s)  arma %.3f m" % [(t - RUN_BEFORE) / dodge_t,
				rad_to_deg(float(r.get("roll", 0.0))), low[0], low[1], sw[0]])
		x += speed * DT
		if i % SHOW_EVERY == 0:
			var m := KNIGHT.instantiate() as Node3D
			add_child(m)
			var lk2 := KnightLook.apply(m, LOOK)
			var r2 := KnightAnim.rig(m)
			for n in PIVOTS:
				if r2.get(n) and r.get(n):
					(r2[n] as Node3D).transform = (r[n] as Node3D).transform
			for key in ["wrist_r", "wrist_l", "roll", "tuck"]:
				r2[key] = r.get(key, 0.0)
			KnightAnim.hold_weapon_upright(lk2, r2)
			m.position = Vector3(shown * 1.0, sim.position.y, 0)
			m.rotation.y = PI / 2.0
			print("quadro %d: arma %.3f  corpo %.3f" % [shown, _lowest(lk2.holder, null)[0], _lowest(m, lk2.holder)[0]])
			if in_dodge:
				var mark := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.5, 0.01, 0.05)
				mark.mesh = bm
				mark.material_override = StandardMaterial3D.new()
				(mark.material_override as StandardMaterial3D).albedo_color = Color(0.9, 0.2, 0.2)
				mark.position = Vector3(shown * 1.0, 0.005, 0.6)
				add_child(mark)
			shown += 1
	sim.visible = false
	var g := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(shown * 1.0 + 4.0, 0.02, 6.0)
	g.mesh = gb
	g.position = Vector3(shown * 1.0 / 2.0, -0.01, 0)
	add_child(g)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.3
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.position = Vector3((shown - 1) * 1.0 / 2.0, 1.0, 10.0)
	add_child(cam)
	cam.current = true


## Vértice mais baixo do corpo (sem a arma e sem a capa, que no jogo é simulada pelo CapeRig): [altura, nome da malha].
func _lowest(m: Node3D, skip: Node3D) -> Array:
	var best := [INF, ""]
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or mi.mesh == null or (skip and skip.is_ancestor_of(mi)) or mi.name == "Cape" or mi.get_parent().name == "Cape":
			continue
		for v: Vector3 in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			var y := (mi.global_transform * v).y
			if y < best[0]:
				best = [y, mi.name]
	return best


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 12:
		return
	get_viewport().get_texture().get_image().save_png(_out)
	print("SHOT ", _out)
	get_tree().quit()
