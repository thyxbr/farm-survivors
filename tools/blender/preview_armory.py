# Folha de conferência das armas de armory.py, com a cor do vértice (pintura anime) e luz chapada.
# blender -b --factory-startup --python tools/blender/preview_armory.py -- <saida.png> <prefixo: st_|bw_|w_> [3q|side] [heads] [ids,separados]
import bpy, sys, math, os, glob
D = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models"))
args = sys.argv[sys.argv.index("--") + 1:]
out, pre = args[0], args[1]
flags = set(args[2:])
only = [a for f in flags if "," in f or f.startswith(pre) for a in f.split(",")]
scn = bpy.context.scene
for o in list(scn.objects):
    bpy.data.objects.remove(o)
files = sorted(glob.glob(os.path.join(D, pre + "*.glb")))
if only:
    files = [f for f in files if os.path.basename(f)[:-4] in only]
gap = 0.42 if pre != "bw_" else 0.5
for i, f in enumerate(files):
    before = set(scn.objects)
    bpy.ops.import_scene.gltf(filepath=f)
    tris = 0
    for o in set(scn.objects) - before:
        if o.type == 'MESH':
            o.data.calc_loop_triangles()
            tris += len(o.data.loop_triangles)
        if o.parent is None:
            o.location.x += (i - (len(files) - 1) / 2) * gap
            o.rotation_mode = 'XYZ'          # o importador glTF usa quatérnio
            if "3q" in flags:
                o.rotation_euler.z = math.radians(-35)
            elif "side" in flags:
                o.rotation_euler.z = math.radians(90)
    print("TRIS", os.path.basename(f)[:-4], tris, flush=True)
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
scn.collection.objects.link(cam)
cam.data.type = 'ORTHO'
cam.data.ortho_scale = max(len(files) * gap + 0.2, 1.5 if pre == "sc_" else 2.0)
cam.location = (0, -10, 0.35 if pre in ("st_", "sc_") else 0.0)
cam.rotation_euler = (math.radians(90), 0, 0)
scn.camera = cam
scn.render.engine = 'BLENDER_WORKBENCH'
sh = scn.display.shading
sh.light, sh.color_type = 'FLAT', 'VERTEX'
sh.show_object_outline = False
sh.background_type, sh.background_color = 'VIEWPORT', (0.86, 0.87, 0.9)
scn.view_settings.view_transform = 'Standard'
scn.render.resolution_x = 2000
scn.render.resolution_y = int(2000 * 2.0 / cam.data.ortho_scale) if cam.data.ortho_scale > 2.0 else 2000
if "heads" in flags:                        # só as cabeças dos cajados, de perto
    cam.location.z = 1.06
    scn.render.resolution_y = int(2000 * 0.42 / cam.data.ortho_scale)
scn.render.filepath = out
bpy.ops.render.render(write_still=True)
