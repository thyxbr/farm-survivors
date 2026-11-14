extends Node3D
## PROTÓTIPO (spike): vitrine dos efeitos de encantamento e de aura de buff.
## Teclas: Tab / 1-7 trocam a página · ←/→ trocam o elemento (página "Níveis") · arraste para girar.
## Com `-- --vfxshot=<pasta>` salva um PNG de cada página e fecha.

const KNIGHT := preload("res://assets/models/knight.glb")
var SPACING := 1.45

var pages := ["niveis", "elementos", "armas", "auras1", "auras2", "juntas", "rampa"]
var page := 0
var element_i := 0
var _knights: Array = []     # [{"model", "rig", "look", "pivot"}]
var _t := 0.0
var _title: Label
var _cam: Camera3D
var _shot_dir := ""
var _turn := 0.0
var _drag := false
var _ramp: StaticBody3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--vfxshot="):
			_shot_dir = a.substr(10)
		elif a.begins_with("--vfxpage="):
			page = clampi(int(a.substr(10)) - 1, 0, pages.size() - 1)
	_setup_world()
	_show_page()
	if _shot_dir != "":
		_take_shots()


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
				var r := _knight(i, foods.size(), l, "%s\n%s" % [it.name, it.buff.name])
				var aura := BuffAura.new()
				r.model.add_child(aura)
				aura.set_buffs([foods[i]])
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
	if pages[page] in ["auras1", "auras2", "juntas", "rampa"]:
		_cam.position = Vector3(0, 1.9, 7.2)
		_cam.look_at(Vector3(0, 1.05, 0))
	else:
		_cam.position = Vector3(0, 1.6, w * 0.62 + 2.2)
		_cam.look_at(Vector3(0, 1.0, 0))


func _process(delta: float) -> void:
	_t += delta
	for k in _knights:
		k.pivot.rotation.y = _turn + sin(_t * 0.6) * 0.35
		KnightAnim.apply(k.rig, KnightAnim.idle_pose(_t), 1.0 - exp(-14.0 * delta))
		KnightAnim.hold_weapon_upright(k.look, k.rig)


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
