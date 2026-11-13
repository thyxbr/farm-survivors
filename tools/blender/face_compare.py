# Folha de conferência do rosto: frente, 3/4 e perfil com linhas de proporção humana.
# 1) blender -b --factory-startup --python tools/blender/face_compare.py -- <nome> <queixo_z> <altura_cabeca> <saida.png> [sem_chapeu]
# 2) python tools/face_sheet.py <saida.png> <queixo_z> <altura_cabeca> <referencia.png> <folha.png>
import bpy, sys, math
import os
D = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models")).replace("\\", "/") + "/"  # funciona em worktrees
args = sys.argv[sys.argv.index("--") + 1:]
name, chin, H, out = args[0], float(args[1]), float(args[2]), args[3]
hide_hat = len(args) > 4 and args[4] == "sem_chapeu"
scn = bpy.context.scene
for o in list(scn.objects):
    bpy.data.objects.remove(o)
for i, ang in enumerate((0.0, 0.6, math.pi / 2)):
    before = set(scn.objects)
    bpy.ops.import_scene.gltf(filepath=D + name + ".glb")
    for o in set(scn.objects) - before:
        if hide_hat and any(k in o.name for k in ("Turban", "Hat", "Hood", "Helmet")):
            o.hide_render = True
        if o.parent is None:
            o.rotation_mode = 'XYZ'
            o.rotation_euler.z += ang
            o.location.x += (i - 1) * 0.3
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
scn.collection.objects.link(cam)
cam.data.type = 'ORTHO'
cam.data.ortho_scale = 0.9          # 0,9 m na largura de 1800 px -> 2000 px/m
cam.location = (0, -6, chin + H * 0.5)
cam.rotation_euler = (math.radians(90), 0, 0)
scn.camera = cam
scn.render.engine = 'BLENDER_WORKBENCH'
sh = scn.display.shading
sh.light = 'STUDIO'
sh.color_type = 'MATERIAL'
sh.show_shadows = True
sh.show_cavity = True
sh.background_type = 'VIEWPORT'
sh.background_color = (0.08, 0.08, 0.09)
scn.view_settings.view_transform = 'Standard'
scn.render.resolution_x = 1800
scn.render.resolution_y = 700
scn.render.filepath = out
bpy.ops.render.render(write_still=True)
