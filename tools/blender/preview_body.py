# Folha de conferência do corpo contínuo (body_mesh.py): parado (frente, lado, 3/4, costas) e em poses
# (corrida e agachado/braço erguido), para ver se ombro, quadril, joelho e cotovelo dobram sem quebrar.
# blender -b --factory-startup --python tools/blender/preview_body.py -- <prefixo_saida>
# Gera <prefixo>_rest.png, <prefixo>_run.png e <prefixo>_bend.png.
import bpy, sys, os, math
import numpy as np

out = sys.argv[sys.argv.index("--") + 1]
os.environ["ASSETS"] = "none"
here = os.path.dirname(os.path.abspath(__file__))
g = {"__file__": os.path.join(here, "build_assets.py"), "__name__": "preview_body"}
exec(open(g["__file__"], encoding="utf-8").read(), g)
scn = g["scn"]
rig, body = g["cb_character"]()

cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
scn.collection.objects.link(cam)
cam.data.type = 'ORTHO'
cam.data.ortho_scale = 2.05
cam.location = (0, -10, 0.95)
cam.rotation_euler = (math.radians(90), 0, 0)
scn.camera = cam
scn.render.engine = 'BLENDER_WORKBENCH'
sh = scn.display.shading
sh.light = 'STUDIO'
sh.color_type = 'MATERIAL'
sh.show_cavity = True
sh.cavity_type = 'BOTH'
sh.background_type = 'VIEWPORT'
sh.background_color = (0.95, 0.95, 0.95)
scn.view_settings.view_transform = 'Standard'
scn.render.resolution_x = 420
scn.render.resolution_y = 1000


def render(name, angs):
    tiles = []
    for ang in angs:
        rig.rotation_euler.z = ang
        f = out + "_tmp.png"
        scn.render.filepath = f
        bpy.ops.render.render(write_still=True)
        im = bpy.data.images.load(f, check_existing=False)
        tiles.append(np.array(im.pixels[:]).reshape(im.size[1], im.size[0], 4))
        bpy.data.images.remove(im)
    big = np.concatenate(tiles, axis=1)
    img = bpy.data.images.new("Sheet", big.shape[1], big.shape[0], alpha=True)
    img.pixels = big.ravel()
    img.filepath_raw = "%s_%s.png" % (out, name)
    img.file_format = 'PNG'
    img.save()
    rig.rotation_euler.z = 0
    os.remove(out + "_tmp.png")


def pose(**rots):
    for b in rig.pose.bones:
        b.rotation_mode = 'XYZ'
        b.rotation_euler = (rots.get(b.name, 0.0), 0, 0)


render("rest", (0.0, math.pi / 2, 0.75, math.pi))
# corrida: perna esquerda à frente (joelho levemente dobrado), direita atrás com o calcanhar subindo
pose(LegL=-0.75, KneeL=0.45, LegR=0.5, KneeR=1.2, ArmL=0.55, ElbowL=-0.6, ArmR=-0.6, ElbowR=-1.1)
render("run", (0.0, math.pi / 2, 0.75))
# coxa erguida e braço levantado para a frente: testa virilha e axila no limite
pose(LegL=-1.4, KneeL=1.6, ArmL=-1.3, ElbowL=-1.4, ArmR=0.4)
render("bend", (math.pi / 2, 0.75))
