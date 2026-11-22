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


def build_h_dragonknight():
    P, R = g_rig("h_dragonknight")
    head = R["Head"]
    with bpy.data.libraries.load(DH_BASE) as (src, dst):
        dst.objects = [n for n in src.objects if n == "DragonFace"]
    ob = dst.objects[0]
    coll.objects.link(ob)
    ob.data.transform(Matrix.Translation(-_wloc(head)))
    ob.parent = head
    ob.location = (0, 0, 0)
    ob["wloc"] = list(_wloc(head))
    g_head_done("h_dragonknight", "DragonKnightHelm", [ob], P, R)
