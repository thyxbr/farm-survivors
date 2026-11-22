# Etapa 2 do rosto do Elmo do Dragão: constrói a parte de trás que o modelo gerado não tem.
# Técnica: o corte de trás do modelo é um perfil (cúpula do crânio + três fiadas de placas da nuca em degraus).
# Esse meio-perfil é GIRADO em volta do eixo do pescoço, de um lado ao outro: as fiadas dão a volta pela nuca e
# encontram o outro lado na mesma altura, com a mesma cor (cada ponto leva a cor do ponto da borda de onde saiu).
# Os chifres e a ponta da crista, que o corte abriu, são fechados com uma tampa abaulada.
# Uso:  OUT=<pasta com face_stage1.blend> blender --background --factory-startup --python dragon_face_back.py
import bpy, bmesh, os, math
from mathutils import Vector

OUTD = os.environ["OUT"].rstrip("/") + "/"
BACK_K = float(os.environ.get("BACK_K", "0.40"))      # fundo da nuca = meia largura x BACK_K
CHEVRON = 0.028                                       # as fiadas descem em V no meio das costas (vista de costas)
NP, NT = 170, 22                                      # pontos do perfil e passos do giro

bpy.ops.wm.open_mainfile(filepath=OUTD + "face_stage1.blend")
ob = bpy.data.objects["DragonFace"]
me = ob.data
bm = bmesh.new()
bm.from_mesh(me)
uvl = bm.loops.layers.uv.active
col = bm.loops.layers.color.active
bmesh.ops.delete(bm, geom=[e for e in bm.edges if not e.link_faces], context='EDGES')
bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_edges], context='VERTS')


def boundary_loops():
    """Laços fechados da borda, andando por ARESTAS (um vértice pode ser ponto de encontro de dois laços)."""
    be = set(e for e in bm.edges if len(e.link_faces) == 1)
    loops = []
    while be:
        e = next(iter(be))
        be.discard(e)
        a, b = e.verts
        loop, cur = [a, b], b
        while cur is not a:
            nxt = [x for x in cur.link_edges if x in be]
            if not nxt:
                break
            e2 = nxt[0]
            be.discard(e2)
            cur = e2.other_vert(cur)
            if cur is not a:
                loop.append(cur)
        loops.append(loop)
    return sorted(loops, key=lambda l: max(v.co.x for v in l) - min(v.co.x for v in l), reverse=True)


def vuv(v):
    l = v.link_loops[0]
    return l[uvl].uv.copy(), tuple(l[col])


loops = boundary_loops()
main = loops[0]
y_plane = sum(v.co.y for v in main) / len(main)
print("LOOPS", [len(l) for l in loops[:8]], "plano y=%.4f" % y_plane)

# ---- meio-perfil da direita (x >= 0), do alto ao fundo, e o correspondente da esquerda
top_i = max(range(len(main)), key=lambda i: main[i].co.z - abs(main[i].co.x) * 2)
main = main[top_i:] + main[:top_i]
if main[5].co.x < 0:
    main = [main[0]] + main[:0:-1]
bot_i = min(range(len(main)), key=lambda i: abs(main[i].co.x) * 2 + (main[i].co.z if i > 20 and i < len(main) - 20 else 99))
right, left = main[:bot_i + 1], [main[0]] + main[:bot_i - 1:-1]
print("perfil direita", len(right), "esquerda", len(left), "alto", tuple(round(c, 3) for c in right[0].co),
      "fundo", tuple(round(c, 3) for c in right[-1].co))


def resample(vs, n):
    pts = [v.co.copy() for v in vs]
    d = [0.0]
    for a, b in zip(pts, pts[1:]):
        d.append(d[-1] + (b - a).length)
    out, k = [], 0
    for i in range(n):
        t = d[-1] * i / (n - 1)
        while k < len(d) - 2 and d[k + 1] < t:
            k += 1
        f = (t - d[k]) / max(1e-9, d[k + 1] - d[k])
        out.append((pts[k].lerp(pts[k + 1], f), vs[k if f < 0.5 else k + 1]))
    return out


R = resample(right, NP)
L = resample(left, NP)
# cor das costas: placas no vermelho do elmo, friso de ouro na beirada de cada fiada (onde o perfil faz bico).
# (levar a cor ponto a ponto da borda deixava as costas riscadas e com emenda no meio)
allv = [v for v in bm.verts if v.link_loops]
def _c(v):
    return vuv(v)[1]
golds = sorted((v for v in allv if _c(v)[0] > 0.68 and 0.48 < _c(v)[1] < 0.75 and _c(v)[2] < 0.45
                and _c(v)[0] - _c(v)[2] > 0.3), key=lambda v: _c(v)[1])
reds = sorted((v for v in allv if 0.38 < _c(v)[0] < 0.7 and _c(v)[1] < 0.2 and _c(v)[2] < 0.22), key=lambda v: _c(v)[0])
C_GOLD, C_RED = _c(golds[len(golds) // 2])[:3], _c(reds[int(len(reds) * 0.6)])[:3]
print("cores: ouro", [round(c, 2) for c in C_GOLD], "vermelho", [round(c, 2) for c in C_RED], len(golds), len(reds))
V_GOLD = V_RED = main[0]


def flat_mat(name, c, rough, metal):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    lin = [((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c]
    b.inputs["Base Color"].default_value = (*lin, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    m.diffuse_color = (*lin, 1)
    return m


me.materials[0].name = "dh_face"
me.materials.append(flat_mat("dh_back", C_RED, 0.6, 0.0))
me.materials.append(flat_mat("dh_back_gold", (0.80, 0.64, 0.33), 0.4, 0.5))   # ouro da ficha
# olhos: as faces pintadas de laranja no rosto ganham material próprio, que acende no jogo
eye_m = flat_mat("dh_eye_flat", (1.0, 0.52, 0.2), 0.4, 0.0)
_b = next(n for n in eye_m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
_b.inputs["Emission Color"].default_value = (1.0, 0.25, 0.04, 1)
_b.inputs["Emission Strength"].default_value = 2.2
me.materials.append(eye_m)
xs = [(pr.x + (-pl.x)) / 2 for (pr, _), (pl, _) in zip(R, L)]
step = sum((R[i + 1][0] - R[i][0]).length for i in range(NP - 1)) / (NP - 1)
lip = [False] * NP
for i in range(4, NP - 4):
    if xs[i] == max(xs[i - 4:i + 5]) and xs[i] > 0.12 and xs[i] - min(xs[i - 4:i + 5]) > 0.006:
        for j in range(NP):
            if abs(j - i) * step < 0.008:
                lip[j] = True
print("bicos com ouro", sum(lip))
z_top = R[0][0].z
rows = []
for j in range(-1, NT + 2):                 # um passo a mais de cada lado: aba que entra por baixo da borda
    th = math.pi * min(max(j, -0.6), NT + 0.6) / NT
    row = []
    for (pr, vr), (pl, vl) in zip(R, L):
        k = min(1.0, max(0.0, j / NT))
        xr, xl = pr.x, -pl.x
        x = xr + (xl - xr) * k              # o lado esquerdo do modelo não é espelho exato: mistura no caminho
        y0 = pr.y + (pl.y - pr.y) * k
        z = pr.z + (pl.z - pr.z) * k
        s = math.sin(max(0.0, min(math.pi, th)))
        w = min(1.0, max(0.0, (z_top - 0.05 - z) / 0.08))
        keel = 0.007 * w * max(0.0, 1 - abs(th - math.pi / 2) / 0.11)      # quilha no meio das costas (ficha)
        p = Vector((x * math.cos(th), y0 + x * BACK_K * math.sin(th) + keel, z - CHEVRON * w * s ** 3))
        if j < 0 or j > NT:                 # aba: 4 mm para dentro e para a frente
            p = Vector((p.x * 0.985, y0 - 0.006, z))
        row.append((p, vr if k < 0.5 else vl))
    rows.append(row)
verts = [[bm.verts.new(p) for p, _ in row] for row in rows]
faces = []
for a, b, ra in zip(verts, verts[1:], rows):
    for i in range(NP - 1):
        f = bm.faces.new((a[i], a[i + 1], b[i + 1], b[i]))
        f.material_index = 2 if (lip[i] and lip[i + 1]) else 1
        faces.append(f)
        for lp in f.loops:
            ii = i if lp.vert in (a[i], b[i]) else i + 1
            u, c = vuv(V_GOLD if lip[ii] else V_RED)
            lp[uvl].uv = u
            lp[col] = c
bmesh.ops.recalc_face_normals(bm, faces=faces)
# para fora = para trás (+Y) no meio do giro
mid = faces[len(faces) // 2]
if mid.normal.y < 0:
    bmesh.ops.reverse_faces(bm, faces=faces)
print("costas: faces", len(faces))


# ---- tampas abauladas nos buracos do corte (chifres, crista, espinhos)
def cap(loop, bulge, rings=5):
    c = sum((v.co for v in loop), Vector()) / len(loop)
    n = len(loop)
    r_max = max((v.co - c).length for v in loop)
    ring_prev = loop
    made = []
    for k in range(1, rings + 1):
        f = 1 - k / rings
        if k < rings:
            ring = []
            for v in loop:
                d = v.co - c
                rr = d.length / r_max * f
                q = c + d * f
                q.y = v.co.y * f + c.y * (1 - f) + bulge * math.sqrt(max(0.0, 1 - f * f))
                ring.append(bm.verts.new(q))
        else:
            tip = bm.verts.new(c + Vector((0, bulge, 0)))
            ring = None
        for i in range(n):
            j = (i + 1) % n
            if ring is not None:
                made.append(bm.faces.new((ring_prev[i], ring_prev[j], ring[j], ring[i])))
            else:
                made.append(bm.faces.new((ring_prev[i], ring_prev[j], tip)))
        ring_prev = ring
    u, cc = vuv(loop[0])
    for f in made:
        for lp in f.loops:
            lp[uvl].uv = u
            lp[col] = vuv(loop[len(loop) // 2])[1]
    bmesh.ops.recalc_face_normals(bm, faces=made)
    if sum(f.normal.y for f in made) < 0:
        bmesh.ops.reverse_faces(bm, faces=made)
    return made


def tube_cap(loop, n=30, m=8):
    """Fecha um chifre/espinho cortado ao meio no comprido: liga as duas bordas do corte por arcos para trás,
    como a metade que faltava do tubo. A cor vem do próprio chifre (não da borda, que pega a tinta do corte)."""
    import numpy as np
    P = np.array([(v.co.x, v.co.z) for v in loop])
    c = P.mean(0)
    w, vec = np.linalg.eigh(np.cov((P - c).T))
    ax = vec[:, 1]
    t = (P - c) @ ax
    i0, i1 = int(t.argmin()), int(t.argmax())
    lp = loop[i0:] + loop[:i0]
    k = (i1 - i0) % len(loop)
    A, B = lp[:k + 1], [lp[0]] + lp[:k - 1:-1]
    RA, RB = resample(A, n), resample(B, n)
    ring1 = set()
    for v in loop:
        for e in v.link_edges:
            ring1.add(e.other_vert(v))
    cand = sorted((x for x in ring1 if x not in set(loop)), key=lambda x: sum(vuv(x)[1][:3]))
    u, cc = vuv(cand[int(len(cand) * 0.85)])       # tom claro do próprio chifre
    rows = []
    for j in range(m + 1):
        sj = j / m
        row = []
        for (pa, _), (pb, _) in zip(RA, RB):
            q = pa.lerp(pb, sj)
            q.y += 0.48 * (pa - pb).length * math.sin(math.pi * sj) - 0.002
            row.append(bm.verts.new(q))
        rows.append(row)
    made = []
    for ra, rb in zip(rows, rows[1:]):
        for i in range(n - 1):
            made.append(bm.faces.new((ra[i], ra[i + 1], rb[i + 1], rb[i])))
    for f in made:
        for l in f.loops:
            l[uvl].uv = u
            l[col] = cc
    bmesh.ops.recalc_face_normals(bm, faces=made)
    if sum(f.normal.y for f in made) < 0:
        bmesh.ops.reverse_faces(bm, faces=made)


ncap = 0
for lp in loops[1:]:
    zs = [v.co.z for v in lp]
    if min(zs) < 1.5 or len(lp) < 3:          # anel de baixo da gola: fica aberto (passa o pescoço)
        continue
    w = max(v.co.x for v in lp) - min(v.co.x for v in lp)
    try:
        if len(lp) > 60:
            tube_cap(lp)
            print("tampa", len(lp), "largura %.3f" % w)
        else:                                   # furinhos da redução: fecha reto
            cap(lp, bulge=0.0, rings=1)
        ncap += 1
    except ValueError:
        pass
print("buracos fechados", ncap)

# o olho é pintado na textura e a malha reduzida quase não tem faces ali: refina só a região dos olhos e
# separa pela cor da textura no meio de cada face pequena
import numpy as np
_img = next(i for i in bpy.data.images if i.size[0] > 0)
_W, _H = _img.size
_px = np.empty(_W * _H * 4, np.float32)
_img.pixels.foreach_get(_px)
_px = _px.reshape(_H, _W, 4)


def in_eye_box(c):
    return 0.02 < abs(c.x) < 0.14 and -0.2 < c.y < 0.0 and 1.68 < c.z < 1.76


def tex_at(f):
    u = sum(l[uvl].uv.x for l in f.loops) / len(f.loops)
    v = sum(l[uvl].uv.y for l in f.loops) / len(f.loops)
    return _px[min(_H - 1, int(v % 1.0 * _H)), min(_W - 1, int(u % 1.0 * _W)), :3]


def orange(c):
    return c[0] > 0.8 and 0.25 < c[1] < 0.68 and c[2] < 0.32


for _ in range(1):
    near = [f for f in bm.faces if in_eye_box(f.calc_center_median())]
    hot = set()
    for f in near:                       # só as faces que tocam o laranja (e as vizinhas) são refinadas
        if orange(tex_at(f)) or any(orange(_px[min(_H - 1, int(l[uvl].uv.y % 1.0 * _H)), min(_W - 1, int(l[uvl].uv.x % 1.0 * _W)), :3]) for l in f.loops):
            hot.add(f)
            for e in f.edges:
                hot.update(e.link_faces)
    edges = list({e for f in hot for e in f.edges})
    if edges:
        bmesh.ops.subdivide_edges(bm, edges=edges, cuts=2, use_grid_fill=True)
n_eye = 0
for f in bm.faces:
    if in_eye_box(f.calc_center_median()) and orange(tex_at(f)):
        f.material_index = 3
        n_eye += 1
print("faces dos olhos", n_eye)
bm.normal_update()
bm.to_mesh(me)
bm.free()
me.update()
for p in me.polygons:
    p.use_smooth = True
print("FINAL faces", len(me.polygons), "verts", len(me.vertices))
for im in bpy.data.images:
    if im.size[0] > 0 and im.filepath_raw:
        im.pack()
bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
bpy.ops.wm.save_as_mainfile(filepath=OUTD + "face_stage2.blend")
bpy.ops.wm.save_as_mainfile(filepath=OUTD + "face_base.blend", copy=True, compress=True)
print("STAGE2 DONE")
