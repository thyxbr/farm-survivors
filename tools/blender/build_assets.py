# Gera todos os modelos low-poly do jogo e exporta como GLB para assets/models.
# Uso dentro do Blender:  exec(open(r"C:/Games/godot-3d/tools/blender/build_assets.py").read())
# Cada asset é montado numa cena separada ("RPG_Assets"), exportado e depois apagado,
# então a cena padrão do usuário não é tocada.
import bpy, bmesh, math, os, random
from mathutils import Matrix, Euler, Vector

# Saída relativa ao próprio script (funciona em worktrees); via exec() no Blender cai no caminho fixo.
try:
    OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models")).replace("\\", "/") + "/"
except NameError:
    OUT = "C:/Games/godot-3d/assets/models/"
PI = math.pi

scn = bpy.context.scene if bpy.app.background else (bpy.data.scenes.get("RPG_Assets") or bpy.data.scenes.new("RPG_Assets"))
coll = scn.collection
exported = []


def mat(name, color, rough=0.8, metal=0.0, emit=None, strength=3.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    b = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    if b is None:
        b = nt.nodes.new("ShaderNodeBsdfPrincipled")
        out = next((n for n in nt.nodes if n.type == 'OUTPUT_MATERIAL'), None) or nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(b.outputs[0], out.inputs[0])
    b.inputs["Base Color"].default_value = (*color, 1)
    m.diffuse_color = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = strength
    return m


def clear():
    for o in list(coll.all_objects):
        bpy.data.objects.remove(o, do_unlink=True)


def empty(name, loc, parent=None):
    e = bpy.data.objects.new(name, None)
    coll.objects.link(e)
    if parent is not None:
        e.parent = parent
        e.location = Vector(loc) - _wloc(parent)
    else:
        e.location = loc
    e["wloc"] = list(loc)
    return e


def _wloc(o):
    return Vector(o["wloc"]) if o is not None and "wloc" in o else Vector((0, 0, 0))


def part(name, kind, loc, size, material, rot=(0, 0, 0), parent=None, seg=8, r2=0.5, sub=1, jitter=0.0, smooth=False, seed=1):
    print("PART", name, kind, flush=True)
    bm = bmesh.new()
    if kind == "cube":
        bmesh.ops.create_cube(bm, size=1.0)
    elif kind == "cyl":
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=0.5, radius2=r2, depth=1.0)
    elif kind == "cone":
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=0.5, radius2=0.0, depth=1.0)
    elif kind == "ico":
        bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=0.5)
    elif kind == "sphere":
        bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=max(4, seg // 2), radius=0.5)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0001)
    if jitter > 0:
        rnd = random.Random(seed)
        for v in bm.verts:
            v.co += Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))) * jitter
    rel = Vector(loc) - _wloc(parent)
    M = Matrix.Translation(rel) @ Euler(rot).to_matrix().to_4x4() @ Matrix.Diagonal((*size, 1))
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.validate()
    for p in me.polygons:
        p.use_smooth = smooth
    me.materials.append(material)
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    if parent is not None:
        ob.parent = parent
    return ob


def export(fname):
    print("EXPORT", fname, flush=True)
    vl = scn.view_layers[0]
    vl.update()
    wins = bpy.context.window_manager.windows
    kw = {"scene": scn, "view_layer": vl}
    if len(wins) > 0:
        kw["window"] = wins[0]
    with bpy.context.temp_override(**kw):
        for o in scn.objects:
            o.select_set(True, view_layer=vl)
        bpy.ops.export_scene.gltf(filepath=OUT + fname + ".glb", export_format='GLB', use_selection=True,
                                  export_apply=True, export_yup=True, export_animations=False,
                                  export_cameras=False, export_lights=False)
    exported.append(fname)
    clear()


# ---------- materiais compartilhados ----------
skin = mat("m_skin", (0.85, 0.6, 0.45))
leather = mat("m_leather", (0.33, 0.19, 0.09))
wood = mat("m_wood", (0.4, 0.25, 0.12))
wood_dark = mat("m_wood_dark", (0.22, 0.13, 0.06))
steel = mat("m_steel", (0.55, 0.58, 0.65), 0.35, 0.85)
dark = mat("m_dark", (0.1, 0.1, 0.12), 0.6)
red = mat("m_red", (0.55, 0.05, 0.05), 0.7)
gold = mat("m_gold", (0.95, 0.7, 0.2), 0.3, 1.0)
blade_m = mat("m_blade", (0.85, 0.87, 0.9), 0.2, 1.0)
stone = mat("m_stone", (0.45, 0.45, 0.47), 0.95)
stone_dark = mat("m_stone_dark", (0.3, 0.3, 0.32), 0.95)
moss = mat("m_moss", (0.2, 0.35, 0.12), 0.95)
white = mat("m_white", (0.95, 0.95, 0.95), 0.5)
black = mat("m_black", (0.02, 0.02, 0.02), 0.3)
leaf = mat("m_leaf", (0.18, 0.45, 0.12), 0.9)
pine = mat("m_pine", (0.08, 0.3, 0.12), 0.9)
plaster = mat("m_plaster", (0.9, 0.85, 0.72), 0.95)
roof_m = mat("m_roof", (0.55, 0.16, 0.1), 0.85)
glass = mat("m_glass", (0.2, 0.35, 0.5), 0.2, 0.0, emit=(0.9, 0.7, 0.3), strength=0.6)
water = mat("m_water", (0.05, 0.2, 0.35), 0.1)
fire = mat("m_fire", (1.0, 0.45, 0.05), 0.5, 0.0, emit=(1.0, 0.45, 0.05), strength=8.0)
lantern = mat("m_lantern", (1.0, 0.8, 0.4), 0.5, 0.0, emit=(1.0, 0.75, 0.35), strength=6.0)
canvas = mat("m_canvas", (0.55, 0.45, 0.3), 0.95)


def build_slime():
    goo = mat("m_slime", (0.25, 0.75, 0.3), 0.15)
    root = empty("Slime", (0, 0, 0))
    body = empty("Body", (0, 0, 0), root)
    part("BodyMesh", "ico", (0, 0, 0.32), (0.9, 0.9, 0.68), goo, sub=2, parent=body)
    part("Base", "cyl", (0, 0, 0.06), (0.86, 0.86, 0.12), goo, seg=12, parent=body)
    for s, x in (("L", 0.16), ("R", -0.16)):
        part("Eye" + s, "ico", (x, -0.36, 0.42), (0.16, 0.08, 0.2), white, parent=body)
        part("Pupil" + s, "ico", (x, -0.4, 0.42), (0.08, 0.05, 0.11), black, parent=body)
    part("Shine", "ico", (0.2, -0.15, 0.62), (0.14, 0.1, 0.06), white, parent=body)
    export("slime")


# ================= ALDEÕES =================
# ================= CENÁRIO =================
def build_tree_pine():
    bark = mat("m_bark", (0.28, 0.17, 0.08), 0.95)
    part("Trunk", "cyl", (0, 0, 0.75), (0.38, 0.38, 1.5), bark, seg=6)
    part("Leaves1", "cone", (0, 0, 2.0), (2.6, 2.6, 2.0), pine, seg=7)
    part("Leaves2", "cone", (0, 0, 3.05), (2.0, 2.0, 1.8), pine, seg=7)
    part("Leaves3", "cone", (0, 0, 4.0), (1.3, 1.3, 1.6), pine, seg=7)
    export("tree_pine")


def build_tree_oak():
    bark = mat("m_bark", (0.28, 0.17, 0.08), 0.95)
    part("Trunk", "cyl", (0, 0, 1.0), (0.5, 0.5, 2.0), bark, r2=0.35, seg=6)
    part("Branch", "cyl", (0.35, 0, 1.9), (0.18, 0.18, 0.9), bark, rot=(0, 0.7, 0), seg=5)
    part("Crown1", "ico", (0, 0, 3.0), (3.0, 3.0, 2.5), leaf, jitter=0.12, seed=3)
    part("Crown2", "ico", (0.9, 0.4, 2.6), (1.9, 1.9, 1.6), leaf, jitter=0.1, seed=5)
    part("Crown3", "ico", (-0.8, -0.5, 2.7), (2.0, 2.0, 1.7), leaf, jitter=0.1, seed=7)
    export("tree_oak")


def build_rock():
    part("Rock", "ico", (0, 0, 0.3), (1.5, 1.2, 1.0), stone, jitter=0.12, seed=11)
    part("Moss", "ico", (0.15, 0.1, 0.72), (0.8, 0.6, 0.18), moss, jitter=0.05, seed=12)
    export("rock")


def hull(name, verts, material):
    """Malha convexa a partir de pontos (empenas, prismas) — normais saem certas sozinhas."""
    bm = bmesh.new()
    vs = [bm.verts.new(v) for v in verts]
    bmesh.ops.convex_hull(bm, input=vs)
    bmesh.ops.dissolve_limit(bm, angle_limit=0.01, verts=bm.verts, edges=bm.edges)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(material)
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    return ob


def join_all(name):
    """Junta todas as malhas da cena num objeto só (um MeshInstance3D no Godot, uma superfície por material)."""
    objs = [o for o in coll.all_objects if o.type == 'MESH']
    with bpy.context.temp_override(active_object=objs[0], object=objs[0], selected_objects=objs,
                                   selected_editable_objects=objs):
        bpy.ops.object.join()
    objs[0].name = name
    objs[0].data.name = name


def build_house():
    # Chalé em enxaimel: pegada 5 x 4 m (paredes), frente em -Y, cumeeira ao longo de X.
    h_plaster = mat("h_plaster", (0.86, 0.77, 0.60), 0.95)
    h_timber = mat("h_timber", (0.24, 0.14, 0.07), 0.9)
    h_door = mat("h_door", (0.46, 0.28, 0.13), 0.85)
    h_stone = mat("h_stone", (0.52, 0.50, 0.47), 0.95)
    h_stone_dk = mat("h_stone_dark", (0.33, 0.32, 0.31), 0.95)
    h_roof = mat("h_roof", (0.48, 0.15, 0.08), 0.85)
    h_ridge = mat("h_roof_dark", (0.30, 0.09, 0.05), 0.85)
    h_shutter = mat("h_shutter", (0.17, 0.36, 0.20), 0.8)
    h_glass = mat("h_glass", (0.20, 0.33, 0.45), 0.2, 0.0, emit=(0.95, 0.72, 0.35), strength=0.5)
    h_iron = mat("h_iron", (0.10, 0.10, 0.11), 0.6, 0.6)
    h_leaf = mat("h_leaf", (0.22, 0.48, 0.15), 0.9)
    h_flower = mat("h_flower", (0.88, 0.25, 0.30), 0.7)
    h_flower2 = mat("h_flower2", (0.98, 0.80, 0.25), 0.7)
    h_lamp = mat("h_lamp", (1.0, 0.8, 0.4), 0.5, 0.0, emit=(1.0, 0.75, 0.35), strength=5.0)

    W, D = 2.5, 2.0              # meia largura (X) e meia profundidade (Y) das paredes
    Z0, ZT = 0.3, 3.1            # piso (topo da fundação) e topo das paredes
    th = math.radians(40)        # caimento do telhado
    cs, sn, tn = math.cos(th), math.sin(th), math.tan(th)
    ZR = ZT + 0.02 + D * tn           # face de baixo do telhado na linha da cumeeira
    n = [0]

    def nm(p):
        n[0] += 1
        return "%s_%d" % (p, n[0])

    def fp(prefix, face, u, out, z, su, so, sz, m, tilt=0.0, kind="cube"):
        """Peça presa a uma fachada. u = lateral na fachada, out = afastamento da parede.
        tilt > 0 faz o eixo longo (su) subir no sentido +u."""
        if face == "-y":
            loc, size, rot = (u, -D - out, z), (su, so, sz), (0, -tilt, 0)
        elif face == "+y":
            loc, size, rot = (-u, D + out, z), (su, so, sz), (0, tilt, 0)
        elif face == "+x":
            loc, size, rot = (W + out, u, z), (so, su, sz), (tilt, 0, 0)
        else:
            loc, size, rot = (-W - out, -u, z), (so, su, sz), (-tilt, 0, 0)
        return part(nm(prefix), kind, loc, size, m, rot=rot)

    def window(face, u, z, w, h, cross=True, shutters=False, flowers=None):
        fp("WinFrame", face, u, 0.0, z, w + 0.16, 0.08, h + 0.16, h_timber)
        fp("WinGlass", face, u, 0.03, z, w, 0.04, h, h_glass)
        if cross:
            fp("WinBarV", face, u, 0.06, z, 0.05, 0.03, h, h_timber)
            fp("WinBarH", face, u, 0.06, z, w, 0.03, 0.05, h_timber)
        if shutters:
            for s in (-1, 1):
                fp("Shutter", face, u + s * (w / 2 + 0.1 + w / 4), 0.04, z, w / 2, 0.05, h + 0.08, h_shutter)
        if flowers:
            bz = z - h / 2 - 0.2
            fp("FlowerBox", face, u, 0.13, bz, w + 0.2, 0.26, 0.2, h_door)
            fp("Leaves", face, u, 0.13, bz + 0.13, w + 0.1, 0.24, 0.16, h_leaf, kind="ico")
            fp("Flowers", face, u + 0.05, 0.13, bz + 0.2, w - 0.15, 0.2, 0.13, flowers, kind="ico")

    # ---- base e paredes
    part("Foundation", "cube", (0, 0, 0.16), (2 * W + 0.3, 2 * D + 0.3, 0.32), h_stone_dk)
    part("Walls", "cube", (0, 0, (Z0 + ZT) / 2), (2 * W, 2 * D, ZT - Z0), h_plaster)
    for sx in (-1, 1):
        g = W * sx
        gi = (W - 0.2) * sx
        hull("Gable", [(g, -D, ZT), (g, D, ZT), (g, 0, ZT + D * tn - 0.02),
                       (gi, -D, ZT), (gi, D, ZT), (gi, 0, ZT + D * tn - 0.02)], h_plaster)

    # ---- enxaimel (madeira aparente)
    hpost = ZT - Z0
    for x in (-1, 1):
        for y in (-1, 1):
            part(nm("Post"), "cube", (x * (W - 0.04), y * (D - 0.04), Z0 + hpost / 2), (0.24, 0.24, hpost), h_timber)
    for sy in (-1, 1):
        part(nm("SillPlate"), "cube", (0, sy * (D + 0.03), Z0 + 0.08), (2 * W, 0.2, 0.16), h_timber)
        part(nm("TopPlate"), "cube", (0, sy * (D + 0.03), ZT - 0.08), (2 * W + 0.15, 0.22, 0.2), h_timber)
    for sx in (-1, 1):
        part(nm("SillPlate"), "cube", (sx * (W + 0.03), 0, Z0 + 0.08), (0.2, 2 * D, 0.16), h_timber)
        part(nm("TopPlate"), "cube", (sx * (W + 0.03), 0, ZT - 0.08), (0.22, 2 * D + 0.1, 0.2), h_timber)
    rail_z = 1.15
    for s in (-1, 1):
        fp("Rail", "-y", s * 1.49, 0.03, rail_z, 1.7, 0.12, 0.14, h_timber)
        fp("Brace", "-y", s * 1.83, 0.03, 0.75, 1.1, 0.1, 0.14, h_timber, tilt=-s * math.radians(30.5))
        fp("Brace", "+y", s * 1.83, 0.03, 0.75, 1.1, 0.1, 0.14, h_timber, tilt=-s * math.radians(30.5))
    fp("Rail", "+y", 0, 0.03, rail_z, 2 * W, 0.12, 0.14, h_timber)
    for face in ("-x", "+x"):
        fp("Rail", face, 0, 0.03, rail_z, 2 * D, 0.12, 0.14, h_timber)
        for s in (-1, 1):   # escoras da empena, paralelas ao telhado
            fp("GableStrut", face, s * 1.0, 0.03, ZT + 0.43, 1.28, 0.1, 0.13, h_timber, tilt=-s * math.radians(38.7))

    # ---- porta, alpendre e lampião
    dz = Z0 + 0.975
    fp("Door", "-y", 0, 0.0, dz, 1.0, 0.08, 1.95, h_door)
    for s in (-1, 1):
        fp("Jamb", "-y", s * 0.57, 0.03, Z0 + hpost / 2, 0.14, 0.12, hpost - 0.1, h_timber)
    fp("Lintel", "-y", 0, 0.03, Z0 + 2.03, 1.3, 0.12, 0.16, h_timber)
    fp("DoorStrap", "-y", 0, 0.06, 0.8, 0.9, 0.03, 0.07, h_iron)
    fp("DoorStrap", "-y", 0, 0.06, 1.9, 0.9, 0.03, 0.07, h_iron)
    fp("DoorKnob", "-y", 0.32, 0.08, dz, 0.09, 0.07, 0.09, h_iron, kind="ico")
    part("Step", "cube", (0, -D - 0.38, 0.14), (1.5, 0.6, 0.28), h_stone)
    part("Awning", "cube", (0, -D - 0.4, 2.72), (1.7, 0.9, 0.08), h_roof, rot=(0.35, 0, 0))
    for s in (-1, 1):
        part(nm("AwningBracket"), "cube", (s * 0.72, -D - 0.28, 2.48), (0.08, 0.62, 0.08), h_timber, rot=(-0.55, 0, 0))
    fp("LampArm", "-y", 1.05, 0.15, 2.74, 0.06, 0.3, 0.06, h_iron)
    fp("Lamp", "-y", 1.05, 0.28, 2.56, 0.17, 0.17, 0.22, h_lamp)
    fp("LampCap", "-y", 1.05, 0.28, 2.7, 0.24, 0.24, 0.06, h_iron)

    # ---- janelas
    for s, fl in ((-1, h_flower), (1, h_flower2)):
        window("-y", s * 1.45, 1.95, 0.7, 0.8, shutters=True, flowers=fl)
        window("+y", s * 1.4, 1.95, 0.75, 0.75)
    for face in ("-x", "+x"):
        window(face, 0, 1.95, 0.7, 0.75, cross=False)
        window(face, 0, ZT + 0.65, 0.4, 0.4, cross=False)

    # ---- telhado em fiadas (a de cima sobrepõe a de baixo), cumeeira e testeiras
    rows, t = 4, 0.12
    ls = (D + 0.5) / cs                       # comprimento da água (beiral de 0,5 m)
    step = ls / rows
    rx = 2 * W + 0.76                         # beiral de 0,38 m nas empenas

    def slope(side, s, off):
        return (0, side * (s * cs + sn * off), ZR - s * sn + cs * off)

    for side in (-1, 1):
        for i in range(rows):
            off = t / 2 + 0.05 * (rows - 1 - i)
            part(nm("RoofRow"), "cube", slope(side, (i + 0.5) * step, off), (rx, step + 0.12, t), h_roof,
                 rot=(-side * th, 0, 0))
        for sx in (-1, 1):
            p = slope(side, ls / 2, -0.11)
            part(nm("BargeBoard"), "cube", (sx * (W + 0.32), p[1], p[2]), (0.08, ls, 0.2), h_timber,
                 rot=(-side * th, 0, 0))
    top = (t + 0.05 * (rows - 1)) / cs
    part("Ridge", "cube", (0, 0, ZR + top - 0.02), (rx + 0.1, 0.3, 0.3), h_ridge, rot=(PI / 4, 0, 0))

    # ---- chaminé de pedra atravessando a água de trás
    part("Chimney", "cube", (1.5, 1.0, ZT + 1.22), (0.62, 0.62, 2.45), h_stone)
    part("ChimneyCap", "cube", (1.5, 1.0, ZT + 2.48), (0.78, 0.78, 0.12), h_stone_dk)
    part("ChimneyFlue", "cube", (1.5, 1.0, ZT + 2.62), (0.34, 0.34, 0.18), h_stone_dk)

    join_all("House")
    export("house")


def build_fence():
    for x in (-1.0, 1.0):
        part("Post_%d" % x, "cube", (x, 0, 0.5), (0.15, 0.15, 1.0), wood)
    part("RailTop", "cube", (0, 0, 0.75), (2.15, 0.07, 0.12), wood)
    part("RailLow", "cube", (0, 0, 0.38), (2.15, 0.07, 0.12), wood)
    export("fence")


def build_well():
    part("Ring", "cyl", (0, 0, 0.45), (1.8, 1.8, 0.9), stone, seg=10)
    part("Water", "cyl", (0, 0, 0.88), (1.5, 1.5, 0.04), water, seg=10)
    for x in (-0.8, 0.8):
        part("WellPost_%d" % (x * 10), "cube", (x, 0, 1.5), (0.14, 0.14, 1.4), wood)
    part("Axle", "cyl", (0, 0, 1.9), (0.1, 0.1, 1.7), wood_dark, rot=(0, PI / 2, 0), seg=6)
    part("Bucket", "cyl", (0, 0, 1.35), (0.3, 0.3, 0.3), wood_dark, r2=0.6, seg=8)
    part("WellRoof", "cyl", (0, 0, 2.45), (1.2, 2.3, 2.1), roof_m, rot=(0, -PI / 2, 0), seg=3)
    export("well")


def build_ruin_pillar():
    part("PBase", "cube", (0, 0, 0.2), (1.1, 1.1, 0.4), stone_dark)
    part("Column", "cyl", (0, 0, 1.8), (0.75, 0.75, 2.8), stone, seg=8)
    part("Broken", "cube", (0.05, 0, 3.3), (0.8, 0.8, 0.35), stone, rot=(0.25, 0.15, 0.4))
    part("PMoss", "ico", (0.3, -0.3, 0.45), (0.5, 0.4, 0.2), moss, jitter=0.03)
    export("ruin_pillar")


def build_ruin_wall():
    rnd = random.Random(21)
    i = 0
    for row in range(3):
        n = 4 - row
        for k in range(n):
            x = -1.6 + k * 1.05 + row * 0.4 + rnd.uniform(-0.05, 0.05)
            part("Block%d" % i, "cube", (x, 0, 0.35 + row * 0.68), (1.0, 0.8, 0.66), stone if (i % 3) else stone_dark,
                 rot=(0, 0, rnd.uniform(-0.05, 0.05)))
            i += 1
    part("WMoss", "ico", (-1.2, -0.35, 0.3), (0.9, 0.3, 0.35), moss, jitter=0.04)
    export("ruin_wall")


def build_crate():
    part("Crate", "cube", (0, 0, 0.4), (0.8, 0.8, 0.8), wood)
    for z in (0.05, 0.75):
        part("Band%d" % (z * 100), "cube", (0, 0, z), (0.84, 0.84, 0.1), wood_dark)
    export("crate")


def build_barrel():
    part("Barrel", "cyl", (0, 0, 0.5), (0.75, 0.75, 1.0), wood, seg=10)
    for z in (0.15, 0.85):
        part("Hoop%d" % (z * 100), "cyl", (0, 0, z), (0.78, 0.78, 0.07), dark, seg=10)
    export("barrel")


def build_lamp():
    part("LampPost", "cyl", (0, 0, 1.4), (0.14, 0.14, 2.8), wood_dark, seg=6)
    part("LampArm", "cube", (0, -0.25, 2.7), (0.08, 0.55, 0.08), wood_dark)
    part("Lantern", "cube", (0, -0.5, 2.45), (0.24, 0.24, 0.32), lantern)
    part("LanternCap", "cone", (0, -0.5, 2.67), (0.32, 0.32, 0.14), dark, seg=4)
    export("lamp")


def build_campfire():
    for i in range(5):
        a = i / 5 * 2 * PI
        part("Stone%d" % i, "ico", (math.cos(a) * 0.55, math.sin(a) * 0.55, 0.08), (0.3, 0.25, 0.2), stone)
    part("Log1", "cyl", (0, 0, 0.12), (0.16, 0.16, 0.9), wood_dark, rot=(0, PI / 2, 0.5), seg=6)
    part("Log2", "cyl", (0, 0, 0.18), (0.16, 0.16, 0.9), wood_dark, rot=(0, PI / 2, -0.7), seg=6)
    part("Flame1", "cone", (0, 0, 0.45), (0.45, 0.45, 0.7), fire, seg=5)
    part("Flame2", "cone", (0.1, 0.05, 0.4), (0.3, 0.3, 0.9), fire, seg=4, rot=(0, 0, 0.6))
    export("campfire")


def build_tent():
    part("Tent", "cone", (0, 0, 1.1), (2.6, 2.6, 2.2), canvas, seg=4, rot=(0, 0, PI / 4))
    part("TentPole", "cyl", (0, 0, 2.3), (0.08, 0.08, 0.5), wood_dark, seg=5)
    part("Flap", "cube", (0, -0.9, 0.5), (0.6, 0.05, 0.9), dark, rot=(-0.4, 0, 0))
    export("tent")


def build_chest():
    part("ChestBase", "cube", (0, 0, 0.25), (0.9, 0.6, 0.5), wood)
    part("ChestLid", "cyl", (0, 0, 0.5), (0.6, 0.6, 0.9), wood, rot=(0, PI / 2, 0), seg=8)
    part("ChestBand", "cube", (0, 0, 0.35), (0.95, 0.65, 0.08), gold)
    part("ChestLock", "cube", (0, -0.32, 0.45), (0.12, 0.05, 0.14), gold)
    export("chest")


exec(open(OUT.replace("assets/models/", "tools/blender/characters.py"), encoding="utf-8").read(), globals())

# ASSETS="knight,elder" no ambiente gera só esses (útil para iterar).
import os
_only = [a for a in os.environ.get("ASSETS", "").split(",") if a]
BUILDERS = {
    "knight": build_knight, "goblin": build_goblin, "slime": build_slime, "elder": build_elder,
    "merchant": build_merchant, "tree_pine": build_tree_pine, "tree_oak": build_tree_oak, "rock": build_rock,
    "house": build_house, "fence": build_fence, "well": build_well, "ruin_pillar": build_ruin_pillar,
    "ruin_wall": build_ruin_wall, "crate": build_crate, "barrel": build_barrel, "lamp": build_lamp,
    "campfire": build_campfire, "tent": build_tent, "chest": build_chest,
}
clear()
for _name, _fn in BUILDERS.items():
    if not _only or _name in _only:
        _fn()
result = {"exported": exported}
