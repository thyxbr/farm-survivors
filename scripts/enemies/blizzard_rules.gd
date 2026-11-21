class_name BlizzardRules
extends RefCounted
## Habilidades da Sentinela da Nevasca (chefe do Pico): qual golpe vem agora, o Sopro Congelante (cone que gira),
## as Estacas de Gelo que caem do teto e ficam no chão, e a Nevasca da fase 2 (quem fica longe de um braseiro aceso
## vai congelando; o sopro apaga braseiros e eles reacendem depois).
## Puro: sem autoloads (roda no runner de unitários). O servidor e o cliente chegam aos mesmos pontos pela
## direção/semente que vai no snapshot. Ângulos no plano são "yaw": 0 = +Z, crescendo para +X (atan2(x, z)).

## Só começa um golpe com o alvo a até isto (m); mais longe ela anda até ele.
const CAST_RANGE := 17.0
## Sopro: BREATH_T0 s plantando as patas (aviso no chão), depois BREATH_TIME s soprando um cone de BREATH_RANGE m
## e BREATH_HALF graus para cada lado, que gira BREATH_SWEEP graus (BREATH_SWEEP_FURY na fúria) no total. Quem
## está dentro leva um tique de dano a cada BREATH_TICK s e fica lento por BREATH_CHILL s.
const BREATH_T0 := 1.3
const BREATH_TIME := 4.0
const BREATH_RANGE := 15.0
const BREATH_HALF := 20.0
const BREATH_SWEEP := 110.0
const BREATH_SWEEP_FURY := 150.0
const BREATH_TICK := 0.4
const BREATH_CHILL := 2.0
## O cone começa BREATH_LEAD do giro antes do alvo e passa por ele: dá para fugir andando na frente ou atrás dele.
const BREATH_LEAD := 0.35
## No snapshot a direção inicial vai como um deslocamento (ThrowRules.pack_flags): o comprimento diz o sentido.
const BREATH_LEN_CCW := 10.0
const BREATH_LEN_CW := 20.0
## Estacas: SPIKES pontos sorteados pela semente até SPIKE_SPREAD m dela (além de um sob cada jogador). Avisadas
## por SPIKE_T s, caem em SPIKE_FALL s, acertam quem está a até SPIKE_R m e ficam SPIKE_LIFE s no chão soltando
## frio: quem encosta (SPIKE_AURA m) leva um tique a cada SPIKE_TICK s e fica lento.
const SPIKES := 6
const SPIKE_SPREAD := 10.0
const SPIKE_R := 1.8
const SPIKE_T := 1.5
const SPIKE_FALL := 0.5
const SPIKE_LIFE := 9.0
const SPIKE_AURA := 2.0
const SPIKE_TICK := 0.6
## Nevasca (fase 2): BRAZIERS braseiros na sala; a até BRAZIER_R m de um aceso o jogador está abrigado. Fora, a
## exposição vai de 0 a 1 em EXPOSE_RAMP s (e volta a 0 em THAW s no abrigo); a cada BLIZZARD_TICK s o exposto leva
## dano e lentidão que crescem com a exposição. Braseiro apagado pelo sopro reacende em RELIGHT s.
const BRAZIERS := 4
const BRAZIER_R := 4.2
const RELIGHT := 12.0
const EXPOSE_RAMP := 7.0
const THAW := 2.5
const BLIZZARD_TICK := 0.8
const BLIZZARD_DMG_MIN := 0.25
const BLIZZARD_CHILL_AT := 0.2
const BLIZZARD_CHILL_MAX := 2.5
## Sala padrão quando ela não está numa sala de chefe (testes, laboratório): largura e profundidade (m).
const ROOM := Vector2(22.0, 18.0)
## Braseiros acesos nos bits 18..21 de `flags` do snapshot (0 e 1 são lento e enfurecido; 2..17, o golpe). Tudo
## abaixo de 2^24, então sobrevive ao float32 do snapshot.
const MASK_SHIFT := 18
const MASK_ALL := (1 << BRAZIERS) - 1


## O golpe da vez. `n` = golpes já dados na luta; `roar` = a fúria acabou de começar e a nevasca ainda não foi
## chamada. Golpes ímpares são especiais (Sopro e Estacas, alternados); os pares são a patada perto ou, longe, o
## especial que não é o próximo (quem fica longe nunca descansa).
static func attack(n: int, dist: float, reach: float, roar: bool) -> String:
	if roar:
		return "blizzard"
	var next := "breath" if (n / 2) % 2 == 0 else "icicles"
	if n % 2 == 1:
		return next
	if dist <= reach:
		return "swing"
	return "icicles" if next == "breath" else "breath"


## Sentido do giro do `k`-ésimo sopro da luta: alterna (+1 = anti-horário visto de cima, yaw crescendo).
static func sweep_sign(k: int) -> float:
	return 1.0 if k % 2 == 0 else -1.0


static func sweep(enraged: bool) -> float:
	return deg_to_rad(BREATH_SWEEP_FURY if enraged else BREATH_SWEEP)


## Yaw de `v` no plano.
static func yaw_of(v: Vector3) -> float:
	return atan2(v.x, v.z)


static func dir_of(yaw: float) -> Vector3:
	return Vector3(sin(yaw), 0.0, cos(yaw))


## Yaw em que o sopro começa para passar pelo alvo (em `aim`) girando no sentido `sign`.
static func breath_start(aim: float, sign: float, enraged: bool) -> float:
	return aim - sign * sweep(enraged) * BREATH_LEAD


## Yaw do cone `t` s depois do começo do golpe (parado no início durante o preparo, parado no fim depois).
static func breath_angle(start: float, sign: float, t: float, enraged: bool) -> float:
	var u := clampf((t - BREATH_T0) / BREATH_TIME, 0.0, 1.0)
	return start + sign * sweep(enraged) * u


## O sopro está saindo `t` s depois do começo do golpe.
static func breath_active(t: float) -> bool:
	return t >= BREATH_T0 and t <= BREATH_T0 + BREATH_TIME


## `p` está dentro do cone que sai de `origin` no yaw `angle` (a altura não conta).
static func in_cone(origin: Vector3, angle: float, p: Vector3, half_deg: float = BREATH_HALF,
		reach: float = BREATH_RANGE) -> bool:
	var v := Vector3(p.x - origin.x, 0.0, p.z - origin.z)
	var d := v.length()
	if d > reach:
		return false
	if d < 0.6:
		return true   # debaixo do focinho
	return absf(wrapf(yaw_of(v) - angle, -PI, PI)) <= deg_to_rad(half_deg)


## Deslocamento que leva a direção inicial e o sentido do sopro no snapshot.
static func breath_offset(start: float, sign: float) -> Vector3:
	return dir_of(start) * (BREATH_LEN_CCW if sign > 0.0 else BREATH_LEN_CW)


## [yaw inicial, sentido] lidos do deslocamento do snapshot.
static func breath_unpack(offset: Vector3) -> Array:
	var flat := Vector3(offset.x, 0.0, offset.z)
	return [yaw_of(flat), 1.0 if flat.length() < (BREATH_LEN_CCW + BREATH_LEN_CW) / 2.0 else -1.0]


## Sala em volta de `center` para quem não está numa sala de chefe.
static func default_room(center: Vector3) -> Rect2:
	return Rect2(Vector2(center.x, center.z) - ROOM / 2.0, ROOM)


## Onde ficam os braseiros da sala `room` (x, z do mundo), na altura `y`: em losango, a um terço do centro para
## cada parede (entre os pilares dos cantos, longe das paredes).
static func brazier_points(room: Rect2, y: float) -> Array:
	var c := room.get_center()
	var ex := room.size.x * 0.33
	var ez := room.size.y * 0.33
	return [Vector3(c.x - ex, y, c.y), Vector3(c.x + ex, y, c.y), Vector3(c.x, y, c.y + ez), Vector3(c.x, y, c.y - ez)]


## Pontos das Estacas sorteados pela semente, até `spread` m em volta de `center`, sempre dentro da sala.
static func spike_points(seed: int, center: Vector3, room: Rect2, n: int = SPIKES, spread: float = SPIKE_SPREAD) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out := []
	for i in n:
		var a := rng.randf() * TAU
		var d := lerpf(0.3, 1.0, sqrt(rng.randf())) * spread   # nada colado nela: a patada já cobre ali
		out.append(clamp_to_room(Vector3(center.x + cos(a) * d, center.y, center.z + sin(a) * d), room))
	return out


## `p` trazido para dentro da sala (1,5 m longe das paredes); sem sala, fica onde está.
static func clamp_to_room(p: Vector3, room: Rect2, margin := 1.5) -> Vector3:
	if not room.has_area():
		return p
	var r := room.grow(-margin)
	return Vector3(clampf(p.x, r.position.x, r.end.x), p.y, clampf(p.z, r.position.y, r.end.y))


## Braseiros acesos (bit i = braseiro i) a partir dos relógios de reacender (s restantes; <= 0 = aceso).
static func lit_mask(timers: Array) -> int:
	var m := 0
	for i in timers.size():
		if float(timers[i]) <= 0.0:
			m |= 1 << i
	return m


## Relógios depois de `dt` s.
static func relight_step(timers: Array, dt: float) -> Array:
	var out := []
	for t in timers:
		out.append(maxf(0.0, float(t) - dt))
	return out


## Braseiros (bits) que o cone do sopro pega agora.
static func cone_braziers(origin: Vector3, angle: float, points: Array) -> int:
	var m := 0
	for i in points.size():
		if in_cone(origin, angle, points[i]):
			m |= 1 << i
	return m


## `p` está abrigado: a até `r` m de um braseiro aceso.
static func sheltered(p: Vector3, points: Array, mask: int, r: float = BRAZIER_R) -> bool:
	for i in points.size():
		if mask & (1 << i) == 0:
			continue
		var b: Vector3 = points[i]
		if Vector2(p.x - b.x, p.z - b.z).length() <= r:
			return true
	return false


## Exposição (0..1) depois de `dt` s: sobe fora do abrigo, desce dentro.
static func exposure_step(e: float, dt: float, safe: bool) -> float:
	return clampf(e - dt / THAW if safe else e + dt / EXPOSE_RAMP, 0.0, 1.0)


## Dano de um tique da nevasca para quem tem exposição `e` (`base` = o tique cheio).
static func blizzard_damage(base: float, e: float) -> float:
	return base * lerpf(BLIZZARD_DMG_MIN, 1.0, clampf(e, 0.0, 1.0))


## Segundos de lentidão de um tique da nevasca (0 = ainda não congela).
static func blizzard_chill(e: float) -> float:
	if e < BLIZZARD_CHILL_AT:
		return 0.0
	return lerpf(0.8, BLIZZARD_CHILL_MAX, clampf(e, 0.0, 1.0))


static func pack_mask(flags: int, mask: int) -> int:
	return (flags & ((1 << MASK_SHIFT) - 1)) | ((mask & MASK_ALL) << MASK_SHIFT)


static func unpack_mask(flags: int) -> int:
	return (flags >> MASK_SHIFT) & MASK_ALL
