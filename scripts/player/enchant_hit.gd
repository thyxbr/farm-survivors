class_name EnchantHit
extends RefCounted
## Efeito do elemento da arma encantada quando ela acerta (golpe corpo a corpo e projétil da arma;
## magias e armas automáticas da Horda não passam por aqui). Números em data/balance/enchant.json
## ("effects"), lidos por EnchantRules.effect via Game.weapon_effect().
##   scale(): antes do dano  -> Sagrado aumenta o golpe em chefes e elites.
##   on_hit(): depois do dano -> queimadura, lentidão, corrente, veneno ou cura.
## Um efeito nunca dispara outro: o dano da queimadura e da corrente vai direto por take_damage.
## O combate é do cliente; queimadura, lentidão e veneno viram estado do inimigo no servidor (StatusEffects).

## Elemento do golpe da arma equipada (Enemy.take_damage): `base` (físico; faísca do cajado e esfera do cetro
## têm o deles) com a fatia que o encantamento soma ao dano no elemento do encanto (ElementRules.weapon_mix).
static func mix(base := "fisico"):
	var e := Game.weapon_enchant()
	return ElementRules.weapon_mix(base, str(e.get("el", "")), Game.enchant_damage(str(Game.equipment.weapon)),
		Game.mod("damage"))


## Dano do golpe já com o bônus de Sagrado, se o alvo for chefe ou elite. Outros casos: `dmg`.
static func scale(target: Node, dmg: float) -> float:
	if not (target is Enemy):
		return dmg
	var fx := Game.weapon_effect()
	if fx.get("el", "") != "sagrado":
		return dmg
	var e: Enemy = target
	if e.is_boss or e.elite or e.data.get("elite", false):
		return dmg * (1.0 + float(fx.value))
	return dmg


## Aplica o efeito da arma equipada num alvo que acabou de levar `dmg`. Ignora o que não é inimigo
## (animal da cidade, nó de recurso) e arma sem encanto.
static func on_hit(target: Node, dmg: float) -> void:
	if not is_instance_valid(target) or not (target is Enemy):
		return
	var fx := Game.weapon_effect()
	if fx.is_empty():
		return
	var e: Enemy = target
	var v: float = fx.value
	if fx.el in StatusRules.STATUS_ELEMENTS:
		try_status(e, dmg, fx, randf())
		return
	match fx.el:
		"raio":
			if randf() < v:
				chain(e, dmg, fx)
		"sombra":
			if Game.hp > 0.0:
				Game.hp = minf(Game.max_hp(), Game.hp + dmg * v)


## Status da arma (fogo, gelo ou veneno; StatusRules) num alvo que levou `dmg`, com a rolagem `r` (0..1):
## a chance do nível (fx.chance) cortada pela resistência do Bestiário. Pegou: pede o status (fogo e veneno
## levam fx.value do dano em pulsos ao longo de fx.secs; gelo, fx.value segundos de lentidão). Imune e a base
## teria pego: "Resistiu" sobre o alvo. Devolve o resultado da rolagem ("applied", "resisted" ou "none").
static func try_status(e: Enemy, dmg: float, fx: Dictionary, r: float) -> String:
	if not is_instance_valid(e) or e.dead:
		return "none"
	var el := str(fx.get("el", ""))
	var resist := StatusRules.enemy_resist(Balance.tables, e.kind, el)
	var res := StatusRules.roll(float(fx.get("chance", 0.0)), resist, r)
	match res:
		"applied":
			if el == "gelo":
				e.apply_status(el, 0.0, float(fx.value))
			else:
				e.apply_status(el, dmg * float(fx.value), float(fx.get("secs", 3.0)))
			if el == "veneno":
				FX.burst(e.global_position + Vector3.UP * 0.8, EnchantFX.ELEMENTS["veneno"].color, 6, 2.0, 0.07, 0.5, 2.0)
		"resisted":
			e.show_resisted(el)
	return res


## Corrente: o inimigo vivo mais próximo de `target`, a até fx.radius, leva dmg * fx.mult.
## Devolve quem foi atingido (null se não havia ninguém por perto).
static func chain(target: Enemy, dmg: float, fx: Dictionary) -> Enemy:
	var best: Enemy = null
	var best_d := float(fx.get("radius", 6.0))
	for o in target.get_tree().get_nodes_in_group("enemies"):
		if o == target or not (o is Enemy) or o.dead or o.is_queued_for_deletion():
			continue
		var d: float = o.global_position.distance_to(target.global_position)
		if d <= best_d:
			best_d = d
			best = o
	if best == null:
		return null
	_bolt(target.global_position + Vector3.UP * 0.8, best.global_position + Vector3.UP * 0.8)
	best.take_damage(dmg * float(fx.get("mult", 0.5)), target.global_position, false, 0.0, 0.0, 0.0, "raio")
	return best


## Risco de luz entre dois pontos (o salto da corrente), só visual.
static func _bolt(a: Vector3, b: Vector3) -> void:
	if Network.is_server() or DisplayServer.get_name() == "headless" or a.distance_to(b) < 0.05:
		return
	var root := (Engine.get_main_loop() as SceneTree).current_scene
	if root == null:
		return
	var color: Color = EnchantFX.ELEMENTS["raio"].spark
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.06, 0.06, a.distance_to(b))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = EnchantFX.ELEMENTS["raio"].color
	m.emission_energy_multiplier = 3.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	box.material = m
	mi.mesh = box
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = (a + b) * 0.5
	mi.look_at(b, Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT)
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, 0.18)
	tw.tween_callback(mi.queue_free)
	FX.burst(b, color, 8, 3.0, 0.06, 0.3, 0.0)
