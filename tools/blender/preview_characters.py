# Prévia dos personagens (frente e costas) em fundo escuro.
# blender --background --factory-startup --python tools/blender/preview_characters.py -- <saida.png>
import bpy, sys, math
out = sys.argv[-1]
import os
D = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models")).replace("\\", "/") + "/"  # funciona em worktrees
scn = bpy.context.scene
for o in list(scn.objects):
    bpy.data.objects.remove(o)
names = ["knight", "elder", "merchant", "goblin"]
x = -3.6
for n in names:
    for back in (False, True):
        before = set(scn.objects)
        bpy.ops.import_scene.gltf(filepath=D + n + ".glb")
        for o in set(scn.objects) - before:
            if o.parent is None:
                o.location.x += x
                o.rotation_mode = 'XYZ'
                o.rotation_euler.z += math.pi if back else 0.0
        x += 0.95 if not back else 1.15
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
scn.collection.objects.link(cam)
cam.data.type = 'ORTHO'
cam.data.ortho_scale = 8.6
cam.location = (0.2, -12, 1.6)
cam.rotation_euler = (math.radians(86), 0, 0)
scn.camera = cam
scn.render.engine = 'BLENDER_WORKBENCH'
sh = scn.display.shading
sh.light = 'STUDIO'
sh.color_type = 'MATERIAL'
sh.show_shadows = True
sh.show_cavity = True
sh.cavity_type = 'BOTH'
sh.background_type = 'VIEWPORT'
sh.background_color = (0.08, 0.08, 0.09)
scn.display.shadow_shift = 0.1
scn.render.resolution_x = 1800
scn.render.resolution_y = 760
scn.render.filepath = out
bpy.ops.render.render(write_still=True)
