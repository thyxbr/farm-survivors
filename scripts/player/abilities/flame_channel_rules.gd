class_name FlameChannelRules
extends RefCounted
## Canalização de Fogo: contas puras (sem nó nem autoload), para os testes unitários: quem está dentro da labareda,
## quem leva um tique agora, quando a canalização termina e qual quadro do círculo mágico mostrar.


## O ponto `pos` (corpo de raio `er`) está dentro da labareda? O cone é contado no chão: começa em `origin` (a palma,
## só x/z), vai `length` m na direção `dir` (no plano) e abre de `r0` a `r1`; na altura vale de `feet_y - below` a
## `feet_y + above` (o mago de pé numa encosta ainda queima quem está abaixo).
static func in_cone(origin: Vector3, dir: Vector3, pos: Vector3, length: float, r0: float, r1: float, feet_y: float,
		below: float, above: float, er := 0.0) -> bool:
	if pos.y < feet_y - below or pos.y > feet_y + above:
		return false
	var d := Vector2(dir.x, dir.z)
	if d.length() < 0.0001:
		return false
	d = d.normalized()
	var rel := Vector2(pos.x - origin.x, pos.z - origin.z)
	var along := rel.dot(d)
	if along < -er or along > length + er:
		return false
	var side := absf(rel.dot(Vector2(-d.y, d.x)))
	return side <= lerpf(r0, r1, clampf(along / maxf(length, 0.001), 0.0, 1.0)) + er


## Quem leva um tique agora (`now`, s): dentro da labareda e sem tique nos últimos `interval` s (`last_hit`: id ->
## instante do último tique; os escolhidos são marcados). `targets` = [{id, pos, radius}]; `cone` = os parâmetros de
## in_cone num Dictionary (origin, dir, length, r0, r1, feet_y, below, above).
static func pick_targets(targets: Array, cone: Dictionary, now: float, interval: float, last_hit: Dictionary) -> Array:
	var out := []
	for t in targets:
		if last_hit.has(t.id) and now - float(last_hit[t.id]) < interval - 0.0001:
			continue
		if not in_cone(cone.origin, cone.dir, t.pos, cone.length, cone.r0, cone.r1, cone.feet_y, cone.below, cone.above,
				float(t.get("radius", 0.0))):
			continue
		last_hit[t.id] = now
		out.append(t)
	return out


## A canalização termina agora? Soltou a tecla (depois do mínimo), passou do máximo ou a mana acabou.
static func should_end(t: float, released: bool, min_time: float, max_time: float, mana: float) -> bool:
	if t >= max_time:
		return true
	if mana <= 0.0:
		return true
	return released and t >= min_time


## Velocidade dos pedaços de chama para chegarem a `length` m em `lifetime` s: o amortecimento `damping` (m/s²) come
## parte do caminho (v·t - d·t²/2 = length).
static func jet_speed(length: float, lifetime: float, damping: float) -> float:
	var l := maxf(lifetime, 0.01)
	return (length + damping * l * l * 0.5) / l


## Quadro do círculo no instante `t` (s): a formação (`form`, uma vez em `form_time`) e depois o laço (`loop`, a
## `fps`), emendando o último quadro do laço no primeiro. Devolve (quadro, próximo, mistura 0..1).
static func circle_frame(t: float, form: Vector2i, form_time: float, loop: Vector2i, fps: float) -> Vector3:
	if t < form_time:
		var x := clampf(t / maxf(form_time, 0.001), 0.0, 1.0) * float(form.y - form.x)
		var f0 := floorf(x)
		return Vector3(form.x + f0, mini(form.x + int(f0) + 1, form.y), minf(x - f0, 0.999))
	var n := maxi(loop.y - loop.x + 1, 1)
	var y := (t - form_time) * fps
	var g := floorf(y)
	return Vector3(loop.x + posmod(int(g), n), loop.x + posmod(int(g) + 1, n), minf(y - g, 0.999))   # o Vector3 é float32: 0,99999 viraria 1


## Quadro do anel se desfazendo, `u` 0..1 do fade-out.
static func end_frame(u: float, frames: Vector2i) -> Vector3:
	var x := clampf(u, 0.0, 1.0) * float(frames.y - frames.x)
	var f0 := floorf(x)
	return Vector3(frames.x + f0, mini(frames.x + int(f0) + 1, frames.y), minf(x - f0, 0.999))
