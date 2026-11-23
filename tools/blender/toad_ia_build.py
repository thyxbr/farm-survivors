"""Sapo-Bufo gerado por IA local (monstro do Pântano, docs/EQUIPAMENTO_POR_IA.md, seção Monstros).

  blender -b --factory-startup --python tools/blender/toad_ia_build.py -- [pintado.glb] [pasta_previa]

Entrada: a malha pintada pela IA (D:/ia3d/saida/sapo/pintura/pintado.glb, folha de três vistas do usuário).
Saída: assets/models/toad_ia.glb com os pivôs do sapo (Body no centro da barriga; ArmL/ArmR > HandL/HandR e
LegL/LegR > FootL/FootR, filhos da raiz), um esqueleto com um osso `<pivô>_skin` por pivô e a malha com pele. No jogo
o PivotSkin faz cada osso seguir o seu pivô e a animação é a do sapo (enemy.gd, _animate_toad): pulinhos e, no
pavio do bomber, o Body incha e treme até estourar.

O Body fica no centro da barriga porque o inchaço é uma escala dele: com o pivô no meio o corpo cresce para todos os
lados (o jogo sobe o pivô junto, para a barriga não afundar no chão). As patas são filhas da raiz e não crescem;
a pele entre o ombro/coxa e o corpo mistura ao longo do eixo da pata, para esticar em vez de rasgar.

Pesos por regra, cada uma com limite no eixo do membro:
- pata da frente: raio em volta do eixo ombro-punho, abaixo do ombro (z 0,20..0,27), do lado dela em x;
- mão e pé: a parte da pata perto do chão (z < 0,045..0,085); tudo abaixo de z 0,085..0,10 na frente da barriga
  (y < -0,06) é mão;
- coxa de trás: o volume fora da parede do corpo (|x| 0,31..0,37), atrás de y 0 e abaixo de z 0,30..0,38;
  o pé de trás inteiro (z < 0,09, |x| > 0,19, y > 0) vai na pata;
- o resto (corpo, cabeça, glândulas, papo) fica 100% no Body e incha junto.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SRC = ARGS[0] if ARGS else os.path.join(os.environ.get("IA3D", "D:/ia3d"), "saida/sapo/pintura/pintado.glb")
PREVIA = ARGS[1] if len(ARGS) > 1 else ""
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets/models/toad_ia.glb")

HEIGHT = 0.8       # da sola ao alto dos olhos (o jogo ainda multiplica pela escala do tipo)
FACES = 8000       # malha do jogo (a IA entrega 40 mil); 4 sapos no Pântano
TEX = 1024

# ---------------------------------------------------------------- pivôs, medidos na malha normalizada (fatias em z)
# frente = -Y, esquerda = +X. Corpo de y -0,5 (focinho) a 0,5, barriga a z 0,06 no meio, alto em z 0,76.
BODY = Vector((0, 0.0, 0.40))      # centro da barriga: o inchaço cresce daqui
# pata da frente: coluna quase vertical que entra no corpo em z ~0,24; anel do punho em z 0,06 (x 0,15..0,33,
# y -0,2..-0,07); a mão espalma até y -0,37 no chão
SHOULDER = Vector((0.27, -0.07, 0.25))
WRIST = Vector((0.235, -0.14, 0.06))
HAND_TIP = Vector((0.25, -0.33, 0.02))
# pata de trás: coxa grossa colada no flanco (|x| 0,36..0,53, y 0,05..0,45, até z 0,36), joelho para a frente e
# para fora (y 0,1, z 0,2), calcanhar atrás (y 0,4, z 0,08) e o pé no chão voltando para a frente até y 0,05
HIP = Vector((0.36, 0.24, 0.28))
HEEL = Vector((0.30, 0.38, 0.06))
TOE = Vector((0.45, 0.12, 0.02))


def smooth(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def mirror(v, s):
    return Vector((v.x * s, v.y, v.z))


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

# ---------------------------------------------------------------- normaliza: altura HEIGHT, sola em z 0, centro em x e y
zs = [v.co.z for v in me.vertices]
me.transform(Matrix.Scale(HEIGHT / (max(zs) - min(zs)), 4) @ Matrix.Translation((0, 0, -min(zs))))
P = [v.co for v in me.vertices]
cx = (min(p.x for p in P) + max(p.x for p in P)) / 2
cy = (min(p.y for p in P) + max(p.y for p in P)) / 2
me.transform(Matrix.Translation((-cx, -cy, 0)))

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

img = next((i for i in bpy.data.images if i.size[0] > 0), None)
if img:
    img.scale(TEX, TEX)
    img.name = "toad_ia_albedo"
me.materials.clear()
paint = bpy.data.materials.new("tdia_paint_flat")     # _flat: a luz já vem pintada, o toon não soma sombra de forma
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
ob.name = me.name = "ToadIA"


# ---------------------------------------------------------------- pivôs (empties)
def empty(name, loc, parent=None):
    e = bpy.data.objects.new(name, None)
    e.location = loc
    scn.collection.objects.link(e)
    if parent:
        e.parent = parent
        e.location = Vector(loc) - parent.matrix_world.translation
        bpy.context.view_layer.update()
    return e


root = empty("Toad", (0, 0, 0))
piv = {"Body": empty("Body", BODY, root)}
for s, sd in ((1, "L"), (-1, "R")):
    piv["Arm" + sd] = empty("Arm" + sd, mirror(SHOULDER, s), root)
    piv["Hand" + sd] = empty("Hand" + sd, mirror(WRIST, s), piv["Arm" + sd])
    piv["Leg" + sd] = empty("Leg" + sd, mirror(HIP, s), root)
    piv["Foot" + sd] = empty("Foot" + sd, mirror(HEEL, s), piv["Leg" + sd])

# ---------------------------------------------------------------- esqueleto: um osso por pivô, a cabeça do osso no pivô
arm = bpy.data.armatures.new("ToadIA_Rig")
rig = bpy.data.objects.new("ToadIA_Rig", arm)
scn.collection.objects.link(rig)
rig.parent = root
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='EDIT')
BONES = {"Body": (None, BODY, BODY + Vector((0, -0.2, 0)))}
for s, sd in ((1, "L"), (-1, "R")):
    BONES["Arm" + sd] = (None, mirror(SHOULDER, s), mirror(WRIST, s))
    BONES["Hand" + sd] = ("Arm" + sd, mirror(WRIST, s), mirror(HAND_TIP, s))
    BONES["Leg" + sd] = (None, mirror(HIP, s), mirror(HEEL, s))
    BONES["Foot" + sd] = ("Leg" + sd, mirror(HEEL, s), mirror(TOE, s))
SK = "_skin"     # osso "<pivô>_skin": o PivotSkin tira o sufixo (com o mesmo nome do pivô o Godot renomeia o osso)
for name, (par, h, t) in BONES.items():
    b = arm.edit_bones.new(name + SK)
    b.head, b.tail = h, t
for name, (par, h, t) in BONES.items():
    if par:
        arm.edit_bones[name + SK].parent = arm.edit_bones[par + SK]
bpy.ops.object.mode_set(mode='OBJECT')


# ---------------------------------------------------------------- pesos por regra
def seg_dist(p, a, b):
    d = b - a
    t = max(0.0, min(1.0, (p - a).dot(d) / d.length_squared))
    return (p - (a + d * t)).length


def weights(co):
    s = 1 if co.x > 0 else -1
    sd = "L" if s > 0 else "R"
    ax = co.x * s       # distância ao meio, do lado do ponto
    low = 1 - smooth(0.045, 0.085, co.z)      # mão e pé: a parte que apoia no chão
    # pata da frente: raio em volta do eixo ombro-punho (o anel do punho tem raio ~0,09), abaixo do ombro; a mão
    # no chão (z < 0,05, à frente de y -0,07) inteira
    r = seg_dist(co, mirror(SHOULDER, s), mirror(WRIST, s))
    front = (1 - smooth(0.095, 0.125, r)) * (1 - smooth(0.20, 0.27, co.z)) * (ax > 0.1)
    # a mão inteira no chão: as pontas dos dedos (bolas até z 0,08) e o dedo de dentro (|x| 0,05..0,1) ficavam
    # no Body e rasgavam quando ele inchava (a barriga da frente só começa em z 0,1)
    if co.y < -0.06 and 0.03 < ax < 0.45:
        front = max(front, 1 - smooth(0.085, 0.10, co.z))
    # pata de trás: a coxa é o volume fora da parede do corpo (a parede fica em |x| 0,33..0,35); o pé no chão inteiro
    hind = smooth(0.31, 0.37, ax) * (1 - smooth(0.30, 0.38, co.z)) * smooth(-0.02, 0.04, co.y)
    if co.y > 0.0 and ax > 0.14:     # os dedos de dentro chegam a |x| 0,15; a barriga embaixo fica em |x| < 0,13
        hind = max(hind, 1 - smooth(0.08, 0.10, co.z))
    if front > 0 and hind > 0:      # nunca as duas patas no mesmo vértice (não acontece pela forma; garante)
        if front >= hind:
            hind = 0.0
        else:
            front = 0.0
    W = {}
    if front > 0:
        W["Arm" + sd] = front * (1 - low)
        W["Hand" + sd] = front * low
    if hind > 0:
        W["Leg" + sd] = hind * (1 - low)
        W["Foot" + sd] = hind * low
    body = 1.0 - front - hind
    if body > 0:
        W["Body"] = body
    return {k: w for k, w in W.items() if w > 1e-4}


ob.parent = rig
md = ob.modifiers.new("rig", "ARMATURE")
md.object = rig
groups = {name: ob.vertex_groups.new(name=name + SK) for name in BONES}
for v in me.vertices:
    W = weights(v.co)
    tot = sum(W.values()) or 1.0
    for k, w in W.items():
        groups[k].add([v.index], w / tot, 'REPLACE')

# ---------------------------------------------------------------- conferência: combinação de grupos por vértice
# (a cor do osso dominante esconde mistura): só Body + uma pata, ou ossos da mesma pata, podem dividir um vértice
gi = {g.index: g.name[:-len(SK)] for g in ob.vertex_groups}
combos, ERRADO = {}, 0
for v in me.vertices:
    names = tuple(sorted(gi[g.group] for g in v.groups if g.weight > 0.05))
    combos[names] = combos.get(names, 0) + 1
for names, n in sorted(combos.items(), key=lambda kv: -kv[1]):
    limbs = {nm for nm in names if nm != "Body"}
    fams = {("F" if nm[:3] in ("Arm", "Han") else "B") + nm[-1] for nm in limbs}
    bad = len(fams) > 1
    ERRADO += n if bad else 0
    print("GRUPOS %-30s %5d%s" % ("+".join(names), n, "  <- ERRO" if bad else ""))
print("GRUPOS errados: %d vértices" % ERRADO)

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

# ---------------------------------------------------------------- prévia: pesos e poses de teste (pulo e inchaço)
if PREVIA:
    os.makedirs(PREVIA, exist_ok=True)
    scn.render.engine = "BLENDER_WORKBENCH"
    sh = scn.display.shading
    sh.light, sh.color_type = "FLAT", "TEXTURE"
    scn.view_settings.view_transform = "Standard"
    scn.world = bpy.data.worlds.new("w")
    scn.world.color = (0.45, 0.47, 0.52)
    scn.render.resolution_x = scn.render.resolution_y = 600
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scn.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    scn.camera = cam
    C = Vector((0, 0, 0.4))
    VIEWS = (("lado", C + Vector((-4, 0, 0)), (math.pi / 2, 0, -math.pi / 2), 1.5),
             ("frente", C + Vector((0, -4, 0)), (math.pi / 2, 0, 0), 1.5),
             ("tres_quartos", C + Vector((-3, -3, 2.0)), None, 1.6),
             ("baixo", C + Vector((0, 0, -4)), (math.pi, 0, 0), 1.5))

    def shoot(prefix):
        for nm, loc, rotc, sc in VIEWS:
            cam.location = loc
            cam.rotation_euler = rotc if rotc else (C - loc).to_track_quat("-Z", "Y").to_euler()
            cam.data.ortho_scale = sc
            scn.render.filepath = os.path.join(PREVIA, "%s_%s.png" % (prefix, nm))
            bpy.ops.render.render(write_still=True)

    PAL = {"Body": (0.55, 0.55, 0.55), "ArmL": (0.9, 0.1, 0.1), "HandL": (1, 0.55, 0.55),
           "ArmR": (0.1, 0.8, 0.1), "HandR": (0.55, 1, 0.55), "LegL": (0.1, 0.4, 1.0), "FootL": (0.5, 0.8, 1),
           "LegR": (0.9, 0.2, 0.8), "FootR": (1, 0.6, 0.95)}
    ca = me.color_attributes.new("peso", 'FLOAT_COLOR', 'POINT')
    for v in me.vertices:
        g = max(v.groups, key=lambda g: g.weight, default=None)
        ca.data[v.index].color = (*(PAL.get(gi[g.group], (0, 0, 0)) if g else (0, 0, 0)), 1)
    sh.color_type = "VERTEX"
    shoot("pesos")
    me.color_attributes.remove(me.color_attributes["peso"])
    sh.color_type = "TEXTURE"
    pb = rig.pose.bones
    # giro em x do mundo (como o jogo); "escala" incha o Body e sobe o pivô para a barriga não afundar
    POSES = {"repouso": ({}, 1.0),
             "pulo": ({"LegL": 0.5, "LegR": 0.5, "FootL": 0.4, "FootR": 0.4, "ArmL": -0.4, "ArmR": -0.4}, 1.0),
             "inchado": ({}, 1.5)}
    for pose, (rot, sc) in POSES.items():
        for b in pb:
            b.rotation_mode = 'XYZ'
            b.rotation_euler = (0, 0, 0)
            b.scale = (1, 1, 1)
            b.location = (0, 0, 0)
        for k, a in rot.items():
            b = pb[k + SK]
            mw = (rig.matrix_world @ b.bone.matrix_local).to_3x3()
            axl = mw.inverted() @ Vector((1, 0, 0))
            b.rotation_mode = 'AXIS_ANGLE'
            b.rotation_axis_angle = (a, *axl)
        if sc != 1.0:
            b = pb["Body" + SK]
            b.scale = (sc, sc, sc)
            mw = (rig.matrix_world @ b.bone.matrix_local).to_3x3()
            b.location = mw.inverted() @ Vector((0, 0, (sc - 1) * (BODY.z - 0.06)))
        bpy.context.view_layer.update()
        shoot(pose)
    for b in pb:
        b.rotation_mode = 'XYZ'
        b.rotation_euler = (0, 0, 0)
        b.scale = (1, 1, 1)
        b.location = (0, 0, 0)

for o in scn.objects:
    o.select_set(o.type != 'CAMERA')
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_yup=True,
                          export_animations=False, export_cameras=False, export_lights=False,
                          export_image_format='JPEG', export_jpeg_quality=88, export_skins=True,
                          export_def_bones=False)
print("EXPORT", OUT)
