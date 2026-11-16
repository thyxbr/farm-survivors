# Folha de conferência do herói montado como no jogo (knight.glb + estilos de equipamento padrão).
# blender -b --factory-startup --python tools/blender/preview_hero.py -- <saida.png> <fig> [<fig>...] [silhouette] [head]
# fig = <corpo><visual>:<vista>, corpo m|f, visual b (sem armadura: camisa, calça, sapato, cabeça nua) ou
# p (placas do knight.glb, com capa) ou [estilos] (ex.: f[a_mail,h_hood]:side), vista front|q|side|back|qb.
# Ex.: fb:front fb:side fp:back mb:back
import bpy, sys, math, os
D = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models")).replace("\\", "/") + "/"
args = sys.argv[sys.argv.index("--") + 1:]
out = args[0]
figs = [a for a in args[1:] if ":" in a]
flags = set(a for a in args[1:] if ":" not in a)
REGION = ["Helmet", "HelmetDome", "VisorSlit", "HelmetTrim", "Plume", "Hips", "Torso", "Fauld", "Belt", "Tabard",
          "Gorget", "ArmL_Pauldron", "ArmR_Pauldron", "ArmL_Upper", "ArmR_Upper", "ArmL_Vambrace", "ArmR_Vambrace",
          "LegL_Thigh", "LegR_Thigh", "ArmL_Gauntlet", "ArmR_Gauntlet", "ArmL_Hand", "ArmR_Hand", "LegL_Sabaton",
          "LegR_Sabaton", "LegL_Knee", "LegR_Knee", "LegL_Foot", "LegR_Foot", "Cape"]
HIDE = ["Shield", "ShieldRim", "Grip", "Blade"]
VIEW = {"front": 0.0, "q": 0.62, "side": math.pi / 2, "back": math.pi, "qb": math.pi - 0.62}
scn = bpy.context.scene
for o in list(scn.objects):
    bpy.data.objects.remove(o)


def load(path, x, rot, drop=()):
    before = set(scn.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o.name for o in scn.objects if o not in before]
    for n in new:
        if n.split(".")[0] in drop:
            o = bpy.data.objects[n]
            for c in list(o.children):
                c.parent = None
            bpy.data.objects.remove(o)
    for o in [bpy.data.objects[n] for n in new if n in bpy.data.objects]:
        if o.parent is None:
            o.location.x += x
            o.rotation_mode = 'XYZ'
            o.rotation_euler.z += rot


step = 0.62 if "head" in flags else 0.95
x0 = -(len(figs) - 1) * step / 2
for i, f in enumerate(figs):
    kind, view = f.rsplit(":", 1)
    body, look = kind[0], kind[1]
    suf = "_f" if body == "f" else ""
    x, rot = x0 + i * step, VIEW[view]
    styles = {"h": "h_bare", "a": "a_shirt", "g": "g_bare", "f": "f_shoes"}
    if look == "[":     # estilos dados: f[a_mail,h_hood]:side (o resto fica no padrão)
        for st in kind[2:-1].split(","):
            styles[st[0]] = st
    load(D + "knight" + suf + ".glb", x, rot, HIDE + (REGION if look != "p" else []))
    if look != "p":
        for st in styles.values():
            load(D + "gear/" + st + suf + ".glb", x, rot)
# cor de viewport = cor base do material (os GLBs com AO por vértice importam a cor num nó Mix)
for m in bpy.data.materials:
    if not m.node_tree:
        continue
    for nd in m.node_tree.nodes:
        if nd.type == 'MIX' and nd.inputs.get("B") is not None and hasattr(nd.inputs["B"].default_value, "__len__"):
            for i in nd.inputs:
                if i.enabled and i.name == "B" and hasattr(i.default_value, "__len__") and len(i.default_value) == 4:
                    m.diffuse_color = i.default_value
        if nd.type == 'BSDF_PRINCIPLED' and not nd.inputs["Base Color"].links:
            m.diffuse_color = nd.inputs["Base Color"].default_value
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
scn.collection.objects.link(cam)
cam.data.type = 'ORTHO'
if "head" in flags:
    cam.data.ortho_scale = max(1.0, len(figs) * step + 0.1)
    cam.location = (0, -10, 1.45)
else:
    cam.data.ortho_scale = max(2.1, len(figs) * step + 0.2)
    cam.location = (0, -10, 0.95)
cam.rotation_euler = (math.radians(90), 0, 0)
scn.camera = cam
scn.render.engine = 'BLENDER_WORKBENCH'
sh = scn.display.shading
if "silhouette" in flags:
    sh.light = 'FLAT'
    sh.color_type = 'SINGLE'
    sh.single_color = (0, 0, 0)
    sh.background_type = 'VIEWPORT'
    sh.background_color = (1, 1, 1)
else:
    sh.light = 'STUDIO'
    sh.color_type = 'MATERIAL'
    sh.show_shadows = True
    sh.show_cavity = True
    sh.cavity_type = 'BOTH'
    sh.background_type = 'VIEWPORT'
    sh.background_color = (0.08, 0.08, 0.09)
scn.view_settings.view_transform = 'Standard'
w = 1500
scn.render.resolution_x = w
if "head" in flags:
    scn.render.resolution_y = int(w * 0.75 / cam.data.ortho_scale)
else:
    scn.render.resolution_y = int(w * 2.05 / cam.data.ortho_scale)
scn.render.filepath = out
bpy.ops.render.render(write_still=True)
