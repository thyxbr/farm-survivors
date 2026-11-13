# Folha de conferência de um asset: frente, 3/4 e costas, corpo inteiro.
# blender -b --factory-startup --python tools/blender/preview_single.py -- <nome> <saida.png> [silhouette]
import bpy, sys, math
args = sys.argv[sys.argv.index("--") + 1:]
name, out = args[0], args[1]
silhouette = len(args) > 2 and args[2] == "silhouette"
scn = bpy.context.scene
for o in list(scn.objects):
    bpy.data.objects.remove(o)
tris = 0
for i, ang in enumerate((0.0, 0.75, math.pi)):
    before = set(scn.objects)
    bpy.ops.import_scene.gltf(filepath="C:/Games/godot-3d/assets/models/" + name + ".glb")
    for o in set(scn.objects) - before:
        if i == 0 and o.type == 'MESH':
            o.data.calc_loop_triangles()
            tris += len(o.data.loop_triangles)
        if o.parent is None:
            o.location.x += (i - 1) * 1.05
            o.rotation_mode = 'XYZ'
            o.rotation_euler.z += ang
print("TRIS", name, tris, flush=True)
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
scn.collection.objects.link(cam)
cam.data.type = 'ORTHO'
cam.data.ortho_scale = 3.3
cam.location = (0, -10, 0.98)
cam.rotation_euler = (math.radians(90), 0, 0)
scn.camera = cam
scn.render.engine = 'BLENDER_WORKBENCH'
sh = scn.display.shading
if silhouette:
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
scn.render.resolution_x = 1650
scn.render.resolution_y = 1050
scn.render.filepath = out
bpy.ops.render.render(write_still=True)
