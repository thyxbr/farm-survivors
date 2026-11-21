class_name ShieldRules
extends RefCounted
## Defesa com escudo (botão direito segurado com escudo na mão secundária). Puro (sem autoload):
## o jogador passa o item do escudo e os números do golpe.
##
## Como funciona (pesquisa: Dark Souls, Elden Ring, Crimson Desert, Kingdom Come):
##  - só defende o que vem pela frente (cone de FRONT_DOT); golpe pelas costas entra cheio;
##  - o escudo segura `block` do dano (madeira ~60%, escudos de placa ~90%);
##  - cada golpe defendido custa fôlego, proporcional ao dano, e o custo SOBE a cada golpe seguido
##    (CHAIN_STEP por golpe na sequência; a sequência zera depois de CHAIN_RESET s sem apanhar);
##  - `guard` do escudo (0..1) corta esse custo (escudo melhor cansa menos);
##  - sem fôlego para o golpe, a guarda quebra: dano cheio e BREAK_TIME s sem poder levantar o escudo.

## Fôlego fixo de cada golpe defendido (mesmo um arranhão empurra o braço).
const BASE_COST := 8.0
## Fôlego por ponto de dano que chegaria (antes do escudo).
const DMG_COST := 0.55
## Quanto o custo cresce a cada golpe seguido: o 2º custa +40%, o 3º +80%...
const CHAIN_STEP := 0.4
## Teto do multiplicador da sequência (não chega a ser impossível segurar uma pancada isolada depois).
const CHAIN_MAX := 3.0
## Segundos sem apanhar para a sequência zerar.
const CHAIN_RESET := 1.8
## Cosseno do meio-ângulo do cone defendido (0,25 ≈ 75° para cada lado da frente).
const FRONT_DOT := 0.25
## Guarda quebrada: segundos sem poder defender (cambaleia).
const BREAK_TIME := 1.2
## Andando com o escudo levantado: fração da velocidade de andar.
const MOVE_SPEED := 0.5
## Recuperação de fôlego enquanto segura o escudo (fração da normal).
const REGEN_MULT := 0.35
## Escudo sem os campos (itens antigos): madeira simples.
const DEFAULT_BLOCK := 0.6


## Fração do dano que o escudo `it` segura (0..0,95).
static func block_of(it: Dictionary) -> float:
	return clampf(float(it.get("block", DEFAULT_BLOCK)), 0.0, 0.95)


## Quanto o escudo corta do fôlego gasto (0..0,6).
static func guard_of(it: Dictionary) -> float:
	return clampf(float(it.get("guard", 0.0)), 0.0, 0.6)


## Multiplicador da sequência: 1 no primeiro golpe, +CHAIN_STEP a cada um seguido, até CHAIN_MAX.
static func chain_mult(chain: int) -> float:
	return minf(1.0 + CHAIN_STEP * maxi(chain, 0), CHAIN_MAX)


## Fôlego que um golpe de `amount` de dano custa, sendo o golpe número `chain` + 1 da sequência.
static func cost(amount: float, chain: int, it: Dictionary) -> float:
	return (BASE_COST + maxf(amount, 0.0) * DMG_COST) * chain_mult(chain) * (1.0 - guard_of(it))


## O golpe vindo de `from_pos` está na frente de quem olha para `facing` (no plano do chão)?
static func in_front(pos: Vector3, facing: Vector3, from_pos: Vector3) -> bool:
	var to := from_pos - pos
	to.y = 0.0
	if to.length() < 0.05:
		return true   # colado: conta como de frente
	var f := Vector3(facing.x, 0.0, facing.z)
	if f.length() < 0.001:
		return false
	return f.normalized().dot(to.normalized()) >= FRONT_DOT


## Decide um golpe contra o escudo levantado. Devolve {blocked, damage (o que passa), stamina (o que
## sobra), broke (guarda quebrou)}. `damage` é o dano antes da defesa da armadura.
static func resolve(amount: float, stamina: float, chain: int, it: Dictionary) -> Dictionary:
	var c := cost(amount, chain, it)
	if stamina < c:
		return {"blocked": false, "damage": amount, "stamina": 0.0, "broke": true}
	return {"blocked": true, "damage": amount * (1.0 - block_of(it)), "stamina": stamina - c, "broke": false}
