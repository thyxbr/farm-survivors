class_name KnightMoves
extends RefCounted
## Golpes do cavaleiro: poses-chave e tempos, tocados por KnightAnim.play_track.
##
## Cada trilha é uma lista [t, {articulações}, curva] com t em fração do golpe (0..1).
## O começo e o fim da trilha são a pose de locomoção; articulação ausente numa chave é atravessada.
## Curvas: "in" acelera até a chave (golpe), "out" chega desacelerando (follow-through), "io" suave.
##
## Articulações (sinais em knight_anim.gd): arm_X = Vector3 (x: frente/trás, y: gira para o lado,
## z: abre para o lado), elbow_X (< 0 dobra), wrist_X (gira a arma; > 0 inclina a ponta para a
## frente/baixo), twist (> 0 o ombro direito vem para a frente), body_x (> 0 inclina para a frente),
## head_x / head_y, leg_X (< 0 coxa à frente), knee_X (> 0 dobra).
##
## Momento do acerto (definido em player.gd): espada em 0,42 do golpe, cajado em 0,35.
## A chave de impacto de cada trilha fica nesse instante.

# ------------------------------------------------------------------ espada (0,42 s / 0,42 s / 0,6 s)
const SWORD := [
	[  # 1: diagonal de cima, do ombro direito para o quadril esquerdo
		[0.26, {"arm_r": Vector3(-2.55, -0.35, -0.45), "elbow_r": -1.55, "wrist_r": -0.6, "twist": -0.5,
			"body_x": -0.12, "body_z": 0.06, "head_y": 0.25,
			"arm_l": Vector3(-0.75, 0.25, 0.3), "elbow_l": -1.25,
			"leg_l": -0.1, "knee_l": 0.12, "leg_r": 0.18, "knee_r": 0.32}],
		[0.36, {"arm_r": Vector3(-2.15, 0.15, -0.2), "elbow_r": -0.8, "wrist_r": 0.7, "twist": -0.05}, "in"],
		[0.42, {"arm_r": Vector3(-0.95, 0.55, 0.3), "elbow_r": -0.12, "wrist_r": 1.7, "twist": 0.45,
			"body_x": 0.3, "body_z": -0.05, "head_y": -0.2,
			"arm_l": Vector3(0.25, -0.2, 0.45), "elbow_l": -0.55,
			"leg_l": -0.52, "knee_l": 0.55, "leg_r": 0.35, "knee_r": 0.3}, "in"],
		[0.56, {"arm_r": Vector3(-0.65, 0.7, 0.42), "elbow_r": -0.22, "wrist_r": 1.85, "twist": 0.55,
			"body_x": 0.32}, "out"],
	],
	[  # 2: horizontal de volta (revés), da esquerda para a direita
		[0.24, {"arm_r": Vector3(-1.35, 0.95, 0.35), "elbow_r": -1.7, "wrist_r": 0.3, "twist": 0.55,
			"body_x": 0.05, "head_y": -0.3,
			"arm_l": Vector3(-0.3, -0.3, 0.6), "elbow_l": -0.9,
			"leg_l": -0.15, "knee_l": 0.3, "leg_r": 0.12, "knee_r": 0.15}],
		[0.35, {"arm_r": Vector3(-1.45, 0.3, 0.0), "elbow_r": -0.8, "wrist_r": 1.2, "twist": 0.15}, "in"],
		[0.42, {"arm_r": Vector3(-1.4, -0.8, 0.0), "elbow_r": -0.1, "wrist_r": 1.45, "twist": -0.5,
			"body_x": 0.18, "head_y": 0.25,
			"arm_l": Vector3(-0.6, 0.4, 0.35), "elbow_l": -1.1,
			"leg_l": -0.42, "knee_l": 0.45, "leg_r": 0.3, "knee_r": 0.32}, "in"],
		[0.56, {"arm_r": Vector3(-1.3, -1.1, 0.0), "elbow_r": -0.2, "wrist_r": 1.5, "twist": -0.62}, "out"],
	],
	[  # 3: giro com a lâmina estendida (o tronco dá uma volta: ver SPIN_START/SPIN_END)
		[0.2, {"arm_r": Vector3(-1.3, 0.9, 0.3), "elbow_r": -1.5, "wrist_r": 0.6, "twist": 0.55,
			"body_x": 0.15, "head_y": -0.3,
			"arm_l": Vector3(-0.4, 0.0, 0.5), "elbow_l": -1.0,
			"leg_l": -0.3, "knee_l": 0.65, "leg_r": 0.3, "knee_r": 0.65}],
		[0.32, {"arm_r": Vector3(-1.5, -0.2, -0.75), "elbow_r": -0.1, "wrist_r": 1.45, "twist": 0.0,
			"arm_l": Vector3(-0.2, 0.0, 1.1), "elbow_l": -0.3, "head_y": 0.0}, "in"],
		[0.75, {"arm_r": Vector3(-1.5, -0.2, -0.75), "elbow_r": -0.1, "wrist_r": 1.45,
			"leg_l": -0.32, "knee_l": 0.7, "leg_r": 0.32, "knee_r": 0.7}, "lin"],
		[0.85, {"arm_r": Vector3(-1.2, -0.6, -0.6), "elbow_r": -0.3, "wrist_r": 1.2, "body_x": 0.2}, "out"],
	],
]
const SPIN_START := 0.24        ## o giro começa logo depois da antecipação
const SPIN_END := 0.78          ## e termina aqui (uma volta inteira)

# ------------------------------------------------------------------ soco, sem arma (0,3 s / 0,32 s / 0,5 s)
## Combo de boxe: jab de esquerda, direto de direita e uppercut de direita. Entre um e outro as mãos voltam
## à guarda, os punhos na frente do queixo. O acerto é em 0,42, como na espada.
const PUNCH_GUARD := {"arm_l": Vector3(-0.8, 0.3, 0.08), "elbow_l": -2.15, "arm_r": Vector3(-0.7, -0.3, -0.08),
	"elbow_r": -2.2, "wrist_l": 0.0, "wrist_r": 0.0}
const PUNCH_STANCE := {"leg_l": -0.2, "knee_l": 0.3, "leg_r": 0.18, "knee_r": 0.35}
const PUNCH := [
	[  # 1: jab de esquerda, rápido e reto, o ombro esquerdo vai à frente
		[0.2, [PUNCH_GUARD, PUNCH_STANCE, {"twist": 0.12, "body_x": 0.05}]],
		[0.42, [PUNCH_GUARD, {"arm_l": Vector3(-1.6, 0.35, 0.02), "elbow_l": -0.05, "twist": -0.4,
			"body_x": 0.14, "head_y": 0.2, "leg_l": -0.35, "knee_l": 0.4, "leg_r": 0.25, "knee_r": 0.3}], "in"],
		[0.56, [PUNCH_GUARD, {"arm_l": Vector3(-1.55, 0.35, 0.02), "elbow_l": -0.12, "twist": -0.38}], "out"],
		[0.85, [PUNCH_GUARD, PUNCH_STANCE, {"twist": 0.0}], "io"],
	],
	[  # 2: direto de direita, o quadril gira e o pé de trás empurra
		[0.2, [PUNCH_GUARD, PUNCH_STANCE, {"twist": -0.3, "body_x": 0.02, "head_y": 0.15}]],
		[0.42, [PUNCH_GUARD, {"arm_r": Vector3(-1.62, -0.3, -0.02), "elbow_r": -0.05, "twist": 0.65,
			"body_x": 0.2, "head_y": -0.25, "leg_l": -0.4, "knee_l": 0.45, "leg_r": 0.32, "knee_r": 0.2}], "in"],
		[0.56, [PUNCH_GUARD, {"arm_r": Vector3(-1.58, -0.3, -0.02), "elbow_r": -0.12, "twist": 0.62,
			"body_x": 0.2}], "out"],
		[0.85, [PUNCH_GUARD, PUNCH_STANCE, {"twist": 0.0, "body_x": 0.05}], "io"],
	],
	[  # 3: uppercut de direita: agacha com o punho baixo e sobe esticando as pernas
		[0.24, [PUNCH_GUARD, {"arm_r": Vector3(-0.35, -0.1, -0.2), "elbow_r": -1.55, "twist": -0.4,
			"body_x": 0.3, "body_y": -0.07, "head_y": 0.2,
			"leg_l": -0.45, "knee_l": 0.85, "leg_r": 0.1, "knee_r": 0.8}]],
		[0.42, [PUNCH_GUARD, {"arm_r": Vector3(-1.4, -0.45, -0.05), "elbow_r": -1.75, "twist": 0.55,
			"body_x": -0.1, "body_y": 0.02, "head_x": -0.12, "head_y": -0.2,
			"leg_l": -0.3, "knee_l": 0.2, "leg_r": 0.25, "knee_r": 0.1}], "in"],
		[0.62, [PUNCH_GUARD, {"arm_r": Vector3(-1.45, -0.45, -0.05), "elbow_r": -1.8, "twist": 0.5,
			"body_x": -0.08}], "out"],
		[0.88, [PUNCH_GUARD, PUNCH_STANCE, {"twist": 0.0}], "io"],
	],
]

# ------------------------------------------------------------------ cajado (0,4 s / 0,4 s / 0,6 s)
## Inclinação do cajado: o suporte desfaz 3/4 do giro do braço (KnightLook.COUNTER), então o cajado tomba
## 0,25 * (arm_r.x + elbow_r) + wrist_r para a frente (0 = de pé, > 0 = gema à frente, ~1,57 = deitado).
## O golpe do cajado é um gesto de "reger" o feitiço: a mão quase não viaja (fica na frente do peito com o
## cotovelo dobrado) e quem se move é a vara, girando no punho: começa de pé com a gema um pouco para trás
## (STAFF_WINDUP), tomba rápido para a frente até a gema apontar o alvo (STAFF_AIM, ~55° somando a inclinação
## do tronco, que também tomba a vara; a mão sai um pouco para fora, a ponta de baixo passa ao lado do
## quadril) e volta um pouco no
## coice (STAFF_RECOIL). Antes o braço esticava inteiro com a vara deitada, como um rifle.
## O disparo (0,35 do golpe) e a bola de fogo saem da gema, então ela fica parada na pose de mira no disparo.
const STAFF_WINDUP := {"arm_r": Vector3(-0.6, 0.2, -0.22), "elbow_r": -1.05, "wrist_r": 0.06,
	"twist": -0.25, "body_x": -0.06, "head_y": 0.15,
	"arm_l": Vector3(-0.7, 0.3, 0.2), "elbow_l": -1.3}
const STAFF_AIM := {"arm_r": Vector3(-1.05, 0.05, -0.2), "elbow_r": -0.42, "wrist_r": 1.3,
	"twist": 0.12, "body_x": 0.14, "head_y": -0.1,
	"arm_l": Vector3(-0.95, -0.15, 0.3), "elbow_l": -1.0}
## Passo à frente ao mirar (só com o jogador parado).
const STAFF_AIM_LEGS := {"leg_l": -0.32, "knee_l": 0.32, "leg_r": 0.22, "knee_r": 0.2}
## Coice depois do disparo: a vara volta um pouco para cima (a gema sobe) e a mão fica onde estava.
const STAFF_RECOIL := {"arm_r": Vector3(-1.0, 0.05, -0.2), "elbow_r": -0.5, "wrist_r": 0.95, "body_x": 0.06,
	"twist": 0.15}
## Cajado carregado (KnightAnim.weapon_carry), parado/andando e correndo: braço um pouco à frente e aberto
## (a vara não raspa na perna), cotovelo dobrado, só 30% do balanço do braço; `tilt` = inclinação do cajado
## (> 0 gema à frente). Correndo vai na diagonal à frente, com a mão no quadril.
const STAFF_CARRY := {"arm": Vector3(-0.14, 0.0, -0.17), "arm_run": Vector3(-0.55, 0.12, -0.3),
	"elbow": -0.55, "elbow_run": -1.1, "tilt": 0.08, "tilt_run": 0.4, "swing": 0.3}
## Duas mãos no cajado: onde a mão esquerda pega (no espaço do suporte; a direita fica na origem) e para
## onde aponta o cotovelo esquerdo (espaço do modelo).
## Cajado tombado para a frente: quanto a vara gira no punho para cruzar na diagonal (rad; a ponta de baixo
## vai para fora do quadril). Entra aos poucos com a inclinação (KnightAnim.hold_weapon_upright).
const STAFF_CROSS := 0.45
const STAFF_LEFT_GRIP := Vector3(0.0, -0.3, 0.0)
const STAFF_POLE_L := Vector3(1.0, -0.4, -0.3)
const STAFF := [
	[  # 1: ergue a vara de pé junto ao ombro e tomba a gema para o alvo
		[0.16, [STAFF_WINDUP, {"leg_r": 0.15, "knee_r": 0.3}]],
		[0.3, [STAFF_AIM, STAFF_AIM_LEGS], "in"],
		[0.37, [STAFF_AIM], "lin"],   # firme no disparo
		[0.48, [STAFF_RECOIL], "out"],
	],
	[  # 2: leva a vara para a direita, de pé, e tomba a gema para o alvo varrendo para o centro
		[0.16, {"arm_r": Vector3(-0.75, -0.7, -0.35), "elbow_r": -0.85, "wrist_r": 0.3, "twist": -0.45,
			"body_x": 0.0, "head_y": 0.35,
			"arm_l": Vector3(-1.1, 0.6, 0.1), "elbow_l": -1.6,
			"leg_l": -0.1, "knee_l": 0.25, "leg_r": 0.15, "knee_r": 0.25}],
		[0.3, [STAFF_AIM, STAFF_AIM_LEGS], "in"],
		[0.37, [STAFF_AIM], "lin"],
		[0.48, [STAFF_RECOIL], "out"],
	],
	[  # 3: ergue o cajado de pé com as duas mãos e tomba a gema para o alvo (três disparos)
		[0.22, {"arm_r": Vector3(-2.4, 0.1, -0.1), "elbow_r": -0.6, "wrist_r": 0.35,
			"arm_l": Vector3(-2.6, -0.1, 0.25), "elbow_l": -0.75, "body_x": -0.22, "head_x": -0.1,
			"twist": -0.1, "leg_l": -0.05, "knee_l": 0.15, "knee_r": 0.15}],
		[0.32, [STAFF_AIM, {"arm_r": Vector3(-1.2, -0.05, -0.1), "elbow_r": -0.35, "wrist_r": 1.2, "body_x": 0.35, "head_x": -0.15,
			"arm_l": Vector3(-1.25, -0.3, 0.25), "elbow_l": -0.3,
			"leg_l": -0.38, "knee_l": 0.7, "leg_r": 0.3, "knee_r": 0.55}], "in"],
		[0.4, [STAFF_AIM, {"arm_r": Vector3(-1.2, -0.05, -0.1), "elbow_r": -0.35, "wrist_r": 1.2, "body_x": 0.35,
			"arm_l": Vector3(-1.25, -0.3, 0.25), "elbow_l": -0.3}], "lin"],
		[0.6, [STAFF_RECOIL, {"body_x": 0.25}], "out"],
	],
]

# ------------------------------------------------------------------ magias
const CAST_TIME := 0.45         ## duração da pose de magia (s)
## Fração de CAST_TIME em que a bola de fogo sai (da gema do cajado, ou da mão esquerda sem
## cajado): o tempo de apontar antes do disparo.
const CAST_RELEASE := 0.27
const CAST := {
	# bola de fogo sem cajado: a mão esquerda recua junto ao peito e empurra a palma para a frente
	"fireball": [
		[0.12, {"arm_l": Vector3(-0.85, -0.35, 0.55), "elbow_l": -1.9, "twist": 0.35, "body_x": -0.06,
			"head_y": -0.2}],
		[0.27, {"arm_l": Vector3(-1.55, 0.3, 0.05), "elbow_l": -0.05, "twist": -0.3, "body_x": 0.18,
			"head_y": 0.15, "arm_r": Vector3(-0.1, 0.0, -0.35), "elbow_r": -0.4,
			"leg_l": -0.3, "knee_l": 0.3, "leg_r": 0.2, "knee_r": 0.15}, "in"],
		[0.65, {"arm_l": Vector3(-1.5, 0.3, 0.05), "elbow_l": -0.1}, "out"],
	],
	# cura: braços se abrem para o alto, peito para cima, olhar para o céu
	"heal": [
		[0.4, {"arm_l": Vector3(-2.5, 0.0, 0.75), "elbow_l": -0.45, "arm_r": Vector3(-0.6, 0.0, -0.8),
			"elbow_r": -0.5, "body_x": -0.18, "head_x": -0.4, "body_y": 0.02}, "out"],
		[0.75, {"arm_l": Vector3(-2.55, 0.0, 0.8), "elbow_l": -0.4, "head_x": -0.45}],
	],
	# nova de gelo: ergue os dois braços e golpeia o chão agachando
	"frost_nova": [
		[0.2, {"arm_l": Vector3(-2.7, 0.0, 0.35), "elbow_l": -0.9, "arm_r": Vector3(-2.3, 0.0, -0.3),
			"elbow_r": -0.6, "body_x": -0.18, "knee_l": 0.1, "knee_r": 0.1}],
		[0.36, {"arm_l": Vector3(-0.45, 0.0, 0.55), "elbow_l": -0.1, "arm_r": Vector3(-0.45, 0.0, -0.55),
			"elbow_r": -0.1, "body_x": 0.5, "head_x": -0.25,
			"leg_l": -0.6, "knee_l": 1.0, "leg_r": -0.3, "knee_r": 0.8}, "in"],
		[0.7, {"body_x": 0.48, "leg_l": -0.58, "knee_l": 0.95, "leg_r": -0.3, "knee_r": 0.78}],
	],
}
## Com cajado, a bola de fogo usa o gesto do golpe: ergue a vara, tomba a gema para o alvo (dispara em
## CAST_RELEASE) e dá o coice.
const CAST_STAFF := {
	"fireball": [
		[0.12, [STAFF_WINDUP]],
		[0.24, [STAFF_AIM, STAFF_AIM_LEGS], "in"],
		[0.36, [STAFF_AIM], "lin"],
		[0.55, [STAFF_RECOIL], "out"],
	],
}

# ------------------------------------------------------------------ arco
## Referência: o pack "Longbow Aiming" do Mixamo (posições dos ossos medidas quadro a quadro). Mirando, o
## quadril fica ~90° de lado para o alvo e os ombros também; a cabeça vira de volta para o alvo; o braço do
## arco fica quase reto (~167°); a mão da corda ancora ~11 cm abaixo da base da cabeça, no canto do queixo,
## com o cotovelo na altura do ombro e bem atrás. Ao soltar, a mão escapa ~0,4 m para trás e os braços
## descem. Aqui só o tronco vem destas poses; as mãos vão por IK (KnightAnim._bow_ik).
const BOW_NOCK := {   # arco erguido, flecha encaixada, corda ainda frouxa
	"twist": -1.05, "head_y": 0.95, "body_x": 0.03, "wrist_l": 0.0,
}
const BOW_FULL := {   # corda toda puxada: de lado para o alvo
	"twist": -1.3, "head_y": 1.2, "body_x": 0.0,
}
const BOW_HIP_SHARE := 0.65         ## quanto do giro dos ombros o quadril faz parado (o corpo todo de lado)
const BOW_HIP_SHARE_MOVING := 0.25  ## andando: o quadril gira menos, as pernas seguem para a frente
## Âncora da corda no espaço da cabeça (pivô no pescoço): canto direito do queixo.
const BOW_ANCHOR := Vector3(-0.075, 0.04, 0.09)
const BOW_GRIP_DROP := 0.04         ## a flecha passa este tanto acima do centro da mão do arco (m)
const BOW_ARM_STRETCH := 0.97       ## fração do alcance do braço do arco (quase reto, sem travar)
const BOW_BRACE := 0.17             ## da corda frouxa ao punho do arco (m)
## Centro da mão da corda em relação ao encaixe da flecha (m): x para fora, y para baixo, z para trás.
const BOW_FINGERS := Vector3(0.03, 0.03, 0.045)
const BOW_POLE_L := Vector3(0.5, -1.0, 0.0)    ## cotovelo do arco: para fora e para baixo
const BOW_POLE_R := Vector3(-0.6, 0.25, -1.0)  ## cotovelo da corda: alto, para trás e para fora
const BOW_CANT := 0.1               ## topo do arco tomba um pouco para fora (rad)
const BOW_LOOSE_DOWN := 0.2         ## arco solto (deitado): a ponta da frente um pouco para baixo (rad)
## Arco carregado (KnightAnim.weapon_carry): parado, braço reto (`elbow_idle`); andando, o braço do arco
## balança pela metade com o cotovelo dobrado.
const BOW_CARRY := {"arm": Vector3(-0.15, 0.0, 0.12), "swing": 0.5, "elbow_idle": -0.08, "elbow": -0.7,
	"elbow_run": -1.1}
const BOW_RELEASE_HOLD := 0.35      ## fração da recuperação em que o arco ainda fica na mira
const BOW_RELEASE_BACK := 0.16      ## quanto a mão da corda escapa para trás da âncora ao soltar (m)
const BOW_RELEASE_SPEED := 3.0      ## a mão da corda escapa rápido (multiplica a suavização)
const GALE_OVERDRAW := 0.1          ## Vendaval: a corda passa da âncora este tanto com a carga cheia (m)
const BOW_TREMBLE := 0.004      ## tremor da mão do arco com a corda toda puxada (m)
const BOW_RAISE_SPEED := 2.2    ## multiplica a suavização ao erguer o arco (mais rápido que andar)
## Flecha do Vendaval (KnightAnim.bow_gale_pose): agacha com a perna do arco à frente, tronco para trás.
const GALE_KNEE := 1.15         ## dobra dos joelhos com a carga cheia (rad)
const GALE_THIGH_L := -0.75     ## coxa da frente (perna do arco)
const GALE_THIGH_R := -0.25     ## coxa de trás (com o joelho a 0,9 as duas pernas ficam com a mesma altura)
const GALE_LEAN := -0.5         ## tronco inclinado para trás (rad; body_x > 0 é para a frente)
const GALE_CROUCH_Y := -0.17    ## o quadril desce (m), além do que as pernas dobradas já baixam
const GALE_TREMBLE := 0.022     ## tremor da mão do arco com a carga cheia do Vendaval (m)
const GALE_RECOIL := -0.3       ## tranco extra do tronco para trás no disparo (rad)
## Chuva de Meteoros (KnightAnim.meteor_pose): o cajado erguido acima da cabeça com as duas mãos, o tronco
## arqueado para trás, o olhar no céu e as pernas abertas firmando o corpo.
const METEOR_RAISE := {
	"arm_r": Vector3(-2.4, -0.1, -0.2), "elbow_r": -0.6, "wrist_r": 0.65,
	"arm_l": Vector3(-2.6, 0.15, 0.32), "elbow_l": -0.75, "wrist_l": 0.0,
	"twist": -0.12, "body_x": -0.22, "body_y": -0.04, "head_x": -0.5, "head_y": 0.0,
	"leg_l": -0.32, "knee_l": 0.38, "leg_r": 0.26, "knee_r": 0.3,
}
const METEOR_TREMBLE := 0.045   ## tremor dos braços e do tronco canalizando (rad)
const METEOR_RAISE_SPEED := 1.4 ## multiplica a suavização ao erguer o cajado
# ------------------------------------------------------------------ habilidades da espada
## Investida (SwordAbilities.CHARGE_TIME = 0,6 s): preparo até 0,25 (agacha, espada para trás),
## avanço até 0,67 (estocada com a lâmina à frente, em investida) e recuperação.
const CHARGE := [
	[0.2, {"arm_r": Vector3(0.75, 0.25, -0.35), "elbow_r": -1.1, "wrist_r": 1.2, "twist": -0.6,
		"body_x": 0.42, "body_y": -0.08, "head_x": -0.3, "head_y": 0.3,
		"arm_l": Vector3(-0.9, -0.3, 0.35), "elbow_l": -0.9,
		"leg_l": -0.75, "knee_l": 1.15, "leg_r": 0.35, "knee_r": 0.95}, "out"],
	[0.3, {"arm_r": Vector3(-1.35, 0.1, -0.05), "elbow_r": -0.08, "wrist_r": 1.55, "twist": 0.45,
		"body_x": 0.5, "body_y": -0.05, "head_x": -0.35, "head_y": -0.15,
		"arm_l": Vector3(0.7, 0.0, 0.45), "elbow_l": -0.4,
		"leg_l": -0.95, "knee_l": 0.55, "leg_r": 0.65, "knee_r": 0.35}, "in"],
	[0.66, {"arm_r": Vector3(-1.4, 0.05, -0.05), "elbow_r": -0.05, "wrist_r": 1.6, "twist": 0.5,
		"body_x": 0.48, "arm_l": Vector3(0.75, 0.0, 0.5), "elbow_l": -0.35,
		"leg_l": -0.9, "knee_l": 0.6, "leg_r": 0.6, "knee_r": 0.4}, "lin"],
	# chegada: a estocada vira um corte, da frente/esquerda para a direita (o efeito de FXToon.CHARGE_CUT
	# segue este caminho: mexeu aqui, meça a lâmina de novo no vfx_lab)
	[0.75, {"arm_r": Vector3(-1.4, -0.8, 0.0), "elbow_r": -0.1, "wrist_r": 1.45, "twist": -0.5,
		"body_x": 0.3, "head_y": 0.25, "arm_l": Vector3(-0.6, 0.4, 0.35), "elbow_l": -1.1,
		"leg_l": -0.55, "knee_l": 0.7, "leg_r": 0.3, "knee_r": 0.3}, "in"],
	[0.9, {"arm_r": Vector3(-1.3, -1.1, 0.0), "elbow_r": -0.2, "wrist_r": 1.5, "twist": -0.62,
		"body_x": 0.2}, "out"],
]

## Golpe Sísmico (SwordAbilities.QUAKE_TIME = 0,65 s): ergue a espada com as duas mãos até 0,5
## (o pulinho), crava no chão em 0,54 (impacto aos 0,35 s) e segura a pose até o fim.
const QUAKE := [
	[0.5, {"arm_r": Vector3(-2.75, -0.1, -0.25), "elbow_r": -0.9, "wrist_r": -0.4, "twist": -0.3,
		"body_x": -0.28, "head_x": -0.25, "head_y": 0.0,
		"arm_l": Vector3(-2.6, 0.15, 0.3), "elbow_l": -0.8,
		"leg_l": -0.25, "knee_l": 0.55, "leg_r": 0.2, "knee_r": 0.55}, "out"],
	[0.56, {"arm_r": Vector3(-0.95, 0.05, -0.1), "elbow_r": -0.1, "wrist_r": 1.7, "twist": 0.3,
		"body_x": 0.55, "head_x": 0.15,
		"arm_l": Vector3(-0.85, -0.1, 0.25), "elbow_l": -0.2,
		"leg_l": -0.6, "knee_l": 0.8, "leg_r": 0.4, "knee_r": 0.6}, "in"],
	[0.8, {"arm_r": Vector3(-0.9, 0.05, -0.1), "elbow_r": -0.1, "wrist_r": 1.75, "twist": 0.3,
		"body_x": 0.5, "arm_l": Vector3(-0.8, -0.1, 0.25), "elbow_l": -0.2,
		"leg_l": -0.55, "knee_l": 0.75, "leg_r": 0.35, "knee_r": 0.55}, "lin"],
]

## Pose curta das habilidades de buff (0,5 s): braços erguidos e volta.
const BUFF := [
	[0.35, {"arm_r": Vector3(-2.5, 0.0, -0.3), "elbow_r": -0.5, "arm_l": Vector3(-2.3, 0.0, 0.3), "elbow_l": -0.5,
		"body_x": -0.15, "head_x": -0.2}, "out"],
	[0.7, {"arm_r": Vector3(-2.5, 0.0, -0.3), "elbow_r": -0.5, "arm_l": Vector3(-2.3, 0.0, 0.3), "elbow_l": -0.5,
		"body_x": -0.15, "head_x": -0.2}, "lin"],
]

## Turbilhão (SwordAbilities.WHIRL_TIME = 2,1 s): preparo até 0,19 (agacha, espada para trás com as
## duas mãos, tronco torcido), giro de 0,19 a 0,905 (braços estendidos, lâmina na horizontal, tronco
## inclinado; o modelo inteiro gira em SwordAbilities) e golpe final para baixo, no chão em 0,943.
const WHIRL := [
	[0.17, {"arm_r": Vector3(0.5, 0.3, -0.55), "elbow_r": -0.6, "wrist_r": -2.8, "twist": -0.95,
		"body_x": 0.4, "body_y": -0.14, "body_z": 0.08, "head_x": -0.3, "head_y": 0.65,
		"arm_l": Vector3(0.15, -0.6, -0.35), "elbow_l": -1.1,
		"leg_l": -0.7, "knee_l": 1.2, "leg_r": 0.5, "knee_r": 1.0}, "out"],
	[0.24, {"arm_r": Vector3(-1.75, -0.2, -0.75), "elbow_r": -0.1, "wrist_r": 1.45, "twist": 0.1,
		"body_x": 0.32, "body_y": -0.12, "body_z": 0.16, "head_x": -0.1, "head_y": 0.0,
		"arm_l": Vector3(-0.2, 0.0, 1.1), "elbow_l": -0.3,
		"leg_l": -0.45, "knee_l": 0.95, "leg_r": 0.4, "knee_r": 0.9}, "in"],
	[0.9, {"arm_r": Vector3(-1.75, -0.2, -0.75), "elbow_r": -0.1, "wrist_r": 1.45, "twist": 0.1,
		"body_x": 0.32, "body_y": -0.12, "body_z": 0.16,
		"arm_l": Vector3(-0.2, 0.0, 1.1), "elbow_l": -0.3,
		"leg_l": -0.45, "knee_l": 0.95, "leg_r": 0.4, "knee_r": 0.9}, "lin"],
	[0.925, {"arm_r": Vector3(-2.7, -0.1, -0.25), "elbow_r": -0.8, "wrist_r": -0.3, "twist": -0.25,
		"body_x": -0.2, "body_z": 0.0, "head_x": -0.2,
		"arm_l": Vector3(-2.55, 0.15, 0.3), "elbow_l": -0.8}, "out"],
	[0.943, {"arm_r": Vector3(-0.95, 0.05, -0.1), "elbow_r": -0.1, "wrist_r": 1.7, "twist": 0.3,
		"body_x": 0.55, "body_y": -0.12, "head_x": 0.15,
		"arm_l": Vector3(-0.85, -0.1, 0.25), "elbow_l": -0.2,
		"leg_l": -0.65, "knee_l": 0.9, "leg_r": 0.45, "knee_r": 0.7}, "in"],
	[0.985, {"arm_r": Vector3(-0.9, 0.05, -0.1), "elbow_r": -0.1, "wrist_r": 1.75, "twist": 0.3,
		"body_x": 0.5, "arm_l": Vector3(-0.8, -0.1, 0.25), "elbow_l": -0.2,
		"leg_l": -0.6, "knee_l": 0.85, "leg_r": 0.4, "knee_r": 0.65}, "lin"],
]
