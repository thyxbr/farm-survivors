class_name PivotSkin
extends Node
## Faz os esqueletos (Skeleton3D) das roupas com pele contínua seguirem os pivôs do cavaleiro.
## O jogo anima girando/movendo nós Node3D (LegL, KneeL, Body, Head, ArmL, ElbowL...); cada osso tem o nome
## de um pivô e repousa na mesma articulação. A cada quadro o osso recebe a transformação do pivô:
##   osso = pivô_agora * pivô_em_repouso⁻¹ * osso_em_repouso
## (no repouso o pivô não tem rotação e fica na origem do osso). Assim o código de animação não muda.
## KnightLook.apply cria um PivotSkin dentro do modelo e chama refresh() depois de trocar as roupas.

const NODE_NAME := "PivotSkin"

var model: Node3D
## [{skel, order: [ids na ordem pai -> filho], pivot: {id: Node3D}, rest: {id: Transform3D}, parent: {id: id}}]
var _skels: Array = []


static func ensure(m: Node3D) -> PivotSkin:
	var ps := m.get_node_or_null(NODE_NAME) as PivotSkin
	if ps == null:
		ps = PivotSkin.new()
		ps.name = NODE_NAME
		ps.model = m
		m.add_child(ps)
	ps.refresh()
	return ps


func _ready() -> void:
	process_priority = 1000      # depois de quem anima os pivôs neste quadro


func refresh() -> void:
	_skels.clear()
	if model == null:
		return
	for skel: Skeleton3D in model.find_children("*", "Skeleton3D", true, false):
		var e := {"skel": skel, "order": [], "pivot": {}, "rest": {}, "parent": {}}
		var depth := {}
		for i in skel.get_bone_count():
			var piv := _pivot(skel.get_bone_name(i))
			if piv == null:
				continue
			e.pivot[i] = piv
			e.rest[i] = skel.get_bone_global_rest(i)
			e.parent[i] = skel.get_bone_parent(i)
			var d := 0
			var p := skel.get_bone_parent(i)
			while p >= 0:
				d += 1
				p = skel.get_bone_parent(p)
			depth[i] = d
		var ids: Array = e.pivot.keys()
		ids.sort_custom(func(a, b): return depth[a] < depth[b])
		e.order = ids
		_skels.append(e)
	update()


## Pivô do modelo com esse nome, fora de qualquer esqueleto (os ossos não são nós).
func _pivot(n: String) -> Node3D:
	for c in model.find_children(n, "Node3D", true, false):
		var inside := false
		var p := c.get_parent()
		while p and p != model:
			if p is Skeleton3D:
				inside = true
				break
			p = p.get_parent()
		if not inside and not (c is MeshInstance3D):
			return c
	return null


func _process(_delta: float) -> void:
	update()


func update() -> void:
	for e in _skels:
		var skel: Skeleton3D = e.skel
		if not is_instance_valid(skel):
			continue
		var to_skel := skel.global_transform.affine_inverse()
		# base do modelo no espaço do esqueleto: o pivô em repouso não tem rotação no espaço do modelo
		var rest_basis := (to_skel * model.global_transform).basis
		var glob := {}
		for i in e.order:
			var piv: Node3D = e.pivot[i]
			var rest: Transform3D = e.rest[i]
			var p_now := to_skel * piv.global_transform
			var p_rest := Transform3D(rest_basis, rest.origin)
			var g: Transform3D = p_now * p_rest.affine_inverse() * rest
			glob[i] = g
			var par: int = e.parent[i]
			var local := g
			if par >= 0:
				local = (glob[par] if glob.has(par) else skel.get_bone_global_pose(par)).affine_inverse() * g
			skel.set_bone_pose_position(i, local.origin)
			skel.set_bone_pose_rotation(i, local.basis.get_rotation_quaternion())
			skel.set_bone_pose_scale(i, local.basis.get_scale())
