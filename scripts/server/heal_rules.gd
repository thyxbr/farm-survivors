class_name HealRules
extends RefCounted
## Servidor: decisões da Cura do healer em aliados. Puro (sem autoload): recebe os dados já prontos.

## Distância máxima, em metros, entre o healer e o aliado curado (posições recebidas pelo servidor).
const RADIUS := 8.0
## Tempo mínimo, em segundos, entre duas curas aceitas do mesmo jogador (a recarga de verdade é do cliente).
const MIN_INTERVAL := 2.0


## Quem recebe a cura do `caster`: ele mesmo sempre e os de `zone_peers` a até RADIUS m dele.
## `positions` é peer -> última posição; quem não tem posição conhecida é pulado.
static func targets(caster: int, zone_peers: Array, positions: Dictionary) -> Array:
	var out := []
	var origin: Vector3 = positions.get(caster, Vector3.INF)
	for pid in zone_peers:
		if pid == caster:
			out.append(pid)
			continue
		var p: Vector3 = positions.get(pid, Vector3.INF)
		if origin.is_finite() and p.is_finite() and p.distance_to(origin) <= RADIUS:
			out.append(pid)
	if not (caster in out):
		out.append(caster)
	return out


## true = passou o intervalo mínimo desde a última cura aceita (`last` em segundos; -INF = nunca).
static func interval_ok(last: float, now: float) -> bool:
	return now - last >= MIN_INTERVAL
