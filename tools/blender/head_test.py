# Teste visual das cabeças: blender -b --factory-startup --python head_test.py -- <saida_prefixo>
import bpy, sys, math, os
os.environ["ASSETS"] = "none"
exec(open("C:/Games/godot-3d/tools/blender/build_assets.py", encoding="utf-8").read(), globals())
exec(open("C:/Games/godot-3d/tools/blender/head.py", encoding="utf-8").read(), globals())
out = sys.argv[-1]
M = {
    "skin": mat("t_skin", (0.82, 0.58, 0.45), 0.8), "lip": mat("t_lip", (0.66, 0.36, 0.32), 0.7),
    "sclera": mat("t_sclera", (0.92, 0.9, 0.86), 0.4), "iris": mat("t_iris", (0.3, 0.2, 0.1), 0.3),
    "pupil": mat("t_pupil", (0.02, 0.02, 0.02), 0.2), "brow": mat("t_brow", (0.25, 0.15, 0.08), 0.9),
    "lash": mat("t_lash", (0.08, 0.05, 0.04), 0.9),
}
variants = [("A", {}), ("B", {"age": 1.0, "nose": 1.2, "eye_depth": 1.3}), ("C", {"fem": 1.0, "nose": 0.75, "brow": 0.5, "jaw": 0.92, "eye_size": 1.1})]
for i, (n, prm) in enumerate(variants):
    root = empty("H" + n, (0, 0, 0))
    human_head(n, 0.0, 0.235, root, M, prm)
    for o in list(coll.objects):
        if o.parent is root or o is root:
            pass
    root.location.x = (i - 1) * 0.3
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam")); scn.collection.objects.link(cam)
cam.data.type = 'ORTHO'; cam.data.ortho_scale = 0.95
scn.camera = cam
scn.render.engine = 'BLENDER_WORKBENCH'
sh = scn.display.shading; sh.light = 'STUDIO'; sh.color_type = 'MATERIAL'; sh.show_shadows = True; sh.show_cavity = True
scn.render.resolution_x = 1500; scn.render.resolution_y = 560
for tag, ang in (("front", 0.0), ("tq", 0.6), ("side", 1.5708), ("zoom", 0.35)):
    cam.data.ortho_scale = 0.95 if tag != "zoom" else 0.3
    r = 3.0
    cam.location = (math.sin(ang) * r + (0.0 if tag != "zoom" else -0.3 + 0.0), -math.cos(ang) * r, 0.12 if tag != "zoom" else 0.11)
    cam.rotation_euler = (math.radians(90), 0, ang)
    scn.render.filepath = out + "_" + tag + ".png"
    bpy.ops.render.render(write_still=True)
