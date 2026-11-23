"""Sanguessuga do Lodo gerada por IA local (monstro do Pântano, docs/EQUIPAMENTO_POR_IA.md, seção Monstros).

  blender -b --factory-startup --python tools/blender/leech_ia_build.py -- [pintado.glb] [pasta_previa]

Entrada: a malha pintada pela IA (D:/ia3d/saida/sanguessuga/pintura/pintado.glb, folha de três vistas do usuário).
Saída: assets/models/leech_ia.glb com uma cadeia de pivôs ao longo do corpo (Head à frente, Body atrás do pescoço,
Tail, Tail2 e Tail3 até a cauda), um esqueleto com um osso `<pivô>_skin` por pivô e a malha com pele. No jogo o PivotSkin faz cada osso
seguir o seu pivô e a animação é a da sanguessuga (enemy.gd, _animate_leech): onda de lado a lado ao rastejar e bote
que ergue a frente e dispara a cabeça.

Pesos ao longo do eixo do corpo (y), com mistura larga em cada junta para o corpo dobrar liso; a ventosa da boca vai
inteira na cabeça e o disco da cauda no Tail2.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SRC = ARGS[0] if ARGS else os.path.join(os.environ.get("IA3D", "D:/ia3d"), "saida/sanguessuga/pintura/pintado.glb")
PREVIA = ARGS[1] if len(ARGS) > 1 else ""
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets/models/leech_ia.glb")

LENGTH = 1.4       # da boca ao disco da cauda (o jogo ainda multiplica pela escala do tipo)
FACES = 8000       # malha do jogo (a IA entrega 40 mil); 10 sanguessugas no Pântano
TEX = 1024

# ---------------------------------------------------------------- pivôs, medidos na malha normalizada
# frente = -Y; sola em z 0. O pescoço sobe a partir de y -0,34 (cabeça erguida até z 0,61 em y -0,54); o corpo tem
# 0,4 de altura no meio e afina para trás a partir de y 0,24 até o disco da cauda (y 0,7).
HEAD = Vector((0, -0.34, 0.20))      # base do pescoço: a cabeça se ergue e se abaixa daqui
# o corpo em quatro ossos (com um osso só do pescoço até y 0,24 o meio ficava rígido e a onda saía dura)
BODY = Vector((0, -0.12, 0.20))
TAIL = Vector((0, 0.10, 0.19))
TAIL2 = Vector((0, 0.32, 0.17))
TAIL3 = Vector((0, 0.52, 0.14))
HEAD_TIP = Vector((0, -0.70, 0.45))
TAIL_TIP = Vector((0, 0.70, 0.24))
BLEND = 0.06        # meia largura da mistura em cada junta (o gomo tem ~0,12)


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

# ---------------------------------------------------------------- normaliza: comprimento LENGTH, sola em z 0, centro em x e y
ys = [v.co.y for v in me.vertices]
zs = [v.co.z for v in me.vertices]
me.transform(Matrix.Scale(LENGTH / (max(ys) - min(ys)), 4) @ Matrix.Translation((0, 0, -min(zs))))
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
    img.name = "leech_ia_albedo"
me.materials.clear()
paint = bpy.data.materials.new("lcia_paint_flat")     # _flat: a luz já vem pintada, o toon não soma sombra de forma
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
ob.name = me.name = "LeechIA"


def empty(name, loc, parent=None):
    e = bpy.data.objects.new(name, None)
    e.location = loc
    scn.collection.objects.link(e)
    if parent:
        e.parent = parent
        e.location = Vector(loc) - parent.matrix_world.translation
        bpy.context.view_layer.update()
    return e


# cadeia: o Body no meio; a cabeça para a frente e a cauda (dois ossos) para trás, todos filhos do Body
root = empty("Leech", (0, 0, 0))
piv = {"Body": empty("Body", BODY, root)}
piv["Head"] = empty("Head", HEAD, piv["Body"])
piv["Tail"] = empty("Tail", TAIL, piv["Body"])
piv["Tail2"] = empty("Tail2", TAIL2, piv["Tail"])
piv["Tail3"] = empty("Tail3", TAIL3, piv["Tail2"])

arm = bpy.data.armatures.new("LeechIA_Rig")
rig = bpy.data.objects.new("LeechIA_Rig", arm)
scn.collection.objects.link(rig)
rig.parent = root
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='EDIT')
BONES = {"Body": (None, BODY, BODY + Vector((0, -0.2, 0))), "Head": ("Body", HEAD, HEAD_TIP),
         "Tail": ("Body", TAIL, TAIL2), "Tail2": ("Tail", TAIL2, TAIL3), "Tail3": ("Tail2", TAIL3, TAIL_TIP)}
SK = "_skin"     # osso "<pivô>_skin": o PivotSkin tira o sufixo (com o mesmo nome do pivô o Godot renomeia o osso)
for name, (par, h, t) in BONES.items():
    b = arm.edit_bones.new(name + SK)
    b.head, b.tail = h, t
for name, (par, h, t) in BONES.items():
    if par:
        arm.edit_bones[name + SK].parent = arm.edit_bones[par + SK]
bpy.ops.object.mode_set(mode='OBJECT')


def weights(co):
    """Ao longo do eixo: cabeça à frente da base do pescoço, Tail2 atrás do seu pivô, Tail entre os dois pivôs de trás."""
    head = smooth(HEAD.y + BLEND, HEAD.y - BLEND, co.y)
    s1, s2, s3 = (smooth(p.y - BLEND, p.y + BLEND, co.y) for p in (TAIL, TAIL2, TAIL3))
    body = max(0.0, 1.0 - head - s1)
    return {k: w for k, w in (("Head", head), ("Body", body), ("Tail", s1 - s2), ("Tail2", s2 - s3), ("Tail3", s3))
            if w > 1e-4}


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
# numa cadeia só ossos vizinhos podem dividir um vértice (Head+Tail ou Body+Tail2 seria erro)
gi = {g.index: g.name[:-len(SK)] for g in ob.vertex_groups}
NEIGH = {frozenset(("Head", "Body")), frozenset(("Body", "Tail")), frozenset(("Tail", "Tail2")), frozenset(("Tail2", "Tail3"))}
combos, ERRADO = {}, 0
for v in me.vertices:
    names = tuple(sorted(gi[g.group] for g in v.groups if g.weight > 0.05))
    combos[names] = combos.get(names, 0) + 1
for names, n in sorted(combos.items(), key=lambda kv: -kv[1]):
    bad = len(names) > 2 or (len(names) == 2 and frozenset(names) not in NEIGH)
    ERRADO += n if bad else 0
    print("GRUPOS %-24s %5d%s" % ("+".join(names), n, "  <- ERRO" if bad else ""))
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

# ---------------------------------------------------------------- prévia: pesos e pose de teste (curva de lado + cabeça erguida)
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
    C = Vector((0, 0, 0.25))
    VIEWS = (("lado", C + Vector((-4, 0, 0)), (math.pi / 2, 0, -math.pi / 2), 1.7),
             ("cima", C + Vector((0, 0, 4)), (0, 0, 0), 1.7),
             ("tres_quartos", C + Vector((-3, -3, 2.0)), None, 1.9))

    def shoot(prefix):
        for nm, loc, rotc, sc in VIEWS:
            cam.location = loc
            cam.rotation_euler = rotc if rotc else (C - loc).to_track_quat("-Z", "Y").to_euler()
            cam.data.ortho_scale = sc
            scn.render.filepath = os.path.join(PREVIA, "%s_%s.png" % (prefix, nm))
            bpy.ops.render.render(write_still=True)

    PAL = {"Body": (0.55, 0.55, 0.55), "Head": (0.9, 0.8, 0.1), "Tail": (0.2, 0.5, 1.0), "Tail2": (0.6, 0.2, 1.0),
           "Tail3": (0.9, 0.3, 0.3)}
    ca = me.color_attributes.new("peso", 'FLOAT_COLOR', 'POINT')
    for v in me.vertices:
        g = max(v.groups, key=lambda g: g.weight, default=None)
        ca.data[v.index].color = (*(PAL.get(gi[g.group], (0, 0, 0)) if g else (0, 0, 0)), 1)
    sh.color_type = "VERTEX"
    shoot("pesos")
    me.color_attributes.remove(me.color_attributes["peso"])
    sh.color_type = "TEXTURE"
    pb = rig.pose.bones
    POSES = {"repouso": {}, "teste": {"Head": ((0, 0, 1), 0.35), "Tail": ((0, 0, 1), -0.3), "Tail2": ((0, 0, 1), -0.3),
                                      "Tail3": ((0, 0, 1), 0.3)},
             "erguida": {"Head": ((1, 0, 0), -0.6)}}
    for pose, rot in POSES.items():
        for b in pb:
            b.rotation_mode = 'XYZ'
            b.rotation_euler = (0, 0, 0)
        for k, (axw, a) in rot.items():     # giro no eixo do mundo
            b = pb[k + SK]
            mw = (rig.matrix_world @ b.bone.matrix_local).to_3x3()
            ax = mw.inverted() @ Vector(axw)
            b.rotation_mode = 'AXIS_ANGLE'
            b.rotation_axis_angle = (a, *ax)
        bpy.context.view_layer.update()
        shoot(pose)
    for b in pb:
        b.rotation_mode = 'XYZ'
        b.rotation_euler = (0, 0, 0)

for o in scn.objects:
    o.select_set(o.type != 'CAMERA')
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_yup=True,
                          export_animations=False, export_cameras=False, export_lights=False,
                          export_image_format='JPEG', export_jpeg_quality=88, export_skins=True,
                          export_def_bones=False)
print("EXPORT", OUT)
