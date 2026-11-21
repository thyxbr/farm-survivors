# Chefes de dungeon com modelo próprio. Executado por build_assets.py depois de monsters.py (usa os helpers de
# monsters.py, anime_body.py e body.py). Frente = -Y, Z para cima. Cada membro nasce de uma junta enterrada no
# corpo, com o pivô dentro do corpo: girando, a junta continua escondida e nada fica solto (loose_parts confere).
import math


# ================================================================== ESPINHEIRA, A GUARDIÃ-RAIZ (chefe do Bosque)
# Árvore antiga corrompida (~4 m) que anda sobre duas pernas de raiz. Tronco grosso de casca em sulcos, curvado
# para a frente, que se abre em galhos no alto; rosto entalhado (sobrancelha de nó, olhos em fenda e boca acesos
# de carmim) e veios de corrupção subindo pela casca. Braços de galho em dois ossos com mãos de raízes-garra,
# espinhos pelo corpo e uma copa de galhos tortos com tufos de folha escura. Frente = -Y.
# Pivôs animados por scripts/enemies/enemy.gd (_animate_thorn): Body (tronco, no quadril), Head (o rosto, dentro de
# Body), Jaw (o queixo, dentro de Head), Crown (a copa, dentro de Body), ArmL/ArmR (no ombro, DENTRO do tronco) >
# ElbowL/ElbowR (antebraço e mão) e LegL/LegR (no quadril, dentro do tronco) > KneeL/KneeR (canela e pé de raiz).
THORN_HIP = 1.15


def _bark_tube(name, pts, r0, r1, bark, bark_d, parent, sides=12, n=16):
    """Galho/raiz liso afinando por uma linha de pontos, com sulcos de casca (colunas alternadas mais escuras)."""
    k = len(pts)
    secs = fera_dense([sec(p, r0 + (r1 - r0) * i / (k - 1), r0 + (r1 - r0) * i / (k - 1)) for i, p in enumerate(pts)],
                      n, cut=2)
    return sloft(name, secs, bark, parent, sides=sides, fwd=(0, 0, 1), mats=(bark_d,),
                 matf=lambda i, j: 1 if j % 3 == 0 else 0, sharp=80.0)


def _foliage(name, c, r, mats, parent, seed):
    """Tufo de folhas: três bolas achatadas e facetadas encavaladas (lê como copa no toon, não como esfera)."""
    import random
    rnd = random.Random(seed)
    c = Vector(c)
    for k in range(3):
        off = Vector((rnd.uniform(-1, 1) * r * 0.45, rnd.uniform(-1, 1) * r * 0.45, rnd.uniform(-0.2, 0.3) * r))
        rr = r * rnd.uniform(0.62, 0.85)
        _rock("%s_%d" % (name, k), c + off, rr, mats[k % len(mats)], parent, squash=(1.0, 1.0, 0.72), sides=7,
              prof=((-1.0, 0.25), (-0.55, 0.85), (0.0, 1.0), (0.5, 0.86), (0.88, 0.45), (1.0, 0.1)))


def build_thorn_tree():
    bark = mat("tt_bark", hexc("#5B4636"), 0.95)
    bark_d = mat("tt_bark_d", hexc("#35281F"), 0.95)
    bark_l = mat("tt_bark_l", hexc("#7E6650"), 0.95)
    moss = mat("tt_moss", hexc("#3F5A24"), 0.95)
    leaf = mat("tt_leaf", hexc("#2F4A26"), 0.9)
    leaf_d = mat("tt_leaf_d", hexc("#1F3320"), 0.9)
    leaf_c = mat("tt_leaf_c", hexc("#5A2A44"), 0.9)          # folhas tomadas pela corrupção
    thorn = mat("tt_thorn", hexc("#2A1A1E"), 0.6)
    vein = mat("tt_vein", hexc("#C21A5C"), 0.4, 0.0, emit=(0.85, 0.08, 0.38), strength=2.6)
    eye = mat("tt_eye_flat", hexc("#FF5A8A"), 0.2, 0.0, emit=(1.0, 0.2, 0.45), strength=4.5)
    maw = mat("tt_maw_flat", hexc("#1A0610"), 0.9)
    tooth = mat("tt_tooth", hexc("#B8A27E"), 0.8)
    HIP = THORN_HIP

    root = empty("Thorn", (0, 0, 0))

    # ---------------- tronco: base larga (onde as raízes-pernas entram), cintura, peito largo curvado para a frente;
    # no alto não fecha: continua largo e os galhos da copa saem de dentro dele
    body = empty("Body", (0, 0, HIP), root)
    trunk = fera_dense([sec((0, 0.05, HIP - 0.35), 0.46, 0.4), sec((0, 0.04, HIP - 0.05), 0.6, 0.5),
                        sec((0, 0.02, HIP + 0.35), 0.52, 0.45), sec((0, -0.06, 1.95), 0.6, 0.5),
                        sec((0, -0.16, 2.45), 0.66, 0.54), sec((0, -0.2, 2.85), 0.6, 0.52),
                        sec((0, -0.18, 3.15), 0.52, 0.46), sec((0, -0.16, 3.3), 0.4, 0.36)], 22, cut=2)
    sloft("Trunk", trunk, bark, body, sides=20, phase=0.0, mats=(bark_d,),
          matf=lambda i, j: 1 if j % 4 == 1 or (j % 4 == 2 and i % 5 == 0) else 0, sharp=80.0)
    # nós de casca no peito e na barriga, meio enterrados
    for k, (z, d, r) in enumerate(((2.05, 58, 0.16), (1.7, 128, 0.13), (2.6, 300, 0.15), (1.45, 240, 0.14))):
        _blob("Burl%d" % k, _vsurf(trunk, z, d, -0.06), r, r * 0.85, r * 1.1, bark_l, body, sides=14, rings=8)
    # musgo: tufos baixos e achatados no alto, onde o tronco abre em galhos
    for k, (z, d, r) in enumerate(((3.05, 10, 0.2), (3.0, 170, 0.2), (2.9, 250, 0.22), (3.08, 300, 0.18))):
        c = _vsurf(trunk, z, d, -0.1)
        for j in range(3):
            _rock("Moss%d_%d" % (k, j), c + Vector((0.07 * (j - 1), 0.03 * (j - 1), -0.05 * j)), r * (1.0 - 0.2 * j),
                  moss, body, squash=(1.0, 1.0, 0.4), sides=7)
    # veios de corrupção: sobem pela casca da frente e das costas, acesos
    for k, pts in enumerate((((1.0, 100), (1.3, 92), (1.6, 104), (1.85, 96)),
                             ((1.1, 70), (1.4, 62), (1.75, 74)),
                             ((2.6, 125), (2.85, 136), (3.05, 128)),
                             ((1.2, 250), (1.6, 262), (2.0, 252), (2.45, 266), (2.85, 258)),
                             ((1.5, 300), (1.85, 292), (2.2, 306)))):
        fera_curve("Vein%d" % k, [_vsurf(trunk, z, d, 0.008) for z, d in pts], 0.03, 0.014, vein, body, sides=5)
    # espinhos pelo tronco
    for k, (z, d, ln) in enumerate(((1.2, 20, 0.22), (1.35, 160, 0.2), (2.0, 200, 0.26), (2.2, 340, 0.24),
                                    (2.5, 230, 0.3), (1.8, 285, 0.3), (2.6, 250, 0.28), (1.05, 275, 0.22))):
        p = _vsurf(trunk, z, d, -0.04)
        out = (p - Vector((0, trunk[0]["c"].y, z))).normalized()
        fera_tip("TrunkThorn%d" % k, p, p + (out + Vector((0, 0, 0.35))).normalized() * ln, 0.05, thorn, body)

    # ---------------- rosto entalhado: sobrancelha de nó caída para o meio, olhos em fenda inclinados (bravos),
    # nariz de galho quebrado e boca larga de casca com dentes de lasca
    head = empty("Head", (0, -0.5, 2.4), body)
    for s in (1, -1):
        nm = "L" if s > 0 else "R"
        bp = _vsurf(trunk, 2.64, 90 - s * 26, -0.06)
        sloft("Brow" + nm, fera_dense([sec(bp + Vector((-s * 0.22, 0.02, -0.12)), 0.08, 0.08),
                                       sec(bp + Vector((0, -0.06, 0.0)), 0.13, 0.12),
                                       sec(bp + Vector((s * 0.22, 0.08, 0.08)), 0.06, 0.06)], 10),
              bark_l, head, sides=10, fwd=(0, -1, 0), axis=(1, 0, 0), sharp=80.0)
        ec = _vsurf(trunk, 2.48, 90 - s * 26, -0.02)
        tilt = (s * 0.4, 0.0, 1.0)   # canto de dentro mais baixo: olhar bravo
        sloft("EyeSocket" + nm, [sec(ec + Vector((0, 0.06, 0)), 0.15, 0.08), sec(ec + Vector((0, -0.005, 0)), 0.17, 0.09),
                                 sec(ec + Vector((0, -0.02, 0)), 0.15, 0.075)], maw, head, sides=12,
              fwd=tilt, axis=(0, -1, 0))
        sloft("Eye" + nm, [sec(ec + Vector((0, 0.0, 0)), 0.12, 0.042), sec(ec + Vector((0, -0.03, 0)), 0.105, 0.034),
                           sec(ec + Vector((0, -0.036, 0)), 0.03, 0.012)], eye, head, sides=10,
              fwd=tilt, axis=(0, -1, 0))
    np = _vsurf(trunk, 2.3, 90, -0.04)
    sloft("Nose", fera_dense([sec(np + Vector((0, 0.08, 0.06)), 0.09, 0.08), sec(np + Vector((0, -0.08, -0.02)), 0.07, 0.06),
                              sec(np + Vector((0, -0.14, -0.06)), 0.035, 0.03)], 8), bark_l, head, sides=10,
          fwd=(0, 0, 1), axis=(0, -1, 0), sharp=80.0)
    mc = _vsurf(trunk, 2.06, 90, -0.04)
    sloft("Maw", [sec(mc + Vector((0, 0.1, 0)), 0.3, 0.14), sec(mc + Vector((0, -0.02, 0)), 0.34, 0.17),
                  sec(mc + Vector((0, -0.05, 0)), 0.3, 0.13)], maw, head, sides=16, fwd=(0, 0, 1), axis=(0, -1, 0))
    for k in range(7):
        x = (k - 3) * 0.085
        p = Vector((x, mc.y - 0.05, mc.z + 0.13 - 0.03 * (abs(k - 3) / 3) ** 2))
        fera_tip("UpTooth%d" % k, p, p + Vector((0, -0.01, -0.13 + 0.025 * abs(k - 3) + 0.03 * (k % 2))), 0.032,
                 tooth, head)
    # queixo: placa de casca que abre para baixo (pivô no fundo da boca)
    jaw = empty("Jaw", (0, mc.y + 0.08, mc.z - 0.02), head)
    sloft("JawMesh", fera_dense([sec(mc + Vector((-0.34, 0.04, -0.12)), 0.09, 0.09),
                                 sec(mc + Vector((0, -0.07, -0.2)), 0.13, 0.11),
                                 sec(mc + Vector((0.34, 0.04, -0.12)), 0.09, 0.09)], 12),
          bark_l, jaw, sides=10, fwd=(0, -1, 0), axis=(1, 0, 0), sharp=80.0)
    for k in range(6):
        x = (k - 2.5) * 0.095
        p = Vector((x, mc.y - 0.07, mc.z - 0.12))
        fera_tip("LowTooth%d" % k, p, p + Vector((0, -0.01, 0.1 - 0.03 * (k % 2))), 0.028, tooth, jaw)

    # ---------------- copa: galhos grossos que saem de dentro do topo do tronco, com espinhos e tufos de folha
    crown = empty("Crown", (0, -0.16, 3.0), body)
    top = Vector((0, -0.16, 3.05))
    boughs = (((0.95, 0.15, 0.7), (1.75, 0.25, 0.95), 0.17), ((-1.0, 0.1, 0.65), (-1.8, 0.3, 0.9), 0.17),
              ((0.45, 0.6, 1.0), (0.8, 1.2, 1.25), 0.15), ((-0.4, 0.65, 0.95), (-0.85, 1.15, 1.3), 0.15),
              ((0.2, -0.4, 0.95), (0.45, -0.75, 1.3), 0.13))
    tips = []
    for k, (mid, end, r) in enumerate(boughs):
        p0 = top + Vector((mid[0] * 0.2, mid[1] * 0.2, -0.3))
        p1 = top + Vector((mid[0] * 0.45, mid[1] * 0.45, mid[2] * 0.4))
        p2 = top + Vector(mid)
        p3 = top + Vector(end)
        _bark_tube("Bough%d" % k, [p0, p1, p2, p3], r * 1.6, 0.03, bark, bark_d, crown, sides=12, n=16)
        tips.append((p2, p3))
        for j in range(2):   # espinhos nos galhos
            c = p1.lerp(p2, 0.45) if j == 0 else p2.lerp(p3, 0.5)
            d = Vector((mid[1], -mid[0], 0.6)).normalized() * (1 if (k + j) % 2 else -1)
            fera_tip("BoughThorn%d_%d" % (k, j), c, c + (d + Vector((0, 0, 0.6))).normalized() * 0.2, 0.035, thorn,
                     crown)
    for k, (p2, p3) in enumerate(tips):
        _foliage("Leaves%d" % k, p2.lerp(p3, 0.75), 0.68 if k < 2 else 0.6,
                 (leaf, leaf_d, leaf_c) if k == 2 else (leaf, leaf_d), crown, 11 + k)
    _foliage("LeavesTop", top + Vector((0, 0.25, 1.25)), 0.75, (leaf_d, leaf, leaf_c), crown, 7)
    for k, (dx, dy, dz, r) in enumerate(((0.9, 0.6, 1.05, 0.55), (-0.95, 0.55, 1.0, 0.55), (0.55, -0.3, 1.2, 0.5),
                                         (-0.55, -0.25, 1.15, 0.5))):   # tufos entre os galhos: copa cheia
        _foliage("LeavesMid%d" % k, top + Vector((dx, dy, dz)), r, (leaf, leaf_d) if k % 2 else (leaf_d, leaf_c, leaf),
                 crown, 31 + k)
        _bark_tube("Twig%d" % k, [top + Vector((dx * 0.15, dy * 0.15, 0.1)), top + Vector((dx * 0.6, dy * 0.6, dz * 0.75)),
                                  top + Vector((dx, dy, dz))], 0.12, 0.05, bark, bark_d, crown, sides=10, n=10)

    # ---------------- pernas de raiz em dois ossos: coxa (LegL/LegR, quadril DENTRO da base do tronco) e canela com
    # o pé de raízes grossas que arqueiam e afundam no chão (KneeL/KneeR). O joelho é um nó que cobre a dobra.
    for side, x in (("LegL", 0.34), ("LegR", -0.34)):
        s = 1 if x > 0 else -1
        leg = empty(side, (x, 0.04, HIP), root)
        knee = Vector((x + s * 0.24, -0.08, 0.62))
        _bark_tube(side + "_Thigh", [Vector((x, 0.04, HIP + 0.1)), Vector((x + s * 0.12, -0.02, 0.9)), knee],
                   0.24, 0.19, bark, bark_d, leg, sides=12, n=12)
        kn = empty("Knee" + side[-1], knee, leg)
        _blob(side + "_KneeKnot", knee + Vector((s * 0.03, -0.04, 0)), 0.26, 0.25, 0.22, bark_l, kn, sides=16, rings=8)
        ankle = Vector((x + s * 0.3, -0.02, 0.18))
        _bark_tube(side + "_Shin", [knee, knee.lerp(ankle, 0.5) + Vector((0, 0.02, 0)), ankle], 0.19, 0.2,
                   bark, bark_d, kn, sides=12, n=10)
        _blob(side + "_Foot", ankle + Vector((0, -0.02, -0.04)), 0.26, 0.3, 0.16, bark_d, kn, sides=16, rings=8)
        for k, (dx, dy) in enumerate(((s * 0.12, -0.55), (s * 0.42, -0.32), (s * 0.45, 0.2), (-s * 0.12, 0.42))):
            a = ankle + Vector((0, 0, -0.06))
            _bark_tube("%s_Toe%d" % (side, k), [a, a + Vector((dx * 0.45, dy * 0.45, 0.08)),
                                                 a + Vector((dx * 1.25, dy * 1.25, -0.14))],
                       0.15, 0.025, bark, bark_d, kn, sides=10, n=10)

    # ---------------- braços de galho em dois ossos: nó do ombro enterrado no tronco (pivô DENTRO do tronco),
    # braço até o cotovelo (nó), antebraço comprido que vira a mão de raízes-garra na altura do joelho
    for side, x in (("ArmL", 0.62), ("ArmR", -0.62)):
        s = 1 if x > 0 else -1
        arm = empty(side, (s * 0.35, -0.12, 2.55), body)
        _blob(side + "_Shoulder", (x - s * 0.04, -0.12, 2.55), 0.27, 0.27, 0.27, bark_l, arm, sides=16, rings=8)
        elbow = Vector((x + s * 0.55, -0.12, 1.78))
        _bark_tube(side + "_Upper", [Vector((x, -0.12, 2.55)), Vector((x + s * 0.32, -0.12, 2.18)), elbow],
                   0.25, 0.2, bark, bark_d, arm, sides=12, n=12)
        el = empty("Elbow" + side[-1], elbow, arm)
        _blob(side + "_ElbowKnot", elbow + Vector((s * 0.03, 0.02, 0)), 0.25, 0.24, 0.23, bark_l, el, sides=14, rings=8)
        wrist = Vector((x + s * 0.62, -0.5, 0.98))
        _bark_tube(side + "_Fore", [elbow, elbow.lerp(wrist, 0.5) + Vector((s * 0.06, 0, 0)), wrist], 0.21, 0.2,
                   bark, bark_d, el, sides=12, n=10)
        _blob(side + "_Palm", wrist + Vector((0, -0.04, -0.06)), 0.24, 0.22, 0.2, bark_d, el, sides=14, rings=8)
        for k, (dx, dy, dz) in enumerate(((s * 0.16, -0.3, -0.35), (s * 0.02, -0.34, -0.42), (-s * 0.12, -0.28, -0.38),
                                          (-s * 0.18, -0.02, -0.25))):
            a = wrist + Vector((0, -0.04, -0.08))
            b = a + Vector((dx * 0.6, dy * 0.6, dz * 0.45))
            c = a + Vector((dx, dy * 1.1, dz))
            _bark_tube("%s_Claw%d" % (side, k), [a, b, c], 0.08, 0.014, bark_d, thorn, el, sides=8, n=8)
        for k in range(2):   # espinhos no braço e no antebraço
            c = Vector((x, -0.12, 2.55)).lerp(elbow, 0.35) if k == 0 else elbow.lerp(wrist, 0.5)
            out = Vector((s, 0.1, 0.3)).normalized()
            fera_tip("%s_Thorn%d" % (side, k), c + out * 0.1, c + out * 0.38, 0.045, thorn, arm if k == 0 else el)
        fera_curve(side + "_Vein", [Vector((x + s * 0.08, -0.26, 2.4)), Vector((x + s * 0.3, -0.3, 2.12)),
                                    elbow + Vector((0, -0.14, 0.06))], 0.024, 0.012, vein, arm, sides=5)

    loose_parts("thorn_tree")
    export("thorn_tree")


BOSS_BUILDERS = {"thorn_tree": build_thorn_tree}
