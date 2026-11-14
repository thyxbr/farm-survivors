# Prévia das árvores (ou flores) em fila, câmera um pouco acima do olho.
# blender -b --factory-startup --python tools/blender/preview_trees.py -- <saida.png> nome,nome,... [espaço_m]
import bpy, sys, math, os
D = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models")).replace("\\", "/") + "/"
args = sys.argv[sys.argv.index("--") + 1:]
out = args[0]
names = args[1].split(",")
sp = float(args[2]) if len(args) > 2 else 5.5
scn = bpy.context.scene
for o in list(scn.objects):
    bpy.data.objects.remove(o)
hmax = 0.0
for i, n in enumerate(names):
    before = set(scn.objects)
    bpy.ops.import_scene.gltf(filepath=D + n + ".glb")
    for o in set(scn.objects) - before:
        if o.type == 'MESH':
            hmax = max(hmax, max((o.matrix_world @ v.co).z for v in o.data.vertices))
        if o.parent is None:
            o.location.x += (i - (len(names) - 1) / 2) * sp
bpy.ops.mesh.primitive_plane_add(size=400)
g = scn.objects[-1] if bpy.context.active_object is None else bpy.context.active_object
gm = bpy.data.materials.new("ground")
gm.diffuse_color = (0.2, 0.33, 0.12, 1)
g.scale = (1, 0.12, 1)
g.data.materials.append(gm)
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
scn.collection.objects.link(cam)
cam.data.type = 'ORTHO'
w = len(names) * sp
cam.data.ortho_scale = max(w + 1.0, hmax * 1.9)
cam.location = (0, -40, hmax * 0.5 + 40 * math.tan(math.radians(8)))
cam.rotation_euler = (math.radians(82), 0, 0)
scn.camera = cam
sh = scn.display.shading
sh.light = 'STUDIO'
sh.color_type = 'MATERIAL'
sh.show_shadows = True
sh.show_cavity = False
sh.background_type = 'VIEWPORT'
sh.background_color = (0.6, 0.72, 0.85)
scn.render.engine = 'BLENDER_WORKBENCH'
scn.view_settings.view_transform = 'Standard'
scn.render.resolution_x = 1600
scn.render.resolution_y = int(1600 * hmax * 1.25 / max(w + 1.0, hmax * 1.9)) + 200
scn.render.filepath = out
bpy.ops.render.render(write_still=True)
