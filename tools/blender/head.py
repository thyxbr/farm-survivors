# Cabeça humana low poly "desenhada": poucos planos grandes com shading flat e feições como formas
# gráficas — olhos escuros, sobrancelhas em cunha, nariz em cunha e a boca como um traço curto, sem lábios.
# Proporções humanas (cânone de Loomis): olhos na metade da altura, nariz e boca nos terços do rosto,
# orelhas entre a sobrancelha e a base do nariz.
# Unidade interna: cm, queixo em z=0, rosto voltado para -Y, eixo das orelhas em y=0, altura nominal 23 cm.
import bmesh, math
from mathutils import Vector

# (z, meia-largura, y frontal, y traseiro) de cada anel, do queixo ao crânio
HEAD_RINGS = [
    (0.0, 2.4, -7.3, -3.8),     # 0 base do queixo
    (2.0, 4.7, -8.3, -0.6),     # 1 queixo / linha da mandíbula
    (5.0, 6.3, -9.0, 3.6),      # 2 boca / ângulo da mandíbula
    (8.6, 7.0, -9.1, 7.6),      # 3 maçãs do rosto
    (11.4, 7.1, -8.8, 9.2),     # 4 olhos (órbitas)
    (13.4, 7.2, -9.5, 9.7),     # 5 arco das sobrancelhas
    (17.2, 7.2, -8.6, 9.5),     # 6 testa
    (20.8, 5.4, -5.4, 6.6),     # 7 crânio
]
TOP_Z = 23.0
# poucas colunas = planos grandes; 0 é o centro do rosto (aresta do nariz/queixo)
COL_DEG = [0, 32, 68, 105, 145, 180, -145, -105, -68, -32]

HEAD_DEFAULTS = {
    "width": 1.0, "jaw": 1.0, "chin": 1.0, "cheek": 1.0, "nose": 1.0, "nose_w": 1.0, "brow": 1.0,
    "eye_depth": 1.0, "eye_size": 1.0, "mouth_w": 1.0, "ear": 1.0, "age": 0.0, "fem": 0.0, "lips": 1.0,
}


def _feature(ri, col, p):
    """(dx para fora, dy) em cm aplicados ao anel ri na coluna col (graus absolutos)."""
    dx = dy = 0.0
    if col == 0:
        dy = {0: -0.2 * p["chin"], 1: -0.45 * p["chin"], 4: -0.45, 5: -0.25 * p["brow"]}.get(ri, 0.0)
    elif col == 32:
        dy = {2: -0.25, 3: -0.15, 4: 0.85 * p["eye_depth"], 5: -0.3 * p["brow"]}.get(ri, 0.0)
    elif col == 68:
        if ri == 3:
            dx = 0.35 * p["cheek"]
        if ri == 2:
            dx = 0.2 * p["age"]
    return dx, dy


def head_points(p):
    pts = []
    for ri, (z, W, fy, by) in enumerate(HEAD_RINGS):
        Wm = W * p["width"]
        if ri <= 2:
            Wm *= p["jaw"] * (1.0 - (0.14, 0.1, 0.05)[ri] * p["fem"])   # queixo e mandíbula mais finos no feminino
        cy, D = (fy + by) / 2, (by - fy) / 2
        row = []
        for deg in COL_DEG:
            th = math.radians(deg)
            sn, cs = math.sin(th), math.cos(th)
            nf = 3.2 if cs > 0 else 2.2          # frente mais plana, nuca arredondada
            x = Wm * math.copysign(abs(sn) ** (2 / nf), sn)
            y = cy - D * math.copysign(abs(cs) ** (2 / nf), cs)
            dx, dy = _feature(ri, abs(deg), p)
            if sn:
                x += math.copysign(dx, sn)
            row.append(Vector((x, y + dy, z)))
        pts.append(row)
    return pts


def _front_y(pts, ri, x):
    """y da superfície frontal do anel ri na posição lateral |x| (entre as colunas 0, 32 e 68)."""
    x = abs(x)
    cols = [pts[ri][0], pts[ri][1], pts[ri][2]]
    for a, b in zip(cols, cols[1:]):
        if a.x <= x <= b.x:
            t = (x - a.x) / max(1e-6, b.x - a.x)
            return a.y + (b.y - a.y) * t
    return cols[-1].y


def _front_y_at(pts, z, x):
    for i in range(len(HEAD_RINGS) - 1):
        z0, z1 = HEAD_RINGS[i][0], HEAD_RINGS[i + 1][0]
        if z0 <= z <= z1:
            t = (z - z0) / (z1 - z0)
            return _front_y(pts, i, x) * (1 - t) + _front_y(pts, i + 1, x) * t
    return _front_y(pts, len(HEAD_RINGS) - 1, x)


def _mesh(name, verts, faces, material, parent, thick=0.0):
    bm = bmesh.new()
    vv = [bm.verts.new(v) for v in verts]
    for f in faces:
        bm.faces.new([vv[i] for i in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method='BEAUTY')
    if thick:
        bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=thick)
    _place(bm, (0, 0, 0), parent)
    return _finish(name, bm, material, parent)


def human_head(prefix, chin_z, height, parent, mats, params=None, y0=0.0):
    """Cria cabeça, olhos, sobrancelhas, nariz, traço da boca e orelhas no estilo low poly desenhado.
    mats: skin, pupil (olho), sclera (brilho), brow, lip; opcionais: mouth, lash.
    Retorna marcos em metros (queixo, olhos, boca, frente do rosto...)."""
    p = dict(HEAD_DEFAULTS)
    p.update(params or {})
    s = height / 23.0
    pts = head_points(p)

    def m(x, y, z):
        return (x * s, y0 + y * s, chin_z + z * s)

    # ---- crânio e rosto: anéis triangulados, shading flat
    n = len(COL_DEG)
    verts = [m(v.x, v.y, v.z) for row in pts for v in row]
    faces = []
    for i in range(len(pts) - 1):
        for j in range(n):
            a, b = i * n + j, i * n + (j + 1) % n
            faces.append((a, b, b + n, a + n))
    top = len(verts)
    verts.append(m(0, 0.6, TOP_Z))
    last = (len(pts) - 1) * n
    faces += [(last + j, last + (j + 1) % n, top) for j in range(n)]
    bot = len(verts)
    verts.append(m(0, -2.6, 0.6))
    faces += [((j + 1) % n, j, bot) for j in range(n)]
    _mesh(prefix + "HeadMesh", verts, faces, mats["skin"], parent)

    es, fem = p["eye_size"], p["fem"]
    ex, ez = 3.05 * p["width"], 11.5
    dark = mats.get("pupil") or mats["lash"]
    for sg, nm in ((1, "L"), (-1, "R")):
        x = sg * ex
        # olho: amêndoa escura dentro da órbita + ponto de brilho
        ey = _front_y_at(pts, ez, ex) - 0.1
        tbox(prefix + "Eye" + nm, m(x, ey, ez), (2.3 * es * s, 0.5 * s, 1.05 * es * s), dark,
             top=(0.8, 1.0), bottom=(0.65, 1.0), shift_top=(sg * 0.12 * s, 0), rot=(0, -sg * 0.06, 0), parent=parent)
        if mats.get("sclera"):
            tbox(prefix + "EyeShine" + nm, m(x + sg * 0.45, ey - 0.27, ez + 0.2), (0.42 * s, 0.1 * s, 0.4 * s),
                 mats["sclera"], parent=parent)
        if fem:   # traço de cílio na ponta externa
            limb(prefix + "Lash" + nm, m(x + sg * 1.0 * es, ey - 0.05, ez + 0.3), m(x + sg * 1.75 * es, ey + 0.25, ez + 0.75),
                 0.24 * s, 0.03 * s, dark, sides=4, flat=0.5, parent=parent)
        # sobrancelha em cunha: grossa por dentro, fina por fora, sobre o arco
        bt = (0.5 if fem else 0.62) * p["brow"] + 0.15 * p["age"]
        bz_in, bz_out = 13.35, 13.25 + (0.35 * fem) - 0.4 * p["age"]
        limb(prefix + "Brow" + nm, m(sg * 1.25, _front_y_at(pts, bz_in, 1.25) - 0.15, bz_in),
             m(sg * 4.7 * p["width"], _front_y_at(pts, bz_out, 4.7) + 0.05, bz_out),
             bt * s, bt * 0.45 * s, mats["brow"], sides=4, flat=0.55, parent=parent)
        # orelha: cunha simples, inclinada para trás
        exr = 6.9 * p["width"] + 0.3
        tbox(prefix + "Ear" + nm, m(sg * exr, 0.9, 9.9), (0.9 * s, 2.6 * p["ear"] * s, 5.0 * p["ear"] * s), mats["skin"],
             top=(1.0, 1.15), bottom=(0.7, 0.6), shift_bottom=(0, -0.3 * s), rot=(0, 0, sg * 0.3), parent=parent)

    # ---- nariz em cunha: dorso com duas faces laterais e base plana (como nos bustos facetados)
    nn, nw = p["nose"], p["nose_w"]
    Fr = _front_y_at(pts, 12.0, 0)
    Fb = _front_y_at(pts, 7.0, 0)
    nv = [
        (0, Fr + 0.3, 12.0),               # 0 raiz
        (0, Fb - 2.0 * nn, 7.5),           # 1 ponta
        (0, Fb - 0.75 * nn, 6.55),         # 2 base (subnasal)
        (1.3 * nw, Fb + 0.1, 6.95),        # 3 asa E
        (-1.3 * nw, Fb + 0.1, 6.95),       # 4 asa D
        (0.75 * nw, Fr + 0.45, 10.6),      # 5 lateral alta E
        (-0.75 * nw, Fr + 0.45, 10.6),     # 6 lateral alta D
    ]
    _mesh(prefix + "Nose", [m(*v) for v in nv], [(0, 1, 3, 5), (1, 2, 3), (0, 6, 4, 1), (1, 4, 2)],
          mats["skin"], parent, thick=0.25 * s)

    # ---- boca: só um traço curto e levemente curvo (sem lábios modelados)
    mz = 4.75
    mw = 1.25 * p["mouth_w"] * (0.92 if fem else 1.0)
    my = _front_y_at(pts, mz, 0) - 0.05
    mouth_m = mats.get("mouth") or mats["lip"]
    for sg, nm in ((1, "L"), (-1, "R")):
        tbox(prefix + "Mouth" + nm, m(sg * mw / 2, my + 0.03 * mw, mz + 0.05), (mw * s, 0.35 * s, 0.3 * s), mouth_m,
             rot=(0, -sg * 0.1, 0), parent=parent)
    # sombra do lábio inferior: plano curto um tom abaixo da pele, só sugerido
    tbox(prefix + "LipShade", m(0, my + 0.12, mz - 0.75), (1.5 * mw * s, 0.25 * s, 0.35 * s), mouth_m,
         top=(1.0, 1.0), bottom=(0.6, 1.0), parent=parent)

    return {
        "s": s, "chin": chin_z, "top": chin_z + TOP_Z * s, "eye_z": chin_z + ez * s,
        "mouth_z": chin_z + mz * s, "nose_base_z": chin_z + 6.55 * s, "brow_z": chin_z + 13.4 * s,
        "front_y": y0 + pts[5][0].y * s, "mouth_y": y0 + my * s, "chin_y": y0 + pts[1][0].y * s,
        "half_w": 7.2 * p["width"] * s, "back_y": y0 + 9.7 * s, "cy": y0 + 0.45 * s,
        "eye_x": ex * s, "eye_y": y0 + (_front_y_at(pts, ez, ex) - 0.1) * s,
    }


# ------------------------------------------------------------------ cabelo em mechas facetadas
# Cada mecha é uma tira com seção em losango (aresta viva no meio, como nos bustos low poly de referência)
# que segue a superfície do crânio de um ponto a outro, pode cair na vertical abaixo do crânio e
# termina em ponta. Ângulos: phi = 0 na frente do rosto, positivo para a esquerda do personagem (+X);
# theta = elevação a partir do centro do crânio (90 = topo).
def _hdir(phi, th):
    p, t = math.radians(phi), math.radians(th)
    return Vector((math.cos(t) * math.sin(p), -math.cos(t) * math.cos(p), math.sin(t)))


def _slerp(a, b, t):
    om = a.angle(b)
    if om < 1e-5:
        return a.copy()
    return (a * math.sin((1 - t) * om) + b * math.sin(t * om)) / math.sin(om)


def _lock_mesh(name, pts, widths, thick, center, material, parent):
    bm = bmesh.new()
    secs = []
    last = len(pts) - 1
    for i, p in enumerate(pts):
        if i == last:
            secs.append([bm.verts.new(p)])
            continue
        tan = (pts[min(i + 1, last)] - pts[max(i - 1, 0)]).normalized()
        out = p - center
        out = (out - tan * out.dot(tan)).normalized()
        side = tan.cross(out).normalized()
        w, t = widths[i] / 2, thick[i]
        secs.append([bm.verts.new(p - side * w), bm.verts.new(p + out * t), bm.verts.new(p + side * w),
                     bm.verts.new(p - out * t * 0.35)])
    bm.faces.new(secs[0])
    for a, b in zip(secs, secs[1:]):
        for k in range(4):
            if len(b) == 1:
                bm.faces.new((a[k], a[(k + 1) % 4], b[0]))
            else:
                bm.faces.new((a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method='BEAUTY')
    _place(bm, (0, 0, 0), parent)
    return _finish(name, bm, material, parent)


def hair_locks(prefix, H, specs, material, parent, scale=1.04):
    """specs: lista de dicts com a=(phi, theta) raiz, b=(phi, theta) fim sobre o crânio e opcionais
    drop (m, queda vertical depois de b), w (largura da raiz, m), t (espessura), lift (afastamento do crânio),
    bulge (volume extra no meio), flare (abertura para fora na queda), n (segmentos sobre o crânio)."""
    s = H["s"]
    C = Vector((0, H.get("cy", 0.45 * s), H["chin"] + 12.0 * s))
    rx, ryf, ryb, rz = 7.25 * s * scale, 9.6 * s * scale, 9.8 * s * scale, 11.0 * s * scale
    for i, L in enumerate(specs):
        n = L.get("n", 5)
        da, db = _hdir(*L["a"]), _hdir(*L["b"])
        pts = []
        for k in range(n + 1):
            d = _slerp(da, db, k / n)
            P = C + Vector((d.x * rx, d.y * (ryf if d.y < 0 else ryb), d.z * rz))
            lift = L.get("lift", 0.004) + L.get("bulge", 0.01) * math.sin(math.pi * k / n)
            pts.append(P + (P - C).normalized() * lift)
        drop = L.get("drop", 0.0)
        if drop:
            pe = pts[-1]
            hout = Vector((pe.x - C.x, pe.y - C.y, 0)).normalized()
            for j in (1, 2):
                pts.append(pe + Vector((0, 0, -drop * j / 2)) + hout * L.get("flare", 0.008) * j / 2)
        N = len(pts) - 1
        w, t = L.get("w", 0.035), L.get("t", 0.011)
        widths = [w * (1 - k / N) ** 0.75 for k in range(N + 1)]
        thick = [t * (1 - 0.5 * k / N) for k in range(N + 1)]
        _lock_mesh("%sLock%02d" % (prefix, i), pts, widths, thick, C, material, parent)
