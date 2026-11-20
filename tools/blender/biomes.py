# Peças dos biomas dos mapas de viagem: Pântano Sussurrante (árvore do pântano, juncos, cogumelos), Geleira de
# Cristal (cristais de gelo) e Vulcão das Cinzas (árvore morta queimada). Executado por build_assets.py depois de
# trees.py (usa boulder/hull/join/_mesh_obj/_lin de props.py e tr_* de trees.py).
#
# Mesmo estilo das árvores: low-poly facetado, tons por direção da face, uma malha por modelo.
# Frente = -Y, chão em Z = 0, origem no pé.

b_swamp_bark = mat("b_swamp_bark", _lin(0.26, 0.22, 0.16), 0.95)
b_swamp_bark_dk = mat("b_swamp_bark_dark", _lin(0.15, 0.13, 0.10), 0.95)
b_swamp_leaf = [mat("b_swamp_leaf_dark", _lin(0.12, 0.20, 0.08), 0.9), mat("b_swamp_leaf", _lin(0.22, 0.32, 0.12), 0.9),
                mat("b_swamp_leaf_light", _lin(0.38, 0.46, 0.18), 0.9)]
b_moss_hang = mat("b_moss_hang", _lin(0.46, 0.52, 0.34), 0.95)
b_reed = [mat("b_reed_dark", _lin(0.20, 0.30, 0.10), 0.9), mat("b_reed", _lin(0.36, 0.46, 0.16), 0.9),
          mat("b_reed_light", _lin(0.56, 0.62, 0.26), 0.9)]
b_cattail = mat("b_cattail", _lin(0.30, 0.17, 0.08), 0.95)
b_cap = [mat("b_cap_dark", _lin(0.30, 0.12, 0.36), 0.8), mat("b_cap", _lin(0.50, 0.24, 0.62), 0.8),
         mat("b_cap_light", _lin(0.70, 0.44, 0.82), 0.8)]
b_stalk = mat("b_stalk", _lin(0.82, 0.78, 0.66), 0.9)
b_spot = mat("b_spot", (0.45, 1.0, 0.85), 0.5, 0.0, emit=(0.4, 1.0, 0.8), strength=2.5)
b_ice = [mat("b_ice_dark", _lin(0.30, 0.55, 0.78), 0.2), mat("b_ice", _lin(0.55, 0.80, 0.95), 0.2),
         mat("b_ice_light", _lin(0.85, 0.96, 1.00), 0.2)]
b_char = mat("b_char", _lin(0.10, 0.09, 0.09), 0.95)
b_char_lt = mat("b_char_light", _lin(0.26, 0.24, 0.23), 0.95)
b_ember = mat("b_ember", (1.0, 0.32, 0.04), 0.6, 0.0, emit=(1.0, 0.35, 0.05), strength=5.0)


def _moss_strand(name, top, length, width, seed):
    """Barba-de-velho pendurada: fita fina que afina e balança um pouco para o lado."""
    rnd = random.Random(seed)
    top = Vector(top)
    sway = Vector((rnd.uniform(-0.12, 0.12), rnd.uniform(-0.12, 0.12), 0))
    pts = [top + sway * (t * t) + Vector((0, 0, -length * t)) for t in (0.0, 0.35, 0.7, 1.0)]
    return tr_tube(name, pts, [width, width * 0.8, width * 0.5, width * 0.12], b_moss_hang, seg=4, seed=seed)


# ======================================================== ÁRVORE DO PÂNTANO
def build_tree_swamp():
    """Árvore torta do pântano: raízes em arco (palafitas), tronco inclinado, galhos tortos, copa rala e escura
    e barba-de-velho pendurada. ~6 m."""
    rnd = random.Random(301)
    objs = [tr_trunk("Trunk", 4.2, 0.36, 0.14, b_swamp_bark, lean=(0.35, -0.2), flare=2.1, seed=302, seg=8)]
    # raízes em arco: saem do tronco a 0,6–1,2 m e descem longe, entrando no chão
    for k in range(6):
        a = k / 6 * 2 * PI + rnd.uniform(-0.35, 0.35)
        d = Vector((math.cos(a), math.sin(a), 0))
        h0 = rnd.uniform(0.45, 1.0)
        L = rnd.uniform(0.85, 1.4)
        objs.append(tr_limb("Root%d" % k, d * 0.1 + Vector((0, 0, h0)), d * L + Vector((0, 0, -0.15)),
                            rnd.uniform(0.17, 0.22), 0.1, b_swamp_bark_dk,
                            bend=d * 0.25 + Vector((0, 0, rnd.uniform(0.15, 0.35))), n=5, seg=6, cap=False))
    top = Vector((0.35, -0.2, 4.2))
    crowns = []
    for k, (dx, dy, dz) in enumerate(((1.6, 0.3, 0.6), (-1.2, 0.9, 0.9), (0.2, -1.5, 0.7), (-0.6, -0.4, 1.4))):
        end = top + Vector((dx, dy, dz))
        objs.append(tr_limb("Branch%d" % k, top + Vector((0, 0, -0.7 + k * 0.15)), end, 0.12, 0.04, b_swamp_bark,
                            bend=(rnd.uniform(-0.3, 0.3), rnd.uniform(-0.3, 0.3), 0.45), n=4, seg=5))
        crowns.append(end)
    for k, c in enumerate(crowns):
        tr_crown(objs, "Crown%d" % k, c + Vector((0, 0, 0.15)), 0.75, 0.32, b_swamp_leaf, 4, 310 + k, s_min=0.6,
                 s_max=0.95, base=0.85, squash=0.55)
    # barba-de-velho: das pontas dos galhos e da borda das copas
    for k in range(14):
        c = crowns[k % len(crowns)]
        a = rnd.uniform(0, 2 * PI)
        p = c + Vector((math.cos(a) * rnd.uniform(0.3, 0.8), math.sin(a) * rnd.uniform(0.3, 0.8), -0.1))
        objs.append(_moss_strand("Moss%d" % k, p, rnd.uniform(0.7, 1.5), 0.05, 330 + k))
    tr_finish(objs, "TreeSwamp", "tree_swamp")


# ======================================================== ÁRVORE MORTA (queimada)
def build_tree_dead():
    """Tronco morto e queimado, topo quebrado, galhos secos em garra e brasas nas rachaduras. ~5 m."""
    rnd = random.Random(401)
    objs = [tr_trunk("Trunk", 3.6, 0.3, 0.12, b_char, lean=(-0.2, 0.25), flare=1.9, seed=402, seg=7)]
    tr_roots(objs, "Dead", 0.3, b_char, n=5, seed=403, length=0.55)
    # topo quebrado em lasca
    objs.append(hull("Snap", [(-0.32, 0.12, 3.5), (-0.05, 0.36, 3.5), (-0.1, 0.18, 4.25), (-0.28, 0.3, 3.85)], b_char_lt))
    for k, (z, a, L) in enumerate(((1.9, 0.4, 1.5), (2.4, 2.6, 1.3), (2.9, 4.4, 1.2), (3.3, 1.4, 1.0), (1.4, 5.4, 0.9))):
        base = Vector((-0.2 * (z / 3.6) ** 2, 0.25 * (z / 3.6) ** 2, z))
        d = Vector((math.cos(a), math.sin(a), 0))
        end = base + d * L + Vector((0, 0, L * 0.75))
        objs.append(tr_limb("Branch%d" % k, base, end, 0.1, 0.03, b_char, n=4, seg=5))
        for j in range(2):   # gravetos em garra
            b2 = base.lerp(end, 0.5 + j * 0.2)
            d2 = Vector((math.cos(a + (0.8 if j else -0.8)), math.sin(a + (0.8 if j else -0.8)), 0.9)).normalized()
            objs.append(tr_limb("Twig%d_%d" % (k, j), b2, b2 + d2 * L * 0.45, 0.04, 0.012, b_char, n=2, seg=4))
    # rachaduras com brasa no pé do tronco
    for k in range(4):
        a = k / 4 * 2 * PI + 0.4
        p = Vector((math.cos(a) * 0.29, math.sin(a) * 0.29, rnd.uniform(0.3, 0.8)))
        objs.append(bx("Ember%d" % k, p, (0.04, 0.03, rnd.uniform(0.2, 0.35)), b_ember, rot=(0.25, 0, a + PI / 2), bev=0.0))
    tr_finish(objs, "TreeDead", "tree_dead")


# ======================================================== JUNCOS
def build_reeds():
    """Touceira de juncos e taboas: lâminas finas em leque e 4 taboas com a espiga marrom. ~1,6 m."""
    rnd = random.Random(501)
    objs = []
    for k in range(16):
        a = rnd.uniform(0, 2 * PI)
        r0 = rnd.uniform(0.0, 0.25)
        base = Vector((math.cos(a) * r0, math.sin(a) * r0, -0.02))
        h = rnd.uniform(0.8, 1.5)
        lean = Vector((math.cos(a), math.sin(a), 0)) * rnd.uniform(0.15, 0.45)
        pts = [base, base + lean * 0.2 + Vector((0, 0, h * 0.45)), base + lean * 0.6 + Vector((0, 0, h * 0.8)),
               base + lean + Vector((0, 0, h))]
        ob = tr_tube("Blade%d" % k, pts, [0.035, 0.03, 0.02, 0.004], b_reed[1], seg=3, seed=510 + k)
        tr_tone(ob, b_reed, hi=0.3, lo=-0.3, rnd=random.Random(k), flip=0.2)
        _drop_first_slot(ob)
        objs.append(ob)
    for k in range(4):
        a = k / 4 * 2 * PI + rnd.uniform(-0.3, 0.3)
        base = Vector((math.cos(a) * 0.15, math.sin(a) * 0.15, -0.02))
        top = base + Vector((math.cos(a) * 0.12, math.sin(a) * 0.12, rnd.uniform(1.35, 1.7)))
        objs.append(tr_limb("Stalk%d" % k, base, top, 0.015, 0.01, b_reed[0], n=2, seg=4))
        head = top - Vector((0, 0, 0.12))
        objs.append(tr_tube("Head%d" % k, [head - Vector((0, 0, 0.12)), head, head + Vector((0, 0, 0.1))],
                            [0.03, 0.045, 0.03], b_cattail, seg=6, seed=530 + k))
    tr_finish(objs, "Reeds", "reeds")


# ======================================================== COGUMELOS (brilham à noite)
def build_mushrooms():
    """Tufo de cogumelos roxos com pintas que brilham (pântano). 3 grandes e 4 pequenos, ~0,7 m."""
    rnd = random.Random(601)
    objs = []
    spots = [(0.0, 0.0, 0.7, 0.32), (0.32, 0.18, 0.5, 0.24), (-0.28, 0.22, 0.42, 0.2), (0.2, -0.3, 0.28, 0.14),
             (-0.15, -0.28, 0.22, 0.12), (0.45, -0.1, 0.18, 0.1), (-0.42, -0.05, 0.16, 0.09)]
    for k, (x, y, h, r) in enumerate(spots):
        lean = Vector((x, y, 0)) * 0.25
        top = Vector((x, y, 0)) + lean + Vector((0, 0, h))
        objs.append(tr_limb("Stem%d" % k, (x, y, -0.02), top - Vector((0, 0, r * 0.15)), r * 0.28, r * 0.2, b_stalk,
                            bend=(0, 0, 0), n=2, seg=6))
        cap = boulder("Cap%d" % k, top - Vector((0, 0, r * 0.25)), (r * 2.2, r * 2.1, r * 1.1), b_cap[1], n=14,
                      seed=610 + k, flat_bottom=True)
        tr_tone(cap, b_cap, hi=0.55, lo=-0.2, rnd=random.Random(k), flip=0.08)
        _drop_first_slot(cap)
        objs.append(cap)
        for j in range(3 if r > 0.15 else 1):   # pintas que brilham
            a = rnd.uniform(0, 2 * PI)
            p = top + Vector((math.cos(a) * r * 0.55, math.sin(a) * r * 0.55, r * 0.12))
            objs.append(boulder("Spot%d_%d" % (k, j), p, (r * 0.32, r * 0.32, r * 0.14), b_spot, n=7, seed=620 + k * 5 + j,
                                flat_bottom=False))
    tr_finish(objs, "Mushrooms", "mushrooms")


# ======================================================== CRISTAIS DE GELO
def _prism(name, base, d, length, r, mats, seed, sides=6):
    """Cristal: prisma de 'sides' lados com ponta piramidal, apontando para d."""
    rnd = random.Random(seed)
    d = Vector(d).normalized()
    u = d.cross(Vector((0, 0, 1)) if abs(d.z) < 0.95 else Vector((1, 0, 0))).normalized()
    v = d.cross(u)
    base = Vector(base)
    pts = []
    for k in range(sides):
        a = 2 * PI * k / sides + rnd.uniform(-0.1, 0.1)
        o = (u * math.cos(a) + v * math.sin(a)) * r
        pts.append(base + o - d * 0.2)
        pts.append(base + o * 0.92 + d * length * 0.78)
    pts.append(base + d * length)
    ob = hull(name, pts, mats[1])
    tr_tone(ob, mats, hi=0.35, lo=-0.35, rnd=rnd, flip=0.1)
    _drop_first_slot(ob)
    return ob


def build_ice_crystal():
    """Aglomerado de cristais de gelo saindo do chão (Geleira de Cristal): um grande e 6 menores inclinados. ~2,6 m.
    Também serve de espinho de obsidiana no Vulcão (MapProp.tint escuro)."""
    rnd = random.Random(701)
    objs = [_prism("Main", (0, 0, 0), (0.08, -0.05, 1), 2.6, 0.34, b_ice, 702)]
    for k in range(6):
        a = k / 6 * 2 * PI + rnd.uniform(-0.3, 0.3)
        d = Vector((math.cos(a) * rnd.uniform(0.45, 0.8), math.sin(a) * rnd.uniform(0.45, 0.8), 1))
        base = Vector((math.cos(a) * 0.32, math.sin(a) * 0.32, 0))
        objs.append(_prism("Shard%d" % k, base, d, rnd.uniform(0.8, 1.7), rnd.uniform(0.13, 0.22), b_ice, 710 + k))
    # base de gelo/neve onde os cristais nascem
    ob = boulder("Base", (0, 0, 0), (1.5, 1.4, 0.35), b_ice[2], n=14, seed=720)
    objs.append(ob)
    tr_finish(objs, "IceCrystal", "ice_crystal")


BIOME_BUILDERS = {
    "tree_swamp": build_tree_swamp, "tree_dead": build_tree_dead, "reeds": build_reeds, "mushrooms": build_mushrooms,
    "ice_crystal": build_ice_crystal,
}
