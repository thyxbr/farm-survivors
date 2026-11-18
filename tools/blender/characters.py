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
exec(open(OUT.replace("assets/models/", "tools/blender/rig.py"), encoding="utf-8").read(), globals())


# ================================================================== CAVALEIRO
# Corpo-base em loft (body.py) com armadura em camadas derivada das mesmas seções.
# Peças tingidas por scripts/player/knight_look.gd (cada uma com um material só):
#   Helmet, HelmetDome | Torso, Fauld, ArmX_Pauldron | ArmX_Gauntlet, ArmX_Hand | LegX_Sabaton | Shield.
#   (LegX_Foot, no pivô AnkleX, também é tingida com as botas.)
# O resto é juntado por pivô para reduzir objetos.
def band(name, s, axis, w, material, parent, sides=10, phase=0.5, arc=None, fwd=(0, -1, 0), out=0.004,
         thick=0.006):
    """Friso: faixa fina (sem tampas) logo por fora da seção s, com largura w ao longo de axis."""
    ax = Vector(axis).normalized()
    a = dict(s, rx=s["rx"] + out, ry=s["ry"] + out)
    b = dict(a, c=s["c"] + ax * w)
    return loft(name, [a, b], material, parent, sides=sides, phase=phase, axis=ax, fwd=fwd, arc=arc,
                thick=thick, caps=(False, False))


_knight_band = band   # armory.py redefine band() depois; o cavaleiro usa esta


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


def anime_mats(pre, skin_c, iris_c, brow_c, lash_c, mouth_c):
    """Materiais do rosto desenhado (anime.py). O sufixo _flat tira a sombra de forma no jogo (ToonLook)."""
    def sc(c, k):
        return tuple(min(1.0, v * k) for v in c)
    return {
        "skin": mat(pre + "_skin_flat", skin_c, 0.8), "white": mat(pre + "_eyewhite_flat", hexc("#F7F1EA"), 0.5),
        "iris": mat(pre + "_iris_flat", iris_c, 0.5), "iris_dark": mat(pre + "_irisdark_flat", sc(iris_c, 0.42), 0.5),
        "iris_light": mat(pre + "_irislight_flat", sc(iris_c, 2.1), 0.5), "pupil": mat(pre + "_pupil_flat", sc(iris_c, 0.12), 0.5),
        "lash": mat(pre + "_lash_flat", lash_c, 0.5), "brow": mat(pre + "_brow_flat", brow_c, 0.5),
        "mouth": mat(pre + "_mouth_flat", mouth_c, 0.5), "line": mat(pre + "_line_flat", sc(skin_c, 0.62), 0.5)}


def build_knight(female=False):
    """female=True: o mesmo cavaleiro deformado para o corpo feminino, com rabo de cavalo (female.py) ->
    knight_f.glb, com os mesmos nós e pivôs."""
    band = _knight_band
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
        leg, knee, ankle = R["Leg" + n], R["Knee" + n], R["Ankle" + n]
        K = mirror(P["knee"], s)
        th = loft("Leg%s_Thigh" % n, S["thigh"], chain, leg)
        cu = loft("Leg%s_Cuisse" % n, grow(span(S["thigh"], 0.12, 0.9), 1.12, 0.014), steel, leg, sides=6, arc=3.6,
                  thick=0.014)
        join_objs("Leg%s_Thigh" % n, [th, cu])
        pol = loft("Leg%s_Knee" % n, [sec((K.x, K.y - 0.03, K.z + 0.005), 0.07, 0.074),
                                      sec((K.x, K.y - 0.075, K.z), 0.064, 0.068),
                                      sec((K.x, K.y - 0.1, K.z - 0.006), 0.042, 0.046)],
                   steel, knee, fwd=(0, 0, 1), chamfer=(0.0, 0.008))
        sab_s = grow(S["foot"], 1.1, 0.006)   # escarpe de aço inteiro, sem sola de couro: pisa direto no chão
        kw = wing("Leg%s_KneeWing" % n, (K.x + s * 0.066, K.y - 0.035, K.z), 0.075, 0.1, 0.009, steel, knee)
        gband = band("Leg%s_GreaveTrim" % n, grow([sample(S["shin"], 0.2)], 1.13, 0.008, keel=0.12)[0],
                     S["shin"][-1]["c"] - S["shin"][0]["c"], 0.016, trim, knee, sides=8, phase=0)
        join_objs("Leg%s_Knee" % n, [pol, kw, gband])
        gr = loft("Leg%s_Sabaton" % n, grow(span(S["shin"], 0.04, 0.97), 1.13, 0.008, keel=0.12), steel, knee,
                  phase=0, chamfer=(0.006, 0.0))
        # pé no tornozelo (AnkleX): calcanhar, pé chato e ponta giram sem a canela
        loft("Leg%s_Foot" % n, stepped(sab_s, (0.42, 0.58, 0.74), drop=0.92, keep_bottom=True), steel, ankle,
             fwd=(0, 0, 1), chamfer=(0.008, 0.01))

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
    if female:   # alças de couro (enarmes) do antebraço ao escudo: o braço fino deixaria o escudo solto
        E, Wl = mirror(P["elbow"], 1), mirror(P["wrist"], 1)
        for k, z in enumerate((sz - 0.04, sz + 0.06)):
            f = E.lerp(Wl, (E.z - z) / (E.z - Wl.z))
            x0, x1 = f.x + 0.02, sxp + 0.004
            rim.append(tbox("ShieldStrap%d" % k, ((x0 + x1) / 2, f.y, z), (x1 - x0, 0.034, 0.014), lea, bevel=0.003,
                            parent=el_l))
    join_objs("ShieldRim", rim)
    tbox("Shield", (sxp + 0.008, 0, sz + 0.005), (0.026, 0.38, 0.48), red_c, bottom=(1, 0.2), bevel=0.008,
         parent=el_l)
    # sombra assada nas dobras (gear.py): mesma leitura das roupas modulares
    if female:
        knight_f_finish(R)
    g_smooth([o for o in scn.objects if o.type == 'MESH'])       # placas lisas, como o corpo e as roupas (gear.py)
    bake_ao([o for o in scn.objects if o.type == 'MESH'], [])
    export("knight_f" if female else "knight", export_vertex_color='ACTIVE')


# ================================================================== ANCIÃO (NPC)
# Bram com esqueleto (rig.py): as mesmas peças, cores e proporções do Bram de peças rígidas, juntadas numa malha
# só. Os braços (modelados caídos ao lado do corpo) são girados em volta do ombro e do cotovelo até a pose T;
# o clipe staff_hold os devolve exatamente à posição modelada. Túnica, manto e acessórios do tronco usam um
# campo de pesos só (robe_field): gradiente no tronco e, abaixo do quadril, quadril cedendo às coxas.
# O cajado ("Staff") é um objeto à parte, sem pesos, com o pivô na mão esquerda (pose T).
ELDER_SPINE = (1.03, 1.13, 1.25, 1.40, 1.50)   # início de Spine, Spine1, Spine2, Neck e Head
ELDER_STAFF_SPOT = Vector((0.42, -0.27))       # eixo do cajado no staff_hold (x, y do Blender), fora da túnica
# ^ só a pose de referência do staff_hold; no jogo o cajado fica no "spot" de tools/build_npc_mixamo.gd (IK nos clipes)


def build_elder(santa=False):
    """santa=True: o Papai Noel da vila (santa.glb). Mesmo corpo, esqueleto e clipes do Bram (o jogo usa a
    biblioteca do Mixamo do Bram nele): casaco vermelho com barra de pele branca, cinto preto de fivela dourada,
    gorro com pompom, barba longa e cheia e uma bengala doce no lugar do cajado."""
    robe = mat("e_robe", (0.08, 0.2, 0.32), 0.95)
    robe_l = mat("e_robe_light", (0.12, 0.3, 0.42), 0.95)
    mantle = mat("e_mantle", (0.55, 0.42, 0.25), 0.95)
    mantle_d = mat("e_mantle_d", (0.38, 0.27, 0.15), 0.95)
    trim = mat("e_trim", (0.85, 0.72, 0.4), 0.5, 0.6)
    fur = trim
    if santa:
        robe = mat("s_coat", (0.42, 0.02, 0.025), 0.9)
        robe_l = mat("s_coat_light", (0.55, 0.04, 0.04), 0.9)
        fur = mat("s_fur", (0.86, 0.85, 0.82), 1.0)
        mantle = mantle_d = fur
    skin = mat("e_skin", (0.78, 0.55, 0.42), 0.8)
    hair = mat("e_hair", (0.9, 0.9, 0.88), 0.9)
    rope = mat("e_rope", (0.7, 0.6, 0.4), 0.95)
    lea = mat("e_leather", (0.3, 0.18, 0.1), 0.85)
    wood = mat("e_wood", (0.36, 0.22, 0.12), 0.9)
    gem = mat("e_gem", (0.3, 0.75, 1.0), 0.2, 0, emit=(0.3, 0.7, 1.0), strength=6)

    hip_z = 0.95
    seen = set()

    def take():
        """Malhas criadas desde a última chamada (para ponderar por região)."""
        new = [o for o in coll.objects if o.type == 'MESH' and o.name not in seen]
        seen.update(o.name for o in new)
        return new

    Z = (0, 0, 1)
    for s, x, sd in ((1, 0.08, "Left"), (-1, -0.08, "Right")):
        tbox("Shoe" + ("L" if s > 0 else "R"), (x, -0.07, 0.04), (0.1, 0.2, 0.08), lea, top=(0.85, 0.75),
             shift_top=(0, 0.02), bevel=0.02)
        weigh(take(), Z, [(0.0, sd + "Foot")])
    drape("RobeSkirt", 1.02, 0.05, 0.17, 0.29, 2 * PI, 2 * PI, robe, rows=5, cols=14, folds=0.018, thick=0.02)
    tbox("RobePanel", (0, -0.2, 0.55), (0.12, 0.02, 0.92), robe_l, top=(0.6, 1), shift_top=(0, 0.07), bevel=0.004,
         rot=(0.07, 0, 0))
    ring("RobeHem", 0.07 if not santa else 0.08, 0.3 if not santa else 0.315, 0.035 if not santa else 0.1, fur, sides=14)
    if santa:
        # barriga redonda por baixo do casaco, pele descendo pela frente, cinto preto com fivela dourada
        tbox("Chest", (0, 0, 1.22), (0.32, 0.21, 0.42), robe, top=(1.12, 1.05), bottom=(0.98, 1.0), bevel=0.04)
        shell("Belly", (0, -0.045, 1.1), (0.42, 0.36, 0.42), robe, cut=-0.75, seg=12, rings=8, thick=0.02)
        tbox("FurPanel", (0, -0.22, 0.5), (0.1, 0.03, 0.86), fur, top=(0.9, 1), shift_top=(0, 0.04), bevel=0.01,
             rot=(0.07, 0, 0))
        ring("Belt", 1.0, 0.214, 0.07, mat("s_belt", (0.03, 0.025, 0.025), 0.6), sides=14, y=-0.02)
        tbox("Buckle", (0, -0.235, 1.0), (0.11, 0.025, 0.09), mat("s_buckle", (0.95, 0.7, 0.2), 0.3, 1.0), bevel=0.008)
        tbox("BuckleHole", (0, -0.249, 1.0), (0.06, 0.006, 0.045), mat("s_belt", (0.03, 0.025, 0.025), 0.6))
        ring("FurCollar", 1.41, 0.15, 0.07, fur, sides=12)
        for k in range(3):   # botões pretos acima do cinto
            shell(f"Button{k}", (0, -0.2 + k * 0.012, 1.12 + k * 0.08), (0.03, 0.02, 0.03),
                  mat("s_belt", (0.03, 0.025, 0.025), 0.6), cut=-1.0, thick=0, seg=6, rings=4)
        pouch("Pouch", (-0.17, -0.09, 0.93), lea, lea, None, size=(0.08, 0.06, 0.1), rotz=-0.5)
    else:
        tbox("Chest", (0, 0, 1.22), (0.32, 0.2, 0.42), robe, top=(1.12, 1.05), bottom=(0.95, 0.95), bevel=0.04)
        tbox("Collar", (0, -0.085, 1.36), (0.14, 0.05, 0.14), robe_l, bottom=(0.3, 1), bevel=0.01)
        # manto sobre os ombros e capuz caído
        shell("Mantle", (0, 0, 1.3), (0.5, 0.34, 0.36), mantle, cut=-0.15, seg=12, rings=8, thick=0.02)
        ring("MantleTrim", 1.27, 0.25, 0.03, trim, sides=12, flat=0.68)
        shell("Hood", (0, 0.11, 1.47), (0.3, 0.2, 0.22), mantle_d, cut=-0.5, rot=(0.9, 0, 0), jitter=0.006)
        # cinto de corda, bolsa, estojo de pergaminho, pingente
        ring("RopeBelt", 1.01, 0.178, 0.03, rope, sides=12)
        limb("RopeEnd1", (0.06, -0.17, 1.0), (0.08, -0.19, 0.72), 0.012, 0.01, rope, sides=4)
        limb("RopeEnd2", (0.09, -0.16, 1.0), (0.12, -0.18, 0.78), 0.012, 0.01, rope, sides=4)
        tbox("Tassel1", (0.08, -0.19, 0.7), (0.03, 0.03, 0.05), trim, bottom=(1.5, 1.5))
        pouch("Pouch", (-0.16, -0.09, 0.93), lea, lea, None, size=(0.08, 0.06, 0.1), rotz=-0.5)
        limb("ScrollCase", (0.19, 0.06, 1.06), (0.21, 0.08, 0.78), 0.035, 0.035, lea, sides=7)
        limb("ScrollCap", (0.21, 0.08, 0.79), (0.212, 0.082, 0.76), 0.04, 0.04, trim, sides=7)
        limb("Necklace", (0, -0.1, 1.38), (0, -0.125, 1.26), 0.006, 0.006, rope, sides=4)
        shell("Pendant", (0, -0.13, 1.24), (0.045, 0.02, 0.06), gem, cut=-1.0, thick=0)
    weigh_by(take(), robe_field(hip_z, 0.5, [(0.98, "Hips"), (1.06, "Spine"), (1.17, "Spine1"), (1.3, "Spine2")]))
    # cabeça
    limb("Neck", (0, 0.005, 1.4), (0, 0.012, 1.6), 0.056, 0.052, skin, sides=7)
    weigh(take(), Z, [(1.42, "Spine2"), (1.47, "Neck"), (1.52, "Neck"), (1.57, "Head")])
    face_mats = {"skin": skin, "lip": mat("e_lip", (0.62, 0.38, 0.34), 0.7), "sclera": mat("e_sclera", (0.88, 0.86, 0.8), 0.4),
                 "iris": mat("e_iris", (0.32, 0.42, 0.52), 0.3), "pupil": mat("e_pupil", (0.03, 0.03, 0.03), 0.2),
                 "brow": hair, "lash": mat("e_lash", (0.2, 0.16, 0.14), 0.9)}
    H = anime_head("", 1.505, 0.235, None,
                   anime_mats("e", (0.78, 0.55, 0.42), (0.20, 0.30, 0.42), (0.50, 0.50, 0.55), (0.2, 0.16, 0.14),
                              (0.42, 0.22, 0.2)),
                   {"eye_h": 0.6, "eye_w": 0.88, "lash": 0.6, "brow": 2.0, "brow_dz": -0.25, "brow_tilt": 0.3, "nose": 1.2})
    # cabelo branco penteado para trás, caindo até a nuca, e barba longa (anime.py)
    hair_d = mat("e_hair_d", (0.42, 0.42, 0.45), 0.9)
    hm = {"hair": hair, "mid": mat("e_hair_mid", (0.66, 0.66, 0.69), 0.9), "under": hair_d}
    back = [([(th, 38, 0.1), (th, 60, 0.7), (th, 82, 1.0), (180 - th * 0.8, 66, 1.1), (180 - th * 0.7, 40, 1.3)], 4.2,
             "hair", 0.2) for th in (-42, -15, 13, 40)]
    anime_hair("", H, hm, None, {"bangs": False, "back": -46, "side": 8, "extra": back, "seed": 5})
    anime_beard("", H, hm, None, {"length": 13.0, "full": 1.5} if santa else {"length": 10.5})
    if santa:
        # gorro: barra de pele, cone vermelho caindo para trás e pompom
        zt = H["top"]
        ring("HatBrim", zt - 0.055, 0.128, 0.05, fur, sides=14, y=0.005)
        limb("Hat1", (0, 0.01, zt - 0.04), (0, 0.05, zt + 0.1), 0.122, 0.07, robe, sides=10)
        limb("Hat2", (0, 0.05, zt + 0.1), (0, 0.16, zt + 0.12), 0.07, 0.035, robe, sides=8)
        limb("Hat3", (0, 0.16, zt + 0.12), (0, 0.22, zt + 0.03), 0.035, 0.02, robe, sides=6)
        shell("Pompom", (0, 0.225, zt + 0.01), (0.07, 0.07, 0.07), fur, cut=-1.0, thick=0, seg=8, rings=5)
    weigh(take(), Z, [(0.0, "Head")])

    # braços com mangas largas, modelados caídos (como antes) e girados até a pose T em volta do ombro e do
    # cotovelo; a ombreira fica no osso do ombro (não gira com o braço)
    joints, turn = {}, {}
    for side, sx, sd in (("ArmR", -0.2, "Right"), ("ArmL", 0.2, "Left")):
        s = 1 if sx > 0 else -1
        sh = Vector((sx, 0, 1.4))
        el = Vector((sx + s * 0.03, 0.01, 1.15))
        wr = Vector((sx + s * 0.045, -0.01, 0.9))
        shell(side + "_Shoulder", (sx, 0, 1.4), (0.16, 0.17, 0.14), robe, cut=-0.2, thick=0)
        weigh(take(), Z, [(0.0, sd + "Shoulder")])
        limb(side + "_Upper", (sx, 0, 1.42), (sx + s * 0.03, 0.01, 1.15), 0.065, 0.075, robe, sides=7)
        upper = take()
        limb(side + "_Sleeve", (sx + s * 0.03, 0.01, 1.16), (sx + s * 0.045, -0.01, 0.94), 0.08, 0.12, robe, sides=8)
        ring(side + "_Cuff", 0.95, 0.122 if not santa else 0.13, 0.035 if not santa else 0.06, fur, sides=8,
             x=sx + s * 0.045, y=-0.01)
        limb(side + "_Wrist", (sx + s * 0.045, -0.01, 0.98), (sx + s * 0.045, -0.01, 0.9), 0.035, 0.032, skin, sides=6)
        fore = take()
        npc_hand(side, (sx + s * 0.045, -0.01, 0.905), s, skin, None)
        palm = take()
        tx = Vector((s, 0, 0))
        r_up = (el - sh).normalized().rotation_difference(tx)
        r_fo = (wr - el).normalized().rotation_difference(tx)
        el_t = sh + r_up @ (el - sh)
        wr_t = el_t + r_fo @ (wr - el)
        for o in upper:
            for v in o.data.vertices:
                v.co = sh + r_up @ (v.co - sh)
        for o in fore + palm:
            for v in o.data.vertices:
                v.co = el_t + r_fo @ (v.co - el)
        weigh(upper, Z, [(0.0, sd + "Arm")])
        weigh(fore, Z, [(0.0, sd + "ForeArm")])
        weigh(palm, Z, [(0.0, sd + "Hand")])
        joints[sd] = (sh, el_t, wr_t)
        turn[sd] = (r_up, r_fo, el, el_t)

    body = join_objs("Elder", [o for o in coll.objects if o.type == 'MESH'])

    # ---------------- cajado (objeto à parte): cajado de caminhada. No staff_hold o braço esquerdo desce do
    # ombro um pouco para a frente e o cotovelo dobra, com o antebraço e a mão apontando para a frente e para fora
    # (o braço modelado caído gira para a frente: polegar para cima, palma para dentro); o punho fecha em volta do
    # cajado na altura de ~1 m, com o cajado de pé, fora da túnica (que abre para a frente quando ele se curva ou
    # dá passos). O cajado é o mesmo de antes, na mesma altura (pé no chão, gancho em cima); só muda de lugar.
    # Na pose T ele vai junto com a mão, com o pivô no punho.
    if santa:
        # bengala doce: haste branca com listras vermelhas e o gancho em arco, alternando as cores
        cw, cr = mat("s_cane_white", (0.9, 0.88, 0.85), 0.5), mat("s_cane_red", (0.6, 0.02, 0.03), 0.5)
        st = [limb("Staff", (0.25, -0.07, 0.02), (0.25, -0.07, 1.7), 0.026, 0.026, cw, sides=8)]
        z = 0.08
        while z < 1.66:
            st.append(ring(f"Stripe{int(z * 100)}", z, 0.029, 0.06, cr, sides=8, x=0.25, y=-0.07))
            z += 0.16
        prev = Vector((0.25, -0.07, 1.7))
        for k in range(1, 8):
            a = PI * k / 7
            p = Vector((0.25 + 0.11 - 0.11 * math.cos(a), -0.07, 1.7 + 0.13 * math.sin(a)))
            st.append(limb(f"StaffCrook{k}", prev, p, 0.026, 0.026, cw if k % 2 else cr, sides=8))
            prev = p
    else:
        st = [limb("Staff", (0.25, -0.07, 0.02), (0.25, -0.07, 1.82), 0.022, 0.026, wood, sides=6, twist=0.6),
              limb("StaffWrap", (0.25, -0.07, 1.0), (0.25, -0.07, 1.12), 0.03, 0.03, lea, sides=6),
              limb("StaffCrook1", (0.25, -0.07, 1.82), (0.29, -0.07, 1.94), 0.026, 0.02, wood, sides=6),
              limb("StaffCrook2", (0.29, -0.07, 1.94), (0.22, -0.07, 2.0), 0.02, 0.016, wood, sides=6),
              shell("StaffGem", (0.255, -0.07, 1.93), (0.075, 0.075, 0.1), gem, cut=-1.0, thick=0, seg=6, rings=4)]
    staff = join_objs("Staff", st)
    r_up, r_fo, el, el_t = turn["Left"]
    sh_l = joints["Left"][0]
    fist = Vector((0.245, -0.006, 0.83))                       # centro do punho modelado (bloco da mão)
    up_dir = Vector((0.12, -0.25, -1.0)).normalized()          # braço: um pouco para a frente e para fora
    r_hu = (el - sh_l).normalized().rotation_difference(up_dir)
    el_h = sh_l + r_hu @ (el - sh_l)                           # cotovelo no staff_hold
    reach = (fist - el).length
    flat = ELDER_STAFF_SPOT - el_h.to_2d()
    fist_h = Vector((ELDER_STAFF_SPOT.x, ELDER_STAFF_SPOT.y, el_h.z - math.sqrt(reach * reach - flat.length_squared)))
    r_hf = (fist - el).normalized().rotation_difference((fist_h - el_h).normalized())
    print("Bram: punho no cajado a %.3f m, cotovelo a %.3f m" % (fist_h.z, el_h.z))
    # malha de pé em volta do punho (eixos da malha alinhados ao cajado); a rotação da pose T fica no objeto
    mw = staff.matrix_world.copy()
    move = Vector((ELDER_STAFF_SPOT.x - 0.25, ELDER_STAFF_SPOT.y + 0.07, 0))
    for v in staff.data.vertices:
        v.co = mw @ v.co + move - fist_h
    to_t = (r_fo @ r_hf.inverted()).to_matrix().to_4x4()
    staff.matrix_world = Matrix.Translation(el_t + r_fo @ r_hf.inverted() @ (fist_h - el_h)) @ to_t

    # ---------------- esqueleto em pose T, nomes do Mixamo (sem pernas modeladas: ossos dentro da túnica)
    P = {"hip": Vector((0.08, 0, hip_z)), "knee": Vector((0.08, 0, 0.5)), "ankle": Vector((0.08, 0, 0.08))}
    arm = mixamo_rig([body], P, joints, hip_z, H["top"], spine=ELDER_SPINE)

    # ---------------- clipes (direções de mundo: frente = -Y, esquerda = +X)
    # staff_hold: braço direito de volta à posição modelada; o esquerdo segura o cajado de caminhada (acima)
    hold = {}
    for sd in ("Left", "Right"):
        r_up, r_fo, _, _ = turn[sd]
        hold[sd + "Arm"] = r_up.inverted().to_matrix()
        hold[sd + "ForeArm"] = hold[sd + "Hand"] = r_fo.inverted().to_matrix()
    r_up, r_fo, _, _ = turn["Left"]
    hold["LeftArm"] = (r_hu.to_matrix() @ r_up.inverted().to_matrix())
    hold["LeftForeArm"] = hold["LeftHand"] = r_hf.to_matrix() @ r_fo.inverted().to_matrix()

    # excited: o braço direito sobe com o punho fechado e "bombeia" duas vezes, como dobradiça (braço, antebraço
    # e mão com o mesmo eixo de dobra); o tronco recua um pouco e a cabeça sobe. O braço esquerdo fica no
    # staff_hold (orientação absoluta), então o cajado continua de pé na mão.
    # n_up: eixo de dobra do braço erguido (perpendicular ao braço e ao antebraço de pé), o mesmo em todas as
    # chaves: o úmero gira para fora uma vez ao subir e depois só o cotovelo e o ombro dobram
    side_up, fore_up = Vector((-0.85, -0.3, 0.35)).normalized(), Vector((-0.15, -0.2, 1.0)).normalized()
    n_up = side_up.cross(fore_up).normalized()

    def cheer(up, flex, lean, head, wrist=0.0):
        """Braço direito apontando para up com o cotovelo dobrado flex graus (e o punho wrist graus) no plano
        de normal n_up; tronco recuado lean graus e cabeça erguida head graus."""
        d = Vector(up).normalized()
        n = (n_up - d * d.dot(n_up)).normalized()
        fo = Quaternion(n, math.radians(flex)) @ d
        hd = Quaternion(n, math.radians(flex + wrist)) @ d
        t = dict(hold)
        t.update(Spine1=_qx(-lean * 0.6), Spine2=_qx(-lean * 0.4), Head=_qx(-head),
                 RightArm=hinge_frame(d, n, -1), RightForeArm=hinge_frame(fo, n, -1),
                 RightHand=hinge_frame(hd, n, -1))
        return t

    fps = scn.render.fps
    scn.render.fps = 30
    bake_clip(arm, "staff_hold", [(0, hold)])
    pump = (side_up, math.degrees(side_up.angle(fore_up)), 2, 6, 10)   # braço para o lado, antebraço de pé
    up = ((-0.45, -0.2, 0.87), 15, 4, 10)                            # punho no alto, cotovelo quase esticado
    bake_clip(arm, "excited", [(0, hold), (7, cheer(*pump)), (13, cheer(*up)), (19, cheer(*pump)), (25, cheer(*up)),
                               (32, cheer(*pump)), (45, hold)])
    g_smooth([o for o in scn.objects if o.type == 'MESH'])
    export("santa" if santa else "elder", export_animations=True, export_skins=True, export_animation_mode='NLA_TRACKS')
    scn.render.fps = fps


# ================================================================== MERCADORA (NPC)
# Segue docs/PROMPT_LOWPOLY.md: camadas corpo -> túnica -> faixa/cinto -> mantelete -> capa,
# barra em toda borda de tecido, 3 tons por material, 60% roxo / 30% ocre e couro / 10% laranja, azul e ouro.
# Com esqueleto (Mixamo, pose T), como o Bram: as peças são as mesmas de antes, montadas nos pivôs de sempre
# (LegL/LegR, Body, Head, ArmL/ArmR) e depois levadas para coordenadas de mundo e juntadas numa malha skinned.
# Os braços são modelados caídos e girados até a pose T; o clipe arms_down os devolve exatamente à posição
# modelada. Saia, faixa, bolsas, mantelete, capuz e capa usam um campo de pesos só (robe_field).
MERCHANT_SPINE = (1.03, 1.13, 1.25, 1.41, 1.52)   # início de Spine, Spine1, Spine2, Neck e Head


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
    H = anime_head("", 1.52, HH, head, anime_mats("m", hexc("#E3A47E"), hexc("#7A4A22"), hexc("#4A2A18"), hexc("#2B170C"),
                                              hexc("#8C3F38")))
    k = HH / 23.0                                # 1 cm do modelo anatômico -> metros
    # cabelo: mechas lisas que saem de baixo do turbante e se juntam no coque baixo (anime.py)
    hair_d = mat("m_hair_d", hexc("#2B170C"), 0.9)
    hm = {"hair": hair, "mid": mat("m_hair_mid", hexc("#3A2012"), 0.9), "under": hair_d}
    locks = []
    for th in (112, 135, 158, 180, 202, 225, 248):
        locks.append(([(th, 30, 0.4), (180 + (th - 180) * 0.75, 2, 1.1), (180 + (th - 180) * 0.3, -34, 1.0)], 3.3,
                      "hair"))
    for sg in (1, -1):
        locks.append(([(sg * 62, 29, 0.2), (sg * 68, 14, 0.6), (sg * 75, -3, 0.4)], 1.9, "hair"))
    anime_hair("", H, hm, head, {"top": 0, "nape": False, "frame": False, "bangs": False, "extra": locks})
    anime_bun("HairBun", (0, 0.105, 1.56), (0.085, 0.07, 0.075), hair, head)
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
        pv = empty(side, (sx, 0, 1.4), body)
        ex = sx + s * 0.028
        wx = sx + s * 0.04
        limb(side + "_Upper", (sx, 0, 1.37), (ex, 0.01, 1.2), 0.042, 0.076, pur, sides=7, parent=pv)
        ring(side + "_SleeveTrimB", 1.232, 0.08, 0.02, pur_d, parent=pv, sides=7, x=ex, y=0.01)
        ring(side + "_SleeveTrimA", 1.203, 0.083, 0.03, pur_l, parent=pv, sides=7, x=ex, y=0.01)
        limb(side + "_Fore", (ex, 0.01, 1.21), (wx, 0, 0.93), 0.05, 0.04, blue, sides=6, parent=pv)
        limb(side + "_Bracer", (sx + s * 0.034, 0.005, 1.06), (wx, 0, 0.94), 0.055, 0.047, lea, sides=7, parent=pv)
        ring(side + "_BracerTop", 1.058, 0.059, 0.022, lea_d, parent=pv, sides=7, x=sx + s * 0.034, y=0.005)
        ring(side + "_BracerBot", 0.947, 0.051, 0.02, lea_d, parent=pv, sides=7, x=wx)
        npc_hand(side, (wx, 0, 0.935), s, skin, pv)

    # ---------------- tudo em coordenadas de mundo, agrupado pelo pivô em que foi montado
    scn.view_layers[0].update()
    groups = {}
    for o in [o for o in coll.objects if o.type == 'MESH']:
        groups.setdefault(o.parent.name, []).append(o)
        o.data.transform(o.matrix_world)
        o.parent = None
        o.matrix_world = Matrix.Identity(4)
    for e in [o for o in coll.objects if o.type == 'EMPTY']:
        bpy.data.objects.remove(e, do_unlink=True)

    hip_z = 0.93
    Z = (0, 0, 1)
    # pernas: bota e pé no Foot, cano no Leg, coxa (calça) no UpLeg, com a dobra no joelho
    for side, sd in (("LegL", "Left"), ("LegR", "Right")):
        weigh(groups[side], Z, [(0.1, sd + "Foot"), (0.16, sd + "Leg"), (0.47, sd + "Leg"), (0.55, sd + "UpLeg")])
    # túnica, faixa, bolsas, mantelete, capuz e capa: o mesmo campo (peças coladas se movem juntas)
    torso = [(0.98, "Hips"), (1.06, "Spine"), (1.17, "Spine1"), (1.3, "Spine2")]
    robe = robe_field(hip_z, 0.5, torso)
    capelet = [o for o in groups["Body"] if o.name == "Capelet"]
    cloak = [o for o in groups["Body"] if o.name == "Cloak"]
    weigh_by([o for o in groups["Body"] if o not in capelet + cloak], robe)
    # a capa é aberta na frente e cai atrás das pernas até o chão: segue menos as coxas, senão a barra varre
    # para a frente da perna no passo
    weigh_by(cloak, robe_field(hip_z, 0.5, torso, legs=0.35))

    def cape_field(co):
        """Mantelete: no meio, o campo da túnica; nos lados passa aos poucos para o osso do ombro, para subir
        por cima do braço quando ele se ergue (o ombro não gira no arms_down, então a pose de sempre não muda)."""
        u = min(1.0, max(0.0, (abs(co.x) - 0.1) / 0.18))
        u = 0.85 * u * u * (3 - 2 * u)
        sd = "Left" if co.x > 0 else "Right"
        return [(b, w * (1.0 - u)) for b, w in robe(co)] + [(sd + "Shoulder", u)]
    weigh_by(capelet, cape_field)
    # cabeça: pescoço em gradiente, o resto (rosto, cabelo, brincos, turbante) no Head
    neck = [o for o in groups["Head"] if o.name == "Neck"]
    weigh(neck, Z, [(1.42, "Spine2"), (1.47, "Neck"), (1.52, "Neck"), (1.57, "Head")])
    weigh([o for o in groups["Head"] if o not in neck], Z, [(0.0, "Head")])
    top = max(v.co.z for o in groups["Head"] for v in o.data.vertices)

    # braços: manga curta (com as barras) no Arm, manga azul e braçadeira no ForeArm, mão no Hand; girados
    # em volta do ombro e do cotovelo da pose caída até a pose T
    joints, turn = {}, {}
    for side, sx, sd in (("ArmR", -0.2, "Right"), ("ArmL", 0.2, "Left")):
        s = 1 if sx > 0 else -1
        sh = Vector((sx, 0, 1.38))
        el = Vector((sx + s * 0.028, 0.01, 1.205))
        wr = Vector((sx + s * 0.04, 0, 0.93))
        parts = {o.name[len(side):]: o for o in groups[side]}
        upper = [parts[n] for n in ("_Upper", "_SleeveTrimB", "_SleeveTrimA")]
        fore = [parts[n] for n in ("_Fore", "_Bracer", "_BracerTop", "_BracerBot")]
        palm = [parts["_Hand"]]              # mão aberta (open_hand): palma, dedos e polegar numa malha só
        assert len(upper) + len(fore) + len(palm) == len(groups[side])
        tx = Vector((s, 0, 0))
        r_up = (el - sh).normalized().rotation_difference(tx)
        r_fo = (wr - el).normalized().rotation_difference(tx)
        el_t = sh + r_up @ (el - sh)
        wr_t = el_t + r_fo @ (wr - el)
        for o in upper:
            for v in o.data.vertices:
                v.co = sh + r_up @ (v.co - sh)
        for o in fore + palm:
            for v in o.data.vertices:
                v.co = el_t + r_fo @ (v.co - el)
        weigh(upper, Z, [(0.0, sd + "Arm")])
        weigh(fore, Z, [(0.0, sd + "ForeArm")])
        weigh(palm, Z, [(0.0, sd + "Hand")])
        joints[sd] = (sh, el_t, wr_t)
        turn[sd] = (r_up, r_fo)

    body = join_objs("Merchant", [o for o in coll.objects if o.type == 'MESH'])

    # ---------------- esqueleto em pose T, nomes do Mixamo
    P = {"hip": Vector((0.09, 0, hip_z)), "knee": Vector((0.09, 0, 0.5)), "ankle": Vector((0.09, 0, 0.1))}
    arm = mixamo_rig([body], P, joints, hip_z, top, spine=MERCHANT_SPINE)

    # ---------------- clipes (direções de mundo: frente = -Y, esquerda = +X)
    # arms_down: braços de volta à posição modelada (caídos ao lado do corpo), a pose de sempre da Mira
    down = {}
    for sd in ("Left", "Right"):
        r_up, r_fo = turn[sd]
        down[sd + "Arm"] = r_up.inverted().to_matrix()
        down[sd + "ForeArm"] = down[sd + "Hand"] = r_fo.inverted().to_matrix()

    # call: a mão direita sobe ao lado da cabeça com a palma para a frente e acena para o cliente, o antebraço
    # balançando para fora e para dentro duas vezes. O braço é uma dobradiça (braço, antebraço e mão com o mesmo
    # eixo de dobra n_up): só o cotovelo e o punho dobram, nada torce. O tronco se inclina um pouco para a frente
    # (para o cliente) e a cabeça tomba de leve. O braço esquerdo fica caído (arms_down).
    side_up, fore_up = Vector((-0.88, -0.3, -0.2)).normalized(), Vector((-0.1, -0.15, 1.0)).normalized()
    n_up = side_up.cross(fore_up).normalized()
    stand = math.degrees(side_up.angle(fore_up))     # dobra do cotovelo com o antebraço de pé

    def wave(flex, wrist, lean, tilt, shrug=14):
        """Antebraço direito a flex graus do braço e mão a mais wrist graus, no plano de normal n_up; tronco
        inclinado lean graus para a frente, cabeça tombada tilt graus e ombro direito erguido shrug graus (leva
        o lado do mantelete por cima do braço)."""
        fo = Quaternion(n_up, math.radians(flex)) @ side_up
        hd = Quaternion(n_up, math.radians(flex + wrist)) @ side_up
        t = dict(down)
        t.update(Spine1=_qx(lean * 0.6), Spine2=_qx(lean * 0.4),
                 RightShoulder=Quaternion((0, 1, 0), math.radians(shrug)),
                 Head=Quaternion((0, 1, 0), math.radians(tilt)) @ _qx(lean * 0.3),
                 RightArm=hinge_frame(side_up, n_up, -1), RightForeArm=hinge_frame(fo, n_up, -1),
                 RightHand=hinge_frame(hd, n_up, -1))
        return t

    fps = scn.render.fps
    scn.render.fps = 30
    bake_clip(arm, "arms_down", [(0, down)])
    out_, in_ = (stand - 22, -12), (stand + 14, 14)          # (cotovelo, punho) para fora / para dentro
    bake_clip(arm, "call", [(0, down), (9, wave(stand, 0, 4, 5)), (15, wave(*out_, 5, 6)), (21, wave(*in_, 5, 6)),
                            (27, wave(*out_, 5, 6)), (33, wave(*in_, 5, 6)), (37, wave(stand, 0, 4, 5)), (45, down)])
    g_smooth([o for o in scn.objects if o.type == 'MESH'])
    export("merchant", export_animations=True, export_skins=True, export_animation_mode='NLA_TRACKS')
    scn.render.fps = fps


# ================================================================== ALDEÃO (Defesa da Cidade)
# Plebeu com esqueleto (Mixamo, pose T), montado como a Mira: peças nos pivôs de sempre, levadas para
# coordenadas de mundo e juntadas numa malha skinned. Túnica curta (não atrapalha as pernas no trabalho),
# calça, botina e mangas arregaçadas. Braço e antebraço têm o comprimento de um adulto (26 cm cada), para as
# mãos dos clipes de trabalho do Mixamo (enxada, caixote) caírem onde o clipe espera. Três variações de roupa
# (VILLAGER_LOOKS), uma por arquivo: villager_1.glb, villager_2.glb, villager_3.glb. Sem ferramenta: o jogo
# prende a do ofício no osso da mão (scripts/colony/villager_visual.gd). Único clipe do .glb: arms_down.
VILLAGER_SPINE = (1.03, 1.13, 1.25, 1.41, 1.52)   # início de Spine, Spine1, Spine2, Neck e Head
VILLAGER_LOOKS = {
    # linho cru, chapéu de palha
    1: dict(tunic="#B99C68", tunic_d="#8A6F44", tunic_l="#D8C190", pants="#5A4631", hair="#5A3A20", skin="#E0A27C",
            head="straw", extra="pouch", fem=0.0),
    # verde, avental e lenço na cabeça
    2: dict(tunic="#5F8048", tunic_d="#3F5A30", tunic_l="#86A568", pants="#6B5A45", hair="#3A2416", skin="#E8B08C",
            head="kerchief", extra="apron", fem=1.0),
    # azul acinzentado, colete de couro, cabeça descoberta
    3: dict(tunic="#5C7592", tunic_d="#3E526B", tunic_l="#8AA0B8", pants="#4A3A2C", hair="#8A5A2A", skin="#D99A72",
            head="", extra="vest", fem=0.0),
}


# Clipes provisórios de trabalho com as duas mãos no cabo (o pacote do Mixamo não tem capina em pé nem golpe
# de machado/picareta). Cada chave: quadro, inclinação e giro do tronco (graus; giro positivo leva o ombro
# direito à frente), quanto o quadril desce e recua (m), cabeça (graus), palma esquerda L (a mão de trás, perto
# da ponta do cabo; mundo: frente = -Y, esquerda = +X), ponto B para onde o cabo aponta (a cabeça da ferramenta)
# e distância entre as mãos: a direita fica no cabo, gap metros à frente da esquerda. No jogo o cabo passa pelas
# duas palmas (ColonyVillager), então a ferramenta acompanha as mãos em qualquer quadro.
# Capina: cabo do lado esquerdo do corpo, mão esquerda junto da cintura, a direita cruzando à frente.
#               quadro lean twist drop back head  L                    B                     gap
VILLAGER_HOE = [(0, 40, 18, 0.08, 0.10, 16, (0.25, 0.00, 1.10), (-0.04, -0.90, 0.20), 0.38),     # fim da puxada
                (14, 38, 20, 0.07, 0.10, 10, (0.25, -0.02, 1.06), (-0.10, -1.34, 0.62), 0.38),     # ergue e leva à frente
                (22, 54, 22, 0.13, 0.14, 20, (0.25, -0.03, 0.97), (-0.08, -1.18, 0.20), 0.38),     # crava
                (27, 55, 22, 0.13, 0.14, 21, (0.25, -0.03, 0.96), (-0.08, -1.17, 0.19), 0.38),
                (48, 40, 18, 0.08, 0.10, 16, (0.25, 0.00, 1.10), (-0.04, -0.90, 0.20), 0.38)]     # puxa até os pés
VILLAGER_HOE_POLE = (0.3, 0.7, -0.65)     # cotovelos para baixo e para trás
VILLAGER_CHOP_POLE = (0.7, 0.25, -0.65)   # cotovelos para fora
# Golpe de machado/picareta: armado por cima do ombro direito e descido à frente, na altura do tronco da árvore.
VILLAGER_CHOP = [(0, 16, 0, 0.04, 0.0, 10, (0.02, -0.26, 1.10), (-0.04, -0.71, 0.88), 0.19),       # pronto
                 (12, 4, -14, 0.0, -0.02, -8, (-0.12, -0.20, 1.58), (-0.10, 0.10, 2.10), 0.19),     # armado no alto
                 (15, 4, -15, 0.0, -0.02, -8, (-0.12, -0.19, 1.59), (-0.10, 0.14, 2.09), 0.19),
                 (20, 28, 4, 0.07, 0.03, 20, (0.00, -0.32, 1.07), (-0.03, -0.86, 0.75), 0.19),      # golpe
                 (24, 29, 5, 0.08, 0.03, 20, (0.00, -0.32, 1.06), (-0.03, -0.86, 0.73), 0.19),
                 (36, 16, 0, 0.04, 0.0, 10, (0.02, -0.26, 1.10), (-0.04, -0.71, 0.88), 0.19)]


def two_hand_cycle(arm, P, joints, spec, pole, step=2):
    """Chaves de bake_clip para um ciclo de trabalho com as duas mãos num cabo (spec como VILLAGER_HOE):
    os parâmetros são interpolados (smoothstep) entre as chaves de spec e amostrados a cada step quadros; em
    cada amostra, pernas por IK até os pés parados no chão e braços por IK até as palmas no cabo, com os
    cotovelos para o lado de pole (o do braço esquerdo; o direito espelha em X). Braço e
    antebraço formam uma dobradiça (hinge_frame, sem torção) e as mãos fecham em volta do cabo."""
    bones = arm.data.bones
    ln = {k: bones[MIXAMO + k].length for k in ("LeftArm", "LeftForeArm", "RightArm", "RightForeArm",
                                                 "LeftUpLeg", "LeftLeg", "RightUpLeg", "RightLeg")}
    wr = {sd: joints[sd][2] for sd in ("Left", "Right")}
    palm = {sd: wr[sd] + Vector((s * 0.065, 0, -0.03)) for sd, s in (("Left", 1), ("Right", -1))}   # pose T
    az = P["ankle"].z
    ankles = {"Left": Vector((0.13, -0.1, az)), "Right": Vector((-0.13, 0.12, az))}
    feet = {"Left": Matrix.Rotation(math.radians(6), 3, 'Z'), "Right": Matrix.Rotation(math.radians(-16), 3, 'Z')}

    def sample(fr):
        for a, b in zip(spec, spec[1:]):
            if fr <= b[0]:
                u = (fr - a[0]) / float(b[0] - a[0])
                u = u * u * (3 - 2 * u)
                out = []
                for x, y in zip(a[1:], b[1:]):
                    out.append(Vector(x).lerp(Vector(y), u) if isinstance(x, tuple) else x + (y - x) * u)
                return out
        return list(spec[-1][1:])

    def key(fr, quiet=False):
        lean, twist, drop, back, head, L, B, gap = sample(fr)
        L = Vector(L)
        f = (Vector(B) - L).normalized()
        t = {"HipsLoc": (0, back, -drop), "Hips": _qx(lean * 0.3), "Spine": _qx(lean * 0.3),
             "Spine1": _qz(twist) @ _qx(lean * 0.25), "Spine2": _qx(lean * 0.15), "Neck": _qx(-lean * 0.2),
             "Head": _qx(head).to_matrix(), "LeftFoot": feet["Left"], "RightFoot": feet["Right"]}
        pose_fk(arm, t)
        bpy.context.view_layer.update()
        h = {k: arm.pose.bones[MIXAMO + k].head.copy() for k in ("LeftArm", "RightArm", "LeftUpLeg", "RightUpLeg")}
        dbg = os.environ.get("VILLAGER_DEBUG") and any(fr == k[0] for k in spec)
        for sd, s in (("Left", 1), ("Right", -1)):
            t[sd + "UpLeg"], t[sd + "Leg"] = _ik(h[sd + "UpLeg"], ankles[sd], ln[sd + "UpLeg"], ln[sd + "Leg"],
                                                 (s * 0.2, -1, 0), warn=False)
            target = L if sd == "Left" else L + f * gap
            hm = Matrix.Identity(3)
            for _ in range(6):
                w = target - hm @ (palm[sd] - wr[sd])
                up, fo = _ik(h[sd + "Arm"], w, ln[sd + "Arm"], ln[sd + "ForeArm"], (s * pole[0], pole[1], pole[2]),
                             warn=False)
                u = fo.normalized()
                u = (u - f * f.dot(u)).normalized()
                # pose T: dedos em s * X, polegar para a frente (-Y); o polegar aponta para a cabeça da ferramenta
                hm = Matrix((s * u, -f, (s * u).cross(-f))).transposed()
            miss = (w - h[sd + "Arm"]).length - (ln[sd + "Arm"] + ln[sd + "ForeArm"])
            if miss > -0.004 and not quiet:
                print("two_hand_cycle: quadro %d, braço %s sem folga (%.3f m)" % (fr, sd, miss))
            if dbg:
                print("DBG q%d %s ombro %s palma %s folga %.2f cabo %.2f" % (
                    fr, sd, tuple(round(c, 2) for c in h[sd + "Arm"]), tuple(round(c, 2) for c in target), -miss,
                    (Vector(B) - L).length - gap))
            nrm = up.cross(fo).normalized()
            t[sd + "Arm"], t[sd + "ForeArm"], t[sd + "Hand"] = hinge_frame(up, nrm, s), hinge_frame(fo, nrm, s), hm
        return t

    key(spec[0][0], True)   # a primeira avaliação da pose sai atrasada: descartada
    return [(fr, key(fr)) for fr in range(spec[0][0], spec[-1][0] + 1, step)]


def build_villager(n=1):
    L = VILLAGER_LOOKS[n]
    px = "v%d_" % n
    tunic = mat(px + "tunic", hexc(L["tunic"]), 0.95)
    tunic_d = mat(px + "tunic_d", hexc(L["tunic_d"]), 0.95)
    tunic_l = mat(px + "tunic_l", hexc(L["tunic_l"]), 0.95)
    pants = mat(px + "pants", hexc(L["pants"]), 0.95)
    skin = mat(px + "skin", hexc(L["skin"]), 0.8)
    hair = mat(px + "hair", hexc(L["hair"]), 0.9)
    lea = mat("v_lea", hexc("#7A4B2A"), 0.85)
    lea_d = mat("v_lea_d", hexc("#472A17"), 0.85)
    sole = mat("v_sole", hexc("#2A1B12"), 0.9)
    iron = mat("v_iron", hexc("#8E939B"), 0.5, 0.7)
    straw = mat("v_straw", hexc("#D9B95C"), 0.95)
    straw_d = mat("v_straw_d", hexc("#A8842F"), 0.95)
    linen = mat("v_linen", hexc("#E6DCC4"), 0.95)
    linen_d = mat("v_linen_d", hexc("#BFB294"), 0.95)
    red = mat("v_red", hexc("#A8442F"), 0.95)
    eye = mat("v_eye", hexc("#1E1512"), 0.5)
    lips = mat("v_lips", hexc("#B8705F"), 0.7)

    root = empty("Villager", (0, 0, 0))
    # ---------------- pernas: calça e botina
    for side, x in (("LegL", 0.09), ("LegR", -0.09)):
        leg = empty(side, (x, 0, 0.93), root)
        limb(side + "_Thigh", (x, 0, 0.94), (x, 0, 0.5), 0.082, 0.064, pants, sides=6, parent=leg)
        limb(side + "_Shin", (x, 0, 0.52), (x, 0, 0.2), 0.064, 0.052, pants, sides=6, parent=leg)
        boot(side, x, lea, sole, leg, top_z=0.26, cuff=lea_d)

    body = empty("Body", (0, 0, 0.93), root)
    # ---------------- túnica curta com barra, cinto
    cloth("TunicSkirt", 1.0, 0.76, 0.155, 0.215, 2 * PI, 2 * PI, [tunic, tunic_d],
          [(0.5, 0), (0.84, 0), (1.0, 1)], back=0.8, cols=12, folds=0.01, thick=0.018, parent=body)
    tbox("Chest", (0, 0, 1.2), (0.3, 0.19, 0.4), tunic, top=(1.02, 1.0), bottom=(0.92, 0.95), bevel=0.035, parent=body)
    tbox("Collar", (0, -0.094, 1.345), (0.07, 0.014, 0.11), skin, bottom=(0.25, 1), parent=body)
    for s, nm in ((1, "L"), (-1, "R")):
        tbox("CollarTrim" + nm, (s * 0.03, -0.097, 1.345), (0.016, 0.016, 0.125), tunic_d, rot=(0, -s * 0.27, 0), parent=body)
    limb("Neckline", (0, 0.008, 1.385), (0, 0.012, 1.455), 0.085, 0.056, tunic, sides=8, parent=body)
    tbox("Belt", (0, 0, 1.0), (0.325, 0.245, 0.042), lea_d, bevel=0.008, parent=body)
    tbox("Buckle", (0.0, -0.126, 1.0), (0.05, 0.012, 0.05), iron, bevel=0.005, parent=body)
    if L["extra"] == "pouch":
        pouch("Pouch", (-0.15, -0.085, 0.93), lea, lea_d, body, size=(0.09, 0.055, 0.1), rotz=-0.5)
        tbox("Patch", (0.07, -0.098, 1.14), (0.07, 0.01, 0.07), tunic_l, rot=(0, 0.2, 0), parent=body)
    elif L["extra"] == "apron":
        tbox("ApronBib", (0, -0.103, 1.17), (0.19, 0.012, 0.3), linen, top=(0.8, 1), bevel=0.003, parent=body)
        cloth("Apron", 1.02, 0.66, 0.17, 0.24, 1.7, 1.8, [linen, linen_d], [(0.85, 0), (1.0, 1)], back=-0.8, cols=6,
              folds=0.008, thick=0.012, parent=body)
        for s, nm in ((1, "L"), (-1, "R")):
            tbox("ApronStrap" + nm, (s * 0.085, -0.1, 1.36), (0.03, 0.014, 0.1), linen_d, rot=(0, s * 0.35, 0), parent=body)
    elif L["extra"] == "vest":
        for s, nm in ((1, "L"), (-1, "R")):
            tbox("Vest" + nm, (s * 0.1, -0.098, 1.2), (0.105, 0.016, 0.37), lea, bottom=(0.9, 1), bevel=0.004, parent=body)
            tbox("VestSide" + nm, (s * 0.153, 0, 1.17), (0.016, 0.2, 0.3), lea, bevel=0.004, parent=body)
            tbox("VestTrim" + nm, (s * 0.05, -0.1, 1.2), (0.014, 0.018, 0.37), lea_d, parent=body)
        tbox("VestBack", (0, 0.098, 1.2), (0.305, 0.016, 0.37), lea, bevel=0.004, parent=body)
        tbox("Scarf", (0, -0.02, 1.4), (0.2, 0.2, 0.06), red, top=(0.8, 0.8), bevel=0.016, parent=body)

    # ---------------- cabeça
    head = empty("Head", (0, 0, 1.45), body)
    # pescoço: largo na base (entra na gola), afinando até a cabeça
    limb("Neck", (0, 0.01, 1.4), (0, 0.014, 1.6), 0.056, 0.044, skin, sides=10, parent=head)
    # rosto liso desenhado, cabelo em mechas e mãos de pele contínua (anime.py), como o herói
    HH = 0.232
    fem = L["fem"]
    am = anime_mats(px, hexc(L["skin"]), hexc("#6A4526"), tuple(c * 0.75 for c in hexc(L["hair"])),
                    tuple(c * 0.35 for c in hexc(L["hair"])), hexc("#B4606A") if fem else hexc("#9A5648"))
    face = ({"eye_w": 1.08, "eye_h": 1.1, "eye_dz": -0.3, "lash": 1.0, "brow": 0.9, "brow_dz": 0.3, "nose": 0.6,
             "jaw": 0.95, "mouth_w": 0.85} if fem else
            {"eye_w": 0.95, "eye_h": 0.7, "lash": 0.8, "brow": 1.4, "brow_dz": -0.3, "nose": 1.1, "jaw": 1.06,
             "chin": 0.4, "mouth_w": 1.05})
    H = anime_head("", 1.52, HH, head, am, face)
    hm = {"hair": hair, "mid": mat(px + "hair_m", tuple(c * 0.78 for c in hexc(L["hair"])), 0.9),
          "under": mat(px + "hair_d", tuple(c * 0.55 for c in hexc(L["hair"])), 0.9)}
    if L["head"] == "":       # cabeça descoberta: cabelo curto com franja de lado
        anime_hair("", H, hm, head, {"fringe": 14, "side": 3, "back": -26, "part": -22, "sweep": 1, "top": 9,
                                     "w": 1.2, "lift": 1.4, "seed": 5 + n})
    else:                     # sob o chapéu ou o lenço: só a calota, os lados e a nuca
        anime_hair("", H, hm, head, {"top": 0, "bangs": False, "frame": False, "side": 2, "back": -32 if fem else -24,
                                     "seed": 5 + n})
    if fem:
        anime_bun("HairBun", (0, 0.105, 1.56), (0.085, 0.07, 0.075), hair, head)
    if L["head"] == "straw":   # chapéu de palha: aba larga caída e copa baixa com fita
        limb("HatBrim", (0, 0.004, 1.69), (0, 0.004, 1.715), 0.2, 0.125, straw, sides=12, flat=1.1, parent=head)
        limb("HatBrimEdge", (0, 0.004, 1.683), (0, 0.004, 1.693), 0.203, 0.203, straw_d, sides=12, flat=1.1, parent=head)
        limb("HatCrown", (0, 0.004, 1.71), (0, 0.004, 1.79), 0.094, 0.078, straw, sides=10, flat=1.2, parent=head)
        ring("HatBand", 1.725, 0.096, 0.022, red, parent=head, sides=10, flat=1.2, y=0.004)
    elif L["head"] == "kerchief":   # lenço justo cobrindo o topo, com as pontas amarradas atrás
        limb("KerchiefBand", (0, 0.004, 1.685), (0, 0.004, 1.745), 0.083, 0.087, red, sides=10, flat=1.24, parent=head)
        shell("KerchiefTop", (0, 0.004, 1.74), (0.18, 0.218, 0.12), red, cut=0.0, seg=10, rings=6, thick=0, jitter=0.003,
              seed=12, parent=head)
        for s, nm in ((1, "L"), (-1, "R")):
            tbox("KerchiefTail" + nm, (s * 0.025, 0.11, 1.65), (0.045, 0.016, 0.11), red, bottom=(0.6, 1),
                 rot=(0.25, 0, s * 0.3), bevel=0.004, parent=head)
    scale_group(head, (0, 0.01, 1.52), 1.1)
    for o in head.children:      # cabeça, cabelo e chapéu 2 cm mais baixos: o pescoço ficava comprido
        if o.type == 'MESH' and o.name != "Neck":
            o.data.transform(Matrix.Translation((0, 0, -0.02)))

    # ---------------- braços: manga arregaçada até o cotovelo, antebraço à mostra
    SH_Z, EL_Z, WR_Z = 1.38, 1.12, 0.87
    for side, sx in (("ArmR", -0.2), ("ArmL", 0.2)):
        s = 1 if sx > 0 else -1
        pv = empty(side, (sx, 0, 1.4), body)
        ex = sx + s * 0.03
        wx = sx + s * 0.045
        limb(side + "_Upper", (sx, 0, SH_Z - 0.01), (ex, 0.01, EL_Z), 0.048, 0.06, tunic, sides=7, parent=pv)
        ring(side + "_SleeveRoll", EL_Z + 0.012, 0.066, 0.04, tunic_l, parent=pv, sides=7, x=ex, y=0.01)
        limb(side + "_Fore", (ex, 0.01, EL_Z + 0.01), (wx, 0, WR_Z), 0.046, 0.036, skin, sides=6, parent=pv)
        npc_hand(side, (wx, 0, WR_Z), s, skin, pv)

    # ---------------- tudo em coordenadas de mundo, agrupado pelo pivô em que foi montado
    scn.view_layers[0].update()
    groups = {}
    for o in [o for o in coll.objects if o.type == 'MESH']:
        groups.setdefault(o.parent.name, []).append(o)
        o.data.transform(o.matrix_world)
        o.parent = None
        o.matrix_world = Matrix.Identity(4)
    for e in [o for o in coll.objects if o.type == 'EMPTY']:
        bpy.data.objects.remove(e, do_unlink=True)

    hip_z = 0.93
    Z = (0, 0, 1)
    for side, sd in (("LegL", "Left"), ("LegR", "Right")):
        weigh(groups[side], Z, [(0.1, sd + "Foot"), (0.16, sd + "Leg"), (0.47, sd + "Leg"), (0.55, sd + "UpLeg")])
    # túnica, cinto, avental, colete: o mesmo campo (peças coladas se movem juntas)
    torso = [(0.98, "Hips"), (1.06, "Spine"), (1.17, "Spine1"), (1.3, "Spine2")]
    weigh_by(groups["Body"], robe_field(hip_z, 0.66, torso, legs=0.6))
    neck = [o for o in groups["Head"] if o.name == "Neck"]
    weigh(neck, Z, [(1.42, "Spine2"), (1.47, "Neck"), (1.52, "Neck"), (1.57, "Head")])
    weigh([o for o in groups["Head"] if o not in neck], Z, [(0.0, "Head")])
    top = max(v.co.z for o in groups["Head"] if not o.name.startswith("Hat") for v in o.data.vertices)

    # braços girados em volta do ombro e do cotovelo da pose caída até a pose T
    joints, turn = {}, {}
    for side, sx, sd in (("ArmR", -0.2, "Right"), ("ArmL", 0.2, "Left")):
        s = 1 if sx > 0 else -1
        sh = Vector((sx, 0, SH_Z))
        el = Vector((sx + s * 0.03, 0.01, EL_Z))
        wr = Vector((sx + s * 0.045, 0, WR_Z))
        parts = {o.name[len(side):]: o for o in groups[side]}
        upper = [parts["_Upper"]]
        fore = [parts[k] for k in ("_SleeveRoll", "_Fore")]
        palm = [parts["_Hand"]]              # mão aberta de pele contínua (npc_hand)
        assert len(upper) + len(fore) + len(palm) == len(groups[side])
        tx = Vector((s, 0, 0))
        r_up = (el - sh).normalized().rotation_difference(tx)
        r_fo = (wr - el).normalized().rotation_difference(tx)
        el_t = sh + r_up @ (el - sh)
        wr_t = el_t + r_fo @ (wr - el)
        for o in upper:
            for v in o.data.vertices:
                v.co = sh + r_up @ (v.co - sh)
        for o in fore + palm:
            for v in o.data.vertices:
                v.co = el_t + r_fo @ (v.co - el)
        # a manga cruza o cotovelo em gradiente; o rolo da manga e o antebraço seguem o ForeArm
        weigh(upper, tx, [(abs(el_t.x) - 0.05, sd + "Arm"), (abs(el_t.x) + 0.01, sd + "ForeArm")])
        weigh(fore, Z, [(0.0, sd + "ForeArm")])
        weigh(palm, Z, [(0.0, sd + "Hand")])
        joints[sd] = (sh, el_t, wr_t)
        turn[sd] = (r_up, r_fo)

    body = join_objs("Villager", [o for o in coll.objects if o.type == 'MESH'])
    P = {"hip": Vector((0.09, 0, hip_z)), "knee": Vector((0.09, 0, 0.5)), "ankle": Vector((0.09, 0, 0.1))}
    arm = mixamo_rig([body], P, joints, hip_z, top, spine=VILLAGER_SPINE)

    down = {}
    for sd in ("Left", "Right"):
        r_up, r_fo = turn[sd]
        down[sd + "Arm"] = r_up.inverted().to_matrix()
        down[sd + "ForeArm"] = down[sd + "Hand"] = r_fo.inverted().to_matrix()
    fps = scn.render.fps
    scn.render.fps = 30
    bake_clip(arm, "arms_down", [(0, down)])
    # provisórios: o build_npc_mixamo.gd troca pelos do Mixamo quando houver villager_hoe.fbx / villager_chop.fbx
    bake_clip(arm, "hoe", two_hand_cycle(arm, P, joints, VILLAGER_HOE, VILLAGER_HOE_POLE))
    bake_clip(arm, "chop", two_hand_cycle(arm, P, joints, VILLAGER_CHOP, VILLAGER_CHOP_POLE))
    g_smooth([o for o in scn.objects if o.type == 'MESH'])
    export("villager_%d" % n, export_animations=True, export_skins=True, export_animation_mode='NLA_TRACKS')
    scn.render.fps = fps


# O goblin e o esqueleto ficam em monsters.py.


# ================================================================== FERREIRO (NPC com esqueleto)
# Primeiro personagem com Armature: peças no estilo do Bram/Mira (limb/tbox/loft, shading flat), montadas
# em pose T (braços em ±X, palmas para baixo), juntadas numa malha só e ponderadas por script: cada peça
# 100% no seu osso; manga, calça, tronco e pescoço (que cruzam juntas) com gradiente entre os dois ossos.
# Ossos com nomes do Mixamo (mixamorig:*) para o retarget pelo perfil humanoide do Godot (rig.py).
# O martelo ("Hammer") e a tenaz ("Tongs") são objetos à parte, sem pesos, com o pivô no punho de cada mão.
# Clipes provisórios (work_hammer, work_pause, idle, talk) em keyframes de rotação (o work_hammer também move
# o quadril), uma faixa NLA cada.
# Barra em brasa deitada na bigorna, nas coordenadas do ferreiro no Blender (frente = -Y, esquerda = +X):
# a mesma WorkBar de props.build_anvil com a bigorna em Blacksmith.ANVIL_OFFSET/ANVIL_YAW (blacksmith.gd).
# A face do martelo bate no topo da barra em BS_STRIKE (o StrikePoint); a tenaz segura a ponta fria.
BS_BAR_HOT, BS_BAR_COLD = Vector((-0.257, -0.635, 0.81)), Vector((-0.02, -0.41, 0.81))
BS_STRIKE = Vector((-0.22, -0.6, 0.82))
BS_TONGS_GRIP = Vector((0.2, -0.27, 0.92))   # punho esquerdo, parado no ciclo inteiro
# martelo na mão direita (pose T): girado em volta do eixo de dobra do punho (Z), cabo saindo para a frente e
# inclinado na direção dos dedos (-X)
BS_HAMMER_IN_HAND = Matrix.Rotation(math.radians(-30), 3, 'Z')


def smith_cycle(arm, P, joints, grips):
    """Chaves do work_hammer: tronco inclinado sobre a bigorna, pé esquerdo à frente, joelhos soltos, a mão
    esquerda parada segurando a tenaz na ponta fria da barra e a direita levando o martelo num arco no plano
    vertical sobre a bigorna até a face bater plana em BS_STRIKE. Braços e pernas por IK de dois ossos sobre
    a pose do tronco de cada chave. Cria também a tenaz ("Tongs", pivô no punho esquerdo, pose T)."""
    bones = arm.data.bones
    ln = {n: bones[MIXAMO + n].length for n in ("LeftArm", "LeftForeArm", "RightArm", "RightForeArm",
                                                 "LeftUpLeg", "LeftLeg", "RightUpLeg", "RightLeg")}
    wr = {sd: joints[sd][2] for sd in ("Left", "Right")}
    face_t = grips["Right"] + BS_HAMMER_IN_HAND @ Vector((-0.10, -0.33, 0))   # centro da face do martelo na pose T
    ankle_z = P["ankle"].z
    ankles = {"Left": Vector((0.12, -0.08, ankle_z)), "Right": Vector((-0.14, 0.1, ankle_z))}
    feet = {"Left": Matrix.Rotation(math.radians(8), 3, 'Z'), "Right": Matrix.Rotation(math.radians(-14), 3, 'Z')}

    def heads(t):
        pose_fk(arm, t)
        bpy.context.view_layer.update()
        return {n: arm.pose.bones[MIXAMO + n].head.copy() for n in ("LeftArm", "RightArm", "LeftUpLeg", "RightUpLeg")}

    def torso(lean, twist, drop, head):
        return {"HipsLoc": (0, 0.03 + lean * 0.0015, -drop), "Hips": _qx(lean * 0.15), "Spine": _qx(lean * 0.3),
                "Spine1": _qz(twist) @ _qx(lean * 0.32), "Spine2": _qx(lean * 0.23), "Neck": _qx(6),
                "Head": _qx(head).to_matrix(), "LeftFoot": feet["Left"], "RightFoot": feet["Right"]}

    def limbs(t, lh):
        """Completa t com pernas e braço esquerdo na tenaz (o direito fica com key())."""
        h = heads(t)
        for sd, s in (("Left", 1), ("Right", -1)):
            t[sd + "UpLeg"], t[sd + "Leg"] = _ik(h[sd + "UpLeg"], ankles[sd], ln[sd + "UpLeg"], ln[sd + "Leg"],
                                                 (s * 0.15, -1, 0))
        wl = BS_TONGS_GRIP - lh @ (grips["Left"] - wr["Left"])
        t["LeftArm"], t["LeftForeArm"] = _ik(h["LeftArm"], wl, ln["LeftArm"], ln["LeftForeArm"], (0.6, 0.5, -0.6))
        t["LeftHand"] = lh
        return t, h

    # mão esquerda: punho fechado em volta da tenaz, com a mão seguindo o antebraço (o cabo cruza o punho)
    dt = (BS_BAR_COLD - BS_TONGS_GRIP).normalized()
    lh = Matrix.Identity(3)
    for _ in range(5):
        h = heads(torso(24, 3, 0.04, 40))
        wl = BS_TONGS_GRIP - lh @ (grips["Left"] - wr["Left"])
        up, fo = _ik(h["LeftArm"], wl, ln["LeftArm"], ln["LeftForeArm"], (0.6, 0.5, -0.6), warn=False)
        u = fo.normalized()
        u = (u - dt * dt.dot(u)).normalized()
        lh = Matrix((u, -dt, u.cross(-dt))).transposed()

    def frame(d, n):
        """Orientação absoluta (relativa à pose T) de um osso do braço direito apontando para d com o eixo da
        dobra em n. Na pose T o braço aponta para -X e o cotovelo dobra para a frente (-Y): eixo +Z."""
        d = d.normalized()
        return Matrix((-d, d.cross(n), n)).transposed()

    def arm_ik(sh, w, n):
        """Braço direito do ombro sh ao punho w dobrando no plano de normal n (perpendicular a sh->w): o
        cotovelo vai para d x n (para trás com o punho embaixo, para a frente com ele no alto)."""
        d = (w - sh).normalized()
        return _ik(sh, w, ln["RightArm"], ln["RightForeArm"], d.cross(n))

    def key(lean, twist, drop, head, tilt=0.0, wrist=0.0, grip=None, face=None):
        """Braço direito como uma cadeia de dobradiças num plano só (ombro, cotovelo, punho e martelo): braço,
        antebraço e mão têm o mesmo eixo de dobra, a normal n do plano. O cotovelo acompanha o antebraço, a
        mão não torce em volta dele e o punho só dobra dentro do plano.
        grip: punho em grip com o punho dobrado wrist graus (+ = martelo armado para trás, - = batendo); o plano
        é o vertical do golpe girado tilt graus em volta do eixo vertical (cotovelo para fora).
        face: a batida, face do martelo em face virada para baixo e cabo na horizontal; o rumo do cabo é o
        que deixa a mão no mesmo plano vertical que o ombro e o punho."""
        t, h = limbs(torso(lean, twist, drop, head), lh)
        sh = h["RightArm"]
        down = Vector((0, 0, -1))
        if face is not None:
            best = None
            for i in range(-80, 81):
                nh = Quaternion((0, 0, 1), math.radians(i * 0.5)) @ Vector((-1, 0, 0))
                rh = frame(down, nh) @ BS_HAMMER_IN_HAND.inverted()   # a face (não a mão) para baixo
                w = face - rh @ (face_t - wr["Right"])
                d = w - sh
                na = Vector((d.y, -d.x, 0)).normalized()   # normal do plano vertical por ombro e punho
                if na.x > 0:
                    na = -na
                err = nh.angle(na)
                if best is None or err < best[0]:
                    best = (err, nh, rh, w)
            _, n, rh, w = best
        else:
            nd = Quaternion((0, 0, 1), math.radians(tilt)) @ Vector((-1, 0, 0))
            fo = Vector((0, -0.5, -0.85))
            n = nd
            for _ in range(10):
                rh = frame(Quaternion(n, math.radians(wrist)) @ fo.normalized(), n)
                w = Vector(grip) - rh @ (grips["Right"] - wr["Right"])
                d = (w - sh).normalized()
                n = (nd - d * d.dot(nd)).normalized()
                up, fo = arm_ik(sh, w, n)
            rh = frame(Quaternion(n, math.radians(wrist)) @ fo.normalized(), n)
        up, fo = arm_ik(sh, w, n)
        t["RightArm"], t["RightForeArm"], t["RightHand"] = frame(up, n), frame(fo, n), rh
        return t

    keys = [(0, key(16, -6, 0.02, 30, -20, -40, grip=(-0.33, -0.02, 1.66))),
            (4, key(15, -7, 0.015, 30, -20, -32, grip=(-0.33, 0.0, 1.68))),
            (8, key(19, -2, 0.025, 34, -10, 10, grip=(-0.27, -0.28, 1.36))),
            (11, key(22, 2, 0.035, 38, 0, -20, grip=(-0.23, -0.3, 1.1))),
            (13, key(24, 3, 0.04, 40, face=BS_STRIKE)),
            (16, key(23, 2, 0.04, 40, 0, -25, grip=(-0.22, -0.26, 1.01))),
            (22, key(20, 0, 0.035, 38, 0, 0, grip=(-0.22, -0.25, 1.17))),
            (29, key(17, -4, 0.025, 33, -15, 0, grip=(-0.32, -0.18, 1.46)))]
    keys.append((36, keys[0][1]))

    # tenaz: modelada na pose da batida (cabos saindo do punho esquerdo, mordentes na ponta fria da barra)
    # e levada para a pose T pela orientação/posição da mão esquerda (fixas no ciclo)
    iron = bpy.data.materials["b_iron"]
    iron_d = bpy.data.materials["b_leather_d"]
    b = (BS_BAR_HOT - BS_BAR_COLD).normalized()
    jaw = BS_BAR_COLD + b * 0.04
    piv = BS_BAR_COLD - dt * 0.035
    e = dt.cross(Vector((0, 0, 1))).cross(dt).normalized()   # perpendicular ao cabo, quase vertical
    side = dt.cross(e).normalized()
    g = BS_TONGS_GRIP
    tg = [limb("TongsReinA", g - dt * 0.08 + e * 0.012, piv + e * 0.006, 0.0075, 0.0065, iron, sides=5),
          limb("TongsReinB", g - dt * 0.08 - e * 0.012, piv - e * 0.006, 0.0075, 0.0065, iron, sides=5),
          limb("TongsRivet", piv - side * 0.016, piv + side * 0.016, 0.009, 0.009, iron_d, sides=6),
          limb("TongsJawA", piv + e * 0.008, jaw + Vector((0, 0, 0.017)), 0.008, 0.007, iron, sides=5),
          limb("TongsJawB", piv - e * 0.008, jaw - Vector((0, 0, 0.017)), 0.008, 0.007, iron, sides=5)]
    tongs = join_objs("Tongs", tg)
    wl = BS_TONGS_GRIP - lh @ (grips["Left"] - wr["Left"])
    to_t = Matrix.Translation(wr["Left"]) @ lh.inverted().to_4x4() @ Matrix.Translation(-wl)
    mw = tongs.matrix_world.copy()
    for v in tongs.data.vertices:
        v.co = to_t @ (mw @ v.co)
    tongs.matrix_world = Matrix.Identity(4)
    tongs.data.transform(Matrix.Translation(-grips["Left"]))
    tongs.location = grips["Left"]
    return keys


def build_blacksmith():
    shirt = mat("b_shirt", hexc("#C9B48C"), 0.95)
    shirt_d = mat("b_shirt_d", hexc("#9A845E"), 0.95)
    pants = mat("b_pants", hexc("#4E4136"), 0.95)
    apron = mat("b_apron", hexc("#8A5A32"), 0.8)
    apron_d = mat("b_apron_d", hexc("#5A381C"), 0.85)
    apron_l = mat("b_apron_l", hexc("#A87444"), 0.8)
    glove = mat("b_glove", hexc("#6B4524"), 0.85)
    glove_d = mat("b_glove_d", hexc("#43291A"), 0.85)
    lea_d = mat("b_leather_d", hexc("#3A2412"), 0.85)
    sole = mat("b_sole", hexc("#21160E"), 0.9)
    iron = mat("b_iron", hexc("#5D6168"), 0.45, 0.8)
    skin = mat("b_skin", hexc("#D08A62"), 0.8)
    skin_d = mat("b_skin_d", hexc("#B0704C"), 0.8)
    hair = mat("b_hair", hexc("#5A2C16"), 0.9)
    hair_d = mat("b_hair_d", hexc("#3A1C0E"), 0.9)
    wood = mat("b_wood", hexc("#7A5030"), 0.9)
    steel = mat("b_steel", hexc("#8C929C"), 0.35, 0.85)

    P = body_proportions(height=1.8, heads=7.8, shoulders=1.15, chest=1.2, waist=1.15, hips=1.05, limbs=1.2,
                         hands=1.25, feet=1.12)
    hip_z = P["pelvis"].z
    seen = set()

    def take():
        """Malhas criadas desde a última chamada (para ponderar por região)."""
        new = [o for o in coll.objects if o.type == 'MESH' and o.name not in seen]
        seen.update(o.name for o in new)
        return new

    Z = (0, 0, 1)
    M = dict(shirt=shirt, shirt_d=shirt_d, pants=pants, apron=apron, apron_d=apron_d, apron_l=apron_l, glove=glove,
             glove_d=glove_d, lea_d=lea_d, sole=sole, iron=iron, skin=skin, skin_d=skin_d)
    # ---------------- corpo liso (anime_body.py): pernas e botas, tronco, cinto e avental
    doran_legs(P, M, take)
    doran_torso(P, M, take)

    # ---------------- cabeça: rosto largo, sobrancelha pesada, cabelo curto, barba cheia
    face_mats = {"skin": skin, "lip": mat("b_lip", hexc("#A55E4A"), 0.7), "sclera": mat("b_sclera", hexc("#EAE2D6"), 0.4),
                 "iris": mat("b_iris", hexc("#4A3220"), 0.3), "pupil": mat("b_pupil", hexc("#1E1410"), 0.5),
                 "mouth": mat("b_mouth", hexc("#7A3E30"), 0.8), "brow": hair, "lash": hair_d}
    H = anime_head("", 1.54, 0.238, None,
                   anime_mats("b", hexc("#D08A62"), hexc("#4A3220"), hexc("#5A2C16"), hexc("#3A1C0E"), hexc("#7A3E30")),
                   {"width": 1.1, "jaw": 1.18, "eye_h": 0.58, "eye_w": 0.88, "lash": 0.65, "brow": 2.6, "brow_dz": -0.4,
                    "brow_tilt": 0.55, "nose": 1.3})
    # cabelo curto e barba cheia desenhados (anime.py): mechas largas e lisas em camadas
    hm = {"hair": hair, "mid": mat("b_hair_mid", hexc("#4A2412"), 0.9), "under": hair_d}
    anime_hair("", H, hm, None, {"back": -20})
    anime_beard("", H, hm, None)
    weigh(take(), Z, [(0.0, "Head")])

    # ---------------- braços fortes na pose T: manga arregaçada, antebraço à mostra, luva de couro grossa
    joints, grips = doran_arms(P, M, take)

    if os.environ.get("PART_TRIS"):     # custo por peça, antes de juntar
        for o in coll.objects:
            if o.type == 'MESH':
                print("TRIS_PART", o.name, sum(len(q.vertices) - 2 for q in o.data.polygons))
    body = join_objs("Blacksmith", [o for o in coll.objects if o.type == 'MESH'])

    # ---------------- martelo (objeto à parte, pivô no punho da mão direita, cabo para a frente)
    # A face da cabeça aponta para fora, quase na direção da mão (-X): é para onde a mão empurra o martelo ao
    # bater (desvio ulnar do punho). O cabo sai do punho inclinado para a frente da mão (BS_HAMMER_IN_HAND),
    # como numa pegada de verdade: na batida a mão não precisa dobrar tanto para a face descer plana.
    g = grips["Right"]
    side = (0, math.pi / 2, 0)   # caixas modeladas em pé (eixo Z) deitadas no eixo X
    hm = [limb("HammerHandle", g + Vector((0, 0.09, 0)), g + Vector((0, -0.33, 0)), 0.016, 0.014, wood, sides=6),
          limb("HammerGrip", g + Vector((0, 0.07, 0)), g + Vector((0, -0.06, 0)), 0.02, 0.02, lea_d, sides=6),
          tbox("HammerHead", g + Vector((0, -0.33, 0)), (0.06, 0.065, 0.17), steel, top=(0.85, 0.85), bevel=0.008,
               rot=side),
          tbox("HammerFace", g + Vector((-0.09, -0.33, 0)), (0.07, 0.075, 0.02), iron, bevel=0.004, rot=side),
          limb("HammerWedge", g + Vector((0.085, -0.33, 0)), g + Vector((0.1, -0.33, 0)), 0.02, 0.012, iron, sides=4)]
    hammer = join_objs("Hammer", hm)
    hammer.data.transform(Matrix.Translation(-g))
    hammer.data.transform(BS_HAMMER_IN_HAND.to_4x4())
    hammer.location = g

    # ---------------- esqueleto em pose T, nomes do Mixamo
    arm = mixamo_rig([body], P, joints, hip_z, H["top"])

    # ---------------- clipes provisórios (direções de mundo: frente = -Y, esquerda = +X)
    def pose(base, **over):
        d = dict(base)
        d.update(over)
        return d

    down = {"LeftArm": (0.28, 0.02, -0.96), "LeftForeArm": (0.2, -0.22, -0.95),
            "RightArm": (-0.28, 0.02, -0.96), "RightForeArm": (-0.15, -0.45, -0.88)}
    work_hammer = smith_cycle(arm, P, joints, grips)
    brow = pose(down, RightArm=(-0.5, -0.7, 0.3), RightForeArm=(0.85, 0.17, 0.5), RightHand=(0.9, 0.3, 0.2),
                Spine1=_qx(-5), Spine2=_qx(-3), Head=_qx(-8))
    wipe = pose(brow, RightForeArm=(0.95, 0.05, 0.3), RightHand=(1.0, 0.2, 0.0), Head=_qx(-10))
    breathe = pose(down, Spine1=_qx(-1.5), Spine2=_qx(-1), Neck=_qx(1.5), LeftArm=(0.3, 0.02, -0.95),
                   RightArm=(-0.3, 0.02, -0.95))
    gest_a = pose(down, LeftArm=(0.45, -0.35, -0.82), LeftForeArm=(0.25, -0.9, 0.35), LeftHand=(0.2, -0.9, 0.4),
                  Head=_qz(6) @ _qx(4))
    gest_b = pose(down, LeftArm=(0.55, -0.2, -0.8), LeftForeArm=(0.6, -0.7, 0.4), LeftHand=(0.6, -0.6, 0.5),
                  Head=_qz(-5) @ _qx(-3), Spine2=_qz(-4))
    gest_c = pose(down, LeftArm=(0.4, -0.3, -0.86), LeftForeArm=(0.3, -0.9, 0.2), Head=_qx(5))
    fps = scn.render.fps
    scn.render.fps = 30
    bake_clip(arm, "work_hammer", work_hammer)
    bake_clip(arm, "work_pause", [(0, down), (18, brow), (38, wipe), (55, brow), (75, down)])
    bake_clip(arm, "idle", [(0, down), (45, breathe), (90, down)])
    bake_clip(arm, "talk", [(0, down), (20, gest_a), (45, gest_b), (70, gest_c), (90, down)])
    g_smooth([o for o in scn.objects if o.type == 'MESH'])
    export("blacksmith", export_animations=True, export_skins=True, export_animation_mode='NLA_TRACKS')
    scn.render.fps = fps
