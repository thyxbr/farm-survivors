class_name TargetHighlight
extends Node3D
## Marca quem vai receber a Cura enquanto o healer mira: borda clara pulsando em volta do corpo (casca
## invertida, como o contorno toon, mas mais grossa e brilhante), anel no chão e um losango de luz girando
## sobre a cabeça. Filho do `model` do jogador marcado; sair da árvore tira as cascas das peças.

const SH := preload("res://shaders/target_outline.gdshader")
const MIN_PIECE := 0.08     ## peças menores (olhos, rebites) ficam sem borda: a casca engoliria a peça
const GEM_Y := 2.7
static var _mat: ShaderMaterial

var _hulls: Array[Node] = []
var _gem: MeshInstance3D
var _ring: MeshInstance3D
var _t := 0.0


func _ready() -> void:
	name = "HealMark"
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = SH
	_build_hulls(get_parent())
	_build_marker()


func _exit_tree() -> void:
	for h in _hulls:
		if is_instance_valid(h):
			h.queue_free()
	_hulls.clear()


func _process(delta: float) -> void:
	_t += delta
	if _gem:
		_gem.position.y = GEM_Y + sin(_t * 4.0) * 0.08
		_gem.rotation.y += delta * 3.0
	if _ring:
		var s := 1.0 + 0.08 * sin(_t * 6.0)
		_ring.scale = Vector3(s, 1.0, s)


func _build_hulls(model: Node) -> void:
	if model == null:
		return
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.name.begins_with("ToonOutline") or mi.name.begins_with("HealMark"):
			continue
		if not mi.is_visible_in_tree() or _skip(mi, model):
			continue
		if mi.get_aabb().get_longest_axis_size() < MIN_PIECE:
			continue
		var hull := ToonLook._hull_of(mi.mesh)
		if hull == null:
			continue
		var o := MeshInstance3D.new()
		o.name = "HealMarkHull"
		o.mesh = hull
		o.material_override = _mat
		o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		o.layers = mi.layers
		if mi.skin != null:
			# malha com esqueleto: a casca fica ao lado, presa ao mesmo esqueleto
			o.skin = mi.skin
			o.transform = mi.transform
			mi.get_parent().add_child(o)
			o.skeleton = o.get_path_to(mi.get_node(mi.skeleton)) if mi.has_node(mi.skeleton) else mi.skeleton
		else:
			mi.add_child(o)
		_hulls.append(o)


## Peças que não são do corpo: efeitos de aura e do próprio marcador.
func _skip(n: Node, model: Node) -> bool:
	var p := n
	while p != null and p != model:
		if p == self or p is BuffAura:
			return true
		p = p.get_parent()
	return false


func _build_marker() -> void:
	# losango (duas pirâmides de 4 lados) apontando para a cabeça
	_gem = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.17
	cm.bottom_radius = 0.0
	cm.height = 0.32
	cm.radial_segments = 4
	cm.rings = 1
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(0.7, 1.0, 0.72)
	cm.material = gm
	_gem.mesh = cm
	_gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gem.position.y = GEM_Y
	add_child(_gem)
	var cap := MeshInstance3D.new()
	var cap_m := CylinderMesh.new()
	cap_m.top_radius = 0.0
	cap_m.bottom_radius = 0.17
	cap_m.height = 0.12
	cap_m.radial_segments = 4
	cap_m.rings = 1
	cap_m.material = gm
	cap.mesh = cap_m
	cap.position.y = 0.22
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gem.add_child(cap)
	# anel no chão
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.62
	tm.outer_radius = 0.72
	tm.rings = 32
	tm.ring_segments = 4
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(0.55, 1.0, 0.6, 0.8)
	tm.material = rm
	_ring.mesh = tm
	_ring.scale = Vector3(1.0, 0.15, 1.0)
	_ring.position.y = 0.06
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
