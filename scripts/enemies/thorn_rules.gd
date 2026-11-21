class_name ThornRules
extends RefCounted
## Habilidades da Espinheira, a Guardiã-Raiz (chefe do Bosque): qual golpe vem agora, as Raízes em linha que
## irrompem do chão até o alvo, os Brotos que curam a árvore enquanto vivem e as Nuvens de Esporos da fúria.
## Puro: sem autoloads (roda no runner de unitários). O servidor e o cliente chegam aos mesmos pontos pela
## direção/semente que vai no snapshot.

## Raízes: a linha sai de ROOT_START m à frente dela e vai até ROOT_LEN m, em ROOT_SEGS trechos; cada trecho
## irrompe ROOT_DT s depois do anterior (o primeiro em ROOT_T0). Quem está a até ROOT_HALF m da linha leva o golpe
## quando o trecho dele irrompe e fica preso (lento) por ROOT_SNARE s.
const ROOT_START := 1.5
const ROOT_LEN := 18.0
const ROOT_SEGS := 10
const ROOT_HALF := 1.1
const ROOT_T0 := 1.1
const ROOT_DT := 0.09
const ROOT_SNARE := 1.6
## Na fúria são três linhas em leque, ROOT_FAN graus para cada lado.
const ROOT_FAN := 24.0
## Brotos: quantos nascem, a que distância dela, e quanto cada um cura por segundo (fração da vida máxima).
const SPROUTS := 3
const SPROUT_RING := 6.0
const SPROUT_HEAL := 0.006
## Não invoca de novo enquanto houver pelo menos isto de brotos vivos.
const SPROUT_MAX_ALIVE := 2
## Esporos: nuvens sorteadas pela semente em volta dela (além de uma sob cada jogador), que nascem com SPORE_R0 m
## e crescem até SPORE_R1 m em SPORE_LIFE s.
const SPORES := 5
const SPORE_SPREAD := 11.0
const SPORE_R0 := 1.6
const SPORE_R1 := 3.0
const SPORE_LIFE := 12.0
## A cada SPECIAL_EVERY golpes um é especial: Brotos e, na fúria, alternando com os Esporos.
const SPECIAL_EVERY := 4


## O golpe da vez. `n` = golpes já dados na luta; `sprouts_alive` = brotos vivos agora. O 4º golpe de cada ciclo é
## especial (Brotos; na fúria alterna Esporos e Brotos, e com brotos demais vivos vira Esporos ou Raízes); os
## outros são a garra perto e as Raízes longe.
static func attack(n: int, enraged: bool, dist: float, reach: float, sprouts_alive: int) -> String:
	if n % SPECIAL_EVERY == SPECIAL_EVERY - 1:
		var cycle := n / SPECIAL_EVERY
		var want := "spores" if enraged and cycle % 2 == 1 else "sprouts"
		if want == "sprouts" and sprouts_alive >= SPROUT_MAX_ALIVE:
			want = "spores" if enraged else "roots"
		return want
	if dist <= reach:
		return "swing"
	return "roots"


## Direções das linhas de raiz (no plano, normalizadas) a partir de `dir`: uma, ou três em leque na fúria.
static func root_dirs(dir: Vector3, enraged: bool) -> Array:
	var d := Vector3(dir.x, 0.0, dir.z)
	d = d.normalized() if d.length() > 0.001 else Vector3.FORWARD
	if not enraged:
		return [d]
	return [d.rotated(Vector3.UP, deg_to_rad(-ROOT_FAN)), d, d.rotated(Vector3.UP, deg_to_rad(ROOT_FAN))]


## Centro do trecho `i` de uma linha que sai de `origin` na direção `dir` (normalizada, no plano).
static func root_point(origin: Vector3, dir: Vector3, i: int) -> Vector3:
	var step := (ROOT_LEN - ROOT_START) / float(ROOT_SEGS - 1)
	return origin + dir * (ROOT_START + step * i)


## Segundos depois do início do golpe em que o trecho `i` irrompe.
static func root_time(i: int) -> float:
	return ROOT_T0 + ROOT_DT * i


## O trecho (0..ROOT_SEGS-1) de uma linha que pega `p`, ou -1 se `p` está fora dela (de lado ou além das pontas).
static func root_segment(origin: Vector3, dir: Vector3, p: Vector3) -> int:
	var v := Vector3(p.x - origin.x, 0.0, p.z - origin.z)
	var along := v.dot(dir)
	if along < ROOT_START - ROOT_HALF or along > ROOT_LEN + ROOT_HALF:
		return -1
	var side := (v - dir * along).length()
	if side > ROOT_HALF:
		return -1
	var step := (ROOT_LEN - ROOT_START) / float(ROOT_SEGS - 1)
	return clampi(roundi((along - ROOT_START) / step), 0, ROOT_SEGS - 1)


## Onde cada broto nasce: em roda, a SPROUT_RING m dela, começando atrás (longe de quem está na frente).
static func sprout_points(center: Vector3, facing: Vector3, n: int = SPROUTS) -> Array:
	var f := Vector3(facing.x, 0.0, facing.z)
	f = f.normalized() if f.length() > 0.001 else Vector3.FORWARD
	var out := []
	for i in n:
		var d := (-f).rotated(Vector3.UP, TAU * i / n)
		out.append(center + d * SPROUT_RING)
	return out


## Vida que `alive` brotos devolvem em `dt` s a quem tem `max_hp`.
static func sprout_heal(max_hp: float, alive: int, dt: float) -> float:
	return max_hp * SPROUT_HEAL * alive * dt


## Pontos das nuvens de esporos sorteados pela semente, até `spread` m em volta de `center` (na altura dele).
static func spore_points(seed: int, center: Vector3, spread: float = SPORE_SPREAD, n: int = SPORES) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out := []
	for i in n:
		var a := rng.randf() * TAU
		var d := lerpf(0.35, 1.0, sqrt(rng.randf())) * spread   # nada colado nela: a garra já cobre ali
		out.append(Vector3(center.x + cos(a) * d, center.y, center.z + sin(a) * d))
	return out


## Raio de uma nuvem de esporos `t` s depois de nascer.
static func spore_radius(t: float) -> float:
	return lerpf(SPORE_R0, SPORE_R1, clampf(t / SPORE_LIFE, 0.0, 1.0))
