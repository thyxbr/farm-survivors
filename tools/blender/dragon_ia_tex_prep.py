# Elmo do Dragão com a pintura gerada pela IA: prepara a base que gear.py carrega (estilo h_dragonhead).
#
#   blender --background --factory-startup --python tools/blender/dragon_ia_tex_prep.py -- <pintado.glb> [pasta_previa]
#
# <pintado.glb> sai de D:\ia3d\pintar.py (etapa de textura do Hunyuan3D-2 rodando na placa AMD): a malha de
# 40 mil faces com UV e textura de 2048 px. Aqui ela é reduzida para o jogo mantendo o UV, a textura cai para
# 1024 px e a peça vai para a altura da cabeça do herói -> base/dragon_ia_tex_base.blend.
# Nenhuma cor é decidida aqui: tudo vem da textura da IA.
import math
import os
import sys

import bpy
from mathutils import Vector

AQUI = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.join(AQUI, "base", "dragon_ia_tex_base.blend")
args = sys.argv[sys.argv.index("--") + 1:]
PINTADO = args[0]
PREVIA = args[1] if len(args) > 1 else None

FACES = 16000                       # triângulos da peça pronta
TEX = 1024                          # lado da textura no jogo
S = 0.48                            # metros por unidade (a malha é normalizada com altura 1)
C_UNID = Vector((0.0, 0.08, 0.03))  # centro do crânio na malha normalizada
C_JOGO = Vector((0.0, 0.016, 1.69)) # centro da cabeça do herói (gear.py, antes de HEAD_DROP)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=PINTADO)
scn = bpy.context.scene
malhas = [o for o in scn.objects if o.type == "MESH"]
bpy.ops.object.select_all(action="DESELECT")
for o in malhas:
    o.select_set(True)
bpy.context.view_layer.objects.active = malhas[0]
if len(malhas) > 1:
    bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
mw = ob.matrix_world.copy()
ob.parent = None
ob.matrix_world = mw
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in [o for o in scn.objects if o is not ob]:
    bpy.data.objects.remove(o, do_unlink=True)
ob.name = ob.data.name = "DragonTex"
me = ob.data

xs, ys, zs = zip(*[tuple(v.co) for v in me.vertices])
centro = Vector(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, (min(zs) + max(zs)) / 2))
esc = 1.0 / (max(zs) - min(zs))
for v in me.vertices:
    v.co = ((v.co - centro) * esc - C_UNID) * S + C_JOGO

# O glTF traz um vértice por canto de UV: solda os que estão no mesmo lugar (o UV fica nos cantos das faces)
# para a redução enxergar a malha fechada, e não as ilhas de UV como pedaços soltos.
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=1e-6)
bpy.ops.object.mode_set(mode='OBJECT')
antes = len(me.polygons)
mod = ob.modifiers.new("dec", "DECIMATE")
mod.ratio = FACES / len(me.polygons)
mod.delimit = {'UV'}                # não funde através das costuras do UV: a textura não escorrega
bpy.ops.object.modifier_apply(modifier="dec")
for p in me.polygons:
    p.use_smooth = True
me.set_sharp_from_angle(angle=math.radians(42))
print("MALHA %d -> %d faces, %d vertices" % (antes, len(me.polygons), len(me.vertices)))

# textura: a da IA, reduzida para TEX e embutida na base
img = next(i for i in bpy.data.images if i.size[0] > 0 and i.name != "Render Result")
print("TEXTURA original %dx%d" % tuple(img.size))
img.scale(TEX, TEX)
os.makedirs(os.path.dirname(BASE), exist_ok=True)
img.name = "dragon_ia_tex_albedo"
img.filepath_raw = os.path.join(os.path.dirname(BASE), "dragon_ia_tex_albedo.png")
img.file_format = 'PNG'
img.save()
img.pack()
me.materials.clear()
mat = bpy.data.materials.new("dgt_paint_flat")     # _flat: o jogo não soma a sombra de forma dele
mat.use_nodes = True
nt = mat.node_tree
bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
no = nt.nodes.new("ShaderNodeTexImage")
no.image = img
nt.links.new(no.outputs["Color"], bsdf.inputs["Base Color"])
bsdf.inputs["Roughness"].default_value = 0.8
bsdf.inputs["Metallic"].default_value = 0.0
me.materials.append(mat)
for a in list(me.color_attributes):
    me.color_attributes.remove(a)
xs, ys, zs = zip(*[tuple(v.co) for v in me.vertices])
print("JOGO x %.3f..%.3f y %.3f..%.3f z %.3f..%.3f" % (min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)))

if PREVIA:
    os.makedirs(PREVIA, exist_ok=True)
    scn.render.engine = "BLENDER_WORKBENCH"
    scn.display.shading.light = "FLAT"
    scn.display.shading.color_type = "TEXTURE"
    scn.display.render_aa = "8"
    scn.view_settings.view_transform = "Standard"
    scn.world = bpy.data.worlds.new("w")
    scn.world.color = (0.6, 0.6, 0.6)
    scn.render.resolution_x = scn.render.resolution_y = 768
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scn.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 0.62
    scn.camera = cam
    alvo = Vector((0, -0.02, C_JOGO.z - 0.015))
    for nome, de in (("frente", (0, -5, 0)), ("lado", (5, 0, 0)), ("costas", (0, 5, 0)),
                     ("tres_quartos", (2.6, -4.0, 0.9))):
        cam.location = alvo + Vector(de)
        cam.rotation_euler = (alvo - cam.location).to_track_quat('-Z', 'Y').to_euler()
        scn.render.filepath = os.path.join(PREVIA, "tex_%s.png" % nome)
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)
bpy.ops.wm.save_as_mainfile(filepath=BASE)
print("OK", BASE)
