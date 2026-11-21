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
## Perna de referência (quadril ao tornozelo do knight.glb, m). Corpos de perna mais curta (anão) andam com
## passos mais curtos e mais rápidos, e o balanço e o voo do tronco, que são em metros, encolhem com a perna.
const REF_LEG := 0.862
const SHORT_STRIDE := 0.0         ## quanto a abertura da coxa encolhe com a perna (0 = nada; 1 = proporcional)
## A velocidade no mundo é a mesma para todo corpo, então a perna curta pediria passos ~1,8x mais rápidos para
## o pé não deslizar (fica frenético). A cadência cai por gait_k^SHORT_CADENCE: o anão fica ~1,1x mais rápido
## que o humano e o pé desliza (~30%) no chão.
const SHORT_CADENCE := 0.75
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
const FLIGHT_LIFT_JOG := 0.05     ## quanto o corpo sobe na fase de voo (m)
const FLIGHT_LIFT_RUN := 0.09
const ARM_SWING_WALK := 0.5       ## balanço dos braços (rad)
const ARM_SWING_RUN := 0.85
const ARM_LAG := 0.25             ## os braços vêm um pouco depois das pernas (rad de fase)
const ELBOW_WALK := -0.55         ## cotovelo médio no andar normal (trote)
const ELBOW_RUN := -1.25          ## e correndo (braço de corredor)
const ELBOW_SWING := -0.35        ## dobra extra quando o braço vai à frente
const BODY_BOUNCE_WALK := 0.025   ## o tronco amortece no meio de cada apoio (m), além do que as pernas dão
const BODY_BOUNCE_RUN := 0.04
const TORSO_TWIST_WALK := 0.22    ## ombros giram contra o quadril (rad)
const TORSO_TWIST_RUN := 0.3
const PELVIS_TWIST_WALK := 0.13   ## o quadril gira contra os ombros (rad); as pernas desfazem o giro (leg_yaw)
const PELVIS_TWIST_RUN := 0.18
const HEAD_STEADY := 0.85         ## quanto a cabeça desfaz do giro e da inclinação do tronco (0..1): olha para a frente
const TORSO_LAG := 0.2            ## os ombros giram um pouco depois do quadril (rad de fase)
const HIP_DROP := 0.07            ## o quadril pende para o lado da perna de apoio (rad)
const WEIGHT_SHIFT_WALK := 0.035  ## a pelve vai para o lado da perna de apoio (m)
const WEIGHT_SHIFT_RUN := 0.022
const FOREARM_LAG := 0.35         ## o antebraço chega depois do braço (rad de fase)
const ARM_CROSS_WALK := 0.08      ## o braço que vai à frente fecha para dentro do corpo (rad)
const ARM_CROSS_RUN := 0.14
const ARM_OUT_MOVE := 0.1         ## andando os braços se afastam do corpo este tanto (rad): cotovelos visíveis de trás
const LEAN_WALK := 0.19           ## inclinação do corpo para a frente na velocidade normal (rad, ~11°)
const LEAN_RUN := 0.3             ## e correndo (~17°)
const LEAN_PULSE := 0.04          ## a cada passada o tronco mergulha este tanto ao amortecer e volta no impulso (rad)
const HEAD_LEAN := 0.6            ## quanto da inclinação a cabeça desfaz (continua olhando para a frente)
## Inclinado, o corpo vai à frente dos pés: o apoio inteiro recua esta fração de perna * sen(inclinação). O pé
## pousa mais embaixo do corpo e empurra mais atrás, como numa corrida, em vez de bater lá na frente.
const STANCE_BACK := 0.3
## Coluna: o tronco tem dois pivôs, Body (quadril, cinto, saiote) e Chest (peito, ombros, braços e cabeça),
## criado em ensure_chest(). A inclinação da corrida se reparte entre os dois (o peito cai mais que o quadril e
## a cabeça volta: a coluna faz uma curva), os ombros giram no peito contra o quadril e ficam nivelados
## enquanto o quadril pende sobre a perna de apoio.
const CHEST_LEAN := 0.45          ## fração da inclinação que o peito faz (o resto é do quadril)
const CHEST_LEVEL := 0.7          ## quanto o peito desfaz do pender do quadril (ombros nivelados)
const CHEST_MIN_TOP := 0.12       ## peça rígida do tronco vai para o peito se sobe isto acima da cintura (m)
const CHEST_DEFAULT_Y := 0.12     ## altura da cintura acima do pivô Body em modelos sem a malha Torso (m)
const LEAN_ACCEL := 0.01          ## inclinação extra por m/s² de aceleração para a frente (soma em player.gd)
const LEAN_MIN := -0.12           ## limites dessa parte da aceleração (freando / arrancando)
const LEAN_ACCEL_MAX := 0.1
const MAX_CADENCE := 26.0         ## limite da fase (rad/s), só para velocidades fora do normal
const MIN_STRIDE := 0.12          ## meio passo mínimo (m) usado no cálculo da cadência
## A pose do ciclo já é suave: a suavização de apply() só serve para as trocas de pose. Aplicada a um
## ciclo de ~3 passos/s ela atrasa e achata o movimento (o joelho dobrava bem menos que o pedido),
## então andando as articulações do ciclo seguem a pose este tanto mais rápido (veja follow_cycle).
const CYCLE_FOLLOW := 8.0
const CYCLE_KEYS := ["leg_l", "leg_r", "side_l", "side_r", "knee_l", "knee_r", "foot_l", "foot_r", "body_y", "body_z", "twist",
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
## Combo de espada com escudo (shield_combo_pose): fração do começo de cada golpe em que a pose sai da que o corpo
## tinha e entra na trilha.
const SHIELD_BLEND := 0.3
const SHIELD_RECOVER := 0.35   ## s para voltar à locomoção quando o combo com escudo para (shield_recover_pose)
## Esquiva = rolamento para a frente: o quadril dá uma volta inteira (pivô Pelvis) com o corpo encolhido.
## Fases em fração da esquiva: mergulho até ROLL_TUCK_IN (encolhe e inclina), volta até ROLL_SPIN_END, e
## levanta agachado até o fim.
const ROLL_TUCK_IN := 0.2
const ROLL_SPIN_END := 0.8
const ROLL_TUCK := {
	"body_x": 0.75, "head_x": 0.7, "leg_l": -1.75, "leg_r": -1.55, "knee_l": 2.3, "knee_r": 2.2,
	"arm_l": Vector3(-0.9, 0.0, 0.25), "arm_r": Vector3(-0.7, 0.0, -0.25), "elbow_l": -1.7, "elbow_r": -1.4,
	"twist": 0.0, "hip_twist": 0.0, "leg_yaw": 0.0, "body_y": 0.0, "body_z": 0.0, "body_shift": 0.0,
	"chest_x": 0.0, "chest_y": 0.0, "chest_z": 0.0,
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
const POSE_KEYS := ["leg_l", "leg_r", "side_l", "side_r", "knee_l", "knee_r", "foot_l", "foot_r", "lift", "body_x", "body_y", "body_z", "body_shift",
	"twist", "hip_twist", "leg_yaw", "roll", "chest_x", "chest_y", "chest_z", "head_x", "head_y", "head_z", "arm_l", "arm_r", "elbow_l", "elbow_r", "wrist_l", "wrist_r", "ground"]


## Pivôs do modelo + medidas das pernas. Funciona com modelos antigos sem KneeX/ElbowX (ficam null).
static func rig(model: Node3D) -> Dictionary:
	var r := {"model": model}
	for n in ["LegL", "LegR", "KneeL", "KneeR", "AnkleL", "AnkleR", "ArmL", "ArmR", "ElbowL", "ElbowR", "Body", "Head"]:
		r[n] = model.find_child(n, true, false)
	r["Pelvis"] = _ensure_pelvis(r)
	r["Chest"] = ensure_chest(model)
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
	# escala da passada pela perna (1 no corpo de referência; o anão fica em ~0,6)
	r["gait_k"] = clampf(leg_length(r) / REF_LEG, 0.3, 1.0)
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
	var tail = r.get("Ponytail")   # sem tipo: o rabo anterior pode ter sido liberado (troca de visual)
	tail = tail if is_instance_valid(tail) else null
	# o rabo de cavalo vem do penteado (KnightLook.apply) e é refeito a cada troca de equipamento
	var model = r.get("model")
	if is_instance_valid(model) and model is Node3D:
		# get_meta com padrão null conta como "sem padrão" e reclama a cada quadro: pergunta antes
		var cur = (model as Node3D).get_meta("ponytail") if (model as Node3D).has_meta("ponytail") else null
		cur = cur if is_instance_valid(cur) else null
		if cur != tail:
			tail = cur
			r["Ponytail"] = tail
			if tail:
				r["tail_basis"] = tail.basis
				r["tail_ang"] = Vector2.ZERO
				r["tail_vel"] = Vector2.ZERO
				r["tail_prev"] = null
	if tail == null or delta <= 0.0 or not (tail as Node3D).is_inside_tree():
		return
	var t3 := tail as Node3D
	var head := t3.get_parent() as Node3D
	var hx := head.global_transform
	var tip := hx * (t3.position + Vector3(0.0, -0.2, -0.08))
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
	t3.basis = Basis.from_euler(Vector3(ang.x, 0.0, ang.y)) * (r.tail_basis as Basis)


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


## Pivô do peito (Chest), filho de Body na altura da cintura: cabeça, braços, capa e as peças rígidas da parte
## de cima do tronco passam para ele; quadril, cinto e saiote ficam em Body. Com ele a coluna dobra na cintura
## (veja CHEST_LEAN). Criado aqui (e não no GLB) para valer em todo modelo e armadura; pode ser chamado de novo
## depois de trocar as roupas (KnightLook.apply), para separar as peças novas. Devolve null sem o pivô Body.
static func ensure_chest(model: Node3D) -> Node3D:
	var body := model.find_child("Body", true, false) as Node3D
	if body == null:
		return null
	var chest := body.get_node_or_null("Chest") as Node3D
	if chest == null:
		chest = Node3D.new()
		chest.name = "Chest"
		var y := CHEST_DEFAULT_Y
		var torso := body.get_node_or_null("Torso") as MeshInstance3D
		if torso and torso.mesh:
			y = (torso.transform * torso.get_aabb()).position.y + 0.03   # um pouco acima da borda de baixo do tronco
		chest.position = Vector3(0.0, y, 0.0)
		body.add_child(chest)
		chest.owner = body.owner
	var inv := chest.transform.affine_inverse()
	for c in body.get_children():
		var n := c as Node3D
		if n == null or n == chest:
			continue
		var up := false
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			up = mi.mesh != null and (mi.transform * mi.get_aabb()).end.y > chest.position.y + CHEST_MIN_TOP
		else:
			# pivôs (cabeça, braços), esqueleto da capa e suportes presos às costas
			var named: bool = n.name in ["Head", "ArmL", "ArmR"] or String(n.name).begins_with("Cape")
			up = named or n.position.y > chest.position.y + CHEST_MIN_TOP
		if not up:
			continue
		var xf := inv * n.transform
		var own := n.owner
		n.owner = null
		body.remove_child(n)
		chest.add_child(n)
		n.owner = own
		n.transform = xf
	return chest


## Comprimento da perna esticada (quadril ao tornozelo).
static func leg_length(r: Dictionary) -> float:
	return r.thigh + r.shin


## Pose neutra (em pé, braços soltos).
## Égide Cristalina: guarda com o escudo fincado (KnightMoves.AEGIS_GUARD, medida no Mixamo). `raise` 0..1 =
## o escudo subindo; `impact` = s desde o último golpe no escudo (fora de 0..AEGIS_IMPACT_TIME: guarda parada);
## `move` = quanto o jogador anda (andando, as pernas seguem o passo). Tronco, pernas, cabeça e a mão da espada
## são do clipe (a mão direita por IK em apply, _guard_ik); o braço do escudo e o giro do escudo são os da
## defesa com escudo (p.shield: _shield_ik e _shield_orient), que servem a todos os modelos de escudo.
static func aegis_guard_pose(p: Dictionary, raise: float, impact: float, move: float) -> void:
	var k := aegis_guard_key(impact)
	var w := clampf(raise, 0.0, 1.0)
	var legs_w := lerpf(1.0, ATK_LEGS_WHILE_MOVING, move) * w
	for j in ["leg_l", "knee_l", "leg_r", "knee_r"]:
		p[j] = lerpf(p[j], float(KnightMoves.AEGIS_STANCE[j]), legs_w)
	p.body_y = lerpf(p.body_y, float(KnightMoves.AEGIS_STANCE.body_y) * (1.0 - move * 0.6) + float(k[7]), w)
	p.body_x = lerpf(p.body_x, float(k[5]), w)
	p.twist = lerpf(p.twist, float(k[6]), w)
	# a cabeça desfaz o giro dos ombros e a inclinação: continua olhando para a frente
	p.head_y = lerpf(p.head_y, -float(k[6]) * 0.85, w)
	p.head_x = lerpf(p.head_x, -float(k[5]) * 0.6, w)
	p["hip_share"] = absf(float(KnightMoves.AEGIS_STANCE.hip_twist) / float(KnightMoves.AEGIS_GUARD[0][6]))
	p["guard"] = {"w": w, "hand_r": k[3], "elbow_r": k[4]}
	# braço e escudo da defesa; o tranco do golpe empurra a mão para trás (como num golpe defendido)
	p["shield"] = {"w": w, "jolt": clampf(1.0 - impact / 0.25, 0.0, 1.0) if impact >= 0.0 else 0.0}
	for j in ["body_x", "body_y", "twist", "head_x", "head_y"]:
		if not (j in p.snap):
			p.snap.append(j)


## Chave da guarda `s` segundos depois do golpe (misturando as vizinhas); fora do clipe, a guarda parada.
static func aegis_guard_key(s: float) -> Array:
	var keys: Array = KnightMoves.AEGIS_GUARD
	if s <= 0.0 or s >= KnightMoves.AEGIS_IMPACT_TIME:
		return keys[0]
	for i in range(1, keys.size()):
		var b: Array = keys[i]
		if s <= float(b[0]):
			var a: Array = keys[i - 1]
			var u := ease_curve((s - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001), "io")
			var out := [s]
			for j in range(1, a.size()):
				out.append(lerp(a[j], b[j], u))
			return out
	return keys[0]


## Martelo de Energia: o herói ergue a espada (KnightMoves.HAMMER_RAISE, medida no clipe "Sword And Shield Casting"
## do Mixamo). `t` = s desde o começo da habilidade; `lower` 0..1 = voltando à locomoção depois do impacto. As duas
## mãos vão por IK (_guard_ik) até os pontos do clipe; a espada fica de pé pelo pulso (HAMMER_WRIST).
static func hammer_raise_pose(p: Dictionary, t: float, lower: float) -> void:
	var k := hammer_raise_key(t)
	var w := smoothstep(0.0, KnightMoves.HAMMER_LEAD, t) * (1.0 - smoothstep(0.0, 1.0, lower))
	if w <= 0.001:
		return
	for j in ["leg_l", "knee_l", "leg_r", "knee_r"]:
		p[j] = lerpf(p[j], float(KnightMoves.HAMMER_STANCE[j]), w)
	p.body_y = lerpf(p.body_y, float(KnightMoves.HAMMER_STANCE.body_y) + float(k[7]), w)
	p.body_x = lerpf(p.body_x, float(k[5]), w)
	p.twist = lerpf(p.twist, float(k[6]), w)
	# a cabeça olha para cima, para o círculo, e desfaz o giro dos ombros
	var up := smoothstep(0.05, KnightMoves.HAMMER_RAISE_TIME, t)
	p.head_x = lerpf(p.head_x, -float(k[5]) * 0.6 - 0.32 * up, w)
	p.head_y = lerpf(p.head_y, -float(k[6]) * 0.85, w)
	# a lâmina vai ficando de pé conforme o braço sobe (hold_weapon_upright orienta o suporte)
	p["blade_up"] = w * smoothstep(0.05, 0.3, t)
	p["guard"] = {"w": w, "hand_r": k[3], "elbow_r": k[4], "hand_l": k[1], "elbow_l": k[2]}
	for j in ["body_x", "body_y", "twist", "head_x", "head_y"]:
		if not (j in p.snap):
			p.snap.append(j)


## Chave da subida da espada `t` s depois do começo (misturando as vizinhas); depois do fim, a última.
static func hammer_raise_key(t: float) -> Array:
	return clip_key(KnightMoves.HAMMER_RAISE, t)


## Círculo da Provocação Sombria: pose do clipe "Sword And Shield Power Up" (KnightMoves.TAUNT_CAST) no instante
## `clip_t` do clipe (DarkTauntRules.clip_time). Recolhe os braços, explode a energia com os braços para baixo e o
## peito aberto, segura e volta à guarda; o peso sai da locomoção no começo e volta a ela no fim do clipe. As duas
## mãos vão por IK (_guard_ik); a cabeça acompanha o peito (olha para cima na explosão).
static func taunt_pose(p: Dictionary, clip_t: float) -> void:
	var k := clip_key(KnightMoves.TAUNT_CAST, clip_t)
	var w := smoothstep(0.0, KnightMoves.TAUNT_LEAD, clip_t) * (1.0 - smoothstep(2.0, 2.36, clip_t))
	if w <= 0.001:
		return
	for j in ["leg_l", "knee_l", "leg_r", "knee_r"]:
		p[j] = lerpf(p[j], float(KnightMoves.TAUNT_STANCE[j]), w)
	p.body_y = lerpf(p.body_y, float(KnightMoves.TAUNT_STANCE.body_y) + float(k[7]), w)
	p.body_x = lerpf(p.body_x, float(k[5]), w)
	p.twist = lerpf(p.twist, float(k[6]), w)
	p.head_x = lerpf(p.head_x, float(k[5]) * 0.5, w)
	p.head_y = lerpf(p.head_y, -float(k[6]) * 0.85, w)
	p["guard"] = {"w": w, "hand_r": k[3], "elbow_r": k[4], "hand_l": k[1], "elbow_l": k[2]}
	for j in ["body_x", "body_y", "twist", "head_x", "head_y"]:
		if not (j in p.snap):
			p.snap.append(j)


## Terremoto Devastador: ergue o escudo por cima da cabeça e bate com ele no chão (KnightMoves.EARTHQUAKE_SLAM).
## `phase` = EarthquakeRules.pose_phase (0 começo, 1 escudo no alto, 2 contato, 3 fim do apoio, 4 de volta): a
## aceleração da descida já vem na fase, então as chaves se misturam em linha reta (sem frear perto do chão). As duas
## mãos vão por IK (_guard_ik); o escudo fica de pé e de frente pela orientação da guarda (p.shield,
## _shield_orient), então sobe erguido e desce com a borda de baixo na frente. As pernas abrem e afundam na descida
## (e ficam presas à pose nela, para o agachamento chegar junto com o escudo).
static func earthquake_pose(p: Dictionary, phase: float) -> void:
	var k := _linear_key(KnightMoves.EARTHQUAKE_SLAM, phase)
	var w := smoothstep(0.0, KnightMoves.EARTHQUAKE_LEAD, phase) * (1.0 - smoothstep(3.6, 4.0, phase))
	if w <= 0.001:
		return
	var crouch := smoothstep(1.15, 2.0, phase) * (1.0 - smoothstep(3.0, 3.9, phase))
	for j in ["leg_l", "knee_l", "leg_r", "knee_r"]:
		var want := lerpf(float(KnightMoves.EARTHQUAKE_STANCE_UP[j]), float(KnightMoves.EARTHQUAKE_STANCE_DOWN[j]), crouch)
		p[j] = lerpf(p[j], want, w)
	p.body_y = lerpf(p.body_y, float(k[7]), w)
	p.body_x = lerpf(p.body_x, float(k[5]), w)
	p.twist = lerpf(p.twist, float(k[6]), w)
	# a cabeça acompanha o escudo: para cima enquanto ele sobe, para o chão no golpe
	var up := smoothstep(0.3, 1.0, phase) * (1.0 - smoothstep(1.0, 1.6, phase))
	p.head_x = lerpf(p.head_x, -float(k[5]) * 0.35 - 0.3 * up + 0.12 * crouch, w)
	p.head_y = lerpf(p.head_y, -float(k[6]) * 0.85, w)
	for j in ["hip_twist", "leg_yaw", "lift"]:
		p[j] = lerpf(p[j], 0.0, w)
	p["guard"] = {"w": w, "hand_r": k[3], "elbow_r": k[4], "hand_l": k[1], "elbow_l": k[2]}
	p["shield"] = {"w": w, "jolt": 0.0}
	var snap := ["body_x", "body_y", "twist", "head_x", "head_y"]
	if phase >= 0.9 and phase <= 2.6:
		snap.append_array(["leg_l", "knee_l", "leg_r", "knee_r"])
	for j in snap:
		if not (j in p.snap):
			p.snap.append(j)


## Chave de uma trilha [fase, ...valores] na fase `x`, em linha reta entre as vizinhas (sem suavizar).
static func _linear_key(keys: Array, x: float) -> Array:
	if x <= float(keys[0][0]):
		return keys[0]
	for i in range(1, keys.size()):
		var b: Array = keys[i]
		if x <= float(b[0]):
			var a: Array = keys[i - 1]
			var u := (x - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001)
			var out := [x]
			for j in range(1, a.size()):
				out.append(lerp(a[j], b[j], u))
			return out
	return keys[keys.size() - 1]


## Chave de um clipe medido (formato [t, ...valores]) no instante `t`, misturando as vizinhas; depois do fim, a última.
static func clip_key(keys: Array, t: float) -> Array:
	if t <= 0.0:
		return keys[0]
	for i in range(1, keys.size()):
		var b: Array = keys[i]
		if t <= float(b[0]):
			var a: Array = keys[i - 1]
			var u := ease_curve((t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001), "io")
			var out := [t]
			for j in range(1, a.size()):
				out.append(lerp(a[j], b[j], u))
			return out
	return keys[keys.size() - 1]


static func rest_pose() -> Dictionary:
	return {"leg_l": 0.0, "leg_r": 0.0, "side_l": 0.0, "side_r": 0.0, "knee_l": 0.0, "knee_r": 0.0, "foot_l": 0.0, "foot_r": 0.0, "lift": 0.0,
		"body_x": 0.0, "body_y": 0.0,
		"body_z": 0.0, "body_shift": 0.0, "twist": 0.0, "hip_twist": 0.0, "leg_yaw": 0.0, "roll": 0.0, "chest_x": 0.0, "chest_y": 0.0, "chest_z": 0.0,
		"head_x": 0.0, "head_y": 0.0, "head_z": 0.0, "wrist_l": 0.0, "wrist_r": 0.0,
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
		p.lift = lerpf(FLIGHT_LIFT_JOG, FLIGHT_LIFT_RUN, run) * float(r.get("gait_k", 1.0)) * sin(PI * (x - duty) / (0.5 - duty)) * amt * st
	# braços ao contrário das pernas do mesmo lado (sl = +1 com a perna esquerda atrás), um pouco atrasados
	var arm_amp := lerpf(ARM_SWING_WALK, ARM_SWING_RUN, run) * move
	var elbow := lerpf(lerpf(-0.3, ELBOW_WALK, minf(st / JOG_STYLE, 1.0)), ELBOW_RUN, run)
	var sl := -cos(phase - ARM_LAG)
	p.arm_l = Vector3(-sl * arm_amp, 0, IDLE_ARM_OUT + (ARM_OUT_MOVE + 0.05 * run) * move)
	p.arm_r = Vector3(IDLE_ARM_R_X * (1.0 - move) + sl * arm_amp * 0.8, 0, -IDLE_ARM_OUT - (ARM_OUT_MOVE + 0.05 * run) * move)
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
	p.body_y = -lerpf(BODY_BOUNCE_WALK, BODY_BOUNCE_RUN, run) * float(r.get("gait_k", 1.0)) * move * bounce
	var shoulders := lerpf(TORSO_TWIST_WALK, TORSO_TWIST_RUN, run) * move * cos(phase - TORSO_LAG)   # giro dos ombros
	# o quadril gira contra os ombros e as pernas desfazem esse giro (continuam balançando para a frente)
	p.hip_twist = -lerpf(PELVIS_TWIST_WALK, PELVIS_TWIST_RUN, run) * move * cos(phase)
	p.leg_yaw = -p.hip_twist
	# com o pivô do peito, o cinto e o saiote (Body) giram com o quadril e os ombros giram no peito, contra ele
	var spine: bool = r.get("Chest") != null
	p.twist = p.hip_twist if spine else shoulders
	p.chest_y = shoulders - p.twist
	# o quadril pende um pouco sobre a perna de apoio
	p.body_z = -HIP_DROP * move * sin(phase)
	# e a pelve passa para o lado dessa perna
	p.body_shift = lerpf(WEIGHT_SHIFT_WALK, WEIGHT_SHIFT_RUN, run) * move * sin(phase)
	# o corpo cai para a frente com a velocidade e mergulha um pouco mais a cada apoio
	var pitch := lean + LEAN_PULSE * move * bounce
	p.chest_x = pitch * CHEST_LEAN if spine else 0.0   # o peito cai mais que o quadril: a coluna curva
	p.body_x = pitch - p.chest_x
	p.head_x = -HEAD_LEAN * pitch
	# os ombros ficam quase nivelados enquanto o quadril pende
	p.chest_z = -CHEST_LEVEL * p.body_z if spine else 0.0
	# a cabeça desfaz quase todo o giro e a inclinação do tronco: o olhar fica estável
	p.head_y = -HEAD_STEADY * shoulders
	# com o tronco inclinado, o giro da cabeça é em torno de um eixo deitado e a tombaria de lado: o termo
	# com sin() desfaz esse tombo
	# o mesmo vale para o giro do peito sobre o quadril inclinado
	p.head_z = -HEAD_STEADY * (p.body_z + p.chest_z) - p.head_y * sin(pitch) - p.chest_y * sin(p.body_x)
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
	var amp := lerpf(WALK_AMP, RUN_AMP, run) * lerpf(1.0, float(r.get("gait_k", 1.0)), SHORT_STRIDE)
	return leg_length(r) * sin(amp * pow(clampf(move, 0.0, 1.0), STRIDE_POW))


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
	var k := pow(float(r.get("gait_k", 1.0)), SHORT_CADENCE)
	return minf(hspeed * PI * gait_duty(move, run) / reach * k, MAX_CADENCE)


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
	# o que a marcha pôs no peito volta para o tronco inteiro (Body): o golpe parte da mesma pose de tronco de
	# sempre e manda nele sozinho. apply() leva o peito com a mesma velocidade do tronco, então não há tranco.
	p.twist += float(p.get("chest_y", 0.0))
	p.body_x += float(p.get("chest_x", 0.0))
	p.body_z += float(p.get("chest_z", 0.0))
	p.chest_x = 0.0
	p.chest_y = 0.0
	p.chest_z = 0.0
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


## Espada com escudo: o combo do Mixamo retargetado (KnightMovesShield, gerado por
## tools/retarget_shield_combo.gd): três golpes e o giro no fim. `combo` 1..4, `t` 0..1 do golpe, `move` 0..1 =
## quanto anda (as pernas fazem só ATK_LEGS_WHILE_MOVING do passo). `from` = a pose em que o corpo estava quando o
## golpe começou (capture_pose): nos primeiros SHIELD_BLEND do golpe a pose sai dela e entra na trilha, então o
## golpe nasce de onde o corpo estiver (parado, andando ou voltando do golpe anterior). Emendados, o fim de um
## golpe já é o começo do próximo e a mistura não muda nada. A trilha é densa: as articulações vão direto a ela
## (snap). O quadril gira o que o do Mixamo gira (spin, sem a parte do tronco de hips_follow).
static func shield_combo_pose(p: Dictionary, combo: int, t: float, move: float, from: Dictionary = {}) -> void:
	drop_gait_comp(p)
	var tr: Dictionary = KnightMovesShield.TRACKS[clampi(combo, 1, KnightMovesShield.TRACKS.size()) - 1]
	t = clampf(t, 0.0, 1.0)
	var x := t * float(KnightMovesShield.N - 1)
	var i := mini(int(x), KnightMovesShield.N - 2)
	var u := x - float(i)
	var legs_w := lerpf(1.0, ATK_LEGS_WHILE_MOVING, move)
	var w := smoothstep(0.0, SHIELD_BLEND, t)
	var snap: Array = p.snap
	for j in tr:
		var base = p.get(j, 0.0)
		var v = _sample_rot(tr[j], i, u) if j in ["arm_l", "arm_r"] else _catmull(tr[j], i, u)
		if w < 1.0 and from.has(j):
			v = _mix_joint(j, from[j], v, w, tr[j][0])
		if j in LEG_KEYS or j == "side_l" or j == "side_r":
			v = lerp(base, v, legs_w)
		p[j] = v
		if j != "spin":
			snap.append(j)
	p["hip_share"] = 0.0


## Volta do combo com escudo para a locomoção `p` quando nenhum golpe emenda: `from` = a pose do fim do golpe
## (capture_pose), `t` 0..1 em SHIELD_RECOVER segundos. Mistura com começo e fim suaves: a suavização comum de
## apply sairia na velocidade máxima, num tranco (o fim de um golpe já está a caminho do próximo).
static func shield_recover_pose(p: Dictionary, from: Dictionary, t: float) -> void:
	var w := smoothstep(0.0, 1.0, t)
	var snap: Array = p.snap
	for j in from:
		var key: String = "hip_twist" if j == "spin" else j   # fora do golpe o quadril é hip_twist
		var b = p.get(key, 0.0)
		p[key] = _mix_joint(j, from[j], b, w, b)
		snap.append(key)


## Pose atual do corpo nas chaves das trilhas de KnightMovesShield (para shield_combo_pose misturar a partir dela).
static func capture_pose(r: Dictionary) -> Dictionary:
	var body: Node3D = r.Body
	var head: Node3D = r.Head
	var c := {"spin": float(r.get("hip_twist", 0.0)), "twist": float(r.get("twist", 0.0)),
		"body_x": body.rotation.x, "body_z": body.rotation.z, "head_x": head.rotation.x, "head_y": head.rotation.y,
		"arm_r": (r.ArmR as Node3D).rotation, "arm_l": (r.ArmL as Node3D).rotation,
		"wrist_r": float(r.get("wrist_r", 0.0)),
		"leg_l": (r.LegL as Node3D).rotation.x, "leg_r": (r.LegR as Node3D).rotation.x,
		"side_l": (r.LegL as Node3D).rotation.z, "side_r": -(r.LegR as Node3D).rotation.z}
	for s in ["l", "r"]:
		var el: Node3D = r.get("Elbow" + s.to_upper())
		var kn: Node3D = r.get("Knee" + s.to_upper())
		c["elbow_" + s] = el.rotation.x if el else IDLE_ELBOW
		c["knee_" + s] = kn.rotation.x if kn else 0.0
	return c


## Mistura `a` -> `b` com peso `w`: braços pelo caminho curto da rotação (Euler misturado faria o braço dar voltas);
## giro do tronco, do quadril e do pulso pela volta mais curta até o começo da trilha (`b0`: medida contra o valor
## que corre, a volta mais curta trocaria de lado no meio de um giro rápido); o resto direto.
static func _mix_joint(j: String, a, b, w: float, b0):
	if j == "twist" or j == "spin" or j == "wrist_r":
		return lerpf(float(b0) + wrapf(float(a) - float(b0), -PI, PI), b, w)
	if j == "arm_l" or j == "arm_r":
		var qa := Basis.from_euler(a as Vector3).get_rotation_quaternion()
		var qb := Basis.from_euler(b as Vector3).get_rotation_quaternion()
		return Basis(qa.slerp(qb, w)).get_euler()
	return lerp(a, b, w)


## Rotação (Euler YXZ) na posição `i + u` dos quadros `a`, interpolada como rotação (cúbica esférica): perto do
## braço apontado para a frente o Euler muda rápido, e interpolar os ângulos tiraria o braço do caminho.
static func _sample_rot(a: Array, i: int, u: float) -> Vector3:
	var n := a.size()
	var q1 := Basis.from_euler(a[i]).get_rotation_quaternion()
	var q2 := _near(q1, Basis.from_euler(a[mini(i + 1, n - 1)]).get_rotation_quaternion())
	var q0 := _near(q1, Basis.from_euler(a[maxi(i - 1, 0)]).get_rotation_quaternion())
	var q3 := _near(q2, Basis.from_euler(a[mini(i + 2, n - 1)]).get_rotation_quaternion())
	var e := Basis(q1.spherical_cubic_interpolate(q2, q0, q3, u)).get_euler()
	# o mesmo ramo de Euler dos quadros (apply mistura os ângulos): desenrolado em torno do quadro i
	var ref: Vector3 = a[i]
	return Vector3(ref.x + wrapf(e.x - ref.x, -PI, PI), ref.y + wrapf(e.y - ref.y, -PI, PI), ref.z + wrapf(e.z - ref.z, -PI, PI))


static func _near(ref: Quaternion, q: Quaternion) -> Quaternion:
	return q if ref.dot(q) >= 0.0 else -q


## Valor na posição `i + u` de uma lista de quadros uniformes (Catmull-Rom).
static func _catmull(a: Array, i: int, u: float):
	var n := a.size()
	return cubic_interpolate(a[i], a[mini(i + 1, n - 1)], a[maxi(i - 1, 0)], a[mini(i + 2, n - 1)], u)


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
	# a inclinação é para trás em relação à MIRA (para longe do alvo), no espaço do modelo. body_x/body_z giram
	# o tronco já torcido de lado (twist ~ -1,3), então um body_x puro aqui tombava o arqueiro para o lado:
	# decompõe o eixo X do modelo no referencial do tronco girado
	var tilt: float = KnightMoves.GALE_LEAN * lean
	p.body_x += tilt * cos(p.twist)
	p.body_z += tilt * sin(p.twist)
	p.head_x -= tilt * 0.6   # a cabeça compensa: continua olhando a mira
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


## Montante (espada de duas mãos) carregada: parado em guarda (KnightMoves.GREAT_GUARD, pernas em GREAT_STANCE),
## andando com a lâmina no ombro e as duas mãos no cabo (GREAT_SHOULDER), correndo baixa, arrastada atrás na mão direita
## (GREAT_RUN; a esquerda volta a balançar e a lâmina balança com o braço). A lâmina acompanha o sobe e desce e metade do giro dos ombros da passada.
## Chamar depois de weapon_carry. Põe p["tool"] (os braços vão por IK em apply).
static func great_carry(p: Dictionary, move: float, run: float, weight := 1.0) -> void:
	var t := great_mix(KnightMoves.GREAT_GUARD, KnightMoves.GREAT_SHOULDER, smoothstep(0.0, 1.0, minf(move * 1.6, 1.0)))
	t = great_mix(t, KnightMoves.GREAT_RUN, run)
	var still := (1.0 - move) * weight
	for j in KnightMoves.GREAT_STANCE:
		p[j] = float(p[j]) + float(KnightMoves.GREAT_STANCE[j]) * still
	# correndo, o braço da arma balança como o da marcha (a mão vai contra a perna direita) em volta do ombro; a
	# lâmina gira só uma parte disso (GREAT_RUN_BLADE): pesada, ela fica quase no mesmo ângulo atrás da perna
	var sw := (float((p.arm_r as Vector3).x) - IDLE_ARM_R_X * (1.0 - move)) * KnightMoves.GREAT_RUN_SWING * run
	if absf(sw) > 0.0001:
		var sh := Vector3(-0.2, 1.42, 0.0)
		var hand := (t.end as Vector3) + (t.dir as Vector3).normalized() * KnightMoves.GREAT_GRIP
		hand = sh + Basis(Vector3.RIGHT, sw) * (hand - sh)
		var blade := Basis(Vector3.RIGHT, sw * KnightMoves.GREAT_RUN_BLADE)
		t.dir = blade * (t.dir as Vector3)
		t.edge = blade * (t.edge as Vector3)
		t.end = hand - (t.dir as Vector3).normalized() * KnightMoves.GREAT_GRIP
	var turn := Basis(Vector3.UP, float(p.get("twist", 0.0)) * 0.5 * (1.0 - run))
	t.end = turn * (t.end as Vector3) + Vector3(0.0, float(p.get("body_y", 0.0)), 0.0)
	t.dir = turn * (t.dir as Vector3)
	t.edge = turn * (t.edge as Vector3)
	t["w"] = weight
	t["grip"] = KnightMoves.GREAT_GRIP
	# correndo, a lâmina aponta para trás: alinhar o punho com ela jogaria o cotovelo para a frente (impossível com o
	# braço balançando). O cotovelo vai para trás e o pulso (_tool_wrists) gira a mão o que der
	t["pole_r"] = KnightMoves.TOOL_POLE_R.lerp(KnightMoves.GREAT_RUN_POLE_R, run)
	t["pole_w"] = lerpf(GRIP_POLE_WEIGHT, KnightMoves.GREAT_RUN_POLE_W, run)
	p["tool"] = t
	p["two_hand"] = 0.0


## Montante nas prévias (inventário, seleção de personagem), que não passam pelo player.gd: se a arma de `look` (o
## que KnightLook.apply devolveu) é de duas mãos, as duas mãos vão ao cabo por cima da pose `p` (peso `weight`).
static func carry(look: Dictionary, p: Dictionary, move := 0.0, run := 0.0, weight := 1.0) -> void:
	if look.get("great", false) and weight > 0.0:
		great_carry(p, move, run, weight)


## Golpe `combo` (1..3) da montante no instante `t` (0..1) por cima da pose de carregar (great_carry já chamado):
## o corpo toca KnightMoves.GREAT e a lâmina segue GREAT_TOOL, saindo da pose de carregar e voltando a ela.
static func great_pose(p: Dictionary, combo: int, t: float, move: float) -> void:
	var c := clampi(combo, 1, 3) - 1
	var ready: Dictionary = p.get("tool", KnightMoves.GREAT_GUARD)
	play_track(p, KnightMoves.GREAT[c], t, move)
	var tl := great_sample(KnightMoves.GREAT_TOOL[c], ready, t)
	tl["w"] = 1.0
	tl["grip"] = KnightMoves.GREAT_GRIP
	p["tool"] = tl
	p["hip_share"] = 0.5
	var snap: Array = p.snap
	for j in ["arm_l", "arm_r", "elbow_l", "elbow_r"]:
		snap.append(j)   # os braços saem do IK da trajetória, que já é suave: sem o atraso da suavização


## A trajetória da montante no instante `u` (chaves [u, {end, dir, edge, slide, left}, curva] entre `ready` nas pontas).
static func great_sample(track: Array, ready: Dictionary, u: float) -> Dictionary:
	var u0 := 0.0
	var a := ready
	for key in track:
		var u1: float = key[0]
		if u <= u1:
			return great_mix(a, key[1], ease_curve((u - u0) / maxf(u1 - u0, 0.0001), key[2]))
		u0 = u1
		a = key[1]
	return great_mix(a, ready, ease_curve((u - u0) / maxf(1.0 - u0, 0.0001), "io"))


static func great_mix(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	return {"end": (a.end as Vector3).lerp(b.end, k),
		"dir": (a.dir as Vector3).normalized().slerp((b.dir as Vector3).normalized(), k),
		"edge": (a.edge as Vector3).normalized().slerp((b.edge as Vector3).normalized(), k),
		"slide": lerpf(float(a.get("slide", 0.0)), float(b.get("slide", 0.0)), k),
		"left": lerpf(float(a.get("left", 1.0)), float(b.get("left", 1.0)), k)}


## Escudo levantado (KnightMoves.SHIELD_GUARD) por cima da locomoção: `w` 0..1 = quanto já subiu, `jolt`
## 0..1 = tranco do último golpe defendido, `move` 0..1 = quanto anda (andando os joelhos já dobram na passada).
## `r` = rig, `phase` = fase da passada (rad, a mesma da locomoção) e `mv` = movimento no espaço do modelo
## (x = para a esquerda dele, y = para a frente; comprimento 0..1 da velocidade de andar com o escudo).
static func shield_block_pose(p: Dictionary, w: float, jolt: float, r: Dictionary, phase: float, mv: Vector2) -> void:
	var g: Dictionary = KnightMoves.SHIELD_GUARD
	var e := w * w * (3.0 - 2.0 * w)
	p["shield"] = {"w": e, "jolt": jolt}   # o braço e o giro do escudo vêm em apply (_shield_ik, _shield_orient)
	p.wrist_l = lerpf(p.wrist_l, 0.0, e)
	p.twist = lerpf(p.twist, float(g.twist), e)
	p.body_x = lerpf(p.body_x, float(g.body_x), e)
	p.head_x = lerpf(p.head_x, float(g.head_x), e)
	_guard_legs(p, e, r, phase, mv)
	for j in ["arm_l", "elbow_l", "twist"]:
		p.speed[j] = float(g.speed)


## Pernas da guarda: joelhos levemente dobrados, pés um pouco afastados e, andando, passo de caranguejo:
## os pés abrem e fecham na direção do movimento (de lado ou para a frente), sem cruzar, e o pé que vai
## à frente do movimento sobe um pouco. O tronco não gira com a passada.
static func _guard_legs(p: Dictionary, e: float, r: Dictionary, phase: float, mv: Vector2) -> void:
	var g: Dictionary = KnightMoves.SHIELD_STEP
	var amt := clampf(mv.length(), 0.0, 1.0)
	var dir := mv / mv.length() if mv.length() > 0.01 else Vector2.ZERO
	var reach := float(g.reach) * smoothstep(0.0, 0.3, amt)
	var lh := leg_length(r) * cos(float(g.knee) * 0.5)
	var o := sin(phase)
	var c := cos(phase)
	for side in [["l", 1.0, o, c], ["r", -1.0, -o, -c]]:
		var sd: String = side[0]
		var sx: float = side[1]
		var off: float = side[2] * reach               # quanto o pé está adiantado no sentido do movimento
		var swing := maxf(float(side[3]), 0.0) * smoothstep(0.0, 0.3, amt)   # pé indo no sentido do movimento
		var foot := Vector2(float(g.width) * sx, 0.0) + dir * off           # x = esquerda do modelo, y = frente
		var knee := float(g.knee) + float(g.lift) * swing
		var side_a := atan2(foot.x * sx, lh)                                 # + = coxa aberta para fora
		var leg := thigh_for(r, -foot.y, knee)
		p["knee_" + sd] = lerpf(p["knee_" + sd], knee, e)
		p["leg_" + sd] = lerpf(p["leg_" + sd], leg, e)
		p["side_" + sd] = lerpf(p["side_" + sd], side_a, e)
		p["foot_" + sd] = lerpf(p["foot_" + sd], 0.0, e)
	# sem o giro de quadril e ombros da marcha; o peso passa de um pé para o outro no passo de lado
	for k in ["hip_twist", "leg_yaw", "chest_y", "head_y", "head_z", "body_z", "lift"]:
		p[k] = lerpf(p[k], 0.0, e)
	p.body_shift = lerpf(p.body_shift, float(g.shift) * o * dir.x * amt, e)
	p.body_y = lerpf(p.body_y, -float(g.bob) * absf(c) * amt, e)


## Guarda do escudo: mão esquerda na frente do peito por IK, cotovelo dobrado à frente (chamado em apply).
static func _shield_ik(r: Dictionary, p: Dictionary, k: float) -> void:
	var sh: Dictionary = p.get("shield", {})
	var w: float = sh.get("w", 0.0)
	r["shield_w"] = lerpf(float(r.get("shield_w", 0.0)), w, minf(1.0, k * float(KnightMoves.SHIELD_GUARD.speed)))
	if w <= 0.001:
		return
	var g: Dictionary = KnightMoves.SHIELD_GUARD
	var hand: Vector3 = g.hand - Vector3(0, 0, float(g.jolt_back) * float(sh.get("jolt", 0.0)))
	arm_ik_pose(r, p, "l", hand, g.pole, w)


## Gira o escudo no antebraço: parado ele pende de lado no braço (como saiu do KnightLook); na guarda fica de
## frente, de pé, logo à frente do antebraço. Mistura as duas pelo peso da guarda (r.shield_w).
static func _shield_orient(r: Dictionary) -> void:
	var model: Node3D = r.model
	var rig: Dictionary = model.get_meta("shield_rig", {})
	if rig.is_empty():
		return
	var w: float = r.get("shield_w", 0.0)
	var rest: Transform3D = rig.rest
	var t := rest
	var elbow: Node3D = r.ElbowL
	if w > 0.001 and elbow and r.get("hand_l") != null:
		var g: Dictionary = KnightMoves.SHIELD_GUARD
		var e := KnightLook._chain(elbow, model)
		var mid := e.origin.lerp(e * (r.hand_l as Vector3), 0.55)
		var b := Basis.from_euler(Vector3(-float(g.tilt), 0.0, 0.0))   # face +Z, borda de cima à frente
		var at := mid + b.z * float(g.out) + b.y * float(g.rise)
		t = rest.interpolate_with(e.affine_inverse() * Transform3D(b, at), w)
	var delta := t * rest.affine_inverse()
	for part in rig.parts:
		var n: Node3D = part[0]
		if is_instance_valid(n):
			n.transform = delta * (part[1] as Transform3D)


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


## Égide Cristalina (chamado em apply, com o tronco já posto): a mão da espada por IK no ponto da guarda do
## Mixamo (p.guard, de aegis_guard_pose), a partir do ombro e escalado pelo alcance do braço do cavaleiro
## (o braço do escudo é o da defesa: _shield_ik). O cotovelo aponta para onde ele está no clipe (a parte dele fora da linha ombro-mão).
static func _guard_ik(r: Dictionary, p: Dictionary) -> void:
	var g: Dictionary = p.get("guard", {})
	var w := float(g.get("w", 0.0))
	if w <= 0.001:
		return
	var model: Node3D = r.model
	for side in ["r", "l"]:   # a Égide só passa a direita (o escudo é da defesa); o Martelo passa as duas
		if not g.has("hand_" + side):
			continue
		var arm: Node3D = r["Arm" + side.to_upper()]
		if arm == null or r.get("hand_" + side) == null:
			continue
		var s := float(r["reach_" + side]) / KnightMoves.AEGIS_GUARD_ARM
		var hand: Vector3 = g["hand_" + side] * s
		var elbow: Vector3 = g["elbow_" + side] * s
		var pole := elbow - hand * (elbow.dot(hand) / maxf(hand.length_squared(), 0.00001))
		if pole.length() < 0.03:   # braço quase esticado no clipe: cotovelo para fora e para trás
			pole = Vector3(0.6 if side == "l" else -0.6, -0.3, -0.5)
		var shoulder: Vector3 = KnightLook._chain(arm, model).origin
		arm_ik_pose(r, p, side, shoulder + hand, pole.normalized(), w)
		if not (("arm_" + side) in p.snap):
			p.snap.append("arm_" + side)
			p.snap.append("elbow_" + side)


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


## Ferramenta de coleta conduzida pela trajetória (GatherAction.pose_cycle põe p["tool"]): `end` = onde fica a
## mão esquerda (fim do cabo), `dir` = para onde o cabo aponta, `edge` = para onde o gume aponta e `slide` = quanto
## a mão direita está subida no cabo, tudo no espaço do modelo. As duas mãos vão por IK até o cabo; o suporte da
## arma é orientado por hold_weapon_upright com o que fica guardado aqui (tool_w, tool_dir, tool_edge).
static func _tool_ik(r: Dictionary, p: Dictionary, k: float) -> void:
	var t: Dictionary = p.get("tool", {})
	var w: float = t.get("w", 0.0)
	r["tool_w"] = lerpf(float(r.get("tool_w", 0.0)), w, k)
	if w <= 0.001:
		return
	var dir: Vector3 = (t.dir as Vector3).normalized()
	var edge: Vector3 = t.edge as Vector3
	edge = (edge - dir * edge.dot(dir)).normalized()
	r["tool_dir"] = dir
	r["tool_edge"] = edge
	var end_m: Vector3 = t.end
	# `grip` = distância entre as mãos no cabo (montante: KnightMoves.GREAT_GRIP); `left` = quanto a esquerda segura
	var grip := float(t.get("grip", -KnightMoves.TOOL_LEFT_GRIP.z))
	var left := float(t.get("left", 1.0))
	r["tool_left"] = lerpf(float(r.get("tool_left", 1.0)), left, k)
	var hand_r: Vector3 = end_m + dir * (float(t.slide) + grip)
	_arm_to_grip(r, p, "l", end_m, dir, KnightMoves.TOOL_POLE_L, w * left)
	# `pole_r`/`pole_w` (montante correndo): o cotovelo direito manda mais que o alinhamento do punho
	var pole_r: Vector3 = t.get("pole_r", KnightMoves.TOOL_POLE_R)
	_arm_to_grip(r, p, "r", hand_r, dir, pole_r, w, float(t.get("pole_w", GRIP_POLE_WEIGHT)))


## Suporte da arma conduzido pela trajetória (_tool_ik): cabo (ou lâmina) em `r.tool_dir` e gume em `r.tool_edge`,
## misturado com o que o antebraço dá por `w`. O gume do machado é +X do suporte (AXE_ROLL); o da picareta e o da
## espada, -Y (a largura da lâmina).
static func _orient_by_path(holder: Node3D, r: Dictionary, w: float) -> void:
	var dir: Vector3 = r.tool_dir
	var edge: Vector3 = r.tool_edge
	var gx := edge if holder.has_meta("axe") else (-edge).cross(dir).normalized()
	var want := Basis(gx, dir.cross(gx).normalized(), dir).orthonormalized()
	var parent_xf := KnightLook._chain(holder.get_parent(), r.model)
	var b := (parent_xf.basis.orthonormalized().inverse() * want).orthonormalized()
	holder.basis = Basis(Quaternion(holder.basis.orthonormalized()).slerp(Quaternion(b), clampf(w, 0.0, 1.0)))


## Braço inteiro a partir do cabo: a mão `side` vai para `target_m` e, como o modelo não tem junta de pulso (o punho
## fecha no eixo Z do antebraço, polegar em +Z), o giro do cotovelo em volta da linha ombro-mão é escolhido para
## o punho ficar o mais alinhado possível com o cabo (`axis_m`, apontando para a cabeça da ferramenta). O polegar
## aponta para o lado de dentro da dobra do cotovelo, então o cotovelo acaba apontando para o lado oposto ao da
## cabeça da ferramenta, como numa pegada de verdade; `pole_m` (para fora e para baixo) só desempata. O pulso
## (_tool_wrists) tira o pouco que sobrar girando a malha da mão. Tudo no espaço do modelo.
const GRIP_SWIVEL_STEPS := 20
const GRIP_POLE_WEIGHT := 0.12   ## peso do cotovelo natural contra o alinhamento do punho
static func _arm_to_grip(r: Dictionary, p: Dictionary, side: String, target_m: Vector3, axis_m: Vector3,
		pole_m: Vector3, w: float, pole_w := GRIP_POLE_WEIGHT) -> void:
	if w <= 0.0:
		return
	var g := grip_solve(r, side, target_m, axis_m, pole_m, pole_w)
	if g.is_empty():
		return
	var sol: Array = g.sol
	var cur: Vector3 = p["arm_" + side]
	# a suavização (apply) interpola os ângulos do ombro: o alvo vem na forma equivalente mais perto de onde o braço
	# está agora, senão ele dá a volta por dentro do corpo para chegar à mesma orientação
	var e := euler_near(sol[0], (r["Arm" + side.to_upper()] as Node3D).rotation)
	p["arm_" + side] = euler_near(cur, e).lerp(e, w)
	p["elbow_" + side] = lerpf(p["elbow_" + side], sol[1], w)


## Os ângulos de Euler (ordem YXZ, a dos ossos) de `e` na forma mais perto de `ref`: (x, y, z) e (π - x, y + π, z + π)
## são a mesma orientação, e cada ângulo pode somar voltas inteiras.
static func euler_near(e: Vector3, ref: Vector3) -> Vector3:
	var a := Vector3(ref.x + wrapf(e.x - ref.x, -PI, PI), ref.y + wrapf(e.y - ref.y, -PI, PI), ref.z + wrapf(e.z - ref.z, -PI, PI))
	var f := Vector3(PI - e.x, e.y + PI, e.z + PI)
	var b := Vector3(ref.x + wrapf(f.x - ref.x, -PI, PI), ref.y + wrapf(f.y - ref.y, -PI, PI), ref.z + wrapf(f.z - ref.z, -PI, PI))
	return a if (a - ref).length_squared() <= (b - ref).length_squared() else b


## A melhor pose do braço `side` para segurar o cabo em `target_m` com o punho em `axis_m` (ver _arm_to_grip), pela
## pose atual do tronco: {"sol": [rotação do ombro, dobra do cotovelo], "turn": giro que ainda sobra para o pulso (rad),
## "miss": quanto a mão fica longe do alvo por falta de alcance (m)}. {} se o modelo não tem cotovelo.
## tools/weapon_pose_shot.tscn -- coleta otimiza usa isto para achar onde as mãos fecham certo em cada pose-chave.
static func grip_solve(r: Dictionary, side: String, target_m: Vector3, axis_m: Vector3, pole_m: Vector3,
		pole_w := GRIP_POLE_WEIGHT) -> Dictionary:
	var arm: Node3D = r["Arm" + side.to_upper()]
	var elbow: Node3D = r["Elbow" + side.to_upper()]
	if arm == null or elbow == null or r.get("hand_" + side) == null:
		return {}
	var inv := KnightLook._chain(arm.get_parent(), r.model).affine_inverse()
	var tgt := inv * target_m
	var axis := (inv.basis * axis_m).normalized()
	var pref := (inv.basis * pole_m).normalized()
	var tn := (tgt - arm.position).normalized()
	var a := tn.cross(Vector3.UP)
	if a.length() < 0.05:
		a = tn.cross(Vector3.RIGHT)
	a = a.normalized()
	var b := tn.cross(a).normalized()
	var hand: Vector3 = r["hand_" + side]
	var cost := func(ang: float) -> float:
		var pole := a * cos(ang) + b * sin(ang)
		var s := solve_arm(arm, elbow, hand, tgt, pole)
		var fore := Basis.from_euler(s[0], EULER_ORDER_YXZ) * Basis(Vector3.RIGHT, s[1])
		# o punho (eixo Z do antebraço, polegar em +Z) o mais alinhado possível com o cabo: é o giro que o pulso
		# ainda teria de fazer. Só a perpendicularidade não basta: deixava a mão virada ao contrário (palma para fora)
		return fore.z.angle_to(axis) + pole_w * pole.angle_to(pref)
	var best := 0.0
	var best_c := INF
	for i in GRIP_SWIVEL_STEPS:
		var ang := TAU * i / GRIP_SWIVEL_STEPS
		var c: float = cost.call(ang)
		if c < best_c:
			best_c = c
			best = ang
	var step := TAU / GRIP_SWIVEL_STEPS
	for _i in 6:   # refina em volta do melhor: o resultado muda suave de um quadro para o outro
		step *= 0.5
		for cand in [best - step, best + step]:
			var c: float = cost.call(cand)
			if c < best_c:
				best_c = c
				best = cand
	var sol := solve_arm(arm, elbow, hand, tgt, a * cos(best) + b * sin(best))
	var ab := Basis.from_euler(sol[0], EULER_ORDER_YXZ)
	var fore := ab * Basis(Vector3.RIGHT, sol[1])
	var reached: Vector3 = arm.position + ab * (elbow.position + Basis(Vector3.RIGHT, sol[1]) * hand)
	return {"sol": sol, "turn": fore.z.angle_to(axis), "miss": reached.distance_to(tgt)}


## Pulsos da ferramenta com as duas mãos: gira a malha de cada mão em volta do centro dela para o punho fechar no
## eixo do cabo (`dir_m`, espaço do modelo), até WRIST_MAX. `w` = peso (0 devolve as mãos ao lugar).
const WRIST_MAX := 1.2    ## mais que isso a mão viraria ao contrário: melhor o punho um pouco torto
static func _tool_wrists(r: Dictionary, dir_m: Vector3, w_all: float, w_left := -1.0) -> void:
	var model: Node3D = r.model
	r["wrist_on"] = w_all > 0.0
	for side in ["L", "R"]:
		var w := w_left if side == "L" and w_left >= 0.0 else w_all   # `w_left`: a esquerda soltou o cabo (montante correndo)
		var fore: Node3D = r.get("Elbow" + side)
		var c = r.get("hand_" + side.to_lower())
		if fore == null or c == null:
			continue
		var local := Basis.IDENTITY
		if w > 0.0:
			var fb := KnightLook._chain(fore, model).basis.orthonormalized()
			var q := Quaternion(fb.z.normalized(), dir_m.normalized())
			r["wrist_turn_" + side] = q.get_angle()   # giro total que a mão precisaria (antes do limite)
			if q.get_angle() > WRIST_MAX:
				q = Quaternion(q.get_axis().normalized(), WRIST_MAX)
			r["wrist_dev_" + side] = asin(clampf(absf(fb.y.dot(dir_m.normalized())), 0.0, 1.0))   # só a dobra
			q = Quaternion.IDENTITY.slerp(q, clampf(w, 0.0, 1.0))
			local = fb.inverse() * Basis(q) * fb
		for n in fore.get_children():
			if not (n is Node3D) or not ("Hand" in n.name):
				continue
			if not n.has_meta("wrist0"):
				n.set_meta("wrist0", n.transform)
			n.transform = Transform3D(local, (c as Vector3) - local * (c as Vector3)) * (n.get_meta("wrist0") as Transform3D)


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


## Fim de um golpe do combo com escudo: traz o giro de tronco, quadril e pulso para -PI..PI e os ângulos dos
## ombros para o Euler canônico, sem mudar a pose (só a forma de escrever o mesmo giro), para a próxima trilha
## (que começa assim) emendar e a volta à locomoção seguir pelo caminho curto.
static func unwind_twist(r: Dictionary) -> void:
	r["twist"] = wrapf(float(r.twist), -PI, PI)
	r["hip_twist"] = wrapf(float(r.hip_twist), -PI, PI)
	r["wrist_r"] = wrapf(float(r.get("wrist_r", 0.0)), -PI, PI)
	for a in ["ArmL", "ArmR"]:
		var arm: Node3D = r[a]
		arm.rotation = Basis.from_euler(arm.rotation).get_euler()


## Zera o giro de tronco e quadril na hora (fim do golpe: o giro do golpe 3 não "desgira").
static func reset_twist(r: Dictionary) -> void:
	r["twist"] = 0.0
	r["hip_twist"] = 0.0
	r.LegL.rotation.y = 0.0
	r.LegR.rotation.y = 0.0
	r.Body.rotation.y = 0.0
	if r.get("Pelvis"):
		r.Pelvis.rotation.y = 0.0
	if r.get("Chest"):
		r.Chest.rotation = Vector3.ZERO


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
	# coxa aberta para o lado (passo de lado da guarda do escudo; + = para fora em cada perna)
	r.LegL.rotation.z = lerpf(r.LegL.rotation.z, float(p.get("side_l", 0.0)), f.call("leg_l"))
	r.LegR.rotation.z = lerpf(r.LegR.rotation.z, -float(p.get("side_r", 0.0)), f.call("leg_r"))
	if r.AnkleL:
		r.AnkleL.rotation.x = r.foot_l - r.LegL.rotation.x - r.KneeL.rotation.x
		r.AnkleR.rotation.x = r.foot_r - r.LegR.rotation.x - r.KneeR.rotation.x
		r.AnkleL.rotation.z = -r.LegL.rotation.z   # sola paralela ao chão com a perna aberta
		r.AnkleR.rotation.z = -r.LegR.rotation.z
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
	# peito: segue com a velocidade da chave de tronco do mesmo eixo, para os dois mudarem juntos
	var chest: Node3D = r.get("Chest")
	if chest:
		chest.rotation.x = lerpf(chest.rotation.x, float(p.get("chest_x", 0.0)), f.call("body_x"))
		chest.rotation.y = lerpf(chest.rotation.y, float(p.get("chest_y", 0.0)), f.call("twist"))
		chest.rotation.z = lerpf(chest.rotation.z, float(p.get("chest_z", 0.0)), f.call("body_z"))
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
	_shield_ik(r, p, k)
	_tool_ik(r, p, f.call("arm_r"))
	_guard_ik(r, p)
	r["two_hand"] = lerpf(float(r.get("two_hand", 0.0)), float(p.get("two_hand", 0.0)), f.call("arm_l"))
	r["blade_up"] = lerpf(float(r.get("blade_up", 0.0)), float(p.get("blade_up", 0.0)), f.call("arm_r"))
	# ferramenta de coleta: quanto a mão direita está subida no cabo, na direção da cabeça (m; ver hold_weapon_upright)
	r["tool_slide"] = lerpf(float(r.get("tool_slide", 0.0)), float(p.get("tool_slide", 0.0)), f.call("arm_r"))
	# pulsos: o modelo não tem pivô; o suporte da arma gira com este valor (hold_weapon_upright)
	r["wrist_l"] = lerpf(float(r.get("wrist_l", 0.0)), p.wrist_l, f.call("wrist_l"))
	r["wrist_r"] = lerpf(float(r.get("wrist_r", 0.0)), p.wrist_r, f.call("wrist_r"))
	r.ArmL.rotation = r.ArmL.rotation.lerp(p.arm_l, f.call("arm_l"))
	r.ArmR.rotation = r.ArmR.rotation.lerp(p.arm_r, f.call("arm_r"))
	if r.ElbowL:
		r.ElbowL.rotation.x = lerpf(r.ElbowL.rotation.x, p.elbow_l, f.call("elbow_l"))
		r.ElbowR.rotation.x = lerpf(r.ElbowR.rotation.x, p.elbow_r, f.call("elbow_r"))
	_shield_orient(r)
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
	if not look.get("tool", false) and not look.get("great", false) and r.get("wrist_on", false):
		_tool_wrists(r, Vector3.UP, 0.0)   # guardou a ferramenta: mãos de volta ao lugar
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
	# Martelo de Energia: espada erguida para o céu (KnightMoves.HAMMER_BLADE_DIR), o fio para os lados
	var bu: float = r.get("blade_up", 0.0)
	# o resto do código só mexe no rotation.x do suporte: guarda o y/z de repouso para devolver no fim
	if bu > 0.001 and not r.has("blade_rest"):
		r["blade_rest"] = Vector2(holder.rotation.y, holder.rotation.z)
	elif bu <= 0.001 and r.has("blade_rest"):
		var rest: Vector2 = r.blade_rest
		holder.rotation = Vector3(holder.rotation.x, rest.x, rest.y)
		r.erase("blade_rest")
	if bu > 0.001 and not look.get("tool", false) and not look.get("great", false):
		var dir := KnightMoves.HAMMER_BLADE_DIR.normalized()
		var edge := Vector3(0.0, 0.0, 1.0)
		edge = (edge - dir * edge.dot(dir)).normalized()
		var gx := (-edge).cross(dir).normalized()
		var want := Basis(gx, dir.cross(gx).normalized(), dir).orthonormalized()
		var parent_xf := KnightLook._chain(holder.get_parent(), r.model)
		var b := (parent_xf.basis.orthonormalized().inverse() * want).orthonormalized()
		holder.basis = Basis(Quaternion(holder.basis.orthonormalized()).slerp(Quaternion(b), clampf(bu, 0.0, 1.0)))
	var tw: float = r.get("tool_w", 0.0)
	var great: bool = look.get("great", false)   # montante: segue a trajetória como as ferramentas
	if great:
		var lw: float = float(r.get("tool_left", 1.0))
		if tw > 0.001 and r.has("tool_dir"):
			_orient_by_path(holder, r, tw)
		if float(r.get("two_hand", 0.0)) > 0.01 and tw <= 0.001:
			_staff_left_hand(holder, r, KnightMoves.GREAT_LEFT_GRIP, KnightMoves.TOOL_POLE_L)   # habilidades
		var gw := maxf(tw * lw, float(r.get("two_hand", 0.0)))
		_tool_fit_hands(holder, r, gw, KnightMoves.GREAT_GRIP)
		_tool_wrists(r, (KnightLook._chain(holder.get_parent(), r.model).basis * holder.basis).z, maxf(tw, gw), gw)
		return
	if look.get("tool", false) and tw > 0.001 and r.has("tool_dir"):
		# conduzida pela trajetória (_tool_ik): cabo em `tool_dir` e gume em `tool_edge`. O gume do machado é +X do
		# suporte (AXE_ROLL); o da picareta, -Y
		var dir: Vector3 = r.tool_dir
		var edge: Vector3 = r.tool_edge
		var gx := edge if holder.has_meta("axe") else (-edge).cross(dir).normalized()
		var want := Basis(gx, dir.cross(gx).normalized(), dir).orthonormalized()
		var parent_xf := KnightLook._chain(holder.get_parent(), r.model)
		var b := (parent_xf.basis.orthonormalized().inverse() * want).orthonormalized()
		holder.basis = Basis(Quaternion(holder.basis.orthonormalized()).slerp(Quaternion(b), clampf(tw, 0.0, 1.0)))
	if look.get("tool", false) and holder.has_meta("grip0"):
		# a mão direita sobe pelo cabo (no preparo fica perto da cabeça) e desce até a esquerda no golpe: a mão
		# fica onde está e é a ferramenta que corre no eixo do cabo
		holder.position = (holder.get_meta("grip0") as Vector3) - holder.basis.z * float(r.get("tool_slide", 0.0))
	if float(r.get("two_hand", 0.0)) > 0.01 and look.get("tool", false) and tw <= 0.001:
		_staff_left_hand(holder, r, KnightMoves.TOOL_LEFT_GRIP, KnightMoves.TOOL_POLE_L)   # picareta/machado
	if look.get("tool", false):
		var hands_w := maxf(tw, float(r.get("two_hand", 0.0)))
		_tool_fit_hands(holder, r, hands_w)
		_tool_wrists(r, (KnightLook._chain(holder.get_parent(), r.model).basis * holder.basis).z, hands_w)


## Ferramenta com as duas mãos: o IK leva as mãos perto do cabo, mas não exatamente nele (alcance, centro da mão x
## palma). Depois dos braços postos, o cabo é girado para passar pela mão esquerda (a direita já é a origem do
## suporte) e corre no próprio eixo até a esquerda ficar no fim dele (TOOL_LEFT_GRIP), sem perder o giro do gume.
## `w` = peso das duas mãos.
static func _tool_fit_hands(holder: Node3D, r: Dictionary, w: float, fixed_grip := -1.0) -> void:
	if w <= 0.01 or r.get("hand_l") == null or not holder.has_meta("grip0"):
		return
	var model: Node3D = r.model
	var parent_xf := KnightLook._chain(holder.get_parent(), model)
	var right: Vector3 = parent_xf * (holder.get_meta("grip0") as Vector3)
	var left: Vector3 = KnightLook._chain(r.ElbowL, model) * (r.hand_l as Vector3)
	var span := right - left
	if span.length() < 0.05:
		return
	var want_dir := span.normalized()
	var cur := (parent_xf.basis * holder.basis).orthonormalized()   # suporte no espaço do modelo
	var fit := Basis(Quaternion(cur.z.normalized(), want_dir)) * cur
	var mixed := Basis(Quaternion(cur).slerp(Quaternion(fit.orthonormalized()), clampf(w, 0.0, 1.0)))
	holder.basis = (parent_xf.basis.orthonormalized().inverse() * mixed).orthonormalized()
	if fixed_grip >= 0.0:
		return   # montante: as duas mãos têm lugar certo no cabo, a lâmina não corre na mão
	var slide := clampf(span.length() + KnightMoves.TOOL_LEFT_GRIP.z, 0.0, 0.45)
	r["tool_slide"] = lerpf(float(r.get("tool_slide", 0.0)), slide, clampf(w, 0.0, 1.0))
	holder.position = (holder.get_meta("grip0") as Vector3) - holder.basis.z * float(r.tool_slide)


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
## `grip`/`pole`: ponto do cabo no espaço do suporte e direção do cotovelo (a ferramenta de coleta usa os seus).
static func _staff_left_hand(holder: Node3D, r: Dictionary, grip := KnightMoves.STAFF_LEFT_GRIP,
		pole := KnightMoves.STAFF_POLE_L) -> void:
	var model: Node3D = r.model
	var target: Vector3 = KnightLook._chain(holder, model) * grip
	var sol := arm_ik(r, "l", target, pole)
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
	var h: float = (r.thigh * cos(th) + r.shin * cos(th + kn)) * cos(leg.rotation.z)   # perna aberta encurta
	if ankle:
		var f := th + kn + ankle.rotation.x
		var a: float = r.ankle_h
		h += maxf(a * cos(f) + float(r.toe) * sin(f), a * cos(f) - float(r.heel) * sin(f))
	return h

