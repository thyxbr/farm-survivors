extends SceneTree
## Monta as AnimationLibrary "mixamo" dos NPCs com esqueleto (ferreiro, Bram, Mira) a partir dos FBX baixados
## do Mixamo em assets/animations/mixamo/. Os .import dos FBX usam o mesmo BoneMap (SkeletonProfileHumanoid,
## renomear ossos, rest fixer) dos modelos, então as tracks já saem como %GeneralSkeleton:<osso do perfil> e
## tocam direto no esqueleto de qualquer um deles. Rode depois do --import:
##   godot --headless --path . --script res://tools/build_npc_mixamo.gd [-- blacksmith elder merchant]
## Sem argumentos monta as três. Imprime, por clipe, a origem: FBX ou SUBSTITUTO (<origem>).
## FBX faltando: idle/talk vêm de blacksmith_mixamo.res; excited/call, do clipe provisório do próprio .glb.
## O ferreiro não tem substitutos (o Mixamo não tinha martelar: work_hammer segue o provisório do .glb).

const DIR := "res://assets/animations/mixamo/"
const SMITH_LIB := "res://assets/animations/blacksmith_mixamo.res"
const SK := "%GeneralSkeleton:"

## npc -> saída, modelo (.glb: substitutos provisórios, pose de repouso e braço preso), braço preso e clipes.
## Clipe: fbx (nome do arquivo em DIR), loop e sub ("smith" = mesmo clipe do ferreiro, "glb" = do modelo).
const NPCS := {
	"blacksmith": {
		"out": "res://assets/animations/blacksmith_mixamo.res",
		"model": "",
		"clips": {
			"idle": {"fbx": "idle", "loop": true, "sub": ""},
			"talk": {"fbx": "talk", "loop": true, "sub": ""},
			# toca uma vez: o ferreiro espera o animation_finished para voltar a martelar
			"work_pause": {"fbx": "work_pause", "loop": false, "sub": ""},
		},
	},
	"elder": {
		"out": "res://assets/animations/elder_mixamo.res",
		"model": "res://assets/models/elder.glb",
		# cajado na mão esquerda, de pé e fincado no chão: a clavícula fica na pose staff_hold e o resto do braço
		# vem de IK de dois ossos, assado quadro a quadro (ver _plant_staff). O ponto fica à frente e para fora,
		# onde a túnica não chega nem quando ele se curva (idle) ou dá passos (excited)
		"lock": {"pose": "staff_hold", "bones": ["LeftShoulder"]},
		"staff": {"node": "Staff", "pose": "staff_hold", "spot": Vector2(0.46, 0.15)},
		"clips": {
			"idle": {"fbx": "elder_idle", "loop": true, "sub": "smith"},
			"excited": {"fbx": "elder_excited", "loop": false, "sub": "glb"},
			"talk": {"fbx": "elder_talk", "loop": true, "sub": "smith"},
		},
	},
	"merchant": {
		"out": "res://assets/animations/merchant_mixamo.res",
		"model": "res://assets/models/merchant.glb",
		"clips": {
			"idle": {"fbx": "merchant_idle", "loop": true, "sub": "smith"},
			"call": {"fbx": "merchant_call", "loop": false, "sub": "glb"},
			"talk": {"fbx": "merchant_talk", "loop": true, "sub": "smith"},
		},
	},
}


func _initialize() -> void:
	var which := OS.get_cmdline_user_args()
	if which.is_empty():
		which = PackedStringArray(NPCS.keys())   # o ferreiro primeiro: os outros usam os clipes dele
	var ok := true
	for npc in which:
		if not NPCS.has(npc):
			push_error("NPC desconhecido: " + npc)
			ok = false
			continue
		print("== ", npc)
		var origins := {}
		var lib := build(npc, DIR, origins)
		if lib == null:
			ok = false
			continue
		for c: String in origins:
			var a := lib.get_animation(c)
			print("  %s: %s, %.2f s, %d tracks, loop %s" % [c, origins[c], a.length, a.get_track_count(),
					a.loop_mode == Animation.LOOP_LINEAR])
		var err := ResourceSaver.save(lib, NPCS[npc].out, ResourceSaver.FLAG_COMPRESS)
		print("SALVO ", NPCS[npc].out, " err=", err)
		ok = ok and err == OK
	quit(0 if ok else 1)


## Monta a biblioteca do npc lendo os FBX de fbx_dir; origins recebe clipe -> "FBX" ou "SUBSTITUTO (<origem>)".
## Devolve null se faltar um clipe sem substituto.
static func build(npc: String, fbx_dir: String, origins: Dictionary) -> AnimationLibrary:
	var cfg: Dictionary = NPCS[npc]
	var model: Node3D = null
	if cfg.model != "":
		model = (load(cfg.model) as PackedScene).instantiate()
	var lib := AnimationLibrary.new()
	for c: String in cfg.clips:
		var clip: Dictionary = cfg.clips[c]
		var path: String = fbx_dir + clip.fbx + ".fbx"
		var a: Animation = null
		if ResourceLoader.exists(path):
			a = _first_clip(load(path) as PackedScene)
			origins[c] = "FBX"
		elif clip.sub == "smith":
			var smith := load(SMITH_LIB) as AnimationLibrary
			if smith and smith.has_animation(c):
				a = smith.get_animation(c).duplicate(true)
				origins[c] = "SUBSTITUTO (%s/%s)" % [SMITH_LIB.get_file(), c]
		elif clip.sub == "glb" and model:
			var ap := _player(model)
			if ap and ap.has_animation(c):
				a = ap.get_animation(c).duplicate(true)
				origins[c] = "SUBSTITUTO (%s/%s)" % [str(cfg.model).get_file(), c]
		if a == null:
			push_error("%s: falta %s e não há substituto" % [npc, path])
			if model:
				model.free()
			return null
		a.resource_name = c
		a.loop_mode = Animation.LOOP_LINEAR if clip.loop else Animation.LOOP_NONE
		a.set_meta("origem", origins[c])
		lib.add_animation(c, a)
	if model:
		var sk := model.find_children("*", "Skeleton3D")[0] as Skeleton3D
		if cfg.has("lock"):
			_lock_bones(lib, sk, _player(model).get_animation(cfg.lock.pose), cfg.lock.bones)
		_fill_rest(lib, sk)
		if cfg.has("staff"):
			_plant_staff(lib, model, sk, cfg.staff)
		model.free()
	return lib


static func _player(m: Node) -> AnimationPlayer:
	var aps := m.find_children("*", "AnimationPlayer")
	return aps[0] if aps.size() > 0 else null


static func _first_clip(scene: PackedScene) -> Animation:
	if scene == null:
		return null
	var m := scene.instantiate()
	var ap := _player(m)
	var a: Animation = null
	if ap and ap.get_animation_list().size() > 0:
		a = ap.get_animation(ap.get_animation_list()[0]).duplicate(true)
	m.free()
	return a


## Em todos os clipes, os ossos dados ficam constantes na pose do clipe pose (ou no repouso, se ele não os anima).
static func _lock_bones(lib: AnimationLibrary, sk: Skeleton3D, pose: Animation, bones: Array) -> void:
	for b: String in bones:
		var path := NodePath(SK + b)
		var tp := pose.find_track(path, Animation.TYPE_ROTATION_3D)
		var rot: Quaternion = pose.rotation_track_interpolate(tp, 0.0) if tp >= 0 \
				else sk.get_bone_rest(sk.find_bone(b)).basis.get_rotation_quaternion()
		for c in lib.get_animation_list():
			var a := lib.get_animation(c)
			for i in range(a.get_track_count() - 1, -1, -1):
				if a.track_get_path(i) == path:
					a.remove_track(i)
			var t := a.add_track(Animation.TYPE_ROTATION_3D)
			a.track_set_path(t, path)
			a.rotation_track_insert_key(t, 0.0, rot)


## Um osso sem track no clipe atual fica na pose do clipe anterior (o AnimationPlayer não volta ao repouso):
## cada clipe ganha uma track constante no repouso do modelo para o que os outros clipes animam e ele não.
static func _fill_rest(lib: AnimationLibrary, sk: Skeleton3D) -> void:
	var tracks := {}   # NodePath -> [tipos]
	for c in lib.get_animation_list():
		var a := lib.get_animation(c)
		for i in a.get_track_count():
			var key := a.track_get_path(i)
			if not tracks.has(key):
				tracks[key] = []
			if not a.track_get_type(i) in tracks[key]:
				tracks[key].append(a.track_get_type(i))
	for c in lib.get_animation_list():
		var a := lib.get_animation(c)
		for path: NodePath in tracks:
			var bone := sk.find_bone(path.get_concatenated_subnames())
			if bone < 0:
				continue
			var rest := sk.get_bone_rest(bone)
			for type: int in tracks[path]:
				if a.find_track(path, type) >= 0:
					continue
				var t := a.add_track(type)
				a.track_set_path(t, path)
				match type:
					Animation.TYPE_POSITION_3D:   # posições do quadril vêm normalizadas pelo motion_scale
						a.position_track_insert_key(t, 0.0, rest.origin / sk.motion_scale)
					Animation.TYPE_ROTATION_3D:
						a.rotation_track_insert_key(t, 0.0, rest.basis.get_rotation_quaternion())
					Animation.TYPE_SCALE_3D:
						a.scale_track_insert_key(t, 0.0, rest.basis.get_scale())


const ARM_SLACK := 0.005             # folga do braço esticado (m): o cotovelo nunca trava reto
const MAX_SPIN := deg_to_rad(60.0)   # giro máximo do cotovelo em torno da linha ombro-mão


## Cajado de pé e fincado: em cada clipe, quadro a quadro (30 fps), o braço esquerdo é resolvido para que a mão
## segure o cajado (preso ao osso como o jogo prende, ver SkinnedNPC._attach) sempre na mesma pega, com o
## cajado vertical e o pé no chão em cfg.spot (x, z do modelo). LeftUpperArm/LeftLowerArm vêm de IK de dois
## ossos: o cotovelo é dobradiça (só gira no eixo X local do antebraço, como nos clipes do Mixamo) e aponta
## para fora e para trás, girando em torno da linha ombro-mão o quanto for preciso (até MAX_SPIN) para a mão não
## torcer em torno do antebraço; LeftHand fica com a orientação que mantém o cajado de pé. A clavícula (LeftShoulder)
## fica na pose staff_hold; só se o ombro passar do alcance ela desce o necessário (impresso; com a pega de cajado
## de caminhada do elder.glb e o ponto escolhido isso não acontece). Se nem assim alcançar, o braço estica na
## direção do alvo e a falta é impressa.
static func _plant_staff(lib: AnimationLibrary, model: Node3D, sk: Skeleton3D, cfg: Dictionary) -> void:
	var staff := model.find_child(cfg.node, true, false) as MeshInstance3D
	var ap := _player(model)
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(model)
	var s := _xform_to(sk, model)
	var cl := sk.find_bone("LeftShoulder")
	var ua := sk.find_bone("LeftUpperArm")
	var la := sk.find_bone("LeftLowerArm")
	var hd := sk.find_bone("LeftHand")
	var u := sk.get_bone_rest(la).origin.length()
	var l := sk.get_bone_rest(hd).origin.length()
	var reach := u + l
	var la_rest := sk.get_bone_rest(la).basis.get_rotation_quaternion()
	var hd_rest := sk.get_bone_rest(hd).basis.get_rotation_quaternion()
	# alvo da mão (espaço do esqueleto): a pega de staff_hold, com o cajado endireitado e levado ao ponto
	ap.play(cfg.pose)
	ap.seek(0.0, true)
	var hand_hold := s * _global(sk, hd)
	var st_hold := hand_hold * (s * sk.get_bone_global_rest(hd)).affine_inverse() * _xform_to(staff, model)
	var st_new := _upright(st_hold, staff.get_aabb(), cfg.spot)
	var target := s.affine_inverse() * st_new * st_hold.affine_inverse() * hand_hold
	var tgt := target.origin
	var pole := (s.basis.inverse() * Vector3(0.35, 0.0, -1.0)).normalized()   # cotovelo para fora (+x) e para trás (-z)
	ap.add_animation_library("bake", lib)
	for c in lib.get_animation_list():
		var a := lib.get_animation(c)
		var keys := []   # [t, rot LeftShoulder, LeftUpperArm, LeftLowerArm, LeftHand]
		var short := 0.0
		var short_t := 0.0
		var drop := 0.0   # maior descida da clavícula (graus)
		var spin_max := 0.0   # maior giro do cotovelo a partir de "para fora e para trás" (graus)
		var twist_max := 0.0
		var n := ceili(a.length * 30.0 - 0.001)
		ap.play("bake/" + c)
		for k in n + 1:
			var t := minf(k / 30.0, a.length)
			ap.seek(t, true)
			var chest := _global(sk, sk.get_bone_parent(cl))
			var clav := chest * sk.get_bone_pose(cl)
			var sh := clav * sk.get_bone_rest(ua).origin
			if sh.distance_to(tgt) > reach - ARM_SLACK:   # clavícula desce para o ombro alcançar
				var va := sh - clav.origin
				var vb := tgt - clav.origin
				var r := va.length()
				var cosv := (vb.length_squared() + r * r - pow(reach - ARM_SLACK, 2)) / (2.0 * vb.length() * r)
				var turn := va.angle_to(vb) - (acos(cosv) if absf(cosv) <= 1.0 else 0.0)
				if turn > 0.0:
					clav.basis = Basis(va.cross(vb).normalized(), turn) * clav.basis
					sh = clav * sk.get_bone_rest(ua).origin
					drop = maxf(drop, rad_to_deg(turn))
			var to := tgt - sh
			var dist := to.length()
			if dist - reach > short:
				short = dist - reach
				short_t = t
			# giro do cotovelo em torno da linha ombro-mão: o que zera a torção da mão em torno do antebraço
			var dir := to / dist
			var p0 := (pole - dir * pole.dot(dir)).normalized()
			var spin := 0.0
			var arm := _arm(sh, tgt, target.basis, p0, u, l, la_rest, hd_rest)
			for it in 3:   # secante: a torção varia quase linear com o giro
				var probe := _arm(sh, tgt, target.basis, p0.rotated(dir, spin + 0.05), u, l, la_rest, hd_rest)
				var slope: float = (probe[3] - arm[3]) / 0.05
				if absf(slope) < 0.001:
					break
				spin = clampf(spin - arm[3] / slope, -MAX_SPIN, MAX_SPIN)
				arm = _arm(sh, tgt, target.basis, p0.rotated(dir, spin), u, l, la_rest, hd_rest)
			spin_max = maxf(spin_max, absf(rad_to_deg(spin)))
			twist_max = maxf(twist_max, absf(rad_to_deg(arm[3])))
			var q_cl := (chest.basis.orthonormalized().inverse() * clav.basis.orthonormalized()).get_rotation_quaternion()
			var q_ua := (clav.basis.orthonormalized().inverse() * (arm[0] as Basis)).get_rotation_quaternion()
			var q_la: Quaternion = arm[1]
			var q_hd: Quaternion = arm[2]
			keys.append([t, q_cl, q_ua, q_la, q_hd])
		var bones := [cl, ua, la, hd]
		for b: int in bones:
			var path := NodePath(SK + sk.get_bone_name(b))
			for i in range(a.get_track_count() - 1, -1, -1):
				if a.track_get_path(i) == path:
					a.remove_track(i)
		for j in bones.size():
			var t := a.add_track(Animation.TYPE_ROTATION_3D)
			a.track_set_path(t, NodePath(SK + sk.get_bone_name(bones[j])))
			for kv in keys:
				a.rotation_track_insert_key(t, kv[0], kv[j + 1])
		print("  %s: cajado fincado em %s, clavícula desce até %.0f°, cotovelo gira até %.0f°, torção da mão até %.1f°%s" % [
				c, cfg.spot, drop, spin_max, twist_max,
				", FORA DO ALCANCE: falta até %.3f m (t=%.2f s)" % [short, short_t] if short > 0.0 else ""])
	ap.stop()
	ap.remove_animation_library("bake")
	tree.root.remove_child(model)


## IK de dois ossos do ombro sh até a mão em tgt (orientação hand), com o cotovelo para o lado de pole (perpendicular
## à linha ombro-mão). Devolve [base global de LeftUpperArm, rotação local de LeftLowerArm, rotação local de
## LeftHand, torção da mão em torno do antebraço (rad)].
static func _arm(sh: Vector3, tgt: Vector3, hand: Basis, pole: Vector3, u: float, l: float, la_rest: Quaternion,
		hd_rest: Quaternion) -> Array:
	var to := tgt - sh
	var dist := to.length()
	var dir := to / dist
	var d := clampf(dist, absf(u - l) + 0.001, u + l - 0.0005)
	var along := (u * u - l * l + d * d) / (2.0 * d)
	var elbow := sh + dir * along + pole * sqrt(maxf(u * u - along * along, 0.0))
	var yu := (elbow - sh).normalized()
	var zu := yu.cross(-pole).normalized()   # eixo da dobradiça: girar yu em torno dele leva ao antebraço
	var up_g := Basis(yu.cross(zu), yu, zu)
	var fore := (tgt - elbow).normalized() if dist <= u + l else dir
	var q_la := la_rest * Quaternion(Vector3.RIGHT, yu.signed_angle_to(fore, zu))
	var q_hd := ((up_g * Basis(q_la)).inverse() * hand.orthonormalized()).get_rotation_quaternion()
	var dh := hd_rest.inverse() * q_hd
	return [up_g, q_la, q_hd, wrapf(2.0 * atan2(dh.y, dh.w), -PI, PI)]


## Pose global (espaço do esqueleto) do osso b a partir das poses locais atuais (o cache global do Skeleton3D
## só se atualiza no próximo quadro).
static func _global(sk: Skeleton3D, b: int) -> Transform3D:
	var x := Transform3D.IDENTITY
	while b >= 0:
		x = sk.get_bone_pose(b) * x
		b = sk.get_bone_parent(b)
	return x


## O cajado st (transformação no modelo, malha com caixa box) endireitado na vertical e com o pé no chão em spot.
static func _upright(st: Transform3D, box: AABB, spot: Vector2) -> Transform3D:
	var ax := staff_axis(st, box)
	var r := Transform3D(Basis(Quaternion(ax, Vector3.UP)), Vector3.ZERO) * st
	var foot := staff_foot(r, box)
	return r.translated(Vector3(spot.x - foot.x, -foot.y, spot.y - foot.z))


## Eixo comprido do cajado (malha com caixa box, transformação st), apontando para cima.
static func staff_axis(st: Transform3D, box: AABB) -> Vector3:
	var i := box.get_longest_axis_index()
	var v := (st.basis * (Vector3.RIGHT if i == 0 else (Vector3.UP if i == 1 else Vector3.BACK))).normalized()
	return v if v.y >= 0.0 else -v


## Pé do cajado: centro da ponta de baixo, na altura do canto mais baixo da caixa.
static func staff_foot(st: Transform3D, box: AABB) -> Vector3:
	var i := box.get_longest_axis_index()
	var c := box.get_center()
	var h := Vector3.ZERO
	h[i] = box.size[i] * 0.5
	var p := st * (c - h)
	var q := st * (c + h)
	var low := INF
	for k in 8:
		low = minf(low, (st * box.get_endpoint(k)).y)
	var f := p if p.y < q.y else q
	return Vector3(f.x, low, f.z)


static func _xform_to(n: Node3D, top: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	while n != top and n != null:
		xf = n.transform * xf
		n = n.get_parent() as Node3D
	return xf
