class_name KnightAnim
extends RefCounted
## Animação procedural do cavaleiro (knight.glb), compartilhada pelo jogador, pelas réplicas do
## multiplayer, pela prévia 3D do inventário e pelo salão.
##
## Pivôs do modelo: LegX (quadril) > KneeX > AnkleX, Body (pelve) > Head e ArmX (ombro) > ElbowX.
## Convenção de sinais (modelo olhando para +Z):
##   LegX.rotation.x  < 0 = coxa para a frente     KneeX.rotation.x  > 0 = joelho dobra (canela para trás)
##   ArmX.rotation.x  < 0 = braço para a frente    ElbowX.rotation.x < 0 = cotovelo dobra (antebraço sobe)
##   ArmL.rotation.z  > 0 e ArmR.rotation.z < 0 = braço se abre para o lado
##   foot_l/foot_r (pose) = inclinação do pé em relação ao CHÃO; > 0 = ponta para baixo. O tornozelo
##   (AnkleX.rotation.x) é calculado em apply() a partir dela, então o pé fica chato no chão por padrão.
##
## Uma pose é um Dictionary com os alvos de cada articulação (veja rest_pose()); apply() leva o
## modelo até ela suavizando, e mantém o pé de apoio no chão calculando a altura das pernas.

# ------------------------------------------------------------------ parado (idle)
const BREATH_FREQ := 1.9          ## rad/s da respiração (~3,3 s por ciclo)
const BREATH_BODY_Y := 0.01       ## sobe e desce do tronco ao respirar (m)
const BREATH_CHEST := 0.022       ## o peito abre (tronco recua) ao inspirar (rad)
const BREATH_ARM := 0.025         ## os braços se afastam um pouco ao inspirar (rad)
const SWAY_FREQ := 0.42           ## troca de peso entre as pernas (rad/s, ~15 s ida e volta)
const SWAY_HOLD := 1.6            ## >1 faz o peso ficar parado numa perna antes de trocar
const SWAY_SHIFT := 0.016         ## a pelve vai para o lado da perna de apoio (m)
const SWAY_ROLL := 0.035          ## o tronco compensa inclinando para o outro lado (rad)
const IDLE_KNEE_RELAX := 0.16     ## joelho da perna sem peso (rad)
const IDLE_ELBOW := -0.2          ## cotovelos levemente dobrados (rad)
const IDLE_ARM_OUT := 0.06        ## braços um pouco afastados do corpo (rad)
const IDLE_ARM_R_X := -0.15       ## braço da arma um pouco à frente

# ------------------------------------------------------------------ andar / correr
## Ciclo da marcha (por perna): apoio (pé no chão) e balanço (pé no ar). DUTY = fração do ciclo em apoio.
## Caminhada humana ~0,6 (os dois pés no chão um tempo); corrida ~0,35-0,4 (os dois no ar um tempo).
## WALK_SPEED do jogo (5,2 m/s) já é um trote, então o "andar" normal usa o estilo de trote.
const WALK_DUTY := 0.6            ## andando devagar (aceleração, lentidão)
const JOG_DUTY := 0.38            ## na velocidade normal
const RUN_DUTY := 0.31            ## correndo
const JOG_STYLE := 0.72           ## quanto o andar normal já se parece com a corrida (0 caminhada, 1 corrida)
const WALK_AMP := 0.64            ## abertura da coxa na velocidade normal (rad); define o tamanho da passada
const RUN_AMP := 0.8              ## na corrida
const STRIDE_POW := 0.4           ## devagar a passada encolhe menos que a velocidade (evita pezinhos rápidos)
## Joelho (rad, > 0 dobra) ao longo do ciclo. Chaves [x, valor]: no apoio x = 0..1 do apoio (0 = pé toca
## o chão), no balanço x = 0..1 do balanço (0 = ponta do pé sai do chão). Valores de biomecânica:
## caminhada ~5° no contato, ~20° amortecendo, ~40° saindo e ~60° no balanço; corrida ~25° no contato,
## ~45° no meio do apoio e 100°+ no balanço (calcanhar sobe para trás).
const KNEE_WALK_STANCE := [[0.0, 0.08], [0.2, 0.3], [0.55, 0.1]]
const KNEE_WALK_SWING := [[0.0, 0.72], [0.3, 1.12], [0.78, 0.3]]
const KNEE_RUN_STANCE := [[0.0, 0.42], [0.42, 0.8]]
const KNEE_RUN_SWING := [[0.0, 0.6], [0.38, 2.05], [0.74, 0.8], [0.92, 0.45]]
## Pé em relação ao chão no apoio (rad, > 0 = ponta para baixo): calcanhar toca com a ponta para cima,
## pé assenta chato, o calcanhar sobe e a ponta empurra o chão até sair (o corpo sobe junto).
const FOOT_WALK_STANCE := [[0.0, -0.3], [0.14, 0.0], [0.6, 0.0], [1.0, 0.62]]
const FOOT_RUN_STANCE := [[0.0, -0.1], [0.12, 0.0], [0.45, 0.02], [1.0, 1.0]]
## No balanço o pé solta em relação à canela (tornozelo, > 0 = ponta para baixo) e, no fim, se prepara
## para o contato (volta à inclinação do começo do apoio). Andando a ponta sobe (dorsiflexão) para não
## raspar no chão quando o pé passa por baixo do corpo; correndo o calcanhar sobe e o pé fica solto.
const ANKLE_WALK_SWING := -0.28
const ANKLE_RUN_SWING := 0.35
const FOOT_RELEASE := 0.35        ## fração do balanço em que o pé passa da saída para a pose solta
const FOOT_PREPARE := 0.6         ## a partir daqui se prepara para tocar o chão
const FLIGHT_LIFT_JOG := 0.035    ## quanto o corpo sobe na fase de voo (m)
const FLIGHT_LIFT_RUN := 0.07
const ARM_SWING_WALK := 0.5       ## balanço dos braços (rad)
const ARM_SWING_RUN := 0.85
const ARM_LAG := 0.25             ## os braços vêm um pouco depois das pernas (rad de fase)
const ELBOW_WALK := -0.55         ## cotovelo médio no andar normal (trote)
const ELBOW_RUN := -1.25          ## e correndo (braço de corredor)
const ELBOW_SWING := -0.35        ## dobra extra quando o braço vai à frente
const BODY_BOUNCE_WALK := 0.012   ## o tronco amortece no meio de cada apoio (m), além do que as pernas dão
const BODY_BOUNCE_RUN := 0.022
const TORSO_TWIST_WALK := 0.1     ## ombros giram contra o quadril (rad)
const TORSO_TWIST_RUN := 0.15
const HIP_DROP := 0.04            ## o quadril pende para o lado da perna de apoio (rad)
const LEAN_WALK := 0.08           ## inclinação do tronco para a frente andando (rad)
const LEAN_RUN := 0.22            ## e correndo
const LEAN_ACCEL := 0.01          ## por m/s² de aceleração para a frente
const LEAN_MIN := -0.12
const LEAN_MAX := 0.3
const MAX_CADENCE := 26.0         ## limite da fase (rad/s), só para velocidades fora do normal
const MIN_STRIDE := 0.12          ## meio passo mínimo (m) usado no cálculo da cadência
## A pose do ciclo já é suave: a suavização de apply() só serve para as trocas de pose. Aplicada a um
## ciclo de ~3 passos/s ela atrasa e achata o movimento (o joelho dobrava bem menos que o pedido),
## então andando as articulações do ciclo seguem a pose este tanto mais rápido (veja follow_cycle).
const CYCLE_FOLLOW := 8.0
const CYCLE_KEYS := ["leg_l", "leg_r", "knee_l", "knee_r", "foot_l", "foot_r", "body_y", "body_z", "twist",
	"arm_l", "arm_r", "elbow_l", "elbow_r", "lift"]

# ------------------------------------------------------------------ ar e aterrissagem
const AIR_KNEE_RISE := Vector2(0.95, 0.35)   ## joelhos (L, R) recolhidos subindo
const AIR_LEG_RISE := Vector2(-0.65, 0.3)    ## coxas (L, R) subindo
const AIR_KNEE_FALL := Vector2(0.25, 0.3)    ## caindo: pernas se esticam para o chão
const AIR_LEG_FALL := Vector2(-0.2, 0.12)
const AIR_ARM_OUT := 0.3                     ## braços abrem para equilibrar
const AIR_ELBOW := -0.55
const LAND_KNEE := 0.75                      ## agachamento ao aterrissar (rad, no impacto máximo)
const LAND_THIGH := -0.35
const LAND_BODY_X := 0.3
const LAND_BODY_Y := 0.06

# ------------------------------------------------------------------ ataque
## As poses-chave e os tempos de cada golpe ficam em knight_moves.gd (KnightMoves).
const ATK_LEGS_WHILE_MOVING := 0.3   ## quanto do passo de ataque as pernas fazem se o jogador anda
## Atraso de cada articulação na trilha do golpe (fração do golpe): quadril e tronco puxam o
## movimento, o ombro segue, cotovelo e pulso chicoteiam por último (sobreposição de ação).
const JOINT_LAG := {
	"leg_l": -0.02, "leg_r": -0.02, "knee_l": -0.02, "knee_r": -0.02,
	"twist": -0.015, "body_x": -0.012, "body_z": -0.012,
	"elbow_r": 0.008, "elbow_l": 0.008, "wrist_r": 0.014, "wrist_l": 0.014, "head_x": 0.03, "head_y": 0.03,
}
const LEG_KEYS := ["leg_l", "leg_r", "knee_l", "knee_r", "foot_l", "foot_r"]
const POSE_KEYS := ["leg_l", "leg_r", "knee_l", "knee_r", "foot_l", "foot_r", "lift", "body_x", "body_y", "body_z", "body_shift",
	"twist", "head_x", "head_y", "arm_l", "arm_r", "elbow_l", "elbow_r", "wrist_l", "wrist_r", "ground"]


## Pivôs do modelo + medidas das pernas. Funciona com modelos antigos sem KneeX/ElbowX (ficam null).
static func rig(model: Node3D) -> Dictionary:
	var r := {"model": model}
	for n in ["LegL", "LegR", "KneeL", "KneeR", "AnkleL", "AnkleR", "ArmL", "ArmR", "ElbowL", "ElbowR", "Body", "Head"]:
		r[n] = model.find_child(n, true, false)
	r["body_y"] = r.Body.position.y
	r["body_x0"] = r.Body.position.x
	var leg: Node3D = r.LegL
	var knee: Node3D = r.KneeL
	var ankle: Node3D = r.AnkleL
	# pé: altura do tornozelo e o quanto calcanhar e ponta saem dele (pela caixa das malhas do pé)
	r["ankle_h"] = 0.0
	r["heel"] = 0.0
	r["toe"] = 0.0
	if knee and ankle:
		r["thigh"] = maxf(0.05, -knee.position.y)
		r["shin"] = maxf(0.05, -ankle.position.y)
		var box := AABB()
		var first := true
		for c in ankle.get_children():
			if c is MeshInstance3D:
				var b: AABB = c.transform * (c as MeshInstance3D).get_aabb()
				box = b if first else box.merge(b)
				first = false
		if first:
			r.ankle_h = maxf(0.0, leg.position.y + knee.position.y + ankle.position.y)
		else:
			r.ankle_h = maxf(0.0, -box.position.y)
			r.heel = maxf(0.0, -box.position.z)
			r.toe = maxf(0.0, box.end.z)
	elif knee:
		r["thigh"] = maxf(0.05, -knee.position.y)
		r["shin"] = maxf(0.05, leg.position.y + knee.position.y)
	else:
		r["thigh"] = leg.position.y * 0.5
		r["shin"] = leg.position.y * 0.5
	return r


## Comprimento da perna esticada (quadril ao tornozelo).
static func leg_length(r: Dictionary) -> float:
	return r.thigh + r.shin


## Pose neutra (em pé, braços soltos).
static func rest_pose() -> Dictionary:
	return {"leg_l": 0.0, "leg_r": 0.0, "knee_l": 0.0, "knee_r": 0.0, "foot_l": 0.0, "foot_r": 0.0, "lift": 0.0,
		"body_x": 0.0, "body_y": 0.0,
		"body_z": 0.0, "body_shift": 0.0, "twist": 0.0, "head_x": 0.0, "head_y": 0.0, "wrist_l": 0.0, "wrist_r": 0.0,
		"arm_l": Vector3(0, 0, IDLE_ARM_OUT), "arm_r": Vector3(IDLE_ARM_R_X, 0, -IDLE_ARM_OUT),
		"elbow_l": IDLE_ELBOW, "elbow_r": IDLE_ELBOW, "ground": 1.0, "snap": [], "speed": {}}


## Parado: respiração e o peso passando de uma perna para a outra. `t` em segundos.
static func idle_pose(t: float) -> Dictionary:
	var p := rest_pose()
	var b := sin(t * BREATH_FREQ)
	var w := clampf(sin(t * SWAY_FREQ) * SWAY_HOLD, -1.0, 1.0)   # +1 = peso na perna esquerda
	w = w * (1.5 - 0.5 * w * w)   # suaviza as pontas do clamp
	p.body_y = b * BREATH_BODY_Y
	p.body_x = -b * BREATH_CHEST
	p.head_x = b * BREATH_CHEST * 0.6
	p.body_shift = w * SWAY_SHIFT
	p.body_z = w * SWAY_ROLL
	# a perna sem peso solta o joelho e a coxa vem um pouco à frente (o pé fica onde estava)
	p.knee_r = IDLE_KNEE_RELAX * maxf(w, 0.0)
	p.knee_l = IDLE_KNEE_RELAX * maxf(-w, 0.0)
	p.leg_r = -p.knee_r * 0.45
	p.leg_l = -p.knee_l * 0.45
	p.arm_l = Vector3(-0.02 * b, 0, IDLE_ARM_OUT + b * BREATH_ARM + w * 0.02)
	p.arm_r = Vector3(IDLE_ARM_R_X - 0.02 * b, 0, -IDLE_ARM_OUT - b * BREATH_ARM + w * 0.02)
	p.elbow_l = IDLE_ELBOW - b * 0.03
	p.elbow_r = IDLE_ELBOW - b * 0.03
	return p


## Andar/correr na fase `phase` (rad). `move` 0..1 = quanto está andando, `run` 0..1 = quanto corre.
## Perna esquerda: u = fase/TAU; 0..duty = apoio (o pé recua em linha reta, parado no chão), duty..1 = balanço.
## A direita é a mesma meia volta defasada. Se duty < 0,5 sobra uma fase de voo entre os apoios.
static func locomotion_pose(r: Dictionary, phase: float, move: float, run: float) -> Dictionary:
	var p := rest_pose()
	var st := gait_style(move, run)
	var duty := gait_duty(move, run)
	var reach := half_stride(r, move, run)
	var amt := smoothstep(0.0, 0.25, move)   # parando, o ciclo some aos poucos
	var foot_keys := _mix_keys(FOOT_WALK_STANCE, FOOT_RUN_STANCE, st)
	var g := [r, duty, st, reach, amt, foot_keys]
	var foot_off := _stance_foot(g, duty - 0.0001)   # como o pé sai do chão (com a ponta rolando)
	var foot_on := _curve(foot_keys, 0.0)
	var bounce := 0.0
	for side in [["l", 0.0], ["r", PI]]:
		var u := fposmod(phase + float(side[1]), TAU) / TAU
		var d: float      # tornozelo atrás do quadril (m); negativo = à frente
		var knee := gait_knee(u, duty, st) * amt
		var foot: float
		if u < duty:
			# apoio: o pé recua em velocidade constante = parado no chão enquanto o corpo avança
			var s := u / duty
			d = reach * (2.0 * s - 1.0)
			foot = _stance_foot(g, u)
			bounce = maxf(bounce, sin(PI * s))
		else:
			# balanço: volta para a frente (lento na saída e na chegada)
			var w := (u - duty) / (1.0 - duty)
			d = reach * (1.0 - 2.0 * w * w * (3.0 - 2.0 * w))
			# pé: da saída (ponta empurrando) solta em relação à canela e se prepara para o contato
			var shin := thigh_for(r, d, knee) + knee
			var free := shin + lerpf(ANKLE_WALK_SWING, ANKLE_RUN_SWING, st)
			foot = lerpf(foot_off, free, smoothstep(0.0, FOOT_RELEASE, w))
			foot = lerpf(foot, foot_on, smoothstep(FOOT_PREPARE, 1.0, w))
		p["knee_" + side[0]] = knee
		p["leg_" + side[0]] = thigh_for(r, d, knee)
		p["foot_" + side[0]] = foot if u < duty else foot * amt
	# voo: entre a saída de um pé e a chegada do outro o corpo sobe
	var x := fposmod(phase / TAU, 0.5)
	if duty < 0.5 and x > duty:
		p.lift = lerpf(FLIGHT_LIFT_JOG, FLIGHT_LIFT_RUN, run) * sin(PI * (x - duty) / (0.5 - duty)) * amt * st
	# braços ao contrário das pernas do mesmo lado (sl = +1 com a perna esquerda atrás), um pouco atrasados
	var arm_amp := lerpf(ARM_SWING_WALK, ARM_SWING_RUN, run) * move
	var elbow := lerpf(lerpf(-0.3, ELBOW_WALK, minf(st / JOG_STYLE, 1.0)), ELBOW_RUN, run)
	var sl := -cos(phase - ARM_LAG)
	p.arm_l = Vector3(-sl * arm_amp, 0, IDLE_ARM_OUT + 0.05 * run * move)
	p.arm_r = Vector3(IDLE_ARM_R_X * (1.0 - move) + sl * arm_amp * 0.8, 0, -IDLE_ARM_OUT - 0.05 * run * move)
	# cotovelo dobra mais quando o braço vai à frente
	p.elbow_l = lerpf(IDLE_ELBOW, elbow + ELBOW_SWING * maxf(sl, 0.0), move)
	p.elbow_r = lerpf(IDLE_ELBOW, elbow + ELBOW_SWING * maxf(-sl, 0.0), move)
	# o tronco amortece no meio de cada apoio (além do que a altura das pernas já dá)
	p.body_y = -lerpf(BODY_BOUNCE_WALK, BODY_BOUNCE_RUN, run) * move * bounce
	p.twist = lerpf(TORSO_TWIST_WALK, TORSO_TWIST_RUN, run) * move * cos(phase)
	# o quadril pende um pouco sobre a perna de apoio
	p.body_z = -HIP_DROP * move * sin(phase)
	return p


## Inclinação do pé de apoio no ponto u do ciclo. g = [r, duty, estilo, meio passo, amt, chaves do pé].
## Na caminhada (há apoio duplo) o pé de trás rola sobre a ponta: a inclinação sai da conta para a ponta
## ficar na altura em que o outro pé está (ou vai tocar) o chão, em vez de erguer o corpo e deixar o
## outro pé no ar e depois cair de uma vez. Na corrida (sem apoio duplo) a ponta empurra para o voo.
static func _stance_foot(g: Array, u: float) -> float:
	var r: Dictionary = g[0]
	var duty: float = g[1]
	var s := u / duty
	var foot := _curve(g[5], s) * float(g[4])
	var walk := clampf((duty - 0.5) / 0.05, 0.0, 1.0)
	if s <= 0.5 or walk <= 0.0 or r.toe <= 0.0:
		return foot
	var uo := fposmod(u + 0.5, 1.0)
	var w := 1.0
	if uo >= duty:
		# o outro pé ainda está no ar: vai mirando onde ele vai tocar o chão
		w = smoothstep(0.45, 1.0, (uo - duty) / (1.0 - duty))
		uo = 0.0
	var front := _curve(g[5], uo / duty) * float(g[4])
	var a: float = r.ankle_h
	var t: float = r.toe
	var ground := _stance_ankle_h(g, uo) + maxf(a * cos(front) + t * sin(front), a * cos(front) - float(r.heel) * sin(front))
	var rr := sqrt(a * a + t * t)
	var rolled := asin(clampf((ground - _stance_ankle_h(g, u)) / rr, a / rr, 1.0)) - atan2(a, t)
	return lerpf(foot, minf(rolled, 1.1), w * walk * smoothstep(0.5, 0.62, s))


## Do quadril ao tornozelo (vertical) da perna em apoio no ponto u.
static func _stance_ankle_h(g: Array, u: float) -> float:
	var r: Dictionary = g[0]
	var duty: float = g[1]
	var knee := gait_knee(u, duty, g[2]) * float(g[4])
	var th := thigh_for(r, float(g[3]) * (2.0 * u / duty - 1.0), knee)
	return r.thigh * cos(th) + r.shin * cos(th + knee)


## 0 = caminhada, 1 = corrida: o andar normal já é um trote, devagar vira caminhada.
static func gait_style(move: float, run: float) -> float:
	return lerpf(smoothstep(0.3, 0.85, move) * JOG_STYLE, 1.0, run)


## Fração do ciclo com o pé no chão.
static func gait_duty(move: float, run: float) -> float:
	return lerpf(lerpf(WALK_DUTY, JOG_DUTY, smoothstep(0.3, 0.85, move)), RUN_DUTY, run)


## Joelho no ponto u (0..1) do ciclo de uma perna.
static func gait_knee(u: float, duty: float, style: float) -> float:
	var stance := _mix_keys(KNEE_WALK_STANCE, KNEE_RUN_STANCE, style)
	var swing := _mix_keys(KNEE_WALK_SWING, KNEE_RUN_SWING, style)
	if u < duty:
		# o fim do apoio emenda na saída do pé (primeira chave do balanço)
		stance.append([1.0, swing[0][1]])
		return _curve(stance, u / duty)
	swing.append([1.0, stance[0][1]])
	return _curve(swing, (u - duty) / (1.0 - duty))


## Mistura duas listas de chaves [x, v] (caminhada e corrida), amostrando cada uma nos x da outra.
static func _mix_keys(a: Array, b: Array, t: float) -> Array:
	var xs: Array = []
	for k in a + b:
		if not (k[0] in xs):
			xs.append(k[0])
	xs.sort()
	var out: Array = []
	for xv in xs:
		out.append([xv, lerpf(_curve(a, xv), _curve(b, xv), t)])
	return out


## Curva suave (Hermite, tangentes pelos vizinhos) pelas chaves [x, v] com x crescente; fora delas segura.
static func _curve(keys: Array, x: float) -> float:
	var n := keys.size()
	if x <= float(keys[0][0]):
		return keys[0][1]
	if x >= float(keys[n - 1][0]):
		return keys[n - 1][1]
	var i := 0
	while i < n - 2 and x > float(keys[i + 1][0]):
		i += 1
	var x0: float = keys[i][0]
	var x1: float = keys[i + 1][0]
	var v0: float = keys[i][1]
	var v1: float = keys[i + 1][1]
	var h := x1 - x0
	var m0 := (v1 - v0) / h
	if i > 0:
		m0 = (v1 - float(keys[i - 1][1])) / (x1 - float(keys[i - 1][0]))
	var m1 := (v1 - v0) / h
	if i + 2 < n:
		m1 = (float(keys[i + 2][1]) - v0) / (float(keys[i + 2][0]) - x0)
	var t := (x - x0) / h
	var t2 := t * t
	var t3 := t2 * t
	return (2.0 * t3 - 3.0 * t2 + 1.0) * v0 + (t3 - 2.0 * t2 + t) * h * m0 + (-2.0 * t3 + 3.0 * t2) * v1 \
		+ (t3 - t2) * h * m1


## Meio passo (m): quanto o tornozelo vai à frente/atrás do quadril.
static func half_stride(r: Dictionary, move: float, run: float) -> float:
	return leg_length(r) * sin(lerpf(WALK_AMP, RUN_AMP, run) * pow(clampf(move, 0.0, 1.0), STRIDE_POW))


## Ângulo da coxa que põe o tornozelo `d` metros atrás do quadril com o joelho dobrado `knee`.
static func thigh_for(r: Dictionary, d: float, knee: float) -> float:
	var t: float = r.thigh
	var s: float = r.shin
	var reach := sqrt(t * t + s * s + 2.0 * t * s * cos(knee))
	var beta := atan2(s * sin(knee), t + s * cos(knee))
	return asin(clampf(d / reach, -1.0, 1.0)) - beta


## Cadência (rad/s de fase) para o pé de apoio não deslizar: no apoio (fração duty do ciclo) o pé
## percorre a passada inteira (2 * half_stride) enquanto o corpo anda o mesmo tanto.
static func cadence(r: Dictionary, hspeed: float, move: float, run: float) -> float:
	var reach := maxf(half_stride(r, move, run), MIN_STRIDE)
	return minf(hspeed * PI * gait_duty(move, run) / reach, MAX_CADENCE)


## Andando, as articulações do ciclo seguem a pose sem o atraso da suavização. `w` 0..1.
static func follow_cycle(p: Dictionary, w: float) -> void:
	if w <= 0.001:
		return
	var spd: Dictionary = p.speed.duplicate()
	for j in CYCLE_KEYS:
		spd[j] = lerpf(float(spd.get(j, 1.0)), CYCLE_FOLLOW, w)
	p.speed = spd


## No ar: `rise` +1 subindo forte, -1 caindo forte.
static func air_pose(rise: float) -> Dictionary:
	var p := rest_pose()
	var up := maxf(rise, 0.0)
	var t := (rise + 1.0) * 0.5
	p.leg_l = lerpf(AIR_LEG_FALL.x, AIR_LEG_RISE.x, t)
	p.leg_r = lerpf(AIR_LEG_FALL.y, AIR_LEG_RISE.y, t)
	p.knee_l = lerpf(AIR_KNEE_FALL.x, AIR_KNEE_RISE.x, t)
	p.knee_r = lerpf(AIR_KNEE_FALL.y, AIR_KNEE_RISE.y, t)
	# pés soltos, a ponta um pouco para baixo em relação à canela
	p.foot_l = p.leg_l + p.knee_l + 0.3
	p.foot_r = p.leg_r + p.knee_r + 0.3
	p.body_x = -0.12 * up + 0.1 * maxf(-rise, 0.0)
	p.arm_l = Vector3(-0.3 * up, 0, IDLE_ARM_OUT + AIR_ARM_OUT)
	p.arm_r = Vector3(IDLE_ARM_R_X - 0.2 * up, 0, -IDLE_ARM_OUT - AIR_ARM_OUT)
	p.elbow_l = AIR_ELBOW
	p.elbow_r = AIR_ELBOW
	p.ground = 0.0
	return p


## Aterrissagem: `land` 0..1 (já suavizado). Agacha dobrando joelhos e jogando a coxa à frente.
static func add_landing(p: Dictionary, land: float) -> void:
	p.knee_l += LAND_KNEE * land
	p.knee_r += LAND_KNEE * land
	p.leg_l += LAND_THIGH * land
	p.leg_r += LAND_THIGH * land
	p.body_x += LAND_BODY_X * land
	p.body_y -= LAND_BODY_Y * land
	p.elbow_l -= 0.3 * land
	p.elbow_r -= 0.3 * land


## Mistura duas poses (w = 0 só a, 1 só b).
static func blend(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	var p := a.duplicate()
	for key in POSE_KEYS:
		p[key] = lerp(a[key], b[key], w)
	return p


## Toca uma trilha de golpe sobre a pose de locomoção `p`.
## Trilha = [[t, {pose parcial}, curva], ...] com t crescente em 0..1. O começo (t=0) e o fim (t=1)
## são a própria pose de locomoção; uma chave sem certa articulação é atravessada por ela.
## Curva de chegada em cada chave: "in" acelera (golpe), "out" desacelera (follow-through),
## "io" suave (padrão), "lin" constante.
## Braço e tronco vão direto ao alvo (a trilha já é suave); as pernas só fazem o passo de ataque
## inteiro com o jogador parado.
static func play_track(p: Dictionary, track: Array, t: float, move: float) -> void:
	var legs_w := lerpf(1.0, ATK_LEGS_WHILE_MOVING, move)
	var snap: Array = p.snap
	var joints: Array = []
	var keys: Array = []
	for key in track:
		var pose := key_pose(key)
		keys.append([key[0], pose, key[2] if key.size() > 2 else "io"])
		for j in pose:
			if not (j in joints):
				joints.append(j)
	for j in joints:
		var base = p[j]
		var v = sample_track(keys, j, base, clampf(t - float(JOINT_LAG.get(j, 0.0)), 0.0, 1.0))
		if j in LEG_KEYS:
			p[j] = lerp(base, v, legs_w)
		else:
			p[j] = v
			snap.append(j)


## Pose de uma chave: um Dictionary, ou uma lista deles somados (o último manda), para reaproveitar
## poses como KnightMoves.STAFF_AIM.
static func key_pose(key: Array) -> Dictionary:
	if key[1] is Dictionary:
		return key[1]
	var pose := {}
	for part in key[1]:
		pose.merge(part, true)
	return pose


## Valor da articulação `j` na trilha no instante `t` (a pose base nas pontas).
static func sample_track(track: Array, j: String, base, t: float):
	var t0 := 0.0
	var v0 = base
	for key in track:
		if not key[1].has(j):
			continue
		var t1: float = key[0]
		if t <= t1:
			return lerp(v0, key[1][j], ease_curve((t - t0) / maxf(t1 - t0, 0.0001), key[2] if key.size() > 2 else "io"))
		t0 = t1
		v0 = key[1][j]
	return lerp(v0, base, ease_curve((t - t0) / maxf(1.0 - t0, 0.0001), "io"))


static func ease_curve(x: float, kind: String) -> float:
	x = clampf(x, 0.0, 1.0)
	match kind:
		"in":
			return x * x * x
		"out":
			return 1.0 - pow(1.0 - x, 3.0)
		"lin":
			return x
	return x * x * (3.0 - 2.0 * x)


static func sword_pose(p: Dictionary, combo: int, t: float, move: float) -> void:
	play_track(p, KnightMoves.SWORD[clampi(combo, 1, 3) - 1], t, move)
	if combo == 3:
		# giro: uma volta inteira desenrolando o tronco; enrolado em -PI..PI para a recuperação
		# não "desgirar"
		p.twist = wrapf(p.twist + TAU * smoothstep(KnightMoves.SPIN_START, KnightMoves.SPIN_END, t), -PI, PI)
		if not ("twist" in p.snap):
			p.snap.append("twist")


static func staff_pose(p: Dictionary, combo: int, t: float, move: float) -> void:
	play_track(p, KnightMoves.STAFF[clampi(combo, 1, 3) - 1], t, move)


## Magia (`kind` = "fireball", "heal", "frost_nova"); `t` 0..1 dentro de KnightMoves.CAST_TIME.
## Com cajado (`staff`), magias que têm versão própria apontam a gema (KnightMoves.CAST_STAFF).
static func cast_pose(p: Dictionary, kind: String, t: float, move: float, staff := false) -> void:
	var track: Array = KnightMoves.CAST_STAFF[kind] if staff and KnightMoves.CAST_STAFF.has(kind) \
		else KnightMoves.CAST.get(kind, KnightMoves.CAST.fireball)
	play_track(p, track, t, move)


## Arco tensionando: `c` 0..1 (0 = flecha encaixada, 1 = corda no queixo).
static func bow_draw_pose(p: Dictionary, c: float) -> void:
	var a: Dictionary = KnightMoves.BOW_NOCK
	var b: Dictionary = KnightMoves.BOW_FULL
	var e := 1.0 - pow(1.0 - c, 2.0)   # puxa rápido no começo e assenta perto do fim
	for j in b:
		p[j] = lerp(a.get(j, p[j]), b[j], e)
	for j in a:
		if not b.has(j):
			p[j] = a[j]
	# com a corda toda puxada o braço do arco treme de leve
	p.arm_l += Vector3(sin(Time.get_ticks_msec() * 0.031) * KnightMoves.BOW_TREMBLE, 0, 0) * smoothstep(0.9, 1.0, c)
	for j in ["arm_l", "arm_r", "elbow_l", "elbow_r", "twist", "head_y", "wrist_l"]:
		p.speed[j] = KnightMoves.BOW_RAISE_SPEED


## Logo depois de soltar a flecha: `t` 0..1 dentro do tempo de recuperação do arco.
static func bow_release_pose(p: Dictionary, t: float, move: float) -> void:
	play_track(p, KnightMoves.BOW_RELEASE, t, move)


## Flecha do Vendaval. `c` 0..1 = carga: agacha (joelhos até KnightMoves.GALE_KNEE), o tronco inclina para
## trás, a mão da corda puxa além da tensão normal e o arco treme (pulso) cada vez mais. `recoil` 0..1 =
## tempo na recuperação depois do disparo (< 0 = ainda tensionando): tranco para trás e levanta.
static func bow_gale_pose(p: Dictionary, c: float, recoil := -1.0) -> void:
	var crouch := smoothstep(0.0, 1.0, minf(c * 1.6, 1.0))   # agacha logo no começo da tensão
	var lean := crouch
	if recoil < 0.0:
		bow_draw_pose(p, minf(c * 2.5, 1.0))
		# puxa além do normal: a mão da corda vai para trás da orelha
		p.arm_r += Vector3(0.0, -0.3, -0.1) * c
		p.elbow_r -= 0.35 * c
		p.twist -= 0.12 * c
		# o arco treme mais com a carga (dois senos fora de fase: parece ruído)
		var ms := float(Time.get_ticks_msec())
		var n := sin(ms * 0.047) * 0.6 + sin(ms * 0.113 + 1.7) * 0.4
		p.wrist_l += n * KnightMoves.GALE_TREMBLE * c
		p.arm_l += Vector3(sin(ms * 0.061) * 0.3 * KnightMoves.GALE_TREMBLE * c, 0.0, 0.0)
	else:
		bow_release_pose(p, recoil, 0.0)
		var up := smoothstep(0.35, 1.0, recoil)
		crouch *= 1.0 - up
		# tranco do tiro: o tronco joga para trás e volta; o braço do arco pula para cima
		var kick := pow(1.0 - recoil, 2.0)
		lean = lean * (1.0 - up) + kick * KnightMoves.GALE_RECOIL / KnightMoves.GALE_LEAN
		p.arm_l += Vector3(-0.35 * kick, 0.0, 0.0)
	p.body_x += KnightMoves.GALE_LEAN * lean
	p.head_x -= KnightMoves.GALE_LEAN * lean * 0.6   # a cabeça compensa: continua olhando a mira
	# os braços compensam parte da inclinação: a flecha fica quase na horizontal
	p.arm_l += Vector3(-KnightMoves.GALE_LEAN * lean * 0.5, 0.0, 0.0)
	p.arm_r += Vector3(-KnightMoves.GALE_LEAN * lean * 0.5, 0.0, 0.0)
	p.body_y += KnightMoves.GALE_CROUCH_Y * crouch
	p.leg_l = lerpf(p.leg_l, KnightMoves.GALE_THIGH_L, crouch)
	p.leg_r = lerpf(p.leg_r, KnightMoves.GALE_THIGH_R, crouch)
	p.knee_l = lerpf(p.knee_l, KnightMoves.GALE_KNEE, crouch)
	p.knee_r = lerpf(p.knee_r, KnightMoves.GALE_KNEE, crouch)
	p.foot_l = lerpf(p.foot_l, 0.0, crouch)
	p.foot_r = lerpf(p.foot_r, 0.0, crouch)
	p.ground = 1.0


## Chuva de Meteoros: `u` 0..1 = preparo (ergue o cajado com as duas mãos acima da cabeça); `shake` 0..1 =
## o tremor da canalização (braços, pulso e tronco tremem como quem segura um peso enorme no céu).
static func meteor_pose(p: Dictionary, u: float, shake: float) -> void:
	var a: Dictionary = KnightMoves.METEOR_RAISE
	var e := smoothstep(0.0, 1.0, u)
	for j in a:
		p[j] = lerp(p[j], a[j], e)
	if shake > 0.0:
		# dois senos fora de fase por junta: parece ruído
		var ms := float(Time.get_ticks_msec())
		var n1 := sin(ms * 0.051) * 0.6 + sin(ms * 0.137 + 1.3) * 0.4
		var n2 := sin(ms * 0.043 + 2.1) * 0.6 + sin(ms * 0.119 + 0.4) * 0.4
		var tr: float = KnightMoves.METEOR_TREMBLE * shake
		p.arm_r += Vector3(n1 * tr, 0.0, n2 * tr * 0.6)
		p.arm_l += Vector3(n2 * tr, 0.0, -n1 * tr * 0.6)
		p.wrist_r += n1 * tr * 0.8
		p.body_z += n2 * tr * 0.35
		p.body_x += n1 * tr * 0.25
	p.ground = 1.0
	for j in ["arm_l", "arm_r", "elbow_l", "elbow_r", "wrist_r", "twist", "head_x", "body_x"]:
		p.speed[j] = KnightMoves.METEOR_RAISE_SPEED


## Leva o modelo até a pose. `k` = fator de suavização deste quadro (0..1).
## Chaves em p.snap vão direto ao alvo; p.speed[chave] multiplica k só para essa chave.
static func apply(r: Dictionary, p: Dictionary, k: float) -> void:
	var snap: Array = p.get("snap", [])
	var spd: Dictionary = p.get("speed", {})
	var f := func(key: String) -> float:
		return 1.0 if key in snap else minf(1.0, k * float(spd.get(key, 1.0)))
	r.LegL.rotation.x = lerpf(r.LegL.rotation.x, p.leg_l, f.call("leg_l"))
	r.LegR.rotation.x = lerpf(r.LegR.rotation.x, p.leg_r, f.call("leg_r"))
	if r.KneeL:
		r.KneeL.rotation.x = lerpf(r.KneeL.rotation.x, p.knee_l, f.call("knee_l"))
		r.KneeR.rotation.x = lerpf(r.KneeR.rotation.x, p.knee_r, f.call("knee_r"))
	# tornozelo: a pose dá a inclinação do pé em relação ao chão; desconta coxa e joelho
	r["foot_l"] = lerpf(float(r.get("foot_l", 0.0)), p.foot_l, f.call("foot_l"))
	r["foot_r"] = lerpf(float(r.get("foot_r", 0.0)), p.foot_r, f.call("foot_r"))
	if r.AnkleL:
		r.AnkleL.rotation.x = r.foot_l - r.LegL.rotation.x - r.KneeL.rotation.x
		r.AnkleR.rotation.x = r.foot_r - r.LegR.rotation.x - r.KneeR.rotation.x
	var body: Node3D = r.Body
	body.rotation.x = lerpf(body.rotation.x, p.body_x, f.call("body_x"))
	body.rotation.z = lerpf(body.rotation.z, p.body_z, f.call("body_z"))
	body.rotation.y = lerpf(body.rotation.y, p.twist, f.call("twist"))
	body.position.y = lerpf(body.position.y, r.body_y + p.body_y, f.call("body_y"))
	body.position.x = lerpf(body.position.x, r.body_x0 + p.body_shift, f.call("body_shift"))
	r.Head.rotation.x = lerpf(r.Head.rotation.x, p.head_x, f.call("head_x"))
	r.Head.rotation.y = lerpf(r.Head.rotation.y, p.head_y, f.call("head_y"))
	# pulsos: o modelo não tem pivô; o suporte da arma gira com este valor (hold_weapon_upright)
	r["wrist_l"] = lerpf(float(r.get("wrist_l", 0.0)), p.wrist_l, f.call("wrist_l"))
	r["wrist_r"] = lerpf(float(r.get("wrist_r", 0.0)), p.wrist_r, f.call("wrist_r"))
	r.ArmL.rotation = r.ArmL.rotation.lerp(p.arm_l, f.call("arm_l"))
	r.ArmR.rotation = r.ArmR.rotation.lerp(p.arm_r, f.call("arm_r"))
	if r.ElbowL:
		r.ElbowL.rotation.x = lerpf(r.ElbowL.rotation.x, p.elbow_l, f.call("elbow_l"))
		r.ElbowR.rotation.x = lerpf(r.ElbowR.rotation.x, p.elbow_r, f.call("elbow_r"))
	# pé de apoio no chão: o modelo desce o quanto a perna mais comprida (a de apoio) encolheu
	var model: Node3D = r.model
	r["lift"] = lerpf(float(r.get("lift", 0.0)), p.lift, f.call("lift"))
	var target := -ground_drop(r) * float(p.ground) + float(r.lift)
	model.position.y = lerpf(model.position.y, target, minf(1.0, k * 1.5 * float(spd.get("lift", 1.0))))


## Suporte da arma: cajado e arco ficam de pé mesmo com o braço erguido (desfaz ombro + cotovelo
## na medida de KnightLook.COUNTER) e o pulso da pose gira a arma (a lâmina estala no golpe).
## `look` = o que KnightLook.apply devolveu; `r` = rig() já animado por apply().
static func hold_weapon_upright(look: Dictionary, r: Dictionary) -> void:
	var holder: Node3D = look.get("holder")
	var arm: Node3D = look.get("arm")
	if holder == null or not is_instance_valid(holder) or arm == null:
		return
	var bend: float = arm.rotation.x
	var elbow: Node3D = look.get("elbow")
	if elbow and elbow != arm:
		bend += elbow.rotation.x
	var wrist: float = r.get("wrist_l" if arm == r.ArmL else "wrist_r", 0.0)
	holder.rotation.x = -bend * float(look.get("counter", 0.0)) + wrist


## Quanto o quadril está abaixo da altura de pé, pela pose atual das pernas.
## O pé que chega mais baixo (calcanhar ou ponta) é o que está no chão.
static func ground_drop(r: Dictionary) -> float:
	var hl := _leg_height(r, r.LegL, r.KneeL, r.AnkleL)
	var hr := _leg_height(r, r.LegR, r.KneeR, r.AnkleR)
	# pode ser negativo: com o calcanhar erguido a perna fica mais comprida e o corpo sobe
	return leg_length(r) + float(r.ankle_h) - maxf(hl, hr)


## Do quadril ao ponto mais baixo do pé (m).
static func _leg_height(r: Dictionary, leg: Node3D, knee: Node3D, ankle: Node3D) -> float:
	var th := leg.rotation.x
	var kn := knee.rotation.x if knee else 0.0
	var h: float = r.thigh * cos(th) + r.shin * cos(th + kn)
	if ankle:
		var f := th + kn + ankle.rotation.x
		var a: float = r.ankle_h
		h += maxf(a * cos(f) + float(r.toe) * sin(f), a * cos(f) - float(r.heel) * sin(f))
	return h
