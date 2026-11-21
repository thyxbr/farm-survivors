# Cajados (st_<id>.glb), cetros (sc_<id>.glb), arcos (bw_<id>.glb + bw_arrow.glb) e as espadas clássicas (w_<id>.glb) que antes eram
# montadas no código com caixas e cilindros. Carregado por build_assets.py via exec, depois de weapons.py (usa
# slab, w_lathe, torus, paint, vc_mat, srgb, mix, ramp, smooth01, finish, WEAPONS).
#
# Convenções (todas com o centro da empunhadura na origem, frente = -Y):
#   cajado  st_*: haste em +Z, ponta de baixo em z≈-0,55, cabeça entre 0,85 e 1,25; "Tip" = centro da gema.
#                 Empunhadura em z = STAFF_HAND (0,3), o meio da vara, onde a mão do personagem fica.
#   arco    bw_*: braços em ±Z, curvados para +Y (lado do arqueiro); corda em y = ponta dos braços.
#                 "Nock" = centro da corda (onde a flecha encaixa), "Tip" = 0,3 m à frente. A corda não vai no
#                 GLB: "StringTop"/"StringBot" marcam as pontas dela e o jogo a desenha (e puxa até os dedos).
#   flecha  bw_arrow: ao longo de -Y a partir da corda (ponta em y≈-0,75).
#   espada  w_*: lâmina em +Z, largura em X, costas das lâminas curvas em -X (mesma regra de weapons.py).
#
# Pintura: estilo anime em 3 tons (sombra / base / luz) gravado por canto na cor do vértice (cel()); os materiais
# terminam em "_flat" para o toon do jogo não somar a sua própria sombra de forma por cima. Gemas e runas usam um
# segundo material com emissão.
import colorsys
from mathutils import Matrix, Euler

ARMORY = []          # (asset, builder) — entram em WEAPONS no fim do arquivo


def H(hx):
    return srgb(hx)


def _hue_to(h, target, amt):
    d = ((target - h + 0.5) % 1.0) - 0.5
    return (h + d * amt) % 1.0


def tones(c):
    """Sombra fria e arroxeada, luz quente — como na pintura anime da folha das espadas."""
    h, s, v = colorsys.rgb_to_hsv(*c)
    if s < 0.08:
        sh = colorsys.hsv_to_rgb(0.66, 0.16, v * 0.6)
        li = colorsys.hsv_to_rgb(0.12, 0.05, min(1.0, v * 1.15 + 0.08))
    else:
        sh = colorsys.hsv_to_rgb(_hue_to(h, 0.74, 0.1), min(1.0, s * 1.08 + 0.06), v * 0.6)
        li = colorsys.hsv_to_rgb(_hue_to(h, 0.14, 0.07), s * 0.78, min(1.0, v * 1.17 + 0.08))
    return sh, c, li


CEL = Vector((-0.6, -0.35, 0.72)).normalized()     # luz pintada: esquerda, um pouco à frente, de cima


def cel(ob, col, lo=0.0, hi=0.58):
    """Pinta por face (bandas duras) com a cor base col (sRGB) ou col(co) -> sRGB por canto."""
    me = ob.data
    me.update()
    a = me.color_attributes.get("Col") or me.color_attributes.new("Col", 'BYTE_COLOR', 'CORNER')
    for p in me.polygons:
        d = p.normal.dot(CEL)
        k = 0 if d < lo else (1 if d < hi else 2)
        for li in p.loop_indices:
            c = col(me.vertices[me.loops[li].vertex_index].co) if callable(col) else col
            a.data[li].color_srgb = (*tones(c)[k], 1.0)
    return ob


def vcf(name, rough=0.6, metal=0.0, emit=None, strength=1.0):
    m = vc_mat(name + "_flat", rough, metal, 0.15)
    if emit:
        b = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
        b.inputs["Emission Color"].default_value = (*[x ** 2.2 for x in H(emit)], 1)
        b.inputs["Emission Strength"].default_value = strength * 0.3   # o bloom do jogo já abre bastante
    return m


def place(ob, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    M = Matrix.Translation(Vector(loc)) @ Euler(rot).to_matrix().to_4x4() @ Matrix.Diagonal((*scale, 1))
    ob.data.transform(M)
    ob.data.update()
    return ob


def deform(ob, fn):
    for v in ob.data.vertices:
        v.co = fn(v.co.copy())
    ob.data.update()
    return ob


def spline(ctrl, per=6):
    C = [Vector(c) for c in ctrl]
    out = []
    for i in range(len(C) - 1):
        p0, p1, p2, p3 = C[max(i - 1, 0)], C[i], C[i + 1], C[min(i + 2, len(C) - 1)]
        for k in range(per):
            t = k / per
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(C[-1])
    return out


def tube(name, pts, r, m, col=None, sides=6, flat=1.0, smooth=True, phase=0.0):
    """Tubo ao longo de uma polilinha 3D (quadro por transporte paralelo). r: número, lista ou r(t).
    flat < 1 achata o tubo na direção N (para um tubo vertical, N = Y: braço de arco, fita)."""
    P = [Vector(p) for p in pts]
    n = len(P)
    rs = [r(i / (n - 1)) if callable(r) else (r[i] if isinstance(r, (list, tuple)) else r) for i in range(n)]
    T = [(P[min(i + 1, n - 1)] - P[max(i - 1, 0)]).normalized() for i in range(n)]
    up = Vector((1, 0, 0)) if abs(T[0].x) < 0.9 else Vector((0, 1, 0))
    N = T[0].cross(up).normalized()
    bm = bmesh.new()
    rings = []
    for i in range(n):
        N = (N - T[i] * N.dot(T[i])).normalized()
        B = T[i].cross(N)
        if rs[i] <= 1e-5:
            rings.append([bm.verts.new(P[i])])
            continue
        rings.append([bm.verts.new(P[i] + (N * math.cos(a) * flat + B * math.sin(a)) * rs[i])
                      for a in (phase + 2 * math.pi * k / sides for k in range(sides))])
    for A, Bv in zip(rings, rings[1:]):
        for k in range(sides):
            k2 = (k + 1) % sides
            q = [A[k % len(A)], A[k2 % len(A)], Bv[k2 % len(Bv)], Bv[k % len(Bv)]]
            q = [v for i, v in enumerate(q) if v not in q[:i]]
            if len(q) >= 3:
                try:
                    bm.faces.new(q)
                except ValueError:
                    pass
    for R in (rings[0], rings[-1]):
        if len(R) > 2:
            try:
                bm.faces.new(R)
            except ValueError:
                pass
    ob = _mk(name, bm, m, smooth)
    return cel(ob, col) if col else ob


def lathe(name, prof, m, col=None, seg=8, smooth=True, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1), phase=0.0):
    ob = w_lathe(name, prof, m, seg=seg, smooth=smooth, phase=phase)
    place(ob, loc, rot, scale)
    return cel(ob, col) if col else ob


def flat(name, outline, m, col=None, th=0.008, bevel=0.008, loc=(0, 0, 0), rot=(0, 0, 0), holes=(), step=0.012,
         paint2d=None, bend=None, ridge=0.25):
    """Peça plana (slab) no plano XZ, curvada por bend(co) e posicionada; paint2d(x, z, d) pinta no plano,
    senão cel() pinta em 3 tons depois de posicionada."""
    ob = slab(name, outline, m, th, bevel, color=paint2d, step=step, holes=holes, ridge=ridge)
    if bend:
        deform(ob, bend)
    place(ob, loc, rot)
    return cel(ob, col) if (col and not paint2d) else ob


def crystal(name, m, col, c, r, top, bot, seg=6, mid=0.0, rot=(0, 0, 0), phase=0.0):
    """Cristal facetado: pirâmide dupla (mid=0) ou prisma com pontas (mid = meia altura do corpo)."""
    prof = [(-bot, 0.0), (-mid, r)] + ([(mid, r)] if mid > 0 else []) + [(top, 0.0)]
    ob = w_lathe(name, prof, m, seg=seg, smooth=False, phase=phase)
    place(ob, c, rot)
    return cel(ob, col, lo=-0.1, hi=0.45) if col else ob


def orb(name, m, col, c, r, seg=10, sq=1.0):
    rows = 6
    prof = [(c[2] + r * sq * math.cos(math.pi * (1 - i / rows)), r * math.sin(math.pi * i / rows)) for i in range(rows + 1)]
    prof[0] = (prof[0][0], 0.0)
    prof[-1] = (prof[-1][0], 0.0)
    ob = w_lathe(name, prof, m, seg=seg, smooth=True)
    place(ob, (c[0], c[1], 0))
    return cel(ob, col, lo=-0.15, hi=0.5)


def ring_place(ob_fn, n, r0, z0, tilt, a0=0.0):
    """Repete uma peça plana em volta do eixo Z: ob_fn(i) devolve a peça crua (plano XZ, base em z=0);
    cada cópia inclina `tilt` para fora e gira para o ângulo a0 + i*2π/n."""
    out = []
    for i in range(n):
        a = a0 + 2 * math.pi * i / n
        ob = ob_fn(i)
        place(ob, (0, 0, 0), (tilt, 0, 0))
        place(ob, (math.sin(a) * r0, -math.cos(a) * r0, z0), (0, 0, a))
        out.append(ob)
    return out


# ------------------------------------------------------------------ conferência: tudo preso a tudo
from mathutils.bvhtree import BVHTree
TOUCH = 0.0015       # peças a menos de 1,5 mm contam como encostadas


def _bvh(o):
    me = o.data
    return BVHTree.FromPolygons([v.co.copy() for v in me.vertices], [tuple(p.vertices) for p in me.polygons])


def _touch(a, b, ta, tb):
    if ta.overlap(tb):
        return True
    for o, t in ((a, tb), (b, ta)):
        for v in o.data.vertices:
            hit = t.find_nearest(v.co, TOUCH)
            if hit[0] is not None:
                return True
    return False


def loose_parts(asset):
    """Agrupa as peças que se tocam; mais de um grupo = alguma peça flutua solta. Imprime e devolve os grupos."""
    objs = [o for o in coll.all_objects if o.type == 'MESH']
    trees = {o.name: _bvh(o) for o in objs}
    group = {o.name: i for i, o in enumerate(objs)}
    for i, a in enumerate(objs):
        for b in objs[i + 1:]:
            if group[a.name] != group[b.name] and _touch(a, b, trees[a.name], trees[b.name]):
                old, new = group[b.name], group[a.name]
                for k in group:
                    if group[k] == old:
                        group[k] = new
    comps = {}
    for k, g in group.items():
        comps.setdefault(g, []).append(k)
    comps = sorted(comps.values(), key=len, reverse=True)
    if len(comps) > 1:
        print("LOOSE %s: %s" % (asset, " | ".join(", ".join(sorted(c)) for c in comps[1:])), flush=True)
    else:
        print("CONNECTED %s" % asset, flush=True)
    LOOSE[asset] = comps[1:]
    return comps


LOOSE = {}
_finish_weapon = finish


def finish(asset, tip_x, tip_z):
    """Toda arma (as espadas de weapons.py inclusive) passa pela conferência antes de juntar e exportar."""
    loose_parts(asset)
    _finish_weapon(asset, tip_x, tip_z)


fin = finish


# ------------------------------------------------------------------ peças de cajado
def grain(base, dark, freq=3.0, zf=9.0, amt=0.45):
    b, d = H(base), H(dark)

    def fn(co):
        a = math.atan2(co.y, co.x)
        g = 0.5 + 0.5 * math.sin(a * freq + co.z * zf + math.sin(co.z * 23.0) * 0.8)
        return mix(b, d, amt * smooth01((g - 0.55) / 0.45))
    return fn


def shaft(name, m, col, z0=-0.55, z1=0.9, r0=0.024, r1=0.02, seg=8, wobble=0.0, knots=(), seed=1, step=0.04,
          smooth=True, phase=0.0):
    rnd = random.Random(seed)
    ph1, ph2 = rnd.uniform(0, 6), rnd.uniform(0, 6)
    n = max(2, int((z1 - z0) / step))
    prof = []
    for i in range(n + 1):
        t = i / n
        z = z0 + (z1 - z0) * t
        r = r0 + (r1 - r0) * t
        for kz, ka, kw in knots:
            r += ka * math.exp(-((z - kz) / kw) ** 2)
        x = wobble * math.sin(t * 7 + ph1) * math.sin(t * 3.1 + ph2) * min(1.0, abs(z) / 0.25)
        prof.append((z, r, x))
    prof = [(z0, 0.0, prof[0][2])] + prof + [(z1, 0.0, prof[-1][2])]
    return lathe(name, prof, m, col, seg=seg, smooth=smooth, phase=phase)


def wrap(name, m, col, z0=-0.13, z1=0.13, r=0.027, turns=7, seg=8):
    """Empunhadura enrolada: cristas e sulcos alternados."""
    prof = [(z0, 0.0), (z0, r * 0.92)]
    h = (z1 - z0) / turns
    for k in range(turns):
        zb = z0 + k * h
        prof += [(zb + h * 0.2, r), (zb + h * 0.8, r), (zb + h, r * 0.9)]
    prof.append((z1, 0.0))
    return lathe(name, prof, m, col, seg=seg)


def band(name, m, col, z, h=0.025, r=0.03, seg=8):
    c = h * 0.25
    return lathe(name, [(z - h / 2, 0.0), (z - h / 2, r - c), (z - h / 2 + c, r), (z + h / 2 - c, r),
                        (z + h / 2, r - c), (z + h / 2, 0.0)], m, col, seg=seg, smooth=False)


def ferrule(name, m, col, z0=-0.6, z1=-0.48, r=0.028):
    return lathe(name, [(z0, 0.0), (z0, r * 0.55), (z0 + 0.02, r), (z1 - 0.01, r), (z1, r * 0.8), (z1, 0.0)],
                 m, col, seg=8, smooth=False)


def cup(name, m, col, z0, z1, r0, r1, seg=8):
    """Colar que abre para cima e segura a cabeça do cajado."""
    zm = z0 + (z1 - z0) * 0.55
    return lathe(name, [(z0, 0.0), (z0, r0), (zm, r0 * 1.05), (z1 - 0.008, r1), (z1, r1 * 0.85), (z1, 0.0)],
                 m, col, seg=seg, smooth=False)


def helix(name, m, col, z0, z1, R, turns, r=0.006, phase=0.0, sides=5):
    n = int(turns * 18) + 2
    pts = [(R * math.cos(phase + 2 * math.pi * turns * i / (n - 1)), R * math.sin(phase + 2 * math.pi * turns * i / (n - 1)),
            z0 + (z1 - z0) * i / (n - 1)) for i in range(n)]
    return tube(name, pts, r, m, col, sides=sides)


def leaf_outline(L, W, n=6):
    pts = [(W * math.sin(math.pi * i / n) ** 0.8, L * i / n) for i in range(n + 1)]
    return pts + [(-x, z) for x, z in reversed(pts[1:-1])]


def finish_staff(asset, tip_z):
    fin(asset, 0.0, tip_z)


# ------------------------------------------------------------------ cajados atuais
## O jogo segura o cajado no meio da vara (KnightLook.STAFF_GRIP desce a vara 0,3 m na mão), então a empunhadura
## enrolada fica em z = STAFF_HAND, onde a mão de fato está.
STAFF_HAND = 0.3


def grip_wrap(m, col, **kw):
    return wrap("Grip", m, col, z0=STAFF_HAND - 0.13, z1=STAFF_HAND + 0.13, **kw)


def build_apprentice():
    m = vcf("st_apprentice")
    g = vcf("st_apprentice_gem", emit="#7fb2ff", strength=0.8)
    wood = grain("#b07a48", "#7a4e2a")
    shaft("Shaft", m, wood, z1=0.9, r0=0.022, r1=0.019, wobble=0.006)
    ferrule("Ferrule", m, H("#c9963c"))
    grip_wrap(m, H("#6b4226"))
    band("Collar", m, H("#d7a648"), 0.88, 0.03, 0.026)
    for k in range(3):
        a = 2 * math.pi * k / 3 + 0.5
        ctrl = [(rr * math.cos(a), rr * math.sin(a), z) for rr, z in
                ((0.01, 0.88), (0.035, 0.94), (0.05, 1.0), (0.043, 1.07), (0.016, 1.12))]
        tube("Prong%d" % k, spline(ctrl, 4), lambda t: 0.012 - 0.007 * t, m, wood, sides=6)
    lathe("Seat", [(0.86, 0.0), (0.86, 0.016), (0.975, 0.011), (0.975, 0.0)], m, wood, seg=6)
    crystal("Gem", g, H("#8cc0ff"), (0, 0, 1.02), 0.043, 0.075, 0.055, seg=8, mid=0.015)
    finish_staff("st_apprentice_staff", 1.02)


def build_oak():
    m = vcf("st_oak")
    g = vcf("st_oak_gem", emit="#6fe08a", strength=0.8)
    wood = grain("#6a4628", "#3e2614", amt=0.6)
    shaft("Shaft", m, wood, z1=0.88, r0=0.027, r1=0.023, seg=7, wobble=0.012, seed=4,
          knots=((-0.32, 0.007, 0.03), (0.3, 0.009, 0.035), (0.62, 0.006, 0.025)))
    lathe("Knot", [(-0.03, 0.0), (-0.01, 0.012), (0.012, 0.009), (0.025, 0.0)], m, wood, seg=6,
          loc=(0.02, -0.012, 0.3), rot=(0.4, 1.2, 0))
    ferrule("Ferrule", m, H("#5c5650"))
    grip_wrap(m, H("#3f5a2a"), turns=6)
    tips = []
    for k in range(4):
        a = 2 * math.pi * k / 4 + 0.3
        ctrl = []
        for i, (rr, z) in enumerate(((0.012, 0.84), (0.04, 0.92), (0.065, 1.0), (0.06, 1.08), (0.03, 1.15), (0.012, 1.19))):
            aa = a + i * 0.28
            ctrl.append((rr * math.cos(aa), rr * math.sin(aa), z))
        tips.append(ctrl[3])
        tube("Root%d" % k, spline(ctrl, 4), lambda t: 0.016 - 0.011 * t, m, wood, sides=6)
    lathe("Seat", [(0.84, 0.0), (0.84, 0.018), (0.975, 0.012), (0.975, 0.0)], m, wood, seg=6)
    crystal("Gem", g, H("#7ef09a"), (0, 0, 1.03), 0.04, 0.09, 0.07, seg=6, mid=0.02)
    for k, p in enumerate(tips[:3]):
        a = math.atan2(p[1], p[0])
        lf = flat("Leaf%d" % k, leaf_outline(0.075, 0.022), m, H("#5fae3c"), th=0.004, bevel=0.004, step=0.01,
                  bend=lambda c: Vector((c.x, c.y + 0.6 * c.z * c.z, c.z)))
        place(lf, (0, 0, 0), (0.9, 0, 0))
        place(lf, p, (0, 0, a + math.pi / 2))
        cel(lf, H("#5fae3c"))
    finish_staff("st_oak_staff", 1.03)


def build_ember():
    m = vcf("st_ember")
    g = vcf("st_ember_gem", emit="#ff7a1a", strength=1.2)
    char_b, crack = H("#3a2620"), H("#ff8a3a")

    def charred(co):
        a = math.atan2(co.y, co.x)
        v = abs(math.sin(co.z * 21 + a * 2.0) * math.cos(co.z * 8.5 - a))
        return mix(char_b, crack, smooth01((v - 0.86) / 0.1))
    shaft("Shaft", m, charred, z1=0.88, r0=0.025, r1=0.022, seg=6, wobble=0.007, seed=7, smooth=False)
    ferrule("Ferrule", m, H("#d0952e"))
    grip_wrap(m, H("#7a2418"))
    for z in (0.22, 0.62):
        band("Band%.2f" % z, m, H("#d0952e"), z, 0.022, 0.027, seg=6)
    cup("Cup", m, H("#4a464e"), 0.84, 0.92, 0.026, 0.04, seg=6)
    flame = [(-0.012, 0.0), (0.012, 0.0), (0.03, 0.07), (0.052, 0.13), (0.04, 0.19), (0.05, 0.26), (0.026, 0.2),
             (0.016, 0.12), (-0.006, 0.06)]
    hot = lambda co: mix(H("#4a464e"), H("#ff9a3a"), smooth01((co.z - 1.02) / 0.12))
    for ob in ring_place(lambda i: flat("Prong%d" % i, flame, m, th=0.007, bevel=0.006, step=0.01, loc=(0.022, 0, 0)),
                         4, 0.0, 0.88, 0.0, a0=math.pi / 4):
        cel(ob, hot)
    lathe("Seat", [(0.9, 0.0), (0.9, 0.02), (0.97, 0.012), (0.97, 0.0)], m, H("#4a464e"), seg=6)
    crystal("Gem", g, H("#ffa040"), (0, 0, 1.03), 0.04, 0.14, 0.07, seg=6, mid=0.01)
    finish_staff("st_ember_staff", 1.04)


def build_frost():
    m = vcf("st_frost", metal=0.2)
    g = vcf("st_frost_gem", emit="#8fe6ff", strength=0.9)
    pale = lambda co: mix(H("#d8e4f2"), H("#a8bcd8"), 0.5 + 0.5 * math.sin(co.z * 14))
    shaft("Shaft", m, pale, z1=0.88, r0=0.022, r1=0.021, seg=8)
    helix("Spiral", m, H("#f2f8ff"), 0.2, 0.84, 0.023, 2.5, r=0.005)
    grip_wrap(m, H("#2c4a7a"))
    ferrule("Ferrule", m, H("#e6eef8"))
    crystal("ButtShard", g, H("#b8f0ff"), (0, 0, -0.6), 0.016, 0.02, 0.07, seg=5)
    cup("Cup", m, H("#e6eef8"), 0.84, 0.93, 0.025, 0.045, seg=8)
    ice = H("#a8eeff")
    crystal("Shard0", g, ice, (0, 0, 1.06), 0.034, 0.17, 0.13, seg=6, mid=0.04)
    for k in range(4):
        a = 2 * math.pi * k / 4 + 0.4
        tilt = 0.45 + 0.08 * (k % 2)
        ob = crystal("Shard%d" % (k + 1), g, ice, (0, 0, 0), 0.02, 0.1 + 0.03 * (k % 2), 0.03, seg=5)
        place(ob, (0, 0, 0), (tilt, 0, 0))
        place(ob, (math.sin(a) * 0.03, -math.cos(a) * 0.03, 0.95), (0, 0, a))
        cel(ob, ice, lo=-0.1, hi=0.45)
    finish_staff("st_frost_scepter", 1.06)


def build_archmage():
    m = vcf("st_archmage", metal=0.3)
    g = vcf("st_archmage_gem", emit="#c27cff", strength=1.1)
    gold = H("#e8b44a")
    shaft("Shaft", m, grain("#4a2c5c", "#2a1838", freq=2, amt=0.5), z1=0.88, r0=0.025, r1=0.022, seg=8)
    helix("Filigree", m, gold, 0.25, 0.7, 0.024, 2.0, r=0.0045)
    helix("Filigree2", m, gold, 0.25, 0.7, 0.024, 2.0, r=0.0045, phase=math.pi)
    for z in (-0.4, 0.25, 0.7):
        band("Band%.2f" % z, m, gold, z, 0.026, 0.029)
    ferrule("Ferrule", m, gold)
    grip_wrap(m, H("#3c1e52"))
    cup("Cup", m, gold, 0.84, 0.94, 0.026, 0.05)
    tube("Stem", [(0, 0, 0.92), (0, 0, 1.04)], 0.012, m, gold)
    tube("StemTop", [(0, 0, 1.12), (0, 0, 1.176)], 0.008, m, gold)
    cel(torus("Ring", (0, 1.08), 0.09, 0.011, m, seg=20, sides=6), gold)
    orb("Orb", g, H("#c890ff"), (0, 0, 1.08), 0.055)
    wing = [(0.0, 0.0), (0.03, 0.02), (0.07, 0.07), (0.085, 0.13), (0.07, 0.11), (0.045, 0.075), (0.02, 0.05), (0.0, 0.035)]
    for s in (1, -1):
        ob = flat("Wing%s" % ("R" if s > 0 else "L"), [(x * s, z) for x, z in wing], m, th=0.007, bevel=0.006, step=0.01,
                  loc=(0.085 * s, 0, 1.03))
        cel(ob, gold)
    star = []
    for i in range(8):
        rr = 0.045 if i % 2 == 0 else 0.014
        a = math.pi / 2 + math.pi * i / 4
        star.append((rr * math.cos(a), rr * math.sin(a)))
    flat("Star", star, g, H("#f6e0ff"), th=0.008, bevel=0.006, step=0.008, loc=(0, 0, 1.22))
    finish_staff("st_archmage_staff", 1.08)


# ------------------------------------------------------------------ cajados novos
def build_willow():
    m = vcf("st_willow")
    g = vcf("st_willow_gem", emit="#6ee0b8", strength=0.8)
    wood = grain("#cdb47c", "#9a8050", freq=2, zf=14, amt=0.5)
    shaft("Shaft", m, wood, z1=0.88, r0=0.02, r1=0.017, seg=7, wobble=0.009, seed=11)
    ferrule("Ferrule", m, H("#8a7a5a"), r=0.022)
    grip_wrap(m, H("#4f7240"), r=0.024)
    for s in (1, -1):
        ctrl = [(0, 0, 0.86), (0.05 * s, 0, 0.95), (0.062 * s, 0, 1.05), (0.035 * s, 0, 1.14), (0, 0, 1.17)]
        tube("Arch%d" % s, spline(ctrl, 5), lambda t: 0.014 - 0.006 * t, m, wood, sides=6)
    tube("Thread", [(0, 0, 1.16), (0, 0, 1.06)], 0.0025, m, H("#e8e0c8"), sides=4)
    crystal("Gem", g, H("#7ef0c8"), (0, 0, 1.02), 0.032, 0.045, 0.05, seg=8, mid=0.012)
    leafc = H("#86c45a")
    for k, (sx, sy) in enumerate(((1, -1), (-1, -1), (1, 1), (-1, 1))):
        ctrl = [(0, 0, 1.17), (0.03 * sx, 0.012 * sy, 1.18), (0.07 * sx, 0.02 * sy, 1.12),
                (0.085 * sx, 0.025 * sy, 1.02), (0.09 * sx, 0.028 * sy, 0.9 + 0.03 * k)]
        tube("Strand%d" % k, spline(ctrl, 5), lambda t: 0.009 * (1 - t) + 0.002, m, leafc, sides=4, flat=0.35)
    finish_staff("st_willow_staff", 1.02)


def build_bone():
    m = vcf("st_bone")
    g = vcf("st_bone_gem", emit="#8dff5a", strength=1.2)
    bone = H("#e9dfc4")
    joints = (-0.52, 0.32, 0.86)
    bcol = lambda co: mix(bone, H("#b8a888"), max(0.0, 1 - min(abs(co.z - j) for j in joints) / 0.08) * 0.6)
    shaft("Shaft", m, bcol, z0=-0.56, z1=0.97, r0=0.019, r1=0.019, seg=7,
          knots=((-0.53, 0.012, 0.03), (0.32, 0.01, 0.03), (0.88, 0.01, 0.03)))
    grip_wrap(m, H("#5a4632"), r=0.025)
    wrap("Rag", m, H("#6a5a3c"), z0=0.02, z1=0.1, r=0.024, turns=3)
    tube("RagTail", spline([(0.022, -0.005, 0.42), (0.04, -0.02, 0.38), (0.045, -0.025, 0.3)], 3),
         lambda t: 0.008 * (1 - t) + 0.002, m, H("#6a5a3c"), sides=4, flat=0.3)
    # crânio: calota, maçãs e mandíbula; órbitas e nariz pintados de escuro
    eyes = [Vector((0.022, -0.063, 1.01)), Vector((-0.022, -0.063, 1.01))]
    nose = Vector((0.0, -0.066, 0.988))

    def skull(co):
        if any((co - e).length < 0.018 for e in eyes) or (co - nose).length < 0.009:
            return H("#2a2420")
        return bone
    lathe("Skull", [(0.95, 0.0), (0.955, 0.035), (0.975, 0.05), (1.01, 0.058), (1.05, 0.056), (1.08, 0.045),
                    (1.1, 0.026), (1.108, 0.0)], m, skull, seg=10, loc=(0, -0.004, 0), scale=(0.95, 1.1, 1))
    lathe("Jaw", [(0.925, 0.0), (0.928, 0.026), (0.95, 0.034), (0.965, 0.03), (0.965, 0.0)], m, bone, seg=8,
          loc=(0, -0.018, 0), scale=(1.0, 1.15, 1))
    for i, e in enumerate(eyes):
        orb("Eye%d" % i, g, H("#9dff6a"), (e.x, e.y + 0.003, e.z), 0.009, seg=6)
    for s in (1, -1):
        ctrl = [(0.04 * s, 0, 1.05), (0.07 * s, 0, 1.1), (0.06 * s, 0, 1.16), (0.022 * s, 0, 1.18)]
        tube("Horn%d" % s, spline(ctrl, 5), lambda t: 0.013 * (1 - t) + 0.003, m, bone, sides=6)
    lathe("Seat", [(1.09, 0.0), (1.09, 0.014), (1.15, 0.009), (1.15, 0.0)], m, bone, seg=6)
    crystal("Gem", g, H("#9dff6a"), (0, 0, 1.18), 0.028, 0.05, 0.04, seg=5, mid=0.01)
    finish_staff("st_bone_staff", 1.18)


def build_tide():
    m = vcf("st_tide")
    g = vcf("st_tide_gem", emit="#66d9ff", strength=0.9)
    sea = lambda co: mix(H("#3f8f98"), H("#2a6070"), 0.5 + 0.5 * math.sin(co.z * 18 + math.sin(co.z * 5) * 2))
    shaft("Shaft", m, sea, z1=0.88, r0=0.023, r1=0.02, seg=7, wobble=0.01, seed=21)
    grip_wrap(m, H("#d8c49a"), turns=9)
    ferrule("Ferrule", m, H("#e8dcc8"))
    coral = H("#ff8a7a")
    tube("ProngC", spline([(0, 0, 0.86), (0, 0, 1.0), (0.006, 0, 1.12), (0, 0, 1.24)], 4),
         lambda t: 0.015 - 0.011 * t, m, coral)
    for s in (1, -1):
        tube("Prong%d" % s, spline([(0, 0, 0.86), (0.04 * s, 0, 0.92), (0.075 * s, 0, 1.0), (0.07 * s, 0, 1.1),
                                    (0.055 * s, 0, 1.16)], 4), lambda t: 0.014 - 0.01 * t, m, coral)
        tube("Twig%d" % s, spline([(0.072 * s, 0, 1.02), (0.1 * s, 0, 1.06), (0.105 * s, 0, 1.1)], 3),
             lambda t: 0.008 - 0.005 * t, m, coral)
    orb("Pearl", g, H("#e4fbff"), (0, 0, 1.03), 0.04)
    fan = [(0.0, 0.0)] + [(0.05 * math.cos(a) * (1 + 0.12 * (i % 2)), 0.05 * math.sin(a) * (1 + 0.12 * (i % 2)))
                          for i, a in enumerate([math.pi * (0.1 + 0.8 * k / 8) for k in range(9)])]
    for s in (1, -1):
        ob = flat("Shell%d" % s, fan, m, th=0.006, bevel=0.005, step=0.009, loc=(0.025 * s, -0.01, 0.86),
                  rot=(0, -0.6 * s, 0))
        cel(ob, lambda co: mix(H("#f6dcc6"), H("#e89a86"), smooth01((co.z - 0.86) / 0.05)))
    finish_staff("st_tide_staff", 1.03)


def build_sun():
    m = vcf("st_sun", metal=0.3)
    g = vcf("st_sun_gem", emit="#ffcf4a", strength=1.2)
    gold = H("#f0b83a")
    shaft("Shaft", m, lambda co: mix(H("#f4ecda"), H("#ddd0b4"), 0.5 + 0.5 * math.sin(co.z * 10)), z1=0.88,
          r0=0.023, r1=0.021, seg=8)
    for z in (0.15, 0.6):
        band("Band%.2f" % z, m, gold, z, 0.03, 0.027)
    ferrule("Ferrule", m, gold)
    grip_wrap(m, H("#b23a2a"))
    cup("Cup", m, gold, 0.84, 0.95, 0.025, 0.04)
    rays = []
    for i in range(24):
        a = math.pi / 2 + math.pi * i / 12
        rr = (0.155 if i % 4 == 0 else 0.135) if i % 2 == 0 else 0.095
        rays.append((rr * math.cos(a), 1.09 + rr * math.sin(a)))
    hole = [(0.07 * math.cos(2 * math.pi * k / 16), 1.09 + 0.07 * math.sin(2 * math.pi * k / 16)) for k in range(16)]
    flat("Rays", rays, m, lambda co: mix(H("#ffd75a"), H("#e89a2a"), smooth01((Vector((co.x, 0, co.z - 1.09)).length - 0.08) / 0.07)),
         th=0.01, bevel=0.008, step=0.012, holes=[hole])
    cel(torus("Rim", (0, 1.09), 0.072, 0.011, m, seg=20, sides=6), gold)
    tube("Stem", [(0, 0, 0.94), (0, 0, 1.05)], 0.012, m, gold)
    orb("Gem", g, H("#ffc24a"), (0, 0, 1.09), 0.062)
    finish_staff("st_sun_staff", 1.09)


def build_storm():
    m = vcf("st_storm", metal=0.4)
    g = vcf("st_storm_gem", emit="#8ab0ff", strength=1.3)
    steel = H("#8e9ab8")
    shaft("Shaft", m, H("#3e4660"), z1=0.88, r0=0.024, r1=0.022, seg=6, smooth=False)
    for z in (-0.3, 0.2, 0.45, 0.7):
        band("Band%.2f" % z, m, steel, z, 0.02, 0.027, seg=6)
    ferrule("Ferrule", m, steel)
    grip_wrap(m, H("#1e2436"))
    cup("Cup", m, steel, 0.83, 0.92, 0.025, 0.042, seg=6)
    bolt = [(0.0, 0.0), (0.02, 0.0), (0.035, 0.12), (0.02, 0.12), (0.05, 0.25), (0.032, 0.25), (0.062, 0.37),
            (0.012, 0.21), (0.028, 0.21), (0.004, 0.1), (0.016, 0.1)]
    for s, a in (("R", 0.0), ("L", math.pi)):
        ob = flat("Bolt" + s, bolt, g, th=0.007, bevel=0.005, step=0.008, loc=(0.03, 0, 0.86))
        place(ob, (0, 0, 0), (0, 0, a))
        cel(ob, lambda co: mix(H("#cfeeff"), H("#7aa8ff"), smooth01((co.z - 0.95) / 0.2)))
    crystal("Gem", g, H("#8ab0ff"), (0, 0, 1.05), 0.03, 0.17, 0.14, seg=6, mid=0.03)
    tr = torus("Halo", (0, 0), 0.062, 0.006, m, seg=20, sides=5)
    place(tr, (0, 0, 1.06), (math.pi / 2 + 0.25, 0, 0))
    cel(tr, steel)
    finish_staff("st_storm_staff", 1.05)


def build_thorn():
    m = vcf("st_thorn")
    g = vcf("st_thorn_gem", emit="#ff4a6a", strength=1.1)
    vine = lambda co: mix(H("#3e3a26"), H("#2a2a1c"), 0.5 + 0.5 * math.sin(co.z * 30))
    lathe("Core", [(-0.56, 0.0), (-0.56, 0.012), (0.88, 0.012), (0.88, 0.0)], m, vine, seg=6)
    for k in range(2):
        helix("Vine%d" % k, m, vine, -0.55, 0.88, 0.013, 4.5, r=0.012, phase=math.pi * k, sides=6)
    grip_wrap(m, H("#5a1e24"), r=0.03)
    rnd = random.Random(5)
    for i in range(16):
        z = -0.45 + i * 0.085
        if -0.16 < z < 0.16:
            continue
        a = rnd.uniform(0, 2 * math.pi)
        ob = crystal("Thorn%d" % i, m, H("#d9c7a0"), (0, 0, 0), 0.006, 0.042, 0.0, seg=4)
        place(ob, (0, 0, 0), (0, 1.25, 0))
        place(ob, (0.008 * math.cos(a), 0.008 * math.sin(a), z), (0, 0, a))
        cel(ob, H("#d9c7a0"))
    lathe("Bud", [(0.84, 0.0), (0.84, 0.014), (0.9, 0.022), (0.94, 0.033), (0.97, 0.031), (1.0, 0.018), (1.0, 0.0)],
          m, H("#3f6a2e"), seg=8)
    for k in range(3):
        lf = flat("Sepal%d" % k, leaf_outline(0.07, 0.02), m, th=0.004, bevel=0.004, step=0.009,
                  bend=lambda c: Vector((c.x, c.y - 0.5 * c.z * c.z, c.z)))
        a = 2 * math.pi * k / 3
        place(lf, (0, 0, 0), (1.9, 0, 0))
        place(lf, (math.sin(a) * 0.015, -math.cos(a) * 0.015, 0.93), (0, 0, a))
        cel(lf, H("#3f6a2e"))
    petal = [(-0.008, 0.0), (0.008, 0.0), (0.028, 0.03), (0.034, 0.06), (0.024, 0.085), (0.0, 0.092),
             (-0.024, 0.085), (-0.034, 0.06), (-0.028, 0.03)]
    pc = lambda co: mix(H("#8c1a34"), H("#f0607a"), smooth01((co.z - 0.95) / 0.16))
    for tier, (n, tilt, sc, r0, z0, a0) in enumerate(((5, 0.35, 1.1, 0.014, 0.96, 0.0), (5, 0.85, 1.4, 0.024, 0.95, 0.63),
                                                         (6, 1.25, 1.55, 0.03, 0.94, 0.3))):
        obs = ring_place(lambda i: flat("Petal%d_%d" % (tier, i), [(x * sc, z * sc) for x, z in petal], m, th=0.004,
                                        bevel=0.004, step=0.008,
                                        bend=lambda c: Vector((c.x, c.y + 4.0 * c.x * c.x - 0.8 * c.z * c.z, c.z))),
                         n, r0, z0, tilt, a0)
        for ob in obs:
            cel(ob, pc)
    crystal("Gem", g, H("#ff5a78"), (0, 0, 1.03), 0.032, 0.065, 0.035, seg=6, mid=0.01)
    finish_staff("st_thorn_staff", 1.03)


def _crescent(c1, R1, c2, R2, n=30):
    """Contorno da lua com as pontas para cima: disco (c1, R1) menos o disco (c2, R2), c2 acima de c1."""
    dy = c2[1] - c1[1]
    yi = (R1 * R1 - R2 * R2 + dy * dy) / (2 * dy)            # altura da interseção acima de c1
    xi = math.sqrt(max(R1 * R1 - yi * yi, 1e-9))
    a1 = math.atan2(yi, xi)                                  # ponta direita no círculo externo
    a2 = math.atan2(yi - dy, xi)                             # e no interno
    outer = [(c1[0] + R1 * math.cos(a), c1[1] + R1 * math.sin(a))
             for a in (a1 - (math.pi + 2 * a1) * k / n for k in range(n + 1))]          # desce pela direita
    inner = [(c2[0] + R2 * math.cos(a), c2[1] + R2 * math.sin(a))
             for a in (math.pi - a2 + (math.pi + 2 * a2) * k / n for k in range(1, n))]  # volta por dentro
    return outer + inner


def build_void():
    m = vcf("st_void", metal=0.2)
    g = vcf("st_void_gem", emit="#b066ff", strength=1.3)
    silver = H("#cfd2e8")

    def obsidian(co):
        a = math.atan2(co.y, co.x)
        v = abs(math.sin(co.z * 16 + a * 1.5 + math.sin(co.z * 7) * 1.5))
        return mix(H("#2a2238"), H("#9a5aff"), smooth01((v - 0.9) / 0.08))
    shaft("Shaft", m, obsidian, z1=0.9, r0=0.025, r1=0.021, seg=5, smooth=False, phase=0.3)
    for z in (0.18, 0.66):
        band("Band%.2f" % z, m, silver, z, 0.022, 0.028, seg=5)
    ferrule("Ferrule", m, silver)
    crystal("Spike", m, H("#3a2e50"), (0, 0, -0.6), 0.02, 0.0, 0.08, seg=5)
    grip_wrap(m, H("#2c1e40"))
    moon = _crescent((0.0, 1.07), 0.125, (0.0, 1.12), 0.1)
    flat("Crescent", moon, m, lambda co: mix(H("#3a2e52"), H("#7a5ab0"), smooth01((co.z - 0.95) / 0.25)),
         th=0.012, bevel=0.01, step=0.012)
    tube("Neck", [(0, 0, 0.88), (0, 0, 0.955)], 0.016, m, silver)
    crystal("Gem", g, H("#b47aff"), (0, 0, 1.1), 0.042, 0.075, 0.087, seg=4, phase=math.pi / 4)
    tr = torus("Orbit", (0, 0), 0.04, 0.006, m, seg=16, sides=5)
    place(tr, (0, 0, 1.1), (math.pi / 2 - 0.2, 0, 0))
    cel(tr, silver)
    for i, s in enumerate((1, -1)):
        crystal("Mote%d" % i, g, H("#d0a8ff"), (0.1 * s, 0, 1.165), 0.012, 0.03, 0.036, seg=4)
    finish_staff("st_void_staff", 1.1)


def build_phoenix():
    m = vcf("st_phoenix", metal=0.2)
    g = vcf("st_phoenix_gem", emit="#ff8a2a", strength=1.4)
    gold = H("#f2b440")
    shaft("Shaft", m, lambda co: mix(H("#f6ecd6"), H("#e2d2b2"), 0.5 + 0.5 * math.sin(co.z * 12)), z1=0.9,
          r0=0.024, r1=0.021, seg=8)
    helix("Gild", m, gold, 0.2, 0.82, 0.023, 2.2, r=0.0045)
    for z in (-0.42, 0.2, 0.82):
        band("Band%.2f" % z, m, gold, z, 0.026, 0.028)
    ferrule("Ferrule", m, gold)
    grip_wrap(m, H("#a8281c"))
    cup("Cup", m, gold, 0.86, 0.97, 0.025, 0.045)
    feather = [(-0.012, 0.0), (0.012, 0.0), (0.026, 0.05), (0.03, 0.11), (0.022, 0.17), (0.01, 0.21), (0.022, 0.23),
               (-0.004, 0.24), (-0.014, 0.18), (-0.022, 0.1), (-0.02, 0.04)]

    def fire(x, z, d):
        L = 0.24
        base = ramp([(0.0, H("#ffe27a")), (0.4, H("#ffa63a")), (0.75, H("#ff6a2a")), (1.0, H("#d8302a"))], z / L)
        return mix(mix(base, H("#8a1c18"), 0.45), base, smooth01(d / 0.006))
    for side in (1, -1):
        for k in range(4):
            sc = 0.75 + 0.1 * k
            ob = flat("Feather%d_%d" % (side, k), [(x * sc * side, z * sc) for x, z in feather], m, th=0.005, bevel=0.005,
                      step=0.008, paint2d=lambda x, z, d, sc=sc: fire(x, z / sc, d),
                      bend=lambda c: Vector((c.x, c.y + 0.4 * c.z * c.z, c.z)))
            place(ob, (0, 0, 0), (0, side * (0.45 + 0.32 * k), 0))
            place(ob, (0.03 * side, 0.004 * k, 0.96))
    for k, a in enumerate((-0.18, 0.0, 0.18)):
        ob = flat("Crest%d" % k, [(x * 0.6, z * 0.6) for x, z in feather], m, th=0.005, bevel=0.005, step=0.008,
                  paint2d=lambda x, z, d: fire(x, z / 0.6, d))
        place(ob, (0, 0, 0), (0, a, 0))
        place(ob, (0, 0.004 * (k - 1), 1.06))
    crystal("Gem", g, H("#ff9a3a"), (0, 0, 1.02), 0.034, 0.1, 0.07, seg=6, mid=0.012)
    finish_staff("st_phoenix_staff", 1.02)


ARMORY += [("st_apprentice_staff", build_apprentice), ("st_oak_staff", build_oak), ("st_ember_staff", build_ember),
           ("st_frost_scepter", build_frost), ("st_archmage_staff", build_archmage),
           ("st_willow_staff", build_willow), ("st_bone_staff", build_bone), ("st_tide_staff", build_tide),
           ("st_sun_staff", build_sun), ("st_storm_staff", build_storm), ("st_thorn_staff", build_thorn),
           ("st_void_staff", build_void), ("st_phoenix_staff", build_phoenix)]


# ------------------------------------------------------------------ arcos
def bow_curve(half, back, recurve=0.0, n=24, sway=0.0):
    pts = []
    for i in range(n + 1):
        t = -1 + 2 * i / n
        y = back * t * t - 0.02 - recurve * smooth01((abs(t) - 0.62) / 0.38) ** 1.5
        pts.append((sway * math.sin(t * 3.3 + 0.4), y, t * half))
    return pts


def limb_at(pts, z):
    """Ponto do braço na altura z."""
    for a, b in zip(pts, pts[1:]):
        if a[2] <= z <= b[2]:
            u = (z - a[2]) / max(b[2] - a[2], 1e-6)
            return Vector(a).lerp(Vector(b), u)
    return Vector(pts[-1] if z > 0 else pts[0])


def bow_base(m, wood, half, back, recurve=0.0, r_mid=0.019, r_tip=0.008, grip="#5a3a20", string="#efe6cc", sway=0.0,
             flatk=0.62):
    pts = bow_curve(half, back, recurve, sway=sway)
    tube("Limbs", pts, lambda t: r_tip + (r_mid - r_tip) * (1 - abs(2 * t - 1)) ** 0.6, m, wood, sides=6, flat=flatk)
    gp = limb_at(pts, 0.0)
    ob = wrap("Grip", m, None, -0.075, 0.075, r_mid * 1.3, turns=5, seg=6)
    place(ob, (gp.x, gp.y, 0))
    cel(ob, H(grip))
    top, bot = pts[-1], pts[0]
    # a corda não entra no GLB: o jogo a desenha das pontas ("StringTop"/"StringBot") até os dedos ao puxar
    _BOW_STRING[:] = [(top[0], top[1], top[2] - 0.01), (bot[0], bot[1], bot[2] + 0.01)]
    return pts, top[1]


def put(ob, col, loc=(0, 0, 0), rot=(0, 0, 0)):
    place(ob, (0, 0, 0), rot)
    place(ob, loc)
    return cel(ob, col)


_BOW_STRING = []   # pontas da corda do arco em montagem (bow_base)


def bow_export(asset, nock_y):
    loose_parts(asset)
    join_all("Weapon")
    empty("Tip", (0, -0.3, 0))
    empty("Nock", (0, nock_y, 0))
    empty("StringTop", _BOW_STRING[0])
    empty("StringBot", _BOW_STRING[1])
    export(asset)


def end_cap(name, m, col, pts, z, prof):
    """Peça na ponta do braço, alinhada à direção dele."""
    s = 1 if z > 0 else -1
    p, q = limb_at(pts, z), limb_at(pts, z - 0.05 * s)
    d = (p - q).normalized()
    ob = w_lathe(name, prof, m, seg=6)
    rot = d.to_track_quat('Z', 'Y').to_euler()
    return put(ob, col, p, rot)


def build_short_bow():
    m = vcf("bw_short")
    wood = grain("#b07a42", "#8a5a2e", freq=1, zf=20, amt=0.5)
    pts, ny = bow_base(m, wood, 0.55, 0.13)
    for z in (-0.53, 0.53):
        end_cap("Cap%d" % (z > 0), m, H("#5a3a20"), pts, z, [(-0.02, 0.0), (-0.02, 0.009), (0.015, 0.0075), (0.025, 0.0)])
    bow_export("bw_short_bow", ny)


def build_hunter_bow():
    m = vcf("bw_hunter")
    wood = grain("#6e4626", "#4a2c16", freq=1, zf=20, amt=0.55)
    pts, ny = bow_base(m, wood, 0.58, 0.14, recurve=0.03, grip="#3e5a2c")
    for z in (-0.55, 0.55):
        end_cap("Tip%d" % (z > 0), m, H("#ece0c4"), pts, z, [(-0.03, 0.0), (-0.03, 0.0095), (0.0, 0.008), (0.035, 0.0)])
    for z in (-0.3, 0.3):
        put(band("Wrap%d" % (z > 0), m, None, 0, 0.03, 0.017, seg=6), H("#3e5a2c"), limb_at(pts, z))
    g = limb_at(pts, -0.06)
    tube("Cord", spline([(0.022, g.y, -0.05), (0.03, g.y - 0.01, -0.12), (0.028, g.y - 0.012, -0.17)], 3), 0.0025, m,
         H("#d8c8a0"), sides=4)
    feather = [(-0.004, 0.0), (0.004, 0.0), (0.014, 0.03), (0.012, 0.07), (0.0, 0.085), (-0.012, 0.07), (-0.014, 0.03)]
    for k, (c, rz) in enumerate((("#c8402a", 0.25), ("#f2ece0", -0.2))):
        ob = flat("Feather%d" % k, feather, m, th=0.003, bevel=0.003, step=0.007)
        put(ob, H(c), (0.028, g.y - 0.012, -0.165), (math.pi + rz, 0, math.pi / 2))
    bow_export("bw_hunter_bow", ny)


def build_elven_bow():
    m = vcf("bw_elven", metal=0.2)
    pts, ny = bow_base(m, lambda co: mix(H("#f0e8cc"), H("#d8ccaa"), 0.5 + 0.5 * math.sin(co.z * 16)), 0.62, 0.14,
                       recurve=0.035, r_mid=0.018, grip="#3a6a3a")
    gold, leafc = H("#e0b44a"), H("#8fcf6a")
    for z in (-0.13, 0.13, -0.45, 0.45):
        put(band("Band%.2f" % z, m, None, 0, 0.018, 0.016, seg=6), gold, limb_at(pts, z))
    for s in (1, -1):
        top, prev = limb_at(pts, 0.62 * s), limb_at(pts, 0.57 * s)
        d = (top - prev).normalized()
        lf = flat("TipLeaf%d" % s, leaf_outline(0.11, 0.022), m, th=0.004, bevel=0.004, step=0.009,
                  bend=lambda c: Vector((c.x, c.y + 0.8 * c.x * c.x, c.z)))
        put(lf, leafc, top - d * 0.035, d.to_track_quat('Z', 'Y').to_euler())
        for k, side in enumerate((1, -1)):
            gl = flat("GripLeaf%d%d" % (s, k), leaf_outline(0.08, 0.018), m, th=0.004, bevel=0.004, step=0.009)
            rot = (0, side * 0.45, 0) if s > 0 else (0, math.pi - side * 0.45, 0)
            put(gl, leafc, limb_at(pts, 0.08 * s) + Vector((0.012 * side, -0.004, 0)), rot)
    bow_export("bw_elven_bow", ny)


def build_goblin_warbow():
    m = vcf("bw_goblin")
    wood = grain("#6e5a30", "#46381c", freq=1, zf=26, amt=0.6)
    pts, ny = bow_base(m, wood, 0.6, 0.15, r_mid=0.023, r_tip=0.011, grip="#8a2a20", string="#c8b890", sway=0.018,
                       flatk=0.8)
    bone = H("#e2d6b4")
    for z in (-0.5, -0.27, 0.27, 0.5):
        put(band("Bone%.2f" % z, m, None, 0, 0.026, 0.02, seg=5), bone, limb_at(pts, z), (0.15 * z, 0, 0.3))
    for k, z in enumerate((-0.42, -0.16, 0.16, 0.42)):
        ob = crystal("Spike%d" % k, m, None, (0, 0, 0), 0.008, 0.05, 0.0, seg=4)
        put(ob, H("#6a6a72"), limb_at(pts, z) + Vector((0, -0.012, 0)), (math.pi / 2 + 0.25 * (1 if z > 0 else -1), 0, 0))
    for z in (-0.57, 0.57):
        end_cap("Fang%d" % (z > 0), m, bone, pts, z, [(-0.01, 0.0), (-0.01, 0.013), (0.06, 0.0)])
    bow_export("bw_goblin_warbow", ny)


def build_storm_bow():
    m = vcf("bw_storm", metal=0.4)
    g = vcf("bw_storm_gem", emit="#9ad8ff", strength=1.4)
    pts, ny = bow_base(m, H("#353d5a"), 0.62, 0.14, recurve=0.035, r_mid=0.02, grip="#1e2436", string="#d8f0ff")
    for s in (1, -1):
        seg = [(x, y - 0.012, z) for x, y, z in spline(pts, 2) if 0.12 < z * s < 0.55]
        tube("Glow%d" % s, seg, 0.0045, g, H("#bfeaff"), sides=4)
        fin = [(0.0, 0.0), (0.05, 0.03), (0.07, 0.1), (0.04, 0.08), (0.03, 0.16), (0.012, 0.11), (0.0, 0.14)]
        ob = flat("Fin%d" % s, fin, m, th=0.005, bevel=0.005, step=0.008)
        place(ob, (0, 0, 0), (0, 0, math.pi / 2))                       # plano YZ, aberta para trás (+Y)
        if s < 0:
            place(ob, (0, 0, 0), (math.pi, 0, 0))
        put(ob, lambda co: mix(H("#cfd8f0"), H("#6a7aa0"), smooth01((co.y - 0.02) / 0.07)),
            limb_at(pts, 0.18 * s) + Vector((0, 0.01, 0)))
    crystal("Gem", g, H("#9ad8ff"), (0, -0.045, 0), 0.016, 0.03, 0.03, seg=4, rot=(math.pi / 2, 0, 0))
    for z in (-0.58, 0.58):
        end_cap("Cap%d" % (z > 0), m, H("#cfd8f0"), pts, z, [(-0.025, 0.0), (-0.025, 0.01), (0.015, 0.0065), (0.03, 0.0)])
    bow_export("bw_storm_bow", ny)


def build_arrow():
    m = vcf("bw_arrow", metal=0.3)
    tube("Shaft", [(0, 0, -0.07), (0, 0, 0.69)], 0.0055, m, H("#b08850"), sides=6)
    crystal("Head", m, H("#c4ccd8"), (0, 0, 0.7), 0.017, 0.055, 0.012, seg=4)
    lathe("Nock", [(-0.085, 0.0), (-0.085, 0.006), (-0.07, 0.0065), (-0.07, 0.0)], m, H("#d8402a"), seg=6)
    vane = [(0.0, 0.0), (0.02, 0.012), (0.024, 0.075), (0.0, 0.1)]
    for k in range(3):
        ob = flat("Vane%d" % k, vane, m, th=0.002, bevel=0.002, step=0.006, loc=(0.004, 0, -0.065))
        put(ob, H("#d8402a" if k == 0 else "#f2ece0"), (0, 0, 0), (0, 0, 2 * math.pi * k / 3 + math.pi / 2))
    for o in [o for o in coll.all_objects if o.type == 'MESH']:
        place(o, (0, 0, 0), (math.pi / 2, 0, 0))       # +Z -> -Y: a flecha sai da corda para a frente
    fin("bw_arrow", 0.0, 0.0)


ARMORY += [("bw_short_bow", build_short_bow), ("bw_hunter_bow", build_hunter_bow), ("bw_elven_bow", build_elven_bow),
           ("bw_goblin_warbow", build_goblin_warbow), ("bw_storm_bow", build_storm_bow), ("bw_arrow", build_arrow)]


# ------------------------------------------------------------------ espadas clássicas
def metal(light, base, edge, cx=lambda z: 0.0, fuller=None, contour=0.009, extra=None):
    """Pintura anime do metal: luz à esquerda da quina central, base à direita, contorno escuro no gume.
    fuller = (z0, z1, meia_largura, cor) — sulco central; extra(x, z, cor) -> cor ajusta por cima."""
    L, B, E = H(light), H(base), H(edge)

    def fn(x, z, d):
        side = x - cx(z)
        c = mix(L, B, smooth01((side + 0.003) / 0.006))
        if fuller and fuller[0] < z < fuller[1] and abs(side) < fuller[2]:
            c = mix(c, H(fuller[3]), 0.85)
        if extra:
            c = extra(x, z, c)
        return mix(E, c, smooth01((d - 0.001) / contour))
    return fn


def sword_blade(name, outline, m, paint2d, th=0.012, bevel=0.011, holes=()):
    return flat(name, outline, m, th=th, bevel=bevel, step=0.01, paint2d=paint2d, holes=holes)


def curved(z0, z1, cx, w, spine=0.4, n=14, tip_back=0.006):
    """Contorno de lâmina curva: costas em cx - w*spine, gume em cx + w*(1-spine), ponta puxada para as costas."""
    zs = [z0 + (z1 - z0) * i / n for i in range(n)]
    back = [(cx(z) - w(z) * spine, z) for z in zs]
    edge = [(cx(z) + w(z) * (1 - spine), z) for z in zs]
    tip = (cx(z1) - tip_back, z1)
    return back + [tip] + list(reversed(edge)), tip


def build_wooden_sword():
    m = vcf("w_wooden")
    wood = H("#c09058")

    def wpaint(x, z, d):
        gr = 0.5 + 0.5 * math.sin(x * 160 + math.sin(z * 14) * 2.0)
        c = mix(wood, H("#9a6c3c"), 0.5 * smooth01((gr - 0.6) / 0.4))
        c = mix(H("#e0b880"), c, smooth01((x + 0.004) / 0.008))
        return mix(H("#6a4626"), c, smooth01((d - 0.001) / 0.008))
    sword_blade("Blade", [(-0.03, 0.07), (0.03, 0.07), (0.03, 0.74), (0.022, 0.8), (0.0, 0.83), (-0.022, 0.8),
                          (-0.03, 0.74)], m, wpaint, th=0.013, bevel=0.012)
    tube("Guard", [(-0.1, 0, 0.068), (0.1, 0, 0.068)], 0.016, m, H("#8a5a30"), sides=6, flat=0.8)
    for s in (1, -1):
        orb("GuardEnd%d" % s, m, H("#8a5a30"), (0.1 * s, 0, 0.068), 0.019, seg=6)
    wrap("Grip", m, H("#e0d2b0"), -0.07, 0.055, 0.017, turns=5)
    orb("Pommel", m, H("#8a5a30"), (0, 0, -0.088), 0.024, seg=8)
    fin("w_wooden_sword", 0.0, 0.83)


def build_iron_sword():
    m = vcf("w_iron", metal=0.4)
    sword_blade("Blade", [(-0.026, 0.07), (0.026, 0.07), (0.022, 0.72), (0.0, 0.95), (-0.022, 0.72)], m,
                metal("#eef2f6", "#a8b4c4", "#46505e", fuller=(0.1, 0.62, 0.005, "#7a8696")))
    iron = H("#6e7684")
    tube("Guard", spline([(-0.11, 0, 0.1), (-0.085, 0, 0.072), (0, 0, 0.064), (0.085, 0, 0.072), (0.11, 0, 0.1)], 4),
         lambda t: 0.012 - 0.004 * abs(2 * t - 1), m, iron, sides=6)
    crystal("Block", m, iron, (0, 0, 0.064), 0.024, 0.02, 0.02, seg=4, phase=math.pi / 4)
    wrap("Grip", m, H("#5a3a22"), -0.07, 0.055, 0.016, turns=6)
    lathe("Pommel", [(-0.105, 0.0), (-0.105, 0.012), (-0.095, 0.024), (-0.08, 0.02), (-0.07, 0.01), (-0.07, 0.0)], m, iron,
          seg=8, smooth=False)
    fin("w_iron_sword", 0.0, 0.95)


def build_steel_saber():
    m = vcf("w_saber", metal=0.4)
    cx = lambda z: -0.12 * ((z - 0.07) / 0.82) ** 2
    w = lambda z: 0.04 - 0.01 * (z - 0.07) / 0.82
    ol, tip = curved(0.07, 0.89, cx, w)
    sword_blade("Blade", ol, m, metal("#f4f8fc", "#b8c6d6", "#4a5668", cx=lambda z: cx(z) - w(z) * 0.1), th=0.011,
                bevel=0.01)
    gold = H("#e0b050")
    lathe("Guard", [(0.055, 0.0), (0.055, 0.028), (0.065, 0.034), (0.075, 0.03), (0.075, 0.0)], m, gold, seg=10,
          scale=(1.3, 0.65, 1), smooth=False)
    tube("Knuckle", spline([(0.035, 0, 0.065), (0.06, 0, 0.03), (0.058, 0, -0.04), (0.035, 0, -0.085),
                            (0.008, 0, -0.095)], 4), 0.0065, m, gold, sides=5)
    wrap("Grip", m, H("#2a2230"), -0.08, 0.055, 0.015, turns=7)
    orb("Pommel", m, gold, (0, 0, -0.092), 0.016, seg=8, sq=0.8)
    fin("w_steel_saber", *tip)


def build_knight_blade():
    m = vcf("w_knight", metal=0.4)
    g = vcf("w_knight_gem", emit="#6ab8ff", strength=1.6)
    sword_blade("Blade", [(-0.035, 0.08), (0.035, 0.08), (0.03, 0.78), (0.0, 0.98), (-0.03, 0.78)], m,
                metal("#eef4fb", "#aebed4", "#3e4c66", fuller=(0.11, 0.72, 0.009, "#8aa0bc")), th=0.013, bevel=0.012)
    for k in range(8):
        z = 0.16 + k * 0.068
        flat("Rune%d" % k, [(0.0, z - 0.016), (0.0055, z), (0.0, z + 0.016), (-0.0055, z)], g, H("#8acaff"), th=0.0142,
             bevel=0.0015, step=0.004, ridge=0.0)
    gold = H("#e8b84a")
    wing = [(0.02, 0.058), (0.07, 0.062), (0.12, 0.1), (0.108, 0.074), (0.135, 0.068), (0.095, 0.046), (0.02, 0.04)]
    for s in (1, -1):
        flat("Wing%d" % s, [(x * s, z) for x, z in wing], m, gold, th=0.01, bevel=0.007, step=0.008)
    crystal("Block", m, gold, (0, 0, 0.06), 0.028, 0.026, 0.022, seg=4, phase=math.pi / 4)
    orb("Gem", g, H("#5aa8ff"), (0, -0.016, 0.06), 0.013, seg=8)
    wrap("Grip", m, H("#2a3e70"), -0.08, 0.04, 0.017, turns=6)
    lathe("Pommel", [(-0.12, 0.0), (-0.115, 0.016), (-0.1, 0.024), (-0.085, 0.016), (-0.08, 0.0)], m, gold, seg=8,
          smooth=False)
    orb("PommelGem", g, H("#5aa8ff"), (0, -0.018, -0.1), 0.009, seg=6)
    fin("w_knight_blade", 0.0, 0.98)


def build_frost_brand():
    m = vcf("w_frost", metal=0.2)
    g = vcf("w_frost_gem", emit="#8fe6ff", strength=1.2)
    right = []
    right = [(0.03, 0.058)]
    z = 0.08
    while z < 0.8:
        right += [(0.034, z), (0.025, z + 0.035)]
        z += 0.07
    ol = right + [(0.0, 0.97)] + [(-x, zz) for x, zz in reversed(right)]
    sword_blade("Blade", ol, m, metal("#f4feff", "#a6e4f6", "#3a86b0", fuller=(0.1, 0.8, 0.004, "#5ab8e0")),
                th=0.012, bevel=0.011)
    flat("Core", [(0.0, 0.1), (0.006, 0.45), (0.0, 0.88), (-0.006, 0.45)], g, H("#c8f6ff"), th=0.0132, bevel=0.002,
         step=0.005, ridge=0.0)
    silver = H("#dce8f4")
    tube("Guard", [(-0.06, 0, 0.065), (0.06, 0, 0.065)], 0.013, m, silver, sides=6)
    for s in (1, -1):
        ob = crystal("Ice%d" % s, g, None, (0, 0, 0), 0.016, 0.07, 0.01, seg=5)
        put(ob, H("#a8eeff"), (0.06 * s, 0, 0.065), (0, s * 1.1, 0))
    wrap("Grip", m, H("#24406a"), -0.075, 0.058, 0.016, turns=6)
    crystal("Pommel", g, H("#a8eeff"), (0, 0, -0.085), 0.018, 0.012, 0.045, seg=5)
    fin("w_frost_brand", 0.0, 0.97)


def build_goblin_cleaver():
    m = vcf("w_cleaver", metal=0.3)
    ol = [(-0.03, 0.07), (0.06, 0.075), (0.11, 0.11), (0.125, 0.2), (0.116, 0.26), (0.128, 0.3), (0.125, 0.4),
          (0.113, 0.44), (0.127, 0.48), (0.13, 0.6), (0.12, 0.68), (0.06, 0.7), (-0.03, 0.66)]
    hole = [(0.014 * math.cos(2 * math.pi * k / 10), 0.6 + 0.014 * math.sin(2 * math.pi * k / 10)) for k in range(10)]

    def hot(x, z, c):
        rust = 0.5 + 0.5 * math.sin(x * 70 + z * 40) * math.sin(z * 23 - x * 31)
        c = mix(c, H("#8a4a2a"), 0.45 * smooth01((rust - 0.7) / 0.3))
        return mix(c, H("#ff8a3a"), smooth01((x - 0.07) / 0.05))
    sword_blade("Blade", ol, m, metal("#b0a098", "#7e6a62", "#2e221e", cx=lambda z: 0.02, extra=hot), th=0.015,
                bevel=0.013, holes=[hole])
    iron = H("#4e4a4e")
    lathe("Guard", [(0.05, 0.0), (0.05, 0.03), (0.075, 0.03), (0.075, 0.0)], m, iron, seg=4, smooth=False,
          scale=(1.9, 0.75, 1), phase=math.pi / 4)
    wrap("Grip", m, H("#5a4a3a"), -0.08, 0.05, 0.018, turns=4)
    for z in (-0.05, 0.02):
        band("Bone%.2f" % z, m, H("#ddd0b0"), z, 0.018, 0.021, seg=5)
    crystal("Spike", m, iron, (0, 0, -0.075), 0.02, 0.0, 0.07, seg=4)
    fin("w_goblin_cleaver", 0.12, 0.69)


def build_guardian_greatsword():
    m = vcf("w_guardian", metal=0.4)
    g = vcf("w_guardian_gem", emit="#ffc860", strength=1.2)
    sword_blade("Blade", [(-0.044, 0.12), (0.044, 0.12), (0.038, 0.98), (0.0, 1.2), (-0.038, 0.98)], m,
                metal("#f6f2e8", "#bcb8b0", "#55504a"), th=0.015, bevel=0.014)
    gold = H("#e8c060")
    flat("Inlay", [(-0.006, 0.15), (0.006, 0.15), (0.004, 0.86), (0.0, 0.92), (-0.004, 0.86)], m, gold, th=0.0158,
         bevel=0.002, step=0.005, ridge=0.0)
    tube("Guard", spline([(-0.17, 0, 0.14), (-0.13, 0, 0.112), (0, 0, 0.105), (0.13, 0, 0.112), (0.17, 0, 0.14)], 4),
         lambda t: 0.017 - 0.005 * abs(2 * t - 1), m, gold, sides=6)
    for s in (1, -1):
        crystal("GuardEnd%d" % s, m, gold, (0.172 * s, 0, 0.145), 0.016, 0.03, 0.012, seg=4)
    crystal("Block", m, gold, (0, 0, 0.105), 0.035, 0.03, 0.03, seg=4, phase=math.pi / 4)
    orb("Gem", g, H("#ffc860"), (0, -0.02, 0.105), 0.02, seg=8)
    wrap("Grip", m, H("#6a2a22"), -0.11, 0.08, 0.018, turns=9)
    lathe("Pommel", [(-0.16, 0.0), (-0.155, 0.02), (-0.135, 0.03), (-0.12, 0.022), (-0.11, 0.0)], m, gold, seg=8,
          smooth=False)
    orb("PommelGem", g, H("#ffc860"), (0, -0.024, -0.135), 0.011, seg=6)
    fin("w_guardian_greatsword", 0.0, 1.2)


def build_dragonfang():
    m = vcf("w_dragon", metal=0.2)
    g = vcf("w_dragon_gem", emit="#ff4a2a", strength=1.4)
    cx = lambda z: -0.1 * max(0.0, (z - 0.1) / 0.95) ** 1.6
    w = lambda z: 0.078 * max(0.0, 1 - (z - 0.1) / 0.98) ** 0.75 + 0.004
    n = 18
    zs = [0.08 + 0.97 * i / n for i in range(n)]
    back = []
    for i, z in enumerate(zs):
        b = cx(z) - w(z) * 0.45
        back.append((b, z))
        if 2 <= i < n - 4 and i % 2 == 0:
            back.append((b - 0.016 * w(z) / 0.08, z + 0.025))       # dente nas costas
    edge = [(cx(z) + w(z) * 0.55, z) for z in zs]
    tip = (cx(1.06) - 0.004, 1.06)
    ol = back + [tip] + list(reversed(edge))

    def fang(x, z, c):
        t = ramp([(0.1, H("#f4e8cc")), (0.55, H("#f8c890")), (0.85, H("#ff7a34")), (1.06, H("#d42a1c"))], z)
        return mix(mix(t, H("#fff6e4"), 0.5), t, smooth01((x - cx(z) + 0.004) / 0.008))
    sword_blade("Blade", ol, m, metal("#ffffff", "#f0e0c0", "#5a2418", cx=cx, extra=fang), th=0.016, bevel=0.015)
    horn = H("#8a1c16")
    for s in (1, -1):
        tube("Horn%d" % s, spline([(0.02 * s, 0, 0.08), (0.07 * s, 0, 0.095), (0.11 * s, 0, 0.07), (0.125 * s, 0, 0.025)], 4),
             lambda t: 0.017 * (1 - t) + 0.003, m, horn, sides=6)
    crystal("Block", m, horn, (0, 0, 0.075), 0.03, 0.025, 0.02, seg=5)
    wrap("Grip", m, H("#7a1e18"), -0.085, 0.055, 0.017, turns=6)
    orb("PommelGem", g, H("#ff5a32"), (0, 0, -0.112), 0.019, seg=8)
    for k in range(3):
        a = 2 * math.pi * k / 3 + 0.5
        tube("Claw%d" % k, spline([(0.008 * math.cos(a), 0.008 * math.sin(a), -0.085),
                                   (0.024 * math.cos(a), 0.024 * math.sin(a), -0.105),
                                   (0.014 * math.cos(a), 0.014 * math.sin(a), -0.13)], 3),
             lambda t: 0.006 * (1 - t) + 0.0015, m, H("#2a1a18"), sides=5)
    fin("w_dragonfang", *tip)


ARMORY += [("w_wooden_sword", build_wooden_sword), ("w_iron_sword", build_iron_sword),
           ("w_steel_saber", build_steel_saber), ("w_knight_blade", build_knight_blade),
           ("w_frost_brand", build_frost_brand), ("w_goblin_cleaver", build_goblin_cleaver),
           ("w_guardian_greatsword", build_guardian_greatsword), ("w_dragonfang", build_dragonfang)]


# ------------------------------------------------------------------ cetros do healer (sc_<id>.glb)
## Cetro: ~0,7x o cajado. Mesma empunhadura (z = STAFF_HAND), mas a vara termina em z≈-0,27 e a cabeça fica em
## ~0,8; paleta marfim/dourada, cabeça luminosa (gema, disco de sol, emblema, auréola) presa à vara.
def sc_body(prefix, wood, z1, bands=(), gold="#d7a648", grip="#7a5a3a", r0=0.021, r1=0.018, seg=8, metal=0.0):
    m = vcf(prefix, metal=metal)
    shaft("Shaft", m, wood, z0=-0.25, z1=z1, r0=r0, r1=r1, seg=seg)
    ferrule("Ferrule", m, H(gold), z0=-0.28, z1=-0.17, r=r0 + 0.004)
    grip_wrap(m, H(grip), r=r0 + 0.005)
    for z in bands:
        band("Band%.2f" % z, m, H(gold), z, 0.024, r1 + 0.005)
    return m


def build_sc_novice():
    g = vcf("sc_novice_gem", emit="#fff2a0", strength=0.8)
    m = sc_body("sc_novice", grain("#c89a5e", "#8f6a3a"), 0.72, bands=(0.62,), gold="#c99a3c", grip="#6b4226")
    cup("Cup", m, H("#c99a3c"), 0.64, 0.76, 0.022, 0.034)
    orb("Gem", g, H("#fff0a0"), (0, 0, 0.8), 0.045)
    finish_staff("sc_novice_scepter", 0.8)


def build_sc_dawn():
    g = vcf("sc_dawn_gem", emit="#ffd98a", strength=1.0)
    gold = H("#f0b83a")
    m = sc_body("sc_dawn", lambda co: mix(H("#f6eedc"), H("#e0d2b4"), 0.5 + 0.5 * math.sin(co.z * 11)), 0.7,
                bands=(0.0, 0.5), gold="#e8b440", grip="#b8452e", metal=0.3)
    cup("Cup", m, gold, 0.66, 0.74, 0.022, 0.03)
    tube("Stem", [(0, 0, 0.7), (0, 0, 0.82)], 0.011, m, gold)
    cz = 0.84
    rays = []
    for i in range(16):
        a = math.pi / 2 + math.pi * i / 8
        rr = 0.11 if i % 2 == 0 else 0.072
        rays.append((rr * math.cos(a), cz + rr * math.sin(a)))
    hole = [(0.046 * math.cos(2 * math.pi * k / 12), cz + 0.046 * math.sin(2 * math.pi * k / 12)) for k in range(12)]
    flat("Rays", rays, m, lambda co: mix(H("#ffd75a"), H("#e89a2a"), smooth01((Vector((co.x, 0, co.z - cz)).length - 0.05) / 0.06)),
         th=0.008, bevel=0.006, step=0.012, holes=[hole])
    cel(torus("Rim", (0, cz), 0.052, 0.009, m, seg=18, sides=6), gold)
    orb("Gem", g, H("#ffe29a"), (0, 0, cz), 0.05)
    finish_staff("sc_dawn_scepter", cz)


def cross_star(cz, L, W):
    """Estrela de quatro pontas (emblema sagrado) no plano XZ, centrada em (0, cz)."""
    pts = []
    for i in range(8):
        a = math.pi / 2 + i * math.pi / 4
        r = L if i % 2 == 0 else W
        pts.append((r * math.cos(a), cz + r * math.sin(a)))
    return pts


def build_sc_blessed():
    g = vcf("sc_blessed_gem", emit="#fff6c0", strength=1.1)
    gold = H("#eab83e")
    m = sc_body("sc_blessed", lambda co: mix(H("#f4ecd8"), H("#d9c9a6"), 0.5 + 0.5 * math.sin(co.z * 9)), 0.72,
                bands=(0.05, 0.56), gold="#eab83e", grip="#f0e6d0", metal=0.35)
    cup("Cup", m, gold, 0.66, 0.76, 0.022, 0.034)
    cz = 0.86
    tube("Stem", [(0, 0, 0.72), (0, 0, cz)], 0.012, m, gold)
    flat("Star", cross_star(cz, 0.14, 0.045), m, lambda co: mix(H("#ffd75a"), H("#e8a830"), smooth01((abs(co.z - cz) + abs(co.x)) / 0.2)),
         th=0.012, bevel=0.007, step=0.01)
    cel(torus("Rim", (0, cz), 0.058, 0.01, m, seg=18, sides=6), gold)
    orb("Gem", g, H("#fff3b8"), (0, 0, cz), 0.055)
    finish_staff("sc_blessed_scepter", cz)


def build_sc_seraph():
    g = vcf("sc_seraph_gem", emit="#fffbe0", strength=1.3)
    gold = H("#f2c04a")
    ivory = H("#fbf6ea")
    m = sc_body("sc_seraph", lambda co: mix(H("#fbf6ea"), H("#e6dcc4"), 0.5 + 0.5 * math.sin(co.z * 10)), 0.72,
                bands=(0.0, 0.46, 0.58), gold="#f2c04a", grip="#d9a93e", r0=0.022, r1=0.019, metal=0.4)
    cup("Cup", m, gold, 0.64, 0.77, 0.024, 0.036)
    cz = 0.86
    tube("Stem", [(0, 0, 0.72), (0, 0, cz)], 0.013, m, gold)
    for sgn in (-1, 1):   # asas de penas abertas dos dois lados da gema, pontas douradas
        for k, (L, W, ry) in enumerate(((0.19, 0.04, 1.4), (0.2, 0.042, 1.0), (0.17, 0.038, 0.6))):
            flat("Wing%d_%d" % (sgn, k), leaf_outline(L, W), m,
                 lambda co: mix(H("#fbf6ea"), H("#f2c04a"), smooth01((Vector((co.x, 0, co.z - cz)).length - 0.1) / 0.1)),
                 th=0.01, bevel=0.005, step=0.012, loc=(sgn * 0.03, 0.0, cz - 0.03 + k * 0.012), rot=(0, sgn * ry, 0))
    cel(torus("Halo", (0, cz), 0.075, 0.01, m, seg=20, sides=6), gold)
    orb("Gem", g, H("#fffbe6"), (0, 0, cz), 0.058)
    finish_staff("sc_seraph_scepter", cz)


def build_sc_halo():
    g = vcf("sc_halo_gem", emit="#fff2a8", strength=1.6)
    gold = H("#f6c84e")
    m = sc_body("sc_halo", lambda co: mix(H("#f7d46a"), H("#d49a2a"), 0.5 + 0.5 * math.sin(co.z * 12)), 0.74,
                bands=(-0.05, 0.42, 0.52, 0.62), gold="#fff0b0", grip="#fbf2dc", r0=0.023, r1=0.02, metal=0.5)
    cup("Cup", m, gold, 0.66, 0.8, 0.026, 0.04)
    cz = 0.97
    tube("Stem", [(0, 0, 0.74), (0, 0, cz)], 0.015, m, gold)
    rays = []
    for i in range(32):
        a = math.pi / 2 + math.pi * i / 16
        rr = 0.19 if i % 4 == 0 else (0.15 if i % 2 == 0 else 0.108)
        rays.append((rr * math.cos(a), cz + rr * math.sin(a)))
    hole = [(0.082 * math.cos(2 * math.pi * k / 16), cz + 0.082 * math.sin(2 * math.pi * k / 16)) for k in range(16)]
    flat("Rays", rays, m, lambda co: mix(H("#fff0a0"), H("#eaa530"), smooth01((Vector((co.x, 0, co.z - cz)).length - 0.09) / 0.1)),
         th=0.01, bevel=0.007, step=0.012, holes=[hole])
    cel(torus("Halo", (0, cz), 0.088, 0.013, m, seg=24, sides=6), gold)
    cel(torus("Halo2", (0, cz), 0.125, 0.008, m, seg=24, sides=5), H("#fff6d0"))
    orb("Gem", g, H("#fff6b8"), (0, 0, cz), 0.075)
    finish_staff("sc_halo_scepter", cz)


ARMORY += [("sc_novice_scepter", build_sc_novice), ("sc_dawn_scepter", build_sc_dawn),
           ("sc_blessed_scepter", build_sc_blessed), ("sc_seraph_scepter", build_sc_seraph),
           ("sc_halo_scepter", build_sc_halo)]


# ------------------------------------------------------------------ ferramentas de coleta (tl_<tipo>_<nível>.glb)
# Picaretas e machados que o personagem saca para minerar e cortar árvores (GatherAction). Mesma convenção das
# espadas: cabo em +Z com a mão direita na origem, cabeça perto de z = 0,575 e o lado que bate (ponta da picareta,
# gume do machado) em +X. O machado é girado 90° no eixo do cabo no jogo (KnightLook.AXE_ROLL) para o gume liderar
# o corte horizontal. A mão esquerda pega o cabo em z ≈ -0,13 (KnightMoves.TOOL_LEFT_GRIP).
# "Tip" = ponto que bate na pedra/árvore (faíscas e lascas nascem ali).
# Cada nível é mais rico que o de baixo, na cabeça e no cabo: pedra amarrada num galho; ferro com ponteira, talas e
# rebites; mitril com espiral, crista e ouro; cristal com prata, anéis de runa acesos, lascas e pomo de cristal; astral
# com filigrana dupla de ouro, runas douradas, asas e uma estrela no pomo. Luz e partículas: KnightLook._tool_fx.
TOOL_TIERS = {
    # madeira, veio, empunhadura, cabeça (luz, base, sombra), metal dos enfeites, brilho (gema/runa) ou None
    "stone": dict(wood="#a8794a", grain="#7a5230", wrap="#6e4c2c", head=("#bdb8ae", "#8e8a82", "#55524e"),
                  ring="#6e4c2c", glow=None, rock=True),
    "iron": dict(wood="#a06c3c", grain="#704826", wrap="#4a3020", head=("#eef2f6", "#a8b4c4", "#46505e"),
                 ring="#5e6672", glow=None),
    "mithril": dict(wood="#5e4030", grain="#3a2618", wrap="#2c3a4a", head=("#e8fcff", "#8fdde8", "#2f6c78"),
                    ring="#e0b44a", glow=None),
    "crystal": dict(wood="#ece2cc", grain="#c4b496", wrap="#5a3a8a", head=("#e6dcff", "#a98cf0", "#5b3fa6"),
                    ring="#d8deea", glow="#9a60ff", gem="#8f5cff"),
    "astral": dict(wood="#3e2c60", grain="#22163a", wrap="#4a2a78", head=("#f4e0ff", "#b878f0", "#5a2a90"),
                   ring="#f0c050", glow="#ffb02a", gem="#ffc23a"),
}
TOOL_EYE_Z = 0.575
TOOL_WING = [(0.0, 0.0), (0.03, 0.015), (0.075, 0.06), (0.09, 0.12), (0.07, 0.1), (0.045, 0.07), (0.02, 0.045), (0.0, 0.035)]


def _langets(m, col, z0=0.4, z1=0.545):
    """Talas de metal descendo do olho pelo cabo (frente e costas), com dois rebites cada."""
    for sy in (1, -1):
        tube("Langet%d" % sy, [(0, 0.021 * sy, z0), (0, 0.021 * sy, z1)], 0.0065, m, col, sides=6, flat=0.55)
        for z in (z0 + 0.025, z0 + 0.08):
            orb("Rivet%d_%.2f" % (sy, z), m, col, (0, 0.027 * sy, z), 0.0055, seg=6)


def _tool_handle(tier, t, m, g):
    wood = grain(t["wood"], t["grain"], freq=2.0, zf=11.0, amt=0.4)
    ring = H(t["ring"])
    if tier == "stone":   # galho torto com nós, empunhadura de couro amarrada e um seixo no pé
        shaft("Handle", m, wood, z0=-0.21, z1=0.63, r0=0.022, r1=0.019, seg=8, wobble=0.004, seed=3,
              knots=((-0.2, 0.004, 0.02), (0.17, 0.005, 0.014), (0.36, 0.004, 0.012)))
        wrap("Grip", m, H(t["wrap"]), -0.19, -0.04, 0.0245, turns=4, seg=8)
        tube("Tie", spline([(0.0, -0.02, -0.03), (0.0, -0.032, -0.06), (0.004, -0.03, -0.1)], 4), 0.004, m, H(t["wrap"]))
        orb("Knob", m, H(t["head"][1]), (0, 0, -0.222), 0.027, seg=7)
        return
    shaft("Handle", m, wood, z0=-0.21, z1=0.63, r0=0.021, r1=0.019, seg=12)
    wrap("Grip", m, H(t["wrap"]), -0.19, -0.035, 0.0235, turns=6, seg=12)
    if tier == "iron":
        lathe("Butt", [(-0.245, 0.0), (-0.245, 0.017), (-0.236, 0.026), (-0.2, 0.026), (-0.196, 0.022), (-0.196, 0.0)],
              m, ring, seg=12, smooth=False)
        band("Mid", m, ring, 0.0, h=0.018, r=0.024, seg=12)
        _langets(m, ring)
        return
    if tier == "mithril":
        helix("Spiral", m, H(t["head"][1]), 0.0, 0.42, 0.0205, 2.5, r=0.0045, sides=6)
        for z in (-0.19, -0.035, 0.0, 0.42):
            band("Gold%.2f" % z, m, ring, z, h=0.016, r=0.026, seg=12)
        lathe("Butt", [(-0.25, 0.0), (-0.25, 0.012), (-0.238, 0.027), (-0.205, 0.025), (-0.2, 0.0)], m, ring, seg=12,
              smooth=False)
        orb("ButtGem", m, H(t["head"][0]), (0, 0, -0.258), 0.013, seg=8)
        _langets(m, ring)
        return
    # cristal e astral: filigrana dupla, anéis de runa acesos e pomo com gema
    helix("Filigree", m, ring, -0.01, 0.47, 0.0205, 2.5, r=0.004, sides=6)
    helix("Filigree2", m, ring, -0.01, 0.47, 0.0205, 2.5, r=0.004, phase=math.pi, sides=6)
    for z in (-0.19, -0.035, -0.015, 0.49):
        band("Band%.2f" % z, m, ring, z, h=0.016, r=0.026, seg=12)
    runes = (0.12, 0.3) if tier == "crystal" else (0.08, 0.2, 0.32)
    for z in runes:
        band("Rune%.2f" % z, g, H(t["gem"]), z, h=0.018, r=0.0225, seg=12)
    _langets(m, ring, z0=0.43)
    lathe("Cup", [(-0.258, 0.0), (-0.258, 0.013), (-0.232, 0.027), (-0.2, 0.024), (-0.198, 0.0)], m, ring, seg=12,
          smooth=False)
    if tier == "crystal":
        crystal("Pommel", g, H(t["gem"]), (0, 0, -0.27), 0.02, 0.03, 0.045, seg=6)
        return
    orb("Pommel", g, H(t["gem"]), (0, 0, -0.272), 0.021, seg=10)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        tube("Prong%d" % k, [(0.02 * math.cos(a), 0.02 * math.sin(a), -0.25), (0.016 * math.cos(a), 0.016 * math.sin(a), -0.28)],
             0.0035, m, ring)
    star = []
    for i in range(8):
        rr = 0.032 if i % 2 == 0 else 0.011
        a = math.pi / 2 + math.pi * i / 4
        star.append((rr * math.cos(a), -0.3 + rr * math.sin(a)))
    flat("Star", star, g, H(t["gem"]), th=0.006, bevel=0.004, step=0.006)


def _head_paint(t):
    L, B, E = (H(c) for c in t["head"])

    def fn(co):
        if t.get("rock"):
            return mix(B, L, 0.25 * (0.5 + 0.5 * math.sin(co.x * 40.0 + co.z * 25.0)))
        return B
    return fn


def _pick_curve(span, lift=0.0, k=1.0):
    return spline([(-span * k, 0, 0.47 + lift), (-span * 0.55 * k, 0, 0.555 + lift), (0, 0, 0.585 + lift),
                   (span * 0.55 * k, 0, 0.555 + lift), ((span + 0.01) * k, 0, 0.465 + lift)], 6)


def _tips(span):
    return {1: ((span + 0.01), 0.465), -1: (-span, 0.47)}


def build_tool_pickaxe(tier):
    t = TOOL_TIERS[tier]
    rock = t.get("rock", False)
    m = vcf("tl_pick_" + tier, metal=0.0 if rock else 0.45)
    g = vcf("tl_pick_%s_gem" % tier, emit=t["glow"], strength=0.8) if t["glow"] else None
    _tool_handle(tier, t, m, g)
    ring = H(t["ring"])
    span = {"stone": 0.22, "iron": 0.25, "mithril": 0.26, "crystal": 0.26, "astral": 0.27}[tier]
    thick = {"stone": 0.036, "iron": 0.028, "mithril": 0.028, "crystal": 0.026, "astral": 0.029}[tier]

    def rad(u):
        return thick * (0.16 + 0.84 * math.sin(math.pi * u) ** 0.55)
    tube("Head", _pick_curve(span), rad, m, _head_paint(t), sides=6 if rock else 10, flat=0.8, smooth=not rock)
    if rock:   # pedra lascada amarrada com tiras de couro cruzando o cabo
        helix("Lash", m, H(t["wrap"]), 0.52, 0.64, 0.024, 2.5, r=0.0065)
        tube("LashX", [(-0.04, -0.012, 0.6), (0.04, -0.012, 0.56)], 0.006, m, H(t["wrap"]))
        tube("LashX2", [(-0.04, 0.012, 0.56), (0.04, 0.012, 0.6)], 0.006, m, H(t["wrap"]))
        fin("tl_pickaxe_" + tier, span + 0.01, 0.465)
        return
    band("Socket", m, ring, TOOL_EYE_Z - 0.005, h=0.104, r=0.031, seg=14)
    band("Collar", m, ring, 0.51, h=0.02, r=0.026, seg=14)
    if tier in ("mithril", "crystal", "astral"):   # crista clara correndo por cima da meia-lua, rebites no olho
        tube("Ridge", _pick_curve(span, 0.016, 0.82), lambda u: 0.009 * math.sin(math.pi * u) ** 0.6 + 0.001, m,
             H(t["head"][0]), sides=8)
        for sy in (1, -1):
            orb("EyeRivet%d" % sy, m, H(t["head"][0]) if tier == "mithril" else ring, (0, 0.031 * sy, TOOL_EYE_Z), 0.007, seg=8)
    if tier == "crystal":
        gem = H(t["gem"])
        for sx, (tx, tz) in _tips(span).items():   # pontas de cristal nas duas pontas e lascas ao longo da meia-lua
            crystal("TipShard%d" % sx, g, gem, (tx - 0.012 * sx, 0, tz + 0.008), 0.014, 0.05, 0.015, seg=6,
                    rot=(0, sx * 2.1, 0))
            for k, (u, h) in enumerate(((0.35, 0.035), (0.6, 0.028))):
                x = span * u * sx
                z = 0.585 - (0.585 - 0.47) * (u ** 1.6)
                crystal("Shard%d_%d" % (sx, k), g, gem, (x, 0, z + 0.008), 0.009, h, 0.01, seg=5, rot=(0, sx * 0.5, 0))
        crystal("Crest", g, gem, (0, 0, 0.63), 0.016, 0.055, 0.02, seg=6)
    if tier == "astral":
        tube("Trim", _pick_curve(span, 0.024, 0.9), lambda u: 0.0055 * math.sin(math.pi * u) ** 0.4 + 0.0015, m, ring,
             sides=6)
        for sx, (tx, tz) in _tips(span).items():
            cel(flat("Wing%d" % sx, [(x * sx, z) for x, z in TOOL_WING], m, th=0.006, bevel=0.005, step=0.008,
                     loc=(0.022 * sx, 0, TOOL_EYE_Z + 0.01)), ring)
            crystal("Glow%d" % sx, g, H(t["gem"]), (tx - 0.012 * sx, 0, tz + 0.008), 0.012, 0.04, 0.012, seg=6,
                    rot=(0, sx * 2.1, 0))
        orb("Gem", g, H(t["gem"]), (0, -0.034, TOOL_EYE_Z), 0.019, seg=10)
        for s in (-1, 1):
            tube("GemProng%d" % s, [(0.0, -0.028, TOOL_EYE_Z + 0.03 * s), (0.0, -0.04, TOOL_EYE_Z + 0.012 * s)], 0.004, m, ring)
        crystal("Crest", g, H(t["gem"]), (0, 0, 0.635), 0.014, 0.05, 0.02, seg=6)
    fin("tl_pickaxe_" + tier, span + 0.01, 0.465)


def build_tool_axe(tier):
    t = TOOL_TIERS[tier]
    rock = t.get("rock", False)
    m = vcf("tl_axe_" + tier, metal=0.0 if rock else 0.45)
    g = vcf("tl_axe_%s_gem" % tier, emit=t["glow"], strength=0.8) if t["glow"] else None
    _tool_handle(tier, t, m, g)
    ring = H(t["ring"])
    # lâmina no plano XZ: pescoço estreito saindo do olho e o gume curvo em +X
    w = {"stone": 0.17, "iron": 0.2, "mithril": 0.21, "crystal": 0.21, "astral": 0.22}[tier]
    out = [(-0.06, 0.515), (0.04, 0.515), (w * 0.55, 0.455), (w * 0.9, 0.39), (w + 0.012, 0.43), (w + 0.022, 0.52),
           (w + 0.016, 0.61), (w * 0.92, 0.69), (w * 0.55, 0.63), (0.04, 0.6), (-0.06, 0.6)]
    L, B, E = (H(c) for c in t["head"])
    edge_x = w + 0.012

    def paint2d(x, z, d):
        c = mix(B, L, smooth01((x - (edge_x - 0.05)) / 0.035))      # gume afiado claro
        if rock:
            c = mix(c, E, 0.25 * (0.5 + 0.5 * math.sin(x * 70 + z * 45)))
        return mix(E, c, smooth01((d - 0.001) / 0.009))
    th = 0.02 if rock else 0.015
    flat("Blade", out, m, th=th, bevel=0.012, step=0.01, paint2d=paint2d)
    if rock:
        helix("Lash", m, H(t["wrap"]), 0.5, 0.63, 0.024, 2.5, r=0.0065)
        tube("LashX", [(-0.04, -0.02, 0.6), (0.03, -0.02, 0.52)], 0.006, m, H(t["wrap"]))
        fin("tl_axe_" + tier, w + 0.022, 0.52)
        return
    band("Eye", m, ring, 0.557, h=0.105, r=0.031, seg=14)
    for sy in (1, -1):   # rebites prendendo a lâmina no olho
        for z in (0.535, 0.58):
            orb("Rivet%d_%.2f" % (sy, z), m, ring, (0.055, (th - 0.002) * sy, z), 0.006, seg=6)
    if tier in ("mithril", "astral"):   # filete gravado acompanhando o gume, nas duas faces
        inlay = spline([(w * 0.6, 0, 0.47), (w * 0.86, 0, 0.44), (w - 0.008, 0, 0.52), (w * 0.86, 0, 0.62), (w * 0.6, 0, 0.6)], 5)
        for sy in (1, -1):
            tube("Inlay%d" % sy, [(x, (th - 0.004) * sy, z) for x, _, z in inlay], 0.0042, m, ring, sides=5)
    if tier in ("crystal", "astral"):   # gume aceso: faixa de cristal/luz por todo o fio
        edge = [(w * 0.82, 0.405), (w + 0.012, 0.43), (w + 0.022, 0.52), (w + 0.016, 0.61), (w * 0.86, 0.675),
                (w * 0.8, 0.62), (w - 0.008, 0.52), (w * 0.82, 0.44)]
        flat("Edge", edge, g, H(t["gem"]), th=th + 0.002, bevel=0.006, step=0.008)
    if tier == "crystal":
        crystal("Shard", g, H(t["gem"]), (-0.075, 0.0, 0.557), 0.02, 0.035, 0.03, seg=6, rot=(0, -math.pi / 2, 0))
        crystal("Crest", g, H(t["gem"]), (0, 0, 0.62), 0.014, 0.045, 0.015, seg=6)
    if tier == "astral":
        orb("Gem", g, H(t["gem"]), (0.085, -0.014, 0.557), 0.018, seg=10)
        cel(place(torus("GemRim", (0.085, 0.557), 0.022, 0.0045, m, seg=14, sides=5), (0, -0.0125, 0)), ring)
        cel(flat("Wing", [(-x, z) for x, z in TOOL_WING], m, th=0.006, bevel=0.005, step=0.008, loc=(-0.02, 0, 0.57)), ring)
        crystal("Crest", g, H(t["gem"]), (0, 0, 0.625), 0.014, 0.05, 0.015, seg=6)
    fin("tl_axe_" + tier, w + 0.022, 0.52)


for _tier in TOOL_TIERS:
    ARMORY += [("tl_pickaxe_" + _tier, (lambda tt=_tier: build_tool_pickaxe(tt))),
               ("tl_axe_" + _tier, (lambda tt=_tier: build_tool_axe(tt)))]


# ------------------------------------------------------------------ escudos (sh_<id>.glb)
## Escudo preso no antebraço esquerdo (KnightLook._build_shield). Convenção do GLB:
##   face da frente em -Y, altura em Z, largura em X; origem = centro das costas do escudo, onde o antebraço
##   encosta (o jogo põe a origem no lugar do escudo antigo do knight.glb). Atrás vão as alças de couro
##   (enarmes: uma presa ao antebraço, outra na mão), encostadas na tábua.
## Referências: broquel (escudo de mão pequeno, todo de metal), escudo redondo nórdico (tábuas, umbo de ferro,
## borda de couro cru costurada), escudo pipa normando (gota alongada, cobre do ombro à canela), pavês
## (retangular alto, quilha central), heater (o "ferro de passar" do séc. XIII, brasão) e um escudo de dragão
## de fantasia para o fim do nivelamento.

def sh_bend(cx=0.0, cz=0.0):
    """Curvatura da tábua: as bordas recuam (+Y) — cx curva de lado a lado, cz de cima a baixo (domo: os dois)."""
    def fn(co):
        co.y += cx * co.x * co.x + cz * co.z * co.z
        return co
    return fn


def sh_y(x, z, cx, cz, th):
    """Y da face da frente da tábua no ponto (x, z), um tico para dentro (peças por cima encostam)."""
    return cx * x * x + cz * z * z - 2.0 * th + 0.002


def sh_face(L, B, S, E, size, contour=0.012, extra=None):
    """Pintura anime da face: luz no alto à esquerda, base no meio, sombra embaixo à direita (bandas duras),
    contorno escuro na borda. extra(x, z, cor) -> cor pinta desenhos por cima."""
    L, B, S, E = H(L), H(B), H(S), H(E)

    def fn(x, z, d):
        k = (-x * 0.55 + z * 0.8) / size
        c = mix(S, B, smooth01((k + 0.42) / 0.03))
        c = mix(c, L, smooth01((k - 0.3) / 0.03))
        if extra:
            c = extra(x, z, c)
        return mix(E, c, smooth01((d - 0.001) / contour))
    return fn


def sh_tint(col, base, ref):
    """Troca a cor de `col` (já com luz/sombra da face) por `base`, mantendo o quanto `col` é mais claro ou
    escuro que `ref` (a base da face): desenho pintado com a mesma luz anime."""
    lum = lambda c: 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]
    k = lum(col) / max(lum(ref), 1e-4)
    return tuple(min(1.0, b * k) for b in base)


def sh_board(outline, m, paint2d, th, cx, cz):
    return flat("Board", outline, m, th=th, bevel=th * 0.9, step=0.008, paint2d=paint2d, bend=sh_bend(cx, cz),
                loc=(0, -th, 0), ridge=0.1)


def sh_rim(outline, m, col, r, cx, cz, th, per=3):
    """Aro de metal (ou couro) por todo o contorno, no meio da espessura da tábua."""
    pts = spline(list(outline) + [outline[0], outline[1]], per)[: -per]
    pts = [(x, cx * x * x + cz * z * z - th, z) for x, z in pts]
    pts.append(pts[0])
    return tube("Rim", pts, r, m, col, sides=6, flat=0.8)


def sh_boss(m, col, x, z, cx, cz, th, r=0.06, h=0.045, name="Boss"):
    """Umbo: domo de metal saindo da face."""
    prof = [(-0.012, r * 1.18), (0.004, r * 1.18), (0.006, r),   # a base afunda na tábua curva
            (h * 0.55, r * 0.78), (h * 0.85, r * 0.45), (h, 0.0)]
    return lathe(name, prof, m, col, seg=14, loc=(x, sh_y(x, z, cx, cz, th), z), rot=(math.pi / 2, 0, 0))


def sh_rivet(m, col, x, z, cx, cz, th, r=0.009, name="Rivet"):
    return orb("%s_%.3f_%.3f" % (name, x, z), m, col, (x, sh_y(x, z, cx, cz, th) - r * 0.3, z), r, seg=6)


def sh_straps(m, col=None, w=0.05, zs=(0.07, -0.08)):
    """Enarmes: duas alças de couro em U atrás da tábua (antebraço na de cima, mão na de baixo)."""
    col = col or H("#6a4428")
    for k, z in enumerate(zs):
        pts = [(-w, -0.004, z), (-w * 0.95, 0.04, z), (0.0, 0.075, z), (w * 0.95, 0.04, z), (w, -0.004, z)]
        tube("Strap%d" % k, spline(pts, 3), 0.008, m, col, sides=5, flat=0.45)
    tube("Guige", spline([(-w * 1.6, -0.004, zs[0] + 0.1), (0.0, 0.03, zs[0] + 0.13), (w * 1.6, -0.004, zs[0] + 0.1)], 3),
         0.006, m, col, sides=5, flat=0.5)   # alça longa (guige) de pendurar no ombro


def sh_circle(R, n=40):
    return [(R * math.cos(2 * math.pi * i / n), R * math.sin(2 * math.pi * i / n)) for i in range(n)]


def sh_heater(w, top, bot, n=12, arch=0.03):
    """Heater: topo levemente arqueado, laterais retas que curvam até a ponta embaixo."""
    out = []
    for i in range(n + 1):   # topo da esquerda para a direita
        x = -w + 2 * w * i / n
        out.append((x, top + arch * (1 - (x / w) ** 2)))
    side = []
    for i in range(1, n + 1):   # lado direito descendo: reto no começo e curvando para a ponta
        t = i / n
        z = top - (top - bot) * t
        x = w * math.cos(t * t * math.pi / 2) if t < 1 else 0.0
        side.append((x, z))
    out += side
    out += [(-x, z) for x, z in reversed(side[:-1])]
    return out


def sh_kite(w, top, bot, n=14):
    """Pipa: topo redondo, a maior largura alto e a ponta comprida embaixo."""
    out = []
    zc = top - w
    for i in range(n + 1):   # meia-lua de cima
        a = math.pi * i / n
        out.append((-w * math.cos(a), zc + w * math.sin(a)))
    for i in range(1, n + 1):   # lado direito descendo até a ponta
        t = i / n
        out.append((w * (1 - t) ** 1.35, zc - (zc - bot) * t))
    out += [(-x, z) for x, z in reversed(out[n + 1:-1])]
    return out


# ---- 1. Broquel de Ferro: pequeno, todo de metal, domo raso e umbo grande (escudo de mão)
def build_sh_iron_buckler():
    m = vcf("sh_buckler", metal=0.45)
    R, th, c = 0.15, 0.012, 0.9
    ol = sh_circle(R)

    def rings(x, z, col):
        r = math.hypot(x, z)
        return mix(col, H("#5c6676"), 0.7 if abs(r - 0.105) < 0.004 else 0.0)   # sulco circular batido
    sh_board(ol, m, sh_face("#e4eaf2", "#a7b2c2", "#6e7a8e", "#353c48", R, extra=rings), th, c, c)
    sh_rim(ol, m, H("#5e6878"), 0.011, c, c, th, per=2)
    sh_boss(m, H("#c8d0dc"), 0, 0, c, c, th, r=0.06, h=0.05)
    for k in range(8):
        a = 2 * math.pi * k / 8 + math.pi / 8
        sh_rivet(m, H("#e6ecf4"), 0.083 * math.cos(a), 0.083 * math.sin(a), c, c, th, r=0.0075)
    sh_straps(m, w=0.04, zs=(0.035, -0.045))
    fin("sh_iron_buckler", 0.0, 0.0)


# ---- 2. Escudo Redondo Nórdico: tábuas, metades pintadas, umbo de ferro e borda de couro costurada
def build_sh_round_shield():
    m = vcf("sh_round", metal=0.1)
    R, th, c = 0.27, 0.011, 0.35
    ol = sh_circle(R, 48)
    blue, cream = H("#3a6aa8"), H("#efe2c2")

    def paint(x, z, col):
        a = math.atan2(z, x) + 0.35 * math.hypot(x, z) / R * math.pi   # quartos girando (redemoinho)
        q = int(((a % (2 * math.pi)) / (math.pi / 2))) % 2
        col = sh_tint(col, blue if q == 0 else cream, H("#b98a52"))
        p = (x + R) / 0.075                                            # tábuas verticais e frestas
        if abs(p - round(p)) < 0.035:
            col = mix(col, H("#3a2a1c"), 0.6)
        return col
    sh_board(ol, m, sh_face("#f0d8a8", "#b98a52", "#7a5634", "#2e2014", R, extra=paint), th, c, c)
    sh_rim(ol, m, H("#8a6a44"), 0.013, c, c, th, per=2)
    for k in range(24):   # pontos da costura do couro cru na borda
        a = 2 * math.pi * k / 24
        x, z = (R - 0.022) * math.cos(a), (R - 0.022) * math.sin(a)
        sh_rivet(m, H("#d8c8a0"), x, z, c, c, th, r=0.0045, name="Stitch")
    sh_boss(m, H("#8a929e"), 0, 0, c, c, th, r=0.07, h=0.055)
    for k in range(6):
        a = 2 * math.pi * k / 6
        sh_rivet(m, H("#c4ccd6"), 0.087 * math.cos(a), 0.087 * math.sin(a), c, c, th, r=0.007)
    sh_straps(m)
    fin("sh_round_shield", 0.0, 0.0)


# ---- 3. Escudo Pipa: gota normanda, campo verde, divisa dourada, aro e umbo de ferro
def build_sh_kite_shield():
    m = vcf("sh_kite", metal=0.2)
    w, top, bot, th, cx = 0.2, 0.25, -0.43, 0.012, 1.3
    ol = sh_kite(w, top, bot)

    def chevron(x, z, col):
        v = z + 0.05 - abs(x) * 0.9              # divisa em V aberto para baixo
        a = smooth01((v + 0.045) / 0.006) * (1.0 - smooth01(v / 0.006))
        return mix(col, sh_tint(col, H("#f2c84a"), H("#2f8a64")), a)
    sh_board(ol, m, sh_face("#7ed0a0", "#2f8a64", "#1c5a48", "#10261e", 0.3, extra=chevron), th, cx, 0.0)
    sh_rim(ol, m, H("#6a7282"), 0.012, cx, 0.0, th, per=2)
    sh_boss(m, H("#b8c2d0"), 0, 0.06, cx, 0.0, th, r=0.05, h=0.04)
    for x, z in ((-0.13, 0.12), (0.13, 0.12), (-0.07, -0.18), (0.07, -0.18), (0.0, -0.33)):
        sh_rivet(m, H("#dfe5ee"), x, z, cx, 0.0, th)
    sh_straps(m)
    fin("sh_kite_shield", 0.0, 0.0)


# ---- 4. Pavês de Torre: retangular alto, quilha central, cintas de ferro e rebites (o escudo de quem segura a linha)
def build_sh_tower_shield():
    m = vcf("sh_tower", metal=0.3)
    wt, wb, top, bot, th, cx = 0.23, 0.2, 0.36, -0.42, 0.014, 1.1
    ol = [(-wt, top - 0.03), (-wt + 0.03, top), (0.0, top + 0.035), (wt - 0.03, top), (wt, top - 0.03),
          (wb, bot + 0.04), (wb - 0.04, bot), (-wb + 0.04, bot), (-wb, bot + 0.04)]

    def bands(x, z, col):
        for zb in (0.22, -0.02, -0.28):
            if abs(z - zb) < 0.022:
                return mix(H("#5a6272"), H("#8a94a4"), 1.0 if z > zb else 0.0)
        if abs(x) < 0.03:      # quilha: luz de um lado, sombra do outro
            return mix(col, H("#f4e6c4") if x < 0 else H("#4a2e1a"), 0.55)
        return col
    sh_board(ol, m, sh_face("#e0b070", "#9c6236", "#62381e", "#24140c", 0.4, extra=bands), th, cx, 0.0)
    sh_rim(ol, m, H("#5a6272"), 0.014, cx, 0.0, th, per=2)
    tube("Keel", [(0.0, sh_y(0, z, cx, 0.0, th) - 0.004, z) for z in (bot + 0.03, 0.0, top + 0.01)],
         lambda t: 0.014, m, H("#8a6a48"), sides=4, flat=0.7)
    for zb in (0.22, -0.02, -0.28):
        for x in (-0.17, -0.06, 0.06, 0.17):
            sh_rivet(m, H("#d8dee8"), x, zb, cx, 0.0, th, r=0.0085)
    sh_boss(m, H("#9aa4b4"), 0, 0.1, cx, 0.0, th, r=0.045, h=0.035)
    sh_straps(m, w=0.055)
    fin("sh_tower_shield", 0.0, 0.0)


# ---- 5. Escudo do Leão Dourado: heater de aço azul-real, aro dourado e cabeça de leão em relevo (épico)
def build_sh_lion_shield():
    m = vcf("sh_lion", metal=0.45)
    w, top, bot, th, cx = 0.21, 0.25, -0.31, 0.012, 1.0
    ol = sh_heater(w, top, bot)
    gold = H("#e8b440")

    def field(x, z, col):
        r = math.hypot(x, z - 0.0)
        if abs(r - 0.135) < 0.006:   # anel gravado em volta do leão
            return mix(col, gold, 0.85)
        if z > 0.17 and abs(x) < 0.16 and int((x + 0.2) / 0.04) % 2 == 0:   # chefe listrado no alto
            return mix(col, H("#f4e0a0"), 0.35)
        return col
    sh_board(ol, m, sh_face("#7aa8f0", "#2c56b0", "#1a2e74", "#0e1636", 0.3, extra=field), th, cx, 0.0)
    sh_rim(ol, m, gold, 0.014, cx, 0.0, th, per=2)
    yf = sh_y(0, 0, cx, 0.0, th)
    # juba: duas voltas de mechas em volta da cara; cara; focinho com nariz; orelhas; olhos
    for ring, (n, L, off, tone) in enumerate(((14, 0.085, 0.045, 0.45), (14, 0.065, 0.04, 0.0))):
        for k in range(n):
            a = 2 * math.pi * (k + 0.5 * ring) / n
            ob = flat("Mane%d_%d" % (ring, k), [(-0.024, 0.0), (-0.01, L * 0.7), (0.0, L), (0.024, 0.0), (0.0, -0.01)],
                      m, th=0.008, bevel=0.007, step=0.008)
            place(ob, (0, 0, off), (0, -a + math.pi / 2, 0))
            place(ob, (0, yf - 0.004 - 0.006 * ring, 0.0))
            cel(ob, mix(gold, H("#b86a18"), tone if k % 2 else tone * 0.4))
    orb("Face", m, H("#f0c860"), (0, yf - 0.016, -0.004), 0.058, seg=12, sq=1.1)
    orb("Muzzle", m, H("#fae2a0"), (0, yf - 0.062, -0.03), 0.026, seg=8)
    orb("Nose", m, H("#6a3010"), (0, yf - 0.086, -0.016), 0.009, seg=6)
    for s_ in (1, -1):
        orb("Ear%d" % s_, m, gold, (0.045 * s_, yf - 0.024, 0.052), 0.018, seg=6)
        orb("Eye%d" % s_, m, H("#3a1a08"), (0.022 * s_, yf - 0.066, 0.012), 0.0075, seg=6)
    for x, z in ((-0.15, 0.2), (0.15, 0.2), (-0.12, -0.13), (0.12, -0.13), (0.0, -0.25)):
        sh_rivet(m, H("#fff0b0"), x, z, cx, 0.0, th, r=0.01)
    sh_straps(m)
    fin("sh_lion_shield", 0.0, 0.0)


# ---- 6. Égide do Dragão: escamas carmim, chifres no alto, aro de ouro velho e olho de dragão aceso (lendário)
def build_sh_dragon_aegis():
    m = vcf("sh_dragon", metal=0.3)
    g = vcf("sh_dragon_eye", emit="#ff6a2a", strength=1.6)
    w, top, bot, th, cx = 0.23, 0.27, -0.36, 0.013, 1.0
    ol = sh_heater(w, top, bot, arch=-0.04)   # topo cavado entre os chifres
    gold = H("#d8a03a")

    def scales(x, z, col):
        row = math.floor((z + 1.0) / 0.045)
        xo = x + (0.0225 if row % 2 else 0.0)
        u = (xo / 0.045) - math.floor(xo / 0.045) - 0.5
        v = (z + 1.0) / 0.045 - row
        edge = (u * u) * 1.6 + (1 - v) * 0.0
        if v < 0.22 + edge:          # contorno escuro embaixo de cada escama (escamas separadas)
            return mix(col, H("#2a0608"), 0.75)
        if v > 0.75 and abs(u) < 0.25:
            return mix(col, H("#ff9a7a"), 0.35)     # brilho no alto da escama
        return col
    sh_board(ol, m, sh_face("#e0485a", "#9a1626", "#5a0a1a", "#16040a", 0.32, extra=scales), th, cx, 0.0)
    sh_rim(ol, m, gold, 0.016, cx, 0.0, th, per=2)
    for s in (1, -1):   # chifres saindo dos cantos de cima, curvando para fora e para trás
        x0, z0 = w * s * 0.96, top - 0.02
        pts = spline([(x0, cx * x0 * x0 - th, z0), (x0 + 0.04 * s, cx * x0 * x0 - th + 0.01, z0 + 0.08),
                      (x0 + 0.1 * s, cx * x0 * x0 - th + 0.04, z0 + 0.13), (x0 + 0.16 * s, cx * x0 * x0 - th + 0.07, z0 + 0.12)], 4)
        tube("Horn%d" % s, pts, lambda t: 0.024 * (1 - t) ** 0.8 + 0.003, m, H("#2c1a1a"), sides=6)
        for k, z in enumerate((0.05, -0.12)):   # garras douradas agarrando a borda
            x = w * s * (0.98 if z > 0 else 0.86)
            yb = cx * x * x - th
            tube("Claw%d_%d" % (s, k), spline([(x + 0.015 * s, yb, z + 0.03), (x - 0.01 * s, yb - 0.025, z),
                                               (x - 0.035 * s, yb - 0.03, z - 0.03)], 3),
                 lambda t: 0.009 * (1 - t) + 0.002, m, gold, sides=5)
    yf = sh_y(0, 0.02, cx, 0.0, th)
    # olho: placa de ouro em amêndoa, íris acesa e pupila em fenda
    eye = [(-0.085, 0.02), (-0.04, 0.06), (0.0, 0.072), (0.04, 0.06), (0.085, 0.02), (0.04, -0.02), (0.0, -0.032),
           (-0.04, -0.02)]
    cel(flat("EyePlate", eye, m, th=0.008, bevel=0.007, step=0.008, loc=(0, yf - 0.004, 0.0)), gold)
    orb("Iris", g, H("#ff8a2a"), (0, yf - 0.012, 0.02), 0.032, seg=12, sq=0.85)
    cel(flat("Pupil", [(-0.006, -0.02), (0.006, -0.02), (0.006, 0.02), (-0.006, 0.02)], m, th=0.004, bevel=0.004,
             step=0.004, loc=(0, yf - 0.04, 0.02)), H("#1a0404"))
    for z in (-0.12, -0.2, -0.27):   # crista de espinhos descendo do olho
        crystal("Spine%.2f" % z, m, gold, (0, sh_y(0, z, cx, 0.0, th) - 0.004, z), 0.014, 0.03, 0.004, seg=4,
                rot=(math.pi / 2, 0, 0))
    sh_straps(m)
    fin("sh_dragon_aegis", 0.0, 0.0)


SHIELDS = [("sh_iron_buckler", build_sh_iron_buckler), ("sh_round_shield", build_sh_round_shield),
           ("sh_kite_shield", build_sh_kite_shield), ("sh_tower_shield", build_sh_tower_shield),
           ("sh_lion_shield", build_sh_lion_shield), ("sh_dragon_aegis", build_sh_dragon_aegis)]
ARMORY += SHIELDS


# ------------------------------------------------------------------ montantes (duas mãos)
## Espada de duas mãos (item "two_handed"): mesma regra das espadas (lâmina em +Z, empunhadura na origem), mas a
## origem é a mão de cima (a direita, junto da guarda) e o cabo desce até a mão de baixo: a esquerda pega em
## z = -GS_LEFT (KnightMoves.GREAT_LEFT_GRIP). Proporção de zweihänder/claymore: cabo ~1/4 do comprimento, ricasso
## sem fio com ganchos de aparo (parierhaken), guarda larga, lâmina de ~1,1 m.
GS_LEFT = 0.15


def gs_hilt(m, grip_col, z0=-0.27, z1=0.045, r=0.019, turns=11):
    wrap("Grip", m, grip_col, z0, z1, r, turns=turns, seg=8)


def gs_hooks(m, col, z, x0, reach=0.05, r=0.009):
    """Ganchos de aparo saindo do ricasso (começam dentro da lâmina, curvam para fora e para baixo)."""
    for s in (1, -1):
        tube("Hook%d" % s, spline([(x0 * 0.6 * s, 0, z), (x0 * s + reach * 0.55 * s, 0, z + 0.012),
                                   (x0 * s + reach * s, 0, z - 0.008), (x0 * s + reach * 0.85 * s, 0, z - 0.03)], 4),
             lambda t: r * (1 - 0.6 * t), m, col, sides=6)


def build_iron_zweihander():
    m = vcf("w_zwei", metal=0.4)
    rx = 0.021
    ol = [(-rx, 0.05), (rx, 0.05), (rx, 0.25), (0.039, 0.28), (0.034, 1.12), (0.0, 1.33), (-0.034, 1.12),
          (-0.039, 0.28), (-rx, 0.25)]
    sword_blade("Blade", ol, m, metal("#eef2f6", "#a8b4c4", "#46505e", fuller=(0.32, 1.0, 0.006, "#7a8696")),
                th=0.013, bevel=0.012)
    iron = H("#6e7684")
    gs_hooks(m, iron, 0.255, rx)
    # couro no ricasso (a mão de cima pode subir até aqui na meia-espada)
    lathe("Ricasso", [(0.075, 0.0), (0.075, 0.024), (0.085, 0.027), (0.2, 0.027), (0.21, 0.024), (0.21, 0.0)],
          m, H("#5a3a22"), seg=8, scale=(1.0, 0.55, 1.0))
    tube("Guard", spline([(-0.21, 0, 0.035), (-0.19, 0, 0.06), (-0.1, 0, 0.066), (0, 0, 0.066), (0.1, 0, 0.066),
                          (0.19, 0, 0.06), (0.21, 0, 0.035)], 4), lambda t: 0.015 - 0.004 * abs(2 * t - 1), m, iron,
         sides=6)
    for s in (1, -1):
        orb("GuardEnd%d" % s, m, iron, (0.212 * s, 0, 0.03), 0.017, seg=6)
    crystal("Block", m, iron, (0, 0, 0.062), 0.03, 0.022, 0.02, seg=4, phase=math.pi / 4)
    gs_hilt(m, H("#5a3a22"))
    band("Band", m, iron, -0.11, 0.02, 0.022, seg=8)
    lathe("Pommel", [(-0.37, 0.0), (-0.365, 0.02), (-0.34, 0.034), (-0.31, 0.03), (-0.285, 0.018), (-0.265, 0.0)],
          m, iron, seg=8, smooth=False)
    fin("w_iron_zweihander", 0.0, 1.33)


def build_highland_claymore():
    m = vcf("w_claymore", metal=0.4)
    ol = [(-0.028, 0.06), (0.028, 0.06), (0.04, 0.11), (0.036, 1.08), (0.022, 1.2), (0.0, 1.29), (-0.022, 1.2),
          (-0.036, 1.08), (-0.04, 0.11)]
    sword_blade("Blade", ol, m, metal("#f2f6f8", "#b4c0c8", "#3e4a52", fuller=(0.16, 0.7, 0.007, "#7c8a94")),
                th=0.013, bevel=0.012)
    steel = H("#8a96a4")
    flat("Langet", [(0.0, 0.05), (0.03, 0.08), (0.0, 0.17), (-0.03, 0.08)], m, steel, th=0.0145, bevel=0.004,
         step=0.006, ridge=0.0)
    # quillons inclinados para a lâmina, terminando em quadrifólio (quatro anéis)
    for s in (1, -1):
        tube("Quillon%d" % s, spline([(0.0, 0, 0.058), (0.08 * s, 0, 0.08), (0.15 * s, 0, 0.13),
                                      (0.178 * s, 0, 0.168)], 5), lambda t: 0.015 - 0.005 * t, m, steel, sides=6)
        c = (0.19 * s, 0.185)
        for k in range(4):
            a = math.pi / 4 + k * math.pi / 2
            cel(torus("Foil%d_%d" % (s, k), (c[0] + math.cos(a) * 0.016, c[1] + math.sin(a) * 0.016), 0.012, 0.0045,
                      m, seg=10, sides=5), steel)
    crystal("Block", m, steel, (0, 0, 0.058), 0.028, 0.02, 0.022, seg=4, phase=math.pi / 4)
    gs_hilt(m, H("#2f4a3a"), turns=10)
    for z in (-0.2, -0.05):
        band("Band%.2f" % z, m, steel, z, 0.016, 0.021, seg=8)
    # pomo em roda (disco de pé, no plano da lâmina)
    ob = w_lathe("Pommel", [(-0.012, 0.0), (-0.012, 0.022), (-0.006, 0.036), (0.006, 0.036), (0.012, 0.022),
                            (0.012, 0.0)], m, seg=12, smooth=False)
    put(ob, steel, (0, 0, -0.3), (math.pi / 2, 0, 0))
    fin("w_highland_claymore", 0.0, 1.29)


def build_ember_flamberge():
    m = vcf("w_flamberge", metal=0.3)
    g = vcf("w_flamberge_gem", emit="#ff7a2a", strength=1.3)
    rx = 0.022
    cx = lambda z: 0.0 if z < 0.3 else 0.011 * math.sin((z - 0.3) / 0.13 * 2 * math.pi) * min(1.0, (1.18 - z) / 0.12)
    w = lambda z: 0.038 - 0.008 * max(0.0, (z - 0.3) / 0.85)
    zs = [0.3 + 0.88 * i / 44 for i in range(45)]
    right = [(rx, 0.05), (rx, 0.25), (0.04, 0.28)] + [(cx(z) + w(z), z) for z in zs]
    left = [(-rx, 0.25), (-0.04, 0.28)] + [(cx(z) - w(z), z) for z in zs]
    ol = [(-rx, 0.05)] + right + [(0.0, 1.32)] + list(reversed(left))

    def ember(x, z, c):
        edge = abs(x - cx(z)) / max(w(z), 1e-3)
        heat = smooth01((edge - 0.55) / 0.45) * smooth01((z - 0.3) / 0.3)
        c = mix(c, H("#ff8a3a"), 0.55 * heat)
        return mix(c, H("#ffcf6a"), smooth01((z - 1.05) / 0.25) * 0.6)
    sword_blade("Blade", ol, m, metal("#f4f0ee", "#b8aaa4", "#5a2a1e", cx=cx, extra=ember), th=0.013, bevel=0.012)
    zc = [0.32 + 0.7 * i / 28 for i in range(29)]
    core = [(cx(z) + 0.005 * math.sin(math.pi * (z - 0.32) / 0.7), z) for z in zc]
    core += [(cx(z) - 0.005 * math.sin(math.pi * (z - 0.32) / 0.7), z) for z in reversed(zc[1:-1])]
    flat("Core", core, g, H("#ffb060"), th=0.0142, bevel=0.002, step=0.005, ridge=0.0)   # veio de brasa, ondulado
    iron = H("#3e3434")
    gs_hooks(m, iron, 0.255, rx, reach=0.045)
    # guarda escura com as pontas enroladas em espiral, como brasas
    for s in (1, -1):
        pts = [(0.0, 0, 0.062), (0.1 * s, 0, 0.066), (0.165 * s, 0, 0.055)]
        cxs, czs = 0.165 * s, 0.085
        for k in range(1, 10):
            a = -math.pi / 2 - k * 0.75
            rr = 0.03 * (1 - k / 12)
            pts.append((cxs - math.cos(a) * rr * s, 0, czs + math.sin(a) * rr))
        tube("Guard%d" % s, spline(pts, 3), lambda t: 0.015 * (1 - 0.55 * t), m, iron, sides=6)
    crystal("Block", m, iron, (0, 0, 0.062), 0.03, 0.024, 0.022, seg=4, phase=math.pi / 4)
    gs_hilt(m, H("#7a2218"))
    lathe("PommelCup", [(-0.3, 0.0), (-0.3, 0.014), (-0.285, 0.024), (-0.27, 0.02), (-0.262, 0.0)], m, iron, seg=8,
          smooth=False)
    orb("PommelGem", g, H("#ff5a2a"), (0, 0, -0.32), 0.024, seg=8)
    for k in range(4):
        a = 2 * math.pi * k / 4 + 0.4
        tube("Claw%d" % k, spline([(0.012 * math.cos(a), 0.012 * math.sin(a), -0.295),
                                   (0.027 * math.cos(a), 0.027 * math.sin(a), -0.315),
                                   (0.016 * math.cos(a), 0.016 * math.sin(a), -0.343)], 3),
             lambda t: 0.006 * (1 - t) + 0.0015, m, iron, sides=5)
    fin("w_ember_flamberge", 0.0, 1.32)


def build_eclipse_greatsword():
    m = vcf("w_eclipse", metal=0.3)
    g = vcf("w_eclipse_gem", emit="#b47aff", strength=1.6)
    ol = [(-0.03, 0.06), (0.03, 0.06), (0.056, 0.13), (0.05, 0.92), (0.06, 1.0), (0.036, 1.18), (0.0, 1.36),
          (-0.036, 1.18), (-0.06, 1.0), (-0.05, 0.92), (-0.056, 0.13)]

    def dusk(x, z, c):
        return mix(c, H("#e8c070"), smooth01((abs(x) - 0.028) / 0.012) * 0.8)
    sword_blade("Blade", ol, m, metal("#5a4a7a", "#2c2440", "#120c1c", extra=dusk), th=0.015, bevel=0.014)
    # runas acesas descendo pelo meio da lâmina
    for i, z in enumerate((0.25, 0.42, 0.59, 0.76, 0.93)):
        flat("Rune%d" % i, [(0.0, z - 0.05), (0.01, z), (0.0, z + 0.05), (-0.01, z)], g, H("#d8b0ff"), th=0.0162,
             bevel=0.002, step=0.004, ridge=0.0)
    gold = H("#e8c060")
    # guarda: duas luas crescentes douradas abraçando um eclipse (orbe escuro com anel de luz)
    for s in (1, -1):
        crescent = [(0.02 * s, 0.03), (0.11 * s, 0.05), (0.2 * s, 0.11), (0.23 * s, 0.17), (0.2 * s, 0.13),
                    (0.12 * s, 0.085), (0.02 * s, 0.09)]
        flat("Moon%d" % s, crescent, m, gold, th=0.012, bevel=0.009, step=0.008)
    orb("Eclipse", m, H("#1c1428"), (0, 0, 0.06), 0.044, seg=12)
    cel(torus("Corona", (0, 0.06), 0.048, 0.008, g, seg=16, sides=6), H("#e0c0ff"))
    gs_hilt(m, H("#2a1e3e"), r=0.02)
    for z in (-0.2, -0.06):
        band("Band%.2f" % z, m, gold, z, 0.018, 0.023, seg=8)
    # pomo: lua crescente de pé com uma gema
    flat("PommelMoon", [(0.0, -0.26), (0.045, -0.29), (0.05, -0.34), (0.02, -0.38), (0.028, -0.34), (0.022, -0.305),
                        (-0.022, -0.305), (-0.028, -0.34), (-0.02, -0.38), (-0.05, -0.34), (-0.045, -0.29)],
         m, gold, th=0.012, bevel=0.009, step=0.008)
    orb("PommelGem", g, H("#c890ff"), (0, -0.012, -0.288), 0.014, seg=8)
    fin("w_eclipse_greatsword", 0.0, 1.36)


ARMORY += [("w_iron_zweihander", build_iron_zweihander), ("w_highland_claymore", build_highland_claymore),
           ("w_ember_flamberge", build_ember_flamberge), ("w_eclipse_greatsword", build_eclipse_greatsword)]


WEAPONS.extend(ARMORY)   # ASSETS=weapons gera todas; ASSETS=staves / bows / classic geram só esse grupo
