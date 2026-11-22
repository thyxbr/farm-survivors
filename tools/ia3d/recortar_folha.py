"""Recorta uma folha de conceito em vistas para o gerador (frente.png, lado.png, costas.png por peça).

  python tools/ia3d/recortar_folha.py <folha.png|webp> <peça>[,<peça>...] [--saida D:/ia3d/vistas] [--colunas frente,lado,costas]

A folha tem uma linha por peça (de cima para baixo, na ordem dos nomes) e uma coluna por vista. As faixas de
linhas e colunas são achadas sozinhas pelo fundo liso (cor do canto). Cada célula vira um quadrado de 1024 px com
o mesmo fundo e margem. Uma imagem só com uma peça e três vistas lado a lado é uma folha de uma linha.
Confira o resultado em <saida>/recortes_folha.png antes de gerar: faixa errada = peça cortada no meio.
"""
import argparse
import os

import numpy as np
from PIL import Image

ap = argparse.ArgumentParser()
ap.add_argument("folha")
ap.add_argument("pecas")
ap.add_argument("--saida", default=os.path.join(os.environ.get("IA3D", "D:/ia3d"), "vistas"))
ap.add_argument("--colunas", default="frente,lado,costas")
ap.add_argument("--lado", type=int, default=1024)
a = ap.parse_args()

im = Image.open(a.folha).convert("RGB")
px = np.asarray(im).astype(int)
fundo = px[3, 3]
cheio = np.abs(px - fundo).sum(2) > 40


def faixas(v, n):
    """As n faixas com conteúdo (as maiores, se o ruído criar faixas a mais), em ordem."""
    r, s = [], None
    for i, x in enumerate(list(v) + [False]):
        if x and s is None:
            s = i
        if not x and s is not None:
            r.append((s, i))
            s = None
    r = sorted(sorted(r, key=lambda f: f[1] - f[0], reverse=True)[:n])
    if len(r) != n:
        raise SystemExit("achei %d faixas, esperava %d: confira a folha ou o número de peças/vistas" % (len(r), n))
    return r


pecas = a.pecas.split(",")
cols = a.colunas.split(",")
linhas = faixas(cheio.any(1), len(pecas))
for nome, (y0, y1) in zip(pecas, linhas):
    # colunas medidas só dentro da linha: cada peça tem a sua largura
    colunas = faixas(cheio[y0:y1].any(0), len(cols))
    os.makedirs(os.path.join(a.saida, nome), exist_ok=True)
    for vista, (x0, x1) in zip(cols, colunas):
        c = im.crop((max(0, x0 - 8), max(0, y0 - 8), min(im.width, x1 + 8), min(im.height, y1 + 8)))
        lado = int(max(c.size) * 1.15)
        q = Image.new("RGB", (lado, lado), tuple(int(v) for v in fundo))
        q.paste(c, ((lado - c.width) // 2, (lado - c.height) // 2))
        q.resize((a.lado, a.lado), Image.LANCZOS).save(os.path.join(a.saida, nome, vista + ".png"))
    print("OK", nome, "linha %d..%d" % (y0, y1), "colunas", colunas)

W = Image.new("RGB", (256 * len(cols), 256 * len(pecas)), "white")
for i, nome in enumerate(pecas):
    for j, vista in enumerate(cols):
        W.paste(Image.open(os.path.join(a.saida, nome, vista + ".png")).resize((256, 256)), (256 * j, 256 * i))
W.save(os.path.join(a.saida, "recortes_folha.png"))
print("CONFERIR", os.path.join(a.saida, "recortes_folha.png"))
