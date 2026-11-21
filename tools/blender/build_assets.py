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


def export(fname, **extra):
    print("EXPORT", fname, flush=True)
    vl = scn.view_layers[0]
    vl.update()
    wins = bpy.context.window_manager.windows
    kw = {"scene": scn, "view_layer": vl}
    if len(wins) > 0:
        kw["window"] = wins[0]
    # extra sobrescreve os padrões (ex.: export_animations=True para o ferreiro com esqueleto)
    opts = dict(filepath=OUT + fname + ".glb", export_format='GLB', use_selection=True, export_apply=True,
                export_yup=True, export_animations=False, export_cameras=False, export_lights=False)
    opts.update(extra)
    with bpy.context.temp_override(**kw):
        for o in scn.objects:
            o.select_set(True, view_layer=vl)
        bpy.ops.export_scene.gltf(**opts)
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
# Árvores e flores: tools/blender/trees.py


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


# A casa da vila (e as variações e lojas) está em village.py.




exec(open(OUT.replace("assets/models/", "tools/blender/characters.py"), encoding="utf-8").read(), globals())
exec(open(OUT.replace("assets/models/", "tools/blender/monsters.py"), encoding="utf-8").read(), globals())
exec(open(OUT.replace("assets/models/", "tools/blender/props.py"), encoding="utf-8").read(), globals())
exec(open(OUT.replace("assets/models/", "tools/blender/buildings.py"), encoding="utf-8").read(), globals())
exec(open(OUT.replace("assets/models/", "tools/blender/village.py"), encoding="utf-8").read(), globals())
exec(open(OUT.replace("assets/models/", "tools/blender/trees.py"), encoding="utf-8").read(), globals())
exec(open(OUT.replace("assets/models/", "tools/blender/biomes.py"), encoding="utf-8").read(), globals())
exec(open(OUT.replace("assets/models/", "tools/blender/weapons.py"), encoding="utf-8").read(), globals())
exec(open(OUT.replace("assets/models/", "tools/blender/armory.py"), encoding="utf-8").read(), globals())
exec(open(OUT.replace("assets/models/", "tools/blender/gear.py"), encoding="utf-8").read(), globals())
exec(open(OUT.replace("assets/models/", "tools/blender/back.py"), encoding="utf-8").read(), globals())
exec(open(OUT.replace("assets/models/", "tools/blender/body_mesh.py"), encoding="utf-8").read(), globals())
exec(open(OUT.replace("assets/models/", "tools/blender/anime.py"), encoding="utf-8").read(), globals())
exec(open(OUT.replace("assets/models/", "tools/blender/anime_body.py"), encoding="utf-8").read(), globals())
exec(open(OUT.replace("assets/models/", "tools/blender/female.py"), encoding="utf-8").read(), globals())
exec(open(OUT.replace("assets/models/", "tools/blender/dwarf.py"), encoding="utf-8").read(), globals())
exec(open(OUT.replace("assets/models/", "tools/blender/hair.py"), encoding="utf-8").read(), globals())

# ASSETS="knight,elder" no ambiente gera só esses (útil para iterar).
import os
_only = [a for a in os.environ.get("ASSETS", "").split(",") if a]
BUILDERS = {
    "knight": build_knight, "goblin": build_goblin, "slime": build_slime, "elder": build_elder,
    "santa": lambda: build_elder(santa=True),
    "merchant": build_merchant, "body_base": build_body_base,
    "blacksmith": build_blacksmith,
    "skeleton": build_skeleton, "raptor": build_raptor, "spider": build_spider, "centipede": build_centipede, "golem": build_golem, "mole": build_mole, "worm": build_worm, "plant": build_plant, "frog": build_frog, "bat": build_bat,
}
for _n in VILLAGER_LOOKS:   # aldeões da Defesa da Cidade (villager_<n>); ASSETS=villagers gera todos
    BUILDERS["villager_%d" % _n] = (lambda n=_n: build_villager(n))
if "villagers" in _only:
    _only += ["villager_%d" % _n for _n in VILLAGER_LOOKS]
BUILDERS.update(PROP_BUILDERS)
BUILDERS.update(VILLAGE_BUILDERS)   # casas e lojas da vila (village.py); ASSETS=village gera todas
if "village" in _only:
    _only += list(VILLAGE_BUILDERS)
if "buildings" in _only:   # ASSETS=buildings gera todas as construções da Defesa da Cidade (b_<tipo>_<nível>)
    _only += [n for n in PROP_BUILDERS if n.startswith("b_")]
BUILDERS.update(TREE_BUILDERS)   # árvores e flores (trees.py)
BUILDERS.update(BIOME_BUILDERS)   # peças dos biomas (biomes.py); ASSETS=biomes gera todas
if "biomes" in _only:
    _only += list(BIOME_BUILDERS)
BUILDERS.update(dict(WEAPONS))   # w_<id>: espadas (weapons.py); ASSETS=weapons gera todas
if "weapons" in _only:
    _only += [n for n, _ in WEAPONS]
for _grp, _pre in (("staves", "st_"), ("bows", "bw_"), ("classic", "w_"), ("scepters", "sc_"), ("tools", "tl_"), ("shields", "sh_")):   # grupos de armory.py
    if _grp in _only:
        _only += [n for n, _ in ARMORY if n.startswith(_pre)]
BUILDERS.update(dict(GEAR))      # roupas e armaduras modulares (gear.py); ASSETS=gear gera todas
if "gear" in _only:
    _only += [n for n, _ in GEAR]
BUILDERS.update(dict(BACK))      # asas e capas das costas (back.py); ASSETS=back gera todas
if "back" in _only:
    _only += [n for n, _ in BACK]
# corpo feminino (female.py): knight_f e gear/<estilo>_f; ASSETS=female gera tudo, ASSETS=gear_f só as roupas
BUILDERS["knight_f"] = build_knight_f
BUILDERS.update(dict(FEM_GEAR))
if "female" in _only or "gear_f" in _only:
    _only += [n for n, _ in FEM_GEAR] + (["knight_f"] if "female" in _only else [])
# corpo do anão (dwarf.py): knight_d e gear/<estilo>_d; ASSETS=dwarf gera tudo, ASSETS=gear_d só as roupas
BUILDERS["knight_d"] = build_knight_d
BUILDERS.update(dict(DWARF_GEAR))
if "dwarf" in _only or "gear_d" in _only:
    _only += [n for n, _ in DWARF_GEAR] + (["knight_d"] if "dwarf" in _only else [])
BUILDERS.update(dict(HAIR_BUILDERS))    # penteados do herói (hair.py); ASSETS=hair gera todos
if "hair" in _only or "gear" in _only or "female" in _only:
    _only += [n for n, _ in HAIR_BUILDERS]
clear()
for _name, _fn in BUILDERS.items():
    if not _only or _name in _only:
        _fn()
result = {"exported": exported}
