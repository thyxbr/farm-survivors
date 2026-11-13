# Folha das espadas (w_*.glb) lado a lado, vistas de frente, em duas fileiras.
# blender -b --factory-startup --python tools/blender/preview_weapons.py -- <saida.png> [silhouette] [small]
import bpy, sys, math, os, glob
D = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models"))
args = sys.argv[sys.argv.index("--") + 1:]
out, flags = args[0], set(args[1:])
scn = bpy.context.scene
for o in list(scn.objects):
    bpy.data.objects.remove(o)
files = sorted(glob.glob(os.path.join(D, "w_*.glb")))
per_row = (len(files) + 1) // 2
for i, f in enumerate(files):
    before = set(scn.objects)
    bpy.ops.import_scene.gltf(filepath=f)
    tris = 0
    for o in set(scn.objects) - before:
        if o.type == 'MESH':
            o.data.calc_loop_triangles()
            tris += len(o.data.loop_triangles)
        if o.parent is None:
            o.location.x += 0.1 + (i % per_row - (per_row - 1) / 2) * 0.5
            o.location.z += 0.0 if i < per_row else -1.55
    print("TRIS", os.path.basename(f)[:-4], tris, len({s.material for o in set(scn.objects) - before
          if o.type == 'MESH' for s in o.material_slots}), flush=True)
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
scn.collection.objects.link(cam)
cam.data.type = 'ORTHO'
cam.data.ortho_scale = per_row * 0.5 + 0.5
cam.location = (0, -10, -0.2)
cam.rotation_euler = (math.radians(90), 0, 0)
scn.camera = cam
scn.render.engine = 'BLENDER_WORKBENCH'
sh = scn.display.shading
if "silhouette" in flags:
    sh.light, sh.color_type, sh.single_color = 'FLAT', 'SINGLE', (0, 0, 0)
    sh.background_type, sh.background_color = 'VIEWPORT', (1, 1, 1)
else:
    sh.light, sh.color_type = 'STUDIO', 'MATERIAL'
    sh.show_cavity, sh.cavity_type = True, 'BOTH'
    sh.background_type, sh.background_color = 'VIEWPORT', (0.93, 0.93, 0.94)
scn.view_settings.view_transform = 'Standard'
small = "small" in flags
scn.render.resolution_x = 1100 if small else 1800
scn.render.resolution_y = int(scn.render.resolution_x * 3.3 / (per_row * 0.5 + 0.5))
scn.render.filepath = out
bpy.ops.render.render(write_still=True)
