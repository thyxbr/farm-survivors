# Junta a folha de conceito e os renders individuais (preview_weapons.py ... each) em pares lado a lado.
# python tools/blender/compare_weapons.py <conceito.png|webp> <pasta_renders> <saida.png>
import sys
from PIL import Image, ImageDraw
# recortes (x0, y0, x1, y1) de cada arma na folha de conceito 1080x1080, na ordem da folha
REF = [("w_rose_flame", (10, 0, 101, 528)), ("w_thorn_root", (175, 0, 256, 528)), ("w_crystal_frost", (268, 0, 435, 528)),
       ("w_azure_edge", (496, 0, 553, 528)), ("w_moon_crescent", (644, 0, 749, 528)), ("w_royal_wings", (765, 0, 941, 528)),
       ("w_venom_leaf", (967, 0, 1046, 528)), ("w_neon_edge", (1, 528, 87, 1080)), ("w_titan_cleaver", (125, 528, 208, 1080)),
       ("w_amber_fang", (252, 528, 320, 1080)), ("w_coral_spine", (335, 528, 471, 1080)), ("w_ivory_wing", (494, 528, 619, 1080)),
       ("w_scarlet_talon", (658, 528, 787, 1080)), ("w_crimson_reed", (834, 528, 892, 1080)), ("w_pale_crescent", (888, 528, 1080, 1080))]
src, folder, out = sys.argv[1:4]
ref = Image.open(src).convert("RGB")
H = 420
pairs = []
for name, box in REF:
    a = ref.crop(box)
    bb = Image.eval(a, lambda v: 255 - v).getbbox()   # apara o branco
    a = a.crop(bb) if bb else a
    b = Image.open(f"{folder}/{name}.png").convert("RGB")
    bb = Image.eval(b, lambda v: 255 - v).getbbox()
    b = b.crop(bb) if bb else b
    a = a.resize((max(1, a.width * H // a.height), H))
    b = b.resize((max(1, b.width * H // b.height), H))
    pairs.append((name, a, b))
cols = 5
cw = max(p[1].width + p[2].width for p in pairs) + 40
rows = (len(pairs) + cols - 1) // cols
img = Image.new("RGB", (cw * cols, rows * (H + 40)), "white")
d = ImageDraw.Draw(img)
for i, (name, a, b) in enumerate(pairs):
    x, y = (i % cols) * cw + 10, (i // cols) * (H + 40) + 26
    d.text((x, y - 20), name[2:] + "  (exemplo | jogo)", fill=(60, 60, 60))
    img.paste(a, (x, y))
    img.paste(b, (x + a.width + 14, y))
img.save(out)
