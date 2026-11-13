# Monta a folha de comparação do rosto (requer Pillow).
# python tools/face_sheet.py <render.png> <queixo_z> <altura_cabeca> <referencia.png> <folha.png>
# Desenha as linhas de proporção de um rosto humano adulto sobre o render (câmera de face_compare.py)
# e coloca os rostos de referência ao lado.
import sys
from PIL import Image, ImageDraw

render, chin, H, ref, out = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), sys.argv[4], sys.argv[5]
PX = 1800 / 0.9            # px por metro (ortho 0,9 m em 1800 px)
im = Image.open(render).convert("RGB")
cy = im.height / 2         # centro da imagem = queixo + H/2


def zpx(frac):
    return cy - (frac - 0.5) * H * PX


# frações da altura queixo->topo do crânio (cânone de Loomis para adulto)
GUIDES = [(1.0, "topo do crânio"), (0.78, "linha do cabelo"), (0.57, "sobrancelhas"), (0.5, "olhos"),
          (0.28, "base do nariz"), (0.2, "boca"), (0.0, "queixo")]
d = ImageDraw.Draw(im)
for frac, label in GUIDES:
    y = zpx(frac)
    d.line([(0, y), (im.width, y)], fill=(90, 200, 255), width=1)
    d.text((6, y - 12), label, fill=(150, 220, 255))
# largura ideal do rosto nas maçãs (~0,62 H) na vista frontal
fx = im.width / 2 - 0.3 * PX     # vista frontal fica 0,3 m à esquerda do centro
hw = 0.31 * H * PX
for x in (fx - hw, fx + hw):
    d.line([(x, zpx(0.15)), (x, zpx(0.75))], fill=(255, 170, 60), width=1)
d.text((fx - hw, zpx(0.75) - 14), "largura ideal (0,62 H)", fill=(255, 190, 90))

r = Image.open(ref).convert("RGB")
r = r.resize((int(r.width * im.height / r.height), im.height), Image.LANCZOS)
sheet = Image.new("RGB", (r.width + im.width, im.height), (20, 20, 22))
sheet.paste(r, (0, 0))
sheet.paste(im, (r.width, 0))
ImageDraw.Draw(sheet).text((8, 8), "REFERÊNCIA", fill=(255, 255, 255))
ImageDraw.Draw(sheet).text((r.width + 8, im.height - 18), "MODELO (frente | 3/4 | perfil)", fill=(255, 255, 255))
sheet.save(out)
