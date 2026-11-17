class_name EnemyPose
extends RefCounted
## Pose dos monstros humanoides (goblin e esqueleto): pernas, tronco, cabeça e os dois braços com cotovelo.
##
## Antes os braços tinham um osso só e todo ataque era o golpe de clava por cima da cabeça: o arqueiro
## erguia o braço direito (o arco fica na mão esquerda e nem subia) e o cajado girava de ponta-cabeça junto
## com o braço. Agora, como no cavaleiro (KnightAnim):
##  - arco: o tronco vira de lado com o ombro esquerdo para o alvo, o braço do arco estica na linha da mira, a
##    mão da corda puxa da corda até o queixo (IK de dois ossos) e solta para trás; a flecha aparece encaixada
##    entre a corda e o arco enquanto ele puxa;
##  - cajado: levado em pé como um bordão; para o raio, ergue ao lado da cabeça e estica o braço apontando a
##    gema para o alvo; para a cura, levanta no alto e bate a ponta no chão; o golpe corpo a corpo (Lich) arma
##    para trás e desce com a gema na frente;
##  - clava, espada, machado: o golpe por cima de antes, agora com o cotovelo armando e esticando.
## Script puro (sem autoloads) para rodar na ferramenta de foto e nos testes unitários.
## Pivôs (espaço do pai): x < 0 em ArmX leva o braço para a frente; x < 0 em ElbowX dobra o antebraço.

const POLE_BOW := Vector3(0.7, -1.0, -0.1)      # braço do arco: cotovelo para baixo e para fora
const POLE_DRAW := Vector3(-1.0, 0.45, -0.8)    # mão da corda: cotovelo alto, para fora e para trás
const POLE_STAFF := Vector3(-0.9, -1.0, -0.3)   # braço do cajado: cotovelo para fora e para baixo
const ARROW_LEN := 0.62                         # flecha encaixada (unidades do modelo)


## Arma que muda a pose: "bow", "staff" ou "" (golpe comum), pelo equipamento da variante.
static func weapon_of(gear: Array) -> String:
	if "Bow" in gear:
		return "bow"
	if "Staff" in gear:
		return "staff"
	return ""


## Medidas do modelo lidas uma vez: ombro (S), cotovelo (E), mão (H) de cada lado, cabeça e a ponta do cajado.
## Vazio se o modelo não tem cotovelo (modelo antigo): aí a pose fica só com os ombros.
static func rig(parts: Dictionary) -> Dictionary:
	var r := {}
	for sd in ["L", "R"]:
		var arm: Node3D = parts.get("Arm" + sd)
		var el: Node3D = parts.get("Elbow" + sd)
		if arm == null or el == null:
			return {}
		r["S" + sd] = arm.position
		r["E" + sd] = el.position
		var hand = _hand(el)
		if hand != null:
			r["H" + sd] = hand
	if not r.has("HL") and not r.has("HR"):
		for sd in ["L", "R"]:
			r["H" + sd] = r["E" + sd].normalized() * r["E" + sd].length() * 1.05
	elif not r.has("HL"):
		r["HL"] = r["HR"] * Vector3(-1, 1, 1)
	elif not r.has("HR"):
		r["HR"] = r["HL"] * Vector3(-1, 1, 1)
	r["len"] = (r.EL.length() + r.HL.length())
	var head: Node3D = parts.get("Head")
	var hp: Vector3 = head.position if head else Vector3(0, r.SL.y + 0.15, 0)
	var sc: float = r.len / 0.5
	# ponto de ancoragem da corda: logo abaixo e na frente do queixo
	r["anchor"] = Vector3(0.0, maxf(hp.y - 0.02 * sc, r.SL.y + 0.06 * sc), 0.12 * sc)
	r["gem"] = _staff_top(parts.get("Staff"))
	r["muzzle"] = Vector3(0, r.SL.y, r.len)
	return r


## Posição da mão no espaço do cotovelo: as peças opcionais (Opt_*) nascem na mão.
static func _hand(el: Node3D):
	for c in el.get_children():
		if String(c.name).begins_with("Opt_"):
			return (c as Node3D).position
	return null


## Ponta do cajado (onde fica a gema), no espaço da peça Opt_Staff.
static func _staff_top(staff: Node3D) -> Vector3:
	if staff == null:
		return Vector3(0, 0.7, 0)
	var top := 0.0
	for mi: MeshInstance3D in staff.find_children("*", "MeshInstance3D", true, false):
		var b := mi.transform * mi.get_aabb()
		top = maxf(top, b.end.y)
	return Vector3(0, maxf(top - 0.06, 0.3), 0)


## IK de dois ossos: rotação do ombro e dobra do cotovelo para a mão chegar em `target` (espaço do Body),
## com o cotovelo virado para `pole`. Devolve [Quaternion do braço, rotação x do cotovelo].
static func solve(r: Dictionary, sd: String, target: Vector3, pole: Vector3) -> Array:
	var S: Vector3 = r["S" + sd]
	var E: Vector3 = r["E" + sd]
	var H: Vector3 = r["H" + sd]
	var a := E.length()
	var b := H.length()
	var d := target - S
	var dn := d.normalized() if d.length() > 0.001 else Vector3.DOWN
	var dist := clampf(d.length(), absf(a - b) + 0.01, a + b - 0.002)
	var want := acos(clampf((a * a + b * b - dist * dist) / (2.0 * a * b), -1.0, 1.0))
	var rest := (-E).angle_to(H)
	var phi := -maxf(0.0, rest - want)
	var h := E + Basis(Vector3.RIGHT, phi) * H
	var q := _arc(h.normalized(), dn)
	var e1 := q * E
	var pe := e1 - dn * e1.dot(dn)
	var pp := pole - dn * pole.dot(dn)
	if pe.length() > 0.0001 and pp.length() > 0.0001:
		q = Quaternion(dn, pe.signed_angle_to(pp, dn)) * q
	return [q.normalized(), phi]


static func _arc(from: Vector3, to: Vector3) -> Quaternion:
	if from.dot(to) < -0.9999:
		return Quaternion(Vector3.FORWARD, PI)
	return Quaternion(from, to)


## Base com o eixo y em `up` e o z o mais perto possível de `fwd` (espaço do Body).
static func _frame(up: Vector3, fwd: Vector3) -> Basis:
	var y := up.normalized()
	var z := fwd - y * fwd.dot(y)
	z = z.normalized() if z.length() > 0.001 else Vector3.BACK
	return Basis(y.cross(z), y, z)


## Pose de um quadro. st: state, kind (attack_kind), t, ht (hora do acerto), dur, amp (0..1 da passada),
## s (seno da passada), weapon, boss. k: suavização normal; kk: suavização do golpe (mais rápida no acerto).
static func humanoid(p: Dictionary, r: Dictionary, st: Dictionary, k: float, kk: float) -> void:
	var amp: float = st.amp
	var s: float = st.s
	var t: float = st.t
	var ht: float = st.ht
	var dur: float = st.dur
	var atk: bool = st.state == "attack"
	var kind: String = st.kind
	var weapon: String = st.weapon
	if p.LegL:
		p.LegL.rotation.x = lerpf(p.LegL.rotation.x, s * amp, k)
		p.LegR.rotation.x = lerpf(p.LegR.rotation.x, -s * amp, k)
	var body_x := 0.0
	var body_y := 0.0
	var head_y := 0.0
	# braços soltos (FK): balançam com a passada, cotovelo meio dobrado (mais andando)
	var fk_l := Vector3(-s * amp * 0.6, 0, 0.05)
	var fk_r := Vector3(s * amp * 0.5, 0, -0.05)
	var el_l := -0.18 - amp * 0.4
	var el_r := el_l
	var ik := {}          # lado -> [alvo, polo, peso]
	var wpn := {}         # lado -> [base desejada da arma no espaço do Body, peso]
	var arrow := []       # [de, até] da flecha encaixada (espaço do Body)
	var sc: float = r.len / 0.5 if not r.is_empty() else 1.0
	match weapon:
		"bow":
			fk_l = Vector3(-s * amp * 0.3 - 0.1, 0, 0.1)
			el_l = -0.35
			if atk and kind == "shoot" and not r.is_empty():
				var rise := smoothstep(0.0, 0.2, t) * (1.0 - smoothstep(dur - 0.2, dur, t))
				var draw := smoothstep(0.12, ht, t)
				body_y = -0.8 * rise
				head_y = 0.75 * rise
				var bb := Basis.from_euler(Vector3(body_x, body_y, 0))
				var aim := bb.inverse() * Vector3.BACK
				var up := bb.inverse() * Vector3.UP
				var A: Vector3 = r.anchor
				var G: Vector3 = A + aim * r.len * 0.92        # mão do arco, na linha da mira
				var string_rest := G - aim * 0.11 * sc
				var hand_r := string_rest.lerp(A, draw)
				if t >= ht:     # soltou: a mão da corda escapa para trás passando pela orelha
					var f := smoothstep(ht, ht + 0.1, t)
					hand_r = A.lerp(A - aim * 0.16 * sc + up * 0.04 * sc + Vector3(-0.05, 0, 0) * sc, f)
				ik["L"] = [G, POLE_BOW, rise]
				ik["R"] = [hand_r, POLE_DRAW, rise]
				var bow := _frame(up, aim) * Basis(Vector3.BACK, -0.12)
				wpn["L"] = [bow, rise]
				r["muzzle"] = G + aim * 0.05 * sc
				if rise > 0.5 and t < ht:
					arrow = [hand_r, hand_r + aim * ARROW_LEN * sc]
		"staff":
			fk_r = Vector3(-0.22 + s * amp * 0.15, 0, -0.14)
			el_r = -0.6
			wpn["R"] = [Basis(Vector3.RIGHT, 0.12), 1.0]     # bordão em pé, ponta um pouco à frente
			if atk and not r.is_empty():
				var SR: Vector3 = r.SR
				var out := 1.0 - smoothstep(dur - 0.25, dur, t)
				if kind == "cast" or kind == "slam":
					# cura (ou pancada do Lich): levanta o cajado no alto e bate a ponta no chão
					if t < ht:
						var f := smoothstep(0.0, ht * 0.7, t)
						body_x = -0.15 * f
						ik["R"] = [SR + Vector3(0.04, 0.5, 0.1) * sc, POLE_STAFF, f]
						wpn["R"] = [Basis(), 1.0]
						if kind == "slam":
							fk_l = Vector3(-2.6 * f, 0, 0)
					else:
						body_x = 0.25 * out
						ik["R"] = [SR + Vector3(0.04, -0.12, 0.32) * sc, POLE_STAFF, out]
						wpn["R"] = [Basis(Vector3.RIGHT, 0.08), 1.0]
						if kind == "slam":
							fk_l = Vector3(0.2, 0, 0)
				else:
					# raio (esqueleto mago) ou golpe com o cajado (Lich): arma ao lado da cabeça e estica para o alvo
					var melee := kind == "swing"
					if t < ht:
						var f := smoothstep(0.0, ht * 0.75, t)
						body_x = -0.12 * f
						body_y = 0.15 * f
						ik["R"] = [SR + (Vector3(-0.06, 0.12, -0.02) if not melee else Vector3(-0.04, 0.32, -0.12)) * sc,
							POLE_STAFF, f]
						wpn["R"] = [Basis(Vector3.RIGHT, -0.25 if not melee else -0.9), 1.0]
						fk_l = Vector3(-0.5 * f, 0, 0.15)
					else:
						body_x = 0.2 * out
						body_y = 0.35 * out
						var bb := Basis.from_euler(Vector3(body_x, body_y, 0))
						var aim := bb.inverse() * Vector3.BACK
						var up := bb.inverse() * Vector3.UP
						var reach: Vector3 = SR + aim * r.len * 0.9 + up * (0.1 if not melee else -0.08) * sc
						ik["R"] = [reach, POLE_STAFF, out]
						# raio: a vara inclina uns 45° com a gema para o alvo; golpe: a cabeça do cajado desce na frente
						var axis := (aim + up * (0.9 if not melee else 0.2)).normalized()
						wpn["R"] = [_frame(axis, -up), 1.0]
						fk_l = Vector3(-0.3 * out, 0, 0.15)
		_:
			if atk:
				if kind == "slam":
					if t < ht:
						fk_r = Vector3(-3.0, 0, 0)
						fk_l = Vector3(-3.0, 0, 0)
						el_r = -0.6
						el_l = -0.6
						body_x = -0.3
					else:
						fk_r = Vector3(0.3, 0, 0)
						fk_l = Vector3(0.3, 0, 0)
						el_r = -0.15
						el_l = -0.15
						body_x = 0.4
				elif t < ht:
					fk_r = Vector3(-2.7, 0, -0.3)
					el_r = -1.1         # cotovelo armado atrás da cabeça
					body_x = -0.2
				elif t < ht + 0.25:
					fk_r = Vector3(-0.45, 0, 0.15)
					el_r = -0.1         # estica no golpe: a arma termina na frente, para baixo
					body_x = 0.3
	if p.Body:
		p.Body.rotation.x = lerpf(p.Body.rotation.x, body_x, k)
		p.Body.rotation.y = lerp_angle(p.Body.rotation.y, body_y, k)
	if p.Head:
		p.Head.rotation.y = lerp_angle(p.Head.rotation.y, head_y, k)
	for sd in ["L", "R"]:
		var arm: Node3D = p.get("Arm" + sd)
		if arm == null:
			continue
		var el: Node3D = p.get("Elbow" + sd)
		var fk: Vector3 = fk_l if sd == "L" else fk_r
		var q := Quaternion(Basis.from_euler(fk))
		var bend: float = el_l if sd == "L" else el_r
		if ik.has(sd) and not r.is_empty():
			var sol := solve(r, sd, ik[sd][0], ik[sd][1])
			var w: float = ik[sd][2]
			q = q.slerp(sol[0], w)
			bend = lerpf(bend, sol[1], w)
		var kq := kk if sd == "R" else k
		arm.quaternion = arm.quaternion.slerp(q, kq)
		if el:
			el.rotation = Vector3(lerpf(el.rotation.x, bend, kq), 0, 0)
		var opt: Node3D = p.get("Bow" if sd == "L" else "Staff")
		if opt == null or el == null:
			continue
		var target := Quaternion.IDENTITY
		if wpn.has(sd):
			var chain := (arm.basis * el.basis).orthonormalized()
			var local := (chain.inverse() * (wpn[sd][0] as Basis)).orthonormalized()
			target = Quaternion.IDENTITY.slerp(local.get_rotation_quaternion(), wpn[sd][1])
		opt.quaternion = opt.quaternion.slerp(target, kq)
	var nock: Node3D = p.get("Nock")
	if nock:
		nock.visible = not arrow.is_empty()
		if nock.visible:
			var a: Vector3 = arrow[0]
			var b: Vector3 = arrow[1]
			nock.transform = Transform3D(_frame(b - a, Vector3.UP.cross(b - a)), (a + b) * 0.5)
