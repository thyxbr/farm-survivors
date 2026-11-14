# Construções da Defesa da Cidade (prefeitura, fazenda, mercado, quartel, muro, portão, estacas e
# as três torres), uma versão por nível. Executado por build_assets.py depois de props.py
# (usa mat/part/hull/export/clear e bx/lathe/beam/boulder/leaf/join/Bag de lá).
#
# Saída: assets/models/buildings/<tipo>_<nível>.glb; as torres têm também <tipo>_turret_<nível>.glb
# (a parte que gira para o alvo, com a origem no piso onde ela fica).
# Convenções: frente (porta) em -Y, chão em Z=0, pegada centrada na origem com o tamanho de
# ColonyData.BUILDINGS[tipo].size (x = largura, y = profundidade).
# Estilo: low-poly facetado, blocos e tábuas separados com chanfro de 1 segmento, juntas escuras.
os.makedirs(OUT + "buildings", exist_ok=True)

b_stone = mat("b_stone", (0.30, 0.29, 0.27), 0.95)
b_stone_lt = mat("b_stone_light", (0.42, 0.40, 0.36), 0.95)
b_stone_dk = mat("b_stone_dark", (0.17, 0.165, 0.16), 0.95)
b_stone_cold = mat("b_stone_cold", (0.22, 0.22, 0.25), 0.95)      # nível 3: pedra azulada
b_mortar = mat("b_mortar", (0.07, 0.065, 0.06), 1.0)
b_plaster = mat("b_plaster", (0.66, 0.56, 0.40), 0.95)
b_thatch = mat("b_thatch", (0.52, 0.38, 0.14), 0.95)
b_thatch_dk = mat("b_thatch_dark", (0.33, 0.23, 0.08), 0.95)
b_blue = mat("b_blue", (0.04, 0.09, 0.38), 0.85)
b_blue_dk = mat("b_blue_dark", (0.02, 0.05, 0.22), 0.85)
b_red = mat("b_red", (0.42, 0.05, 0.03), 0.85)
b_cloth_y = mat("b_cloth_yellow", (0.78, 0.55, 0.14), 0.9)
b_cloth_w = mat("b_cloth_white", (0.75, 0.70, 0.60), 0.9)
b_glass = mat("b_glass", (0.20, 0.33, 0.45), 0.2, 0.0, emit=(0.95, 0.72, 0.35), strength=0.6)
b_arcane = mat("b_arcane", (0.35, 0.75, 1.0), 0.2, 0.0, emit=(0.4, 0.8, 1.0), strength=4.0)
b_arcane_win = mat("b_arcane_window", (0.3, 0.5, 0.9), 0.2, 0.0, emit=(0.45, 0.6, 1.0), strength=1.6)
b_violet = mat("b_violet", (0.14, 0.06, 0.28), 0.8)
b_violet_lt = mat("b_violet_light", (0.26, 0.14, 0.48), 0.8)
b_mage_st = mat("b_mage_stone", (0.25, 0.24, 0.30), 0.95)
b_mage_st_dk = mat("b_mage_stone_dark", (0.14, 0.13, 0.18), 0.95)
b_soil = mat("b_soil", (0.17, 0.10, 0.05), 1.0)
b_soil_lt = mat("b_soil_light", (0.25, 0.16, 0.08), 1.0)
b_skin = mat("b_skin", (0.80, 0.55, 0.40), 0.8)
b_tunic = mat("b_tunic", (0.12, 0.25, 0.08), 0.9)
b_hood = mat("b_hood", (0.08, 0.16, 0.05), 0.9)
b_straw = mat("b_straw", (0.72, 0.56, 0.22), 0.95)
b_apple = mat("b_apple", (0.55, 0.06, 0.04), 0.6)
b_orange = mat("b_orange", (0.85, 0.35, 0.04), 0.6)
b_cabbage = mat("b_cabbage", (0.25, 0.50, 0.12), 0.8)
b_brazier = mat("b_brazier", (1.0, 0.45, 0.05), 0.5, 0.0, emit=(1.0, 0.45, 0.05), strength=8.0)
CROP = [mat("b_crop1", (0.22, 0.45, 0.08), 0.9), mat("b_crop2", (0.45, 0.50, 0.10), 0.9),
        mat("b_crop3", (0.78, 0.58, 0.14), 0.9)]


def _pick(rnd, base, lt, dk):
    r = rnd.random()
    return dk if r < 0.25 else (lt if r > 0.8 else base)


def _bexport(bag, name, fname):
    join(bag.items, name)
    export("buildings/" + fname)


# ================================================================ peças comuns
def courses(bag, rnd, x0, x1, y, depth, z0, z1, mats, axis="x", hmin=0.36, hmax=0.5, wmin=0.55, wmax=1.05,
            bev=0.04, core=True):
    """Pano de alvenaria: fiadas desencontradas de blocos cortadas em x0..x1 (ao longo de 'axis'),
    espessura 'depth' centrada em y. Núcleo escuro atrás deixa as juntas aparentes."""
    base, lt, dk = mats

    def put(name, u, v, z, su, sv, sz, m, rot_z=0.0):
        if axis == "x":
            return bag.add(bx(name, (u, v, z), (su, sv, sz), m, rot=(0, 0, rot_z), bev=bev))
        return bag.add(bx(name, (v, u, z), (sv, su, sz), m, rot=(0, 0, rot_z), bev=bev))

    if core:
        put(bag.nm("Core"), (x0 + x1) / 2, y, (z0 + z1) / 2, x1 - x0 - 0.02, depth - 0.12, z1 - z0 - 0.02, b_mortar)
    z, row = z0, 0
    while z < z1 - 0.06:
        h = rnd.uniform(hmin, hmax)
        if z1 - (z + h) < hmin * 0.6:
            h = z1 - z
        x = x0 - (rnd.uniform(0.2, 0.4) if row % 2 else 0.0)
        while x < x1 - 0.03:
            w = rnd.uniform(wmin, wmax)
            a, b = max(x, x0), min(x + w, x1)
            if b - a > 0.14:
                put(bag.nm("Block"), (a + b) / 2, y + rnd.uniform(-0.015, 0.015), z + h / 2, b - a - 0.035,
                    depth * rnd.uniform(0.98, 1.03), h - 0.035, _pick(rnd, base, lt, dk), rnd.uniform(-0.012, 0.012))
            x += w
        z += h
        row += 1


def tower_ring(bag, rnd, r0, r1, z0, z1, n, depth, mats, hmin=0.38, hmax=0.5, bev=0.035, cx=0.0, cy=0.0, skip=None):
    """Torre redonda de blocos: n blocos por fiada, raio r0 embaixo e r1 em cima (talude).
    skip(ângulo, z) -> True deixa o bloco de fora (vão de porta/seteira)."""
    base, lt, dk = mats
    bag.add(lathe(bag.nm("RingCore"), [(min(r0, r1) - depth * 0.4 + (r0 - min(r0, r1)), z0),
                                       (r1 - depth * 0.4, z1)], b_mortar, seg=n, loc=(cx, cy, 0)))
    z, row = z0, 0
    while z < z1 - 0.06:
        h = rnd.uniform(hmin, hmax)
        if z1 - (z + h) < hmin * 0.6:
            h = z1 - z
        zm = z + h / 2
        r = r0 + (r1 - r0) * (zm - z0) / (z1 - z0)
        off = (0.5 if row % 2 else 0.0) + rnd.uniform(-0.08, 0.08)
        w = 2 * PI * r / n
        for i in range(n):
            a = 2 * PI * (i + off) / n
            if skip and skip(a, zm):
                continue
            rr = r - depth / 2 + 0.02
            bag.add(bx(bag.nm("RBlock"), (cx + math.cos(a) * rr, cy + math.sin(a) * rr, zm),
                       (depth, w * rnd.uniform(0.9, 0.97), h - 0.035), _pick(rnd, base, lt, dk),
                       rot=(0, 0, a), bev=bev))
        z += h
        row += 1


def merlons(bag, r, z, n, size, m, cx=0.0, cy=0.0, rot0=0.0, cap=None):
    for i in range(n):
        a = rot0 + 2 * PI * i / n
        p = (cx + math.cos(a) * r, cy + math.sin(a) * r, z + size[2] / 2)
        bag.add(bx(bag.nm("Merlon"), p, size, m, rot=(0, 0, a), bev=0.04))
        if cap:
            bag.add(bx(bag.nm("MerlonCap"), (p[0], p[1], z + size[2] + 0.04), (size[0] + 0.08, size[1] + 0.08, 0.08),
                       cap, rot=(0, 0, a), bev=0.02))


def cone_roof(bag, z, R, H, m, seg=8, rot=0.0, cx=0.0, cy=0.0, band=None, finial=True, flare=0.12, wobble=0.0):
    """Telhado cônico com beiral virado e ponteira."""
    prof = [(R + flare, z), (R, z + 0.2), (R * 0.62, z + H * 0.45), (R * 0.25, z + H * 0.8), (0.0, z + H)]
    bag.add(lathe(bag.nm("Roof"), prof, m, seg=seg, loc=(cx, cy, 0), rot=(0, 0, rot), wobble=wobble, seed=7))
    if band:
        bag.add(lathe(bag.nm("RoofBand"), [(R + flare + 0.03, z - 0.02), (R + 0.03, z + 0.22), (R - 0.05, z + 0.22)],
                      band, seg=seg, loc=(cx, cy, 0), rot=(0, 0, rot), cap_top=False))
    if finial:
        bag.add(beam(bag.nm("Finial"), (cx, cy, z + H - 0.1), (cx, cy, z + H + 0.6), 0.035, p_iron, seg=5))
        bag.add(part(bag.nm("FinialBall"), "ico", (cx, cy, z + H + 0.25), (0.14, 0.14, 0.14), p_gold, sub=1))


def gable_roof(bag, cx, cy, hw, hd, zt, th, m, m_dk, rows=4, over_x=0.35, over_y=0.45, gable=None, trim=None):
    """Telhado de duas águas com a cumeeira ao longo de X, em fiadas sobrepostas (como a casa).
    hw/hd = meia largura/profundidade das paredes, zt = topo das paredes, th = caimento."""
    cs, sn, tn = math.cos(th), math.sin(th), math.tan(th)
    t = 0.12
    ZR = zt + 0.02 + hd * tn
    ls = (hd + over_y) / cs
    step = ls / rows
    rx = 2 * hw + 2 * over_x

    def slope(side, s, off):
        return (cx, cy + side * (s * cs + sn * off), ZR - s * sn + cs * off)

    for side in (-1, 1):
        for i in range(rows):
            off = t / 2 + 0.05 * (rows - 1 - i)
            bag.add(bx(bag.nm("RoofRow"), slope(side, (i + 0.5) * step, off), (rx, step + 0.12, t),
                       m if i % 2 == 0 else m_dk if rows > 5 else m, rot=(-side * th, 0, 0), bev=0.02))
        for sx in (-1, 1):
            p = slope(side, ls / 2, -0.11)
            bag.add(bx(bag.nm("Barge"), (cx + sx * (hw + over_x - 0.04), p[1], p[2]), (0.08, ls, 0.2),
                       trim or p_wood_dk, rot=(-side * th, 0, 0), bev=0.015))
    top = (t + 0.05 * (rows - 1)) / cs
    bag.add(bx(bag.nm("Ridge"), (cx, cy, ZR + top - 0.02), (rx + 0.1, 0.3, 0.3), m_dk, rot=(PI / 4, 0, 0), bev=0.02))
    if gable:
        for sx in (-1, 1):
            g, gi = cx + hw * sx, cx + (hw - 0.2) * sx
            bag.add(hull(bag.nm("Gable"), [(g, cy - hd, zt), (g, cy + hd, zt), (g, cy, zt + hd * tn - 0.02),
                                           (gi, cy - hd, zt), (gi, cy + hd, zt), (gi, cy, zt + hd * tn - 0.02)], gable))
    return ZR + top


def window(bag, loc, w, h, face="-y", arch=False, bars=False, shutters=None, glass=None, frame=None):
    """Janela numa parede de frente -Y/+Y/-X/+X; loc = centro na face da parede."""
    glass = glass or b_glass
    frame = frame or p_wood_dk
    x, y, z = loc
    n = {"-y": (0, -1), "+y": (0, 1), "-x": (-1, 0), "+x": (1, 0)}[face]
    along_x = face in ("-y", "+y")

    def at(u, out, zz, su, so, sz, m):
        p = (x + (u if along_x else 0) + n[0] * out, y + (0 if along_x else u) + n[1] * out, zz)
        s = (su, so, sz) if along_x else (so, su, sz)
        return bag.add(bx(bag.nm("Win"), p, s, m, bev=0.012))

    at(0, 0.0, z, w + 0.16, 0.1, h + 0.16, frame)
    at(0, 0.03, z, w, 0.06, h, glass)
    if arch:
        at(0, 0.0, z + h / 2 + 0.12, w * 0.7 + 0.16, 0.1, 0.16, frame)
        at(0, 0.03, z + h / 2 + 0.06, w * 0.7, 0.06, 0.12, glass)
    if bars:
        for k in (-1, 0, 1):
            at(k * w / 3.2, 0.07, z, 0.035, 0.035, h, p_iron)
    else:
        at(0, 0.06, z, 0.045, 0.03, h, frame)
        at(0, 0.06, z, w, 0.03, 0.045, frame)
    at(0, 0.08, z - h / 2 - 0.1, w + 0.26, 0.16, 0.08, frame)   # peitoril
    if shutters:
        for s in (-1, 1):
            at(s * (w / 2 + 0.08 + w / 4), 0.05, z, w / 2, 0.05, h + 0.08, shutters)


def banner(bag, x, y, z, w, h, m, trim=p_gold, face=-1, pole=True, emblem=None):
    """Estandarte pendurado (topo em z) com ponta em V; face = -1 olha para -Y."""
    bag.add(bx(bag.nm("Banner"), (x, y, z - h / 2), (w, 0.04, h), m, bev=0.008))
    bag.add(hull(bag.nm("BannerTip"), [(x - w / 2, y - 0.02, z - h), (x + w / 2, y - 0.02, z - h), (x, y - 0.02, z - h - w * 0.45),
                                      (x - w / 2, y + 0.02, z - h), (x + w / 2, y + 0.02, z - h), (x, y + 0.02, z - h - w * 0.45)], m))
    bag.add(bx(bag.nm("BannerTrim"), (x, y + face * 0.03, z - h + 0.08), (w, 0.02, 0.06), trim, bev=0.005))
    if emblem:
        bag.add(part(bag.nm("Emblem"), "cyl", (x, y + face * 0.035, z - h * 0.45), (w * 0.45, w * 0.45, 0.02), emblem,
                     rot=(PI / 2, 0, 0), seg=8))
    if pole:
        bag.add(beam(bag.nm("BannerPole"), (x - w / 2 - 0.1, y, z + 0.02), (x + w / 2 + 0.1, y, z + 0.02), 0.03, p_wood_dk, seg=5))


def torch(bag, x, y, z, face=-1):
    bag.add(bx(bag.nm("TorchBracket"), (x, y + face * 0.12, z - 0.05), (0.06, 0.26, 0.06), p_iron, bev=0.01))
    bag.add(beam(bag.nm("Torch"), (x, y + face * 0.24, z - 0.3), (x, y + face * 0.26, z + 0.15), 0.04, p_wood_dk, seg=5))
    bag.add(lathe(bag.nm("TorchCup"), [(0.05, z + 0.08), (0.09, z + 0.2)], p_iron, seg=6, loc=(x, y + face * 0.26, 0),
                  cap_top=False))
    bag.add(part(bag.nm("Flame"), "cone", (x, y + face * 0.26, z + 0.32), (0.13, 0.13, 0.3), p_fire, seg=5))


def plank_floor(bag, cx, cy, z, sx, sy, m=None, t=0.12, n=None, rnd=None):
    """Assoalho de tábuas ao longo de X."""
    m = m or p_wood
    n = n or max(3, int(sy / 0.3))
    w = sy / n
    for i in range(n):
        mm = m if rnd is None else (p_wood_lt if rnd.random() > 0.7 else m)
        bag.add(bx(bag.nm("Plank"), (cx, cy - sy / 2 + (i + 0.5) * w, z - t / 2), (sx + (0.04 if i % 2 else 0), w - 0.02, t),
                   mm, bev=0.015))


def door(bag, x, y, z0, w, h, face=-1, double=False, studs=False, arch_mat=None):
    """Porta de tábuas com ferragens; y = plano da parede."""
    n = max(3, int(w / 0.22))
    pw = w / n
    for i in range(n):
        bag.add(bx(bag.nm("DoorPlank"), (x - w / 2 + (i + 0.5) * pw, y + face * 0.02, z0 + h / 2), (pw - 0.015, 0.08, h),
                   p_wood if i % 2 else p_wood_lt, bev=0.01))
    for zz in (z0 + h * 0.2, z0 + h * 0.75):
        bag.add(bx(bag.nm("DoorBand"), (x, y + face * 0.07, zz), (w * 0.96, 0.025, 0.09), p_iron, bev=0.008))
        if studs:
            for k in range(n):
                bag.add(part(bag.nm("Stud"), "ico", (x - w / 2 + (k + 0.5) * pw, y + face * 0.085, zz), (0.05, 0.03, 0.05),
                             p_iron_lt, sub=1))
    if double:
        bag.add(bx(bag.nm("DoorSeam"), (x, y + face * 0.07, z0 + h / 2), (0.04, 0.02, h), p_wood_dk, bev=0.0))
        for s in (-1, 1):
            bag.add(lathe(bag.nm("DoorRing"), [(0.08, z0 + h * 0.48), (0.08, z0 + h * 0.5), (0.06, z0 + h * 0.5), (0.06, z0 + h * 0.48)],
                          p_iron_lt, seg=6, loc=(x + s * 0.18, y + face * 0.09, 0), rot=(0, 0, 0)))
    else:
        bag.add(part(bag.nm("Knob"), "ico", (x + w * 0.32, y + face * 0.1, z0 + h * 0.48), (0.08, 0.06, 0.08), p_iron, sub=1))
    if arch_mat:
        bag.add(bx(bag.nm("Lintel"), (x, y + face * 0.04, z0 + h + 0.12), (w + 0.4, 0.18, 0.24), arch_mat, bev=0.03))
        for s in (-1, 1):
            bag.add(bx(bag.nm("Jamb"), (x + s * (w / 2 + 0.1), y + face * 0.04, z0 + h / 2), (0.2, 0.18, h), arch_mat, bev=0.03))


def cannonballs(bag, cx, cy, z, n):
    pts = [(0, 0, 0), (0.24, 0, 0), (0.12, 0.21, 0), (0.12, 0.07, 0.19), (-0.24, 0, 0), (-0.12, 0.21, 0)][:n]
    for i, (dx, dy, dz) in enumerate(pts):
        bag.add(part(bag.nm("Ball"), "ico", (cx + dx, cy + dy, z + 0.12 + dz), (0.24, 0.24, 0.24), p_iron, sub=1))


def grass(bag, pts, m=None):
    for i, (x, y) in enumerate(pts):
        for k in range(3):
            yaw = k * 2.1 + i
            bag.add(leaf(bag.nm("Grass"), (x + math.cos(yaw) * 0.05, y + math.sin(yaw) * 0.05, 0.0), yaw, 1.0, 0.24, 0.06,
                         m or p_moss_lt, droop=0.2))


# ================================================================ MURO (4,0 x 0,9)
def build_wall(level):
    rnd = random.Random(100 + level)
    bag = Bag()
    a = bag.add
    L = 4.0
    if level == 1:
        # paliçada: toras apontadas amarradas em duas travessas por trás (+Y)
        n = 8
        for i in range(n):
            x = -L / 2 + (i + 0.5) * L / n
            r = 0.24 + rnd.uniform(-0.02, 0.02)
            h = 2.55 + rnd.uniform(-0.15, 0.2)
            a(lathe(bag.nm("Log"), [(r * 1.04, 0.0), (r, 0.3), (r * 0.97, h), (r * 0.25, h + 0.42), (0.0, h + 0.5)],
                    p_wood if i % 3 else p_wood_lt, seg=7, loc=(x, rnd.uniform(-0.04, 0.04), 0),
                    rot=(rnd.uniform(-0.03, 0.03), rnd.uniform(-0.03, 0.03), rnd.uniform(0, 1)), wobble=0.05, seed=i))
        for z in (0.75, 1.95):
            a(beam(bag.nm("Rail"), (-L / 2, 0.3, z), (L / 2, 0.3, z + 0.03), 0.09, p_wood_dk, seg=6, end_mat=p_wood_end))
            for i in range(n):
                x = -L / 2 + (i + 0.5) * L / n
                a(bx(bag.nm("Lash"), (x, 0.24, z), (0.1, 0.12, 0.2), p_rope, bev=0.01))
        for x in (-1.5, 0.5):   # escoras
            a(beam(bag.nm("Prop"), (x, 1.05, 0.0), (x, 0.32, 1.9), 0.07, p_wood_dk, seg=5, end_mat=p_wood_end))
        a(boulder("Mound", (0, 0, -0.05), (L + 0.1, 0.95, 0.3), b_soil_lt, n=14, seed=3))
        grass(bag, [(-1.7, -0.35), (-0.2, -0.38), (1.2, -0.33), (0.6, 0.4)])
        return _bexport(bag, "Wall", "wall_1")
    mats = (b_stone, b_stone_lt, b_stone_dk) if level == 2 else (b_stone_cold, b_stone, b_stone_dk)
    H = 2.4 if level == 2 else 2.9
    D = 0.8
    # sapata
    a(bx("Footing", (0, 0, 0.12), (L, D + 0.16, 0.24), b_stone_dk, bev=0.04))
    courses(bag, rnd, -L / 2, L / 2, 0, D, 0.24, H, mats)
    # cordão (fiada saliente) e adarve com ameias
    a(bx("String", (0, 0, H + 0.06), (L, D + 0.12, 0.12), mats[2], bev=0.03))
    nm_ = 3
    for i in range(nm_):
        x = -L / 2 + (i + 0.5) * L / nm_
        a(bx(bag.nm("Merlon"), (x, -D / 2 + 0.2, H + 0.12 + 0.3), (0.82, 0.36, 0.6), _pick(rnd, *mats), bev=0.04))
        if level == 3:
            a(bx(bag.nm("MerlonCap"), (x, -D / 2 + 0.2, H + 0.12 + 0.64), (0.9, 0.44, 0.08), b_stone_dk, bev=0.02))
    a(bx("Parapet", (0, -D / 2 + 0.2, H + 0.12 + 0.12), (L, 0.36, 0.24), mats[0], bev=0.03))
    plank_floor(bag, 0, 0.12, H + 0.15, L, 0.4, m=p_wood_dk, n=2)
    if level == 3:
        # contrafortes na frente e seteira
        for x in (-1.3, 1.3):
            a(hull(bag.nm("Buttress"), [(x - 0.3, -D / 2, 0.24), (x + 0.3, -D / 2, 0.24), (x - 0.3, -D / 2 - 0.45, 0.24),
                                        (x + 0.3, -D / 2 - 0.45, 0.24), (x - 0.26, -D / 2, 1.9), (x + 0.26, -D / 2, 1.9)],
                   b_stone_dk))
        a(bx("Slit", (0, -D / 2 - 0.01, 1.5), (0.1, 0.06, 0.6), b_mortar, bev=0.0))
        a(bx("SlitFrame", (0, -D / 2 - 0.005, 1.5), (0.3, 0.05, 0.8), b_stone_lt, bev=0.02))
    # musgo no pé
    a(boulder("Moss", (rnd.uniform(-1, 1), -D / 2 - 0.05, 0), (1.1, 0.3, 0.3), p_moss, n=10, seed=level))
    _bexport(bag, "Wall", "wall_%d" % level)


# ================================================================ PORTÃO (4,0 x 1,1)
def build_gate(level):
    rnd = random.Random(200 + level)
    bag = Bag()
    a = bag.add
    mats = (b_stone, b_stone_lt, b_stone_dk) if level < 3 else (b_stone_cold, b_stone, b_stone_dk)
    D = 1.0
    H = 3.0 + 0.2 * (level - 1)
    for s in (-1, 1):
        x0, x1 = (1.3, 2.0) if s > 0 else (-2.0, -1.3)
        a(bx(bag.nm("PierFoot"), ((x0 + x1) / 2, 0, 0.12), (0.8, D + 0.14, 0.24), b_stone_dk, bev=0.04))
        courses(bag, rnd, x0, x1, 0, D, 0.24, H + 0.5, mats, wmin=0.3, wmax=0.45, hmin=0.3, hmax=0.42)
        a(bx(bag.nm("PierCap"), ((x0 + x1) / 2, 0, H + 0.56), (0.86, D + 0.12, 0.12), mats[2], bev=0.03))
        for k in (-1, 1):
            a(bx(bag.nm("Merlon"), ((x0 + x1) / 2 + k * 0.2, -D / 2 + 0.2, H + 0.84), (0.3, 0.36, 0.45), mats[0], bev=0.03))
        if level >= 2:
            torch(bag, s * 1.65, -D / 2, 2.0)
    # arco/verga
    a(bx("Lintel", (0, 0, H + 0.12), (2.62, D, 0.5), mats[0], bev=0.04))
    for i in range(7):   # aduelas
        x = -1.2 + i * 0.4
        a(bx(bag.nm("Voussoir"), (x, -D / 2 - 0.02, H - 0.05), (0.36, 0.06, 0.38), _pick(rnd, *mats), bev=0.025))
    a(bx("Keystone", (0, -D / 2 - 0.05, H + 0.05), (0.34, 0.1, 0.55), mats[1], bev=0.03))
    a(bx("Walk", (0, 0, H + 0.42), (2.62, D, 0.12), mats[2], bev=0.03))
    for i in range(3):
        a(bx(bag.nm("Merlon"), (-0.9 + i * 0.9, -D / 2 + 0.2, H + 0.72), (0.5, 0.36, 0.5), _pick(rnd, *mats), bev=0.03))
    # folhas da porta
    for s in (-1, 1):
        door(bag, s * 0.65, 0.1, 0.0, 1.28, H - 0.25, double=False, studs=level >= 2)
    a(bx("DoorSeam", (0, 0.03, (H - 0.25) / 2), (0.05, 0.1, H - 0.25), p_wood_dk, bev=0.0))
    for s in (-1, 1):
        a(lathe(bag.nm("Ring"), [(0.1, 1.28), (0.1, 1.32), (0.07, 1.32), (0.07, 1.28)], p_iron_lt, seg=6,
                loc=(s * 0.22, -0.02, 0)))
    a(bx("Bar", (0, -0.02, 1.15), (1.6, 0.1, 0.14), p_wood_dk, bev=0.02))
    if level == 3:
        banner(bag, 0, -D / 2 - 0.06, H + 0.3, 0.7, 0.9, b_blue, emblem=p_gold)
        for s in (-1, 1):   # grade levadiça recolhida aparecendo sob a verga
            pass
        for i in range(6):
            a(bx(bag.nm("Portcullis"), (-1.1 + i * 0.44, 0.38, H - 0.2), (0.06, 0.06, 0.4), p_iron, bev=0.0))
    _bexport(bag, "Gate", "gate_%d" % level)


# ================================================================ ESTACAS (4,0 x 1,6)
def build_spikes(level):
    rnd = random.Random(300 + level)
    bag = Bag()
    a = bag.add
    zc = 0.5
    a(beam("Spine", (-2.0, 0, zc), (2.0, 0, zc + 0.02), 0.12, p_wood_dk, seg=7, end_mat=p_wood_end))
    n = 5 + level
    for i in range(n):
        x = -1.75 + i * 3.5 / (n - 1) + rnd.uniform(-0.05, 0.05)
        for s in (-1, 1):
            L = 0.95 + rnd.uniform(-0.05, 0.08)
            d = Vector((0, s * 0.75, 0.62)).normalized()
            p0 = Vector((x + s * 0.04, 0, zc)) - d * 0.55
            p1 = Vector((x + s * 0.04, 0, zc)) + d * L
            if level == 1:
                a(beam(bag.nm("Stake"), p0, p1, 0.07, p_wood_lt if s > 0 else p_wood, seg=6, r2=0.008))
            else:
                tip = p1 - d * 0.28
                a(beam(bag.nm("Stake"), p0, tip, 0.07, p_wood_lt if s > 0 else p_wood, seg=6, end_mat=p_wood_end))
                a(beam(bag.nm("Tip"), tip, p1 + d * 0.06, 0.065, p_iron_lt, seg=6, r2=0.006))
    for i in range(3 if level == 1 else 5):
        x = -1.6 + i * (3.2 / (2 if level == 1 else 4))
        a(bx(bag.nm("Lash"), (x, 0, zc), (0.12, 0.27, 0.27), p_rope if level == 1 else p_iron, bev=0.02))
    if level == 3:   # fileira baixa de pontas na frente
        for i in range(9):
            x = -1.8 + i * 0.45
            a(beam(bag.nm("Low"), (x, -0.55, 0.0), (x, -0.78, 0.42), 0.05, p_iron, seg=5, r2=0.005))
    grass(bag, [(-1.4, 0.4), (0.3, -0.45), (1.6, 0.3)])
    _bexport(bag, "Spikes", "spikes_%d" % level)


# ================================================================ TORRE DE ARQUEIROS (3,2 x 3,2)
def archer_floor(level):
    return 4.0 + 0.4 * (level - 1)


def build_archer_tower(level):
    rnd = random.Random(400 + level)
    bag = Bag()
    a = bag.add
    F = archer_floor(level)
    if level == 1:
        # torre de madeira: 4 pernas de tora sobre sapatas de pedra, contraventada em X
        for i, (sx, sy) in enumerate(((-1, -1), (1, -1), (1, 1), (-1, 1))):
            a(boulder(bag.nm("Footing"), (sx * 1.2, sy * 1.2, 0), (0.6, 0.6, 0.35), b_stone, n=10, seed=i))
            a(beam(bag.nm("Leg"), (sx * 1.2, sy * 1.2, 0.15), (sx * 1.0, sy * 1.0, F), 0.14, p_wood, seg=7, end_mat=p_wood_end))
        for z0, z1 in ((0.5, 2.0), (2.1, 3.6)):
            for (ax, ay), (bx_, by) in (((-1, -1), (1, -1)), ((1, -1), (1, 1)), ((1, 1), (-1, 1)), ((-1, 1), (-1, -1))):
                ka, kb = 1.2 - 0.2 * z0 / F, 1.2 - 0.2 * z1 / F
                a(beam(bag.nm("Brace"), (ax * ka, ay * ka, z0), (bx_ * kb, by * kb, z1), 0.06, p_wood_dk, seg=5))
                a(beam(bag.nm("Brace"), (bx_ * ka, by * ka, z0), (ax * kb, ay * kb, z1), 0.06, p_wood_dk, seg=5))
        # escada na frente
        for s in (-1, 1):
            a(beam(bag.nm("LadderRail"), (s * 0.28, -1.75, 0.0), (s * 0.28, -1.12, F), 0.04, p_wood_lt, seg=5))
        for k in range(10):
            t = (k + 0.5) / 10
            a(beam(bag.nm("Rung"), (-0.3, -1.75 + 0.63 * t, F * t), (0.3, -1.75 + 0.63 * t, F * t), 0.025, p_wood_lt, seg=4))
    else:
        mats = (b_stone, b_stone_lt, b_stone_dk) if level == 2 else (b_stone_cold, b_stone, b_stone_dk)
        a(lathe("Plinth", [(1.5, 0.0), (1.5, 0.3), (1.38, 0.38)], b_stone_dk, seg=12))
        tower_ring(bag, rnd, 1.32, 1.12, 0.3, F - 0.2, 11, 0.35, mats,
             skip=lambda ang, z: abs(math.atan2(math.sin(ang + PI / 2), math.cos(ang + PI / 2))) < 0.3 and z < 1.95)
        door(bag, 0, -1.2, 0.3, 0.68, 1.55, arch_mat=mats[2])
        for k, z in enumerate((2.4, 3.4)):
            ang = PI / 2 + k * 2.2
            p = (math.cos(ang) * 1.14, math.sin(ang) * 1.14, z)
            a(bx(bag.nm("Slit"), p, (0.08, 0.12, 0.5), b_mortar, rot=(0, 0, ang), bev=0.0))
        a(lathe("Corbel", [(1.12, F - 0.4), (1.45, F - 0.15), (1.45, F - 0.05)], mats[2], seg=12))
    # plataforma
    plank_floor(bag, 0, 0, F, 3.0, 3.0, rnd=rnd)
    for sx in (-1, 1):
        a(bx(bag.nm("Joist"), (sx * 1.35, 0, F - 0.2), (0.16, 3.0, 0.16), p_wood_dk, bev=0.02))
    # parapeito
    if level < 3:
        for side in range(4):
            ang = side * PI / 2
            c, s = math.cos(ang), math.sin(ang)
            for k in range(9):
                u = -1.35 + k * 2.7 / 8
                if level == 1 and side == 3 and abs(u) < 0.4:   # vão da escada (frente)
                    continue
                p = (c * 1.42 - s * u, s * 1.42 + c * u, F + 0.45)
                a(bx(bag.nm("Pale"), p, (0.08, 0.3, 0.9 + rnd.uniform(-0.05, 0.05)), p_wood if k % 2 else p_wood_lt,
                     rot=(0, 0, ang), bev=0.015))
            a(bx(bag.nm("Rail"), (c * 1.48, s * 1.48, F + 0.72), (0.1, 3.0, 0.1), p_wood_dk, rot=(0, 0, ang), bev=0.015))
    else:
        mats = (b_stone_cold, b_stone, b_stone_dk)
        for side in range(4):
            ang = side * PI / 2
            c, s = math.cos(ang), math.sin(ang)
            a(bx(bag.nm("Parapet"), (c * 1.38, s * 1.38, F + 0.25), (0.3, 3.05, 0.5), mats[0], rot=(0, 0, ang), bev=0.04))
            for u in (-0.95, 0.0, 0.95):
                a(bx(bag.nm("Merlon"), (c * 1.38 - s * u, s * 1.38 + c * u, F + 0.72), (0.34, 0.5, 0.44),
                     _pick(rnd, *mats), rot=(0, 0, ang), bev=0.03))
        for s in (-1, 1):
            banner(bag, s * 0.7, -1.56, F - 0.2, 0.55, 1.1, b_blue, emblem=p_gold)
    # cobertura sobre 4 esteios
    for sx in (-1, 1):
        for sy in (-1, 1):
            a(beam(bag.nm("RoofPost"), (sx * 1.25, sy * 1.25, F), (sx * 1.25, sy * 1.25, F + 2.0), 0.07, p_wood_dk, seg=5))
    roof_m = b_thatch if level == 1 else (p_roof if level == 2 else b_blue)
    cone_roof(bag, F + 1.95, 2.05, 1.6, roof_m, seg=4, rot=PI / 4, band=p_wood_dk if level == 1 else p_roof_dk if level == 2 else b_blue_dk,
              wobble=0.03 if level == 1 else 0.0)
    if level == 2:
        banner(bag, 0, -1.5, F - 0.15, 0.55, 0.9, b_red, emblem=p_gold)
    _bexport(bag, "ArcherTower", "archer_tower_%d" % level)

    # ---- arqueiro (gira inteiro; frente -Y)
    bag = Bag()
    a = bag.add
    for s in (-1, 1):
        a(bx(bag.nm("Leg"), (s * 0.1, 0, 0.22), (0.13, 0.15, 0.45), p_wood_dk, bev=0.02))
        a(bx(bag.nm("Boot"), (s * 0.1, -0.03, 0.06), (0.15, 0.22, 0.12), b_mortar, bev=0.02))
    a(bx("Tunic", (0, 0, 0.68), (0.4, 0.26, 0.5), b_tunic, bev=0.03, taper=(0.9, 0.95)))
    a(bx("Skirt", (0, 0, 0.42), (0.44, 0.3, 0.14), b_tunic, bev=0.02))
    a(bx("Belt", (0, 0, 0.5), (0.42, 0.28, 0.06), p_leather if "p_leather" in globals() else leather, bev=0.01))
    a(part("Head", "ico", (0, -0.02, 1.08), (0.24, 0.24, 0.27), b_skin, sub=1))
    a(lathe("Hood", [(0.17, 0.98), (0.17, 1.14), (0.12, 1.24), (0.0, 1.32)], b_hood, seg=7, loc=(0, 0.02, 0)))
    a(bx("Cape", (0, 0.15, 0.7), (0.42, 0.06, 0.6), b_hood, bev=0.02, rot=(0.08, 0, 0)))
    a(bx("Quiver", (0.12, 0.2, 0.8), (0.12, 0.12, 0.45), leather, rot=(0.15, -0.3, 0), bev=0.02))
    for k in range(3):
        a(beam(bag.nm("Arrow"), (0.1 + k * 0.03, 0.22, 1.0), (0.16 + k * 0.03, 0.28, 1.14), 0.012, p_wood_lt, seg=4))
    # arco à esquerda, braços estendidos para a frente
    bow = [(0.62, 0.0), (0.42, -0.08), (0.2, -0.13), (0.0, -0.14), (-0.2, -0.13), (-0.42, -0.08), (-0.62, 0.0)]
    by0 = -0.42
    for i in range(len(bow) - 1):
        (z0, y0), (z1, y1) = bow[i], bow[i + 1]
        a(beam(bag.nm("Bow"), (-0.12, by0 + y0, 0.88 + z0 * 0.8), (-0.12, by0 + y1, 0.88 + z1 * 0.8), 0.022, p_wood_dk, seg=4))
    a(beam("String", (-0.12, by0, 0.88 + 0.5), (-0.12, by0, 0.88 - 0.5), 0.006, b_cloth_w, seg=3))
    a(beam("ArmL", (-0.2, -0.02, 0.88), (-0.13, by0 - 0.12, 0.88), 0.055, b_tunic, seg=5))
    a(beam("ArmR", (0.2, -0.02, 0.88), (0.0, -0.3, 0.9), 0.055, b_tunic, seg=5))
    a(part("HandL", "ico", (-0.12, by0 - 0.13, 0.88), (0.09, 0.09, 0.09), b_skin, sub=1))
    a(beam("Nocked", (0.0, -0.3, 0.9), (-0.1, by0 - 0.4, 0.89), 0.012, p_wood_lt, seg=4))
    _bexport(bag, "Archer", "archer_turret_%d" % level)


# ================================================================ TORRE DE CANHÃO (3,8 x 3,8)
def cannon_floor(level):
    return 3.0 + 0.3 * (level - 1)


def build_cannon_tower(level):
    rnd = random.Random(500 + level)
    bag = Bag()
    a = bag.add
    F = cannon_floor(level)
    mats = (b_stone, b_stone_lt, b_stone_dk) if level < 3 else (b_stone_cold, b_stone, b_stone_dk)
    a(lathe("Plinth", [(1.85, 0.0), (1.85, 0.25), (1.75, 0.32)], b_stone_dk, seg=14))
    tower_ring(bag, rnd, 1.72, 1.5, 0.25, F, 14, 0.4, mats, hmin=0.42, hmax=0.55,
         skip=lambda ang, z: abs(math.atan2(math.sin(ang + PI / 2), math.cos(ang + PI / 2))) < 0.26 and z < 1.75)
    door(bag, 0, -1.58, 0.25, 0.72, 1.4, arch_mat=mats[2], studs=True)
    a(lathe("String", [(1.52, F - 0.02), (1.68, F + 0.06), (1.68, F + 0.16), (1.5, F + 0.16)], mats[2], seg=14))
    a(lathe("Floor", [(1.5, F + 0.1), (1.5, F + 0.14)], b_stone_dk, seg=14))
    # parapeito com 7 ameias e o vão virado para a frente
    a(lathe("Parapet", [(1.62, F + 0.14), (1.62, F + 0.42), (1.3, F + 0.42), (1.3, F + 0.14)], mats[0], seg=14, cap_top=False, cap_bot=False))
    a(lathe("ParapetTop", [(1.64, F + 0.42), (1.28, F + 0.42)], mats[2], seg=14, cap_top=False, cap_bot=False))
    merlons(bag, 1.46, F + 0.42, 8, (0.36, 0.55, 0.42), mats[0], rot0=PI / 8, cap=mats[2] if level == 3 else None)
    cannonballs(bag, 0.75, 0.75, F + 0.14, 2 + level)
    a(bx("Powder", (-0.85, 0.7, F + 0.42), (0.36, 0.36, 0.56), p_wood, bev=0.03))
    a(bx("PowderBand", (-0.85, 0.7, F + 0.42), (0.38, 0.38, 0.06), p_iron, bev=0.01))
    for k, z in enumerate((1.3, 2.2)):
        ang = 0.6 + k * 2.2
        p = (math.cos(ang) * 1.55, math.sin(ang) * 1.55, z)
        a(bx(bag.nm("Slit"), p, (0.08, 0.12, 0.42), b_mortar, rot=(0, 0, ang), bev=0.0))
    if level >= 2:
        torch(bag, 0.75, -1.6, 1.6)
        torch(bag, -0.75, -1.6, 1.6)
    if level == 3:
        for s in (-1, 1):
            banner(bag, s * 0.95, -1.64, F - 0.05, 0.5, 1.0, b_blue, emblem=p_gold, pole=True)
    _bexport(bag, "CannonTower", "cannon_tower_%d" % level)

    # ---- canhão (frente -Y), origem no piso
    bag = Bag()
    a = bag.add
    a(lathe("Turntable", [(0.85, 0.0), (0.85, 0.1), (0.8, 0.14)], p_wood_dk, seg=12))
    for s in (-1, 1):
        a(hull(bag.nm("Cheek"), [(s * 0.32, 0.55, 0.14), (s * 0.32, -0.55, 0.14), (s * 0.32, -0.3, 0.88), (s * 0.32, 0.45, 0.5),
                                 (s * 0.2, 0.55, 0.14), (s * 0.2, -0.55, 0.14), (s * 0.2, -0.3, 0.88), (s * 0.2, 0.45, 0.5)], p_wood))
        for wy in (-0.35, 0.35):
            a(lathe(bag.nm("Wheel"), [(0.0, -0.05), (0.24, -0.05), (0.26, 0.0), (0.26, 0.06), (0.24, 0.1), (0.0, 0.1)], p_wood_dk, seg=10,
                    loc=(s * 0.4, wy, 0.32), rot=(0, s * PI / 2, 0)))
            a(lathe(bag.nm("Tire"), [(0.27, -0.06), (0.27, 0.11)], p_iron, seg=10, loc=(s * 0.4, wy, 0.32), rot=(0, s * PI / 2, 0),
                    cap_top=False, cap_bot=False))
    a(beam("Axle", (-0.5, -0.35, 0.32), (0.5, -0.35, 0.32), 0.04, p_iron, seg=5))
    a(beam("Axle2", (-0.5, 0.35, 0.32), (0.5, 0.35, 0.32), 0.04, p_iron, seg=5))
    k = 1.0 + 0.12 * (level - 1)
    prof = [(0.0, -0.62), (0.08, -0.66), (0.1, -0.6), (0.06, -0.55), (0.24, -0.5), (0.26, -0.3), (0.24, -0.25),
            (0.22, 0.4), (0.24, 0.42), (0.21, 0.45), (0.19, 0.95), (0.23, 1.0), (0.24, 1.08), (0.13, 1.08), (0.12, 0.9)]
    prof = [(r * k, z * (1.0 + 0.06 * (level - 1))) for r, z in prof]
    a(lathe("Barrel", prof, p_iron, seg=10, loc=(0, -0.05, 0.8), rot=(PI / 2 - 0.25, 0, 0), cap_top=True))
    if level >= 2:
        a(lathe("BarrelBand", [(0.26 * k, -0.2), (0.26 * k, -0.1)], p_gold if level == 3 else p_iron_lt, seg=10,
                loc=(0, -0.05, 0.8), rot=(PI / 2 - 0.25, 0, 0)))
    a(beam("Trunnion", (-0.36, -0.05, 0.8), (0.36, -0.05, 0.8), 0.06, p_iron_lt, seg=6))
    _bexport(bag, "Cannon", "cannon_turret_%d" % level)


# ================================================================ TORRE ARCANA (3,2 x 3,2)
def mage_top(level):
    return 5.0 + 0.4 * (level - 1)


def build_mage_tower(level):
    rnd = random.Random(600 + level)
    bag = Bag()
    a = bag.add
    T = mage_top(level)
    mats = (b_mage_st, b_violet_lt, b_mage_st_dk)
    a(lathe("Base", [(1.55, 0.0), (1.55, 0.35), (1.42, 0.42), (1.42, 0.62), (1.3, 0.7)], b_mage_st_dk, seg=8, rot=(0, 0, PI / 8)))
    tower_ring(bag, rnd, 1.22, 0.92, 0.7, T, 9, 0.3, (b_mage_st, b_mage_st, b_mage_st_dk), hmin=0.4, hmax=0.52,
         skip=lambda ang, z: abs(math.atan2(math.sin(ang + PI / 2), math.cos(ang + PI / 2))) < 0.36 and z < 2.0)
    # contrafortes nas 4 diagonais
    for i in range(4):
        ang = PI / 4 + i * PI / 2
        c, s = math.cos(ang), math.sin(ang)
        a(hull(bag.nm("Rib"), [(c * 1.1 - s * 0.14, s * 1.1 + c * 0.14, 0.7), (c * 1.1 + s * 0.14, s * 1.1 - c * 0.14, 0.7),
                               (c * 1.45 - s * 0.14, s * 1.45 + c * 0.14, 0.7), (c * 1.45 + s * 0.14, s * 1.45 - c * 0.14, 0.7),
                               (c * 0.96 - s * 0.12, s * 0.96 + c * 0.12, 2.6), (c * 0.96 + s * 0.12, s * 0.96 - c * 0.12, 2.6),
                               (c * 1.16 - s * 0.12, s * 1.16 + c * 0.12, 2.35), (c * 1.16 + s * 0.12, s * 1.16 - c * 0.12, 2.35)],
               b_mage_st_dk))
    # porta em arco e janelas brilhando em espiral
    door(bag, 0, -1.12, 0.7, 0.62, 1.2, arch_mat=b_mage_st_dk)
    a(part("DoorRune", "ico", (0, -1.22, 2.15), (0.16, 0.06, 0.16), b_arcane, sub=1))
    for k in range(3):
        ang = -PI / 2 + (0.75, -0.75, PI)[k]
        z = 2.3 + k * 0.95
        r = 1.22 + (0.92 - 1.22) * (z - 0.7) / (T - 0.7) + 0.08
        c, s = math.cos(ang), math.sin(ang)
        a(bx(bag.nm("WinFrame"), (c * r, s * r, z), (0.08, 0.44, 0.7), b_mage_st_dk, rot=(0, 0, ang), bev=0.02))
        a(bx(bag.nm("WinGlow"), (c * (r + 0.03), s * (r + 0.03), z), (0.06, 0.3, 0.56), b_arcane_win, rot=(0, 0, ang), bev=0.0))
        a(hull(bag.nm("WinArch"), [(c * (r + 0.05) - s * u, s * (r + 0.05) + c * u, z + 0.25 + h) for u, h in ((-0.13, 0), (0.13, 0), (0, 0.13))]
               + [(c * (r - 0.02) - s * u, s * (r - 0.02) + c * u, z + 0.25 + h) for u, h in ((-0.13, 0), (0.13, 0), (0, 0.13))], b_arcane_win))
    # sacada com ameias
    a(lathe("Balcony", [(0.92, T - 0.3), (1.32, T - 0.05), (1.32, T + 0.1), (0.9, T + 0.1)], b_mage_st_dk, seg=8, rot=(0, 0, PI / 8)))
    merlons(bag, 1.2, T + 0.1, 8, (0.22, 0.4, 0.34), b_mage_st, rot0=0.0)
    # telhado pontudo
    cone_roof(bag, T + 0.25, 1.2, 2.1, b_violet, seg=8, rot=PI / 8, band=p_gold if level == 3 else b_violet_lt, finial=False, flare=0.18)
    a(beam("Spire", (0, 0, T + 2.2), (0, 0, T + 2.5), 0.05, p_gold, seg=6, r2=0.0))
    # pedras rúnicas flutuando ao redor da base (uma por nível)
    for i in range(level):
        ang = -PI / 2 + PI / 3 + i * 2 * PI / 3
        p = (math.cos(ang) * 1.75, math.sin(ang) * 1.75, 0.0)
        a(boulder(bag.nm("RuneStone"), p, (0.45, 0.4, 0.7), b_mage_st_dk, n=10, seed=i + 3))
        a(bx(bag.nm("Rune"), (p[0] * 0.87, p[1] * 0.87, 0.45), (0.12, 0.12, 0.2), b_arcane, rot=(0, 0, ang), bev=0.0))
    _bexport(bag, "MageTower", "mage_tower_%d" % level)

    # ---- cristal (gira) com anel de runas, centrado na origem
    bag = Bag()
    a = bag.add
    s = 1.0 + 0.1 * (level - 1)
    pts = [(0, 0, 0.62 * s), (0, 0, -0.5 * s)]
    for i in range(6):
        ang = i * PI / 3
        pts.append((math.cos(ang) * 0.3 * s, math.sin(ang) * 0.3 * s, 0.08 * s))
    a(hull("Crystal", pts, b_arcane))
    for i in range(3):
        ang = i * 2 * PI / 3
        p = (math.cos(ang) * 0.65, math.sin(ang) * 0.65, 0.05 * (i - 1))
        a(hull(bag.nm("Shard"), [(p[0], p[1], p[2] + 0.2), (p[0], p[1], p[2] - 0.16), (p[0] + 0.08, p[1], p[2]),
                                 (p[0] - 0.08, p[1], p[2]), (p[0], p[1] + 0.08, p[2]), (p[0], p[1] - 0.08, p[2])], b_arcane))
    for i in range(10):
        ang = i * 2 * PI / 10
        a(bx(bag.nm("RuneRing"), (math.cos(ang) * 0.5, math.sin(ang) * 0.5, -0.38), (0.06, 0.2, 0.03), b_violet_lt,
             rot=(0, 0, ang), bev=0.0))
    _bexport(bag, "Crystal", "mage_turret_%d" % level)


# ================================================================ PREFEITURA (7,4 x 6,4)
def build_town_hall(level):
    rnd = random.Random(700 + level)
    bag = Bag()
    a = bag.add
    HW, Y0, Y1 = 2.6, -1.9, 2.3          # corpo principal: x ±2,6, y de -1,9 a 2,3
    HD, CY = (Y1 - Y0) / 2, (Y0 + Y1) / 2
    Z0, Z1, ZT = 0.4, 2.3, 4.3           # piso, troca pedra/enxaimel, topo das paredes
    mats = (b_stone, b_stone_lt, b_stone_dk)
    # plataforma
    for i in range(5):
        x = -3.6 + i * 1.44
        a(bx(bag.nm("Plinth"), (x + 0.72, 0, 0.2), (1.42, 6.2, 0.4), _pick(rnd, *mats), bev=0.05))
    for k in range(3):   # escadaria da frente
        a(bx(bag.nm("Step"), (0, -3.0 + k * 0.28, 0.07 + k * 0.13), (2.6 - k * 0.2, 0.4, 0.14 + k * 0.26), b_stone_lt, bev=0.03))
    # térreo em pedra (4 panos)
    courses(bag, rnd, -HW, HW, Y0 + 0.2, 0.4, Z0, Z1, mats)
    courses(bag, rnd, -HW, HW, Y1 - 0.2, 0.4, Z0, Z1, mats)
    courses(bag, rnd, Y0 + 0.4, Y1 - 0.4, -HW + 0.2, 0.4, Z0, Z1, mats, axis="y")
    courses(bag, rnd, Y0 + 0.4, Y1 - 0.4, HW - 0.2, 0.4, Z0, Z1, mats, axis="y")
    a(bx("Floor2", (0, CY, Z1 + 0.08), (2 * HW + 0.3, 2 * HD + 0.3, 0.16), p_wood_dk, bev=0.02))
    # andar de cima em enxaimel, um pouco em balanço
    a(bx("Upper", (0, CY, (Z1 + ZT) / 2 + 0.08), (2 * HW + 0.2, 2 * HD + 0.2, ZT - Z1 - 0.16), b_plaster, bev=0.0))
    uw, ud = HW + 0.1, HD + 0.1
    hp = ZT - Z1
    for sx in (-1, 1):
        for sy in (-1, 1):
            a(bx(bag.nm("Post"), (sx * (uw - 0.05), CY + sy * (ud - 0.05), Z1 + hp / 2 + 0.08), (0.22, 0.22, hp - 0.16), p_wood_dk, bev=0.02))
    for sy in (-1, 1):
        a(bx(bag.nm("TopPlate"), (0, CY + sy * (ud + 0.02), ZT - 0.08), (2 * uw + 0.1, 0.2, 0.18), p_wood_dk, bev=0.02))
        for x in (-1.75, -0.6, 0.6, 1.75):
            a(bx(bag.nm("Stud"), (x, CY + sy * (ud + 0.02), Z1 + hp / 2 + 0.08), (0.14, 0.1, hp - 0.2), p_wood_dk, bev=0.015))
    for sx in (-1, 1):
        a(bx(bag.nm("TopPlate"), (sx * (uw + 0.02), CY, ZT - 0.08), (0.2, 2 * ud + 0.1, 0.18), p_wood_dk, bev=0.02))
        a(bx(bag.nm("Stud"), (sx * (uw + 0.02), CY, Z1 + hp / 2 + 0.08), (0.1, 0.14, hp - 0.2), p_wood_dk, bev=0.015))
    # janelas
    for x in (-1.75, 1.75):
        window(bag, (x, Y0, 1.4), 0.62, 0.9, "-y", arch=True, bars=True, frame=b_stone_dk)
    for x in (-1.18, 1.18):
        window(bag, (x, CY - ud - 0.02, 3.3), 0.7, 0.75, "-y", shutters=b_blue_dk)
    for x in (-1.3, 1.3):
        window(bag, (x, Y1, 1.4), 0.6, 0.85, "+y", arch=True, bars=True, frame=b_stone_dk)
        window(bag, (x, CY + ud + 0.02, 3.3), 0.7, 0.75, "+y")
    for s in (-1, 1):
        window(bag, (s * HW, CY, 1.4), 0.6, 0.85, "+x" if s > 0 else "-x", arch=True, bars=True, frame=b_stone_dk)
        window(bag, (s * (uw + 0.02), CY, 3.3), 0.65, 0.7, "+x" if s > 0 else "-x", shutters=b_blue_dk)
    # telhado
    roof = p_roof if level < 3 else b_blue
    roof_dk = p_roof_dk if level < 3 else b_blue_dk
    gable_roof(bag, 0, CY, uw, ud, ZT, math.radians(40), roof, roof_dk, rows=5, over_x=0.4, over_y=0.5, gable=b_plaster)
    # pórtico da entrada com frontão
    door(bag, 0, Y0, Z0, 1.3, 1.85, double=True, studs=True, arch_mat=b_stone_lt)
    for s in (-1, 1):
        a(lathe(bag.nm("Column"), [(0.2, Z0), (0.2, Z0 + 0.15), (0.14, Z0 + 0.25), (0.13, 2.65), (0.18, 2.75), (0.18, 2.85)],
                b_stone_lt, seg=8, loc=(s * 1.0, -2.65, 0)))
    a(bx("Architrave", (0, -2.3, 2.95), (2.4, 0.95, 0.22), b_stone_lt, bev=0.03))
    th = math.radians(28)
    for side in (-1, 1):
        a(bx(bag.nm("PorchRoof"), (side * 0.62, -2.3, 3.36), (1.45, 1.1, 0.12), roof, rot=(0, side * th, 0), bev=0.02))
    a(hull("Pediment", [(-1.2, -2.78, 3.06), (1.2, -2.78, 3.06), (0, -2.78, 3.06 + 1.2 * math.tan(th)),
                        (-1.2, -2.0, 3.06), (1.2, -2.0, 3.06), (0, -2.0, 3.06 + 1.2 * math.tan(th))], b_plaster))
    a(part("Crest", "cyl", (0, -2.82, 3.33), (0.36, 0.36, 0.04), p_gold, rot=(PI / 2, 0, 0), seg=8))
    for s in (-1, 1):
        torch(bag, s * 1.75, Y0, 2.0)
    # torre do sino (fundo, à esquerda)
    TX, TY = -2.85, 1.85
    TH = 6.4 + 0.5 * (level - 1)
    a(bx("TowerCore", (TX, TY, TH / 2), (1.5, 1.5, TH), b_mortar, bev=0.0))
    for s in (-1, 1):
        courses(bag, rnd, TX - 0.8, TX + 0.8, TY + s * 0.62, 0.3, 0.0, TH, mats, wmin=0.4, wmax=0.8, core=False)
        courses(bag, rnd, TY - 0.6, TY + 0.6, TX + s * 0.65, 0.3, 0.0, TH, mats, axis="y", wmin=0.4, wmax=0.8, core=False)
    a(bx("BelfryFloor", (TX, TY, TH + 0.08), (1.8, 1.8, 0.16), b_stone_dk, bev=0.03))
    for sx in (-1, 1):
        for sy in (-1, 1):
            a(bx(bag.nm("BelfryPost"), (TX + sx * 0.72, TY + sy * 0.72, TH + 0.85), (0.28, 0.28, 1.4), b_stone_lt, bev=0.03))
    a(bx("BelfryTop", (TX, TY, TH + 1.62), (1.8, 1.8, 0.16), b_stone_dk, bev=0.03))
    a(lathe("Bell", [(0.0, TH + 1.5), (0.14, TH + 1.48), (0.22, TH + 1.3), (0.3, TH + 0.95), (0.34, TH + 0.9), (0.0, TH + 0.9)],
            p_gold, seg=10, loc=(TX, TY, 0)))
    a(beam("BellBeam", (TX - 0.75, TY, TH + 1.5), (TX + 0.75, TY, TH + 1.5), 0.06, p_wood_dk, seg=5))
    cone_roof(bag, TH + 1.7, 1.25, 1.7, roof, seg=4, rot=PI / 4, band=roof_dk, finial=False, cx=TX, cy=TY)
    a(beam("FlagPole", (TX, TY, TH + 3.3), (TX, TY, TH + 4.6), 0.035, p_wood_dk, seg=5))
    a(bx("Flag", (TX + 0.42, TY, TH + 4.3), (0.8, 0.03, 0.5), b_blue if level < 3 else b_red, bev=0.006))
    if level >= 2:
        a(part("Clock", "cyl", (TX, TY - 0.78, TH - 0.7), (0.62, 0.62, 0.05), b_cloth_w, rot=(PI / 2, 0, 0), seg=12))
        a(lathe("ClockRim", [(0.32, -0.04), (0.32, 0.04)], p_gold, seg=12, loc=(TX, TY - 0.8, TH - 0.7), rot=(PI / 2, 0, 0),
                cap_top=False, cap_bot=False))
        a(bx("Hand1", (TX, TY - 0.82, TH - 0.6), (0.03, 0.02, 0.22), b_mortar, bev=0.0))
        a(bx("Hand2", (TX + 0.08, TY - 0.82, TH - 0.7), (0.17, 0.02, 0.03), b_mortar, bev=0.0))
        for s in (-1, 1):   # braseiros nas quinas da frente
            a(lathe(bag.nm("BrazierPost"), [(0.28, 0.4), (0.28, 0.6), (0.16, 0.7), (0.12, 1.15), (0.3, 1.3), (0.3, 1.38)],
                    b_stone_lt, seg=8, loc=(s * 3.2, -2.75, 0)))
            a(lathe(bag.nm("BrazierBowl"), [(0.12, 1.36), (0.34, 1.42), (0.38, 1.58)], p_iron, seg=8, loc=(s * 3.2, -2.75, 0),
                    cap_top=False))
            a(part(bag.nm("BrazierFire"), "cone", (s * 3.2, -2.75, 1.78), (0.45, 0.45, 0.55), b_brazier, seg=6))
    # chaminé (direita, atrás)
    a(bx("Chimney", (1.7, 1.2, ZT + 1.0), (0.6, 0.6, 2.6), b_stone, bev=0.03))
    a(bx("ChimneyCap", (1.7, 1.2, ZT + 2.33), (0.78, 0.78, 0.12), b_stone_dk, bev=0.02))
    if level >= 3:
        for s in (-1, 1):
            banner(bag, s * 1.75, CY - ud - 0.06, ZT - 0.2, 0.62, 1.3, b_blue, emblem=p_gold)
    _bexport(bag, "TownHall", "town_hall_%d" % level)


# ================================================================ QUARTEL (6,6 x 5,6)
def build_barracks(level):
    rnd = random.Random(800 + level)
    bag = Bag()
    a = bag.add
    HW, Y0, Y1 = 2.9, -1.4, 2.4
    HD, CY = (Y1 - Y0) / 2, (Y0 + Y1) / 2
    Z0, Z1, ZT = 0.3, 1.4, 2.9
    mats = (b_stone, b_stone_lt, b_stone_dk)
    a(bx("Plinth", (0, CY, Z0 / 2), (2 * HW + 0.4, 2 * HD + 0.4, Z0), b_stone_dk, bev=0.04))
    courses(bag, rnd, -HW, HW, Y0 + 0.2, 0.4, Z0, Z1, mats)
    courses(bag, rnd, -HW, HW, Y1 - 0.2, 0.4, Z0, Z1, mats)
    courses(bag, rnd, Y0 + 0.4, Y1 - 0.4, -HW + 0.2, 0.4, Z0, Z1, mats, axis="y")
    courses(bag, rnd, Y0 + 0.4, Y1 - 0.4, HW - 0.2, 0.4, Z0, Z1, mats, axis="y")
    a(bx("Upper", (0, CY, (Z1 + ZT) / 2), (2 * HW - 0.1, 2 * HD - 0.1, ZT - Z1), b_plaster, bev=0.0))
    for x in (-HW + 0.05, -1.45, 1.45, HW - 0.05):
        for y in (Y0 + 0.02, Y1 - 0.02):
            a(bx(bag.nm("Post"), (x, y, (Z1 + ZT) / 2), (0.2, 0.16, ZT - Z1), p_wood_dk, bev=0.02))
    for y in (Y0 + 0.02, Y1 - 0.02):
        a(bx(bag.nm("Plate"), (0, y, ZT - 0.08), (2 * HW + 0.1, 0.18, 0.16), p_wood_dk, bev=0.02))
        a(bx(bag.nm("Plate"), (0, y, Z1 + 0.06), (2 * HW + 0.1, 0.18, 0.12), p_wood_dk, bev=0.02))
        for x0 in (-HW + 0.05, 1.45):   # escoras em diagonal
            a(beam(bag.nm("Brace"), (x0 + 0.1, y, Z1 + 0.1), (x0 + 1.3, y, ZT - 0.15), 0.06, p_wood_dk, seg=4))
    for x in (-HW + 0.02, HW - 0.02):
        a(bx(bag.nm("Plate"), (x, CY, ZT - 0.08), (0.18, 2 * HD, 0.16), p_wood_dk, bev=0.02))
    for x in (-0.75, 0.75):
        window(bag, (x - 1.5 * (1 if x < 0 else -1), Y1, 2.15), 0.55, 0.55, "+y", bars=True)
    for s in (-1, 1):
        window(bag, (s * HW, CY, 2.15), 0.6, 0.55, "+x" if s > 0 else "-x", bars=True)
        window(bag, (s * 2.2, Y0, 2.15), 0.55, 0.55, "-y", bars=True)
    gable_roof(bag, 0, CY, HW, HD, ZT, math.radians(35), p_roof, p_roof_dk, rows=4, over_x=0.35, over_y=0.45, gable=b_plaster)
    door(bag, 0, Y0, Z0, 1.3, 1.8, double=True, studs=True, arch_mat=b_stone_lt)
    a(bx("Sign", (0, Y0 - 0.1, 2.5), (1.0, 0.06, 0.4), p_wood, bev=0.02))
    for s in (-1, 1):   # espadas cruzadas na placa
        a(bx(bag.nm("SignSword"), (0, Y0 - 0.15, 2.5), (0.06, 0.03, 0.62), p_iron_lt, rot=(0, s * 0.9, 0), bev=0.0))
    # estandartes (um por nível)
    for i, x in enumerate((-1.0, 1.0, -2.2)[:level]):
        banner(bag, x, Y0 - 0.06, 2.75, 0.52, 1.0, b_red, emblem=p_gold)
    # pátio: armeiro com lanças, boneco de treino, alvo
    a(bx("RackBase", (-2.3, -2.25, 0.08), (1.6, 0.36, 0.16), p_wood_dk, bev=0.02))
    for s in (-1, 1):
        a(beam(bag.nm("RackPost"), (-2.3 + s * 0.75, -2.25, 0.1), (-2.3 + s * 0.75, -2.25, 1.6), 0.05, p_wood_dk, seg=5))
    a(bx("RackBar", (-2.3, -2.25, 1.4), (1.6, 0.1, 0.1), p_wood, bev=0.015))
    for k in range(4):
        x = -2.85 + k * 0.37
        a(beam(bag.nm("Spear"), (x, -2.25, 0.16), (x + 0.05, -2.33, 2.1), 0.025, p_wood_lt, seg=4))
        a(beam(bag.nm("SpearTip"), (x + 0.05, -2.33, 2.1), (x + 0.055, -2.335, 2.35), 0.04, p_iron_lt, seg=4, r2=0.0))
    a(beam("DummyPost", (2.2, -2.2, 0.0), (2.2, -2.2, 1.7), 0.06, p_wood_dk, seg=6))
    a(bx("DummyBody", (2.2, -2.2, 1.15), (0.4, 0.3, 0.6), b_straw, bev=0.05, taper=(1.1, 1.0)))
    a(beam("DummyArms", (1.75, -2.2, 1.35), (2.65, -2.2, 1.35), 0.04, p_wood_dk, seg=5))
    a(part("DummyHead", "ico", (2.2, -2.2, 1.66), (0.28, 0.26, 0.3), b_straw, sub=1))
    a(bx("DummyRope", (2.2, -2.2, 1.0), (0.42, 0.32, 0.05), p_rope, bev=0.01))
    if level >= 2:   # escudos na parede
        for x in (-2.1, 2.1):
            a(lathe(bag.nm("Shield"), [(0.0, 0.0), (0.32, 0.0), (0.32, 0.05), (0.0, 0.09)], b_blue if x < 0 else b_red, seg=8,
                    loc=(x, Y0 - 0.02, 1.0), rot=(PI / 2, 0, 0)))
            a(part(bag.nm("Boss"), "ico", (x, Y0 - 0.12, 1.0), (0.12, 0.08, 0.12), p_iron_lt, sub=1))
    if level >= 3:
        a(lathe("Brazier", [(0.2, 0.0), (0.12, 0.1), (0.1, 0.8), (0.3, 0.95), (0.34, 1.1)], p_iron, seg=8, loc=(0.0, -2.4, 0)))
        a(part("BrazierFire", "cone", (0.0, -2.4, 1.3), (0.4, 0.4, 0.5), b_brazier, seg=6))
    _bexport(bag, "Barracks", "barracks_%d" % level)


# ================================================================ FAZENDA (7,0 x 6,0)
def build_farm(level):
    rnd = random.Random(900 + level)
    bag = Bag()
    a = bag.add
    crop = CROP[level - 1]
    a(bx("Soil", (0.3, 0.3, 0.03), (6.0, 4.6, 0.06), b_soil, bev=0.02))
    for r in range(5):
        y = -1.55 + r * 0.92
        a(bx(bag.nm("Furrow"), (0.3, y, 0.1), (5.7, 0.5, 0.18), b_soil_lt, bev=0.06, taper=(1.0, 0.55)))
        for c in range(9):
            x = -2.3 + c * 0.66 + rnd.uniform(-0.06, 0.06)
            h = 0.45 + 0.18 * level + rnd.uniform(-0.08, 0.08)
            for k in range(4):
                yaw = k * PI / 2 + rnd.uniform(0, 0.8)
                a(leaf(bag.nm("Crop"), (x, y, 0.16), yaw, 0.35 + rnd.uniform(0, 0.25), h, 0.09, crop, droop=0.12))
            if level == 3:
                a(part(bag.nm("Head"), "cone", (x, y, 0.16 + h * 0.9), (0.1, 0.1, 0.26), b_straw, seg=4))
    # cerca no fundo e nas laterais
    for x in (-3.3, -2.0, -0.7, 0.6, 1.9, 3.2):
        a(beam(bag.nm("FencePost"), (x, 2.75, 0.0), (x, 2.75, 1.05), 0.07, p_wood_dk, seg=6))
    for z in (0.45, 0.85):
        a(beam(bag.nm("FenceRail"), (-3.35, 2.68, z), (3.25, 2.68, z + 0.02), 0.045, p_wood, seg=5, end_mat=p_wood_end))
    for s in (-1, 1):
        for y in (-0.2, 1.3):
            a(beam(bag.nm("FencePost"), (s * 3.3, y, 0.0), (s * 3.3, y, 1.05), 0.07, p_wood_dk, seg=6))
        for z in (0.45, 0.85):
            a(beam(bag.nm("FenceRail"), (s * 3.3, -0.25, z), (s * 3.3, 2.78, z), 0.045, p_wood, seg=5, end_mat=p_wood_end))
    # espantalho
    sx, sy = 0.9, 0.3
    a(beam("CrowPost", (sx, sy, 0.0), (sx, sy, 2.0), 0.05, p_wood_dk, seg=5))
    a(beam("CrowArms", (sx - 0.6, sy, 1.45), (sx + 0.6, sy, 1.45), 0.04, p_wood_dk, seg=5))
    a(bx("CrowShirt", (sx, sy, 1.3), (0.5, 0.26, 0.55), b_red, bev=0.04, taper=(1.15, 1.0)))
    for s in (-1, 1):
        a(bx(bag.nm("CrowSleeve"), (sx + s * 0.4, sy, 1.43), (0.36, 0.16, 0.16), b_red, bev=0.03))
        a(leaf(bag.nm("CrowStraw"), (sx + s * 0.58, sy, 1.43), s * PI / 2 - PI / 2, -0.3, 0.2, 0.12, b_straw))
    a(part("CrowHead", "ico", (sx, sy, 1.78), (0.3, 0.28, 0.32), b_cloth_w, sub=1))
    a(lathe("CrowHat", [(0.3, 1.88), (0.3, 1.9), (0.13, 1.92), (0.11, 2.12), (0.0, 2.14)], b_straw, seg=8, loc=(sx, sy, 0)))
    # canto da frente: carroça de mão/caixotes, barril e saco
    a(bx("Crate", (-2.9, -2.35, 0.3), (0.6, 0.6, 0.6), p_wood, bev=0.03))
    a(bx("CrateBand", (-2.9, -2.35, 0.3), (0.62, 0.62, 0.08), p_wood_dk, bev=0.01))
    a(lathe("Barrel", [(0.26, 0.0), (0.3, 0.2), (0.32, 0.4), (0.3, 0.6), (0.26, 0.78)], p_wood, seg=10, loc=(-2.2, -2.5, 0)))
    for z in (0.15, 0.63):
        a(lathe(bag.nm("BarrelHoop"), [(0.31, z - 0.03), (0.31, z + 0.03)], p_iron, seg=10, loc=(-2.2, -2.5, 0), cap_top=False, cap_bot=False))
    a(boulder("Sack", (-2.85, -1.7, 0), (0.5, 0.4, 0.55), p_canvas, n=12, seed=5))
    a(bx("Hoe", (-2.4, -1.85, 0.6), (0.04, 0.04, 1.3), p_wood_lt, rot=(0.3, 0.2, 0), bev=0.0))
    if level >= 2:   # fardos de feno
        for i, (x, y, z, yaw) in enumerate(((2.6, -2.35, 0.25, 0.1), (3.0, -1.7, 0.25, 1.5), (2.75, -2.05, 0.75, 0.6))):
            a(bx(bag.nm("Hay"), (x, y, z), (0.8, 0.5, 0.5), b_straw, rot=(0, 0, yaw), bev=0.06))
            a(bx(bag.nm("HayTie"), (x, y, z), (0.25, 0.52, 0.52), b_thatch_dk, rot=(0, 0, yaw), bev=0.02))
    if level >= 3:   # celeiro pequeno no canto de trás
        cx, cy = -2.55, 2.1
        a(bx("ShedBase", (cx, cy, 0.06), (1.5, 1.2, 0.12), b_stone_dk, bev=0.02))
        for i in range(6):
            a(bx(bag.nm("ShedWall"), (cx - 0.62 + i * 0.25, cy, 0.75), (0.24, 1.0, 1.3), p_wood if i % 2 else p_wood_lt, bev=0.015))
        gable_roof(bag, cx, cy, 0.7, 0.55, 1.4, math.radians(38), b_thatch, b_thatch_dk, rows=2, over_x=0.15, over_y=0.25,
                   gable=p_wood)
        door(bag, cx, cy - 0.55, 0.1, 0.55, 1.05)
    grass(bag, [(-3.1, -0.6), (3.2, 2.4), (-1.0, -2.6), (1.8, -2.7), (3.0, 0.4)])
    _bexport(bag, "Farm", "farm_%d" % level)


# ================================================================ MERCADO (5,2 x 5,2)
def build_market(level):
    rnd = random.Random(1000 + level)
    bag = Bag()
    a = bag.add
    # calçamento
    for i in range(6):
        for j in range(6):
            x, y = -2.15 + i * 0.86, -2.15 + j * 0.86
            a(bx(bag.nm("Pave"), (x + rnd.uniform(-0.02, 0.02), y + rnd.uniform(-0.02, 0.02), 0.05), (0.82, 0.82, 0.1),
                 _pick(rnd, b_stone, b_stone_lt, b_stone_dk), rot=(0, 0, rnd.uniform(-0.04, 0.04)), bev=0.03))
    # barraca principal: 4 esteios, balcão na frente, prateleira atrás
    X, Yf, Yb = 1.8, -0.9, 1.2
    for x in (-X, X):
        a(beam(bag.nm("Post"), (x, Yf, 0.1), (x, Yf, 2.4), 0.08, p_wood_dk, seg=6))
        a(beam(bag.nm("Post"), (x, Yb, 0.1), (x, Yb, 2.85), 0.08, p_wood_dk, seg=6))
    a(bx("Counter", (0, Yf + 0.15, 0.55), (2 * X - 0.1, 0.5, 0.9), p_wood, bev=0.03))
    for i in range(7):
        a(bx(bag.nm("CounterPlank"), (-X + 0.3 + i * 0.5, Yf - 0.11, 0.55), (0.46, 0.04, 0.86), p_wood_lt if i % 2 else p_wood, bev=0.01))
    a(bx("CounterTop", (0, Yf + 0.15, 1.03), (2 * X + 0.1, 0.62, 0.08), p_wood_dk, bev=0.02))
    a(bx("Shelf", (0, Yb - 0.15, 1.1), (2 * X - 0.1, 0.4, 0.06), p_wood, bev=0.015))
    a(bx("Shelf2", (0, Yb - 0.15, 1.7), (2 * X - 0.1, 0.4, 0.06), p_wood, bev=0.015))
    a(bx("BackCloth", (0, Yb + 0.02, 1.4), (2 * X, 0.04, 2.0), p_canvas_dk, bev=0.0))
    # toldo listrado inclinado para a frente
    n = 7
    w = (2 * X + 0.4) / n
    th = math.atan2(2.85 - 2.4, Yb - Yf)
    Lr = math.hypot(Yb - Yf + 0.7, 0.55)
    for i in range(n):
        x = -X - 0.2 + (i + 0.5) * w
        m = (b_cloth_y if i % 2 == 0 else b_red) if level < 3 else (b_cloth_y if i % 2 == 0 else b_blue)
        a(bx(bag.nm("Awning"), (x, (Yf + Yb) / 2 - 0.3, 2.62), (w, Lr, 0.05), m, rot=(-th, 0, 0), bev=0.0))
        a(hull(bag.nm("Flap"), [(x - w / 2, Yf - 0.62, 2.36), (x + w / 2, Yf - 0.62, 2.36), (x, Yf - 0.62, 2.12),
                                (x - w / 2, Yf - 0.58, 2.36), (x + w / 2, Yf - 0.58, 2.36), (x, Yf - 0.58, 2.12)], m))
    # mercadorias no balcão e nas prateleiras
    goods = (b_apple, b_orange, b_cabbage)
    for k, gx in enumerate((-1.2, -0.2, 0.8)):
        a(bx(bag.nm("Basket"), (gx, Yf + 0.15, 1.15), (0.6, 0.42, 0.18), p_wood_lt, bev=0.03, taper=(1.1, 1.1)))
        for j in range(5):
            a(part(bag.nm("Fruit"), "ico", (gx - 0.18 + (j % 3) * 0.18, Yf + 0.08 + (j // 3) * 0.16, 1.28), (0.15, 0.15, 0.15),
                   goods[k], sub=1))
    for j in range(5):
        a(bx(bag.nm("Jar"), (-1.4 + j * 0.7, Yb - 0.15, 1.27), (0.22, 0.22, 0.28), b_stone_lt if j % 2 else p_roof, bev=0.04))
        a(boulder(bag.nm("Cloth"), (-1.4 + j * 0.7, Yb - 0.15, 1.73), (0.42, 0.3, 0.2), (b_blue, b_red, b_cloth_w, b_cloth_y, p_canvas)[j],
                  n=9, seed=j))
    # placa com moeda
    a(beam("SignArm", (X + 0.05, Yf, 2.2), (X + 0.65, Yf, 2.2), 0.03, p_iron, seg=4))
    a(bx("Sign", (X + 0.4, Yf, 1.88), (0.5, 0.05, 0.45), p_wood, bev=0.02))
    a(part("Coin", "cyl", (X + 0.4, Yf - 0.05, 1.88), (0.28, 0.28, 0.03), p_gold, rot=(PI / 2, 0, 0), seg=10))
    # caixotes, sacos e barril ao redor
    a(bx("Crate1", (-2.05, -1.75, 0.38), (0.55, 0.55, 0.55), p_wood, bev=0.03, rot=(0, 0, 0.2)))
    a(bx("Crate2", (-1.4, -2.0, 0.33), (0.45, 0.45, 0.45), p_wood_lt, bev=0.03, rot=(0, 0, -0.3)))
    a(boulder("Sack1", (2.1, -1.8, 0.1), (0.5, 0.42, 0.6), p_canvas, n=12, seed=11))
    a(boulder("Sack2", (1.6, -2.1, 0.1), (0.45, 0.4, 0.5), p_canvas_dk, n=12, seed=12))
    a(lathe("Barrel", [(0.26, 0.1), (0.3, 0.3), (0.32, 0.5), (0.3, 0.7), (0.26, 0.88)], p_wood, seg=10, loc=(2.1, 1.9, 0)))
    for z in (0.25, 0.73):
        a(lathe(bag.nm("Hoop"), [(0.31, z - 0.03), (0.31, z + 0.03)], p_iron, seg=10, loc=(2.1, 1.9, 0), cap_top=False, cap_bot=False))
    if level >= 2:   # carrinho de mão com abóboras
        a(bx("Cart", (-1.95, 1.75, 0.55), (0.9, 0.7, 0.3), p_wood, bev=0.03))
        a(lathe("CartWheel", [(0.0, -0.04), (0.3, -0.04), (0.3, 0.04), (0.0, 0.04)], p_wood_dk, seg=10, loc=(-1.95, 1.3, 0.38),
                rot=(PI / 2, 0, 0)))
        a(beam("CartHandle", (-1.6, 2.1, 0.6), (-1.3, 2.4, 0.5), 0.03, p_wood_dk, seg=4))
        for k in range(3):
            a(part(bag.nm("Pumpkin"), "sphere", (-2.2 + k * 0.25, 1.75, 0.82), (0.26, 0.26, 0.2), b_orange, seg=8))
    if level >= 3:   # tapete e baú de ouro
        a(bx("Rug", (0, -1.75, 0.105), (1.6, 0.9, 0.01), b_red, bev=0.0))
        a(bx("RugTrim", (0, -1.75, 0.11), (1.4, 0.7, 0.01), b_cloth_y, bev=0.0))
        a(bx("Chest", (0.9, -1.8, 0.33), (0.6, 0.4, 0.42), p_wood, bev=0.03))
        a(bx("ChestBand", (0.9, -1.8, 0.33), (0.62, 0.42, 0.06), p_gold, bev=0.01))
        for k in range(4):
            a(part(bag.nm("Gold"), "cyl", (0.75 + k * 0.1, -1.8, 0.6 + 0.02 * k), (0.12, 0.12, 0.03), p_gold, seg=8))
    _bexport(bag, "Market", "market_%d" % level)


for _lv in (1, 2, 3):
    for _k, _f in (("wall", build_wall), ("gate", build_gate), ("spikes", build_spikes), ("archer_tower", build_archer_tower),
                   ("cannon_tower", build_cannon_tower), ("mage_tower", build_mage_tower), ("town_hall", build_town_hall),
                   ("barracks", build_barracks), ("farm", build_farm), ("market", build_market)):
        PROP_BUILDERS["b_%s_%d" % (_k, _lv)] = (lambda f=_f, lv=_lv: f(lv))
