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


def build_a_dragonknight():
    """Placas do Cavaleiro Dragão (lendário nv 50). Rodada 1: tronco; mangas e pernas na casca cinza-escura até
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
    sleeves = cb_piece(src, "Sleeves", lambda c, b, n: (b.startswith("Arm") or b.startswith("Elbow"))
                       and (not b.startswith("Elbow") or _cb_fore_t(c) < 0.86), 0.01, K["under"])
    g_subdiv(sleeves)
    g_loose_world(style)
    os.makedirs(OUT + "gear", exist_ok=True)
    targets = [o for o in scn.objects if o.type == 'MESH']
    bake_ao(targets, _occluders(style, P, R, M))
    cel_paint(targets, skip=("g_skin", "drk_gem_flat"))
    g_skin_finish(rig, src, [])
    join_objs("DragonKnight", parts)["fem_mode"] = "plate"
    g_export_skinned(style)
