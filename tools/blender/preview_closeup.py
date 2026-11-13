# Close-up do busto de um personagem: blender -b --python preview_closeup.py -- <nome> <saida.png>
import bpy, sys, math
name, out = sys.argv[-2], sys.argv[-1]
scn = bpy.context.scene
for o in list(scn.objects):
    bpy.data.objects.remove(o)
for i, ang in enumerate((0.0, 0.7, math.pi)):
    before = set(scn.objects)
    bpy.ops.import_scene.gltf(filepath="C:/Games/godot-3d/assets/models/" + name + ".glb")
    for o in set(scn.objects) - before:
        if o.parent is None:
            o.location.x += (i - 1) * 0.75
            o.rotation_mode = 'XYZ'
            o.rotation_euler.z += ang
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
scn.collection.objects.link(cam)
cam.data.type = 'ORTHO'
cam.data.ortho_scale = 2.4
top = 1.45 if name != "goblin" else 0.95
cam.location = (0, -10, top)
cam.rotation_euler = (math.radians(88), 0, 0)
scn.camera = cam
scn.render.engine = 'BLENDER_WORKBENCH'
sh = scn.display.shading
sh.light = 'STUDIO'; sh.color_type = 'MATERIAL'; sh.show_shadows = True; sh.show_cavity = True
scn.render.resolution_x = 1500; scn.render.resolution_y = 1000
scn.render.filepath = out
bpy.ops.render.render(write_still=True)
