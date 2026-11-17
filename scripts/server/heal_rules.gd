class_name HealRules
extends RefCounted
## Servidor: decisões da Cura do healer em aliados. Puro (sem autoload): recebe os dados já prontos.

## Distância máxima, em metros, entre o healer e os aliados dos buffs em área (posições recebidas pelo servidor).
const RADIUS := 8.0
## Alcance da Cura mirada num aliado (o cliente mira até Player.HEAL_RANGE = 25 m; folga para o atraso da rede).
const TARGET_RANGE := 28.0
## Tempo mínimo, em segundos, entre duas curas aceitas do mesmo jogador (a recarga de verdade é do cliente).
## A menor recarga legítima é 4,0 x 0,4 (cooldown_mult mínimo) = 1,6 s; 1,4 s deixa folga para o jitter da rede.
const MIN_INTERVAL := 1.4
## Cura total do Banquete do Herói (o cliente limita à vida máxima).
const ULT_HEAL := 9999.0
## Teto da duração de um buff recebido de aliado (o cliente recusa mais do que isto).
const MAX_BUFF_SECS := 60.0
## Buff que cada habilidade de aliados dá (o servidor nunca aceita um id de buff do cliente).
const ALLY_BUFFS := {"scepter_ward": "scepter_ward", "scepter_ult": "scepter_feast"}
## Intervalo mínimo por habilidade = recarga x 0,4 (cooldown_mult mínimo) - 0,2 de folga para o jitter.
## O servidor não vê a fúria: a recarga da ultimate no cliente é de pelo menos a duração do Banquete + 4 s (>= 16 s).
## O piso do servidor (14,5 s) fica um pouco abaixo disso (margem para o jitter) e só barra spam.
const INTERVALS := {"heal": MIN_INTERVAL, "scepter_ward": 6.2, "scepter_ult": 14.5}


## Quem recebe a cura do `caster`: ele mesmo sempre e os de `zone_peers` a até RADIUS + `bonus` m dele.
## `positions` é peer -> última posição; quem não tem posição conhecida é pulado.
static func targets(caster: int, zone_peers: Array, positions: Dictionary, bonus := 0.0) -> Array:
	var out := []
	var origin: Vector3 = positions.get(caster, Vector3.INF)
	for pid in zone_peers:
		if pid == caster:
			out.append(pid)
			continue
		var p: Vector3 = positions.get(pid, Vector3.INF)
		if origin.is_finite() and p.is_finite() and p.distance_to(origin) <= RADIUS + bonus:
			out.append(pid)
	if not (caster in out):
		out.append(caster)
	return out


## Quem recebe a Cura mirada do `caster`: o aliado `target` se ele está em `zone_peers` e a até TARGET_RANGE
## + `bonus` m (posições conhecidas); senão (0, ele mesmo, longe, outra zona, sem posição) o próprio healer.
static func heal_target(caster: int, target: int, zone_peers: Array, positions: Dictionary, bonus := 0.0) -> int:
	if target <= 0 or target == caster or not (target in zone_peers):
		return caster
	var a: Vector3 = positions.get(caster, Vector3.INF)
	var b: Vector3 = positions.get(target, Vector3.INF)
	if not a.is_finite() or not b.is_finite() or a.distance_to(b) > TARGET_RANGE + bonus:
		return caster
	return target


## Duração, em segundos, de um buff em aliado: o tempo da tabela + o bônus de talento do healer (nunca negativo).
static func ally_buff_seconds(base: float, bonus: float) -> float:
	return base + maxf(0.0, bonus)


## Intervalo mínimo, em segundos, entre dois usos aceitos da habilidade `id` (desconhecida: o da Cura).
static func min_interval(id: String) -> float:
	return float(INTERVALS.get(id, MIN_INTERVAL))


## true = passou o intervalo mínimo da habilidade `id` desde o último uso aceito (`last` em segundos; -INF = nunca).
static func interval_ok(last: float, now: float, id := "heal") -> bool:
	return now - last >= min_interval(id)


## O personagem tem nível para a habilidade? (o cliente também confere; o servidor não confia nele)
static func level_ok(char_level: int, ability_level: int) -> bool:
	return char_level >= ability_level
