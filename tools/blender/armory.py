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


_BOW_AURA = []     # (tipo, ponto): partículas do arco mítico (BowAura no jogo lê os empties "Aura_<tipo>_<n>")


def aura(kind, pos):
    _BOW_AURA.append((kind, tuple(pos)))


def bow_export(asset, nock_y):
    loose_parts(asset)
    join_all("Weapon")
    empty("Tip", (0, -0.3, 0))
    empty("Nock", (0, nock_y, 0))
    empty("StringTop", _BOW_STRING[0])
    empty("StringBot", _BOW_STRING[1])
    for i, (kind, pos) in enumerate(_BOW_AURA):
        empty("Aura_%s_%d" % (kind, i), pos)
    _BOW_AURA.clear()
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


def along(d):
    """Rotação que leva +Z da peça para a direção d (peças torneadas e planas apontadas ao longo do braço)."""
    return d.normalized().to_track_quat('Z', 'Y').to_euler()


def limb_dir(pts, z):
    """Direção do braço em z, sempre apontando para a ponta (para cima no de cima, para baixo no de baixo)."""
    s = 1 if z >= 0 else -1
    return limb_at(pts, z + 0.02 * s) - limb_at(pts, z - 0.02 * s)


def build_twig_bow():
    """Arco de Galho (nv 3): um galho torto de verdade, com nós, um broto com folhas e barbante no punho e nas pontas."""
    m = vcf("bw_twig")
    # o torto do galho fica de lado (X, visto de frente); no plano do arco (Y) quase não mexe, para a curva ler como arco
    half, back, n = 0.53, 0.16, 80
    pts = []
    for i in range(n + 1):
        t = -1 + 2 * i / n
        pts.append((0.016 * math.sin(t * 4.1 + 0.7) + 0.005 * math.sin(t * 11.0),
                    back * t * t - 0.02 + 0.0035 * math.sin(t * 7.3), t * half))
    knots = ((0.36, 0.0065), (-0.52, 0.0055), (0.71, 0.004))

    def rad(u):
        t = 2 * u - 1
        r = 0.009 + 0.012 * (1 - abs(t)) ** 0.6
        return r + sum(a * math.exp(-((t - tk) / 0.045) ** 2) for tk, a in knots)
    bark = grain("#80593a", "#5a3c24", freq=5.0, zf=3.0, amt=0.5)      # estrias ao comprido, como casca
    tube("Limbs", pts, rad, m, bark, sides=12, flat=0.84)

    twine, cut, leafc = H("#cdb47e"), H("#d2a874"), H("#7fae4a")
    # punho: barbante enrolado por cima do galho
    gp = limb_at(pts, 0.0)
    # o barbante segue a curva do galho (um cilindro reto deixaria o galho furar o topo do punho)
    gseg = [limb_at(pts, -0.075 + 0.15 * k / 90) for k in range(91)]
    tube("Grip", gseg, lambda u: 0.0222 + 0.0022 * (0.5 + 0.5 * math.cos(2 * math.pi * 13 * u)), m, twine, sides=14)
    # amarras do barbante nas pontas, onde a corda prende, com a sobra pendurada
    for s in (1, -1):
        z = 0.475 * s
        p, d = limb_at(pts, z), limb_dir(pts, z)
        put(wrap("Tie%d" % s, m, None, -0.016, 0.016, 0.0125, turns=3, seg=10), twine, p, along(d))
        tail = [p + Vector((0.006, -0.004, 0)), p + Vector((0.016, -0.008, -0.02 * s)),
                p + Vector((0.02, -0.006, -0.045 * s))]
        tube("Tail%d" % s, spline(tail, 4), lambda u: 0.0028 * (1 - 0.5 * u), m, twine, sides=6)
    # toco de galho cortado no braço de baixo (a ponta clara mostra o corte)
    p = limb_at(pts, -0.3)
    end = p + Vector((-0.042, -0.01, -0.02))
    tube("Stub", spline([p, p + Vector((-0.028, -0.006, -0.012)), end], 3), lambda u: 0.0085 - 0.002 * u, m, bark,
         sides=8)
    lathe("StubCut", [(-0.002, 0.0), (-0.002, 0.0072), (0.002, 0.0068), (0.002, 0.0)], m, cut, seg=10,
          loc=end, rot=along(end - p))
    # broto com duas folhas no braço de cima: nasce de dentro do galho
    p = limb_at(pts, 0.25)
    tw = spline([p, p + Vector((-0.02, -0.004, 0.025)), p + Vector((-0.036, -0.01, 0.06)),
                 p + Vector((-0.042, -0.012, 0.09))], 4)
    tube("Twig", tw, lambda u: 0.0055 * (1 - 0.6 * u), m, bark, sides=8)
    tipp, tipd = Vector(tw[-1]), Vector(tw[-1]) - Vector(tw[-3])
    for k, (ang, L) in enumerate(((0.55, 0.065), (-0.7, 0.05))):
        d = Matrix.Rotation(ang, 3, 'Y') @ tipd
        lf = flat("Leaf%d" % k, leaf_outline(L, 0.017), m, th=0.003, bevel=0.003, step=0.008,
                  bend=lambda c: Vector((c.x, c.y + 0.5 * c.x * c.x - 0.15 * c.z * c.z, c.z)))
        put(lf, leafc, tipp - tipd.normalized() * 0.004, along(d))
    top, bot = Vector(pts[-1]), Vector(pts[0])
    _BOW_STRING[:] = [(top.x, top.y, top.z - 0.06), (bot.x, bot.y, bot.z + 0.06)]
    bow_export("bw_twig_bow", top.y)


def limb_wrap(name, pts, z0, z1, r_of_z, m, col, turns, pad=0.0016, ridge=0.0018, flat=1.0, k=60):
    """Amarra que acompanha a curva do braço entre z0 e z1: raio = braço + folga, com sulcos de `turns` voltas.
    Mesmo `flat` do braço: o quadro do tubo nasce igual (eixo X como referência), então achata para o mesmo lado."""
    seg = [limb_at(pts, z0 + (z1 - z0) * i / k) for i in range(k + 1)]
    return tube(name, seg, lambda u: r_of_z(z0 + (z1 - z0) * u) + pad + ridge * (0.5 + 0.5 * math.cos(2 * math.pi * turns * u)),
                m, col, sides=14, flat=flat)


def build_raptor_bow():
    """Arco de Osso de Raptor (nv 6): duas costelas emendadas com tendão, garras em foice nas pontas, espinhos
    vermelhos da crista nas costas do arco e punho de pele verde com um dente pendurado (cores do raptor do jogo)."""
    m = vcf("bw_raptor")
    half, back, fl = 0.56, 0.15, 0.62
    pts = bow_curve(half, back, recurve=0.02, n=60)
    joints = (0.3, -0.3)

    def r_of_z(z):
        t = z / half
        r = 0.0095 + 0.0125 * (1 - abs(t)) ** 0.7
        return r + sum(0.0045 * math.exp(-((z - j) / 0.022) ** 2) for j in joints)   # nó da emenda das costelas
    bone_l, bone_d = H("#efe4c8"), H("#b8a47c")

    def bone(co):   # marfim que escurece para o punho, com estrias ao comprido
        g = 0.5 + 0.5 * math.sin(math.atan2(co.y, co.x) * 4 + co.z * 5)
        return mix(bone_l, bone_d, 0.55 * (1 - min(abs(co.z) / half, 1)) ** 1.5 + 0.18 * smooth01((g - 0.6) / 0.4))
    tube("Limbs", pts, lambda u: r_of_z(-half + 2 * half * u), m, bone, sides=14, flat=fl)

    skin, sinew, crest, claw = H("#5f7a3e"), H("#7a3424"), H("#b8452a"), H("#3a302a")
    # punho de pele verde, com tendão nas pontas da pele
    limb_wrap("Grip", pts, -0.075, 0.075, r_of_z, m, skin, turns=5, pad=0.0026, ridge=0.0004, flat=fl)
    for s in (1, -1):
        limb_wrap("GripTie%d" % s, pts, 0.072 * s - 0.008, 0.072 * s + 0.008, r_of_z, m, sinew, turns=2, pad=0.0034,
                  ridge=0.001, flat=fl)
        j = joints[0] * s
        limb_wrap("Joint%d" % s, pts, j - 0.03, j + 0.03, r_of_z, m, sinew, turns=6, pad=0.0014, flat=fl)
        # garra em foice na ponta: nasce dentro do braço, segue a direção dele e faz o gancho para a frente (-Y)
        tip, d = limb_at(pts, (half - 0.005) * s), limb_dir(pts, (half - 0.005) * s).normalized()
        hook = [tip - d * 0.03, tip + d * 0.015, tip + d * 0.04 + Vector((0, -0.03, 0)),
                tip + d * 0.045 + Vector((0, -0.07, 0)), tip + d * 0.025 + Vector((0, -0.098, 0))]
        tube("Claw%d" % s, spline(hook, 5), lambda u: 0.0125 * (1 - u) ** 0.8 + 0.0006, m,
             lambda co: claw, sides=10, flat=0.7)
        limb_wrap("TipTie%d" % s, pts, (half - 0.075) * s - 0.012, (half - 0.075) * s + 0.012, r_of_z, m, sinew,
                  turns=3, pad=0.0012, flat=fl)
        # espinhos da crista nas costas do arco (lado -Y), deitados para a ponta como no dorso do raptor
        for k, (z, L) in enumerate(((0.12, 0.042), (0.17, 0.036), (0.215, 0.028))):
            p, dz = limb_at(pts, z * s), limb_dir(pts, z * s).normalized()
            out = Vector((0, -1, 0))
            sp = [p, p + out * L * 0.55 + dz * L * 0.15, p + out * L + dz * L * 0.6]
            tube("Spike%d%d" % (s, k), spline(sp, 4), lambda u: 0.011 * (1 - u) ** 1.3 + 0.0005, m, crest, sides=8,
                 flat=0.4)
    # dente de raptor pendurado no tendão de baixo do punho
    p = limb_at(pts, -0.075)
    cord = [p + Vector((0.006, 0.0, 0.0)), p + Vector((0.024, -0.006, -0.03)), p + Vector((0.03, -0.008, -0.07))]
    tube("Cord", spline(cord, 4), 0.0022, m, sinew, sides=6)
    end = Vector(cord[-1])
    lathe("Tooth", [(0.0, 0.0), (0.0, 0.0075), (0.012, 0.0072), (0.032, 0.0035), (0.046, 0.0)], m, H("#f2ead6"), seg=10,
          loc=end + Vector((0, 0, 0.004)), rot=(math.pi + 0.25, 0, 0))
    top, bot = Vector(pts[-1]), Vector(pts[0])
    _BOW_STRING[:] = [(top.x, top.y, top.z - 0.075), (bot.x, bot.y, bot.z + 0.075)]
    bow_export("bw_raptor_bow", limb_at(pts, half - 0.075).y)


def build_warden_bow():
    """Arco do Vigia (nv 9): recurvo dos guardas da vila. Madeira em camadas (escura por fora, faixa clara na face do
    arqueiro), chapa de ferro rebitada no centro com o escudo da cruz carmesim da guarda, ponteiras de ferro e a fita
    carmesim do tabardo amarrada no punho."""
    m = vcf("bw_warden", metal=0.25)
    half, back, fl = 0.57, 0.17, 0.7
    pts = bow_curve(half, back, recurve=0.05, n=70)

    def r_of_z(z):
        t = min(abs(z) / half, 1.0)     # a tampa da ponta passa um pouco de half
        return 0.0085 + 0.0115 * (1 - t) ** 0.65 + 0.0035 * smooth01((0.19 - abs(z)) / 0.05)   # centro mais grosso
    dark, belly = H("#6b4327"), H("#c99a5e")

    def wood(co):   # laminado: a face do arqueiro (+Y) mostra a faixa clara
        c = limb_at(pts, co.z)
        k = smooth01(((co.y - c.y) / max(r_of_z(co.z) * fl, 1e-4) - 0.35) / 0.3)
        return mix(dark, belly, k)
    tube("Limbs", pts, lambda u: r_of_z(-half + 2 * half * u), m, wood, sides=16, flat=fl)

    iron, leather, crim, cream = H("#8d949e"), H("#4a2e1c"), H("#a32129"), H("#e6dcc4")
    # chapas de ferro na frente do centro (-Y), acima e abaixo da mão, afinando nas pontas
    for s in (1, -1):
        seg = [limb_at(pts, s * (0.068 + 0.11 * i / 40)) for i in range(41)]
        front = [Vector(p) + Vector((0, -r_of_z(p[2]) * fl * 0.72, 0)) for p in seg]
        tube("Plate%d" % s, front, lambda u: 0.0175 * min(1.0, min(u, 1 - u) / 0.12) ** 0.5 + 0.0004, m, iron,
             sides=14, flat=0.3)
    for z in (-0.155, -0.088, 0.155):
        p = limb_at(pts, z)
        orb("Rivet%.2f" % z, m, H("#c4cad2"), (p.x, p.y - r_of_z(z) * fl * 0.72 - 0.0042, z), 0.0034, seg=8)
    for s in (1, -1):
        limb_wrap("Band%d" % s, pts, 0.183 * s - 0.009, 0.183 * s + 0.009, r_of_z, m, iron, turns=1, pad=0.0016,
                  ridge=0.0006, flat=fl)
        # ponteira de ferro com botão na ponta (a corda prende logo abaixo do botão)
        limb_wrap("TipCap%d" % s, pts, (half - 0.05) * s if s > 0 else -half + 0.002, half - 0.002 if s > 0 else
                  -(half - 0.05), r_of_z, m, iron, turns=2, pad=0.0012, ridge=0.0007, flat=fl)
        tip = limb_at(pts, (half - 0.002) * s)
        orb("TipKnob%d" % s, m, iron, (tip.x, tip.y, tip.z + 0.003 * s), 0.0058, seg=10)
    # punho de couro
    limb_wrap("Grip", pts, -0.065, 0.065, r_of_z, m, leather, turns=9, pad=0.0018, ridge=0.0009, flat=fl)
    # escudo da guarda acima da mão: aro de ferro, esmalte creme e a cruz carmesim
    p = limb_at(pts, 0.112)
    face = p.y - r_of_z(0.112) * fl * 0.72 - 0.003
    lathe("Badge", [(0.0, 0.0), (0.0, 0.0175), (0.004, 0.0175), (0.006, 0.015), (0.006, 0.0)], m, iron, seg=20,
          loc=(p.x, face + 0.002, p.z), rot=(math.pi / 2, 0, 0))
    lathe("Enamel", [(0.0, 0.0), (0.0, 0.0138), (0.0064, 0.0138), (0.0064, 0.0)], m, cream, seg=20,
          loc=(p.x, face + 0.002, p.z), rot=(math.pi / 2, 0, 0))
    a, b = 0.0105, 0.0032
    cross = [(-b, -a), (b, -a), (b, -b), (a, -b), (a, b), (b, b), (b, a), (-b, a), (-b, b), (-a, b), (-a, -b), (-b, -b)]
    flat("Cross", cross, m, crim, th=0.0016, bevel=0.0008, step=0.004, loc=(p.x, face - 0.0052, p.z))
    # fita carmesim amarrada embaixo do punho, com as duas pontas caídas
    limb_wrap("RibbonTie", pts, -0.08, -0.068, r_of_z, m, crim, turns=1, pad=0.0026, ridge=0.0005, flat=fl)
    p = limb_at(pts, -0.074)
    for k, (dx, L) in enumerate(((0.01, 0.13), (-0.006, 0.1))):
        rib = [p + Vector((dx * 0.4, -0.01, 0)), p + Vector((dx, -0.02, -0.03)), p + Vector((dx * 1.6, -0.018, -0.07)),
               p + Vector((dx * 1.2, -0.022, -L))]
        tube("Ribbon%d" % k, spline(rib, 5), 0.0085, m, crim, sides=10, flat=0.18)
    top, bot = Vector(pts[-1]), Vector(pts[0])
    _BOW_STRING[:] = [(top.x, top.y, top.z - 0.035), (bot.x, bot.y, bot.z + 0.035)]
    bow_export("bw_warden_bow", limb_at(pts, half - 0.035).y)



def limb_helix(name, pts, z0, z1, r_of_z, turns, phase, m, col, fl, r=0.0013, k=120):
    """Fio enrolado em espiral em volta do braço (encostado na superfície), de z0 a z1."""
    seg = []
    for i in range(k + 1):
        z = z0 + (z1 - z0) * i / k
        c, a = limb_at(pts, z), phase + 2 * math.pi * turns * i / k
        rr = r_of_z(z) + r * 0.4
        seg.append(c + Vector((math.cos(a) * rr, math.sin(a) * rr * fl, 0)))
    return tube(name, seg, r, m, col, sides=6)


def build_silk_bow():
    """Arco de Seda Tecelã (nv 14): braços de quitina roxa em segmentos de pata de aranha, pontas de presa, seda
    enrolada nos braços, punho de casulo com os seis olhos vermelhos (sem brilho: no tamanho do jogo são um pixel) e a marca em divisas da Tecelã do jogo, e duas
    patinhas no centro com um leque de teia preso ao braço."""
    m = vcf("bw_silk", metal=0.15)
    half, back, fl = 0.56, 0.15, 0.78
    pts = bow_curve(half, back, recurve=0.025, n=80)
    joints = (0.2, 0.38, -0.2, -0.38)

    def r_of_z(z):
        t = min(abs(z) / half, 1.0)
        r = 0.0075 + 0.0115 * (1 - t) ** 0.7
        return r + sum(0.0032 * math.exp(-((z - j) / 0.014) ** 2) for j in joints)
    chit, chit_l, chit_d = H("#3b2f3e"), H("#6a5672"), H("#2a212d")
    silk, mark, fang = H("#f2eee6"), H("#c23b4a"), H("#efe6d0")

    def chitin(co):   # segmento escuro que clareia nas juntas, com brilho ao comprido no dorso
        j = max(math.exp(-((co.z - jz) / 0.02) ** 2) for jz in joints)
        return mix(mix(chit_d, chit, 0.6 + 0.4 * smooth01((0.2 - abs(co.z) + 0.2) / 0.4)), chit_l, 0.85 * j)
    tube("Limbs", pts, lambda u: r_of_z(-half + 2 * half * u), m, chitin, sides=14, flat=fl)

    for s in (1, -1):
        # presa de marfim na ponta, curvada para a frente
        tip, d = limb_at(pts, (half - 0.004) * s), limb_dir(pts, (half - 0.004) * s).normalized()
        hook = [tip - d * 0.02, tip + d * 0.02, tip + d * 0.045 + Vector((0, -0.012, 0)),
                tip + d * 0.055 + Vector((0, -0.032, 0))]
        tube("Fang%d" % s, spline(hook, 5), lambda u: 0.0085 * (1 - u) ** 0.9 + 0.0005, m, fang, sides=10, flat=0.8)
        limb_wrap("TipSilk%d" % s, pts, (half - 0.014) * s - 0.011, (half - 0.014) * s + 0.011, r_of_z, m, silk,
                  turns=4, pad=0.0008, ridge=0.0009, flat=fl)
        # dois fios de seda cruzados em espiral no meio de cada braço
        z0, z1 = sorted((0.08 * s, 0.5 * s))
        for k, (tw, ph) in enumerate(((3.5, 0.0), (-3.5, 1.3))):
            limb_helix("Silk%d%d" % (s, k), pts, z0, z1, r_of_z, tw, ph, m, silk, fl)
        # patinha de aranha saindo da frente do centro, com um leque de teia preso ao braço
        base = limb_at(pts, 0.15 * s)
        out = Vector((0, -1, 0.55 * s)).normalized()
        knee = base + out * 0.05 + Vector((0, 0, 0.012 * s))
        foot = knee + Vector((0, -0.012, 0.055 * s))
        tube("Leg%d" % s, spline([base, base + out * 0.03, knee, foot], 4), lambda u: 0.0062 * (1 - 0.6 * u), m,
             chitin, sides=10)
        orb("Knee%d" % s, m, chit_l, (knee.x, knee.y, knee.z), 0.0065, seg=10)
        anchors = [limb_at(pts, s * z) for z in (0.215, 0.26, 0.305)]
        for a_i, a in enumerate(anchors):
            tube("Web%d%d" % (s, a_i), [Vector(foot) + (Vector(a) - Vector(foot)) * 0.02, Vector(a)], 0.0011, m, silk,
                 sides=5)
        for t_i, t in enumerate((0.35, 0.65)):
            ring = [Vector(foot).lerp(Vector(a), t) for a in [knee] + anchors]
            tube("WebArc%d%d" % (s, t_i), spline(ring, 3), 0.001, m, silk, sides=5)
    # casulo de seda no punho (encaroçado, como fio enrolado sem capricho)
    gseg = [limb_at(pts, -0.07 + 0.14 * i / 90) for i in range(91)]
    tube("Cocoon", gseg, lambda u: r_of_z(-0.07 + 0.14 * u) + 0.0032 + 0.0013 * math.sin(u * 41) * math.sin(u * 13 + 1),
         m, silk, sides=14, flat=fl)
    # seis olhos vermelhos acima da mão: o par grande embaixo, dois pares menores em cima
    p = limb_at(pts, 0.122)
    face = p.y - r_of_z(0.122) * fl
    for x, z, r in ((-0.0062, 0.114, 0.0046), (0.0062, 0.114, 0.0046), (-0.0088, 0.126, 0.0031),
                    (0.0088, 0.126, 0.0031), (-0.0035, 0.132, 0.0027), (0.0035, 0.132, 0.0027)):
        orb("Eye%.3f%.3f" % (x, z), m, H("#a8141f"), (p.x + x, face + r * 0.25, z), r, seg=10)
    # marca vermelha em divisas abaixo da mão
    for k, z in enumerate((-0.088, -0.104)):
        q = limb_at(pts, z)
        chev = [(-0.011, 0.004), (0.0, -0.004), (0.011, 0.004), (0.011, 0.0085), (0.0, 0.0005), (-0.011, 0.0085)]
        flat("Chevron%d" % k, chev, m, mark, th=0.0018, bevel=0.0008, step=0.004,
             loc=(q.x, q.y - r_of_z(z) * fl - 0.0002, z))
    top, bot = Vector(pts[-1]), Vector(pts[0])
    _BOW_STRING[:] = [(top.x, top.y, top.z - 0.014), (bot.x, bot.y, bot.z + 0.014)]
    bow_export("bw_silk_bow", limb_at(pts, half - 0.014).y)



def build_frostfang_bow():
    """Uivo da Geada (nv 17): madeira azul-ardósia com a geada subindo para as pontas, presas do Alfa nas pontas,
    cristais de gelo nas costas dos braços (como no dorso do lobo do jogo), punho de pele de lobo com tufos e a cabeça
    de lobo na frente do centro, com olhos de gelo."""
    m = vcf("bw_frostfang", metal=0.1)
    ice = vcf("bw_frostfang_ice", emit="#3cc8ff", strength=0.7)   # só os olhos da cabeça uivando
    half, back, fl = 0.57, 0.16, 0.74
    pts = bow_curve(half, back, recurve=0.03, n=80)

    def r_of_z(z):
        t = min(abs(z) / half, 1.0)
        return 0.009 + 0.012 * (1 - t) ** 0.65 + 0.003 * smooth01((0.15 - abs(z)) / 0.05)
    wood_c, wood_d, frost = H("#4f6378"), H("#33414f"), H("#d6e6f2")

    def wood(co):   # ardósia com estrias; a geada clareia do meio do braço até a ponta
        g = 0.5 + 0.5 * math.sin(math.atan2(co.y, co.x) * 5 + co.z * 4)
        base = mix(wood_c, wood_d, 0.45 * smooth01((g - 0.5) / 0.5))
        return mix(base, frost, 0.8 * smooth01((abs(co.z) - 0.33) / 0.22))
    tube("Limbs", pts, lambda u: r_of_z(-half + 2 * half * u), m, wood, sides=16, flat=fl)

    fang, leather, fur, fur_l = H("#f2f4f6"), H("#2c3440"), H("#7c93a8"), H("#dce7ef")
    for s in (1, -1):
        # presa do Alfa: cone curvo e grosso, apontando para a frente, amarrado com couro escuro
        tip, d = limb_at(pts, (half - 0.004) * s), limb_dir(pts, (half - 0.004) * s).normalized()
        hook = [tip - d * 0.025, tip + d * 0.025, tip + d * 0.055 + Vector((0, -0.02, 0)),
                tip + d * 0.065 + Vector((0, -0.048, 0))]
        tube("Fang%d" % s, spline(hook, 6), lambda u: 0.0145 * (1 - u) ** 0.75 + 0.0006, m,
             lambda co: fang, sides=12, flat=0.85)
        limb_wrap("FangTie%d" % s, pts, (half - 0.016) * s - 0.013, (half - 0.016) * s + 0.013, r_of_z, m, leather,
                  turns=4, pad=0.0016, ridge=0.0009, flat=fl)
        # tufos de lascas de gelo nas costas do braço (-Y), em leque e inclinados para a ponta. Sem brilho: no toon
        # do jogo a emissão estoura para branco e o gelo vira espinho; azul pintado lê como gelo
        for k, (z, n_c, size) in enumerate(((0.235, 5, 1.35), (0.37, 4, 1.05))):
            p, dz = limb_at(pts, z * s), limb_dir(pts, z * s).normalized()
            face = p + Vector((0, -r_of_z(z) * fl * 0.55, 0))
            for c in range(n_c):
                f = (c - (n_c - 1) / 2) / max((n_c - 1) / 2, 1)          # -1..1 através do leque
                tilt = Vector((0.75 * f, -1, 0)).normalized().lerp(dz, 0.28 + 0.12 * abs(f)).normalized()
                h = 0.04 * size * (1 - 0.38 * abs(f))
                ob = crystal("Ice%d%d%d" % (s, k, c), m, None, (0, 0, 0), 0.0068 * size * (1 - 0.25 * abs(f)), h, 0.012,
                             seg=5, phase=0.5 * c)
                put(ob, H("#5ab8e6") if c % 2 else H("#8fd6f4"), face + Vector((0.006 * f, 0, 0.004 * f * s)),
                    along(tilt))
    # punho de pele de lobo, com a gola de tufos claros nas duas pontas
    gseg = [limb_at(pts, -0.07 + 0.14 * i / 90) for i in range(91)]
    tube("Pelt", gseg, lambda u: r_of_z(-0.07 + 0.14 * u) + 0.0036,
         m, fur, sides=14, flat=fl)   # liso: relevo pequeno vira blocos no sombreado de 3 tons
    for s in (1, -1):
        z = 0.072 * s
        p, dz = limb_at(pts, z), limb_dir(pts, z).normalized() * s
        for k in range(12):
            a = 2 * math.pi * k / 12 + 0.2 * s
            out = Vector((math.cos(a), math.sin(a) * fl, 0))
            tuft = [p + out * r_of_z(z) * 0.7, p + out * (r_of_z(z) + 0.0045) + dz * 0.006 * s,
                    p + out * (r_of_z(z) + 0.006) + dz * 0.017 * s]
            tube("Tuft%d%d" % (s, k), spline(tuft, 3), lambda u: 0.0042 * (1 - u) ** 0.7 + 0.0004, m, H("#9db0c2"), sides=6,
                 flat=0.55)
    # cabeça de lobo uivando, de perfil, dos dois lados do centro (é o lado que o jogo mostra): focinho para o alto,
    # virado para a frente (-Y); placa de prata com olho de gelo
    zc, sc = 0.122, 1.3
    p = limb_at(pts, zc)
    howl = [(x * 0.01, z * 0.01) for x, z in (
        (-1.2, -1.4), (-1.4, 0.4), (-1.0, 1.6), (-1.1, 2.0), (-1.9, 3.4), (-0.3, 2.3), (0.3, 2.8), (1.2, 4.0),
        (1.9, 4.9), (2.25, 4.65), (1.7, 3.9), (2.25, 3.65), (1.4, 3.05), (0.9, 1.6), (0.8, -0.2), (0.7, -1.4))]
    rw = r_of_z(zc)
    for s in (1, -1):
        ob = flat("Howl%d" % s, [(x * sc, z * sc) for x, z in howl], m, H("#55697f"), th=0.0045, bevel=0.002,
                  step=0.004)
        put(ob, H("#55697f"), (p.x + s * (rw * 0.92), p.y - 0.002, zc), (0, 0, -math.pi / 2))
        orb("HowlEye%d" % s, ice, H("#3fb6ea"), (p.x + s * (rw * 0.92 + 0.0035), p.y - 0.002 - 0.006 * sc,
                                                 zc + 0.028 * sc),
            0.0026, seg=8)
    top, bot = Vector(pts[-1]), Vector(pts[0])
    _BOW_STRING[:] = [(top.x, top.y, top.z - 0.016), (bot.x, bot.y, bot.z + 0.016)]
    bow_export("bw_frostfang_bow", limb_at(pts, half - 0.016).y)



def build_lantern_bow():
    """Arco Lanterna (nv 20): arco dos kobolds das minas. Madeira escura de escora com cintas de latão rebitadas,
    lanterna de latão acesa na frente do centro, duas dinamites com pavio amarradas no braço de baixo e ponteiras de
    latão com bico de picareta."""
    m = vcf("bw_lantern", metal=0.3)
    glow = vcf("bw_lantern_glow", emit="#ffb347", strength=2.2)
    half, back, fl = 0.56, 0.15, 0.72
    pts = bow_curve(half, back, recurve=0.02, n=80)

    def r_of_z(z):
        t = min(abs(z) / half, 1.0)
        return 0.0095 + 0.0125 * (1 - t) ** 0.65 + 0.003 * smooth01((0.2 - abs(z)) / 0.05)
    wood = grain("#5c4232", "#3c2a1e", freq=4.0, zf=3.5, amt=0.55)
    tube("Limbs", pts, lambda u: r_of_z(-half + 2 * half * u), m, wood, sides=16, flat=fl)

    brass, brass_d, iron, rope = H("#c8963c"), H("#8a6224"), H("#5e5a56"), H("#b89a62")
    for s in (1, -1):
        for z in (0.21, 0.33):
            zz = z * s
            limb_wrap("Strap%d%.2f" % (s, z), pts, zz - 0.011, zz + 0.011, r_of_z, m, brass, turns=1, pad=0.0016,
                      ridge=0.0005, flat=fl)
            p = limb_at(pts, zz)
            orb("Rivet%d%.2f" % (s, z), m, H("#e8c070"), (p.x, p.y - r_of_z(zz) * fl - 0.0028, zz), 0.0028, seg=8)
        # ponteira de latão com o bico de picareta para a frente (-Y)
        limb_wrap("TipCap%d" % s, pts, (half - 0.04) * s if s > 0 else -half + 0.002,
                  half - 0.002 if s > 0 else -(half - 0.04), r_of_z, m, brass, turns=2, pad=0.0014, ridge=0.0006,
                  flat=fl)
        tip = limb_at(pts, (half - 0.016) * s)
        d = limb_dir(pts, (half - 0.016) * s).normalized()
        pick = [tip + Vector((0, 0.004, 0)), tip + Vector((0, -0.018, 0)) + d * 0.004,
                tip + Vector((0, -0.04, 0)) + d * 0.014]
        tube("Pick%d" % s, spline(pick, 4), lambda u: 0.0072 * (1 - u) ** 0.85 + 0.0005, m, iron, sides=8, flat=0.7)
    # punho de corda
    limb_wrap("Grip", pts, -0.07, 0.07, r_of_z, m, rope, turns=14, pad=0.0022, ridge=0.0006, flat=fl)

    # lanterna na frente, acima da mão: base e telhado de latão, vidro aceso, quatro hastes e a argola em cima
    zl, zh = 0.112, 0.172
    pa = limb_at(pts, (zl + zh) / 2)
    cx, cy = pa.x, pa.y - r_of_z((zl + zh) / 2) * fl - 0.026
    lathe("LampBase", [(0.0, 0.0), (0.0, 0.017), (0.004, 0.018), (0.008, 0.015), (0.008, 0.0)], m, brass, seg=16,
          loc=(cx, cy, zl))
    lathe("LampGlass", [(0.0, 0.0), (0.0, 0.0115), (0.022, 0.013), (0.044, 0.0115), (0.044, 0.0)], glow,
          H("#ffc25a"), seg=16, loc=(cx, cy, zl + 0.006))
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        bx, by = cx + 0.0142 * math.cos(a), cy + 0.0142 * math.sin(a)
        tube("LampBar%d" % k, [(bx, by, zl + 0.006), (bx, by, zl + 0.05)], 0.0019, m, brass_d, sides=6)
    lathe("LampRoof", [(0.0, 0.0), (0.0, 0.0185), (0.004, 0.0185), (0.016, 0.006), (0.019, 0.0)], m, brass, seg=16,
          loc=(cx, cy, zl + 0.048))
    tube("LampRing", [(cx + 0.006 * math.cos(a), cy, zl + 0.071 + 0.006 * math.sin(a)) for a in
                      [2 * math.pi * i / 16 for i in range(17)]], 0.0016, m, brass_d, sides=6)
    # dois braços de latão prendem a lanterna no arco
    for z in (zl + 0.008, zl + 0.05):
        p = limb_at(pts, z)
        tube("LampArm%.3f" % z, [(p.x, p.y, z), (cx, cy + 0.008, z)], 0.0028, m, brass_d, sides=8)

    # duas dinamites amarradas na frente do braço de baixo, com os pavios enrolados
    sr, zt, zb = 0.0078, -0.12, -0.2
    pm = limb_at(pts, (zt + zb) / 2)
    rl = r_of_z((zt + zb) / 2)
    y_st = pm.y - rl * fl - sr + 0.001
    red, red_d = H("#b8382a"), H("#7a2418")
    for k, x in enumerate((-sr, sr)):
        lathe("Dyn%d" % k, [(zb, 0.0), (zb, sr), (zt, sr), (zt, 0.0)], m,
              lambda co: red_d if co.z > zt - 0.006 or co.z < zb + 0.006 else red, seg=12, loc=(pm.x + x, y_st, 0))
        fuse = [(pm.x + x, y_st, zt - 0.004), (pm.x + x * 1.4, y_st - 0.004, zt + 0.012),
                (pm.x + x * 2.2, y_st - 0.012, zt + 0.02), (pm.x + x * 2.6, y_st - 0.02, zt + 0.012)]
        tube("Fuse%d" % k, spline(fuse, 4), 0.0015, m, H("#2a2420"), sides=5)
    for k, z in enumerate((zt - 0.017, zb + 0.017)):
        p = limb_at(pts, z)
        rz = r_of_z(z)
        front, backy = p.y - rz * fl - 2 * sr, p.y + rz * fl
        ym, ry, rx = (front + backy) / 2, (backy - front) / 2 + 0.0016, max(rz, 2 * sr) + 0.0016
        loop = [(p.x + rx * math.cos(a), ym + ry * math.sin(a), z) for a in [2 * math.pi * i / 24 for i in range(25)]]
        tube("DynStrap%d" % k, loop, 0.0028, m, H("#5a3a20"), sides=6)
    top, bot = Vector(pts[-1]), Vector(pts[0])
    _BOW_STRING[:] = [(top.x, top.y, top.z - 0.03), (bot.x, bot.y, bot.z + 0.03)]
    bow_export("bw_lantern_bow", limb_at(pts, half - 0.03).y)



def build_crystal_bow():
    """Arco de Cristal Cantante (nv 26): centro de pedra do Golem de Cristal (cores do golem do jogo), braços de cristal
    facetado que clareiam até a ponta, tufos de cristal nascendo da pedra, um cristal grande cravado na frente e as
    pontas abertas em duas hastes, como um diapasão (a corda que canta)."""
    m = vcf("bw_crystal", metal=0.05)
    half, back, fl = 0.57, 0.15, 0.8
    pts = bow_curve(half, back, recurve=0.02, n=80)
    stone_z = 0.165

    def r_of_z(z):
        t = min(abs(z) / half, 1.0)
        return 0.008 + 0.0115 * (1 - t) ** 0.7
    deep, mid, pale = H("#1b78b8"), H("#3fd2f2"), H("#bdf2ff")

    def crys(co):   # azul fundo na raiz, ciano no meio, quase branco na ponta
        t = min(abs(co.z) / half, 1.0)
        return ramp([(0.25, deep), (0.6, mid), (1.0, pale)], t)
    # braços de cristal: seis faces sem suavizar (faceta de cristal); de cada lado nascem de dentro da pedra
    for s in (1, -1):
        seg = [p for p in pts if p[2] * s > stone_z - 0.04]
        if s < 0:
            seg = seg[::-1]
        tube("Limb%d" % s, seg, lambda u, s=s, seg=seg: r_of_z(seg[0][2] + (seg[-1][2] - seg[0][2]) * u), m, crys,
             sides=6, flat=fl, smooth=False, phase=0.5)
    # centro de pedra do golem, encaroçado e facetado
    rock, rock_d, rock_l = H("#5e5a58"), H("#3a3634"), H("#86807a")
    cseg = [limb_at(pts, -stone_z + 2 * stone_z * i / 60) for i in range(61)]
    tube("Stone", cseg, lambda u: 0.0235 + 0.0035 * math.sin(u * 23 + 1) * math.sin(u * 7) -
         0.006 * smooth01((abs(u - 0.5) - 0.42) / 0.08), m,
         lambda co: mix(rock, rock_l, 0.5 + 0.5 * math.sin(co.z * 40 + co.x * 90)), sides=9, flat=0.9, smooth=False)
    limb_wrap("Grip", pts, -0.062, 0.062, lambda z: 0.0235, m, H("#2e2a2a"), turns=8, pad=0.0035, ridge=0.0008,
              flat=0.9)
    # cristal grande cravado na frente, acima da mão, num aro de pedra
    zc = 0.112
    p = limb_at(pts, zc)
    fy = p.y - 0.022
    lathe("GemSeat", [(0.0, 0.0), (0.0, 0.016), (0.006, 0.015), (0.01, 0.011), (0.01, 0.0)], m, rock_d, seg=8,
          loc=(p.x, p.y - 0.012, zc), rot=(math.pi / 2, 0, 0))
    ob = crystal("Gem", m, None, (0, 0, 0), 0.0105, 0.024, 0.008, seg=6, mid=0.006)
    put(ob, mid, (p.x, fy, zc), (math.pi / 2, 0, 0))
    # tufos de cristal nascendo da pedra nas duas pontas do centro, abertos para fora e para a frente
    for s in (1, -1):
        base = limb_at(pts, (stone_z - 0.02) * s)
        d = limb_dir(pts, (stone_z - 0.02) * s).normalized()
        for k, (ax, ay, h, r) in enumerate(((0.9, -0.5, 0.05, 0.0075), (-0.8, -0.6, 0.04, 0.0065), (0.2, -1.0, 0.058, 0.008),
                                             (-0.3, 0.5, 0.032, 0.006))):
            dirv = (Vector((ax, ay, 0)).normalized() * 0.75 + d * 0.55).normalized()
            h, r = h * 1.4, r * 1.35
            ob = crystal("Shard%d%d" % (s, k), m, None, (0, 0, 0), r, h, 0.014, seg=6, mid=h * 0.18, phase=0.4 * k)
            put(ob, deep if k % 2 else mid, base + Vector((ax, ay, 0)).normalized() * 0.01, along(dirv))
        # diapasão: a ponta se abre em duas hastes no plano do arco (frente e trás), presas por um colar de pedra
        tip = limb_at(pts, (half - 0.03) * s)
        dt = limb_dir(pts, (half - 0.03) * s).normalized()
        side = Vector((0, 1, 0)) - dt * dt.y
        side.normalize()
        for k, sg in enumerate((1, -1)):
            prong = [tip - dt * 0.01, tip + side * sg * 0.004 + dt * 0.012, tip + side * sg * 0.0085 + dt * 0.03,
                     tip + side * sg * 0.009 + dt * 0.062]
            tube("Prong%d%d" % (s, k), spline(prong, 4), lambda u: 0.0052 * (1 - 0.45 * u), m, pale, sides=6,
                 smooth=False)
        limb_wrap("Collar%d" % s, pts, (half - 0.03) * s - 0.009, (half - 0.03) * s + 0.009, r_of_z, m, rock_d,
                  turns=1, pad=0.0022, ridge=0.0004, flat=fl)
    top_t, bot_t = limb_at(pts, half - 0.03), limb_at(pts, -(half - 0.03))
    _BOW_STRING[:] = [(top_t.x, top_t.y, top_t.z), (bot_t.x, bot_t.y, bot_t.z)]
    bow_export("bw_crystal_bow", top_t.y)



def build_ossuary_bow():
    """Arco Ossário (nv 29, épico): a espinha de um Cavaleiro Esqueleto, vértebra por vértebra sobre um cordão escuro,
    com o crânio de olhos verdes na frente do centro, pares de costelas curvadas para a frente nas pontas do centro,
    punho de couro com placas de aço enferrujado, estandarte vermelho rasgado e ganchos de costela nas pontas
    (cores do esqueleto do jogo)."""
    m = vcf("bw_ossuary", metal=0.2)
    half, back, fl = 0.57, 0.16, 0.85
    pts = bow_curve(half, back, recurve=0.03, n=90)
    bone, bone_d, bone_l = H("#e2d9bc"), H("#a99e7e"), H("#f5efdc")
    dark, steel, rust, red, red_d = H("#2e2838"), H("#6c707a"), H("#6a5648"), H("#6e211c"), H("#431411")
    green = H("#45f094")

    def core_r(z):
        t = min(abs(z) / half, 1.0)
        return 0.0058 + 0.0065 * (1 - t)
    # cordão escuro que liga as vértebras (a espinha não fica solta)
    tube("Cord", pts, lambda u: core_r(-half + 2 * half * u), m, dark, sides=10, flat=fl)

    # vértebras: corpo torneado, processo espinhoso para trás do arco (-Y) e dois transversos para os lados
    for s in (1, -1):
        z = 0.185
        k = 0
        while z < half - 0.05:
            t = z / half
            rv, hv = 0.0165 * (1 - 0.55 * t), 0.022 * (1 - 0.45 * t)
            p, d = limb_at(pts, z * s), limb_dir(pts, z * s).normalized()
            body = lathe("Vert%d%d" % (s, k), [(-hv / 2, 0.0), (-hv / 2, rv * 0.8), (-hv / 2 + hv * 0.2, rv),
                                              (hv / 2 - hv * 0.2, rv), (hv / 2, rv * 0.8), (hv / 2, 0.0)], m, None, seg=12)
            put(body, lambda co: mix(bone_d, bone, 0.5 + 0.5 * math.cos(co.z * 900)), p, along(d))
            back_v = Vector((0, -1, 0)) - d * d.y
            back_v.normalize()
            spine = [p + back_v * rv * 0.5, p + back_v * (rv + 0.012 * (1 - 0.4 * t)) + d * 0.004,
                     p + back_v * (rv + 0.02 * (1 - 0.4 * t)) + d * 0.012]
            tube("Spinous%d%d" % (s, k), spline(spine, 3), lambda u: 0.0052 * (1 - u) ** 0.8 + 0.0006, m, bone_l,
                 sides=6, flat=0.45)
            for sx in (1, -1):
                side = Vector((sx, 0, 0))
                tr = [p + side * rv * 0.6, p + side * (rv + 0.006) + back_v * 0.002, p + side * (rv + 0.01) + back_v * 0.004]
                tube("Trans%d%d%d" % (s, k, sx), spline(tr, 3), lambda u: 0.0038 * (1 - 0.5 * u), m, bone, sides=6)
            z += hv + 0.0075
            k += 1
        # gancho de costela na ponta, curvado para a frente, com anel de aço
        tip, d = limb_at(pts, (half - 0.035) * s), limb_dir(pts, (half - 0.035) * s).normalized()
        hook = [tip - d * 0.015, tip + d * 0.025, tip + d * 0.05 + Vector((0, -0.02, 0)),
                tip + d * 0.055 + Vector((0, -0.05, 0)), tip + d * 0.042 + Vector((0, -0.07, 0))]
        tube("Hook%d" % s, spline(hook, 5), lambda u: 0.0095 * (1 - u) ** 0.8 + 0.0006, m, bone, sides=10, flat=0.75)
        limb_wrap("HookRing%d" % s, pts, (half - 0.035) * s - 0.009, (half - 0.035) * s + 0.009, core_r, m, steel,
                  turns=1, pad=0.0045, ridge=0.0006, flat=fl)
        # costelas que abraçam o centro: saem dos lados e curvam para a frente
        base = limb_at(pts, 0.17 * s)
        for sx in (1, -1):
            rib = [base + Vector((sx * 0.006, 0, 0)), base + Vector((sx * 0.026, -0.004, 0.006 * s)),
                   base + Vector((sx * 0.034, -0.026, 0.016 * s)), base + Vector((sx * 0.02, -0.046, 0.026 * s))]
            tube("Rib%d%d" % (s, sx), spline(rib, 5), lambda u: 0.0058 * (1 - 0.55 * u), m, bone, sides=8, flat=0.6)

    # centro: núcleo de aço com placas rebitadas e punho de couro
    def riser_r(z):
        return 0.0205
    rseg = [limb_at(pts, -0.19 + 0.38 * i / 60) for i in range(61)]
    tube("Riser", rseg, lambda u: 0.0175 + 0.004 * smooth01((0.19 - abs(-0.19 + 0.38 * u)) / 0.04), m,
         lambda co: mix(rust, steel, 0.5 + 0.5 * math.sin(co.z * 70 + co.x * 140)), sides=14, flat=fl)
    limb_wrap("Grip", pts, -0.065, 0.065, riser_r, m, H("#3a2a20"), turns=10, pad=0.0012, ridge=0.0009, flat=fl)
    for s in (1, -1):
        limb_wrap("GripBand%d" % s, pts, 0.072 * s - 0.006, 0.072 * s + 0.006, riser_r, m, steel, turns=1,
                  pad=0.003, ridge=0.0005, flat=fl)
        p = limb_at(pts, 0.16 * s)
        for sx in (1, -1):
            orb("Rivet%d%d" % (s, sx), m, H("#cfd3da"), (p.x + sx * 0.012, p.y - 0.016, p.z), 0.0028, seg=8)

    # crânio na frente, acima da mão, olhando para o alvo
    zc = 0.118
    p = limb_at(pts, zc)
    cy = p.y - 0.026
    orb("Cranium", m, bone, (p.x, cy + 0.004, zc + 0.004), 0.0185, seg=14, sq=1.05)
    lathe("Muzzle", [(0.0, 0.0), (0.0, 0.0125), (0.011, 0.0115), (0.02, 0.0085), (0.024, 0.0)], m, bone_d, seg=12,
          loc=(p.x, cy - 0.006, zc - 0.008), rot=(math.pi / 2 + 0.35, 0, 0))
    for sx in (1, -1):
        orb("Socket%d" % sx, m, H("#15110e"), (p.x + sx * 0.0072, cy - 0.0125, zc + 0.002), 0.0062, seg=10)
        orb("EyeGlow%d" % sx, m, green, (p.x + sx * 0.0072, cy - 0.0158, zc + 0.002), 0.0032, seg=8)
    orb("Nose", m, H("#15110e"), (p.x, cy - 0.0135, zc - 0.006), 0.0032, seg=8)
    for k in range(5):   # dentes de cima na borda do focinho
        x = (k - 2) * 0.0036
        orb("Tooth%d" % k, m, bone_l, (p.x + x, cy - 0.0158, zc - 0.0155), 0.0019, seg=6)
    # estandarte vermelho rasgado, preso no anel de baixo do punho
    p = limb_at(pts, -0.075)
    flag = [(-0.016, 0.0), (0.016, 0.0), (0.018, -0.07), (0.009, -0.058), (0.004, -0.085), (-0.004, -0.064),
            (-0.012, -0.09), (-0.017, -0.06)]
    ob = flat("Banner", flag, m, None, th=0.0028, bevel=0.0012, step=0.006,
              bend=lambda c: Vector((c.x, c.y - 0.12 * c.z * c.z - 0.004 * math.sin(c.x * 200), c.z)))
    put(ob, lambda co: red if (co.z - p.z) > -0.07 else red_d, (p.x, p.y - 0.021, p.z))
    top_t, bot_t = limb_at(pts, half - 0.035), limb_at(pts, -(half - 0.035))
    _BOW_STRING[:] = [(top_t.x, top_t.y, top_t.z), (bot_t.x, bot_t.y, bot_t.z)]
    bow_export("bw_ossuary_bow", top_t.y)



def build_chitin_bow():
    """Quitina da Mãe-Verme (nv 32, épico): braços de anéis de carapaça encaixados como os segmentos do verme, com
    cristais ciano cravados; boca de verme com anel de dentes nas pontas; colares de pedra com runas ciano, punho de
    pele do verme, fileira de dentes nas costas e o frasco de ácido verde pingando na frente (cores da Mãe-Verme do
    jogo e do ácido que ela cospe)."""
    m = vcf("bw_chitin", metal=0.1)
    half, back, fl = 0.57, 0.16, 0.85
    pts = bow_curve(half, back, recurve=0.025, n=90)
    plate, plate_d, rim = H("#6e5a4c"), H("#43322a"), H("#b07a6a")
    tooth, gum, stone, stone_l = H("#efe6d0"), H("#7a2630"), H("#5e5a58"), H("#86807a")
    cyan, acid, acid_l = H("#3fd2f2"), H("#58b81c"), H("#9cf04a")
    riser_z = 0.17

    def core_r(z):
        t = min(abs(z) / half, 1.0)
        return 0.0068 + 0.0075 * (1 - t)
    tube("Core", pts, lambda u: core_r(-half + 2 * half * u), m, plate_d, sides=10, flat=fl)

    for s in (1, -1):
        # anéis de carapaça: cada um abre para a ponta e o seguinte nasce dentro da borda dele
        z, k = riser_z - 0.004, 0
        while z < half - 0.05:
            t = z / half
            L, rb = 0.036 * (1 - 0.35 * t), 0.0185 * (1 - 0.5 * t)
            p, d = limb_at(pts, z * s), limb_dir(pts, z * s).normalized()
            ob = lathe("Seg%d%d" % (s, k), [(0.0, 0.0), (0.0, rb * 0.72), (L * 0.55, rb * 0.9), (L * 0.9, rb),
                                           (L, rb * 0.94), (L, 0.0)], m, None, seg=14)
            # pinta depois de posicionar (a luz pintada fica igual nos dois braços), medindo ao longo do anel
            put(ob, lambda co, L=L, p=p, d=d: mix(plate_d, plate, smooth01((co - p).dot(d) / (L * 0.7)))
                if (co - p).dot(d) < L * 0.86 else rim, p, along(d))
            if k % 2 == 1:   # cristal ciano cravado nas costas (-Y) do anel
                back_v = (Vector((0, -1, 0)) - d * d.y).normalized()
                c = p + d * L * 0.5 + back_v * rb * 0.8
                ob = crystal("SegGem%d%d" % (s, k), m, None, (0, 0, 0), 0.0045 * (1 - 0.4 * t), 0.012, 0.004, seg=6)
                put(ob, cyan, c, along(back_v.lerp(d, 0.3)))
            z += L * 0.93
            k += 1
        # boca de verme na ponta: funil de lábio, garganta vermelha e um anel de dentes virados para dentro
        zt = (half - 0.05) * s
        p, d = limb_at(pts, zt), limb_dir(pts, zt).normalized()
        ob = lathe("Mouth%d" % s, [(0.0, 0.0), (0.0, 0.0095), (0.02, 0.0125), (0.034, 0.0135), (0.038, 0.011),
                                   (0.036, 0.0075), (0.026, 0.0)], m, None, seg=16)
        put(ob, lambda co, p=p, d=d: rim if (co - p).dot(d) < 0.03 else gum, p, along(d))
        mouth_c = p + d * 0.034
        for k in range(8):
            a = 2 * math.pi * k / 8
            out = Vector((math.cos(a), math.sin(a), 0))
            q = along(d).to_matrix() @ out
            tt = [mouth_c + q * 0.0118, mouth_c + q * 0.0105 + d * 0.006, mouth_c + q * 0.006 + d * 0.0095]
            tube("MouthTooth%d%d" % (s, k), spline(tt, 3), lambda u: 0.0026 * (1 - u) ** 0.8 + 0.0003, m, tooth,
                 sides=6)
        # fileira de dentes nas costas, logo depois do centro
        for k, zz in enumerate((0.19, 0.215, 0.24)):
            q, dq = limb_at(pts, zz * s), limb_dir(pts, zz * s).normalized()
            bv = (Vector((0, -1, 0)) - dq * dq.y).normalized()
            tt = [q + bv * 0.012, q + bv * 0.022 + dq * 0.004, q + bv * 0.03 + dq * 0.012]
            tube("BackTooth%d%d" % (s, k), spline(tt, 3), lambda u: 0.0042 * (1 - u) ** 0.9 + 0.0004, m, tooth,
                 sides=8, flat=0.6)

    # centro: pele do verme com colares de pedra e runas ciano
    def riser_r(z):
        return 0.019
    rseg = [limb_at(pts, -riser_z + 2 * riser_z * i / 60) for i in range(61)]
    tube("Riser", rseg, lambda u: 0.017 + 0.0035 * smooth01((riser_z - abs(-riser_z + 2 * riser_z * u)) / 0.04), m,
         H("#7a5e4c"), sides=14, flat=fl)
    limb_wrap("Grip", pts, -0.062, 0.062, riser_r, m, rim, turns=7, pad=0.0012, ridge=0.0012, flat=fl)
    for s in (1, -1):
        for zz in (0.075, 0.165):
            limb_wrap("Collar%d%.3f" % (s, zz), pts, zz * s - 0.011, zz * s + 0.011, riser_r, m, stone, turns=1,
                      pad=0.0035, ridge=0.0008, flat=fl)
            limb_wrap("Rune%d%.3f" % (s, zz), pts, zz * s - 0.0025, zz * s + 0.0025, riser_r, m, cyan, turns=0,
                      pad=0.0047, ridge=0.0, flat=fl)
    # frasco de ácido na frente, acima da mão: berço de pedra, vidro com ácido verde e gotas penduradas
    zc = 0.12
    p = limb_at(pts, zc)
    cy = p.y - 0.03
    lathe("VialSeat", [(0.0, 0.0), (0.0, 0.012), (0.006, 0.0125), (0.012, 0.009), (0.012, 0.0)], m, stone_l, seg=12,
          loc=(p.x, p.y - 0.014, zc), rot=(math.pi / 2, 0, 0))
    orb("Vial", m, acid, (p.x, cy, zc), 0.0145, seg=14, sq=1.15)
    orb("VialShine", m, acid_l, (p.x - 0.006, cy - 0.009, zc + 0.006), 0.0045, seg=8)
    lathe("VialCap", [(0.0, 0.0), (0.0, 0.006), (0.006, 0.0065), (0.009, 0.004), (0.009, 0.0)], m, stone, seg=10,
          loc=(p.x, cy, zc + 0.0145))
    drip = [(p.x, cy, zc - 0.012), (p.x + 0.001, cy - 0.001, zc - 0.022), (p.x + 0.0015, cy - 0.002, zc - 0.03)]
    tube("Drip", spline(drip, 3), lambda u: 0.0032 * (1 - 0.5 * u), m, acid, sides=8)
    orb("DripDrop", m, acid, (p.x + 0.0015, cy - 0.002, zc - 0.033), 0.0038, seg=10, sq=1.2)
    top_t, bot_t = limb_at(pts, half - 0.045), limb_at(pts, -(half - 0.045))
    _BOW_STRING[:] = [(top_t.x, top_t.y, top_t.z), (bot_t.x, bot_t.y, bot_t.z)]
    bow_export("bw_chitin_bow", top_t.y)



def build_ashen_bow():
    """Arco das Cinzas (nv 35, épico): freixo carbonizado da Encosta de Cinzas, com rachaduras de brasa viva correndo
    pelos braços; braseiro de ferro negro na frente do centro com carvão aceso e chamas; ponteiras de ferro com
    remate de chama; punho de pano cinza e anéis de ferro."""
    m = vcf("bw_ashen", metal=0.15)
    half, back, fl = 0.57, 0.165, 0.76
    pts = bow_curve(half, back, recurve=0.035, n=100)

    def r_of_z(z):
        t = min(abs(z) / half, 1.0)
        return 0.009 + 0.0125 * (1 - t) ** 0.65 + 0.003 * smooth01((0.2 - abs(z)) / 0.05)
    char, char_l, hot, hot_l = H("#2a2220"), H("#4a3c36"), H("#e8561a"), H("#ffb03a")

    def charred(co):   # carvão com veios de casca
        a = math.atan2(co.y, co.x)
        return mix(char, char_l, 0.3 + 0.3 * math.sin(a * 5 + co.z * 4))
    tube("Limbs", pts, lambda u: r_of_z(-half + 2 * half * u), m, charred, sides=18, flat=fl)
    # rachaduras de brasa: veios finos cravados na superfície, serpenteando ao comprido, com ramos curtos
    for s in (1, -1):
        for k, (a0, z0, z1) in enumerate(((0.3, 0.09, 0.5), (2.4, 0.12, 0.44), (4.3, 0.1, 0.53))):
            seg = []
            for i in range(61):
                z = (z0 + (z1 - z0) * i / 60) * s
                c, a = limb_at(pts, z), a0 + 0.7 * math.sin(z * 17 + k) + 0.25 * math.sin(z * 53)
                rr = r_of_z(z) * 0.985
                seg.append(c + Vector((math.cos(a) * rr, math.sin(a) * rr * fl, 0)))
            tube("Crack%d%d" % (s, k), seg, lambda u: 0.0019 * (0.4 + 0.6 * math.sin(math.pi * u) ** 0.5), m,
                 lambda co: hot, sides=6)
            for b in (0.3, 0.65):   # ramos
                p0 = Vector(seg[int(b * 60)])
                zb = p0.z
                ab = a0 + 0.7 * math.sin(zb * 17 + k) + 0.25 * math.sin(zb * 53) + 0.9
                rb = r_of_z(zb) * 0.985
                c = limb_at(pts, zb + 0.03 * s)
                p1 = c + Vector((math.cos(ab) * rb, math.sin(ab) * rb * fl, 0))
                tube("CrackB%d%d%.1f" % (s, k, b), [p0, p0.lerp(p1, 0.5), p1], lambda u: 0.0014 * (1 - 0.7 * u), m,
                     hot_l, sides=5)

    iron, iron_l, cloth = H("#26242a"), H("#4e4a52"), H("#6a625e")
    flame = [(0.0, 0.0), (0.009, 0.006), (0.012, 0.02), (0.006, 0.032), (0.009, 0.045), (0.0, 0.062),
             (-0.004, 0.044), (-0.011, 0.034), (-0.008, 0.016), (-0.009, 0.005)]
    for s in (1, -1):
        # ponteira de ferro com remate de chama (plano do arco, para ler de lado)
        limb_wrap("TipCap%d" % s, pts, (half - 0.045) * s if s > 0 else -half + 0.002,
                  half - 0.002 if s > 0 else -(half - 0.045), r_of_z, m, iron, turns=2, pad=0.0014, ridge=0.0007,
                  flat=fl)
        tip, d = limb_at(pts, (half - 0.004) * s), limb_dir(pts, (half - 0.004) * s).normalized()
        rot = d.to_track_quat('Z', 'X').to_euler()
        for k, (sc, col, off) in enumerate(((1.0, hot, 0.0), (0.6, hot_l, 0.0026))):   # laranja por fora, amarela dentro
            ob = flat("TipFlame%d%d" % (s, k), [(x * sc, z * sc) for x, z in flame], m, None, th=0.004 + off,
                      bevel=0.002, step=0.004)
            put(ob, col, tip - d * 0.006, rot)
        # anéis de ferro no braço
        for z in (0.24, 0.36):
            limb_wrap("Ring%d%.2f" % (s, z), pts, z * s - 0.007, z * s + 0.007, r_of_z, m, iron_l, turns=1,
                      pad=0.0015, ridge=0.0004, flat=fl)
        limb_wrap("RiserBand%d" % s, pts, 0.072 * s - 0.008, 0.072 * s + 0.008, r_of_z, m, iron, turns=1, pad=0.0022,
                  ridge=0.0005, flat=fl)
    limb_wrap("Grip", pts, -0.064, 0.064, r_of_z, m, cloth, turns=11, pad=0.0016, ridge=0.0008, flat=fl)

    # braseiro na frente, acima da mão: taça de ferro presa por dois braços, carvão aceso e três chamas
    zb = 0.118
    p = limb_at(pts, zb)
    cx, cy = p.x, p.y - r_of_z(zb) * fl - 0.022
    lathe("Brazier", [(0.0, 0.0), (0.0, 0.006), (0.004, 0.0075), (0.012, 0.0145), (0.016, 0.0165), (0.017, 0.0145),
                      (0.017, 0.0)], m, iron, seg=16, loc=(cx, cy, zb - 0.012))
    for k in range(6):
        a = 2 * math.pi * k / 6
        orb("BrazierStud%d" % k, m, iron_l, (cx + 0.0158 * math.cos(a), cy + 0.0158 * math.sin(a), zb + 0.001), 0.0022,
            seg=6)
    for z in (zb - 0.008, zb + 0.002):
        q = limb_at(pts, z)
        tube("BrazierArm%.3f" % z, [(q.x, q.y, z), (cx, cy + 0.012, z)], 0.0026, m, iron, sides=8)
    for k, (dx, dy, r) in enumerate(((0.0, 0.0, 0.0085), (0.007, 0.004, 0.0062), (-0.0065, -0.003, 0.0058))):
        orb("Coal%d" % k, m, H("#e8561a") if k else H("#ff9a2a"), (cx + dx, cy + dy, zb + 0.004), r, seg=10, sq=0.8)
    for k, (dx, sc, ang) in enumerate(((0.0, 1.0, 0.0), (0.007, 0.7, 0.35), (-0.0065, 0.65, -0.3))):
        for kk, (f2, col, off) in enumerate(((1.0, hot, 0.0), (0.58, hot_l, 0.0024))):
            ob = flat("BrazierFlame%d%d" % (k, kk), [(x * sc * f2, z * sc * f2) for x, z in flame], m, None,
                      th=0.0035 + off, bevel=0.0017, step=0.004)
            put(ob, col, (cx + dx, cy, zb + 0.006), (0, ang, math.pi / 2))
    top_t, bot_t = limb_at(pts, half - 0.022), limb_at(pts, -(half - 0.022))
    _BOW_STRING[:] = [(top_t.x, top_t.y, top_t.z), (bot_t.x, bot_t.y, bot_t.z)]
    bow_export("bw_ashen_bow", top_t.y)



def build_yeti_bow():
    """Arco do Ieti (nv 40, épico): dois chifres do Ieti Glacial, grossos e anelados, do azul fundo da base ao gelo
    claro da ponta; garras azul-marinho agarrando a raiz dos chifres; golas de pelo branco; punho de pele azul; tufos de
    gelo nas costas dos chifres; pingentes de gelo sob o centro e presas brancas nas pontas (cores do Ieti do jogo).
    Sem emissão: no toon do jogo o gelo brilhando vira branco."""
    m = vcf("bw_yeti", metal=0.1)
    half, back, fl = 0.57, 0.175, 0.82
    pts = bow_curve(half, back, recurve=0.045, n=100)
    root = 0.13

    def horn_r(z):
        t = min(max((abs(z) - root) / (half - root), 0.0), 1.0)
        return 0.0115 + 0.0175 * (1 - t) ** 0.8      # chifre grosso: o arco é pesado
    deep, skin, pale = H("#46698c"), H("#6e97bc"), H("#d6f2ff")

    def horn(co):
        t = min(max((abs(co.z) - root) / (half - root), 0.0), 1.0)
        c = ramp([(0.0, deep), (0.45, skin), (1.0, pale)], t)
        ring = smooth01((math.sin(abs(co.z) * 190) - 0.72) / 0.2) * (1 - 0.5 * t)   # anéis de crescimento pintados
        return mix(c, deep, 0.55 * ring)
    for s in (1, -1):
        seg = [p for p in pts if p[2] * s > root - 0.05]
        if s < 0:
            seg = seg[::-1]
        tube("Horn%d" % s, seg, lambda u, seg=seg: horn_r(seg[0][2] + (seg[-1][2] - seg[0][2]) * u), m, horn,
             sides=16, flat=fl)

    fur, fur_d, claw, fang = H("#e6eef4"), H("#afc0ce"), H("#2c3a4c"), H("#f4f6f8")
    ice, ice_d = H("#8fe6ff"), H("#3aa0d8")

    def riser_r(z):
        return 0.0235
    rseg = [limb_at(pts, -root + 2 * root * i / 60) for i in range(61)]
    tube("Riser", rseg, lambda u: 0.022, m, claw, sides=14, flat=fl)
    limb_wrap("Grip", pts, -0.064, 0.064, riser_r, m, skin, turns=9, pad=0.0008, ridge=0.0009, flat=fl)
    for s in (1, -1):
        # gola de pelo branco na raiz do chifre: tufos deitados para a ponta
        z = (root - 0.012) * s
        p, dz = limb_at(pts, z), limb_dir(pts, z).normalized()
        for row, (zo, rr) in enumerate(((0.0, 0.0), (0.012, 0.004))):   # duas fileiras encavaladas
            for k in range(22):
                a = 2 * math.pi * (k + 0.5 * row) / 22 + 0.3 * s
                out = Vector((math.cos(a), math.sin(a) * fl, 0))
                L = 0.02 + 0.006 * math.sin(k * 2.3 + row)
                q = p - dz * zo
                tuft = [q + out * 0.014, q + out * (0.026 + rr) + dz * L * 0.25, q + out * (0.031 + rr) + dz * L]
                tube("Fur%d%d%d" % (s, row, k), spline(tuft, 3), lambda u: 0.0085 * (1 - u) ** 0.55 + 0.0012, m,
                     fur if (k + row) % 3 else fur_d, sides=7, flat=0.6)
        # garras azul-marinho saindo do centro e agarrando a raiz do chifre (três de cada lado, por fora)
        base = limb_at(pts, (root - 0.035) * s)
        for k, ax in enumerate((-1.0, 0.0, 1.0)):
            side = Vector((ax * 0.9, -0.55 if ax == 0 else -0.2, 0)).normalized()
            c = [base + side * 0.012, base + side * 0.027 + dz * 0.012, base + side * 0.028 + dz * 0.04,
                 base + side * 0.019 + dz * 0.062]
            tube("Claw%d%d" % (s, k), spline(c, 5), lambda u: 0.0072 * (1 - u) ** 0.7 + 0.0006, m, claw, sides=10,
                 flat=0.8)
        # tufos de gelo nas costas do chifre (-Y), em leque, deitados para a ponta
        for k, (zz, n_c, size) in enumerate(((0.22, 5, 1.4), (0.33, 4, 1.1))):
            q, dq = limb_at(pts, zz * s), limb_dir(pts, zz * s).normalized()
            face = q + Vector((0, -horn_r(zz) * fl * 0.55, 0))
            for c in range(n_c):
                f = (c - (n_c - 1) / 2) / max((n_c - 1) / 2, 1)
                tilt = Vector((0.75 * f, -1, 0)).normalized().lerp(dq, 0.3 + 0.12 * abs(f)).normalized()
                h = 0.042 * size * (1 - 0.38 * abs(f))
                ob = crystal("Ice%d%d%d" % (s, k, c), m, None, (0, 0, 0), 0.0068 * size * (1 - 0.25 * abs(f)), h,
                             0.012, seg=5, phase=0.5 * c)
                put(ob, ice_d if c % 2 else ice, face + Vector((0.006 * f, 0, 0.004 * f * s)), along(tilt))
        # presa branca na ponta, curvada para a frente
        tip, d = limb_at(pts, (half - 0.004) * s), limb_dir(pts, (half - 0.004) * s).normalized()
        hook = [tip - d * 0.025, tip + d * 0.022, tip + d * 0.05 + Vector((0, -0.018, 0)),
                tip + d * 0.058 + Vector((0, -0.045, 0))]
        tube("Fang%d" % s, spline(hook, 6), lambda u: 0.0135 * (1 - u) ** 0.75 + 0.0006, m, lambda co: fang,
             sides=12, flat=0.85)
        limb_wrap("FangTie%d" % s, pts, (half - 0.016) * s - 0.012, (half - 0.016) * s + 0.012, horn_r, m, claw,
                  turns=3, pad=0.0014, ridge=0.0008, flat=fl)
    # pingentes de gelo pendurados sob o centro, na frente da gola de baixo
    p = limb_at(pts, -root + 0.005)
    for k, (dx, L) in enumerate(((-0.012, 0.05), (0.0, 0.07), (0.012, 0.045))):
        ob = crystal("Icicle%d" % k, m, None, (0, 0, 0), 0.0055, L, 0.006, seg=6, phase=0.4 * k)
        put(ob, ice if k != 1 else ice_d, (p.x + dx, p.y - 0.017, p.z - 0.004), (math.pi, 0, 0))
    top_t, bot_t = limb_at(pts, half - 0.016), limb_at(pts, -(half - 0.016))
    _BOW_STRING[:] = [(top_t.x, top_t.y, top_t.z), (bot_t.x, bot_t.y, bot_t.z)]
    bow_export("bw_yeti_bow", top_t.y)


# ------------------------------------------------------------------ arcos míticos (endgame)
# Mais longos e ornamentados que os da progressão. Gemas e núcleos em material "bw_<id>_gem" com emissão (WeaponModel
# troca o branco por cor de albedo e emissão baixa); partículas nos empties de aura() (BowAura no jogo).
def mythic_side(pts, z, r, fl, sx):
    """Ponto na lateral (±X) do braço em z, na superfície."""
    return limb_at(pts, z) + Vector((sx * r * 0.95, 0, 0))


def mythic_back(pts, z, r, fl):
    """Ponto nas costas do arco (-Y, o lado do alvo) em z, na superfície."""
    return limb_at(pts, z) + Vector((0, -r * fl * 0.9, 0))


def feather_outline(L, W, notch=True):
    """Pena achatada no plano XZ, base em z=0 subindo em +Z: haste fina, bandeira larga e ponta arredondada."""
    pts = [(0.0, 0.0), (W * 0.2, L * 0.08), (W * 0.55, L * 0.3), (W * 0.62, L * 0.55), (W * 0.48, L * 0.8),
           (W * 0.18, L * 0.97), (0.0, L)]
    left = [(-x * (0.8 if notch else 1.0), z) for x, z in reversed(pts[1:-1])]
    return pts + left


def plane_yz(ob):
    """Peça plana (feita no plano XZ) girada para o plano YZ, o plano do arco (lida de lado)."""
    place(ob, (0, 0, 0), (0, 0, math.pi / 2))
    return ob


def build_abyss_bow():
    """Suspiro do Abismo (Mítico): cada braço é um par de costelas negras que se juntam na ponta e no punho, presas
    por fios do vazio; esporas de osso nas costas; o olho do Abismo acima da mão, com pálpebras e íris violeta acesa;
    cristais do vazio nas pontas do centro e garras negras nas pontas."""
    m = vcf("bw_abyss", metal=0.2)
    g = vcf("bw_abyss_gem", emit="#9a4dff", strength=1.0)
    half, back, fl = 0.6, 0.18, 0.8
    pts = bow_curve(half, back, recurve=0.05, n=110)
    rz = 0.15
    black, black_l, violet, bone = H("#1c1424"), H("#3c2c52"), H("#7b3fd6"), H("#d8cce6")

    def rib_col(co):
        t = min(abs(co.z) / half, 1.0)
        return mix(black, black_l, 0.25 + 0.5 * smooth01((math.sin(co.z * 70) + 1) / 2) * (1 - t))
    for s in (1, -1):
        for k, sx in enumerate((1, -1)):
            seg = []
            for i in range(61):
                z = s * (rz - 0.02 + (half - rz) * i / 60)
                u = i / 60
                spread = 0.017 * math.sin(math.pi * min(u * 1.15, 1.0)) ** 0.8   # abre no meio, junta nas pontas
                seg.append(limb_at(pts, z) + Vector((sx * spread, 0.004 * math.sin(u * 9), 0)))
            tube("Rib%d%d" % (s, k), seg, lambda u: 0.0105 * (1 - 0.55 * u) + 0.0018, m, rib_col, sides=12, flat=0.85)
        # fios do vazio entre as duas costelas
        for j, zz in enumerate((0.24, 0.3, 0.36, 0.42, 0.48)):
            u = (zz - rz + 0.02) / (half - rz)
            spread = 0.017 * math.sin(math.pi * min(u * 1.15, 1.0)) ** 0.8
            c = limb_at(pts, zz * s)
            tube("Sinew%d%d" % (s, j), [c + Vector((-spread, 0, 0)), c + Vector((0, -0.003, 0)), c + Vector((spread, 0, 0))],
                 0.0026, g, violet, sides=6)
        # esporas de osso nas costas, deitadas para a ponta
        for j, (zz, L) in enumerate(((0.2, 0.05), (0.27, 0.042), (0.34, 0.036), (0.41, 0.03))):
            p, d = limb_at(pts, zz * s), limb_dir(pts, zz * s).normalized()
            bv = (Vector((0, -1, 0)) - d * d.y).normalized()
            tube("Spur%d%d" % (s, j), spline([p + bv * 0.004, p + bv * L * 0.6 + d * L * 0.25, p + bv * L + d * L * 0.7], 4),
                 lambda u: 0.0075 * (1 - u) ** 0.9 + 0.0005, m, bone, sides=8, flat=0.5)
        # garra negra na ponta, curvada para a frente, com gema na base
        tip, d = limb_at(pts, (half - 0.004) * s), limb_dir(pts, (half - 0.004) * s).normalized()
        hook = [tip - d * 0.03, tip + d * 0.02, tip + d * 0.055 + Vector((0, -0.025, 0)), tip + d * 0.06 + Vector((0, -0.065, 0)),
                tip + d * 0.04 + Vector((0, -0.09, 0))]
        tube("Claw%d" % s, spline(hook, 6), lambda u: 0.012 * (1 - u) ** 0.8 + 0.0006, m, black, sides=12, flat=0.8)
        orb("ClawGem%d" % s, g, violet, tip - d * 0.012 + Vector((0, -0.009, 0)), 0.0075, seg=10)
        aura("void", tip + d * 0.03 + Vector((0, -0.04, 0)))
        # cristais do vazio nascendo nas pontas do centro
        base = limb_at(pts, rz * s)
        for j, (ax, ay, h, r) in enumerate(((0.9, -0.4, 0.06, 0.009), (-0.85, -0.5, 0.05, 0.008), (0.1, -1.0, 0.07, 0.01),
                                             (0.5, 0.6, 0.04, 0.007), (-0.5, 0.6, 0.035, 0.006))):
            dirv = (Vector((ax, ay, 0)).normalized() * 0.7 + limb_dir(pts, rz * s).normalized() * 0.6).normalized()
            ob = crystal("Void%d%d" % (s, j), g, None, (0, 0, 0), r, h, 0.014, seg=6, mid=h * 0.15, phase=0.4 * j)
            put(ob, violet if j % 2 else H("#b98cff"), base + Vector((ax, ay, 0)).normalized() * 0.012, along(dirv))
        aura("void", base + Vector((0, -0.05, 0.03 * s)))

    # centro: núcleo negro com anéis violeta e punho de couro escuro
    def rr(z):
        return 0.0215
    rseg = [limb_at(pts, -rz + 2 * rz * i / 60) for i in range(61)]
    tube("Riser", rseg, lambda u: 0.019 + 0.004 * smooth01((rz - abs(-rz + 2 * rz * u)) / 0.04), m, black, sides=14, flat=fl)
    limb_wrap("Grip", pts, -0.062, 0.062, rr, m, H("#2a2030"), turns=10, pad=0.0008, ridge=0.0009, flat=fl)
    for s in (1, -1):
        limb_wrap("Band%d" % s, pts, 0.07 * s - 0.005, 0.07 * s + 0.005, rr, g, violet, turns=0, pad=0.0026, ridge=0.0,
                  flat=fl)
    # o olho do Abismo: órbita de osso, íris violeta acesa, pupila em fenda e duas pálpebras
    zc = 0.108
    p = limb_at(pts, zc)
    fy = p.y - 0.02
    lathe("EyeSocket", [(0.0, 0.0), (0.0, 0.021), (0.006, 0.022), (0.012, 0.017), (0.012, 0.0)], m, bone, seg=20,
          loc=(p.x, p.y - 0.008, zc), rot=(math.pi / 2, 0, 0))
    orb("Iris", g, H("#a35cff"), (p.x, fy, zc), 0.0135, seg=16, sq=0.7)
    slit = [(-0.0018, -0.011), (0.0018, -0.011), (0.0032, 0.0), (0.0018, 0.011), (-0.0018, 0.011), (-0.0032, 0.0)]
    flat("Pupil", slit, m, H("#0a0610"), th=0.0016, bevel=0.0006, step=0.003, loc=(p.x, fy - 0.0095, zc))
    for k, sz in enumerate((1, -1)):
        lid = [(-0.022, 0.0), (-0.012, 0.008 * sz), (0.0, 0.011 * sz), (0.012, 0.008 * sz), (0.022, 0.0),
               (0.012, 0.0045 * sz), (0.0, 0.006 * sz), (-0.012, 0.0045 * sz)]
        ob = flat("Lid%d" % k, lid, m, None, th=0.005, bevel=0.002, step=0.003)
        put(ob, black_l, (p.x, fy - 0.004, zc + 0.008 * sz))
    for sx in (1, -1):   # cílios de osso
        for j in range(3):
            q = Vector((p.x + sx * (0.012 + 0.005 * j), fy - 0.003, zc + 0.012 - 0.004 * j))
            tube("Lash%d%d" % (sx, j), [q, q + Vector((sx * 0.01, -0.004, 0.012))], lambda u: 0.002 * (1 - u) + 0.0003, m,
                 bone, sides=5)
    aura("void", (p.x, fy - 0.02, zc))
    top_t, bot_t = limb_at(pts, half - 0.03), limb_at(pts, -(half - 0.03))
    _BOW_STRING[:] = [(top_t.x, top_t.y, top_t.z), (bot_t.x, bot_t.y, bot_t.z)]
    bow_export("bw_abyss_bow", top_t.y)


def build_dawn_bow():
    """Alvorada, a Asa da Fênix (Mítico): arco de ouro com aresta clara; penas de fênix em leque nas costas dos dois
    braços, como asas abertas (vermelho na base, laranja, amarelo na ponta); disco solar com raios e gema acesa acima da
    mão; remates de chama nas pontas."""
    m = vcf("bw_dawn", metal=0.45)
    g = vcf("bw_dawn_gem", emit="#ffb030", strength=1.0)
    half, back, fl = 0.6, 0.17, 0.72
    pts = bow_curve(half, back, recurve=0.05, n=110)
    gold, gold_l, gold_d = H("#e0a83a"), H("#fff0b0"), H("#9a6a1c")

    def r_of_z(z):
        t = min(abs(z) / half, 1.0)
        return 0.0095 + 0.0125 * (1 - t) ** 0.7 + 0.003 * smooth01((0.17 - abs(z)) / 0.05)

    def goldc(co):
        c = limb_at(pts, co.z)
        k = (c.y - co.y) / max(r_of_z(co.z) * fl, 1e-4)      # aresta clara nas costas
        return mix(mix(gold_d, gold, 0.75), gold_l, smooth01((k - 0.55) / 0.3))
    tube("Limbs", pts, lambda u: r_of_z(-half + 2 * half * u), m, goldc, sides=16, flat=fl)
    red, orange, yellow = H("#c8321c"), H("#f07a1e"), H("#ffd24a")
    for s in (1, -1):
        # penas da asa: nascem nas costas do braço e abrem para trás e para a ponta (plano do arco)
        for j in range(7):
            zz = 0.17 + j * 0.05
            p, d = limb_at(pts, zz * s), limb_dir(pts, zz * s).normalized()
            L = 0.07 + 0.11 * math.sin(math.pi * (j + 0.6) / 7.6)
            ang = math.radians(78 - j * 7)                 # as de perto do punho saem mais para trás
            bv = (Vector((0, -1, 0)) - d * d.y).normalized()
            dirv = (bv * math.sin(ang) + d * math.cos(ang)).normalized()
            ob = flat("Feather%d%d" % (s, j), feather_outline(L, 0.028), m, None, th=0.004, bevel=0.002, step=0.006,
                      bend=lambda c, L=L: Vector((c.x, c.y + 0.25 * (c.z / L) ** 2 * 0.03, c.z)))
            plane_yz(ob)
            place(ob, (0, 0, 0), along(dirv))
            place(ob, p + bv * r_of_z(zz) * fl * 0.5)
            cel(ob, lambda co, p=p, dirv=dirv, L=L: ramp([(0.0, red), (0.45, orange), (1.0, yellow)],
                                                         (co - p).dot(dirv) / L))
            if j in (2, 4, 6):
                aura("fire", p + dirv * L * 0.95)
        # remate de chama de ouro na ponta
        tip, d = limb_at(pts, (half - 0.004) * s), limb_dir(pts, (half - 0.004) * s).normalized()
        flame = [(0.0, 0.0), (0.011, 0.008), (0.014, 0.026), (0.007, 0.04), (0.011, 0.056), (0.0, 0.078),
                 (-0.005, 0.055), (-0.013, 0.042), (-0.009, 0.02), (-0.011, 0.006)]
        for k, (sc, col, th) in enumerate(((1.0, gold, 0.006), (0.6, yellow, 0.0085))):
            ob = flat("TipFlame%d%d" % (s, k), [(x * sc, z * sc) for x, z in flame], m if k == 0 else g, None, th=th,
                      bevel=0.002, step=0.005)
            put(ob, col, tip - d * 0.01, d.to_track_quat('Z', 'X').to_euler())
        aura("sun", tip + d * 0.06)
    limb_wrap("Grip", pts, -0.064, 0.064, r_of_z, m, H("#7a2418"), turns=11, pad=0.0014, ridge=0.0008, flat=fl)
    for s in (1, -1):
        limb_wrap("Band%d" % s, pts, 0.072 * s - 0.007, 0.072 * s + 0.007, r_of_z, m, gold_l, turns=1, pad=0.0026,
                  ridge=0.0005, flat=fl)
    # disco solar: raios de ouro em estrela, aro e a gema acesa no centro
    zc = 0.115
    p = limb_at(pts, zc)
    fy = p.y - r_of_z(zc) * fl - 0.006
    rays = []
    for i in range(24):
        a = 2 * math.pi * i / 24
        r = 0.04 if i % 2 == 0 else 0.022
        rays.append((math.cos(a) * r, math.sin(a) * r))
    flat("SunRays", rays, m, gold, th=0.004, bevel=0.0018, step=0.004, loc=(p.x, fy + 0.002, zc))
    lathe("SunRing", [(0.0, 0.0), (0.0, 0.019), (0.004, 0.0195), (0.007, 0.016), (0.007, 0.0)], m, gold_l, seg=24,
          loc=(p.x, fy, zc), rot=(math.pi / 2, 0, 0))
    orb("SunGem", g, H("#ffb030"), (p.x, fy - 0.006, zc), 0.0135, seg=16, sq=0.6)
    aura("sun", (p.x, fy - 0.02, zc))
    top_t, bot_t = limb_at(pts, half - 0.022), limb_at(pts, -(half - 0.022))
    _BOW_STRING[:] = [(top_t.x, top_t.y, top_t.z), (bot_t.x, bot_t.y, bot_t.z)]
    bow_export("bw_dawn_bow", top_t.y)


def build_dragon_bow():
    """Presa do Dragão Ancestral (Mítico): braços de chifre escamado carmim, crista de espinhos de osso nas costas,
    membranas de asa saindo do centro, quatro garras segurando a gema de brasa acima da mão e pontas de chifre marfim."""
    m = vcf("bw_dragon", metal=0.15)
    g = vcf("bw_dragon_gem", emit="#ff5a14", strength=1.0)
    half, back, fl = 0.61, 0.19, 0.8
    pts = bow_curve(half, back, recurve=0.06, n=110)
    scale_d, scale_c, scale_l = H("#3a0e0c"), H("#7a1e16"), H("#b8402a")
    bone, gold = H("#ead8b0"), H("#c89436")

    def r_of_z(z):
        t = min(abs(z) / half, 1.0)
        return 0.011 + 0.014 * (1 - t) ** 0.7 + 0.003 * smooth01((0.17 - abs(z)) / 0.05)

    def scales(co):   # escamas em losango: borda clara em cima de cada escama
        a = math.atan2(co.x, co.y - limb_at(pts, co.z).y)
        u, v = a * 3.2 + co.z * 40, a * 3.2 - co.z * 40
        f = abs(math.sin(u)) * abs(math.sin(v))
        t = min(abs(co.z) / half, 1.0)
        base = mix(scale_d, scale_c, 0.4 + 0.6 * f)
        return mix(base, mix(scale_l, bone, smooth01((t - 0.75) / 0.25)), smooth01((f - 0.75) / 0.2))
    tube("Limbs", pts, lambda u: r_of_z(-half + 2 * half * u), m, scales, sides=18, flat=fl)
    for s in (1, -1):
        # crista de espinhos nas costas, do centro quase até a ponta
        for j in range(9):
            zz = 0.17 + j * 0.042
            p, d = limb_at(pts, zz * s), limb_dir(pts, zz * s).normalized()
            bv = (Vector((0, -1, 0)) - d * d.y).normalized()
            L = 0.045 * (1 - 0.6 * j / 9) + 0.012
            tube("Crest%d%d" % (s, j), spline([p + bv * r_of_z(zz) * 0.5, p + bv * (r_of_z(zz) + L * 0.6) + d * L * 0.25,
                                                p + bv * (r_of_z(zz) + L) + d * L * 0.75], 4),
                 lambda u: 0.0085 * (1 - u) ** 0.9 + 0.0006, m, bone, sides=8, flat=0.45)
        # ponta de chifre marfim curvada para a frente, com anel de ouro
        tip, d = limb_at(pts, (half - 0.004) * s), limb_dir(pts, (half - 0.004) * s).normalized()
        hook = [tip - d * 0.03, tip + d * 0.03, tip + d * 0.065 + Vector((0, -0.025, 0)), tip + d * 0.07 + Vector((0, -0.06, 0))]
        tube("Horn%d" % s, spline(hook, 6), lambda u: 0.0145 * (1 - u) ** 0.75 + 0.0006, m,
             lambda co, tip=tip: mix(bone, H("#fff6e0"), 0.4), sides=12, flat=0.85)
        limb_wrap("HornRing%d" % s, pts, (half - 0.02) * s - 0.01, (half - 0.02) * s + 0.01, r_of_z, m, gold, turns=2,
                  pad=0.0016, ridge=0.0007, flat=fl)
        aura("fire", tip + d * 0.05 + Vector((0, -0.05, 0)))
        # membrana de asa saindo do centro para trás, com três dedos de osso
        root = limb_at(pts, 0.14 * s)
        fingers = []
        for k, (zz, out) in enumerate(((0.21, 0.1), (0.29, 0.13), (0.37, 0.085))):
            q = limb_at(pts, zz * s) + Vector((0, -r_of_z(zz) * fl - out, 0))
            fingers.append(q)
            tube("WingBone%d%d" % (s, k), spline([root, root.lerp(q, 0.5) + Vector((0, -0.01, 0)), q], 4),
                 lambda u: 0.0042 * (1 - 0.5 * u), m, bone, sides=6)
        memb = []
        for k in range(len(fingers)):
            memb.append(fingers[k])
            if k + 1 < len(fingers):
                memb.append(fingers[k].lerp(fingers[k + 1], 0.5) + Vector((0, 0.022, 0)))   # recorte entre os dedos
        last = limb_at(pts, 0.4 * s)
        outline = [root] + memb + [last]
        # membrana: leque de triângulos (malha plana fina) no plano do arco
        bmm = bmesh.new()
        vs = [bmm.verts.new(v) for v in outline]
        faces = []
        for k in range(1, len(vs) - 1):
            try:
                faces.append(bmm.faces.new((vs[0], vs[k], vs[k + 1])))
            except ValueError:
                pass
        bmesh.ops.solidify(bmm, geom=faces, thickness=0.0025)
        me = bpy.data.meshes.new("Membrane%d" % s)
        bmm.to_mesh(me)
        bmm.free()
        ob = bpy.data.objects.new("Membrane%d" % s, me)
        coll.objects.link(ob)
        ob.data.materials.append(m)
        cel(ob, H("#8a2a1e"))
    limb_wrap("Grip", pts, -0.064, 0.064, r_of_z, m, H("#3a1a12"), turns=10, pad=0.0014, ridge=0.0009, flat=fl)
    for s in (1, -1):
        limb_wrap("Band%d" % s, pts, 0.072 * s - 0.007, 0.072 * s + 0.007, r_of_z, m, gold, turns=1, pad=0.0026,
                  ridge=0.0005, flat=fl)
    # gema de brasa segura por quatro garras de ouro, acima da mão
    zc = 0.118
    p = limb_at(pts, zc)
    cy = p.y - r_of_z(zc) * fl - 0.016
    orb("EmberGem", g, H("#ff6a1a"), (p.x, cy, zc), 0.0155, seg=16, sq=1.15)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        o = Vector((math.cos(a), 0, math.sin(a)))
        base = Vector((p.x, p.y - r_of_z(zc) * fl * 0.6, zc)) + o * 0.012
        tipc = Vector((p.x, cy - 0.009, zc)) + o * 0.009
        tube("Talon%d" % k, spline([base, Vector((p.x, cy + 0.006, zc)) + o * 0.02, tipc], 4),
             lambda u: 0.0038 * (1 - 0.6 * u) + 0.0005, m, gold, sides=8)
    aura("fire", (p.x, cy - 0.02, zc))
    top_t, bot_t = limb_at(pts, half - 0.02), limb_at(pts, -(half - 0.02))
    _BOW_STRING[:] = [(top_t.x, top_t.y, top_t.z), (bot_t.x, bot_t.y, bot_t.z)]
    bow_export("bw_dragon_bow", top_t.y)


def build_wind_bow():
    """Rei dos Ventos (Mítico): arco longo e fino de prata e marfim, canal de vento ciano em espiral nos braços, penas
    brancas e fitas longas esvoaçando nas pontas, gema ciano num redemoinho de prata acima da mão."""
    m = vcf("bw_wind", metal=0.4)
    g = vcf("bw_wind_gem", emit="#5ae0ff", strength=1.0)
    half, back, fl = 0.66, 0.15, 0.7
    pts = bow_curve(half, back, recurve=0.07, n=120)
    silver, silver_l, ivory, cyan = H("#b8c4d0"), H("#eef4fa"), H("#f2ecdc"), H("#5ae0ff")

    def r_of_z(z):
        t = min(abs(z) / half, 1.0)
        return 0.0075 + 0.0105 * (1 - t) ** 0.7 + 0.003 * smooth01((0.16 - abs(z)) / 0.05)
    tube("Limbs", pts, lambda u: r_of_z(-half + 2 * half * u), m,
         lambda co: mix(silver, silver_l, 0.5 + 0.5 * math.sin(co.z * 30)), sides=16, flat=fl)
    for s in (1, -1):
        z0, z1 = sorted((0.16 * s, (half - 0.06) * s))
        limb_helix("Wind%d" % s, pts, z0, z1, r_of_z, 4.0, 0.0, g, cyan, fl, r=0.0016, k=160)
        tip, d = limb_at(pts, (half - 0.004) * s), limb_dir(pts, (half - 0.004) * s).normalized()
        limb_wrap("TipCap%d" % s, pts, (half - 0.035) * s - 0.012, (half - 0.035) * s + 0.012, r_of_z, m, silver_l,
                  turns=2, pad=0.0014, ridge=0.0007, flat=fl)
        # ponta em lâmina curva para a frente
        hook = [tip - d * 0.02, tip + d * 0.02, tip + d * 0.045 + Vector((0, -0.02, 0)), tip + d * 0.045 + Vector((0, -0.045, 0))]
        tube("Blade%d" % s, spline(hook, 5), lambda u: 0.009 * (1 - u) ** 0.8 + 0.0005, m, silver_l, sides=8, flat=0.4)
        # duas penas brancas e duas fitas longas presas no anel da ponta, esvoaçando para trás (+Y, lado do arqueiro)
        ring = limb_at(pts, (half - 0.035) * s)
        for k, (ang, L) in enumerate(((0.35, 0.1), (0.8, 0.085))):
            dirv = (d * math.cos(ang) + Vector((0, 1, 0)) * math.sin(ang)).normalized()
            ob = flat("Plume%d%d" % (s, k), feather_outline(L, 0.022), m, None, th=0.003, bevel=0.0015, step=0.006)
            plane_yz(ob)
            put(ob, lambda co, ring=ring, dirv=dirv, L=L: mix(ivory, H("#a8d8ea"), smooth01((co - ring).dot(dirv) / L - 0.6)),
                ring + Vector((0, r_of_z(half - 0.035) * fl * 0.5, 0)), along(dirv))
        for k, (sx, L) in enumerate(((1, 0.22), (-1, 0.18))):
            rib = []
            for i in range(25):
                u = i / 24
                rib.append(ring + Vector((sx * 0.006, 0.01 + L * u * 0.85, -s * L * u * 0.35 + 0.012 * math.sin(u * 7 + k))))
            tube("Ribbon%d%d" % (s, k), rib, lambda u: 0.013 * (1 - 0.3 * u), m,
                 lambda co, k=k: cyan if k == 0 else silver_l, sides=10, flat=0.22)
            aura("wind", rib[-1])
        aura("wind", tip + d * 0.03)
    limb_wrap("Grip", pts, -0.064, 0.064, r_of_z, m, H("#2c4a66"), turns=12, pad=0.0014, ridge=0.0008, flat=fl)
    for s in (1, -1):
        limb_wrap("Band%d" % s, pts, 0.072 * s - 0.006, 0.072 * s + 0.006, r_of_z, m, silver_l, turns=1, pad=0.0026,
                  ridge=0.0005, flat=fl)
    # gema ciano num redemoinho de prata (três braços curvos em volta)
    zc = 0.112
    p = limb_at(pts, zc)
    cy = p.y - r_of_z(zc) * fl - 0.012
    orb("WindGem", g, cyan, (p.x, cy, zc), 0.012, seg=16, sq=1.0)
    for k in range(3):
        a0 = 2 * math.pi * k / 3
        sw = []
        for i in range(13):
            u = i / 12
            a = a0 + u * 2.4
            r = 0.016 + 0.012 * u
            sw.append(Vector((p.x + math.cos(a) * r, cy + 0.006 * (1 - u), zc + math.sin(a) * r)))
        tube("Swirl%d" % k, sw, lambda u: 0.0042 * (1 - 0.7 * u) + 0.0005, m, silver_l, sides=8)
    lathe("GemSeat", [(0.0, 0.0), (0.0, 0.014), (0.005, 0.0145), (0.012, 0.011), (0.012, 0.0)], m, silver, seg=16,
          loc=(p.x, p.y - r_of_z(zc) * fl * 0.5, zc), rot=(math.pi / 2, 0, 0))
    aura("wind", (p.x, cy - 0.02, zc))
    top_t, bot_t = limb_at(pts, half - 0.035), limb_at(pts, -(half - 0.035))
    _BOW_STRING[:] = [(top_t.x, top_t.y, top_t.z), (bot_t.x, bot_t.y, bot_t.z)]
    bow_export("bw_wind_bow", top_t.y)


def build_crescent_bow():
    """Crescente Gêmeo (Mítico): o arco é uma lua crescente de prata, larga no meio e afiada nas pontas; por dentro corre
    a lua gêmea, fina e acesa em azul-claro, presa por pontes de estrela; lua cheia acesa num aro de prata acima da
    mão."""
    m = vcf("bw_crescent", metal=0.5)
    g = vcf("bw_crescent_gem", emit="#bcd0ff", strength=1.0)
    half, back, fl = 0.6, 0.2, 0.5
    pts = bow_curve(half, back, recurve=0.0, n=120)
    silver, silver_l, silver_d, moon = H("#c4ccdc"), H("#f4f8ff"), H("#7a86a0"), H("#bcd0ff")

    def r_of_z(z):   # crescente: largo no meio, afina até a ponta afiada
        t = min(abs(z) / half, 1.0)
        return 0.0035 + 0.024 * (1 - t ** 1.6) ** 0.9

    def silverc(co):
        c = limb_at(pts, co.z)
        k = (c.y - co.y) / max(r_of_z(co.z) * fl, 1e-4)
        return mix(mix(silver_d, silver, 0.7), silver_l, smooth01((k - 0.4) / 0.4))
    tube("Moon", pts, lambda u: r_of_z(-half + 2 * half * u), m, silverc, sides=18, flat=fl)
    # a lua gêmea: arco fino por dentro (lado do arqueiro, +Y), das pontes de estrela
    inner = []
    for i in range(91):
        z = -0.52 + 1.04 * i / 90
        inner.append(limb_at(pts, z) + Vector((0, r_of_z(z) * fl + 0.018 * (1 - (abs(z) / 0.52) ** 2) + 0.004, 0)))
    tube("Twin", inner, lambda u: 0.0028 + 0.003 * math.sin(math.pi * u), g, moon, sides=10)
    for j, z in enumerate((-0.48, -0.32, -0.17, 0.17, 0.32, 0.48)):
        a = limb_at(pts, z) + Vector((0, r_of_z(z) * fl * 0.6, 0))
        b = Vector(inner[int((z + 0.52) / 1.04 * 90)])
        tube("Bridge%d" % j, [a, b], 0.0022, m, silver_l, sides=6)
        star = []
        for i in range(10):
            ang = 2 * math.pi * i / 10
            r = 0.011 if i % 2 == 0 else 0.0045
            star.append((math.cos(ang) * r, math.sin(ang) * r))
        ob = flat("Star%d" % j, star, m, None, th=0.003, bevel=0.0012, step=0.003)
        plane_yz(ob)
        put(ob, silver_l, a.lerp(b, 0.5))
        if abs(z) > 0.4:
            aura("moon", a.lerp(b, 0.5))
    for s in (1, -1):
        tip = limb_at(pts, (half - 0.005) * s)
        aura("moon", tip)
        limb_wrap("Notch%d" % s, pts, (half - 0.06) * s - 0.006, (half - 0.06) * s + 0.006, r_of_z, m, silver_l, turns=1,
                  pad=0.0012, ridge=0.0004, flat=fl)
    limb_wrap("Grip", pts, -0.06, 0.06, r_of_z, m, H("#263052"), turns=12, pad=0.0012, ridge=0.0008, flat=fl)
    # lua cheia acesa num aro de prata, acima da mão, com raios finos
    zc = 0.115
    p = limb_at(pts, zc)
    fy = p.y - r_of_z(zc) * fl - 0.004
    lathe("MoonRing", [(0.0, 0.0), (0.0, 0.019), (0.004, 0.0195), (0.007, 0.0165), (0.007, 0.0)], m, silver_l, seg=24,
          loc=(p.x, fy + 0.003, zc), rot=(math.pi / 2, 0, 0))
    orb("FullMoon", g, moon, (p.x, fy - 0.004, zc), 0.0145, seg=16, sq=0.55)
    rays = []
    for i in range(16):
        a = 2 * math.pi * i / 16
        r = 0.032 if i % 2 == 0 else 0.02
        rays.append((math.cos(a) * r, math.sin(a) * r))
    flat("MoonRays", rays, m, silver, th=0.0025, bevel=0.001, step=0.004, loc=(p.x, fy + 0.006, zc))
    aura("moon", (p.x, fy - 0.02, zc))
    top_t, bot_t = limb_at(pts, half - 0.06), limb_at(pts, -(half - 0.06))
    _BOW_STRING[:] = [(top_t.x, top_t.y, top_t.z), (bot_t.x, bot_t.y, bot_t.z)]
    bow_export("bw_crescent_bow", top_t.y)


def build_root_bow():
    """Raiz-Mãe (Mítico): três raízes trançadas formam cada braço, com musgo; folhas e flores rosadas brotam ao longo;
    cipós pendem das pontas; a semente acesa num ninho de raízes acima da mão; tufos de folhas nas pontas."""
    m = vcf("bw_root", metal=0.0)
    g = vcf("bw_root_gem", emit="#8aff5a", strength=1.0)
    half, back, fl = 0.6, 0.18, 0.8
    pts = bow_curve(half, back, recurve=0.04, n=110)
    bark, bark_d, moss, leafc = H("#6a4a2e"), H("#3e2a1a"), H("#5f8a2e"), H("#6cbf3c")
    pink, pink_l, seed = H("#e86aa0"), H("#ffd0e4"), H("#8aff5a")

    def r_of_z(z):
        t = min(abs(z) / half, 1.0)
        return 0.0105 + 0.0135 * (1 - t) ** 0.7

    def barkc(co):
        g2 = 0.5 + 0.5 * math.sin(math.atan2(co.y, co.x) * 5 + co.z * 6)
        mossy = smooth01((math.sin(co.z * 23 + co.x * 300) - 0.55) / 0.3) * (1 - min(abs(co.z) / half, 1.0))
        return mix(mix(bark_d, bark, g2), moss, 0.85 * mossy)
    # três raízes trançadas em volta da linha do braço (cada uma também afina)
    for k in range(3):
        seg = []
        for i in range(181):
            z = -half + 2 * half * i / 180
            c = limb_at(pts, z)
            a = 2 * math.pi * k / 3 + z * 26
            rr = r_of_z(z) * 0.55
            seg.append(c + Vector((math.cos(a) * rr, math.sin(a) * rr * fl, 0)))
        tube("Root%d" % k, seg, lambda u: r_of_z(-half + 2 * half * u) * 0.58 + 0.001, m, barkc, sides=10)
    tube("Heart", pts, lambda u: r_of_z(-half + 2 * half * u) * 0.5, m, bark_d, sides=8)
    leaves = []
    for s in (1, -1):
        # folhas e flores ao longo do braço, nascendo na superfície
        for j, zz in enumerate((0.2, 0.26, 0.31, 0.37, 0.43, 0.49)):
            p, d = limb_at(pts, zz * s), limb_dir(pts, zz * s).normalized()
            side = Vector((math.cos(zz * 40 + s), -abs(math.sin(zz * 40 + s)) - 0.3, 0)).normalized()
            base = p + side * r_of_z(zz) * 0.85
            if j % 2 == 0:
                dirv = (side * 0.7 + d * 0.7).normalized()
                L = 0.045 + 0.01 * (j % 3)
                lf = flat("Leaf%d%d" % (s, j), leaf_outline(L, 0.016), m, None, th=0.003, bevel=0.002, step=0.007,
                          bend=lambda c, L=L: Vector((c.x, c.y + 0.4 * c.x * c.x, c.z)))
                put(lf, leafc, base, along(dirv))
                leaves.append(base + dirv * L)
            else:
                stem = base + side * 0.012
                tube("Stem%d%d" % (s, j), [p + side * r_of_z(zz) * 0.5, stem], 0.0022, m, moss, sides=6)
                for q in range(5):
                    a = 2 * math.pi * q / 5
                    pe = stem + Vector((math.cos(a) * 0.008, -0.002, math.sin(a) * 0.008))
                    orb("Petal%d%d%d" % (s, j, q), m, pink if q % 2 else pink_l, pe, 0.0065, seg=8, sq=0.55)
                orb("Pistil%d%d" % (s, j), g, H("#ffe066"), stem + Vector((0, -0.004, 0)), 0.004, seg=8)
                aura("leaf", stem + Vector((0, -0.01, 0)))
        # tufo de folhas na ponta e cipó pendendo
        tip, d = limb_at(pts, (half - 0.004) * s), limb_dir(pts, (half - 0.004) * s).normalized()
        for k in range(5):
            a = 2 * math.pi * k / 5
            dirv = (d * 0.75 + Vector((math.cos(a), math.sin(a) * 0.8, 0)) * 0.55).normalized()
            lf = flat("TipLeaf%d%d" % (s, k), leaf_outline(0.05, 0.016), m, None, th=0.003, bevel=0.002, step=0.007,
                      bend=lambda c: Vector((c.x, c.y + 0.4 * c.x * c.x, c.z)))
            put(lf, leafc if k % 2 else moss, tip - d * 0.008, along(dirv))
        aura("leaf", tip + d * 0.03)
        v0 = limb_at(pts, (half - 0.06) * s)
        vine = [v0 + Vector((0.006, -0.004, 0)), v0 + Vector((0.016, -0.014, -0.03 * s)), v0 + Vector((0.012, -0.02, -0.07 * s)),
                v0 + Vector((0.018, -0.016, -0.11 * s))]
        tube("Vine%d" % s, spline(vine, 5), 0.0024, m, moss, sides=6)
        for k in range(3):
            q = Vector(spline(vine, 5)[4 + k * 4])
            lf = flat("VineLeaf%d%d" % (s, k), leaf_outline(0.022, 0.01), m, None, th=0.0025, bevel=0.0015, step=0.006)
            put(lf, leafc, q, (0.4 * k, 0, 1.2 * (k - 1)))
    limb_wrap("Grip", pts, -0.064, 0.064, r_of_z, m, H("#4a3622"), turns=9, pad=0.0016, ridge=0.0012, flat=fl)
    # ninho de raízes com a semente acesa, acima da mão
    zc = 0.115
    p = limb_at(pts, zc)
    cy = p.y - r_of_z(zc) * fl - 0.014
    orb("Seed", g, seed, (p.x, cy, zc), 0.0125, seg=16, sq=1.25)
    for k in range(6):
        a = 2 * math.pi * k / 6
        o = Vector((math.cos(a), 0, math.sin(a)))
        tube("Nest%d" % k, spline([Vector((p.x, p.y - r_of_z(zc) * fl * 0.5, zc)) + o * 0.008,
                                    Vector((p.x, cy + 0.004, zc)) + o * 0.019, Vector((p.x, cy - 0.01, zc)) + o * 0.011], 4),
             lambda u: 0.0034 * (1 - 0.5 * u) + 0.0005, m, bark, sides=6)
    aura("leaf", (p.x, cy - 0.02, zc))
    top_t, bot_t = limb_at(pts, half - 0.03), limb_at(pts, -(half - 0.03))
    _BOW_STRING[:] = [(top_t.x, top_t.y, top_t.z), (bot_t.x, bot_t.y, bot_t.z)]
    bow_export("bw_root_bow", top_t.y)


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
           ("bw_goblin_warbow", build_goblin_warbow), ("bw_storm_bow", build_storm_bow), ("bw_twig_bow", build_twig_bow),
           ("bw_raptor_bow", build_raptor_bow), ("bw_warden_bow", build_warden_bow),
           ("bw_silk_bow", build_silk_bow), ("bw_frostfang_bow", build_frostfang_bow),
           ("bw_lantern_bow", build_lantern_bow), ("bw_crystal_bow", build_crystal_bow),
           ("bw_ossuary_bow", build_ossuary_bow), ("bw_chitin_bow", build_chitin_bow),
           ("bw_ashen_bow", build_ashen_bow), ("bw_yeti_bow", build_yeti_bow),
           ("bw_abyss_bow", build_abyss_bow), ("bw_dawn_bow", build_dawn_bow), ("bw_dragon_bow", build_dragon_bow),
           ("bw_wind_bow", build_wind_bow), ("bw_crescent_bow", build_crescent_bow), ("bw_root_bow", build_root_bow),
           ("bw_arrow", build_arrow)]


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
