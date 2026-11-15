# Rosto e mãos no estilo do estudo de personagem (docs/ESTILO_TOON.md, "Do estudo no Blender"):
# cabeça lisa a partir de curvas de perfil, pele do rosto sem sombra de forma, olhos em camadas
# (branco, íris, pupila, brilho), cílios e sobrancelhas em tira, boca como um traço; mão aberta e
# relaxada com palma e dedos em falanges.
# Mesmas unidades e marcos de head.py (cm, queixo em z=0, rosto para -Y, altura nominal 23), para que
# cabelo, turbante e brincos dos personagens continuem encaixando.
# Materiais com nome terminado em "_flat" ficam sem sombra de forma no jogo (ToonLook).
import bmesh, math
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
