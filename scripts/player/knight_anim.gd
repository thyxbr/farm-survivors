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
const SIT_LEAN := 0.22            ## sentado: tronco curvado para a frente (rad)

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
const PELVIS_TWIST_WALK := 0.07   ## o quadril gira contra os ombros (rad); as pernas desfazem o giro (leg_yaw)
const PELVIS_TWIST_RUN := 0.12
const HEAD_STEADY := 0.85         ## quanto a cabeça desfaz do giro e da inclinação do tronco (0..1): olha para a frente
const TORSO_LAG := 0.2            ## os ombros giram um pouco depois do quadril (rad de fase)
const HIP_DROP := 0.04            ## o quadril pende para o lado da perna de apoio (rad)
const WEIGHT_SHIFT_WALK := 0.012  ## a pelve vai para o lado da perna de apoio (m)
const WEIGHT_SHIFT_RUN := 0.006
const FOREARM_LAG := 0.35         ## o antebraço chega depois do braço (rad de fase)
const ARM_CROSS_WALK := 0.08      ## o braço que vai à frente fecha para dentro do corpo (rad)
const ARM_CROSS_RUN := 0.14
const LEAN_WALK := 0.19           ## inclinação do corpo para a frente na velocidade normal (rad, ~11°)
const LEAN_RUN := 0.3             ## e correndo (~17°)
const LEAN_PULSE := 0.04          ## a cada passada o tronco mergulha este tanto ao amortecer e volta no impulso (rad)
const HEAD_LEAN := 0.6            ## quanto da inclinação a cabeça desfaz (continua olhando para a frente)
## Inclinado, o corpo vai à frente dos pés: o apoio inteiro recua esta fração de perna * sen(inclinação). O pé
## pousa mais embaixo do corpo e empurra mais atrás, como numa corrida, em vez de bater lá na frente.
const STANCE_BACK := 0.3
const LEAN_ACCEL := 0.01          ## inclinação extra por m/s² de aceleração para a frente (soma em player.gd)
const LEAN_MIN := -0.12           ## limites dessa parte da aceleração (freando / arrancando)
const LEAN_ACCEL_MAX := 0.1
const MAX_CADENCE := 26.0         ## limite da fase (rad/s), só para velocidades fora do normal
const MIN_STRIDE := 0.12          ## meio passo mínimo (m) usado no cálculo da cadência
## A pose do ciclo já é suave: a suavização de apply() só serve para as trocas de pose. Aplicada a um
## ciclo de ~3 passos/s ela atrasa e achata o movimento (o joelho dobrava bem menos que o pedido),
## então andando as articulações do ciclo seguem a pose este tanto mais rápido (veja follow_cycle).
const CYCLE_FOLLOW := 8.0
const CYCLE_KEYS := ["leg_l", "leg_r", "knee_l", "knee_r", "foot_l", "foot_r", "body_y", "body_z", "twist",
	"arm_l", "arm_r", "elbow_l", "elbow_r", "lift", "hip_twist", "leg_yaw", "head_y", "head_z", "body_shift"]

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
## Quanto do giro dos ombros nos golpes o quadril faz junto (o resto é o tronco torcendo).
const HIP_TWIST_SHARE := 0.45
## Esquiva = rolamento para a frente: o quadril dá uma volta inteira (pivô Pelvis) com o corpo encolhido.
## Fases em fração da esquiva: mergulho até ROLL_TUCK_IN (encolhe e inclina), volta até ROLL_SPIN_END, e
## levanta agachado até o fim.
const ROLL_TUCK_IN := 0.2
const ROLL_SPIN_END := 0.8
const ROLL_TUCK := {
	"body_x": 0.75, "head_x": 0.7, "leg_l": -1.75, "leg_r": -1.55, "knee_l": 2.3, "knee_r": 2.2,
	"arm_l": Vector3(-0.9, 0.0, 0.25), "arm_r": Vector3(-0.7, 0.0, -0.25), "elbow_l": -1.7, "elbow_r": -1.4,
	"twist": 0.0, "hip_twist": 0.0, "leg_yaw": 0.0, "body_y": 0.0, "body_z": 0.0, "body_shift": 0.0,
	"head_y": 0.0, "head_z": 0.0,
}
## Rolando, a arma aponta para trás e um pouco para cima (ângulo em torno do eixo X do modelo; 0 = para a
## frente, > 0 inclina para baixo): assim a lâmina, o cajado ou o arco não varrem o chão.
const ROLL_WEAPON_PITCH := PI + 0.45
## Pontos que encostam no chão ao rolar: [pivô, deslocamento no espaço do pivô, raio do corpo ali (m)].
## A altura do modelo é a que deixa o mais baixo deles tocando o chão.
const ROLL_CONTACTS := [
	["Pelvis", Vector3(0, 0, -0.04), 0.15], ["Pelvis", Vector3(0, -0.24, -0.12), 0.04],
	["Pelvis", Vector3(0, -0.24, 0.12), 0.04], ["Body", Vector3(0, 0.28, -0.03), 0.17],
	["Body", Vector3(0, 0.46, 0.0), 0.14], ["Head", Vector3(0, 0.2, 0.0), 0.2],
	["KneeL", Vector3.ZERO, 0.08], ["KneeR", Vector3.ZERO, 0.08], ["ElbowL", Vector3.ZERO, 0.06],
	["ElbowR", Vector3.ZERO, 0.06], ["ElbowL", Vector3(0, -0.26, 0.02), 0.07], ["ElbowR", Vector3(0, -0.26, 0.02), 0.07],
]  # os pés (calcanhar e ponta, pelas medidas de rig()) entram em roll_floor()
## Morto, deitado de costas: altura do quadril acima do chão (m).
const DEATH_LIE_Y := 0.16
## e a inclinação do suporte da arma (a lâmina deita ao lado do corpo).
const DEATH_WEAPON_X := 1.5
## Dobra máxima do cotovelo no IK dos braços (rad; < 0 dobra).
const ARM_IK_MAX_BEND := -2.5
const LEG_KEYS := ["leg_l", "leg_r", "knee_l", "knee_r", "foot_l", "foot_r"]
const POSE_KEYS := ["leg_l", "leg_r", "knee_l", "knee_r", "foot_l", "foot_r", "lift", "body_x", "body_y", "body_z", "body_shift",
	"twist", "hip_twist", "leg_yaw", "roll", "head_x", "head_y", "head_z", "arm_l", "arm_r", "elbow_l", "elbow_r", "wrist_l", "wrist_r", "ground"]


## Pivôs do modelo + medidas das pernas. Funciona com modelos antigos sem KneeX/ElbowX (ficam null).
static func rig(model: Node3D) -> Dictionary:
	var r := {"model": model}
	for n in ["LegL", "LegR", "KneeL", "KneeR", "AnkleL", "AnkleR", "ArmL", "ArmR", "ElbowL", "ElbowR", "Body", "Head"]:
		r[n] = model.find_child(n, true, false)
	r["Pelvis"] = _ensure_pelvis(r)
	r["body_y"] = r.Body.position.y
	r["body_x0"] = r.Body.position.x
	r["twist"] = 0.0
	r["hip_twist"] = 0.0
	r["pelvis_pos0"] = r.Pelvis.position if r.Pelvis else Vector3.ZERO
	var leg: Node3D = r.LegL
	# altura do quadril no modelo (a perna fica dentro do Pelvis, na mesma altura dele)
	var hip_y: float = leg.position.y + (r.Pelvis.position.y if r.Pelvis and leg.get_parent() == r.Pelvis else 0.0)
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
			r.ankle_h = maxf(0.0, hip_y + knee.position.y + ankle.position.y)
		else:
			r.ankle_h = maxf(0.0, -box.position.y)
			r.heel = maxf(0.0, -box.position.z)
			r.toe = maxf(0.0, box.end.z)
	elif knee:
		r["thigh"] = maxf(0.05, -knee.position.y)
		r["shin"] = maxf(0.05, hip_y + knee.position.y)
	else:
		r["thigh"] = hip_y * 0.5
		r["shin"] = hip_y * 0.5
	# mãos: centro de cada mão no espaço do antebraço (alvo do IK dos braços) e o alcance do braço esticado
	for side in ["l", "r"]:
		var elbow: Node3D = r["Elbow" + side.to_upper()]
		var arm: Node3D = r["Arm" + side.to_upper()]
		if elbow and arm:
			var hand := KnightLook._point_in(model, elbow, "Arm%s_Hand" % side.to_upper())
			r["hand_" + side] = hand
			r["reach_" + side] = (elbow.position + hand).length()
	r["aim_pitch"] = 0.0     # inclinação da mira (rad, > 0 para cima); o jogador local atualiza ao mirar
	r["bow_w"] = 0.0         # quanto o IK do arco manda nos braços agora (suavizado em apply)
	r["two_hand"] = 0.0      # quanto a mão esquerda segura o cajado junto (suavizado em apply)
	# rabo de cavalo (corpo feminino, knight_f.glb): balança atrasado em relação à cabeça (veja sway_ponytail)
	var tail := model.find_child("Ponytail", true, false) as Node3D
	r["Ponytail"] = tail
	if tail:
		r["tail_basis"] = tail.basis
		r["tail_ang"] = Vector2.ZERO     # (para trás, para o lado) em rad
		r["tail_vel"] = Vector2.ZERO
		r["tail_prev"] = null
	return r


# ------------------------------------------------------------------ rabo de cavalo
const TAIL_LAG := 0.045       ## rad por m/s da ponta: quanto o rabo fica para trás com o movimento
const TAIL_STIFF := 70.0      ## mola que puxa o rabo para o alvo
const TAIL_DAMP := 9.0        ## amortecimento (um pouco abaixo do crítico: balança uma vez e assenta)
const TAIL_BACK := Vector2(-0.08, 0.6)   ## limites para a frente (encosta nas costas) e para trás (rad)
const TAIL_SIDE := 0.35       ## limite para cada lado (rad)


## Balança o rabo de cavalo como um pêndulo amortecido: a ponta (estimada abaixo e atrás do prendedor) fica
## para trás quando a cabeça anda, gira ou desce. Sem rabo (corpo masculino) não faz nada.
static func sway_ponytail(r: Dictionary, delta: float) -> void:
	var tail: Node3D = r.get("Ponytail")
	if tail == null or delta <= 0.0 or not tail.is_inside_tree():
		return
	var head := tail.get_parent() as Node3D
	var hx := head.global_transform
	var tip := hx * (tail.position + Vector3(0.0, -0.2, -0.08))
	var prev = r.tail_prev
	r.tail_prev = tip
	var target := Vector2.ZERO
	if prev != null:
		var v: Vector3 = hx.basis.inverse() * ((tip - prev) / delta)
		if v.length() > 25.0:   # teleporte ou troca de modelo: sem tranco
			v = Vector3.ZERO
		target = Vector2(clampf((v.z - v.y * 0.6) * TAIL_LAG, TAIL_BACK.x, TAIL_BACK.y),
			clampf(-v.x * TAIL_LAG, -TAIL_SIDE, TAIL_SIDE))
	var ang: Vector2 = r.tail_ang
	var vel: Vector2 = r.tail_vel
	vel += (TAIL_STIFF * (target - ang) - TAIL_DAMP * vel) * delta
	ang += vel * delta
	ang = Vector2(clampf(ang.x, TAIL_BACK.x, TAIL_BACK.y), clampf(ang.y, -TAIL_SIDE, TAIL_SIDE))
	r.tail_ang = ang
	r.tail_vel = vel
	tail.basis = Basis.from_euler(Vector3(ang.x, 0.0, ang.y)) * (r.tail_basis as Basis)


## O knight.glb tem pernas e tronco (Body) como irmãos: girar ou deitar o Body mexia só a parte de cima
## e as pernas ficavam paradas. Cria um pivô de quadril (Pelvis) na altura da pelve, pai de Body, LegL e
## LegR, para o corpo inteiro girar e cair junto. Feito aqui (e não no GLB) para valer em todo modelo com
## esses pivôs; as roupas com esqueleto seguem os pivôs pela posição global (PivotSkin), então não mudam.
static func _ensure_pelvis(r: Dictionary) -> Node3D:
	var body: Node3D = r.Body
	if body == null or r.LegL == null or r.LegR == null:
		return null
	var par := body.get_parent() as Node3D
	if par.name == "Pelvis":
		return par
	if r.LegL.get_parent() != par or r.LegR.get_parent() != par:
		return null
	var pelvis := Node3D.new()
	pelvis.name = "Pelvis"
	par.add_child(pelvis)
	par.move_child(pelvis, body.get_index())
	pelvis.owner = body.owner    # os pivôs continuam com o mesmo dono (a raiz do GLB)
	pelvis.position = body.position
	for n: Node3D in [body, r.LegL, r.LegR]:
		var xf := n.transform
		var own := n.owner
		n.owner = null
		par.remove_child(n)
		pelvis.add_child(n)
		n.owner = own
		n.transform = Transform3D(xf.basis, xf.origin - pelvis.position)
	return pelvis


## Comprimento da perna esticada (quadril ao tornozelo).
static func leg_length(r: Dictionary) -> float:
	return r.thigh + r.shin


## Pose neutra (em pé, braços soltos).
static func rest_pose() -> Dictionary:
	return {"leg_l": 0.0, "leg_r": 0.0, "knee_l": 0.0, "knee_r": 0.0, "foot_l": 0.0, "foot_r": 0.0, "lift": 0.0,
		"body_x": 0.0, "body_y": 0.0,
		"body_z": 0.0, "body_shift": 0.0, "twist": 0.0, "hip_twist": 0.0, "leg_yaw": 0.0, "roll": 0.0, "head_x": 0.0, "head_y": 0.0, "head_z": 0.0, "wrist_l": 0.0, "wrist_r": 0.0,
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


## Sentado num tronco (tela de seleção): coxas para a frente, canelas na vertical, cotovelos nos joelhos e
## o tronco um pouco curvado para a fogueira, respirando. Com "ground" 1 o modelo desce o quanto as coxas
## subiram, e o quadril fica na altura do joelho (o tronco do assento fica ali). `t` em segundos.
static func sit_pose(t: float) -> Dictionary:
	var p := rest_pose()
	var b := sin(t * BREATH_FREQ)
	p.leg_l = -1.5
	p.leg_r = -1.42
	p.knee_l = 1.5
	p.knee_r = 1.34
	p.foot_l = 0.0
	p.foot_r = 0.0
	p.body_y = b * BREATH_BODY_Y
	p.body_x = SIT_LEAN - b * BREATH_CHEST
	p.head_x = -0.06 + b * BREATH_CHEST * 0.6
	p.arm_l = Vector3(-0.95 - 0.02 * b, 0, 0.18)
	p.arm_r = Vector3(-0.95 - 0.02 * b, 0, -0.18)
	p.elbow_l = -0.75
	p.elbow_r = -0.75
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
	# o quadril gira (hip_twist) em torno do pivô Pelvis: cada articulação da coxa vai um pouco para a frente
	# ou para trás (dz). O tornozelo tem de ficar `d` atrás do quadril no chão, então `d` leva esse deslocamento.
	var ht := -lerpf(PELVIS_TWIST_WALK, PELVIS_TWIST_RUN, run) * move * cos(phase)
	# inclinado para a frente, o apoio inteiro fica mais atrás do quadril (veja STANCE_BACK)
	var lean := speed_lean(move, run)
	var back := STANCE_BACK * leg_length(r) * sin(lean) * amt
	for side in [["l", 0.0], ["r", PI]]:
		var u := fposmod(phase + float(side[1]), TAU) / TAU
		var hip: Vector3 = r["Leg" + String(side[0]).to_upper()].position
		var hip_dz := -hip.x * sin(ht) + hip.z * (cos(ht) - 1.0)
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
		d += hip_dz + back
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
	# o antebraço vem um pouco depois do braço
	var sf := -cos(phase - ARM_LAG - FOREARM_LAG)
	p.elbow_l = lerpf(IDLE_ELBOW, elbow + ELBOW_SWING * maxf(sf, 0.0), move)
	p.elbow_r = lerpf(IDLE_ELBOW, elbow + ELBOW_SWING * maxf(-sf, 0.0), move)
	# o braço que vai à frente fecha para dentro, cruzando o corpo
	var cross := lerpf(ARM_CROSS_WALK, ARM_CROSS_RUN, run) * move
	p.arm_l.z -= cross * maxf(sl, 0.0)
	p.arm_r.z += cross * maxf(-sl, 0.0)
	# o tronco amortece no meio de cada apoio (além do que a altura das pernas já dá)
	p.body_y = -lerpf(BODY_BOUNCE_WALK, BODY_BOUNCE_RUN, run) * move * bounce
	p.twist = lerpf(TORSO_TWIST_WALK, TORSO_TWIST_RUN, run) * move * cos(phase - TORSO_LAG)
	# o quadril gira contra os ombros e as pernas desfazem esse giro (continuam balançando para a frente)
	p.hip_twist = -lerpf(PELVIS_TWIST_WALK, PELVIS_TWIST_RUN, run) * move * cos(phase)
	p.leg_yaw = -p.hip_twist
	# o quadril pende um pouco sobre a perna de apoio
	p.body_z = -HIP_DROP * move * sin(phase)
	# e a pelve passa para o lado dessa perna
	p.body_shift = lerpf(WEIGHT_SHIFT_WALK, WEIGHT_SHIFT_RUN, run) * move * sin(phase)
	# o corpo cai para a frente com a velocidade e mergulha um pouco mais a cada apoio
	p.body_x = lean + LEAN_PULSE * move * bounce
	p.head_x = -HEAD_LEAN * p.body_x
	# a cabeça desfaz quase todo o giro e a inclinação do tronco: o olhar fica estável
	p.head_y = -HEAD_STEADY * p.twist
	# com o tronco inclinado, o giro da cabeça é em torno de um eixo deitado e a tombaria de lado: o termo
	# com sin() desfaz esse tombo
	p.head_z = -HEAD_STEADY * p.body_z - p.head_y * sin(p.body_x)
	return p


## Inclinação do corpo para a frente (rad) pela velocidade: `move` 0..1 do andar normal, `run` 0..1 correndo.
static func speed_lean(move: float, run: float) -> float:
	return lerpf(LEAN_WALK, LEAN_RUN, run) * clampf(move, 0.0, 1.0)


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


## A cabeça e as pernas da marcha compensam o giro e a inclinação do tronco da marcha (head_y, head_z,
## leg_yaw). Quando um golpe, arco ou magia assume o tronco (play_track, bow_draw_pose, bow_release_pose e as
## poses de magia), essa compensação sai da pose antes de ele escrever os seus valores: quem define head_y
## manda, quem não define fica com 0. A esquiva não passa por aqui: ela vai direto ao alvo (snap de todas as
## chaves) e as chaves ROLL_TUCK a cobrem. head_y e head_z também perdem a velocidade x8 do follow_cycle
## (o ataque define as suas, se quiser), para a cabeça assentar suave em vez de saltar.
static func drop_gait_comp(p: Dictionary) -> void:
	p.head_y = 0.0
	p.head_z = 0.0
	p.leg_yaw = 0.0
	var spd: Dictionary = p.speed.duplicate()   # p.speed pode ser compartilhado com outra pose
	spd.erase("head_y")
	spd.erase("head_z")
	p.speed = spd


## Toca uma trilha de golpe sobre a pose de locomoção `p`.
## Trilha = [[t, {pose parcial}, curva], ...] com t crescente em 0..1. O começo (t=0) e o fim (t=1)
## são a própria pose de locomoção; uma chave sem certa articulação é atravessada por ela.
## Curva de chegada em cada chave: "in" acelera (golpe), "out" desacelera (follow-through),
## "io" suave (padrão), "lin" constante.
## Braço e tronco vão direto ao alvo (a trilha já é suave); as pernas só fazem o passo de ataque
## inteiro com o jogador parado.
static func play_track(p: Dictionary, track: Array, t: float, move: float) -> void:
	drop_gait_comp(p)
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


## Sem arma: combo de boxe (KnightMoves.PUNCH).
static func punch_pose(p: Dictionary, combo: int, t: float, move: float) -> void:
	play_track(p, KnightMoves.PUNCH[clampi(combo, 1, 3) - 1], t, move)


static func sword_pose(p: Dictionary, combo: int, t: float, move: float) -> void:
	play_track(p, KnightMoves.SWORD[clampi(combo, 1, 3) - 1], t, move)
	if combo == 3:
		# giro: uma volta inteira desenrolando o tronco; enrolado em -PI..PI para a recuperação
		# não "desgirar"
		# o corpo inteiro gira (quadril junto: veja hips_follow), não só o tronco sobre pernas paradas
		p["spin"] = TAU * smoothstep(KnightMoves.SPIN_START, KnightMoves.SPIN_END, t)
		p.twist = wrapf(p.twist + p.spin, -PI, PI)
		if not ("twist" in p.snap):
			p.snap.append("twist")


static func staff_pose(p: Dictionary, combo: int, t: float, move: float) -> void:
	play_track(p, KnightMoves.STAFF[clampi(combo, 1, 3) - 1], t, move)
	if combo == 3:   # ergue e baixa o cajado com as duas mãos
		p["two_hand"] = smoothstep(0.02, 0.16, t) * (1.0 - smoothstep(0.42, 0.62, t))


## Magia (`kind` = "fireball", "heal", "frost_nova"); `t` 0..1 dentro de KnightMoves.CAST_TIME.
## Com cajado (`staff`), magias que têm versão própria apontam a gema (KnightMoves.CAST_STAFF).
static func cast_pose(p: Dictionary, kind: String, t: float, move: float, staff := false) -> void:
	var track: Array = KnightMoves.CAST_STAFF[kind] if staff and KnightMoves.CAST_STAFF.has(kind) \
		else KnightMoves.CAST.get(kind, KnightMoves.CAST.fireball)
	play_track(p, track, t, move)


## Arco tensionando: `c` 0..1 (0 = flecha encaixada com a corda frouxa, 1 = corda no queixo). `move` 0..1 =
## quanto anda: andando o quadril gira menos (as pernas continuam passando para a frente).
## Como no tiro com arco de verdade (e no pack "Longbow" do Mixamo): o corpo fica de lado, com o ombro
## esquerdo para o alvo; o braço do arco estica na direção da mira; a mão da corda leva a corda até o canto
## do queixo, com o cotovelo alto atrás, na linha da flecha. As mãos vão a pontos exatos por IK (veja
## _bow_ik em apply): a mão da corda fica sempre na corda e a flecha passa rente ao queixo.
static func bow_draw_pose(p: Dictionary, c: float, move := 0.0) -> void:
	drop_gait_comp(p)
	var a: Dictionary = KnightMoves.BOW_NOCK
	var b: Dictionary = KnightMoves.BOW_FULL
	var e := 1.0 - pow(1.0 - clampf(c, 0.0, 1.0), 2.0)   # puxa rápido no começo e assenta perto do fim
	for j in b:
		p[j] = lerp(a.get(j, p[j]), b[j], e)
	for j in a:
		if not b.has(j):
			p[j] = a[j]
	p["bow"] = {"draw": e, "w": 1.0, "tremble": smoothstep(0.9, 1.0, c) * KnightMoves.BOW_TREMBLE}
	p["hip_share"] = lerpf(KnightMoves.BOW_HIP_SHARE, KnightMoves.BOW_HIP_SHARE_MOVING, move)
	for j in ["arm_l", "arm_r", "elbow_l", "elbow_r", "twist", "head_y", "head_x", "wrist_l"]:
		p.speed[j] = KnightMoves.BOW_RAISE_SPEED


## Logo depois de soltar a flecha: `t` 0..1 dentro do tempo de recuperação do arco. A mão da corda escapa
## para trás, passando pela orelha (o "follow-through"); o braço do arco segura a mira um instante e os dois
## voltam à pose de andar.
## `keep` = continua mirando (botão direito ainda segurado): o arco fica erguido e a mão volta para a corda,
## pronta para encaixar a próxima flecha.
static func bow_release_pose(p: Dictionary, t: float, move: float, keep := false) -> void:
	drop_gait_comp(p)
	var hold := 1.0 if keep else 1.0 - smoothstep(KnightMoves.BOW_RELEASE_HOLD, 1.0, t)
	for j in KnightMoves.BOW_FULL:
		p[j] = lerp(p[j], KnightMoves.BOW_FULL[j], hold)
	p["bow"] = {"draw": 1.0, "w": hold, "release": t, "keep": keep}
	p["hip_share"] = lerpf(KnightMoves.BOW_HIP_SHARE, KnightMoves.BOW_HIP_SHARE_MOVING, move)
	for j in ["arm_l", "arm_r", "elbow_l", "elbow_r"]:
		p.speed[j] = KnightMoves.BOW_RELEASE_SPEED


## Flecha do Vendaval. `c` 0..1 = carga: agacha (joelhos até KnightMoves.GALE_KNEE), o tronco inclina para
## trás, a mão da corda puxa além da tensão normal e o arco treme cada vez mais. `recoil` 0..1 =
## tempo na recuperação depois do disparo (< 0 = ainda tensionando): tranco para trás e levanta.
## Os braços seguem o IK do arco: a flecha continua na linha da mira mesmo com o tronco inclinado.
static func bow_gale_pose(p: Dictionary, c: float, recoil := -1.0) -> void:
	var crouch := smoothstep(0.0, 1.0, minf(c * 1.6, 1.0))   # agacha logo no começo da tensão
	var lean := crouch
	if recoil < 0.0:
		bow_draw_pose(p, minf(c * 2.5, 1.0))
		# puxa além do normal (a mão da corda vai para trás da orelha) e o arco treme mais com a carga
		p.bow["over"] = KnightMoves.GALE_OVERDRAW * c
		p.bow["tremble"] = KnightMoves.GALE_TREMBLE * c
		p.twist -= 0.12 * c
	else:
		bow_release_pose(p, recoil, 0.0)
		var up := smoothstep(0.35, 1.0, recoil)
		crouch *= 1.0 - up
		# tranco do tiro: o tronco joga para trás e volta; o braço do arco pula para cima
		var kick := pow(1.0 - recoil, 2.0)
		lean = lean * (1.0 - up) + kick * KnightMoves.GALE_RECOIL / KnightMoves.GALE_LEAN
		p.bow["kick"] = kick
	p.body_x += KnightMoves.GALE_LEAN * lean
	p.head_x -= KnightMoves.GALE_LEAN * lean * 0.6   # a cabeça compensa: continua olhando a mira
	p.body_y += KnightMoves.GALE_CROUCH_Y * crouch
	p.leg_l = lerpf(p.leg_l, KnightMoves.GALE_THIGH_L, crouch)
	p.leg_r = lerpf(p.leg_r, KnightMoves.GALE_THIGH_R, crouch)
	p.knee_l = lerpf(p.knee_l, KnightMoves.GALE_KNEE, crouch)
	p.knee_r = lerpf(p.knee_r, KnightMoves.GALE_KNEE, crouch)
	p.foot_l = lerpf(p.foot_l, 0.0, crouch)
	p.foot_r = lerpf(p.foot_r, 0.0, crouch)
	p.ground = 1.0


## Como cada arma é carregada parado, andando e correndo (`move`, `run` 0..1). Chamar logo depois da pose de
## locomoção, antes dos golpes. A espada fica como está (o braço balança solto).
##  - cajado: segurado firme ao lado do corpo como um bordão, gema um pouco à frente; o braço balança pouco
##    (antes ele girava o cajado inteiro e a vara atravessava a perna e o tronco). Correndo, vai inclinado à
##    frente, mão na altura do quadril.
##  - arco: parado, o braço do arco fica reto ao lado do corpo; andando, dobra e balança menos.
static func weapon_carry(p: Dictionary, cls: String, move: float, run: float) -> void:
	match cls:
		"staff":
			var c: Dictionary = KnightMoves.STAFF_CARRY
			var sw: float = (p.arm_r.x - IDLE_ARM_R_X * (1.0 - move)) * float(c.swing)   # o que sobrou do balanço
			var arm: Vector3 = (c.arm as Vector3).lerp(c.arm_run, run)
			p.arm_r = Vector3(arm.x + sw, arm.y, arm.z)
			p.elbow_r = lerpf(c.elbow, c.elbow_run, run)
			# o suporte desfaz COUNTER do giro do braço; o resto inclinaria o cajado. O pulso completa a
			# inclinação pedida (> 0 = gema à frente) para ela não depender do balanço.
			var tilt: float = lerpf(c.tilt, c.tilt_run, run)
			var bend: float = p.arm_r.x + p.elbow_r
			p.wrist_r = tilt - bend * (1.0 - float(KnightLook.COUNTER.staff))
		"bow":
			var c: Dictionary = KnightMoves.BOW_CARRY
			# parado o braço fica solto e reto (a pose de respirar); andando dobra e balança pela metade
			var walk := Vector3(c.arm.x + p.arm_l.x * float(c.swing), c.arm.y, c.arm.z)
			p.arm_l = (p.arm_l as Vector3).lerp(walk, move)
			p.elbow_l = lerpf(c.elbow_idle, lerpf(c.elbow, c.elbow_run, run), move)


## IK de dois ossos do braço: ombro (ArmX, giro livre, ordem YXZ) e cotovelo (ElbowX, dobra só em X).
## `target` = onde o centro da mão deve ficar e `pole` = para onde o cotovelo deve apontar, os dois no
## espaço do pai do ombro (Body). Devolve [rotação do ombro, dobra do cotovelo]. Alvo fora do alcance:
## o braço estica na direção dele.
static func solve_arm(arm: Node3D, elbow: Node3D, hand: Vector3, target: Vector3, pole: Vector3) -> Array:
	var u := elbow.position
	var tv := target - arm.position
	var lo := ARM_IK_MAX_BEND
	var hi := 0.0
	var dist := clampf(tv.length(), (u + Basis(Vector3.RIGHT, lo) * hand).length() + 0.001,
		(u + hand).length() - 0.001)
	for _i in 22:   # o alcance cresce com o cotovelo abrindo: busca binária
		var mid := (lo + hi) * 0.5
		if (u + Basis(Vector3.RIGHT, mid) * hand).length() < dist:
			lo = mid
		else:
			hi = mid
	var bend := (lo + hi) * 0.5
	var reach := u + Basis(Vector3.RIGHT, bend) * hand
	var tn := tv.normalized()
	var q0 := Quaternion(reach.normalized(), tn)
	# gira em volta da linha ombro-mão até o cotovelo apontar para o polo
	var e0 := q0 * u
	var e_perp := e0 - tn * e0.dot(tn)
	var p_perp := pole - tn * pole.dot(tn)
	var q := q0
	if e_perp.length() > 0.0001 and p_perp.length() > 0.0001:
		q = Quaternion(tn, e_perp.normalized().signed_angle_to(p_perp.normalized(), tn)) * q0
	return [Basis(q).get_euler(EULER_ORDER_YXZ), bend]


## Põe o braço `side` ("l"/"r") com a mão em `target_m` (espaço do modelo), cotovelo para `pole_m`, misturando
## com o que a pose já pedia por `w`. O giro escolhido fica perto do atual (sem dar a volta inteira no lerp).
static func arm_ik_pose(r: Dictionary, p: Dictionary, side: String, target_m: Vector3, pole_m: Vector3, w: float) -> void:
	var sol := arm_ik(r, side, target_m, pole_m)
	if sol.is_empty() or w <= 0.0:
		return
	var cur: Vector3 = p["arm_" + side]
	var e: Vector3 = sol[0]
	e = Vector3(cur.x + wrapf(e.x - cur.x, -PI, PI), cur.y + wrapf(e.y - cur.y, -PI, PI), cur.z + wrapf(e.z - cur.z, -PI, PI))
	p["arm_" + side] = cur.lerp(e, w)
	p["elbow_" + side] = lerpf(p["elbow_" + side], sol[1], w)


## IK do braço com alvo e polo no espaço do modelo (pela pose atual do tronco). [] se o modelo não tem cotovelo.
static func arm_ik(r: Dictionary, side: String, target_m: Vector3, pole_m: Vector3) -> Array:
	var arm: Node3D = r["Arm" + side.to_upper()]
	var elbow: Node3D = r["Elbow" + side.to_upper()]
	if arm == null or elbow == null or r.get("hand_" + side) == null:
		return []
	var inv := KnightLook._chain(arm.get_parent(), r.model).affine_inverse()
	return solve_arm(arm, elbow, r["hand_" + side], inv * target_m, inv.basis * pole_m)


## Alvos das mãos com o arco (chamado em apply, com tronco e cabeça já postos). A âncora fica no canto do
## queixo; a linha da flecha sai dela na direção da mira e passa pelo arco, que fica onde o braço esquerdo
## chega quase esticado. A mão da corda segura a corda no encaixe da flecha: da corda frouxa (BOW_BRACE
## atrás do arco) até a âncora, conforme a tensão.
static func _bow_ik(r: Dictionary, p: Dictionary, k: float) -> void:
	var b: Dictionary = p.get("bow", {})
	var w: float = b.get("w", 0.0)
	r["bow_w"] = lerpf(float(r.get("bow_w", 0.0)), w, minf(1.0, k * KnightMoves.BOW_RAISE_SPEED))
	if w <= 0.001 or r.get("hand_l") == null:
		return
	var model: Node3D = r.model
	var pitch: float = r.get("aim_pitch", 0.0)
	var d := Vector3(0.0, sin(pitch), cos(pitch))          # mira no espaço do modelo (ele olha para +Z)
	var up := Vector3(0.0, cos(pitch), -sin(pitch))
	var right := Vector3(-1.0, 0.0, 0.0)
	var anchor: Vector3 = KnightLook._chain(r.Head, model) * KnightMoves.BOW_ANCHOR
	var drop: Vector3 = up * KnightMoves.BOW_GRIP_DROP     # a flecha passa por cima da mão do arco
	# arco: ponto da linha da flecha onde o braço esquerdo chega quase esticado
	var sl: Vector3 = KnightLook._chain(r.ArmL, model).origin
	var o := anchor - drop - sl
	var reach: float = float(r.reach_l) * KnightMoves.BOW_ARM_STRETCH
	var bb := d.dot(o)
	var s := clampf(-bb + sqrt(maxf(bb * bb - (o.length_squared() - reach * reach), 0.0)), 0.3, 0.9)
	var grip := anchor + d * s
	var hand_l := grip - drop
	var draw := lerpf(KnightMoves.BOW_BRACE, s + float(b.get("over", 0.0)), float(b.get("draw", 0.0)))
	var nock := grip - d * draw
	var rel: float = b.get("release", -1.0)
	if rel >= 0.0:
		# soltou: os dedos abrem e a mão escapa para trás e para fora, rente à orelha
		var e := ease_curve(clampf(rel / 0.45, 0.0, 1.0), "out")
		nock = anchor - d * (KnightMoves.BOW_RELEASE_BACK * e) + right * (0.07 * e) + up * (0.03 * e)
		if b.get("keep", false):   # ainda mirando: a mão volta para a corda solta
			nock = nock.lerp(grip - d * KnightMoves.BOW_BRACE, smoothstep(0.45, 1.0, rel))
	var tr: float = b.get("tremble", 0.0)
	if tr > 0.0:
		var ms := float(Time.get_ticks_msec())
		hand_l += up * (sin(ms * 0.047) * 0.6 + sin(ms * 0.113 + 1.7) * 0.4) * tr \
			+ right * sin(ms * 0.061) * tr * 0.5
	hand_l += up * 0.12 * float(b.get("kick", 0.0))
	# a mão da corda: os dedos no encaixe; o centro da mão fica um pouco atrás e para fora da corda
	var f: Vector3 = KnightMoves.BOW_FINGERS
	var hand_r := nock + right * f.x - up * f.y - d * f.z
	r["bow_fingers"] = nock - hand_r if rel < 0.0 else Vector3(9, 9, 9)   # 9 = soltou (corda volta)
	arm_ik_pose(r, p, "l", hand_l, KnightMoves.BOW_POLE_L, w)
	arm_ik_pose(r, p, "r", hand_r, KnightMoves.BOW_POLE_R, w)


## Corda e flecha do arco (depois de apply e hold_weapon_upright): a corda vai das pontas do arco até os
## dedos da mão da corda (com o peso do IK do arco) e a flecha sai dos dedos passando rente ao punho. O arco
## enverga conforme a corda é puxada.
static func bow_string(look: Dictionary, r: Dictionary) -> void:
	var holder: Node3D = look.get("holder")
	if holder == null or not is_instance_valid(holder) or not holder.has_meta("bow"):
		return
	var rest: Vector3 = KnightLook.bow_rest_nock(holder)
	var nock := rest
	var w: float = r.get("bow_w", 0.0)
	var fingers: Vector3 = r.get("bow_fingers", Vector3(9, 9, 9))
	if w > 0.001 and fingers.x < 8.0 and r.ElbowR and r.get("hand_r") != null:
		var model: Node3D = r.model
		var hand_m: Vector3 = KnightLook._chain(r.ElbowR, model) * (r.hand_r as Vector3)
		var nh := KnightLook._chain(holder, model).affine_inverse() * (hand_m + fingers)
		nh = Vector3(0.0, clampf(nh.y, -0.12, 0.12), minf(nh.z, rest.z))
		nock = rest.lerp(nh, smoothstep(0.0, 0.6, w))
	KnightLook.bow_shape(holder, nock)


## Chuva de Meteoros: `u` 0..1 = preparo (ergue o cajado com as duas mãos acima da cabeça); `shake` 0..1 =
## o tremor da canalização (braços, pulso e tronco tremem como quem segura um peso enorme no céu).
static func meteor_pose(p: Dictionary, u: float, shake: float) -> void:
	drop_gait_comp(p)
	var a: Dictionary = KnightMoves.METEOR_RAISE
	var e := smoothstep(0.0, 1.0, u)
	for j in a:
		p[j] = lerp(p[j], a[j], e)
	p["two_hand"] = e
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


## Golpes, arco e magias: o quadril acompanha parte do giro dos ombros (HIP_TWIST_SHARE) e as pernas
## giram com ele, em vez de o tronco torcer sozinho sobre pernas paradas. O giro inteiro do golpe 3
## (p.spin) é todo do quadril. Chamar depois da pose de ataque, antes de apply().
static func hips_follow(p: Dictionary) -> void:
	var spin: float = p.get("spin", 0.0)
	var own := wrapf(p.twist - spin, -PI, PI)
	p.hip_twist = wrapf(spin + own * float(p.get("hip_share", HIP_TWIST_SHARE)), -PI, PI)
	p.leg_yaw = 0.0   # o giro da marcha acabou: as pernas giram com o quadril
	# hip_twist e leg_yaw assentam com a suavização normal (sem o x8 do follow_cycle), senão o quadril salta
	var spd: Dictionary = p.speed.duplicate()
	spd.erase("hip_twist")
	spd.erase("leg_yaw")
	p.speed = spd
	if "twist" in p.snap and not ("hip_twist" in p.snap):
		p.snap.append("hip_twist")
		p.snap.append("leg_yaw")


## Zera o giro de tronco e quadril na hora (fim do golpe: o giro do golpe 3 não "desgira").
static func reset_twist(r: Dictionary) -> void:
	r["twist"] = 0.0
	r["hip_twist"] = 0.0
	r.LegL.rotation.y = 0.0
	r.LegR.rotation.y = 0.0
	r.Body.rotation.y = 0.0
	if r.get("Pelvis"):
		r.Pelvis.rotation.y = 0.0


## Esquiva (rolamento para a frente) no instante `u` (0..1 da esquiva): mergulha encolhendo o corpo, o
## quadril dá uma volta inteira e levanta agachado. Parte da pose de locomoção `p` (começo e fim contínuos
## com ela) e vai direto ao alvo (snap), porque a esquiva é curta demais para a suavização. A altura vem
## dos pontos de contato (ROLL_CONTACTS) em apply().
static func dodge_pose(p: Dictionary, u: float) -> void:
	u = clampf(u, 0.0, 1.0)
	var tuck := smoothstep(0.0, ROLL_TUCK_IN, u) * (1.0 - smoothstep(ROLL_SPIN_END, 1.0, u))
	for key in ROLL_TUCK:
		p[key] = lerp(p[key], ROLL_TUCK[key], tuck)
	# saindo do rolamento: agachado, pés chatos, tronco ainda inclinado
	var rise := smoothstep(ROLL_SPIN_END - 0.1, 1.0, u) * (1.0 - smoothstep(0.92, 1.0, u))
	p.knee_l = maxf(p.knee_l, 1.2 * rise)
	p.knee_r = maxf(p.knee_r, 1.0 * rise)
	# pé solto em relação à canela enquanto rola (o pé não fica "chato no chão" de cabeça para baixo)
	p.foot_l = lerpf(p.foot_l, p.leg_l + p.knee_l + 0.35, tuck)
	p.foot_r = lerpf(p.foot_r, p.leg_r + p.knee_r + 0.35, tuck)
	# volta: começa devagar no mergulho, gira rápido e desacelera ao levantar
	var spin := clampf(u / ROLL_SPIN_END, 0.0, 1.0)
	p.roll = wrapf(TAU * spin * spin * (3.0 - 2.0 * spin), -PI, PI)
	p["roll_contact"] = u < 1.0
	p["tuck"] = tuck
	p.lift = 0.0
	for key in POSE_KEYS:
		if not (key in p.snap):
			p.snap.append(key)


## Morte em duas fases: os joelhos cedem (o quadril desce com os pés no chão) e o corpo inteiro cai de
## costas, com uma perna dobrada e os braços abertos. Mexe nos pivôs direto (morto não chama apply()).
## `tw` = Tween novo do dono (o jogador); `holder` = suporte da arma (KnightLook), que deita a lâmina no
## chão em vez de ela ficar apontando para cima. revive() desfaz.
static func die(r: Dictionary, tw: Tween, holder: Node3D = null) -> void:
	reset_twist(r)
	r["death_tw"] = tw
	tw.set_parallel(true)
	var buckle := _death_buckle(r)
	for e in buckle[1]:
		tw.tween_property(e[0], e[1], e[2], buckle[0]).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var down := _death_down(r, holder)
	for e in down[1]:
		var tr := tw.tween_property(e[0], e[1], e[2], down[0]).set_delay(buckle[0])
		if e[0] == r.get("Pelvis") or e[1] == "position:y":
			tr.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)    # bate no chão e quica
		else:
			tr.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Pose final da morte na hora (prévias e testes).
static func set_dead(r: Dictionary, holder: Node3D = null) -> void:
	reset_twist(r)
	for e in _death_down(r, holder)[1]:
		(e[0] as Node).set_indexed(e[1], e[2])


## Volta da morte: quadril e tronco voltam ao lugar; braços e pernas o apply() traz de volta.
static func revive(r: Dictionary) -> void:
	var tw: Tween = r.get("death_tw")
	if tw and tw.is_valid():
		tw.kill()
	r.erase("death_tw")
	reset_twist(r)
	r["roll"] = 0.0    # morreu rolando: não termina a volta ao renascer
	r["tuck"] = 0.0
	r.Body.rotation = Vector3.ZERO
	r.Body.position.y = r.body_y
	var pelvis: Node3D = r.get("Pelvis")
	if pelvis:
		pelvis.rotation = Vector3.ZERO
		pelvis.position = r.pelvis_pos0


## [duração, [[nó, propriedade, valor], ...]]: joelhos cedem, o quadril desce o que as pernas encolheram.
static func _death_buckle(r: Dictionary) -> Array:
	var l := Vector2(-0.45, 0.95)     # (coxa, joelho) de cada perna
	var rr := Vector2(-0.25, 0.65)
	var h := maxf(r.thigh * cos(l.x) + r.shin * cos(l.x + l.y), r.thigh * cos(rr.x) + r.shin * cos(rr.x + rr.y))
	var drop := leg_length(r) - h
	var e: Array = [[r.model, "position:y", 0.0]]
	var pelvis: Node3D = r.get("Pelvis")
	if pelvis:
		e.append([pelvis, "position:y", float(r.pelvis_pos0.y) - drop])
	e.append_array(_death_limbs(r, l, rr, 0.3, Vector3(-0.35, 0, 0.3), Vector3(-0.35, 0, -0.3), -0.6))
	return [0.22, e]


## [duração, [[nó, propriedade, valor], ...]]: deitado de costas.
static func _death_down(r: Dictionary, holder: Node3D = null) -> Array:
	var e: Array = [[r.model, "position:y", 0.0]]
	if holder and is_instance_valid(holder):
		e.append([holder, "rotation:x", DEATH_WEAPON_X])
	var pelvis: Node3D = r.get("Pelvis")
	if pelvis:
		e.append([pelvis, "rotation:x", -PI / 2.0])
		e.append([pelvis, "position:y", DEATH_LIE_Y])
		e.append_array(_death_limbs(r, Vector2(-0.6, 1.5), Vector2(0.04, 0.1), 0.08,
			Vector3(0.0, 0, 1.15), Vector3(0.0, 0, -0.95), -0.2))
	else:   # modelo sem o quadril (pernas fora de Body e LegX): só o tronco deita, como antes
		e.append([r.Body, "rotation:x", -1.4])
		e.append([r.Body, "position:y", 0.35])
	return [0.55, e]


## Pernas (Vector2 = coxa, joelho), tronco, braços e cotovelos; o tornozelo deixa o pé alinhado à canela.
static func _death_limbs(r: Dictionary, l: Vector2, rr: Vector2, body_x: float, arm_l: Vector3, arm_r: Vector3,
		elbow: float) -> Array:
	var e: Array = [
		[r.LegL, "rotation:x", l.x], [r.LegR, "rotation:x", rr.x], [r.Body, "rotation:x", body_x],
		[r.ArmL, "rotation", arm_l], [r.ArmR, "rotation", arm_r], [r.Head, "rotation:x", 0.0]]
	if r.KneeL:
		e.append_array([[r.KneeL, "rotation:x", l.y], [r.KneeR, "rotation:x", rr.y]])
	if r.AnkleL:
		e.append_array([[r.AnkleL, "rotation:x", -(l.x + l.y)], [r.AnkleR, "rotation:x", -(rr.x + rr.y)]])
	if r.ElbowL:
		e.append_array([[r.ElbowL, "rotation:x", elbow], [r.ElbowR, "rotation:x", elbow]])
	return e


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
	# twist = giro dos ombros em relação ao modelo; hip_twist = a parte dele que o quadril (e as pernas) faz
	r["twist"] = lerpf(float(r.twist), p.twist, f.call("twist"))
	r["hip_twist"] = lerpf(float(r.hip_twist), float(p.get("hip_twist", 0.0)), f.call("hip_twist"))
	var pelvis: Node3D = r.get("Pelvis")
	r["roll"] = lerpf(float(r.get("roll", 0.0)), float(p.get("roll", 0.0)), f.call("roll"))
	r["tuck"] = float(p.get("tuck", 0.0))
	if pelvis:
		pelvis.rotation.y = r.hip_twist
		pelvis.rotation.x = r.roll
		body.rotation.y = wrapf(r.twist - r.hip_twist, -PI, PI)
	else:
		body.rotation.y = r.twist
	body.position.y = lerpf(body.position.y, r.body_y + p.body_y, f.call("body_y"))
	body.position.x = lerpf(body.position.x, r.body_x0 + p.body_shift, f.call("body_shift"))
	# mirando com o arco a cabeça acompanha a inclinação da mira
	var aim_head: float = -float(r.get("aim_pitch", 0.0)) * 0.8 * float(p.get("bow", {}).get("w", 0.0))
	r.Head.rotation.x = lerpf(r.Head.rotation.x, p.head_x + aim_head, f.call("head_x"))
	r.Head.rotation.y = lerpf(r.Head.rotation.y, p.head_y, f.call("head_y"))
	r.Head.rotation.z = lerpf(r.Head.rotation.z, float(p.get("head_z", 0.0)), f.call("head_z"))
	# o quadril gira com a marcha e as pernas desfazem o giro, para os pés seguirem em frente
	var leg_yaw := float(p.get("leg_yaw", 0.0))
	r.LegL.rotation.y = lerpf(r.LegL.rotation.y, leg_yaw, f.call("leg_yaw"))
	r.LegR.rotation.y = lerpf(r.LegR.rotation.y, leg_yaw, f.call("leg_yaw"))
	# arco: com tronco e cabeça no lugar, as mãos vão por IK até o arco e a corda
	_bow_ik(r, p, f.call("arm_l"))
	r["two_hand"] = lerpf(float(r.get("two_hand", 0.0)), float(p.get("two_hand", 0.0)), f.call("arm_l"))
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
	if p.get("roll_contact", false) and pelvis:
		model.position.y = -roll_floor(r)   # rolando: o ponto do corpo mais baixo encosta no chão
		return
	var target := -ground_drop(r) * float(p.ground) + float(r.lift)
	model.position.y = lerpf(model.position.y, target, minf(1.0, k * 1.5 * float(spd.get("lift", 1.0))))


## Altura (no espaço do modelo, sem a posição dele) do ponto mais baixo da superfície do corpo, pelos
## pontos de contato de ROLL_CONTACTS.
static func roll_floor(r: Dictionary) -> float:
	var model: Node3D = r.model
	var inv := model.global_transform.affine_inverse()
	var low := INF
	for c in ROLL_CONTACTS:
		var n: Node3D = r.get(c[0])
		if n == null:
			continue
		var pt: Vector3 = inv * (n.global_transform * (c[1] as Vector3))
		low = minf(low, pt.y - float(c[2]))
	for a in ["AnkleL", "AnkleR"]:
		var n: Node3D = r.get(a)
		if n == null:
			continue
		for off in [Vector3(0, -r.ankle_h, -r.heel), Vector3(0, -r.ankle_h, r.toe)]:
			low = minf(low, (inv * (n.global_transform * off)).y)
	return low if low < INF else 0.0


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
	if look.get("class", "") == "bow" and holder.has_meta("bow"):
		_orient_bow(holder, r, bend + wrist)
	else:
		holder.rotation.x = -bend * float(look.get("counter", 0.0)) + wrist
		# cajado: desfaz também a abertura do braço, senão a vara tomba para dentro, na frente do corpo
		if look.get("class", "") == "staff":
			# tombando para a frente, a vara cruza na diagonal: a gema vem para a frente do peito e a ponta de
			# baixo sai por fora do quadril direito (senão ela entra na coxa)
			var tilt: float = holder.rotation.x + bend
			holder.rotation.z = -arm.rotation.z * float(look.get("counter", 0.0)) 				- KnightMoves.STAFF_CROSS * smoothstep(0.15, 0.9, tilt)
	# rolando: desfaz quadril, tronco, ombro e cotovelo para a arma ficar em ROLL_WEAPON_PITCH
	var tuck: float = r.get("tuck", 0.0)
	if tuck > 0.0:
		var chain: float = float(r.get("roll", 0.0)) + r.Body.rotation.x + bend
		var to := wrapf(ROLL_WEAPON_PITCH - chain - holder.rotation.x, -PI, PI)
		holder.rotation.x += to * tuck
	if float(r.get("two_hand", 0.0)) > 0.01 and look.get("class", "") == "staff":
		_staff_left_hand(holder, r)


## Arco: o punho fica na mão esquerda, mas a orientação vem do corpo, não do antebraço (o pulso solto).
## Mirando (peso do IK do arco), a flecha aponta na mira e o arco fica de pé, com um leve tombo do topo para
## fora; solto, o arco fica deitado ao lado da perna e inclina um pouco com o balanço do braço (`swing`); ao
## erguer para mirar ele gira de deitado para de pé.
static func _orient_bow(holder: Node3D, r: Dictionary, swing: float) -> void:
	var w: float = r.get("bow_w", 0.0)
	var pitch: float = r.get("aim_pitch", 0.0)
	# solto: deitado ao lado da perna, um braço do arco para a frente (a ponta um pouco para baixo) e o
	# outro para trás, a corda para cima; balança um pouco com o braço
	var dn := KnightMoves.BOW_LOOSE_DOWN
	var lying := Basis(Vector3.RIGHT, Vector3(0.0, -sin(dn), cos(dn)), Vector3(0.0, -cos(dn), -sin(dn)))
	var loose := Basis.from_euler(Vector3(clampf(swing * 0.4, -0.5, 0.5), 0.0, 0.0)) * lying
	var aim := Basis.from_euler(Vector3(-pitch, 0.0, 0.0)) * Basis(Vector3.BACK, KnightMoves.BOW_CANT)
	var want := Basis(Quaternion(loose).slerp(Quaternion(aim), smoothstep(0.0, 1.0, w)))
	var parent_xf := KnightLook._chain(holder.get_parent(), r.model)
	holder.basis = (parent_xf.basis.orthonormalized().inverse() * want).orthonormalized()


## Cajado com as duas mãos (golpe 3 e Chuva de Meteoros): a mão esquerda pega a vara um pouco abaixo da
## direita, por IK, com o peso r.two_hand (o braço sai da pose e volta a ela suavemente).
static func _staff_left_hand(holder: Node3D, r: Dictionary) -> void:
	var model: Node3D = r.model
	var target: Vector3 = KnightLook._chain(holder, model) * KnightMoves.STAFF_LEFT_GRIP
	var sol := arm_ik(r, "l", target, KnightMoves.STAFF_POLE_L)
	if sol.is_empty():
		return
	var w: float = r.two_hand
	r.ArmL.rotation = r.ArmL.rotation.lerp(sol[0], w)
	r.ElbowL.rotation.x = lerpf(r.ElbowL.rotation.x, sol[1], w)


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

