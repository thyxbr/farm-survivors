# Folha das espadas (w_*.glb), vistas de frente.
# blender -b --factory-startup --python tools/blender/preview_weapons.py -- <saida.png> [silhouette] [small]
# blender -b --factory-startup --python tools/blender/preview_weapons.py -- <pasta> each   (um PNG por arma, enquadrado)
import bpy, sys, math, os, glob
from mathutils import Vector
D = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models"))
args = sys.argv[sys.argv.index("--") + 1:]
out, flags = args[0], set(args[1:])
scn = bpy.context.scene
files = sorted(glob.glob(os.path.join(D, "w_*.glb")))


def clear():
    for o in list(scn.objects):
        bpy.data.objects.remove(o)


def load(f):
    before = set(scn.objects)
    bpy.ops.import_scene.gltf(filepath=f)
    new = set(scn.objects) - before
    tris, mats = 0, set()
    for o in new:
        if o.type == 'MESH':
            o.data.calc_loop_triangles()
            tris += len(o.data.loop_triangles)
            mats |= {s.material.name for s in o.material_slots if s.material}
    print("TRIS", os.path.basename(f)[:-4], tris, len(mats), flush=True)
    return [o for o in new if o.parent is None]


def setup(silhouette):
    scn.render.engine = 'BLENDER_WORKBENCH'
    sh = scn.display.shading
    sh.show_backface_culling = True     # o contorno (casca invertida) só aparece nas bordas
    if silhouette:
        sh.light, sh.color_type, sh.single_color = 'FLAT', 'SINGLE', (0, 0, 0)
        sh.background_type, sh.background_color = 'VIEWPORT', (1, 1, 1)
    else:
        has_col = any(o.type == 'MESH' and o.data.color_attributes for o in scn.objects)
        sh.light, sh.color_type = 'STUDIO', ('VERTEX' if has_col else 'MATERIAL')
        sh.show_cavity, sh.cavity_type = True, 'BOTH'
        sh.show_specular_highlight = True
        sh.background_type, sh.background_color = 'VIEWPORT', (1, 1, 1)
    scn.view_settings.view_transform = 'Standard'
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    scn.collection.objects.link(cam)
    cam.data.type = 'ORTHO'
    cam.rotation_euler = (math.radians(90), 0, 0)
    scn.camera = cam
    return cam


if "each" in flags:
    os.makedirs(out, exist_ok=True)
    for f in files:
        clear()
        roots = load(f)
        cam = setup(False)
        pts = [o.matrix_world @ Vector(c) for o in scn.objects if o.type == 'MESH' for c in o.bound_box]
        lo = Vector((min(p.x for p in pts), 0, min(p.z for p in pts)))
        hi = Vector((max(p.x for p in pts), 0, max(p.z for p in pts)))
        w, h = (hi.x - lo.x) * 1.08, (hi.z - lo.z) * 1.04
        cam.location = ((lo.x + hi.x) / 2, -10, (lo.z + hi.z) / 2)
        cam.data.ortho_scale = max(w, h)
        scn.render.resolution_y = 900
        scn.render.resolution_x = max(64, int(900 * w / h))
        scn.render.filepath = os.path.join(out, os.path.basename(f)[:-4] + ".png")
        bpy.ops.render.render(write_still=True)
        bpy.data.objects.remove(cam)
    sys.exit(0)

clear()
per_row = (len(files) + 1) // 2
for i, f in enumerate(files):
    for o in load(f):
        o.location.x += 0.1 + (i % per_row - (per_row - 1) / 2) * 0.5
        o.location.z += 0.0 if i < per_row else -1.55
cam = setup("silhouette" in flags)
cam.data.ortho_scale = per_row * 0.5 + 0.5
cam.location = (0, -10, -0.2)
small = "small" in flags
scn.render.resolution_x = 1100 if small else 1800
scn.render.resolution_y = int(scn.render.resolution_x * 3.3 / (per_row * 0.5 + 0.5))
scn.render.filepath = out
bpy.ops.render.render(write_still=True)
