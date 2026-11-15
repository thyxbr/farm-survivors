# Casas da vila e lojas da praça de Valdoria. Executado por build_assets.py depois de buildings.py
# (usa mat/part/hull/export de lá, bx/lathe/beam/boulder/leaf/join/Bag de props.py e
# courses/gable_roof/window/door/banner/torch/_log_pile de buildings.py).
#
# Saída em assets/models/:
#   house.glb    chalé em enxaimel, telha vermelha (a casa de sempre, remodelada)
#   house_b.glb  casinha de sapê, pedra embaixo, venezianas azuis
#   house_c.glb  sobrado: térreo de pedra, andar de cima em balanço, telhado de ardósia com água-furtada
#   shop_smithy.glb     ferraria aberta na frente; a origem é o lugar do ferreiro (forja e bigorna são props à parte)
#   shop_alchemist.glb  botica do alquimista: torrinha redonda, vitrine de frascos, caldeirão na porta
#   shop_merchant.glb   empório do mercador: balcão na frente sob toldo listrado, mercadorias
# Convenções: frente (porta) em -Y, chão em Z=0. As casas têm paredes de 5 x 4 m centradas na origem
# (colisão 5,2 x 4,2 no jogo), igual à casa antiga, então posições na vila, na praça e na cidade não mudam.

v_plaster = mat("v_plaster", (0.80, 0.71, 0.55), 0.95)
v_plaster_w = mat("v_plaster_warm", (0.78, 0.60, 0.40), 0.95)
v_plaster_dk = mat("v_plaster_dark", (0.55, 0.45, 0.32), 0.95)
v_timber = mat("v_timber", (0.17, 0.09, 0.04), 0.9)
v_slate = mat("v_slate", (0.17, 0.19, 0.25), 0.9)
v_slate_dk = mat("v_slate_dark", (0.10, 0.11, 0.15), 0.9)
v_green = mat("v_shutter_green", (0.10, 0.28, 0.13), 0.85)
v_blue = mat("v_shutter_blue", (0.08, 0.20, 0.42), 0.85)
v_red = mat("v_shutter_red", (0.42, 0.08, 0.05), 0.85)
v_leaf = mat("v_leaf", (0.16, 0.40, 0.10), 0.9)
v_flower_r = mat("v_flower_red", (0.85, 0.15, 0.20), 0.7)
v_flower_y = mat("v_flower_yellow", (0.95, 0.75, 0.15), 0.7)
v_flower_v = mat("v_flower_violet", (0.50, 0.25, 0.85), 0.7)
v_flower_w = mat("v_flower_white", (0.92, 0.90, 0.85), 0.7)
v_lamp = mat("v_lamp", (1.0, 0.8, 0.4), 0.4, 0.0, emit=(1.0, 0.75, 0.35), strength=6.0)
v_potion_g = mat("v_potion_green", (0.25, 0.95, 0.35), 0.15, 0.0, emit=(0.3, 1.0, 0.4), strength=1.2)
v_potion_r = mat("v_potion_red", (0.95, 0.15, 0.20), 0.15, 0.0, emit=(1.0, 0.2, 0.25), strength=1.0)
v_potion_b = mat("v_potion_blue", (0.20, 0.45, 1.0), 0.15, 0.0, emit=(0.3, 0.55, 1.0), strength=1.2)
v_potion_p = mat("v_potion_purple", (0.70, 0.30, 1.0), 0.15, 0.0, emit=(0.75, 0.35, 1.0), strength=1.2)
v_brew = mat("v_brew", (0.30, 1.0, 0.45), 0.2, 0.0, emit=(0.35, 1.0, 0.45), strength=4.0)
v_copper = mat("v_copper", (0.72, 0.35, 0.16), 0.35, 0.9)
v_teal = mat("v_roof_teal", (0.07, 0.30, 0.30), 0.85)
v_teal_dk = mat("v_roof_teal_dark", (0.04, 0.18, 0.19), 0.85)
v_soot = mat("v_soot", (0.06, 0.055, 0.05), 1.0)
v_herb = mat("v_herb", (0.35, 0.45, 0.15), 0.9)
v_mush = mat("v_mushroom", (0.75, 0.12, 0.10), 0.7)


# ================================================================ peças comuns
class Body:
    """Retângulo de paredes (centro cx, cy; meia largura hw em X, meia profundidade hd em Y)."""
    def __init__(self, cx, cy, hw, hd):
        self.cx, self.cy, self.hw, self.hd = cx, cy, hw, hd

    def span(self, face):
        return 2 * self.hw if face in ("-y", "+y") else 2 * self.hd

    def at(self, bag, face, u, out, z, su, so, sz, m, tilt=0.0, bev=0.015, name="P"):
        """Peça presa à fachada. u = lateral (da esquerda para a direita de quem olha a fachada),
        out = afastamento da parede. tilt > 0 faz o eixo longo (su) subir no sentido +u."""
        cx, cy, hw, hd = self.cx, self.cy, self.hw, self.hd
        if face == "-y":
            loc, size, rot = (cx + u, cy - hd - out, z), (su, so, sz), (0, -tilt, 0)
        elif face == "+y":
            loc, size, rot = (cx - u, cy + hd + out, z), (su, so, sz), (0, tilt, 0)
        elif face == "+x":
            loc, size, rot = (cx + hw + out, cy + u, z), (so, su, sz), (tilt, 0, 0)
        else:
            loc, size, rot = (cx - hw - out, cy - u, z), (so, su, sz), (-tilt, 0, 0)
        return bag.add(bx(bag.nm(name), loc, size, m, rot=rot, bev=bev))

    def point(self, face, u, out):
        cx, cy, hw, hd = self.cx, self.cy, self.hw, self.hd
        return {"-y": (cx + u, cy - hd - out), "+y": (cx - u, cy + hd + out),
                "+x": (cx + hw + out, cy + u), "-x": (cx - hw - out, cy - u)}[face]


def half_timber(bag, b, face, z0, z1, posts, rails=(), braces=(), m=None, w=0.16):
    """Madeira aparente numa fachada: frechal e baldrame, esteios em 'posts' (u), travessas
    rails = [(z, u0, u1)] e escoras braces = [(u0, z0, u1, z1)]."""
    m = m or v_timber
    L = b.span(face)
    b.at(bag, face, 0, 0.03, z0 + 0.08, L + 0.12, 0.14, 0.16, m, name="Sill")
    b.at(bag, face, 0, 0.03, z1 - 0.08, L + 0.16, 0.16, 0.18, m, name="Plate")
    for u in posts:
        b.at(bag, face, u, 0.035, (z0 + z1) / 2, w, 0.12, z1 - z0 - 0.2, m, name="Post")
    for z, u0, u1 in rails:
        b.at(bag, face, (u0 + u1) / 2, 0.03, z, u1 - u0, 0.11, 0.13, m, name="Rail")
    for u0, za, u1, zb in braces:
        du, dz = u1 - u0, zb - za
        b.at(bag, face, (u0 + u1) / 2, 0.025, (za + zb) / 2, math.hypot(du, dz), 0.1, 0.12, m,
             tilt=math.atan2(dz, du), name="Brace")


def corner_posts(bag, b, z0, z1, m=None, w=0.24):
    m = m or v_timber
    for sx in (-1, 1):
        for sy in (-1, 1):
            bag.add(bx(bag.nm("Corner"), (b.cx + sx * (b.hw + 0.01), b.cy + sy * (b.hd + 0.01), (z0 + z1) / 2),
                       (w, w, z1 - z0), m, bev=0.02))


def stone_band(bag, rnd, b, z0, z1, depth=0.3, out=0.06, mats=None, skip=None):
    """Rodapé/térreo de pedra em volta do corpo b (blocos com junta escura); skip = [(face, u0, u1)] vãos."""
    mats = mats or (b_stone_lt, b_stone, b_stone_dk)
    hw, hd = b.hw + out, b.hd + out
    cx, cy = b.cx, b.cy
    bag.add(bx(bag.nm("BandCore"), (cx, cy, (z0 + z1) / 2), (2 * hw - 0.05, 2 * hd - 0.05, z1 - z0 - 0.01), b_mortar, bev=0.0))
    skip = skip or []

    def cut(face, a0, a1):
        segs = [(a0, a1)]
        for f, u0, u1 in skip:
            if f != face:
                continue
            nxt = []
            for s0, s1 in segs:
                if u1 <= s0 or u0 >= s1:
                    nxt.append((s0, s1))
                    continue
                if u0 > s0:
                    nxt.append((s0, u0))
                if u1 < s1:
                    nxt.append((u1, s1))
            segs = nxt
        return segs

    for face, y, sgn in (("-y", cy - hd + depth / 2, 1), ("+y", cy + hd - depth / 2, -1)):
        for s0, s1 in cut(face, -hw, hw):
            x0, x1 = (cx + s0, cx + s1) if sgn > 0 else (cx - s1, cx - s0)
            courses(bag, rnd, x0, x1, y, depth, z0, z1, mats, hmin=0.24, hmax=0.34, wmin=0.35, wmax=0.7,
                    bev=0.035, core=False)
    for face, x, sgn in (("+x", cx + hw - depth / 2, 1), ("-x", cx - hw + depth / 2, -1)):
        for s0, s1 in cut(face, -hd + depth, hd - depth):
            y0, y1 = (cy + s0, cy + s1) if sgn > 0 else (cy - s1, cy - s0)
            courses(bag, rnd, y0, y1, x, depth, z0, z1, mats, axis="y", hmin=0.24, hmax=0.34, wmin=0.35, wmax=0.7,
                    bev=0.035, core=False)


def chimney(bag, rnd, x, y, z0, z1, w=0.6, mats=None):
    """Chaminé de pedra em fiadas de blocos levemente tortos, capa e boca."""
    mats = mats or (b_stone, b_stone_lt, b_stone_dk)
    bag.add(bx(bag.nm("FlueCore"), (x, y, (z0 + z1) / 2), (w - 0.06, w - 0.06, z1 - z0), b_mortar, bev=0.0))
    z, k = z0, 0
    while z < z1 - 0.05:
        h = min(rnd.uniform(0.22, 0.3), z1 - z)
        for i in range(2):   # duas pedras por fiada, junta alternada
            off = (0.5 - i) * w / 2 * (1 if k % 2 else -1)
            ww = w / 2 + rnd.uniform(-0.04, 0.04)
            if k % 2:
                loc, size = (x + off, y, z + h / 2), (ww, w + rnd.uniform(0, 0.03), h - 0.03)
            else:
                loc, size = (x, y + off, z + h / 2), (w + rnd.uniform(0, 0.03), ww, h - 0.03)
            bag.add(bx(bag.nm("FlueStone"), loc, size, _pick(rnd, *mats), rot=(0, 0, rnd.uniform(-0.03, 0.03)), bev=0.03))
        z += h
        k += 1
    bag.add(bx(bag.nm("FlueCap"), (x, y, z1 + 0.06), (w + 0.18, w + 0.18, 0.12), b_stone_dk, bev=0.03))
    bag.add(bx(bag.nm("FlueMouth"), (x, y, z1 + 0.2), (w * 0.55, w * 0.55, 0.18), b_stone_dk, bev=0.02))
    bag.add(bx(bag.nm("FlueHole"), (x, y, z1 + 0.28), (w * 0.38, w * 0.38, 0.04), v_soot, bev=0.0))


def flower_box(bag, b, face, u, z, w, flowers, rnd):
    b.at(bag, face, u, 0.16, z, w + 0.2, 0.26, 0.2, p_wood, bev=0.03, name="FlowerBox")
    b.at(bag, face, u, 0.16, z + 0.06, w + 0.24, 0.3, 0.04, p_wood_dk, bev=0.01, name="FlowerBoxRim")
    n = max(3, int(w / 0.16))
    for i in range(n):
        uu = u - w / 2 + (i + 0.5) * w / n
        x, y = b.point(face, uu, 0.16)
        bag.add(part(bag.nm("Bush"), "ico", (x, y, z + 0.17), (0.2, 0.2, 0.17), v_leaf, sub=1))
        if i % 2 == 0 or rnd.random() < 0.4:
            x2, y2 = b.point(face, uu + rnd.uniform(-0.04, 0.04), 0.13 + rnd.uniform(0.0, 0.06))
            bag.add(part(bag.nm("Bloom"), "ico", (x2, y2, z + 0.27), (0.1, 0.1, 0.09), flowers, sub=1))


def window_on(bag, b, face, u, z, w, h, shutters=None, flowers=None, rnd=None, arch=False, bars=False, frame=None):
    x, y = b.point(face, u, 0.0)
    window(bag, (x, y, z), w, h, face, arch=arch, bars=bars, shutters=shutters, frame=frame or v_timber)
    if flowers:
        flower_box(bag, b, face, u, z - h / 2 - 0.22, w, flowers, rnd)


def lantern(bag, x, y, z, face=-1):
    bag.add(bx(bag.nm("LampArm"), (x, y + face * 0.17, z + 0.2), (0.05, 0.34, 0.05), p_iron, bev=0.01))
    bag.add(beam(bag.nm("LampHook"), (x, y + face * 0.32, z + 0.2), (x, y + face * 0.32, z + 0.08), 0.012, p_iron, seg=4))
    bag.add(bx(bag.nm("LampCap"), (x, y + face * 0.32, z + 0.06), (0.2, 0.2, 0.06), p_iron, bev=0.01, taper=(0.5, 0.5)))
    bag.add(bx(bag.nm("Lamp"), (x, y + face * 0.32, z - 0.08), (0.15, 0.15, 0.2), v_lamp, bev=0.01))
    bag.add(bx(bag.nm("LampBase"), (x, y + face * 0.32, z - 0.2), (0.18, 0.18, 0.04), p_iron, bev=0.008))


def step_stones(bag, rnd, x, y, n=2, w=1.2):
    for k in range(n):
        bag.add(bx(bag.nm("Step"), (x + rnd.uniform(-0.03, 0.03), y - 0.32 - k * 0.32, 0.1 - k * 0.04),
                   (w - k * 0.1, 0.36, 0.2 - k * 0.08), _pick(rnd, b_stone_lt, b_stone, b_stone_dk), bev=0.04))


def thatch_roof(bag, cx, cy, hw, hd, zt, th, over_x=0.4, over_y=0.4, layers=5, rnd=None):
    """Sapê: camadas grossas e arredondadas em cada água, rolo na cumeeira e beiral grosso."""
    cs, sn, tn = math.cos(th), math.sin(th), math.tan(th)
    ZR = zt + 0.05 + hd * tn
    ls = (hd + over_y) / cs
    rx = 2 * hw + 2 * over_x
    step = ls / layers
    for side in (-1, 1):
        for i in range(layers):
            s = (i + 0.5) * step
            off = 0.14 + 0.07 * (layers - 1 - i)
            p = (cx, cy + side * (s * cs + sn * off), ZR - s * sn + cs * off)
            bag.add(bx(bag.nm("Thatch"), p, (rx - 0.04 * i, step + 0.2, 0.24), b_thatch if i % 2 == 0 else b_straw,
                       rot=(-side * th, 0, 0), bev=0.09))
            if i < layers - 1:
                continue
            # franja irregular no beiral: tufos de comprimentos diferentes
            k, x = 0, cx - rx / 2 + 0.1
            while x < cx + rx / 2 - 0.1:
                w = rnd.uniform(0.28, 0.5)
                lo = s + step / 2 + rnd.uniform(0.02, 0.16)
                q = (x + w / 2, cy + side * (lo * cs + sn * (off + 0.05)), ZR - lo * sn + cs * (off + 0.05))
                bag.add(bx(bag.nm("Tuft"), q, (w - 0.03, 0.22, 0.2), (b_thatch_dk, b_thatch, b_straw)[(k + i) % 3],
                           rot=(-side * th, 0, rnd.uniform(-0.05, 0.05)), bev=0.07))
                x += w
                k += 1
        e = ls + 0.02
        p = (cx, cy + side * (e * cs + sn * 0.08), ZR - e * sn + cs * 0.08)
        bag.add(beam(bag.nm("Eave"), (cx - rx / 2 - 0.02, p[1], p[2]), (cx + rx / 2 + 0.02, p[1], p[2]), 0.13, b_thatch_dk, seg=7))
    bag.add(beam("ThatchRidge", (cx - rx / 2 - 0.04, cy, ZR + 0.36), (cx + rx / 2 + 0.04, cy, ZR + 0.36), 0.24, b_thatch_dk, seg=8))
    for i in range(5):   # amarrações da cumeeira
        x = cx - rx / 2 + 0.3 + i * (rx - 0.6) / 4
        bag.add(lathe(bag.nm("RidgeTie"), [(0.26, -0.06), (0.26, 0.06)], p_rope, seg=8, loc=(x, cy, ZR + 0.36),
                      rot=(0, PI / 2, 0), cap_top=False, cap_bot=False))
    return ZR + 0.6


def woodpile(bag, rnd, x, y, length=1.6, rows=3):
    """Lenha empilhada encostada numa parede lateral (toras ao longo de Y), com telhadinho."""
    _log_pile(bag, rnd, x, y, rows + 1, rows, length, r=0.13)
    bag.add(bx(bag.nm("PileRoof"), (x, y, rows * 0.24 + 0.32), (0.75, length + 0.3, 0.06), p_wood_dk, rot=(0, 0.25, 0), bev=0.01))


def barrel(bag, x, y, z=0.0, s=1.0, top=None):
    bag.add(lathe(bag.nm("Barrel"), [(0.26 * s, z), (0.3 * s, z + 0.2 * s), (0.32 * s, z + 0.4 * s), (0.3 * s, z + 0.6 * s),
                                     (0.26 * s, z + 0.78 * s)], p_wood, seg=10, loc=(x, y, 0)))
    for zz in (0.15, 0.63):
        bag.add(lathe(bag.nm("Hoop"), [(0.31 * s, z + (zz - 0.03) * s), (0.31 * s, z + (zz + 0.03) * s)], p_iron, seg=10,
                      loc=(x, y, 0), cap_top=False, cap_bot=False))
    if top:
        bag.add(part(bag.nm("BarrelTop"), "cyl", (x, y, z + 0.76 * s), (0.46 * s, 0.46 * s, 0.03), top, seg=10))


def crate(bag, x, y, z, s, yaw=0.0, m=None):
    bag.add(bx(bag.nm("Crate"), (x, y, z + s / 2), (s, s, s), m or p_wood, rot=(0, 0, yaw), bev=0.03))
    bag.add(bx(bag.nm("CrateBand"), (x, y, z + s / 2), (s + 0.02, s + 0.02, s * 0.14), p_wood_dk, rot=(0, 0, yaw), bev=0.01))
    bag.add(bx(bag.nm("CrateBand"), (x, y, z + s / 2), (s * 0.14, s + 0.02, s + 0.02), p_wood_dk, rot=(0, 0, yaw), bev=0.01))


def sack(bag, x, y, z, s, seed, m=None):
    bag.add(boulder(bag.nm("Sack"), (x, y, z), (0.45 * s, 0.4 * s, 0.55 * s), m or p_canvas, n=12, seed=seed))
    bag.add(lathe(bag.nm("SackTie"), [(0.07 * s, z + 0.5 * s), (0.05 * s, z + 0.62 * s)], p_rope, seg=6, loc=(x, y, 0)))


def bottle(bag, x, y, z, m, h=0.22, r=0.07, kind=0):
    """Frasco: 0 redondo, 1 alto, 2 cônico; rolha de madeira."""
    if kind == 0:
        bag.add(part(bag.nm("Flask"), "ico", (x, y, z + r), (2 * r, 2 * r, 2 * r), m, sub=1))
        neck = z + 2 * r
    elif kind == 1:
        bag.add(bx(bag.nm("Flask"), (x, y, z + h * 0.4), (r * 1.5, r * 1.5, h * 0.8), m, bev=0.02))
        neck = z + h * 0.8
    else:
        bag.add(lathe(bag.nm("Flask"), [(r * 1.2, z), (r * 0.4, z + h * 0.7)], m, seg=6, loc=(x, y, 0)))
        neck = z + h * 0.7
    bag.add(lathe(bag.nm("Neck"), [(r * 0.35, neck - 0.01), (r * 0.35, neck + 0.06)], b_glass, seg=5, loc=(x, y, 0)))
    bag.add(lathe(bag.nm("Cork"), [(r * 0.4, neck + 0.05), (r * 0.42, neck + 0.1)], p_wood_lt, seg=5, loc=(x, y, 0)))


# ================================================================ CASA A: enxaimel, telha vermelha
def build_house_a():
    rnd = random.Random(31)
    bag = Bag()
    a = bag.add
    b = Body(0, 0, 2.5, 2.0)
    Z0, Z1, ZT = 0.3, 0.95, 3.1
    th = math.radians(42)
    # fundação e rodapé de pedra (vão da porta na frente)
    a(bx("Foundation", (0, 0, 0.15), (2 * b.hw + 0.34, 2 * b.hd + 0.34, 0.3), b_stone_dk, bev=0.05))
    stone_band(bag, rnd, b, Z0, Z1, skip=[("-y", -0.62, 0.62)])
    a(bx("Walls", (0, 0, (Z1 + ZT) / 2), (2 * b.hw, 2 * b.hd, ZT - Z1), v_plaster, bev=0.0))
    a(bx("WallsLow", (0, 0, (Z0 + Z1) / 2), (2 * b.hw - 0.2, 2 * b.hd - 0.2, Z1 - Z0), v_plaster_dk, bev=0.0))
    for sx in (-1, 1):
        g, gi = b.hw * sx, (b.hw - 0.2) * sx
        a(hull(bag.nm("Gable"), [(g, -b.hd, ZT), (g, b.hd, ZT), (g, 0, ZT + b.hd * math.tan(th)),
                                 (gi, -b.hd, ZT), (gi, b.hd, ZT), (gi, 0, ZT + b.hd * math.tan(th))], v_plaster))
    corner_posts(bag, b, Z1, ZT)
    rail = 2.05
    half_timber(bag, b, "-y", Z1, ZT, posts=(-0.62, 0.62, -1.95, 1.95),
                rails=[(rail + 0.35, -2.4, -0.7), (rail + 0.35, 0.7, 2.4)],
                braces=[(-2.4, Z1 + 0.1, -1.95, 1.7), (2.4, Z1 + 0.1, 1.95, 1.7)])
    half_timber(bag, b, "+y", Z1, ZT, posts=(-0.8, 0.8), rails=[(rail, -2.4, 2.4)],
                braces=[(-2.4, Z1 + 0.1, -0.85, rail - 0.1), (2.4, Z1 + 0.1, 0.85, rail - 0.1), (-0.75, Z1 + 0.1, 0.75, rail - 0.1)])
    for face in ("-x", "+x"):
        half_timber(bag, b, face, Z1, ZT, posts=(-0.75, 0.75), rails=[(rail, -1.9, 1.9)],
                    braces=[(-1.9, Z1 + 0.1, -0.8, rail - 0.1), (1.9, Z1 + 0.1, 0.8, rail - 0.1)])
        for s in (-1, 1):   # escoras da empena paralelas ao telhado
            b.at(bag, face, s * 1.0, 0.03, ZT + 0.43, 1.3, 0.1, 0.13, v_timber, tilt=-s * th * 0.97, name="GableStrut")
        b.at(bag, face, 0, 0.03, ZT + 0.75, 0.14, 0.1, 1.3, v_timber, name="KingPost")
    # porta com moldura, degraus, alpendre e lampião
    door(bag, 0, -b.hd, Z0, 1.0, 1.95)
    for s in (-1, 1):
        b.at(bag, "-y", s * 0.6, 0.05, Z0 + 1.0, 0.16, 0.14, 2.05, v_timber, name="Jamb")
    b.at(bag, "-y", 0, 0.06, Z0 + 2.06, 1.4, 0.16, 0.2, v_timber, name="Lintel")
    step_stones(bag, rnd, 0, -b.hd - 0.02, n=2, w=1.4)
    pz, py = 2.75, -b.hd
    for s in (-1, 1):   # telhadinho de duas águas sobre a porta
        a(bx(bag.nm("Hood"), (s * 0.45, py - 0.42, pz + 0.18), (1.0, 0.95, 0.08), p_roof, rot=(0, s * 0.42, 0), bev=0.015))
        a(beam(bag.nm("HoodBracket"), (s * 0.7, py - 0.02, pz - 0.55), (s * 0.7, py - 0.75, pz - 0.02), 0.04, v_timber, seg=4))
    a(bx("HoodBeam", (0, py - 0.42, pz - 0.02), (1.6, 0.85, 0.1), v_timber, bev=0.015))
    a(hull("HoodGable", [(-0.85, py - 0.86, pz + 0.03), (0.85, py - 0.86, pz + 0.03), (0, py - 0.86, pz + 0.4),
                         (-0.85, py - 0.82, pz + 0.03), (0.85, py - 0.82, pz + 0.03), (0, py - 0.82, pz + 0.4)], v_plaster))
    lantern(bag, 1.05, -b.hd, 2.35)
    # janelas
    for s, fl in ((-1, v_flower_r), (1, v_flower_y)):
        window_on(bag, b, "-y", s * 1.35, 1.75, 0.7, 0.8, shutters=v_green, flowers=fl, rnd=rnd)
        window_on(bag, b, "+y", s * 1.6, 1.7, 0.6, 0.7)
    for face in ("-x", "+x"):
        window_on(bag, b, face, 0, 1.6, 0.6, 0.7, shutters=v_green)
        window_on(bag, b, face, 0, ZT + 0.85, 0.36, 0.42)
    # telhado
    top = gable_roof(bag, 0, 0, b.hw, b.hd, ZT, th, p_roof, p_roof_dk, rows=6, over_x=0.38, over_y=0.5, trim=v_timber)
    for s in (-1, 1):   # ponteiras de madeira cruzadas nas empenas
        a(bx(bag.nm("Finial"), (s * (b.hw + 0.4), 0, top + 0.12), (0.08, 0.1, 0.55), v_timber, bev=0.01))
    chimney(bag, rnd, 1.55, 1.05, ZT - 0.3, top + 0.7, w=0.58)
    # lenha no lado direito, barril de chuva no canto de trás
    woodpile(bag, rnd, b.hw + 0.5, 0.2, length=1.8)
    barrel(bag, -b.hw - 0.42, 1.45, top=p_water)
    _vexport(bag, "House", "house")


# ================================================================ CASA B: sapê
def build_house_b():
    rnd = random.Random(57)
    bag = Bag()
    a = bag.add
    b = Body(0, 0, 2.5, 2.0)
    Z0, Z1, ZT = 0.25, 1.15, 2.75
    th = math.radians(48)
    a(bx("Foundation", (0, 0, 0.13), (2 * b.hw + 0.3, 2 * b.hd + 0.3, 0.26), b_stone_dk, bev=0.05))
    stone_band(bag, rnd, b, Z0, Z1, depth=0.34, out=0.08, skip=[("-y", 0.05, 1.15)])
    a(bx("Walls", (0, 0, (Z1 + ZT) / 2), (2 * b.hw, 2 * b.hd, ZT - Z1), v_plaster_w, bev=0.0))
    a(bx("WallsLow", (0, 0, (Z0 + Z1) / 2), (2 * b.hw - 0.2, 2 * b.hd - 0.2, Z1 - Z0), v_plaster_dk, bev=0.0))
    tn = math.tan(th)
    for sx in (-1, 1):
        g, gi = b.hw * sx, (b.hw - 0.2) * sx
        a(hull(bag.nm("Gable"), [(g, -b.hd, ZT), (g, b.hd, ZT), (g, 0, ZT + b.hd * tn),
                                 (gi, -b.hd, ZT), (gi, b.hd, ZT), (gi, 0, ZT + b.hd * tn)], v_plaster_w))
    corner_posts(bag, b, Z1, ZT, w=0.2)
    for face in ("-y", "+y", "-x", "+x"):
        half_timber(bag, b, face, Z1, ZT, posts=(), m=v_timber)
    for face in ("-x", "+x"):   # madeira da empena em "A"
        b.at(bag, face, 0, 0.03, ZT + b.hd * tn * 0.42, 0.14, 0.1, b.hd * tn * 0.84, v_timber, name="KingPost")
        b.at(bag, face, 0, 0.03, ZT + 0.75, 2.2, 0.1, 0.12, v_timber, name="Collar")
        window_on(bag, b, face, 0, ZT + 0.32, 0.34, 0.36)
    # porta deslocada para a direita, com banco e vaso ao lado
    door(bag, 0.6, -b.hd, Z0, 0.9, 1.85)
    b.at(bag, "-y", 0.6, 0.06, Z0 + 1.98, 1.25, 0.16, 0.2, v_timber, name="Lintel")
    for s in (-1, 1):
        b.at(bag, "-y", 0.6 + s * 0.55, 0.05, Z0 + 0.95, 0.15, 0.14, 1.9, v_timber, name="Jamb")
    step_stones(bag, rnd, 0.6, -b.hd - 0.02, n=1, w=1.1)
    window_on(bag, b, "-y", -1.35, 1.75, 0.85, 0.7, shutters=v_blue, flowers=v_flower_v, rnd=rnd)
    window_on(bag, b, "-y", 1.85, 1.8, 0.4, 0.5)
    a(bx("BenchSeat", (-1.35, -b.hd - 0.35, 0.45), (1.1, 0.34, 0.07), p_wood_lt, bev=0.015))
    for s in (-1, 1):
        a(bx(bag.nm("BenchLeg"), (-1.35 + s * 0.45, -b.hd - 0.35, 0.21), (0.08, 0.28, 0.42), p_wood_dk, bev=0.01))
    a(lathe("Pot", [(0.12, 0.0), (0.17, 0.25), (0.19, 0.3)], p_roof, seg=8, loc=(1.55, -b.hd - 0.35, 0), cap_top=False))
    a(part("PotPlant", "ico", (1.55, -b.hd - 0.35, 0.4), (0.38, 0.38, 0.32), v_leaf, sub=1))
    for k in range(3):
        a(part(bag.nm("PotBloom"), "ico", (1.5 + k * 0.06, -b.hd - 0.47 + (k % 2) * 0.1, 0.55), (0.1, 0.1, 0.09), v_flower_w, sub=1))
    lantern(bag, -0.1, -b.hd, 2.1)
    for s in (-1, 1):
        window_on(bag, b, "+y", s * 1.2, 1.8, 0.6, 0.6, shutters=v_blue)
        window_on(bag, b, "+x" if s > 0 else "-x", -0.9, 1.75, 0.55, 0.6, shutters=v_blue)
    top = thatch_roof(bag, 0, 0, b.hw, b.hd, ZT, th, rnd=rnd)
    chimney(bag, rnd, -1.6, 0.35, ZT - 0.2, top + 0.7, w=0.55)
    # horta de ervas no lado esquerdo e cerquinha
    for k in range(3):
        y = -0.9 + k * 0.75
        a(bx(bag.nm("Bed"), (-b.hw - 0.75, y, 0.08), (0.75, 0.55, 0.16), b_soil, bev=0.04))
        for j in range(3):
            a(part(bag.nm("Herb"), "ico", (-b.hw - 0.97 + j * 0.22, y + rnd.uniform(-0.08, 0.08), 0.24), (0.2, 0.2, 0.22),
                   (v_leaf, v_herb)[(j + k) % 2], sub=1))
    for y in (-1.3, -0.1, 1.1):
        a(beam(bag.nm("Picket"), (-b.hw - 1.2, y, 0), (-b.hw - 1.2, y, 0.6), 0.035, p_wood_dk, seg=5))
    a(bx("PicketRail", (-b.hw - 1.2, -0.1, 0.42), (0.05, 2.5, 0.06), p_wood, bev=0.01))
    crate(bag, b.hw + 0.4, 1.3, 0.0, 0.5, 0.2)
    sack(bag, b.hw + 0.45, 0.6, 0.0, 1.0, 3)
    _vexport(bag, "HouseB", "house_b")


# ================================================================ CASA C: sobrado de pedra e ardósia
def build_house_c():
    rnd = random.Random(83)
    bag = Bag()
    a = bag.add
    b = Body(0, 0, 2.5, 2.0)
    up = Body(0, 0, 2.6, 2.18)                  # andar de cima em balanço
    Z0, Z1, ZT = 0.3, 1.85, 3.8
    th = math.radians(44)
    a(bx("Foundation", (0, 0, 0.15), (2 * b.hw + 0.34, 2 * b.hd + 0.34, 0.3), b_stone_dk, bev=0.05))
    stone_band(bag, rnd, b, Z0, Z1, depth=0.36, out=0.0, skip=[("-y", -0.62, 0.62)])
    a(bx("GroundCore", (0, 0, (Z0 + Z1) / 2), (2 * b.hw - 0.3, 2 * b.hd - 0.3, Z1 - Z0), v_plaster_dk, bev=0.0))
    a(bx("Floor2", (0, 0, Z1 + 0.08), (2 * up.hw + 0.12, 2 * up.hd + 0.12, 0.16), v_timber, bev=0.02))
    for x in (-2.0, -1.0, 0.0, 1.0, 2.0):   # pontas das vigas do balanço
        for s in (-1, 1):
            a(bx(bag.nm("Joist"), (x, s * (up.hd + 0.02), Z1 - 0.06), (0.14, 0.3, 0.16), v_timber, bev=0.015))
    a(bx("Upper", (0, 0, (Z1 + ZT) / 2 + 0.08), (2 * up.hw, 2 * up.hd, ZT - Z1 - 0.16), v_plaster, bev=0.0))
    corner_posts(bag, up, Z1 + 0.16, ZT, w=0.22)
    zr = Z1 + 0.85
    for face in ("-y", "+y"):
        half_timber(bag, up, face, Z1 + 0.16, ZT, posts=(-1.55, -0.5, 0.5, 1.55), rails=[(zr - 0.35, -2.5, 2.5)],
                    braces=[(-2.5, zr - 0.3, -1.6, ZT - 0.2), (2.5, zr - 0.3, 1.6, ZT - 0.2),
                            (-0.45, zr - 0.3, 0.45, ZT - 0.2), (0.45, zr - 0.3, -0.45, ZT - 0.2)])
    for face in ("-x", "+x"):
        half_timber(bag, up, face, Z1 + 0.16, ZT, posts=(-0.7, 0.7), rails=[(zr - 0.35, -2.1, 2.1)],
                    braces=[(-2.1, zr - 0.3, -0.75, ZT - 0.2), (2.1, zr - 0.3, 0.75, ZT - 0.2)])
    # térreo: porta em arco de pedra e janelas gradeadas
    door(bag, 0, -b.hd, Z0, 1.05, 1.5, studs=True, arch_mat=b_stone_lt)
    step_stones(bag, rnd, 0, -b.hd - 0.02, n=2, w=1.5)
    for s in (-1, 1):
        window_on(bag, b, "-y", s * 1.55, 1.1, 0.6, 0.65, bars=True, frame=b_stone_dk)
        window_on(bag, b, "+y", s * 1.3, 1.1, 0.55, 0.6, bars=True, frame=b_stone_dk)
        window_on(bag, b, "+x" if s > 0 else "-x", 0, 1.1, 0.55, 0.6, bars=True, frame=b_stone_dk)
    # andar de cima: janelas com venezianas vermelhas e floreiras
    for s, fl in ((-1, v_flower_r), (1, v_flower_w)):
        window_on(bag, up, "-y", s * 1.05, zr + 0.12, 0.6, 0.75, shutters=v_red, flowers=fl, rnd=rnd)
        window_on(bag, up, "+y", s * 1.05, zr + 0.12, 0.6, 0.7, shutters=v_red)
    for face in ("-x", "+x"):
        window_on(bag, up, face, 0, zr + 0.12, 0.55, 0.7, shutters=v_red)
    # telhado de ardósia com água-furtada na frente
    top = gable_roof(bag, 0, 0, up.hw, up.hd, ZT, th, v_slate, v_slate_dk, rows=7, over_x=0.35, over_y=0.3,
                     gable=v_plaster, trim=v_timber)
    tn = math.tan(th)
    dx, dw = 0.0, 0.62
    dz0 = ZT + 0.35
    y_front = -up.hd + 0.05
    y_back = -up.hd + (dz0 + 1.0 - ZT) / tn
    a(bx("DormerBody", (dx, (y_front + y_back) / 2, dz0 + 0.42), (2 * dw, y_back - y_front, 0.95), v_plaster, bev=0.0))
    for s in (-1, 1):
        a(bx(bag.nm("DormerPost"), (dx + s * dw, y_front, dz0 + 0.42), (0.12, 0.12, 0.95), v_timber, bev=0.01))
    window(bag, (dx, y_front, dz0 + 0.4), 0.5, 0.55, "-y", frame=v_timber)
    dth = math.radians(40)
    for s in (-1, 1):
        a(bx(bag.nm("DormerRoof"), (dx + s * (dw / 2 + 0.06), (y_front + y_back) / 2 - 0.1, dz0 + 0.98 + dw * math.tan(dth) / 2),
             (dw / math.cos(dth) + 0.25, y_back - y_front + 0.35, 0.08), v_slate_dk, rot=(0, s * dth, 0), bev=0.015))
    a(hull("DormerGable", [(dx - dw, y_front - 0.02, dz0 + 0.9), (dx + dw, y_front - 0.02, dz0 + 0.9),
                           (dx, y_front - 0.02, dz0 + 0.9 + dw * math.tan(dth)),
                           (dx - dw, y_front + 0.1, dz0 + 0.9), (dx + dw, y_front + 0.1, dz0 + 0.9),
                           (dx, y_front + 0.1, dz0 + 0.9 + dw * math.tan(dth))], v_plaster))
    chimney(bag, rnd, -1.7, 0.9, ZT - 0.3, top + 0.8, w=0.62)
    chimney(bag, rnd, 1.7, 0.9, ZT - 0.3, top + 0.55, w=0.5)
    lantern(bag, -0.85, -b.hd, 1.55)
    lantern(bag, 0.85, -b.hd, 1.55)
    barrel(bag, b.hw + 0.4, -1.3)
    barrel(bag, b.hw + 0.45, -0.6, s=0.85)
    crate(bag, -b.hw - 0.45, 1.2, 0.0, 0.55, 0.3)
    _vexport(bag, "HouseC", "house_c")


# ================================================================ FERRARIA (4,6 x 4,6)
def build_shop_smithy():
    """Oficina aberta na frente. Origem = onde o ferreiro fica; a forja (prop) fica em y=+1,6 e a bigorna em y=-0,6.
    Parede de pedra no fundo com a chaminé por cima da forja, meia-parede à esquerda com ferramentas,
    à direita a tina de têmpera, carvão e a estante de armas."""
    rnd = random.Random(101)
    bag = Bag()
    a = bag.add
    X, YF, YB = 2.0, -1.3, 2.6           # meia largura, frente (esteios), fundo (parede); cabe no vão entre duas casas
    ZT = 2.7
    # chão de terra batida e pedras
    a(bx("Floor", (0, (YF + YB) / 2 - 0.2, 0.03), (2 * X + 0.4, YB - YF + 0.8, 0.06), b_soil_lt, bev=0.02))
    for i in range(14):
        x, y = rnd.uniform(-X, X), rnd.uniform(YF - 0.4, YB - 0.3)
        if abs(x) < 1.0 and -1.0 < y < 2.2:
            continue
        a(bx(bag.nm("Flag"), (x, y, 0.06), (rnd.uniform(0.35, 0.6), rnd.uniform(0.3, 0.5), 0.06),
             _pick(rnd, b_stone, b_stone_lt, b_stone_dk), rot=(0, 0, rnd.uniform(0, PI)), bev=0.02))
    # parede do fundo e chaminé grande sobre a forja
    courses(bag, rnd, -X, X, YB, 0.4, 0.0, ZT, (b_stone, b_stone_lt, b_stone_dk))
    gz = ZT + 0.02 + (YB - YF) / 2 * math.tan(math.radians(30))
    a(hull("BackGable", [(-X, YB - 0.15, ZT), (X, YB - 0.15, ZT), (0, YB - 0.15, ZT + 0.3),
                         (-X, YB + 0.15, ZT), (X, YB + 0.15, ZT), (0, YB + 0.15, ZT + 0.3)], b_stone_dk))
    chimney(bag, rnd, 0, YB - 0.1, 1.4, gz + 2.0, w=0.95)
    a(bx("Hood", (0, 1.95, 1.75), (1.3, 0.95, 0.5), b_stone_dk, bev=0.04, taper=(0.7, 0.75)))
    a(bx("HoodFace", (0, 1.47, 1.62), (1.25, 0.06, 0.18), p_iron, bev=0.01))
    # meia-parede esquerda com ferramentas penduradas; direita aberta
    courses(bag, rnd, YF + 0.3, YB - 0.2, -X + 0.2, 0.35, 0.0, 1.05, (b_stone, b_stone_lt, b_stone_dk), axis="y")
    a(bx("LeftCap", (-X + 0.2, (YF + 0.3 + YB) / 2 - 0.1, 1.1), (0.45, YB - YF - 0.4, 0.1), p_wood_dk, bev=0.02))
    # esteios e telhado de duas águas (cumeeira ao longo de X)
    for x in (-X, X):   # sem esteio no meio: da praça se vê o ferreiro na bigorna
        a(beam(bag.nm("Post"), (x, YF, 0.0), (x, YF, ZT), 0.11, v_timber, seg=6))
        a(bx(bag.nm("PostBase"), (x, YF, 0.1), (0.32, 0.32, 0.2), b_stone_lt, bev=0.03))
    for x in (-X, X):
        a(beam(bag.nm("Post"), (x, YB - 0.2, 1.05), (x, YB - 0.2, ZT), 0.1, v_timber, seg=6))
        a(beam(bag.nm("Brace"), (x, YF + 0.05, ZT - 0.75), (x, YF + 0.75, ZT - 0.05), 0.05, v_timber, seg=4))
    a(bx("FrontBeam", (0, YF, ZT - 0.1), (2 * X + 0.3, 0.24, 0.3), v_timber, bev=0.02))
    for s in (-1, 1):
        a(beam(bag.nm("FrontBrace"), (s * (X - 0.05), YF, ZT - 0.75), (s * (X - 0.7), YF, ZT - 0.12), 0.05, v_timber, seg=4))
    for x in (-X, X):
        a(bx(bag.nm("SideBeam"), (x, (YF + YB) / 2, ZT - 0.08), (0.2, YB - YF + 0.2, 0.22), v_timber, bev=0.02))
    cy, hd = (YF + YB) / 2, (YB - YF) / 2
    gable_roof(bag, 0, cy, X, hd, ZT, math.radians(30), p_roof, p_roof_dk, rows=5, over_x=0.22, over_y=0.5, trim=v_timber)
    for s in (-1, 1):
        g = s * X
        a(hull(bag.nm("Gable"), [(g, YF, ZT), (g, YB, ZT), (g, cy, ZT + hd * math.tan(math.radians(30)) - 0.02),
                                 (g - s * 0.12, YF, ZT), (g - s * 0.12, YB, ZT),
                                 (g - s * 0.12, cy, ZT + hd * math.tan(math.radians(30)) - 0.02)], p_wood_dk))
    # placa: martelo sobre bigorna
    a(bx("SignPlate", (X + 0.15, YF, ZT - 0.35), (0.6, 0.06, 0.06), p_iron, bev=0.01))
    for s in (-1, 1):
        a(beam(bag.nm("SignChain"), (X + 0.15 + s * 0.2, YF, ZT - 0.35), (X + 0.15 + s * 0.2, YF, ZT - 0.5), 0.01, p_iron, seg=4))
    a(bx("SignBoard", (X + 0.15, YF, ZT - 0.78), (0.55, 0.06, 0.5), p_wood, bev=0.02))
    sx, sy, sz = X + 0.15, YF - 0.04, ZT - 0.78
    a(bx("SignAnvil", (sx, sy, sz - 0.06), (0.32, 0.03, 0.09), p_iron_lt, bev=0.01))
    a(bx("SignAnvilFoot", (sx, sy, sz - 0.15), (0.14, 0.03, 0.1), p_iron_lt, bev=0.01))
    a(bx("SignHammer", (sx + 0.05, sy, sz + 0.1), (0.04, 0.03, 0.26), p_wood_lt, rot=(0, 0.6, 0), bev=0.0))
    a(bx("SignHammerHead", (sx - 0.04, sy, sz + 0.2), (0.15, 0.03, 0.08), p_iron_lt, rot=(0, 0.6, 0), bev=0.0))
    # ferramentas na meia-parede esquerda e na parede do fundo
    a(bx("ToolRack", (-X + 0.42, 0.4, 1.75), (0.06, 2.2, 0.1), p_wood_dk, bev=0.01))
    a(beam("ToolRackPostA", (-X + 0.3, -0.7, 1.1), (-X + 0.3, -0.7, ZT - 0.1), 0.05, v_timber, seg=5))
    a(beam("ToolRackPostB", (-X + 0.3, 1.5, 1.1), (-X + 0.3, 1.5, ZT - 0.1), 0.05, v_timber, seg=5))
    for i in range(5):
        y = -0.4 + i * 0.4
        a(bx(bag.nm("Handle"), (-X + 0.47, y, 1.45), (0.035, 0.035, 0.6), p_wood_lt, bev=0.0))
        if i % 2 == 0:   # tenaz
            a(bx(bag.nm("Tong"), (-X + 0.47, y + 0.04, 1.42), (0.03, 0.03, 0.62), p_iron, rot=(0.12, 0, 0), bev=0.0))
        else:            # martelo
            a(bx(bag.nm("Head"), (-X + 0.47, y, 1.17), (0.08, 0.2, 0.08), p_iron_lt, bev=0.01))
    for k, x in enumerate((-1.45, -0.95, 0.95, 1.45)):   # ferraduras e foices na parede do fundo
        a(lathe(bag.nm("Shoe"), [(0.11, -0.015), (0.11, 0.015), (0.07, 0.015), (0.07, -0.015)], p_iron, seg=8,
                loc=(x, YB - 0.22, 1.9 + (k % 2) * 0.25), rot=(PI / 2, 0, 0)))
    # tina de têmpera, carvão, barra de ferro e estante de armas à direita
    a(lathe("Tub", [(0.4, 0.0), (0.45, 0.55), (0.47, 0.6)], p_wood, seg=10, loc=(1.4, 0.4, 0), cap_top=False))
    a(part("TubWater", "cyl", (1.4, 0.4, 0.52), (0.84, 0.84, 0.04), p_water, seg=10))
    for z in (0.12, 0.45):
        a(lathe(bag.nm("TubHoop"), [(0.43 + z * 0.08, z - 0.03), (0.43 + z * 0.08, z + 0.03)], p_iron, seg=10,
                loc=(1.4, 0.4, 0), cap_top=False, cap_bot=False))
    for i in range(7):
        a(boulder(bag.nm("Coal"), (1.5 + rnd.uniform(-0.2, 0.2), 1.95 + rnd.uniform(-0.2, 0.2), 0.36),
                  (0.22, 0.2, 0.16), v_soot, n=9, seed=200 + i))
    a(bx("CoalBin", (1.5, 1.95, 0.2), (0.7, 0.65, 0.4), p_wood_dk, bev=0.02))
    for i in range(6):
        a(bx(bag.nm("Bar"), (1.75, 1.2 + i * 0.04, 0.55 + i * 0.01), (0.04, 0.04, 1.1), p_iron_lt, rot=(0.15 - i * 0.05, 0.3, 0), bev=0.0))
    a(bx("RackBase", (X - 0.15, -0.55, 0.06), (0.3, 1.2, 0.12), p_wood_dk, bev=0.02))
    a(bx("RackBar", (X - 0.15, -0.55, 1.0), (0.1, 1.2, 0.08), p_wood_dk, bev=0.01))
    for i in range(4):
        y = -1.0 + i * 0.3
        a(bx(bag.nm("Blade"), (X - 0.15, y, 0.62), (0.03, 0.06, 0.95), p_iron_lt, bev=0.0))
        a(bx(bag.nm("Guard"), (X - 0.15, y, 1.12), (0.04, 0.2, 0.04), p_gold if i == 1 else p_iron, bev=0.0))
        a(bx(bag.nm("Grip"), (X - 0.15, y, 1.25), (0.035, 0.035, 0.22), p_wood_dk, bev=0.0))
    gx, gy = -1.35, -1.05
    a(lathe("Grindstone", [(0.0, -0.06), (0.32, -0.06), (0.32, 0.06), (0.0, 0.06)], b_stone_lt, seg=12, loc=(gx, gy, 0.6),
            rot=(0, PI / 2, 0)))
    for s in (-1, 1):
        a(bx(bag.nm("GrindLeg"), (gx + s * 0.12, gy, 0.3), (0.06, 0.08, 0.6), p_wood_dk, bev=0.01))
    a(beam("GrindAxle", (gx - 0.2, gy, 0.6), (gx + 0.2, gy, 0.6), 0.025, p_iron, seg=5))
    torch(bag, -X + 0.1, YF + 0.05, 2.0)
    _vexport(bag, "Smithy", "shop_smithy")


# ================================================================ BOTICA DO ALQUIMISTA (5,6 x 4,6)
def build_shop_alchemist():
    """Casa estreita de enxaimel com telhado verde-azulado, torrinha redonda no canto de trás à esquerda,
    vitrine de frascos que brilham, caldeirão borbulhando na frente e ervas secando no varal."""
    rnd = random.Random(131)
    bag = Bag()
    a = bag.add
    b = Body(0.2, 0, 2.2, 1.9)
    Z0, Z1, ZT = 0.3, 0.9, 3.4
    th = math.radians(50)
    a(bx("Foundation", (b.cx, 0, 0.15), (2 * b.hw + 0.34, 2 * b.hd + 0.34, 0.3), b_stone_dk, bev=0.05))
    stone_band(bag, rnd, b, Z0, Z1, mats=(b_mage_st, b_stone, b_mage_st_dk), skip=[("-y", 0.45, 1.45)])
    a(bx("Walls", (b.cx, 0, (Z1 + ZT) / 2), (2 * b.hw, 2 * b.hd, ZT - Z1), v_plaster, bev=0.0))
    a(bx("WallsLow", (b.cx, 0, (Z0 + Z1) / 2), (2 * b.hw - 0.2, 2 * b.hd - 0.2, Z1 - Z0), v_plaster_dk, bev=0.0))
    corner_posts(bag, b, Z1, ZT)
    half_timber(bag, b, "-y", Z1, ZT, posts=(-0.25, 0.4, 1.5), rails=[(2.25, -2.1, -0.32), (2.4, 0.47, 1.43)],
                braces=[(-2.1, 2.3, -1.3, ZT - 0.2), (-0.32, 2.3, -1.1, ZT - 0.2)])
    half_timber(bag, b, "+y", Z1, ZT, posts=(-0.7, 0.7), rails=[(2.0, -2.1, 2.1)],
                braces=[(-2.1, Z1 + 0.1, -0.75, 1.95), (2.1, Z1 + 0.1, 0.75, 1.95)])
    for face in ("-x", "+x"):
        half_timber(bag, b, face, Z1, ZT, posts=(-0.6, 0.6), rails=[(2.0, -1.8, 1.8)],
                    braces=[(-1.8, 2.05, -0.65, ZT - 0.2), (1.8, 2.05, 0.65, ZT - 0.2)])
    # vitrine larga à esquerda da porta, com prateleiras de frascos
    vx, vz, vw, vh = -1.25, 1.55, 1.5, 1.05
    x, y = b.point("-y", vx, 0)
    for s in (-1, 1):
        a(bx(bag.nm("ShopFrame"), (x + s * (vw / 2 + 0.05), y - 0.1, vz), (0.12, 0.2, vh + 0.2), v_timber, bev=0.02))
        a(bx(bag.nm("ShopFrame"), (x, y - 0.1, vz + s * (vh / 2 + 0.05)), (vw + 0.2, 0.2, 0.12), v_timber, bev=0.02))
    a(bx("ShopBack", (x, y - 0.01, vz), (vw, 0.02, vh), v_soot, bev=0.0))
    a(bx("ShopSill", (x, y - 0.2, vz - vh / 2 - 0.06), (vw + 0.35, 0.36, 0.08), v_timber, bev=0.015))
    for k, zz in enumerate((vz - vh / 2 + 0.04, vz + 0.05)):
        a(bx(bag.nm("ShopShelf"), (x, y - 0.1, zz), (vw - 0.05, 0.18, 0.04), p_wood, bev=0.005))
        for j in range(6):
            m = (v_potion_g, v_potion_r, v_potion_b, v_potion_p)[(j + k) % 4]
            bottle(bag, x - vw / 2 + 0.15 + j * 0.24, y - 0.1, zz + 0.02, m, h=0.24, r=0.06, kind=(j + k * 2) % 3)
    for k in (-1, 1):
        a(bx(bag.nm("ShopMullion"), (x + k * vw / 4, y - 0.17, vz), (0.05, 0.03, vh), v_timber, bev=0.0))
    a(bx("ShopTransom", (x, y - 0.17, vz + vh / 4 + 0.1), (vw, 0.03, 0.05), v_timber, bev=0.0))
    # porta, degrau, lampião verde e placa com frasco
    door(bag, b.cx + 0.95, -b.hd, Z0, 0.9, 1.9)
    b.at(bag, "-y", 0.95, 0.06, Z0 + 2.0, 1.2, 0.16, 0.2, v_timber, name="Lintel")
    step_stones(bag, rnd, b.cx + 0.95, -b.hd - 0.02, n=1, w=1.0)

    # placa pendurada na quina da frente direita, de lado para a rua
    qx, qy = b.cx + b.hw, -b.hd
    a(bx("SignArm", (qx + 0.42, qy, 2.75), (0.84, 0.05, 0.05), p_iron, bev=0.01))
    a(beam("SignStay", (qx + 0.02, qy, 2.4), (qx + 0.6, qy, 2.73), 0.02, p_iron, seg=4))
    a(bx("SignBoard", (qx + 0.6, qy, 2.35), (0.55, 0.06, 0.5), v_teal_dk, bev=0.02))
    for s in (-1, 1):
        a(beam(bag.nm("SignChain"), (qx + 0.6 + s * 0.17, qy, 2.75), (qx + 0.6 + s * 0.17, qy, 2.6), 0.01, p_iron, seg=4))
        fx = qx + 0.6
        a(part(bag.nm("SignFlask"), "ico", (fx, qy + s * 0.04, 2.3), (0.26, 0.04, 0.26), v_potion_g, sub=1))
        a(bx(bag.nm("SignNeck"), (fx, qy + s * 0.04, 2.48), (0.07, 0.04, 0.12), b_glass, bev=0.0))
        a(bx(bag.nm("SignCork"), (fx, qy + s * 0.04, 2.56), (0.09, 0.04, 0.05), p_wood_lt, bev=0.0))
    # janelas de cima e dos lados
    for u in (-1.3, 0.95):
        window_on(bag, b, "-y", u, 2.85, 0.5, 0.55, shutters=v_teal)
    window_on(bag, b, "+x", 0, 1.8, 0.55, 0.7, shutters=v_teal, flowers=v_flower_v, rnd=rnd)
    window_on(bag, b, "-x", 0.6, 1.8, 0.5, 0.7, shutters=v_teal)
    for u in (-1.0, 1.0):
        window_on(bag, b, "+y", u, 1.8, 0.5, 0.6)
    top = gable_roof(bag, b.cx, 0, b.hw, b.hd, ZT, th, v_teal, v_teal_dk, rows=6, over_x=0.32, over_y=0.45,
                     gable=v_plaster, trim=v_timber)
    for face in ("-x", "+x"):
        b.at(bag, face, 0, 0.03, ZT + 0.9, 0.14, 0.1, 1.6, v_timber, name="KingPost")
        window_on(bag, b, face, 0, ZT + 0.6, 0.32, 0.4, arch=True)
    # chaminé torta com boca verde (fumaça de poção)
    chimney(bag, rnd, b.cx + 1.3, 0.75, ZT - 0.3, top + 0.4, w=0.5, mats=(b_mage_st, b_stone, b_mage_st_dk))
    a(bx("FlueGlow", (b.cx + 1.3, 0.75, top + 0.73), (0.18, 0.18, 0.03), v_brew, bev=0.0))
    # torrinha redonda no canto de trás à esquerda
    TX, TY, TR = b.cx - b.hw - 0.05, b.hd - 0.1, 0.85
    TT = ZT + 1.5
    tower_ring(bag, rnd, TR + 0.08, TR, 0.0, TT, 9, 0.3, (b_mage_st, b_stone, b_mage_st_dk), cx=TX, cy=TY,
               hmin=0.3, hmax=0.42)
    a(lathe("TowerBelt", [(TR + 0.08, TT - 0.02), (TR + 0.12, TT + 0.1), (TR + 0.08, TT + 0.16)], v_timber, seg=9,
            loc=(TX, TY, 0)))
    for k in range(3):
        ang = PI * 0.9 + k * 0.7
        wx, wy = TX + math.cos(ang) * (TR + 0.02), TY + math.sin(ang) * (TR + 0.02)
        a(bx(bag.nm("TowerWin"), (wx, wy, TT - 0.65), (0.14, 0.3, 0.5), v_potion_b if k == 1 else b_glass, rot=(0, 0, ang), bev=0.02))
        a(bx(bag.nm("TowerWinArch"), (wx, wy, TT - 0.35), (0.16, 0.38, 0.1), b_mage_st_dk, rot=(0, 0, ang), bev=0.02))
    cone_roof(bag, TT + 0.15, TR + 0.25, 2.0, v_teal, seg=9, cx=TX, cy=TY, band=v_teal_dk, wobble=0.04)
    a(part("Moon", "cyl", (TX, TY, TT + 2.95), (0.22, 0.22, 0.03), p_gold, rot=(PI / 2, 0, 0.6), seg=10))
    # caldeirão na frente da vitrine, com fogo e poção borbulhando
    cx, cy = b.cx - 1.25, -b.hd - 0.95
    for s in range(3):
        ang = s * 2 * PI / 3 + 0.3
        a(beam(bag.nm("CauldronLeg"), (cx + math.cos(ang) * 0.35, cy + math.sin(ang) * 0.35, 0.0),
               (cx + math.cos(ang) * 0.25, cy + math.sin(ang) * 0.25, 0.3), 0.035, p_iron, seg=4))
    a(lathe("Cauldron", [(0.0, 0.2), (0.28, 0.24), (0.42, 0.42), (0.44, 0.58), (0.38, 0.72), (0.42, 0.76), (0.36, 0.78)],
            p_iron, seg=12, loc=(cx, cy, 0), cap_top=False))
    a(part("Brew", "cyl", (cx, cy, 0.72), (0.74, 0.74, 0.03), v_brew, seg=12))
    for k in range(4):
        a(part(bag.nm("Bubble"), "ico", (cx + rnd.uniform(-0.2, 0.2), cy + rnd.uniform(-0.2, 0.2), 0.76),
               (0.1, 0.1, 0.08), v_potion_g, sub=1))
    for k in range(5):
        a(boulder(bag.nm("Firewood"), (cx + math.cos(k * 1.3) * 0.15, cy + math.sin(k * 1.3) * 0.15, 0.0), (0.16, 0.12, 0.1),
                  p_wood_dk, n=8, seed=300 + k))
    a(part("CauldronFire", "cone", (cx, cy, 0.12), (0.34, 0.34, 0.22), p_fire, seg=6))
    a(beam("Ladle", (cx + 0.1, cy, 0.65), (cx + 0.38, cy - 0.05, 1.15), 0.02, p_wood_lt, seg=4))
    # varal de ervas secando entre a parede e um poste
    px, py = b.cx + b.hw + 0.9, -1.0
    a(beam("HerbPole", (px, py, 0.0), (px, py, 2.2), 0.05, v_timber, seg=6))
    a(beam("HerbLine", (px, py, 2.1), (b.cx + b.hw + 0.02, py + 0.5, 2.35), 0.012, p_rope, seg=4))
    for k in range(4):
        t = (k + 0.5) / 4
        hx, hy, hz = px + (b.cx + b.hw - px) * t, py + 0.5 * t, 2.1 + 0.25 * t - 0.05
        a(bx(bag.nm("HerbStem"), (hx, hy, hz - 0.16), (0.04, 0.04, 0.3), v_herb, bev=0.0))
        a(part(bag.nm("HerbBunch"), "cone", (hx, hy, hz - 0.4), (0.18, 0.18, 0.28), (v_herb, v_leaf, v_flower_v, v_herb)[k], seg=5,
               rot=(PI, 0, 0)))
    # canteiro de cogumelos e caixotes de frascos
    for k in range(5):
        mx, my = b.cx + b.hw + 0.4 + rnd.uniform(-0.2, 0.25), 0.6 + k * 0.3
        h = rnd.uniform(0.12, 0.25)
        a(beam(bag.nm("MushStem"), (mx, my, 0.0), (mx, my, h), 0.03, v_flower_w, seg=5))
        a(lathe(bag.nm("MushCap"), [(0.11, h - 0.02), (0.08, h + 0.05), (0.0, h + 0.07)], v_mush, seg=7, loc=(mx, my, 0)))
    crate(bag, b.cx + b.hw + 0.45, -0.3, 0.0, 0.5, 0.25)
    for k in range(3):
        bottle(bag, b.cx + b.hw + 0.35 + k * 0.12, -0.35 + (k % 2) * 0.1, 0.5, (v_potion_b, v_potion_r, v_potion_g)[k], kind=k)
    _vexport(bag, "Alchemist", "shop_alchemist")


# ================================================================ EMPÓRIO DO MERCADOR (6 x 5)
def build_shop_merchant():
    """Loja de pedra e tábua com balcão aberto na frente: a janela grande tem a veneziana de cima erguida
    como toldo e um toldo listrado por cima; mercadorias no balcão e em volta."""
    rnd = random.Random(151)
    bag = Bag()
    a = bag.add
    b = Body(0, 0.4, 2.6, 1.8)
    Z0, Z1, ZT = 0.3, 1.0, 3.0
    th = math.radians(36)
    a(bx("Foundation", (0, b.cy, 0.15), (2 * b.hw + 0.34, 2 * b.hd + 0.34, 0.3), b_stone_dk, bev=0.05))
    stone_band(bag, rnd, b, Z0, Z1, skip=[("-y", -2.0, 0.6), ("-y", 1.2, 2.2)])
    # paredes de tábuas na vertical sobre o rodapé
    a(bx("Walls", (0, b.cy, (Z0 + ZT) / 2), (2 * b.hw - 0.1, 2 * b.hd - 0.1, ZT - Z0), p_wood_dk, bev=0.0))
    for face in ("+y", "-x", "+x"):
        L = b.span(face)
        n = int(L / 0.3)
        for i in range(n):
            u = -L / 2 + (i + 0.5) * L / n
            b.at(bag, face, u, 0.0, (Z1 + ZT) / 2, L / n - 0.02, 0.08, ZT - Z1, p_wood if (i * 7) % 3 else p_wood_lt,
                 bev=0.01, name="Board")
    corner_posts(bag, b, Z0, ZT, w=0.26)
    for face in ("-y", "+y", "-x", "+x"):
        b.at(bag, face, 0, 0.05, ZT - 0.08, b.span(face) + 0.2, 0.16, 0.18, v_timber, name="Plate")
    # frente: balcão largo à esquerda, porta à direita
    cw, cx = 2.4, -0.7
    a(bx("FrontWall", (cx, -b.hd + b.cy, (Z0 + 1.0) / 2 + 0.1), (cw, 0.2, 0.9), p_wood, bev=0.01))
    for i in range(8):
        a(bx(bag.nm("CounterBoard"), (cx - cw / 2 + (i + 0.5) * cw / 8, -b.hd + b.cy - 0.12, 0.72), (cw / 8 - 0.02, 0.05, 0.84),
             p_wood if i % 2 else p_wood_lt, bev=0.008))
    a(bx("CounterTop", (cx, -b.hd + b.cy - 0.12, 1.2), (cw + 0.3, 0.6, 0.08), v_timber, bev=0.02))
    a(bx("OpeningBack", (cx, -b.hd + b.cy + 0.3, 2.0), (cw, 0.05, 1.5), v_soot, bev=0.0))
    for k, zz in enumerate((1.6, 2.15)):   # prateleiras lá dentro
        a(bx(bag.nm("InShelf"), (cx, -b.hd + b.cy + 0.18, zz), (cw - 0.1, 0.22, 0.04), p_wood, bev=0.005))
        for j in range(7):
            m = (v_copper, p_canvas, b_cloth_y, b_red, b_blue, p_gold, b_cloth_w)[(j + k * 3) % 7]
            a(bx(bag.nm("Ware"), (cx - cw / 2 + 0.2 + j * 0.33, -b.hd + b.cy + 0.18, zz + 0.13), (0.2, 0.16, 0.22 - (j % 2) * 0.06),
                 m, bev=0.03))
    a(bx("OpeningHead", (cx, -b.hd + b.cy, ZT - 0.12), (cw + 0.3, 0.22, 0.24), v_timber, bev=0.02))
    for s in (-1, 1):
        a(bx(bag.nm("OpeningPost"), (cx + s * (cw / 2 + 0.06), -b.hd + b.cy, (Z0 + ZT) / 2), (0.16, 0.2, ZT - Z0), v_timber, bev=0.02))
    # toldo listrado por cima de tudo
    n = 9
    aw = (2 * b.hw + 0.3) / n
    ath = math.radians(24)
    L = 1.5
    ay = -b.hd + b.cy - L / 2 * math.cos(ath)
    az = ZT + 0.2 - L / 2 * math.sin(ath)
    for i in range(n):
        x = -b.hw - 0.15 + (i + 0.5) * aw
        m = b_cloth_w if i % 2 else v_red
        a(bx(bag.nm("Awning"), (x, ay, az), (aw, L, 0.04), m, rot=(ath, 0, 0), bev=0.0))
        ey, ez = -b.hd + b.cy - L * math.cos(ath), ZT + 0.2 - L * math.sin(ath)
        a(hull(bag.nm("Scallop"), [(x - aw / 2, ey - 0.01, ez), (x + aw / 2, ey - 0.01, ez), (x, ey - 0.01, ez - 0.22),
                                   (x - aw / 2, ey + 0.02, ez), (x + aw / 2, ey + 0.02, ez), (x, ey + 0.02, ez - 0.22)], m))
    a(beam("AwningBar", (-b.hw - 0.2, -b.hd + b.cy - L * math.cos(ath), ZT + 0.2 - L * math.sin(ath)),
           (b.hw + 0.2, -b.hd + b.cy - L * math.cos(ath), ZT + 0.2 - L * math.sin(ath)), 0.035, v_timber, seg=5))
    # porta
    door(bag, 1.65, -b.hd + b.cy - 0.08, Z0, 0.85, 1.85)
    b.at(bag, "-y", 1.65, 0.06, Z0 + 1.95, 1.15, 0.16, 0.2, v_timber, name="Lintel")
    for s in (-1, 1):
        b.at(bag, "-y", 1.65 + s * 0.52, 0.05, Z0 + 0.95, 0.14, 0.14, 1.9, v_timber, name="Jamb")
    a(bx("DoorWall", (1.65, -b.hd + b.cy, (Z0 + ZT) / 2), (1.6, 0.16, ZT - Z0), p_wood_dk, bev=0.0))
    a(bx("DoorWallTop", (1.65, -b.hd + b.cy - 0.05, Z0 + 2.4), (1.6, 0.08, 0.7), p_wood, bev=0.01))
    step_stones(bag, rnd, 1.65, -b.hd + b.cy - 0.02, n=1, w=1.0)
    # mercadorias no balcão: cesto de maçãs, balança, rolo de pano, moedas
    ty = -b.hd + b.cy - 0.12
    a(bx("Basket", (cx - 0.8, ty, 1.32), (0.5, 0.38, 0.16), p_wood_lt, bev=0.03, taper=(1.1, 1.1)))
    for j in range(6):
        a(part(bag.nm("Apple"), "ico", (cx - 0.95 + (j % 3) * 0.15, ty - 0.08 + (j // 3) * 0.15, 1.44), (0.14, 0.14, 0.14), b_apple, sub=1))
    a(beam("ScalePost", (cx + 0.1, ty, 1.24), (cx + 0.1, ty, 1.7), 0.02, p_gold, seg=5))
    a(bx("ScaleBeam", (cx + 0.1, ty, 1.7), (0.5, 0.025, 0.025), p_gold, bev=0.0))
    for s in (-1, 1):
        a(beam(bag.nm("ScaleCord"), (cx + 0.1 + s * 0.24, ty, 1.7), (cx + 0.1 + s * 0.24, ty, 1.45), 0.006, p_gold, seg=3))
        a(lathe(bag.nm("ScalePan"), [(0.0, 1.43), (0.1, 1.45), (0.11, 1.48)], p_gold, seg=8, loc=(cx + 0.1 + s * 0.24, ty, 0), cap_top=False))
    a(bx("ScaleFoot", (cx + 0.1, ty, 1.26), (0.18, 0.14, 0.04), v_timber, bev=0.01))
    a(part("ClothRoll", "cyl", (cx + 0.75, ty, 1.33), (0.18, 0.18, 0.6), b_blue, rot=(0, PI / 2, 0), seg=8))
    a(part("ClothRoll2", "cyl", (cx + 0.75, ty + 0.05, 1.5), (0.16, 0.16, 0.55), b_cloth_y, rot=(0, PI / 2, 0.1), seg=8))
    for k in range(4):
        a(part(bag.nm("Coin"), "cyl", (cx + 0.4 + k * 0.03, ty - 0.15, 1.25 + k * 0.02), (0.1, 0.1, 0.02), p_gold, seg=8))
    # placa com moeda pendurada na quina direita
    qx, qy = b.hw, -b.hd + b.cy
    a(bx("SignArm", (qx + 0.42, qy, 2.6), (0.84, 0.05, 0.05), p_iron, bev=0.01))
    a(beam("SignStay", (qx + 0.02, qy, 2.25), (qx + 0.6, qy, 2.58), 0.02, p_iron, seg=4))
    a(bx("SignBoard", (qx + 0.6, qy, 2.2), (0.55, 0.06, 0.5), p_wood, bev=0.02))
    for s in (-1, 1):
        a(beam(bag.nm("SignChain"), (qx + 0.6 + s * 0.17, qy, 2.6), (qx + 0.6 + s * 0.17, qy, 2.45), 0.01, p_iron, seg=4))
        a(part(bag.nm("SignCoin"), "cyl", (qx + 0.6, qy + s * 0.04, 2.2), (0.32, 0.32, 0.03), p_gold, rot=(PI / 2, 0, 0), seg=10))
    # telhado e janelas
    top = gable_roof(bag, 0, b.cy, b.hw, b.hd, ZT, th, p_roof, p_roof_dk, rows=5, over_x=0.35, over_y=0.45,
                     gable=p_wood, trim=v_timber)
    for face in ("-x", "+x"):
        window_on(bag, b, face, 0, 1.8, 0.6, 0.7, shutters=v_green)
        window_on(bag, b, face, 0, ZT + 0.45, 0.35, 0.35)
    for u in (-1.3, 1.3):
        window_on(bag, b, "+y", u, 1.8, 0.6, 0.6, bars=True)
    chimney(bag, rnd, -1.7, b.cy + 0.8, ZT - 0.3, top + 0.5, w=0.5)
    # mercadorias em volta: caixotes, sacos, barris, abóboras
    crate(bag, -b.hw - 0.4, -1.1, 0.0, 0.6, 0.2)
    crate(bag, -b.hw - 0.35, -1.05, 0.6, 0.45, -0.25, p_wood_lt)
    crate(bag, -b.hw - 0.45, -0.3, 0.0, 0.5, 0.5)
    sack(bag, -b.hw - 0.2, -1.9, 0.0, 1.0, 21)
    sack(bag, -b.hw + 0.25, -2.05, 0.0, 0.85, 22, p_canvas_dk)
    barrel(bag, b.hw + 0.4, 1.2, top=p_wood_lt)
    barrel(bag, b.hw + 0.45, 0.45)
    for k in range(3):
        a(part(bag.nm("Pumpkin"), "sphere", (b.hw + 0.4 + (k % 2) * 0.25, -0.35 - k * 0.25, 0.12), (0.3, 0.3, 0.24), b_orange, seg=8))
    _vexport(bag, "MerchantShop", "shop_merchant")


def _vexport(bag, name, fname):
    join(bag.items, name)
    export(fname)


VILLAGE_BUILDERS = {
    "house": build_house_a, "house_b": build_house_b, "house_c": build_house_c,
    "shop_smithy": build_shop_smithy, "shop_alchemist": build_shop_alchemist, "shop_merchant": build_shop_merchant,
}
