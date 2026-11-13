# Espadas do jogo (GLB w_<id>.glb). Carregado por build_assets.py via exec (usa mat, part, empty,
# join_all, export, hexc). Convenção: centro do cabo na origem, lâmina subindo em +Z, largura em X,
# espessura em Y. O empty "Tip" marca a ponta (o jogo usa para rastro/alcance).
# knight_look.gd instancia o GLB no WeaponHolder quando o item tem "model".
import math
from mathutils import Vector
from mathutils import geometry as mgeo

WEAPONS = []   # nomes dos builders, registrados em BUILDERS


# ------------------------------------------------------------------ pintura por vértice
# Cor por vértice (atributo "Col", sRGB) faz o papel da textura pintada: degradês, gume escuro,
# sombra nos sulcos. O material vc_mat liga "Col" direto na cor base, então o glTF exporta COLOR_0
# e o Godot usa a cor do vértice como albedo. Uma arma pintada assim tem um material só.
def srgb(hx):
    hx = hx.lstrip("#")
    return tuple(int(hx[i:i + 2], 16) / 255 for i in (0, 2, 4))


def mix(a, b, t):
    t = min(max(t, 0.0), 1.0)
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def smooth01(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3 - 2 * t)


def ramp(stops, t):
    """stops: [(t, cor)] crescente -> cor interpolada."""
    if t <= stops[0][0]:
        return stops[0][1]
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t <= t1:
            return mix(c0, c1, (t - t0) / (t1 - t0))
    return stops[-1][1]


LIGHT = Vector((-0.45, -0.65, 0.6)).normalized()   # luz pintada: frente, esquerda, de cima


def vc_mat(name, rough=0.55, metal=0.0, spec=0.2):
    """spec baixo: o reflexo rasante (Fresnel) clareia o gume e apaga o contorno escuro pintado."""
    m = mat(name, (1, 1, 1), rough, metal)
    nt = m.node_tree
    b = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    if "Specular IOR Level" in b.inputs:
        b.inputs["Specular IOR Level"].default_value = spec
    ca = next((n for n in nt.nodes if n.type == 'VERTEX_COLOR'), None) or nt.nodes.new("ShaderNodeVertexColor")
    ca.layer_name = "Col"
    nt.links.new(ca.outputs["Color"], b.inputs["Base Color"])
    return m


def paint(ob, fn):
    """fn(co, normal, índice_do_vértice) -> (r, g, b) sRGB, gravado por canto em 'Col'."""
    me = ob.data
    a = me.color_attributes.get("Col") or me.color_attributes.new("Col", 'BYTE_COLOR', 'CORNER')
    cache = {}
    for li, lp in enumerate(me.loops):
        vi = lp.vertex_index
        if vi not in cache:
            v = me.vertices[vi]
            cache[vi] = fn(v.co, v.normal, vi)
        a.data[li].color_srgb = (*cache[vi], 1.0)
    return ob


def _mk(name, bm, material, smooth=True):
    print("PART", name, "mesh", flush=True)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.00005)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.validate()
    for p in me.polygons:
        p.use_smooth = smooth
    me.materials.append(material)
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    return ob


def _inside(p, poly):
    c, j = False, len(poly) - 1
    for i in range(len(poly)):
        a, b = poly[i], poly[j]
        if (a.y > p.y) != (b.y > p.y) and p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x:
            c = not c
        j = i
    return c


def _seg_d(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-12)))
    return (a + ab * t - p).length


def _densify(pts, sp):
    out = []
    for i, a in enumerate(pts):
        b = pts[(i + 1) % len(pts)]
        k = max(1, int((b - a).length / sp))
        out += [a.lerp(b, j / k) for j in range(k)]
    return out


def _signed(pts):
    return sum(a.x * b.y - b.x * a.y for a, b in zip(pts, pts[1:] + pts[:1]))


def slab(name, outline, material, th, bevel, color=None, step=0.02, ridge=0.25, holes=()):
    """Lâmina 'inflada' a partir de um contorno 2D [(x, z)] no plano XZ (qualquer sentido), com furos opcionais.
    Espessura (meia) vai de 0 no gume a th, numa faixa arredondada de largura `bevel`, mais um leve
    abaulado no miolo (ridge). color(x, z, d) -> sRGB por vértice (d = distância ao contorno); sem color,
    a peça fica sem pintura (para textura projetada)."""
    pts = [Vector(p) for p in outline]
    if _signed(pts) < 0:
        pts.reverse()                                   # externo anti-horário: normal à esquerda aponta para dentro
    dense = _densify(pts, step * 0.7)
    hl = []
    for h in holes:
        hp = [Vector(p) for p in h]
        if len(hp) < 3 or not _inside(hp[0], dense):
            continue
        if _signed(hp) > 0:
            hp.reverse()                                # furo horário: a normal à esquerda também aponta para o material
        hl.append(_densify(hp, step * 0.5))
    loops = [dense] + hl
    segs = [s for L in loops for s in zip(L, L[1:] + L[:1])]

    def dist(p):
        return min(_seg_d(p, a, b) for a, b in segs)

    def solid(p):
        return _inside(p, dense) and not any(_inside(p, h) for h in hl)

    inner = []
    for L in loops:
        n = len(L)
        for i in range(n):
            t = (L[(i + 1) % n] - L[i - 1]).normalized()
            q = L[i] + Vector((-t.y, t.x)) * bevel
            if solid(q) and dist(q) > bevel * 0.8:
                inner.append(q)
    lo = Vector((min(p.x for p in dense), min(p.y for p in dense)))
    hi = Vector((max(p.x for p in dense), max(p.y for p in dense)))
    z, row = lo.y, 0
    while z < hi.y:
        x = lo.x + (step / 2 if row % 2 else 0)
        while x < hi.x:
            q = Vector((x, z))
            if solid(q) and dist(q) > bevel * 1.4:
                inner.append(q)
            x += step
        z += step * 0.866
        row += 1
    keep = []
    for q in inner:
        if all((q - k).length > step * 0.4 for k in keep):
            keep.append(q)
    verts = [tuple(p) for L in loops for p in L] + [tuple(p) for p in keep]
    edges, base = [], 0
    for L in loops:
        edges += [(base + i, base + (i + 1) % len(L)) for i in range(len(L))]
        base += len(L)
    co, _e, faces, *_ = mgeo.delaunay_2d_cdt(verts, edges, [list(range(len(dense)))], 1, 1e-6)
    faces = [f for f in faces if not any(_inside(Vector(((co[f[0]][0] + co[f[1]][0] + co[f[2]][0]) / 3,
                                                         (co[f[0]][1] + co[f[1]][1] + co[f[2]][1]) / 3)), h)
                                         for h in hl)]
    ds = [dist(Vector(c)) for c in co]
    dmax = max(ds) or 1.0
    bm = bmesh.new()
    front, back, vcol = [], [], {}
    for c, d in zip(co, ds):
        u = min(d / bevel, 1.0)
        t = th * (1 - ridge) * math.sin(u * math.pi / 2) + th * ridge * (d / dmax)
        if color:
            vcol[(round(c[0], 5), round(c[1], 5))] = color(c[0], c[1], d)
        if d < 1e-6:
            v = bm.verts.new((c[0], 0.0, c[1]))
            front.append(v)
            back.append(v)
        else:
            front.append(bm.verts.new((c[0], -t, c[1])))
            back.append(bm.verts.new((c[0], t, c[1])))
    for f in faces:
        for side in (front, back):
            try:
                bm.faces.new([side[i] for i in f])
            except ValueError:
                pass
    ob = _mk(name, bm, material)
    if not color:
        return ob
    return paint(ob, lambda c, nrm, vi: vcol.get((round(c.x, 5), round(c.z, 5))) or color(c.x, c.z, 0.0))


def torus(name, c, R, r, material, seg=16, sides=8, color=None):
    """Anel no plano XZ (de frente para a câmera), centro c=(x, z)."""
    bm = bmesh.new()
    rings = []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        rings.append([bm.verts.new((c[0] + (R + r * math.cos(b)) * math.cos(a), r * math.sin(b),
                                    c[1] + (R + r * math.cos(b)) * math.sin(a)))
                      for b in (2 * math.pi * j / sides for j in range(sides))])
    for i in range(seg):
        A, B = rings[i], rings[(i + 1) % seg]
        for j in range(sides):
            j2 = (j + 1) % sides
            bm.faces.new((A[j], B[j], B[j2], A[j2]))
    ob = _mk(name, bm, material)
    return paint(ob, color) if color else ob


def lathe(name, prof, material, seg=10, x=0.0, phase=0.0, color=None, smooth=True):
    """Sólido de revolução em torno do eixo Z (em x, y=0). prof [(z, r)] ou [(z, r, x)] (centro por linha);
    r=0 fecha num polo."""
    bm = bmesh.new()
    rows = []
    for row in prof:
        z, r = row[0], row[1]
        xc = row[2] if len(row) > 2 else x
        if r <= 1e-6:
            rows.append([bm.verts.new((xc, 0, z))])
        else:
            rows.append([bm.verts.new((xc + r * math.cos(phase + 2 * math.pi * k / seg),
                                       r * math.sin(phase + 2 * math.pi * k / seg), z)) for k in range(seg)])
    for A, B in zip(rows, rows[1:]):
        for k in range(seg):
            k2 = (k + 1) % seg
            q = [A[k % len(A)], A[k2 % len(A)], B[k2 % len(B)], B[k % len(B)]]
            q = [v for i, v in enumerate(q) if v not in q[:i]]
            if len(q) >= 3:
                try:
                    bm.faces.new(q)
                except ValueError:
                    pass
    ob = _mk(name, bm, material, smooth)
    return paint(ob, color) if color else ob


def finish(asset, tip_x, tip_z):
    meshes = [o for o in coll.all_objects if o.type == 'MESH']
    if any("Col" in o.data.color_attributes for o in meshes):   # sem isso o join preenche de preto
        for o in meshes:
            if "Col" not in o.data.color_attributes:
                paint(o, lambda c, n, i: (1.0, 1.0, 1.0))
    join_all("Weapon")
    empty("Tip", (tip_x, 0, tip_z))
    export(asset)


# ------------------------------------------------------------------ espadas traçadas da folha de conceito
# trace_swords.py lê refs/espadas.webp (local) e grava traced/espadas_trace.json (contornos e perfis em pixels
# da folha) e traced/tex/<id>.png (recorte com o fundo preenchido). Aqui cada peça plana vira slab() e cada cabo/pomo
# vira lathe(); a pintura da folha entra como textura projetada de frente (UV = posição na folha), então
# degradês, sombras e frisos pintados chegam ao jogo como na referência. Um material por espada.
import json
REFS = OUT.replace("assets/models/", "tools/blender/traced/")
TRACE_S = 1.2 / 426            # mesma escala da Chama Rosada: 426 px da folha = 1,2 m
_TRACE = {}


def tex_mat(name, png, rough=0.6, spec=0.12):
    m = mat(name, (1, 1, 1), rough, 0.0)
    nt = m.node_tree
    b = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    if "Specular IOR Level" in b.inputs:
        b.inputs["Specular IOR Level"].default_value = spec
    tx = next((n for n in nt.nodes if n.type == 'TEX_IMAGE'), None) or nt.nodes.new("ShaderNodeTexImage")
    tx.image = bpy.data.images.load(png, check_existing=True)
    nt.links.new(tx.outputs["Color"], b.inputs["Base Color"])
    return m


def project_uv(ob, fn):
    me = ob.data
    uv = me.uv_layers.get("UVMap") or me.uv_layers.new(name="UVMap")
    for li, lp in enumerate(me.loops):
        uv.data[li].uv = fn(me.vertices[lp.vertex_index].co)


def build_traced(sid):
    if not _TRACE:
        with open(REFS + "espadas_trace.json", encoding="utf-8") as f:
            _TRACE.update(json.load(f))
    d = _TRACE[sid]
    x0, y0, x1, y1 = d["box"]
    gx, gy = d["grip"]
    S = TRACE_S

    def P(x, y):
        return ((x - gx) * S, (gy - y) * S)

    def uvf(c):
        return ((c.x / S + gx - x0) / (x1 - x0), 1 - ((gy - c.z / S) - y0) / (y1 - y0))

    m = tex_mat(sid + "_tex", REFS + "tex/" + sid + ".png")
    tip = (0.0, 0.0)
    for p in d["parts"]:
        if p["kind"] == "slab":
            ol = [P(*q) for q in p["outline"]]
            ob = slab(p["name"], ol, m, p["th"], p["bevel"], step=0.022,
                      holes=[[P(*q) for q in h] for h in p["holes"]])
            tip = max([tip] + ol, key=lambda q: q[0] * q[0] + q[1] * q[1])
        else:
            prof = [((gy - y) * S, r * S, (cx - gx) * S) for y, cx, r in p["prof"]]
            prof = [(prof[0][0], 0.0, prof[0][2])] + prof + [(prof[-1][0], 0.0, prof[-1][2])]
            ob = lathe(p["name"], prof, m, seg=p.get("seg", 8))
        project_uv(ob, uvf)
    finish(sid, *tip)


# ------------------------------------------------------------------ 15. Chama Rosada
# Traçada da folha de conceito (coordenadas em pixels da folha 1080x1080; px() converte para metros,
# com o centro do cabo em (61.5, 403)). Pintura por vértice com a paleta amostrada da folha.
ROSE_S = 1.2 / 426


def _px(x, y):
    return ((x - 61.5) * ROSE_S, (403.0 - y) * ROSE_S)


def _unpx(x, z):
    return (x / ROSE_S + 61.5, 403.0 - z / ROSE_S)


ROSE_BLADE = [(58, 341), (60, 326), (61, 312), (62, 298), (63, 284), (63, 270), (62, 258), (60, 248), (57, 238),
              (53, 228), (49, 218), (44, 210), (41, 206), (37, 221), (33, 211), (29, 203), (25, 192), (21, 181),
              (18, 172), (15, 162), (12, 148), (10, 130), (10, 114), (11, 102), (13, 90), (16, 78), (19, 66),
              (22, 55), (25, 45), (27, 37),
              (29, 50), (30, 66), (31, 80), (34, 92), (37, 104), (41, 114), (45, 123), (51, 130), (57, 134),
              (66, 124), (69, 116), (72, 128), (74, 141), (76, 155), (77, 167), (79, 181), (82, 190), (88, 185),
              (94, 178), (95, 188), (93, 200), (91, 212), (89, 224), (88, 236), (90, 244), (95, 249), (100, 252),
              (97, 258), (94, 265), (92, 274), (90, 286), (90, 298), (93, 306), (97, 312), (91, 318), (86, 324),
              (81, 331), (77, 341)]
# faixa ciano que desce pelo pé da lâmina
ROSE_SWIRL = [(60, 236), (62, 245), (68, 260), (74, 275), (77, 288), (75, 302), (68, 311), (62, 320), (57, 330)]
# (y, esquerda, centro, direita, gume) — esquerda sombreada, centro claro, direita magenta intenso
ROSE_RAMP = [(40, "#9a2262", "#e0509a", "#962a64", "#4a1434"),
             (110, "#b02a78", "#f477b8", "#b8307e", "#5e1a40"),
             (160, "#a02868", "#ec6aae", "#c4106e", "#5c1638"),
             (200, "#b83c6c", "#fb7c9c", "#d01c58", "#7a2238"),
             (235, "#d87e88", "#ffa0a4", "#d44c64", "#88383f"),
             (270, "#e8cdd2", "#fdb4b0", "#e88a88", "#8c4446"),
             (335, "#dcdae2", "#f6baae", "#d87478", "#965258")]


def _span(poly, y):
    xs = sorted(a[0] + (y - a[1]) * (b[0] - a[0]) / (b[1] - a[1])
                for a, b in zip(poly, poly[1:] + poly[:1]) if (a[1] > y) != (b[1] > y))
    return (xs[0], xs[-1]) if len(xs) >= 2 else None


def _poly_x(line, y):
    for a, b in zip(line, line[1:]):
        if min(a[1], b[1]) <= y <= max(a[1], b[1]):
            return a[0] + (y - a[1]) * (b[0] - a[0]) / max(b[1] - a[1], 1e-6)
    return None


def _rose_blade_col(x, z, d):
    px, py = _unpx(x, z)
    dp = d / ROSE_S
    cols = [(s[0], [srgb(h) for h in s[1:]]) for s in ROSE_RAMP]
    L, C, R, E = (ramp([(y, c[k]) for y, c in cols], py) for k in range(4))
    sp = _span(ROSE_BLADE, py)
    u = (px - sp[0]) / max(sp[1] - sp[0], 1e-6) if sp else 0.5
    base = mix(L, C, smooth01((u - 0.05) / 0.4)) if u < 0.45 else mix(C, R, smooth01((u - 0.6) / 0.35))
    sx = _poly_x(ROSE_SWIRL, py)
    if sx is not None and py > 240 and px < sx:           # prata à esquerda da faixa ciano
        base = mix(base, srgb("#d4dce4"), smooth01((py - 240) / 25))
    return mix(E, base, smooth01((dp - 1.0) / 4.5))       # gume escuro largo, como o contorno pintado


def _ribbon(line, w0, w1):
    """Contorno de uma fita ao longo de uma polilinha 2D, largura w0 -> w1 (afina nas pontas)."""
    P = [Vector(p) for p in line]
    for _ in range(2):                                    # Chaikin: tira os cantos da polilinha
        P = [P[0]] + [q for a, b in zip(P, P[1:]) for q in (a.lerp(b, 0.25), a.lerp(b, 0.75))] + [P[-1]]
    L, R = [], []
    for i, p in enumerate(P):
        t = (P[min(i + 1, len(P) - 1)] - P[max(i - 1, 0)]).normalized()
        f = i / (len(P) - 1)
        w = (w0 + (w1 - w0) * f) * min(1.0, 1.8 * math.sin(math.pi * f)) if 0 < i < len(P) - 1 else 0.0
        nrm = Vector((-t.y, t.x)) * w
        L.append(p + nrm)
        R.append(p - nrm)
    return [tuple(v) for v in L] + [tuple(v) for v in reversed(R[1:-1])]


def _rose_silver(x, z, d):
    return mix(srgb("#7f9ca2"), mix(srgb("#e9eef0"), srgb("#b7c4cc"), (_unpx(x, z)[1] - 320) / 30),
               smooth01(d / ROSE_S / 3))


def _lit(dark, light, base):
    """Sombra pintada: dark -> base -> light conforme a normal encara a luz LIGHT."""
    def fn(c, n, i):
        return ramp([(-0.7, dark), (0.1, base), (0.9, light)], n.dot(LIGHT))
    return fn


def build_w_rose_flame():
    vm = vc_mat("w_rose_vc", 0.5, 0.0, 0.25)
    slab("Blade", [_px(*p) for p in ROSE_BLADE], vm, th=0.012, bevel=0.016, color=_rose_blade_col, step=0.022)
    # faixa ciano: fita própria, um pouco mais grossa que a lâmina (aflora dos dois lados, borda limpa)
    slab("Swirl", _ribbon([_px(*p) for p in ROSE_SWIRL], 4.4 * ROSE_S, 3.0 * ROSE_S), vm, th=0.0118,
         bevel=0.0012, step=0.012, ridge=0.0,
         color=lambda x, z, d: mix(srgb("#1c6f9c"), srgb("#86d4f4"), smooth01(d / ROSE_S / 1.6)))
    slab("WingL", [_px(*p) for p in ((62, 319), (50, 325), (31, 331), (47, 337), (39, 348), (56, 342), (62, 338))],
         vm, th=0.006, bevel=0.008, color=_rose_silver, step=0.015)
    slab("WingR", [_px(*p) for p in ((77, 334), (85, 339), (94, 350), (84, 350), (77, 346))],
         vm, th=0.006, bevel=0.008, color=_rose_silver, step=0.015)
    torus("GuardRing", _px(63, 352), 11.5 * ROSE_S, 5.5 * ROSE_S, vm, seg=16, sides=8,
          color=_lit(srgb("#0c4a74"), srgb("#8adcff"), srgb("#1f8fc4")))
    disc = part("GuardDisc", "cyl", (_px(63, 352)[0], 0, _px(63, 352)[1]), (18 * ROSE_S, 18 * ROSE_S, 0.018), vm,
                rot=(1.5708, 0, 0), seg=12, smooth=True)
    cz = _px(63, 352)
    paint(disc, lambda c, n, i: mix(srgb("#fde0d2"), srgb("#e9a08e"),
                                    math.hypot(c.x - cz[0], c.z - cz[1]) / (9 * ROSE_S)))
    gz = [_px(0, y)[1] for y in (441, 362)]          # entra no anel e no pomo: sem fresta
    h = (gz[1] - gz[0]) / 6
    rmin, rmax = 9.0 * ROSE_S, 10.5 * ROSE_S
    prof = [(gz[0], 0.0), (gz[0], rmin)]
    for k in range(6):
        z0 = gz[0] + k * h
        prof += [(z0 + h * 0.3, rmax), (z0 + h * 0.7, rmax), (z0 + h, rmin)]
    prof.append((gz[1], 0.0))
    groove = lambda c: (math.hypot(c.x, c.y) - rmin) / (rmax - rmin)
    lathe("Grip", prof, vm, seg=10, color=lambda c, n, i: mix(srgb("#3e1644"), _lit(
        srgb("#4e1c50"), srgb("#b0559a"), srgb("#843a78"))(c, n, i), 0.5 + 0.5 * groove(c)))
    pz = [_px(0, y)[1] for y in (464, 448, 438)]
    lathe("Pommel", [(pz[0], 0.0), (pz[1], 14 * ROSE_S), (pz[2], 9 * ROSE_S), (pz[2], 0.0)], vm, seg=4,
          smooth=False,
          color=lambda c, n, i: mix(_lit(srgb("#4f5c78"), srgb("#eef2f8"), srgb("#a2adc4"))(c, n, i),
                                    srgb("#3d9ccc"), max(0.0, (c.z - pz[1]) / (pz[2] - pz[1])) * 0.55))
    finish("w_rose_flame", *_px(27, 37))


for _sid in ("w_azure_edge", "w_thorn_root", "w_crystal_frost", "w_moon_crescent", "w_royal_wings", "w_venom_leaf",
             "w_neon_edge", "w_titan_cleaver", "w_amber_fang", "w_coral_spine", "w_ivory_wing", "w_scarlet_talon",
             "w_crimson_reed", "w_pale_crescent"):
    WEAPONS.append((_sid, lambda _sid=_sid: build_traced(_sid)))
WEAPONS.append(("w_rose_flame", build_w_rose_flame))
