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
# montantes de nível 50 (armory.py, build_gsia): a vista de frente já tem a lâmina de pé, ponta em +Z
for _gs in ("abismo", "arcano", "aurora", "tempestade", "carmesim", "inverno"):
    PECAS["gs_" + _gs] = ("gsia_%s_base.blend" % _gs, "Gs%sTex" % _gs.capitalize(), 0, False, None, 10000, False)
ARQ, NOME, GIRO, ESPELHO, CORTE, FACES, CHIFRE = PECAS[PECA]
# manchas que a pintura da IA deixou: caixas (x0, x1, z0, z1, lado em y) na peça normalizada, repintadas com o
# vermelho mais forte em volta. Peitoral: o emblema da frente vazou para o meio das costas, acima do cinto.
LIMPA = {"peito": [(-0.14, 0.14, -0.09, 0.13, 1)]}.get(PECA, [])
BASE = os.path.join(AQUI, "base", ARQ)
TEX = 1024                          # lado da textura no jogo
# montantes: decalque das linhas acesas do conceito (cores alvo) nas faces de frente e de costas. A pintura da IA
# perde traços finos (circuitos, raio, orbes); a lâmina é plana e a malha saiu destas mesmas vistas, então a
# vista de frente cai certa nela. Só as linhas na cor alvo: o resto continua a pintura da IA (regra 1 do
# docs/EQUIPAMENTO_POR_IA.md: projetar o conceito inteiro numa peça curva deu manchas).
DECAL = {"gs_abismo": ["#b04cff"], "gs_arcano": ["#3ee0ff", "#9a6cff"], "gs_tempestade": ["#38b8ff", "#2c3e66"]}.get(PECA, [])
# branco que a pintura deixou onde o conceito é energia (Abismo: corrente de orbes da fenda e cristal do pomo; a
# lâmina é negra, então todo texel claro e sem cor é dessa energia): vira a cor alvo, com o brilho que tinha
TINGE = {"gs_abismo": "#b04cff"}.get(PECA)
# fenda vazada: faces de frente/costas que caem no fundo do conceito nas duas vistas saem (o gerador fechou o vão)
FURO = PECA in ("gs_tempestade",)
VISTAS = os.path.join(os.environ.get("IA3D", "D:/ia3d"), "vistas", PECA)


def _vista(nome):
    """(pixels float 0..1, caixa da peça (x0, y0, x1, y1), cor do fundo) de uma vista do conceito."""
    import numpy as np
    im = bpy.data.images.load(os.path.join(VISTAS, nome))
    im.colorspace_settings.name = "Non-Color"      # valores do arquivo como estão (a textura da IA também é sRGB crua)
    W, Hh = im.size
    px = np.array(im.pixels[:], dtype=np.float32).reshape(Hh, W, 4)[::-1, :, :3].copy()   # linha 0 = topo
    bpy.data.images.remove(im)
    fundo = px[3, 3]
    cheio = np.abs(px - fundo).sum(2) > 40 / 255.0
    ys, xs = np.where(cheio)
    return px, (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1), fundo, cheio


def _alvo_mask(px, cores):
    """Pixels saturados no tom de uma das cores alvo e com brilho perto do dela (0..1): o ciano aceso pede pixel
    claro; o azul-marinho das penas, pixel escuro (contorno preto e prata ficam de fora)."""
    import numpy as np
    mx, mn = px.max(2), px.min(2)
    sat = (mx - mn) / np.maximum(mx, 1e-4)
    pn = px / np.maximum(mx[:, :, None], 1e-4)
    m = np.zeros(mx.shape, np.float32)
    for c in cores:
        c = np.array([int(c[i:i + 2], 16) / 255.0 for i in (1, 3, 5)], np.float32)
        cm = c.max()
        escuro = cm < 0.6    # azul-ardósia das penas: pouco saturado, aceita tom mais solto
        perto = 1.0 - np.clip(np.abs(pn - c / cm).sum(2) / (0.85 if escuro else 0.55), 0.0, 1.0)
        luz = np.clip((mx - 0.6 * cm) / (0.25 * cm), 0, 1) * np.clip((min(1.0, 1.6 * cm) + 0.1 - mx) / 0.1, 0, 1)
        cor = np.clip((sat - (0.12 if escuro else 0.3)) / 0.15, 0, 1)
        m = np.maximum(m, perto * luz * cor)
    return m


def _projetor(me):
    """Função (x, z, frente?) -> (linha, coluna) do pixel na vista, pela caixa da malha e da peça no conceito."""
    xs, zs = [v.co.x for v in me.vertices], [v.co.z for v in me.vertices]
    x0, x1, z0, z1 = min(xs), max(xs), min(zs), max(zs)

    def proj(x, z, caixa, frente):
        bx0, by0, bx1, by1 = caixa
        u = (x - x0) / (x1 - x0) if frente else (x1 - x) / (x1 - x0)   # costas: vista de trás, esquerda e direita trocadas
        v = (z1 - z) / (z1 - z0)
        return by0 + v * (by1 - by0 - 1), bx0 + u * (bx1 - bx0 - 1)
    return proj


def fura_fenda(me):
    import bmesh
    import numpy as np
    vf, vc = _vista("frente.png"), _vista("costas.png")
    proj = _projetor(me)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.normal_update()
    sai = []
    for f in bm.faces:
        if abs(f.normal.y) < 0.6:
            continue
        c = f.calc_center_median()
        fundo_nas_duas = True
        for (px, caixa, fundo, cheio), frente in ((vf, True), (vc, False)):
            r, k = proj(c.x, c.z, caixa, frente)
            r, k = int(round(r)), int(round(k))
            if 0 <= r < cheio.shape[0] and 0 <= k < cheio.shape[1] and cheio[max(0, r - 1):r + 2, max(0, k - 1):k + 2].any():
                fundo_nas_duas = False
        if fundo_nas_duas:
            sai.append(f)
    bmesh.ops.delete(bm, geom=sai, context="FACES")
    soltos = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=soltos, context="VERTS")
    print("FURO %d faces tiradas (fenda vazada)" % len(sai))
    bm.to_mesh(me)
    bm.free()


def decalca(me, img, cores):
    """Pinta na textura, texel a texel, as linhas do conceito na cor alvo (frente nas faces -Y, costas nas +Y)."""
    import numpy as np
    W, Hh = img.size
    tex = np.array(img.pixels[:], dtype=np.float32).reshape(Hh, W, 4)
    vistas = []
    for nome, frente in (("frente.png", True), ("costas.png", False)):
        px, caixa, _, _ = _vista(nome)
        vistas.append((px, caixa, _alvo_mask(px, cores), frente))
    proj = _projetor(me)
    me.calc_loop_triangles()
    uvl = me.uv_layers.active.data
    feitos = 0
    for t in me.loop_triangles:
        ny = t.normal.y
        if abs(ny) < 0.5:
            continue
        px, caixa, mask, frente = vistas[0] if ny < 0 else vistas[1]
        P = np.array([me.vertices[i].co[:] for i in t.vertices])
        U = np.array([uvl[l].uv[:] for l in t.loops]) * (W, Hh)
        lo, hi = np.floor(U.min(0)).astype(int), np.ceil(U.max(0)).astype(int) + 1
        gx, gy = np.meshgrid(np.arange(max(lo[0], 0), min(hi[0], W)), np.arange(max(lo[1], 0), min(hi[1], Hh)))
        if gx.size == 0:
            continue
        q = np.stack([gx.ravel() + 0.5, gy.ravel() + 0.5], 1)
        a, b, c = U
        den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(den) < 1e-9:
            continue
        w0 = ((b[1] - c[1]) * (q[:, 0] - c[0]) + (c[0] - b[0]) * (q[:, 1] - c[1])) / den
        w1 = ((c[1] - a[1]) * (q[:, 0] - c[0]) + (a[0] - c[0]) * (q[:, 1] - c[1])) / den
        w2 = 1 - w0 - w1
        dentro = (w0 >= -0.02) & (w1 >= -0.02) & (w2 >= -0.02)
        if not dentro.any():
            continue
        X = w0[dentro] * P[0, 0] + w1[dentro] * P[1, 0] + w2[dentro] * P[2, 0]
        Z = w0[dentro] * P[0, 2] + w1[dentro] * P[1, 2] + w2[dentro] * P[2, 2]
        r, k = proj(X, Z, caixa, frente)
        r = np.clip(np.round(r).astype(int), 0, mask.shape[0] - 1)
        k = np.clip(np.round(k).astype(int), 0, mask.shape[1] - 1)
        m = mask[r, k][:, None]
        tx, ty = q[dentro, 0].astype(int), q[dentro, 1].astype(int)
        # a textura do Blender é sRGB guardada como está nos pixels: a cor do conceito entra direto
        tex[ty, tx, :3] = tex[ty, tx, :3] * (1 - m) + px[r, k] * m
        feitos += int((m > 0.3).sum())
    img.pixels[:] = tex.ravel()
    print("DECALQUE %d texels nas cores %s" % (feitos, cores))


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

if FURO:
    fura_fenda(me)
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
    if TINGE:
        import numpy as np
        t = np.array(img.pixels[:], dtype=np.float32).reshape(-1, 4)
        mx, mn = t[:, :3].max(1), t[:, :3].min(1)
        claro = np.clip((mx - 0.5) / 0.2, 0, 1) * np.clip((0.35 - (mx - mn) / np.maximum(mx, 1e-4)) / 0.15, 0, 1)
        alvo = np.array([int(TINGE[i:i + 2], 16) / 255.0 for i in (1, 3, 5)], np.float32)
        cor = np.minimum(1.0, alvo[None, :] * (0.6 + 0.6 * mx[:, None]))
        t[:, :3] = t[:, :3] * (1 - claro[:, None]) + cor * claro[:, None]
        img.pixels[:] = t.ravel()
        print("TINGE %d texels claros -> %s" % (int((claro > 0.5).sum()), TINGE))
    if DECAL:
        decalca(me, img, DECAL)
    if PECA.startswith("gs_"):
        # a imagem veio empacotada no GLB: save()/pack() gravam os bytes originais (2048 px, sem decalque nem
        # tinta). Uma imagem nova com os pixels editados é o que vai para a base.
        nova = bpy.data.images.new("tmp", TEX, TEX)
        nova.pixels[:] = img.pixels[:]
        bpy.data.images.remove(img)
        img = nova
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
