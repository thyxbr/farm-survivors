"""Pernilongo do Brejo gerado por IA local (monstro do Pântano, docs/EQUIPAMENTO_POR_IA.md, seção Monstros).

  blender -b --factory-startup --python tools/blender/mosquito_ia_build.py -- [pintado.glb] [pasta_previa]

Entrada: a malha pintada pela IA (D:/ia3d/saida/pernilongo/pintura/pintado.glb, folha de três vistas do usuário).
Saída: assets/models/mosquito_ia.glb com os pivôs da Asa-couro (Body a 1,5 do chão, Head, WingL, WingR) e mais um
Tail (abdômen), um esqueleto com um osso `<pivô>_skin` por pivô e a malha com pele. No jogo o PivotSkin faz cada osso
seguir o seu pivô; a animação é a da Asa-couro (enemy.gd, _animate_bat), com batida mais rápida e o abdômen balançando.

Pesos por regra, cada uma com limite no eixo do membro:
- tórax e as seis patas no Body (as patas ficam firmes, penduradas);
- cada asa no osso dela: fora do tórax em x e acima do ombro em z, com a raiz misturada;
- cabeça e ferrão no Head: à frente do pescoço e acima das patas da frente;
- abdômen no Tail: atrás da cintura, abaixo das asas e fora das patas de trás. As patas de trás passam ao lado do
  abdômen; são achadas por fatia (em cada altura, grupo pequeno de vértices ligados é pata).
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SRC = ARGS[0] if ARGS else os.path.join(os.environ.get("IA3D", "D:/ia3d"), "saida/pernilongo/pintura/pintado.glb")
PREVIA = ARGS[1] if len(ARGS) > 1 else ""
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets/models/mosquito_ia.glb")

LENGTH = 1.3       # da ponta do ferrão ao fim do abdômen (o jogo ainda multiplica pela escala do tipo)
FACES = 8000       # malha do jogo (a IA entrega 40 mil); 14 pernilongos no Pântano
TEX = 1024
HOVER = 1.5        # altura do pivô do corpo, como a Asa-couro (_animate_bat põe o Body em 1,5 + balanço)

# ---------------------------------------------------------------- pivôs, medidos na malha normalizada (antes de subir)
# frente = -Y, esquerda = +X; z 0 = centro da caixa da malha da IA
BODY = Vector((0, -0.02, 0.07))       # centro do tórax
HEAD = Vector((0, -0.20, 0.08))       # pescoço, entre o tórax e a cabeça
TAIL = Vector((0, 0.16, -0.02))       # cintura: o abdômen gira daqui
TAIL_TIP = Vector((0, 0.62, -0.15))
WING = {"L": Vector((0.19, 0.06, 0.22)), "R": Vector((-0.19, 0.06, 0.22))}   # raiz da asa, no alto do tórax
# asa nova: lâmina em forma de folha aberta na horizontal (como no conceito), um pouco para cima e para trás
WING_SPAN, WING_SWEEP, WING_DIHEDRAL = 0.75, math.radians(18), math.radians(10)


def wing_dir(s):
    sx = 1 if s == "L" else -1
    return Vector((sx * math.cos(WING_SWEEP) * math.cos(WING_DIHEDRAL), math.sin(WING_SWEEP),
                   math.sin(WING_DIHEDRAL))).normalized()


WING_TIP = {s: WING[s] + wing_dir(s) * WING_SPAN for s in "LR"}


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

# ---------------------------------------------------------------- normaliza: comprimento LENGTH, centro da caixa na origem
ys = [v.co.y for v in me.vertices]
me.transform(Matrix.Scale(LENGTH / (max(ys) - min(ys)), 4))
P = [v.co for v in me.vertices]
c = Vector([(min(p[i] for p in P) + max(p[i] for p in P)) / 2 for i in range(3)])
me.transform(Matrix.Translation(-c))

bpy.context.view_layer.objects.active = ob
ob.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=1e-6)
bpy.ops.object.mode_set(mode='OBJECT')
# ---------------------------------------------------------------- patas por fatia: grupo pequeno de vértices ligados
# Em fatias de 4 cm abaixo do tórax (z < -0,08), os vértices da fatia ligados por arestas formam grupos; grupo com
# menos de 0,12 de largura é pata (o abdômen e o saco verde passam de 0,3). Feito na malha cheia (arestas de ~1 cm):
# na reduzida (~4 cm) a fatia do abdômen quebrava em pedaços pequenos e virava "pata". Depois da redução, cada
# vértice herda a marca do vértice cheio mais perto.
bm = bmesh.new()
bm.from_mesh(me)
bm.verts.ensure_lookup_table()
leg_v = set()
z = -0.66
while z < -0.06:
    # y > -0,45: o ferrão também é fino e desce abaixo de z -0,08, mas fica à frente de todas as patas
    inside = {v.index for v in bm.verts if z <= v.co.z < z + 0.04 and v.co.y > -0.45}
    seen = set()
    for i in inside:
        if i in seen:
            continue
        comp, stack = [], [i]
        while stack:
            u = stack.pop()
            if u in seen:
                continue
            seen.add(u)
            comp.append(u)
            stack.extend(e.other_vert(bm.verts[u]).index for e in bm.verts[u].link_edges
                         if e.other_vert(bm.verts[u]).index in inside)
        xs = [bm.verts[k].co.x for k in comp]
        yy = [bm.verts[k].co.y for k in comp]
        if max(max(xs) - min(xs), max(yy) - min(yy)) < 0.12:
            leg_v.update(comp)
    z += 0.04
bm.free()
from mathutils.kdtree import KDTree
kd = KDTree(len(me.vertices))
for v in me.vertices:
    kd.insert(v.co, 1 if v.index in leg_v else 0)
kd.balance()
print("PATAS %d vértices (malha cheia)" % len(leg_v))

antes = len(me.polygons)
mod = ob.modifiers.new("dec", "DECIMATE")
mod.ratio = min(1.0, FACES / len(me.polygons))
mod.delimit = {'UV'}
bpy.ops.object.modifier_apply(modifier="dec")
print("MALHA %d -> %d faces" % (antes, len(me.polygons)))
leg_v = {v.index for v in me.vertices if kd.find(v.co)[1] == 1}
print("PATAS %d vértices (malha do jogo)" % len(leg_v))


# ---------------------------------------------------------------- asas da IA fora: vêm em V, com borda rasgada e dobra
# na raiz (o usuário reprovou na rodada 1). Corta a asa (fora do tórax em x, acima do ombro), fecha o buraco no
# tórax e põe asas novas, feitas aqui (mais abaixo), abertas na horizontal como no conceito.
def wing_of(co):
    ax = abs(co.x)
    w = smooth(0.18, 0.22, ax) * smooth(0.14, 0.18, co.z)
    return 1.0 if ax > 0.3 and co.z > 0.15 else w


bm = bmesh.new()
bm.from_mesh(me)
# a raiz sobe acima do tórax (em y 0,05..0,35 a asa nasce em z 0,25..0,32 com o alto do tórax em 0,28 - 3,2 x²):
# sem cortar essa parte sobravam dois tocos em pé nos ombros


def wing_root(co):
    ax = abs(co.x)
    return ax > 0.11 and -0.02 < co.y < 0.4 and co.z > 0.285 - 3.2 * ax * ax + 0.02


cut = [v for v in bm.verts if (wing_of(v.co) >= 0.3 or wing_root(v.co)) and v.index not in leg_v]
bmesh.ops.delete(bm, geom=cut, context='VERTS')
loose = [v for v in bm.verts if not v.link_faces]
bmesh.ops.delete(bm, geom=loose, context='VERTS')
edges = [e for e in bm.edges if e.is_boundary]
filled = bmesh.ops.holes_fill(bm, edges=edges, sides=0)
tri = bmesh.ops.triangulate(bm, faces=filled["faces"])["faces"]
# a tampa nasce sem UV (lia o canto da textura, cinza): cada canto copia o UV do mesmo vértice numa face vizinha
uvl = bm.loops.layers.uv.active
caps = set(tri)
for f in caps:
    for lp in f.loops:
        src = next((o for o in lp.vert.link_loops if o.face not in caps), None)
        if src is not None:
            lp[uvl].uv = src[uvl].uv
bm.to_mesh(me)
bm.free()
print("ASAS DA IA: %d vértices cortados, %d faces de tampa" % (len(cut), len(filled["faces"])))
leg_v = {v.index for v in me.vertices if kd.find(v.co)[1] == 1}

# ---------------------------------------------------------------- textura e material (pintura da IA, _flat)
img = next((i for i in bpy.data.images if i.size[0] > 0), None)
if img:
    img.scale(TEX, TEX)
    img.name = "mosquito_ia_albedo"
me.materials.clear()
paint = bpy.data.materials.new("mqia_paint_flat")     # _flat: a luz já vem pintada, o toon não soma sombra de forma
paint.use_nodes = True
bsdf = next(nd for nd in paint.node_tree.nodes if nd.type == 'BSDF_PRINCIPLED')
if img:
    tx = paint.node_tree.nodes.new("ShaderNodeTexImage")
    tx.image = img
    paint.node_tree.links.new(tx.outputs["Color"], bsdf.inputs["Base Color"])
bsdf.inputs["Roughness"].default_value = 0.85
me.materials.append(paint)
for a in list(me.color_attributes):
    me.color_attributes.remove(a)
for p in me.polygons:
    p.use_smooth = True
ob.name = me.name = "MosquitoIA"


# ---------------------------------------------------------------- pesos por regra (coordenadas antes de subir)
def weights(co, is_leg):
    W = {}
    ax = abs(co.x)
    # as asas da IA foram cortadas: o toco da raiz fica no tórax (Body); a regra só serve para o abdômen não pegar
    # o ombro onde a asa nascia
    wing = 0.0 if is_leg else wing_of(co)
    # cabeça e ferrão: à frente do pescoço; abaixo de z -0,1 só se perto do meio (o ferrão), as patas da frente não
    head = smooth(-0.17, -0.24, co.y) * (1.0 if co.z > -0.10 or ax < 0.06 else 0.0) * (1 - wing)
    if is_leg:
        head = 0.0
    # abdômen: atrás da cintura, abaixo das asas, fora das patas
    tail = smooth(0.12, 0.20, co.y) * (0.0 if is_leg or wing > 0 else 1.0)   # nunca no mesmo vértice da asa
    body = max(0.0, 1.0 - head - tail)
    for k, w in (("Head", head), ("Tail", tail), ("Body", body)):
        if w > 1e-4:
            W[k] = W.get(k, 0) + w
    return W


wts = {v.index: weights(v.co, v.index in leg_v) for v in me.vertices}

# ---------------------------------------------------------------- sobe: o tórax fica na altura de voo (HOVER)
LIFT = Vector((0, 0, HOVER - BODY.z))
me.transform(Matrix.Translation(LIFT))


def up(p):
    return p + LIFT


def empty(name, loc, parent=None):
    e = bpy.data.objects.new(name, None)
    e.location = loc
    scn.collection.objects.link(e)
    if parent:
        e.parent = parent
        e.location = Vector(loc) - parent.matrix_world.translation
        bpy.context.view_layer.update()
    return e


root = empty("Mosquito", (0, 0, 0))
piv = {"Body": empty("Body", up(BODY), root)}
piv["Head"] = empty("Head", up(HEAD), piv["Body"])
piv["Tail"] = empty("Tail", up(TAIL), piv["Body"])
for s in "LR":
    piv["Wing" + s] = empty("Wing" + s, up(WING[s]), piv["Body"])

arm = bpy.data.armatures.new("MosquitoIA_Rig")
rig = bpy.data.objects.new("MosquitoIA_Rig", arm)
scn.collection.objects.link(rig)
rig.parent = root
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='EDIT')
BONES = {"Body": (None, up(BODY), up(BODY + Vector((0, -0.15, 0)))),
         "Head": ("Body", up(HEAD), up(HEAD + Vector((0, -0.2, 0)))),
         "Tail": ("Body", up(TAIL), up(TAIL_TIP))}
for s in "LR":
    BONES["Wing" + s] = ("Body", up(WING[s]), up(WING_TIP[s]))
SK = "_skin"     # osso "<pivô>_skin": o PivotSkin tira o sufixo (com o mesmo nome do pivô o Godot renomeia o osso)
for name, (par, h, t) in BONES.items():
    b = arm.edit_bones.new(name + SK)
    b.head, b.tail = h, t
for name, (par, h, t) in BONES.items():
    if par:
        arm.edit_bones[name + SK].parent = arm.edit_bones[par + SK]
bpy.ops.object.mode_set(mode='OBJECT')

ob.parent = rig
md = ob.modifiers.new("rig", "ARMATURE")
md.object = rig
groups = {name: ob.vertex_groups.new(name=name + SK) for name in BONES}
for v in me.vertices:
    W = wts[v.index]
    tot = sum(W.values()) or 1.0
    for k, w in W.items():
        groups[k].add([v.index], w / tot, 'REPLACE')

# ---------------------------------------------------------------- asas novas: lâmina fina com veios, raiz dentro do tórax
WT_W, WT_H = 256, 96
wimg = bpy.data.images.new("mosquito_ia_wing", WT_W, WT_H)
VEINS = [[(0.0, 0.5), (0.35, 0.40), (0.75, 0.30), (0.98, 0.42)],      # (u ao longo da asa, v de trás 0 à frente 1)
         [(0.0, 0.5), (0.30, 0.62), (0.62, 0.72), (0.90, 0.66)],
         [(0.05, 0.45), (0.40, 0.22), (0.70, 0.14)],
         [(0.35, 0.40), (0.55, 0.12)], [(0.62, 0.72), (0.78, 0.86)]]
BASE, VEIN, RIM = (0.80, 0.84, 0.74), (0.22, 0.24, 0.20), (0.40, 0.44, 0.36)


def seg_d(px, py, a, b):
    ax_, ay_ = a[0] * WT_W, a[1] * WT_H
    bx_, by_ = b[0] * WT_W, b[1] * WT_H
    dx, dy = bx_ - ax_, by_ - ay_
    tt = max(0.0, min(1.0, ((px - ax_) * dx + (py - ay_) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - ax_ - dx * tt, py - ay_ - dy * tt)


px = []
for yy in range(WT_H):
    for xx in range(WT_W):
        d = min(seg_d(xx, yy, a_, b_) for vein in VEINS for a_, b_ in zip(vein, vein[1:]))
        c = VEIN if d < 1.6 else BASE
        if yy < 3 or yy > WT_H - 4:     # borda escura (a lâmina mapeia v de 0 a 1 de uma borda à outra)
            c = RIM
        if xx < WT_W * 0.1:             # a raiz (talo que sai do tórax) na cor do corpo, não do véu claro
            c = (0.30, 0.27, 0.14)
        px.extend((*c, 1.0))
wimg.pixels = px
wmat = bpy.data.materials.new("mqia_wing_flat")
wmat.use_nodes = True
wb = next(nd for nd in wmat.node_tree.nodes if nd.type == 'BSDF_PRINCIPLED')
wtx = wmat.node_tree.nodes.new("ShaderNodeTexImage")
wtx.image = wimg
wmat.node_tree.links.new(wtx.outputs["Color"], wb.inputs["Base Color"])
wb.inputs["Roughness"].default_value = 0.8


def build_wing(s):
    """Folha de WING_SPAN de comprimento (do tamanho do conceito: ~0,6 do corpo): borda da frente 0,09 e de trás 0,17 no meio (sqrt(sin) arredonda as pontas),
    espessura 1 cm. Começa 4 cm dentro do tórax para não ficar solta."""
    sx = 1 if s == "L" else -1
    d = wing_dir(s)
    back = Vector((0, 1, 0)) - d * d.y
    back.normalize()
    upv = d.cross(back) * sx
    if upv.z < 0:
        upv = -upv
    root = WING[s] - d * 0.04
    NU, NV, TH = 26, 8, 0.005
    b = bmesh.new()
    uvl = b.loops.layers.uv.new("UVMap")
    top, bot = [], []
    for i in range(NU + 1):
        u = 0.02 + 0.96 * i / NU
        prof = math.sqrt(math.sin(math.pi * u))
        f, r = 0.09 * prof, 0.17 * prof
        rt, rb = [], []
        for j in range(NV + 1):
            v = j / NV                             # 0 = borda de trás, 1 = borda da frente
            off = -r + (f + r) * v                 # ao longo de "back" (negativo = para a frente)
            base_p = root + d * (u * (WING_SPAN + 0.04)) - back * off
            thick = TH * (1 - abs(2 * v - 1) ** 2) * prof + 0.0015
            rt.append((b.verts.new(base_p + upv * thick), (u, v)))
            rb.append((b.verts.new(base_p - upv * thick), (u, v)))
        top.append(rt)
        bot.append(rb)

    def face(vs):
        fc = b.faces.new([x[0] for x in vs])
        for lp, x in zip(fc.loops, vs):
            lp[uvl].uv = x[1]

    for i in range(NU):
        for j in range(NV):
            face([top[i][j], top[i + 1][j], top[i + 1][j + 1], top[i][j + 1]])
            face([bot[i][j + 1], bot[i + 1][j + 1], bot[i + 1][j], bot[i][j]])
        face([top[i][0], bot[i][0], bot[i + 1][0], top[i + 1][0]])
        face([top[i + 1][NV], bot[i + 1][NV], bot[i][NV], top[i][NV]])
    for i, rows in ((0, None), (NU, None)):
        ring_t, ring_b = top[i], bot[i]
        for j in range(NV):
            if i == 0:
                face([ring_t[j + 1], bot[i][j + 1], ring_b[j], ring_t[j]])
            else:
                face([ring_t[j], ring_b[j], ring_b[j + 1], ring_t[j + 1]])
    bmesh.ops.recalc_face_normals(b, faces=b.faces)
    wm = bpy.data.meshes.new("MosquitoIA_Wing" + s)
    b.to_mesh(wm)
    b.free()
    for p in wm.polygons:
        p.use_smooth = True
    wm.materials.append(wmat)
    wm.transform(Matrix.Translation(LIFT))
    wo = bpy.data.objects.new("MosquitoIA_Wing" + s, wm)
    scn.collection.objects.link(wo)
    wo.parent = rig
    m2 = wo.modifiers.new("rig", "ARMATURE")
    m2.object = rig
    g = wo.vertex_groups.new(name="Wing" + s + SK)
    g.add([v.index for v in wm.vertices], 1.0, 'REPLACE')
    return wo


wings = [build_wing(s) for s in "LR"]

# ---------------------------------------------------------------- conferência: combinação de grupos por vértice
gi = {g.index: g.name[:-len(SK)] for g in ob.vertex_groups}
combos = {}
for v in me.vertices:
    names = tuple(sorted(gi[g.group] for g in v.groups if g.weight > 0.05))
    combos[names] = combos.get(names, 0) + 1
ERRADO = 0
for names, n in sorted(combos.items(), key=lambda kv: -kv[1]):
    s = set(names) - {"Body"}
    bad = len(s) > 1     # dois membros no mesmo vértice (asa+cabeça, asa+abdômen, as duas asas...)
    if bad:
        ERRADO += n
    print("GRUPOS %-30s %5d%s" % ("+".join(names), n, "  <- ERRO" if bad else ""))
print("GRUPOS errados: %d vértices" % ERRADO)
legs_wrong = sum(1 for i in leg_v if any(gi[g.group] != "Body" and g.weight > 0.01 for g in me.vertices[i].groups))
print("PATAS fora do Body: %d" % legs_wrong)

bm = bmesh.new()
bm.from_mesh(me)
seen, parts = set(), 0
for v in bm.verts:
    if v.index in seen:
        continue
    parts += 1
    stack = [v]
    while stack:
        u = stack.pop()
        if u.index in seen:
            continue
        seen.add(u.index)
        stack.extend(e.other_vert(u) for e in u.link_edges)
bm.free()
print("PEDACOS malha=%d (esperado 1)" % parts)

# ---------------------------------------------------------------- prévia: pesos e pose de teste
if PREVIA:
    os.makedirs(PREVIA, exist_ok=True)
    scn.render.engine = "BLENDER_WORKBENCH"
    sh = scn.display.shading
    sh.light, sh.color_type = "FLAT", "TEXTURE"
    scn.view_settings.view_transform = "Standard"
    scn.world = bpy.data.worlds.new("w")
    scn.world.color = (0.45, 0.47, 0.52)
    scn.render.resolution_x = scn.render.resolution_y = 700
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scn.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    scn.camera = cam
    C = up(BODY)
    VIEWS = (("lado", C + Vector((-4, 0, 0)), (math.pi / 2, 0, -math.pi / 2), 1.7),
             ("frente", C + Vector((0, -4, 0)), (math.pi / 2, 0, 0), 1.7),
             ("cima", C + Vector((0, 0, 4)), (0, 0, 0), 1.7),
             ("tres_quartos", C + Vector((-3, -3, 2.0)), None, 1.9))

    def shoot(prefix):
        for nm, loc, rotc, sc in VIEWS:
            cam.location = loc
            cam.rotation_euler = rotc if rotc else (C - loc).to_track_quat("-Z", "Y").to_euler()
            cam.data.ortho_scale = sc
            scn.render.filepath = os.path.join(PREVIA, "%s_%s.png" % (prefix, nm))
            bpy.ops.render.render(write_still=True)

    PAL = {"Body": (0.55, 0.55, 0.55), "Head": (0.9, 0.8, 0.1), "Tail": (0.2, 0.5, 1.0),
           "WingL": (0.9, 0.1, 0.1), "WingR": (0.1, 0.8, 0.1)}
    ca = me.color_attributes.new("peso", 'FLOAT_COLOR', 'POINT')
    for v in me.vertices:
        g = max(v.groups, key=lambda g: g.weight, default=None)
        ca.data[v.index].color = (*(PAL.get(gi[g.group], (0, 0, 0)) if g else (0, 0, 0)), 1)
    sh.color_type = "VERTEX"
    shoot("pesos")
    me.color_attributes.remove(me.color_attributes["peso"])
    sh.color_type = "TEXTURE"
    pb = rig.pose.bones
    # giro no eixo do mundo, como o jogo: asas em y (bate), cabeça e abdômen em x
    POSES = {"repouso": {}, "teste": {"WingL": ((0, 1, 0), 0.6), "WingR": ((0, 1, 0), 0.6),
                                      "Head": ((1, 0, 0), 0.3), "Tail": ((1, 0, 0), -0.3)}}
    for pose, rot in POSES.items():
        for b in pb:
            b.rotation_mode = 'XYZ'
            b.rotation_euler = (0, 0, 0)
        for k, (axw, a) in rot.items():
            b = pb[k + SK]
            mw = (rig.matrix_world @ b.bone.matrix_local).to_3x3()
            ax = mw.inverted() @ Vector(axw)
            b.rotation_mode = 'AXIS_ANGLE'
            b.rotation_axis_angle = (a if k != "WingR" else -a, *ax)
        bpy.context.view_layer.update()
        shoot(pose)
    for b in pb:
        b.rotation_mode = 'XYZ'
        b.rotation_euler = (0, 0, 0)

# ---------------------------------------------------------------- exporta (pivôs + esqueleto + malha com pele)
for o in scn.objects:
    o.select_set(o.type != 'CAMERA')
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_yup=True,
                          export_animations=False, export_cameras=False, export_lights=False,
                          export_image_format='JPEG', export_jpeg_quality=88, export_skins=True,
                          export_def_bones=False)
print("EXPORT", OUT)
