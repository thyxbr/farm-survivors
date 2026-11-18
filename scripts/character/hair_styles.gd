class_name HairStyles
## Penteados do herói, por corpo, escolhidos na criação (docs/superpowers/specs/2026-11-18-penteados-design.md).
## O primeiro de cada lista é o padrão: vale para personagens antigos (sem penteado gravado) e para penteado
## inválido. O modelo é assets/models/gear/hair_<id>.glb (ver KnightLook).

const STYLES := {
	"m": ["m_curto", "m_penteado", "m_franja", "m_raspado"],
	"f": ["f_longo", "f_chanel", "f_curto", "f_marias"],
}

## Nome mostrado na tela de criação.
const NAMES := {
	"m_curto": "Curto", "m_penteado": "Penteado", "m_franja": "Franja", "m_raspado": "Raspado",
	"f_longo": "Rabo de cavalo", "f_chanel": "Chanel", "f_curto": "Curto", "f_marias": "Marias",
}


## Corpo válido ("m" quando vazio ou desconhecido, como KnightLook.body_key).
static func _body(body: String) -> String:
	return body if STYLES.has(body) else "m"


static func default_for(body: String) -> String:
	return STYLES[_body(body)][0]


## Verdadeiro se `hair` é um penteado do corpo `body`.
static func valid(body: String, hair: String) -> bool:
	return STYLES.has(body) and hair in STYLES[body]


## O penteado a mostrar: o gravado, se for do corpo; senão o padrão do corpo.
static func resolve(body: String, hair: String) -> String:
	return hair if valid(_body(body), hair) else default_for(body)
