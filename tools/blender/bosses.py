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
    trunk = fera_dense([sec((0, 0.07, 0.56), 0.2, 0.18), sec((0, 0.07, 0.64), 0.7, 0.62), sec((0, 0.05, 1.1), 0.56, 0.48),
                        sec((0, 0.03, 1.55), 0.4, 0.33), sec((0, 0.0, 1.8), 0.34, 0.28), sec((0, -0.04, 2.1), 0.42, 0.32),
                        sec((0, -0.1, 2.4), 0.5, 0.37), sec((0, -0.14, 2.68), 0.54, 0.4), sec((0, -0.13, 2.86), 0.42, 0.34),
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
            m = Vector((s * (0.27 - 0.02 * k), hc.y - 0.11, z - 0.02))
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
        h = 0.78 - 0.1 * abs(k - 3) + (0.08 if k % 2 else 0.0)
        pts = [b, b + o * 0.16 + up * h * 0.5, b + o * 0.28 + up * h]
        _vh_blade("Collar%d" % k, pts, [0.15, 0.12, 0.012], o, robe_d if k % 2 else iron, body, thick=0.035,
                  mats=(gold_d,), matf=lambda i, j: 1 if j in (0, 4) else 0, n=8)
    for s in (1, -1):
        nm = "L" if s > 0 else "R"
        for k in range(3):   # três placas sobrepostas, a de cima maior
            c = Vector((s * (0.5 + 0.12 * k), -0.14, 2.87 - 0.11 * k))
            _rock("Pauldron%s%d" % (nm, k), c, 0.27 - 0.035 * k, iron if k != 1 else gold_d, body,
                  squash=(1.2, 1.15, 0.5), sides=6, prof=((-1.0, 0.8), (-0.5, 1.0), (0.2, 0.9), (0.7, 0.55), (1.0, 0.1)))
            _vh_blade("PauldronCrest%s%d" % (nm, k), [c + Vector((0, -0.26 + 0.03 * k, -0.02)), c + Vector((s * 0.03, 0, 0.17 - 0.02 * k)),
                                                       c + Vector((0, 0.26 - 0.03 * k, -0.02))], [0.02, 0.05, 0.02], (s, 0, 0.3),
                      gold if k != 1 else iron, body, thick=0.05)
            fera_tip("PauldronSpike%s%d" % (nm, k), c + Vector((s * 0.1, 0, 0.05)),
                     c + Vector((s * (0.3 + 0.08 * k), 0.04, 0.38 - 0.1 * k)), 0.065, bone_d if k == 0 else iron, body)
        fera_tip("PauldronHorn" + nm, Vector((s * 0.44, -0.02, 2.92)), Vector((s * 0.56, 0.3, 3.5)), 0.09, bone_d, body)
        _vh_loop("PauldronRim" + nm, Vector((s * 0.54, -0.14, 2.8)), 0.3, 0.03, (1, 0, 0), (0, 1, 0), gold, body, n=18, sides=5)

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
            r = 0.55 + 0.36 * t + 0.09 * math.sin(j * 2.6 + t * 2.0) * t
            drop = 2.05 + ((0.34 if j % 2 == 0 else -0.16) if i == rows - 1 else 0.0)
            row.append(Vector((o.x * r * 1.05, o.y * r * 0.86 + 0.16 * t, 2.84 - t * drop)))
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
        _rock("CapeClasp" + ("L" if s > 0 else "R"), Vector((s * 0.44, -0.05, 2.84)), 0.11, gold, cape,
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
    mk = [Vector((0, -0.6, 3.6)), Vector((0, -0.66, 3.46)), Vector((0, -0.69, 3.24)), Vector((0, -0.67, 3.02)),
          Vector((0, -0.62, 2.84)), Vector((0, -0.56, 2.7))]
    sloft("Mask", fera_dense([sec(p, w, 0.07, fr=1.0, bk=0.5) for p, w in zip(mk, (0.1, 0.19, 0.21, 0.16, 0.09, 0.012))],
                             14, cut=2), bone, head, sides=12, fwd=(0, -1, 0), mats=(bone_d,),
          matf=lambda i, j: 1 if j in (0, 5, 6, 11) else 0, sharp=80.0)
    # a fenda: um corte vertical aceso, mais largo no meio
    sloft("EyeSocket", [sec(Vector((0, -0.74, 3.5)), 0.012, 0.01), sec(Vector((0, -0.762, 3.32)), 0.075, 0.012),
                        sec(Vector((0, -0.76, 3.18)), 0.068, 0.012), sec(Vector((0, -0.73, 2.98)), 0.01, 0.01)], void, head,
          sides=8, fwd=(0, -1, 0), sharp=80.0)
    sloft("Eye", [sec(Vector((0, -0.75, 3.46)), 0.008, 0.012), sec(Vector((0, -0.772, 3.31)), 0.045, 0.02),
                  sec(Vector((0, -0.77, 3.19)), 0.04, 0.02), sec(Vector((0, -0.74, 3.02)), 0.006, 0.012)], eye, head,
          sides=6, fwd=(0, -1, 0), sharp=80.0)
    # rachaduras e o canto quebrado da máscara
    for k, pts in enumerate((((0.1, -0.735, 3.46), (0.07, -0.752, 3.38), (0.11, -0.74, 3.3)),
                             ((-0.14, -0.72, 3.22), (-0.08, -0.752, 3.14), (-0.1, -0.74, 3.02)),
                             ((0.03, -0.7, 2.94), (0.05, -0.685, 2.86), (0.0, -0.66, 2.78)))):
        fera_curve("MaskCrack%d" % k, [Vector(p) for p in pts], 0.012, 0.004, iron, head, sides=4)
    fera_curve("MaskTear", [Vector((0, -0.742, 3.05)), Vector((0.005, -0.722, 2.95)), Vector((0.0, -0.69, 2.86))], 0.014,
               0.004, vein, head, sides=4)
    _rock("MaskChip", Vector((-0.15, -0.69, 3.46)), 0.05, void, head, squash=(1.0, 0.6, 1.2), sides=5)
    # coroa quebrada: aro na testa do capuz e pontas de alturas diferentes (três partidas, de topo reto)
    cz = 3.62

    def crown_r(deg, out=0.0):
        return _vsurf(hood, cz, deg, out)

    sloft("CrownBand", [sec(crown_r(a, 0.015), 0.035, 0.06) for a in range(0, 361, 12)], gold, head, sides=6,
          fwd=(0, 0, 1), sharp=60.0)
    for k, (deg, h, broken) in enumerate(((90, 0.62, False), (58, 0.4, True), (122, 0.46, False), (25, 0.34, False),
                                          (155, 0.22, True), (350, 0.3, False), (190, 0.36, False), (300, 0.26, False),
                                          (240, 0.3, True))):
        b = crown_r(deg, 0.0)
        o = radial(deg)
        t = b + o * 0.1 + up * h
        if broken:
            sloft("CrownSpike%d" % k, [sec(b - up * 0.04, 0.06, 0.035), sec(b.lerp(t, 0.6), 0.045, 0.028),
                                       sec(b.lerp(t, 0.66), 0.03, 0.02)], gold_d, head, sides=6, fwd=o, sharp=50.0)
        else:
            _vh_blade("CrownSpike%d" % k, [b - up * 0.04, b.lerp(t, 0.5), t], [0.06, 0.045, 0.006], o, gold, head,
                      thick=0.035, mats=(gold_d,), matf=lambda i, j: 1 if j in (0, 4) else 0)
    _rock("CrownGem", crown_r(90, 0.04), 0.06, eye, head, squash=(0.8, 0.6, 1.3), sides=6)
    # halo partido: cubo na nuca preso ao capuz por uma haste; do cubo saem os raios até os arcos do anel
    hub_c = Vector((0, 0.42, 3.5))
    fera_curve("HaloStem", [Vector((0, 0.1, 3.42)), Vector((0, 0.3, 3.47)), hub_c + Vector((0, 0.02, 0))], 0.07, 0.06, iron,
               head, sides=6)
    halo = empty("Halo", hub_c, head)
    _rock("HaloHub", hub_c, 0.13, gold, halo, squash=(1.0, 0.6, 1.0), sides=8)
    _rock("HaloEye", hub_c + Vector((0, -0.06, 0)), 0.06, eye, halo, squash=(1.0, 0.6, 1.0), sides=6)
    HR = 0.86
    for k, (a0, a1) in enumerate(((-0.35, 1.25), (1.6, 3.0), (3.45, 4.45), (4.75, 5.6))):
        _vh_loop("HaloArc%d" % k, hub_c, HR, 0.05, (1, 0, 0), (0, 0, 1), gold if k != 2 else gold_d, halo, a0, a1,
                 n=max(6, int((a1 - a0) * 9)), sides=6)
        _vh_loop("HaloGlow%d" % k, hub_c + Vector((0, -0.035, 0)), HR, 0.022, (1, 0, 0), (0, 0, 1), eye, halo,
                 a0 + 0.06, a1 - 0.06, n=max(6, int((a1 - a0) * 9)), sides=4)
        # raios: um ou dois por arco, do cubo até o anel
        for j, t in enumerate((0.3, 0.75) if a1 - a0 > 1.2 else (0.5,)):
            a = a0 + (a1 - a0) * t
            d = Vector((math.cos(a), 0, math.sin(a)))
            _vh_blade("HaloSpoke%d_%d" % (k, j), [hub_c + d * 0.08, hub_c + d * HR * 0.55, hub_c + d * (HR + 0.02)],
                      [0.04, 0.022, 0.03], (0, -1, 0), gold_d, halo, thick=0.02)
        # pontas de sol para fora do arco (as do arco gasto estão quebradas)
        m = max(2, int((a1 - a0) * 3.2))
        for j in range(m):
            a = a0 + (a1 - a0) * (j + 0.5) / m
            d = Vector((math.cos(a), 0, math.sin(a)))
            ln = (0.3 if j % 2 == 0 else 0.18) * (0.5 if k == 2 else 1.0)
            _vh_blade("HaloRay%d_%d" % (k, j), [hub_c + d * (HR - 0.03), hub_c + d * (HR + ln * 0.5), hub_c + d * (HR + ln)],
                      [0.05, 0.035, 0.005], (0, -1, 0), gold, halo, thick=0.022)

    # ---------------- braços em três ossos, continuação do tronco: o ombro nasce DENTRO do manto, a manga larga
    # cobre o braço até o cotovelo e acaba em tiras; o antebraço é quitina nua com bracelete; a mão tem quatro
    # garras compridas e um polegar
    for side, s in (("ArmL", 1), ("ArmR", -1)):
        nm = side[-1]
        sh = Vector((s * 0.32, -0.13, 2.72))
        arm = empty(side, sh, body)
        elbow = Vector((s * 0.86, -0.1, 1.94))
        up_pts = [Vector((s * 0.2, -0.13, 2.76)), Vector((s * 0.54, -0.13, 2.62)), Vector((s * 0.78, -0.12, 2.3)), elbow]
        up_r = (0.3, 0.21, 0.185, 0.24)
        sloft(side + "_Sleeve", fera_dense([sec(p, r, r * 0.92) for p, r in zip(up_pts, up_r)], 16, cut=2),
              robe, arm, sides=14, fwd=(0, -1, 0), mats=(robe_d, robe_l),
              matf=lambda i, j: 1 if j % 4 == 0 else (2 if j % 4 == 2 else 0), sharp=80.0)
        ud = (elbow - up_pts[2]).normalized()
        cu = ud.cross(Vector((0, 1, 0))).normalized()
        # boca da manga: debrum e as tiras rasgadas (SleeveL/R balançam)
        _vh_loop(side + "_Cuff", elbow - ud * 0.02, 0.235, 0.045, cu, (0, 1, 0), lining_d, arm, n=16, sides=5)
        for k in range(6):   # dobras do pano descendo a manga
            a = math.tau * k / 6 + 0.3
            o = (cu * math.cos(a) + Vector((0, 1, 0)) * math.sin(a)).normalized()
            fera_curve("%s_Fold%d" % (side, k), [p + o * r * 0.86 for p, r in zip(up_pts[1:], up_r[1:])], 0.035, 0.07,
                       robe_l if k % 2 else robe_d, arm, sides=5)
        slv = empty("Sleeve" + nm, elbow, arm)
        for k in range(5):
            a = math.tau * k / 5 + 0.4
            o = (cu * math.cos(a) + Vector((0, 1, 0)) * math.sin(a)).normalized()
            b = elbow - ud * 0.1 + o * 0.2
            ln = 0.4 + 0.22 * ((k * 3) % 4) / 3.0
            _vh_blade("%s_Shred%d" % (side, k), [b, b + ud * 0.1 - up * ln * 0.5 + o * 0.03, b + ud * 0.06 - up * ln],
                      [0.11, 0.085, 0.01], o, robe_d if k % 2 else robe, slv, mats=(lining_d,),
                      matf=lambda i, j: 1 if i >= 5 else 0, n=8)
        el = empty("Elbow" + nm, elbow, arm)
        wrist = Vector((s * 0.93, -0.46, 1.12))
        fd = (wrist - elbow).normalized()
        sloft(side + "_ElbowKnot", [sec(elbow - fd * 0.34 + Vector((0, 0.02, 0.1)), 0.07, 0.07), sec(elbow - fd * 0.12, 0.15, 0.14),
                                    sec(elbow + fd * 0.1, 0.14, 0.13), sec(elbow + fd * 0.3, 0.1, 0.1)], chitin, el,
              sides=10, fwd=(0, -1, 0), sharp=80.0)
        fera_tip(side + "_ElbowSpur", elbow + Vector((s * 0.06, 0.08, 0.02)), elbow + Vector((s * 0.2, 0.36, 0.2)), 0.06,
                 bone_d, el)
        fore = [elbow - fd * 0.06, elbow.lerp(wrist, 0.35) + Vector((s * 0.03, 0, 0)), elbow.lerp(wrist, 0.7), wrist]
        sloft(side + "_Fore", fera_dense([sec(p, r, r) for p, r in zip(fore, (0.11, 0.125, 0.1, 0.085))], 12, cut=2),
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
            ln = 0.62 - 0.07 * abs(k - 1.5)
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

    loose_parts("void_herald")
    export("void_herald")


BOSS_BUILDERS["void_herald"] = build_void_herald
