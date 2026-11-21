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
