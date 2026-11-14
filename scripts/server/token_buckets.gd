class_name TokenBuckets
extends RefCounted
## Balde de fichas por chave (peer): cada pedido gasta uma ficha; o balde enche `rate` fichas por segundo
## até `burst`. Sem ficha, o pedido é recusado sem tocar no banco. Puro: o relógio vem no `allow`.

var burst := 10.0
var rate := 5.0
var _buckets := {}   # chave -> {"tokens": float, "t": float}


func _init(p_burst := 10.0, p_rate := 5.0) -> void:
	burst = p_burst
	rate = p_rate


## Gasta uma ficha de `key` no instante `now` (s). false = acima do limite.
func allow(key, now: float) -> bool:
	var b: Dictionary = _buckets.get(key, {"tokens": burst, "t": now})
	b.tokens = minf(burst, float(b.tokens) + maxf(0.0, now - float(b.t)) * rate)
	b.t = now
	_buckets[key] = b
	if b.tokens < 1.0:
		return false
	b.tokens -= 1.0
	return true


## Esquece a chave (o peer saiu).
func forget(key) -> void:
	_buckets.erase(key)


func size() -> int:
	return _buckets.size()
