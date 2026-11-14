# Folha de conferência das construções da Defesa da Cidade: níveis 1, 2 e 3 lado a lado, em 3/4 pela frente.
# blender -b --factory-startup --python tools/blender/preview_buildings.py -- <tipo> <saida.png> [back]
import bpy, sys, math, os
D = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "buildings")).replace("\\", "/") + "/"
args = sys.argv[sys.argv.index("--") + 1:]
kind, out = args[0], args[1]
back = "back" in args[2:]
TURRET = {"archer_tower": ("archer_turret", lambda lv: 4.0 + 0.4 * (lv - 1)),
          "cannon_tower": ("cannon_turret", lambda lv: 3.0 + 0.3 * (lv - 1)),
          "mage_tower": ("mage_turret", lambda lv: 5.0 + 0.4 * (lv - 1) + 2.8)}
SPAN = {"town_hall": 9.0, "farm": 8.0, "barracks": 7.6, "market": 6.4}.get(kind, 5.2)
scn = bpy.context.scene
for o in list(scn.objects):
    bpy.data.objects.remove(o)


def imp(path, dx, z=0.0):
    before = set(scn.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    tris = 0
    for o in set(scn.objects) - before:
        if o.type == 'MESH':
            o.data.calc_loop_triangles()
            tris += len(o.data.loop_triangles)
        if o.parent is None:
            o.location.x += dx
            o.location.z += z
            if back:
                o.rotation_mode = 'XYZ'
                o.rotation_euler.z += math.pi
    return tris


top = 0.0
for lv in (1, 2, 3):
    dx = (lv - 2) * SPAN
    t = imp(D + "%s_%d.glb" % (kind, lv), dx)
    if kind in TURRET:
        name, h = TURRET[kind]
        t += imp(D + "%s_%d.glb" % (name, lv), dx, h(lv))
    print("TRIS", kind, lv, t, flush=True)
for o in scn.objects:
    if o.type == 'MESH':
        top = max(top, max((o.matrix_world @ v.co).z for v in o.data.vertices))
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
scn.collection.objects.link(cam)
cam.data.type = 'ORTHO'
cam.data.ortho_scale = SPAN * 3.3
yaw = math.radians(-28)
dist = 40
cam.location = (math.sin(yaw) * dist, -math.cos(yaw) * dist, top * 0.45 + dist * math.tan(math.radians(22)))
cam.rotation_euler = (math.radians(68), 0, yaw)
scn.camera = cam
scn.render.engine = 'BLENDER_WORKBENCH'
sh = scn.display.shading
sh.light = 'STUDIO'
sh.color_type = 'MATERIAL'
sh.show_shadows = True
sh.show_cavity = True
sh.cavity_type = 'BOTH'
sh.background_type = 'VIEWPORT'
sh.background_color = (0.32, 0.4, 0.3)
scn.view_settings.view_transform = 'Standard'
scn.render.resolution_x = 1500
scn.render.resolution_y = 760
scn.render.filepath = out
bpy.ops.render.render(write_still=True)
