class_name StatusEffects
extends Node
## Status elementais ativos num inimigo (StatusRules): queimadura e veneno (dano em pulsos), lentidão de gelo
## e congelamento. Filho do Enemy. O dono (servidor ou solo) guarda o estado e roda tick(); a réplica só
## recebe o bitmask pelo snapshot (set_mask) para desenhar a aura.
## No servidor, cada pulso conta como acerto de quem aplicou (last_hitter): abate, XP e loot vão para ele.
## Um pulso nunca rola status.

signal mask_changed(mask: int)

var enemy: Enemy
## {el: {"power", "timer", "left", "next", "every", "applier"}} (gelo só usa "timer").
var _fx := {}
var _ice_stacks := 0
var _freeze_t := 0.0
var _freeze_cd := 0.0
var _mask := 0


func _init(owner_enemy: Enemy = null) -> void:
	enemy = owner_enemy
	name = "StatusEffects"


func has(el: String) -> bool:
	return _mask & int(StatusRules.BITS.get(el, 0)) != 0


func mask() -> int:
	return _mask


## Réplica: bitmask vindo do snapshot.
func set_mask(m: int) -> void:
	if m != _mask:
		_mask = m
		mask_changed.emit(_mask)


## Dono: aplica `el` com `power` (dano total do efeito; gelo ignora) por `secs`. `applier` = peer que bateu
## (0 no solo).
func apply(el: String, power: float, secs: float, applier: int) -> void:
	if enemy == null or enemy.dead or secs <= 0.0 or not (el in StatusRules.STATUS_ELEMENTS):
		return
	var bt := Balance.tables
	if el == "gelo":
		var cfg: Dictionary = bt.get_table("enchant").get("effects", {}).get("gelo", {})
		_ice_stacks = _ice_stacks + 1 if _fx.has("gelo") else 1
		_fx["gelo"] = StatusRules.renew(_fx.get("gelo", {}), 0.0, secs)
		enemy.slow_timer = maxf(enemy.slow_timer, secs)
		var protected: bool = enemy.is_boss or enemy.elite or enemy.data.get("elite", false)
		if StatusRules.should_freeze(_ice_stacks, int(cfg.get("freeze_stacks", 3)), protected, _freeze_cd):
			var fs := float(cfg.get("freeze_secs", 1.0))
			enemy.apply_stun(fs)
			_freeze_t = fs
			_freeze_cd = float(cfg.get("freeze_cd", 5.0))
			_ice_stacks = 0
	else:
		var n := maxi(1, StatusRules.ticks(bt, el))
		if power <= 0.0:
			return
		var cur: Dictionary = StatusRules.renew(_fx.get(el, {}), power, secs)
		cur["left"] = n
		cur["every"] = cur.timer / n
		cur["next"] = cur.every
		cur["applier"] = applier
		_fx[el] = cur
	_refresh_mask()


## Dono: avança os tempos e dá os pulsos que venceram.
func tick(delta: float) -> void:
	if enemy == null:
		return
	_freeze_t = maxf(0.0, _freeze_t - delta)
	_freeze_cd = maxf(0.0, _freeze_cd - delta)
	for el in _fx.keys():
		var f: Dictionary = _fx[el]
		if el == "gelo":
			f.timer -= delta
			if f.timer <= 0.0:
				_fx.erase(el)
				_ice_stacks = 0
			continue
		f.next -= delta
		while f.next <= 0.0 and f.left > 0:
			f.left -= 1
			f.next += f.every
			_pulse(el, f.power / float(StatusRules.ticks(Balance.tables, el)), int(f.applier))
			if enemy == null or enemy.dead or not is_instance_valid(enemy):
				_fx.clear()
				break
		if _fx.has(el) and f.left <= 0:
			_fx.erase(el)
	_refresh_mask()


func _pulse(el: String, amount: float, applier: int) -> void:
	if amount <= 0.0 or enemy.dead or not enemy.is_inside_tree():
		return
	var server := Network.is_server()
	var prev := enemy.last_hitter
	if server:
		enemy.last_hitter = applier if Network.players.has(applier) else 0
	enemy.take_damage(amount, enemy.global_position, false, 0.0, 0.0, 0.0, el)
	if server and is_instance_valid(enemy):
		enemy.last_hitter = prev


func _refresh_mask() -> void:
	var m := 0
	for el in _fx:
		m |= int(StatusRules.BITS.get(el, 0))
	if _freeze_t > 0.0:
		m |= int(StatusRules.BITS.congelado)
	set_mask(m)
