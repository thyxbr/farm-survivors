"""Peças da interface "grimório" (livro aberto e abas de marcador) modeladas no Blender e renderizadas
de frente em PNG com fundo transparente. Ver docs/INTERFACE_GRIMORIO.md.

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


book()
tab("on", paper("paper_tab", False))
tab("off", cloth("ribbon", (0.3, 0.04, 0.03), (0.14, 0.02, 0.015), 0.6))
print("UI_KIT_OK")
