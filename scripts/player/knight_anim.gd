class_name KnightAnim
extends RefCounted
## Animação procedural do cavaleiro (knight.glb), compartilhada pelo jogador, pelas réplicas do
## multiplayer, pela prévia 3D do inventário e pelo salão.
##
## Pivôs do modelo: LegX (quadril) > KneeX, Body (pelve) > Head e ArmX (ombro) > ElbowX.
## Convenção de sinais (modelo olhando para +Z):
##   LegX.rotation.x  < 0 = coxa para a frente     KneeX.rotation.x  > 0 = joelho dobra (canela para trás)
##   ArmX.rotation.x  < 0 = braço para a frente    ElbowX.rotation.x < 0 = cotovelo dobra (antebraço sobe)
##   ArmL.rotation.z  > 0 e ArmR.rotation.z < 0 = braço se abre para o lado
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
const WALK_AMP := 0.6             ## abertura da coxa na caminhada (rad); define o tamanho da passada
const RUN_AMP := 0.85             ## na corrida
const KNEE_SWING_WALK := 0.8      ## joelho dobra na perna que está no ar
const KNEE_SWING_RUN := 1.5
const KNEE_SWING_EARLY := 0.7     ## <1 adianta o pico de dobra do joelho na fase aérea
const KNEE_STANCE_WALK := 0.1     ## flexão da perna de apoio (amortece e faz o quique)
const KNEE_STANCE_RUN := 0.38
const ARM_SWING_WALK := 0.4       ## balanço dos braços (rad)
const ARM_SWING_RUN := 0.8
const ELBOW_WALK := -0.32         ## cotovelo médio andando
const ELBOW_RUN := -1.15          ## e correndo (braço de corredor)
const ELBOW_SWING := -0.3         ## dobra extra quando o braço vai à frente
const BODY_BOUNCE_WALK := 0.006   ## quique extra do tronco a cada passo (m), além do que as pernas dão
const BODY_BOUNCE_RUN := 0.028
const TORSO_TWIST_WALK := 0.07    ## ombros giram contra o quadril (rad)
const TORSO_TWIST_RUN := 0.13
const LEAN_WALK := 0.05           ## inclinação do tronco para a frente andando (rad)
const LEAN_RUN := 0.22            ## e correndo
const LEAN_ACCEL := 0.01          ## por m/s² de aceleração para a frente
const LEAN_MIN := -0.12
const LEAN_MAX := 0.3
const STRIDE_FIT := 1.0           ## <1 dá passos mais rápidos; 1 = pé parado no chão durante o apoio
const MAX_CADENCE := 26.0         ## limite da fase (rad/s), só para velocidades fora do normal
const MIN_STRIDE := 0.12          ## passada mínima (m) usada no cálculo da cadência

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
## Fases do golpe, em fração do tempo total: antecipação até ATK_WINDUP, golpe até ATK_STRIKE,
## segura o impacto até ATK_HOLD, depois recupera até o fim.
const ATK_WINDUP := 0.3
const ATK_STRIKE := 0.42
const ATK_HOLD := 0.55
const ATK_FOLLOW := 0.08          ## o golpe passa um pouco do ponto de impacto (fração, durante o hold)
const ATK_LEGS_WHILE_MOVING := 0.3   ## quanto do passo de ataque as pernas fazem se o jogador anda

## Poses-chave dos golpes de espada: [antecipação, impacto]. Chaves ausentes ficam na pose de locomoção.
const SWORD_KEYS := [
	[  # 1: de cima para baixo
		{"arm_r": Vector3(-2.8, 0, -0.2), "elbow_r": -1.25, "body_x": -0.14, "twist": 0.22, "elbow_l": -0.6,
			"leg_l": -0.12, "knee_l": 0.12, "leg_r": 0.12, "knee_r": 0.25},
		{"arm_r": Vector3(0.5, 0, 0.1), "elbow_r": -0.05, "body_x": 0.3, "twist": -0.12, "elbow_l": -0.35,
			"leg_l": -0.5, "knee_l": 0.55, "leg_r": 0.32, "knee_r": 0.35},
	],
	[  # 2: horizontal, da direita para a esquerda
		{"arm_r": Vector3(-1.6, 0, -1.3), "elbow_r": -1.0, "body_x": 0.0, "twist": 0.5, "elbow_l": -0.7,
			"leg_l": -0.1, "knee_l": 0.18, "leg_r": 0.15, "knee_r": 0.3},
		{"arm_r": Vector3(-1.4, 0, 1.0), "elbow_r": -0.1, "body_x": 0.18, "twist": -0.6, "elbow_l": -0.3,
			"leg_l": -0.42, "knee_l": 0.45, "leg_r": 0.3, "knee_r": 0.3},
	],
	[  # 3: giro (o tronco dá uma volta inteira, ver sword_pose)
		{"arm_r": Vector3(-1.5, 0, -0.7), "elbow_r": -0.7, "body_x": 0.12, "elbow_l": -0.8,
			"leg_l": -0.25, "knee_l": 0.5, "leg_r": 0.25, "knee_r": 0.5},
		{"arm_r": Vector3(-1.5, 0, -0.5), "elbow_r": -0.15, "body_x": 0.2, "elbow_l": -0.5,
			"leg_l": -0.3, "knee_l": 0.6, "leg_r": 0.3, "knee_r": 0.6},
	],
]
## Cajado: golpes 1-2 (estocada) e 3 (pancada de cima).
const STAFF_KEYS := [
	[{"arm_r": Vector3(-0.9, 0, -0.3), "elbow_r": -1.0, "body_x": -0.06, "twist": 0.18, "knee_r": 0.2},
		{"arm_r": Vector3(-1.55, 0, 0.15), "elbow_r": -0.08, "body_x": 0.14, "twist": -0.1,
			"leg_l": -0.3, "knee_l": 0.3, "leg_r": 0.2, "knee_r": 0.2}],
	[{"arm_r": Vector3(-2.5, 0, 0.0), "elbow_r": -0.7, "body_x": -0.12, "knee_l": 0.2, "knee_r": 0.2},
		{"arm_r": Vector3(-1.4, 0, 0.0), "elbow_r": -0.05, "body_x": 0.28,
			"leg_l": -0.35, "knee_l": 0.55, "leg_r": 0.3, "knee_r": 0.45}],
]
const LEG_KEYS := ["leg_l", "leg_r", "knee_l", "knee_r"]
const POSE_KEYS := ["leg_l", "leg_r", "knee_l", "knee_r", "body_x", "body_y", "body_z", "body_shift",
	"twist", "head_x", "arm_l", "arm_r", "elbow_l", "elbow_r", "ground"]


## Pivôs do modelo + medidas das pernas. Funciona com modelos antigos sem KneeX/ElbowX (ficam null).
static func rig(model: Node3D) -> Dictionary:
	var r := {"model": model}
	for n in ["LegL", "LegR", "KneeL", "KneeR", "ArmL", "ArmR", "ElbowL", "ElbowR", "Body", "Head"]:
		r[n] = model.find_child(n, true, false)
	r["body_y"] = r.Body.position.y
	r["body_x0"] = r.Body.position.x
	var leg: Node3D = r.LegL
	var knee: Node3D = r.KneeL
	if knee:
		r["thigh"] = maxf(0.05, -knee.position.y)
		r["shin"] = maxf(0.05, leg.position.y + knee.position.y)
	else:
		r["thigh"] = leg.position.y * 0.5
		r["shin"] = leg.position.y * 0.5
	return r


## Comprimento da perna esticada (quadril ao chão).
static func leg_length(r: Dictionary) -> float:
	return r.thigh + r.shin


## Pose neutra (em pé, braços soltos).
static func rest_pose() -> Dictionary:
	return {"leg_l": 0.0, "leg_r": 0.0, "knee_l": 0.0, "knee_r": 0.0, "body_x": 0.0, "body_y": 0.0,
		"body_z": 0.0, "body_shift": 0.0, "twist": 0.0, "head_x": 0.0,
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
## Perna esquerda: fase 0..PI = apoio (pé da frente para trás, em linha reta), PI..TAU = no ar.
## A direita é a mesma meia volta defasada.
static func locomotion_pose(r: Dictionary, phase: float, move: float, run: float) -> Dictionary:
	var p := rest_pose()
	var reach := half_stride(r, move, run)
	# o joelho no ar cai mais devagar que a passada: passos curtos ainda tiram o pé do chão
	var knee_swing := lerpf(KNEE_SWING_WALK, KNEE_SWING_RUN, run) * sqrt(move)
	var knee_stance := lerpf(KNEE_STANCE_WALK, KNEE_STANCE_RUN, run) * move
	var arm_amp := lerpf(ARM_SWING_WALK, ARM_SWING_RUN, run) * move
	var elbow := lerpf(ELBOW_WALK, ELBOW_RUN, run)
	for side in [["l", 0.0], ["r", PI]]:
		var u := fposmod(phase + float(side[1]), TAU) / TAU
		var d: float      # pé atrás do quadril (m); negativo = à frente
		var knee: float
		if u < 0.5:
			# apoio: o pé recua em velocidade constante = parado no chão enquanto o corpo avança
			var s := u * 2.0
			d = reach * (2.0 * s - 1.0)
			knee = knee_stance * sin(PI * s)
		else:
			# no ar: volta para a frente com o joelho dobrando logo depois de sair do chão
			var s := (u - 0.5) * 2.0
			d = reach * (1.0 - 2.0 * s * s * (3.0 - 2.0 * s))
			knee = knee_swing * sin(PI * pow(s, KNEE_SWING_EARLY))
		p["knee_" + side[0]] = knee
		p["leg_" + side[0]] = thigh_for(r, d, knee)
	# braços ao contrário das pernas do mesmo lado (sl = +1 com a perna esquerda atrás)
	var sl := -cos(phase)
	p.arm_l = Vector3(-sl * arm_amp, 0, IDLE_ARM_OUT + 0.05 * run * move)
	p.arm_r = Vector3(IDLE_ARM_R_X * (1.0 - move) + sl * arm_amp * 0.8, 0, -IDLE_ARM_OUT - 0.05 * run * move)
	# cotovelo dobra mais quando o braço vai à frente
	p.elbow_l = lerpf(IDLE_ELBOW, elbow + ELBOW_SWING * maxf(sl, 0.0), move)
	p.elbow_r = lerpf(IDLE_ELBOW, elbow + ELBOW_SWING * maxf(-sl, 0.0), move)
	# quique: o tronco desce no meio de cada apoio (além do que a altura das pernas já dá)
	var step := maxf(0.0, -cos(2.0 * phase))
	p.body_y = -lerpf(BODY_BOUNCE_WALK, BODY_BOUNCE_RUN, run) * move * step
	p.twist = -lerpf(TORSO_TWIST_WALK, TORSO_TWIST_RUN, run) * move * sl
	# o quadril pende um pouco sobre a perna de apoio
	p.body_z = -0.03 * move * sin(phase)
	return p


## Meio passo (m): quanto o pé vai à frente/atrás do quadril.
static func half_stride(r: Dictionary, move: float, run: float) -> float:
	return leg_length(r) * sin(lerpf(WALK_AMP, RUN_AMP, run) * move)


## Ângulo da coxa que põe o tornozelo `d` metros atrás do quadril com o joelho dobrado `knee`.
static func thigh_for(r: Dictionary, d: float, knee: float) -> float:
	var t: float = r.thigh
	var s: float = r.shin
	var reach := sqrt(t * t + s * s + 2.0 * t * s * cos(knee))
	var beta := atan2(s * sin(knee), t + s * cos(knee))
	return asin(clampf(d / reach, -1.0, 1.0)) - beta


## Cadência (rad/s de fase) para o pé de apoio não deslizar: no apoio (meia volta) o pé percorre
## a passada inteira (2 * half_stride) enquanto o corpo anda o mesmo tanto.
static func cadence(r: Dictionary, hspeed: float, move: float, run: float) -> float:
	var stride := maxf(2.0 * half_stride(r, move, run), MIN_STRIDE)
	return minf(hspeed * PI / (stride * STRIDE_FIT), MAX_CADENCE)


## No ar: `rise` +1 subindo forte, -1 caindo forte.
static func air_pose(rise: float) -> Dictionary:
	var p := rest_pose()
	var up := maxf(rise, 0.0)
	var t := (rise + 1.0) * 0.5
	p.leg_l = lerpf(AIR_LEG_FALL.x, AIR_LEG_RISE.x, t)
	p.leg_r = lerpf(AIR_LEG_FALL.y, AIR_LEG_RISE.y, t)
	p.knee_l = lerpf(AIR_KNEE_FALL.x, AIR_KNEE_RISE.x, t)
	p.knee_r = lerpf(AIR_KNEE_FALL.y, AIR_KNEE_RISE.y, t)
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


## Valor de uma articulação no golpe: locomoção -> antecipação -> impacto (passa um pouco) -> locomoção.
static func attack_value(base, wind, hit, t: float):
	if t < ATK_WINDUP:
		var x := t / ATK_WINDUP
		return lerp(base, wind, x * x * (3.0 - 2.0 * x))
	if t < ATK_STRIKE:
		var x := (t - ATK_WINDUP) / (ATK_STRIKE - ATK_WINDUP)
		return lerp(wind, hit, x * x)   # acelera até o impacto: o peso está no fim do golpe
	var over = hit + (hit - wind) * ATK_FOLLOW
	if t < ATK_HOLD:
		var x := (t - ATK_STRIKE) / (ATK_HOLD - ATK_STRIKE)
		return lerp(hit, over, sin(x * PI * 0.5))
	var x := clampf((t - ATK_HOLD) / (1.0 - ATK_HOLD), 0.0, 1.0)
	return lerp(over, base, x * x * (3.0 - 2.0 * x))   # recuperação


## Aplica um golpe sobre a pose de locomoção `p`. `keys` = [antecipação, impacto]; `t` 0..1; `move` 0..1.
## As articulações do golpe vão direto ao alvo (a curva já é suave); as pernas só fazem parte do
## passo de ataque se o jogador estiver andando.
static func add_attack(p: Dictionary, keys: Array, t: float, move: float) -> void:
	t = clampf(t, 0.0, 1.0)
	var wind: Dictionary = keys[0]
	var hit: Dictionary = keys[1]
	var legs_w := lerpf(1.0, ATK_LEGS_WHILE_MOVING, move)
	var snap: Array = p.snap
	var all := wind.keys()
	for key in hit:
		if not (key in all):
			all.append(key)
	for key in all:
		var base = p[key]
		var v = attack_value(base, wind.get(key, base), hit.get(key, base), t)
		if key in LEG_KEYS:
			p[key] = lerp(base, v, legs_w)
		else:
			p[key] = v
			snap.append(key)


static func sword_pose(p: Dictionary, combo: int, t: float, move: float) -> void:
	add_attack(p, SWORD_KEYS[clampi(combo, 1, 3) - 1], t, move)
	if combo == 3:
		# uma volta inteira; enrolado em -PI..PI para a recuperação não "desgirar" o tronco
		p.twist = wrapf(-TAU * smoothstep(0.2, 0.75, t), -PI, PI)
		p.snap.append("twist")


static func staff_pose(p: Dictionary, combo: int, t: float, move: float) -> void:
	add_attack(p, STAFF_KEYS[0 if combo < 3 else 1], t, move)


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
	var body: Node3D = r.Body
	body.rotation.x = lerpf(body.rotation.x, p.body_x, f.call("body_x"))
	body.rotation.z = lerpf(body.rotation.z, p.body_z, f.call("body_z"))
	body.rotation.y = lerpf(body.rotation.y, p.twist, f.call("twist"))
	body.position.y = lerpf(body.position.y, r.body_y + p.body_y, f.call("body_y"))
	body.position.x = lerpf(body.position.x, r.body_x0 + p.body_shift, f.call("body_shift"))
	r.Head.rotation.x = lerpf(r.Head.rotation.x, p.head_x, f.call("head_x"))
	r.ArmL.rotation = r.ArmL.rotation.lerp(p.arm_l, f.call("arm_l"))
	r.ArmR.rotation = r.ArmR.rotation.lerp(p.arm_r, f.call("arm_r"))
	if r.ElbowL:
		r.ElbowL.rotation.x = lerpf(r.ElbowL.rotation.x, p.elbow_l, f.call("elbow_l"))
		r.ElbowR.rotation.x = lerpf(r.ElbowR.rotation.x, p.elbow_r, f.call("elbow_r"))
	# pé de apoio no chão: o modelo desce o quanto a perna mais comprida (a de apoio) encolheu
	var model: Node3D = r.model
	var target := -ground_drop(r) * float(p.ground)
	model.position.y = lerpf(model.position.y, target, minf(1.0, k * 1.5))


## Cajado e arco ficam de pé mesmo com o braço erguido: o suporte desfaz ombro + cotovelo.
## `look` = o que KnightLook.apply devolveu.
static func hold_weapon_upright(look: Dictionary) -> void:
	var holder: Node3D = look.get("holder")
	var arm: Node3D = look.get("arm")
	if holder == null or not is_instance_valid(holder) or arm == null:
		return
	var bend: float = arm.rotation.x
	var elbow: Node3D = look.get("elbow")
	if elbow and elbow != arm:
		bend += elbow.rotation.x
	holder.rotation.x = -bend * float(look.get("counter", 0.0))


## Quanto o quadril está abaixo da altura de pé, pela pose atual das pernas.
static func ground_drop(r: Dictionary) -> float:
	var kl: float = r.KneeL.rotation.x if r.KneeL else 0.0
	var kr: float = r.KneeR.rotation.x if r.KneeR else 0.0
	var hl := _leg_height(r, r.LegL.rotation.x, kl)
	var hr := _leg_height(r, r.LegR.rotation.x, kr)
	return maxf(0.0, leg_length(r) - maxf(hl, hr))


static func _leg_height(r: Dictionary, thigh: float, knee: float) -> float:
	return r.thigh * cos(thigh) + r.shin * cos(thigh + knee)
