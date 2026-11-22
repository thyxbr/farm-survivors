# Armadura do Cavaleiro Dragão (a_dragonknight, g_dragonknight, f_dragonknight), a partir da ficha em
# tools/blender/refs/elmo_dragao/ficha_completa.webp. Mesmo conjunto do elmo (dragon_helm.py).
# Executado por exec() depois de gear.py.
#
# Placas lisas feitas por código com os helpers de gear.py; as partes esculpidas (emblema do peito, cabeça de
# dragão da joelheira) vêm de malhas preparadas em tools/blender/base/, como o rosto do elmo.
# Materiais foscos (sem metal): com metal o toon do jogo escurece a cor e põe manchas de brilho, e o elmo é fosco.
# Como female.py decide o modo do busto pelo metal, as placas levam a propriedade fem_mode = "plate".


def dragonknight_mats():
    return dict(
        red=gm("drk_red", "#6C3232", 0.85), red_d=gm("drk_red_d", "#472022", 0.85),
        gold=gm("drk_gold", "#B8924C", 0.7), line=gm("drk_line", "#2A1012", 0.9),
        under=gm("drk_under", "#3E4047", 0.9),
        lea=gm("drk_leather", "#5E3D2B", 0.9), cloth=gm("drk_cloth", "#86282B", 0.9),
        bone=gm("drk_bone", "#D9CBA8", 0.8),
        gem=mat("drk_gem_flat", hexc("#E0531E"), 0.3, 0.0, emit=hexc("#FF6A20"), strength=1.2),
    )


def dragonknight_torso(K, src, body):
    """Tronco do Cavaleiro Dragão: casca cinza-escura (aparece nos flancos da barriga); peitoral vermelho liso
    do ombro até abaixo do peito, com a barra em bico para cima no meio (onde assenta o emblema) e friso de
    ouro grosso na barra e nas cavas; gola em pé com friso de ouro e abertura em V na frente; na barriga, três
    lâminas em V (ponta para baixo) entre dois frisos de ouro em pé; costal fechado com lâminas retas.
    Devolve (casca, peças)."""
    def under_keep(c, b, n):
        return not (b.startswith("Arm") or b.startswith("Elbow") or b.startswith("Knee")) and 0.86 <= c.z < 1.52
    under = cb_piece(src, "Under", under_keep, 0.006, K["under"])
    g_subdiv(under, 2)
    under["fem_mode"] = "plate"
    parts = []
    A = 1.45                           # meia largura do peitoral (rad); atrás disso é a cava e o costal
    AB = 0.86                          # meia largura do painel da barriga
    OFF = 0.022

    def half_w(u):                     # cava: estreito no ombro, abre até o flanco
        return 1.0 + (A - 1.0) * min(1.0, u / 0.7) ** 0.75

    def top_z(x):
        return 1.478 - 0.045 * x ** 4

    def bot_z(a):                      # barra em bico para cima no meio, caindo para os flancos
        x = min(1.0, abs(a) / 1.25)
        return 1.262 - 0.07 * x ** 0.85

    def chest(u, v):
        a = (2 * v - 1) * half_w(u)
        z = top_z(abs(2 * v - 1)) + (bot_z(a) - top_z(abs(2 * v - 1))) * u
        return wk_plate_pt(a, z, OFF, fr_max=1.03)
    ch, rr = _wk_plate("Chest", chest, 14, 48, K["red"], body, thick=0.006)
    parts.append(ch)
    hem = [q + _cz_rad(q) * 0.001 for q in rr[-1]]
    parts.append(cz_strip("ChestHem", hem, [_cz_rad(q) for q in hem], 0.02, 0.007, K["gold"], body))
    for sn, j in (("R", 0), ("L", -1)):
        col = [r[j] for r in rr][1:]
        parts.append(cz_strip("ArmholeTrim" + sn, col, [_cz_rad(q) for q in col], 0.013, 0.006, K["gold"], body))
    # ---- lâminas da barriga em V, cada uma por baixo da de cima
    for k in range(3):
        def lame(u, v, k=k):
            a = -AB + 2 * AB * v
            x = abs(a) / AB
            top = 1.262 - 0.068 * k
            bot = 1.176 - 0.068 * k - 0.05 * (1 - x) ** 1.1
            z = top + (bot - top) * u
            return wk_plate_pt(a, z, 0.019 - 0.0035 * k + 0.003 * u, keel=0.08, fr_max=1.03)
        lm, lr = _wk_plate("Lame%d" % k, lame, 8, 36, K["red"], body, thick=0.005)
        parts.append(lm)
        parts.append(g_pipe("LameLine%d" % k, [q + _cz_rad(q) * 0.0012 - Vector((0, 0, 0.001)) for q in lr[-1]],
                            0.0022, K["line"], body, sides=6))
    # ---- frisos de ouro em pé nas beiras do painel da barriga
    for sn, s in (("L", 1), ("R", -1)):
        col = [wk_plate_pt(s * AB, z, 0.019, fr_max=1.03) for z in (1.215, 1.17, 1.12, 1.07, 1.02, 0.99)]
        parts.append(cz_strip("BellyTrim" + sn, col, [_cz_rad(q) for q in col], 0.014, 0.007, K["gold"], body))
    # ---- costal e lâminas de trás
    B = math.pi - A

    def back(u, v):
        a = math.pi - B + 2 * B * v
        zt = 1.478 - 0.05 * abs(2 * v - 1) ** 4
        zb = 1.21 + 0.03 * abs(2 * v - 1) ** 2
        return wk_plate_pt(a, zt + (zb - zt) * u, OFF)
    bk, bkr = _wk_plate("Backplate", back, 12, 40, K["red"], body)
    parts.append(bk)
    bhem = [q + _cz_rad(q) * 0.001 for q in bkr[-1]]
    parts.append(cz_strip("BackHem", bhem, [_cz_rad(q) for q in bhem], 0.018, 0.007, K["gold"], body))
    for k in range(3):
        def blame(u, v, k=k):
            a = math.pi - 1.55 + 3.1 * v
            z = 1.225 - 0.068 * k - 0.085 * u
            return wk_plate_pt(a, z, 0.018 - 0.003 * k + 0.003 * u)
        lm, lr = _wk_plate("BackLame%d" % k, blame, 6, 44, K["red"], body, thick=0.005)
        parts.append(lm)
        parts.append(g_pipe("BackLameLine%d" % k, [q + _cz_rad(q) * 0.0012 for q in lr[-1]], 0.0022, K["line"],
                            body, sides=6))
    # ---- gola em pé e pala sobre os ombros (mesma cor do peitoral: lê como uma peça só)
    NG = 56

    def col_top(a):                    # abertura em V na frente
        return 1.546 - 0.05 * max(0.0, 1 - abs(a) / 0.55) ** 1.3

    def yoke_bot(a):
        x = min(1.0, abs(a) / 1.3)
        return 1.44 + 0.028 * x ** 0.8 - 0.03 * abs(math.sin(a)) ** 6

    def yoke_pt(j, u):
        a = math.atan2(math.sin(2 * math.pi * j / NG), math.cos(2 * math.pi * j / NG))
        zc = 1.497
        if u <= 0.4:
            t = u / 0.4
            z = col_top(a) - (col_top(a) - zc) * t
            rx = 0.104 + (0.112 - 0.104) * t ** 1.8
            ry = 0.096 + (0.104 - 0.096) * t ** 1.8
            return Vector((math.sin(a) * rx, 0.012 - math.cos(a) * ry, z))
        t = (u - 0.4) / 0.6
        z = 1.484 + (yoke_bot(a) - 1.484) * t
        q = wk_plate_pt(a, z, OFF + 0.0012, fr_max=1.03)
        if t < 0.34:
            c = Vector((math.sin(a) * 0.112, 0.012 - math.cos(a) * 0.104, zc))
            q = c.lerp(q, 0.55 + 0.45 * (t / 0.34))
        return q
    US = [0.0, 0.1, 0.2, 0.3, 0.4, 0.48, 0.58, 0.72, 0.86, 1.0]
    yoke = [[yoke_pt(j, u) for j in range(NG)] for u in US]
    parts.append(g_smooth_mesh("Yoke", yoke, K["red"], body, cap_end=False, thick=0.005, outward=True))
    # fundo da gola: fecha o vão entre a gola larga e o pescoço
    seat = [[Vector((math.sin(2 * math.pi * j / NG) * r * 1.07, 0.012 - math.cos(2 * math.pi * j / NG) * r, 1.5))
             for j in range(NG)] for r in (0.04, 0.075, 0.106)]
    parts.append(g_smooth_mesh("CollarSeat", seat, K["red_d"], body, cap_end=False, thick=0.004))
    rim = yoke[0]
    rim_n = [Vector((q.x, q.y - 0.012, 0)).normalized() for q in rim]
    parts.append(cz_strip("CollarRim", [q + Vector((0, 0, -0.004)) for q in rim], rim_n, 0.014, 0.006, K["gold"],
                          body, loop=True))
    return under, parts


def dragonknight_pauldron(K, src, body, s):
    """Ombreira do Cavaleiro Dragão: três placas sobrepostas (copa e duas lâminas), cada uma abrindo para fora
    numa ponta, com friso de ouro grosso na barra; friso de ouro em arco na beira de dentro (junto do pescoço);
    gema laranja engastada em ouro na frente, junto do peito; chifre cor de osso subindo do alto da copa e
    curvando para a cabeça."""
    sn = "L" if s > 0 else "R"
    parts = []
    PM = 2.25
    spec = [(0.05, 1.35, PM, 0.07, 0.004, 0.07), (1.0, 2.1, PM, 0.058, 0.004, 0.095), (1.8, 2.9, PM - 0.1, 0.046, 0.004, 0.105)]
    lames = _g_shoulder_dome(src, s, [l[:5] for l in spec], phis=40, rows=12, pull=0.3, cap=0.008, taper=True)
    top = None
    for k, ((rings, dirs, C), sp) in enumerate(zip(lames, spec)):
        # as pontas da grade são degeneradas (todas as fileiras no mesmo ponto): engrossar ali estoura os vértices
        rings, dirs = [r[1:-1] for r in rings], [r[1:-1] for r in dirs]
        n, nr = len(rings[0]), len(rings)
        tip = sp[5]
        slope = Vector((s * 0.72, 0, -0.69))        # telha: a placa desce inclinada para fora
        for i in range(nr):            # ponta: a barra avança para fora no meio da placa
            w = i / (nr - 1)
            for j in range(n):
                u = abs(-1 + 2 * j / (n - 1))
                rings[i][j] = rings[i][j] + slope * (tip * w ** 1.5 * (0.35 + 0.65 * max(0.0, 1 - u / 0.8) ** 1.5))
        parts.append(g_smooth_mesh("Pauldron%s%d" % (sn, k), rings, K["red"], body, cap_end=False, closed=False,
                                   thick=0.006, outward=True))
        edge = [rings[-1][j] + dirs[-1][j] * 0.001 for j in range(n)]
        parts.append(cz_strip("PauldronTrim%s%d" % (sn, k), edge, dirs[-1], 0.016, 0.007, K["gold"], body))
        if k == 0:
            top = (rings, dirs)
            # friso de dentro: sobe por uma ponta da copa, passa pelo alto e desce pela outra
            a = [(rings[i][2], dirs[i][2]) for i in range(nr - 1, 0, -1)]
            b = [(rings[i][n - 3], dirs[i][n - 3]) for i in range(0, nr)]
            arc = a + b
            parts.append(cz_strip("PauldronArc" + sn, [q + d * 0.001 for q, d in arc], [d for _, d in arc], 0.026,
                                  0.012, K["gold"], body))
        else:                          # traço escuro no meio da lâmina (desenho da ficha)
            m = nr // 2
            parts.append(g_pipe("PauldronLine%s%d" % (sn, k), [rings[m][j] + dirs[m][j] * 0.0012 for j in range(3, n - 3)],
                                0.002, K["line"], body, sides=6))
    rings, dirs = top
    n, nr = len(rings[0]), len(rings)
    # ---- gema na frente, junto do peito (frente = φ·s > 0)
    jg = (n - 1) * (0.5 + s * 0.34)
    q, d = _dk_grid_at(rings, dirs, nr - 2.6, jg)
    up = Vector((0, 0, 1))
    t1 = (up - d * up.dot(d)).normalized()
    parts.append(g_cap("PauldronBezel" + sn, q - d * 0.002, d, t1, 0.037, 0.037, 0.011, K["gold"], body, rings=4, sides=20))
    parts.append(g_cap("PauldronGem" + sn, q + d * 0.004, d, t1, 0.026, 0.026, 0.012, K["gem"], body, rings=5, sides=18))
    # ---- chifre: nasce no alto da copa, sobe e curva para a cabeça
    q, d = _dk_grid_at(rings, dirs, nr * 0.72, (n - 1) * (0.5 - s * 0.06))
    inw = Vector((-s, 0, 0))
    P0 = q - d * 0.02
    P1 = P0 + up * 0.09 - inw * 0.05
    P2 = P0 + up * 0.19 - inw * 0.035
    P3 = P0 + up * 0.25 + inw * 0.06
    NH = 18
    path = [P0 * (1 - t) ** 3 + P1 * 3 * t * (1 - t) ** 2 + P2 * 3 * t * t * (1 - t) + P3 * t ** 3
            for t in (i / NH for i in range(NH + 1))]
    rad = [(0.046 * (1 - i / NH) ** 0.8 + 0.0015,) * 2 for i in range(NH + 1)]
    parts.append(g_smooth_mesh("PauldronHorn" + sn, g_curved_tube(path, rad, sides=14), K["bone"], body))
    parts.append(g_pipe("PauldronHornSeat" + sn, [P0 + d * 0.021 + (t1 * math.cos(a) + d.cross(t1) * math.sin(a)) * 0.047
                                                  for a in (2 * math.pi * k / 20 for k in range(20))], 0.006, K["gold"],
                        body, sides=8, loop=True))
    return parts


def dragonknight_arm(K, src, body, s):
    """Braço do Cavaleiro Dragão: manga cinza-escura com uma correia de couro acima do cotovelo; braçal de
    escamas vermelhas pelo lado de fora do antebraço (o de dentro fica na manga), com moldura de ouro grossa em
    toda a volta, a borda de cima subindo numa ponta sobre o cotovelo, anel de ouro no punho, desenho de
    escamas em losango e três espinhos cor de osso por fora, perto do cotovelo."""
    from mathutils.bvhtree import BVHTree
    sn = "L" if s > 0 else "R"
    tmp = cb_piece(src, "ArmProbe" + sn, lambda c, b, n: (b.startswith("Arm") or b.startswith("Elbow")) and c.x * s > 0)
    bvh = BVHTree.FromPolygons([v.co.copy() for v in tmp.data.vertices], [tuple(p.vertices) for p in tmp.data.polygons])
    bpy.data.objects.remove(tmp, do_unlink=True)
    L1, L2, at, coords, ring = _gb_arm_frame(s)
    parts = []
    # ---- correia de couro acima do cotovelo
    sr, sd, _ = _mt_tube(bvh, at, s, 0.78 * L1, 0.87 * L1, NR=3, NP=32, add=lambda t: 0.0125)
    parts.append(g_smooth_mesh("ArmStrap" + sn, sr, K["lea"], body, cap_end=False, thick=0.004, outward=True))
    # ---- braçal
    NR, NP, J = 16, 40, 12

    def vadd(t):
        return 0.013 + 0.012 * max(0.0, 1 - t / 0.3) ** 1.6 + 0.006 * max(0.0, (t - 0.8) / 0.2) ** 1.5
    vr, vd, vc = _mt_tube(bvh, at, s, L1 + 0.04 * L2, L1 + 0.9 * L2, NR=NR, NP=NP, add=vadd)
    c0, ax0 = at(L1 + 0.04 * L2)
    for j in range(NP):                # borda de cima sobe numa ponta do lado de fora (sobre o cotovelo)
        w = max(0.0, math.cos(2 * math.pi * j / NP)) ** 4
        if w > 0.01:
            vr[0][j] = vr[0][j] - ax0 * 0.05 * w + vd[0][j] * 0.006 * w
            vr[1][j] = vr[1][j] - ax0 * 0.024 * w + vd[1][j] * 0.003 * w

    def at_phi(i, ph, out=0.0):
        x = (ph % (2 * math.pi)) / (2 * math.pi) * NP
        j = int(x) % NP
        k = (j + 1) % NP
        f = x - int(x)
        return vr[i][j].lerp(vr[i][k], f) + vd[i][j].lerp(vd[i][k], f) * out, vd[i][j].lerp(vd[i][k], f).normalized()
    cols = list(range(-J, J + 1))
    grid = [[vr[i][j % NP] for j in cols] for i in range(NR + 1)]
    dgrid = [[vd[i][j % NP] for j in cols] for i in range(NR + 1)]
    parts.append(g_smooth_mesh("Vambrace" + sn, grid, K["red"], body, cap_end=False, closed=False, thick=0.005,
                               outward=True))
    # moldura de ouro: as duas beiras compridas, a borda de cima e o anel do punho
    for nm, c in (("A", 0), ("B", len(cols) - 1)):
        parts.append(cz_strip("VambraceSide%s%s" % (sn, nm), [grid[i][c] + dgrid[i][c] * 0.001 for i in range(NR + 1)],
                              [dgrid[i][c] for i in range(NR + 1)], 0.015, 0.006, K["gold"], body))
    parts.append(cz_strip("VambraceTop" + sn, [q + d * 0.001 for q, d in zip(grid[0], dgrid[0])], dgrid[0], 0.017,
                          0.007, K["gold"], body))
    parts.append(cz_strip("VambraceCuff" + sn, [q + d * 0.001 for q, d in zip(vr[NR - 1], vd[NR - 1])], vd[NR - 1],
                          0.022, 0.007, K["gold"], body, loop=True))
    # desenho de escamas: duas famílias de traços em diagonal (losangos)
    PH = 2 * math.pi * (J - 1.6) / NP
    for fam, sl in (("a", 1), ("b", -1)):
        for k in range(-4, 9):
            line = []
            for i in range(1, NR - 1):
                ph = -PH + k * 0.95 + (i - 1) * 0.24 if sl > 0 else PH - k * 0.95 - (i - 1) * 0.24
                if abs(ph) < PH:
                    line.append(at_phi(i, ph, 0.0012)[0])
            if len(line) >= 3:
                parts.append(g_pipe("VambraceScale%s%s%d" % (sn, fam, k), line, 0.002, K["line"], body, sides=6))
    # espinhos por fora, perto do cotovelo
    for k, (i, ln) in enumerate(((2, 0.05), (6, 0.044), (10, 0.038))):
        q, d = at_phi(i, -0.45 * s, 0.0)
        dr = (d - ax0 * 0.3).normalized()
        parts.append(g_cone("ArmSpike%s%d" % (sn, k), [q - dr * 0.006, q + dr * ln * 0.5 - ax0 * 0.004,
                                                       q + dr * ln - ax0 * 0.012], 0.016, K["bone"], body, sides=10))
    return parts


def build_a_dragonknight():
    """Placas do Cavaleiro Dragão (lendário nv 50). Rodadas 1-3: tronco, ombreiras e braços; mangas e pernas na casca cinza-escura até
    as próximas peças."""
    style = "a_dragonknight"
    P, R = g_rig(style)
    M = g_mats()
    K = dragonknight_mats()
    body = R["Body"]
    rig, src = _cb_start(M)
    neck(R, M["skin"])
    hips(R, K["under"])
    g_skinned_pants(src, K["under"])
    under, parts = dragonknight_torso(K, src, body)
    shoulder = dragonknight_pauldron(K, src, body, 1) + dragonknight_pauldron(K, src, body, -1)
    arms = dragonknight_arm(K, src, body, 1) + dragonknight_arm(K, src, body, -1)
    sleeves = cb_piece(src, "Sleeves", lambda c, b, n: (b.startswith("Arm") or b.startswith("Elbow"))
                       and (not b.startswith("Elbow") or _cb_fore_t(c) < 0.86), 0.01, K["under"])
    g_subdiv(sleeves)
    g_loose_world(style)
    os.makedirs(OUT + "gear", exist_ok=True)
    targets = [o for o in scn.objects if o.type == 'MESH']
    bake_ao(targets, _occluders(style, P, R, M))
    cel_paint(targets, skip=("g_skin", "drk_gem_flat"))
    horns = [o for o in shoulder if "Horn" in o.name]        # rígidos: peso por vértice esticava a ponta
    plates = [o for o in shoulder if o not in horns]
    g_skin_finish(rig, src, [(arms, "vert", ("ArmL", "ArmR", "ElbowL", "ElbowR"), 1.0), (plates, "vert", ("Body", "ArmL", "ArmR"), 1.0),
                             (horns, "fn", lambda q: {"Body": 0.6, ("ArmL" if q.x > 0 else "ArmR"): 0.4}, 1.0)])
    join_objs("DragonKnight", parts + shoulder + arms)["fem_mode"] = "plate"
    g_export_skinned(style)
