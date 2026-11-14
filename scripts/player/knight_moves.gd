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

# ------------------------------------------------------------------ cajado (0,4 s / 0,4 s / 0,6 s)
## Mira: braço estendido, cajado inclinado quase na horizontal com a gema à frente. O disparo
## (0,35 do golpe) e a bola de fogo saem da gema, então ela fica parada nessa pose no disparo.
## wrist_r: quanto o cajado tomba para a frente (com o braço erguido ~1,4 = gema bem à frente).
const STAFF_AIM := {"arm_r": Vector3(-1.4, -0.12, 0.0), "elbow_r": -0.12, "wrist_r": 1.75,
	"twist": 0.12, "body_x": 0.12, "head_y": -0.15,
	"arm_l": Vector3(-0.95, -0.15, 0.3), "elbow_l": -1.0}
## Passo à frente ao mirar (só com o jogador parado).
const STAFF_AIM_LEGS := {"leg_l": -0.32, "knee_l": 0.32, "leg_r": 0.22, "knee_r": 0.2}
## Coice depois do disparo: a gema sobe um pouco e o braço recua.
const STAFF_RECOIL := {"arm_r": Vector3(-1.55, -0.1, 0.0), "elbow_r": -0.4, "wrist_r": 1.4, "body_x": 0.02,
	"twist": 0.2}
const STAFF := [
	[  # 1: recolhe o cajado junto ao ombro, aponta a gema e dispara
		[0.16, {"arm_r": Vector3(-0.45, 0.3, -0.3), "elbow_r": -1.6, "wrist_r": -0.25, "twist": -0.4,
			"body_x": -0.08, "head_y": 0.3,
			"arm_l": Vector3(-1.0, 0.45, 0.15), "elbow_l": -1.5,
			"leg_r": 0.15, "knee_r": 0.3}],
		[0.3, [STAFF_AIM, STAFF_AIM_LEGS], "in"],
		[0.37, [STAFF_AIM], "lin"],   # firme no disparo
		[0.48, [STAFF_RECOIL], "out"],
	],
	[  # 2: traz o cajado da direita, varrendo até a mira
		[0.16, {"arm_r": Vector3(-1.0, -0.85, -0.3), "elbow_r": -0.9, "wrist_r": 0.6, "twist": -0.45,
			"body_x": 0.0, "head_y": 0.35,
			"arm_l": Vector3(-1.1, 0.6, 0.1), "elbow_l": -1.6,
			"leg_l": -0.1, "knee_l": 0.25, "leg_r": 0.15, "knee_r": 0.25}],
		[0.3, [STAFF_AIM, STAFF_AIM_LEGS], "in"],
		[0.37, [STAFF_AIM], "lin"],
		[0.48, [STAFF_RECOIL], "out"],
	],
	[  # 3: ergue o cajado com as duas mãos e baixa a gema apontando (três disparos)
		[0.22, {"arm_r": Vector3(-2.75, 0.1, -0.1), "elbow_r": -0.55, "wrist_r": -0.4,
			"arm_l": Vector3(-2.6, -0.1, 0.25), "elbow_l": -0.75, "body_x": -0.22, "head_x": -0.1,
			"twist": -0.1, "leg_l": -0.05, "knee_l": 0.15, "knee_r": 0.15}],
		[0.32, [STAFF_AIM, {"arm_r": Vector3(-1.3, -0.12, 0.0), "wrist_r": 1.55, "body_x": 0.35, "head_x": -0.15,
			"arm_l": Vector3(-1.25, -0.3, 0.25), "elbow_l": -0.3,
			"leg_l": -0.38, "knee_l": 0.7, "leg_r": 0.3, "knee_r": 0.55}], "in"],
		[0.4, [STAFF_AIM, {"arm_r": Vector3(-1.3, -0.12, 0.0), "wrist_r": 1.55, "body_x": 0.35,
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
## Com cajado, a bola de fogo usa a mira do cajado: recolhe, aponta a gema (dispara em CAST_RELEASE)
## e dá o coice.
const CAST_STAFF := {
	"fireball": [
		[0.12, {"arm_r": Vector3(-0.45, 0.3, -0.3), "elbow_r": -1.6, "wrist_r": -0.25, "twist": -0.4,
			"body_x": -0.08, "head_y": 0.3, "arm_l": Vector3(-1.0, 0.45, 0.15), "elbow_l": -1.5}],
		[0.24, [STAFF_AIM, STAFF_AIM_LEGS], "in"],
		[0.36, [STAFF_AIM], "lin"],
		[0.55, [STAFF_RECOIL], "out"],
	],
}

# ------------------------------------------------------------------ arco
## Arco na mão esquerda: o corpo fica de lado (ombro esquerdo para o alvo), o braço do arco
## estende para a frente compensando o giro, e a mão direita leva a corda até o queixo com o
## cotovelo alto atrás.
const BOW_NOCK := {   # flecha encaixada, corda ainda frouxa
	"twist": -0.45, "head_y": 0.4, "body_x": 0.04,
	"arm_l": Vector3(-1.5, 0.45, 0.0), "elbow_l": -0.15, "wrist_l": 0.0,
	"arm_r": Vector3(-1.4, 0.55, 0.1), "elbow_r": -0.55,
}
const BOW_FULL := {   # corda toda puxada
	"twist": -0.75, "head_y": 0.7, "body_x": 0.0,
	"arm_l": Vector3(-1.55, 0.75, 0.0), "elbow_l": -0.05,
	"arm_r": Vector3(-1.45, -0.55, -0.2), "elbow_r": -2.1,
}
const BOW_TREMBLE := 0.008      ## tremor do braço do arco com a corda toda puxada (rad)
const BOW_RAISE_SPEED := 1.6    ## multiplica a suavização ao erguer o arco (mais rápido que andar)
## Soltar: a mão da corda escapa para trás da orelha, o braço do arco segura e depois desce.
const BOW_RELEASE := [
	[0.15, {"arm_r": Vector3(-1.4, -0.95, -0.35), "elbow_r": -1.5, "twist": -0.7, "head_y": 0.65,
		"arm_l": Vector3(-1.55, 0.7, 0.0), "elbow_l": -0.05}, "out"],
	[0.5, {"arm_l": Vector3(-1.4, 0.6, 0.05), "elbow_l": -0.15, "arm_r": Vector3(-1.1, -0.7, -0.4),
		"elbow_r": -1.3, "twist": -0.55, "head_y": 0.5}],
]

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
	[0.8, {"arm_r": Vector3(-1.1, 0.4, 0.1), "elbow_r": -0.3, "wrist_r": 1.4, "twist": 0.3,
		"body_x": 0.25, "leg_l": -0.55, "knee_l": 0.7, "leg_r": 0.3, "knee_r": 0.3}, "out"],
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
