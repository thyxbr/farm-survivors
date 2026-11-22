class_name GreatswordDarkComboRules
extends RefCounted
## Dança do Abismo: contas puras (sem nó nem autoload), para os testes unitários: o relógio dos quatro golpes (cada um
## começa antes do anterior terminar, para emendar), os instantes dos acertos, quanto o herói anda pela trilha ROOT e
## quem está no arco de cada acerto.


## Tempo (s) que cada golpe leva para tocar o clipe inteiro: a duração do Mixamo dividida pela velocidade.
static func segment_lengths(clip_times: Array, speed: float) -> Array[float]:
	var out: Array[float] = []
	for c in clip_times:
		out.append(maxf(float(c) / maxf(speed, 0.01), 0.01))
	return out


## Instante (s desde o começo da habilidade) em que cada golpe começa: o seguinte entra quando o anterior chega na
## fração `chain[i]` do clipe dele (a volta à guarda do anterior fica de fora; a mistura emenda os dois).
static func segment_starts(lens: Array[float], chain: Array) -> Array[float]:
	var out: Array[float] = []
	var acc := 0.0
	for i in lens.size():
		out.append(acc)
		var c: float = float(chain[i]) if i < chain.size() else 1.0
		acc += lens[i] * clampf(c, 0.05, 1.0)
	return out


## Duração total: o último golpe toca até o fim do clipe.
static func total_time(lens: Array[float], starts: Array[float]) -> float:
	if lens.is_empty():
		return 0.0
	return starts[starts.size() - 1] + lens[lens.size() - 1]


## Golpe e progresso no clipe dele (0..1) no instante `t`: o último golpe que já começou.
static func segment_at(t: float, lens: Array[float], starts: Array[float]) -> Vector2:
	var i := 0
	for k in starts.size():
		if t >= starts[k]:
			i = k
	return Vector2(i, clampf((t - starts[i]) / lens[i], 0.0, 1.0))


## Instante (s) de um acerto: no golpe `seg`, na fração `at` do clipe.
static func hit_time(seg: int, at: float, lens: Array[float], starts: Array[float]) -> float:
	seg = clampi(seg, 0, lens.size() - 1)
	return starts[seg] + lens[seg] * clampf(at, 0.0, 1.0)


## Os acertos (índices em `segs`/`ats`) cujo instante caiu em (t0, t1]: a habilidade aplica cada um uma vez.
static func hits_between(t0: float, t1: float, segs: Array, ats: Array, lens: Array[float], starts: Array[float]) -> Array[int]:
	var out: Array[int] = []
	for i in mini(segs.size(), ats.size()):
		var h := hit_time(int(segs[i]), float(ats[i]), lens, starts)
		if h > t0 and h <= t1:
			out.append(i)
	return out


## Deslocamento (espaço do modelo) da trilha ROOT na fração `u` do clipe, interpolado entre os quadros.
static func root_at(root: Array, u: float) -> Vector3:
	if root.is_empty():
		return Vector3.ZERO
	var x := clampf(u, 0.0, 1.0) * float(root.size() - 1)
	var i := mini(int(x), root.size() - 2)
	if i < 0:
		return root[0]
	return (root[i] as Vector3).lerp(root[i + 1], x - float(i))


## O ponto `pos` (corpo de raio `er`) está no golpe? No chão: até `reach` de `origin` e dentro do arco à frente
## (`arc_deg` total; 360 = em volta). Muito perto conta sempre (o corpo encostado no herói).
static func in_arc(origin: Vector3, fwd: Vector3, pos: Vector3, reach: float, arc_deg: float, er := 0.0) -> bool:
	var d := Vector2(pos.x - origin.x, pos.z - origin.z)
	var dist := d.length()
	if dist > reach + er:
		return false
	if arc_deg >= 359.0 or dist < 0.8:
		return true
	var f := Vector2(fwd.x, fwd.z)
	if f.length() < 0.001:
		return true
	return f.normalized().dot(d / dist) >= cos(deg_to_rad(arc_deg * 0.5))


## Filtra os alvos de um acerto: dentro do arco e com altura parecida. `targets` = [{pos, radius, ...}].
static func pick_targets(targets: Array, origin: Vector3, fwd: Vector3, reach: float, arc_deg: float, height := 2.5) -> Array:
	var out := []
	for t in targets:
		var p: Vector3 = t.pos
		if absf(p.y - origin.y) > height:
			continue
		if in_arc(origin, fwd, p, reach, arc_deg, float(t.get("radius", 0.0))):
			out.append(t)
	return out
