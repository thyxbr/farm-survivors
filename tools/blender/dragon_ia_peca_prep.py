# Armadura do Dragão com a pintura gerada pela IA: prepara as bases que gear.py carrega (estilos a_/g_/f_dragonia).
#
#   blender --background --factory-startup --python tools/blender/dragon_ia_peca_prep.py -- <pintado.glb> <peça> [pasta_previa]
#
# Irmão de dragon_ia_tex_prep.py (elmo). <peça> é uma das chaves de PECAS. A peça sai normalizada (altura 1,
# centro da caixa na origem) e girada para o lugar dela no corpo; a escala e o lugar no herói ficam nos
# build_*_dragonia de gear.py, que conhecem o esqueleto. Nenhuma cor é decidida aqui: tudo vem da textura da IA.
#
# Vistas do conceito: frente = -Y no Blender. A ombreira e a braçadeira são do lado ESQUERDO com a face de fora
# para a câmera, então giram 90° para a face de fora olhar para +X; peitoral, coxote e greva já olham para -Y.
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

AQUI = os.path.dirname(os.path.abspath(__file__))
args = sys.argv[sys.argv.index("--") + 1:]
PINTADO = args[0]
PECA = args[1]
PREVIA = args[2] if len(args) > 2 else None

PECAS = {   # base, objeto, giro em Z (graus), espelhar em x antes do giro, corte embaixo (z normalizado ou None),
            # triângulos, tirar o chifre de dentro
    "ombreira": ("dragon_ia_pauldron_base.blend", "PauldronTex", 90, False, None, 9000, True),
    # braçadeira: espelhada para o chifre ficar no cotovelo (atrás); a luva da IA sai (a mão é feita no gear.py)
    "braco": ("dragon_ia_vambrace_base.blend", "VambraceTex", 90, True, -0.27, 7000, False),
    "coxa": ("dragon_ia_cuisse_base.blend", "CuisseTex", 0, False, None, 7000, False),
    "canela": ("dragon_ia_greave_base.blend", "GreaveTex", 0, False, None, 9000, False),
    "peito": ("dragon_ia_chest_base.blend", "ChestTex", 0, False, None, 16000, False),
}
ARQ, NOME, GIRO, ESPELHO, CORTE, FACES, CHIFRE = PECAS[PECA]
# manchas que a pintura da IA deixou: caixas (x0, x1, z0, z1, lado em y) na peça normalizada, repintadas com o
# vermelho mais forte em volta. Peitoral: o emblema da frente vazou para o meio das costas, acima do cinto.
LIMPA = {"peito": [(-0.14, 0.14, -0.09, 0.13, 1)]}.get(PECA, [])
BASE = os.path.join(AQUI, "base", ARQ)
TEX = 1024                          # lado da textura no jogo


RAIO_RAIZ = 0.08                    # unidades da malha normalizada (altura 1)


def tira_chifre_de_dentro(me, img):
    """A IA fez dois chifres lado a lado no alto da copa; o conceito tem um só, do lado de fora. Os chifres são
    as faces cor de osso da textura (claras e pouco saturadas: o friso é dourado, a placa é vermelha); separados
    em ilhas, sai a de x menor (a de dentro, perto do pescoço) e o furo na raiz é fechado com a cor da borda."""
    import bmesh
    import numpy as np
    W, H = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)
    bm = bmesh.new()
    bm.from_mesh(me)
    uvl = bm.loops.layers.uv.active
    bm.faces.ensure_lookup_table()

    def osso(f):
        u = sum(l[uvl].uv.x for l in f.loops) / len(f.loops)
        v = sum(l[uvl].uv.y for l in f.loops) / len(f.loops)
        r, g, b = px[min(H - 1, max(0, int(v * H))), min(W - 1, max(0, int(u * W))), :3]
        mx, mn = max(r, g, b), min(r, g, b)
        return mx > 0.55 and (mx - mn) / mx < 0.32
    chifre = {f for f in bm.faces if osso(f)}
    ilhas, visto = [], set()
    for f in chifre:
        if f in visto:
            continue
        ilha, pilha = [], [f]
        visto.add(f)
        while pilha:
            a = pilha.pop()
            ilha.append(a)
            for e in a.edges:
                for b in e.link_faces:
                    if b in chifre and b not in visto:
                        visto.add(b)
                        pilha.append(b)
        ilhas.append(ilha)
    ilhas = [i for i in ilhas if len(i) > 40]           # pintas claras soltas na placa não são chifre
    ilhas.sort(key=lambda i: sum(f.calc_center_median().x for f in i) / len(i))
    print("CHIFRES %d ilhas: %s" % (len(ilhas), ["%d faces x=%.3f z=%.3f" % (len(i), sum(f.calc_center_median().x for f in i) / len(i),
                                                  max(v.co.z for f in i for v in f.verts)) for i in ilhas]))
    if len(ilhas) < 2:
        bm.free()
        return
    dentro = ilhas[0]
    bmesh.ops.delete(bm, geom=dentro, context="FACES_ONLY")
    soltos = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=soltos, context='VERTS')
    borda = [e for e in bm.edges if e.is_boundary]
    raiz = sum((v.co for e in borda for v in e.verts), Vector()) / max(1, 2 * len(borda))
    novas = bmesh.ops.holes_fill(bm, edges=borda, sides=0)["faces"]
    novas = set(bmesh.ops.triangulate(bm, faces=novas)["faces"])

    def cor(g):
        u = sum(l[uvl].uv.x for l in g.loops) / len(g.loops)
        v = sum(l[uvl].uv.y for l in g.loops) / len(g.loops)
        r, gg, bb = px[min(H - 1, max(0, int(v * H))), min(W - 1, max(0, int(u * W))), :3]
        return r - max(gg, bb), (u, v)
    # a pintura sujou a placa em volta da raiz com a cor do chifre: tudo o que não é vermelho num raio da raiz
    # entra no tampo, que fica numa cor só (o UV do centro da face vizinha mais vermelha)
    perto = {g for g in bm.faces if (g.calc_center_median() - raiz).length < RAIO_RAIZ and g not in novas}
    sujas = {g for g in perto if cor(g)[0] < 0.12}
    _, uv0 = max(cor(g) for g in perto - sujas)
    for f in novas | sujas:
        for l in f.loops:
            l[uvl].uv = uv0
    novas = novas | sujas
    print("TAMPO %d faces, bordas abertas restantes %d" % (len(novas), sum(1 for e in bm.edges if e.is_boundary)))
    bm.to_mesh(me)
    bm.free()
    me.update()


def limpa_caixas(me, img, caixas):
    """Repinta as faces dentro de cada caixa (só as viradas para o lado dado em y) com o UV do centro da face mais
    vermelha da borda da caixa: a mancha some numa cor lisa de placa."""
    import bmesh
    import numpy as np
    W, H = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)
    bm = bmesh.new()
    bm.from_mesh(me)
    uvl = bm.loops.layers.uv.active
    bm.normal_update()

    def cor(g):
        u = sum(l[uvl].uv.x for l in g.loops) / len(g.loops)
        v = sum(l[uvl].uv.y for l in g.loops) / len(g.loops)
        r, gg, bb = px[min(H - 1, max(0, int(v * H))), min(W - 1, max(0, int(u * W))), :3]
        return r - 2 * max(gg, bb), (u, v)     # vermelho da placa, não o laranja do friso
    for x0, x1, z0, z1, ly in caixas:
        def dentro(f, m=0.0):
            c = f.calc_center_median()
            return (x0 - m <= c.x <= x1 + m and z0 - m <= c.z <= z1 + m and c.y * ly > 0 and f.normal.y * ly > 0.2)
        alvo = [f for f in bm.faces if dentro(f)]
        borda = [f for f in bm.faces if dentro(f, 0.05) and not dentro(f)]
        _, uv0 = max(cor(g) for g in borda)
        for f in alvo:
            for l in f.loops:
                l[uvl].uv = uv0
        print("LIMPA caixa (%.2f..%.2f, %.2f..%.2f): %d faces" % (x0, x1, z0, z1, len(alvo)))
    bm.to_mesh(me)
    bm.free()


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
ob.name = ob.data.name = NOME
me = ob.data

xs, ys, zs = zip(*[tuple(v.co) for v in me.vertices])
centro = Vector(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, (min(zs) + max(zs)) / 2))
esc = 1.0 / (max(zs) - min(zs))
me.transform(Matrix.Rotation(math.radians(GIRO), 4, 'Z') @ Matrix.Scale(esc, 4) @ Matrix.Translation(-centro) @
             Matrix.Scale(-1 if ESPELHO else 1, 4, (1, 0, 0)))
if ESPELHO or CORTE is not None:
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(me)
    if ESPELHO:                     # o espelho inverte a ordem dos cantos: faces de volta para fora
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    if CORTE is not None:           # corta embaixo e fecha a boca com a cor da borda
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, CORTE),
                               plane_no=(0, 0, 1), clear_inner=True)
        bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)
        borda = [e for e in bm.edges if e.is_boundary]
        tampa = bmesh.ops.holes_fill(bm, edges=borda, sides=0)["faces"]
        uvl = bm.loops.layers.uv.active
        for f in tampa:
            for l in f.loops:
                ref = next((o for o in l.vert.link_loops if o.face not in tampa), None)
                if ref is not None:
                    l[uvl].uv = ref[uvl].uv.copy()
        bmesh.ops.triangulate(bm, faces=tampa)
        print("CORTE em z=%.2f: tampa de %d faces" % (CORTE, len(tampa)))
    bm.to_mesh(me)
    bm.free()
    xs, ys, zs = zip(*[tuple(v.co) for v in me.vertices])
    c2 = Vector(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, (min(zs) + max(zs)) / 2))
    me.transform(Matrix.Scale(1.0 / (max(zs) - min(zs)), 4) @ Matrix.Translation(-c2))

bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=1e-6)
bpy.ops.object.mode_set(mode='OBJECT')
antes = len(me.polygons)
mod = ob.modifiers.new("dec", "DECIMATE")
mod.ratio = min(1.0, FACES / len(me.polygons))
mod.delimit = {'UV'}
bpy.ops.object.modifier_apply(modifier="dec")
for p in me.polygons:
    p.use_smooth = True
me.set_sharp_from_angle(angle=math.radians(42))
print("MALHA %d -> %d faces, %d vertices" % (antes, len(me.polygons), len(me.vertices)))

img = next((i for i in bpy.data.images if i.size[0] > 0 and i.name != "Render Result"), None)
os.makedirs(os.path.dirname(BASE), exist_ok=True)
if img is None:                     # malha ainda sem pintura: só para acertar lugar e escala no herói
    print("TEXTURA nenhuma (cinza)")
else:
    print("TEXTURA original %dx%d" % tuple(img.size))
    if CHIFRE:
        tira_chifre_de_dentro(me, img)
    if LIMPA:
        limpa_caixas(me, img, LIMPA)
    img.scale(TEX, TEX)
    img.name = ARQ.replace("_base.blend", "_albedo")
    img.filepath_raw = os.path.join(os.path.dirname(BASE), img.name + ".png")
    img.file_format = 'PNG'
    img.save()
    img.pack()
me.materials.clear()
mat = bpy.data.materials.new("dg%s_paint_flat" % PECA)     # _flat: o jogo não soma a sombra de forma dele
mat.use_nodes = True
nt = mat.node_tree
bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
if img is not None:
    no = nt.nodes.new("ShaderNodeTexImage")
    no.image = img
    nt.links.new(no.outputs["Color"], bsdf.inputs["Base Color"])
bsdf.inputs["Roughness"].default_value = 0.8
bsdf.inputs["Metallic"].default_value = 0.0
me.materials.append(mat)
for a in list(me.color_attributes):
    me.color_attributes.remove(a)
xs, ys, zs = zip(*[tuple(v.co) for v in me.vertices])
print("UNID x %.3f..%.3f y %.3f..%.3f z %.3f..%.3f" % (min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)))

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
    cam.data.ortho_scale = 1.3
    scn.camera = cam
    alvo = Vector((0, 0, 0))
    # nomes pela câmera: menos_y = de frente para o herói, mais_x = do lado de fora do lado esquerdo
    for nome, de in (("menos_y", (0, -5, 0)), ("mais_x", (5, 0, 0)), ("mais_y", (0, 5, 0)), ("menos_x", (-5, 0, 0)),
                     ("cima", (0, 0, 5)), ("tres_quartos", (4.0, -2.6, 0.9))):
        cam.location = alvo + Vector(de)
        cam.rotation_euler = (alvo - cam.location).to_track_quat('-Z', 'Y').to_euler()
        scn.render.filepath = os.path.join(PREVIA, "tex_%s.png" % nome)
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)
bpy.ops.wm.save_as_mainfile(filepath=BASE)
print("OK", BASE)
