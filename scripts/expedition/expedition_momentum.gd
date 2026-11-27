class_name ExpeditionMomentum
extends RefCounted
## Ímpeto do Guerreiro (Lutador) na expedição (puro: sem cena, sem autoload; testado à parte).
##
## Acúmulos de pressão: cada golpe que acerta dá 1 (no máximo um a cada GAIN_GAP s, por mais inimigos que o golpe
## pegue) e cada abate dá KILL_GAIN. Ficar HOLD s sem ganhar nada começa a perder 1 a cada DECAY_STEP s: quem para
## de pressionar perde o embalo. O teto vem de fora (run_mods "momentum_max": 0 fora da expedição ou sem a passiva,
## e aí o Ímpeto não acumula nem vale nada). Quem guarda o estado é o Game (Game.momentum); quem lê os efeitos é
## ExpeditionClasses (dano, velocidade, crítico, defesa por acúmulo).

## Intervalo mínimo entre dois ganhos por acerto (s): um golpe de área que pega 6 inimigos rende 1, não 6.
const GAIN_GAP := 0.3
## Segundos sem ganhar Ímpeto até ele começar a cair.
const HOLD := 2.5
## Depois do HOLD, perde 1 acúmulo a cada DECAY_STEP s.
const DECAY_STEP := 0.5
## Ímpeto por abate (soma com o do acerto; a bênção Lâmina Faminta dá mais).
const KILL_GAIN := 1
## Teto absoluto de acúmulos, com qualquer bênção.
const HARD_MAX := 8

var stacks := 0
## Segundos desde o último ganho (o HOLD conta daqui).
var idle := 0.0
## Segundos que ainda faltam para o próximo ganho por acerto valer.
var gap := 0.0
## Segundos em que o Ímpeto não cai (Fúria Desperta: enquanto dura a Fúria Picante).
var lock := 0.0
var _decay := 0.0


static func clamp_cap(cap: float) -> int:
	if not is_finite(cap):
		return 0
	return clampi(roundi(cap), 0, HARD_MAX)


## Um acerto. Devolve quanto ganhou (0 ou 1). Sem teto (cap 0) não acumula.
func on_hit(cap: int) -> int:
	if cap <= 0 or gap > 0.0:
		return 0
	gap = GAIN_GAP
	return add(1, cap)


## Um abate (`extra` = Ímpeto a mais da bênção). Não espera o GAIN_GAP.
func on_kill(cap: int, extra := 0) -> int:
	return add(KILL_GAIN + maxi(extra, 0), cap)


## Soma `n` sem passar de `cap`; zera a espera da queda. Devolve quanto subiu de fato.
func add(n: int, cap: int) -> int:
	if cap <= 0 or n <= 0:
		return 0
	var before := stacks
	stacks = mini(stacks + n, mini(cap, HARD_MAX))
	idle = 0.0
	_decay = 0.0
	return stacks - before


## Passo de tempo. `hold_bonus` = segundos a mais antes de cair (Pressão Implacável). Devolve quantos perdeu.
func tick(delta: float, cap: int, hold_bonus := 0.0) -> int:
	if delta <= 0.0:
		return 0
	gap = maxf(0.0, gap - delta)
	if cap <= 0:
		var all := stacks
		reset()
		return all
	if stacks > cap:
		var over := stacks - cap
		stacks = cap
		return over
	if lock > 0.0:
		lock = maxf(0.0, lock - delta)
		idle = 0.0
		return 0
	if stacks <= 0:
		idle = 0.0
		return 0
	idle += delta
	var hold := HOLD + maxf(hold_bonus, 0.0)
	if idle <= hold:
		return 0
	_decay += minf(delta, idle - hold)
	var lost := 0
	while _decay >= DECAY_STEP and stacks > 0:
		_decay -= DECAY_STEP
		stacks -= 1
		lost += 1
	return lost


## Gasta tudo (Explosão de Ímpeto). Devolve quantos acúmulos tinha.
func consume() -> int:
	var n := stacks
	stacks = 0
	idle = 0.0
	_decay = 0.0
	return n


func is_full(cap: int) -> bool:
	return cap > 0 and stacks >= mini(cap, HARD_MAX)


## Acúmulos que valem com o teto `cap` (o estado pode estar acima se o teto caiu agora).
func effective(cap: int) -> int:
	return clampi(stacks, 0, maxi(cap, 0))


func reset() -> void:
	stacks = 0
	idle = 0.0
	gap = 0.0
	lock = 0.0
	_decay = 0.0
