class_name ColonyVillager
extends Node3D
## Aldeão decorativo (só no cliente com tela, nunca no headless): plebeu com esqueleto (assets/models/villager_<n>.glb,
## três variações de roupa) tocando os clipes de assets/animations/villager_mixamo.res (tools/build_npc_mixamo.gd):
## parado, andando e o trabalho do ofício da construção. Anda da porta até o alvo de trabalho, trabalha alguns
## ciclos do clipe e volta. A ferramenta do ofício segue as mãos a cada quadro (place_prop). Sem colisão nem rede.

const MODELS: Array[PackedScene] = [
	preload("res://assets/models/villager_1.glb"),
	preload("res://assets/models/villager_2.glb"),
	preload("res://assets/models/villager_3.glb"),
]
const LIBRARY := "res://assets/animations/villager_mixamo.res"
const CRATE := preload("res://assets/models/crate.glb")
const SPEED := 1.4
const STRIDE_SPEED := 1.1   # m/s que os clipes de andar do Mixamo cobrem em velocidade 1 (modelo em escala 1)
const BLEND := 0.25
## Ofício por construção (as demais ficam de vigia com a lança): ferramenta (assets/models/buildings/tool_<nome>.glb
## ou o caixote), clipes de trabalho (um é sorteado a cada ida) e quantos ciclos do clipe dura o trabalho.
const JOBS := {
	"lumber_camp": {"tool": "axe", "work": ["chop"], "loops": 3},
	"quarry": {"tool": "pickaxe", "work": ["chop"], "loops": 3},
	"farm": {"tool": "hoe", "work": ["hoe", "hoe", "dig"], "loops": 2},
	"market": {"tool": "crate", "work": ["carry_idle"], "loops": 1},
}
const GUARD := {"tool": "spear", "work": ["idle"], "loops": 1}
## Clipes em que a ferramenta fica nas duas mãos (o cabo passa pelas duas palmas) e em que fica largada no chão.
## Machado e picareta parados ou andando: a mão segura a CARRY_GRIP metros da origem (logo abaixo da cabeça da
## ferramenta) e o cabo pende para baixo, CARRY_TILT radianos para trás.
const CARRY_GRIP := 0.28
const CARRY_TILT := -0.3
const TWO_HANDS := ["hoe", "chop"]
const ON_GROUND := ["dig"]
## Caixote do tamanho que o clipe de carregar do Mixamo espera: a mão direita por baixo, junto do quadril, e a
## esquerda por cima do canto de lá (as palmas ficam a uns 50 cm uma da outra de lado e 30 cm na altura).
const CRATE_SIZE := Vector3(0.5, 0.3, 0.36)
## Centro da palma em relação ao punho, na pose T, para a mão esquerda (a direita espelha em X).
const PALM := Vector3(0.065, -0.03, 0.0)

var home: ColonyBuilding
var model: Node3D
var tool_name := ""
var _made := {}        # o que make_model devolveu
var _state := "idle"   # idle | go | work | back
var _t := 0.0
var _work_time := 3.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _target_id := -1


func _ready() -> void:
	add_to_group("villager_visual")
	_made = make_model(home.kind)
	model = _made.model
	tool_name = _made.tool
	add_child(model)
	var sk: Skeleton3D = _made.skeleton
	if sk:
		sk.skeleton_updated.connect(place_prop.bind(_made))
	_idle(randf() * 4.0)


## Monta o modelo de um aldeão que trabalha numa construção `kind`: {"model", "anim" (AnimationPlayer),
## "skeleton", "job" (linha de JOBS), "tool" (nome), "prop" (a ferramenta ou o caixote, filho do modelo) e o
## que play()/place_prop() usam}. `look` escolhe a roupa (1 a MODELS.size(); 0 = sorteia).
static func make_model(kind: String, look := 0) -> Dictionary:
	var m: Node3D = (MODELS[look - 1] if look > 0 else MODELS.pick_random()).instantiate()
	m.scale = Vector3.ONE * randf_range(0.9, 0.98)
	var job: Dictionary = JOBS.get(kind, GUARD)
	var ap := SkinnedNPC.pose_model(m, {}, LIBRARY)
	var sks := m.find_children("*", "Skeleton3D")
	var sk: Skeleton3D = sks[0] if sks.size() > 0 else null
	var v := {"model": m, "anim": ap, "skeleton": sk, "job": job, "tool": job.tool, "prop": null, "clip": "",
			"mode": "", "since": 0.0, "from": Transform3D.IDENTITY}
	var prop: Node3D = null
	if job.tool == "crate":
		prop = Node3D.new()
		var c: Node3D = CRATE.instantiate()   # origem do crate.glb na base, que assenta na palma direita
		c.scale = CRATE_SIZE
		prop.add_child(c)
	else:
		var path := "res://assets/models/buildings/tool_%s.glb" % job.tool
		if ResourceLoader.exists(path):
			prop = (load(path) as PackedScene).instantiate()
	if prop and sk:
		prop.name = "Prop"
		m.add_child(prop)
		if ToonLook.enabled():
			ToonLook.apply(prop)
		var to_model := SkinnedNPC._xform_to(sk, m)
		v["to_model"] = to_model
		for side in ["Right", "Left"]:
			var i := sk.find_bone(side + "Hand")
			var rest := sk.get_bone_global_rest(i)
			var s := -1.0 if side == "Right" else 1.0
			v["bone_" + side] = i
			# palma no espaço do osso, medida na pose T (espaço do modelo: esquerda = +X, frente = +Z)
			v["palm_" + side] = (to_model * rest).affine_inverse() * (to_model * rest.origin + PALM * Vector3(s, 1, 1))
	else:
		prop = null
	v.prop = prop
	play(v, "idle", 0.0)
	return v


## Nome do clipe do estado ("idle", "walk" ou um de trabalho) para a ferramenta que o aldeão leva: quem
## carrega o caixote anda e para com os clipes de carregar.
static func clip_for(v: Dictionary, state: String) -> String:
	if v.tool == "crate" and state in ["idle", "walk"]:
		return "carry_" + state
	return state


## Toca o clipe do estado (versão do Mixamo, se a biblioteca tiver) e escolhe como a ferramenta fica.
static func play(v: Dictionary, state: String, blend := BLEND, speed := 1.0) -> void:
	var c := clip_for(v, state)
	if c in ON_GROUND or v.clip in ON_GROUND:
		blend = minf(blend * 2.0, blend + 0.3)   # ajoelhar e levantar pedem uma passagem mais longa
	var ap: AnimationPlayer = v.anim
	if ap:
		var n := SkinnedNPC._resolve(ap, c)
		if ap.has_animation(n):
			ap.play(n, blend, speed)
	var mode := "carry"   # machado e picareta: pendurados da mão, seguros logo abaixo da cabeça
	if v.tool == "crate":
		mode = "crate"
	elif c in TWO_HANDS:
		mode = "two"
	elif c in ON_GROUND:
		mode = "ground"
	elif v.tool == "spear" or v.tool == "hoe":
		mode = "upright"   # lança e enxada vão de pé, como um cajado
	v.clip = c
	if mode != v.mode and v.prop:
		v.from = (v.prop as Node3D).transform
		v.since = 0.0 if v.mode != "" and blend > 0.0 else BLEND
		v.mode = mode


## Duração de um ciclo do clipe do estado, em segundos.
static func clip_length(v: Dictionary, state: String) -> float:
	var ap: AnimationPlayer = v.anim
	var n := SkinnedNPC._resolve(ap, clip_for(v, state)) if ap else ""
	return ap.get_animation(n).length if ap and ap.has_animation(n) else 1.0


## Leva a ferramenta para onde as mãos estão na pose atual do esqueleto (chamado a cada skeleton_updated):
## com o cabo passando pelas duas palmas ("two": a esquerda atrás, a direita à frente, o gume para o lado de
## baixo do golpe), de pé na mão direita ("upright"), pendurada da mão direita, segura perto da cabeça e com o
## cabo para baixo ("carry"), largada no chão ("ground") ou, no caso do caixote, entre as duas mãos com a base
## na palma direita ("crate"). Na troca de modo, vai de um ao outro em BLEND s.
static func place_prop(v: Dictionary) -> void:
	var prop: Node3D = v.prop
	var sk: Skeleton3D = v.skeleton
	if prop == null or sk == null:
		return
	var to_model: Transform3D = v.to_model
	var hand_r: Transform3D = to_model * sk.get_bone_global_pose(v.bone_Right)
	var hand_l: Transform3D = to_model * sk.get_bone_global_pose(v.bone_Left)
	var pr: Vector3 = hand_r * v.palm_Right
	var pl: Vector3 = hand_l * v.palm_Left
	var xf := Transform3D.IDENTITY
	match v.mode:
		"two":
			var y := (pr - pl).normalized()
			var x := y.cross(Vector3.LEFT).normalized()   # Vector3.LEFT = direita do aldeão (ele olha para +Z)
			xf = Transform3D(Basis(x, y, x.cross(y)), pr)
		"upright":
			xf = Transform3D(Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)), pr)
		"ground":
			xf = Transform3D(Basis(Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)), Vector3(-0.55, 0.03, -0.1))
		"crate":
			xf = Transform3D(Basis.IDENTITY, Vector3((pr.x + pl.x) * 0.5, pr.y, (pr.z + pl.z) * 0.5))
		_:   # "carry"
			var b := Basis(Vector3.RIGHT, CARRY_TILT) * Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0))
			xf = Transform3D(b, pr - b.y * CARRY_GRIP)
	if v.since < BLEND:
		xf = (v.from as Transform3D).interpolate_with(xf, smoothstep(0.0, 1.0, v.since / BLEND))
	prop.transform = xf


func _play(state: String, speed := 1.0) -> void:
	play(_made, state, BLEND, speed)


func _door() -> Vector3:
	return home.global_transform * Vector3(randf_range(-0.6, 0.6), 0, home.size.y / 2.0 + 0.6)


func _flat_y() -> float:
	return home.global_position.y


func _idle(wait: float) -> void:
	_state = "idle"
	_t = wait
	_target_id = -1
	global_position = _door()
	_play("idle")


func _pick_target() -> bool:
	var nat = home.colony.nature if home.colony else null
	match home.kind:
		"lumber_camp", "quarry":
			if nat == null:
				return false
			var ids: Array[int] = nat.alive_near(home.data.gather, home.global_position, float(home.data.reach))
			if ids.is_empty():
				return false
			var best := -1
			var bd := INF
			for id in ids:
				var d: float = nat.node(id).global_position.distance_to(home.global_position) + randf() * 3.0
				if d < bd:
					bd = d
					best = id
			_target_id = best
			var np: Vector3 = nat.node(best).global_position
			var dir := (home.global_position - np) * Vector3(1, 0, 1)
			_to = np + dir.normalized() * 0.9
		"farm":
			_to = home.global_transform * Vector3(randf_range(-2.6, 2.6), 0, randf_range(-5.0, -1.2))
		"market":
			var sx := -1.0 if randf() < 0.5 else 1.0
			_to = home.global_transform * Vector3(sx * 1.6 + randf_range(-0.4, 0.4), 0, randf_range(-1.0, 1.2))
		_:   # torre e demais: parado ao pé
			_to = home.global_transform * Vector3(randf_range(-1.4, 1.4), 0, home.size.y / 2.0 + 0.9)
	_to.y = _flat_y()
	return true


func _go(to: Vector3, next: String) -> void:
	_from = global_position
	_to = to
	_state = next
	_t = 0.0
	# o passo do clipe acompanha a velocidade com que o aldeão se desloca
	_play("walk", SPEED / (STRIDE_SPEED * model.scale.x))


func _work() -> void:
	_state = "work"
	_t = 0.0
	var job: Dictionary = _made.job
	var clip: String = (job.work as Array).pick_random()
	_work_time = clip_length(_made, clip) * (1 if clip in ON_GROUND else int(job.loops))
	_play(clip)


func _process(delta: float) -> void:
	if not is_instance_valid(home):
		return
	_made.since += delta
	match _state:
		"idle":
			_t -= delta
			if _t <= 0.0:
				if _pick_target():
					_go(_to, "go")
				else:
					_idle(3.0)
		"go", "back":
			var dist := maxf(0.01, Vector2(_to.x - _from.x, _to.z - _from.z).length())
			_t += delta * SPEED / dist
			var p := _from.lerp(_to, clampf(_t, 0.0, 1.0))
			p.y = _flat_y()
			global_position = p
			if dist > 0.05:
				global_rotation.y = atan2(_to.x - _from.x, _to.z - _from.z)
			if _t >= 1.0:
				if _state == "go":
					_work()
				else:
					_idle(randf_range(1.0, 4.0))
		"work":
			_t += delta
			if _target_id >= 0 and home.colony and home.colony.nature:
				var n = home.colony.nature.node(_target_id)
				if n and n.alive:
					var d: Vector3 = n.global_position - global_position
					global_rotation.y = atan2(d.x, d.z)
			if _t >= _work_time:
				_go(_door(), "back")
