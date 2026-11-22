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


# Recolor do rosto por variante: cada faixa da textura (osso, ouro, brasa dos olhos, corpo vermelho) vira lum * mult + add.
DH_TINTS = {
    "dark": dict(bone=((0.82, 0.78, 0.70), (0, 0, 0)), gold=((1.0, 0.8, 0.5), (0.04, 0.03, 0)),
                 ember=(0.95, 0.3, 0.06), body=(0.395, 0.38, 0.38),
                 back=(0.03, 0.03, 0.032), back_gold=(0.4, 0.3, 0.15), eye=(1.0, 0.3, 0.1)),
}


def _dh_tint(img, T):
    """Recolore a textura do rosto por faixa de matiz (osso/claro, ouro, brasa dos olhos, corpo), sem tocar no .blend."""
    import numpy as np
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
    for key, sel in (("bone", bone), ("gold", gold)):
        mul, add = T[key]
        for c in range(3):
            out[sel, c] = lum[sel] * mul[c] + add[c]
    for c in range(3):
        out[ember, c] = T["ember"][c] if c != 1 else np.minimum(1.0, T["ember"][1] + 0.1 * v[ember])
        out[body, c] = np.clip(lum[body] * T["body"][c], 0, 1)
    img.pixels.foreach_set(out.reshape(-1))
    img.update()


def _build_h_dragonknight(style, variant):
    P, R = g_rig(style)
    head = R["Head"]
    with bpy.data.libraries.load(DH_BASE) as (src, dst):
        dst.objects = [n for n in src.objects if n == "DragonFace"]
    ob = dst.objects[0]
    coll.objects.link(ob)
    if variant:
        T = DH_TINTS[variant]
        # por posição (face, costas, ouro das costas, olhos): o nome pode ganhar sufixo .00N se o mesmo .blend já foi carregado
        mf, mb, mg, me = [m.copy() for m in ob.data.materials[:4]]
        for i, m in enumerate((mf, mb, mg, me)):
            m.name = "dh_%s_%s" % (variant, ("face", "back", "back_gold", "eye_flat")[i])
            ob.data.materials[i] = m
        for n in mf.node_tree.nodes:
            if n.type == 'TEX_IMAGE' and n.image and "normal" not in n.image.name:
                n.image = n.image.copy()
                n.image.name = "face_albedo_%s.png" % variant
                _dh_tint(n.image, T)
        for m, key in ((mb, "back"), (mg, "back_gold")):
            m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = tuple(T[key]) + (1,)
        bsdf = me.node_tree.nodes["Principled BSDF"]
        for k in ("Base Color", "Emission Color"):
            if k in bsdf.inputs:
                bsdf.inputs[k].default_value = tuple(T["eye"]) + (1,)
    ob.data.transform(Matrix.Translation(-_wloc(head)))
    ob.parent = head
    ob.location = (0, 0, 0)
    ob["wloc"] = list(_wloc(head))
    g_head_done(style, "DragonKnightHelm", [ob], P, R)


def build_h_dragonknight():
    _build_h_dragonknight("h_dragonknight", "")


def build_h_dragonknight_dark():
    _build_h_dragonknight("h_dragonknight_dark", "dark")


def build_h_dragonknight_ice():
    """Tiara de gelo do conjunto de gelo (o rosto de dragão fechado destoava do gelo): aro de prata baixo, cristais de
    gelo de alturas diferentes (o do meio é o mais alto), gema ciano na testa e dois chifres curtos e brancos que
    saem das têmporas e curvam para trás. O cabelo do herói aparece por baixo."""
    style = "h_dragonknight_ice"
    P, R, head = g_head(style)
    K = dragonknight_mats("ice")
    crystal = gm("drk_ice_crystal_flat", "#A8DCF5", 0.5)
    zf = lambda th: 1.757 + 0.008 * math.cos(th)
    band = [g_headring(lambda th, dz=dz: zf(th) + dz, out, 48) for dz, out in ((-0.014, 0.004), (0.0, 0.008),
                                                                               (0.014, 0.004))]
    parts = [g_smooth_mesh("TiaraBand", band, K["gold"], head, cap_end=False, thick=0.005)]
    for i, dz in enumerate((-0.014, 0.014)):
        parts.append(g_pipe("TiaraRim%d" % i, g_headring(lambda th, dz=dz: zf(th) + dz, 0.0055, 48), 0.004, K["gold"],
                            head, loop=True))
    up = Vector((0, 0, 1))
    for k, (th, ln, r) in enumerate(((0.0, 0.17, 0.026), (0.42, 0.115, 0.02), (-0.42, 0.115, 0.02),
                                     (0.85, 0.075, 0.015), (-0.85, 0.075, 0.015), (1.2, 0.045, 0.011),
                                     (-1.2, 0.045, 0.011))):
        b = g_skull(th, zf(th) + 0.004, 0.004)
        od = Vector((math.sin(th), -math.cos(th), 0))
        parts.append(g_shard("TiaraIce%d" % k, b - up * 0.012, b + up * ln + od * ln * 0.18, r, crystal, head,
                             twist=k * 0.5))
    parts.append(g_gem("TiaraGem", g_skull(0, zf(0) - 0.002, 0.012), 0.014, 0.02, 0.008, K["gem"], head))
    for sd, sx in (("L", 1), ("R", -1)):
        th = sx * 1.5
        b = g_skull(th, zf(th) + 0.004, 0.006)
        P0 = b
        P1 = b + Vector((sx * 0.03, 0.035, 0.02))
        P2 = b + Vector((sx * 0.052, 0.095, 0.055))
        P3 = b + Vector((sx * 0.04, 0.15, 0.135))
        NH = 14
        path = [P0 * (1 - t) ** 3 + P1 * 3 * t * (1 - t) ** 2 + P2 * 3 * t * t * (1 - t) + P3 * t ** 3
                for t in (i / NH for i in range(NH + 1))]
        rad = [(0.016 * (1 - i / NH) ** 0.8 + 0.002,) * 2 for i in range(NH + 1)]
        parts.append(g_smooth_mesh("TiaraHorn" + sd, g_curved_tube(path, rad, sides=12), K["bone"], head))
    g_head_done(style, "DragonKnightTiara", parts, P, R)
