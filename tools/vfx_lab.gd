extends Node3D
## PROTÓTIPO (spike): vitrine dos efeitos de encantamento e de aura de buff.
## Teclas: Tab / 1-7 trocam a página · ←/→ trocam o elemento (página "Níveis") · arraste para girar.
## Com `-- --vfxshot=<pasta>` salva um PNG de cada página e fecha.

const KNIGHT := preload("res://assets/models/knight.glb")
var SPACING := 1.45

var pages := ["niveis", "elementos", "armas", "auras1", "auras2", "juntas", "rampa", "perto1", "perto2", "corte", "investida", "sismico", "turbilhao", "magias", "meteoros", "faisca", "arco", "vendaval"]
var page := 0
var element_i := 0
var _knights: Array = []     # [{"model", "rig", "look", "pivot"}]
var _t := 0.0
var _title: Label
var _cam: Camera3D
var _shot_dir := ""
var _seq_dir := ""       # --vfxseq=<pasta>: quadros em sequência da página atual (use com --fixed-fps 60)
var _turn := 0.0
var _drag := false
var _ramp: StaticBody3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--vfxshot="):
			_shot_dir = a.substr(10)
		elif a.begins_with("--vfxseq="):
			_seq_dir = a.substr(9)
		elif a.begins_with("--vfxpage="):
			page = clampi(int(a.substr(10)) - 1, 0, pages.size() - 1)
	_setup_world()
	_show_page()
	if _shot_dir != "":
		_take_shots()
	elif _seq_dir != "":
		_take_seq()


func _setup_world() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.07, 0.08, 0.11)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.47, 0.55)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.glow_bloom = 0.05
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.5, 0)
	sun.light_energy = 0.9
	sun.light_color = Color(1, 0.92, 0.82)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 12)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.2, 0.22, 0.2)
	gm.roughness = 0.95
	pm.material = gm
	ground.mesh = pm
	add_child(ground)
	_cam = Camera3D.new()
	_cam.fov = 38.0
	add_child(_cam)
	var ui := CanvasLayer.new()
	add_child(ui)
	_title = Label.new()
	_title.position = Vector2(20, 14)
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_outline_color", Color.BLACK)
	_title.add_theme_constant_override("outline_size", 6)
	ui.add_child(_title)


func _clear() -> void:
	for k in _knights:
		k.pivot.queue_free()
	_knights.clear()


## Cria um cavaleiro na posição `i` de `n`, com equipamento `look`, legenda e devolve o registro.
func _knight(i: int, n: int, look: Dictionary, caption: String) -> Dictionary:
	var pivot := Node3D.new()
	add_child(pivot)
	pivot.position = Vector3((i - (n - 1) / 2.0) * SPACING, 0, 0)
	var m := KNIGHT.instantiate() as Node3D
	pivot.add_child(m)
	var lk := KnightLook.apply(m, look)
	var lbl := Label3D.new()
	lbl.text = caption
	lbl.font_size = 40
	lbl.pixel_size = 0.004
	lbl.outline_size = 10
	lbl.position = Vector3(0, 2.15, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pivot.add_child(lbl)
	var rec := {"pivot": pivot, "model": m, "rig": KnightAnim.rig(m), "look": lk}
	_knights.append(rec)
	return rec


func _show_page() -> void:
	_clear()
	var base := {"armor": "chain_mail", "head": "iron_helm", "hands": "iron_gauntlets", "feet": "leather_boots"}
	SPACING = 1.9 if pages[page] in ["auras1", "auras2", "juntas", "rampa"] else 1.45
	if _ramp:
		_ramp.queue_free()
		_ramp = null
	match pages[page]:
		"niveis":
			var el: String = EnchantFX.ELEMENTS.keys()[element_i]
			_title.text = "Níveis de encantamento — %s   (←/→ troca o elemento · Tab troca a página)" % EnchantFX.ELEMENTS[el].name
			for lv in EnchantFX.MAX_LEVEL + 1:
				var l := base.duplicate()
				l.weapon = "iron_sword"
				var r := _knight(lv, EnchantFX.MAX_LEVEL + 1, l, "+%d" % lv if lv > 0 else "sem encanto")
				EnchantFX.apply(r.look, el, lv)
		"elementos":
			_title.text = "Elementos no nível máximo (+%d)" % EnchantFX.MAX_LEVEL
			var els: Array = EnchantFX.ELEMENTS.keys()
			for i in els.size():
				var l := base.duplicate()
				l.weapon = "knight_blade"
				var r := _knight(i, els.size(), l, EnchantFX.ELEMENTS[els[i]].name)
				EnchantFX.apply(r.look, els[i], EnchantFX.MAX_LEVEL)
		"armas":
			_title.text = "Mesmo encanto (+4) em armas diferentes"
			var ws := [["wooden_sword", "fogo"], ["azure_edge", "gelo"], ["crystal_frost", "raio"],
				["apprentice_staff", "veneno"], ["short_bow", "sagrado"], ["steel_saber", "sombra"]]
			for i in ws.size():
				var l := base.duplicate()
				l.weapon = ws[i][0]
				var r := _knight(i, ws.size(), l, "%s\n%s" % [ItemDB.get_item(ws[i][0]).name, EnchantFX.ELEMENTS[ws[i][1]].name])
				EnchantFX.apply(r.look, ws[i][1], 4)
		"auras1", "auras2":
			_title.text = "Auras de buff (comida ativa) — %s de 2" % pages[page].right(1)
			var foods := ["bread", "carrot_stew", "spicy_soup", "dragon_chili"]
			if pages[page] == "auras2":
				foods = ["mint_tea", "garden_salad", "valdoria_feast"]
			for i in foods.size():
				var l := base.duplicate()
				l.weapon = "iron_sword"
				var it := ItemDB.get_item(foods[i])
				var r := _knight(i, foods.size(), l, "%s\n%s" % [it.name, ItemDB.BUFFS[it.buff].name])
				var aura := BuffAura.new()
				r.model.add_child(aura)
				aura.set_buffs([it.buff])
		"perto1", "perto2":
			# de perto: os três níveis mais altos de um elemento, depois três elementos no máximo
			var near: Array = [["fogo", 3], ["fogo", 4], ["fogo", 5]]
			if pages[page] == "perto2":
				near = [["gelo", 5], ["raio", 5], ["sombra", 5]]
			_title.text = "De perto — " + ", ".join(near.map(func(x): return "%s +%d" % [EnchantFX.ELEMENTS[x[0]].name, x[1]]))
			for i in near.size():
				var l := base.duplicate()
				l.weapon = "knight_blade"
				var r := _knight(i, near.size(), l, "%s +%d" % [EnchantFX.ELEMENTS[near[i][0]].name, near[i][1]])
				EnchantFX.apply(r.look, near[i][0], near[i][1])
		"corte":
			_title.text = "Corte da espada (estilo desenhado): golpes 1, 2 e 3 do combo"
			SPACING = 4.6
			var cols := [Color(0.6, 0.8, 1.0), Color(1.0, 0.42, 0.08), Color(0.55, 0.15, 0.85)]
			for i in 3:
				var l := base.duplicate()
				l.weapon = "knight_blade"
				var r := _knight(i, 3, l, "golpe %d" % (i + 1))
				r["swing"] = i + 1
				r["color"] = cols[i]
				r["fired"] = false
				r.pivot.rotation.y = PI * 0.82
		"investida":
			_title.text = "Investida (estilo desenhado): preparo, avanço de 5 m e chegada"
			var l := base.duplicate()
			l.weapon = "knight_blade"
			var r := _knight(0, 1, l, "")
			r["charge"] = {"yaw": PI * 0.62, "from": Vector3(-2.6, 0, 1.0), "phase": 0, "lance": null}
			r.pivot.rotation.y = r.charge.yaw
			r.pivot.position = r.charge.from
		"sismico":
			_title.text = "Golpe Sísmico (estilo desenhado): ergue, crava e a onda corre 6 m pelo cone"
			var l := base.duplicate()
			l.weapon = "knight_blade"
			var r := _knight(0, 1, l, "")
			r["quake"] = {"yaw": PI * 0.62, "phase": 0, "wave": 0}
			r.pivot.rotation.y = r.quake.yaw
			r.pivot.position = Vector3(-3.4, 0, 1.6)
		"turbilhao":
			_title.text = "Turbilhão (estilo desenhado): preparo, 4 voltas e golpe final"
			var l := base.duplicate()
			l.weapon = "knight_blade"
			var r := _knight(0, 1, l, "")
			r["whirl"] = {"yaw": PI * 0.62, "phase": 0}
			r.pivot.rotation.y = r.whirl.yaw
			r.pivot.position = Vector3(0, 0, 0.5)
		"magias":
			_title.text = "Magias do cajado (estilo desenhado): Bola de Fogo, Nova Gélida e Cura"
			var l := base.duplicate()
			l.weapon = "apprentice_staff"
			var r := _knight(0, 1, l, "")
			r["spells"] = {"yaw": PI * 0.5, "step": 0}
			r.pivot.rotation.y = r.spells.yaw
			r.pivot.position = Vector3(-4.5, 0, 0.5)
		"meteoros":
			_title.text = "Chuva de Meteoros (estilo desenhado): círculo de runas, meteoros e explosões"
			var l := base.duplicate()
			l.weapon = "apprentice_staff"
			var r := _knight(0, 1, l, "")
			r["meteors"] = {"center": Vector3(2.0, 0, -1.0), "next": 0.0, "sigil": null, "on": false}
			r.pivot.rotation.y = PI * 0.5
			r.pivot.position = Vector3(-7.0, 0, 2.0)
		"faisca":
			_title.text = "Ataque básico do cajado: faísca, leque do 3º golpe e estouro em área"
			var l := base.duplicate()
			l.weapon = "apprentice_staff"
			var r := _knight(0, 1, l, "")
			r["bolts"] = {"yaw": PI * 0.5, "step": 0}
			r.pivot.rotation.y = r.bolts.yaw
			r.pivot.position = Vector3(-5.0, 0, 0.5)
		"arco":
			_title.text = "Arco: flecha, Tiro Triplo e Flecha Glacial (carga, voo e gelo no alvo)"
			var l := base.duplicate()
			l.weapon = "short_bow"
			var r := _knight(0, 1, l, "")
			r["arrows"] = {"yaw": PI * 0.5, "step": 0}
			r.pivot.rotation.y = r.arrows.yaw
			r.pivot.position = Vector3(-5.0, 0, 0.5)
		"vendaval":
			_title.text = "Flecha do Vendaval: tensão (1,2 s), disparo e o feixe correndo a linha"
			var l := base.duplicate()
			l.weapon = "short_bow"
			var r := _knight(0, 1, l, "")
			r["gale"] = {"yaw": PI * 0.5, "phase": 0, "fx": null}
			r.pivot.rotation.y = r.gale.yaw
			r.pivot.position = Vector3(-6.5, 0, 0.5)
		"juntas":
			_title.text = "Auras juntas (habilidades + comida): cada uma ganha seu anel"
			var sets := [["escudo", "furia"], ["cura", "vento"], ["escudo", "vento", "heroi"], ["cura", "escudo", "dragao", "sorte"]]
			for i in sets.size():
				var l := base.duplicate()
				l.weapon = "iron_sword"
				var r := _knight(i, sets.size(), l, " + ".join(sets[i]))
				var aura := BuffAura.new()
				r.model.add_child(aura)
				aura.set_styles(sets[i])
		"rampa":
			_title.text = "Terreno inclinado (18°): os anéis acompanham o chão"
			var ang := deg_to_rad(18.0)
			_ramp = StaticBody3D.new()
			_ramp.rotation.z = ang
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(9, 0.2, 5)
			cs.shape = bs
			cs.position.y = -0.1
			_ramp.add_child(cs)
			var rm := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = bs.size
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.3, 0.33, 0.28)
			bm.material = mat
			rm.mesh = bm
			rm.position.y = -0.1
			_ramp.add_child(rm)
			add_child(_ramp)
			var sets2 := [["escudo"], ["dragao"], ["heroi", "vento"]]
			for i in sets2.size():
				var l := base.duplicate()
				l.weapon = "iron_sword"
				var r := _knight(i, sets2.size(), l, " + ".join(sets2[i]))
				r.pivot.position.y = tan(ang) * r.pivot.position.x
				var aura := BuffAura.new()
				r.model.add_child(aura)
				aura.set_styles(sets2[i])
	var n := _knights.size()
	var w := n * SPACING
	if pages[page] == "vendaval":
		_cam.position = Vector3(0, 7.0, 13.0)
		_cam.look_at(Vector3(0, 1.0, 0.0))
	elif pages[page] == "faisca" or pages[page] == "arco":
		_cam.position = Vector3(0, 6.0, 11.0)
		_cam.look_at(Vector3(0, 1.0, 0.0))
	elif pages[page] == "meteoros":
		_cam.position = Vector3(0, 9.0, 15.0)
		_cam.look_at(Vector3(0.5, 1.5, -1.0))
	elif pages[page] == "magias":
		_cam.position = Vector3(0, 8.0, 14.0)
		_cam.look_at(Vector3(0, 0.8, 0.0))
	elif pages[page] == "turbilhao":
		_cam.position = Vector3(0, 6.5, 10.5)
		_cam.look_at(Vector3(0, 0.9, 0.3))
	elif pages[page] == "sismico":
		_cam.position = Vector3(0, 5.6, 9.5)
		_cam.look_at(Vector3(0, 0.7, -0.8))
	elif pages[page] == "investida":
		_cam.position = Vector3(0, 5.2, 9.0)
		_cam.look_at(Vector3(0, 0.9, -0.6))
	elif pages[page] == "corte":
		_cam.position = Vector3(0, 5.2, 9.0)
		_cam.look_at(Vector3(0, 0.9, 0))
	elif pages[page].begins_with("perto"):
		_cam.position = Vector3(0, 1.25, 3.6)
		_cam.look_at(Vector3(0, 0.95, 0))
	elif pages[page] in ["auras1", "auras2", "juntas", "rampa"]:
		_cam.position = Vector3(0, 1.9, 7.2)
		_cam.look_at(Vector3(0, 1.05, 0))
	else:
		_cam.position = Vector3(0, 1.6, w * 0.62 + 2.2)
		_cam.look_at(Vector3(0, 1.0, 0))


func _process(delta: float) -> void:
	_t += delta
	for k in _knights:
		if k.has("swing"):
			_swing(k, delta)
			continue
		if k.has("charge"):
			_charge(k, delta)
			continue
		if k.has("quake"):
			_quake(k, delta)
			continue
		if k.has("whirl"):
			_whirl(k, delta)
			continue
		if k.has("spells"):
			_spells(k, delta)
			continue
		if k.has("meteors"):
			_meteors(k, delta)
			continue
		if k.has("bolts"):
			_bolts(k, delta)
			continue
		if k.has("arrows"):
			_arrows(k, delta)
			continue
		if k.has("gale"):
			_gale(k, delta)
			continue
		k.pivot.rotation.y = _turn + sin(_t * 0.6) * 0.35
		KnightAnim.apply(k.rig, KnightAnim.idle_pose(_t), 1.0 - exp(-14.0 * delta))
		KnightAnim.hold_weapon_upright(k.look, k.rig)


## Página "corte": o cavaleiro repete o golpe `swing` do combo e dispara o corte no instante da receita.
func _swing(k: Dictionary, delta: float) -> void:
	var combo: int = k.swing
	var dur: float = [0.42, 0.42, 0.6][combo - 1]
	var t := fmod(_t, 1.2)
	var p := KnightAnim.idle_pose(_t)
	if t < dur:
		KnightAnim.sword_pose(p, combo, t / dur, 0.0)
		KnightAnim.hips_follow(p)
		if not k.fired and t / dur >= FXToon.SWORD_COMBO[combo - 1].at:
			k.fired = true
			FXToon.sword_slash(k.pivot, 0.0, combo, k.color)
	else:
		k.fired = false
	KnightAnim.apply(k.rig, p, 1.0 - exp(-14.0 * delta))   # mesma suavização do jogador
	KnightAnim.hold_weapon_upright(k.look, k.rig)     # como no jogo: o pulso da pose gira a lâmina
	if "--vfxtip" in OS.get_cmdline_user_args() and t < dur and _t < 1.2:
		# medição: ponta da lâmina no espaço do personagem (para alinhar a receita do corte ao golpe)
		var tip: Vector3 = k.pivot.to_local((k.look.tip as Node3D).global_position)
		print("TIP %d %.3f %.3f %.3f %.3f" % [combo, t / dur, tip.x, tip.y, tip.z])


## Página "investida": repete a Investida com os mesmos tempos e chamadas de SwordAbilities._charge_tick.
func _charge(k: Dictionary, delta: float) -> void:
	var c: Dictionary = k.charge
	var t := fmod(_t, 1.5)
	var dir := Vector3(sin(c.yaw), 0, cos(c.yaw))
	var w := SwordAbilities.CHARGE_WINDUP
	var p := KnightAnim.idle_pose(_t)
	if t < SwordAbilities.CHARGE_TIME:
		KnightAnim.play_track(p, KnightMoves.CHARGE, t / SwordAbilities.CHARGE_TIME, 0.0)
		KnightAnim.hips_follow(p)
	var go := clampf((t - w) / SwordAbilities.CHARGE_DASH, 0.0, 1.0)
	k.pivot.position = c.from + dir * SwordAbilities.CHARGE_DIST * (go if t < 1.3 else 0.0)
	KnightAnim.apply(k.rig, p, 1.0 - exp(-14.0 * delta))
	KnightAnim.hold_weapon_upright(k.look, k.rig)
	var tip: Vector3 = (k.look.tip as Node3D).global_position
	if c.phase == 0 and t >= w and t < 1.3:
		c.phase = 1
		FXToon.charge_kick(k.pivot.position, dir)
		c.lance = FXToon.charge_lance(k.pivot.position, dir, Color(0.6, 0.8, 1.0))
	if c.phase == 1:
		if is_instance_valid(c.lance):
			c.lance.reach(tip, (tip + (k.look.holder as Node3D).global_position) * 0.5)
		if go >= 1.0:
			c.phase = 2
			if is_instance_valid(c.lance):
				c.lance.finish()
			FXToon.charge_arrive(k.pivot.position, dir)
	if c.phase == 2 and t >= SwordAbilities.CHARGE_CUT_AT:
		c.phase = 3
		FXToon.charge_cut(k.pivot, Vector3.BACK, Color(0.6, 0.8, 1.0))   # preso ao cavaleiro: frente dele = +Z
	if t < w:
		c.phase = 0
	if "--vfxtip" in OS.get_cmdline_user_args() and _t < 1.5 and t < SwordAbilities.CHARGE_TIME:
		var lt: Vector3 = k.pivot.to_local(tip)
		print("TIP 0 %.3f %.3f %.3f %.3f" % [t, lt.x, lt.y, lt.z])


## Página "sismico": repete o Golpe Sísmico com os tempos e as chamadas de SwordAbilities._quake_tick.
func _quake(k: Dictionary, delta: float) -> void:
	var q: Dictionary = k.quake
	var t := fmod(_t, 2.0)
	var dir := Vector3(sin(q.yaw), 0, cos(q.yaw))
	var p := KnightAnim.idle_pose(_t)
	if t < SwordAbilities.QUAKE_TIME:
		KnightAnim.play_track(p, KnightMoves.QUAKE, t / SwordAbilities.QUAKE_TIME, 0.0)
		KnightAnim.hips_follow(p)
	KnightAnim.apply(k.rig, p, 1.0 - exp(-14.0 * delta))
	KnightAnim.hold_weapon_upright(k.look, k.rig)
	var tip: Vector3 = (k.look.tip as Node3D).global_position
	var base: Vector3 = k.pivot.position
	if q.phase == 0 and t >= SwordAbilities.QUAKE_CUT_AT and t < 1.0:
		q.phase = 1
		FXToon.quake_cut(k.pivot, Vector3.BACK, Color(0.6, 0.8, 1.0))   # preso ao cavaleiro: frente dele = +Z
	if q.phase == 1 and t >= SwordAbilities.QUAKE_WINDUP:
		q.phase = 2
		q.wave = 0
		FXToon.quake_impact(base, dir, base + dir * SwordAbilities.QUAKE_TIP, SwordAbilities.QUAKE_RANGE,
			SwordAbilities.QUAKE_HALF_ANGLE, SwordAbilities.QUAKE_WAVE_STEP)
	if q.phase == 2:
		var reach: int = mini(int((t - SwordAbilities.QUAKE_WINDUP) / SwordAbilities.QUAKE_WAVE_STEP), int(SwordAbilities.QUAKE_RANGE))
		while q.wave < reach:
			q.wave += 1
			FXToon.quake_wave(base, dir, q.wave, SwordAbilities.QUAKE_HALF_ANGLE)
	if t < 0.1:
		q.phase = 0
	if "--vfxtip" in OS.get_cmdline_user_args() and _t < 2.0 and t < SwordAbilities.QUAKE_TIME:
		var lt: Vector3 = k.pivot.to_local(tip)
		print("TIP 0 %.3f %.3f %.3f %.3f" % [t, lt.x, lt.y, lt.z])


## Página "turbilhao": repete o Turbilhão com os tempos e as chamadas de SwordAbilities._whirl_tick.
func _whirl(k: Dictionary, delta: float) -> void:
	var w: Dictionary = k.whirl
	var t := fmod(_t, 3.4)
	var dir := Vector3(sin(w.yaw), 0, cos(w.yaw))
	var p := KnightAnim.idle_pose(_t)
	var on := t < SwordAbilities.WHIRL_TIME
	if on:
		KnightAnim.play_track(p, KnightMoves.WHIRL, t / SwordAbilities.WHIRL_TIME, 0.0)
		KnightAnim.hips_follow(p)
	(k.model as Node3D).rotation.y = wrapf(SwordAbilities._whirl_angle(t - SwordAbilities.WHIRL_WINDUP), -PI, PI) if on else 0.0
	KnightAnim.apply(k.rig, p, 1.0 - exp(-14.0 * delta))
	KnightAnim.hold_weapon_upright(k.look, k.rig)
	var base: Vector3 = k.pivot.position
	if w.phase == 0 and t >= SwordAbilities.WHIRL_WINDUP and t < 1.0:
		w.phase = 1
		FXToon.whirl_spin(k.pivot, k.look.tip, SwordAbilities.WHIRL_SPIN)
	if w.phase == 1 and t >= SwordAbilities.WHIRL_CUT_AT:
		w.phase = 2
		FXToon.whirl_cut(k.pivot, Vector3.BACK)   # preso ao cavaleiro: frente dele = +Z
	if w.phase == 2 and t >= SwordAbilities.WHIRL_IMPACT:
		w.phase = 3
		FXToon.whirl_finale(base, dir, base + dir * SwordAbilities.WHIRL_TIP, SwordAbilities.WHIRL_FINAL_RADIUS)
	if t < 0.1:
		w.phase = 0
	if "--vfxtip" in OS.get_cmdline_user_args() and _t < 3.4 and on:
		var lt: Vector3 = k.pivot.to_local((k.look.tip as Node3D).global_position)
		print("TIP 0 %.3f %.3f %.3f %.3f" % [t, lt.x, lt.y, lt.z])


## Página "magias": a cada 4,6 s lança a Bola de Fogo (0,3 s), a Nova Gélida (1,7 s) e a Cura (3,3 s), com as
## mesmas chamadas do jogo (fireball.gd só visual, FXToon.frost_nova e FXToon.heal).
func _spells(k: Dictionary, delta: float) -> void:
	var sp: Dictionary = k.spells
	var t := fmod(_t, 4.6)
	var dir := Vector3(sin(sp.yaw), 0, cos(sp.yaw))
	var p := KnightAnim.idle_pose(_t)
	var cast := [[0.3, "fireball"], [1.7, "frost_nova"], [3.3, "heal"]]
	for c in cast:
		var ct: float = t - (float(c[0]) - 0.12)
		if ct >= 0.0 and ct < KnightMoves.CAST_TIME:
			KnightAnim.cast_pose(p, c[1], ct / KnightMoves.CAST_TIME, 0.0, true)
	KnightAnim.apply(k.rig, p, 1.0 - exp(-14.0 * delta))
	KnightAnim.hold_weapon_upright(k.look, k.rig)
	if t < 0.1:
		sp.step = 0
	if sp.step < cast.size() and t >= float(cast[sp.step][0]):
		match str(cast[sp.step][1]):
			"fireball":
				var fb: Area3D = preload("res://scripts/player/fireball.gd").new()
				fb.direction = dir
				fb.visual_only = true
				fb.life = 0.38
				add_child(fb)
				fb.global_position = (k.look.tip as Node3D).global_position
			"frost_nova":
				FXToon.frost_nova(k.pivot.position, 6.5)
			"heal":
				FXToon.heal(k.pivot)
		sp.step += 1


## Página "meteoros": a cada 4,5 s abre o círculo de runas e derruba meteoros (StaffAbilities.MeteorStrike,
## só visual) por 2,4 s, no ritmo e com a diagonal da habilidade.
func _meteors(k: Dictionary, delta: float) -> void:
	var m: Dictionary = k.meteors
	var t := fmod(_t, 4.5)
	KnightAnim.apply(k.rig, KnightAnim.idle_pose(_t), 1.0 - exp(-14.0 * delta))
	KnightAnim.hold_weapon_upright(k.look, k.rig)
	if t < 0.1:
		m.on = false
	if not m.on and t >= 0.3:
		m.on = true
		m.next = 0.3
		m.sigil = FXToon.rune_circle(m.center, StaffAbilities.METEOR_AREA)
	if m.on and t < 2.7:
		while float(m.next) <= t:
			m.next = float(m.next) + StaffAbilities.METEOR_INTERVAL
			var a := randf() * TAU
			var s := StaffAbilities.MeteorStrike.new()
			s.target = (m.center as Vector3) + Vector3(cos(a), 0, sin(a)) * StaffAbilities.METEOR_AREA * sqrt(randf())
			s.start = s.target + Vector3(-0.6, 0, -0.8).normalized() * StaffAbilities.METEOR_SLANT + Vector3.UP * StaffAbilities.METEOR_HEIGHT
			s.size = randf_range(0.8, 1.35)
			add_child(s)
	if m.on and t >= 3.0 and is_instance_valid(m.sigil):
		m.sigil.release()
		m.sigil = null


## Página "faisca": a cada 3 s dispara uma faísca (0,2 s), o leque de três do 3º golpe (1,0 s) e mostra o
## estouro em área de energia (1,9 s), com projectile.gd só visual.
func _bolts(k: Dictionary, delta: float) -> void:
	var b: Dictionary = k.bolts
	var t := fmod(_t, 3.0)
	var dir := Vector3(sin(b.yaw), 0, cos(b.yaw))
	var p := KnightAnim.idle_pose(_t)
	var shots := [[0.2, 1], [1.0, 3]]
	for sh in shots:
		var dur: float = [0.42, 0.42, 0.6][int(sh[1]) - 1]
		var st: float = t - (float(sh[0]) - dur * 0.35)
		if st >= 0.0 and st < dur:
			KnightAnim.staff_pose(p, sh[1], st / dur, 0.0)
	KnightAnim.apply(k.rig, p, 1.0 - exp(-14.0 * delta))
	KnightAnim.hold_weapon_upright(k.look, k.rig)
	if t < 0.1:
		b.step = 0
	var tip: Vector3 = (k.look.tip as Node3D).global_position
	if b.step < shots.size() and t >= float(shots[b.step][0]):
		for a in ([0.0] if int(shots[b.step][1]) < 3 else [-0.14, 0.0, 0.14]):
			var pr: Area3D = preload("res://scripts/player/projectile.gd").new()
			pr.kind = "bolt"
			pr.direction = dir.rotated(Vector3.UP, a)
			pr.visual_only = true
			pr.life = 0.3
			pr.color = Color(0.6, 0.8, 1.0) if b.step == 0 else Color(0.65, 0.55, 1.0)
			add_child(pr)
			pr.global_position = tip
		b.step += 1
	if b.step == shots.size() and t >= 1.9:
		b.step += 1
		FXToon.energy_burst(k.pivot.position + dir * 6.0 + Vector3.UP * 0.9, FXToon.palette(Color(0.65, 0.55, 1.0)))


## Página "arco": a cada 3,6 s solta uma flecha (0,2 s), o Tiro Triplo (0,9 s) e a Flecha Glacial (carga em
## 1,5 s, tiro em 1,9 s, gelo no alvo em 2,2 s), com projectile.gd só visual e as chamadas de BowAbilities.
func _arrows(k: Dictionary, delta: float) -> void:
	var ar: Dictionary = k.arrows
	var t := fmod(_t, 3.6)
	var dir := Vector3(sin(ar.yaw), 0, cos(ar.yaw))
	KnightAnim.apply(k.rig, KnightAnim.idle_pose(_t), 1.0 - exp(-14.0 * delta))
	KnightAnim.hold_weapon_upright(k.look, k.rig)
	if t < 0.1:
		ar.step = 0
	var origin: Vector3 = k.pivot.position + dir * 0.6 + Vector3.UP * 1.35
	var times := [0.2, 0.9, 1.5, 1.9, 2.2]
	if ar.step < times.size() and t >= float(times[ar.step]):
		var shoot := func(d: Vector3, frost: bool) -> void:
			var pr: Area3D = preload("res://scripts/player/projectile.gd").new()
			pr.kind = "arrow"
			pr.direction = d
			pr.visual_only = true
			pr.speed = 40.0 if frost else 34.0
			pr.life = 0.26
			if frost:
				pr.fx = "glacial"
				pr.color = BowAbilities.FROST_COLOR
			add_child(pr)
			pr.global_position = origin
		match int(ar.step):
			0:
				shoot.call(dir, false)
			1:
				for d in BowAbilities._triple_dirs(dir):
					shoot.call(d, false)
				BowAbilities._triple_fx(null, origin, dir)
			2:
				BowAbilities._frost_glow(origin)
			3:
				shoot.call(dir, true)
				BowAbilities._frost_fx(origin, dir)
			4:
				FXToon.frost_hit(k.pivot.position + dir * 9.5, 1.3)
		ar.step += 1


## Página "vendaval": a cada 3,4 s tensiona por GALE_CHARGE (FXToon.gale_charge) e dispara
## (FXToon.gale_fire + BowAbilities.GaleLine, com 14 m de linha para caber na tela).
func _gale(k: Dictionary, delta: float) -> void:
	var g: Dictionary = k.gale
	var t := fmod(_t, 3.4)
	var dir := Vector3(sin(g.yaw), 0, cos(g.yaw))
	var fire_t := 0.2 + BowAbilities.GALE_CHARGE
	# a pose do jogo (BowAbilities.pose): agacha e inclina para trás com a carga, tranco no disparo
	var p := KnightAnim.idle_pose(_t)
	if t >= 0.2 and t < fire_t:
		KnightAnim.bow_gale_pose(p, clampf((t - 0.2) / BowAbilities.GALE_CHARGE, 0.0, 1.0))
		KnightAnim.hips_follow(p)
	elif t >= fire_t and t < fire_t + BowAbilities.GALE_RECOVER:
		KnightAnim.bow_gale_pose(p, 1.0, (t - fire_t) / BowAbilities.GALE_RECOVER)
		KnightAnim.hips_follow(p)
	KnightAnim.apply(k.rig, p, 1.0 - exp(-14.0 * delta))
	KnightAnim.hold_weapon_upright(k.look, k.rig)
	if t < 0.1:
		g.phase = 0
	if g.phase == 0 and t >= 0.2:
		g.phase = 1
		g.fx = FXToon.gale_charge(k.pivot, k.look.tip)
	if g.phase == 1:
		if is_instance_valid(g.fx):
			g.fx.charge = clampf((t - 0.2) / BowAbilities.GALE_CHARGE, 0.0, 1.0)
		if t >= fire_t:
			g.phase = 2
			if is_instance_valid(g.fx):
				g.fx.queue_free()
			var origin: Vector3 = k.pivot.position + Vector3.UP * BowAbilities.GALE_HEIGHT
			FXToon.gale_fire(k.pivot.position, origin, dir, 1.0)
			var line := BowAbilities.GaleLine.new()
			line.origin = origin
			line.dir = dir
			line.length = 14.0
			line.charge = 1.0
			add_child(line)


func _take_seq() -> void:
	DirAccess.make_dir_recursive_absolute(_seq_dir)
	await get_tree().create_timer(0.5).timeout
	var loop: float = {"investida": 1.5, "sismico": 2.0, "turbilhao": 3.4, "magias": 4.6, "meteoros": 4.5, "faisca": 3.0, "arco": 3.6, "vendaval": 3.4}.get(pages[page], 1.2)
	while fmod(_t, loop) > 0.05:      # espera o começo de um golpe
		await get_tree().process_frame
	for i in int({"sismico": 90, "turbilhao": 170, "magias": 260, "meteoros": 230, "faisca": 150, "arco": 200, "vendaval": 150}.get(pages[page], 50)):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%03d.png" % [_seq_dir, i])
	get_tree().quit()


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_TAB:
				page = (page + 1) % pages.size()
				_show_page()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7:
				page = ev.keycode - KEY_1
				_show_page()
			KEY_RIGHT, KEY_LEFT:
				var d := 1 if ev.keycode == KEY_RIGHT else -1
				element_i = posmod(element_i + d, EnchantFX.ELEMENTS.size())
				if pages[page] == "niveis":
					_show_page()
			KEY_ESCAPE:
				get_tree().quit()
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		_drag = ev.pressed
	elif ev is InputEventMouseMotion and _drag:
		_turn += ev.relative.x * 0.01


func _take_shots() -> void:
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	for p in pages.size():
		page = p
		_show_page()
		await get_tree().create_timer(1.6).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%d_%s.png" % [_shot_dir, p + 1, pages[p]])
	# níveis de mais dois elementos para comparar
	page = 0
	for ei in [1, 2]:
		element_i = ei
		_show_page()
		await get_tree().create_timer(1.6).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/1_niveis_%s.png" % [_shot_dir, EnchantFX.ELEMENTS.keys()[ei]])
	get_tree().quit()
