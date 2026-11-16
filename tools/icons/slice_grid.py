"""Recorta uma grade de ícones pintados (fundo branco) em PNGs com transparência.

Uso: python -X utf8 tools/icons/slice_grid.py <grade.png> <id1,id2,...> [--out assets/ui/items] [--size 256]

Um id "-" pula aquele objeto (ex.: o Gemini repetiu um item). O fundo branco ligado à borda vira
transparente (color-to-alpha, então fumaça e brilho ficam translúcidos); o branco dentro do contorno
do objeto (brilho no vidro, linha do carretel) continua opaco. Os objetos são achados pelas faixas
de linhas e colunas que não são fundo, então a grade não precisa estar alinhada, só com branco entre
os objetos. A ordem é esquerda→direita, de cima para baixo.
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image

NEAR_WHITE = 200     # menor canal acima disso conta como possível fundo
SOLID = 0.12         # alfa mínimo para o pixel contar como objeto ao achar as faixas
GAP = 12             # faixa vazia mínima (px) entre dois objetos


def background_mask(rgb: np.ndarray) -> np.ndarray:
    """Pixels quase brancos ligados à borda da imagem (preenchimento a partir da borda)."""
    near = rgb.min(axis=2) > NEAR_WHITE
    bg = np.zeros_like(near)
    bg[0, :], bg[-1, :], bg[:, 0], bg[:, -1] = near[0, :], near[-1, :], near[:, 0], near[:, -1]
    while True:
        grow = bg.copy()
        grow[1:, :] |= bg[:-1, :]
        grow[:-1, :] |= bg[1:, :]
        grow[:, 1:] |= bg[:, :-1]
        grow[:, :-1] |= bg[:, 1:]
        grow &= near
        if (grow == bg).all():
            return bg
        bg = grow


def to_rgba(rgb: np.ndarray) -> np.ndarray:
    """Tira o branco do fundo: alfa = quanto o pixel se afasta do branco, cor desmisturada do branco."""
    f = rgb.astype(np.float32) / 255.0
    bg = background_mask(rgb)
    a = np.ones(f.shape[:2], np.float32)
    a_bg = (1.0 - f).max(axis=2)
    a[bg] = a_bg[bg]
    safe = np.maximum(a, 1e-4)[..., None]
    col = np.where(bg[..., None], (f - (1.0 - safe)) / safe, f)
    out = np.dstack([np.clip(col, 0, 1), a])
    out[a < 0.02] = 0
    return (out * 255 + 0.5).astype(np.uint8)


def bands(profile: np.ndarray) -> list:
    """Intervalos [ini, fim) onde o perfil tem objeto, juntando buracos menores que GAP."""
    on = np.flatnonzero(profile)
    if on.size == 0:
        return []
    out = [[on[0], on[0] + 1]]
    for i in on[1:]:
        if i - out[-1][1] < GAP:
            out[-1][1] = i + 1
        else:
            out.append([i, i + 1])
    return [(a, b) for a, b in out if b - a > 24]   # descarta poeira solta


def objects(rgba: np.ndarray) -> list:
    solid = rgba[..., 3] > SOLID * 255
    found = []
    for y0, y1 in bands(solid.any(axis=1)):
        row = solid[y0:y1]
        for x0, x1 in bands(row.any(axis=0)):
            cell = solid[y0:y1, x0:x1]
            ys = np.flatnonzero(cell.any(axis=1))
            found.append((x0, y0 + ys[0], x1, y0 + ys[-1] + 1))
    return found


def square(img: Image.Image, size: int, margin: float = 0.04) -> Image.Image:
    w, h = img.size
    side = int(max(w, h) / (1.0 - 2 * margin))
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, ((side - w) // 2, (side - h) // 2))
    return canvas.resize((size, size), Image.LANCZOS)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("grid")
    ap.add_argument("ids")
    ap.add_argument("--out", default="assets/ui/items")
    ap.add_argument("--size", type=int, default=256)
    args = ap.parse_args()
    ids = [s.strip() for s in args.ids.split(",")]
    rgb = np.asarray(Image.open(args.grid).convert("RGB"))
    rgba = to_rgba(rgb)
    boxes = objects(rgba)
    if len(boxes) != len(ids):
        print("ERRO: %s tem %d objetos, mas vieram %d ids" % (args.grid, len(boxes), len(ids)))
        for b in boxes:
            print("  objeto em", b)
        return 1
    os.makedirs(args.out, exist_ok=True)
    for id_, (x0, y0, x1, y1) in zip(ids, boxes):
        if id_ == "-":
            continue
        icon = square(Image.fromarray(rgba[y0:y1, x0:x1], "RGBA"), args.size)
        icon.save(os.path.join(args.out, id_ + ".png"))
        print("%-16s %4dx%-4d de (%d,%d)" % (id_, x1 - x0, y1 - y0, x0, y0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
