# Monstros da Geleira de Cristal (mapa "mina"): Lobo da Geada (e o Alfa, o mesmo modelo tingido), Gralha-de-Cristal e
# Ieti Glacial. Executado por build_assets.py (usa os helpers de monsters.py, anime_body.py e body.py).
# Frente = -Y, Z para cima. Cada membro nasce de uma junta enterrada no corpo, com o pivô dentro do corpo: girando,
# a junta continua escondida e nada fica solto (loose_parts confere no build).


# ================================================================== LOBO DA GEADA
# Lobo magro de pelo azul-gelo (~0,85 m na cernelha), barriga clara, cauda espessa com a ponta branca, colar de pelo
# eriçado no pescoço e uma crista de cristais de gelo da nuca até o meio das costas; olhos gelados acesos.
# Pivôs animados por scripts/enemies/enemy.gd (_animate_wolf): Body (tronco), Head (dentro de Body), Jaw (dentro de
# Head), Tail > Tail2 (a cauda em dois ossos, dentro de Body) e as patas LegFL, LegFR, LegBL, LegBR (na raiz; o ombro/quadril é uma massa enterrada no
# tronco), cada uma com Knee<lado> (cotovelo/joelho) > Paw<lado> (punho/jarrete) e o marcador Foot<lado> no apoio.
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
    SIDES = 20
    dense, tip, curve, surf = fera_dense, fera_tip, fera_curve, fera_surf
    # colunas do anel de 20 lados com a frente do anel para cima: 5 = topo, 15 = barriga
    TOP = set(range(3, 8))
    BELLY = set(range(12, 19))

    root = empty("Wolf", (0, 0, 0))
    body = empty("Body", (0, 0.0, 0.8), root)

    # ---------------- tronco + pescoço numa peça só: garupa redonda, lombo fino com a barriga recolhida, peito fundo e
    # estreito, cernelha alta e o pescoço grosso de juba subindo até a nuca (a cabeça nasce dentro dele)
    torso = dense([sec((0, 0.62, 0.8), 0.05, 0.05),
                   sec((0, 0.56, 0.82), 0.13, 0.12),
                   sec((0, 0.44, 0.83), 0.15, 0.14, bk=1.0),
                   sec((0, 0.26, 0.82), 0.13, 0.12, bk=0.85),
                   sec((0, 0.06, 0.83), 0.14, 0.14, bk=1.15),
                   sec((0, -0.14, 0.85), 0.16, 0.17, bk=1.55),
                   sec((0, -0.3, 0.88), 0.165, 0.18, fr=1.15, bk=1.6),
                   sec((0, -0.42, 0.95), 0.17, 0.18, fr=1.1, bk=1.45),
                   sec((0, -0.52, 1.04), 0.16, 0.16, bk=1.3),
                   sec((0, -0.58, 1.12), 0.12, 0.12),
                   sec((0, -0.61, 1.16), 0.05, 0.05)], 30)
    n_t = len(torso)
    # escuro no dorso (sela), claro embaixo do peito até o queixo e na barriga
    def tmat(i, j):
        y = torso[min(i, n_t - 1)]["c"].y
        if j in BELLY and (y < -0.05 or j in (14, 15, 16)):
            return 2
        if j in TOP and -0.45 < y < 0.45:
            return 1
        return 0
    sloft("Torso", torso, fur, body, sides=SIDES, fwd=up, mats=(fur_d, belly), matf=tmat, sharp=80.0)
    # crista de cristais de gelo na cernelha, os maiores no meio, inclinados para trás
    for k, (y, ln, rr, lean, dx) in enumerate(((-0.4, 0.13, 0.035, 0.7, 0.0), (-0.3, 0.2, 0.045, 0.8, 0.0),
                                               (-0.19, 0.17, 0.04, 0.9, 0.0), (-0.08, 0.11, 0.03, 1.0, 0.0),
                                               (-0.25, 0.1, 0.028, 0.7, 0.05), (-0.22, 0.1, 0.028, 0.7, -0.05),
                                               (0.02, 0.07, 0.022, 1.1, 0.0))):
        base = surf(torso, y, 90 - math.degrees(math.atan2(dx, 0.2)), -0.03)
        _crystal("Spine%d" % k, base, (dx * 6.0, lean, 1.0), ln, rr, (crys, crys_d), body)

    # ---------------- cauda grossa e peluda, pendurada em curva, mais cheia no meio e com a ponta clara
    # dois ossos: Tail (na garupa, dentro do tronco) e Tail2 (no meio, leva a metade de baixo e a ponta), com uma bola
    # de pelo na junta; a ponta balança atrasada em relação à base
    tail = empty("Tail", (0, 0.56, 0.82), body)
    mid = Vector((0, 0.86, 0.72))
    tail2 = empty("Tail2", mid, tail)
    sloft("TailMesh", dense([sec((0, 0.5, 0.82), 0.06, 0.06), sec((0, 0.64, 0.83), 0.07, 0.07),
                             sec((0, 0.78, 0.79), 0.1, 0.1), sec(mid, 0.11, 0.105),
                             sec(mid + Vector((0, 0.03, -0.04)), 0.1, 0.095)], 14), fur, tail, sides=14, fwd=(0, 0, 1),
          mats=(fur_d,), matf=lambda i, j: 1 if j in (2, 3, 4, 5) else 0, sharp=80.0)
    _blob("TailBall", mid, 0.104, 0.1, 0.104, fur, tail2, sides=14, rings=8)
    t2 = dense([sec(mid + Vector((0, -0.02, 0.03)), 0.1, 0.095), sec(mid, 0.11, 0.105), sec((0, 0.95, 0.58), 0.11, 0.1),
                sec((0, 0.99, 0.46), 0.08, 0.075), sec((0, 1.0, 0.38), 0.045, 0.045), sec((0, 1.0, 0.33), 0.01, 0.01)], 16)
    sloft("TailTip", t2, fur, tail2, sides=14, fwd=(0, 0, 1), mats=(fur_d, belly),
          matf=lambda i, j: 2 if i >= 9 else (1 if j in (2, 3, 4, 5) else 0), sharp=80.0)

    # ---------------- cabeça: crânio largo com bochechas, testa marcada, focinho afinando, nariz, orelhas grandes
    head = empty("Head", (0, -0.56, 1.1), body)
    skull = dense([sec((0, -0.5, 1.16), 0.1, 0.1),
                   sec((0, -0.6, 1.19), 0.135, 0.12, bk=1.0),
                   sec((0, -0.7, 1.19), 0.125, 0.11, bk=0.9),
                   sec((0, -0.79, 1.16), 0.085, 0.085, bk=0.8),     # stop: onde a testa desce para o focinho
                   sec((0, -0.88, 1.13), 0.065, 0.065, bk=0.8),
                   sec((0, -0.96, 1.115), 0.055, 0.055, bk=0.8),
                   sec((0, -1.01, 1.11), 0.04, 0.042, bk=0.85),
                   sec((0, -1.03, 1.11), 0.01, 0.01)], 22, cut=2)
    in_mouth = lambda i: skull[min(i, len(skull) - 1)]["c"].y < -0.8
    # embaixo do focinho, o céu da boca é escuro (aparece com a boca aberta); os lados de baixo e a garganta, claros
    def skmat(i, j):
        y = skull[min(i, len(skull) - 1)]["c"].y
        if j in (14, 15, 16) and y < -0.78:
            return 3
        if j in BELLY and y < -0.62:
            return 2
        if j in TOP and y > -0.9:
            return 1
        return 0
    sloft("Skull", skull, fur, head, sides=SIDES, fwd=up, mats=(fur_d, belly, mouth), matf=skmat, sharp=80.0)
    _blob("Nose", surf(skull, -1.0, 35, -0.004), 0.034, 0.03, 0.026, nose, head, sides=14, rings=8)
    # orelhas grandes em ponta, de base larga e funda, viradas para a frente; dentro claro
    for s, nm in ((1, "L"), (-1, "R")):
        b0 = surf(skull, -0.6, 90 - s * 42, -0.03)
        tp = b0 + Vector((s * 0.06, 0.03, 0.2))
        sloft("Ear" + nm, dense([sec(b0, 0.07, 0.035), sec(b0.lerp(tp, 0.45), 0.055, 0.028), sec(tp, 0.005, 0.005)], 8),
              fur_d, head, sides=10, fwd=(0, -1, 0))
        ic = b0.lerp(tp, 0.3) + Vector((0, -0.022, 0))
        sloft("EarIn" + nm, dense([sec(ic, 0.04, 0.012), sec(ic.lerp(tp, 0.65), 0.018, 0.008)], 6), belly, head, sides=8,
              fwd=(0, -1, 0))
    # olhos amendoados gelados sob a sobrancelha escura
    for s, nm in ((1, "L"), (-1, "R")):
        e0, e1, e2 = surf(skull, -0.7, 34, -0.004), surf(skull, -0.735, 38, 0.004), surf(skull, -0.77, 32, -0.004)
        for e in (e0, e1, e2):
            e.x *= s
        sloft("Eye" + nm, [sec(e0, 0.003, 0.006), sec(e1, 0.012, 0.02), sec(e2, 0.003, 0.005)], eye, head, sides=8,
              fwd=(s, 0, 0.3))
        brow = [surf(skull, y, d, -0.004) for y, d in ((-0.68, 55), (-0.73, 50), (-0.78, 42))]
        for b in brow:
            b.x *= s
        curve("Brow" + nm, brow, 0.02, 0.008, fur_d, head, sides=8)
        for k, (y, ln) in enumerate(((-0.95, 0.04), (-0.89, 0.022))):     # presas de cima
            p = surf(skull, y, -50, -0.006)
            p.x *= s
            tip("Fang%s%d" % (nm, k), p, p + Vector((0, -0.004, -ln)), 0.011, fang, head)
    # mandíbula: dobradiça atrás do canto da boca (dentro da cabeça), corpo grosso afinando até o queixo; encaixa sob
    # o focinho com a boca fechada. Por fora pelo (lados) e claro (embaixo); por cima, a boca escura com a língua.
    jaw = empty("Jaw", (0, -0.66, 1.075), head)
    jraw = []
    # o topo da mandíbula sobe por dentro do focinho (metade da altura dela fica escondida): fechada, não abre fresta
    # nos lados, onde o focinho é redondo
    for y, w, h in ((-0.6, 0.8, 0.062), (-0.68, 0.86, 0.058), (-0.78, 0.86, 0.05), (-0.88, 0.84, 0.042),
                    (-0.95, 0.8, 0.033), (-0.99, 0.66, 0.022), (-1.005, 0.35, 0.01)):
        bot = surf(skull, y, -90).z
        jraw.append(sec((0, y, bot - h * 0.45), surf(skull, y, 0).x * w, h))
    jsecs = dense(jraw, 16, cut=1)
    sloft("JawMesh", jsecs, fur, jaw, sides=16, fwd=up, mats=(belly, mouth),
          matf=lambda i, j: 2 if (j in (3, 4, 5) and i <= 13) else 1 if j in (10, 11, 12, 13, 14) else 0, sharp=80.0)
    tg = [surf(jsecs, y, 90, -0.012) for y in (-0.66, -0.78, -0.9, -0.96)]
    sloft("Tongue", dense([sec(tg[0], 0.04, 0.012), sec(tg[1], 0.038, 0.012), sec(tg[2], 0.03, 0.01),
                           sec(tg[3], 0.012, 0.006)], 10), mouth, jaw, sides=10, fwd=up, sharp=80.0)
    for s in (1, -1):
        for k, (y, ln) in enumerate(((-0.95, 0.03), (-0.86, 0.016))):
            p = surf(jsecs, y, 65, -0.004)
            p.x *= s
            tip("LowFang%d%d" % (0 if s > 0 else 1, k), p, p + Vector((0, 0.002, ln)), 0.009, fang, jaw)

    # ---------------- patas em três ossos: Leg (ombro/quadril, a massa enterrada no tronco) > Knee (cotovelo/joelho) >
    # Paw (punho/jarrete, com a pata). Cada osso é um tubo liso só; na junta, o osso de baixo começa com uma bola do
    # mesmo tamanho do tubo (a dobra não mostra degrau).
    def paw(name, c, parent, s, front):
        sloft(name + "Pad", dense([sec(c + Vector((0, 0.04, 0.03)), 0.045, 0.04), sec(c + Vector((0, -0.01, 0.0)), 0.06, 0.035),
                                   sec(c + Vector((0, -0.06, -0.005)), 0.055, 0.028),
                                   sec(c + Vector((0, -0.085, -0.01)), 0.02, 0.012)], 10), fur_d, parent, sides=14,
              fwd=up, sharp=80.0)
        for k in range(4):
            dx = (k - 1.5) * 0.026
            c0 = c + Vector((dx, -0.075 + abs(dx) * 0.4, -0.012))
            _blob(name + "Toe%d" % k, c0, 0.019, 0.024, 0.017, fur_d, parent, sides=10, rings=6)
            fera_tip(name + "Claw%d" % k, c0 + Vector((0, -0.018, 0.0)), c0 + Vector((dx * 0.15, -0.045, -0.02)), 0.009,
                     claw, parent)

    LEGS = {
        # lado: (topo, junta 1, junta 2, apoio, raios (rx, ry) em cada ponto do tubo)
        True: ((-0.3, 0.8), (-0.23, 0.48), (-0.27, 0.15), (-0.31, 0.05),
               [(0.075, 0.13), (0.06, 0.08), (0.05, 0.058), (0.045, 0.05), (0.034, 0.036), (0.034, 0.034), (0.036, 0.034)]),
        False: ((0.42, 0.8), (0.3, 0.47), (0.47, 0.22), (0.43, 0.05),
                [(0.09, 0.17), (0.075, 0.12), (0.05, 0.06), (0.045, 0.06), (0.032, 0.036), (0.03, 0.032), (0.034, 0.033)]),
    }
    for side, s, front in (("LegFL", 1, True), ("LegFR", -1, True), ("LegBL", 1, False), ("LegBR", -1, False)):
        nm = side[3:]
        (ty, tz), (y1, z1), (y2, z2), (yf, zf), R = LEGS[front]
        x = s * (0.085 if front else 0.095)
        top, j1, j2, ft = Vector((x, ty, tz)), Vector((x, y1, z1)), Vector((x, y2, z2)), Vector((x, yf, zf))
        leg = empty(side, top, root)
        knee = empty("Knee" + nm, j1, leg)
        pawp = empty("Paw" + nm, j2, knee)
        empty("Foot" + nm, ft, pawp)
        # osso de cima: a massa do ombro/coxa enterrada no tronco afinando até a junta 1
        mid1 = top.lerp(j1, 0.5) + Vector((0, (-0.03 if front else 0.05), 0))
        sloft(side + "_Upper", dense([sec(top + Vector((0, 0, 0.06)), R[0][0] * 0.7, R[0][1] * 0.7), sec(top, *R[0]),
                                      sec(mid1, *R[1]), sec(j1, *R[2]),
                                      sec(j1 + (j1 - mid1).normalized() * 0.03, R[2][0] * 0.9, R[2][1] * 0.9)], 16),
              fur, leg, sides=16, fwd=(0, -1, 0),
              sharp=80.0)
        # osso do meio: antebraço (frente) ou gaskin (trás), grosso em cima, fino no punho/jarrete
        _blob(side + "_KneeBall", j1, R[2][0] * 0.95, R[2][1] * 0.95, R[2][0] * 0.95, fur, knee, sides=16, rings=10)
        mid2 = j1.lerp(j2, 0.35)
        sloft(side + "_Lower", dense([sec(j1 - (mid2 - j1).normalized() * 0.03, R[2][0] * 0.9, R[2][1] * 0.9),
                                      sec(j1, *R[2]), sec(mid2, *R[3]), sec(j2, *R[4])], 16), fur, knee, sides=16,
              fwd=(0, -1, 0), mats=(fur_d,), matf=lambda i, j: 1 if (front and i >= 13) else 0, sharp=80.0)
        # osso de baixo: metacarpo/metatarso até a pata (escuro, a "meia")
        _blob(side + "_AnkleBall", j2, R[4][0] * 0.95, R[4][1] * 0.95, R[4][0] * 0.95, fur_d, pawp, sides=14, rings=8)
        if not front:   # o calcanhar do jarrete aparece para trás
            fera_tip(side + "_Heel", j2 + Vector((0, 0.0, 0.0)), j2 + Vector((0, 0.05, 0.02)), 0.026, fur_d, pawp)
        sloft(side + "_Foot", dense([sec(j2, *R[4]), sec(j2.lerp(ft, 0.6), *R[5]), sec(ft + Vector((0, 0, 0.02)), *R[6])], 10),
              fur_d, pawp, sides=14, fwd=(0, -1, 0), sharp=80.0)
        paw(side + "_Paw", ft, pawp, s, front)

    for ob in coll.all_objects:
        if ob.type == 'MESH' and "Spine" not in ob.name:
            smooth_sharp(ob, 80.0)
    loose_parts("wolf")
    export("wolf")


# ================================================================== GRALHA-DE-CRISTAL
# Ave escura do tamanho de um cão (~1,9 m de asa a asa) que voa em volta e atira estilhaços de gelo: penas azul-noite,
# peito cinza-gelo, bico de gelo, olhos acesos e as pontas das penas grandes viradas em lascas de cristal.
# Pivôs animados por scripts/enemies/enemy.gd (_animate_crow): Body (a 1,5 m, sobe e desce no voo), Head e Tail (dentro
# de Body) e as asas em três ossos, WingL > WingL2 > WingL3 (ombro, cotovelo, punho; o mesmo à direita).
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

    # ---------------- asas em três ossos: Wing<L/R> (ombro, dentro do tronco) > Wing<L/R>2 (cotovelo) > Wing<L/R>3
    # (punho, com as penas grandes). Cada junta tem uma bola de penas no osso de fora, que tapa a dobra.
    for s, nm in ((1, "L"), (-1, "R")):
        sh = Vector((s * 0.1, -0.06, Z + 0.06))
        el = Vector((s * 0.42, -0.04, Z + 0.14))
        wr = Vector((s * 0.74, -0.1, Z + 0.14))
        wing = empty("Wing" + nm, sh, body)
        fore = empty("Wing" + nm + "2", el, wing)
        hand = empty("Wing" + nm + "3", wr, fore)
        _blob(nm + "Shoulder", sh + Vector((s * 0.03, 0, 0)), 0.08, 0.1, 0.07, plum, wing, sides=12, rings=8)
        sloft(nm + "Arm", fera_dense([sec(sh, 0.12, 0.05), sec(sh.lerp(el, 0.5), 0.15, 0.045), sec(el, 0.17, 0.04)], 8),
              plum, wing, sides=10, fwd=up, sharp=80.0)
        _blob(nm + "ElbowBall", el, 0.06, 0.16, 0.045, plum, fore, sides=12, rings=6)
        sloft(nm + "Forearm", fera_dense([sec(el, 0.17, 0.04), sec(el.lerp(wr, 0.5), 0.13, 0.035), sec(wr, 0.09, 0.03)], 8),
              plum, fore, sides=10, fwd=up, sharp=80.0)
        _blob(nm + "WristBall", wr, 0.05, 0.09, 0.035, plum, hand, sides=12, rings=6)
        # cobertura: penas médias atrás do braço (as de dentro no braço, as de fora no antebraço)
        for k in range(6):
            u = 0.12 + k * 0.16
            a = sh.lerp(wr, u)
            _feather("%sCovert%d" % (nm, k), a, a + Vector((s * (0.03 + k * 0.03), 0.36 - k * 0.025, -0.03)), 0.085,
                     plum_d if k % 2 else plum, wing if u < 0.5 else fore)
        # primárias em leque a partir do punho
        for k, (ang, ln) in enumerate(((-28, 0.5), (-10, 0.56), (8, 0.54), (26, 0.48), (44, 0.42))):
            a = math.radians(ang)
            d = Vector((s * math.cos(a), math.sin(a), -0.03))
            _feather("%sPrimary%d" % (nm, k), wr - d * 0.06, wr + d * ln, 0.072, plum, hand, tipmat=crys, lift=0.01)
        _crystal(nm + "WristIce", wr + Vector((0, 0, 0.02)), (s * 0.4, -0.6, 0.6), 0.14, 0.03, (crys, crys_d), hand)

    # ---------------- cauda em leque e pés recolhidos com garras
    tail = empty("Tail", (0, 0.24, Z - 0.01), body)
    for k, ang in enumerate((-22, -11, 0, 11, 22)):
        a = math.radians(ang)
        p0 = Vector((0, 0.2, Z - 0.01))
        d = Vector((math.sin(a), math.cos(a), -0.12))
        _feather("Tail%d" % k, p0, p0 + d * (0.42 - abs(ang) * 0.004), 0.055, plum_d if k % 2 else plum, tail,
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
# Pivôs animados por scripts/enemies/enemy.gd (_animate_yeti): LegL, LegR (no quadril), Body, Head (dentro de Body),
# ArmL/ArmR (no ombro, DENTRO do tronco: a massa de pelo do ombro fica enterrada no corpo ao girar) e ElbowL/ElbowR
# (o cotovelo, dentro do braço: antebraço, mão e manopla de gelo).
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
        fore = empty("Elbow" + side[3:], elbow, arm)      # antebraço, mão e manopla de gelo dobram no cotovelo
        _blob(side + "_ElbowBall", elbow, 0.18, 0.18, 0.18, fur_d, fore, sides=14, rings=8)
        sloft(side + "_Upper", fera_dense([sec((x, -0.04, 1.66), 0.2, 0.2), sec(elbow + Vector((0, 0, 0.1)), 0.17, 0.17),
                                           sec(elbow, 0.17, 0.17)], 8), fur, arm, sides=12, phase=0.0, sharp=80.0)
        sloft(side + "_Fore", fera_dense([sec(elbow, 0.18, 0.18), sec(elbow.lerp(wrist, 0.5), 0.22, 0.22),
                                          sec(wrist, 0.17, 0.17)], 8), fur_d, fore, sides=12, phase=0.0, sharp=80.0)
        hand = Vector((x + s * 0.15, -0.2, 0.44))
        _blob(side + "_Hand", hand, 0.2, 0.22, 0.19, skin, fore, sides=16, rings=10)
        for k, dx in enumerate((-0.11, 0.0, 0.11)):
            c0 = hand + Vector((dx, -0.18, -0.08))
            fera_curve(side + "_Claw%d" % k, [c0, c0 + Vector((0, -0.07, -0.02)), c0 + Vector((0, -0.1, -0.1))],
                       0.04, 0.004, claw, fore, sides=8)
        # manopla de gelo: cristais nascendo do antebraço para fora e para trás
        for k, (u, d, ln, rr) in enumerate(((0.3, (s * 0.9, 0.2, 0.3), 0.3, 0.07), (0.55, (s * 0.8, -0.3, 0.1), 0.26, 0.065),
                                            (0.75, (s * 0.7, 0.4, -0.1), 0.22, 0.055), (0.45, (s * 0.2, 0.9, 0.2), 0.2, 0.05))):
            _crystal("%s_Ice%d" % (side, k), elbow.lerp(wrist, u), d, ln, rr, (crys, crys_d), fore)
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
