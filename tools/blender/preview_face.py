# Close do rosto (frente, 3/4, perfil): blender -b --python preview_face.py -- <nome> <altura_olhos> <saida.png>
import bpy, sys, math
import os
D = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models")).replace("\\", "/") + "/"  # funciona em worktrees
name, eye_z, out = sys.argv[-3], float(sys.argv[-2]), sys.argv[-1]
scn = bpy.context.scene
for o in list(scn.objects):
    bpy.data.objects.remove(o)
for i, ang in enumerate((0.0, 0.65, 1.5708)):
    before = set(scn.objects)
    bpy.ops.import_scene.gltf(filepath=D + name + ".glb")
    for o in set(scn.objects) - before:
        if o.parent is None:
            o.rotation_mode = 'XYZ'
            o.rotation_euler.z += ang
            o.location.x += (i - 1) * 0.42
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
scn.collection.objects.link(cam)
cam.data.type = 'ORTHO'; cam.data.ortho_scale = 1.3
cam.location = (0, -6, eye_z - 0.03); cam.rotation_euler = (math.radians(90), 0, 0)
scn.camera = cam
scn.render.engine = 'BLENDER_WORKBENCH'
sh = scn.display.shading; sh.light = 'STUDIO'; sh.color_type = 'MATERIAL'; sh.show_shadows = True; sh.show_cavity = True
scn.render.resolution_x = 1500; scn.render.resolution_y = 560
scn.render.filepath = out
bpy.ops.render.render(write_still=True)
