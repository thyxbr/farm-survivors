# Monstros da Geleira de Cristal (mapa "mina"): Lobo da Geada (e o Alfa, o mesmo modelo tingido), Gralha-de-Cristal e
# Ieti Glacial. Executado por build_assets.py (usa os helpers de monsters.py, anime_body.py e body.py).
# Frente = -Y, Z para cima. Cada membro nasce de uma junta enterrada no corpo, com o pivô dentro do corpo: girando,
# a junta continua escondida e nada fica solto (loose_parts confere no build).


# ================================================================== LOBO DA GEADA
# Lobo magro de pelo azul-gelo (~0,85 m na cernelha), barriga clara, cauda espessa com a ponta branca, colar de pelo
# eriçado no pescoço e uma crista de cristais de gelo da nuca até o meio das costas; olhos gelados acesos.
# Pivôs animados por scripts/enemies/enemy.gd (_animate_wolf): Body (tronco), Head (dentro de Body), Jaw (dentro de
# Head), Tail (dentro de Body) e LegFL, LegFR, LegBL, LegBR (na raiz; o ombro/quadril é uma massa enterrada no tronco).
def build_wolf():
    fur = mat("w_fur", hexc("#7C93A8"), 0.9)
    fur_d = mat("w_fur_d", hexc("#4A5E74"), 0.9)
    belly = mat("w_belly", hexc("#DCE7EF"), 0.9)
    nose = mat("w_nose", hexc("#1C2230"), 0.5)
    mouth = mat("w_mouth", hexc("#5A1E2A"), 0.85)
    fang = mat("w_fang", hexc("#F2F4F6"), 0.5)
    claw = mat("w_claw", hexc("#2A3038"), 0.55)
    crys = mat("w_ice", hexc("#8FE6FF"), 0.2, 0.0, emit=(0.35, 0.85, 1.0), strength=1.6)
    crys_d = mat("w_ice_d", hexc("#3AA0D8"), 0.2, 0.0, emit=(0.1, 0.55, 0.95), strength=1.2)
    eye = mat("w_eye_flat", (0.75, 0.97, 1.0), 0.3, 0.0, emit=(0.45, 0.9, 1.0), strength=4.0)
    up = (0, 0, 1)
    SIDES = 16
    TOP, BOTTOM = (2, 3, 4), (10, 11, 12)
    dense, tip, curve, surf = fera_dense, fera_tip, fera_curve, fera_surf

    def bands(dark=(), top=TOP, bottom=BOTTOM, belly_from=0, belly_to=999):
        def f(i, j):
            if j in bottom and belly_from <= i <= belly_to:
                return 2
            if j in top and i in dark:
                return 1
            return 0
        return f

    root = empty("Wolf", (0, 0, 0))
    body = empty("Body", (0, 0.0, 0.84), root)

    # ---------------- tronco: garupa, cintura fina e peito fundo que sobe para o pescoço
    torso = dense([sec((0, 0.66, 0.86), 0.06, 0.06),
                   sec((0, 0.56, 0.86), 0.15, 0.15),
                   sec((0, 0.36, 0.84), 0.16, 0.15, bk=0.95),
                   sec((0, 0.08, 0.84), 0.165, 0.16, bk=1.1),
                   sec((0, -0.18, 0.86), 0.2, 0.21, bk=1.5),
                   sec((0, -0.38, 0.9), 0.19, 0.22, bk=1.45),
                   sec((0, -0.5, 0.95), 0.12, 0.13)], 20)
    sloft("Torso", torso, fur, body, sides=SIDES, fwd=up, mats=(fur_d, belly),
          matf=bands(dark=set(range(2, 17)), belly_from=6, belly_to=19), sharp=80.0)
    # juba de inverno: um colar de pelo mais grosso em volta do pescoço (escuro em cima, claro embaixo), com tufos
    # curtos que escapam para trás nos lados
    mane = dense([sec((0, -0.3, 0.9), 0.17, 0.19, bk=1.3), sec((0, -0.4, 0.94), 0.23, 0.25, bk=1.35),
                  sec((0, -0.5, 1.0), 0.19, 0.2, bk=1.2), sec((0, -0.56, 1.04), 0.11, 0.12)], 12)
    sloft("Mane", mane, fur, body, sides=SIDES, fwd=up, mats=(fur_d, belly),
          matf=bands(dark=set(range(0, 12)), top=(3, 4, 5), bottom=(9, 10, 11, 12, 13), belly_from=0), sharp=80.0)
    for k, (a, y) in enumerate(((-30, -0.36), (-150, -0.36), (10, -0.34), (170, -0.34))):
        p = surf(mane, y, a, -0.04)
        ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
        tip("Tuft%d" % k, p, p + Vector((ca * 0.07, 0.13, sa * 0.05 - 0.02)), 0.06, belly if a < 0 else fur, body,
            flat=0.6)
    # crista de cristais de gelo: da nuca ao meio das costas, os maiores sobre os ombros
    for k, (y, ln, rr, lean) in enumerate(((-0.34, 0.2, 0.045, 0.6), (-0.22, 0.26, 0.055, 0.7), (-0.08, 0.22, 0.05, 0.8),
                                           (0.06, 0.16, 0.04, 0.9), (0.18, 0.11, 0.03, 1.0))):
        base = surf(torso, y, 90, -0.03)
        _crystal("Spine%d" % k, base, (0.0, lean, 1.0), ln, rr, (crys, crys_d), body)
    for k, (y, s) in enumerate(((-0.16, 1), (-0.12, -1), (0.0, 1))):   # cristais menores tortos para os lados
        base = surf(torso, y, 90 - s * 30, -0.03)
        _crystal("SpineSide%d" % k, base, (s * 0.6, 0.6, 0.8), 0.12, 0.03, (crys, crys_d), body)

    # ---------------- cauda espessa, curvada para baixo, ponta branca
    tail = empty("Tail", (0, 0.6, 0.86), body)
    tsecs = dense([sec((0, 0.56, 0.87), 0.08, 0.08), sec((0, 0.74, 0.88), 0.1, 0.1),
                   sec((0, 0.92, 0.8), 0.11, 0.11), sec((0, 1.04, 0.66), 0.09, 0.09),
                   sec((0, 1.1, 0.54), 0.05, 0.05), sec((0, 1.12, 0.48), 0.01, 0.01)], 16)
    sloft("TailMesh", tsecs, fur, tail, sides=12, fwd=(0, 0, 1), mats=(fur_d, belly),
          matf=lambda i, j: 2 if i >= 11 else (1 if j in (1, 2, 3) else 0), sharp=80.0)

    # ---------------- pescoço e cabeça: crânio largo, focinho longo, orelhas em ponta, mandíbula separada
    head = empty("Head", (0, -0.46, 0.98), body)
    neck = dense([sec((0, -0.38, 0.92), 0.13, 0.14), sec((0, -0.54, 1.02), 0.11, 0.12),
                  sec((0, -0.64, 1.1), 0.1, 0.1)], 10)
    sloft("Neck", neck, fur, head, sides=SIDES, fwd=(0, -0.5, 1), mats=(fur_d, belly),
          matf=bands(dark=set(range(0, 9)), belly_from=0), sharp=80.0)
    skull = dense([sec((0, -0.58, 1.13), 0.09, 0.09),
                   sec((0, -0.68, 1.15), 0.115, 0.1, bk=0.9),
                   sec((0, -0.78, 1.13), 0.095, 0.085, bk=0.8),
                   sec((0, -0.88, 1.09), 0.06, 0.055, bk=0.75),
                   sec((0, -0.97, 1.075), 0.045, 0.042, bk=0.75),
                   sec((0, -1.0, 1.072), 0.03, 0.03),
                   sec((0, -1.012, 1.07), 0.008, 0.008)], 16, cut=1)
    in_mouth = lambda i: skull[min(i, len(skull) - 1)]["c"].y < -0.8
    sloft("Skull", skull, fur, head, sides=SIDES, fwd=up, mats=(fur_d, mouth),
          matf=lambda i, j: 2 if (j in (10, 11, 12) and in_mouth(i)) else 1 if (j in TOP and i <= 7) else 0, sharp=80.0)
    # nariz preto na ponta do focinho
    _blob("Nose", surf(skull, -0.99, 40, -0.01), 0.032, 0.03, 0.026, nose, head, sides=12, rings=8)
    # bochechas de pelo claro abrindo para trás
    for s, nm in ((1, "L"), (-1, "R")):
        p = surf(skull, -0.7, -20, -0.02)
        p.x *= s
        tip("Cheek" + nm, p, p + Vector((s * 0.09, 0.1, -0.03)), 0.05, belly, head, flat=0.5)
    # orelhas em ponta, um pouco para trás
    for s, nm in ((1, "L"), (-1, "R")):
        e0 = surf(skull, -0.66, 90 - s * 45, -0.02)
        e0.x *= 1.0
        tp = Vector((s * 0.12, -0.6, 1.35))
        sloft("Ear" + nm, [sec(e0, 0.055, 0.03), sec(e0.lerp(tp, 0.5), 0.045, 0.022), sec(tp, 0.004, 0.004)],
              fur_d, head, sides=6, fwd=(0, -1, 0))
        ic = e0.lerp(tp, 0.35) + Vector((0, -0.018, 0))
        sloft("EarIn" + nm, [sec(ic, 0.03, 0.01), sec(ic.lerp(tp, 0.6), 0.015, 0.006)], belly, head, sides=6,
              fwd=(0, -1, 0))
    # olhos gelados amendoados, sob uma sobrancelha escura
    for s, nm in ((1, "L"), (-1, "R")):
        e0, e1, e2 = surf(skull, -0.73, 30, -0.004), surf(skull, -0.76, 34, 0.004), surf(skull, -0.795, 30, -0.004)
        for e in (e0, e1, e2):
            e.x *= s
        sloft("Eye" + nm, [sec(e0, 0.003, 0.006), sec(e1, 0.01, 0.017), sec(e2, 0.003, 0.005)], eye, head, sides=8,
              fwd=(s, 0, 0.3))
        brow = [surf(skull, y, d, -0.006) for y, d in ((-0.71, 52), (-0.75, 46), (-0.8, 40))]
        for b in brow:
            b.x *= s
        curve("Brow" + nm, brow, 0.018, 0.008, fur_d, head, sides=8)
    # presas de cima descendo do lábio
    for s, nm in ((1, "L"), (-1, "R")):
        for k, (y, ln) in enumerate(((-0.92, 0.045), (-0.86, 0.025))):
            p = surf(skull, y, -45, -0.006)
            p.x *= s
            tip("Fang%s%d" % (nm, k), p, p + Vector((0, -0.004, -ln)), 0.011, fang, head)

    # mandíbula estreita sob o focinho
    jaw = empty("Jaw", (0, -0.74, 1.06), head)
    jraw = []
    for y, w, h in ((-0.72, 0.7, 0.035), (-0.8, 0.66, 0.03), (-0.88, 0.62, 0.026), (-0.95, 0.6, 0.02),
                    (-0.985, 0.45, 0.012)):
        bot = surf(skull, y, -90).z
        jraw.append(sec((0, y, bot - h * 0.6), surf(skull, y, 0).x * w, h, bk=1.2))
    jsecs = dense(jraw, 10, cut=1)
    sloft("JawMesh", jsecs, belly, jaw, sides=12, fwd=up, mats=(mouth,),
          matf=lambda i, j: 1 if (j in (1, 2, 3, 4) and 1 <= i <= 8) else 0, sharp=80.0)
    for s in (1, -1):
        p = surf(jsecs, -0.9, 60, -0.004)
        p.x *= s
        tip("LowFang%d" % (0 if s > 0 else 1), p, p + Vector((0, 0.002, 0.03)), 0.009, fang, jaw)

    # ---------------- pernas: cada uma uma peça só, nascendo de uma massa de ombro/coxa enterrada no tronco
    def paw(name, c, leg, s):
        _blob(name, c + Vector((0, -0.02, 0.0)), 0.055, 0.075, 0.04, fur_d, leg, sides=12, rings=8)
        for k in range(3):
            dx = (k - 1) * 0.03
            c0 = c + Vector((dx, -0.08, -0.005))
            fera_tip(name + "Claw%d" % k, c0, c0 + Vector((dx * 0.2, -0.04, -0.03)), 0.012, claw, leg)

    for side, s, front in (("LegFL", 1, True), ("LegFR", -1, True), ("LegBL", 1, False), ("LegBR", -1, False)):
        x = s * 0.11
        if front:
            top = Vector((x, -0.3, 0.84))
            j1 = Vector((x + s * 0.01, -0.26, 0.5))    # cotovelo
            j2 = Vector((x + s * 0.01, -0.32, 0.2))    # punho
            ft = Vector((x + s * 0.01, -0.34, 0.05))
            secs = [(0.085, 0.13), (0.075, 0.1), (0.058, 0.066), (0.05, 0.055), (0.045, 0.05), (0.048, 0.05)]
        else:
            top = Vector((x, 0.42, 0.82))
            j1 = Vector((x + s * 0.01, 0.3, 0.5))      # joelho (para a frente)
            j2 = Vector((x + s * 0.01, 0.5, 0.24))     # jarrete (para trás)
            ft = Vector((x + s * 0.01, 0.45, 0.05))
            secs = [(0.095, 0.17), (0.085, 0.14), (0.058, 0.07), (0.045, 0.06), (0.042, 0.05), (0.046, 0.05)]
        leg = empty(side, top, root)
        _blob(side + "_Joint", top + Vector((0, 0, 0.03)), 0.08, 0.1, 0.11, fur, leg, sides=14, rings=8)
        pts = [top, top.lerp(j1, 0.5), j1, j1.lerp(j2, 0.5), j2, ft]
        lsecs = dense([sec(p, rx, ry) for p, (rx, ry) in zip(pts, secs)], 16)
        sloft(side + "_Mesh", lsecs, fur, leg, sides=12, fwd=(0, -1, 0), mats=(fur_d,),
              matf=lambda i, j: 1 if i >= 11 else 0, sharp=80.0)
        paw(side + "_Paw", ft, leg, s)

    for ob in coll.all_objects:
        if ob.type == 'MESH' and "Spine" not in ob.name:
            smooth_sharp(ob, 80.0)
    loose_parts("wolf")
    export("wolf")


# ================================================================== GRALHA-DE-CRISTAL
# Ave escura do tamanho de um cão (~1,9 m de asa a asa) que voa em volta e atira estilhaços de gelo: penas azul-noite,
# peito cinza-gelo, bico de gelo, olhos acesos e as pontas das penas grandes viradas em lascas de cristal.
# Mesmos pivôs do morcego (scripts/enemies/enemy.gd, _animate_bat): Body (a 1,5 m, sobe e desce no voo), Head (dentro
# de Body) e WingL/WingR (no ombro, dentro do tronco; giram no eixo da frente para bater).
def _feather(name, p0, p1, w, material, parent, mats=(), tipmat=None, thick=0.018, lift=0.0):
    """Pena chata e horizontal de p0 a p1, larga no meio e fechada na ponta; tipmat pinta o último terço."""
    p0, p1 = Vector(p0), Vector(p1)
    mid = p0.lerp(p1, 0.5) + Vector((0, 0, lift))
    secs = fera_dense([sec(p0, w * 0.5, thick), sec(p0.lerp(mid, 0.6), w, thick), sec(mid, w * 0.95, thick * 0.9),
                       sec(mid.lerp(p1, 0.6), w * 0.7, thick * 0.8), sec(p1, w * 0.06, thick * 0.4)], 12, cut=1)
    matf = (lambda i, j: 1 if i >= 8 else 0) if tipmat else None
    return sloft(name, secs, material, parent, sides=8, fwd=(0, 0, 1), mats=((tipmat,) if tipmat else ()), matf=matf,
                 sharp=80.0)


def build_crow():
    plum = mat("cr_plum", hexc("#3A4A6C"), 0.8)
    plum_d = mat("cr_plum_d", hexc("#24304A"), 0.8)
    chest = mat("cr_chest", hexc("#A9BED0"), 0.85)
    beak = mat("cr_beak", hexc("#D6E8F2"), 0.35)
    claw = mat("cr_claw", hexc("#151A24"), 0.5)
    crys = mat("cr_ice", hexc("#8FE6FF"), 0.2, 0.0, emit=(0.35, 0.85, 1.0), strength=1.8)
    crys_d = mat("cr_ice_d", hexc("#3AA0D8"), 0.2, 0.0, emit=(0.1, 0.55, 0.95), strength=1.3)
    eye = mat("cr_eye_flat", (0.75, 0.97, 1.0), 0.3, 0.0, emit=(0.45, 0.9, 1.0), strength=4.5)
    up = (0, 0, 1)
    Z = 1.5

    root = empty("Crow", (0, 0, 0))
    body = empty("Body", (0, 0, Z), root)
    tsecs = fera_dense([sec((0, 0.34, Z - 0.02), 0.05, 0.04), sec((0, 0.2, Z - 0.01), 0.12, 0.11),
                        sec((0, 0.0, Z), 0.16, 0.16, bk=1.15), sec((0, -0.16, Z + 0.04), 0.15, 0.16, bk=1.2),
                        sec((0, -0.26, Z + 0.08), 0.1, 0.11)], 14)
    sloft("Torso", tsecs, plum, body, sides=14, fwd=up, mats=(chest, plum_d),
          matf=lambda i, j: 1 if 8 <= j <= 12 and i >= 3 else 2 if j in (2, 3, 4) else 0, sharp=80.0)

    # ---------------- cabeça redonda, bico longo de gelo, olho aceso sob a sobrancelha, topete de penas
    head = empty("Head", (0, -0.26, Z + 0.1), body)
    hsecs = fera_dense([sec((0, -0.2, Z + 0.1), 0.085, 0.085), sec((0, -0.3, Z + 0.14), 0.11, 0.105),
                        sec((0, -0.4, Z + 0.14), 0.09, 0.085), sec((0, -0.45, Z + 0.13), 0.05, 0.05)], 12)
    sloft("HeadMesh", hsecs, plum, head, sides=14, fwd=up, mats=(plum_d,),
          matf=lambda i, j: 1 if j in (3, 4, 5) else 0, sharp=80.0)
    b0 = Vector((0, -0.42, Z + 0.13))
    sloft("Beak", [sec(b0, 0.05, 0.045), sec(b0 + Vector((0, -0.1, -0.01)), 0.032, 0.03),
                   sec(b0 + Vector((0, -0.2, -0.03)), 0.012, 0.014), sec(b0 + Vector((0, -0.24, -0.05)), 0.002, 0.002)],
          beak, head, sides=8, fwd=up)
    for s, nm in ((1, "L"), (-1, "R")):
        ec = fera_surf(hsecs, -0.36, 90 - s * 55, -0.004)
        _blob("Eye" + nm, ec, 0.022, 0.026, 0.02, eye, head, sides=10, rings=6)
        fera_curve("Brow" + nm, [fera_surf(hsecs, y, 90 - s * d, -0.006) for y, d in ((-0.31, 40), (-0.36, 36), (-0.41, 34))],
                   0.018, 0.008, plum_d, head, sides=8)
    for k, (y, h, lean) in enumerate(((-0.28, 0.12, 0.1), (-0.24, 0.1, 0.12), (-0.2, 0.08, 0.12))):   # topete
        base = fera_surf(hsecs, y, 90, -0.03)
        fera_tip("Crest%d" % k, base, base + Vector((0, lean, h)), 0.03, plum_d if k else crys_d, head, flat=0.4)

    # ---------------- asas: braço coberto de penas e cinco penas grandes em leque, pontas de cristal
    for s, nm in ((1, "L"), (-1, "R")):
        sh = Vector((s * 0.1, -0.06, Z + 0.06))
        wing = empty("Wing" + nm, sh, body)
        _blob(nm + "Shoulder", sh + Vector((s * 0.03, 0, 0)), 0.08, 0.1, 0.07, plum, wing, sides=12, rings=8)
        el = Vector((s * 0.42, -0.04, Z + 0.14))
        wr = Vector((s * 0.74, -0.1, Z + 0.14))
        sloft(nm + "Arm", fera_dense([sec(sh, 0.12, 0.05), sec(el, 0.17, 0.04), sec(wr, 0.09, 0.03)], 10), plum, wing,
              sides=10, fwd=up, axis=None, sharp=80.0)
        # cobertura: penas médias atrás do braço
        for k in range(6):
            a = sh.lerp(wr, 0.12 + k * 0.16)
            _feather("%sCovert%d" % (nm, k), a, a + Vector((s * (0.03 + k * 0.03), 0.36 - k * 0.025, -0.03)), 0.085,
                     plum_d if k % 2 else plum, wing)
        # primárias em leque a partir do punho
        for k, (ang, ln) in enumerate(((-28, 0.5), (-10, 0.56), (8, 0.54), (26, 0.48), (44, 0.42))):
            a = math.radians(ang)
            d = Vector((s * math.cos(a), math.sin(a), -0.03))
            _feather("%sPrimary%d" % (nm, k), wr - d * 0.06, wr + d * ln, 0.072, plum, wing, tipmat=crys, lift=0.01)
        _crystal(nm + "WristIce", wr + Vector((0, 0, 0.02)), (s * 0.4, -0.6, 0.6), 0.14, 0.03, (crys, crys_d), wing)

    # ---------------- cauda em leque e pés recolhidos com garras
    for k, ang in enumerate((-22, -11, 0, 11, 22)):
        a = math.radians(ang)
        p0 = Vector((0, 0.24, Z - 0.01))
        d = Vector((math.sin(a), math.cos(a), -0.12))
        _feather("Tail%d" % k, p0, p0 + d * (0.42 - abs(ang) * 0.004), 0.055, plum_d if k % 2 else plum, body,
                 tipmat=crys if k == 2 else None)
    for s, nm in ((1, "L"), (-1, "R")):
        hp = Vector((s * 0.06, 0.08, Z - 0.1))
        ft = Vector((s * 0.07, 0.2, Z - 0.24))
        fera_curve(nm + "LegMesh", [hp, hp.lerp(ft, 0.5) + Vector((0, 0.02, 0)), ft], 0.03, 0.02, claw, body)
        for k in range(3):
            c0 = ft + Vector(((k - 1) * 0.018, -0.005, 0))
            fera_curve(nm + "Talon%d" % k, [c0, c0 + Vector(((k - 1) * 0.01, -0.03, -0.02)),
                                            c0 + Vector(((k - 1) * 0.012, -0.05, 0.0))], 0.011, 0.002, claw, body, sides=6)

    for ob in coll.all_objects:
        if ob.type == 'MESH' and "Ice" not in ob.name:
            smooth_sharp(ob, 80.0)
    loose_parts("crow")
    export("crow")


# ================================================================== IETI GLACIAL
# Fera grande dos fossos (~2,4 m), curvada como um gorila: pelo branco-azulado, rosto, mãos e pés de pele azul,
# chifres de gelo curvos, ombros e antebraços cobertos de cristais (o gelo que ele bate no chão).
# Mesmos pivôs do Golem (scripts/enemies/enemy.gd, _animate_golem): LegL, LegR (no quadril), Body, Head (dentro de
# Body) e ArmL/ArmR (no ombro, DENTRO do tronco: a massa de pelo do ombro fica enterrada no corpo ao girar).
def build_yeti():
    fur = mat("y_fur", hexc("#E6EEF4"), 0.95)
    fur_d = mat("y_fur_d", hexc("#AFC0CE"), 0.95)
    skin = mat("y_skin", hexc("#6E97BC"), 0.75)
    skin_d = mat("y_skin_d", hexc("#46698C"), 0.75)
    mouth = mat("y_mouth", hexc("#2A1830"), 0.85)
    fang = mat("y_fang", hexc("#F4F6F8"), 0.5)
    claw = mat("y_claw", hexc("#2C3A4C"), 0.5)
    crys = mat("y_ice", hexc("#8FE6FF"), 0.2, 0.0, emit=(0.35, 0.85, 1.0), strength=1.6)
    crys_d = mat("y_ice_d", hexc("#3AA0D8"), 0.2, 0.0, emit=(0.1, 0.55, 0.95), strength=1.2)
    eye = mat("y_eye_flat", (0.75, 0.97, 1.0), 0.3, 0.0, emit=(0.45, 0.9, 1.0), strength=4.5)
    HIP = 0.88

    root = empty("Yeti", (0, 0, 0))

    # ---------------- tronco em pera invertida: barriga cheia, peito e ombros largos, corcunda peluda
    body = empty("Body", (0, 0, HIP), root)
    torso = fera_dense([sec((0, 0.02, HIP - 0.12), 0.32, 0.28), sec((0, 0.0, HIP + 0.12), 0.42, 0.36, fr=1.1),
                        sec((0, -0.04, 1.32), 0.5, 0.4, fr=1.1), sec((0, -0.06, 1.62), 0.58, 0.44),
                        sec((0, 0.06, 1.86), 0.5, 0.36), sec((0, 0.1, 2.0), 0.3, 0.26),
                        sec((0, 0.12, 2.06), 0.06, 0.06)], 16, cut=1)
    # peito e barriga de pele azul: faixa da frente do próprio tronco (sem placa por cima)
    sloft("Torso", torso, fur, body, sides=16, phase=0.0, sharp=80.0, mats=(skin,),
          matf=lambda i, j: 1 if j in (3, 4) and 3 <= i <= 11 else 0)
    # franja do pelo comprido descendo pelos lados e pela cintura
    for k, (z, d, ln) in enumerate(((0.8, 30, 0.2), (0.8, 150, 0.2), (0.78, 70, 0.16), (0.78, 110, 0.16),
                                    (0.8, 250, 0.2), (0.8, 290, 0.2), (1.2, 0, 0.18), (1.2, 180, 0.18))):
        p = _vsurf(torso, z, d, -0.05)
        r = math.radians(d)
        fera_tip("Fringe%d" % k, p, p + Vector((math.cos(r) * 0.06, -math.sin(r) * 0.06, -ln)), 0.09, fur_d, body,
                 flat=0.6)
    # gelo crescendo na corcunda
    for k, (z, dx, ln, rr) in enumerate(((1.86, 0.0, 0.42, 0.08), (1.76, 0.2, 0.32, 0.065), (1.74, -0.22, 0.36, 0.07),
                                         (1.56, 0.08, 0.26, 0.055))):
        base = _vsurf(torso, z, 270, -0.05) + Vector((dx, 0, 0))
        _crystal("BackIce%d" % k, base, (dx * 1.5, 0.8, 0.6), ln, rr, (crys, crys_d), body)

    # ---------------- cabeça baixa e afundada: rosto azul, sobrancelha de pelo, boca com presas, chifres de gelo
    head = empty("Head", (0, -0.34, 1.86), body)
    hsecs = fera_dense([sec((0, -0.28, 1.74), 0.2, 0.2), sec((0, -0.34, 1.9), 0.25, 0.24),
                        sec((0, -0.32, 2.06), 0.21, 0.2), sec((0, -0.3, 2.16), 0.1, 0.1),
                        sec((0, -0.29, 2.19), 0.02, 0.02)], 12, cut=1)
    sloft("HeadMesh", hsecs, fur, head, sides=14, phase=0.0, sharp=80.0)
    face = fera_dense([sec((0, -0.44, 1.78), 0.15, 0.08), sec((0, -0.5, 1.88), 0.17, 0.08),
                       sec((0, -0.5, 1.98), 0.15, 0.07), sec((0, -0.47, 2.04), 0.08, 0.04)], 10, cut=1)
    sloft("Face", face, skin, head, sides=14, phase=0.0, mats=(mouth,),
          matf=lambda i, j: 1 if i <= 2 and j in (2, 3, 4, 5) else 0, sharp=80.0)
    _blob("Muzzle", (0, -0.56, 1.86), 0.09, 0.06, 0.05, skin_d, head, sides=12, rings=8)
    for s, nm in ((1, "L"), (-1, "R")):
        c = Vector((s * 0.075, -0.56, 1.96))
        _blob("Eye" + nm, c, 0.04, 0.025, 0.03, eye, head, sides=10, rings=6)
        fera_curve("Brow" + nm, [Vector((s * 0.02, -0.56, 2.01)), Vector((s * 0.09, -0.57, 2.0)),
                                 Vector((s * 0.17, -0.52, 1.99))], 0.04, 0.025, fur_d, head, sides=8)
        fera_tip("Tusk" + nm, Vector((s * 0.07, -0.56, 1.8)), Vector((s * 0.085, -0.6, 1.9)), 0.022, fang, head)
        # chifre de gelo curvo: nasce da lateral da cabeça, vai para fora, sobe e volta para a frente
        h0 = Vector((s * 0.18, -0.34, 2.02))
        fera_curve("Horn" + nm, [h0, h0 + Vector((s * 0.14, 0.02, 0.06)), h0 + Vector((s * 0.22, -0.02, 0.2)),
                                 h0 + Vector((s * 0.2, -0.12, 0.3))], 0.06, 0.008, crys, head, sides=8)
    for k, (dx, h) in enumerate(((0.0, 0.16), (0.08, 0.12), (-0.08, 0.12))):   # topete de pelo
        base = Vector((dx, -0.32, 2.12))
        fera_tip("Tuft%d" % k, base, base + Vector((dx * 0.5, 0.1, h)), 0.07, fur, head, flat=0.6)
    # cabeça maior e mais à frente do corpo (a escala fica no nó: o código só gira a cabeça)
    head.scale = (1.3, 1.3, 1.3)
    head.location.y -= 0.05

    # ---------------- pernas curtas e grossas de pelo, pés azuis com garras
    for side, x in (("LegL", 0.26), ("LegR", -0.26)):
        s = 1 if x > 0 else -1
        leg = empty(side, (x, 0, HIP), root)
        lsecs = fera_dense([sec((x, 0.0, HIP + 0.1), 0.22, 0.24), sec((x + s * 0.03, -0.03, 0.55), 0.24, 0.25),
                            sec((x + s * 0.05, 0.0, 0.26), 0.2, 0.2), sec((x + s * 0.05, 0.0, 0.14), 0.17, 0.17)], 10)
        sloft(side + "_Mesh", lsecs, fur, leg, sides=12, phase=0.0, sharp=80.0)
        _blob(side + "_Foot", (x + s * 0.05, -0.1, 0.08), 0.17, 0.24, 0.09, skin, leg, sides=14, rings=8)
        for k, dx in enumerate((-0.09, 0.0, 0.09)):
            c0 = Vector((x + s * 0.05 + dx, -0.3, 0.07))
            fera_tip(side + "_Toe%d" % k, c0, c0 + Vector((0, -0.07, -0.05)), 0.03, claw, leg)

    # ---------------- braços longos de gorila: ombro de pelo enterrado no tronco, antebraço com manopla de gelo e
    # mão enorme de pele azul com três garras
    for side, x in (("ArmL", 0.62), ("ArmR", -0.62)):
        s = 1 if x > 0 else -1
        arm = empty(side, (s * 0.42, -0.04, 1.7), body)
        _blob(side + "_Shoulder", (x - s * 0.04, -0.04, 1.72), 0.3, 0.3, 0.28, fur, arm, sides=16, rings=10)
        elbow = Vector((x + s * 0.12, -0.06, 1.16))
        wrist = Vector((x + s * 0.14, -0.16, 0.6))
        sloft(side + "_Upper", fera_dense([sec((x, -0.04, 1.66), 0.2, 0.2), sec(elbow + Vector((0, 0, 0.1)), 0.17, 0.17),
                                           sec(elbow, 0.17, 0.17)], 8), fur, arm, sides=12, phase=0.0, sharp=80.0)
        sloft(side + "_Fore", fera_dense([sec(elbow, 0.18, 0.18), sec(elbow.lerp(wrist, 0.5), 0.22, 0.22),
                                          sec(wrist, 0.17, 0.17)], 8), fur_d, arm, sides=12, phase=0.0, sharp=80.0)
        hand = Vector((x + s * 0.15, -0.2, 0.44))
        _blob(side + "_Hand", hand, 0.2, 0.22, 0.19, skin, arm, sides=16, rings=10)
        for k, dx in enumerate((-0.11, 0.0, 0.11)):
            c0 = hand + Vector((dx, -0.18, -0.08))
            fera_curve(side + "_Claw%d" % k, [c0, c0 + Vector((0, -0.07, -0.02)), c0 + Vector((0, -0.1, -0.1))],
                       0.04, 0.004, claw, arm, sides=8)
        # manopla de gelo: cristais nascendo do antebraço para fora e para trás
        for k, (u, d, ln, rr) in enumerate(((0.3, (s * 0.9, 0.2, 0.3), 0.3, 0.07), (0.55, (s * 0.8, -0.3, 0.1), 0.26, 0.065),
                                            (0.75, (s * 0.7, 0.4, -0.1), 0.22, 0.055), (0.45, (s * 0.2, 0.9, 0.2), 0.2, 0.05))):
            _crystal("%s_Ice%d" % (side, k), elbow.lerp(wrist, u), d, ln, rr, (crys, crys_d), arm)
        # gelo no ombro
        for k, (d, ln, rr) in enumerate((((s * 0.4, 0.1, 1.0), 0.42, 0.085), ((s * 0.8, 0.3, 0.6), 0.32, 0.07),
                                         ((s * 0.6, -0.4, 0.7), 0.28, 0.06))):
            _crystal("%s_ShoulderIce%d" % (side, k), Vector((x + s * 0.04, -0.04, 1.88)), d, ln, rr, (crys, crys_d), arm)

    for ob in coll.all_objects:
        if ob.type == 'MESH' and "Ice" not in ob.name:
            smooth_sharp(ob, 80.0)
    loose_parts("yeti")
    export("yeti")


FROST_BUILDERS = {"wolf": build_wolf, "crow": build_crow, "yeti": build_yeti}
