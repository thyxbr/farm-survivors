# Personagens low-poly detalhados (cavaleiro, ancião, mercadora, goblin).
# Executado dentro de build_assets.py (usa scn, coll, mat, empty, _wloc, export, PI).
# Convenções: frente do personagem = -Y no Blender (+Z no Godot). Pivôs usados pelas
# animações do jogo: LegL, LegR (quadril), Body (quadril), Head (pescoço), ArmL, ArmR (ombro).
import bmesh, math, random
from mathutils import Matrix, Euler, Vector


# ------------------------------------------------------------------ helpers de malha
def _finish(name, bm, material, parent, smooth=False):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.validate()
    for p in me.polygons:
        p.use_smooth = smooth
    me.materials.append(material)
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    if parent is not None:
        ob.parent = parent
    return ob


def _place(bm, loc, parent, rotm=None):
    R = rotm.to_4x4() if rotm is not None else Matrix.Identity(4)
    M = Matrix.Translation(Vector(loc) - _wloc(parent)) @ R
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts)


def _bevel(bm, amount):
    bmesh.ops.bevel(bm, geom=bm.verts[:] + bm.edges[:], offset=amount, segments=1, profile=0.5,
                    affect='EDGES', clamp_overlap=True)


def _jit(bm, amount, seed):
    rnd = random.Random(seed)
    for v in bm.verts:
        v.co += Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))) * amount


def tbox(name, loc, size, material, top=(1, 1), bottom=(1, 1), shift_top=(0, 0), shift_bottom=(0, 0),
         bevel=0.0, rot=(0, 0, 0), parent=None, jitter=0.0, seed=1):
    """Caixa com topo/base afunilados e chanfro."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        x, y, z = v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]
        if v.co.z > 0:
            x, y = x * top[0] + shift_top[0], y * top[1] + shift_top[1]
        else:
            x, y = x * bottom[0] + shift_bottom[0], y * bottom[1] + shift_bottom[1]
        v.co = Vector((x, y, z))
    if bevel:
        _bevel(bm, bevel)
    if jitter:
        _jit(bm, jitter, seed)
    _place(bm, loc, parent, Euler(rot).to_matrix())
    return _finish(name, bm, material, parent)


def limb(name, p0, p1, r0, r1, material, sides=6, flat=1.0, parent=None, twist=0.0, bevel=0.0, jitter=0.0, seed=1):
    """Prisma afunilado ligando p0 (raio r0) a p1 (raio r1)."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=sides, radius1=r0, radius2=r1, depth=d.length)
    for v in bm.verts:
        v.co.y *= flat
        if twist:
            v.co = Matrix.Rotation(twist, 3, 'Z') @ v.co
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    if bevel and r0 > 0 and r1 > 0:
        _bevel(bm, bevel)
    if jitter:
        _jit(bm, jitter, seed)
    q = Vector((0, 0, 1)).rotation_difference(d.normalized())
    _place(bm, (p0 + p1) / 2, parent, q.to_matrix())
    return _finish(name, bm, material, parent)


def shell(name, loc, size, material, cut=0.0, seg=10, rings=8, rot=(0, 0, 0), parent=None, thick=0.012, jitter=0.0, seed=1):
    """Calota de esfera (z >= cut, em -1..1) com espessura."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=0.5)
    kill = [v for v in bm.verts if v.co.z < cut * 0.5 - 1e-4]
    if kill:
        bmesh.ops.delete(bm, geom=kill, context='VERTS')
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    if jitter:
        _jit(bm, jitter, seed)
    if thick:
        bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=thick)
    _place(bm, loc, parent, Euler(rot).to_matrix())
    return _finish(name, bm, material, parent)


def drape(name, z0, z1, r0, r1, arc0, arc1, material, center=(0, 0), back=1.0, rows=5, cols=10,
          folds=0.02, thick=0.018, parent=None, face=1.0, lift=0.0, center1=None):
    """Tecido em arco: capas (arc < 2pi, face=+1 atrás) ou saias/túnicas (arc = 2pi), com dobras."""
    bm = bmesh.new()
    grid = []
    for i in range(rows + 1):
        t = i / rows
        z = z0 + (z1 - z0) * t
        r = r0 + (r1 - r0) * t
        arc = arc0 + (arc1 - arc0) * t
        row = []
        for j in range(cols + 1):
            a = -arc / 2 + arc * j / cols
            edge = (j == 0 or j == cols) and arc < 6.2
            rr = r + (0 if edge else folds * t * (1 if j % 2 else -1))
            c1 = center1 or center
            cx, cy = center[0] + (c1[0] - center[0]) * t, center[1] + (c1[1] - center[1]) * t
            x = cx + math.sin(a) * rr
            y = cy + math.cos(a) * rr * back * face
            zz = z + (lift * t * abs(math.sin(a)) if lift else 0)
            row.append(bm.verts.new((x, y, zz)))
        grid.append(row)
    for i in range(rows):
        for j in range(cols):
            bm.faces.new((grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]))
    if arc0 >= 6.2:
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=thick)
    _place(bm, (0, 0, 0), parent)
    return _finish(name, bm, material, parent)


def ring(name, z, r, h, material, parent=None, sides=10, flat=1.0, y=0.0, x=0.0):
    return limb(name, (x, y, z - h / 2), (x, y, z + h / 2), r, r, material, sides=sides, flat=flat, parent=parent)


def hexc(h):
    """Cor sRGB em hex -> tupla linear (o que o Principled BSDF espera)."""
    h = h.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return tuple(out)


def cloth(name, z0, z1, r0, r1, arc0, arc1, mats, bands, center=(0, 0), back=1.0, cols=10, folds=0.02,
          thick=0.018, parent=None, border=0.0, border_mat=0, flare=1.0):
    """Tecido com barras: como drape(), mas cada faixa horizontal tem seu material.
    bands = [(t_fim, indice_material), ...] com t de 0 (topo) a 1 (barra).
    border = fração do arco usada como debrum lateral (só em tecidos abertos), no material border_mat."""
    closed = arc0 >= 6.2
    ts = [0.0] + [b[0] for b in bands]
    if closed or border <= 0:
        us = [j / cols for j in range(cols + (0 if closed else 1))]
    else:
        us = [0.0] + [border + (1 - 2 * border) * j / cols for j in range(cols + 1)] + [1.0]
    bm = bmesh.new()
    grid = []
    for t in ts:
        z = z0 + (z1 - z0) * t
        r = r0 + (r1 - r0) * (t ** flare)
        arc = arc0 + (arc1 - arc0) * t
        row = []
        for j, u in enumerate(us):
            a = -arc / 2 + arc * u
            edge = (not closed) and (j == 0 or j == len(us) - 1)
            rr = r + (0 if edge else folds * t * (1 if j % 2 else -1))
            row.append(bm.verts.new((center[0] + math.sin(a) * rr, center[1] + math.cos(a) * rr * back, z)))
        grid.append(row)
    n = len(us)
    for i in range(len(ts) - 1):
        for j in range(n if closed else n - 1):
            k = (j + 1) % n
            f = bm.faces.new((grid[i][j], grid[i + 1][j], grid[i + 1][k], grid[i][k]))
            side = (not closed) and border > 0 and (j == 0 or j == n - 2)
            f.material_index = border_mat if side else bands[i][1]
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if thick:
        bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=thick)
    _place(bm, (0, 0, 0), parent)
    ob = _finish(name, bm, mats[0], parent)
    for m in mats[1:]:
        ob.data.materials.append(m)
    return ob


def scale_group(parent, pivot, f):
    """Escala todas as malhas filhas de parent em torno de pivot (coords de mundo), sem mexer no nó."""
    pv = Vector(pivot) - _wloc(parent)
    M = Matrix.Translation(pv) @ Matrix.Diagonal((f, f, f, 1)) @ Matrix.Translation(-pv)
    for o in parent.children:
        if o.type == 'MESH':
            o.data.transform(M)


# ------------------------------------------------------------------ partes humanas
def hand(prefix, x, z, material, parent, thumb_mat=None):
    s = 1 if x > 0 else -1
    tbox(prefix + "_Hand", (x, -0.006, z - 0.03), (0.06, 0.09, 0.14), material, top=(1.0, 1.0), bottom=(0.78, 0.8),
         shift_bottom=(-s * 0.008, 0.004), bevel=0.016, parent=parent)
    tbox(prefix + "_Thumb", (x - s * 0.012, -0.052, z - 0.015), (0.026, 0.03, 0.06), thumb_mat or material,
         bottom=(0.8, 0.8), bevel=0.009, rot=(0.3, 0, -s * 0.25), parent=parent)


def face(prefix, cz, w, d, h, skin, eye, brow, parent, jaw=0.82, nose=1.0, ear=1.0, ears=True, tilt=0.0, brow_h=0.018):
    tbox(prefix + "HeadMesh", (0, 0, cz), (w, d, h), skin, bottom=(jaw, 0.9), shift_bottom=(0, -0.008),
         bevel=0.034, parent=parent)
    fy = -d / 2
    limb(prefix + "Nose", (0, fy + 0.012, cz - 0.0), (0, fy - 0.03 * nose, cz - 0.045), 0.026, 0.012, skin,
         sides=4, flat=0.8, parent=parent)
    for s, n in ((1, "L"), (-1, "R")):
        tbox(prefix + "Eye" + n, (s * w * 0.23, fy + 0.006, cz + 0.022), (0.032, 0.012, 0.02), eye, parent=parent)
        tbox(prefix + "Brow" + n, (s * w * 0.24, fy + 0.002, cz + 0.052), (0.055, 0.02, brow_h), brow,
             rot=(0, s * tilt, 0), bevel=0.004, parent=parent)
        if ears:
            tbox(prefix + "Ear" + n, (s * (w / 2 + 0.004), 0.01, cz + 0.004), (0.022, 0.05 * ear, 0.07 * ear), skin,
                 bevel=0.008, parent=parent)
    tbox(prefix + "Mouth", (0, fy + 0.008, cz - 0.075), (0.05, 0.01, 0.01), eye, parent=parent)


def boot(prefix, x, mat_boot, mat_sole, parent, top_z=0.42, cuff=None, toe=0.13):
    limb(prefix + "_Shaft", (x, 0.0, 0.08), (x, 0.0, top_z), 0.058, 0.064, mat_boot, sides=7, parent=parent)
    tbox(prefix + "_Foot", (x, -0.045, 0.055), (0.105, 0.2, 0.1), mat_boot, top=(0.85, 0.7), shift_top=(0, 0.03),
         bevel=0.022, parent=parent)
    tbox(prefix + "_Sole", (x, -0.045, 0.012), (0.115, 0.215, 0.026), mat_sole, bevel=0.006, parent=parent)
    if cuff:
        limb(prefix + "_Cuff", (x, 0.0, top_z - 0.02), (x, 0.0, top_z + 0.06), 0.074, 0.086, cuff, sides=7, parent=parent)


def pouch(name, loc, mat_bag, mat_flap, parent, size=(0.08, 0.06, 0.09), rotz=0.0):
    tbox(name, loc, size, mat_bag, bottom=(0.92, 0.9), bevel=0.014, rot=(0, 0, rotz), parent=parent)
    fl = Vector(loc) + Euler((0, 0, rotz)).to_matrix() @ Vector((0, -size[1] / 2 - 0.004, size[2] * 0.18))
    tbox(name + "Flap", fl, (size[0] * 1.04, 0.012, size[2] * 0.55), mat_flap, bevel=0.004, rot=(0, 0, rotz), parent=parent)


exec(open(OUT.replace("assets/models/", "tools/blender/head.py"), encoding="utf-8").read(), globals())
exec(open(OUT.replace("assets/models/", "tools/blender/body.py"), encoding="utf-8").read(), globals())


# ================================================================== CAVALEIRO
# Corpo-base em loft (body.py) com armadura em camadas derivada das mesmas seções.
# Peças tingidas por scripts/player/knight_look.gd (cada uma com um material só):
#   Helmet, HelmetDome | Torso, Fauld, ArmX_Pauldron | ArmX_Gauntlet, ArmX_Hand | LegX_Sabaton | Shield.
# O resto é juntado por pivô para reduzir objetos. KneeX/ElbowX ficam retos (o jogo ainda não os anima).
def band(name, s, axis, w, material, parent, sides=10, phase=0.5, arc=None, fwd=(0, -1, 0), out=0.004,
         thick=0.006):
    """Friso: faixa fina (sem tampas) logo por fora da seção s, com largura w ao longo de axis."""
    ax = Vector(axis).normalized()
    a = dict(s, rx=s["rx"] + out, ry=s["ry"] + out)
    b = dict(a, c=s["c"] + ax * w)
    return loft(name, [a, b], material, parent, sides=sides, phase=phase, axis=ax, fwd=fwd, arc=arc,
                thick=thick, caps=(False, False))


def wing(name, c, w, h, t, material, parent):
    """Asa lateral de joelheira/cotoveleira: losango vertical fino (largura w em Y, altura h, espessura t)."""
    c = Vector(c)
    return loft(name, [sec(c + Vector((0, 0.01, -h / 2)), t * 0.7, 0.008),
                       sec(c, t, w / 2),
                       sec(c + Vector((0, -0.004, h * 0.42)), t * 0.7, 0.01)],
                material, parent, sides=4, axis=(0, 0, 1))


def strap(name, p0, p1, width, material, parent, radial, t=0.005):
    """Tira de couro chata de p0 a p1; radial = direção da espessura (para fora do corpo)."""
    return loft(name, [sec(p0, width / 2, t), sec(p1, width * 0.45, t)], material, parent, sides=4,
                fwd=radial)


def build_knight():
    steel = mat("k_steel", hexc("#A9B1BE"), 0.35, 0.85)
    steel_d = mat("k_steel_dark", hexc("#5D6573"), 0.45, 0.85)
    chain = mat("k_chain", hexc("#4A4F59"), 0.6, 0.7)
    red_c = mat("k_red", hexc("#A3202A"), 0.85)
    red_dark = mat("k_red_dark", hexc("#5E1016"), 0.9)
    trim = mat("k_trim", hexc("#E6B544"), 0.35, 0.8)
    lea = mat("k_leather", hexc("#6B4423"), 0.8)
    lea_d = mat("k_leather_d", hexc("#3A2412"), 0.85)
    slit = mat("k_slit", (0.02, 0.02, 0.02), 0.9)
    bl = mat("k_blade", (0.86, 0.88, 0.92), 0.18, 1.0)

    P = body_proportions(height=1.84, heads=7.5, shoulders=1.08, waist=0.92, limbs=1.06, hands=1.15, feet=1.1)
    R = humanoid_rig("Knight", P)
    body, head = R["Body"], R["Head"]

    # ---------------- pernas
    for n, s in (("L", 1), ("R", -1)):
        S = limb_sections(P, s)
        leg, knee = R["Leg" + n], R["Knee" + n]
        K = mirror(P["knee"], s)
        th = loft("Leg%s_Thigh" % n, S["thigh"], chain, leg)
        cu = loft("Leg%s_Cuisse" % n, grow(span(S["thigh"], 0.12, 0.9), 1.12, 0.014), steel, leg, sides=6, arc=3.6,
                  thick=0.014)
        join_objs("Leg%s_Thigh" % n, [th, cu])
        pol = loft("Leg%s_Knee" % n, [sec((K.x, K.y - 0.03, K.z + 0.005), 0.07, 0.074),
                                      sec((K.x, K.y - 0.075, K.z), 0.064, 0.068),
                                      sec((K.x, K.y - 0.1, K.z - 0.006), 0.042, 0.046)],
                   steel, knee, fwd=(0, 0, 1), chamfer=(0.0, 0.008))
        sab_s = [dict(x, c=x["c"] + Vector((0, 0, 0.008))) for x in grow(S["foot"], 1.1, 0.006)]
        heel_y, toe_y = sab_s[0]["c"].y, sab_s[-1]["c"].y
        sole = tbox("Leg%s_Sole" % n, (K.x, (heel_y + toe_y) / 2 - 0.004, 0.011),
                    (0.15 * P["ft"], heel_y - toe_y + 0.05, 0.022), lea_d, bevel=0.006, parent=knee)
        kw = wing("Leg%s_KneeWing" % n, (K.x + s * 0.066, K.y - 0.035, K.z), 0.075, 0.1, 0.009, steel, knee)
        gband = band("Leg%s_GreaveTrim" % n, grow([sample(S["shin"], 0.2)], 1.13, 0.008, keel=0.12)[0],
                     S["shin"][-1]["c"] - S["shin"][0]["c"], 0.016, trim, knee, sides=8, phase=0)
        join_objs("Leg%s_Knee" % n, [pol, sole, kw, gband])
        gr = loft("Leg%s_Sabaton" % n, grow(span(S["shin"], 0.04, 0.97), 1.13, 0.008, keel=0.12), steel, knee,
                  phase=0, chamfer=(0.006, 0.0))
        sb = loft("Leg%s_Foot" % n, stepped(sab_s, (0.42, 0.58, 0.74), drop=0.92, keep_bottom=True), steel, knee,
                  fwd=(0, 0, 1), chamfer=(0.008, 0.01))
        join_objs("Leg%s_Sabaton" % n, [gr, sb])

    # ---------------- tronco: cota por baixo, couraça, plackart, faldas em lâminas, tassets, cinto
    loft("Hips", [sec((0, 0, 1.0), 0.15, 0.112), sec((0, 0, 0.86), 0.17, 0.125)], chain, body, sides=12, phase=0)
    torso = loft("Torso", [sec((0, 0, 0.98), 0.15, 0.118),
                           sec((0, 0, 1.08), 0.145, 0.112),
                           sec((0, 0, 1.2), 0.175, 0.132, fr=1.12, keel=0.03),
                           sec((0, 0, 1.31), 0.205, 0.145, fr=1.24, keel=0.07),
                           sec((0, 0, 1.4), 0.205, 0.13, fr=1.1, keel=0.03),
                           sec((0, 0, 1.455), 0.155, 0.1),
                           sec((0, 0, 1.48), 0.09, 0.075)], steel, body, sides=12, phase=0, axis=(0, 0, 1),
                 chamfer=(0.0, 0.01))
    plack = loft("Plackart", [sec((0, 0, 0.995), 0.158, 0.128, fr=1.04),
                              sec((0, 0, 1.1), 0.155, 0.125, fr=1.06),
                              sec((0, 0, 1.19), 0.182, 0.143, fr=1.13, keel=0.05)],
                 steel, body, sides=8, axis=(0, 0, 1), arc=2.5, thick=0.016)
    join_objs("Torso", [torso, plack])
    lames = []
    for i, (z0, z1, rx0, rx1, ry0, ry1) in enumerate(((1.0, 0.93, 0.158, 0.18, 0.122, 0.142),
                                                      (0.95, 0.87, 0.174, 0.2, 0.138, 0.158),
                                                      (0.89, 0.81, 0.19, 0.218, 0.152, 0.175))):
        lames.append(loft("Fauld%d" % i, [sec((0, 0, z0), rx0, ry0, fr=1.06), sec((0, 0, z1), rx1, ry1, fr=1.06)],
                          steel, body, sides=12, phase=0, axis=(0, 0, 1), chamfer=(0.0, 0.006)))
    ZUP = (0, 0, 1)
    btrim = [band("FauldTrim", sec((0, 0, 0.81), 0.218, 0.175, fr=1.06), ZUP, 0.016, trim, body, sides=12, phase=0)]
    # tassets: duas placas por coxa, a de baixo saindo por baixo da de cima, com friso na borda
    for n, s in (("L", 1), ("R", -1)):
        for i, (z0, z1, r0, r1) in enumerate(((0.86, 0.75, 0.0, 0.012), (0.77, 0.66, 0.014, 0.028))):
            lo = sec((s * (0.11 + r1), -r1, z1), 0.122 + r1, 0.16 + r1)
            lames.append(loft("Tasset%s%d" % (n, i), [sec((s * (0.105 + r0), -r0, z0), 0.122 + r0, 0.16 + r0), lo],
                              steel, body, sides=4, axis=ZUP, arc=2.0, thick=0.012))
            btrim.append(band("Tasset%s%dTrim" % (n, i), lo, ZUP, 0.014, trim, body, sides=4, arc=2.0,
                              out=0.003))
    join_objs("Fauld", lames)
    # frisos do peitoral: borda de cima do plackart e decote da couraça
    btrim.append(band("PlackTrim", sec((0, 0, 1.178), 0.182, 0.143, fr=1.13, keel=0.05), ZUP, 0.016, trim, body,
                      sides=8, arc=2.5))
    btrim.append(band("NeckTrim", sec((0, 0, 1.425), 0.18, 0.115, fr=1.05), ZUP, 0.016, trim, body, sides=12,
                      phase=0))
    belt = loft("Belt", [sec((0, 0, 1.03), 0.168, 0.13, fr=1.06), sec((0, 0, 0.982), 0.172, 0.134, fr=1.06)],
                lea, body, sides=12, phase=0, axis=ZUP)
    # fivela: aro dourado com o couro aparecendo no meio, pino, e a ponta do cinto pendurada
    bk = [tbox("Buckle", (0, -0.147, 1.006), (0.058, 0.012, 0.05), trim, bevel=0.003, parent=body),
          tbox("BuckleHole", (0, -0.153, 1.006), (0.032, 0.004, 0.026), lea_d, parent=body),
          tbox("BucklePin", (0.004, -0.157, 1.006), (0.034, 0.005, 0.006), trim, parent=body),
          strap("BeltEnd", (0.05, -0.15, 0.995), (0.062, -0.158, 0.9), 0.034, lea, body, (0.2, -1, 0))]
    # alças: tiras de couro penduradas do cinto por cima das faldas, com ponteira dourada
    for k, a in enumerate((-1.25, -0.6, 0.6, 1.25)):
        rad = Vector((math.sin(a), -math.cos(a), 0))
        p0 = Vector((math.sin(a) * 0.18, -math.cos(a) * 0.15, 0.99))
        p1 = Vector((math.sin(a) * 0.246, -math.cos(a) * 0.214, 0.77))
        bk.append(strap("Strap%d" % k, p0, p1, 0.03, lea, body, rad))
        bk.append(strap("StrapTip%d" % k, p1 + rad * 0.002, p1 + (p1 - p0).normalized() * 0.025 + rad * 0.003,
                        0.026, trim, body, rad, t=0.006))
    join_objs("Belt", [belt] + bk + btrim)
    # tabardo pendurado do cinto, inclinado para ficar por fora das faldas e dos frisos
    tbox("Tabard", (0, -0.207, 0.745), (0.15, 0.012, 0.42), red_c, bottom=(1.25, 1), bevel=0.004, rot=(-0.14, 0, 0),
         parent=body)
    loft("Gorget", [sec((0, 0, 1.43), 0.15, 0.115), sec((0, 0, 1.47), 0.11, 0.09), sec((0, 0.004, 1.52), 0.08, 0.075),
                    sec((0, 0.006, 1.55), 0.075, 0.072)], steel_d, body, sides=10, axis=(0, 0, 1),
         chamfer=(0.0, 0.006))
    cloth("Cape", 1.46, 0.3, 0.17, 0.28, 2.3, 2.9, [red_c, red_dark],
          [(0.25, 0), (0.5, 0), (0.75, 0), (0.92, 0), (1.0, 1)], center=(0, 0.035), back=1.0, cols=8,
          folds=0.025, thick=0.016, border=0.07, border_mat=1, parent=body)

    # ---------------- cabeça: elmo fechado facetado (vértice na frente para a quilha) com
    # bevor em prova (duas placas em degrau), fenda dos olhos sob a testa saliente, crista central na calota
    # e penacho em leque. Helmet e HelmetDome levam um material só (tingidos pelo equipamento);
    # frisos, fenda e penacho ficam em objetos à parte.
    hy = 0.005
    helm = loft("Helmet", [sec((0, hy, 1.5), 0.085, 0.088),
                           sec((0, hy, 1.56), 0.108, 0.118, fr=1.06),
                           sec((0, hy, 1.64), 0.118, 0.13, fr=1.05, keel=0.05),
                           sec((0, hy, 1.72), 0.122, 0.132),
                           sec((0, hy, 1.75), 0.122, 0.132)], steel, head, sides=12, phase=0, axis=(0, 0, 1))
    BEV = [sec((0, hy, 1.522), 0.1, 0.112, fr=1.1, keel=0.2),
           sec((0, hy, 1.575), 0.118, 0.13, fr=1.14, keel=0.24),
           sec((0, hy, 1.622), 0.123, 0.136, fr=1.14, keel=0.2)]
    BEV2 = [sec((0, hy, 1.612), 0.12, 0.134, fr=1.15, keel=0.24),
            sec((0, hy, 1.646), 0.126, 0.14, fr=1.16, keel=0.2),
            sec((0, hy, 1.668), 0.127, 0.14, fr=1.15, keel=0.15)]
    BROW = [sec((0, hy, 1.69), 0.127, 0.139, fr=1.13, keel=0.12),
            sec((0, hy, 1.705), 0.131, 0.143, fr=1.15, keel=0.12),
            sec((0, hy, 1.742), 0.131, 0.142, fr=1.08, keel=0.05)]
    bev = loft("Bevor", BEV, steel, head, sides=12, phase=0, axis=(0, 0, 1), arc=3.0, thick=0.014,
               chamfer=(0.004, 0.0))
    bev2 = loft("Visor", BEV2, steel, head, sides=12, phase=0, axis=(0, 0, 1), arc=2.6, thick=0.014)
    brow = loft("VisorBrow", BROW, steel, head, sides=12, phase=0, axis=(0, 0, 1), arc=2.5, thick=0.016)
    join_objs("Helmet", [helm, bev, bev2, brow])
    DOME = [sec((0, hy, 1.735), 0.13, 0.14),
            sec((0, hy, 1.765), 0.13, 0.14),
            sec((0, hy, 1.81), 0.115, 0.126, keel=0.05),
            sec((0, hy, 1.85), 0.076, 0.086),
            sec((0, hy, 1.872), 0.03, 0.035)]
    dome_m = loft("HelmetDome", DOME, steel, head, sides=12, phase=0, axis=(0, 0, 1), chamfer=(0.006, 0.0))
    # crista: aleta de seção em losango sobre o meio da calota, da testa à nuca
    prof = [(-0.15, 1.738), (-0.143, 1.79), (-0.112, 1.838), (-0.06, 1.87), (0.0, 1.882), (0.06, 1.87),
            (0.098, 1.84), (0.13, 1.79), (0.142, 1.745)]
    crest = loft("Crest", [sec((0, y + hy, z), 0.02 if abs(y) < 0.13 else 0.012, 0.011) for y, z in prof],
                 steel, head, sides=4, phase=0, fwd=(1, 0, 0))
    join_objs("HelmetDome", [dome_m, crest])

    # fenda dos olhos (fundo escuro entre o visor e a testa) e respiros no lado direito do bevor
    slit_o = [loft("VisorSlit", [sec((0, hy, 1.664), 0.121, 0.133, fr=1.13, keel=0.15),
                                 sec((0, hy, 1.696), 0.121, 0.133, fr=1.12, keel=0.12)],
                   slit, head, sides=12, phase=0, axis=(0, 0, 1), arc=2.2, thick=0.01)]
    for k in range(4):
        a = -0.62 - k * 0.15
        rr = 0.141 * 1.14
        x, y = 0.125 * math.sin(a) * 1.0, hy - rr * math.cos(a) * 0.98
        slit_o.append(tbox("Breath%d" % k, (x, y, 1.6 - k * 0.004), (0.008, 0.012, 0.036 - k * 0.004), slit,
                           rot=(0, 0, a), parent=head))
    join_objs("VisorSlit", slit_o)

    # frisos dourados: aba da calota, borda de baixo da testa e risca vertical do bevor (forma um T)
    def front_y(sc):
        return sc["c"].y - sc["ry"] * sc["fr"] * (1 + sc["keel"])
    vt_secs = [sec((0, front_y(sc) - 0.003, sc["c"].z), 0.006, 0.006) for sc in (BEV2[-1], BEV2[0], BEV[2], BEV[1])]
    vt_secs.append(sec((0, front_y(BEV[0]) + 0.004, BEV[0]["c"].z + 0.006), 0.005, 0.005))
    trims = [band("HelmetTrim", DOME[0], (0, 0, 1), 0.016, trim, head, sides=12, phase=0),
             band("BrowTrim", dict(BROW[0], c=BROW[0]["c"] + Vector((0, 0, 0.001))), (0, 0, 1), 0.012, trim, head,
                  sides=12, phase=0, arc=2.5, out=0.003),
             loft("VisorTrim", vt_secs, trim, head, sides=4, phase=0, fwd=(1, 0, 0))]
    join_objs("HelmetTrim", trims)

    # penacho: cinco lâminas facetadas em leque saindo de um tubo dourado no alto da nuca
    sock = Vector((0, hy + 0.05, 1.862))
    blades = [limb("PlumeSocket", sock + Vector((0, -0.012, -0.03)), sock + Vector((0, 0.012, 0.022)), 0.02, 0.016,
                   trim, sides=6, parent=head)]
    # cada lâmina sobe e curva para trás (b = para trás, u = para cima, no plano girado por yaw)
    path = ((0.0, 0.015), (0.0, 0.08), (0.03, 0.15), (0.09, 0.2), (0.16, 0.218), (0.23, 0.205), (0.29, 0.165))
    widths = (0.02, 0.042, 0.054, 0.052, 0.044, 0.03, 0.004)
    for k, (yaw, sc, m) in enumerate(((0.0, 1.0, red_c), (0.17, 0.88, red_dark), (-0.17, 0.88, red_dark),
                                      (0.34, 0.74, red_c), (-0.34, 0.74, red_c))):
        back = Vector((math.sin(yaw), math.cos(yaw), 0))
        nrm = Vector((math.cos(yaw), -math.sin(yaw), 0))     # normal do plano da lâmina
        pts = [sock + back * (bb * sc) + Vector((0, 0, uu * (0.55 + 0.45 * sc))) for bb, uu in path]
        blades.append(loft("PlumeBlade%d" % k, [sec(p, w * (0.6 + 0.4 * sc), 0.01) for p, w in zip(pts, widths)],
                           m, head, sides=4, phase=0, fwd=nrm))
    join_objs("Plume", blades)

    # ---------------- braços
    for n, s in (("R", -1), ("L", 1)):
        S = limb_sections(P, s)
        arm, elbow = R["Arm" + n], R["Elbow" + n]
        U = S["upper"]
        up = loft("Arm%s_Upper" % n, U, chain, arm)
        sh = mirror(P["shoulder"], s)
        tilt = Vector((s * math.sin(0.75), 0, math.cos(0.75)))
        down = (U[-1]["c"] - U[0]["c"]).normalized()
        pbase = sh + Vector((s * 0.012, 0, -0.002))
        pl = [dome("Arm%s_Pauldron" % n, pbase, tilt, 0.158, 0.148, 0.088, steel, arm, sides=10, lip=0.025)]
        atrim = [band("Arm%s_PauldronTrim" % n, sec(pbase - tilt * 0.014, 0.158, 0.148), tilt, 0.016, trim, arm)]
        # três lâminas em degrau sob a calota: cada uma termina mais larga que o início da de baixo
        for i, (t0, t1, a0, a1) in enumerate(((0.12, 0.3, 0.104, 0.114), (0.27, 0.45, 0.097, 0.107),
                                              (0.42, 0.6, 0.09, 0.1))):
            c0, c1 = sample(U, t0), sample(U, t1)
            lo = sec(c1["c"] + Vector((s * 0.006, 0, 0)), a1, a1 + 0.01)
            pl.append(loft("Arm%s_Lame%d" % (n, i), [sec(c0["c"], a0, a0 + 0.01), lo],
                           steel, arm, sides=10, chamfer=(0.0, 0.006)))
            if i == 2:
                atrim.append(band("Arm%s_LameTrim" % n, lo, -down, 0.014, trim, arm, out=0.003))
        pl.append(loft("Arm%s_Rerebrace" % n, grow(span(U, 0.56, 0.93), 1.14, 0.008), steel, arm,
                       chamfer=(0.0, 0.006)))
        join_objs("Arm%s_Pauldron" % n, pl)
        join_objs("Arm%s_Upper" % n, [up] + atrim)
        E = mirror(P["elbow"], s)
        F = S["fore"]
        fdown = (F[-1]["c"] - F[0]["c"]).normalized()
        cop = dome("Arm%s_Couter" % n, E + Vector((0, 0.012, 0)), (s * 0.35, 1, 0), 0.056, 0.06, 0.05, steel, elbow,
                   fwd=(0, 0, 1))
        ew = wing("Arm%s_CouterWing" % n, E + Vector((s * 0.056, 0.012, 0)), 0.07, 0.09, 0.008, steel, elbow)
        vb = loft("Arm%s_Vambrace" % n, grow(span(F, 0.1, 0.92), 1.16, 0.006), steel, elbow,
                  chamfer=(0.006, 0.006))
        vtop = grow([sample(F, 0.12)], 1.16, 0.006)[0]
        vt = band("Arm%s_VambraceTrim" % n, vtop, fdown, 0.014, trim, elbow, sides=8, out=0.003)
        cuff0 = sample(F, 0.68)
        gt = band("Arm%s_CuffTrim" % n, sec(cuff0["c"], 0.05, 0.056), fdown, 0.012, trim, elbow, sides=8,
                  out=0.004)
        join_objs("Arm%s_Vambrace" % n, [vb, cop, ew, vt, gt])
        W = mirror(P["wrist"], s)
        loft("Arm%s_Gauntlet" % n, [sec(cuff0["c"], 0.05, 0.056), sec(W + Vector((0, 0, -0.018)), 0.058, 0.066)],
             steel_d, elbow, sides=8, chamfer=(0.0, 0.006))
        fist("Arm" + n, P, s, steel_d, elbow)

    # ---------------- espada (mão direita, apontando para frente) — o jogo usa Grip como ponto da mão
    arm_r = R["ArmR"]
    W = mirror(P["wrist"], -1)
    hx, hz = W.x + 0.004, W.z - 0.064 * P["hd"]
    limb("Grip", (hx, 0.07, hz), (hx, -0.07, hz), 0.017, 0.017, lea, sides=6, parent=arm_r)
    sw = [shell("Pommel", (hx, 0.09, hz), (0.05, 0.05, 0.05), trim, cut=-1.0, thick=0, parent=arm_r),
          tbox("Guard", (hx, -0.085, hz), (0.03, 0.03, 0.24), trim, top=(0.7, 0.7), bottom=(0.7, 0.7), bevel=0.006,
               parent=arm_r),
          tbox("Blade", (hx, -0.53, hz), (0.012, 0.86, 0.052), bl, bevel=0.003, parent=arm_r),
          limb("BladeTip", (hx, -0.96, hz), (hx, -1.06, hz), 0.026, 0.0, bl, sides=4, flat=0.25, twist=PI / 4,
               parent=arm_r)]
    join_objs("Blade", [sw[2], sw[0], sw[1], sw[3]])
    # escudo (antebraço esquerdo), face externa em +X
    el_l = R["ElbowL"]
    sxp, sz = 0.35, 1.03
    rim = [tbox("ShieldRim", (sxp - 0.004, 0, sz), (0.03, 0.42, 0.52), steel_d, bottom=(1, 0.22), bevel=0.01,
                parent=el_l),
           tbox("ShieldCrossV", (sxp + 0.024, 0, sz + 0.02), (0.01, 0.045, 0.36), trim, parent=el_l),
           tbox("ShieldCrossH", (sxp + 0.024, 0, sz + 0.1), (0.01, 0.26, 0.045), trim, parent=el_l),
           shell("ShieldBoss", (sxp + 0.03, 0, sz + 0.1), (0.07, 0.07, 0.07), trim, cut=-0.2, rot=(0, PI / 2, 0),
                 parent=el_l)]
    join_objs("ShieldRim", rim)
    tbox("Shield", (sxp + 0.008, 0, sz + 0.005), (0.026, 0.38, 0.48), red_c, bottom=(1, 0.2), bevel=0.008,
         parent=el_l)
    # sombra assada nas dobras (gear.py): mesma leitura das roupas modulares
    bake_ao([o for o in scn.objects if o.type == 'MESH'], [])
    export("knight", export_vertex_color='ACTIVE')


# ================================================================== ANCIÃO (NPC)
def build_elder():
    robe = mat("e_robe", (0.08, 0.2, 0.32), 0.95)
    robe_l = mat("e_robe_light", (0.12, 0.3, 0.42), 0.95)
    mantle = mat("e_mantle", (0.55, 0.42, 0.25), 0.95)
    mantle_d = mat("e_mantle_d", (0.38, 0.27, 0.15), 0.95)
    trim = mat("e_trim", (0.85, 0.72, 0.4), 0.5, 0.6)
    skin = mat("e_skin", (0.78, 0.55, 0.42), 0.8)
    hair = mat("e_hair", (0.9, 0.9, 0.88), 0.9)
    eye = mat("e_eye", (0.05, 0.04, 0.04), 0.5)
    rope = mat("e_rope", (0.7, 0.6, 0.4), 0.95)
    lea = mat("e_leather", (0.3, 0.18, 0.1), 0.85)
    wood = mat("e_wood", (0.36, 0.22, 0.12), 0.9)
    gem = mat("e_gem", (0.3, 0.75, 1.0), 0.2, 0, emit=(0.3, 0.7, 1.0), strength=6)

    root = empty("Villager", (0, 0, 0))
    for s, x in ((1, 0.08), (-1, -0.08)):
        tbox("Shoe" + ("L" if s > 0 else "R"), (x, -0.07, 0.04), (0.1, 0.2, 0.08), lea, top=(0.85, 0.75),
             shift_top=(0, 0.02), bevel=0.02, parent=root)
    body = empty("Body", (0, 0, 0.95), root)
    drape("RobeSkirt", 1.02, 0.05, 0.17, 0.29, 2 * PI, 2 * PI, robe, rows=5, cols=14, folds=0.018, thick=0.02, parent=body)
    tbox("RobePanel", (0, -0.2, 0.55), (0.12, 0.02, 0.92), robe_l, top=(0.6, 1), shift_top=(0, 0.07), bevel=0.004,
         rot=(0.07, 0, 0), parent=body)
    ring("RobeHem", 0.07, 0.3, 0.035, trim, parent=body, sides=14)
    tbox("Chest", (0, 0, 1.22), (0.32, 0.2, 0.42), robe, top=(1.12, 1.05), bottom=(0.95, 0.95), bevel=0.04, parent=body)
    tbox("Collar", (0, -0.085, 1.36), (0.14, 0.05, 0.14), robe_l, bottom=(0.3, 1), bevel=0.01, parent=body)
    # manto sobre os ombros e capuz caído
    shell("Mantle", (0, 0, 1.3), (0.5, 0.34, 0.36), mantle, cut=-0.15, seg=12, rings=8, thick=0.02, parent=body)
    ring("MantleTrim", 1.27, 0.25, 0.03, trim, parent=body, sides=12, flat=0.68)
    shell("Hood", (0, 0.11, 1.47), (0.3, 0.2, 0.22), mantle_d, cut=-0.5, rot=(0.9, 0, 0), jitter=0.006, parent=body)
    # cinto de corda, bolsa, estojo de pergaminho, pingente
    ring("RopeBelt", 1.01, 0.178, 0.03, rope, parent=body, sides=12)
    limb("RopeEnd1", (0.06, -0.17, 1.0), (0.08, -0.19, 0.72), 0.012, 0.01, rope, sides=4, parent=body)
    limb("RopeEnd2", (0.09, -0.16, 1.0), (0.12, -0.18, 0.78), 0.012, 0.01, rope, sides=4, parent=body)
    tbox("Tassel1", (0.08, -0.19, 0.7), (0.03, 0.03, 0.05), trim, bottom=(1.5, 1.5), parent=body)
    pouch("Pouch", (-0.16, -0.09, 0.93), lea, lea, body, size=(0.08, 0.06, 0.1), rotz=-0.5)
    limb("ScrollCase", (0.19, 0.06, 1.06), (0.21, 0.08, 0.78), 0.035, 0.035, lea, sides=7, parent=body)
    limb("ScrollCap", (0.21, 0.08, 0.79), (0.212, 0.082, 0.76), 0.04, 0.04, trim, sides=7, parent=body)
    limb("Necklace", (0, -0.1, 1.38), (0, -0.125, 1.26), 0.006, 0.006, rope, sides=4, parent=body)
    shell("Pendant", (0, -0.13, 1.24), (0.045, 0.02, 0.06), gem, cut=-1.0, thick=0, parent=body)
    # cabeça
    head = empty("Head", (0, 0, 1.45), body)
    limb("Neck", (0, 0.005, 1.4), (0, 0.012, 1.6), 0.056, 0.052, skin, sides=7, parent=head)
    face_mats = {"skin": skin, "lip": mat("e_lip", (0.62, 0.38, 0.34), 0.7), "sclera": mat("e_sclera", (0.88, 0.86, 0.8), 0.4),
                 "iris": mat("e_iris", (0.32, 0.42, 0.52), 0.3), "pupil": mat("e_pupil", (0.03, 0.03, 0.03), 0.2),
                 "brow": hair, "lash": mat("e_lash", (0.2, 0.16, 0.14), 0.9)}
    H = human_head("", 1.505, 0.235, head, face_mats,
                   {"age": 1.0, "nose": 1.15, "eye_depth": 1.25, "cheek": 1.1, "lips": 0.9})
    # cabelo: base escura colada ao crânio + mechas facetadas penteadas para trás, caindo até a nuca
    hair_d = mat("e_hair_d", (0.42, 0.42, 0.45), 0.9)
    shell("HairBase", (0, 0.004, 1.628), (0.152, 0.2, 0.226), hair_d, cut=0.22, seg=10, rings=6, rot=(-0.35, 0, 0),
          thick=0.008, parent=head)
    shell("HairBaseBack", (0, 0.006, 1.6), (0.158, 0.28, 0.204), hair_d, cut=0.05, seg=10, rings=6, rot=(-PI / 2, 0, 0),
          thick=0.008, parent=head)
    locks = []
    for phi, drop in ((-58, 0.07), (-35, 0.09), (-12, 0.08), (12, 0.095), (35, 0.075), (58, 0.088)):  # topo, para trás
        locks.append(dict(a=(phi, 31), b=(180 - phi * 0.5, 4), drop=drop, w=0.06, t=0.012, bulge=0.006))
    for sg in (1, -1):
        locks.append(dict(a=(sg * 72, 23), b=(sg * 138, 0), drop=0.08, w=0.056, t=0.012, bulge=0.005))   # têmporas
        locks.append(dict(a=(sg * 92, 22), b=(sg * 118, -6), drop=0.088, w=0.05, t=0.011, flare=0.01))   # sobre a orelha
    for phi in (148, 180, -148):                                                              # nuca
        locks.append(dict(a=(phi, 55), b=(phi, -6), drop=0.1, w=0.062, t=0.012, bulge=0.006))
    hair_locks("Hair", H, locks, hair, head)
    # barba: cunha facetada cobrindo a mandíbula até o peito, bigode caído
    for sg, n in ((1, "L"), (-1, "R")):
        limb("Mustache" + n, (sg * 0.004, H["mouth_y"] - 0.004, H["nose_base_z"] - 0.006),
             (sg * 0.031, H["mouth_y"] + 0.008, H["mouth_z"] - 0.016), 0.0075, 0.0035, hair, sides=5, flat=0.7, parent=head)
    limb("Beard", (0, -0.036, H["mouth_z"] - 0.004), (0, -0.105, 1.34), 0.075, 0.012, hair, sides=7, flat=0.78,
         twist=PI / 7, jitter=0.003, seed=9, parent=head)
    limb("BeardTip", (0.012, -0.1, 1.38), (0.026, -0.112, 1.31), 0.018, 0.004, hair, sides=4, flat=0.7, parent=head)
    # braços com mangas largas
    for side, sx in (("ArmR", -0.2), ("ArmL", 0.2)):
        s = 1 if sx > 0 else -1
        arm = empty(side, (sx, 0, 1.4), body)
        shell(side + "_Shoulder", (sx, 0, 1.4), (0.16, 0.17, 0.14), robe, cut=-0.2, thick=0, parent=arm)
        limb(side + "_Upper", (sx, 0, 1.42), (sx + s * 0.03, 0.01, 1.15), 0.065, 0.075, robe, sides=7, parent=arm)
        limb(side + "_Sleeve", (sx + s * 0.03, 0.01, 1.16), (sx + s * 0.045, -0.01, 0.94), 0.08, 0.12, robe, sides=8, parent=arm)
        ring(side + "_Cuff", 0.95, 0.122, 0.035, trim, parent=arm, sides=8, x=sx + s * 0.045, y=-0.01)
        limb(side + "_Wrist", (sx + s * 0.045, -0.01, 0.98), (sx + s * 0.045, -0.01, 0.9), 0.035, 0.032, skin, sides=6, parent=arm)
        hand(side, sx + s * 0.045, 0.86, skin, arm)
    arm_l = bpy.data.objects["ArmL"]
    limb("Staff", (0.25, -0.07, 0.02), (0.25, -0.07, 1.82), 0.022, 0.026, wood, sides=6, twist=0.6, parent=arm_l)
    limb("StaffWrap", (0.25, -0.07, 1.0), (0.25, -0.07, 1.12), 0.03, 0.03, lea, sides=6, parent=arm_l)
    limb("StaffCrook1", (0.25, -0.07, 1.82), (0.29, -0.07, 1.94), 0.026, 0.02, wood, sides=6, parent=arm_l)
    limb("StaffCrook2", (0.29, -0.07, 1.94), (0.22, -0.07, 2.0), 0.02, 0.016, wood, sides=6, parent=arm_l)
    shell("StaffGem", (0.255, -0.07, 1.93), (0.075, 0.075, 0.1), gem, cut=-1.0, thick=0, seg=6, rings=4, parent=arm_l)
    export("elder")


# ================================================================== MERCADORA (NPC)
# Segue docs/PROMPT_LOWPOLY.md: camadas corpo -> túnica -> faixa/cinto -> mantelete -> capa,
# barra em toda borda de tecido, 3 tons por material, 60% roxo / 30% ocre e couro / 10% laranja, azul e ouro.
def build_merchant():
    pur = mat("m_purple", hexc("#7A3E9E"), 0.95)
    pur_d = mat("m_purple_d", hexc("#4A2269"), 0.95)
    pur_l = mat("m_purple_l", hexc("#B07FD0"), 0.95)
    ochre = mat("m_ochre", hexc("#B98A3C"), 0.95)
    ochre_d = mat("m_ochre_d", hexc("#5E3D1F"), 0.95)
    ochre_l = mat("m_ochre_l", hexc("#D9B366"), 0.95)
    blue = mat("m_blue", hexc("#2E6DB4"), 0.9)
    blue_d = mat("m_blue_d", hexc("#1F4A80"), 0.9)
    orange = mat("m_orange", hexc("#CC6A22"), 0.9)
    orange_d = mat("m_orange_d", hexc("#964516"), 0.9)
    lea = mat("m_lea", hexc("#7A4B2A"), 0.85)
    lea_d = mat("m_lea_d", hexc("#472A17"), 0.85)
    sole = mat("m_sole", hexc("#2A1B12"), 0.9)
    gold_m = mat("m_gold", hexc("#E6B544"), 0.35, 0.8)
    silver = mat("m_silver", hexc("#C9CED6"), 0.35, 0.8)
    skin = mat("m_skin", hexc("#E3A47E"), 0.8)
    hair = mat("m_hair", hexc("#4A2A18"), 0.9)
    eye = mat("m_eye", hexc("#1E1512"), 0.5)
    lips = mat("m_lips", hexc("#B8605A"), 0.7)

    root = empty("Villager", (0, 0, 0))
    # ---------------- pernas: calça escura + bota de cano alto com punho
    for side, x in (("LegL", 0.09), ("LegR", -0.09)):
        leg = empty(side, (x, 0, 0.93), root)
        limb(side + "_Thigh", (x, 0, 0.94), (x, 0, 0.5), 0.08, 0.062, pur_d, sides=6, parent=leg)
        boot(side, x, lea, sole, leg, top_z=0.4, cuff=lea_d)
        ring(side + "_CuffTrim", 0.452, 0.092, 0.022, ochre_l, parent=leg, sides=7, x=x)
        ring(side + "_AnkleStrap", 0.17, 0.066, 0.028, lea_d, parent=leg, sides=7, x=x)
        tbox(side + "_AnkleBuckle", (x, -0.066, 0.17), (0.026, 0.012, 0.026), silver, bevel=0.003, parent=leg)
        tbox(side + "_ToeCap", (x, -0.125, 0.05), (0.1, 0.06, 0.07), lea_d, top=(0.85, 0.8), bevel=0.014, parent=leg)

    body = empty("Body", (0, 0, 0.93), root)
    # ---------------- túnica com barra dupla
    cloth("TunicSkirt", 1.0, 0.5, 0.15, 0.26, 2 * PI, 2 * PI, [pur, pur_l, pur_d],
          [(0.4, 0), (0.74, 0), (0.82, 1), (0.92, 0), (1.0, 2)], back=0.8, cols=12, folds=0.014, thick=0.018, parent=body)
    tbox("Chest", (0, 0, 1.2), (0.3, 0.19, 0.4), pur, top=(1.02, 1.0), bottom=(0.92, 0.95), bevel=0.035, parent=body)
    # painel frontal azul com debrum claro e tachas
    tbox("Placket", (0, -0.1, 1.17), (0.085, 0.014, 0.3), blue, bevel=0.003, parent=body)
    for s, n in ((1, "L"), (-1, "R")):
        tbox("PlacketTrim" + n, (s * 0.05, -0.1, 1.17), (0.016, 0.018, 0.3), pur_l, parent=body)
    for k in range(4):
        tbox("Stud%d" % k, (0, -0.108, 1.06 + k * 0.06), (0.02, 0.01, 0.02), silver, rot=(0, PI / 4, 0), parent=body)
    # faixa laranja larga + cinto de couro por cima
    tbox("Sash", (0, 0, 1.0), (0.335, 0.25, 0.1), orange, top=(0.97, 0.97), bottom=(1.0, 1.0), bevel=0.014, parent=body)
    tbox("Belt", (0, 0, 1.005), (0.347, 0.262, 0.036), lea_d, bevel=0.008, parent=body)
    tbox("Buckle", (-0.02, -0.134, 1.005), (0.06, 0.014, 0.052), gold_m, bevel=0.005, parent=body)
    tbox("SashKnot", (0.09, -0.135, 0.985), (0.062, 0.04, 0.07), orange_d, bevel=0.012, parent=body)
    tbox("SashTail1", (0.085, -0.152, 0.84), (0.052, 0.014, 0.26), orange, bottom=(1.25, 1), rot=(-0.12, 0, 0.05), parent=body)
    tbox("SashTail2", (0.118, -0.146, 0.875), (0.045, 0.014, 0.19), orange_d, bottom=(1.2, 1), rot=(-0.12, 0, -0.12), parent=body)
    tbox("SashTassel", (0.079, -0.169, 0.7), (0.068, 0.016, 0.03), gold_m, parent=body)
    # bolsas (assimetria): moedas à esquerda, alça cruzada + sacola à direita
    pouch("CoinPurse", (0.175, -0.05, 0.925), ochre_l, lea_d, body, size=(0.06, 0.05, 0.075), rotz=0.95)
    tbox("Strap", (-0.02, -0.115, 1.13), (0.036, 0.012, 0.4), lea_d, rot=(0, 0.78, 0), parent=body)
    pouch("Satchel", (-0.125, -0.138, 0.9), lea, lea_d, body, size=(0.13, 0.055, 0.13), rotz=-0.3)
    tbox("SatchelClasp", (-0.134, -0.172, 0.905), (0.022, 0.01, 0.03), gold_m, rot=(0, 0, -0.3), parent=body)
    # ---------------- mantelete nos ombros, capuz caído e capa longa
    cloth("Capelet", 1.475, 1.24, 0.11, 0.32, 2 * PI, 2 * PI, [ochre, ochre_d, ochre_l],
          [(0.14, 2), (0.42, 0), (0.74, 0), (1.0, 1)], center=(0, 0.01), back=0.7, cols=12, folds=0.008,
          thick=0.018, flare=0.4, parent=body)
    tbox("Brooch", (0, -0.16, 1.412), (0.04, 0.02, 0.04), gold_m, rot=(0, PI / 4, 0), bevel=0.004, parent=body)
    shell("Hood", (0, 0.125, 1.43), (0.3, 0.2, 0.2), ochre, cut=-0.5, seg=8, rings=6, rot=(0.9, 0, 0), jitter=0.006, parent=body)
    cloth("Cloak", 1.37, 0.07, 0.15, 0.34, 2.3, 2.6, [ochre, ochre_d],
          [(0.25, 0), (0.5, 0), (0.75, 0), (0.95, 0), (1.0, 1)], center=(0, 0.03), back=0.8, cols=8, folds=0.028,
          thick=0.018, border=0.07, border_mat=1, flare=0.8, parent=body)

    # ---------------- cabeça com turbante
    head = empty("Head", (0, 0, 1.45), body)
    limb("Neck", (0, 0.008, 1.4), (0, 0.014, 1.6), 0.046, 0.043, skin, sides=7, parent=head)
    face_mats = {"skin": skin, "lip": lips, "sclera": mat("m_sclera", hexc("#EFE8DE"), 0.4),
                 "iris": mat("m_iris", hexc("#5A3A1E"), 0.3), "pupil": mat("m_pupil", hexc("#2A1810"), 0.6),
                 "mouth": mat("m_mouth", hexc("#A0594A"), 0.8),
                 "brow": hair, "lash": eye}
    HH = 0.232                                   # 7,5 cabeças: legível como personagem estilizado
    H = human_head("", 1.52, HH, head, face_mats,
                   {"fem": 1.0, "nose": 0.8, "nose_w": 0.9, "brow": 0.6, "jaw": 0.95, "chin": 0.8, "eye_size": 1.1,
                    "width": 1.0, "lips": 1.1})
    k = HH / 23.0                                # 1 cm do modelo anatômico -> metros
    # cabelo: base escura + mechas facetadas que saem de baixo do turbante e se juntam no coque baixo
    hair_d = mat("m_hair_d", hexc("#2B170C"), 0.9)
    shell("HairBase", (0, 0.006, 1.62), (0.152, 0.25, 0.2), hair_d, cut=0.15, seg=10, rings=6, rot=(-PI / 2, 0, 0),
          thick=0.008, parent=head)
    locks = []
    for phi in (110, 135, 158, 180, -158, -135, -110):
        sg = 1 if phi > 0 else -1
        pb = 180 if phi == 180 else sg * (180 - (180 - abs(phi)) * 0.3)
        locks.append(dict(a=(phi, 27), b=(pb, -35), w=0.042, t=0.011, bulge=0.007, n=4))
    for sg in (1, -1):
        locks.append(dict(a=(sg * 68, 25), b=(sg * 92, -10), drop=0.02, w=0.03, t=0.009, bulge=0.004, n=4))
    hair_locks("Hair", H, locks, hair, head)
    shell("HairBun", (0, 0.105, 1.56), (0.085, 0.07, 0.075), hair, cut=-1.0, thick=0, seg=8, rings=6, jitter=0.003,
          seed=14, parent=head)
    ring("HairTie", 1.56, 0.03, 0.022, gold_m, parent=head, sides=8, y=0.075, flat=0.6)
    for sg, n in ((1, "L"), (-1, "R")):
        shell("Earring" + n, (sg * 0.077, 0.012, 1.575), (0.02, 0.02, 0.028), gold_m, cut=-1, thick=0, seg=6, rings=4,
              parent=head)
    # turbante justo no crânio (só ~1,5 cm maior que a cabeça), cobrindo a linha do cabelo
    limb("TurbanBase", (0, 0.004, 1.69), (0, 0.004, 1.75), 0.081, 0.085, pur, sides=10, flat=1.24, parent=head)
    limb("TurbanWrap1", (0.012, 0.004, 1.702), (-0.012, 0.004, 1.758), 0.089, 0.088, pur_l, sides=10, flat=1.2, parent=head)
    limb("TurbanWrap2", (-0.014, 0.004, 1.752), (0.014, 0.004, 1.79), 0.086, 0.074, pur_d, sides=10, flat=1.2, parent=head)
    shell("TurbanTop", (0, 0.004, 1.768), (0.178, 0.214, 0.13), pur, cut=0.0, seg=10, rings=6, thick=0, jitter=0.003, seed=12,
          parent=head)
    tbox("TurbanGem", (0, -0.112, 1.725), (0.03, 0.016, 0.04), gold_m, top=(0.6, 1), bottom=(0.6, 1), bevel=0.005,
         parent=head)
    tbox("TurbanTail", (0.02, 0.108, 1.64), (0.055, 0.018, 0.15), pur_l, bottom=(0.7, 1), rot=(0.15, 0, 0.1), bevel=0.005,
         parent=head)

    scale_group(head, (0, 0.01, 1.52), 1.1)      # cabeça a ~7 alturas do corpo (guia de estilo)

    # ---------------- braços: manga curta com barra dupla, manga azul por baixo, braçadeira de couro
    for side, sx in (("ArmR", -0.2), ("ArmL", 0.2)):
        s = 1 if sx > 0 else -1
        arm = empty(side, (sx, 0, 1.4), body)
        ex = sx + s * 0.028
        wx = sx + s * 0.04
        limb(side + "_Upper", (sx, 0, 1.37), (ex, 0.01, 1.2), 0.042, 0.076, pur, sides=7, parent=arm)
        ring(side + "_SleeveTrimB", 1.232, 0.08, 0.02, pur_d, parent=arm, sides=7, x=ex, y=0.01)
        ring(side + "_SleeveTrimA", 1.203, 0.083, 0.03, pur_l, parent=arm, sides=7, x=ex, y=0.01)
        limb(side + "_Fore", (ex, 0.01, 1.21), (wx, 0, 0.93), 0.05, 0.04, blue, sides=6, parent=arm)
        limb(side + "_Bracer", (sx + s * 0.034, 0.005, 1.06), (wx, 0, 0.94), 0.055, 0.047, lea, sides=7, parent=arm)
        ring(side + "_BracerTop", 1.058, 0.059, 0.022, lea_d, parent=arm, sides=7, x=sx + s * 0.034, y=0.005)
        ring(side + "_BracerBot", 0.947, 0.051, 0.02, lea_d, parent=arm, sides=7, x=wx)
        hand(side, wx, 0.875, skin, arm)
    export("merchant")


# ================================================================== GOBLIN
# Segue docs/PROMPT_LOWPOLY.md: rosto "desenhado" (mesma cabeça facetada com proporções de goblin),
# 3 tons por material, barra em todo tecido, cabelo em mechas. Pivôs: LegL/LegR, Body, Head, ArmL/ArmR; Crown só no chefe.
def build_goblin():
    gskin = mat("g_skin", hexc("#5E8C2E"), 0.85)
    gskin_d = mat("g_skin_d", hexc("#3F6620"), 0.85)
    gskin_l = mat("g_skin_l", hexc("#86B04A"), 0.85)
    cloth_m = mat("g_cloth", hexc("#7A5A34"), 0.95)
    cloth_d = mat("g_cloth_d", hexc("#4F3820"), 0.95)
    cloth_l = mat("g_cloth_l", hexc("#A07C4C"), 0.95)
    lea = mat("g_leather", hexc("#5A3A20"), 0.85)
    lea_d = mat("g_leather_d", hexc("#37220F"), 0.85)
    bone = mat("g_bone", hexc("#E6DCC0"), 0.7)
    eye = mat("g_eye", (1.0, 0.75, 0.05), 0.4, 0.0, emit=(1.0, 0.6, 0.0), strength=3.5)
    dark = mat("g_dark", hexc("#1A120E"), 0.6)
    hair = mat("g_hair", hexc("#2A2018"), 0.9)
    wood = mat("g_wood", hexc("#6B4423"), 0.9)
    wood_d = mat("g_wood_d", hexc("#40280F"), 0.9)
    iron = mat("g_iron", hexc("#7A7D86"), 0.45, 0.8)
    goldm = mat("g_gold", hexc("#E6B544"), 0.35, 0.8)
    ruby = mat("g_ruby", (0.7, 0.02, 0.05), 0.2, 0.0, emit=(0.6, 0.0, 0.05), strength=1.5)

    root = empty("Goblin", (0, 0, 0))
    # ---------------- pernas arqueadas com faixas
    for side, x in (("LegL", 0.1), ("LegR", -0.1)):
        s = 1 if x > 0 else -1
        leg = empty(side, (x, 0, 0.55), root)
        knee = (x + s * 0.025, -0.045, 0.31)
        limb(side + "_Thigh", (x, 0, 0.56), knee, 0.068, 0.05, gskin, sides=6, parent=leg)
        limb(side + "_Shin", knee, (x + s * 0.02, 0.0, 0.08), 0.05, 0.038, gskin, sides=6, parent=leg)
        tbox(side + "_Knee", (knee[0], knee[1] - 0.03, knee[2]), (0.062, 0.04, 0.065), gskin_l, bevel=0.012, parent=leg)
        limb(side + "_Wrap", (x + s * 0.022, -0.016, 0.22), (x + s * 0.02, -0.004, 0.11), 0.054, 0.048, cloth_m,
             sides=6, parent=leg)
        ring(side + "_WrapTrim", 0.215, 0.057, 0.016, cloth_d, parent=leg, sides=6, x=x + s * 0.022, y=-0.016)
        ring(side + "_WrapTrim2", 0.12, 0.051, 0.014, cloth_d, parent=leg, sides=6, x=x + s * 0.02, y=-0.004)
        tbox(side + "_Foot", (x + s * 0.02, -0.06, 0.04), (0.115, 0.2, 0.08), gskin, top=(0.8, 0.6), shift_top=(0, 0.04),
             bevel=0.02, parent=leg)
        for k in range(3):
            limb(side + "_Toe%d" % k, (x + s * 0.02 + (k - 1) * 0.033, -0.14, 0.03),
                 (x + s * 0.02 + (k - 1) * 0.04, -0.2, 0.015), 0.018, 0.006, bone, sides=4, parent=leg)

    body = empty("Body", (0, 0, 0.55), root)
    # ---------------- tanga com barra escura, abas na frente e atrás, cinto com fivela de osso
    tbox("Hips", (0, 0, 0.575), (0.28, 0.2, 0.13), cloth_m, bevel=0.02, parent=body)
    cloth("LoinSkirt", 0.6, 0.4, 0.15, 0.185, 2 * PI, 2 * PI, [cloth_m, cloth_d], [(0.55, 0), (0.78, 0), (1.0, 1)],
          back=0.75, cols=10, folds=0.012, thick=0.014, parent=body)
    for nm, y, rx in (("Front", -1, 0.12), ("Back", 1, -0.12)):
        tbox("Loin" + nm, (0, y * 0.115, 0.43), (0.14, 0.018, 0.22), cloth_l, bottom=(1.25, 1), rot=(y * -rx, 0, 0),
             jitter=0.004, parent=body)
        tbox("LoinHem" + nm, (0, y * 0.128, 0.33), (0.172, 0.02, 0.03), cloth_d, rot=(y * -rx, 0, 0), parent=body)
    tbox("Belt", (0, 0, 0.625), (0.3, 0.215, 0.045), lea, bevel=0.008, parent=body)
    tbox("BeltBuckle", (0, -0.112, 0.625), (0.05, 0.016, 0.05), bone, bevel=0.006, rot=(0, PI / 4, 0), parent=body)
    pouch("Pouch", (0.14, -0.08, 0.57), lea, lea_d, body, size=(0.07, 0.05, 0.08), rotz=0.6)
    # ---------------- tronco curvado: peito, barriga clara, alça e ombreira com espinhos
    tbox("Chest", (0, 0.03, 0.86), (0.33, 0.22, 0.27), gskin, top=(1.15, 1.0), bottom=(0.85, 0.9), bevel=0.035,
         rot=(0.3, 0, 0), parent=body)
    tbox("Belly", (0, -0.045, 0.71), (0.25, 0.19, 0.19), gskin_l, top=(1.05, 1.0), bottom=(0.85, 0.85), bevel=0.05,
         parent=body)
    tbox("Strap", (0, -0.09, 0.81), (0.04, 0.012, 0.44), lea, rot=(0.25, 0.75, 0), parent=body)
    shell("ShoulderPad", (0.18, 0.02, 0.985), (0.17, 0.19, 0.14), lea, cut=-0.3, rot=(0, 0.4, 0), parent=body)
    ring("ShoulderPadTrim", 0.955, 0.088, 0.018, lea_d, parent=body, sides=8, x=0.2, y=0.02)
    for k in range(3):
        limb("PadSpike%d" % k, (0.2 + k * 0.01, -0.04 + k * 0.05, 1.02), (0.25 + k * 0.01, -0.04 + k * 0.05, 1.1),
             0.02, 0.0, bone, sides=4, parent=body)
    for k in range(5):
        a = -0.8 + k * 0.4
        limb("Tooth%d" % k, (math.sin(a) * 0.12, -0.085 - math.cos(a) * 0.04, 0.965),
             (math.sin(a) * 0.13, -0.095 - math.cos(a) * 0.05, 0.905), 0.012, 0.0, bone, sides=4, parent=body)

    # ---------------- cabeça "desenhada" de goblin: larga, nariz enorme, sobrancelha pesada, olhos amarelos
    head = empty("Head", (0, -0.04, 0.98), body)
    limb("Neck", (0, 0.0, 0.93), (0, -0.05, 1.05), 0.06, 0.055, gskin, sides=6, parent=head)
    face_mats = {"skin": gskin, "pupil": eye, "brow": gskin_d, "lip": dark, "mouth": dark}
    H = human_head("", 0.99, 0.3, head, face_mats,
                   {"width": 1.32, "jaw": 1.12, "chin": 0.6, "nose": 2.2, "nose_w": 1.55, "brow": 1.9, "eye_size": 1.75,
                    "eye_depth": 1.4, "mouth_w": 2.1, "ear": 0.6, "cheek": 1.4}, y0=-0.075)
    for sg, n in ((1, "L"), (-1, "R")):
        # pupila em fenda sobre o olho amarelo
        tbox("Pupil" + n, (sg * H["eye_x"], H["eye_y"] - 0.004, H["eye_z"]), (0.01, 0.006, 0.026), dark, parent=head)
        # presas saindo do canto da boca
        limb("Tusk" + n, (sg * 0.03, H["mouth_y"] + 0.004, H["mouth_z"] - 0.012),
             (sg * 0.038, H["mouth_y"] - 0.006, H["mouth_z"] + 0.03), 0.012, 0.0, bone, sides=4, parent=head)
        # orelhas longas e pontudas, com a parte interna mais escura
        ex, ez = sg * (H["half_w"] - 0.01), H["eye_z"] - 0.005
        limb("Ear" + n, (ex, H["cy"] - 0.01, ez), (sg * 0.37, H["cy"] + 0.08, ez + 0.13), 0.075, 0.008, gskin,
             sides=4, flat=0.35, parent=head)
        limb("EarIn" + n, (ex + sg * 0.012, H["cy"] - 0.024, ez), (sg * 0.32, H["cy"] + 0.055, ez + 0.1), 0.048, 0.006,
             gskin_d, sides=4, flat=0.2, parent=head)
        tbox("Earring" + n, (sg * 0.2, H["cy"] + 0.015, ez - 0.035), (0.02, 0.02, 0.03), goldm, rot=(0, 0, sg * 0.5),
             parent=head)
    # tufo de cabelo espetado em mechas
    # moicano curto penteado para trás: mechas largas na linha do meio, pontas descendo na nuca
    tuft = [dict(a=(0, 52), b=(180, 58), w=0.05, t=0.014, bulge=0.026, n=5),
            dict(a=(-10, 62), b=(-170, 30), w=0.042, t=0.012, bulge=0.02, n=5),
            dict(a=(10, 62), b=(170, 30), w=0.042, t=0.012, bulge=0.02, n=5)]
    hair_locks("Hair", H, tuft, hair, head, scale=1.02)
    # coroa (só aparece no chefe): aro facetado sentado no crânio
    cz, cy, cr = H["chin"] + 20.4 * H["s"], H["cy"], 0.094
    crown = empty("Crown", (0, cy, cz), head)
    ring("CrownBand", cz, cr, 0.045, goldm, parent=crown, sides=8, flat=1.22, y=cy)
    for i in range(6):
        a = i / 6 * 2 * PI + PI / 2
        limb("CrownSpike%d" % i, (math.cos(a) * cr * 0.95, cy + math.sin(a) * cr * 1.17, cz + 0.02),
             (math.cos(a) * cr * 1.02, cy + math.sin(a) * cr * 1.26, cz + 0.09), 0.032, 0.0, goldm, sides=4, parent=crown)
    tbox("CrownGem", (0, cy - cr * 1.24, cz), (0.04, 0.02, 0.036), ruby, bevel=0.006, parent=crown)

    # ---------------- braços longos com faixas e garras
    for side, sx in (("ArmR", -0.2), ("ArmL", 0.2)):
        s = 1 if sx > 0 else -1
        arm = empty(side, (sx, 0, 0.97), body)
        limb(side + "_Upper", (sx, 0, 0.98), (sx + s * 0.05, 0.02, 0.73), 0.056, 0.042, gskin, sides=6, parent=arm)
        limb(side + "_Fore", (sx + s * 0.05, 0.02, 0.73), (sx + s * 0.06, -0.01, 0.52), 0.046, 0.035, gskin,
             sides=6, parent=arm)
        tbox(side + "_Elbow", (sx + s * 0.05, 0.05, 0.73), (0.05, 0.03, 0.05), gskin_l, bevel=0.01, parent=arm)
        limb(side + "_Wrap", (sx + s * 0.058, 0.0, 0.61), (sx + s * 0.06, -0.01, 0.53), 0.049, 0.045, cloth_m,
             sides=6, parent=arm)
        ring(side + "_WrapTrim", 0.605, 0.052, 0.014, cloth_d, parent=arm, sides=6, x=sx + s * 0.058, y=0.0)
        hx, hz = sx + s * 0.06, 0.48
        tbox(side + "_Hand", (hx, -0.01, hz), (0.05, 0.08, 0.07), gskin, bevel=0.012, parent=arm)
        for k in range(3):
            limb(side + "_Claw%d" % k, (hx, -0.04 + k * 0.03, hz - 0.03), (hx - s * 0.01, -0.045 + k * 0.03, hz - 0.08),
                 0.013, 0.004, bone, sides=4, parent=arm)
    arm_r = bpy.data.objects["ArmR"]
    hx, hz = -0.26, 0.48
    limb("Club", (hx, 0.06, hz), (hx, -0.52, hz + 0.05), 0.03, 0.075, wood, sides=7, jitter=0.004, parent=arm_r)
    limb("ClubGrip", (hx, 0.06, hz), (hx, -0.06, hz + 0.01), 0.034, 0.036, lea, sides=7, parent=arm_r)
    for k, yy in enumerate((-0.3, -0.44)):
        limb("ClubBand%d" % k, (hx, yy, hz + 0.03), (hx, yy - 0.035, hz + 0.033), 0.072, 0.075, wood_d if k else iron,
             sides=7, parent=arm_r)
    for k, (dx, dz) in enumerate(((0.07, 0.0), (-0.07, 0.0), (0.0, 0.075), (0.0, -0.07))):
        limb("ClubSpike%d" % k, (hx + dx * 0.8, -0.46, hz + 0.045 + dz * 0.8),
             (hx + dx * 1.5, -0.47, hz + 0.045 + dz * 1.5), 0.018, 0.0, iron, sides=4, parent=arm_r)
    export("goblin")
