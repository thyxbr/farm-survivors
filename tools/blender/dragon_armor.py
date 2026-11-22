# Armadura do Cavaleiro Dragão (a_dragonknight, g_dragonknight, f_dragonknight), a partir da ficha em
# tools/blender/refs/elmo_dragao/ficha_completa.webp. Mesmo conjunto do elmo (dragon_helm.py).
# Executado por exec() depois de gear.py.
#
# Placas lisas feitas por código com os helpers de gear.py; as partes esculpidas (emblema do peito, cabeça de
# dragão da joelheira) vêm de malhas preparadas em tools/blender/base/, como o rosto do elmo.
# Materiais foscos (sem metal): com metal o toon do jogo escurece a cor e põe manchas de brilho, e o elmo é fosco.
# Como female.py decide o modo do busto pelo metal, as placas levam a propriedade fem_mode = "plate".


# Paletas do conjunto: "" = Cavaleiro Dragão (vermelho e ouro); "dark" = versão sombria. Cada variante tem materiais
# próprios (drk_<variante>_*), então os itens existentes não mudam de cor.
DRK_PALETTES = {
    "": dict(red="#6C3232", red_d="#472022", gold="#B8924C", line="#2A1012", under="#3E4047", lea="#5E3D2B",
             cloth="#6B2226", bone="#D9CBA8", gem=("#C8401A", "#E0401A", 0.35), sole="#1E1A1A"),
    # placas pretas (sem tom de cor), vermelho-sangue só nos traços das escamas, bordas em bronze envelhecido no lugar do ouro
    # (contrasta com o preto), gemas de brasa; chifres e garras em marfim cinzento
    "dark": dict(red="#151517", red_d="#0C0C0E", gold="#A9875A", line="#A3121E", under="#121214", lea="#1E1612",
                 cloth="#1C0C10", bone="#A39A88", gem=("#E8301C", "#FF4A1A", 0.5), sole="#0E0D0E"),
}


def dragonknight_mats(variant=""):
    c = DRK_PALETTES[variant]
    pre = "drk_" + (variant + "_" if variant else "")
    return dict(
        red=gm(pre + "red", c["red"], 0.85), red_d=gm(pre + "red_d", c["red_d"], 0.85),
        gold=gm(pre + "gold", c["gold"], 0.7), line=gm(pre + "line", c["line"], 0.9),
        under=gm(pre + "under", c["under"], 0.9),
        lea=gm(pre + "leather", c["lea"], 0.9), cloth=gm(pre + "cloth", c["cloth"], 0.9),
        bone=gm(pre + "bone", c["bone"], 0.8),
        gem=mat(pre + "gem_flat", hexc(c["gem"][0]), 0.3, 0.0, emit=hexc(c["gem"][1]), strength=c["gem"][2]),
        sole=gm(pre + "sole", c["sole"], 0.9),
    )


def _drk_knee_head(K, gold=False):
    """Cabeça de dragão da joelheira: o rosto esculpido do elmo (dragon_face_base.blend), reduzido a poucos
    polígonos e sem textura. As cores vêm da cor por vértice que o preparo do elmo guardou: claro e pouco
    saturado vira osso (chifres, dentes), amarelo vivo vira ouro (olhos), o resto é o vermelho das placas.
    Com gold=True é o emblema do peito: tudo em ouro, com os olhos na cor da gema.
    Devolve a malha em coordenadas do elmo (cabeça do jogo), ainda sem dono."""
    import numpy as np
    with bpy.data.libraries.load(DH_BASE) as (src, dst):
        dst.objects = [n for n in src.objects if n == "DragonFace"]
    ob = dst.objects[0]
    coll.objects.link(ob)
    mod = ob.modifiers.new("Dec", 'DECIMATE')
    mod.ratio = 3200 / max(1, len(ob.data.polygons))
    with bpy.context.temp_override(active_object=ob, object=ob, selected_objects=[ob], selected_editable_objects=[ob]):
        bpy.ops.object.modifier_apply(modifier="Dec")
    me = ob.data
    ca = me.color_attributes["Col"]
    c = np.empty(len(ca.data) * 4, np.float32)
    ca.data.foreach_get("color", c)
    c = c.reshape(-1, 4)[:, :3]
    me.materials.clear()
    for m in ((K["gold"], K["gold"], K["gem"], K["gold"]) if gold else (K["red"], K["bone"], K["gold"], K["red_d"])):
        me.materials.append(m)
    cnt = [0, 0, 0, 0]
    for pl in me.polygons:
        r, g, b = c[list(pl.loop_indices)].mean(0)
        v = max(r, g, b)
        sat = (v - min(r, g, b)) / max(v, 1e-4)
        if v > 0.42 and sat < 0.5:
            k = 1
        elif r > 0.55 and g > 0.3 and b < 0.3:
            k = 2
        else:
            k = 0
        pl.material_index = k
        pl.use_smooth = True
        cnt[k] += 1
    for a in list(me.color_attributes):
        me.color_attributes.remove(a)
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    return ob


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
    # ---- emblema: o rosto do dragão em ouro no meio do peito, em relevo (o mesmo rosto do elmo, achatado)
    em = _drk_knee_head(K, gold=True)
    ec = wk_plate_pt(0.0, 1.335, OFF, fr_max=1.03)
    ES = 0.3
    em.data.transform(Matrix.Translation(Vector((0, ec.y - 0.012, 1.335)) - _wloc(body))
                      @ Matrix.Diagonal((ES, ES * 0.3, ES, 1.0)) @ Matrix.Translation(Vector((0, -0.06, -1.7))))
    em.parent = body
    em.location = (0, 0, 0)
    em["wloc"] = list(_wloc(body))
    em.name = "ChestEmblem"
    parts.append(em)
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
    up = Vector((0, 0, 1))
    for gn, sg in (("", 1), ("Back", -1)):          # a vista de costas da ficha mostra a mesma gema atrás
        jg = (n - 1) * (0.5 + s * sg * 0.34)
        q, d = _dk_grid_at(rings, dirs, nr - 2.6, jg)
        t1 = (up - d * up.dot(d)).normalized()
        parts.append(g_cap("PauldronBezel%s%s" % (gn, sn), q - d * 0.002, d, t1, 0.037, 0.037, 0.011, K["gold"], body,
                           rings=4, sides=20))
        parts.append(g_cap("PauldronGem%s%s" % (gn, sn), q + d * 0.004, d, t1, 0.026, 0.026, 0.012, K["gem"], body,
                           rings=5, sides=18))
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


def dragonknight_skirt(K, src, body):
    """Cintura do Cavaleiro Dragão: cinto de couro com passadores de ouro e, na frente, gema laranja oval
    engastada em ouro; escarcela de escamas vermelhas em cada quadril, em ponta para baixo, com moldura de ouro
    grossa; placa de escamas atrás; pano vermelho comprido no meio da frente, com a barra em ponta, debrum de
    ouro, um painel em ponta desenhado no alto e chamas de ouro desenhadas junto da barra.
    Devolve (cinto, escarcelas, placa de trás, pano)."""
    from mathutils.bvhtree import BVHTree
    belt = []
    NB = 72
    rings = [[wk_plate_pt(2 * math.pi * j / NB, z, 0.027) for j in range(NB)] for z in (1.012, 0.995, 0.972, 0.955)]
    belt.append(g_smooth_mesh("Belt", rings, K["lea"], body, cap_end=False, thick=0.006, outward=True))
    for k, a in enumerate((-0.62, 0.62, math.pi - 0.7, math.pi + 0.7)):
        col = [wk_plate_pt(a, z, 0.0285) for z in (1.018, 1.0, 0.983, 0.966, 0.949)]
        belt.append(cz_strip("BeltLoop%d" % k, col, [_cz_rad(q) for q in col], 0.013, 0.005, K["gold"], body))
    C = wk_plate_pt(0.0, 0.983, 0.03)
    n0 = Vector((0, -1, 0))
    belt.append(g_cap("BeltBezel", C, n0, (1, 0, 0), 0.04, 0.05, 0.012, K["gold"], body, rings=4, sides=24))
    belt.append(g_cap("BeltGem", C + n0 * 0.006, n0, (1, 0, 0), 0.027, 0.036, 0.013, K["gem"], body, rings=5,
                      sides=20))
    # ---- escarcelas de escamas
    tas = []
    for sn, s in (("L", 1), ("R", -1)):
        def plate(u, v, s=s):
            a_in = 0.44 + 0.1 * u
            a = (a_in + (2.05 - a_in) * v) * s
            zb = 0.6 + 0.2 * abs(v - 0.5) ** 1.15
            z = 0.962 + (zb - 0.962) * u
            return _wk_hip_pt(a, z, 0.036 + 0.02 * u)
        ob, rr = _wk_plate("Tasset" + sn, plate, 16, 36, K["red"], body, thick=0.005)
        tas.append(ob)
        edge = [r[0] for r in rr] + rr[-1][1:] + [r[-1] for r in rr][::-1][1:]
        edge = [q + _cz_rad(q) * 0.001 for q in edge]
        tas.append(cz_strip("TassetTrim" + sn, edge, [_cz_rad(q) for q in edge], 0.02, 0.007, K["gold"], body))
        # escamas: fileiras de arcos em U, desencontradas
        for r in range(6):
            u0 = 0.06 + 0.135 * r
            for c in range(-1, 5):
                v0 = 0.1 + 0.2 * (c + 0.5 * (r % 2))
                line = []
                for f in (i / 8 for i in range(9)):
                    v, u = v0 + 0.2 * f, u0 + 0.12 * math.sin(math.pi * f) ** 0.7
                    if 0.09 < v < 0.91 and u < 0.9:
                        q = plate(u, v)
                        line.append(q + _cz_rad(q) * 0.0015)
                if len(line) >= 3:
                    tas.append(g_pipe("TassetScale%s%d_%d" % (sn, r, c), line, 0.0021, K["line"], body, sides=6))

    # ---- placa de escamas atrás
    def rear(u, v):
        a = 2.05 + (2 * math.pi - 4.1) * v
        zb = 0.72 - 0.05 * math.sin(math.pi * v)
        return _pal_hip_pt(a, 0.962 + (zb - 0.962) * u, 0.034 + 0.016 * u)
    rb, rrr = _wk_plate("RearPlate", rear, 10, 44, K["red"], body, thick=0.005)
    back = [rb]
    edge = [q + _cz_rad(q) * 0.001 for q in rrr[-1]]
    back.append(cz_strip("RearTrim", edge, [_cz_rad(q) for q in edge], 0.018, 0.007, K["gold"], body))
    for r in range(4):
        u0 = 0.08 + 0.2 * r
        for c in range(-1, 9):
            v0 = 0.02 + 0.11 * (c + 0.5 * (r % 2))
            line = []
            for f in (i / 8 for i in range(9)):
                v, u = v0 + 0.11 * f, u0 + 0.17 * math.sin(math.pi * f) ** 0.7
                if 0.02 < v < 0.98 and u < 0.9:
                    q = rear(u, v)
                    line.append(q + _cz_rad(q) * 0.0015)
            if len(line) >= 3:
                back.append(g_pipe("RearScale%d_%d" % (r, c), line, 0.0021, K["line"], body, sides=6))
    # ---- pano do meio da frente
    probe = cb_piece(src, "LegProbe", lambda c, b, n: (b.startswith("Leg") or b.startswith("Knee")
                                                         or b == "Body") and c.z < 1.0)
    pb = BVHTree.FromPolygons([probe.matrix_world @ v.co for v in probe.data.vertices],
                              [tuple(p.vertices) for p in probe.data.polygons])
    bpy.data.objects.remove(probe, do_unlink=True)
    pb_plates = _mt_bvh(tas)
    NZ, NX, HW, ZT, ZB = 26, 16, 0.082, 0.95, 0.4
    cols = []
    for j in range(NX + 1):
        x = -HW + 2 * HW * j / NX
        zend = ZB + 0.085 * abs(x) / HW
        col, yp = [], None
        for i in range(NZ + 1):
            z = ZT - (ZT - zend) * (i / NZ)
            y = -0.08
            for bv in (pb, pb_plates):
                h = bv.ray_cast(Vector((x, -0.6, z)), Vector((0, 1, 0)))
                if h[0] is not None:
                    y = min(y, h[0].y - 0.014)
            yp = y if yp is None else min(yp, y)
            fold = 0.006 * math.cos(math.pi * x / HW) * min(1.0, i / 6)
            col.append(Vector((x, yp - fold, z)))
        cols.append(col)
    grid = [[cols[j][i] for j in range(NX + 1)] for i in range(NZ + 1)]
    mid = [g_smooth_mesh("FrontCloth", grid, K["cloth"], body, cap_end=False, closed=False, thick=0.003,
                         outward=True)]

    def on(xf, t, out=0.0035):          # ponto do pano: xf em -1..1 (largura), t em 0..1 (cinto -> barra)
        x = (xf + 1) / 2 * NX
        j = min(NX - 1, int(x))
        y = t * NZ
        i = min(NZ - 1, int(y))
        a = grid[i][j].lerp(grid[i][j + 1], x - j)
        b = grid[i + 1][j].lerp(grid[i + 1][j + 1], x - j)
        return a.lerp(b, y - i) + Vector((0, -out, 0))
    yn = [Vector((0, -1, 0))]
    # debrum de ouro pelos lados e pela barra em ponta
    hem = ([on(-0.86, t) for t in (0.04, 0.2, 0.4, 0.6, 0.8, 0.93)]
           + [on(xf, 0.95) for xf in (-0.86, -0.6, -0.3, 0.0, 0.3, 0.6, 0.86)]
           + [on(0.86, t) for t in (0.93, 0.8, 0.6, 0.4, 0.2, 0.04)])
    mid.append(cz_strip("ClothHem", hem, yn * len(hem), 0.008, 0.003, K["gold"], body))
    # painel em ponta desenhado no alto
    pan = [on(-0.55, 0.03), on(-0.55, 0.3), on(0.0, 0.42), on(0.55, 0.3), on(0.55, 0.03)]
    mid.append(g_pipe("ClothPanel", pan, 0.003, K["gold"], body, sides=6))
    # chamas de ouro junto da barra: de cada lado, duas línguas subindo da barra
    for sd in (-1, 1):
        for k, (x0, h, lean) in enumerate(((0.58, 0.26, -0.1), (0.24, 0.17, 0.06))):
            t0 = 0.9 - 0.035 * k
            pts = [on(sd * (x0 + 0.13), t0), on(sd * (x0 + lean * 0.4 + 0.1), t0 - h * 0.5),
                   on(sd * (x0 + lean), t0 - h), on(sd * (x0 + lean * 0.4 - 0.1), t0 - h * 0.45),
                   on(sd * (x0 - 0.13), t0)]
            mid.append(g_pipe("ClothFlame%d_%d" % (sd, k), pts, 0.0034, K["gold"], body, sides=6))
    return belt, tas, back, mid


def _drk_cape_w(p):
    """Capa: no alto com o tronco; da cintura para baixo vai em boa parte com a coxa do seu lado, para o pé de
    trás na passada não atravessar o pano."""
    leg = max(0.0, min(1.0, (0.98 - p.z) / 0.4)) * 0.72
    left = max(0.0, min(1.0, 0.5 + p.x / 0.2))
    return {"Body": 1.0 - leg, "LegL": leg * left, "LegR": leg * (1 - left)}


def dragonknight_cape(K, body):
    """Capa do Cavaleiro Dragão: pano vermelho preso no alto das costas entre as ombreiras, com uma dobra caída
    em U sob a gola; desce abrindo até a canela em poucas pregas largas, com os cantos da barra mais baixos;
    na barra, duas linhas de ouro onduladas, duas chamas no meio e um risco em gancho em cada canto."""
    rows, NC = 22, 34
    ZT, ZB = 1.47, 0.3
    WRAP = 1.0

    def need(a, z):                    # ponto mínimo por fora do costal, da placa de trás e das escarcelas
        if z > 1.0:
            return wk_plate_pt(a, z, 0.044)
        return _pal_hip_pt(a, min(z, 0.99), 0.066 + 0.02 * (1.0 - z))

    def center_need(z):
        return max(q.y + WRAP * q.x ** 2 for q in (need(math.pi + 0.07 * k, z) for k in range(-9, 10)))
    zs = [ZT - (ZT - ZB) * i / 24 for i in range(25)]
    nd = [center_need(z) for z in zs]
    for k in range(81):                # a reta mais em pé que passa por fora de tudo
        slope = 0.005 * k
        yt = max(n - slope * (ZT - z) for n, z in zip(nd, zs))
        if yt - nd[0] <= 0.03:
            break

    def cpt(u, v, out=0.0):            # u: 0 em cima -> 1 embaixo; v: 0 -> 1 de um lado ao outro
        w = 2 * v - 1
        zb = ZB - 0.035 * abs(w) ** 2.2
        z = ZT - (ZT - zb) * u
        x = (0.165 + 0.15 * u ** 0.85) * w
        fold = 0.02 * math.sin(2 * math.pi * v * 3.5 + 0.5) * u ** 0.9
        y = yt + slope * (ZT - z) - WRAP * x * x * (1 - 0.45 * u) + fold + out
        return Vector((x, y, z))
    grid = [[cpt(i / rows, j / NC) for j in range(NC + 1)] for i in range(rows + 1)]
    parts = [g_smooth_mesh("Cape", grid, K["cloth"], body, cap_end=False, closed=False, thick=0.004, outward=True)]
    for sd in (-1, 1):                 # fechos de ouro: prendem os cantos de cima da capa no costal
        q = cpt(0.02, 0.5 + sd * 0.42)
        a = math.atan2(q.x, 0.0) if False else math.pi - sd * 0.75
        t = wk_plate_pt(a, q.z - 0.01, 0.02)
        parts.append(g_pipe("CapeClasp%d" % sd, [q + Vector((0, 0.003, 0)), q.lerp(t, 0.5) + Vector((0, 0, 0.004)), t],
                            0.008, K["gold"], body, sides=8))
    # dobra caída em U sob a gola
    NU, NV = 8, 20
    cowl = []
    for i in range(NU + 1):
        u = i / NU
        row = []
        for j in range(NV + 1):
            v = j / NV
            w = 2 * v - 1
            sag = math.sin(math.pi * v) ** 0.8
            q = cpt(0.0, 0.5 + 0.48 * w)
            row.append(Vector((q.x, q.y + 0.012 + 0.03 * math.sin(math.pi * u) * sag,
                               ZT + 0.012 - (0.02 + 0.12 * sag) * u)))
        cowl.append(row)
    parts.append(g_smooth_mesh("CapeCowl", cowl, K["cloth"], body, cap_end=False, closed=False, thick=0.006,
                               outward=True))
    parts.append(g_pipe("CapeCowlFold", [q + Vector((0, 0.004, -0.002)) for q in cowl[-1]], 0.005, K["red_d"], body,
                        sides=8))
    # desenho de ouro na barra
    O = 0.004
    for k, (u0, amp, ph) in enumerate(((0.925, 0.012, 0.0), (0.955, 0.008, 1.2))):
        line = [cpt(u0 - amp * math.sin(2 * math.pi * 2 * v + ph), v, O) for v in (0.04 + 0.92 * j / 40 for j in range(41))]
        parts.append(g_pipe("CapeLine%d" % k, line, 0.0032, K["gold"], body, sides=6))
    for sd in (-1, 1):                 # chamas em crescente no meio
        pts = [cpt(0.925 - 0.085 * f, 0.5 + sd * (0.03 + 0.035 * math.sin(math.pi * f) + 0.012 * f), O)
               for f in (i / 8 for i in range(9))]
        rad = [(0.0055 * (1 - i / 8) ** 0.8 + 0.001,) * 2 for i in range(9)]
        parts.append(g_smooth_mesh("CapeFlame%d" % sd, g_curved_tube(pts, rad, sides=8), K["gold"], body))
        hook = [cpt(0.93, 0.5 + sd * 0.34, O), cpt(0.9, 0.5 + sd * 0.4, O), cpt(0.875, 0.5 + sd * 0.43, O),
                cpt(0.895, 0.5 + sd * 0.455, O)]
        parts.append(g_pipe("CapeHook%d" % sd, hook, 0.003, K["gold"], body, sides=6))
    return parts


def _build_a_dragonknight(style, variant, cape=True):
    """Placas do Cavaleiro Dragão (lendário nv 50). Tronco com emblema, ombreiras, braços, cintura e capa; mangas e pernas na casca cinza-escura até
    as próximas peças."""
    P, R = g_rig(style)
    M = g_mats()
    K = dragonknight_mats(variant)
    body = R["Body"]
    rig, src = _cb_start(M)
    neck(R, M["skin"])
    hips(R, K["under"])
    g_skinned_pants(src, K["under"])
    under, parts = dragonknight_torso(K, src, body)
    shoulder = dragonknight_pauldron(K, src, body, 1) + dragonknight_pauldron(K, src, body, -1)
    arms = dragonknight_arm(K, src, body, 1) + dragonknight_arm(K, src, body, -1)
    belt, tas, rear, mid = dragonknight_skirt(K, src, body)
    cape = dragonknight_cape(K, body) if cape else []
    sleeves = cb_piece(src, "Sleeves", lambda c, b, n: (b.startswith("Arm") or b.startswith("Elbow"))
                       and (not b.startswith("Elbow") or _cb_fore_t(c) < 0.86), 0.01, K["under"])
    g_subdiv(sleeves)
    g_loose_world(style)
    os.makedirs(OUT + "gear", exist_ok=True)
    targets = [o for o in scn.objects if o.type == 'MESH']
    bake_ao(targets, _occluders(style, P, R, M))
    cel_paint(targets, skip=("g_skin",))
    horns = [o for o in shoulder if "Horn" in o.name]        # rígidos: peso por vértice esticava a ponta
    plates = [o for o in shoulder if o not in horns]
    g_skin_finish(rig, src, [(tas, "fn", _cs_tasset_w, 1.0), (mid, "fn", _wk_cloth_w, 1.0),
                             ] + ([(cape, "fn", _drk_cape_w, 1.0)] if cape else []) + [
                             (rear, "fn", _gb_skirt_w, 1.0), (arms, "vert", ("ArmL", "ArmR", "ElbowL", "ElbowR"), 1.0), (plates, "vert", ("Body", "ArmL", "ArmR"), 1.0),
                             (horns, "fn", lambda q: {"Body": 0.6, ("ArmL" if q.x > 0 else "ArmR"): 0.4}, 1.0)])
    join_objs("DragonKnight", parts + shoulder + arms + belt + tas + rear + mid + cape)["fem_mode"] = "plate"
    g_export_skinned(style)


def _build_g_dragonknight(style, variant):
    """Manoplas do Cavaleiro Dragão: mão de placa vermelha (fechada e aberta) com traços escuros separando as
    falanges, um losango cor de osso em cada nó dos dedos e garras cor de osso: na mão aberta continuam a ponta
    de cada dedo e do polegar; na mão fechada (pontas dos dedos escondidas) saem dos nós. Punho curto de
    placa com friso de ouro grosso na boca e anel de ouro no pulso."""
    from mathutils.bvhtree import BVHTree
    P, R = g_rig(style)
    K = dragonknight_mats(variant)
    N = 24
    for n, s in (("L", 1), ("R", -1)):
        S = limb_sections(P, s)
        elbow = R["Elbow" + n]
        F = S["fore"]
        hd, o, ay, up, pt = _hand_frame(P, s)
        fist = soft_fist("Arm" + n, P, s, K["red"], elbow)
        hand = relaxed_hand("Arm" + n, P, s, K["red"], elbow)
        fp, op = [fist], [hand]
        bpy.context.view_layer.update()
        down = -up.normalized()
        dia = [(0.0, 0.0085), (0.0055, 0.0), (0.0, -0.0085), (-0.0055, 0.0)]
        for lst, ob, nm in ((fp, fist, "Fist"), (op, hand, "Open")):
            vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
            bvh = BVHTree.FromPolygons(vs, [tuple(p.vertices) for p in ob.data.polygons])
            zs = [v.z for v in vs]
            zk = (max(zs) - min(zs))
            rows = {}
            for k, fz in enumerate((0.5, 0.22, -0.02, -0.24)):
                line = []
                for j in range(11):
                    y = -0.035 + 0.07 * j / 10
                    c = pt(0, y / hd, -(fz * zk) / hd)
                    h = bvh.ray_cast(c + o * 0.2, -o)
                    if h[0] is not None:
                        line.append(h[0] + o * 0.0015)
                if len(line) > 3:
                    rows[k] = line
                    if k > 0:
                        lst.append(g_pipe("Arm%s_Seg%s%d" % (n, nm, k), line, 0.0022, K["line"], elbow, sides=6))
            kn = rows.get(1 if nm == "Fist" else 0)
            if kn and len(kn) > 6:     # losangos de osso: nos nós dos dedos (mão aberta) ou nas costas da mão (fechada)
                for m in range(4):
                    q = kn[int(round(1 + m * (len(kn) - 3) / 3))]
                    lst.append(g_plate("Arm%s_Stud%s%d" % (n, nm, m), dia, q + o * 0.002, ay, up, 0.004, K["bone"],
                                       elbow))
            tip = rows.get(0)
            if nm == "Fist" and tip and len(tip) > 6:      # mão fechada: as pontas dos dedos ficam dentro do punho,
                for m in range(4):                         # então as garras saem dos nós, para fora e para baixo
                    q = tip[int(round(1 + m * (len(tip) - 3) / 3))]
                    path = [q - o * 0.004, q + o * 0.014 + down * 0.006, q + o * 0.021 + down * 0.026]
                    claw = g_curved_tube(path, [(0.0068, 0.0058), (0.004, 0.0035), (0.0006, 0.0006)], sides=8)
                    lst.append(g_smooth_mesh("Arm%s_Claw%s%d" % (n, nm, m), claw, K["bone"], elbow))
        # garras da mão aberta: continuam a última falange de cada dedo (mesma conta de relaxed_hand)
        for q, (y, sp, zb, f, w, cu) in enumerate(((-0.0325, -0.007, -0.086, 0.95, 1.0, 0), (-0.0108, -0.002, -0.089, 1.0, 1.04, 4),
                                                   (0.0108, 0.003, -0.087, 0.93, 0.98, 9), (0.0315, 0.008, -0.081, 0.76, 0.86, 14))):
            cur = (-0.006, zb)
            for L, a in ((0.042, 14 + cu), (0.027, 36 + cu * 1.5), (0.023, 54 + cu * 2)):
                t = math.radians(a)
                d = (-math.sin(t), -math.cos(t))
                cur = (cur[0] + d[0] * L * f, cur[1] + d[1] * L * f)
            yy = y + sp
            m = math.hypot(d[0] * 0.25, d[1] - 1.0)          # garra comprida, quase reta: aparece pelas costas da mão
            e = (d[0] * 0.25 / m, (d[1] - 1.0) / m)
            op.append(g_cone("Arm%s_Claw%d" % (n, q), [pt(cur[0] - d[0] * 0.007, yy, cur[1] - d[1] * 0.007),
                                                      pt(cur[0] + e[0] * 0.02, yy, cur[1] + e[1] * 0.02),
                                                      pt(cur[0] + e[0] * 0.047, yy, cur[1] + e[1] * 0.047)],
                             0.0098 * hd * w, K["bone"], elbow, sides=8))
        op.append(g_cone("Arm%s_ClawThumb" % n, [pt(-0.016, -0.0625, -0.088), pt(-0.02, -0.065, -0.105),
                                                 pt(-0.028, -0.064, -0.122)], 0.0078 * hd, K["bone"], elbow, sides=8))
        cuff = [_rg_ring(sample(F, t), 1.08, add, n=N) for t, add in ((0.8, 0.017), (0.88, 0.012), (1.0, 0.008))]
        cp = [g_smooth_mesh("Arm%s_Cuff" % n, cuff, K["red"], elbow, cap_end=False, thick=0.004, outward=True),
              g_pipe("Arm%s_CuffRim" % n, cuff[0], 0.0055, K["gold"], elbow, sides=8, loop=True),
              g_pipe("Arm%s_CuffWrist" % n, cuff[-1], 0.0055, K["gold"], elbow, sides=8, loop=True)]
        join_objs("Arm%s_Hand" % n, fp)
        join_objs("Arm%s_HandOpen" % n, op)
        join_objs("Arm%s_Gauntlet" % n, cp)
    g_export(style, P, R)


def _build_f_dragonknight(style, variant):
    """Grevas do Cavaleiro Dragão: volta do joelho e canela em casca cinza-escura; greva de escamas vermelhas
    pela frente e pelos lados da canela (desenho em losango), com a borda de cima em V e friso de ouro grosso
    nela, e anel de ouro no tornozelo; joelheira em cabeça de dragão com chifres (o rosto do elmo, em miniatura);
    bota de placa vermelha com lâminas no peito do pé e sola escura."""
    P, R = g_rig(style)
    K = dragonknight_mats(variant)
    sole = K["sole"]
    N = 32
    A = 1.95
    head0 = _drk_knee_head(K)
    HS = 0.36                          # escala da cabeça (o focinho encurtado: a ficha tem cabeça curta no joelho)
    for n, s in (("L", 1), ("R", -1)):
        S = limb_sections(P, s)
        sh, th = S["shin"], S["thigh"]
        knee, ankle = R["Knee" + n], R["Ankle" + n]
        KJ = mirror(P["knee"], s)
        parts = []
        kn = grow(span(th, 0.86, 1.0), 1.05, 0.006) + grow(span(sh, 0.0, 0.24), 1.05, 0.006)[1:]
        parts.append(g_smooth_mesh("Leg%s_KneeJoint" % n, [_rg_ring(x, n=N) for x in kn], K["under"], knee,
                                   cap_end=False))

        def gp(t, a, add):
            q = sample(sh, t)
            rx, ry = q["rx"] * 1.06 + add, q["ry"] * 1.06 + add
            x, y = cb_spt(a, rx, ry, q.get("fr", 1.0), q.get("bk", 1.0), keel=0.06)
            return Vector((q["c"].x + x, q["c"].y + y, q["c"].z))

        def gn(t, a):
            q = gp(t, a, 0.0)
            c = sample(sh, t)["c"]
            return Vector((q.x - c.x, q.y - c.y, 0)).normalized()
        # ---- casca cinza da canela inteira
        ts = [0.13 + 0.86 * i / 15 for i in range(16)]
        parts.append(g_smooth_mesh("Leg%s_Shin" % n, [[gp(t, 2 * math.pi * j / N, 0.007) for j in range(N)] for t in ts],
                                   K["under"], knee, cap_end=False, thick=0.004, outward=True))

        # ---- greva de escamas: frente e lados, borda de cima em V
        def top_t(a):
            return 0.15 + 0.1 * max(0.0, 1 - abs(a) / 1.3) ** 1.1

        def plate(u, v):
            a = -A + 2 * A * v
            t = top_t(a) + (0.95 - top_t(a)) * u
            fl = 0.014 * max(0.0, (t - 0.82) / 0.13) ** 1.6
            return gp(t, a, 0.014 + fl)
        NRW, NCL = 16, 30
        grid = [[plate(i / NRW, j / NCL) for j in range(NCL + 1)] for i in range(NRW + 1)]
        parts.append(g_smooth_mesh("Leg%s_Greave" % n, grid, K["red"], knee, cap_end=False, closed=False, thick=0.005,
                                   outward=True))
        top = [plate(0.0, j / NCL) for j in range(NCL + 1)]
        topn = [gn(top_t(-A + 2 * A * j / NCL), -A + 2 * A * j / NCL) for j in range(NCL + 1)]
        parts.append(cz_strip("Leg%s_GreaveTop" % n, [q + d * 0.001 for q, d in zip(top, topn)], topn, 0.022, 0.008,
                              K["gold"], knee))
        ank = [gp(0.93, 2 * math.pi * j / N, 0.017) for j in range(N)]
        ankn = [gn(0.93, 2 * math.pi * j / N) for j in range(N)]
        parts.append(cz_strip("Leg%s_GreaveAnkle" % n, ank, ankn, 0.026, 0.008, K["gold"], knee, loop=True))
        # desenho de escamas em losango
        for fam in (1, -1):
            for k in range(-5, 9):
                line = []
                for i in range(1, 13):
                    u = 0.1 + 0.8 * (i - 1) / 11
                    a = (-A + 0.2 + k * 0.62 + (i - 1) * 0.2) * fam
                    if abs(a) < A - 0.18:
                        q = plate(u, (a + A) / (2 * A))
                        line.append(q + gn(0.5, a) * 0.0013)
                if len(line) >= 3:
                    parts.append(g_pipe("Leg%s_Scale%d_%d" % (n, fam > 0, k), line, 0.002, K["line"], knee, sides=6))
        # ---- joelheira: cabeça de dragão
        hd = head0.copy()
        hd.data = head0.data.copy()
        coll.objects.link(hd)
        kc = Vector((KJ.x, KJ.y - 0.058, KJ.z + 0.01))        # nuca da cabeça encostada na frente do joelho
        T = (Matrix.Translation(kc - _wloc(knee)) @ Matrix.Diagonal((HS, HS * 0.68, HS, 1.0))
             @ Matrix.Translation(Vector((0, -0.06, -1.7))))
        hd.data.transform(T)
        hd.parent = knee
        hd.location = (0, 0, 0)
        hd["wloc"] = list(_wloc(knee))
        hd.name = "Leg%s_KneeHead" % n
        parts.append(hd)
        join_objs("Leg%s_Boot" % n, parts)
        # ---- bota de placa
        f = P["ft"]
        ft = _foot_secs(P, s, 1.07, 0.006)
        zmin = 0.02 * f

        def fring(sc, k=1.0):
            return [sc["c"] + Vector((math.sin(a) * sc["rx"] * k, 0, 0)) +
                    Vector((0, 0, max(zmin - sc["c"].z, math.cos(a) * sc["ry"] * k * 0.86)))
                    for a in (2 * math.pi * j / N for j in range(N))]
        h0 = ft[0]
        hc = dict(h0, c=h0["c"] + Vector((0, 0.014 * f, 0.006)))
        frs = [fring(hc, 0.02), fring(dict(h0, c=h0["c"] + Vector((0, 0.011 * f, 0.004))), 0.5), fring(h0, 0.9)]
        frs += [fring(x) for x in ft]
        frs.append(fring(dict(ft[-1], c=ft[-1]["c"] + Vector((0, -0.02 * f, -0.002))), 0.1))
        shoe = g_smooth_mesh("Leg%s_Foot" % n, frs, K["red"], ankle, outward=True)
        foot = [shoe, foot_sole("Leg%s_Sole" % n, ft, sole, ankle, f, heel=0.01 * f)]
        for k, i in enumerate((1, 2, 3, 4)):
            if i >= len(ft) - 1:
                break
            b = ft[i]
            arc = [b["c"] + Vector((math.sin(t) * (b["rx"] * 1.0 + 0.003), 0,
                                    max(zmin - b["c"].z + 0.004, math.cos(t) * (b["ry"] * 0.86 + 0.003))))
                   for t in (-1.7 + 3.4 * m / 14 for m in range(15))]
            foot.append(g_pipe("Leg%s_SabatonLame%d" % (n, k), arc, 0.003, K["line"], ankle, sides=6))
        join_objs("Leg%s_BootFoot" % n, foot)
    bpy.data.objects.remove(head0, do_unlink=True)
    g_loose_world(style)
    g_export(style, P, R)


def build_a_dragonknight():
    _build_a_dragonknight("a_dragonknight", "")


def build_g_dragonknight():
    _build_g_dragonknight("g_dragonknight", "")


def build_f_dragonknight():
    _build_f_dragonknight("f_dragonknight", "")


def build_a_dragonknight_dark():
    _build_a_dragonknight("a_dragonknight_dark", "dark", cape=False)    # a capa é um item das costas (c_dragonknight_dark)


def build_g_dragonknight_dark():
    _build_g_dragonknight("g_dragonknight_dark", "dark")


def build_f_dragonknight_dark():
    _build_f_dragonknight("f_dragonknight_dark", "dark")
