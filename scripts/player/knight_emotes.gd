class_name KnightEmotes
extends RefCounted
## Emotes do cavaleiro na praça (teclas 1–3): acenar, comemorar e sentar.
## Cada emote é uma pose do KnightAnim montada sobre a respiração do idle_pose, então o corpo continua
## vivo por baixo. O jogador local e as réplicas usam a mesma função: pela rede vai só o índice em KINDS
## (evento "emote" do _player_event), e cada cliente anima a pose sozinho.

const KINDS := ["acenar", "comemorar", "sentar"]
## Segundos de cada emote; 0 = fica até o jogador se mexer (sentar).
const DURATION := {"acenar": 2.4, "comemorar": 2.6, "sentar": 0.0}
## Tempo para entrar na pose e para sair dela (o fim suaviza de volta ao idle).
const EASE_IN := 0.3
const EASE_OUT := 0.35


static func duration(kind: String) -> float:
	return float(DURATION.get(kind, 0.0))


## Pose do emote `kind` `t` segundos depois de começar.
static func pose(kind: String, t: float) -> Dictionary:
	var idle := KnightAnim.idle_pose(t)
	var p := idle.duplicate()
	match kind:
		"acenar":
			# braço esquerdo (a mão livre) erguido de lado, o antebraço balança de um lado para o outro
			var s := sin(t * 9.0)
			p.arm_l = Vector3(-2.35, 0.0, 0.75 + 0.32 * s)
			p.elbow_l = -0.55 - 0.25 * s
			p.head_y = 0.12
			p.head_x = -0.08
			p.body_z = -0.04
		"comemorar":
			# os dois braços para o alto e pulinhos: o modelo sobe (lift) e os joelhos absorvem a queda
			var hop := absf(sin(t * 6.5))
			p.arm_l = Vector3(-2.75, 0.0, 0.45 + 0.1 * hop)
			p.arm_r = Vector3(-2.75, 0.0, -0.45 - 0.1 * hop)
			p.elbow_l = -0.25
			p.elbow_r = -0.25
			p.head_x = -0.3
			p.body_x = -0.1
			p.lift = 0.14 * hop
			p.knee_l = 0.35 * (1.0 - hop)
			p.knee_r = 0.35 * (1.0 - hop)
			p.leg_l = -0.15 * (1.0 - hop)
			p.leg_r = -0.15 * (1.0 - hop)
			p.foot_l = 0.25 * hop
			p.foot_r = 0.25 * hop
		"sentar":
			# sentado no chão: pernas para a frente (o ground do KnightAnim baixa o modelo até o quadril
			# encostar), tronco um pouco para trás apoiado nas mãos
			p.leg_l = -1.5
			p.leg_r = -1.35
			p.knee_l = 0.25
			p.knee_r = 0.55
			p.foot_l = -1.0
			p.foot_r = -0.7
			p.body_x = -0.22 + idle.body_x
			p.head_x = 0.12 + idle.head_x
			p.arm_l = Vector3(0.55, 0.0, 0.4)
			p.arm_r = Vector3(0.55, 0.0, -0.4)
			p.elbow_l = -0.1
			p.elbow_r = -0.1
		_:
			return idle
	var w := smoothstep(0.0, EASE_IN, t)
	var d := duration(kind)
	if d > 0.0:
		w = minf(w, smoothstep(d, d - EASE_OUT, t))
	return KnightAnim.blend(idle, p, w)
