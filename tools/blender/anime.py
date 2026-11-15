# Rosto e mãos no estilo do estudo de personagem (docs/ESTILO_TOON.md, "Do estudo no Blender"):
# cabeça lisa a partir de curvas de perfil, pele do rosto sem sombra de forma, olhos em camadas
# (branco, íris, pupila, brilho), cílios e sobrancelhas em tira, boca como um traço; mão aberta e
# relaxada com palma e dedos em falanges.
# Mesmas unidades e marcos de head.py (cm, queixo em z=0, rosto para -Y, altura nominal 23), para que
# cabelo, turbante e brincos dos personagens continuem encaixando.
# Materiais com nome terminado em "_flat" ficam sem sombra de forma no jogo (ToonLook).
import bmesh, math, random
from mathutils import Vector
from mathutils.bvhtree import BVHTree

# (z, meia-largura, y frontal, y traseiro): queixo fino, bochecha larga e baixa, crânio igual ao de head.py
ANIME_RINGS = [
    (0.0, 1.3, -6.9, -3.6), (1.4, 3.1, -8.1, -1.0), (3.0, 4.5, -8.7, 2.2), (4.6, 5.6, -8.95, 4.6),
    (6.2, 6.35, -9.05, 6.3), (7.3, 6.7, -9.1, 7.2), (8.6, 7.05, -9.1, 8.0), (10.6, 7.2, -9.0, 9.0),
    (12.6, 7.2, -9.05, 9.5), (14.6, 7.2, -9.0, 9.7), (17.2, 7.2, -8.6, 9.5), (19.6, 6.4, -6.9, 8.3),
    (21.6, 4.2, -3.9, 5.2),
]
ANIME_TOP = 23.0
ANIME_COLS = [0, 9, 20, 33, 48, 66, 88, 112, 136, 159, 180, -159, -136, -112, -88, -66, -48, -33, -20, -9]


def _tab(T, x):
    for (x0, v0), (x1, v1) in zip(T, T[1:]):
        if x <= x1:
            k = max(0.0, (x - x0) / (x1 - x0))
            return v0 + (v1 - v0) * k
    return T[-1][1]


def _fan(bm, pts, bvh, d, eps, rings=2):
    """Forma cheia (contorno em estrela) projetada na superfície ao longo de d."""
    c = sum(pts, Vector()) / len(pts)
    n = len(pts)
    layers = [[c + (p - c) * (1 - k / rings) for p in pts] for k in range(rings)] + [[c]]
    V = [[bm.verts.new(_proj(bvh, q, d, eps)) for q in L] for L in layers]
    for r0, r1 in zip(V, V[1:]):
        for i in range(n):
            if len(r1) == 1:
                bm.faces.new((r0[i], r0[(i + 1) % n], r1[0]))
            else:
                bm.faces.new((r0[i], r0[(i + 1) % n], r1[(i + 1) % n], r1[i]))


def _ribbon(bm, pts, widths, bvh, d, eps):
    """Tira ao longo de pts com meia-largura por ponto, projetada na superfície."""
    L, R = [], []
    for i, p in enumerate(pts):
        a, b = pts[max(i - 1, 0)], pts[min(i + 1, len(pts) - 1)]
        side = (b - a).cross(-d).normalized()
        L.append(bm.verts.new(_proj(bvh, p + side * widths[i], d, eps)))
        R.append(bm.verts.new(_proj(bvh, p - side * widths[i], d, eps)))
    for i in range(len(pts) - 1):
        bm.faces.new((L[i], L[i + 1], R[i + 1], R[i]))


def _proj(bvh, p, d, eps):
    hit = bvh.ray_cast(p - d * 0.3, d)[0]
    return (hit - d * eps) if hit is not None else p


def _decal(name, bm, material, parent):
    # todas as feições olham para a frente (-Y): recalc_face_normals numa tira solta vira ao acaso, e a
    # face de costas some no jogo (culling)
    bm.normal_update()
    flip = [f for f in bm.faces if f.normal.y > 0]
    if flip:
        bmesh.ops.reverse_faces(bm, faces=flip)
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method='BEAUTY')
    _place(bm, (0, 0, 0), parent)
    return _finish(name, bm, material, parent, smooth=True)


def anime_head(prefix, chin_z, height, parent, mats, params=None, y0=0.0):
    """Cabeça lisa com feições desenhadas. mats: skin (ideal: nome terminado em _flat), white, iris, iris_dark,
    iris_light, pupil, lash, brow, mouth, line. Devolve os mesmos marcos de human_head (para hair_locks)."""
    p = {"eye_w": 1.0, "eye_h": 1.0, "eye_x": 1.0, "nose": 1.0, "mouth_w": 1.0, "lash": 1.0, "brow": 1.0,
         "width": 1.0, "jaw": 1.0, "brow_dz": 0.0, "brow_tilt": 0.0}
    p.update(params or {})
    s = height / 23.0

    def m(x, y, z):
        return Vector((x * s, y0 + y * s, chin_z + z * s))

    # ---- cabeça: grade lisa (anéis x colunas), nariz como um pequeno relevo na coluna central
    n = len(ANIME_COLS)
    verts, faces = [], []
    for z, W, fy, by in ANIME_RINGS:
        cy, D = (fy + by) / 2, (by - fy) / 2
        for deg in ANIME_COLS:
            th = math.radians(deg)
            sn, cs = math.sin(th), math.cos(th)
            nf = 2.9 if cs > 0 else 2.2
            Wm = W * p["width"] * (p["jaw"] if z <= 6.2 else 1.0)       # jaw alarga só do nariz para baixo
            x = Wm * math.copysign(abs(sn) ** (2 / nf), sn)
            y = cy - D * math.copysign(abs(cs) ** (2 / nf), cs)
            if cs > 0:
                y -= 1.5 * p["nose"] * math.exp(-(x / 0.75) ** 2 - ((z - 7.2) / 1.05) ** 2)     # ponta do nariz
                y -= 0.30 * math.exp(-(x / 1.0) ** 2 - ((z - 9.6) / 2.2) ** 2)                 # dorso
                y -= 0.20 * math.exp(-(x / 1.8) ** 2 - ((z - 3.9) / 0.9) ** 2)                 # lábios
            verts.append(m(x, y, z))
    rows = len(ANIME_RINGS)
    for i in range(rows - 1):
        for j in range(n):
            a, b = i * n + j, i * n + (j + 1) % n
            faces.append((a, b, b + n, a + n))
    top = len(verts)
    verts.append(m(0, 0.6, ANIME_TOP))
    last = (rows - 1) * n
    faces += [(last + j, last + (j + 1) % n, top) for j in range(n)]
    bot = len(verts)
    verts.append(m(0, -3.4, 0.2))
    faces += [((j + 1) % n, j, bot) for j in range(n)]
    hb = bmesh.new()
    hv = [hb.verts.new(v) for v in verts]
    for f in faces:
        hb.faces.new([hv[i] for i in f])
    bmesh.ops.recalc_face_normals(hb, faces=hb.faces[:])
    bmesh.ops.triangulate(hb, faces=hb.faces[:], quad_method='BEAUTY')
    bvh = BVHTree.FromBMesh(hb)
    _place(hb, (0, 0, 0), parent)
    _finish(prefix + "HeadMesh", hb, mats["skin"], parent, smooth=True)

    d = Vector((0, 1, 0))
    mm = 0.001          # as camadas ficam a 1 mm uma da outra: abaixo disso brigam de longe no jogo

    # ---- olhos em camadas
    ez = 10.7
    ex = 3.25 * p["eye_x"] * p["width"]
    hw, ht, hbm, e = 1.95 * p["eye_w"], 1.30 * p["eye_h"], 1.50 * p["eye_h"], 2.3
    for sg, nm in ((1, "L"), (-1, "R")):
        def P(lx, lz):          # coordenadas do olho: +lx = lado de fora
            return m(sg * (ex + lx), -20.0, ez + lz + lx * 0.05)

        def outl(deg):
            a = math.radians(deg)
            ca, sa = math.cos(a), math.sin(a)
            x = math.copysign(abs(ca) ** (2 / e), ca) * hw
            if sa > 0:
                return (x, abs(sa) ** (2 / e) * ht)
            k = abs(sa) ** (2 / e)
            return (x * (1.0 - 0.20 * k), -k * hbm)           # o olho estreita para a pálpebra de baixo

        def ell(cx, cz, rx, rz, k=14):
            return [P(cx + rx * math.cos(2 * math.pi * i / k), cz + rz * math.sin(2 * math.pi * i / k)) for i in range(k)]

        b = bmesh.new()
        _fan(b, [P(*outl(a)) for a in range(0, 360, 20)], bvh, d, 1 * mm)
        _decal(prefix + "EyeWhite" + nm, b, mats["white"], parent)
        b = bmesh.new()
        ih = p["eye_h"]            # olho mais fechado (adulto, idoso): íris, pupila e brilho encolhem junto
        iw = (1.0 + ih) / 2
        _fan(b, ell(-0.1, -0.15 * ih, 1.12 * iw, 1.50 * ih), bvh, d, 2 * mm)
        _decal(prefix + "EyeIris" + nm, b, mats["iris"], parent)
        b = bmesh.new()
        _fan(b, ell(-0.1, 0.45 * ih, 1.06 * iw, 0.92 * ih, 12), bvh, d, 3 * mm, rings=1)        # sombra da pálpebra na íris
        _decal(prefix + "EyeIrisDark" + nm, b, mats["iris_dark"], parent)
        b = bmesh.new()
        _fan(b, ell(-0.1, -1.0 * ih, 0.72 * iw, 0.48 * ih, 10), bvh, d, 3 * mm, rings=1)        # reflexo claro embaixo
        _decal(prefix + "EyeIrisLight" + nm, b, mats["iris_light"], parent)
        b = bmesh.new()
        _fan(b, ell(-0.1, -0.1 * ih, 0.42 * iw, 0.66 * ih, 10), bvh, d, 4 * mm, rings=1)
        _decal(prefix + "EyePupil" + nm, b, mats["pupil"], parent)
        b = bmesh.new()             # brilho do mesmo lado nos dois olhos (luz vinda da direita do personagem)
        hx = (-0.52 if sg == 1 else 0.52) * iw
        _fan(b, [m(sg * ex + hx + 0.27 * iw * math.cos(a), -20.0, ez + (0.55 + 0.32 * math.sin(a)) * ih)
                 for a in (2 * math.pi * i / 8 for i in range(8))], bvh, d, 5 * mm, rings=1)
        _decal(prefix + "EyeShine" + nm, b, mats["white"], parent)

        # cílio de cima (grosso no meio, ponta para fora), de baixo (fino), dobra da pálpebra e sobrancelha
        b = bmesh.new()
        up = [P(*outl(a)) + Vector((0, 0, 0.10 * s)) for a in range(180, -1, -15)]
        wd = [(0.14 + 0.26 * math.sin(math.pi * min(1.0, i / (len(up) - 1) * 1.1) * 0.5)) * p["lash"] * s for i in range(len(up))]
        up.append(P(hw + 0.42, 0.18))
        wd.append(0.04 * s)
        _ribbon(b, up, wd, bvh, d, 5.5 * mm)
        lo = [P(*outl(a)) for a in range(-40, -141, -20)]
        _ribbon(b, lo, [0.06 * s] * len(lo), bvh, d, 5.5 * mm)
        _decal(prefix + "Lash" + nm, b, mats["lash"], parent)
        b = bmesh.new()
        cr = [P(outl(a)[0] * 0.9, outl(a)[1] + 0.50) for a in range(150, 29, -20)]
        _ribbon(b, cr, [0.05 * s] * len(cr), bvh, d, 1.5 * mm)
        _decal(prefix + "EyeCrease" + nm, b, mats["line"], parent)
        b = bmesh.new()
        bz, bt = ht + 1.25 + p["brow_dz"], p["brow_tilt"]     # brow_tilt baixa a ponta de dentro (cenho)
        br = [P(-1.75, bz - bt), P(-0.6, bz + 0.27 - bt * 0.55), P(0.7, bz + 0.25), P(1.95, bz - 0.13)]
        _ribbon(b, br, [k_ * p["brow"] * s for k_ in (0.10, 0.22, 0.20, 0.07)], bvh, d, 1.5 * mm)
        _decal(prefix + "Brow" + nm, b, mats["brow"], parent)

        # orelha lisa, mais larga em cima, levemente virada para trás
        eb = bmesh.new()
        bmesh.ops.create_uvsphere(eb, u_segments=8, v_segments=6, radius=1.0)
        for v in eb.verts:
            k = 1.0 + 0.22 * v.co.z
            v.co = m(sg * 7.15 * p["width"] + v.co.x * 0.85, 1.2 + v.co.y * 1.5 * k + 0.35 * v.co.z, 9.9 + v.co.z * 2.6)
        bmesh.ops.triangulate(eb, faces=eb.faces[:])
        _place(eb, (0, 0, 0), parent)
        _finish(prefix + "Ear" + nm, eb, mats["skin"], parent, smooth=True)

    # ---- boca: traço curto levemente curvo + sombra do lábio de baixo; nariz: um tracinho de sombra
    mz, mw = 4.35, 1.15 * p["mouth_w"]
    b = bmesh.new()
    _ribbon(b, [m(-mw, -20, mz + 0.10), m(-mw * 0.4, -20, mz), m(mw * 0.4, -20, mz), m(mw, -20, mz + 0.10)],
            [0.06 * s, 0.13 * s, 0.13 * s, 0.06 * s], bvh, d, 1.5 * mm)
    _decal(prefix + "Mouth", b, mats["mouth"], parent)
    b = bmesh.new()
    _ribbon(b, [m(-0.6, -20, mz - 0.80), m(0.6, -20, mz - 0.80)], [0.06 * s, 0.06 * s], bvh, d, 1.5 * mm)
    _ribbon(b, [m(0.20, -20, 7.25), m(0.45, -20, 6.5)], [0.05 * s, 0.10 * s], bvh, d, 1.5 * mm)
    _decal(prefix + "FaceLines", b, mats["line"], parent)

    return {
        "s": s, "chin": chin_z, "top": chin_z + ANIME_TOP * s, "eye_z": chin_z + ez * s,
        "mouth_z": chin_z + mz * s, "nose_base_z": chin_z + 6.4 * s, "brow_z": chin_z + 13.4 * s,
        "front_y": y0 - 9.1 * s, "mouth_y": y0 - 8.9 * s, "chin_y": y0 - 8.1 * s,
        "half_w": 7.2 * p["width"] * s, "back_y": y0 + 9.7 * s, "cy": y0 + 0.45 * s,
        "eye_x": ex * s, "eye_y": y0 - 9.0 * s,
        "y0": y0, "width": p["width"], "jaw": p["jaw"],        # para anime_hair / anime_beard seguirem a cabeça
    }


# ------------------------------------------------------------------ mão aberta e relaxada
def _tube(bm, secs, sides=6):
    """Tubo liso por seções (centro, rx, ry, tangente, u). Tampas nas duas pontas."""
    rings = []
    for c, rx, ry, t, u in secs:
        t = t.normalized()
        u = (u - t * u.dot(t)).normalized()
        v = t.cross(u).normalized()
        rings.append([bm.verts.new(c + u * rx * math.cos(2 * math.pi * i / sides) + v * ry * math.sin(2 * math.pi * i / sides))
                      for i in range(sides)])
    for r0, r1 in zip(rings, rings[1:]):
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new((r0[i], r0[j], r1[j], r1[i]))
    for r, flip in ((rings[0], True), (rings[-1], False)):
        c = bm.verts.new(sum((q.co for q in r), Vector()) / sides)
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new((c, r[j], r[i]) if flip else (c, r[i], r[j]))


def open_hand(prefix, wrist, s, material, parent, k=1.12):
    """Mão caída ao lado do corpo: palma que alarga do pulso aos nós, quatro dedos em três falanges
    curvando para a coxa, com um leve leque, e o polegar afastado para a frente.
    wrist = ponto do pulso (mundo, m); s = +1 esquerda do personagem, -1 direita; k = escala."""
    W = Vector(wrist)
    dn = Vector((0, 0, -1))
    out = Vector((s, 0, 0))            # dorso da mão
    inw = -out
    fy = Vector((0, -1, 0))
    bm = bmesh.new()
    # palma: rx = espessura (X), ry = largura (Y)
    palm = [(0.000, 0.0170, 0.0200), (0.022, 0.0190, 0.0290), (0.048, 0.0180, 0.0365), (0.070, 0.0155, 0.0385),
            (0.084, 0.0115, 0.0350)]
    _tube(bm, [(W + dn * (a * k) + inw * (0.004 * k * (a / 0.084)), rx * k, ry * k, dn, out) for a, rx, ry in palm], sides=8)
    for yo, base, L, splay in ((-0.0265, 0.074, 0.058, 9), (-0.0088, 0.081, 0.066, 3), (0.0090, 0.077, 0.061, -4),
                               (0.0255, 0.066, 0.048, -11)):
        p0 = W + dn * (base * k) + Vector((0, yo * k, 0)) + inw * 0.004 * k
        sp = math.radians(splay)
        fwd = (dn * math.cos(sp) + fy * math.sin(sp) * 0.35).normalized()
        secs = [(p0 - fwd * 0.008 * k, 0.0098 * k, 0.0098 * k, fwd, out)]
        ang, cur = 0.0, p0
        for seg, bend, r in ((0.44, 8, 0.0094), (0.31, 18, 0.0087), (0.25, 16, 0.0074)):
            ang += math.radians(bend)
            dirv = (fwd * math.cos(ang) + inw * math.sin(ang)).normalized()
            cur = cur + dirv * (L * seg * k)
            secs.append((cur, r * k, r * k, dirv, out))
        secs.append((cur + dirv * 0.004 * k, 0.0050 * k, 0.0050 * k, dirv, out))
        _tube(bm, secs, sides=6)
    tb = W + dn * (0.030 * k) + fy * (0.026 * k) + inw * 0.004 * k
    t1 = (dn * 0.62 + fy * 0.70 + inw * 0.30).normalized()
    t2 = (dn * 0.90 + fy * 0.32 + inw * 0.40).normalized()
    q1 = tb + t1 * 0.026 * k
    q2 = q1 + t2 * 0.024 * k
    _tube(bm, [(tb - t1 * 0.010 * k, 0.0130 * k, 0.0130 * k, t1, out), (tb + t1 * 0.008 * k, 0.0135 * k, 0.0135 * k, t1, out),
               (q1, 0.0114 * k, 0.0114 * k, t2, out), (q2, 0.0094 * k, 0.0094 * k, t2, out),
               (q2 + t2 * 0.006 * k, 0.0058 * k, 0.0058 * k, t2, out)], sides=6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method='BEAUTY')
    _place(bm, (0, 0, 0), parent)
    return _finish(prefix + "_Hand", bm, material, parent, smooth=True)


# ------------------------------------------------------------------ cabelo e barba desenhados
# Mechas largas, chatas e lisas, em loft ao longo de uma spline que corre sobre a cabeça e termina em
# ponta (docs/ESTUDO_PERSONAGEM_ANIME.md, "Cabelo"). Tudo parte dos marcos de anime_head, então serve a
# qualquer cabeça feita por ela (largura e mandíbula entram na conta).
# Ângulos: th = 0 na frente do rosto, +90 à esquerda do personagem (+X), 180 atrás; ph = elevação a partir
# do centro do crânio (90 = topo, 0 = altura do olho/orelha, negativo = nuca).
def _ring_at(z):
    R = ANIME_RINGS + [(22.6, 2.2, -1.5, 3.0), (ANIME_TOP, 0.05, 0.5, 0.7)]
    if z <= R[0][0]:
        return R[0][1:]
    for a, b in zip(R, R[1:]):
        if z <= b[0]:
            k = (z - a[0]) / (b[0] - a[0])
            return tuple(a[i] + (b[i] - a[i]) * k for i in (1, 2, 3))
    return R[-1][1:]


def _hp(H, deg, z):
    """Ponto da superfície da cabeça (m) na coluna deg e altura z (cm acima do queixo)."""
    s = H["s"]
    W, fy, by = _ring_at(z)
    W *= H.get("width", 1.0) * (H.get("jaw", 1.0) if z <= 6.2 else 1.0)
    cy, D = (fy + by) / 2, (by - fy) / 2
    th = math.radians(deg)
    sn, cs = math.sin(th), math.cos(th)
    nf = 2.9 if cs > 0 else 2.2
    x = W * math.copysign(abs(sn) ** (2 / nf), sn)
    y = cy - D * math.copysign(abs(cs) ** (2 / nf), cs)
    return Vector((x * s, H.get("y0", 0.0) + y * s, H["chin"] + z * s))


def _face_pt(H, x, z):
    """Ponto da frente do rosto (m) na posição lateral x e altura z (cm)."""
    W = _ring_at(z)[0] * H.get("width", 1.0) * (H.get("jaw", 1.0) if z <= 6.2 else 1.0)
    sn = min(1.0, abs(x) / W) ** (2.9 / 2)
    return _hp(H, math.copysign(math.degrees(math.asin(sn)), x), z)


def _scalp(H, th, ph, lift=0.0):
    s = H["s"]
    C = Vector((0, H["cy"], H["chin"] + 12.0 * s))
    e = math.radians(ph)
    if ph >= 0:
        p = _hp(H, th, 12.0 + 11.0 * math.sin(e))
        zk = 1.0
    else:                       # abaixo da orelha o cabelo cai mais reto que o crânio, fechando um pouco para o pescoço
        k = 1.0 + 0.30 * math.sin(e)
        q = _hp(H, th, 12.0)
        p = Vector((q.x * k, C.y + (q.y - C.y) * k, C.z + 12.3 * s * math.sin(e)))
        zk = 0.35
    r = p - C
    n = Vector((r.x / 7.5 ** 2, r.y / 9.5 ** 2, r.z * zk / 11.0 ** 2)).normalized()
    return p + n * lift


def _spline(P, k):
    """Catmull-Rom pelos pontos P, k amostras por trecho. Devolve (pontos, tangentes)."""
    P = [P[0] * 2 - P[1]] + list(P) + [P[-1] * 2 - P[-2]]
    out, tg = [], []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for j in range(k + (1 if i == len(P) - 3 else 0)):
            t = j / k
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
            tg.append((0.5 * ((-p0 + p2) + 2 * (2 * p0 - 5 * p1 + 4 * p2 - p3) * t
                              + 3 * (-p0 + 3 * p1 - 3 * p2 + p3) * t * t)).normalized())
    return out, tg


# seção da mecha: bordas finas dos lados, dorso arredondado em cima, barriga rasa embaixo (colada à cabeça)
_LOCK_SEC = ((1.0, 0.0), (0.0, 1.0), (-1.0, 0.0), (0.0, -0.4))


def _lock(bm, ctrl, w, nrm, th_k=0.30, k=2, root=0.5):
    """Mecha: ctrl = pontos (m), w = meia-largura máxima, nrm(p) = normal de apoio (para fora da cabeça).
    A largura abre de `root` até 1 no primeiro sexto e afina em ponta; a espessura é th_k * w."""
    pts, tgs = _spline([Vector(c) for c in ctrl], k)
    m = len(pts)
    rings = []
    for i, (p, tg) in enumerate(zip(pts, tgs)):
        if i == m - 1:
            rings.append([bm.verts.new(p)])
            break
        f = i / (m - 1)
        u = tg.cross(nrm(p))
        if u.length < 1e-5:
            u = tg.cross(Vector((0, 0, 1)))
        u.normalize()
        v = u.cross(tg).normalized()
        ww = w * min(1.0, root + f * 3.2) * (1.0 - f ** 2.6) ** 0.85
        tt = w * th_k * min(1.0, 0.6 + f * 2.5) * (1.0 - f ** 3) ** 0.7
        rings.append([bm.verts.new(p + u * (a * ww) + v * (b * tt)) for a, b in _LOCK_SEC])
    ns = len(_LOCK_SEC)
    for r0, r1 in zip(rings, rings[1:]):
        for i in range(ns):
            j = (i + 1) % ns
            if len(r1) == 1:
                bm.faces.new((r0[i], r0[j], r1[0]))
            else:
                bm.faces.new((r0[i], r0[j], r1[j], r1[i]))


def _hair_obj(name, bm, material, parent, recalc=True):
    if not bm.faces:
        bm.free()
        return None
    if recalc:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method='BEAUTY')
    _place(bm, (0, 0, 0), parent)
    return _finish(name, bm, material, parent, smooth=True)


HAIR_STYLE = {
    "fringe": 30,            # elevação onde terminam as pontas da franja (30 = testa à mostra; 8 = na sobrancelha)
    "side": 10,              # idem nos lados (acima da orelha: > 6)
    "back": -34,             # idem na nuca
    "part": 20,              # ângulo do repartido da franja
    "sweep": -1,             # para que lado a franja cai (-1 = direita do personagem)
    "top": 8,                # mechas da camada de cima, dos lados e de trás
    "w": 1.0, "lift": 1.0, "seed": 3,
    "hairline": [(0, 37), (35, 35), (60, 25), (78, 13), (97, 8), (112, -6), (135, -27), (180, -33)],
}


def anime_hair(prefix, H, mats, parent, style=None):
    """Cabelo em camadas. mats: hair (mechas), mid (calota e vãos entre as mechas), under (nuca, por baixo).
    Devolve as malhas criadas (prefix + HairCap / HairUnder / HairTop)."""
    st = dict(HAIR_STYLE)
    st.update(style or {})
    rnd = random.Random(st["seed"])
    s, W, LF = H["s"], st["w"] * H["s"], st["lift"] * H["s"]
    C = Vector((0, H["cy"], H["chin"] + 12.0 * s))

    def J(a):
        return rnd.uniform(-a, a)

    def nrm(p):
        r = p - C
        return Vector((r.x / 7.5 ** 2, r.y / 9.5 ** 2, r.z * (1.0 if r.z > 0 else 0.35) / 11.0 ** 2)).normalized()

    def sp(th, ph, lift):                       # lift em cm
        return _scalp(H, th, ph, lift * LF)

    def wrap(th):
        return abs((th + 180) % 360 - 180)

    def end(th):                                # onde a ponta termina, por direção
        return _tab([(0, st["fringe"]), (45, st["fringe"]), (70, st["side"] + 6), (95, st["side"]),
                     (115, st["side"] - 4), (140, st["back"] + 12), (180, st["back"])], wrap(th))

    # ---- calota no tom intermediário: nunca aparece pele, e a borda em serra aparece entre as mechas
    cb = bmesh.new()
    cols = 20
    grid = []
    for r in (0.0, 0.3, 0.62, 0.86):
        row = []
        for c in range(cols):
            th = -180 + 360 * c / cols
            h0 = _tab(st["hairline"], abs(th)) + (2.0 if c % 2 else -3.0) * (1.0 if abs(th) > 20 else 0.3)
            row.append(cb.verts.new(sp(th, h0 + (90 - h0) * r, 0.35)))
        grid.append(row)
    topv = cb.verts.new(sp(0, 90, 0.35))
    for r0, r1 in zip(grid, grid[1:]):
        for c in range(cols):
            d = (c + 1) % cols
            cb.faces.new((r0[c], r0[d], r1[d], r1[c]))
    for c in range(cols):
        cb.faces.new((grid[-1][c], grid[-1][(c + 1) % cols], topv))
    out = [_hair_obj(prefix + "HairCap", cb, mats["mid"], parent)]

    # ---- nuca: mechas curtas no tom escuro, por baixo de tudo
    ub = bmesh.new()
    for th in (128, 154, 180, 206, 232):
        t = th + J(4)
        e = end(t)
        _lock(ub, [sp(t, e + 34, 0.3), sp(t + J(3), e + 14, 0.6), sp(t + J(4), e - 7, 0.9)], 3.3 * W, nrm)
    out.append(_hair_obj(prefix + "HairUnder", ub, mats["under"], parent))

    # ---- camada de cima: do topo para fora; perto da orelha a mecha para cedo e vira para trás
    tb = bmesh.new()
    n = st["top"]
    for i in range(n):
        t = 58 + (244 / (n - 1)) * i + J(5)
        sg = 1 if t < 180 else -1
        e = end(t)
        lf = rnd.uniform(0.0, 0.5)
        if 76 < wrap(t + 12 * sg) < 114:
            ctrl = [sp(t, 84, 0.5 + lf), sp(t + 5 * sg, 58, 1.1 + lf), sp(t + 14 * sg, 34, 1.3 + lf),
                    sp(t + 30 * sg, e + 6, 1.3 + lf)]
        else:
            ctrl = [sp(t, 84, 0.5 + lf), sp(t + 4 * sg, 58, 1.1 + lf), sp(t + 9 * sg, 30, 1.3 + lf),
                    sp(t + 14 * sg + J(4), e + J(4), 1.5 + J(0.4))]
        _lock(tb, ctrl, 4.3 * W * rnd.uniform(0.9, 1.1), nrm, th_k=0.28)
    # mechas que emolduram o rosto: uma curta na têmpora, uma atrás da orelha
    for sg in (1, -1):
        _lock(tb, [sp(sg * 60, 62, 0.6), sp(sg * 65, 40, 1.0), sp(sg * 73, st["side"] + 6, 1.0)], 3.0 * W, nrm)
        _lock(tb, [sp(sg * 118, 46, 0.7), sp(sg * 120, 18, 1.0), sp(sg * 117, end(118) - 4, 1.1)], 3.0 * W, nrm)
    # franja: folhas largas a partir do repartido, cruzando a testa (a0 = raiz, a1 = ponta, em graus a partir do repartido)
    pt, sw, fr = st["part"], st["sweep"], st["fringe"]
    for a0, a1, dz, ww in ((0, -30, 3, 3.4), (4, -4, -2, 3.6), (8, 22, -5, 4.0), (6, 46, -3, 4.0), (0, 70, 2, 3.6)):
        b0, b1 = pt + sw * a0, pt + sw * a1
        _lock(tb, [sp(b0, 80, 0.5), sp(b0 + (b1 - b0) * 0.35, 62, 1.5), sp(b0 + (b1 - b0) * 0.75, 44, 1.6),
                   sp(b1, fr + dz, 1.5)], ww * W, nrm, th_k=0.34)
    out.append(_hair_obj(prefix + "HairTop", tb, mats["hair"], parent))
    return [o for o in out if o]


BEARD_STYLE = {
    "length": 4.2,           # cm abaixo do queixo
    "full": 1.0,             # volume
    "mustache": True,
    "locks": True,           # mechas sobrepostas à massa
}
# colunas da cabeça (o ângulo é o parâmetro da grade de anime_head, não o geométrico: 84 fica logo à frente da
# orelha e 98 embaixo dela)
_BEARD_DEG = [0, 4, 9, 16, 26, 38, 52, 68, 84, 98]
_BEARD_TOP = [3.1, 3.1, 3.5, 5.0, 6.0, 6.6, 7.4, 8.8, 14.6, 6.8]  # linha de cima (cm): sob o lábio, bochecha, costeleta
# borda de baixo: em fração do comprimento abaixo do queixo (pontas e reentrâncias alternadas); atrás da
# mandíbula (valores positivos, em cm) a borda sobe até a orelha
_BEARD_BOT = [-1.0, -0.88, -0.56, -0.80, -0.50, -0.62, -0.22, -0.42, 0.3, 1.8]


def anime_beard(prefix, H, mats, parent, style=None):
    """Barba cheia: massa lisa que cobre mandíbula e queixo, com a borda de baixo recortada em pontas, mechas
    largas por cima e bigode em duas mechas. mats: hair (massa e mechas), mid (por baixo, entre as pontas)."""
    st = dict(BEARD_STYLE)
    st.update(style or {})
    s, L, full = H["s"], st["length"], st["full"]
    cy = H["cy"] - 3.0 * s

    def radial(p):
        r = Vector((p.x, p.y - cy, 0))
        return r.normalized() if r.length > 1e-6 else Vector((0, -1, 0))

    def col(i, sg):
        zb = _BEARD_BOT[i]
        return _BEARD_DEG[i] * sg, _BEARD_TOP[i], (zb * L if zb < 0 else zb)

    def surf(i, sg, t, lift=0.0):
        """Ponto da massa na coluna i, do topo (t=0) à borda de baixo (t=1); t > 1 continua além da ponta."""
        deg, zt, zb = col(i, sg)
        z = zt + (zb - zt) * t
        side = min(1.0, abs(deg) / 50.0)
        # abaixo da linha da mandíbula a barba cai na vertical; nos lados a linha é mais alta (anel mais largo),
        # para a barba descer por fora do pescoço e cobrir a mandíbula de perfil
        zr = max(z, 2.0 + 2.6 * min(1.0, abs(deg) / 70.0))
        p = _hp(H, deg, zr)
        dn = (zr - z) / L                                               # quanto desceu abaixo da mandíbula
        p.z -= (zr - z) * s
        p.x *= 1.0 - (0.42 - 0.28 * side) * min(1.0, dn) ** 1.4
        p.y -= 0.25 * dn * s
        off = (0.45 + (1.2 + 0.5 * side) * full * math.sin(math.pi * min(1.0, t * 1.25) / 2)) * s
        return p + radial(p) * (off + lift * s)

    n = len(_BEARD_DEG)
    order = [(i, -1) for i in range(n - 1, 0, -1)] + [(i, 1) for i in range(n)]
    bm = bmesh.new()
    G = [[bm.verts.new(surf(i, sg, t)) for (i, sg) in order] for t in (0.0, 0.2, 0.5, 0.8, 1.0)]
    for r0, r1 in zip(G, G[1:]):
        for c in range(len(order) - 1):
            bm.faces.new((r0[c], r1[c], r1[c + 1], r0[c + 1]))
    out = [_hair_obj(prefix + "Beard", bm, mats["hair"], parent)]

    # por baixo: fecha da borda recortada até o queixo, no tom intermediário (vira sombra entre as pontas)
    ub = bmesh.new()
    e0 = [ub.verts.new(surf(i, sg, 1.0)) for (i, sg) in order]
    e1 = [ub.verts.new(v.co - radial(v.co) * 3.5 * s + Vector((0, 0, 1.2 * s))) for v in e0]     # some no pescoço
    for c in range(len(order) - 1):
        f = ub.faces.new((e0[c], e0[c + 1], e1[c + 1], e1[c]))
        f.normal_update()
        # a face olha para baixo e para dentro; sem ela, de costas aparece o avesso da massa (a casca, preta)
        if f.normal.dot(Vector((0, 0, -0.6)) - radial(f.calc_center_median())) < 0:
            f.normal_flip()
    out.append(_hair_obj(prefix + "BeardUnder", ub, mats["mid"], parent, recalc=False))

    if st["locks"]:
        lb = bmesh.new()
        # mechas curtas, só sobre as pontas: compridas, viram "dedos" pendurados
        for i, w, t0 in ((0, 2.0, 0.3), (3, 1.9, 0.5), (5, 2.0, 0.58), (7, 1.9, 0.55)):
            for sg in ((1,) if i == 0 else (1, -1)):
                # a raiz nasce dentro da massa: só a metade da ponta aparece, como uma folha, não um gomo
                _lock(lb, [surf(i, sg, t0 - 0.12, -0.35), surf(i, sg, (t0 + 1.14) / 2, 0.4), surf(i, sg, 1.14, 0.2)],
                      w * 1.15 * s, radial, th_k=0.24, root=0.35)
        out.append(_hair_obj(prefix + "BeardLocks", lb, mats["hair"], parent))
    if st["mustache"]:
        mb = bmesh.new()
        fwd = Vector((0, -1, 0))

        def mn(p):
            return (radial(p) * 0.4 + fwd * 0.6).normalized()

        for sg in (1, -1):
            ctrl = []
            for x, z, lf in ((0.15, 6.0, 0.45), (1.5, 5.45, 0.6), (2.9, 4.4, 0.55), (3.7, 2.7, 0.45)):
                p = _face_pt(H, sg * x, z)
                ctrl.append(p + mn(p) * lf * s)
            _lock(mb, ctrl, 1.15 * s, mn, th_k=0.5, root=0.75)
        out.append(_hair_obj(prefix + "Mustache", mb, mats["hair"], parent))
    return [o for o in out if o]
