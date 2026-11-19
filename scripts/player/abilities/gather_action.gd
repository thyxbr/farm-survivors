class_name GatherAction
extends RefCounted
## Coleta com ferramenta: o jogador perto de um veio ou de uma árvore aperta F uma vez (player.start_gather), saca a
## melhor picareta/machado da mochila e bate sozinho, um golpe a cada `swing` segundos, até o nó ceder. Cada golpe
## soma força no nó (WorldResourceNode.strike) e a barra do HUD sobe; no último o item chega pela coleta do Econ.
##
## Roda como uma habilidade (`player.ability == ID`, ver SwordAbilities): sem ataque nem outras habilidades enquanto
## dura, tick() a cada passo de física (local e réplicas), pose() por cima da locomoção. Para sozinha quando o nó
## cede; andar, esquivar, levar dano ou F de novo interrompem (o progresso fica guardado no nó).
## A ferramenta aparece na mão pelo visual do jogador (player.gather_tool vira a "arma" do look, então as réplicas
## dos outros jogadores também a veem); o evento de rede só começa a pose nas réplicas.

const ID := "gather"
## Fração do ciclo em que a ferramenta bate (a chave de impacto de KnightMoves.MINE / CHOP).
const IMPACT := 0.5
## Depois do golpe que derruba o nó, o tempo (fração do ciclo) para terminar o movimento antes de guardar a ferramenta.
const FOLLOW := 0.4
## Alcance de F a partir da borda do nó (m).
const REACH := 1.6
## Andar interrompe depois deste tempo (s): o primeiro instante tolera a tecla ainda apertada.
const MOVE_GRACE := 0.15
## Antes do primeiro golpe o personagem anda sozinho até ficar a esta distância da borda do nó (m): é onde a
## picareta alcança a pedra e o machado o tronco (medido com tools/weapon_pose_shot.tscn -- coleta).
const STAND := 0.45
## Ponta do gume do machado no impacto, no espaço do modelo: x (para a esquerda do personagem) e z (para a frente),
## em metros (KnightMoves.CHOP_TOOL; medido com tools/weapon_pose_shot.tscn -- coleta, que imprime TIP). No golpe
## lateral o gume cai um pouco à esquerda da frente do corpo: o personagem mira esse tanto para a direita da árvore
## e para à distância em que o gume crava na casca e para nela, sem atravessar.
const CHOP_TIP := Vector2(0.125, 0.78)
const CHOP_REACH := 0.79          ## = CHOP_TIP.length()
const CHOP_BITE := 0.7            ## fração do raio do tronco até onde o gume entra
## Tolerância da parada (m): mais longe ou mais perto que isso, anda para a frente ou recua.
const STAND_TOL := 0.06
const APPROACH_SPEED := 3.5
const APPROACH_MAX := 2.0   ## desiste de chegar mais perto depois disso (preso em algo) e bate de onde está


## Começa a coletar o nó `node` com o plano de WorldResourceNode.gather_plan() (local).
static func start(player: Node, node: Node3D, plan: Dictionary) -> void:
	var axe := bool(node.is_tree())
	player.begin_ability(ID, {"node": node, "tool": plan.tool, "power": float(plan.power), "swing": float(plan.swing),
		"axe": axe, "approach": absf(_center_distance(player, node) - node.stand_distance()) > STAND_TOL})
	_face(player, node.global_position)
	player.gather_tool = str(plan.tool)
	player.refresh_look()
	if not player.ability_data.approach:
		_announce(player)


## Avisa as réplicas que os golpes começaram (b.x = segundos por golpe, b.y = 1 se machado).
static func _announce(player: Node) -> void:
	var d: Dictionary = player.ability_data
	Network.send_event(ID, d.node.global_position, Vector3(float(d.swing), 1.0 if d.axe else 0.0, 0.0))


## Réplica: começa a pose de coleta de outro jogador (só visual; o nó dele é pessoal).
static func play_remote(player: Node, _kind: String, a: Vector3, b: Vector3) -> void:
	player.begin_ability(ID, {"swing": maxf(b.x, GatherRules.SWING_MIN), "axe": b.y > 0.5, "at": a})


static func use(_player: Node, _id: String) -> bool:
	return false   # não sai de slot de habilidade: começa por F (player.start_gather)


static func tick(player: Node, delta: float, move_dir := Vector3.ZERO, _move_speed := 0.0) -> void:
	var d: Dictionary = player.ability_data
	var t0: float = player.ability_t
	player.ability_t += delta
	var t: float = player.ability_t
	var swing: float = d.get("swing", 1.0)
	if not player.remote:
		if d.get("approach", false):
			_approach(player, d, t, move_dir)
			return
		player.velocity.x = move_toward(player.velocity.x, 0.0, 40.0 * delta)
		player.velocity.z = move_toward(player.velocity.z, 0.0, 40.0 * delta)
		if d.has("done_t"):
			if t >= float(d.done_t) + swing * FOLLOW:
				player.end_ability()
			return
		var node = d.get("node")
		if node == null or not is_instance_valid(node) or not node.alive:
			player.end_ability()
			return
		if t > MOVE_GRACE and move_dir.length() > 0.2:
			player.end_ability()   # andou: guarda a ferramenta (o progresso fica no nó)
			return
		_face(player, node.global_position)
	# o golpe bate no meio de cada ciclo
	if floorf(t / swing + (1.0 - IMPACT)) > floorf(t0 / swing + (1.0 - IMPACT)):
		_impact(player, d, t)


## Anda até a distância de golpe (STAND); chegando, zera o relógio para o primeiro golpe começar do preparo.
static func _approach(player: Node, d: Dictionary, t: float, move_dir: Vector3) -> void:
	var node = d.get("node")
	if node == null or not is_instance_valid(node) or not node.alive or (t > MOVE_GRACE and move_dir.length() > 0.2):
		player.end_ability()
		return
	var to: Vector3 = node.global_position - player.global_position
	to.y = 0.0
	var off: float = to.length() - node.stand_distance()   # > 0: longe; < 0: perto demais (recua)
	if absf(off) <= STAND_TOL or t > APPROACH_MAX or to.length() < 0.05:
		d.approach = false
		player.ability_t = 0.0
		player.velocity.x = 0.0
		player.velocity.z = 0.0
		_announce(player)
		return
	var v := to.normalized() * APPROACH_SPEED * signf(off) * clampf(absf(off) / 0.25, 0.4, 1.0)
	player.velocity.x = v.x
	player.velocity.z = v.z
	_face(player, node.global_position)


static func _impact(player: Node, d: Dictionary, t: float) -> void:
	var tip: Vector3 = player.weapon_tip()
	if player.remote:
		Sfx.play_at("chop_wood" if d.get("axe", false) else "chop_stone", tip, 0.15, -8.0)
		FX.burst(tip, Color(0.45, 0.3, 0.15) if d.get("axe", false) else Color(0.62, 0.6, 0.56), 5, 2.5, 0.06, 0.3)
		return
	var node = d.node
	var done: bool = node.strike(player.global_position, float(d.power))
	player.add_shake(0.07)
	if not d.get("axe", false):
		FX.burst(tip, Color(1.0, 0.85, 0.5), 4, 3.5, 0.04, 0.25)   # faíscas da picareta na pedra
	if done:
		d["done_t"] = t


static func release(_player: Node) -> void:
	pass


static func can_dodge_cancel(_player: Node) -> bool:
	return true


static func dodge_cancel(player: Node) -> void:
	player.end_ability()


## Pose: o ciclo do golpe (picareta de cima para baixo, machado na horizontal) com as duas mãos no cabo.
static func pose(player: Node, p: Dictionary) -> void:
	var d: Dictionary = player.ability_data
	if d.get("approach", false):
		return   # andando até o nó com a ferramenta na mão
	var swing: float = d.get("swing", 1.0)
	pose_cycle(p, d.get("axe", false), fposmod(player.ability_t, swing) / swing, smoothstep(0.0, 0.15, player.ability_t))
	if d.has("done_t"):   # guardando a ferramenta: a mão esquerda solta no fim
		p["two_hand"] *= 1.0 - smoothstep(0.0, swing * FOLLOW, player.ability_t - float(d.done_t))


## Pose de um instante `u` (0..1) do ciclo do golpe por cima da locomoção `p` (também usada por
## tools/weapon_pose_shot.tscn). `hands` = peso das duas mãos no cabo.
static func pose_cycle(p: Dictionary, axe: bool, u: float, hands: float) -> void:
	# corpo: a base do ciclo é a pose pronta (ferramenta erguida), não a pose parada
	p.merge(KnightMoves.CHOP_READY if axe else KnightMoves.MINE_READY, true)
	p["hip_share"] = KnightMoves.CHOP_HIP_SHARE
	KnightAnim.play_track(p, KnightMoves.CHOP if axe else KnightMoves.MINE, u, 0.0)
	# braços: a ferramenta segue a trajetória e as duas mãos são resolvidas a partir do cabo
	var t := sample_tool(KnightMoves.CHOP_TOOL, KnightMoves.CHOP_TOOL_READY, u) if axe \
		else sample_tool(KnightMoves.MINE_TOOL, KnightMoves.MINE_TOOL_READY, u)
	t["w"] = hands
	p["tool"] = t
	p["tool_slide"] = t.slide
	p["two_hand"] = 0.0   # as duas mãos já vão pelo IK da trajetória


## A trajetória da ferramenta no instante `u`: as chaves de `track` ([u, {end, dir, edge, slide}, curva]) entre a pose
## `ready` nas duas pontas do ciclo, com as curvas de KnightAnim.ease_curve.
static func sample_tool(track: Array, ready: Dictionary, u: float) -> Dictionary:
	var u0 := 0.0
	var a := ready
	for key in track:
		var u1: float = key[0]
		if u <= u1:
			return _mix_tool(a, key[1], KnightAnim.ease_curve((u - u0) / maxf(u1 - u0, 0.0001), key[2]))
		u0 = u1
		a = key[1]
	return _mix_tool(a, ready, KnightAnim.ease_curve((u - u0) / maxf(1.0 - u0, 0.0001), "io"))


static func _mix_tool(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	return {"end": (a.end as Vector3).lerp(b.end, k), "dir": (a.dir as Vector3).normalized().slerp((b.dir as Vector3).normalized(), k),
		"edge": (a.edge as Vector3).normalized().slerp((b.edge as Vector3).normalized(), k),
		"slide": lerpf(a.slide, b.slide, k)}


static func _center_distance(player: Node, node: Node3D) -> float:
	var to: Vector3 = node.global_position - player.global_position
	to.y = 0.0
	return to.length()


## Vira o modelo para o nó; com o machado, um pouco para a direita dele, para a ponta do gume (CHOP_TIP) cair no tronco.
static func _face(player: Node, at: Vector3) -> void:
	var to: Vector3 = at - player.global_position
	to.y = 0.0
	if to.length() > 0.05:
		var aim := atan2(CHOP_TIP.x, CHOP_TIP.y) if player.ability_data.get("axe", false) else 0.0
		player.model.rotation.y = atan2(to.x, to.z) - aim


## Centro do tronco (raio `trunk_r`) no espaço do modelo quando o jogador está na posição de golpe.
static func chop_target(trunk_r: float) -> Vector3:
	return Vector3(CHOP_TIP.x, 0.0, CHOP_TIP.y).normalized() * (CHOP_REACH + trunk_r * CHOP_BITE)


## Nó de coleta mais perto ao alcance de F (borda a até REACH m), ou null.
static func nearest(player: Node) -> Node3D:
	var best: Node3D = null
	var best_d := REACH
	var w := player.get_tree().current_scene
	var cands: Array = w.harvest_near(player.global_position) if w and w.has_method("harvest_near") \
		else player.get_tree().get_nodes_in_group("harvest")
	for n in cands:
		if not is_instance_valid(n):
			continue
		if not n.alive:
			continue
		var dist: float = n.edge_distance(player.global_position)
		if dist <= best_d:
			best_d = dist
			best = n
	return best
