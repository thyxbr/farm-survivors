class_name GroundFit
extends RefCounted
## Conta pura do chão dos desenhos de área (FXToon.ground_frame): sem autoloads, para os testes unitários.

const OUTLIER := 0.18   ## m: ponto mais longe que isto do plano do chão é pedra/degrau, fica de fora
const MAX_TILT := 0.8   ## normal.y mínima (~37°): mais íngreme que isto o desenho não deita


## A base do chão a partir dos pontos medidos: o plano que melhor passa por eles, sem os que fogem dele
## (um raio que caiu em cima de uma pedra, tronco ou degrau não inclina o desenho). Terreno íngreme demais
## ou poucos pontos: base reta. A origem fica no plano, na vertical de `pos`.
static func fit(pts: Array, pos: Vector3) -> Transform3D:
	var use: Array = pts.duplicate()
	var plane := Vector3.ZERO      # y = plane.x * dx + plane.y * dz + plane.z, com dx/dz medidos de `pos`
	while true:
		if use.size() < 4:
			var y := pos.y
			if not use.is_empty():   # sem plano confiável: reto, na altura do meio dos pontos
				var hs: Array = use.map(func(p: Vector3) -> float: return p.y)
				hs.sort()
				y = hs[hs.size() / 2]
			return Transform3D(Basis.IDENTITY, Vector3(pos.x, y, pos.z))
		plane = _plane_through(use, pos)
		var worst := -1
		var worst_d := OUTLIER
		for i in use.size():
			var p: Vector3 = use[i]
			var d := absf(p.y - (plane.x * (p.x - pos.x) + plane.y * (p.z - pos.z) + plane.z))
			if d > worst_d:
				worst_d = d
				worst = i
		if worst < 0:
			break
		use.remove_at(worst)
	var origin := Vector3(pos.x, plane.z, pos.z)
	var n := Vector3(-plane.x, 1.0, -plane.y).normalized()
	if n.y < MAX_TILT:
		return Transform3D(Basis.IDENTITY, origin)
	var x := Vector3(1.0, plane.x, 0.0)
	x = (x - n * x.dot(n)).normalized()
	return Transform3D(Basis(x, n, x.cross(n).normalized()), origin)


## Mínimos quadrados de y = a·dx + b·dz + c pelos pontos (dx/dz medidos de `pos`); devolve (a, b, c).
## Pontos alinhados (sem plano único): só a altura média.
static func _plane_through(pts: Array, pos: Vector3) -> Vector3:
	var sx := 0.0
	var sz := 0.0
	var sy := 0.0
	var sxx := 0.0
	var szz := 0.0
	var sxz := 0.0
	var sxy := 0.0
	var szy := 0.0
	for p: Vector3 in pts:
		var dx := p.x - pos.x
		var dz := p.z - pos.z
		sx += dx
		sz += dz
		sy += p.y
		sxx += dx * dx
		szz += dz * dz
		sxz += dx * dz
		sxy += dx * p.y
		szy += dz * p.y
	var m := Basis(Vector3(sxx, sxz, sx), Vector3(sxz, szz, sz), Vector3(sx, sz, float(pts.size())))
	if absf(m.determinant()) < 1e-6:
		return Vector3(0.0, 0.0, sy / pts.size())
	return m.inverse() * Vector3(sxy, szy, sy)
