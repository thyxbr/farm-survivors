class_name BowMythicRules
extends RefCounted
## Regras puras dos arcos míticos de endgame (o "fx" do item; o efeito em cena fica em BowMythic).
##   vortex     Suspiro do Abismo: o tiro tensionado abre uma fenda que puxa os inimigos e implode.
##   solar      Alvorada: cada acerto marca o alvo; a 3ª marca em SOLAR.window s derruba uma coluna de sol.
##   dragonfire Presa do Dragão: o tiro tensionado chama uma chuva de flechas de fogo sobre o ponto atingido.
##   gale       Rei dos Ventos: toda flecha empurra; a tensionada ricocheteia e o vento joga o arqueiro para trás.
##   crescent   Crescente Gêmeo: soltar até CRESCENT.window s depois da tensão máxima = crítico e flecha fantasma.
##   bramble    Raiz-Mãe: o tiro tensionado brota um espinheiro (dano e lentidão); abate faz nascer flor que cura.
## Os números multiplicam o dano da flecha que disparou o efeito.

const FX := ["vortex", "solar", "dragonfire", "gale", "crescent", "bramble"]

const VORTEX := {"radius": 6.0, "time": 1.2, "tick": 0.2, "pull": 7.0, "tick_dmg": 0.06,
	"implode_radius": 4.0, "implode_dmg": 1.3, "stun": 0.6}
const SOLAR := {"marks": 3, "window": 6.0, "radius": 2.8, "dmg": 1.6}
const RAIN := {"arrows": 14, "radius": 3.6, "time": 1.0, "height": 13.0, "dmg": 0.55, "splash": 2.0}
const GALE := {"push": 9.0, "bounces": 3, "range": 9.0, "bounce_dmg": 0.7, "dash": 0.2}
const CRESCENT := {"window": 0.3, "ghost_delay": 0.35, "ghost_dmg": 0.8}
const BRAMBLE := {"radius": 2.6, "time": 3.0, "tick": 0.5, "tick_dmg": 0.12, "slow": 1.2,
	"flower_time": 5.0, "flower_radius": 3.5, "flower_heal": 0.04}


static func is_mythic_fx(fx: String) -> bool:
	return fx in FX


## Crescente: a soltura é perfeita se veio até `window` s depois de a tensão chegar ao máximo (full_at < 0 = não chegou).
static func perfect_release(full_at: float, now: float) -> bool:
	return full_at >= 0.0 and now >= full_at and now - full_at <= float(CRESCENT.window) + 0.0001


## Alvorada: soma a marca de `now` às marcas ainda vivas. Devolve {"marks": [...], "fire": bool}; ao disparar a
## coluna as marcas zeram.
static func add_mark(marks: Array, now: float) -> Dictionary:
	var alive: Array = []
	for t in marks:
		if now - float(t) <= float(SOLAR.window):
			alive.append(float(t))
	alive.append(now)
	if alive.size() >= int(SOLAR.marks):
		return {"marks": [], "fire": true}
	return {"marks": alive, "fire": false}


## Presa do Dragão: onde cada flecha da chuva cai (espiral de ângulo áureo, o centro primeiro), no plano do chão.
static func rain_points(center: Vector3, n: int, radius: float) -> Array:
	var out: Array = []
	for i in n:
		var r := radius * sqrt(float(i) / maxf(float(n - 1), 1.0))
		var a := float(i) * 2.39996
		out.append(center + Vector3(cos(a) * r, 0.0, sin(a) * r))
	return out


## Rei dos Ventos: índice do alvo mais perto de `from` (dentro de `range_m`) que ainda não foi atingido; -1 = nenhum.
## `cands` = [{"id": int, "pos": Vector3}], `hit` = {id: true}.
static func bounce_target(from: Vector3, cands: Array, hit: Dictionary, range_m: float) -> int:
	var best := -1
	var best_d := range_m
	for i in cands.size():
		var c: Dictionary = cands[i]
		if hit.has(c.id):
			continue
		var d := from.distance_to(c.pos)
		if d <= best_d:
			best_d = d
			best = i
	return best


## Suspiro do Abismo: velocidade do puxão (m/s) de quem está a `dist` m do centro; fora do raio = 0. Mais forte na
## borda (quem está quase no centro não passa direto).
static func vortex_pull(dist: float) -> float:
	var r := float(VORTEX.radius)
	if dist > r:
		return 0.0
	return float(VORTEX.pull) * (0.35 + 0.65 * clampf(dist / r, 0.0, 1.0))


## A flecha das réplicas viaja só com origem e direção: o tiro tensionado vai como direção de comprimento 2.
static func encode_dir(dir: Vector3, full: bool) -> Vector3:
	return dir.normalized() * (2.0 if full else 1.0)


static func decode_full(v: Vector3) -> bool:
	return v.length() > 1.5
