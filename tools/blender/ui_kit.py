"""Peças de interface (moldura, brasão, botão, espaço de item) modeladas como metal e renderizadas
de frente em PNG com fundo transparente. TESTE descartável.

  blender --background --factory-startup --python tools/blender/ui_kit.py -- <pasta de saída>
"""
import math
import sys

import bpy

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "assets/ui"
PPU = 128  # pixels por unidade


# ------------------------------------------------------------------ cena
def reset():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for c in list(bpy.data.curves):
        bpy.data.curves.remove(c)
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)


def setup(w_units, h_units):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 96
    try:
        sc.cycles.use_denoising = True
    except Exception:
        pass
    sc.render.film_transparent = True
    sc.render.resolution_x = int(round(w_units * PPU))
    sc.render.resolution_y = int(round(h_units * PPU))
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    cam_d = bpy.data.cameras.new("cam")
    cam_d.type = "ORTHO"
    cam_d.ortho_scale = max(w_units, h_units)
    cam = bpy.data.objects.new("cam", cam_d)
    cam.location = (0, 0, 5)
    sc.collection.objects.link(cam)
    sc.camera = cam
    # luz principal de cima-esquerda, preenchimento frio de baixo-direita
    sun_d = bpy.data.lights.new("sun", "SUN")
    sun_d.energy = 2.3
    sun_d.angle = math.radians(12)
    sun = bpy.data.objects.new("sun", sun_d)
    sun.rotation_euler = (math.radians(48), 0, math.radians(38))
    sc.collection.objects.link(sun)
    fill_d = bpy.data.lights.new("fill", "SUN")
    fill_d.energy = 0.7
    fill_d.color = (0.55, 0.7, 1.0)
    fill_d.angle = math.radians(30)
    fill = bpy.data.objects.new("fill", fill_d)
    fill.rotation_euler = (math.radians(60), 0, math.radians(215))
    sc.collection.objects.link(fill)
    world()


def world():
    w = bpy.data.worlds.get("ui") or bpy.data.worlds.new("ui")
    bpy.context.scene.world = w
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    tc = nt.nodes.new("ShaderNodeTexCoord")
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    dot.inputs[1].default_value = (-0.45, 0.55, 0.7)
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.15
    ramp.color_ramp.elements[0].color = (0.02, 0.025, 0.04, 1)
    ramp.color_ramp.elements[1].position = 0.95
    ramp.color_ramp.elements[1].color = (0.5, 0.55, 0.66, 1)
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs[1].default_value = 1.0
    out = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(tc.outputs["Generated"], dot.inputs[0])
    nt.links.new(dot.outputs["Value"], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], bg.inputs[0])
    nt.links.new(bg.outputs[0], out.inputs[0])


# ------------------------------------------------------------------ materiais
def metal(name, base, dark, metallic=0.9, rough=0.42):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Metallic"].default_value = metallic
    tc = nt.nodes.new("ShaderNodeTexCoord")
    big = nt.nodes.new("ShaderNodeTexNoise")
    big.inputs["Scale"].default_value = 2.5
    big.inputs["Detail"].default_value = 6
    fine = nt.nodes.new("ShaderNodeTexNoise")
    fine.inputs["Scale"].default_value = 55
    fine.inputs["Detail"].default_value = 4
    nt.links.new(tc.outputs["Object"], big.inputs["Vector"])
    nt.links.new(tc.outputs["Object"], fine.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (*dark, 1)
    ramp.color_ramp.elements[1].position = 0.7
    ramp.color_ramp.elements[1].color = (*base, 1)
    nt.links.new(big.outputs["Fac"], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], b.inputs["Base Color"])
    rr = nt.nodes.new("ShaderNodeMapRange")
    rr.inputs["To Min"].default_value = rough - 0.1
    rr.inputs["To Max"].default_value = rough + 0.18
    nt.links.new(fine.outputs["Fac"], rr.inputs["Value"])
    nt.links.new(rr.outputs[0], b.inputs["Roughness"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.12
    bump.inputs["Distance"].default_value = 0.02
    nt.links.new(fine.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs[0], b.inputs["Normal"])
    return m


def flat(name, color, alpha=1.0):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs[0].default_value = (*color, 1)
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    mix.inputs[0].default_value = alpha
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs[0])
    return m


def enamel(name, color):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Metallic"].default_value = 0.25
    b.inputs["Roughness"].default_value = 0.3
    return m


def gem(name, color):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Metallic"].default_value = 0.6
    b.inputs["Roughness"].default_value = 0.12
    b.inputs["Emission Color"].default_value = (*color, 1)
    b.inputs["Emission Strength"].default_value = 0.6
    return m


STEEL = lambda: metal("steel", (0.2, 0.235, 0.32), (0.08, 0.09, 0.13))
STEEL_HI = lambda: metal("steel_hi", (0.42, 0.47, 0.6), (0.2, 0.23, 0.31), 0.95, 0.32)
STEEL_LO = lambda: metal("steel_lo", (0.075, 0.085, 0.12), (0.035, 0.04, 0.06), 0.8, 0.55)


# ------------------------------------------------------------------ formas
def qb(p0, p1, p2, n=10):
    """Curva quadrática amostrada (sem o último ponto, para encadear)."""
    pts = []
    for i in range(n):
        t = i / n
        a = (1 - t) ** 2
        b = 2 * (1 - t) * t
        c = t * t
        pts.append((a * p0[0] + b * p1[0] + c * p2[0], a * p0[1] + b * p1[1] + c * p2[1]))
    return pts


def rect(hw, hh, cx=0.0, cy=0.0):
    return [(cx - hw, cy - hh), (cx + hw, cy - hh), (cx + hw, cy + hh), (cx - hw, cy + hh)]


def xf(pts, sx=1.0, sy=1.0, ox=0.0, oy=0.0, rot=0.0, scale=1.0, pivot=(0.0, 0.0)):
    out = []
    c, s = math.cos(rot), math.sin(rot)
    for x, y in pts:
        x = pivot[0] + (x - pivot[0]) * scale
        y = pivot[1] + (y - pivot[1]) * scale
        x, y = x * c - y * s, x * s + y * c
        out.append((ox + x * sx, oy + y * sy))
    return out


def shape(name, loops, mat, z=0.0, height=0.04, bevel=0.012):
    """Chapa: contornos 2D (o 1º é o de fora, os outros são furos), com altura e chanfro."""
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "2D"
    cu.fill_mode = "BOTH"
    cu.extrude = max(height * 0.5 - bevel, 0.0)
    cu.bevel_depth = bevel
    cu.bevel_resolution = 3
    cu.offset = -bevel
    for pts in loops:
        sp = cu.splines.new("POLY")
        sp.points.add(len(pts) - 1)
        for i, (x, y) in enumerate(pts):
            sp.points[i].co = (x, y, 0, 1)
        sp.use_cyclic_u = True
    ob = bpy.data.objects.new(name, cu)
    ob.location = (0, 0, z + height * 0.5)
    ob.data.materials.append(mat)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def pyramid(name, x, y, r, h, mat, z=0.0, rot=0.0, sides=4):
    bpy.ops.mesh.primitive_cone_add(vertices=sides, radius1=r, radius2=r * 0.35, depth=h,
                                    location=(x, y, z + h * 0.5), rotation=(0, 0, rot))
    ob = bpy.context.active_object
    ob.name = name
    ob.data.materials.append(mat)
    return ob


def render(name):
    bpy.context.scene.render.filepath = f"{OUT}/{name}.png"
    bpy.ops.render.render(write_still=True)


# ------------------------------------------------------------------ canto ornamentado
def bracket():
    """Cantoneira (canto na origem, braços para +x e +y)."""
    o = (-0.07, -0.07)
    t1 = (0.86, 0.07)
    t2 = (0.07, 0.86)
    pts = qb(o, (0.42, -0.11), t1)
    pts += qb(t1, (0.5, 0.2), (0.3, 0.25))
    pts += qb((0.3, 0.25), (0.25, 0.25), (0.25, 0.3), 5)
    pts += qb((0.25, 0.3), (0.2, 0.5), t2)
    pts += qb(t2, (-0.11, 0.42), o)
    return pts


def hook():
    """Espinho que sai do canto para fora, na diagonal."""
    tip = (-0.33, -0.33)
    pts = qb((0.16, -0.08), (-0.1, -0.1), tip)
    pts += qb(tip, (-0.1, -0.1), (-0.08, 0.16))
    pts += [(0.05, 0.05)]
    return pts


def corner(cx, cy, sx, sy, size=1.0, z=0.0):
    k = dict(sx=sx, sy=sy, ox=cx, oy=cy, scale=size)
    shape("hook", [xf(hook(), **k)], STEEL_LO(), z + 0.0, 0.05, 0.02)
    shape("bracket", [xf(bracket(), **k)], STEEL(), z + 0.03, 0.07, 0.025)
    inner = xf(bracket(), pivot=(0.16, 0.16), scale=0.62)
    shape("bracket2", [xf(inner, **k)], STEEL_HI(), z + 0.09, 0.04, 0.016)
    bx, by = cx + 0.15 * size * sx, cy + 0.15 * size * sy
    pyramid("boss", bx, by, 0.1 * size, 0.07, STEEL_HI(), z + 0.12)
    pyramid("gem", bx, by, 0.045 * size, 0.05, gem("gem", (0.1, 0.35, 1.0)), z + 0.17)


# ------------------------------------------------------------------ peças
def window():
    """Moldura de janela 9 fatias: 512 px, cantos de 176 px."""
    reset()
    setup(4, 4)
    h = 1.5
    shape("back", [rect(h - 0.06, h - 0.06)], flat("back", (0.004, 0.0045, 0.008), 0.97), -0.02, 0.01, 0.0)
    shape("base", [rect(h, h), rect(h - 0.2, h - 0.2)], STEEL_LO(), 0.0, 0.03, 0.012)
    shape("rail", [rect(h - 0.02, h - 0.02), rect(h - 0.1, h - 0.1)], STEEL(), 0.02, 0.06, 0.028)
    shape("bead", [rect(h - 0.145, h - 0.145), rect(h - 0.18, h - 0.18)], STEEL_HI(), 0.02, 0.035, 0.014)
    for sx in (-1, 1):
        for sy in (-1, 1):
            corner(-sx * (h - 0.01), -sy * (h - 0.01), sx, sy)
    render("window")


def inset():
    """Painel interno 9 fatias: 128 px, cantos de 20 px."""
    reset()
    setup(1, 1)
    h = 0.47
    shape("back", [rect(h - 0.01, h - 0.01)], flat("back2", (0.009, 0.0105, 0.017), 0.9), -0.02, 0.01, 0.0)
    shape("rail", [rect(h, h), rect(h - 0.035, h - 0.035)], STEEL_LO(), 0.0, 0.03, 0.012)
    shape("bead", [rect(h - 0.012, h - 0.012), rect(h - 0.024, h - 0.024)], STEEL(), 0.02, 0.016, 0.006)
    for sx in (-1, 1):
        for sy in (-1, 1):
            pyramid("stud", sx * (h - 0.018), sy * (h - 0.018), 0.035, 0.03, STEEL_HI(), 0.02)
    render("inset")


def slot():
    """Espaço de item: 96 px."""
    reset()
    setup(0.75, 0.75)
    h = 0.355
    shape("back", [rect(h - 0.01, h - 0.01)], flat("back3", (0.002, 0.0024, 0.004), 0.95), -0.02, 0.01, 0.0)
    shape("rail", [rect(h, h), rect(h - 0.05, h - 0.05)], STEEL_LO(), 0.0, 0.03, 0.012)
    shape("bead", [rect(h - 0.012, h - 0.012), rect(h - 0.032, h - 0.032)], STEEL(), 0.02, 0.022, 0.009)
    render("slot")


def hexa(hw, hh, point):
    return [(-hw, 0), (-hw + point, hh), (hw - point, hh), (hw, 0), (hw - point, -hh), (-hw + point, -hh)]


def button(name, color):
    """Botão 3 fatias: 256 x 48 px, pontas de 40 px."""
    reset()
    setup(2, 0.375)
    shape("base", [hexa(0.97, 0.168, 0.13)], STEEL(), 0.0, 0.05, 0.02)
    shape("face", [hexa(0.925, 0.13, 0.1)], enamel("en_" + name, color), 0.04, 0.035, 0.016)
    for sx in (-1, 1):
        pyramid("tip", sx * 0.9, 0, 0.035, 0.03, STEEL_HI(), 0.075)
    render("button_" + name)


def blade(length, width, ang, curl=0.25):
    """Lâmina de asa: sai da origem para +x, curva para cima, termina em ponta."""
    tip = (length, length * curl)
    pts = qb((0, -width * 0.5), (length * 0.55, -width * 0.9), tip)
    pts += qb(tip, (length * 0.5, width * 0.6), (0, width * 0.5))
    return xf(pts, rot=ang)


def crest():
    """Brasão do topo da janela: escudo com gema e asas de lâminas. 448 x 192 px."""
    reset()
    setup(3.5, 1.5)
    for sx in (-1, 1):
        for i, (ln, wd, ang) in enumerate([(1.45, 0.2, 0.02), (1.15, 0.18, -0.2), (0.85, 0.16, -0.44)]):
            pts = xf(blade(ln, wd, ang), sx=sx, ox=sx * 0.18, oy=0.05)
            shape("wing", [pts], STEEL() if i else STEEL_HI(), 0.0 + 0.02 * (2 - i), 0.05, 0.022)
    # coroa de três pontas
    for x, hgt in [(-0.17, 0.2), (0.0, 0.3), (0.17, 0.2)]:
        shape("spike", [[(x - 0.07, 0.36), (x + 0.07, 0.36), (x, 0.36 + hgt)]], STEEL_HI(), 0.02, 0.05, 0.02)
    kite = [(-0.31, 0.4), (0.0, 0.46), (0.31, 0.4)]
    kite += qb((0.31, 0.4), (0.33, -0.2), (0.0, -0.62))
    kite += qb((0.0, -0.62), (-0.33, -0.2), (-0.31, 0.4))
    shape("shield", [kite], STEEL(), 0.06, 0.08, 0.03)
    shape("field", [xf(kite, pivot=(0, 0.0), scale=0.74)], enamel("field", (0.012, 0.03, 0.1)), 0.13, 0.04, 0.018)
    pyramid("boss", 0, 0.02, 0.13, 0.06, STEEL_HI(), 0.16)
    pyramid("gem", 0, 0.02, 0.07, 0.06, gem("gem", (0.1, 0.35, 1.0)), 0.21)
    render("crest")


# ------------------------------------------------------------------ grimório
def rrect(x0, y0, x1, y1, r, n=6):
    pts = []
    for cx, cy, a0 in [(x1 - r, y1 - r, 0), (x0 + r, y1 - r, 90), (x0 + r, y0 + r, 180), (x1 - r, y0 + r, 270)]:
        for i in range(n + 1):
            a = math.radians(a0 + 90 * i / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def paper(name="paper", shade=True):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.95
    tc = nt.nodes.new("ShaderNodeTexCoord")
    stain = nt.nodes.new("ShaderNodeTexNoise")
    stain.inputs["Scale"].default_value = 0.9
    stain.inputs["Detail"].default_value = 8
    stain.inputs["Roughness"].default_value = 0.65
    nt.links.new(tc.outputs["Object"], stain.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.3
    ramp.color_ramp.elements[0].color = (0.5, 0.34, 0.15, 1)
    ramp.color_ramp.elements[1].position = 0.68
    ramp.color_ramp.elements[1].color = (0.78, 0.6, 0.33, 1)
    nt.links.new(stain.outputs["Fac"], ramp.inputs[0])
    col = ramp.outputs[0]
    if shade:
        # escurece junto da lombada e nas bordas da página
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(tc.outputs["Object"], sep.inputs[0])
        fac = None
        for axis, lo, hi, a, bb in [("X", 0.0, 0.75, 0.42, 1.0), ("X", 4.3, 5.1, 1.0, 0.78), ("Y", 2.2, 2.85, 1.0, 0.8)]:
            ab = nt.nodes.new("ShaderNodeMath")
            ab.operation = "ABSOLUTE"
            nt.links.new(sep.outputs[axis], ab.inputs[0])
            mr = nt.nodes.new("ShaderNodeMapRange")
            mr.interpolation_type = "SMOOTHSTEP"
            mr.inputs["From Min"].default_value = lo
            mr.inputs["From Max"].default_value = hi
            mr.inputs["To Min"].default_value = a
            mr.inputs["To Max"].default_value = bb
            nt.links.new(ab.outputs[0], mr.inputs["Value"])
            if fac is None:
                fac = mr.outputs[0]
            else:
                mul = nt.nodes.new("ShaderNodeMath")
                mul.operation = "MULTIPLY"
                nt.links.new(fac, mul.inputs[0])
                nt.links.new(mr.outputs[0], mul.inputs[1])
                fac = mul.outputs[0]
        mix = nt.nodes.new("ShaderNodeVectorMath")
        mix.operation = "SCALE"
        nt.links.new(col, mix.inputs[0])
        nt.links.new(fac, mix.inputs["Scale"])
        col = mix.outputs[0]
    nt.links.new(col, b.inputs["Base Color"])
    nt.links.new(col, b.inputs["Emission Color"])
    b.inputs["Emission Strength"].default_value = 0.45
    fine = nt.nodes.new("ShaderNodeTexNoise")
    fine.inputs["Scale"].default_value = 60
    nt.links.new(tc.outputs["Object"], fine.inputs["Vector"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.08
    nt.links.new(fine.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs[0], b.inputs["Normal"])
    return m


def cloth(name, base, dark, rough=0.7):
    m = metal(name, base, dark, 0.0, rough)
    return m


def book():
    """Livro aberto: capa de couro, cantoneiras de latão, duas páginas de pergaminho. 1408 x 800 px."""
    reset()
    setup(11, 6.25)
    leather = cloth("leather", (0.11, 0.035, 0.022), (0.04, 0.014, 0.01), 0.55)
    brass = metal("brass", (0.62, 0.4, 0.12), (0.3, 0.17, 0.05), 0.95, 0.35)
    shape("cover", [rrect(-5.42, -3.05, 5.42, 3.05, 0.14)], leather, 0.0, 0.07, 0.03)
    shape("cover_line", [rrect(-5.34, -2.97, 5.34, 2.97, 0.1), rrect(-5.3, -2.93, 5.3, 2.93, 0.08)], brass, 0.06, 0.02, 0.008)
    for sx in (-1, 1):
        for sy in (-1, 1):
            tri = [(0, 0), (0.62, 0), (0.5, 0.12), (0.12, 0.5), (0, 0.62)]
            shape("corner", [xf(tri, sx=-sx, sy=-sy, ox=sx * 5.44, oy=sy * 3.07)], brass, 0.06, 0.035, 0.014)
            pyramid("stud", sx * 5.3, sy * 2.93, 0.05, 0.03, brass, 0.09, sides=8)
        # maço de folhas e a página de cima
        for i in range(3):
            x1 = 5.2 - i * 0.035
            hy = 2.9 - i * 0.02
            pts = rrect(0.0, -hy, x1, hy, 0.04, 3)
            shape("leaf", [xf(pts, sx=sx)], paper("paper_edge", False), 0.1 + i * 0.012, 0.012, 0.004)
        shape("page", [xf(rrect(0.0, -2.83, 5.09, 2.83, 0.05, 3), sx=sx)], paper(), 0.14, 0.014, 0.005)
    shape("gutter", [rect(0.012, 2.83)], flat("gutter", (0.02, 0.012, 0.006), 0.55), 0.16, 0.004, 0.0)
    render("book")


def tab(name, mat):
    """Aba de marcador que sai do topo da página. 192 x 56 px."""
    reset()
    setup(1.5, 0.4375)
    pts = [(-0.7, -0.2), (0.7, -0.2)] + qb((0.7, -0.2), (0.7, 0.19), (0.58, 0.19), 6) + qb((-0.58, 0.19), (-0.7, 0.19), (-0.7, -0.2), 6)
    shape("tab", [pts], mat, 0.0, 0.03, 0.012)
    render("tab_" + name)


if "--book" in sys.argv:
    book()
    tab("on", paper("paper_tab", False))
    tab("off", cloth("ribbon", (0.3, 0.04, 0.03), (0.14, 0.02, 0.015), 0.6))
    print("UI_KIT_OK")
    sys.exit(0)

window()
inset()
slot()
button("normal", (0.018, 0.05, 0.16))
button("hover", (0.04, 0.1, 0.32))
button("pressed", (0.01, 0.026, 0.085))
button("disabled", (0.02, 0.022, 0.028))
crest()
print("UI_KIT_OK")
