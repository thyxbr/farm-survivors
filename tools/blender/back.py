# Peças das costas (espaço "back"): asas e capas com modelo próprio.
# Executado por exec() dentro de build_assets.py, depois de gear.py (usa gm, g_spline, g_curved_tube,
# g_smooth_mesh, g_pipe, bake_ao, cel_paint) e de armory.py (BVHTree, TOUCH).
#
# Cada peça vira assets/models/back/<estilo>.glb. Frente do personagem = -Y, costas = +Y, pés em Z=0.
# Nós do GLB: "Back" (parado, na origem do personagem) com o suporte; "WingL" e "WingR" são os pivôs na
# raiz de cada asa (scripts/player/back_wings.gd gira os dois para bater as asas).
# Materiais terminados em _flat levam a pintura anime de cel_paint (claro / base / sombra por face).
import math
from mathutils import Vector

BK_ROOT_Z = 1.40          # altura da raiz das asas (entre as omoplatas)
BK_BACK_Y = 0.105         # superfície das costas nessa altura


def bk_world_verts(o):
    off = _wloc(o.parent)
    return [v.co + off for v in o.data.vertices]


def bk_loose(asset):
    """Como loose_parts de armory.py, mas em coordenadas do mundo (as peças têm pivôs diferentes)."""
    objs = [o for o in coll.all_objects if o.type == 'MESH']
    verts = {o.name: bk_world_verts(o) for o in objs}
    trees = {o.name: BVHTree.FromPolygons(verts[o.name], [tuple(p.vertices) for p in o.data.polygons]) for o in objs}
    group = {o.name: i for i, o in enumerate(objs)}
    for i, a in enumerate(objs):
        for b in objs[i + 1:]:
            if group[a.name] == group[b.name]:
                continue
            hit = bool(trees[a.name].overlap(trees[b.name]))
            if not hit:
                hit = any(trees[b.name].find_nearest(v, TOUCH)[0] is not None for v in verts[a.name]) or \
                    any(trees[a.name].find_nearest(v, TOUCH)[0] is not None for v in verts[b.name])
            if hit:
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
    return comps


def bk_join(name, parent):
    """Junta numa malha só todas as malhas filhas de parent (menos chamadas de desenho no jogo)."""
    objs = [o for o in coll.all_objects if o.type == 'MESH' and o.parent == parent]
    if not objs:
        return None
    mats = []
    bm = bmesh.new()
    for o in objs:
        me = o.data
        idx = []
        for m in me.materials:
            if m not in mats:
                mats.append(m)
            idx.append(mats.index(m))
        # from_mesh leva junto o UV do pano (o shader animado das capas precisa dele); o índice de material
        # é trocado antes para o da lista comum
        for p in me.polygons:
            p.material_index = idx[p.material_index]
        bm.from_mesh(me)
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    ob.parent = parent
    return ob


def bk_feather(name, base, d, n, length, width, mats, parent, tip_from=2.0, bend=0.0, segs=6, thick=0.013,
               cup=0.0, twist=0.0, shade_to=0.0, blade=False):
    """Pena em forma de folha, seção em losango (a quina do meio é a haste): sai de base na direção d, deitada no plano de normal n.
    mats = (corpo, ponta[, sombra]); as faces depois de tip_from (0..1 do comprimento) usam o material da ponta
    e as de antes de shade_to o da sombra (a faixa escura que a fileira de cima projeta na de baixo).
    bend curva a pena para o lado, cup a arqueia para fora do plano, twist gira a lâmina (rad)."""
    d = Vector(d).normalized()
    n = Vector(n).normalized()
    side = n.cross(d).normalized()
    n = d.cross(side).normalized()
    if twist:
        side, n = (side * math.cos(twist) + n * math.sin(twist)), (n * math.cos(twist) - side * math.sin(twist))
    bm = bmesh.new()
    rings, ts = [], []
    for i in range(segs):
        t = 1.0 - (1.0 - i / segs) ** 1.5
        c = Vector(base) + d * length * t + side * bend * length * t * t + n * cup * length * math.sin(math.pi * t)
        if blade:      # lâmina: lados retos e ponta em bisel (asas mecânicas, cristais)
            prof = min(1.0, 0.6 + 2.0 * t) * min(1.0, (1.0 - t) / 0.22 + 0.05)
        else:
            prof = min(1.0, 0.34 + 1.7 * t) * math.sqrt(max(0.0, 1.0 - max(0.0, (t - 0.55) / 0.45) ** 2.4))
        w = width * prof
        th = thick * (1.0 - 0.7 * t)
        rings.append([bm.verts.new(c + side * w * math.cos(a) + n * th * math.sin(a))
                      for a in (k * math.pi / 2 for k in range(4))])
        ts.append(t)
    tip = bm.verts.new(Vector(base) + d * length + side * bend * length)
    for i in range(segs - 1):
        for j in range(4):
            f = bm.faces.new((rings[i][j], rings[i][(j + 1) % 4], rings[i + 1][(j + 1) % 4], rings[i + 1][j]))
            f.material_index = 1 if ts[i] >= tip_from else (2 if ts[i + 1] <= shade_to else 0)
    for j in range(4):
        f = bm.faces.new((rings[-1][j], rings[-1][(j + 1) % 4], tip))
        f.material_index = 1 if tip_from <= 1.0 else 0
    bm.faces.new(rings[0][::-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.translate(bm, vec=-_wloc(parent), verts=bm.verts)
    ob = _finish(name, bm, mats[0], parent, smooth=True)
    ob.data.materials.append(mats[1])
    if len(mats) > 2:
        ob.data.materials.append(mats[2])
    return ob


def bk_lerp(vals, t):
    """Interpola a lista vals em t (0..1)."""
    x = max(0.0, min(1.0, t)) * (len(vals) - 1)
    k = min(int(x), len(vals) - 2)
    return vals[k] + (vals[k + 1] - vals[k]) * (x - k)


# ------------------------------------------------------------------ asas seráficas
def seraph_mats():
    return dict(
        white=gm("sr_white_flat", "#F3F0EA", 0.8),
        shade=gm("sr_shade_flat", "#C4BEDD", 0.8),
        cream=gm("sr_cream_flat", "#F0DDA6", 0.8),
        gold=gm("sr_gold_flat", "#E9AE3C", 0.5),
        gold_d=gm("sr_goldd_flat", "#B77F2C", 0.55),
        gem=mat("sr_gem", hexc("#62CCFF"), 0.25, 0.0, emit=hexc("#62CCFF"), strength=2.2),
        glow=mat("sr_glow", hexc("#FFE9A8"), 0.4, 0.0, emit=hexc("#FFD56B"), strength=1.6),
    )


def seraph_wing(M, piv, s, k=1.0, flame=0.0):
    """Uma asa de penas: s = 1 esquerda (+X), -1 direita. k = escala geral. flame entorta as penas longas
    para lados alternados, como labaredas (asas de fênix)."""
    sw = math.radians(24)                      # asa aberta um pouco para trás
    U = Vector((s * math.cos(sw), math.sin(sw), 0))
    V = Vector((0, 0, 1))
    N = Vector((-s * math.sin(sw), math.cos(sw), 0))
    root = _wloc(piv)
    n = "L" if s > 0 else "R"

    def pt(u, v, depth=0.0):
        return root + U * u * k + V * v * k + N * depth

    def dirv(deg):
        a = math.radians(deg)
        return U * math.cos(a) + V * math.sin(a)

    # braço da asa: sobe e abre até o punho, depois a mão desce um pouco
    arm_uv = [(-0.02, -0.02), (0.06, 0.17), (0.16, 0.38), (0.28, 0.54), (0.41, 0.61), (0.53, 0.59), (0.62, 0.50)]
    arm = g_spline([Vector((u, v, 0)) for u, v in arm_uv], 36)

    def arm_at(t):
        p = arm[int(round(max(0.0, min(1.0, t)) * 36))]
        return p.x, p.y

    # penas longas (primárias) na mão: abrem em leque de baixo para fora
    for i in range(10):
        t = i / 9
        u, v = arm_at(0.60 + 0.40 * t)
        bk_feather("Prim%s%d" % (n, i), pt(u, v, 0.004 + 0.002 * i), dirv(bk_lerp([-90, -82, -72, -60, -47, -36], t)), N,
                   bk_lerp([0.96, 1.04, 1.06, 1.0, 0.9, 0.76, 0.58], t) * k, 0.08 * k, (M["white"], M["gold"], M["shade"]),
                   piv, tip_from=0.72, shade_to=0.58, bend=-0.05 * s * (1 - t) + flame * s * (1 if i % 2 else -1),
                   cup=0.03, twist=0.10 * s, segs=7)
    # penas médias (secundárias) no braço: caem para baixo, mais curtas perto do corpo
    for i in range(9):
        t = i / 8
        u, v = arm_at(0.06 + 0.54 * t)
        bk_feather("Sec%s%d" % (n, i), pt(u, v, 0.014), dirv(bk_lerp([-104, -96, -90, -85], t)), N,
                   bk_lerp([0.50, 0.68, 0.82, 0.92], t) * k, 0.088 * k, (M["white"], M["cream"], M["shade"]),
                   piv, tip_from=0.84, shade_to=0.58, bend=0.04 * s + flame * 0.7 * s * (1 if i % 2 else -1), cup=0.035,
                   twist=0.12 * s)
    # coberteiras: duas fileiras por cima, cobrindo a base das penas longas
    for i in range(13):
        t = i / 12
        u, v = arm_at(0.04 + 0.92 * t)
        bk_feather("CovA%s%d" % (n, i), pt(u, v, 0.026), dirv(bk_lerp([-102, -94, -88, -76, -58, -40], t)), N,
                   bk_lerp([0.30, 0.42, 0.48, 0.46, 0.36, 0.26], t) * k, 0.066 * k, (M["white"], M["cream"], M["shade"]),
                   piv, tip_from=0.62, shade_to=0.45, cup=0.05, twist=0.14 * s, segs=5)
    for i in range(12):
        t = i / 11
        u, v = arm_at(0.06 + 0.86 * t)
        bk_feather("CovB%s%d" % (n, i), pt(u, v, 0.036), dirv(bk_lerp([-100, -92, -86, -72, -54, -38], t)), N,
                   bk_lerp([0.16, 0.22, 0.25, 0.23, 0.18, 0.14], t) * k, 0.054 * k, (M["cream"], M["gold"]),
                   piv, tip_from=0.7, cup=0.06, twist=0.14 * s, segs=4)
    # braço dourado, liso, por cima das bases
    path = [pt(p.x, p.y, 0.022) for p in arm[::2]]
    radii = [(bk_lerp([0.036, 0.040, 0.034, 0.024, 0.012], i / 18) * k,
              bk_lerp([0.034, 0.036, 0.030, 0.022, 0.011], i / 18) * k) for i in range(19)]
    g_smooth_mesh("Arm" + n, g_curved_tube(path, radii, sides=10, side0=N), M.get("arm", M["gold"]), piv)
    # friso mais escuro ao longo do braço e três gemas engastadas
    g_pipe("ArmTrim" + n, [pt(*arm_at(t), 0.022 + bk_lerp([0.034, 0.036, 0.030, 0.022], t) * k) for t in
                           [j / 14 * 0.9 for j in range(15)]], 0.007 * k, M["gold_d"], piv, sides=6)
    for j, t in enumerate((0.16, 0.36, 0.56)):
        u, v = arm_at(t)
        r = bk_lerp([0.036, 0.040, 0.034, 0.024, 0.012], t) * k
        c = pt(u, v, 0.022 + r)
        seat = [c + (U * math.cos(a) + V * math.sin(a)) * 0.021 * k for a in (q * math.pi / 5 for q in range(10))]
        g_pipe("GemSeat%s%d" % (n, j), seat, 0.005 * k, M["gold_d"], piv, sides=6, loop=True)
        bk_feather("Gem%s%d" % (n, j), c - V * 0.022 * k, V, N, 0.044 * k, 0.017 * k, (M["gem"], M["gem"]), piv,
                   thick=0.012, segs=4)
    # pluma de luz na ponta do punho (brilha)
    u, v = arm_at(0.62)
    bk_feather("Plume" + n, pt(u, v, 0.03), dirv(58), N, 0.20 * k, 0.03 * k, (M["glow"], M["glow"]), piv,
               bend=0.25 * s, segs=6)


def seraph_harness(M, back, R=0.21, rays=16, ray_len=(0.085, 0.05), ray_w=(0.016, 0.012)):
    """Suporte nas costas: medalhão com gema, aro com raios (sol ou coroa de espinhos) e travessas até o aro."""
    c = Vector((0, BK_BACK_Y + 0.012, BK_ROOT_Z + 0.02))
    X, Z, Y = Vector((1, 0, 0)), Vector((0, 0, 1)), Vector((0, 1, 0))
    # medalhão: disco abaulado encostado nas costas
    rings = []
    for r, y in ((0.070, -0.03), (0.070, 0.004), (0.058, 0.016), (0.034, 0.022)):
        rings.append([c + (X * math.cos(a) + Z * math.sin(a)) * r + Y * y for a in (q * math.pi / 12 for q in range(24))])
    g_smooth_mesh("Medal", rings, M["gold"], back)
    bk_feather("MedalGem", c + Y * 0.02 - Z * 0.03, Z, Y, 0.06, 0.022, (M["gem"], M["gem"]), back, thick=0.014, segs=4)
    # aro de sol atrás das omoplatas
    ring_c = c + Y * 0.115 + Z * 0.05          # atrás das raízes das asas, para aparecer visto de costas
    g_pipe("Halo", [ring_c + (X * math.cos(a) + Z * math.sin(a)) * R for a in (q * math.pi / 20 for q in range(40))],
           0.011, M["gold"], back, sides=8, loop=True)
    g_pipe("HaloIn", [ring_c + Y * 0.006 + (X * math.cos(a) + Z * math.sin(a)) * (R - 0.011)
                      for a in (q * math.pi / 20 for q in range(40))], 0.005, M["glow"], back, sides=6, loop=True)
    for q in range(rays):
        a = (q + 0.5) * 2 * math.pi / rays
        d = X * math.cos(a) + Z * math.sin(a)
        long = q % 2 == 0
        bk_feather("Ray%d" % q, ring_c + d * (R - 0.004), d, Y, ray_len[0] if long else ray_len[1],
                   ray_w[0] if long else ray_w[1],
                   (M["gold"], M["cream"]), back, tip_from=0.6, thick=0.007, segs=4)
    for q in range(4):
        a = q * math.pi / 2 + math.pi / 4
        d = X * math.cos(a) + Z * math.sin(a)
        g_pipe("Spoke%d" % q, [c + d * 0.05 + Y * 0.01, c + d * 0.10 + Y * 0.07 + Z * 0.03, ring_c + d * (R - 0.004)],
               0.008, M["gold_d"], back, sides=6)


def bk_finish(style, skip):
    """Confere se tudo se toca, junta as malhas por pivô, pinta os tons anime e exporta back/<style>.glb."""
    back = bpy.data.objects["Back"]
    bk_loose(style)
    for par in [back] + [o for o in coll.all_objects if o.name in ("WingL", "WingR", "Cloth")]:
        bk_join(par.name + "Mesh", par)
    targets = [o for o in scn.objects if o.type == 'MESH']
    for o in targets:      # sem oclusão assada (manchava as penas): a sombra entre fileiras é material próprio
        a = o.data.color_attributes.get("Col") or o.data.color_attributes.new("Col", 'BYTE_COLOR', 'CORNER')
        o.data.color_attributes.active_color = a
        for d in a.data:
            d.color = (1, 1, 1, 1)
    cel_paint(targets, skip=skip)
    os.makedirs(OUT + "back", exist_ok=True)
    export("back/" + style, export_vertex_color='ACTIVE')


def bk_wing_pivots(back):
    return [(s, empty("Wing" + n, (s * 0.06, BK_BACK_Y + 0.02, BK_ROOT_Z), back)) for n, s in (("L", 1), ("R", -1))]


def build_b_seraph():
    M = seraph_mats()
    back = empty("Back", (0, 0, 0))
    seraph_harness(M, back)
    for s, piv in bk_wing_pivots(back):
        seraph_wing(M, piv, s)
    bk_finish("b_seraph", ("sr_gem", "sr_glow"))


# ------------------------------------------------------------------ asas do abismo
def bk_membrane(name, A, B, W, N, mats, parent, rows=8, cols=6, sag=0.22, billow=0.04, thick=0.006):
    """Membrana esticada entre dois dedos (A e B: curvas do punho W até a ponta, mesma quantidade de pontos).
    A borda de fora afunda em arco para o punho (sag) e o pano estufa para trás (billow).
    mats = (meio, escuro junto aos ossos e ao punho, borda de fora)."""
    bm = bmesh.new()
    grid = []
    for i in range(rows + 1):
        t = 0.07 + 0.93 * i / rows
        a = A[int(round(t * (len(A) - 1)))]
        b = B[int(round(t * (len(B) - 1)))]
        row = []
        for j in range(cols + 1):
            sj = j / cols
            q = a.lerp(b, sj)
            q = W + (q - W) * (1.0 - sag * math.sin(math.pi * sj) * t * t) + N * billow * math.sin(math.pi * sj) * t
            row.append(bm.verts.new(q))
        grid.append(row)
    for i in range(rows):
        for j in range(cols):
            f = bm.faces.new((grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]))
            f.material_index = 2 if i == rows - 1 else (1 if j in (0, cols - 1) or i < 2 else 0)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=thick)
    bmesh.ops.translate(bm, vec=-_wloc(parent), verts=bm.verts)
    ob = _finish(name, bm, mats[0], parent, smooth=True)
    ob.data.materials.append(mats[1])
    ob.data.materials.append(mats[2])
    return ob


def abyss_mats():
    return dict(
        bone=gm("ab_bone_flat", "#3A2A4A", 0.7),
        bone_d=gm("ab_boned_flat", "#231730", 0.75),
        mem=gm("ab_mem_flat", "#A3213F", 0.8),
        mem_d=gm("ab_memd_flat", "#5E1436", 0.8),
        claw=gm("ab_claw_flat", "#E8DCC4", 0.6),
        ember=mat("ab_ember", hexc("#FF7A2E"), 0.4, 0.0, emit=hexc("#FF6A1E"), strength=2.6),
        gem=mat("ab_gem", hexc("#FF3B4E"), 0.25, 0.0, emit=hexc("#FF2A3C"), strength=2.4),
    )


def abyss_wing(M, piv, s, k=0.92, tips=None, veins=True):
    """Asa de morcego: braço até o punho, dedos em leque, membrana entre eles e garras nas pontas."""
    sw = math.radians(24)
    U = Vector((s * math.cos(sw), math.sin(sw), 0))
    V = Vector((0, 0, 1))
    N = Vector((-s * math.sin(sw), math.cos(sw), 0))
    root = _wloc(piv)
    n = "L" if s > 0 else "R"

    def pt(u, v, depth=0.0):
        return root + U * u * k + V * v * k + N * depth

    def curve(uvs, depth=0.02, m=24):
        return g_spline([pt(u, v, depth) for u, v in uvs], m)

    wrist = (0.36, 0.64)
    arm = curve([(-0.02, -0.02), (0.10, 0.20), (0.20, 0.44), wrist])
    tips = tips or [(1.00, 0.74), (1.08, 0.22), (0.86, -0.30), (0.50, -0.56)]
    fingers = []
    for i, (tu, tv) in enumerate(tips):
        du, dv = tu - wrist[0], tv - wrist[1]
        ln = math.hypot(du, dv)
        bow = 0.07 if i < 2 else 0.05            # dedos arqueados para cima e para fora
        mid = (wrist[0] + du * 0.5 - dv / ln * bow, wrist[1] + dv * 0.5 + du / ln * bow)
        fingers.append(curve([wrist, mid, (tu, tv)]))
    # linha de dentro: do punho, pelo braço, até a raiz e descendo rente ao corpo
    inner = curve([wrist, (0.20, 0.40), (0.05, 0.08), (0.03, -0.14), (0.07, -0.36)])
    W = pt(*wrist, 0.02)
    mm = (M["mem"], M["mem_d"], M["ember"])
    for i in range(len(fingers) - 1):
        bk_membrane("Mem%s%d" % (n, i), fingers[i], fingers[i + 1], W, N, mm, piv)
    bk_membrane("MemIn" + n, fingers[-1], inner, W, N, mm, piv, sag=0.16, billow=0.03)
    # ossos por cima da membrana
    g_smooth_mesh("Arm" + n, g_curved_tube(arm[::2], [(bk_lerp([0.034, 0.038, 0.030], i / 12) * k,) * 2 for i in range(13)],
                                           sides=10, side0=N), M["bone"], piv)
    for i, f in enumerate(fingers):
        g_smooth_mesh("Finger%s%d" % (n, i), g_curved_tube(f[::2], [(bk_lerp([0.024, 0.017, 0.007], j / 12) * k,) * 2
                                                                     for j in range(13)], sides=8, side0=N), M["bone"], piv)
        d = (f[-1] - f[-3]).normalized()
        bk_feather("Claw%s%d" % (n, i), f[-1] - d * 0.012, d, N, 0.075 * k, 0.012 * k, (M["claw"], M["claw"]), piv,
                   thick=0.011, bend=-0.3 * s, segs=4)
    # junta do punho, garra do polegar e esporão do cotovelo
    for q, (c, r) in enumerate(((W, 0.04), (pt(0.20, 0.44, 0.02), 0.034))):
        rings = [[c + (U * math.cos(a) + V * math.sin(a)) * r * k * math.sin(ph) + N * r * k * math.cos(ph)
                  for a in (j * math.pi / 5 for j in range(10))] for ph in (0.35, 0.9, 1.57, 2.24, 2.8)]
        g_smooth_mesh("Joint%s%d" % (n, q), rings, M["bone_d"], piv)
    bk_feather("Thumb" + n, W, U * 0.25 + V, N, 0.20 * k, 0.022 * k, (M["bone"], M["claw"]), piv, tip_from=0.5,
               thick=0.02, bend=0.35 * s, segs=6)
    bk_feather("Spur" + n, pt(0.20, 0.44, 0.02), U * -0.7 + V * 0.6, N, 0.12 * k, 0.018 * k, (M["bone"], M["claw"]), piv,
               tip_from=0.5, thick=0.016, segs=5)
    # veias de brasa ao longo dos dois dedos de cima
    for i in ((0, 1) if veins else ()):
        g_pipe("Vein%s%d" % (n, i), [q + N * 0.018 * k for q in fingers[i][2:20:3]], 0.005 * k, M["ember"], piv, sides=5)


def build_b_abyss():
    M = abyss_mats()
    back = empty("Back", (0, 0, 0))
    H = dict(gold=M["bone"], gold_d=M["bone_d"], gem=M["gem"], glow=M["ember"], cream=M["claw"])
    seraph_harness(H, back, R=0.17, rays=10, ray_len=(0.13, 0.08), ray_w=(0.02, 0.016))
    for s, piv in bk_wing_pivots(back):
        abyss_wing(M, piv, s)
    bk_finish("b_abyss", ("ab_ember", "ab_gem"))


def bk_frame(piv, s, k, sweep=24):
    """Eixos de uma asa: (pt(u, v, fundo), dirv(graus), U, V, N). u abre para fora, v sobe, N aponta para trás."""
    sw = math.radians(sweep)
    U = Vector((s * math.cos(sw), math.sin(sw), 0))
    V = Vector((0, 0, 1))
    N = Vector((-s * math.sin(sw), math.cos(sw), 0))
    root = _wloc(piv)

    def pt(u, v, depth=0.0):
        return root + U * u * k + V * v * k + N * depth

    def dirv(deg):
        a = math.radians(deg)
        return U * math.cos(a) + V * math.sin(a)

    return pt, dirv, U, V, N


def bk_ball(name, c, r, material, parent, sy=1.0, sz=1.0, sides=10):
    """Bola lisa (junta, tufo de pele, ombreira) com achatamento opcional em Y e Z."""
    c = Vector(c)
    rings = [[c + Vector((math.cos(a) * math.sin(ph) * r, math.sin(a) * math.sin(ph) * r * sy, math.cos(ph) * r * sz))
              for a in (j * 2 * math.pi / sides for j in range(sides))] for ph in (2.85, 2.3, 1.57, 0.84, 0.29)]
    return g_smooth_mesh(name, rings, material, parent)


# ------------------------------------------------------------------ asas de fênix
def build_b_phoenix():
    flame = mat("ph_flame", hexc("#FFC83A"), 0.4, 0.0, emit=hexc("#FFB020"), strength=2.2)
    arm = gm("ph_gold_flat", "#DDA02E", 0.5)
    M = dict(white=gm("ph_red_flat", "#E2421E", 0.8), shade=gm("ph_dark_flat", "#8C1B1B", 0.8),
             cream=gm("ph_orange_flat", "#FF8C22", 0.8), gold=flame, arm=arm, gold_d=gm("ph_goldd_flat", "#9C5C1C", 0.55),
             gem=mat("ph_gem", hexc("#FF5A2A"), 0.25, 0.0, emit=hexc("#FF4A1A"), strength=2.4), glow=flame)
    back = empty("Back", (0, 0, 0))
    H = dict(M, gold=arm, cream=flame)
    seraph_harness(H, back, R=0.2, rays=12, ray_len=(0.12, 0.07), ray_w=(0.022, 0.016))
    for s, piv in bk_wing_pivots(back):
        seraph_wing(M, piv, s, k=0.97, flame=0.16)
    bk_finish("b_phoenix", ("ph_flame", "ph_gem"))


# ------------------------------------------------------------------ asas de cristal
def crystal_wing(M, piv, s, k=0.95):
    """Lascas de cristal em leque, engastadas num braço de prata."""
    pt, dirv, U, V, N = bk_frame(piv, s, k)
    n = "L" if s > 0 else "R"
    arm = g_spline([Vector((u, v, 0)) for u, v in [(-0.02, -0.02), (0.08, 0.20), (0.20, 0.42), (0.34, 0.56), (0.50, 0.58)]], 24)

    def arm_at(t):
        p = arm[int(round(max(0.0, min(1.0, t)) * 24))]
        return p.x, p.y

    ang = [-90, -72, -52, -32, -14]
    for i in range(8):                      # lascas grandes
        t = i / 7
        u, v = arm_at(0.22 + 0.78 * t)
        bk_feather("Shard%s%d" % (n, i), pt(u, v, 0.012), dirv(bk_lerp(ang, t)), N,
                   bk_lerp([0.60, 0.86, 1.0, 0.92, 0.72, 0.52], t) * k, 0.062 * k, (M["ice"], M["tip"], M["deep"]), piv,
                   tip_from=0.72, shade_to=0.3, thick=0.034, segs=5, blade=True, twist=0.5 * s)
    for i in range(7):                      # lascas menores por cima, intercaladas
        t = (i + 0.5) / 7
        u, v = arm_at(0.2 + 0.78 * t)
        bk_feather("Chip%s%d" % (n, i), pt(u, v, 0.034), dirv(bk_lerp(ang, t) + 7), N,
                   bk_lerp([0.30, 0.42, 0.48, 0.44, 0.34, 0.26], t) * k, 0.046 * k, (M["deep"], M["ice"], M["deep"]), piv,
                   tip_from=0.5, thick=0.03, segs=4, blade=True, twist=-0.45 * s)
    for i in range(5):                      # espinhos de cristal para cima, ao longo do braço
        t = i / 4
        u, v = arm_at(0.3 + 0.7 * t)
        bk_feather("Spike%s%d" % (n, i), pt(u, v, 0.02), dirv(bk_lerp([105, 85, 62, 40], t)), N,
                   bk_lerp([0.12, 0.2, 0.18, 0.13], t) * k, 0.03 * k, (M["ice"], M["tip"]), piv, tip_from=0.6,
                   thick=0.022, segs=4, blade=True, twist=0.4 * s)
    path = [pt(p.x, p.y, 0.024) for p in arm[::2]]
    g_smooth_mesh("Arm" + n, g_curved_tube(path, [(bk_lerp([0.032, 0.034, 0.026, 0.014], i / 12) * k,) * 2
                                                  for i in range(13)], sides=10, side0=N), M["silver"], piv)
    g_pipe("ArmTrim" + n, [q + N * 0.03 * k for q in path[1:11]], 0.006 * k, M["silver_d"], piv, sides=6)


def build_b_crystal():
    M = dict(ice=gm("cr_ice_flat", "#A8ECFF", 0.4), deep=gm("cr_deep_flat", "#4A8FE6", 0.4),
             tip=mat("cr_tip", hexc("#E6FBFF"), 0.2, 0.0, emit=hexc("#9FE8FF"), strength=2.4),
             silver=gm("cr_silver_flat", "#D5DEEE", 0.5), silver_d=gm("cr_silverd_flat", "#7F8DAA", 0.55),
             gem=mat("cr_gem", hexc("#B58CFF"), 0.25, 0.0, emit=hexc("#A070FF"), strength=2.2))
    back = empty("Back", (0, 0, 0))
    H = dict(gold=M["silver"], gold_d=M["silver_d"], gem=M["gem"], glow=M["tip"], cream=M["ice"])
    seraph_harness(H, back, R=0.19, rays=8, ray_len=(0.16, 0.09), ray_w=(0.024, 0.018))
    for s, piv in bk_wing_pivots(back):
        crystal_wing(M, piv, s)
    bk_finish("b_crystal", ("cr_tip", "cr_gem"))


# ------------------------------------------------------------------ asas mecânicas
def mech_wing(M, piv, s, k=0.95):
    """Braço articulado em três segmentos com juntas, pistão e lâminas de aço com filete de luz."""
    pt, dirv, U, V, N = bk_frame(piv, s, k)
    n = "L" if s > 0 else "R"
    J = [(0.0, 0.0), (0.20, 0.40), (0.46, 0.58), (0.70, 0.50)]

    def on_seg(i, t):
        return J[i][0] + (J[i + 1][0] - J[i][0]) * t, J[i][1] + (J[i + 1][1] - J[i][1]) * t

    for i, r in enumerate((0.032, 0.028, 0.022)):
        a, b = pt(*J[i], 0.024), pt(*J[i + 1], 0.024)
        g_smooth_mesh("Seg%s%d" % (n, i), g_curved_tube([a, a.lerp(b, 0.5), b], [(r * k, r * k)] * 3, sides=8, side0=N),
                      M["steel"], piv)
        g_pipe("Piston%s%d" % (n, i), [a.lerp(b, 0.12) + N * 0.03 * k, a.lerp(b, 0.5) + N * 0.045 * k,
                                       a.lerp(b, 0.88) + N * 0.03 * k], 0.008 * k, M["brass"], piv, sides=6)
    for i, (u, v) in enumerate(J):
        bk_ball("Joint%s%d" % (n, i), pt(u, v, 0.024), (0.05 if i < 3 else 0.03) * k, M["dark"], piv)
        bk_ball("Core%s%d" % (n, i), pt(u, v, 0.024 + 0.04 * k), 0.018 * k, M["glow"], piv)

    def blade(name, base_uv, deg, ln, wd, depth):
        b = pt(*base_uv, depth)
        d = dirv(deg)
        bk_feather(name, b, d, N, ln * k, wd * k, (M["steel"], M["steel"], M["dark"]), piv, shade_to=0.22, thick=0.012,
                   segs=5, blade=True, twist=0.16 * s)
        g_pipe(name + "Line", [b + d * ln * k * t + N * 0.011 for t in (0.2, 0.5, 0.82)], 0.006 * k, M["glow"], piv, sides=5)

    for i in range(7):                      # lâminas longas na mão
        t = i / 6
        blade("Blade%s%d" % (n, i), on_seg(2, t), bk_lerp([-86, -72, -56, -42, -30], t),
              bk_lerp([1.0, 1.06, 1.02, 0.92, 0.78, 0.6], t), 0.05, 0.004 + 0.002 * i)
    for i in range(6):                      # lâminas médias no antebraço
        t = i / 5
        blade("Fore%s%d" % (n, i), on_seg(1, 0.05 + 0.9 * t), bk_lerp([-94, -90, -87], t), bk_lerp([0.62, 0.78, 0.92], t),
              0.055, 0.014)
    for i in range(4):                      # lâminas curtas no braço
        t = i / 3
        blade("Up%s%d" % (n, i), on_seg(0, 0.25 + 0.7 * t), bk_lerp([-102, -96], t), bk_lerp([0.36, 0.56], t), 0.055, 0.014)
    for i in range(9):                      # placas de latão cobrindo as bases
        t = i / 8
        seg = 1 if t < 0.5 else 2
        uv = on_seg(seg, (t * 2) % 1.0 if t < 1 else 1.0)
        bk_feather("Plate%s%d" % (n, i), pt(*uv, 0.034), dirv(bk_lerp([-92, -88, -70, -40], t)), N, 0.2 * k, 0.062 * k,
                   (M["brass"], M["dark"]), piv, tip_from=0.7, thick=0.012, segs=4, blade=True)


def build_b_mech():
    M = dict(steel=gm("mc_steel_flat", "#CBD3E1", 0.45), dark=gm("mc_dark_flat", "#4A5469", 0.5),
             brass=gm("mc_brass_flat", "#C9973F", 0.5),
             glow=mat("mc_glow", hexc("#6FE8FF"), 0.3, 0.0, emit=hexc("#4FDCFF"), strength=2.6))
    back = empty("Back", (0, 0, 0))
    H = dict(gold=M["steel"], gold_d=M["dark"], gem=M["glow"], glow=M["glow"], cream=M["brass"])
    seraph_harness(H, back, R=0.17, rays=12, ray_len=(0.05, 0.05), ray_w=(0.03, 0.03))
    for s, piv in bk_wing_pivots(back):
        mech_wing(M, piv, s)
    bk_finish("b_mech", ("mc_glow",))


# ------------------------------------------------------------------ asas de dragão
def build_b_dragon():
    M = dict(bone=gm("dg_bone_flat", "#5A4630", 0.7), bone_d=gm("dg_boned_flat", "#332618", 0.75),
             mem=gm("dg_mem_flat", "#2F9E6C", 0.8), mem_d=gm("dg_memd_flat", "#1B5E4A", 0.8),
             claw=gm("dg_claw_flat", "#EFE4C8", 0.6), ember=gm("dg_rim_flat", "#CBEA8C", 0.7),
             gem=mat("dg_gem", hexc("#FFB23A"), 0.25, 0.0, emit=hexc("#FFA020"), strength=2.0))
    back = empty("Back", (0, 0, 0))
    H = dict(gold=M["bone"], gold_d=M["bone_d"], gem=M["gem"], glow=M["ember"], cream=M["claw"])
    seraph_harness(H, back, R=0.14, rays=6, ray_len=(0.09, 0.09), ray_w=(0.022, 0.022))
    for s, piv in bk_wing_pivots(back):
        abyss_wing(M, piv, s, k=0.96, tips=[(0.96, 0.82), (1.04, 0.20), (0.62, -0.52)], veins=False)
    bk_finish("b_dragon", ("dg_gem",))


# ------------------------------------------------------------------ asas de fada
def fairy_wing(M, piv, s, k=0.9):
    """Asa de borboleta: lóbulo de cima grande, lóbulo de baixo menor com cauda, nervuras por cima."""
    pt, dirv, U, V, N = bk_frame(piv, s, k, sweep=18)
    n = "L" if s > 0 else "R"
    W = pt(0.0, 0.0, 0.02)
    mm = (M["mid"], M["edge"], M["rim"])
    lobes = (([(0.0, 0.0), (0.28, 0.50), (0.62, 0.86), (0.86, 0.84)], [(0.0, 0.0), (0.40, 0.10), (0.78, 0.16), (0.96, 0.34)]),
             ([(0.0, 0.0), (0.34, -0.04), (0.66, -0.10), (0.80, -0.26)], [(0.0, 0.0), (0.10, -0.30), (0.26, -0.62), (0.46, -0.80)]))
    for li, (a_uv, b_uv) in enumerate(lobes):
        A = g_spline([pt(u, v, 0.02) for u, v in a_uv], 24)
        B = g_spline([pt(u, v, 0.02) for u, v in b_uv], 24)
        bk_membrane("Lobe%s%d" % (n, li), A, B, W, N, mm, piv, rows=8, cols=8, sag=-0.2, billow=0.03, thick=0.008)
        for ci, c in enumerate((A, B)):
            g_pipe("Edge%s%d%d" % (n, li, ci), [q + N * 0.006 for q in c[1::3]], 0.009 * k, M["vein"], piv, sides=6)
        for f in (0.34, 0.67):
            mid = [W + (A[j].lerp(B[j], f) - W) * (1.0 + 0.2 * math.sin(math.pi * f) * (j / 24) ** 2)
                   + N * (0.03 * math.sin(math.pi * f) * j / 24 + 0.003) for j in range(2, 23, 4)]
            g_pipe("Vein%s%d%d" % (n, li, int(f * 10)), mid, 0.005 * k, M["rim"], piv, sides=5)
    tail = pt(0.46, -0.80, 0.02)
    bk_feather("Tail" + n, tail + V * 0.04 - U * 0.01, U * 0.25 - V, N, 0.3 * k, 0.03 * k, (M["edge"], M["rim"]), piv, tip_from=0.6,
               bend=0.3 * s, segs=6)
    bk_ball("Root" + n, W, 0.04 * k, M["vein"], piv)


def build_b_fairy():
    M = dict(mid=gm("fy_mid_flat", "#FFC4E8", 0.6), edge=gm("fy_edge_flat", "#B77BEA", 0.6),
             vein=gm("fy_vein_flat", "#7C52C4", 0.6),
             rim=mat("fy_rim", hexc("#FFF0FA"), 0.3, 0.0, emit=hexc("#FFB8EC"), strength=2.0),
             gem=mat("fy_gem", hexc("#8CF0D0"), 0.25, 0.0, emit=hexc("#6CE8C0"), strength=2.0))
    back = empty("Back", (0, 0, 0))
    H = dict(gold=M["vein"], gold_d=M["edge"], gem=M["gem"], glow=M["rim"], cream=M["mid"])
    seraph_harness(H, back, R=0.09, rays=6, ray_len=(0.08, 0.08), ray_w=(0.034, 0.034))
    for s, piv in bk_wing_pivots(back):
        fairy_wing(M, piv, s)
    bk_finish("b_fairy", ("fy_rim", "fy_gem"))


# ------------------------------------------------------------------ capas com modelo próprio
# O pano fica no pivô "Cloth" (vira a malha ClothMesh, que o CapeRig do jogo transforma em tecido) e as peças
# rígidas (gola, ombreiras, manto de penas) no "Back". Enfeites do pano entram na mesma malha e balançam junto.
# Materiais "fx_<tipo>" são trocados no jogo pelo shader animado (assets/shaders/back_anim.gdshader), que usa
# o UV do pano: U atravessa a capa, V vai da gola (0) à barra (1).
def bk_cape(name, parent, mats, mat_fn, z0=1.46, z1=0.3, r0=0.17, r1=0.30, arc0=2.3, arc1=2.9, rows=22, cols=32,
            folds=0.03, nf=5, hem=None, a_off=0.0, ys=1.0, lining=None):
    """Pano curvo em volta das costas, com dobras lisas que crescem até a barra. hem(u) sobe a barra (m) na
    coluna u; mat_fn(t, u, dobra, i, j) escolhe o material da face (t: 0 gola .. 1 barra; dobra: -1 fundo .. 1
    crista; i, j: linha e coluna, para padrões bordados). lining = material do forro (segunda folha por dentro).
    Devolve P(t, u, fora) -> (ponto, tangente, normal) para assentar enfeites no pano."""
    def P(t, u, out=0.0):
        arc = arc0 + (arc1 - arc0) * t
        a = a_off - arc / 2 + arc * u
        zb = z1 + (hem(u) if hem else 0.0)
        r = r0 + (r1 - r0) * t + folds * t * math.sin(u * nf * 2 * math.pi) + out
        return (Vector((math.sin(a) * r, math.cos(a) * r * ys, z0 + (zb - z0) * t)),
                Vector((math.cos(a), -math.sin(a) * ys, 0)).normalized(), Vector((math.sin(a), math.cos(a), 0)))

    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    grid = [[bm.verts.new(P(i / rows, j / cols)[0]) for j in range(cols + 1)] for i in range(rows + 1)]
    for i in range(rows):
        for j in range(cols):
            ij = ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))
            f = bm.faces.new([grid[a][b] for a, b in ij])
            for loop, (a, b) in zip(f.loops, ij):
                loop[uvl].uv = (b / cols, 1.0 - a / rows)     # o glTF inverte o V: no jogo V = 0 na gola, 1 na barra
            f.material_index = mat_fn((i + 0.5) / rows, (j + 0.5) / cols, math.sin((j + 0.5) / cols * nf * 2 * math.pi), i, j)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    mid = sum((v.co for v in bm.verts), Vector()) / len(bm.verts)
    axis = Vector((0, 0, mid.z))
    if sum(f.normal.dot(f.calc_center_median() - Vector((0, 0, f.calc_center_median().z))) for f in bm.faces) < 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    if lining is not None:               # forro: folha por dentro, virada para o corpo
        lr, lc = max(4, rows // 2), max(4, cols // 2)
        g2 = [[bm.verts.new(P(i / lr, j / lc, -0.012)[0]) for j in range(lc + 1)] for i in range(lr + 1)]
        for i in range(lr):
            for j in range(lc):
                f = bm.faces.new((g2[i][j], g2[i][j + 1], g2[i + 1][j + 1], g2[i + 1][j]))
                f.material_index = len(mats)
                f.normal_update()
                c = f.calc_center_median()
                if f.normal.dot(c - Vector((0, 0, c.z))) > 0:
                    f.normal_flip()
    bmesh.ops.translate(bm, vec=-_wloc(parent), verts=bm.verts)
    ob = _finish(name, bm, mats[0], parent, smooth=True)
    for m in mats[1:]:
        ob.data.materials.append(m)
    if lining is not None:
        ob.data.materials.append(lining)
    return P


def bk_fold(base=0, shade=1):
    """Tom de sombra no fundo das dobras."""
    return lambda t, u, f: shade if (f < -0.35 and t > 0.18) else base


def bk_on_cloth(P, t, u, out=0.004):
    """Origem e eixos (u, v) para uma chapa assentada no pano."""
    p, tan, nrm = P(t, u, out)
    return p, tan, Vector((0, 0, 1))


def bk_chain(name, P, t0, u0, u1, sag, material, parent, pend=None, n=14, r=0.006):
    """Corrente em arco sobre o pano, de u0 a u1, caindo `sag` (em t) no meio. pend(i, origem, tu, tv) pendura
    um enfeite a cada dois elos."""
    pts = []
    for i in range(n + 1):
        q = i / n
        pts.append((t0 + sag * math.sin(math.pi * q), u0 + (u1 - u0) * q))
    g_pipe(name, [P(t, u, 0.008)[0] for t, u in pts], r, material, parent, sides=5)
    if pend:
        for i in range(2, n - 1, 3):
            o, tu, tv = bk_on_cloth(P, pts[i][0] + 0.02, pts[i][1], 0.008)
            pend(i, o, tu, tv)


def bk_feather_ring(name, parent, mats, z, r, n, a0, a1, length, width, droop=0.5, tip_from=0.6, ys=0.9, blade=False):
    """Fileira de penas (ou folhas, ou cristais) em arco em volta dos ombros, apontando para fora e para baixo."""
    for i in range(n):
        a = a0 + (a1 - a0) * i / (n - 1)
        out = Vector((math.sin(a), math.cos(a) * ys, 0))
        base = Vector((out.x * r, out.y * r, z + 0.006 * math.cos(i * 2.3)))
        d = (out * (1.0 - droop) - Vector((0, 0, droop))).normalized()
        nrm = (out * droop + Vector((0, 0, 1.0 - droop))).normalized()
        bk_feather("%s%d" % (name, i), base, d, nrm, length * (0.9 + 0.2 * ((i * 7) % 5) / 4), width, mats, parent,
                   tip_from=tip_from, thick=0.012, segs=4, twist=0.25 * (1 if i % 2 else -1), blade=blade)


def bk_pauldron(name, parent, s, body, rim, gem, r=0.095, spikes=(), spike_mats=None):
    """Ombreira em duas placas com gema. spikes = [(direção, comprimento, largura, curva)] saindo do topo."""
    sh = Vector((s * 0.215, 0.0, 1.46))
    bk_ball(name + "A", sh, r, body, parent, sz=0.72)
    bk_ball(name + "B", sh + Vector((s * 0.035, 0.0, -0.045)), r * 0.95, rim, parent, sz=0.6)
    g_pipe(name + "Rim", [sh + Vector((math.cos(a) * r, math.sin(a) * r, -0.03)) for a in
                          (q * math.pi / 8 for q in range(16))], 0.011, rim, parent, sides=6, loop=True)
    bk_ball(name + "Gem", sh + Vector((s * 0.06, 0.0, 0.045)), 0.024, gem, parent)
    for i, (d, ln, wd, bend) in enumerate(spikes):
        d = Vector((d[0] * s, d[1], d[2]))
        bk_feather("%sSpike%d" % (name, i), sh + d.normalized() * r * 0.45, d, Vector((0, 1, 0)), ln, wd,
                   spike_mats or (rim, rim), parent, tip_from=0.55, thick=wd * 0.8, bend=bend * s, segs=5)
    return sh


def bk_hem_drops(name, P, parent, mats, n, length, width, u0=0.04, u1=0.96, blade=False, tip_from=0.6, t=0.97):
    """Pingentes na barra do pano (pingos de gelo, folhas, penas): balançam com a capa."""
    for i in range(n):
        u = u0 + (u1 - u0) * i / (n - 1)
        p, tan, nrm = P(t, u, 0.004)
        ln = length * (0.7 + 0.6 * ((i * 5) % 7) / 6)
        bk_feather("%s%d" % (name, i), p, Vector((0, 0, -1)) + nrm * 0.08, nrm, ln, width, mats, parent, tip_from=tip_from,
                   thick=width * 0.5 if blade else 0.01, segs=4, blade=blade)


def bk_fx(name, hx, emit, strength=1.6):
    """Material que o jogo troca pelo shader animado (prefixo fx_). A cor aqui vale para prévia e ícone."""
    return mat(name, hexc(hx), 0.5, 0.0, emit=hexc(emit), strength=strength)


def build_c_dragonking():
    red, red_d = gm("dk_red_flat", "#B3202A", 0.8), gm("dk_redd_flat", "#74121C", 0.8)
    panel = gm("dk_panel_flat", "#5E0F1A", 0.8)
    gold, gold_d = gm("dk_gold_flat", "#E9AE3C", 0.5), gm("dk_goldd_flat", "#B77F2C", 0.55)
    glow = mat("dk_glow", hexc("#FFD56B"), 0.4, 0.0, emit=hexc("#FFC040"), strength=1.4)
    fire = bk_fx("fx_fire", "#FF7A1E", "#FF5A10")
    fur, spot = gm("dk_fur_flat", "#F4EEDF", 0.9), gm("dk_spot_flat", "#3A3028", 0.9)
    horn = gm("dk_horn_flat", "#EFE4C8", 0.6)
    lin = gm("dk_lining_flat", "#E2B95C", 0.7)
    back = empty("Back", (0, 0, 0))
    cloth = empty("Cloth", (0, 0, 0), back)
    fold = bk_fold()

    def mf(t, u, f, i, j):
        c = abs(u - 0.5)
        if t > 0.80 - 0.05 * abs(math.sin(u * math.pi * 9)):
            return 4                                   # barra em chamas (animada)
        if u < 0.04 or u > 0.96 or 0.74 < t < 0.77:
            return 2
        if 0.105 < c < 0.13:
            return 2                                   # filetes do painel central
        if c <= 0.105:
            return 2 if (i + j) % 4 == 0 and i % 2 == 0 else 3      # painel escuro com escamas douradas
        if (i % 6 == 3) and (j % 4 == 1) and t > 0.3:
            return 2                                   # flores-de-lis espalhadas
        return fold(t, u, f)

    P = bk_cape("CapeCloth", cloth, [red, red_d, gold, panel, fire], mf, z1=0.10, r1=0.38, arc1=3.2, folds=0.04,
                rows=30, cols=40, lining=lin)
    o, tu, tv = bk_on_cloth(P, 0.40, 0.5)
    g_plate("Crest", [(0, 0.13), (0.06, 0), (0, -0.13), (-0.06, 0)], o, tu, tv, 0.008, gold, cloth)
    g_plate("CrestGem", [(0, 0.045), (0.024, 0), (0, -0.045), (-0.024, 0)], o + P(0.40, 0.5)[2] * 0.008, tu, tv, 0.006,
            glow, cloth)
    # sobrecapa nos ombros: curta, com barra recortada e filete dourado
    bk_cape("Mantle", cloth, [red_d, panel, gold], lambda t, u, f, i, j: 2 if t > 0.78 or u < 0.05 or u > 0.95 else
            (1 if f < -0.3 else 0), z0=1.49, z1=1.10, r0=0.18, r1=0.36, arc0=2.9, arc1=3.3, rows=8, cols=30, folds=0.02,
            nf=7, hem=lambda u: 0.06 * abs(math.sin(u * math.pi * 7)), lining=lin)
    for i in range(13):                   # gola de arminho
        a = -1.62 + 3.24 * i / 12
        c = Vector((math.sin(a) * 0.19, math.cos(a) * 0.17, 1.5 + 0.012 * math.cos(i * 2.1)))
        bk_ball("Fur%d" % i, c, 0.074, fur, back, sz=0.8)
        if i % 2 == 0:
            bk_ball("FurSpot%d" % i, c + Vector((math.sin(a), math.cos(a), 0.2)) * 0.062, 0.016, spot, back)
    for s in (-1, 1):                     # ombreiras com chifres de dragão
        bk_pauldron("Pauldron%d" % s, back, s, gold, gold_d, glow, r=0.1,
                    spikes=[((0.6, 0.25, 1.0), 0.2, 0.026, 0.5), ((1.0, 0.5, 0.35), 0.15, 0.022, 0.4),
                            ((0.2, 0.9, 0.5), 0.12, 0.02, 0.3)], spike_mats=(horn, gold_d))
    bk_finish("c_dragonking", ("dk_glow", "fx_fire"))


def build_c_starry():
    gal = bk_fx("fx_galaxy", "#24327E", "#3A2A9A", 0.6)
    gold, gold_d = gm("st_gold_flat", "#E9C25A", 0.5), gm("st_goldd_flat", "#A8842E", 0.55)
    navy, navy_d = gm("st_navy_flat", "#1C2666", 0.8), gm("st_navyd_flat", "#101844", 0.8)
    star = mat("st_star", hexc("#FFF4C0"), 0.3, 0.0, emit=hexc("#FFE890"), strength=2.4)
    lin = gm("st_lining_flat", "#6A3FB8", 0.7)
    back = empty("Back", (0, 0, 0))
    cloth = empty("Cloth", (0, 0, 0), back)

    def mf(t, u, f, i, j):
        if u < 0.035 or u > 0.965 or t > 0.955:
            return 1
        if t > 0.9 and (j % 2 == 0):
            return 2                                   # franja de luz na barra
        return 0

    P = bk_cape("CapeCloth", cloth, [gal, gold, star], mf, z1=0.14, r1=0.37, arc1=3.2, folds=0.035, nf=6, rows=26,
                cols=36, hem=lambda u: 0.05 * abs(math.sin(u * math.pi * 9)), lining=lin)

    def pendant(i, o, tu, tv):
        g_plate("Pend%d_%d" % (i, int(o.z * 1000)), g_star4(0.026, 0.008), o, tu, tv, 0.006, star, cloth)

    for k, (t0, sag) in enumerate(((0.10, 0.07), (0.17, 0.10), (0.25, 0.13))):      # correntes com estrelas
        bk_chain("Chain%d" % k, P, t0, 0.14, 0.86, sag, gold, cloth, pend=pendant)
    o, tu, tv = bk_on_cloth(P, 0.50, 0.5)
    g_crescent("Moon", o, tu, tv, 0.008, star, cloth, r=0.11, r_in=0.094, d=0.044)
    for i, (t, u, r) in enumerate(((0.44, 0.26, 0.05), (0.62, 0.72, 0.06), (0.74, 0.3, 0.045), (0.36, 0.76, 0.04),
                                   (0.82, 0.58, 0.05))):
        o, tu, tv = bk_on_cloth(P, t, u)
        g_plate("BigStar%d" % i, g_star4(r, r * 0.26), o, tu, tv, 0.007, star, cloth)
    # capuz caído nas costas e gola larga
    g_pipe("Cowl", [Vector((math.sin(a) * 0.15, math.cos(a) * 0.135 + 0.01, 1.5 + 0.02 * math.cos(a)))
                    for a in (q * math.pi / 10 for q in range(20))], 0.05, navy, back, sides=10, loop=True)
    bk_ball("Hood", Vector((0, 0.2, 1.44)), 0.13, navy_d, back, sy=0.62, sz=1.05)
    g_pipe("HoodRim", [Vector((math.sin(a) * 0.092, 0.255, 1.44 + math.cos(a) * 0.096)) for a in
                       (q * math.pi / 8 for q in range(16))], 0.01, gold, back, sides=6, loop=True)
    for s in (-1, 1):                     # ombreiras com meia-lua em pé
        sh = bk_pauldron("Pauldron%d" % s, back, s, navy, gold, star, r=0.09)
        g_crescent("Crescent%d" % s, sh + Vector((s * 0.03, 0.0, 0.1)), Vector((0, 0, 1)), Vector((s, 0, 0)), 0.008, gold,
                   back, r=0.07, r_in=0.06, d=0.028)
    bk_finish("c_starry", ("st_star", "fx_galaxy"))


def build_c_wanderer():
    red, red_d = gm("wd_red_flat", "#5E1E2A", 0.9), gm("wd_redd_flat", "#35101A", 0.9)
    patch = gm("wd_patch_flat", "#8E6B4C", 0.9)
    scarf, scarf_d = gm("wd_scarf_flat", "#C4323C", 0.9), gm("wd_scarfd_flat", "#84202A", 0.9)
    raven, sheen = gm("wd_raven_flat", "#221E30", 0.7), gm("wd_sheen_flat", "#4C4388", 0.6)
    eye = mat("wd_eye", hexc("#7FD8FF"), 0.3, 0.0, emit=hexc("#5FC8FF"), strength=2.0)
    back = empty("Back", (0, 0, 0))
    cloth = empty("Cloth", (0, 0, 0), back)
    rnd = random.Random(5)
    cols = 30
    rip = [rnd.choice((0.0, 0.03, 0.08, 0.2, 0.12, 0.0, 0.26)) for _ in range(cols + 1)]
    fold = bk_fold()
    patches = ((0.40, 0.52, 0.18, 0.34), (0.60, 0.72, 0.60, 0.78), (0.74, 0.86, 0.30, 0.42))

    def mf(t, u, f, i, j):
        for t0, t1, u0, u1 in patches:
            if t0 < t < t1 and u0 < u < u1:
                return 2
        return fold(t, u, f)

    P = bk_cape("CapeCloth", cloth, [red, red_d, patch], mf, z1=0.34, r1=0.32, arc1=3.0, folds=0.035, nf=5, cols=cols,
                rows=20, hem=lambda u: rip[int(round(u * cols))], lining=red_d)
    bk_hem_drops("HemFeather", P, cloth, (raven, sheen), 12, 0.2, 0.03, t=0.8)     # penas presas nos rasgos
    # manto de penas de corvo: três fileiras em volta dos ombros
    for k, (z, r, ln) in enumerate(((1.50, 0.185, 0.2), (1.44, 0.215, 0.24), (1.37, 0.24, 0.28))):
        bk_feather_ring("Raven%d_" % k, back, (raven, sheen), z, r, 17 + k * 2, -2.0, 2.0, ln, 0.045, droop=0.62)
    g_pipe("ScarfRoll", [Vector((math.sin(a) * 0.125, math.cos(a) * 0.115 + 0.01, 1.52 + 0.012 * math.sin(a * 3)))
                         for a in (q * math.pi / 10 for q in range(20))], 0.042, scarf, back, sides=10, loop=True)
    bk_ball("Brooch", Vector((0.0, 0.135, 1.5)), 0.03, eye, back)                  # broche de olho de corvo, atrás
    tail_rip = [0.0, 0.1, 0.02, 0.16, 0.05]
    bk_cape("ScarfTail", cloth, [scarf, scarf_d], lambda t, u, f, i, j: 1 if u > 0.7 else 0, z0=1.5, z1=0.62, r0=0.155,
            r1=0.39, arc0=0.36, arc1=0.5, rows=12, cols=4, folds=0.012, nf=1, a_off=0.75,
            hem=lambda u: tail_rip[int(round(u * 4))])
    bk_finish("c_wanderer", ("wd_eye",))


def build_c_half():
    wine, wine_d = gm("hc_wine_flat", "#7E2142", 0.8), gm("hc_wined_flat", "#4E1029", 0.8)
    gold, gold_d = gm("hc_gold_flat", "#E2B04A", 0.5), gm("hc_goldd_flat", "#A87A28", 0.55)
    lin = gm("hc_lining_flat", "#F0E6CF", 0.8)
    gem = mat("hc_gem", hexc("#7FD0FF"), 0.25, 0.0, emit=hexc("#5FC0FF"), strength=1.8)
    back = empty("Back", (0, 0, 0))
    cloth = empty("Cloth", (0, 0, 0), back)
    fold = bk_fold()

    def mf(t, u, f, i, j):
        if t > 0.9 or u < 0.045 or u > 0.955 or 0.80 < t < 0.83:
            return 2
        if 0.83 <= t <= 0.9 and j % 3 == 1:
            return 2                                   # losangos bordados entre os dois filetes
        if 0.3 < t < 0.76 and i % 5 == 2 and j % 4 == 2:
            return 2
        return fold(t, u, f)

    kw = dict(arc0=2.3, arc1=2.9, nf=4, a_off=1.15, ys=0.66)
    P = bk_cape("CapeCloth", cloth, [wine, wine_d, gold], mf, z0=1.45, z1=0.78, r0=0.25, r1=0.41, rows=20, cols=30,
                folds=0.03, lining=lin, **kw)
    bk_cape("Capelet", cloth, [wine_d, wine, gold], lambda t, u, f, i, j: 2 if t > 0.75 or u < 0.06 or u > 0.94 else 0,
            z0=1.47, z1=1.2, r0=0.262, r1=0.35, rows=6, cols=22, folds=0.012,
            hem=lambda u: 0.04 * abs(math.sin(u * math.pi * 6)), **kw)
    bk_chain("Cord", P, 0.16, 0.5, 0.92, 0.2, gold, cloth, r=0.008,
             pend=lambda i, o, tu, tv: bk_ball("Tassel%d" % i, o, 0.02, gold_d, cloth, sz=1.6))
    bk_pauldron("Pauldron", back, 1, gold, gold_d, gem, r=0.105,
                spikes=[((0.9, 0.0, 0.7), 0.13, 0.024, 0.2), ((0.5, 0.6, 0.8), 0.1, 0.02, 0.2)])
    bk_finish("c_half", ("hc_gem",))


# ------------------------------------------------------------------ capas elementais
def build_c_flame():
    char, char_d = gm("fl_char_flat", "#3A1414", 0.9), gm("fl_chard_flat", "#1E0A0C", 0.9)
    fire = bk_fx("fx_fire", "#FF7A1E", "#FF5A10")
    obs, obs_d = gm("fl_obs_flat", "#2A2228", 0.6), gm("fl_obsd_flat", "#151015", 0.6)
    ember = mat("fl_ember", hexc("#FF8A2E"), 0.4, 0.0, emit=hexc("#FF6A1E"), strength=2.6)
    back = empty("Back", (0, 0, 0))
    cloth = empty("Cloth", (0, 0, 0), back)
    fold = bk_fold()

    def mf(t, u, f, i, j):
        if t > 0.34 - 0.08 * abs(math.sin(u * math.pi * 6)):
            return 2                                   # o fogo sobe da barra (animado)
        return fold(t, u, f)

    P = bk_cape("CapeCloth", cloth, [char, char_d, fire], mf, z1=0.16, r1=0.37, arc1=3.1, folds=0.04, rows=26, cols=36,
                hem=lambda u: 0.14 * abs(math.sin(u * math.pi * 7)) ** 0.7, lining=char_d)
    bk_hem_drops("Lick", P, cloth, (ember, ember), 9, 0.16, 0.035, t=0.9)         # línguas de fogo na barra
    g_pipe("Collar", [Vector((math.sin(a) * 0.16, math.cos(a) * 0.14 + 0.01, 1.5)) for a in
                      (q * math.pi / 10 for q in range(20))], 0.035, obs, back, sides=8, loop=True)
    for s in (-1, 1):                     # ombreiras de obsidiana com labaredas
        sh = bk_pauldron("Pauldron%d" % s, back, s, obs, obs_d, ember, r=0.1,
                         spikes=[((0.5, 0.2, 1.0), 0.24, 0.04, 0.6), ((1.0, 0.3, 0.5), 0.18, 0.034, 0.5),
                                 ((0.1, 0.8, 0.7), 0.16, 0.03, -0.4)], spike_mats=(ember, ember))
        g_pipe("Crack%d" % s, [sh + Vector((math.cos(a) * 0.07, math.sin(a) * 0.07, 0.05 + 0.012 * math.sin(a * 3)))
                               for a in (q * math.pi / 6 for q in range(12))], 0.006, ember, back, sides=5, loop=True)
    bk_finish("c_flame", ("fl_ember", "fx_fire"))


def build_c_frost():
    ice_fx = bk_fx("fx_ice", "#8FD8FF", "#6FC0FF", 0.8)
    ice, deep = gm("fr_ice_flat", "#BFF0FF", 0.4), gm("fr_deep_flat", "#4A8FE6", 0.4)
    tip = mat("fr_tip", hexc("#E6FBFF"), 0.2, 0.0, emit=hexc("#9FE8FF"), strength=2.2)
    silver, silver_d = gm("fr_silver_flat", "#D5DEEE", 0.5), gm("fr_silverd_flat", "#7F8DAA", 0.55)
    snow = gm("fr_snow_flat", "#F4F8FF", 0.9)
    back = empty("Back", (0, 0, 0))
    cloth = empty("Cloth", (0, 0, 0), back)
    P = bk_cape("CapeCloth", cloth, [ice_fx, silver, snow], lambda t, u, f, i, j: 1 if (u < 0.04 or u > 0.96) else
                (2 if t < 0.1 + 0.04 * abs(math.sin(u * math.pi * 8)) else 0), z1=0.2, r1=0.36, arc1=3.1, folds=0.035,
                rows=24, cols=34, hem=lambda u: 0.07 * abs(math.sin(u * math.pi * 8)), lining=deep)
    bk_hem_drops("Icicle", P, cloth, (ice, tip), 15, 0.2, 0.022, blade=True, tip_from=0.55)
    for k, (z, r, ln) in enumerate(((1.5, 0.19, 0.11), (1.455, 0.215, 0.14))):   # gola de neve
        for i in range(14):
            a = -1.7 + 3.4 * i / 13
            bk_ball("Snow%d_%d" % (k, i), Vector((math.sin(a) * r, math.cos(a) * r * 0.9, z)), 0.06 - 0.008 * k, snow, back,
                    sz=0.8)
    for s in (-1, 1):                     # ombreiras com cristais de gelo
        bk_pauldron("Pauldron%d" % s, back, s, silver, silver_d, tip, r=0.095,
                    spikes=[((0.4, 0.1, 1.0), 0.26, 0.04, 0.0), ((1.0, 0.2, 0.6), 0.2, 0.034, 0.0),
                            ((0.0, 0.7, 0.8), 0.17, 0.03, 0.0), ((0.9, -0.3, 0.9), 0.14, 0.026, 0.0)], spike_mats=(ice, tip))
    bk_finish("c_frost", ("fr_tip", "fx_ice"))


def build_c_storm():
    storm = bk_fx("fx_storm", "#2E3A5E", "#8FD0FF", 0.6)
    steel, steel_d = gm("sm_steel_flat", "#59647E", 0.5), gm("sm_steeld_flat", "#2C3348", 0.55)
    gold = gm("sm_gold_flat", "#F2CF4A", 0.5)
    bolt = mat("sm_bolt", hexc("#FFF6B0"), 0.3, 0.0, emit=hexc("#FFE860"), strength=2.6)
    back = empty("Back", (0, 0, 0))
    cloth = empty("Cloth", (0, 0, 0), back)

    def zig(u):
        return 0.16 * abs(((u * 9) % 1.0) - 0.5) * 2.0          # barra em dentes de raio

    P = bk_cape("CapeCloth", cloth, [storm, gold, bolt], lambda t, u, f, i, j: 1 if (u < 0.04 or u > 0.96) else
                (2 if t > 0.94 else 0), z1=0.16, r1=0.37, arc1=3.1, folds=0.035, rows=24, cols=36, hem=zig, lining=steel_d)
    zz = [(-0.03, 0.2), (0.035, 0.05), (-0.01, 0.05), (0.03, -0.2), (-0.035, -0.04), (0.01, -0.04)]
    o, tu, tv = bk_on_cloth(P, 0.36, 0.5)
    g_plate("Sigil", [(x * 1.6, y * 1.1) for x, y in zz], o, tu, tv, 0.007, bolt, cloth)        # raio no meio das costas
    g_pipe("SigilRing", [P(0.36 + 0.16 * math.cos(a), 0.5 + 0.2 * math.sin(a), 0.006)[0] for a in
                         (q * math.pi / 10 for q in range(20))], 0.006, gold, cloth, sides=5, loop=True)
    g_pipe("Collar", [Vector((math.sin(a) * 0.16, math.cos(a) * 0.14 + 0.01, 1.5)) for a in
                      (q * math.pi / 10 for q in range(20))], 0.036, steel, back, sides=8, loop=True)
    for s in (-1, 1):                     # ombreiras de aço com raio em pé
        sh = bk_pauldron("Pauldron%d" % s, back, s, steel, steel_d, bolt, r=0.1)
        g_plate("Bolt%d" % s, [(x * 1.3, y * 0.9 + 0.2) for x, y in zz], sh + Vector((s * 0.03, 0, 0.0)), Vector((s, 0, 0)),
                Vector((0, 0, 1)), 0.008, bolt, back)
        g_plate("BoltB%d" % s, [(x * 0.9, y * 0.6 + 0.13) for x, y in zz], sh + Vector((s * 0.03, 0.05, 0.0)),
                Vector((0, 1, 0)), Vector((0, 0, 1)), 0.007, gold, back)
    bk_finish("c_storm", ("sm_bolt", "fx_storm"))


def build_c_verdant():
    nat = bk_fx("fx_nature", "#2F8A4E", "#B8F06A", 0.5)
    leaf, leaf_d = gm("vd_leaf_flat", "#4FB85A", 0.8), gm("vd_leafd_flat", "#256E3C", 0.8)
    bark, bark_d = gm("vd_bark_flat", "#6A4A2C", 0.8), gm("vd_barkd_flat", "#3E2A18", 0.8)
    petal = gm("vd_petal_flat", "#FF9CC8", 0.7)
    pollen = mat("vd_pollen", hexc("#FFF0A0"), 0.3, 0.0, emit=hexc("#FFE060"), strength=2.0)
    back = empty("Back", (0, 0, 0))
    cloth = empty("Cloth", (0, 0, 0), back)
    P = bk_cape("CapeCloth", cloth, [nat, bark, leaf_d], lambda t, u, f, i, j: 1 if (u < 0.035 or u > 0.965) else
                (2 if t > 0.93 else 0), z1=0.2, r1=0.36, arc1=3.1, folds=0.035, rows=24, cols=34,
                hem=lambda u: 0.08 * abs(math.sin(u * math.pi * 8)), lining=leaf_d)
    bk_hem_drops("HemLeaf", P, cloth, (leaf, leaf_d), 17, 0.17, 0.045, tip_from=0.7)
    bk_chain("Vine", P, 0.14, 0.12, 0.88, 0.12, bark, cloth, r=0.009,
             pend=lambda i, o, tu, tv: bk_ball("Bud%d" % i, o, 0.022, pollen, cloth))
    # manto de folhas nos ombros, com flores
    for k, (z, r, ln) in enumerate(((1.5, 0.19, 0.17), (1.44, 0.22, 0.21))):
        bk_feather_ring("Leaf%d_" % k, back, (leaf, leaf_d), z, r, 15 + k * 2, -2.0, 2.0, ln, 0.06, droop=0.55, tip_from=0.7)
    for i, a in enumerate((-1.5, -0.8, 0.0, 0.8, 1.5)):
        c = Vector((math.sin(a) * 0.2, math.cos(a) * 0.18, 1.535))
        bk_ball("Bloom%d" % i, c, 0.03, pollen, back)
        for q in range(5):
            b = q * 2 * math.pi / 5
            d = Vector((math.sin(a) * 0.4 + math.cos(b) * math.cos(a), math.cos(a) * 0.4 - math.cos(b) * math.sin(a), math.sin(b)))
            bk_feather("Petal%d_%d" % (i, q), c, d, Vector((math.sin(a), math.cos(a), 0.3)), 0.06, 0.026, (petal, petal),
                       back, thick=0.008, segs=4)
    g_pipe("Collar", [Vector((math.sin(a) * 0.16, math.cos(a) * 0.14 + 0.01, 1.5)) for a in
                      (q * math.pi / 10 for q in range(20))], 0.04, bark_d, back, sides=8, loop=True)
    bk_finish("c_verdant", ("vd_pollen", "fx_nature"))


# paletas da capa do Cavaleiro Dragão (pano, pano escuro, borda, painel, gema, brilho da gema)
DKC_PAL = {
    "dark": ("#1C0C10", "#0F0709", "#A9875A", "#4A0C14", "#E8301C", "#FF4A1A"),
    "ice": ("#4A7DB5", "#2C5B94", "#E2EEF8", "#9FD2F0", "#5FE0FF", "#7FEAFF"),
}


def _build_c_dragonknight(variant):
    """Capa do Cavaleiro Dragão Sombrio (antes parte da armadura): pano preto-vinho caindo até a canela, painel
    central vermelho-sangue com filetes de cobre, barra com duas linhas onduladas de cobre e uma gema de brasa na gola."""
    pc = DKC_PAL[variant]
    pre = "dkc_" + variant + "_"
    cloth_m, cloth_d = gm(pre + "cloth_flat", pc[0], 0.9), gm(pre + "clothd_flat", pc[1], 0.9)
    copper = gm(pre + "copper_flat", pc[2], 0.7)
    blood = gm(pre + "blood_flat", pc[3], 0.9)
    gem = mat(pre + "gem", hexc(pc[4]), 0.3, 0.0, emit=hexc(pc[5]), strength=1.6)
    back = empty("Back", (0, 0, 0))
    cloth = empty("Cloth", (0, 0, 0), back)
    fold = bk_fold()

    def mf(t, u, f, i, j):
        c = abs(u - 0.5)
        if u < 0.03 or u > 0.97 or t > 0.965 or 0.745 < t < 0.76:
            return 2                                   # borda e friso de cobre
        if 0.095 < c < 0.115:
            return 2                                   # filetes do painel central
        if c <= 0.095:
            return 3                                   # painel vermelho-sangue
        return fold(t, u, f)

    P = bk_cape("CapeCloth", cloth, [cloth_m, cloth_d, copper, blood], mf, z1=0.30, r1=0.38, arc1=3.0, folds=0.035,
                nf=4, rows=30, cols=40, lining=cloth_d)
    for k, (t0, amp) in enumerate(((0.86, 0.012), (0.91, 0.01))):      # linhas onduladas de cobre perto da barra
        pts = [P(t0 + amp * math.sin(u * math.pi * 10 + k), u, 0.004)[0] for u in [x / 60 for x in range(61)]]
        g_pipe("HemLine%d" % k, pts, 0.0035, copper, cloth, sides=6)
    o, tu, tv = bk_on_cloth(P, 0.04, 0.5)
    g_cap("CapeGem", o, P(0.04, 0.5)[2], tu, 0.02, 0.026, 0.01, gem, cloth, rings=4, sides=10)
    bk_finish("c_dragonknight_" + variant, (pre + "gem",))


def build_c_dragonknight_dark():
    _build_c_dragonknight("dark")


def build_c_dragonknight_ice():
    _build_c_dragonknight("ice")


BACK = [("b_seraph", build_b_seraph), ("b_abyss", build_b_abyss), ("b_phoenix", build_b_phoenix),
        ("b_crystal", build_b_crystal), ("b_mech", build_b_mech), ("b_dragon", build_b_dragon), ("b_fairy", build_b_fairy),
        ("c_dragonking", build_c_dragonking), ("c_starry", build_c_starry), ("c_wanderer", build_c_wanderer),
        ("c_half", build_c_half), ("c_flame", build_c_flame), ("c_frost", build_c_frost), ("c_storm", build_c_storm),
        ("c_verdant", build_c_verdant), ("c_dragonknight_dark", build_c_dragonknight_dark),
        ("c_dragonknight_ice", build_c_dragonknight_ice)]
