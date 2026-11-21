extends RefCounted
## Animação do Mixamo lida de um .fbx em tempo de execução (FBXDocument), sem importar no projeto.
## globals(t) avalia as trilhas e devolve a transformação global (espaço do esqueleto) de cada osso.
## Usado por tools/retarget_shield_combo.gd e tools/shield_combo_shot.gd.

var sk: Skeleton3D
var anim: Animation
var _rot := {}
var _pos := {}
var _rest_g: Array = []


func load_fbx(path: String, parent: Node) -> bool:
	var doc := FBXDocument.new()
	var st := FBXState.new()
	if doc.append_from_file(path, st) != OK:
		push_error("não abriu " + path)
		return false
	var root: Node = doc.generate_scene(st)
	parent.add_child(root)
	if root is Node3D:
		(root as Node3D).visible = false
	var ap: AnimationPlayer = root.find_child("AnimationPlayer", true, false)
	sk = root.find_children("*", "Skeleton3D", true, false)[0]
	anim = ap.get_animation(ap.get_animation_list()[0])
	for i in anim.get_track_count():
		var b := sk.find_bone(str(anim.track_get_path(i).get_concatenated_subnames()))
		if b < 0:
			continue
		if anim.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			_rot[b] = i
		elif anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			_pos[b] = i
	for b in sk.get_bone_count():
		var p := sk.get_bone_parent(b)
		_rest_g.append(sk.get_bone_rest(b) if p < 0 else (_rest_g[p] as Transform3D) * sk.get_bone_rest(b))
	return true


func globals(t: float) -> Array:
	var g := []
	for b in sk.get_bone_count():
		var rest := sk.get_bone_rest(b)
		var q := rest.basis.get_rotation_quaternion()
		var o := rest.origin
		if _rot.has(b):
			q = anim.rotation_track_interpolate(_rot[b], t)
		if _pos.has(b):
			o = anim.position_track_interpolate(_pos[b], t)
		var l := Transform3D(Basis(q), o)
		var p := sk.get_bone_parent(b)
		g.append(l if p < 0 else (g[p] as Transform3D) * l)
	return g


## Posição do osso `bone` (sem o prefixo "mixamorig_").
func pt(g: Array, bone: String) -> Vector3:
	return (g[sk.find_bone("mixamorig_" + bone)] as Transform3D).origin


## Rotação do osso desde a pose de descanso (T-pose olhando +Z), no espaço do esqueleto.
func q(g: Array, bone: String) -> Basis:
	var b := sk.find_bone("mixamorig_" + bone)
	return ((g[b] as Transform3D).basis * (_rest_g[b] as Transform3D).basis.inverse()).orthonormalized()
