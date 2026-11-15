# Rig compartilhado dos personagens com esqueleto (ferreiro, Bram, Mira).
# Executado dentro de characters.py (usa bpy, coll, scn, math, Vector, Matrix).
# Ossos com nomes do Mixamo (mixamorig:*) em pose T, para o retarget pelo perfil humanoide do Godot;
# pesos por região (weigh), poses em direções de mundo (pose_fk), clipes em faixas NLA (bake_clip) e IK de
# dois ossos (_ik).
from mathutils import Quaternion

MIXAMO = "mixamorig:"
# (osso, pai) na ordem da hierarquia (pai antes do filho)
BS_BONES = [("Hips", None), ("Spine", "Hips"), ("Spine1", "Spine"), ("Spine2", "Spine1"), ("Neck", "Spine2"),
            ("Head", "Neck"), ("HeadTop_End", "Head")]
for _sd in ("Left", "Right"):
    BS_BONES += [(_sd + "Shoulder", "Spine2"), (_sd + "Arm", _sd + "Shoulder"), (_sd + "ForeArm", _sd + "Arm"),
                 (_sd + "Hand", _sd + "ForeArm")]
for _sd in ("Left", "Right"):
    BS_BONES += [(_sd + "UpLeg", "Hips"), (_sd + "Leg", _sd + "UpLeg"), (_sd + "Foot", _sd + "Leg"),
                 (_sd + "ToeBase", _sd + "Foot"), (_sd + "Toe_End", _sd + "ToeBase")]


def weigh(objs, axis, stops):
    """Pesos ao longo de axis (coords de mundo): stops = [(t, osso), ...] em t crescente. Antes do primeiro
    e depois do último stop o peso é 100% daquele osso; entre dois stops passa linearmente de um ao outro."""
    ax = Vector(axis).normalized()
    for o in objs:
        for v in o.data.vertices:
            t = v.co.dot(ax)
            ws = [(stops[-1][1], 1.0)]
            if t <= stops[0][0]:
                ws = [(stops[0][1], 1.0)]
            else:
                for (t0, b0), (t1, b1) in zip(stops, stops[1:]):
                    if t <= t1:
                        u = (t - t0) / max(t1 - t0, 1e-6)
                        ws = [(b0, 1.0)] if b0 == b1 else [(b0, 1.0 - u), (b1, u)]
                        break
            for b, w in ws:
                if w > 1e-4:
                    g = o.vertex_groups.get(MIXAMO + b) or o.vertex_groups.new(name=MIXAMO + b)
                    g.add([v.index], w, 'REPLACE')


def _qx(deg):
    return Quaternion((1, 0, 0), math.radians(deg))


def _qz(deg):
    return Quaternion((0, 0, 1), math.radians(deg))


def pose_fk(arm, targets):
    """Põe o esqueleto numa pose dada em direções de mundo. targets[osso] = Vector (para onde o osso aponta),
    Quaternion (rotação extra em eixos de mundo sobre a do pai) ou Matrix (orientação absoluta em mundo,
    relativa à pose T). Ossos fora de targets seguem o pai. targets["HipsLoc"] desloca o quadril (mundo)."""
    hb = arm.data.bones[MIXAMO + "Hips"]
    arm.pose.bones[MIXAMO + "Hips"].location = hb.matrix_local.to_3x3().inverted() @ Vector(targets.get("HipsLoc", (0, 0, 0)))
    acc = {}
    for n, parent in BS_BONES:
        b, pb = arm.data.bones[MIXAMO + n], arm.pose.bones[MIXAMO + n]
        wp = acc.get(parent, Quaternion())
        t = targets.get(n)
        if t is None:
            w = wp
        elif isinstance(t, Matrix):   # orientação absoluta em mundo, relativa à pose T
            w = t.to_quaternion()
        elif isinstance(t, Quaternion):
            w = t @ wp
        else:
            cur = wp @ (b.matrix_local.to_3x3() @ Vector((0, 1, 0)))
            w = cur.rotation_difference(Vector(t).normalized()) @ wp
        acc[n] = w
        rq = b.matrix_local.to_quaternion()
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = rq.inverted() @ (wp.inverted() @ w) @ rq


def bake_clip(arm, name, keys):
    """keys = [(frame, targets)]: cada chave grava a rotação de todos os ossos. Vira uma faixa NLA com o nome do clipe."""
    ad = arm.animation_data or arm.animation_data_create()
    act = bpy.data.actions.new(name)
    ad.action = act
    moves_hips = any("HipsLoc" in t for _, t in keys)
    prev = {}
    for f, targets in keys:
        pose_fk(arm, targets)
        for n, _ in BS_BONES:
            pb = arm.pose.bones[MIXAMO + n]
            # q e -q são a mesma rotação, mas a curva interpola os componentes: sem manter o hemisfério da
            # chave anterior, o osso dá uma volta errada entre as chaves
            if n in prev and pb.rotation_quaternion.dot(prev[n]) < 0:
                pb.rotation_quaternion = -pb.rotation_quaternion
            prev[n] = pb.rotation_quaternion.copy()
            pb.keyframe_insert("rotation_quaternion", frame=f, group=MIXAMO + n)
        if moves_hips:
            arm.pose.bones[MIXAMO + "Hips"].keyframe_insert("location", frame=f, group=MIXAMO + "Hips")
    track = ad.nla_tracks.new()
    track.name = name
    track.strips.new(name, int(keys[0][0]), act)
    ad.action = None
    for pb in arm.pose.bones:
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()


def _ik(root, end, l1, l2, pole, warn=True):
    """Dois ossos de root até end (l1, l2) com a junta do meio para o lado de pole: direções dos dois ossos."""
    d = end - root
    if warn and d.length > (l1 + l2) * 0.995:
        print("IK: alvo fora de alcance (%.3f > %.3f)" % (d.length, l1 + l2))
    L = min(max(d.length, abs(l1 - l2) + 0.01), (l1 + l2) * 0.995)
    dn = d.normalized()
    a = math.acos(max(-1.0, min(1.0, (l1 * l1 + L * L - l2 * l2) / (2 * l1 * L))))
    p = Vector(pole)
    p = (p - dn * dn.dot(p)).normalized()
    mid = root + dn * (l1 * math.cos(a)) + p * (l1 * math.sin(a))
    return mid - root, root + dn * L - mid


def mixamo_rig(body_objs, P, joints, hip_z, top, spine=(1.06, 1.18, 1.3, 1.45, 1.57)):
    """Esqueleto BS_BONES em pose T (frente = -Y, esquerda = +X). joints[lado] = (ombro, cotovelo, punho) da
    pose T; P traz "hip", "knee" e "ankle" (lado esquerdo); hip_z = altura do quadril; top = topo da cabeça;
    spine = alturas do início de Spine, Spine1, Spine2, Neck e Head. Parenteia body_objs ao esqueleto com o
    modificador Armature (os grupos de vértices já vêm de weigh) e devolve o objeto Armature."""
    ad = bpy.data.armatures.new("Armature")
    arm = bpy.data.objects.new("Armature", ad)
    coll.objects.link(arm)
    hip, knee, ankle = P["hip"], P["knee"], P["ankle"]
    z_sp, z_s1, z_s2, z_nk, z_hd = spine
    J = {"Hips": ((0, 0, hip_z), (0, 0, z_sp)), "Spine": ((0, 0, z_sp), (0, 0, z_s1)),
         "Spine1": ((0, 0, z_s1), (0, 0, z_s2)), "Spine2": ((0, 0, z_s2), (0, 0, z_nk)),
         "Neck": ((0, 0, z_nk), (0, 0.01, z_hd)), "Head": ((0, 0.01, z_hd), (0, 0.01, top)),
         "HeadTop_End": ((0, 0.01, top), (0, 0.01, top + 0.08))}
    for sd, s in (("Left", 1), ("Right", -1)):
        sh, el_t, wr_t = joints[sd]
        x = hip.x * s
        J[sd + "Shoulder"] = ((s * 0.06, 0, sh.z), sh)
        J[sd + "Arm"] = (sh, el_t)
        J[sd + "ForeArm"] = (el_t, wr_t)
        J[sd + "Hand"] = (wr_t, wr_t + Vector((s * 0.1, 0, 0)))
        J[sd + "UpLeg"] = ((x, 0, hip_z - 0.02), (x, knee.y, knee.z))
        J[sd + "Leg"] = ((x, knee.y, knee.z), (x, 0, ankle.z))
        J[sd + "Foot"] = ((x, 0, ankle.z), (x, -0.1, 0.025))
        J[sd + "ToeBase"] = ((x, -0.1, 0.025), (x, -0.17, 0.025))
        J[sd + "Toe_End"] = ((x, -0.17, 0.025), (x, -0.23, 0.025))
    scn.view_layers[0].objects.active = arm
    with bpy.context.temp_override(active_object=arm, object=arm, selected_objects=[arm]):
        bpy.ops.object.mode_set(mode='EDIT')
        for n, parent in BS_BONES:
            eb = ad.edit_bones.new(MIXAMO + n)
            eb.head, eb.tail = Vector(J[n][0]), Vector(J[n][1])
            if parent:
                eb.parent = ad.edit_bones[MIXAMO + parent]
                eb.use_connect = (eb.head - eb.parent.tail).length < 1e-4
        bpy.ops.object.mode_set(mode='OBJECT')
    for o in body_objs:
        o.parent = arm
        o.modifiers.new("Armature", 'ARMATURE').object = arm
    return arm


def weigh_by(objs, field):
    """Pesos por uma função de posição (coords de mundo): field(co) -> [(osso, peso), ...]."""
    for o in objs:
        for v in o.data.vertices:
            for b, w in field(v.co):
                if w > 1e-4:
                    g = o.vertex_groups.get(MIXAMO + b) or o.vertex_groups.new(name=MIXAMO + b)
                    g.add([v.index], w, 'REPLACE')


def robe_field(hip_z, low_z, torso, legs=0.7, spread=0.12):
    """Campo de pesos de túnica comprida: acima de hip_z o gradiente do tronco (torso = [(z, osso), ...] como
    em weigh); abaixo, o quadril cede aos poucos para as coxas até low_z (no máximo legs do peso), repartido
    entre a esquerda e a direita por uma rampa suave de largura 2 * spread em X. Todas as peças da túnica usam
    o mesmo campo, então peças coladas se movem juntas e a malha não rasga entre as pernas."""
    def field(co):
        z = co.z
        if z >= hip_z:
            if z <= torso[0][0]:
                return [(torso[0][1], 1.0)]
            for (z0, b0), (z1, b1) in zip(torso, torso[1:]):
                if z <= z1:
                    u = (z - z0) / max(z1 - z0, 1e-6)
                    return [(b0, 1.0)] if b0 == b1 else [(b0, 1.0 - u), (b1, u)]
            return [(torso[-1][1], 1.0)]
        u = min(1.0, (hip_z - z) / max(hip_z - low_z, 1e-6))
        u = legs * u * u * (3 - 2 * u)
        x = max(-1.0, min(1.0, co.x / spread))
        left = 0.5 + 0.25 * x * (3 - x * x)        # smoothstep de -spread (0) a +spread (1)
        return [(torso[0][1], 1.0 - u), ("LeftUpLeg", u * left), ("RightUpLeg", u * (1.0 - left))]
    return field


def hinge_frame(d, n, side):
    """Orientação absoluta (relativa à pose T) de um osso de braço apontando para d com o eixo de dobra n.
    Na pose T o braço aponta para side * X (side = 1 esquerdo, -1 direito), palma para baixo, e o cotovelo dobra
    para a frente (-Y) girando em volta de -side * Z. Braço, antebraço e mão com o mesmo n formam uma cadeia de
    dobradiças: o antebraço não torce em volta do próprio eixo."""
    d = Vector(d).normalized()
    n = Vector(n).normalized()
    return Matrix((side * d, d.cross(n), -side * n)).transposed()
