class_name DeriveQueue
extends RefCounted
## Fila das derivações de senha do AuthHttp (pura: só decide a ordem e quantas rodam ao mesmo tempo).
## No máximo `max_running` derivações em andamento; as outras esperam na fila (até `max_waiting`; além disso
## o pedido é recusado na hora com 503). Ordem de chegada.

## Padrão do AuthHttp: duas derivações em paralelo (~0,3 s cada) e até 32 esperando.
const MAX_RUNNING := 2
const MAX_WAITING := 32

var max_running := MAX_RUNNING
var max_waiting := MAX_WAITING
var running := 0
var _waiting: Array = []


func _init(p_max_running := MAX_RUNNING, p_max_waiting := MAX_WAITING) -> void:
	max_running = p_max_running
	max_waiting = p_max_waiting


## Põe na fila. false = fila cheia (o chamador recusa o pedido).
func push(item) -> bool:
	if _waiting.size() >= max_waiting:
		return false
	_waiting.append(item)
	return true


## Tira da fila os itens que podem começar agora (marca cada um como em andamento).
func take_startable() -> Array:
	var out := []
	while running < max_running and not _waiting.is_empty():
		out.append(_waiting.pop_front())
		running += 1
	return out


## Uma derivação terminou.
func finished() -> void:
	running = maxi(0, running - 1)


func waiting() -> int:
	return _waiting.size()
