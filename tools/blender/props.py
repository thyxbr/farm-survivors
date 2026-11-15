# Objetos de cenário (baú, cerca, caixote, barril, lampião, fogueira, tenda, poço, rocha) e as
# culturas da Horta. Executado por build_assets.py (usa mat/part/hull/export/clear/coll de lá).
#
# Estilo: low-poly facetado (sombreamento flat), tábuas e peças separadas com chanfro de
# 1 segmento, dois tons por material, ferragens escuras. Frente = -Y, chão em Z=0.

# ---------- materiais dos objetos ----------
p_wood = mat("p_wood", (0.36, 0.21, 0.10), 0.85)
p_wood_lt = mat("p_wood_light", (0.48, 0.30, 0.15), 0.85)
p_wood_dk = mat("p_wood_dark", (0.20, 0.11, 0.05), 0.9)
p_wood_end = mat("p_wood_end", (0.66, 0.48, 0.28), 0.9)     # topo de tora cortada
p_iron = mat("p_iron", (0.13, 0.13, 0.15), 0.55, 0.7)
p_iron_lt = mat("p_iron_light", (0.32, 0.33, 0.36), 0.45, 0.8)
p_gold = mat("p_gold", (0.95, 0.66, 0.18), 0.3, 1.0)
p_stone = mat("p_stone", (0.22, 0.21, 0.20), 0.95)          # linear: ~0,5 sRGB, não estoura no sol
p_stone_lt = mat("p_stone_light", (0.32, 0.31, 0.29), 0.95)
p_stone_dk = mat("p_stone_dark", (0.12, 0.115, 0.11), 0.95)
p_moss = mat("p_moss", (0.20, 0.34, 0.10), 0.95)
p_moss_lt = mat("p_moss_light", (0.32, 0.46, 0.14), 0.95)
p_canvas = mat("p_canvas", (0.62, 0.52, 0.36), 0.95)
p_canvas_dk = mat("p_canvas_dark", (0.42, 0.33, 0.21), 0.95)
p_patch = mat("p_patch", (0.45, 0.18, 0.12), 0.95)
p_rope = mat("p_rope", (0.62, 0.50, 0.30), 0.95)
p_roof = mat("p_roof", (0.45, 0.15, 0.08), 0.85)
p_roof_dk = mat("p_roof_dark", (0.28, 0.09, 0.05), 0.85)
p_water = mat("p_water", (0.06, 0.20, 0.30), 0.08)
p_ash = mat("p_ash", (0.10, 0.09, 0.08), 1.0)
p_ember = mat("p_ember", (1.0, 0.25, 0.02), 0.6, 0.0, emit=(1.0, 0.3, 0.03), strength=6.0)
p_fire = mat("p_fire", (1.0, 0.42, 0.05), 0.5, 0.0, emit=(1.0, 0.42, 0.05), strength=8.0)
p_fire_core = mat("p_fire_core", (1.0, 0.85, 0.3), 0.5, 0.0, emit=(1.0, 0.85, 0.35), strength=10.0)
p_lantern = mat("p_lantern", (1.0, 0.8, 0.4), 0.4, 0.0, emit=(1.0, 0.75, 0.35), strength=6.0)


# ---------- helpers ----------
def _mesh_obj(name, bm, material):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.validate()
    for p in me.polygons:
        p.use_smooth = False
    if isinstance(material, (list, tuple)):
        for m in material:
            me.materials.append(m)
    else:
        me.materials.append(material)
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    return ob


def bx(name, loc, size, material, rot=(0, 0, 0), bev=0.015, taper=None):
    """Caixa com chanfro de 1 segmento. taper=(sx, sy) afina o topo (estacas, pés)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    if taper:
        for v in bm.verts:
            if v.co.z > 0:
                v.co.x *= taper[0]
                v.co.y *= taper[1]
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    if bev > 0:
        b = min(bev, min(size) * 0.45)
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=b, segments=1, affect='EDGES', profile=0.5)
    M = Matrix.Translation(Vector(loc)) @ Euler(rot).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    return _mesh_obj(name, bm, material)


def lathe(name, prof, material, seg=10, loc=(0, 0, 0), rot=(0, 0, 0), cap_top=True, cap_bot=True, mats=None,
          wobble=0.0, seed=1):
    """Sólido de revolução. prof = [(raio, z), ...] de baixo para cima.
    mats = função(i_segmento) -> índice de material (listas de materiais em 'material')."""
    rnd = random.Random(seed)
    bm = bmesh.new()
    rings = []
    for r, z in prof:
        ring = []
        for i in range(seg):
            a = 2 * PI * i / seg
            rr = r * (1 + rnd.uniform(-wobble, wobble))
            ring.append(bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, z)))
        rings.append(ring)
    for k in range(len(rings) - 1):
        for i in range(seg):
            j = (i + 1) % seg
            f = bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
            if mats:
                f.material_index = mats(i)
    if cap_bot and prof[0][0] > 0.0001:
        bm.faces.new(list(reversed(rings[0])))
    if cap_top and prof[-1][0] > 0.0001:
        bm.faces.new(rings[-1])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0001)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    M = Matrix.Translation(Vector(loc)) @ Euler(rot).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    return _mesh_obj(name, bm, material)


def boulder(name, loc, size, material, n=14, seed=1, flat_bottom=True, rot=(0, 0, 0)):
    """Pedra facetada: casco convexo de pontos sorteados num elipsoide."""
    rnd = random.Random(seed)
    pts = []
    for i in range(n):
        u = rnd.uniform(-1, 1)
        a = rnd.uniform(0, 2 * PI)
        s = math.sqrt(1 - u * u)
        k = rnd.uniform(0.82, 1.0)
        z = u * k
        if flat_bottom:
            z = max(z, -0.55)
        pts.append((math.cos(a) * s * k, math.sin(a) * s * k, z))
    for a in range(5):   # anel da base garante apoio largo
        t = a / 5 * 2 * PI + rnd.uniform(0, 0.6)
        pts.append((math.cos(t) * 0.9, math.sin(t) * 0.9, -0.55 if flat_bottom else -0.4))
    bm = bmesh.new()
    vs = [bm.verts.new(p) for p in pts]
    bmesh.ops.convex_hull(bm, input=vs)
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context='VERTS')
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    sz = Vector(size) / 2
    zoff = 0.55 * sz.z if flat_bottom else 0
    M = (Matrix.Translation(Vector(loc) + Vector((0, 0, zoff))) @ Euler(rot).to_matrix().to_4x4()
         @ Matrix.Diagonal((*sz, 1)))
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    return _mesh_obj(name, bm, material)


def beam(name, a, b, r, material, seg=6, r2=None, end_mat=None):
    """Tora/haste de a até b (cilindro facetado). end_mat pinta as pontas (madeira cortada)."""
    a, b = Vector(a), Vector(b)
    d = b - a
    L = d.length
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r,
                          radius2=r if r2 is None else r2, depth=L)
    if end_mat is not None:
        for f in bm.faces:
            if abs(f.normal.z) > 0.9:
                f.material_index = 1
    q = Vector((0, 0, 1)).rotation_difference(d.normalized())
    M = Matrix.Translation((a + b) / 2) @ q.to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    return _mesh_obj(name, bm, [material, end_mat] if end_mat is not None else material)


def leaf(name, base, yaw, pitch, length, width, material, droop=0.25, fold=0.18, roll=0.0):
    """Folha dobrada na nervura (4 triângulos). Nasce em 'base', aponta para yaw/pitch."""
    bm = bmesh.new()
    L, W = length, width
    v0 = bm.verts.new((0, 0, 0))
    vl = bm.verts.new((-W / 2, L * 0.42, W * fold))
    vm = bm.verts.new((0, L * 0.45, 0))
    vr = bm.verts.new((W / 2, L * 0.42, W * fold))
    vt = bm.verts.new((0, L, -L * droop))
    for f in ((v0, vm, vl), (v0, vr, vm), (vl, vm, vt), (vm, vr, vt)):
        bm.faces.new(f)
    M = (Matrix.Translation(Vector(base)) @ Euler((0, 0, yaw)).to_matrix().to_4x4()
         @ Euler((pitch, 0, 0)).to_matrix().to_4x4() @ Euler((0, roll, 0)).to_matrix().to_4x4())
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    return _mesh_obj(name, bm, material)


def join(objs, name):
    objs = [o for o in objs if o is not None]
    with bpy.context.temp_override(active_object=objs[0], object=objs[0], selected_objects=objs,
                                   selected_editable_objects=objs):
        bpy.ops.object.join()
    o = objs[0]
    o.name = name
    o.data.name = name
    return o


def set_origin(ob, p):
    """Leva a origem do objeto para p (mundo) sem mexer na geometria — para escalar no lugar."""
    p = Vector(p)
    ob.data.transform(Matrix.Translation(-p))
    ob.location = p


class Bag:
    """Coleta peças para juntar num objeto só no fim."""
    def __init__(self):
        self.items = []
        self.n = 0

    def add(self, ob):
        self.items.append(ob)
        return ob

    def nm(self, p):
        self.n += 1
        return "%s_%d" % (p, self.n)


# ======================================================== BAÚ
def build_chest():
    # Corpo 0,9 x 0,6, topo em Z=0,5. A tampa (objeto "ChestLid") é um meio-cilindro de aduelas
    # com dobradiça na aresta de trás (0, +0,3, 0,5) — loot_chest.gd gira a tampa por ali.
    W, D, H = 0.9, 0.6, 0.5
    base, lid = Bag(), Bag()
    b = base.add
    b(bx("Core", (0, 0, 0.3), (W - 0.06, D - 0.06, 0.4), p_wood_dk, bev=0))
    # tábuas horizontais (frente/trás e laterais), 3 fiadas com fresta
    for row in range(3):
        z = 0.12 + row * 0.13
        tone = p_wood if row % 2 == 0 else p_wood_lt
        for sy in (-1, 1):
            b(bx(base.nm("PlankFB"), (0, sy * (D / 2 - 0.02), z), (W - 0.1, 0.04, 0.12), tone, bev=0.012))
        for sx in (-1, 1):
            b(bx(base.nm("PlankS"), (sx * (W / 2 - 0.02), 0, z), (0.04, D - 0.1, 0.12), p_wood_lt if row % 2 == 0 else p_wood, bev=0.012))
    b(bx("Bottom", (0, 0, 0.06), (W - 0.02, D - 0.02, 0.05), p_wood_dk, bev=0.01))
    # quinas de ferro (cantoneiras) e pés
    for sx in (-1, 1):
        for sy in (-1, 1):
            cx, cy = sx * (W / 2 - 0.005), sy * (D / 2 - 0.005)
            b(bx(base.nm("CornerA"), (cx - sx * 0.035, cy, 0.29), (0.08, 0.02, 0.44), p_iron, bev=0.006))
            b(bx(base.nm("CornerB"), (cx, cy - sy * 0.035, 0.29), (0.02, 0.08, 0.44), p_iron, bev=0.006))
            b(bx(base.nm("Foot"), (sx * (W / 2 - 0.06), sy * (D / 2 - 0.06), 0.025), (0.12, 0.12, 0.05), p_iron, bev=0.01))
            for z in (0.12, 0.45):
                b(bx(base.nm("Rivet"), (cx - sx * 0.045, cy - sy * 0.012, z), (0.022, 0.022, 0.022), p_iron_lt, bev=0.005))
    # cinta de ferro na borda de cima e duas cintas verticais
    for sy in (-1, 1):
        b(bx(base.nm("RimFB"), (0, sy * (D / 2 + 0.002), H - 0.025), (W + 0.01, 0.025, 0.05), p_iron, bev=0.006))
    for sx in (-1, 1):
        b(bx(base.nm("RimS"), (sx * (W / 2 + 0.002), 0, H - 0.025), (0.025, D + 0.01, 0.05), p_iron, bev=0.006))
        x = sx * 0.27
        for sy in (-1, 1):
            b(bx(base.nm("Band"), (x, sy * (D / 2 + 0.006), 0.27), (0.07, 0.022, 0.46), p_iron, bev=0.006))
            for z in (0.12, 0.3):
                b(bx(base.nm("Rivet"), (x, sy * (D / 2 + 0.02), z), (0.024, 0.02, 0.024), p_iron_lt, bev=0.005))
        b(bx(base.nm("Handle"), (sx * (W / 2 + 0.03), 0, 0.33), (0.03, 0.2, 0.03), p_iron, bev=0.008))
        for sy in (-1, 1):
            b(bx(base.nm("HandleEar"), (sx * (W / 2 + 0.018), sy * 0.09, 0.35), (0.03, 0.03, 0.06), p_iron, bev=0.006))
    # fechadura (espelho dourado com buraco)
    b(bx("LockPlate", (0, -D / 2 - 0.012, 0.4), (0.15, 0.025, 0.17), p_gold, bev=0.01))
    b(bx("Keyhole", (0, -D / 2 - 0.026, 0.39), (0.025, 0.01, 0.055), p_wood_dk, bev=0.004))
    for sx in (-1, 1):   # cantoneiras douradas no alto das quinas
        for sy in (-1, 1):
            cx, cy = sx * (W / 2 + 0.012), sy * (D / 2 + 0.012)
            b(hull(base.nm("GoldCorner"), [(cx, cy, H - 0.005), (cx - sx * 0.13, cy, H - 0.005), (cx, cy - sy * 0.11, H - 0.005),
                                            (cx, cy, H - 0.14), (cx - sx * 0.03, cy - sy * 0.03, H - 0.005)], p_gold))
    b(lathe("LockRing", [(0.045, -0.008), (0.045, 0.008), (0.03, 0.008), (0.03, -0.008)], p_gold, seg=8,
            loc=(0, -D / 2 - 0.035, 0.31), rot=(PI / 2, 0, 0)))
    join(base.items, "ChestBase")

    # tampa: 5 aduelas num meio-cilindro de raio R em torno do eixo (Y=0, Z=H)
    R, n = D / 2, 5
    l = lid.add
    w = 2 * R * math.sin(PI / (2 * n)) + 0.01
    for i in range(n):
        th = (i + 0.5) * PI / n
        y, z = -math.cos(th) * (R - 0.02), H + math.sin(th) * (R - 0.02)
        tone = p_wood_lt if i % 2 == 0 else p_wood
        l(bx(lid.nm("Stave"), (0, y, z), (W - 0.06, w - 0.012, 0.045), tone, rot=(PI / 2 - th, 0, 0), bev=0.012))
    pts = [(0, -math.cos(a) * (R - 0.01), H + math.sin(a) * (R - 0.01)) for a in [k * PI / 8 for k in range(9)]]
    for sx in (-1, 1):   # tampas laterais em meia-lua
        x0, x1 = sx * (W / 2 - 0.035), sx * (W / 2)
        l(hull(lid.nm("LidEnd"), [(x0, p[1], p[2]) for p in pts] + [(x1, p[1], p[2]) for p in pts], p_wood_dk))
    # cintas de ferro sobre o arco (segmentos) + aro da borda da tampa
    for x in (-0.27, 0.27, -W / 2 + 0.015, W / 2 - 0.015):
        wide = 0.07 if abs(x) < 0.3 else 0.035
        for i in range(n):
            th = (i + 0.5) * PI / n
            rr = R + 0.006
            l(bx(lid.nm("LidBand"), (x, -math.cos(th) * rr, H + math.sin(th) * rr), (wide, w + 0.012, 0.018), p_iron,
                 rot=(PI / 2 - th, 0, 0), bev=0.005))
    for sy in (-1, 1):
        l(bx(lid.nm("LidRim"), (0, sy * (R + 0.004), H + 0.025), (W + 0.01, 0.024, 0.05), p_iron, bev=0.006))
    th = PI / 2
    for x in (-0.27, 0.27):   # rebites no topo
        for th in (0.6, PI / 2, PI - 0.6):
            rr = R + 0.016
            l(bx(lid.nm("LidRivet"), (x, -math.cos(th) * rr, H + math.sin(th) * rr), (0.024, 0.024, 0.024), p_iron_lt, bev=0.005))
    # lingueta dourada que desce da tampa sobre a fechadura, e dobradiças atrás
    l(bx("Hasp", (0, -R - 0.024, H + 0.02), (0.07, 0.02, 0.12), p_gold, bev=0.008))
    for x in (-0.27, 0.27):
        l(bx(lid.nm("Hinge"), (x, R + 0.02, H + 0.01), (0.09, 0.03, 0.07), p_iron, bev=0.008))
    l(part("LidGem", "ico", (0, 0, H + R + 0.03), (0.1, 0.1, 0.07), p_gold, sub=1))
    for sx in (-1, 1):   # pontas douradas nos cantos do arco
        for sy in (-1, 1):
            l(bx(lid.nm("LidCap"), (sx * (W / 2 - 0.005), sy * (R - 0.03), H + 0.09), (0.05, 0.1, 0.15), p_gold, bev=0.01))
    join(lid.items, "ChestLid")
    export("chest")


# ======================================================== CERCA
def build_fence():
    # Vão de 2 m: mourões em x = ±1 (iguais, para coincidir com o vizinho), duas travessas de
    # tora rachada presas na frente e uma escora diagonal. Altura ~1 m.
    # Mourão: tora sextavada um pouco torta, topo cortado em bisel; travessas em 3 trechos com
    # barriga e torção leve, dois tons, nós escuros; amarração de corda em X; pedrinhas no pé.
    bag = Bag()
    a = bag.add
    rnd = random.Random(4)
    for x in (-1.0, 1.0):
        lean = (rnd.uniform(-0.02, 0.02), rnd.uniform(-0.015, 0.015))
        top = (x + lean[0], lean[1], 0.97)
        a(beam(bag.nm("Post"), (x, 0, -0.02), top, 0.085, p_wood_dk, seg=6, r2=0.074))
        # topo em bisel (corte inclinado) com o miolo claro à mostra
        a(hull(bag.nm("PostTip"), [(top[0] + math.cos(k * PI / 3) * 0.074, top[1] + math.sin(k * PI / 3) * 0.074,
                                    top[2] - 0.01 + 0.06 * math.cos(k * PI / 3)) for k in range(6)]
               + [(top[0], top[1], top[2] - 0.02)], p_wood_end))
        a(lathe(bag.nm("PostRing"), [(0.088, 0.62), (0.09, 0.66)], p_wood, seg=6, loc=(x, 0, 0)))   # marca de casca
        for k in range(3):   # pedrinhas no pé do mourão
            ang = k * 2.1 + rnd.uniform(0, 0.6)
            a(boulder(bag.nm("FootStone"), (x + math.cos(ang) * 0.13, math.sin(ang) * 0.13, 0),
                      (0.12, 0.1, 0.07), (p_stone, p_stone_dk, p_stone_lt)[k], n=8, seed=40 + k + int(x * 5)))
    for z, sag, tone in ((0.8, 0.03, p_wood), (0.42, 0.02, p_wood_lt)):
        y = -0.12
        z0, z1 = z + rnd.uniform(-0.02, 0.02), z + rnd.uniform(-0.02, 0.02)
        pts = []
        for k in range(4):   # 3 trechos: barriga no meio e um leve zigue-zague em Y
            t = k / 3
            pts.append(Vector((-1.1 + 2.2 * t, y + (rnd.uniform(-0.012, 0.012) if 0 < k < 3 else 0.0),
                               z0 + (z1 - z0) * t - sag * math.sin(PI * t))))
        for k in range(3):
            r0 = 0.055 if k != 1 else 0.05
            a(beam(bag.nm("Rail"), pts[k], pts[k + 1], r0, tone, seg=5, r2=0.05 if k != 1 else 0.055,
                   end_mat=p_wood_end if k in (0, 2) else None))
        for k in range(2):   # nós da madeira
            t = rnd.uniform(0.2, 0.8)
            c = pts[0].lerp(pts[3], t)
            a(boulder(bag.nm("Knot"), (c.x, c.y - 0.045, c.z - 0.015), (0.045, 0.03, 0.035), p_wood_dk, n=7, seed=50 + k))
        for x in (-1.0, 1.0):   # amarração de corda em X no mourão
            zz = z0 if x < 0 else z1
            for s in (-1, 1):
                a(bx(bag.nm("Lash"), (x, -0.095, zz), (0.2, 0.03, 0.03), p_rope, rot=(0, s * 0.6, 0), bev=0.008))
    a(beam(bag.nm("Brace"), (-0.9, -0.06, 0.45), (0.9, -0.06, 0.78), 0.035, p_wood_lt, seg=5, end_mat=p_wood_end))
    # tufos de capim na base dos mourões
    for x in (-1.0, 1.0):
        for k in range(5):
            yaw = k * 2 * PI / 5 + 0.4
            a(leaf(bag.nm("Grass"), (x + math.cos(yaw) * 0.09, math.sin(yaw) * 0.09, 0.0), yaw - PI / 2, 1.05,
                   rnd.uniform(0.18, 0.3), 0.05, (p_moss_lt, p_moss)[k % 2], droop=0.25))
    join(bag.items, "Fence")
    export("fence")


# ======================================================== CAIXOTE
def build_crate():
    S = 0.8
    h = S / 2
    bag = Bag()
    a = bag.add
    a(bx("Core", (0, 0, h), (S - 0.08, S - 0.08, S - 0.08), p_wood_dk, bev=0))
    f = 0.08   # moldura: 12 arestas
    for sx in (-1, 1):
        for sy in (-1, 1):
            a(bx(bag.nm("FrameZ"), (sx * (h - f / 2), sy * (h - f / 2), h), (f, f, S), p_wood_dk, bev=0.012))
    for sz in (-1, 1):
        z = h + sz * (h - f / 2)
        for s in (-1, 1):
            a(bx(bag.nm("FrameX"), (0, s * (h - f / 2), z), (S - 2 * f + 0.002, f, f), p_wood_dk, bev=0.012))
            a(bx(bag.nm("FrameY"), (s * (h - f / 2), 0, z), (f, S - 2 * f + 0.002, f), p_wood_dk, bev=0.012))
    inner = S - 2 * f
    pw = inner / 3
    # tábuas dos lados (verticais) e do topo, com fresta
    for k in range(3):
        u = -inner / 2 + pw * (k + 0.5)
        tone = (p_wood, p_wood_lt, p_wood)[k]
        for s in (-1, 1):
            a(bx(bag.nm("PlankY"), (u, s * (h - 0.03), h), (pw - 0.012, 0.03, inner), tone, bev=0.008))
            a(bx(bag.nm("PlankX"), (s * (h - 0.03), u, h), (0.03, pw - 0.012, inner), tone, bev=0.008))
            a(bx(bag.nm("PlankT"), (u, 0, S - 0.03), (pw - 0.012, inner, 0.03), (p_wood_lt, p_wood, p_wood_lt)[k], bev=0.008))
    # escora diagonal em cada lado
    L = math.hypot(inner, inner)
    ang = math.atan2(inner, inner)
    for s in (-1, 1):
        a(bx(bag.nm("BraceY"), (0, s * (h - 0.005), h), (L, 0.025, 0.07), p_wood_dk, rot=(0, s * ang, 0), bev=0.008))
        a(bx(bag.nm("BraceX"), (s * (h - 0.005), 0, h), (0.025, L, 0.07), p_wood_dk, rot=(-s * ang, 0, 0), bev=0.008))
    # pregos nos cantos da moldura
    for sx in (-1, 1):
        for sz in (-1, 1):
            for s in (-1, 1):
                a(bx(bag.nm("Nail"), (sx * (h - f / 2), s * (h + 0.002), h + sz * (h - f / 2)), (0.02, 0.01, 0.02), p_iron_lt, bev=0))
                a(bx(bag.nm("Nail"), (s * (h + 0.002), sx * (h - f / 2), h + sz * (h - f / 2)), (0.01, 0.02, 0.02), p_iron_lt, bev=0))
    join(bag.items, "Crate")
    export("crate")


# ======================================================== BARRIL
def build_barrel():
    R, H, seg = 0.36, 1.0, 14

    def rad(z):   # barriga das aduelas
        return R * (0.86 + 0.14 * math.sin(PI * z / H))

    prof = [(rad(z), z) for z in (0.0, 0.12, 0.3, 0.5, 0.7, 0.88, 1.0)]
    bag = Bag()
    a = bag.add
    # aduelas em dois tons alternados; topo aberto (tampa embutida abaixo da borda)
    a(lathe("Staves", prof, [p_wood, p_wood_lt], seg=seg, cap_top=False, mats=lambda i: i % 2))
    a(lathe("Inner", [(rad(1.0) - 0.035, 0.94), (rad(1.0) - 0.035, 1.0)], p_wood_dk, seg=seg, cap_bot=False, cap_top=False))
    a(lathe("Lid", [(rad(1.0) - 0.03, 0.935), (rad(1.0) - 0.03, 0.95)], p_wood_dk, seg=seg))
    for k in (-1, 0, 1):   # tábuas da tampa
        a(bx(bag.nm("LidPlank"), (k * 0.17, 0, 0.955), (0.155, 2 * (rad(1.0) - 0.05) * math.cos(math.asin(min(0.95, abs(k) * 0.17 / R))), 0.015),
             p_wood if k else p_wood_lt, bev=0.004))
    a(lathe("Rim", [(rad(1.0) - 0.035, 1.0), (rad(1.0) + 0.002, 1.0)], p_wood_end, seg=seg, cap_bot=False, cap_top=False))
    for zc in (0.1, 0.27, 0.73, 0.9):   # aros de ferro seguindo a barriga
        r0, r1 = rad(zc - 0.03) + 0.012, rad(zc + 0.03) + 0.012
        a(lathe(bag.nm("Hoop"), [(r0, zc - 0.03), (r1, zc + 0.03)], p_iron, seg=seg))
    # torneira de madeira na frente
    a(beam("Tap", (0, -rad(0.25) + 0.02, 0.25), (0, -rad(0.25) - 0.09, 0.25), 0.035, p_wood_dk, seg=6))
    a(bx("TapKey", (0, -rad(0.25) - 0.06, 0.29), (0.025, 0.025, 0.06), p_wood_dk, bev=0.005))
    join(bag.items, "Barrel")
    export("barrel")


# ======================================================== LAMPIÃO
def build_lamp():
    # Lanterna em (0, -0,5, ~3,3) — world.gd e hub_world.gd põem a OmniLight ali. O poste é alto (topo a
    # ~3,5 m) para o varal de luzes de Natal pendurado entre os postes passar acima da cabeça do jogador.
    up = 0.9   # quanto o poste cresceu (antes o topo ficava a ~2,6 m)
    bag = Bag()
    a = bag.add
    a(boulder("Base", (0, 0, 0), (0.55, 0.5, 0.3), p_stone, n=12, seed=31))
    a(bx("Plinth", (0, 0, 0.3), (0.26, 0.26, 0.2), p_stone_dk, bev=0.03))
    a(bx("Post", (0, 0, 1.45 + up / 2), (0.15, 0.15, 2.3 + up), p_wood_dk, bev=0.03, taper=(0.8, 0.8)))
    a(bx("PostCap", (0, 0, 2.63 + up), (0.2, 0.2, 0.08), p_wood_dk, bev=0.02))
    a(bx("Arm", (0, -0.28, 2.6 + up), (0.08, 0.6, 0.08), p_wood_dk, bev=0.015))
    a(beam("Strut", (0, -0.06, 2.25 + up), (0, -0.4, 2.57 + up), 0.03, p_wood_dk, seg=5))
    a(bx("ArmRing", (0, -0.08, 2.6 + up), (0.18, 0.04, 0.12), p_iron, bev=0.008))
    a(bx("Hook", (0, -0.5, 2.6 + up), (0.03, 0.03, 0.1), p_iron, bev=0.005))
    # lanterna: base, 4 colunas, vidro, telhado de 4 águas com argola
    zc = 2.36 + up
    a(bx("LBase", (0, -0.5, zc - 0.16), (0.24, 0.24, 0.04), p_iron, bev=0.01))
    a(bx("LTop", (0, -0.5, zc + 0.15), (0.26, 0.26, 0.035), p_iron, bev=0.01))
    for sx in (-1, 1):
        for sy in (-1, 1):
            a(bx(bag.nm("LBar"), (sx * 0.1, -0.5 + sy * 0.1, zc), (0.025, 0.025, 0.3), p_iron, bev=0.004))
    a(bx("LGlass", (0, -0.5, zc), (0.17, 0.17, 0.27), p_lantern, bev=0.01))
    a(hull("LRoof", [(sx * 0.15, -0.5 + sy * 0.15, zc + 0.165) for sx in (-1, 1) for sy in (-1, 1)]
           + [(0, -0.5, zc + 0.3)], p_iron))
    a(lathe("LRing", [(0.035, zc + 0.3), (0.035, zc + 0.34)], p_iron_lt, seg=6))
    join(bag.items, "Lamp")
    export("lamp")


# ======================================================== FOGUEIRA
def build_campfire():
    bag = Bag()
    a = bag.add
    rnd = random.Random(8)
    a(lathe("Ash", [(0.5, 0.0), (0.46, 0.03), (0.3, 0.045), (0.0, 0.05)], p_ash, seg=10))
    n = 9
    for i in range(n):
        ang = i / n * 2 * PI + rnd.uniform(-0.1, 0.1)
        r = 0.6 + rnd.uniform(-0.03, 0.03)
        s = rnd.uniform(0.85, 1.15)
        a(boulder(bag.nm("Stone"), (math.cos(ang) * r, math.sin(ang) * r, 0), (0.3 * s, 0.24 * s, 0.2 * s),
                  (p_stone, p_stone_lt, p_stone_dk)[i % 3], n=10, seed=40 + i, rot=(0, 0, ang)))
    # lenha em tenda (5 toras inclinadas) + 2 deitadas
    for i in range(5):
        ang = i / 5 * 2 * PI + 0.3
        foot = Vector((math.cos(ang) * 0.36, math.sin(ang) * 0.36, 0.05))
        top = Vector((math.cos(ang) * 0.05, math.sin(ang) * 0.05, 0.55))
        a(beam(bag.nm("Log"), foot, top, 0.055, p_wood_dk, seg=6, end_mat=p_wood_end))
    a(beam("LogA", (-0.45, -0.1, 0.07), (0.4, 0.2, 0.08), 0.07, p_wood_dk, seg=6, end_mat=p_wood_end))
    a(beam("LogB", (-0.25, 0.35, 0.07), (0.3, -0.35, 0.1), 0.065, p_wood_dk, seg=6, end_mat=p_wood_end))
    for i in range(7):   # brasas
        ang = rnd.uniform(0, 2 * PI)
        r = rnd.uniform(0.05, 0.3)
        a(boulder(bag.nm("Ember"), (math.cos(ang) * r, math.sin(ang) * r, 0.03), (0.07, 0.06, 0.05), p_ember, n=8, seed=60 + i))
    # chamas: cones facetados retorcidos, núcleo claro por dentro
    for i, (dx, dy, h, r) in enumerate(((0, 0, 0.85, 0.24), (0.1, 0.06, 0.6, 0.16), (-0.1, 0.05, 0.55, 0.15),
                                       (0.02, -0.1, 0.65, 0.15))):
        a(lathe(bag.nm("Flame"), [(r, 0.1), (r * 0.8, 0.1 + h * 0.35), (r * 0.35, 0.1 + h * 0.75), (0.0, 0.1 + h)],
                p_fire, seg=5, loc=(dx, dy, 0), rot=(rnd.uniform(-0.12, 0.12), rnd.uniform(-0.12, 0.12), i * 0.7), wobble=0.12, seed=70 + i))
    a(lathe("FlameCore", [(0.13, 0.1), (0.1, 0.3), (0.0, 0.62)], p_fire_core, seg=5, rot=(0, 0, 0.3)))
    join(bag.items, "Campfire")
    export("campfire")


# ======================================================== TENDA
def sheet(name, grid, thick, materials, mat_fn=None):
    """Lona/pano com espessura a partir de uma grade de pontos grid[i][j]. A face de trás sai
    deslocada 'thick' pela normal local e as bordas fecham. mat_fn(i, j) -> índice em 'materials'
    para o quadrado (i, j) (frente, verso e borda)."""
    ni, nj = len(grid), len(grid[0])
    G = [[Vector(p) for p in row] for row in grid]

    def nrm(i, j):
        a = G[min(i + 1, ni - 1)][j] - G[max(i - 1, 0)][j]
        b = G[i][min(j + 1, nj - 1)] - G[i][max(j - 1, 0)]
        n = a.cross(b)
        return n.normalized() if n.length > 1e-6 else Vector((0, 0, 1))

    bm = bmesh.new()
    top = [[bm.verts.new(G[i][j]) for j in range(nj)] for i in range(ni)]
    bot = [[bm.verts.new(G[i][j] - nrm(i, j) * thick) for j in range(nj)] for i in range(ni)]
    for i in range(ni - 1):
        for j in range(nj - 1):
            m = mat_fn(i, j) if mat_fn else 0
            bm.faces.new((top[i][j], top[i + 1][j], top[i + 1][j + 1], top[i][j + 1])).material_index = m
            bm.faces.new((bot[i][j + 1], bot[i + 1][j + 1], bot[i + 1][j], bot[i][j])).material_index = m
    rim = ([(i, 0) for i in range(ni)] + [(ni - 1, j) for j in range(1, nj)]
           + [(i, nj - 1) for i in range(ni - 2, -1, -1)] + [(0, j) for j in range(nj - 2, 0, -1)])
    for k in range(len(rim)):
        (i0, j0), (i1, j1) = rim[k], rim[(k + 1) % len(rim)]
        f = bm.faces.new((top[i0][j0], bot[i0][j0], bot[i1][j1], top[i1][j1]))
        f.material_index = mat_fn(min(i0, i1, ni - 2), min(j0, j1, nj - 2)) if mat_fn else 0
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _mesh_obj(name, bm, list(materials))


# lona da tenda: o toon acende a face inteira, então os tons ficam abaixo do p_canvas comum
p_tent_a = mat("p_tent_a", (0.44, 0.34, 0.20), 0.95)
p_tent_b = mat("p_tent_b", (0.55, 0.45, 0.28), 0.95)
p_tent_hem = mat("p_tent_hem", (0.24, 0.16, 0.08), 0.95)
p_cloth_red = mat("p_cloth_red", (0.42, 0.08, 0.05), 0.95)
p_cloth_blue = mat("p_cloth_blue", (0.10, 0.16, 0.30), 0.95)
p_tent_dark = mat("p_tent_dark", (0.05, 0.04, 0.035), 1.0)   # sombra dentro da tenda


def build_tent():
    # Tenda em A: cumeeira ao longo de Y (porta em -Y), ~2,4 m de largura, 2 m de altura.
    # Lona em gomos de dois tons com barra escura, barriga entre os mastros e entre a cumeeira e a
    # barra; uma aba da porta enrolada e amarrada, a outra puxada de lado; saco de dormir lá dentro.
    bag = Bag()
    a = bag.add
    hw, hd, Ht = 1.15, 1.1, 1.95
    y0, y1 = -hd - 0.1, hd + 0.04          # a lona passa um pouco da porta (beiral)
    NV, NU = 8, 4                          # gomos ao longo de Y, faixas da cumeeira à barra
    U = (0.0, 0.3, 0.58, 0.85, 1.0)       # a última faixa é a barra escura, mais estreita
    pegs_v = (0, NV // 2, NV)              # onde a barra é presa por estaca (sem recorte ali)
    beta = math.atan2(Ht, hw)              # inclinação da água

    def roof_pt(sx, u, v):
        y = y0 + (y1 - y0) * v
        ridge = Vector((0, y, Ht - 0.06 * math.sin(PI * v)))
        # barra: abre um pouco para fora e sobe em arco entre as estacas
        half = (v * NV) % (NV // 2) / (NV // 2)
        lift = 0.07 * math.sin(PI * half)
        hem = Vector((sx * (hw + 0.06), y, 0.04 + lift * u ** 4))
        pt = ridge.lerp(hem, u)
        # barriga: a lona afunda para dentro no meio de cada água, mais no meio da tenda
        sag = math.sin(PI * u) * (0.04 + 0.05 * math.sin(PI * v))
        return pt - Vector((sx * math.sin(beta), 0, math.cos(beta))) * sag

    for sx in (-1, 1):
        grid = [[roof_pt(sx, U[i], j / NV) for j in range(NV + 1)] for i in range(NU + 1)]
        if sx < 0:
            grid = [list(reversed(r)) for r in grid]

        def mfn(i, j, sx=sx):
            if i == NU - 1:
                return 2                                   # barra escura (lama/respingo)
            return (j if sx > 0 else NV - 1 - j) % 2       # gomos alternados
        a(sheet(bag.nm("Roof"), grid, 0.035, [p_tent_a, p_tent_b, p_tent_hem], mfn))
    # remendo costurado numa das águas
    n = Vector((math.sin(beta), 0, math.cos(beta)))
    c = roof_pt(1, 0.45, 0.68) + n * 0.012
    a(bx("Patch", c, (0.34, 0.36, 0.02), p_patch, rot=(0, beta, 0), bev=0.005))
    for k in range(4):
        ang = k * PI / 2 + PI / 4
        q = roof_pt(1, 0.45 + math.cos(ang) * 0.075, 0.68 + math.sin(ang) * 0.065) + n * 0.02
        a(bx(bag.nm("Stitch"), q, (0.035, 0.035, 0.012), p_rope, rot=(0, beta, 0), bev=0))
    a(beam("RidgePole", (0, y0 - 0.14, Ht + 0.03), (0, y1 + 0.14, Ht + 0.03), 0.04, p_wood_dk, seg=6, end_mat=p_wood_end))
    # fundo fechado (empena de lona) e interior escuro atrás da porta
    a(hull("Back", [(-hw, hd, 0.02), (hw, hd, 0.02), (0, hd, Ht - 0.05),
                    (-hw, hd - 0.03, 0.02), (hw, hd - 0.03, 0.02), (0, hd - 0.03, Ht - 0.05)], p_tent_a))
    a(hull("Dark", [(-hw * 0.88, -hd + 0.45, 0.01), (hw * 0.88, -hd + 0.45, 0.01), (0, -hd + 0.45, Ht * 0.93),
                    (-hw * 0.88, -hd + 0.4, 0.01), (hw * 0.88, -hd + 0.4, 0.01), (0, -hd + 0.4, Ht * 0.93)], p_tent_dark))
    a(bx("Floor", (0, 0.0, 0.012), (2 * hw - 0.3, 2 * hd - 0.1, 0.02), p_canvas_dk, bev=0.005))
    # saco de dormir enrolado na entrada, com duas tiras, e um travesseiro
    roll = (-0.28, -hd + 0.2, 0.13)
    axis = Vector((math.cos(0.25), math.sin(0.25), 0))
    ra, rb = Vector(roll) - axis * 0.4, Vector(roll) + axis * 0.4
    a(beam("Bedroll", ra, rb, 0.13, p_cloth_red, seg=8, end_mat=p_cloth_blue))
    for t in (0.25, 0.75):
        cc = ra.lerp(rb, t)
        a(beam(bag.nm("BedStrap"), cc - axis * 0.025, cc + axis * 0.025, 0.138, p_rope, seg=8))
    a(boulder("Pillow", (0.4, -hd + 0.55, 0.0), (0.42, 0.28, 0.14), p_cloth_blue, n=10, seed=5))
    # porta: aba esquerda enrolada e amarrada ao longo da água
    slope = Vector((-hw, 0, -Ht)).normalized()
    top = Vector((0, y0 - 0.04, Ht - 0.1))
    roll_a, roll_b = top + slope * 0.12, top + slope * 1.3
    a(beam("FlapRoll", roll_a, roll_b, 0.07, p_tent_b, seg=7, r2=0.095))
    for t in (0.3, 0.78):
        cc = roll_a.lerp(roll_b, t)
        r = 0.07 + (0.095 - 0.07) * t + 0.008
        a(beam(bag.nm("RollTie"), cc - slope * 0.025, cc + slope * 0.025, r, p_rope, seg=7))
    # aba direita: pano que desce da cumeeira e é puxado para o lado (barriga para fora)
    grid = []
    for i in range(4):
        u = i / 3
        row = []
        for j in range(3):
            v = j / 2
            edge = Vector((0.02, y0, Ht - 0.04)).lerp(Vector((hw + 0.06, y0, 0.04)), u)   # costurada na lona
            free = Vector((0.08, y0 - 0.03, Ht - 0.12)).lerp(Vector((0.6, y0 - 0.16, 0.04)), u)
            pt = edge.lerp(free, v)
            pt.y -= math.sin(PI * v) * 0.05 * (0.4 + u)
            row.append(pt)
        grid.append(row)
    a(sheet("FlapR", grid, 0.03, [p_tent_b]))
    a(beam("FlapTie", (0.42, y0 - 0.12, Ht * 0.4), (hw * 0.62, y0 - 0.02, Ht * 0.44), 0.012, p_rope, seg=4))
    # mastros com ponteira, pé de pedra, cordas e estacas; bandeirola no mastro da frente
    for sy, yy in ((-1, y0 - 0.06), (1, y1 + 0.06)):
        a(beam(bag.nm("Pole"), (0, yy, 0), (0, yy, Ht + 0.24), 0.042, p_wood_dk, seg=6, end_mat=p_wood_end))
        a(lathe(bag.nm("PoleKnob"), [(0.05, Ht + 0.23), (0.065, Ht + 0.28), (0.0, Ht + 0.35)], p_wood_lt, seg=6, loc=(0, yy, 0)))
        a(boulder(bag.nm("PoleFoot"), (0, yy, 0), (0.2, 0.18, 0.1), p_stone_dk, n=8, seed=90 + sy))
        peg = (0, yy + sy * 0.95, 0.03)
        a(beam(bag.nm("Guy"), (0, yy, Ht + 0.14), peg, 0.009, p_rope, seg=4))
        a(bx(bag.nm("Peg"), (0, peg[1] - sy * 0.03, 0.06), (0.045, 0.045, 0.18), p_wood, rot=(sy * 0.45, 0, 0), bev=0.01, taper=(0.6, 0.6)))
    fy = y0 - 0.06
    fa, fb, ft = Vector((0, fy, Ht + 0.21)), Vector((0, fy, Ht + 0.02)), Vector((0.02, fy - 0.5, Ht + 0.06))
    grid = [[fa, fa.lerp(ft, 0.5) + Vector((0.05, 0, 0.0)), ft],
            [fb, fb.lerp(ft, 0.5) + Vector((0.05, 0, -0.01)), ft + Vector((0, 0, -0.004))]]
    a(sheet("Pennant", grid, 0.012, [p_cloth_red]))
    # cordas laterais presas na barra, com estacas inclinadas
    for sx in (-1, 1):
        for j in pegs_v:
            y = min(max(y0 + (y1 - y0) * j / NV, -hd + 0.05), hd - 0.05)
            peg = (sx * (hw + 0.62), y, 0.03)
            a(beam(bag.nm("Guy"), tuple(roof_pt(sx, 0.55, j / NV)), peg, 0.008, p_rope, seg=4))
            a(bx(bag.nm("Peg"), (peg[0] - sx * 0.02, y, 0.06), (0.045, 0.045, 0.18), p_wood, rot=(0, -sx * 0.45, 0), bev=0.01, taper=(0.6, 0.6)))
    # pedras segurando a barra
    for i, (x, y) in enumerate(((-hw - 0.05, hd - 0.15), (hw + 0.1, hd - 0.3), (-hw - 0.1, 0.25))):
        a(boulder(bag.nm("HemStone"), (x, y, 0), (0.24, 0.2, 0.15), (p_stone, p_stone_lt)[i % 2], n=9, seed=80 + i))
    join(bag.items, "Tent")
    export("tent")


# ======================================================== POÇO
def build_well():
    # Poço de pedra (raio 0,88, colisão 0,95 no jogo): calçada em volta, muro de blocos irregulares com
    # junta escura, capa de pedras, mourões sobre a borda, sarilho com corda e balde, telhado de tabuinhas.
    # Usa tower_ring/grass e as pedras b_* de buildings.py (definidos antes de os construtores rodarem).
    bag = Bag()
    a = bag.add
    rnd = random.Random(12)
    R = 0.88
    mats = (b_stone, b_stone_lt, b_stone_dk)
    # calçada de lajes em volta
    for i in range(14):
        ang = i / 14 * 2 * PI + rnd.uniform(-0.05, 0.05)
        rr = R + 0.32
        a(bx(bag.nm("Flag"), (math.cos(ang) * rr, math.sin(ang) * rr, 0.03), (0.42, 2 * PI * rr / 14 - 0.05, 0.06),
             _pick(rnd, b_stone, b_stone_lt, b_stone_dk), rot=(0, 0, ang + rnd.uniform(-0.06, 0.06)), bev=0.025))
    # muro: fiadas de blocos desencontrados (com núcleo escuro) e boca escura por dentro
    tower_ring(bag, rnd, R + 0.03, R, 0.0, 0.8, 12, 0.2, mats, hmin=0.18, hmax=0.26, bev=0.03)
    a(lathe("InnerWall", [(R - 0.2, 0.86), (R - 0.2, 0.15)], p_stone_dk, seg=12, cap_bot=False, cap_top=False))
    a(lathe("Water", [(R - 0.2, 0.42), (R - 0.2, 0.43)], p_water, seg=12))
    # capa: pedras lisas com leve saliência
    n = 10
    for i in range(n):
        ang = (i + 0.5) / n * 2 * PI
        rr = R - 0.06
        a(bx(bag.nm("Cap"), (math.cos(ang) * rr, math.sin(ang) * rr, 0.85), (0.34, 2 * PI * rr / n - 0.025, 0.11),
             b_stone_lt if i % 3 else b_stone, rot=(0, 0, ang), bev=0.03))
    # musgo e capim no pé do muro
    for k, ang in enumerate((-0.9, 0.6, 2.4)):
        a(boulder(bag.nm("Moss"), (math.cos(ang) * (R + 0.05), math.sin(ang) * (R + 0.05), 0.02), (0.42, 0.26, 0.2),
                  p_moss if k % 2 else p_moss_lt, n=9, seed=13 + k))
    grass(bag, [(math.cos(t) * (R + 0.55), math.sin(t) * (R + 0.55)) for t in (0.2, 1.7, 3.6, 4.6)])
    # mourões apoiados em sapatas de pedra sobre a capa, com mãos-francesas
    for sx in (-1, 1):
        x = sx * 0.76
        a(bx(bag.nm("PostFoot"), (x, 0, 0.98), (0.24, 0.24, 0.16), b_stone_dk, bev=0.03))
        a(bx(bag.nm("WellPost"), (x, 0, 1.68), (0.14, 0.14, 1.3), p_wood_dk, bev=0.02))
        a(beam(bag.nm("Brace"), (x, -0.02, 1.95), (sx * 0.5, -0.02, 2.2), 0.035, p_wood_dk, seg=5))
    a(bx("TieBeam", (0, 0, 2.25), (1.72, 0.12, 0.1), p_wood_dk, bev=0.015))
    a(beam("Axle", (-0.9, 0, 1.85), (0.98, 0, 1.85), 0.06, p_wood, seg=8, end_mat=p_wood_end))
    for k in range(5):   # voltas de corda enroladas no sarilho
        a(lathe(bag.nm("RopeCoil"), [(0.085, -0.24 + k * 0.08), (0.085, -0.17 + k * 0.08)], p_rope, seg=8,
                rot=(0, PI / 2, 0), loc=(0, 0, 1.85), cap_top=False, cap_bot=False))
    a(bx("CrankArm", (1.0, 0, 1.74), (0.045, 0.06, 0.3), p_iron, bev=0.01))
    a(beam("CrankGrip", (1.0, 0, 1.6), (1.16, 0, 1.6), 0.028, p_wood_lt, seg=6))
    a(beam("Rope", (0, -0.085, 1.85), (0, -0.085, 1.38), 0.013, p_rope, seg=4))
    # balde pendurado e outro descansando na capa
    for kx, ky, bz, hang in ((0.0, -0.085, 1.05, True), (-0.42, -0.55, 0.9, False)):
        a(lathe(bag.nm("Bucket"), [(0.12, bz), (0.15, bz + 0.24)], [p_wood, p_wood_lt], seg=8, cap_top=False,
                mats=lambda i: i % 2, loc=(kx, ky, 0)))
        a(lathe(bag.nm("BucketIn"), [(0.13, bz + 0.19), (0.13, bz + 0.2)], p_water, seg=8, loc=(kx, ky, 0)))
        for zc in (bz + 0.04, bz + 0.19):
            rr = 0.125 + (zc - bz) * 0.12 + 0.008
            a(lathe(bag.nm("BucketHoop"), [(rr, zc - 0.015), (rr, zc + 0.015)], p_iron, seg=8, loc=(kx, ky, 0)))
        if hang:
            a(beam(bag.nm("Bail"), (kx - 0.15, ky, bz + 0.24), (kx, ky, bz + 0.35), 0.01, p_iron, seg=4))
            a(beam(bag.nm("Bail"), (kx + 0.15, ky, bz + 0.24), (kx, ky, bz + 0.35), 0.01, p_iron, seg=4))
    # telhado de tabuinhas desencontradas, cumeeira, empenas de tábuas e ponteiras
    th = math.radians(36)
    zr = 2.55
    half = 0.98
    rows = 4
    for sy in (-1, 1):
        for k in range(rows):
            sl = (k + 0.5) * half / rows
            y = sy * sl * math.cos(th)
            z = zr - sl * math.sin(th) + 0.025 * (rows - 1 - k)
            for j in range(7):
                x = -1.08 + (j + 0.5 * (k % 2)) * 0.36
                if x > 1.1:
                    continue
                a(bx(bag.nm("Shingle"), (x, y, z), (0.35, half / rows + 0.07, 0.045),
                     (p_roof, p_roof_dk, p_roof)[(j + k) % 3], rot=(-sy * th, rnd.uniform(-0.03, 0.03), 0), bev=0.01))
    a(bx("RoofRidge", (0, 0, zr + 0.08), (2.3, 0.17, 0.17), p_roof_dk, rot=(PI / 4, 0, 0), bev=0.02))
    for sx in (-1, 1):
        for k in range(4):   # empena de tábuas verticais
            yy = -0.45 + k * 0.3
            hz = zr - abs(yy) * math.tan(th) - 0.04
            a(bx(bag.nm("GablePlank"), (sx * 0.76, yy, (2.25 + hz) / 2), (0.04, 0.28, max(0.05, hz - 2.25)),
                 p_wood if k % 2 else p_wood_lt, bev=0.008))
        a(bx(bag.nm("Finial"), (sx * 1.12, 0, zr + 0.2), (0.06, 0.08, 0.4), p_wood_dk, bev=0.01))
    join(bag.items, "Well")
    export("well")


# ======================================================== RUÍNAS
# Muro: ~4,2 (X) x 0,9 (Y) x 2,0 (Z); pilar: raio ~0,5, ~4 m. Colisões em world.gd (_build_ruins).
def _stone_pick(rnd):
    r = rnd.random()
    return p_stone_dk if r < 0.3 else (p_stone_lt if r > 0.82 else p_stone)


def build_ruin_wall():
    rnd = random.Random(21)
    bag = Bag()
    a = bag.add
    L, D = 4.2, 0.8

    def top(x):   # topo quebrado: alto à esquerda, desaba no meio, sobe um pouco à direita
        t = (x + L / 2) / L
        if t < 0.35:
            return 2.0 - t * 0.6
        if t < 0.62:
            return 1.25 - (t - 0.35) * 1.2
        return 0.95 + (t - 0.62) * 1.6

    # núcleo escuro tapa as frestas entre blocos
    a(bx("Core", (0, 0, 0.55), (L - 0.3, D - 0.2, 1.1), p_stone_dk, bev=0))
    a(bx("CoreHi", (-1.2, 0, 1.3), (1.5, D - 0.2, 1.1), p_stone_dk, bev=0))
    # sapata larga
    x = -L / 2 - 0.05
    while x < L / 2 + 0.05:
        w = min(rnd.uniform(0.6, 0.95), L / 2 + 0.1 - x)
        if w > 0.15:
            a(bx(bag.nm("Footing"), (x + w / 2, rnd.uniform(-0.02, 0.02), 0.11), (w - 0.03, D + 0.12, 0.22), p_stone_dk,
                 bev=0.04, rot=(0, 0, rnd.uniform(-0.03, 0.03))))
        x += w
    # fiadas desencontradas de blocos de tamanhos variados
    tops = []   # (x0, x1, z do topo) de cada bloco, para assentar cascalho e musgo

    def surf(x0, x1):   # altura mais baixa do topo do muro no trecho (nada flutua)
        hs = []
        for k in range(5):
            xs = x0 + (x1 - x0) * k / 4
            hs.append(max([t[2] for t in tops if t[0] <= xs <= t[1]] or [0.22]))
        return min(hs)

    z = 0.22
    row = 0
    while z < 2.0:
        hgt = rnd.uniform(0.36, 0.5)
        x = -L / 2 - (0.0 if row % 2 == 0 else rnd.uniform(0.25, 0.45))
        while x < L / 2 - 0.05:
            w = rnd.uniform(0.5, 1.05)
            x0, x1 = max(x, -L / 2), min(x + w, L / 2)
            cx, ww = (x0 + x1) / 2, x1 - x0
            if ww > 0.2 and z + hgt * 0.5 < top(cx):
                hh = hgt
                if z + hgt > top(cx):   # bloco do topo: mais baixo e torto
                    hh = max(0.18, top(cx) - z + 0.08)
                rot = (rnd.uniform(-0.04, 0.04), rnd.uniform(-0.05, 0.05), rnd.uniform(-0.04, 0.04))
                a(bx(bag.nm("Block"), (cx, rnd.uniform(-0.04, 0.04), z + hh / 2),
                     (ww - 0.04, D * rnd.uniform(0.94, 1.0), hh - 0.03), _stone_pick(rnd), rot=rot, bev=0.045))
                tops.append((x0, x1, z + hh - 0.03))
            x += w
        z += hgt
        row += 1
    # pedras soltas no topo quebrado
    for i, px in enumerate((-0.35, 0.75, 1.6)):
        a(boulder(bag.nm("Rubble"), (px, rnd.uniform(-0.1, 0.1), surf(px - 0.15, px + 0.15) - 0.06), (0.42, 0.36, 0.26),
                  _stone_pick(rnd), n=10, seed=40 + i))
    # blocos caídos ao pé (frente -Y e trás +Y)
    for px, py, yaw, tilt in ((0.35, -0.85, 0.5, 0.25), (1.1, -0.72, -0.3, -0.15), (-1.4, 0.82, 0.9, 0.2), (0.6, 0.95, 0.2, 0.0)):
        a(bx(bag.nm("Fallen"), (px, py, 0.17), (rnd.uniform(0.5, 0.75), 0.42, 0.36), _stone_pick(rnd),
             rot=(tilt, 0.1, yaw), bev=0.045))
    for i, (px, py) in enumerate(((-0.4, -0.75), (1.55, 0.7), (-1.9, -0.6))):
        a(boulder(bag.nm("Chunk"), (px, py, 0), (0.3, 0.26, 0.2), p_stone_dk, n=8, seed=60 + i))
    # musgo: na base, no topo e numa junta
    a(boulder("MossFoot", (-1.1, -0.58, 0), (1.4, 0.45, 0.42), p_moss, n=12, seed=71))
    a(boulder("MossFoot2", (1.3, 0.58, 0), (1.0, 0.4, 0.34), p_moss, n=10, seed=72))
    for i, (px, w, m) in enumerate(((-1.55, 0.8, p_moss), (-0.85, 0.5, p_moss_lt), (1.35, 0.6, p_moss_lt), (0.3, 0.45, p_moss))):
        a(boulder(bag.nm("MossTop"), (px, rnd.uniform(-0.08, 0.08), surf(px - w / 2, px + w / 2) + 0.01), (w, 0.86, 0.16), m,
                  n=11, seed=73 + i, flat_bottom=False))
    a(boulder("MossDrip", (-1.5, -0.42, 1.45), (0.5, 0.14, 0.55), p_moss, n=9, seed=79, flat_bottom=False))
    a(boulder("MossFallen", (0.35, -0.85, 0.32), (0.4, 0.3, 0.12), p_moss_lt, n=8, seed=76, flat_bottom=False))
    join(bag.items, "RuinWall")
    export("ruin_wall")


def _fluted(name, r, z0, z1, material, seg=16, flute=0.08, twist=0.0, top_cut=None, seed=1):
    """Tambor de coluna com caneluras (o raio alterna a cada vértice). top_cut=(inclinação, ruído)
    parte o topo num plano torto e irregular, com o centro afundado."""
    rnd = random.Random(seed)
    bm = bmesh.new()
    rings = []
    for k, z in enumerate((z0, z1)):
        ring = []
        for i in range(seg):
            ang = 2 * PI * i / seg + twist
            rr = r * (1 - flute * (i % 2))
            zz = z
            if k == 1 and top_cut:
                zz = z + math.cos(ang) * rr * top_cut[0] + rnd.uniform(-top_cut[1], top_cut[1])
            ring.append(bm.verts.new((math.cos(ang) * rr, math.sin(ang) * rr, zz)))
        rings.append(ring)
    for i in range(seg):
        j = (i + 1) % seg
        bm.faces.new((rings[0][i], rings[0][j], rings[1][j], rings[1][i]))
    bm.faces.new(list(reversed(rings[0])))
    if top_cut:
        c = bm.verts.new((rnd.uniform(-0.05, 0.05), rnd.uniform(-0.05, 0.05), z1 - top_cut[1]))
        for i in range(seg):
            bm.faces.new((rings[1][i], rings[1][(i + 1) % seg], c))
    else:
        bm.faces.new(rings[1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _mesh_obj(name, bm, material)


def build_ruin_pillar():
    rnd = random.Random(33)
    bag = Bag()
    a = bag.add
    # base em degraus + toro
    a(bx("Step0", (0, 0, 0.09), (1.12, 1.12, 0.18), p_stone_dk, bev=0.04, rot=(0, 0, 0.02)))
    a(bx("Step1", (0, 0, 0.27), (0.92, 0.92, 0.18), p_stone, bev=0.04, rot=(0, 0, -0.03)))
    a(lathe("Torus", [(0.44, 0.36), (0.47, 0.4), (0.47, 0.46), (0.42, 0.5)], p_stone_lt, seg=16))
    # fuste: tambores com caneluras, levemente desalinhados; o último partido
    z = 0.5
    hs = (0.78, 0.74, 0.8, 0.7)
    for i, h in enumerate(hs):
        r = 0.38 - i * 0.012
        last = i == len(hs) - 1
        ob = _fluted(bag.nm("Drum"), r, z + 0.012, z + h, (p_stone, p_stone_lt, p_stone, p_stone_dk)[i], flute=0.14,
                     twist=rnd.uniform(0, 0.4), top_cut=(0.75, 0.07) if last else None, seed=50 + i)
        ob.data.transform(Matrix.Translation((rnd.uniform(-0.025, 0.025), rnd.uniform(-0.025, 0.025), 0))
                          @ Euler((rnd.uniform(-0.012, 0.012), rnd.uniform(-0.012, 0.012), 0)).to_matrix().to_4x4())
        a(ob)
        if not last:   # junta escura entre tambores
            a(lathe(bag.nm("Joint"), [(r - 0.04, z + h - 0.01), (r - 0.04, z + h + 0.02)], p_stone_dk, seg=16))
        z += h
    a(boulder("Chip", (-0.18, 0.08, z + 0.05), (0.25, 0.2, 0.16), p_stone_dk, n=8, seed=61, flat_bottom=False))
    # tambor caído (deitado), capitel quebrado e cascalho
    fallen = _fluted("FallenDrum", 0.34, -0.3, 0.3, p_stone, twist=0.2, top_cut=(0.5, 0.06), seed=70)
    fallen.data.transform(Matrix.Translation((0.95, -0.55, 0.34)) @ Euler((PI / 2, 0, 0.7)).to_matrix().to_4x4())
    a(fallen)
    a(bx("Capital", (-0.85, 0.45, 0.13), (0.62, 0.62, 0.24), p_stone_lt, rot=(0.12, -0.18, 0.5), bev=0.05))
    a(boulder("Rubble1", (-0.62, -0.62, 0), (0.28, 0.24, 0.2), p_stone_dk, n=8, seed=81))
    a(boulder("Rubble2", (0.7, 0.62, 0), (0.22, 0.2, 0.15), p_stone, n=8, seed=82))
    # musgo na base e subindo no fuste
    a(boulder("MossBase", (0.3, -0.45, 0.1), (0.75, 0.4, 0.32), p_moss, n=11, seed=91))
    a(boulder("MossBase2", (-0.45, 0.3, 0.1), (0.5, 0.55, 0.26), p_moss_lt, n=9, seed=92))
    a(boulder("MossShaft", (0.3, -0.24, 0.85), (0.22, 0.2, 0.5), p_moss, n=9, seed=93, flat_bottom=False))
    a(boulder("MossFallen", (0.95, -0.55, 0.62), (0.4, 0.35, 0.12), p_moss_lt, n=8, seed=94, flat_bottom=False))
    join(bag.items, "RuinPillar")
    export("ruin_pillar")


# ======================================================== ROCHA
def build_rock():
    # Afloramento em camadas: base larga, massa de cima deslocada, laje inclinada no topo e uma
    # lasca encostada; tons alternados por camada, musgo nas faces de cima e líquen claro.
    # A massa principal cabe no cilindro de colisão (~0,65 m de raio a escala 1).
    bag = Bag()
    a = bag.add
    a(boulder("RockBase", (0.0, 0.0, 0), (1.5, 1.2, 1.0), p_stone, n=18, seed=11, rot=(0, 0, 0.3)))
    a(boulder("RockMid", (-0.1, 0.08, 0.22), (1.25, 1.0, 0.85), p_stone, n=16, seed=13, rot=(0.05, -0.04, 0.9)))
    a(boulder("RockTop", (0.28, -0.2, 0.56), (0.72, 0.6, 0.24), p_stone_lt, n=12, seed=15, rot=(0.2, 0.16, 0.4)))
    a(boulder("RockShard", (0.62, -0.42, 0), (0.42, 0.34, 0.85), p_stone_dk, n=10, seed=17, rot=(0.18, -0.22, 1.1)))
    a(boulder("RockSide", (-0.6, 0.45, 0), (0.6, 0.5, 0.42), p_stone_lt, n=11, seed=23))
    for i, (x, y, s) in enumerate(((0.95, 0.2, 0.2), (-0.85, -0.35, 0.16), (0.2, -0.8, 0.14), (-0.3, 0.85, 0.12))):
        a(boulder(bag.nm("Pebble"), (x, y, 0), (s, s * 0.85, s * 0.6), (p_stone_dk, p_stone)[i % 2], n=8, seed=30 + i))
    # musgo cobrindo o alto (cascos achatados por cima das camadas) e escorrendo de um lado
    a(boulder("Moss", (-0.2, 0.15, 0.79), (0.78, 0.64, 0.16), p_moss, n=12, seed=19, flat_bottom=False))
    a(boulder("Moss2", (-0.42, 0.3, 0.68), (0.45, 0.4, 0.12), p_moss_lt, n=9, seed=21, flat_bottom=False))
    a(boulder("Moss3", (-0.62, 0.5, 0.36), (0.32, 0.3, 0.1), p_moss, n=8, seed=25, flat_bottom=False))
    for i, (x, y, z) in enumerate(((0.35, -0.38, 0.62), (0.15, -0.5, 0.3), (0.62, 0.2, 0.5))):   # líquen
        a(boulder(bag.nm("Lichen"), (x, y, z), (0.13, 0.11, 0.05), p_moss_lt, n=7, seed=60 + i, flat_bottom=False))
    join(bag.items, "Rock")
    export("rock")


# ======================================================== CULTURAS DA HORTA
# Cada cultura é um GLB com o canteiro inteiro (1,8 x 1,8 m, terra em Y≈0,12 no Godot):
#   "Plant"    — folhas/caules juntos (cresce com o canteiro)
#   "Fruit_N"  — frutos com origem no próprio centro (farm_plot.gd escala cada um no lugar)
#   "Mounds"   — montinhos de terra (farm_plot.gd tira do crescimento e pinta com a terra)
def _lin(r, g, b):
    return tuple(c ** 2.2 for c in (r, g, b))


c_leaf = mat("c_leaf", _lin(0.30, 0.62, 0.20), 0.8)
c_leaf_dk = mat("c_leaf_dark", _lin(0.18, 0.45, 0.14), 0.8)
c_leaf_lt = mat("c_leaf_light", _lin(0.50, 0.75, 0.26), 0.8)
c_stem = mat("c_stem", _lin(0.42, 0.55, 0.20), 0.8)
c_soil = mat("c_soil", _lin(0.30, 0.20, 0.12), 1.0)
c_carrot = mat("c_carrot", _lin(1.0, 0.5, 0.1), 0.6)
c_wheat = mat("c_wheat", _lin(0.95, 0.8, 0.3), 0.7)
c_wheat_dk = mat("c_wheat_dark", _lin(0.78, 0.6, 0.2), 0.7)
c_straw = mat("c_straw", _lin(0.72, 0.72, 0.32), 0.8)
c_tomato = mat("c_tomato", _lin(0.9, 0.12, 0.08), 0.35)
c_pepper = mat("c_pepper", _lin(1.0, 0.22, 0.04), 0.35, 0.0, emit=_lin(1.0, 0.22, 0.04), strength=0.5)
c_mint = mat("c_mint", _lin(0.45, 0.95, 1.0), 0.5, 0.0, emit=_lin(0.45, 0.95, 1.0), strength=1.2)
c_mint_leaf = mat("c_mint_leaf", _lin(0.25, 0.62, 0.45), 0.7)
c_pumpkin = mat("c_pumpkin", _lin(1.0, 0.52, 0.08), 0.6)
c_pumpkin_dk = mat("c_pumpkin_dark", _lin(0.82, 0.36, 0.05), 0.6)


def _grid(n, step):
    off = (n - 1) * step / 2
    return [(x * step - off, z * step - off) for x in range(n) for z in range(n)]


def _gp(x, z, h=0.0):
    """Posição de Godot (x, z do canteiro, altura h acima da terra) -> Blender."""
    return Vector((x, -z, 0.12 + h))


def _mounds(spots, r=0.2):
    objs = [lathe("Mound_%d" % i, [(r, -0.02), (r * 0.75, 0.04), (0.0, 0.06)], c_soil, seg=7,
                  loc=_gp(x, z, -0.0), rot=(0, 0, i)) for i, (x, z) in enumerate(spots)]
    join(objs, "Mounds")


def _fruit(objs, name, center):
    o = join(objs, name)
    set_origin(o, center)
    return o


def build_crop_carrot():
    rnd = random.Random(1)
    plant, k = [], 0
    spots = _grid(2, 0.42)
    _mounds(spots, 0.17)
    for i, (x, z) in enumerate(spots):
        b = _gp(x, z, 0.06)
        for j in range(7):   # folhas finas em leque (rama)
            yaw = j / 7 * 2 * PI + rnd.uniform(-0.2, 0.2)
            plant.append(leaf("Frond%d" % k, b + Vector((0, 0, 0.04)), yaw, rnd.uniform(0.75, 1.05), rnd.uniform(0.32, 0.42),
                              0.07, c_leaf if j % 2 else c_leaf_lt, droop=0.25, fold=0.3))
            k += 1
        plant.append(beam("Stems%d" % i, b, b + Vector((0, 0, 0.1)), 0.025, c_stem, seg=5))
        # ombro da cenoura aparecendo na terra
        carrot = lathe("Carrot%d" % i, [(0.0, -0.18), (0.05, -0.05), (0.065, 0.03), (0.055, 0.07)], c_carrot, seg=7,
                       loc=b + Vector((0, 0, -0.02)), wobble=0.06, seed=i)
        _fruit([carrot], "Fruit_%d" % i, b)
    join(plant, "Plant")
    export("crop_carrot")


def build_crop_wheat():
    rnd = random.Random(2)
    plant = []
    spots = _grid(3, 0.5)
    _mounds(spots, 0.16)
    for i, (x, z) in enumerate(spots):
        b = _gp(x, z, 0.04)
        heads = []
        top_sum = Vector()
        for j in range(5):
            yaw = j / 5 * 2 * PI + rnd.uniform(-0.3, 0.3)
            lean = rnd.uniform(0.05, 0.16)
            h = rnd.uniform(0.75, 0.95)
            top = b + Vector((math.cos(yaw) * lean, math.sin(yaw) * lean, h))
            plant.append(beam("Stalk%d_%d" % (i, j), b + Vector((math.cos(yaw) * 0.03, math.sin(yaw) * 0.03, 0)), top,
                              0.012, c_straw if j % 2 else c_stem, seg=4))
            # espiga: grãos em losango ao longo de um fuso facetado + barbas
            d = (top - b).normalized()
            hd = top + d * 0.13
            heads.append(lathe("Head%d_%d" % (i, j), [(0.0, 0.0), (0.035, 0.05), (0.04, 0.14), (0.0, 0.24)],
                               c_wheat if j % 2 else c_wheat_dk, seg=5, loc=top - d * 0.02,
                               rot=Vector((0, 0, 1)).rotation_difference(d).to_euler()))
            heads.append(beam("Awn%d_%d" % (i, j), hd, hd + d * 0.14, 0.004, c_wheat, seg=3))
            top_sum += hd
        for j in range(3):   # folhas compridas na base
            yaw = j / 3 * 2 * PI + 0.5
            plant.append(leaf("Blade%d_%d" % (i, j), b + Vector((0, 0, 0.05)), yaw, 0.6, 0.45, 0.05, c_leaf, droop=0.5, fold=0.2))
        _fruit(heads, "Fruit_%d" % i, top_sum / 5)
    join(plant, "Plant")
    export("crop_wheat")


def build_crop_tomato():
    rnd = random.Random(3)
    plant = []
    spots = _grid(2, 0.42)
    _mounds(spots, 0.18)
    fi = 0
    for i, (x, z) in enumerate(spots):
        b = _gp(x, z, 0.0)
        plant.append(bx("Stake%d" % i, b + Vector((0.08, 0.08, 0.5)), (0.035, 0.035, 1.0), p_wood_lt, bev=0.008))
        plant.append(bx("Tie%d" % i, b + Vector((0.07, 0.07, 0.62)), (0.06, 0.06, 0.03), p_rope, bev=0.005))
        plant.append(beam("Stem%d" % i, b, b + Vector((0.03, 0.03, 0.85)), 0.018, c_stem, seg=5))
        for j, (hz, s) in enumerate(((0.32, 0.36), (0.55, 0.32), (0.78, 0.24))):   # copa em 3 tufos
            plant.append(boulder("Bush%d_%d" % (i, j), b + Vector((rnd.uniform(-0.04, 0.04), rnd.uniform(-0.04, 0.04), hz - s * 0.4)),
                                 (s, s, s * 0.8), c_leaf if j % 2 else c_leaf_dk, n=10, seed=i * 10 + j, flat_bottom=False))
        for j in range(5):
            yaw = j / 5 * 2 * PI
            plant.append(leaf("TLeaf%d_%d" % (i, j), b + Vector((0, 0, 0.25 + j * 0.1)), yaw, 1.1, 0.24, 0.14, c_leaf_dk, droop=0.3))
        for j in range(3):
            a = j * 2 * PI / 3 + 0.4
            c = b + Vector((math.cos(a) * 0.19, math.sin(a) * 0.19, 0.42 + j * 0.13))
            t = lathe("Tom%d" % fi, [(0.0, -0.065), (0.06, -0.045), (0.08, 0.0), (0.065, 0.045), (0.0, 0.06)], c_tomato,
                      seg=8, loc=c)
            cal = [leaf("Calyx%d_%d" % (fi, q), c + Vector((0, 0, 0.055)), q * 2 * PI / 5, 0.25, 0.06, 0.03, c_leaf_dk, droop=0.1)
                   for q in range(5)]
            _fruit([t] + cal, "Fruit_%d" % fi, c)
            fi += 1
    join(plant, "Plant")
    export("crop_tomato")


def build_crop_pepper():
    rnd = random.Random(4)
    plant = []
    spots = _grid(2, 0.42)
    _mounds(spots, 0.17)
    fi = 0
    for i, (x, z) in enumerate(spots):
        b = _gp(x, z, 0.0)
        plant.append(beam("Stem%d" % i, b, b + Vector((0, 0, 0.45)), 0.02, c_stem, seg=5))
        for j in range(11):   # arbusto de folhas lanceoladas em espiral
            yaw = j * 2.4
            hz = 0.12 + (j / 11) * 0.42
            plant.append(leaf("PLeaf%d_%d" % (i, j), b + Vector((0, 0, hz)), yaw, rnd.uniform(0.9, 1.3), 0.2, 0.09,
                              c_leaf_dk if j % 3 else c_leaf, droop=0.25))
        for j in range(3):
            a = j * 2 * PI / 3 + 0.2
            top = b + Vector((math.cos(a) * 0.13, math.sin(a) * 0.13, 0.36 + (j % 2) * 0.06))
            # pimenta pendurada: cone curvo (3 trechos) com cabinho verde
            body = lathe("Pep%d" % fi, [(0.0, -0.21), (0.022, -0.16), (0.04, -0.07), (0.045, -0.01), (0.03, 0.0)], c_pepper,
                         seg=6, loc=top, rot=(math.sin(a) * 0.35, -math.cos(a) * 0.35, 0))
            cap = beam("PCap%d" % fi, top, top + Vector((0, 0, 0.05)), 0.012, c_stem, seg=4)
            _fruit([body, cap], "Fruit_%d" % fi, top + Vector((0, 0, -0.1)))
            fi += 1
    join(plant, "Plant")
    export("crop_pepper")


def build_crop_mint():
    rnd = random.Random(5)
    plant = []
    spots = _grid(2, 0.42)
    _mounds(spots, 0.17)
    fi = 0
    for i, (x, z) in enumerate(spots):
        b = _gp(x, z, 0.0)
        for s in range(3):   # 3 hastes quadradas, folhas em pares opostos girando 90°
            ang = s * 2 * PI / 3 + rnd.uniform(-0.3, 0.3)
            base = b + Vector((math.cos(ang) * 0.05, math.sin(ang) * 0.05, 0.02))
            h = rnd.uniform(0.45, 0.58)
            top = base + Vector((math.cos(ang) * 0.06, math.sin(ang) * 0.06, h))
            plant.append(beam("MStem%d_%d" % (i, s), base, top, 0.012, c_mint_leaf, seg=4))
            nodes = 4
            tops = []
            for k in range(nodes):
                t = (k + 1) / (nodes + 0.5)
                p = base.lerp(top, t)
                for side in (0, PI):
                    yaw = ang + k * PI / 2 + side
                    if k >= nodes - 2:   # folhas novas do topo brilham (a colheita)
                        tops.append(leaf("MTop%d_%d_%d_%d" % (i, s, k, int(side)), p, yaw, 0.7, 0.13, 0.09, c_mint, droop=0.1, fold=0.25))
                    else:
                        plant.append(leaf("MLeaf%d_%d_%d_%d" % (i, s, k, int(side)), p, yaw, 0.95, 0.16, 0.11,
                                          c_mint_leaf, droop=0.2, fold=0.25))
            tops.append(leaf("MTip%d_%d" % (i, s), top, ang, 0.6, 0.08, 0.06, c_mint, droop=0.0))
            _fruit(tops, "Fruit_%d" % fi, top - Vector((0, 0, 0.1)))
            fi += 1
    join(plant, "Plant")
    export("crop_mint")


def build_crop_pumpkin():
    rnd = random.Random(6)
    plant = []
    _mounds([(0.0, 0.0)], 0.4)
    c = _gp(0.0, 0.05, 0.0)
    # gomos: esfera achatada com 8 sulcos (raio modulado pelo ângulo)
    bm = bmesh.new()
    seg, rings = 16, 7
    vs = []
    for r in range(1, rings):
        v = r / rings * PI
        row = []
        for s in range(seg):
            u = s / seg * 2 * PI
            k = 1.0 - 0.12 * (0.5 - 0.5 * math.cos(8 * u))
            row.append(bm.verts.new((math.cos(u) * math.sin(v) * 0.42 * k, math.sin(u) * math.sin(v) * 0.42 * k,
                                     -math.cos(v) * 0.29)))
        vs.append(row)
    bot = bm.verts.new((0, 0, -0.27))
    topv = bm.verts.new((0, 0, 0.24))
    for r in range(len(vs) - 1):
        for s in range(seg):
            t = (s + 1) % seg
            f = bm.faces.new((vs[r][s], vs[r][t], vs[r + 1][t], vs[r + 1][s]))
            f.material_index = (s // 1) % 2
    for s in range(seg):
        t = (s + 1) % seg
        bm.faces.new((bot, vs[0][t], vs[0][s])).material_index = s % 2
        bm.faces.new((topv, vs[-1][s], vs[-1][t])).material_index = s % 2
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.transform(bm, matrix=Matrix.Translation(c + Vector((0, 0, 0.27))), verts=bm.verts)
    body = _mesh_obj("PumpkinBody", bm, [c_pumpkin, c_pumpkin_dk])
    stem = beam("PStem", c + Vector((0, 0, 0.5)), c + Vector((0.05, 0.02, 0.66)), 0.035, c_stem, seg=5, r2=0.025)
    _fruit([body, stem], "Fruit_0", c + Vector((0, 0, 0.27)))
    # rama: trechos de caule pelo chão + folhas largas
    for j in range(5):
        a = j * 2 * PI / 5 + 0.3
        p0 = c + Vector((0, 0, 0.03))
        p1 = c + Vector((math.cos(a) * 0.45, math.sin(a) * 0.45, 0.04))
        p2 = c + Vector((math.cos(a + 0.4) * 0.75, math.sin(a + 0.4) * 0.75, 0.03))
        plant.append(beam("Vine%d" % j, p0, p1, 0.02, c_stem, seg=4))
        plant.append(beam("Vine%db" % j, p1, p2, 0.017, c_stem, seg=4))
        for q, p in enumerate((p1, p2)):
            plant.append(leaf("PLeaf%d_%d" % (j, q), p, a - PI / 2 + rnd.uniform(-0.5, 0.5), 0.15, 0.36, 0.34,
                              c_leaf if q else c_leaf_dk, droop=0.05, fold=0.12))
        plant.append(beam("Stalk%d" % j, p1, p1 + Vector((0, 0, 0.12)), 0.012, c_stem, seg=4))
    join(plant, "Plant")
    export("crop_pumpkin")


def build_field_crop():
    """Pé de repolho para os campos dos slimes (MultiMesh): uma malha só."""
    objs = [boulder("Head", (0, 0, 0.04), (0.26, 0.26, 0.24), c_leaf_lt, n=12, seed=2)]
    for j in range(7):
        yaw = j / 7 * 2 * PI
        objs.append(leaf("Leaf%d" % j, (0, 0, 0.05), yaw, rnd_pitch(j), 0.3, 0.24, c_leaf if j % 2 else c_leaf_dk, droop=0.15))
    join(objs, "FieldCrop")
    export("field_crop")


def rnd_pitch(j):
    return 0.15 + 0.12 * ((j * 37) % 5) / 5.0


# ======================================================== VEGETAÇÃO (MultiMesh em ground.gd)
# Uma malha só por planta, origem no chão; sem colisão (decoração espalhada aos milhares).
v_bush = mat("v_bush", _lin(0.24, 0.50, 0.15), 0.9)
v_bush_dk = mat("v_bush_dark", _lin(0.14, 0.36, 0.10), 0.9)
v_bush_lt = mat("v_bush_light", _lin(0.40, 0.64, 0.20), 0.9)
v_fern = mat("v_fern", _lin(0.22, 0.52, 0.16), 0.85)
v_fern_dk = mat("v_fern_dark", _lin(0.14, 0.40, 0.12), 0.85)
v_berry = mat("v_berry", _lin(0.80, 0.12, 0.16), 0.4)


def _bush(name, berries):
    rnd = random.Random(7 if berries else 5)
    objs = []
    # tufos de folhagem facetados: um central alto e outros em volta, mais baixos
    blobs = [((0, 0, 0), (1.0, 0.9, 0.78), v_bush)]
    for k in range(5):
        a = k / 5 * 2 * PI + rnd.uniform(-0.3, 0.3)
        d = rnd.uniform(0.32, 0.45)
        s = rnd.uniform(0.55, 0.72)
        blobs.append(((math.cos(a) * d, math.sin(a) * d, 0), (s, s * 0.9, s * 0.8), (v_bush_dk, v_bush, v_bush_lt)[k % 3]))
    for i, (p, s, m) in enumerate(blobs):
        objs.append(boulder("%s_B%d" % (name, i), p, s, m, n=12, seed=100 + i * 7 + (50 if berries else 0)))
    # topo mais claro (luz de cima)
    objs.append(boulder(name + "_Top", (0.05, -0.05, 0.42), (0.6, 0.55, 0.3), v_bush_lt, n=9, seed=31, flat_bottom=False))
    # folhas soltas na borda quebram a silhueta redonda
    for k in range(9):
        a = k / 9 * 2 * PI + rnd.uniform(-0.2, 0.2)
        r = rnd.uniform(0.45, 0.6)
        objs.append(leaf("%s_L%d" % (name, k), (math.cos(a) * r * 0.8, math.sin(a) * r * 0.8, rnd.uniform(0.15, 0.45)),
                         a - PI / 2, rnd.uniform(0.1, 0.5), 0.28, 0.16, (v_bush, v_bush_dk)[k % 2], droop=0.2))
    if berries:
        for k in range(16):   # na casca de um dos tufos (boulder: centro em z = 0,55*meia-altura)
            p, s, _m = blobs[k % len(blobs)]
            a = rnd.uniform(0, 2 * PI)
            el = rnd.uniform(0.1, 0.9)
            hx, hy, hz = s[0] / 2 * 0.86, s[1] / 2 * 0.86, s[2] / 2 * 0.86
            c = (p[0] + math.cos(a) * math.cos(el) * hx, p[1] + math.sin(a) * math.cos(el) * hy,
                 0.55 * s[2] / 2 + math.sin(el) * hz)
            objs.append(boulder("%s_Berry%d" % (name, k), c, (0.08, 0.08, 0.08), v_berry, n=6, seed=200 + k, flat_bottom=False))
    join(objs, name)


def build_bush():
    _bush("Bush", False)
    export("bush")


def build_bush_berry():
    _bush("BushBerry", True)
    export("bush_berry")


def build_fern():
    rnd = random.Random(9)
    objs = []
    n = 9
    for j in range(n):
        yaw = j / n * 2 * PI + rnd.uniform(-0.2, 0.2)
        pitch = rnd.uniform(0.55, 0.95)
        L = rnd.uniform(0.55, 0.75)
        droop = 0.55
        m = v_fern if j % 2 else v_fern_dk
        objs.append(leaf("Frond%d" % j, (0, 0, 0.02), yaw, pitch, L, 0.1, m, droop=droop, fold=0.1))
        # folíolos em pares ao longo da fronde (segue o arco aproximado da folha)
        fwd = Vector((math.cos(yaw + PI / 2), math.sin(yaw + PI / 2), 0))
        for k in range(1, 5):
            t = k / 5
            hz = t * L * math.cos(pitch)
            z = 0.02 + t * L * math.sin(pitch) - droop * L * t * t * 0.9
            base = fwd * hz + Vector((0, 0, z))
            size = 0.2 * (1.1 - t * 0.6)
            for side in (-1, 1):
                objs.append(leaf("Leaflet%d_%d_%d" % (j, k, side + 1), base, yaw + side * 1.0, 0.1 - t * 0.5, size, size * 0.45,
                                 m, droop=0.15, fold=0.2))
    join(objs, "Fern")
    export("fern")


# ======================================================== BIGORNA
def build_anvil():
    # Bigorna de aço sobre tora; chifre para a frente (-Y). Topo da face em Z=0,8, com uma barra em brasa
    # (WorkBar, à parte) deitada nela: o golpe do ferreiro (work_hammer) mira o empty StrikePoint no topo da
    # barra, perto da ponta quente. A barra cruza a face na diagonal e passa da borda, onde a tenaz do
    # ferreiro a segura (tools/blender/characters.py, BS_BAR: mesma barra nas coordenadas do ferreiro).
    bag = Bag()
    a = bag.add
    top = 0.8
    a(beam("Stump", (0, 0, 0), (0, 0, 0.46), 0.3, p_wood, seg=9, r2=0.27, end_mat=p_wood_end))
    a(bx("Foot", (0, 0.02, 0.5), (0.34, 0.46, 0.08), p_iron, bev=0.012))
    a(bx("Waist", (0, 0.02, 0.59), (0.2, 0.3, 0.15), p_iron, bev=0.012))   # 0,515..0,665: encosta no pé e no corpo
    a(bx("Body", (0, 0.04, top - 0.09), (0.28, 0.62, 0.1), p_iron, bev=0.012))
    a(bx("Face", (0, 0.04, top - 0.02), (0.3, 0.62, 0.04), p_iron_lt, bev=0.008))
    # chifre cônico para a frente e cauda curta atrás
    a(hull("Horn", [(sx * 0.12, -0.27, top - 0.04) for sx in (-1, 1)] + [(sx * 0.12, -0.27, top - 0.14) for sx in (-1, 1)]
           + [(0, -0.62, top - 0.08)], p_iron_lt))
    a(bx("Tail", (0, 0.4, top - 0.06), (0.22, 0.14, 0.08), p_iron, bev=0.01))
    a(bx("Hardy", (0, 0.3, top + 0.005), (0.04, 0.04, 0.01), p_iron, bev=0.003))
    join(bag.items, "Anvil")
    hot, cold = Vector((-0.035, 0.077, top + 0.01)), Vector((0.19, -0.16, top + 0.01))
    d = cold - hot
    yaw = math.atan2(d.y, d.x)
    mid = hot + d * 0.55
    join([bx("WorkBarHot", (hot + mid) / 2, ((mid - hot).length, 0.03, 0.02), p_ember, rot=(0, 0, yaw), bev=0.004),
          bx("WorkBarCold", (mid + cold) / 2, ((cold - mid).length, 0.028, 0.019), p_iron, rot=(0, 0, yaw), bev=0.004)],
         "WorkBar")
    empty("StrikePoint", (0, 0.04, top + 0.02))
    export("anvil")


# ======================================================== FORJA
def build_forge():
    # Forja baixa de pedra (0,9 x 0,8 x 0,7 m), brasas ao centro e fole de couro ao lado (+X).
    # Frente = -Y. O empty Embers marca o meio das brasas (luz/partículas).
    bag = Bag()
    a = bag.add
    rnd = random.Random(12)
    a(bx("Plinth", (0, 0, 0.06), (0.95, 0.85, 0.12), p_stone_dk, bev=0.03))
    a(bx("Back", (0, 0.32, 0.45), (0.9, 0.2, 0.7), p_stone, bev=0.03))
    a(bx("SideL", (-0.4, -0.05, 0.36), (0.18, 0.7, 0.48), p_stone_lt, bev=0.03))
    a(bx("SideR", (0.4, -0.05, 0.36), (0.18, 0.7, 0.48), p_stone, bev=0.03))
    a(bx("Front", (0, -0.36, 0.32), (0.62, 0.14, 0.4), p_stone_lt, bev=0.03))
    a(bx("Hearth", (0, -0.05, 0.5), (0.62, 0.55, 0.06), p_ash, bev=0.01))
    for i in range(5):   # pedras irregulares na borda
        a(boulder(bag.nm("Rock"), (-0.4 + i * 0.2, -0.38, 0.58), (0.16, 0.12, 0.1), (p_stone, p_stone_lt)[i % 2],
                  n=9, seed=90 + i))
    a(bx("Hood", (0, 0.3, 1.05), (0.46, 0.22, 0.7), p_stone, bev=0.03, taper=(0.7, 0.7)))   # chaminé afunilada
    for i in range(8):   # brasas e carvão
        a(boulder(bag.nm("Ember"), (rnd.uniform(-0.2, 0.2), rnd.uniform(-0.18, 0.1), 0.56),
                  (0.11, 0.1, 0.07), p_ember if i % 3 else p_fire, n=8, seed=100 + i))
    a(boulder("Coal", (0.0, -0.05, 0.55), (0.3, 0.26, 0.08), p_ash, n=10, seed=120))
    # fole: duas tábuas, couro dobrado em losango, bico de ferro virado para a forja
    a(bx("BellowsBase", (0.78, -0.02, 0.22), (0.34, 0.5, 0.05), p_wood_dk, bev=0.008))
    a(bx("BellowsTop", (0.78, -0.02, 0.5), (0.3, 0.46, 0.05), p_wood, bev=0.008, rot=(0.08, 0, 0)))
    a(hull("BellowsLeather", [(0.78 + sx * 0.15, -0.02 + sy * 0.23, 0.245) for sx in (-1, 1) for sy in (-1, 1)]
           + [(0.78 + sx * 0.12, -0.02 + sy * 0.2, 0.475) for sx in (-1, 1) for sy in (-1, 1)]
           + [(0.78 + sx * 0.2, -0.02, 0.36) for sx in (-1, 1)], leather))
    a(beam("Nozzle", (0.7, -0.02, 0.34), (0.5, -0.02, 0.5), 0.03, p_iron, seg=5, r2=0.02))
    a(beam("Handle", (0.78, 0.22, 0.52), (0.78, 0.42, 0.7), 0.02, p_iron, seg=5))
    join(bag.items, "Forge")
    empty("Embers", (0, -0.05, 0.62))
    export("forge")




# ======================================================== PLACAS
def build_signpost():
    # Poste de direção: pedras no pé, poste roliço com telhadinho e lanterna, e 4 setas soltas ("Arrow0".."Arrow3"),
    # cada uma com a origem no eixo do poste e apontando para +X: o jogo gira cada seta para o seu destino e põe o
    # texto (Label3D) nela; seta sem destino fica escondida. Frente da seta em -Y.
    bag = Bag()
    a = bag.add
    for k in range(6):
        ang = k / 6 * 2 * PI + 0.3
        a(boulder(bag.nm("Stone"), (math.cos(ang) * 0.22, math.sin(ang) * 0.22, 0), (0.26, 0.22, 0.18),
                  (p_stone, p_stone_lt)[k % 2], n=9, seed=780 + k))
    a(beam("Post", (0, 0, 0.0), (0, 0, 2.55), 0.075, p_wood, seg=7, r2=0.065, end_mat=p_wood_end))
    a(bx("Cap", (0, 0, 2.6), (0.3, 0.3, 0.06), p_wood_dk, bev=0.015))
    for sy in (-1, 1):
        a(bx(bag.nm("CapRoof"), (0, sy * 0.1, 2.7), (0.36, 0.24, 0.04), p_roof, rot=(-sy * 0.6, 0, 0), bev=0.01))
    join(bag.items, "Signpost")
    for i, z in enumerate((2.25, 1.93, 1.61, 1.29)):
        arm = Bag()
        x0, x1, h = 0.1, 1.15, 0.26
        tone = (p_wood_lt, p_wood, p_wood_lt, p_wood)[i]
        arm.add(hull("Board%d" % i, [(x0, -0.03, z - h / 2), (x0, 0.03, z - h / 2), (x0, -0.03, z + h / 2), (x0, 0.03, z + h / 2),
                                     (x1 - 0.16, -0.03, z - h / 2), (x1 - 0.16, 0.03, z - h / 2), (x1 - 0.16, -0.03, z + h / 2),
                                     (x1 - 0.16, 0.03, z + h / 2), (x1, -0.03, z), (x1, 0.03, z)], tone))
        arm.add(bx("Trim%d" % i, (x0 + 0.02, 0, z), (0.04, 0.08, h + 0.04), p_wood_dk, bev=0.008))
        for zz in (z - 0.07, z + 0.07):
            arm.add(bx(arm.nm("Nail%d_" % i), (x0 + 0.05, -0.04, zz), (0.025, 0.02, 0.025), p_iron, bev=0.004))
        ob = join(arm.items, "Arrow%d" % i)
        set_origin(ob, (0, 0, z))
    export("signpost")


def build_notice_board():
    # Quadro de avisos 2,4 m: dois postes, telhadinho, moldura e um pergaminho grande no meio (onde o jogo escreve
    # com Label3D: centro a 1,6 m, frente em -Y a ~0,06 m do eixo) e bilhetes pregados nas bordas.
    bag = Bag()
    a = bag.add
    for sx in (-1, 1):
        a(bx(bag.nm("Post"), (sx * 1.25, 0, 1.4), (0.16, 0.16, 2.8), p_wood_dk, bev=0.02))
        a(boulder(bag.nm("Foot"), (sx * 1.25, 0, 0), (0.34, 0.3, 0.2), p_stone, n=9, seed=912 + sx))
    for k in range(5):   # tábuas do fundo
        a(bx(bag.nm("BoardPlank"), (0, 0.0, 0.85 + k * 0.31 + 0.15), (2.34, 0.06, 0.3), p_wood if k % 2 else p_wood_lt, bev=0.008))
    for sz in (-1, 1):
        a(bx(bag.nm("FrameH"), (0, -0.03, 1.6 + sz * 0.8), (2.5, 0.08, 0.1), p_wood_dk, bev=0.012))
    a(bx("Parchment", (0, -0.035, 1.6), (2.12, 0.012, 1.28), p_canvas, bev=0.0))
    for x, z, w, hh, yaw in ((-1.07, 2.2, 0.2, 0.26, 0.12), (1.02, 2.22, 0.24, 0.18, -0.1), (1.1, 0.98, 0.18, 0.24, 0.08)):
        a(bx(bag.nm("Note"), (x, -0.045, z), (w, 0.01, hh), b_cloth_w, rot=(0, yaw, 0), bev=0.0))
        a(bx(bag.nm("Pin"), (x, -0.055, z + hh / 2 - 0.04), (0.025, 0.015, 0.025), p_roof, bev=0.004))
    for sx in (-1, 1):
        for sz in (-1, 1):
            a(bx(bag.nm("Tack"), (sx * 1.0, -0.05, 1.6 + sz * 0.58), (0.035, 0.015, 0.035), p_iron, bev=0.005))
    th = math.radians(30)
    for sy in (-1, 1):
        for k in range(2):
            sl = (k + 0.5) * 0.25
            a(bx(bag.nm("Roof"), (0, sy * sl * math.cos(th), 2.95 - sl * math.sin(th) + 0.02 * (1 - k)), (2.85, 0.28, 0.05),
                 (p_roof, p_roof_dk)[k], rot=(-sy * th, 0, 0), bev=0.01))
    a(bx("Ridge", (0, 0, 3.0), (2.9, 0.12, 0.12), p_roof_dk, rot=(PI / 4, 0, 0), bev=0.015))
    a(bx("RoofBeam", (0, 0, 2.82), (2.7, 0.12, 0.12), p_wood_dk, bev=0.015))
    join(bag.items, "NoticeBoard")
    export("notice_board")


PROP_BUILDERS = {
    "chest": build_chest, "fence": build_fence, "crate": build_crate, "barrel": build_barrel,
    "lamp": build_lamp, "campfire": build_campfire, "tent": build_tent, "well": build_well, "rock": build_rock,
    "ruin_wall": build_ruin_wall, "ruin_pillar": build_ruin_pillar,
    "crop_carrot": build_crop_carrot, "crop_wheat": build_crop_wheat, "crop_tomato": build_crop_tomato,
    "crop_pepper": build_crop_pepper, "crop_mint": build_crop_mint, "crop_pumpkin": build_crop_pumpkin,
    "field_crop": build_field_crop,
    "anvil": build_anvil, "forge": build_forge, "signpost": build_signpost, "notice_board": build_notice_board,
    "bush": build_bush, "bush_berry": build_bush_berry, "fern": build_fern,
}
