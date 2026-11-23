"""Tartaruga-Musgo gerada por IA local (monstro do Pântano, docs/EQUIPAMENTO_POR_IA.md, seção Monstros).

  blender -b --factory-startup --python tools/blender/turtle_ia_build.py -- [pintado.glb] [pasta_previa]

Entrada: a malha pintada pela IA (D:/ia3d/saida/tartaruga/pintura/pintado.glb, folha de três vistas do usuário).
Saída: assets/models/turtle_ia.glb com os pivôs do lobo (Body, Head, Jaw, Tail, Tail2 e as patas Leg > Knee > Paw >
Foot), um esqueleto com um osso `<pivô>_skin` por pivô e a malha com pele. No jogo o PivotSkin faz cada osso seguir
o seu pivô e a animação é a do lobo (enemy.gd, _animate_wolf), com passada e bote próprios da tartaruga.

Pesos por regra, cada uma com limite no eixo do membro:
- o casco, o musgo e os cogumelos ficam 100% no Body (o casco não entorta);
- a pata inteira vai no osso dela abaixo da borda do casco (z 0,32 a 0,38), perto da coluna da pata em y e fora da
  barriga em x;
- o pescoço vai na cabeça só dentro do tubo dele (|x| < 0,15) e abaixo da borda da frente do casco (z 0,605);
- a cauda só atrás da garupa, abaixo da borda de trás do casco e perto do meio em x.
Bico: a IA entrega o bico fechado numa casca só; o corte segue a linha do bico (do canto até a frente da mandíbula,
antes do gancho de cima, que fica na cabeça) e a parte de baixo vai 100% na mandíbula, com um saco escuro por dentro.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SRC = ARGS[0] if ARGS else os.path.join(os.environ.get("IA3D", "D:/ia3d"), "saida/tartaruga/pintura/pintado.glb")
PREVIA = ARGS[1] if len(ARGS) > 1 else ""
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets/models/turtle_ia.glb")

HEIGHT = 1.0       # da sola ao alto do cogumelo (o jogo ainda multiplica pela escala do tipo)
FACES = 10000      # malha do jogo (a IA entrega 40 mil); 17 tartarugas no Pântano
TEX = 1024

# ---------------------------------------------------------------- pivôs, medidos na malha normalizada (fatias em z)
# frente = -Y, esquerda = +X. Pata: (ombro/quadril, cotovelo/joelho, punho/jarrete, apoio) em (x, y, z); o x de cada
# junta é o centro da fatia (a malha da IA não é simétrica). O topo fica dentro do corpo, sob a borda do casco.
LEGS = {
    "FL": ((0.28, -0.27, 0.34), (0.315, -0.262, 0.19), (0.345, -0.285, 0.08), (0.365, -0.30, 0.02)),
    "FR": ((-0.28, -0.27, 0.34), (-0.32, -0.262, 0.19), (-0.35, -0.285, 0.08), (-0.373, -0.30, 0.02)),
    "BL": ((0.28, 0.215, 0.34), (0.305, 0.205, 0.20), (0.325, 0.23, 0.08), (0.34, 0.21, 0.02)),
    "BR": ((-0.28, 0.215, 0.34), (-0.305, 0.205, 0.20), (-0.33, 0.23, 0.08), (-0.35, 0.21, 0.02)),
}
BODY = Vector((0, 0.0, 0.40))
HEAD = Vector((0, -0.36, 0.45))    # base do pescoço, sob a borda da frente do casco (a cabeça gira e estica daqui)
JAW = Vector((0, -0.565, 0.43))    # dobradiça atrás do canto do bico, dentro da cabeça
TAIL = Vector((0, 0.38, 0.29))
TAIL2 = Vector((0.03, 0.52, 0.21))
TAIL_TIP = Vector((0.13, 0.68, 0.14))
# linha do bico no perfil: canto (y -0,585, z 0,425) até a frente da mandíbula (y -0,638); o gancho de cima desce
# mais à frente (y < -0,64, até z 0,39) e fica na cabeça
MOUTH_Y0, MOUTH_Y1 = -0.585, -0.638
MOUTH_SLOPE = 0.33
MOUTH_X = 0.10
SHELL_FRONT_Z = 0.605   # abaixo daqui, na frente, é pescoço (o casco sobre o pescoço começa em z 0,61)
NECK_X = 0.135          # meia largura do pescoço (0,13 medido); o casco ao lado começa em |x| 0,15
LEG_TOP = (0.32, 0.38)  # a pata some para o Body entre estas alturas (borda do casco: z 0,34..0,43)


def mouth_z(y):
    return 0.425 + (y - MOUTH_Y0) * MOUTH_SLOPE


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

# ---------------------------------------------------------------- normaliza: altura HEIGHT, sola em z 0
zs = [v.co.z for v in me.vertices]
S, z0 = HEIGHT / (max(zs) - min(zs)), min(zs)
me.transform(Matrix.Scale(S, 4) @ Matrix.Translation((0, 0, -z0)))

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

# ---------------------------------------------------------------- bico: corta na linha e separa as duas metades
bm = bmesh.new()
bm.from_mesh(me)
n = Vector((0, -MOUTH_SLOPE, 1)).normalized()
p0 = Vector((0, MOUTH_Y0, mouth_z(MOUTH_Y0)))


def in_mouth(co, pad=0.0):
    return MOUTH_Y1 - pad < co.y < MOUTH_Y0 + pad and abs(co.z - mouth_z(co.y)) < 0.03 + pad and abs(co.x) < MOUTH_X


faces = [f for f in bm.faces if any(in_mouth(v.co, 0.01) for v in f.verts)]
geom = list({e for f in faces for e in f.edges}) + faces + list({v for f in faces for v in f.verts})
res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=p0, plane_no=n, dist=1e-5)
cut = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)
       and all(MOUTH_Y1 < v.co.y < MOUTH_Y0 and abs(v.co.x) < MOUTH_X for v in e.verts)]
bmesh.ops.split_edges(bm, edges=cut)
print("BOCA %d arestas cortadas" % len(cut))
bm.to_mesh(me)
bm.free()

# lado de cada vértice da fenda: pelo centro das faces dele (as duas metades têm vértices no mesmo lugar)
below = {v.index: v.co.z < mouth_z(v.co.y) - 1e-4 for v in me.vertices}
vf = {}
for p in me.polygons:
    for i in p.vertices:
        vf.setdefault(i, []).append(p.center)
for v in me.vertices:
    if abs((v.co - p0).dot(n)) < 2e-4 and MOUTH_Y1 < v.co.y < MOUTH_Y0:
        cs = vf.get(v.index, [])
        if cs:
            below[v.index] = ((sum(cs, Vector()) / len(cs)) - p0).dot(n) < 0

# ---------------------------------------------------------------- textura e material (pintura da IA, _flat)
img = next((i for i in bpy.data.images if i.size[0] > 0), None)
if img:
    img.scale(TEX, TEX)
    img.name = "turtle_ia_albedo"
me.materials.clear()
paint = bpy.data.materials.new("tuia_paint_flat")     # _flat: a luz já vem pintada, o toon não soma sombra de forma
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
ob.name = me.name = "TurtleIA"

# saco escuro dentro do bico: metade de cima na cabeça, de baixo na mandíbula; com o bico aberto tapa o vão
half = {}
for v in me.vertices:
    if MOUTH_Y1 - 0.01 < v.co.y < MOUTH_Y0 + 0.02 and abs(v.co.z - mouth_z(v.co.y)) < 0.012:
        k = round(v.co.y, 2)
        half[k] = max(half.get(k, 0.0), abs(v.co.x))
print("BICO meia largura", sorted(half.items()))
sk = bmesh.new()
RING = 12
ys = [MOUTH_Y0 + 0.015 - i * 0.008 for i in range(8)]     # acaba antes da frente da mandíbula (-0,638)
rows = []
for y in ys:
    w = max(0.008, 0.6 * half.get(round(y, 2), 0.03)) * (0.6 if y > MOUTH_Y0 else 1.0)
    rows.append([sk.verts.new((w * math.cos(a), y, mouth_z(min(y, MOUTH_Y0)) +
                               (0.02 if math.sin(a) > 0 else 0.008) * math.sin(a)))
                 for a in [2 * math.pi * j / RING for j in range(RING)]])
for r0, r1 in zip(rows, rows[1:]):
    for j in range(RING):
        sk.faces.new((r0[j], r0[(j + 1) % RING], r1[(j + 1) % RING], r1[j]))
sk.faces.new(rows[0][::-1])
sk.faces.new(rows[-1])
bmesh.ops.recalc_face_normals(sk, faces=sk.faces)
sme = bpy.data.meshes.new("TurtleIA_Mouth")
sk.to_mesh(sme)
sk.free()
sme.uv_layers.new(name="UVMap")
mouth = bpy.data.objects.new("TurtleIA_Mouth", sme)
scn.collection.objects.link(mouth)
dark = bpy.data.materials.new("tuia_mouth_flat")
dark.use_nodes = True
db = next(nd for nd in dark.node_tree.nodes if nd.type == 'BSDF_PRINCIPLED')
db.inputs["Base Color"].default_value = (0.10, 0.03, 0.04, 1)
dimg = bpy.data.images.new("turtle_ia_mouth", 4, 4)     # textura lisa: a prévia (cor de textura) mostra o escuro
dimg.pixels = [0.10, 0.03, 0.04, 1.0] * 16
dtx = dark.node_tree.nodes.new("ShaderNodeTexImage")
dtx.image = dimg
dark.node_tree.links.new(dtx.outputs["Color"], db.inputs["Base Color"])
sme.materials.append(dark)


# ---------------------------------------------------------------- pivôs (empties), como o lobo
def empty(name, loc, parent=None):
    e = bpy.data.objects.new(name, None)
    e.location = loc
    scn.collection.objects.link(e)
    if parent:
        e.parent = parent
        e.location = Vector(loc) - parent.matrix_world.translation
        bpy.context.view_layer.update()
    return e


root = empty("Turtle", (0, 0, 0))
piv = {"Body": empty("Body", BODY, root)}
piv["Head"] = empty("Head", HEAD, piv["Body"])
piv["Jaw"] = empty("Jaw", JAW, piv["Head"])
piv["Tail"] = empty("Tail", TAIL, piv["Body"])
piv["Tail2"] = empty("Tail2", TAIL2, piv["Tail"])
chains = {}
for sd, P in LEGS.items():
    pts = [Vector(p) for p in P]
    leg = piv["Leg" + sd] = empty("Leg" + sd, pts[0], root)
    knee = piv["Knee" + sd] = empty("Knee" + sd, pts[1], leg)
    paw = piv["Paw" + sd] = empty("Paw" + sd, pts[2], knee)
    empty("Foot" + sd, pts[3], paw)
    chains[sd] = pts

# ---------------------------------------------------------------- esqueleto: um osso por pivô, a cabeça do osso no pivô
arm = bpy.data.armatures.new("TurtleIA_Rig")
rig = bpy.data.objects.new("TurtleIA_Rig", arm)
scn.collection.objects.link(rig)
rig.parent = root
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='EDIT')
BONES = {"Body": (None, BODY, BODY + Vector((0, -0.2, 0))), "Head": ("Body", HEAD, HEAD + Vector((0, -0.2, 0))),
         "Jaw": ("Head", JAW, JAW + Vector((0, -0.07, -0.02))), "Tail": ("Body", TAIL, TAIL2),
         "Tail2": ("Tail", TAIL2, TAIL_TIP)}
for sd, pts in chains.items():
    BONES["Leg" + sd] = (None, pts[0], pts[1])
    BONES["Knee" + sd] = ("Leg" + sd, pts[1], pts[2])
    BONES["Paw" + sd] = ("Knee" + sd, pts[2], pts[3])
SK = "_skin"     # osso "<pivô>_skin": o PivotSkin tira o sufixo (com o mesmo nome do pivô o Godot renomeia o osso)
for name, (par, h, t) in BONES.items():
    b = arm.edit_bones.new(name + SK)
    b.head, b.tail = h, t
    if (t - h).length < 1e-3:
        b.tail = h + Vector((0, 0, 0.05))
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


def leg_weights(co, sd, pts):
    """Pesos de um ponto da pata entre Leg/Knee/Paw pela altura ao longo do eixo, com mistura em cada junta.
    A pata da tartaruga é grossa (raio ~0,11): medida pela distância ao ponto da junta, como no lobo, a pele ficava
    fora da mistura e a junta era um corte seco que dobrava para dentro no passo."""
    u1 = (co - pts[1]).dot((pts[2] - pts[0]).normalized())    # > 0: abaixo do cotovelo/joelho
    u2 = (co - pts[2]).dot((pts[3] - pts[1]).normalized())    # > 0: abaixo do punho/jarrete
    s1 = smooth(-0.045, 0.045, u1)
    s2 = smooth(-0.03, 0.03, u2)
    return {"Leg" + sd: 1 - s1, "Knee" + sd: s1 * (1 - s2), "Paw" + sd: s1 * s2}


def axis_xy(pts, z):
    """(x, y) do eixo da pata na altura z (interpolado entre as juntas)."""
    for a, b in zip(pts, pts[1:]):
        if b.z <= z <= a.z:
            f = (a.z - z) / (a.z - b.z)
            return a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f
    p = pts[0] if z > pts[0].z else pts[-1]
    return p.x, p.y


def weights(co, low_jaw):
    W = {}
    # pata: a do quadrante; limitada em z (borda do casco), em y (coluna da pata) e em x (fora da barriga)
    sd = ("F" if co.y < -0.03 else "B") + ("L" if co.x > 0 else "R")
    pts = chains[sd]
    ax, ay = axis_xy(pts, co.z)
    r = math.hypot(co.x - ax, co.y - ay)          # distância ao eixo da pata, no plano
    if co.z < 0.14:
        # perto do chão só há pata (a carapaça de baixo começa em z 0,165; a cauda fica a mais de 0,28 do eixo):
        # o pé inteiro, calcanhar e garras, vai na pata (com o limite de 0,12 o calcanhar ficava meio no Body e
        # rasgava no passo)
        leg = 1.0 - smooth(0.20, 0.24, r)
    else:
        # sob o casco: dentro do raio da pata (~0,11) e abaixo da borda do casco
        leg = (1 - smooth(LEG_TOP[0], LEG_TOP[1], co.z)) * (1 - smooth(0.125, 0.165, r))
        if co.z < 0.30 and r < 0.125:
            leg = 1.0
    rest = 1.0 - leg
    if leg > 0:
        for k, w in leg_weights(co, sd, pts).items():
            W[k] = W.get(k, 0) + w * leg
    if rest <= 0:
        return W
    # cabeça: pescoço à frente do casco, dentro do tubo dele e abaixo da borda da frente; além de y -0,51 só há cabeça
    # pescoço: tubo em volta do eixo dele (centro z 0,455..0,47, raio 0,135..0,11, medidos nas fatias). Por baixo da
    # borda da frente o casco desce até z 0,60 em |x| 0,1 (mais alto que o pescoço ali, mas abaixo do limite em z):
    # com um limite só em x e z essa borda ia junto com a cabeça no bote e virava uma ponta marrom
    f = smooth(-0.40, -0.50, co.y)
    rn = math.hypot(co.x, co.z - (0.455 + 0.015 * f))
    # a pele de dentro da borda (rn 0,15..0,18) estica junto, como um capuz: com corte seco no raio do pescoço o
    # vão entre a borda e o pescoço esticado abria um buraco escuro; a borda de fora começa em rn ~0,2
    tube = 1 - smooth(0.13 - 0.015 * f, 0.19 - 0.015 * f, rn)
    head = smooth(-0.35, -0.42, co.y) * tube * (co.z < SHELL_FRONT_Z)
    if co.y < -0.51:
        head = 1.0
    jaw = 0.0
    if low_jaw:
        jaw = 1.0
    elif MOUTH_Y1 < co.y < -0.565 and co.z < mouth_z(min(co.y, MOUTH_Y0)) and abs(co.x) < 0.12:
        jaw = smooth(-0.565, -0.59, co.y)
    jaw *= head
    # cauda: atrás da garupa, abaixo da borda de trás do casco (z 0,42 em y 0,44) e perto do meio
    tail = smooth(0.35, 0.40, co.y) * (1 - smooth(0.38, 0.41, co.z)) * (1 - smooth(0.16, 0.20, abs(co.x)))
    if co.y > 0.47:
        tail = 1.0
    t2 = smooth(TAIL2.y - 0.04, TAIL2.y + 0.04, co.y)
    body = max(0.0, 1.0 - head - tail)
    for k, w in (("Head", head - jaw), ("Jaw", jaw), ("Tail", tail * (1 - t2)), ("Tail2", tail * t2), ("Body", body)):
        if w > 1e-4:
            W[k] = W.get(k, 0) + w * rest
    return W


for o in (ob, mouth):
    o.parent = rig
    md = o.modifiers.new("rig", "ARMATURE")
    md.object = rig
    groups = {name: o.vertex_groups.new(name=name + SK) for name in BONES}
    for v in o.data.vertices:
        if o is mouth:
            W = {"Jaw": 1.0} if v.co.z < mouth_z(min(v.co.y, MOUTH_Y0)) - 1e-4 else {"Head": 1.0}
        else:
            W = weights(v.co, below[v.index] and MOUTH_Y1 < v.co.y < MOUTH_Y0 and abs(v.co.x) < MOUTH_X
                        and v.co.z > mouth_z(v.co.y) - 0.04)
        tot = sum(W.values()) or 1.0
        for k, w in W.items():
            groups[k].add([v.index], w / tot, 'REPLACE')

# ---------------------------------------------------------------- conferência: combinação de grupos por vértice
# (a cor do osso dominante esconde mistura): conta as combinações com peso > 5% e marca as que não deviam existir
gi = {g.index: g.name[:-len(SK)] for g in ob.vertex_groups}
combos = {}
for v in me.vertices:
    names = tuple(sorted(gi[g.group] for g in v.groups if g.weight > 0.05))
    combos[names] = combos.get(names, 0) + 1


def fam(nm):
    return nm[-2:] if nm[:3] in ("Leg", "Kne", "Paw") else nm


ERRADO = 0
for names, c in sorted(combos.items(), key=lambda kv: -kv[1]):
    fams = {fam(nm) for nm in names} - {"Body"}
    bad = len({f for f in fams if f in ("FL", "FR", "BL", "BR")}) > 1 or \
        (fams & {"FL", "FR", "BL", "BR"} and fams & {"Head", "Jaw", "Tail", "Tail2"}) or \
        (fams & {"Head", "Jaw"} and fams & {"Tail", "Tail2"})
    if bad:
        ERRADO += c
    print("GRUPOS %-40s %5d%s" % ("+".join(names), c, "  <- ERRO" if bad else ""))
print("GRUPOS errados: %d vértices" % ERRADO)

# partes soltas: a malha da IA é uma casca só; o saco da boca fica por dentro (não aparece de bico fechado)
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

# ---------------------------------------------------------------- prévia: pesos (cor do osso dominante) e pose de teste
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
    VIEWS = (("lado", (-4, 0, 0.45), (math.pi / 2, 0, -math.pi / 2), 1.6),
             ("frente", (0, -4, 0.45), (math.pi / 2, 0, 0), 1.3),
             ("tres_quartos", (-3, -3, 2.2), None, 1.7),
             ("baixo", (0, 0, -4), (math.pi, 0, 0), 1.6),
             ("boca", (-3, -0.58, 0.45), (math.pi / 2, 0, -math.pi / 2), 0.35))

    def shoot(prefix):
        for nm, loc, rotc, sc in VIEWS:
            cam.location = loc
            cam.rotation_euler = rotc if rotc else \
                (Vector((0, 0, 0.4)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
            cam.data.ortho_scale = sc
            scn.render.filepath = os.path.join(PREVIA, "%s_%s.png" % (prefix, nm))
            bpy.ops.render.render(write_still=True)

    # pesos: cor do osso dominante por vértice
    PAL = {"Body": (0.55, 0.55, 0.55), "Head": (0.9, 0.8, 0.1), "Jaw": (1.0, 0.3, 0.0), "Tail": (0.2, 0.5, 1.0),
           "Tail2": (0.6, 0.2, 1.0), "LegFL": (0.9, 0.1, 0.1), "KneeFL": (0.6, 0.0, 0.0), "PawFL": (1, 0.5, 0.5),
           "LegFR": (0.1, 0.8, 0.1), "KneeFR": (0.0, 0.5, 0.0), "PawFR": (0.5, 1, 0.5),
           "LegBL": (0.1, 0.8, 0.9), "KneeBL": (0.0, 0.5, 0.6), "PawBL": (0.5, 1, 1),
           "LegBR": (0.9, 0.2, 0.8), "KneeBR": (0.6, 0.0, 0.5), "PawBR": (1, 0.6, 0.9)}
    ca = me.color_attributes.new("peso", 'FLOAT_COLOR', 'POINT')
    for v in me.vertices:
        g = max(v.groups, key=lambda g: g.weight, default=None)
        c = PAL.get(gi[g.group], (0, 0, 0)) if g else (0, 0, 0)
        ca.data[v.index].color = (*c, 1)
    sh.color_type = "VERTEX"
    shoot("pesos")
    me.color_attributes.remove(me.color_attributes["peso"])
    sh.color_type = "TEXTURE"
    pb = rig.pose.bones
    POSES = {"repouso": {}, "teste": {"LegFL": -0.45, "KneeFL": 0.7, "PawFL": -0.5, "LegBR": 0.45, "KneeBR": -0.6,
                                      "PawBR": 0.5, "Head": 0.35, "Jaw": 0.5, "Tail": 0.4, "Tail2": 0.4}}
    for pose, rot in POSES.items():
        for b in pb:
            b.rotation_mode = 'XYZ'
            b.rotation_euler = (0, 0, 0)
        for k, a in rot.items():     # giro em x do mundo, como o jogo
            b = pb[k + SK]
            mw = (rig.matrix_world @ b.bone.matrix_local).to_3x3()
            ax = mw.inverted() @ Vector((1, 0, 0))
            b.rotation_mode = 'AXIS_ANGLE'
            b.rotation_axis_angle = (a, *ax)
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
