# Árvores e flores. Executado por build_assets.py depois de props.py (usa mat/boulder/leaf/join/_lin/
# _mesh_obj de lá).
#
# Estilo: low-poly facetado, copas de tufos convexos com 3 tons pintados pela direção da face
# (topo claro, lado médio, baixo escuro — não depende do giro da árvore no jogo), tronco contínuo
# com raiz alargada e galhos que entram na copa. Uma malha por modelo (poucas superfícies):
# o jogo instancia centenas de árvores e espalha as flores em MultiMesh (ground.gd).
# Frente = -Y, chão em Z = 0, origem no pé do tronco.

# ---------- materiais ----------
t_bark = mat("t_bark", _lin(0.36, 0.25, 0.16), 0.95)
t_bark_dk = mat("t_bark_dark", _lin(0.22, 0.15, 0.10), 0.95)
t_bark_grey = mat("t_bark_grey", _lin(0.42, 0.38, 0.34), 0.95)
t_birch = mat("t_birch", _lin(0.90, 0.88, 0.82), 0.85)
t_birch_mark = mat("t_birch_mark", _lin(0.16, 0.15, 0.14), 0.9)
t_cherry_bark = mat("t_cherry_bark", _lin(0.30, 0.18, 0.16), 0.9)

t_oak = [mat("t_oak_dark", _lin(0.13, 0.32, 0.10), 0.9), mat("t_oak", _lin(0.22, 0.46, 0.14), 0.9),
         mat("t_oak_light", _lin(0.40, 0.62, 0.20), 0.9)]
t_pine = [mat("t_pine_dark", _lin(0.07, 0.24, 0.13), 0.9), mat("t_pine", _lin(0.12, 0.36, 0.18), 0.9),
          mat("t_pine_light", _lin(0.24, 0.50, 0.24), 0.9)]
t_fir = [mat("t_fir_dark", _lin(0.05, 0.18, 0.15), 0.9), mat("t_fir", _lin(0.09, 0.29, 0.24), 0.9),
         mat("t_fir_light", _lin(0.20, 0.42, 0.34), 0.9)]
t_birchleaf = [mat("t_birchleaf_dark", _lin(0.30, 0.46, 0.12), 0.9), mat("t_birchleaf", _lin(0.50, 0.66, 0.20), 0.9),
               mat("t_birchleaf_light", _lin(0.72, 0.80, 0.30), 0.9)]
t_maple = [mat("t_maple_dark", _lin(0.62, 0.16, 0.06), 0.85), mat("t_maple", _lin(0.88, 0.38, 0.08), 0.85),
           mat("t_maple_light", _lin(1.00, 0.66, 0.16), 0.85)]
t_blossom = [mat("t_blossom_dark", _lin(0.84, 0.48, 0.62), 0.85), mat("t_blossom", _lin(0.96, 0.66, 0.78), 0.85),
             mat("t_blossom_light", _lin(1.00, 0.86, 0.92), 0.85)]

f_stem = mat("f_stem", _lin(0.26, 0.50, 0.16), 0.85)
f_leaf = mat("f_leaf", _lin(0.20, 0.44, 0.14), 0.85)
f_red = mat("f_red", _lin(0.90, 0.10, 0.10), 0.6)
f_yellow = mat("f_yellow", _lin(1.00, 0.82, 0.12), 0.6)
f_pink = mat("f_pink", _lin(0.98, 0.50, 0.70), 0.6)
f_white = mat("f_white", _lin(0.97, 0.96, 0.92), 0.6)
f_purple = mat("f_purple", _lin(0.56, 0.38, 0.90), 0.6)
f_purple_dk = mat("f_purple_dark", _lin(0.38, 0.22, 0.70), 0.6)
f_center = mat("f_center", _lin(0.95, 0.70, 0.10), 0.6)
f_black = mat("f_black", _lin(0.08, 0.06, 0.05), 0.7)
f_seed = mat("f_seed", _lin(0.30, 0.18, 0.08), 0.8)
f_blue = mat("f_blue", _lin(0.35, 0.50, 1.00), 0.6)


# ---------- helpers ----------
def tr_tone(ob, mats, hi=0.5, lo=-0.25, rnd=None, flip=0.0):
    """Pinta as faces por direção: baixo (normal.z < lo) escuro, topo (> hi) claro, resto médio.
    flip > 0 sorteia algumas faces para o tom vizinho (quebra a regularidade)."""
    me = ob.data
    base = len(me.materials)
    for m in mats:
        me.materials.append(m)
    for p in me.polygons:
        z = p.normal.z
        k = 0 if z < lo else (2 if z > hi else 1)
        if rnd is not None and rnd.random() < flip:
            k = max(0, min(2, k + rnd.choice((-1, 1))))
        p.material_index = base + k
    return ob


def _drop_first_slot(ob):
    """tr_tone() acrescenta os materiais; o slot 0 (do criador) fica sem faces — remove."""
    me = ob.data
    if len(me.materials) > 1 and not any(p.material_index == 0 for p in me.polygons):
        for p in me.polygons:
            p.material_index -= 1
        me.materials.pop(index=0)


def tr_clump(name, c, size, mats, seed, n=16, flip=0.12):
    """Tufo de folhagem: casco convexo facetado, 3 tons."""
    ob = boulder(name, c, size, mats[1], n=n, seed=seed, flat_bottom=False)
    tr_tone(ob, mats, rnd=random.Random(seed), flip=flip)
    _drop_first_slot(ob)
    return ob


def tr_tube(name, pts, radii, material, seg=7, cap=True, mark=None, mark_p=0.0, seed=1, twist=0.0):
    """Tronco/galho contínuo: anéis ao longo de uma polilinha (cada anel perpendicular à direção).
    mark=(material) pinta ao acaso uma fração mark_p dos quadriláteros (manchas da bétula)."""
    rnd = random.Random(seed)
    pts = [Vector(p) for p in pts]
    bm = bmesh.new()
    rings = []
    ref = Vector((1, 0, 0))
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        u = (ref - d * ref.dot(d))
        if u.length < 1e-4:
            u = Vector((0, 1, 0)) - d * d.y
        u.normalize()
        v = d.cross(u)
        ref = u
        ring = []
        for k in range(seg):
            a = 2 * PI * k / seg + twist * i
            r = radii[i] * (1 + rnd.uniform(-0.08, 0.08))
            ring.append(bm.verts.new(p + (u * math.cos(a) + v * math.sin(a)) * r))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(seg):
            j = (k + 1) % seg
            f = bm.faces.new((rings[i][k], rings[i][j], rings[i + 1][j], rings[i + 1][k]))
            if mark is not None and rnd.random() < mark_p:
                f.material_index = 1
    if cap:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _mesh_obj(name, bm, [material, mark] if mark is not None else material)


def tr_limb(name, a, b, r0, r1, material, bend=(0, 0, 0.0), n=4, seg=5, **kw):
    """Galho de a até b com curva (bend somado no meio)."""
    a, b, bend = Vector(a), Vector(b), Vector(bend)
    pts, rr = [], []
    for i in range(n + 1):
        t = i / n
        pts.append(a.lerp(b, t) + bend * (4 * t * (1 - t)))
        rr.append(r0 + (r1 - r0) * t)
    return tr_tube(name, pts, rr, material, seg=seg, **kw)


def tr_trunk(name, h, r0, r1, material, lean=(0, 0), flare=1.6, seg=8, n=6, seed=1, **kw):
    """Tronco com raiz alargada (anéis de baixo mais largos) e inclinação suave."""
    rnd = random.Random(seed)
    pts, rr = [], []
    for i in range(n + 1):
        t = i / n
        off = Vector((lean[0], lean[1], 0)) * (t * t) + Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), 0)) * 0.03 * (i > 0)
        pts.append(Vector((0, 0, -0.05 + (h + 0.05) * t)) + off)
        r = r0 + (r1 - r0) * t
        if t < 0.2:
            r *= 1 + (flare - 1) * (1 - t / 0.2) ** 2
        rr.append(r)
    return tr_tube(name, pts, rr, material, seg=seg, seed=seed, **kw)


def tr_roots(objs, name, r, material, n=5, seed=1, length=0.38):
    """Raízes que saem da base e afundam no chão (quebram o 'poste espetado no chão')."""
    rnd = random.Random(seed)
    for k in range(n):
        a = k / n * 2 * PI + rnd.uniform(-0.3, 0.3)
        d = Vector((math.cos(a), math.sin(a), 0))
        L = length * rnd.uniform(0.75, 1.2)
        objs.append(tr_limb("%s_Root%d" % (name, k), d * r * 0.3 + Vector((0, 0, 0.22)), d * (r + L) + Vector((0, 0, -0.1)),
                         r * 0.55, r * 0.22, material, bend=(0, 0, 0.1), n=3, seg=5, cap=False))


def tr_crown(objs, name, center, rx, rz, mats, count, seed, s_min=0.75, s_max=1.15, base=1.0, n=16, squash=0.85,
          top_bias=0.25):
    """Copa de 'count' tufos espalhados num elipsoide (mais tufos em cima e na borda) + núcleo."""
    rnd = random.Random(seed)
    c = Vector(center)
    objs.append(tr_clump(name + "_Core", c, (rx * 1.5, rx * 1.5, rz * 1.4), mats, seed, n=n + 4))
    for k in range(count):
        a = k / count * 2 * PI * 2.618 + rnd.uniform(-0.4, 0.4)   # espiral áurea: cobre a volta inteira
        el = rnd.uniform(-0.35, 1.0) * (1 - top_bias) + top_bias * rnd.uniform(0.2, 1.0)
        el = max(-0.5, min(1.0, el))
        ce = math.cos(el * PI / 2)
        p = c + Vector((math.cos(a) * ce * rx, math.sin(a) * ce * rx, math.sin(el * PI / 2) * rz))
        s = base * rnd.uniform(s_min, s_max)
        objs.append(tr_clump("%s_C%d" % (name, k), p, (s, s * rnd.uniform(0.85, 1.1), s * squash), mats, seed * 31 + k, n=n))


def tr_finish(objs, name, fname):
    o = join(objs, name)
    me = o.data
    me.calc_loop_triangles()
    print("TRIS", fname, len(me.loop_triangles), "MATS", len(me.materials), flush=True)
    export(fname)


# ======================================================== CARVALHO
def build_tree_oak():
    objs = []
    objs.append(tr_trunk("Trunk", 2.3, 0.34, 0.2, t_bark, lean=(0.12, 0.05), seed=3))
    tr_roots(objs, "Oak", 0.34, t_bark, n=5, seed=4)
    top = Vector((0.12, 0.05, 2.25))
    # três braços grossos que abrem a copa
    arms = [((1.15, 0.3, 3.3), (0.1, 0, 0.25)), ((-0.95, 0.55, 3.45), (0, 0, 0.2)), ((0.05, -1.05, 3.6), (0, 0, 0.2))]
    for i, (b, bend) in enumerate(arms):
        objs.append(tr_limb("Arm%d" % i, top - Vector((0, 0, 0.25)), b, 0.17, 0.07, t_bark, bend=bend, n=4, seg=6))
    objs.append(tr_limb("Branch", (0.08, 0.04, 1.55), (-1.05, -0.35, 2.2), 0.09, 0.035, t_bark, bend=(0, 0, 0.18), n=3, seg=5))
    tr_crown(objs, "Oak", (0.05, 0.1, 3.85), 1.7, 1.0, t_oak, 15, seed=7, base=1.75, s_min=0.85, s_max=1.2)
    # tufo baixo no galho solto e um no topo (silhueta irregular)
    objs.append(tr_clump("Low", (-1.15, -0.4, 2.35), (1.0, 0.9, 0.75), t_oak, 61))
    objs.append(tr_clump("Top", (0.25, -0.1, 4.9), (1.9, 1.8, 1.3), t_oak, 63))
    tr_finish(objs, "TreeOak", "tree_oak")


# ======================================================== CONÍFERAS
def _tier(name, z, r, h, mats, seed, pts=9, droop=0.35, under=0.18, jag=0.62):
    """Saia de galhos de conífera: cone com borda em estrela (pontas caídas) e fundo fechado."""
    rnd = random.Random(seed)
    bm = bmesh.new()
    apex = bm.verts.new((rnd.uniform(-0.04, 0.04), rnd.uniform(-0.04, 0.04), z + h))
    ring = []
    off = rnd.uniform(0, 2 * PI)
    for k in range(pts * 2):
        a = off + k / (pts * 2) * 2 * PI
        tip = k % 2 == 0
        rr = r * (rnd.uniform(0.9, 1.08) if tip else jag * rnd.uniform(0.95, 1.05))
        zz = z - (droop * r * rnd.uniform(0.8, 1.2) if tip else -0.08 * h)
        ring.append(bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, zz)))
    bottom = bm.verts.new((0, 0, z + h * under))
    n = len(ring)
    for k in range(n):
        j = (k + 1) % n
        bm.faces.new((apex, ring[k], ring[j]))
        bm.faces.new((ring[j], ring[k], bottom))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = _mesh_obj(name, bm, mats[1])
    tr_tone(ob, mats, hi=0.62, lo=-0.1, rnd=rnd, flip=0.1)
    _drop_first_slot(ob)
    return ob


def build_tree_pine():
    objs = [tr_trunk("Trunk", 4.6, 0.24, 0.06, t_bark_dk, flare=1.7, seed=11, seg=7)]
    tr_roots(objs, "Pine", 0.24, t_bark_dk, n=4, seed=12, length=0.4)
    # saias: largas embaixo, afinando até a ponta
    tiers = [(1.25, 1.75, 1.35), (2.05, 1.5, 1.25), (2.8, 1.22, 1.15), (3.5, 0.92, 1.05), (4.15, 0.62, 0.95)]
    for i, (z, r, h) in enumerate(tiers):
        objs.append(_tier("Tier%d" % i, z, r, h, t_pine, seed=40 + i, pts=9 - i // 2, droop=0.32))
    objs.append(_tier("Tip", 4.75, 0.32, 0.8, t_pine, seed=49, pts=5, droop=0.2))
    tr_finish(objs, "TreePine", "tree_pine")


def build_tree_fir():
    """Abeto alto e estreito, verde-azulado escuro (floresta densa e encostas)."""
    objs = [tr_trunk("Trunk", 6.4, 0.22, 0.05, t_bark_dk, flare=1.6, seed=21, seg=7)]
    tr_roots(objs, "Fir", 0.22, t_bark_dk, n=4, seed=22, length=0.35)
    n = 8
    for i in range(n):
        t = i / (n - 1)
        z = 0.9 + t * 5.3
        r = 1.35 * (1 - t) ** 0.9 + 0.22
        objs.append(_tier("Tier%d" % i, z, r, 0.95 - 0.25 * t, t_fir, seed=60 + i, pts=8 - i // 3, droop=0.45, jag=0.55))
    objs.append(_tier("Tip", 6.85, 0.2, 0.7, t_fir, seed=69, pts=5, droop=0.15))
    tr_finish(objs, "TreeFir", "tree_fir")


# ======================================================== BÉTULA
def build_tree_birch():
    objs = []
    rnd = random.Random(31)
    # dois troncos finos e brancos com manchas escuras, levemente abertos
    for i, (lean, h, r) in enumerate((((0.35, 0.1), 5.0, 0.15), ((-0.4, -0.25), 4.2, 0.12))):
        objs.append(tr_trunk("Trunk%d" % i, h, r, 0.045, t_birch, lean=lean, flare=1.35, seed=32 + i, seg=7, n=8,
                          mark=t_birch_mark, mark_p=0.22))
    objs.append(tr_limb("Branch0", (0.08, 0.02, 2.6), (0.95, -0.3, 3.5), 0.05, 0.02, t_birch, bend=(0, 0, 0.12), n=3))
    objs.append(tr_limb("Branch1", (-0.12, -0.05, 2.4), (-1.0, -0.5, 3.0), 0.045, 0.02, t_birch, bend=(0, 0, 0.1), n=3))
    objs.append(tr_limb("Branch2", (0.2, 0.05, 3.6), (0.5, 0.9, 4.3), 0.04, 0.018, t_birch, n=3))
    # copa leve: tufos menores e separados ao longo da metade de cima (deixa ver o céu entre eles)
    spots = [(0.4, 0.1, 5.0, 1.1), (0.85, -0.3, 4.2, 0.95), (-0.15, 0.4, 4.4, 1.0), (-0.5, -0.3, 3.75, 0.95),
             (-1.0, -0.5, 3.15, 0.8), (0.95, -0.35, 3.45, 0.8), (0.5, 0.9, 4.35, 0.85), (0.1, -0.5, 4.75, 0.85),
             (-0.6, 0.2, 4.9, 0.8), (0.3, 0.3, 5.6, 0.75)]
    for k, (x, y, z, s) in enumerate(spots):
        objs.append(tr_clump("C%d" % k, (x, y, z), (s * 1.35, s * 1.25, s * 1.5), t_birchleaf, 300 + k, n=14, flip=0.18))
    tr_roots(objs, "Birch", 0.15, t_birch, n=3, seed=33, length=0.3)
    tr_finish(objs, "TreeBirch", "tree_birch")


# ======================================================== BORDO DE OUTONO
def build_tree_maple():
    objs = [tr_trunk("Trunk", 2.0, 0.3, 0.17, t_bark_grey, lean=(-0.08, 0.06), seed=51)]
    tr_roots(objs, "Maple", 0.3, t_bark_grey, n=5, seed=52, length=0.45)
    top = Vector((-0.08, 0.06, 1.9))
    for i, b in enumerate(((0.9, 0.2, 3.1), (-0.85, 0.45, 3.2), (0.0, -0.95, 3.3), (0.1, 0.4, 3.6))):
        objs.append(tr_limb("Arm%d" % i, top, b, 0.13, 0.05, t_bark_grey, bend=(0, 0, 0.2), n=4, seg=6))
    # copa redonda e cheia, um pouco mais alta que larga
    tr_crown(objs, "Maple", (0.0, 0.1, 3.6), 1.25, 1.05, t_maple, 14, seed=53, base=1.65, squash=0.95, top_bias=0.1, s_min=0.85)
    objs.append(tr_clump("Top", (0.1, 0.0, 4.8), (1.7, 1.6, 1.3), t_maple, 54))
    # folhas caídas em volta do pé
    for k in range(10):
        a = rnd_a = (k * 2.39996) % (2 * PI)
        d = 0.6 + (k * 0.37) % 1.4
        objs.append(leaf("Fallen%d" % k, (math.cos(a) * d, math.sin(a) * d, 0.02), a * 3.1, -0.05, 0.16, 0.13,
                         t_maple[k % 3], droop=0.0, fold=0.05))
    tr_finish(objs, "TreeMaple", "tree_maple")


# ======================================================== CEREJEIRA EM FLOR
def build_tree_cherry():
    objs = []
    # tronco baixo e torto que se divide cedo em galhos longos e abertos
    objs.append(tr_tube("Trunk", [(0, 0, -0.05), (0.04, 0.0, 0.4), (0.18, 0.05, 0.9), (0.12, -0.04, 1.35)],
                     [0.32, 0.22, 0.19, 0.16], t_cherry_bark, seg=7, seed=71))
    tr_roots(objs, "Cherry", 0.26, t_cherry_bark, n=4, seed=72, length=0.4)
    base = Vector((0.12, -0.04, 1.3))
    tips = [(1.7, 0.4, 2.6), (-1.6, 0.6, 2.7), (0.3, -1.7, 2.8), (-0.6, -1.0, 3.2), (0.7, 1.3, 3.0)]
    for i, b in enumerate(tips):
        objs.append(tr_limb("Arm%d" % i, base, b, 0.12, 0.04, t_cherry_bark, bend=(0, 0, 0.35), n=4, seg=6))
    # flores em nuvens achatadas na ponta de cada galho + o miolo
    for i, b in enumerate(tips):
        b = Vector(b)
        objs.append(tr_clump("Bloom%d" % i, b + Vector((0, 0, 0.25)), (1.9, 1.8, 1.15), t_blossom, 80 + i, n=16))
        objs.append(tr_clump("BloomB%d" % i, b * 0.65 + Vector((0, 0, 1.1)), (1.5, 1.4, 1.0), t_blossom, 90 + i, n=12))
    objs.append(tr_clump("Core", (0.1, 0.0, 3.25), (2.8, 2.6, 1.5), t_blossom, 99, n=18))
    # pétalas caídas
    for k in range(14):
        a = (k * 2.39996) % (2 * PI)
        d = 0.5 + (k * 0.53) % 2.0
        objs.append(leaf("Petal%d" % k, (math.cos(a) * d, math.sin(a) * d, 0.015), a * 2.3, 0.0, 0.08, 0.07,
                         t_blossom[1 + k % 2], droop=0.0, fold=0.05))
    tr_finish(objs, "TreeCherry", "tree_cherry")


# ======================================================== FLORES (MultiMesh em ground.gd)
# Touceiras pequenas, origem no chão, uma malha só. Pouca geometria: aparecem às centenas.
def _stem(name, base, top, r=0.012):
    return tr_limb(name, base, top, r, r * 0.8, f_stem, bend=(0.02, 0, 0), n=2, seg=4, cap=False)


def _blade(objs, name, n, seed, h=(0.18, 0.3), w=0.05, material=None):
    rnd = random.Random(seed)
    for k in range(n):
        a = k / n * 2 * PI + rnd.uniform(-0.3, 0.3)
        objs.append(leaf("%s%d" % (name, k), (0, 0, 0.0), a, rnd.uniform(0.9, 1.2), rnd.uniform(*h), w,
                         material or f_leaf, droop=0.12, fold=0.25))


def _cup(name, c, r, h, material, n=5, seed=1, open_=0.3):
    """Flor em taça (tulipa, papoula): pétalas como faces de um cone aberto, com fundo."""
    rnd = random.Random(seed)
    bm = bmesh.new()
    c = Vector(c)
    bot = bm.verts.new(c)
    ring_lo, ring_hi = [], []
    for k in range(n * 2):
        a = k / (n * 2) * 2 * PI + rnd.uniform(-0.05, 0.05)
        tip = k % 2 == 0
        ring_lo.append(bm.verts.new(c + Vector((math.cos(a) * r, math.sin(a) * r, h * 0.45))))
        rr = r * (1 + open_) * (1.0 if tip else 0.8)
        ring_hi.append(bm.verts.new(c + Vector((math.cos(a) * rr, math.sin(a) * rr, h * (1.0 if tip else 0.75)))))
    m = len(ring_lo)
    for k in range(m):
        j = (k + 1) % m
        bm.faces.new((bot, ring_lo[j], ring_lo[k]))
        bm.faces.new((ring_lo[k], ring_lo[j], ring_hi[j], ring_hi[k]))
    return _mesh_obj(name, bm, material)


def _daisy(objs, name, c, r, petal_mat, center_mat, n=8, tilt=0.15, seed=1):
    """Margarida/girassol: anel de pétalas planas em volta de um miolo."""
    rnd = random.Random(seed)
    c = Vector(c)
    for k in range(n):
        a = k / n * 2 * PI + rnd.uniform(-0.08, 0.08)
        objs.append(leaf("%s_P%d" % (name, k), c, a - PI / 2, tilt, r, r * 0.42, petal_mat, droop=0.08, fold=0.08))
    objs.append(lathe(name + "_Mid", [(r * 0.38, -0.01), (r * 0.36, 0.02), (r * 0.12, 0.045)], center_mat, seg=7,
                      loc=c, cap_bot=True))


def build_flower_tulips():
    objs = []
    rnd = random.Random(101)
    cols = [f_red, f_yellow, f_pink, f_red, f_white, f_yellow, f_red]
    for k in range(7):
        a = k / 7 * 2 * PI * 1.618
        d = 0.06 + 0.13 * ((k * 0.61) % 1)
        b = Vector((math.cos(a) * d, math.sin(a) * d, 0))
        h = rnd.uniform(0.32, 0.45)
        top = b + Vector((rnd.uniform(-0.04, 0.04), rnd.uniform(-0.04, 0.04), h))
        objs.append(_stem("Stem%d" % k, b, top))
        objs.append(_cup("Cup%d" % k, top, 0.05, 0.11, cols[k], n=3, seed=110 + k, open_=0.15))
    _blade(objs, "Leaf", 6, 102, h=(0.2, 0.3), w=0.07)
    tr_finish(objs, "Tulips", "flower_tulips")


def build_flower_poppies():
    objs = []
    rnd = random.Random(121)
    for k in range(6):
        a = k * 2.4
        d = 0.05 + 0.16 * ((k * 0.43) % 1)
        b = Vector((math.cos(a) * d, math.sin(a) * d, 0))
        top = b + Vector((rnd.uniform(-0.07, 0.07), rnd.uniform(-0.07, 0.07), rnd.uniform(0.3, 0.48)))
        objs.append(_stem("Stem%d" % k, b, top, r=0.009))
        objs.append(_cup("Cup%d" % k, top, 0.06, 0.06, f_red, n=4, seed=130 + k, open_=0.7))
        objs.append(boulder("Eye%d" % k, top + Vector((0, 0, 0.03)), (0.03, 0.03, 0.025), f_black, n=6, seed=140 + k,
                            flat_bottom=False))
    _blade(objs, "Leaf", 5, 122, h=(0.12, 0.2), w=0.05)
    tr_finish(objs, "Poppies", "flower_poppies")


def build_flower_daisies():
    objs = []
    rnd = random.Random(151)
    for k in range(6):
        a = k * 2.4 + 0.3
        d = 0.04 + 0.15 * ((k * 0.57) % 1)
        b = Vector((math.cos(a) * d, math.sin(a) * d, 0))
        top = b + Vector((rnd.uniform(-0.05, 0.05), rnd.uniform(-0.05, 0.05), rnd.uniform(0.18, 0.3)))
        objs.append(_stem("Stem%d" % k, b, top, r=0.008))
        _daisy(objs, "Daisy%d" % k, top, 0.075, f_white, f_center, n=9, tilt=rnd.uniform(0.25, 0.6), seed=160 + k)
    _blade(objs, "Leaf", 7, 152, h=(0.08, 0.14), w=0.04)
    tr_finish(objs, "Daisies", "flower_daisies")


def build_flower_lavender():
    objs = []
    rnd = random.Random(171)
    _blade(objs, "Leaf", 10, 172, h=(0.18, 0.3), w=0.03, material=mat("f_sage", _lin(0.42, 0.55, 0.40), 0.85))
    for k in range(8):
        a = k * 2.4
        tilt = rnd.uniform(0.05, 0.35)
        b = Vector((math.cos(a) * 0.04, math.sin(a) * 0.04, 0))
        dirv = Vector((math.cos(a) * math.sin(tilt), math.sin(a) * math.sin(tilt), math.cos(tilt)))
        h = rnd.uniform(0.42, 0.62)
        top = b + dirv * h
        objs.append(_stem("Stem%d" % k, b, top, r=0.007))
        # espiga: 3–4 gomos facetados empilhados, mais finos na ponta
        for j in range(3):
            t = 0.66 + j * 0.15
            s = 0.065 * (1.0 - j * 0.15)
            objs.append(boulder("Bud%d_%d" % (k, j), b + dirv * h * t, (s, s, s * 1.6), (f_purple, f_purple_dk)[(j + k) % 2],
                                n=6, seed=180 + k * 4 + j, flat_bottom=False))
    tr_finish(objs, "Lavender", "flower_lavender")


def build_flower_bluebells():
    objs = []
    rnd = random.Random(191)
    for k in range(5):
        a = k * 2.4
        b = Vector((math.cos(a) * 0.08, math.sin(a) * 0.08, 0))
        tip = b + Vector((math.cos(a) * 0.12, math.sin(a) * 0.12, rnd.uniform(0.25, 0.33)))
        objs.append(tr_limb("Stem%d" % k, b, tip, 0.008, 0.005, f_stem, bend=(0, 0, 0.08), n=3, seg=4, cap=False))
        # sininhos pendurados ao longo do arco
        for j in range(3):
            t = 0.55 + j * 0.2
            p = b.lerp(tip, t) + Vector((0, 0, 0.08 * 4 * t * (1 - t) - 0.03))
            objs.append(_cup("Bell%d_%d" % (k, j), p, 0.03, -0.065, f_blue, n=3, seed=200 + k * 3 + j, open_=0.4))
    _blade(objs, "Leaf", 6, 192, h=(0.16, 0.24), w=0.04)
    tr_finish(objs, "Bluebells", "flower_bluebells")


def build_flower_sunflower():
    """Girassol alto (1,5 m): perto da horta e das casas, não espalhado."""
    objs = []
    rnd = random.Random(211)
    heads = [((0, 0, 0), (0.05, -0.05, 1.55), 0.17), ((0.18, 0.08, 0), (0.28, -0.02, 1.25), 0.13),
             ((-0.15, 0.1, 0), (-0.25, 0.0, 1.05), 0.12)]
    for k, (b, t, r) in enumerate(heads):
        b, t = Vector(b), Vector(t)
        objs.append(tr_limb("Stem%d" % k, b, t, 0.025, 0.016, f_stem, bend=(0, -0.05, 0), n=3, seg=5))
        for j in range(3):
            z = 0.3 + j * 0.35
            if z < t.z - 0.2:
                objs.append(leaf("Leaf%d_%d" % (k, j), b.lerp(t, z / t.z), j * 2.1 + k, 0.4, 0.34, 0.24, f_leaf,
                                 droop=0.35, fold=0.2))
        # cabeça virada para frente (-Y) e um pouco para cima
        head = []
        _daisy(head, "Head%d" % k, Vector((0, 0, 0)), r * 1.25, f_yellow, f_seed, n=12, tilt=0.1, seed=220 + k)
        h = join(head, "Head%d" % k)
        h.data.transform(Euler((-1.2, 0, rnd.uniform(-0.3, 0.3))).to_matrix().to_4x4())
        h.data.transform(Matrix.Translation(t))
        objs.append(h)
    tr_finish(objs, "Sunflower", "flower_sunflower")


TREE_BUILDERS = {
    "tree_oak": build_tree_oak, "tree_pine": build_tree_pine, "tree_fir": build_tree_fir,
    "tree_birch": build_tree_birch, "tree_maple": build_tree_maple, "tree_cherry": build_tree_cherry,
    "flower_tulips": build_flower_tulips, "flower_poppies": build_flower_poppies,
    "flower_daisies": build_flower_daisies, "flower_lavender": build_flower_lavender,
    "flower_bluebells": build_flower_bluebells, "flower_sunflower": build_flower_sunflower,
}
