class_name AegisRules
extends RefCounted
## Regras puras da Égide Cristalina (escudo de placas da espada com escudo): integridade e absorção de dano.
## Sem nó, sem autoload: o dono do personagem (hoje o PC do jogador, que é dono da vida em Game.hp) chama
## absorb() dentro de Player.take_damage; um servidor com autoridade pode guardar o mesmo `state` por peer e
## chamar as mesmas funções antes de repassar o dano (Network.server_damage_player), mandando só a fração
## para o visual. O visual (AegisBarrier) nunca decide nada: ele só recebe a fração de integridade.
##
## state = {"integrity": float, "max": float, "broken": bool, "absorbed": float (total absorvido)}


## Integridade máxima para um personagem de `level` com `defense` de equipamento.
static func max_integrity(cfg: AegisConfig, level: int, defense: float) -> float:
	return maxf(1.0, cfg.max_integrity + cfg.integrity_per_level * float(maxi(level - 1, 0))
		+ cfg.integrity_per_defense * maxf(defense, 0.0))


static func new_state(max_hp: float) -> Dictionary:
	var m := maxf(1.0, max_hp)
	return {"integrity": m, "max": m, "broken": false, "absorbed": 0.0}


## Fração da integridade (0..1) que o visual mostra.
static func fraction(state: Dictionary) -> float:
	return clampf(float(state.get("integrity", 0.0)) / maxf(float(state.get("max", 1.0)), 0.0001), 0.0, 1.0)


## O escudo ainda protege?
static func active(state: Dictionary) -> bool:
	return not state.is_empty() and not bool(state.get("broken", false)) and float(state.get("integrity", 0.0)) > 0.0


## Absorve `amount` de dano (já reduzido pela defesa). Muda `state` e devolve:
## {"absorbed": o que o escudo segurou, "overflow": o que passa para a vida, "broke": quebrou agora}.
## `absorb_ratio` < 1: só essa parte do golpe vai para o escudo; o resto passa direto.
static func absorb(state: Dictionary, amount: float, absorb_ratio := 1.0) -> Dictionary:
	var out := {"absorbed": 0.0, "overflow": maxf(amount, 0.0), "broke": false}
	if not active(state) or amount <= 0.0:
		return out
	var into_shield := amount * clampf(absorb_ratio, 0.0, 1.0)
	var passthrough := amount - into_shield
	var held := minf(into_shield, float(state.integrity))
	state.integrity = float(state.integrity) - held
	state.absorbed = float(state.get("absorbed", 0.0)) + held
	out.absorbed = held
	out.overflow = passthrough + (into_shield - held)
	if float(state.integrity) <= 0.0001:
		state.integrity = 0.0
		state.broken = true
		out.broke = true
	return out


## Quanto cada placa está rachada (0..1) para a fração de integridade `frac`. `bias` (0..1) é o sorteio
## da placa (umas racham antes das outras) e `near` (0..1) a proximidade do último golpe (racha mais perto
## dele). `spread` = AegisConfig.crack_spread. Com o escudo inteiro nada racha; zerado, tudo racha.
static func plate_crack(frac: float, bias: float, near: float, spread := 1.0) -> float:
	var lost := clampf(1.0 - frac, 0.0, 1.0)
	if lost <= 0.0:
		return 0.0
	if frac <= 0.0:
		return 1.0
	var c := lost * spread * (0.55 + 0.9 * bias) + near * lost * 0.6
	return clampf(c, 0.0, 1.0)
