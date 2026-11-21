class_name AbyssRules
extends RefCounted
## Habilidades do Arauto do Abismo (chefe final, dungeon do Abismo): as três fases, qual golpe vem agora, a Rajada
## de Sombras em leque, a Garra em arco, as Zonas de Vazio que crescem, a Miragem (teleporte com cópias) e o
## Colapso (puxão para o centro e explosão em anéis de dentro para fora).
## Puro: sem autoloads (roda no runner de unitários). O servidor e o cliente chegam aos mesmos pontos pela
## direção/semente que vai no snapshot.

## Golpes novos do Arauto (os nomes que entram em Network.ATTACK_KINDS); a Garra usa o "swing" de todos.
const KINDS := ["volley", "voids", "mirage", "collapse"]

## Fases pela fração de vida: 2 abaixo de PHASE2 (Miragem), 3 abaixo de PHASE3 (Colapso).
const PHASE2 := 0.65
const PHASE3 := 0.30

## Rajada de Sombras: projéteis em leque na direção do alvo, VOLLEY_FAN graus entre um e outro; ele ataca de até
## VOLLEY_RANGE m. Da fase 2 em diante o leque é maior.
const VOLLEY_RANGE := 20.0
const VOLLEY_SHOTS := 5
const VOLLEY_SHOTS_FURY := 7
const VOLLEY_FAN := 13.0
## Garra em arco: setor de CLAW_R m à frente dele, CLAW_HALF graus para cada lado.
const CLAW_R := 5.2
const CLAW_HALF := 65.0
## Zonas de Vazio: VOIDS sorteadas pela semente até VOID_SPREAD m do centro (além de uma sob cada jogador); nascem
## com VOID_R0 m, crescem até VOID_R1 m em VOID_GROW s e somem depois de VOID_LIFE s.
const VOIDS := 4
const VOID_SPREAD := 9.0
const VOID_R0 := 1.6
const VOID_R1 := 4.2
const VOID_GROW := 14.0
const VOID_LIFE := 24.0
## Miragem: ele e as cópias reaparecem em roda, a MIRAGE_RING m do centro da sala; cada cópia dura ECHO_LIFE s.
const MIRAGE_RING := 6.5
const ECHO_LIFE := 16.0
## Acertar o verdadeiro com cópias vivas desfaz todas e o deixa ECHO_BREAK s sem golpe novo.
const ECHO_BREAK := 1.6
## Colapso: por PULL_T s todos são puxados para o centro a PULL_SPEED m/s (até PULL_STOP m dele). Depois a
## explosão abre de dentro para fora: o miolo (disco de COLLAPSE_DISC m) estoura em COLLAPSE_T0 s e cada anel de
## COLLAPSE_WIDTH m vem COLLAPSE_DT s depois do anterior, com um vão seguro de COLLAPSE_GAP m entre dois.
const PULL_T := 2.0
const PULL_SPEED := 9.0
const PULL_STOP := 2.0
const COLLAPSE_RINGS := 4
const COLLAPSE_DISC := 4.0
const COLLAPSE_GAP := 1.5
const COLLAPSE_WIDTH := 2.0
const COLLAPSE_T0 := 3.3
const COLLAPSE_DT := 0.5


## Fase (1 a 3) pela fração de vida que resta.
static func phase(hp_frac: float) -> int:
	if hp_frac < PHASE3:
		return 3
	return 2 if hp_frac < PHASE2 else 1


## O golpe da vez. `n` = golpes já dados NESTA fase (zera quando a fase muda, então cada fase abre com o golpe
## dela); `echoes` = cópias vivas agora. Fase 1: três golpes comuns e as Zonas de Vazio. Fase 2: abre com a
## Miragem e repete a cada 6 golpes. Fase 3: abre com o Colapso e repete a cada 6, com a Miragem no meio.
## Golpe comum: Garra perto, Rajada longe. Com cópias vivas não faz outra Miragem.
static func attack(n: int, phase_now: int, dist: float, reach: float, echoes: int) -> String:
	var want := ""
	match phase_now:
		1:
			want = "voids" if n % 4 == 3 else ""
		2:
			want = ["mirage", "", "", "voids", "", ""][n % 6]
		_:
			want = ["collapse", "", "mirage", "", "voids", ""][n % 6]
	if want == "mirage" and echoes > 0:
		want = ""
	if want != "":
		return want
	return "swing" if dist <= reach else "volley"


## Golpe das cópias: só os comuns.
static func echo_attack(dist: float, reach: float) -> String:
	return "swing" if dist <= reach else "volley"


## Segundos do início do golpe até ele acertar.
static func hit_time(kind: String) -> float:
	match kind:
		"volley":
			return 0.9
		"voids":
			return 1.3
		"mirage":
			return 1.0
		"collapse":
			return COLLAPSE_T0
	return 0.85   # garra


## Duração do golpe inteiro.
static func duration(kind: String) -> float:
	match kind:
		"volley":
			return 1.7
		"voids":
			return 2.1
		"mirage":
			return 1.9
		"collapse":
			return float(collapse_ring(COLLAPSE_RINGS - 1).t) + 0.9
	return 1.6


static func _flat(dir: Vector3) -> Vector3:
	var d := Vector3(dir.x, 0.0, dir.z)
	return d.normalized() if d.length() > 0.001 else Vector3.FORWARD


## Quantos projéteis tem a Rajada nesta fase.
static func volley_shots(phase_now: int) -> int:
	return VOLLEY_SHOTS if phase_now <= 1 else VOLLEY_SHOTS_FURY


## Direções da Rajada (no plano, normalizadas): leque centrado em `dir`.
static func volley_dirs(dir: Vector3, shots: int) -> Array:
	var d := _flat(dir)
	var out := []
	for i in shots:
		out.append(d.rotated(Vector3.UP, deg_to_rad(VOLLEY_FAN * (i - (shots - 1) / 2.0))))
	return out


## `p` está dentro do arco da Garra de quem está em `origin` olhando para `dir`.
static func in_claw(origin: Vector3, dir: Vector3, p: Vector3) -> bool:
	var v := Vector3(p.x - origin.x, 0.0, p.z - origin.z)
	var dist := v.length()
	if dist > CLAW_R:
		return false
	if dist < 0.8:
		return true   # colado nele: não há como estar "atrás"
	return v.normalized().dot(_flat(dir)) >= cos(deg_to_rad(CLAW_HALF))


## Ponto `p` trazido para dentro de `rect` (x, z do mundo) com `margin` m de folga; sem sala (rect vazio) não muda.
static func clamp_to_room(p: Vector3, rect: Rect2, margin: float) -> Vector3:
	if not rect.has_area():
		return p
	var m := minf(margin, minf(rect.size.x, rect.size.y) * 0.45)
	return Vector3(clampf(p.x, rect.position.x + m, rect.end.x - m), p.y,
		clampf(p.z, rect.position.y + m, rect.end.y - m))


## Pontos das Zonas de Vazio sorteados pela semente em volta de `center`, dentro da sala.
static func void_points(seed: int, center: Vector3, rect: Rect2, spread: float = VOID_SPREAD, n: int = VOIDS) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out := []
	for i in n:
		var a := rng.randf() * TAU
		var d := lerpf(0.3, 1.0, sqrt(rng.randf())) * spread
		out.append(clamp_to_room(Vector3(center.x + cos(a) * d, center.y, center.z + sin(a) * d), rect, VOID_R0))
	return out


## Raio de uma Zona de Vazio `t` s depois de nascer.
static func void_radius(t: float) -> float:
	return lerpf(VOID_R0, VOID_R1, clampf(t / VOID_GROW, 0.0, 1.0))


## Quantas cópias a Miragem cria nesta fase.
static func echo_count(phase_now: int) -> int:
	return 3 if phase_now >= 3 else 2


## Onde ele e as cópias reaparecem: `copies` + 1 pontos em roda, a MIRAGE_RING m de `center`, com a roda girada
## pela semente e dentro da sala. O primeiro ponto é o do verdadeiro (a roda gira ao acaso: a posição não entrega).
static func mirage_points(seed: int, center: Vector3, rect: Rect2, copies: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var a0 := rng.randf() * TAU
	var n := copies + 1
	var out := []
	for i in n:
		var a := a0 + TAU * i / n
		out.append(clamp_to_room(Vector3(center.x + cos(a) * MIRAGE_RING, center.y, center.z + sin(a) * MIRAGE_RING),
			rect, 2.0))
	return out


## Faixa `i` do Colapso: {r0: raio de dentro, r1: raio de fora (m), t: segundos depois do início do golpe}.
## A faixa 0 é o miolo (disco); as outras são anéis, cada um depois de um vão seguro.
static func collapse_ring(i: int) -> Dictionary:
	var t := COLLAPSE_T0 + COLLAPSE_DT * i
	if i <= 0:
		return {"r0": 0.0, "r1": COLLAPSE_DISC, "t": t}
	var r0 := COLLAPSE_DISC + COLLAPSE_GAP + (i - 1) * (COLLAPSE_WIDTH + COLLAPSE_GAP)
	return {"r0": r0, "r1": r0 + COLLAPSE_WIDTH, "t": t}


## A distância `dist` (no plano, do centro) está dentro da faixa `i`.
static func in_collapse_ring(dist: float, i: int) -> bool:
	var q := collapse_ring(i)
	return dist >= float(q.r0) and dist <= float(q.r1)


## A distância `dist` fica num vão: nenhuma faixa do Colapso passa ali.
static func collapse_safe(dist: float) -> bool:
	for i in COLLAPSE_RINGS:
		if in_collapse_ring(dist, i):
			return false
	return true


## Onde fica quem está em `pos` depois de `dt` s do puxão para `center` (no plano; para a PULL_STOP m dele).
static func pull_step(pos: Vector3, center: Vector3, dt: float) -> Vector3:
	var v := Vector3(center.x - pos.x, 0.0, center.z - pos.z)
	var dist := v.length()
	if dist <= PULL_STOP:
		return pos
	var step := minf(PULL_SPEED * dt, dist - PULL_STOP)
	return pos + v / dist * step
