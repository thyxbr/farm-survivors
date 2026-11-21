class_name AegisWalls
extends RefCounted
## Égide Cristalina: a barreira como parede sólida. Registro das paredes ativas (uma por escudo erguido), cada
## uma presa a quem lançou: o centro anda com o jogador. Quem decide (solo e servidor) consulta isto:
##   - Enemy, depois de mover: keep_out() empurra para fora quem está dentro. Enquanto a barreira se forma o raio
##     cresce junto com o círculo (empurra aos poucos quem estava perto); depois nenhum monstro entra.
##   - EnemyArrow (flechas, orbes, cuspe, teia): crossing() acha a parede que o projétil cruzou de fora para
##     dentro; ele para ali e o golpe vai para o escudo (take_damage de quem ergueu, que absorve).
##   - Explosões do lado de fora (dinamite): shielded() diz quem está protegido dentro.
##   - Monstro corpo a corpo com o alvo lá dentro: blocking() devolve a parede, que vira o alvo dele (a distância
##     é até a coroa e o golpe vai para o escudo de quem ergueu, que racha e quebra).
## Só para entrar: de dentro para fora tudo passa (o grupo ataca de dentro). A coroa é aberta em cima: o que
## cai do céu (chuva de pedras, ácido) não é parede, e o escudo de quem ergueu absorve como qualquer golpe.
## A parede sai do registro quando a habilidade acaba (soltar, quebrar, morrer): até se quebrar, segura tudo.
## Registro estático: um por processo (o servidor tem as réplicas dos jogadores; o cliente, as dele).

static var walls: Array = []   # [{caster: Node3D, radius, height, born (ms), form (s)}]

const PUSH_SPEED := 2.5   ## tranco para fora (m/s) em quem a parede empurra


## Começa uma parede em volta de `caster`. `form` = tempo (s) para o raio chegar ao cheio.
static func add(caster: Node3D, radius: float, height: float, form: float) -> Dictionary:
	var w := {"caster": caster, "radius": radius, "height": height, "born": Time.get_ticks_msec(), "form": maxf(form, 0.0)}
	walls.append(w)
	return w


static func remove(w: Dictionary) -> void:
	walls.erase(w)


static func clear() -> void:
	walls.clear()


## Paredes ainda válidas (quem ergueu saiu da cena: some do registro).
static func active() -> Array:
	var out: Array = []
	for w in walls.duplicate():
		if not is_instance_valid(w.caster) or not w.caster.is_inside_tree():
			walls.erase(w)
			continue
		out.append(w)
	return out


static func center(w: Dictionary) -> Vector3:
	return (w.caster as Node3D).global_position


## Raio agora: cresce de 0 ao cheio durante a formação (o empurrão acompanha o círculo).
static func radius_now(w: Dictionary) -> float:
	var f := 1.0
	if float(w.form) > 0.0:
		f = clampf((Time.get_ticks_msec() - int(w.born)) / 1000.0 / float(w.form), 0.0, 1.0)
		f = 1.0 - pow(1.0 - f, 2.0)
	return float(w.radius) * f


static func _same_world(w: Dictionary, n: Node3D) -> bool:
	return (w.caster as Node3D).get_world_3d() == n.get_world_3d()


# ------------------------------------------------------------------ contas puras (testes: test_aegis_walls.gd)
## Uma parede de centro `c`, raio `r` e altura `h`: empurra para fora um corpo de raio `body_r` em `pos`.
## Devolve [nova posição, direção para fora (ZERO se não estava dentro)].
static func push_point(pos: Vector3, c: Vector3, r: float, h: float, body_r: float) -> Array:
	if r <= 0.01 or pos.y > c.y + h or pos.y < c.y - 1.5:
		return [pos, Vector3.ZERO]   # parede ainda sem raio, ou o corpo está por cima da coroa
	var rr := r + body_r
	var d := Vector3(pos.x - c.x, 0.0, pos.z - c.z)
	if d.length() >= rr:
		return [pos, Vector3.ZERO]
	var dir := d.normalized() if d.length() > 0.001 else Vector3(sin(pos.x * 7.0 + 1.0), 0.0, cos(pos.x * 7.0 + 1.0)).normalized()
	return [Vector3(c.x + dir.x * rr, pos.y, c.z + dir.z * rr), dir]


## Onde o segmento `from` -> `to` entra na parede (de fora para dentro, na altura dela); null se não entra.
static func entry_point(from: Vector3, to: Vector3, c: Vector3, r: float, h: float):
	if r <= 0.01 or to.y > c.y + h or to.y < c.y - 0.5:
		return null
	var a := Vector2(from.x - c.x, from.z - c.z)
	var b := Vector2(to.x - c.x, to.z - c.z)
	if a.length() < r or b.length() >= r:
		return null
	var dv := b - a
	var qa := dv.dot(dv)
	var qb := 2.0 * a.dot(dv)
	var qc := a.dot(a) - r * r
	var disc := maxf(qb * qb - 4.0 * qa * qc, 0.0)
	var t := clampf((-qb - sqrt(disc)) / maxf(2.0 * qa, 0.00001), 0.0, 1.0)
	return from.lerp(to, t)


## `target` está dentro da parede e `source` fora (a parede fica entre os dois)?
static func between(target: Vector3, source: Vector3, c: Vector3, r: float) -> bool:
	var t := Vector2(target.x - c.x, target.z - c.z).length()
	var s := Vector2(source.x - c.x, source.z - c.z).length()
	return t < r and s >= r


# ------------------------------------------------------------------ consultas do jogo
## Ponto fora de todas as paredes `ws` para um corpo de raio `body_r`. [nova posição, direção (ZERO = não empurrou)].
static func push_out(pos: Vector3, body_r: float, ws: Array) -> Array:
	var out_dir := Vector3.ZERO
	for w in ws:
		var res := push_point(pos, center(w), radius_now(w), float(w.height), body_r)
		if res[1] != Vector3.ZERO:
			pos = res[0]
			out_dir = res[1]
	return [pos, out_dir]


## Monstro (solo ou servidor): fica fora de todas as paredes do mesmo mundo; durante a formação ganha um tranco
## para fora (o círculo empurra). Quem chama deixa a Mãe-Verme de fora (fincada no chão).
static func keep_out(e: CharacterBody3D, body_r: float) -> void:
	if walls.is_empty():
		return
	var ws := active().filter(func(w): return _same_world(w, e))
	if ws.is_empty():
		return
	var res := push_out(e.global_position, body_r, ws)
	var dir: Vector3 = res[1]
	if dir == Vector3.ZERO:
		return
	e.global_position = res[0]
	var inward := Vector3(e.velocity.x, 0.0, e.velocity.z).dot(-dir)
	if inward > 0.0:   # tira só a parte que vai para dentro: pode andar em volta da parede
		e.velocity.x += dir.x * inward
		e.velocity.z += dir.z * inward
	e.velocity.x += dir.x * PUSH_SPEED
	e.velocity.z += dir.z * PUSH_SPEED


## Parede que o segmento `from` -> `to` cruza de fora para dentro, ou {} se nenhuma. A devolvida traz "point"
## (onde cruzou, na borda).
static func crossing(from: Vector3, to: Vector3, node: Node3D) -> Dictionary:
	if walls.is_empty():
		return {}
	for w in active():
		if not _same_world(w, node):
			continue
		var p = entry_point(from, to, center(w), radius_now(w), float(w.height))
		if p != null:
			var hit: Dictionary = w.duplicate()
			hit["point"] = p
			return hit
	return {}


## Paredes que protegem quem está em `target` de algo que vem de `source` (alvo dentro, origem fora).
static func shielded(target: Vector3, source: Vector3, node: Node3D) -> Array:
	var out: Array = []
	if walls.is_empty():
		return out
	for w in active():
		if _same_world(w, node) and between(target, source, center(w), radius_now(w)):
			out.append(w)
	return out


## Parede entre o monstro `e` (fora) e o alvo `target` (dentro): o monstro corpo a corpo bate nela. {} se nenhuma.
static func blocking(e: Node3D, target: Node3D) -> Dictionary:
	if walls.is_empty() or target == null or not is_instance_valid(target):
		return {}
	for w in active():
		if _same_world(w, e) and between(target.global_position, e.global_position, center(w), radius_now(w)):
			return w
	return {}
