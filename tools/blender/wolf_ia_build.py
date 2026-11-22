"""Lobo da Geada gerado por IA local (piloto de monstro por IA, docs/EQUIPAMENTO_POR_IA.md, seção Monstros).

  blender -b --factory-startup --python tools/blender/wolf_ia_build.py -- [pintado.glb] [pasta_previa]

Entrada: a malha pintada pela IA (D:/ia3d/saida/lobo/pintura/pintado.glb, vistas da folha do usuário). Saída:
assets/models/wolf_ia.glb com os MESMOS pivôs do lobo feito por código (frost_monsters.build_wolf: Body, Head, Jaw,
Tail, Tail2 e as patas Leg > Knee > Paw > Foot), mais um esqueleto com um osso por pivô e a malha com pele. No jogo,
o PivotSkin faz cada osso seguir o seu pivô; o código de animação do lobo (enemy.gd, _animate_wolf) não muda.

Por que pele e não peças rígidas: o pelo do ombro e da coxa nasce de dentro do tronco; cortado em partes, a emenda
apareceria em toda dobra. Os pesos são por regra (região do corpo + distância ao longo da pata), não automáticos:
a malha da IA tem o rabo perto da coxa e a juba em volta do pescoço, e o calor do Blender espalha peso entre eles.

Boca: a malha da IA vem de boca fechada (uma casca só). O corte segue a linha da boca pintada e abre uma fenda do
canto até a frente; a parte de baixo vai 100% na mandíbula (Jaw) e um saco escuro por dentro tapa o vão quando abre.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SRC = ARGS[0] if ARGS else os.path.join(os.environ.get("IA3D", "D:/ia3d"), "saida/lobo/pintura/pintado.glb")
PREVIA = ARGS[1] if len(ARGS) > 1 else ""
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets/models/wolf_ia.glb")

HEIGHT = 1.45      # da sola à ponta da orelha, como o lobo de código (caixa 0..1,452)
FACES = 14000      # malha do jogo (a IA entrega 40 mil)
TEX = 1024

# ---------------------------------------------------------------- pivôs, medidos na malha normalizada (fatias em z)
# frente = -Y, esquerda = +X. x de cada pata = centro da fatia z 0,3 (a malha da IA não é simétrica: ~2 cm).
LEG_X = {"FL": 0.156, "FR": -0.137, "BL": 0.189, "BR": -0.206}
# (topo, junta 1, junta 2, apoio) em (y, z): frente = ombro, cotovelo, punho, pata; trás = quadril, joelho, jarrete, pata
LEG_YZ = {True: ((-0.31, 0.80), (-0.28, 0.50), (-0.305, 0.13), (-0.37, 0.03)),
          False: ((0.43, 0.80), (0.30, 0.50), (0.455, 0.32), (0.40, 0.03))}
BODY = Vector((0, 0.0, 0.80))
HEAD = Vector((0, -0.52, 1.04))    # base do pescoço (a cabeça gira e estica daqui)
JAW = Vector((0, -0.75, 0.985))    # dobradiça atrás do canto da boca, dentro da cabeça
# linha da boca no perfil (pintura): canto (y -0,791, z 0,991) até a frente do lábio (y -0,90, z 0,961)
MOUTH_Y0, MOUTH_Y1 = -0.79, -0.935
MOUTH_SLOPE = 0.275


def mouth_z(y):
    return 0.991 + (y + 0.791) * MOUTH_SLOPE


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

# ---------------------------------------------------------------- normaliza: altura HEIGHT, sola em z 0, centro das patas em x 0
zs = [v.co.z for v in me.vertices]
S, z0 = HEIGHT / (max(zs) - min(zs)), min(zs)
me.transform(Matrix.Scale(S, 4) @ Matrix.Translation((0, 0, -z0)))
legs_x = [v.co.x for v in me.vertices if 0.15 < v.co.z < 0.35]
me.transform(Matrix.Translation((-sum(legs_x) / len(legs_x), 0, 0)))

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

# ---------------------------------------------------------------- boca: corta na linha pintada e separa os lábios
bm = bmesh.new()
bm.from_mesh(me)
n = Vector((0, -MOUTH_SLOPE, 1)).normalized()
p0 = Vector((0, -0.791, 0.991))


def in_mouth(co, pad=0.0):
    return MOUTH_Y1 - pad < co.y < MOUTH_Y0 + pad and abs(co.z - mouth_z(co.y)) < 0.05 + pad and abs(co.x) < 0.09


faces = [f for f in bm.faces if any(in_mouth(v.co, 0.01) for v in f.verts)]
geom = list({e for f in faces for e in f.edges}) + faces + list({v for f in faces for v in f.verts})
res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=p0, plane_no=n, dist=1e-5)
cut = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)
       and all(MOUTH_Y1 < v.co.y < MOUTH_Y0 and abs(v.co.x) < 0.09 for v in e.verts)]
bmesh.ops.split_edges(bm, edges=cut)
print("BOCA %d arestas cortadas" % len(cut))
bm.to_mesh(me)
bm.free()

# lado de cada vértice da fenda: pelo centro das faces dele (os dois lábios têm vértices no mesmo lugar)
below = {}
for v in me.vertices:
    below[v.index] = v.co.z < mouth_z(v.co.y) - 1e-4
for p in me.polygons:
    pass
vf = {}
for p in me.polygons:
    c = p.center
    for i in p.vertices:
        vf.setdefault(i, []).append(c)
for v in me.vertices:
    if abs((v.co - p0).dot(n)) < 2e-4 and MOUTH_Y1 < v.co.y < MOUTH_Y0:
        cs = vf.get(v.index, [])
        if cs:
            m = sum(cs, Vector()) / len(cs)
            below[v.index] = (m - p0).dot(n) < 0

# ---------------------------------------------------------------- textura e material (pintura da IA, _flat)
img = next((i for i in bpy.data.images if i.size[0] > 0), None)
if img:
    img.scale(TEX, TEX)
    img.name = "wolf_ia_albedo"
me.materials.clear()
paint = bpy.data.materials.new("wia_paint_flat")     # _flat: a luz já vem pintada, o toon não soma sombra de forma
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
ob.name = me.name = "WolfIA"

# saco escuro dentro do focinho: metade de cima na cabeça, de baixo na mandíbula; com a boca aberta tapa o vão
half = {}
for v in me.vertices:
    if MOUTH_Y1 < v.co.y < MOUTH_Y0 + 0.02 and abs(v.co.z - mouth_z(v.co.y)) < 0.012:
        k = round(v.co.y, 2)
        half[k] = max(half.get(k, 0.0), abs(v.co.x))
sk = bmesh.new()
RING = 12
# a mandíbula da IA é fina (1,5 cm na frente): o saco sobe para dentro do focinho e quase não desce; acaba antes da
# frente do lábio (y -0,89), senão fura o queixo
ys = [MOUTH_Y0 + 0.015 - i * 0.015 for i in range(8)]
rows = []
for y in ys:
    w = max(0.01, 0.6 * half.get(round(y, 2), 0.025)) * (0.6 if y > MOUTH_Y0 else 1.0)
    up, dn = 0.02, 0.005
    rows.append([sk.verts.new((w * math.cos(a), y, mouth_z(min(y, MOUTH_Y0)) +
                               (up if math.sin(a) > 0 else dn) * math.sin(a)))
                 for a in [2 * math.pi * j / RING for j in range(RING)]])
for r0, r1 in zip(rows, rows[1:]):
    for j in range(RING):
        sk.faces.new((r0[j], r0[(j + 1) % RING], r1[(j + 1) % RING], r1[j]))
sk.faces.new(rows[0][::-1])
sk.faces.new(rows[-1])
bmesh.ops.recalc_face_normals(sk, faces=sk.faces)
sme = bpy.data.meshes.new("WolfIA_Mouth")
sk.to_mesh(sme)
sk.free()
mouth = bpy.data.objects.new("WolfIA_Mouth", sme)
scn.collection.objects.link(mouth)
dark = bpy.data.materials.new("wia_mouth_flat")
dark.use_nodes = True
db = next(nd for nd in dark.node_tree.nodes if nd.type == 'BSDF_PRINCIPLED')
db.inputs["Base Color"].default_value = (0.09, 0.025, 0.04, 1)
sme.materials.append(dark)

# ---------------------------------------------------------------- pivôs (empties), como o lobo de código
def empty(name, loc, parent=None):
    e = bpy.data.objects.new(name, None)
    e.location = loc
    scn.collection.objects.link(e)
    if parent:
        e.parent = parent
        e.location = Vector(loc) - parent.matrix_world.translation
        bpy.context.view_layer.update()
    return e


root = empty("Wolf", (0, 0, 0))
piv = {"Body": empty("Body", BODY, root)}
piv["Head"] = empty("Head", HEAD, piv["Body"])
piv["Jaw"] = empty("Jaw", JAW, piv["Head"])

# cauda: centro das fatias da malha atrás da garupa; Tail2 no meio do comprimento
TAIL_Y0 = 0.62
tail_pts = []
for k in range(14):
    y = TAIL_Y0 + k * 0.03
    P = [v.co for v in me.vertices if abs(v.co.y - y) < 0.012 and v.co.z > 0.42 and
         (y > 0.7 or v.co.z > 0.55)]
    if len(P) > 4:
        tail_pts.append(sum(P, Vector()) / len(P))
TAIL = tail_pts[0].copy()
TAIL2 = tail_pts[len(tail_pts) // 2].copy()
print("CAUDA", [tuple(round(c, 3) for c in p) for p in tail_pts])
piv["Tail"] = empty("Tail", TAIL, piv["Body"])
piv["Tail2"] = empty("Tail2", TAIL2, piv["Tail"])

chains = {}
for sd, x in LEG_X.items():
    front = sd[0] == "F"
    pts = [Vector((x, y, z)) for y, z in LEG_YZ[front]]
    leg = piv["Leg" + sd] = empty("Leg" + sd, pts[0], root)
    knee = piv["Knee" + sd] = empty("Knee" + sd, pts[1], leg)
    paw = piv["Paw" + sd] = empty("Paw" + sd, pts[2], knee)
    empty("Foot" + sd, pts[3], paw)
    chains[sd] = pts

# ---------------------------------------------------------------- esqueleto: um osso por pivô, a cabeça do osso no pivô
arm = bpy.data.armatures.new("WolfIA_Rig")
rig = bpy.data.objects.new("WolfIA_Rig", arm)
scn.collection.objects.link(rig)
rig.parent = root
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='EDIT')
BONES = {"Body": (None, BODY, BODY + Vector((0, -0.25, 0))), "Head": ("Body", HEAD, HEAD + Vector((0, -0.25, 0))),
         "Jaw": ("Head", JAW, JAW + Vector((0, -0.15, -0.02))), "Tail": ("Body", TAIL, TAIL2),
         "Tail2": ("Tail", TAIL2, tail_pts[-1])}
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
    """Pesos de um ponto da pata entre Leg/Knee/Paw: segmento mais perto, com mistura de 3 cm em cada junta."""
    d = [seg_dist(co, pts[i], pts[i + 1]) for i in range(3)]
    names = ["Leg" + sd, "Knee" + sd, "Paw" + sd]
    W = {}
    i = min(range(3), key=lambda k: d[k])
    W[names[i]] = 1.0
    for j in (i - 1, i + 1):        # perto da junta com o vizinho: divide
        if 0 <= j < 3:
            joint = pts[max(i, j)]
            dj = (co - joint).length
            if dj < 0.05:
                s = 0.5 * (1 - dj / 0.05)
                W[names[j]] = s
                W[names[i]] -= s
    return W


def weights(co, low_jaw):
    W = {}
    # pata: a mais perto no plano (x pelo lado, y pela metade); abaixo da barriga 100%, some até o topo do pivô
    sd = ("F" if co.y < 0.06 else "B") + ("L" if co.x > 0 else "R")
    pts = chains[sd]
    hor = math.hypot(co.x - pts[0].x, co.y - (pts[0].y + pts[1].y) / 2)
    belly = 0.56 if sd[0] == "F" else 0.58
    reach = 0.1 if sd[0] == "F" else 0.16           # coxa mais larga que o ombro
    leg = (1 - smooth(belly, 0.78, co.z)) * (1 - smooth(reach, reach + 0.06, hor))
    if sd[0] == "B":
        # coxa de trás inteira com a perna (rodada 2: com a coxa no Body ela ficava parada e só a canela girava,
        # esticando de um bloco imóvel): perto do eixo quadril-joelho no perfil, até 6 cm abaixo do pivô do quadril;
        # só a face de dentro, junto da barriga, fica no Body
        yz = Vector((0, co.y, co.z))
        thigh = seg_dist(yz, Vector((0, pts[0].y, pts[0].z)), Vector((0, pts[1].y, pts[1].z)))
        inner = abs(pts[0].x) - abs(co.x)
        leg = max(leg, (1 - smooth(0.68, 0.80, co.z)) * (1 - smooth(0.17, 0.25, thigh)) * (1 - smooth(0.06, 0.14, inner)))
    if co.z < belly - 0.02 and hor < reach + 0.1:
        leg = 1.0
    rest = 1.0 - leg
    if leg > 0:
        for k, w in leg_weights(co, sd, pts).items():
            W[k] = W.get(k, 0) + w * leg
    if rest <= 0:
        return W
    # cabeça: na frente do pescoço e acima do peito; mandíbula: lábio de baixo e o queixo
    head = smooth(-0.45, -0.58, co.y) * smooth(0.84, 0.95, co.z)
    jaw = 0.0
    if low_jaw:
        jaw = 1.0
    elif co.y < -0.70 and co.z < mouth_z(min(co.y, MOUTH_Y0)) and co.z > 0.9:
        jaw = smooth(-0.70, -0.79, co.y)
    jaw *= head
    tail = smooth(TAIL.y - 0.04, TAIL.y + 0.05, co.y) * smooth(0.42, 0.5, co.z)
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
            W = weights(v.co, below[v.index] and MOUTH_Y1 < v.co.y < MOUTH_Y0 and abs(v.co.x) < 0.09
                        and v.co.z > mouth_z(v.co.y) - 0.06)
        tot = sum(W.values()) or 1.0
        for k, w in W.items():
            groups[k].add([v.index], w / tot, 'REPLACE')

# partes soltas: a malha da IA é uma casca só; o saco da boca fica por dentro (não aparece de boca fechada)
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

# ---------------------------------------------------------------- prévia: pose de teste (passo, cabeça baixa, boca aberta)
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
    pb = rig.pose.bones
    POSES = {"repouso": {}, "teste": {"LegFL": -0.5, "KneeFL": 0.9, "PawFL": -0.6, "LegBR": 0.5, "KneeBR": -0.6,
                                      "PawBR": 0.6, "Head": 0.35, "Jaw": 0.45, "Tail": 0.4, "Tail2": 0.4}}
    for pose, rot in POSES.items():
        for b in pb:
            b.rotation_mode = 'XYZ'
            b.rotation_euler = (0, 0, 0)
        for k, a in rot.items():     # giro em x do mundo, como o jogo (no espaço do osso, depende do osso)
            b = pb[k + SK]
            mw = (rig.matrix_world @ b.bone.matrix_local).to_3x3()
            ax = mw.inverted() @ Vector((1, 0, 0))
            b.rotation_mode = 'AXIS_ANGLE'
            b.rotation_axis_angle = (a, *ax)
        bpy.context.view_layer.update()
        for nm, loc, rotc, sc in (("lado", (-4, 0, 0.7), (math.pi / 2, 0, -math.pi / 2), 2.3),
                                  ("tres_quartos", (-3, -3, 2.4), None, 2.4),
                                  ("boca", (-3, -0.8, 1.0), (math.pi / 2, 0, -math.pi / 2), 0.5)):
            cam.location = loc
            if rotc:
                cam.rotation_euler = rotc
            else:
                cam.rotation_euler = (Vector((0, 0, 0.7)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
            cam.data.ortho_scale = sc
            scn.render.filepath = os.path.join(PREVIA, "%s_%s.png" % (pose, nm))
            bpy.ops.render.render(write_still=True)
    for b in pb:
        b.rotation_mode = 'XYZ'
        b.rotation_euler = (0, 0, 0)

# ---------------------------------------------------------------- exporta (pivôs + esqueleto + malha com pele)
for o in scn.objects:
    o.select_set(True)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_yup=True,
                          export_animations=False, export_cameras=False, export_lights=False,
                          export_image_format='JPEG', export_jpeg_quality=88, export_skins=True,
                          export_def_bones=False)
print("EXPORT", OUT)
