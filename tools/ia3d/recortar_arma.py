"""Recorta uma folha de arma deitada (frente em cima, costas embaixo, ponta para a direita) em vistas de pé.

  python tools/ia3d/recortar_arma.py <folha.png|jpg> <peça> [--saida D:/ia3d/vistas] [--ponta direita|esquerda]

O Gemini desenha bem a arma deitada (usa a largura da imagem), mas o gerador quer a arma de pé: cada linha é
girada para a ponta ficar em cima. A linha de baixo (costas) vem desenhada igual à de cima, como se a arma
tivesse girado no próprio eixo; para o gerador, as costas são vistas de trás (esquerda e direita trocadas), então
a vista de costas é espelhada. Não há vista de lado: a lâmina é fina e o Gemini não a desenha certo.
Sai <saida>/<peça>/frente.png e costas.png (1024 px, fundo da folha) e uma prévia <saida>/<peça>/recorte.png.
"""
import argparse
import os

import numpy as np
from PIL import Image, ImageOps

ap = argparse.ArgumentParser()
ap.add_argument("folha")
ap.add_argument("peca")
ap.add_argument("--saida", default=os.path.join(os.environ.get("IA3D", "D:/ia3d"), "vistas"))
ap.add_argument("--ponta", default="direita")
ap.add_argument("--lado", type=int, default=1024)
a = ap.parse_args()

im = Image.open(a.folha).convert("RGB")
px = np.asarray(im).astype(int)
fundo = px[3, 3]
cheio = np.abs(px - fundo).sum(2) > 40


def faixas(v, n, minimo=20):
    r, s = [], None
    for i, x in enumerate(list(v) + [False]):
        if x and s is None:
            s = i
        if not x and s is not None:
            if i - s >= minimo:
                r.append((s, i))
            s = None
    r = sorted(sorted(r, key=lambda f: f[1] - f[0], reverse=True)[:n])
    if len(r) != n:
        raise SystemExit("achei %d faixas, esperava %d" % (len(r), n))
    return r


linhas = faixas(cheio.any(1), 2)
out = os.path.join(a.saida, a.peca)
os.makedirs(out, exist_ok=True)
prev = []
for vista, (y0, y1) in zip(("frente", "costas"), linhas):
    xs = np.where(cheio[y0:y1].any(0))[0]
    c = im.crop((max(0, xs[0] - 8), max(0, y0 - 8), min(im.width, xs[-1] + 9), min(im.height, y1 + 8)))
    # ponta para cima: ponta à direita gira 90° no sentido anti-horário
    c = c.rotate(90 if a.ponta == "direita" else -90, expand=True)
    if vista == "costas":
        c = ImageOps.mirror(c)
    lado = int(max(c.size) * 1.08)
    q = Image.new("RGB", (lado, lado), tuple(int(v) for v in fundo))
    q.paste(c, ((lado - c.width) // 2, (lado - c.height) // 2))
    q = q.resize((a.lado, a.lado), Image.LANCZOS)
    q.save(os.path.join(out, vista + ".png"))
    prev.append(q.resize((384, 384)))
W = Image.new("RGB", (768, 384), "white")
for i, p in enumerate(prev):
    W.paste(p, (384 * i, 0))
W.save(os.path.join(out, "recorte.png"))
print("OK", a.peca, "linhas", linhas)
