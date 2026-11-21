# Chefes de dungeon com modelo próprio. Executado por build_assets.py depois de monsters.py (usa os helpers de
# monsters.py, anime_body.py e body.py). Frente = -Y, Z para cima. Cada membro nasce de dentro do corpo, com o
# pivô dentro do corpo: girando, a emenda continua escondida e nada fica solto (loose_parts confere no build).
import math
import random


# ================================================================== ESPINHEIRA, A GUARDIÃ-RAIZ (chefe do Bosque)
# Árvore antiga corrompida (~5 m com a copa) que anda sobre duas pernas de raiz. Tronco torto e nodoso, casca em
# relevo (cristas, nós, tocos de galho quebrado, cogumelos-de-prateleira, um cipó em espiral), um oco no peito com
# o coração de corrupção aceso, rosto entalhado com barba de musgo, saia de raízes na base. Os braços e as pernas
# são continuação da madeira: saem de dentro do tronco num colarinho grosso e dobram num nó alongado (nada de
# bola). A copa é galho de verdade: três galhos mestres que se ramificam, ramos finos e folhas uma a uma (verdes,
# com um lado roxo de corrupção), um galho morto com espinhos e cipós pendurados. Frente = -Y.
# Pivôs animados por scripts/enemies/enemy.gd (_animate_thorn): Body (tronco, no quadril), Head (o rosto, dentro de
# Body), Jaw (queixo e barba, dentro de Head), Crown (a copa, dentro de Body) > BoughL/BoughR (galhos mestres dos
# lados) e Hang0..Hang3 (cipós pendurados), ArmL/ArmR (no ombro, DENTRO do tronco) > ElbowL/ElbowR > HandL/HandR
# (a mão de garras) e LegL/LegR (no quadril, dentro do tronco) > KneeL/KneeR (canela e pé de raiz).
THORN_HIP = 1.15


def _bark_tube(name, pts, r0, r1, bark, bark_d, parent, sides=12, n=16, stripe=3, radii=None):
    """Galho/raiz liso por uma linha de pontos, com sulcos de casca (colunas alternadas mais escuras). `radii`
    dá o raio em cada ponto (senão afina de r0 a r1)."""
    k = len(pts)
    rr = radii or [r0 + (r1 - r0) * i / (k - 1) for i in range(k)]
    secs = fera_dense([sec(p, rr[i], rr[i]) for i, p in enumerate(pts)], n, cut=2)
    return sloft(name, secs, bark, parent, sides=sides, fwd=(0, 0, 1), mats=(bark_d,),
                 matf=lambda i, j: 1 if j % stripe == 0 else 0, sharp=80.0)


def _knot(name, a, b, r, material, parent, sides=12):
    """Nó de madeira alongado na direção a→b (fuso): cobre a dobra de um membro sem virar bola."""
    a, b = Vector(a), Vector(b)
    prof = ((0.0, 0.7), (0.15, 0.9), (0.35, 1.0), (0.5, 0.93), (0.65, 1.0), (0.85, 0.9), (1.0, 0.7))
    secs = [sec(a.lerp(b, t), r * k, r * k * 0.94) for t, k in prof]
    return sloft(name, secs, material, parent, sides=sides, fwd=(0, 0, 1), sharp=80.0)


def _leaves(name, stems, mats, parent, seed, per=7, size=0.32, weights=None):
    """Folhas uma a uma ao longo de cada ramo (p0→p1) de `stems`: lâmina pontuda dobrada ao meio, alternando de
    lado em espiral, a ponta caindo um pouco. Uma malha só, com as duas faces. `weights` = peso de cada material."""
    rnd = random.Random(seed)
    bm = bmesh.new()
    up = Vector((0, 0, 1))
    pick = []
    for i, _m in enumerate(mats):
        pick += [i] * int((weights[i] if weights else 1) * 10)
    for p0, p1 in stems:
        p0, p1 = Vector(p0), Vector(p1)
        ax = (p1 - p0).normalized()
        ref = ax.cross(up)
        if ref.length < 1e-3:
            ref = ax.cross(Vector((1, 0, 0)))
        ref.normalize()
        ref2 = ax.cross(ref)
        a0 = rnd.uniform(0, math.tau)
        for i in range(per + 1):
            tip = i == per
            t = 1.0 if tip else (i + 0.5) / per
            base = p0.lerp(p1, t) - ax * 0.01
            ang = a0 + i * 2.4
            radial = ref * math.cos(ang) + ref2 * math.sin(ang)
            d = (ax if tip else (ax * 0.55 + radial * 0.9 + up * 0.12)).normalized()
            ln = size * rnd.uniform(0.8, 1.2) * (1.1 if tip else 1.0)
            w = ln * rnd.uniform(0.42, 0.55)
            side = d.cross(up)
            if side.length < 1e-3:
                side = d.cross(ref)
            side.normalize()
            nrm = side.cross(d).normalized()
            if nrm.z < 0:
                nrm = -nrm
            mid = base + d * ln * 0.42
            pts = (base, mid + side * w * 0.5 + nrm * ln * 0.09, base + d * ln - nrm * ln * 0.16,
                   mid - side * w * 0.5 + nrm * ln * 0.09)
            mi = pick[rnd.randrange(len(pick))]
            for flip in (False, True):
                v = [bm.verts.new(p) for p in pts]
                for tri in ((0, 1, 2), (0, 2, 3)):
                    f = bm.faces.new([v[k] for k in (reversed(tri) if flip else tri)])
                    f.material_index = mi
    print("PART", name, "leaves", flush=True)
    bmesh.ops.translate(bm, vec=-_wloc(parent), verts=bm.verts)
    ob = _finish(name, bm, mats[0], parent, smooth=False)
    for m in mats[1:]:
        ob.data.materials.append(m)
    return ob


def _spray(name, origin, direction, length, bark, bark_d, mats, parent, seed, twigs=5, per=7, size=0.32, spread=0.75,
           weights=None):
    """Ramo folhado: `twigs` raminhos em leque a partir de `origin` em volta de `direction`, cada um com as suas
    folhas. Os raminhos nascem um pouco para trás (dentro do galho de onde saem)."""
    rnd = random.Random(seed)
    origin = Vector(origin)
    d = Vector(direction).normalized()
    ref = d.cross(Vector((0, 0, 1)))
    if ref.length < 1e-3:
        ref = d.cross(Vector((1, 0, 0)))
    ref.normalize()
    ref2 = d.cross(ref)
    stems = []
    for k in range(twigs):
        if k == 0:
            td = d
        else:
            a = math.tau * k / (twigs - 1) + rnd.uniform(-0.3, 0.3)
            td = (d + (ref * math.cos(a) + ref2 * math.sin(a)) * spread * rnd.uniform(0.7, 1.1)).normalized()
        ln = length * rnd.uniform(0.8, 1.15)
        p0 = origin - d * 0.08
        p1 = origin + td * ln * 0.55 + Vector((0, 0, 0.04))
        p2 = origin + td * ln - Vector((0, 0, ln * 0.12))
        _bark_tube("%s_Twig%d" % (name, k), [p0, p1, p2], 0.04, 0.012, bark, bark_d, parent, sides=5, n=6)
        stems.append((p0.lerp(p1, 0.5), p1))
        stems.append((p1, p2))
    _leaves(name + "_Leaves", stems, mats, parent, seed * 7 + 1, per=max(2, per // 2), size=size, weights=weights)


def _gnarl(secs, seed, wob=0.05, amt=0.08):
    """Tronco torto: desloca o centro e varia a largura de cada anel (mesma semente, mesmo tronco)."""
    rnd = random.Random(seed)
    ph = [rnd.uniform(0, 6.28) for _ in range(4)]
    for i, s in enumerate(secs[1:-1], 1):
        z = s["c"].z
        s["c"] = s["c"] + Vector((math.sin(z * 2.3 + ph[0]) * wob, math.sin(z * 1.9 + ph[1]) * wob * 0.7, 0))
        s["rx"] *= 1.0 + math.sin(z * 3.1 + ph[2]) * amt
        s["ry"] *= 1.0 + math.sin(z * 2.7 + ph[3]) * amt
    return secs


def build_thorn_tree():
    bark = mat("tt_bark", hexc("#5E4838"), 0.95)
    bark_d = mat("tt_bark_d", hexc("#33261E"), 0.95)
    bark_l = mat("tt_bark_l", hexc("#84694F"), 0.95)
    heartwood = mat("tt_heartwood", hexc("#C9A873"), 0.9)       # madeira clara dos tocos quebrados
    moss = mat("tt_moss", hexc("#52702B"), 0.95)
    moss_d = mat("tt_moss_d", hexc("#34501F"), 0.95)
    leaf = mat("tt_leaf", hexc("#3F6B2C"), 0.9)
    leaf_d = mat("tt_leaf_d", hexc("#27481F"), 0.9)
    leaf_l = mat("tt_leaf_l", hexc("#6A9438"), 0.9)
    leaf_c = mat("tt_leaf_c", hexc("#8A2A5C"), 0.9)            # folhas tomadas pela corrupção
    leaf_c2 = mat("tt_leaf_c2", hexc("#C2496A"), 0.9)
    thorn = mat("tt_thorn", hexc("#2A1A1E"), 0.6)
    cap = mat("tt_shroom", hexc("#C8743A"), 0.8)
    cap_u = mat("tt_shroom_u", hexc("#E9D2A4"), 0.8)
    vein = mat("tt_vein", hexc("#C21A5C"), 0.4, 0.0, emit=(0.85, 0.08, 0.38), strength=2.6)
    eye = mat("tt_eye_flat", hexc("#FF5A8A"), 0.2, 0.0, emit=(1.0, 0.2, 0.45), strength=4.5)
    maw = mat("tt_maw_flat", hexc("#1A0610"), 0.9)
    tooth = mat("tt_tooth", hexc("#B8A27E"), 0.8)
    GREEN = (leaf, leaf_d, leaf_l)
    SICK = (leaf_c, leaf_c2, leaf_d)
    MIX = (leaf, leaf_d, leaf_l, leaf_c)
    HIP = THORN_HIP
    up = Vector((0, 0, 1))

    root = empty("Thorn", (0, 0, 0))

    # ---------------- tronco: base larga onde as pernas entram, cintura, peito largo e corcunda, curvado para a
    # frente; no alto continua largo e os galhos mestres saem de dentro dele
    body = empty("Body", (0, 0, HIP), root)
    trunk = _gnarl(fera_dense([sec((0, 0.06, HIP - 0.42), 0.4, 0.36), sec((0, 0.05, HIP - 0.1), 0.66, 0.56),
                               sec((0, 0.03, HIP + 0.4), 0.56, 0.48), sec((0, -0.04, 1.95), 0.6, 0.5),
                               sec((0, -0.16, 2.5), 0.74, 0.6, bk=1.25), sec((0, -0.22, 2.95), 0.7, 0.58, bk=1.3),
                               sec((0, -0.2, 3.3), 0.66, 0.56), sec((0, -0.18, 3.55), 0.6, 0.52)], 26, cut=2), 5)
    sloft("Trunk", trunk, bark, body, sides=24, phase=0.0, mats=(bark_d,),
          matf=lambda i, j: 1 if j % 3 == 1 else 0, sharp=80.0)

    def surf(z, deg, out=0.0):
        return _vsurf(trunk, z, deg, out)

    # cristas de casca em relevo: tiras grossas que sobem o tronco serpenteando, meio enterradas
    rnd = random.Random(3)
    for k in range(13):
        deg = k * 360.0 / 13 + rnd.uniform(-8, 8)
        if 60 < deg % 360 < 120:
            z0, z1 = 0.95, 1.5        # na frente só embaixo: em cima ficam o oco e o rosto
        else:
            z0, z1 = rnd.uniform(0.85, 1.2), rnd.uniform(2.5, 3.35)
        pts = []
        z = z0
        while z < z1:
            pts.append(surf(z, deg + math.sin(z * 2.2 + k) * 7.0, -0.02))
            z += 0.22
        if len(pts) >= 3:
            fera_curve("Ridge%d" % k, pts, rnd.uniform(0.075, 0.105), 0.035, bark_l if k % 2 == 0 else bark_d, body, sides=6)
    for k, d in enumerate((20, 62, 118, 160, 215, 270, 325)):
        o = Vector((math.cos(math.radians(d)), -math.sin(math.radians(d)), 0))
        _bark_tube("Buttress%d" % k, [surf(2.05, d, -0.1), surf(1.6, d + 5, -0.02), surf(1.2, d - 4, 0.04),
                                      surf(0.95, d, 0.0), surf(0.8, d, -0.16)],
                   0, 0, bark, bark_d, body, sides=8, n=12, radii=[0.07, 0.12, 0.17, 0.15, 0.1])
    # nós de casca (olhos de madeira): calombo com um anel escuro no meio
    for k, (z, d, r) in enumerate(((1.5, 150, 0.15), (2.75, 205, 0.16), (2.2, 320, 0.14), (1.35, 40, 0.13),
                                   (3.05, 300, 0.13))):
        c = surf(z, d, -0.07)
        out = (c - Vector((trunk[0]["c"].x, trunk[0]["c"].y, z))).normalized()
        _blob("Burl%d" % k, c, r, r, r * 1.15, bark_l, body, sides=12, rings=8)
        _blob("BurlEye%d" % k, c + out * r * 0.72, r * 0.42, r * 0.42, r * 0.5, bark_d, body, sides=10, rings=6)
    # tocos de galho quebrado: toco curto com a madeira clara à mostra e lascas
    for k, (z, d, ln, r) in enumerate(((2.35, 178, 0.42, 0.11), (1.75, 12, 0.34, 0.1), (2.9, 252, 0.4, 0.1))):
        p = surf(z, d, -0.1)
        out = ((p - Vector((0, trunk[0]["c"].y, z))).normalized() + up * 0.45).normalized()
        e = p + out * (ln + 0.1)
        sloft("Stub%d" % k, [sec(p, r * 1.25, r * 1.25), sec(p.lerp(e, 0.55), r, r), sec(e, r * 0.9, r * 0.9)],
              bark, body, sides=8, fwd=(0, 0, 1), mats=(heartwood,), matf=lambda i, j: 0, sharp=50.0)
        sloft("StubCut%d" % k, [sec(e - out * 0.02, r * 0.78, r * 0.78), sec(e + out * 0.015, r * 0.7, r * 0.7)],
              heartwood, body, sides=8, fwd=(0, 0, 1), sharp=40.0)
        for j in range(3):   # lascas
            a = Vector((math.cos(j * 2.1 + k), math.sin(j * 2.1 + k), 0)).cross(out).normalized()
            fera_tip("StubSplint%d_%d" % (k, j), e + a * r * 0.5 - out * 0.03, e + a * r * 0.62 + out * (0.1 + 0.05 * j),
                     0.03, heartwood, body)
    # cogumelos-de-prateleira subindo pelo lado esquerdo e nas costas
    for k, (z, d, r) in enumerate(((1.45, 196, 0.2), (1.68, 204, 0.16), (1.88, 190, 0.12), (2.05, 268, 0.18),
                                   (2.24, 278, 0.13))):
        c = surf(z, d, 0.0)
        out = (c - Vector((0, trunk[0]["c"].y, z))).normalized()
        cc = c + out * r * 0.45
        sloft("Shroom%d" % k, [sec(cc + Vector((0, 0, -0.035)), r * 0.55, r * 0.55), sec(cc + Vector((0, 0, -0.01)), r, r),
                               sec(cc + Vector((0, 0, 0.03)), r * 0.92, r * 0.92),
                               sec(cc + Vector((0, 0, 0.07)), r * 0.3, r * 0.3)],
              cap_u, body, sides=10, fwd=(0, -1, 0), mats=(cap,), matf=lambda i, j: 1 if i >= 1 else 0, sharp=60.0)
    # espinhos pelo tronco (costas e lados)
    for k, (z, d, ln) in enumerate(((1.25, 20, 0.24), (1.4, 165, 0.22), (2.05, 215, 0.28), (2.3, 345, 0.26),
                                    (2.6, 232, 0.32), (1.85, 290, 0.32), (2.75, 262, 0.3), (1.1, 275, 0.24),
                                    (3.1, 240, 0.26), (3.0, 330, 0.24), (2.45, 300, 0.3))):
        p = surf(z, d, -0.04)
        out = (p - Vector((0, trunk[0]["c"].y, z))).normalized()
        fera_tip("TrunkThorn%d" % k, p, p + (out + up * 0.35).normalized() * ln, 0.05, thorn, body)
    # cipó em espiral em volta do tronco, com folhinhas
    vine_pts = [surf(1.0 + 2.2 * i / 30, 130 + 560 * i / 30, 0.025) for i in range(31)]
    fera_curve("Vine", vine_pts, 0.04, 0.02, moss_d, body, sides=5)
    _leaves("VineLeaves", [(vine_pts[i], vine_pts[i] + (vine_pts[i] - Vector((0, 0, vine_pts[i].z))).normalized() * 0.03
                            + up * 0.02) for i in range(2, 30, 2)], (leaf, leaf_l, leaf_d), body, 21, per=1, size=0.2)
    # musgo: tapete nas costas da corcunda e mechas penduradas
    for k, (z, d) in enumerate(((3.2, 262), (3.05, 228), (3.12, 300), (2.9, 270))):
        c = surf(z, d, -0.06)
        _rock("MossPad%d" % k, c, 0.26, moss if k % 2 else moss_d, body, squash=(1.0, 1.0, 0.5), sides=7)
        for j in range(3):
            p = surf(z - 0.05, d + (j - 1) * 9, 0.0)
            fera_curve("MossStrand%d_%d" % (k, j), [p + up * 0.05, p - up * 0.2, p - up * (0.45 + 0.1 * j)
                                                  + Vector((0, 0.03, 0))], 0.035, 0.008, moss, body, sides=5)
    # ---------------- o oco do peito: cavidade escura com borda de casca e o coração de corrupção aceso lá dentro;
    # os veios acesos saem dele pela casca
    hc = surf(1.56, 90, -0.06)
    sloft("Hollow", [sec(hc + Vector((0, 0.14, 0)), 0.15, 0.21), sec(hc + Vector((0, -0.01, 0)), 0.18, 0.25),
                     sec(hc + Vector((0, -0.045, 0)), 0.15, 0.22)], maw, body, sides=14, fwd=(0, 0, 1), axis=(0, -1, 0))
    rim = []
    for i in range(17):
        a = math.tau * i / 16
        rim.append(surf(1.56 + math.sin(a) * 0.26, 90 + math.degrees(math.cos(a) * 0.19 / 0.55), 0.0))
    fera_curve("HollowRim", rim, 0.06, 0.055, bark_l, body, sides=6)
    _blob("Heart", hc + Vector((0, 0.02, -0.02)), 0.1, 0.09, 0.13, eye, body, sides=10, rings=8)
    for k, pts in enumerate((((1.3, 96), (1.12, 104), (0.95, 97)), ((1.4, 70), (1.2, 58), (1.05, 66)),
                             ((1.8, 108), (1.98, 124), (2.2, 140), (2.6, 148)), ((1.78, 72), (1.95, 54), (2.3, 40)),
                             ((1.56, 120), (1.7, 150), (2.0, 172), (2.4, 186)),
                             ((1.2, 250), (1.6, 262), (2.0, 252), (2.45, 266), (2.9, 258)),
                             ((1.5, 300), (1.85, 292), (2.2, 306)))):
        fera_curve("Vein%d" % k, [surf(z, d, 0.012) for z, d in pts], 0.032, 0.012, vein, body, sides=5)

    # ---------------- rosto entalhado: sobrancelhas de casca caídas para o meio, olhos em fenda acesos e inclinados,
    # nariz de galho quebrado, boca larga rachada com dentes de lasca e a barba de musgo no queixo
    head = empty("Head", (0, -0.55, 2.65), body)
    for s in (1, -1):
        nm = "L" if s > 0 else "R"
        bp = surf(2.92, 90 - s * 26, -0.05)
        sloft("Brow" + nm, fera_dense([sec(bp + Vector((-s * 0.25, 0.02, -0.14)), 0.09, 0.09),
                                       sec(bp + Vector((0, -0.07, 0.0)), 0.15, 0.13),
                                       sec(bp + Vector((s * 0.26, 0.08, 0.1)), 0.07, 0.07)], 10),
              bark_l, head, sides=10, fwd=(0, -1, 0), axis=(1, 0, 0), sharp=80.0)
        fera_tip("BrowThorn" + nm, bp + Vector((s * 0.2, 0.0, 0.1)), bp + Vector((s * 0.36, -0.06, 0.34)), 0.05, thorn, head)
        ec = surf(2.74, 90 - s * 26, -0.02)
        tilt = (s * 0.42, 0.0, 1.0)   # canto de dentro mais baixo: olhar bravo
        sloft("EyeSocket" + nm, [sec(ec + Vector((0, 0.07, 0)), 0.17, 0.09), sec(ec + Vector((0, -0.005, 0)), 0.19, 0.1),
                                 sec(ec + Vector((0, -0.02, 0)), 0.17, 0.085)], maw, head, sides=12,
              fwd=tilt, axis=(0, -1, 0))
        sloft("Eye" + nm, [sec(ec + Vector((0, 0.0, 0)), 0.13, 0.046), sec(ec + Vector((0, -0.032, 0)), 0.115, 0.037),
                           sec(ec + Vector((0, -0.04, 0)), 0.03, 0.012)], eye, head, sides=10,
              fwd=tilt, axis=(0, -1, 0))
        # rachadura de corrupção descendo do olho
        fera_curve("Tear" + nm, [surf(2.66, 90 - s * 30, 0.01), surf(2.5, 90 - s * 36, 0.01),
                                 surf(2.34, 90 - s * 32, 0.01)], 0.022, 0.008, vein, head, sides=5)
    np_ = surf(2.56, 90, -0.04)
    sloft("Nose", fera_dense([sec(np_ + Vector((0, 0.08, 0.1)), 0.1, 0.09), sec(np_ + Vector((0, -0.1, -0.02)), 0.08, 0.07),
                              sec(np_ + Vector((0, -0.2, -0.08)), 0.045, 0.04)], 8), bark_l, head, sides=10,
          fwd=(0, 0, 1), axis=(0, -1, 0), sharp=80.0)
    mc = surf(2.28, 90, -0.04)
    sloft("Maw", [sec(mc + Vector((0, 0.1, 0)), 0.34, 0.15), sec(mc + Vector((0, -0.02, 0)), 0.38, 0.18),
                  sec(mc + Vector((0, -0.05, 0)), 0.34, 0.14)], maw, head, sides=16, fwd=(0, 0, 1), axis=(0, -1, 0))
    for k in range(7):
        x = (k - 3) * 0.095
        p = Vector((x, mc.y - 0.05, mc.z + 0.14 - 0.03 * (abs(k - 3) / 3) ** 2))
        fera_tip("UpTooth%d" % k, p, p + Vector((0, -0.01, -0.14 + 0.025 * abs(k - 3) + 0.035 * (k % 2))), 0.036,
                 tooth, head)
    jaw = empty("Jaw", (0, mc.y + 0.08, mc.z - 0.02), head)
    sloft("JawMesh", fera_dense([sec(mc + Vector((-0.38, 0.05, -0.12)), 0.1, 0.1),
                                 sec(mc + Vector((0, -0.08, -0.22)), 0.15, 0.12),
                                 sec(mc + Vector((0.38, 0.05, -0.12)), 0.1, 0.1)], 12),
          bark_l, jaw, sides=10, fwd=(0, -1, 0), axis=(1, 0, 0), sharp=80.0)
    for k in range(6):
        x = (k - 2.5) * 0.105
        p = Vector((x, mc.y - 0.08, mc.z - 0.13))
        fera_tip("LowTooth%d" % k, p, p + Vector((0, -0.01, 0.11 - 0.03 * (k % 2))), 0.03, tooth, jaw)
    for k in range(7):   # barba de musgo pendurada no queixo
        x = (k - 3) * 0.09
        p = Vector((x, mc.y - 0.06 + 0.02 * abs(k - 3), mc.z - 0.26))
        fera_curve("Beard%d" % k, [p + up * 0.08, p - up * 0.14 + Vector((0, -0.02, 0)),
                                   p - up * (0.3 - 0.05 * abs(k - 3)) + Vector((x * 0.2, 0.01, 0))],
                   0.05, 0.008, moss if k % 2 else moss_d, jaw, sides=5)

    # ---------------- copa: três galhos mestres que saem de dentro do topo do tronco e se ramificam; ramos finos
    # com folhas uma a uma; um galho morto com espinhos na frente; cipós pendurados que balançam
    crown = empty("Crown", (0, -0.18, 3.25), body)
    top = Vector((0, -0.18, 3.3))
    mains = (
        ("BoughL", [(0.2, 0.0, -0.35), (0.6, 0.05, 0.5), (1.15, 0.12, 1.0), (1.7, 0.18, 1.25)], 0.34, GREEN, None),
        ("BoughR", [(-0.22, 0.0, -0.35), (-0.68, 0.1, 0.42), (-1.25, 0.22, 0.85), (-1.8, 0.34, 1.0)], 0.34, MIX, None),
        ("BoughC", [(0.0, 0.1, -0.35), (0.12, 0.3, 0.7), (-0.06, 0.5, 1.4), (0.12, 0.55, 2.0)], 0.36, GREEN, None),
    )
    hang_at = []
    n_spray = 0
    for bi, (bname, rel, r, pal, _x) in enumerate(mains):
        par = crown if bname == "BoughC" else empty(bname, top + Vector(rel[0]) + Vector((0, 0, 0.25)), crown)
        pts = [top + Vector(p) for p in rel]
        _bark_tube(bname + "_Main", pts, 0, 0, bark, bark_d, par, sides=12, n=18, radii=[r, r * 0.72, r * 0.45, r * 0.2])
        path = fera_dense([sec(p, 0.1, 0.1) for p in pts], 24, cut=2)
        along = (pts[3] - pts[2]).normalized()
        # ramos secundários: sobem e abrem para a frente e para trás
        for si, (t, dv, ln) in enumerate(((0.42, (0.0, -0.55, 0.85), 0.95), (0.58, (0.0, 0.6, 0.8), 0.9),
                                          (0.78, (0.0, -0.4, 0.7), 0.75), (0.9, (0.0, 0.45, 0.55), 0.6))):
            c = sample(path, t)["c"]
            d = (Vector(dv) + along * 0.45).normalized()
            if bname == "BoughC":
                d = (Vector((dv[1] * 1.1, dv[0] * 0.3 - 0.1 * (si % 2), dv[2] * 0.9))).normalized()
            e1 = c + d * ln * 0.55 + up * 0.05
            e2 = c + d * ln
            _bark_tube("%s_Sec%d" % (bname, si), [c - d * 0.06, e1, e2], r * (0.5 - 0.3 * t) + 0.05, 0.035, bark, bark_d,
                       par, sides=8, n=9)
            n_spray += 1
            _spray("%s_Spray%d" % (bname, si), e2, d + up * 0.25, 0.62, bark, bark_d,
                   SICK if (bname == "BoughR" and si >= 2) else pal, par, 100 + n_spray, twigs=5, per=8, size=0.34)
            n_spray += 1
            _spray("%s_SprayM%d" % (bname, si), e1, (d + up * 0.9).normalized(), 0.5, bark, bark_d, pal, par,
                   100 + n_spray, twigs=4, per=6, size=0.3)
        n_spray += 1
        _spray(bname + "_SprayTip", pts[3], along + up * 0.15, 0.7, bark, bark_d,
               SICK if bname == "BoughR" else pal, par, 100 + n_spray, twigs=6, per=8, size=0.36)
        # espinhos no galho mestre
        for j, t in enumerate((0.25, 0.5, 0.7)):
            c = sample(path, t)["c"]
            d = (along.cross(up) * (1 if j % 2 else -1) + up * 0.5).normalized()
            fera_tip("%s_Thorn%d" % (bname, j), c, c + d * 0.26, 0.04, thorn, par)
        if bname != "BoughC":
            hang_at.append((sample(path, 0.55)["c"], par))
            hang_at.append((sample(path, 0.85)["c"], par))
    # o galho morto: torto, sem folhas, com espinhos e a ponta rachada acesa
    dead = [top + Vector(p) for p in ((0.06, -0.12, -0.3), (0.32, -0.5, 0.45), (0.2, -0.95, 0.9), (0.42, -1.25, 1.3))]
    _bark_tube("DeadBough", dead, 0, 0, bark_d, thorn, crown, sides=9, n=14, radii=[0.2, 0.14, 0.09, 0.03])
    dpath = fera_dense([sec(p, 0.1, 0.1) for p in dead], 16, cut=2)
    for j, (t, dv) in enumerate(((0.45, (0.5, -0.2, 0.6)), (0.62, (-0.55, -0.1, 0.5)), (0.8, (0.35, 0.3, 0.7)))):
        c = sample(dpath, t)["c"]
        e = c + Vector(dv).normalized() * (0.5 - 0.1 * j)
        _bark_tube("DeadTwig%d" % j, [c, c.lerp(e, 0.5) + up * 0.04, e], 0.06, 0.012, bark_d, thorn, crown, sides=6, n=7)
        fera_tip("DeadThorn%d" % j, c, c + Vector((-dv[0], dv[1], 0.5)).normalized() * 0.22, 0.035, thorn, crown)
    fera_curve("DeadVein", [sample(dpath, t)["c"] + Vector((0.0, -0.02, 0.09 - 0.05 * t)) for t in (0.2, 0.4, 0.6, 0.8, 0.97)],
               0.026, 0.01, vein, crown, sides=5)
    # tufos baixos no miolo da copa: fecham o vão entre os galhos mestres
    for k, (dv, ln) in enumerate((((0.5, 0.2, 1.0), 0.75), ((-0.55, 0.15, 1.0), 0.75), ((0.2, -0.45, 1.0), 0.6),
                                  ((-0.15, 0.7, 0.9), 0.7))):
        c = top + Vector((dv[0] * 0.3, dv[1] * 0.3, 0.0))
        d = Vector(dv).normalized()
        e = c + d * ln
        _bark_tube("Inner%d" % k, [c - d * 0.25, c.lerp(e, 0.5), e], 0.13, 0.04, bark, bark_d, crown, sides=8, n=8)
        _spray("InnerSpray%d" % k, e, d, 0.6, bark, bark_d, GREEN if k != 1 else MIX, crown, 300 + k, twigs=6, per=8,
               size=0.34)
    # cipós pendurados nos galhos dos lados (Hang0..Hang3): fio fino com folhas, balança com atraso
    for k, (at, par) in enumerate(hang_at):
        hang = empty("Hang%d" % k, at, par)
        ln = 0.9 + 0.25 * (k % 2)
        pts = [at + up * 0.06, at - up * ln * 0.4 + Vector((0.03, 0.02, 0)), at - up * ln * 0.75 + Vector((-0.02, 0.04, 0)),
               at - up * ln]
        fera_curve("Hang%d_Vine" % k, pts, 0.03, 0.01, moss_d, hang, sides=5)
        _leaves("Hang%d_Leaves" % k, [(pts[0], pts[1]), (pts[1], pts[2]), (pts[2], pts[3])],
                (leaf, leaf_l, leaf_c) if k >= 2 else (leaf, leaf_l, leaf_d), hang, 400 + k, per=3, size=0.24)

    # ---------------- pernas de raiz em dois ossos, continuação do tronco: a coxa sai de dentro da base num
    # colarinho grosso (LegL/LegR, pivô DENTRO do tronco), dobra num nó alongado e a canela abre no pé de raízes
    for side, x in (("LegL", 0.36), ("LegR", -0.36)):
        s = 1 if x > 0 else -1
        leg = empty(side, (x, 0.04, HIP), root)
        knee = Vector((x + s * 0.26, -0.1, 0.64))
        _bark_tube(side + "_Thigh", [Vector((x - s * 0.1, 0.05, HIP + 0.3)), Vector((x + s * 0.1, 0.0, 0.98)), knee],
                   0, 0, bark, bark_d, leg, sides=14, n=14, radii=[0.38, 0.3, 0.24])
        kn = empty("Knee" + side[-1], knee, leg)
        ankle = Vector((x + s * 0.3, -0.02, 0.2))
        _knot(side + "_KneeKnot", knee + Vector((-s * 0.04, 0.0, 0.26)), knee + Vector((s * 0.02, 0.0, -0.28)), 0.27, bark, kn)
        fera_tip(side + "_KneeThorn", knee + Vector((0, -0.2, 0.02)), knee + Vector((0, -0.48, 0.12)), 0.07, thorn, kn)
        _bark_tube(side + "_Shin", [knee + up * 0.05, knee.lerp(ankle, 0.5) + Vector((0, 0.03, 0)), ankle,
                                    ankle + Vector((0, -0.02, -0.19))],
                   0, 0, bark, bark_d, kn, sides=14, n=12, radii=[0.24, 0.22, 0.27, 0.4])
        base = ankle + Vector((0, 0, -0.1))
        for k, (dx, dy, ln) in enumerate(((s * 0.1, -1.0, 0.78), (s * 0.75, -0.62, 0.7), (s * 0.95, 0.25, 0.62),
                                          (s * 0.25, 0.95, 0.66), (-s * 0.6, 0.55, 0.5), (-s * 0.55, -0.6, 0.55))):
            d = Vector((dx, dy, 0)).normalized()
            _bark_tube("%s_Toe%d" % (side, k), [base + d * 0.08, base + d * ln * 0.45 + up * 0.09,
                                                 base + d * ln * 0.8 - up * 0.02, base + d * ln - up * 0.12],
                       0, 0, bark, bark_d, kn, sides=9, n=10, radii=[0.17, 0.13, 0.08, 0.02])
            if k < 3:   # raizinha que sai da raiz
                c = base + d * ln * 0.55 + up * 0.06
                sd = d.cross(up) * (1 if k % 2 else -1)
                fera_curve("%s_ToeFork%d" % (side, k), [c, c + (d + sd).normalized() * 0.16 + up * 0.02,
                                                        c + (d + sd * 1.4).normalized() * 0.32 - up * 0.1],
                           0.05, 0.01, bark_d, kn, sides=5)
        fera_curve(side + "_Vein", [knee + Vector((s * 0.2, -0.12, -0.1)), knee.lerp(ankle, 0.5) + Vector((s * 0.2, -0.1, 0)),
                                    ankle + Vector((s * 0.22, -0.14, 0.02))], 0.024, 0.01, vein, kn, sides=5)

    # ---------------- braços de galho em três ossos, continuação do tronco: colarinho grosso que sai de dentro do
    # ombro (pivô DENTRO do tronco), nó alongado no cotovelo, antebraço que engrossa até o punho e a mão de
    # raízes-garra (HandL/HandR) quase no chão
    for side, x in (("ArmL", 0.5), ("ArmR", -0.5)):
        s = 1 if x > 0 else -1
        arm = empty(side, (s * 0.34, -0.14, 2.82), body)
        elbow = Vector((s * 1.16, -0.14, 1.86))
        _bark_tube(side + "_Upper", [Vector((s * 0.2, -0.14, 2.9)), Vector((s * 0.72, -0.14, 2.72)),
                                     Vector((s * 1.02, -0.14, 2.32)), elbow],
                   0, 0, bark, bark_d, arm, sides=14, n=18, radii=[0.44, 0.36, 0.27, 0.21])
        # ombreira de musgo e um raminho com folhas no ombro
        _rock(side + "_ShoulderMoss", Vector((s * 0.7, -0.12, 3.04)), 0.26, moss, arm, squash=(1.2, 1.0, 0.4), sides=7)
        _spray(side + "_ShoulderSpray", Vector((s * 0.78, -0.08, 3.02)), (s * 0.5, 0.2, 1.0), 0.42, bark, bark_d,
               GREEN if s > 0 else MIX, arm, 500 + s, twigs=3, per=6, size=0.26)
        fera_tip(side + "_ShoulderThorn", Vector((s * 0.9, -0.14, 2.62)), Vector((s * 1.28, -0.1, 2.86)), 0.07, thorn, arm)
        el = empty("Elbow" + side[-1], elbow, arm)
        wrist = Vector((s * 1.26, -0.52, 1.02))
        ud = (wrist - elbow).normalized()
        _knot(side + "_ElbowKnot", elbow - ud * 0.3 + Vector((0, 0.02, 0.08)), elbow + ud * 0.3, 0.24, bark, el)
        fera_tip(side + "_ElbowThorn", elbow + Vector((s * 0.16, 0.12, 0.02)), elbow + Vector((s * 0.36, 0.34, 0.14)),
                 0.07, thorn, el)
        _bark_tube(side + "_Fore", [elbow - ud * 0.05, elbow.lerp(wrist, 0.5) + Vector((s * 0.05, 0, 0)), wrist],
                   0, 0, bark, bark_d, el, sides=14, n=12, radii=[0.2, 0.22, 0.27])
        fera_curve(side + "_Vein", [Vector((s * 0.68, -0.42, 2.62)), Vector((s * 0.96, -0.36, 2.3)),
                                    elbow + Vector((0, -0.2, 0.1)), elbow.lerp(wrist, 0.5) + Vector((0, -0.2, 0))],
                   0.026, 0.01, vein, arm, sides=5)
        c = elbow.lerp(wrist, 0.45)
        fera_tip(side + "_ForeThorn", c + Vector((s * 0.15, 0, 0.05)), c + Vector((s * 0.45, 0.02, 0.2)), 0.055, thorn, el)
        _spray(side + "_ForeSpray", c + Vector((s * 0.1, 0.12, 0.1)), (s * 0.6, 0.6, 0.5), 0.34, bark, bark_d, GREEN, el,
               520 + s, twigs=3, per=4, size=0.22)
        # a mão: palma larga que continua o antebraço e quatro raízes-garra compridas de ponta escura
        hand = empty("Hand" + side[-1], wrist, el)
        knuckle = wrist + ud * 0.32
        sloft(side + "_Palm", fera_dense([sec(wrist - ud * 0.12, 0.26, 0.24), sec(wrist + ud * 0.14, 0.31, 0.22),
                                          sec(knuckle, 0.28, 0.17), sec(knuckle + ud * 0.1, 0.16, 0.1)], 9),
              bark, hand, sides=12, fwd=(0, -1, 0), mats=(bark_d,), matf=lambda i, j: 1 if j % 3 == 0 else 0, sharp=80.0)
        for k, (dx, dy) in enumerate(((s * 0.24, -0.02), (s * 0.09, -0.1), (-s * 0.08, -0.1), (-s * 0.24, 0.0))):
            a = knuckle + Vector((dx, dy * 0.4, 0.02))
            fd = (ud + Vector((dx * 0.9, -0.25, 0))).normalized()
            ln = 0.72 - 0.1 * abs(k - 1.5)
            _bark_tube("%s_Claw%d" % (side, k), [a - fd * 0.06, a + fd * ln * 0.45 + Vector((0, -0.08, 0)),
                                                  a + fd * ln * 0.8 + Vector((0, -0.06, -0.05)),
                                                  a + fd * ln + Vector((0, 0.1, -0.12))],
                       0, 0, bark_d, thorn, hand, sides=8, n=10, stripe=2, radii=[0.1, 0.085, 0.06, 0.012])
        # polegar
        a = wrist + ud * 0.1 + Vector((-s * 0.26, -0.05, 0))
        _bark_tube(side + "_Thumb", [a + Vector((s * 0.06, 0, 0)), a + Vector((-s * 0.2, -0.16, -0.14)),
                                     a + Vector((-s * 0.22, -0.3, -0.38))], 0.09, 0.012, bark_d, thorn, hand, sides=8,
                   n=8, stripe=2)

    loose_parts("thorn_tree")
    export("thorn_tree")


BOSS_BUILDERS = {"thorn_tree": build_thorn_tree}


# ================================================================== ARAUTO DO ABISMO (chefe final, dungeon do Abismo)
# Entidade do vazio (~4,5 m com o halo), alta, encapuzada e meio flutuante: não tem pernas, o manto afina e acaba
# em fiapos de sombra que não tocam o chão. Capuz fundo com uma máscara de osso sem rosto (só uma fenda vertical
# acesa), coroa de pontas quebrada na testa e um halo partido atrás da cabeça, preso por raios a um cubo na nuca.
# No peito, costelas-garra abertas em volta do núcleo de vazio (esfera preta com um anel aceso). Capa rasgada nas
# costas, gola alta de lâminas, ombreiras de placas com espinhos, cinto de placas com um tabardo e amuletos
# pendurados. Braços compridos em três ossos que saem de dentro do tronco: manga rasgada, antebraço nu de quitina
# com bracelete e a mão de garras longas. Frente = -Y.
# Pivôs animados por scripts/enemies/enemy.gd (_animate_herald): Body (no quadril) > Head (capuz e máscara) > Halo
# (gira no próprio eixo), Core (o núcleo, pulsa e gira), Cape (a capa das costas), Sash (tabardo), Charm0/Charm1
# (amuletos), Tatter0..Tatter5 (tiras da barra), Wisp0..Wisp3 (fiapos de sombra), ArmL/ArmR (no ombro, DENTRO do
# tronco) > ElbowL/ElbowR > HandL/HandR, e SleeveL/SleeveR (tiras da manga, dentro de ArmL/ArmR).
HERALD_HIP = 1.7


def _vh_blade(name, pts, widths, out, material, parent, thick=0.028, mats=(), matf=None, n=None):
    """Tira chata de pano (ou lâmina) por uma linha de pontos: larga de lado, fina na direção `out`; `widths` dá
    a meia largura em cada ponto (irregular = rasgada)."""
    secs = [sec(p, w, thick) for p, w in zip(pts, widths)]
    if n:
        secs = fera_dense(secs, n, cut=1)
    return sloft(name, secs, material, parent, sides=8, fwd=out, mats=mats, matf=matf, sharp=70.0)


def _vh_sheet(name, grid, thick, material, parent, mats=(), matf=None):
    """Pano com espessura a partir de uma grade grid[i][j] (linhas de cima para baixo). matf(i, j) -> material."""
    ni, nj = len(grid), len(grid[0])
    G = [[Vector(p) for p in row] for row in grid]

    def nrm(i, j):
        a = G[min(i + 1, ni - 1)][j] - G[max(i - 1, 0)][j]
        b = G[i][min(j + 1, nj - 1)] - G[i][max(j - 1, 0)]
        nn = a.cross(b)
        return nn.normalized() if nn.length > 1e-6 else Vector((0, 0, 1))

    bm = bmesh.new()
    top = [[bm.verts.new(G[i][j]) for j in range(nj)] for i in range(ni)]
    bot = [[bm.verts.new(G[i][j] - nrm(i, j) * thick) for j in range(nj)] for i in range(ni)]
    for i in range(ni - 1):
        for j in range(nj - 1):
            m = matf(i, j) if matf else 0
            bm.faces.new((top[i][j], top[i + 1][j], top[i + 1][j + 1], top[i][j + 1])).material_index = m
            bm.faces.new((bot[i][j + 1], bot[i + 1][j + 1], bot[i + 1][j], bot[i][j])).material_index = m
    rim = ([(i, 0) for i in range(ni)] + [(ni - 1, j) for j in range(1, nj)]
           + [(i, nj - 1) for i in range(ni - 2, -1, -1)] + [(0, j) for j in range(nj - 2, 0, -1)])
    for k in range(len(rim)):
        (i0, j0), (i1, j1) = rim[k], rim[(k + 1) % len(rim)]
        f = bm.faces.new((top[i0][j0], bot[i0][j0], bot[i1][j1], top[i1][j1]))
        f.material_index = matf(min(i0, i1, ni - 2), min(j0, j1, nj - 2)) if matf else 0
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    print("PART", name, "sheet", flush=True)
    bmesh.ops.translate(bm, vec=-_wloc(parent), verts=bm.verts)
    ob = _finish(name, bm, material, parent, smooth=True)
    for m in mats:
        ob.data.materials.append(m)
    smooth_sharp(ob, 50.0)
    return ob


def _vh_loop(name, c, r, tube, axis_u, axis_v, material, parent, a0=0.0, a1=math.tau, n=24, sides=6):
    """Arco (ou anel) de tubo no plano (axis_u, axis_v) em volta de `c`, do ângulo a0 ao a1."""
    u = Vector(axis_u).normalized()
    v = Vector(axis_v)
    v = (v - u * v.dot(u)).normalized()
    c = Vector(c)
    pts = [c + (u * math.cos(a0 + (a1 - a0) * i / n) + v * math.sin(a0 + (a1 - a0) * i / n)) * r for i in range(n + 1)]
    return sloft(name, [sec(p, tube, tube) for p in pts], material, parent, sides=sides, fwd=u.cross(v), sharp=80.0)


def _vh_remap(ob, g, old_w, new_w):
    """Passa todos os descendentes de `ob` pela função g(ponto no mundo) -> ponto no mundo: vértices das malhas e
    posição dos pivôs (a hierarquia só tem translações)."""
    for ch in ob.children:
        co = old_w + Vector(ch.location)
        cn = g(co)
        if ch.type == "MESH":
            for v in ch.data.vertices:
                v.co = g(co + v.co) - cn
        ch.location = cn - new_w
        if "wloc" in ch:
            ch["wloc"] = list(cn)
        _vh_remap(ch, g, co, cn)


HERALD_HEAD = 1.22      # a cabeça (capuz, máscara, coroa, halo) é modelada menor e ampliada no fim
HERALD_STRETCH = 0.45   # a saia do manto (z 0.7..1.7) é esticada este tanto: figura mais alta e esguia
HERALD_SCALE = 0.9      # e o conjunto encolhe para a altura total não mudar


def build_void_herald():
    robe = mat("vh_robe", hexc("#3B2C58"), 0.9)
    robe_d = mat("vh_robe_d", hexc("#211834"), 0.9)
    robe_l = mat("vh_robe_l", hexc("#5C4688"), 0.9)
    lining = mat("vh_lining", hexc("#8E1B45"), 0.85)            # forro carmim da capa e do tabardo
    lining_d = mat("vh_lining_d", hexc("#450B24"), 0.85)
    shadow = mat("vh_shadow", hexc("#08060E"), 1.0)             # fiapos de sombra
    shadow_l = mat("vh_shadow_l", hexc("#2B1747"), 1.0)
    gold = mat("vh_gold", hexc("#B08A45"), 0.45, 0.6)           # ouro velho da coroa, do halo e das placas
    gold_d = mat("vh_gold_d", hexc("#6B5127"), 0.5, 0.6)
    iron = mat("vh_iron", hexc("#4A4658"), 0.55, 0.5)
    bone = mat("vh_bone", hexc("#D9D2C2"), 0.6)                 # a máscara
    bone_d = mat("vh_bone_d", hexc("#9A917F"), 0.65)
    chitin = mat("vh_chitin", hexc("#43355E"), 0.5)             # antebraço e mão
    chitin_l = mat("vh_chitin_l", hexc("#6A5490"), 0.5)
    claw = mat("vh_claw", hexc("#C9C0D8"), 0.35)
    void = mat("vh_void_flat", hexc("#030207"), 1.0)            # o escuro do capuz, do oco do peito e do núcleo
    eye = mat("vh_eye_flat", hexc("#E3123F"), 0.2, 0.0, emit=(0.9, 0.04, 0.2), strength=1.5)
    glow = mat("vh_glow_flat", hexc("#8A2BE2"), 0.3, 0.0, emit=(0.45, 0.1, 0.9), strength=1.5)
    vein = mat("vh_vein", hexc("#B0143F"), 0.4, 0.0, emit=(0.7, 0.03, 0.18), strength=1.2)
    HIP = HERALD_HIP
    up = Vector((0, 0, 1))
    rnd = random.Random(11)

    root = empty("Herald", (0, 0, 0))
    body = empty("Body", (0, 0, HIP), root)

    # ---------------- tronco: manto em sino (barra larga, cintura fina, peito e ombros largos), curvado para a frente
    trunk = fera_dense([sec((0, 0.07, 0.56), 0.2, 0.18), sec((0, 0.07, 0.64), 0.62, 0.56), sec((0, 0.05, 1.1), 0.5, 0.44),
                        sec((0, 0.03, 1.55), 0.36, 0.31), sec((0, 0.0, 1.8), 0.3, 0.26), sec((0, -0.04, 2.1), 0.38, 0.3),
                        sec((0, -0.1, 2.4), 0.45, 0.35), sec((0, -0.14, 2.68), 0.47, 0.37), sec((0, -0.13, 2.86), 0.38, 0.32),
                        sec((0, -0.1, 3.0), 0.2, 0.2)], 30, cut=2)
    sloft("Robe", trunk, robe, body, sides=28, phase=0.0, mats=(robe_d, robe_l),
          matf=lambda i, j: 1 if j % 4 == 1 else (2 if j % 4 == 3 and i < 14 else 0), sharp=80.0)

    def surf(z, deg, out=0.0):
        return _vsurf(trunk, z, deg, out)

    def radial(deg):
        return Vector((math.cos(math.radians(deg)), -math.sin(math.radians(deg)), 0))

    # dobras do manto em relevo: gomos que descem da cintura até a barra, abrindo
    for k in range(12):
        deg = k * 30 + rnd.uniform(-7, 7)
        pts = [surf(z, deg + math.sin(z * 3.0 + k) * 4.0, -0.03) for z in (1.72, 1.4, 1.1, 0.85, 0.66)]
        fera_curve("Fold%d" % k, pts, 0.05, 0.11, robe_l if k % 3 == 0 else robe_d, body, sides=6)
    # barra do manto: debrum carmim gasto
    hem = [surf(0.69, a, 0.01) for a in range(0, 361, 15)]
    sloft("Hem", [sec(p, 0.045, 0.045) for p in hem], lining_d, body, sides=6, fwd=(0, 0, 1), sharp=80.0)

    # tiras rasgadas da barra: doze, as seis dos pivôs (Tatter0..5) mais compridas; cada uma nasce dentro do manto
    for k in range(12):
        deg = k * 30 + 15 + rnd.uniform(-6, 6)
        o = radial(deg)
        top = surf(0.82, deg, -0.05)
        ln = rnd.uniform(0.5, 0.72) if k % 2 == 0 else rnd.uniform(0.3, 0.45)
        w = rnd.uniform(0.13, 0.19)
        pts = [top, top + o * 0.06 - up * ln * 0.35, top + o * 0.12 - up * ln * 0.7 + o.cross(up) * 0.04,
               top + o * 0.1 - up * ln]
        par = empty("Tatter%d" % (k // 2), top, body) if k % 2 == 0 else body
        _vh_blade("TatterCloth%d" % k, pts, [w, w * 0.95, w * rnd.uniform(0.45, 0.7), 0.012], o,
                  robe if k % 4 else robe_d, par, mats=(lining_d,), matf=lambda i, j: 1 if i >= 7 else 0, n=10)
        if k % 2 == 0:   # um fiapo a mais ao lado, mais curto
            sd = o.cross(up) * (0.11 if k % 4 else -0.11)
            _vh_blade("TatterShred%d" % k, [top + sd, top + sd + o * 0.05 - up * ln * 0.45,
                                            top + sd * 1.3 + o * 0.12 - up * ln * 0.8],
                      [0.06, 0.05, 0.008], o, robe_d, par, n=6)

    # ---------------- fiapos de sombra: saem de dentro da barra e descem torcidos sem tocar o chão (Wisp0..3 nos
    # pivôs; os outros quatro, mais curtos, são fixos)
    for k, (deg, ln, r0) in enumerate(((60, 0.6, 0.17), (150, 0.64, 0.18), (240, 0.66, 0.2), (330, 0.6, 0.17),
                                       (0, 0.46, 0.13), (195, 0.44, 0.13), (105, 0.42, 0.12), (285, 0.47, 0.13))):
        o = radial(deg)
        s0 = Vector((0, 0.07, 0.8)) + o * 0.28
        tw = o.cross(up)
        pts = [s0, s0 + o * 0.1 - up * ln * 0.3 + tw * 0.07, s0 + o * 0.04 - up * ln * 0.6 - tw * 0.08,
               s0 + o * 0.13 - up * ln * 0.85 + tw * 0.05, s0 + o * 0.06 - up * ln]
        par = empty("Wisp%d" % k, s0, body) if k < 4 else body
        secs = fera_dense([sec(p, r, r) for p, r in zip(pts, (r0, r0 * 0.9, r0 * 0.6, r0 * 0.34, 0.012))], 14, cut=2)
        sloft("WispMesh%d" % k, secs, shadow, par, sides=8, fwd=(0, 0, 1), mats=(shadow_l,),
              matf=lambda i, j: 1 if (i + j) % 4 == 0 else 0, sharp=80.0)
    # a cauda: o manto por dentro continua num cone torcido de sombra
    tail = [Vector((0, 0.07, 0.82)), Vector((0.05, 0.1, 0.6)), Vector((-0.06, 0.16, 0.4)), Vector((0.03, 0.24, 0.24)),
            Vector((0.0, 0.34, 0.12))]
    sloft("Tail", fera_dense([sec(p, r, r) for p, r in zip(tail, (0.4, 0.3, 0.2, 0.11, 0.015))], 16, cut=2), shadow, body,
          sides=10, fwd=(0, 0, 1), mats=(shadow_l,), matf=lambda i, j: 1 if (i + j * 2) % 5 == 0 else 0, sharp=80.0)

    # ---------------- cinto de placas, tabardo e amuletos
    belt_z = 1.78
    sloft("Belt", [sec(surf(belt_z, a, 0.012), 0.05, 0.075) for a in range(0, 361, 12)], iron, body, sides=6,
          fwd=(0, 0, 1), sharp=60.0)
    for k in range(9):
        deg = 90 + (k - 4) * 34
        c = surf(belt_z, deg, 0.035)
        o = radial(deg)
        w = 0.1 if k != 4 else 0.15
        _vh_blade("BeltPlate%d" % k, [c + up * w * 1.1, c + o * 0.03 + up * w * 0.3, c + o * 0.03 - up * w * 0.5, c - up * w * 1.7],
                  [0.01, w * 0.85, w * 0.7, 0.008], o, gold if k % 2 == 0 else gold_d, body, thick=0.035, mats=(iron,),
                  matf=lambda i, j: 1 if j in (0, 4) else 0)
    fera_tip("BeltFang", surf(belt_z - 0.1, 90, 0.03), surf(belt_z - 0.34, 90, 0.1), 0.06, gold, body)
    sash = empty("Sash", surf(belt_z - 0.06, 90, -0.04), body)
    st = surf(belt_z - 0.02, 90, -0.03)
    f = Vector((0, -1, 0))
    spts = [st, st + f * 0.14 - up * 0.3, st + f * 0.22 - up * 0.62, st + f * 0.26 - up * 0.92, st + f * 0.24 - up * 1.18]
    _vh_blade("SashCloth", spts, [0.2, 0.2, 0.19, 0.17, 0.02], f, lining, sash, thick=0.03, mats=(gold_d, lining_d),
              matf=lambda i, j: 1 if i in (8, 9) else (2 if j in (1, 2, 5, 6) and i < 8 else 0), n=14)
    # runa do tabardo: losango de ouro com um traço aceso
    rc = st + f * 0.235 - up * 0.52
    _rock("SashSigil", rc, 0.1, gold, sash, squash=(1.0, 0.3, 1.5), sides=4)
    fera_curve("SashRune", [rc + f * 0.035 + up * 0.12, rc + f * 0.045, rc + f * 0.035 - up * 0.12], 0.018, 0.018, eye, sash, sides=4)
    for k, deg in enumerate((28, 152)):
        at = surf(belt_z - 0.04, deg, 0.02)
        o = radial(deg)
        ch = empty("Charm%d" % k, at, body)
        ln = 0.62 + 0.14 * k
        fera_curve("CharmCord%d" % k, [at - o * 0.05, at + o * 0.05 - up * ln * 0.5, at + o * 0.06 - up * ln], 0.016, 0.014,
                   gold_d, ch, sides=5)
        e = at + o * 0.06 - up * ln
        sloft("CharmShard%d" % k, [sec(e + up * 0.06, 0.012, 0.012), sec(e - up * 0.03, 0.07, 0.05),
                                   sec(e - up * 0.16, 0.055, 0.04), sec(e - up * 0.34, 0.006, 0.006)],
              glow, ch, sides=5, fwd=(0, -1, 0), mats=(shadow_l,), matf=lambda i, j: 1 if j % 2 else 0, sharp=30.0)

    # ---------------- peito: costelas-garra abertas em volta do oco, e o núcleo de vazio lá dentro
    hc = surf(2.36, 90, -0.05)
    sloft("Hollow", [sec(hc + Vector((0, 0.16, 0)), 0.2, 0.25), sec(hc + Vector((0, -0.005, 0)), 0.25, 0.31),
                     sec(hc + Vector((0, -0.03, 0)), 0.21, 0.27)], void, body, sides=16, fwd=(0, 0, 1), axis=(0, -1, 0))
    for s in (1, -1):
        for k in range(4):
            z = 2.62 - k * 0.17
            a = surf(z, 90 - s * (46 + 3 * k), -0.03)
            m = Vector((s * (0.24 - 0.02 * k), hc.y - 0.11, z - 0.02))
            e = Vector((s * 0.07, hc.y - 0.06, z - 0.05 + (0.04 if k == 0 else 0.0)))
            secs = fera_dense([sec(a, 0.06, 0.06), sec(m, 0.05, 0.05), sec(e, 0.012, 0.012)], 9, cut=2)
            sloft("Rib%s%d" % ("L" if s > 0 else "R", k), secs, bone if k % 2 == 0 else bone_d, body, sides=7,
                  fwd=(0, 0, 1), sharp=80.0)
    # esterno: placa de ouro em cima do oco, com um espinho para baixo
    sc = surf(2.72, 90, 0.0)
    _rock("Sternum", sc, 0.13, gold, body, squash=(1.3, 0.5, 1.0), sides=6)
    fera_tip("SternumFang", sc - up * 0.06, hc + Vector((0, -0.07, 0.2)), 0.05, gold_d, body)
    core = empty("Core", hc, body)
    cc = hc + Vector((0, 0.01, 0.0))
    _blob("CoreVoid", cc, 0.15, 0.15, 0.15, void, core, sides=14, rings=10)
    _vh_loop("CoreRing", cc, 0.165, 0.028, (1, 0, 0.25), (0, 0.5, 1), eye, core, n=22, sides=5)
    _vh_loop("CoreRing2", cc, 0.158, 0.02, (1, 0, -0.5), (0, -0.4, 1), glow, core, n=20, sides=5)
    # veios acesos saindo do oco pelo manto
    for k, pts in enumerate((((2.05, 96), (1.92, 104), (1.82, 99)), ((2.08, 78), (1.95, 66), (1.84, 72)),
                             ((2.5, 128), (2.6, 146), (2.7, 160)), ((2.5, 52), (2.6, 36), (2.72, 22)),
                             ((2.2, 132), (2.1, 152), (1.96, 166), (1.86, 184)), ((2.2, 48), (2.1, 30), (1.98, 12)))):
        fera_curve("Vein%d" % k, [surf(z, d, 0.012) for z, d in pts], 0.026, 0.008, vein, body, sides=5)

    # ---------------- gola alta de lâminas atrás da cabeça e ombreiras de placas com espinhos
    for k in range(7):
        deg = 270 + (k - 3) * 27
        o = radial(deg)
        b = surf(2.78, deg, -0.08)
        h = 0.5 - 0.07 * abs(k - 3) + (0.06 if k % 2 else 0.0)
        pts = [b, b + o * 0.16 + up * h * 0.5, b + o * 0.28 + up * h]
        _vh_blade("Collar%d" % k, pts, [0.15, 0.12, 0.012], o, robe_d if k % 2 else iron, body, thick=0.035,
                  mats=(gold_d,), matf=lambda i, j: 1 if j in (0, 4) else 0, n=8)
    for s in (1, -1):
        nm = "L" if s > 0 else "R"
        for k in range(3):   # três placas sobrepostas, a de cima maior
            c = Vector((s * (0.42 + 0.1 * k), -0.14, 2.86 - 0.1 * k))
            _rock("Pauldron%s%d" % (nm, k), c, 0.22 - 0.03 * k, iron if k != 1 else gold_d, body,
                  squash=(1.2, 1.15, 0.5), sides=6, prof=((-1.0, 0.8), (-0.5, 1.0), (0.2, 0.9), (0.7, 0.55), (1.0, 0.1)))
            _vh_blade("PauldronCrest%s%d" % (nm, k), [c + Vector((0, -0.21 + 0.03 * k, -0.02)), c + Vector((s * 0.03, 0, 0.14 - 0.02 * k)),
                                                       c + Vector((0, 0.21 - 0.03 * k, -0.02))], [0.02, 0.05, 0.02], (s, 0, 0.3),
                      gold if k != 1 else iron, body, thick=0.05)
            fera_tip("PauldronSpike%s%d" % (nm, k), c + Vector((s * 0.1, 0, 0.05)),
                     c + Vector((s * (0.24 + 0.06 * k), 0.04, 0.3 - 0.08 * k)), 0.055, bone_d if k == 0 else iron, body)
        fera_tip("PauldronHorn" + nm, Vector((s * 0.38, -0.02, 2.9)), Vector((s * 0.5, 0.3, 3.36)), 0.075, bone_d, body)
        _vh_loop("PauldronRim" + nm, Vector((s * 0.46, -0.14, 2.8)), 0.25, 0.028, (1, 0, 0), (0, 1, 0), gold, body, n=18, sides=5)

    # ---------------- capa das costas (Cape): pano dos ombros até quase a barra, aberto na frente, com a borda de
    # baixo em pontas rasgadas e o forro carmim nas faixas de baixo
    cape = empty("Cape", (0, 0.18, 2.78), body)
    rows, cols = 9, 15
    grid = []
    for i in range(rows):
        t = i / (rows - 1)
        row = []
        for j in range(cols):
            deg = 168 + 204 * j / (cols - 1)        # de um lado ao outro, passando pelas costas (270)
            o = radial(deg)
            r = 0.5 + 0.2 * t + 0.07 * math.sin(j * 2.6 + t * 2.0) * t
            drop = 2.05 + ((0.34 if j % 2 == 0 else -0.16) if i == rows - 1 else 0.0)
            row.append(Vector((o.x * r * 0.96, o.y * r * 0.86 + 0.16 * t, 2.84 - t * drop)))
        grid.append(row)
    _vh_sheet("CapeCloth", grid, 0.03, robe, cape, mats=(robe_d, lining),
              matf=lambda i, j: 2 if i >= rows - 3 and j % 2 == 0 else (1 if j % 3 == 0 else 0))

    def cape_pt(t, u, out=0.02):
        x, y = t * (rows - 1), u * (cols - 1)
        i, j = min(int(x), rows - 2), min(int(y), cols - 2)
        a, b = grid[i][j].lerp(grid[i][j + 1], y - j), grid[i + 1][j].lerp(grid[i + 1][j + 1], y - j)
        p = a.lerp(b, x - i)
        return p + Vector((p.x, p.y - 0.1, 0)).normalized() * out

    # dobras em relevo descendo a capa e a costura de ouro no alto
    for k, u in enumerate((0.12, 0.26, 0.4, 0.6, 0.74, 0.88)):
        fera_curve("CapeFold%d" % k, [cape_pt(t, u + 0.012 * math.sin(t * 7 + k), 0.0) for t in (0.08, 0.3, 0.52, 0.74, 0.93)],
                   0.035, 0.075, robe_l if k % 2 else robe_d, cape, sides=6)
    fera_curve("CapeSeam", [cape_pt(0.035, u, 0.01) for u in (0.04, 0.2, 0.36, 0.5, 0.64, 0.8, 0.96)], 0.035, 0.035, gold_d,
               cape, sides=5)
    # emblema nas costas: o halo partido bordado em ouro (dois arcos), raios e a fenda acesa no meio
    et, eu = 0.4, 0.5
    for k, (a0, a1) in enumerate(((0.5, 2.9), (3.6, 5.9))):
        pts = [cape_pt(et - math.sin(a0 + (a1 - a0) * i / 12) * 0.13, eu + math.cos(a0 + (a1 - a0) * i / 12) * 0.105, 0.012)
               for i in range(13)]
        sloft("CapeSigil%d" % k, [sec(p, 0.028, 0.028) for p in pts], gold, cape, sides=5, fwd=(0, 1, 0), sharp=80.0)
    for k in range(7):
        a = 0.45 + k * 0.9
        fera_curve("CapeSigilRay%d" % k, [cape_pt(et - math.sin(a) * 0.15, eu + math.cos(a) * 0.12, 0.012),
                                          cape_pt(et - math.sin(a) * (0.2 + 0.03 * (k % 2)), eu + math.cos(a) * (0.16 + 0.025 * (k % 2)), 0.012)],
                   0.022, 0.006, gold_d, cape, sides=4)
    fera_curve("CapeSigilEye", [cape_pt(et - 0.09, eu, 0.014), cape_pt(et, eu, 0.02), cape_pt(et + 0.1, eu, 0.014)], 0.012,
               0.012, eye, cape, sides=4)
    sloft("CapeSigilSlit", [sec(cape_pt(et - 0.085, eu, 0.015), 0.006, 0.01), sec(cape_pt(et - 0.02, eu, 0.02), 0.03, 0.014),
                            sec(cape_pt(et + 0.03, eu, 0.02), 0.026, 0.014), sec(cape_pt(et + 0.1, eu, 0.015), 0.005, 0.01)],
          eye, cape, sides=6, fwd=(0, 1, 0), sharp=80.0)
    for j in (1, 4, 7, 10, 13):   # farrapos soltos pendurados da borda da capa
        p = grid[rows - 1][j]
        o = Vector((p.x, p.y, 0)).normalized()
        _vh_blade("CapeShred%d" % j, [p + up * 0.12, p + o * 0.05 - up * 0.2, p + o * 0.02 - up * 0.46],
                  [0.07, 0.055, 0.008], o, robe_d, cape, n=6)
    # presilhas: a capa sai de baixo das ombreiras
    for s in (1, -1):
        _rock("CapeClasp" + ("L" if s > 0 else "R"), Vector((s * 0.4, -0.05, 2.84)), 0.1, gold, cape,
              squash=(1.0, 1.0, 0.7), sides=6)

    # ---------------- cabeça: capuz fundo com a ponta caída para trás, o escuro lá dentro, a máscara de osso sem
    # rosto com a fenda acesa, a coroa quebrada e o halo partido
    head = empty("Head", (0, -0.1, 2.98), body)
    hood = fera_dense([sec((0, -0.1, 2.9), 0.24, 0.24), sec((0, -0.14, 3.08), 0.36, 0.38), sec((0, -0.16, 3.36), 0.4, 0.43),
                       sec((0, -0.12, 3.6), 0.34, 0.38), sec((0, 0.02, 3.8), 0.2, 0.24), sec((0, 0.22, 3.9), 0.08, 0.1),
                       sec((0, 0.4, 3.84), 0.012, 0.012)], 20, cut=2)
    sloft("Hood", hood, robe, head, sides=20, phase=0.0, mats=(robe_d,), matf=lambda i, j: 1 if j % 5 == 0 else 0,
          sharp=80.0)
    fc = Vector((0, -0.5, 3.3))
    sloft("HoodDark", [sec(fc + Vector((0, 0.2, 0)), 0.24, 0.3), sec(fc + Vector((0, -0.045, 0)), 0.27, 0.35),
                       sec(fc + Vector((0, -0.07, 0)), 0.22, 0.3)], void, head, sides=16, fwd=(0, 0, 1), axis=(0, -1, 0))
    # a beira do capuz: rolo grosso de pano em volta da abertura
    rimp = []
    for i in range(25):
        a = math.tau * i / 24
        rimp.append(fc + Vector((math.cos(a) * 0.3, -0.05 + 0.05 * abs(math.cos(a)), math.sin(a) * 0.39)))
    sloft("HoodRim", [sec(p, 0.07, 0.07) for p in rimp], robe_l, head, sides=7, fwd=(0, -1, 0), sharp=80.0)
    # máscara: escudo comprido de osso, liso, que afina num queixo em ponta abaixo do capuz
    mk = [Vector((0, -0.6, 3.66)), Vector((0, -0.67, 3.52)), Vector((0, -0.7, 3.3)), Vector((0, -0.69, 3.08)),
          Vector((0, -0.65, 2.9)), Vector((0, -0.6, 2.76))]
    sloft("Mask", fera_dense([sec(p, w, 0.07, fr=1.0, bk=0.5) for p, w in
                              zip(mk, (0.06, 0.2, 0.23, 0.2, 0.12, 0.012))], 16, cut=2), bone, head, sides=12,
          fwd=(0, -1, 0), mats=(bone_d,), matf=lambda i, j: 1 if j in (0, 5, 6, 11) else 0, sharp=80.0)
    # a fenda: um corte vertical aceso, comprido, mais largo no meio
    sloft("EyeSocket", [sec(Vector((0, -0.745, 3.52)), 0.012, 0.01), sec(Vector((0, -0.772, 3.33)), 0.075, 0.012),
                        sec(Vector((0, -0.768, 3.14)), 0.066, 0.012), sec(Vector((0, -0.735, 2.92)), 0.01, 0.01)], void, head,
          sides=8, fwd=(0, -1, 0), sharp=80.0)
    sloft("Eye", [sec(Vector((0, -0.755, 3.48)), 0.008, 0.012), sec(Vector((0, -0.782, 3.32)), 0.045, 0.02),
                  sec(Vector((0, -0.778, 3.15)), 0.04, 0.02), sec(Vector((0, -0.745, 2.96)), 0.006, 0.012)], eye, head,
          sides=6, fwd=(0, -1, 0), sharp=80.0)
    # testeira de ouro no alto da máscara e os sulcos entalhados que descem pelas faces até o queixo
    fera_curve("MaskBrow", [Vector((-0.18, -0.7, 3.47)), Vector((-0.09, -0.745, 3.54)), Vector((0, -0.755, 3.58)),
                            Vector((0.09, -0.745, 3.54)), Vector((0.18, -0.7, 3.47))], 0.03, 0.03, gold, head, sides=5)
    fera_tip("MaskBrowFang", Vector((0, -0.75, 3.57)), Vector((0, -0.79, 3.44)), 0.035, gold_d, head)
    for sx in (1, -1):
        fera_curve("MaskGroove" + ("L" if sx > 0 else "R"),
                   [Vector((sx * 0.13, -0.762, 3.42)), Vector((sx * 0.15, -0.752, 3.2)), Vector((sx * 0.1, -0.732, 2.98)),
                    Vector((sx * 0.03, -0.71, 2.88))], 0.016, 0.007, bone_d, head, sides=4)
    # rachaduras e o fio carmim que escorre da fenda
    for k, pts in enumerate((((0.1, -0.752, 3.46), (0.07, -0.768, 3.38), (0.11, -0.755, 3.3)),
                             ((-0.14, -0.735, 3.22), (-0.08, -0.765, 3.14), (-0.1, -0.75, 3.02)))):
        fera_curve("MaskCrack%d" % k, [Vector(p) for p in pts], 0.012, 0.004, iron, head, sides=4)
    fera_curve("MaskTear", [Vector((0, -0.75, 2.98)), Vector((0.005, -0.73, 2.92)), Vector((0.0, -0.705, 2.86))], 0.014,
               0.004, vein, head, sides=4)
    # coroa quebrada: aro na testa do capuz e pontas de alturas diferentes (três partidas, de topo reto)
    cz = 3.62

    def crown_r(deg, out=0.0):
        return _vsurf(hood, cz, deg, out)

    sloft("CrownBand", [sec(crown_r(a, 0.015), 0.035, 0.06) for a in range(0, 361, 12)], gold, head, sides=6,
          fwd=(0, 0, 1), sharp=60.0)
    for k, (deg, h, broken) in enumerate(((90, 0.72, False), (62, 0.52, False), (118, 0.56, False), (34, 0.3, True),
                                          (146, 0.42, False), (6, 0.2, True), (174, 0.34, False))):
        b = crown_r(deg, 0.0)
        o = radial(deg)
        t = b + o * 0.16 + up * h
        if broken:
            sloft("CrownSpike%d" % k, [sec(b - up * 0.04, 0.075, 0.035), sec(b.lerp(t, 0.6), 0.055, 0.028),
                                       sec(b.lerp(t, 0.66), 0.03, 0.02)], gold_d, head, sides=6, fwd=o, sharp=50.0)
        else:
            _vh_blade("CrownSpike%d" % k, [b - up * 0.04, b.lerp(t, 0.5), t], [0.075, 0.055, 0.006], o, gold, head,
                      thick=0.035, mats=(gold_d,), matf=lambda i, j: 1 if j in (0, 4) else 0)
    _rock("CrownGem", crown_r(90, 0.04), 0.06, eye, head, squash=(0.8, 0.6, 1.3), sides=6)
    # halo partido: cubo na nuca preso ao capuz por uma haste; do cubo saem os raios até os arcos do anel
    hub_c = Vector((0, 0.42, 3.5))
    fera_curve("HaloStem", [Vector((0, 0.1, 3.42)), Vector((0, 0.3, 3.47)), hub_c + Vector((0, 0.02, 0))], 0.07, 0.06, iron,
               head, sides=6)
    halo = empty("Halo", hub_c, head)
    _rock("HaloHub", hub_c, 0.1, gold, halo, squash=(1.0, 0.6, 1.0), sides=8)
    _rock("HaloEye", hub_c + Vector((0, -0.06, 0)), 0.06, eye, halo, squash=(1.0, 0.6, 1.0), sides=6)
    HR = 0.74
    for k, (a0, a1) in enumerate(((-0.25, 1.3), (1.78, 3.4), (4.0, 5.2))):
        _vh_loop("HaloArc%d" % k, hub_c, HR, 0.05, (1, 0, 0), (0, 0, 1), gold if k != 2 else gold_d, halo, a0, a1,
                 n=max(6, int((a1 - a0) * 9)), sides=6)
        _vh_loop("HaloGlow%d" % k, hub_c + Vector((0, -0.035, 0)), HR, 0.022, (1, 0, 0), (0, 0, 1), eye, halo,
                 a0 + 0.06, a1 - 0.06, n=max(6, int((a1 - a0) * 9)), sides=4)
        # raios: um ou dois por arco, do cubo até o anel
        for j, t in enumerate((0.5,)):
            a = a0 + (a1 - a0) * t
            d = Vector((math.cos(a), 0, math.sin(a)))
            _vh_blade("HaloSpoke%d_%d" % (k, j), [hub_c + d * 0.08, hub_c + d * HR * 0.55, hub_c + d * (HR + 0.02)],
                      [0.03, 0.014, 0.02], (0, -1, 0), iron, halo, thick=0.016)
        # pontas de sol para fora do arco (as do arco gasto estão quebradas)
        m = max(2, int((a1 - a0) * 2.3))
        for j in range(m):
            a = a0 + (a1 - a0) * (j + 0.5) / m
            d = Vector((math.cos(a), 0, math.sin(a)))
            ln = (0.38 if j % 2 == 0 else 0.2) * (0.5 if k == 2 else 1.0)
            _vh_blade("HaloRay%d_%d" % (k, j), [hub_c + d * (HR - 0.03), hub_c + d * (HR + ln * 0.5), hub_c + d * (HR + ln)],
                      [0.05, 0.035, 0.005], (0, -1, 0), gold, halo, thick=0.022)

    # ---------------- braços em três ossos, continuação do tronco: o ombro nasce DENTRO do manto, a manga larga
    # cobre o braço até o cotovelo e acaba em tiras; o antebraço é quitina nua com bracelete; a mão tem quatro
    # garras compridas e um polegar
    for side, s in (("ArmL", 1), ("ArmR", -1)):
        nm = side[-1]
        sh = Vector((s * 0.29, -0.13, 2.72))
        arm = empty(side, sh, body)
        elbow = Vector((s * 0.76, -0.1, 1.84))
        up_pts = [Vector((s * 0.18, -0.13, 2.76)), Vector((s * 0.48, -0.13, 2.62)), Vector((s * 0.69, -0.12, 2.26)), elbow]
        up_r = (0.26, 0.18, 0.155, 0.2)
        sloft(side + "_Sleeve", fera_dense([sec(p, r, r * 0.92) for p, r in zip(up_pts, up_r)], 16, cut=2),
              robe, arm, sides=14, fwd=(0, -1, 0), mats=(robe_d, robe_l),
              matf=lambda i, j: 1 if j % 4 == 0 else (2 if j % 4 == 2 else 0), sharp=80.0)
        ud = (elbow - up_pts[2]).normalized()
        cu = ud.cross(Vector((0, 1, 0))).normalized()
        # boca da manga: debrum e as tiras rasgadas (SleeveL/R balançam)
        _vh_loop(side + "_Cuff", elbow - ud * 0.02, 0.196, 0.04, cu, (0, 1, 0), lining_d, arm, n=16, sides=5)
        for k in range(6):   # dobras do pano descendo a manga
            a = math.tau * k / 6 + 0.3
            o = (cu * math.cos(a) + Vector((0, 1, 0)) * math.sin(a)).normalized()
            fera_curve("%s_Fold%d" % (side, k), [p + o * r * 0.86 for p, r in zip(up_pts[1:], up_r[1:])], 0.035, 0.07,
                       robe_l if k % 2 else robe_d, arm, sides=5)
        slv = empty("Sleeve" + nm, elbow, arm)
        for k in range(5):
            a = math.tau * k / 5 + 0.4
            o = (cu * math.cos(a) + Vector((0, 1, 0)) * math.sin(a)).normalized()
            b = elbow - ud * 0.1 + o * 0.165
            ln = 0.4 + 0.22 * ((k * 3) % 4) / 3.0
            _vh_blade("%s_Shred%d" % (side, k), [b, b + ud * 0.1 - up * ln * 0.5 + o * 0.03, b + ud * 0.06 - up * ln],
                      [0.11, 0.085, 0.01], o, robe_d if k % 2 else robe, slv, mats=(lining_d,),
                      matf=lambda i, j: 1 if i >= 5 else 0, n=8)
        el = empty("Elbow" + nm, elbow, arm)
        wrist = Vector((s * 0.82, -0.5, 1.0))
        fd = (wrist - elbow).normalized()
        sloft(side + "_ElbowKnot", [sec(elbow - fd * 0.34 + Vector((0, 0.02, 0.1)), 0.07, 0.07), sec(elbow - fd * 0.12, 0.15, 0.14),
                                    sec(elbow + fd * 0.1, 0.14, 0.13), sec(elbow + fd * 0.3, 0.1, 0.1)], chitin, el,
              sides=10, fwd=(0, -1, 0), sharp=80.0)
        fera_tip(side + "_ElbowSpur", elbow + Vector((s * 0.06, 0.08, 0.02)), elbow + Vector((s * 0.2, 0.36, 0.2)), 0.06,
                 bone_d, el)
        fore = [elbow - fd * 0.06, elbow.lerp(wrist, 0.35) + Vector((s * 0.03, 0, 0)), elbow.lerp(wrist, 0.7), wrist]
        sloft(side + "_Fore", fera_dense([sec(p, r, r) for p, r in zip(fore, (0.1, 0.11, 0.09, 0.078))], 12, cut=2),
              chitin, el, sides=10, fwd=(0, -1, 0), mats=(chitin_l,), matf=lambda i, j: 1 if j % 3 == 0 else 0, sharp=80.0)
        # cristas no antebraço e um veio aceso
        for k, t in enumerate((0.25, 0.42, 0.58)):
            c = elbow.lerp(wrist, t)
            fera_tip("%s_ForeFin%d" % (side, k), c + Vector((s * 0.06, 0.05, 0)), c + Vector((s * 0.2, 0.2, 0.12 - 0.02 * k)),
                     0.05, chitin_l, el)
        fera_curve(side + "_Vein", [elbow.lerp(wrist, t) + Vector((0, -0.1 + 0.01 * i, 0.02)) for i, t in
                                    enumerate((0.1, 0.35, 0.6, 0.85))], 0.02, 0.008, vein, el, sides=4)
        # bracelete de ouro com espinho
        bc = elbow.lerp(wrist, 0.8)
        bu = fd.cross(Vector((0, 0, 1))).normalized()
        _vh_loop(side + "_Bracer", bc, 0.105, 0.035, bu, fd.cross(bu), gold, el, n=14, sides=6)
        fera_tip(side + "_BracerSpike", bc + Vector((s * 0.08, 0, 0)), bc + Vector((s * 0.26, 0.04, 0.1)), 0.04, gold_d, el)
        # mão
        hand = empty("Hand" + nm, wrist, el)
        knuckle = wrist + fd * 0.24
        sloft(side + "_Palm", fera_dense([sec(wrist - fd * 0.1, 0.085, 0.08), sec(wrist + fd * 0.1, 0.16, 0.07),
                                          sec(knuckle, 0.17, 0.06), sec(knuckle + fd * 0.07, 0.1, 0.04)], 9), chitin, hand,
              sides=10, fwd=(0, -1, 0), mats=(chitin_l,), matf=lambda i, j: 1 if j % 3 == 0 else 0, sharp=80.0)
        for k, dx in enumerate((s * 0.15, s * 0.055, -s * 0.045, -s * 0.14)):
            a = knuckle + Vector((dx, 0.0, 0.01))
            gd = (fd + Vector((dx * 1.1, -0.22, 0))).normalized()
            ln = 0.5 - 0.06 * abs(k - 1.5)
            pts = [a - gd * 0.05, a + gd * ln * 0.4 + Vector((0, -0.07, 0)), a + gd * ln * 0.75 + Vector((0, -0.07, -0.04)),
                   a + gd * ln + Vector((0, 0.06, -0.12))]
            secs = fera_dense([sec(p, r, r) for p, r in zip(pts, (0.045, 0.04, 0.03, 0.006))], 10, cut=2)
            sloft("%s_Claw%d" % (side, k), secs, chitin, hand, sides=7, fwd=(0, -1, 0), mats=(claw,),
                  matf=lambda i, j: 1 if i >= 5 else 0, sharp=80.0)
        a = wrist + fd * 0.06 + Vector((-s * 0.14, -0.03, 0))
        secs = fera_dense([sec(p, r, r) for p, r in zip(
            [a + Vector((s * 0.05, 0, 0)), a + Vector((-s * 0.14, -0.14, -0.1)), a + Vector((-s * 0.15, -0.26, -0.3))],
            (0.045, 0.036, 0.006))], 8, cut=2)
        sloft(side + "_Thumb", secs, chitin, hand, sides=7, fwd=(0, -1, 0), mats=(claw,),
              matf=lambda i, j: 1 if i >= 4 else 0, sharp=80.0)

    # cabeça maior (em volta do pivô do pescoço), depois a saia esticada e o conjunto reduzido
    hp = _wloc(head)
    _vh_remap(head, lambda q: hp + (q - hp) * HERALD_HEAD, hp, hp)

    def tall(q):
        z = q.z + HERALD_STRETCH * min(1.0, max(0.0, q.z - 0.7))
        return Vector((q.x, q.y, z)) * HERALD_SCALE

    _vh_remap(root, tall, Vector((0, 0, 0)), Vector((0, 0, 0)))
    loose_parts("void_herald")
    export("void_herald")


BOSS_BUILDERS["void_herald"] = build_void_herald
# ================================================================== FORJADOR RÚNICO (chefe das Galerias Profundas)
# Golem antigo de alvenaria e ferro forjado (~4,6 m com as chaminés): tronco de blocos de pedra talhada assentados
# em fiadas (a argamassa escura e as frestas em brasa aparecem entre eles), cintas de ferro rebitadas, uma
# fornalha de fogão no peito (boca funda com carvão aceso, labaredas e porta de grade com dobradiça), três
# chaminés na corcunda, canos da fornalha até elas, disco de runas nas costas, elmo de ferro com viseira acesa
# e queixo de grelha, ombreira de lajes à esquerda e uma bigorna de ombreira à direita, cinto com escarcelas,
# correntes com a tenaz e o martelinho de ferreiro, e o martelo de guerra enorme na mão direita (cabeça de ferro
# com veio derretido, chapa de bater, bico atrás e runas). Runas acesas em âmbar por todo o corpo. Frente = -Y.
# Pivôs animados por scripts/enemies/enemy.gd (_animate_forge): Body (tronco, no quadril), Head (elmo, dentro de
# Body) > Jaw (queixo de grelha), Door (porta da fornalha, na dobradiça), Fire (as labaredas), Lid (tampa da
# chaminé do meio), Stack0..2 (boca de cada chaminé: fumaça e fagulhas), Tasset0..3 e Chain0/Chain1 (penduradas
# no cinto), ArmL/ArmR (no ombro, DENTRO do tronco) > ElbowL/ElbowR > HandL/HandR, Hammer (dentro de HandR) >
# HammerChain, e LegL/LegR (no quadril, dentro do tronco) > KneeL/KneeR.
FORGE_HIP = 1.25
FORGE_GLYPHS = {
    "a": [[(-0.45, -1.0), (-0.45, 1.0), (0.5, 0.35), (-0.45, -0.25)]],
    "b": [[(0.0, -1.0), (0.0, 1.0)], [(-0.6, 0.35), (0.0, 1.0), (0.6, 0.35)]],
    "c": [[(-0.6, 1.0), (0.0, 0.1), (0.6, 1.0)], [(0.0, 0.1), (0.0, -1.0)]],
    "d": [[(-0.5, 1.0), (0.5, 0.0), (-0.5, -1.0)], [(0.5, 1.0), (-0.5, 0.0), (0.5, -1.0)]],
    "e": [[(-0.5, -1.0), (-0.5, 1.0)], [(0.5, -1.0), (0.5, 1.0)], [(-0.5, 0.55), (0.5, -0.25)]],
    "f": [[(-0.3, -1.0), (-0.3, 1.0), (0.45, 0.5), (-0.3, 0.0), (0.45, -0.5), (-0.3, -1.0)]],
}


def _fg_box(name, c, size, material, parent, x=(1, 0, 0), z=(0, 0, 1), bevel=0.02, jitter=0.0, seed=1, taper=1.0):
    """Caixa chanfrada com eixos próprios: `x` = eixo da largura, `z` = eixo da altura (o y sai do produto);
    `taper` afunila o lado +z. Sombreado plano (pedra talhada, chapa de ferro)."""
    zv = Vector(z).normalized()
    xv = Vector(x)
    xv = (xv - zv * xv.dot(zv)).normalized()
    yv = zv.cross(xv).normalized()
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        k = taper if v.co.z > 0 else 1.0
        v.co = Vector((v.co.x * size[0] * k, v.co.y * size[1] * k, v.co.z * size[2]))
    if bevel:
        _bevel(bm, bevel)
    if jitter:
        _jit(bm, jitter, seed)
    _place(bm, c, parent, Matrix((xv, yv, zv)).transposed())
    print("PART", name, "box", flush=True)
    return _finish(name, bm, material, parent)


def _fg_rivets(name, spots, r, material, parent):
    """Rebites: um tronco de cone baixo de 6 lados em cada (ponto, direção para fora); uma malha só."""
    bm = bmesh.new()
    for p, out in spots:
        q = Vector((0, 0, 1)).rotation_difference(Vector(out).normalized())
        M = Matrix.Translation(Vector(p) - _wloc(parent)) @ q.to_matrix().to_4x4()
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=6, radius1=r, radius2=r * 0.55,
                              depth=r * 1.3, matrix=M)
    print("PART", name, "rivets", flush=True)
    return _finish(name, bm, material, parent)


def _fg_strap(name, pts, outs, width, thick, material, parent, sink=0.05):
    """Cinta chata de ferro que segue os pontos `pts` de uma superfície (`outs` = para fora em cada ponto)."""
    bm = bmesh.new()
    rings = []
    n = len(pts)
    for i in range(n):
        p, o = Vector(pts[i]), Vector(outs[i]).normalized()
        along = (Vector(pts[min(i + 1, n - 1)]) - Vector(pts[max(i - 1, 0)])).normalized()
        side = o.cross(along).normalized()
        a, b = p + side * width / 2, p - side * width / 2
        rings.append([bm.verts.new(a - o * sink), bm.verts.new(a + o * thick), bm.verts.new(b + o * thick),
                      bm.verts.new(b - o * sink)])
    for r0, r1 in zip(rings, rings[1:]):
        for j in range(4):
            k = (j + 1) % 4
            bm.faces.new((r0[j], r0[k], r1[k], r1[j]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.translate(bm, vec=-_wloc(parent), verts=bm.verts)
    print("PART", name, "strap", flush=True)
    return _finish(name, bm, material, parent)


def _fg_glyph(name, c, out, size, key, material, parent, up=(0, 0, 1), r=0.03):
    """Runa acesa entalhada numa face que olha para `out`: os traços de FORGE_GLYPHS[key], meio afundados."""
    o = Vector(out).normalized()
    u = Vector(up)
    u = (u - o * u.dot(o)).normalized()
    s = u.cross(o).normalized()
    c = Vector(c) - o * r * 0.35
    for i, stroke in enumerate(FORGE_GLYPHS[key]):
        pts = [c + s * (x * size * 0.5) + u * (y * size * 0.5) for x, y in stroke]
        secs = [sec(p, r, r) for p in pts]
        sloft("%s_%d" % (name, i), secs, material, parent, sides=4, fwd=tuple(o), sharp=20.0)


def _fg_band(name, secs, z0, z1, out, material, parent, sides=14, n=3):
    """Cinta de ferro em volta de um loft vertical: o mesmo contorno, `out` m para fora, entre z0 e z1."""
    rows = []
    for i in range(n):
        s = sec_at(secs, z0 + (z1 - z0) * i / (n - 1))
        rows.append(sec(s["c"], s["rx"] + out, s["ry"] + out))
    return sloft(name, rows, material, parent, sides=sides, phase=0.0, sharp=25.0)


def _fg_chain(prefix, top, n, material, parent, tangent, out, step=0.1):
    """Corrente pendurada: elos chatos alternando de lado, de `top` para baixo. Devolve a ponta de baixo."""
    for i in range(n):
        c = Vector(top) - Vector((0, 0, 0.05 + step * i))
        _fg_box("%s_Link%d" % (prefix, i), c, (0.09, 0.032, 0.14), material, parent,
                x=out if i % 2 == 0 else tangent, bevel=0.012)
    return Vector(top) - Vector((0, 0, 0.05 + step * (n - 1) + 0.06))


def build_forge_golem():
    stone = mat("fr_stone", hexc("#7C7770"), 0.95)
    stone_d = mat("fr_stone_d", hexc("#57534E"), 0.95)
    stone_l = mat("fr_stone_l", hexc("#A39E94"), 0.95)
    mortar = mat("fr_mortar", hexc("#231D1A"), 1.0)
    iron = mat("fr_iron", hexc("#3D414B"), 0.7)
    iron_d = mat("fr_iron_d", hexc("#1F2127"), 0.75)
    iron_l = mat("fr_iron_l", hexc("#767D8B"), 0.6)
    brass = mat("fr_brass", hexc("#B88C3A"), 0.6)
    leather = mat("fr_leather", hexc("#4C2F1F"), 0.9)
    soot = mat("fr_soot_flat", hexc("#0E0908"), 1.0)
    rune = mat("fr_rune_flat", hexc("#FFC04A"), 0.3, 0.0, emit=(1.0, 0.62, 0.12), strength=4.0)
    ember = mat("fr_ember_flat", hexc("#FF6A1E"), 0.3, 0.0, emit=(1.0, 0.32, 0.05), strength=4.5)
    ember_l = mat("fr_ember_l_flat", hexc("#FFD36A"), 0.3, 0.0, emit=(1.0, 0.75, 0.25), strength=5.0)
    crack = mat("fr_crack_flat", hexc("#E0471C"), 0.4, 0.0, emit=(0.95, 0.22, 0.04), strength=2.6)
    STONES = (stone, stone, stone, stone_l, stone_l, stone_d)
    HIP = FORGE_HIP
    up = Vector((0, 0, 1))
    rnd = random.Random(11)

    root = empty("Forge", (0, 0, 0))

    # ---------------- tronco: miolo de argamassa escura (aparece nas juntas) vestido de blocos talhados em fiadas
    body = empty("Body", (0, 0, HIP), root)
    T = [sec((0, 0.05, 0.92), 0.6, 0.5), sec((0, 0.04, 1.25), 0.82, 0.64), sec((0, 0.0, 1.65), 0.88, 0.7),
         sec((0, -0.06, 2.1), 1.0, 0.78), sec((0, -0.14, 2.6), 1.12, 0.84), sec((0, -0.2, 3.0), 1.1, 0.82),
         sec((0, -0.1, 3.3), 0.9, 0.66), sec((0, 0.0, 3.52), 0.5, 0.42)]
    sloft("Core", T, mortar, body, sides=14, phase=0.0, sharp=25.0)

    def surf(z, deg, out=0.0):
        return _vsurf(T, z, deg, out)

    def tout(z, deg):
        s = sec_at(T, z)
        r = math.radians(deg)
        return Vector((math.cos(r) / s["rx"], -math.sin(r) / s["ry"], 0)).normalized()

    row, z = 0, 1.54
    while z < 3.45:
        s = sec_at(T, z)
        circ = math.pi * (s["rx"] + s["ry"])
        n = max(5, int(circ / 0.58))
        for k in range(n):
            deg = (k + 0.5 * (row % 2)) * 360.0 / n
            if 58 < deg < 122 and 1.4 < z < 2.75:
                continue        # a fornalha ocupa o meio do peito
            o = tout(z, deg)
            _fg_box("Block%d_%d" % (row, k), surf(z, deg, rnd.uniform(-0.03, 0.05)),
                    (circ / n * rnd.uniform(0.86, 0.95), 0.32, 0.36 * rnd.uniform(0.82, 0.93)),
                    STONES[rnd.randrange(len(STONES))], body, x=o.cross(up), bevel=0.035, jitter=0.012,
                    seed=row * 40 + k)
        z += 0.36
        row += 1
    # frestas em brasa: o calor da fornalha aparece nas juntas entre as fiadas
    for k, (zc, d0, d1) in enumerate(((2.08, 128, 178), (2.44, 2, 52), (2.8, 196, 252), (2.44, 282, 334),
                                      (1.72, 150, 216), (2.8, 122, 164), (3.16, 18, 72), (1.72, 300, 350),
                                      (3.16, 232, 300), (2.08, 236, 290))):
        pts = [surf(zc, d0 + (d1 - d0) * i / 6.0, 0.075) for i in range(7)]
        fera_curve("Seam%d" % k, pts, 0.04, 0.03, crack, body, sides=4)

    # ---------------- cinto de ferro rebitado, fivela com runa e gola de ferro em volta do pescoço
    _fg_band("Belt", T, 1.08, 1.38, 0.1, iron, body)
    _fg_rivets("BeltRivets", [(surf(1.23, d, 0.1), tout(1.23, d)) for d in range(10, 360, 24)], 0.045, brass, body)
    bk = surf(1.23, 90, 0.06)
    limb("Buckle", bk, bk + Vector((0, -0.14, 0)), 0.27, 0.23, brass, sides=8, parent=body)
    _fg_glyph("BuckleRune", bk + Vector((0, -0.14, 0)), (0, -1, 0), 0.26, "b", rune, body)
    _fg_band("Gorget", T, 3.34, 3.5, 0.2, iron, body)
    _fg_rivets("GorgetRivets", [(surf(3.42, d, 0.2), tout(3.42, d)) for d in range(150, 400, 30)], 0.04, brass, body)
    # cintas de ferro subindo dos lados da fornalha até a gola
    for s in (1, -1):
        degs = 90 - s * 40
        zs = [1.36 + (3.36 - 1.36) * i / 9.0 for i in range(10)]
        _fg_strap("Strap%s" % ("L" if s > 0 else "R"), [surf(zz, degs, 0.19) for zz in zs], [tout(zz, degs) for zz in zs],
                  0.2, 0.045, iron, body)
        _fg_rivets("StrapRivets%s" % ("L" if s > 0 else "R"),
                   [(surf(zz, degs, 0.235), tout(zz, degs)) for zz in zs[1:-1:2]], 0.04, iron_l, body)

    # ---------------- a fornalha: caixa de fogão de ferro cravada no peito, boca funda de fuligem, carvão aceso,
    # labaredas (Fire) e a porta de grade na dobradiça (Door)
    fz, fy = 2.08, -1.06

    def fsec(y, r):
        return sec((0, y, fz), r, r, sq=3.5)

    sloft("Firebox", [fsec(-0.5, 0.52), fsec(fy + 0.04, 0.52), fsec(fy, 0.47), fsec(fy - 0.004, 0.4), fsec(-0.72, 0.37)],
          iron, body, sides=20, fwd=(0, 0, 1), axis=(0, -1, 0), caps=(False, True), mats=(soot,),
          matf=lambda i, j: 1 if i >= 3 else 0, sharp=30.0)
    spots = []
    for i in range(16):
        a = math.tau * (i + 0.5) / 16
        e = 2.0 / 3.5
        x = 0.52 * math.copysign(abs(math.cos(a)) ** e, math.cos(a))
        zz = 0.52 * math.copysign(abs(math.sin(a)) ** e, math.sin(a))
        spots.append((Vector((x, fy + 0.13, fz + zz)), Vector((x, 0, zz))))
    _fg_rivets("FireboxRivets", spots, 0.04, brass, body)
    for k, (x, y, zz, r) in enumerate(((-0.2, -0.86, 1.76, 0.13), (0.03, -0.9, 1.75, 0.14), (0.22, -0.84, 1.77, 0.12),
                                       (-0.1, -0.8, 1.86, 0.12), (0.13, -0.8, 1.87, 0.11), (0.0, -0.96, 1.74, 0.1),
                                       (-0.27, -0.94, 1.75, 0.09), (0.28, -0.95, 1.75, 0.09), (0.02, -0.78, 1.96, 0.1))):
        _rock("Coal%d" % k, (x, y, zz), r, (ember, ember_l, iron_d)[k % 3], body, sides=6)
    fire = empty("Fire", (0, -0.86, 1.8), body)
    for k, (x, y, h, r) in enumerate(((-0.16, -0.84, 0.42, 0.1), (0.04, -0.88, 0.58, 0.12), (0.2, -0.83, 0.38, 0.09),
                                      (-0.05, -0.8, 0.5, 0.08), (0.12, -0.92, 0.3, 0.07))):
        fera_tip("Flame%d" % k, Vector((x, y, 1.82)), Vector((x * 0.7, y + 0.03, 1.82 + h)), r,
                 ember_l if k % 2 else ember, fire, sides=5)
    door = empty("Door", (0.45, fy - 0.03, fz), body)
    loop = []
    for i in range(25):
        a = math.tau * i / 24
        e = 2.0 / 3.5
        loop.append(Vector((0.435 * math.copysign(abs(math.cos(a)) ** e, math.cos(a)), fy - 0.035,
                            fz + 0.435 * math.copysign(abs(math.sin(a)) ** e, math.sin(a)))))
    fera_curve("DoorFrame", loop, 0.04, 0.04, iron_l, door, sides=5)
    for k, x in enumerate((-0.27, -0.135, 0.0, 0.135, 0.27)):
        h = 0.42 if abs(x) < 0.2 else 0.39
        limb("DoorBar%d" % k, (x, fy - 0.035, fz - h), (x, fy - 0.035, fz + h), 0.028, 0.028, iron_d, sides=6, parent=door)
    limb("DoorCross", (-0.43, fy - 0.04, fz), (0.43, fy - 0.04, fz), 0.03, 0.03, iron_l, sides=6, parent=door)
    for k, dz in enumerate((-0.24, 0.24)):
        limb("DoorHinge%d" % k, (0.47, fy - 0.03, fz + dz - 0.07), (0.47, fy - 0.03, fz + dz + 0.07), 0.05, 0.05, brass,
             sides=8, parent=door)
    _fg_box("DoorLatch", (-0.46, fy - 0.045, fz), (0.14, 0.05, 0.09), brass, door, bevel=0.015)
    # pedra-chave de ferro com a runa mestra, em cima da boca
    kc = Vector((0, surf(2.82, 90, 0.0).y - 0.06, 2.82))
    _fg_box("Keystone", kc, (0.56, 0.3, 0.38), iron_l, body, z=(0, 0, -1), taper=0.72, bevel=0.03)
    _fg_glyph("KeystoneRune", kc + Vector((0, -0.15, 0)), (0, -1, 0), 0.26, "d", rune, body)

    # ---------------- chaminés na corcunda (Stack0..2 = a boca de cada uma), a tampa que bate (Lid) e os canos
    # que sobem da fornalha por cima dos ombros
    for k, (x, y, z0, z1, r) in enumerate(((0.44, 0.22, 3.0, 4.28, 0.17), (-0.42, 0.28, 3.0, 4.0, 0.16),
                                           (0.0, 0.46, 2.9, 4.62, 0.2))):
        nm = "Stack%d" % k
        limb(nm + "_Pipe", (x, y, z0), (x, y, z1), r, r * 0.92, iron_d, sides=10, parent=body)
        for j, t in enumerate((0.55, 0.8)):
            zz = z0 + (z1 - z0) * t
            limb("%s_Ring%d" % (nm, j), (x, y, zz - 0.04), (x, y, zz + 0.04), r + 0.03, r + 0.03, iron_l, sides=10,
                 parent=body)
        limb(nm + "_Flare", (x, y, z1 - 0.06), (x, y, z1 + 0.1), r * 0.92, r * 1.3, iron, sides=10, parent=body)
        limb(nm + "_Mouth", (x, y, z1 + 0.06), (x, y, z1 + 0.105), r * 1.1, r * 1.12, soot, sides=10, parent=body)
        limb(nm + "_Glow", (x, y, z1 + 0.02), (x, y, z1 + 0.108), r * 0.7, r * 0.72, ember, sides=8, parent=body)
        empty(nm, (x, y, z1 + 0.12), body)
        if k == 2:
            lid = empty("Lid", (x, y + r * 1.3, z1 + 0.12), body)
            limb("Lid_Plate", (x, y, z1 + 0.13), (x, y, z1 + 0.18), r * 1.36, r * 1.2, iron, sides=10, parent=lid)
            _fg_box("Lid_Hinge", (x, y + r * 1.3, z1 + 0.1), (0.14, 0.1, 0.12), brass, lid, bevel=0.015)
            _fg_rivets("Lid_Knob", [(Vector((x, y, z1 + 0.19)), up)], 0.06, brass, lid)
    for s in (1, -1):
        pts = [Vector((s * 0.4, -0.8, 2.5)), surf(2.78, 90 - s * 36, 0.27), surf(3.08, 90 - s * 44, 0.29),
               surf(3.36, 90 - s * 60, 0.3), Vector((s * 0.56, -0.05, 3.74)), Vector((s * 0.44, 0.2, 3.6))]
        fera_curve("Flue%s" % ("L" if s > 0 else "R"), pts, 0.085, 0.085, iron_d, body, sides=7)
        _fg_rivets("FlueJoint%s" % ("L" if s > 0 else "R"), [(pts[2], tout(3.08, 90 - s * 44))], 0.13, brass, body)
    # disco de runas nas costas: chapa de ferro, aro de rebites e seis runas em roda da runa do meio
    bc = Vector((0, surf(2.55, 270, 0.0).y, 2.55))
    limb("BackDisc", bc + Vector((0, -0.1, 0)), bc + Vector((0, 0.26, 0)), 0.56, 0.5, iron, sides=12, parent=body)
    face_y = bc.y + 0.26
    _fg_rivets("BackDiscRivets", [(Vector((math.cos(a) * 0.43, face_y, bc.z + math.sin(a) * 0.43)), (0, 1, 0))
                                  for a in [math.tau * i / 12 for i in range(12)]], 0.04, brass, body)
    for i, key in enumerate("acebfd"):
        a = math.tau * i / 6 + 0.5
        _fg_glyph("BackRune%d" % i, Vector((math.cos(a) * 0.27, face_y, bc.z + math.sin(a) * 0.27)), (0, 1, 0), 0.15, key,
                  rune, body, up=(math.cos(a), 0, math.sin(a)), r=0.022)
    limb("BackBoss", bc + Vector((0, 0.24, 0)), bc + Vector((0, 0.32, 0)), 0.12, 0.09, ember, sides=8, parent=body)

    # ---------------- elmo: cúpula de ferro facetada que sai da frente do alto do peito, viseira em fenda com os
    # olhos acesos, sobrancelha e nasal, crista de latão e o queixo de grelha em brasa (Jaw)
    head = empty("Head", (0, -0.7, 3.2), body)
    sloft("Helm", [sec((0, -0.86, 2.92), 0.3, 0.3), sec((0, -0.92, 3.08), 0.37, 0.37), sec((0, -0.92, 3.36), 0.37, 0.38),
                   sec((0, -0.9, 3.54), 0.31, 0.32), sec((0, -0.88, 3.66), 0.13, 0.13)], iron, head, sides=8,
          sharp=25.0)
    _fg_box("Visor", (0, -1.26, 3.3), (0.56, 0.1, 0.11), soot, head, bevel=0.01)
    for s in (1, -1):
        _fg_box("Eye%s" % ("L" if s > 0 else "R"), (s * 0.14, -1.3, 3.3), (0.15, 0.06, 0.065), rune, head,
                x=(1, 0, s * 0.22), bevel=0.01)
        _fg_rivets("Cheek%s" % ("L" if s > 0 else "R"), [(Vector((s * 0.33, -1.08, 3.14)), (s, -0.6, 0)),
                                                         (Vector((s * 0.33, -1.08, 3.44)), (s, -0.6, 0))], 0.045,
                   brass, head)
    _fg_box("Brow", (0, -1.25, 3.42), (0.7, 0.2, 0.11), iron_l, head, bevel=0.02)
    _fg_box("Nasal", (0, -1.29, 3.22), (0.1, 0.1, 0.36), iron_l, head, bevel=0.02)
    _fg_box("Crest", (0, -0.9, 3.66), (0.09, 0.72, 0.26), brass, head, z=(0, -0.25, 1), taper=0.55, bevel=0.02)
    jaw = empty("Jaw", (0, -1.0, 3.04), head)
    _fg_box("JawMesh", (0, -1.16, 2.98), (0.52, 0.3, 0.22), iron_d, jaw, bevel=0.03)
    _fg_box("JawGlow", (0, -1.31, 2.99), (0.38, 0.04, 0.13), ember, jaw, bevel=0.0)
    for k, x in enumerate((-0.15, -0.05, 0.05, 0.15)):
        _fg_box("JawBar%d" % k, (x, -1.325, 2.99), (0.045, 0.05, 0.2), iron_l, jaw, bevel=0.01)

    # ---------------- escarcelas (Tasset0..3) e as correntes do cinto com as ferramentas (Chain0: tenaz;
    # Chain1: martelinho de ferreiro)
    for k, deg in enumerate((62, 118, 242, 298)):
        o = tout(1.12, deg)
        tan = o.cross(up)
        piv = surf(1.12, deg, 0.12)
        ts = empty("Tasset%d" % k, piv, body)
        c = piv + Vector((0, 0, -0.27))
        _fg_box("Tasset%d_Plate" % k, c, (0.4, 0.07, 0.58), iron, ts, x=tan, z=(0, 0, -1), taper=0.7, bevel=0.02)
        _fg_box("Tasset%d_Trim" % k, c + Vector((0, 0, -0.27)) + o * 0.01, (0.3, 0.09, 0.07), brass, ts, x=tan, bevel=0.015)
        _fg_rivets("Tasset%d_Rivets" % k, [(c + tan * sx * 0.13 + Vector((0, 0, 0.2)) + o * 0.035, o) for sx in (-1, 1)],
                   0.035, brass, ts)
        if k < 2:
            _fg_glyph("Tasset%d_Rune" % k, c + o * 0.035 + Vector((0, 0, -0.04)), o, 0.2, "ac"[k], rune, ts, r=0.022)
    for k, deg in enumerate((30, 150)):
        o = tout(1.14, deg)
        tan = o.cross(up)
        piv = surf(1.14, deg, 0.14)
        ch = empty("Chain%d" % k, piv, body)
        end = _fg_chain("Chain%d" % k, piv, 5, iron_l, ch, tan, o)
        if k == 0:      # tenaz: duas hastes cruzadas num rebite, bocas abertas embaixo
            for j, sx in enumerate((-1, 1)):
                _fg_box("Tongs%d" % j, end + Vector((0, 0, -0.2)), (0.04, 0.035, 0.52), iron_d, ch, x=tan,
                        z=Vector((0, 0, 1)) + tan * sx * 0.16, bevel=0.01)
            _fg_rivets("TongsPin", [(end + Vector((0, 0, -0.2)) + o * 0.02, o)], 0.035, brass, ch)
        else:           # martelinho: cabo e cabeça
            _fg_box("Mallet_Shaft", end + Vector((0, 0, -0.18)), (0.045, 0.045, 0.46), leather, ch, x=tan, bevel=0.01)
            _fg_box("Mallet_Head", end + Vector((0, 0, -0.4)), (0.24, 0.1, 0.11), iron_l, ch, x=tan, bevel=0.02)

    # ---------------- pernas em dois ossos, continuação da base: coxa de pedra que sai de dentro do tronco
    # (LegL/LegR, pivô DENTRO do tronco), coxote de ferro, joelheira pontuda (no KneeL/KneeR), greva de ferro
    # e o pé de laje com biqueira rebitada
    for nm, s in (("L", 1), ("R", -1)):
        leg = empty("Leg" + nm, (s * 0.45, 0.04, HIP), root)
        knee = Vector((s * 0.58, -0.1, 0.76))
        sloft("Leg%s_Thigh" % nm, fera_dense([sec((s * 0.4, 0.04, 1.44), 0.45, 0.45), sec((s * 0.5, -0.02, 1.06), 0.41, 0.41),
                                             sec(knee, 0.35, 0.35)], 7, cut=1), stone, leg, sides=8, sharp=25.0)
        _fg_box("Leg%s_Cuisse" % nm, (s * 0.52, -0.4, 1.06), (0.56, 0.14, 0.5), iron, leg, z=(0, 0.16, 1), bevel=0.03)
        _fg_rivets("Leg%s_CuisseRivets" % nm, [(Vector((s * 0.52 + dx, -0.5, 1.06 + dz)), (0, -1, 0.1))
                                              for dx in (-0.2, 0.2) for dz in (-0.17, 0.17)], 0.035, brass, leg)
        kn = empty("Knee" + nm, knee, leg)
        ankle = Vector((s * 0.6, 0.02, 0.28))
        sloft("Leg%s_Shin" % nm, [sec(knee + Vector((0, 0, 0.14)), 0.33, 0.33), sec(knee.lerp(ankle, 0.5), 0.37, 0.37),
                                  sec(ankle, 0.43, 0.43), sec(ankle + Vector((0, 0, -0.16)), 0.47, 0.47)], iron_d, kn,
              sides=8, sharp=25.0)
        for j, t in enumerate((0.3, 0.75)):
            c = knee.lerp(ankle, t)
            r = 0.37 + 0.08 * t
            limb("Leg%s_Greave%d" % (nm, j), c + Vector((0, 0, -0.05)), c + Vector((0, 0, 0.05)), r + 0.03, r + 0.03,
                 iron_l, sides=8, parent=kn)
        _fg_box("Leg%s_KneeCop" % nm, knee + Vector((0, -0.3, 0.02)), (0.5, 0.22, 0.46), iron_l, kn, z=(0, -0.2, 1),
                taper=0.7, bevel=0.03)
        fera_tip("Leg%s_KneeSpike" % nm, knee + Vector((0, -0.36, 0.06)), knee + Vector((0, -0.7, 0.2)), 0.1, brass, kn,
                 sides=4)
        _fg_box("Leg%s_Foot" % nm, (s * 0.6, -0.14, 0.14), (0.84, 1.1, 0.28), stone_d, kn, bevel=0.05, jitter=0.01, seed=5)
        _fg_box("Leg%s_ToeCap" % nm, (s * 0.6, -0.56, 0.17), (0.9, 0.36, 0.34), iron, kn, bevel=0.04)
        _fg_rivets("Leg%s_ToeRivets" % nm, [(Vector((s * 0.6 + dx, -0.75, 0.2)), (0, -1, 0.2)) for dx in (-0.3, 0.0, 0.3)],
                   0.04, brass, kn)
        _fg_box("Leg%s_Heel" % nm, (s * 0.6, 0.36, 0.2), (0.6, 0.3, 0.4), iron_d, kn, bevel=0.04)

    # ---------------- braços em três ossos, continuação do tronco: o braço de pedra sai de dentro do ombro (pivô
    # DENTRO do tronco) com a ombreira em cima, cotoveleira só por trás da dobra, antebraço de manopla de ferro
    # com a lápide de runa, e a mão (HandL aberta em garra; HandR fechada no cabo do martelo)
    hand_r = None
    grip = None
    for nm, s in (("L", 1), ("R", -1)):
        arm = empty("Arm" + nm, (s * 0.8, -0.18, 2.95), body)
        elbow = Vector((s * 1.66, -0.2, 2.02))
        upper = fera_dense([sec((s * 0.75, -0.18, 2.98), 0.5, 0.5), sec((s * 1.22, -0.18, 2.9), 0.46, 0.46),
                            sec((s * 1.56, -0.19, 2.5), 0.38, 0.38), sec(elbow, 0.32, 0.32)], 9, cut=1)
        sloft("Arm%s_Upper" % nm, upper, stone, arm, sides=8, sharp=25.0)
        for j, t in enumerate((0.62, 0.86)):
            a, b = sample(upper, t - 0.04), sample(upper, t + 0.04)
            limb("Arm%s_Band%d" % (nm, j), a["c"], b["c"], a["rx"] + 0.035, b["rx"] + 0.035, iron, sides=8, parent=arm)
        # lajes de pedra assentadas no braço (por fora, na frente e atrás): relevo de alvenaria, não tubo liso
        for j, (t, face) in enumerate(((0.3, 0), (0.5, 0), (0.74, 0), (0.4, 1), (0.66, 1), (0.4, 2), (0.66, 2))):
            c0 = sample(upper, t)
            d = (sample(upper, t + 0.05)["c"] - sample(upper, t - 0.05)["c"]).normalized()
            nrm = d.cross(Vector((0, 1, 0)))
            if nrm.dot(Vector((s, 0, 1))) < 0:
                nrm = -nrm
            nrm = (nrm, Vector((0, -1, 0)), Vector((0, 1, 0)))[face]
            _fg_box("Arm%s_Slab%d" % (nm, j), c0["c"] + nrm * c0["rx"] * 0.86, (0.34, c0["rx"] * 1.25, 0.2),
                    STONES[(j * 2 + (0 if s > 0 else 3)) % len(STONES)], arm, x=d, z=nrm, bevel=0.03, jitter=0.012,
                    seed=60 + j)
        if s > 0:   # ombreira de lajes: duas pedras empilhadas, cinta de ferro e a runa em cima
            tilt = Vector((0.32, 0, 1))
            _fg_box("PauldronL_Slab", (1.3, -0.18, 3.36), (1.05, 1.0, 0.3), stone_l, arm, z=tilt, bevel=0.05, jitter=0.012,
                    seed=3)
            _fg_box("PauldronL_Top", (1.3, -0.18, 3.58), (0.7, 0.68, 0.22), stone, arm, z=tilt, bevel=0.04, jitter=0.01,
                    seed=4)
            _fg_box("PauldronL_Rim", (1.36, -0.18, 3.33), (1.1, 1.05, 0.1), iron, arm, z=tilt, bevel=0.02)
            tn = tilt.normalized()
            _fg_glyph("PauldronL_Rune", Vector((1.3, -0.18, 3.58)) + tn * 0.11, tn, 0.36, "e", rune, arm, up=(0, -1, 0))
            _fg_rivets("PauldronL_Rivets", [(Vector((1.36 + dx * 0.5, -0.18 + dy * 0.48, 3.33 - dx * 0.16)) + tn * 0.05, tn)
                                            for dx in (-1, 1) for dy in (-1, 1)], 0.05, brass, arm)
        else:       # bigorna de ombreira: pé, cintura, mesa e o chifre para fora
            _fg_box("Anvil_Foot", (-1.26, -0.18, 3.36), (0.86, 0.64, 0.18), iron_d, arm, bevel=0.03)
            _fg_box("Anvil_Waist", (-1.26, -0.18, 3.54), (0.5, 0.36, 0.24), iron_d, arm, bevel=0.03)
            _fg_box("Anvil_Face", (-1.3, -0.18, 3.73), (1.0, 0.5, 0.2), iron, arm, bevel=0.03)
            _fg_box("Anvil_Plate", (-1.3, -0.18, 3.84), (0.9, 0.44, 0.04), iron_l, arm, bevel=0.01)
            fera_tip("Anvil_Horn", Vector((-1.74, -0.18, 3.73)), Vector((-2.34, -0.18, 3.8)), 0.2, iron_l, arm, sides=8)
            _fg_glyph("Anvil_Rune", Vector((-1.26, -0.36, 3.54)), (0, -1, 0), 0.17, "c", rune, arm, r=0.022)
        el = empty("Elbow" + nm, elbow, arm)
        wrist = Vector((s * 1.7, -0.62, 1.12))
        ud = (wrist - elbow).normalized()
        sloft("Arm%s_Fore" % nm, [sec(elbow - ud * 0.14, 0.3, 0.3), sec(elbow.lerp(wrist, 0.5), 0.37, 0.37),
                                  sec(wrist, 0.43, 0.43)], iron, el, sides=8, sharp=25.0)
        for j, t in enumerate((0.34, 0.9)):
            c = elbow.lerp(wrist, t)
            r = 0.33 + 0.11 * t
            limb("Arm%s_Cuff%d" % (nm, j), c - ud * 0.05, c + ud * 0.05, r + 0.035, r + 0.035, iron_l, sides=8, parent=el)
        _fg_box("Arm%s_Cop" % nm, elbow + Vector((0, 0.27, 0.0)), (0.42, 0.24, 0.52), iron_l, el, bevel=0.04)
        fera_tip("Arm%s_CopSpike" % nm, elbow + Vector((0, 0.34, 0.0)), elbow + Vector((0, 0.7, 0.1)), 0.11, brass, el,
                 sides=4)
        tc = elbow.lerp(wrist, 0.62) + Vector((s * 0.37, 0, 0))
        _fg_box("Arm%s_Tablet" % nm, tc, (0.1, 0.34, 0.5), stone_l, el, z=ud * -1.0, x=(1, 0, 0), bevel=0.02)
        _fg_glyph("Arm%s_Rune" % nm, tc + Vector((s * 0.05, 0, 0)), (s, 0, 0), 0.26, "f" if s > 0 else "a", rune, el,
                  up=tuple(-ud), r=0.024)
        hand = empty("Hand" + nm, wrist, el)
        fd = (ud + Vector((0, -0.5, 0))).normalized()     # os dedos apontam para baixo e para a frente
        if s > 0:
            pc = wrist + ud * 0.24
            _fg_box("HandL_Palm", pc, (0.52, 0.4, 0.44), iron_d, hand, z=-ud, bevel=0.04)
            for k, dx in enumerate((-0.18, 0.0, 0.18)):
                b = pc + ud * 0.2 + Vector((dx, -0.08, 0))
                _fg_box("HandL_Finger%d" % k, b + fd * 0.12, (0.15, 0.17, 0.34), iron, hand, z=-fd, bevel=0.025)
                tip = b + fd * 0.3 + Vector((0, 0.08, -0.12))
                _fg_box("HandL_Tip%d" % k, tip, (0.13, 0.15, 0.28), iron_l, hand, z=Vector((0, -0.5, 1)), taper=0.6,
                        bevel=0.02, x=(1, 0, 0))
            _fg_box("HandL_Thumb", pc + Vector((-0.3, -0.1, -0.06)), (0.15, 0.17, 0.34), iron, hand, z=Vector((0.5, 0.3, 1)),
                    bevel=0.025)
        else:
            grip = wrist + ud * 0.3
            hand_r = hand
            _fg_box("HandR_Fist", grip, (0.56, 0.52, 0.48), iron_d, hand, z=-ud, bevel=0.05)
            for k in range(4):
                _fg_box("HandR_Knuckle%d" % k, grip + Vector((0, -0.27, 0.16 - 0.11 * k)), (0.5, 0.14, 0.1), iron, hand,
                        bevel=0.02)
            _fg_box("HandR_Thumb", grip + Vector((0.2, -0.3, 0.02)), (0.16, 0.16, 0.36), iron_l, hand, z=(0.3, 0, 1),
                    bevel=0.025)

    # ---------------- o martelo de guerra (Hammer, dentro de HandR): cabo de ferro com empunhadura de couro e
    # colares de latão, cabeça em dois blocos com o veio derretido no meio, chapa de bater rebitada com runa,
    # bico atrás, e a corrente do pomo (HammerChain)
    ham = empty("Hammer", grip, hand_r)
    A = Vector((-0.05, -0.11, 1.0)).normalized()
    butt = grip - A * 0.74
    hc = grip + A * 3.0
    xv = Vector((1, 0, 0))
    xv = (xv - A * xv.dot(A)).normalized()
    yv = A.cross(xv).normalized()      # para trás (+Y); a frente da cabeça é -yv
    limb("Hammer_Shaft", butt, hc, 0.085, 0.085, iron_d, sides=8, parent=ham)
    for k, t in enumerate((-0.36, 0.36, 0.52, 0.68)):
        c = grip + A * t
        limb("Hammer_Wrap%d" % k, c - A * 0.06, c + A * 0.06, 0.105, 0.105, leather, sides=8, parent=ham)
    limb("Hammer_Collar", hc - A * 0.56, hc - A * 0.36, 0.12, 0.17, brass, sides=8, parent=ham)
    limb("Hammer_Pommel", butt + A * 0.1, butt - A * 0.06, 0.13, 0.07, brass, sides=8, parent=ham)
    _fg_box("Hammer_Seam", hc, (0.56, 0.3, 0.6), ember, ham, x=xv, z=A, bevel=0.0)
    _fg_box("Hammer_Front", hc - yv * 0.34, (0.7, 0.5, 0.76), iron, ham, x=xv, z=A, bevel=0.05)
    _fg_box("Hammer_Back", hc + yv * 0.32, (0.66, 0.44, 0.7), iron, ham, x=xv, z=A, bevel=0.05)
    for k, sy in enumerate((-0.11, 0.1)):
        _fg_box("Hammer_Hoop%d" % k, hc + yv * sy, (0.75, 0.07, 0.8), iron_l, ham, x=xv, z=A, bevel=0.012)
    _fg_box("Hammer_Strike", hc - yv * 0.63, (0.8, 0.14, 0.86), iron_l, ham, x=xv, z=A, bevel=0.03)
    _fg_rivets("Hammer_StrikeRivets", [(hc - yv * 0.7 + xv * sx * 0.31 + A * sz * 0.34, -yv) for sx in (-1, 1)
                                       for sz in (-1, 1)], 0.05, brass, ham)
    _fg_glyph("Hammer_RuneFace", hc - yv * 0.7, -yv, 0.42, "d", rune, ham, up=tuple(A), r=0.034)
    fera_tip("Hammer_Pick", hc + yv * 0.5, hc + yv * 1.12 - A * 0.08, 0.24, iron_l, ham, sides=4)
    for k, (o, key) in enumerate(((xv, "a"), (-xv, "e"))):
        _fg_glyph("Hammer_RuneSide%d" % k, hc - yv * 0.34 + o * 0.35, o, 0.3, key, rune, ham, up=tuple(A))
    _fg_glyph("Hammer_RuneTop", hc - yv * 0.34 + A * 0.38, A, 0.28, "b", rune, ham, up=tuple(-yv))
    _fg_box("Hammer_Cap", hc + A * 0.42, (0.3, 0.3, 0.12), brass, ham, x=xv, z=A, taper=0.6, bevel=0.02)
    ct = hc - A * 0.46 - xv * 0.15
    hch = empty("HammerChain", ct, ham)
    end = _fg_chain("HammerChain", ct, 4, iron_l, hch, Vector((0, 1, 0)), Vector((1, 0, 0)), step=0.1)
    _rock("HammerChain_Weight", end + Vector((0, 0, -0.05)), 0.11, brass, hch, sides=6)
    _fg_glyph("HammerChain_Rune", end + Vector((0, -0.09, -0.05)), (0, -1, 0), 0.12, "b", rune, hch, r=0.018)

    loose_parts("forge_golem")
    export("forge_golem")


# ================================================================== RUNA DO ESCUDO (Forjador Rúnico)
# Pedra-runa de ~1,9 m que brota do chão da sala enquanto o Escudo Rúnico está de pé: lasca de pedra talhada e
# torta, cravada num monte de entulho, com cintas de ferro rebitadas, a runa acesa nas duas faces e uma brasa
# no alto. Pivô: Body (a pedra inteira; pulsa e treme em scripts/enemies/enemy.gd, _animate_rune).
def build_forge_rune():
    stone = mat("fr_stone", hexc("#7C7770"), 0.95)
    stone_d = mat("fr_stone_d", hexc("#57534E"), 0.95)
    stone_l = mat("fr_stone_l", hexc("#A39E94"), 0.95)
    iron = mat("fr_iron", hexc("#3D414B"), 0.7)
    brass = mat("fr_brass", hexc("#B88C3A"), 0.6)
    rune = mat("fr_rune_flat", hexc("#FFC04A"), 0.3, 0.0, emit=(1.0, 0.62, 0.12), strength=4.0)
    ember = mat("fr_ember_flat", hexc("#FF6A1E"), 0.3, 0.0, emit=(1.0, 0.32, 0.05), strength=4.5)
    crack = mat("fr_crack_flat", hexc("#E0471C"), 0.4, 0.0, emit=(0.95, 0.22, 0.04), strength=2.6)
    root = empty("ForgeRune", (0, 0, 0))
    body = empty("Body", (0, 0, 0), root)
    lean = Vector((0.06, 0.05, 1))
    ln = lean.normalized()
    rr = random.Random(4)
    for k in range(8):     # entulho: lascas de pedra talhada tombadas em volta do pé
        a = math.tau * k / 8 + rr.uniform(-0.2, 0.2)
        d = rr.uniform(0.3, 0.42)
        sz = rr.uniform(0.26, 0.4)
        _fg_box("Rubble%d" % k, (math.cos(a) * d, math.sin(a) * d * 0.8, sz * 0.22), (sz, sz * rr.uniform(0.6, 0.9), sz * 0.7),
                (stone_d, stone, stone_l)[k % 3], body, x=(math.cos(a * 3.1), math.sin(a * 3.1), rr.uniform(-0.3, 0.3)),
                z=(rr.uniform(-0.35, 0.35), rr.uniform(-0.35, 0.35), 1), bevel=0.04, jitter=0.03, seed=k + 1)
    _fg_box("Slab", ln * 0.82, (0.74, 0.34, 1.7), stone, body, z=lean, taper=0.62, bevel=0.06, jitter=0.02, seed=9)
    _fg_box("SlabTip", ln * 1.74, (0.44, 0.22, 0.34), stone_l, body, z=lean, taper=0.25, bevel=0.03, jitter=0.012, seed=2)
    for k, t in enumerate((0.42, 1.36)):
        w = 0.74 * (1.0 - 0.38 * (t / 1.7 if t > 0.82 else 0.0))
        _fg_box("Band%d" % k, ln * t, (w + 0.09, 0.42, 0.1), iron, body, z=lean, bevel=0.015)
        _fg_rivets("BandRivets%d" % k, [(ln * t + Vector((sx * w * 0.32, sy * 0.215, 0)), (0, sy, 0)) for sx in (-1, 1)
                                        for sy in (-1, 1)], 0.04, brass, body)
    for k, sy in enumerate((-1, 1)):
        _fg_glyph("Rune%d" % k, ln * 0.9 + Vector((0, sy * 0.17, 0)), (0, sy, 0), 0.5, "d" if k == 0 else "b", rune, body,
                  up=tuple(ln), r=0.04)
    fera_curve("Crack", [ln * 0.16 + Vector((0.22, -0.165, 0)), ln * 0.34 + Vector((0.27, -0.165, 0)),
                         ln * 0.5 + Vector((0.21, -0.165, 0)), ln * 0.66 + Vector((0.27, -0.165, 0))], 0.03, 0.02,
               crack, body, sides=4)
    _rock("Ember", ln * 1.93, 0.1, ember, body, sides=6, prof=((-1.0, 0.1), (-0.3, 1.0), (0.4, 0.7), (1.0, 0.05)))
    loose_parts("forge_rune")
    export("forge_rune")


BOSS_BUILDERS["forge_golem"] = build_forge_golem
BOSS_BUILDERS["forge_rune"] = build_forge_rune
