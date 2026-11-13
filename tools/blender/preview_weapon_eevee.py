# Render de UMA arma (w_<id>.glb) em Eevee, de frente, com luz de estúdio parecida com a do jogo:
# mostra a cor por vértice, o brilho especular e o volume do bisel, que o Workbench achata.
# blender -b --factory-startup --python tools/blender/preview_weapon_eevee.py -- <w_id> <saida.png> [altura_px] [3q]
#   3q: vista 3/4 (gira 35°) para conferir espessura e bisel.
import bpy, sys, math, os
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
name, out = args[0], args[1]
H = int(args[2]) if len(args) > 2 and args[2].isdigit() else 900
D = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models"))
scn = bpy.context.scene
for o in list(scn.objects):
    bpy.data.objects.remove(o)
bpy.ops.import_scene.gltf(filepath=os.path.join(D, name + ".glb"))
meshes = [o for o in scn.objects if o.type == 'MESH']
tris = 0
for o in meshes:
    o.data.calc_loop_triangles()
    tris += len(o.data.loop_triangles)
print("TRIS", name, tris, len({s.material for o in meshes for s in o.material_slots}), flush=True)
if "3q" in args:
    piv = bpy.data.objects.new("Piv", None)
    scn.collection.objects.link(piv)
    for o in scn.objects:
        if o.parent is None and o is not piv:
            o.parent = piv
    piv.rotation_euler = (0, 0, math.radians(35))
    bpy.context.view_layer.update()

scn.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in {e.identifier for e in
                                                                      bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items} else 'BLENDER_EEVEE'
scn.view_settings.view_transform = 'Standard'
w = bpy.data.worlds.new("W")
scn.world = w
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.58, 0.65, 1)
w.node_tree.nodes["Background"].inputs[1].default_value = 0.6


def light(nm, kind, energy, rot, color=(1, 1, 1)):
    l = bpy.data.objects.new(nm, bpy.data.lights.new(nm, kind))
    l.data.energy = energy
    l.data.color = color
    l.rotation_euler = [math.radians(a) for a in rot]
    scn.collection.objects.link(l)


light("Key", 'SUN', 2.0, (60, 0, -35), (1.0, 0.97, 0.92))    # de cima, esquerda, frente
light("Rim", 'SUN', 0.6, (-60, 0, 160), (0.85, 0.9, 1.0))    # contra-luz para o brilho do gume

pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
lo = Vector((min(p.x for p in pts), 0, min(p.z for p in pts)))
hi = Vector((max(p.x for p in pts), 0, max(p.z for p in pts)))
wd, ht = (hi.x - lo.x) * 1.08, (hi.z - lo.z) * 1.04
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
scn.collection.objects.link(cam)
cam.data.type = 'ORTHO'
cam.data.ortho_scale = max(wd, ht)
cam.rotation_euler = (math.radians(90), 0, 0)
cam.location = ((lo.x + hi.x) / 2, -10, (lo.z + hi.z) / 2)
scn.camera = cam
scn.render.resolution_y = H
scn.render.resolution_x = max(64, int(H * wd / ht))
scn.render.film_transparent = True
scn.render.image_settings.color_mode = 'RGBA'
scn.render.filepath = out
bpy.ops.render.render(write_still=True)
