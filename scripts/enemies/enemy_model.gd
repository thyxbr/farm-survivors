class_name EnemyModel
extends RefCounted
## Modelo pronto de cada tipo de inimigo, montado uma vez e instanciado a cada nascimento.
##
## O GLB do goblin tem 102 peças soltas (uma MeshInstance3D por cubo/cilindro do Blender). Cada passo de
## física movia as 102, e a Horda cheia não saía do teto de 8 passos por quadro (docs/desempenho). Aqui a
## tintura, o material da gelatina e o estilo toon são aplicados uma vez por tipo, e as peças irmãs (mesmo nó
## pai) viram uma malha só, com uma superfície por material: o goblin fica com uma malha por grupo que o
## código anima (Body, Head, ArmL, ArmR, LegL, LegR) e uma por peça de equipamento da variante (Opt_<Nome>,
## ver EnemyGear). O desenho é o mesmo.
## Os nós de grupo continuam com o mesmo nome; as peças juntadas ficam num filho chamado "Merged".

const MODELS := {
	"slime": preload("res://assets/models/slime.glb"),
	"goblin": preload("res://assets/models/goblin.glb"),
	"skeleton": preload("res://assets/models/skeleton.glb"),
	"raptor": preload("res://assets/models/raptor.glb"),
	"spider": preload("res://assets/models/spider.glb"),
}
const MERGED := "Merged"

static var _scenes := {}        # tipo + estilo -> PackedScene do modelo pronto


## Uma cópia do modelo de `kind` (chave de Enemy.TYPES, com os dados dele), já com tintura, toon e contorno.
## Sem autoload aqui, para que as ferramentas de foto e os testes unitários usem o mesmo caminho do jogo.
static func instance(kind: String, data: Dictionary) -> Node3D:
	var toon := ToonLook.enabled()
	var key := "%s|%d|%d" % [kind, int(toon), int(toon and ToonLook.outline_enabled())]
	var ps: PackedScene = _scenes.get(key)
	if ps == null:
		var src: Node3D = MODELS[data.model].instantiate()
		# só o equipamento da variante (Opt_<Nome>) entra no modelo pronto; o resto sai antes de juntar
		var no_gear := EnemyGear.apply(src, data.get("gear", []))
		if not no_gear.is_empty():
			push_warning("%s: o modelo %s não tem as peças %s" % [kind, data.model, str(no_gear)])
		_dress(src, kind, data)
		var out := merged_copy(src) as Node3D
		src.free()
		_own(out, out)
		ps = PackedScene.new()
		ps.pack(out)
		out.free()
		_scenes[key] = ps
	return ps.instantiate() as Node3D


## Materiais do tipo: gelatina do slime, tintura das variantes do goblin e, por último, o toon (que lê as
## cores já tingidas e junta as cascas de contorno por grupo de peças).
static func _dress(model: Node3D, kind: String, data: Dictionary) -> void:
	var toon := ToonLook.enabled()
	if data.model == "slime" and toon:
		ToonLook.apply_slime(model, data.get("goo", ToonLook.SLIME_GOO))
	elif data.model == "slime":
		var goo := StandardMaterial3D.new()
		goo.albedo_color = data.get("goo", Color(0.25, 0.85, 0.3, 0.78))
		goo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		goo.roughness = 0.1
		goo.rim_enabled = true
		goo.rim = 0.6
		for n in ["BodyMesh", "Base"]:
			var m := model.find_child(n, true, false) as MeshInstance3D
			if m:
				m.material_override = goo
	if data.has("tint"):
		tint(model, data.tint[0], data.tint[1], kind == "goblin_dourado")
	if toon:
		ToonLook.apply(model, true, true)


## Recolore o modelo (variantes do goblin): cada material é copiado e puxado para a cor. Peças que usam o
## mesmo material ficam com a mesma cópia.
static func tint(model: Node, c: Color, amount: float, golden := false) -> void:
	var done := {}      # material original -> cópia tingida
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i) as StandardMaterial3D
			if mat == null:
				continue
			var m2: StandardMaterial3D = done.get(mat)
			if m2 == null:
				m2 = mat.duplicate() as StandardMaterial3D
				m2.albedo_color = mat.albedo_color.lerp(c, amount)
				if golden:
					m2.metallic = 0.7
					m2.roughness = 0.3
				done[mat] = m2
			mi.set_surface_override_material(i, m2)


## Cópia de `src` com as peças irmãs juntadas. Só entram peças simples (ver `_mergeable`); o resto é
## copiado como está, na mesma posição da árvore. `src` não é alterado.
static func merged_copy(src: Node) -> Node:
	var dst: Node
	if src is MeshInstance3D:
		dst = _copy_mesh(src)
	elif src.get_class() == "Node3D":
		dst = Node3D.new()
	else:
		return src.duplicate()      # tipo que este script não conhece: cópia inteira, sem juntar nada
	dst.name = src.name
	(dst as Node3D).transform = (src as Node3D).transform
	(dst as Node3D).visible = (src as Node3D).visible
	for k in src.get_meta_list():
		dst.set_meta(k, src.get_meta(k))
	for g in src.get_groups():
		dst.add_to_group(g, true)
	var pieces: Array[MeshInstance3D] = []
	var rest: Array[Node] = []
	for c in src.get_children():
		if _mergeable(c):
			pieces.append(c)
		else:
			rest.append(c)
	if pieces.size() < 2:       # uma peça sozinha não tem com quem juntar: segue como está
		rest = src.get_children()
		pieces.clear()
	for c in rest:
		dst.add_child(merged_copy(c))
	if not pieces.is_empty():
		var mi := MeshInstance3D.new()
		mi.name = MERGED
		mi.mesh = merge(pieces)
		dst.add_child(mi)
	return dst


static func _copy_mesh(src: MeshInstance3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = src.mesh
	mi.skin = src.skin
	mi.skeleton = src.skeleton
	mi.material_override = src.material_override
	mi.material_overlay = src.material_overlay
	mi.cast_shadow = src.cast_shadow
	mi.layers = src.layers
	mi.visibility_range_end = src.visibility_range_end
	mi.visibility_range_end_margin = src.visibility_range_end_margin
	if src.mesh != null:
		for s in src.mesh.get_surface_count():
			var m := src.get_surface_override_material(s)
			if m != null:
				mi.set_surface_override_material(s, m)
	return mi


## Peça que pode entrar na malha juntada: folha visível, de triângulos, sem esqueleto, sem material por
## cima e com as opções de desenho padrão. (A gelatina do slime e as cascas de contorno ficam de fora.)
static func _mergeable(n: Node) -> bool:
	var mi := n as MeshInstance3D
	if mi == null or mi.get_child_count() > 0 or not mi.visible or mi.skin != null:
		return false
	if mi.material_override != null or mi.material_overlay != null or mi.is_in_group(ToonLook.OUTLINE_GROUP):
		return false
	if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON or mi.layers != 1 or mi.visibility_range_end > 0.0:
		return false
	var mesh := mi.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0 or mesh.get_blend_shape_count() > 0:
		return false
	for s in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			return false
	return true


## Uma malha com todas as peças, cada uma na sua posição (espaço do nó pai), com uma superfície por
## material em uso. Leva posição, normal, cor por vértice e UV; peça espelhada tem os triângulos invertidos.
static func merge(pieces: Array[MeshInstance3D]) -> ArrayMesh:
	var buckets := {}       # material -> {v, n, col, uv, idx, has_col, has_uv}
	for mi in pieces:
		var xf := mi.transform
		var nb := xf.basis.inverse().transposed()      # normais: inversa transposta (escala não uniforme)
		var flip := xf.basis.determinant() < 0.0
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if not buckets.has(mat):
				buckets[mat] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "col": PackedColorArray(),
					"uv": PackedVector2Array(), "idx": PackedInt32Array(), "has_col": false, "has_uv": false}
			var b: Dictionary = buckets[mat]
			var arr := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var base: int = b.v.size()
			var count := v.size()
			for i in count:
				b.v.append(xf * v[i])
			if arr[Mesh.ARRAY_NORMAL] != null:
				var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				for i in count:
					b.n.append((nb * nn[i]).normalized())
			else:
				for i in count:
					b.n.append(Vector3.UP)
			if arr[Mesh.ARRAY_COLOR] != null:
				b.col.append_array(arr[Mesh.ARRAY_COLOR])
				b.has_col = true
			else:
				for i in count:
					b.col.append(Color.WHITE)       # sem cor por vértice o shader lê branco
			if arr[Mesh.ARRAY_TEX_UV] != null:
				b.uv.append_array(arr[Mesh.ARRAY_TEX_UV])
				b.has_uv = true
			else:
				for i in count:
					b.uv.append(Vector2.ZERO)
			var idx := PackedInt32Array()
			if arr[Mesh.ARRAY_INDEX] != null:
				idx = arr[Mesh.ARRAY_INDEX]
			else:
				idx.resize(count)
				for i in count:
					idx[i] = i
			for t in range(0, idx.size() - 2, 3):
				b.idx.append(base + idx[t])
				b.idx.append(base + idx[t + (2 if flip else 1)])
				b.idx.append(base + idx[t + (1 if flip else 2)])
	var out := ArrayMesh.new()
	for mat in buckets:
		var b: Dictionary = buckets[mat]
		if b.v.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = b.v
		arrays[Mesh.ARRAY_NORMAL] = b.n
		if b.has_col:
			arrays[Mesh.ARRAY_COLOR] = b.col
		if b.has_uv:
			arrays[Mesh.ARRAY_TEX_UV] = b.uv
		arrays[Mesh.ARRAY_INDEX] = b.idx
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, mat)
	return out


static func _own(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		_own(c, owner)
