# Prévia dos objetos de cenário e das culturas em 3/4.
# blender -b --factory-startup --python tools/blender/preview_props.py -- <saida.png> [nome,nome,...]
import bpy, sys, math, os
D = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models")).replace("\\", "/") + "/"
args = sys.argv[sys.argv.index("--") + 1:]
out = args[0]
names = args[1].split(",") if len(args) > 1 else ["chest", "crate", "barrel", "fence", "lamp", "campfire", "rock", "well", "tent"]
scn = bpy.context.scene
for o in list(scn.objects):
    bpy.data.objects.remove(o)
cols = min(5, len(names))
sp = 2.6 if any(n in ("well", "tent", "rock", "fence") for n in names) else 2.0
for i, n in enumerate(names):
    before = set(scn.objects)
    bpy.ops.import_scene.gltf(filepath=D + n + ".glb")
    for o in set(scn.objects) - before:
        if o.parent is None:
            o.location.x += (i % cols - (cols - 1) / 2) * sp
            o.location.y += (i // cols) * sp
rows = (len(names) - 1) // cols + 1
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
scn.collection.objects.link(cam)
cam.data.type = 'ORTHO'
cam.data.ortho_scale = cols * sp + 0.6
cam.location = (cols * 0.0 - 6, -12 + (rows - 1) * sp / 2, 9)
cam.rotation_euler = (math.radians(58), 0, math.radians(-28))
scn.camera = cam
sh = scn.display.shading
sh.light = 'STUDIO'
sh.color_type = 'MATERIAL'
sh.show_shadows = True
sh.show_cavity = True
sh.background_type = 'VIEWPORT'
sh.background_color = (0.32, 0.42, 0.28)
scn.render.engine = 'BLENDER_WORKBENCH'
scn.view_settings.view_transform = 'Standard'
scn.render.resolution_x = 1600
scn.render.resolution_y = 600 + 300 * (rows - 1)
scn.render.filepath = out
bpy.ops.render.render(write_still=True)
