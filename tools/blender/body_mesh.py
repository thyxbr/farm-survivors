# Corpo-base contínuo: UMA malha (tronco, pescoço, braços, pernas e pés ligados) com esqueleto e pesos,
# em vez de peças rígidas penduradas em pivôs. Assim ombro, quadril, joelho e cotovelo dobram sem abrir
# frestas nem "parafusar" uma peça na outra.
# Executado por exec() dentro de build_assets.py, depois de characters.py, body.py, head.py e gear.py
# (usa bpy, bmesh, Vector, coll, empty, _finish, human_head, fist, body_proportions, GEAR_P, HEAD_CHIN, HEAD_H,
# g_mats, export).
#
# Topologia (estilo box modeling):
#   - tronco em anéis de 16 vértices (0 = frente, cresce para +x), da virilha até dentro da cabeça;
#   - cada perna nasce da metade do anel de baixo + um vértice na virilha (laço de 10) e desce em anéis de 10
#     até o tornozelo, onde o mesmo tubo dobra para a frente e vira o pé;
#   - cada braço nasce de um furo de 8 vértices no lado do tronco (3 anéis x 3 colunas) e desce em anéis de 8.
# Pés em Z=0, frente = -Y, altura ~1,84 m (mesmas medidas de GEAR_P).
#
# Esqueleto: ossos com os nomes dos pivôs do jogo (Body, Head, ArmL/R, ElbowL/R, LegL/R, KneeL/R).
# Rotação +X no osso leva o membro para trás; o joelho dobra com +X (canela para trás) e o cotovelo com -X
# (antebraço para a frente).
import math
import bmesh
from mathutils import Vector

CB_NT = 16                                      # vértices por anel do tronco

# z, meia-largura, meia-profundidade, extras (fr/bk = frente/trás, y = deslocamento)
CB_TORSO = [
    (0.845, 0.163, 0.112, dict(bk=1.14, fr=0.95)),   # 0 virilha (linha em V, ver cb_body)
    (0.94, 0.158, 0.11, dict(bk=1.34)),              # 1 glúteos
    (1.005, 0.148, 0.103, dict(bk=1.12)),            # 2 crista ilíaca
    (1.085, 0.137, 0.096, dict(bk=0.98)),            # 3 cintura (lombar entra)
    (1.18, 0.148, 0.103, dict(fr=1.04, bk=1.06)),    # 4 costelas baixas
    (1.235, 0.157, 0.105, dict(fr=1.02, bk=1.1)),    # 5 vinco sob o peitoral
    (1.285, 0.166, 0.11, dict(fr=1.17, bk=1.12)),    # 6 peitoral / dorsais
    (1.35, 0.172, 0.113, dict(fr=1.14, bk=1.14)),    # 7 axila (base do furo do braço)
    (1.405, 0.168, 0.102, dict(fr=1.05, bk=1.12)),   # 8 meio do furo
    (1.46, 0.145, 0.086, dict(bk=1.05)),             # 9 topo do ombro
    (1.5, 0.108, 0.072, dict()),                     # 10 rampa do trapézio
    (1.525, 0.072, 0.066, dict(y=0.01)),             # 11 base do pescoço
    (1.57, 0.064, 0.06, dict(y=0.004)),              # 12
    (1.63, 0.056, 0.054, dict(y=-0.008)),            # 13 (dentro da cabeça)
]
CB_ARM_ROWS = (7, 8, 9)
CB_ARM_COLS = (3, 4, 5)                          # lado esquerdo; o direito usa 16 - j

# articulações (lado esquerdo, x > 0): as mesmas dos pivôs do jogo (body_proportions com GEAR_P), para o
# esqueleto girar exatamente onde o jogo gira os pivôs
_CB_P = body_proportions(**GEAR_P)
CB_J = {n: _CB_P[n].copy() for n in ("pelvis", "neck", "shoulder", "elbow", "wrist", "hip", "knee", "ankle")}


def _cb_at(a, b, z):
    """Ponto do segmento a->b na altura z."""
    return a.lerp(b, (a.z - z) / (a.z - b.z))


def cb_mirror(v, s):
    return Vector((v.x * s, v.y, v.z))


def cb_spt(a, rx, ry, fr=1.0, bk=1.0, sq=2.0, keel=0.0):
    """Ponto da superelipse no ângulo a (0 = frente, 90° = lado +x) -> (x, y) com frente = -y."""
    e = 2.0 / sq
    sa, ca = math.sin(a), math.cos(a)
    x = math.copysign(abs(sa) ** e, sa) * rx
    yy = math.copysign(abs(ca) ** e, ca)
    k = 1.0 + keel * max(0.0, ca) ** 6
    return x * k, -yy * ry * (fr if yy > 0 else bk) * k


def _cb_frames(path, fwd, fwds):
    out, prev = [], None
    for i in range(len(path)):
        a, b = path[max(i - 1, 0)], path[min(i + 1, len(path) - 1)]
        t = (b - a).normalized()
        fw = fwds[i] if fwds[i] is not None else fwd
        f = fw - t * fw.dot(t)
        if f.length < 1e-4:
            f = Vector((0, 0, 1)) - t * t.z
        f.normalize()
        side = f.cross(t).normalized()
        if prev is not None and side.dot(prev) < 0:
            side = -side
        prev = side
        out.append((side, f))
    return out


def _cb_tube(bm, secs, angs, fwd=Vector((0, -1, 0))):
    """Anéis ao longo de secs=[(centro, rx, ry, extras)]; extras pode ter fwd (frente local do anel)."""
    fr = _cb_frames([s[0] for s in secs], fwd, [s[3].get("fwd") for s in secs])
    rings = []
    for (c, rx, ry, ex), (side, f) in zip(secs, fr):
        ex = {k: v for k, v in ex.items() if k != "fwd"}
        if abs(side.x) > 0.5:
            side = Vector((abs(side.x), side.y, side.z))
        r = []
        for a in angs:
            x, y = cb_spt(a, rx, ry, **ex)
            r.append(bm.verts.new(c + side * x - f * y))
        rings.append(r)
    return rings


def _cb_bridge(bm, loop, ring):
    """Liga um laço a um anel do mesmo tamanho, na rotação/sentido de menor distância."""
    n = len(loop)
    best = None
    for rev in (False, True):
        rr = ring[::-1] if rev else ring
        for off in range(n):
            d = sum((loop[i].co - rr[(i + off) % n].co).length for i in range(n))
            if best is None or d < best[0]:
                best = (d, rr, off)
    _, rr, off = best
    for i in range(n):
        bm.faces.new((loop[i], loop[(i + 1) % n], rr[(i + 1 + off) % n], rr[(i + off) % n]))


def _cb_connect(bm, rings, cap=True):
    for a, b in zip(rings, rings[1:]):
        n = len(a)
        for j in range(n):
            k = (j + 1) % n
            bm.faces.new((a[j], a[k], b[k], b[j]))
    if cap:
        bm.faces.new(rings[-1][::-1])


def cb_body(name, material):
    """Malha contínua do corpo (sem cabeça e mãos). Devolve o objeto, em coordenadas de mundo."""
    bm = bmesh.new()
    NT = CB_NT
    rings = []
    for i, (z, rx, ry, ex) in enumerate(CB_TORSO):
        ex = dict(ex)
        yo = ex.pop("y", 0.0)
        r = []
        for j in range(NT):
            a = 2 * math.pi * j / NT
            x, y = cb_spt(a, rx, ry, sq=2.12, **ex)
            zz = z
            if i == 0:   # virilha em V: baixa na frente/atrás do centro, alta nas laterais do quadril
                zz = z - 0.03 + 0.085 * math.sin(a) ** 2
            r.append(bm.verts.new((x, y + yo, zz)))
        rings.append(r)
    hole = set()
    for s in (1, -1):
        for i in CB_ARM_ROWS[:-1]:
            for j in CB_ARM_COLS[:-1]:
                hole.add((i, j if s > 0 else NT - j - 1))
    for i in range(len(rings) - 1):
        for j in range(NT):
            if (i, j) not in hole:
                k = (j + 1) % NT
                bm.faces.new((rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j]))
    bm.faces.new(rings[-1])
    for s in (1, -1):
        bm.verts.remove(rings[CB_ARM_ROWS[1]][CB_ARM_COLS[1] if s > 0 else NT - CB_ARM_COLS[1]])

    # pernas (laço de 10: metade do anel de baixo + virilha) e pés
    crotch = bm.verts.new((0, 0.006, 0.775))
    leg_ang = [math.radians(-54 + 36 * k) for k in range(10)]
    for s in (1, -1):
        hip, knee, ank = (cb_mirror(CB_J[n], s) for n in ("hip", "knee", "ankle"))
        up = Vector((0, -0.6, 0.8)).normalized()
        zf = Vector((0, 0, 1))
        secs = [
            (_cb_at(hip, knee, 0.79), 0.086, 0.096, dict(fr=1.04, bk=1.1)),   # topo da coxa, logo abaixo da virilha
            (_cb_at(hip, knee, 0.73), 0.084, 0.09, dict(fr=1.12, bk=1.02)),   # quadríceps na frente
            (_cb_at(hip, knee, 0.64), 0.073, 0.08, dict(fr=1.1)),
            (_cb_at(hip, knee, 0.565), 0.06, 0.066, dict(fr=1.02)),
            (knee + Vector((0, -0.004, 0)), 0.055, 0.06, dict(keel=0.25)),       # joelho: patela na frente
            (knee.lerp(ank, 0.1), 0.054, 0.058, dict(bk=1.12, fr=0.95)),
            (knee.lerp(ank, 0.27), 0.056, 0.062, dict(bk=1.35, fr=0.92)),      # panturrilha atrás
            (knee.lerp(ank, 0.5), 0.048, 0.052, dict(bk=1.2, fr=0.92)),
            (knee.lerp(ank, 0.78), 0.036, 0.038, dict(bk=1.05)),
            (knee.lerp(ank, 0.95), 0.034, 0.037, dict()),                      # tornozelo
            # pé: o mesmo tubo dobra para a frente; calcanhar saltado atrás, dedos achatados
            (ank + Vector((0, -0.012, -0.04)), 0.04, 0.05, dict(bk=1.25, fwd=up)),
            (ank + Vector((s * 0.002, -0.07, -0.06)), 0.045, 0.034, dict(sq=2.6, fwd=zf)),
            (ank + Vector((s * 0.005, -0.13, -0.066)), 0.048, 0.024, dict(sq=2.8, fwd=zf)),
            (ank + Vector((s * 0.006, -0.172, -0.068)), 0.04, 0.017, dict(sq=2.8, fwd=zf)),
        ]
        rs = _cb_tube(bm, secs, leg_ang if s > 0 else [-a for a in leg_ang])
        top = rings[0]
        loop = [top[(j if s > 0 else (NT - j) % NT)] for j in range(9)] + [crotch]
        _cb_bridge(bm, loop, rs[0])
        _cb_connect(bm, rs)

    # braços (furo de 8 no lado do tronco)
    arm_ang = [2 * math.pi * (k + 0.5) / 8 for k in range(8)]
    for s in (1, -1):
        r6, r7, r8 = (rings[i] for i in CB_ARM_ROWS)
        c = CB_ARM_COLS if s > 0 else tuple(NT - j for j in CB_ARM_COLS)
        loop = [r6[c[0]], r6[c[1]], r6[c[2]], r7[c[2]], r8[c[2]], r8[c[1]], r8[c[0]], r7[c[0]]]
        sh, el, wr = (cb_mirror(CB_J[n], s) for n in ("shoulder", "elbow", "wrist"))
        secs = [
            (sh + Vector((-s * 0.006, 0, -0.02)), 0.06, 0.062, dict()),        # deltoide: desce do trapézio
            (sh + Vector((s * 0.018, 0.002, -0.08)), 0.06, 0.062, dict()),     # volume do deltoide
            (sh.lerp(el, 0.38), 0.05, 0.054, dict(fr=1.12)),                   # bíceps
            (sh.lerp(el, 0.72), 0.044, 0.048, dict(fr=1.05)),
            (el, 0.04, 0.042, dict(bk=1.05)),                                   # cotovelo
            (el.lerp(wr, 0.2), 0.045, 0.045, dict(bk=1.08)),                    # massa do antebraço
            (el.lerp(wr, 0.62), 0.036, 0.032, dict()),
            (wr, 0.03, 0.023, dict()),                                          # pulso
        ]
        rs = _cb_tube(bm, secs, arm_ang)
        _cb_bridge(bm, loop, rs[0])
        _cb_connect(bm, rs)

    # relaxa as junções (ombro/axila e virilha) para a passagem ficar suave
    J = [Vector((0.17, 0, 1.41)), Vector((-0.17, 0, 1.41)), Vector((0.09, 0, 0.83)), Vector((-0.09, 0, 0.83))]
    jv = [v for v in bm.verts if min((v.co - j).length for j in J) < 0.075]
    for _ in range(3):
        bmesh.ops.smooth_vert(bm, verts=jv, factor=0.45, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    print("PART", name, "corpo contínuo", flush=True)
    return _finish(name, bm, material, None)


def cb_rig(name="Rig"):
    """Armature com os ossos nomeados como os pivôs do jogo."""
    ad = bpy.data.armatures.new(name)
    rig = bpy.data.objects.new(name, ad)
    coll.objects.link(rig)
    vl = bpy.context.view_layer
    vl.objects.active = rig
    with bpy.context.temp_override(active_object=rig, object=rig):
        bpy.ops.object.mode_set(mode='EDIT')

    def bone(n, h, t, parent=None):
        b = ad.edit_bones.new(n)
        b.head, b.tail, b.roll = Vector(h), Vector(t), 0.0
        if parent:
            b.parent = ad.edit_bones[parent]

    J = CB_J
    bone("Body", J["pelvis"], (0, 0, 1.4))
    bone("Head", J["neck"], (0, 0, 1.75), "Body")
    for s, n in ((1, "L"), (-1, "R")):
        bone("Arm" + n, cb_mirror(J["shoulder"], s), cb_mirror(J["elbow"], s), "Body")
        bone("Elbow" + n, cb_mirror(J["elbow"], s), cb_mirror(J["wrist"], s), "Arm" + n)
        bone("Leg" + n, cb_mirror(J["hip"], s), cb_mirror(J["knee"], s))
        bone("Knee" + n, cb_mirror(J["knee"], s), cb_mirror(J["ankle"], s), "Leg" + n)
    with bpy.context.temp_override(active_object=rig, object=rig):
        bpy.ops.object.mode_set(mode='OBJECT')
    return rig


def cb_skin(rig, body, rigid=()):
    """Pesos automáticos (calor) no corpo; peças rígidas (cabeça, mãos) ficam 100% no osso dado."""
    vl = bpy.context.view_layer
    for o in coll.all_objects:
        o.select_set(False)
    body.select_set(True)
    rig.select_set(True)
    vl.objects.active = rig
    with bpy.context.temp_override(active_object=rig, object=rig, selected_objects=[body, rig],
                                   selected_editable_objects=[body, rig]):
        bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    for ob, bone in rigid:
        g = ob.vertex_groups.new(name=bone)
        g.add([v.index for v in ob.data.vertices], 1.0, 'REPLACE')
        mw = ob.matrix_world.copy()
        ob.parent = rig
        ob.matrix_world = mw
        md = ob.modifiers.new("Armature", 'ARMATURE')
        md.object = rig


def cb_character(M=None):
    """Corpo contínuo + cabeça + mãos, tudo preso ao esqueleto. Devolve (rig, corpo)."""
    M = M or g_mats()
    root = empty("CBTmp", (0, 0, 0))
    body = cb_body("BodyMesh", M["skin"])
    face_mats = {"skin": M["skin"], "pupil": M["eye"], "sclera": M["sclera"], "brow": M["hair"], "lip": M["lip"]}
    before = set(coll.all_objects)
    human_head("", HEAD_CHIN, HEAD_H, root, face_mats, {"jaw": 1.08, "chin": 1.1, "brow": 1.2, "nose": 1.05})
    heads = [o for o in coll.all_objects if o not in before and o.type == 'MESH']
    P = body_proportions(**GEAR_P)
    hands = []
    for s, n in ((1, "L"), (-1, "R")):
        hands.append((fist("Arm" + n, P, s, M["skin"], root), "Elbow" + n))
    for o in heads + [h for h, _ in hands]:
        o.parent = None
    bpy.data.objects.remove(root)
    rig = cb_rig()
    cb_skin(rig, body, [(o, "Head") for o in heads] + hands)
    return rig, body


def build_body_base():
    cb_character()
    export("body_base")


# ================================================================== roupas padrão com esqueleto
# Camisa, calça e sapato são cascas tiradas da própria malha do corpo (mesmos vértices e mesmos pesos),
# empurradas para fora pela normal. Por isso dobram exatamente junto com o corpo, sem frestas. A pele que
# fica coberta é apagada (não aparece através do pano quando o membro dobra).
# Cada estilo vira assets/models/gear/<estilo>.glb com seu próprio esqueleto (ossos com os nomes dos pivôs);
# no jogo, PivotSkin faz esse esqueleto copiar a pose dos pivôs do cavaleiro.

def cb_piece(src, name, keep, offset=0.0, material=None, mat_fn=None, mats=()):
    """Cópia de src só com as faces em que keep(centro, osso, normal) é verdadeiro; offset empurra pela
    normal (calculada no corpo inteiro, então peças vizinhas continuam encostadas)."""
    ob = src.copy()
    ob.data = src.data.copy()
    ob.name = ob.data.name = name
    coll.objects.link(ob)
    gname = {g.index: g.name for g in src.vertex_groups}
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    dl = bm.verts.layers.deform.active
    bm.normal_update()
    nrm = {v: v.normal.copy() for v in bm.verts}
    drop = []
    for f in bm.faces:
        acc = {}
        for v in f.verts:
            for gi, w in v[dl].items():
                acc[gi] = acc.get(gi, 0.0) + w
        bone = gname.get(max(acc, key=acc.get), "") if acc else ""
        if not keep(f.calc_center_median(), bone, f.normal):
            drop.append(f)
    bmesh.ops.delete(bm, geom=drop, context='FACES')
    if offset:
        for v in bm.verts:
            v.co += nrm[v] * offset
    if material is not None:
        ob.data.materials.clear()
        ob.data.materials.append(material)
        for m in mats:
            ob.data.materials.append(m)
        for f in bm.faces:
            f.material_index = mat_fn(f) if mat_fn else 0
    bm.to_mesh(ob.data)
    bm.free()
    return ob


def _cb_t(c, a, b):
    """Posição de c ao longo do segmento a->b (0..1)."""
    d = b - a
    return (c - a).dot(d) / d.length_squared


def _cb_fore_t(c):
    s = 1 if c.x > 0 else -1
    return _cb_t(c, cb_mirror(CB_J["elbow"], s), cb_mirror(CB_J["wrist"], s))


def _cb_rigid(rig, objs):
    """Prende peças rígidas (objeto, osso) ao esqueleto com peso 1."""
    for ob, bone in objs:
        g = ob.vertex_groups.new(name=bone)
        g.add([v.index for v in ob.data.vertices], 1.0, 'REPLACE')
        mw = ob.matrix_world.copy()
        ob.parent = rig
        ob.matrix_world = mw
        ob.modifiers.new("Armature", 'ARMATURE').object = rig


def _cb_start(M):
    """Esqueleto + corpo com pesos (corpo inteiro, só como fonte das peças)."""
    rig = cb_rig("Rig")
    body = cb_body("BodySrc", M["skin"])
    cb_skin(rig, body)
    return rig, body


def _cb_finish(style, body):
    bpy.data.objects.remove(body, do_unlink=True)
    g_export(style)


SLEEVE_END = 0.42           # fração do antebraço onde termina a manga arregaçada


def build_h_bare():
    """Cabeça com cabelo curto, presa ao osso Head."""
    M = g_mats()
    rig = cb_rig("Rig")
    root = empty("CBTmp", (0, 0, 0))
    before = set(coll.all_objects)
    plain_head({"Head": root}, M)
    parts = [o for o in coll.all_objects if o not in before and o.type == 'MESH']
    for o in parts:
        o.parent = None
    bpy.data.objects.remove(root)
    _cb_rigid(rig, [(o, "Head") for o in parts])
    g_export("h_bare")


def build_g_bare():
    """Mãos fechadas (pele), presas aos ossos ElbowL/ElbowR."""
    M = g_mats()
    rig = cb_rig("Rig")
    root = empty("CBTmp", (0, 0, 0))
    P = body_proportions(**GEAR_P)
    hands = [(fist("Arm" + n, P, s, M["skin"], root), "Elbow" + n) for n, s in (("L", 1), ("R", -1))]
    for o, _ in hands:
        o.parent = None
    bpy.data.objects.remove(root)
    _cb_rigid(rig, hands)
    g_export("g_bare")


def build_a_shirt():
    """Sem armadura: camisa de linho solta por fora da calça, mangas arregaçadas com punho dobrado, gola,
    cinto com fivela; calça até o joelho (a canela vem do estilo dos pés). Pescoço e antebraços de pele."""
    M = g_mats()
    rig, body = _cb_start(M)
    knee_z = CB_J["knee"].z

    def is_arm(b):
        return b.startswith("Arm") or b.startswith("Elbow")

    def fore(c, b):
        return b.startswith("Elbow") and _cb_fore_t(c) > SLEEVE_END - 0.06

    # pele à vista: pescoço e antebraço abaixo da manga
    cb_piece(body, "SkinUpper", lambda c, b, n: c.z > 1.49 or fore(c, b))
    # tronco x pernas pela geometria (os pesos do quadril se dividem entre Body e as pernas)
    def torso(c, b):
        return not is_arm(b) and c.z >= 0.86 and not (b.startswith("Knee"))

    # camisa solta: do pescoço até cobrir o alto da coxa + braço até a manga
    shirt = lambda c, b, n: (torso(c, b) and c.z < 1.51) or         (is_arm(b) and (b.startswith("Arm") or _cb_fore_t(c) < SLEEVE_END))
    cb_piece(body, "Shirt", shirt, 0.014, M["linen"])
    cb_piece(body, "ShirtHem", lambda c, b, n: torso(c, b) and c.z < 0.93, 0.02, M["linen_d"])
    cb_piece(body, "ShirtCollar", lambda c, b, n: torso(c, b) and 1.485 < c.z < 1.51, 0.017, M["linen_d"])
    cb_piece(body, "ShirtCuff", lambda c, b, n: b.startswith("Elbow") and SLEEVE_END - 0.11 < _cb_fore_t(c) < SLEEVE_END,
             0.024, M["linen_d"])
    # calça: quadril e coxas (até o joelho; a canela é do estilo dos pés)
    cb_piece(body, "Pants", lambda c, b, n: not is_arm(b) and c.z < 1.0 and c.z > knee_z - 0.03, 0.009, M["pants"])
    cb_piece(body, "Belt", lambda c, b, n: torso(c, b) and 0.965 < c.z < 1.03, 0.027, M["lea"])
    fy = -0.112 - 0.03
    buckle = tbox("BeltBuckle", (0, fy, 0.992), (0.048, 0.01, 0.04), M["brass"], bevel=0.004)
    tip = tbox("BeltTip", (0.03, fy + 0.002, 0.95), (0.024, 0.006, 0.07), M["lea"], bevel=0.002)
    vee = tbox("ShirtV", (0, -0.113, 1.43), (0.05, 0.006, 0.07), M["skin"], bottom=(0.1, 1))
    _cb_rigid(rig, [(buckle, "Body"), (tip, "Body"), (vee, "Body")])
    _cb_finish("a_shirt", body)


def build_f_shoes():
    """Sem botas: calça na canela (tp_) e sapato baixo de couro com sola escura."""
    M = g_mats()
    rig, body = _cb_start(M)
    knee_z = CB_J["knee"].z
    shin = lambda c, b, n: b.startswith("Knee") and 0.13 < c.z < knee_z + 0.03 or (b.startswith("Leg") and c.z < knee_z + 0.03)
    cb_piece(body, "PantsShin", shin, 0.009, M["pants"])
    shoe = lambda c, b, n: (b.startswith("Knee") or b.startswith("Leg")) and c.z <= 0.15
    cb_piece(body, "Shoes", shoe, 0.012, M["lea"], mat_fn=lambda f: 1 if f.normal.z < -0.5 else 0, mats=(M["lea_d"],))
    cb_piece(body, "ShoeTop", lambda c, b, n: b.startswith("Knee") and 0.11 < c.z <= 0.15, 0.02, M["lea_d"])
    _cb_finish("f_shoes", body)


_CB_SKINNED = {"h_bare": build_h_bare, "a_shirt": build_a_shirt, "g_bare": build_g_bare, "f_shoes": build_f_shoes}
GEAR = [(n, _CB_SKINNED.get(n, f)) for n, f in GEAR]
