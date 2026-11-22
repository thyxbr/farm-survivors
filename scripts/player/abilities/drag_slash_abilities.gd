class_name DragSlashAbilities
extends RefCounted
## Corte do Abismo: habilidade da montante (espada de duas mãos) na tecla 2. ItemDB "sword_drag", "offhand":
## "two_handed": com a montante nas mãos ela troca o Golpe Sísmico.
##   1. Corrida e atrito: o herói solta a mão esquerda, desce a ponta da montante até o chão e dispara para a frente
##      arrastando a lâmina atrás, numa mão só. A ponta raspa o chão: chuva de fagulhas, brasas, pedrinhas e poeira para
##      trás, e um sulco em brasa no caminho. Para ao completar a distância, numa parede ou ao chegar num inimigo.
##   2. Corte e garras: finca o pé, enrola o tronco com a lâmina ainda raspando atrás e solta um corte violento de baixo
##      para cima, a ponta varrendo o chão pela direita e subindo à frente até o alto, com um rastro incandescente e o
##      arco de energia. No acerto, três garras espectrais (violeta e carmesim) irrompem do chão em fila à frente.
## Dano (só o dono): o corte fere quem está no arco à frente; cada garra fere quem está em cima dela quando irrompe.
## Visual e detecção de dano: DragAndSlash (cena própria na cena do mundo, se libera sozinha). Configuração em
## DragSlashConfig (assets/vfx/longsword_drag/drag_slash_config.tres, editável no Inspector).
## A esquiva cancela até o corte começar (sem dano).
## Rede: o dono manda "sword_drag" (a = posição, b = (yaw, semente)) e, quando para de correr, "sword_drag_slash"
## (a = posição): as réplicas tocam a mesma animação e o mesmo visual, sem dano. Cancelado: "sword_drag_cancel".

const ID := "sword_drag"
const SLASH_EVENT := "sword_drag_slash"
const CANCEL_EVENT := "sword_drag_cancel"
const SKILL := preload("res://scenes/vfx/longsword_drag/drag_and_slash.tscn")
const CONFIG := preload("res://assets/vfx/longsword_drag/drag_slash_config.tres")

## Pose da corrida (espaço do modelo: +Z = frente, +X = esquerda do herói, Y = altura a partir dos pés): o braço direito
## pende quase esticado para trás e para fora (a mão ao lado e atrás do quadril, não colada nele: o cabo longo da montante
## ficava enfiado na cintura) e a lâmina segue para trás até a ponta tocar o chão. Pegada de martelo: o polegar aponta
## para a lâmina (KnightAnim.grip_solve), o punho cede para a ponta descer.
const DRAG_HAND := Vector3(-0.37, 0.93, -0.17)
const DRAG_AZ := -2.95            ## para onde a lâmina vai, no chão (rad: 0 = frente, -PI/2 = direita, -PI = trás)
## Cotovelo na corrida: para trás e um pouco para fora, com peso moderado (o punho ainda alinha com o cabo).
const DRAG_POLE := Vector3(-0.45, -0.25, -1.0)
const DRAG_POLE_W := 1.2
## No corte o cotovelo segue POLE nas chaves com este peso (baixo: o punho fecha em volta do cabo).
const SLASH_POLE_W := 0.6
const GROUND_LIFT := 0.03         ## a ponta fica rente, não enterrada (m)
## Corte: [fração do tempo, mão direita, azimute, elevação desejada, cotovelo] (a elevação nunca deixa a ponta entrar no
## chão, DragSlashRules.min_elevation). As frações são do "relógio do corte" (key_time): 0 = fim da corrida, 1 = fim do
## preparo (plant), 2 = fim da subida (rise), 3 = fim do alto (hold). No alto o braço vai para cima e à frente e a
## lâmina fica quase perpendicular ao antebraço, para trás por cima da cabeça (pegada de martelo com o punho firme);
## esticar o braço reto para cima com a lâmina na mesma linha torcia o punho.
## Elevação acima de PI = passou do alto e inclina para trás (o giro continua no mesmo plano, sem virar pelo lado).
const SLASH_KEYS := [
	[1.0, Vector3(-0.4, 0.78, -0.3), -2.75, 0.0, Vector3(-0.6, -0.3, -0.8)],    # enrola: mão baixa e atrás, a ponta raspando
	[1.38, Vector3(-0.5, 0.74, 0.2), -1.15, 0.0, Vector3(-1.0, -0.45, -0.2)], # varre: a ponta corre pelo chão pela direita
	[-1.0, Vector3(-0.22, 1.25, 0.55), -0.25, 1.95, Vector3(-0.9, -0.6, 0.15)], # acerto (fração 1 + hit_at): à frente, subindo
	[2.0, Vector3(-0.14, 1.78, 0.42), 0.12, 3.68, Vector3(-1.0, -0.2, 0.35)],   # no alto: braço para cima e à frente
	[3.0, Vector3(-0.13, 1.74, 0.38), 0.12, 3.72, Vector3(-1.0, -0.25, 0.3)],   # segura, assentando
]
## Corpo no corte: [fração, {articulações}] por cima da locomoção (o peso entra no preparo e sai na volta).
const BODY_KEYS := [
	[1.0, {"twist": -0.8, "body_x": 0.45, "body_y": -0.11, "body_z": 0.06, "head_x": -0.28, "head_y": 0.6,
		"leg_l": -0.7, "knee_l": 1.1, "leg_r": 0.45, "knee_r": 0.9, "arm_l": Vector3(-0.95, 0.3, 0.4), "elbow_l": -1.0}],
	[1.38, {"twist": -0.3, "body_x": 0.35, "body_y": -0.09, "body_z": 0.03, "head_x": -0.2, "head_y": 0.35,
		"leg_l": -0.62, "knee_l": 0.95, "leg_r": 0.42, "knee_r": 0.7, "arm_l": Vector3(-0.4, 0.2, 0.5), "elbow_l": -0.8}],
	[-1.0, {"twist": 0.35, "body_x": 0.02, "body_y": 0.0, "body_z": -0.04, "head_x": -0.08, "head_y": -0.12,
		"leg_l": -0.45, "knee_l": 0.45, "leg_r": 0.35, "knee_r": 0.25, "arm_l": Vector3(0.45, 0.0, 0.55), "elbow_l": -0.45}],
	[2.0, {"twist": 0.55, "body_x": -0.24, "body_y": 0.04, "body_z": -0.06, "head_x": -0.32, "head_y": -0.25,
		"leg_l": -0.38, "knee_l": 0.18, "leg_r": 0.42, "knee_r": 0.1, "arm_l": Vector3(0.7, 0.0, 0.75), "elbow_l": -0.3}],
	[3.0, {"twist": 0.45, "body_x": -0.14, "body_y": 0.0, "body_z": -0.03, "head_x": -0.22, "head_y": -0.18,
		"leg_l": -0.36, "knee_l": 0.3, "leg_r": 0.38, "knee_r": 0.22, "arm_l": Vector3(0.45, 0.0, 0.6), "elbow_l": -0.45}],
]
const BODY_JOINTS := ["twist", "body_x", "body_y", "body_z", "head_x", "head_y", "leg_l", "knee_l", "leg_r", "knee_r",
	"arm_l", "elbow_l"]


static func use(player: Node, id: String) -> bool:
	if id != ID:
		return false
	var f: Vector3 = player.facing()
	var yaw := atan2(f.x, f.z)
	var seed_v := randi() % 65536
	_begin(player, yaw, seed_v)
	Network.send_event(ID, player.global_position, Vector3(yaw, float(seed_v), 0.0))
	Sfx.play("sword_swing", 0.1, -6.0)
	return true


static func _begin(player: Node, yaw: float, seed_v: int) -> void:
	var skill: DragAndSlash = null
	var root := FX._scene()
	if root != null:   # servidor dedicado: sem visual (o dano é do cliente dono)
		skill = SKILL.instantiate()
		skill.config = CONFIG
		skill.follow = player
		skill.yaw = yaw
		skill.seed_value = seed_v
		skill.deal_damage = not player.remote
		var lk: Dictionary = player.look
		skill.blade_base = lk.get("holder")
		skill.blade_tip = lk.get("tip")
		root.add_child(skill)
		skill.global_position = player.global_position
		if not player.remote:
			skill.slash_hit.connect(_on_slash_hit.bind(weakref(player)))
			skill.claw_hit.connect(_on_claw_hit)
	var d := {"skill": skill, "yaw": yaw, "dir": Vector3(sin(yaw), 0.0, cos(yaw)), "phase": DragSlashRules.WINDUP,
		"origin": player.global_position, "dash_t": -1.0, "slash_t": -1.0, "from": KnightAnim.capture_pose(player.parts),
		"blade_len": _blade_length(player)}
	player.begin_ability(ID, d)
	d["on_end"] = _on_end.bind(player, d)


## Comprimento da lâmina das mãos à ponta, no espaço do modelo (o tamanho muda com a montante e com o corpo).
static func _blade_length(player: Node) -> float:
	var lk: Dictionary = player.look
	var h = lk.get("holder")
	var tp = lk.get("tip")
	if h is Node3D and tp is Node3D and is_instance_valid(h) and is_instance_valid(tp) and (h as Node3D).is_inside_tree():
		var m: Node3D = player.model
		var l := (m.to_local((tp as Node3D).global_position) - m.to_local((h as Node3D).global_position)).length()
		if l > 0.3:
			return l
	return 1.3


static func tick(player: Node, delta: float, _move_dir := Vector3.ZERO, _move_speed := 0.0) -> void:
	player.ability_t += delta
	var t: float = player.ability_t
	var d: Dictionary = player.ability_data
	var cfg: DragSlashConfig = CONFIG
	var dir: Vector3 = d.dir
	var local: bool = not player.remote
	player.model.rotation.y = lerp_angle(player.model.rotation.y, float(d.yaw), 1.0 - exp(-18.0 * delta))
	match int(d.phase):
		DragSlashRules.WINDUP:
			if local:
				# já começa a arrancar enquanto a ponta desce
				var v := cfg.dash_speed * 0.3 * smoothstep(0.0, cfg.windup_time, t)
				player.velocity.x = dir.x * v
				player.velocity.z = dir.z * v
			if t >= cfg.windup_time:
				d.phase = DragSlashRules.DASH
				d.dash_t = t
				d.origin = player.global_position
				_skill_call(d, "start_drag")
		DragSlashRules.DASH:
			var run_t: float = t - float(d.dash_t)
			if local:
				var flat: Vector3 = player.global_position - (d.origin as Vector3)
				flat.y = 0.0
				var traveled := flat.length()
				var ahead := DragSlashRules.nearest_ahead(player.global_position, dir, _enemy_list(player),
					cfg.stop_distance + 0.5, cfg.lane_half_width)
				var wall: bool = run_t > 0.05 and player.is_on_wall() and player.get_wall_normal().dot(dir) < -0.5
				if DragSlashRules.dash_should_stop(traveled, cfg.dash_distance, ahead, cfg.stop_distance, wall) \
						or run_t >= cfg.dash_max_time:
					_start_slash(player, d)
					Network.send_event(SLASH_EVENT, player.global_position, Vector3(float(d.yaw), 0.0, 0.0))
				else:
					var v := DragSlashRules.dash_speed(run_t, cfg.dash_distance - traveled, cfg.dash_speed)
					player.velocity.x = dir.x * v
					player.velocity.z = dir.z * v
			elif run_t >= cfg.dash_max_time + 0.35:
				_start_slash(player, d)   # o evento do corte não chegou: segue pelo relógio
		DragSlashRules.SLASH:
			var s: float = t - float(d.slash_t)
			if local:
				# o embalo da corrida acaba no pé fincado (escorrega um pouco); no corte, um passinho à frente
				var target := 0.0
				if s > cfg.plant_time and s < cfg.plant_time + cfg.rise_time:
					target = 1.2
				var decel: float = maxf(float(d.get("slash_v", 8.0)) / maxf(cfg.plant_time, 0.05), 20.0)
				var hv := Vector2(player.velocity.x, player.velocity.z).length()
				hv = move_toward(hv, target, decel * delta)
				player.velocity.x = dir.x * hv
				player.velocity.z = dir.z * hv
			if s >= cfg.slash_total():
				player.end_ability()


## A corrida acabou: o corte começa (dono, réplica pelo evento ou pelo relógio).
static func _start_slash(player: Node, d: Dictionary) -> void:
	if int(d.phase) == DragSlashRules.SLASH:
		return
	d.phase = DragSlashRules.SLASH
	d.slash_t = player.ability_t
	d["slash_v"] = Vector2(player.velocity.x, player.velocity.z).length()
	_skill_call(d, "start_slash")
	Sfx.play_at("sword_swing_heavy", player.global_position, 0.08, -1.0)


static func _skill_call(d: Dictionary, method: String) -> void:
	var skill = d.get("skill")
	if skill != null and is_instance_valid(skill):
		skill.call(method)


static func _enemy_list(player: Node) -> Array:
	var out := []
	for e in player.get_tree().get_nodes_in_group("enemies"):
		if not e.dead:
			out.append({"pos": e.global_position, "radius": float(e.radius)})
	return out


static func release(_player: Node) -> void:
	pass


## Toca o visual uma vez, bem abaixo do mapa, para os shaders e pipelines ficarem prontos antes da primeira ativação
## da sessão (como FXEpic.prewarm_instances). Chamado (deferred) pelo jogador local.
static func prewarm_instances(at: Node3D) -> void:
	var root := FX._scene()
	if root == null or at == null or not is_instance_valid(at) or not at.is_inside_tree():
		return
	var s: DragAndSlash = SKILL.instantiate()
	s.config = CONFIG
	s.warm_only = true
	root.add_child(s)
	s.global_position = at.global_position + Vector3(0, -200, 0)


static func can_dodge_cancel(player: Node) -> bool:
	return player.ability == ID and int(player.ability_data.get("phase", 0)) != DragSlashRules.SLASH


static func dodge_cancel(player: Node) -> void:
	player.end_ability()


static func play_remote(player: Node, kind: String, a: Vector3, b: Vector3) -> void:
	match kind:
		ID:
			_begin(player, b.x, int(b.y))
			if FX._scene() != null:
				Sfx.play_at("sword_swing", a, 0.1, -8.0)
		SLASH_EVENT:
			if player.ability == ID:
				_start_slash(player, player.ability_data)
		CANCEL_EVENT:
			if player.ability == ID:
				player.end_ability()


## Fim por qualquer caminho: antes do corte as fagulhas se apagam sem dano; depois o visual segue sozinho.
static func _on_end(player: Node, d: Dictionary) -> void:
	var skill = d.get("skill")
	if is_instance_valid(skill) and skill.can_cancel():
		skill.cancel()
		if not player.remote:
			Network.send_event(CANCEL_EVENT, player.global_position, Vector3.ZERO)


## O corte acertou (dono): dano físico, um pequeno atordoamento e o empurrão para longe do herói.
static func _on_slash_hit(origin: Vector3, _fwd: Vector3, targets: Array, player_ref: WeakRef) -> void:
	var cfg: DragSlashConfig = CONFIG
	var dmg := Game.melee_damage() * cfg.slash_mult * Game.ability_dmg_mult(ID)
	var any := false
	for e in targets:
		if not is_instance_valid(e) or e.dead:
			continue
		e.take_damage(dmg, origin, false, 0.0, cfg.slash_stun, -cfg.slash_knockback)
		Game.on_damage_dealt(dmg, e.max_hp)
		FXEpic.sparks(e.global_position + Vector3.UP * 0.8, Vector3.UP + _fwd, Color(1.0, 0.7, 0.3), 14, 9.0, 0.3)
		any = true
	if any:
		Sfx.play("sword_hit_flesh", 0.1)
		var player = player_ref.get_ref()
		if player != null and is_instance_valid(player) and cfg.hitstop_time > 0.0:
			FXEpic.hit_stop(cfg.hitstop_time)


## Uma garra irrompeu embaixo de inimigos (dono): dano arcano e atordoamento.
static func _on_claw_hit(center: Vector3, targets: Array) -> void:
	var cfg: DragSlashConfig = CONFIG
	var dmg := Game.melee_damage() * cfg.claw_mult * Game.ability_dmg_mult(ID)
	for e in targets:
		if not is_instance_valid(e) or e.dead:
			continue
		e.take_damage(dmg, center, false, 0.0, cfg.claw_stun, 0.0, ElementRules.NEUTRAL)
		Game.on_damage_dealt(dmg, e.max_hp)
	if not targets.is_empty():
		Sfx.play("arcane_hit", 0.1, -2.0)


# ------------------------------------------------------------------ animação
## Relógio do corte em "chaves": 0 = fim da corrida, 1 = fim do preparo, 2 = fim da subida, 3 = fim do alto,
## 4 = de volta à guarda (cada trecho com o seu tempo da configuração).
static func key_time(s: float, cfg: DragSlashConfig) -> float:
	var spans := [cfg.plant_time, cfg.rise_time, cfg.hold_time, cfg.recover_time]
	var k := 0.0
	for sp: float in spans:
		var span := maxf(sp, 0.001)
		if s < span:
			return k + s / span
		s -= span
		k += 1.0
	return 4.0


## A pose por cima da locomoção (o player.gd já tirou a arma de carregar: "tool" é desta habilidade).
static func pose(player: Node, p: Dictionary) -> void:
	var d: Dictionary = player.ability_data
	var cfg: DragSlashConfig = CONFIG
	var t: float = player.ability_t
	var length := float(d.get("blade_len", 1.3))
	var snap: Array = p.snap
	for j in ["arm_r", "elbow_r"]:
		snap.append(j)   # o braço da arma sai do IK da trajetória, que já é suave
	p["two_hand"] = 0.0
	if int(d.phase) != DragSlashRules.SLASH:
		_drag_pose(p, d, cfg, t, length)
		return
	_slash_pose(player, p, d, cfg, t - float(d.slash_t), length)


## Correndo com a lâmina arrastada: a mão balança um pouco com a passada e a ponta fica sempre rente ao chão atrás e à
## direita. No preparo a arma sai da pose em que estava (`from`).
static func _drag_pose(p: Dictionary, d: Dictionary, cfg: DragSlashConfig, t: float, length: float) -> void:
	var w := smoothstep(0.0, cfg.windup_time, t)
	var sw := float((p.arm_r as Vector3).x) * 0.12
	var hand := DRAG_HAND + Vector3(0.0, float(p.get("body_y", 0.0)), 0.0)
	var sh := Vector3(-0.2, 1.42, 0.0)
	hand = sh + Basis(Vector3.RIGHT, sw) * (hand - sh)
	var tl := _blade_tool(hand, DRAG_AZ, 0.0, length, Vector3.ZERO)
	d["drag_hand"] = hand
	var from: Dictionary = d.get("from", {}).get("tool", {})
	if w < 1.0 and not from.is_empty():
		var a := {"end": from.end, "dir": from.dir, "edge": from.edge, "slide": 0.0, "left": float(from.get("left", 1.0))}
		var m := KnightAnim.great_mix(a, tl, w)
		for k in ["w", "grip", "pole_r", "pole_w"]:
			m[k] = tl[k]
		tl = m
	p["tool"] = tl
	# corpo: inclinado na corrida, o ombro direito para trás (puxando a lâmina) e a cabeça olhando para a frente
	p.body_x = float(p.body_x) + 0.2 * w
	p.twist = float(p.twist) - 0.32 * w
	p.head_y = float(p.head_y) + 0.26 * w
	p.head_x = float(p.head_x) - 0.1 * w
	# no preparo, um pequeno agachar para o arranque
	var dip := sin(PI * clampf(t / maxf(cfg.windup_time, 0.01), 0.0, 1.0)) * (1.0 - smoothstep(cfg.windup_time, cfg.windup_time * 1.5, t))
	p.body_y = float(p.body_y) - 0.05 * dip
	p.knee_l = float(p.knee_l) + 0.3 * dip
	p.knee_r = float(p.knee_r) + 0.3 * dip


## A arma (trajetória do tool, espaço do modelo) com a mão direita em `hand` e a lâmina em azimute/elevação, sem
## deixar a ponta entrar no chão. `edge` zero = o gume para baixo.
static func _blade_tool(hand: Vector3, az: float, el: float, length: float, edge: Vector3) -> Dictionary:
	el = maxf(el, DragSlashRules.min_elevation(hand.y, GROUND_LIFT, length))
	var dir := DragSlashRules.blade_dir(az, el)
	if edge.length() < 0.001:
		edge = Vector3.DOWN
	edge = edge - dir * edge.dot(dir)
	edge = edge.normalized() if edge.length() > 0.001 else dir.cross(Vector3.UP).normalized()
	return {"end": hand - dir * KnightMoves.GREAT_GRIP, "dir": dir, "edge": edge, "slide": 0.0, "left": 0.0,
		"w": 1.0, "grip": KnightMoves.GREAT_GRIP, "pole_r": DRAG_POLE, "pole_w": DRAG_POLE_W}


## Chaves da arma no corte, com a primeira = a pose da corrida quando ela acabou.
static func _slash_keys(d: Dictionary, cfg: DragSlashConfig) -> Array:
	var hand0: Vector3 = d.get("drag_hand", DRAG_HAND)
	var keys := [[0.0, hand0, DRAG_AZ, 0.0, DRAG_POLE]]
	for k in SLASH_KEYS:
		var kt: float = k[0] if k[0] >= 0.0 else 1.0 + cfg.hit_at
		keys.append([kt, k[1], k[2], k[3], k[4]])
	return keys


static func _sample_blade(keys: Array, kt: float, length: float) -> Array:
	var hand: Vector3 = DragSlashRules.spline(keys.map(func(k: Array) -> Array: return [k[0], k[1]]), kt)
	var az: float = DragSlashRules.spline(keys.map(func(k: Array) -> Array: return [k[0], k[2]]), kt)
	var el: float = DragSlashRules.spline(keys.map(func(k: Array) -> Array: return [k[0], k[3]]), kt)
	el = maxf(el, DragSlashRules.min_elevation(hand.y, GROUND_LIFT, length))
	var pole: Vector3 = DragSlashRules.spline(keys.map(func(k: Array) -> Array: return [k[0], k[4]]), kt)
	return [hand, DragSlashRules.blade_dir(az, el), pole]


static func _slash_pose(player: Node, p: Dictionary, d: Dictionary, cfg: DragSlashConfig, s: float, length: float) -> void:
	var kt := key_time(s, cfg)
	var keys := _slash_keys(d, cfg)
	var cur := _sample_blade(keys, minf(kt, 3.0), length)
	var hand: Vector3 = cur[0]
	var dir: Vector3 = cur[1]
	# o gume vai na frente do movimento (a direção em que a lâmina gira agora); parada no alto, o último
	var nxt := _sample_blade(keys, minf(kt + 0.04, 3.0), length)
	var motion: Vector3 = (nxt[1] as Vector3) - dir
	motion -= dir * motion.dot(dir)
	var edge: Vector3 = d.get("edge", Vector3.DOWN)
	if motion.length() > 0.002:
		edge = (edge - dir * edge.dot(dir)).normalized().slerp(motion.normalized(), 0.5 if kt < 3.0 else 0.1)
	# no começo do preparo o gume ainda está para baixo (como na corrida) e gira com o punho
	var e_down := Vector3.DOWN - dir * Vector3.DOWN.dot(dir)
	if e_down.length() > 0.001:
		edge = e_down.normalized().slerp(edge.normalized(), smoothstep(0.0, 0.8, kt))
	d["edge"] = edge
	var tl := _blade_tool(hand, 0.0, 0.0, length, edge)
	tl.dir = dir
	tl.end = hand - dir * KnightMoves.GREAT_GRIP
	tl.edge = (edge - dir * edge.dot(dir)).normalized()
	# o cotovelo muda de lado ao longo do corte (atrás na corrida, para fora no alto); o peso sai do da corrida para o
	# baixo do corte no preparo
	tl.pole_r = (cur[2] as Vector3).normalized()
	tl.pole_w = lerpf(DRAG_POLE_W, SLASH_POLE_W, smoothstep(0.0, 1.0, kt))
	# a volta à guarda: a arma vai para a de carregar pelo caminho de cima e o corpo devolve a pose à locomoção
	var back := smoothstep(3.0, 4.0, kt)
	if back > 0.0:
		var cp := p.duplicate(true)
		KnightAnim.great_carry(cp, float(player.get("_amp")), float(player.get("_run")))
		var carry: Dictionary = cp.tool
		var q := KnightAnim.blade_turn(tl.dir, carry.dir, back)
		var ndir: Vector3 = (q * (tl.dir as Vector3)).normalized()
		var mixed := KnightAnim.great_mix(tl, carry, back)
		mixed.dir = ndir
		# a mão direita vai em linha reta; o pomo (end) segue a lâmina girando pelo caminho de cima
		var g := KnightMoves.GREAT_GRIP
		var hand_b: Vector3 = (carry.end as Vector3) + (carry.dir as Vector3).normalized() * g
		mixed.end = hand.lerp(hand_b, back) - ndir * g
		mixed.edge = (q * (tl.edge as Vector3)).slerp(carry.edge as Vector3, back)
		mixed.w = 1.0
		mixed.grip = KnightMoves.GREAT_GRIP
		# o cotovelo e o peso dele passam aos poucos para os da guarda (trocar de uma vez estalava o braço)
		mixed.pole_r = (tl.pole_r as Vector3).lerp(carry.get("pole_r", KnightMoves.TOOL_POLE_R), back).normalized()
		mixed.pole_w = lerpf(float(tl.pole_w), float(carry.get("pole_w", KnightAnim.GRIP_POLE_WEIGHT)), back)
		mixed.left = lerpf(0.0, float(carry.get("left", 1.0)), smoothstep(0.6, 1.0, back))
		tl = mixed
		p["two_hand"] = smoothstep(0.6, 1.0, back) * float(carry.get("left", 1.0))
	p["tool"] = tl
	# corpo
	var w_in := smoothstep(0.0, 0.85, kt)
	var w := w_in * (1.0 - back)
	if w <= 0.0:
		return
	var bk := []
	for k in BODY_KEYS:
		bk.append([float(k[0]) if float(k[0]) >= 0.0 else 1.0 + cfg.hit_at, k[1]])
	var spd: Dictionary = p.speed
	for j in BODY_JOINTS:
		var pts := []
		pts.append([0.0, p.get(j, 0.0)])
		for k in bk:
			pts.append([k[0], (k[1] as Dictionary).get(j, p.get(j, 0.0))])
		var v = DragSlashRules.spline(pts, minf(kt, 3.0))
		if j == "arm_l":
			var qa := Basis.from_euler(p.arm_l as Vector3).get_rotation_quaternion()
			var qb := Basis.from_euler(v as Vector3).get_rotation_quaternion()
			p.arm_l = Basis(qa.slerp(qb, w)).get_euler()
		else:
			p[j] = lerpf(float(p.get(j, 0.0)), float(v), w)
		spd[j] = 2.4   # o corte é rápido: o corpo acompanha sem o atraso da suavização
