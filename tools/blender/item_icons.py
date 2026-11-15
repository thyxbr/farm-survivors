"""Modelos dos ícones de item sem modelo de equipamento (poções, comida, colheitas, sementes, materiais,
anéis, amuletos, orbe, aljava). Um GLB por família; a cor do item entra no Godot, nos materiais
`i_tint`, `i_tint_dark`, `i_tint_light` e `i_tint_glow` (scripts/ui/item_icon_models.gd, item_icons.gd).
Ver docs/INTERFACE_GRIMORIO.md, etapa 3.

  blender --background --factory-startup --python tools/blender/item_icons.py -- <pasta de saída>
  (depois: godot --headless --path . --import)

Estilo: low-poly facetado, poucas formas, cor chapada; a peça é lida em 62 px. Frente = -Y, chão em
Z=0, cada peça com uns 25 a 35 cm (a mesma escala dos equipamentos).
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "assets/models/items"
PI = math.pi
scn = bpy.context.scene


# ------------------------------------------------------------------ materiais
def _lin(c):
    return tuple(((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in c)


def mat(name, color, rough=0.85, metal=0.0, emit=0.0):
    """Material chapado. `color` em sRGB (o que se vê na tela)."""
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    b = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    lin = _lin(color)
    b.inputs["Base Color"].default_value = (*lin, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit > 0.0:
        b.inputs["Emission Color"].default_value = (*lin, 1)
        b.inputs["Emission Strength"].default_value = emit
    m.diffuse_color = (*lin, 1)
    m.use_backface_culling = False       # folhas e peças abertas (coroa) aparecem dos dois lados
    return m


# a cor destes quatro é trocada pela do item no Godot
TINT = mat("i_tint", (0.8, 0.3, 0.3))
TINT_DK = mat("i_tint_dark", (0.5, 0.18, 0.18))
TINT_LT = mat("i_tint_light", (1.0, 0.6, 0.6))
TINT_GLOW = mat("i_tint_glow", (0.8, 0.3, 0.3), emit=1.0)

GOLD = mat("i_gold", (0.93, 0.72, 0.28), 0.4, 0.7)
GOLD_DK = mat("i_gold_dark", (0.66, 0.45, 0.14), 0.4, 0.7)
STEEL = mat("i_steel", (0.72, 0.75, 0.8), 0.4, 0.7)
GLASS = mat("i_glass", (0.82, 0.92, 0.96), 0.3)
CORK = mat("i_cork", (0.62, 0.42, 0.24))
WOOD = mat("i_wood", (0.5, 0.33, 0.17))
WOOD_DK = mat("i_wood_dark", (0.33, 0.2, 0.1))
WOOD_LT = mat("i_wood_light", (0.68, 0.5, 0.3))
LEATHER = mat("i_leather", (0.45, 0.28, 0.13))
LEATHER_DK = mat("i_leather_dark", (0.27, 0.16, 0.07))
BURLAP = mat("i_burlap", (0.72, 0.58, 0.38))
BURLAP_DK = mat("i_burlap_dark", (0.5, 0.38, 0.22))
ROPE = mat("i_rope", (0.38, 0.26, 0.14))
LEAF = mat("i_leaf", (0.3, 0.66, 0.22))
LEAF_DK = mat("i_leaf_dark", (0.18, 0.45, 0.15))
STRAW = mat("i_straw", (0.78, 0.66, 0.32))
STONE = mat("i_stone", (0.36, 0.35, 0.38))
STONE_DK = mat("i_stone_dark", (0.22, 0.21, 0.24))
WHITE = mat("i_white", (0.96, 0.94, 0.88))
CREAM = mat("i_cream", (0.9, 0.84, 0.72))
CRUST = mat("i_crust", (0.85, 0.62, 0.32))
CRUST_DK = mat("i_crust_dark", (0.62, 0.4, 0.18))
ROAST = mat("i_roast", (0.66, 0.36, 0.15))
ROAST_DK = mat("i_roast_dark", (0.45, 0.22, 0.09))
RED = mat("i_red", (0.82, 0.14, 0.16))
RED_DK = mat("i_red_dark", (0.55, 0.08, 0.1))
FLESH = mat("i_flesh", (0.7, 0.3, 0.3))
DARK = mat("i_dark", (0.12, 0.09, 0.08))


# ------------------------------------------------------------------ formas
def _obj(bm, material, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.00005)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    M = Matrix.Translation(Vector(loc)) @ Euler(rot).to_matrix().to_4x4() @ Matrix.Diagonal((*scale, 1))
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    me = bpy.data.meshes.new("m")
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    for m in (material if isinstance(material, (list, tuple)) else [material]):
        me.materials.append(m)
    ob = bpy.data.objects.new("o", me)
    scn.collection.objects.link(ob)
    return ob


def lathe(prof, material, seg=8, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1), rib=0.0, wobble=0.0, seed=1,
          cap=True, split=None):
    """Sólido de revolução em torno de Z. prof = [(raio, z), ...] de baixo para cima.
    rib afunda um gomo sim, um não (abóbora); split = índice do anel a partir do qual vale o 2º material."""
    rnd = random.Random(seed)
    bm = bmesh.new()
    rings = []
    for r, z in prof:
        ring = []
        for i in range(seg):
            a = 2 * PI * i / seg
            rr = r * (1 - rib * (i % 2)) * (1 + rnd.uniform(-wobble, wobble))
            ring.append(bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, z)))
        rings.append(ring)
    for k in range(len(rings) - 1):
        for i in range(seg):
            j = (i + 1) % seg
            f = bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
            if split is not None and k >= split:
                f.material_index = 1
    if cap and prof[0][0] > 0.0001:
        bm.faces.new(list(reversed(rings[0])))
    if cap and prof[-1][0] > 0.0001:
        f = bm.faces.new(rings[-1])
        if split is not None:
            f.material_index = 1
    return _obj(bm, material, loc, rot, scale)


def ball(r, material, loc=(0, 0, 0), sub=2, scale=(1, 1, 1), rot=(0, 0, 0), floor=None):
    """Esfera facetada. floor achata o que ficar abaixo dessa altura (em raios), para assentar."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=r)
    if floor is not None:
        for v in bm.verts:
            v.co.z = max(v.co.z, floor * r)
    return _obj(bm, material, loc, rot, scale)


def box(size, material, loc=(0, 0, 0), rot=(0, 0, 0), bev=0.006, taper=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    if taper:
        for v in bm.verts:
            if v.co.z > 0:
                v.co.x *= taper[0]
                v.co.y *= taper[1]
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    if bev > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(bev, min(size) * 0.4), segments=1, affect='EDGES',
                        profile=0.5)
    return _obj(bm, material, loc, rot)


def tube(pts, radii, material, seg=6, flat=1.0):
    """Tubo ao longo de pontos (curva no plano XZ). radii por ponto (0 fecha em ponta); flat afina em Y."""
    bm = bmesh.new()
    rings = []
    n = len(pts)
    for i in range(n):
        p = Vector(pts[i])
        t = Vector(pts[min(i + 1, n - 1)]) - Vector(pts[max(i - 1, 0)])
        q = Vector((0, 0, 1)).rotation_difference(t.normalized())
        ring = []
        for k in range(seg):
            a = 2 * PI * k / seg
            v = q @ Vector((math.cos(a) * radii[i], math.sin(a) * radii[i], 0))
            v.y *= flat
            ring.append(bm.verts.new(p + v))
        rings.append(ring)
    for k in range(n - 1):
        for i in range(seg):
            j = (i + 1) % seg
            bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
    if radii[0] > 0.0001:
        bm.faces.new(list(reversed(rings[0])))
    if radii[-1] > 0.0001:
        bm.faces.new(rings[-1])
    return _obj(bm, material)


def rod(a, b, r, material, seg=6, r2=None):
    return tube([a, b], [r, r if r2 is None else r2], material, seg)


def torus(R, r, material, loc=(0, 0, 0), rot=(0, 0, 0), seg=12, sseg=5, scale=(1, 1, 1), arc=1.0):
    """Anel em torno de Z (rot=(pi/2,0,0) deixa de frente para a câmera). arc < 1 = pedaço do anel (alça)."""
    bm = bmesh.new()
    rings = []
    count = seg if arc >= 1.0 else int(seg * arc) + 1
    for i in range(count):
        a = 2 * PI * i / seg
        ring = []
        for k in range(sseg):
            b = 2 * PI * k / sseg
            rr = R + math.cos(b) * r
            ring.append(bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, math.sin(b) * r)))
        rings.append(ring)
    last = count if arc >= 1.0 else count - 1
    for i in range(last):
        n = rings[(i + 1) % count]
        for k in range(sseg):
            j = (k + 1) % sseg
            bm.faces.new((rings[i][k], n[k], n[j], rings[i][j]))
    if arc < 1.0:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    return _obj(bm, material, loc, rot, scale)


def leaf(base, yaw, pitch, length, width, material, droop=0.2, fold=0.2):
    """Folha dobrada na nervura (4 triângulos). Nasce em base, aponta para yaw/pitch (0 = deitada em +Y)."""
    bm = bmesh.new()
    L, W = length, width
    v0 = bm.verts.new((0, 0, 0))
    vl = bm.verts.new((-W / 2, L * 0.45, W * fold))
    vm = bm.verts.new((0, L * 0.45, 0))
    vr = bm.verts.new((W / 2, L * 0.45, W * fold))
    vt = bm.verts.new((0, L, -L * droop))
    for f in ((v0, vm, vl), (v0, vr, vm), (vl, vm, vt), (vm, vr, vt)):
        bm.faces.new(f)
    M = (Matrix.Translation(Vector(base)) @ Euler((0, 0, yaw)).to_matrix().to_4x4()
         @ Euler((pitch, 0, 0)).to_matrix().to_4x4())
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    return _obj(bm, material)


def gem(r, h, material, loc=(0, 0, 0), rot=(0, 0, 0), seg=6, top=0.55):
    """Pedra lapidada: cinta larga, ponta embaixo, coroa mais baixa em cima."""
    return lathe([(0, -h), (r, 0), (r * 0.55, h * top), (0, h * top * 1.15)], material, seg, loc, rot)


def rock(size, material, loc=(0, 0, 0), n=12, seed=1, rot=(0, 0, 0)):
    """Pedra facetada: casco convexo de pontos sorteados num elipsoide, base achatada."""
    rnd = random.Random(seed)
    bm = bmesh.new()
    vs = []
    for i in range(n):
        u = rnd.uniform(-1, 1)
        a = rnd.uniform(0, 2 * PI)
        s = math.sqrt(1 - u * u)
        k = rnd.uniform(0.8, 1.0)
        vs.append(bm.verts.new((math.cos(a) * s * k, math.sin(a) * s * k, max(u * k, -0.5))))
    bmesh.ops.convex_hull(bm, input=vs)
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context='VERTS')
    sz = Vector(size) / 2
    return _obj(bm, material, (loc[0], loc[1], loc[2] + 0.5 * sz.z), rot, tuple(sz))


def prism(points, depth, material, loc=(0, 0, 0), rot=(0, 0, 0)):
    """Chapa: polígono no plano XZ (visto de frente) com espessura em Y."""
    bm = bmesh.new()
    front = [bm.verts.new((x, -depth / 2, z)) for x, z in points]
    back = [bm.verts.new((x, depth / 2, z)) for x, z in points]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    n = len(points)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[i], back[i], back[j], front[j]))
    return _obj(bm, material, loc, rot)


def star(r_out, r_in, n=5):
    pts = []
    for i in range(n * 2):
        a = PI / 2 + PI * i / n
        r = r_out if i % 2 == 0 else r_in
        pts.append((math.cos(a) * r, math.sin(a) * r))
    return pts


# ------------------------------------------------------------------ exportação
def export(name, objs, tilt=0.0, turn=0.0):
    """Junta as peças, inclina (tilt, em torno de Y: tomba para a direita) e gira (turn, em torno de Z)."""
    objs = [o for o in objs if o is not None]
    with bpy.context.temp_override(active_object=objs[0], object=objs[0], selected_objects=objs,
                                   selected_editable_objects=objs):
        bpy.ops.object.join()
    ob = objs[0]
    ob.name = name
    ob.data.name = name
    if tilt or turn:
        ob.data.transform(Euler((0, tilt, turn)).to_matrix().to_4x4())
    vl = scn.view_layers[0]
    vl.update()
    kw = {"scene": scn, "view_layer": vl}
    wins = bpy.context.window_manager.windows
    if len(wins) > 0:
        kw["window"] = wins[0]
    with bpy.context.temp_override(**kw):
        for o in scn.objects:
            o.select_set(o == ob, view_layer=vl)
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format='GLB',
                                  use_selection=True, export_apply=True, export_yup=True,
                                  export_animations=False, export_cameras=False, export_lights=False)
    print("EXPORT", name, len(ob.data.polygons), "faces", flush=True)
    bpy.data.objects.remove(ob, do_unlink=True)


# ================================================================== consumíveis
def build_potion():
    o = []
    # corpo: o líquido (cor do item) até o ombro, vidro dali para cima
    o.append(lathe([(0.05, 0), (0.1, 0.02), (0.118, 0.085), (0.1, 0.145), (0.05, 0.185), (0.04, 0.2), (0.04, 0.25),
                    (0.055, 0.262)], [TINT, GLASS], 8, split=3))
    o.append(torus(0.047, 0.011, ROPE, (0, 0, 0.215), seg=8, sseg=4))
    o.append(lathe([(0.034, 0.255), (0.04, 0.305)], CORK, 8))
    o.append(ball(0.03, TINT_LT, (-0.045, -0.085, 0.1), 1, (1, 0.5, 1.5)))       # brilho pintado
    return o


# ================================================================== equipamento sem modelo
def build_ring():
    o = []
    o.append(torus(0.1, 0.024, GOLD, (0, 0, 0.125), (PI / 2, 0, 0), 12, 5))
    o.append(lathe([(0.035, 0.22), (0.062, 0.25), (0.062, 0.262)], GOLD_DK, 6))    # engaste
    o.append(lathe([(0.066, 0.258), (0.072, 0.285), (0.045, 0.325), (0, 0.335)], [TINT, TINT_DK], 6, split=1))
    o.append(ball(0.016, TINT_LT, (-0.03, -0.05, 0.3), 1))
    return o


def build_amulet():
    o = []
    # cordão em gota, de frente; o pingente pende embaixo
    o.append(torus(0.105, 0.009, GOLD, (0, 0, 0.26), (PI / 2, 0, 0), 12, 4, (1, 1, 1.35)))
    o.append(torus(0.022, 0.008, GOLD_DK, (0, 0, 0.125), (PI / 2, 0, 0), 8, 4))
    o.append(lathe([(0.075, -0.012), (0.085, 0), (0.075, 0.012)], GOLD, 6, (0, 0, 0.06), (PI / 2, 0, PI / 6)))
    o.append(lathe([(0.055, 0), (0.035, 0.022), (0, 0.028)], TINT, 6, (0, -0.01, 0.06), (PI / 2, 0, PI / 6)))
    o.append(ball(0.014, TINT_LT, (-0.018, -0.035, 0.078), 1))
    return o


def build_orb():
    o = []
    o.append(lathe([(0.075, 0), (0.085, 0.015), (0.045, 0.035), (0.032, 0.07), (0.06, 0.095)], GOLD, 8))
    for i in range(3):
        a = 2 * PI * i / 3 + PI / 6
        c, s = math.cos(a), math.sin(a)
        o.append(rod((c * 0.05, s * 0.05, 0.085), (c * 0.115, s * 0.115, 0.2), 0.013, GOLD_DK, 4, 0.006))
    o.append(ball(0.115, TINT_GLOW, (0, 0, 0.215), 2))
    o.append(ball(0.03, TINT_LT, (-0.05, -0.08, 0.265), 1, (1, 0.6, 1)))
    return o


def build_quiver():
    o = []
    o.append(lathe([(0.045, 0), (0.06, 0.015), (0.075, 0.3)], TINT, 8, cap=True))
    o.append(lathe([(0.079, 0.262), (0.082, 0.305), (0.07, 0.307)], TINT_DK, 8))     # boca
    o.append(lathe([(0.05, 0.0), (0.066, 0.02), (0.066, 0.05)], TINT_DK, 8))         # fundo reforçado
    o.append(lathe([(0.068, 0.13), (0.074, 0.14), (0.076, 0.165), (0.07, 0.175)], GOLD_DK, 8))
    for i, (x, y, top) in enumerate(((-0.03, 0.01, 0.43), (0.01, -0.02, 0.46), (0.035, 0.02, 0.42))):
        o.append(rod((x * 0.6, y * 0.6, 0.28), (x, y, top), 0.007, WOOD_LT, 4))
        for yaw in (0.0, 2.1, 4.2):                                                    # penas
            o.append(prism([(0.006, 0), (0.03, 0.01), (0.03, 0.075), (0.006, 0.095)], 0.004, RED,
                           (x, y, top - 0.11), (0, 0, yaw + i)))
    return o


# ================================================================== horta
def build_seed_bag():
    o = []
    o.append(lathe([(0.085, 0), (0.12, 0.035), (0.125, 0.11), (0.09, 0.175), (0.05, 0.205)], BURLAP, 8, wobble=0.04,
                   seed=3))
    o.append(torus(0.05, 0.012, ROPE, (0, 0, 0.207), seg=8, sseg=4))
    o.append(lathe([(0.045, 0.205), (0.085, 0.25), (0.06, 0.255)], BURLAP_DK, 8, wobble=0.08, seed=5))  # boca franzida
    # selo na frente com a cor da cultura e sementes caídas ao lado
    o.append(lathe([(0.055, 0), (0.05, 0.012)], TINT, 8, (0, -0.118, 0.095), (PI / 2 + 0.12, 0, 0)))
    o.append(lathe([(0.03, 0), (0.026, 0.008)], TINT_LT, 6, (0, -0.13, 0.097), (PI / 2 + 0.12, 0, 0)))
    for x, y, a in ((0.15, -0.09, 0.4), (0.19, -0.02, 1.5), (0.125, -0.15, 2.4)):
        o.append(ball(0.028, TINT, (x, y, 0.014), 1, (1.3, 0.8, 0.55), (0, 0, a)))
    return o


def build_carrot():
    o = []
    o.append(lathe([(0, 0), (0.022, 0.035), (0.04, 0.11), (0.055, 0.2), (0.05, 0.245), (0.025, 0.262)], TINT, 7))
    for z in (0.07, 0.125, 0.185):                                                    # riscos da casca
        o.append(lathe([(0.012 + z * 0.22, 0), (0.014 + z * 0.22, 0.01)], TINT_DK, 7, (0, 0, z)))
    for i, (yaw, pitch, L) in enumerate(((0.0, 1.25, 0.16), (2.1, 1.0, 0.14), (4.2, 1.05, 0.15), (1.0, 1.45, 0.17),
                                         (3.2, 1.4, 0.15))):
        o.append(leaf((0, 0, 0.255), yaw, pitch, L, 0.07, LEAF if i % 2 == 0 else LEAF_DK, 0.25))
    return o


def build_wheat():
    o = []
    for i, (lean, turn) in enumerate(((-0.34, 0.0), (0.0, 0.5), (0.34, 1.0))):
        top = (math.sin(lean) * 0.2, (i - 1) * 0.012, 0.2)
        o.append(rod((math.sin(lean) * -0.03, 0, 0), top, 0.012, STRAW, 4))
        ear = lathe([(0, 0), (0.036, 0.03), (0.042, 0.09), (0.026, 0.135), (0, 0.17)], TINT, 6)
        ear.data.transform(Matrix.Translation(Vector(top)) @ Euler((0, lean, turn)).to_matrix().to_4x4())
        o.append(ear)
        for k in range(3):                                                             # grãos em relevo
            g = ball(0.02, TINT_LT, (0, -0.036, 0.045 + k * 0.04), 1, (1, 0.7, 1.4))
            g.data.transform(Matrix.Translation(Vector(top)) @ Euler((0, lean, turn)).to_matrix().to_4x4())
            o.append(g)
    o.append(torus(0.02, 0.008, ROPE, (0, 0, 0.075), seg=8, sseg=4, scale=(1.6, 1, 1)))
    return o


def build_tomato():
    o = []
    o.append(ball(0.12, TINT, (0, 0, 0.105), 2, (1, 1, 0.88)))
    o.append(ball(0.03, TINT_LT, (-0.05, -0.085, 0.15), 1, (1, 0.6, 1)))
    for i in range(5):
        o.append(leaf((0, 0, 0.207), 2 * PI * i / 5, -0.25, 0.085, 0.04, LEAF, 0.1))
    o.append(rod((0, 0, 0.2), (0.012, 0, 0.25), 0.011, LEAF_DK, 5, 0.008))
    return o


def build_pepper():
    o = []
    pts = [(-0.11, 0, 0.0), (-0.085, 0, 0.045), (-0.05, 0, 0.1), (-0.005, 0, 0.16), (0.04, 0, 0.21), (0.07, 0, 0.245)]
    o.append(tube(pts, [0.0, 0.022, 0.038, 0.05, 0.052, 0.03], TINT, 7))
    o.append(ball(0.02, TINT_LT, (-0.03, -0.04, 0.15), 1, (0.8, 0.6, 2.0), (0, 0.7, 0)))
    o.append(lathe([(0.034, 0), (0.02, 0.018)], LEAF, 6, (0.07, 0, 0.243), (0, 0.7, 0)))
    o.append(tube([(0.075, 0, 0.25), (0.095, 0, 0.285), (0.125, 0, 0.3)], [0.012, 0.01, 0.009], LEAF_DK, 5))
    return o


def build_mint():
    o = []
    o.append(rod((0, 0, 0), (0.0, 0, 0.25), 0.011, LEAF_DK, 4))
    # pares de folhas ovais abertas para os lados e para cima, de frente para a câmera
    for k, (z, L) in enumerate(((0.05, 0.16), (0.125, 0.14), (0.195, 0.11))):
        for side in (-1, 1):
            ang = side * 0.55                   # sobe para fora
            cx = side * L * 0.5 * math.cos(0.55)
            cz = z + L * 0.5 * math.sin(0.55)
            o.append(ball(1.0, TINT if (k + (side > 0)) % 2 else TINT_DK, (cx, -0.004 * k, cz), 1,
                          (L * 0.52, 0.016, L * 0.3), (0, -ang, 0)))
            o.append(rod((0, -0.02, z), (cx * 1.5, -0.02, z + (cz - z) * 1.5), 0.005, TINT_LT, 4))      # nervura
    o.append(ball(1.0, TINT_LT, (0.0, -0.01, 0.3), 1, (0.04, 0.016, 0.075)))
    return o


def build_pumpkin():
    o = []
    o.append(lathe([(0.03, 0), (0.1, 0.012), (0.145, 0.065), (0.15, 0.115), (0.115, 0.17), (0.04, 0.19)], TINT, 14,
                   rib=0.13))
    o.append(lathe([(0.04, 0.185), (0.02, 0.2)], TINT_DK, 7))
    o.append(tube([(0, 0, 0.195), (0.01, 0, 0.235), (0.04, 0, 0.26)], [0.02, 0.015, 0.013], LEAF_DK, 5))
    o.append(leaf((0.0, 0, 0.2), -1.9, -0.15, 0.1, 0.07, LEAF, 0.15))
    return o


# ================================================================== comida
def build_bread():
    o = []
    o.append(ball(0.1, TINT, (0, 0, 0.055), 2, (1.7, 1.0, 0.95), floor=-0.55))
    o.append(ball(0.1, TINT_DK, (0, 0, 0.03), 2, (1.71, 1.01, 0.42)))                 # base tostada
    for x in (-0.085, 0.0, 0.085):                                                    # cortes do pão
        o.append(box((0.026, 0.14, 0.016), TINT_DK, (x, -0.012, 0.142 - abs(x) * 0.16), (0, x * 3.0, 0.5), 0.004))
    return o


def build_bowl():
    o = []
    o.append(lathe([(0.055, 0), (0.07, 0.012), (0.125, 0.075), (0.14, 0.105), (0.128, 0.105)], WOOD, 10))
    o.append(lathe([(0.055, 0), (0.06, 0.014)], WOOD_DK, 10))
    o.append(lathe([(0.128, 0.1), (0.07, 0.11), (0, 0.113)], TINT, 10))                # caldo
    for x, y, m, r in ((-0.04, -0.03, TINT_LT, 0.3), (0.045, 0.02, TINT_DK, 1.1), (0.0, 0.055, TINT_LT, 2.0),
                       (0.03, -0.06, TINT_LT, 0.8)):                                  # pedaços
        o.append(box((0.04, 0.036, 0.026), m, (x, y, 0.115), (0.2, 0.15, r), 0.006))
    o.append(rod((0.05, 0.03, 0.1), (0.19, 0.1, 0.2), 0.011, WOOD_LT, 5))               # colher
    return o


def build_cup():
    o = []
    o.append(lathe([(0.07, 0), (0.078, 0.01), (0.088, 0.15), (0.078, 0.15)], WOOD_LT, 10))
    o.append(lathe([(0.087, 0.105), (0.092, 0.11), (0.093, 0.128), (0.088, 0.132)], STEEL, 10))
    o.append(lathe([(0.072, 0), (0.081, 0.022)], WOOD_DK, 10))
    o.append(lathe([(0.079, 0.142), (0, 0.142)], TINT, 10))                           # chá
    o.append(torus(0.045, 0.013, WOOD, (0.105, 0, 0.08), (PI / 2, 0, 0), 10, 4, (0.85, 1, 1)))
    o.append(leaf((-0.035, -0.04, 0.146), -0.9, 0.0, 0.07, 0.04, LEAF, 0.0, 0.05))    # folha boiando
    # vapor: duas espirais curtas, na cor clara do chá
    for x, h in ((-0.025, 0.0), (0.03, 0.03)):
        o.append(tube([(x, 0, 0.18 + h), (x + 0.018, 0, 0.215 + h), (x - 0.012, 0, 0.25 + h), (x + 0.008, 0, 0.285 + h)],
                      [0.006, 0.011, 0.01, 0.0], TINT_LT, 4))
    return o


def build_pie():
    o = []
    o.append(lathe([(0.105, 0), (0.14, 0.045), (0.155, 0.05), (0.15, 0.064), (0.128, 0.058)], CRUST, 12, rib=0.04))
    o.append(lathe([(0.105, 0), (0.115, 0.014)], CRUST_DK, 12))
    o.append(lathe([(0.13, 0.056), (0.06, 0.066), (0, 0.068)], TINT, 12))             # recheio
    o.append(lathe([(0.04, 0.064), (0.032, 0.085), (0.012, 0.1), (0, 0.112)], WHITE, 7))   # chantili
    for i in range(6):                                                                # fatias marcadas
        a = 2 * PI * i / 6
        o.append(box((0.07, 0.008, 0.006), TINT_DK, (math.cos(a) * 0.085, math.sin(a) * 0.085, 0.066), (0, 0, a), 0.0))
    return o


def build_feast():
    o = []
    o.append(lathe([(0.1, 0), (0.175, 0.016), (0.19, 0.03), (0.178, 0.03), (0.1, 0.014)], TINT, 12))   # travessa
    o.append(ball(0.09, ROAST, (-0.02, 0, 0.085), 2, (1.25, 0.95, 0.8)))              # assado
    o.append(ball(0.05, ROAST_DK, (-0.02, 0, 0.14), 1, (1.6, 1.0, 0.4)))
    o.append(tube([(0.06, -0.03, 0.09), (0.12, -0.03, 0.13), (0.165, -0.03, 0.165)], [0.04, 0.032, 0.016], ROAST, 6))
    o.append(rod((0.16, -0.03, 0.16), (0.215, -0.03, 0.205), 0.011, WHITE, 5))
    o.append(ball(0.02, WHITE, (0.222, -0.03, 0.212), 1, (1.3, 1, 1)))
    o.append(ball(0.03, RED, (-0.11, -0.09, 0.045), 1))                               # guarnição
    o.append(ball(0.028, RED, (0.03, -0.12, 0.043), 1))
    o.append(leaf((-0.05, -0.1, 0.035), 2.9, 0.3, 0.09, 0.06, LEAF, 0.2))
    o.append(leaf((0.1, -0.09, 0.035), -2.4, 0.3, 0.08, 0.055, LEAF_DK, 0.2))
    return o


# ================================================================== materiais
def build_gel():
    o = []
    o.append(lathe([(0.115, 0), (0.135, 0.03), (0.125, 0.1), (0.09, 0.17), (0.04, 0.205), (0, 0.215)], TINT, 9,
                   wobble=0.07, seed=4))
    o.append(ball(0.05, TINT_DK, (0.11, -0.02, 0.03), 1, (1.2, 1, 0.7)))               # escorrido
    o.append(lathe([(0.118, 0), (0.138, 0.028)], TINT_DK, 9, wobble=0.07, seed=4))
    o.append(ball(0.034, TINT_LT, (-0.05, -0.09, 0.13), 1, (1, 0.6, 1.3)))
    o.append(ball(0.016, TINT_LT, (0.02, -0.1, 0.085), 1))
    o.append(ball(0.04, TINT, (0.2, -0.06, 0.022), 1, (1, 1, 0.6)))                   # pingo
    return o


def build_ear():
    o = []
    # orelha pontuda de goblin: base larga embaixo à esquerda (o corte), ponta para cima à direita
    pts = [(-0.11, 0, 0.0), (-0.09, 0, 0.055), (-0.045, 0, 0.115), (0.025, 0, 0.175), (0.105, 0, 0.23), (0.18, 0, 0.27)]
    o.append(tube(pts, [0.05, 0.075, 0.078, 0.058, 0.03, 0.0], TINT, 7, flat=0.35))
    # a dobra de cima (hélice), em relevo, e a concha funda embaixo dela
    rim = [(-0.15, -0.012, 0.075), (-0.11, -0.012, 0.15), (-0.035, -0.012, 0.205), (0.06, -0.012, 0.245), (0.18, 0, 0.27)]
    o.append(tube(rim, [0.02, 0.024, 0.022, 0.016, 0.0], TINT_LT, 5))
    inner = [(-0.085, -0.03, 0.035), (-0.055, -0.03, 0.08), (-0.005, -0.028, 0.125), (0.06, -0.02, 0.165)]
    o.append(tube(inner, [0.022, 0.04, 0.03, 0.0], TINT_DK, 6, flat=0.3))
    o.append(lathe([(0.05, 0), (0.042, 0.014)], FLESH, 7, (-0.118, 0, -0.012), (0, -0.5 + PI, 0), (1, 0.4, 1)))   # corte
    o.append(torus(0.034, 0.009, GOLD, (-0.02, -0.02, 0.0), (PI / 2, 0, 0), 8, 4))     # brinco
    return o


def build_bone():
    o = []
    a, b = (-0.09, 0, 0.03), (0.07, 0, 0.19)
    o.append(rod(a, b, 0.024, TINT, 6, 0.02))
    for dx, dz in ((-0.028, 0.012), (0.012, -0.028)):                                 # cabeça do osso
        o.append(ball(0.036, TINT, (a[0] + dx, 0, a[2] + dz), 1))
    o.append(ball(0.03, TINT_DK, (a[0] - 0.012, 0.012, a[2] - 0.016), 1))
    o.append(rod((-0.085, 0.012, 0.022), (0.075, 0.012, 0.182), 0.022, TINT_DK, 6, 0.018))
    # a outra ponta é a lasca: quebrada em bico, com o miolo escuro
    o.append(tube([b, (0.095, 0, 0.215), (0.135, 0, 0.275)], [0.02, 0.024, 0.0], TINT, 5))
    o.append(tube([(0.085, -0.004, 0.205), (0.1, -0.006, 0.235)], [0.014, 0.0], TINT_DK, 4))
    return o


def build_crown():
    o = []
    o.append(lathe([(0.105, 0), (0.11, 0.012), (0.105, 0.075), (0.118, 0.085)], TINT, 10, cap=False))
    o.append(lathe([(0.108, 0), (0.113, 0.02)], TINT_DK, 10, cap=False))
    for i in range(5):                                                                # pontas
        a = 2 * PI * i / 5 - PI / 2
        c, s = math.cos(a), math.sin(a)
        o.append(lathe([(0.042, 0), (0, 0.1)], TINT, 4, (c * 0.106, s * 0.106, 0.078), (0, 0, a + PI / 4)))
        o.append(ball(0.016, TINT_LT, (c * 0.106, s * 0.106, 0.185), 1))
    for i in range(5):
        a = 2 * PI * (i + 0.5) / 5 - PI / 2
        o.append(ball(0.017, RED, (math.cos(a) * 0.11, math.sin(a) * 0.11, 0.045), 1))
    o.append(lathe([(0.1, 0.004), (0, 0.004)], DARK, 10))                             # fundo, para não ver através
    return o


def build_ore():
    o = []
    o.append(rock((0.26, 0.2, 0.19), STONE, (0, 0, 0), 13, 2))
    o.append(rock((0.14, 0.13, 0.11), STONE_DK, (0.12, -0.05, 0), 10, 5))
    for i, (x, y, z, s) in enumerate(((-0.05, -0.085, 0.085, 0.1), (0.05, -0.07, 0.125, 0.085), (-0.085, -0.02, 0.15, 0.07),
                                      (0.135, -0.105, 0.05, 0.07), (0.01, -0.01, 0.175, 0.075))):
        o.append(rock((s, s * 0.8, s * 0.8), TINT if i % 2 == 0 else TINT_LT, (x, y, z - s * 0.4), 8, 20 + i,
                      (0.3 * i, 0.2, i)))
    return o


def build_crystal():
    o = []
    o.append(rock((0.24, 0.2, 0.07), STONE_DK, (0, 0, 0), 11, 7))
    for x, y, r, h, tilt, m in ((0.0, 0.0, 0.05, 0.3, 0.0, TINT_GLOW), (-0.07, -0.01, 0.036, 0.2, 0.42, TINT),
                                (0.07, 0.0, 0.038, 0.22, -0.38, TINT_LT), (0.02, -0.06, 0.028, 0.13, -0.15, TINT_LT),
                                (-0.03, 0.05, 0.03, 0.17, 0.2, TINT_DK)):
        o.append(lathe([(r * 0.75, 0), (r, h * 0.72), (0, h)], m, 6, (x, y, 0.02), (0.0, -tilt, 0.3)))
    return o


def build_core():
    # esfera de pedra queimada rachada: as placas escuras saltam e a brasa aparece nas frestas
    rnd = random.Random(11)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=2, radius=0.115)
    for f in bm.faces:
        f.material_index = 0
    shell = [f for f in bm.faces if rnd.random() < 0.62]
    res = bmesh.ops.extrude_discrete_faces(bm, faces=shell)
    for f in res["faces"]:
        f.material_index = 1
        n = f.normal.copy()
        c = f.calc_center_median()
        for v in f.verts:
            v.co = c + (v.co - c) * 0.86 + n * 0.02
    core =_obj(bm, [TINT_GLOW, STONE_DK], (0, 0, 0.13))
    # as laterais das placas extrudadas ficam escuras
    for p in core.data.polygons:
        if p.material_index == 0 and len(p.vertices) == 4:
            p.material_index = 1
    return [core, ball(0.03, TINT_LT, (0.0, -0.02, 0.27), 1, (0.7, 0.7, 1.3))]


def build_drop():
    o = []
    o.append(lathe([(0, 0), (0.075, 0.025), (0.1, 0.085), (0.08, 0.16), (0.035, 0.235), (0, 0.29)], TINT, 8))
    o.append(ball(0.028, TINT_LT, (-0.04, -0.07, 0.11), 1, (0.8, 0.6, 1.6)))
    o.append(lathe([(0.1, 0.02), (0.085, 0.0)], TINT_DK, 8, (0, 0, 0)))
    return o


def build_totem():
    o = []
    o.append(box((0.13, 0.11, 0.05), WOOD_DK, (0, 0, 0.025), bev=0.008))
    o.append(box((0.11, 0.095, 0.1), WOOD, (0, 0, 0.1), bev=0.01))
    o.append(box((0.125, 0.105, 0.095), WOOD_LT, (0, 0, 0.195), bev=0.01))
    o.append(box((0.1, 0.09, 0.07), WOOD, (0, 0, 0.275), bev=0.01, taper=(0.75, 0.75)))
    for side in (-1, 1):                                                              # asas
        o.append(prism([(0, -0.025), (0.1, 0.01), (0.115, 0.06), (0.05, 0.035), (0, 0.03)] if side > 0 else
                       [(0, -0.025), (0, 0.03), (-0.05, 0.035), (-0.115, 0.06), (-0.1, 0.01)], 0.03, WOOD_DK,
                       (side * 0.06, 0, 0.2)))
        o.append(box((0.03, 0.012, 0.03), TINT_GLOW, (side * 0.03, -0.054, 0.21), bev=0.0))       # olhos
    o.append(box((0.065, 0.012, 0.018), TINT_GLOW, (0, -0.05, 0.085), bev=0.0))       # boca
    o.append(prism([(0.012, 0.05), (-0.022, 0.005), (0.0, 0.005), (-0.012, -0.045), (0.024, 0.012), (0.002, 0.012)],
                   0.012, TINT_LT, (0, -0.048, 0.275)))                                # raio na testa
    return o


def build_gland():
    o = []
    o.append(ball(0.11, TINT, (0, 0, 0.1), 2, (1.1, 0.95, 0.9)))
    for x, y, z, r in ((-0.06, -0.075, 0.13, 0.03), (0.05, -0.085, 0.075, 0.026), (0.085, -0.03, 0.15, 0.022),
                       (-0.02, -0.095, 0.055, 0.02), (0.0, -0.07, 0.17, 0.018)):      # bolhas
        o.append(ball(r, TINT_LT, (x, y, z), 1))
    o.append(tube([(0.03, 0, 0.185), (0.06, 0, 0.235), (0.11, 0, 0.26), (0.15, 0, 0.245)], [0.035, 0.026, 0.022, 0.024],
                  FLESH, 6))
    o.append(torus(0.024, 0.008, RED_DK, (0.152, 0, 0.244), (0, PI / 2 - 0.3, 0), 7, 4))
    o.append(lathe([(0, 0), (0.02, 0.012), (0.014, 0.035), (0, 0.055)], TINT_LT, 6, (0.175, 0, 0.15)))   # gota
    return o


def build_dust():
    o = []
    # saquinho de couro tombado, com o pó derramado na frente
    bag = lathe([(0.06, 0), (0.085, 0.03), (0.08, 0.1), (0.045, 0.14), (0.06, 0.17)], LEATHER, 8, wobble=0.04, seed=2)
    bag.data.transform(Matrix.Translation((-0.07, 0.05, 0.075)) @ Euler((0.25, 1.15, 0)).to_matrix().to_4x4())
    o.append(bag)
    tie = torus(0.047, 0.01, LEATHER_DK, (0, 0, 0.142), seg=8, sseg=4)
    tie.data.transform(Matrix.Translation((-0.07, 0.05, 0.075)) @ Euler((0.25, 1.15, 0)).to_matrix().to_4x4())
    o.append(tie)
    o.append(lathe([(0.14, 0), (0.1, 0.028), (0.04, 0.07), (0, 0.082)], TINT, 9, (0.065, -0.04, 0), wobble=0.1, seed=6))
    o.append(lathe([(0.143, 0), (0.12, 0.012)], TINT_DK, 9, (0.065, -0.04, 0), wobble=0.1, seed=6))
    for x, y, z, r in ((0.02, -0.09, 0.1, 0.02), (0.13, 0.0, 0.14, 0.024), (0.19, -0.1, 0.07, 0.016),
                       (0.085, -0.06, 0.19, 0.016)):                                  # centelhas
        o.append(gem(r, r * 1.5, TINT_LT, (x, y, z), seg=4, top=1.3))
    return o


def build_fang():
    o = []
    pts = [(-0.085, 0, 0.26), (-0.07, 0, 0.2), (-0.035, 0, 0.13), (0.02, 0, 0.065), (0.085, 0, 0.02), (0.14, 0, 0.0)]
    o.append(tube(pts, [0.05, 0.055, 0.047, 0.034, 0.018, 0.0], TINT, 7, flat=0.8))
    o.append(tube([(-0.09, 0, 0.285), (-0.085, 0, 0.255), (-0.078, 0, 0.225)], [0.04, 0.058, 0.058], TINT_DK, 7, flat=0.8))
    o.append(tube([(-0.05, -0.036, 0.185), (-0.02, -0.032, 0.125), (0.02, -0.024, 0.08)], [0.0, 0.012, 0.0], TINT_LT, 4,
                  flat=0.5))
    return o


def build_badge():
    o = []
    for side in (-1, 1):                                                              # fita
        o.append(prism([(side * 0.005, 0.0), (side * 0.07, 0.0), (side * 0.11, 0.13), (side * 0.045, 0.13)]
                       if side > 0 else
                       [(-0.005, 0.0), (-0.045, 0.13), (-0.11, 0.13), (-0.07, 0.0)], 0.012, RED if side > 0 else RED_DK,
                       (0, 0.004 * side, 0.2)))
    o.append(lathe([(0.105, -0.012), (0.115, 0), (0.105, 0.012)], TINT, 10, (0, 0, 0.115), (PI / 2, 0, 0)))
    o.append(lathe([(0.088, 0), (0.08, 0.008)], TINT_DK, 10, (0, -0.012, 0.115), (PI / 2, 0, 0)))
    o.append(prism(star(0.07, 0.03), 0.012, TINT_LT, (0, -0.024, 0.115)))
    o.append(torus(0.02, 0.007, GOLD_DK, (0, 0, 0.228), (PI / 2, 0, 0), 8, 4))
    return o


# nome do arquivo -> (construtor, inclinação, giro)
MODELS = {
    "potion": (build_potion, 0.0, 0.0),
    "ring": (build_ring, 0.0, 0.0),
    "amulet": (build_amulet, 0.0, 0.0),
    "orb": (build_orb, 0.0, 0.0),
    "quiver": (build_quiver, 0.35, 0.0),
    "seed_bag": (build_seed_bag, 0.0, 0.0),
    "carrot": (build_carrot, 0.75, 0.0),
    "wheat": (build_wheat, 0.0, 0.0),
    "tomato": (build_tomato, 0.0, 0.0),
    "pepper": (build_pepper, 0.0, 0.0),
    "mint": (build_mint, 0.2, 0.0),
    "pumpkin": (build_pumpkin, 0.0, 0.0),
    "bread": (build_bread, 0.0, 0.35),
    "bowl": (build_bowl, 0.0, 0.0),
    "cup": (build_cup, 0.0, 0.0),
    "pie": (build_pie, 0.0, 0.0),
    "feast": (build_feast, 0.0, 0.0),
    "gel": (build_gel, 0.0, 0.0),
    "ear": (build_ear, 0.0, 0.0),
    "bone": (build_bone, 0.0, 0.0),
    "crown": (build_crown, 0.0, 0.0),
    "ore": (build_ore, 0.0, 0.0),
    "crystal": (build_crystal, 0.0, 0.0),
    "core": (build_core, 0.0, 0.0),
    "drop": (build_drop, 0.0, 0.0),
    "totem": (build_totem, 0.0, 0.0),
    "gland": (build_gland, 0.0, 0.0),
    "dust": (build_dust, 0.0, 0.0),
    "fang": (build_fang, 0.0, 0.0),
    "badge": (build_badge, 0.0, 0.0),
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    only = [a for a in sys.argv[sys.argv.index("--") + 2:]] if "--" in sys.argv else []
    for name, (build, tilt, turn) in MODELS.items():
        if only and name not in only:
            continue
        export(name, build(), tilt, turn)
    print("PRONTO", len(MODELS), "modelos em", OUT, flush=True)


main()
