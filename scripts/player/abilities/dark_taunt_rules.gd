class_name DarkTauntRules
extends RefCounted
## Círculo da Provocação Sombria: contas puras (sem nó nem autoload), para os testes unitários: quem está dentro
## do círculo (uma vez por ativação), onde cada mão sai do chão, o tempo do clipe do herói e os tempos de
## imobilização e provocação de cada inimigo.

## As mãos levam este tempo (s) para se esticar até o alvo e fechar os dedos, depois de sair do chão.
const REACH_TIME := 0.3
## Distância (m) entre o ponto onde a mão sai do chão e o centro do inimigo agarrado (x tamanho da mão).
const HAND_GAP := 0.8
## Distância mínima entre duas mãos (m): não saem todas do mesmo lugar.
const HAND_MIN_GAP := 1.1

## Clipe do herói (KnightMoves.TAUNT_CAST, medido no "Sword And Shield Power Up" do Mixamo): até CLIP_HOLD_FROM
## ele recolhe e explode a energia em tempo real; segura a pose até as mãos agarrarem; depois volta à guarda
## (trecho CLIP_RETURN_FROM..CLIP_END do clipe, comprimido em `ret_time`).
const CLIP_HOLD_FROM := 0.8
const CLIP_RETURN_FROM := 1.6
const CLIP_END := 2.36


## O inimigo (centro `pos`, raio `er`) está dentro do círculo de raio `radius` centrado em `center`? Distância no
## chão (a altura não importa: um voador baixo sobre o círculo também é agarrado), o corpo encostando na borda.
static func in_radius(center: Vector3, pos: Vector3, radius: float, er := 0.0) -> bool:
	return Vector2(pos.x - center.x, pos.z - center.z).length() <= radius + er


## Alvos de uma ativação: só os ainda não agarrados (`taken`, ids de instância), dentro do raio, do mais perto
## para o mais longe. Marca os escolhidos em `taken` (cada um é capturado uma vez só). `targets` = [{id, pos, radius}].
static func pick_targets(targets: Array, center: Vector3, radius: float, taken: Dictionary) -> Array:
	var out := []
	for t in targets:
		if taken.has(t.id):
			continue
		if not in_radius(center, t.pos, radius, float(t.get("radius", 0.0))):
			continue
		taken[t.id] = true
		out.append(t)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return Vector2(a.pos.x - center.x, a.pos.z - center.z).length() < Vector2(b.pos.x - center.x, b.pos.z - center.z).length())
	return out


## Onde cada mão sai do chão (deslocamentos x, z em m a partir do centro), `count` no total:
##   - uma por alvo (`targets` = deslocamentos dos inimigos agarrados), a HAND_GAP x `size` dele, para o lado de
##     dentro do círculo e girada por um desvio sorteado (as mãos vêm de direções diferentes);
##   - as que sobram (sem alvo) espalhadas pelo disco em espiral (ângulo de ouro), longe das outras.
## Tudo dentro do raio. Mesma `seed` = mesmas mãos (o dono e as réplicas veem o mesmo). Cada item:
## {"pos": Vector2, "target": índice em `targets` ou -1}.
static func hand_spots(targets: Array, count: int, radius: float, size: float, seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out := []
	var lim := maxf(radius - 0.3, 0.2)
	for i in targets.size():
		var o: Vector2 = targets[i]
		var inward := (-o).normalized() if o.length() > 0.05 else Vector2.from_angle(rng.randf() * TAU)
		var dir := inward.rotated(rng.randf_range(-1.1, 1.1))
		var p := o + dir * HAND_GAP * size
		if p.length() > lim:
			p = p.normalized() * lim
		out.append({"pos": p, "target": i})
	var extra := maxi(count - targets.size(), 0)
	var golden := PI * (3.0 - sqrt(5.0))
	var a0 := rng.randf() * TAU
	var k := 0
	var tries := 0
	while extra > 0 and tries < 200:
		tries += 1
		k += 1
		# espiral de Vogel: preenche o disco por igual; o miolo fica para o herói
		var u := fmod(float(k) * 0.618034 + rng.randf() * 0.1, 1.0)
		var d := lerpf(0.32, 0.92, sqrt(u)) * lim
		var p := Vector2.from_angle(a0 + golden * k) * d
		var ok := true
		for h in out:
			if (h.pos as Vector2).distance_to(p) < HAND_MIN_GAP * size:
				ok = false
				break
		if not ok and tries < 150:
			continue
		out.append({"pos": p, "target": -1})
		extra -= 1
	return out


## Tempo no clipe do herói `t` s depois do começo da habilidade. `hold_end` = quando as mãos agarram (o herói
## segura a pose de energia solta até lá); depois volta à guarda em `ret_time` s.
static func clip_time(t: float, hold_end: float, ret_time: float) -> float:
	if t <= CLIP_HOLD_FROM:
		return maxf(t, 0.0)
	if t <= hold_end:
		# segura: anda devagar pelo trecho parado do clipe (respira, sem congelar)
		var u := (t - CLIP_HOLD_FROM) / maxf(hold_end - CLIP_HOLD_FROM, 0.001)
		return lerpf(CLIP_HOLD_FROM, CLIP_RETURN_FROM, clampf(u, 0.0, 1.0))
	var r := (t - hold_end) / maxf(ret_time, 0.001)
	return lerpf(CLIP_RETURN_FROM, CLIP_END, clampf(r, 0.0, 1.0))


## Imobilização e provocação (s) que um inimigo recebe: Vector2(segurado, provocado no total). O total começa na
## captura (a provocação já vale enquanto as mãos seguram e dura `taunt` s depois). Chefes não ficam presos (como
## no atordoamento), só são provocados. Valores negativos ou não finitos viram 0.
static func taunt_times(hold: float, taunt: float, boss: bool) -> Vector2:
	hold = hold if is_finite(hold) else 0.0
	taunt = taunt if is_finite(taunt) else 0.0
	hold = maxf(hold, 0.0)
	taunt = maxf(taunt, 0.0)
	if taunt <= 0.0:
		return Vector2(0.0 if boss else hold, 0.0)
	return Vector2(0.0 if boss else hold, hold + taunt)


## O alvo da provocação ainda vale? (vivo, no mesmo mundo, fora da vila). Quando não vale, o inimigo volta a
## escolher pelo mais próximo de sempre.
static func taunter_ok(alive: bool, same_world: bool, in_village: bool, in_arena: bool) -> bool:
	return alive and same_world and not in_village and in_arena
