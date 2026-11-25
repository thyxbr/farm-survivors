extends SceneTree
## Converte um GLB de arma vindo de fora (gerador de IA, loja de modelos) no formato que KnightLook espera em
## assets/models/w_<id>.glb: o cabo na origem, a arma subindo em +Y (o "fio" para +Y, como as espadas), um
## nó "Tip" na ponta (onde nasce o rastro do golpe) e o tamanho de uma arma de uma mão.
## O eixo comprido da malha vira o +Y; a ponta mais larga (a cabeça da maça, do martelo, a lâmina do machado)
## fica em cima. A malha e a textura são as do arquivo original.
##   godot --headless --path . -s tools/import_weapon_glb.gd -- <entrada.glb> <saida.glb> [comprimento=0.95] [cabo=0.2]
## `comprimento` é o tamanho total em metros; `cabo` é quanto do comprimento fica abaixo da mão (pomo).


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 2:
		push_error("uso: -- <entrada.glb> <saida.glb> [comprimento] [cabo]")
		quit(1)
		return
	var length := float(a[2]) if a.size() > 2 else 0.95
	var below := float(a[3]) if a.size() > 3 else 0.2

	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(a[0], st) != OK:
		push_error("não leu %s" % a[0])
		quit(1)
		return
	var src := doc.generate_scene(st) as Node3D
	_shrink_textures(src)

	# todos os vértices no espaço da cena original
	var pts := PackedVector3Array()
	for mi: MeshInstance3D in src.find_children("*", "MeshInstance3D", true, false):
		var xf := _global(mi, src)
		for s in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				pts.append(xf * v)
	var box := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		box = box.expand(p)
	var axis := box.get_longest_axis_index()
	var lo := box.position[axis]
	var hi := box.end[axis]
	# largura da malha no primeiro e no último quarto do eixo comprido: a ponta larga é a cabeça
	var wid_lo := 0.0
	var wid_hi := 0.0
	var center := box.get_center()
	for p in pts:
		var off := p - center
		off[axis] = 0.0
		var t := (p[axis] - lo) / (hi - lo)
		if t < 0.25:
			wid_lo = maxf(wid_lo, off.length())
		elif t > 0.75:
			wid_hi = maxf(wid_hi, off.length())
	var head_up := wid_hi >= wid_lo
	print("caixa %s, eixo %d, largura em baixo %.3f / em cima %.3f -> cabeça %s" % [box, axis, wid_lo, wid_hi,
		"no fim" if head_up else "no começo"])

	# base nova: eixo comprido -> +Y (a cabeça para cima); o eixo mais fino -> Z (a espessura da arma)
	var dir := Vector3.ZERO
	dir[axis] = 1.0 if head_up else -1.0
	var others := [0, 1, 2]
	others.erase(axis)
	var thin: int = others[0] if box.size[others[0]] < box.size[others[1]] else others[1]
	var zdir := Vector3.ZERO
	zdir[thin] = 1.0
	var xdir := dir.cross(zdir)
	var rot := Basis(xdir, dir, zdir).inverse()
	var scale := length / (hi - lo)
	var bottom := lo if head_up else hi
	var base_pt := center
	base_pt[axis] = bottom
	# mão a `below` metros da ponta de baixo
	var xf_all := Transform3D(rot.scaled(Vector3.ONE * scale), Vector3.ZERO)
	xf_all.origin = -(xf_all.basis * base_pt) - Vector3(0, below, 0)
	xf_all = _straighten_handle(xf_all, pts, length, below)

	var root := Node3D.new()
	root.name = "Weapon"
	var holder := Node3D.new()
	holder.name = "Mesh"
	holder.transform = xf_all
	root.add_child(holder)
	src.get_parent().remove_child(src) if src.get_parent() else null
	holder.add_child(src)
	var tip := Node3D.new()
	tip.name = "Tip"
	tip.position = Vector3(0, length - below, 0)
	root.add_child(tip)
	for n in [holder, src, tip]:
		n.owner = root
	for c in src.find_children("*", "", true, false):
		c.owner = root

	var out := GLTFDocument.new()
	out.image_format = "Lossy WebP"   # PNG de 2048 deixaria o GLB com ~15 MB
	out.lossy_quality = 0.85
	var ost := GLTFState.new()
	if out.append_from_scene(root, ost) != OK or out.write_to_filesystem(ost, a[1]) != OK:
		push_error("não gravou %s" % a[1])
		quit(1)
		return
	print("gravado %s (%.2f m, cabo %.2f m abaixo da mão)" % [a[1], length, below])
	root.free()
	quit(0)


## Parte de baixo da arma (fração do comprimento) onde fica o cabo, usada para achar a linha dele.
const HANDLE_SPAN := 0.5


## O cabo de uma malha de IA raramente vem reto no eixo: acha a linha do cabo (centro de cada fatia da parte de
## baixo, reta por mínimos quadrados), gira a arma para essa linha ficar em +Y e põe o centro do cabo na origem
## (a mão), como nas espadas. A ponta de baixo fica a `below` m da mão, medida já no eixo novo.
static func _straighten_handle(xf: Transform3D, pts: PackedVector3Array, length: float, below: float) -> Transform3D:
	for _pass in 2:   # a segunda passada mede de novo com o eixo já quase reto
		var moved := PackedVector3Array()
		var y_min := INF
		for p in pts:
			var q := xf * p
			moved.append(q)
			y_min = minf(y_min, q.y)
		# centro da fatia (meio do mínimo e do máximo em x e z) a cada 2 cm do cabo
		var ys := PackedFloat32Array()
		var xs := PackedFloat32Array()
		var zs := PackedFloat32Array()
		var steps := int(length * HANDLE_SPAN / 0.02)
		for i in range(1, steps):
			var yy := y_min + i * 0.02
			var mn := Vector2(INF, INF)
			var mx := -mn
			var n := 0
			for q in moved:
				if absf(q.y - yy) < 0.006:
					mn = mn.min(Vector2(q.x, q.z))
					mx = mx.max(Vector2(q.x, q.z))
					n += 1
			if n >= 6:
				ys.append(yy)
				xs.append((mn.x + mx.x) * 0.5)
				zs.append((mn.y + mx.y) * 0.5)
		if ys.size() < 4:
			return xf
		var lx := _fit(ys, xs)   # x = a + b*y
		var lz := _fit(ys, zs)
		var dir := Vector3(lx.y, 1.0, lz.y).normalized()
		var hand_y := y_min + below
		var hand := Vector3(lx.x + lx.y * hand_y, hand_y, lz.x + lz.y * hand_y)
		var rot := Basis(Quaternion(dir, Vector3.UP))
		xf = Transform3D(rot, -(rot * hand)) * xf
		print("cabo: inclinação %.1f°, desvio na mão (%.3f, %.3f) m" % [rad_to_deg(dir.angle_to(Vector3.UP)), hand.x, hand.z])
	return xf


static func _fit(ys: PackedFloat32Array, vs: PackedFloat32Array) -> Vector2:
	var n := ys.size()
	var sy := 0.0
	var sv := 0.0
	var syy := 0.0
	var syv := 0.0
	for i in n:
		sy += ys[i]
		sv += vs[i]
		syy += ys[i] * ys[i]
		syv += ys[i] * vs[i]
	var b := (n * syv - sy * sv) / (n * syy - sy * sy)
	return Vector2((sv - b * sy) / n, b)


## Texturas acima de MAX_TEX px caem para MAX_TEX (uma arma na mão não precisa de 2048 px).
const MAX_TEX := 1024
const TEX_PROPS := ["albedo_texture", "normal_texture", "metallic_texture", "roughness_texture", "emission_texture",
	"ao_texture"]


static func _shrink_textures(root: Node) -> void:
	var done := {}
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null:
				continue
			for prop: String in TEX_PROPS:
				var tex := mat.get(prop) as Texture2D
				if tex == null:
					continue
				if not done.has(tex):
					var img := tex.get_image()
					if img.is_compressed():
						img.decompress()
					if maxi(img.get_width(), img.get_height()) > MAX_TEX:
						var k := float(MAX_TEX) / maxi(img.get_width(), img.get_height())
						img.resize(int(img.get_width() * k), int(img.get_height() * k), Image.INTERPOLATE_LANCZOS)
					done[tex] = ImageTexture.create_from_image(img)
				mat.set(prop, done[tex])


static func _global(n: Node3D, top: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != top:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return top.transform * xf
