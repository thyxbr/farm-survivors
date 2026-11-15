# Corpo liso no estilo do estudo de personagem (docs/ESTUDO_PERSONAGEM_ANIME.md, "Torso", "Braços" e
# "Pernas e botas"): tronco em grade de anéis com material por faixa, roupa como casca sobre o corpo,
# membros em loft liso, botas com cano e pé em loft, dobras sugeridas por rolos, frisos e tiras em relevo
# assentados na superfície.
# Executado dentro de build_assets.py, depois de characters.py, body.py e anime.py: usa as seções de body.py
# (sec, sample, grow, _frames, _ring, limb_sections), os decalques de anime.py (_fan, _decal) e os pesos de rig.py.
# Sem subdivisão: o liso vem do sombreado (normais suaves) e a aresta, do ângulo entre as faces (smooth_sharp).
import bmesh, math
from mathutils import Vector
from mathutils.bvhtree import BVHTree


def smooth_sharp(ob, angle=55.0):
    """Sombreado liso, com aresta viva onde as faces vizinhas fazem mais que angle graus (tampas, barras)."""
    for p in ob.data.polygons:
        p.use_smooth = True
    ob.data.set_sharp_from_angle(angle=math.radians(angle))
    return ob


def sloft(name, secs, material, parent=None, sides=8, phase=0.5, caps=(True, True), axis=None, fwd=(0, -1, 0),
          matf=None, mats=(), sharp=55.0, bvh=False):
    """Loft liso pelas seções de body.py (sec). matf(segmento, coluna) -> índice do material (material é o 0,
    mats os seguintes). Tampas em leque. bvh=True devolve (objeto, BVHTree em coordenadas de mundo), para
    assentar tiras e decalques na superfície."""
    fr = _frames(secs, axis, fwd)
    bm = bmesh.new()
    vr = [[bm.verts.new(p) for p in _ring(s, side, f, sides, phase, None, 0.0)] for s, (t, side, f) in zip(secs, fr)]
    # os anéis giram no sentido anti-horário em volta do eixo: esta ordem deixa as faces para fora
    for i, (a, b) in enumerate(zip(vr, vr[1:])):
        for j in range(sides):
            k = (j + 1) % sides
            f = bm.faces.new((a[j], a[k], b[k], b[j]))
            if matf:
                f.material_index = matf(i, j)
    for end, on in ((0, caps[0]), (-1, caps[1])):
        if not on:
            continue
        c = bm.verts.new(secs[end]["c"])
        for j in range(sides):
            k = (j + 1) % sides
            f = bm.faces.new((c, vr[0][k], vr[0][j]) if end == 0 else (c, vr[-1][j], vr[-1][k]))
            if matf:
                f.material_index = matf(0 if end == 0 else len(vr) - 2, j)
    if bvh:
        bm.normal_update()      # find_nearest devolve a normal da face: sem isto ela vem zerada
    tree = BVHTree.FromBMesh(bm) if bvh else None
    print("PART", name, "sloft", flush=True)
    bmesh.ops.translate(bm, vec=-_wloc(parent), verts=bm.verts)
    ob = _finish(name, bm, material, parent, smooth=True)
    for m in mats:
        ob.data.materials.append(m)
    smooth_sharp(ob, sharp)
    return (ob, tree) if bvh else ob


def sec_at(secs, z):
    """Seção interpolada na altura z de uma tabela de anéis horizontais (z crescente)."""
    if z <= secs[0]["c"].z:
        return dict(secs[0], c=Vector((secs[0]["c"].x, secs[0]["c"].y, z)))
    for a, b in zip(secs, secs[1:]):
        if z <= b["c"].z:
            return _mix(a, b, (z - a["c"].z) / (b["c"].z - a["c"].z))
    return dict(secs[-1], c=Vector((secs[-1]["c"].x, secs[-1]["c"].y, z)))


def sec_y(s, x, back=False):
    """y da superfície da seção s (anel horizontal) na posição lateral x: frente (-Y) ou costas."""
    k = min(1.0, abs(x) / s["rx"])
    d = s["ry"] * (s["bk"] if back else s["fr"]) * (1.0 - k ** s["sq"]) ** (1.0 / s["sq"])
    return s["c"].y + (d if back else -d)


def xf_secs(secs, pivot, rot, new_pivot):
    """Leva as seções para outra pose: gira os centros em volta de pivot e reassenta em new_pivot."""
    return [dict(q, c=new_pivot + rot @ (q["c"] - pivot)) for q in secs]


def plate(name, P, material, parent=None, matf=None, mats=(), thick=0.012, tdir=(0, 1, 0), back_from=None, sharp=40.0):
    """Placa de roupa sobre o corpo (avental, bolso): grade P[linha][coluna] de pontos de mundo, linhas de cima
    para baixo e colunas de -X a +X (a face olha para -Y). thick dá a espessura ao longo de tdir, com a borda
    fechada; as costas só são fechadas da linha back_from para baixo (onde a placa se solta do corpo).
    matf(linha, coluna) -> índice do material (barra, friso)."""
    bm = bmesh.new()
    F = [[bm.verts.new(p) for p in row] for row in P]
    cells = []
    for r in range(len(P) - 1):
        for c in range(len(P[0]) - 1):
            f = bm.faces.new((F[r][c], F[r + 1][c], F[r + 1][c + 1], F[r][c + 1]))
            if matf:
                f.material_index = matf(r, c)
            cells.append((r, c, f.material_index))
    if thick:
        td = Vector(tdir) * thick
        B = [[bm.verts.new(v.co + td) for v in row] for row in F]
        back = {v: b for fr_, br_ in zip(F, B) for v, b in zip(fr_, br_)}
        for e in [e for e in bm.edges if len(e.link_faces) == 1]:
            l = e.link_loops[0]
            a, b = l.vert, l.link_loop_next.vert
            f = bm.faces.new((b, a, back[a], back[b]))
            f.material_index = l.face.material_index
        for r, c, mi in cells:
            if back_from is not None and r >= back_from:
                f = bm.faces.new((B[r][c], B[r][c + 1], B[r + 1][c + 1], B[r + 1][c]))
                f.material_index = mi
    print("PART", name, "plate", flush=True)
    bmesh.ops.translate(bm, vec=-_wloc(parent), verts=bm.verts)
    ob = _finish(name, bm, material, parent, smooth=True)
    for m in mats:
        ob.data.materials.append(m)
    return smooth_sharp(ob, sharp)


def surf_band(bm, pts, hw, bvh, thick=0.004, edge=0.7):
    """Tira em relevo (alça, friso, gola) assentada na superfície de bvh: o caminho pts é desenhado perto da
    peça e cada vértice gruda no ponto mais próximo dela. Seção de 4 vértices: duas bordas rentes e o dorso a
    thick da superfície. hw = meia-largura (número ou lista por ponto)."""
    hws = hw if isinstance(hw, (list, tuple)) else [hw] * len(pts)

    def snap(p):
        loc, n, _, _ = bvh.find_nearest(p)
        return loc, n

    base = [snap(Vector(p)) for p in pts]
    rings = []
    for i, (loc, n) in enumerate(base):
        t = (base[min(i + 1, len(base) - 1)][0] - base[max(i - 1, 0)][0]).normalized()
        s = t.cross(n).normalized()
        ring = []
        for k, h in ((1.0, 0.0), (edge, thick), (-edge, thick), (-1.0, 0.0)):
            q, qn = snap(loc + s * (hws[i] * k))
            ring.append(bm.verts.new(q + qn * (h + 0.0008)))
        rings.append(ring)
    for r0, r1 in zip(rings, rings[1:]):
        for j in range(3):
            bm.faces.new((r0[j], r1[j], r1[j + 1], r0[j + 1]))
    bm.faces.new(rings[0])
    bm.faces.new(rings[-1][::-1])


def band_obj(name, bm, material, parent=None, sharp=60.0):
    print("PART", name, "band", flush=True)
    bmesh.ops.translate(bm, vec=-_wloc(parent), verts=bm.verts)
    return smooth_sharp(_finish(name, bm, material, parent, smooth=True), sharp)


def fold_ring(name, secs, material, parent=None, sides=8, lip=0.012, **kw):
    """Punho dobrado / rolo: anel curto que sai rente à peça, engorda lip e volta. secs = [de, até] (seções da
    peça de baixo nos dois extremos do anel)."""
    a, b = secs
    m0, m1 = _mix(a, b, 0.12), _mix(a, b, 0.88)
    return sloft(name, [a, dict(m0, rx=m0["rx"] + lip, ry=m0["ry"] + lip), dict(m1, rx=m1["rx"] + lip, ry=m1["ry"] + lip), b],
                 material, parent, sides=sides, caps=(False, False), **kw)


# ================================================================== Doran: corpo liso (cópia de teste)
# Mesmas proporções, pose T, materiais e grupos de pesos do build_blacksmith; só a malha do corpo muda.
def _doran_torso_secs():
    rows = (  # z, rx, ry, extras: do gancho à base do pescoço; barril (ferreiro forte), ombro largo, cintura grossa
        (0.855, 0.100, 0.085, {}),
        (0.890, 0.200, 0.126, {"bk": 1.10}),
        (0.940, 0.222, 0.134, {"bk": 1.12}),
        (0.985, 0.200, 0.132, {"bk": 1.04}),
        (1.020, 0.192, 0.130, {}),
        (1.060, 0.199, 0.138, {"fr": 1.05}),          # a camisa faz um rolo por cima do cinto
        (1.120, 0.200, 0.133, {"fr": 1.05}),
        (1.220, 0.212, 0.132, {"fr": 1.08}),
        (1.310, 0.222, 0.130, {"fr": 1.10}),
        (1.385, 0.224, 0.122, {"fr": 1.04}),
        (1.426, 0.215, 0.113, {}),                    # ombro quadrado: o trapézio só cai perto do pescoço
        (1.452, 0.165, 0.096, {}),
        (1.468, 0.090, 0.076, {}),
    )
    return [sec((0, 0, z), rx, ry, sq=2.5, **ex) for z, rx, ry, ex in rows]


def doran_legs(P, M, take):
    hip_z = P["pelvis"].z
    Z = (0, 0, 1)
    for n, s, sd in (("L", 1, "Left"), ("R", -1, "Right")):
        H, K, A = (mirror(P[j], s) for j in ("hip", "knee", "ankle"))
        # calça grossa numa peça só do quadril até a bota: dois rolos juntam o pano em cima do cano
        secs = _along(H, K, [(0.0, 0.118, 0.124), (0.14, 0.122, 0.128, {"fr": 1.06}), (0.45, 0.112, 0.117, {"fr": 1.05}),
                             (0.8, 0.094, 0.098), (1.0, 0.086, 0.090)], 1.0)
        secs += _along(K, A, [(0.10, 0.086, 0.092, {"bk": 1.1}), (0.19, 0.093, 0.098), (0.235, 0.084, 0.088),
                              (0.275, 0.091, 0.095), (0.32, 0.072, 0.076)], 1.0)
        sloft("Leg%s_Pants" % n, secs, M["pants"], sides=8)
        weigh(take(), Z, [(K.z - 0.035, sd + "Leg"), (K.z + 0.045, sd + "UpLeg"), (hip_z - 0.06, sd + "UpLeg"),
                          (hip_z + 0.02, "Hips")])
        # bota: cano em loft, punho dobrado, pé com o peito alto atrás e a biqueira baixa e larga, sola chata
        x = K.x
        shaft = [sec((x, 0.004, 0.10), 0.054, 0.058), sec((x, 0.003, 0.20), 0.058, 0.062),
                 sec((x, 0.001, 0.30), 0.066, 0.070), sec((x, 0, 0.37), 0.070, 0.074)]
        sloft("Leg%s_Shaft" % n, shaft, M["lea_d"], sides=8, caps=(False, False))
        fold_ring("Leg%s_Cuff" % n, [sec((x, 0, 0.300), 0.068, 0.072), sec((x, 0, 0.392), 0.074, 0.078)], M["glove_d"],
                  lip=0.014)
        fold_ring("Leg%s_BootStrap" % n, [sec((x, 0.003, 0.186), 0.058, 0.062), sec((x, 0.003, 0.214), 0.059, 0.063)],
                  M["glove"], lip=0.008)
        tbox("Leg%s_BootBuckle" % n, (x + s * 0.045, -0.05, 0.2), (0.026, 0.012, 0.026), M["iron"])
        fy = (0, -1, 0)
        foot = [(0.060, 0.050, 0.034, 0.030, 1.0, 1.0), (0.040, 0.056, 0.046, 0.040, 1.35, 0.95),
                (-0.010, 0.060, 0.053, 0.044, 1.6, 0.95), (-0.060, 0.054, 0.056, 0.040, 1.15, 0.9),
                (-0.110, 0.049, 0.057, 0.036, 1.0, 0.85), (-0.148, 0.045, 0.051, 0.032, 0.95, 0.8),
                (-0.170, 0.040, 0.036, 0.022, 0.9, 0.8)]
        sloft("Leg%s_Foot" % n, [sec((x, y, z), rx, ry, fr=fr, bk=bk, sq=2.5) for y, z, rx, ry, fr, bk in foot],
              M["lea_d"], sides=8, axis=fy, fwd=(0, 0, 1))
        sole = [(0.066, 0.036, 0.016), (0.030, 0.050, 0.017), (-0.060, 0.060, 0.014), (-0.130, 0.060, 0.013),
                (-0.176, 0.042, 0.012)]
        sloft("Leg%s_Sole" % n, [sec((x, y, ry), rx, ry, sq=3.2) for y, rx, ry in sole], M["sole"], sides=6, axis=fy,
              fwd=(0, 0, 1), sharp=40.0)
        weigh(take(), Z, [(0.11, sd + "Foot"), (0.16, sd + "Leg")])


def doran_torso(P, M, take):
    Z = (0, 0, 1)
    T = _doran_torso_secs()
    # tronco: uma grade só, calça até o cinto e camisa daí para cima
    _, bvh = sloft("Chest", T, M["shirt"], sides=12, phase=0.0, axis=Z, matf=lambda i, j: 1 if i < 3 else 0,
                   mats=(M["pants"],), bvh=True)
    sloft("Belt", [dict(sec_at(T, z), rx=sec_at(T, z)["rx"] + a, ry=sec_at(T, z)["ry"] + a)
                   for z, a in ((0.974, 0.003), (0.979, 0.013), (1.019, 0.013), (1.024, 0.003))],
          M["lea_d"], sides=12, phase=0.0, axis=Z, caps=(False, False))
    base = take()

    # avental de couro: casca curva sobre o tronco (peitilho) que se solta do cinto para baixo (saia), com o
    # friso de cima e a barra na mesma grade (material por faixa)
    def y_ap(x, z, off=0.014):
        s = sec_at(T, max(z, 0.985))
        k = max(0.0, min(1.0, (1.05 - z) / 0.15))
        s = dict(s, rx=s["rx"] + 0.10 * k)                     # abaixo da cintura a saia abre e deixa de abraçar o corpo
        return sec_y(s, x) - off - 0.06 * max(0.0, 0.985 - z)  # e cai inclinada para a frente, por fora das coxas

    HW = [(0.505, 0.226), (0.64, 0.219), (0.77, 0.212), (0.9, 0.205), (1.0, 0.19), (1.045, 0.138), (1.11, 0.132),
          (1.2, 0.125), (1.29, 0.115), (1.38, 0.105)]
    rows = [1.38, 1.352, 1.27, 1.19, 1.11, 1.045, 1.0, 0.982, 0.9, 0.77, 0.64, 0.548, 0.505]
    cols = 6
    Pg = [[Vector((hw * (2.0 * c / cols - 1.0), y_ap(hw * (2.0 * c / cols - 1.0), z), z)) for c in range(cols + 1)]
          for z, hw in ((z, _tab(HW, z)) for z in rows)]
    plate("Apron", Pg, M["apron"], matf=lambda r, c: 1 if r in (0, 6, len(rows) - 2) else 0, mats=(M["apron_d"],),
          back_from=7)
    px = (0.012, 0.085, 0.158)
    plate("ApronPocket", [[Vector((x, y_ap(x, z, 0.030), z)) for x in px] for z in (0.848, 0.822, 0.715)], M["apron_d"],
          matf=lambda r, c: 1 if r == 0 else 0, mats=(M["apron_l"],), thick=0.016)
    ya = y_ap(0.07, 0.82, 0.030)
    limb("TongsHandleA", (0.06, ya + 0.004, 0.8), (0.07, ya - 0.022, 0.97), 0.008, 0.008, M["iron"], sides=4)
    limb("TongsHandleB", (0.08, ya + 0.004, 0.8), (0.1, ya - 0.022, 0.96), 0.008, 0.008, M["iron"], sides=4)
    skirt = take()

    # alças por cima dos ombros até o nó nas costas, e a amarra em volta da cintura: tiras em relevo na camisa
    sb = bmesh.new()
    zt = 1.048
    for s in (1, -1):
        surf_band(sb, [(s * 0.100, -0.2, 1.36), (s * 0.100, -0.2, 1.41), (s * 0.099, -0.10, 1.47), (s * 0.097, -0.05, 1.5),
                       (s * 0.092, 0.03, 1.5), (s * 0.087, 0.09, 1.47), (s * 0.082, 0.2, 1.40), (s * 0.050, 0.2, 1.22), (s * 0.006, 0.2, zt + 0.01)],
                  0.012, bvh, thick=0.005)
    ring = _ring(sec_at(T, zt), Vector((1, 0, 0)), Vector((0, -1, 0)), 24, 0.0, None, 0.0)
    surf_band(sb, [ring[k % 24] for k in range(10, 27, 2)], 0.014, bvh, thick=0.005)
    band_obj("ApronStraps", sb, M["apron_d"])
    yb = sec_y(sec_at(T, zt), 0.0, back=True)
    sloft("ApronKnot", [sec((-0.022, yb + 0.006, zt), 0.012, 0.010), sec((0, yb + 0.012, zt), 0.02, 0.014),
                        sec((0.022, yb + 0.006, zt), 0.012, 0.010)], M["apron_d"], sides=6, fwd=(0, 1, 0))
    for s in (1, -1):
        sloft("ApronTail%d" % s, [sec((s * 0.004, yb + 0.012, zt - 0.006), 0.011, 0.004),
                                  sec((s * 0.022, yb + 0.016, zt - 0.06), 0.013, 0.004),
                                  sec((s * 0.030, yb + 0.012, zt - 0.11), 0.008, 0.003)], M["apron_d"], sides=4, fwd=(0, 1, 0))

    # gola: abertura em V desenhada na camisa (pele em sombra) e a barra da gola em duas tiras gordas
    d = Vector((0, 1, 0))
    vb = bmesh.new()
    _fan(vb, [Vector((x, -0.2, z)) for x, z in ((-0.044, 1.44), (-0.030, 1.40), (-0.008, 1.35), (0.008, 1.35),
                                               (0.030, 1.40), (0.044, 1.44), (0.0, 1.44))], bvh, d, 0.002)
    _decal("ChestOpen", vb, M["skin_d"], None)
    cb = bmesh.new()
    for s in (1, -1):
        surf_band(cb, [(s * 0.056, -0.2, 1.45), (s * 0.040, -0.2, 1.405), (s * 0.016, -0.2, 1.352), (s * 0.001, -0.2, 1.332)],
                  [0.011, 0.011, 0.010, 0.007], bvh, thick=0.005)
    band_obj("Collar", cb, M["shirt_d"])

    # pano de limpar pendurado no cinto, do lado direito: língua de pano com uma leve onda
    rad = Vector((-0.92, -0.39, 0)).normalized()
    p0 = Vector((-0.185, -0.078, 0)) + rad * 0.022
    sloft("Rag", [sec(p0 + rad * o + Vector((0, 0, z)), w, 0.007)
                  for z, w, o in ((1.012, 0.030, 0.0), (0.985, 0.034, 0.004), (0.92, 0.040, -0.002), (0.86, 0.046, 0.006),
                                  (0.815, 0.042, 0.002))], M["shirt_d"], sides=6, phase=0.0, fwd=rad)
    stops = [(1.0, "Hips"), (1.08, "Spine"), (1.2, "Spine1"), (1.32, "Spine2")]
    weigh(base + take(), Z, stops)
    # a saia do avental cede para as coxas (como a túnica do Bram): no passo à frente a coxa não atravessa o couro
    weigh_by(skirt, robe_field(0.985, 0.55, stops))
    sloft("Neck", [sec((0, 0.012, 1.42), 0.076, 0.072), sec((0, 0.014, 1.52), 0.068, 0.064),
                   sec((0, 0.016, 1.6), 0.062, 0.060)], M["skin"], sides=8, caps=(False, False))
    weigh(take(), Z, [(1.44, "Spine2"), (1.5, "Neck")])


def doran_arms(P, M, take):
    """Braços na pose T. Devolve (joints, grips) como o build_blacksmith."""
    joints, grips = {}, {}
    for n, s, sd in (("L", 1, "Left"), ("R", -1, "Right")):
        S = limb_sections(dict(P, lb=1.35), s)
        sh, el, wr = (mirror(P[j], s) for j in ("shoulder", "elbow", "wrist"))
        tx = Vector((s, 0, 0))
        r_up = (el - sh).normalized().rotation_difference(tx)
        r_fo = (wr - el).normalized().rotation_difference(tx)
        el_t = sh + r_up @ (el - sh)
        wr_t = el_t + r_fo @ (wr - el)
        U0, F0 = S["upper"], S["fore"]

        def up(secs):
            return xf_secs(secs, sh, r_up, sh)

        def fo(secs):
            return xf_secs(secs, el, r_fo, el_t)

        # manga: calota do ombro (fecha por cima quando o braço desce) e tubo até o meio do braço
        sl = grow(U0[:6], 1.12, 0.012)
        tip = dict(sl[0], rx=sl[0]["rx"] * 0.45, ry=sl[0]["ry"] * 0.45, c=sl[0]["c"] + (sl[0]["c"] - sl[1]["c"]) * 1.6)
        sloft("Arm%s_Sleeve" % n, up([tip] + sl), M["shirt"], caps=(True, False))
        # manga arregaçada: dois rolos gordos
        r = [grow([sample(U0, t)], k, a)[0] for t, k, a in ((0.46, 1.12, 0.012), (0.478, 1.2, 0.024), (0.522, 1.18, 0.016),
                                                            (0.566, 1.2, 0.024), (0.59, 1.0, 0.004))]
        sloft("Arm%s_Roll" % n, up(r), M["shirt_d"], caps=(False, False))
        upper = take()
        # pele: uma peça só do rolo até dentro da luva, passando pelo cotovelo
        skin = up([sample(U0, 0.55), U0[6], U0[7]]) + fo([F0[1], F0[2], sample(F0, 0.8)])
        sloft("Arm%s_Fore" % n, skin, M["skin"], caps=(False, False))
        # punho da luva: boca aberta com a borda virada
        c = [dict(sample(F0, t), rx=rx * P["k"], ry=ry * P["k"]) for t, rx, ry in (
            (0.46, 0.056, 0.058), (0.49, 0.071, 0.076), (0.55, 0.071, 0.076), (0.60, 0.064, 0.069), (1.0, 0.058, 0.063))]
        sloft("Arm%s_GloveCuff" % n, fo(c), M["glove_d"], caps=(False, False))
        hand = fist("Arm" + n, P, s, M["glove"], None)
        for v in hand.data.vertices:
            v.co = el_t + r_fo @ (v.co - el)
        smooth_sharp(hand, 42.0)
        fore = take()
        ax = (s, 0, 0)
        weigh(upper, ax, [(0.0, sd + "Arm")])
        weigh(fore, ax, [(abs(el_t.x) - 0.03, sd + "Arm"), (abs(el_t.x) + 0.04, sd + "ForeArm"),
                         (abs(wr_t.x) - 0.005, sd + "ForeArm"), (abs(wr_t.x) + 0.02, sd + "Hand")])
        joints[sd] = (sh, el_t, wr_t)
        grips[sd] = el_t + r_fo @ (wr + Vector((-s * 0.004, 0, -0.064 * P["hd"])) - el)
    return joints, grips
