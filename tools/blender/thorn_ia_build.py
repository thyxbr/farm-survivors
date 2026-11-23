"""Espinheira, a Guardiã-Raiz, gerada por IA local (chefe do Covil das Raízes; docs/EQUIPAMENTO_POR_IA.md, Monstros).

  blender -b --factory-startup --python tools/blender/thorn_ia_build.py -- [pintado.glb] [pasta_previa]

Entrada: a malha pintada pela IA (D:/ia3d/saida/espinheira/pintura/pintado.glb, vistas de
docs/renders/espinheira_ia/conceito). Saída: assets/models/thorn_tree_ia.glb com os MESMOS pivôs da Espinheira feita
por código (bosses.build_thorn_tree): Body, Head > Jaw, Crown > BoughL/BoughR > Hang0..3, LegL/R > KneeL/R e
ArmL/R > ElbowL/R > HandL/R; mais um esqueleto com um osso "<pivô>_skin" por pivô e a malha com pele. No jogo o
PivotSkin faz cada osso seguir o seu pivô; o código de animação (enemy.gd, _animate_thorn) não muda.

Pesos por regra (como o lobo, wolf_ia_build.py): o membro INTEIRO segue o osso dele (lição do lobo: coxa parada no
Body e só a canela girando fica estranho). Perna: tudo abaixo da virilha e a massa do quadril do lado dela; braço:
tudo fora do tronco abaixo do ombro e a calota do ombro. Cipós: achados por fatia (fios finos que pendem da copa),
cada um no Hang do seu lado e da sua metade (frente/trás). Copa: centro no Crown, lados nos BoughL/BoughR.

Boca: a IA esculpiu uma fenda sob o nariz (z 3,345); o corte segue essa fenda, o lábio de baixo e a barba vão para a
mandíbula (Jaw) e um saco escuro por dentro tapa o vão quando ela abre.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SRC = ARGS[0] if ARGS else os.path.join(os.environ.get("IA3D", "D:/ia3d"), "saida/espinheira/pintura/pintado.glb")
PREVIA = ARGS[1] if len(ARGS) > 1 else ""
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets/models/thorn_tree_ia.glb")

HEIGHT = 6.3       # do pé ao topo da copa (a Espinheira de código tem 6,4 m com a copa)
FACES = 20000      # malha do jogo (a IA entrega 40 mil); chefe grande, um só na sala
TEX = 2048

# ---------------------------------------------------------------- pivôs, medidos na malha normalizada (fatias)
# frente = -Y, esquerda = +X. Pernas: colunas grossas, centro em x ~0,85 até o joelho; a virilha fica em z 1,35.
BODY = Vector((0, -0.05, 1.5))
LEG = {"L": (Vector((0.62, -0.05, 1.55)), Vector((0.86, -0.12, 0.75)), Vector((0.9, -0.08, 0.0))),
       "R": (Vector((-0.62, -0.05, 1.55)), Vector((-0.88, -0.14, 0.75)), Vector((-0.92, -0.1, 0.0)))}
# braço: sobe reto do cotovelo ao ombro (x ~1,47) e do cotovelo desce para fora e para a frente até a mão
ARM = {"L": (Vector((1.05, 0.1, 3.45)), Vector((1.45, 0.12, 2.6)), Vector((1.88, -0.78, 1.85)),
             Vector((2.05, -1.05, 1.05))),
       "R": (Vector((-1.05, 0.1, 3.45)), Vector((-1.45, 0.15, 2.6)), Vector((-1.86, -0.76, 1.85)),
             Vector((-2.05, -1.05, 1.05)))}
HEAD = Vector((0, -0.35, 3.25))     # rosto: frente do alto do tronco
MOUTH_Z = 3.345                     # fenda esculpida sob o nariz (perfil: lábio de cima y -0,96, de baixo -1,10)
MOUTH_X = 0.3                       # meia largura da boca (vista de frente)
MOUTH_Y = -0.84                     # do canto da boca para a frente
MOUTH_FRONT = -1.2                  # até o lábio (a ponta do nariz, na mesma altura em y -1,35, não é cortada)
JAW = Vector((0, -0.62, 3.32))      # dobradiça atrás do canto, dentro da cabeça
CROWN = Vector((0, -0.05, 4.4))     # onde os galhos mestres se separam
BOUGH_X = 0.25


def smooth(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


bpy.ops.wm.read_factory_settings(use_empty=True)
scn = bpy.context.scene
bpy.ops.import_scene.gltf(filepath=SRC)
ob = next(o for o in scn.objects if o.type == 'MESH')
for o in list(scn.objects):
    if o is not ob:
        bpy.data.objects.remove(o)
me = ob.data
me.transform(ob.matrix_world)
ob.matrix_world = Matrix.Identity(4)
ob.parent = None

# ---------------------------------------------------------------- normaliza: altura HEIGHT, pé em z 0, centro dos pés na origem
zs = [v.co.z for v in me.vertices]
S, z0 = HEIGHT / (max(zs) - min(zs)), min(zs)
me.transform(Matrix.Scale(S, 4) @ Matrix.Translation((0, 0, -z0)))
lx = [v.co.x for v in me.vertices if v.co.z < 0.6]
ly = [v.co.y for v in me.vertices if v.co.z < 0.6]
me.transform(Matrix.Translation((-(min(lx) + max(lx)) / 2, -(min(ly) + max(ly)) / 2, 0)))

bpy.context.view_layer.objects.active = ob
ob.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=1e-6)
bpy.ops.object.mode_set(mode='OBJECT')
antes = len(me.polygons)
mod = ob.modifiers.new("dec", "DECIMATE")
mod.ratio = min(1.0, FACES / len(me.polygons))
mod.delimit = {'UV'}
bpy.ops.object.modifier_apply(modifier="dec")
print("MALHA %d -> %d faces" % (antes, len(me.polygons)))


def in_mouth(co, pad=0.0):
    return MOUTH_FRONT - pad < co.y < MOUTH_Y + pad and abs(co.x) < MOUTH_X + pad and abs(co.z - MOUTH_Z) < 0.06 + pad


# ---------------------------------------------------------------- boca: corta na fenda esculpida
bm = bmesh.new()
bm.from_mesh(me)
p0, n = Vector((0, 0, MOUTH_Z)), Vector((0, 0, 1))
faces = [f for f in bm.faces if any(in_mouth(v.co, 0.02) for v in f.verts)]
geom = list({e for f in faces for e in f.edges}) + faces + list({v for f in faces for v in f.verts})
res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=p0, plane_no=n, dist=1e-5)
cut = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)
       and all(MOUTH_FRONT < v.co.y < MOUTH_Y and abs(v.co.x) < MOUTH_X for v in e.verts)]
bmesh.ops.split_edges(bm, edges=cut)
print("BOCA %d arestas cortadas" % len(cut))
bm.to_mesh(me)
bm.free()
below = {}
vf = {}
for p in me.polygons:
    for i in p.vertices:
        vf.setdefault(i, []).append(p.center)
for v in me.vertices:
    below[v.index] = v.co.z < MOUTH_Z - 1e-4
    if abs(v.co.z - MOUTH_Z) < 2e-4 and v.co.y < MOUTH_Y and abs(v.co.x) < MOUTH_X:
        cs = vf.get(v.index, [])
        if cs:
            below[v.index] = (sum(cs, Vector()) / len(cs)).z < MOUTH_Z

# ---------------------------------------------------------------- cipós: fios finos que pendem da copa (por fatia)
V = [v.co.copy() for v in me.vertices]
vine = set()
BAND = 0.06
LINK = 0.15     # malha reduzida: ~8 cm entre vértices; com menos o tronco vira fatias "finas"
bands = {}
for i, co in enumerate(V):
    if 3.2 < co.z < 4.8:
        bands.setdefault(int(co.z / BAND), []).append(i)
for idx in bands.values():
    par = {i: i for i in idx}

    def find(a):
        while par[a] != a:
            par[a] = par[par[a]]
            a = par[a]
        return a
    for a_ in range(len(idx)):
        ia = idx[a_]
        for b_ in range(a_ + 1, len(idx)):
            ib = idx[b_]
            if abs(V[ia].x - V[ib].x) < LINK and abs(V[ia].y - V[ib].y) < LINK:
                par[find(ia)] = find(ib)
    groups = {}
    for i in idx:
        groups.setdefault(find(i), []).append(i)
    for g in groups.values():
        xs_ = [V[i].x for i in g]
        ys_ = [V[i].y for i in g]
        if max(xs_) - min(xs_) < 0.3 and max(ys_) - min(ys_) < 0.3:
            vine.update(g)
# componentes ligados só por vértices de cipó: cada fio é um
adj = {}
for e in me.edges:
    a, b = e.vertices
    adj.setdefault(a, []).append(b)
    adj.setdefault(b, []).append(a)
for _ in range(2):    # fecha buracos de uma fatia (vértice cercado de cipó)
    add = {i for i in range(len(V)) if i not in vine and 3.2 < V[i].z < 4.8 and adj.get(i)
           and sum(1 for j in adj[i] if j in vine) * 2 > len(adj[i])}
    vine |= add
comp, seen = [], set()
for i in vine:
    if i in seen:
        continue
    st, c = [i], []
    while st:
        u = st.pop()
        if u in seen:
            continue
        seen.add(u)
        c.append(u)
        st.extend(j for j in adj.get(u, []) if j in vine and j not in seen)
    comp.append(c)


def outside_trunk(c):
    m = min((V[i] for i in c), key=lambda p: p.z)     # a ponta de baixo do fio pende longe do tronco
    return (m.x / 1.0) ** 2 + (m.y / 1.05) ** 2 > 1.0


# fio de verdade (não lasca) e fora do tronco (casca fina do alto do tronco também passa no teste da fatia)
comp = [c for c in comp if max(V[i].z for i in c) - min(V[i].z for i in c) > 0.35 and outside_trunk(c)
        and max(V[i].z for i in c) > 4.0]     # pende da copa (os tocos de galho do ombro, não)
vine = {i for c in comp for i in c}
vines = []
for c in comp:
    top = max((V[i] for i in c), key=lambda p: p.z)
    bot = min((V[i] for i in c), key=lambda p: p.z)
    vines.append({"verts": c, "top": top.copy(), "bot": bot.copy()})
print("CIPOS", len(vines), [(round(v["bot"].x, 2), round(v["bot"].y, 2), round(v["top"].z, 2),
                             round(v["bot"].z, 2)) for v in vines])
# Hang0/1 = lado esquerdo (+X) frente/trás; Hang2/3 = direito frente/trás (na Espinheira de código Hang0/1 ficam
# no BoughL e Hang2/3 no BoughR)
HANG = {}
for v in vines:
    k = (0 if v["top"].x > 0 else 2) + (0 if v["top"].y < 0 else 1)
    v["hang"] = k
    HANG.setdefault(k, []).append(v["top"])
for k in range(4):
    if k not in HANG:     # lado sem fio nessa metade: pivô no meio da copa daquele lado (fica sem pele)
        HANG[k] = [Vector(((1 if k < 2 else -1) * 1.2, -0.3 if k % 2 == 0 else 0.3, 4.65))]
HANG = {k: sum(p, Vector()) / len(p) for k, p in HANG.items()}
vine_of = {}
for v in vines:
    for i in v["verts"]:
        vine_of[i] = v

# ---------------------------------------------------------------- textura e material (pintura da IA, _flat)
img = next((i for i in bpy.data.images if i.size[0] > 0), None)
if img:
    if img.size[0] != TEX:
        img.scale(TEX, TEX)
    img.name = "thorn_ia_albedo"
me.materials.clear()
paint = bpy.data.materials.new("tia_paint_flat")     # _flat: a luz já vem pintada, o toon não soma sombra de forma
paint.use_nodes = True
bsdf = next(nd for nd in paint.node_tree.nodes if nd.type == 'BSDF_PRINCIPLED')
if img:
    tx = paint.node_tree.nodes.new("ShaderNodeTexImage")
    tx.image = img
    paint.node_tree.links.new(tx.outputs["Color"], bsdf.inputs["Base Color"])
bsdf.inputs["Roughness"].default_value = 0.9
me.materials.append(paint)
for a in list(me.color_attributes):
    me.color_attributes.remove(a)
for p in me.polygons:
    p.use_smooth = True
ob.name = me.name = "ThornIA"

# saco escuro atrás da fenda: metade de cima na cabeça, de baixo na mandíbula
sk = bmesh.new()
RING = 16
rows = []
for k in range(7):
    y = MOUTH_Y - 0.02 - k * 0.035
    w = MOUTH_X * 0.85 * math.sqrt(max(0.15, 1 - ((k - 3) / 3.6) ** 2))
    rows.append([sk.verts.new((w * math.cos(a), y, MOUTH_Z + (0.05 if math.sin(a) > 0 else 0.07) * math.sin(a)))
                 for a in [2 * math.pi * j / RING for j in range(RING)]])
for r0, r1 in zip(rows, rows[1:]):
    for j in range(RING):
        sk.faces.new((r0[j], r0[(j + 1) % RING], r1[(j + 1) % RING], r1[j]))
sk.faces.new(rows[0][::-1])
sk.faces.new(rows[-1])
bmesh.ops.recalc_face_normals(sk, faces=sk.faces)
sme = bpy.data.meshes.new("ThornIA_Mouth")
sk.to_mesh(sme)
sk.free()
sme.uv_layers.new(name="UVMap")
mouth = bpy.data.objects.new("ThornIA_Mouth", sme)
scn.collection.objects.link(mouth)
dark = bpy.data.materials.new("tia_mouth_flat")
dark.use_nodes = True
db = next(nd for nd in dark.node_tree.nodes if nd.type == 'BSDF_PRINCIPLED')
db.inputs["Base Color"].default_value = (0.07, 0.02, 0.03, 1)
dimg = bpy.data.images.new("thorn_ia_mouth", 4, 4)     # textura lisa: a prévia (cor de textura) mostra o escuro
dimg.pixels = [0.07, 0.02, 0.03, 1.0] * 16
dtx = dark.node_tree.nodes.new("ShaderNodeTexImage")
dtx.image = dimg
dark.node_tree.links.new(dtx.outputs["Color"], db.inputs["Base Color"])
sme.materials.append(dark)


# ---------------------------------------------------------------- pivôs (empties), como a Espinheira de código
def empty(name, loc, parent=None):
    e = bpy.data.objects.new(name, None)
    e.location = loc
    scn.collection.objects.link(e)
    if parent:
        e.parent = parent
        e.location = Vector(loc) - parent.matrix_world.translation
        bpy.context.view_layer.update()
    return e


root = empty("Thorn", (0, 0, 0))
piv = {"Body": empty("Body", BODY, root)}
piv["Head"] = empty("Head", HEAD, piv["Body"])
piv["Jaw"] = empty("Jaw", JAW, piv["Head"])
piv["Crown"] = empty("Crown", CROWN, piv["Body"])
BOUGH = {"L": Vector((BOUGH_X, CROWN.y, CROWN.z + 0.05)), "R": Vector((-BOUGH_X, CROWN.y, CROWN.z + 0.05))}
for sd in "LR":
    piv["Bough" + sd] = empty("Bough" + sd, BOUGH[sd], piv["Crown"])
for k, p in HANG.items():
    piv["Hang%d" % k] = empty("Hang%d" % k, p, piv["BoughL" if k < 2 else "BoughR"])
for sd in "LR":
    h, kn, ft = LEG[sd]
    piv["Leg" + sd] = empty("Leg" + sd, h, root)
    piv["Knee" + sd] = empty("Knee" + sd, kn, piv["Leg" + sd])
    sh, el, wr, tip = ARM[sd]
    piv["Arm" + sd] = empty("Arm" + sd, sh, piv["Body"])
    piv["Elbow" + sd] = empty("Elbow" + sd, el, piv["Arm" + sd])
    piv["Hand" + sd] = empty("Hand" + sd, wr, piv["Elbow" + sd])

# ---------------------------------------------------------------- esqueleto: um osso por pivô, a cabeça do osso no pivô
arm = bpy.data.armatures.new("ThornIA_Rig")
rig = bpy.data.objects.new("ThornIA_Rig", arm)
scn.collection.objects.link(rig)
rig.parent = root
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='EDIT')
up = Vector((0, 0, 0.4))
BONES = {"Body": (None, BODY, BODY + up * 3), "Head": ("Body", HEAD, HEAD + Vector((0, -0.5, 0.3))),
         "Jaw": ("Head", JAW, JAW + Vector((0, -0.45, -0.3))), "Crown": ("Body", CROWN, CROWN + up)}
for sd in "LR":
    BONES["Bough" + sd] = ("Crown", BOUGH[sd], BOUGH[sd] + Vector((1.0 if sd == "L" else -1.0, 0, 0.4)))
    h, kn, ft = LEG[sd]
    BONES["Leg" + sd] = (None, h, kn)
    BONES["Knee" + sd] = ("Leg" + sd, kn, ft)
    sh, el, wr, tip = ARM[sd]
    BONES["Arm" + sd] = ("Body", sh, el)
    BONES["Elbow" + sd] = ("Arm" + sd, el, wr)
    BONES["Hand" + sd] = ("Elbow" + sd, wr, tip)
for k, p in HANG.items():
    BONES["Hang%d" % k] = ("BoughL" if k < 2 else "BoughR", p, p - up * 2)
SK = "_skin"     # osso "<pivô>_skin": o PivotSkin tira o sufixo (com o mesmo nome do pivô o Godot renomeia o osso)
for name, (par, h, t) in BONES.items():
    b = arm.edit_bones.new(name + SK)
    b.head, b.tail = h, t
for name, (par, h, t) in BONES.items():
    if par:
        arm.edit_bones[name + SK].parent = arm.edit_bones[par + SK]
bpy.ops.object.mode_set(mode='OBJECT')


# ---------------------------------------------------------------- pesos por regra
def seg_t(p, a, b):
    d = b - a
    return max(0.0, min(1.0, (p - a).dot(d) / d.length_squared))


def seg_dist(p, a, b):
    return (p - (a + (b - a) * seg_t(p, a, b))).length


def chain_weights(co, pts, names, blend):
    """Segmento mais perto da corrente, com mistura de `blend` m em cada junta."""
    d = [seg_dist(co, pts[i], pts[i + 1]) for i in range(len(names))]
    i = min(range(len(names)), key=lambda k: d[k])
    W = {names[i]: 1.0}
    for j in (i - 1, i + 1):
        if 0 <= j < len(names):
            dj = (co - pts[max(i, j)]).length
            if dj < blend:
                s = 0.5 * (1 - dj / blend)
                W[names[j]] = s
                W[names[i]] -= s
    return W


def add(W, src, f):
    for k, w in src.items():
        W[k] = W.get(k, 0.0) + w * f


def weights(i, co):
    W = {}
    sd = "L" if co.x > 0 else "R"
    ax = abs(co.x)
    if i in vine_of:      # cipó: o fio no Hang dele; a raiz (perto da copa) mistura com o galho
        v = vine_of[i]
        t = smooth(v["top"].z - 0.25, v["top"].z - 0.02, co.z)
        hb = "Hang%d" % v["hang"]
        add(W, {hb: 1.0 - t, "Bough" + ("L" if v["hang"] < 2 else "R"): t}, 1.0)
        return W
    # perna: abaixo da virilha 100%; o quadril do lado dela até z 1,9 (perto do eixo da perna)
    h, kn, ft = LEG[sd]
    # (só na coluna da perna, x < 1,2: as mãos pendem nessa mesma altura, em x ~2; rodada 1 elas iam 85% na perna)
    leg = 1.0 if co.z < 1.3 else (1 - smooth(1.35, 1.95, co.z)) * smooth(0.08, 0.38, ax) * (1 - smooth(1.1, 1.3, ax))
    # braço: fora do tronco abaixo do ombro; a calota do ombro mistura com o Body
    sh, el, wr, tip = ARM[sd]
    arm_w = 0.0
    if co.z < 3.4:
        arm_w = smooth(0.9, 1.12, ax) if co.z > 2.2 else smooth(1.0, 1.3, ax)
    elif co.z < 4.05:
        arm_w = smooth(0.95, 1.25, ax) * (1 - smooth(3.55, 4.0, co.z))
    if co.z >= 1.3:
        arm_w = min(arm_w, 1.0 - leg)
    else:
        # abaixo da virilha: dedo se está mais perto da mão que da coluna da perna (as raízes do pé ficam abaixo
        # de z 0,8). Rodada 1: com só x > 1,45 as pontas dos dedos de dentro ficavam na perna e viravam tiras
        # esticadas quando o braço subia no golpe
        d_hand = seg_dist(co, wr, tip)
        d_leg = math.hypot(co.x - kn.x, co.y - kn.y)
        arm_w = 1.0 if co.z > 0.8 and d_hand < d_leg else 0.0
    if arm_w > 0:
        add(W, chain_weights(co, [sh, el, wr, tip], ["Arm" + sd, "Elbow" + sd, "Hand" + sd], 0.18), arm_w)
    leg = min(leg, 1.0 - arm_w)
    if leg > 0:
        add(W, chain_weights(co, [h, kn, ft], ["Leg" + sd, "Knee" + sd], 0.2), leg)
    rest = 1.0 - leg - arm_w
    if rest <= 1e-4:
        return W
    # copa: acima dos galhos; os lados nos BoughL/R, o miolo no Crown
    crown = smooth(4.05, 4.5, co.z)
    side = smooth(0.35, 0.95, ax)
    # rosto (cabeça) e mandíbula: frente do alto do tronco
    head = smooth(-0.55, -0.75, co.y) * smooth(2.55, 2.85, co.z) * (1 - smooth(4.05, 4.3, co.z)) * (1 - smooth(0.55, 0.75, ax))
    jaw = 0.0
    nose = co.y < MOUTH_FRONT and co.z > 3.2       # a ponta do nariz desce até z 3,3, na frente do lábio
    if co.z < MOUTH_Z + 1e-4 and (below[i] or co.z < MOUTH_Z - 1e-3) and not nose:
        jaw = smooth(-0.8, -0.92, co.y) * smooth(2.5, 2.7, co.z) * (1 - smooth(MOUTH_X, MOUTH_X + 0.15, ax))
    jaw = min(jaw, head) if head > 0 else 0.0
    body = max(0.0, 1.0 - crown - head)
    add(W, {"Crown": crown * (1 - side), "Bough" + sd: crown * side, "Head": head - jaw, "Jaw": jaw, "Body": body},
        rest)
    return W


for o in (ob, mouth):
    o.parent = rig
    md = o.modifiers.new("rig", "ARMATURE")
    md.object = rig
    groups = {name: o.vertex_groups.new(name=name + SK) for name in BONES}
    for v in o.data.vertices:
        if o is mouth:
            W = {"Jaw": 1.0} if v.co.z < MOUTH_Z - 1e-4 else {"Head": 1.0}
        else:
            W = weights(v.index, v.co)
        W = {k: w for k, w in W.items() if w > 1e-4}
        tot = sum(W.values()) or 1.0
        for k, w in W.items():
            groups[k].add([v.index], w / tot, 'REPLACE')

# partes soltas: a malha da IA é uma casca só (o corte da boca não separa: a fenda acaba antes dos cantos)
bm = bmesh.new()
bm.from_mesh(me)
seen, parts = set(), []
for v in bm.verts:
    if v.index in seen:
        continue
    stack, c = [v], []
    while stack:
        u = stack.pop()
        if u.index in seen:
            continue
        seen.add(u.index)
        c.append(u.co.copy())
        stack.extend(e.other_vert(u) for e in u.link_edges)
    parts.append(c)
bm.free()
print("PEDACOS malha=%d (esperado 1)" % len(parts), [(len(c), tuple(round(x, 2) for x in sum(c, Vector()) / len(c)))
                                                      for c in sorted(parts, key=len)[:-1]])

# ---------------------------------------------------------------- prévia: pesos (cor do osso dominante) e uma pose de teste
COLORS = {"Body": (0.55, 0.55, 0.55), "Head": (1.0, 0.85, 0.2), "Jaw": (1.0, 0.3, 0.1), "Crown": (0.2, 0.8, 0.3),
          "BoughL": (0.1, 0.5, 1.0), "BoughR": (0.7, 0.2, 1.0), "Hang0": (0.0, 1.0, 1.0), "Hang1": (0.0, 0.55, 0.55),
          "Hang2": (1.0, 0.4, 0.8), "Hang3": (0.6, 0.15, 0.4), "LegL": (0.9, 0.1, 0.1), "KneeL": (0.5, 0.05, 0.05),
          "LegR": (0.1, 0.3, 0.9), "KneeR": (0.05, 0.1, 0.45), "ArmL": (1.0, 0.6, 0.0), "ElbowL": (0.75, 0.95, 0.1),
          "HandL": (0.4, 0.25, 0.0), "ArmR": (0.0, 0.85, 0.6), "ElbowR": (0.6, 0.7, 1.0), "HandR": (0.05, 0.3, 0.2)}
if PREVIA:
    os.makedirs(PREVIA, exist_ok=True)
    scn.render.engine = "BLENDER_WORKBENCH"
    sh_ = scn.display.shading
    sh_.light = "FLAT"
    scn.view_settings.view_transform = "Standard"
    scn.world = bpy.data.worlds.new("w")
    scn.world.color = (0.85, 0.85, 0.85)
    scn.render.resolution_x = scn.render.resolution_y = 900
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scn.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    scn.camera = cam
    # pesos: cor do osso dominante num atributo de cor por vértice (uma cópia, para não ir no GLB)
    wc = ob.copy()
    wc.data = me.copy()
    scn.collection.objects.link(wc)
    attr = wc.data.color_attributes.new("peso", 'FLOAT_COLOR', 'POINT')
    gname = {g.index: g.name[:-len(SK)] for g in ob.vertex_groups}
    for v in me.vertices:
        g = max(v.groups, key=lambda x: x.weight, default=None)
        c = COLORS.get(gname[g.group], (1, 1, 1)) if g else (1, 1, 1)
        attr.data[v.index].color = (*c, 1)
    marks = []
    for nm, e in piv.items():
        mk = bpy.data.objects.new("mk_" + nm, bpy.data.meshes.new("mk"))
        b2 = bmesh.new()
        bmesh.ops.create_uvsphere(b2, u_segments=10, v_segments=6, radius=0.07)
        b2.to_mesh(mk.data)
        b2.free()
        mk.location = e.matrix_world.translation
        mk.show_in_front = True
        scn.collection.objects.link(mk)
        marks.append(mk)
    VIEWS = (("frente", (0, -12, 3.15), (math.pi / 2, 0, 0)), ("lado", (-12, 0, 3.15), (math.pi / 2, 0, -math.pi / 2)),
             ("tres_quartos", (-8, -8, 6.0), None))

    def shoot(prefix):
        cam.data.ortho_scale = 7.2
        for nm, loc, rotc in VIEWS:
            cam.location = loc
            cam.rotation_euler = rotc if rotc else (Vector((0, 0, 3.0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
            scn.render.filepath = os.path.join(PREVIA, "%s_%s.png" % (prefix, nm))
            bpy.ops.render.render(write_still=True)
    ob.hide_render = mouth.hide_render = True
    sh_.color_type = "VERTEX"
    shoot("pesos")
    wc.hide_render = True
    for mk in marks:
        mk.hide_render = True
    ob.hide_render = mouth.hide_render = False
    sh_.color_type = "TEXTURE"
    pb = rig.pose.bones
    POSES = {"repouso": {}, "teste": {"LegL": -0.4, "KneeL": 0.7, "LegR": 0.35, "ArmR": -1.6, "ElbowR": -0.6,
                                      "HandR": -0.5, "ArmL": 0.4, "Jaw": 0.38, "Head": -0.04, "Crown": 0.1,
                                      "Hang0": 0.4, "Hang2": -0.4}}
    for pose, rot in POSES.items():
        for b in pb:
            b.rotation_mode = 'XYZ'
            b.rotation_euler = (0, 0, 0)
        for k, a in rot.items():     # giro em x do mundo, como o jogo
            b = pb[k + SK]
            mw = (rig.matrix_world @ b.bone.matrix_local).to_3x3()
            axw = mw.inverted() @ Vector((1, 0, 0))
            b.rotation_mode = 'AXIS_ANGLE'
            b.rotation_axis_angle = (a, *axw)
        bpy.context.view_layer.update()
        shoot(pose)
        cam.data.ortho_scale = 1.6
        cam.location = Vector((-2.5, -5.5, 3.5))
        cam.rotation_euler = (Vector((0, -1.0, 3.2)) - cam.location).to_track_quat("-Z", "Y").to_euler()
        scn.render.filepath = os.path.join(PREVIA, "%s_boca.png" % pose)
        bpy.ops.render.render(write_still=True)
    for b in pb:
        b.rotation_mode = 'XYZ'
        b.rotation_euler = (0, 0, 0)
    bpy.data.objects.remove(wc)
    for mk in marks:
        bpy.data.objects.remove(mk)

# ---------------------------------------------------------------- exporta (pivôs + esqueleto + malha com pele)
for o in scn.objects:
    o.select_set(True)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_yup=True,
                          export_animations=False, export_cameras=False, export_lights=False,
                          export_image_format='JPEG', export_jpeg_quality=88, export_skins=True,
                          export_def_bones=False)
print("EXPORT", OUT)
