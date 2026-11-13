# Gera todos os modelos low-poly do jogo e exporta como GLB para assets/models.
# Uso dentro do Blender:  exec(open(r"C:/Games/godot-3d/tools/blender/build_assets.py").read())
# Cada asset é montado numa cena separada ("RPG_Assets"), exportado e depois apagado,
# então a cena padrão do usuário não é tocada.
import bpy, bmesh, math, random
from mathutils import Matrix, Euler, Vector

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


def build_house():
    part("Foundation", "cube", (0, 0, 0.15), (5.2, 4.2, 0.3), stone_dark)
    part("Walls", "cube", (0, 0, 1.55), (5.0, 4.0, 2.5), plaster)
    for x in (-2.45, 2.45):
        for y in (-1.95, 1.95):
            part("Beam_%d_%d" % (x * 10, y * 10), "cube", (x, y, 1.55), (0.22, 0.22, 2.5), wood_dark)
    part("BeamTopF", "cube", (0, -2.0, 2.75), (5.1, 0.16, 0.18), wood_dark)
    part("BeamTopB", "cube", (0, 2.0, 2.75), (5.1, 0.16, 0.18), wood_dark)
    part("BeamMid", "cube", (0, -2.02, 1.55), (5.0, 0.1, 0.14), wood_dark)
    part("Roof", "cyl", (0, 0, 3.6), (2.9, 5.6, 5.8), roof_m, rot=(0, -PI / 2, 0), seg=3)
    part("Door", "cube", (0, -2.03, 1.1), (0.95, 0.08, 1.6), wood)
    part("DoorKnob", "ico", (0.3, -2.09, 1.1), (0.08, 0.06, 0.08), gold)
    for x in (-1.55, 1.55):
        part("Window_%d" % (x * 10), "cube", (x, -2.03, 1.85), (0.75, 0.06, 0.6), glass)
        part("WinFrameH_%d" % (x * 10), "cube", (x, -2.06, 1.85), (0.8, 0.04, 0.06), wood_dark)
        part("WinFrameV_%d" % (x * 10), "cube", (x, -2.06, 1.85), (0.06, 0.04, 0.65), wood_dark)
    part("Chimney", "cube", (1.4, 0.9, 4.0), (0.55, 0.55, 1.8), stone)
    part("Step", "cube", (0, -2.35, 0.1), (1.3, 0.5, 0.2), stone)
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
