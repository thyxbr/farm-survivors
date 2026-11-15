class_name ColonyVillager
extends Node3D
## Aldeão decorativo (só no cliente com tela, nunca no headless): o boneco do cavaleiro vestido de plebeu
## (KnightLook) com a ferramenta do ofício na mão direita. Anda da porta da construção até o alvo de
## trabalho, golpeia por alguns segundos e volta. Sem colisão nem rede.

const KNIGHT := preload("res://assets/models/knight.glb")
const CRATE := preload("res://assets/models/crate.glb")
const WORK_TIME := 3.0
const SPEED := 1.6
const SWING := 0.9          # segundos de um golpe da ferramenta
## Capina (enxada, duas mãos, corpo inclinado): o ciclo leva HOE_CYCLE segundos. Cada linha é uma chave
## [fração do ciclo, braço, cotovelo, inclinação do corpo, inclinação do cabo]: ergue e leva a enxada para a
## frente, crava a lâmina no chão, puxa para perto dos pés e descansa um instante.
## Inclinação do cabo: giro em X no espaço do boneco (0 = apontado para a frente, positivo = lâmina para baixo).
const HOE_CYCLE := 1.5
const HOE_KEYS := [
	[0.0, -0.7, -0.8, 0.42, 0.98],     # fim da puxada: lâmina perto dos pés
	[0.32, -1.2, -0.3, 0.3, 0.36],     # erguida e levada à frente
	[0.46, -0.95, -0.25, 0.5, 0.7],    # cravada no chão, braço da frente estendido
	[0.88, -0.7, -0.8, 0.42, 0.98],    # puxada até os pés
	[1.0, -0.7, -0.8, 0.42, 0.98],
]
## As duas mãos ficam no cabo, uma na frente da outra: a direita vai à frente (é onde o suporte da ferramenta
## fica) e a esquerda segura HOE_GAP metros atrás, perto do quadril, na frente da barriga, levada até lá por
## _reach_left.
const HOE_GAP := 0.32
## Carregando o caixote: braço um pouco à frente e cotovelo dobrado, antebraço quase na horizontal.
const CARRY_ARM := -0.4
const CARRY_ELBOW := -1.1
const CARRY_IN := 0.3       # antebraços fechados para dentro
const CARRY_DROP := 0.3     # quanto abaixo do ombro fica a base do caixote (em cima dos antebraços)
const CARRY_FRONT := 0.36   # centro do caixote à frente do corpo
## Roupas sorteadas ("" = camisa, cabeça descoberta, sapatos).
const ARMORS := ["", "", "traveler_tunic", "ranger_vest", "leather_armor"]
const HEADS := ["", "", "leather_cap", "wool_hood", "ranger_hood"]
const FEET := ["", "leather_boots"]
## Ferramenta por construção (as demais levam a lança de vigia): assets/models/buildings/tool_<nome>.glb.
const TOOLS := {"lumber_camp": "axe", "quarry": "pickaxe", "farm": "hoe", "market": "crate"}
## Mesma base das armas modeladas (KnightLook._build_model): cabo do GLB (+Y) vai para +Z do suporte e o
## gume (+X do GLB) para -Y, liderando o golpe.
const TOOL_BASIS := Basis(Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0))

var home: ColonyBuilding
var model: Node3D
var parts := {}
var tool_name := ""
var _holder: Node3D
var _made := {}        # o que make_model devolveu (pose() guarda nele o que mede do boneco)
var _state := "idle"   # idle | go | work | back
var _t := 0.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _target_id := -1
var _bob := 0.0


func _ready() -> void:
	add_to_group("villager_visual")
	_made = make_model(home.kind)
	model = _made.model
	parts = _made.parts
	tool_name = _made.tool
	_holder = _made.holder
	add_child(model)
	_idle(randf() * 4.0)


## Monta o boneco de um aldeão que trabalha numa construção `kind`:
## {"model", "parts" (pivôs LegL/LegR/ArmL/ArmR/Body), "tool" (nome), "holder" (suporte da ferramenta ou null)}.
static func make_model(kind: String) -> Dictionary:
	var m: Node3D = KNIGHT.instantiate()
	m.scale = Vector3.ONE * randf_range(0.86, 0.94)
	var p := {}
	for n in ["LegL", "LegR", "ArmL", "ArmR", "ElbowL", "ElbowR", "Body"]:
		p[n] = m.find_child(n, true, false)
	KnightLook.apply(m, {"armor": ARMORS.pick_random(), "head": HEADS.pick_random(), "feet": FEET.pick_random()})
	var tool: String = TOOLS.get(kind, "spear")
	var holder: Node3D = null
	if tool == "crate":   # caixote apoiado nos antebraços dobrados, encostado na barriga
		var body: Node3D = p.Body
		if body and p.ArmL:
			# altura do ombro no espaço do corpo: os antebraços ficam CARRY_DROP abaixo dele (veja pose)
			var shoulder: Vector3 = KnightLook._chain(body, m, true).affine_inverse() * KnightLook._chain(p.ArmL, m, true).origin
			holder = Node3D.new()
			holder.name = "Carry"
			holder.position = Vector3(0, shoulder.y - CARRY_DROP, CARRY_FRONT)
			body.add_child(holder)
			var c: Node3D = CRATE.instantiate()   # origem do crate.glb no chão: a base assenta nos antebraços
			c.scale = Vector3.ONE * 0.36
			holder.add_child(c)
	else:
		var fore := m.find_child("ElbowR", true, false) as Node3D
		if fore == null:
			fore = p.ArmR
		var path := "res://assets/models/buildings/tool_%s.glb" % tool
		if fore and ResourceLoader.exists(path):
			holder = Node3D.new()
			holder.name = "ToolHolder"
			holder.position = KnightLook._point_in(m, fore, "Grip")
			fore.add_child(holder)
			var t := (load(path) as PackedScene).instantiate() as Node3D
			t.transform = Transform3D(TOOL_BASIS, Vector3.ZERO)
			holder.add_child(t)
	if holder and ToonLook.enabled():
		ToonLook.apply(holder)
	var res := {"model": m, "parts": p, "tool": tool, "holder": holder}
	pose(res, "idle", 0.0)
	return res


## Põe o boneco numa pose: "idle" (parado), "walk" (t = fase do passo, em radianos) ou "work"
## (t = segundos desde o começo do trabalho). `k` = quanto se aproxima da pose (1 = na hora).
static func pose(v: Dictionary, state: String, t: float, k := 1.0) -> void:
	var p: Dictionary = v.parts
	var tool: String = v.tool
	var s := sin(t) if state == "walk" else 0.0
	var leg := s * 0.55
	var arm_l := Vector3(-s * 0.4, 0, 0)
	var arm_r := Vector3(s * 0.3 - 0.15, 0, 0)
	var lean := 0.0
	var elbow_l := 0.0
	var elbow_r := 0.0
	# Inclinação da ferramenta em relação ao corpo (giro em X somando braço + suporte): 0 = apontada para a
	# frente como uma espada, -PI/2 = de pé. Parado e andando ela vai de pé, encostada no ombro.
	var tilt := -1.85
	var follow := false   # a ferramenta segue o antebraço (golpe de machado e picareta)
	match tool:
		"crate":   # cotovelos dobrados, antebraços por baixo do caixote (o passo balança só de leve)
			# o giro em Y fecha os antebraços para dentro: as mãos encostam nas laterais do caixote
			arm_l = Vector3(CARRY_ARM + s * 0.04, -CARRY_IN, 0.06)
			arm_r = Vector3(CARRY_ARM - s * 0.04, CARRY_IN, -0.06)
			elbow_l = CARRY_ELBOW
			elbow_r = CARRY_ELBOW
			lean = -0.06   # corpo um pouco para trás, compensando o peso
		"spear":   # lança de pé, apoiada no chão
			arm_r = Vector3(-0.35, 0, 0)
			tilt = -PI / 2
		_:
			if state == "work" and tool == "hoe":
				var key := _hoe_key(fmod(t, HOE_CYCLE) / HOE_CYCLE)
				arm_r = Vector3(key[1], 0.3, 0.0)   # fechado para dentro: o cabo fica na frente do corpo
				elbow_r = key[2]
				lean = key[3]
				tilt = key[4]
				arm_l = Vector3(key[1] - 0.3, -0.4, 0.0)   # palpite inicial; _reach_left acerta a mão no cabo
				elbow_l = key[2] * 0.6
			elif state == "work":
				var u := fmod(t, SWING) / SWING
				var up := Vector3(-2.5, 0, -0.2)
				var down := Vector3(-0.35, 0, 0.1)
				if u < 0.5:
					arm_r = down.lerp(up, smoothstep(0.0, 0.5, u))
				elif u < 0.68:
					arm_r = up.lerp(down, smoothstep(0.5, 0.68, u))
				else:
					arm_r = down
				lean = 0.12 + (0.22 if u >= 0.6 else 0.0)
				arm_l = Vector3(-0.5, 0, 0)
				follow = true
	if p.LegL:
		p.LegL.rotation.x = lerpf(p.LegL.rotation.x, leg, k)
	if p.LegR:
		p.LegR.rotation.x = lerpf(p.LegR.rotation.x, -leg, k)
	if p.ArmL:
		p.ArmL.rotation = p.ArmL.rotation.lerp(arm_l, k)
	if p.ArmR:
		p.ArmR.rotation = p.ArmR.rotation.lerp(arm_r, k)
	if p.get("ElbowL"):
		p.ElbowL.rotation.x = lerpf(p.ElbowL.rotation.x, elbow_l, k)
	if p.get("ElbowR"):
		p.ElbowR.rotation.x = lerpf(p.ElbowR.rotation.x, elbow_r, k)
	if p.Body:
		p.Body.rotation.x = lerpf(p.Body.rotation.x, lean, k)
	var h: Node3D = v.holder
	if h and tool != "crate":
		# o suporte desfaz os giros em X do corpo, do braço e do cotovelo para o cabo ficar na inclinação pedida
		h.rotation.x = lerpf(h.rotation.x, 0.0 if follow else tilt - arm_r.x - elbow_r - lean, k)
	if tool == "hoe" and state == "work" and h:
		_reach_left(v, h, -HOE_GAP)


## Leva a mão esquerda até o cabo, a `gap` metros da direita (negativo = atrás dela, para o lado da ponta do
## cabo), ou o mais perto disso que o braço alcança: a mão escorrega pelo cabo em direção à direita até caber.
## Dobra o cotovelo até a mão ficar à distância certa do ombro e gira o ombro para apontá-la para lá. Usa a
## pose que o braço direito e o corpo têm agora, então acompanha o cabo quadro a quadro.
static func _reach_left(v: Dictionary, holder: Node3D, gap: float) -> void:
	var p: Dictionary = v.parts
	var arm: Node3D = p.get("ArmL")
	var elbow: Node3D = p.get("ElbowL")
	var m: Node3D = v.get("model")
	if arm == null or elbow == null or m == null or arm.get_parent() == null:
		return
	if not v.has("hand_l"):   # centro da mão no espaço do antebraço (pose de repouso)
		v["hand_l"] = KnightLook._point_in(m, elbow, "ArmL_Hand")
	var hand: Vector3 = v.hand_l
	# cabo no espaço do pai do braço (onde o ombro gira), medido a partir do ombro
	var to_arm := KnightLook._chain(arm.get_parent() as Node3D, m).affine_inverse() * KnightLook._chain(holder, m)
	var max_reach := (elbow.position.length() + hand.length()) * 0.97
	var target := to_arm * Vector3(0, 0, gap) - arm.position
	while absf(gap) > 0.12 and target.length() > max_reach:
		gap -= 0.02 * signf(gap)
		target = to_arm * Vector3(0, 0, gap) - arm.position
	var reach := elbow.position.length() + hand.length()
	var dist := clampf(target.length(), 0.12, reach * 0.995)
	v["hoe_gap"] = gap   # para a foto de conferência (tools/villager_shot.gd)
	# o cotovelo só dobra para a frente (giro negativo em X): quanto mais dobra, mais perto a mão fica do ombro
	var lo := -2.6
	var hi := 0.0
	for i in 14:
		var mid := (lo + hi) * 0.5
		if (elbow.position + Basis(Vector3.RIGHT, mid) * hand).length() > dist:
			hi = mid
		else:
			lo = mid
	var bend := (lo + hi) * 0.5
	elbow.rotation = Vector3(bend, 0, 0)
	var cur := (elbow.position + Basis(Vector3.RIGHT, bend) * hand).normalized()
	arm.basis = Basis(Quaternion(cur, target.normalized()))


## Chave da capina na fração `u` do ciclo, interpolada entre as linhas de HOE_KEYS.
static func _hoe_key(u: float) -> Array:
	for i in range(1, HOE_KEYS.size()):
		var a: Array = HOE_KEYS[i - 1]
		var b: Array = HOE_KEYS[i]
		if u <= b[0]:
			var f := smoothstep(a[0], b[0], u)
			return [u, lerpf(a[1], b[1], f), lerpf(a[2], b[2], f), lerpf(a[3], b[3], f), lerpf(a[4], b[4], f)]
	return HOE_KEYS[-1]


func _pose(state: String, t: float, delta: float) -> void:
	pose(_made, state, t, 1.0 - exp(-14.0 * delta))


func _door() -> Vector3:
	return home.global_transform * Vector3(randf_range(-0.6, 0.6), 0, home.size.y / 2.0 + 0.6)


func _flat_y() -> float:
	return home.global_position.y


func _idle(wait: float) -> void:
	_state = "idle"
	_t = wait
	_target_id = -1
	global_position = _door()


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


func _process(delta: float) -> void:
	if not is_instance_valid(home):
		return
	match _state:
		"idle":
			_t -= delta
			_pose("idle", 0.0, delta)
			if _t <= 0.0:
				if _pick_target():
					_from = global_position
					_state = "go"
					_t = 0.0
				else:
					_idle(3.0)
		"go", "back":
			var dist := maxf(0.01, Vector2(_to.x - _from.x, _to.z - _from.z).length())
			_t += delta * SPEED / dist
			var p := _from.lerp(_to, clampf(_t, 0.0, 1.0))
			_bob += delta * 7.0
			p.y = _flat_y()
			global_position = p
			if dist > 0.05:
				global_rotation.y = atan2(_to.x - _from.x, _to.z - _from.z)
			_pose("walk", _bob, delta)
			if _t >= 1.0:
				if _state == "go":
					_state = "work"
					_t = 0.0
				else:
					_idle(randf_range(1.0, 4.0))
		"work":
			_t += delta
			_pose("work", _t, delta)
			if _target_id >= 0 and home.colony and home.colony.nature:
				var n = home.colony.nature.node(_target_id)
				if n and n.alive:
					var d: Vector3 = n.global_position - global_position
					global_rotation.y = atan2(d.x, d.z)
			if _t >= WORK_TIME:
				_go(_door(), "back")
