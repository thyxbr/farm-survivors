# Elmo do Cavaleiro Dragão (h_dragonknight), a partir das fichas em tools/blender/refs/elmo_dragao/.
# Executado por exec() depois de gear.py.
#
# O rosto é esculpido: vem de um modelo gerado por IA (imagem -> 3D) a partir das vistas da ficha, preparado por
# dragon_face_prep.py (escala e posição da cabeça do jogo, cortes, redução de polígonos) e dragon_face_back.py
# (costas construídas girando o perfil do corte, chifres fechados). O resultado fica em
# tools/blender/base/dragon_face_base.blend, com a textura embutida; aqui ele só é carregado, preso à cabeça e exportado.
# (A primeira tentativa, toda por código com seções e placas, não chegou perto da ficha: rosto esculpido não se
# descreve bem com tabelas de medidas.)
DH_BASE = OUT.replace("assets/models/", "tools/blender/base/dragon_face_base.blend")


def _dh_tint_dark(img):
    """Versão sombria da textura do rosto: o vermelho vira quase preto de tom quente, o ouro vira aço azulado, o osso
    vira marfim cinzento e o laranja aceso (olhos, faíscas) vira violeta. Atua por faixa de matiz, sem tocar no .blend."""
    import numpy as np
    import colorsys
    w, h = img.size
    px = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(-1, 4)
    r, g, b = px[:, 0], px[:, 1], px[:, 2]
    v = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    sat = (v - mn) / np.maximum(v, 1e-4)
    d = np.maximum(v - mn, 1e-4)
    hue = np.where(v == r, ((g - b) / d) % 6, np.where(v == g, (b - r) / d + 2, (r - g) / d + 4)) * 60.0
    out = px.copy()
    bone = (v > 0.42) & (sat < 0.5)
    ember = (~bone) & (hue < 30) & (sat > 0.7) & (v > 0.75)
    gold = (~bone) & (~ember) & (hue >= 28) & (hue < 70) & (sat > 0.35) & (v > 0.45)
    body = ~(bone | ember | gold)
    lum = 0.3 * r + 0.59 * g + 0.11 * b
    out[bone, 0] = lum[bone] * 0.82
    out[bone, 1] = lum[bone] * 0.78
    out[bone, 2] = lum[bone] * 0.70
    out[gold, 0] = lum[gold] * 0.62 + 0.03
    out[gold, 1] = lum[gold] * 0.66 + 0.03
    out[gold, 2] = lum[gold] * 0.80 + 0.06
    out[ember, 0] = 0.34 + 0.45 * v[ember] * 0.5
    out[ember, 1] = 0.12 + 0.2 * v[ember] * 0.5
    out[ember, 2] = 0.65 + 0.35 * v[ember]
    out[body, 0] = r[body] * 0.34
    out[body, 1] = g[body] * 0.32
    out[body, 2] = b[body] * 0.38
    img.pixels.foreach_set(out.reshape(-1))
    img.update()


def _build_h_dragonknight(style, variant):
    P, R = g_rig(style)
    head = R["Head"]
    with bpy.data.libraries.load(DH_BASE) as (src, dst):
        dst.objects = [n for n in src.objects if n == "DragonFace"]
    ob = dst.objects[0]
    coll.objects.link(ob)
    if variant == "dark":
        # por posição (face, costas, ouro das costas, olhos): o nome pode ganhar sufixo .00N se o mesmo .blend já foi carregado
        mf, mb, mg, me = [m.copy() for m in ob.data.materials[:4]]
        for i, m in enumerate((mf, mb, mg, me)):
            m.name = "dh_dark_" + ("face", "back", "back_gold", "eye_flat")[i]
            ob.data.materials[i] = m
        for n in mf.node_tree.nodes:
            if n.type == 'TEX_IMAGE' and n.image and "normal" not in n.image.name:
                n.image = n.image.copy()
                n.image.name = "face_albedo_dark.png"
                _dh_tint_dark(n.image)
        mb.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.045, 0.035, 0.04, 1)
        mg.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.22, 0.24, 0.30, 1)
        bsdf = me.node_tree.nodes["Principled BSDF"]
        for k in ("Base Color", "Emission Color"):
            if k in bsdf.inputs:
                bsdf.inputs[k].default_value = (0.55, 0.2, 1.0, 1)
    ob.data.transform(Matrix.Translation(-_wloc(head)))
    ob.parent = head
    ob.location = (0, 0, 0)
    ob["wloc"] = list(_wloc(head))
    g_head_done(style, "DragonKnightHelm", [ob], P, R)


def build_h_dragonknight():
    _build_h_dragonknight("h_dragonknight", "")


def build_h_dragonknight_dark():
    _build_h_dragonknight("h_dragonknight_dark", "dark")
