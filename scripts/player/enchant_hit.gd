class_name EnchantHit
extends RefCounted
## Efeito do elemento da arma encantada quando ela acerta (golpe corpo a corpo e projétil da arma;
## magias e armas automáticas da Horda não passam por aqui). Números em data/balance/enchant.json
## ("effects"), lidos por EnchantRules.effect via Game.weapon_effect().
##   scale(): antes do dano  -> Sagrado aumenta o golpe em chefes e elites.
##   on_hit(): depois do dano -> queimadura, lentidão, corrente, marca tóxica ou cura.
## Um efeito nunca dispara outro: o dano da queimadura e da corrente vai direto por take_damage.
## O combate é do cliente; só a marca tóxica vira estado do inimigo (o servidor a limita).

const BURN_TICKS := 3


## Dano do golpe já com o bônus de Sagrado, se o alvo for chefe ou elite. Outros casos: `dmg`.
static func scale(target: Node, dmg: float) -> float:
	if not (target is Enemy):
		return dmg
	var fx := Game.weapon_effect()
	if fx.get("el", "") != "sagrado":
		return dmg
	var e: Enemy = target
	if e.is_boss or e.elite or e.affix != "" or e.data.get("elite", false):
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
	match fx.el:
		"fogo":
			_burn(e, dmg * v, float(fx.get("secs", 3.0)))
		"gelo":
			if not e.dead:
				e.apply_slow(v)
		"raio":
			if randf() < v:
				chain(e, dmg, fx)
		"veneno":
			if not e.dead:
				e.apply_venom(v, float(fx.get("secs", 4.0)))
				FX.burst(e.global_position + Vector3.UP * 0.8, EnchantFX.ELEMENTS["veneno"].color, 6, 2.0, 0.07, 0.5, 2.0)
		"sombra":
			if Game.hp > 0.0:
				Game.hp = minf(Game.max_hp(), Game.hp + dmg * v)


## Queimadura: `total` de dano em BURN_TICKS pulsos ao longo de `secs`. Uma por inimigo de cada vez
## (um golpe novo não empilha nem reinicia), para não inundar o servidor de acertos.
static func _burn(e: Enemy, total: float, secs: float) -> void:
	if e.dead or total <= 0.0 or e.has_meta("enchant_burn"):
		return
	e.set_meta("enchant_burn", true)
	var tree := e.get_tree()
	var per := total / BURN_TICKS
	for i in BURN_TICKS:
		await tree.create_timer(secs / BURN_TICKS).timeout
		if not is_instance_valid(e) or e.dead or not e.is_inside_tree():
			return
		e.take_damage(per, e.global_position, false)
		FX.burst(e.global_position + Vector3.UP * 0.6, EnchantFX.ELEMENTS["fogo"].spark, 5, 2.0, 0.07, 0.4, 3.0)
	if is_instance_valid(e):
		e.remove_meta("enchant_burn")


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
	best.take_damage(dmg * float(fx.get("mult", 0.5)), target.global_position, false)
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
