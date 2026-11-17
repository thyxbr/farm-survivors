class_name VillageWard
extends RefCounted
## Zona protegida pela guarda da vila (Vale, coordenadas do mundo): a vila cercada e, ao sul, a Horta e o
## Pomar. Nenhum monstro do mundo entra: a IA não persegue quem está aqui dentro nem dá passo para dentro, e o
## que entrar mesmo assim (empurrão, bug de física) é abatido pelos guardas depois de DOOM segundos.
## Monstro abatido pela guarda não dá XP, loot nem conta em missão para ninguém (Enemy.guard_kill).
## Só contas puras (sem autoload), para os testes. A Horda (arena) fica longe e não usa a zona.

## Retângulos (x0, z0, largura, profundidade): a cerca da vila (VillageLayout.BOUNDS) e a Horta + Pomar.
const ZONES := [Rect2(-36, -18, 75, 45), Rect2(-13, 25, 44, 18)]
## Folga em volta das zonas (m): o monstro para antes da cerca e a guarda atira quem passar dela.
const MARGIN := 4.0
## Folga (m) além da cerca em que a guarda atira: um pouco mais para dentro que a linha onde o monstro para
## (MARGIN), para um empurrão de quem luta na beira da cerca não custar o abate.
const KILL_MARGIN := 1.5
## Segundos dentro da zona até a flecha do guarda derrubar o monstro.
const DOOM := 0.6
## Distância (m) que um ponto de monstro (descontado o raio do bando) precisa manter da zona com folga: o passeio
## vai até 6 m da casa, então com 10 m o bando não fica rondando o portão (MapValidation confere).
const SPAWN_CLEARANCE := 10.0


## O ponto (x, z) está na zona protegida (com a folga)?
static func inside(pos: Vector3, margin := MARGIN) -> bool:
	for r: Rect2 in ZONES:
		if r.grow(margin).has_point(Vector2(pos.x, pos.z)):
			return true
	return false


## Distância (m, no plano) do ponto até a zona com folga; 0 dentro.
static func distance(pos: Vector3, margin := MARGIN) -> float:
	var best := INF
	var p := Vector2(pos.x, pos.z)
	for r: Rect2 in ZONES:
		var g := r.grow(margin)
		var dx := maxf(maxf(g.position.x - p.x, 0.0), p.x - g.end.x)
		var dz := maxf(maxf(g.position.y - p.y, 0.0), p.y - g.end.y)
		best = minf(best, Vector2(dx, dz).length())
	return best


## O passo de `from` para `to` entra na zona? (quem já está dentro pode sair à vontade)
static func blocks_step(from: Vector3, to: Vector3) -> bool:
	return inside(to) and not inside(from)
