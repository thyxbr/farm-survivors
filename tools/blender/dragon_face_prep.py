# Prepara o rosto do Elmo do Dragão a partir do modelo esculpido gerado por IA (imagem -> 3D).
# O modelo gerado tem o rosto bem esculpido, mas é só a metade da frente, cortada reta atrás (um "troféu").
# Etapa 1 (este arquivo, com STAGE=1): põe na escala e posição da cabeça do jogo (ajuste medido contra a vista de
#   lado da ficha: 90% de sobreposição), corta a gola abaixo dos ombros, tira a tampa reta de trás, reduz os
#   polígonos e guarda a cor da textura por vértice. Salva um .blend intermediário.
# Uso:  SRC=<glb gerado> OUT=<pasta> blender --background --factory-startup --python dragon_face_prep.py
import bpy, bmesh, os, math
import numpy as np
from mathutils import Vector, Matrix

SRC = os.environ["SRC"]
OUTD = os.environ["OUT"].rstrip("/") + "/"
DH_S = 0.00155
DH_EYE = Vector((0.0, -0.095, 1.72))
FIT_S, FIT_OY, FIT_OZ = 440.0, 47.0, -218.0       # px da ficha por unidade do modelo; origem do modelo em (u, v)
Z_CUT = 1.49                                        # gola cortada acima dos ombros
TARGET_FACES = int(os.environ.get("FACES", "42000"))

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.gltf(filepath=SRC)
scn = bpy.context.scene
ob = [o for o in scn.objects if o.type == 'MESH'][0]
for o in list(scn.objects):
    if o is not ob:
        bpy.data.objects.remove(o, do_unlink=True)
bpy.context.view_layer.update()
me = ob.data
# para o referencial do jogo (frente = -Y, esquerda do boneco = +X), em metros
K = FIT_S * DH_S
T = (Matrix.Translation((0, DH_EYE.y + FIT_OY * DH_S, DH_EYE.z + FIT_OZ * DH_S)) @ Matrix.Scale(K, 4)
     @ Matrix.Rotation(math.pi / 2, 4, 'Z'))
me.transform(T @ ob.matrix_world)
ob.matrix_world = Matrix.Identity(4)
ob.parent = None
me.update()
co = np.empty(len(me.vertices) * 3, np.float32)
me.vertices.foreach_get("co", co)
co = co.reshape(-1, 3)
y_back = float(co[:, 1].max())
print("BBOX", co.min(0), co.max(0), "plano de trás y=%.4f" % y_back)

bm = bmesh.new()
bm.from_mesh(me)
# tampa reta de trás: faces com os três vértices no plano
# (a tampa é levemente abaulada, não um plano exato: vale a face virada para trás nos últimos 4 cm)
bm.normal_update()
back = [f for f in bm.faces if f.normal.y > 0.75 and f.calc_center_median().y > y_back - 0.04]
print("faces da tampa", len(back))
bmesh.ops.delete(bm, geom=back, context='FACES')
# gola: corta abaixo de Z_CUT
geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, Z_CUT), plane_no=(0, 0, -1), clear_outer=True)
bm.to_mesh(me)
bm.free()
me.update()
print("depois dos cortes", len(me.polygons))

# cor da textura por vértice (canto), antes de reduzir: serve para separar chifre/ouro/olho e para a pintura
img = next(i for i in bpy.data.images if i.size[0] > 1000 and "normal" not in i.name and "metallic" not in i.name)
W, H = img.size
px = np.empty(W * H * 4, np.float32)
img.pixels.foreach_get(px)
px = px.reshape(H, W, 4)
uv = np.empty(len(me.loops) * 2, np.float32)
me.uv_layers.active.data.foreach_get("uv", uv)
uv = uv.reshape(-1, 2)
ix = np.clip((uv[:, 0] % 1.0 * W).astype(int), 0, W - 1)
iy = np.clip((uv[:, 1] % 1.0 * H).astype(int), 0, H - 1)
cols = px[iy, ix]
ca = me.color_attributes.new("Col", 'BYTE_COLOR', 'CORNER')
ca.data.foreach_set("color", cols.reshape(-1))      # textura em sRGB -> atributo BYTE (guarda como está)
me.color_attributes.active_color = ca

# solda os vértices duplicados nas emendas da textura (o glTF separa; sem soldar a redução abre frestas)
bm = bmesh.new()
bm.from_mesh(me)
n0 = len(bm.verts)
bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)
print("soldados", n0 - len(bm.verts), "de", n0)
bm.to_mesh(me)
bm.free()
me.update()
# reduz os polígonos
ratio = TARGET_FACES / max(1, len(me.polygons))
mod = ob.modifiers.new("Dec", 'DECIMATE')
mod.ratio = ratio
bpy.context.view_layer.objects.active = ob
ob.select_set(True)
bpy.ops.object.modifier_apply(modifier="Dec")
print("depois de reduzir", len(ob.data.polygons), "verts", len(ob.data.vertices))
ob.name = "DragonFace"
ob.data.name = "DragonFace"
# textura menor, salva junto
img.scale(1024, 1024)
img.filepath_raw = OUTD + "face_albedo.png"
img.file_format = 'PNG'
img.save()
# o arquivo embutido no .glb continua sendo o de 4096: troca pela imagem reduzida, lida do PNG salvo
small = bpy.data.images.load(OUTD + "face_albedo.png")
for m in ob.data.materials:
    for nd in m.node_tree.nodes:
        if nd.type == 'TEX_IMAGE':
            if nd.image is img:
                nd.image = small
            else:                       # normal e metal/rugosidade: o jogo é toon, não usa
                m.node_tree.nodes.remove(nd)
for i in list(bpy.data.images):
    if i is not small:
        bpy.data.images.remove(i)
# o material vinha como metal polido: no toon do jogo isso escurece a cor e põe faixa de brilho
for m in ob.data.materials:
    bs = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    for nm in ("Metallic", "Roughness", "Normal"):          # sobras das texturas removidas ficam ligadas
        for lk in list(bs.inputs[nm].links):
            m.node_tree.links.remove(lk)
    bs.inputs["Metallic"].default_value = 0.0
    bs.inputs["Roughness"].default_value = 0.75
bpy.ops.wm.save_as_mainfile(filepath=OUTD + "face_stage1.blend")
print("STAGE1 DONE y_back=%.5f" % y_back)
