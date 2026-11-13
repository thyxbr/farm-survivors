# Renderiza uma prévia de todos os GLBs lado a lado (útil para conferir os modelos).
# blender --background --factory-startup --python tools/blender/preview_assets.py -- <saida.png>
import bpy, sys, math, os
out = sys.argv[-1]
import os
D = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models")).replace("\\", "/") + "/"  # funciona em worktrees
scn = bpy.context.scene
for o in list(scn.objects):
    bpy.data.objects.remove(o)
chars = ["knight", "goblin", "slime", "elder", "merchant", "chest", "crate", "barrel", "campfire"]
props = ["house", "tree_pine", "tree_oak", "rock", "well", "fence", "ruin_pillar", "ruin_wall", "lamp", "tent"]
def place(names, y, spacing):
    x = -spacing * (len(names) - 1) / 2
    for n in names:
        before = set(scn.objects)
        bpy.ops.import_scene.gltf(filepath=D + n + ".glb")
        for o in set(scn.objects) - before:
            if o.parent is None:
                o.location.x += x
                o.location.y += y
        x += spacing
place(chars, 0, 1.6)
place(props, 9, 6.0)
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
scn.collection.objects.link(cam)
cam.location = (0, -26, 14)
cam.rotation_euler = (math.radians(65), 0, 0)
cam.data.lens = 28
scn.camera = cam
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
scn.collection.objects.link(sun)
sun.rotation_euler = (math.radians(50), math.radians(20), math.radians(-30))
scn.render.engine = 'BLENDER_WORKBENCH'
scn.display.shading.light = 'STUDIO'
scn.display.shading.color_type = 'MATERIAL'
scn.display.shading.show_shadows = True
scn.render.resolution_x = 1600
scn.render.resolution_y = 900
scn.render.filepath = out
bpy.ops.render.render(write_still=True)
