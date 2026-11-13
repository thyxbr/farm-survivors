# Close-up do busto de um personagem: blender -b --python preview_closeup.py -- <nome> <saida.png> [z] [escala]
#   [x] [ângulos]
# z = altura do centro da imagem (padrão: busto), escala = largura ortográfica (padrão 2.4) e x = ponto do modelo
# posto no centro de cada uma das três vistas; ângulos = giros das três cópias em graus (padrão "0,40,180"). Ex.: "1.72 0.9" = elmo; "0.9 0.6 -0.3" = mão direita.
import bpy, sys, math
import os
D = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models")).replace("\\", "/") + "/"  # funciona em worktrees
args = sys.argv[sys.argv.index("--") + 1:]
name, out = args[0], args[1]
zoom = float(args[3]) if len(args) > 3 else 2.4
fx = float(args[4]) if len(args) > 4 else 0.0
gap = 0.75 if len(args) < 4 else zoom / 3
scn = bpy.context.scene
for o in list(scn.objects):
    bpy.data.objects.remove(o)
from mathutils import Vector
top = float(args[2]) if len(args) > 2 else (1.45 if name != "goblin" else 0.95)
angs = [math.radians(float(a)) for a in args[5].split(",")] if len(args) > 5 else (0.0, 0.7, math.pi)
for i, ang in enumerate(angs):
    before = set(scn.objects)
    bpy.ops.import_scene.gltf(filepath=D + name + ".glb")
    if len(args) > 4:  # foco num ponto lateral (mão): some com o que está longe dele para as vistas não se taparem
        bpy.context.view_layer.update()
        for o in set(scn.objects) - before:
            if o.type == 'MESH':
                c = o.matrix_world @ (sum((Vector(b) for b in o.bound_box), Vector()) / 8)
                if math.hypot(c.x - fx, c.z - top) > zoom * 0.45:
                    bpy.data.objects.remove(o)
    for o in set(scn.objects) - before:
        if o.parent is None:
            o.location.x += (i - 1) * gap - fx * math.cos(ang)
            o.location.y -= fx * math.sin(ang)
            o.rotation_mode = 'XYZ'
            o.rotation_euler.z += ang
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
scn.collection.objects.link(cam)
cam.data.type = 'ORTHO'
cam.data.ortho_scale = zoom
cam.location = (0, -10, top + (10 * math.tan(math.radians(2)) if len(args) > 2 else 0.0))
cam.rotation_euler = (math.radians(88), 0, 0)
scn.camera = cam
scn.render.engine = 'BLENDER_WORKBENCH'
sh = scn.display.shading
sh.light = 'STUDIO'; sh.color_type = 'MATERIAL'; sh.show_shadows = True; sh.show_cavity = True
scn.render.resolution_x = 1500; scn.render.resolution_y = 1000
scn.render.filepath = out
bpy.ops.render.render(write_still=True)
