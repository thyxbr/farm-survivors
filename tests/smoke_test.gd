extends Node
## Teste de fumaça do gameplay. Rode com:
##   godot --headless --path . res://scenes/world.tscn -- --smoketest
## Imprime PASS/FAIL para cada verificação e encerra com código 0 (ok) ou 1 (falhas).
## No CI roda em partes, em paralelo (cada uma num job): `--smoke-part=mundo` (história, combate e classes),
## `--smoke-part=sistemas` (_test_sistemas: horta, coleta, masmorras, encantos, chefes, rio...) e
## `--smoke-part=horda` (só o Desafio da Horda). Sem o argumento roda tudo, como antes.

const UPG := preload("res://scripts/survival/upgrades.gd")

var fails := 0
var world: Node
var player: Player


func check(cond: bool, what: String) -> void:
	if cond:
		print("PASS  ", what)
	else:
		fails += 1
		print("FAIL  ", what)


## Ids das habilidades mostradas nos slots 1-4 da barra de ações (pelo ícone).
func hud_slot_ids() -> Array[String]:
	var out: Array[String] = []
	var hud = world.hud
	for n in range(1, ItemDB.SLOT_COUNT + 1):
		var icon: String = hud.slots["slot_%d" % n].icon_kind
		var found := ""
		for id in ItemDB.ABILITIES:
			if ItemDB.ABILITIES[id].icon == icon and ItemDB.ABILITIES[id].slot == n and ItemDB.ABILITIES[id]["class"] == Game.weapon_class():
				found = id
		if found != "":
			out.append(found)
	return out


## Equipa trocando antes a classe do personagem para a da arma (a classe é fixa no jogo de verdade;
## o teste precisa passar pelas quatro armas).
func equip_any(id: String, use := false) -> void:
	if CharRules.slot_of(Balance.tables, id) == "weapon":
		var wc := CharRules.weapon_class(Balance.tables, id)
		for cls in CharRules.CLASS_IDS:
			if CharRules.class_weapon(Balance.tables, cls) == wc and Game.char_class != cls:
				Econ.test_force_class(cls)
	# o item pede nível: sobe o personagem só para equipar e devolve (o item equipado fica)
	var lv0 := Game.level
	Econ.test_force_level(maxi(lv0, CharRules.item_level(Balance.tables, id)))
	if use:
		Game.use_item(id)
	else:
		Game.equip(id)
	Econ.test_force_level(lv0)


## Égide Cristalina (espada + escudo, slot 1): kit, formação, absorção com rachaduras, quebra, dissipação,
## limpeza dos nós e o fim por soltar a tecla. Volta sem escudo e com a vida de antes.
func _check_aegis(player: Node, world: Node) -> void:
	var cfg: AegisConfig = ShieldAbilities.CONFIG
	Game.add_item("wooden_shield")
	equip_any("wooden_shield")
	await wait_until(func(): return Game.offhand_kind() == "shield")
	check(Game.ability_kit()[0] == "sword_aegis" and Game.ability_kit().size() == 5,
		"Égide: espada + escudo troca a habilidade 1 (%s)" % [Game.ability_kit()])
	await wait_until(func(): return player.ability == "" and not player.attacking and player.dodge_timer <= 0.0)
	var hp0: float = Game.hp
	var count_fx := func(cls: String) -> int:
		var n := 0
		for c in get_tree().current_scene.find_children("*", cls, true, false):
			if not c.is_queued_for_deletion():
				n += 1
		return n
	# nenhum monstro em volta bate no escudo durante a checagem: os alvos de checagens anteriores ficam fora do
	# atordoamento periódico e um golpe deles (~7) enquanto a barreira se forma tirava a integridade dos 60% esperados
	_calm_bystanders([], player.global_position, 40.0, 3.5)   # cobre até o terceiro golpe (~2,9 s)
	player.cooldowns.sword_aegis = 0.0
	player.cast("sword_aegis")   # slot 0 = fica erguido até release(), como a tecla segurada
	check(player.ability == "sword_aegis", "Égide: a habilidade começa")
	var bar: AegisBarrier = player.ability_data.get("barrier")
	check(is_instance_valid(bar) and bar.get_parent() == player, "Égide: barreira nasce presa ao jogador")
	var rings0: Vector2 = bar.rings.angles()
	await wait(cfg.circle_form_time + 0.05)
	var dr: Vector2 = bar.rings.angles() - rings0
	check(bar.ground.formed() >= 1.0, "Égide: círculo mágico formado em %.2f s" % cfg.circle_form_time)
	check(dr.x > 0.0 and dr.y < 0.0, "Égide: anéis giram em sentidos opostos (%.2f / %.2f rad)" % [dr.x, dr.y])
	var early := bar.formed()
	await wait(cfg.barrier_form_time + 0.2)
	check(early < 0.9 and bar.formed() >= 0.99, "Égide: barreira cresce aos poucos (%.2f -> %.2f)" % [early, bar.formed()])
	var low_first := bar.plates[0].h01 < bar.plates[bar.plates.size() - 1].h01
	check(bar.plates.size() == AegisBarrier.layout(cfg.plate_count, cfg.shield_width, cfg.shield_height, cfg.plate_rows).size() and low_first, "Égide: %d placas em losango, de baixo para cima" % bar.plates.size())
	check(player.model.visible and cfg.plate_fill < 0.5, "Égide: personagem visível dentro (preenchimento %.2f)" % cfg.plate_fill)
	var pos0: Vector3 = player.global_position
	await wait(0.3)
	check(bar.global_position.distance_to(player.global_position) < 0.01, "Égide: círculo acompanha o jogador")
	# golpes: o escudo absorve (a vida não cai) e as rachaduras crescem
	var st: Dictionary = player.ability_data.aegis
	var mx: float = st.max
	var raw := func(final: float) -> float: return final / Game.damage_taken_mult()
	var src: Vector3 = player.global_position + Vector3(0, 1, 3)
	var avg_crack := func() -> float:
		var s := 0.0
		for p in bar.plates:
			s += p.damage()
		return s / bar.plates.size()
	player.invuln = 0.0
	var hp_hit: float = Game.hp   # a vida regenera com o tempo: compara com a de logo antes do golpe
	# compara com a integridade de logo antes do golpe (no mesmo quadro): um monstro solto que tenha batido na
	# barreira antes (no CI, às vezes) não muda a conta deste golpe
	var f_hit := AegisRules.fraction(st)
	player.take_damage(raw.call(mx * 0.4), src)
	var c1: float = avg_crack.call()
	check(is_equal_approx(Game.hp, hp_hit) and absf((f_hit - AegisRules.fraction(st)) - 0.4) < 0.02,
		"Égide: 40%% do escudo absorvido sem tocar na vida (integridade %.2f -> %.2f)" % [f_hit, AegisRules.fraction(st)])
	await wait(0.5)
	player.invuln = 0.0
	player.take_damage(raw.call(mx * 0.4), src)
	var c2: float = avg_crack.call()
	check(c1 > 0.0 and c2 > c1, "Égide: rachaduras crescem com o dano (%.2f -> %.2f)" % [c1, c2])
	check(bar.plates.any(func(p): return p.crack.visible), "Égide: efeito de rachadura aparece nas placas")
	await wait(0.5)
	# quebra: o que passa da integridade vai para a vida, a guarda cai e a barreira estoura
	player.invuln = 0.0
	var hp_b: float = Game.hp
	var excess: float = mx * 0.5 - float(st.integrity)   # o que passa do que restava logo antes do golpe
	player.take_damage(raw.call(mx * 0.5), src)
	check(player.ability == "" and st.broken, "Égide: integridade zero tira a proteção na hora")
	check(absf((hp_b - Game.hp) - excess) < 1.0, "Égide: só o excesso (%.1f) vai para a vida (perdeu %.1f)" % [excess, hp_b - Game.hp])
	check(bar.is_broken() and is_instance_valid(bar), "Égide: barreira entra na quebra (pulsação)")
	check(player.cooldowns.sword_aegis >= ItemDB.ABILITIES.sword_aegis.cooldown, "Égide: recarga começa no fim (%.1f s)" % player.cooldowns.sword_aegis)
	await wait(cfg.break_delay + 0.1)
	check(count_fx.call("AegisShards") >= 1 and count_fx.call("AegisDissipate") >= 1, "Égide: fragmentos e partículas na quebra")
	await wait(cfg.dissipate_time + 1.0)
	check(not is_instance_valid(bar), "Égide: barreira liberada depois da dissipação")
	check(count_fx.call("AegisShards") == 0 and count_fx.call("AegisDissipate") == 0, "Égide: fragmentos e partículas limpos")
	# soltar a tecla: dissolve sem estouro e também se libera
	player.cooldowns.sword_aegis = 0.0
	player.invuln = 0.0
	player.cast("sword_aegis")
	var bar2: AegisBarrier = player.ability_data.get("barrier")
	await wait(0.4)
	ShieldAbilities.release(player)
	check(player.ability == "" and bar2.state == AegisBarrier.State.DISSOLVING, "Égide: soltar a tecla dissolve o escudo")
	await wait(cfg.dissipate_time)
	check(not is_instance_valid(bar2) and count_fx.call("AegisDissipate") == 0, "Égide: dissolver também limpa tudo")
	player.invuln = 0.0
	var hp_c: float = Game.hp
	player.take_damage(raw.call(5.0), src)
	check(Game.hp < hp_c - 4.0, "Égide: sem escudo erguido o dano volta para a vida")
	await _check_aegis_wall(player, world, cfg)
	# tira o escudo: a Investida volta
	Game.unequip("offhand")
	await wait_until(func(): return Game.offhand_kind() == "")
	check(Game.ability_kit()[0] == "sword_charge", "Égide: sem escudo a habilidade 1 volta a ser a Investida")
	Game.hp = hp0
	player.global_position = pos0
	player.cooldowns.sword_aegis = 0.0
	player.invuln = 0.0


## Égide como parede: ao se formar empurra os monstros de perto; depois nenhum entra nem projétil atravessa (o
## golpe vai para o escudo); quebrou ou soltou, a parede some.
func _check_aegis_wall(player: Node, world: Node, cfg: AegisConfig) -> void:
	var back: Vector3 = player.global_position
	var spot := Vector3(-105, 0.3, 40)   # fora da vila (a guarda abate monstro lá dentro)
	player.global_position = spot
	player.velocity = Vector3.ZERO
	await wait(0.2)
	var mobs: Array = []
	for off in [Vector3(1.0, 0, 0.3), Vector3(-1.2, 0, 0.8), Vector3(0.4, 0, -1.5), Vector3(5.5, 0, 0)]:
		var e := Enemy.new()
		e.kind = "slime"
		world.add_child(e)
		e.global_position = spot + off
		e.home = e.global_position
		mobs.append(e)
	await wait(0.1)
	var flat := func(e: Node3D) -> float:
		return Vector2(e.global_position.x - player.global_position.x, e.global_position.z - player.global_position.z).length()
	check(flat.call(mobs[0]) < 1.5 and flat.call(mobs[1]) < 1.5, "Égide parede: monstros começam colados no jogador")
	player.cooldowns.sword_aegis = 0.0
	player.invuln = 0.0
	player.cast("sword_aegis")
	var wall: Dictionary = player.ability_data.get("wall", {})
	check(not wall.is_empty() and AegisWalls.walls.has(wall), "Égide parede: a parede entra no registro")
	await wait(0.15)
	var mid: float = flat.call(mobs[0])
	await wait(cfg.circle_form_time + cfg.barrier_form_time)
	var min_d := 99.0
	for e in mobs:
		if is_instance_valid(e) and not e.dead:
			min_d = minf(min_d, flat.call(e) - e.radius)
	check(mid > 1.0 and mid < cfg.shield_width, "Égide parede: o empurrão acompanha a formação (%.2f m no meio)" % mid)
	check(min_d >= cfg.shield_width - 0.05, "Égide parede: todos empurrados para fora (mais perto: %.2f m, raio %.1f)" % [min_d, cfg.shield_width])
	# os monstros perseguem o jogador por um tempo: nenhum entra
	for e in mobs:
		if is_instance_valid(e):
			e._set_state("chase")
			e.attack_cd = 0.0
	var st_w: Dictionary = player.ability_data.aegis
	var integ_w: float = st_w.integrity
	var hp_w: float = Game.hp
	# andar com a habilidade ativa: parado (a tecla de andar não move)
	var pos_w: Vector3 = player.global_position
	Input.action_press("move_forward")
	var worst := 99.0
	for _i in 25:
		await wait(0.1)
		for e in mobs:
			if is_instance_valid(e) and not e.dead:
				worst = minf(worst, flat.call(e) - e.radius)
	Input.action_release("move_forward")
	check(worst >= cfg.shield_width - 0.05, "Égide parede: perseguindo, nenhum entra (mais perto: %.2f m)" % worst)
	var moved_w := Vector2(player.global_position.x - pos_w.x, player.global_position.z - pos_w.z).length()
	check(moved_w < 0.05, "Égide: com a habilidade ativa o herói não anda (andou %.2f m segurando W)" % moved_w)
	check(float(st_w.integrity) < integ_w and Game.hp >= hp_w,
		"Égide parede: monstros corpo a corpo batem na barreira (integridade %.1f -> %.1f), vida intacta" % [integ_w, float(st_w.integrity)])
	# projétil de fora: para na coroa e o golpe vai para o escudo (a vida não cai)
	var st: Dictionary = player.ability_data.aegis
	var integ0: float = st.integrity
	var hp_a: float = Game.hp
	player.invuln = 0.0
	var arrow: Node3D = EnemyArrow_script().new()
	arrow.direction = Vector3(-1, 0, 0)
	arrow.damage = 6.0
	arrow.source = world
	world.add_child(arrow)
	arrow.global_position = player.global_position + Vector3(6.0, 1.0, 0.0)
	await wait(0.5)
	check(not is_instance_valid(arrow), "Égide parede: a flecha some na coroa")
	check(float(st.integrity) < integ0 and Game.hp >= hp_a,   # a vida pode regenerar na espera, nunca cair
		"Égide parede: o golpe da flecha vai para o escudo (%.1f -> %.1f), vida intacta" % [integ0, float(st.integrity)])
	# de dentro para fora passa: uma flecha (de monstro) saindo do centro não para na parede
	var out_arrow: Node3D = EnemyArrow_script().new()
	out_arrow.direction = Vector3(0, 0, 1)
	out_arrow.damage = 0.0
	world.add_child(out_arrow)
	out_arrow.global_position = player.global_position + Vector3(0.0, 1.0, 0.5)
	await wait(0.3)
	check(is_instance_valid(out_arrow) and flat.call(out_arrow) > cfg.shield_width, "Égide parede: de dentro para fora passa")
	if is_instance_valid(out_arrow):
		out_arrow.queue_free()
	# soltou: a parede sai do registro e os monstros podem chegar de novo
	ShieldAbilities.release(player)
	check(not AegisWalls.walls.has(wall), "Égide parede: soltou, a parede sai do registro")
	for e in mobs:
		if is_instance_valid(e):
			e.queue_free()
	await wait(0.1)
	player.global_position = back
	player.velocity = Vector3.ZERO
	player.cooldowns.sword_aegis = 0.0
	player.invuln = 0.0


## Martelo de Energia (espada + escudo, slot 4 / tecla 4, no lugar do Turbilhão): kit, círculo acima da cabeça girando, martelo saindo
## do círculo proporcional a ele (do tamanho do da Égide), câmera olhando para cima, círculo fechando antes da queda, queda no ponto certo, dano em área (os de
## dentro uma vez só, os de fora nada), crateras pela área, recarga, limpeza de tudo e o cancelamento pela esquiva.
func _check_hammer(player: Node, world: Node) -> void:
	var cfg: HammerConfig = HammerAbilities.CONFIG
	var back: Vector3 = player.global_position
	var lv0: int = Game.level
	Econ.test_force_level(maxi(lv0, 3))
	Game.add_item("wooden_shield")
	equip_any("wooden_shield")
	await wait_until(func(): return Game.offhand_kind() == "shield" and Game.level >= 3)
	var kit := Game.ability_kit()
	check(kit.size() == 5 and kit[4] == "sword_rally" and kit[3] == "sword_hammer" and kit[1] == "sword_earthquake" and not ("sword_whirl" in kit),
		"Martelo: espada + escudo troca a habilidade 4 (%s)" % [kit])
	check(Game.knows_ability("sword_hammer"), "Martelo: liberado no nível %d" % ItemDB.ABILITIES.sword_hammer.level)
	var count_fx := func(cls: String) -> int:
		var n := 0
		for c in get_tree().current_scene.find_children("*", cls, true, false):
			if not c.is_queued_for_deletion():
				n += 1
		return n
	var spot := Vector3(-105, 0.3, 40)   # fora da vila (a guarda abate monstro lá dentro)
	player.global_position = spot
	player.velocity = Vector3.ZERO
	player.model.rotation.y = 0.0     # olhando para +Z: o martelo cai em spot + (0, 0, forward_offset)
	await wait(0.25)
	await wait_until(func(): return player.ability == "" and not player.attacking and player.dodge_timer <= 0.0)
	var center: Vector3 = player.global_position + Vector3(0, 0, cfg.forward_offset)
	# monstros parados (sem física de movimento): 3 dentro do raio, 2 fora
	var mobs: Array = []
	for off in [Vector3(1.5, 0, 0.5), Vector3(-2.2, 0, 1.4), Vector3(0.4, 0, -3.3), Vector3(cfg.radius + 2.5, 0, 0), Vector3(-cfg.radius - 3.0, 0, 2.0)]:
		var e := Enemy.new()
		e.kind = "slime"
		world.add_child(e)
		e.global_position = center + off
		e.home = e.global_position
		mobs.append(e)
	await wait(0.15)
	for e in mobs:
		e.set_physics_process(false)
	var inside := mobs.slice(0, 3)
	var outside := mobs.slice(3)
	var hp0 := {}
	for e in mobs:
		hp0[e] = e.hp
	var hp_player: float = Game.hp
	player.cooldowns.sword_hammer = 0.0
	player.invuln = 99.0   # os monstros não interferem (o teste é do golpe)
	player.cast("sword_hammer")
	check(player.ability == "sword_hammer", "Martelo: a habilidade começa na tecla 4")
	var skill: HammerSkill = player.ability_data.get("skill")
	check(is_instance_valid(skill) and skill.get_parent() == get_tree().current_scene, "Martelo: HammerSkill na cena do mundo")
	var cd: float = player.cooldowns.sword_hammer
	check(cd >= cfg.cooldown * Game.cooldown_mult() - 0.01, "Martelo: recarga do HammerConfig (%.1f s)" % cd)
	# círculo acima da cabeça, girando
	await wait(cfg.circle_form_time * 0.5)
	var c_pos: Vector3 = skill.circle.global_position
	var above: float = c_pos.y - player.global_position.y
	var flat_c := Vector2(c_pos.x - center.x, c_pos.z - center.z).length()
	check(skill.circle.visible and above > 2.2 and absf(above - cfg.circle_height) < 0.05 and flat_c < 0.05,
		"Martelo: círculo aparece %.2f m acima do herói, sobre o ponto do golpe" % above)
	var a0: float = skill.circle.spin_angle
	await wait(0.2)
	check(skill.circle.spin_angle > a0 + 0.05, "Martelo: círculo gira (%.2f -> %.2f rad)" % [a0, skill.circle.spin_angle])
	check(skill.circle.formed() > 0.0, "Martelo: círculo se materializa aos poucos (%.2f)" % skill.circle.formed())
	# o martelo sai de dentro do círculo: a cabeça abaixo do plano do círculo, o cabo ainda acima
	await wait_until(func(): return skill.state == HammerSkill.State.FORM)
	await wait(cfg.formation_time * 0.45)
	var plane: float = skill.global_position.y + cfg.circle_height
	check(skill.hammer.visible and skill.hammer.bottom_y() < plane - 0.3 and skill.hammer.top_y() > plane + 0.3,
		"Martelo: sai de dentro do círculo, cabeça primeiro (base %.2f, topo %.2f, círculo %.2f)" % [skill.hammer.bottom_y(), skill.hammer.top_y(), plane])
	check(absf(skill.hammer.length / cfg.circle_radius - 3.6 / 1.7) < 0.2 and is_equal_approx(cfg.circle_radius, ShieldAbilities.CONFIG.circle_radius),
		"Martelo: círculo do tamanho do da Égide (%.2f m) e martelo proporcional (%.2f m)" % [cfg.circle_radius, skill.hammer.length])
	check(player.cam_tilt > 0.1 and player.cam_back > 1.0, "Martelo: a câmera recua e olha para cima enquanto invoca (%.2f rad)" % player.cam_tilt)
	# andar não move o herói enquanto invoca
	var pos_w: Vector3 = player.global_position
	Input.action_press("move_forward")
	await wait(0.3)
	Input.action_release("move_forward")
	check(Vector2(player.global_position.x - pos_w.x, player.global_position.z - pos_w.z).length() < 0.05,
		"Martelo: parado enquanto invoca")
	# o círculo fecha antes da queda
	await wait_until(func(): return skill.state >= HammerSkill.State.CLOSE, 3.0)
	check(skill.state == HammerSkill.State.CLOSE and skill.circle.state == MagicCircle.State.CLOSING,
		"Martelo: martelo pronto, o círculo começa a fechar")
	await wait_until(func(): return skill.state >= HammerSkill.State.FALL, 3.0)
	check(skill.circle.is_closed() and skill.hammer.visible, "Martelo: círculo fechado antes da queda, martelo continua visível")
	var y_fall0: float = skill.hammer.bottom_y()
	await wait(cfg.fall_time() * 0.5)
	var y_mid: float = skill.hammer.bottom_y()
	check(y_mid < y_fall0 or skill.impact_at >= 0.0, "Martelo: cai (%.2f -> %.2f)" % [y_fall0, y_mid])
	await wait_until(func(): return skill.impact_at >= 0.0, 2.0)
	var ic: Vector3 = skill.impact_center
	check(Vector2(ic.x - center.x, ic.z - center.z).length() < 0.05 and absf(skill.hammer.bottom_y() - ic.y) < 0.3,
		"Martelo: cai no ponto certo, à frente do herói (%.2f m do esperado)" % Vector2(ic.x - center.x, ic.z - center.z).length())
	await wait(0.05)
	var hp1 := {}
	for e in mobs:
		hp1[e] = e.hp if is_instance_valid(e) else -1.0
	var hit_in := inside.filter(func(e): return not is_instance_valid(e) or e.dead or float(hp1[e]) < float(hp0[e]))
	check(hit_in.size() == inside.size() and skill.hit_count == inside.size(),
		"Martelo: todos os %d monstros dentro do raio levam dano (%d)" % [inside.size(), hit_in.size()])
	check(outside.all(func(e): return is_instance_valid(e) and is_equal_approx(e.hp, float(hp0[e]))),
		"Martelo: monstros fora do raio não levam dano")
	check(is_equal_approx(Game.hp, hp_player) or Game.hp >= hp_player, "Martelo: o próprio herói não leva dano")
	check(count_fx.call("HammerImpact") == 1, "Martelo: explosão no impacto")
	var shocks: Array = skill.find_children("*", "HammerGroundShock", false, false)
	var gs: HammerGroundShock = shocks[0] if shocks.size() == 1 else null
	check(gs != null and gs.has_node("Shock") and gs.find_children("*", "Decal", false, false).size() == 1 + HammerGroundShock.SIDE_DECALS
		and gs.find_children("*", "GPUParticles3D", false, false).size() == 3,
		"Martelo: choque no chão (onda de choque da sheet, %d rachaduras projetadas, detritos/brasas/fumaça)" % (1 + HammerGroundShock.SIDE_DECALS))
	check(player.shake > 0.3, "Martelo: a câmera treme no impacto (%.2f)" % player.shake)
	await wait(cfg.crater_max_distance / cfg.crater_wave_speed + 0.2)
	var craters: Array = get_tree().current_scene.find_children("*", "GroundCrater", true, false)
	var far := 0.0
	var spread := {}
	for c in craters:
		var d := Vector2(c.global_position.x - ic.x, c.global_position.z - ic.z)
		far = maxf(far, d.length())
		spread[int(floor((atan2(d.y, d.x) + PI) / (TAU / 4.0))) % 4] = true
	check(craters.size() == cfg.crater_count and far <= cfg.radius and spread.size() == 4,
		"Martelo: %d crateras espalhadas pela área (mais longe %.2f m, raio %.1f)" % [craters.size(), far, cfg.radius])
	# cada um levou dano uma vez só
	await wait(0.5)
	check(inside.all(func(e): return not is_instance_valid(e) or e.dead or is_equal_approx(e.hp, float(hp1[e]))),
		"Martelo: cada monstro leva dano uma vez por ativação")
	await wait_until(func(): return player.ability == "", 2.0)
	check(player.ability == "", "Martelo: o herói fica livre depois do impacto")
	check(player.cam_tilt == 0.0, "Martelo: a câmera volta ao normal no fim")
	# o martelo some e tudo é liberado
	await wait_until(func(): return not is_instance_valid(skill), cfg.linger_time + cfg.dissolve_time + cfg.crater_life + 3.0)
	check(not is_instance_valid(skill) and count_fx.call("GroundCrater") == 0 and count_fx.call("HammerImpact") == 0
		and count_fx.call("HammerDissolve") == 0 and count_fx.call("HammerGroundShock") == 0
		and get_tree().current_scene.find_children("CrackDecal*", "Decal", true, false).is_empty(),
		"Martelo: martelo, crateras, choque no chão e efeitos removidos no fim")
	# esquiva antes da queda cancela: sem dano e tudo se desfaz
	for e in mobs:
		if is_instance_valid(e) and not e.dead:
			hp0[e] = e.hp
	player.cooldowns.sword_hammer = 0.0
	player.cast("sword_hammer")
	var skill2: HammerSkill = player.ability_data.get("skill")
	await wait(cfg.circle_form_time + 0.2)
	check(HammerAbilities.can_dodge_cancel(player), "Martelo: esquiva pode cancelar antes da queda")
	HammerAbilities.dodge_cancel(player)
	check(player.ability == "" and skill2.state == HammerSkill.State.CANCELED, "Martelo: cancelado pela esquiva")
	await wait_until(func(): return not is_instance_valid(skill2), 2.0)
	check(not is_instance_valid(skill2) and mobs.all(func(e): return not is_instance_valid(e) or e.dead or is_equal_approx(e.hp, float(hp0[e]))),
		"Martelo: cancelado não fere ninguém e se libera")
	for e in mobs:
		if is_instance_valid(e):
			e.queue_free()
	# tira o escudo: o Turbilhão volta
	Game.unequip("offhand")
	await wait_until(func(): return Game.offhand_kind() == "")
	check(Game.ability_kit()[3] == "sword_whirl", "Martelo: sem escudo a habilidade 4 volta a ser o Turbilhão")
	Econ.test_force_level(lv0)
	player.global_position = back
	player.velocity = Vector3.ZERO
	player.cooldowns.sword_hammer = 0.0
	player.invuln = 0.0
	Game.hp = hp_player


## Corte do Abismo (montante, slot 2 / tecla 2, no lugar do Golpe Sísmico): kit, a corrida arrastando a lâmina (avança,
## fagulhas acesas, para perto do inimigo à frente), o corte que fere quem está à frente, as garras que ferem quem está em
## cima delas (cada um uma vez em cada), quem está fora sem dano, limpeza de tudo e o cancelamento pela esquiva na corrida.
func _check_drag_slash(player: Node, world: Node) -> void:
	var cfg: DragSlashConfig = DragSlashAbilities.CONFIG
	var back: Vector3 = player.global_position
	var lv0: int = Game.level
	var weapon0: String = Game.equipment.get("weapon", "")
	Game.add_item("iron_zweihander")
	equip_any("iron_zweihander")
	Econ.test_force_level(maxi(Game.level, int(ItemDB.ABILITIES.sword_drag.level)))
	await wait_until(func(): return Game.offhand_kind() == "two_handed" and Game.level >= 3)
	var kit := Game.ability_kit()
	check(kit.size() >= 2 and kit[1] == "sword_drag" and not ("sword_quake" in kit), "Corte do Abismo: a montante troca a habilidade 2 (%s)" % [kit])
	player.global_position = Vector3(-105, 0.3, 40)   # fora da vila
	player.velocity = Vector3.ZERO
	player.model.rotation.y = 0.0     # olhando para +Z
	await wait(0.25)
	await wait_until(func(): return player.ability == "" and not player.attacking and player.dodge_timer <= 0.0)
	player.cooldowns["sword_drag"] = 0.0
	var origin: Vector3 = player.global_position
	var f := Vector3(0, 0, 1)
	# A no caminho (a corrida para nele: leva o corte e a primeira garra), B mais à frente (só uma garra), C de lado e D
	# atrás (fora)
	var mobs: Array = []
	for p in [origin + f * 4.5, origin + f * 7.6 + Vector3(0.3, 0, 0), origin + f * 5.0 + Vector3(7.0, 0, 0), origin - f * 4.0]:
		var e := Enemy.new()
		e.kind = "slime"
		world.add_child(e)
		e.global_position = p
		e.home = p
		mobs.append(e)
	await wait(0.15)
	for e in mobs:
		e.set_physics_process(false)
	var hp0 := {}
	for e in mobs:
		hp0[e] = e.hp
	var hp_player: float = Game.hp
	player.invuln = 99.0
	player.use_slot(2)
	check(player.ability == "sword_drag", "Corte do Abismo: começa na tecla 2")
	var skill: DragAndSlash = player.ability_data.get("skill")
	check(is_instance_valid(skill) and skill.get_parent() == get_tree().current_scene, "Corte do Abismo: a cena do golpe na cena do mundo")
	check(DragSlashAbilities.can_dodge_cancel(player), "Corte do Abismo: a esquiva cancela na corrida")
	await wait_until(func(): return int(player.ability_data.get("phase", 0)) == DragSlashRules.DASH, 1.0)
	await wait(0.12)
	var spd := Vector2(player.velocity.x, player.velocity.z).length()
	check(spd > 8.6 and Vector2(player.velocity.x, player.velocity.z).normalized().dot(Vector2(0, 1)) > 0.95,
		"Corte do Abismo: dispara correndo para a frente (%.1f m/s)" % spd)
	check(skill.sparks.emitting and skill._contact > 0.3, "Corte do Abismo: a ponta raspa o chão e solta fagulhas")
	await wait_until(func(): return int(player.ability_data.get("phase", 0)) == DragSlashRules.SLASH, 2.0)
	var ran := Vector2(player.global_position.x - origin.x, player.global_position.z - origin.z).length()
	var gap := Vector2(mobs[0].global_position.x - player.global_position.x, mobs[0].global_position.z - player.global_position.z).length()
	check(ran > 1.2 and gap < cfg.stop_distance + 1.4, "Corte do Abismo: corre e para perto do inimigo à frente (%.1f m corridos, %.1f m dele)" % [ran, gap])
	check(not DragSlashAbilities.can_dodge_cancel(player), "Corte do Abismo: no corte a esquiva não cancela mais")
	await wait_until(func(): return skill.hit_at >= 0.0, 2.0)
	await wait(cfg.claw_stagger * cfg.claw_count + 0.25)
	check(not is_instance_valid(mobs[0]) or mobs[0].dead or mobs[0].hp < float(hp0[mobs[0]]), "Corte do Abismo: o corte fere quem parou a corrida")
	check(skill.hit_count == 1, "Corte do Abismo: o corte pega só quem está à frente (%d)" % skill.hit_count)
	check(not is_instance_valid(mobs[1]) or mobs[1].dead or mobs[1].hp < float(hp0[mobs[1]]), "Corte do Abismo: as garras ferem quem está mais à frente")
	check(skill.claw_hit_count == 2, "Corte do Abismo: cada um leva uma garra (%d)" % skill.claw_hit_count)
	check(mobs.slice(2).all(func(e): return is_instance_valid(e) and is_equal_approx(e.hp, float(hp0[e]))), "Corte do Abismo: quem está fora não leva dano")
	check(Game.hp >= hp_player - 0.01, "Corte do Abismo: o herói não se fere")
	await wait_until(func(): return player.ability == "", cfg.slash_total() + 1.0)
	check(player.ability == "", "Corte do Abismo: termina e solta o herói")
	var skill_ref: WeakRef = weakref(skill)
	await wait_until(func(): return skill_ref.get_ref() == null, cfg.claw_life + cfg.groove_life + 3.0)
	check(skill_ref.get_ref() == null, "Corte do Abismo: fagulhas, rastro e garras removidos no fim")
	# esquiva na corrida cancela: sem dano e tudo se desfaz
	for e in mobs:
		if is_instance_valid(e) and not e.dead:
			hp0[e] = e.hp
	await wait(0.3)
	player.cooldowns["sword_drag"] = 0.0
	player.model.rotation.y = PI   # para trás, longe dos monstros que sobraram
	player.cast("sword_drag")
	var skill2: DragAndSlash = player.ability_data.get("skill")
	await wait(cfg.windup_time + 0.08)
	player._dodge_pressed(Vector3.BACK)
	check(player.ability == "" and is_instance_valid(skill2) and skill2.state == DragAndSlash.State.CANCELED, "Corte do Abismo: cancelado pela esquiva")
	var skill2_ref: WeakRef = weakref(skill2)
	await wait_until(func(): return skill2_ref.get_ref() == null, cfg.groove_life + 2.0)
	check(skill2_ref.get_ref() == null and mobs.all(func(e): return not is_instance_valid(e) or e.dead or is_equal_approx(e.hp, float(hp0[e]))),
		"Corte do Abismo: cancelado não fere ninguém e se libera")
	for e in mobs:
		if is_instance_valid(e):
			e.queue_free()
	if weapon0 != "":
		equip_any(weapon0)
	await wait_until(func(): return Game.offhand_kind() == "")
	check(Game.ability_kit()[1] == "sword_quake", "Corte do Abismo: sem a montante a habilidade 2 volta a ser o Golpe Sísmico")
	Econ.test_force_level(lv0)
	await wait(0.6)
	player.global_position = back


## Lâmina Suprema (montante, slot 4 / tecla 4, no lugar do Turbilhão, gasta a fúria): kit, herói parado do começo ao fim,
## espada de energia se formando até ~3x a altura dele durante a carga, impacto no ponto à frente na hora certa, a rachadura
## reta no chão, dano no ponto do golpe e no caminho do corte (uma vez só), os de fora sem dano, limpeza de tudo e o
## cancelamento pela esquiva durante a carga.
func _check_supreme(player: Node, world: Node) -> void:
	var cfg: GreatswordSupremeConfig = GreatswordSupremeAbilities.CONFIG
	var back: Vector3 = player.global_position
	var lv0: int = Game.level
	var weapon0: String = Game.equipment.get("weapon", "")
	Game.add_item("iron_zweihander")
	equip_any("iron_zweihander")
	Econ.test_force_level(maxi(Game.level, int(ItemDB.ABILITIES.sword_supreme.level)))
	await wait_until(func(): return Game.offhand_kind() == "two_handed" and Game.level >= 8)
	var kit := Game.ability_kit()
	check(kit.size() == 5 and kit[3] == "sword_supreme" and not ("sword_whirl" in kit), "Lâmina Suprema: a montante troca a habilidade 4 (%s)" % [kit])
	var spot := Vector3(-105, 0.3, 40)   # fora da vila
	player.global_position = spot
	player.velocity = Vector3.ZERO
	player.model.rotation.y = 0.0     # olhando para +Z
	await wait(0.25)
	await wait_until(func(): return player.ability == "" and not player.attacking and player.dodge_timer <= 0.0)
	var origin: Vector3 = player.global_position
	var center: Vector3 = origin + Vector3(0, 0, cfg.impact_distance)
	# monstros parados: 2 no ponto do golpe, 1 no caminho do corte, 2 fora (dos lados e atrás)
	var mobs: Array = []
	for p in [center + Vector3(1.5, 0, 0.5), center + Vector3(-1.0, 0, 1.8), origin + Vector3(0.4, 0, 1.0),
			center + Vector3(cfg.impact_radius + 3.0, 0, 0), origin + Vector3(0, 0, -4.5)]:
		var e := Enemy.new()
		e.kind = "slime"
		world.add_child(e)
		e.global_position = p
		e.home = p
		mobs.append(e)
	await wait(0.15)
	for e in mobs:
		e.set_physics_process(false)
	var inside := mobs.slice(0, 3)
	var outside := mobs.slice(3)
	var hp0 := {}
	for e in mobs:
		hp0[e] = e.hp
	var hp_player: float = Game.hp
	player.invuln = 99.0
	Game.fury = 0.0
	player.cast("sword_supreme")
	check(player.ability == "", "Lâmina Suprema: sem fúria cheia não começa")
	Game.fury = 100.0
	player.use_slot(4)
	check(player.ability == "sword_supreme" and Game.fury == 0.0, "Lâmina Suprema: começa na tecla 4 e gasta a fúria")
	var skill: GreatswordSupremeSlash = player.ability_data.get("skill")
	check(is_instance_valid(skill) and skill.get_parent() == get_tree().current_scene, "Lâmina Suprema: a cena do golpe na cena do mundo")
	# carga: parado (mesmo com a tecla de andar) e a espada pegando fogo da guarda para a ponta
	await wait(cfg.raise_time + cfg.charge_time * 0.5)
	var pos_mid: Vector3 = player.global_position
	Input.action_press("move_right")
	await wait(0.3)
	Input.action_release("move_right")
	var moved := Vector2(player.global_position.x - pos_mid.x, player.global_position.z - pos_mid.z).length()
	check(moved < 0.05, "Lâmina Suprema: o herói não anda durante a habilidade (%.2f m com a tecla de andar)" % moved)
	var len_mid: float = skill.sword_len()
	check(float(skill.energy_sword.get_instance_shader_parameter("heat")) > 0.99 and len_mid > 1.6 and len_mid < cfg.sword_length - 0.5,
		"Lâmina Suprema: a energia já cobre a espada e está crescendo (%.2f m)" % len_mid)
	check(player.cam_back > 1.0, "Lâmina Suprema: a câmera recua")
	await wait_until(func(): return skill.state == GreatswordSupremeSlash.State.SLASH)
	var len_full: float = skill.sword_pivot.global_basis.y.length()
	check(len_full >= cfg.sword_length - 0.01 and len_full > 5.0 and skill.energy_sword.mesh != null,
		"Lâmina Suprema: espada de energia formada ~3x a altura do herói (%.2f m)" % len_full)
	check(not GreatswordSupremeAbilities.can_dodge_cancel(player), "Lâmina Suprema: no corte a esquiva não cancela mais")
	await wait_until(func(): return skill.impact_at >= 0.0, 3.0)
	check(absf(skill.impact_at - cfg.impact_time()) < 0.1, "Lâmina Suprema: impacto na hora (%.2f s)" % skill.impact_at)
	var flat := Vector2(skill.impact_center.x - center.x, skill.impact_center.z - center.z).length()
	check(flat < 0.1, "Lâmina Suprema: a espada bate à frente do herói (%.2f m do ponto)" % flat)
	var crack_dir: Vector3 = skill.crack.global_basis.z.normalized()
	await wait(0.4)   # a cratera corre pelo chão
	check(skill.impact_root.visible and skill.crack.texture_albedo != null and is_equal_approx(skill.crack.size.z, cfg.crack_length())
		and is_equal_approx(skill.crack.size.x, cfg.crack_width * GreatswordSupremeSlash.DECAL_WIDTH) and is_equal_approx(cfg.crack_width, 3.0)
		and absf(crack_dir.dot(Vector3(0, 0, 1))) > 0.99, "Lâmina Suprema: cratera reta de 3 m de largura, na direção do golpe (%.1f m)" % skill.crack.size.z)
	check(skill.souls_spawned == cfg.soul_count and is_instance_valid(skill.souls) and skill.souls.active_count() > 0,
		"Lâmina Suprema: almas saem voando da cratera (%d)" % skill.souls_spawned)
	check(inside.all(func(e): return not is_instance_valid(e) or e.dead or e.hp < float(hp0[e])),
		"Lâmina Suprema: fere quem está no ponto do golpe e no caminho do corte (%d atingidos)" % skill.hit_count)
	check(outside.all(func(e): return is_instance_valid(e) and is_equal_approx(e.hp, float(hp0[e]))), "Lâmina Suprema: quem está fora não leva dano")
	check(skill.hit_count == 3, "Lâmina Suprema: cada um uma vez (%d)" % skill.hit_count)
	check(Game.hp >= hp_player - 0.01, "Lâmina Suprema: o herói não se fere (%.1f -> %.1f)" % [hp_player, Game.hp])
	await wait_until(func(): return player.ability == "", cfg.kneel_time + cfg.rise_time + 1.0)
	check(player.ability == "" and player.cam_back == 0.0, "Lâmina Suprema: termina e solta o herói")
	var skill_ref: WeakRef = weakref(skill)   # (a lambda não captura o nó: ele é liberado no meio da espera)
	await wait_until(func(): return skill_ref.get_ref() == null, cfg.crack_hold + cfg.fade_time + 2.0)
	check(skill_ref.get_ref() == null, "Lâmina Suprema: rachadura, partículas e espada removidas no fim")
	# esquiva durante a carga cancela: sem dano e tudo se desfaz
	for e in mobs:
		if is_instance_valid(e) and not e.dead:
			hp0[e] = e.hp
	Game.fury = 100.0
	player.cast("sword_supreme")
	var skill2: GreatswordSupremeSlash = player.ability_data.get("skill")
	await wait(cfg.raise_time + 0.3)
	check(GreatswordSupremeAbilities.can_dodge_cancel(player), "Lâmina Suprema: a esquiva cancela durante a carga")
	player._dodge_pressed(Vector3.BACK)
	check(player.ability == "" and is_instance_valid(skill2) and skill2.state == GreatswordSupremeSlash.State.CANCELED, "Lâmina Suprema: cancelada pela esquiva")
	var skill2_ref: WeakRef = weakref(skill2)
	await wait_until(func(): return skill2_ref.get_ref() == null, 2.0)
	check(skill2_ref.get_ref() == null and mobs.all(func(e): return not is_instance_valid(e) or e.dead or is_equal_approx(e.hp, float(hp0[e]))),
		"Lâmina Suprema: cancelada não fere ninguém e se libera")
	for e in mobs:
		if is_instance_valid(e):
			e.queue_free()
	# volta para a espada de antes: o Turbilhão volta
	if weapon0 != "":
		equip_any(weapon0)
	await wait_until(func(): return Game.offhand_kind() == "")
	check(Game.ability_kit()[3] == "sword_whirl", "Lâmina Suprema: sem a montante a habilidade 4 volta a ser o Turbilhão")
	Econ.test_force_level(lv0)
	await wait(0.6)   # a esquiva do cancelamento termina
	player.global_position = back
	player.velocity = Vector3.ZERO
	player.invuln = 0.0
	Game.fury = 0.0
	Game.hp = hp_player


## Ciclone de Aço (montante, slot 1 / tecla 1, no lugar da Investida): kit, recarga, herói preso no lugar enquanto gira, o
## modelo girando e parando virado para onde começou, vários cortes (com intervalo por alvo) em quem está no alcance, os
## de fora sem dano, limpeza da cena, o giro começando assim que aciona (a esquiva não interrompe) e o fim antecipado.
func _check_spin(player: Node, world: Node) -> void:
	var cfg: GreatswordSpinConfig = GreatswordSpinAbilities.CONFIG
	var back: Vector3 = player.global_position
	var lv0: int = Game.level
	var weapon0: String = Game.equipment.get("weapon", "")
	var fury0: float = Game.fury
	Game.add_item("iron_zweihander")
	Econ.test_force_level(maxi(Game.level, CharRules.item_level(Balance.tables, "iron_zweihander")))
	equip_any("iron_zweihander")
	await wait_until(func(): return Game.offhand_kind() == "two_handed")
	var kit := Game.ability_kit()
	check(kit.size() >= 1 and kit[0] == "sword_spin" and not ("sword_charge" in kit), "Ciclone de Aço: a montante troca a habilidade 1 (%s)" % [kit])
	var spot := Vector3(-105, 0.3, 36)   # fora da vila
	player.global_position = spot
	player.velocity = Vector3.ZERO
	player.model.rotation.y = 0.0
	await wait(0.25)
	await wait_until(func(): return player.ability == "" and not player.attacking and player.dodge_timer <= 0.0)
	var origin: Vector3 = player.global_position
	# monstros parados: 3 em volta (frente, lado e atrás: o giro corta em volta) e 1 fora do alcance
	var mobs: Array = []
	for p in [origin + Vector3(0, 0, 1.8), origin + Vector3(2.0, 0, 0.4), origin + Vector3(-0.6, 0, -2.2),
			origin + Vector3(cfg.radius + 4.0, 0, 0)]:
		var e := Enemy.new()
		e.kind = "slime"
		world.add_child(e)
		e.global_position = p
		e.home = p
		mobs.append(e)
	await wait(0.15)
	for e in mobs:
		e.set_physics_process(false)
	var inside := mobs.slice(0, 3)
	var outside := mobs.slice(3)
	var hp0 := {}
	for e in mobs:
		hp0[e] = e.hp
	var hp_player: float = Game.hp
	player.invuln = 99.0
	player.cooldowns["sword_spin"] = 0.0
	player.use_slot(1)
	check(player.ability == "sword_spin" and player.cooldowns["sword_spin"] > 0.0, "Ciclone de Aço: começa na tecla 1 e entra em recarga")
	var skill: GreatswordSpinSlash = player.ability_data.get("skill")
	check(is_instance_valid(skill) and skill.get_parent() == get_tree().current_scene, "Ciclone de Aço: a cena do giro na cena do mundo")
	var yaw0: float = player.model.rotation.y
	var d := GreatswordSpinAbilities.durations()
	# no meio do giro: anda para onde a tecla de andar manda, o modelo virando e cortes saindo
	await wait(d[0] + d[1] + d[2] * 0.3)
	var pos_mid: Vector3 = player.global_position
	var yaw_mid: float = player.model.rotation.y
	Input.action_press("move_right")
	await wait(0.3)
	Input.action_release("move_right")
	var moved := Vector2(player.global_position.x - pos_mid.x, player.global_position.z - pos_mid.z).length()
	check(moved > 0.3, "Ciclone de Aço: o herói anda enquanto gira (%.2f m com a tecla de andar)" % moved)
	check(absf(wrapf(player.model.rotation.y - yaw_mid, -PI, PI)) > 0.05, "Ciclone de Aço: o herói gira no próprio eixo")
	check(skill.phase == GreatswordSpinRules.Phase.SPIN and skill.trail.strength() > 0.9 and skill.trail.sample_count() > 4,
		"Ciclone de Aço: a energia sombria segue o corte enquanto gira (%.2f, %d pontos)" % [skill.trail.strength(), skill.trail.sample_count()])
	check(not GreatswordSpinAbilities.can_dodge_cancel(player), "Ciclone de Aço: girando, a esquiva não cancela")
	await wait_until(func(): return player.ability == "", GreatswordSpinAbilities.total_time() + 1.0)
	check(player.ability == "" and player.cam_back == 0.0, "Ciclone de Aço: para e solta o herói")
	check(absf(wrapf(player.model.rotation.y - yaw0, -PI, PI)) < 0.05, "Ciclone de Aço: termina virado para onde começou")
	check(inside.all(func(e): return not is_instance_valid(e) or e.dead or e.hp < float(hp0[e])),
		"Ciclone de Aço: corta quem está em volta (%d cortes)" % skill.hit_count)
	check(outside.all(func(e): return is_instance_valid(e) and is_equal_approx(e.hp, float(hp0[e]))), "Ciclone de Aço: quem está fora não leva dano")
	# cortes repetidos, mas com intervalo: nunca mais que o giro inteiro dividido pelo intervalo, por alvo
	var span := d[1] + d[2] + d[3]
	var max_hits := inside.size() * (int(span / cfg.hit_interval) + 1)
	check(skill.hit_count > inside.size() and skill.hit_count <= max_hits,
		"Ciclone de Aço: vários cortes com intervalo por alvo (%d, máx. %d)" % [skill.hit_count, max_hits])
	check(Game.hp >= hp_player - 0.01, "Ciclone de Aço: o herói não se fere")
	var skill_ref: WeakRef = weakref(skill)
	await wait_until(func(): return skill_ref.get_ref() == null, cfg.fade_time + 2.0)
	check(skill_ref.get_ref() == null, "Ciclone de Aço: rastro sombrio e partículas removidos no fim")
	# o giro começa assim que aciona (sem postura parada) e a esquiva não o interrompe
	player.cooldowns["sword_spin"] = 0.0
	Game.stamina = Game.max_stamina()
	var yaw_start: float = player.model.rotation.y
	player.use_slot(1)
	var skill2: GreatswordSpinSlash = player.ability_data.get("skill")
	check(not GreatswordSpinAbilities.can_dodge_cancel(player), "Ciclone de Aço: a esquiva não cancela desde o começo")
	await wait(0.2)
	check(absf(wrapf(player.model.rotation.y - yaw_start, -PI, PI)) > 0.1 and skill2.phase != GreatswordSpinRules.Phase.STANCE,
		"Ciclone de Aço: já gira logo depois de acionar (%.2f rad em 0,2 s)" % absf(wrapf(player.model.rotation.y - yaw_start, -PI, PI)))
	player._dodge_pressed(Vector3.BACK)
	check(player.ability == "sword_spin" and player.dodge_timer <= 0.0, "Ciclone de Aço: a esquiva não interrompe o giro")
	# interrompido de fora (morte, troca de arma): o visual se apaga depressa e se libera
	player.end_ability()
	check(player.ability == "" and is_instance_valid(skill2) and skill2.stopped, "Ciclone de Aço: interrompido apaga o visual")
	var skill2_ref: WeakRef = weakref(skill2)
	await wait_until(func(): return skill2_ref.get_ref() == null, 2.0)
	check(skill2_ref.get_ref() == null, "Ciclone de Aço: interrompido se libera")
	for e in mobs:
		if is_instance_valid(e):
			e.queue_free()
	# volta para a espada de antes: a Investida volta
	if weapon0 != "":
		equip_any(weapon0)
	await wait_until(func(): return Game.offhand_kind() == "")
	check(Game.ability_kit()[0] == "sword_charge", "Ciclone de Aço: sem a montante a habilidade 1 volta a ser a Investida")
	Econ.test_force_level(lv0)
	await wait(0.6)   # a esquiva do cancelamento termina
	player.global_position = back
	player.velocity = Vector3.ZERO
	player.invuln = 0.0
	Game.fury = fury0   # os cortes enchem a fúria: as checagens seguintes contam com ela como estava
	Game.stamina = Game.max_stamina()
	Game.hp = hp_player


## Dança do Abismo (montante, tecla 3; a Fúria Picante vai para a tecla 5): kit e barra de ações com 5 teclas, o combo
## dos quatro golpes do Mixamo sempre começando pelo deslize, o herói andando com os golpes (a tecla de andar não manda),
## o rastro sombrio acendendo nos cortes, dano em quem está no caminho e nada em quem está longe, o golpe final com as
## garras, limpeza da cena no fim, a esquiva cancelando no meio e a Fúria da tecla 5 dando o mesmo buff.
func _check_dark_combo(player: Node, world: Node) -> void:
	var cfg: GreatswordDarkComboConfig = GreatswordDarkComboAbilities.CONFIG
	var back: Vector3 = player.global_position
	var lv0: int = Game.level
	var weapon0: String = Game.equipment.get("weapon", "")
	Game.add_item("iron_zweihander")
	Econ.test_force_level(maxi(Game.level, int(ItemDB.ABILITIES.sword_dark_combo.level)))
	equip_any("iron_zweihander")
	await wait_until(func(): return Game.offhand_kind() == "two_handed" and Game.level >= 5)
	var kit := Game.ability_kit()
	check(kit.size() == 5 and kit[2] == "sword_dark_combo" and kit[4] == "sword_fury_great" and not ("sword_fury" in kit),
		"Dança do Abismo: a montante põe o combo na tecla 3 e a Fúria na 5 (%s)" % [kit])
	await wait(0.1)
	var hud = world.hud
	check(hud.slots["slot_5"].visible and hud._slot_ids[2] == "sword_dark_combo" and hud._slot_ids[4] == "sword_fury_great",
		"Dança do Abismo: a barra da montante mostra a tecla 5 (%s)" % [hud._slot_ids])
	var spot := Vector3(-105, 0.3, 44)   # fora da vila
	player.global_position = spot
	player.velocity = Vector3.ZERO
	player.model.rotation.y = 0.0     # olhando para +Z
	await wait(0.25)
	await wait_until(func(): return player.ability == "" and not player.attacking and player.dodge_timer <= 0.0)
	var origin: Vector3 = player.global_position
	# monstros parados: 2 no caminho à frente (bem para o lado, para não travarem o deslize), 1 fora (longe do lado)
	var mobs: Array = []
	for off in [Vector3(1.6, 0, 3.0), Vector3(-1.6, 0, 5.5), Vector3(14.0, 0, 3.0)]:
		var e := Enemy.new()
		e.kind = "slime"
		world.add_child(e)
		e.global_position = origin + off
		e.home = e.global_position
		mobs.append(e)
	await wait(0.15)
	for e in mobs:
		e.set_physics_process(false)
	var inside := mobs.slice(0, 2)
	var outside := mobs.slice(2)
	var hp0 := {}
	for e in mobs:
		hp0[e] = e.hp
	var hp_player: float = Game.hp
	player.cooldowns.sword_dark_combo = 0.0
	player.invuln = 99.0
	player.use_slot(3)
	check(player.ability == "sword_dark_combo" and player.ability_slot == 3, "Dança do Abismo: começa na tecla 3")
	var skill: GreatswordDarkComboFX = player.ability_data.get("skill")
	check(is_instance_valid(skill) and skill.get_parent() == get_tree().current_scene, "Dança do Abismo: o visual na cena do mundo")
	var cd: float = player.cooldowns.sword_dark_combo
	check(cd >= cfg.cooldown * Game.cooldown_mult() - 0.01, "Dança do Abismo: recarga do GreatswordDarkComboConfig (%.1f s)" % cd)
	check(int(player.ability_data.get("seg", -1)) == KnightMovesGreatDark.SLIDE, "Dança do Abismo: começa sempre pelo deslize")
	# o deslize anda para a frente, mesmo com a tecla de andar para o lado
	Input.action_press("move_right")
	await wait(cfg.starts()[1] * 0.8)
	Input.action_release("move_right")
	# na direção do combo (a mira suave pode tê-lo virado para o monstro mais perto à frente)
	var cyaw := float(player.ability_data.get("yaw", 0.0))
	var cf := Vector3(sin(cyaw), 0.0, cos(cyaw))
	var moved_v: Vector3 = player.global_position - origin
	moved_v.y = 0.0
	var ahead: float = moved_v.dot(cf)
	var sideways: float = absf(moved_v.dot(Vector3(cf.z, 0.0, -cf.x)))
	check(ahead > 1.5 and sideways < 0.6 and cf.z > 0.7,
		"Dança do Abismo: o herói anda com o deslize, para a frente (%.2f m à frente, %.2f para o lado)" % [ahead, sideways])
	var lit := 0.0
	var segs := {}
	while player.ability == "sword_dark_combo":
		segs[int(player.ability_data.get("seg", 0))] = true
		if is_instance_valid(skill):
			lit = maxf(lit, skill.trail.strength())
		await get_tree().physics_frame
	check(segs.size() == 4, "Dança do Abismo: os quatro golpes tocam (%s)" % [segs.keys()])
	check(lit > 0.6, "Dança do Abismo: o rastro sombrio acende nos cortes (%.2f)" % lit)
	check(is_instance_valid(skill) and skill.bursts == cfg.hit_count(), "Dança do Abismo: uma explosão sombria por acerto (%d)" % (skill.bursts if is_instance_valid(skill) else -1))
	check(inside.all(func(e): return not is_instance_valid(e) or e.dead or e.hp < float(hp0[e])),
		"Dança do Abismo: fere quem está no caminho do combo")
	check(outside.all(func(e): return is_instance_valid(e) and is_equal_approx(e.hp, float(hp0[e]))), "Dança do Abismo: quem está longe não leva dano")
	check(Game.hp >= hp_player, "Dança do Abismo: o próprio herói não leva dano")
	check(player.cam_back == 0.0, "Dança do Abismo: termina e solta a câmera")
	var skill_ref: WeakRef = weakref(skill)
	await wait_until(func(): return skill_ref.get_ref() == null, 4.0)
	check(skill_ref.get_ref() == null, "Dança do Abismo: rastro, garras e explosões removidos no fim")
	# a esquiva cancela no meio: o visual se apaga e se libera
	await wait_until(func(): return player.dodge_timer <= 0.0)
	player.cooldowns.sword_dark_combo = 0.0
	Game.stamina = Game.max_stamina()
	player.cast("sword_dark_combo")
	var skill2: GreatswordDarkComboFX = player.ability_data.get("skill")
	await wait(0.6)
	check(GreatswordDarkComboAbilities.can_dodge_cancel(player), "Dança do Abismo: a esquiva pode cancelar no meio")
	player._dodge_pressed(Vector3.BACK)
	check(player.ability != "sword_dark_combo" and is_instance_valid(skill2) and skill2.stopped, "Dança do Abismo: cancelada pela esquiva")
	var skill2_ref: WeakRef = weakref(skill2)
	await wait_until(func(): return skill2_ref.get_ref() == null, 4.0)
	check(skill2_ref.get_ref() == null, "Dança do Abismo: cancelada se libera")
	for e in mobs:
		if is_instance_valid(e):
			e.queue_free()
	# a Fúria Picante na tecla 5 da montante dá o mesmo buff
	Game.buffs.erase("sword_fury")
	player.cooldowns.sword_fury_great = 0.0
	await wait_until(func(): return player.ability == "" and player.dodge_timer <= 0.0)
	player.use_slot(5)
	check(Game.buffs.has("sword_fury") and player.cooldowns.sword_fury_great >= Game.buff_duration("sword_fury") + 4.0 - 0.01,
		"Fúria Picante na tecla 5 da montante: o buff da Fúria e a recarga dela")
	await wait_until(func(): return player.ability == "", 2.0)
	Game.buffs.erase("sword_fury")
	Game.add_buff("sword_fury", 0.01)
	# sem a montante: a Fúria volta para a tecla 3 e a tecla 5 some
	if weapon0 != "":
		equip_any(weapon0)
	await wait_until(func(): return Game.offhand_kind() == "")
	check(Game.ability_kit()[2] == "sword_fury" and not ("sword_dark_combo" in Game.ability_kit()) and not ("sword_fury_great" in Game.ability_kit()),
		"Dança do Abismo: sem a montante a habilidade 3 volta a ser a Fúria Picante")
	await wait(0.1)
	check(not hud.slots["slot_5"].visible, "Dança do Abismo: sem a montante a tecla 5 some da barra")
	Econ.test_force_level(lv0)
	player.global_position = back
	player.velocity = Vector3.ZERO
	player.cooldowns.sword_dark_combo = 0.0
	player.cooldowns.sword_fury_great = 0.0
	player.invuln = 0.0
	Game.stamina = Game.max_stamina()
	Game.hp = hp_player


## Terremoto Devastador (espada + escudo, slot 2 / tecla 2, no lugar do Golpe Sísmico): kit, carga antes do impacto
## (rachaduras pequenas, energia, pedrinhas), parado enquanto bate, impacto na hora certa e no ponto à frente do
## herói (explosão e tremor), onda crescendo até o raio, rachaduras e placas acompanhando a onda, pedras lançadas,
## dano sincronizado com a passagem da onda (o perto antes do longe), os de fora sem dano, uma vez só por inimigo,
## o herói sem dano, recarga do EarthquakeConfig, limpeza de todos os nós e o cancelamento pela esquiva.
func _check_earthquake(player: Node, world: Node) -> void:
	var cfg: EarthquakeConfig = EarthquakeAbilities.CONFIG
	var back: Vector3 = player.global_position
	var lv0: int = Game.level
	Econ.test_force_level(maxi(lv0, 3))
	Game.add_item("wooden_shield")
	equip_any("wooden_shield")
	await wait_until(func(): return Game.offhand_kind() == "shield" and Game.level >= 3)
	var kit := Game.ability_kit()
	check(kit.size() == 5 and kit[1] == "sword_earthquake" and not ("sword_quake" in kit),
		"Terremoto: espada + escudo troca a habilidade 2 (%s)" % [kit])
	check(Game.knows_ability("sword_earthquake"), "Terremoto: liberado no nível %d" % ItemDB.ABILITIES.sword_earthquake.level)
	var count_fx := func(cls: String) -> int:
		var n := 0
		for c in get_tree().current_scene.find_children("*", cls, true, false):
			if not c.is_queued_for_deletion():
				n += 1
		return n
	var spot := Vector3(-105, 0.3, 44)   # fora da vila (a guarda abate monstro lá dentro)
	player.global_position = spot
	player.velocity = Vector3.ZERO
	player.model.rotation.y = 0.0     # olhando para +Z: o escudo bate em spot + (0, 0, forward_offset)
	await wait(0.25)
	await wait_until(func(): return player.ability == "" and not player.attacking and player.dodge_timer <= 0.0)
	var center: Vector3 = EarthquakeAbilities.impact_point(player.global_position, 0.0)
	# monstros parados: 3 dentro do raio (perto, no meio, longe) e 2 fora
	var mobs: Array = []
	for off in [Vector3(0.9, 0, 0.4), Vector3(-1.2, 0, 1.0), Vector3(0.2, 0, cfg.radius - 0.2),
			Vector3(cfg.radius + 3.0, 0, 0), Vector3(-cfg.radius - 3.5, 0, 2.0)]:
		var e := Enemy.new()
		e.kind = "slime"
		world.add_child(e)
		e.global_position = center + off
		e.home = e.global_position
		mobs.append(e)
	await wait(0.15)
	for e in mobs:
		e.set_physics_process(false)
	var inside := mobs.slice(0, 3)
	var outside := mobs.slice(3)
	var hp0 := {}
	for e in mobs:
		hp0[e] = e.hp
	var hp_player: float = Game.hp
	player.cooldowns.sword_earthquake = 0.0
	player.invuln = 99.0   # os monstros não interferem (o teste é do golpe)
	player.cast("sword_earthquake")
	check(player.ability == "sword_earthquake", "Terremoto: a habilidade começa na tecla 2")
	var skill: EarthquakeSkill = player.ability_data.get("skill")
	check(is_instance_valid(skill) and skill.get_parent() == get_tree().current_scene, "Terremoto: EarthquakeSkill na cena do mundo")
	var cd: float = player.cooldowns.sword_earthquake
	check(cd >= cfg.cooldown * Game.cooldown_mult() - 0.01, "Terremoto: recarga do EarthquakeConfig (%.1f s)" % cd)
	var flat_c := Vector2(skill.global_position.x - center.x, skill.global_position.z - center.z).length()
	check(flat_c < 0.05, "Terremoto: centro à frente do herói, onde o escudo bate (%.2f m)" % flat_c)
	# carga: rachaduras pequenas sob o ponto, energia e pedrinhas tremendo; o herói fica parado
	await wait(cfg.windup_time * 0.6)
	check(skill.state == EarthquakeSkill.State.CHARGE and skill.impact_at < 0.0 and is_instance_valid(skill.charge_cracks)
		and skill.charge_cracks.wave_r > 0.05 and skill.debris.count() > 0 and skill.vfx.has_node("ChargeSheet"),
		"Terremoto: carga antes do impacto (rachaduras pequenas, energia, pedrinhas tremendo)")
	var pos_w: Vector3 = player.global_position
	Input.action_press("move_forward")
	await wait(0.15)
	Input.action_release("move_forward")
	check(Vector2(player.global_position.x - pos_w.x, player.global_position.z - pos_w.z).length() < 0.05,
		"Terremoto: parado enquanto bate")
	await wait_until(func(): return skill.impact_at >= 0.0, 2.0)
	check(skill.impact_at >= 0.0 and absf(skill.impact_at - cfg.impact_time()) < 0.1,
		"Terremoto: o escudo toca o chão no fim da descida (%.2f s, esperado %.2f)" % [skill.impact_at, cfg.impact_time()])
	check(skill.ground.is_done() and is_instance_valid(skill.ring) and is_instance_valid(skill.cracks),
		"Terremoto: chão medido e a onda montada antes do impacto")
	check(count_fx.call("GroundImpact") == 1 and player.shake > 0.3, "Terremoto: explosão no impacto e a câmera treme (%.2f)" % player.shake)
	check(count_fx.call("EarthquakeDamage") == 1, "Terremoto: o dano começa no impacto (EarthquakeDamage separado do visual)")
	var ic: Vector3 = skill.impact_center
	check(absf(ic.y - spot.y) < 1.5, "Terremoto: impacto no chão (altura %.2f, herói %.2f)" % [ic.y, spot.y])
	# a onda passa pelo de perto antes do de longe
	await wait_until(func(): return skill.wave_r >= 1.3, 1.0)
	await wait(0.05)   # um passo de física para o dano alcançar o relógio da onda
	var near_hit: bool = not is_instance_valid(inside[0]) or inside[0].dead or inside[0].hp < float(hp0[inside[0]])
	var far_hit: bool = not is_instance_valid(inside[2]) or inside[2].dead or inside[2].hp < float(hp0[inside[2]])
	check(near_hit and not far_hit, "Terremoto: o dano acompanha a onda (o perto já levou, o longe ainda não; onda %.1f m)" % skill.wave_r)
	check(skill.wave_r > 0.5 and skill.wave_r < cfg.radius and skill.cracks.wave_r == skill.wave_r
		and skill.cracks.plates_up < skill.plate_spots.size(), "Terremoto: rachaduras e placas acompanham a onda (não aparecem de uma vez)")
	await wait_until(func(): return skill.state == EarthquakeSkill.State.DISSIPATE, 3.0)
	check(is_equal_approx(skill.wave_r, cfg.radius), "Terremoto: a onda para no raio máximo (%.1f m)" % skill.wave_r)
	check(skill.cracks.plates_up > 0 and skill.debris.count() > 20 and skill.secondary_done == skill.secondary_spots.size(),
		"Terremoto: placas levantadas (%d), pedras lançadas (%d) e explosões secundárias (%d)" % [skill.cracks.plates_up, skill.debris.count(), skill.secondary_done])
	await wait(0.2)
	var hp1 := {}
	for e in mobs:
		hp1[e] = e.hp if is_instance_valid(e) else -1.0
	var hit_in := inside.filter(func(e): return not is_instance_valid(e) or e.dead or float(hp1[e]) < float(hp0[e]))
	check(hit_in.size() == inside.size(), "Terremoto: todos os %d monstros dentro do raio levam dano (%d)" % [inside.size(), hit_in.size()])
	check(outside.all(func(e): return is_instance_valid(e) and is_equal_approx(e.hp, float(hp0[e]))),
		"Terremoto: monstros fora do raio não levam dano")
	check(Game.hp >= hp_player, "Terremoto: o próprio herói não leva dano")
	check(count_fx.call("EarthquakeDamage") == 0, "Terremoto: o dano termina com a onda")
	await wait(0.5)
	check(inside.all(func(e): return not is_instance_valid(e) or e.dead or is_equal_approx(e.hp, float(hp1[e]))),
		"Terremoto: cada monstro leva dano uma vez por ativação")
	await wait_until(func(): return player.ability == "", 2.0)
	check(player.ability == "" and player.cam_back == 0.0, "Terremoto: o herói fica livre e a câmera volta ao normal")
	await wait_until(func(): return skill.debris == null or not is_instance_valid(skill.debris) or skill.debris.landed > 0, 1.0)
	check(not is_instance_valid(skill) or not is_instance_valid(skill.debris) or skill.debris.landed > 0, "Terremoto: as pedras caem de volta no chão")
	# tudo se dissipa e é liberado
	await wait_until(func(): return not is_instance_valid(skill), cfg.dissipation_time + 4.0)
	var left := 0
	for cls in ["EarthquakeSkill", "GroundImpact", "ShockwaveRing", "GroundCrack", "RockDebris", "EarthquakeDust", "EarthquakeVFX", "EarthquakeDamage", "EarthquakeSheet"]:
		left += count_fx.call(cls)
	check(not is_instance_valid(skill) and left == 0, "Terremoto: onda, rachaduras, placas, pedras, poeira e energia removidas no fim (%d sobrando)" % left)
	# esquiva antes do impacto cancela: sem onda nem dano
	for e in mobs:
		if is_instance_valid(e) and not e.dead:
			hp0[e] = e.hp
	player.cooldowns.sword_earthquake = 0.0
	player.cast("sword_earthquake")
	var skill2: EarthquakeSkill = player.ability_data.get("skill")
	await wait(cfg.windup_time * 0.4)
	check(EarthquakeAbilities.can_dodge_cancel(player), "Terremoto: esquiva pode cancelar antes do escudo tocar o chão")
	EarthquakeAbilities.dodge_cancel(player)
	check(player.ability == "" and skill2.state == EarthquakeSkill.State.CANCELED, "Terremoto: cancelado pela esquiva")
	await wait_until(func(): return not is_instance_valid(skill2), 3.0)
	check(not is_instance_valid(skill2) and count_fx.call("EarthquakeDamage") == 0
		and mobs.all(func(e): return not is_instance_valid(e) or e.dead or is_equal_approx(e.hp, float(hp0[e]))),
		"Terremoto: cancelado não fere ninguém e se libera")
	for e in mobs:
		if is_instance_valid(e):
			e.queue_free()
	# tira o escudo: o Golpe Sísmico volta
	Game.unequip("offhand")
	await wait_until(func(): return Game.offhand_kind() == "")
	check(Game.ability_kit()[1] == "sword_quake", "Terremoto: sem escudo a habilidade 2 volta a ser o Golpe Sísmico")
	Econ.test_force_level(lv0)
	player.global_position = back
	player.velocity = Vector3.ZERO
	player.cooldowns.sword_earthquake = 0.0
	player.invuln = 0.0
	Game.hp = hp_player


## Círculo da Provocação Sombria (espada + escudo, slot 3 / tecla 3): kit, círculo no chão sob o herói girando, mãos
## em pontos diferentes, captura só de quem está dentro (uma vez), imobilização, a IA trocando o alvo (um aliado
## mais perto) pelo herói e indo atacá-lo, olhos vermelhos por inimigo seguindo a cabeça, morte no meio, fim da
## provocação (olhos somem e a IA volta), herói que provocou morrendo, limpeza e o cancelamento pela esquiva.
func _check_dark_taunt(player: Node, world: Node) -> void:
	var cfg: DarkTauntConfig = DarkTauntAbilities.CONFIG
	var back: Vector3 = player.global_position
	var lv0: int = Game.level
	Econ.test_force_level(maxi(lv0, 5))
	Game.add_item("wooden_shield")
	equip_any("wooden_shield")
	await wait_until(func(): return Game.offhand_kind() == "shield" and Game.level >= 5)
	var kit := Game.ability_kit()
	check(kit.size() == 5 and kit[2] == "sword_taunt" and not ("sword_fury" in kit),
		"Provocação: espada + escudo troca a habilidade 3 (%s)" % [kit])
	check(Game.knows_ability("sword_taunt"), "Provocação: liberada no nível %d" % ItemDB.ABILITIES.sword_taunt.level)
	var count_fx := func(cls: String) -> int:
		var n := 0
		for c in get_tree().current_scene.find_children("*", cls, true, false):
			if not c.is_queued_for_deletion():
				n += 1
		return n
	var spot := Vector3(-105, 0.3, 40)   # fora da vila (a guarda abate monstro lá dentro)
	player.global_position = spot
	player.velocity = Vector3.ZERO
	player.model.rotation.y = 0.0
	await wait(0.25)
	await wait_until(func(): return player.ability == "" and not player.attacking and player.dodge_timer <= 0.0)
	var hero_pos: Vector3 = player.global_position
	# um aliado (réplica de outro jogador) mais perto dos monstros: sem a provocação, é ele o alvo
	var ally := Player.new()
	ally.remote = true
	world.add_child(ally)
	ally.global_position = hero_pos + Vector3(4.6, 0, 0)
	ally._net_pos = ally.global_position
	# 4 monstros dentro do raio (mais perto do aliado que do herói), 2 fora
	var mobs: Array = []
	for off in [Vector3(3.6, 0, 1.2), Vector3(4.2, 0, -1.4), Vector3(2.9, 0, 2.6), Vector3(-1.5, 0, 4.4),
			Vector3(cfg.radius + 4.0, 0, 0.5), Vector3(-cfg.radius - 4.0, 0, -2.0)]:
		var e := Enemy.new()
		e.kind = "goblin"
		world.add_child(e)
		e.global_position = hero_pos + off
		e.home = e.global_position
		mobs.append(e)
	var inside := mobs.slice(0, 4)
	var outside := mobs.slice(4)
	await wait(0.2)
	# os de fora ficam parados: andando, eles entram no círculo antes de ele terminar (e aí são agarrados, certo)
	for e in outside:
		e.set_physics_process(false)
	check(inside[0]._nearest_player() == ally, "Provocação: antes, o alvo do monstro é o aliado mais perto")
	player.cooldowns.sword_taunt = 0.0
	player.invuln = 99.0
	player.cast("sword_taunt")
	check(player.ability == "sword_taunt", "Provocação: a habilidade começa na tecla 3")
	var skill: DarkTauntSkill = player.ability_data.get("skill")
	check(is_instance_valid(skill) and skill.get_parent() == get_tree().current_scene, "Provocação: DarkTauntSkill na cena do mundo")
	var cd: float = player.cooldowns.sword_taunt
	check(cd >= cfg.cooldown * Game.cooldown_mult() - 0.01, "Provocação: recarga do DarkTauntConfig (%.1f s)" % cd)
	# o círculo se desenha no chão, sob o herói, girando
	await wait(DarkTauntConfig.CAST_LEAD + cfg.circle_form_time * 0.5)
	var cp: Vector3 = skill.circle.global_position
	check(skill.circle.visible and Vector2(cp.x - hero_pos.x, cp.z - hero_pos.z).length() < 0.05 and absf(cp.y - hero_pos.y) < 0.6,
		"Provocação: círculo no chão, centrado sob o herói (%.2f m de altura relativa)" % (cp.y - hero_pos.y))
	var f0 := skill.circle.formed()
	var a0: float = skill.circle.spin_angle
	await wait(0.15)
	check(f0 > 0.0 and f0 < 1.0 and skill.circle.formed() > f0, "Provocação: círculo aparece aos poucos (%.2f -> %.2f)" % [f0, skill.circle.formed()])
	check(skill.circle.spin_angle > a0, "Provocação: os anéis giram")
	# parado enquanto invoca
	var pos_w: Vector3 = player.global_position
	Input.action_press("move_forward")
	await wait(0.25)
	Input.action_release("move_forward")
	check(Vector2(player.global_position.x - pos_w.x, player.global_position.z - pos_w.z).length() < 0.05, "Provocação: parado enquanto invoca")
	check(player.cam_back > 0.5, "Provocação: a câmera recua para o círculo caber")
	# as mãos sobem: uma por alvo dentro do raio, em pontos diferentes
	await wait_until(func(): return skill.state >= DarkTauntSkill.State.RISE, 3.0)
	check(skill.targets.size() == inside.size() and inside.all(func(e): return e in skill.targets)
		and outside.all(func(e): return not (e in skill.targets)), "Provocação: só os %d de dentro são alvos (%d)" % [inside.size(), skill.targets.size()])
	check(skill.hands.size() == maxi(cfg.hand_count, inside.size()), "Provocação: %d mãos sombrias" % skill.hands.size())
	var min_gap := INF
	for i in skill.hands.size():
		for j in range(i + 1, skill.hands.size()):
			var pa: Vector3 = skill.hands[i].global_position
			var pb: Vector3 = skill.hands[j].global_position
			min_gap = minf(min_gap, Vector2(pa.x - pb.x, pa.z - pb.z).length())
	check(min_gap > 0.4 and inside.all(func(e): return skill.hands.any(func(h): return h.target == e)),
		"Provocação: cada alvo tem a sua mão, saindo de pontos diferentes (menor distância %.2f m)" % min_gap)
	# fecham: cada um capturado uma vez, preso e provocado; os de fora nada
	await wait_until(func(): return skill.captured_count >= inside.size(), 3.0)
	check(skill.captured_count == inside.size(), "Provocação: os %d monstros de dentro são agarrados (%d)" % [inside.size(), skill.captured_count])
	var grabbing := skill.hands.filter(func(h): return h.held)
	check(grabbing.size() == inside.size() and grabbing.all(func(h): return h.grip >= 0.99), "Provocação: as mãos fecham os dedos nos alvos")
	await wait(0.05)
	check(inside.all(func(e): return e.held_t > 0.0 and e.taunt_t > 0.0 and e.taunt_by == player),
		"Provocação: os agarrados ficam presos e provocados pelo herói")
	check(outside.all(func(e): return e.taunt_t <= 0.0 and e.held_t <= 0.0), "Provocação: os de fora não são afetados")
	check(not (player in skill.targets) and not (ally in skill.targets), "Provocação: o herói e o aliado nunca são agarrados")
	check(inside.all(func(e): return e.taunt_eyes != null and e.taunt_eyes.active and e.taunt_eyes.visible)
		and outside.all(func(e): return e.taunt_eyes == null), "Provocação: cada provocado tem o seu par de olhos vermelhos")
	var flat := func(a: Vector3, b: Vector3) -> float: return Vector2(a.x - b.x, a.z - b.z).length()
	var eyes_ok := true
	for e in inside:
		if e.taunt_eyes == null:
			eyes_ok = false
			continue
		var ep: Vector3 = e.taunt_eyes.global_position
		eyes_ok = eyes_ok and ep.y > e.global_position.y + e.head_top() and flat.call(ep, e.global_position) < 0.6
	check(eyes_ok, "Provocação: os olhos ficam acima da cabeça de cada um")
	var held_pos := {}
	for e in inside:
		held_pos[e] = e.global_position
	await wait(0.5)
	var still_ok := true
	for e in inside:
		still_ok = still_ok and flat.call(e.global_position, held_pos[e]) < 0.15 and e.state != "attack"
	check(still_ok, "Provocação: presos pelas mãos não andam nem atacam")
	check(inside.all(func(e): return e._nearest_player() == player) and outside[0]._nearest_player() == ally,
		"Provocação: o alvo dos provocados passa a ser o herói (o de fora segue no aliado)")
	await wait_until(func(): return player.ability == "", 3.0)
	check(player.ability == "", "Provocação: o herói fica livre depois que as mãos agarram")
	# as mãos soltam: os provocados vêm atrás do herói (e não do aliado, que está mais perto)
	await wait_until(func(): return inside.all(func(e): return e.held_t <= 0.0), cfg.hold_time + 1.0)
	var d0 := {}
	for e in inside:
		d0[e] = Vector2(e.global_position.x - hero_pos.x, e.global_position.z - hero_pos.z).length()
	await wait(1.0)
	var closer := []
	for e in inside:
		if flat.call(e.global_position, hero_pos) < float(d0[e]) - 0.3 or e.state == "attack":
			closer.append(e)
	check(closer.size() >= inside.size() - 1 and inside.all(func(e): return e._tgt == player),
		"Provocação: soltos, perseguem o herói (%d de %d se aproximaram)" % [closer.size(), inside.size()])
	check(inside.all(func(e): return e.taunt_eyes != null and Vector2(e.taunt_eyes.global_position.x - e.global_position.x, e.taunt_eyes.global_position.z - e.global_position.z).length() < 0.6),
		"Provocação: os olhos acompanham o monstro andando")
	# um provocado morre no meio: o indicador sai junto
	var victim: Enemy = inside[3]
	victim.take_damage(99999.0, hero_pos, false)
	await wait(0.05)
	check(victim.dead and victim.taunt_t <= 0.0 and (victim.taunt_eyes == null or not is_instance_valid(victim.taunt_eyes)),
		"Provocação: monstro morto perde a provocação e os olhos")
	# fim da provocação: os olhos se apagam aos poucos e a IA volta a escolher o mais perto
	var rest := inside.slice(0, 3)
	for e in rest:
		e.taunt_t = 0.05
	await wait(0.15)
	check(rest.all(func(e): return e.taunt_t <= 0.0 and e.taunt_by == null and e.taunt_eyes != null and not e.taunt_eyes.active),
		"Provocação: acabou o tempo, a provocação termina")
	check(rest.all(func(e): return e.taunt_eyes != null and e.taunt_eyes.visible), "Provocação: os olhos não somem de uma vez (apagando)")
	await wait(cfg.eye_fade_time + 0.2)
	check(rest.all(func(e): return e.taunt_eyes != null and not e.taunt_eyes.visible), "Provocação: os olhos somem no fim")
	var near_ally: Enemy = rest[0]
	near_ally.global_position = ally.global_position + Vector3(1.2, 0, 0)
	await wait(0.1)
	check(near_ally._nearest_player() == ally, "Provocação: depois do fim, a IA volta a escolher o alvo mais perto")
	# o herói que provocou morre (aqui: o aliado como provocador): a provocação acaba na hora
	var e2: Enemy = rest[1]
	e2.apply_taunt(ally, 0.0, 5.0)
	await wait(0.05)
	check(e2.taunt_t > 0.0 and e2._nearest_player() == ally, "Provocação: apply_taunt direto vale")
	ally.dead = true
	await wait(0.1)
	check(e2.taunt_t <= 0.0 and e2.taunt_by == null, "Provocação: quem provocou morreu, a provocação acaba")
	ally.dead = false
	# tudo sai da cena no fim (mãos, círculo, efeitos)
	await wait_until(func(): return not is_instance_valid(skill), cfg.dissipate_time + cfg.circle_linger + 4.0)
	check(not is_instance_valid(skill) and count_fx.call("ShadowHand") == 0 and count_fx.call("DarkMagicCircle") == 0
		and count_fx.call("DarkTauntVFX") == 0, "Provocação: mãos, círculo e efeitos removidos no fim")
	# esquiva antes das mãos fecharem: cancela sem provocar ninguém
	var fresh := Enemy.new()
	fresh.kind = "goblin"
	world.add_child(fresh)
	fresh.global_position = hero_pos + Vector3(2.0, 0, -2.0)
	fresh.home = fresh.global_position
	mobs.append(fresh)
	await wait(0.1)
	player.global_position = hero_pos
	player.cooldowns.sword_taunt = 0.0
	player.cast("sword_taunt")
	var skill2: DarkTauntSkill = player.ability_data.get("skill")
	await wait(DarkTauntConfig.CAST_LEAD + 0.2)
	check(DarkTauntAbilities.can_dodge_cancel(player), "Provocação: esquiva pode cancelar antes das mãos fecharem")
	DarkTauntAbilities.dodge_cancel(player)
	check(player.ability == "" and skill2.state == DarkTauntSkill.State.CANCELED, "Provocação: cancelada pela esquiva")
	await wait_until(func(): return not is_instance_valid(skill2), 4.0)
	check(not is_instance_valid(skill2) and fresh.taunt_t <= 0.0 and fresh.taunt_eyes == null,
		"Provocação: cancelada não provoca ninguém e se libera")
	for e in mobs:
		if is_instance_valid(e):
			e.queue_free()
	ally.queue_free()
	# tira o escudo: a Fúria Picante volta
	Game.unequip("offhand")
	await wait_until(func(): return Game.offhand_kind() == "")
	check(Game.ability_kit()[2] == "sword_fury", "Provocação: sem escudo a habilidade 3 volta a ser a Fúria Picante")
	Econ.test_force_level(lv0)
	player.global_position = back
	player.velocity = Vector3.ZERO
	player.cooldowns.sword_taunt = 0.0
	player.invuln = 0.0


## Grito do Bastião (espada + escudo, tecla 5): HUD sem o M1 e com o 5 ao lado do 4, a animação com a aura azul
## suave, o buff só no fim da animação, a defesa (fixa e percentual) entrando e saindo limpa, os escudos girando no
## personagem e se desfazendo em partículas, reaplicar renova sem empilhar, esquiva cancela sem buff, réplica só
## visual, e sem escudo a tecla 5 some.
func _check_party_shield(player: Node, world: Node) -> void:
	var cfg: PartyShieldConfig = PartyShieldAbilities.CONFIG
	var id := PartyShieldRules.ID
	var buff := PartyShieldRules.BUFF
	var back: Vector3 = player.global_position
	var lv0: int = Game.level
	Econ.test_force_level(maxi(lv0, int(ItemDB.ABILITIES[id].level)))
	Game.add_item("wooden_shield")
	equip_any("wooden_shield")
	await wait_until(func(): return Game.offhand_kind() == "shield" and Game.level >= int(ItemDB.ABILITIES[id].level))
	Game.clear_buffs(true)
	var kit := Game.ability_kit()
	check(kit == ["sword_aegis", "sword_earthquake", "sword_taunt", "sword_hammer", id],
		"Bastião: espada + escudo ganha a habilidade 5 (%s)" % [kit])
	check(Game.knows_ability(id), "Bastião: liberado no nível %d" % ItemDB.ABILITIES[id].level)
	var count_fx := func(cls: String) -> int:
		var n := 0
		for c in get_tree().current_scene.find_children("*", cls, true, false):
			if not c.is_queued_for_deletion():
				n += 1
		return n
	# --- HUD: o M1 não aparece (o clique continua atacando), o 5 fica logo depois do 4 e a doca fica centrada
	var hud = world.hud
	await wait(0.1)
	var s4: Control = hud.slots["slot_4"]
	var s5: Control = hud.slots["slot_5"]
	check(not hud.slots["attack"].visible, "HUD: o M1 não aparece mais na barra")
	check(s5.visible and s5.get_index() == s4.get_index() + 1 and s5.icon_tex == ItemSlot.skill_art(id) and s5.icon_tex != null,
		"HUD: a habilidade 5 aparece ao lado da 4, com o ícone do Grito do Bastião")
	check(s5.key_text == "5" and s4.key_text == "4", "HUD: selos de tecla 4 e 5")
	check(hud_slot_ids() == kit, "HUD: a barra mostra o kit com escudo (%s)" % [hud_slot_ids()])
	var dock: Control = hud.dock
	check(absf(dock.offset_left + dock.offset_right) < 1.5, "HUD: a doca continua centrada com o 5 (%.1f, %.1f)" % [dock.offset_left, dock.offset_right])
	# --- o herói longe da vila, parado; o ataque do clique esquerdo continua funcionando sem o M1 na barra
	var spot := Vector3(-105, 0.3, 36)
	player.global_position = spot
	player.velocity = Vector3.ZERO
	player.invuln = 99.0
	await wait(0.25)
	await wait_until(func(): return player.ability == "" and not player.attacking and player.dodge_timer <= 0.0)
	Input.action_press("attack")
	await wait(0.1)
	Input.action_release("attack")
	check(player.attacking or player.combo > 0, "HUD: sem o M1 na barra, o clique esquerdo ainda ataca")
	await wait_until(func(): return not player.attacking, 2.0)
	await wait(0.3)
	var def0: float = Game.defense()
	# --- tecla 5: a habilidade começa, com a recarga da config (nunca abaixo do buff + 4 s)
	player.cooldowns[id] = 0.0
	player.use_slot(5)
	check(player.ability == id and player.ability_slot == 5, "Bastião: a tecla 5 começa o Grito do Bastião")
	var cd: float = player.cooldowns[id]
	var want_cd := maxf(cfg.cooldown * Game.cooldown_mult(), Game.buff_duration(buff) + 4.0)
	check(absf(cd - want_cd) < 0.05, "Bastião: recarga %.1f s (config %.0f s, piso do buff)" % [cd, cfg.cooldown])
	var fx: PartyShieldCast = player.ability_data.get("fx")
	check(is_instance_valid(fx) and fx.get_parent() == player, "Bastião: a aura azul nasce no herói (segue ele)")
	# a aura acende devagar (sem tranco) e respira
	await wait(cfg.aura_fade_in * 0.35)
	var w1: float = fx.weight() if is_instance_valid(fx) else -1.0
	check(w1 > 0.05 and w1 < 0.95, "Bastião: a aura acende aos poucos (%.2f)" % w1)
	await wait(cfg.aura_fade_in)
	check(is_instance_valid(fx) and fx.weight() > 0.98, "Bastião: aura acesa durante a animação")
	check(is_instance_valid(fx) and fx.light.visible and fx.light.light_color.b > fx.light.light_color.r, "Bastião: luz azul junto da aura")
	# parado enquanto grita, a câmera recua um pouco
	var pos_w: Vector3 = player.global_position
	Input.action_press("move_forward")
	await wait(0.25)
	Input.action_release("move_forward")
	check(Vector2(player.global_position.x - pos_w.x, player.global_position.z - pos_w.z).length() < 0.05, "Bastião: parado enquanto grita")
	check(player.cam_back > 0.5, "Bastião: a câmera recua")
	check(player.ability_data.get("shout", false), "Bastião: o grito sai na explosão do clipe")
	# antes do fim da animação: nada de buff
	await wait_until(func(): return player.ability_t >= PartyShieldAbilities.total_time() - 0.15, 4.0)
	check(player.ability == id and not Game.has_buff(buff) and absf(Game.defense() - def0) < 0.01,
		"Bastião: o buff ainda não entrou durante a animação")
	# fim da animação: o buff entra (solo: direto no herói), com o tempo da tabela
	await wait_until(func(): return player.ability == "", 2.0)
	check(Game.has_buff(buff), "Bastião: a animação termina e o buff entra")
	check(absf(float(Game.buffs.get(buff, 0.0)) - Game.buff_duration(buff)) < 0.3, "Bastião: dura %.0f s" % Game.buff_duration(buff))
	var add: Dictionary = ItemDB.BUFFS[buff].add
	var def_want := PartyShieldRules.defense_with(def0 + float(add.defense), float(add.defense_pct))
	check(absf(Game.defense() - def_want) < 0.01 and Game.defense() > def0,
		"Bastião: defesa %.1f -> %.1f (+%d e +%d%%)" % [def0, Game.defense(), int(add.defense), int(float(add.defense_pct) * 100.0)])
	# a aura do grito apaga devagar e se libera
	check(is_instance_valid(fx) and fx.finished, "Bastião: a aura começa a apagar no fim")
	await wait_until(func(): return not is_instance_valid(fx), cfg.aura_fade_out + 1.5)
	check(not is_instance_valid(fx) and count_fx.call("PartyShieldCast") == 0, "Bastião: a aura do grito se libera")
	# os escudos azuis no herói (BuffAura, estilo "bastiao"), girando
	await wait_until(func(): return player.find_children("*", "PartyShieldBuff", true, false).size() > 0, 1.0)
	var vis: Array = player.find_children("*", "PartyShieldBuff", true, false)
	check(vis.size() == 1, "Bastião: um PartyShieldBuff no herói (%d)" % vis.size())
	if vis.size() == 1:
		var pb: PartyShieldBuff = vis[0]
		check(pb.shield_nodes().size() == cfg.shield_count, "Bastião: %d escudos pequenos" % cfg.shield_count)
		check(pb.get_child_count() == 2 and pb.get_node_or_null("Orbit") != null and pb.find_children("*", "GPUParticles3D", true, false).size() == 1,
			"Bastião: no corpo só os escudos girando (sem anel da sheet nem faíscas)")
		var aura: BuffAura = player.vfx_aura
		check(aura != null and aura._ground_root != null and aura._ground_root.get_child_count() == 0 and aura._rim == null,
			"Bastião: sem marca no chão nem contorno no corpo")
		await wait(cfg.intro_time + 0.1)
		var sh: MeshInstance3D = pb.shield_nodes()[0]
		var p0: Vector3 = sh.global_position - player.global_position
		await wait(0.3)
		var p1: Vector3 = sh.global_position - player.global_position
		var ang := absf(Vector2(p0.x, p0.z).angle_to(Vector2(p1.x, p1.z)))
		check(ang > 0.2 and absf(Vector2(p1.x, p1.z).length() - cfg.orbit_radius) < 0.1,
			"Bastião: os escudos giram em volta (%.2f rad em 0,3 s, raio %.2f m)" % [ang, Vector2(p1.x, p1.z).length()])
		check(sh.global_position.y - player.global_position.y > 0.5, "Bastião: na altura do corpo")
	# --- reaplicar renova o tempo, sem empilhar a defesa nem duplicar o visual
	var def_on: float = Game.defense()
	Game.buffs[buff] = 3.0
	player.cooldowns[id] = 0.0
	player.use_slot(5)
	await wait_until(func(): return player.ability == "", PartyShieldAbilities.total_time() + 1.0)
	check(float(Game.buffs.get(buff, 0.0)) > Game.buff_duration(buff) - 0.5, "Bastião: reaplicar renova o tempo (%.1f s)" % float(Game.buffs.get(buff, 0.0)))
	check(absf(Game.defense() - def_on) < 0.01, "Bastião: reaplicar não empilha a defesa")
	await wait(0.2)
	var live := player.find_children("*", "PartyShieldBuff", true, false).filter(func(n): return not n.dissipating)
	check(live.size() == 1, "Bastião: reaplicar não duplica os escudos (%d)" % live.size())
	# --- o buff acaba: a defesa volta exatamente e os escudos se desfazem em partículas, depois somem
	Game.buffs[buff] = 0.05
	await wait(0.25)
	check(not Game.has_buff(buff) and absf(Game.defense() - def0) < 0.01, "Bastião: acabou, a defesa volta a %.1f" % Game.defense())
	var dis: Array = player.find_children("*", "PartyShieldBuff", true, false)
	check(dis.size() == 1 and dis[0].dissipating and dis[0].dissipate_fx.emitting,
		"Bastião: os escudos se desfazem em partículas (não somem de uma vez)")
	await wait(cfg.dissipate_time + PartyShieldBuff.PARTICLE_LIFE + 0.5)
	check(player.find_children("*", "PartyShieldBuff", true, false).is_empty(), "Bastião: depois da dissipação nada fica no herói")
	# limpar os buffs (morte, troca de mapa) também tira a defesa
	Game.add_buff(buff, 10.0)
	check(Game.defense() > def0, "Bastião: add_buff direto vale")
	Game.clear_buffs(true)
	check(absf(Game.defense() - def0) < 0.01, "Bastião: buffs limpos, a defesa não fica presa")
	await wait(cfg.dissipate_time + PartyShieldBuff.PARTICLE_LIFE + 0.5)
	check(player.find_children("*", "PartyShieldBuff", true, false).is_empty(), "Bastião: buffs limpos, os escudos somem")
	# --- esquiva antes do fim cancela: sem buff, aura apaga e se libera
	player.cooldowns[id] = 0.0
	player.use_slot(5)
	var fx2: PartyShieldCast = player.ability_data.get("fx")
	await wait(PartyShieldAbilities.total_time() * 0.5)
	check(PartyShieldAbilities.can_dodge_cancel(player), "Bastião: a esquiva pode cancelar antes do fim")
	PartyShieldAbilities.dodge_cancel(player)
	check(player.ability == "" and is_instance_valid(fx2) and fx2.finished, "Bastião: cancelado pela esquiva, a aura apaga")
	await wait(PartyShieldAbilities.total_time())
	check(not Game.has_buff(buff), "Bastião: cancelado não dá o buff")
	check(not is_instance_valid(fx2), "Bastião: aura cancelada se libera")
	# --- réplica de outro jogador: só o visual (animação e aura), sem dar buff a ninguém aqui
	var ally := Player.new()
	ally.remote = true
	world.add_child(ally)
	ally.global_position = spot + Vector3(3, 0, 0)
	ally._net_pos = ally.global_position
	await wait(0.2)
	ally.play_remote_event(id, ally.global_position, Vector3.ZERO)
	check(ally.ability == id and ally.find_children("*", "PartyShieldCast", true, false).size() == 1,
		"Bastião: a réplica grita com a mesma aura")
	await wait_until(func(): return ally.ability == "", PartyShieldAbilities.total_time() + 1.0)
	check(ally.ability == "" and not Game.has_buff(buff), "Bastião: a réplica termina sem dar buff por conta própria")
	ally.play_remote_event(id, ally.global_position, Vector3.ZERO)
	await wait(0.3)
	ally.play_remote_event(PartyShieldAbilities.CANCEL_EVENT, ally.global_position, Vector3.ZERO)
	check(ally.ability == "", "Bastião: o cancelamento chega na réplica")
	# o buff de um colega aparece na réplica dele (estilo de aura pela rede) e se desfaz quando ele perde o buff
	ally._vfx_apply({"auras": ["bastiao"], "en": "", "lv": 0}, false)
	await wait(0.1)
	check(ally.find_children("*", "PartyShieldBuff", true, false).size() == 1, "Bastião: os escudos aparecem no colega com o buff")
	ally._vfx_apply({"auras": [], "en": "", "lv": 0}, false)
	await wait(0.1)
	var ad: Array = ally.find_children("*", "PartyShieldBuff", true, false)
	check(ad.size() == 1 and ad[0].dissipating, "Bastião: no colega também se desfazem em partículas")
	await wait(cfg.dissipate_time + PartyShieldBuff.PARTICLE_LIFE + 0.5)
	check(ally.find_children("*", "PartyShieldBuff", true, false).is_empty(), "Bastião: e somem do colega")
	ally.queue_free()
	await wait(0.5)
	check(count_fx.call("PartyShieldCast") == 0 and count_fx.call("PartyShieldBuff") == 0, "Bastião: nada sobra na cena")
	# --- sem escudo: a tecla 5 some do HUD e não faz nada
	Game.unequip("offhand")
	await wait_until(func(): return Game.offhand_kind() == "")
	await wait(0.1)
	check(Game.ability_kit().size() == 4 and not (id in Game.ability_kit()), "Bastião: sem escudo o kit volta a 4 habilidades")
	check(not hud.slots["slot_5"].visible, "HUD: sem escudo a tecla 5 some da barra")
	check(absf(dock.offset_left + dock.offset_right) < 1.5, "HUD: a doca recentraliza sem o 5")
	player.use_slot(5)
	check(player.ability == "", "Bastião: sem escudo a tecla 5 não faz nada")
	Game.clear_buffs(true)
	Econ.test_force_level(lv0)
	player.global_position = back
	player.velocity = Vector3.ZERO
	player.cooldowns[id] = 0.0
	player.invuln = 0.0


func EnemyArrow_script() -> GDScript:
	return load("res://scripts/enemies/enemy_arrow.gd")


func wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, true).timeout


## Espera até `cond` ficar verdadeira ou estourar `timeout` (evita folgas fixas frágeis).
func wait_until(cond: Callable, timeout := 3.0) -> void:
	var t := 0.0
	while t < timeout and not cond.call():
		await wait(0.05)
		t += 0.05


## Alvos do teste: os monstros do mundo que alguma checagem escolheu (_nearest, _today, _targets). Só eles
## podem andar e bater perto do jogador; os outros monstros dos pontos do mapa ficam atordoados (ver
## _physics_process). Os que o teste cria (Enemy.new, Horda, invocados do chefe) não são dos pontos: ficam livres.
var _target_ids := {}
var _calm_t := 0.0
const CALM_RADIUS := 30.0   ## maior que o alcance de perseguição e de tiro dos monstros do mapa
const CALM_EVERY := 0.25
const CALM_STUN := 0.6      ## cobre com folga o intervalo entre duas passadas


func _target(e: Enemy) -> Enemy:
	if e != null:
		_target_ids[e.get_instance_id()] = true
	return e


func _targets(list: Array) -> void:
	for e in list:
		_target(e)


## Posição em que o teste segura o jogador (encosta íngreme demais para ficar de pé); null = solto.
var _pin: Variant = null


## Monstros de fora: o vale nasce cheio, em bandos de 3 a 5 com nível (slimes de gelo nv 9 e esqueletos nv 11
## ao lado dos slimes do teste). Quem não é alvo vinha atrás do jogador, empurrava no meio de uma habilidade,
## enchia a fúria e às vezes matava (a tela de morte pausa o jogo e derruba tudo o que vem depois). A cada
## CALM_EVERY s, os monstros dos pontos do mapa que não são alvo e estão a até CALM_RADIUS do jogador levam um
## atordoamento curto: nem andam nem golpeiam.
func _physics_process(delta: float) -> void:
	if _pin != null and player != null:
		player.global_position = _pin
		player.velocity = Vector3.ZERO
	_calm_t -= delta
	if _calm_t > 0.0 or player == null or world == null:
		return
	_calm_t = CALM_EVERY
	var at := player.global_position
	for s in world.spawns:
		var e = s.get("node")
		if e == null or not is_instance_valid(e) or e.dead or _target_ids.has(e.get_instance_id()):
			continue
		if e.global_position.distance_to(at) < CALM_RADIUS:
			e.apply_stun(CALM_STUN)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await wait(0.5)
	world = get_tree().current_scene
	player = get_tree().get_first_node_in_group("player")
	check(world != null and player != null, "mundo e jogador carregados")
	# confere o kit antes de qualquer combate: slimes podem soltar cajado/arco e o saque é aleatório
	check(Game.char_class == "warrior" and Game.equipment.weapon == "azure_edge", "o teste escolheu guerreiro e começou com a espada")
	check(Game.count_item("apprentice_staff") == 0 and Game.count_item("short_bow") == 0, "personagem novo não traz cajado nem arco")
	check(Game.equipment.head == "" and Game.count_item("leather_cap") == 0, "personagem novo sem nenhum equipamento além da arma da classe")
	# o kit das três armas, dado como concessão, para os testes de combate de cada classe de arma
	Econ.grant(0, 0, {"apprentice_staff": 1, "short_bow": 1, "leather_cap": 1}, "test", true)
	check(Game.count_item("apprentice_staff") == 1 and Game.count_item("short_bow") == 1, "kit de teste tem cajado e arco")
	if _part() == "horda" and not Game.HORDE_ENABLED:
		print("[smoke] Horda desligada (Game.HORDE_ENABLED): parte horda pulada")
		_finish()
		return
	if _part() == "horda":
		# o chili do dragão comido na rodada vem do teste da horta, que esta parte não roda
		Econ.grant(0, 0, {"dragon_chili": 1}, "test", true)
		await _test_survival()
		_finish()
		return
	if _part() == "sistemas":
		await _test_sistemas()
		_finish()
		return

	# --- som posicional: combate longe do jogador não deve ser ouvido
	check(Sfx.distance_gain(0.0) == 1.0 and Sfx.distance_gain(15.0) < 0.5 and Sfx.distance_gain(Sfx.FAR_DIST + 1.0) == 0.0,
		"volume do som do mundo cai com a distância")
	var slot0: int = Sfx._next_3d
	Sfx.play_at("hit", player.global_position + Vector3(Sfx.FAR_DIST + 5.0, 0, 0))
	check(Sfx._next_3d == slot0, "som de combate longe do jogador é descartado")
	var near_pos := player.global_position + Vector3(10, 0, 0)
	Sfx.play_at("hit", near_pos)
	var used: AudioStreamPlayer3D = Sfx._players_3d[slot0]
	check(Sfx._next_3d != slot0 and used.global_position.is_equal_approx(near_pos) and used.volume_db < -1.0,
		"som de combate perto toca no lugar certo, mais baixo (%.1f dB)" % used.volume_db)
	var slot_anvil: int = Sfx._next_3d
	Sfx.play_at("anvil", player.global_position + Vector3(2, 0, 0))
	check(Sfx._next_3d != slot_anvil, "som da bigorna toca perto do jogador")
	check(get_tree().get_nodes_in_group("enemies").size() >= 15, "inimigos spawnados (%d)" % get_tree().get_nodes_in_group("enemies").size())
	# monstros do vale: os pontos de antes continuam (cada tipo com pelo menos o que tinha) e os bandos das
	# regiões com nome (MapRegion + regions.json) enchem o mapa: ~120 no total, cada região com o bando dela
	var by_kind := {}
	var by_area := {}
	var vale_total := 0
	var nest_ok := true
	var area_ok := true
	for en in get_tree().get_nodes_in_group("enemies"):
		if Regions.region_at(en.global_position) != "vila":
			continue   # os mapas da guilda (bosque, mina, pico) têm os monstros deles; aqui conta só o vale
		vale_total += 1
		by_kind[en.kind] = int(by_kind.get(en.kind, 0)) + 1
		if en.area != "":
			by_area[en.area] = int(by_area.get(en.area, 0)) + 1
		if en.kind == "slime_mae" or (en.kind in ["slime_veloz", "slime_explosivo"] and en.area == "ninho_slimes"):
			nest_ok = nest_ok and en.global_position.distance_to(world.NEST) < 24.0   # o disco do ninho (r14) e o bando da borda
	var before := {"slime_veloz": 4, "slime_explosivo": 3, "slime_mae": 1, "goblin_arqueiro": 2, "goblin_xama": 1,
		"goblin_campeao": 1, "goblin_bruto": 2, "goblin_dourado": 2, "esqueleto": 3, "esqueleto_arqueiro": 2,
		"esqueleto_mago": 1, "esqueleto_cavaleiro": 1, "goblin_bombardeiro": 2, "slime_gelo": 2, "raptor_capim": 6,
		"tecela": 3, "flor_faminta": 3, "bocarrao": 2}
	var missing: Array = []
	for k in before:
		if int(by_kind.get(k, 0)) < before[k]:
			missing.append("%s %d/%d" % [k, int(by_kind.get(k, 0)), before[k]])
	check(missing.is_empty(), "vale: cada tipo com pelo menos os monstros de antes %s" % str(missing))
	check(nest_ok, "Ninho de Slimes: a mãe e as crias perto do ninho")
	check(vale_total >= 110, "vale cheio: %d monstros (alvo ~120)" % vale_total)
	for id in ["campos_norte", "ninho_slimes", "margem_lagoa", "toca_goblins", "capinzal_raptores", "teia_tecelas",
			"cemiterio_velho", "ruinas_valdoria", "forte_brutos", "jardim_faminto", "fonte_gelada"]:
		area_ok = area_ok and int(by_area.get(id, 0)) >= 5
	check(area_ok, "cada região do vale com um bando (≥ 5): %s" % str(by_area))
	# os quatro cantos do vale: um tipo de monstro em cada (sem misturar), e nenhum slime de gelo nos Campos
	var corner := {"capinzal_raptores": "raptor_capim", "teia_tecelas": "tecela", "jardim_faminto": "flor_faminta",
		"fonte_gelada": "slime_gelo"}
	var corner_bad: Array = []
	for en in get_tree().get_nodes_in_group("enemies"):
		if corner.has(en.area) and en.kind != corner[en.area]:
			corner_bad.append("%s@%s" % [en.kind, en.area])
		elif en.kind in corner.values() and Regions.region_at(en.global_position) == "vila" and not corner.has(en.area):
			corner_bad.append("%s fora do canto (%s)" % [en.kind, en.area])
	check(corner_bad.is_empty(), "cantos do vale com um tipo de monstro cada %s" % str(corner_bad))
	var lv_ok := true
	for en in get_tree().get_nodes_in_group("enemies"):
		if en.area != "" and en.level <= 0:
			lv_ok = false
	check(lv_ok, "todo monstro de região tem nível (o ponto ou a faixa da região)")
	# cada tipo na sua área: nenhum goblin nas Ruínas nem no Cemitério, nenhum esqueleto fora deles
	var mixed: Array = []
	for en in get_tree().get_nodes_in_group("enemies"):
		var undead_area: bool = en.area in ["cemiterio_velho", "ruinas_valdoria"]
		if (en.kind.begins_with("goblin") and en.kind != "goblin_king" and undead_area) 				or (en.kind.begins_with("esqueleto") and not undead_area and Regions.region_at(en.global_position) == "vila"):
			mixed.append("%s@%s" % [en.kind, en.area])
	check(mixed.is_empty(), "goblins e esqueletos em áreas separadas %s" % str(mixed))
	var asas_want := 3 if world.is_night() else 0
	check(by_kind.get("asa_couro", 0) == asas_want, "Asas-couro nas Ruínas só de noite (%d, esperado %d)"
		% [by_kind.get("asa_couro", 0), asas_want])
	var gear_ok := true
	for en in get_tree().get_nodes_in_group("enemies"):
		var want: Array = en.data.get("gear", [])
		var got: Array = EnemyGear.names(en.model)
		got.sort()
		var w2 := want.duplicate()
		w2.sort()
		gear_ok = gear_ok and got == w2
	check(gear_ok, "cada monstro só carrega o equipamento da sua variante")
	# vale: 5 NPCs + bilhete + portal + guilda (Lina, quadro, cocheiro) + Rufus, Zélia, Tonico, Ravi, Osvaldo, gato;
	# mais o Papai Noel e os pontos da antiga praça (Orin e recordes, hub_point no vale.tscn); mapas: Sylvi, Tico e cocheiro no bosque; Bolgar, diário e cocheiro na mina; só o cocheiro no pico (o Kael
	# de lá aparece no Arco 2)
	# + os guardas da vila (VillageGuard, também conversam)
	var n_inter := get_tree().get_nodes_in_group("interactable").size()
	var n_guards := get_tree().get_nodes_in_group("npc").filter(func(n: Node) -> bool: return n is VillageGuard).size()
	# a feira e as oficinas da vila do sul: 3 feirantes + o artesão, 4 moradores que passeiam e a mesa de alquimia
	var n_portal := 1 if Game.HORDE_ENABLED else 0   # o portal da Horda só existe com ela ligada
	check(n_inter == 6 + n_portal + 9 + 7 + 1 + world.points.size() + Game.FARM_PLOTS + 1 + 1 + 8 + n_guards + 4 + 4 + 1,
		"interagíveis do vale, da guilda e dos mapas + %d canteiros + caldeirão + bancadas de couraria e alquimia + feirantes, artesão e moradores + 8 portas de dungeon + %d guardas (%d)" % [Game.FARM_PLOTS, n_guards, n_inter])
	check(not ResourceLoader.exists("res://scenes/colony.tscn"), "sem a Defesa da Cidade")

	# --- diálogo e missão
	var elder: Node = null
	for n in get_tree().get_nodes_in_group("interactable"):
		if n.get("npc_id") == "elder":
			elder = n
	player.global_position = elder.global_position + Vector3(0, 0.2, 1.5)
	await wait(0.3)
	check(player.interact_target == elder, "jogador detecta o ancião para interagir")
	elder.interact(player)
	await wait(0.1)
	check(world.modal != null and get_tree().paused, "diálogo abre e pausa o jogo")
	check(world.modal.size.x > 100 and world.modal.size.y > 100, "janela de diálogo ocupa a tela (%s)" % world.modal.size)
	var pages: Array = world.modal.pages
	var last: Dictionary = pages[pages.size() - 1]
	check(last.has("choices"), "diálogo oferece escolha de missão")
	check(Game.quests.is_empty() and elder.marker.text == "!", "Bram mostra ! para a primeira missão da história")
	world.modal._choose(last.choices[0].action)
	await wait(0.1)
	check(Game.quest_state("chegada") == "active", "primeira missão da história aceita")
	check(world.modal == null and not get_tree().paused, "diálogo fecha e despausa")
	await _test_story_talk()
	# o ferreiro primeiro, logo depois da missão como antes do Bram e da Mira: ~25 s depois ele pode estar
	# na pausa entre ciclos (work_pause) e "começa trabalhando" falharia por sorte
	await _test_blacksmith()
	await _test_elder(elder as Elder)
	await _test_merchant()

	# --- combate corpo a corpo (um slime dos Campos do Norte: a missão dos slimes conta só os de lá)
	var slime := _nearest("slime", "campos_norte")
	var xp0 := Game.xp
	var lvl0 := Game.level
	var gold0 := Game.gold
	player.global_position = slime.global_position + Vector3(0, 0.3, 1.2)
	player.model.rotation.y = PI
	await wait(0.2)
	var hp0: float = slime.hp
	Game.fury = 0.0
	player.invuln = 3.0   # apanhar do slime também enche a fúria: aqui conta só o golpe do jogador
	player._start_swing()
	await wait(0.5)
	check(Game.fury > 0.0 and Game.fury < 10.0, "fúria sobe com o dano do golpe do jogador (%.2f)" % Game.fury)
	player.invuln = 0.0
	Game.fury = 0.0
	check(slime.hp < hp0, "golpe de espada causa dano (%.0f -> %.0f)" % [hp0, slime.hp])
	var w_fist: String = Game.equipment.weapon
	Game.equipment.weapon = ""
	check(player._unarmed() and player._attack_sound() == "punch" and is_equal_approx(player._swing_time(1), 0.3),
		"sem arma o golpe é soco: som de soco e combo de boxe")
	Game.equipment.weapon = w_fist
	check(not player._unarmed() and player._attack_sound().begins_with("sword_swing"), "com a espada volta o som de lâmina")
	slime.take_damage(9999, player.global_position, false)
	check(Game.level > lvl0 or Game.xp > xp0, "XP ganho ao matar slime")
	check(Game.quests.slimes.progress == 1, "progresso da missão 1/5")
	player.global_position = slime.global_position + Vector3(0, 0.3, 0)
	await wait(2.5)
	check(Game.gold > gold0, "ouro coletado do chão (%d -> %d)" % [gold0, Game.gold])

	# --- acerto de longe num slime parado em casa: ele persegue, não volta para casa curando o dano
	var far_s := _today(_nearest("slime"))
	far_s.global_position = far_s.home
	far_s._set_state("idle")
	# para o norte, longe da vila (do lado da cerca o jogador estaria sob a guarda e o slime não perseguiria)
	player.global_position = far_s.home + Vector3(0, 0.3, -far_s.data.aggro * 2.5)
	await wait(0.1)
	var far_hp: float = far_s.hp
	far_s.take_damage(10.0, player.global_position, false)
	await wait(0.4)
	check(far_s.hp < far_hp and far_s.state == "chase",
		"acerto de longe não é curado na hora (%.0f -> %.0f, %s)" % [far_hp, far_s.hp, far_s.state])
	await _test_village_guard()

	# --- Investida (espada, slot 1): avança pela frente atravessando o slime
	var pos_c := player.global_position
	var ch_s := _today(_nearest_clear_lane("slime"))
	ch_s.global_position = ch_s.home
	player.global_position = ch_s.global_position + Vector3(0, 0.3, 3.0)
	player.model.rotation.y = PI   # olhando para -Z, para o slime
	player.velocity = Vector3.ZERO
	await wait(0.2)
	player.global_position = ch_s.global_position + Vector3(0, 0.3, 3.0)
	player.model.rotation.y = PI
	player.cooldowns.sword_charge = 0.0
	var ch_hp: float = ch_s.hp
	var ch_from := player.global_position
	player.use_slot(1)
	check(player.ability == "sword_charge", "Investida começa (%s)" % player.ability)
	var mask_c: int = player.collision_mask
	await wait(0.75)   # folga sobre SwordAbilities.CHARGE_TIME (0,6 s)
	var ch_d := Vector2(player.global_position.x - ch_from.x, player.global_position.z - ch_from.z).length()
	check(ch_s.hp < ch_hp, "Investida fere o slime no caminho (%.0f -> %.0f)" % [ch_hp, ch_s.hp])
	# o dano é fixo (melee_damage x1,6, sem crítico): a perda de vida igual a um golpe prova acerto único
	# (com a afinidade ao físico do slime, ElementRules)
	var ch_want: float = Game.melee_damage() * SwordAbilities.CHARGE_MULT * ch_s.element_mult("fisico")
	check(is_equal_approx(ch_hp - ch_s.hp, ch_want),
		"Investida acerta cada inimigo uma vez só (perdeu %.1f, golpe %.1f)" % [ch_hp - ch_s.hp, ch_want])
	check(ch_d >= 3.0 and ch_d <= 5.5, "Investida avança entre 3 e 5,5 m (%.2f, de %s, slime %s)" % [ch_d, ch_from, ch_s.home])
	check(player.ability == "" and player.cooldowns.sword_charge > 0.0, "Investida termina e entra em recarga (%s, %.2f)" % [player.ability, player.cooldowns.sword_charge])
	check(player.collision_mask == mask_c, "Investida devolve a colisão com inimigos ao terminar")
	# as próximas investidas vão para longe do slime (+Z)
	var away := ch_s.global_position + Vector3(0, 0.3, 3.0)
	# end_ability no meio do avanço: colisão de volta e sem velocidade especial
	player.global_position = away
	player.model.rotation.y = 0.0
	player.cooldowns.sword_charge = 0.0
	player.use_slot(1)
	await wait(0.25)
	var mid_v := Vector2(player.velocity.x, player.velocity.z).length()
	check(player.ability == "sword_charge" and player.collision_mask != mask_c and mid_v > 10.0,
		"Investida no meio do avanço atravessa inimigos (vel %.1f)" % mid_v)
	player.end_ability()
	check(player.ability == "" and player.ability_t == 0.0 and player.collision_mask == mask_c
		and Vector2(player.velocity.x, player.velocity.z).length() < 0.01, "end_ability no avanço limpa estado, colisão e velocidade")
	# esquiva: cancela no preparo, é ignorada no avanço
	Game.stamina = Game.max_stamina()
	player.global_position = away
	player.velocity = Vector3.ZERO
	await wait(0.2)
	player.cooldowns.sword_charge = 0.0
	player.use_slot(1)
	await wait(0.05)
	player._dodge_pressed(Vector3.ZERO)
	check(player.ability == "" and player.dodge_timer > 0.0, "esquiva no preparo cancela a Investida")
	await wait(0.5)
	Game.stamina = Game.max_stamina()
	player.global_position = away
	player.velocity = Vector3.ZERO
	await wait(0.2)
	player.cooldowns.sword_charge = 0.0
	player.use_slot(1)
	await wait(0.3)
	player._dodge_pressed(Vector3.ZERO)
	check(player.ability == "sword_charge" and player.dodge_timer <= 0.0, "esquiva no avanço é ignorada")
	await wait(0.45)
	# abrir menu (input_locked) encerra
	player.global_position = away
	player.cooldowns.sword_charge = 0.0
	player.use_slot(1)
	player.input_locked = true
	await wait(0.05)
	player.input_locked = false
	check(player.ability == "", "menu (input_locked) encerra a habilidade")
	Game.fury = 0.0
	Game.stamina = Game.max_stamina()
	player.cooldowns.sword_charge = 0.0
	player.global_position = pos_c
	player.velocity = Vector3.ZERO
	await wait(0.1)

	# --- Golpe Sísmico (espada, slot 2, nível 3): cone à frente fere e atordoa, quem está atrás não
	var lvl_q := Game.level
	Game.level = 3
	var qk_a := _nearest("slime")
	var qk_b: Enemy = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != qk_a and e.kind == "slime" and not e.dead:
			qk_b = e
			break
	var qk_base := pos_c + Vector3(0, 0.3, 0)   # chão firme dos campos (fora da zona da guarda da vila)
	_today(qk_a)   # o mais próximo pode ser o ferido pela Investida
	_today(qk_b)
	player.global_position = qk_base
	player.model.rotation.y = PI   # olhando para -Z
	player.velocity = Vector3.ZERO
	qk_a.global_position = qk_base + Vector3(0, 0, -3.0)
	qk_b.global_position = qk_base + Vector3(0, 0, 3.0)
	await wait(0.2)
	player.global_position = qk_base
	player.model.rotation.y = PI
	qk_a.global_position = qk_base + Vector3(0, 0, -3.0)
	qk_b.global_position = qk_base + Vector3(0, 0, 3.0)
	player.cooldowns.sword_quake = 0.0
	var qk_ahp: float = qk_a.hp
	var qk_bhp: float = qk_b.hp
	qk_a._set_state("attack")   # no meio de um golpe: o atordoamento o interrompe
	var qk_pos: Vector3 = qk_a.global_position
	player.use_slot(2)
	check(player.ability == "sword_quake", "Golpe Sísmico começa (%s)" % player.ability)
	await wait(0.8)   # 0,35 s de preparo + 0,3 s de recuperação, com folga
	check(qk_a.hp < qk_ahp, "Golpe Sísmico fere o slime da frente (%.0f -> %.0f)" % [qk_ahp, qk_a.hp])
	check(is_equal_approx(qk_ahp - qk_a.hp, Game.melee_damage() * SwordAbilities.QUAKE_MULT * qk_a.element_mult("fisico")),
		"Golpe Sísmico causa melee_damage x2 (perdeu %.1f)" % (qk_ahp - qk_a.hp))
	check(qk_b.hp == qk_bhp, "Golpe Sísmico não fere quem está atrás")
	check(player.ability == "" and player.cooldowns.sword_quake > 0.0, "Golpe Sísmico termina e entra em recarga (%s, %.2f)" % [player.ability, player.cooldowns.sword_quake])
	# 0,8 s depois do início (0,45 s após o impacto) ainda restam ~0,55 s dos 1,0 s de atordoamento
	check(qk_a.stagger > 0.3 and qk_a.state != "attack", "Golpe Sísmico atordoa e interrompe o golpe (stagger %.2f, %s)" % [qk_a.stagger, qk_a.state])
	check(qk_pos.distance_to(qk_a.global_position) < 2.5, "inimigo atordoado não avançou (%.2f m)" % qk_pos.distance_to(qk_a.global_position))
	# a esquiva não cancela
	Game.stamina = Game.max_stamina()
	qk_a.hp = qk_a.max_hp   # sobrevive ao segundo golpe
	player.cooldowns.sword_quake = 0.0
	player.use_slot(2)
	await wait(0.1)
	player._dodge_pressed(Vector3.ZERO)
	check(player.ability == "sword_quake" and player.dodge_timer <= 0.0, "esquiva não cancela o Golpe Sísmico")
	await wait(0.7)
	# colado no jogador, o atordoado não volta a atacar durante o atordoamento
	player.global_position = qk_base
	player.model.rotation.y = PI
	qk_a.global_position = qk_base + Vector3(0, 0, -1.2)
	qk_a.attack_cd = 0.0
	qk_a.hp = qk_a.max_hp
	player.cooldowns.sword_quake = 0.0
	player.use_slot(2)
	await wait(0.45)   # impacto aos 0,35 s
	var qk_attacked := false
	for i in 8:
		await wait(0.08)
		if qk_a.state == "attack":
			qk_attacked = true
	check(qk_a.stagger > 0.0 and not qk_attacked, "atordoado ao alcance não ataca durante o atordoamento (stagger %.2f)" % qk_a.stagger)
	await wait(0.3)
	Game.level = lvl_q
	Game.fury = 0.0
	player.cooldowns.sword_quake = 0.0
	player.global_position = pos_c
	player.velocity = Vector3.ZERO
	await wait(0.1)

	# --- Turbilhão (ultimate da espada, slot 4, nível 8, fúria cheia): gira ferindo e puxando em volta
	var lvl_w := Game.level
	var hp_w := Game.hp
	var spring_w: float = player.spring.spring_length
	Game.level = 8
	Game.fury = 100.0
	var s1 := _today(_nearest("slime"))
	player.global_position = s1.global_position + Vector3(2.5, 0.3, 0)
	player.velocity = Vector3.ZERO
	var h1: float = s1.hp
	player.invuln = 3.0   # apanhar de um inimigo próximo também enche a fúria: só os acertos do giro contam aqui
	player.use_slot(4)
	check(Game.fury == 0.0 and player.ability == "sword_whirl", "Turbilhão começa e gasta a fúria")
	check(player.ability_slot == 4, "ability_slot = tecla que começou a habilidade (%d)" % player.ability_slot)
	player.use_slot(1)   # com habilidade em execução o cast é ignorado: a soltura continua da tecla 4
	check(player.ability == "sword_whirl" and player.ability_slot == 4, "tecla de outro slot não sobrescreve ability_slot (%d)" % player.ability_slot)
	await wait_until(func(): return s1.hp < h1, 3.0)
	check(Game.fury == 0.0, "Turbilhão que acertou não recarrega a própria fúria (%.2f)" % Game.fury)
	check(s1.hp < h1, "Turbilhão causa dano durante o giro (%.0f -> %.0f)" % [h1, s1.hp])
	# imune a empurrão: o golpe tira vida mas não empurra nem levanta
	player.invuln = 0.0
	player.take_damage(1.0, player.global_position + Vector3(0, 0, 3.0))
	check(player.velocity.y < 1.0 and Vector2(player.velocity.x, player.velocity.z).length() < 3.0,
		"Turbilhão: imune a empurrão (vel %s)" % player.velocity)
	check(player.spring.spring_length > spring_w + 0.2, "Turbilhão: câmera recua (%.2f -> %.2f)" % [spring_w, player.spring.spring_length])
	Game.stamina = Game.max_stamina()
	player._dodge_pressed(Vector3.ZERO)
	check(player.ability == "sword_whirl" and player.dodge_timer <= 0.0, "esquiva não cancela o Turbilhão")
	player._die()
	await wait(0.1)
	check(player.ability == "" and is_equal_approx(Engine.time_scale, 1.0), "morrer no meio limpa o estado")
	player.revive(player.global_position)
	# a tela de morte abre 1,8 s depois de morrer, mesmo revivido: fecha sem a multa de ouro
	await wait(2.0)
	if world.modal != null:
		world.modal.queue_free()
		world.modal = null
	world._set_paused(false)
	check(not player.dead and not get_tree().paused, "reviveu depois de morrer no Turbilhão")
	check(absf(player.spring.spring_length - spring_w) < 0.05, "câmera volta ao normal (%.2f)" % player.spring.spring_length)
	# puxão: o golpe com pull leva o inimigo em direção a quem bateu (em vez de empurrar)
	var pl_s := _today(_nearest("slime"))
	pl_s.global_position = player.global_position + Vector3(3.0, 0.0, 0.0)
	pl_s.velocity = Vector3.ZERO
	pl_s.take_damage(0.5, player.global_position, false, 0.0, 0.0, SwordAbilities.WHIRL_PULL)
	var to_pl := player.global_position - pl_s.global_position
	check(Vector2(pl_s.velocity.x, pl_s.velocity.z).dot(Vector2(to_pl.x, to_pl.z)) > 0.0,
		"golpe com puxão leva o inimigo para o jogador (vel %s)" % pl_s.velocity)
	# giro inteiro: termina sozinho, tempo normal e o modelo volta a olhar para onde olhava
	Game.fury = 100.0
	player.invuln = 0.0
	player.model.rotation.y = 0.5
	# o puxão se vê: um inimigo a 3 m termina bem mais perto depois do giro (com vida de sobra para não morrer).
	# Num campo aberto: perto da ponte ou de uma cerca, a mureta entre os dois segurava o puxão.
	var pull_back := player.global_position
	player.global_position = Vector3(60, 0.3, 70)
	await wait(0.1)
	var pl_max: float = pl_s.max_hp
	var pl_home: Vector3 = pl_s.home
	pl_s.hp = 100000.0
	pl_s.max_hp = 100000.0
	pl_s.global_position = player.global_position + Vector3(3.0, 0.0, 0.0)
	pl_s.velocity = Vector3.ZERO
	# só o puxão mexe no slime: preso (não anda nem ataca; o empurrão dos golpes ainda vale) e com a casa aqui (longe
	# de casa ele alternava entre perseguir e voltar). Solto, a IA andava entre as voltas e o puxão media 2,5 m no CI.
	pl_s.home = pl_s.global_position
	pl_s.held_t = SwordAbilities.WHIRL_TIME + 2.0
	var d_pull0: float = pl_s.global_position.distance_to(player.global_position)
	var lvl_w2: int = Game.level
	Game.level = 8   # morrer e reviver passa pelo Econ, cuja resposta devolve Game.level ao nível real
	player.use_slot(4)
	check(player.ability == "sword_whirl", "Turbilhão de novo com a fúria cheia (nível antes %d, %s, esquiva %.2f, atacando %s)"
		% [lvl_w2, player.ability, player.dodge_timer, player.attacking])
	# mede logo antes do golpe final: ele EMPURRA (_whirl_finale), e quanto o inimigo voa até a habilidade
	# acabar depende dos quadros de física que cabem nos ~0,12 s seguintes (no CI chegava a 4,8 m, mais longe
	# que o começo, e o teste falhava sem o puxão ter falhado)
	# mede a cada quadro de física até o golpe final (antes conferia a cada 0,05 s numa janela de 0,04 s: às vezes
	# passava do golpe e media o inimigo já empurrado, 4,5-4,9 m)
	var d_pull1: float = d_pull0
	var pull_t0 := Time.get_ticks_msec()
	while player.ability == "sword_whirl" and player.ability_t < SwordAbilities.WHIRL_IMPACT 			and Time.get_ticks_msec() - pull_t0 < int((SwordAbilities.WHIRL_TIME + 1.5) * 1000.0):
		d_pull1 = pl_s.global_position.distance_to(player.global_position)
		await get_tree().physics_frame
	await wait_until(func(): return player.ability == "", SwordAbilities.WHIRL_TIME + 1.5)
	var d_end: float = pl_s.global_position.distance_to(player.global_position)
	# o puxão por volta depende de quantos quadros de física cabem no giro: na máquina local leva ~1,7 m,
	# no CI lento chegou a 0,98 m. 0,6 m ainda separa com folga o puxão de um inimigo parado.
	check(d_pull0 - d_pull1 >= 0.6, "Turbilhão puxa o inimigo para perto (%.2f m -> %.2f m antes do golpe final; %.2f m depois)"
		% [d_pull0, d_pull1, d_end])
	player.global_position = pull_back
	pl_s.max_hp = pl_max
	pl_s.hp = pl_max
	pl_s.home = pl_home
	pl_s.held_t = 0.0
	check(player.ability == "" and is_equal_approx(Engine.time_scale, 1.0), "Turbilhão termina sozinho (%s)" % player.ability)
	check(absf(wrapf(player.model.rotation.y - 0.5, -PI, PI)) < 0.05, "giro volta à direção inicial (%.2f)" % player.model.rotation.y)
	Game.level = lvl_w
	Game.fury = 0.0
	Game.hp = hp_w
	player.cooldowns.sword_whirl = 0.0
	player.global_position = pos_c
	player.velocity = Vector3.ZERO
	await wait(0.1)

	# --- servidor dedicado: nenhum nó de efeito nasce (FX._scene() devolve null)
	var mode_s: int = Network.mode
	Network.mode = Network.Mode.SERVER
	var kids_s := world.get_child_count()
	check(FX._scene() == null, "servidor dedicado não cria efeitos (FX._scene nulo)")
	FX.ring(player.global_position, Color.WHITE, 3.0, 0.3)
	FXEpic.nova(player.global_position, Color.ORANGE, 20, 5.0, 0.2, 0.4)
	check(world.get_child_count() == kids_s and FXEpic.stream(player, "flame", Color.ORANGE, 10, 0.5) == null,
		"servidor: chamadas de efeito não adicionam nós")
	Network.mode = mode_s

	# --- kits de habilidade por arma (começa de espada: weapon_class() == "sword")
	var kit_weapon: String = Game.equipment.weapon
	check(Game.ability_kit() == ["sword_charge", "sword_quake", "sword_fury", "sword_whirl"], "kit da espada (%s)" % [Game.ability_kit()])
	check(not Game.knows_ability("sword_quake") and Game.knows_ability("sword_charge"), "liberação por nível")
	check(Game.level < 3 and not Game.knows_ability("frost_nova") and ItemDB.ABILITIES.frost_nova.level == 3, "Nova Gélida só no nível 3")
	await _check_aegis(player, world)
	await _check_hammer(player, world)
	await _check_earthquake(player, world)
	await _check_dark_taunt(player, world)
	await _check_party_shield(player, world)
	await _check_supreme(player, world)
	await _check_drag_slash(player, world)
	await _check_spin(player, world)
	await _check_dark_combo(player, world)
	# todas as habilidades estão prontas (a Chuva de Meteoros foi a última): o caminho "Em breve" não tem mais
	# quem testar; resta conferir que há recarga para cada habilidade
	Game.add_item("short_bow")
	equip_any("short_bow")
	var lvl_bf: int = Game.level
	check(Game.weapon_class() == "bow" and player.cooldowns.size() == ItemDB.ABILITIES.size(), "uma recarga por habilidade")
	# --- arco: botão direito mira (puxa a corda), esquerdo atira; o clique direito não esquiva com arco
	var bw_shot := [0, null]   # flechas disparadas (contadas ao entrar na cena: somem ao acertar) e a última
	var bw_count := func(c: Node) -> void:
		if c.get("kind") == "arrow" and not c.get("visual_only"):
			bw_shot[0] += 1
			bw_shot[1] = c
	world.child_entered_tree.connect(bw_count)
	var bw_arrows := func() -> int: return bw_shot[0]
	await wait_until(func(): return player.dodge_timer <= 0.0 and not player.attacking and not player.drawing)
	Game.stamina = Game.max_stamina()
	var bw_n0: int = bw_arrows.call()
	Input.action_press("aim")
	Input.action_press("dodge")    # o mesmo clique direito aperta as duas ações
	await wait(0.5)
	check(player.aiming and player.drawing and player.dodge_timer <= 0.0 and player.bow_charge() > 0.3,
		"arco: botão direito mira e puxa sem esquivar (carga %.2f, esquiva %.2f)" % [player.bow_charge(), player.dodge_timer])
	var bw_hand: Vector3 = (player.parts.ElbowR as Node3D).global_transform * (player.parts.hand_r as Vector3)
	var bw_head: Vector3 = (player.parts.Head as Node3D).global_position
	await wait(0.5)
	bw_hand = (player.parts.ElbowR as Node3D).global_transform * (player.parts.hand_r as Vector3)
	bw_head = (player.parts.Head as Node3D).global_position
	check(bw_hand.distance_to(bw_head) < 0.25, "arco: com a corda toda puxada a mão vai ao queixo (%.2f m)" % bw_hand.distance_to(bw_head))
	Input.action_press("attack")
	await wait(0.05)
	Input.action_release("attack")
	check(bw_arrows.call() == bw_n0 + 1 and player.attacking, "arco: clique esquerdo mirando atira")
	# a flecha voa na linha da câmera (a mira), não do arco à esquerda dela
	var bw_ar = bw_shot[1]
	if bw_ar and is_instance_valid(bw_ar):
		var bw_co: Vector3 = player.camera.global_position
		var bw_f: Vector3 = -player.camera.global_basis.z
		var bw_rel: Vector3 = (bw_ar as Node3D).global_position - bw_co
		var bw_off := (bw_rel - bw_f * bw_rel.dot(bw_f)).length()
		check(bw_off < 0.6, "arco: a flecha sai na linha da mira (%.2f m dela)" % bw_off)
	await wait(KnightMoves.BOW_RELEASE_HOLD + 0.5)
	check(player.drawing, "arco: segurando a mira, encaixa a próxima flecha sozinho")
	Input.action_release("aim")
	Input.action_release("dodge")
	await wait(0.1)
	check(not player.drawing and not player.aiming and bw_arrows.call() == bw_n0 + 1, "arco: soltar a mira baixa o arco sem atirar")
	await wait_until(func(): return not player.attacking)
	Input.action_press("attack")
	await wait(0.05)
	Input.action_release("attack")
	await wait(0.45)
	check(bw_arrows.call() == bw_n0 + 2, "arco: clique esquerdo sem mirar dá um tiro rápido")
	world.child_entered_tree.disconnect(bw_count)
	# --- Tiro Triplo (arco, slot 1): 3 flechas em leque, ignora multishot, esquiva só cancela antes do disparo
	var tt_pos := player.global_position
	var tt_s := _nearest("slime")
	var tt_max: float = tt_s.max_hp
	tt_s.max_hp = 100000.0   # aguenta as 9 flechas sem morrer (o nó some ao morrer)
	tt_s.global_position = tt_s.home
	var tt_fire := func() -> Array:
		var out := []
		for c in world.get_children():
			if c.get("kind") == "arrow" and not c.visual_only:
				out.append(c)
		return out
	Game.add_item("storm_bow")
	Game.add_item("goblin_warbow")
	var tt_weapons := ["short_bow", "storm_bow", "goblin_warbow"]
	var tt_grounded := func() -> bool: return player.is_on_floor()
	for tt_w in tt_weapons:
		equip_any(tt_w)
		await wait_until(func(): return player.dodge_timer <= 0.0 and not player.attacking)
		for c in tt_fire.call():
			c.queue_free()
		tt_s.global_position = tt_s.home
		player.global_position = tt_s.global_position + Vector3(0, 0.3, 6.0)
		player.model.rotation.y = PI
		player.velocity = Vector3.ZERO
		await wait_until(tt_grounded)
		player.global_position = tt_s.global_position + Vector3(0, 0.3, 6.0)
		_on_aim_line(tt_s)
		player.cooldowns.bow_triple = 0.0
		tt_s.hp = tt_s.max_hp
		var tt_hp: float = tt_s.hp
		player.use_slot(1)
		check(player.ability == "bow_triple" and BowAbilities.can_dodge_cancel(player), "Tiro Triplo começa (%s, %s)" % [player.ability, tt_w])
		await wait_until(func(): return tt_fire.call().size() > 0 or player.ability == "")
		var tt_arrows: Array = tt_fire.call()
		var tt_n: int = tt_arrows.size()
		var tt_ab: bool = player.ability == "bow_triple"
		check(tt_n == 3 and tt_ab and not BowAbilities.can_dodge_cancel(player),
			"Tiro Triplo dispara 3 flechas de uma vez (%s: %d)" % [tt_w, tt_n])
		if tt_n == 3:
			# dano de cada flecha (x0,8, x1,8 se crítica), velocidade 42 e perfuração só com fx "pierce"
			var tt_dmg_ok := true
			var tt_pierce_ok := true
			var tt_flat := []
			for ar in tt_arrows:
				var want: float = Game.melee_damage() * BowAbilities.TRIPLE_MULT * (1.8 if ar.crit else 1.0)
				tt_dmg_ok = tt_dmg_ok and absf(ar.damage - want) < 0.01 and is_equal_approx(ar.speed, BowAbilities.TRIPLE_SPEED)
				tt_pierce_ok = tt_pierce_ok and ar.pierce == (2 if tt_w == "goblin_warbow" else 0)
				var f: Vector3 = ar.direction
				f.y = 0.0
				tt_flat.append(f.normalized())
			tt_flat.sort_custom(func(x, y): return x.signed_angle_to(y, Vector3.UP) < 0.0)   # esquerda, centro, direita
			var ang_a := rad_to_deg(absf(tt_flat[0].signed_angle_to(tt_flat[1], Vector3.UP)))
			var ang_b := rad_to_deg(absf(tt_flat[1].signed_angle_to(tt_flat[2], Vector3.UP)))
			var ang_c := rad_to_deg(tt_flat[0].angle_to(tt_flat[2]))
			check(tt_dmg_ok, "Tiro Triplo: dano x0,8 e velocidade 42 em cada flecha (%s)" % tt_w)
			check(tt_pierce_ok, "Tiro Triplo: perfuração %s (%s)" % ["+2 com fx pierce" if tt_w == "goblin_warbow" else "0", tt_w])
			check(absf(ang_a - 12.0) < 0.5 and absf(ang_b - 12.0) < 0.5 and absf(ang_c - 24.0) < 0.5,
				"Tiro Triplo: leque de 12 graus (%.1f, %.1f, total %.1f)" % [ang_a, ang_b, ang_c])
		await wait_until(func(): return player.ability == "")
		# as flechas ainda voam os 6 m até o slime quando a habilidade termina: espera o acerto (com prazo)
		await wait_until(func(): return tt_s.hp < tt_hp, 1.0)
		check(player.cooldowns.bow_triple > 0.0 and tt_s.hp < tt_hp, "Tiro Triplo fere o slime e entra em recarga (%.0f -> %.0f)" % [tt_hp, tt_s.hp])
	# esquiva antes do disparo cancela sem gastar flechas (logo no início, ability_t = 0); depois é ignorada
	equip_any("short_bow")
	await wait_until(func(): return player.dodge_timer <= 0.0 and not player.attacking)
	Game.stamina = Game.max_stamina()
	player.global_position = tt_pos
	for c in tt_fire.call():
		c.queue_free()
	player.cooldowns.bow_triple = 0.0
	player.use_slot(1)
	check(player.ability == "bow_triple" and player.ability_t < BowAbilities.TRIPLE_DRAW, "Tiro Triplo antes do disparo (t %.2f)" % player.ability_t)
	player._dodge_pressed(Vector3.ZERO)
	check(player.ability == "" and tt_fire.call().size() == 0 and player.dodge_timer > 0.0, "esquiva antes do disparo cancela o Tiro Triplo")
	await wait_until(func(): return player.dodge_timer <= 0.0)
	Game.stamina = Game.max_stamina()
	player.cooldowns.bow_triple = 0.0
	player.use_slot(1)
	await wait_until(func(): return player.ability_t >= BowAbilities.TRIPLE_DRAW or player.ability == "")
	player._dodge_pressed(Vector3.ZERO)
	check(player.ability == "bow_triple" and player.dodge_timer <= 0.0, "esquiva depois do disparo é ignorada")
	await wait_until(func(): return player.ability == "")
	for c in tt_fire.call():
		c.queue_free()
	# réplica: o evento "bow_triple" cria 3 flechas só visuais, sem dano, e a pose acaba em 0,25 s
	var tt_rp := Player.new()
	tt_rp.remote = true
	world.add_child(tt_rp)
	tt_s.hp = tt_s.max_hp
	var tt_rhp: float = tt_s.hp
	var tt_o := tt_s.global_position + Vector3(0, 1.2, 6.0)
	var tt_vis_before := 0
	for c in world.get_children():
		if c.get("kind") == "arrow" and c.visual_only:
			tt_vis_before += 1
	BowAbilities.play_remote(tt_rp, "bow_triple", tt_o, Vector3(0, 0, -1))
	var tt_vis := []
	for c in world.get_children():
		if c.get("kind") == "arrow" and c.visual_only:
			tt_vis.append(c)
	check(tt_vis.size() - tt_vis_before == 3 and tt_fire.call().size() == 0, "réplica do Tiro Triplo cria 3 flechas visual_only (%d)" % [tt_vis.size() - tt_vis_before])
	check(tt_rp.ability == "bow_triple" and is_equal_approx(tt_rp.ability_t, BowAbilities.TRIPLE_DRAW), "réplica começa no disparo")
	var tt_t0 := Time.get_ticks_msec()
	await wait_until(func(): return tt_rp.ability == "")
	var tt_el := (Time.get_ticks_msec() - tt_t0) / 1000.0
	check(tt_rp.ability == "" and tt_el >= BowAbilities.TRIPLE_RECOVER - 0.1, "réplica termina após a recuperação de 0,25 s (%.2f s)" % tt_el)
	await wait(0.6)   # as flechas visuais atravessam o slime: sem dano
	check(tt_s.hp == tt_rhp, "flechas da réplica não ferem (%.0f)" % tt_s.hp)
	tt_rp.queue_free()
	for c in world.get_children():
		if c.get("kind") == "arrow":
			c.queue_free()
	Game.stamina = Game.max_stamina()
	player.cooldowns.bow_triple = 0.0
	# --- Flecha Glacial (arco, slot 2): tensão 0,35 s, 1 flecha (dano x1,4, vel 40), prende 1,5 s + lentidão 3 s; chefe só a lentidão
	Game.level = 3
	equip_any("short_bow")
	await wait_until(func(): return player.dodge_timer <= 0.0 and not player.attacking)
	var fg_boss0: bool = tt_s.is_boss
	tt_s.global_position = tt_s.home
	player.global_position = tt_s.global_position + Vector3(0, 0.3, 6.0)
	player.model.rotation.y = PI
	player.velocity = Vector3.ZERO
	await wait_until(tt_grounded)
	player.global_position = tt_s.global_position + Vector3(0, 0.3, 6.0)
	_on_aim_line(tt_s)
	for c in tt_fire.call():
		c.queue_free()
	tt_s.stagger = 0.0
	tt_s.slow_timer = 0.0
	tt_s.hp = tt_s.max_hp
	var fg_hp: float = tt_s.hp
	player.cooldowns.bow_frost = 0.0
	Game.level = 3
	player.use_slot(2)
	check(player.ability == "bow_frost" and BowAbilities.can_dodge_cancel(player), "Flecha Glacial começa (%s)" % player.ability)
	await wait_until(func(): return tt_fire.call().size() > 0 or player.ability == "")
	var fg_arrows: Array = tt_fire.call()
	check(fg_arrows.size() == 1 and player.ability == "bow_frost" and player.ability_t >= BowAbilities.FROST_DRAW - 0.0001
		and not BowAbilities.can_dodge_cancel(player), "Flecha Glacial dispara 1 flecha só depois da tensão (%d, t %.2f)" % [fg_arrows.size(), player.ability_t])
	if fg_arrows.size() == 1:
		var fa = fg_arrows[0]
		var fwant: float = Game.melee_damage() * BowAbilities.FROST_MULT * (1.8 if fa.crit else 1.0)
		check(absf(fa.damage - fwant) < 0.01 and is_equal_approx(fa.speed, 40.0) and fa.pierce == 0 and fa.fx == "glacial",
			"Flecha Glacial: dano x1,4, velocidade 40, sem perfuração (%.1f vs %.1f, vel %.0f, fx %s)" % [fa.damage, fwant, fa.speed, fa.fx])
	await wait_until(func(): return tt_s.hp < fg_hp)
	check(tt_s.stagger > 0.8 and tt_s.slow_timer > 1.5, "Flecha Glacial prende e atrasa (stagger %.2f, slow %.2f)" % [tt_s.stagger, tt_s.slow_timer])
	await wait_until(func(): return player.ability == "")
	check(player.cooldowns.bow_frost > 0.0, "Flecha Glacial entra em recarga")
	# chefe: só a lentidão (sem prender)
	tt_s.is_boss = true
	tt_s.stagger = 0.0
	tt_s.slow_timer = 0.0
	tt_s.global_position = tt_s.home
	player.global_position = tt_s.global_position + Vector3(0, 0.3, 6.0)
	player.velocity = Vector3.ZERO
	await wait_until(tt_grounded)
	player.global_position = tt_s.global_position + Vector3(0, 0.3, 6.0)
	_on_aim_line(tt_s)
	player.cooldowns.bow_frost = 0.0
	fg_hp = tt_s.hp
	Game.level = 3
	player.use_slot(2)
	await wait_until(func(): return tt_s.hp < fg_hp)
	check(tt_s.stagger < 1.0 and tt_s.slow_timer > 0.0, "Flecha Glacial no chefe: só lentidão (stagger %.2f, slow %.2f)" % [tt_s.stagger, tt_s.slow_timer])
	await wait_until(func(): return player.ability == "")
	tt_s.is_boss = fg_boss0
	# réplica: flecha visual_only, sem dano nem prisão
	var fg_rp := Player.new()
	fg_rp.remote = true
	world.add_child(fg_rp)
	tt_s.stagger = 0.0
	tt_s.slow_timer = 0.0
	tt_s.hp = tt_s.max_hp
	var fg_rhp: float = tt_s.hp
	var fg_vis0 := 0
	for c in world.get_children():
		if c.get("kind") == "arrow" and c.visual_only:
			fg_vis0 += 1
	BowAbilities.play_remote(fg_rp, "bow_frost", tt_s.global_position + Vector3(0, 1.2, 6.0), Vector3(0, 0, -1))
	var fg_vis := []
	for c in world.get_children():
		if c.get("kind") == "arrow" and c.visual_only:
			fg_vis.append(c)
	check(fg_vis.size() - fg_vis0 == 1 and fg_rp.ability == "bow_frost" and tt_fire.call().size() == 0,
		"réplica da Flecha Glacial cria 1 flecha visual_only (%d)" % [fg_vis.size() - fg_vis0])
	await wait_until(func(): return fg_rp.ability == "")
	await wait(0.6)
	check(tt_s.hp == fg_rhp and tt_s.stagger <= 0.0 and tt_s.slow_timer <= 0.0, "flecha glacial da réplica não fere nem prende")
	fg_rp.queue_free()
	for c in world.get_children():
		if c.get("kind") == "arrow":
			c.queue_free()
	tt_s.stagger = 0.0
	tt_s.slow_timer = 0.0
	player.cooldowns.bow_frost = 0.0
	await _test_bow_gale()
	await _test_mythic_bows()
	await _test_meteor_rain()
	Game.level = lvl_bf
	tt_s.hp = tt_max
	tt_s.max_hp = tt_max
	tt_s.held_t = 0.0
	tt_s.global_position = tt_s.home
	player.global_position = tt_pos
	player.velocity = Vector3.ZERO
	equip_any(kit_weapon)
	player.cooldowns.sword_charge = 3.0   # para conferir que a recarga atravessa a troca de arma
	equip_any("apprentice_staff")
	await wait(0.1)
	check(Game.ability_kit() == ["fireball", "frost_nova", "staff_ember", "meteor_rain"], "trocar de arma troca o kit (cajado sem Cura)")
	check(player.cooldowns.sword_charge > 2.5, "recarga continua depois de trocar de arma")
	check(hud_slot_ids() == Game.ability_kit(), "barra de ações mostra o kit novo (%s)" % [hud_slot_ids()])
	var mp_m := Game.mp
	player.cast("meteor_rain")
	check(Game.mp == mp_m and player.cooldowns.meteor_rain == 0.0 and player.ability == "", "ultimate sem fúria não sai nem gasta nada")

	# --- magia do cajado enche a fúria (Nova Gélida causa dano ao slime perto)
	var lvl_n := Game.level
	var mp_n := Game.mp
	Game.level = 5
	Game.mp = Game.max_mp()
	player.cooldowns.frost_nova = 0.0
	player.cast_timer = 0.0
	var pos_n := player.global_position
	var nova_s := _nearest("slime")
	player.global_position = nova_s.global_position + Vector3(0, 0.3, 1.5)
	await wait(0.1)
	# a magia só sai com o jogador livre (cast() recusa no meio de golpe, esquiva ou habilidade)
	await wait_until(func(): return player.dodge_timer <= 0.0 and not player.attacking and player.ability == "")
	Game.fury = 0.0
	# o nível forçado vai logo antes da magia: qualquer estado que o Econ reaplica durante as esperas (ouro ou
	# saque recolhido ao chegar perto do slime) devolve o nível de verdade, e a Nova Gélida (nível 3) era recusada
	Game.level = 5
	player.cast("frost_nova")
	check(Game.fury > 0.0, "magia do cajado enche a fúria (%.2f; nível %d, recarga %.2f, golpe %s, esquiva %.2f, habilidade '%s', mana %.0f, slime a %.1f m)"
		% [Game.fury, Game.level, player.cooldowns.frost_nova, player.attacking, player.dodge_timer, player.ability, Game.mp,
			nova_s.global_position.distance_to(player.global_position)])
	# magias não roubam vida (o roubo é só do corpo a corpo)
	var weapon_n: String = Game.equipment.weapon
	var hp_n := Game.hp
	Game.equipment.weapon = "scarlet_talon"
	Game.hp = 10.0
	player.cooldowns.frost_nova = 0.0
	player.cast_timer = 0.0
	Game.mp = Game.max_mp()
	var nova_saved := {}   # sem abate: o XP subiria o nível do Econ e curaria (apply_state)
	for e in get_tree().get_nodes_in_group("enemies"):
		nova_saved[e] = [e.max_hp, e.hp]
		e.max_hp = 1.0e6
		e.hp = 1.0e6
	Game.level = 5
	player.cast("frost_nova")
	for e in nova_saved:
		if is_instance_valid(e):
			e.max_hp = nova_saved[e][0]
			e.hp = nova_saved[e][1]
	check(Game.gear("leech") > 0.0 and Game.hp <= 10.0, "Nova Gélida não rouba vida mesmo com roubo de vida equipado (%.1f)" % Game.hp)
	Game.equipment.weapon = weapon_n
	Game.hp = hp_n
	Game.fury = 0.0
	Game.level = lvl_n
	Game.mp = mp_n
	player.cooldowns.frost_nova = 0.0
	player.global_position = pos_n
	player.cast_timer = 0.0

	# --- habilidades de buff do slot 3 (espada, arco, cajado): nível 5 libera, nível 4 bloqueia
	var lvl_bz := Game.level
	var wp_bz: String = Game.equipment.weapon
	var bz_cases := [["sword_fury", kit_weapon, "damage", 0.3], ["bow_focus", "short_bow", "crit", 0.15],
		["staff_ember", "apprentice_staff", "damage", 0.2]]
	for bz in bz_cases:
		var bid: String = bz[0]
		equip_any(bz[1])
		Game.clear_buffs(true)
		Game.mp = Game.max_mp()
		player.cooldowns[bid] = 0.0
		player.cast_timer = 0.0
		Game.level = 4
		player.use_slot(3)
		check(not Game.has_buff(bid) and player.ability == "" and player.cooldowns[bid] == 0.0, "%s bloqueada no nível 4" % bid)
		Game.level = 5
		var base_m: float = Game.mod(bz[2])
		var mp_b: float = Game.mp
		player.use_slot(3)
		check(Game.has_buff(bid) and player.ability == bid, "%s dá o buff e começa (%s)" % [bid, player.ability])
		check(is_equal_approx(Game.mod(bz[2]) - base_m, bz[3]), "%s sobe o %s em %.2f (%.2f)" % [bid, bz[2], bz[3], Game.mod(bz[2]) - base_m])
		check(player.cooldowns[bid] > 0.0, "%s entra em recarga (%.1f)" % [bid, player.cooldowns[bid]])
		if bid == "staff_ember":
			check(Game.mp < mp_b, "staff_ember gasta mana")
			check(Game.cooldown_mult() < 1.0, "staff_ember reduz a recarga (%.2f)" % Game.cooldown_mult())
		check(player._vfx_state().auras.has(ItemDB.BUFFS[bid].aura), "%s liga a aura %s" % [bid, ItemDB.BUFFS[bid].aura])
		await wait(0.7)
		check(player.ability == "", "%s termina a pose" % bid)
		Game.clear_buffs(true)
	equip_any(wp_bz)

	# --- talentos valem no combate: dano, duração de buff, recarga, mana, cura
	var tm_saved: Dictionary = Game.talent_mods
	var ts := CharState.new()
	ts.char_class = "warrior"
	ts.talents = {"w_edge": 3, "w_rage": 1, "w_focus": 2}
	var dmg_t0: float = Game.mod("damage")
	var cd_t0: float = Game.cooldown_mult()
	Game.talent_mods = CharRules.talent_mods(Balance.tables, ts)
	check(is_equal_approx(Game.mod("damage") - dmg_t0, 0.12), "talento w_edge 3: dano +0,12 (%.3f)" % (Game.mod("damage") - dmg_t0))
	check(is_equal_approx(cd_t0 - Game.cooldown_mult(), 0.08) or Game.cooldown_mult() == 0.4, "talento w_focus 2: recarga -0,08 (%.3f)" % Game.cooldown_mult())
	check(is_equal_approx(Game.buff_duration("sword_fury"), 12.0), "w_rage 1: Fúria Picante dura 12 s (%.1f)" % Game.buff_duration("sword_fury"))
	Game.clear_buffs(true)
	Game.add_buff("sword_fury", Game.buff_duration("sword_fury"))
	check(is_equal_approx(float(Game.buffs.sword_fury), 12.0), "buff ligado com 12 s")
	Game.clear_buffs(true)
	var mp_t0 := Game.max_mp()
	Game.talent_mods = {"mp_pct": 0.16, "ability_time:scepter_ult": 4.0}
	check(is_equal_approx(Game.max_mp(), mp_t0 * 1.16), "mp_pct 0,16: mana máxima x1,16")
	check(is_equal_approx(Game.buff_duration("scepter_feast"), 16.0), "scepter_ult +4 s vale para o Banquete (%.1f)" % Game.buff_duration("scepter_feast"))
	check(is_equal_approx(Game.ability_dmg_mult("sword_whirl"), 1.0), "sem talento: dano da habilidade x1")
	Game.talent_mods = {"ability_dmg:sword_whirl": 0.2}
	check(is_equal_approx(Game.ability_dmg_mult("sword_whirl"), 1.2), "ability_dmg 0,2: x1,2")
	Game.talent_mods = {"ability_time:staff_ember": 6.0, "cooldown": -0.12}   # m_dragon 3 + m_focus 3
	var ember_dur: float = Game.buff_duration("staff_ember")
	var ember_cd: float = Game.ability_cooldown("staff_ember", 30.0, 0.4)   # cdr no mínimo (talentos + equipamento + o buff)
	check(is_equal_approx(ember_dur, 16.0) and is_equal_approx(ember_cd, ember_dur + 4.0), "recarga do buff >= duração + 4 s (%.1f / %.1f)" % [ember_cd, ember_dur])
	check(Game.ability_cooldown("sword_whirl", 10.0, 0.5) == 5.0, "habilidade sem buff próprio: sem piso")
	var hp_ls: float = Game.hp
	Game.talent_mods = {"lifesteal": 3.0}
	Game.hp = 10.0
	Game.kill_lifesteal()
	check(is_equal_approx(Game.hp, 13.0), "w_bloodlust: abate cura fora da Horda (%.1f)" % Game.hp)
	Game.hp = hp_ls
	Game.talent_mods = tm_saved
	Game.level = lvl_bz
	Game.mp = Game.max_mp()

	# --- barra de fúria e ultimate (slot 4 do cajado = meteor_rain)
	var lvl_f := Game.level
	var hp_f := Game.hp
	Game.fury = 0.0
	Game.on_damage_dealt(5.0, 100.0)
	check(is_equal_approx(Game.fury, 2.5), "fúria: 5 de dano em alvo de 100 de vida = 2.5 (%.2f)" % Game.fury)
	Game.on_damage_dealt(9999.0, 10.0)
	check(is_equal_approx(Game.fury, 8.5), "fúria: ganho por golpe limitado a 6 (%.2f)" % Game.fury)
	Game.on_damage_dealt(0.01, 1000.0)
	check(is_equal_approx(Game.fury, 9.0), "fúria: ganho mínimo 0.5 (%.2f)" % Game.fury)
	Game.fury = 0.0
	player.invuln = 0.0
	player.take_damage(Game.max_hp() * 0.4, player.global_position + Vector3(0, 0, 5))
	check(is_equal_approx(Game.fury, (Game.max_hp() * 0.4 * Game.damage_taken_mult()) / Game.max_hp() * 25.0), "fúria sobe ao receber dano (%.2f)" % Game.fury)
	Game.hp = hp_f
	player.invuln = 0.0
	Game.add_fury(500.0)
	check(Game.fury == 100.0 and Game.fury_full(), "fúria limitada a 100")
	Game.level = 8
	Game.fury = 50.0
	player.use_slot(4)
	check(Game.fury == 50.0, "ultimate não sai com fúria incompleta")
	Game.level = 2
	Game.fury = 100.0
	player.use_slot(4)
	check(Game.fury == 100.0, "ultimate não sai abaixo do nível 8")
	Game.level = 8
	player.use_slot(4)
	check(Game.fury == 0.0 and player.ability == "meteor_rain", "ultimate sai com fúria cheia no nível 8 e zera a fúria")
	player.end_ability()   # encerrada no preparo (o teste completo é _test_meteor_rain)
	player.cooldowns.meteor_rain = 0.0
	# --- fúria persistida no personagem (CharState)
	var fs := CharState.new()
	fs.fury = 70.0
	check(is_equal_approx(CharState.from_dict(fs.to_dict(), Balance.tables).fury, 70.0), "fúria: to_dict/from_dict preserva 70")
	var fd := fs.to_dict()
	fd.erase("fury")
	check(CharState.from_dict(fd, Balance.tables).fury == 0.0, "fúria: save antigo sem o campo = 0")
	fd["fury"] = 999.0
	check(CharState.from_dict(fd, Balance.tables).fury == CharState.FURY_MAX, "fúria: limitada a FURY_MAX ao carregar")

	# --- despacho por módulo da classe da arma, com fonte única de "pronta"
	for id in ItemDB.ABILITIES:
		check(Game.ability_implemented(id) == ItemDB.ABILITIES[id].ready, "fonte única de 'pronta' (%s)" % id)
	check(player._ab_module("sword_whirl") == SwordAbilities and player._ab_module("bow_gale") == BowAbilities
		and player._ab_module("meteor_rain") == StaffAbilities, "despacho por módulo da classe")
	check(player._ab_module("meteor_rain_end") == StaffAbilities and player._ab_module("bow_gale_fire") == BowAbilities
		and player._ab_module("sword_charge") == SwordAbilities, "kind de evento remoto roteia por prefixo")

	Game.level = lvl_f
	Game.fury = 0.0
	Game.hp = hp_f

	# --- magia
	var mp0 := Game.mp
	var fb_watch := _watch_spawns()
	player.cast("fireball")
	# a bola de fogo sai depois do movimento de apontar
	await wait_until(func(): return "fireball" in fb_watch[0])
	_stop_spawn_watch(fb_watch)
	check(Game.mp < mp0, "bola de fogo gasta mana")
	check("fireball" in fb_watch[0], "projétil de bola de fogo criado")
	# nível 1 de fato: uma resposta do Econ (XP de um abate) pode ter devolvido outro nível no meio do teste
	var lvl_sp := Game.level
	Game.level = 1
	player.use_slot(2)   # Nova Gélida (nível 3) bloqueada no nível 1
	check(player.cooldowns.frost_nova == 0.0, "slot 2 respeita o nível")
	Game.level = lvl_sp
	equip_any(kit_weapon)   # restaura a arma inicial

	# --- completar missão e subir de nível
	for i in 4:
		var s := _nearest("slime", "campos_norte")
		s.take_damage(9999, player.global_position, false)
	check(Game.quest_state("slimes") == "ready", "missão pronta após 5 slimes")
	var xp_before := Game.xp + Game.level * 100000
	Game.complete_quest("slimes")
	check(Game.quest_state("slimes") == "done" and Game.xp + Game.level * 100000 > xp_before, "recompensa de XP entregue")
	check(Game.level >= 2, "subiu para o nível %d" % Game.level)
	check(Game.count_item("health_potion") >= 6, "poções de recompensa recebidas")
	Game.spend_point("str")
	check(Game.attributes.str == 6, "ponto de atributo gasto em força")

	# --- inventário / equipamento / loja
	world._open_menu(0)
	await wait(0.1)
	check(world.modal != null, "menu de inventário abre")
	world.modal._close()
	await wait(0.05)
	world.open_shop()
	await wait(0.05)
	var g := Game.gold
	Game.buy("iron_sword")
	check(Game.count_item("iron_sword") == 1 and Game.gold == g - 60, "comprou espada de ferro (%d, ouro %d -> %d)" % [Game.count_item("iron_sword"), g, Game.gold])
	equip_any("iron_sword", true)
	check(Game.equipment.weapon == "iron_sword" and Game.count_item("azure_edge") == 1, "equipou espada de ferro (%s, gume %d)" % [Game.equipment.weapon, Game.count_item("azure_edge")])
	Game.sell("azure_edge")
	check(Game.count_item("azure_edge") == 0, "vendeu o gume celeste")
	world.modal._close()
	await wait(0.05)

	# --- novas armas, armaduras e equipamentos
	await _test_gear()
	await _test_female_body()

	# --- persistência no save solo: cada pedido já foi gravado; recriar o serviço local devolve o mesmo personagem
	var saved_gold := Game.gold
	var saved_lvl := Game.level
	var saved_inv: Array = Game.inventory.duplicate(true)
	var saved_pos := player.global_position
	check(Econ.quick_save(saved_pos, 0.0), "F5 offline grava vida e posição")
	Game.gold = 1   # bagunça o espelho: o estado tem que voltar do banco
	Game.level = 1
	Game.inventory = []
	check(Econ.reload_solo(), "serviço local recriado a partir do save solo")
	check(Game.gold == saved_gold and Game.level == saved_lvl, "save solo guarda ouro e nível")
	check(Game.inventory == saved_inv, "save solo guarda a mochila (%d espaços)" % Game.inventory.size())
	check(Game.equipment.weapon == "iron_sword", "save solo guarda o equipamento")
	check(Game.equipment.head == "leather_cap" and Game.equipment.feet == "leather_boots", "save solo guarda cabeça e pés")
	Econ.quick_load()   # F9: recarrega do save solo e volta ao mundo
	await wait(0.6)
	world = get_tree().current_scene
	player = get_tree().get_first_node_in_group("player")
	check(player != null and Game.gold == saved_gold and player.global_position.distance_to(saved_pos) < 1.5,
		"F9 recarrega do save solo na posição salva")

	# --- missões goblin e chefe (as da história antes delas são feitas direto pelas regras)
	_story_to("goblins")
	Game.start_quest("goblins")
	for i in 4:
		_nearest("goblin", "toca_goblins").take_damage(9999, player.global_position, false)
	Game.complete_quest("goblins")
	check(Game.count_item("chain_mail") == 1, "cota de malha recebida")
	_story_to("goblin_king")
	Game.start_quest("goblin_king")
	await wait(0.1)
	var boss: Enemy = world.boss
	check(boss != null and is_instance_valid(boss), "chefe aparece ao aceitar a missão final")
	var goblins_before := _count("goblin")
	var enemies_before := get_tree().get_nodes_in_group("enemies")
	# 60% da vida já descontada a resistência ao físico do Rei Goblin (ElementRules)
	boss.take_damage(boss.max_hp * 0.6 / boss.element_mult("fisico"), boss.global_position + Vector3.FORWARD, false)
	await wait(0.2)
	check(boss.enraged and _count("goblin") == goblins_before + 2, "chefe enfurece e invoca 2 goblins")
	var minion_levels := []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.kind == "goblin" and not (e in enemies_before):
			minion_levels.append(e.level)
	check(boss.level > 0 and minion_levels.count(boss.level) >= 2,
		"goblins invocados no nível do chefe (%d): %s" % [boss.level, str(minion_levels)])
	boss.take_damage(99999, boss.global_position + Vector3.FORWARD, false)
	check(Game.quest_state("goblin_king") == "ready" and Game.flags.get("king_dead", false), "chefe derrotado")
	await _test_guild_travel()

	# --- IA ataca o jogador
	var gob := _nearest("goblin")
	player.global_position = gob.global_position + Vector3(0, 0.3, 1.0)
	var php := Game.hp
	await wait(3.0)
	check(Game.hp < php, "goblin causa dano ao jogador (%.0f -> %.0f)" % [php, Game.hp])

	# --- morte e renascimento
	player.invuln = 0
	player.take_damage(99999, player.global_position + Vector3.FORWARD)
	check(player.dead, "jogador morre")
	await wait(2.2)
	check(world.modal != null and get_tree().paused, "tela de morte aparece")
	var gold_dead := Game.gold
	world.modal._respawn()
	await wait(0.2)
	check(not player.dead and not get_tree().paused and Game.hp == Game.max_hp(), "renasce na vila")
	check(Game.gold == gold_dead - int(gold_dead * 0.1), "renascer custa 10%% do ouro (%d -> %d)" % [gold_dead, Game.gold])

	if _part() == "mundo":
		_finish()   # o resto (_test_sistemas) roda em outro job, na parte "sistemas"
		return
	await _test_sistemas()
	_finish()


## Segunda metade do mundo: cada teste monta o próprio cenário, então roda logo depois do kit (parte
## "sistemas", em paralelo com a parte "mundo" no CI) ou depois da primeira metade (teste inteiro).
func _test_sistemas() -> void:
	await _test_fx_epic()
	await _test_farm()
	await _test_gather()
	await _test_dungeons()
	await _test_enchant()
	await _test_enchant_effects()
	await _test_tecela_web()
	await _test_bocarrao_tongue()
	await _test_flor_rooted()
	await _test_espinheira()
	await _test_sentinela()
	await _test_arauto()
	await _test_forjador()
	await _test_enemy_detour()
	await _test_river()
	await _test_archer_pose()
	await _test_gold_goblin_world()
	if _part() == "" and Game.HORDE_ENABLED:
		await _test_survival()
	await _test_update()
	await _test_char_create()   # por último: troca o personagem solo por um novo, sem classe


## Parte pedida com --smoke-part=<mundo|sistemas|horda>; "" = o teste inteiro.
func _part() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-part="):
			return a.trim_prefix("--smoke-part=")
	return ""


func _finish() -> void:
	print("\n==== %s (%d falhas) ====" % ["OK" if fails == 0 else "FALHOU", fails])
	get_tree().quit(1 if fails > 0 else 0)


# ---------------------------------------------------------------- Efeitos épicos
## Flecha do Vendaval (ultimate do arco, slot 4): segurar 4 tensiona (carga 0..1 em 1,2 s), soltar dispara
## um raio de 40 m na mira que atravessa todos os inimigos da linha (cada um uma vez) e para em parede.
func _test_bow_gale() -> void:
	var lvl0: int = Game.level
	var fury0: float = Game.fury
	var weapon0: String = Game.equipment.weapon
	var pos0 := player.global_position
	var yaw0: float = player.cam_yaw.rotation.y
	var spring0: float = player.spring.spring_length
	var fov0: float = player.camera.fov
	equip_any("short_bow")
	await wait_until(func(): return player.dodge_timer <= 0.0 and not player.attacking and player.ability == "")
	# 4 slimes (os mais perto): 3 na linha da mira a 5/10/15 m e 1 a 6 m do lado da linha
	var gs: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.kind == "slime" and not e.dead and not e.is_boss:
			gs.append(e)
	gs.sort_custom(func(a, b): return a.global_position.distance_to(player.global_position) < b.global_position.distance_to(player.global_position))
	gs = gs.slice(0, 4)
	_targets(gs)
	check(gs.size() == 4, "Vendaval: 4 slimes para o teste (%d)" % gs.size())
	if gs.size() < 4:
		return
	var saved: Array = []
	for e in gs:
		saved.append([e, e.max_hp, e.global_position])
		e.max_hp = 100000.0
	# lugar aberto: casa do slime mais perto; gira a câmera até a mira ter 18 m livres
	var base: Vector3 = gs[0].home
	var grounded := func() -> bool: return player.is_on_floor()
	player.global_position = base + Vector3(0, 0.3, 0)
	player.velocity = Vector3.ZERO
	await wait_until(grounded)
	var dir := Vector3.ZERO
	for k in 12:
		player.cam_yaw.rotation.y = yaw0 + k * TAU / 12.0
		await wait(0.05)
		var d: Vector3 = BowAbilities._gale_dir(player)
		var o: Vector3 = player.global_position + Vector3.UP * BowAbilities.GALE_HEIGHT
		if BowAbilities._gale_length(player, o, d) >= 18.0:
			dir = d
			break
	check(dir != Vector3.ZERO and absf(dir.y) < 0.001, "Vendaval: mira horizontal com 18 m livres (%s)" % dir)
	var side := dir.cross(Vector3.UP).normalized()
	var place := func() -> void:
		var p0: Vector3 = player.global_position
		for i in 3:
			gs[i].global_position = p0 + dir * (5.0 * (i + 1)) + Vector3.UP * 0.3
		gs[3].global_position = p0 + dir * 10.0 + side * 6.0 + Vector3.UP * 0.3
		for e in gs:
			e.velocity = Vector3.ZERO
			e.stagger = 5.0   # parados até o tiro
			e.hp = e.max_hp
	var hps := func() -> Array:
		var out := []
		for e in gs:
			out.append(e.hp)
		return out
	var lines := func() -> int:
		var n := 0
		for c in world.get_children():
			if c is BowAbilities.GaleLine:
				n += 1
		return n
	_calm_bystanders(gs, base, 40.0, 20.0)   # monstros com nível batem mais: nenhum outro chega no meio da tensão
	place.call()
	await wait(0.3)
	place.call()
	var h0: Array = hps.call()

	# --- 1) segura, solta aos 0,6 s: os 3 da linha perdem vida, o de fora não; a fúria fica em 0
	Game.fury = 100.0
	Game.level = 8
	player.use_slot(4)
	check(player.ability == "bow_gale" and Game.fury == 0.0 and player.ability_slot == 4,
		"Vendaval começa, gasta a fúria e grava a tecla 4 (%s, %.0f, %d)" % [player.ability, Game.fury, player.ability_slot])
	check(not BowAbilities.can_dodge_cancel(player), "Vendaval: esquiva não cancela a tensão")
	await wait(0.3)
	var c03: float = player.ability_data.get("charge", -1.0)
	check(c03 > 0.15 and c03 < 0.4 and not player.ability_data.get("fired", false), "Vendaval: carga cresce com o tempo (%.2f aos 0,3 s)" % c03)
	check(Vector2(player.velocity.x, player.velocity.z).length() < 0.1, "Vendaval: parado na tensão (vel %s)" % player.velocity)
	check(player.camera.fov < fov0 - 0.5 and player.cam_back > 0.0, "Vendaval: câmera recua e fecha o FOV (%.1f, back %.2f)" % [player.camera.fov, player.cam_back])
	Game.stamina = Game.max_stamina()
	player._dodge_pressed(Vector3.ZERO)
	check(player.ability == "bow_gale" and player.dodge_timer <= 0.0, "Vendaval: esquiva ignorada na tensão")
	await wait_until(func(): return player.ability_t >= 0.6 or player.ability == "")
	BowAbilities.release(player)
	var fired1: bool = player.ability_data.get("fired", false)
	var ch1: float = player.ability_data.get("charge", -1.0)
	check(fired1 and absf(ch1 - 0.5) < 0.06, "Vendaval: soltar com carga >= 0,25 dispara na hora (carga %.2f)" % ch1)
	check(lines.call() >= 1, "Vendaval: o disparo cria a linha visual")
	# o raio nasce na ponta da flecha, à frente do corpo (antes saía do meio do peito: visto de lado, de dentro dele)
	var g_or: Vector3 = player.ability_data.get("origin", Vector3.ZERO)
	var g_out := Vector2(g_or.x - player.global_position.x, g_or.z - player.global_position.z).length()
	check(g_or.distance_to(player.weapon_tip()) < 0.35 and g_out > 0.35, "Vendaval: o raio sai da ponta da flecha, fora do corpo (%.2f m da ponta, %.2f m do eixo)" % [g_or.distance_to(player.weapon_tip()), g_out])
	check(absf(float(player.parts.get("aim_pitch", 9.0))) < 0.1, "Vendaval: o braço mira na horizontal, como o raio (%.2f)" % float(player.parts.get("aim_pitch", 9.0)))
	await wait_until(func(): return player.ability == "", 2.0)
	var h1: Array = hps.call()
	var want1: float = Game.melee_damage() * lerpf(BowAbilities.GALE_MULT_MIN, BowAbilities.GALE_MULT_MAX, ch1) * gs[0].element_mult("fisico")
	var line_ok := true
	for i in 3:
		line_ok = line_ok and absf((h0[i] - h1[i]) - want1) < 0.05
	check(line_ok, "Vendaval: os 3 slimes da linha (5/10/15 m) perdem melee x lerp(3,6,carga) uma vez (%.1f, %.1f, %.1f; esperado %.1f)"
		% [h0[0] - h1[0], h0[1] - h1[1], h0[2] - h1[2], want1])
	check(h1[3] == h0[3], "Vendaval: o slime fora da linha não perde vida")
	check(Game.fury == 0.0, "Vendaval: acertos da ultimate não recarregam a fúria (%.2f)" % Game.fury)
	check(is_equal_approx(Engine.time_scale, 1.0) and player.cam_back == 0.0 and absf(player.camera.fov - fov0) < 0.01,
		"Vendaval: fim restaura tempo, câmera e FOV (%.2f, %.2f, %.1f)" % [Engine.time_scale, player.cam_back, player.camera.fov])

	# --- 2) sem soltar: dispara sozinha com carga cheia em <= 1,4 s
	player.global_position = base + Vector3(0, 0.3, 0)
	player.velocity = Vector3.ZERO
	await wait_until(grounded)
	place.call()
	await wait(0.1)
	h0 = hps.call()
	Game.fury = 100.0
	Game.level = 8
	var t2 := Time.get_ticks_msec()
	player.use_slot(4)
	await wait_until(func(): return player.ability_data.get("fired", false) or player.ability == "", 2.0)
	var el2 := (Time.get_ticks_msec() - t2) / 1000.0
	var ch2: float = player.ability_data.get("charge", -1.0)
	check(player.ability_data.get("fired", false) and el2 <= 1.4 and is_equal_approx(ch2, 1.0),
		"Vendaval: sem soltar dispara sozinha com carga cheia (%.2f s, carga %.2f)" % [el2, ch2])
	await wait_until(func(): return player.ability == "", 2.0)
	var h2: Array = hps.call()
	var want2: float = Game.melee_damage() * BowAbilities.GALE_MULT_MAX * gs[0].element_mult("fisico")
	check(absf((h0[0] - h2[0]) - want2) < 0.05 and h2[2] < h0[2] and h2[3] == h0[3],
		"Vendaval: carga cheia = melee x6 (%.1f, esperado %.1f)" % [h0[0] - h2[0], want2])

	# --- 3) soltar cedo (carga < 0,25): continua tensionando até 0,25 e dispara
	player.global_position = base + Vector3(0, 0.3, 0)
	player.velocity = Vector3.ZERO
	await wait_until(grounded)
	place.call()
	await wait(0.1)
	Game.fury = 100.0
	Game.level = 8
	player.use_slot(4)
	await wait(0.05)
	BowAbilities.release(player)
	check(player.ability == "bow_gale" and not player.ability_data.get("fired", false), "Vendaval: soltar com carga < 0,25 não dispara na hora")
	await wait_until(func(): return player.ability_data.get("fired", false) or player.ability == "", 1.0)
	var ch3: float = player.ability_data.get("charge", -1.0)
	check(player.ability_data.get("fired", false) and absf(ch3 - BowAbilities.GALE_MIN) < 0.03,
		"Vendaval: dispara ao chegar a 0,25 (carga %.2f)" % ch3)
	await wait_until(func(): return player.ability == "", 2.0)

	# --- 4) morrer na tensão: não dispara, limpa o estado
	player.global_position = base + Vector3(0, 0.3, 0)
	player.velocity = Vector3.ZERO
	await wait_until(grounded)
	place.call()
	await wait(0.1)
	h0 = hps.call()
	var lines0: int = lines.call()
	Game.fury = 100.0
	Game.level = 8
	player.use_slot(4)
	await wait(0.4)
	check(player.ability == "bow_gale" and player.cam_back > 0.0, "Vendaval: tensionando antes de morrer")
	player._die()
	await wait(0.1)
	check(player.ability == "" and is_equal_approx(Engine.time_scale, 1.0) and player.cam_back == 0.0 and absf(player.camera.fov - fov0) < 0.01,
		"Vendaval: morrer na tensão limpa o estado (%s, %.2f, %.2f, %.1f)" % [player.ability, Engine.time_scale, player.cam_back, player.camera.fov])
	player.revive(player.global_position)
	await wait(1.5)
	check(hps.call() == h0 and lines.call() <= lines0, "Vendaval: morrer na tensão não dispara (nenhum slime ferido)")
	# a tela de morte abre 1,8 s depois de morrer, mesmo revivido: fecha sem a multa de ouro
	await wait(0.5)
	if world.modal != null:
		world.modal.queue_free()
		world.modal = null
	world._set_paused(false)
	check(not player.dead and absf(player.spring.spring_length - spring0) < 0.05, "Vendaval: câmera volta depois de morrer (%.2f)" % player.spring.spring_length)

	# --- 5) trocar de arma na tensão: encerra sem disparar
	place.call()
	await wait(0.1)
	h0 = hps.call()
	Game.fury = 100.0
	Game.level = 8
	player.use_slot(4)
	await wait(0.3)
	check(player.ability == "bow_gale", "Vendaval: tensionando antes de trocar de arma")
	equip_any("apprentice_staff")   # outra classe: Game.kit_changed -> end_ability
	await wait(0.1)
	check(player.ability == "" and player.cam_back == 0.0 and absf(player.camera.fov - fov0) < 0.01, "Vendaval: trocar de arma na tensão encerra")
	await wait(1.3)
	check(hps.call() == h0, "Vendaval: trocar de arma na tensão não dispara")
	equip_any("short_bow")
	await wait(0.1)

	# --- 6) réplica: "bow_gale" toca a tensão sem dano; "bow_gale_fire" toca o disparo e a linha, sem dano nem hit stop
	place.call()
	await wait(0.1)
	h0 = hps.call()
	var rp := Player.new()
	rp.remote = true
	world.add_child(rp)
	rp.global_position = player.global_position
	var lines6: int = lines.call()
	BowAbilities.play_remote(rp, "bow_gale", rp.global_position, Vector3.ZERO)
	check(rp.ability == "bow_gale" and not rp.ability_data.get("fired", false), "réplica do Vendaval começa a tensão")
	await wait(0.3)
	check(rp.ability == "bow_gale" and hps.call() == h0, "réplica tensionando não fere")
	var ro: Vector3 = player.global_position + Vector3.UP * BowAbilities.GALE_HEIGHT
	BowAbilities.play_remote(rp, "bow_gale_fire", ro, dir * 0.8)
	check(rp.ability == "bow_gale" and rp.ability_data.get("fired", false) and is_equal_approx(rp.ability_data.get("charge", 0.0), 0.8)
		and lines.call() > lines6, "réplica do Vendaval dispara a linha visual")
	var ts_ok := true
	for i in 6:
		await wait(0.03)
		ts_ok = ts_ok and is_equal_approx(Engine.time_scale, 1.0)
	check(ts_ok, "réplica do Vendaval não dá hit stop")
	await wait_until(func(): return rp.ability == "", 2.0)
	await wait(0.2)
	check(rp.ability == "" and hps.call() == h0, "réplica do Vendaval não fere (%s)" % [hps.call()])
	rp.queue_free()

	# restaura
	for s in saved:
		var e = s[0]
		if is_instance_valid(e):
			e.max_hp = s[1]
			e.hp = s[1]
			e.global_position = s[2]
			e.stagger = 0.0
			e.velocity = Vector3.ZERO
	player.cam_yaw.rotation.y = yaw0
	player.global_position = pos0
	player.velocity = Vector3.ZERO
	player.cooldowns.bow_gale = 0.0
	equip_any(weapon0)
	Game.fury = fury0
	Game.level = lvl0
	await wait(0.1)


## Chuva de Meteoros (ultimate do cajado, canalizada): soltar, tempo, esquiva, mirar no céu, morrer e réplica.
func _test_meteor_rain() -> void:
	var lvl0: int = Game.level
	var fury0: float = Game.fury
	var weapon0: String = Game.equipment.weapon
	var pos0 := player.global_position
	var yaw0: float = player.cam_yaw.rotation.y
	var pitch0: float = player.cam_pitch.rotation.x
	var spring0: float = player.spring.spring_length
	equip_any("apprentice_staff")
	await wait_until(func(): return player.dodge_timer <= 0.0 and not player.attacking and player.ability == "")
	var gs: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.kind == "slime" and not e.dead and not e.is_boss:
			gs.append(e)
	gs.sort_custom(func(a, b): return a.global_position.distance_to(player.global_position) < b.global_position.distance_to(player.global_position))
	gs = gs.slice(0, 4)
	_targets(gs)
	check(gs.size() == 4, "Meteoros: 4 slimes para o teste (%d)" % gs.size())
	if gs.size() < 4:
		return
	var saved: Array = []
	for e in gs:
		saved.append([e, e.max_hp, e.global_position])
		e.max_hp = 100000.0
	var base: Vector3 = gs[0].home
	var grounded := func() -> bool: return player.is_on_floor()
	player.global_position = base + Vector3(0, 0.3, 0)
	player.velocity = Vector3.ZERO
	await wait_until(grounded)
	await wait(0.1)
	var c: Vector3 = StaffAbilities._meteor_center(player)
	var flat_d := Vector2(c.x - player.global_position.x, c.z - player.global_position.z).length()
	check(flat_d <= StaffAbilities.METEOR_RANGE + 0.01, "Meteoros: centro da mira no chão a até 14 m (%.1f m)" % flat_d)
	# 3 slimes perto do centro (dentro da área) e 1 longe, do outro lado (fora do alcance de qualquer explosão)
	var place_at := func(ctr: Vector3) -> void:
		var away := Vector3(ctr.x - player.global_position.x, 0.0, ctr.z - player.global_position.z)
		away = away.normalized() if away.length() > 0.1 else player.facing()
		for i in 3:
			var a := i * TAU / 3.0
			gs[i].global_position = ctr + Vector3(cos(a), 0.0, sin(a)) * 0.8 + Vector3.UP * 0.4
		gs[3].global_position = ctr + away * (StaffAbilities.METEOR_AREA + StaffAbilities.METEOR_HIT_RADIUS + 4.0) + Vector3.UP * 0.4
		for e in gs:
			e.velocity = Vector3.ZERO
			e.stagger = 10.0   # parados até o primeiro acerto
			e.hp = e.max_hp
	var hps := func() -> Array:
		var out := []
		for e in gs:
			out.append(e.hp)
		return out
	var mets := func(caster: Node) -> Array:
		var out := []
		for n in world.get_children():
			if n is StaffAbilities.MeteorStrike and n.caster == caster and not n.is_queued_for_deletion():
				out.append(n)
		return out
	var airborne := func(caster: Node) -> int:
		var n := 0
		for m in mets.call(caster):
			if not m.landed:
				n += 1
		return n
	var area_hit := func(hb: Array) -> bool:
		for i in 3:
			if gs[i].hp < hb[i]:
				return true
		return false
	player.invuln = 60.0   # os slimes não interrompem nem enchem a fúria batendo no jogador
	place_at.call(c)
	await wait(0.3)
	place_at.call(c)
	var h0: Array = hps.call()

	# --- 1) segura, solta aos 2,0 s: os 3 da área perdem vida, o de fora não; fúria 0, mana igual
	Game.fury = 100.0
	Game.level = 8
	Game.mp = Game.max_mp()   # cheia (o máximo depende do nível): a regeneração não a muda
	var mp1: float = Game.mp
	var c1: Vector3 = StaffAbilities._meteor_center(player)   # com os slimes no lugar (a mira também acerta inimigos)
	player.use_slot(4)
	var d1: Dictionary = player.ability_data
	check(player.ability == "meteor_rain" and Game.fury == 0.0 and player.ability_slot == 4,
		"Meteoros começa, gasta a fúria e grava a tecla 4 (%s, %.0f, %d)" % [player.ability, Game.fury, player.ability_slot])
	check(d1.get("center", Vector3.INF).distance_to(c1) < 0.05, "Meteoros: área fixada no ponto mirado (%s vs %s)" % [d1.get("center"), c1])
	check(not StaffAbilities.can_dodge_cancel(player), "Meteoros: esquiva não cancela o preparo")
	Game.stamina = Game.max_stamina()
	player._dodge_pressed(Vector3.ZERO)
	check(player.ability == "meteor_rain" and player.dodge_timer <= 0.0, "Meteoros: esquiva no preparo é ignorada")
	await wait_until(func(): return player.ability_t >= 0.3 or player.ability == "")
	check(airborne.call(player) == 0, "Meteoros: nenhum meteoro no preparo")
	await wait_until(func(): return area_hit.call(h0) or player.ability == "", 3.0)
	check(area_hit.call(h0), "Meteoros: um slime da área perde vida (t %.2f)" % player.ability_t)
	check(player.ability == "meteor_rain" and StaffAbilities.can_dodge_cancel(player), "Meteoros: esquiva pode cancelar a canalização")
	check(Vector2(player.velocity.x, player.velocity.z).length() < 0.1, "Meteoros: parado canalizando (vel %s)" % player.velocity)
	var seed1: int = int(d1.get("seed", -1))
	var center1: Vector3 = d1.get("center", c)
	await wait_until(func(): return player.ability_t >= 2.0 or player.ability == "", 3.0)
	check(player.ability == "meteor_rain", "Meteoros: ainda canalizando aos 2,0 s")
	var targets1: Array = d1.get("targets", []).slice(0, 4)
	var n_rel: int = d1.get("targets", []).size()
	StaffAbilities.release(player)
	check(player.ability == "", "Meteoros: soltar a tecla encerra a canalização na hora")
	await wait(0.6)
	check(airborne.call(player) == 0 and d1.get("targets", []).size() == n_rel, "Meteoros: nenhum meteoro novo depois de soltar")
	var h1: Array = hps.call()
	check(h1[0] < h0[0] and h1[1] < h0[1] and h1[2] < h0[2], "Meteoros: os 3 slimes da área perdem vida (%.0f, %.0f, %.0f)"
		% [h0[0] - h1[0], h0[1] - h1[1], h0[2] - h1[2]])
	var want: float = (14.0 + Game.spell_power() * 1.6) * Game.damage_mult() * gs[0].element_mult("fogo")   # meteoro é fogo
	var ok_dmg := true
	for i in 3:
		var hits: float = (h0[i] - h1[i]) / want
		ok_dmg = ok_dmg and hits >= 0.99 and absf(hits - roundf(hits)) < 0.01
	check(ok_dmg, "Meteoros: cada explosão tira (14 + INT x 1,6) x dano (%.1f; perdas %.1f, %.1f, %.1f)"
		% [want, h0[0] - h1[0], h0[1] - h1[1], h0[2] - h1[2]])
	check(h1[3] == h0[3], "Meteoros: o slime fora da área não perde vida")
	check(Game.fury == 0.0, "Meteoros: acertos da ultimate não recarregam a fúria (%.2f)" % Game.fury)
	# se um abate devolveu o nível real no meio do teste, a mana máxima cai e a mana é cortada junto: isso
	# não é gasto. Gastar é ficar abaixo do que dava (a cheia de antes, limitada ao máximo de agora).
	check(Game.mp >= minf(mp1, Game.max_mp()) - 0.01, "Meteoros: não gasta mana (%.1f -> %.1f, máximo %.1f)"
		% [mp1, Game.mp, Game.max_mp()])
	check(is_equal_approx(Engine.time_scale, 1.0) and player.cam_back == 0.0, "Meteoros: fim restaura tempo e câmera")

	# --- soltar no preparo (um toque na tecla): fica guardado; a chuva abre no fim do preparo, canaliza
	# METEOR_TAP_MIN s e termina sozinha (a ultimate não se desperdiça)
	place_at.call(c)
	await wait(0.1)
	Game.fury = 100.0
	Game.level = 8
	player.use_slot(4)
	await wait_until(func(): return player.ability_t >= 0.2 or player.ability == "")
	check(player.ability == "meteor_rain" and player.ability_t < StaffAbilities.METEOR_WINDUP, "Meteoros: no preparo antes de soltar")
	var dw: Dictionary = player.ability_data
	StaffAbilities.release(player)
	check(player.ability == "meteor_rain" and Game.fury == 0.0, "Meteoros: soltar no preparo não encerra (fica guardado)")
	var tap_t := [0.0]
	await wait_until(func():
		if player.ability == "meteor_rain":
			tap_t[0] = player.ability_t
		return player.ability == "", 3.0)
	var tap_end: float = StaffAbilities.METEOR_WINDUP + StaffAbilities.METEOR_TAP_MIN
	check(player.ability == "" and tap_t[0] >= tap_end - 0.1 and tap_t[0] <= tap_end + 0.05 and dw.get("targets", []).size() >= 4,
		"Meteoros: um toque abre a chuva e ela dura o mínimo (fim aos %.2f s, %d meteoros)" % [tap_t[0], dw.get("targets", []).size()])
	await wait(0.6)
	check(airborne.call(player) == 0, "Meteoros: depois do toque não nasce meteoro novo")
	player.cooldowns.meteor_rain = 0.0

	# --- 2) sem soltar: termina sozinha em <= 4,6 s
	place_at.call(c)
	await wait(0.1)
	Game.fury = 100.0
	Game.level = 8
	player.use_slot(4)
	var last_t := [0.0]
	await wait_until(func():
		if player.ability == "meteor_rain":
			last_t[0] = player.ability_t
		return player.ability == "", 6.0)
	check(player.ability == "" and last_t[0] <= 4.6 and last_t[0] >= 4.0,
		"Meteoros: sem soltar termina sozinha aos 4,5 s (último t %.2f)" % last_t[0])
	await wait(0.6)
	check(airborne.call(player) == 0, "Meteoros: os últimos meteoros caem depois do fim")

	# --- esquiva na canalização: encerra; os meteoros no ar ainda caem e ferem
	place_at.call(c)
	await wait(0.1)
	Game.fury = 100.0
	Game.level = 8
	player.use_slot(4)
	var aimed := [null, null]   # [meteoro no ar, slime perto do alvo dele]
	await wait_until(func():
		if player.ability != "meteor_rain":
			return true
		for m in mets.call(player):
			if m.landed or m.age() > StaffAbilities.METEOR_FALL * 0.5:
				continue
			for i in 3:
				var dd := Vector2(m.target.x - gs[i].global_position.x, m.target.z - gs[i].global_position.z).length()
				if dd < 1.0:
					aimed[0] = m
					aimed[1] = gs[i]
					return true
		return false, 4.0)
	check(aimed[0] != null and player.ability == "meteor_rain", "Meteoros: meteoro no ar sobre um slime antes da esquiva")
	if aimed[0] != null:
		var hd: float = aimed[1].hp
		Game.stamina = Game.max_stamina()
		player._dodge_pressed(Vector3.ZERO)
		check(player.ability == "" and player.dodge_timer > 0.0, "Meteoros: esquiva encerra a canalização")
		check(is_instance_valid(aimed[0]) and not aimed[0].is_queued_for_deletion() and not aimed[0].landed,
			"Meteoros: depois da esquiva o meteoro no ar continua caindo")
		await wait(0.7)
		check(aimed[1].hp < hd, "Meteoros: meteoro no ar fere depois da esquiva (%.0f -> %.0f)" % [hd, aimed[1].hp])
		check(airborne.call(player) == 0, "Meteoros: nenhum meteoro novo depois da esquiva")
	await wait_until(func(): return player.dodge_timer <= 0.0)

	# --- 3) mirar no céu: centro a <= 14 m; 4) morrer no meio: meteoros no ar somem sem dano
	player.cam_pitch.rotation.x = 0.6
	await wait(0.1)
	var cs: Vector3 = StaffAbilities._meteor_center(player)
	var sd := Vector2(cs.x - player.global_position.x, cs.z - player.global_position.z).length()
	check(sd <= StaffAbilities.METEOR_RANGE + 0.01 and sd >= StaffAbilities.METEOR_RANGE - 0.5 and absf(cs.y - player.global_position.y) < 6.0,
		"Meteoros: mirar no céu põe a área no chão a 14 m (%.1f m, dy %.1f)" % [sd, cs.y - player.global_position.y])
	place_at.call(cs)
	await wait(0.1)
	Game.fury = 100.0
	Game.level = 8
	player.use_slot(4)
	var c4: Vector3 = player.ability_data.get("center", Vector3.INF)
	check(Vector2(c4.x - player.global_position.x, c4.z - player.global_position.z).length() <= StaffAbilities.METEOR_RANGE + 0.01,
		"Meteoros: mirando no céu a área começa a até 14 m")
	await wait_until(func(): return player.ability == "" or (player.ability_t > StaffAbilities.METEOR_WINDUP + 0.3 and airborne.call(player) >= 1), 3.0)
	check(player.ability == "meteor_rain" and airborne.call(player) >= 1, "Meteoros: meteoros no ar antes de morrer")
	player._die()
	await get_tree().process_frame
	check(player.ability == "" and airborne.call(player) == 0 and mets.call(player).is_empty() and is_equal_approx(Engine.time_scale, 1.0),
		"Meteoros: morrer remove os meteoros no ar (%d) e restaura o tempo (%.2f)" % [mets.call(player).size(), Engine.time_scale])
	var h4b: Array = hps.call()
	player.revive(player.global_position)
	await wait(0.8)
	check(hps.call() == h4b, "Meteoros: nenhum dano depois de morrer")
	# a tela de morte abre 1,8 s depois de morrer, mesmo revivido: fecha sem a multa de ouro
	await wait_until(func(): return world.modal != null, 3.0)
	if world.modal != null:
		world.modal.queue_free()
		world.modal = null
	world._set_paused(false)
	check(not player.dead and player.cam_back == 0.0, "Meteoros: revive sem resto da habilidade")
	player.cam_pitch.rotation.x = pitch0

	# --- 5) réplica: mesma semente = mesmos pontos de impacto; visual sem dano; para em "meteor_rain_end"
	place_at.call(c)
	await wait(0.1)
	var h5: Array = hps.call()
	var rp := Player.new()
	rp.remote = true
	world.add_child(rp)
	rp.global_position = player.global_position
	StaffAbilities.play_remote(rp, "meteor_rain", center1, Vector3(seed1, 0, 0))
	check(rp.ability == "meteor_rain", "réplica da Chuva de Meteoros começa")
	await wait_until(func(): return rp.ability_data.get("targets", []).size() >= 4 or rp.ability == "", 3.0)
	var rt: Array = rp.ability_data.get("targets", []).slice(0, 4)
	var same := rt.size() == 4 and targets1.size() == 4
	for i in mini(rt.size(), targets1.size()):
		same = same and rt[i].distance_to(targets1[i]) < 0.01
	check(same, "réplica: a semente reproduz os mesmos pontos de impacto (%s vs %s)" % [rt, targets1])
	await wait_until(func(): return rp.ability == "" or rp.ability_data.get("targets", []).size() >= 8, 3.0)
	check(rp.ability == "meteor_rain" and airborne.call(rp) >= 1 and hps.call() == h5, "réplica da Chuva de Meteoros cai e não fere (%s)" % [hps.call()])
	StaffAbilities.play_remote(rp, "meteor_rain_end", c, Vector3.ZERO)
	check(rp.ability == "", "réplica: 'meteor_rain_end' encerra a chuva")
	await wait(0.6)
	check(airborne.call(rp) == 0 and hps.call() == h5, "réplica: nenhum meteoro novo depois do fim e nenhum dano")
	# o estado de rede sem a flag de habilidade (sem morte) encerra macio: os meteoros no ar ainda caem
	StaffAbilities.play_remote(rp, "meteor_rain", center1, Vector3(seed1, 0, 0))
	await wait_until(func(): return airborne.call(rp) >= 1 or rp.ability == "", 3.0)
	var rp_air: Array = []
	for m in mets.call(rp):
		if not m.landed:
			rp_air.append(m)
	rp.apply_net_state(rp.global_position, 0.0, Vector3.ZERO, 0, 0, 0.0)
	await get_tree().process_frame
	var still := 0
	for m in rp_air:
		if is_instance_valid(m) and not m.is_queued_for_deletion():
			still += 1
	check(rp.ability == "" and rp_air.size() >= 1 and still == rp_air.size(),
		"réplica: perder a flag encerra macio, os meteoros no ar continuam (%d de %d)" % [still, rp_air.size()])
	await wait(0.8)
	rp.queue_free()

	# --- réplica removida no meio da chuva (o jogador saiu ou trocou de zona): nada fica órfão na cena
	await wait(1.0)
	var budget0: int = FXEpic._active_amount
	var skies := func() -> int:
		var n := 0
		for x in world.get_children():
			if x.has_node("Dark") and x.has_node("Glow") and not x.is_queued_for_deletion():
				n += 1
		return n
	var sky0: int = skies.call()
	var rq := Player.new()
	rq.remote = true
	world.add_child(rq)
	rq.global_position = player.global_position
	StaffAbilities.play_remote(rq, "meteor_rain", center1, Vector3(seed1, 0, 0))
	await wait_until(func(): return rq.ability_t >= StaffAbilities.METEOR_WINDUP + 0.6 or rq.ability == "", 3.0)
	check(rq.ability == "meteor_rain" and skies.call() == sky0 + 1, "réplica removida: céu escuro no ar antes de sair (%d)" % skies.call())
	rq.queue_free()
	for i in 3:
		await get_tree().process_frame
	var live_mets := 0
	for x in world.get_children():
		if x is StaffAbilities.MeteorStrike and not x.is_queued_for_deletion():
			live_mets += 1
	check(skies.call() == sky0 and live_mets == 0, "réplica removida: céu, redemoinho e meteoros somem com ela (%d céus, %d meteoros)" % [skies.call(), live_mets])
	await wait(1.2)   # as explosões que já tinham começado terminam a vida
	check(FXEpic._active_amount <= budget0, "réplica removida: o orçamento de partículas volta (%d -> %d)" % [budget0, FXEpic._active_amount])

	# --- 6) encosta de montanha: de pé na encosta do Pico do sudoeste, mirando no céu para fora (para a
	# planície lá embaixo). O centro e cada ponto de impacto ficam no chão de verdade (um raio de cima a
	# baixo no mesmo x, z), não enterrados nem flutuando na altura do jogador.
	var top_ground := func(x: float, z: float) -> float:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 300.0, z), Vector3(x, -100.0, z), StaffAbilities.METEOR_GROUND_MASK)
		var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(q)
		return hit.position.y if not hit.is_empty() else -999.0
	var m0: Vector4 = world.maps["vila"].mountain_data()[0]   # o primeiro morro da cena do vale
	var pk := Vector3(m0.x, 0.0, m0.y)
	var out := Vector3(-pk.x, 0.0, -pk.z).normalized()   # do pico para o meio do mapa
	var best_r := 0.0
	var best_drop := -1.0
	for r in range(4, 36):
		var a: Vector3 = pk + out * float(r)
		var b2: Vector3 = a + out * StaffAbilities.METEOR_RANGE
		var drop: float = top_ground.call(a.x, a.z) - top_ground.call(b2.x, b2.z)
		if drop > best_drop:
			best_drop = drop
			best_r = float(r)
	var flank: Vector3 = pk + out * best_r
	# o flanco inteiro acima de 10 m passa de 45° (o floor_max_angle do jogador): ali is_on_floor() nunca
	# fica verdadeiro e o jogador escorrega encosta abaixo (já caiu de 12,6 para 6,9 m antes da checagem).
	# O teste prende o jogador no ponto (_pin, ver _physics_process) até o fim desta parte.
	_pin = Vector3(flank.x, top_ground.call(flank.x, flank.z) + 0.05, flank.z)
	player.global_position = _pin
	player.velocity = Vector3.ZERO
	player._snap_visuals()
	await wait(0.2)
	player.cam_yaw.rotation.y = atan2(-out.x, -out.z)   # frente da câmera (-Z) para fora do pico
	var pf: Vector3 = player.global_position
	check(pf.y > 10.0, "Meteoros: jogador no alto da encosta (y %.1f)" % pf.y)
	# no céu (o ponto vai a 14 m) e para baixo, na planície distante (o raio acerta o chão bem além dos
	# 14 m e o ponto a 14 m ainda está no meio da encosta, muito acima do acerto)
	for pitch in [0.6, -0.5]:
		player.cam_pitch.rotation.x = pitch
		await wait(0.15)
		var aim: Vector3 = player.aim_point()
		var cm: Vector3 = StaffAbilities._meteor_center(player)
		var cm_ref: float = top_ground.call(cm.x, cm.z)
		var pn: Vector3 = player.global_position   # (no topo o jogador pode escorregar um pouco)
		check(absf(cm.y - cm_ref) < 0.05 and Vector2(cm.x - pn.x, cm.z - pn.z).length() <= StaffAbilities.METEOR_RANGE + 0.01,
			"Meteoros: na encosta (pitch %.1f) o centro fica no chão (y %.2f, chão %.2f, jogador %.1f, mira em y %.1f a %.0f m)"
			% [pitch, cm.y, cm_ref, pf.y, aim.y, Vector2(aim.x - pf.x, aim.z - pf.z).length()])
	Game.fury = 100.0
	Game.level = 8
	player.use_slot(4)
	await wait_until(func(): return player.ability_data.get("targets", []).size() >= 6 or player.ability == "", 3.0)
	var on_ground := 0
	var tg: Array = player.ability_data.get("targets", [])
	for t in tg:
		if absf(t.y - top_ground.call(t.x, t.z)) < 0.05:
			on_ground += 1
	check(tg.size() >= 6 and on_ground == tg.size(), "Meteoros: na encosta os meteoros caem no chão (%d de %d)" % [on_ground, tg.size()])
	player.end_ability()
	player.cooldowns.meteor_rain = 0.0

	_pin = null
	# restaura
	for s in saved:
		var e = s[0]
		if is_instance_valid(e):
			e.max_hp = s[1]
			e.hp = s[1]
			e.global_position = s[2]
			e.stagger = 0.0
			e.velocity = Vector3.ZERO
	player.cam_yaw.rotation.y = yaw0
	player.cam_pitch.rotation.x = pitch0
	player.global_position = pos0
	player.velocity = Vector3.ZERO
	player.invuln = 0.0
	player.cooldowns.meteor_rain = 0.0
	equip_any(weapon0)
	Game.fury = fury0
	Game.level = lvl0
	await wait(0.3)
	check(absf(player.spring.spring_length - spring0) < 0.3, "Meteoros: câmera de volta (%.2f)" % player.spring.spring_length)


func _test_fx_epic() -> void:
	var p := player.global_position
	var n0 := get_tree().current_scene.get_child_count()
	FXEpic.glow_burst(p, Color.ORANGE)
	FXEpic.sparks(p, Vector3.UP, Color.YELLOW)
	FXEpic.smoke(p)
	FXEpic.flash(p, Color.ORANGE)
	FXEpic.ground_mark(p, Color.BLACK, 2.0, 1.0)
	FXEpic.trail(player.model, Color.ORANGE)
	check(get_tree().current_scene.get_child_count() >= n0 + 6, "efeitos épicos criados")
	FXEpic.hit_stop(0.05)
	FXEpic.hit_stop(0.05)
	check(Engine.time_scale >= 0.05 and Engine.time_scale < 1.0, "hit stop ativo (%.2f)" % Engine.time_scale)
	# espera pela condição, não 0,3 s fixos: na parte "sistemas" este é o primeiro teste depois de carregar
	# o mundo e o quadro dos efeitos novos (shaders compilando) passa de 0,3 s
	await wait_until(func() -> bool: return is_equal_approx(Engine.time_scale, 1.0), 2.0)
	check(is_equal_approx(Engine.time_scale, 1.0), "hit stop volta para 1.0")
	# perder o guarda no meio do hit stop também restaura o tempo
	FXEpic.hit_stop(5.0)
	check(Engine.time_scale < 1.0, "hit stop longo ativo")
	FXEpic._hs_guard.free()
	check(is_equal_approx(Engine.time_scale, 1.0), "guarda liberado cedo restaura o tempo")
	FXEpic.hit_stop(0.05)
	await wait_until(func() -> bool: return is_equal_approx(Engine.time_scale, 1.0), 2.0)
	check(is_equal_approx(Engine.time_scale, 1.0), "hit stop volta para 1.0 de novo")
	await wait(2.0)
	check(get_tree().current_scene.get_child_count() <= n0 + 1, "efeitos épicos se liberam")
	check(FXEpic._active_amount == 0, "orçamento de partículas devolvido (%d)" % FXEpic._active_amount)
	# liberar um emissor antes da hora também devolve o orçamento
	FXEpic.glow_burst(p, Color.ORANGE, 40)
	check(FXEpic._active_amount == 40, "orçamento reservado (%d)" % FXEpic._active_amount)
	get_tree().current_scene.get_child(get_tree().current_scene.get_child_count() - 1).free()
	check(FXEpic._active_amount == 0, "emissor liberado cedo devolve o orçamento (%d)" % FXEpic._active_amount)


# ---------------------------------------------------------------- Bram e Mira
func _test_elder(elder: Elder) -> void:
	check(elder != null, "Ancião Bram é um Elder")
	if elder == null:
		return
	var back := player.global_position
	player.global_position = elder.global_position + Vector3(0, 0.2, 1.5)
	await wait(0.2)
	var ap := elder.anim
	check(elder.state == Elder.State.IDLE and ap.current_animation == elder.clip("idle"),
		"Bram começa parado (%s, %s)" % [Elder.State.keys()[elder.state], ap.current_animation])
	var staff := elder.model.find_child("Staff", true, false)
	check(staff != null and staff.get_parent() is BoneAttachment3D and staff.get_parent().bone_name == "LeftHand",
		"cajado do Bram preso à mão esquerda")
	# fala com ele: o diálogo abre na hora e ele se anima; depois conversa, animando com o jogo pausado
	elder.interact(player)
	check(world.modal != null and elder.state == Elder.State.EXCITED and ap.current_animation == elder.clip("excited"),
		"Bram se anima ao abrir o diálogo (%s, %s)" % [Elder.State.keys()[elder.state], ap.current_animation])
	var p0 := ap.current_animation_position
	await wait(0.3)
	check(get_tree().paused and ap.current_animation_position != p0, "Bram anima a reação com o jogo pausado")
	await wait_until(func() -> bool: return elder.state == Elder.State.TALK, Elder.EXCITED_MAX + 0.5)
	# medido no relógio do próprio Bram (tempo do jogo), não no do sistema: máquina lenta não reprova
	var took := elder.excited_time
	check(elder.state == Elder.State.TALK and ap.current_animation == elder.clip("talk") and took <= Elder.EXCITED_MAX + 0.25,
		"Bram passa a conversar em até %.1f s (%.2f s, %s)" % [Elder.EXCITED_MAX, took, ap.current_animation])
	p0 = ap.current_animation_position
	await wait(0.3)
	check(get_tree().paused and ap.current_animation_position != p0, "Bram conversa animando com o jogo pausado")
	world.modal._choose(Callable())
	await wait(0.1)
	check(elder.state == Elder.State.IDLE and not get_tree().paused and elder.process_mode == Node.PROCESS_MODE_INHERIT,
		"Bram volta a ficar parado após o diálogo (%s)" % Elder.State.keys()[elder.state])
	# fecha durante a reação: volta ao parado e não fica preso em excited/talk
	elder.interact(player)
	await wait(0.3)
	check(elder.state == Elder.State.EXCITED, "Bram se anima de novo a cada conversa")
	world.modal._choose(Callable())
	await wait(0.1)
	check(elder.state == Elder.State.IDLE and ap.current_animation == elder.clip("idle") and elder.process_mode == Node.PROCESS_MODE_INHERIT,
		"fechar o diálogo durante a reação volta o Bram ao parado (%s, %s)" % [Elder.State.keys()[elder.state], ap.current_animation])
	await wait(Elder.EXCITED_MAX)
	check(elder.state == Elder.State.IDLE and ap.current_animation == elder.clip("idle"), "Bram não volta sozinho a conversar")
	player.global_position = back


func _test_merchant() -> void:
	var mira := _interactable("merchant") as Merchant
	check(mira != null, "Mira é uma Merchant")
	if mira == null:
		return
	var back := player.global_position
	var ap := mira.anim
	# o teste do Bram deixa o jogador a ~10 m dela: começa de um chamado liberado
	mira.reset_call()
	var dir := Vector3(-1, 0, 1).normalized()   # para a praça, fora da frente dela (-X): ela tem que virar
	player.global_position = mira.global_position + dir * 20.0 + Vector3(0, 0.3, 0)
	var c0 := mira.calls
	await wait(1.0)
	check(mira.calls == c0 and mira.state == Merchant.State.IDLE, "Mira não chama com o jogador a 20 m")
	player.global_position = mira.global_position + dir * 10.0 + Vector3(0, 0.3, 0)
	await wait_until(func() -> bool: return mira.calls > c0, 1.0)
	check(mira.state == Merchant.State.CALL and mira.calls == c0 + 1 and ap.current_animation == mira.clip("call"),
		"Mira chama o jogador a 10 m (%s, %d chamados)" % [Merchant.State.keys()[mira.state], mira.calls - c0])
	await wait(1.0)
	var to := player.global_position - mira.global_position
	to.y = 0.0
	var off := rad_to_deg(mira.face_dir().angle_to(to.normalized()))
	check(off < 20.0, "Mira se vira para quem ela chama (%.0f°)" % off)
	await wait(4.0)
	check(mira.calls == c0 + 1, "Mira não chama de novo antes do intervalo (%d chamados em 5 s)" % (mira.calls - c0))
	check(mira.state == Merchant.State.IDLE and ap.current_animation == mira.clip("idle"), "Mira volta ao parado depois do chamado")
	await wait(4.0)
	check(mira.calls == c0 + 2, "Mira chama de novo depois do intervalo (%d chamados em 9 s)" % (mira.calls - c0))
	# conversa e loja
	player.global_position = mira.global_position + mira.face_dir() * 1.8 + Vector3(0, 0.3, 0)
	await wait(1.8)
	var c1 := mira.calls
	mira.interact(player)
	check(world.modal != null and mira.state == Merchant.State.TALK and ap.current_animation == mira.clip("talk"),
		"Mira conversa ao abrir o diálogo (%s)" % Merchant.State.keys()[mira.state])
	var p0 := ap.current_animation_position
	await wait(0.3)
	check(get_tree().paused and ap.current_animation_position != p0, "Mira anima a conversa com o jogo pausado")
	var pages: Array = world.modal.pages
	world.modal._choose(pages[0].choices[0].action)   # "Ver mercadorias"
	await wait(0.1)
	check(world.modal != null and world.modal.get("buy_grid") != null, "loja abre pelo diálogo da Mira")
	check(mira.state == Merchant.State.IDLE and mira.process_mode == Node.PROCESS_MODE_INHERIT,
		"Mira fica parada com a loja aberta (%s)" % Merchant.State.keys()[mira.state])
	world.modal._close()
	await wait(0.1)
	check(world.modal == null and not get_tree().paused and mira.calls == c1, "loja fecha; Mira não chama quem está perto")
	player.global_position = back


# ---------------------------------------------------------------- Ferreiro
func _test_blacksmith() -> void:
	var back := player.global_position
	var smith := _interactable("blacksmith") as Blacksmith
	check(smith != null and smith.state == Blacksmith.State.WORK, "ferreiro começa trabalhando")
	if smith == null:
		return
	# jogador longe: golpes acontecem mas o som não toca (fora de FAR_DIST)
	player.global_position = smith.global_position + Vector3(Sfx.FAR_DIST + 5.0, 0.3, 0)
	var s0 := smith.strikes
	# esvazia os slots 3D que já tocaram a bigorna: outros sons (inimigos perto do jogador) podem ocupar
	# slots à vontade, mas nenhum pode voltar a receber o som da bigorna enquanto o jogador está longe
	var clang: AudioStream = Sfx.streams["anvil"]
	for p3 in Sfx._players_3d:
		if p3.stream == clang:
			p3.stop()
			p3.stream = null
	# 4,0 s: cobre o pior caso de começar logo no início de uma pausa (work_pause do Mixamo 2,63 s + blend de
	# saída Blacksmith.PAUSE_BLEND 0,5 s + golpe a 0,43 s = 3,56 s)
	await wait(4.0)
	check(smith.strikes > s0, "ferreiro bate na bigorna (%d golpes)" % (smith.strikes - s0))
	var clangs := Sfx._players_3d.filter(func(p3: AudioStreamPlayer3D) -> bool: return p3.stream == clang).size()
	check(clangs == 0, "som do golpe não toca com o jogador longe (%d slots com a bigorna)" % clangs)
	# outro modal pausa o jogo (menu, inventário, loja, outro diálogo): a bigorna fica quieta
	smith._work()
	get_tree().paused = true
	var sp := smith.strikes
	await wait(1.5)   # mais que uma volta do work_hammer (1,2 s)
	check(smith.strikes == sp and smith.state == Blacksmith.State.WORK, "ferreiro para de martelar com o jogo pausado por outro modal (%d golpes)" % (smith.strikes - sp))
	get_tree().paused = false
	var wh: Animation = smith.anim.get_animation(smith.clip("work_hammer"))
	check(wh.find_track(smith.anim.get_node(smith.anim.root_node).get_path_to(smith), Animation.TYPE_METHOD) >= 0, "golpe injetado no clipe que o ferreiro toca (%s)" % smith.clip("work_hammer"))
	# chega perto: para e vira
	var ahead := smith.anvil.global_position - smith.global_position
	ahead.y = 0.0
	player.global_position = smith.anvil.global_position + ahead.normalized() * 2.0 + Vector3(0, 0.3, 0)
	await wait(0.6)
	check(smith.state == Blacksmith.State.IDLE, "ferreiro para quando o jogador chega")
	var s1 := smith.strikes
	smith._on_strike()   # o que a method track do work_hammer faria no blend de saída
	check(smith.strikes == s1, "golpe fora do trabalho é ignorado")
	# conversa: anima com o jogo pausado
	smith.interact(player)
	await wait(0.1)
	check(smith.state == Blacksmith.State.TALK and get_tree().paused, "ferreiro conversa com o jogo pausado")
	var ap: AnimationPlayer = smith.anim
	var p0 := ap.current_animation_position
	await wait(0.3)
	check(ap.current_animation_position != p0, "ferreiro continua animando durante o diálogo")
	world.modal._choose(Callable())
	await wait(0.1)
	check(smith.state == Blacksmith.State.IDLE and not get_tree().paused, "ferreiro volta a ouvir após o diálogo (estado %s, pausado %s)" % [Blacksmith.State.keys()[smith.state], get_tree().paused])
	# sai de perto: volta a martelar e vira para a bigorna
	player.global_position = smith.global_position + Vector3(Blacksmith.NEAR + 3.0, 0.3, 0)
	await wait(1.0)
	check(smith.state == Blacksmith.State.WORK, "ferreiro volta a trabalhar quando o jogador sai (estado %s)" % Blacksmith.State.keys()[smith.state])
	check(absf(angle_difference(smith.model.rotation.y, smith._base_yaw)) < 0.2, "ferreiro vira de volta para a bigorna")
	# clipes do Mixamo (biblioteca "mixamo"); o Mixamo não tinha martelar, então esse segue o provisório
	for c in ["idle", "talk", "work_pause"]:
		check(smith.clip(c) == "mixamo/" + c, "ferreiro usa o clipe do Mixamo: %s -> %s" % [c, smith.clip(c)])
	check(smith.clip("work_hammer") == "work_hammer", "martelar segue o clipe provisório (%s)" % smith.clip("work_hammer"))
	# o provisório não anima pernas/quadril: sem tracks de repouso, a pose do Mixamo (passo da pausa) ficaria
	# presa nas pernas quando ele volta a martelar
	var missing := 0
	for c in ["idle", "talk", "work_pause"]:
		var m: Animation = smith.anim.get_animation(smith.clip(c))
		for t in m.get_track_count():
			if wh.find_track(m.track_get_path(t), m.track_get_type(t)) < 0:
				missing += 1
	check(missing == 0, "martelar provisório cobre os ossos dos clipes do Mixamo (%d tracks faltando)" % missing)
	player.global_position = back


# ---------------------------------------------------------------- Dungeons
func _test_dungeons() -> void:
	var doors := {}
	for n in get_tree().get_nodes_in_group("interactable"):
		if n.get("npc_id") == "dungeon_door":
			doors[str(n.target)] = int(doors.get(str(n.target), 0)) + 1
	check(doors.get("out", 0) == 4 and doors.has("dg_bosque") and doors.has("dg_mina") and doors.has("dg_pico")
		and doors.has("dg_final"), "portas das 4 dungeons e as 4 saídas (%s)" % str(doors))
	var by_dg := {}
	var bosses := {}
	for e in get_tree().get_nodes_in_group("enemies"):
		var r := Regions.region_at(e.global_position)
		if Regions.is_dungeon(r):
			by_dg[r] = int(by_dg.get(r, 0)) + 1
			if e.is_boss:
				bosses[r] = true
	for d in Regions.DUNGEONS:
		check(int(by_dg.get(d, 0)) >= 14 and bosses.has(d), "%s com monstros (%d) e chefe" % [d, int(by_dg.get(d, 0))])
	var lv_ok := true
	for e in get_tree().get_nodes_in_group("enemies"):
		if Regions.region_at(e.global_position) == "dg_mina" and not e.is_boss and (e.level < 26 or e.level > 30):
			lv_ok = false
	check(lv_ok, "Galerias Profundas: monstros entre os níveis 26 e 30 (das salas)")
	var back := player.global_position
	var rank0 := str(Game.flags.get("rank", "D"))
	Game.flags["rank"] = "D"
	world.use_dungeon_door("dg_bosque")
	await wait(1.2)
	check(Regions.region_at(player.global_position) != "dg_bosque", "sem Rank C a porta do Covil recusa")
	Game.flags["rank"] = "C"
	world.use_dungeon_door("dg_bosque")
	await wait(1.4)
	check(Regions.region_at(player.global_position) == "dg_bosque", "com Rank C entra no Covil das Raízes")
	check(Regions.exit_point("dg_bosque").distance_to(player.global_position) < 3.0, "chega na porta de saída")
	# dentro da dungeon não há viagem paga (nem cocheiro nem mapa-mundi): é preciso sair primeiro
	var g_in := Game.gold
	check(world.travel_block_reason("vila", "map").contains("dungeon"), "teleporte do mapa recusado dentro da dungeon")
	check(not world.request_travel("vila", "map") and Game.gold == g_in, "dentro da dungeon não cobra nem viaja")
	world.use_dungeon_door("out")
	await wait(1.4)
	check(player.global_position.distance_to(Regions.door_point("dg_bosque")) < 3.0, "a saída leva de volta à porta no Bosque")
	# morrer lá dentro: volta na porta de fora
	player.global_position = Regions.arrive_point("dg_mina")
	await wait(0.1)
	world._respawn()
	await wait(0.2)
	check(player.global_position.distance_to(Regions.door_point("dg_mina")) < 3.0, "quem morre na dungeon volta na porta dela")
	# chefe da dungeon: só luta dentro da sala dele (arena) e perde o agro quando o jogador sai
	var king: Enemy = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.is_boss and Regions.region_at(e.global_position) == "dg_mina":
			king = e
	check(king != null and king.arena.size.x >= 30.0 and king.arena.size.y >= 24.0,
		"Rei Caído tem a sala grande como arena (%s)" % (str(king.arena) if king else "sem chefe"))
	if king != null:
		var o := Regions.DATA["dg_mina"].origin as Vector3
		var hp0: float = Game.hp
		player.global_position = o + Vector3(0, 0.3, -20.0)   # antecâmara, na frente do portão
		await wait(1.0)
		check(king.state in ["idle", "wander", "return"], "chefe não ataca quem está fora da sala (estado %s)" % king.state)   # "return": o Forjador anda devagar e ainda pode estar voltando para casa
		player.global_position = o + Vector3(16.0, 0.3, -36.0)   # dentro da sala, longe do alcance normal de agro
		await wait(0.6)
		check(king.state in ["chase", "attack"], "chefe persegue quem entra na sala (estado %s)" % king.state)
		player.global_position = o + Vector3(0, 0.3, -20.0)
		await wait(0.8)
		check(king.state in ["return", "idle", "wander"], "chefe perde o agro quando o jogador sai da sala (estado %s)" % king.state)
		Game.hp = hp0
		# só um chefe na sala, e o portal de volta só abre depois que ele cai
		var portal: Node = world.get_node_or_null("BossPortal_dg_mina")
		var n_boss := 0
		for e in get_tree().get_nodes_in_group("enemies"):
			if e.is_boss and king.arena.grow(2.0).has_point(Vector2(e.global_position.x, e.global_position.z)):
				n_boss += 1
		check(n_boss == 1, "um chefe só na sala (%d)" % n_boss)
		check(portal != null and not portal.is_open(), "portal de volta fechado com o chefe vivo")
		king.take_damage(999999, king.global_position + Vector3.FORWARD, false)
		await wait(2.2)
		check(portal != null and portal.is_open() and portal.visible, "chefe morto: o portal de volta abre na sala")
		if portal != null:
			player.global_position = portal.global_position + Vector3(0, 0.3, 1.5)
			portal.interact(player)
			await wait(1.6)
			check(player.global_position.distance_to(Regions.arrive_point("dg_mina")) < 3.0,
				"o portal leva de volta à entrada da dungeon")
	Game.flags["rank"] = rank0
	player.global_position = back
	await wait(0.2)


# ---------------------------------------------------------------- Profissões e craft
func _test_crafting() -> void:
	for st in ["forge", "leather", "alchemy"]:
		world.open_crafting(st)
		await wait(0.1)
		check(world.modal is CraftingUI and (world.modal as CraftingUI).recipe_count() > 5, "bancada %s abre com receitas" % st)
		world.modal._close()
		await wait(0.05)
	check(world.modal == null, "bancadas fechadas")
	var station_ok := false
	for n in get_tree().get_nodes_in_group("interactable"):
		if n.get("npc_id") == "station" and n.get("station") == "leather":
			station_ok = true
	check(station_ok, "Bancada de Couraria na vila")
	# essência (alquimia nível 1) e arco curto (couraria nível 1) com os materiais dados
	Econ.grant(100, 0, {"hide_t1": 10, "slime_gel": 2, "pine_log": 2}, "teste", true)   # 4 para as essências, 4 para o arco
	var axp0 := Game.prof_xp("alchemy")
	Game.craft("essence_t1", 2)
	await wait(0.1)
	check(Game.count_item("essence_t1") >= 2 and Game.prof_xp("alchemy") > axp0, "alquimia faz essência e dá XP")
	var bows0 := Game.count_item("short_bow") + Game.count_item("short_bow@fina") + Game.count_item("short_bow@obra")
	Game.craft("short_bow", 1)
	await wait(0.1)
	var bows1 := Game.count_item("short_bow") + Game.count_item("short_bow@fina") + Game.count_item("short_bow@obra")
	check(bows1 == bows0 + 1 and Game.prof_xp("leatherwork") > 0, "couraria faz o arco curto e dá XP")
	Game.craft("astral_blade", 1)
	await wait(0.1)
	check(Game.count_item("astral_blade") == 0, "receita de pergaminho e nível alto é recusada")
	# pela tela: a animação roda, espera a resposta e mostra o desfecho; clique fecha
	Econ.grant(20, 0, {"hide_t1": 2, "essence_t1": 1}, "teste", true)
	world.open_crafting("leather")
	await wait(0.1)
	var cui := world.modal as CraftingUI
	cui._select("leather_boots")
	var boots0 := Game.count_item("leather_boots") + Game.count_item("leather_boots@fina") + Game.count_item("leather_boots@obra")
	cui._craft(1)
	check(cui.anim.active() and cui.anim.phase == CraftAnim.WORK, "animação de craft começa trabalhando")
	await wait(CraftAnim.WORK_TIME + 0.6)
	var boots1 := Game.count_item("leather_boots") + Game.count_item("leather_boots@fina") + Game.count_item("leather_boots@obra")
	check(cui.anim.phase == CraftAnim.RESULT and boots1 == boots0 + 1, "animação mostra o desfecho e o item chegou")
	cui.anim.skip()
	check(not cui.anim.active(), "desfecho fecha no clique")
	cui._close()
	await wait(0.05)
	world._open_menu(4)
	await wait(0.1)
	check(world.modal != null, "aba Profissões abre")
	if world.modal != null:
		world.modal._close()
	await wait(0.05)


# ---------------------------------------------------------------- Coleta de ferro e cristal
func _test_gather() -> void:
	check(world.resource_nodes.size() == WorldHarvest.count(Balance.tables) and world.resource_nodes.size() > 600,
		"veios, cristais e todas as árvores dos quatro mapas viram nós (%d)" % world.resource_nodes.size())
	var scenery := 0
	for n in world.resource_nodes:
		if n.prop:
			scenery += 1
			if n._visual == null:
				check(false, "árvore %d do cenário sem modelo ligado" % n.node_id)
				break
	check(scenery > 600, "árvores do cenário ligadas ao modelo do mapa (%d)" % scenery)
	if world.resource_nodes.size() < 10:
		return
	var back := player.global_position
	var node = world.resource_nodes[0]
	check(node.node_id == 0 and node.alive, "veio 0 de pé")
	player.global_position = node.global_position + Vector3(1.6, 0.3, 0)
	await wait(0.3)
	check(GatherAction.nearest(player) == node, "F alcança o veio 0")
	var plan: Dictionary = node.gather_plan()
	check(plan.ok and plan.tool == "pickaxe_stone", "personagem novo minera com a picareta de pedra (%s)" % str(plan))
	check(int(plan.strikes) >= 2, "picareta de pedra pede vários golpes (%d)" % int(plan.strikes))
	var iron0 := Game.count_item("iron_ore")
	var mxp0 := Game.prof_xp("mining") + Game.prof_level("mining") * 100000
	# o veio 0 fica no Acampamento Goblin: goblins que já foram alvo de outra parte do teste não entram na calmaria
	# (_physics_process) e um golpe deles interrompe a coleta. Aqui todo monstro perto fica atordoado até o fim.
	_hush_around(node.global_position, 25.0, 3.0 + float(plan.swing) * (float(plan.strikes) + 3.0))
	player.start_gather(node)
	check(player.ability == GatherAction.ID, "F começa a coleta")
	await wait(0.3)
	check(player.gather_tool == "pickaxe_stone" and player.look.get("tool", false), "picareta na mão")
	await wait(0.8 + float(plan.swing) * 1.2)
	check(node.alive and node.progress > 0.0 and Game.count_item("iron_ore") == iron0,
		"primeiros golpes: barra sobe, veio de pé, nada ganho ainda (%.1f/%.1f)" % [node.progress, node.tough])
	var r0 := GatherAction.bar_ratio(player)
	await wait(float(plan.swing) * 0.3)
	var r1 := GatherAction.bar_ratio(player)
	check(r1 > r0 and r1 < 1.0, "barra da coleta sobe entre um golpe e outro (%.2f -> %.2f)" % [r0, r1])
	check(world.hud.gather_bar.value > 0.0 and not world.hud.gather_info.text.contains("golpe"),
		"HUD mostra a barra, sem contar golpes (%s)" % world.hud.gather_info.text)
	await wait(float(plan.swing) * float(plan.strikes) + 1.0)
	check(not node.alive, "um F só: bate sozinho até o veio ceder")
	check(Game.prof_xp("mining") + Game.prof_level("mining") * 100000 > mxp0, "coleta dá XP de Mineração (maestria)")
	check(Game.count_item("iron_ore") == iron0 + 3, "veio de ferro dá 3 minérios (%d → %d)" % [iron0, Game.count_item("iron_ore")])
	check(player.ability == "" and player.gather_tool == "", "terminou: guarda a ferramenta")
	await wait(0.1)
	check(not player.look.get("tool", false), "arma de volta na mão")
	Econ.gather_node(0, player.global_position)
	await wait(0.1)
	check(Game.count_item("iron_ore") == iron0 + 3, "veio esgotado não concede de novo")
	Econ.gather_node(1, Vector3.ZERO)
	await wait(0.1)
	check(Game.count_item("iron_ore") == iron0 + 3, "coleta de longe não concede")
	Econ.gather_node(999, player.global_position)
	await wait(0.1)
	check(Game.count_item("iron_ore") == iron0 + 3, "veio inexistente não concede")
	# andar interrompe e o progresso fica no nó
	var node1 = world.resource_nodes[1]
	player.global_position = node1.global_position + Vector3(1.2, 0.3, 0)
	await wait(0.3)
	player.start_gather(node1)
	await wait(0.5 + float(plan.swing))
	player.end_ability()
	var kept: float = node1.progress
	check(kept > 0.0 and node1.alive, "parou no meio: o progresso fica guardado (%.1f)" % kept)
	# cristal pede picareta de ferro
	var crystal = world.resource_nodes[6]
	player.global_position = crystal.global_position + Vector3(1.5, 0.3, 0)
	await wait(0.2)
	plan = crystal.gather_plan()
	check(not plan.ok and str(plan.msg).contains("Picareta de Ferro"), "cristal com picareta de pedra: avisa (%s)" % plan.msg)
	Econ.grant(0, 0, {"pickaxe_iron": 1}, "teste", true)
	await wait(0.1)
	check(not crystal.gather_plan().ok, "a de ferro só na mochila não conta: vale a equipada")
	Game.equip("pickaxe_iron")
	await wait(0.1)
	check(Game.equipment.get("pickaxe", "") == "pickaxe_iron", "picareta de ferro no espaço da picareta")
	plan = crystal.gather_plan()
	check(plan.ok and plan.tool == "pickaxe_iron", "com a de ferro equipada, usa a de ferro")
	var cr0 := Game.count_item("arcane_crystal")
	crystal.strike(player.global_position, crystal.tough)
	await wait(0.2)
	check(Game.count_item("arcane_crystal") == cr0 + 1, "cristal das Ruínas dá 1 cristal arcano")
	# veio de camada alta: sem o nível de Mineração F só avisa
	var silver = null
	for n in world.resource_nodes:
		if n.prof == "mining" and n.level > Game.prof_level("mining"):
			silver = n
			break
	check(silver != null, "há veio que pede mais Mineração")
	if silver != null:
		player.global_position = silver.global_position + Vector3(1.5, 0.3, 0)
		await wait(0.2)
		check(not silver.gather_plan().ok, "veio acima do nível: F recusa")
		player.start_gather(silver)
		check(player.ability == "", "não começa a bater")
	await _test_crafting()
	player.global_position = back
	await wait(0.2)


# ---------------------------------------------------------------- Encantamento de armas
func _test_enchant() -> void:
	# solo: o serviço local decide; o Game só espelha
	check(Game.equipment.weapon != "", "tem arma equipada para encantar (%s)" % Game.equipment.weapon)
	check(Game.weapon_enchant() == {"el": "", "lv": 0}, "arma começa sem encanto")
	var dmg_plain := Game.melee_damage()
	var ore0 := Game.count_item("iron_ore")      # pode haver minério da coleta de antes
	var ember0 := Game.count_item("ember_core")
	Econ.grant(50, 0, {"iron_ore": 4, "ember_core": 2}, "teste", true)
	var gold0 := Game.gold
	var changed := [0]
	var on_changed := func() -> void: changed[0] += 1
	Game.enchant_changed.connect(on_changed)
	Econ.request("enchant", ["fogo"])
	await wait(0.2)
	check(Game.weapon_enchant() == {"el": "fogo", "lv": 1}, "arma equipada encantada: fogo +1")
	check(changed[0] == 1, "enchant_changed avisou uma vez")
	check(absf(Game.melee_damage() - dmg_plain * 1.05) < 0.01, "encanto +1 dá +5%% de dano (%.2f → %.2f)" % [dmg_plain, Game.melee_damage()])
	check(Game.gold == gold0 - 50, "ouro gasto")
	check(Game.count_item("iron_ore") == ore0 and Game.count_item("ember_core") == ember0, "materiais gastos")
	# gasta o que sobrou da coleta para os testes abaixo partirem de "sem materiais"
	if Game.count_item("iron_ore") > 0:
		for i in Game.count_item("iron_ore"):
			Econ.request("sell", ["iron_ore"])
	await wait(0.1)
	Econ.request("enchant", ["fogo"])
	await wait(0.2)
	check(Game.weapon_enchant().lv == 1, "sem recursos não sobe")
	check(Game.enchant_text(Game.equipment.weapon) == "Fogo +1 · +5% de dano", "texto do encanto para a dica da arma")
	# o encanto é do tipo de arma: a versão com qualidade e afixo de craft usa o mesmo (como no servidor)
	var crafted: String = Game.equipment.weapon + "@fina~urso"
	check(Game.enchant_of(crafted) == {"el": "fogo", "lv": 1},
		"arma com qualidade/afixo usa o encanto do tipo base (%s)" % Game.enchant_of(crafted))
	Game.enchant_changed.disconnect(on_changed)

	# ---- painel do Doran (a arma está em fogo +1, sem materiais)
	var smith := _interactable("blacksmith") as Blacksmith
	var pages: Array = smith._build_dialogue()
	var choices: Array = pages[pages.size() - 1].get("choices", []).filter(
		func(c: Dictionary) -> bool: return c.text == "Encantar arma")
	check(choices.size() == 1, "Doran oferece encantar a arma")
	var wid: String = Game.equipment.weapon
	var wname: String = ItemDB.get_item(wid).name
	choices[0].action.call()
	var eui = world.modal
	check(eui != null and eui.get("selected") == "fogo", "painel abre no elemento atual da arma")
	if eui == null or eui.get("selected") == null:
		return
	check(wname in eui.status_text() and "+1" in eui.status_text(), "título mostra a arma e o nível")
	check(eui.enchant_button.disabled, "sem materiais: botão desligado")
	check("veios de ferro" in eui.status_text(), "painel diz onde achar o que falta")
	Econ.grant(120, 0, {"iron_ore": 8, "ember_core": 4}, "teste", true)
	await wait(0.2)
	check(not eui.enchant_button.disabled, "com materiais: botão ligado")
	var strikes0: int = smith.enchant_strikes
	eui.enchant_button.pressed.emit()
	check(eui.enchant_button.disabled, "pedido pendente: botão desligado (sem clique duplo)")
	eui.enchant_button.pressed.emit()
	await wait(0.3)
	check(Game.weapon_enchant() == {"el": "fogo", "lv": 2}, "um clique duplo sobe um nível só")
	check(smith.enchant_strikes == strikes0 + 1, "Doran bate na bigorna ao encantar")
	eui.select("gelo")
	var gold_row: Dictionary = eui.cost_rows()[0]
	check(gold_row.id == "" and gold_row.need == 100, "trocar de elemento mostra a taxa de troca")
	check("mantém +2" in eui.status_text(), "troca avisa que mantém o nível")
	# arma trocada com o painel aberto
	var other := "short_bow" if wid != "short_bow" else "apprentice_staff"
	if Game.count_item(other) == 0:
		Econ.grant(0, 0, {other: 1}, "teste", true)
	equip_any(other)
	await wait(0.3)
	check(ItemDB.get_item(other).name in eui.status_text(), "painel acompanha a troca de arma")
	check(eui.cost_rows()[0].need == 50, "arma nova: custo do +1")
	equip_any(wid)
	await wait(0.3)
	check(Game.weapon_enchant() == {"el": "fogo", "lv": 2}, "voltar à arma traz o encanto de volta")
	# sem arma equipada
	Econ.request("unequip", ["weapon"])
	await wait(0.3)
	check("Equipe uma arma" in eui.status_text() and eui.enchant_button.disabled, "sem arma: painel pede para equipar")
	equip_any(wid)
	await wait(0.3)
	# servidor antigo, sem a tabela
	var keep: Dictionary = Balance.tables.to_dict()
	var no_table := keep.duplicate(true)
	no_table.erase("enchant")
	Balance.apply(no_table)
	await wait(0.1)
	check("indisponível" in eui.status_text() and eui.enchant_button.disabled, "sem tabela enchant: painel avisa e não quebra")
	Balance.apply(keep)
	await wait(0.1)
	check(not ("indisponível" in eui.status_text()), "tabela de volta: painel volta ao normal")
	eui._close()
	await wait(0.1)
	check(world.modal == null, "painel fecha")


# ---------------------------------------------------------------- Bocarrão e Flor-faminta
## O Bocarrão de meia distância lança a língua e puxa o jogador para perto da boca.
func _test_bocarrao_tongue() -> void:
	var back := player.global_position
	var spot := Vector3(-105, 0.3, 40)
	player.global_position = spot
	var e := Enemy.new()
	e.kind = "bocarrao"
	world.add_child(e)
	e.global_position = spot + Vector3(0, 0, -5.5)
	e.home = e.global_position
	await wait(0.2)
	check(e.parts.get("Tongue") != null and e.parts.get("Jaw") != null, "Bocarrão: língua e queixo no modelo")
	var hp0: float = Game.hp
	var d0: float = Vector2(player.global_position.x - e.global_position.x, player.global_position.z - e.global_position.z).length()
	e.web_cd = 0.0
	e.attack_cd = 0.0
	e._set_state("chase")
	await wait_until(func(): return Game.hp < hp0, 4.0)
	check(Game.hp < hp0 and e.web_cd > 0.0, "Bocarrão: a língua acerta de longe e entra em recarga (%.0f -> %.0f)" % [hp0, Game.hp])
	await wait(0.25)
	var d1: float = Vector2(player.global_position.x - e.global_position.x, player.global_position.z - e.global_position.z).length()
	check(d1 < d0 - 0.4, "Bocarrão: a língua puxa o jogador para perto (%.1f m -> %.1f m)" % [d0, d1])
	e.queue_free()
	Game.hp = Game.max_hp()
	player.global_position = back
	await wait(0.1)


## Obstáculo de teste (como as árvores e pedras do mapa: StaticBody na camada 1). shape "cyl" = tronco.
func _obstacle(at: Vector3, shape: String, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	if shape == "cyl":
		var c := CylinderShape3D.new()
		c.radius = size.x
		c.height = size.y
		cs.shape = c
	else:
		var b := BoxShape3D.new()
		b.size = size
		cs.shape = b
	cs.position.y = size.y / 2.0
	body.add_child(cs)
	world.add_child(body)
	body.global_position = at
	return body


## Monstro com um tronco ou um muro bem no meio do caminho: contorna e chega no jogador (antes ficava
## empurrando o obstáculo para sempre).
func _test_enemy_detour() -> void:
	var back := player.global_position
	var spot := Vector3(56, 0.3, 66)   # longe dos cantos do vale (a Fonte Gelada fica no sudoeste)
	player.global_position = spot
	player.invuln = 99.0
	for case in [["cyl", Vector3(0.6, 3.0, 0.6)], ["box", Vector3(4.0, 2.5, 0.8)]]:
		var wall := _obstacle(spot + Vector3(0, -0.3, -3.6), case[0], case[1])
		var e := Enemy.new()
		e.kind = "goblin"
		world.add_child(e)
		e.global_position = spot + Vector3(0, 0, -7.5)
		e.home = e.global_position
		await wait(0.1)
		e._set_state("chase")
		var reached := await _until(func() -> bool:
			return Vector2(e.global_position.x - spot.x, e.global_position.z - spot.z).length() < e.data.reach + 0.3, 7.0)
		check(reached, "goblin contorna o %s no caminho (ficou a %.1f m)" % ["tronco" if case[0] == "cyl" else "muro",
			Vector2(e.global_position.x - spot.x, e.global_position.z - spot.z).length()])
		e.queue_free()
		wall.queue_free()
		await wait(0.1)
	player.invuln = 0.0
	Game.hp = Game.max_hp()
	player.global_position = back
	await wait(0.1)


## Rio do Vale: andando para o norte fora da ponte, a parede da margem segura o jogador antes da água; pela
## Estrada do Norte ele sobe na ponte e chega do outro lado sem cair.
func _test_river() -> void:
	var back := player.global_position
	player.invuln = 99.0
	var yaw0: float = player.cam_yaw.global_rotation.y
	player.cam_yaw.global_rotation.y = 0.0   # câmera olhando para -Z: "frente" é o norte
	for case in [[Vector3(20, 0.3, -17), false], [Vector3(0, 0.3, -17), true]]:
		player.global_position = case[0]
		player.velocity = Vector3.ZERO
		await wait(0.2)
		var low := 99.0
		Input.action_press("move_forward")
		for i in 50:
			await wait(0.1)
			low = minf(low, player.global_position.y)
		Input.action_release("move_forward")
		var z: float = player.global_position.z
		if case[1]:
			check(z < -40.0, "atravessa o rio pela ponte (chegou a z = %.1f)" % z)
			check(low > -0.2, "não afunda nem cai da ponte (y mínimo %.2f)" % low)
		else:
			check(z < -21.0 and z > -26.5, "a margem do rio segura o jogador fora da água (parou em z = %.1f)" % z)
	# no meio da ponte, pulando para o lado (leste e oeste): a parede invisível da mureta segura
	for side in [["move_right", 1.0], ["move_left", -1.0]]:
		player.global_position = Vector3(0, 1.6, -31)
		player.velocity = Vector3.ZERO
		await wait(0.3)
		Input.action_press(side[0])
		for i in 12:
			if player.is_on_floor():
				Input.action_press("jump")
			await wait(0.1)
			Input.action_release("jump")
		Input.action_release(side[0])
		await wait(0.4)
		var p: Vector3 = player.global_position
		check(absf(p.x) < 2.6 and p.y > 0.5, "pulando para %s a ponte segura o jogador (x %.2f, y %.2f)"
			% ["leste" if side[1] > 0 else "oeste", p.x, p.y])
	player.cam_yaw.global_rotation.y = yaw0
	player.invuln = 0.0
	player.global_position = back
	await wait(0.1)


## Arqueiro: o arco fica em pé na mão esquerda esticada para o alvo e a flecha encaixada aparece puxando; com
## um muro no meio não atira (anda de lado até abrir a linha) e, livre, atira e acerta.
func _test_archer_pose() -> void:
	var back := player.global_position
	var spot := Vector3(64, 0.3, 62)
	player.global_position = spot
	player.invuln = 99.0
	var arrows := preload("res://scripts/enemies/enemy_arrow.gd")
	var e := Enemy.new()
	e.kind = "goblin_arqueiro"
	world.add_child(e)
	e.global_position = spot + Vector3(0, 0, -9)
	e.home = e.global_position
	await wait(0.2)
	check(e.weapon == "bow" and e.parts.get("ElbowL") != null and not e._rig.is_empty(), "arqueiro: cotovelos e arco no modelo")
	e.attack_cd = 0.0
	e._set_state("chase")
	await wait_until(func(): return e.state == "attack" and e.attack_timer > 0.5, 4.0)
	var bow: Node3D = e.parts.Bow
	var upright: float = bow.global_basis.y.normalized().dot(Vector3.UP)
	var to_p := (player.global_position - bow.global_position) * Vector3(1, 0, 1)
	var arm_out: float = (bow.global_position - (e.parts.ArmL as Node3D).global_position).normalized().dot(to_p.normalized())
	check(upright > 0.85, "arqueiro: arco em pé ao puxar (%.2f)" % upright)
	check(arm_out > 0.7, "arqueiro: braço do arco esticado para o alvo (%.2f)" % arm_out)
	if e.parts.get("Nock") != null:
		check(e.parts.Nock.visible, "arqueiro: flecha encaixada enquanto puxa a corda")
	# muro entre os dois: não atira até sair de trás dele
	await wait(1.0)
	var wall := _obstacle(spot + Vector3(0, -0.3, -4.5), "box", Vector3(3.0, 3.0, 0.6))
	for c in world.get_children():
		if c.get_script() == arrows:
			c.queue_free()
	await wait(0.05)
	e.global_position = spot + Vector3(0, 0, -9)
	e.attack_cd = 0.0
	e._los_t = 0.0
	e._set_state("chase")
	var hidden_shot := await _until(func() -> bool:
		return _count_script(world, arrows) > 0 and absf(e.global_position.x - spot.x) < 1.2, 1.5)
	check(not hidden_shot, "arqueiro não atira com um muro na frente")
	var free := await _until(func() -> bool: return _count_script(world, arrows) > 0, 8.0)
	check(free, "arqueiro anda de lado, abre a linha e atira (x = %.1f)" % (e.global_position.x - spot.x))
	wall.queue_free()
	e.queue_free()
	player.invuln = 0.0
	Game.hp = Game.max_hp()
	player.global_position = back
	await wait(0.1)


## Goblin Dourado no mundo aberto: foge do jogador (antes corria para cima e só empurrava) e, longe demais
## do ponto dele, volta rodeando em vez de sumir no mapa.
func _test_gold_goblin_world() -> void:
	var back := player.global_position
	var spot := Vector3(64, 0.3, 62)
	player.global_position = spot
	player.invuln = 99.0
	var e := Enemy.new()
	e.kind = "goblin_dourado"
	e.level = 8
	world.add_child(e)
	e.global_position = spot + Vector3(0, 0, -5)
	e.home = e.global_position
	await wait(0.2)
	e._set_state("chase")
	await wait(1.5)
	var d := e.global_position.distance_to(player.global_position)
	check(d > 8.0, "Goblin Dourado foge do jogador no mundo (%.1f m)" % d)
	e.global_position = e.home + Vector3(0, 0, -(Enemy.FLEE_LEASH + 8.0))
	e.provoked = Enemy.PROVOKE_TIME
	e._set_state("chase")
	await wait(1.5)
	var from_home := e.global_position.distance_to(e.home)
	check(from_home < Enemy.FLEE_LEASH + 6.5, "Goblin Dourado volta para perto do ponto dele (%.1f m)" % from_home)
	e.queue_free()
	player.invuln = 0.0
	player.global_position = back
	await wait(0.1)


## A Flor-faminta não sai do lugar, nem apanhando.
func _test_flor_rooted() -> void:
	var back := player.global_position
	var spot := Vector3(-105, 0.3, 60)
	player.global_position = spot
	var e := Enemy.new()
	e.kind = "flor_faminta"
	world.add_child(e)
	e.global_position = spot + Vector3(0, 0, -2.0)
	e.home = e.global_position
	await wait(0.3)
	var p0: Vector3 = e.global_position
	e.take_damage(5.0, spot, false)
	await wait(1.5)
	var moved := Vector2(e.global_position.x - p0.x, e.global_position.z - p0.z).length()
	check(moved < 0.05, "Flor-faminta: fica plantada mesmo apanhando (andou %.2f m)" % moved)
	e.queue_free()
	Game.hp = Game.max_hp()
	player.global_position = back
	await wait(0.1)


# ---------------------------------------------------------------- Tecelã
## A Tecelã de meia distância cospe teia e o jogador fica preso (anda a 30%); o modelo tem as oito patas.
func _test_tecela_web() -> void:
	var back := player.global_position
	var spot := Vector3(-105, 0.3, 20)
	player.global_position = spot
	player.web_t = 0.0
	var e := Enemy.new()
	e.kind = "tecela"
	world.add_child(e)
	e.global_position = spot + Vector3(0, 0, -7)
	e.home = e.global_position
	await wait(0.2)
	var legs := 0
	for n in Enemy.SPIDER_PARTS:
		legs += 1 if e.parts.get(n) != null else 0
	check(legs == 9, "Tecelã: abdômen e oito patas no modelo (%d de 9)" % legs)
	e.web_cd = 0.0
	e.attack_cd = 0.0
	e._set_state("chase")
	await wait_until(func(): return player.web_t > 0.0, 4.0)
	check(player.web_t > 0.0, "Tecelã cospe teia de longe e prende o jogador (%.2f s)" % player.web_t)
	check(e.web_cd > 0.0, "teia entra em recarga (%.1f s)" % e.web_cd)
	e.queue_free()
	player.web_t = 0.0
	player.global_position = back
	await wait(0.1)


# ---------------------------------------------------------------- Efeitos dos elementos
## Um slime grande de teste num canto vazio do mapa (longe dos outros inimigos).
func _fx_dummy(at: Vector3, kind := "slime_grande") -> Enemy:
	var e := Enemy.new()
	e.kind = kind
	world.add_child(e)
	e.global_position = at
	return e


## Status elementais direto no componente do monstro (sem chance: Enemy.apply_status aplica sempre).
func _test_status_effects(spot: Vector3) -> void:
	var a := _fx_dummy(spot + Vector3(0, 0, 4))
	await wait(0.1)
	a.apply_status("fogo", 30.0, 3.0)
	check(a.status.has("fogo") and a.status.mask() & StatusRules.BITS.fogo != 0, "fogo aplicado entra no bitmask")
	var hp0: float = a.hp
	a.status.tick(1.01)
	check(a.hp < hp0, "queimadura tira vida no primeiro tick (%.1f -> %.1f)" % [hp0, a.hp])
	a.status.tick(3.0)
	check(not a.status.has("fogo"), "queimadura acaba")
	a.apply_status("veneno", 50.0, 5.0)
	var hp1: float = a.hp
	for i in 6:
		a.status.tick(1.0)
	check(absf((hp1 - a.hp) - 50.0 * a.element_mult("veneno")) < 1.0, "veneno dá a força toda em 5 s (x%.2f: %.1f)" % [a.element_mult("veneno"), hp1 - a.hp])
	check(not a.status.has("veneno"), "veneno acaba")
	for i in 3:
		a.apply_status("gelo", 0.0, 2.0)
	check(a.status.has("congelado") and a.stagger > 0.0 and a.slow_timer > 0.0, "3 gelos congelam")
	a.status.tick(1.1)
	check(not a.status.has("congelado"), "congelamento dura ~1 s")
	a.stagger = 0.0
	for i in 3:
		a.apply_status("gelo", 0.0, 2.0)
	check(not a.status.has("congelado") and a.stagger <= 0.0, "em recarga não congela de novo")
	# a aura acompanha o bitmask (a réplica recebe o mesmo pelo snapshot)
	a.apply_status("veneno", 50.0, 5.0)
	check(a.status_aura != null and a.status_aura.shown() == "veneno", "aura de veneno no corpo do monstro")
	a.status.tick(6.0)
	check(a.status_aura.shown() == "", "aura some quando o veneno acaba")
	await _test_status_aura_cap()
	var boss := _fx_dummy(spot + Vector3(-4, 0, 4))
	await wait(0.1)
	boss.is_boss = true
	for i in 3:
		boss.apply_status("gelo", 0.0, 2.0)
	check(not boss.status.has("congelado") and boss.slow_timer > 0.0, "chefe fica lento, nunca congela")
	a.queue_free()
	boss.queue_free()
	await wait(0.1)


## Horda em chamas: só StatusAura.MAX_PARTICLE_AURAS auras ganham partícula; as outras ficam só no contorno e
## tentam de novo no próximo set_mask delas.
func _test_status_aura_cap() -> void:
	var base := StatusAura.particle_slots_used()
	var auras: Array = []
	for i in 15:
		var au := StatusAura.new()
		world.add_child(au)
		auras.append(au)
	var free_slots := StatusAura.MAX_PARTICLE_AURAS - base
	for au in auras:
		au.set_mask(StatusRules.BITS.fogo)
	check(StatusAura.particle_slots_used() == StatusAura.MAX_PARTICLE_AURAS, "teto de auras com partícula (%d)" % StatusAura.particle_slots_used())
	var with_p := auras.filter(func(x) -> bool: return x.has_particles())
	var without := auras.filter(func(x) -> bool: return not x.has_particles())
	check(with_p.size() == free_slots and without.size() == 15 - free_slots, "as que passaram do teto ficam só no contorno")
	for k in 3:
		with_p[k].set_mask(0)
	check(StatusAura.particle_slots_used() == StatusAura.MAX_PARTICLE_AURAS - 3, "máscara 0 libera a vaga")
	for au in without:
		au.set_mask(StatusRules.BITS.fogo)
	check(StatusAura.particle_slots_used() == StatusAura.MAX_PARTICLE_AURAS, "aura sem vaga pega a vaga livre no próximo set_mask")
	for au in auras:
		au.queue_free()
	await wait(0.1)
	check(StatusAura.particle_slots_used() == base, "aura que sai da árvore devolve a vaga")


## Troca o elemento da arma equipada pelo serviço (mantém o nível) e confere que trocou.
func _swap_element(el: String, lv: int) -> void:
	Econ.request("enchant", [el])
	await wait(0.1)
	check(Game.weapon_enchant() == {"el": el, "lv": lv}, "arma trocada para %s +%d" % [el, lv])


func _test_enchant_effects() -> void:
	var back := player.global_position
	var spot := Vector3(52, 0.3, 58)
	player.global_position = spot
	await wait(0.2)
	var lv: int = Game.weapon_enchant().lv
	check(Game.weapon_enchant().el == "fogo" and lv == 2, "efeitos: a arma chega em fogo +2")
	# o clarão vermelho de dano não pode apagar o brilho do encanto (só acontecia no jogador local)
	var glowing := func() -> int:
		var n := 0
		for mi in (player.look["holder"] as Node).find_children("*", "MeshInstance3D", true, false):
			if mi.material_overlay is ShaderMaterial and mi.material_overlay.shader == EnchantFX.SHADER:
				n += 1
		return n
	var glow0: int = glowing.call()
	check(glow0 > 0, "arma encantada tem o brilho do encanto")
	player._flash()
	check(glowing.call() == 0, "clarão de dano cobre a arma")
	await wait(0.3)
	check(glowing.call() == glow0, "depois do clarão de dano o brilho do encanto volta")
	Econ.grant(600, 0, {"frost_drop": 3, "thunder_totem": 3, "toxic_gland": 3, "golden_dust": 3, "shadow_fang": 3}, "teste", true)
	var a := _fx_dummy(spot + Vector3(3, 0, 0))
	await wait(0.1)

	# fogo +2: 30% de chance; pegando, 22% do dano do golpe em 3 pulsos ao longo de 3 s
	var fx_fogo := Game.weapon_effect()
	check(absf(float(fx_fogo.get("chance", 0.0)) - 0.30) < 0.001, "fogo +2: 30% de chance")
	var hp0: float = a.hp
	check(EnchantHit.try_status(a, 100.0, fx_fogo, 0.99) == "none" and not a.status.has("fogo"), "rolagem alta não pega")
	check(EnchantHit.try_status(a, 100.0, fx_fogo, 0.10) == "applied" and a.status.has("fogo"), "fogo pega no slime")
	check(a.hp == hp0, "queimadura não tira vida na hora")
	await wait(3.4)
	# (os números destes testes levam a afinidade do boneco: queimadura é fogo, corrente é raio; ElementRules)
	check(absf((hp0 - a.hp) - 22.0 * a.element_mult("fogo")) < 1.0, "queimadura +2 tira 22 de vida em 3 s (x%.2f de fogo: %.1f)" % [a.element_mult("fogo"), hp0 - a.hp])
	var immune := _fx_dummy(spot + Vector3(-6, 0, -6), "slime_explosivo")
	await wait(0.1)
	check(EnchantHit.try_status(immune, 100.0, fx_fogo, 0.10) == "resisted" and not immune.status.has("fogo"), "imune resiste")
	immune.queue_free()
	var gone := _fx_dummy(spot + Vector3(-6, 0, 6))
	await wait(0.1)
	EnchantHit.try_status(gone, 100.0, fx_fogo, 0.0)
	gone.queue_free()   # o alvo some antes dos pulsos da queimadura
	await wait(1.3)
	check(true, "queimadura em alvo que sumiu não quebra")
	check(EnchantHit.scale(a, 100.0) == 100.0, "fogo não muda o dano do golpe")

	# gelo +2: 35% de chance; pegando, lentidão por 0,9 s
	await _swap_element("gelo", lv)
	a.slow_timer = 0.0
	EnchantHit.try_status(a, 10.0, Game.weapon_effect(), 0.0)
	check(absf(a.slow_timer - 0.9) < 0.05, "gelo +2 deixa lento por 0,9 s (%.2f)" % a.slow_timer)

	# raio +2: a corrente dá metade do dano no inimigo mais próximo a até 6 m
	await _swap_element("raio", lv)
	var fx := Game.weapon_effect()
	check(absf(float(fx.get("value", 0.0)) - 0.15) < 0.001, "raio +2: 15% de chance")
	check(EnchantHit.chain(a, 100.0, fx) == null, "corrente sem outro inimigo por perto não faz nada")
	var b := _fx_dummy(a.global_position + Vector3(2.5, 0, 0))
	await wait(0.1)
	var hpb: float = b.hp
	var a_before: float = a.hp
	check(EnchantHit.chain(a, 100.0, fx) == b, "corrente salta para o vizinho")
	check(absf((hpb - b.hp) - 50.0 * b.element_mult("raio")) < 0.01, "corrente dá metade do dano (x%.2f de raio: %.1f)" % [b.element_mult("raio"), hpb - b.hp])
	check(a.hp == a_before, "corrente não acerta o próprio alvo")
	b.queue_free()
	await wait(0.1)

	# status elementais no dono (StatusEffects): ticks, fim, congelamento e recarga
	await _test_status_effects(spot)

	# sagrado +2: +12% de dano em chefes e elites
	await _swap_element("sagrado", lv)
	check(EnchantHit.scale(a, 100.0) == 100.0, "sagrado não muda o dano em inimigo comum")
	a.elite = true
	check(absf(EnchantHit.scale(a, 100.0) - 112.0) < 0.01, "sagrado +2: 100 vira 112 em elite")
	a.elite = false
	var node = world.resource_nodes[5]
	check(EnchantHit.scale(node, 100.0) == 100.0, "alvo que não é inimigo: dano igual")
	EnchantHit.on_hit(node, 100.0)
	check(true, "efeito em alvo que não é inimigo é ignorado")

	# sombra +2: cura 1,5% do dano causado
	await _swap_element("sombra", lv)
	Game.hp = 50.0
	EnchantHit.on_hit(a, 100.0)
	check(absf(Game.hp - 51.5) < 0.01, "sombra +2 cura 1,5 por 100 de dano (%.2f)" % Game.hp)

	# arma sem encanto: nenhum efeito
	var other := "short_bow" if Game.equipment.weapon != "short_bow" else "apprentice_staff"
	var wid: String = Game.equipment.weapon
	equip_any(other)
	await wait(0.1)
	a.slow_timer = 0.0
	Game.hp = 50.0
	EnchantHit.on_hit(a, 100.0)
	check(Game.weapon_effect().is_empty() and Game.hp <= 50.0 and a.slow_timer == 0.0, "arma sem encanto não tem efeito")
	equip_any(wid)
	await wait(0.1)
	a.queue_free()
	Game.hp = Game.max_hp()
	player.global_position = back
	await wait(0.2)


# ---------------------------------------------------------------- Horta, caldeirão e comida
## Conversas da história pelos NPCs de verdade: a Mira entrega a chegada (diálogo com escolha de sabor e a
## próxima missão), o Doran entrega a forja e oferece os slimes; o rastreador e o cartão de episódio reagem.
func _test_story_talk() -> void:
	var mira := _interactable("merchant")
	check(mira.marker.text == "?", "Mira mostra ? com a conversa da chegada ativa")
	check(world.hud._track_dest == {"npc": "merchant"}, "rastreador aponta para a Mira (%s)" % world.hud._track_dest)
	check(world.story_card.kicker.text == "EPISÓDIO 1" and world.story_card.title.text == "Um Herói Caiu na Vila",
		"cartão do Episódio 1 ao aceitar a missão (%s)" % world.story_card.kicker.text)
	mira.interact(player)
	await wait(0.1)
	var d = world.modal
	check(d != null and d.get("box") != null, "diálogo novo (caixa estilo visual novel) abre")
	var guard := 0
	while is_instance_valid(d) and world.modal == d and guard < 60:
		guard += 1
		var page: Dictionary = d.pages[d.index]
		d._finish_typing()
		if page.has("choices"):
			var ch: Dictionary = page.choices[0]
			d._choose(ch.get("action", Callable()), ch.get("pages", []))
		else:
			d._advance()
		await wait(0.02)
	await wait(0.1)
	check(Game.quest_state("chegada") == "done" and Game.quest_state("forja") == "active",
		"Mira entrega a chegada e passa o favor do Doran (%s, %s)" % [Game.quest_state("chegada"), Game.quest_state("forja")])
	check(Game.count_item("health_potion") >= 2, "poções da Mira recebidas")
	var doran := _interactable("blacksmith")
	check(doran.marker.text == "?", "Doran mostra ?")
	_story_to("slimes")
	Game.start_quest("slimes")
	check(Game.quest_state("slimes") == "active", "missão dos slimes aceita")
	check(world.hud._track_dest.has("pos"), "rastreador aponta para os campos durante a caça")
	for id in ["alchemist", "rival", "camp_note"]:
		check(_interactable(id) != null, "%s está no mapa" % id)


## Guilda e mapas: registro (Rank D), contrato do quadro, promoção pela Lina (Rank C), carruagem para o
## Pântano Sussurrante (monstros e NPCs de lá) e volta para a vila.
func _test_guild_travel() -> void:
	_story_to("registro")
	Game.start_quest("registro")
	var lina := _interactable("lina")
	check(lina != null and lina.marker.text == "?", "Lina espera o registro com ?")
	Game.complete_quest("registro")
	check(Game.rank() == "D" and Game.guild_points() == 60, "registrado no Rank D com 60 pontos (%s, %d)" % [Game.rank(), Game.guild_points()])
	var board := _interactable("board")
	check(board != null, "Quadro de Contratos na vila")
	_story_to("bosque")
	Game.start_quest("q_gelo")
	for i in 3:
		Econ.kill("slime_gelo", 0, 0, "campos_norte")
	Game.complete_quest("q_gelo")
	check(Game.guild_points() >= 100, "contrato do quadro dá pontos (%d)" % Game.guild_points())
	# promoção pelo diálogo da Lina: a escolha de promoção está nos serviços dela
	lina.interact(player)
	await wait(0.1)
	var d = world.modal
	var promo: Dictionary = {}
	if d != null:
		for pg in d.pages:
			for ch in pg.get("choices", []):
				if str(ch.text).begins_with("Pedir promoção"):
					promo = ch
	check(not promo.is_empty(), "Lina oferece a promoção")
	if not promo.is_empty():
		for pg in promo.pages:
			if pg.has("on_show"):
				pg.on_show.call()
	if d != null and is_instance_valid(d):
		d._close()
	await wait(0.1)
	check(Game.rank() == "C", "promovido ao Rank C (%s)" % Game.rank())
	check(world.story_card.kicker.text == "PROMOÇÃO NA GUILDA" or world.story_card._queue.any(
		func(c: Array) -> bool: return c[0] == "PROMOÇÃO NA GUILDA"), "cartão de promoção")
	# carruagem
	var coach := _interactable("coach")
	check(coach != null, "cocheiro da guilda no portão norte")
	var pages: Array = StoryDialogue.build(coach)
	var dests: Array = []
	for ch in pages[0].get("choices", []):
		dests.append(str(ch.text))
	var bosque_label := "Pântano Sussurrante (%d de ouro)" % Game.travel_cost("bosque", "coach")
	check(bosque_label in dests and "Geleira de Cristal (Rank B)" in dests, "carruagem: bosque liberado com preço, mina travada (%s)" % [dests])
	# viagem paga: sem ouro não vai; com ouro, o cocheiro cobra e leva
	var coach_cost := Game.travel_cost("bosque", "coach")
	check(coach_cost > 0 and Game.travel_cost("bosque", "map") > coach_cost, "teleporte do mapa mais caro que o cocheiro")
	if Game.gold < coach_cost:
		Game.add_gold(coach_cost - Game.gold)
	var gold_before := Game.gold
	check(world.request_travel("bosque", "coach"), "pede a viagem paga ao cocheiro")
	await wait(1.6)
	check(Game.gold == gold_before - coach_cost, "cocheiro cobrou %d de ouro (%d -> %d)" % [coach_cost, gold_before, Game.gold])
	check(Regions.region_at(player.global_position) == "bosque", "viagem leva ao Pântano Sussurrante (%s)" % player.global_position)
	check(_interactable("sylvi") != null and _interactable("coach_bosque") != null, "Sylvi e a carruagem no bosque")
	var queen := false
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.kind == "slime_rainha" and not e.dead:
			queen = true
	check(queen, "Slime Rainha nasceu no bosque")
	check(MusicRules.area(player.global_position) == "swamp", "música do bosque (pântano)")
	world.travel_to("vila")
	await wait(1.6)
	check(Regions.region_at(player.global_position) == "vila", "carruagem traz de volta à vila")


## Completa pelas regras as missões da história antes de `target` (conversa, coleta com os itens dados, abates).
func _story_to(target: String) -> void:
	for id in ItemDB.QUESTS:
		if id == target:
			return
		var d: Dictionary = ItemDB.QUESTS[id]
		if Game.quest_state(id) == "done":
			continue
		if Game.quest_state(id) == "none":
			Game.start_quest(id)
		match CharRules.quest_type(d):
			"collect":
				Econ.grant(0, 0, {d.target: int(d.count)}, "teste", true)
			"kill":
				var kind: String = d.targets[0] if d.has("targets") else d.target
				for i in maxi(0, int(d.count) - int(Game.quests[id].progress)):
					Econ.kill(kind, 0, 0, str(d.get("region", "")))
		Game.complete_quest(id)


func _interactable(id: String, index := -1) -> Node:
	for n in get_tree().get_nodes_in_group("interactable"):
		if n.get("npc_id") == id and (index < 0 or n.get("index") == index):
			return n
	return null


func _test_farm() -> void:
	var plot := _interactable("plot", 0)
	check(plot != null and Game.plot_state(0) == "empty", "canteiro 0 vazio e liberado")
	check(Game.plot_state(Game.FARM_START_PLOTS) == "locked", "canteiros extras começam bloqueados")
	player.global_position = plot.global_position + Vector3(0, 0.3, -1.2)
	await wait(0.3)
	check(player.interact_target == plot, "jogador detecta o canteiro")
	plot.interact(player)
	await wait(0.1)
	check(world.modal != null and world.modal.get("plot_index") == 0, "menu de plantio abre")
	var seeds0 := Game.count_item("seed_carrot")
	world.modal.select_crop("carrot")
	world.modal._plant_here()
	await wait(0.05)
	var confirm: ActionModal = null
	for n in world.modal.get_children():
		if n is ActionModal:
			confirm = n
	check(confirm != null and Game.plot_state(0) == "empty", "plantar pergunta antes (janelinha de confirmação)")
	if confirm:
		confirm._confirm()
	await wait(0.1)
	check(world.modal == null and Game.plot_state(0) == "growing" and Game.farm.plots[0].crop == "carrot", "cenoura plantada")
	check(Game.count_item("seed_carrot") == seeds0 - 1, "semente consumida")
	plot.interact(player)
	check(Game.farm.plots[0].watered, "canteiro regado")
	var g0: float = Game.plot_growth(0)
	var t0 := Econ.now()
	await wait(1.0)
	var g1: float = Game.plot_growth(0)
	var rate := (g1 - g0) / (Econ.now() - t0)
	check(g1 > g0 and abs(rate - 2.0 / ItemDB.CROPS.carrot.time) < 0.02, "regado cresce 2x (%.3f/s)" % rate)
	Econ.time_offset += ItemDB.CROPS.carrot.time   # a horta cresce pelo relógio: adianta o relógio
	await wait(0.3)
	check(Game.plot_state(0) == "ready", "planta fica pronta")
	var carrots := Game.count_item("carrot")
	plot.interact(player)
	check(Game.plot_state(0) == "empty" and Game.count_item("carrot") >= carrots + 3, "colheita regada rende +1 (%d)" % (Game.count_item("carrot") - carrots))

	# adubo de gel de slime
	Game.add_item("slime_gel", 1, true)
	Game.plant(1, "wheat", true)
	Game.water(1)
	Game.fertilize(1)
	check(Game.farm.plots[1].fert and Game.plot_growth(1) >= 0.4, "adubo de gel de slime acelera")

	# plantar em todos os vazios
	Econ.grant(200, 0, {}, "teste")
	plot.interact(player)
	await wait(0.1)
	world.modal.select_crop("tomato")
	world.modal.plant_all_now()
	await wait(0.1)
	var growing := 0
	for i in Game.FARM_PLOTS:
		if Game.plot_state(i) == "growing":
			growing += 1
	check(growing == Game.FARM_START_PLOTS, "plantar em todos os vazios (%d canteiros)" % growing)

	# liberar canteiro
	var gold0 := Game.gold
	var cost := Game.unlock_cost()
	Game.unlock_next_plot()
	check(Game.farm.unlocked == Game.FARM_START_PLOTS + 1 and Game.gold == gold0 - cost, "canteiro novo liberado por %d ouro" % cost)

	# caldeirão
	var kitchen := _interactable("kitchen")
	check(kitchen != null, "caldeirão na horta")
	Game.add_item("tomato", 6, true)
	Game.add_item("pepper", 6, true)
	Game.add_item("carrot", 2, true)
	kitchen.interact(player)
	await wait(0.1)
	check(world.modal != null and world.modal.has_method("_cook"), "menu do caldeirão abre")
	world.modal.select_recipe("spicy_soup")
	world.modal._cook(99)
	check(Game.count_item("spicy_soup") == 3, "cozinhou 3 sopas picantes (%d)" % Game.count_item("spicy_soup"))
	world.modal._close()
	await wait(0.05)
	Game.cook("dragon_chili")
	check(Game.count_item("dragon_chili") == 1, "cozinhou chili do dragão")

	# comer: bônus temporário
	var dmg0 := Game.melee_damage()
	Game.selected_food = "spicy_soup"
	Game.eat_cooldown = 0.0
	var mgold0 := Game.mod("gold")
	check(Game.eat_selected() and Game.has_buff("food_warm"), "comeu sopa picante")
	check(abs(Game.mod("gold") - mgold0 - 0.05) < 0.001, "sopa dá +5% de ouro")
	check(abs(Game.melee_damage() - dmg0) < 0.01, "sopa não muda o dano")
	var gold_food0 := Game.gold
	Game.add_gold(100)
	check(Game.gold - gold_food0 == 105, "comida: ouro ganho na vila +5%% (%d)" % (Game.gold - gold_food0))
	check(not Game.eat("spicy_soup"), "não come de novo durante a mastigação")
	Game.tick_buffs(999.0)
	check(Game.buffs.is_empty() and abs(Game.mod("gold") - mgold0) < 0.001, "bônus expira e o ouro volta")

	# a horta também fica no save solo
	var farm_saved: Dictionary = Game.farm.duplicate(true)
	var g_saved := Game.plot_growth(1)
	Game.farm = {"unlocked": 0, "plots": []}
	check(Econ.reload_solo(), "serviço local recriado (horta)")
	check(Game.farm.unlocked == farm_saved.unlocked and Game.farm.plots[1].crop == "wheat" \
		and abs(Game.plot_growth(1) - g_saved) < 0.05, "save solo guarda a horta")


# ---------------------------------------------------------------- Desafio da Horda
func _test_survival() -> void:
	var portal: Node = null
	for n in get_tree().get_nodes_in_group("interactable"):
		if n.get("npc_id") == "portal":
			portal = n
	check(portal != null, "portal do desafio na vila")
	player.global_position = portal.global_position + Vector3(0, 0.3, 1.5)
	await wait(0.3)
	check(player.interact_target == portal, "jogador detecta o portal")
	portal.interact(player)
	await wait(0.1)
	check(world.modal != null and world.modal.pages[0].has("choices"), "portal abre diálogo com escolha")
	var xp0 := Game.xp
	var lvl0 := Game.level
	var gold0 := Game.gold
	world.modal._choose(world.modal.pages[0].choices[0].action)
	await wait(0.2)
	var sv = world.survival
	check(sv != null and Game.run_mods.active, "desafio iniciado pelo portal")
	check(player.global_position.distance_to(world.ARENA) < 3.0, "jogador teleportado para a arena")
	check(absf(world.ARENA.z) > world.MAP_HALF + 200.0, "arena é um mapa à parte, fora de Valdoria")
	check(player.is_on_floor() or player.global_position.y > -1.0, "arena tem chão próprio")
	check(sv.weapon_levels.get("fogo", 0) == 1, "começa com Orbe de Fogo Nv 1")
	sv.round_time = 6.0
	sv.round_left = 6.0
	await wait(3.0)
	var horde: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.horde:
			horde.append(e)
	check(horde.size() >= 2, "inimigos da horda surgem (%d)" % horde.size())
	var near := true
	for e in horde:
		if e.global_position.distance_to(world.ARENA) > sv.ARENA_RADIUS + 1.0:
			near = false
	check(near, "inimigos nascem dentro da arena")
	for e in horde:
		if is_instance_valid(e) and not e.dead:
			e.take_damage(99999, player.global_position, false)
	await wait(0.1)
	check(sv.kills >= horde.size(), "abates contados (%d)" % sv.kills)
	check(sv.my_dmg > 0.0, "placar soma o dano causado (%d)" % int(sv.my_dmg))
	var rows: Array = sv.scoreboard_rows()
	check(rows.size() == 1 and rows[0].me and rows[0].build.w.has("fogo"), "placar do Tab tem a build do jogador")
	sv.hud.scoreboard.force_open = true
	await wait(0.1)
	check(sv.hud.scoreboard.visible and sv.hud.weapon_row.get_child_count() == 1, "Tab abre o placar e a build aparece em ícones")
	sv.hud.scoreboard.force_open = false
	check(Game.xp == xp0 and Game.level == lvl0, "horda não dá XP do RPG")
	check(get_tree().get_nodes_in_group("xp_gems").size() > 0, "gemas de XP caem")
	var gem = get_tree().get_nodes_in_group("xp_gems")[0]
	player.global_position = gem.global_position + Vector3(0.5, 0.0, 0.0)
	await wait(0.8)
	check(not is_instance_valid(gem) and sv.run_xp + sv.run_level > 1, "gema coletada ao se aproximar")

	# subida de nível da partida
	sv.add_xp(sv.xp_needed())
	await wait(0.1)
	check(world.modal != null and world.modal.mode == "levelup" and get_tree().paused, "cartas de nível abrem e pausam")
	check(world.modal.choices.size() == 3, "3 cartas oferecidas")
	await _pick_levelups(true)
	check(not get_tree().paused, "jogo volta após a escolha")

	# fim de rodada: limpa a arena e oferece bênção
	sv.round_left = 0.01
	for i in 50:
		await wait(0.1)
		if world.modal != null and world.modal.get("mode") == "round":
			break
		await _pick_levelups(false)
	check(sv.rounds_cleared == 1 and world.modal != null and world.modal.mode == "round", "fim da rodada abre escolha de bênção")
	var horde_alive := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.horde:
			horde_alive += 1
	check(horde_alive == 0, "pulso de fim de rodada elimina a horda")
	await wait(0.45)
	world.modal._pick(0)
	await wait(0.2)
	check(sv.blessing_counts.size() == 1 and sv.round_num == 2 and sv.phase == "fight", "bênção aplicada e rodada 2 começa")
	check(sv.seeds_won >= 1, "rodada concluída dá sementes (%d)" % sv.seeds_won)

	# comer no meio da rodada: o bônus da comida soma aos da Horda
	sv._spawn_enemy("slime", player.global_position + Vector3(3, 0.2, 0))
	await wait(0.1)
	Game.eat_cooldown = 0.0
	Game.selected_food = "dragon_chili"
	check(Game.eat_selected() and Game.has_buff("food_chili"), "comeu chili do dragão na rodada")
	check(Game.mod("gold") > float(Game.run_mods.get("gold", 0.0)), "bônus da comida soma aos da Horda")

	# elite: maior, mais vida e solta mais gemas
	var plain: Enemy = sv._spawn_enemy("slime", player.global_position + Vector3(-5, 0.2, 0))
	var elite: Enemy = sv._spawn_enemy("slime", player.global_position + Vector3(-5, 0.2, 2), -1.0, -1.0, true)
	await wait(0.1)
	check(elite.elite and elite.max_hp > plain.max_hp * 3.0, "elite tem 3x+ a vida de um comum")
	# conta as gemas novas, não o total: uma gema antiga recolhida pelo jogador nesse meio tempo baixava o total
	var gems_old := {}
	for g in get_tree().get_nodes_in_group("xp_gems"):
		gems_old[g.get_instance_id()] = true
	elite.take_damage(99999, player.global_position, false)
	plain.take_damage(99999, player.global_position, false)
	await wait(0.1)
	var gems_new := 0
	for g in get_tree().get_nodes_in_group("xp_gems"):
		if not gems_old.has(g.get_instance_id()):
			gems_new += 1
	check(gems_new >= 4, "elite solta várias gemas (%d novas)" % gems_new)
	for g in get_tree().get_nodes_in_group("xp_gems"):
		g.queue_free()   # não deixa XP extra no chão para os testes seguintes

	# combo (efeito direto): dano em área em volta do ponto
	var ce: Enemy = sv._spawn_enemy("slime_grande", player.global_position + Vector3(0, 0.2, -4))
	await wait(0.1)
	var chp := ce.hp
	sv.weapons.combo_strike("choque", ce.global_position, 2)
	check(ce.hp < chp or ce.dead, "efeito de combo fere inimigos em volta")
	if not ce.dead:
		ce._die()
	await wait(0.05)
	for g in get_tree().get_nodes_in_group("xp_gems"):
		g.queue_free()
	check(UPG.combo_for("aura", "fogo") == "choque" and UPG.combo_for("fogo", "fogo") == "", "pares de combo")

	# escala de dificuldade: sobe a cada rodada e alivia na do chefe
	var r0: int = sv.round_num
	sv.round_num = 4
	var hp4: float = sv.hp_scale()
	sv.round_num = 9
	check(sv.hp_scale() > hp4 * 1.8 and sv.elite_chance() > 0.0, "inimigos escalam com a rodada")
	var evt = load("res://scripts/survival/horde_events.gd")
	check(evt.spawn_rate(4, 1) > evt.spawn_rate(5, 1) and evt.spawn_rate(6, 1) > evt.spawn_rate(1, 1),
		"ritmo em dente de serra: alivia na rodada do chefe e o ciclo seguinte começa mais forte")
	sv.round_num = r0

	# chefe na rodada 5
	sv.round_num = 4
	sv._start_round()
	await wait(0.1)
	check(sv.boss_alive() and sv.boss.horde, "Rei Goblin aparece na rodada 5")
	check(sv.event == "", "rodada do chefe sem evento")
	var king_flag = Game.flags.get("king_dead", false)
	sv.boss.take_damage(99999, player.global_position, false)
	await wait(0.1)
	check(Game.flags.get("king_dead", false) == king_flag and not sv.boss_alive(), "chefe da horda derrotado sem afetar missões")

	await _test_horde_extras(sv)

	# retirada pelo menu de pausa
	world._open_modal(_pause_menu())
	await wait(0.1)
	world.modal._abandon()
	await wait(0.2)
	check(world.modal != null and world.modal.mode == "results", "tela de resultados ao abandonar")
	await wait(0.45)
	world.modal._finish()
	await wait(0.2)
	check(world.survival == null and not Game.run_mods.active, "desafio encerrado e bônus zerados")
	check(player.global_position.distance_to(world.HORDE_RETURN) < 3.0, "jogador volta para a vila, na frente do portal")
	check(Game.xp != xp0 or Game.level > lvl0, "XP de recompensa entregue ao RPG")
	check(Game.flags.has("horde_best"), "recorde salvo")
	check(Econ.quick_save(player.global_position, 0.0), "salvar volta a funcionar após o desafio")

	# morte no desafio não tira ouro
	world.start_survival()
	await wait(0.2)
	sv = world.survival
	var gold1 := Game.gold
	player.invuln = 0
	player.take_damage(99999, player.global_position + Vector3.FORWARD)
	check(player.dead, "jogador cai na horda")
	await wait(2.2)
	check(world.modal != null and world.modal.mode == "results", "resultados após morrer no desafio")
	await wait(0.45)
	world.modal._finish()
	await wait(0.2)
	check(not player.dead and Game.gold == gold1 and Game.hp == Game.max_hp(), "volta à vila sem perder ouro")
	check(gold1 >= gold0, "ouro não diminuiu durante o desafio")


## Monstros novos, eventos e Caçada (solo). As armas automáticas ficam desligadas para não
## matarem os monstros antes de eles mostrarem o comportamento.
func _test_horde_extras(sv) -> void:
	await _pick_levelups(false)
	sv.weapons.process_mode = Node.PROCESS_MODE_DISABLED
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.horde and not e.dead:
			e._die()
	sv.round_left = 999.0
	sv._spawn_acc = -9999.0   # sem spawns normais durante o teste
	sv.event = ""
	sv.hunt_target = 0
	await wait(0.3)
	var base: Vector3 = player.global_position

	# slime explosivo: corre até o jogador, explode (dano em área) e morre
	player.invuln = 0
	Game.hp = Game.max_hp()
	var hp0 := Game.hp
	var bomb: Enemy = sv._spawn_enemy("slime_explosivo", base + Vector3(3.0, 0.2, 0))
	var kills0: int = sv.kills
	check(await _until(func() -> bool: return not is_instance_valid(bomb) or bomb.dead, 5.0), "slime explosivo explode")
	check(Game.hp < hp0, "explosão fere o jogador (%.0f → %.0f)" % [hp0, Game.hp])
	check(sv.kills == kills0 + 1, "explosão conta como abate")
	Game.hp = Game.max_hp()

	# Slime Mãe se divide em 3 slimes velozes
	var veloz0 := _count_alive("slime_veloz")
	var mae: Enemy = sv._spawn_enemy("slime_mae", base + Vector3(-12, 0.2, 0))
	await wait(0.1)
	mae.take_damage(99999, base, false)
	await wait(0.2)
	check(_count_alive("slime_veloz") == veloz0 + 3, "Slime Mãe se divide em 3 (%d)" % (_count_alive("slime_veloz") - veloz0))
	_kill_horde()
	await wait(0.2)
	await _settle_horde()

	# Goblin Arqueiro mantém distância e atira flechas
	var archer: Enemy = sv._spawn_enemy("goblin_arqueiro", base + Vector3(0, 0.2, 9.0))
	var arrow_seen := await _until(func() -> bool: return _count_script(sv, preload("res://scripts/enemies/enemy_arrow.gd")) > 0, 6.0)
	check(arrow_seen, "Goblin Arqueiro atira flechas")
	check(archer.global_position.distance_to(player.global_position) > 4.0, "arqueiro mantém distância (%.1f m)" % archer.global_position.distance_to(player.global_position))
	player.invuln = 0
	Game.hp = Game.max_hp()
	var hp1 := Game.hp
	check(await _until(func() -> bool: return Game.hp < hp1, 6.0), "flecha acerta o jogador")
	_kill_horde()
	Game.hp = Game.max_hp()
	await wait(0.2)
	await _settle_horde()

	# Goblin Xamã cura os aliados em volta
	var shaman: Enemy = sv._spawn_enemy("goblin_xama", base + Vector3(8.0, 0.2, 0))
	var hurt: Enemy = sv._spawn_enemy("slime_grande", base + Vector3(9.0, 0.2, 1.0))
	await wait(0.1)
	hurt.hp = hurt.max_hp * 0.3
	var hhp := hurt.hp
	check(await _until(func() -> bool: return is_instance_valid(hurt) and hurt.hp > hhp, 7.0), "Goblin Xamã cura aliados (%.0f → %.0f)" % [hhp, hurt.hp])
	check(is_instance_valid(shaman) and shaman.data.get("tint") != null, "xamã com cor própria")
	_kill_horde()
	Game.hp = Game.max_hp()
	await wait(0.2)
	await _settle_horde()

	# Goblin Dourado: foge e some sem contar abate; abatido, solta ouro
	var gold_g: Enemy = sv._spawn_enemy("goblin_dourado", base + Vector3(5, 0.2, 0))
	await wait(1.0)
	check(gold_g.global_position.distance_to(player.global_position) > 5.5, "Goblin Dourado foge do jogador")
	var k1: int = sv.kills
	gold_g.born_t = sv.GOLD_ESCAPE + 1.0
	await wait(0.2)
	check(gold_g.dead and gold_g.escaped and sv.kills == k1, "Goblin Dourado escapa sem contar abate")
	var gold_g2: Enemy = sv._spawn_enemy("goblin_dourado", base + Vector3(2, 0.2, 0))
	await wait(0.1)
	var coins0 := _count_script(sv, preload("res://scripts/world/pickup.gd"))
	gold_g2.take_damage(99999, base, false)
	await wait(0.1)
	check(_count_script(sv, preload("res://scripts/world/pickup.gd")) >= coins0 + 3 or Game.gold > 0, "Goblin Dourado abatido solta ouro")

	# Campeão Goblin: elite com barra de vida sempre visível
	var champ: Enemy = sv._spawn_enemy("goblin_campeao", base + Vector3(-6, 0.2, 0))
	await wait(0.1)
	check(champ.bar_root.visible and champ.max_hp > 400, "Campeão Goblin (elite, %d de vida)" % champ.max_hp)
	_kill_horde()
	Game.hp = Game.max_hp()
	await wait(0.3)

	# Chuva de Meteoros: o círculo avisa e o impacto fere quem ficou dentro
	_clear_gems()
	await _pick_levelups(false)
	sv.event = "meteoros"
	player.invuln = 0
	Game.hp = Game.max_hp()
	var hp2 := Game.hp
	sv._meteor_t = 999.0
	sv._drop_meteor(player.global_position)
	check(sv._meteors.size() == 1, "meteoro anunciado com aviso")
	# cartas de nível (gemas ainda chegando) pausam o jogo: escolhe e segue esperando
	await _until(func() -> bool:
		if world.modal != null and world.modal.get("mode") == "levelup" and world.modal._lock <= 0.0:
			world.modal._pick(0)
		return sv._meteors.is_empty(), 8.0)
	check(Game.hp < hp2 and sv._meteors.is_empty(), "meteoro cai e fere quem ficou no círculo (hp %.0f→%.0f, %d pendentes, fase %s, pausado %s, modal %s)" % [hp2, Game.hp, sv._meteors.size(), sv.phase, get_tree().paused, world.modal])
	sv.event = ""
	Game.hp = Game.max_hp()

	# sorteio dos eventos
	var seen := {}
	for i in 200:
		var ev: String = sv.EVT.roll_event(3 + i % 4, false, "")
		if ev != "":
			seen[ev] = true
	check(seen.size() >= 5, "eventos sorteados variam (%s)" % ", ".join(seen.keys()))
	check(sv.EVT.roll_event(5, true) == "" and sv.EVT.roll_event(1, false) == "", "sem evento na rodada 1 e na do chefe")

	# Caçada: bater a meta dá o baú (gemas e ouro em volta do jogador)
	_clear_gems()
	await _pick_levelups(false)
	sv.hunt_target = sv.hunt_kills + 1
	sv.hunt_done = false
	var won0: int = sv.hunts_won
	var gems0 := get_tree().get_nodes_in_group("xp_gems").size()
	var victim: Enemy = sv._spawn_enemy("slime", base + Vector3(4, 0.2, 0))
	await wait(0.1)
	victim.take_damage(99999, base, false)
	# conta logo: o ímã recolhe as gemas em poucos quadros
	var gems1 := get_tree().get_nodes_in_group("xp_gems").size()
	check(sv.hunt_done and sv.hunts_won == won0 + 1, "Caçada concluída dá o baú")
	check(gems1 >= gems0 + 6, "baú da Caçada solta gemas (%d)" % (gems1 - gems0))
	await wait(0.1)
	sv.hunt_target = 0

	# HUD da horda mostra nível e habilidades
	var hud = sv.hud
	await wait(0.05)
	check(hud.lvl_label.text.ends_with(" %d" % sv.run_level), "HUD mostra o nível (%s)" % hud.lvl_label.text)
	check(hud.weapon_row.get_child_count() == sv.weapon_levels.size(), "HUD mostra os ícones das armas (%d)" % hud.weapon_row.get_child_count())
	check(hud.extra_row.get_child_count() == sv.passive_levels.size() + sv.blessing_counts.size(), "HUD mostra os ícones das passivas e bênçãos")

	sv.weapons.process_mode = Node.PROCESS_MODE_INHERIT
	sv._spawn_acc = 0.0
	await _pick_levelups(false)


func _until(cond: Callable, max_t: float) -> bool:
	var t := 0.0
	while not cond.call() and t < max_t:
		await wait(0.1)
		t += 0.1
	return cond.call()


func _count_alive(kind: String) -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.kind == kind and not e.dead:
			n += 1
	return n


func _count_script(parent: Node, scr: Script) -> int:
	var n := 0
	for c in parent.get_children():
		if c.get_script() == scr:
			n += 1
	return n


func _clear_gems() -> void:
	for g in get_tree().get_nodes_in_group("xp_gems"):
		g.remove_from_group("xp_gems")
		g.queue_free()


## Depois de abater a horda de um bloco: tira as gemas do chão e escolhe as cartas de nível pendentes. Uma gema
## recolhida por acaso sobe o nível, e a horda fica congelada enquanto a carta espera (survival_mode.frozen):
## o arqueiro, o xamã e o Goblin Dourado do bloco seguinte ficavam parados até o tempo da checagem acabar.
func _settle_horde() -> void:
	_clear_gems()
	await _pick_levelups(false)


func _kill_horde() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.horde and not e.dead:
			e.take_damage(99999, player.global_position, false)


# ---------------------------------------------------------------- Aviso de atualização durante a partida
func _test_update() -> void:
	check(Updater.state == Updater.State.DISABLED, "auto update desligado fora do build exportado")
	# simula a checagem periódica achando uma versão nova com a partida em andamento
	Updater.latest_version = "99.0.0"
	Updater._set_state(Updater.State.AVAILABLE)
	check(Updater._toast != null and Updater._toast.visible, "aviso de versão nova aparece durante a partida")
	world._open_modal(_pause_menu())
	await wait(0.1)
	var panel: Control = null
	for n in world.modal.find_children("*", "VBoxContainer", true, false):
		if n.get_script() == preload("res://scripts/ui/update_panel.gd"):
			panel = n
	check(panel != null and panel.is_visible_in_tree(), "menu de pausa oferece Atualizar agora")
	world.modal._close()
	await wait(0.1)
	Updater.latest_version = ""
	Updater._set_state(Updater.State.DISABLED)
	check(not Updater._toast.visible, "aviso some quando não há versão nova")
	# recusa por versão: servidor antigo (deploy em andamento) x jogo desatualizado
	var r := "Versão diferente do servidor (sua: %s, servidor: %s). Atualize o jogo."
	check(Network.explain_rejection(r % ["0.5.3", "0.5.2"], "0.5.3").begins_with("O servidor ainda está na v0.5.2"),
		"jogo mais novo que o servidor: avisa que o servidor está sendo atualizado")
	check(Network.explain_rejection(r % ["0.5.2", "0.5.3"], "0.5.2") == r % ["0.5.2", "0.5.3"],
		"jogo mais velho que o servidor: mantém o pedido para atualizar")


func _pause_menu() -> Control:
	var p := preload("res://scripts/ui/pause_menu.gd").new()
	p.mode = "pause"
	return p


## Registra os projéteis CRIADOS na cena (não só os vivos): a faísca do cajado e a bola de fogo seguem a mira
## da câmera, batem no chão a poucos metros e somem; contar só os vivos depois de uma espera falhava no CI.
## Devolve [lista de kinds, callable]; chame _stop_spawn_watch com o resultado ao terminar.
func _watch_spawns() -> Array:
	var seen: Array[String] = []
	var cb := func(n: Node) -> void:
		if n is Area3D and n.get_script() == preload("res://scripts/player/projectile.gd"):
			seen.append(n.kind)
		elif n is Area3D and n.get_script() == preload("res://scripts/player/fireball.gd"):
			seen.append("fireball")
		elif n is FireballProjectile:
			seen.append("staff_fireball")
	world.child_entered_tree.connect(cb)
	return [seen, cb]


func _stop_spawn_watch(w: Array) -> void:
	if world.child_entered_tree.is_connected(w[1]):
		world.child_entered_tree.disconnect(w[1])


func _test_gear() -> void:
	# dados consistentes
	var bad: Array[String] = []
	for id in ItemDB.ITEMS:
		var it: Dictionary = ItemDB.ITEMS[id]
		if it.type in ["weapon", "armor", "gear"] and not ItemDB.SLOTS.has(ItemDB.slot_of(id)):
			bad.append(id)
		for k in it.get("stats", {}):
			if not ItemDB.STAT_NAMES.has(k):
				bad.append("%s.%s" % [id, k])
		if ItemTooltip.build_text(id) == "":
			bad.append(id + " (dica)")
	for id in ItemDB.SHOP_STOCK:
		if not ItemDB.ITEMS.has(id):
			bad.append("loja:" + id)
	for k in Enemy.TYPES:
		for entry in Enemy.TYPES[k].loot:
			if not ItemDB.ITEMS.has(entry[0]):
				bad.append("saque:" + entry[0])
	check(bad.is_empty(), "itens novos consistentes (%d itens) %s" % [ItemDB.ITEMS.size(), bad])

	# cajado: ataque básico = Bola de Fogo (clique: bola normal; segurar: cresce na gema e explode em área)
	var dmg_sword := Game.melee_damage()
	equip_any("apprentice_staff")
	check(Game.equipment.weapon == "apprentice_staff", "equipou cajado")
	await wait(0.05)
	check(Game.weapon_class() == "staff" and player.look["class"] == "staff", "classe da arma: cajado")
	check(player.look.holder != null and is_instance_valid(player.look.holder), "modelo do cajado montado na mão")
	player.attacking = false
	player.combo_window = 0.0
	Game.stamina = Game.max_stamina()
	var fb_watch := _watch_spawns()
	player._start_swing()   # sem o botão segurado: solta no passo seguinte como clique
	await wait_until(func(): return not player.attacking, 2.0)
	_stop_spawn_watch(fb_watch)
	check("staff_fireball" in fb_watch[0], "cajado dispara a Bola de Fogo no clique")
	check(player.fireball_orb == null, "clique não deixa bola presa na gema")
	await wait(0.3)
	# segurar: a bola nasce na gema e cresce; soltar dispara a carregada
	Game.stamina = Game.max_stamina()
	Input.action_press("attack")
	player._start_swing()
	await wait(0.25 + MageStaffAttack.CHARGE_TIME * 0.6)
	var orb: FireballProjectile = player.fireball_orb
	check(orb != null and is_instance_valid(orb) and orb.size > 1.5, "segurar: a bola cresce na gema (%s)" % [orb.size if orb else -1.0])
	Input.action_release("attack")
	await wait(0.05)
	check(orb != null and is_instance_valid(orb) and orb.is_charged and orb._state == FireballProjectile.FLYING, "soltar dispara a bola carregada")
	check(orb != null and is_instance_valid(orb) and orb.aoe_radius > MageStaffAttack.AOE_MIN, "carga maior, explosão maior")
	await wait(0.5)
	check(not ("heal" in ItemDB.kit("staff")) and ItemDB.kit("scepter")[0] == "heal", "Cura é do cetro, não do cajado")

	# cetro (healer): kit pela classe, Cura sobe a vida e o ataque básico é a esfera de luz
	Game.add_item("sc_novice_scepter")
	equip_any("sc_novice_scepter")
	await wait(0.05)
	check(Game.char_class == "healer" and Game.weapon_class() == "scepter", "healer com cetro")
	check(Game.ability_kit() == ["heal", "scepter_lance", "scepter_ward", "scepter_ult", "scepter_judgment"], "kit do healer (%s)" % [Game.ability_kit()])
	check(world.hud.slots["slot_5"].visible, "a barra mostra a 5ª habilidade para o healer")
	check(player.look["class"] == "staff" and player.look.holder != null, "cetro sem modelo próprio cai no cajado procedural")
	Game.hp = Game.max_hp() * 0.3
	Game.mp = Game.max_mp()
	player.attacking = false
	player.ability = ""
	player.dodge_timer = 0.0
	var hp_h := Game.hp
	var mp_h := Game.mp
	player.cast("heal")
	check(player.heal_armed and is_equal_approx(Game.hp, hp_h) and is_equal_approx(Game.mp, mp_h), "Cura: a tecla só prepara (sem cura, sem mana)")
	await wait(0.1)
	check(player.heal_target == player and player.model.get_node_or_null("HealMark") != null, "Cura preparada sem aliado na mira marca você")
	player.cast("heal")
	check(not player.heal_armed and player.model.get_node_or_null("HealMark") == null and is_equal_approx(Game.mp, mp_h), "a mesma tecla de novo desiste sem gastar")
	player.cast("heal")
	hp_h = Game.hp   # a vida regenerou nas esperas acima
	mp_h = Game.mp
	player.confirm_heal(player.heal_target)
	check(Game.hp > hp_h and absf((Game.hp - hp_h) - minf(Game.heal_amount(), Game.max_hp() - hp_h)) < 0.01, "Cura confirmada sobe a vida (%.1f -> %.1f)" % [hp_h, Game.hp])
	check(Game.mp < mp_h and player.cooldowns.heal > 0.0, "Cura gasta mana e entra em recarga")
	check(not player.heal_armed, "confirmar desarma a Cura")
	await wait(0.1)
	check(player.model.get_node_or_null("HealMark") == null, "a borda some depois da Cura")
	# Lança de Luz (nível 2): projétil de luz que causa dano
	player.ability = ""
	player.cast_timer = 0.0
	Game.mp = Game.max_mp()
	var lvl_lance := Game.level
	Game.level = maxi(Game.level, 2)
	var lance_watch := _watch_spawns()
	player.cooldowns.scepter_lance = 0.0
	var lance_mp := Game.mp
	player.cast("scepter_lance")
	check(player.ability == "scepter_lance", "Lança de Luz começa")
	check(is_equal_approx(lance_mp - Game.mp, 15.0) and player.cooldowns.scepter_lance > 0.0, "Lança de Luz gasta 15 de mana e entra em recarga")
	await wait_until(func(): return "holy_lance" in lance_watch[0], 1.0)
	_stop_spawn_watch(lance_watch)
	check("holy_lance" in lance_watch[0], "Lança de Luz dispara o projétil")
	await wait(0.5)
	check(player.ability == "", "Lança de Luz termina a pose")
	Game.level = lvl_lance
	# Escudo de Luz (nível 3) e Banquete do Herói (ultimate, nível 8) no solo: buff em si, mana, recarga, fúria
	var lvl_hz := Game.level
	Game.clear_buffs(true)
	Game.level = 2
	Game.mp = Game.max_mp()
	player.cooldowns.scepter_ward = 0.0
	player.cast("scepter_ward")
	check(not Game.has_buff("scepter_ward") and player.ability == "", "Escudo de Luz bloqueado no nível 2")
	# Julgamento de Luz (slot 5, nível 5): a tecla prepara a área, a confirmação solta no ponto mirado
	Game.level = 4
	player.cooldowns.scepter_judgment = 0.0
	player.use_slot(5)
	check(player.area_armed == "" and player.ability == "", "Julgamento de Luz bloqueado no nível 4")
	Game.level = 8
	var jud_mp := Game.mp
	player.use_slot(5)
	check(player.area_armed == "scepter_judgment" and player.ability == "" and is_equal_approx(Game.mp, jud_mp),
		"Julgamento de Luz: a tecla 5 só prepara a área (sem mana)")
	await wait(0.1)
	check(player._area_mark != null and player.global_position.distance_to(player.area_point) <= 18.5,
		"círculo da área no chão, dentro do alcance (%.1f m)" % player.global_position.distance_to(player.area_point))
	player.use_slot(5)
	check(player.area_armed == "" and player._area_mark == null and Game.mp >= jud_mp - 0.01, "a mesma tecla de novo desiste sem gastar")
	player.use_slot(5)
	jud_mp = Game.mp
	player.attacking = false
	Input.action_press("attack")   # clique esquerdo com a área preparada: confirma, não dá o ataque básico
	await wait_until(func(): return player.area_armed == "", 1.0)
	Input.action_release("attack")
	check(player.area_armed == "" and player.ability == "scepter_judgment", "clique esquerdo solta o Julgamento de Luz")
	check(not player.attacking, "o clique que confirma não dá o ataque básico")
	check(absf(jud_mp - Game.mp - 28.0) < 1.5 and player.cooldowns.scepter_judgment > 0.0, "Julgamento de Luz gasta 28 de mana e entra em recarga")
	check(not Game.has_buff("scepter_ward"), "Julgamento de Luz não dá o Escudo de Luz")
	await wait(0.7)
	check(player.ability == "", "Julgamento de Luz termina a pose")
	Game.mp = Game.max_mp()
	var ward_mp := Game.mp
	var maxhp0 := Game.max_hp()
	player.cast("scepter_ward")
	check(Game.has_buff("scepter_ward") and player.ability == "scepter_ward", "Escudo de Luz dá o buff e começa")
	check(is_equal_approx(Game.max_hp() - maxhp0, 30.0), "Escudo de Luz sobe a vida máx. em 30 (%.0f)" % (Game.max_hp() - maxhp0))
	check(is_equal_approx(ward_mp - Game.mp, 30.0) and player.cooldowns.scepter_ward > 0.0, "Escudo de Luz gasta 30 de mana e entra em recarga")
	await wait(0.7)
	check(player.ability == "", "Escudo de Luz termina a pose")
	Game.clear_buffs(true)
	_calm_bystanders([], player.global_position, 40.0, 6.0)   # com 5 de vida, qualquer golpe de fora derruba o teste
	Game.fury = 0.0
	player.cast("scepter_ult")
	check(not Game.has_buff("scepter_feast") and player.ability == "", "Banquete do Herói exige a fúria cheia")
	Game.fury = Game.FURY_MAX
	Game.hp = 5.0
	player.attacking = false
	player.dodge_timer = 0.0
	player.cast("scepter_ult")
	check(Game.has_buff("scepter_feast") and Game.fury == 0.0, "Banquete do Herói dá o buff e zera a fúria")
	check(is_equal_approx(Game.hp, Game.max_hp()), "Banquete do Herói cura por completo (%.0f)" % Game.hp)
	await wait(0.7)
	Game.clear_buffs(true)
	Game.level = lvl_hz
	Game.mp = Game.max_mp()
	player.ability = ""
	player.cast_timer = 0.0
	player.attacking = false
	player.combo_window = 0.0
	player.cast_timer = 0.0
	Game.stamina = Game.max_stamina()
	var orb_watch := _watch_spawns()
	player._start_swing()
	await wait_until(func(): return "light_orb" in orb_watch[0], 2.0)
	_stop_spawn_watch(orb_watch)
	check("light_orb" in orb_watch[0] and not ("bolt" in orb_watch[0]), "cetro dispara a esfera de luz")
	await wait(0.5)

	# arco: tensionar e soltar
	equip_any("short_bow")
	check(Game.equipment.weapon == "short_bow", "equipou arco")
	await wait(0.05)
	check(player.look["class"] == "bow" and player.look.arrow != null, "classe da arma: arco (com flecha encaixável)")
	player.attacking = false
	player.drawing = true
	player.draw_t = player.BOW_FULL
	check(player.bow_charge() >= 0.99, "arco totalmente tensionado")
	var arrow_watch := _watch_spawns()
	player.release_arrow()
	await wait_until(func(): return "arrow" in arrow_watch[0], 2.0)
	_stop_spawn_watch(arrow_watch)
	check("arrow" in arrow_watch[0], "arco dispara flecha")
	check(not player.drawing, "soltar encerra a tensão")

	# mão secundária combina com a arma
	Game.add_item("wooden_shield", 1, true)
	var refused := [""]
	var on_res := func(op: String, ok: bool, err: String) -> void:
		if op == "equip" and not ok:
			refused[0] = err
	var shields0 := Game.count_item("wooden_shield")   # o Doran também dá um, na história
	Econ.result.connect(on_res)
	equip_any("wooden_shield")
	Econ.result.disconnect(on_res)
	check(refused[0] == "exige_classe" and Game.equipment.offhand == "", "escudo recusado com arco (%s)" % refused[0])
	equip_any("iron_sword")
	equip_any("wooden_shield")
	check(Game.equipment.offhand == "wooden_shield", "escudo equipado com espada")
	var shield_mesh := player.model.find_child("Shield", true, false) as MeshInstance3D
	check(shield_mesh == null or shield_mesh.visible, "escudo aparece no modelo")
	# defesa com escudo: botão direito segurado levanta; golpe de frente custa fôlego (mais a cada golpe) e
	# passa só parte do dano; pelas costas entra cheio; sem fôlego a guarda quebra
	Input.action_press("aim")
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(player.blocking, "botão direito com escudo levanta o escudo")
	check(player.dodge_timer <= 0.0, "levantar o escudo não esquiva")
	var front := player.global_position + player.facing() * 2.0
	Game.stamina = Game.max_stamina()
	Game.hp = Game.max_hp()
	player.invuln = 0.0
	var hp_b := Game.hp
	var st_b := Game.stamina
	player.take_damage(20.0, front)
	var lost1 := hp_b - Game.hp
	var cost1 := st_b - Game.stamina
	check(cost1 > 0.0 and lost1 < 20.0 * 0.6, "golpe defendido gasta fôlego (%.1f) e segura dano (passou %.1f)" % [cost1, lost1])
	player.invuln = 0.0
	st_b = Game.stamina
	player.take_damage(20.0, front)
	check(st_b - Game.stamina > cost1 + 0.1, "2º golpe seguido custa mais fôlego (%.1f > %.1f)" % [st_b - Game.stamina, cost1])
	player.invuln = 0.0
	hp_b = Game.hp
	st_b = Game.stamina
	player.take_damage(20.0, player.global_position - player.facing() * 2.0)
	check(Game.stamina == st_b and hp_b - Game.hp > lost1, "golpe pelas costas não é defendido")
	player.invuln = 0.0
	Game.stamina = 1.0
	player.take_damage(20.0, front)
	check(player.guard_break_t > 0.0 and not player.blocking, "sem fôlego a guarda quebra")
	Input.action_release("aim")
	player.guard_break_t = 0.0
	Game.hp = Game.max_hp()
	Game.stamina = Game.max_stamina()
	await get_tree().physics_frame
	# combo com escudo (KnightMovesShield): 3 golpes do combo e o giro no fim, emendados segurando o clique
	check(player._shield_combo() and player._combo_len() == 4 and is_equal_approx(player._swing_time(4), 0.75),
		"espada com escudo: combo de 4 golpes, o último é o giro")
	player.attacking = false
	player.combo_window = 0.0
	player.dodge_timer = 0.0
	player.invuln = 6.0
	var spin_back := player.global_position   # os golpes empurram o jogador: volta aqui no fim
	var seen := []
	player._start_swing()
	var until := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < until:
		if player.attacking:
			if not (player.combo in seen):
				seen.append(player.combo)
			player.buffered_attack = player.combo < 4
			Game.stamina = Game.max_stamina()
		elif seen.size() >= 4 or seen.is_empty():
			break
		await get_tree().process_frame
	check(seen == [1, 2, 3, 4], "os 4 golpes do combo com escudo emendam (%s)" % [seen])
	check(not player.attacking and player._recover_t >= 0.0 and absf(float(player.parts.twist)) <= PI + 0.001,
		"no fim do combo o corpo volta suave à pose de parado (giro desenrolado: %.2f)" % float(player.parts.twist))
	await wait(0.5)
	check(player._recover_t < 0.0 and absf(float(player.parts.twist)) < 0.3,
		"volta do combo com escudo termina (giro %.2f)" % float(player.parts.twist))
	# o giro (4º) acerta em volta, até quem está atrás (um slime do teste, com vida de sobra, longe dos outros)

	var spin_spot := Vector3(-105, 0.3, 46)
	player.global_position = spin_spot
	player.model.rotation.y = 0.0   # olhando para +Z: o slime fica atrás
	var behind := Enemy.new()
	behind.kind = "slime"
	world.add_child(behind)
	behind.global_position = spin_spot + Vector3(0, 0, -1.3)
	behind.home = behind.global_position
	await wait(0.15)
	behind.max_hp = 9999.0
	behind.hp = 9999.0
	player.combo = 3
	player.combo_window = 0.3
	player.attacking = false
	Game.stamina = Game.max_stamina()
	player._start_swing()
	check(player.combo == 4, "4º golpe do combo com escudo é o giro")
	await wait(0.8)
	check(is_instance_valid(behind) and behind.hp < 9999.0,
		"giro do combo com escudo acerta quem está atrás (%.0f)" % (behind.hp if is_instance_valid(behind) else -1.0))
	if is_instance_valid(behind):
		behind.queue_free()
	player.global_position = spin_back
	player.invuln = 0.0
	Game.hp = Game.max_hp()
	Game.stamina = Game.max_stamina()
	equip_any("apprentice_staff")
	check(Game.equipment.offhand == "" and Game.count_item("wooden_shield") == shields0, "trocar para cajado guarda o escudo")
	equip_any("iron_sword")
	check(not player._shield_combo() and player._combo_len() == 3, "sem escudo, o combo da espada volta a 3 golpes")
	check(is_equal_approx(Game.melee_damage(), dmg_sword), "dano da espada volta ao trocar de volta")

	# armaduras: defesa e bônus somam
	var def0 := Game.defense()
	var hp0 := Game.max_hp()
	Game.add_item("leather_boots", 1, true)
	Game.add_item("life_amulet", 1, true)
	var prev := Game.preview_equip("life_amulet")
	check(prev.get("hp", 0.0) > 0.0, "comparação prevê +vida do amuleto (%+.0f)" % prev.get("hp", 0.0))
	equip_any("leather_cap")
	equip_any("leather_boots")
	equip_any("life_amulet")
	check(Game.defense() > def0, "capuz e botas aumentam a defesa (%.1f -> %.1f)" % [def0, Game.defense()])
	check(Game.max_hp() > hp0 and Game.attr("vit") == Game.attributes.vit + 1, "amuleto dá vida e vitalidade")
	check(Game.speed_multiplier() > 1.0, "botas dão velocidade")
	Game.sort_inventory()
	check(ItemDB.category(Game.inventory[0].id) == "equip", "organizar coloca equipamentos primeiro")

	# telas novas abrem
	world._open_menu(0)
	await wait(0.15)
	var m = world.modal
	check(m != null and m.equip_slots.size() == 9 and m.bag_slots.size() >= 48, "inventário com boneco (9 espaços) e grade")
	check(m.tool_slots.size() == 2 and m.tool_slots.pickaxe.item_id == Game.equipment.get("pickaxe", ""),
		"aba Ferramentas da página do herói com os espaços da picareta e do machado")
	check(m.gear_view.visible and not m.tools_view.visible, "Inventário abre na aba Equipamento")
	m._set_side_tab("tools")
	await wait(0.05)
	check(m.tools_view.visible and not m.gear_view.visible and m.tool_slots.pickaxe.visible and not m.equip_slots.head.visible,
		"aba Ferramentas troca os espaços em volta do boneco (a mochila fica)")
	check(m.hero_preview.weapon_override == Game.equipment.get("pickaxe", ""), "na aba Ferramentas o boneco segura a picareta")
	m._set_side_tab("equip")
	check(m.equip_slots.head.item_id == "leather_cap", "boneco mostra o capuz equipado")
	var book: BookWindow = m.book
	check(book != null and book.side == "right" and m.pages.size() == 1 and world.dock.at("right") == m,
		"inventário abre na janela da direita")
	await wait(0.1)
	var inv_page: Rect2 = m.pages[0].get_global_rect()
	check(book.content_rect().grow(1.0).encloses(inv_page),
		"inventário cabe inteiro na janela, sem rolar (%s em %s)" % [inv_page, book.content_rect()])
	# janela do herói (C) abre à esquerda sem fechar o inventário, e as duas não se sobrepõem
	world._open_menu(1)
	await wait(0.15)
	var h = world.modal
	check(h != m and h.mode == "hero" and world.dock.at("left") == h and world.dock.at("right") == m and is_instance_valid(m),
		"janela do herói abre à esquerda com o inventário aberto à direita")
	check(not h.book._frame.get_global_rect().intersects(m.book._frame.get_global_rect()),
		"janelas do herói e do inventário não se sobrepõem (%s | %s)" % [h.book._frame.get_global_rect(), m.book._frame.get_global_rect()])
	# arrastar: a janela do herói solta por cima do inventário encosta ao lado dele, e reabre onde ficou
	var hf: Control = h.book.frame()
	var mf: Control = m.book.frame()
	hf.set_meta("_user_pos", mf.position - Vector2(200, 0))
	h.book._layout()
	check(hf.get_global_rect().intersects(mf.get_global_rect()), "janela arrastada por cima do inventário (antes de soltar)")
	world.dock.resolve(hf)
	await wait(0.05)
	check(not hf.get_global_rect().grow(-1.0).intersects(mf.get_global_rect())
		and Rect2(Vector2.ZERO, hf.get_viewport_rect().size).encloses(hf.get_global_rect()),
		"ao soltar, a janela encosta ao lado da outra sem sair da tela (%s | %s)" % [hf.get_global_rect(), mf.get_global_rect()])
	hf.remove_meta("_user_pos")
	h.book._layout()
	for i in h.pages.size():
		h._show_tab(i)
		await wait(0.1)
		var area: Rect2 = h.book.content_rect().grow(1.0)
		var pr: Rect2 = h.pages[i].get_global_rect()
		check(area.position.x <= pr.position.x and pr.end.x <= area.end.x and h.book.page_width == h.TAB_WIDTHS[i],
			"aba %d dentro da janela, na largura dela (%.0f de %.0f)" % [i, pr.size.x, h.book.page_width])
		if h.pages[i] is HBoxContainer:   # abas em duas colunas: uma não invade a outra
			var halves: Array = h.pages[i].get_children()
			var lr: Rect2 = halves[0].get_global_rect()
			var rr: Rect2 = halves[1].get_global_rect()
			check(lr.end.x <= rr.position.x, "aba %d: colunas lado a lado sem se cruzar" % i)
	check(h.book.overflow_warnings == 0 and book.overflow_warnings == 0, "nenhuma aba pede mais largura do que a janela tem")
	# o atalho da aba aberta fecha a janela; o inventário fica
	world.toggle_window("character")
	world.toggle_window("character")
	await wait(0.05)
	check(world.dock.at("left") == null and world.dock.at("right") == m and world.modal == m, "C de novo fecha só a janela do herói")
	world._open_menu(1)
	await wait(0.1)
	h = world.modal
	var plain_tip := ItemTooltip.new()
	check(m.tooltip.paper and not plain_tip.paper, "dica de item: papel no livro, escura por padrão")
	plain_tip.free()
	var tip_paper := ItemTooltip.build_text("leather_cap", "bag", true)
	var tip_dark := ItemTooltip.build_text("leather_cap", "bag")
	check(tip_paper != tip_dark and not tip_paper.contains(UITheme.GOOD.to_html(false))
		and not tip_paper.contains(UITheme.DIM.to_html(false)), "dica de papel não usa as cores claras do tema escuro")
	await _test_compare(m)
	# Personagem, Missões e Profissões a tinta: nenhum painel escuro nem texto claro
	for i in [0, 2, 3]:
		h._show_tab(i)
		await wait(0.1)
		check(_light_text(h.pages[i]) == "", "aba %d sem texto claro nem painel escuro%s" % [i, _light_text(h.pages[i])])
	m._close()
	await wait(0.05)
	m = h
	# gastar um ponto de atributo pelo botão "+" da aba Personagem
	m._show_tab(0)
	if Game.stat_points <= 0:
		Game.add_xp(Game.xp_to_next())   # sobe um nível para ter ponto a gastar
	await wait(0.1)
	var str0: int = Game.attributes.str
	var pts0: int = Game.stat_points
	var plus: Button = m.attr_buttons["str"]
	check(not plus.disabled, "botão + de Força ligado com ponto sobrando")
	plus.pressed.emit()
	await wait(0.1)
	check(Game.attributes.str == str0 + 1 and Game.stat_points == pts0 - 1, "botão + da aba Personagem gasta o ponto em Força")
	check(m.attr_values["str"].text == str(Game.attr("str")), "aba Personagem mostra o novo valor de Força")
	check(m.attr_buttons["str"].disabled == (Game.stat_points <= 0), "botão + desliga quando os pontos acabam")
	# selecionar uma missão troca os detalhes
	m._show_tab(2)
	var fake_quest := not Game.quests.has("goblins")
	if fake_quest:   # segunda missão só no espelho da tela (o estado de verdade fica no Econ)
		Game.quests["goblins"] = {"state": "active", "progress": 1}
	m._refresh()
	await wait(0.1)
	check(m.quest_buttons.size() == Game.quests.size() and Game.quests.size() >= 2,
		"diário lista todas as missões (%d)" % m.quest_buttons.size())
	for qid in Game.quests.keys():
		m.quest_buttons[qid].pressed.emit()
		await wait(0.1)
		check(m.quest_sel == qid and m.quest_title.text == ItemDB.QUESTS[qid].name and m.quest_buttons[qid].button_pressed,
			"selecionar a missão %s troca os detalhes" % qid)
	if fake_quest:
		Game.quests.erase("goblins")
	await _test_talent_tab(m)
	# sem janela não se fotografa nada, mas o ícone assado no build (assets/ui/item_icons) vale do mesmo jeito
	check(not ItemIcons.enabled() and ItemIcons.icon("leather_cap", Callable()) == ItemIcons.baked("leather_cap")
		and ItemIcons.baked("leather_cap") != null, "sem janela, o ícone assado do item aparece (sem foto ao vivo)")
	check(ItemIcons.icon("health_potion", Callable()) == null, "sem janela, item de família também cai no ícone pintado")
	var no_icon: Array[String] = []
	for id: String in ItemDB.ITEMS:
		if not ItemIcons._has_model(id) and ItemSlot.item_art(id) == null:
			no_icon.append(id)
	check(no_icon.is_empty(), "todo item tem arte pintada ou modelo para o ícone 3D (sem: %s)" % ", ".join(no_icon))
	check(ItemSlot.item_art("health_potion") != null and not ItemIcons._has_model("health_potion"),
		"item com arte pintada usa a arte e não é fotografado em 3D")
	m._close()
	await wait(0.05)
	world.open_shop()
	await wait(0.1)
	check(world.modal != null and world.modal.buy_grid.get_child_count() > 10, "loja mostra a grade de mercadorias")
	var shop_inv = world.dock.at("right")
	check(shop_inv != null and shop_inv.trade == world.modal and shop_inv.bag_slots[0].context == "sell",
		"loja abre o inventário ao lado, e nele o clique direito vende")
	world.modal._close()
	await wait(0.05)
	check(world.modal == null and (not is_instance_valid(shop_inv) or shop_inv.is_queued_for_deletion()),
		"fechar a loja fecha o inventário que ela abriu")


## Aba Talentos (Guerreiro): aprende pelo botão e vê x/3, linha bloqueada apagada; a Lina redistribui e
## devolve os pontos (cobra 50 x nível acima do 5).
func _test_talent_tab(m) -> void:
	check(m.TAB_NAMES[1] == "Talentos" and m.TAB_ACTIONS[1] == "talents", "aba Talentos ao lado de Personagem (K)")
	check(InputMap.has_action("talents"), "atalho K da aba Talentos")
	while Game.talent_points() < 2:
		Game.add_xp(Game.xp_to_next())
	m._show_tab(1)
	await wait(0.15)
	var tp = m.talent_panel
	check(tp != null and tp.buttons.size() == 9, "aba Talentos mostra os 9 talentos da classe")
	if tp == null or tp.buttons.size() != 9:
		return
	var pts0 := Game.talent_points()
	check(tp.points_label.text.contains(str(pts0)), "pontos livres no topo (%s)" % tp.points_label.text)
	check(tp.level_labels["w_edge"].text == "0/3" and not tp.buttons["w_edge"].disabled, "linha 1 aberta em 0/3")
	check(tp.buttons["w_bloodlust"].disabled and tp.slots["w_bloodlust"].dim, "linha 2 bloqueada: botão desligado e ícone apagado")
	check(tp.buttons["w_edge"].tooltip_text.contains("dano"), "dica do talento com a descrição")
	tp.buttons["w_edge"].pressed.emit()
	await wait(0.1)
	check(Game.talents.get("w_edge", 0) == 1 and Game.talent_points() == pts0 - 1,
		"botão aprende o talento (%s, %d pontos)" % [Game.talents, Game.talent_points()])
	check(tp.level_labels["w_edge"].text == "1/3", "aba mostra 1/3 (%s)" % tp.level_labels["w_edge"].text)
	check(is_equal_approx(float(Game.talent_mods.get("damage", 0.0)), 0.04), "talento já vale: dano +4%")
	check(tp.reset_label.text.contains("Lina"), "aba diz onde redistribuir (%s)" % tp.reset_label.text)
	check(m.book.overflow_warnings == 0, "aba Talentos cabe na janela")
	check(_light_text(m.pages[1]) == "", "aba Talentos a tinta%s" % _light_text(m.pages[1]))
	# redistribuir pela Lina: a opção está nos serviços dela e cobra 50 x nível (grátis até o 5)
	var cost := Game.talent_reset_cost()
	if Game.gold < cost:
		Econ.grant(cost, 0, {}, "teste", true)
	var gold0 := Game.gold
	check(_interactable("lina") != null, "Lina na vila")
	var reset: Dictionary = {}
	for ch in StoryDialogue._services("lina"):
		if str(ch.text) == "Redistribuir talentos":
			for sub in ch.get("pages", []):
				for c2 in sub.get("choices", []):
					if str(c2.text).begins_with("Redistribuir") and c2.get("action", Callable()).is_valid():
						reset = c2
	check(not reset.is_empty(), "Lina oferece redistribuir os talentos")
	if not reset.is_empty():
		reset.action.call()
	await wait(0.1)
	check(Game.talents.is_empty() and Game.talent_points() == pts0 and Game.gold == gold0 - cost,
		"redistribuir devolve os pontos e cobra %d (%s, %d pontos, ouro %d -> %d)" % [cost, Game.talents, Game.talent_points(), gold0, Game.gold])
	check(tp.level_labels["w_edge"].text == "0/3", "aba volta a 0/3 depois de redistribuir")


## Procura, numa página do livro, texto claro (ilegível sobre papel) ou painel de fundo escuro.
## Devolve "" se estiver tudo a tinta, ou a descrição do primeiro problema.
## Shift sobre um item equipável abre ao lado a ficha do item equipado naquele espaço.
func _test_compare(m) -> void:
	var worn := str(Game.equipment.get("weapon", ""))
	var slot: ItemSlot = null
	for s in m.bag_slots:
		if s.item_id != "" and s.item_id != worn and ItemDB.slot_of(s.item_id) == "weapon":
			slot = s
			break
	check(worn != "" and slot != null, "há arma equipada e outra na mochila para comparar")
	if slot == null:
		return
	check(ItemTooltip.compare_target(slot.item_id, "bag") == worn and ItemTooltip.compare_target(worn, "equip") == ""
		and ItemTooltip.compare_target("health_potion", "bag") == "", "comparar: só item equipável contra o equipado no mesmo espaço")
	var tip: ItemTooltip = m.tooltip
	tip.show_for(slot)
	tip.set_process(false)   # sem Shift de verdade, o próximo quadro fecharia a ficha
	tip._update_compare(true)
	await wait(0.05)
	check(tip._cmp.visible and tip._cmp_text.text.contains(ItemDB.get_item(worn).name)
		and not tip._cmp.get_global_rect().intersects(tip.get_global_rect()),
		"com Shift a ficha do equipado abre ao lado da dica, sem cobrir (%s, %s | %s)" % [tip._cmp.visible,
			tip._cmp.get_global_rect(), tip.get_global_rect()])
	tip._update_compare(false)
	check(not tip._cmp.visible, "soltar Shift fecha a ficha do equipado")
	tip.hide_for(slot)
	tip.set_process(true)


func _light_text(node: Node) -> String:
	if node is Label and node.is_visible_in_tree() and node.text != "":
		var c: Color = node.get_theme_color("font_color")
		if c.get_luminance() > 0.45:
			return " (texto claro: \"%s\")" % node.text
	if node is PanelContainer:
		var sb := node.get_theme_stylebox("panel") as StyleBoxFlat
		if sb and sb.bg_color.a > 0.5 and sb.bg_color.get_luminance() < 0.2 and sb.bg_color != UITheme.INK:
			return " (painel escuro em %s)" % node.get_path()
	for c in node.get_children():
		var r := _light_text(c)
		if r != "":
			return r
	return ""


## Corpo feminino: o modelo do jogador segue Game.body (knight_f.glb + roupas _f); trocar arma e armadura
## mantém o corpo. O penteado (padrão f_longo, com rabo de cavalo) some sob o gorro e vem rente sob o capuz.
func _test_female_body() -> void:
	var body0 := Game.body
	var eq0: Dictionary = Game.equipment.duplicate()
	var want0 := "f" if body0 == "f" else "m"
	check(KnightLook.body_of(player.model) == want0, "o modelo do jogador é o do corpo escolhido (%s)" % want0)
	for sl in ["head", "armor", "hands", "feet"]:
		if Game.equipment.get(sl, "") != "":
			Game.unequip(sl)
	Econ.test_force_body("f")
	await wait(0.1)
	var m: Node3D = player.model
	check(KnightLook.body_of(m) == "f" and m.find_child("Gear_Ponytail", true, false) != null, "corpo feminino carrega o knight_f.glb")
	check(m.find_child("Gear_HairLong", true, false) != null and m.find_child("Gear_HairLock00", true, false) == null,
		"sem armadura: cabeça e roupas femininas (h_bare_f) com o penteado padrão")
	check(player.parts.Head != null and player.parts.Head.is_inside_tree() and player.cape != null, "esqueleto e capa refeitos no corpo novo")
	var need := {}
	for id in ["leather_cap", "ranger_hood", "guard_surcoat", "short_bow"]:
		if Game.count_item(id) == 0:
			need[id] = 1
	Econ.grant(0, 0, need, "test", true)
	equip_any("leather_cap")
	equip_any("guard_surcoat")
	await wait(0.1)
	check(player.model == m and KnightLook.body_of(player.model) == "f", "trocar armadura mantém o corpo feminino")
	check(m.find_child("Gear_LashL", true, false) != null, "elmo aberto feminino (h_cap_f, com cílios)")
	check(m.find_child("Gear_Ponytail", true, false) == null and m.find_child("Gear_HairLong", true, false) == null,
		"gorro justo sem cabelo (o cabelo atravessaria)")
	equip_any("ranger_hood")
	await wait(0.1)
	check(m.find_child("Gear_Ponytail", true, false) != null and m.find_child("Gear_HairLong", true, false) != null,
		"capuz com o penteado inteiro, rente (rabo de cavalo por fora)")
	equip_any("short_bow")
	await wait(0.1)
	check(player.model == m and KnightLook.body_of(player.model) == "f" and player.look["class"] == "bow"
		and player.look.holder != null and is_instance_valid(player.look.holder), "trocar a arma mantém o corpo feminino")
	for sl in ["head", "armor"]:
		Game.unequip(sl)
	for sl in ["weapon", "head", "armor", "hands", "feet"]:
		if str(eq0.get(sl, "")) != "":
			equip_any(eq0[sl])
	Econ.test_force_body(body0)
	await wait(0.1)
	check(KnightLook.body_of(player.model) == want0 and (want0 == "f") == (player.model.find_child("Gear_Ponytail", true, false) != null),
		"corpo de volta ao escolhido (%s)" % want0)


## Tela de criação: personagem sem classe passa por ela; escolher arqueiro dá o arco e trava a espada.
func _test_char_create() -> void:
	check(Game.harness_class(PackedStringArray(["--smoketest", "--class=archer"])) == ["archer", "m", ""]
		and Game.harness_class(PackedStringArray(["--body=f", "--class=healer"])) == ["healer", "f", ""],
		"--class= e --body= pedem a classe e o corpo")
	check(Game.harness_class(PackedStringArray(["--body=f", "--class=mage", "--hair=f_chanel"])) == ["mage", "f", "f_chanel"]
		and Game.harness_class(PackedStringArray(["--class=mage", "--hair=f_chanel"])) == ["mage", "m", ""],
		"--hair= pede o penteado, só se for do corpo")
	check(Game.harness_class(PackedStringArray(["--smoketest"])) == ["warrior", "m", ""]
		and Game.harness_class(PackedStringArray([])) == ["", "m", ""], "testes sem --class= são guerreiros; o jogo normal mostra a tela")
	check(Game.entry_scene() == Game.WORLD_SCENE, "personagem com classe entra direto no mundo")
	Econ.start_scratch_solo("user://smoketest_create.json", false)
	check(Game.char_class == "" and Game.equipment.weapon == "", "personagem novo começa sem classe e sem arma")
	check(Game.entry_scene() == Game.CHAR_CREATE_SCENE, "sem classe a entrada abre a tela de criação")
	check(not Game.is_old_character(), "personagem novo não conta como antigo (poções iniciais não contam)")
	var cc = load(Game.CHAR_CREATE_SCENE).instantiate()
	cc.enter_world = false
	get_tree().root.add_child(cc)
	await wait(0.2)
	check(cc.title_label.text == "Crie seu herói" and not cc.old_note.visible, "título de herói novo, sem aviso de arma")
	check(cc.cards.size() == 4, "quatro cartões de classe (%d)" % cc.cards.size())
	var emb_ok := true
	for id in cc.cards:
		emb_ok = emb_ok and cc.cards[id].find_children("*", "ClassEmblem", true, false).size() == 1
	check(emb_ok, "cada classe da coluna tem o seu emblema")
	check(cc.hair_picker.buttons.size() == 4, "quatro miniaturas de penteado (%d)" % cc.hair_picker.buttons.size())
	cc.select_class("healer")
	var kit: Array = ItemDB.kit("scepter")
	var icons_ok: bool = cc.skill_strip.slots.size() == kit.size()
	for i in kit.size():   # arte pintada da própria habilidade; o desenho do IconPainter fica de reserva
		icons_ok = icons_ok and cc.skill_strip.slots[i].icon_tex == ItemSlot.skill_art(kit[i]) \
			and cc.skill_strip.slots[i].icon_kind == str(ItemDB.ABILITIES[kit[i]].icon)
	check(icons_ok, "healer: um ícone por habilidade, arte dela ou desenho de reserva (%d)" % cc.skill_strip.slots.size())
	check(cc.skill_strip.slots[0].icon_tex != null and "Cura" in cc.skill_strip.detail_text(),
		"primeira habilidade com arte pintada e detalhe aberto (%s)" % cc.skill_strip.detail_text())
	for t in ["Ab", "Ana Luz", "Abcdefghijklmnopq", ""]:
		check(not cc._name_rule(t)[0], "nome recusado: '%s' (%s)" % [t, cc._name_rule(t)[1]])
	check(cc._name_rule("Ayla")[0], "nome aceito: Ayla")
	cc.select_class("archer")
	check(cc.preview.weapon_override == "short_bow", "prévia mostra o arco inicial sem equipar")
	var kit_ok := true
	for id in ItemDB.kit("bow"):
		kit_ok = kit_ok and str(ItemDB.ABILITIES[id].name) in cc.kit_names()
	check(kit_ok and cc.class_name_label.text == "Arqueiro", "detalhe do arqueiro lista as habilidades do kit")
	cc.select_body("f")
	check(cc.body == "f" and KnightLook.body_of(cc.preview.model) == "f"
		and cc.preview.model.find_child("Gear_Ponytail", true, false) != null, "Feminino troca a prévia para o corpo feminino")
	check(cc.preview.model.find_child("Gear_HairLong", true, false) != null, "prévia feminina com o cabelo comprido")
	var f_ids: Array = cc.hair_picker.buttons.keys()
	check(f_ids == HairStyles.STYLES["f"] and cc.hair == HairStyles.default_for("f")
		and cc.hair_picker.buttons[cc.hair].button_pressed, "Feminino: miniaturas do corpo feminino, padrão marcado (%s)" % [f_ids])
	cc.hair_picker.buttons["f_marias"].emit_signal("pressed")
	check(cc.hair == "f_marias" and cc.preview.hair_override == "f_marias", "miniatura troca o cabelo do herói")
	cc.body_buttons["f"].emit_signal("pressed")   # clicar de novo no sexo já escolhido
	check(cc.hair == "f_marias", "clicar no sexo já escolhido não perde o penteado (%s)" % cc.hair)
	var head_before: String = Game.equipment.get("head", "")
	Game.equipment["head"] = "guard_greathelm"   # elmo fechado esconde o cabelo no jogo
	cc.select_body("m")
	cc.select_body("f")
	await wait(0.1)
	var thumb: CharPreview = cc.hair_picker.buttons["f_longo"].find_children("*", "CharPreview", true, false)[0]
	check(thumb.model.find_child("Gear_HairLong", true, false) != null,
		"miniatura mostra o penteado sem o elmo equipado")
	Game.equipment["head"] = head_before
	for i in 3:   # trocar de corpo várias vezes não deixa miniatura sobrando
		cc.select_body("m")
		cc.select_body("f")
	await wait(0.1)
	check(cc.hair_picker.get_child_count() == 4 and cc.hair == HairStyles.default_for("f"),
		"trocar o corpo várias vezes: 4 miniaturas e o penteado padrão (%d)" % cc.hair_picker.get_child_count())
	cc.select_body("m")
	check(cc.body == "m" and KnightLook.body_of(cc.preview.model) == "m"
		and cc.preview.model.find_child("Gear_Ponytail", true, false) == null, "Masculino volta a prévia para o corpo masculino")
	cc._start()
	await wait(0.1)
	check(cc.finished and Game.char_class == "archer" and Game.body == "m" and Game.equipment.weapon == "short_bow",
		"Começar: arqueiro com o arco equipado (%s, %s)" % [Game.char_class, Game.equipment.weapon])
	cc.queue_free()
	var notes: Array = []
	var cb := func(t: String, _c: Color) -> void: notes.append(t)
	Game.notify.connect(cb)
	Econ.grant(5000, 0, {"azure_edge": 1}, "test", true)   # ouro: na loja, só a classe apaga a arma
	Game.equip("azure_edge")
	Game.notify.disconnect(cb)
	check(Game.equipment.weapon == "short_bow" and "Gume Celeste é arma de Guerreiro." in notes,
		"espada da mochila recusada com aviso (%s)" % [notes])
	check(not Game.can_wield("azure_edge") and Game.can_wield("short_bow") and Game.can_wield("health_potion"),
		"arqueiro só empunha arco")
	check(ItemTooltip.build_text("azure_edge", "buy").contains("Arma de Guerreiro"), "dica da loja marca arma de outra classe")
	world.open_shop()
	await wait(0.2)
	var sword_dim := false
	var bow_dim := true
	for sl in world.modal.buy_grid.get_children():
		if sl.item_id == "azure_edge":
			sword_dim = sl.dim
		elif sl.item_id == "short_bow":
			bow_dim = sl.dim
	check(sword_dim and not bow_dim, "loja apaga a espada e deixa o arco")
	world.modal._close()
	await wait(0.1)
	world._open_menu(0)
	await wait(0.2)
	var m = world.modal
	for i in Game.inventory.size():
		if Game.inventory[i].id == "azure_edge":
			m.sel_index = i
	m._refresh_selection()
	check(m.use_btn.disabled and m.use_btn.text == "Equipar", "inventário desabilita Equipar para a espada")
	m._close()
	await wait(0.1)
	check(Game.is_old_character(), "com equipamento conta como personagem antigo")
	Econ.start_scratch_solo("user://smoketest_create.json", false)
	Econ.grant(0, 0, {"iron_sword": 1}, "test", true)
	var old = load(Game.CHAR_CREATE_SCENE).instantiate()
	old.enter_world = false
	get_tree().root.add_child(old)
	await wait(0.2)
	check(old.title_label.text == "Escolha sua classe" and old.old_note.visible, "personagem antigo: Escolha sua classe e aviso da arma")
	old.queue_free()


## Escolhe cartas de nível enquanto houver; se check_weapon, confere que a arma escolhida subiu.
func _pick_levelups(check_weapon: bool) -> void:
	var first := true
	while world.modal != null and world.modal.get("mode") == "levelup":
		await wait(0.45)
		var m = world.modal
		var idx := 0
		for i in m.choices.size():
			if m.choices[i].type == "weapon":
				idx = i
		var ch: Dictionary = m.choices[idx]
		var sv = world.survival
		var before: int = sv.weapon_levels.get(ch.id, 0) if ch.type == "weapon" else sv.passive_levels.get(ch.id, 0)
		m._pick(idx)
		await wait(0.15)
		if check_weapon and first:
			var after: int = sv.weapon_levels.get(ch.id, 0) if ch.type == "weapon" else sv.passive_levels.get(ch.id, 0)
			check(after == before + 1, "carta escolhida aplicada (%s %d -> %d)" % [ch.id, before, after])
		first = false


## Alvo com a vida de hoje (data.hp, cheia): os monstros do vale nascem com nível sorteado na faixa do ponto,
## e a vida muda com o nível. As checagens de dano contam com a vida do tipo, não com a do nível sorteado.
## Atordoa (sem andar nem golpear por `t` s) os monstros a até `radius` de `center` que não são alvos do teste:
## a checagem fica só com os próprios alvos, sem depender de quem passa por perto.
func _calm_bystanders(keep: Array, center: Vector3, radius: float, t: float) -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e.dead and not (e in keep) and e.global_position.distance_to(center) < radius:
			e.apply_stun(t)


func _today(e: Enemy) -> Enemy:
	e.max_hp = float(e.data.hp)
	e.hp = e.max_hp
	return _target(e)


## O monstro vivo de `kind` mais perto do jogador; com `area`, só os que nasceram naquela região com nome (as
## missões com "region" só contam esses).
## Guarda da vila: nenhum ponto de monstro perto da cerca, guardas nos postos, e o monstro que entra é abatido
## pela guarda sem dar XP, ouro, loot nem missão (nem a quem já tinha acertado nele).
func _test_village_guard() -> void:
	var near_gate: Array = []
	for en in get_tree().get_nodes_in_group("enemies"):
		if VillageWard.distance(en.home) < VillageWard.SPAWN_CLEARANCE - 6.0:
			near_gate.append("%s %s" % [en.kind, en.home])
	check(near_gate.is_empty(), "nenhum monstro mora colado na vila %s" % str(near_gate))
	var back := player.global_position
	var guards := get_tree().get_nodes_in_group("npc").filter(func(n: Node) -> bool: return n is VillageGuard)
	check(guards.size() >= 8, "guardas nos portões e cantos da vila (%d)" % guards.size())
	var intruder := _nearest("goblin")
	var xp0 := Game.xp
	var lvl0 := Game.level
	var gold0 := Game.gold
	var prog0 := JSON.stringify(Game.quests)
	var pickups0 := _count_pickups()
	player.global_position = Vector3(2, 0.3, 6)
	intruder.take_damage(1.0, player.global_position, false)   # o jogador acertou antes: mesmo assim não leva nada
	intruder.global_position = Vector3(4, 0.5, 76)   # na praça da feira
	await wait_until(func() -> bool: return intruder.dead, VillageWard.DOOM + 2.0)
	check(intruder.dead, "goblin que entra na vila é abatido pela guarda")
	await wait(0.3)
	check(Game.xp == xp0 and Game.level == lvl0, "abate da guarda não dá XP")
	check(Game.gold == gold0 and _count_pickups() == pickups0, "abate da guarda não dá ouro nem saque")
	check(JSON.stringify(Game.quests) == prog0, "abate da guarda não conta em missão")
	# monstro do lado de fora não entra atrás do jogador: para na cerca
	var chaser := _today(_nearest("slime"))
	player.global_position = Vector3(0, 0.3, 40)   # na estrada entre a Horta e o portão norte
	chaser.global_position = Vector3(0, 0.5, 8)
	chaser._set_state("chase")
	await wait(2.0)
	check(not chaser.dead and not VillageWard.inside(chaser.global_position, VillageWard.KILL_MARGIN),
		"slime para na cerca e não entra atrás do jogador (z %.1f)" % chaser.global_position.z)
	player.global_position = back   # os testes seguintes trazem monstros para perto do jogador: fora da vila
	player.velocity = Vector3.ZERO
	await wait(0.1)


func _count_pickups() -> int:
	var n := 0
	for c in world.get_children():
		if c.get_script() == Enemy.PICKUP:
			n += 1
	return n


## Põe o monstro onde a linha da mira passa a meia altura dele. As flechas voam na linha da câmera, que fica
## sobre o ombro direito (uns 45 cm ao lado do jogador) e olha para baixo: a linha chega ao chão uns 5,4 m à
## frente. Com o alvo 6 m bem na frente do jogador a flecha passava na beira dele (raio 0,5 m) ou caía no chão
## pouco antes, e só acertava se ele andasse para o lado certo.
## Usa a posição da câmera em relação ao jogador, que não depende de a câmera já ter seguido um teleporte.
func _on_aim_line(e: Enemy) -> void:
	var f: Vector3 = -player.camera.global_basis.z
	var ground: float = e.home.y - 0.2   # os monstros nascem 0,2 m acima do chão; o jogador é posto no ar e assenta
	var feet := Vector3(player.global_position.x, ground, player.global_position.z)
	var cam: Vector3 = feet + Vector3.UP * 1.55 + (player.camera.global_position - player.cam_yaw.global_position)
	var mid: float = ground + 0.5   # meia altura do corpo
	var t: float = (cam.y - mid) / maxf(-f.y, 0.05)
	var at: Vector3 = cam + f * t
	e.global_position = Vector3(at.x, e.home.y, at.z)
	# segura o alvo no ponto da mira (as mãos sombrias: não anda nem ataca, mas leva dano, empurrão e efeitos): o
	# slime anda 2,8 m/s, e na tensão do arco (~0,4 s) chegava ~1 m mais perto; a mira, que desce da câmera, passava
	# por cima da cabeça dele e o Tiro Triplo e a Flecha Glacial falhavam no CI de vez em quando (vida intacta)
	e.velocity = Vector3.ZERO
	e.held_t = 3.0


## Corredor da Investida livre de cenário (camadas 1 e 8, as que param o jogador além dos monstros): de 9 m ao sul a 3 m ao norte do ponto do monstro (o teste investe
## de +3 m para -Z atravessando o monstro e depois de +3 m para +Z), na largura do jogador.
func _lane_clear(e: Enemy) -> bool:
	var space := player.get_world_3d().direct_space_state
	for dx in [-0.6, 0.0, 0.6]:
		var a: Vector3 = e.home + Vector3(dx, 0.6, 9.0)
		var b: Vector3 = e.home + Vector3(dx, 0.6, -3.0)
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, 1 | 8)).is_empty():
			return false
	return true


## Como _nearest, mas só entre os monstros com o corredor da Investida livre: o "slime (Campos) 5" tem um
## carvalho 1,5 m ao sul do ponto dele, e a Investida parava na árvore quando ele era o mais perto.
func _nearest_clear_lane(kind: String) -> Enemy:
	var best: Enemy = null
	var bd := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.kind == kind and not e.dead and _lane_clear(e):
			var d: float = e.global_position.distance_to(player.global_position)
			if d < bd:
				bd = d
				best = e
	return _target(best) if best != null else _nearest(kind)


## Atordoa por `secs` todo monstro vivo a até `radius` m de `at`, alvo do teste ou não.
func _hush_around(at: Vector3, radius: float, secs: float) -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e.dead and e.global_position.distance_to(at) < radius:
			e.apply_stun(secs)


func _nearest(kind: String, area := "") -> Enemy:
	var best: Enemy = null
	var bd := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.kind == kind and not e.dead and (area == "" or e.area == area):
			var d: float = e.global_position.distance_to(player.global_position)
			if d < bd:
				bd = d
				best = e
	return _target(best)


func _count(kind: String) -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.kind == kind:
			n += 1
	return n


## Forjador Rúnico (chefe das Galerias Profundas): a Martelada acerta quem está no cone e deixa as faixas de metal
## derretido (que queimam quem pisa), o Respiro da Fornalha queima quem está colado, o Escudo Rúnico deixa ele
## imune e só cai com as 3 runas quebradas (e ele segue atacando), e abaixo de metade da vida ele superaquece:
## golpes mais rápidos, mais faixas e mais dano recebido.
func _test_forjador() -> void:
	var back := player.global_position
	var spot := Vector3(-105, 0.3, 40)
	player.global_position = spot
	Game.hp = Game.max_hp()
	var e := Enemy.new()
	e.kind = "forjador_runico"
	world.add_child(e)
	e.global_position = spot + Vector3(0, 0, -5)
	e.home = e.global_position
	await wait(0.2)
	check(e.is_boss and e.parts.get("Hammer") != null and e.parts.get("KneeL") != null and e.parts.get("ElbowR") != null
		and e.parts.get("Door") != null, "Forjador: chefe, com martelo, joelhos, cotovelos e a porta da fornalha no modelo")
	# Martelada: o jogador está a 5 m, na frente
	var hp0: float = Game.hp
	e._forge_n = 0
	e.attack_cd = 0.0
	e._set_state("chase")
	await wait_until(func(): return e.state == "attack", 2.0)
	check(e.attack_kind == "hammer", "Forjador: ataca com a Martelada (%s)" % e.attack_kind)
	check(ForgeRules.in_cone(e._forge_origin, e._forge_dir, player.global_position), "Forjador: o cone aponta para o alvo")
	await wait_until(func(): return Game.hp < hp0, 3.0)
	check(Game.hp < hp0, "Forjador: a Martelada acerta quem está no cone (%.0f -> %.0f)" % [hp0, Game.hp])
	var trails := _forge_trails()
	check(trails.size() == ForgeRules.TRAILS, "Forjador: a Martelada deixa as faixas de metal derretido (%d)" % trails.size())
	# a faixa do meio passa debaixo do jogador: queima enquanto ele fica em cima
	Game.hp = Game.max_hp()
	var hp1: float = Game.hp
	await wait_until(func(): return Game.hp < hp1, 2.5)
	check(Game.hp < hp1, "Forjador: o metal derretido queima quem pisa (%.0f -> %.0f)" % [hp1, Game.hp])
	await wait_until(func(): return e.state != "attack", 3.0)
	for tr in _forge_trails():
		tr.queue_free()
	# Respiro da Fornalha: o 3º golpe, com o alvo colado nele
	player.global_position = e.global_position + Vector3(0, 0, 3.0)
	Game.hp = Game.max_hp()
	var hp2: float = Game.hp
	e._forge_n = 2
	e.attack_cd = 0.0
	e._set_state("chase")
	await wait_until(func(): return e.state == "attack", 2.0)
	check(e.attack_kind == "vent", "Forjador: com o alvo colado vem o Respiro da Fornalha (%s)" % e.attack_kind)
	await wait_until(func(): return Game.hp < hp2, 3.0)
	check(Game.hp < hp2, "Forjador: o Respiro queima quem está em volta (%.0f -> %.0f)" % [hp2, Game.hp])
	await wait_until(func(): return e.state != "attack", 3.0)
	# Escudo Rúnico: a vida cai a 80%, ele crava o punho e as 3 runas nascem
	Game.hp = Game.max_hp()
	e.hp = e.max_hp * 0.7
	e._forge_n = 0
	e.attack_cd = 0.0
	e._set_state("chase")
	await wait_until(func(): return e.state == "attack", 2.0)
	check(e.attack_kind == "rune_shield", "Forjador: ferido, ergue o Escudo Rúnico (%s)" % e.attack_kind)
	await wait_until(func(): return e.shielded, 3.0)
	var runes: Array = e._runes_near()
	check(e.shielded and runes.size() == ForgeRules.RUNES, "Forjador: o escudo sobe e as runas nascem (%d)" % runes.size())
	var hp_s: float = e.hp
	e.take_damage(500.0, player.global_position, false)
	check(is_equal_approx(e.hp, hp_s), "Forjador: com o escudo de pé ele é imune (%.0f -> %.0f)" % [hp_s, e.hp])
	# com o escudo de pé ele continua atacando
	await wait_until(func(): return e.state != "attack", 3.0)
	Game.hp = Game.max_hp()
	e.attack_cd = 0.0
	e._set_state("chase")
	await wait_until(func(): return e.state == "attack", 2.5)
	check(e.state == "attack" and e.attack_kind in ["hammer", "vent"] and e.shielded,
		"Forjador: de escudo erguido ele continua atacando (%s)" % e.attack_kind)
	# duas runas quebradas: o escudo fica; a terceira: cai
	for i in 2:
		runes[i].take_damage(999999.0, player.global_position, false)
	await wait(1.2)
	check(e.shielded and e._runes_near().size() == 1, "Forjador: com uma runa viva o escudo continua de pé")
	runes[2].take_damage(999999.0, player.global_position, false)
	await wait_until(func(): return not e.shielded, 2.0)
	check(not e.shielded, "Forjador: o escudo só cai com as 3 runas quebradas")
	hp_s = e.hp
	e.take_damage(50.0, player.global_position, false)
	check(e.hp < hp_s, "Forjador: sem o escudo volta a levar dano (%.0f -> %.0f)" % [hp_s, e.hp])
	check(not e._forge_wants_shield(), "Forjador: o próximo escudo espera a recarga")
	await wait_until(func(): return e.state != "attack", 3.0)
	for tr in _forge_trails():
		tr.queue_free()
	# fase 2: abaixo de metade da vida, superaquecido
	var slow: float = e._forge_time(1.0)
	e.hp = e.max_hp * 0.52
	e.take_damage(e.max_hp * 0.05, player.global_position, false)
	check(e.enraged, "Forjador: abaixo de metade da vida ele superaquece")
	check(e._forge_time(1.0) < slow, "Forjador: superaquecido ataca mais rápido (%.2f -> %.2f)" % [slow, e._forge_time(1.0)])
	hp_s = e.hp
	e.take_damage(100.0, player.global_position, false)
	var took: float = hp_s - e.hp
	var plain: float = e.incoming(100.0) * e.element_mult("fisico")
	check(took > plain * 1.2, "Forjador: superaquecido leva mais dano (%.0f em vez de %.0f)" % [took, plain])
	player.global_position = e.global_position + Vector3(0, 0, 5.0)
	Game.hp = Game.max_hp()
	e._forge_n = 0
	e._forge_since = 0.0
	e.attack_cd = 0.0
	e._set_state("chase")
	await wait_until(func(): return e.state == "attack" and e.hit_done, 4.0)
	check(e.attack_kind == "hammer" and _forge_trails().size() == ForgeRules.TRAILS_HOT,
		"Forjador: superaquecido a Martelada deixa mais faixas (%d)" % _forge_trails().size())
	# fim da luta: sem ele de escudo erguido, as runas se desfazem (sem recompensa)
	e._forge_since = ForgeRules.SHIELD_CD
	await wait_until(func(): return e.state != "attack", 3.0)
	Game.hp = Game.max_hp()
	e.attack_cd = 0.0
	e._set_state("chase")
	await wait_until(func(): return e.shielded, 5.0)
	var last: Array = e._runes_near()
	check(e.shielded and last.size() == ForgeRules.RUNES, "Forjador: depois da recarga o escudo sobe de novo (%d runas)" % last.size())
	e.queue_free()
	await wait(1.5)
	var left := 0
	for r in last:
		if is_instance_valid(r) and not r.dead:
			left += 1
	check(left == 0, "Forjador: sem ele, as runas se desfazem (%d sobraram)" % left)
	for tr in _forge_trails():
		tr.queue_free()
	Game.hp = Game.max_hp()
	player.global_position = back
	await wait(0.1)


func _forge_trails() -> Array:
	var out := []
	for c in world.get_children():
		if c is MoltenTrail and not c.is_queued_for_deletion():
			out.append(c)
	return out


## Espinheira, a Guardiã-Raiz (chefe do Bosque): as Raízes acertam de longe e prendem, os Brotos nascem e a curam,
## na fúria as Nuvens de Esporos aparecem, e os brotos murcham quando a luta acaba.
func _test_espinheira() -> void:
	var back := player.global_position
	var spot := Vector3(-105, 0.3, 40)
	player.global_position = spot
	Game.hp = Game.max_hp()
	var e := Enemy.new()
	e.kind = "espinheira"
	world.add_child(e)
	e.global_position = spot + Vector3(0, 0, -9)
	e.home = e.global_position
	await wait(0.2)
	check(e.is_boss and e.parts.get("Crown") != null and e.parts.get("KneeL") != null and e.parts.get("ElbowR") != null,
		"Espinheira: chefe, com copa, joelhos e cotovelos no modelo")
	# Raízes: o jogador está a 9 m (fora da garra), na linha
	var hp0: float = Game.hp
	e._thorn_n = 0
	e.attack_cd = 0.0
	e._set_state("chase")
	await wait_until(func(): return e.state == "attack", 2.0)
	check(e.attack_kind == "roots", "Espinheira: longe, ataca com as Raízes (%s)" % e.attack_kind)
	await wait_until(func(): return Game.hp < hp0, 3.5)
	check(Game.hp < hp0 and player.web_t > 0.0, "Espinheira: as Raízes acertam e prendem (%.0f -> %.0f, preso %.1f s)"
		% [hp0, Game.hp, player.web_t])
	await wait_until(func(): return e.state != "attack", 3.0)
	# Brotos: o 4º golpe do ciclo; eles nascem e curam a árvore ferida
	Game.hp = Game.max_hp()
	e._thorn_n = 3
	e.attack_cd = 0.0
	e._set_state("chase")
	await wait_until(func(): return e._sprouts_near(e.global_position).size() >= ThornRules.SPROUTS, 3.0)
	var sprouts: Array = e._sprouts_near(e.global_position)
	check(sprouts.size() == ThornRules.SPROUTS, "Espinheira: os Brotos nascem (%d)" % sprouts.size())
	e.hp = e.max_hp * 0.6
	var hp_b: float = e.hp
	await wait(1.2)
	check(e.hp > hp_b, "Espinheira: os Brotos vivos a curam (%.0f -> %.0f)" % [hp_b, e.hp])
	await wait_until(func(): return e.state != "attack", 3.0)
	# Esporos: na fúria, no ciclo ímpar; uma nuvem nasce sob o jogador
	Game.hp = Game.max_hp()
	e.enraged = true
	e._thorn_n = 7
	e.attack_cd = 0.0
	e._set_state("chase")
	await wait_until(func(): return e.state == "attack", 2.0)
	check(e.attack_kind == "spores", "Espinheira: na fúria vêm os Esporos (%s)" % e.attack_kind)
	await wait(1.8)
	var clouds := 0
	for c in world.get_children():
		if c is SporeCloud:
			clouds += 1
	check(clouds >= ThornRules.SPORES + 1, "Espinheira: as Nuvens de Esporos nascem, uma sob o jogador (%d)" % clouds)
	Game.hp = Game.max_hp()
	# fim da luta: sem a árvore, os brotos murcham (sem recompensa)
	e.queue_free()
	await wait(1.5)
	var left := 0
	for s in sprouts:
		if is_instance_valid(s) and not s.dead:
			left += 1
	check(left == 0, "Espinheira: sem ela, os Brotos murcham (%d sobraram)" % left)
	for c in world.get_children():
		if c is SporeCloud:
			c.queue_free()
	Game.hp = Game.max_hp()
	player.web_t = 0.0
	player.chill_t = 0.0
	player.global_position = back
	await wait(0.1)


## Arcos míticos (BowMythic): cada um equipado, uma flecha tensionada contra slimes parados e a mecânica conferida:
## fenda que puxa e implode, marcas solares e coluna, chuva de fogo, empurrão e ricochete, flecha fantasma do
## Crescente, espinheiro que deixa lento e flor de cura no abate. Partículas na mão (BowAura) em todos.
func _test_mythic_bows() -> void:
	var weapon0: String = Game.equipment.weapon
	var pos0: Vector3 = player.global_position
	var gs: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.kind == "slime" and not e.dead and not e.is_boss:
			gs.append(e)
	gs.sort_custom(func(a, b): return a.global_position.distance_to(player.global_position) < b.global_position.distance_to(player.global_position))
	gs = gs.slice(0, 3)
	_targets(gs)
	check(gs.size() == 3, "arcos míticos: 3 slimes para o teste (%d)" % gs.size())
	if gs.size() < 3:
		return
	var saved: Array = []
	for e in gs:
		saved.append([e, e.max_hp, e.global_position])
		e.max_hp = 100000.0
	var base: Vector3 = gs[0].home
	player.global_position = base + Vector3(0, 0.3, 0)
	player.velocity = Vector3.ZERO
	await wait_until(func(): return player.is_on_floor())
	_calm_bystanders(gs, base, 40.0, 30.0)
	var fwd := -player.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP).normalized()
	# alvo a 8 m; os outros dois a 2,5 m e 5 m dele, para fenda, chuva, coluna, ricochete e espinheiro
	var place := func() -> void:
		var p0: Vector3 = player.global_position
		var c: Vector3 = p0 + fwd * 8.0
		var spots := [c, c + side * 2.5, c + side * 5.0]
		for i in 3:
			gs[i].global_position = spots[i] + Vector3.UP * 0.3
			gs[i].velocity = Vector3.ZERO
			gs[i].stagger = 4.0
			gs[i].hp = gs[i].max_hp
			gs[i].slow_timer = 0.0
	var shoot := func(fx_full: bool, target: Node3D) -> Node:
		var from: Vector3 = player.global_position + Vector3.UP * 1.4
		var to: Vector3 = target.global_position + Vector3.UP * 0.4
		var ar = player._spawn_projectile("arrow", from, (to - from).normalized(), 30.0, false, 0, 40.0)
		ar.full = fx_full
		ar.no_drop = true
		if fx_full and player._weapon_fx() == "gale":
			ar.bounces = int(BowMythicRules.GALE.bounces)
		return ar
	var count := func(cls) -> int:
		var n := 0
		for c in get_tree().current_scene.get_children():
			if is_instance_of(c, cls):
				n += 1
		return n

	for id in ["abyss_bow", "dawn_bow", "dragon_bow", "wind_bow", "crescent_bow", "root_bow"]:
		Game.add_item(id)
		equip_any(id)
		await wait(0.2)
		check(Game.equipment.weapon == id, "%s equipado" % id)
		var holder: Node3D = player.look.get("holder")
		var auras := holder.find_children("Aura_*", "Node3D", true, false) if holder else []
		var emitters := 0
		for a in auras:
			for c in a.get_children():
				if c is CPUParticles3D and c.emitting:
					emitters += 1
		check(auras.size() >= 3 and emitters >= 3, "%s: partículas na mão (%d pontos, %d emissores)" % [id, auras.size(), emitters])
		place.call()
		await wait(0.1)
		var fx: String = player._weapon_fx()
		match fx:
			"vortex":
				var d0: float = gs[1].global_position.distance_to(gs[0].global_position)
				shoot.call(true, gs[0])
				await wait(0.25)
				check(count.call(BowMythic.Rift) == 1, "Suspiro do Abismo: a fenda abre onde a flecha acertou")
				for e in gs:
					e.stagger = 0.0
				await wait(0.7)
				var d1: float = gs[1].global_position.distance_to(gs[0].global_position)
				check(d1 < d0 - 0.3, "Suspiro do Abismo: a fenda puxa quem está perto (%.2f m -> %.2f m)" % [d0, d1])
				await wait(0.6)
				check(gs[1].hp < gs[1].max_hp, "Suspiro do Abismo: fere em volta (%.0f / %.0f)" % [gs[1].hp, gs[1].max_hp])
				await wait(0.4)
				check(count.call(BowMythic.Rift) == 0, "Suspiro do Abismo: implode e some (%d)" % count.call(BowMythic.Rift))
			"solar":
				for k in 3:
					shoot.call(false, gs[0])
					await wait(0.35)
					if k < 2:
						check(gs[0].get_meta("solar_marks", []).size() == k + 1, "Alvorada: %dª marca no alvo" % (k + 1))
				check(gs[0].get_meta("solar_marks", [1]).is_empty(), "Alvorada: a 3ª marca derruba a coluna de sol")
				check(gs[1].hp < gs[1].max_hp, "Alvorada: a coluna fere quem está perto do alvo")
			"dragonfire":
				shoot.call(true, gs[0])
				await wait(0.25)
				var rain_at := Vector3.INF
				for c in get_tree().current_scene.get_children():
					if c is BowMythic.Rain:
						rain_at = c.global_position
				check(rain_at.distance_to(gs[0].global_position) < 2.0,
					"Presa do Dragão: a chuva de fogo começa no alvo (%.2f m)" % rain_at.distance_to(gs[0].global_position))
				await wait(1.6)
				var hurt := 0
				for e in gs:
					if e.hp < e.max_hp:
						hurt += 1
				check(hurt >= 2, "Presa do Dragão: a chuva fere o alvo e quem está em volta (%d de 3; %s; alvo %s, vizinho %s)"
					% [hurt, rain_at, gs[0].global_position, gs[1].global_position])
				check(count.call(BowMythic.Rain) == 0, "Presa do Dragão: a chuva acaba (%d)" % count.call(BowMythic.Rain))
			"gale":
				var me0: Vector3 = player.global_position
				gs[0].stagger = 0.0
				shoot.call(true, gs[0])
				player._gale_leap(fwd)
				# afastamento a partir de onde a flecha acertou (o slime provocado já vem andando para o jogador antes
				# do acerto); o maior em 1 s, porque depois do empurrão ele volta
				var hp0: float = gs[0].hp
				var hit_at := Vector3.INF
				var pushed := 0.0
				var t_end := Time.get_ticks_msec() + 1200
				while Time.get_ticks_msec() < t_end:
					if hit_at == Vector3.INF and gs[0].hp < hp0:
						hit_at = gs[0].global_position
					elif hit_at != Vector3.INF:
						pushed = maxf(pushed, (gs[0].global_position - hit_at).dot(fwd))
					await get_tree().physics_frame
				check(pushed > 0.3, "Rei dos Ventos: a flecha empurra o alvo para longe (%.2f m; elite=%s estado=%s hp=%.0f/%.0f vel=%s)" % [pushed, gs[0].elite, gs[0].state, gs[0].hp, gs[0].max_hp, gs[0].velocity])
				check(gs[1].hp < gs[1].max_hp, "Rei dos Ventos: a flecha tensionada ricocheteia no vizinho")
				check((player.global_position - me0).dot(fwd) < -0.5, "Rei dos Ventos: o vento joga o arqueiro para trás")
			"crescent":
				var before: int = count.call(PROJECTILE_SCRIPT())
				player._crescent_perfect(30.0, 40.0)
				await wait(float(BowMythicRules.CRESCENT.ghost_delay) + 0.08)
				check(count.call(PROJECTILE_SCRIPT()) > before, "Crescente Gêmeo: a soltura perfeita dispara a flecha fantasma")
			"bramble":
				# o vizinho bem dentro do espinheiro (raio BRAMBLE.radius): a 2,5 m ele ficava na borda e, com o desnível
				# do chão e o ponto onde a flecha acerta, às vezes fora (falhava de vez em quando no CI)
				gs[1].global_position = gs[0].global_position + side * float(BowMythicRules.BRAMBLE.radius) * 0.5
				gs[1].velocity = Vector3.ZERO
				shoot.call(true, gs[0])
				await wait_until(func(): return count.call(BowMythic.Bramble) == 1 and gs[1].slow_timer > 0.0 and gs[1].hp < gs[1].max_hp, 1.5)
				check(count.call(BowMythic.Bramble) == 1, "Raiz-Mãe: o espinheiro brota no alvo")
				var d_b: float = gs[1].global_position.distance_to(gs[0].global_position)
				check(gs[1].slow_timer > 0.0 and gs[1].hp < gs[1].max_hp,
					"Raiz-Mãe: o espinheiro fere e deixa lento (vizinho a %.2f m, lento %.2f s)" % [d_b, gs[1].slow_timer])
				var fl0: int = count.call(BowMythic.Flower)
				BowMythic.spawn_flower(gs[0], gs[0].global_position)
				Game.hp = Game.max_hp() * 0.5
				player.global_position = gs[0].global_position + Vector3.UP * 0.3
				var hp0: float = Game.hp
				await wait(1.2)
				check(count.call(BowMythic.Flower) > fl0, "Raiz-Mãe: a flor nasce")
				check(Game.hp > hp0, "Raiz-Mãe: a flor cura quem está perto (%.0f -> %.0f)" % [hp0, Game.hp])
				player.global_position = base + Vector3(0, 0.3, 0)
	for c in get_tree().current_scene.get_children():
		if c is BowMythic.Rift or c is BowMythic.Rain or c is BowMythic.Bramble or c is BowMythic.Flower:
			c.queue_free()
	for s in saved:
		s[0].max_hp = s[1]
		s[0].hp = s[1]
		s[0].global_position = s[2]
	equip_any(weapon0)
	Game.hp = Game.max_hp()
	player.global_position = pos0
	player.velocity = Vector3.ZERO
	await wait(0.3)


func PROJECTILE_SCRIPT() -> GDScript:
	return load("res://scripts/player/projectile.gd")

## Arauto do Abismo (chefe final): Rajada e Garra acertam, as Zonas de Vazio nascem e crescem, abaixo de 65% vem a
## Miragem (cópias que se desfazem sem levar dano; acertar o verdadeiro desfaz todas) e abaixo de 30% o Colapso
## (puxa para o centro, o miolo estoura e o vão entre os anéis é seguro).
func _test_arauto() -> void:
	var back := player.global_position
	var spot := Vector3(-105, 0.3, 40)
	player.global_position = spot
	Game.hp = Game.max_hp()
	var e := Enemy.new()
	e.kind = "arauto_abismo"
	world.add_child(e)
	e.global_position = spot + Vector3(0, 0, -9)
	e.home = e.global_position
	await wait(0.2)
	check(e.is_boss and e.parts.get("Halo") != null and e.parts.get("Core") != null and e.parts.get("ElbowL") != null
		and e.parts.get("HandR") != null and e.parts.get("Wisp3") != null,
		"Arauto: chefe, com halo, núcleo, cotovelos, mãos e fiapos no modelo")
	# Rajada: o jogador está a 9 m (fora da garra), na linha do projétil do meio
	var hp0: float = Game.hp
	e.attack_cd = 0.0
	e._set_state("chase")
	await wait_until(func(): return e.state == "attack", 2.0)
	check(e.attack_kind == "volley", "Arauto: longe, ataca com a Rajada de Sombras (%s)" % e.attack_kind)
	await wait_until(func(): return Game.hp < hp0, 3.0)
	check(Game.hp < hp0, "Arauto: a Rajada acerta (%.0f -> %.0f)" % [hp0, Game.hp])
	await wait_until(func(): return e.state != "attack", 3.0)
	# Garra: o jogador a 3 m, na frente
	Game.hp = Game.max_hp()
	hp0 = Game.hp
	player.global_position = e.global_position + Vector3(0, 0, 3)
	e._abyss_n = 0
	e.attack_cd = 0.0
	await wait_until(func(): return e.state == "attack", 2.0)
	check(e.attack_kind == "swing", "Arauto: perto, ataca com a Garra (%s)" % e.attack_kind)
	await wait_until(func(): return Game.hp < hp0, 2.5)
	check(Game.hp < hp0, "Arauto: a Garra em arco acerta quem está na frente (%.0f -> %.0f)" % [hp0, Game.hp])
	await wait_until(func(): return e.state != "attack", 3.0)
	# Zonas de Vazio: o 4º golpe do ciclo; nascem, crescem e ferem quem fica dentro (uma nasce sob o jogador)
	Game.hp = Game.max_hp()
	e._abyss_n = 3
	e.attack_cd = 0.0
	await wait_until(func(): return e.state == "attack", 2.0)
	check(e.attack_kind == "voids", "Arauto: o 4º golpe são as Zonas de Vazio (%s)" % e.attack_kind)
	await wait_until(func(): return get_tree().get_nodes_in_group("void_zones").size() > AbyssRules.VOIDS, 3.0)
	var zones := get_tree().get_nodes_in_group("void_zones")
	check(zones.size() == AbyssRules.VOIDS + 1, "Arauto: as Zonas nascem, uma sob o jogador (%d)" % zones.size())
	var r0: float = zones[0].radius() if not zones.is_empty() else 0.0
	hp0 = Game.hp
	await wait(1.6)
	var r1: float = zones[0].radius() if not zones.is_empty() and is_instance_valid(zones[0]) else 0.0
	check(r1 > r0 + 0.1, "Arauto: as Zonas crescem com o tempo (%.2f -> %.2f m)" % [r0, r1])
	check(Game.hp < hp0, "Arauto: quem fica na Zona leva dano (%.0f -> %.0f)" % [hp0, Game.hp])
	await wait_until(func(): return e.state != "attack", 3.0)
	for z in get_tree().get_nodes_in_group("void_zones"):
		z.queue_free()
	# Fase 2: abaixo de 65% abre com a Miragem (duas cópias, ele muda de lugar)
	Game.hp = Game.max_hp()
	player.global_position = e.global_position + Vector3(0, 0, 9)
	var was := e.global_position
	e.hp = e.max_hp * 0.6
	e.attack_cd = 0.0
	await wait_until(func(): return e._abyss_phase == 2, 1.0)
	check(e._abyss_phase == 2 and e.enraged, "Arauto: abaixo de 65% entra na fase 2")
	await wait_until(func(): return e.state == "attack", 2.5)
	check(e.attack_kind == "mirage", "Arauto: a fase 2 abre com a Miragem (%s)" % e.attack_kind)
	await wait_until(func(): return e._abyss_echoes().size() >= 2, 3.0)
	var echoes: Array = e._abyss_echoes()
	check(echoes.size() == 2, "Arauto: a Miragem cria duas cópias (%d)" % echoes.size())
	check(e.global_position.distance_to(was) > 2.0, "Arauto: ele reaparece em outro ponto (%.1f m)"
		% e.global_position.distance_to(was))
	if echoes.size() == 2:
		var echo: Enemy = echoes[0]
		check(echo.display_name == e.display_name and not echo.is_boss and e._rig.has("shadow")
			and not echo._rig.has("shadow"), "Arauto: a cópia tem o mesmo nome e só o verdadeiro tem a sombra no chão")
		# acertar uma cópia a desfaz, sem dano em ninguém
		var boss_hp: float = e.hp
		echo.take_damage(80.0, player.global_position, false)
		await wait(0.1)
		check(not is_instance_valid(echo) or echo.dead, "Arauto: acertar uma cópia a desfaz")
		check(is_equal_approx(e.hp, boss_hp) and e._abyss_echoes().size() == 1,
			"Arauto: o golpe na cópia não fere o verdadeiro e a outra cópia continua")
		# acertar o verdadeiro fere de verdade e desfaz as cópias que restam
		e.take_damage(80.0, player.global_position, false)
		await wait(0.1)
		check(e.hp < boss_hp and e._abyss_echoes().is_empty(),
			"Arauto: só o verdadeiro leva dano (%.0f -> %.0f) e o golpe nele desfaz a Miragem" % [boss_hp, e.hp])
	await wait_until(func(): return e.state != "attack", 3.0)
	# Fase 3: abaixo de 30% abre com o Colapso: vai para o centro (a casa dele, fora de sala) e puxa o jogador
	Game.hp = Game.max_hp()
	e.hp = e.max_hp * 0.25
	e.attack_cd = 0.0
	await wait_until(func(): return e._abyss_phase == 3, 1.0)
	check(e._abyss_phase == 3, "Arauto: abaixo de 30% entra na fase 3")
	player.global_position = e.home + Vector3(0, 0.3, 10)
	await wait_until(func(): return e.state == "attack", 2.5)
	check(e.attack_kind == "collapse", "Arauto: a fase 3 abre com o Colapso (%s)" % e.attack_kind)
	check(Vector2(e.global_position.x - e.home.x, e.global_position.z - e.home.z).length() < 0.5,
		"Arauto: no Colapso ele vai para o centro")
	var flat := func() -> float:
		return Vector2(player.global_position.x - e.global_position.x, player.global_position.z - e.global_position.z).length()
	await wait_until(func(): return e.attack_timer >= AbyssRules.PULL_T, 3.0)
	check(flat.call() <= AbyssRules.PULL_STOP + 0.5, "Arauto: o Colapso puxa o jogador para o centro (10 m -> %.1f m)"
		% flat.call())
	# quem fica no centro leva o miolo
	hp0 = Game.hp
	await wait_until(func(): return Game.hp < hp0, 2.5)
	check(Game.hp < hp0 and e.attack_timer >= float(AbyssRules.collapse_ring(0).t),
		"Arauto: o miolo da explosão pega quem ficou no centro (%.0f -> %.0f)" % [hp0, Game.hp])
	# no vão entre o miolo e o primeiro anel a onda passa sem acertar
	# (o golpe do miolo empurra o jogador para fora: o teste o segura no vão até a explosão acabar)
	var gap := e.global_position + Vector3(0, 0.3, AbyssRules.COLLAPSE_DISC + AbyssRules.COLLAPSE_GAP * 0.5)
	player.global_position = gap
	hp0 = Game.hp
	var guard := 0
	while e.state == "attack" and guard < 400:
		guard += 1
		player.global_position = Vector3(gap.x, player.global_position.y, gap.z)
		player.velocity = Vector3.ZERO
		await get_tree().physics_frame
	check(Game.hp >= hp0 - 0.5, "Arauto: no vão entre os anéis a explosão não acerta (%.0f -> %.0f)"
		% [hp0, Game.hp])
	# fim da luta: sem ele, as cópias que houver se desfazem
	e.queue_free()
	await wait(1.2)
	var left := 0
	for x in get_tree().get_nodes_in_group("enemies"):
		if x is Enemy and x.kind == Enemy.ECHO_KIND and not x.dead:
			left += 1
	check(left == 0, "Arauto: sem ele, as cópias se desfazem (%d sobraram)" % left)
	for z in get_tree().get_nodes_in_group("void_zones"):
		z.queue_free()
	Game.hp = Game.max_hp()
	player.global_position = back
	await wait(0.1)


## Sentinela da Nevasca (chefe do Pico): a patada acerta e congela, o Sopro em cone acerta, deixa lento e apaga o
## braseiro no caminho, as Estacas caem (uma sob o jogador) e ficam no chão, e na fúria a Nevasca fere quem está
## longe de um braseiro aceso e poupa quem está perto de um.
func _test_sentinela() -> void:
	var back := player.global_position
	var spot := Vector3(-105, 0.3, 40)
	Game.hp = Game.max_hp()
	var e := Enemy.new()
	e.kind = "sentinela_nevasca"
	world.add_child(e)
	e.global_position = spot
	e.home = e.global_position
	player.global_position = spot + Vector3(0, 0, 4.0)
	await wait(0.3)
	check(e.is_boss and e.parts.get("KneeFL") != null and e.parts.get("Tail3") != null and e.parts.get("PlateL") != null
		and e.parts.get("Mane0") != null, "Sentinela: chefe, com patas em três ossos, cauda, ombreiras e juba no modelo")
	check(e._blz_braziers.size() == BlizzardRules.BRAZIERS and e.brazier_mask() == BlizzardRules.MASK_ALL,
		"Sentinela: os braseiros da sala nascem acesos (%d)" % e._blz_braziers.size())
	var pts: Array = e._blz_pts
	var begin := func(n: int) -> void:
		Game.hp = Game.max_hp()
		player.chill_t = 0.0
		player.invuln = 0.0
		e._blz_n = n
		e.attack_cd = 0.0
		e._set_state("chase")
	# patada: o jogador está a 4 m, na frente
	e.model.rotation.y = 0.0
	begin.call(0)
	var hp0: float = Game.hp
	await wait_until(func(): return e.state == "attack", 2.0)
	check(e.attack_kind == "swing", "Sentinela: perto, ataca com a patada (%s)" % e.attack_kind)
	await wait_until(func(): return Game.hp < hp0, 2.0)
	check(Game.hp < hp0 and player.chill_t > 0.0, "Sentinela: a patada acerta e congela (%.0f -> %.0f, lento %.1f s)"
		% [hp0, Game.hp, player.chill_t])
	await wait_until(func(): return e.state != "attack", 3.0)
	# sopro: o jogador fica ao lado do braseiro do leste; o cone passa por ele e apaga o braseiro
	player.global_position = (pts[1] as Vector3) + Vector3(-1.2, 0.4, 0.0)
	begin.call(1)
	hp0 = Game.hp
	await wait_until(func(): return e.state == "attack", 2.0)
	check(e.attack_kind == "breath", "Sentinela: o 2º golpe é o Sopro (%s)" % e.attack_kind)
	await wait_until(func(): return Game.hp < hp0, BlizzardRules.BREATH_T0 + BlizzardRules.BREATH_TIME)
	check(Game.hp < hp0 and player.chill_t > 0.0, "Sentinela: o Sopro acerta e deixa lento (%.0f -> %.0f, lento %.1f s)"
		% [hp0, Game.hp, player.chill_t])
	check(e.brazier_mask() & 2 == 0, "Sentinela: o Sopro apaga o braseiro no caminho (acesos %d)" % e.brazier_mask())
	check(not (e._blz_braziers[1] as BlizzardBrazier).lit, "Sentinela: o braseiro apagado mostra o gelo")
	Game.hp = Game.max_hp()
	await wait_until(func(): return e.state != "attack", 7.0)
	# estacas: caem nos pontos avisados, uma sob o jogador, e ficam no chão
	player.global_position = spot + Vector3(0, 0.4, 8.0)
	begin.call(3)
	hp0 = Game.hp
	await wait_until(func(): return e.state == "attack", 2.0)
	check(e.attack_kind == "icicles", "Sentinela: o 4º golpe são as Estacas (%s)" % e.attack_kind)
	await wait_until(func(): return Game.hp < hp0, BlizzardRules.SPIKE_T + 1.0)
	var spikes := 0
	for c in world.get_children():
		if c is IceSpike:
			spikes += 1
	check(Game.hp < hp0, "Sentinela: a Estaca que cai no jogador acerta (%.0f -> %.0f)" % [hp0, Game.hp])
	check(spikes >= BlizzardRules.SPIKES + 1, "Sentinela: as Estacas ficam no chão, uma sob o jogador (%d)" % spikes)
	await wait_until(func(): return e.state != "attack", 4.0)
	for c in world.get_children():
		if c is IceSpike:
			c.queue_free()
	# fase 2: abaixo de metade da vida ela urra e a nevasca começa
	e.hp = e.max_hp * 0.6
	e.take_damage(e.max_hp * 0.15, player.global_position, false)
	check(e.enraged and not e._blz_storm, "Sentinela: abaixo de 50% entra em fúria (a nevasca ainda não sopra)")
	begin.call(0)
	await wait_until(func(): return e.state == "attack", 2.0)
	check(e.attack_kind == "blizzard", "Sentinela: o primeiro golpe da fúria chama a Nevasca (%s)" % e.attack_kind)
	await wait_until(func(): return e._blz_storm, 3.0)
	check(e._blz_storm, "Sentinela: a Nevasca toma a sala")
	await wait_until(func(): return e.state != "attack", 4.0)
	# daqui em diante ela fica parada: só a nevasca age
	e.attack_cd = 999.0
	e.speed_mult = 0.0
	e._blz_relight = [0.0, 0.0, 0.0, 0.0]
	# longe dos braseiros: congela (dano e lentidão que crescem)
	player.global_position = spot + Vector3(-9.0, 0.4, -7.0)
	Game.hp = Game.max_hp()
	player.chill_t = 0.0
	hp0 = Game.hp
	await wait(BlizzardRules.EXPOSE_RAMP * 0.5)
	var exp_far: float = e._blz_exposure.get(player.get_instance_id(), 0.0)
	check(Game.hp < hp0 and player.chill_t > 0.0 and exp_far > 0.3,
		"Sentinela: longe dos braseiros a Nevasca congela (%.0f -> %.0f, lento %.1f s, exposição %.2f)"
		% [hp0, Game.hp, player.chill_t, exp_far])
	# ao lado de um braseiro aceso: abrigado
	player.global_position = (pts[0] as Vector3) + Vector3(1.0, 0.4, 0.0)
	await wait(BlizzardRules.THAW + 1.0)
	Game.hp = Game.max_hp()
	player.invuln = 0.0
	hp0 = Game.hp
	await wait(2.0)
	check(Game.hp >= hp0 and float(e._blz_exposure.get(player.get_instance_id(), 0.0)) <= 0.0,
		"Sentinela: perto de um braseiro aceso a Nevasca não fere (%.0f -> %.0f)" % [hp0, Game.hp])
	# o braseiro apaga: o abrigo acaba; depois ele reacende sozinho
	e._blz_relight[0] = 3.0
	await wait(2.4)
	check(Game.hp < hp0, "Sentinela: com o braseiro apagado o abrigo acaba (%.0f -> %.0f)" % [hp0, Game.hp])
	await wait(1.2)
	check(e.brazier_mask() & 1 == 1 and (e._blz_braziers[0] as BlizzardBrazier).lit, "Sentinela: o braseiro reacende sozinho")
	e.queue_free()
	await wait(0.2)
	Game.hp = Game.max_hp()
	player.chill_t = 0.0
	player.global_position = back
	await wait(0.1)
