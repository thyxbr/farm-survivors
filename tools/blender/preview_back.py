# Folha de conferência de uma peça das costas no cavaleiro: costas, 3/4 de costas, lado e frente.
# blender -b --factory-startup --python tools/blender/preview_back.py -- <estilo> <saida.png> [small]
import bpy, sys, math, os
D = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models")).replace("\\", "/") + "/"
args = sys.argv[sys.argv.index("--") + 1:]
name, out = args[0], args[1]
small = "small" in args[2:]
scn = bpy.context.scene
for o in list(scn.objects):
    bpy.data.objects.remove(o)
tris = 0
for i, ang in enumerate((math.pi, math.pi - 0.8, math.pi / 2, 0.0)):
    for f in ("knight", "back/" + name):
        before = set(scn.objects)
        bpy.ops.import_scene.gltf(filepath=D + f + ".glb")
        for o in set(scn.objects) - before:
            if i == 0 and f != "knight" and o.type == 'MESH':
                o.data.calc_loop_triangles()
                tris += len(o.data.loop_triangles)
            if f == "knight" and o.name.split(".")[0] in ("Cape", "Shield", "ShieldBoss", "ShieldRim"):
                o.hide_render = True
            if o.parent is None:
                o.location.x += (i - 1.5) * 2.5
                o.rotation_mode = 'XYZ'
                o.rotation_euler.z += ang
print("TRIS", name, tris, flush=True)
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
scn.collection.objects.link(cam)
cam.data.type = 'ORTHO'
cam.data.ortho_scale = 10.2
cam.location = (0, -12, 1.15)
cam.rotation_euler = (math.radians(90), 0, 0)
scn.camera = cam
scn.render.engine = 'BLENDER_WORKBENCH'
sh = scn.display.shading
sh.light = 'STUDIO'
sh.color_type = 'MATERIAL'
sh.show_cavity = True
sh.cavity_type = 'BOTH'
sh.background_type = 'VIEWPORT'
sh.background_color = (0.16, 0.18, 0.24)
scn.view_settings.view_transform = 'Standard'
scn.render.resolution_x = 1100 if small else 2000
scn.render.resolution_y = 330 if small else 600
scn.render.filepath = out
bpy.ops.render.render(write_still=True)
